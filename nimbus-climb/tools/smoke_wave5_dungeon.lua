-- smoke_wave5_dungeon.lua: wave 5 dungeon lane (bugs #26 and #15; .superpowers/bugs-2026-10-24/wave5-dungeon-spec.md).
-- Loaded by tools/smoke.py in BOTH worlds; ARGS.context picks the half.
--
-- server (booted, before "shutdown"):
--   w5dgn_enter           a SOLO start sends DungeonState("Enter", { Cover 0.55, Reveal 0.9, Element, Floor, Name }) BEFORE
--                         any teleport (still at the gate, Transit lock on, no Run payload, Dg.confirm -> "Transit"); after
--                         Cover the member stands on the hall pad, Transit off, ONE Run payload, Joined set; a party of 3
--                         through Start gets three Enters, a member who disconnects during the cover is dropped and the rest
--                         are teleported; an endRun during the cover: finishEnter refuses, nobody teleported
--   w5dgn_walkin_timeout  room 1 entered, nobody crosses: still Corridor at +2.9 s, the fight starts by +3.6 s (WALK_IN_TIMEOUT
--                         3, not 30); the member left in the corridor is placed inside the Threshold box, the member who
--                         already walked into the room keeps the exact spot (no yank to the Entrance); MaxRunSeconds shrank
--   w5dgn_infight         InFight nil in the Hall / the corridor, true for every team member from startFight, nil after the
--                         clear, true again in room 2, nil for a leaver while the other keeps true, nil after a Timeout
--                         endRun; InBattle stays the run id throughout and is released by finishRun
--   w5dgn_crossing        a crossing at +1.3 s starts the fight at once (well before the 3 s timeout); the wave arrival is
--                         still BattleCatalog.Fighter.ArriveSeconds 1.2 (the summon flash)
-- client:
--   client_w5dgn_walkin   the walk-in under the fade: Scriptable camera inside the room in front of the character (9 studs past
--                         the Threshold, 3.5 up, looking at it, FOV 60), MoveTo into the Threshold box, "Here we go!",
--                         Cinematic; after the walk + blend: Custom, FOV 70, controls back; a game-processed click does not
--                         skip, a free click skips (the character at the Threshold), the sink key skips, a Fight payload
--                         hands back within 0.45 s, End clears at once, no room model = no walk-in, a lost RenderStep is
--                         cleared by the light loop; the lane / end point come from where the root stands at the fade-in
--                         (a Run payload that beat the teleport); Shake OFF: the walk-in shot still moves (player ruling
--                         2026-10-28: the setting turns off only the hit shakes)
--   client_w5dgn_enter    the voxel entrance: 16 x 9 cells on 1920 x 1080 (DisplayOrder 26), the camera rush (Scriptable ->
--                         Custom by the cover), every cell full by 0.45 (Cover 0.55 - ENTER_MARGIN), no Workspace walk to find
--                         the gate, the fresh Run makes them fall, the gui off by 0.95; 9 x 16 on a portrait phone, End during
--                         the cover clears at once; Low = 8 x 5 and a click in the reveal hides at once; no Run: reveal at 3 s
--                         and clear; Shake OFF: the rush still plays (ruling 2026-10-28); a camera > 60 studs from the gate:
--                         no rush, the blocks still cover
--   client_w5pets_follow  InBattle = a run id with no InFight: the followers show; InFight true parks them; InFight nil keeps
--                         them parked 0.5 s, shows them by 1.1 s, the fighter-key pet starting where BattleController last
--                         drew it; InBattle = a battle id still parks (regression)
--   client_w5dgn_camera   the dungeon shoulder offset on the run's Run payload, kept through a shake (AttackFx punch), zero
--                         on End; in a dungeon battle a 5 % hit on my fighter shakes once and a big punch (0.25) opens the
--                         FOV and lets it go within 0.3 s; Shake OFF: no shake but the FOV punch still plays (ruling
--                         2026-10-28); a raid: no light shake, no FOV punch
-- Plain Lua 5.1 syntax only.

local CONTEXT = (ARGS and ARGS.context) or "server"

----------------------------------------------------------------------------------------------------
-- server world
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local K = _G.K
	local T = K.T
	local advance = K.advance
	local S = {}
	local seq = 0
	local STRONG = { "cloudy_dragon", "ember_phoenix", "aurora_fox" }

	local function req(path)
		local inst = K.moduleInstance(path)
		if not inst then
			return nil
		end
		local ok, m = pcall(require, inst)
		return (ok and type(m) == "table") and m or nil
	end
	local function BS() return req("server/Services/BattleService") end
	local function DS() return req("server/Services/DataService") end
	local function BC() return req("shared/BattleCatalog") end
	local function DGS() return req("server/Services/DungeonService") end
	local function DGB() return req("server/Services/DungeonBuilder") end
	local function info()
		local db = DGB()
		return db and db.GetInfo and db.GetInfo() or nil
	end
	local function remote(name)
		local folder = K.remoteFolder()
		return folder and folder:FindFirstChild(name) or nil
	end

	local function ready(label)
		if not K.needBoot() then
			return false
		end
		if not DGS() or not DGB() or not BS() or not BC() or not info() or not remote("DungeonRequest") then
			T.fail(label .. ": skipped, the dungeon services did not load")
			return false
		end
		if type(DGS().Dg.finishEnter) ~= "function" then
			T.fail(label .. ": DungeonService has no Dg.finishEnter (wave 5 entrance not implemented)")
			return false
		end
		return true
	end

	local function newPlayer(prefix, level)
		seq = seq + 1
		local p = Mock.AddPlayer(prefix .. seq, 975700 + seq)
		advance(1.0)
		local data = DS()
		local prof = data.GetProfile(p)
		if prof then
			for _, id in ipairs(STRONG) do
				prof.Pets[id] = (prof.Pets[id] or 0) + 1
				prof.PetLevels[id] = { Level = level or 20, Xp = 0 }
			end
			data.MarkDirty(p)
			data.SetTeam(p, 1, STRONG)
		end
		return p
	end

	local function toPad(p, dx)
		local i = info()
		local pad = i and (i.Pad or i.PromptPart)
		if pad then
			Mock.Teleport(p, CFrame.new(pad.Position + Vector3.new(dx or 0, 3.5, 0)))
		end
		advance(0.05)
	end

	local function request(p, action, a)
		Mock.FromClient(remote("DungeonRequest"), p, action, a)
		advance(0.05)
	end

	local function runOf(p)
		return DGS().St.runOf[p]
	end

	local function msgs(p, mark, kind)
		local out = {}
		for _, e in ipairs(K.remotesFor("DungeonState", p.UserId, mark or 0)) do
			if kind == nil or e.args[1] == kind then
				out[#out + 1] = e.args[2]
			end
		end
		return out
	end

	local function pos(p)
		local r = K.root(p)
		return r and r.Position or Vector3.new(0, 0, 0)
	end

	local function cleanup(list)
		local dgs = DGS()
		for _, p in ipairs(list) do
			if p.Parent and dgs and dgs.St.runOf[p] then
				pcall(dgs.Quit, p)
			end
			if p.Parent and dgs and dgs.St.partyOf[p] then
				pcall(dgs.LeaveParty, p)
			end
		end
		advance(5.5)
		local live = {}
		for _, p in ipairs(list) do
			if p.Parent then
				live[#live + 1] = p
			end
		end
		K.removePlayers(live)
		advance(1)
	end

	local function scenario(name, fn)
		return K.guarded(name, function()
			local dgs = DGS()
			local saved = dgs and dgs.Dg.enterRoom
			local ok, err = pcall(fn)
			if dgs and saved then
				dgs.Dg.enterRoom = saved
			end
			if not ok then
				error(err, 0)
			end
		end)
	end

	local function members(run)
		local out = {}
		for _, uid in ipairs(run.Order) do
			local m = run.Members[uid]
			if m and not m.Left then
				out[#out + 1] = m.Player
			end
		end
		return out
	end

	local function doorOf(run)
		local dg = DGS().Dg
		local t0 = Mock.Clock.now
		local prompt = dg.nextDoor(run)
		while not prompt and run.State ~= "Ending" and Mock.Clock.now - t0 < 6 do
			advance(0.25)
			prompt = dg.nextDoor(run)
		end
		return prompt
	end

	-- every member presses E at the open door; returns the mock time Dg.enterRoom ran (nil = no room change)
	local function pressAll(run)
		local dg = DGS().Dg
		local prompt = doorOf(run)
		if not prompt then
			return nil
		end
		local real = dg.enterRoom
		local at = nil
		dg.enterRoom = function(r, room)
			at = at or Mock.Clock.now
			return real(r, room)
		end
		for _, p in ipairs(members(run)) do
			Mock.Teleport(p, CFrame.new(prompt.Parent.Position + Vector3.new(1, 0, 0)))
			Mock.Trigger(prompt, p)
		end
		advance(0.55)
		dg.enterRoom = real
		return at
	end

	local function battleOf(battleId)
		local f = BS().IsInBattle
		for i = 1, 80 do
			local name, v = debug.getupvalue(f, i)
			if not name then
				break
			end
			if name == "St" and type(v) == "table" and type(v.battles) == "table" then
				return v.battles[battleId]
			end
		end
		return nil
	end

	local function crossThreshold(run, p)
		local ri = run.Pocket.Rooms[run.Room]
		if ri and ri.Threshold then
			Mock.Teleport(p, CFrame.new(ri.Threshold.Position))
		end
		advance(0.6)
	end

	local function clearRoom(run, p, seconds)
		local t0 = Mock.Clock.now
		while run.State == "Fight" and Mock.Clock.now - t0 < (seconds or 60) do
			local b = battleOf(run.Battle)
			local sim = b and b.Sim
			local team = sim and sim.teamByOwner and sim.teamByOwner[p.UserId]
			local f = team and team.fighter
			local target = nil
			for _, u in ipairs(sim and sim.units or {}) do
				if u.side == 2 and u.alive then
					u.hp = math.min(u.hp, 0.01)
					target = target or u
				end
			end
			if f and target and b.Zone then
				f.x, f.z = target.x - 1, target.z
				f.nextAttack = 0
				Mock.Teleport(p, CFrame.new(b.Zone.CFrame:PointToWorldSpace(Vector3.new(target.x - 1, 3, target.z))))
				pcall(BS().Command, p, "Attack", target.id)
			end
			advance(0.1)
		end
		advance(0.3)
		return run.State == "Corridor" or run.State == "Treasure"
	end

	-- a party of n through Create / Join / Ready / Start; returns players, the run (the instant it begins), the log mark
	local function party(n, prefix)
		local ps = {}
		for i = 1, n do
			ps[i] = newPlayer(prefix, 20)
			toPad(ps[i], i)
		end
		request(ps[1], "Create", 1)
		for i = 2, n do
			request(ps[i], "Join", ps[1].UserId)
			request(ps[i], "Ready", true)
			advance(0.4)
		end
		local mark = K.logSize()
		request(ps[1], "Start")
		local t0 = Mock.Clock.now
		while not runOf(ps[1]) and Mock.Clock.now - t0 < 8 do
			advance(0.05)
		end
		return ps, runOf(ps[1]), mark
	end

	local function attr(p, name)
		return p:GetAttribute(name)
	end

	------------------------------------------------------------------------------------------------
	S.w5dgn_enter = scenario("w5dgn_enter", function()
		if not ready("w5dgn_enter") then
			return
		end
		local dgs = DGS()
		local p = newPlayer("W5Ent", 20)
		toPad(p)
		local at0 = pos(p)
		local mark = K.logSize()
		request(p, "Solo", 1)
		local run = runOf(p)
		if not T.check(run ~= nil and run.State == "Hall", "w5 enter: (setup) a solo run begins") then
			cleanup({ p })
			return
		end
		local enters = msgs(p, mark, "Enter")
		local e = enters[1]
		T.check(#enters == 1 and e and e.Cover == 0.55 and e.Reveal == 0.9 and e.Element == run.Element and e.Floor == 1 and e.Name == run.Name,
			"w5 enter: DungeonState('Enter', { Cover 0.55, Reveal 0.9, Element, Floor 1, Name }) once", tostring(#enters))
		T.check((pos(p) - at0).Magnitude < 0.5, "w5 enter: positions unchanged before Cover (still at the gate under the cover)",
			string.format("moved %.1f studs", (pos(p) - at0).Magnitude))
		T.check(run.Transit == true and #msgs(p, mark, "Run") == 0, "w5 enter: the Transit lock is on and no Run payload went out yet")
		local okC, whyC = dgs.Dg.confirm(run, p, run.Pocket.Hall.NextPrompt)
		T.check(okC == false and whyC == "Transit", "w5 enter: an E press during the cover is refused ('Transit')", tostring(whyC))
		advance(0.6)
		local hall = run.Pocket.Hall
		T.check(not run.Transit and hall and (pos(p) - hall.Spawns[1].Position).Magnitude < 4, "w5 enter: after Cover the member stands on the hall pad, Transit off")
		local runs = msgs(p, mark, "Run")
		T.check(#runs == 1 and runs[1].State == "Hall" and runs[1].RunId == run.Id, "w5 enter: exactly one Run payload after the teleport", tostring(#runs))
		T.check(run.Members[p.UserId].Joined ~= nil, "w5 enter: Joined is stamped at the teleport (the FAR grace)")
		cleanup({ p })

		-- a party of 3 through Start: three Enters; a member gone during the cover is dropped, the rest teleported
		local ps, prun, pmark = party(3, "W5EntP")
		if T.check(prun ~= nil and prun.Transit == true and #members(prun) == 3, "w5 enter: (setup) a party of 3 starts, in its cover") then
			local n = 0
			for _, q in ipairs(ps) do
				n = n + #msgs(q, pmark, "Enter")
			end
			T.eq(n, 3, "w5 enter: each of the 3 members got one Enter")
			K.removePlayers({ ps[3] })
			advance(0.8)
			local inHall = true
			for i = 1, 2 do
				if (pos(ps[i]) - prun.Pocket.Hall.Center).Magnitude > 30 then
					inHall = false
				end
			end
			T.check(inHall and prun.Members[ps[3].UserId].Left == true and prun.State == "Hall", "w5 enter: the member who disconnected in the cover is Left, the other two are in the hall")
		end
		cleanup({ ps[1], ps[2] })

		-- an endRun during the cover: finishEnter refuses, nobody teleported
		local q = newPlayer("W5EntE", 20)
		toPad(q)
		local q0 = pos(q)
		request(q, "Solo", 1)
		local qrun = runOf(q)
		if T.check(qrun ~= nil and qrun.Transit == true, "w5 enter: (setup) a second solo run in its cover") then
			local seqNow = qrun.TransitSeq
			dgs.Dg.endRun(qrun, false, "Error")
			advance(0.6)
			T.check(dgs.Dg.finishEnter(qrun, seqNow) == false and (pos(q) - q0).Magnitude < 0.5, "w5 enter: endRun during the cover: finishEnter returns false, nobody teleported")
		end
		cleanup({ q })
	end)

	------------------------------------------------------------------------------------------------
	S.w5dgn_walkin_timeout = scenario("w5dgn_walkin_timeout", function()
		if not ready("w5dgn_walkin_timeout") then
			return
		end
		local dgs = DGS()
		local ps, run = party(2, "W5Walk")
		local a, b = ps[1], ps[2]
		if not T.check(run ~= nil, "w5 walk-in: (setup) a party of 2") then
			cleanup(ps)
			return
		end
		advance(0.7)
		local enteredAt = pressAll(run)
		if not T.check(enteredAt ~= nil and run.Room == 1 and run.Phase == "Threshold", "w5 walk-in: (setup) room 1 entered") then
			cleanup(ps)
			return
		end
		local ri = run.Pocket.Rooms[1]
		-- a: back in the corridor (outside the room's Zone); b: inside the room, not on the Threshold
		local back = (ri.Threshold.Position - ri.Entrance.Position)
		back = Vector3.new(back.X, 0, back.Z).Unit
		Mock.Teleport(a, CFrame.new(ri.Entrance.Position - back * 9))
		local bSpot = ri.ZoneFloor.Position + Vector3.new(4, 3, 4)
		Mock.Teleport(b, CFrame.new(bSpot))
		advance(0.05)
		T.check(not dgs.Dg.insideBox(ri.Zone, pos(a)) and dgs.Dg.insideBox(ri.Zone, pos(b)) and not dgs.Dg.insideBox(ri.Threshold, pos(b)),
			"w5 walk-in: (setup) one member in the corridor, one inside the room off the Threshold")
		local bAt = pos(b)
		while Mock.Clock.now - enteredAt < 2.9 do
			advance(0.05)
		end
		T.check(run.State == "Corridor" and run.Phase == "Threshold", "w5 walk-in: nobody crossed: still waiting at +2.9 s", tostring(run.State))
		while run.State == "Corridor" and Mock.Clock.now - enteredAt < 6 do
			advance(0.05)
		end
		local took = Mock.Clock.now - enteredAt
		T.check(run.State == "Fight" and took >= 2.95 and took <= 3.6, "w5 walk-in: the fight starts by itself 3 s after the room was entered (WALK_IN_TIMEOUT)", string.format("%.2f s", took))
		T.check(dgs.Dg.insideBox(ri.Threshold, pos(a)), "w5 walk-in: the member left in the corridor is placed inside the Threshold box")
		T.check((pos(b) - bAt).Magnitude < 0.05, "w5 walk-in: no yank: the member inside the room keeps the exact spot", string.format("moved %.2f", (pos(b) - bAt).Magnitude))
		local old = 4 * 180 + 4 * (30 + (BC().Dungeon.Intermission or 2)) + 5 * (180 + 1.25) + (BC().Dungeon.TreasureSeconds or 45) + 120
		T.check(dgs.MaxRunSeconds(1) < old, "w5 walk-in: MaxRunSeconds(1) shrank with the walk-in timeout", tostring(dgs.MaxRunSeconds(1)) .. " < " .. tostring(old))
		cleanup(ps)
	end)

	------------------------------------------------------------------------------------------------
	S.w5dgn_infight = scenario("w5dgn_infight", function()
		if not ready("w5dgn_infight") then
			return
		end
		local dgs = DGS()
		local ps, run = party(2, "W5Fight")
		local a, b = ps[1], ps[2]
		if not T.check(run ~= nil, "w5 infight: (setup) a party of 2") then
			cleanup(ps)
			return
		end
		advance(0.7)
		T.check(attr(a, "InFight") == nil and attr(b, "InFight") == nil and attr(a, "InBattle") == run.Id, "w5 infight: InFight nil in the Hall, InBattle = the run id")
		pressAll(run)
		T.check(run.Phase == "Threshold" and attr(a, "InFight") == nil, "w5 infight: InFight nil in the room before the fight")
		crossThreshold(run, a)
		T.check(run.State == "Fight" and attr(a, "InFight") == true and attr(b, "InFight") == true, "w5 infight: InFight true for every team member from startFight")
		T.check(clearRoom(run, a, 60) and run.Phase == "Walk", "w5 infight: (setup) room 1 cleared", tostring(run.State))
		T.check(attr(a, "InFight") == nil and attr(b, "InFight") == nil and attr(a, "InBattle") == run.Id, "w5 infight: nil after the clear (the followers come back), InBattle unchanged")
		pressAll(run)
		crossThreshold(run, a)
		T.check(run.State == "Fight" and run.Room == 2 and attr(a, "InFight") == true, "w5 infight: true again in room 2")
		request(b, "Quit")
		advance(0.2)
		T.check(attr(b, "InFight") == nil and attr(a, "InFight") == true, "w5 infight: the leaver's InFight is cleared, the other keeps true")
		dgs.Dg.endRun(run, false, "Timeout")
		advance(0.1)
		T.check(attr(a, "InFight") == nil and attr(a, "InBattle") == run.Id, "w5 infight: nil after a Timeout endRun (InBattle until the return)")
		advance(5)
		T.check(attr(a, "InFight") == nil and attr(a, "InBattle") == nil, "w5 infight: finishRun releases InBattle; InFight stays nil")
		cleanup(ps)
	end)

	------------------------------------------------------------------------------------------------
	S.w5dgn_crossing = scenario("w5dgn_crossing", function()
		if not ready("w5dgn_crossing") then
			return
		end
		local p = newPlayer("W5Cross", 20)
		toPad(p)
		request(p, "Solo", 1)
		local run = runOf(p)
		advance(0.7)
		local enteredAt = run and pressAll(run)
		if not T.check(enteredAt ~= nil and run.Phase == "Threshold", "w5 crossing: (setup) room 1 entered") then
			cleanup({ p })
			return
		end
		while Mock.Clock.now - enteredAt < 1.3 do
			advance(0.05)
		end
		T.check(run.State == "Corridor", "w5 crossing: no fight before anyone crossed (+1.3 s)")
		local ri = run.Pocket.Rooms[1]
		Mock.Teleport(p, CFrame.new(ri.Threshold.Position))
		while run.State == "Corridor" and Mock.Clock.now - enteredAt < 3 do
			advance(0.05)
		end
		local took = Mock.Clock.now - enteredAt
		T.check(run.State == "Fight" and took < 2.0, "w5 crossing: the crossing at +1.3 s starts the fight at once", string.format("%.2f s", took))
		local f = BC().Fighter
		T.check(f and f.ArriveSeconds == 1.2, "w5 crossing: the wave still arrives in its 1.2 s summon flash (Fighter.ArriveSeconds)", f and tostring(f.ArriveSeconds))
		cleanup({ p })
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client world
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local KC = _G.KC
	local S = {}
	local T = KC and KC.T or _G.K.T
	local guarded = (KC and KC.guarded) or SmokeCommon.guarded
	local Players = game:GetService("Players")
	local Workspace = game:GetService("Workspace")
	local UIS = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local LP = Players.LocalPlayer

	local function req(key)
		local inst = Mock.GetPath(ROOTS[key:match("^(%a+)/")] .. "/" .. key:gsub("^%a+/", ""))
		local ok, mod = pcall(require, inst)
		return ok and type(mod) == "table" and mod or nil
	end
	local function DCm() return (KC.M and KC.M.DungeonController) or req("client/Controllers/DungeonController") end
	local function MCm() return (KC.M and KC.M.MovementController) or req("client/Controllers/MovementController") end
	local function BCm() return (KC.M and KC.M.BattleController) or req("client/Controllers/BattleController") end
	local function PCm() return (KC.M and KC.M.PetController) or req("client/Controllers/PetController") end
	local function CS() return req("client/ClientSettings") end
	local function GQ() return req("client/GraphicsQuality") end
	local function pg()
		return LP:FindFirstChild("PlayerGui")
	end
	local function find(root, name)
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end
	local function cam()
		return Workspace.CurrentCamera
	end
	local function status()
		local rg = pg():FindFirstChild("NimbusDungeonRun")
		local card = rg and rg:FindFirstChild("RunCard")
		local st = card and find(card, "Status")
		return st and st.Text or nil
	end
	local function stepUntil(pred, seconds)
		local t0 = Mock.Clock.now
		while not pred() and Mock.Clock.now - t0 < seconds do
			Mock.Step(1 / 30)
		end
		return pred()
	end
	-- an earlier scenario (client_p5menu) swaps the character out and back without a CharacterAdded: re-announce the
	-- current character so MovementController's per-frame step (FOV, WalkSpeed) is bound, as in the real game
	local function bindCharacter()
		local char = LP.Character
		if char then
			Mock.FireSignal(LP, "CharacterAdded", char)
			KC.advance(0.2)
		end
	end
	local function battleGui()
		return pg():FindFirstChild("NimbusBattle")
	end
	-- a finished battle's floor and result card gone (as smoke_dgfix_client.lua's cleanup)
	local function clearBattle()
		KC.advance(15)
		local g = battleGui()
		local ok = g and g:FindFirstChild("Root")
		ok = ok and ok:FindFirstChild("ResultCard")
		ok = ok and ok:FindFirstChild("Body")
		ok = ok and ok:FindFirstChild("OkButton")
		if ok and ok.Visible then
			Mock.Click(ok)
		end
		Mock.Step(0.1)
	end
	local function setShake(on)
		local cs = CS()
		if cs then
			pcall(cs.Set, "Shake", on)
		end
	end

	local runSeq = 0
	local function runPayload(state, phase, room, id)
		return { RunId = id, Floor = 1, Name = "Mossy Cellar", Element = "Nature", Room = room or 0, RoomCount = 4, Wave = 0, Waves = 0,
			State = state, Phase = phase, Members = { { UserId = LP.UserId, Name = LP.Name } }, Confirmed = {}, NeedConfirm = 0,
			EnterOpen = false, Joinable = false }
	end
	local function newRun()
		runSeq = runSeq + 1
		local id = "D9" .. tostring(runSeq)
		LP:SetAttribute("InBattle", id)
		KC.toClient("DungeonState", "Run", runPayload("Hall", nil, 0, id))
		KC.advance(0.1)
		return id
	end
	local function endRun()
		KC.toClient("DungeonState", "End", { Floor = 1, Name = "Mossy Cellar", Cleared = false, Reason = "Quit", Room = 1, Totals = { Cash = 0, Tokens = 0, Xp = 0, Gems = 0 } })
		KC.advance(0.1)
	end

	-- a pocket with Room_1: the Threshold 10 studs past the door, the character 3 studs before the door (facing -Z)
	local P0 = Vector3.new(520, 60, 520)
	local function buildPocket()
		local folder = Workspace:FindFirstChild("Dungeons")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Dungeons"
			folder.Parent = Workspace
		end
		local holder = Instance.new("Model")
		holder.Name = "Dungeon_W5"
		local ent = Instance.new("Model")
		ent.Name = "Entrance_1"
		local ep = Instance.new("Part")
		ep.Name = "Floor"
		ep.Anchored = true
		ep.Position = P0 + Vector3.new(0, -3, 6)
		ep.Parent = ent
		ent.Parent = holder
		local room = Instance.new("Model")
		room.Name = "Room_1"
		local th = Instance.new("Part")
		th.Name = "Threshold"
		th.Anchored = true
		th.Transparency = 1
		th.Size = Vector3.new(12, 8, 4)
		th.Position = P0 + Vector3.new(0, 1, -10)
		th.Parent = room
		local door = Instance.new("Model")
		door.Name = "Door_Entrance"
		local lintel = Instance.new("Part")
		lintel.Name = "Lintel"
		lintel.Anchored = true
		lintel.Position = P0 + Vector3.new(0, 6, -3)
		lintel.Parent = door
		door.Parent = room
		room.Parent = holder
		holder.Parent = folder
		return holder, th
	end
	local function home()
		Mock.Teleport(LP, CFrame.new(P0, P0 + Vector3.new(0, 0, -1)))
		KC.advance(0.05)
	end
	-- Fade + the next room's Run payload (the walk-in is set up under the black); returns after the Run payload
	local function enterRoom(id, room)
		KC.toClient("DungeonState", "Fade", { Out = 0.45, Hold = 0.35, In = 0.45, Room = room or 1 })
		KC.advance(0.5)
		KC.toClient("DungeonState", "Run", runPayload("Corridor", "Threshold", room or 1, id))
		Mock.Step(1 / 30)
	end
	local function insideTh(th, p)
		local rel = th.CFrame:PointToObjectSpace(p)
		return math.abs(rel.X) <= th.Size.X / 2 + 1 and math.abs(rel.Z) <= th.Size.Z / 2 + 1
	end

	S.client_w5dgn_walkin = guarded("client_w5dgn_walkin", function()
		local DC, MC = DCm(), MCm()
		if not T.check(DC ~= nil and MC ~= nil and type(MC.SetFovOverride) == "function" and type(MC.SetCinematic) == "function", "w5 walk-in: DungeonController + MovementController hooks") then
			return
		end
		pcall(DC.Init)
		UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = false, true, true
		LP:SetAttribute("InMatch", false)
		pcall(DC.Close)
		setShake(true)
		bindCharacter()
		local holder, th = buildPocket()
		home()
		local id = newRun()
		cam().CameraType = Enum.CameraType.Custom
		enterRoom(id, 1)
		local c = cam()
		local root = KC.root()
		local endPos = Vector3.new(th.Position.X, root.Position.Y, th.Position.Z) + Vector3.new(0, 0, -1.5)
		local want = endPos + Vector3.new(0, 0, -9) + Vector3.new(0, 3.5, 0)
		local cp = c.CFrame.Position
		T.check(c.CameraType == Enum.CameraType.Scriptable, "w5 walk-in: Scriptable at fade-in (the camera is placed while the screen is black)", tostring(c.CameraType))
		T.check(Vector3.new(cp.X - want.X, 0, cp.Z - want.Z).Magnitude <= 1 and math.abs(cp.Y - want.Y) <= 0.5,
			"w5 walk-in: the camera stands 9 studs past the Threshold, 3.5 up, in front of the character", string.format("cam %.1f %.1f %.1f want %.1f %.1f %.1f", cp.X, cp.Y, cp.Z, want.X, want.Y, want.Z))
		local toRoot = (root.Position - cp).Unit
		T.check(c.CFrame.LookVector:Dot(toRoot) > 0.95, "w5 walk-in: the camera looks back at the character")
		T.check(math.abs(c.FieldOfView - 60) < 0.6, "w5 walk-in: FOV 60 at the start", tostring(c.FieldOfView))
		T.check(DC.GetState().Walk == "Hold" and status() == "Here we go!", "w5 walk-in: GetState().Walk Hold, the card says 'Here we go!'", tostring(status()))
		T.check(MC.GetSpeedState().Cinematic == true, "w5 walk-in: MovementController is in the cinematic (run / dash ignored, WalkSpeed held)")
		stepUntil(function()
			return DC.GetState().Walk == "Walk"
		end, 0.6)
		local hum = KC.hum()
		local wtp = hum.WalkToPoint
		T.check(DC.GetState().Walk == "Walk" and typeof(wtp) == "Vector3" and insideTh(th, wtp), "w5 walk-in: the fade lifts: Humanoid:MoveTo to a point inside the Threshold box", tostring(wtp))
		T.check(math.abs(hum.WalkSpeed - 6) < 0.01, "w5 walk-in: WalkSpeed 6 during the walk", tostring(hum.WalkSpeed))
		KC.advance(1.35)
		T.check(DC.GetState().Walk == "Blend" or DC.GetState().Walk == nil, "w5 walk-in: the walk ends after 1.3 s (blend)", tostring(DC.GetState().Walk))
		KC.advance(0.45)
		T.check(DC.GetState().Walk == nil and c.CameraType == Enum.CameraType.Custom, "w5 walk-in: Custom after the blend", tostring(c.CameraType))
		T.check(math.abs(c.FieldOfView - 70) < 0.6 and MC.GetSpeedState().Cinematic == false and MC.GetSpeedState().FovOverride == nil, "w5 walk-in: FOV 70, the cinematic off", tostring(c.FieldOfView))

		-- the skip: a game-processed click does not, a free click does (at the Threshold at once); the sink key skips too
		KC.toClient("DungeonState", "Run", runPayload("Fight", nil, 1, id))
		KC.advance(0.1)
		home()
		enterRoom(id, 1)
		stepUntil(function()
			return DC.GetState().Walk == "Walk"
		end, 0.6)
		Mock.FireSignal(UIS, "InputBegan", Mock.NewInput("Unknown", "MouseButton1", "Begin"), false)
		Mock.Step(1 / 30)
		T.check(DC.GetState().Walk == "Blend" and insideTh(th, KC.root().Position), "w5 walk-in: a click skips: the character stands at the Threshold, the blend runs", tostring(DC.GetState().Walk))
		KC.advance(0.3)
		T.check(DC.GetState().Walk == nil and c.CameraType == Enum.CameraType.Custom, "w5 walk-in: the skip's blend ends within 0.25 s")
		KC.toClient("DungeonState", "Run", runPayload("Fight", nil, 1, id))
		KC.advance(0.1)
		home()
		enterRoom(id, 1)
		stepUntil(function()
			return DC.GetState().Walk == "Walk"
		end, 0.6)
		Mock.FireSignal(UIS, "InputBegan", Mock.NewInput("Unknown", "MouseButton1", "Begin"), true)
		Mock.Step(1 / 30)
		T.check(DC.GetState().Walk == "Walk", "w5 walk-in: a game-processed click (a GUI button) does not skip")
		local okSink = pcall(Mock.TriggerAction, "NimbusDungeonWalkSink", "Begin", Mock.NewInput("Space", "Keyboard", "Begin"))
		Mock.Step(1 / 30)
		T.check(okSink and DC.GetState().Walk == "Blend", "w5 walk-in: the movement keys are sunk during the walk-in and a press skips", tostring(DC.GetState().Walk))
		KC.advance(0.4)

		-- a Fight payload mid-walk hands control back within 0.45 s; End clears at once
		KC.toClient("DungeonState", "Run", runPayload("Fight", nil, 1, id))
		KC.advance(0.1)
		home()
		enterRoom(id, 1)
		stepUntil(function()
			return DC.GetState().Walk == "Walk"
		end, 0.6)
		KC.toClient("DungeonState", "Run", runPayload("Fight", nil, 1, id))
		KC.advance(0.45)
		T.check(DC.GetState().Walk == "Blend" or DC.GetState().Walk == nil, "w5 walk-in: the fight started (Run Fight): the blend starts within 0.45 s", tostring(DC.GetState().Walk))
		KC.advance(0.5)
		home()
		enterRoom(id, 1)
		stepUntil(function()
			return DC.GetState().Walk == "Walk"
		end, 0.6)
		endRun()
		T.check(DC.GetState().Walk == nil and c.CameraType == Enum.CameraType.Custom and MC.GetSpeedState().Cinematic == false, "w5 walk-in: End clears at once (camera Custom, controls back)")

		-- no room model: no walk-in, the old text, the camera untouched
		id = newRun()
		home()
		c.CameraType = Enum.CameraType.Custom
		KC.toClient("DungeonState", "Fade", { Out = 0.45, Hold = 0.35, In = 0.45, Room = 3 })
		KC.advance(0.5)
		KC.toClient("DungeonState", "Run", runPayload("Corridor", "Threshold", 3, id))
		KC.advance(1.0)
		T.check(DC.GetState().Walk == nil and c.CameraType == Enum.CameraType.Custom and status() == "Walk into the room to start the fight",
			"w5 walk-in: no room model: no walk-in, the old status text, the camera untouched", tostring(status()))

		-- a lost RenderStep: the light loop clears it by the safety (3 s after the walk began)
		KC.toClient("DungeonState", "Run", runPayload("Fight", nil, 3, id))
		KC.advance(0.1)
		home()
		enterRoom(id, 1)
		stepUntil(function()
			return DC.GetState().Walk == "Walk"
		end, 0.6)
		RunService:UnbindFromRenderStep("NimbusDungeonWalk")
		KC.advance(2.0)
		T.check(DC.GetState().Walk == "Walk", "w5 walk-in: (setup) the walk-in stuck without its RenderStep")
		KC.advance(1.4)
		T.check(DC.GetState().Walk == nil and c.CameraType == Enum.CameraType.Custom, "w5 walk-in: a stuck walk clears by 3 s (the light loop's safety)")

		-- the Run payload beat the teleport: the root is still at the previous room's exit when the walk-in is prepared and
		-- lands by the door under the black; the lane and the end point follow where it stands as the fade lifts
		KC.toClient("DungeonState", "Run", runPayload("Fight", nil, 1, id))
		KC.advance(0.1)
		Mock.Teleport(LP, CFrame.new(P0 + Vector3.new(60, 20, 40)))
		KC.advance(0.05)
		enterRoom(id, 1)
		local preparedAt = DC.GetState().Walk
		Mock.Teleport(LP, CFrame.new(P0 + Vector3.new(3, 0, 0), P0 + Vector3.new(3, 0, -1)))
		stepUntil(function()
			return DC.GetState().Walk == "Walk"
		end, 0.6)
		local wtpL = KC.hum().WalkToPoint
		T.check(preparedAt == "Hold" and typeof(wtpL) == "Vector3" and math.abs(wtpL.X - (th.Position.X + 3)) < 0.2 and math.abs(wtpL.Y - KC.root().Position.Y) < 0.5,
			"w5 walk-in: the lane / end point are recomputed at the fade-in from where the root stands (not the stale pre-teleport spot)",
			string.format("%s, MoveTo %s, Threshold X %.1f", tostring(preparedAt), tostring(wtpL), th.Position.X))
		KC.advance(2.0)

		-- Shake OFF: the walk-in shot still moves (player ruling 2026-10-28: the setting turns off only the hit shakes)
		setShake(false)
		KC.toClient("DungeonState", "Run", runPayload("Fight", nil, 1, id))
		KC.advance(0.1)
		home()
		enterRoom(id, 1)
		stepUntil(function()
			return DC.GetState().Walk == "Walk"
		end, 0.6)
		local cf1 = c.CFrame
		KC.advance(0.5)
		local cf2 = c.CFrame
		T.check(DC.GetState().Walk == "Walk" and (cf1.Position - cf2.Position).Magnitude > 0.3 and c.CameraType == Enum.CameraType.Scriptable,
			"w5 walk-in: Shake OFF: the walk-in shot still plays (the camera dollies)", string.format("moved %.2f, %s, %s, cf1 %s", (cf1.Position - cf2.Position).Magnitude, tostring(DC.GetState().Walk), tostring(c.CameraType), tostring(cf1.Position)))
		setShake(true)
		endRun()
		LP:SetAttribute("InBattle", nil)
		holder:Destroy()
		KC.advance(0.4)
		KC.flushErrors("client_w5dgn_walkin")
	end)

	------------------------------------------------------------------------------------------------
	local function cells()
		local gui = pg():FindFirstChild("NimbusDungeonEnter")
		local grid = gui and gui:FindFirstChild("Grid")
		local out = {}
		for _, c in ipairs(grid and grid:GetChildren() or {}) do
			if c.Name == "Cell" then
				out[#out + 1] = c
			end
		end
		return out, gui
	end
	local function allFull(list, cols, rows)
		for _, c in ipairs(list) do
			if math.abs(c.Size.X.Scale - 1 / cols) > 1e-3 or math.abs(c.Size.Y.Scale - 1 / rows) > 1e-3 then
				return false
			end
		end
		return #list > 0
	end
	local function enterPayload()
		return { Cover = 0.55, Reveal = 0.9, Element = "Flame", Floor = 2, Name = "Ember Hall" }
	end

	S.client_w5dgn_enter = guarded("client_w5dgn_enter", function()
		local DC = DCm()
		if not T.check(DC ~= nil, "w5 enter: DungeonController loads") then
			return
		end
		pcall(DC.Init)
		setShake(true)
		endRun()
		Mock.SetViewport(1920, 1080)
		-- the Dungeon gate: its GlowCore 40 studs in front of the camera
		local gate = Instance.new("Model")
		gate.Name = "Portal_Dungeon_W5"
		local core = Instance.new("Part")
		core.Name = "GlowCore"
		core.Anchored = true
		core.Transparency = 1
		core.CFrame = CFrame.new(0, 300, 0)
		core.Parent = gate
		gate.PrimaryPart = core
		gate:SetAttribute("GateId", "Dungeon")
		gate.Parent = Workspace
		local c = cam()
		c.CameraType = Enum.CameraType.Custom
		c.CFrame = CFrame.lookAt(Vector3.new(0, 300, 40), Vector3.new(0, 300, 0))
		LP:SetAttribute("InBattle", "D95")
		-- the gate lookup never walks the whole Workspace (a hitch on a big plaza)
		local wsMethods = Mock.Classes and Mock.Classes.Workspace and Mock.Classes.Workspace.methods
		local realGD = wsMethods and wsMethods.GetDescendants
		local walks = 0
		if realGD then
			wsMethods.GetDescendants = function(self, ...)
				if self == Workspace then
					walks = walks + 1
				end
				return realGD(self, ...)
			end
		end
		KC.toClient("DungeonState", "Enter", enterPayload())
		Mock.Step(1 / 30)
		if realGD then
			wsMethods.GetDescendants = realGD
		end
		T.check(realGD ~= nil and walks == 0, "w5 enter: the Dungeon gate is found without a Workspace:GetDescendants() walk", walks .. " walks")
		local list, gui = cells()
		T.check(gui and gui.Enabled and gui.DisplayOrder == 26 and gui.IgnoreGuiInset == true and #list == 144, "w5 enter: NimbusDungeonEnter (DisplayOrder 26) with 16 x 9 cells on 1920 x 1080", tostring(#list))
		T.check(DC.GetState().Enter == "Rush" and c.CameraType == Enum.CameraType.Scriptable, "w5 enter: the camera rushes into the gate (Scriptable)", tostring(DC.GetState().Enter))
		KC.advance(0.3)
		T.check((c.CFrame.Position - Vector3.new(0, 300, 40)).Magnitude > 3, "w5 enter: the camera moved toward the vortex")
		KC.advance(0.12)
		T.check(allFull(list, 16, 9) and DC.GetState().Enter ~= "Hold", "w5 enter: every cell full by 0.45 s (ENTER_MARGIN before Cover 0.55: the teleport can never show at the edges)", tostring(DC.GetState().Enter))
		KC.advance(0.15)
		T.check(allFull(list, 16, 9) and c.CameraType == Enum.CameraType.Custom and DC.GetState().Enter == "Hold", "w5 enter: every cell full by 0.55 s, the camera back to Custom under them", tostring(DC.GetState().Enter))
		KC.toClient("DungeonState", "Run", runPayload("Hall", nil, 0, "D95"))
		KC.advance(0.3)
		local falling = 0
		for _, cell in ipairs(list) do
			if cell.Rotation ~= 0 and cell.BackgroundTransparency > 0 then
				falling = falling + 1
			end
		end
		T.check(DC.GetState().Enter == "Reveal" and falling > 0, "w5 enter: the fresh Run payload makes the blocks fall away (tumbling, fading)", tostring(DC.GetState().Enter) .. " " .. falling)
		KC.advance(0.65)
		T.check(gui.Enabled == false and DC.GetState().Enter == nil, "w5 enter: gui disabled by 0.95 s after the reveal began")

		-- a portrait phone: 9 x 16; End during the cover clears at once
		endRun()
		Mock.SetViewport(390, 844)
		LP:SetAttribute("InBattle", "D96")
		KC.toClient("DungeonState", "Enter", enterPayload())
		KC.advance(0.6)
		list, gui = cells()
		T.check(#list == 144 and allFull(list, 9, 16), "w5 enter: 9 x 16 cells on a 390 x 844 phone", tostring(#list))
		KC.toClient("DungeonState", "Enter", enterPayload())
		Mock.Step(1 / 30)
		endRun()
		T.check(gui.Enabled == false and DC.GetState().Enter == nil and c.CameraType == Enum.CameraType.Custom, "w5 enter: End during the cover clears at once")

		-- Low graphics: 8 x 5; a click during the reveal hides at once
		Mock.SetViewport(1920, 1080)
		local gq = GQ()
		local okLow = gq and pcall(gq.Apply, "Low")
		LP:SetAttribute("InBattle", "D97")
		KC.toClient("DungeonState", "Enter", enterPayload())
		KC.advance(0.6)
		list, gui = cells()
		T.check(okLow and #list == 40 and allFull(list, 8, 5), "w5 enter: GraphicsQuality Low: 8 x 5 cells", tostring(#list))
		KC.toClient("DungeonState", "Run", runPayload("Hall", nil, 0, "D97"))
		KC.advance(0.1)
		Mock.FireSignal(UIS, "InputBegan", Mock.NewInput("Unknown", "MouseButton1", "Begin"), false)
		Mock.Step(1 / 30)
		T.check(gui.Enabled == false and DC.GetState().Enter == nil, "w5 enter: a click during the reveal hides the blocks at once")
		if gq then
			pcall(gq.Apply, "High")
		end

		-- no Run payload (refused): reveal at 3 s, then clear
		endRun()
		LP:SetAttribute("InBattle", "D98")
		KC.toClient("DungeonState", "Enter", enterPayload())
		KC.advance(2.9)
		T.check(DC.GetState().Enter == "Hold" and gui.Enabled, "w5 enter: the blocks hold while no Run payload came (2.9 s)")
		KC.advance(0.2)
		T.check(DC.GetState().Enter == "Reveal", "w5 enter: no Run by 3 s: the reveal starts anyway", tostring(DC.GetState().Enter))
		KC.advance(1.0)
		T.check(gui.Enabled == false and DC.GetState().Enter == nil, "w5 enter: ... and the blocks are gone")

		-- Shake OFF: the rush still plays (player ruling 2026-10-28: the setting turns off only the hit shakes)
		KC.advance(0.6)
		endRun()
		setShake(false)
		c.CameraType = Enum.CameraType.Custom
		c.CFrame = CFrame.lookAt(Vector3.new(0, 300, 40), Vector3.new(0, 300, 0))
		KC.toClient("DungeonState", "Enter", enterPayload())
		Mock.Step(1 / 30)
		T.check(DC.GetState().Enter == "Rush" and c.CameraType == Enum.CameraType.Scriptable and gui.Enabled, "w5 enter: Shake OFF: the camera rush still plays (Scriptable), the blocks cover",
			tostring(DC.GetState().Enter))
		setShake(true)
		endRun()
		-- a camera far from the gate (a member who wandered off): no flight across the plaza, the blocks still cover
		c.CameraType = Enum.CameraType.Custom
		c.CFrame = CFrame.lookAt(Vector3.new(0, 300, 100), Vector3.new(0, 300, 0))
		KC.toClient("DungeonState", "Enter", enterPayload())
		local never = true
		for _ = 1, 20 do
			Mock.Step(1 / 30)
			if c.CameraType ~= Enum.CameraType.Custom then
				never = false
			end
		end
		T.check(never and DC.GetState().Enter ~= nil and gui.Enabled, "w5 enter: a camera 100 studs from the gate (> 60): no rush, the blocks still cover")
		endRun()
		LP:SetAttribute("InBattle", nil)
		gate:Destroy()
		KC.advance(0.4)
		KC.flushErrors("client_w5dgn_enter")
	end)

	------------------------------------------------------------------------------------------------
	local PetCatalog = req("shared/PetCatalog")
	local function petOf(rarity, skip)
		for _, def in ipairs(PetCatalog and PetCatalog.Pets or {}) do
			if def.Rarity == rarity and not def.EventOnly and def.Id ~= skip then
				return def.Id
			end
		end
		return nil
	end
	local function snapshot(pets)
		local owned = {}
		for _, id in ipairs(pets) do
			owned[id] = 1
		end
		return {
			Tokens = 600, Pets = owned, Equipped = {}, Items = {},
			Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			SpotIndex = 1, Perks = {}, Discovered = owned, IndexClaimed = {},
			Tutorial = { Step = 99, Done = true, Gifted = true },
			PetLevels = {}, PetGrowth = {},
		}
	end

	S.client_w5pets_follow = guarded("client_w5pets_follow", function()
		local pc, BC = PCm(), BCm()
		T.check(pc ~= nil and pc.HANDOVER == 1.0, "w5 pets: PetController.HANDOVER is 1.0 s (= BattleController DUNGEON_LINGER)", pc and tostring(pc.HANDOVER))
		if not T.check(pc ~= nil and BC ~= nil and type(BC.LastDrawn) == "function", "w5 pets: PetController + BattleController.LastDrawn") then
			return
		end
		local a, b = petOf("Common"), petOf("Rare")
		KC.toClient("ProfileSync", snapshot({ a, b }))
		KC.advance(0.2)
		LP:SetAttribute("InBattle", nil)
		LP:SetAttribute("InFight", nil)
		LP:SetAttribute("EquippedPets", "")
		KC.advance(0.3)
		Mock.Teleport(LP, CFrame.new(Vector3.new(420, 60, 420)))
		LP:SetAttribute("EquippedPets", a .. "," .. b)
		KC.advance(3)
		local info = pc.GetFollowerInfo(LP)
		if not T.check(#info == 2 and info[1].Model and info[2].Model, "w5 pets: (setup) 2 followers built", tostring(#info)) then
			return
		end
		local function shown()
			local m = pc.GetFollowerInfo(LP)[1].Model
			return m ~= nil and m:IsDescendantOf(Workspace)
		end
		local function cardsShown()
			local n, on = 0, 0
			for _, c in ipairs(pc.GetCards()) do
				if c.UserId == LP.UserId then
					n = n + 1
					on = on + (c.Shown and 1 or 0)
				end
			end
			return n, on
		end
		LP:SetAttribute("InBattle", "D1")
		KC.advance(0.6)
		T.check(shown(), "w5 pets: visible in the corridor (InBattle = a run id, InFight nil)")
		local nc, onc = cardsShown()
		T.check(nc == 2 and onc == 2, "w5 pets: ...and their name cards show with them (the cards follow the park rule, not InBattle)", onc .. " of " .. nc)
		LP:SetAttribute("InFight", true)
		Mock.Step(1 / 30)
		Mock.Step(1 / 30)
		T.check(not shown(), "w5 pets: InFight true parks them within a frame (BattleController draws the team)")
		nc, onc = cardsShown()
		T.check(onc == 0, "w5 pets: ...and their name cards hide", onc .. " of " .. nc)
		local real = BC.LastDrawn
		local spot = KC.root().Position + Vector3.new(6, 0, 0)
		local key = info[1].Key
		BC.LastDrawn = function(uid)
			if uid == LP.UserId then
				return spot, key
			end
			return nil
		end
		local ok, err = pcall(function()
			LP:SetAttribute("InFight", nil)
			KC.advance(0.5)
			T.check(not shown(), "w5 pets: still parked at +0.5 s after the fight (the fighter model is still drawn)")
			local t0 = Mock.Clock.now
			while not shown() and Mock.Clock.now - t0 < 1 do
				Mock.Step(1 / 60)
			end
			T.check(shown() and Mock.Clock.now - t0 <= 0.65, "w5 pets: visible again by +1.1 s", string.format("%.2f", Mock.Clock.now - t0 + 0.5))
			local m = pc.GetFollowerInfo(LP)[1].Model
			local d = m and (m:GetPivot().Position - spot).Magnitude or 99
			T.check(d < 2.5, "w5 pets: the fighter-key pet starts where BattleController last drew the fighter", string.format("%.2f studs", d))
		end)
		-- a LOST room: the KO'd fighter is still drawn (END_LINGER) after the hand-over: the followers wait for it
		local drawnUntil = 0
		local realDrawn = BC.FighterDrawn
		BC.FighterDrawn = function(uid)
			return uid == LP.UserId and Mock.Clock.now < drawnUntil
		end
		local ok2, err2 = pcall(function()
			LP:SetAttribute("InFight", true)
			KC.advance(0.2)
			drawnUntil = Mock.Clock.now + 2.5
			LP:SetAttribute("InFight", nil)
			KC.advance(1.6)
			T.check(not shown(), "w5 pets: a lost room: still parked at +1.6 s while the KO'd fighter model is drawn (no two teams on screen)")
			KC.advance(1.1)
			T.check(shown(), "w5 pets: ...and back once the fighter is gone")
			LP:SetAttribute("InFight", true)
			KC.advance(0.2)
			drawnUntil = Mock.Clock.now + 60
			LP:SetAttribute("InFight", nil)
			KC.advance(5.3)
			T.check(shown(), "w5 pets: ...never longer than HANDOVER_MAX (5 s) after the fight, whatever BattleController says")
		end)
		BC.FighterDrawn = realDrawn
		BC.LastDrawn = real
		if not ok then
			error(err, 0)
		end
		if not ok2 then
			error(err2, 0)
		end
		LP:SetAttribute("InBattle", "B7")
		Mock.Step(1 / 30)
		Mock.Step(1 / 30)
		T.check(not shown(), "w5 pets: a battle id (B7) still parks the followers (regression)")
		LP:SetAttribute("InBattle", nil)
		KC.advance(0.3)
		T.check(shown(), "w5 pets: back after the battle")
		LP:SetAttribute("EquippedPets", "")
		KC.advance(0.3)
		KC.flushErrors("client_w5pets_follow")
	end)

	------------------------------------------------------------------------------------------------
	-- a minimal battle driver (server order: Start, then the wave) on a real BattleSim, as smoke_dgfix_client.lua's
	local function team(count, skip, level)
		local out, kinds = {}, {}
		skip = skip or 0
		for _, def in ipairs(PetCatalog and PetCatalog.Pets or {}) do
			local sp = type(def.Special) == "table" and def.Special.Kind or nil
			if sp and def.Role == "Combat" and not kinds[sp] and def.Rarity ~= "Secret" and not def.EventOnly then
				if skip > 0 then
					skip = skip - 1
				else
					kinds[sp] = true
					out[#out + 1] = { Key = def.Id, PetId = def.Id, Level = level or 12, Tier = "Normal", Slot = #out + 1 }
					if #out >= count then
						break
					end
				end
			end
		end
		return out
	end
	local function driver(opts)
		local Sim = req("shared/BattleSim")
		if not Sim then
			return nil
		end
		local id = "w5_" .. tostring(opts.Mode) .. "_" .. tostring(math.random(100000, 999999))
		local sim = Sim.new({ Mode = opts.Mode, Seed = 9, Id = id, Teams = opts.Teams, Boss = opts.Boss, Zone = { X = 44, Z = 44 }, TimeLimit = 120 })
		if not sim then
			return nil
		end
		local d = { sim = sim, id = id, opts = opts }
		function d.start()
			local p = sim:Describe()
			p.BattleId = id
			p.Zone = { CFrame = CFrame.new(0, 200, 0), Size = Vector3.new(p.Zone.X, 30, p.Zone.Z), X = p.Zone.X, Z = p.Zone.Z }
			p.Names = { [tostring(LP.UserId)] = LP.Name }
			p.Side = 1
			p.Spectator = false
			p.T = sim:Time()
			p.Dungeon = opts.Dungeon
			local tm = sim:TeamOf(LP.UserId)
			if tm then
				p.Team = { Fighter = tm.Fighter, Bench = tm.Bench, Lives = tm.Lives, Speed = tm.Speed,
					Cooldowns = { Element = tm.Cooldowns.Element, Dash = tm.Cooldowns.Dash, Swap = tm.Cooldowns.Swap, Buff = {} } }
			end
			LP:SetAttribute("InBattle", id)
			KC.toClient("BattleState", "Start", p, id)
		end
		function d.step()
			local evs = sim:Step(0.1)
			if #evs > 0 then
				KC.toClient("BattleState", "Events", evs, id)
			end
			d.last = d.last or {}
			local snap = sim:SnapshotDelta(d.last)
			snap.BattleId = id
			KC.toClient("BattleState", "Snapshot", snap, id)
			for _ = 1, 3 do
				Mock.Step(0.1 / 3)
			end
		end
		function d.finish()
			KC.toClient("BattleState", "End", { BattleId = id, Mode = opts.Mode, Outcome = "Left", Won = false, Spectator = false, Reason = "Left" }, id)
		end
		return d
	end

	S.client_w5dgn_camera = guarded("client_w5dgn_camera", function()
		local DC, BC, MC = DCm(), BCm(), MCm()
		local AF = req("client/Controllers/AttackFx")
		if not T.check(DC ~= nil and BC ~= nil and MC ~= nil and AF ~= nil and type(MC.FovPunch) == "function", "w5 camera: the controllers load") then
			return
		end
		pcall(DC.Init)
		setShake(true)
		endRun()
		bindCharacter()
		local hum = KC.hum()
		hum.CameraOffset = Vector3.new(0, 0, 0)
		local SH = Vector3.new(1.4, 0.35, 0)
		local id = newRun()
		T.check((hum.CameraOffset - SH).Magnitude < 1e-4 and DC.GetState().Shoulder == true, "w5 camera: the run's Run payload puts the camera over the shoulder (CameraOffset 1.4, 0.35, 0)", tostring(hum.CameraOffset))
		BC.FxHooks()
		local punch = AF.Hooks and AF.Hooks.Punch
		T.check(type(punch) == "function", "w5 camera: (setup) AttackFx's camera punch hook")
		if punch then
			punch(0.12, 0.15)
			Mock.Step(1 / 30)
			T.check((hum.CameraOffset - SH).Magnitude > 1e-4, "w5 camera: (setup) the shake moves the offset")
			KC.advance(0.4)
			T.check((hum.CameraOffset - SH).Magnitude < 1e-4, "w5 camera: offset kept after a shake (the shake rides on the shoulder)", tostring(hum.CameraOffset))
		end
		endRun()
		T.check(hum.CameraOffset.Magnitude < 1e-4 and DC.GetState().Shoulder == false, "w5 camera: End -> CameraOffset zero")

		-- a dungeon battle: a 5 % hit on my fighter shakes once; a big punch opens the FOV and lets it go
		local d = driver({ Mode = "Dungeon", Teams = { { Owner = LP.UserId, Side = 1, Pets = team(3, 0, 14) } }, Dungeon = { Floor = 2, Room = 1, Wave = 1, Waves = 2, Name = "Ember Hall", Element = "Flame" } })
		if not T.check(d ~= nil, "w5 camera: (setup) a dungeon battle driver") then
			return
		end
		d.start()
		d.step()
		d.sim:SpawnEnemies(team(1, 3, 10), { Wave = 1, Anchor = { 0, 10 } })
		for _ = 1, 16 do
			d.step()
		end
		local gb = BC.GetBattle()
		local fid = gb and gb.FighterId
		local enemy = nil
		for _, u in ipairs(d.sim.units or {}) do
			if u.side ~= 1 and u.alive then
				enemy = u.id
			end
		end
		local function hitMe(mode)
			local fu = fid and BC.GetUnit(fid)
			local maxHp = (fu and fu.MaxHp) or 100
			local before = BC.GetStats().CameraShakes
			KC.toClient("BattleState", "Events", { { type = "Hit", from = enemy, to = fid, dmg = math.max(1, maxHp * 0.05) } }, d.id)
			KC.advance(0.4)
			return BC.GetStats().CameraShakes - before
		end
		T.check(gb and gb.Mode == "Dungeon" and fid and enemy, "w5 camera: (setup) my fighter and an enemy on the floor")
		if gb and fid and enemy then
			T.eq(hitMe(), 1, "w5 camera: a 5 % hit on my fighter in a dungeon -> one light shake")
			local c = cam()
			KC.advance(0.5)
			local base = c.FieldOfView
			punch(0.25, 0.2)
			Mock.Step(1 / 30)
			local peak = c.FieldOfView
			T.check(peak > base + 1, "w5 camera: a big attack's punch (0.25) opens the FOV next frame", string.format("%.2f -> %.2f", base, peak))
			KC.advance(0.3)
			T.check(math.abs(c.FieldOfView - base) < 0.05, "w5 camera: ... and lets it go within 0.3 s", string.format("%.2f", c.FieldOfView))
			setShake(false)
			KC.advance(0.1)
			local offBefore = hum.CameraOffset
			punch(0.25, 0.2)
			Mock.Step(1 / 30)
			T.check(c.FieldOfView > base + 1 and (hum.CameraOffset - offBefore).Magnitude < 1e-4, "w5 camera: Shake OFF: no shake, but the FOV punch still plays (player ruling 2026-10-28)",
				string.format("FOV %.2f -> %.2f", base, c.FieldOfView))
			KC.advance(0.3)
			setShake(true)
		end
		d.finish()
		LP:SetAttribute("InBattle", nil)
		clearBattle()

		-- a raid: no light shake on a small hit, no FOV punch
		local r = driver({ Mode = "Raid", Boss = "storm_titan", Teams = { { Owner = LP.UserId, Side = 1, Pets = team(3, 0, 20) } } })
		if r then
			r.start()
			for _ = 1, 6 do
				r.step()
			end
			gb = BC.GetBattle()
			fid = gb and gb.FighterId
			enemy = nil
			for _, u in ipairs(r.sim.units or {}) do
				if u.side ~= 1 and u.alive then
					enemy = u.id
				end
			end
			if T.check(gb and gb.Mode == "Raid" and fid and enemy, "w5 camera: (setup) a raid battle") then
				T.eq(hitMe(), 0, "w5 camera: a raid: no light shake on a 5 % hit")
				local c = cam()
				KC.advance(0.5)
				local base = c.FieldOfView
				punch(0.25, 0.2)
				Mock.Step(1 / 30)
				T.check(math.abs(c.FieldOfView - base) < 0.05, "w5 camera: Raid: no FOV punch", string.format("%.2f -> %.2f", base, c.FieldOfView))
			end
			r.finish()
		end
		LP:SetAttribute("InBattle", nil)
		clearBattle()
		T.check(BC.GetBattle() == nil, "w5 camera: (cleanup) no battle left for the next scenario")
		KC.flushErrors("client_w5dgn_camera")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
