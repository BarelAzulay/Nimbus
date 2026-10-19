-- smoke_p2_visual.lua: the Phase 2 visual pass (ARCHITECTURE_V3.md ART DIRECTION, Readability + World text rules,
-- "Phase 2 build contract"). Loaded by tools/smoke.py in BOTH worlds; ARGS.context picks the half:
--   p2visual_art    (server) the Phase 5 art pass (6.4) on every station level (HomeBuilder.BuildStationModel): only
--                   WorldStyle materials and no big SmoothPlastic, muted large faces, three or more real materials per
--                   station, pure decor in NC_Detail models without prompts; the Berry Farm's berry rows (red, blue,
--                   gold, the glowing Starberry tree with its warm light at 40) by a planked barn; the Fusion Machine's
--                   contract parts (2 Pods, Chamber, OutputDome, Swirl, FusionPrompt on PromptPoint) with neon inlays,
--                   brass at 2 and shards at 3; seedlings on every closed Garden bed and a cushion under a clay roof on
--                   every open one; the Training Place's open front and mat colours; the Food Machine's berry-filled
--                   hopper, glowing button and Berry Basket; clay roofs, real walls, slate plinths and warm windows on
--                   every House tier, the Sky Castle's rose window and spires
--   p2visual_plot   (server, booted) a private test plot: the staked-out house lot (owned, no House yet: stakes, a
--                   string, planks and bricks, no collisions, <= 12 parts; gone with the House, back after a prestige
--                   reset, kept by ClearPlot while owned, never on a free plot); a locked station's ghost is a
--                   ForceField hologram (light, no collisions, no prompts, <= 12 parts); the Prestige pad's sign says
--                   what the reset buys ("Reset: x1.25 income")
--   client_p2visual (client) HomeFx shows the sign of one of the local player's LOCKED pads only up close (6 studs; the
--                   next affordable unlocked pads keep their signs from afar), roaming Garden pets at 0.85 like Training pets; the Fusion
--                   window's locked card is opaque with a teaser line, a Mix pick mark sits in the tile's top-left
--                   corner clear of the pet; the Shop's Secret roulette hint is the short one-liner
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, max, min, huge = math.abs, math.max, math.min, math.huge

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

local function named(root, name)
	local out = {}
	for _, p in ipairs(parts(root)) do
		if p.Name == name then
			out[#out + 1] = p
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

local function plainText(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("TextLabel") then
			out[#out + 1] = d.Text
		end
	end
	return table.concat(out, " | ")
end

-- model height (studs) over its visible parts
local function height(root)
	local y0, y1 = huge, -huge
	for _, p in ipairs(parts(root)) do
		if p.Transparency < 1 then
			local h = p.Size.Y / 2
			y0, y1 = min(y0, p.Position.Y - h), max(y1, p.Position.Y + h)
		end
	end
	return (y1 > y0) and (y1 - y0) or 0
end

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local K = _G.K
	local S = {}

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

	S.p2visual_art = guarded("p2visual_art", function()
		local HB = requireAt("server/Services/HomeBuilder")
		local TC = requireAt("shared/TycoonCatalog")
		local WS = requireAt("shared/WorldStyle")
		if not (type(HB) == "table" and type(HB.BuildStationModel) == "function" and type(TC) == "table") then
			T.warn("visual art: HomeBuilder.BuildStationModel or TycoonCatalog missing, skipped")
			return
		end
		local CS = game:GetService("CollectionService")
		local function count(m, name)
			return #named(m, name)
		end
		local function exempt(p, root)
			local cur = p
			while cur and cur ~= root.Parent do
				if CS:HasTag(cur, "NC_StyleExempt") then
					return true
				end
				cur = cur.Parent
			end
			return false
		end

		-- 6.4 on every station at every level: real materials, muted big faces, plinths under the big structures
		local mats = T.tally("visual art (6.4): every station level uses only WorldStyle materials, no SmoothPlastic part over 2 studs (voxel clouds aside)")
		local muted = T.tally("visual art (6.4): every large face is muted (saturation <= 0.45, opaque value 0.35..0.9; thin neon inlays and small pieces aside)")
		local varied = T.tally("visual art (6.4): every station mixes at least three real materials (no single-material toy blocks)")
		local detail = T.tally("visual art (6.4): pure decor sits in NC_Detail models (the farm's crates, the fountain's lanterns, the fence's flowers) that hold no prompts")
		for _, def in ipairs(TC.Stations) do
			if def.Kind ~= "Prestige" then
				for level = 1, def.MaxLevel do
					local m = HB.BuildStationModel(def.Id, level)
					if m then
						local seen, kinds = {}, 0
						for _, p in ipairs(parts(m)) do
							local s = p.Size
							local dims = { s.X, s.Y, s.Z }
							table.sort(dims)
							if p.Transparency < 0.99 and not exempt(p, m) then
								mats:case((WS == nil or WS.IsWorldMaterial(p.Material)) and not (p.Material == Enum.Material.SmoothPlastic and dims[3] > 2), def.Id .. " " .. level .. " " .. p.Name .. " " .. tostring(p.Material))
								if dims[2] * dims[3] > 16 and dims[1] * dims[2] * dims[3] > 8 and p.Material ~= Enum.Material.ForceField and not (p.Material == Enum.Material.Neon and dims[1] <= 0.5) then
									local _, sat, val = p.Color:ToHSV()
									muted:case(sat <= 0.451 and (p.Material == Enum.Material.Neon or p.Transparency >= 0.3 or (val >= 0.35 and val <= 0.9)), def.Id .. " " .. level .. " " .. p.Name .. string.format(" sat %.2f val %.2f", sat, val))
								end
								if not seen[p.Material] then
									seen[p.Material] = true
									kinds = kinds + 1
								end
							end
						end
						varied:case(kinds >= 3, def.Id .. " " .. level .. ": " .. kinds .. " materials")
						for _, d in ipairs(m:GetDescendants()) do
							if d:IsA("Model") and CS:HasTag(d, "NC_Detail") then
								detail:case(find(d, "GardenSpotPrompt") == nil and find(d, "FusionPrompt") == nil and d:FindFirstChildWhichIsA("ProximityPrompt", true) == nil, def.Id .. " " .. level .. " " .. d.Name)
							end
						end
						m:Destroy()
					end
				end
			end
		end
		mats:report()
		muted:report()
		varied:report()
		local function hasDetail(id, level, name)
			local m = HB.BuildStationModel(id, level)
			local ok = false
			for _, d in ipairs(m and m:GetDescendants() or {}) do
				if d:IsA("Model") and d.Name == name and CS:HasTag(d, "NC_Detail") then
					ok = true
				end
			end
			if m then
				m:Destroy()
			end
			return ok
		end
		detail:case(hasDetail("Press1", 20, "Crates") and hasDetail("DecorFountain", 2, "Lanterns") and hasDetail("DecorFence", 1, "Flowers"), "crates / lanterns / flowers tagged")
		detail:report()

		-- the Berry Farm reads at a glance: red berries in the front row, blue ones in the middle, gold vines at the back,
		-- the Starberry tree glowing at 38-40 (a warm light at 40), the barn and its crates at the south end
		local farm = T.tally("visual art: the Berry Farm shows its berries (red L1-10, + blue L11-22, + gold L23-37, the glowing Starberry tree L38-40) by a red barn")
		local function berryColours(m)
			local red, blue, gold = 0, 0, 0
			for _, p in ipairs(parts(m)) do
				if p.Name == "Berry" then
					if p.Color.R > p.Color.B then
						red = red + 1
					else
						blue = blue + 1
					end
				elseif p.Name == "GoldBerry" then
					gold = gold + 1
				end
			end
			return red, blue, gold
		end
		for _, case in ipairs({ { 5, true, false, false }, { 15, true, true, false }, { 30, true, true, true }, { 40, true, true, true } }) do
			local m = HB.BuildStationModel("Press1", case[1])
			local red, blue, gold = berryColours(m)
			local barn = m and find(m, "Barn", "BasePart")
			local stars = count(m, "Starberry")
			local glow = m and find(m, "Starberry") and m:FindFirstChildWhichIsA("PointLight", true)
			local okTree = (case[1] >= 38) == (stars > 0) and ((case[1] < 40) or (glow ~= nil and glow.Brightness <= 1.5 and glow.Range <= 16))
			farm:case((red > 0) == case[2] and (blue > 0) == case[3] and (gold > 0) == case[4] and barn ~= nil and barn.Material == Enum.Material.WoodPlanks and okTree,
				"level " .. case[1] .. ": red " .. red .. " blue " .. blue .. " gold " .. gold .. " stars " .. stars)
			if m then
				m:Destroy()
			end
		end
		farm:report()

		-- the Fusion Machine at every level
		local fusion = T.tally("visual art: the Fusion Machine keeps its contract parts at every level (2 Pods, Chamber, OutputDome, Swirl >= 3 parts, FusionPrompt on a PromptPoint) with neon inlays, brass from level 2, shards at 3")
		for level = 1, TC.Get("FusionMachine").MaxLevel do
			local m = HB.BuildStationModel("FusionMachine", level)
			local swirl = m and m:FindFirstChild("Swirl")
			local prompt = m and find(m, "FusionPrompt", "ProximityPrompt")
			local inlays = m and count(m, "Inlay") + count(m, "ChamberInlay") or 0
			local brass = m and find(m, "Lantern") ~= nil
			fusion:case(m and count(m, "Pod") == 2 and find(m, "Chamber") and find(m, "OutputDome") and swirl and #parts(swirl) >= 3 and prompt and prompt.Parent.Name == "PromptPoint"
				and inlays >= 3 and (level < 2 or brass) and (level < 3 or count(m, "Shard") == 2) and #parts(m) <= 90, "level " .. level)
			if m then
				m:Destroy()
			end
		end
		fusion:report()

		-- every closed garden bed carries a seedling; open beds a cushion under a little clay roof
		local garden = T.tally("visual art: every closed Pet Garden bed carries a seedling (Stem + Sprout), every open bed a cushion under a clay roof (open counts 3 / 7 / 12)")
		for _, level in ipairs({ 1, 5, 8 }) do
			for _, open in ipairs({ 3, 7, 12 }) do
				local m = HB.BuildStationModel("Garden", level, nil, open)
				local roofs = 0
				for _, p in ipairs(named(m, "BedRoof")) do
					if p.Material == Enum.Material.ClayRoofTiles then
						roofs = roofs + 1
					end
				end
				garden:case(m and count(m, "Stem") == 12 - open and count(m, "Sprout") == 12 - open and count(m, "Cushion") == open and roofs == open,
					"level " .. level .. " open " .. open .. ": " .. count(m, "Stem") .. " stems, " .. roofs .. " roofs")
				if m then
					m:Destroy()
				end
			end
		end
		garden:report()

		-- the Training Place keeps its front open and gives every mat its own colour
		local train = T.tally("visual art: the Training Place keeps its front open (nothing over knee height in front of the mats) and every mat has its own colour")
		for level = 1, TC.Get("Gym").MaxLevel do
			local m = HB.BuildStationModel("Gym", level)
			local blocking, colours, dup = nil, {}, false
			for _, p in ipairs(parts(m)) do
				if p.Position.Z < -1.4 and p.Position.Y + p.Size.Y / 2 > 1.4 and p.Transparency < 1 then
					blocking = p.Name
				end
				if p.Name == "Mat" then
					local key = p.Color:ToHex()
					if colours[key] then
						dup = true
					end
					colours[key] = true
				end
			end
			train:case(m and blocking == nil and not dup, "level " .. level .. ": " .. tostring(blocking))
			if m then
				m:Destroy()
			end
		end
		train:report()

		-- the Food Machine's glass hopper is full of berries and its FEED button glows
		local machine = HB.BuildStationModel("Kitchen", 3)
		if machine then
			local hopper = find(machine, "Hopper", "BasePart")
			local inside, lit = 0, 0
			for _, p in ipairs(parts(machine)) do
				if hopper and p ~= hopper and p.Name == "HopperBerries" and math.abs(p.Position.X - hopper.Position.X) < hopper.Size.X / 2 and math.abs(p.Position.Y - hopper.Position.Y) < hopper.Size.Y / 2 then
					inside = inside + 1
				end
				if p.Name == "Button" and p.Material == Enum.Material.Neon then
					lit = lit + 1
				end
			end
			T.check(hopper ~= nil and inside >= 2 and lit >= 1 and find(machine, "Basket") ~= nil, "visual art: the Food Machine's glass hopper is full of berries, its FEED button glows and the Berry Basket stands by it", inside .. " berry layers inside, " .. lit .. " neon")
			machine:Destroy()
		end

		-- the houses: real roofs and walls; the Sky Castle has its rose window and tiled spires
		local houses = T.tally("visual art: every House tier has ClayRoofTiles roofs, Brick / WoodPlanks / Marble walls on a Slate plinth and warm-glass windows")
		for level = 1, 4 do
			local m = HB.BuildStationModel("House", level)
			local roof, wall, plinth, windows = 0, 0, 0, 0
			for _, p in ipairs(parts(m)) do
				if p.Material == Enum.Material.ClayRoofTiles then
					roof = roof + 1
				elseif p.Material == Enum.Material.Brick or p.Material == Enum.Material.WoodPlanks or p.Material == Enum.Material.Marble then
					wall = wall + 1
				end
				if p.Name == "Plinth" and p.Material == Enum.Material.Slate then
					plinth = plinth + 1
				end
				if p.Name == "Window" and p.Material == Enum.Material.Glass then
					windows = windows + 1
				end
			end
			houses:case(roof >= 2 and wall >= 3 and plinth >= 1 and windows >= 3, "tier " .. level .. ": roof " .. roof .. ", walls " .. wall .. ", windows " .. windows)
			if level == 4 then
				T.check(find(m, "RoseWindow") ~= nil and count(m, "Spire") >= 20 and #parts(m) <= 150, "visual art: the Sky Castle has a rose window over its gate and tiled spires on its towers (within its 150 parts)", #parts(m) .. " parts")
			end
			if m then
				m:Destroy()
			end
		end
		houses:report()
	end)

	S.p2visual_plot = guarded("p2visual_plot", function()
		local HB = requireAt("server/Services/HomeBuilder")
		local TC = requireAt("shared/TycoonCatalog")
		if not (type(HB) == "table" and type(TC) == "table") then
			T.warn("visual plot: HomeBuilder or TycoonCatalog missing, skipped")
			return
		end
		local root = Instance.new("Folder")
		root.Name = "SmokeVisualHomes"
		root.Parent = workspace
		local spotFolder = Instance.new("Folder")
		spotFolder.Name = "Spot_93"
		spotFolder.Parent = root
		local plotCF = CFrame.new(-4000, 300, -4000) * CFrame.Angles(0, math.rad(-90), 0)
		local spot = { Index = 93, PlotCFrame = plotCF, PlotSize = TC.PlotSize, Center = plotCF.Position, Folder = spotFolder }
		local home = HB.PreparePlot(spot)
		if not T.check(typeof(home) == "Instance", "visual plot: PreparePlot makes a test plot") then
			root:Destroy()
			return
		end
		T.check(home:FindFirstChild("HouseLot") == nil, "visual plot: a free plot has no house lot (the lobby's part budget)")
		local owner = Mock.AddPlayer("VisualSmoke", 963777)
		K.advance(0.5)
		HB.SetOwner(spot, owner)
		local lot = home:FindFirstChild("HouseLot")
		local solid = false
		for _, p in ipairs(parts(lot)) do
			if p.CanCollide or p.CanTouch or p.CanQuery then
				solid = true
			end
		end
		T.check(lot ~= nil and #parts(lot) > 0 and #parts(lot) <= 12 and not solid and #named(lot, "Stake") == 4 and #named(lot, "String") == 4,
			"visual plot: a claimed plot without a House shows the staked-out house lot (4 stakes, a string, planks, bricks; <= 12 parts, no collisions)",
			lot and (#parts(lot) .. " parts") or "none")
		if lot then
			-- the lot sits on the House slot
			local slot = plotCF * TC.Get("House").Slot.CFrame
			local c = Vector3.new(0, 0, 0)
			local n = 0
			for _, p in ipairs(named(lot, "Stake")) do
				c = c + p.Position
				n = n + 1
			end
			c = c / max(1, n)
			local loc = slot:PointToObjectSpace(c)
			T.check(abs(loc.X) < 2 and abs(loc.Z) < 4, "visual plot: ...where the house will stand (the House slot)", string.format("%.1f, %.1f", loc.X, loc.Z))
		end
		HB.SetStation(spot, "Press1", 1)
		T.check(home:FindFirstChild("HouseLot") ~= nil, "visual plot: other stations (the Berry Farm) leave the lot alone")
		HB.SetStation(spot, "House", 1)
		T.check(home:FindFirstChild("HouseLot") == nil, "visual plot: building the House clears the lot")
		HB.SetStation(spot, "House", 0)
		T.check(home:FindFirstChild("HouseLot") ~= nil, "visual plot: the lot is back when the House resets (a prestige)")
		HB.ClearPlot(spot)
		T.check(home:FindFirstChild("HouseLot") ~= nil, "visual plot: ClearPlot keeps the lot while the plot is owned (like the paths)")

		-- a ghost for a station that unlocks later: a ForceField hologram
		local fusionPad = nil
		for _, pad in ipairs(TC.AvailablePads({ Stations = { Press1 = 3, House = 1, Garden = 1, Kitchen = 1 }, Prestige = 0 })) do
			if pad.StationId == "FusionMachine" then
				fusionPad = pad
			end
		end
		if fusionPad and fusionPad.Locked then
			HB.SetPads(spot, { fusionPad })
			local ghost = home:FindFirstChild("Ghost_FusionMachine")
			local holo, bad = 0, nil
			for _, p in ipairs(parts(ghost)) do
				if p.Material == Enum.Material.ForceField and p.Transparency < 0.9 and (p.Color.R + p.Color.G + p.Color.B) > 1.2 then
					holo = holo + 1
				end
				if p.CanCollide or p.CanQuery or p.CanTouch then
					bad = p.Name
				end
			end
			T.check(ghost ~= nil and holo == #parts(ghost) and holo > 0 and holo <= 12 and bad == nil and find(ghost, "BuyPrompt") == nil,
				"visual plot: a station that unlocks later shows a light ForceField hologram (no collisions, no prompts, <= 12 parts)", ghost and (holo .. " of " .. #parts(ghost)) or "no ghost")
		else
			T.warn("visual plot: the Fusion Machine pad is not locked in the test home, ghost check skipped")
		end

		-- the Prestige pad says what the reset buys
		local prestigePad = {
			StationId = "Prestige", Prestige = true, NextLevel = 1, Level = 0, MaxLevel = 1, Price = 0,
			Title = "Prestige 1", Name = "Prestige", Kind = "Prestige", LevelText = "0 -> 1", Icon = "*",
		}
		HB.SetPads(spot, { prestigePad })
		local pad = home:FindFirstChild("Pads") and home.Pads:FindFirstChild("Pad_Prestige")
		local sign = pad and find(pad, "PadSign", "BillboardGui")
		local text = sign and plainText(sign) or ""
		local mult = (type(TC.Prestige) == "table" and tonumber(TC.Prestige.IncomeMultiplier)) or 1.25
		local want = "x" .. (string.format("%.2f", mult):gsub("0+$", ""):gsub("%.$", ""))
		T.check(text:find("Prestige 1", 1, true) ~= nil and text:find(want, 1, true) ~= nil and text:find("income", 1, true) ~= nil,
			"visual plot: the Prestige pad's sign says what the reset buys ('Reset: " .. want .. " income')", text)

		HB.SetOwner(spot, nil)
		T.check(home:FindFirstChild("HouseLot") == nil, "visual plot: freeing the plot removes the lot")
		root:Destroy()
		Mock.RemovePlayer(owner)
		K.advance(0.2)
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
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local LocalPlayer = Players.LocalPlayer
	local advance = KC and KC.advance or function(s)
		Mock.Advance(s)
	end

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

	local function toClient(name, ...)
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local remote = remotes and remotes:FindFirstChild(name)
		if remote then
			Mock.ToClient(remote, ...)
		end
	end

	local function snapshot(prestige, fusion)
		return {
			Tokens = 12450,
			Pets = { pebble_pup = 3, honey_bunny = 1, pip_penguin = 1, mallow_kitten = 1, maple_fox = 1, cloudy_dragon = 1 },
			Equipped = { "cloudy_dragon" },
			Items = {},
			Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
			Discovered = { pebble_pup = true, honey_bunny = true, pip_penguin = true },
			IndexClaimed = {},
			Tutorial = { Step = 15, Done = true, Gifted = true },
			Cash = 48250, Gems = 1820,
			Home = { Level = 20, Prestige = prestige, Stations = { Press1 = 5, Collector = 2, House = 2, Kitchen = 1, FusionMachine = fusion }, Garden = {}, Gym = {}, CollectorCash = 0 },
			Food = {},
			Tiers = {},
			Hybrids = {},
			PetLevels = {},
		}
	end

	S.client_p2visual = guarded("client_p2visual", function()
		local outputBefore, errorsBefore = #Mock.Output, #Mock.Errors
		local HF = (KC and KC.M and KC.M.HomeFx) or moduleAt("client", "Controllers/HomeFx")
		local HB = moduleAt("server", "Services/HomeBuilder")
		local TC = moduleAt("shared", "TycoonCatalog")

		-- HomeFx: the local player's locked pads show their sign only up close
		if HF and HB and TC then
			HF.Init()
			local root = Instance.new("Folder")
			root.Name = "SmokeVisualClient"
			root.Parent = workspace
			local base = CFrame.new(3000, 300, -3000)
			local folder = Instance.new("Folder")
			folder.Name = "Spot_86"
			folder.Parent = root
			local spot = { Index = 86, PlotCFrame = base, PlotSize = TC.PlotSize, Center = base.Position, Folder = folder }
			HB.PreparePlot(spot)
			HB.SetOwner(spot, LocalPlayer)
			local state = { Stations = { Press1 = 6, Press2 = 3, Collector = 2, House = 1, Garden = 2, Kitchen = 1, Gym = 1 }, Prestige = 0 }
			HB.BuildHome(spot, state)
			HB.SetPads(spot, TC.AvailablePads(state))
			HB.SetStation(spot, "Garden", 2)
			HB.SetStation(spot, "Gym", 1)
			local petId = "pebble_pup"
			folder:SetAttribute("GardenPets", "1=" .. petId)
			folder:SetAttribute("TrainingPets", "1=" .. petId .. ":Ability:" .. tostring(math.floor(workspace:GetServerTimeNow()) + 300))
			local character = LocalPlayer.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			local savedHrp = hrp and hrp.CFrame
			local savedAnchored = hrp and hrp.Anchored
			if hrp then
				hrp.Anchored = true -- stand still where the test puts the player (no falling off the test plot)
			end
			local cam = workspace.CurrentCamera
			local savedCam = cam and cam.CFrame
			local function standAt(pos)
				if hrp then
					hrp.CFrame = CFrame.new(pos)
				end
				if cam then
					cam.CFrame = CFrame.lookAt(pos + Vector3.new(0, 20, -30), pos)
				end
			end
			-- far away: at the gate of the plot looking in from the street (the yard's far corner is > 60 studs off)
			standAt(base * Vector3.new(0, 4, -TC.PlotSize / 2 - 6))
			advance(1.0)
			local signs = {}
			for _, d in ipairs(folder:GetDescendants()) do
				if d:IsA("BillboardGui") and d.Name == "PadSign" then
					local pad = d:FindFirstAncestorWhichIsA("Model")
					while pad and pad:GetAttribute("StationId") == nil do
						pad = pad.Parent and pad.Parent:FindFirstAncestorWhichIsA("Model")
					end
					if pad then
						signs[#signs + 1] = { Gui = d, Pad = pad, Locked = (pad:GetAttribute("Locked") or "") ~= "" }
					end
				end
			end
			local focus = hrp and hrp.Position or (cam and cam.CFrame.Position)
			local farLocked, farLockedShown, unlockedShown, unlocked = 0, 0, 0, 0
			-- (HomeFx also lays the signs out on the screen, World text rule: an unlocked pad's sign may wait while a
			-- nearer one takes its place, smoke_p2_fix_client.lua; it is never hidden for being far or locked)
			-- (Phase 5 3.3: an open pad TycoonCatalog.SignedPads did not pick is "Unsigned": only the next affordable
			-- pads carry a sign)
			local layoutOnly = { Shown = true, Crowded = true, Away = true, Pending = true, Unsigned = true }
			local laidOut, signed = 0, 0
			local nearest, nearestD = nil, huge
			for _, s in ipairs(signs) do
				local anchor = s.Gui.Adornee or s.Gui.Parent
				local d = (anchor.Position - focus).Magnitude
				if s.Locked then
					if d > 40 then
						farLocked = farLocked + 1
						if s.Gui.Enabled then
							farLockedShown = farLockedShown + 1
						end
					end
					if d > 40 and d < nearestD then
						nearest, nearestD = s, d
					end
				else
					unlocked = unlocked + 1
					if s.Gui.Enabled then
						unlockedShown = unlockedShown + 1
					end
					local why = type(HF.SignState) == "function" and HF.SignState(s.Gui) or nil
					if (why == nil and s.Gui.Enabled) or layoutOnly[why] then
						laidOut = laidOut + 1
					end
					if why ~= "Unsigned" then
						signed = signed + 1
					end
				end
			end
			T.check(farLocked > 0 and farLockedShown == 0, "HomeFx: the local player's locked pads keep their lock signs hidden from afar (the yard shows what can be bought now)",
				farLockedShown .. " of " .. farLocked .. " far locked signs shown")
			T.check(unlocked > 0 and signed >= 1 and signed <= 4 and laidOut == unlocked, "HomeFx: ...while the next affordable unlocked pads (SignedPads) keep their signs, the rest 'Unsigned' (only the layout holds signed ones back)",
				unlockedShown .. " shown, " .. signed .. " signed, " .. laidOut .. " of " .. unlocked .. " accounted")
			if nearest then
				local anchor = nearest.Gui.Adornee or nearest.Gui.Parent
				standAt(anchor.Position + Vector3.new(2, 1, 2))
				advance(0.6)
				T.check(nearest.Gui.Enabled, "HomeFx: walking up to a locked pad (within 6 studs) shows its sign (the lock reason)")
				standAt(anchor.Position + Vector3.new(80, 3, 80))
				advance(0.6)
				T.check(not nearest.Gui.Enabled, "HomeFx: ...and walking away hides it again")
			end
			-- garden pets stand bigger than training pets (5 studs between cushions, 3 between mats)
			standAt(base * Vector3.new(0, 4, -10))
			advance(1.5)
			local pets = workspace:FindFirstChild("ClientFx") and workspace.ClientFx:FindFirstChild("HomePets")
			local gardenH, gymH = 0, 0
			for _, m in ipairs(pets and pets:GetChildren() or {}) do
				if m:GetAttribute("PetKey") == petId then
					if m.Name == "GardenPet" then
						gardenH = max(gardenH, height(m))
					elseif m.Name == "TrainingPet" then
						gymH = max(gymH, height(m))
					end
				end
			end
			T.check(gardenH > 0 and gymH > 0 and math.abs(gardenH / gymH - 1) < 0.08, "HomeFx: roaming Garden pets and Training Place pets both stand at 0.85 scale (K.ROAM_SCALE)",
				string.format("garden %.2f, training %.2f", gardenH, gymH))
			if hrp and savedHrp then
				hrp.CFrame = savedHrp
				hrp.Anchored = savedAnchored
			end
			if cam and savedCam then
				cam.CFrame = savedCam
			end
			root:Destroy()
			advance(0.3)
		else
			T.warn("visual client: HomeFx / HomeBuilder / TycoonCatalog missing, HomeFx checks skipped")
		end

		-- the Fusion window
		local FC = (KC and KC.M and KC.M.FusionController) or moduleAt("client", "Controllers/FusionController")
		if FC and type(FC.Open) == "function" then
			LocalPlayer:SetAttribute("InMatch", false)
			toClient("ProfileSync", snapshot(0, 0))
			advance(0.4)
			FC.Open("Upgrade", {})
			advance(0.6)
			local window = pg() and find(pg(), "Window_Fusion")
			local locked = window and find(window, "Locked")
			local sub = locked and locked:FindFirstChild("Sub")
			T.check(locked ~= nil and locked.Visible and locked.BackgroundTransparency == 0 and sub ~= nil and sub.Visible and sub.Text ~= "",
				"Fusion window: before the machine, an opaque locked card (nothing of the preview shows through) with a teaser line")
			FC.Close()
			advance(0.3)
			toClient("ProfileSync", snapshot(1, 1))
			advance(0.4)
			FC.Open("Mix", {})
			advance(0.4)
			if type(FC.Select) == "function" then
				FC.Select("pip_penguin", "honey_bunny")
			end
			advance(0.6)
			local marks = {}
			for _, d in ipairs(window and window:GetDescendants() or {}) do
				if d.Name == "Mark" and d:IsA("TextLabel") and d.Visible then
					marks[#marks + 1] = d
				end
			end
			local cornerOk = #marks >= 1
			for _, mark in ipairs(marks) do
				local tile = mark.Parent
				local view = tile and tile:FindFirstChild("View")
				local mp, ms = mark.AbsolutePosition, mark.AbsoluteSize
				local tp = tile.AbsolutePosition
				local inCorner = mp.X - tp.X <= 12 and mp.Y - tp.Y <= 12
				local clear = true
				if view then
					local c = view.AbsolutePosition + view.AbsoluteSize / 2
					clear = not (c.X >= mp.X and c.X <= mp.X + ms.X and c.Y >= mp.Y and c.Y <= mp.Y + ms.Y)
				end
				if not (inCorner and clear) then
					cornerOk = false
				end
			end
			T.check(cornerOk, "Fusion window: the Mix pick marks (1 = Body, 2 = Style) sit in the tile's top-left corner, clear of the pet", #marks .. " marks")
			FC.Close()
			advance(0.3)
		else
			T.warn("visual client: FusionController missing, Fusion window checks skipped")
		end

		-- the Shop's Secret roulette hint: the short one-liner
		local MC = (KC and KC.M and KC.M.MenuController) or moduleAt("client", "Controllers/MenuController")
		if MC and type(MC.Open) == "function" then
			local restricted = LocalPlayer:GetAttribute("PaidRandomItemsRestricted")
			LocalPlayer:SetAttribute("PaidRandomItemsRestricted", false) -- GemService: gem roulettes allowed here
			LocalPlayer:SetAttribute("Gems", 99999)
			toClient("ProfileSync", snapshot(1, 1))
			advance(0.3)
			MC.Open("Shop", { Tab = "Gems" })
			advance(0.8)
			local card = pg() and find(pg(), "GemRoulette_Secret")
			local hint = card and find(card, "Hint", "TextLabel")
			if card and card.Visible and hint then
				T.check(hint.Text == "" or (#hint.Text <= 32 and hint.Text:find("Mythic or Secret", 1, true) ~= nil) or hint.Text:find("closed", 1, true) ~= nil or hint.Text:find("Need", 1, true) ~= nil,
					"Shop Gems tab: the Secret roulette's hint is the short one-liner (no orphan word on a second line)", hint.Text)
			else
				T.info("Shop Gems tab: the Secret roulette card is not shown here (policy / config), hint check skipped")
			end
			if type(MC.Close) == "function" then
				MC.Close()
			end
			LocalPlayer:SetAttribute("Gems", nil)
			LocalPlayer:SetAttribute("PaidRandomItemsRestricted", restricted)
			advance(0.3)
		end

		local warned = nil
		for i = outputBefore + 1, #Mock.Output do
			local o = Mock.Output[i]
			if o.kind == "warn" and (o.text:find("HomeFx", 1, true) or o.text:find("FusionController", 1, true)) then
				warned = o.text
			end
		end
		T.check(warned == nil and #Mock.Errors == errorsBefore, "visual client: no errors or warnings from HomeFx / FusionController", tostring(warned))
		if KC and KC.flushErrors then
			KC.flushErrors("client_p2visual")
		end
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
