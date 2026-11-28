-- smoke_match_guard.lua: the obby finish's anti-cheat (playtest 2026-11-28 C22: a client teleport onto the finish pad won
-- Easy in 0:59; MatchService.markFinished checked membership, the state and HP only). Server world, booted.
--   guard_finish_teleport  a teleport straight onto the finish never finishes (refused once in the log and a toast); the
--                          same player wins after every checkpoint in order
--   guard_finish_order     a skipped checkpoint keeps the player's own trail (and the team's) short; taking it later works
--   guard_finish_time      every checkpoint in order but under the course's shortest honest time is refused; once the
--                          clock is past it the finish counts; the floor is far under the time limit on every difficulty
--   guard_finish_respawn   a player who dies mid-run comes back at the team checkpoint (the server placed them) and finishes
--                          with the team
--   guard_finish_party     a member who stayed at the start cannot finish on the team's progress; a void fall brings them to
--                          the team checkpoint, from where the finish counts
-- Plain Lua 5.1 syntax only.

local K = _G.K
local T = K.T
local guarded = K.guarded
local fmt = string.format
local config = K.config
local advance = K.advance
local waitFor = K.waitFor
local hum, root = K.hum, K.root
local flushErrors, flushWarnings = K.flushErrors, K.flushWarnings
local freshPlayers, removePlayers = K.freshPlayers, K.removePlayers
local logSize, notified = K.logSize, K.notified
local needBoot = K.needBoot
local MS, DS = K.MS, K.DS
local startMatch, toPlaying, endAllMatches = K.startMatch, K.toPlaying, K.endAllMatches

local S = {}
local ALLOWED = { "finish refused" } -- the guard's own log line

local function padTop(part)
	return part.Position + Vector3.new(0, part.Size.Y / 2 + 3.5, 0)
end

local function finishTop(m)
	return padTop(m.Course.Finish)
end

-- warn() lines of the guard since `mark` (an index into Mock.Output)
local function refusalsSince(mark, player)
	local n = 0
	for i = mark + 1, #Mock.Output do
		local o = Mock.Output[i]
		if o.kind == "warn" and o.text:find("finish refused", 1, true) and (player == nil or o.text:find(player.Name, 1, true)) then
			n = n + 1
		end
	end
	return n
end

local function trailOf(m, p)
	local rec = m.Recs[p]
	return rec and rec.Checkpoint or -1
end

-- walks every checkpoint in order (a teleport onto each pad, the 4 Hz poll between)
local function walkCheckpoints(m, players, from, to)
	for i = from or 1, to or m.MaxCheckpoint do
		local cp = m.Course.Checkpoints[i]
		if cp then
			for _, p in ipairs(players) do
				Mock.Teleport(p, padTop(cp.Part))
			end
			advance(0.6)
		end
	end
end

local function begin(name, count)
	if not needBoot() then
		return nil
	end
	local players = freshPlayers(count or 1, name)
	local m = startMatch("Easy", players)
	if not T.check(m ~= nil, name .. ": an Easy match starts") then
		removePlayers(players)
		return nil
	end
	toPlaying(m)
	advance(0.5)
	return m, players
end

local function finish(name, m, players)
	advance(config().Match.EndScreenSeconds + 1.5)
	endAllMatches(players)
	removePlayers(players)
	flushErrors(name)
	flushWarnings(name, ALLOWED)
end

----------------------------------------------------------------------------------------------------
S.guard_finish_teleport = guarded("guard_finish_teleport", function()
	local m, players = begin("TpWin", 1)
	if not m then
		return
	end
	local a = players[1]
	T.check(m.MaxCheckpoint >= 2 and type(m.MinSeconds) == "number" and m.MinSeconds > 0, "guard: the course has checkpoints and a minimum time", fmt("%d checkpoints, min %.1f s", m.MaxCheckpoint, m.MinSeconds or -1))
	T.eq(trailOf(m, a), 0, "guard: a player's own trail starts at 0")
	local mark, out = logSize(), #Mock.Output
	-- the exploit: straight onto the finish pad
	Mock.Teleport(a, finishTop(m))
	advance(2.0)
	T.eq(m.State, "Playing", "guard: a teleport onto the finish does not end the match")
	T.check(m.Finished[a] ~= true, "guard: ...the player is not marked Finished")
	T.check(not (root(a).Anchored or hum(a).WalkSpeed == 0), "guard: ...and is not frozen on the pad")
	T.eq(refusalsSince(out, a), 1, "guard: the refusal is logged once ([MatchService] finish refused ...), not every poll")
	T.check(notified(a, "checkpoint", "bad", mark) ~= nil, "guard: the player is told to reach every checkpoint first (one bad toast)")
	-- standing there longer changes nothing
	advance(2.0)
	T.eq(m.State, "Playing", "guard: standing on the finish keeps the match playing")
	T.eq(refusalsSince(out, a), 1, "guard: ...with no second log line")
	-- the honest way: every checkpoint in order, then the finish, past the course's minimum time
	walkCheckpoints(m, { a })
	T.eq(m.Checkpoint, m.MaxCheckpoint, "guard: the team reached every checkpoint in order")
	T.eq(trailOf(m, a), m.MaxCheckpoint, "guard: ...and so did the player's own trail")
	m.StartedAt = m.StartedAt - 120 -- a teleport run is quicker than the floor; the clock says the run took long enough
	Mock.Teleport(a, finishTop(m))
	local won = waitFor(function()
		return m.State == "Ended"
	end, 3)
	T.check(won and m.Won == true and m.Reason == "victory", "guard: after the checkpoints the same player wins", tostring(m.State) .. " " .. tostring(m.Reason))
	finish("guard_finish_teleport", m, players)
end)

----------------------------------------------------------------------------------------------------
S.guard_finish_order = guarded("guard_finish_order", function()
	local m, players = begin("OrderWin", 1)
	if not m then
		return
	end
	local a = players[1]
	if not T.check(m.MaxCheckpoint >= 3, "guard order: the course has at least three checkpoints", tostring(m.MaxCheckpoint)) then
		finish("guard_finish_order", m, players)
		return
	end
	local out = #Mock.Output
	-- 1, then 3 (2 skipped), then the rest
	walkCheckpoints(m, { a }, 1, 1)
	walkCheckpoints(m, { a }, 3, m.MaxCheckpoint)
	T.eq(m.Checkpoint, 1, "guard order: the team's checkpoint stays at 1 when 2 is skipped (bug #8 rule)")
	T.eq(trailOf(m, a), 1, "guard order: the player's own trail stays at 1 too")
	m.StartedAt = m.StartedAt - 120
	Mock.Teleport(a, finishTop(m))
	advance(1.5)
	T.eq(m.State, "Playing", "guard order: the finish is refused with a checkpoint skipped")
	T.eq(refusalsSince(out, a), 1, "guard order: ...and logged once")
	-- back for 2, then on in order
	walkCheckpoints(m, { a }, 2, m.MaxCheckpoint)
	T.eq(m.Checkpoint, m.MaxCheckpoint, "guard order: taking 2 and then the rest completes the team's checkpoints")
	T.eq(trailOf(m, a), m.MaxCheckpoint, "guard order: ...and the player's trail")
	Mock.Teleport(a, finishTop(m))
	local won = waitFor(function()
		return m.State == "Ended"
	end, 3)
	T.check(won and m.Won == true, "guard order: the finish counts once every checkpoint was taken in order")
	finish("guard_finish_order", m, players)
end)

----------------------------------------------------------------------------------------------------
S.guard_finish_time = guarded("guard_finish_time", function()
	if not needBoot() then
		return
	end
	local Config = config()
	-- the floor on every difficulty: well under the time limit (an honest run is several times slower than the floor; the
	-- floor must never be in an honest run's way)
	local floors = T.tally("guard time: the course's minimum time is under 10 % of its time limit on every difficulty")
	for _, diff in ipairs(Config.Difficulties) do
		local players = freshPlayers(1, "Floor")
		local m = startMatch(diff.Id, players)
		if m then
			local limit = diff.TimeLimit
			floors:case(type(m.MinSeconds) == "number" and m.MinSeconds > 0 and m.MinSeconds < limit * 0.1,
				fmt("%s: %d checkpoints, min %.1f s of a %d s limit", diff.Id, m.MaxCheckpoint, m.MinSeconds or -1, limit))
			T.info(fmt("guard time: %s floor %.1f s (limit %d s, %d checkpoints)", diff.Id, m.MinSeconds or -1, limit, m.MaxCheckpoint))
		else
			floors:case(false, diff.Id .. ": no match started")
		end
		endAllMatches(players)
		removePlayers(players)
	end
	floors:report()
	-- every checkpoint in order, but at once: under the floor the finish waits; past it, it counts
	local m, players = begin("FastWin", 1)
	if not m then
		return
	end
	local a = players[1]
	local out = #Mock.Output
	walkCheckpoints(m, { a })
	T.eq(trailOf(m, a), m.MaxCheckpoint, "guard time: the trail is complete")
	m.StartedAt = Mock.Clock.now -- the run has just begun as far as the clock knows
	Mock.Teleport(a, finishTop(m))
	advance(0.6)
	T.eq(m.State, "Playing", "guard time: a complete trail under the course's minimum time is refused")
	T.eq(refusalsSince(out, a), 1, "guard time: ...and logged once")
	m.StartedAt = m.StartedAt - m.MinSeconds - 1
	local won = waitFor(function()
		return m.State == "Ended"
	end, 3)
	T.check(won and m.Won == true, "guard time: once the clock is past the minimum the finish counts (the player did not move)")
	finish("guard_finish_time", m, players)
end)

----------------------------------------------------------------------------------------------------
S.guard_finish_respawn = guarded("guard_finish_respawn", function()
	local m, players = begin("RespawnWin", 2)
	if not m then
		return
	end
	local a, b = players[1], players[2]
	if not T.check(m.MaxCheckpoint >= 3, "guard respawn: the course has at least three checkpoints", tostring(m.MaxCheckpoint)) then
		finish("guard_finish_respawn", m, players)
		return
	end
	walkCheckpoints(m, { a, b }, 1, 2)
	T.eq(m.Checkpoint, 2, "guard respawn: the team is at checkpoint 2")
	T.eq(trailOf(m, b), 2, "guard respawn: b's trail is at 2")
	-- a runs ahead to 3; b dies and comes back at the team checkpoint, which the server chose
	walkCheckpoints(m, { a }, 3, 3)
	T.eq(m.Checkpoint, 3, "guard respawn: a took checkpoint 3 alone")
	local old = b.Character
	Mock.Kill(b)
	T.check(waitFor(function()
		return b.Character ~= nil and b.Character ~= old and hum(b) ~= nil and hum(b).Health > 0
	end, 12), "guard respawn: b's character is replaced")
	advance(1.2)
	local cp3 = m.Course.Checkpoints[3]
	T.check(K.distance(root(b).Position, cp3.SpawnCFrame.Position) <= 14, "guard respawn: b respawns at the team checkpoint (3)", fmt("%.1f studs", K.distance(root(b).Position, cp3.SpawnCFrame.Position)))
	T.eq(trailOf(m, b), 3, "guard respawn: the server's placement counts for b's trail")
	-- both climb the rest and finish
	walkCheckpoints(m, { a, b }, 4, m.MaxCheckpoint)
	m.StartedAt = m.StartedAt - 120
	Mock.Teleport(a, finishTop(m))
	advance(0.6)
	T.eq(m.Finished[a], true, "guard respawn: a finishes")
	Mock.Teleport(b, finishTop(m))
	local won = waitFor(function()
		return m.State == "Ended"
	end, 3)
	T.check(won and m.Won == true and m.Finished[b] == true, "guard respawn: b finishes after the respawn and the team wins", tostring(m.State))
	finish("guard_finish_respawn", m, players)
end)

----------------------------------------------------------------------------------------------------
S.guard_finish_party = guarded("guard_finish_party", function()
	local m, players = begin("PartyWin", 2)
	if not m then
		return
	end
	local a, b = players[1], players[2]
	K.waitNotInvulnerable(b)
	local out = #Mock.Output
	-- a does the whole climb; b never leaves the start
	walkCheckpoints(m, { a })
	T.eq(m.Checkpoint, m.MaxCheckpoint, "guard party: a took every checkpoint for the team")
	T.eq(trailOf(m, b), 0, "guard party: b's own trail is still 0 (the team's progress is not theirs)")
	m.StartedAt = m.StartedAt - 120
	Mock.Teleport(b, finishTop(m))
	advance(1.5)
	T.check(m.Finished[b] ~= true and m.State == "Playing", "guard party: b teleporting onto the finish is refused")
	T.eq(refusalsSince(out, b), 1, "guard party: ...and logged once for b")
	-- b falls into the void: the server brings them to the team checkpoint, so the last leg is honest from there
	local start = m.Course.StartCFrame.Position
	Mock.Teleport(b, Vector3.new(start.X, m.Course.KillY - 30, start.Z))
	advance(1.0)
	local last = m.Course.Checkpoints[m.MaxCheckpoint]
	T.check(K.distance(root(b).Position, last.SpawnCFrame.Position) <= 14, "guard party: the void rescue puts b at the team checkpoint", fmt("%.1f studs", K.distance(root(b).Position, last.SpawnCFrame.Position)))
	T.eq(trailOf(m, b), m.MaxCheckpoint, "guard party: ...which counts for b's trail")
	Mock.Teleport(a, finishTop(m))
	advance(0.6)
	Mock.Teleport(b, finishTop(m))
	local won = waitFor(function()
		return m.State == "Ended"
	end, 3)
	T.check(won and m.Won == true and m.Finished[b] == true, "guard party: from the team checkpoint b's finish counts and the team wins", tostring(m.State))
	finish("guard_finish_party", m, players)
end)

return S
