-- smoke_p2_homeworld.lua: Phase 2 home world (ARCHITECTURE_V3.md "Phase 2 build contract": HomeBuilder + HomeFx,
-- ART DIRECTION, World text rule, Replication rule). Loaded by tools/smoke.py in BOTH worlds; ARGS.context picks the
-- half:
--   p2home_art      (server) every station at every level (HomeBuilder.BuildStationModel; Phase 5 contract 3.6):
--                   clean models (Station_<Id>, anchored, no welds / scripts / asset ids, none of the retired pieces:
--                   plants, Coin Magnet, cushion bowls, sand walks), the per-station budgets (Farm 150, Garden 95, Food
--                   Machine 55, Training Place 90, House 150, Fusion 90, Fence 90, Fountain 80, others 80), every level
--                   differs from the one before, every station inside its Slot.Footprint; the Berry Farm (40 levels:
--                   never fewer parts, 1 red bush per level 1-10, the blue row 11-22, a gold vine per level 23-37, the
--                   Starberry tree 38-40, the FarmSign "Berry Farm Lv N" / 70 studs, BerryPoint), the Food Machine's
--                   glass Hopper + MachineSign with the BasketLine, the Training Place's mats (Spot1..level at
--                   Slot.Spots), the Garden's 12 beds for every open count 0..12 (Spot1..12 at Slot.Beds, a
--                   GardenSpotPrompt beside each open bed only: E, MaxActivationDistance 3, no line of sight; seedling
--                   beds with "Prestige to open" signs; an open inside and entrance; <= 95 parts), the Food Bowl at
--                   Slot.Bowl with its sign (40 studs), the Garden:<level>:<open> cache, the House tiers, the Fusion
--                   Machine (pods, chamber, Swirl, FusionPrompt), the Arena Gate (ArenaGatePrompt, Teleport Arena), the
--                   Fountain's 4 / 6 / 8 lanterns and the Fence's three looks; templates are reused
--   p2home_plot     (server, booted) a private test plot far from the lobby: PreparePlot (Home folder tagged
--                   NC_Home, the gate's ClaimPrompt "Claim Home" / "Free home" / E / SpotIndex, the FREE HOME
--                   signpost, idempotent, at most 3 parts per free plot), SetOwner, junk arguments never error, a greedy
--                   progression through TycoonCatalog.AvailablePads (never > 950 parts, the full plot <= 950), contract
--                   names and attributes on stations, the Berry Farm (Kind Farm, BerryPoint, sign), no old plants / Coin
--                   Magnet, the Food Machine (Hopper, MachineSign, ChuteMouth / Tray / HopperTop / BasketTop) and the
--                   Training Place on their swapped slots, SetGarden (12 beds, prompts on the open EMPTY beds,
--                   owner-only, a new open count rebuilds the Garden, clamped to 12), HomeRoam plans (3 seeds x 12 slots
--                   x 3 cycles) never cross station art at pet height, the Welcome-back pile clear, SetTraining
--                   (attributes only), the Fusion Machine, pads, layout sanity (inside the yard, no pad / path blocked,
--                   no two stations overlap), the 6.4 art rules on the whole plot (materials, muted big faces, small
--                   parts without shadows, warm lights, NC_Detail decor blocks nothing), the server never moves a part
--                   and creates no Instance per coin, ClearPlot
--   client_p2home   (client) HomeFx on plots HomeBuilder builds in the client world (standing in for replication):
--                   it finds every NC_Home, hides another player's BuyPrompts / GardenSpotPrompts / pad signs and the
--                   claim prompts of other plots while the local player owns a home (and keeps hiding a prompt the
--                   server re-enables), the owner's prompts stay; (Phase 5) CoinDrops draws a 6-part TokenLook
--                   Cloud Cash coin per drop at its HomeRoam poop point (a Lucky one sparkles, no lights) and the
--                   Welcome-back heap (<= 60) at Garden.Slot.WelcomePile, a drop that goes takes its coin; no client
--                   bowls; the Garden's pets (GardenPets) roam the yard on the ground, a place above GardenSlots asleep
--                   on its bed (Zzz), roaming pets walk and poop once per 24 s cycle, the Berry Farm's berries fly;
--                   the Training Place's pets (TrainingPets) on their mats with a moving voxel prop; the Fusion swirl
--                   turns; a new station pops in and ends exactly where the server built it; the owner's pads dim
--                   when Cash cannot pay; far homes freeze and put heaps, bowls, coins and pets away; nothing is
--                   created per frame; ClearPlot / removing the home cleans up; no errors or warnings from HomeFx
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, floor, max, min, huge = math.abs, math.floor, math.max, math.min, math.huge

local function fmt(v, n)
	if type(v) ~= "number" then
		return tostring(v)
	end
	return string.format("%." .. (n or 2) .. "f", v)
end

local function parts(root)
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

-- world-aligned box {x0, y0, z0, x1, y1, z1} of a part (its 8 corners)
local function aabb(p)
	local h = p.Size / 2
	local x0, y0, z0, x1, y1, z1 = huge, huge, huge, -huge, -huge, -huge
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local c = p.CFrame * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
				x0, y0, z0 = min(x0, c.X), min(y0, c.Y), min(z0, c.Z)
				x1, y1, z1 = max(x1, c.X), max(y1, c.Y), max(z1, c.Z)
			end
		end
	end
	return { x0, y0, z0, x1, y1, z1 }
end

-- bounds of every visible part of a model in the model's frame `cf` (default: world)
local function bounds(root, cf)
	local b = { huge, huge, huge, -huge, -huge, -huge }
	for _, p in ipairs(parts(root)) do
		if p.Transparency < 1 then
			local h = p.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local c = p.CFrame * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
						if cf then
							c = cf:PointToObjectSpace(c)
						end
						b[1], b[2], b[3] = min(b[1], c.X), min(b[2], c.Y), min(b[3], c.Z)
						b[4], b[5], b[6] = max(b[4], c.X), max(b[5], c.Y), max(b[6], c.Z)
					end
				end
			end
		end
	end
	return b
end

local function overlap(a, b, tol)
	tol = tol or 0
	return a[1] < b[4] - tol and b[1] < a[4] - tol and a[2] < b[5] - tol and b[2] < a[5] - tol and a[3] < b[6] - tol and b[3] < a[6] - tol
end

local function colorNear(a, b, tol)
	return abs(a.R - b.R) * 255 <= tol and abs(a.G - b.G) * 255 <= tol and abs(a.B - b.B) * 255 <= tol
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

local function findAll(root, pred)
	local out = {}
	if root then
		for _, d in ipairs(root:GetDescendants()) do
			if pred(d) then
				out[#out + 1] = d
			end
		end
	end
	return out
end

local function plainText(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("TextLabel") then
			out[#out + 1] = d.Text
		end
	end
	return table.concat(out, " | ")
end

-- the station's stamp: part count + bounds + colour/material census (to tell two levels apart)
local function signature(model)
	local list = {}
	for _, p in ipairs(parts(model)) do
		list[#list + 1] = string.format("%s:%.1f,%.1f,%.1f:%s:%.0f", p.Name, p.Size.X, p.Size.Y, p.Size.Z, p.Color:ToHex(), p.Transparency * 100)
	end
	table.sort(list)
	return table.concat(list, ";")
end

local GOLD = Color3.fromRGB(244, 198, 84)

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local K = _G.K
	local S = {}
	local CollectionService = game:GetService("CollectionService")

	local function requireAt(key)
		local inst = K.moduleInstance(key)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		if ok and type(result) == "table" then
			return result
		end
		return nil
	end

	-- Phase 5 contract 3.6: per-station part budgets (by kind; the decor by id)
	local BUDGET_KIND = { Farm = 150, Garden = 95, FoodMachine = 55, Training = 90, House = 150, Fusion = 90, Vault = 80, Arena = 80 }
	local BUDGET_ID = { DecorFence = 90, DecorFountain = 80 }
	local DEFAULT_BUDGET = 80
	local function budgetOf(def)
		return BUDGET_ID[def.Id] or BUDGET_KIND[def.Kind] or DEFAULT_BUDGET
	end
	-- names of retired pieces: the Phase 2/3 machines, the Phase 4 plants / Coin Magnet / cushion bowls / sand walks
	local RETIRED = {
		PressHead = true, Conveyor = true, CollectPad = true, CollectPrompt = true, CashGui = true, CashFill = true, CashLabel = true,
		CapLabel = true, CookPrompt = true, FeedBowl = true, Belt = true, MagnetHead = true, Entrance = true,
		WestJoin = true, EastJoin = true, CushionBowl = true,
	}
	local RETIRED_ATTR = { "FruitPoint", "Fruit", "FruitColor", "MagnetCenter" }

	S.p2home_art = guarded("p2home_art", function()
		local HB = requireAt("server/Services/HomeBuilder")
		local TC = requireAt("shared/TycoonCatalog")
		if not T.check(type(HB) == "table", "HomeBuilder: server/Services/HomeBuilder.lua loads") then
			return
		end
		if not T.check(type(TC) == "table", "HomeBuilder art: shared/TycoonCatalog loads") then
			return
		end
		local api = T.tally("HomeBuilder: the contract API exists (Init, PreparePlot, SetOwner, SetStation, SetPads, SetGarden, SetTraining, ClearPlot)")
		for _, fn in ipairs({ "Init", "PreparePlot", "SetOwner", "SetStation", "SetPads", "SetGarden", "SetTraining", "ClearPlot" }) do
			api:case(type(HB[fn]) == "function", fn)
		end
		api:report()
		T.check(HB.SetCollector == nil, "HomeBuilder: SetCollector is gone (Phase 4)")
		if type(HB.BuildStationModel) ~= "function" then
			T.warn("HomeBuilder art: no BuildStationModel extra, the per-level art checks are skipped")
			return
		end
		T.check(TC.Get("Press2") == nil and TC.Get("Collector") == nil and HB.BuildStationModel("Press2", 1) == nil and HB.BuildStationModel("Collector", 1) == nil,
			"station art: the 4 old plants and the Coin Magnet are gone (Press2-4 / Collector build nothing)")

		local clean = T.tally("station art: every station at every level builds a clean model (anchored, no welds, no scripts, no asset ids, no retired pieces or attributes)")
		local budget = T.tally("station art: per-station part budgets (Farm 150, Garden 95, Food Machine 55, Training Place 90, House 150, Fusion 90, Fence 90, Fountain 80, others 80)")
		local differ = T.tally("station art: every level looks different from the one before")
		local fits = T.tally("station art: every station stays inside its Slot.Footprint (+0.75 stud; the Yard Fence inside the plot)")
		local models = {} -- [id] = { [level] = { b = bounds, n = parts, sig = s, model = m } }
		local t0 = os.clock()
		local builds = 0
		for _, def in ipairs(TC.Stations) do
			if def.Kind ~= "Prestige" then
				models[def.Id] = {}
				local prev = nil
				local fp = def.Slot.Footprint
				for level = 1, def.MaxLevel do
					local ok, m = pcall(HB.BuildStationModel, def.Id, level)
					builds = builds + 1
					if not ok or typeof(m) ~= "Instance" then
						clean:case(false, def.Id .. " " .. level .. ": " .. tostring(m))
					else
						local list = parts(m)
						local bad = nil
						for _, p in ipairs(list) do
							if not p.Anchored then
								bad = "unanchored " .. p.Name
							end
						end
						for _, d in ipairs(m:GetDescendants()) do
							if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Script") or d:IsA("LocalScript") then
								bad = d.ClassName .. " " .. d.Name
							elseif d:IsA("ParticleEmitter") and tostring(d.Texture):find("rbxassetid", 1, true) then
								bad = "asset id on " .. d.Name
							elseif RETIRED[d.Name] then
								bad = "retired piece " .. d.Name
							end
						end
						for _, a in ipairs(RETIRED_ATTR) do
							if m:GetAttribute(a) ~= nil then
								bad = "retired attribute " .. a
							end
						end
						clean:case(bad == nil and m.Name == "Station_" .. def.Id and #list > 0, def.Id .. " " .. level .. ": " .. tostring(bad or m.Name))
						local cap = budgetOf(def)
						budget:case(#list <= cap, def.Id .. " " .. level .. ": " .. #list .. " parts > " .. cap)
						local b = bounds(m)
						if def.Slot.Perimeter then
							local half = TC.PlotSize / 2
							fits:case(b[1] >= -half and b[4] <= half and b[3] >= -half and b[6] <= half, def.Id .. " " .. level .. string.format(" x %.1f..%.1f z %.1f..%.1f", b[1], b[4], b[3], b[6]))
						else
							local hx, hz = fp.X / 2 + 0.75, fp.Z / 2 + 0.75
							fits:case(b[1] >= -hx and b[4] <= hx and b[3] >= -hz and b[6] <= hz and b[5] <= fp.Y + 3.5,
								def.Id .. " " .. level .. string.format(" x %.1f..%.1f z %.1f..%.1f top %.1f (footprint %gx%gx%g)", b[1], b[4], b[3], b[6], b[5], fp.X, fp.Y, fp.Z))
						end
						local sig = signature(m)
						models[def.Id][level] = { b = b, n = #list, sig = sig, model = m }
						if prev then
							differ:case(sig ~= prev, def.Id .. " level " .. level .. " looks exactly like level " .. (level - 1))
						end
						prev = sig
					end
				end
			end
		end
		clean:report(builds .. " models")
		budget:report()
		differ:report()
		fits:report()
		T.info("station art: " .. builds .. " station levels built in " .. fmt(os.clock() - t0, 2) .. " s")

		local function size(id, level)
			local r = models[id] and models[id][level]
			if not r then
				return nil
			end
			local b = r.b
			return b[4] - b[1], b[5] - b[2], b[6] - b[3], r
		end
		local function count(m, name)
			local n = 0
			for _, p in ipairs(parts(m)) do
				if p.Name == name then
					n = n + 1
				end
			end
			return n
		end
		local function modelAt(id, level)
			return models[id] and models[id][level] and models[id][level].model
		end

		-- the Berry Farm (Press1): 40 levels that visibly grow (3.6)
		local farmDef = TC.Get("Press1")
		T.check(farmDef and farmDef.Kind == "Farm" and farmDef.MaxLevel == 40 and farmDef.Name == "Berry Farm", "station art: Press1 is the Berry Farm (Kind Farm, 40 levels)")
		local grows = T.tally("station art: the Berry Farm never loses parts from one level to the next and gains something at every level")
		for level = 2, 40 do
			local a, b = models.Press1[level - 1], models.Press1[level]
			grows:case(a and b and b.n >= a.n, (level - 1) .. " -> " .. level .. ": " .. tostring(a and a.n) .. " -> " .. tostring(b and b.n))
		end
		grows:report()
		local rows = T.tally("station art: the farm's rows follow the levels (L1-10 one red bush per level, L11-22 the blue row, L23-37 a gold-berry vine per level, L38-40 the Starberry tree)")
		local wantRows = { [1] = { 1, 0, 0 }, [10] = { 10, 0, 0 }, [11] = { 11, 0, 0 }, [22] = { 22, 0, 0 }, [23] = { 22, 1, 0 }, [37] = { 22, 15, 0 }, [38] = { 22, 15, 1 }, [40] = { 22, 15, 1 } }
		for level, want in pairs(wantRows) do
			local m = modelAt("Press1", level)
			local bushes, vines, tree = count(m, "Bush"), count(m, "Vine"), (count(m, "Trunk") > 0 and count(m, "Starberry") > 0) and 1 or 0
			rows:case(bushes == want[1] and vines == want[2] and tree == want[3], "level " .. level .. ": " .. bushes .. " bushes, " .. vines .. " vines, tree " .. tree)
		end
		rows:report()
		local farmSign = T.tally("station art: the farm wears its sign (pixel billboard FarmSign 'Berry Farm Lv N' / 'Grows berries for your pets', MaxDistance 70) and a BerryPoint")
		for _, level in ipairs({ 1, 13, 40 }) do
			local m = modelAt("Press1", level)
			local gui = find(m, "FarmSign", "BillboardGui")
			local text = gui and plainText(gui) or ""
			local pts = HB.Points and HB.Points("Press1", level)
			farmSign:case(gui and gui.MaxDistance == 70 and gui.Size.X.Scale == 0 and gui.LightInfluence == 0 and text:find("Berry Farm Lv " .. level, 1, true) and text:find("Grows berries for your pets", 1, true)
				and pts and typeof(pts.BerryPoint) == "Vector3", "level " .. level .. ": '" .. text .. "'")
		end
		farmSign:report()

		-- the Food Machine: the glass Hopper part PetCareService's FeedPrompt sits on, the sign with the basket line
		local hopper = T.tally("station art: the Food Machine (Kitchen) has one glass Hopper part on top and the MachineSign ('Food Machine' / 'Berries -> XP: press E' / BasketLine) at every level")
		for level = 1, TC.Get("Kitchen").MaxLevel do
			local m = modelAt("Kitchen", level)
			local list = {}
			for _, p in ipairs(parts(m)) do
				if p.Name == "Hopper" then
					list[#list + 1] = p
				end
			end
			local h = list[1]
			local _, height = size("Kitchen", level)
			local gui = find(m, "MachineSign", "BillboardGui")
			local text = gui and plainText(gui) or ""
			hopper:case(TC.Get("Kitchen").Kind == "FoodMachine" and #list == 1 and h.Material == Enum.Material.Glass and h.Transparency > 0.2 and h.Transparency < 0.9 and h.Position.Y > height * 0.5
				and gui ~= nil and text:find("Food Machine", 1, true) and text:find("Berries -> XP: press E", 1, true) and find(gui, "BasketLine", "TextLabel") ~= nil,
				"level " .. level .. ": " .. #list .. " Hopper parts, sign '" .. text .. "'")
		end
		hopper:report()
		-- the Training Place: one mat per level with the Spot<i> attachments at the catalog's Spots, on the deck
		local mats = T.tally("station art: the Training Place (Gym) lays one mat per level with Attachments Spot1..level (attribute Slot) at Slot.Spots on the deck")
		local gymDef = TC.Get("Gym")
		for level = 1, gymDef.MaxLevel do
			local m = modelAt("Gym", level)
			local found, bad = 0, nil
			for i = 1, 5 do
				local a = m and find(m, "Spot" .. i, "Attachment")
				if a then
					found = found + 1
					local want = gymDef.Slot.Spots[i]
					local at = a.WorldPosition
					if a:GetAttribute("Slot") ~= i or abs(at.X - want.X) > 0.05 or abs(at.Z - want.Z) > 0.05 or at.Y < 0.6 or at.Y > 1.6 then
						bad = "Spot" .. i .. string.format(" at %.2f, %.2f, %.2f", at.X, at.Y, at.Z)
					end
				end
			end
			mats:case(gymDef.Kind == "Training" and found == level and count(m, "Mat") == level and bad == nil, "level " .. level .. ": " .. found .. " spots " .. tostring(bad or ""))
		end
		mats:report()

		-- the Garden (3.3 / 3.6): 12 beds at Slot.Beds, the Food Bowl, the fence ring with the entrance
		local gdef = TC.Get("Garden")
		local gs = gdef.Slot
		local beds = gs.Beds
		local hx, hz, ft = gs.Footprint.X / 2, gs.Footprint.Z / 2, gs.Fence
		local ent = gs.Entrance
		local garden = T.tally("station art: the Pet Garden has 12 beds (Attachments Spot1..12, attribute Slot / Open) at Slot.Beds for every open count 0..12, within 95 parts")
		local prompts = T.tally("station art: every OPEN bed (and only those) carries a GardenSpotPrompt 'Put a pet here' (E, MaxActivationDistance 3, no line of sight, attribute Slot) beside the bed")
		local closed = T.tally("station art: every bed beyond the open count is a seedling bed (Stem + Sprout) with a 'Prestige to open' sign (40-60 px per stud); open beds have a cushion under a little roof")
		local clearIn = T.tally("station art: the Garden's inside stays clear for the roaming pets (no solid or decor part between 0.7 and 3 studs except the beds and the bowl) and its entrance is open")
		for _, level in ipairs({ 1, 4, gdef.MaxLevel }) do
			for open = 0, #beds do
				local ok, m = pcall(HB.BuildStationModel, "Garden", level, nil, open)
				if not ok or typeof(m) ~= "Instance" then
					garden:case(false, "level " .. level .. " open " .. open .. ": " .. tostring(m))
				else
					local n = #parts(m)
					local spotOk, promptN, promptBad = 0, 0, nil
					for i, want in ipairs(beds) do
						local a = find(m, "Spot" .. i, "Attachment")
						if a and a:GetAttribute("Slot") == i and a:GetAttribute("Open") == (i <= open) and abs(a.WorldPosition.X - want.X) < 0.05 and abs(a.WorldPosition.Z - want.Z) < 0.05 then
							spotOk = spotOk + 1
						end
					end
					for _, d in ipairs(m:GetDescendants()) do
						if d:IsA("ProximityPrompt") and d.Name == "GardenSpotPrompt" then
							promptN = promptN + 1
							local slot = d:GetAttribute("Slot")
							local at = d.Parent and d.Parent:IsA("Attachment") and d.Parent.WorldPosition
							local bed = beds[slot or 0]
							local dist = (bed and at) and (Vector3.new(at.X, 0, at.Z) - Vector3.new(bed.X, 0, bed.Z)).Magnitude or huge
							if not (bed and slot <= open and d.ActionText == "Put a pet here" and d.KeyboardKeyCode == Enum.KeyCode.E and d.MaxActivationDistance == 3
								and d.RequiresLineOfSight == false and d:GetAttribute("StationId") == "Garden" and dist <= 2.2 and dist >= 1.2) then
								promptBad = "slot " .. tostring(slot) .. string.format(" %.2f from its bed", dist)
							end
						end
					end
					local stems, sprouts, signs = count(m, "Stem"), count(m, "Sprout"), 0
					for _, p in ipairs(parts(m)) do
						if p.Name == "ClosedSign" then
							local gui = p:FindFirstChildWhichIsA("SurfaceGui")
							local text = gui and plainText(gui) or ""
							if gui and gui.PixelsPerStud >= 40 and gui.PixelsPerStud <= 60 and text:find("Prestige", 1, true) and text:find("to open", 1, true) then
								signs = signs + 1
							end
						end
					end
					garden:case(spotOk == #beds and n <= 95 and m:GetAttribute("Open") == open, "level " .. level .. " open " .. open .. ": " .. spotOk .. " spots, " .. n .. " parts")
					prompts:case(promptN == open and promptBad == nil, "level " .. level .. " open " .. open .. ": " .. promptN .. " prompts " .. tostring(promptBad or ""))
					closed:case(signs == #beds - open and stems == #beds - open and sprouts == #beds - open and count(m, "Cushion") == open and count(m, "BedRoof") == open,
						"level " .. level .. " open " .. open .. ": " .. signs .. " signs, " .. stems .. " seedlings, " .. count(m, "Cushion") .. " cushions")
					-- the interior (inside the fence band) at pet height: only beds, the bowl and their own pieces
					local OK_IN = { Bed = true, Cushion = true, Headboard = true, BedRoof = true, SoilBed = true, Stem = true, Sprout = true, ClosedSign = true,
						FoodBowl = true, BowlRim = true, BowlBerries = true, BowlBerry = true, Lawn = true, Walk = true }
					local hit = nil
					for _, p in ipairs(parts(m)) do
						if p.Transparency < 0.5 and not OK_IN[p.Name] then
							local b = aabb(p)
							local inside = b[1] < hx - ft - 0.2 and b[4] > -hx + ft + 0.2 and b[3] < hz - ft - 0.2 and b[6] > -hz + ft + 0.2
							if inside and b[2] < 3 and b[5] > 0.7 then
								hit = p.Name .. string.format(" at %.1f, %.1f", p.Position.X, p.Position.Z)
							end
							-- the entrance gap (Slot.Entrance) at walking height
							if b[1] < ent.Center.X + ent.Width / 2 - 0.05 and b[4] > ent.Center.X - ent.Width / 2 + 0.05 and b[3] < -hz + ft + 0.5 and b[6] > -hz - 0.5 and b[2] < 3.0 and b[5] > 0.5 then
								hit = "entrance blocked by " .. p.Name
							end
						end
					end
					clearIn:case(hit == nil, "level " .. level .. " open " .. open .. ": " .. tostring(hit))
					m:Destroy()
				end
			end
		end
		garden:report()
		prompts:report()
		closed:report()
		clearIn:report()
		local gm = modelAt("Garden", gdef.MaxLevel)
		local bowl = gm and find(gm, "FoodBowl", "BasePart")
		local bowlGui = bowl and find(bowl, "BowlSign", "BillboardGui")
		local bowlText = bowlGui and plainText(bowlGui) or ""
		T.check(bowl ~= nil and abs(bowl.Position.X - gs.Bowl.Center.X) < 0.05 and abs(bowl.Position.Z - gs.Bowl.Center.Z) < 0.05 and abs(math.max(bowl.Size.X, bowl.Size.Z) - 2 * gs.Bowl.Radius) < 0.6
			and bowlGui ~= nil and bowlGui.MaxDistance == 40 and bowlText:find("Food Bowl", 1, true) and bowlText:find("Pets eat here, then poop Cloud Cash!", 1, true),
			"station art: the Food Bowl stands at Slot.Bowl (radius " .. gs.Bowl.Radius .. ") with its sign 'Food Bowl' / 'Pets eat here, then poop Cloud Cash!' (MaxDistance 40)", bowlText)
		local g3a, g3b, g7 = HB.BuildStationModel("Garden", 3, nil, 5), HB.BuildStationModel("Garden", 3, nil, 5), HB.BuildStationModel("Garden", 3, nil, 7)
		T.check(g3a and g3b and g7 and signature(g3a) == signature(g3b) and signature(g3a) ~= signature(g7),
			"station art: the Garden template is cached per Garden:<level>:<open> (same open count = the same model, another count = another model)")
		for _, g in ipairs({ g3a, g3b, g7 }) do
			g:Destroy()
		end

		-- the house: every tier clearly grander
		local tiers = T.tally("station art: the House goes Cottage -> Villa -> Manor -> Sky Castle, each tier taller or with a bigger footprint")
		for level = 2, 4 do
			local w0, h0, d0 = size("House", level - 1)
			local w1, h1, d1 = size("House", level)
			tiers:case(w0 and w1 and h1 >= h0 + 1.5 and (h1 >= h0 + 4 or w1 * d1 >= w0 * d0 * 1.05), string.format("tier %d -> %d: %sx%sx%s -> %sx%sx%s", level - 1, level, fmt(w0, 0), fmt(h0, 0), fmt(d0, 0), fmt(w1, 0), fmt(h1, 0), fmt(d1, 0)))
		end
		tiers:report()
		local bigger = T.tally("station art: the Garden, Food Machine, Training Place, Vault, Fusion Machine and Berry Farm hold more at their top level than at level 1")
		for _, id in ipairs({ "Garden", "Kitchen", "Gym", "Vault", "FusionMachine", "Press1" }) do
			local def = TC.Get(id)
			local r1, rN = models[id][1], models[id][def.MaxLevel]
			bigger:case(r1 and rN and rN.n > r1.n, id .. ": " .. tostring(r1 and r1.n) .. " -> " .. tostring(rN and rN.n) .. " parts")
		end
		bigger:report()
		-- the Fusion Machine: two input pods, a glass chamber with the Swirl, an output pod, a prompt
		local fusion = modelAt("FusionMachine", 1)
		if T.check(fusion ~= nil, "station art: the Fusion Machine builds") then
			local swirl = fusion:FindFirstChild("Swirl")
			T.check(count(fusion, "Pod") == 2 and find(fusion, "Chamber") ~= nil and find(fusion, "OutputDome") ~= nil, "station art: the Fusion Machine has two glass input pods, a glass chamber and an output pod")
			T.check(swirl ~= nil and swirl:IsA("Model") and #parts(swirl) >= 3, "station art: ...with a Swirl model inside the chamber (HomeFx spins it)")
			local prompt = find(fusion, "FusionPrompt", "ProximityPrompt")
			T.check(prompt ~= nil and prompt.ActionText == "Fuse" and prompt.HoldDuration == 0 and prompt:GetAttribute("StationId") == "FusionMachine", "station art: ...and a FusionPrompt that opens the Fusion window")
			local _, h1 = size("FusionMachine", 1)
			T.check(h1 and h1 >= 8, "station art: ...and it is an impressive machine (>= 8 studs tall)", fmt(h1, 1) .. " studs")
		end
		-- the Arena Gate: a half-size red gate with the teleport prompt
		local gate = modelAt("ArenaGate", 1)
		local gp = gate and find(gate, "ArenaGatePrompt", "ProximityPrompt")
		local portal = gate and find(gate, "Portal", "BasePart")
		T.check(gp ~= nil and gp:GetAttribute("Teleport") == "Arena" and gp:GetAttribute("StationId") == "ArenaGate" and gp.ActionText == "Go to Arena" and portal ~= nil and not portal.CanCollide
			and count(gate, "Column") == 2 and count(gate, "Inlay") >= 3,
			"station art: the Arena Gate is a small gate (two columns, a neon inlay, a walk-through Portal) with the ArenaGatePrompt (Teleport = Arena)")
		-- the decor: three levels each, the fountain's lanterns 4 / 6 / 8
		local lanterns = T.tally("station art: the Fountain carries 4 / 6 / 8 lanterns (wood / brass / crystal) and the Yard Fence three different looks")
		for level = 1, 3 do
			local m = modelAt("DecorFountain", level)
			lanterns:case(count(m, "Lantern") == 2 + 2 * level, "fountain level " .. level .. ": " .. count(m, "Lantern") .. " lanterns")
		end
		local fence1, fence3 = modelAt("DecorFence", 1), modelAt("DecorFence", 3)
		lanterns:case(count(fence1, "Pickets") >= 5 and count(fence3, "Wall") >= 5 and count(fence3, "Cloth") >= 4 and count(modelAt("DecorFence", 2), "Hedge") >= 5, "fence looks")
		lanterns:report()
		-- templates are cloned: a second build of the same level is identical
		local a = HB.BuildStationModel("House", 4)
		local b = HB.BuildStationModel("House", 4)
		T.check(a and b and a ~= b and signature(a) == signature(b), "station art: heavy pieces are built once and cloned (two builds of the Sky Castle are identical copies)")
		for _, levels in pairs(models) do
			for _, r in pairs(levels) do
				r.model:Destroy()
			end
		end
		if a then
			a:Destroy()
		end
		if b then
			b:Destroy()
		end
	end)

	S.p2home_plot = guarded("p2home_plot", function()
		local HB = requireAt("server/Services/HomeBuilder")
		local TC = requireAt("shared/TycoonCatalog")
		if not (type(HB) == "table" and type(TC) == "table") then
			T.warn("home plot: HomeBuilder or TycoonCatalog missing, skipped")
			return
		end
		local outputBefore, errorsBefore = #Mock.Output, #Mock.Errors
		-- a private plot far from the lobby (never one TycoonService manages)
		local root = Instance.new("Folder")
		root.Name = "SmokeHomes"
		root.Parent = workspace
		local spotFolder = Instance.new("Folder")
		spotFolder.Name = "Spot_91"
		spotFolder.Parent = root
		local plotCF = CFrame.new(4000, 300, 4000) * CFrame.Angles(0, math.rad(90), 0)
		local half = TC.PlotSize / 2
		local spot = { Index = 91, PlotCFrame = plotCF, PlotSize = TC.PlotSize, Center = plotCF.Position, Folder = spotFolder }
		local home = HB.PreparePlot(spot)
		if not T.check(typeof(home) == "Instance" and home.Name == "Home" and home.Parent == spotFolder, "home plot: PreparePlot makes the plot's Home folder", tostring(home)) then
			root:Destroy()
			return
		end
		T.check(CollectionService:HasTag(home, "NC_Home") and home:GetAttribute("SpotIndex") == 91, "home plot: the Home folder is tagged NC_Home with its SpotIndex (HomeFx finds it)")
		local claims = findAll(spotFolder, function(d)
			return d:IsA("ProximityPrompt") and d.Name == "ClaimPrompt"
		end)
		local claim = claims[1]
		T.check(#claims == 1 and claim.ActionText == "Claim Home" and claim.ObjectText == "Free home" and claim.KeyboardKeyCode == Enum.KeyCode.E
			and claim.HoldDuration == 0 and claim:GetAttribute("SpotIndex") == 91 and claim.Enabled,
			"home plot: the gate has one ClaimPrompt 'Claim Home' (E, ObjectText 'Free home', attribute SpotIndex)", claim and (claim.ActionText .. " / " .. claim.ObjectText) or "none")
		if claim then
			local gatePos = plotCF * Vector3.new(0, 0, -half)
			local p = claim.Parent
			local at = (p and p:IsA("Attachment") and p.WorldPosition) or (p and p:IsA("BasePart") and p.Position) or nil
			T.check(at ~= nil and (Vector3.new(at.X, gatePos.Y, at.Z) - gatePos).Magnitude <= 3 and claim.MaxActivationDistance >= 8,
				"home plot: the ClaimPrompt sits in the gate opening (reachable from the street)")
		end
		local signParts = 0
		local claimGate = spotFolder:FindFirstChild("ClaimGate")
		for _, d in ipairs(claimGate and claimGate:GetDescendants() or {}) do
			if d:IsA("BasePart") then
				signParts = signParts + 1
			end
		end
		T.check(signParts <= 3, "home plot: a free plot adds at most 3 parts (the lobby's part budget)", signParts .. " parts")
		local sign = find(spotFolder, "ClaimGui", "SurfaceGui")
		T.check(sign ~= nil and sign.PixelsPerStud >= 40 and sign.PixelsPerStud <= 60 and plainText(sign):find("FREE HOME", 1, true) and plainText(sign):find("Press E", 1, true),
			"home plot: a FREE HOME signpost tells free plots apart (\"Press E at the gate\", 40-60 px per stud)")
		local lobbySpots = (K.W and K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
		local cheap = T.tally("home plot: every free lobby plot carries its ClaimPrompt in the gate on the lobby's own gate part (2 parts added per plot)")
		for i, info in pairs(lobbySpots) do
			local folder = info.Folder
			local prompt = folder and find(folder, "ClaimPrompt", "ProximityPrompt")
			local gateModel = folder and folder:FindFirstChild("ClaimGate")
			local n = 0
			for _, d in ipairs(gateModel and gateModel:GetDescendants() or {}) do
				if d:IsA("BasePart") then
					n = n + 1
				end
			end
			cheap:case(prompt ~= nil and n <= 2 and prompt.Parent:IsA("Attachment"), "spot " .. tostring(i) .. ": " .. n .. " parts, prompt on " .. (prompt and prompt.Parent.ClassName or "nothing"))
		end
		cheap:report()
		T.check(HB.PreparePlot(spot) == home and #findAll(spotFolder, function(d)
			return d.Name == "ClaimPrompt"
		end) == 1, "home plot: PreparePlot is idempotent (same Home folder, one ClaimPrompt)")

		-- an owner (a real player: SetOwner takes a Player)
		local owner = Mock.AddPlayer("HomeSmoke", 963501)
		K.advance(1.0)
		HB.SetOwner(spot, owner)
		T.check(home:GetAttribute("OwnerUserId") == owner.UserId and not claim.Enabled and find(spotFolder, "ClaimGui") == nil,
			"home plot: SetOwner(player) writes OwnerUserId; the claim prompt and the signpost go away while owned")

		-- junk never errors
		local junk = T.tally("home plot: junk arguments never error (unknown ids, NaN / negative / huge levels, wrong types)")
		for _, args in ipairs({ { "Nope", 1 }, { "Press1", 0 / 0 }, { "Press1", -5 }, { 42, 1 }, { "Press1", "x" }, { nil, nil }, { "Prestige", 1 } }) do
			local ok, err = pcall(HB.SetStation, spot, args[1], args[2])
			junk:case(ok, tostring(args[1]) .. "/" .. tostring(args[2]) .. ": " .. tostring(err))
		end
		local okPads, errPads = pcall(HB.SetPads, spot, { { StationId = 5 }, "x", { StationId = "Nope" } })
		junk:case(okPads, "SetPads junk: " .. tostring(errPads))
		for _, args in ipairs({ { nil, 0 / 0 }, { "x", -3 }, { { [0] = "a", [99] = "b", [1.5] = "c", [2] = 5, x = "y" }, 1e9 }, { {}, "7" }, { { [1] = "" }, math.huge } }) do
			local okG, errG = pcall(HB.SetGarden, spot, args[1], args[2])
			junk:case(okG, "SetGarden(" .. tostring(args[1]) .. ", " .. tostring(args[2]) .. "): " .. tostring(errG))
		end
		for _, arg in ipairs({ "x", { [0] = {}, [9] = {}, [1] = "y", [2] = { Ends = 0 / 0 }, [3] = { Key = 5, Ends = math.huge } }, 7 }) do
			local okT, errT = pcall(HB.SetTraining, spot, arg)
			junk:case(okT, "SetTraining(" .. tostring(arg) .. "): " .. tostring(errT))
		end
		HB.SetGarden(spot, {}, 3)
		local okH = pcall(HB.SetStation, spot, "Press1", 99)
		junk:case(okH and (home:FindFirstChild("Station_Press1") == nil or home.Station_Press1:GetAttribute("Level") == TC.Get("Press1").MaxLevel), "level 99 is clamped to MaxLevel")
		HB.SetStation(spot, "Press1", 0)
		junk:report()

		-- a greedy progression through the pads, the way a player fills the yard
		local state = { Stations = {}, Prestige = 0 }
		local function partCount()
			return #parts(home)
		end
		local maxParts, maxAt, steps = 0, "", 0
		local stationOk = T.tally("home plot: every purchase builds Station_<Id> under Home with StationId / Level / BuiltAt; the pads follow")
		local padOk = T.tally("home plot: every pad is Pad_<Id> under Home/Pads with a BuyPrompt 'Buy' (E, 0.25 s, StationId, OwnerUserId; the Prestige pad's says 'Prestige' with a hold >= 1 s), enabled only when unlocked")
		local signOk = T.tally("home plot: every pad sign is a pixel-sized billboard (names >= 22 px, info >= 18 px, outlined, LightInfluence 0, MaxDistance 50-150) showing the name and 'Lv a -> b' + price or the lock reason")
		local ghostOk = T.tally("home plot: stations that unlock later ('Unlocks at Prestige', 'Coming soon') show a cheap ghost (<= 12 parts, no prompts, no collisions)")
		local function checkPads(pads)
			local padFolder = home:FindFirstChild("Pads")
			for _, pad in ipairs(pads) do
				local m = padFolder and padFolder:FindFirstChild("Pad_" .. pad.StationId)
				if not m then
					padOk:case(false, "no Pad_" .. pad.StationId)
				else
					local prompt = find(m, "BuyPrompt", "ProximityPrompt")
					local locked = pad.Locked ~= nil and pad.Locked ~= ""
					-- the Prestige pad buys nothing: "Prestige" with a long hold (it opens the prestige confirmation)
					local wantText, holdOk = "Buy", prompt ~= nil and abs(prompt.HoldDuration - 0.25) < 1e-6
					if pad.StationId == "Prestige" then
						wantText, holdOk = "Prestige", prompt ~= nil and prompt.HoldDuration >= 1
					end
					padOk:case(prompt ~= nil and prompt.ActionText == wantText and holdOk and prompt.KeyboardKeyCode == Enum.KeyCode.E
						and prompt:GetAttribute("StationId") == pad.StationId and prompt:GetAttribute("OwnerUserId") == owner.UserId
						and m:GetAttribute("StationId") == pad.StationId and m:GetAttribute("OwnerUserId") == owner.UserId and prompt.Enabled == not locked,
						pad.StationId .. (prompt and (" enabled=" .. tostring(prompt.Enabled) .. " locked=" .. tostring(locked)) or " no BuyPrompt"))
					local gui = find(m, "PadSign", "BillboardGui")
					if not gui then
						signOk:case(false, pad.StationId .. ": no PadSign")
					else
						local pixel = gui.Size.X.Scale == 0 and gui.Size.Y.Scale == 0 and gui.LightInfluence == 0 and gui.MaxDistance >= 50 and gui.MaxDistance <= 150
						local biggest, smallest, outlined = 0, huge, true
						for _, d in ipairs(gui:GetDescendants()) do
							if d:IsA("TextLabel") and d.Text ~= "" then
								biggest, smallest = max(biggest, d.TextSize), min(smallest, d.TextSize)
								local stroke = d:FindFirstChildWhichIsA("UIStroke")
								if d.TextStrokeTransparency > 0.5 and not stroke then
									outlined = false
								end
							end
						end
						local text = plainText(gui)
						local wants = locked and tostring(pad.Locked) or tostring(pad.LevelText or "")
						signOk:case(pixel and biggest >= 22 and smallest >= 18 and outlined and text:find(tostring(pad.Title or pad.Name), 1, true) ~= nil and text:find(wants, 1, true) ~= nil,
							pad.StationId .. ": '" .. text .. "' sizes " .. smallest .. "-" .. biggest)
					end
					if locked and (pad.Locked:find("Prestige", 1, true) or pad.Locked:find("Coming soon", 1, true)) and (tonumber(pad.Level) or 0) == 0 and pad.StationId ~= "Prestige" then
						local ghost = home:FindFirstChild("Ghost_" .. pad.StationId)
						local n = ghost and #parts(ghost) or 0
						local solid = false
						for _, p in ipairs(parts(ghost)) do
							if p.CanCollide then
								solid = true
							end
						end
						ghostOk:case(ghost ~= nil and n <= 12 and n > 0 and not solid and find(ghost, "BuyPrompt") == nil, pad.StationId .. ": " .. n .. " parts")
					end
				end
			end
		end
		local function buy(id, level)
			state.Stations[id] = level
			local m = HB.SetStation(spot, id, level)
			local built = home:FindFirstChild("Station_" .. id)
			stationOk:case(m ~= nil and built == m and m:GetAttribute("StationId") == id and m:GetAttribute("Level") == level and type(m:GetAttribute("BuiltAt")) == "number",
				id .. " -> " .. level)
			HB.SetGarden(spot, {}, TC.GardenSlots(state))
			local pads = TC.AvailablePads(state)
			HB.SetPads(spot, pads)
			steps = steps + 1
			local n = partCount()
			if n > maxParts then
				maxParts, maxAt = n, id .. " " .. level
			end
			return pads
		end
		local pads = TC.AvailablePads(state)
		HB.SetPads(spot, pads)
		checkPads(pads)
		for _ = 1, 400 do
			local pick = nil
			for _, pad in ipairs(pads) do
				if (pad.Locked == nil or pad.Locked == "") and pad.StationId ~= "Prestige" then
					if not pick or (tonumber(pad.Price) or 0) < (tonumber(pick.Price) or 0) then
						pick = pad
					end
				end
			end
			if not pick then
				if state.Prestige == 0 and TC.HouseTierOf and (state.Stations.House or 0) >= 4 then
					state.Prestige = 1 -- the first star unlocks the Fusion Machine and a 4th garden place; keep building
					HB.SetGarden(spot, {}, TC.GardenSlots(state))
					pads = TC.AvailablePads(state)
					HB.SetPads(spot, pads)
				else
					break
				end
			else
				pads = buy(pick.StationId, pick.NextLevel)
				if steps % 7 == 0 then
					checkPads(pads)
				end
			end
		end
		checkPads(pads)
		stationOk:report(steps .. " purchases")
		padOk:report()
		signOk:report()
		ghostOk:report()
		local full = partCount()
		T.check(maxParts <= 950, "home plot: the plot never passes ~950 parts while it fills up (pads included)", "max " .. maxParts .. " after " .. maxAt)
		T.check(full <= 950, "home plot: the fully built plot stays <= 950 parts (the Phase 3 Arena Gate is a real build)", full .. " parts")
		T.check(HB.PartCount == nil or HB.PartCount(spot) == full, "home plot: PartCount(spot) agrees")
		local maxed = 0
		for _, def in ipairs(TC.Stations) do
			if def.Kind ~= "Prestige" and not def.ComingSoon and (state.Stations[def.Id] or 0) >= def.MaxLevel then
				maxed = maxed + 1
			end
		end
		T.info("home plot: " .. steps .. " purchases, " .. maxed .. " stations maxed, " .. full .. " parts built, peak " .. maxParts)

		-- SetStation: same level again is a no-op; replacing a level swaps the model
		local press = home:FindFirstChild("Station_Press1")
		T.check(press ~= nil and HB.SetStation(spot, "Press1", state.Stations.Press1) == press, "home plot: SetStation with the same level keeps the model (no rebuild)")

		-- the Berry Farm (Press1): Kind Farm, its sign and the BerryPoint for HomeFx's berry flights
		local farm = home:FindFirstChild("Station_Press1")
		local bp = farm and farm:GetAttribute("BerryPoint")
		local farmSign = farm and find(farm, "FarmSign", "BillboardGui")
		local farmSlot = plotCF * TC.Get("Press1").Slot.CFrame
		T.check(farm ~= nil and farm:GetAttribute("Kind") == "Farm" and typeof(bp) == "Vector3" and math.abs(farmSlot:PointToObjectSpace(bp).Z) < 4 and farmSign ~= nil
			and plainText(farmSign):find("Berry Farm Lv " .. tostring(state.Stations.Press1), 1, true) ~= nil,
			"home plot: Station_Press1 is the Berry Farm (Kind Farm, a BerryPoint over its rows, the 'Berry Farm Lv N' sign)")
		T.check(home:FindFirstChild("Station_Collector") == nil and home:FindFirstChild("Station_Press2") == nil and #findAll(home, function(d)
			return d.Name == "MagnetHead" or (d:IsA("Model") and (d:GetAttribute("FruitPoint") ~= nil or d:GetAttribute("MagnetCenter") ~= nil))
		end) == 0, "home plot: no old plants and no Coin Magnet anywhere (merged into the Berry Farm and the Pet Garden)")
		local machine = home:FindFirstChild("Station_Kitchen")
		local hopperPart = machine and machine:FindFirstChild("Hopper", true)
		local machineSign = machine and find(machine, "MachineSign", "BillboardGui")
		T.check(machine ~= nil and machine:GetAttribute("Kind") == "FoodMachine" and hopperPart ~= nil and hopperPart:IsA("BasePart")
			and typeof(machine:GetAttribute("ChuteMouth")) == "Vector3" and typeof(machine:GetAttribute("Tray")) == "Vector3" and typeof(machine:GetAttribute("HopperTop")) == "Vector3"
			and typeof(machine:GetAttribute("BasketTop")) == "Vector3" and machineSign ~= nil and find(machineSign, "BasketLine", "TextLabel") ~= nil,
			"home plot: the Kitchen slot holds the Food Machine with its Hopper part (PetCareService's FeedPrompt), the MachineSign + BasketLine and the ChuteMouth / Tray / HopperTop / BasketTop points")
		local hopLocal = hopperPart and plotCF:PointToObjectSpace(hopperPart.Position)
		local gymSpot = home:FindFirstChild("Station_Gym") and find(home.Station_Gym, "Spot1", "Attachment")
		local gymLocal = gymSpot and plotCF:PointToObjectSpace(gymSpot.WorldPosition)
		T.check(hopLocal ~= nil and math.abs(hopLocal.X + 24) < 1.5 and math.abs(hopLocal.Z - 29.3) < 1.5 and gymLocal ~= nil and math.abs(gymLocal.X - 19) < 0.1 and math.abs(gymLocal.Z - 24) < 0.1,
			"home plot: the Food Machine and the Training Place stand on their swapped slots (Kitchen at (-24, 29), Gym at (25, 24))")
		local retired = findAll(home, function(d)
			return RETIRED[d.Name] == true
		end)
		T.check(#retired == 0 and home:GetAttribute("CollectorCap") == nil, "home plot: no Conveyor, press heads, Collector screen / CollectPad / CollectPrompt or cooking pieces anywhere in the home",
			#retired > 0 and retired[1]:GetFullName() or "")

		-- the Garden places (SetGarden): open count = garden places (3 + stars), prompts on the OPEN EMPTY places only
		local gdef = TC.Get("Garden")
		local gslot = plotCF * gdef.Slot.CFrame
		local function gardenPrompts()
			local out = {}
			local g = home:FindFirstChild("Station_Garden")
			for _, d in ipairs(g and g:GetDescendants() or {}) do
				if d:IsA("ProximityPrompt") and d.Name == "GardenSpotPrompt" then
					out[d:GetAttribute("Slot")] = d
				end
			end
			return out, g
		end
		local open0 = TC.GardenSlots(state)
		local gp, gmodel = gardenPrompts()
		local spotsOk = 0
		for i, want in ipairs(gdef.Slot.Beds) do
			local a = gmodel and find(gmodel, "Spot" .. i, "Attachment")
			if a and (gslot:PointToObjectSpace(a.WorldPosition) - Vector3.new(want.X, a.WorldPosition.Y - gslot.Position.Y, want.Z)).Magnitude < 0.05 then
				spotsOk = spotsOk + 1
			end
		end
		T.check(gmodel ~= nil and spotsOk == 12 and gmodel:GetAttribute("Open") == open0, "home plot: the Garden shows 12 beds (Spot1..12 at Slot.Beds) and Open = TC.GardenSlots(home)", spotsOk .. " spots, open " .. tostring(gmodel and gmodel:GetAttribute("Open")) .. " vs " .. open0)
		local enabled = 0
		for slot, pr in pairs(gp) do
			if pr.Enabled then
				enabled = enabled + 1
			end
		end
		T.check(enabled == open0 and gp[1] and gp[1]:GetAttribute("OwnerUserId") == owner.UserId, "home plot: every open empty place has an enabled, owner-only GardenSpotPrompt", enabled .. " enabled of " .. open0)
		HB.SetGarden(spot, { [1] = "cat", [3] = "fox@Golden" }, open0)
		gp = gardenPrompts()
		T.check(gp[1] and not gp[1].Enabled and gp[3] and not gp[3].Enabled and gp[2] and gp[2].Enabled and home:FindFirstChild("Station_Garden") == gmodel,
			"home plot: SetGarden(valid) disables the prompts of taken places, keeps the empty ones and does not rebuild the Garden")
		local before7 = Mock.CountDescendants(home)
		HB.SetGarden(spot, { [1] = "cat" }, 7)
		local gp7, g7 = gardenPrompts()
		local en7 = 0
		for slot, pr in pairs(gp7) do
			if pr.Enabled then
				en7 = en7 + 1
			end
		end
		T.check(g7 ~= nil and g7 ~= gmodel and gmodel.Parent == nil and g7:GetAttribute("Open") == 7 and en7 == 6 and g7:GetAttribute("Level") == state.Stations.Garden,
			"home plot: a new open count (a Prestige) rebuilds the Garden with 7 places (6 empty prompts), same level", "open " .. tostring(g7 and g7:GetAttribute("Open")) .. ", " .. en7 .. " prompts")
		HB.SetGarden(spot, {}, 12)
		local gp12 = gardenPrompts()
		local en12 = 0
		for _, pr in pairs(gp12) do
			if pr.Enabled then
				en12 = en12 + 1
			end
		end
		T.check(en12 == 12 and home:FindFirstChild("Station_Garden"):GetAttribute("Open") == 12, "home plot: 12 open places (the cap) show 12 prompts")
		HB.SetGarden(spot, {}, 40)
		T.check(home:FindFirstChild("Station_Garden"):GetAttribute("Open") == 12, "home plot: SetGarden clamps the open count to the 12 drawn places")
		HB.SetGarden(spot, {}, open0)
		T.info("home plot: the Garden went " .. open0 .. " -> 7 -> 12 -> " .. open0 .. " places; the home holds " .. (Mock.CountDescendants(home) - before7) .. " instances more than before")

		-- the roaming pets (HomeRoam, 3.5) never walk through station art: sampled plans of 3 seeds x 12 slots x 3 cycles,
		-- every point at pet height clear of every visible station part (beds, the bowl and the garden floor are theirs);
		-- the Welcome-back pile clear of pads and station art
		local Roam = requireAt("shared/HomeRoam")
		local OWN = { Bed = true, Cushion = true, Headboard = true, BedRoof = true, SoilBed = true, Stem = true, Sprout = true, ClosedSign = true,
			FoodBowl = true, BowlRim = true, BowlBerries = true, BowlBerry = true, Lawn = true, Walk = true }
		local stationBoxes = {}
		for _, m in ipairs(home:GetChildren()) do
			if m:IsA("Model") and m.Name:sub(1, 8) == "Station_" and m.Name ~= "Station_DecorFence" then
				for _, p in ipairs(parts(m)) do
					if p.Transparency < 0.5 and not OWN[p.Name] then
						local b = aabb(p)
						local lo = plotCF:PointToObjectSpace(Vector3.new(b[1], b[2], b[3]))
						local hi = plotCF:PointToObjectSpace(Vector3.new(b[4], b[5], b[6]))
						stationBoxes[#stationBoxes + 1] = { name = m.Name .. "." .. p.Name, x0 = min(lo.X, hi.X), x1 = max(lo.X, hi.X), z0 = min(lo.Z, hi.Z), z1 = max(lo.Z, hi.Z), y0 = b[2] - plotCF.Position.Y, y1 = b[5] - plotCF.Position.Y }
					end
				end
			end
		end
		local function blockedAt(x, z, r)
			for _, sb in ipairs(stationBoxes) do
				if sb.y0 < 2.0 and sb.y1 > 0.7 and x > sb.x0 - r and x < sb.x1 + r and z > sb.z0 - r and z < sb.z1 + r then
					return sb.name
				end
			end
			return nil
		end
		local roamClear = T.tally("home plot: the roaming pets' walks (HomeRoam plans) never pass through station art at pet height")
		if type(Roam) == "table" and type(Roam.Plan) == "function" then
			local samples = 0
			for _, seed in ipairs({ 1, 777001, 424242 }) do
				for slot = 1, 12 do
					for cycle = 1, 3 do
						local plan = Roam.Plan(seed, slot, cycle)
						local pts = plan and plan.Out or {}
						local hit = nil
						for k = 2, #pts do
							local a, b = pts[k - 1], pts[k]
							local ax, az, bx, bz = a.x or a[1], a.z or a[2], b.x or b[1], b.z or b[2]
							local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
							local n = max(1, math.ceil(len / 0.5))
							for t = 0, n do
								local f = t / n
								local h = blockedAt(ax + (bx - ax) * f, az + (bz - az) * f, 0.2)
								samples = samples + 1
								if h and not hit then
									hit = h .. string.format(" at %.1f, %.1f", ax + (bx - ax) * f, az + (bz - az) * f)
								end
							end
						end
						roamClear:case(#pts > 1 and hit == nil, "seed " .. seed .. " slot " .. slot .. " cycle " .. cycle .. ": " .. tostring(hit or (#pts .. " points")))
					end
				end
			end
			roamClear:report(samples .. " samples")
		else
			T.warn("home plot: shared/HomeRoam missing, the roam clearance check is skipped")
		end
		local wp = gdef.Slot.WelcomePile
		if typeof(wp) == "Vector3" then
			local hit = blockedAt(wp.X, wp.Z, 0.4)
			for _, d in ipairs(TC.Stations) do
				local pc = d.Slot and typeof(d.Slot.Pad) == "CFrame" and d.Slot.Pad.Position
				if pc and math.abs(pc.X - wp.X) < 2.6 and math.abs(pc.Z - wp.Z) < 2.6 then
					hit = "pad " .. d.Id
				end
			end
			T.check(hit == nil, "home plot: the Welcome-back pile is clear of every pad and every station part", tostring(hit))
		end

		-- the Training Place: Spot1..level on the deck; SetTraining writes who trains where (attributes only)
		local gym = home:FindFirstChild("Station_Gym")
		local gymLevel = state.Stations.Gym or 0
		if T.check(gym ~= nil and gym:GetAttribute("Kind") == "Training", "home plot: the Gym slot holds the Training Place") then
			local spotsN = 0
			for i = 1, 5 do
				if find(gym, "Spot" .. i, "Attachment") then
					spotsN = spotsN + 1
				end
			end
			T.check(spotsN == gymLevel, "home plot: ...with one mat (Spot<i>) per level", spotsN .. " mats at level " .. gymLevel)
			local count0 = Mock.CountDescendants(home)
			HB.SetTraining(spot, { [1] = { Key = "cat", Stat = "Physique", Ends = 1760000000 }, [2] = { Key = "fox@Golden", Stat = "Speed", Ends = 1760000420.7 } })
			local s1, s2, s3 = find(gym, "Spot1", "Attachment"), find(gym, "Spot2", "Attachment"), find(gym, "Spot3", "Attachment")
			T.check(s1 and s1:GetAttribute("Busy") == true and s1:GetAttribute("Key") == "cat" and s1:GetAttribute("Stat") == "Physique" and s1:GetAttribute("Ends") == 1760000000
				and s2 and s2:GetAttribute("Ends") == 1760000420 and (not s3 or s3:GetAttribute("Busy") == false) and Mock.CountDescendants(home) == count0,
				"home plot: SetTraining marks the busy mats (Busy / Key / Stat / Ends) with attributes only")
			HB.SetTraining(spot, {})
			T.check(s1 and s1:GetAttribute("Busy") == false and s1:GetAttribute("Key") == "", "home plot: SetTraining({}) frees every mat")
		end

		-- the Fusion Machine
		local fusion = home:FindFirstChild("Station_FusionMachine")
		if T.check(fusion ~= nil, "home plot: the Fusion Machine is built after the first prestige") then
			T.check(fusion:FindFirstChild("Swirl") ~= nil and typeof(fusion:GetAttribute("SwirlCenter")) == "Vector3" and find(fusion, "FusionPrompt", "ProximityPrompt") ~= nil,
				"home plot: the Fusion Machine has its Swirl (SwirlCenter) and the owner-only FusionPrompt")
		end

		-- unchanged pads are kept, missing pads go
		local padFolder = home:FindFirstChild("Pads")
		local kept = HB.SetPads(spot, { { StationId = "DecorFountain", NextLevel = 2, Price = 10, Level = 1, Title = "Fountain", LevelText = "Lv 1 -> 2" } })
		local lamp = padFolder and padFolder:FindFirstChild("Pad_DecorFountain")
		HB.SetPads(spot, { { StationId = "DecorFountain", NextLevel = 2, Price = 10, Level = 1, Title = "Fountain", LevelText = "Lv 1 -> 2" } })
		T.check(kept and lamp ~= nil and padFolder:FindFirstChild("Pad_DecorFountain") == lamp and #padFolder:GetChildren() == 1, "home plot: SetPads keeps an unchanged pad and removes the pads that are no longer listed")
		HB.SetPads(spot, {})

		-- layout sanity on the built plot
		local inside = T.tally("home plot: every station stands inside the yard (fence decor along its edge)")
		local blocks = T.tally("home plot: no station blocks a buy pad or a stone path at walking height")
		local apart = T.tally("home plot: no two stations overlap")
		local solids = {}
		for _, m in ipairs(home:GetChildren()) do
			if m:IsA("Model") and m.Name:sub(1, 8) == "Station_" then
				local b = bounds(m, plotCF)
				local lim = half + ((m.Name == "Station_DecorFence") and 1.5 or 0.6)
				inside:case(b[1] >= -lim and b[4] <= lim and b[3] >= -lim and b[6] <= lim, m.Name .. string.format(" x %.1f..%.1f z %.1f..%.1f", b[1], b[4], b[3], b[6]))
				for _, p in ipairs(parts(m)) do
					if p.CanCollide and p.Transparency < 1 then
						solids[#solids + 1] = { name = m.Name, box = aabb(p), part = p }
					end
				end
			end
		end
		inside:report()
		local zones = {}
		for _, def in ipairs(TC.Stations) do
			if def.Slot and typeof(def.Slot.Pad) == "CFrame" then
				local c = (plotCF * def.Slot.Pad).Position
				zones[#zones + 1] = { name = "pad " .. def.Id, box = { c.X - 1.6, c.Y + 0.7, c.Z - 1.6, c.X + 1.6, c.Y + 5, c.Z + 1.6 } }
			end
		end
		for _, path in ipairs((TC.Layout and TC.Layout.Paths) or {}) do
			local a, b2 = plotCF * path.Start, plotCF * path.Finish
			local across = (path.Width or 4) / 2 - 0.5 -- the walkable middle of the path
			local dir = (b2 - a)
			local len = dir.Magnitude
			if len > 0 then
				-- sample the centre line every 2 studs (ends included, nothing beyond them: paths meet at junctions)
				local u = dir.Unit
				local side = Vector3.new(-u.Z, 0, u.X)
				for t = 0, len, 2 do
					local c = a + u * t
					local p1 = c + side * across + u * 0.5
					local p2 = c - side * across - u * 0.5
					zones[#zones + 1] = { name = "path " .. tostring(path.Name), box = { min(p1.X, p2.X), c.Y + 0.7, min(p1.Z, p2.Z), max(p1.X, p2.X), c.Y + 5, max(p1.Z, p2.Z) } }
				end
			end
		end
		for _, z in ipairs(zones) do
			local hit = nil
			for _, s in ipairs(solids) do
				if overlap(z.box, s.box, 0.05) then
					hit = s.name .. "." .. s.part.Name
					break
				end
			end
			blocks:case(hit == nil, z.name .. " blocked by " .. tostring(hit))
		end
		blocks:report(#zones .. " zones")
		local byStation = {}
		for _, s in ipairs(solids) do
			byStation[s.name] = byStation[s.name] or {}
			table.insert(byStation[s.name], s)
		end
		local names = {}
		for n in pairs(byStation) do
			names[#names + 1] = n
		end
		table.sort(names)
		for i = 1, #names do
			for j = i + 1, #names do
				local hit = nil
				for _, a in ipairs(byStation[names[i]]) do
					for _, b in ipairs(byStation[names[j]]) do
						if overlap(a.box, b.box, 0.2) then
							hit = a.part.Name .. " / " .. b.part.Name
							break
						end
					end
					if hit then
						break
					end
				end
				apart:case(hit == nil, names[i] .. " x " .. names[j] .. ": " .. tostring(hit))
			end
		end
		apart:report()

		-- the Phase 6 A1 look (back to P4) on the whole built plot (stations, pads, paths): SmoothPlastic (Neon / Glass /
		-- ForceField for glow, glass and holograms) and blocky voxel shapes only (no Ball / Cylinder parts); kept from
		-- 6.4: parts < 4 studs cast no shadow, warm lights within Brightness 1.5 / Range 16 and no shadows; pure decor sits
		-- in NC_Detail models that block nothing and hold no prompts
		do
			local P4MAT = { [Enum.Material.SmoothPlastic] = true, [Enum.Material.Neon] = true, [Enum.Material.Glass] = true, [Enum.Material.ForceField] = true }
			local CS = game:GetService("CollectionService")
			local function exempt(p)
				local cur = p
				while cur and cur ~= home do
					if CS:HasTag(cur, "NC_StyleExempt") then
						return true
					end
					cur = cur.Parent
				end
				return false
			end
			local tMat = T.tally("home plot art (P6 A1): every visible part is SmoothPlastic, Neon, Glass or ForceField (the P4 look, no realistic textures)")
			local tSat = T.tally("home plot art (P6 A1): blocky voxel shapes only (no Ball / Cylinder parts)")
			local tShadow = T.tally("home plot art (6.4): parts under 4 studs cast no shadow")
			local tLight = T.tally("home plot art (6.4): lights are warm lanterns (Brightness <= 1.5, Range <= 16, no shadows)")
			local tDetail = T.tally("home plot art (6.4): NC_Detail decor blocks nothing and holds no prompts")
			for _, p in ipairs(parts(home)) do
				local sz = p.Size
				local dims = { sz.X, sz.Y, sz.Z }
				table.sort(dims)
				if p.Transparency < 0.99 and not exempt(p) and not p.Name:find("^Ghost") then
					tMat:case(P4MAT[p.Material] == true, p:GetFullName() .. " " .. tostring(p.Material) .. " " .. fmt(dims[3], 1))
					tSat:case(not p:IsA("Part") or p.Shape == Enum.PartType.Block, p:GetFullName() .. " " .. tostring(p:IsA("Part") and p.Shape))
				end
				if dims[3] < 4 then
					tShadow:case(p.CastShadow == false, p:GetFullName())
				end
			end
			for _, d in ipairs(home:GetDescendants()) do
				if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
					tLight:case(d.Brightness <= 1.5 and d.Range <= 16 and d.Shadows == false, d:GetFullName())
				end
				if d:IsA("Model") and CS:HasTag(d, "NC_Detail") then
					local bad = nil
					for _, x in ipairs(d:GetDescendants()) do
						if (x:IsA("BasePart") and x.CanCollide) or x:IsA("ProximityPrompt") then
							bad = x.Name
						end
					end
					tDetail:case(bad == nil, d:GetFullName() .. " " .. tostring(bad))
				end
			end
			tMat:report()
			tSat:report()
			tShadow:report()
			tLight:report()
			tDetail:report()
		end

		-- the server never moves a part (HomeFx animates on the clients) and makes no Instance per coin: coins are the
		-- plot's CoinPiles / CollectorCash attributes (TycoonService) that HomeFx draws
		local snap = {}
		for _, p in ipairs(parts(home)) do
			snap[p] = p.CFrame
		end
		local countBefore = Mock.CountDescendants(home)
		for i = 1, 12 do
			home:SetAttribute("CoinPiles", "1=" .. (i % 6) .. ";2=" .. ((i + 2) % 6) .. "F;W=5")
			home:SetAttribute("CollectorCash", i * 100)
			HB.SetGarden(spot, (i % 2 == 0) and { [2] = "cat" } or {}, open0)
			K.advance(0.25)
		end
		local moved = 0
		for p, c in pairs(snap) do
			if p.Parent and (p.CFrame.Position - c.Position).Magnitude > 1e-6 then
				moved = moved + 1
			end
		end
		T.check(moved == 0, "home plot: the server never moves a part of a home (Replication rule)", moved .. " parts moved")
		T.check(Mock.CountDescendants(home) == countBefore, "home plot: coins, piles and garden changes create no server Instance (HomeFx draws the coins)", (Mock.CountDescendants(home) - countBefore) .. " new instances")
		home:SetAttribute("CoinPiles", nil)
		home:SetAttribute("CollectorCash", nil)

		-- level 0 removes; ClearPlot empties the plot, the claim prompt stays
		HB.SetStation(spot, "DecorPodium", 0)
		T.check(home:FindFirstChild("Station_DecorPodium") == nil, "home plot: SetStation(id, 0) removes the station")
		HB.ClearPlot(spot)
		local left = 0
		for _, c in ipairs(home:GetChildren()) do
			if c.Name:sub(1, 8) == "Station_" or c.Name:sub(1, 6) == "Ghost_" then
				left = left + 1
			end
		end
		T.check(left == 0 and (not home:FindFirstChild("Pads") or #home.Pads:GetChildren() == 0) and #findAll(spotFolder, function(d)
			return d.Name == "ClaimPrompt"
		end) == 1, "home plot: ClearPlot removes every station, pad and ghost; the ClaimPrompt stays")
		HB.SetOwner(spot, nil)
		T.check(home:GetAttribute("OwnerUserId") == 0 and claim.Enabled and find(spotFolder, "ClaimGui") ~= nil, "home plot: SetOwner(nil) frees the plot (claim prompt + signpost back)")

		-- no errors / warnings from HomeBuilder during all this
		local warned = nil
		for i = outputBefore + 1, #Mock.Output do
			local o = Mock.Output[i]
			if o.kind == "warn" and o.text:find("HomeBuilder", 1, true) then
				warned = o.text
			end
		end
		T.check(warned == nil and #Mock.Errors == errorsBefore, "home plot: no errors or HomeBuilder warnings", tostring(warned))
		root:Destroy()
		Mock.RemovePlayer(owner)
		K.advance(0.5)
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local KC = _G.KC
	local S = {}
	local Players = game:GetService("Players")
	local CollectionService = game:GetService("CollectionService")
	local LocalPlayer = Players.LocalPlayer
	local advance = KC.advance

	local function moduleAt(top, rest)
		local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end

	S.client_p2home = guarded("client_p2home", function()
		local HF = KC.M.HomeFx or moduleAt("client", "Controllers/HomeFx")
		if not T.check(type(HF) == "table" and type(HF.Init) == "function", "HomeFx: client/Controllers/HomeFx.lua loads with Init") then
			return
		end
		HF.Init() -- Main.client.lua already did; a second call is a no-op
		local HB = moduleAt("server", "Services/HomeBuilder")
		local TC = moduleAt("shared", "TycoonCatalog")
		if not (HB and TC) then
			T.warn("HomeFx: HomeBuilder / TycoonCatalog missing in the client world, skipped")
			return
		end
		local outputBefore, errorsBefore = #Mock.Output, #Mock.Errors
		local stats = type(HF.Stats) == "function" and HF.Stats or function()
			return {}
		end
		local count = type(HF.Count) == "function" and HF.Count or function()
			return -1
		end
		local homes0 = count()
		-- two plots built the way the server builds them (standing in for replication): ours and a neighbour's,
		-- plus a free plot
		local root = Instance.new("Folder")
		root.Name = "SmokeHomesClient"
		root.Parent = workspace
		local function makeSpot(index, cf)
			local f = Instance.new("Folder")
			f.Name = string.format("Spot_%02d", index)
			f.Parent = root
			return { Index = index, PlotCFrame = cf, PlotSize = TC.PlotSize, Center = cf.Position, Folder = f }
		end
		local base = CFrame.new(-3000, 300, 3000)
		local mine = makeSpot(81, base)
		local theirs = makeSpot(82, base * CFrame.new(120, 0, 0))
		local free = makeSpot(83, base * CFrame.new(-120, 0, 0))
		local neighbour = Mock.AddPlayer("Neighbour", 5151, { character = false })
		advance(0.2)
		for _, sp in ipairs({ mine, theirs, free }) do
			HB.PreparePlot(sp)
		end
		local cam = workspace.CurrentCamera
		local savedCam = cam and cam.CFrame
		if cam then
			cam.CFrame = CFrame.lookAt(base.Position + Vector3.new(-30, 40, -60), base.Position)
		end
		advance(0.5)
		T.check(count() >= homes0 + 3, "HomeFx: finds every NC_Home folder (also ones added later)", tostring(homes0) .. " -> " .. tostring(count()))

		-- the free plot's claim prompt: shown while we own nothing, hidden once we own a home
		local freeClaim = HB.GetClaimPrompt and HB.GetClaimPrompt(free) or free.Folder:FindFirstChild("ClaimPrompt", true)
		T.check(freeClaim ~= nil and freeClaim.Enabled, "HomeFx: a free plot's Claim Home prompt is usable while the local player owns no home")

		local function buildHome(spot, owner, stations)
			HB.SetOwner(spot, owner)
			local home = { Stations = stations, Prestige = 1 }
			HB.BuildHome(spot, home)
			HB.SetPads(spot, TC.AvailablePads(home))
		end
		local stations = { Press1 = 4, House = 1, Garden = 2, Kitchen = 1, Gym = 2, FusionMachine = 1, DecorFence = 1 }
		LocalPlayer:SetAttribute("Cash", 0) -- broke while the pads arrive (and pop in)
		buildHome(mine, LocalPlayer, stations)
		buildHome(theirs, neighbour, stations)
		advance(2.0)
		local mineHome, theirHome = mine.Folder.Home, theirs.Folder.Home
		T.check(freeClaim == nil or not freeClaim.Enabled, "HomeFx: ...and the other plots' Claim Home prompts are disabled locally once it owns one (one home per player)")
		Mock.AdvanceUntil(function()
			return (tonumber(stats().Pops) or 0) == 0
		end, 15)
		local dimmed, priced = 0, 0
		for _, m in ipairs(mineHome.Pads:GetChildren()) do
			local locked = m:GetAttribute("Locked")
			local glow = m:FindFirstChild("Glow")
			if glow and (locked == nil or locked == "") and (tonumber(m:GetAttribute("Price")) or 0) > 0 then
				priced = priced + 1
				if glow.Transparency >= 0.55 then
					dimmed = dimmed + 1
				end
			end
		end
		T.check(priced > 0 and dimmed == priced, "HomeFx: pads that arrive (and pop in) while Cash cannot pay them settle dimmed", dimmed .. " of " .. priced)

		-- owner-only prompts and signs
		local function prompts(home, names)
			return findAll(home, function(d)
				return d:IsA("ProximityPrompt") and names[d.Name]
			end)
		end
		local ownerOnly = { BuyPrompt = true, GardenSpotPrompt = true, FusionPrompt = true }
		local theirPrompts = prompts(theirHome, ownerOnly)
		local enabledTheirs = 0
		for _, p in ipairs(theirPrompts) do
			if p.Enabled then
				enabledTheirs = enabledTheirs + 1
			end
		end
		T.check(#theirPrompts >= 5 and enabledTheirs == 0, "HomeFx: every BuyPrompt / GardenSpotPrompt / FusionPrompt of another player's home is disabled on this client",
			enabledTheirs .. " of " .. #theirPrompts .. " still enabled")
		local theirSigns = findAll(theirHome, function(d)
			return d:IsA("BillboardGui") and d.Name == "PadSign"
		end)
		local shownSigns = 0
		for _, g in ipairs(theirSigns) do
			if g.Enabled then
				shownSigns = shownSigns + 1
			end
		end
		T.check(#theirSigns > 0 and shownSigns == 0, "HomeFx: ...and its pad signs are hidden (only the owner sees their pads)", shownSigns .. " of " .. #theirSigns .. " shown")
		local mineOk = true
		local myPads = 0
		for _, p in ipairs(prompts(mineHome, { BuyPrompt = true })) do
			local pad = p.Parent and p.Parent.Parent
			local locked = pad and pad:GetAttribute("Locked")
			myPads = myPads + 1
			if p.Enabled ~= (locked == nil or locked == "") then
				mineOk = false
			end
		end
		local mySpot = find(mineHome, "GardenSpotPrompt", "ProximityPrompt")
		T.check(myPads > 0 and mineOk and mySpot ~= nil and mySpot.Enabled, "HomeFx: the owner's own unlocked BuyPrompts and the open GardenSpotPrompts stay enabled")
		-- the server enabling a hidden prompt again: HomeFx hides it again
		local victim = theirPrompts[1]
		if victim then
			victim.Enabled = true
			advance(0.1)
			T.check(not victim.Enabled, "HomeFx: a hidden prompt the server re-enables is hidden again")
		end
		local st = stats()
		T.check((tonumber(st.HiddenPrompts) or 0) >= #theirPrompts, "HomeFx: Stats() counts the hidden prompts", tostring(st.HiddenPrompts))

		-- the Pet Garden (Phase 5 contract 3.5, client): Cloud Cash coins follow CoinDrops, the Welcome heap, roaming pets
		local PC = moduleAt("shared", "PetCatalog")
		local HR = moduleAt("shared", "HomeRoam")
		local petId = nil
		for _, d in ipairs((PC and PC.Pets) or {}) do
			if d.Role == "Economy" and not d.EventOnly then
				petId = d.Id
				break
			end
		end
		local gdef = TC.Get("Garden")
		local seed = (LocalPlayer.UserId % 2147483646) + 1
		local function dropAt(slot, cycle)
			local pt = HR.Plan(seed, slot, cycle or 0).Poop
			return base:PointToWorldSpace(Vector3.new(pt.x, 0, pt.z))
		end
		local function gstate(folder)
			return type(HF.Garden) == "function" and HF.Garden(folder) or nil
		end
		mine.Folder:SetAttribute("GardenSlots", 3)
		mine.Folder:SetAttribute("RoamSeed", seed)
		mine.Folder:SetAttribute("RoamVersion", HR.Version)
		mine.Folder:SetAttribute("Roam", "")
		mine.Folder:SetAttribute("CoinDrops", "1=0:2;2=0:4*;W=5")
		advance(0.3)
		local g = gstate(mine.Folder)
		T.check(type(HF.Garden) == "function" and g ~= nil, "HomeFx: HomeFx.Garden(plot) tells what the client draws in a garden")
		g = g or { Heaps = {}, Coins = {}, Pets = {}, Training = {} }
		local c1, c2, hw = g.Coins["1:0"], g.Coins["2:0"], g.Heaps.W
		local function flat(a, b)
			return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
		end
		T.check(c1 ~= nil and c2 ~= nil and hw ~= nil and c1.Stage == 2 and c2.Stage == 4 and c2.Lucky and c2.Look == "GoldenCash4",
			"HomeFx: CoinDrops draws a Cloud Cash coin per drop (stage 2, a Lucky stage 4) and the Welcome-back heap",
			tostring(c1 and c1.Look) .. " / " .. tostring(c2 and c2.Look) .. " / " .. tostring(hw ~= nil))
		T.check(c1 and flat(c1.Point, dropAt(1)) < 0.05 and c2 and flat(c2.Point, dropAt(2)) < 0.05,
			"HomeFx: ...each coin lies on its HomeRoam poop point (Plan(seed, slot, cycle).Poop)")
		local wp = base:PointToWorldSpace(gdef.Slot.WelcomePile)
		T.check(hw and flat(hw.Point, wp) < 0.05, "HomeFx: ...and the Welcome-back heap at Garden.Slot.WelcomePile")
		T.check(c1 and c2 and c1.Parts == 6 and c2.Parts == 6 and hw and hw.Parts <= 60, "HomeFx: a coin is 6 TokenLook parts (no halo, no light), the Welcome-back heap <= 60",
			tostring(c1 and c1.Parts) .. ", W " .. tostring(hw and hw.Parts))
		local light = false
		for _, d in ipairs(c1 and c1.Part:GetDescendants() or {}) do
			if d:IsA("Light") then
				light = true
			end
		end
		T.check(c1 and c2 and not light and c2.Part:FindFirstChildOfClass("ParticleEmitter") ~= nil, "HomeFx: ...no light on a coin; a Lucky coin sparkles")
		local fx = workspace:FindFirstChild("ClientFx") and workspace.ClientFx:FindFirstChild("HomeFx")
		local bowls = 0
		for _, pc in ipairs(fx and fx:GetChildren() or {}) do
			if pc.Name == "Bowl" or pc.Name == "BowlFood" then
				bowls = bowls + 1
			end
		end
		T.eq(bowls, 0, "HomeFx: no client food bowls any more (the Food Bowl is HomeBuilder's)")
		local solid = 0
		for _, pc in ipairs(parts(fx)) do
			local welded = pc:FindFirstChildWhichIsA("WeldConstraint") ~= nil or pc:FindFirstChildWhichIsA("Weld") ~= nil
			if pc.CanCollide or pc.CanQuery or pc.CanTouch or not (pc.Anchored or welded) then
				solid = solid + 1
			end
		end
		T.check(solid == 0, "HomeFx: coins and heaps are anchored (or welded to an anchored root) and never collide, query or touch", solid .. " parts")
		mine.Folder:SetAttribute("CoinDrops", "1=0:4;W=5")
		advance(0.3)
		g = gstate(mine.Folder) or g
		T.check(g.Coins["1:0"] and g.Coins["1:0"].Stage == 4 and g.Coins["2:0"] == nil, "HomeFx: a drop that grows swaps its coin's look, a drop that is gone takes its coin away")
		local homeDesc = Mock.CountDescendants(mineHome)

		if petId then
			-- garden pets roam: GardenPets + Roam; a pet above GardenSlots sleeps on its closed bed
			local now = workspace:GetServerTimeNow()
			mine.Folder:SetAttribute("Roam", string.format("1=%.1f;2=%.1f;7=%.1f", now - 50, now - 61, now - 40))
			mine.Folder:SetAttribute("GardenPets", "1=" .. petId .. ";2=" .. petId .. "@Golden;7=" .. petId .. ";3=hyb:nobody")
			advance(0.6)
			g = gstate(mine.Folder) or g
			local onGround = 0
			for slot = 1, 2 do
				local e = g.Pets[slot]
				if e then
					local lo = huge
					for _, part in ipairs(parts(e.Model)) do
						if part.Transparency < 1 then
							lo = min(lo, part.Position.Y - part.Size.Y / 2)
						end
					end
					local ground = base.Position.Y + ((e.State == "Eat") and 0.2 or 0)
					if abs(lo - base.Position.Y) < 0.6 then
						onGround = onGround + 1
					end
				end
			end
			T.check(onGround == 2 and g.Pets[3] == nil and (tonumber(stats().GardenPets) or 0) == 3,
				"HomeFx: the Garden's pets (GardenPets) roam the yard standing on the ground; hybrids without a record are skipped", onGround .. " on the ground, " .. tostring(stats().GardenPets) .. " pets")
			local bx, bz = HR.BedPoint(7)
			local p7 = g.Pets[7]
			local lp7 = p7 and base:PointToObjectSpace(p7.Model:GetPivot().Position)
			T.check(p7 and p7.Sleep and p7.Zzz ~= nil and #p7.Zzz <= 6 and math.sqrt((lp7.X - bx) ^ 2 + (lp7.Z - bz) ^ 2) < 2,
				"HomeFx: a pet on a place above GardenSlots sleeps on its closed bed (a voxel Zzz)")
			T.check(g.Pets[1] and not g.Pets[1].Sleep, "HomeFx: ...the open places' pets roam")
			-- they walk: over 10 s a roaming pet moves several studs; poops pop pending coins (Stats().Poops)
			local e1 = g.Pets[1]
			local p0 = e1 and e1.Model:GetPivot()
			local moved, poops0 = 0, tonumber(stats().Poops) or 0
			for _ = 1, 260 do
				advance(0.1)
				local pv = e1 and e1.Model.Parent and e1.Model:GetPivot()
				if pv and p0 then
					moved = max(moved, flat(pv.Position, p0.Position))
				end
			end
			local poops = (tonumber(stats().Poops) or 0) - poops0
			T.check(moved > 2, "HomeFx: a roaming pet walks the yard (HomeRoam)", fmt(moved) .. " studs")
			T.check(poops >= 2 and poops <= 4, "HomeFx: each roaming pet poops once per 24 s cycle (2 pets, 26 s; the sleeper never)", poops .. " poops")
			T.check((tonumber(stats().Coins) or 0) <= 36 and (tonumber(stats().Bits) or 0) <= 16, "HomeFx: coins (<= 36) and berries / puffs (<= 16) are pooled")
			T.check((tonumber(stats().BerryFlights) or 0) >= 2, "HomeFx: the Berry Farm sends berries to the Food Bowl and the basket", tostring(stats().BerryFlights))
			-- the Training Place: pets on their mats with a pooled voxel prop of their skill
			local ends = math.floor(workspace:GetServerTimeNow()) + 130
			mine.Folder:SetAttribute("TrainingPets", "1=" .. petId .. ":Physique:" .. ends .. ";2=" .. petId .. "@Golden:Speed:" .. ends .. ";4=" .. petId .. ":Defense:" .. ends)
			advance(0.6)
			g = gstate(mine.Folder) or g
			local gym = mineHome:FindFirstChild("Station_Gym")
			local onMat, propsOk = 0, 0
			for slot = 1, 2 do
				local e = g.Training[slot]
				local att = gym and gym:FindFirstChild("Spot" .. slot, true)
				if e and att and flat(e.Model:GetPivot().Position, att.WorldPosition) < 0.6 then
					onMat = onMat + 1
				end
				if e and e.Prop and #e.Prop >= 3 and #e.Prop <= 12 then
					propsOk = propsOk + 1
				end
			end
			T.check(onMat == 2 and g.Training[4] == nil and (tonumber(stats().TrainingPets) or 0) == 2,
				"HomeFx: the Training Place's pets (TrainingPets) stand on their mats (only the mats the level has)", onMat .. " on a mat, " .. tostring(stats().TrainingPets) .. " training")
			T.check(propsOk == 2 and g.Training[1].Stat == "Physique" and g.Training[2].Stat == "Speed", "HomeFx: ...each with a voxel prop of its skill (<= 12 parts: dumbbell, treadmill)")
			local bar = g.Training[1] and g.Training[1].Prop and g.Training[1].Prop[1]
			local b0 = bar and bar.Position
			advance(0.4)
			T.check(bar and b0 and (bar.Position - b0).Magnitude > 0.02, "HomeFx: ...and the prop moves (the dumbbell goes up and down)")
			mine.Folder:SetAttribute("TrainingPets", "")
			advance(0.3)
			T.check((tonumber(stats().TrainingPets) or 0) == 0 and (tonumber(stats().Props) or 0) == 0, "HomeFx: ...and pets and props leave when the training ends")
			mine.Folder:SetAttribute("GardenPets", "")
			advance(0.3)
			local pf = workspace.ClientFx:FindFirstChild("HomePets")
			T.check((not pf or #pf:GetChildren() == 0) and (tonumber(stats().GardenPets) or 0) == 0, "HomeFx: emptying the Garden removes its pets")
			mine.Folder:SetAttribute("GardenPets", "1=" .. petId)
			advance(0.3)
		else
			T.warn("HomeFx: no Economy pet in the catalog, garden pets skipped")
		end
		-- nothing created per frame: the effect folder stays bounded, nothing added to the home
		local n1 = fx and Mock.CountDescendants(fx) or 0
		advance(6)
		local n2 = fx and Mock.CountDescendants(fx) or 0
		T.check(n2 <= 400 and abs(n2 - n1) <= 80 and Mock.CountDescendants(mineHome) == homeDesc and (tonumber(stats().CashMade) or 0) <= 36,
			"HomeFx: coins, heaps and berries are pooled client parts (nothing created per frame, nothing added to the home)", n1 .. " -> " .. n2 .. ", coins made " .. tostring(stats().CashMade))

		-- the fusion swirl turns
		local fusion = mineHome:FindFirstChild("Station_FusionMachine")
		local swirlPart = fusion and fusion:FindFirstChild("Swirl") and parts(fusion.Swirl)[1]
		local s0 = swirlPart and swirlPart.CFrame
		advance(0.5)
		T.check(swirlPart and (swirlPart.CFrame.Position - s0.Position).Magnitude > 0.01, "HomeFx: the Fusion Machine's cloud chamber swirls")

		-- pop-in: a new level assembles and ends exactly where the server built it
		local before = mineHome:FindFirstChild("Station_Kitchen")
		HB.SetStation(mine, "Kitchen", 3)
		local kitchen = mineHome:FindFirstChild("Station_Kitchen")
		local def = TC.Get("Kitchen")
		local slotCF = base * def.Slot.CFrame
		local ref = HB.BuildStationModel("Kitchen", 3)
		local refParts, kParts = parts(ref), parts(kitchen)
		advance(0.15)
		local popping = 0
		for i, p in ipairs(kParts) do
			local r = refParts[i]
			if r and (abs(p.Transparency - r.Transparency) > 0.01 or (p.Size - r.Size).Magnitude > 0.01) then
				popping = popping + 1
			end
		end
		T.check(kitchen ~= before and popping > 0, "HomeFx: a new station pops in (its blocks spring up bottom-to-top)", popping .. " of " .. #kParts .. " parts mid-pop")
		advance(2.0)
		local off = 0
		for i, p in ipairs(kParts) do
			local r = refParts[i]
			if r then
				local want = slotCF * r.CFrame
				if (p.Position - want.Position).Magnitude > 0.01 or (p.Size - r.Size).Magnitude > 0.01 or abs(p.Transparency - r.Transparency) > 0.01 then
					off = off + 1
				end
			end
		end
		T.check(#refParts == #kParts and off == 0, "HomeFx: ...and ends exactly where and how the server built it", off .. " parts off")
		ref:Destroy()

		-- the owner's pads: dim when the Cash attribute cannot pay, pulse when it can
		local function myPad()
			for _, m in ipairs(mineHome.Pads:GetChildren()) do
				local locked = m:GetAttribute("Locked")
				if (locked == nil or locked == "") and (tonumber(m:GetAttribute("Price")) or 0) > 0 then
					return m
				end
			end
			return nil
		end
		local pad = myPad()
		if pad then
			local glow = pad:FindFirstChild("Glow")
			LocalPlayer:SetAttribute("Cash", 1e12) -- whatever an earlier scenario left: rich, then broke
			advance(0.2)
			LocalPlayer:SetAttribute("Cash", 0)
			advance(0.3)
			local dim = glow and glow.Transparency
			LocalPlayer:SetAttribute("Cash", 1e12)
			local seen = {}
			for _ = 1, 10 do
				advance(0.1)
				seen[#seen + 1] = glow and glow.Transparency or 0
			end
			local lo, hi = huge, -huge
			for _, v in ipairs(seen) do
				lo, hi = min(lo, v), max(hi, v)
			end
			T.check(glow and dim >= 0.55 and hi - lo > 0.05 and lo < dim, "HomeFx: the owner's pad dims while Cash cannot pay its price and pulses once it can",
				"dim " .. fmt(dim) .. ", affordable " .. fmt(lo) .. ".." .. fmt(hi))
		else
			T.warn("HomeFx: no priced unlocked pad on the test home, affordability skipped")
		end

		-- far away: frozen, flying parts, heaps, bowls and pets put away
		if cam then
			cam.CFrame = CFrame.lookAt(base.Position + Vector3.new(0, 40, 2000), base.Position + Vector3.new(0, 0, 1900))
		end
		advance(1.5)
		local live = 0
		fx = workspace:FindFirstChild("ClientFx") and workspace.ClientFx:FindFirstChild("HomeFx")
		for _, b in ipairs(fx and fx:GetChildren() or {}) do
			if b:IsA("BasePart") or b:IsA("Model") then
				live = live + 1
			end
		end
		local headPos = headPart and headPart.Position
		advance(1.0)
		T.check(live == 0 and (not headPart or (headPart.Position - headPos).Magnitude < 1e-6), "HomeFx: homes far from the camera freeze and put their heaps, bowls and coins away", live .. " pieces left")
		if petId then
			local pf = workspace.ClientFx:FindFirstChild("HomePets")
			T.check((not pf or #pf:GetChildren() == 0) and (tonumber(stats().GardenPets) or 0) == 0, "HomeFx: ...and put their garden pets away")
		end
		if cam and savedCam then
			cam.CFrame = savedCam
		end

		-- ownership changes: the neighbour's home becomes ours (prompts come back per lock state)
		HB.SetOwner(theirs, LocalPlayer)
		advance(0.3)
		local back = 0
		local should = 0
		for _, p in ipairs(prompts(theirHome, { BuyPrompt = true })) do
			local pad2 = p.Parent and p.Parent.Parent
			local locked = pad2 and pad2:GetAttribute("Locked")
			if locked == nil or locked == "" then
				should = should + 1
				if p.Enabled then
					back = back + 1
				end
			end
		end
		T.check(should > 0 and back == should, "HomeFx: when a home becomes the local player's, its unlocked BuyPrompts come back", back .. " of " .. should)

		-- clean up: ClearPlot and removing a home are followed
		local stations0 = tonumber(stats().Stations) or 0
		HB.ClearPlot(theirs)
		advance(0.2)
		T.check((tonumber(stats().Stations) or 0) < stations0, "HomeFx: ClearPlot's removed stations are forgotten")
		local c0 = count()
		root:Destroy()
		advance(0.5)
		T.check(count() <= c0 - 3, "HomeFx: removed homes are forgotten", c0 .. " -> " .. count())
		Mock.RemovePlayer(neighbour)
		LocalPlayer:SetAttribute("Cash", nil)
		advance(0.5)
		local warned = nil
		for i = outputBefore + 1, #Mock.Output do
			local o = Mock.Output[i]
			if o.kind == "warn" and o.text:find("HomeFx", 1, true) then
				warned = o.text
			end
		end
		T.check(warned == nil and #Mock.Errors == errorsBefore, "HomeFx: no errors or warnings from HomeFx", tostring(warned))
		KC.flushErrors("client_p2home")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
