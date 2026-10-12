-- smoke_p3_arenaworld.lua: Phase 3 "arenaworld" (ARCHITECTURE_V3.md "Phase 3: Pet battles", "Phase 3 build contract":
-- ArenaBuilder + its "Interfaces between the Phase 3 modules" (ArenaInfo, BuildPocket / FreePocket, OpenPanel prompts),
-- ART DIRECTION, World text rule, Replication rule): server/Services/ArenaBuilder.lua, the Trial Portal on the plaza,
-- the arena link and the home Arena Gate (HomeBuilder's ArenaGatePrompt, TycoonCatalog without ComingSoon). Server world
-- only (listed in server_files of tools/smoke.py):
--   p3arena_world     (booted) the API; workspace.BattleArena is ArenaInfo.Model and the info has the contract shape
--                     (Center, Floor {CFrame, Size}, Rings {CFrame, Size, Pads}, Spawn, ReturnCFrame, TrialPortal);
--                     the part budget (<= 2500), anchored, no scripts / welds / decals, no big neon; battle zones
--                     tagged NC_BattleZone with Mode / Size (= BattleCatalog.Zones) for the boss floor and 2+ duel
--                     rings, ZoneAt / InArena; the battle squares fit the floors at ANY rotation (solid floor at the
--                     floor height under every corner, nothing collidable standing in them at walking height); duel
--                     pads carry a "Duel" prompt with OpenPanel = "Arena"; Portal_Trials on the plaza near the
--                     difficulty portals with OpenPanel = "Trials"; the arena never touches the lobby (no lobby part,
--                     home plot, the Storm Altar or a portal inside its outline) and stays well below the sky dragon;
--                     the link (Bridge: walkable without gaps or obstacles from the street to the forum; Portal: both
--                     portal prompts); readable world text (SurfaceGuis 40-60 px per stud with letters >= 0.6 stud,
--                     pixel-sized BillboardGuis >= 18 px with LightInfluence 0 and a sane MaxDistance, Theme fonts)
--   p3arena_boards    (booted) ApplyArenaState draws the event board (next boss + a countdown that ticks down, the
--                     live raid with HP and fighters, Double Rewards) and the trophy leaderboard (10 rows, long names
--                     cut, empty rows hidden); junk states never error; without EventService the boards fill
--                     themselves in (schedule + the server's trophies)
--   p3arena_pockets   (booted) BuildPocket(index): contract shape, Size = BattleCatalog.Zones.Trial, <= 250 parts, far
--                     out in the sky (away from the lobby, the obby match slots and each other), the trial square
--                     fits its (axis-aligned) floor, a Trial zone; the same index returns the same pocket; FreePocket removes
--                     it (and its zone); junk indices / zones never error
--   p3arena_teleport  (booted) the home Arena Gate: TycoonCatalog has no ComingSoon on ArenaGate (its pad opens with the
--                     Gym), HomeBuilder's gate model carries ArenaGatePrompt (StationId / Teleport = "Arena"); the
--                     owner standing at the gate lands on the arena's Spawn (on solid ground) and the server fires
--                     ArenaBuilder.Teleported; refused for another player, from far away, in a match, in a battle
--                     (with a side toast), and during the cooldown; Trial / duel / board prompts never teleport or
--                     error on the server; the server never moves a part of the arena (Replication rule)
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
	local defaults = { Raid = 96, Duel = 44, Trial = 56 }
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
	T.check(typeof(info.TrialPortal) == "Instance" and info.TrialPortal:IsA("BasePart"), "arena: ArenaInfo.TrialPortal is a BasePart")
	local rx, rz = zoneSize("Raid")
	local dx, dz = zoneSize("Duel")
	if type(info.Floor) == "table" and typeof(info.Floor.Size) == "Vector3" then
		T.check(abs(info.Floor.Size.X - rx) < 0.01 and abs(info.Floor.Size.Z - rz) < 0.01, "arena: the boss floor's Size is BattleCatalog.Zones.Raid", tostring(info.Floor.Size))
		T.check(abs(info.Floor.CFrame.UpVector.Y - 1) < 1e-3, "arena: the floor CFrame is level (the snapshot frame is x / z on it)")
	end

	-- budget and hygiene
	local parts = partsOf(model)
	T.check(#parts <= 2500, "arena: the Battle Arena (island, bridge, Trial Portal) stays <= 2500 parts", #parts .. " parts")
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
	local promptOk = T.tally("arena: every prompt has an action, a range <= 14 and (when it opens a window) OpenPanel Arena / Trials")
	for _, pr in ipairs(prompts) do
		local panel = pr:GetAttribute("OpenPanel")
		promptOk:case(pr.ActionText ~= "" and pr.MaxActivationDistance <= 14 and (panel == nil or panel == "Arena" or panel == "Trials"), pr:GetFullName())
	end
	promptOk:report()

	-- the Trial Portal on the plaza, next to the difficulty portals
	local portal = model:FindFirstChild("Portal_Trials", true)
	T.check(portal ~= nil and portal:IsA("Model"), "trial portal: a Portal_Trials model exists")
	local Config = config()
	local origin = Config.Lobby.Origin
	if typeof(info.TrialPortal) == "Instance" then
		local tp = info.TrialPortal
		T.check(portal ~= nil and tp:IsDescendantOf(portal), "trial portal: ArenaInfo.TrialPortal belongs to Portal_Trials")
		local trialPrompt = nil
		for _, pr in ipairs(promptsUnder(portal or tp)) do
			if pr:GetAttribute("OpenPanel") == "Trials" then
				trialPrompt = pr
			end
		end
		T.check(trialPrompt ~= nil and trialPrompt.Enabled, "trial portal: its prompt carries OpenPanel = \"Trials\"")
		local r = hdist(tp.Position, origin)
		local ringR = Config.Lobby.PortalRingRadius or 88
		T.check(abs(r - ringR) <= 14, "trial portal: it stands on the plaza's portal ring", "r = " .. fmt(r, 1) .. " (ring " .. ringR .. ")")
		T.check(abs(tp.Position.Y - origin.Y) <= 3, "trial portal: at plaza height", "y = " .. fmt(tp.Position.Y, 1))
		local hit = surfaceBelow(tp.Position + Vector3.new(0, 1, 0), 8)
		T.check(hit ~= nil, "trial portal: its pad stands on solid ground")
		-- near the difficulty portals, never on top of one
		local lobby = workspace:FindFirstChild("NimbusLobby")
		local nearest = huge
		if lobby then
			for _, d in ipairs(lobby:GetDescendants()) do
				if d:IsA("Model") and d.Name:sub(1, 7) == "Portal_" then
					local ok, pivot = pcall(function()
						return d:GetPivot().Position
					end)
					if ok then
						nearest = min(nearest, hdist(pivot, tp.Position))
					end
				end
			end
		end
		T.check(nearest > 16 and nearest < 70, "trial portal: next to the difficulty portals (16..70 studs from the nearest)", fmt(nearest, 1) .. " studs")
		-- ReturnCFrame: on the plaza in front of the Trial Portal, on solid ground
		local ret = info.ReturnCFrame.Position
		T.check(hdist(ret, tp.Position) < 25 and hdist(ret, origin) < (Config.Lobby.PlazaRadius or 130), "trial portal: ReturnCFrame is on the plaza in front of the portal")
		T.check(surfaceBelow(ret, 10) ~= nil, "trial portal: ReturnCFrame stands on solid ground")
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

	-- the link
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
		T.check(names.ArenaPortalPrompt and names.ArenaReturnPrompt, "arena link: an Arena Portal on the plaza and a Return Portal on the forum")
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
	-- EventService draws its next raid (NEXT: BOSS RAID, the boss, a countdown); without it the board shows the schedule
	T.check(idle:find("NEXT: BOSS RAID", 1, true) ~= nil or idle:find("Every %d+ minutes") ~= nil or idle:find("BOSS RAIDS") ~= nil,
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
	local ok = AB.ApplyArenaState({ Next = { Kind = "BossRaid", BossId = bossId, StartsIn = 120 }, Leaderboard = list })
	T.check(ok == true, "boards: ApplyArenaState accepts a state")
	local text = visibleText(board)
	T.check(text:find("2:00", 1, true) ~= nil, "boards: the countdown shows 2:00", text)
	if bossName then
		T.check(text:find(bossName, 1, true) ~= nil, "boards: the next boss is named (" .. bossName .. ")", text)
	end
	advance(5.2)
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
	local tx, tz = zoneSize("Trial")
	local p1 = AB.BuildPocket(1)
	T.check(type(p1) == "table" and typeof(p1.Model) == "Instance" and typeof(p1.CFrame) == "CFrame" and typeof(p1.Size) == "Vector3" and typeof(p1.Spawn) == "CFrame", "pockets: BuildPocket(1) -> { Model, CFrame, Size, Spawn }")
	if type(p1) ~= "table" or typeof(p1.Model) ~= "Instance" then
		return
	end
	T.check(p1.Model:IsDescendantOf(workspace), "pockets: the pocket is in the workspace")
	T.check(abs(p1.Size.X - tx) < 0.01 and abs(p1.Size.Z - tz) < 0.01, "pockets: Size is BattleCatalog.Zones.Trial", tostring(p1.Size))
	local n = #partsOf(p1.Model)
	T.check(n <= 250 and n >= 100, "pockets: a detailed pocket within 250 parts", n .. " parts")
	T.check(AB.BuildPocket(1) == p1, "pockets: building an existing index returns the same pocket")
	local origin = Config.Lobby.Origin
	T.check((p1.CFrame.Position - origin).Magnitude > 1500, "pockets: far out in the sky (> 1500 studs from the lobby)", fmt((p1.CFrame.Position - origin).Magnitude, 0))
	local arenaOrigin = Config.Match and Config.Match.ArenaOrigin or Vector3.new(4000, 800, 0)
	T.check((p1.CFrame.Position - arenaOrigin).Magnitude > 1500, "pockets: far from the obby match slots")
	T.check(abs(p1.CFrame.UpVector.Y - 1) < 1e-3, "pockets: the floor CFrame is level")
	local z = AB.ZoneAt(p1.CFrame.Position + Vector3.new(0, 2, 0))
	T.check(z ~= nil and z:GetAttribute("Mode") == "Trial" and z:IsDescendantOf(p1.Model), "pockets: a Trial zone (NC_BattleZone) covers the floor")
	T.check(z ~= nil and CollectionService:HasTag(z, "NC_BattleZone"), "pockets: the zone is tagged NC_BattleZone")
	squareFits("pocket 1", p1.CFrame, tx, tz, false)
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
	for i = 1, 10 do
		AB.FreePocket(i)
	end
	local left = 0
	for _, t in ipairs(CollectionService:GetTagged("NC_BattleZone")) do
		if t:GetAttribute("Mode") == "Trial" and t:IsDescendantOf(workspace) then
			left = left + 1
		end
	end
	T.check(left == 0, "pockets: freed pockets leave no Trial zone behind", left .. " left")
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
	T.check(okAll and hdist(K.root(owner).Position, spawnPos) < 12, "teleport: OpenPanel prompts (Trials / Arena) never teleport on the server")
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

return S
