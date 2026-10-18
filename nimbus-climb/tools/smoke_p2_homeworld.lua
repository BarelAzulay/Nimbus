-- smoke_p2_homeworld.lua: Phase 2 home world (ARCHITECTURE_V3.md "Phase 2 build contract": HomeBuilder + HomeFx,
-- ART DIRECTION, World text rule, Replication rule). Loaded by tools/smoke.py in BOTH worlds; ARGS.context picks the
-- half:
--   p2home_art      (server) every station at every level (HomeBuilder.BuildStationModel): clean models (Station_<Id>,
--                   anchored, no welds, only the allowed asset-free content, none of the retired machine pieces),
--                   the per-station part budgets of Phase 4 contract section 6 (Plant 45, Magnet 55, Garden 85, Food
--                   Machine 55, Training Place 90, House 150, Fusion 90, fence 60, others 80), every level differs from
--                   the one before, the four food plants (Press1..4: Berry Bush, Carrot Patch, Cloud Melons, Starfruit
--                   Tree) look different and GROW (taller, more parts, a gold planter at 10; never shorter level to
--                   level), the Coin Magnet's MagnetHead, the Food Machine's glass Hopper, the Training Place's mats
--                   (Spot1..level at Slot.Spots), the Garden's 12 places for every open count 0..12 (Spot1..12, a
--                   GardenSpotPrompt on each open place only: E, MaxActivationDistance 3, no line of sight, at the
--                   cushion's far edge >= 3.5 studs from every walk; seedling beds with a "Prestige to open" sign on
--                   the others; <= 85 parts), the Garden:<level>:<open> template cache, Cottage -> Villa -> Manor ->
--                   Sky Castle, the Fusion Machine's pods / chamber / Swirl; templates are reused
--   p2home_plot     (server, booted) a private test plot far from the lobby: PreparePlot (Home folder tagged
--                   NC_Home, the gate's ClaimPrompt "Claim Home" / "Free home" / E / SpotIndex, the FREE HOME
--                   signpost, idempotent, at most 3 parts per free plot; the lobby's free plots carry the prompt on
--                   their own gate part), SetOwner (claim prompt + signpost only while free), junk arguments never
--                   error (SetStation / SetPads / SetGarden / SetTraining), a greedy progression through
--                   TycoonCatalog.AvailablePads with SetStation + SetGarden + SetPads after every purchase (the plot
--                   never passes 950 parts at any house tier, the fully built plot stays <= 950), contract names and
--                   attributes on stations (StationId, Level, BuiltAt, Kind, same level = no-op, level 0 removes),
--                   Station_Press1 is a Berry Bush (FruitPoint), the Coin Magnet (MagnetHead, MagnetCenter), the Food
--                   Machine (Hopper, ChuteMouth / Tray / HopperTop), no retired pieces (conveyor, press heads,
--                   Collector screen / CollectPad / CollectPrompt, cooking), SetGarden (12 places, prompts on the open
--                   EMPTY places, owner-only, a new open count rebuilds the Garden, clamped to 12), the coin points and
--                   the Welcome-back pile clear of pads and station art, the Training Place's mats + SetTraining
--                   (attributes only), the Fusion Machine (Swirl, SwirlCenter, FusionPrompt), pads (Pad_<Id>,
--                   BuyPrompt "Buy" / 0.25 s / StationId / OwnerUserId, enabled only when unlocked and owned, a
--                   pixel-sized readable PadSign, unchanged pads kept, removed pads gone, a cheap ghost for "Unlocks
--                   at Prestige" / "Coming soon"), layout sanity on the built plot (stations inside the yard, no
--                   station blocks a pad or a stone path at walking height, no two stations overlap), the server never
--                   moves a part and creates no Instance per coin (Replication rule), ClearPlot (the claim prompt stays)
--   client_p2home   (client) HomeFx on plots HomeBuilder builds in the client world (standing in for replication):
--                   it finds every NC_Home, hides another player's BuyPrompts / GardenSpotPrompts / pad signs and the
--                   claim prompts of other plots while the local player owns a home (and keeps hiding a prompt the
--                   server re-enables), the owner's prompts stay; CoinPiles draws a coin heap per pile on its
--                   CoinPoint (growing with the stage, <= 40 parts, a Lucky sparkle) and the Welcome-back heap
--                   (<= 60) at Garden.Slot.WelcomePile, a pile that goes takes its heap; a bowl with the best plant's
--                   fruit in front of each open place; the Garden's pets (GardenPets) on their cushions, a place above
--                   GardenSlots asleep (Zzz), a full pile ('F') napping, eating pets dip and pop pooled coins (<= 40),
--                   the plants' fruit flies into the bowls (<= 24); the Training Place's pets (TrainingPets) on their
--                   mats with a moving voxel prop of their skill; the Coin Magnet's head turns; the Fusion swirl
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

	-- contract section 6: per-station part budgets (by kind; the fence and the Fusion Machine by id)
	local BUDGET_KIND = { Plant = 45, Magnet = 55, Garden = 85, FoodMachine = 55, Training = 90, House = 150, Fusion = 90 }
	local BUDGET_ID = { DecorFence = 60 }
	local DEFAULT_BUDGET = 80
	local function budgetOf(def)
		return BUDGET_ID[def.Id] or BUDGET_KIND[def.Kind] or DEFAULT_BUDGET
	end
	-- names of the retired Phase 2 / 3 machine pieces (presses, conveyor, Collector screen, kitchen queue)
	local RETIRED = { PressHead = true, Conveyor = true, CollectPad = true, CollectPrompt = true, CashGui = true, CashFill = true, CashLabel = true, CapLabel = true, CookPrompt = true, FeedBowl = true, Belt = true }
	-- horizontal distance from q to the centre line of a garden walk (station frame)
	local function walkLineDistance(q, w)
		local c, sz = w.Center, w.Size
		local ax, az
		if sz.X >= sz.Z then
			local h = max(0, sz.X / 2 - sz.Z / 2)
			ax, az = max(c.X - h, min(c.X + h, q.X)), c.Z
		else
			local h = max(0, sz.Z / 2 - sz.X / 2)
			ax, az = c.X, max(c.Z - h, min(c.Z + h, q.Z))
		end
		return math.sqrt((q.X - ax) ^ 2 + (q.Z - az) ^ 2)
	end

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
		T.check(HB.SetCollector == nil, "HomeBuilder: SetCollector is gone (Phase 4: the Collector screen became the Coin Magnet)")
		if type(HB.BuildStationModel) ~= "function" then
			T.warn("HomeBuilder art: no BuildStationModel extra, the per-level art checks are skipped")
			return
		end

		local clean = T.tally("station art: every station at every level builds a clean model (anchored, no welds, no scripts, no asset ids, no retired machine parts)")
		local budget = T.tally("station art: per-station part budgets (Plant 45, Magnet 55, Garden 85, Food Machine 55, Training Place 90, House 150, Fusion 90, fence 60, others 80)")
		local differ = T.tally("station art: every level looks different from the one before")
		local models = {} -- [id] = { [level] = { b = bounds, n = parts, gold = n, neon = n, sig = s } }
		local t0 = os.clock()
		local builds = 0
		for _, def in ipairs(TC.Stations) do
			if def.Kind ~= "Prestige" then
				models[def.Id] = {}
				local prev = nil
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
						clean:case(bad == nil and m.Name == "Station_" .. def.Id and #list > 0, def.Id .. " " .. level .. ": " .. tostring(bad or m.Name))
						local cap = budgetOf(def)
						budget:case(#list <= cap, def.Id .. " " .. level .. ": " .. #list .. " parts > " .. cap)
						local gold, neon = 0, 0
						for _, p in ipairs(list) do
							if colorNear(p.Color, GOLD, 24) then
								gold = gold + 1
							end
							if p.Material == Enum.Material.Neon then
								neon = neon + 1
							end
						end
						local sig = signature(m)
						models[def.Id][level] = { b = bounds(m), n = #list, gold = gold, neon = neon, sig = sig, model = m }
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
		T.info("station art: " .. builds .. " station levels sculpted in " .. fmt(os.clock() - t0, 2) .. " s")

		local function size(id, level)
			local r = models[id] and models[id][level]
			if not r then
				return nil
			end
			local b = r.b
			return b[4] - b[1], b[5] - b[2], b[6] - b[3], r
		end
		-- the four food plants (the old press slots): four looks by station id, each visibly GROWING with its level
		local looks = T.tally("station art: the four food plants are Plant art with their own fruit (Press1 Berry Bush, Press2 Carrot Patch, Press3 Cloud Melons, Press4 Starfruit Tree)")
		local FRUIT = { Press1 = "Berry", Press2 = "Carrot", Press3 = "Melon", Press4 = "Starfruit" }
		local sigs = {}
		for id, fruit in pairs(FRUIT) do
			local def = TC.Get(id)
			local m = models[id] and models[id][5] and models[id][5].model
			looks:case(def and def.Kind == "Plant" and m and m:GetAttribute("Fruit") == fruit and typeof(m:GetAttribute("FruitColor")) == "Color3",
				id .. ": kind " .. tostring(def and def.Kind) .. ", fruit " .. tostring(m and m:GetAttribute("Fruit")))
			sigs[#sigs + 1] = m and signature(m) or id
		end
		looks:report()
		local distinct = true
		for i = 1, #sigs do
			for j = i + 1, #sigs do
				if sigs[i] == sigs[j] then
					distinct = false
				end
			end
		end
		T.check(distinct, "station art: ...and the four plants look different from each other")
		local grow = T.tally("station art: a level-10 plant is taller, at least as wide and richer (more parts, a gold planter) than a level-1 plant")
		for _, id in ipairs({ "Press1", "Press2", "Press3", "Press4" }) do
			local w1, h1, _, r1 = size(id, 1)
			local w10, h10, _, r10 = size(id, 10)
			grow:case(w1 and w10 and w10 >= w1 - 0.01 and h10 >= h1 + 1.5 and r10.n > r1.n and r10.gold > r1.gold,
				string.format("%s: %sx%s -> %sx%s studs, %s -> %s parts, gold %s -> %s", id, fmt(w1, 1), fmt(h1, 1), fmt(w10, 1), fmt(h10, 1), tostring(r1 and r1.n), tostring(r10 and r10.n), tostring(r1 and r1.gold), tostring(r10 and r10.gold)))
		end
		grow:report()
		-- the plants grow step by step: never shorter from one level to the next
		local steady = T.tally("station art: plants never shrink from one level to the next")
		for _, id in ipairs({ "Press1", "Press2", "Press3", "Press4" }) do
			for level = 2, 10 do
				local _, h0 = size(id, level - 1)
				local _, h1 = size(id, level)
				steady:case(h0 and h1 and h1 >= h0 - 0.01, id .. " " .. (level - 1) .. " -> " .. level .. ": " .. fmt(h0, 1) .. " -> " .. fmt(h1, 1))
			end
		end
		steady:report()
		-- the Coin Magnet totem: a MagnetHead model (HomeFx spins it) and the MagnetCenter point
		local magnet = T.tally("station art: the Coin Magnet (Collector slot) is a totem with a MagnetHead model (a PrimaryPart for HomeFx) at every level")
		for level = 1, TC.Get("Collector").MaxLevel do
			local m = models.Collector[level] and models.Collector[level].model
			local head = m and m:FindFirstChild("MagnetHead")
			magnet:case(TC.Get("Collector").Kind == "Magnet" and head ~= nil and head:IsA("Model") and head.PrimaryPart ~= nil and #parts(head) >= 3, "level " .. level)
		end
		magnet:report()
		-- the Food Machine: the glass Hopper part PetCareService's FeedPrompt sits on
		local hopper = T.tally("station art: the Food Machine (Kitchen slot) has one glass Hopper part on top at every level (the FeedPrompt's part)")
		for level = 1, TC.Get("Kitchen").MaxLevel do
			local m = models.Kitchen[level] and models.Kitchen[level].model
			local list = {}
			for _, p in ipairs(parts(m)) do
				if p.Name == "Hopper" then
					list[#list + 1] = p
				end
			end
			local h = list[1]
			local _, height = size("Kitchen", level)
			hopper:case(TC.Get("Kitchen").Kind == "FoodMachine" and #list == 1 and h.Material == Enum.Material.Glass and h.Transparency > 0.2 and h.Transparency < 0.9 and h.Position.Y > height * 0.5,
				"level " .. level .. ": " .. #list .. " Hopper parts")
		end
		hopper:report()
		-- the Training Place: one mat per level with the Spot<i> attachments at the catalog's Spots, on the deck
		local mats = T.tally("station art: the Training Place (Gym slot) lays one mat per level with Attachments Spot1..level (attribute Slot) at Slot.Spots on the deck")
		local gymDef = TC.Get("Gym")
		for level = 1, gymDef.MaxLevel do
			local m = models.Gym[level] and models.Gym[level].model
			local found, bad = 0, nil
			for i = 1, 5 do
				local a = m and find(m, "Spot" .. i, "Attachment")
				if a then
					found = found + 1
					local want = gymDef.Slot.Spots[i]
					local at = a.WorldPosition
					if a:GetAttribute("Slot") ~= i or abs(at.X - want.X) > 0.05 or abs(at.Z - want.Z) > 0.05 or at.Y < 0.9 or at.Y > 1.6 then
						bad = "Spot" .. i .. string.format(" at %.2f, %.2f, %.2f", at.X, at.Y, at.Z)
					end
				end
			end
			local matParts = 0
			for _, p in ipairs(parts(m)) do
				if p.Name == "Mat" then
					matParts = matParts + 1
				end
			end
			mats:case(gymDef.Kind == "Training" and found == level and matParts == level and bad == nil, "level " .. level .. ": " .. found .. " spots, " .. matParts .. " mats " .. tostring(bad or ""))
		end
		mats:report()
		-- the Garden (3.3): 12 places, open = SetGarden's count (not the level), prompts on the open places only
		local gdef = TC.Get("Garden")
		local spots = gdef.Slot.Spots
		local walks = gdef.Slot.Walkable
		local garden = T.tally("station art: the Pet Garden has 12 places (Attachments Spot1..12, attribute Slot / Open) at Slot.Spots for every open count 0..12, within 85 parts")
		local prompts = T.tally("station art: every OPEN place (and only those) carries a GardenSpotPrompt 'Put a pet here' (E, MaxActivationDistance 3, no line of sight, attribute Slot) at the cushion's far edge, >= 3.5 studs from every walk")
		local closed = T.tally("station art: every place beyond the open count is a seedling bed with a small 'Prestige to open' sign (40-60 px per stud)")
		for _, level in ipairs({ 1, 4, gdef.MaxLevel }) do
			for open = 0, #spots do
				local ok, m = pcall(HB.BuildStationModel, "Garden", level, nil, open)
				if not ok or typeof(m) ~= "Instance" then
					garden:case(false, "level " .. level .. " open " .. open .. ": " .. tostring(m))
				else
					local n = #parts(m)
					local spotOk, promptN, promptBad = 0, 0, nil
					for i, want in ipairs(spots) do
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
							local cushion = spots[slot or 0]
							local nearest = huge
							for _, w in ipairs(walks) do
								if at then
									nearest = min(nearest, walkLineDistance(at, w))
								end
							end
							if not (cushion and at and slot <= open and d.ActionText == "Put a pet here" and d.KeyboardKeyCode == Enum.KeyCode.E and d.MaxActivationDistance == 3
								and d.RequiresLineOfSight == false and nearest >= 3.45 and abs((Vector3.new(at.X, 0, at.Z) - Vector3.new(cushion.X, 0, cushion.Z)).Magnitude - 1) < 0.05) then
								promptBad = "slot " .. tostring(slot) .. string.format(" %.2f from a walk", nearest)
							end
						end
					end
					local stems, sprouts, signs = 0, 0, 0
					for _, p in ipairs(parts(m)) do
						if p.Name == "Stem" then
							stems = stems + 1
						elseif p.Name == "Sprout" then
							sprouts = sprouts + 1
						elseif p.Name == "ClosedSign" then
							local gui = p:FindFirstChildWhichIsA("SurfaceGui")
							local text = gui and plainText(gui) or ""
							if gui and gui.PixelsPerStud >= 40 and gui.PixelsPerStud <= 60 and text:find("Prestige", 1, true) and text:find("to open", 1, true) then
								signs = signs + 1
							end
						end
					end
					garden:case(spotOk == #spots and n <= 85 and m:GetAttribute("Open") == open, "level " .. level .. " open " .. open .. ": " .. spotOk .. " spots, " .. n .. " parts")
					prompts:case(promptN == open and promptBad == nil, "level " .. level .. " open " .. open .. ": " .. promptN .. " prompts " .. tostring(promptBad or ""))
					closed:case(signs == #spots - open and stems == #spots - open and sprouts == #spots - open, "level " .. level .. " open " .. open .. ": " .. signs .. " signs, " .. stems .. " seedlings")
					m:Destroy()
				end
			end
		end
		garden:report()
		prompts:report()
		closed:report()
		local g3a, g3b, g7 = HB.BuildStationModel("Garden", 3, nil, 5), HB.BuildStationModel("Garden", 3, nil, 5), HB.BuildStationModel("Garden", 3, nil, 7)
		T.check(g3a and g3b and g7 and signature(g3a) == signature(g3b) and signature(g3a) ~= signature(g7),
			"station art: the Garden template is cached per Garden:<level>:<open> (same open count = the same model, another count = another model)")
		for _, g in ipairs({ g3a, g3b, g7 }) do
			g:Destroy()
		end

		-- the house: every tier clearly grander
		local tiers = T.tally("station art: the House goes Cottage -> Villa -> Manor -> Sky Castle, each tier taller and with a bigger footprint")
		for level = 2, 4 do
			local w0, h0, d0 = size("House", level - 1)
			local w1, h1, d1 = size("House", level)
			tiers:case(w0 and w1 and h1 >= h0 + 3 and w1 * d1 > w0 * d0 * 1.1, string.format("tier %d -> %d: %sx%sx%s -> %sx%sx%s", level - 1, level, fmt(w0, 0), fmt(h0, 0), fmt(d0, 0), fmt(w1, 0), fmt(h1, 0), fmt(d1, 0)))
		end
		tiers:report()
		local castle = models.House and models.House[4]
		T.check(castle and castle.gold >= 4 and castle.neon >= 3, "station art: the Sky Castle carries gold finials and lit windows", castle and ("gold " .. castle.gold .. ", neon " .. castle.neon) or "missing")
		-- other stations: bigger at the top level
		local bigger = T.tally("station art: the Coin Magnet, Garden, Food Machine, Training Place and Vault are bigger at their top level than at level 1")
		for _, id in ipairs({ "Collector", "Garden", "Kitchen", "Gym", "Vault" }) do
			local def = TC.Get(id)
			local w1, h1, d1 = size(id, 1)
			local wN, hN, dN = size(id, def.MaxLevel)
			bigger:case(w1 and wN and wN * hN * dN > w1 * h1 * d1 * 1.2, string.format("%s: %sx%sx%s -> %sx%sx%s", id, fmt(w1, 1), fmt(h1, 1), fmt(d1, 1), fmt(wN, 1), fmt(hN, 1), fmt(dN, 1)))
		end
		bigger:report()
		-- the Fusion Machine: two input pods, a glass chamber with the Swirl, an output pod, a prompt
		local fusion = models.FusionMachine and models.FusionMachine[1] and models.FusionMachine[1].model
		if T.check(fusion ~= nil, "station art: the Fusion Machine builds") then
			local glass = findAll(fusion, function(d)
				return d:IsA("BasePart") and d.Material == Enum.Material.Glass
			end)
			local pods = 0
			for _, g in ipairs(glass) do
				if g.Name == "PodGlass" then
					pods = pods + 1
				end
			end
			local swirl = fusion:FindFirstChild("Swirl")
			T.check(pods >= 3 and find(fusion, "Chamber") ~= nil, "station art: the Fusion Machine has two input pods + an output pod (glass) and a glass chamber", pods .. " pod glasses")
			T.check(swirl ~= nil and #parts(swirl) >= 3, "station art: ...with a cloud Swirl inside the chamber (HomeFx spins it)")
			local prompt = find(fusion, "FusionPrompt", "ProximityPrompt")
			T.check(prompt ~= nil and prompt.ActionText ~= "" and prompt.HoldDuration == 0, "station art: ...and a FusionPrompt that opens the Fusion window")
			local _, h1 = size("FusionMachine", 1)
			T.check(h1 and h1 >= 10, "station art: ...and it is an impressive machine (>= 10 studs tall)", fmt(h1, 1) .. " studs")
		end
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

		-- the food plants: Station_Press1 is the Berry Bush (FruitPoint for HomeFx's fruit flights)
		local bush = home:FindFirstChild("Station_Press1")
		local fp = bush and bush:GetAttribute("FruitPoint")
		T.check(bush ~= nil and bush:GetAttribute("Kind") == "Plant" and bush:GetAttribute("Fruit") == "Berry" and typeof(fp) == "Vector3"
			and (Vector3.new(fp.X, 0, fp.Z) - Vector3.new(bush:GetPivot().Position.X, 0, bush:GetPivot().Position.Z)).Magnitude < 3,
			"home plot: Station_Press1 is a Berry Bush (Kind Plant, Fruit Berry, a FruitPoint over the bush)")
		local magnetModel = home:FindFirstChild("Station_Collector")
		T.check(magnetModel ~= nil and magnetModel:GetAttribute("Kind") == "Magnet" and magnetModel:FindFirstChild("MagnetHead") ~= nil and typeof(magnetModel:GetAttribute("MagnetCenter")) == "Vector3",
			"home plot: the Collector slot holds the Coin Magnet (MagnetHead + MagnetCenter for HomeFx)")
		local machine = home:FindFirstChild("Station_Kitchen")
		local hopperPart = machine and machine:FindFirstChild("Hopper", true)
		T.check(machine ~= nil and machine:GetAttribute("Kind") == "FoodMachine" and hopperPart ~= nil and hopperPart:IsA("BasePart")
			and typeof(machine:GetAttribute("ChuteMouth")) == "Vector3" and typeof(machine:GetAttribute("Tray")) == "Vector3" and typeof(machine:GetAttribute("HopperTop")) == "Vector3",
			"home plot: the Kitchen slot holds the Food Machine with its Hopper part (PetCareService's FeedPrompt) and the ChuteMouth / Tray / HopperTop points")
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
		for i, want in ipairs(gdef.Slot.Spots) do
			local a = gmodel and find(gmodel, "Spot" .. i, "Attachment")
			if a and (gslot:PointToObjectSpace(a.WorldPosition) - Vector3.new(want.X, a.WorldPosition.Y - gslot.Position.Y, want.Z)).Magnitude < 0.05 then
				spotsOk = spotsOk + 1
			end
		end
		T.check(gmodel ~= nil and spotsOk == 12 and gmodel:GetAttribute("Open") == open0, "home plot: the Garden shows 12 places (Spot1..12 at Slot.Spots) and Open = TC.GardenSlots(home)", spotsOk .. " spots, open " .. tostring(gmodel and gmodel:GetAttribute("Open")) .. " vs " .. open0)
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

		-- the coin points and the Welcome-back pile stay clear of pads and station art (walking height)
		local clear = T.tally("home plot: the 12 coin points and the Welcome-back pile are clear of every pad and every solid station part")
		local coinSpots = {}
		for i = 1, 12 do
			local pt = TC.CoinPoint and TC.CoinPoint(i)
			if typeof(pt) == "Vector3" then
				coinSpots[#coinSpots + 1] = { name = "coin " .. i, at = gslot * pt }
			end
		end
		if typeof(gdef.Slot.WelcomePile) == "Vector3" then
			coinSpots[#coinSpots + 1] = { name = "WelcomePile", at = plotCF * gdef.Slot.WelcomePile }
		end
		local coinZones = {}
		for _, c in ipairs(coinSpots) do
			coinZones[#coinZones + 1] = { name = c.name, box = { c.at.X - 0.6, c.at.Y + 0.7, c.at.Z - 0.6, c.at.X + 0.6, c.at.Y + 3, c.at.Z + 0.6 } }
		end
		local padBoxes = {}
		for _, d in ipairs(TC.Stations) do
			if d.Slot and typeof(d.Slot.Pad) == "CFrame" then
				local c = (plotCF * d.Slot.Pad).Position
				padBoxes[#padBoxes + 1] = { name = "pad " .. d.Id, box = { c.X - 2.2, c.Y - 1, c.Z - 2.2, c.X + 2.2, c.Y + 5, c.Z + 2.2 } }
			end
		end
		local stationSolids = {}
		for _, m in ipairs(home:GetChildren()) do
			if m:IsA("Model") and m.Name:sub(1, 8) == "Station_" then
				for _, p in ipairs(parts(m)) do
					if (p.CanCollide or p.Transparency < 0.5) and p.Transparency < 1 then
						stationSolids[#stationSolids + 1] = { name = m.Name .. "." .. p.Name, box = aabb(p) }
					end
				end
			end
		end
		for _, z in ipairs(coinZones) do
			local hit = nil
			for _, pb in ipairs(padBoxes) do
				if overlap(z.box, pb.box, 0) then
					hit = pb.name
				end
			end
			for _, sp in ipairs(stationSolids) do
				if not hit and overlap(z.box, sp.box, 0.02) then
					hit = sp.name
				end
			end
			clear:case(hit == nil, z.name .. " blocked by " .. tostring(hit))
		end
		clear:report(#coinZones .. " points")

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
		local kept = HB.SetPads(spot, { { StationId = "DecorLamps", NextLevel = 2, Price = 10, Level = 1, Title = "Lanterns", LevelText = "Lv 1 -> 2" } })
		local lamp = padFolder and padFolder:FindFirstChild("Pad_DecorLamps")
		HB.SetPads(spot, { { StationId = "DecorLamps", NextLevel = 2, Price = 10, Level = 1, Title = "Lanterns", LevelText = "Lv 1 -> 2" } })
		T.check(kept and lamp ~= nil and padFolder:FindFirstChild("Pad_DecorLamps") == lamp and #padFolder:GetChildren() == 1, "home plot: SetPads keeps an unchanged pad and removes the pads that are no longer listed")
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
		local stations = { Press1 = 4, Press2 = 2, Collector = 2, House = 1, Garden = 2, Kitchen = 1, Gym = 2, FusionMachine = 1, DecorLamps = 1 }
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

		-- the Pet Garden (contract 3.2 / 3.3, client): heaps follow CoinPiles, bowls on the open places, pets eat
		local PC = moduleAt("shared", "PetCatalog")
		local petId = nil
		for _, d in ipairs((PC and PC.Pets) or {}) do
			if d.Role == "Economy" and not d.EventOnly then
				petId = d.Id
				break
			end
		end
		local garden = mineHome:FindFirstChild("Station_Garden")
		local gdef = TC.Get("Garden")
		local frame = base * gdef.Slot.CFrame
		local function pileAt(slot)
			return frame:PointToWorldSpace(Vector3.new(TC.CoinPoint(slot).X, 0, TC.CoinPoint(slot).Z))
		end
		local function gstate(folder)
			return type(HF.Garden) == "function" and HF.Garden(folder) or nil
		end
		mine.Folder:SetAttribute("GardenSlots", 3)
		mine.Folder:SetAttribute("CoinPiles", "1=2;2=5F*;W=5")
		advance(0.3)
		local g = gstate(mine.Folder)
		T.check(type(HF.Garden) == "function" and g ~= nil, "HomeFx: HomeFx.Garden(plot) tells what the client draws in a garden")
		g = g or { Heaps = {}, Bowls = {}, Pets = {}, Training = {} }
		local h1, h2, hw = g.Heaps[1], g.Heaps[2], g.Heaps.W
		local function flat(a, b)
			return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
		end
		T.check(h1 ~= nil and h2 ~= nil and hw ~= nil and h1.Stage == 2 and h2.Stage == 5, "HomeFx: CoinPiles draws a heap per pile (stage 2, stage 5) and the Welcome-back heap",
			tostring(h1 and h1.Stage) .. " / " .. tostring(h2 and h2.Stage) .. " / " .. tostring(hw ~= nil))
		T.check(h1 and flat(h1.Point, pileAt(1)) < 0.05 and h2 and flat(h2.Point, pileAt(2)) < 0.05,
			"HomeFx: ...each heap lies on its TycoonCatalog.CoinPoint (on the walk)")
		local wp = base:PointToWorldSpace(gdef.Slot.WelcomePile)
		T.check(hw and flat(hw.Point, wp) < 0.05, "HomeFx: ...and the Welcome-back heap at Garden.Slot.WelcomePile")
		T.check(h1 and h2 and hw and h1.Parts < h2.Parts and h2.Parts <= 40 and hw.Parts <= 60, "HomeFx: the heap grows with its stage (<= 40 parts, the Welcome-back heap <= 60)",
			tostring(h1 and h1.Parts) .. " < " .. tostring(h2 and h2.Parts) .. ", W " .. tostring(hw and hw.Parts))
		T.check(h2 and h2.Lucky and h1 and not h1.Lucky, "HomeFx: a Lucky coin ('*') sparkles on its heap")
		local nb = 0
		for slot, b in pairs(g.Bowls) do
			nb = nb + 1
			if slot > 3 or not (b.Dish.Parent and b.Food.Parent) then
				nb = -100
			end
		end
		T.check(nb == 3, "HomeFx: a food bowl (2 client parts) in front of each of the 3 open places", tostring(nb))
		local food = g.Bowls[1] and g.Bowls[1].Food.Color
		local carrot = mineHome:FindFirstChild("Station_Press2") and mineHome.Station_Press2:GetAttribute("FruitColor")
		T.check(food ~= nil and carrot ~= nil and (food.R - carrot.R) ^ 2 + (food.G - carrot.G) ^ 2 + (food.B - carrot.B) ^ 2 < 1e-4,
			"HomeFx: the bowls hold the fruit of the best plant built (the Carrot Patch here)")
		local solid = 0
		for _, pc in ipairs(parts(workspace.ClientFx.HomeFx)) do
			if pc.CanCollide or pc.CanQuery or pc.CanTouch or not pc.Anchored then
				solid = solid + 1
			end
		end
		T.check(solid == 0, "HomeFx: heaps, bowls and coins are anchored and never collide, query or touch", solid .. " parts")
		mine.Folder:SetAttribute("CoinPiles", "1=4;W=5")
		advance(0.3)
		g = gstate(mine.Folder) or g
		T.check(g.Heaps[1] and g.Heaps[1].Stage == 4 and g.Heaps[2] == nil, "HomeFx: a pile that grows swaps its heap, a pile that is gone takes its heap away")
		local fx = workspace:FindFirstChild("ClientFx") and workspace.ClientFx:FindFirstChild("HomeFx")
		local homeDesc = Mock.CountDescendants(mineHome)

		if petId then
			-- garden pets: GardenPets puts Low-detail pets on the cushions; a place above GardenSlots sleeps on its closed bed
			mine.Folder:SetAttribute("GardenPets", "1=" .. petId .. ";2=" .. petId .. "@Golden;7=" .. petId .. ";3=hyb:nobody")
			advance(0.6)
			g = gstate(mine.Folder) or g
			local onCushion = 0
			for slot = 1, 2 do
				local e = g.Pets[slot]
				local att = garden and garden:FindFirstChild("Spot" .. slot, true)
				if e and att then
					local pivot = e.Model:GetPivot()
					local lo = huge
					for _, part in ipairs(parts(e.Model)) do
						lo = min(lo, part.Position.Y - part.Size.Y / 2)
					end
					if flat(pivot.Position, att.WorldPosition) < 0.6 and abs(lo - att.WorldPosition.Y) < 0.5 then
						onCushion = onCushion + 1
					end
				end
			end
			T.check(onCushion == 2 and g.Pets[3] == nil and (tonumber(stats().GardenPets) or 0) == 3,
				"HomeFx: the Garden's pets (GardenPets) stand on their cushions; hybrids without a record are skipped", onCushion .. " on a cushion, " .. tostring(stats().GardenPets) .. " pets")
			T.check(g.Pets[7] and g.Pets[7].Sleep and g.Pets[7].Zzz ~= nil, "HomeFx: a pet on a place above GardenSlots sleeps on its closed bed (a voxel Zzz)")
			mine.Folder:SetAttribute("CoinPiles", "1=4;2=3F;W=5")
			advance(0.3)
			g = gstate(mine.Folder) or g
			T.check(g.Pets[2] and g.Pets[2].Sleep and g.Pets[2].Zzz ~= nil and #g.Pets[2].Zzz <= 6, "HomeFx: a full pile ('F'): its pet naps (lies down, Zzz)")
			T.check(g.Pets[1] and not g.Pets[1].Sleep, "HomeFx: ...the pets of piles that are not full keep eating")
			-- the meal rhythm: the pet dips into its bowl, a coin hops onto its pile (Stats().Drops)
			local e1 = g.Pets[1]
			local p0 = e1 and e1.Model:GetPivot()
			local moved, drops0, maxCoins = 0, tonumber(stats().Drops) or 0, 0
			for _ = 1, 100 do
				advance(0.1)
				local pv = e1 and e1.Model.Parent and e1.Model:GetPivot()
				if pv and p0 then
					moved = max(moved, (pv.Position - p0.Position).Magnitude)
				end
				maxCoins = max(maxCoins, tonumber(stats().Coins) or 0)
			end
			local drops = (tonumber(stats().Drops) or 0) - drops0
			T.check(drops >= 1 and drops <= 4, "HomeFx: every meal (8 s) an eating pet pops a coin onto its pile (napping and sleeping pets do not)", drops .. " coins in 10 s")
			T.check(moved > 0.1 and moved < 1.0, "HomeFx: ...after dipping into its bowl (a small move, back on its cushion)", fmt(moved) .. " studs")
			T.check(maxCoins >= 1 and maxCoins <= 40, "HomeFx: the flying coins are pooled parts (<= 40)", tostring(maxCoins))
			T.check((tonumber(stats().FruitFlights) or 0) >= 2, "HomeFx: the plants send their fruit into the bowls (~every 3 s per plant)", tostring(stats().FruitFlights))
			T.check((tonumber(stats().Fruit) or 0) <= 24 and (tonumber(stats().FruitPool) or 0) <= 24, "HomeFx: ...pooled fruit parts (<= 24)", tostring(stats().FruitPool))
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
		T.check(n2 <= 260 and abs(n2 - n1) <= 60 and Mock.CountDescendants(mineHome) == homeDesc and (tonumber(stats().CoinPool) or 0) <= 40,
			"HomeFx: heaps, bowls, coins and fruit are pooled client parts (nothing created per frame, nothing added to the home)", n1 .. " -> " .. n2 .. ", coin parts " .. tostring(stats().CoinPool))
		-- the Coin Magnet's head turns
		local magnet = mineHome:FindFirstChild("Station_Collector")
		local headPart = magnet and magnet:FindFirstChild("MagnetHead") and parts(magnet.MagnetHead)[1]
		local m0 = headPart and headPart.CFrame
		advance(0.5)
		T.check(headPart and m0 and (headPart.CFrame.LookVector - m0.LookVector).Magnitude > 0.01, "HomeFx: the Coin Magnet's head turns")

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
