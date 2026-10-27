-- smoke_p3_visual.lua: the Phase 3 visual pass (ARCHITECTURE_V3.md ART DIRECTION, Readability + World text rules,
-- "Phase 3: Pet battles"). Loaded by tools/smoke.py in BOTH worlds; ARGS.context picks the half:
--   p3visual_arena    (server, booted) the arena floors are crafted, not one flat colour: raked sand drifts on the boss
--                     floor (flat slabs just over the sand, inside the gold line, clear of the element wheel), framed
--                     element marks, Phase 5 (6.4): a mown lawn, jittered avenue tiles, a promenade and the colosseum's
--                     apron; sand drifts on every duel ring (under its painted circle); the arena stays <= 2800 parts
--                     and a pocket <= 250; the gate and arch sign titles fit their panels (World text rule sizes kept); the
--                     event board draws the live boss HP bar (and hides it without a raid); Phase 5: Portal_Ring is a
--                     WorldStyle gate in the Gate Court (NimbusLobby.Gates, <= 120 parts, gold crowns + violet gems on
--                     its pedestals), no Trial Portal anywhere; the Champion Ring pocket (<= 250) has a two-tone floor,
--                     a Marble rim with a gold Neon inlay, four violet crown gems and a cheering crowd of cloud puffs
--                     facing the ring
--   p3visual_bosses   (server) every boss keeps its shading and its colour regions at High detail (the torso is not
--                     folded into one flat colour: several shades per region, the Frost Wyrm's belly and frost patch,
--                     the Hydra's belly, the Golem's ash), High <= 1000 parts and Low <= 760, Low keeps the accents
--   client_p3visual   (client) a boss telegraph has a crisp rim in its saturated colour (16 neon segments round a
--                     circle) besides the pale area, and the rim goes with it after the hit; Phase 4: every unit's
--                     PetCard reads on the sand (solid dark plate, stroked Lv, green HP for mine / a teammate's, red for
--                     enemies; the raid boss keeps its top-card bar; Phase 5: another player's helpers are not drawn);
--                     the Team picker tiles write pet names in white on their rarity-tinted tiles
--   client_p3visual_mobile (phone world; Phase 5) a battle unit's PetCard reads on a phone (Lv >= 14 px, stroked) and
--                     shows the fighter's lives pips (PetCard:SetLives)
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, floor, max, min, sqrt, huge = math.abs, math.floor, math.max, math.min, math.sqrt, math.huge

local function partsOf(root)
	local out = {}
	if not root then
		return out
	end
	if root:IsA("BasePart") then
		out[#out + 1] = root
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			out[#out + 1] = d
		end
	end
	return out
end

local function find(root, name, className)
	if not root then
		return nil
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name and (not className or d:IsA(className)) then
			return d
		end
	end
	return nil
end

local function colorKey(c)
	return floor(c.R * 255 + 0.5) .. "," .. floor(c.G * 255 + 0.5) .. "," .. floor(c.B * 255 + 0.5)
end

----------------------------------------------------------------------------------------------------
-- server world
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local K = _G.K
	local S = {}

	local function req(key)
		local inst = K and K.moduleInstance(key)
		if not inst then
			return nil
		end
		local ok, m = pcall(require, inst)
		return ok and type(m) == "table" and m or nil
	end

	S.p3visual_arena = guarded("p3visual_arena", function()
		if not K.needBoot() then
			return
		end
		local AB = req("server/Services/ArenaBuilder")
		local info = AB and AB.GetInfo and AB.GetInfo()
		local model = workspace:FindFirstChild("BattleArena")
		if not T.check(type(info) == "table" and model ~= nil, "visual arena: the Battle Arena is built (ArenaBuilder.GetInfo)") then
			return
		end
		local all = partsOf(model)
		T.check(#all <= 2800, "visual arena: the detailed arena stays within its 2800-part budget (Phase 5 10.3)", #all .. " parts")

		-- the boss floor: sand drifts (flat, just over the sand, inside the gold line, not on the wheel)
		local floorTop = info.Floor.CFrame.Position.Y
		local centre = info.Floor.CFrame.Position
		local drift = find(model, "SandDrift")
		local slabs = partsOf(drift)
		local colours, bad = {}, {}
		for _, p in ipairs(slabs) do
			colours[colorKey(p.Color)] = true
			local top = p.Position.Y + p.Size.Y / 2
			local d = sqrt((p.Position.X - centre.X) ^ 2 + (p.Position.Z - centre.Z) ^ 2)
			if top > floorTop + 0.01 or top < floorTop - 0.25 or p.Size.Y > 0.5 then
				bad[#bad + 1] = "height " .. string.format("%.2f", top - floorTop)
			elseif d + max(p.Size.X, p.Size.Z) / 2 > 72 then
				bad[#bad + 1] = "beyond the gold line"
			elseif not p.CanCollide or not p.Anchored then
				bad[#bad + 1] = "not solid"
			end
		end
		local nColours = 0
		for _ in pairs(colours) do
			nColours = nColours + 1
		end
		T.check(#slabs >= 8 and nColours >= 2, "visual arena: the boss floor has raked sand drifts in two shades", #slabs .. " slabs, " .. nColours .. " colours")
		T.check(#bad == 0, "visual arena: every drift is a flat solid slab just under the floor surface, inside the gold line", table.concat(bad, "; "))
		local centreHits = 0
		for _, p in ipairs(slabs) do
			local d = sqrt((p.Position.X - centre.X) ^ 2 + (p.Position.Z - centre.Z) ^ 2)
			if d < 15.2 and p.Size.X <= 8 and p.Size.Z <= 8 then
				centreHits = centreHits + 1
			end
		end
		T.check(centreHits == 0, "visual arena: no drift covers the element wheel in the middle")
		local frames, marks = 0, 0
		for _, p in ipairs(partsOf(find(model, "ArenaFloor"))) do
			if p.Name == "ElementFrame" then
				frames = frames + 1
			elseif p.Name == "ElementMark" then
				marks = marks + 1
			end
		end
		T.check(frames == 8 and marks == 8, "visual arena: eight element marks, each in a gold frame", frames .. " frames, " .. marks .. " marks")

		-- the forum (Phase 5 art pass): a mown lawn in two shades, the avenue's jittered tiles, Cobblestone aprons and a
		-- promenade (never one flat colour)
		local forum = find(model, "Forum")
		local keys, shades = {}, {}
		for _, p in ipairs(partsOf(forum)) do
			keys[p.Name] = (keys[p.Name] or 0) + 1
			if p.Name == "Lawn" or p.Name == "AvenueTile" or p.Name == "Promenade" then
				shades[p.Name .. colorKey(p.Color)] = true
			end
		end
		local nShades = 0
		for _ in pairs(shades) do
			nShades = nShades + 1
		end
		T.check((keys.Lawn or 0) > 10 and (keys.AvenueTile or 0) > 10 and (keys.Promenade or 0) > 10 and (keys.Apron or 0) == 32 and nShades >= 10,
			"visual arena: the forum is crafted (mown lawn, jittered avenue tiles, promenade, the colosseum's apron), never one flat colour",
			"Lawn " .. tostring(keys.Lawn) .. ", tiles " .. tostring(keys.AvenueTile) .. ", promenade " .. tostring(keys.Promenade) .. ", apron " .. tostring(keys.Apron) .. ", " .. nShades .. " shades")

		-- every duel ring: drifts under its painted circle
		for i, ring in ipairs(info.Rings or {}) do
			local rm = model:FindFirstChild("DuelRing_" .. i)
			local rd = partsOf(rm and rm:FindFirstChild("RingDrift"))
			local line = rm and find(rm, "RingLine")
			local lineTop = line and (line.Position.Y + line.Size.Y / 2) or huge
			local under = true
			for _, p in ipairs(rd) do
				if p.Position.Y + p.Size.Y / 2 > lineTop - 0.01 then
					under = false
				end
			end
			T.check(#rd >= 4 and under, "visual arena: duel ring " .. i .. " has sand drifts under its painted circle", #rd .. " slabs")
		end

		-- the sign titles fit their panels (an estimate at the bold font's ~0.62 em per letter)
		for _, spec in ipairs({ { "GateSign", 11 }, { "ArchSign", 12 } }) do
			local part = find(model, spec[1], "BasePart")
			local gui = part and part:FindFirstChildOfClass("SurfaceGui")
			local title = gui and find(gui, "Title")
			if part and title then
				local pps = gui.PixelsPerStud or 50
				local width = 0.92 * part.Size.X * pps
				local need = 0.62 * title.TextSize * #title.Text
				T.check(need <= width and title.TextSize / pps >= 1, "visual arena: the " .. spec[1] .. " title fits its panel and stays >= 1 stud tall",
					string.format("%s at %d px: ~%d of %d px", title.Text, title.TextSize, need, width))
			end
		end

		-- the event board shows the live boss's HP as a bar (in the Double Rewards pill's slot)
		if AB.ApplyArenaState then
			AB.ApplyArenaState({ Raid = { Active = true, BossId = "lava_golem", Hp = 61000, MaxHp = 90000, Players = 3, EndsIn = 200 }, Leaderboard = {} })
			local bar = find(model, "RaidHpBar")
			local fill = bar and bar:FindFirstChild("Fill")
			T.check(bar and bar.Visible and fill and abs(fill.Size.X.Scale - 61000 / 90000) < 0.01, "visual arena: the event board draws the raid boss's HP bar",
				fill and string.format("%.2f", fill.Size.X.Scale) or "no bar")
			AB.ApplyArenaState({ Next = { Kind = "BossRaid", BossId = "storm_titan", StartsIn = 600 }, Leaderboard = {} })
			T.check(bar and not bar.Visible, "visual arena: ...and hides it when no raid runs")
		end

		-- a pocket with no kind (Phase 5: the Ring pocket), within 250 parts
		local pocket = AB.BuildPocket and AB.BuildPocket(61)
		if T.check(type(pocket) == "table" and pocket.Model, "visual arena: a pocket builds (no kind = the Ring pocket)") then
			local n = #partsOf(pocket.Model)
			local dark = 0
			for _, p in ipairs(partsOf(find(pocket.Model, "PocketFloor"))) do
				if p.Name == "SandDark" then
					dark = dark + 1
				end
			end
			-- (Phase 5: the trial pocket's drifts went with the Trials; the pocket keeps its budget)
			T.check(n <= 250, "visual arena: a pocket stays <= 250 parts", n .. " parts, " .. dark .. " drift slabs")
			AB.FreePocket(pocket)
		end

		-- Phase 5 (C4 / C12, 6.2): Portal_Ring is a WorldStyle gate in the plaza's Gate Court (workspace.NimbusLobby.Gates,
		-- <= 120 parts) in champion gold with its crowned pedestals (gold crowns, violet Neon gems); no Trial Portal is left
		local lobby = workspace:FindFirstChild("NimbusLobby")
		local gates = lobby and lobby:FindFirstChild("Gates")
		local ringPortal = gates and gates:FindFirstChild("Portal_Ring", true)
		if T.check(ringPortal ~= nil, "visual ring: Portal_Ring is built in the Gate Court (NimbusLobby.Gates)") then
			local rparts = partsOf(ringPortal)
			local gold, gems, colours = 0, 0, {}
			for _, p in ipairs(rparts) do
				if p.Transparency < 1 then
					colours[colorKey(p.Color)] = true
					local c = p.Color
					if c.R > 0.85 and c.G > 0.6 and c.B < 0.4 then
						gold = gold + 1
					end
					if p.Name == "CrownGem" and p.Material == Enum.Material.Neon then
						gems = gems + 1
					end
				end
			end
			local nColours = 0
			for _ in pairs(colours) do
				nColours = nColours + 1
			end
			T.check(#rparts <= 120, "visual ring: Portal_Ring stays within the 120-part gate budget", #rparts .. " parts")
			T.check(gold >= 6 and gems >= 2 and nColours >= 4, "visual ring: champion gold crowns + violet gems on its pedestals, shaded stone",
				gold .. " gold, " .. gems .. " gems, " .. nColours .. " colours")
		end
		T.check(workspace:FindFirstChild("Portal_Trials", true) == nil, "visual ring: no Trial Portal is left anywhere (Phase 5: Trials are gone)")

		-- Phase 4: the Champion Ring pocket: a two-tone round floor inside a gold rim, four crown posts with violet gems,
		-- the crowd: cloud puffs in at least four soft colours with faces looking at the ring, outside the battle square
		local rp = AB.BuildPocket and AB.BuildPocket(62, "Ring")
		if T.check(type(rp) == "table" and rp.Model and rp.Kind == "Ring", "visual ring: a Champion Ring pocket builds") then
			local n = #partsOf(rp.Model)
			local floorCols, rimGold, gems, tints, eyes, faceBad = {}, 0, 0, {}, 0, 0
			for _, p in ipairs(partsOf(rp.Model)) do
				local rel = rp.CFrame:PointToObjectSpace(p.Position)
				if p.Name == "RingFloor" or p.Name == "RingCanvas" then
					floorCols[colorKey(p.Color)] = true
				elseif p.Name == "RingRimInlay" and p.Material == Enum.Material.Neon and p.Color.R > 0.85 and p.Color.B < 0.4 then
					rimGold = rimGold + 1
				elseif p.Name == "CrownGem" and p.Material == Enum.Material.Neon then
					gems = gems + 1
				elseif p.Name == "Body" and p.Parent and p.Parent:GetAttribute("Spectator") ~= nil then
					-- bug #11: the sky-sailor clouds (one Model per spectator, its Body root carries the eyes)
					tints[colorKey(p.Color)] = true
					if abs(rel.X) < 22 and abs(rel.Z) < 22 then
						faceBad = faceBad + 1
					end
				elseif p.Name == "PuffEye" then
					eyes = eyes + 1
					-- the eyes sit on the side that looks at the ring centre
					local body = (p.Parent and p.Parent.Name == "Body") and p.Parent or nil
					if body then
						local toCentre = (rp.CFrame.Position - body.Position) * Vector3.new(1, 0, 1)
						if (p.Position - body.Position):Dot(toCentre) <= 0 then
							faceBad = faceBad + 1
						end
					end
				end
			end
			local nFloor, nTints = 0, 0
			for _ in pairs(floorCols) do
				nFloor = nFloor + 1
			end
			for _ in pairs(tints) do
				nTints = nTints + 1
			end
			T.check(n <= 250, "visual ring: the ring pocket stays within 250 parts (Phase 5 art pass)", n .. " parts")
			T.check(nFloor >= 2 and rimGold >= 8 and gems == 4, "visual ring: a two-tone floor, a Marble rim with a champion-gold inlay and four violet crown gems", nFloor .. " floor colours, " .. rimGold .. " inlay, " .. gems .. " gems")
			T.check(nTints >= 4 and eyes >= 10 and faceBad == 0, "visual ring: a cheering crowd of cloud puffs in soft colours, every face turned to the ring, all outside the battle square",
				nTints .. " colours, " .. eyes .. " eyes, " .. faceBad .. " wrong")
			AB.FreePocket(rp)
		end
	end)

	S.p3visual_bosses = guarded("p3visual_bosses", function()
		local BB = req("shared/BossBuilder")
		if not T.check(BB ~= nil and type(BB.Build) == "function", "visual bosses: shared/BossBuilder.lua loads") then
			return
		end
		local mustKeep = {
			frost_wyrm = { "Belly", "Frost", "ScaleDark" },
			shadow_hydra = { "Belly", "Spike" },
			lava_golem = { "Ash", "Magma" },
			storm_titan = { "Metal", "Mist" },
		}
		for _, id in ipairs(BB.Ids()) do
			local high = BB.Build(id, { Detail = "High" })
			local low = BB.Build(id, { Detail = "Low" })
			if T.check(high ~= nil and low ~= nil, "visual bosses: " .. id .. " builds at High and Low") then
				local nh, nl = #partsOf(high), #partsOf(low)
				T.check(nh <= 1000 and nl <= 760 and nl < nh, "visual bosses: " .. id .. " within budget (High <= 1000, Low <= 760)", nh .. " / " .. nl)
				-- the torso keeps its light / dark shading: several shades of its main colour region
				local body = high:FindFirstChild("Body")
				local shades, names = {}, {}
				for _, p in ipairs(partsOf(body)) do
					shades[p.Name] = shades[p.Name] or {}
					shades[p.Name][colorKey(p.Color)] = true
					names[p.Name] = true
				end
				local best, bestKey = 0, "?"
				for key, set in pairs(shades) do
					local n = 0
					for _ in pairs(set) do
						n = n + 1
					end
					if n > best then
						best, bestKey = n, key
					end
				end
				T.check(best >= 2, "visual bosses: " .. id .. "'s torso keeps light / dark shades (not one flat colour)", bestKey .. ": " .. best .. " shades")
				local missing = {}
				for _, key in ipairs(mustKeep[id] or {}) do
					if not names[key] then
						missing[#missing + 1] = key
					end
				end
				T.check(#missing == 0, "visual bosses: " .. id .. "'s torso keeps its colour regions at High", "missing " .. table.concat(missing, ", "))
				local lowNames = {}
				for _, p in ipairs(partsOf(low:FindFirstChild("Body"))) do
					lowNames[p.Name] = true
				end
				local lost = {}
				for _, key in ipairs(mustKeep[id] or {}) do
					if not lowNames[key] then
						lost[#lost + 1] = key
					end
				end
				T.check(#lost == 0, "visual bosses: " .. id .. "'s Low detail keeps the accents too", "missing " .. table.concat(lost, ", "))
				high:Destroy()
				low:Destroy()
			end
		end
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client world
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local KC = _G.KC
	local S = {}
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer

	local function moduleAt(top, rest)
		local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end

	local function pg()
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end

	local function shown(obj)
		local cur = obj
		while cur and cur ~= game do
			if cur:IsA("LayerCollector") then
				if cur.Enabled == false then
					return false
				end
			elseif cur:IsA("GuiObject") and cur.Visible == false then
				return false
			end
			cur = cur.Parent
		end
		return cur ~= nil
	end

	local function advance(seconds)
		Mock.Advance(seconds)
	end

	local function isWhite(c)
		return c and c.R > 0.93 and c.G > 0.93 and c.B > 0.93
	end

	-- a real raid BattleSim, sent the way BattleService sends it, until its first telegraph
	local function raidDriver()
		local Sim = moduleAt("shared", "BattleSim")
		local PC = moduleAt("shared", "PetCatalog")
		if not Sim or not PC then
			return nil
		end
		local pets = {}
		for _, def in ipairs(PC.Pets or {}) do
			if def.Role == "Combat" and not def.EventOnly and def.Rarity ~= "Secret" then
				pets[#pets + 1] = { Key = def.Id, PetId = def.Id, Level = 10, Tier = "Normal", Slot = #pets + 1 }
				if #pets >= 3 then
					break
				end
			end
		end
		local id = "visual_raid_" .. tostring(math.random(100000, 999999))
		local mate = {}
		for i, p in ipairs(pets) do
			mate[i] = { Key = p.Key, PetId = p.PetId, Level = 8, Tier = "Normal", Slot = i }
		end
		local sim = Sim.new({ Mode = "Raid", Seed = 5, Id = id, Boss = "storm_titan", Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = pets }, { Owner = 77, Side = 1, Pets = mate } } })
		if not sim then
			return nil
		end
		local d = { sim = sim, id = id }
		function d.start()
			local p = sim:Describe()
			p.BattleId = id
			p.Zone = { CFrame = CFrame.new(0, 200, 0), Size = Vector3.new(p.Zone.X, 30, p.Zone.Z), X = p.Zone.X, Z = p.Zone.Z }
			p.Names = { [tostring(LocalPlayer.UserId)] = LocalPlayer.Name }
			p.Side = 1
			p.Spectator = false
			p.T = sim:Time()
			KC.toClient("BattleState", "Start", p, id)
		end
		function d.step()
			local evs = sim:Step(0.1)
			if #evs > 0 then
				KC.toClient("BattleState", "Events", evs, id)
			end
			local snap = sim:Snapshot()
			snap.BattleId = id
			local units, top = {}, 0
			for k in pairs(snap.Units) do
				if k > top then
					top = k
				end
			end
			for k = 1, top do
				units[k] = snap.Units[k] or { x = 0, z = 0, hp = 0, state = 5, meter = 0 }
			end
			snap.Units = units
			KC.toClient("BattleState", "Snapshot", snap, id)
			for _ = 1, 3 do
				Mock.Step(0.1 / 3)
			end
			return evs
		end
		return d
	end

	local function rimParts()
		local out = {}
		local root = workspace:FindFirstChild("ClientBattle")
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if d:IsA("BasePart") and d.Name == "BattleFx" and d.Material == Enum.Material.Neon and d.Parent and abs(d.Size.Y - 0.16) < 1e-3
				and d.Transparency < 0.99 then
				out[#out + 1] = d
			end
		end
		return out
	end

	S.client_p3visual = guarded("client_p3visual", function()
		local BC = moduleAt("client", "Controllers/BattleController")
		if T.check(BC ~= nil and KC ~= nil, "visual client: BattleController loads") then
			local d = raidDriver()
			if T.check(d ~= nil, "visual client: a raid BattleSim for the telegraph check") then
				LocalPlayer:SetAttribute("InBattle", d.id)
				d.start()
				Mock.Step(0.1)
				local seen, maxRim, rimColor = false, 0, nil
				for _ = 1, 400 do
					local evs = d.step()
					for _, e in ipairs(evs) do
						if e.type == "Telegraph" or e.t == "Telegraph" or e.Type == "Telegraph" then
							seen = true
						end
					end
					local rim = rimParts()
					if #rim > maxRim then
						maxRim = #rim
						rimColor = rim[1].Color
					end
					if seen and maxRim >= 16 then
						break
					end
				end
				T.check(maxRim >= 16, "visual client: a circle telegraph draws a crisp rim (16 neon segments)", maxRim .. " segments")
				if rimColor then
					local sat = max(rimColor.R, rimColor.G, rimColor.B) - min(rimColor.R, rimColor.G, rimColor.B)
					T.check(sat >= 0.3, "visual client: ...in the attack's saturated colour (it reads on the pale sand)", colorKey(rimColor))
				end
				-- Phase 4 (contract 3.9): the unit cards read on the pale sand: a solid dark plate, a stroked "Lv", green HP
				-- for my pets and a teammate's, red for enemies; the raid boss keeps its top-card bar (no card)
				local cards, solid, stroked, greens, bossCard = 0, 0, 0, 0, false
				local modes = {}
				for _, u in ipairs(d.sim.units or {}) do
					local info = BC.GetUnit(u.id)
					local card = info and info.Card
					if card and card.Gui then
						cards = cards + 1
						modes[card.Mode] = true
						local plate = card.Gui:FindFirstChild("Plate")
						local c = plate and plate.BackgroundColor3
						if c and plate.BackgroundTransparency <= 0.2 and (0.3 * c.R + 0.59 * c.G + 0.11 * c.B) < 0.35 then
							solid = solid + 1
						end
						local lv = plate and plate:FindFirstChild("Level")
						if lv and (lv:FindFirstChildOfClass("UIStroke") or lv.TextStrokeTransparency < 0.5) then
							stroked = stroked + 1
						end
						local fill = plate and plate:FindFirstChild("Hp") and plate.Hp:FindFirstChild("Fill")
						local fc = fill and fill.BackgroundColor3
						if fc and u.side == 1 and fc.G > fc.R then
							greens = greens + 1
						elseif fc and u.side ~= 1 and fc.R > fc.G then
							greens = greens + 1
						end
						if info.Kind == "Boss" then
							bossCard = true
						end
					end
				end
				-- (Phase 5: my fighter + my two helpers + the teammate's FIGHTER; another player's helpers are not drawn)
				T.check(cards >= 4 and solid == cards and stroked == cards, "visual client: every unit card has a solid dark plate and a stroked Lv (reads on the sand)", solid .. "/" .. stroked .. " of " .. cards)
				T.check(greens == cards and modes.Unit and modes.Ally, "visual client: HP rows are green for my pets (Unit) and a teammate's (Ally), red for enemies", greens .. " of " .. cards)
				T.check(not bossCard, "visual client: the raid boss has no pet card (its HP bar is in the top card)")
				-- after the hits the rims go with their telegraphs
				for _ = 1, 60 do
					d.step()
				end
				KC.toClient("BattleState", "End", { BattleId = d.id, Result = "Lost", Rewards = {} }, d.id)
				LocalPlayer:SetAttribute("InBattle", nil)
				for _ = 1, 40 do
					Mock.Step(0.1)
				end
				T.check(#rimParts() == 0, "visual client: no telegraph rim is left once the battle is over", #rimParts() .. " left")
				-- (no BattleController.Stop here: it disconnects the controller for the scenarios that follow)
				for _ = 1, 60 do
					Mock.Step(0.1) -- let the result card close by itself
				end
			end
		end

		-- white pet names on the rarity-tinted cards (Team picker, Trial enemy cards)
		local MC = moduleAt("client", "Controllers/MenuController")
		local AC = moduleAt("client", "Controllers/ArenaController")
		if not T.check(type(MC) == "table" and type(AC) == "table", "visual client: MenuController and ArenaController load") then
			return
		end
		pcall(MC.Init)
		pcall(AC.Init)
		-- a profile with a few pets and a team (like smoke_p3_ui.lua's), so the picker has tiles
		local owned = { "biscuit_bear", "ember_phoenix", "sunbeam_bear", "pebble_pup", "cloudy_dragon" }
		local pets, levels = {}, {}
		for i, id in ipairs(owned) do
			pets[id] = 1
			levels[id] = { Level = 2 + i, Xp = 0 }
		end
		KC.toClient("ProfileSync", {
			Tokens = 900, Pets = pets, Equipped = {}, Items = {},
			Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
			Discovered = {}, IndexClaimed = {}, Tutorial = { Step = 1000, Done = true, Gifted = true },
			Cash = 0, Gems = 0, Home = { Level = 5, Prestige = 0, Stations = {}, Garden = {}, Gym = {}, CollectorCash = 0 },
			Food = {}, Tiers = {}, Hybrids = {}, PetLevels = levels,
			Teams = { Presets = { { "biscuit_bear", "ember_phoenix", "sunbeam_bear" }, {}, {} }, Active = 1, Slots = 3 },
			Battle = { Trophies = 340, TrialBest = 6, TrialCleared = { true, true, true, true, true, true }, Raids = 0, RaidBestDamage = 0, PvPWins = 0, PvPLosses = 0, EventPets = {} },
		})
		advance(0.5)
		pcall(MC.Open, "Team")
		advance(0.8)
		local menu = pg() and pg():FindFirstChild("NimbusMenu")
		local win = menu and menu:FindFirstChild("Window_Team")
		local grid = win and find(win, "PickerGrid")
		local tiles, white = 0, 0
		for _, c in ipairs(grid and grid:GetChildren() or {}) do
			local name = c:IsA("TextButton") and c:FindFirstChild("PetName")
			if name and name.Text ~= "" then
				tiles = tiles + 1
				if isWhite(name.TextColor3) then
					white = white + 1
				end
			end
		end
		if tiles > 0 then
			T.check(white == tiles, "visual client: the Team picker writes pet names in white on the tinted tiles", white .. " of " .. tiles)
		else
			T.info("visual client: no pets owned in this world, the Team picker tile names are checked by the phone run")
		end
		pcall(MC.Close)
		advance(0.3)
		-- (Phase 5: the Trial window is gone with the Trials; its enemy-card checks went with it)
	end)

	-- Phase 5: (the Trial window is gone) a battle unit's PetCard on a portrait phone: Lv >= 14 px with its stroke, the
	-- fighter's lives pips sized for the phone
	S.client_p3visual_mobile = guarded("client_p3visual_mobile", function()
		local PCard = moduleAt("client", "UI/PetCard")
		if not T.check(type(PCard) == "table" and type(PCard.New) == "function", "visual phone: PetCard loads") then
			return
		end
		local part = Instance.new("Part")
		part.Anchored = true
		part.Parent = workspace
		local card = PCard.New(part, "Unit", 2.5, { Name = "VisualPhoneCard" })
		card:SetLevel(34, 1, false)
		card:SetLives(2, 3)
		advance(0.1)
		local lv = card.Gui:FindFirstChild("Plate") and card.Gui.Plate:FindFirstChild("Level")
		T.check(lv and lv.TextSize >= 14 and (lv:FindFirstChildOfClass("UIStroke") or lv.TextStrokeTransparency < 0.5), "visual phone: a battle card's Lv is >= 14 px with its stroke", lv and tostring(lv.TextSize) or "nil")
		local pips = card.Gui:FindFirstChild("Lives", true)
		local lit = 0
		for _, p in ipairs(pips and pips:GetChildren() or {}) do
			if p:IsA("Frame") and p.Visible and p.BackgroundColor3.R > 0.8 and p.BackgroundColor3.G < 0.5 then
				lit = lit + 1
			end
		end
		T.check(pips and pips.Visible and lit == 2 and pips.Size.Y.Offset >= 5, "visual phone: the fighter's lives pips show (2 of 3 lit, >= 5 px)", tostring(lit) .. " lit")
		card:SetLives(nil)
		T.check(pips and not pips.Visible, "visual phone: SetLives(nil) hides the pips")
		card:Destroy()
		part:Destroy()
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
