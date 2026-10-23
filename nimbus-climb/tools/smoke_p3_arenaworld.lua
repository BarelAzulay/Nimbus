-- smoke_p3_arenaworld.lua: Phase 3 "arenaworld" (ARCHITECTURE_V3.md "Phase 3: Pet battles", "Phase 3 build contract":
-- ArenaBuilder + its "Interfaces between the Phase 3 modules" (ArenaInfo, BuildPocket / FreePocket, OpenPanel prompts),
-- ART DIRECTION, World text rule, Replication rule) as changed by Phase 5 (6.1 / 6.2 / 10.3 / 10.5: the Trials are gone,
-- Portal_Ring and Portal_Arena stand in the plaza's Gate Court, arena <= 2800 parts): server/Services/ArenaBuilder.lua,
-- the arena link and the home Arena Gate. Server world only (listed in server_files of tools/smoke.py):
--   p3arena_world     (booted) the API; workspace.BattleArena is ArenaInfo.Model and the info has the contract shape
--                     (Center, Floor {CFrame, Size}, Rings {CFrame, Size, Pads}, Spawn, ReturnCFrame, RingPortal,
--                     LobbyCFrame; no TrialPortal); the part budget (<= 2800), anchored, no scripts / welds / decals, no
--                     big neon; battle zones tagged NC_BattleZone with Mode / Size (= BattleCatalog.Zones) for the boss
--                     floor and 2+ duel rings, ZoneAt / InArena; the battle squares fit the floors at ANY rotation;
--                     duel pads carry a "Duel" prompt with OpenPanel = "Arena"; no Portal_Trials anywhere; Portal_Ring and
--                     Portal_Arena are WorldStyle gates (<= 120 parts each, a pixel tag) in LobbyInfo.GatesFolder at
--                     GateSites.Ring / .Arena (RingPrompt OpenPanel = "Ring" on the pad, ArenaPortalPrompt), the RingBoard
--                     pill; the forum's Return gate; the arena never touches the lobby and stays below the sky dragon;
--                     the bridge link; readable world text
--   p3arena_boards    (booted) ApplyArenaState draws the event board and the trophy leaderboard; junk never errors
--   p3arena_pockets   (booted) BuildPocket(index[, "Ring"]): the Champion Ring pocket only (Phase 5: nil / unknown kinds
--                     build it too): contract shape, Size = BattleCatalog.Zones.Ring 44 x 44, 100..250 parts, far out
--                     in the sky, a Ring zone found by ZoneAt, the square fits at any rotation, the spawn on the -Z side,
--                     a gold rim / four crown posts / a crowd of cloud puffs; the same index returns the same pocket;
--                     FreePocket removes it (and its zone); junk indices / zones never error
--   p3arena_art       (booted; Phase 6 A1 look revert) the P4 look on the island and the Champion Ring pocket:
--                     SmoothPlastic (Neon / Glass / ForceField), blocks only, a bright P4 palette, warm lanterns, no
--                     small-part shadows, square voxel posts, a kerb + lip round the edge (open at the bridge), the avenue's 4..6-stud tiles
--                     (+-0.05, jittered), mown lawn stripes, NC_Detail decor every ~12 studs, P4 white / light-blue exempt clouds,
--                     <= 2800 / <= 250 parts, the safety net idle (ArtFixes = 0)
--   p3arena_teleport  (booted) the home Arena Gate: the owner standing at the gate lands on the arena's Spawn; refused
--                     for another player, from far away, in a match, in a battle, and during the cooldown; Phase 5:
--                     Portal_Arena's ArenaPortalPrompt -> Spawn, the Return gate -> LobbyCFrame in front of Portal_Arena;
--                     panel / duel / board prompts never teleport; the server never moves a part of the arena
-- Plain Lua 5.1 syntax only.

local K = _G.K
local T = K.T
local guarded = K.guarded
local advance, mod, config, fmt = K.advance, K.mod, K.config, K.fmt

local abs, floor, max, min, sqrt, huge = math.abs, math.floor, math.max, math.min, math.sqrt, math.huge
local CollectionService = game:GetService("CollectionService")

local S = {}

----------------------------------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------------------------------
local function arenaBuilder()
	local inst = K.moduleInstance("server/Services/ArenaBuilder")
	if not inst then
		return nil
	end
	local ok, AB = pcall(require, inst)
	if ok and type(AB) == "table" then
		return AB
	end
	return nil
end

local function battleCatalog()
	local inst = K.moduleInstance("shared/BattleCatalog")
	if not inst then
		return nil
	end
	local ok, BC = pcall(require, inst)
	return ok and type(BC) == "table" and BC or nil
end

local function zoneSize(mode)
	local defaults = { Raid = 96, Duel = 44, Trial = 56, Ring = 44 }
	local BC = battleCatalog()
	local z = BC and type(BC.Zones) == "table" and BC.Zones[mode]
	if type(z) == "table" and tonumber(z.X) and tonumber(z.Z) then
		return z.X, z.Z
	end
	return defaults[mode], defaults[mode]
end

local function partsOf(root)
	local out = {}
	if not root then
		return out
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			out[#out + 1] = d
		end
	end
	return out
end

local function findAll(root, pred)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if pred(d) then
			out[#out + 1] = d
		end
	end
	return out
end

local function promptsUnder(root)
	return findAll(root, function(d)
		return d:IsA("ProximityPrompt")
	end)
end

local function promptWorldPos(prompt)
	local p = prompt.Parent
	if p and p:IsA("Attachment") then
		return p.WorldPosition
	elseif p and p:IsA("BasePart") then
		return p.Position
	end
	return nil
end

local function hdist(a, b)
	return sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end

-- downward ray: the first collidable surface under `pos` (from 3 studs above, `depth` studs down)
local function surfaceBelow(pos, depth)
	local params = RaycastParams.new()
	params.RespectCanCollide = true
	local hit = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -(depth or 14), 0), params)
	return hit
end

-- the corners of a `sx` x `sz` square centred on `cf` (flat), turned `deg` degrees
local function squareCorners(cf, sx, sz, deg, inset)
	local out = {}
	local hx, hz = sx / 2 - (inset or 0), sz / 2 - (inset or 0)
	local turn = cf * CFrame.Angles(0, math.rad(deg), 0)
	for _, c in ipairs({ { -hx, -hz }, { hx, -hz }, { hx, hz }, { -hx, hz }, { 0, -hz }, { hx, 0 }, { 0, hz }, { -hx, 0 } }) do
		out[#out + 1] = (turn * CFrame.new(c[1], 0, c[2])).Position
	end
	return out
end

-- does a battle square fit its floor at any rotation? solid ground at the floor height under every corner / edge
-- midpoint and no collidable part at walking height between the centre and each of them
local function squareFits(label, cf, sx, sz, anyRotation)
	local floorY = cf.Position.Y
	local bad = {}
	local params = RaycastParams.new()
	params.RespectCanCollide = true
	for deg = 0, anyRotation == false and 0 or 90, 15 do
		for _, p in ipairs(squareCorners(cf, sx, sz, deg, 0.5)) do
			local hit = surfaceBelow(Vector3.new(p.X, floorY + 1, p.Z), 8)
			if not hit then
				bad[#bad + 1] = string.format("%d deg: no floor under (%.0f, %.0f)", deg, p.X, p.Z)
			elseif abs(hit.Position.Y - floorY) > 1.2 then
				bad[#bad + 1] = string.format("%d deg: surface at y %.1f under (%.0f, %.0f), floor %.1f", deg, hit.Position.Y, p.X, p.Z, floorY)
			end
			-- walking height: chest-high ray from the centre to the corner
			local from = cf.Position + Vector3.new(0, 2.5, 0)
			local to = Vector3.new(p.X, floorY + 2.5, p.Z)
			local block = workspace:Raycast(from, to - from, params)
			if block and block.Instance then
				bad[#bad + 1] = string.format("%d deg: %s stands in the square at walking height", deg, block.Instance:GetFullName())
			end
		end
		if #bad > 0 then
			break
		end
	end
	T.check(#bad == 0, label .. ": the " .. sx .. " x " .. sz .. " battle square fits " .. (anyRotation == false and "on its floor" or "at any rotation") .. " (solid floor, nothing in the way)", table.concat(bad, "; "))
end

local function themeFonts()
	local Theme = K.M["shared/Theme"]
	local set = {}
	if Theme and type(Theme.Fonts) == "table" then
		for _, f in pairs(Theme.Fonts) do
			set[f] = true
		end
	end
	return set
end

----------------------------------------------------------------------------------------------------
-- scenario: the arena world
----------------------------------------------------------------------------------------------------
S.p3arena_world = guarded("p3arena_world", function()
	if not K.needBoot() then
		return
	end
	local AB = arenaBuilder()
	T.check(AB ~= nil, "arena: server/Services/ArenaBuilder.lua loads")
	if not AB then
		return
	end
	for _, fn in ipairs({ "Build", "BuildPocket", "FreePocket", "GetInfo", "ApplyArenaState", "InArena", "ZoneAt" }) do
		T.check(type(AB[fn]) == "function", "arena: ArenaBuilder." .. fn .. " exists")
	end
	local info = AB.GetInfo and AB.GetInfo()
	local model = workspace:FindFirstChild("BattleArena")
	T.check(type(info) == "table" and model ~= nil and info.Model == model, "arena: Main built workspace.BattleArena and ArenaInfo.Model is it")
	if type(info) ~= "table" or not model then
		return
	end
	T.check(model:IsA("Model"), "arena: BattleArena is a Model")

	-- contract shape
	T.check(typeof(info.Center) == "CFrame", "arena: ArenaInfo.Center is a CFrame")
	T.check(type(info.Floor) == "table" and typeof(info.Floor.CFrame) == "CFrame" and typeof(info.Floor.Size) == "Vector3", "arena: ArenaInfo.Floor = { CFrame, Size }")
	T.check(type(info.Rings) == "table" and #info.Rings >= 2, "arena: ArenaInfo.Rings holds 2+ duel rings", type(info.Rings) == "table" and (#info.Rings .. " rings") or "none")
	T.check(typeof(info.Spawn) == "CFrame" and typeof(info.ReturnCFrame) == "CFrame", "arena: ArenaInfo.Spawn and ReturnCFrame are CFrames")
	T.check(info.TrialPortal == nil, "arena: ArenaInfo.TrialPortal is gone (Phase 5: no Trials)")
	T.check(typeof(info.LobbyCFrame) == "CFrame", "arena: ArenaInfo.LobbyCFrame is a CFrame (in front of Portal_Arena)")
	local rx, rz = zoneSize("Raid")
	local dx, dz = zoneSize("Duel")
	if type(info.Floor) == "table" and typeof(info.Floor.Size) == "Vector3" then
		T.check(abs(info.Floor.Size.X - rx) < 0.01 and abs(info.Floor.Size.Z - rz) < 0.01, "arena: the boss floor's Size is BattleCatalog.Zones.Raid", tostring(info.Floor.Size))
		T.check(abs(info.Floor.CFrame.UpVector.Y - 1) < 1e-3, "arena: the floor CFrame is level (the snapshot frame is x / z on it)")
	end

	-- budget and hygiene
	local parts = partsOf(model)
	T.check(#parts <= 2800, "arena: the Battle Arena (island, bridge, the forum's Return gate) stays <= 2800 parts (10.3)", #parts .. " parts")
	T.check(#parts >= 800, "arena: the arena is detailed (more than 800 parts)", #parts .. " parts")
	T.info("*arena: " .. #parts .. " parts, link " .. tostring(info.Link) .. ", " .. Mock.CountDescendants(model, "PointLight") .. " lights, " .. Mock.CountDescendants(model, "ParticleEmitter") .. " emitters")
	local loose, junk = 0, {}
	for _, p in ipairs(parts) do
		if not p.Anchored then
			loose = loose + 1
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("Decal") or d:IsA("Texture") or d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Sound") or d:IsA("MeshPart") then
			junk[#junk + 1] = d.ClassName .. " " .. d:GetFullName()
		end
	end
	T.check(loose == 0, "arena: every part is anchored", loose .. " loose")
	T.check(#junk == 0, "arena: no scripts, welds, decals, sounds or meshes (built in code, no asset ids)", table.concat(junk, "; "))
	local pal = K.paletteAudit(model, { maxNeonFace = 220 })
	T.check(pal.bigNeonCount == 0, "arena: Neon only for small accents", table.concat(pal.bigNeon, "; "))

	-- battle zones
	local zones = {}
	for _, z in ipairs(CollectionService:GetTagged("NC_BattleZone")) do
		if z:IsDescendantOf(model) then
			zones[#zones + 1] = z
		end
	end
	local raid, duel = {}, {}
	local zoneOk = T.tally("arena: every NC_BattleZone part has Mode / Size and is not collidable")
	for _, z in ipairs(zones) do
		local mode, size = z:GetAttribute("Mode"), z:GetAttribute("Size")
		zoneOk:case(z:IsA("BasePart") and (mode == "Raid" or mode == "Duel") and typeof(size) == "Vector3" and z.CanCollide == false and z.Transparency >= 1, z:GetFullName())
		if mode == "Raid" then
			raid[#raid + 1] = z
		elseif mode == "Duel" then
			duel[#duel + 1] = z
		end
	end
	zoneOk:report()
	T.check(#raid == 1, "arena: one Raid zone (the boss floor)", #raid .. " found")
	T.check(#duel >= 2 and #duel == #info.Rings, "arena: one Duel zone per duel ring", #duel .. " zones, " .. #info.Rings .. " rings")
	if raid[1] then
		local s = raid[1]:GetAttribute("Size")
		T.check(typeof(s) == "Vector3" and abs(s.X - rx) < 0.01 and abs(s.Z - rz) < 0.01, "arena: the Raid zone's Size attribute is BattleCatalog.Zones.Raid", tostring(s))
		T.check(AB.ZoneAt(info.Floor.CFrame.Position + Vector3.new(0, 2, 0)) == raid[1], "arena: ZoneAt(the floor centre) is the Raid zone")
	end
	T.check(AB.ZoneAt(info.Spawn.Position) == nil, "arena: the arrival point is outside every battle zone")
	-- the safe-zone rule (contract 3.11): battle zones exist only in the arena (floor + duel rings) and the pockets
	local stray = {}
	for _, z in ipairs(CollectionService:GetTagged("NC_BattleZone")) do
		if z:IsDescendantOf(workspace) and not z:IsDescendantOf(model) then
			local holder = workspace:FindFirstChild("BattlePockets")
			if not (holder and z:IsDescendantOf(holder)) then
				stray[#stray + 1] = z:GetFullName()
			end
		end
	end
	T.check(#stray == 0, "safe zones: every NC_BattleZone is in the Battle Arena or a battle pocket", table.concat(stray, "; "))
	local plazaOrigin = config().Lobby.Origin
	T.check(AB.ZoneAt(plazaOrigin + Vector3.new(0, 3, 0)) == nil, "safe zones: the plaza is outside every battle zone")
	T.check(AB.InArena(info.Spawn.Position) == true and AB.InArena(info.Floor.CFrame.Position) == true, "arena: InArena is true on the forum and the floor")
	T.check(AB.InArena(config().Lobby.Origin) == false, "arena: InArena is false on the plaza")
	T.check(AB.InArena(nil) == false and AB.InArena("x") == false and AB.ZoneAt({}) == nil, "arena: InArena / ZoneAt refuse junk")
	squareFits("arena boss floor", info.Floor.CFrame, rx, rz)

	-- duel rings: size, zone, pads with Arena prompts, the square fits
	for i, ring in ipairs(info.Rings) do
		local label = "arena duel ring " .. i
		T.check(typeof(ring.CFrame) == "CFrame" and typeof(ring.Size) == "Vector3" and type(ring.Pads) == "table", label .. ": { CFrame, Size, Pads }")
		if typeof(ring.Size) == "Vector3" then
			T.check(abs(ring.Size.X - dx) < 0.01 and abs(ring.Size.Z - dz) < 0.01, label .. ": Size is BattleCatalog.Zones.Duel", tostring(ring.Size))
		end
		local z = typeof(ring.CFrame) == "CFrame" and AB.ZoneAt(ring.CFrame.Position + Vector3.new(0, 2, 0))
		T.check(z ~= nil and z:GetAttribute("Mode") == "Duel", label .. ": ZoneAt(its centre) is a Duel zone")
		local padsOk = type(ring.Pads) == "table" and #ring.Pads >= 1
		for _, pad in ipairs(type(ring.Pads) == "table" and ring.Pads or {}) do
			local found = false
			for _, pr in ipairs(promptsUnder(pad)) do
				if pr:GetAttribute("OpenPanel") == "Arena" and pr.Enabled and pr.ActionText ~= "" then
					found = true
				end
			end
			if not (typeof(pad) == "Instance" and pad:IsA("BasePart") and pad:IsDescendantOf(model) and found) then
				padsOk = false
			end
		end
		T.check(padsOk, label .. ": challenge pads carry an enabled prompt with OpenPanel = \"Arena\"")
		if typeof(ring.CFrame) == "CFrame" then
			squareFits(label, ring.CFrame, dx, dz)
			-- rings never overlap the colosseum or each other
			for j, other in ipairs(info.Rings) do
				if j > i and typeof(other.CFrame) == "CFrame" then
					T.check(hdist(ring.CFrame.Position, other.CFrame.Position) > max(dx, dz) * 1.2, label .. ": apart from ring " .. j)
				end
			end
			T.check(hdist(ring.CFrame.Position, info.Floor.CFrame.Position) > rx / 2 + dx / 2 + 10, label .. ": outside the colosseum floor")
		end
	end

	-- every prompt: sane, panel prompts carry a known panel id
	local prompts = promptsUnder(model)
	local promptOk = T.tally("arena: every prompt has an action, a range <= 14 and (when it opens a window) OpenPanel Arena / Ring")
	for _, pr in ipairs(prompts) do
		local panel = pr:GetAttribute("OpenPanel")
		promptOk:case(pr.ActionText ~= "" and pr.MaxActivationDistance <= 14 and (panel == nil or panel == "Arena" or panel == "Ring"), pr:GetFullName())
	end
	promptOk:report()

	-- Phase 5 (6.1 / 6.2 / 10.5): no Trial Portal anywhere; Portal_Ring and Portal_Arena are WorldStyle gates in the Gate
	-- Court (LobbyInfo.GatesFolder) at their GateSites
	local Config = config()
	local origin = Config.Lobby.Origin
	local lobbyM = workspace:FindFirstChild("NimbusLobby")
	T.check(model:FindFirstChild("Portal_Trials", true) == nil and (lobbyM == nil or lobbyM:FindFirstChild("Portal_Trials", true) == nil), "trial portal: Portal_Trials is gone")
	local lobbyInfo0 = K.W and K.W.lobbyInfo
	local gatesFolder = type(lobbyInfo0) == "table" and lobbyInfo0.GatesFolder or nil
	local sites = type(lobbyInfo0) == "table" and type(lobbyInfo0.GateSites) == "table" and lobbyInfo0.GateSites or {}
	T.check(typeof(gatesFolder) == "Instance" and gatesFolder.Name == "Gates" and gatesFolder.Parent == lobbyM, "gates: LobbyInfo.GatesFolder is workspace.NimbusLobby.Gates")
	local ringSite = type(lobbyInfo0) == "table" and lobbyInfo0.RingSite or nil
	T.check(typeof(ringSite) == "CFrame" and typeof(sites.Ring) == "CFrame" and ringSite == sites.Ring, "ring portal: LobbyInfo.RingSite = GateSites.Ring (C12)")
	local ringPortal = typeof(gatesFolder) == "Instance" and gatesFolder:FindFirstChild("Portal_Ring") or nil
	T.check(ringPortal ~= nil and ringPortal:IsA("Model") and model:FindFirstChild("Portal_Ring", true) == nil, "ring portal: Portal_Ring stands in the Gates folder (not in workspace.BattleArena)")
	local rp = info.RingPortal
	T.check(typeof(rp) == "Instance" and rp:IsA("BasePart") and ringPortal ~= nil and rp:IsDescendantOf(ringPortal), "ring portal: ArenaInfo.RingPortal is a BasePart of Portal_Ring (its pad)")
	T.check(typeof(info.RingSite) == "CFrame" and typeof(ringSite) == "CFrame" and (info.RingSite.Position - ringSite.Position).Magnitude < 0.01, "ring portal: ArenaInfo.RingSite = LobbyInfo.RingSite")
	if ringPortal and typeof(rp) == "Instance" and typeof(ringSite) == "CFrame" then
		local nRing = #partsOf(ringPortal)
		T.check(nRing <= 120 and nRing >= 60, "ring portal: Portal_Ring is detailed and within 120 parts (6.2)", nRing .. " parts")
		T.eq(ringPortal:GetAttribute("GateId"), "Ring", "ring portal: a WorldStyle gate (GateId = Ring)")
		local ringPrompt = rp:FindFirstChild("RingPrompt")
		T.check(ringPrompt ~= nil and ringPrompt:IsA("ProximityPrompt") and ringPrompt.Enabled and ringPrompt:GetAttribute("OpenPanel") == "Ring" and ringPrompt.ActionText ~= "",
			"ring portal: its pad carries RingPrompt (enabled, OpenPanel = \"Ring\")")
		T.check(ringPrompt ~= nil and ringPrompt.MaxActivationDistance >= 8 and ringPrompt.MaxActivationDistance <= 14 and ringPrompt.HoldDuration == 0,
			"ring portal: RingPrompt is a quick E within 8-14 studs", ringPrompt and tostring(ringPrompt.MaxActivationDistance) or "")
		local padFront = (ringSite.Position + ringSite.LookVector * 14)
		T.check(hdist(rp.Position, padFront) < 1 and abs(rp.Position.Y - origin.Y) <= 1.5, "ring portal: the pad lies 14 studs in front of the gate, at plaza height", "off " .. fmt(hdist(rp.Position, padFront), 2))
		local toCentre = Vector3.new(origin.X - ringSite.Position.X, 0, origin.Z - ringSite.Position.Z).Unit
		T.check(ringSite.LookVector:Dot(toCentre) > 0.98, "ring portal: RingSite looks at the plaza centre")
		T.check(surfaceBelow(rp.Position + Vector3.new(0, 1, 0), 8) ~= nil, "ring portal: its pad stands on solid ground")
		-- the tag: title, info and the RingBoard pill
		local bill = ringPortal:FindFirstChild("GateTag", true)
		local title = bill and bill:FindFirstChild("Title", true)
		local infoL = bill and bill:FindFirstChild("Info", true)
		local pillF = bill and bill:FindFirstChild("Pill", true)
		local pill = pillF and (pillF:FindFirstChild("Label") or pillF:FindFirstChild("PillLabel"))
		T.check(title ~= nil and title.Text == "Champion Ring" and infoL ~= nil and infoL.Text == "Beat the champion, meet a stronger one", "ring portal: the tag reads 'Champion Ring' / 'Beat the champion, meet a stronger one'",
			(title and title.Text or "?") .. " / " .. (infoL and infoL.Text or "?"))
		-- (BattleService may already have written a board in this server: keep it and put it back afterwards)
		local savedModel, savedPad = ringPortal:GetAttribute("RingBoard"), rp:GetAttribute("RingBoard")
		ringPortal:SetAttribute("RingBoard", nil)
		rp:SetAttribute("RingBoard", nil)
		advance(0.1)
		T.check(pill ~= nil and pill.Text ~= "" and not pill.Text:find("Round") and pillF.Visible, "ring portal: without a RingBoard the pill invites a first record", pill and pill.Text or "no pill")
		if pill then
			ringPortal:SetAttribute("RingBoard", "Alex|31;Sam|24;Kim|20")
			advance(0.1)
			T.check(pill.Text == "Best in this server: Alex - Round 31", "ring portal: RingBoard 'Alex|31;Sam|24;Kim|20' -> 'Best in this server: Alex - Round 31'", pill.Text)
			rp:SetAttribute("RingBoard", "Kim|20;Zoe|45")
			advance(0.1)
			T.check(pill.Text == "Best in this server: Zoe - Round 45", "ring portal: the pad's RingBoard works too and the best round wins", pill.Text)
			ringPortal:SetAttribute("RingBoard", "AVeryVeryLongPlayerName123|12")
			advance(0.1)
			T.check(pill.Text:find("...", 1, true) ~= nil and #pill.Text <= 50, "ring portal: a long name is cut with '...'", pill.Text)
			local junkOk = true
			for _, junk in ipairs({ "", "x", "|5", "Bob|", ";;;", "Bob|-3", "<>|5", "A|99999999999999", string.rep("A|1;", 200) }) do
				local okJ = pcall(function()
					ringPortal:SetAttribute("RingBoard", junk)
				end)
				advance(0.05)
				if not okJ or pill.Text == "" then
					junkOk = false
				end
			end
			T.check(junkOk, "ring portal: junk RingBoard values never error or blank the pill", pill.Text)
			ringPortal:SetAttribute("RingBoard", nil)
			rp:SetAttribute("RingBoard", nil)
		end
		rp:SetAttribute("RingBoard", savedPad)
		ringPortal:SetAttribute("RingBoard", savedModel)
		-- the crown motif: the crown glyph and two crowned pedestals (no crossed swords)
		local crown = 0
		for _, d in ipairs(ringPortal:GetDescendants()) do
			if d:IsA("BasePart") and (d.Name == "CrownBand" or d.Name == "CrownPoint") then
				crown = crown + 1
			end
		end
		T.check(crown >= 6 and ringPortal:GetAttribute("Glyph") == "crown", "ring portal: the crown glyph and crowned pedestals", crown .. " crown parts")
		T.check(AB.ZoneAt(rp.Position + Vector3.new(0, 2, 0)) == nil, "ring portal: the portal is a safe zone (no battle zone on the plaza)")
	end
	-- Portal_Arena: always built, ArenaPortalPrompt -> Spawn; the forum's Return gate -> in front of Portal_Arena
	local arenaPortal = typeof(gatesFolder) == "Instance" and gatesFolder:FindFirstChild("Portal_Arena") or nil
	if T.check(arenaPortal ~= nil and arenaPortal:IsA("Model") and typeof(sites.Arena) == "CFrame", "arena portal: Portal_Arena stands in the Gates folder (always, 6.2)") then
		local n = #partsOf(arenaPortal)
		T.check(n <= 120 and n >= 40, "arena portal: within 120 parts", n .. " parts")
		T.check(hdist(arenaPortal:GetPivot().Position, sites.Arena.Position) < 1, "arena portal: at GateSites.Arena")
		local found = nil
		for _, pr in ipairs(promptsUnder(arenaPortal)) do
			if pr.Name == "ArenaPortalPrompt" then
				found = pr
			end
		end
		T.check(found ~= nil and found.Enabled and found.MaxActivationDistance <= 14 and found:GetAttribute("OpenPanel") == nil, "arena portal: it carries ArenaPortalPrompt (a travel prompt, no panel)")
		T.check(typeof(info.LobbyCFrame) == "CFrame" and hdist(info.LobbyCFrame.Position, sites.Arena.Position) < 16 and surfaceBelow(info.LobbyCFrame.Position, 10) ~= nil, "arena portal: LobbyCFrame stands on the court in front of Portal_Arena")
		T.check(typeof(info.LobbyCFrame) == "CFrame" and info.LobbyCFrame.LookVector:Dot(sites.Arena.LookVector) > 0.9, "arena portal: LobbyCFrame looks at the plaza")
	end
	local returnGate = model:FindFirstChild("Portal_Return", true)
	local returnPrompt = returnGate and returnGate:FindFirstChild("ArenaReturnPrompt", true)
	T.check(returnGate ~= nil and returnPrompt ~= nil and AB.InArena(returnGate:GetPivot().Position), "arena: the forum's Return gate carries ArenaReturnPrompt")
	-- ReturnCFrame: in front of Portal_Ring, on solid ground (ring climbers come back there)
	if typeof(ringSite) == "CFrame" then
		local ret = info.ReturnCFrame.Position
		T.check(hdist(ret, ringSite.Position + ringSite.LookVector * 12) < 2 and surfaceBelow(ret, 10) ~= nil, "ring portal: ReturnCFrame stands on the court in front of Portal_Ring")
	end

	-- placement: nothing of the lobby inside the island's outline, plots / altar / portals clear, below the dragon
	local lobby = workspace:FindFirstChild("NimbusLobby")
	local inside = {}
	if lobby then
		for _, p in ipairs(partsOf(lobby)) do
			if p.Transparency < 1 and AB.InArena(p.Position) then
				inside[#inside + 1] = p:GetFullName()
				if #inside >= 5 then
					break
				end
			end
		end
	end
	T.check(#inside == 0, "arena placement: no lobby part lies inside the arena island", table.concat(inside, "; "))
	local W = K.W
	local lobbyInfo = W and W.lobbyInfo
	local plotHits = {}
	local half = (Config.Lobby.PlotSize or 72) / 2
	for _, spot in ipairs(type(lobbyInfo) == "table" and type(lobbyInfo.Spots) == "table" and lobbyInfo.Spots or {}) do
		local cf = type(spot) == "table" and (spot.PlotCFrame or spot.CFrame) or nil
		if typeof(cf) == "CFrame" then
			for _, c in ipairs({ { 0, 0 }, { -half, -half }, { half, -half }, { half, half }, { -half, half } }) do
				local p = (cf * CFrame.new(c[1], 0, c[2])).Position
				if AB.InArena(p) then
					plotHits[#plotHits + 1] = tostring(spot.Index or "?")
				end
			end
		end
	end
	T.check(#plotHits == 0, "arena placement: no home plot reaches into the arena island", table.concat(plotHits, ", "))
	local altar = lobby and lobby:FindFirstChild("StormAltar", true)
	if altar then
		local ok, pivot = pcall(function()
			return altar:GetPivot().Position
		end)
		T.check(ok and not AB.InArena(pivot) and hdist(pivot, info.Center.Position) > 150, "arena placement: far from the Storm Altar")
	end
	local top = -huge
	for _, p in ipairs(parts) do
		top = max(top, p.Position.Y + p.Size.Y / 2)
	end
	T.check(top < origin.Y + 70, "arena placement: the arena stays low (the sky dragon flies 120+ studs over the lobby)", "top y " .. fmt(top, 1))
	local centreR = hdist(info.Center.Position, origin)
	T.check(centreR > (Config.Lobby.SpotRingRadius or 300), "arena placement: beyond the ring of home plots", fmt(centreR, 0) .. " studs out")

	-- the link (the bridge stays when its corridor is clear; Portal_Arena links it always)
	T.check(info.Link == "Bridge" or info.Link == "Portal", "arena link: Bridge or Portal", tostring(info.Link))
	if info.Link == "Bridge" then
		local dock = type(lobbyInfo) == "table" and lobbyInfo.ArenaDock
		T.check(typeof(dock) == "Vector3", "arena link: the lobby reserved a dock (LobbyInfo.ArenaDock)")
		if typeof(dock) == "Vector3" then
			local goal = info.Spawn.Position
			local flat = Vector3.new(goal.X - dock.X, 0, goal.Z - dock.Z)
			local len = flat.Magnitude
			local dir = flat.Unit
			local gaps = {}
			local s = -6
			while s <= len do
				local p = dock + dir * s
				local hit = surfaceBelow(Vector3.new(p.X, origin.Y + 1, p.Z), 6)
				if not hit then
					gaps[#gaps + 1] = fmt(s, 0)
				end
				s = s + 2
			end
			T.check(#gaps == 0, "arena link: the bridge is walkable from the street to the arrival point (no gaps)", #gaps .. " gaps at " .. table.concat(gaps, ", "))
			local params = RaycastParams.new()
			params.RespectCanCollide = true
			local from = dock - dir * 4 + Vector3.new(0, 2.5, 0)
			local block = workspace:Raycast(from, dir * (len + 4), params)
			T.check(block == nil, "arena link: nothing collidable blocks the walk at chest height", block and block.Instance and block.Instance:GetFullName() or "")
			T.check(model:FindFirstChild("ArenaBridge", true) ~= nil, "arena link: the ArenaBridge model exists")
		end
	else
		local names = {}
		for _, pr in ipairs(prompts) do
			names[pr.Name] = true
		end
		T.check(names.ArenaReturnPrompt == true, "arena link: the forum's Return gate (Portal_Arena is in the Gate Court)")
	end
	T.check(surfaceBelow(info.Spawn.Position, 10) ~= nil, "arena: the arrival point (Spawn) stands on solid ground")

	-- world text (World text rule) + Theme fonts
	local fonts = themeFonts()
	local textOk = T.tally("arena text: SurfaceGuis at 40-60 px per stud with letters >= 0.6 stud (TextSize <= 100), never TextScaled")
	local billOk = T.tally("arena text: BillboardGuis sized in pixels, LightInfluence 0, MaxDistance 40-130, text >= 18 px")
	local fontOk = T.tally("arena text: every label uses a Theme font role")
	local strokeOk = T.tally("arena text: every label has a stroke or sits on a solid panel")
	for _, gui in ipairs(findAll(model, function(d)
		return d:IsA("SurfaceGui") or d:IsA("BillboardGui")
	end)) do
		local labels = findAll(gui, function(d)
			return d:IsA("TextLabel") or d:IsA("TextButton")
		end)
		if gui:IsA("SurfaceGui") then
			local pps = gui.PixelsPerStud
			local okGui = gui.SizingMode == Enum.SurfaceGuiSizingMode.PixelsPerStud and pps >= 40 and pps <= 60
			for _, l in ipairs(labels) do
				textOk:case(okGui and not l.TextScaled and l.TextSize / pps >= 0.6 - 1e-6 and l.TextSize <= 100, l:GetFullName() .. " (" .. tostring(l.TextSize) .. " px at " .. tostring(pps) .. ")")
			end
		else
			local sizeOk = gui.Size.X.Scale == 0 and gui.Size.Y.Scale == 0 and gui.LightInfluence == 0 and gui.MaxDistance >= 40 and gui.MaxDistance <= 130
			for _, l in ipairs(labels) do
				billOk:case(sizeOk and not l.TextScaled and l.TextSize >= 18, l:GetFullName() .. " (" .. tostring(l.TextSize) .. " px)")
			end
		end
		for _, l in ipairs(labels) do
			if next(fonts) ~= nil then
				fontOk:case(fonts[l.Font] == true, l:GetFullName() .. " " .. tostring(l.Font))
			end
			local stroke = l.TextStrokeTransparency < 1 or l:FindFirstChildOfClass("UIStroke") ~= nil
			local panel = false
			local a = l.Parent
			while a and a ~= gui do
				if a:IsA("GuiObject") and a.BackgroundTransparency <= 0.4 then
					panel = true
				end
				a = a.Parent
			end
			strokeOk:case(stroke or panel, l:GetFullName())
		end
	end
	textOk:report()
	billOk:report()
	fontOk:report()
	strokeOk:report()
	T.check(model:FindFirstChild("EventBoard", true) ~= nil and model:FindFirstChild("Leaderboard", true) ~= nil, "arena: the event board and the trophy leaderboard exist")
	K.flushErrors("p3arena_world")
	K.flushWarnings("p3arena_world")
end)

----------------------------------------------------------------------------------------------------
-- scenario: the boards
----------------------------------------------------------------------------------------------------
local function boardText(model, name)
	local b = model:FindFirstChild(name, true)
	return b and K.plainText(K.textsUnder(b)) or ""
end

local function visibleText(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" then
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

S.p3arena_boards = guarded("p3arena_boards", function()
	if not K.needBoot() then
		return
	end
	local AB = arenaBuilder()
	local info = AB and AB.GetInfo()
	if not info then
		T.fail("boards: no arena")
		return
	end
	local model = info.Model
	local board = model:FindFirstChild("EventBoard", true)
	local leaders = model:FindFirstChild("Leaderboard", true)
	T.check(board ~= nil and leaders ~= nil, "boards: EventBoard + Leaderboard")
	if not board or not leaders then
		return
	end
	advance(2)
	local idle = visibleText(board)
	-- EventService draws its next raid (NEXT: BOSS RAID, the boss, a countdown); without it the board shows the schedule;
	-- a scheduled raid that happens to be running when this scenario starts (the shared game clock of a full run) shows
	-- BOSS RAID LIVE, which is right too
	T.check(idle:find("NEXT: BOSS RAID", 1, true) ~= nil or idle:find("Every %d+ minutes") ~= nil or idle:find("BOSS RAIDS") ~= nil or idle:find("BOSS RAID LIVE", 1, true) ~= nil,
		"boards: the event board shows when the next Boss Raid comes (EventService's state, or the schedule without it)", idle)

	local BC = battleCatalog()
	local bossId, bossName = nil, nil
	if BC and type(BC.Bosses) == "table" then
		for id, b in pairs(BC.Bosses) do
			if type(b) == "table" and type(b.Name) == "string" and (bossId == nil or tostring(id) < bossId) then
				bossId, bossName = id, b.Name
			end
		end
	end
	bossId = bossId or "storm_titan"
	local list = {}
	for i = 1, 12 do
		list[i] = { UserId = 500 + i, Name = (i == 3) and string.rep("VeryLongPlayerName", 4) or ("Champ" .. i), Trophies = 5000 - i * 100 }
	end
	-- EventService redraws the boards with the live state on its own broadcasts (every few seconds, at a phase set by
	-- whatever ran before): hold them while this state is checked, or the 5 s wait may show the real players / raid
	local esInst = K.moduleInstance("server/Services/EventService")
	local okES, ES = false, nil
	if esInst then
		okES, ES = pcall(require, esInst)
	end
	ES = (okES and type(ES) == "table") and ES or nil
	local realBroadcast = ES and ES.Broadcast
	if realBroadcast then
		ES.Broadcast = function(player)
			if player ~= nil then
				return realBroadcast(player)
			end
			return nil
		end
	end
	local ok = AB.ApplyArenaState({ Next = { Kind = "BossRaid", BossId = bossId, StartsIn = 120 }, Leaderboard = list })
	T.check(ok == true, "boards: ApplyArenaState accepts a state")
	local text = visibleText(board)
	T.check(text:find("2:00", 1, true) ~= nil, "boards: the countdown shows 2:00", text)
	if bossName then
		T.check(text:find(bossName, 1, true) ~= nil, "boards: the next boss is named (" .. bossName .. ")", text)
	end
	local okWait, waitErr = pcall(advance, 5.2)
	if realBroadcast then
		ES.Broadcast = realBroadcast
	end
	if not okWait then
		error(waitErr, 0)
	end
	text = visibleText(board)
	T.check(text:find("1:5[4-6]") ~= nil, "boards: the countdown ticks down between two states (about 1:55 after 5 s)", text)
	local lt = visibleText(leaders)
	T.check(lt:find("Champ1", 1, true) ~= nil and lt:find("Champ10", 1, true) ~= nil and lt:find("Champ11", 1, true) == nil, "boards: the leaderboard shows the top 10 rows only", lt)
	T.check(lt:find("4,900", 1, true) ~= nil, "boards: trophies with thousands separators", lt)
	local longOk = true
	for _, l in ipairs(findAll(leaders, function(d)
		return d:IsA("TextLabel") and d.Name == "PlayerName"
	end)) do
		if #l.Text > 30 then
			longOk = false
		end
	end
	T.check(longOk, "boards: a long player name is cut to fit its row")

	-- a live raid and double rewards
	AB.ApplyArenaState({ Raid = { Active = true, BossId = bossId, Hp = 500, MaxHp = 1000, Players = 3, EndsIn = 90 }, Double = { Active = true, EndsIn = 600 }, Leaderboard = { list[1] } })
	text = visibleText(board)
	T.check(text:find("LIVE", 1, true) ~= nil and text:find("50%", 1, true) ~= nil and text:find("3 fighters", 1, true) ~= nil, "boards: a live raid shows LIVE, the boss HP and the fighters", text)
	T.check(text:find("x2", 1, true) ~= nil and text:find("10:00", 1, true) ~= nil, "boards: Double Rewards shows its pill with the time left", text)
	lt = visibleText(leaders)
	T.check(lt:find("Champ1", 1, true) ~= nil and lt:find("Champ2", 1, true) == nil, "boards: empty rows hide", lt)
	AB.ApplyArenaState({ Leaderboard = {} })
	T.check(visibleText(leaders):find("No champions", 1, true) ~= nil, "boards: an empty leaderboard says so")

	-- junk never errors
	local junkOk = true
	for _, junk in ipairs({ 5, "x", true, {}, { Next = 5 }, { Next = { Kind = 5, StartsIn = "x" } }, { Raid = { Active = true, Hp = "x", MaxHp = 0, Players = {}, EndsIn = -5 } }, { Leaderboard = { 5, "x", { Name = 7 }, { UserId = "x", Trophies = -9 } } }, { Double = { Active = true, EndsIn = math.huge } } }) do
		local okCall = pcall(AB.ApplyArenaState, junk)
		if not okCall then
			junkOk = false
		end
	end
	T.check(junkOk, "boards: junk states never error")
	T.check(AB.ApplyArenaState(nil) == false, "boards: a nil state is refused")
	K.flushErrors("p3arena_boards")
	K.flushWarnings("p3arena_boards")
end)

----------------------------------------------------------------------------------------------------
-- scenario: private trial pockets
----------------------------------------------------------------------------------------------------
S.p3arena_pockets = guarded("p3arena_pockets", function()
	if not K.needBoot() then
		return
	end
	local AB = arenaBuilder()
	if not AB then
		T.fail("pockets: no ArenaBuilder")
		return
	end
	local Config = config()
	local tx, tz = zoneSize("Ring")
	local p1 = AB.BuildPocket(1)
	T.check(type(p1) == "table" and typeof(p1.Model) == "Instance" and typeof(p1.CFrame) == "CFrame" and typeof(p1.Size) == "Vector3" and typeof(p1.Spawn) == "CFrame", "pockets: BuildPocket(1) -> { Model, CFrame, Size, Spawn }")
	if type(p1) ~= "table" or typeof(p1.Model) ~= "Instance" then
		return
	end
	T.check(p1.Model:IsDescendantOf(workspace), "pockets: the pocket is in the workspace")
	T.check(abs(p1.Size.X - tx) < 0.01 and abs(p1.Size.Z - tz) < 0.01 and p1.Kind == "Ring", "pockets: BuildPocket(1) builds the Champion Ring pocket (Phase 5: the only kind; Size = BattleCatalog.Zones.Ring)", tostring(p1.Size))
	local n = #partsOf(p1.Model)
	T.check(n <= 250 and n >= 100, "pockets: a detailed pocket within 250 parts", n .. " parts")
	T.check(AB.BuildPocket(1) == p1, "pockets: building an existing index returns the same pocket")
	local origin = Config.Lobby.Origin
	T.check((p1.CFrame.Position - origin).Magnitude > 1500, "pockets: far out in the sky (> 1500 studs from the lobby)", fmt((p1.CFrame.Position - origin).Magnitude, 0))
	local arenaOrigin = Config.Match and Config.Match.ArenaOrigin or Vector3.new(4000, 800, 0)
	T.check((p1.CFrame.Position - arenaOrigin).Magnitude > 1500, "pockets: far from the obby match slots")
	T.check(abs(p1.CFrame.UpVector.Y - 1) < 1e-3, "pockets: the floor CFrame is level")
	local z = AB.ZoneAt(p1.CFrame.Position + Vector3.new(0, 2, 0))
	T.check(z ~= nil and z:GetAttribute("Mode") == "Ring" and z:IsDescendantOf(p1.Model), "pockets: a Ring zone (NC_BattleZone) covers the floor")
	T.check(z ~= nil and CollectionService:HasTag(z, "NC_BattleZone"), "pockets: the zone is tagged NC_BattleZone")
	squareFits("pocket 1", p1.CFrame, tx, tz, true)
	T.check(surfaceBelow(p1.Spawn.Position, 10) ~= nil and AB.ZoneAt(p1.Spawn.Position) == z, "pockets: Spawn stands on the floor inside the zone")
	local pockets = { p1 }
	for i = 2, 10 do
		pockets[i] = AB.BuildPocket(i)
	end
	local minGap = huge
	for i = 1, #pockets do
		for j = i + 1, #pockets do
			if pockets[i] and pockets[j] then
				minGap = min(minGap, (pockets[i].CFrame.Position - pockets[j].CFrame.Position).Magnitude)
			end
		end
	end
	T.check(#pockets == 10 and minGap > 250, "pockets: ten pockets at once, each on its own spot (> 250 studs apart)", fmt(minGap, 0))
	-- clones of one template: same part count
	T.check(pockets[2] and #partsOf(pockets[2].Model) == n, "pockets: every pocket is a clone of one template")
	-- free
	local m2 = pockets[2].Model
	T.check(AB.FreePocket(pockets[2]) == true and m2.Parent == nil, "pockets: FreePocket(zone table) removes the pocket")
	T.check(AB.FreePocket(pockets[2]) == false, "pockets: freeing it twice is a no-op")
	T.check(AB.BuildPocket(2) ~= nil and AB.BuildPocket(2).Model ~= m2, "pockets: the index can be built again")
	-- Phase 4: the Champion Ring pocket (BuildPocket(index, "Ring"), contract 3.8)
	local gx, gz = zoneSize("Ring")
	local ring = AB.BuildPocket(11, "Ring")
	T.check(type(ring) == "table" and typeof(ring.Model) == "Instance" and typeof(ring.CFrame) == "CFrame" and typeof(ring.Size) == "Vector3" and typeof(ring.Spawn) == "CFrame" and ring.Index == 11,
		"ring pocket: BuildPocket(11, \"Ring\") -> { Model, CFrame, Size, Spawn, Zone, Index }")
	if type(ring) == "table" and typeof(ring.Model) == "Instance" then
		T.check(ring.Kind == "Ring", "ring pocket: Kind = \"Ring\"", tostring(ring.Kind))
		T.check(abs(ring.Size.X - gx) < 0.01 and abs(ring.Size.Z - gz) < 0.01 and abs(gx - 44) < 0.01, "ring pocket: Size is BattleCatalog.Zones.Ring (44 x 44)", tostring(ring.Size))
		local nr = #partsOf(ring.Model)
		T.check(nr >= 100 and nr <= 250, "ring pocket: a detailed pocket within the 100..250 window", nr .. " parts")
		T.check(nr <= 250, "ring pocket: within its budget (Phase 5 art pass: 250; 10.3 counts 600 per pocket)", nr .. " parts")
		local rzone = AB.ZoneAt(ring.CFrame.Position + Vector3.new(0, 2, 0))
		T.check(rzone ~= nil and rzone:IsDescendantOf(ring.Model) and rzone:GetAttribute("Mode") == "Ring" and rzone:GetAttribute("ZoneId") == "Ring" and CollectionService:HasTag(rzone, "NC_BattleZone"),
			"ring pocket: ZoneAt(its centre) is its NC_BattleZone with Mode = \"Ring\", ZoneId = \"Ring\"", rzone and (tostring(rzone:GetAttribute("Mode")) .. "/" .. tostring(rzone:GetAttribute("ZoneId"))) or "none")
		local zsize = rzone and rzone:GetAttribute("Size")
		T.check(typeof(zsize) == "Vector3" and abs(zsize.X - gx) < 0.01 and abs(zsize.Z - gz) < 0.01 and rzone.CanCollide == false and rzone.Transparency >= 1, "ring pocket: the zone's Size attribute is the 44 x 44 floor, invisible, not collidable", tostring(zsize))
		T.check(rzone ~= nil and rzone:GetAttribute("Index") == 11, "ring pocket: the zone carries its pocket Index")
		squareFits("ring pocket", ring.CFrame, gx, gz, true)
		T.check(surfaceBelow(ring.Spawn.Position, 10) ~= nil and AB.ZoneAt(ring.Spawn.Position) == rzone, "ring pocket: Spawn stands on the floor inside the Ring zone")
		local look = ring.Spawn.LookVector
		T.check(look.Z > 0.9 and ring.Spawn.Position.Z < ring.CFrame.Position.Z, "ring pocket: the fighter starts on the -Z side looking at the champion's side")
		T.check(AB.BuildPocket(11, "Ring") == ring, "ring pocket: building the same index and kind returns the same pocket")
		T.check(abs(ring.CFrame.UpVector.Y - 1) < 1e-3 and (ring.CFrame.Position - Config.Lobby.Origin).Magnitude > 1500, "ring pocket: level and far out in the sky")
		local others = 0
		for i, pk in ipairs(pockets) do
			if pk and pk.Model and pk.Model.Parent and (pk.CFrame.Position - ring.CFrame.Position).Magnitude < 250 then
				others = others + 1
			end
		end
		T.check(others == 0, "ring pocket: on its own spot of the shared pocket grid")
		-- the art the contract names: a gold rim, four crown posts and a cheering crowd of cloud puffs outside the square
		local rim, posts, puffs, inside = 0, 0, 0, {}
		for _, d in ipairs(ring.Model:GetDescendants()) do
			if d:IsA("BasePart") then
				if d.Name == "RingRim" then
					rim = rim + 1
				elseif d.Name == "CrownGem" then
					posts = posts + 1
				elseif d.Name == "PuffBody" then
					puffs = puffs + 1
				end
				local rel = ring.CFrame:PointToObjectSpace(d.Position)
				if d.CanCollide and d.Transparency < 1 and rel.Y > 0.6 and rel.Y < 6 and abs(rel.X) < gx / 2 and abs(rel.Z) < gz / 2 then
					inside[#inside + 1] = d.Name
				end
			end
		end
		T.check(rim >= 8 and posts == 4 and puffs >= 5, "ring pocket: a gold rim, four crown posts and a crowd of cloud puffs", rim .. " rim, " .. posts .. " posts, " .. puffs .. " puffs")
		T.check(#inside == 0, "ring pocket: nothing collidable stands in the 44 x 44 square", table.concat(inside, ", "))
		-- Phase 5: the Trial kind is gone: nil / "Trial" / unknown kinds return the same ring pocket
		local m11 = ring.Model
		T.check(AB.BuildPocket(11) == ring and AB.BuildPocket(11, "Trial") == ring and m11.Parent ~= nil, "ring pocket: BuildPocket(11) / (11, \"Trial\") keep the ring pocket (no Trial kind)")
		local again = ring
		local okJunk, junkKind = pcall(AB.BuildPocket, 12, "Banana")
		T.check(okJunk and type(junkKind) == "table" and junkKind.Kind == "Ring", "ring pocket: an unknown kind builds the ring pocket")
		AB.FreePocket(12)
		local zr = again.Zone
		T.check(AB.FreePocket(again) == true and again.Model.Parent == nil and zr.Parent == nil, "ring pocket: FreePocket removes the ring pocket and its zone")
	end
	for i = 1, 12 do
		AB.FreePocket(i)
	end
	local left = 0
	for _, t in ipairs(CollectionService:GetTagged("NC_BattleZone")) do
		if (t:GetAttribute("Mode") == "Trial" or t:GetAttribute("Mode") == "Ring") and t:IsDescendantOf(workspace) then
			left = left + 1
		end
	end
	T.check(left == 0, "pockets: freed pockets leave no Trial / Ring zone behind", left .. " left")
	T.check(workspace:FindFirstChild("BattlePockets") == nil, "pockets: the BattlePockets folder goes away with the last pocket")
	local junkOk = true
	for _, junk in ipairs({ 0, -1, 1.5, "x", 1e9, {}, true, 0 / 0 }) do
		local okCall, res = pcall(AB.BuildPocket, junk)
		if not okCall or res ~= nil then
			junkOk = false
		end
		local okFree = pcall(AB.FreePocket, junk)
		if not okFree then
			junkOk = false
		end
	end
	local okNil, resNil = pcall(AB.BuildPocket, nil)
	T.check(junkOk and okNil and resNil == nil and pcall(AB.FreePocket, nil), "pockets: junk indices / zones never error or build")
	K.flushErrors("p3arena_pockets")
	K.flushWarnings("p3arena_pockets")
end)

----------------------------------------------------------------------------------------------------
-- scenario: the home Arena Gate teleport
----------------------------------------------------------------------------------------------------
S.p3arena_teleport = guarded("p3arena_teleport", function()
	if not K.needBoot() then
		return
	end
	local AB = arenaBuilder()
	local info = AB and AB.GetInfo()
	if not info then
		T.fail("teleport: no arena")
		return
	end
	-- TycoonCatalog: the Arena Gate is a real station now
	local TC = K.M["shared/TycoonCatalog"]
	if TC then
		local def = TC.Get("ArenaGate")
		T.check(def ~= nil and def.ComingSoon == nil, "teleport: TycoonCatalog's ArenaGate has no ComingSoon flag (Phase 3)")
		local home = { Stations = { Press1 = 2, Press2 = 2, Collector = 1, Garden = 1, Kitchen = 1, Gym = 1 }, Prestige = 0, Garden = {}, Gym = {} }
		local pad = nil
		for _, p in ipairs(TC.AvailablePads(home)) do
			if p.StationId == "ArenaGate" then
				pad = p
			end
		end
		T.check(pad ~= nil and pad.Locked == nil, "teleport: the Arena Gate pad opens once the Gym is built", pad and tostring(pad.Locked) or "no pad")
	end
	-- HomeBuilder: the gate model carries the prompt
	local HB = mod("HomeBuilder")
	if not HB then
		local inst = K.moduleInstance("server/Services/HomeBuilder")
		local okR, res = pcall(function()
			return require(inst)
		end)
		HB = okR and type(res) == "table" and res or nil
	end
	local gate = HB and HB.BuildStationModel and HB.BuildStationModel("ArenaGate", 1)
	local gatePrompt = gate and gate:FindFirstChild("ArenaGatePrompt", true)
	T.check(gatePrompt ~= nil and gatePrompt:IsA("ProximityPrompt") and gatePrompt:GetAttribute("StationId") == "ArenaGate" and gatePrompt:GetAttribute("Teleport") == "Arena" and gatePrompt.ActionText ~= "", "teleport: HomeBuilder's Arena Gate carries ArenaGatePrompt (StationId / Teleport = \"Arena\")",
		gate and (gate:GetFullName() .. " " .. #promptsUnder(gate) .. " prompts, " .. #gate:GetDescendants() .. " descendants") or "no model")
	if not gatePrompt then
		if gate then
			gate:Destroy()
		end
		return
	end
	local players = K.freshPlayers(2, "Gate")
	local owner, other = players[1], players[2]
	advance(1)
	local r = K.root(owner)
	T.check(r ~= nil, "teleport: the owner has a character")
	if not r then
		K.removePlayers(players)
		return
	end
	-- park the gate next to the owner (a home far from everything) and claim it for them
	local spot = CFrame.new(1800, 300, 1800)
	local stand = Instance.new("Part")
	stand.Name = "GateTestFloor"
	stand.Anchored = true
	stand.Size = Vector3.new(40, 1, 40)
	stand.CFrame = spot * CFrame.new(0, -0.5, 0)
	stand.Parent = workspace
	gate.Parent = workspace
	pcall(function()
		gate:PivotTo(spot)
	end)
	gatePrompt:SetAttribute("OwnerUserId", owner.UserId)
	local at = promptWorldPos(gatePrompt)
	T.check(at ~= nil, "teleport: the prompt rides an attachment on the gate")
	local function standAt(player, pos)
		local char = player.Character
		if char then
			char:PivotTo(CFrame.new(pos))
		end
	end
	local arenaCFrames = {}
	for _, p in ipairs(partsOf(info.Model)) do
		arenaCFrames[p] = p.CFrame
	end
	local fired = {}
	local conn = AB.Teleported and AB.Teleported:Connect(function(player, where, source)
		fired[#fired + 1] = { player, where, source }
	end)
	local spawnPos = info.Spawn.Position

	-- another player triggers the gate: nothing
	standAt(other, at + Vector3.new(0, 0, -3))
	advance(0.2)
	Mock.Trigger(gatePrompt, other)
	advance(0.3)
	T.check(hdist(K.root(other).Position, spawnPos) > 50, "teleport: another player's trigger does nothing")
	-- the owner from far away: nothing
	standAt(owner, at + Vector3.new(0, 0, -60))
	advance(0.2)
	Mock.Trigger(gatePrompt, owner)
	advance(0.3)
	T.check(hdist(K.root(owner).Position, spawnPos) > 50, "teleport: refused from far away (the server checks the distance)")
	-- in a battle: refused with a toast
	advance(3)
	standAt(owner, at + Vector3.new(0, 0, -3))
	owner:SetAttribute("InBattle", "B1")
	local mark = K.logSize()
	advance(0.2)
	Mock.Trigger(gatePrompt, owner)
	advance(0.3)
	T.check(hdist(K.root(owner).Position, spawnPos) > 50 and K.notified(owner, "battle", nil, mark), "teleport: refused in a battle, with a side toast")
	owner:SetAttribute("InBattle", nil)
	-- in an obby match: refused
	advance(3)
	owner:SetAttribute("InMatch", true)
	Mock.Trigger(gatePrompt, owner)
	advance(0.3)
	T.check(hdist(K.root(owner).Position, spawnPos) > 50, "teleport: refused during an obby match")
	owner:SetAttribute("InMatch", false)
	-- the owner at the gate: lands on the arena's Spawn
	advance(3)
	standAt(owner, at + Vector3.new(0, 0, -3))
	advance(0.2)
	local before = #fired
	Mock.Trigger(gatePrompt, owner)
	advance(0.5)
	local pos = K.root(owner).Position
	T.check(hdist(pos, spawnPos) < 8 and abs(pos.Y - spawnPos.Y) < 6, "teleport: the owner lands at the arena's arrival point", fmt(hdist(pos, spawnPos), 1) .. " studs off")
	T.check(AB.InArena(pos) and surfaceBelow(pos, 12) ~= nil, "teleport: ...on the arena island, on solid ground")
	T.check(#fired == before + 1 and fired[#fired][1] == owner and fired[#fired][2] == "Arena", "teleport: ArenaBuilder.Teleported fires (player, \"Arena\", source)")
	-- cooldown: back at the gate at once -> refused
	standAt(owner, at + Vector3.new(0, 0, -3))
	advance(0.1)
	Mock.Trigger(gatePrompt, owner)
	advance(0.2)
	T.check(hdist(K.root(owner).Position, spawnPos) > 50, "teleport: a second trigger inside the cooldown is refused")

	-- panel prompts in the arena never teleport or error on the server
	standAt(owner, info.Spawn.Position + Vector3.new(0, 0, 0))
	advance(3)
	local okAll = true
	for _, pr in ipairs(promptsUnder(info.Model)) do
		if pr:GetAttribute("OpenPanel") ~= nil then
			local okT = pcall(Mock.Trigger, pr, owner)
			if not okT then
				okAll = false
			end
		end
	end
	advance(0.5)
	T.check(okAll and hdist(K.root(owner).Position, spawnPos) < 12, "teleport: OpenPanel prompts (Arena / Ring) never teleport on the server")
	-- the Replication rule: no arena part moved
	local moved = 0
	for p, cf in pairs(arenaCFrames) do
		if p.Parent and p.CFrame ~= cf then
			moved = moved + 1
		end
	end
	T.check(moved == 0, "teleport: the server never moves a part of the arena (Replication rule)", moved .. " moved")

	if conn then
		conn:Disconnect()
	end
	gate:Destroy()
	stand:Destroy()
	K.removePlayers(players)
	K.flushErrors("p3arena_teleport")
	K.flushWarnings("p3arena_teleport")
end)

----------------------------------------------------------------------------------------------------
-- scenario: the Phase 5 art pass (arenaart, 6.4) on the island and the Champion Ring pocket
----------------------------------------------------------------------------------------------------
-- The look audit of one model (Phase 6 A1: back to the P4 look, 7aa0df2): every part SmoothPlastic (Neon / Glass /
-- ForceField for glow, glass and shimmer), blocky voxel shapes only (no Ball / Cylinder), a bright colourful palette
-- (the area-weighted saturation of the big opaque faces >= 0.2: no muted P5 greys); kept from 6.4: lights Brightness
-- <= 1.5, Range <= 16, no shadows, warm outside the gates (rule 7) and parts < 4 studs cast no shadow (rule 8); the
-- voxel clouds / the crowd are skipped by the exempt tag.
local function artAudit(root, label, WS)
	local exemptTag = (WS and WS.Tags and WS.Tags.Exempt) or "NC_StyleExempt"
	local P4MAT = { [Enum.Material.SmoothPlastic] = true, [Enum.Material.Neon] = true, [Enum.Material.Glass] = true, [Enum.Material.ForceField] = true }
	local function exempt(p)
		local cur = p
		while cur and cur ~= game do
			if CollectionService:HasTag(cur, exemptTag) then
				return true
			end
			cur = cur.Parent
		end
		return false
	end
	local function hsv(c)
		local hi, lo = max(c.R, c.G, c.B), min(c.R, c.G, c.B)
		return hi > 0 and (hi - lo) / hi or 0, hi
	end
	local tMat = T.tally(label .. ": every part is SmoothPlastic / Neon / Glass / ForceField (P6 A1: the P4 look, no realistic textures)")
	local tShape = T.tally(label .. ": blocky voxel shapes only (no Ball / Cylinder parts; P6 A1)")
	local tShadow = T.tally(label .. ": parts < 4 studs cast no shadow (rule 8)")
	local n, skipped = 0, 0
	local satArea, area = 0, 0
	for _, p in ipairs(partsOf(root)) do
		local s = p.Size
		local dims = { s.X, s.Y, s.Z }
		table.sort(dims)
		if dims[3] < 4 then
			tShadow:case(p.CastShadow == false, p:GetFullName())
		end
		if p.Transparency < 0.99 then
			if exempt(p) then
				skipped = skipped + 1
			else
				n = n + 1
				tMat:case(P4MAT[p.Material] == true, p:GetFullName() .. " " .. tostring(p.Material))
				tShape:case(not p:IsA("Part") or p.Shape == Enum.PartType.Block, p:GetFullName() .. " " .. tostring(p:IsA("Part") and p.Shape))
				if dims[2] * dims[3] > 16 and p.Transparency < 0.3 and p.Material ~= Enum.Material.Neon then
					local sat = hsv(p.Color)
					satArea = satArea + sat * dims[2] * dims[3]
					area = area + dims[2] * dims[3]
				end
			end
		end
	end
	tMat:report()
	tShape:report()
	tShadow:report()
	local wsat = area > 0 and satArea / area or 0
	T.check(wsat >= 0.2, label .. ": a bright, colourful P4 palette (area-weighted saturation of the big faces >= 0.2)", fmt(wsat, 3))
	local lights = T.tally(label .. ": every light is a lantern light: Brightness <= 1.5, Range <= 16, no shadows; warm outside the gates (rule 7)")
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			-- a gate's own glow (WorldStyle.BuildGate: the GateId model) follows the gate kit, not the lantern rule
			local inGate = false
			local cur = d.Parent
			while cur and cur ~= root.Parent do
				if cur:GetAttribute("GateId") ~= nil then
					inGate = true
				end
				cur = cur.Parent
			end
			local c = d.Color
			local warm = c.R >= c.G and c.G >= c.B and c.R > 0.9
			lights:case(inGate or (d.Brightness <= 1.5 and d.Range <= 16 and not d.Shadows and warm), d:GetFullName())
		end
	end
	lights:report()
	return n, skipped
end

S.p3arena_art = guarded("p3arena_art", function()
	if not K.needBoot() then
		return
	end
	local AB = arenaBuilder()
	local info = AB and AB.GetInfo and AB.GetInfo()
	local model = workspace:FindFirstChild("BattleArena")
	if not T.check(type(info) == "table" and model ~= nil, "arena art: the Battle Arena is built") then
		return
	end
	local wsInst = K.moduleInstance("shared/WorldStyle")
	local okW, WS = pcall(require, wsInst)
	WS = okW and type(WS) == "table" and WS or nil
	T.check(WS ~= nil, "arena art: shared/WorldStyle loads (the art kit)")
	local exemptTag = (WS and WS.Tags and WS.Tags.Exempt) or "NC_StyleExempt"
	local detailTag = (WS and WS.Tags and WS.Tags.Detail) or "NC_Detail"

	-- budget (10.3) and the safety net: the builder's own choices already follow the rules
	local parts = partsOf(model)
	T.check(#parts <= 2800, "arena art: the island + bridge stay <= 2800 parts (10.3)", #parts .. " parts")
	T.check(#parts >= 1800, "arena art: still detailed (>= 1800 parts)", #parts .. " parts")
	T.eq(model:GetAttribute("ArtFixes"), 0, "arena art: the P6 A1 safety net had nothing to fix (every piece is built in the P4 look)")

	-- the P4 look, rules 7, 8 over the whole island (the clouds are exempt by tag)
	local audited, skipped = artAudit(model, "arena art", WS)
	T.info("*arena art: " .. audited .. " parts audited, " .. skipped .. " exempt (voxel clouds)")
	local cloud = model:FindFirstChild("IslandCloud")
	T.check(cloud ~= nil and CollectionService:HasTag(cloud, exemptTag), "arena art: the island's voxel cloud is tagged " .. exemptTag)
	-- the clouds are shaded like P4 (white / light blue: blue >= green on every part, light tops ~244,247,252, the
	-- undersides down to ~170,190,228, nothing pure white)
	local light, dark, cool, white = false, false, 0, 0
	for _, p in ipairs(partsOf(cloud)) do
		local c = p.Color
		if c.R >= 0.94 then
			light = true
		end
		if c.R <= 0.8 then
			dark = true
		end
		if c.B + 1e-3 < c.G then
			cool = cool + 1
		end
		if c.R >= 0.99 and c.G >= 0.99 and c.B >= 0.99 then
			white = white + 1
		end
	end
	T.check(light and dark and cool == 0 and white == 0, "arena art: the cloud is shaded like P4 (white tops, light-blue undersides, no pure white)",
		tostring(light) .. "/" .. tostring(dark) .. ", " .. cool .. " not lavender, " .. white .. " white")

	-- the P4 palette on the main surfaces (P6 A1): a lime lawn, light cream stone walls, golden sand, gold trim
	local pal = { Lawn = 0, Wall = 0, Sand = 0, Gold = 0 }
	for _, p in ipairs(parts) do
		local _, sat, val = p.Color:ToHSV()
		if p.Name == "Lawn" and p.Color.G > 0.6 and sat >= 0.4 then
			pal.Lawn = pal.Lawn + 1
		elseif p.Name == "Wall" and val >= 0.75 and sat <= 0.2 then
			pal.Wall = pal.Wall + 1
		elseif (p.Name == "Sand" or p.Name == "SandDrift" or p.Name == "RingFloor") and p.Color.R >= 0.82 and sat >= 0.2 then
			pal.Sand = pal.Sand + 1
		elseif p.Color.R > 0.9 and p.Color.G > 0.7 and p.Color.B < 0.45 then
			pal.Gold = pal.Gold + 1
		end
	end
	T.check(pal.Lawn > 0 and pal.Wall > 0 and pal.Sand > 0 and pal.Gold > 0, "arena art: the P4 palette (lime lawn, light cream stone walls, golden sand, gold trim)",
		string.format("lawn %d, walls %d, sand %d, gold %d", pal.Lawn, pal.Wall, pal.Sand, pal.Gold))
	-- the colosseum: walls, marble-white trims and seats in the element colours
	local col = model:FindFirstChild("Colosseum")
	local wall, seat, marble = 0, 0, 0
	for _, p in ipairs(partsOf(col)) do
		if p.Name == "Wall" then
			wall = wall + 1
		elseif p.Name == "Seat" and select(2, p.Color:ToHSV()) >= 0.3 then
			seat = seat + 1
		elseif (p.Name == "Cornice" or p.Name == "Pilaster") and select(3, p.Color:ToHSV()) >= 0.85 then
			marble = marble + 1
		end
	end
	T.check(wall >= 16 and seat >= 16 and marble >= 32, "arena art: walls, white trims and element-coloured seats on the colosseum", wall .. " walls, " .. marble .. " marble, " .. seat .. " seats")

	-- P6 A1: free-standing posts / columns are square voxel posts (no Cylinder parts)
	local postNames = { Post = true, Pillar = true, ArchPillar = true, TorchPole = true, Pole = true, LanternPost = true, Trunk = true }
	local round = T.tally("arena art: every free-standing post / column >= 4 studs tall is a square voxel post (P6 A1)")
	for _, p in ipairs(parts) do
		if postNames[p.Name] and p:IsA("Part") and max(p.Size.X, p.Size.Y, p.Size.Z) >= 4 and not p:FindFirstAncestor("Portal_Return") then
			round:case(p.Shape == Enum.PartType.Block, p:GetFullName())
		end
	end
	round:report()

	-- rule 3: kerbs + lips along the island's edge (open where the bridge lands)
	local kerbs = model:FindFirstChild("Kerbs", true)
	local nKerb, nLip, kerbLen = 0, 0, 0
	for _, p in ipairs(partsOf(kerbs)) do
		if p.Name == "Kerb" then
			nKerb = nKerb + 1
			kerbLen = kerbLen + max(p.Size.X, p.Size.Z)
			T.check(abs(p.Size.Y - 0.4) < 0.01, "arena art: a kerb is 0.4 tall", tostring(p.Size.Y))
		elseif p.Name == "KerbLip" then
			nLip = nLip + 1
		end
	end
	T.check(nKerb >= 20 and nLip == nKerb and kerbLen > 900, "arena art: a kerb + lip runs round the island's edge (rule 3)", nKerb .. " kerbs, " .. nLip .. " lips, " .. fmt(kerbLen, 0) .. " studs")
	if info.Link == "Bridge" then
		local A = info.Center
		local blocked = false
		for _, p in ipairs(partsOf(kerbs)) do
			local rel = A:PointToObjectSpace(p.Position)
			if p.Name == "Kerb" and abs(rel.X) < 6 and rel.Z < -195 then
				blocked = true
			end
		end
		T.check(not blocked, "arena art: no kerb across the bridge's landing")
	end

	-- rule 5: the avenue's tiles are 4..6 studs, alternate +-0.05 in height and are jittered (+-6 RGB)
	local A = info.Center
	local tops, colours, sizesOk, nTiles = {}, {}, true, 0
	for _, p in ipairs(partsOf(model:FindFirstChild("Forum"))) do
		if p.Name == "AvenueTile" then
			nTiles = nTiles + 1
			local rel = A:PointToObjectSpace(p.Position + Vector3.new(0, p.Size.Y / 2, 0))
			tops[string.format("%.2f", rel.Y)] = true
			colours[string.format("%d,%d,%d", p.Color.R * 255 + 0.5, p.Color.G * 255 + 0.5, p.Color.B * 255 + 0.5)] = true
			if p.Size.X < 4 - 1e-3 or p.Size.X > 6 + 1e-3 or p.Size.Z < 4 - 1e-3 or p.Size.Z > 6 + 1e-3 then
				sizesOk = false
			end
		end
	end
	local nTops, nCols = 0, 0
	local lo, hi = huge, -huge
	for k in pairs(tops) do
		nTops = nTops + 1
		lo, hi = min(lo, tonumber(k)), max(hi, tonumber(k))
	end
	for _ in pairs(colours) do
		nCols = nCols + 1
	end
	T.check(nTiles >= 40 and sizesOk, "arena art: the avenue is paved with 4..6-stud tiles (rule 5)", nTiles .. " tiles")
	T.check(nTops == 2 and abs((hi - lo) - 0.05) < 0.011, "arena art: the tiles alternate by 0.05 in height (rule 5)", nTops .. " levels, " .. fmt(hi - lo, 3))
	T.check(nCols >= 6, "arena art: the tiles are jittered (never one flat colour)", nCols .. " colours")
	-- the lawn is mown in stripes of two shades
	local lawnCols = {}
	for _, p in ipairs(partsOf(model:FindFirstChild("Lawn", true))) do
		if p.Name == "Lawn" then
			lawnCols[string.format("%.2f", p.Color.G)] = true
		end
	end
	local nLawn = 0
	for _ in pairs(lawnCols) do
		nLawn = nLawn + 1
	end
	T.check(nLawn >= 2, "arena art: the forum lawn has mown stripes (2+ green shades)", nLawn .. " shades")

	-- rule 6: a detail every ~12 studs along the avenue (torches, hedge boxes, banners, lanterns: NC_Detail)
	local details = {}
	for _, d in ipairs(CollectionService:GetTagged(detailTag)) do
		if d:IsDescendantOf(model) and (d:IsA("Model") or d:IsA("BasePart")) then
			local ok, pivot = pcall(function()
				return d:GetPivot().Position
			end)
			if ok then
				details[#details + 1] = A:PointToObjectSpace(pivot)
			end
		end
	end
	T.check(#details >= 30, "arena art: pure decor is tagged " .. detailTag .. " (the Low setting hides it)", #details .. " tagged")
	local gaps = {}
	for z = -200, -152, 12 do
		local found = false
		for _, rel in ipairs(details) do
			if rel.Z >= z and rel.Z < z + 12 and abs(rel.X) < 22 then
				found = true
			end
		end
		if not found then
			gaps[#gaps + 1] = tostring(z)
		end
	end
	T.check(#gaps == 0, "arena art: a detail every ~12 studs along the avenue (rule 6)", "gaps at z " .. table.concat(gaps, ", "))

	-- the Champion Ring pocket follows the same rules (its cloud and its cheering crowd are exempt)
	local rp = AB.BuildPocket(63, "Ring")
	if T.check(type(rp) == "table" and rp.Model, "arena art: a Champion Ring pocket builds") then
		local n = #partsOf(rp.Model)
		T.check(n <= 250, "arena art: the ring pocket stays <= 250 parts", n .. " parts")
		T.eq(rp.Model:GetAttribute("ArtFixes"), 0, "arena art: the pocket needed no safety-net fixes")
		artAudit(rp.Model, "ring pocket art", WS)
		local crowd = rp.Model:FindFirstChild("CrowdPuffs", true)
		T.check(crowd ~= nil and CollectionService:HasTag(crowd, exemptTag), "ring pocket art: the cheering cloud puffs are characters (tagged exempt)")
		local pk = 0
		for _, p in ipairs(partsOf(rp.Model)) do
			if p.Name == "Kerb" then
				pk = pk + 1
			end
		end
		T.check(pk >= 16, "ring pocket art: a kerb + lip round its stone deck (rule 3)", pk .. " kerbs")
		AB.FreePocket(rp)
	end
	K.flushErrors("p3arena_art")
	K.flushWarnings("p3arena_art")
end)


-- [owner: art-arenadungeon] begin -- Phase 6 W2: the Blender keys of the arena (blender/catalog/arenadungeon.json) and
-- ArenaBuilder's Tag calls (ArenaBuilder._Mesh): every tagged piece has its arena_<piece> key and every arena key is
-- tagged somewhere, each LayoutSig still matches the live Part build (else rebuild: blender/build_all.py --class
-- arenadungeon), targets never nest, every visible Neon part of a target stays (keep), nothing is tagged without
-- uploaded ids, a tag with ids carries the offset / look / keep, a stale layout is refused, the arena's mesh budget.
local function meshKeysWith(prefix)
	local inst = K.moduleInstance("shared/MeshLibrary")
	local dir = inst and inst.Parent and inst.Parent:FindFirstChild("MeshManifests")
	local out = {}
	for _, m in ipairs(dir and dir:GetChildren() or {}) do
		if m:IsA("ModuleScript") and string.sub(m.Name, 1, #prefix) == prefix then
			out[#out + 1] = m.Name
		end
	end
	table.sort(out)
	return out
end

S.p3arena_mesh = guarded("p3arena_mesh", function()
	if not K.needBoot() then
		return
	end
	local AB = arenaBuilder()
	local mlInst = K.moduleInstance("shared/MeshLibrary")
	local okML, ML = pcall(require, mlInst)
	local Mesh = AB and AB._Mesh
	local info = AB and AB.GetInfo and AB.GetInfo()
	if not T.check(type(Mesh) == "table" and type(Mesh.Placed) == "table" and okML and type(ML) == "table" and info and info.Model, "arena mesh: ArenaBuilder._Mesh, MeshLibrary and the built arena") then
		return
	end
	local rp = AB.BuildPocket(37)
	-- the recorded Tag calls (sorted: deterministic)
	local recs = {}
	for target, r in pairs(Mesh.Placed) do
		if target.Parent and (target:IsDescendantOf(info.Model) or (rp and target == rp.Model)) then
			recs[#recs + 1] = { Target = target, Key = r.Key, Origin = r.Origin, Look = r.Look, Keep = r.Keep, Scale = r.Scale, Name = target:GetFullName() }
		end
	end
	table.sort(recs, function(a, b)
		return a.Key .. a.Name < b.Key .. b.Name
	end)
	local set = {}
	for _, r in ipairs(recs) do
		set[r.Target] = true
	end
	-- 1. key coverage both ways
	local used = {}
	for _, r in ipairs(recs) do
		used[r.Key] = (used[r.Key] or 0) + 1
	end
	local missing, orphan = {}, {}
	for key in pairs(used) do
		if not ML.Manifest(key) then
			missing[#missing + 1] = key
		end
	end
	table.sort(missing)
	for _, key in ipairs(meshKeysWith("arena_")) do
		if not used[key] then
			orphan[#orphan + 1] = key
		end
	end
	T.check(#recs >= 70 and #missing == 0, "arena mesh: every tagged piece has its manifest (src/shared/MeshManifests/arena_*)", #recs .. " targets; missing " .. table.concat(missing, ", "))
	T.check(#orphan == 0, "arena mesh: every arena_* key is tagged by the build", table.concat(orphan, ", "))
	for _, key in ipairs({ "arena_island", "arena_forum", "arena_floor", "arena_seg_stand", "arena_seg_gate", "arena_seg_bossgate", "arena_pillar", "arena_ring_1", "arena_ring_2", "arena_board_event", "arena_board_leader", "arena_trophy", "arena_bridge", "arena_pocket", "arena_torch", "arena_lantern", "arena_tree" }) do
		T.check(used[key] ~= nil, "arena mesh: " .. key .. " is tagged", tostring(used[key]))
	end
	T.eq(used.arena_seg_stand, 12, "arena mesh: 12 stand segments share one key")
	T.eq(used.arena_pillar, 16, "arena mesh: 16 columns share one key")
	-- 2. layouts match, no nesting, glows kept
	local sig = T.tally("arena mesh: each target's Part build matches its key's LayoutSig (else rebuild: blender/build_all.py --class arenadungeon)")
	local nest = T.tally("arena mesh: targets never nest (one dress per subtree)")
	local glow = T.tally("arena mesh: every visible Neon part of a target is in its keep list (it stays a glow part)")
	for _, r in ipairs(recs) do
		local man = ML.Manifest(r.Key)
		local att = man and man.Attachments and man.Attachments.LayoutSig
		if att then
			local pos = att.Pos or att.pos
			local n, a, b = Mesh.Signature(r.Target, r.Origin, r.Scale, r.Keep)
			local tol = 0.05 + n * 1e-4
			sig:case(n == pos[1] and abs(a - pos[2]) <= tol and abs(b - pos[3]) <= tol, r.Name, n .. " / " .. tostring(pos[1]) .. " parts, " .. fmt(a, 3) .. " vs " .. fmt(pos[2], 3))
		end
		local p = r.Target.Parent
		local nested = false
		while p do
			if set[p] then
				nested = true
			end
			p = p.Parent
		end
		nest:case(not nested, r.Name)
		local keep = {}
		for _, k in ipairs(r.Keep or {}) do
			keep[k] = true
		end
		local bad = nil
		for _, d in ipairs(r.Target:GetDescendants()) do
			if d:IsA("BasePart") and d.Material == Enum.Material.Neon and d.Transparency < 0.99 and not keep[d.Name] then
				bad = d.Name
			end
		end
		glow:case(bad == nil, r.Name, bad)
	end
	sig:report()
	nest:report()
	glow:report()
	-- 3. tagged exactly when the key has a shipped id (Status ~= "missing"; ArenaBuilder's rule with the LayoutSig
	-- checked in 2.): empty MeshIds = nothing tagged, the Part build is unchanged
	local quiet = T.tally("arena mesh: a target is tagged exactly when its key has a shipped id (empty MeshIds: nothing tagged, the Part build is unchanged)")
	for _, r in ipairs(recs) do
		local okStatus, st = pcall(ML.Status, r.Key)
		local shipped = okStatus and st ~= "missing"
		local key = r.Target:GetAttribute("ML_DressKey")
		quiet:case((key ~= nil) == shipped and (key == nil or key == r.Key), r.Name, tostring(key) .. " / shipped " .. tostring(shipped))
	end
	quiet:report()
	-- 4. the arena's meshes stay light: <= 300k triangles over every placement, <= 10k per MeshPart
	local tris, worst = 0, 0
	for _, r in ipairs(recs) do
		local man = ML.Manifest(r.Key)
		tris = tris + (tonumber(man and man.Raw and man.Raw.Tris) or 0)
		for _, part in ipairs(man and man.Raw and man.Raw.Parts or {}) do
			worst = max(worst, tonumber(part.Tris) or 0)
		end
	end
	T.check(tris > 0 and tris <= 300000 and worst <= 10000, "arena mesh: the whole arena <= 300k triangles, every MeshPart <= 10k", tris .. " tris, worst part " .. worst)
	-- 5. with ids: the tag carries the offset, the look and the keep list; a stale layout is refused
	local ids, idn = {}, 0
	for _, key in ipairs(meshKeysWith("arena_")) do
		idn = idn + 1
		ids[key] = 200000 + idn
	end
	-- W2.5 isolation: Start() with ids creates ReplicatedStorage.MeshLibrary; remove it again at the end so later
	-- scenarios (p6pets_default: MeshLibrary.Active() is false) see the empty-ids game
	local hadMLFolder = game:GetService("ReplicatedStorage"):FindFirstChild("MeshLibrary") ~= nil
	ML._Reset()
	ML._Configure({ Ids = ids })
	pcall(ML.Start)
	local tagged = T.tally("arena mesh: with ids every target is tagged (ML_DressKey = its key, the offset puts the mesh on the Tag origin)")
	local function untag(target)
		CollectionService:RemoveTag(target, "ML_Dress")
		for _, att in ipairs({ "ML_DressKey", "ML_Offset", "ML_Keep", "ML_Primary", "ML_Secondary", "ML_Scale" }) do
			target:SetAttribute(att, nil)
		end
	end
	local seen = {}
	for _, r in ipairs(recs) do
		if not seen[r.Key] then
			seen[r.Key] = r
			local ok = Mesh.tag(r.Target, r.Key, r.Origin, r.Look, r.Keep, r.Scale)
			local offOk = false
			local off = r.Target:GetAttribute("ML_Offset")
			if type(off) == "string" then
				local v = {}
				for x in string.gmatch(off, "[^,%s]+") do
					v[#v + 1] = tonumber(x)
				end
				if #v == 12 then
					local cf = r.Target:GetPivot() * CFrame.new(unpack(v))
					offOk = (cf.Position - r.Origin.Position).Magnitude < 0.02
				end
			end
			tagged:case(ok and r.Target:GetAttribute("ML_DressKey") == r.Key and CollectionService:HasTag(r.Target, "ML_Dress") and offOk, r.Key, tostring(off))
		end
	end
	tagged:report()
	local seg = seen.arena_seg_stand
	if seg then
		local seat = Mesh.colorOf(seg.Target, "Seat")
		T.check(seat ~= nil and seg.Target:GetAttribute("ML_Primary") == seat and seg.Target:GetAttribute("ML_Secondary") == Mesh.colorOf(seg.Target, "Banner"), "arena mesh: a stand segment's seats / banner tint = its element colours (ML_Primary / ML_Secondary)")
	end
	local pil = seen.arena_pillar
	T.check(pil ~= nil and string.find(pil.Target:GetAttribute("ML_Keep") or "", "Flame", 1, true) ~= nil, "arena mesh: a column keeps its Neon flame visible (ML_Keep)")
	-- a stale layout (one part moved) is never tagged
	if pil then
		local clone = pil.Target:Clone()
		untag(clone)
		local moved = clone:FindFirstChild("Capital", true)
		if moved then
			moved.CFrame = moved.CFrame * CFrame.new(0, 2, 0)
		end
		T.check(Mesh.tag(clone, "arena_pillar", pil.Origin, nil, pil.Keep) == false and clone:GetAttribute("ML_DressKey") == nil, "arena mesh: a Part build that no longer matches its key is never tagged")
		clone:Destroy()
	end
	for _, r in pairs(seen) do
		untag(r.Target)
	end
	ML._Reset()
	local mlFolder = game:GetService("ReplicatedStorage"):FindFirstChild("MeshLibrary")
	if mlFolder and not hadMLFolder then
		mlFolder:Destroy()
	end
	if rp then
		AB.FreePocket(rp)
	end
	K.flushErrors("p3arena_mesh")
	K.flushWarnings("p3arena_mesh")
end)
-- [owner: art-arenadungeon] end

return S
