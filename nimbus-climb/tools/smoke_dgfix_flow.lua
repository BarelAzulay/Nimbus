-- smoke_dgfix_flow.lua: dungeon fixes (docs/dungeon-fixes/plan.md decisions 1 + 2, dungeon side) - the room change by
-- E at the door with a per-player confirm and a fade, and the encounter centre on the room's floor.
-- Loaded by tools/smoke.py in BOTH worlds; ARGS.context picks the half.
--
-- server (booted, before "shutdown"):
--   dgfix_flow_solo    no room change without E (the Hall and a cleared corridor wait past HallSeconds / Intermission +
--                      DoorTime), the EnterPrompt shape, a press from too far / at the wrong door / spammed 25 times in
--                      one frame moves the run ONCE (Dg.enterRoom counted), Fade { Out 0.45, Hold 0.35, In 0.45 } sent
--                      BEFORE the teleport, the Run payload's Confirmed / NeedConfirm / EnterOpen, a run older than the
--                      old 703 s limit waiting at a door is NOT ended, an AFK run past MaxRunSeconds still is
--   dgfix_flow_party   3 players: one member's E moves nobody (the others see "Confirmed {a}, NeedConfirm 2"), the
--                      other two pressing in the same frame move the group exactly once, a Downed member must press too,
--                      a leaver mid-wait unblocks the rest, a late joiner must press before the group moves
--   dgfix_flow_floor   floor 2: the encounter centre (BattleService's zone + the Start payload) within 0.5 studs of the
--                      room's floor in a wave room and the boss room, FloorY on the floor, waves 2 / 3 still spawn
--                      (SpawnWave + Wave events), the boss room's exit -> E -> the treasure alcove (no timer)
-- client:
--   client_dgfix_flow  the side card ("Go to the door and press E" / "Waiting for 2 more (Ava, Sam)"), the fade
--                      overlay (own ScreenGui, IgnoreGuiInset, above the HUD / below Notify) appears, holds until the
--                      next room's Run payload and clears; the 3 s safety clear; End clears it at once; nothing is sent
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
	local function D()
		local bc = BC()
		return bc and bc.Dungeon or {}
	end
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
		if type(DGS().Dg.nextDoor) ~= "function" or type(DGS().Dg.confirm) ~= "function" then
			T.fail(label .. ": DungeonService has no Dg.nextDoor / Dg.confirm (decision 2 not implemented)")
			return false
		end
		return true
	end

	local function newPlayer(prefix, level)
		seq = seq + 1
		local p = Mock.AddPlayer(prefix .. seq, 975300 + seq)
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
	local function lastRun(p, mark)
		local list = msgs(p, mark, "Run")
		return list[#list]
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
		K.removePlayers(list)
		advance(1)
	end

	local function scenario(name, fn)
		return K.guarded(name, function()
			local dgs = DGS()
			local saved = dgs and dgs.Dg.enterRoom
			local bs = BS()
			local savedSpawn = bs and bs.SpawnWave
			local ok, err = pcall(fn)
			if dgs and saved then
				dgs.Dg.enterRoom = saved
			end
			if bs and savedSpawn then
				bs.SpawnWave = savedSpawn
			end
			if not ok then
				error(err, 0)
			end
		end)
	end

	-- counts Dg.enterRoom calls (the room change must happen exactly once per door)
	local function countEnterRoom()
		local dg = DGS().Dg
		local real = dg.enterRoom
		local box = { n = 0, rooms = {} }
		dg.enterRoom = function(run, room)
			box.n = box.n + 1
			box.rooms[#box.rooms + 1] = room
			return real(run, room)
		end
		box.restore = function()
			dg.enterRoom = real
		end
		return box
	end

	-- the open door's prompt (waits out the Intermission)
	local function doorOf(run)
		local dg = DGS().Dg
		local t0 = Mock.Clock.now
		local prompt = dg.nextDoor(run)
		while not prompt and run.State ~= "Ending" and Mock.Clock.now - t0 < (D().Intermission or 2) + 2 do
			advance(0.25)
			prompt = dg.nextDoor(run)
		end
		return prompt
	end

	local function press(p, prompt, times)
		Mock.Teleport(p, CFrame.new(prompt.Parent.Position + Vector3.new(1, 0, 0)))
		for _ = 1, times or 1 do
			Mock.Trigger(prompt, p)
		end
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

	local function pressAll(run)
		local prompt = doorOf(run)
		if not prompt then
			return false
		end
		for _, p in ipairs(members(run)) do
			press(p, prompt)
		end
		advance(0.6)
		return true
	end

	-- the BattleService battle record of an encounter (white-box, as smoke_p5_dungeon.lua does)
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

	-- clears the current room: `p`'s fighter stands at each enemy (made fragile) with its attack ready
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

	-- the top of the room's floor under the zone centre (the template's Floor tiles)
	local function floorTop(ri, at)
		local best, bestD = nil, math.huge
		for _, d in ipairs(ri.Room:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Floor" then
				local dx, dz = d.Position.X - at.X, d.Position.Z - at.Z
				local dist = dx * dx + dz * dz
				if dist < bestD then
					best, bestD = d, dist
				end
			end
		end
		return best and (best.Position.Y + best.Size.Y / 2) or nil
	end

	local function startOf(p, mark)
		for _, e in ipairs(K.remotesFor("BattleState", p.UserId, mark)) do
			if e.args[1] == "Start" and type(e.args[2]) == "table" then
				return e.args[2]
			end
		end
		return nil
	end

	------------------------------------------------------------------------------------------------
	S.dgfix_flow_solo = scenario("dgfix_flow_solo", function()
		if not ready("dgfix_flow_solo") then
			return
		end
		local dgs, d = DGS(), D()
		local p = newPlayer("DgfSolo", 20)
		toPad(p)
		local mark = K.logSize()
		request(p, "Solo", 1)
		local run = runOf(p)
		if not T.check(run ~= nil and run.State == "Hall", "dgfix solo: (setup) a solo floor-1 run in its Hall") then
			cleanup({ p })
			return
		end
		local enters = countEnterRoom()
		-- 1. the Hall never times out into room 1
		advance((d.HallSeconds or 10) + 5)
		T.check(run.State == "Hall" and run.Room == 0 and enters.n == 0, "dgfix solo: no room change without E (Hall after HallSeconds + 5 s)", tostring(run.State))
		local prompt = dgs.Dg.nextDoor(run)
		T.check(prompt ~= nil and prompt == run.Pocket.Hall.NextPrompt and prompt.Enabled == true and prompt.Name == "EnterPrompt" and prompt.ActionText == "Enter"
			and prompt.ObjectText == "Room 1" and prompt.KeyboardKeyCode == Enum.KeyCode.E and prompt.HoldDuration == 0 and prompt.RequiresLineOfSight == false
			and prompt.MaxActivationDistance == 10 and prompt:GetAttribute("DungeonAction") == "Enter",
			"dgfix solo: the hall's exit EnterPrompt (E, no hold, no line of sight, 10 studs, DungeonAction Enter, Enter / 'Room 1') is enabled")
		local msg = lastRun(p, mark)
		T.check(msg and msg.EnterOpen == true and msg.NeedConfirm == 1 and type(msg.Confirmed) == "table" and #msg.Confirmed == 0 and msg.Next == 1,
			"dgfix solo: Run { EnterOpen, NeedConfirm 1, Confirmed {}, Next 1 } in the Hall")
		local others = 0
		for _, room in pairs(run.Pocket.Rooms) do
			if room.EnterPrompt and room.EnterPrompt.Enabled then
				others = others + 1
			end
		end
		T.eq(others, 0, "dgfix solo: every other EnterPrompt is disabled")
		-- 2. too far / the wrong door / the remote: nothing
		if not prompt then
			cleanup({ p })
			return
		end
		Mock.Teleport(p, CFrame.new(prompt.Parent.Position + Vector3.new(30, 0, 0)))
		Mock.Trigger(prompt, p)
		advance(0.4)
		T.check(not run.Confirm[p.UserId] and run.State == "Hall", "dgfix solo: a press 30 studs from the door is ignored")
		local wrong = run.Pocket.Rooms[1] and run.Pocket.Rooms[1].EnterPrompt
		if wrong then
			Mock.Teleport(p, CFrame.new(wrong.Parent.Position))
			Mock.Trigger(wrong, p)
			advance(0.4)
			T.check(not run.Confirm[p.UserId] and run.State == "Hall" and enters.n == 0, "dgfix solo: a press at a door that is not open (room 1's entrance) is ignored")
		end
		request(p, "Enter")
		advance(0.4)
		T.check(not run.Confirm[p.UserId] and run.State == "Hall", "dgfix solo: DungeonRequest('Enter') is junk (the client sends nothing new)")
		-- 3. 25 presses in one frame: one Fade, the teleport after Out, one enterRoom
		advance(0.4)
		local fadeMark = K.logSize()
		press(p, prompt, 25)
		local fades = msgs(p, fadeMark, "Fade")
		T.check(#fades == 1 and fades[1].Out == 0.45 and fades[1].Hold == 0.35 and fades[1].In == 0.45 and fades[1].Room == 1,
			"dgfix solo: the last E sends DungeonState('Fade', { Out 0.45, Hold 0.35, In 0.45, Room 1 }) once", tostring(#fades))
		T.check(run.Transit == true and run.State == "Hall" and enters.n == 0 and (pos(p) - prompt.Parent.Position).Magnitude < 3,
			"dgfix solo: the Fade goes out BEFORE the teleport (still in the Hall, Transit lock on)")
		T.check(prompt.Enabled == false, "dgfix solo: the door's prompt is disabled during the transit")
		advance(0.6)
		local ri1 = run.Pocket.Rooms[1]
		T.check(enters.n == 1 and enters.rooms[1] == 1 and run.State == "Corridor" and run.Phase == "Threshold" and run.Room == 1 and not run.Transit,
			"dgfix solo: after Out the run enters room 1 exactly once (Dg.enterRoom x" .. enters.n .. ")")
		T.check(ri1 and (pos(p) - ri1.Entrance.Position).Magnitude < 6 and ri1.Model:GetAttribute("EntranceOpen") == true, "dgfix solo: the member stands at room 1's Entrance, its door open")
		for _ = 1, 5 do
			Mock.Trigger(prompt, p)
		end
		advance(1.5)
		T.eq(enters.n, 1, "dgfix solo: more presses at the old door change nothing")
		-- 4. the fight, the clear, the corridor wait (no DoorTime)
		crossThreshold(run, p)
		T.check(run.State == "Fight" and run.Room == 1, "dgfix solo: (setup) room 1's fight")
		T.check(clearRoom(run, p, 60) and run.State == "Corridor" and run.Phase == "Walk", "dgfix solo: (setup) room 1 cleared", tostring(run.State))
		local door2 = doorOf(run)
		local ri2 = run.Pocket.Rooms[2]
		T.check(door2 ~= nil and ri2 and door2 == ri2.EnterPrompt and door2.ObjectText == "Room 2" and door2.Enabled == true and ri2.Model:GetAttribute("EntranceOpen") == false,
			"dgfix solo: after the bars open, room 2's closed Door_Entrance offers EnterPrompt 'Room 2'")
		local waitS = (d.Intermission or 2) + (d.DoorTime or 12) + (d.HallSeconds or 10) + 40
		local t0 = Mock.Clock.now
		while Mock.Clock.now - t0 < waitS do
			advance(1)
		end
		T.check(run.State == "Corridor" and run.Room == 1 and enters.n == 1, "dgfix solo: a slow group: " .. math.floor(waitS) .. " s at the door, still no room change")
		-- the old watchdog limit (RunMaxSeconds, with DoorTime) would have killed this run: the new one does not
		run.Started = Mock.Clock.now - (d.RunMaxSeconds or 703) - 30
		advance(1.2)
		T.check(run.State == "Corridor", "dgfix solo: a run older than the catalog's RunMaxSeconds waiting at a door is not ended (" .. tostring(dgs.MaxRunSeconds(1)) .. " s limit)")
		press(p, door2)
		advance(0.6)
		T.check(enters.n == 2 and run.Room == 2 and run.Phase == "Threshold", "dgfix solo: E at room 2's door enters room 2 (enterRoom x" .. enters.n .. ")")
		-- 5. an AFK group still frees its pocket at MaxRunSeconds
		run.Started = Mock.Clock.now - dgs.MaxRunSeconds(1) - 1
		advance(1.2)
		T.check(run.State == "Ending" and run.EndReason == "Error", "dgfix solo: an AFK run past MaxRunSeconds(floor) still ends (watchdog)")
		enters.restore()
		cleanup({ p })
	end)

	------------------------------------------------------------------------------------------------
	S.dgfix_flow_party = scenario("dgfix_flow_party", function()
		if not ready("dgfix_flow_party") then
			return
		end
		local dgs = DGS()
		local a, b, c = newPlayer("DgfA", 20), newPlayer("DgfB", 20), newPlayer("DgfC", 20)
		local late = newPlayer("DgfLate", 20)
		local all = { a, b, c, late }
		for i, p in ipairs({ a, b, c }) do
			toPad(p, i)
		end
		request(a, "Create", 1)
		for _, p in ipairs({ b, c }) do
			request(p, "Join", a.UserId)
			request(p, "Ready", true)
			advance(0.4)
		end
		request(a, "Start")
		advance(6)
		local run = runOf(a)
		if not T.check(run ~= nil and run.State == "Hall" and #members(run) == 3, "dgfix party: (setup) a 3-player run in its Hall") then
			cleanup(all)
			return
		end
		local enters = countEnterRoom()
		local prompt = doorOf(run)
		-- 1. one member's E moves nobody
		local mark = K.logSize()
		local pb, pc = pos(b), pos(c)
		press(a, prompt, 10)
		advance(3)
		local seen = lastRun(b, mark)
		T.check(run.State == "Hall" and enters.n == 0 and run.Confirm[a.UserId] == true and not run.Transit, "dgfix party: one member pressing E (10 times) moves nobody")
		T.check(seen and #seen.Confirmed == 1 and seen.Confirmed[1] == a.UserId and seen.NeedConfirm == 2 and seen.EnterOpen == true,
			"dgfix party: the others see Run { Confirmed { a }, NeedConfirm 2 }")
		T.check((pos(b) - pb).Magnitude < 0.01 and (pos(c) - pc).Magnitude < 0.01 and #msgs(b, mark, "Fade") == 0, "dgfix party: no one was teleported or faded")
		-- 2. the other two in the same frame (+ a again): the group moves exactly once
		mark = K.logSize()
		Mock.Teleport(b, CFrame.new(prompt.Parent.Position + Vector3.new(-1, 0, 0)))
		Mock.Teleport(c, CFrame.new(prompt.Parent.Position + Vector3.new(0, 0, 1)))
		Mock.Trigger(prompt, b)
		Mock.Trigger(prompt, c)
		Mock.Trigger(prompt, a)
		Mock.Trigger(prompt, c)
		local fadesOk = #msgs(a, mark, "Fade") == 1 and #msgs(b, mark, "Fade") == 1 and #msgs(c, mark, "Fade") == 1
		T.check(fadesOk and run.Transit == true and enters.n == 0, "dgfix party: the last two presses (same frame) send ONE Fade to each member before any teleport")
		advance(0.6)
		local ri1 = run.Pocket.Rooms[1]
		local placed = true
		for _, p in ipairs({ a, b, c }) do
			if (pos(p) - ri1.Entrance.Position).Magnitude > 8 then
				placed = false
			end
		end
		T.check(enters.n == 1 and run.Room == 1 and run.Phase == "Threshold" and placed, "dgfix party: all three enter room 1 together, Dg.enterRoom exactly once (x" .. enters.n .. ")")
		advance(2)
		T.eq(enters.n, 1, "dgfix party: no second enterRoom after the transit")
		-- 3. clear room 1; a Downed member must press too; a leaver mid-wait unblocks the rest
		crossThreshold(run, a)
		T.check(clearRoom(run, a, 60), "dgfix party: (setup) room 1 cleared", tostring(run.State))
		local door2 = doorOf(run)
		run.Members[b.UserId].Downed = true
		press(a, door2)
		press(b, door2)
		advance(1)
		T.check(run.Room == 1 and enters.n == 1 and run.Confirm[b.UserId] == true, "dgfix party: a Downed member's E counts, and the group still waits for the third")
		mark = K.logSize()
		request(c, "Quit")
		advance(0.1)
		T.check(#msgs(a, mark, "Fade") == 1 and run.Members[c.UserId].Left == true, "dgfix party: the third member leaving mid-wait starts the transit for the rest")
		advance(0.6)
		T.check(enters.n == 2 and run.Room == 2 and #members(run) == 2, "dgfix party: ...into room 2, once (x" .. enters.n .. ")")
		-- 4. a late joiner must press before the group moves on
		crossThreshold(run, a)
		T.check(clearRoom(run, a, 60), "dgfix party: (setup) room 2 cleared")
		local door3 = doorOf(run)
		toPad(late)
		request(late, "Join", a.UserId)
		T.check(runOf(late) == run and #members(run) == 3, "dgfix party: (setup) a late joiner enters in room 2's corridor")
		mark = K.logSize()
		press(a, door3)
		press(b, door3)
		advance(1)
		local view = lastRun(a, mark)
		T.check(run.Room == 2 and enters.n == 2 and view and view.NeedConfirm == 1, "dgfix party: the late joiner's E is still missing (NeedConfirm 1)")
		press(late, door3)
		advance(0.6)
		T.check(enters.n == 3 and run.Room == 3, "dgfix party: the late joiner's E moves the group into room 3 (x" .. enters.n .. ")")
		enters.restore()
		cleanup(all)
	end)

	------------------------------------------------------------------------------------------------
	S.dgfix_flow_floor = scenario("dgfix_flow_floor", function()
		if not ready("dgfix_flow_floor") then
			return
		end
		local dgs, bs, d = DGS(), BS(), D()
		local p = newPlayer("DgfFloor", 30)
		DS().MutateDungeon(p, function(rec)
			rec.Best = math.max(tonumber(rec.Best) or 0, 1)
		end)
		toPad(p)
		request(p, "Solo", 2)
		local run = runOf(p)
		if not T.check(run ~= nil and run.Floor == 2, "dgfix floor: (setup) a solo floor-2 run") then
			cleanup({ p })
			return
		end
		local waves = {}
		local realSpawn = bs.SpawnWave
		bs.SpawnWave = function(battleId, pets, opts)
			waves[#waves + 1] = { room = run.Room, wave = type(opts) == "table" and opts.Wave or nil }
			return realSpawn(battleId, pets, opts)
		end
		local function wavesOfRoom(room)
			local out = {}
			for _, w in ipairs(waves) do
				if w.room == room then
					out[#out + 1] = w.wave
				end
			end
			return out
		end
		local function checkCentre(room, label)
			local ri = run.Pocket.Rooms[room]
			local b = battleOf(run.Battle)
			local mark0 = run.FightMark
			local start = startOf(p, mark0)
			local centre = b and b.Zone and b.Zone.CFrame.Position
			local top = ri and centre and floorTop(ri, centre)
			local fy = ri and ri.Zone and ri.Zone:GetAttribute("FloorY")
			T.check(centre and top and math.abs(centre.Y - top) <= 0.5, "dgfix floor: " .. label .. ": the encounter centre is on the floor (|dy| <= 0.5)",
				centre and top and string.format("dy %.2f", centre.Y - top) or "no zone")
			T.check(start and start.Zone and typeof(start.Zone.CFrame) == "CFrame" and top and math.abs(start.Zone.CFrame.Position.Y - top) <= 0.5,
				"dgfix floor: " .. label .. ": the Start payload's Zone.CFrame (where the client draws the enemies) is on the floor")
			T.check(type(fy) == "number" and top and math.abs(fy - top) <= 0.5, "dgfix floor: " .. label .. ": the zone's FloorY attribute is the floor top", tostring(fy))
			T.check(b and b.Zone.Part == ri.Zone and ri.Zone.Position.Y > top + 4, "dgfix floor: " .. label .. ": the NC_BattleZone part stays the presence box above the floor")
		end
		pressAll(run)
		T.check(run.Room == 1 and run.Phase == "Threshold", "dgfix floor: (setup) room 1")
		run.FightMark = K.logSize()
		crossThreshold(run, p)
		T.check(run.State == "Fight", "dgfix floor: (setup) room 1's fight")
		checkCentre(1, "wave room 1")
		T.check(clearRoom(run, p, 90), "dgfix floor: (setup) room 1 cleared", tostring(run.State))
		local w1 = wavesOfRoom(1)
		T.check(#w1 == 2 and w1[1] == 1 and w1[2] == 2, "dgfix floor: room 1 of floor 2 spawned waves 1 and 2 (Dungeon.Waves[1])", table.concat(w1, ","))
		local waveEvents = 0
		for _, e in ipairs(K.remotesFor("BattleState", p.UserId, run.FightMark)) do
			if e.args[1] == "Events" and type(e.args[2]) == "table" then
				for _, ev in ipairs(e.args[2]) do
					if ev.type == "Wave" and tonumber(ev.index) == 2 and type(ev.units) == "table" and #ev.units >= 1 then
						waveEvents = waveEvents + 1
					end
				end
			end
		end
		T.check(waveEvents >= 1, "dgfix floor: wave 2 reached the client as a Wave event with its units")
		-- room 3 (3 waves) and the boss room (white-box jumps, as smoke_p5_dungeon.lua's intoBossRoom)
		dgs.Dg.enterRoom(run, 3)
		advance(0.3)
		crossThreshold(run, p)
		T.check(run.State == "Fight" and run.Room == 3 and clearRoom(run, p, 120), "dgfix floor: (setup) room 3 fought and cleared")
		local w3 = wavesOfRoom(3)
		T.check(#w3 == 3 and w3[3] == 3, "dgfix floor: room 3 of floor 2 spawned 3 waves (Dungeon.Waves[3])", table.concat(w3, ","))
		dgs.Dg.enterRoom(run, 4)
		advance(0.3)
		run.FightMark = K.logSize()
		crossThreshold(run, p)
		T.check(run.State == "Fight" and run.Room == 4, "dgfix floor: (setup) the boss room's fight")
		checkCentre(4, "boss room")
		T.check(clearRoom(run, p, 120) and run.State == "Corridor" and run.Room == 4, "dgfix floor: (setup) boss and escort beaten", tostring(run.State))
		local w4 = wavesOfRoom(4)
		T.check(#w4 == 2, "dgfix floor: the boss room spawned the boss and its escort", table.concat(w4, ","))
		-- the treasure: E at the boss room's exit, no timer
		advance((d.Intermission or 2) + (d.DoorTime or 12) + 5)
		T.check(run.State == "Corridor" and run.Room == 4, "dgfix floor: after the boss no timer moves the member to the treasure")
		local exitPrompt = dgs.Dg.nextDoor(run)
		T.check(exitPrompt ~= nil and exitPrompt == run.Pocket.Rooms[4].NextPrompt and exitPrompt.ObjectText == "Treasure" and exitPrompt.Enabled == true,
			"dgfix floor: the boss room's exit offers EnterPrompt 'Treasure'")
		if exitPrompt then
			local mark = K.logSize()
			press(p, exitPrompt, 3)
			T.check(#msgs(p, mark, "Fade") == 1 and run.State == "Corridor", "dgfix floor: E at the exit fades first")
			advance(0.6)
			local tr = run.Pocket.Rooms[5]
			T.check(run.State == "Treasure" and tr and (pos(p) - tr.Spawns[1].Position).Magnitude < 8 and run.Chests[p.UserId] == "Closed",
				"dgfix floor: ...then the member stands in the treasure alcove with a closed chest")
			advance(1)
			T.check(run.State == "Treasure", "dgfix floor: the treasure stays (no second transit)")
		end
		bs.SpawnWave = realSpawn
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

	local function req(key)
		local inst = Mock.GetPath(ROOTS[key:match("^(%a+)/")] .. "/" .. key:gsub("^%a+/", ""))
		local ok, mod = pcall(require, inst)
		return ok and type(mod) == "table" and mod or nil
	end
	local function pg()
		return game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
	end
	local function find(root, name)
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end
	local function sent(mark)
		return #KC.serverCalls("DungeonRequest", mark)
	end

	S.client_dgfix_flow = guarded("client_dgfix_flow", function()
		local DC = (KC.M and KC.M.DungeonController) or req("client/Controllers/DungeonController")
		if not T.check(DC ~= nil, "dgfix client: DungeonController loads") then
			return
		end
		pcall(DC.Init)
		local UIS = game:GetService("UserInputService")
		UIS.TouchEnabled = false
		UIS.KeyboardEnabled = true
		UIS.MouseEnabled = true
		local LP = game:GetService("Players").LocalPlayer
		LP:SetAttribute("InMatch", false)
		LP:SetAttribute("InBattle", "D77")
		pcall(DC.Close)
		KC.advance(0.3)
		local me = LP.UserId
		local run = { RunId = "D77", Floor = 2, Name = "Stone Halls", Element = "Earth", Room = 0, RoomCount = 4, Wave = 0, Waves = 0, State = "Hall",
			Members = { { UserId = me, Name = LP.Name }, { UserId = 601, Name = "Ava" }, { UserId = 602, Name = "Sam" } },
			Confirmed = {}, NeedConfirm = 3, EnterOpen = true, Next = 1, Joinable = true }
		local mark = #Mock.RemoteLog
		KC.toClient("DungeonState", "Run", run)
		KC.advance(0.6)
		local rg = pg():FindFirstChild("NimbusDungeonRun")
		local card = rg and rg:FindFirstChild("RunCard")
		local status = card and find(card, "Status")
		T.check(status and status.Text == "Go to the door and press E", "dgfix client: at an open door the side card says 'Go to the door and press E'", status and status.Text)
		T.check(DC.GetState().Door == "press", "dgfix client: GetState().Door = press")
		run.Confirmed = { me }
		run.NeedConfirm = 2
		KC.toClient("DungeonState", "Run", run)
		KC.advance(0.6)
		T.check(status and status.Text == "Waiting for 2 more (Ava, Sam)", "dgfix client: after my E: 'Waiting for 2 more (Ava, Sam)'", status and status.Text)
		run.Confirmed = { me, 601 }
		run.NeedConfirm = 1
		KC.toClient("DungeonState", "Run", run)
		KC.advance(0.4)
		T.check(status and status.Text == "Waiting for 1 more (Sam)", "dgfix client: 'Waiting for 1 more (Sam)'", status and status.Text)
		-- the fade: appears, holds until the next room's Run payload, clears
		local fg = pg():FindFirstChild("NimbusDungeonFade")
		local frame = fg and fg:FindFirstChild("Fade")
		local hud = pg():FindFirstChild("NimbusHud")
		local notify = pg():FindFirstChild("NimbusNotify")
		T.check(fg and fg:IsA("ScreenGui") and fg.IgnoreGuiInset == true and fg.DisplayOrder > 12 and (not hud or fg.DisplayOrder > hud.DisplayOrder) and (not notify or fg.DisplayOrder < notify.DisplayOrder) and fg.DisplayOrder < 30,
			"dgfix client: the fade has its own ScreenGui (IgnoreGuiInset, DisplayOrder above the HUD / run card, below Notify)", fg and tostring(fg.DisplayOrder))
		T.check(frame and frame:IsA("Frame") and (fg.Enabled == false or frame.Visible == false), "dgfix client: the overlay is hidden while no fade runs")
		run.Transit = true
		run.EnterOpen = false
		run.Confirmed, run.NeedConfirm = {}, 0
		KC.toClient("DungeonState", "Run", run)
		KC.toClient("DungeonState", "Fade", { Out = 0.45, Hold = 0.35, In = 0.45, Room = 1 })
		KC.advance(0.1)
		local sz, col = frame and frame.Size, frame and frame.BackgroundColor3
		T.check(frame and fg.Enabled == true and frame.Visible == true and sz.X.Scale == 1 and sz.Y.Scale == 1 and sz.X.Offset == 0 and sz.Y.Offset == 0 and col.R == 0 and col.G == 0 and col.B == 0,
			"dgfix client: 'Fade' shows one black full-screen Frame")
		KC.advance(0.5)
		T.check(frame and frame.BackgroundTransparency <= 0.05 and DC.GetState().Fade ~= nil, "dgfix client: black after Out", frame and tostring(frame.BackgroundTransparency))
		KC.advance(0.6)
		T.check(frame and frame.Visible == true and frame.BackgroundTransparency <= 0.05, "dgfix client: it holds while the room has not changed yet")
		run.State, run.Phase, run.Room, run.Transit = "Corridor", "Threshold", 1, false
		KC.toClient("DungeonState", "Run", run)
		KC.advance(0.25)
		-- (the mock's tweens jump to their goal when they complete: the phase tells that the fade back in started)
		T.check(DC.GetState().Fade == "In" and frame and frame.Visible == true, "dgfix client: the next room's Run payload starts the fade back in", tostring(DC.GetState().Fade))
		KC.advance(0.6)
		T.check(frame and frame.Visible == false and fg.Enabled == false and DC.GetState().Fade == nil, "dgfix client: the overlay clears after In")
		T.check(status and status.Text == "Walk into the room to start the fight", "dgfix client: room 1's status after the fade", status and status.Text)
		-- the safety clear: a Fade with no room change still clears within FADE_SAFETY (wave 6: 3 -> 6 s, the black waits
		-- for a room payload that queued behind a big replication)
		KC.toClient("DungeonState", "Fade", { Out = 0.45, Hold = 0.35, In = 0.45 })
		KC.advance(0.6)
		T.check(frame and frame.Visible == true, "dgfix client: (setup) a second fade with no room change")
		KC.advance(5.6)
		T.check(frame and frame.Visible == false and fg.Enabled == false, "dgfix client: the 6 s safety clear never leaves the screen black")
		-- junk Fade values are clamped; End clears at once
		KC.toClient("DungeonState", "Fade", { Out = 1e9, Hold = -5, In = 0 / 0 })
		KC.advance(0.2)
		KC.toClient("DungeonState", "End", { Floor = 2, Name = "Stone Halls", Cleared = false, Reason = "Quit", Room = 1, Totals = { Cash = 0, Tokens = 0, Xp = 0, Gems = 0 } })
		KC.advance(0.1)
		T.check(frame and frame.Visible == false and fg.Enabled == false, "dgfix client: End clears the fade at once")
		T.eq(sent(mark), 0, "dgfix client: the door / fade flow sends nothing to the server")
		LP:SetAttribute("InBattle", nil)
		KC.advance(0.4)
		KC.flushErrors("client_dgfix_flow")
	end)
	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
