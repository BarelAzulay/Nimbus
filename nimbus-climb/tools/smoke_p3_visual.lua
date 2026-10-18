-- smoke_p3_visual.lua: the Phase 3 visual pass (ARCHITECTURE_V3.md ART DIRECTION, Readability + World text rules,
-- "Phase 3: Pet battles"). Loaded by tools/smoke.py in BOTH worlds; ARGS.context picks the half:
--   p3visual_arena    (server, booted) the arena floors are crafted, not one flat colour: raked sand drifts on the boss
--                     floor (flat slabs just over the sand, inside the gold line, clear of the element wheel), framed
--                     element marks, worn / warm stretches in the forum paving, sand drifts on every duel ring (under
--                     its painted circle), drifts on a trial pocket's floor; the arena stays <= 2500 parts and a
--                     pocket <= 250; the gate and arch sign titles fit their panels (World text rule sizes kept); the
--                     event board draws the live boss HP bar (and hides it without a raid); Phase 4: Portal_Ring is a
--                     crowned arch in champion gold and royal violet (<= 70 parts, a gold crown on top, no crossed
--                     swords) and the Champion Ring pocket (<= 220) has a two-tone floor, a gold rim, four violet crown
--                     gems and a cheering crowd of cloud puffs in soft colours facing the ring, outside the square
--   p3visual_bosses   (server) every boss keeps its shading and its colour regions at High detail (the torso is not
--                     folded into one flat colour: several shades per region, the Frost Wyrm's belly and frost patch,
--                     the Hydra's belly, the Golem's ash), High <= 1000 parts and Low <= 760, Low keeps the accents
--   client_p3visual   (client) a boss telegraph has a crisp rim in its saturated colour (16 neon segments round a
--                     circle) besides the pale area, and the rim goes with it after the hit; Phase 4: every unit's
--                     PetCard reads on the sand (solid dark plate, stroked Lv, green HP for mine / a teammate's, red for
--                     enemies; the raid boss keeps its top-card bar); the Team picker tiles and
--                     the Trial window's enemy cards write pet names in white on their rarity-tinted cards
--   client_p3visual_mobile (phone world) the Trial window's enemy cards use the width of a portrait phone (two wide
--                     columns instead of two narrow cards and a gap)
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
		T.check(#all <= 2500, "visual arena: the detailed arena stays within its 2500-part budget", #all .. " parts")

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

		-- the forum paving: plain paving plus worn and warm stretches
		local paving = find(model, "Paving")
		local keys = {}
		for _, p in ipairs(partsOf(paving)) do
			keys[p.Name] = (keys[p.Name] or 0) + 1
		end
		T.check((keys.Worn or 0) > 0 and (keys.Warm or 0) > 0, "visual arena: the forum paving has worn and sun-warmed stretches (never one flat colour)",
			"Worn " .. tostring(keys.Worn) .. ", Warm " .. tostring(keys.Warm))

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

		-- a trial pocket: sand drifts on its floor, within 250 parts
		local pocket = AB.BuildPocket and AB.BuildPocket(61)
		if T.check(type(pocket) == "table" and pocket.Model, "visual arena: a trial pocket builds") then
			local n = #partsOf(pocket.Model)
			local dark = 0
			for _, p in ipairs(partsOf(find(pocket.Model, "PocketFloor"))) do
				if p.Name == "SandDark" then
					dark = dark + 1
				end
			end
			T.check(n <= 250 and dark > 0, "visual arena: the pocket's sand floor has drifts and the pocket stays <= 250 parts", n .. " parts, " .. dark .. " drift slabs")
			AB.FreePocket(pocket)
		end

		-- Phase 4: the Champion Ring portal reads differently from the Trial Portal (a crowned arch in champion gold and
		-- royal violet), within 70 parts, with shading on its stone (never one flat colour)
		local ringPortal = model:FindFirstChild("Portal_Ring")
		if T.check(ringPortal ~= nil, "visual ring: Portal_Ring is built") then
			local rparts = partsOf(ringPortal)
			local gold, violet, neon, colours = 0, 0, 0, {}
			for _, p in ipairs(rparts) do
				if p.Transparency < 1 then
					colours[colorKey(p.Color)] = true
					local c = p.Color
					if c.R > 0.85 and c.G > 0.6 and c.B < 0.4 then
						gold = gold + 1
					elseif c.B > 0.75 and c.R > 0.45 and c.G < 0.6 then
						violet = violet + 1
					end
					if p.Material == Enum.Material.Neon then
						neon = neon + 1
					end
				end
			end
			local nColours = 0
			for _ in pairs(colours) do
				nColours = nColours + 1
			end
			T.check(#rparts <= 70, "visual ring: Portal_Ring stays within 70 parts", #rparts .. " parts")
			T.check(gold >= 6 and violet >= 4 and neon >= 4 and nColours >= 6, "visual ring: champion gold trim + crown, royal violet glows and gems, shaded stone",
				gold .. " gold, " .. violet .. " violet, " .. neon .. " neon, " .. nColours .. " colours")
			local gate = ringPortal:FindFirstChild("Gate")
			local top, crownGold = -huge, 0
			for _, p in ipairs(partsOf(gate)) do
				top = max(top, p.Position.Y + p.Size.Y / 2)
			end
			for _, p in ipairs(partsOf(gate)) do
				if p.Position.Y + p.Size.Y / 2 > top - 5 and p.Color.R > 0.85 and p.Color.B < 0.4 then
					crownGold = crownGold + 1
				end
			end
			T.check(crownGold >= 3, "visual ring: a gold crown tops the gate (several gold blocks in its top 5 studs)", crownGold .. " blocks")
			local trial = model:FindFirstChild("Portal_Trials")
			T.check(trial ~= nil and trial:FindFirstChild("CrestBlade", true) ~= nil and ringPortal:FindFirstChild("CrestBlade", true) == nil, "visual ring: the crossed swords stay the Trial Portal's, the ring has its crown")
		end

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
				elseif p.Name == "RingRim" and p.Color.R > 0.85 and p.Color.B < 0.4 then
					rimGold = rimGold + 1
				elseif p.Name == "CrownGem" and p.Material == Enum.Material.Neon then
					gems = gems + 1
				elseif p.Name == "PuffBody" then
					tints[colorKey(p.Color)] = true
					if abs(rel.X) < 22 and abs(rel.Z) < 22 then
						faceBad = faceBad + 1
					end
				elseif p.Name == "PuffEye" then
					eyes = eyes + 1
					-- the eyes sit on the side that looks at the ring centre
					local body = nil
					for _, q in ipairs(p.Parent:GetChildren()) do
						if q.Name == "PuffBody" and (q.Position - p.Position).Magnitude < 2.5 then
							body = q
						end
					end
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
			T.check(n <= 220, "visual ring: the ring pocket stays within 220 parts", n .. " parts")
			T.check(nFloor >= 2 and rimGold >= 8 and gems == 4, "visual ring: a two-tone floor, a gold rim and four violet crown gems", nFloor .. " floor colours, " .. rimGold .. " rim, " .. gems .. " gems")
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
				T.check(cards >= 6 and solid == cards and stroked == cards, "visual client: every unit card has a solid dark plate and a stroked Lv (reads on the sand)", solid .. "/" .. stroked .. " of " .. cards)
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
		pcall(AC.OpenTrials, 12)
		advance(0.8)
		local arena = pg() and pg():FindFirstChild("NimbusArena")
		local trials = arena and arena:FindFirstChild("Window_Trials")
		local enemies = trials and find(trials, "Enemies")
		local cards, whiteCards = 0, 0
		for _, c in ipairs(enemies and enemies:GetChildren() or {}) do
			local name = c:IsA("Frame") and c:FindFirstChild("PetName")
			if name then
				cards = cards + 1
				if isWhite(name.TextColor3) then
					whiteCards = whiteCards + 1
				end
			end
		end
		T.check(cards > 0 and whiteCards == cards, "visual client: the Trial window's enemy cards write names in white", whiteCards .. " of " .. cards)
		pcall(AC.Close)
		advance(0.3)
	end)

	S.client_p3visual_mobile = guarded("client_p3visual_mobile", function()
		local AC = moduleAt("client", "Controllers/ArenaController")
		if not T.check(type(AC) == "table" and type(AC.OpenTrials) == "function", "visual phone: ArenaController loads") then
			return
		end
		pcall(AC.Init)
		pcall(AC.OpenTrials, 12)
		advance(0.8)
		local arena = pg() and pg():FindFirstChild("NimbusArena")
		local trials = arena and arena:FindFirstChild("Window_Trials")
		local enemies = trials and find(trials, "Enemies")
		local layout = enemies and enemies:FindFirstChildOfClass("UIGridLayout")
		if T.check(layout ~= nil and shown(enemies), "visual phone: the Trial window shows the enemy team") then
			local cell = layout.CellSize.X.Offset
			-- on-screen boxes (the window is scaled): the cards' right edge against the row's right edge
			local left, right, n = huge, -huge, 0
			for _, c in ipairs(enemies:GetChildren()) do
				if c:IsA("Frame") and c.Visible then
					n = n + 1
					left = min(left, c.AbsolutePosition.X)
					right = max(right, c.AbsolutePosition.X + c.AbsoluteSize.X)
				end
			end
			local rowW = enemies.AbsoluteSize.X
			local gap = (enemies.AbsolutePosition.X + rowW) - right
			local cardW = n > 0 and (right - left) / math.min(n, 2) or 0
			T.check(cell > 130, "visual phone: two wide enemy cards per row on a portrait phone", "cell " .. cell .. " design px")
			T.check(n > 0 and gap <= cardW * 0.35, "visual phone: ...using the window's width (no gap the size of a card)",
				string.format("%d cards, %.0f px free of a %.0f px row", n, gap, rowW))
		end
		pcall(AC.Close)
		advance(0.3)
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
