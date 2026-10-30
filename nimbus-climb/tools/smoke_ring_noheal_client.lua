-- smoke_ring_noheal_client.lua: the Champion Ring no-heal rule on the client (HUD cleanup plan, Task 4 review fix).
-- Loaded by tools/smoke.py in the CLIENT world.
--   client_ringnh_card  BattleController's run card line (Ring.ResultTitle): a run that ends because the whole team
--                       fainted (BattleService sends End { Outcome = "Left", Reason = "Fainted" } between two rounds)
--                       says the team fainted, never "you left"; a real leave / forfeit still says "you left", a loss
--                       still names the champion, a timeout the clock
-- Pure: the TESTS ONLY export BattleController._Ring, a fake battle record. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
local IS_SERVER = game:GetService("RunService"):IsServer()

if IS_SERVER then
	return S
end

local function moduleAt(path)
	local ok, inst = pcall(Mock.GetPath, path)
	if not ok or not inst then
		return nil
	end
	local ok2, mod = pcall(require, inst)
	return ok2 and type(mod) == "table" and mod or nil
end

-- the final End of a run (the shape RingRun.endRun sends between two rounds)
local function finalEnd(round, extra)
	local p = { Mode = "Ring", Outcome = "Loss", Won = false, Spectator = false, Reason = "Wipe",
		Rewards = { Won = false, Final = true, Round = round, Cash = 0, Xp = 0, Run = { Wins = round - 1, Round = round, Start = 1, Best = round - 1 } } }
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	return p
end

S.client_ringnh_card = guarded("client_ringnh_card", function()
	local BCtl = moduleAt(ROOTS.client .. "/Controllers/BattleController")
	local Ring = BCtl and BCtl._Ring
	if not T.check(type(Ring) == "table" and type(Ring.ResultTitle) == "function", "ring no-heal card: BattleController._Ring.ResultTitle loads") then
		return
	end
	local B = { Mode = "Ring", Round = 4 }
	local title, _, line = Ring.ResultTitle(B, finalEnd(4, { Outcome = "Left", Reason = "Fainted" }), "")
	T.check(title == "RUN OVER" and type(line) == "string" and line:find("whole team fainted after round 4", 1, true) ~= nil and line:find("left", 1, true) == nil,
		"ring no-heal card: End { Outcome Left, Reason Fainted } says the whole team fainted (never 'you left')", tostring(line))
	local _, _, left = Ring.ResultTitle(B, finalEnd(4, { Outcome = "Left", Reason = "Left" }), "")
	local _, _, forfeit = Ring.ResultTitle(B, finalEnd(4, { Outcome = "Left", Reason = "Forfeit" }), "")
	T.check(tostring(left):find("you left after round 4", 1, true) ~= nil and tostring(forfeit):find("you left after round 4", 1, true) ~= nil,
		"ring no-heal card: a real leave / forfeit still says 'you left after round N'", tostring(left) .. " | " .. tostring(forfeit))
	local _, _, lost = Ring.ResultTitle(B, finalEnd(4), "")
	local _, _, timeout = Ring.ResultTitle(B, finalEnd(4, { Reason = "Timeout" }), "")
	T.check(tostring(lost):find("the champion won round 4", 1, true) ~= nil and tostring(timeout):find("time ran out in round 4", 1, true) ~= nil,
		"ring no-heal card: a lost round names the champion, a timeout the clock", tostring(lost) .. " | " .. tostring(timeout))
	local recTitle = Ring.ResultTitle(B, finalEnd(9, { Outcome = "Left", Reason = "Fainted", Rewards = { Final = true, Round = 9, Run = { Wins = 8, Round = 9, Record = 8, Best = 8 } } }), "")
	T.check(recTitle == "NEW RECORD!", "ring no-heal card: a fainted run that set a record still says NEW RECORD!", tostring(recTitle))
end)

return S
