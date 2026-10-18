-- smoke_p4_fix_battle.lua: regression checks for the Phase 4 review fixes in BattleService (fix:battle). Server world
-- only (server_files of tools/smoke.py), booted, before the care block (the ring rounds advance the clock).
--   p4fixbat_forfeit  a BattleCommand("Forfeit") through the REAL remote between two ring rounds (the won round's
--                     battle is already Ended) ends the run cleanly: no battle left, Ring.Runs + 1, the win kept, the
--                     pocket freed (contract 5.1); a Forfeit with no battle at all is still refused quietly; the
--                     client has a way to send it (a BattleController caller of Command("Forfeit"))
--   p4fixbat_return   every ring run ends with the climber in front of the Champion Ring portal (ArenaInfo.RingSite,
--                     contract 3.8 "back at the portal"), not at the Trial Portal's ReturnCFrame: after a Forfeit in a
--                     fight and after a Forfeit between rounds; a trial still returns to ReturnCFrame
-- Plain Lua 5.1 syntax only.

local K = _G.K
local T = K.T
local guarded = K.guarded
local advance = K.advance

local S = {}

local seq = 0
local STRONG = { "cloudy_dragon", "ember_phoenix", "aurora_fox" }
local ALLOWED_WARNINGS = { "[BattleService]", "[DataService]", "[TycoonService]", "[PetCareService]" }

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
local function TS()
	return req("server/Services/TycoonService")
end
local function arenaInfo()
	local ab = req("server/Services/ArenaBuilder")
	return ab and ab.GetInfo and ab.GetInfo() or nil
end

local function ready(label)
	if not K.needBoot() then
		return false
	end
	local bs = BS()
	if not bs or type(bs.StartRing) ~= "function" or type(bs.Command) ~= "function" then
		T.fail(label .. ": skipped, BattleService (StartRing / Command) did not load")
		return false
	end
	local info = arenaInfo()
	if not info or typeof(info.RingSite) ~= "CFrame" then
		T.fail(label .. ": skipped, ArenaBuilder.GetInfo().RingSite is missing (no Portal_Ring in this build)")
		return false
	end
	if not TS() then
		T.fail(label .. ": skipped, TycoonService did not load (the ring needs a claimed home)")
		return false
	end
	return true
end

local function newPlayer(prefix, pets, level)
	seq = seq + 1
	local p = Mock.AddPlayer(prefix .. seq, 967000 + seq)
	advance(1.0)
	local data = DS()
	local prof = data.GetProfile(p)
	for _, id in ipairs(pets) do
		prof.Pets[id] = (prof.Pets[id] or 0) + 1
		prof.PetLevels[id] = { Level = level, Xp = 0 }
	end
	data.MarkDirty(p)
	local ok, why = data.SetTeam(p, 1, pets)
	if not ok then
		T.fail("(setup) SetTeam for " .. p.Name .. " failed", tostring(why))
	end
	return p
end

local function claimHome(p)
	local SS = req("server/Services/SpotService")
	local spots = (K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
	for i = 1, K.config().Lobby.SpotCount do
		if spots[i] and not (SS and SS.GetOwner(i)) then
			local ok = TS().Claim(p, i)
			advance(0.6)
			if ok then
				TS().Buy(p, "Garden")
				advance(0.3)
				return i
			end
		end
	end
	return nil
end

local function ringPos()
	local info = arenaInfo()
	local pad = info.RingPortal
	if typeof(pad) == "Instance" and pad:IsA("BasePart") then
		return pad.Position
	end
	return info.RingSite.Position
end

local function toRing(p)
	Mock.Teleport(p, CFrame.new(ringPos() + Vector3.new(0, 3, 6)))
	advance(0.05)
end

local function hdist(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function pocketCount()
	local pockets = workspace:FindFirstChild("BattlePockets")
	return pockets and #pockets:GetChildren() or 0
end

local function battleEnds(p, fromIndex)
	local out = {}
	local log = Mock.RemoteLog
	for i = (fromIndex or 0) + 1, #log do
		local e = log[i]
		if e.remote == "BattleState" and e.kind == "client" and e.userId == p.UserId and e.args[1] == "End" then
			out[#out + 1] = e.args[2]
		end
	end
	return out
end

-- starts a ring run from round 1 and waits (0.1 s steps) until round 1 is won: the run is then in its intermission
local function toIntermission(p)
	toRing(p)
	advance(1.6)
	local bs = BS()
	local mark = K.logSize()
	local ok, id = bs.StartRing(p, 1)
	if not ok then
		return false, tostring(id)
	end
	local t0 = Mock.Clock.now
	while Mock.Clock.now - t0 < 120 do
		advance(0.1)
		for _, m in ipairs(battleEnds(p, mark)) do
			if type(m.Rewards) == "table" and m.Rewards.Next then
				return true
			end
			if type(m.Rewards) == "table" and m.Rewards.Final then
				return false, "the run ended in round 1"
			end
		end
	end
	return false, "round 1 never ended"
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

-- EventService's scheduler must not open a raid in the middle of a scenario; the BattleState traffic stays out of
-- the client replay log
local function hold(bs)
	local real = bs.StartRaid
	bs.StartRaid = function()
		return false, "A raid is already running"
	end
	local hook = Mock._onRemote
	if hook then
		Mock._onRemote = function(entry)
			if entry.remote ~= "BattleState" then
				hook(entry)
			end
		end
	end
	return function()
		bs.StartRaid = real
		Mock._onRemote = hook
	end
end

----------------------------------------------------------------------------------------------------
-- p4fixbat_forfeit: BattleCommand Forfeit between two ring rounds ends the run
----------------------------------------------------------------------------------------------------
S.p4fixbat_forfeit = guarded("p4fixbat_forfeit", function()
	if not ready("p4fixbat_forfeit") then
		return
	end
	local bs, data = BS(), DS()
	local release = hold(bs)
	local cmd = K.remoteFolder():FindFirstChild("BattleCommand")
	T.check(cmd ~= nil, "p4 fix battle: the BattleCommand remote exists")

	-- no battle at all: still refused, nothing sent
	local idle = newPlayer("FixBatIdle", { STRONG[1] }, 12)
	T.check(bs.Command(idle, "Forfeit") == false, "p4 fix battle: Command('Forfeit') without any battle is refused")

	local p = newPlayer("FixBatF", STRONG, 12)
	T.check(claimHome(p) ~= nil, "p4 fix battle: (setup) the climber claims a home")
	local ok, why = toIntermission(p)
	local g = bs.GetBattle(p)
	T.check(ok and g and g.State == "Intermission" and g.Round == 2, "p4 fix battle: (setup) round 1 won, the run waits between rounds", tostring(why) .. " / " .. tostring(g and g.State))
	local ring0 = data.GetRing(p) or {}
	local cash0 = data.GetCash(p)
	local mark = K.logSize()
	Mock.FromClient(cmd, p, "Forfeit")
	advance(0.3)
	local g2 = bs.GetBattle(p)
	local ring1 = data.GetRing(p) or {}
	T.check(g2 == nil or g2.State ~= "Intermission",
		"p4 fix battle: BattleCommand('Forfeit') during a ring intermission ends the run (contract 5.1)", g2 and ("GetBattle State " .. tostring(g2.State) .. " Round " .. tostring(g2.Round)) or "")
	T.check(ring1.Runs == (ring0.Runs or 0) + 1 and ring1.Best == 1 and data.GetCash(p) == cash0,
		"p4 fix battle: ...Ring.Runs + 1, Best 1 (the won round kept), no Cash moves", "Runs " .. tostring(ring1.Runs) .. " Best " .. tostring(ring1.Best))
	local final = false
	for _, m in ipairs(battleEnds(p, mark)) do
		if type(m.Rewards) == "table" and m.Rewards.Final then
			final = true
		end
	end
	T.check(final, "p4 fix battle: ...the client gets the run's final End (the result card)")
	advance(4.6)
	T.check(p:GetAttribute("InBattle") == nil and not bs.IsInBattle(p) and pocketCount() == 0 and #bs.ListBattles() == 0,
		"p4 fix battle: ...InBattle cleared after the return, the pocket freed, no battle left")
	T.check(bs.Command(p, "Forfeit") == false, "p4 fix battle: ...a second Forfeit finds nothing")

	-- the client side: a kid needs a button that sends it (contract 5.1: BattleCommand "Forfeit")
	local inst = K.moduleInstance("client/Controllers/BattleController")
	if inst then
		local source = inst.Source or ""
		T.check(source:find('Command%(%s*"Forfeit"') ~= nil,
			"p4 fix battle: BattleController has a LEAVE control that calls Command(\"Forfeit\") (lead request: the client owner adds it)")
	else
		T.info("*BattleController not visible from the server world: the client caller check was skipped")
	end
	K.flushErrors("p4fixbat_forfeit")
	K.flushWarnings("p4fixbat_forfeit", ALLOWED_WARNINGS)
	release()
	cleanup({ p, idle })
end)

----------------------------------------------------------------------------------------------------
-- p4fixbat_return: a ring run ends in front of the Champion Ring portal
----------------------------------------------------------------------------------------------------
S.p4fixbat_return = guarded("p4fixbat_return", function()
	if not ready("p4fixbat_return") then
		return
	end
	local bs = BS()
	local release = hold(bs)
	local info = arenaInfo()
	local portal = ringPos()
	local trialRet = info.ReturnCFrame.Position
	local p = newPlayer("FixBatR", STRONG, 12)
	T.check(claimHome(p) ~= nil, "p4 fix battle: (setup) the climber claims a home")

	-- 1) a Forfeit in a fight (round 1): the run ends, 4 s later the climber stands at the ring portal
	toRing(p)
	advance(1.6)
	local ok = bs.StartRing(p, 1)
	advance(0.3)
	bs.Forfeit(p)
	advance(4.6)
	local pos = K.root(p).Position
	T.check(ok and p:GetAttribute("InBattle") == nil and hdist(pos, portal) < 20 and math.abs(pos.Y - portal.Y) < 12,
		"p4 fix battle: a ring run lost in round 1 ends in front of the Champion Ring portal (< 20 studs, contract 3.8)",
		string.format("%.1f studs from the ring portal, %.1f from the trial return", hdist(pos, portal), hdist(pos, trialRet)))
	local started = bs.StartRing(p, 1)
	T.check(started == true, "p4 fix battle: ...so START works again right there (inside RING_RANGE)")
	if started then
		advance(0.3)
		bs.Forfeit(p)
		advance(4.6)
	end

	-- 2) a Forfeit between two rounds: the same spot
	local okI, why = toIntermission(p)
	T.check(okI, "p4 fix battle: (setup) round 1 won", tostring(why))
	bs.Forfeit(p)
	advance(4.6)
	pos = K.root(p).Position
	T.check(p:GetAttribute("InBattle") == nil and hdist(pos, portal) < 20,
		"p4 fix battle: a ring run left between rounds ends in front of the Champion Ring portal",
		string.format("%.1f studs from the ring portal", hdist(pos, portal)))

	-- 3) trials keep their own return (ArenaInfo.ReturnCFrame)
	Mock.Teleport(p, CFrame.new(info.TrialPortal.Position + Vector3.new(0, 3, 6)))
	advance(1.6)
	local okT = bs.StartTrial(p, 1)
	advance(0.3)
	bs.Forfeit(p)
	advance(4.6)
	pos = K.root(p).Position
	T.check(okT and p:GetAttribute("InBattle") == nil and (pos - trialRet).Magnitude < 12,
		"p4 fix battle: a trial still ends at ArenaInfo.ReturnCFrame (the Trial Portal)", string.format("%.1f studs", (pos - trialRet).Magnitude))
	K.flushErrors("p4fixbat_return")
	K.flushWarnings("p4fixbat_return", ALLOWED_WARNINGS)
	release()
	cleanup({ p })
end)

return S
