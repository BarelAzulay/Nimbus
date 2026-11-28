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
-- Review round (C22): the floor came from 1.5 x DashSpeed (3.6-4.9 s on Easy: a pad-by-pad teleport won after 4.3 s) and the
-- Touched handlers trusted the event alone (touches reported from the start platform won Saint).
--   guard_finish_time      (also) the floor on every difficulty has a LOWER bound (at least the straight chain at 2.5 x the
--                          best run + dash pace) and an upper one (an honest-pace stand-in on the straight chain, a cannon
--                          leg at its flight time, is never under it); the refusal says how long to wait; an accepted
--                          finish close to the floor is logged ("fast finish")
--   guard_finish_padhop    on every difficulty a pad-by-pad teleport run (0.35 s a pad, the clock untouched) waits on the
--                          finish until the floor, then finishes on its own, never before the lower bound above
--   guard_finish_touch     touches reported for every pad and the finish with the character on the start platform mark
--                          nothing and never finish; a touch with the root at a pad's rim (outside the poll's window) counts
--                          for the pad and for the finish
--   guard_finish_standin   on every difficulty a stand-in moving along the straight chain at the honest pace wins on arrival
--   guard_finish_toast     the refusal toast names the missing checkpoint (also when the team has it) and comes back every
--                          few seconds while the player stays on the finish; the log line stays once
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
local ALLOWED = { "finish refused", "fast finish" } -- the guard's own log lines

local function padTop(part)
	return part.Position + Vector3.new(0, part.Size.Y / 2 + 3.5, 0)
end

local function finishTop(m)
	return padTop(m.Course.Finish)
end

-- warn() lines of the guard containing `needle` since `mark` (an index into Mock.Output)
local function logLinesSince(mark, player, needle)
	local n = 0
	for i = mark + 1, #Mock.Output do
		local o = Mock.Output[i]
		if o.kind == "warn" and o.text:find(needle, 1, true) and (player == nil or o.text:find(player.Name, 1, true)) then
			n = n + 1
		end
	end
	return n
end

local function refusalsSince(mark, player)
	return logLinesSince(mark, player, "finish refused")
end

-- Notify toasts to `player` since `mark` (an index into Mock.RemoteLog) whose text contains `needle`
local function toastsSince(mark, player, needle, kind)
	local n = 0
	for _, e in ipairs(K.remotesFor("Notify", player.UserId, mark)) do
		if tostring(e.args[1]):find(needle, 1, true) and (kind == nil or e.args[2] == kind) then
			n = n + 1
		end
	end
	return n
end

local function trailOf(m, p)
	local rec = m.Recs[p]
	return rec and rec.Checkpoint or -1
end

-- the first checkpoint index after `from` on this course
local function nextPad(m, from)
	for i = from + 1, m.MaxCheckpoint do
		if m.Course.Checkpoints[i] then
			return i
		end
	end
	return nil
end

-- the best run + dash average a climber can hold (Config.Physics: RunSpeed, a dash of DashSpeed for DashDuration every
-- DashCooldown), worked out here on its own (not read from MatchService)
local function honestPace()
	local ph = config().Physics
	return ((ph.DashCooldown - ph.DashDuration) * ph.RunSpeed + ph.DashDuration * ph.DashSpeed) / ph.DashCooldown
end

-- the course's straight chain: start spot -> every checkpoint pad -> the finish pad; -> horizontal length, the 3D points
-- (pad tops) a stand-in walks through
local function chainOf(m)
	local points = { m.Course.StartCFrame.Position }
	for i = 1, m.MaxCheckpoint do
		local cp = m.Course.Checkpoints[i]
		if cp then
			points[#points + 1] = padTop(cp.Part)
		end
	end
	points[#points + 1] = finishTop(m)
	local flat = 0
	for i = 2, #points do
		flat = flat + K.planar(points[i], points[i - 1])
	end
	return flat, points
end

-- the cannon legs of the layout: horizontal pad -> target spans and flight times
local function cannonLegs(m)
	local span, flight = 0, 0
	for _, step in ipairs((m.Layout and m.Layout.Steps) or {}) do
		local h = step.Hazard
		if step.Kind == "CannonPad" and type(h) == "table" and h.Target and h.Pos then
			span = span + K.planar(h.Target, h.Pos)
			flight = flight + (h.FlightTime or 0)
		end
	end
	return span, flight
end

-- an honest-pace stand-in's time: the straight chain at honestPace(), each cannon leg at its flight time instead
local function standinSeconds(m)
	local flat = chainOf(m)
	local span, flight = cannonLegs(m)
	return math.max(0, flat - span) / honestPace() + flight
end

-- the floor's lower bound: the straight chain at 2.5 x the honest pace (the old 1.5 x DashSpeed floor was 3.8 x)
local function lowerBound(m)
	return chainOf(m) / (2.5 * honestPace())
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
	-- (review) was notified(...) ~= nil, true for any answer since notified returns a boolean: now the exact toast
	T.eq(toastsSince(mark, a, fmt("Checkpoint %d first!", nextPad(m, 0)), "bad"), 1, "guard: the player is told which checkpoint to reach first (one bad toast in 2 s)")
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
	local mark = logSize()
	Mock.Teleport(a, finishTop(m))
	advance(1.5)
	T.eq(m.State, "Playing", "guard order: the finish is refused with a checkpoint skipped")
	T.eq(refusalsSince(out, a), 1, "guard order: ...and logged once")
	T.eq(toastsSince(mark, a, fmt("Checkpoint %d first!", nextPad(m, 1)), "bad"), 1, "guard order: ...and the toast names the skipped checkpoint (review)")
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
	-- (review) and it is high enough: a floor looser than the straight chain at 2.5 x the honest pace lets a pad-by-pad
	-- teleport through in a few seconds (the 1.5 x DashSpeed floor was 3.8 x); and an honest-pace stand-in is never under it
	local lows = T.tally("guard time: the floor is at least the straight chain at 2.5 x the best run + dash pace on every difficulty")
	local highs = T.tally("guard time: the floor is never above an honest-pace stand-in's time (straight chain at the run + dash pace, cannons at their flight time)")
	for _, diff in ipairs(Config.Difficulties) do
		local players = freshPlayers(1, "Floor")
		local m = startMatch(diff.Id, players)
		if m then
			local limit = diff.TimeLimit
			local low, standin = lowerBound(m), standinSeconds(m)
			local floor = type(m.MinSeconds) == "number" and m.MinSeconds or -1
			floors:case(floor > 0 and floor < limit * 0.1,
				fmt("%s: %d checkpoints, min %.1f s of a %d s limit", diff.Id, m.MaxCheckpoint, floor, limit))
			lows:case(floor >= low, fmt("%s: floor %.1f s, the chain at 2.5 x pace %.1f s", diff.Id, floor, low))
			highs:case(floor > 0 and floor <= standin, fmt("%s: floor %.1f s, the stand-in %.1f s", diff.Id, floor, standin))
			T.info(fmt("guard time: %s floor %.1f s (limit %d s, %d checkpoints; lower bound %.1f s, honest-pace stand-in %.1f s)", diff.Id, floor, limit, m.MaxCheckpoint, low, standin))
		else
			floors:case(false, diff.Id .. ": no match started")
			lows:case(false, diff.Id .. ": no match started")
			highs:case(false, diff.Id .. ": no match started")
		end
		endAllMatches(players)
		removePlayers(players)
	end
	floors:report()
	lows:report()
	highs:report()
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
	local mark = logSize()
	Mock.Teleport(a, finishTop(m))
	advance(0.6)
	T.eq(m.State, "Playing", "guard time: a complete trail under the course's minimum time is refused")
	T.eq(refusalsSince(out, a), 1, "guard time: ...and logged once")
	local waitToast = nil
	for _, e in ipairs(K.remotesFor("Notify", a.UserId, mark)) do
		local mm, ss = tostring(e.args[1]):match("^Finish opens in (%d+):(%d%d)$")
		if mm and e.args[2] == "bad" then
			waitToast = tonumber(mm) * 60 + tonumber(ss)
		end
	end
	T.check(toastsSince(mark, a, "Finish opens in", "bad") == 1 and waitToast ~= nil and waitToast >= math.floor(m.MinSeconds - 0.6) and waitToast <= math.ceil(m.MinSeconds),
		"guard time: ...the toast says how long to wait ('Finish opens in 0:ss', the floor's seconds), not 'checkpoint' (review)", fmt("%s s shown, floor %.1f s", tostring(waitToast), m.MinSeconds))
	T.eq(toastsSince(mark, a, "first!"), 0, "guard time: ...and does not send the player back for a checkpoint")
	local fast = #Mock.Output
	m.StartedAt = m.StartedAt - m.MinSeconds - 1
	local won = waitFor(function()
		return m.State == "Ended"
	end, 3)
	T.check(won and m.Won == true, "guard time: once the clock is past the minimum the finish counts (the player did not move)")
	T.eq(logLinesSince(fast, a, "fast finish"), 1, "guard time: ...a finish just past the floor is accepted and logged once ([MatchService] fast finish ...)")
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

----------------------------------------------------------------------------------------------------
-- (review) the reviewer's exploit in the game's own harness: one teleport onto each pad in order, then the finish, the
-- clock untouched. It must wait out the floor on every difficulty (and the floor must not be a few seconds).
S.guard_finish_padhop = guarded("guard_finish_padhop", function()
	if not needBoot() then
		return
	end
	local waits = T.tally("guard hop: a pad-by-pad teleport run (0.35 s a pad, the clock untouched) still waits on the finish 0.4 s before the floor, its trail complete, on every difficulty")
	local wins = T.tally("guard hop: ...it finishes on its own right after the floor (it only had to wait), never before the floor's lower bound")
	local logs = T.tally("guard hop: ...refused once in the log, accepted with one 'fast finish' line")
	for _, diff in ipairs(config().Difficulties) do
		local players = freshPlayers(1, "Hop")
		local m = startMatch(diff.Id, players)
		if m and toPlaying(m) then
			local a = players[1]
			local out = #Mock.Output
			for i = 1, m.MaxCheckpoint do
				local cp = m.Course.Checkpoints[i]
				if cp then
					Mock.Teleport(a, padTop(cp.Part))
					advance(0.35)
				end
			end
			Mock.Teleport(a, finishTop(m))
			local floor = m.MinSeconds or 0
			local wait = floor - 0.4 - (Mock.Clock.now - m.StartedAt)
			if wait > 0 then
				advance(wait)
			end
			local played = Mock.Clock.now - m.StartedAt
			waits:case(m.Finished[a] ~= true and m.State == "Playing" and trailOf(m, a) == m.MaxCheckpoint,
				fmt("%s: %.1f s played of a %.1f s floor, trail %d of %d, %s", diff.Id, played, floor, trailOf(m, a), m.MaxCheckpoint, tostring(m.State)))
			local at = nil
			waitFor(function()
				if m.Finished[a] == true then
					at = at or (Mock.Clock.now - m.StartedAt)
					return true
				end
				return m.State ~= "Playing"
			end, 3)
			local low = lowerBound(m)
			wins:case(at ~= nil and at >= floor and at <= floor + 1 and at >= low,
				fmt("%s: finished after %s s, floor %.1f s, lower bound %.1f s", diff.Id, at and fmt("%.2f", at) or "never", floor, low))
			logs:case(refusalsSince(out, a) == 1 and logLinesSince(out, a, "fast finish") == 1,
				fmt("%s: %d refusal lines, %d fast-finish lines", diff.Id, refusalsSince(out, a), logLinesSince(out, a, "fast finish")))
		else
			waits:case(false, diff.Id .. ": no match reached Playing")
			wins:case(false, diff.Id .. ": no match reached Playing")
			logs:case(false, diff.Id .. ": no match reached Playing")
		end
		endAllMatches(players)
		removePlayers(players)
	end
	waits:report()
	wins:report()
	logs:report()
	flushErrors("guard_finish_padhop")
	flushWarnings("guard_finish_padhop", ALLOWED)
end)

----------------------------------------------------------------------------------------------------
-- (review) the Touched handlers: an exploit client can report touches for its own parts from anywhere (firetouchinterest).
-- A touch counts only with the root at the pad; the 4 Hz poll's windows are 2 studs (team checkpoint) and 1 stud (finish)
-- past the edge, a touch's TOUCH_SLACK is 4, so a root 3 studs past the edge is taken by the touch alone.
S.guard_finish_touch = guarded("guard_finish_touch", function()
	local m, players = begin("TouchWin", 1)
	if not m then
		return
	end
	local a = players[1]
	local start = root(a).Position
	m.StartedAt = m.StartedAt - 120 -- the clock is not what stops this run
	local out = #Mock.Output
	-- the exploit: a touch reported for every pad in order, then for the finish, the character left on the start platform
	for i = 1, m.MaxCheckpoint do
		local cp = m.Course.Checkpoints[i]
		if cp then
			Mock.Touch(cp.Part, root(a))
			advance(0.3)
			Mock.Untouch(cp.Part, root(a))
		end
	end
	T.eq(trailOf(m, a), 0, "guard touch: touches reported for every pad from the start platform mark none of the player's trail")
	T.eq(m.Checkpoint, 0, "guard touch: ...nor the team's checkpoint")
	Mock.Touch(m.Course.Finish, root(a))
	advance(1.0)
	Mock.Untouch(m.Course.Finish, root(a))
	T.check(m.Finished[a] ~= true and m.State == "Playing", "guard touch: a finish touch reported from the start platform never finishes", tostring(m.State))
	T.check(K.distance(root(a).Position, start) < 1, "guard touch: (the character stayed on the start platform)", fmt("%.1f studs", K.distance(root(a).Position, start)))
	-- an honest touch at the first pad's rim: the poll does not take it for the team from there, the touch does
	local first = nextPad(m, 0)
	local cp = m.Course.Checkpoints[first]
	local hs = cp.Part.Size / 2
	Mock.Teleport(a, (cp.Part.CFrame * CFrame.new(hs.X + 3, hs.Y + 3, 0)).Position)
	advance(0.6)
	T.eq(m.Checkpoint, 0, "guard touch: (3 studs past the pad's edge the poll does not take it for the team)")
	Mock.Touch(cp.Part, root(a))
	advance(0.1)
	Mock.Untouch(cp.Part, root(a))
	T.eq(m.Checkpoint, first, "guard touch: a touch with the root at the pad's rim takes the checkpoint for the team")
	T.eq(trailOf(m, a), first, "guard touch: ...and the player's own trail has it")
	-- the rest in order, then the finish by a touch at its rim (the poll's window there is 1 stud)
	walkCheckpoints(m, { a }, first + 1, m.MaxCheckpoint)
	T.eq(trailOf(m, a), m.MaxCheckpoint, "guard touch: the trail is complete")
	local fin = m.Course.Finish
	local fh = fin.Size / 2
	Mock.Teleport(a, (fin.CFrame * CFrame.new(fh.X + 3, fh.Y + 3, 0)).Position)
	advance(0.6)
	T.check(m.Finished[a] ~= true, "guard touch: (3 studs past the finish's edge the poll does not finish)")
	Mock.Touch(fin, root(a))
	local won = waitFor(function()
		return m.State == "Ended"
	end, 2)
	Mock.Untouch(fin, root(a))
	T.check(won and m.Won == true, "guard touch: a touch with the root at the finish's rim finishes and wins", tostring(m.State))
	T.eq(refusalsSince(out, a), 0, "guard touch: (no refusal on the way: the far touches never reached the finish check)")
	finish("guard_finish_touch", m, players)
end)

----------------------------------------------------------------------------------------------------
-- (review) an honest-pace stand-in still wins: it moves along the straight chain (start -> each pad top -> the finish) at
-- the run + dash pace, a cannon leg counted at its flight time, and must finish on arrival on every difficulty, unlogged.
S.guard_finish_standin = guarded("guard_finish_standin", function()
	if not needBoot() then
		return
	end
	local wins = T.tally("guard stand-in: a climber on the straight chain at the honest pace (run + every dash, cannons at their flight time) finishes on arrival on every difficulty")
	local quiet = T.tally("guard stand-in: ...and is not logged as a fast finish (1.25 x the floor)")
	for _, diff in ipairs(config().Difficulties) do
		local players = freshPlayers(1, "Pace")
		local m = startMatch(diff.Id, players)
		if m and toPlaying(m) then
			local a = players[1]
			DS().GrantInvulnerability(a, 600) -- the hazards along the straight line are not what this checks
			local out = #Mock.Output
			local _, points = chainOf(m)
			local target = standinSeconds(m)
			local length = 0
			for i = 2, #points do
				length = length + (points[i] - points[i - 1]).Magnitude
			end
			local speed = length / math.max(target, 0.1)
			local dt = 0.1
			local pos, seg = points[1], 2
			Mock.Teleport(a, pos)
			while seg <= #points do
				local left = speed * dt
				while left > 0 and seg <= #points do
					local d = (points[seg] - pos).Magnitude
					if d <= left then
						pos = points[seg]
						left = left - d
						seg = seg + 1
					else
						pos = pos + (points[seg] - pos).Unit * left
						left = 0
					end
				end
				Mock.Teleport(a, pos)
				advance(dt)
			end
			local arrived = Mock.Clock.now - m.StartedAt
			local won = waitFor(function()
				return m.Finished[a] == true
			end, 0.6)
			wins:case(won and trailOf(m, a) == m.MaxCheckpoint,
				fmt("%s: arrived after %.1f s (stand-in %.1f s at %.1f studs/s along the chain), floor %.1f s, trail %d of %d", diff.Id, arrived, target, speed, m.MinSeconds or -1, trailOf(m, a), m.MaxCheckpoint))
			quiet:case(logLinesSince(out, a, "fast finish") == 0 and refusalsSince(out, a) == 0,
				fmt("%s: %d fast-finish, %d refusal lines", diff.Id, logLinesSince(out, a, "fast finish"), refusalsSince(out, a)))
		else
			wins:case(false, diff.Id .. ": no match reached Playing")
			quiet:case(false, diff.Id .. ": no match reached Playing")
		end
		endAllMatches(players)
		removePlayers(players)
	end
	wins:report()
	quiet:report()
	flushErrors("guard_finish_standin")
	flushWarnings("guard_finish_standin", ALLOWED)
end)

----------------------------------------------------------------------------------------------------
-- (review) the refusal toast: it names the checkpoint the player's own trail misses (the team HUD may already read 4/4)
-- and comes back every few seconds while they stay on the finish; the log line stays once per player
S.guard_finish_toast = guarded("guard_finish_toast", function()
	local m, players = begin("ToastWin", 2)
	if not m then
		return
	end
	local a, b = players[1], players[2]
	if not T.check(m.MaxCheckpoint >= 3, "guard toast: the course has at least three checkpoints", tostring(m.MaxCheckpoint)) then
		finish("guard_finish_toast", m, players)
		return
	end
	-- both take checkpoint 1, then a takes the rest alone
	walkCheckpoints(m, { a, b }, 1, 1)
	walkCheckpoints(m, { a }, 2, m.MaxCheckpoint)
	T.eq(m.Checkpoint, m.MaxCheckpoint, "guard toast: the team has every checkpoint (a took them)")
	T.eq(trailOf(m, b), 1, "guard toast: b's own trail ends at checkpoint 1")
	m.StartedAt = m.StartedAt - 120
	local want = fmt("Checkpoint %d first!", nextPad(m, 1))
	local mark, out = logSize(), #Mock.Output
	Mock.Teleport(b, finishTop(m))
	advance(2.0)
	T.eq(toastsSince(mark, b, want, "bad"), 1, "guard toast: b on the finish is told the checkpoint they missed ('" .. want .. "'), though the team has it")
	advance(5.0)
	T.eq(toastsSince(mark, b, want, "bad"), 2, "guard toast: ...and told again while they stay on the finish (every 4 s, not every poll)")
	T.eq(refusalsSince(out, b), 1, "guard toast: ...the log line stays once")
	T.eq(m.Finished[b] == true, false, "guard toast: (b is still not finished)")
	finish("guard_finish_toast", m, players)
end)

return S
