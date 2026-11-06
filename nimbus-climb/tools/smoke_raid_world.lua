-- smoke_raid_world.lua: boss raids, Task 3 (docs/superpowers/specs/2026-11-01-raid-boss-design.md: the boss gate, the Raid pockets and
-- the boards in server/Services/ArenaBuilder.lua, the tier dressing and head tracking in shared/BossBuilder.lua). Server world only
-- (listed in server_files of tools/smoke.py), booted, before shutdown:
--   raid_world_gate    ArenaInfo.Gate: where it stands (bug batch 6: Segment_01, beside the main gate, never in its way), the
--                      walk-through zone, the Return frame, the dare prompt, the crest; the
--                      portcullis lets a player through and the segment's art is untouched
--   raid_world_pocket  BuildPocket(index, "Raid"): 96 x 96, a colliding floor, no crowd, the part budget; FreePocket; the Ring pocket
--                      is unchanged
--   raid_world_boards  the event board with no floor fight (the boss waits, the next boss, a line per fight) and with one (the HP bar)
--   raid_world_bosses  tier dressing: scale, crown, aura, SetTier re-dresses, the enrage colours win, Low has no aura; LookAt
--   raid_world_sky     the real SkyService: only the floor fight drives the server-wide sky
-- White-box: the wipes command the sim (St is an upvalue of IsInBattle, as in smoke_raid_service.lua). Plain Lua 5.1 syntax only.

local K = _G.K
local T = K.T
local guarded = K.guarded
local advance = K.advance
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local S = {}

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

local function arenaBuilder()
	return req("server/Services/ArenaBuilder")
end

local function partsOf(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			out[#out + 1] = d
		end
	end
	return out
end

local function visibleText(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text ~= "" then
			local vis = true
			local a = d
			while a and a:IsA("GuiObject") do
				if not a.Visible then
					vis = false
				end
				a = a.Parent
			end
			if vis then
				out[#out + 1] = d.Text
			end
		end
	end
	return table.concat(out, "\n")
end

----------------------------------------------------------------------------------------------------
-- raid_world_gate
----------------------------------------------------------------------------------------------------
S.raid_world_gate = guarded("raid_world_gate", function()
	if not K.needBoot() then
		return
	end
	local AB = arenaBuilder()
	local info = AB.GetInfo()
	local gate = info.Gate
	if not T.check(type(gate) == "table" and typeof(gate.CFrame) == "CFrame" and typeof(gate.Size) == "Vector3" and gate.Zone and gate.Zone:IsA("BasePart") and gate.Zone.CanCollide == false and typeof(gate.Return) == "CFrame", "raid gate: ArenaInfo.Gate = { CFrame, Size, Zone, Return }") then
		return
	end
	-- bug batch 6 (the owner: "why put it there? make it at the main enterance."): the BossGate is the segment beside the
	-- main gate (k = 1); the back (k = 8) is a stand again. Segment k's frame: Center turned k x 22.5 degrees, outward = -Z.
	local STEP16, FLOOR_R, GATE_HALF, WALL_OUT = math.pi / 8, 72, 6, 92
	local stands = info.Model.Colosseum.Stands
	local kinds = {}
	for k = 0, 15 do
		local s = stands:FindFirstChild(string.format("Segment_%02d", k))
		kinds[#kinds + 1] = k .. "=" .. tostring(s and s:GetAttribute("Kind"))
	end
	local function kindOf(k)
		local s = stands:FindFirstChild(string.format("Segment_%02d", k))
		return s and s:GetAttribute("Kind")
	end
	local nBoss = 0
	for k = 0, 15 do
		if kindOf(k) == "BossGate" then
			nBoss = nBoss + 1
		end
	end
	T.check(nBoss == 1 and kindOf(1) == "BossGate" and kindOf(8) == "Stand" and kindOf(0) == "Gate" and kindOf(4) == "Gate" and kindOf(12) == "Gate",
		"raid gate: Segment_01 (beside the main gate) is the one BossGate, Segment_08 a Stand, Segment_00 / 04 / 12 the gates", table.concat(kinds, " "))
	local seg01, seg08 = stands:FindFirstChild("Segment_01"), stands:FindFirstChild("Segment_08")
	-- (the recorded Tag calls: p3arena_mesh strips the live ML_* attributes when it is done)
	local placed = type(AB._Mesh) == "table" and type(AB._Mesh.Placed) == "table" and AB._Mesh.Placed or {}
	local function dressKey(seg)
		return seg and placed[seg] and placed[seg].Key
	end
	T.check(dressKey(seg01) == "arena_seg_bossgate" and dressKey(seg08) == "arena_seg_stand",
		"raid gate: the existing Blender segments dress the swapped slots (arena_seg_bossgate on 01, arena_seg_stand on 08)", tostring(dressKey(seg01)) .. " / " .. tostring(dressKey(seg08)))
	local main = info.Center -- Segment_00's frame: the main gate looks along -Z
	local segFrame = info.Center * CFrame.Angles(0, STEP16, 0)
	local rel = segFrame:PointToObjectSpace(gate.CFrame.Position)
	T.check(math.abs(rel.X) < 0.5 and math.abs(rel.Z + (FLOOR_R - 2)) < 0.5 and math.abs(rel.Y) < 2, "raid gate: the gate sits in Segment_01's podium wall, FloorR - 2 from the centre, 22.5 degrees off the main gate", tostring(rel))
	T.check(gate.CFrame.LookVector:Dot((info.Floor.CFrame.Position - gate.CFrame.Position).Unit) > 0.99, "raid gate: -Z looks at the floor's centre")
	T.check(math.abs(gate.CFrame.UpVector.Y - 1) < 1e-6, "raid gate: upright")
	-- never in the way in or out: the main gate's corridor (|x| <= GateHalf + 1, from FloorR - 6 to WallOut + 4 out) stays 13+
	-- studs from the walk-through's footprint
	local zone = gate.Zone
	local hx, hz = zone.Size.X / 2, zone.Size.Z / 2
	local function toCorridor(p)
		local l = main:PointToObjectSpace(p)
		local dx = math.max(math.abs(l.X) - (GATE_HALF + 1), 0)
		local dz = math.max((FLOOR_R - 6) - (-l.Z), (-l.Z) - (WALL_OUT + 4), 0)
		return math.sqrt(dx * dx + dz * dz)
	end
	local function toZone(p)
		local l = zone.CFrame:PointToObjectSpace(p)
		local dx, dz = math.max(math.abs(l.X) - hx, 0), math.max(math.abs(l.Z) - hz, 0)
		return math.sqrt(dx * dx + dz * dz)
	end
	local gap = math.huge
	for i = -20, 20 do
		local t = i / 20
		for _, o in ipairs({ { t * hx, -hz }, { t * hx, hz }, { -hx, t * hz }, { hx, t * hz } }) do
			gap = math.min(gap, toCorridor((zone.CFrame * CFrame.new(o[1], 0, o[2])).Position))
		end
	end
	for _, cx in ipairs({ -(GATE_HALF + 1), GATE_HALF + 1 }) do
		for _, r in ipairs({ FLOOR_R - 6, WALL_OUT + 4 }) do
			gap = math.min(gap, toZone((main * CFrame.new(cx, zone.Position.Y - main.Y, -r)).Position))
		end
	end
	T.check(gap >= 13, "raid gate: walking in or out of the main gate never touches the walk-through (13+ studs from its corridor)", string.format("%.1f studs", gap))
	local ret = gate.Return.Position
	local rl = main:PointToObjectSpace(ret)
	T.check(Vector3.new(rl.X, 0, rl.Z).Magnitude < FLOOR_R and toZone(ret) > 0 and toCorridor(ret) > 0, "raid gate: Return stands on the sand, outside the walk-through and the main gate's corridor", tostring(rl))
	T.check((gate.Return.Position - info.Floor.CFrame.Position).Magnitude < (gate.CFrame.Position - info.Floor.CFrame.Position).Magnitude and gate.Return.LookVector:Dot((info.Floor.CFrame.Position - gate.Return.Position).Unit) > 0.9, "raid gate: Return is on the floor side of the gate, looking at the centre")
	T.check(CollectionService:HasTag(gate.Zone, "NC_RaidGate") and gate.Zone.Name == "RaidGate" and gate.Zone.CanTouch == false and gate.Zone.CanQuery == false and gate.Zone.Transparency >= 1, "raid gate: the zone is an invisible part tagged NC_RaidGate")
	T.check(CollectionService:HasTag(gate.Zone, "NC_BattleZone") == false, "raid gate: the zone is no battle zone")
	local floorRel = gate.Zone.CFrame:PointToObjectSpace(gate.CFrame.Position + Vector3.new(0, 3, 0))
	T.check(math.abs(floorRel.Y) <= gate.Zone.Size.Y / 2, "raid gate: the zone covers a standing player's root")
	local seg = seg01
	local bars = 0
	for _, d in ipairs(seg:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Iron" then
			bars = bars + 1
			T.check(d.CanCollide == false and d.CanQuery == false, "raid gate: the portcullis bars do not collide")
		end
	end
	T.check(bars > 0, "raid gate: the BossGate segment still has its iron (the art is untouched)")
	local stand = info.Model.Colosseum.Stands:FindFirstChild("Segment_00")
	local solidIron = 0
	for _, d in ipairs(stand:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Iron" and d.CanCollide then
			solidIron = solidIron + 1
		end
	end
	T.check(solidIron > 0, "raid gate: the other gates' iron still collides (BossGate kind only)")
	T.check(gate.Prompt and gate.Prompt:IsA("ProximityPrompt") and gate.Prompt:GetAttribute("OpenPanel") == "Dare" and gate.Prompt.MaxActivationDistance <= 12 and gate.Prompt.Name == "DarePrompt" and gate.Prompt.ActionText == "Dare a higher tier", "raid gate: the dare prompt (OpenPanel = Dare) on the pillar")
	if gate.Prompt then
		local pillar = gate.Prompt.Parent
		local px = gate.Zone.CFrame:PointToObjectSpace(pillar.Position)
		T.check(math.abs(px.X) - pillar.Size.X / 2 >= gate.Zone.Size.X / 2, "raid gate: the pillar stands beside the walk-through, not in it", tostring(px))
		T.check((pillar.Position - gate.CFrame.Position).Magnitude + gate.Prompt.MaxActivationDistance <= 20, "raid gate: anywhere the prompt shows is within BattleService's dare range")
		T.check(math.abs(main:PointToObjectSpace(pillar.Position).X) > math.abs(main:PointToObjectSpace(zone.Position).X) and toCorridor(pillar.Position) >= 13,
			"raid gate: the pillar stands on the far side of the walk-through from the main gate")
	end
	T.check(gate.Crest and gate.Crest:IsA("BasePart") and gate.Crest:IsDescendantOf(seg) and gate.Crest.Name == "Gold", "raid gate: the crest part for the client's tag (in Segment_01)")
	if gate.Crest then
		local crel = segFrame:PointToObjectSpace(gate.Crest.Position)
		T.check(math.abs(crel.X) < 2 and crel.Y > 5 and crel.Y < 9 and crel.Z < -70 and crel.Z > -75, "raid gate: the crest is the gold over the gate, not the banner's on the outer wall", tostring(crel))
		T.check(CollectionService:HasTag(gate.Crest, "NC_RaidGateCrest"), "raid gate: the crest is tagged for the client")
	end
	T.check(AB.InArena(gate.CFrame.Position) and info.Parts <= 2800, "raid gate: inside the arena; the island stays within 2800 parts", tostring(info.Parts))
	T.check(AB.GetInfo().Gate == gate, "raid gate: GetInfo().Gate is the same table")
	K.flushErrors("raid_world_gate")
	K.flushWarnings("raid_world_gate")
end)

----------------------------------------------------------------------------------------------------
-- raid_world_pocket
----------------------------------------------------------------------------------------------------
S.raid_world_pocket = guarded("raid_world_pocket", function()
	if not K.needBoot() then
		return
	end
	local AB = arenaBuilder()
	local p = AB.BuildPocket(3, "Raid")
	if not T.check(p and p.Kind == "Raid" and p.Size.X == 96 and p.Size.Z == 96 and p.Zone:GetAttribute("Mode") == "Raid" and p.Model:GetAttribute("PocketKind") == "Raid", "raid pocket: BuildPocket(index, 'Raid') builds a 96 x 96 Raid zone") then
		return
	end
	T.check(p.Model.Name == "RaidPocket_3" and p.Zone.Name == "BattleZone_Raid" and p.Zone:GetAttribute("ZoneId") == "Raid" and p.Zone:GetAttribute("Index") == 3 and CollectionService:HasTag(p.Zone, "NC_BattleZone") and p.Index == 3, "raid pocket: its name, ZoneId and Index")
	local n = #partsOf(p.Model)
	T.check(n <= 160 and n >= 20, "raid pocket: within 160 parts", n .. " parts")
	T.check(p.Model:FindFirstChild("Crowd", true) == nil and p.Model:FindFirstChild("RingEmblem", true) == nil and p.Model:FindFirstChild("Confetti", true) == nil and p.Model:FindFirstChild("SpawnPad", true) == nil, "raid pocket: no crowd, no emblem, no confetti, no pads")
	local floorHit = false
	local gems, lights = 0, 0
	for _, d in ipairs(p.Model:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide and math.abs(d.Position.Y - p.CFrame.Position.Y) < 1.5 and (d.Size.X > 60 or d.Size.Z > 60) then
			floorHit = true
		end
		if d:IsA("BasePart") and d.Name == "CrownGem" then
			gems = gems + 1
		end
		if d:IsA("PointLight") then
			lights = lights + 1
		end
	end
	T.check(floorHit, "raid pocket: a colliding floor under the whole zone")
	T.check(gems == 4 and lights == 0, "raid pocket: four unlit crown posts", gems .. " posts, " .. lights .. " lights")
	T.check(AB.ZoneAt(p.Spawn.Position) == p.Zone and p.Spawn.Position.Z < p.CFrame.Position.Z and p.Spawn.LookVector.Z > 0.9, "raid pocket: Spawn is on the -Z rim inside the zone, looking at the centre")
	-- the fighters stand on the rim of the 96 x 96 floor (BattleService's raidStand: r = 48 + 6), at any angle
	for _, a in ipairs({ 0, 45, 90, 135, 180, 225, 270, 315 }) do
		local pos = p.CFrame.Position + Vector3.new(math.cos(math.rad(a)) * 54, 2, math.sin(math.rad(a)) * 54)
		T.check(AB.ZoneAt(pos) == p.Zone, "raid pocket: the rim at " .. a .. " degrees is in the zone")
	end
	T.check(AB.BuildPocket(3, "Raid") == p and AB.GetPocket(3) == p, "raid pocket: building the same index returns it")
	local m = p.Model
	T.check(AB.FreePocket(p) == true and AB.GetPocket(3) == nil and m.Parent == nil, "raid pocket: FreePocket frees it")
	local r = AB.BuildPocket(4, "Ring")
	T.check(r.Kind == "Ring" and r.Size.X == 44 and r.Model.Name == "RingPocket_4" and r.Model:GetAttribute("PocketKind") == "Ring", "raid pocket: the Ring pocket is unchanged")
	AB.FreePocket(r)
	K.flushErrors("raid_world_pocket")
	K.flushWarnings("raid_world_pocket")
end)

----------------------------------------------------------------------------------------------------
-- raid_world_boards
----------------------------------------------------------------------------------------------------
S.raid_world_boards = guarded("raid_world_boards", function()
	if not K.needBoot() then
		return
	end
	local AB = arenaBuilder()
	local info = AB.GetInfo()
	local board = info.Model:FindFirstChild("EventBoard", true)
	-- EventService redraws the boards on its own broadcasts: hold them while these states are checked
	local ES = req("server/Services/EventService")
	local realBroadcast = ES and ES.Broadcast
	if realBroadcast then
		ES.Broadcast = function(player)
			if player ~= nil then
				return realBroadcast(player)
			end
			return nil
		end
	end
	local ok, err = pcall(function()
		local labels = info.EventBoard.Labels
		AB.ApplyArenaState({ Raid = { BossId = "lava_golem", Name = "Lava Golem", Active = false, NextBossIn = 95, Fights = {}, Closed = {} }, Next = { Kind = "DoubleRewards", StartsIn = 600 }, Leaderboard = {} })
		local text = visibleText(board)
		T.check(text:find("Lava Golem waits at the gate", 1, true) ~= nil and text:find("Next boss in", 1, true) ~= nil and text:find("1:35", 1, true) ~= nil, "raid board: no fight: the boss waits, the next boss's clock", text)
		T.check(text:find("Walk through", 1, true) ~= nil, "raid board: no fight: says how to fight", text)
		T.check(text:find("join", 1, true) == nil and text:find("Join", 1, true) == nil, "raid board: no word of joining", text)
		T.check(text:find("x2", 1, true) ~= nil and text:find("10:00", 1, true) ~= nil, "raid board: the next Double Rewards still shows", text)
		T.check(labels.RaidBar.Visible == false, "raid board: no floor fight, no HP bar")
		AB.ApplyArenaState({ Raid = { BossId = "lava_golem", Name = "Lava Golem", Active = false, NextBossIn = 95, Fights = {
			Mid = { Tier = "Mid", Players = 3, Hp = 500, MaxHp = 1000, EndsIn = 200, Floor = false },
			Max = { Tier = "Max", Players = 1, Hp = 900, MaxHp = 1000, EndsIn = 200, Floor = false },
			Starter = { Tier = "Starter", Players = 8, Hp = 1, MaxHp = 1000, EndsIn = 200, Floor = false },
		}, Closed = {} }, Leaderboard = {} })
		text = visibleText(board)
		T.check(text:find("waits", 1, true) ~= nil and text:find("1:35", 1, true) ~= nil and text:find("Mid: 3 fighting, HP 50%", 1, true) ~= nil and text:find("Max: 1 fighting, HP 90%", 1, true) ~= nil and text:find("Starter: 8 fighting, HP 0%", 1, true) ~= nil, "raid board: a line per running tier fight", text)
		T.check(text:find("Starter", 1, true) < text:find("Mid", 1, true) and text:find("Mid", 1, true) < text:find("Max", 1, true), "raid board: the fights in tier order", text)
		AB.ApplyArenaState({ Raid = { BossId = "lava_golem", Name = "Lava Golem", Active = false, NextBossIn = 95, Fights = {}, Closed = {} }, Leaderboard = {} })
		text = visibleText(board)
		T.check(text:find("fighting", 1, true) == nil and text:find("Walk through", 1, true) ~= nil and text:find("1:35", 1, true) ~= nil, "raid board: the lines go with the fights", text)
		AB.ApplyArenaState({ Raid = { BossId = "lava_golem", Name = "Lava Golem", Active = true, FloorTier = "High", BattleId = "R1", NextBossIn = 95, Fights = { High = { Tier = "High", Players = 2, Hp = 250, MaxHp = 1000, EndsIn = 90, Floor = true }, Mid = { Tier = "Mid", Players = 1, Hp = 1000, MaxHp = 1000, EndsIn = 90, Floor = false } }, Closed = {} }, Leaderboard = {} })
		text = visibleText(board)
		T.check(labels.RaidBar.Visible == true and text:find("High", 1, true) ~= nil and text:find("Lava Golem", 1, true) ~= nil and text:find("25%", 1, true) ~= nil and text:find("2 fighters", 1, true) ~= nil and text:find("01:30", 1, true) ~= nil, "raid board: a floor fight: the live HP bar, its tier, HP, fighters and clock", text)
		T.check(math.abs(labels.RaidFill.Size.X.Scale - 0.25) < 1e-6, "raid board: the bar shows the floor fight's HP (not the pocket's)")
		T.check(text:find("join", 1, true) == nil, "raid board: a floor fight: no word of joining", text)
		-- junk in the new shape never errors
		for _, junk in ipairs({ { Raid = { Active = true, FloorTier = "High" } }, { Raid = { Active = true, FloorTier = "Nope", Fights = { High = 5 } } }, { Raid = { Active = false, Fights = 7, NextBossIn = "x" } }, { Raid = { Active = false, Fights = { Mid = {} }, BossId = 7 } }, { Raid = { Fights = { Banana = { Players = "x", Hp = "y", MaxHp = 0 } } } } }) do
			T.check(pcall(AB.ApplyArenaState, junk) == true, "raid board: a junk state never errors")
		end
		K.flushErrors("raid_world_boards")
	end)
	if realBroadcast then
		ES.Broadcast = realBroadcast
		ES.Broadcast()
	end
	if not ok then
		error(err, 0)
	end
	K.flushWarnings("raid_world_boards")
end)

----------------------------------------------------------------------------------------------------
-- raid_world_bosses
----------------------------------------------------------------------------------------------------
S.raid_world_bosses = guarded("raid_world_bosses", function()
	local BB = req("shared/BossBuilder")
	local BC = req("shared/BattleCatalog")
	if not T.check(BB and type(BB.SetTier) == "function" and type(BB.TierLooks) == "table", "raid bosses: BossBuilder.TierLooks + SetTier") then
		return
	end
	for _, id in ipairs(BB.Ids()) do
		local plain = BB.Build(id, { Detail = "High" })
		local maxed = BB.Build(id, { Detail = "High", Tier = "Max" })
		local starter = BB.Build(id, { Detail = "High", Tier = "Starter" })
		T.check(maxed:GetAttribute("Scale") > plain:GetAttribute("Scale") and starter:GetAttribute("Scale") < plain:GetAttribute("Scale"), id .. ": Max is bigger, Starter smaller")
		T.check(math.abs(maxed:GetAttribute("Scale") - plain:GetAttribute("Scale") * BC.RaidTierById("Max").Scale) < 1e-6, id .. ": the scale is the tier's")
		T.check(plain:GetAttribute("Tier") == nil and plain:FindFirstChild("TierLight", true) == nil, id .. ": no tier = today's boss")
		T.check(maxed:GetAttribute("Tier") == "Max" and starter:GetAttribute("Tier") == "Starter", id .. ": the model says its tier")
		T.check(maxed:FindFirstChild("TierCrown", true) ~= nil and #maxed.TierCrown:GetChildren() == 8 and starter:FindFirstChild("TierCrown", true) == nil, id .. ": only Max wears the crown of 8 spikes")
		T.check(maxed:FindFirstChild("TierAura", true) ~= nil and starter:FindFirstChild("TierAura", true) == nil, id .. ": the aura grows with the tier (none at Starter)")
		local aura = maxed:FindFirstChild("TierAura", true)
		T.check(aura and aura:IsA("ParticleEmitter") and aura.Parent:IsA("Attachment") and aura.Parent.Name == "Fx_Core" and aura.Rate == 18, id .. ": the aura is on Fx_Core, Rate 12 x Aura")
		local light = maxed:FindFirstChild("TierLight", true)
		T.check(light and light:IsA("PointLight") and light.Range == 27 and starter:FindFirstChild("TierLight", true).Range == 18, id .. ": one TierLight, Range 18 + 6 x Aura")
		T.check(BB.PartCount(maxed) <= 960, id .. ": a Max boss stays within 960 parts", tostring(BB.PartCount(maxed)))
		-- the spikes are boss parts: above the rest of the model's middle, Neon, no collisions, they move with the rig
		local spike = maxed.TierCrown:GetChildren()[1]
		T.check(spike:IsA("BasePart") and spike.Material == Enum.Material.Neon and spike.Anchored == true and spike.CanCollide == false and spike.CanQuery == false and spike.CanTouch == false, id .. ": a crown spike is an anchored Neon part with no collisions")
		T.check(spike.Position.Y > maxed:GetAttribute("Height") * 0.5, id .. ": the crown sits on top of the boss", tostring(spike.Position.Y))
		local spikeAt = spike.Position
		BB.Animate(maxed, "Idle", 0, { CFrame = CFrame.new(100, 0, 0) })
		T.check((spike.Position - spikeAt - Vector3.new(100, 0, 0)).Magnitude < 1e-3, id .. ": Animate moves the crown with the rig")
		BB.Animate(maxed, "Idle", 0, { CFrame = CFrame.new() })
		-- a lit tint: the glow parts turn the tier's colour; the enrage colours win while enraged and the tint comes back
		local glow = nil
		local plainGlow = nil
		for _, name in ipairs({ "Eye", "Glow", "Magma", "Rune" }) do
			glow = glow or maxed:FindFirstChild(name, true)
			plainGlow = plainGlow or plain:FindFirstChild(name, true)
		end
		local look = BB.TierLooks.Max.Color
		local function dist(a, b)
			return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B)
		end
		local tinted = glow.Color
		T.check(dist(tinted, look) < dist(plainGlow.Color, look), id .. ": the glow parts lean toward the tier colour")
		BB.SetEnraged(maxed, true)
		T.check(dist(glow.Color, tinted) > 0.01, id .. ": SetEnraged wins while enraged")
		BB.SetTier(maxed, "Max")
		T.check(dist(glow.Color, tinted) > 0.01, id .. ": SetTier does not take the enrage colours away")
		BB.SetEnraged(maxed, false)
		T.check(dist(glow.Color, tinted) < 1e-6, id .. ": the tint comes back after the enrage")
		T.check(BB.SetTier(maxed, "Max") and #maxed.TierCrown:GetChildren() == 8 and BB.PartCount(maxed) <= 960, id .. ": SetTier is idempotent")
		local count = BB.PartCount(maxed)
		T.check(BB.SetTier(maxed, "Mid") and maxed:FindFirstChild("TierCrown", true) == nil and maxed:GetAttribute("Tier") == "Mid" and BB.PartCount(maxed) == count - 8, id .. ": SetTier re-dresses (the crown goes)")
		T.check(BB.Animate(maxed, "Idle", 0.5, {}) == true, id .. ": Animate still runs after the crown went")
		T.check(BB.SetTier(maxed, nil) and maxed:GetAttribute("Tier") == nil and maxed:FindFirstChild("TierAura", true) == nil and maxed:FindFirstChild("TierLight", true) == nil, id .. ": SetTier(nil) takes the dressing off")
		T.check(dist(glow.Color, tinted) > 0.001, id .. ": SetTier(nil) takes the tint off")
		T.check(BB.SetTier(maxed, "Banana") == false, id .. ": an unknown tier is refused")
		BB.SetTier(maxed, "Max")
		-- Graphics Low: the crown stays, the aura does not
		local low = BB.Build(id, { Detail = "Low", Tier = "Max" })
		T.check(low:FindFirstChild("TierCrown", true) ~= nil and low:FindFirstChild("TierAura", true) == nil, id .. ": a Low boss wears the crown without the aura")
		T.check(BB.SetTier(maxed, "Max", { NoAura = true }) and maxed:FindFirstChild("TierAura", true) == nil and maxed:FindFirstChild("TierCrown", true) ~= nil, id .. ": SetTier(..., { NoAura = true }) cuts the aura of a High boss")
		-- LookAt
		BB.SetTier(maxed, "Max")
		local head = maxed:FindFirstChild("Head", true) or maxed:FindFirstChild("Head2", true)
		BB.Animate(maxed, "Idle", 0, {})
		local before = head:GetChildren()[1].CFrame
		BB.Animate(maxed, "Idle", 0, { LookAt = maxed.PrimaryPart.Position + Vector3.new(40, 10, -40) })
		T.check((head:GetChildren()[1].CFrame.LookVector - before.LookVector).Magnitude > 0.05, id .. ": LookAt turns the head")
		local turned = head:GetChildren()[1].CFrame.LookVector
		T.check(turned.X > before.LookVector.X, id .. ": ... toward the target (+X)")
		BB.Animate(maxed, "Idle", 0, { LookAt = maxed.PrimaryPart.Position + Vector3.new(1000, 0, 200) })
		local far = head:GetChildren()[1].CFrame.LookVector
		T.check(math.acos(math.max(-1, math.min(1, far:Dot(before.LookVector)))) <= 1.0 + 1e-3, id .. ": the turn is clamped to 1 rad")
		BB.Animate(maxed, "Idle", 0, {})
		T.check((head:GetChildren()[1].CFrame.LookVector - before.LookVector).Magnitude < 1e-3, id .. ": no LookAt = the rest pose")
	end
	T.check(BB.SetTier(nil, "Max") == false and BB.SetTier(game, "Max") == false, "raid bosses: SetTier on anything else is refused")
	K.flushErrors("raid_world_bosses")
	K.flushWarnings("raid_world_bosses")
end)

----------------------------------------------------------------------------------------------------
-- raid_world_sky
----------------------------------------------------------------------------------------------------
local function svcState(bs)
	for i = 1, 80 do
		local name, v = debug.getupvalue(bs.IsInBattle, i)
		if not name then
			break
		end
		if name == "St" and type(v) == "table" and type(v.battles) == "table" then
			return v
		end
	end
	return nil
end

local function newPlayer(prefix, level)
	seq = seq + 1
	local p = Mock.AddPlayer(prefix .. seq, 986000 + seq)
	advance(0.2)
	local data = req("server/Services/DataService")
	local prof = data.GetProfile(p)
	for _, id in ipairs(COMMON) do
		prof.Pets[id] = (prof.Pets[id] or 0) + 1
		prof.PetLevels[id] = { Level = level, Xp = 0 }
	end
	data.MarkDirty(p)
	local ok, why = data.SetTeam(p, 1, COMMON)
	if not ok then
		T.fail("(setup) SetTeam for " .. p.Name .. " failed", tostring(why))
	end
	return p
end

S.raid_world_sky = guarded("raid_world_sky", function()
	if not K.needBoot() then
		return
	end
	local bs = req("server/Services/BattleService")
	local info = arenaBuilder().GetInfo()
	local cfg = K.config().Sky
	local attr = cfg.Attr.Event
	local players = {}
	local function add(prefix, level, dx)
		local p = newPlayer(prefix, level)
		players[#players + 1] = p
		Mock.Teleport(p, info.Spawn * CFrame.new(dx, 0, 0))
		advance(0.05)
		return p
	end
	local function wipeFight(id)
		local b = svcState(bs).battles[id]
		for _, part in ipairs(b.PartList) do
			if not part.Left then
				b.Sim:Command(part.UserId, "Forfeit")
			end
		end
		advance(0.3)
	end
	local ok, err = pcall(function()
		bs.EndRaids("Ended")
		advance(0.3)
		T.eq(Workspace:GetAttribute(attr), "", "raid sky: no fight, no raid sky")
		local starter, mid, high = add("SkyS", 10, 2), add("SkyM", 30, 4), add("SkyH", 60, 6)
		local _, idS = bs.EnterRaid(starter)
		local bossId = bs.GetRaidStatus().BossId
		T.eq(Workspace:GetAttribute(attr), bossId, "raid sky: a floor fight starts: the server-wide sky turns")
		local _, idM = bs.EnterRaid(mid)
		T.check(bs.GetRaidStatus().Fights.Mid.Floor == false, "raid sky: (setup) the second tier fights in a pocket")
		wipeFight(idS)
		T.eq(Workspace:GetAttribute(attr), "", "raid sky: the floor fight ends while a pocket fight runs: the sky clears")
		advance(cfg.EventWatch + 1)
		T.check(bs.GetRaidStatus().Fights.Mid ~= nil, "raid sky: (setup) the pocket fight runs on")
		T.eq(Workspace:GetAttribute(attr), "", "raid sky: a pocket fight alone never turns the server-wide sky")
		local _, idH = bs.EnterRaid(high)
		T.eq(Workspace:GetAttribute(attr), bossId, "raid sky: the next floor fight turns it again")
		wipeFight(idM)
		T.eq(Workspace:GetAttribute(attr), bossId, "raid sky: a pocket fight's end never clears it")
		advance(cfg.EventWatch + 1)
		T.eq(Workspace:GetAttribute(attr), bossId, "raid sky: ... and the watchdog agrees")
		wipeFight(idH)
		advance(cfg.EventWatch + 1)
		T.eq(Workspace:GetAttribute(attr), "", "raid sky: the floor fight ends: the sky clears")
	end)
	bs.EndRaids("Ended")
	advance(0.2)
	K.removePlayers(players)
	advance(RETURN_DELAY + 1)
	local St = svcState(bs)
	if St then
		for tier in pairs(St.raidClosed or {}) do
			St.raidClosed[tier] = nil
		end
	end
	if not ok then
		error(err, 0)
	end
	K.flushErrors("raid_world_sky")
	K.flushWarnings("raid_world_sky")
end)

return S
