-- smoke_p4_garden.lua: the home garden's Cloud Cash (Phase 4 contract 3.1-3.3, 5.3, 7 X1-X6 / X20, 8.1; Phase 5 contract
-- 3.5: the roaming ledger replaces the piles). Loaded by tools/smoke.py in BOTH worlds; ARGS.context picks the half:
--   SERVER (Phase 5 wave 2, tycoon+care): every scenario runs on the booted game (Main.server.lua) through TycoonService:
--   p4garden_coins   the free Pet Garden; a placed pet gets Epoch = now + SettleSeconds (Roam attribute, one decimal),
--                    its first poop >= 24 s later at HomeRoam.PoopTime, every poop worth CoinValue x PoopMeals at
--                    HomeRoam.Plan(seed, slot, cycle).Poop in the plot frame (Drops / Piles / CoinDrops "slot=cycle:stage"),
--                    berries = value x Share; a Combat pet earns 1/1.6 of an Economy pet (PetPower); RoamSeed /
--                    RoamVersion / BerryCap / IncomePerSecond / GardenPets / GardenInfo / GardenSlots / CollectorCash
--                    attributes, no CoinPiles; the invariant sum(drops) + Welcome == CollectorCash every second; 3 drops
--                    per slot then merging into the nearest; no Lucky at Garden L1, Lucky drops (x5, '*') at Garden L8;
--                    the lawn cap (PileSeconds x the pet's rate) -> the pet naps (':N<cycle>'), the bank stops, a scoop
--                    wakes it (epoch = now + the back walk); no Instance per coin; the stored stage scales the coin by
--                    LevelFactor
--   p4garden_scoop   the owner within ScoopRadius (Garden L1 8 studs, a folded Coin Magnet 9) and 10 studs vertically is
--                    paid exactly once (Cash + CollectorCash constant, CoinsScooped(player, amount), whole Cash only,
--                    the fraction stays as an unlisted drop), a second player on the lawn scoops nothing (touch or
--                    Collect), HomeAction "Collect" = scoop in range; GardenSet: the training lock with the time left,
--                    a key in a running battle, the Y8 epoch rule (the same key back within a cycle keeps its epoch, a
--                    new placement waits SettleSeconds + a cycle, 80 requests in one frame move nothing), resting keys
--                    above the open count (no epoch, no coin), LegacySlots opening places (a settle first, no backlog)
--   p4garden_ledger  exactly once across the session edges (X4 / X6): leave + rejoin -> the coins left on the lawn wait
--                    in the Welcome-back pile (W=5) and pay once (the fresh ledger staggers the epochs); the Vault's
--                    offline coins go INTO the bank with LastSeen and offline x Share berries into the basket, once;
--                    ProfileRebased rebuilds the ledger from the merged bank; a provisional profile claims nothing;
--                    a DataStore outage never loses or doubles Cash (the rejoin reads the store once the departed
--                    entry is released; a rejoin during the outage picks up the session still in memory); Prestige mid-lawn (bank + drops to 0, Garden L1
--                    kept, +1 place, LegacySlots gone, pets and berries kept, x1.25 poops), star prices / LegacyPrices;
--                    old station ids (Press2, Collector, old decor) answer "That station is now part of the ..." and
--                    build nothing; ClearCoins; the veteran welcome toast once; no Phase 5 toast for a new player
--   CLIENT (wave 3, homefx): HomeFx draws the garden from the plot attributes
--   client_p4garden_heaps  (Phase 5) the Cloud Cash coin of a drop follows CoinDrops (stage, '*' Lucky) at HomeRoam's
--                          poop point and goes with the drop; another player's coins are dimmed (no sparkles) and never
--                          move; 12 roaming pets for 30 s poop once per cycle each as pooled TokenLook coins (<= 36),
--                          unconfirmed ones fade; a visitor at another player's coin sees the hint once, at the coin
--   client_p4garden_scoop  the owner's scooped drop (bank drop + Cash rise + drop gone): coins zip from it to the owner
--                          and a pixel "+$1,234" label floats AT THE DROP (never over the head); out of reach, other
--                          players' drops and a Prestige show no zip / no label; the scoop ring only in the own
--                          yard; no ScreenGui added (nothing in the screen centre)
--   client_p4garden_cards  PetCards: own garden pets mode Garden "Lv n" + stars (GardenInfo), own training pets the
--                          purple timer counting down, others' garden pets level only (mode Other), only within 40 studs
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, floor = math.abs, math.floor

----------------------------------------------------------------------------------------------------
-- CLIENT half (wave 3, homefx): HomeFx draws the garden from the plot attributes (contract 3.2 / 3.3 / 3.9 / 6)
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local KC = _G.KC
	local CS = {}
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer
	local max, min, huge = math.max, math.min, math.huge

	local function advance(seconds)
		KC.advance(seconds)
	end

	local function moduleAt(top, rest)
		local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end

	local function flat(a, b)
		return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
	end

	local function partsOf(root)
		local out = {}
		if root and root:IsA("BasePart") then
			out[#out + 1] = root
		end
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if d:IsA("BasePart") then
				out[#out + 1] = d
			end
		end
		return out
	end

	-- a test world: two built homes (ours and a neighbour's) far from everything, the camera and the local player
	-- next to ours; returns a context table and a cleanup function
	local function setup(tag, x)
		local HF = KC.M.HomeFx or moduleAt("client", "Controllers/HomeFx")
		local HB = moduleAt("server", "Services/HomeBuilder")
		local TC = moduleAt("shared", "TycoonCatalog")
		local PC = moduleAt("shared", "PetCatalog")
		local HR = moduleAt("shared", "HomeRoam")
		if not (HF and HB and TC and PC and HR and type(HF.Garden) == "function") then
			T.fail("p4 garden client: HomeFx (with HomeFx.Garden) / HomeBuilder / TycoonCatalog / PetCatalog load in the client world")
			return nil
		end
		HF.Init()
		local ids = {}
		for _, d in ipairs(PC.Pets) do
			if d.Role == "Economy" and not d.EventOnly and #ids < 12 then
				ids[#ids + 1] = d.Id
			end
		end
		for _, d in ipairs(PC.Pets) do
			if d.Role ~= "Economy" and not d.EventOnly and #ids < 12 then
				ids[#ids + 1] = d.Id
			end
		end
		local root = Instance.new("Folder")
		root.Name = "SmokeP4Garden" .. tag
		root.Parent = workspace
		local neighbour = Mock.AddPlayer("GardenNeighbour" .. tag, 8800 + #tag, { character = false })
		local base = CFrame.new(x, 300, -7000)
		local function makeSpot(index, cf, owner)
			local f = Instance.new("Folder")
			f.Name = string.format("Spot_%02d", index)
			f.Parent = root
			local spot = { Index = index, PlotCFrame = cf, PlotSize = TC.PlotSize, Center = cf.Position, Folder = f }
			HB.PreparePlot(spot)
			HB.SetOwner(spot, owner)
			HB.BuildHome(spot, { Stations = { Press1 = 3, House = 1, Garden = 2, Kitchen = 1, Gym = 2 }, Prestige = 9 })
			if type(HB.SetGarden) == "function" then
				HB.SetGarden(spot, {}, 12)
			end
			f:SetAttribute("GardenSlots", 12)
			-- Phase 5 (3.5): the roam attributes TycoonService writes; the drops lie at HomeRoam's poop points
			local uid = owner and owner.UserId or 0
			f:SetAttribute("RoamSeed", (uid % 2147483646) + 1)
			f:SetAttribute("RoamVersion", HR and HR.Version or 1)
			f:SetAttribute("Roam", "")
			spot.Seed = (uid % 2147483646) + 1
			return spot
		end
		local mine = makeSpot(91, base, LocalPlayer)
		local theirs = makeSpot(92, base * CFrame.new(80, 0, 0), neighbour)
		local def = TC.Get("Garden")
		local frame = base * def.Slot.CFrame
		local frameTheirs = theirs.PlotCFrame * def.Slot.CFrame
		local character = LocalPlayer.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local saved = { Hrp = hrp and hrp.CFrame, Anchored = hrp and hrp.Anchored, Cam = workspace.CurrentCamera and workspace.CurrentCamera.CFrame }
		if hrp then
			hrp.Anchored = true
		end
		local ctx = {
			HF = HF, HB = HB, TC = TC, Ids = ids, Mine = mine, Theirs = theirs, Neighbour = neighbour, Hrp = hrp,
			-- Phase 5: the drop of (slot, cycle 0) lies at HomeRoam.Plan(seed, slot, 0).Poop (plot-local)
			Pile = function(slot, other)
				local spot = other and theirs or mine
				local pt = HR.Plan(spot.Seed, slot, 0).Poop
				return spot.PlotCFrame:PointToWorldSpace(Vector3.new(pt.x, 0, pt.z))
			end,
			HR = HR,
			Frame = frame,
			Gym = base * TC.Get("Gym").Slot.CFrame,
		}
		function ctx.standAt(pos)
			if hrp then
				hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
			end
			local cam = workspace.CurrentCamera
			if cam then
				cam.CFrame = CFrame.lookAt(pos + Vector3.new(0, 18, -26), pos)
			end
		end
		function ctx.g(spot)
			return HF.Garden((spot or mine).Folder) or { Heaps = {}, Coins = {}, Pets = {}, Training = {} }
		end
		local function cleanup()
			if hrp and saved.Hrp then
				hrp.CFrame = saved.Hrp
				hrp.Anchored = saved.Anchored
			end
			if workspace.CurrentCamera and saved.Cam then
				workspace.CurrentCamera.CFrame = saved.Cam
			end
			LocalPlayer:SetAttribute("Cash", nil)
			root:Destroy()
			Mock.RemovePlayer(neighbour)
			advance(0.5)
		end
		ctx.standAt(mine.PlotCFrame * def.Slot.CFrame.Position)
		advance(0.5)
		return ctx, cleanup
	end

	local function noWarnings(label, outputBefore, errorsBefore)
		local warned = nil
		for i = outputBefore + 1, #Mock.Output do
			local o = Mock.Output[i]
			if o.kind == "warn" and (o.text:find("HomeFx", 1, true) or o.text:find("PetCard", 1, true)) then
				warned = o.text
			end
		end
		T.check(warned == nil and #Mock.Errors == errorsBefore, label .. ": no errors or warnings from HomeFx", tostring(warned))
	end

	-- heaps follow CoinPiles; another player's heaps are dimmed and still; pools stay small with 12 eating pets
	-- Phase 5 (3.5): the Cloud Cash coins follow CoinDrops; another player's coins are dimmed and still; pools stay
	-- small with 12 roaming pets
	local function coinParts(c)
		local out = {}
		if c and c.Part then
			out = partsOf(c.Part)
		end
		return out
	end
	CS.client_p4garden_heaps = guarded("client_p4garden_heaps", function()
		local outputBefore, errorsBefore = #Mock.Output, #Mock.Errors
		local ctx, cleanup = setup("Heaps", 9000)
		if not ctx then
			return
		end
		local ok, err = pcall(function()
			local mine, theirs, HF = ctx.Mine, ctx.Theirs, ctx.HF
			local seq = { { "1=0:1", 1, false }, { "1=0:3", 3, false }, { "1=0:4*", 4, true } }
			local good = 0
			for _, step in ipairs(seq) do
				mine.Folder:SetAttribute("CoinDrops", step[1])
				advance(0.15)
				local c = ctx.g().Coins["1:0"]
				if c and c.Stage == step[2] and c.Lucky == step[3] and flat(c.Point, ctx.Pile(1)) < 0.05 and not c.Pending then
					good = good + 1
				end
			end
			T.check(good == #seq, "p4 garden client: the coin of a drop follows CoinDrops (stage 1 -> 3 -> 4, '*' Lucky) at HomeRoam's poop point", good .. " of " .. #seq)
			mine.Folder:SetAttribute("CoinDrops", "")
			advance(0.15)
			T.check(next(ctx.g().Coins) == nil, "p4 garden client: ...and goes when the drop is gone")
			-- another player's coins: dimmed, never moving
			theirs.Folder:SetAttribute("CoinDrops", "1=0:4*;5=0:2;W=5")
			advance(0.3)
			local tg = ctx.g(theirs)
			local tc = tg.Coins["1:0"]
			local sparkles = false
			for _, d in ipairs(tc and tc.Part:GetDescendants() or {}) do
				if d:IsA("ParticleEmitter") then
					sparkles = true
				end
			end
			local trans = huge
			for _, p in ipairs(coinParts(tc)) do
				trans = min(trans, p.Transparency)
			end
			T.check(tg.Dim and tc and tc.Dim and not sparkles and tg.Heaps.W ~= nil and trans >= 0.25, "p4 garden client: another player's coins are drawn dimmed (no Lucky sparkles) + their Welcome heap", "min transparency " .. tostring(trans))
			mine.Folder:SetAttribute("CoinDrops", "1=0:3")
			advance(0.15)
			local mc = ctx.g().Coins["1:0"]
			local mtrans = huge
			for _, p in ipairs(coinParts(mc)) do
				mtrans = min(mtrans, p.Transparency)
			end
			T.check(mc and not mc.Dim and mtrans < 0.05, "p4 garden client: ...the local player's own coins are not")
			local before = {}
			for _, p in ipairs(coinParts(tc)) do
				before[p] = p.CFrame.Position
			end
			advance(3)
			local movedParts = 0
			for p, pos in pairs(before) do
				if (p.CFrame.Position - pos).Magnitude > 1e-4 then
					movedParts = movedParts + 1
				end
			end
			T.check(next(before) ~= nil and movedParts == 0, "p4 garden client: ...and they never move", movedParts .. " parts moved")
			-- 12 roaming pets in our garden for 30 s: each poops once a cycle (24 s), coins pooled, nothing per frame
			local list = {}
			for i = 1, 12 do
				list[#list + 1] = i .. "=" .. ctx.Ids[i]
			end
			mine.Folder:SetAttribute("GardenPets", table.concat(list, ";"))
			local now = workspace:GetServerTimeNow()
			local roam = {}
			for i = 1, 12 do
				roam[#roam + 1] = string.format("%d=%.1f", i, now - 30 - i * 2)
			end
			mine.Folder:SetAttribute("Roam", table.concat(roam, ";"))
			advance(3)
			local fx = workspace.ClientFx:FindFirstChild("HomeFx")
			local st0 = HF.Stats()
			local most, desc0, descMost = 0, Mock.CountDescendants(fx), 0
			for _ = 1, 150 do
				advance(0.2)
				most = max(most, tonumber(HF.Stats().Coins) or 0)
				descMost = max(descMost, Mock.CountDescendants(fx))
			end
			local st1 = HF.Stats()
			local poops = (tonumber(st1.Poops) or 0) - (tonumber(st0.Poops) or 0)
			T.check((tonumber(st1.GardenPets) or 0) >= 12, "p4 garden client: (12 garden pets roam our yard)", tostring(st1.GardenPets))
			T.check(poops >= 12 and poops <= 24, "p4 garden client: 12 roaming pets poop once per 24 s cycle each (30 s)", poops .. " poops")
			T.check(most <= 36 and (tonumber(st1.Faded) or 0) >= 1, "p4 garden client: ...as pooled TokenLook coins (<= 36), the unconfirmed ones fade", "at most " .. most .. ", " .. tostring(st1.Faded) .. " faded")
			T.check(descMost - desc0 <= 400, "p4 garden client: ...nothing piles up in the effect folder (pooled coins)", desc0 .. " -> at most " .. descMost)
			-- a visitor next to another player's coin: the one-time hint "Only the owner can pick these up", at the coin
			ctx.standAt(ctx.Pile(1, true) + Vector3.new(1.5, 0, 0))
			advance(1.2)
			local st = HF.Stats()
			T.check(st.Hint == "Only the owner can pick these up", "p4 garden client: a visitor at another player's coin sees the hint once", tostring(st.Hint))
			local hint = nil
			for _, d in ipairs(fx:GetDescendants()) do
				if d:IsA("BillboardGui") and d.Name == "OwnerHint" and d.Parent and d.Parent.Parent == fx then
					hint = d
				end
			end
			local label = hint and hint:FindFirstChild("Text")
			T.check(hint ~= nil and hint.Parent:IsA("BasePart") and flat(hint.Parent.Position, ctx.Pile(1, true)) < 0.5 and hint.Size.X.Scale == 0 and hint.Size.Y.Scale == 0
				and label and label.TextSize >= 15, "p4 garden client: ...a pixel-sized label at the coin (never in the screen centre)")
			ctx.standAt(ctx.Pile(1) + Vector3.new(0, 0, -30))
			advance(1.0)
			ctx.standAt(ctx.Pile(5, true) + Vector3.new(1, 0, 0))
			advance(4.0)
			local shownAgain = false
			for _, d in ipairs(fx:GetDescendants()) do
				if d:IsA("BillboardGui") and d.Name == "OwnerHint" and d.Parent and d.Parent.Parent == fx then
					shownAgain = true
				end
			end
			T.check(not shownAgain, "p4 garden client: ...and never again")
		end)
		cleanup()
		if not ok then
			T.fail("p4 garden client: coins scenario raised an error", tostring(err))
		end
		noWarnings("p4 garden client coins", outputBefore, errorsBefore)
		KC.flushErrors("client_p4garden_heaps")
	end)

	-- the scoop: only the owner's drops zip to them, the "+$" label at the drop
	CS.client_p4garden_scoop = guarded("client_p4garden_scoop", function()
		local outputBefore, errorsBefore = #Mock.Output, #Mock.Errors
		local ctx, cleanup = setup("Scoop", 9600)
		if not ctx then
			return
		end
		local ok, err = pcall(function()
			local mine, theirs, HF, hrp = ctx.Mine, ctx.Theirs, ctx.HF, ctx.Hrp
			local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
			local screens0 = 0
			for _, c in ipairs(pg and pg:GetChildren() or {}) do
				if c:IsA("ScreenGui") then
					screens0 = screens0 + 1
				end
			end
			local radius = ctx.TC.ScoopRadius({ Stations = { Garden = 2 } })
			LocalPlayer:SetAttribute("Cash", 100)
			mine.Folder:SetAttribute("CollectorCash", 5000)
			mine.Folder:SetAttribute("CoinDrops", "1=0:4;2=0:3;W=5")
			-- stand 2 studs from drop 1 (inside the scoop radius)
			local p1 = ctx.Pile(1)
			ctx.standAt(p1 + Vector3.new(2, 0, 0))
			advance(0.6)
			local g = ctx.g()
			T.check(g.Coins["1:0"] and g.Coins["2:0"] and g.Heaps.W and g.Radius == radius, "p4 garden client: (precondition) two coins + the Welcome heap, the Garden L2 scoop radius", tostring(g.Radius))
			T.check(HF.Stats().Ring == true, "p4 garden client: standing in their yard, the owner sees the faint scoop ring")
			local st0 = HF.Stats()
			-- the server scoops drop 1: the bank drops, the Cash rises, the drop is gone (any order, one moment)
			LocalPlayer:SetAttribute("Cash", 1334)
			mine.Folder:SetAttribute("CollectorCash", 3766)
			mine.Folder:SetAttribute("CoinDrops", "2=0:3;W=5")
			advance(0.05)
			local st1 = HF.Stats()
			T.check((tonumber(st1.Zips) or 0) == (tonumber(st0.Zips) or 0) + 1 and (tonumber(st1.Flying) or 0) >= 3,
				"p4 garden client: the owner's scooped drop: coins zip from it", tostring(st1.Flying) .. " coins flying")
			local fx = workspace.ClientFx:FindFirstChild("HomeFx")
			local nearest = huge
			for _ = 1, 4 do
				advance(0.08)
				for _, p in ipairs(fx:GetChildren()) do
					if p:IsA("BasePart") and p.Name == "FlyingCoin" then
						nearest = min(nearest, (p.Position - hrp.Position).Magnitude)
					end
				end
			end
			T.check(nearest < 1.5, "p4 garden client: ...to the owner", "closest " .. tostring(nearest))
			T.check(st1.LastLabel == "+" .. ctx.TC.FormatCash(1234) and st1.LastLabelAt and flat(st1.LastLabelAt, p1) < 0.05,
				"p4 garden client: ...and a \"+$1,234\" label (the bank's drop) at the drop", tostring(st1.LastLabel))
			local pop = nil
			for _, d in ipairs(fx:GetDescendants()) do
				if d:IsA("BillboardGui") and d.Name == "ScoopPop" and d.Parent and d.Parent.Parent == fx then
					pop = d
				end
			end
			local text = pop and pop:FindFirstChild("Text")
			T.check(pop ~= nil and flat(pop.Parent.Position, p1) < 0.1 and flat(pop.Parent.Position, hrp.Position) > 1 and pop.Parent.Position.Y < hrp.Position.Y + 1,
				"p4 garden client: ...never over the player's head (in third person that is the screen centre)")
			T.check(pop and pop.Size.X.Scale == 0 and pop.LightInfluence == 0 and text and text.TextSize >= 22 and (text.TextStrokeTransparency <= 0.5 or text:FindFirstChild("TextOutline") ~= nil),
				"p4 garden client: ...a pixel-sized label, >= 22 px with a stroke (World text rule)", text and tostring(text.TextSize) or "no label")
			advance(2)
			-- a drop that vanishes out of reach (the farthest of slots 3-12 from where we stand): no zip
			local farSlot, farD = nil, 0
			for slot = 3, 12 do
				local d = flat(ctx.Pile(slot), hrp.Position)
				if d > farD then
					farSlot, farD = slot, d
				end
			end
			if farD > radius + 4 then
				mine.Folder:SetAttribute("CoinDrops", "2=0:3;" .. farSlot .. "=0:3;W=5")
				advance(1.0)
				local st2 = HF.Stats()
				LocalPlayer:SetAttribute("Cash", 2334)
				mine.Folder:SetAttribute("CollectorCash", 2766)
				mine.Folder:SetAttribute("CoinDrops", "2=0:3;W=5")
				advance(0.3)
				T.check((tonumber(HF.Stats().Zips) or 0) == (tonumber(st2.Zips) or 0) and HF.Stats().Labels == st2.Labels,
					"p4 garden client: a drop out of the owner's reach vanishes without a zip or a label")
			else
				T.info("p4 garden client: no drop far enough from the owner for the out-of-reach check (" .. string.format("%.1f", farD) .. " studs)")
			end
			-- another player's drops never zip to the local player, even standing on them
			theirs.Folder:SetAttribute("CollectorCash", 4000)
			theirs.Folder:SetAttribute("CoinDrops", "1=0:4;2=0:4")
			ctx.standAt(ctx.Pile(1, true) + Vector3.new(1, 0, 0))
			advance(0.6)
			T.check(HF.Stats().Ring == false, "p4 garden client: no scoop ring in another player's yard")
			local st3 = HF.Stats()
			LocalPlayer:SetAttribute("Cash", 3334)
			theirs.Folder:SetAttribute("CollectorCash", 0)
			theirs.Folder:SetAttribute("CoinDrops", "")
			advance(0.3)
			T.check(HF.Stats().Zips == st3.Zips and HF.Stats().Labels == st3.Labels, "p4 garden client: another player's drops never zip to the local player (only the owner's coins are collectable)")
			-- a Prestige (bank and Cash to 0, every drop gone) while standing in the yard: no "+$" label
			ctx.standAt(ctx.Pile(2) + Vector3.new(2, 0, 0))
			mine.Folder:SetAttribute("CollectorCash", 2766)
			mine.Folder:SetAttribute("CoinDrops", "2=0:3;W=5")
			advance(1.5)
			local st4 = HF.Stats()
			LocalPlayer:SetAttribute("Cash", 0)
			mine.Folder:SetAttribute("CollectorCash", 0)
			mine.Folder:SetAttribute("CoinDrops", "")
			advance(0.5)
			T.check(HF.Stats().Labels == st4.Labels, "p4 garden client: drops emptied by a Prestige (no Cash gained) show no \"+$\" label")
			local screens1 = 0
			for _, c in ipairs(pg and pg:GetChildren() or {}) do
				if c:IsA("ScreenGui") then
					screens1 = screens1 + 1
				end
			end
			T.check(screens1 == screens0, "p4 garden client: HomeFx adds nothing to the screen (no ScreenGui: nothing in the screen centre)", screens0 .. " -> " .. screens1)
			ctx.standAt(ctx.Pile(1) + Vector3.new(0, 0, -60))
			advance(0.6)
			T.check(HF.Stats().Ring == false, "p4 garden client: ...and the scoop ring goes when the owner leaves the yard")
		end)
		cleanup()
		if not ok then
			T.fail("p4 garden client: scoop scenario raised an error", tostring(err))
		end
		noWarnings("p4 garden client scoop", outputBefore, errorsBefore)
		KC.flushErrors("client_p4garden_scoop")
	end)

	-- PetCards over garden / training pets (contract 3.9): own garden pets level + XP, others' level only, training timers
	CS.client_p4garden_cards = guarded("client_p4garden_cards", function()
		local outputBefore, errorsBefore = #Mock.Output, #Mock.Errors
		local ctx, cleanup = setup("Cards", 10200)
		if not ctx then
			return
		end
		local ok, err = pcall(function()
			local mine, theirs, HF = ctx.Mine, ctx.Theirs, ctx.HF
			local key = ctx.Ids[12]
			mine.Folder:SetAttribute("GardenPets", "1=" .. key .. ";9=" .. ctx.Ids[11])
			mine.Folder:SetAttribute("GardenInfo", "1=12:1;9=3:0")
			theirs.Folder:SetAttribute("GardenPets", "2=" .. ctx.Ids[10])
			theirs.Folder:SetAttribute("GardenInfo", "2=7:0")
			local ends = math.floor(workspace:GetServerTimeNow()) + 130
			mine.Folder:SetAttribute("TrainingPets", "1=" .. ctx.Ids[9] .. ":Ability:" .. ends)
			ctx.standAt(ctx.Pile(1))
			advance(1.5)
			local g = ctx.g()
			local gp1 = g.Pets[1]
			local card = g.Pets[1] and g.Pets[1].Card
			local gui = card and card.Gui
			local lv = gui and gui:FindFirstChild("Plate") and gui.Plate:FindFirstChild("Level")
			T.check(card ~= nil and card.mode == "Garden" and lv and lv.Text == "Lv 12", "p4 garden client: an own garden pet carries a PetCard (mode Garden) with its level from GardenInfo",
				lv and lv.Text or "no card")
			T.check(lv and lv.TextSize >= 17 and gui.Size.X.Scale == 0 and gui.LightInfluence == 0, "p4 garden client: ...pixel-sized (World text rule)")
			local stars = gui and gui:FindFirstChild("StarBadge")
			T.check(stars ~= nil and stars.Visible ~= false, "p4 garden client: ...with the star of its evolution stage")
			ctx.standAt(ctx.Gym.Position + ctx.Gym.LookVector * 6)
			advance(1.2)
			local tr = ctx.g().Training[1]
			local tcard = tr and tr.Card
			local ttext = tcard and tcard.Gui and tcard.Gui:FindFirstChild("Plate") and tcard.Gui.Plate:FindFirstChild("TimerText")
			T.check(tcard ~= nil and tcard.mode == "Training" and ttext and string.match(ttext.Text, "^%d+:%d%d$") ~= nil,
				"p4 garden client: an own training pet's card shows the purple timer (m:ss)", ttext and ttext.Text or "no timer")
			local t0 = ttext and ttext.Text
			advance(2.2)
			T.check(ttext and ttext.Text ~= t0, "p4 garden client: ...counting down", tostring(t0) .. " -> " .. tostring(ttext and ttext.Text))
			-- the far garden pet (place 9, back row) is too far from the player for a card? both are within 40 studs here
			T.check(gp1 ~= nil and g.Pets[9] and g.Pets[9].Card ~= nil, "p4 garden client: every own garden pet within 40 studs has a card")
			-- another player's garden pet: level only
			ctx.standAt(ctx.Pile(2, true))
			advance(1.2)
			local og = ctx.g(theirs)
			local ocard = og.Pets[2] and og.Pets[2].Card
			local olv = ocard and ocard.Gui and ocard.Gui.Plate:FindFirstChild("Level")
			local xpRow = ocard and ocard.Gui and ocard.Gui.Plate:FindFirstChild("Xp")
			T.check(ocard ~= nil and ocard.mode == "Other" and olv and olv.Text == "Lv 7" and (xpRow == nil or not xpRow.Visible),
				"p4 garden client: another player's garden pet: level only (mode Other)", olv and olv.Text or "no card")
			local back = ctx.g().Pets[1]
			T.check(back == nil or back.Card == nil, "p4 garden client: cards only within 40 studs of the player (ours are gone over there)")
			ctx.standAt(ctx.Pile(1) + Vector3.new(0, 0, -400))
			advance(1.2)
			local left = 0
			for _, spot in ipairs({ mine, theirs }) do
				for _, e in pairs(ctx.g(spot).Pets) do
					if e.Card then
						left = left + 1
					end
				end
			end
			T.check(left == 0, "p4 garden client: ...and none far away", left .. " cards left")
		end)
		cleanup()
		if not ok then
			T.fail("p4 garden client: cards scenario raised an error", tostring(err))
		end
		noWarnings("p4 garden client cards", outputBefore, errorsBefore)
		KC.flushErrors("client_p4garden_cards")
	end)

	return CS
end

local S = {}
if CONTEXT ~= "server" then
	return clientScenarios()
end

local advance, config, mod = K.advance, K.config, K.mod

local function near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and abs(a - b) <= (tol or 1e-6)
end

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

local function TS()
	return requireAt("server/Services/TycoonService")
end
local function TC()
	return requireAt("shared/TycoonCatalog")
end
local function PK()
	return requireAt("shared/PetKeys")
end

local userSeq = 0
local function join(prefix)
	userSeq = userSeq + 1
	local p = Mock.AddPlayer(prefix .. userSeq, 964000 + userSeq)
	advance(1.0)
	return p
end

local function rejoin(name, userId)
	local p = Mock.AddPlayer(name, userId)
	advance(1.0)
	return p
end

local function leave(p)
	if p and p.Parent then
		Mock.RemovePlayer(p)
	end
	advance(0.6)
end

local function spots()
	return (K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
end

local function freeIndex(skip)
	local SS = mod("SpotService")
	for i = 1, config().Lobby.SpotCount do
		if spots()[i] and not SS.GetOwner(i) and i ~= skip then
			return i
		end
	end
	return nil
end

local function claimPromptOf(index)
	local info = spots()[index]
	if info and info.Folder then
		for _, d in ipairs(info.Folder:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Name == "ClaimPrompt" then
				return d
			end
		end
	end
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "ClaimPrompt" and d:GetAttribute("SpotIndex") == index then
			return d
		end
	end
	return nil
end

-- walks to the gate (just outside it, like a player) and presses E on its ClaimPrompt
local function claim(p, index)
	local prompt = claimPromptOf(index)
	local SS = mod("SpotService")
	local gate = SS.GateCFrame(spots()[index])
	if gate and p.Character then
		Mock.Teleport(p, gate * CFrame.new(0, 3, -5))
	end
	if prompt then
		Mock.Trigger(prompt, p)
	end
	advance(0.6)
	return prompt ~= nil
end

local function remote(name)
	return K.remoteFolder():FindFirstChild(name)
end

local function homeAction(p, action, arg)
	Mock.FromClient(remote("HomeAction"), p, action, arg)
end

local function cashOf(p)
	return mod("DataService").GetCash(p)
end

local function bankOf(p)
	local home = mod("DataService").GetHome(p)
	return home and home.CollectorCash or 0
end

local function givePet(p, key, n)
	local DataS = mod("DataService")
	local prof = DataS.GetProfile(p)
	local ok = PK().Add(prof, key, n or 1)
	DataS.MarkDirty(p)
	return ok
end

-- an Economy and a Combat pet of the SAME rarity (the 1/1.6 rule reads exactly), plus a Legendary-or-better Economy
local function petPair()
	local PC = K.M["shared/PetCatalog"]
	local byRarity = {}
	for _, def in ipairs(PC.Pets) do
		if def.Rarity ~= "Secret" and not def.EventOnly then
			local r = byRarity[def.Rarity]
			if not r then
				r = {}
				byRarity[def.Rarity] = r
			end
			if def.Role == "Economy" and not r.Eco then
				r.Eco = def
			elseif def.Role == "Combat" and not r.Combat then
				r.Combat = def
			end
		end
	end
	for _, rarity in ipairs({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }) do
		local r = byRarity[rarity]
		if r and r.Eco and r.Combat then
			return r.Eco, r.Combat
		end
	end
	return nil, nil
end

-- the first Epic-or-rarer Economy pet (it evolves twice)
local function epicEco()
	local PC = K.M["shared/PetCatalog"]
	for _, rarity in ipairs({ "Epic", "Legendary", "Mythic" }) do
		for _, def in ipairs(PC.Pets) do
			if def.Rarity == rarity and def.Role == "Economy" and not def.EventOnly then
				return def
			end
		end
	end
	return nil
end

-- the owner stands at a world point (the root ~3 studs over it)
local function standAt(p, pos, dx, dz)
	Mock.Teleport(p, CFrame.new(pos + Vector3.new(dx or 0, 3, dz or 0)))
end

-- far from every garden (the plaza, where players spawn)
local function away(p)
	Mock.Teleport(p, config().Lobby.Origin + Vector3.new(0, 4, 0))
end

local function pileOf(Ty, p, slot)
	local piles = Ty.Piles(p)
	return piles and piles[slot] or nil
end

local function liveSum(Ty, p)
	local piles = Ty.Piles(p)
	if not piles then
		return 0, 0
	end
	local total, count = 0, 0
	for slot, pile in pairs(piles) do
		if slot ~= "W" then
			total = total + pile.Value
			count = count + pile.Coins
		end
	end
	return total, count, piles.W and piles.W.Value or 0
end

local function entryOf(p, def, key)
	local DataS = mod("DataService")
	return { Def = def, Level = DataS.GetPetLevel(p, key or def.Id) or 1, Tier = "Normal", Stage = DataS.GetEvolution(p, key or def.Id) or 0, Key = key or def.Id }
end

-- a new home with the free Pet Garden built (the only pad of a fresh home)
local function startHome(Ty, p)
	local index = freeIndex()
	claim(p, index)
	local ok, lvl = Ty.Buy(p, "Garden")
	advance(0.3)
	return index, spots()[index], ok, lvl
end

local function HR()
	return requireAt("shared/HomeRoam")
end

local function PCat()
	return K.M["shared/PetCatalog"] or requireAt("shared/PetCatalog")
end

local function roamSeedOf(p)
	return (p.UserId % 2147483646) + 1
end

-- the Roam attribute "1=1760001234.5;3=1760001240.0:N812" -> { [slot] = { Epoch, Nap } }
local function roamOf(info)
	local out = {}
	local text = info and info.Folder and info.Folder:GetAttribute("Roam") or ""
	for part in tostring(text):gmatch("[^;]+") do
		local slot, epoch, nap = part:match("^(%d+)=([%d%.]+):N(%d+)$")
		if not slot then
			slot, epoch = part:match("^(%d+)=([%d%.]+)$")
		end
		if slot then
			out[tonumber(slot)] = { Epoch = tonumber(epoch), Nap = nap and tonumber(nap) or nil }
		end
	end
	return out
end

local function dropsText(info)
	return info and info.Folder and info.Folder:GetAttribute("CoinDrops") or ""
end

local function dropsOf(Ty, p, slot)
	local out = {}
	for _, d in ipairs(Ty.Drops(p) or {}) do
		if slot == nil or d.Slot == slot then
			out[#out + 1] = d
		end
	end
	return out
end

-- the plot-local poop point of (seed, slot, cycle) as a world point
local function poopWorld(info, seed, slot, cycle)
	local plan = HR().Plan(seed, slot, cycle)
	if not plan or not plan.Poop then
		return nil
	end
	return info.PlotCFrame:PointToWorldSpace(Vector3.new(plan.Poop.x, 0, plan.Poop.z))
end

local function serverNow()
	return workspace:GetServerTimeNow()
end

-- the whole Cash of every drop within `radius` (planar) of `pos`, plus the Welcome pile when in range
local function inRangeValue(Ty, p, pos, radius)
	local sum = 0
	for _, d in ipairs(Ty.Drops(p) or {}) do
		if typeof(d.Position) == "Vector3" and K.planar(d.Position, pos) <= radius then
			sum = sum + d.Value
		end
	end
	local piles = Ty.Piles(p)
	if piles and piles.W and piles.W.Pos and K.planar(piles.W.Pos, pos) <= radius then
		sum = sum + piles.W.Value
	end
	return sum
end

-- advances second by second until slot `slot` holds >= n poops (or maxSeconds pass); returns the poop count
local function waitPoops(Ty, p, slot, n, maxSeconds)
	local waited = 0
	while waited < (maxSeconds or 120) do
		local pile = pileOf(Ty, p, slot)
		if pile and pile.Coins >= n then
			return pile.Coins
		end
		advance(1)
		waited = waited + 1
	end
	local pile = pileOf(Ty, p, slot)
	return pile and pile.Coins or 0
end

local function poopValueOf(Cat, home, p, def, stars)
	return Cat.CoinValue(home, Cat.PetPower(entryOf(p, def)), stars or 0) * Cat.Coins.PoopMeals
end

----------------------------------------------------------------------------------------------------
-- p4garden_coins
----------------------------------------------------------------------------------------------------
S.p4garden_coins = guarded("p4garden_coins", function()
	if not K.needBoot() then
		return
	end
	local DataS = mod("DataService")
	local Ty, Cat, Roam = TS(), TC(), HR()
	if not Ty or not Cat or not Roam then
		T.fail("p4 garden: TycoonService, TycoonCatalog and HomeRoam load")
		return
	end
	for _, fn in ipairs({ "PileSeconds", "CollectorCap", "CoinsWaiting", "GardenSet", "GoHome", "OpenHomePortal", "ClearCoins", "Collect", "Piles", "Drops" }) do
		T.check(type(Ty[fn]) == "function", "p4 garden: TycoonService." .. fn .. " is a function")
	end
	for _, sig in ipairs({ "CoinsScooped", "PortalUsed" }) do
		T.check(type(Ty[sig]) == "table" and type(Ty[sig].Connect) == "function", "p4 garden: signal TycoonService." .. sig)
	end
	T.check(Cat.CoinPoint == nil or type(Cat.CoinPoint) == "function", "p4 garden: (Phase 5) TycoonService no longer needs TycoonCatalog.CoinPoint")
	local Eco, Combat = petPair()
	if not T.check(Eco ~= nil and Combat ~= nil, "p4 garden: (precondition) an Economy and a Combat pet of one rarity") then
		return
	end
	local cycle = Roam.Cycle
	local p = join("GardCoin")
	local seed = roamSeedOf(p)
	local cash0 = cashOf(p)
	local index, info, okGarden = startHome(Ty, p)
	local home = Ty.GetHome(p)
	T.check(okGarden == true and home and home.Stations.Garden == 1 and cashOf(p) == cash0 and home.Level == 1,
		"p4 garden: the Pet Garden is the free first station (Home Level 1)")
	T.eq(info.Folder:GetAttribute("GardenSlots"), 3, "p4 garden: the plot replicates GardenSlots = 3 (3 + 0 stars)")
	T.eq(info.Folder:GetAttribute("CollectorCash"), 0, "p4 garden: ...CollectorCash 0")
	T.eq(info.Folder:GetAttribute("IncomePerSecond"), 0, "p4 garden: ...IncomePerSecond 0: no pet in the garden = no coins")
	T.check(dropsText(info) == "", "p4 garden: ...and no Cloud Cash drop yet (CoinDrops empty)")
	T.eq(info.Folder:GetAttribute("CoinPiles"), nil, "p4 garden: (Phase 5) the CoinPiles attribute is gone")
	T.eq(info.Folder:GetAttribute("RoamSeed"), seed, "p4 garden: RoamSeed = (UserId % 2147483646) + 1")
	T.eq(info.Folder:GetAttribute("RoamVersion"), Roam.Version, "p4 garden: RoamVersion = HomeRoam.Version")
	T.eq(info.Folder:GetAttribute("BerryCap"), Cat.Berries.BasketMin, "p4 garden: BerryCap = BasketMin (" .. Cat.Berries.BasketMin .. ") with no income")
	away(p)
	advance(30)
	T.eq(bankOf(p), 0, "p4 garden: an empty garden makes nothing (30 s)")

	-- an Economy pet: Epoch = now + SettleSeconds, nothing before its first poop, then a drop worth CoinValue x PoopMeals
	givePet(p, Eco.Id, 1)
	givePet(p, Combat.Id, 1)
	local mark = K.logSize()
	local placedAt = serverNow()
	local okSet, whySet = Ty.GardenSet(p, 1, Eco.Id)
	T.check(okSet == true, "p4 garden: GardenSet(1, Economy) places the pet", tostring(whySet))
	T.check(K.notified(p, "working in your Garden", "good", mark), "p4 garden: ...with a toast")
	home = Ty.GetHome(p)
	T.eq(home.Garden[1], Eco.Id, "p4 garden: Home.Garden[1] holds the key")
	T.eq(info.Folder:GetAttribute("GardenPets"), "1=" .. Eco.Id, "p4 garden: GardenPets replicates the placed key")
	T.eq(info.Folder:GetAttribute("GardenInfo"), "1=1:0", "p4 garden: GardenInfo replicates level:stage (1:0)")
	local roam = roamOf(info)
	T.check(roam[1] and near(roam[1].Epoch, placedAt + Roam.SettleSeconds, 0.11) and roam[1].Nap == nil,
		"p4 garden: Roam carries the slot's epoch = placement + SettleSeconds 20 (one decimal)", tostring(info.Folder:GetAttribute("Roam")))
	local epoch1 = roam[1].Epoch
	local coinE = Cat.CoinValue(home, Cat.PetPower(entryOf(p, Eco)), 0)
	local poopE = coinE * Cat.Coins.PoopMeals
	local foodNow = Cat.FoodOf(home)
	T.check(near(coinE, Cat.Coins.GrassFood * Cat.PetPower(entryOf(p, Eco)), 1e-6) and foodNow == Cat.Coins.GrassFood,
		"p4 garden: a Garden L1 coin = GrassFood 12 x PetPower (" .. string.format("%.2f", coinE) .. "); a poop = 3 coins")
	local incomeE = Cat.IncomePerSecond(home, { [1] = entryOf(p, Eco) }, 0)
	T.check(near(Ty.IncomePerSecond(p), incomeE, 1e-6) and near(info.Folder:GetAttribute("IncomePerSecond"), incomeE, 0.051),
		"p4 garden: IncomePerSecond = Food / 8 x PetPower (" .. string.format("%.3f", incomeE) .. "/s), replicated")
	local firstPoop = Roam.PoopTime(seed, 1, epoch1, 0)
	T.check(firstPoop - placedAt >= cycle - 1e-6, "p4 garden: the first poop comes >= 24 s after the placement (" .. string.format("%.1f", firstPoop - placedAt) .. " s)")
	advance(firstPoop - serverNow() - 0.6)
	T.eq(bankOf(p), 0, "p4 garden: nothing before the first poop time (HomeRoam.PoopTime on the slot's epoch)")
	T.check(dropsText(info) == "", "p4 garden: ...no drop yet")
	advance(1.7)
	T.check(near(bankOf(p), poopE, 1e-6), "p4 garden: one poop landed (bank = CoinValue x PoopMeals)", tostring(bankOf(p)))
	local drops1 = dropsOf(Ty, p, 1)
	T.check(#drops1 == 1 and drops1[1].Cycle == 0 and near(drops1[1].Value, poopE, 1e-6) and not drops1[1].Lucky and drops1[1].Stage == 1,
		"p4 garden: Drops(player) lists one drop of slot 1, cycle 0, stage 1")
	local pile1 = pileOf(Ty, p, 1)
	T.check(pile1 ~= nil and pile1.Coins == 1 and near(pile1.Value, poopE, 1e-6) and not pile1.Lucky and not pile1.Full,
		"p4 garden: Piles (per-slot sums) agree: 1 poop, its value")
	T.eq(dropsText(info), "1=0:1", "p4 garden: CoinDrops '1=0:1' (slot 1 = cycle 0 : stage 1)")
	T.eq(info.Folder:GetAttribute("CollectorCash"), floor(poopE), "p4 garden: CollectorCash replicates the whole bank")
	local want = poopWorld(info, seed, 1, 0)
	T.check(drops1[1] and typeof(drops1[1].Position) == "Vector3" and want and (drops1[1].Position - want).Magnitude < 1e-3,
		"p4 garden: the drop lies at HomeRoam.Plan(seed, 1, 0).Poop in the plot frame (the client computes the same point)")
	T.check(pile1 and typeof(pile1.Pos) == "Vector3" and (pile1.Pos - want).Magnitude < 1e-3, "p4 garden: ...Piles[1].Pos is that point")
	local berries1 = DataS.GetBerries(p)
	T.check(berries1 == floor(poopE * Cat.Berries.Share) or berries1 == floor(poopE * Cat.Berries.Share) + 1 or berries1 == 0 and poopE * Cat.Berries.Share < 1,
		"p4 garden: the poop grew value x Share berries (" .. tostring(berries1) .. ")")

	-- a Combat pet of the same rarity: 1/1.6 of the Economy coin; its own epoch and plan
	local okC = Ty.GardenSet(p, 2, Combat.Id)
	T.check(okC == true, "p4 garden: GardenSet accepts a Combat pet (any role works)")
	home = Ty.GetHome(p)
	local coinC = Cat.CoinValue(home, Cat.PetPower(entryOf(p, Combat)), 0)
	T.check(near(coinC * 1.6, coinE, 1e-6), "p4 garden: a Combat pet's coin is 1/1.6 of an Economy pet's at the same rarity / level",
		string.format("%.3f vs %.3f", coinC, coinE))
	local epoch2 = roamOf(info)[2] and roamOf(info)[2].Epoch
	T.check(epoch2 ~= nil and epoch2 > epoch1, "p4 garden: the second slot has its own, later epoch")
	local bankBefore = bankOf(p)
	advance(Roam.PoopTime(seed, 2, epoch2, 0) - serverNow() + 1.2)
	local pile2 = pileOf(Ty, p, 2)
	T.check(pile2 ~= nil and pile2.Coins == 1 and near(pile2.Value, coinC * Cat.Coins.PoopMeals, 1e-6), "p4 garden: the Combat pet dropped its smaller poop at its own time", pile2 and tostring(pile2.Value) or "no drop")
	T.check(bankOf(p) >= bankBefore + coinC * Cat.Coins.PoopMeals - 1e-6, "p4 garden: the bank took the new coins", tostring(bankOf(p) - bankBefore))
	T.check(near(Ty.IncomePerSecond(p), Cat.IncomePerSecond(home, { [1] = entryOf(p, Eco), [2] = entryOf(p, Combat) }, 0), 1e-6),
		"p4 garden: IncomePerSecond sums both pets")
	T.eq(info.Folder:GetAttribute("GardenPets"), "1=" .. Eco.Id .. ";2=" .. Combat.Id, "p4 garden: GardenPets lists both (slot order)")
	T.eq(info.Folder:GetAttribute("GardenInfo"), "1=1:0;2=1:0", "p4 garden: GardenInfo lists both")

	-- the invariant while coins flow: sum(drops) + Welcome == CollectorCash; every poop at its planned point; plain
	-- coins only at Garden L1; a slot keeps 3 drops then merges into the nearest
	local parts0 = #info.Folder:GetDescendants()
	local okInv, okPlain, okPoints = true, true, true
	for _ = 1, 5 * cycle do
		advance(1)
		local live, _, welcome = liveSum(Ty, p)
		if not near(live + welcome, bankOf(p), 1e-6) then
			okInv = false
		end
		for _, d in ipairs(Ty.Drops(p) or {}) do
			if d.Lucky then
				okPlain = false
			end
			local at = poopWorld(info, seed, d.Slot, d.Cycle)
			if not at or (at - d.Position).Magnitude > 1e-3 then
				okPoints = false
			end
		end
	end
	T.check(okInv, "p4 garden: sum(drops) + Welcome-back == CollectorCash at every second while coins flow (X4 invariant)")
	T.check(okPlain, "p4 garden: at Garden L1 (Lucky 0) every drop is plain (no Lucky)")
	T.check(okPoints, "p4 garden: every drop stays at the poop point of its own (slot, cycle) plan")
	T.eq(#info.Folder:GetDescendants(), parts0, "p4 garden: no Instance per coin on the server (the plot's descendants did not grow)")
	local p1 = pileOf(Ty, p, 1)
	local d1 = dropsOf(Ty, p, 1)
	T.check(p1 and p1.Coins >= 5 and #d1 == Cat.Coins.DropsPerPet, "p4 garden: after 6 poops slot 1 holds exactly DropsPerPet 3 drops (the rest merged)", tostring(p1 and p1.Coins) .. " poops / " .. #d1 .. " drops")
	local merged = 0
	for _, d in ipairs(d1) do
		if d.Poops >= 2 then
			merged = merged + 1
		end
	end
	T.check(merged >= 1 and near(p1.Value, p1.Coins * poopE, 1e-6), "p4 garden: a merged drop holds the sum of its poops (value = poops x poop)")
	local text = dropsText(info)
	local okText = true
	for _, d in ipairs(d1) do
		if not text:find(tostring(d.Cycle) .. ":" .. tostring(d.Stage), 1, true) then
			okText = false
		end
	end
	T.check(okText and text:match("^1=[%d:,%*]+;2=[%d:,%*]+$") ~= nil, "p4 garden: CoinDrops lists every drop as cycle:stage per slot (" .. text .. ")")

	-- the stored evolution stage multiplies the coin through LevelFactor (never the level alone)
	local evoDef = epicEco()
	if evoDef then
		givePet(p, evoDef.Id, 1)
		DataS.SetPetLevel(p, evoDef.Id, 20)
		Ty.GardenSet(p, 3, evoDef.Id)
		home = Ty.GetHome(p)
		local plain = Cat.CoinValue(home, Cat.PetPower(entryOf(p, evoDef)), 0)
		T.check(near(plain, Cat.Coins.GrassFood * Cat.PetPower({ Def = evoDef, Level = 20, Tier = "Normal", Stage = 0 }), 1e-6),
			"p4 garden: a level-20 pet that has not pressed EVOLVE earns the plain level-20 coin")
		T.eq(DataS.SetEvolution(p, evoDef.Id, 1), true, "p4 garden: (precondition) SetEvolution stage 1")
		advance(0.1)
		local evolved = Cat.CoinValue(Ty.GetHome(p), Cat.PetPower(entryOf(p, evoDef)), 0)
		local factor = PCat().LevelFactor(20, 1) / PCat().LevelFactor(20, 0)
		T.check(near(evolved, plain * factor, 1e-6), "p4 garden: the STORED stage 1 multiplies the coin by LevelFactor(20, 1) / LevelFactor(20, 0) = " .. string.format("%.3f", factor),
			string.format("%.3f vs %.3f", evolved, plain))
		local e3 = roamOf(info)[3]
		if T.check(e3 ~= nil, "p4 garden: (precondition) slot 3 has an epoch") then
			advance(Roam.PoopTime(seed, 3, e3.Epoch, 0) - serverNow() + 1.2)
			local p3 = pileOf(Ty, p, 3)
			T.check(p3 ~= nil and near(p3.Value, evolved * Cat.Coins.PoopMeals, 1e-6) and info.Folder:GetAttribute("GardenInfo") == "1=1:0;2=1:0;3=20:1",
				"p4 garden: ...its first poop is the evolved poop and GardenInfo says 20:1", tostring(info.Folder:GetAttribute("GardenInfo")))
		end
		Ty.GardenSet(p, 3, nil)
	else
		T.info("*evolution coin check skipped: no Epic+ Economy pet")
	end

	-- Lucky drops at Garden L8 (Lucky 0.15): three Economy copies, ~8 cycles
	Ty.GardenSet(p, 2, nil)
	givePet(p, Eco.Id, 2)
	DataS.MutateHome(p, function(h)
		h.Stations.Garden = 8
		h.Stations.Press1 = 1
		h.Level = Cat.HomeLevelOf(h)
	end)
	advance(1.2)
	T.check(Cat.LuckyChance(Ty.GetHome(p)) >= 0.15 - 1e-9, "p4 garden: (precondition) Garden L8 rolls Lucky coins at 15%")
	Ty.ClearCoins(p)
	Ty.GardenSet(p, 2, Eco.Id)
	Ty.GardenSet(p, 3, Eco.Id)
	home = Ty.GetHome(p)
	local poop8 = poopValueOf(Cat, home, p, Eco, 0)
	advance(8 * cycle + Roam.SettleSeconds + 2)
	local live, count = liveSum(Ty, p)
	local luckies = (live - count * poop8) / ((Cat.Coins.LuckyMult - 1) * poop8)
	T.check(count >= 20 and near(luckies, floor(luckies + 0.5), 1e-6) and luckies >= 1 and luckies <= count * 0.5,
		"p4 garden: Lucky poops are worth x5 (over " .. count .. " poops: " .. string.format("%.0f", luckies) .. " Lucky)")
	advance(2.1) -- the throttled CoinDrops write (<= 0.5 / s) lands
	local starsOk, anyStar = true, false
	text = dropsText(info)
	local listed = {} -- [slot] = { [cycle] = "stage[*]" }
	for part in text:gmatch("[^;]+") do
		local slot, items = part:match("^(%d+)=(.*)$")
		if slot then
			listed[tonumber(slot)] = {}
			for cycle, rest in items:gmatch("(%d+):([%d%*]+)") do
				listed[tonumber(slot)][tonumber(cycle)] = rest
			end
		end
	end
	for _, d in ipairs(Ty.Drops(p) or {}) do
		if d.Poops >= 1 then
			local entry = listed[d.Slot] and listed[d.Slot][d.Cycle]
			local inText = entry ~= nil and entry:sub(-1) == "*"
			if entry == nil or d.Lucky ~= inText or tonumber(entry:match("^%d+")) ~= d.Stage then
				starsOk = false
			end
			if d.Lucky then
				anyStar = true
			end
		end
	end
	T.check(starsOk and anyStar, "p4 garden: a drop with a Lucky poop inside shows '*' in CoinDrops (" .. text .. ")")
	T.check(near(live, bankOf(p), 1e-6), "p4 garden: ...and the bank still equals the drops")
	T.check(#text <= 400, "p4 garden: CoinDrops stays under 400 bytes (" .. #text .. ")")

	-- the lawn cap: one pet, PileSeconds (Garden L8 600 s) of its coins, then the pet naps (':N<cycle>' in Roam) until scooped
	Ty.GardenSet(p, 2, nil)
	Ty.GardenSet(p, 3, nil)
	Ty.ClearCoins(p)
	home = Ty.GetHome(p)
	local pileSeconds = Cat.PileSeconds(home)
	T.eq(Ty.PileSeconds(p), pileSeconds, "p4 garden: TycoonService.PileSeconds(player) = TycoonCatalog.PileSeconds(home) (" .. pileSeconds .. ")")
	T.eq(Ty.CollectorCap(p), pileSeconds, "p4 garden: ...CollectorCap is its alias")
	local coin8 = Cat.CoinValue(home, Cat.PetPower(entryOf(p, Eco)), 0)
	local cap = pileSeconds * coin8 / Cat.Coins.MealSeconds * Cat.LuckyEV(home)
	-- the cap is set by the Lucky EV but the lawn fills with the poops actually rolled: wait cycle by cycle up to the
	-- all-plain worst case
	local worstCycles = math.ceil(cap / poop8 - 1e-9) + 3
	local napped = false
	for _ = 1, worstCycles do
		local r = roamOf(info)[1]
		if r and r.Nap then
			napped = true
			break
		end
		advance(cycle)
	end
	advance(1.2)
	local r1 = roamOf(info)[1]
	local full = pileOf(Ty, p, 1)
	T.check(r1 and r1.Nap ~= nil and full and full.Full == true and full.Value >= cap - poop8 * Cat.Coins.LuckyMult - 1e-6 and full.Value <= cap + poop8 * Cat.Coins.LuckyMult + 1e-6,
		"p4 garden: the lawn fills to PileSeconds x the pet's rate and the pet naps (Roam ':N<cycle>', Piles.Full)", (full and string.format("%.1f of %.1f", full.Value, cap) or "no drop") .. " roam " .. tostring(info.Folder:GetAttribute("Roam")))
	T.check(full and full.Value >= cap - 1e-6, "p4 garden: ...the nap comes only once the lawn value reached the cap", full and string.format("%.1f of %.1f", full.Value, cap) or "")
	local bankFull = bankOf(p)
	advance(3 * cycle)
	T.check(near(bankOf(p), bankFull, 1e-6), "p4 garden: a napping pet poops nothing: the bank stops growing", tostring(bankOf(p) - bankFull))
	T.check(near(Ty.CoinsWaiting(p), floor(bankFull), 1e-6), "p4 garden: CoinsWaiting = the whole Cash on the lawn")
	local cashBefore = cashOf(p)
	local radius = Cat.ScoopRadius(home)
	local wantPaid = floor(inRangeValue(Ty, p, full.Pos, radius) + 1e-6)
	local wakeAt = serverNow()
	standAt(p, full.Pos)
	advance(0.4)
	T.eq(cashOf(p) - cashBefore, wantPaid, "p4 garden: scooping at the napping pet's drops pays their whole Cash")
	r1 = roamOf(info)[1]
	local napPlan = Roam.Plan(seed, 1, (roamOf(info)[1] and 0) or 0)
	T.check(r1 and r1.Nap == nil and r1.Epoch >= wakeAt - 0.11 and r1.Epoch <= wakeAt + cycle + 0.5,
		"p4 garden: the scoop wakes the pet: Roam drops ':N' and its epoch = now + the back walk (<= one cycle)", tostring(info.Folder:GetAttribute("Roam")))
	away(p)
	local poopsBefore = pileOf(Ty, p, 1) and pileOf(Ty, p, 1).Coins or 0
	advance(2 * cycle + 2)
	local again = pileOf(Ty, p, 1)
	T.check(again ~= nil and again.Coins > poopsBefore and not again.Full, "p4 garden: ...and the pet poops again within the back walk + a cycle")
	leave(p)
	K.flushErrors("p4garden_coins")
	K.flushWarnings("p4garden_coins", { "HomeBuilder is missing" })
end)

----------------------------------------------------------------------------------------------------
-- p4garden_scoop
----------------------------------------------------------------------------------------------------
S.p4garden_scoop = guarded("p4garden_scoop", function()
	if not K.needBoot() then
		return
	end
	local DataS, SS = mod("DataService"), mod("SpotService")
	local Ty, Cat, Roam = TS(), TC(), HR()
	if not Ty or not Cat or not Roam then
		T.fail("p4 garden: TycoonService, TycoonCatalog and HomeRoam load")
		return
	end
	local Eco, Combat = petPair()
	if not Eco then
		T.fail("p4 garden scoop: (precondition) pets")
		return
	end
	local cycle = Roam.Cycle
	local p = join("GardScoop")
	local index, info = startHome(Ty, p)
	givePet(p, Eco.Id, 3)
	givePet(p, Combat.Id, 1)
	away(p)
	Ty.GardenSet(p, 1, Eco.Id)
	Ty.GardenSet(p, 2, Eco.Id)
	advance(Roam.SettleSeconds + 3 * cycle + 2)
	-- freeze production: the pets leave the garden, their drops stay on the lawn
	Ty.GardenSet(p, 1, nil)
	Ty.GardenSet(p, 2, nil)
	advance(1.1)
	local pile1, pile2 = pileOf(Ty, p, 1), pileOf(Ty, p, 2)
	if not T.check(pile1 and pile2 and pile1.Coins >= 2 and pile2.Coins >= 2, "p4 garden scoop: (precondition) drops of two slots on the lawn") then
		leave(p)
		return
	end
	local total0 = cashOf(p) + bankOf(p)
	T.check(near(pile1.Value + pile2.Value, bankOf(p), 1e-6), "p4 garden scoop: the drops equal the bank")
	local radius = Cat.ScoopRadius(Ty.GetHome(p))
	T.eq(radius, Cat.Get("Garden").Effects[1].Radius, "p4 garden scoop: ScoopRadius at Garden L1 = its Radius effect (8 studs)")
	T.eq(Cat.ScoopRadius({ Stations = {} }), Cat.Coins.BaseRadius, "p4 garden scoop: ...6 studs without a Garden")
	local drops1 = dropsOf(Ty, p, 1)
	local drop = drops1[1]

	-- a second player on the lawn: nothing (X2), also with HomeAction Collect from their position / their own plot
	local stranger = join("GardStranger")
	local cashS = cashOf(stranger)
	standAt(stranger, drop.Position)
	advance(1.0)
	local mark = K.logSize()
	homeAction(stranger, "Collect")
	advance(0.3)
	T.check(cashOf(stranger) == cashS and near(bankOf(p), pile1.Value + pile2.Value, 1e-6) and pileOf(Ty, p, 1) ~= nil,
		"p4 garden scoop: another player standing on the owner's coins scoops nothing (touch or Collect)")
	T.check(K.notified(stranger, "Claim a home first", nil, mark), "p4 garden scoop: ...their Collect answers 'Claim a home first'")
	local otherIndex = freeIndex(index)
	claim(stranger, otherIndex)
	standAt(stranger, drop.Position)
	mark = K.logSize()
	homeAction(stranger, "Collect")
	advance(0.5)
	T.check(cashOf(stranger) == cashS and near(bankOf(p), pile1.Value + pile2.Value, 1e-6),
		"p4 garden scoop: a plot owner standing in someone else's garden scoops nothing of theirs")
	T.check(K.notified(stranger, "Nothing to scoop yet", nil, mark), "p4 garden scoop: ...'Nothing to scoop yet' (their own lawn is empty)")

	-- the owner just outside the radius: nothing; inside: paid exactly once, whole Cash, fractions stay
	local farDir = Vector3.new(1, 0, 0)
	local farPos = drop.Position + farDir * (radius + 1.5)
	-- a point radius + 1.5 from the drop that is also out of range of every other drop and the Welcome pile
	for _, angle in ipairs({ 0, 90, 180, 270, 45, 135, 225, 315 }) do
		local dir = Vector3.new(math.cos(math.rad(angle)), 0, math.sin(math.rad(angle)))
		local pos = drop.Position + dir * (radius + 1.5)
		if inRangeValue(Ty, p, pos, radius) < 1 then
			farPos = pos
			break
		end
	end
	standAt(p, farPos)
	advance(0.6)
	T.check(near(bankOf(p), pile1.Value + pile2.Value, 1e-6), "p4 garden scoop: the owner just outside the radius scoops nothing")
	Mock.Teleport(p, CFrame.new(drop.Position + Vector3.new(0, 11.5, 0)))
	advance(0.6)
	T.check(near(bankOf(p), pile1.Value + pile2.Value, 1e-6), "p4 garden scoop: ...nor 11.5 studs above a drop (10 studs of vertical reach)")
	local scooped = {}
	local conn = Ty.CoinsScooped:Connect(function(pl, amount)
		scooped[#scooped + 1] = { pl, amount }
	end)
	local cashBefore, bankBefore = cashOf(p), bankOf(p)
	local inRange = inRangeValue(Ty, p, drop.Position, radius)
	standAt(p, drop.Position)
	advance(0.3)
	local paid = cashOf(p) - cashBefore
	T.eq(paid, floor(inRange), "p4 garden scoop: the owner within the radius is paid the whole Cash of the drops in range (" .. floor(inRange) .. ")")
	T.check(near(bankOf(p), bankBefore - paid, 1e-6), "p4 garden scoop: ...the bank lost exactly that (MutateHome then AddCash)")
	T.check(near(cashOf(p) + bankOf(p), total0, 1e-6), "p4 garden scoop: Cash + CollectorCash is constant across the scoop (paid once)")
	T.check(#scooped == 1 and scooped[1][1] == p and scooped[1][2] == paid, "p4 garden scoop: CoinsScooped(player, amount) fired once with the amount", tostring(#scooped))
	local frac = inRange - floor(inRange)
	local leftValue = inRangeValue(Ty, p, drop.Position, radius)
	T.check((frac < 1e-6 and leftValue < 1e-6) or (frac >= 1e-6 and near(leftValue, frac, 1e-6)),
		"p4 garden scoop: whole Cash only: the fraction below one Cash stays on the lawn (" .. string.format("%.3f", frac) .. ")")
	local fracDrop = nil
	for _, d in ipairs(Ty.Drops(p) or {}) do
		if d.Poops == 0 then
			fracDrop = d
		end
	end
	T.check((frac < 1e-6) == (fracDrop == nil) and not dropsText(info):find(":0", 1, true), "p4 garden scoop: ...as a drop with 0 poops that CoinDrops never lists")
	advance(1.0)
	T.eq(cashOf(p) - cashBefore, paid, "p4 garden scoop: standing still pays nothing more (the drops are gone)")
	T.eq(#scooped, 1, "p4 garden scoop: ...and CoinsScooped stays at one")
	conn:Disconnect()

	-- HomeAction "Collect" (old clients / tests) = scoop in range
	local rest = Ty.Drops(p) or {}
	local target = nil
	for _, d in ipairs(rest) do
		if d.Poops >= 1 then
			target = d
			break
		end
	end
	if target then
		away(p)
		local bankNow = bankOf(p)
		homeAction(p, "Collect")
		advance(0.3)
		T.check(near(bankOf(p), bankNow, 1e-6), "p4 garden scoop: HomeAction 'Collect' far from the coins scoops nothing")
		advance(0.6) -- past the Collect cooldown
		cashBefore = cashOf(p)
		local want = floor(inRangeValue(Ty, p, target.Position, radius) + 1e-6)
		standAt(p, target.Position)
		mark = K.logSize()
		homeAction(p, "Collect")
		advance(0.1)
		T.eq(cashOf(p) - cashBefore, want, "p4 garden scoop: HomeAction 'Collect' at a drop scoops it (the 0.25 s loop would too)")
		T.check(K.notified(p, "scooped", "good", mark), "p4 garden scoop: ...with a '+$ scooped!' toast")
	end
	T.check(near(cashOf(p) + bankOf(p), total0, 1e-6), "p4 garden scoop: Cash + CollectorCash still constant")

	-- a folded Coin Magnet (LegacyMagnet 1 at the home's star): radius 9 beats the Garden's 8
	DataS.MutateHome(p, function(h)
		h.LegacyMagnet = 1
		h.LegacyMagnetStar = 0
	end)
	T.check(Cat.ScoopRadius(Ty.GetHome(p)) == 9, "p4 garden scoop: a folded Coin Magnet L1 -> ScoopRadius 9")
	Ty.ClearCoins(p)
	away(p)
	Ty.GardenSet(p, 1, Eco.Id)
	advance(Roam.SettleSeconds + 2 * cycle + 2)
	Ty.GardenSet(p, 1, nil)
	advance(1.1)
	local pm = dropsOf(Ty, p, 1)[1]
	if T.check(pm ~= nil and pm.Poops >= 1, "p4 garden scoop: (precondition) a drop for the Magnet check") then
		cashBefore = cashOf(p)
		local pos = pm.Position + Vector3.new(8.5, 0, 0)
		local want = floor(inRangeValue(Ty, p, pos, 9) + 1e-6)
		standAt(p, pm.Position, 8.5, 0)
		advance(0.4)
		T.eq(cashOf(p) - cashBefore, want, "p4 garden scoop: with the Magnet the owner scoops from 8.5 studs")
	end
	DataS.MutateHome(p, function(h)
		h.LegacyMagnet = nil
		h.LegacyMagnetStar = nil
	end)
	away(p) -- out of reach: the checks below count coins on the lawn

	-- GardenSet rules: the training lock (DataService.TrainingKeys) with the time left; a key in a running battle
	local prof = DataS.GetProfile(p)
	local okJob = DataS.MutateGrowth(p, function(g)
		g[Combat.Id] = g[Combat.Id] or {}
		g[Combat.Id].Job = { Stat = "Speed", Ends = os.time() + 130, Rank = 1, Slot = 1, Paid = 0 }
	end)
	T.check(okJob == true and DataS.TrainingKeys(p)[Combat.Id] == true, "p4 garden scoop: (precondition) a training job on the Combat pet")
	local okT, whyT = Ty.GardenSet(p, 2, Combat.Id)
	local cName = tostring(Combat.DisplayName or Combat.Name)
	T.check(okT == false and tostring(whyT):find(cName, 1, true) ~= nil and tostring(whyT):find("is training", 1, true) ~= nil and tostring(whyT):find("%(2:%d%d left%)") ~= nil
		and Ty.GetHome(p).Garden[2] == nil, "p4 garden scoop: a training pet cannot be placed: '<name> is training (2:xx left)'", tostring(whyT))
	-- a training pet already in the garden stops eating (its slot is kept for PetCareService to clear)
	Ty.GardenSet(p, 1, Eco.Id)
	advance(0.3)
	T.check(near(Ty.IncomePerSecond(p), Cat.IncomePerSecond(Ty.GetHome(p), { [1] = entryOf(p, Eco) }, 0), 1e-6), "p4 garden scoop: (precondition) the Economy pet earns in place 1")
	DataS.MutateGrowth(p, function(g)
		g[Eco.Id] = g[Eco.Id] or {}
		g[Eco.Id].Job = { Stat = "Physique", Ends = os.time() + 60, Rank = 1, Slot = 2, Paid = 0 }
	end)
	advance(1.2)
	T.check(Ty.IncomePerSecond(p) == 0 and Ty.GetHome(p).Garden[1] == Eco.Id and (info.Folder:GetAttribute("GardenPets") or "") == "",
		"p4 garden scoop: a garden pet that starts training stops earning (its key stays in Home.Garden, GardenPets drops it)")
	T.check((info.Folder:GetAttribute("Roam") or "") == "", "p4 garden scoop: ...and Roam drops its epoch (the client parks it)")
	DataS.MutateGrowth(p, function(g)
		g[Eco.Id].Job = nil
		g[Combat.Id].Job = nil
	end)
	advance(1.2)
	T.check(Ty.IncomePerSecond(p) > 0 and info.Folder:GetAttribute("GardenPets") == "1=" .. Eco.Id, "p4 garden scoop: ...and earns again when the job is gone")
	local BS = requireAt("server/Services/BattleService")
	if BS then
		local hadFn = BS.KeysInBattle
		BS.KeysInBattle = function(pl)
			if pl == p then
				return { [Combat.Id] = true }
			end
			return {}
		end
		local okB, whyB = Ty.GardenSet(p, 2, Combat.Id)
		T.check(okB == false and whyB == "Finish your battle first!" and Ty.GetHome(p).Garden[2] == nil,
			"p4 garden scoop: a key in the caller's running battle (BattleService.KeysInBattle) is refused", tostring(whyB))
		BS.KeysInBattle = hadFn
	end
	local okC2 = Ty.GardenSet(p, 2, Combat.Id)
	T.check(okC2 == true, "p4 garden scoop: ...and accepted once the battle is over")
	Ty.GardenSet(p, 2, nil)

	-- X5 / Y8: remove + re-place within one cycle keeps the epoch; a placement after a cycle away starts over
	Ty.GardenSet(p, 1, nil)
	Ty.ClearCoins(p)
	advance(1.1)
	local t0 = serverNow()
	Ty.GardenSet(p, 1, Eco.Id)
	local e0 = roamOf(info)[1].Epoch
	T.check(near(e0, t0 + Roam.SettleSeconds, 0.11), "p4 garden scoop: (Y8) a NEW placement: Epoch = now + SettleSeconds")
	advance(cycle - 6)
	Ty.GardenSet(p, 1, nil)
	advance(0.5)
	Ty.GardenSet(p, 1, Eco.Id)
	T.check(near(roamOf(info)[1].Epoch, e0, 1e-6), "p4 garden scoop: (Y8) the same key back within one cycle keeps its epoch (no later poop, no earlier one)")
	T.eq(bankOf(p), 0, "p4 garden scoop: (Y8) nothing yet before the first poop time")
	advance(Roam.PoopTime(roamSeedOf(p), 1, e0, 0) - serverNow() + 1.2)
	T.check(bankOf(p) > 0, "p4 garden scoop: (Y8) ...the poop comes at the ORIGINAL time")
	local b1 = bankOf(p)
	Ty.GardenSet(p, 1, nil)
	advance(cycle + 2)
	local t1 = serverNow()
	Ty.GardenSet(p, 1, Eco.Id)
	local e1 = roamOf(info)[1].Epoch
	T.check(near(e1, t1 + Roam.SettleSeconds, 0.11) and e1 > e0, "p4 garden scoop: (Y8) a placement after more than a cycle away starts over (a new epoch)")
	advance(cycle - 1.5)
	T.check(near(bankOf(p), b1, 1e-6), "p4 garden scoop: (Y8) ...no poop before a full cycle")
	-- churn spam: 40 remove / place pairs in one frame never move the epoch (the first request passes, the rest wait)
	for _ = 1, 40 do
		homeAction(p, "GardenSet", { 1 })
		homeAction(p, "GardenSet", { 1, Eco.Id })
	end
	advance(0.3)
	Ty.GardenSet(p, 1, Eco.Id)
	advance(0.3)
	T.check(Ty.GetHome(p).Garden[1] == Eco.Id and near(roamOf(info)[1].Epoch, e1, 1e-6), "p4 garden scoop: 80 GardenSet requests in one frame leave the pet in place 1 with its epoch (cooldown + burst budget)")

	-- resting keys above the open count (X20) and LegacySlots
	Ty.ClearCoins(p)
	DataS.MutateHome(p, function(h)
		h.Garden[2] = Eco.Id
		h.Garden[4] = Eco.Id -- a 4th key (an old Garden L8 after a prestige that ended LegacySlots): it rests
	end)
	advance(1.2)
	T.eq(Cat.GardenSlots(Ty.GetHome(p)), 3, "p4 garden scoop: (precondition) 3 open places")
	T.eq(info.Folder:GetAttribute("GardenPets"), "1=" .. Eco.Id .. ";2=" .. Eco.Id .. ";4=" .. Eco.Id, "p4 garden scoop: GardenPets lists the resting key too (nothing is deleted)")
	T.check((info.Folder:GetAttribute("GardenInfo") or ""):find("4=1:0", 1, true) ~= nil, "p4 garden scoop: ...GardenInfo too")
	T.check(roamOf(info)[4] == nil and roamOf(info)[2] ~= nil, "p4 garden scoop: Roam carries epochs for the open places only")
	T.check(near(Ty.IncomePerSecond(p), Cat.IncomePerSecond(Ty.GetHome(p), { [1] = entryOf(p, Eco), [2] = entryOf(p, Eco) }, 0), 1e-6),
		"p4 garden scoop: IncomePerSecond counts only the open places")
	advance(Roam.SettleSeconds + 2 * cycle + 2)
	T.check(pileOf(Ty, p, 4) == nil and pileOf(Ty, p, 2) ~= nil, "p4 garden scoop: the resting key makes no coins while places 1-2 do")
	local okLocked, whyLocked = Ty.GardenSet(p, 5, Eco.Id)
	T.check(okLocked == false and tostring(whyLocked):find("locked", 1, true) ~= nil, "p4 garden scoop: GardenSet above the open count is refused ('locked')", tostring(whyLocked))
	local okClear = Ty.GardenSet(p, 4, nil)
	T.check(okClear == true and Ty.GetHome(p).Garden[4] == nil, "p4 garden scoop: ...but a resting key can always be taken out")
	DataS.MutateHome(p, function(h)
		h.LegacySlots = 5
	end)
	advance(1.2)
	T.eq(Cat.GardenSlots(Ty.GetHome(p)), 5, "p4 garden scoop: LegacySlots 5 opens 5 places")
	T.eq(info.Folder:GetAttribute("GardenSlots"), 5, "p4 garden scoop: ...GardenSlots replicates 5")
	local t5 = serverNow()
	local ok5 = Ty.GardenSet(p, 5, Eco.Id)
	local ok6, why6 = Ty.GardenSet(p, 6, Eco.Id)
	T.check(ok5 == true and ok6 == false and tostring(why6):find("locked", 1, true) ~= nil, "p4 garden scoop: place 5 opens, place 6 stays locked")
	advance(0.3)
	local r5 = roamOf(info)[5]
	T.check(pileOf(Ty, p, 5) == nil and r5 ~= nil and near(r5.Epoch, t5 + Roam.SettleSeconds, 0.11), "p4 garden scoop: the newly opened place owes no backlog (a settle first, no coin at once)")
	advance(Roam.PoopTime(roamSeedOf(p), 5, r5.Epoch, 0) - serverNow() + 1.2)
	T.check(pileOf(Ty, p, 5) ~= nil and pileOf(Ty, p, 5).Coins == 1, "p4 garden scoop: ...its first poop comes at its planned time",
		"garden5 " .. tostring(Ty.GetHome(p).Garden[5]) .. " income " .. tostring(Ty.IncomePerSecond(p)) .. " pets " .. tostring(info.Folder:GetAttribute("GardenPets")) .. " drops " .. tostring(dropsText(info)) .. " open " .. tostring(Cat.GardenSlots(Ty.GetHome(p))))
	T.check(cashOf(p) >= 0 and cashOf(stranger) >= 0, "p4 garden scoop: Cash never goes negative")
	leave(stranger)
	leave(p)
	K.flushErrors("p4garden_scoop")
	K.flushWarnings("p4garden_scoop", { "HomeBuilder is missing" })
end)

----------------------------------------------------------------------------------------------------
-- p4garden_ledger
----------------------------------------------------------------------------------------------------
S.p4garden_ledger = guarded("p4garden_ledger", function()
	if not K.needBoot() then
		return
	end
	local DataS, SS = mod("DataService"), mod("SpotService")
	local Ty, Cat, Roam = TS(), TC(), HR()
	if not Ty or not Cat or not Roam then
		T.fail("p4 garden: TycoonService, TycoonCatalog and HomeRoam load")
		return
	end
	local Eco = petPair()
	if not Eco then
		T.fail("p4 garden ledger: (precondition) pets")
		return
	end
	local cycle = Roam.Cycle
	local name, userId = "GardLedger", 964501
	local storeKey = config().Tokens.DataStoreName .. "/u_" .. userId
	local p = rejoin(name, userId)
	local first, info = startHome(Ty, p)
	givePet(p, Eco.Id, 2)
	DataS.MutateHome(p, function(h)
		h.Stations.Press1 = 3
		h.Stations.Vault = 1
		h.Level = Cat.HomeLevelOf(h)
	end)
	away(p)
	Ty.GardenSet(p, 1, Eco.Id)
	Ty.GardenSet(p, 2, Eco.Id)
	advance(Roam.SettleSeconds + 3 * cycle + 2)
	local income = Ty.IncomePerSecond(p)
	local bankLeave = bankOf(p)
	T.check(bankLeave > 0 and income > 0, "p4 garden ledger: (precondition) coins on the lawn, a Vault home that earns")

	-- leave + rejoin: the coins left on the lawn wait in the Welcome-back pile and pay once
	leave(p)
	advance(1.0)
	local rec = Mock.DataStore.Data[storeKey]
	-- (the store keeps whole Cash: the bank is saved floored, like the Cash balance)
	if not T.check(rec ~= nil and type(rec.Home) == "table" and abs((rec.Home.CollectorCash or 0) - bankLeave) < 1 and (rec.Home.LastSeen or 0) > 0,
		"p4 garden ledger: the leave save holds the bank (CollectorCash, whole Cash) and LastSeen", rec and tostring(rec.Home and rec.Home.CollectorCash) or "no save") then
		return
	end
	bankLeave = rec.Home.CollectorCash
	rec.Home.LastSeen = os.time() -- just left: no offline pay on this rejoin
	local cashStored = rec.Cash or 0
	local berriesStored = rec.Berries or 0
	p = rejoin(name, userId)
	advance(3)
	T.check(near(bankOf(p), bankLeave, 1e-6) and cashOf(p) == cashStored, "p4 garden ledger: a rejoin within 120 s pays no offline coins and banks nothing by itself",
		tostring(bankOf(p)) .. " vs " .. tostring(bankLeave))
	T.eq(DataS.GetBerries(p), berriesStored, "p4 garden ledger: ...and adds no berries")
	local blocker = join("GardBlock")
	claim(blocker, first)
	local second = freeIndex(first)
	claim(p, second)
	local info2 = spots()[second]
	local piles = Ty.Piles(p)
	T.check(piles ~= nil and piles.W ~= nil and near(piles.W.Value, bankLeave, 1e-6) and piles[1] == nil and piles[2] == nil and #(Ty.Drops(p) or {}) == 0,
		"p4 garden ledger: on the claim the whole bank waits in the Welcome-back pile (no live drop)")
	T.check(dropsText(info2):find("W=5", 1, true) ~= nil, "p4 garden ledger: CoinDrops carries 'W=5' while the Welcome-back pile holds anything")
	local wantW = (info2.PlotCFrame):PointToWorldSpace(Cat.Get("Garden").Slot.WelcomePile)
	T.check(piles.W and typeof(piles.W.Pos) == "Vector3" and (piles.W.Pos - wantW).Magnitude < 1e-3, "p4 garden ledger: the Welcome-back pile stands at the plot-local WelcomePile point")
	T.eq(info2.Folder:GetAttribute("GardenPets"), "1=" .. Eco.Id .. ";2=" .. Eco.Id, "p4 garden ledger: the garden pets are back in their places")
	local roam2 = roamOf(info2)
	local now2 = serverNow()
	T.check(roam2[1] and roam2[2] and roam2[1].Epoch >= now2 - 0.11 and roam2[1].Epoch <= now2 + cycle + 0.11 and roam2[2].Epoch <= now2 + cycle + 0.11,
		"p4 garden ledger: a fresh ledger staggers the epochs within one cycle (Epoch = now + Rng x 24)", tostring(info2.Folder:GetAttribute("Roam")))
	local cashBefore = cashOf(p)
	standAt(p, piles.W.Pos)
	advance(0.4)
	T.eq(cashOf(p) - cashBefore, floor(bankLeave), "p4 garden ledger: scooping the Welcome-back pile pays the whole stored bank once (" .. floor(bankLeave) .. ")")
	local live, _, welcome = liveSum(Ty, p)
	T.check(welcome < 1 and near(live + welcome, bankOf(p), 1e-6), "p4 garden ledger: ...the Welcome-back pile is empty and the bank equals the new drops")
	advance(1.0)
	T.eq(cashOf(p) - cashBefore, floor(bankLeave), "p4 garden ledger: ...and nothing is paid twice")

	-- offline coins: into the bank in the same write as LastSeen; Cash untouched; paid once; offline berries once
	away(p)
	advance(2 * cycle)
	local homeBefore = Ty.GetHome(p)
	income = Ty.IncomePerSecond(p)
	leave(p)
	advance(1.0)
	rec = Mock.DataStore.Data[storeKey]
	local away2h = 2 * 3600
	rec.Home.LastSeen = os.time() - away2h
	local storedBank = rec.Home.CollectorCash or 0
	local want = Cat.OfflineEarnings(homeBefore, away2h, income)
	cashStored = rec.Cash or 0
	berriesStored = rec.Berries or 0
	local mark = K.logSize()
	p = rejoin(name, userId)
	advance(4.0)
	T.check(want > 0 and cashOf(p) == cashStored, "p4 garden ledger: offline coins never go to the Cash balance (" .. tostring(want) .. " owed)")
	T.check(near(bankOf(p), storedBank + floor(want), 1e-6), "p4 garden ledger: ...they go INTO the bank (CollectorCash + " .. floor(want) .. ")",
		string.format("%.2f vs %.2f", bankOf(p), storedBank + floor(want)))
	local wantBerries = floor(floor(want) * Cat.Berries.Share)
	T.eq(DataS.GetBerries(p) - berriesStored, wantBerries, "p4 garden ledger: ...and offline x Share berries land in the basket (" .. wantBerries .. ", the cap ignored)")
	T.check(K.notified(p, "Welcome back! Your pets made", "good", mark), "p4 garden ledger: the 'Welcome back! Your pets made $X while you were away: scoop it in your garden!' toast")
	local bankPaid = bankOf(p)
	advance(20)
	T.check(near(bankOf(p), bankPaid, 1e-6) and DataS.GetBerries(p) - berriesStored == wantBerries, "p4 garden ledger: paid once (LastSeen moved on with the same write)")
	local seen = DataS.GetHome(p).LastSeen or 0
	T.check(os.time() - seen <= 25, "p4 garden ledger: ...LastSeen is fresh", tostring(os.time() - seen))
	claim(p, freeIndex())
	local pl = Ty.Piles(p)
	T.check(pl and pl.W and near(pl.W.Value, bankPaid, 1e-6), "p4 garden ledger: the offline coins wait in the Welcome-back pile on the claim")
	cashBefore = cashOf(p)
	standAt(p, pl.W.Pos)
	advance(0.4)
	T.eq(cashOf(p) - cashBefore, floor(bankPaid), "p4 garden ledger: ...and are scooped once")

	-- a rebase while the plot is held: the ledger is rebuilt from the merged bank, nothing is paid twice
	away(p)
	advance(Roam.SettleSeconds + cycle + 2)
	local liveBefore = liveSum(Ty, p)
	T.check(liveBefore > 0, "p4 garden ledger: (precondition) live drops before the rebase")
	DataS.MutateHome(p, function(h)
		h.CollectorCash = h.CollectorCash + 20 -- what a merge with another server's coins would bring
	end)
	DataS.ProfileRebased:Fire(p, DataS.GetProfile(p))
	advance(0.3)
	local merged = bankOf(p)
	pl = Ty.Piles(p)
	T.check(pl and pl.W and near(pl.W.Value, merged, 1e-6) and pl[1] == nil and pl[2] == nil,
		"p4 garden ledger: ProfileRebased rebuilds the ledger: the whole merged bank waits in the Welcome-back pile", pl and tostring(pl.W and pl.W.Value) or "nil")
	cashBefore = cashOf(p)
	standAt(p, pl.W.Pos)
	advance(0.4)
	T.eq(cashOf(p) - cashBefore, floor(merged), "p4 garden ledger: ...scooped once for exactly the merged bank")
	T.check(bankOf(p) < 1 + 3 * income, "p4 garden ledger: ...the bank is down to the fraction and the newest coins", tostring(bankOf(p)))

	-- a provisional load (DataStore outage): nothing can be claimed from stand-in data; after the recovery the stored
	-- bank waits as the Welcome-back pile
	local vetId = 964502
	local vetKey = config().Tokens.DataStoreName .. "/u_" .. vetId
	local function deepCopy(t)
		if type(t) ~= "table" then
			return t
		end
		local out = {}
		for k, v in pairs(t) do
			out[k] = deepCopy(v)
		end
		return out
	end
	local copy = deepCopy(Mock.DataStore.Data[storeKey])
	copy.Home.CollectorCash = 30
	copy.Home.LastSeen = 0
	copy.Home.Garden = { Eco.Id }
	copy.Cash = 100
	copy.SpotIndex = nil
	Mock.DataStore.Data[vetKey] = copy
	Mock.DataStore.Fail = true
	local v = rejoin("GardOutage", vetId)
	advance(4)
	T.check(DataS.IsProvisional(v) == true, "p4 garden ledger: (precondition) the outage makes the profile provisional")
	local okProv, whyProv = Ty.Claim(v, freeIndex())
	T.check(okProv == false and tostring(whyProv):find("still loading", 1, true) ~= nil and SS.GetSpot(v) == nil,
		"p4 garden ledger: a provisional profile claims nothing ('Your home is still loading...')", tostring(whyProv))
	T.eq(Ty.CoinsWaiting(v), 0, "p4 garden ledger: ...and CoinsWaiting answers 0 (no decision from stand-in data)")
	Mock.DataStore.Fail = false
	local recovered = K.waitFor(function()
		return not DataS.IsProvisional(v)
	end, 40)
	T.check(recovered, "p4 garden ledger: (the recovery reads the real save)")
	advance(1)
	T.check(near(bankOf(v), 30, 1e-6) and cashOf(v) == 100, "p4 garden ledger: after the recovery the stored bank and Cash are intact (30 / 100)", tostring(bankOf(v)) .. " / " .. tostring(cashOf(v)))
	claim(v, freeIndex())
	local pv = Ty.Piles(v)
	T.check(pv and pv.W and near(pv.W.Value, 30, 1e-6), "p4 garden ledger: ...the claim puts the stored 30 in the Welcome-back pile")
	cashBefore = cashOf(v)
	standAt(v, pv.W.Pos)
	advance(0.4)
	T.eq(cashOf(v) - cashBefore, 30, "p4 garden ledger: ...scooped once")
	leave(v)

	-- an outage during scoops: the leave save fails, the orphan retry writes Cash and the bank; nothing is lost or doubled
	away(p)
	Ty.ClearCoins(p)
	advance(Roam.SettleSeconds + 2 * cycle + 2)
	Mock.DataStore.Fail = true
	advance(cycle)
	local dl = dropsOf(Ty, p, 1)[1] or dropsOf(Ty, p, 2)[1]
	cashBefore = cashOf(p)
	standAt(p, dl.Position)
	advance(0.4)
	local paidOut = cashOf(p) - cashBefore
	T.check(paidOut >= floor(dl.Value) and paidOut >= 1, "p4 garden ledger: scoops keep working during a DataStore outage", tostring(paidOut))
	away(p)
	advance(0.5)
	local cashLeave, bankLeave2 = cashOf(p), bankOf(p)
	local function ledgerDetail(player, wantCash, wantBank)
		return "cash " .. tostring(cashOf(player)) .. " vs " .. tostring(wantCash) .. " / bank " .. tostring(bankOf(player)) .. " vs " .. tostring(wantBank)
	end
	local gone = p
	leave(p)
	advance(1.0)
	Mock.DataStore.Fail = false
	local written = K.waitFor(function()
		local r = Mock.DataStore.Data[storeKey]
		return r ~= nil and r.Cash == cashLeave
	end, 120)
	rec = Mock.DataStore.Data[storeKey]
	T.check(written and rec and rec.Cash == cashLeave and abs((rec.Home.CollectorCash or 0) - bankLeave2) < 1,
		"p4 garden ledger: the orphan save after the outage carries the scooped Cash and the remaining bank (nothing lost, nothing doubled)",
		rec and (tostring(rec.Cash) .. " / " .. tostring(rec.Home.CollectorCash) .. " vs " .. tostring(cashLeave) .. " / " .. tostring(bankLeave2)) or "no save")
	-- The write that landed may have been the autosave walk's (whenever its 90 s period falls on the leave: it holds the
	-- entry lock, the deferred leave save waits for it and only then releases the entry, a few frames later) or the leave
	-- save's own (released at once). Wait for the release, so the rejoin below reads the STORE (whole bank) and not the
	-- session still in memory (the live bank keeps its fraction: that path is checked on its own further down).
	local released = K.waitFor(function()
		return DataS.GetProfile(gone) == nil
	end, 30)
	T.check(released, "p4 garden ledger: ...and the departed entry is released once the store holds it")
	rec = Mock.DataStore.Data[storeKey]
	rec.Home.LastSeen = os.time()
	p = rejoin(name, userId)
	advance(2)
	T.check(cashOf(p) == cashLeave and near(bankOf(p), rec.Home.CollectorCash, 1e-6), "p4 garden ledger: ...and the rejoin reads exactly them from the store",
		ledgerDetail(p, cashLeave, rec.Home.CollectorCash))

	-- a rejoin DURING an outage (the leave save cannot land, the dirty entry stays in memory): the new session picks up
	-- the live profile with exactly the Cash and the bank it had; the old session's Release skips it; the store gets
	-- them once when it is back
	DataS.AddCash(p, 1) -- something unsaved, so the failed leave save keeps the entry (a clean one is dropped at once)
	local cashQ, bankQ = cashOf(p), bankOf(p)
	Mock.DataStore.Fail = true
	gone = p
	leave(p)
	p = rejoin(name, userId)
	advance(2)
	T.check(DataS.GetProfile(gone) ~= nil and not DataS.IsProvisional(p) and cashOf(p) == cashQ and near(bankOf(p), bankQ, 1e-6),
		"p4 garden ledger: a rejoin during an outage picks up the session still in memory: Cash and bank exact", ledgerDetail(p, cashQ, bankQ))
	Mock.DataStore.Fail = false
	written = K.waitFor(function()
		local r = Mock.DataStore.Data[storeKey]
		return r ~= nil and r.Cash == cashQ
	end, 120)
	rec = Mock.DataStore.Data[storeKey]
	T.check(written and rec and rec.Cash == cashQ and near(rec.Home.CollectorCash, floor(bankQ), 1e-6) and DataS.GetProfile(p) ~= nil
		and cashOf(p) == cashQ and near(bankOf(p), bankQ, 1e-6),
		"p4 garden ledger: ...the store gets them once when it is back and the live session keeps them (the old session's Release skipped it)",
		rec and (tostring(rec.Cash) .. " / " .. tostring(rec.Home.CollectorCash) .. "; " .. ledgerDetail(p, cashQ, bankQ)) or "no save")

	-- Prestige mid-lawn: bank + drops to 0, the Garden stays at L1, +1 place, LegacySlots cleared, pets kept, berries kept
	claim(p, freeIndex())
	local idx = SS.GetSpot(p) and SS.GetSpot(p).Index
	local pinfo = spots()[idx]
	DataS.MutateHome(p, function(h)
		for _, def in ipairs(Cat.Stations) do
			if not def.KeepOnPrestige then
				h.Stations[def.Id] = def.MaxLevel
			end
		end
		h.Stations.FusionMachine = 0
		h.Stations.ArenaGate = 0
		h.LegacySlots = 6
		h.Level = Cat.HomeLevelOf(h)
	end)
	advance(1.2)
	local ready = Cat.CanPrestige(Ty.GetHome(p))
	T.check(ready == true and Cat.GardenSlots(Ty.GetHome(p)) == 6, "p4 garden ledger: (precondition) prestige-ready, 6 legacy places")
	away(p)
	advance(Roam.SettleSeconds + cycle + 2)
	T.check(bankOf(p) > 0 and liveSum(Ty, p) > 0, "p4 garden ledger: (precondition) coins on the lawn before the Prestige")
	DataS.AddCash(p, 500)
	local berriesKept = DataS.GetBerries(p)
	mark = K.logSize()
	local okP, stars = Ty.Prestige(p)
	advance(0.3)
	local after = Ty.GetHome(p)
	T.check(okP == true and stars == 1 and after.Prestige == 1, "p4 garden ledger: Prestige -> 1 star")
	T.check(after.CollectorCash == 0 and Ty.CoinsWaiting(p) == 0 and cashOf(p) == 0, "p4 garden ledger: ...the bank, the coins on the lawn and the Cash are zero")
	T.eq(DataS.GetBerries(p), berriesKept, "p4 garden ledger: ...the berries survive the Prestige")
	local pp = Ty.Piles(p)
	local count = 0
	for slot in pairs(pp or {}) do
		if slot ~= "W" then
			count = count + 1
		end
	end
	T.check(pp and count == 0 and (pp.W == nil or pp.W.Value == 0) and dropsText(pinfo) == "", "p4 garden ledger: ...every drop is gone (CoinDrops empty)")
	T.eq(after.Stations.Garden, 1, "p4 garden ledger: ...the Garden stays built at level 1 (StationsAfterPrestige)")
	T.check((after.Stations.Press1 or 0) == 0 and (after.Stations.Vault or 0) == 0, "p4 garden ledger: ...the other stations reset")
	T.check(after.LegacySlots == nil and Cat.GardenSlots(after) == 4, "p4 garden ledger: ...LegacySlots are gone: 4 places (3 + 1 star)")
	T.eq(pinfo.Folder:GetAttribute("GardenSlots"), 4, "p4 garden ledger: ...GardenSlots replicates 4")
	T.check(K.notified(p, "Garden place 4 unlocked", "good", mark), "p4 garden ledger: the 'Garden place 4 unlocked!' toast")
	T.check(after.Garden[1] == Eco.Id and after.Garden[2] == Eco.Id, "p4 garden ledger: ...the garden pets keep their places")
	advance(2 * cycle + 2)
	T.check(bankOf(p) > 0, "p4 garden ledger: ...and the coins never stop (x1.25 now)")
	local coin1 = Cat.CoinValue(Ty.GetHome(p), Cat.PetPower(entryOf(p, Eco)), 1)
	local p1 = pileOf(Ty, p, 1) or pileOf(Ty, p, 2)
	T.check(p1 ~= nil and near(p1.Value / p1.Coins, coin1 * Cat.Coins.PoopMeals, 1e-6) and near(coin1, Cat.FoodOf(Ty.GetHome(p)) * Cat.PetPower(entryOf(p, Eco)) * 1.25, 1e-6),
		"p4 garden ledger: ...each poop carries the x1.25 star multiplier")

	-- star prices through PriceAt; a veteran's LegacyPrices (the one-time migration) pays base prices until the next Prestige
	local h1 = Ty.GetHome(p)
	local starPrice = Cat.PriceAt("Press1", 1, h1)
	T.check(starPrice == floor(Cat.PriceFor("Press1", 1) * 1.5), "p4 garden ledger: at 1 star a pad costs PriceAt = x1.5 (" .. tostring(starPrice) .. ")")
	DataS.AddCash(p, starPrice - 1)
	local okPoor, whyPoor = Ty.Buy(p, "Press1")
	T.check(okPoor == false and tostring(whyPoor):find("Not enough Cash", 1, true) ~= nil and tostring(whyPoor):find(tostring(starPrice), 1, true) ~= nil,
		"p4 garden ledger: ...the Upgrade is refused below the star price (the toast names it)", tostring(whyPoor))
	DataS.MutateHome(p, function(h)
		h.LegacyPrices = true
	end)
	local okLegacy = Ty.Buy(p, "Press1")
	T.check(okLegacy == true and cashOf(p) == starPrice - 1 - Cat.PriceFor("Press1", 1), "p4 garden ledger: with Home.LegacyPrices the same pad costs the base price (" .. tostring(Cat.PriceFor("Press1", 1)) .. ")",
		tostring(cashOf(p)))
	DataS.MutateHome(p, function(h)
		h.LegacyPrices = nil
	end)

	-- old station ids from an old client answer a toast and change nothing (3.3)
	local hBefore = Ty.GetHome(p)
	local lvBefore = Cat.HomeLevelOf(hBefore)
	for _, old in ipairs({ { "Press2", "Berry Farm" }, { "Collector", "Pet Garden" }, { "DecorFlowers", "Yard Fence" }, { "DecorLamps", "Fountain" } }) do
		local okOld, whyOld = Ty.Buy(p, old[1])
		T.check(okOld == false and whyOld == "That station is now part of the " .. old[2], "p4 garden ledger: Buy('" .. old[1] .. "') answers 'That station is now part of the " .. old[2] .. "'", tostring(whyOld))
	end
	mark = K.logSize()
	homeAction(p, "Upgrade", "Press3")
	advance(0.3)
	T.check(K.notified(p, "now part of the Berry Farm", nil, mark) and Cat.HomeLevelOf(Ty.GetHome(p)) == lvBefore and Ty.GetHome(p).Stations.Press3 == nil,
		"p4 garden ledger: HomeAction Upgrade with an old id toasts it and builds nothing")

	-- ClearCoins (the developer reset)
	T.eq(Ty.ClearCoins(p), true, "p4 garden ledger: ClearCoins(player) answers true")
	T.check(bankOf(p) == 0 and liveSum(Ty, p) == 0 and dropsText(pinfo) == "", "p4 garden ledger: ...bank and drops are zero")

	-- the one-time welcome toast of a migrated veteran (P4Veteran -> P4Welcome)
	local vet = rejoin("GardVeteran", 964503)
	advance(1)
	T.eq(DataS.MarkMigrated(vet, "P4Veteran"), true, "p4 garden ledger: (precondition) a veteran marker")
	mark = K.logSize()
	claim(vet, freeIndex())
	T.check(K.notified(vet, "Welcome to the new home", "good", mark), "p4 garden ledger: the first claim of a migrated veteran shows the welcome toast")
	T.eq(DataS.IsMigrated(vet, "P4Welcome"), true, "p4 garden ledger: ...and marks P4Welcome")
	leave(vet)
	vet = rejoin("GardVeteran", 964503)
	mark = K.logSize()
	claim(vet, freeIndex())
	T.check(not K.notified(vet, "Welcome to the new home", nil, mark), "p4 garden ledger: ...never twice (a union across sessions and servers)")
	local newbie = join("GardNew")
	mark = K.logSize()
	claim(newbie, freeIndex())
	T.check(not K.notified(newbie, "Welcome to the new home", nil, mark), "p4 garden ledger: a new player never sees the veteran toast")
	T.check(not K.notified(newbie, "Your home got simpler", nil, mark), "p4 garden ledger: ...nor the Phase 5 'Your home got simpler!' toast (nothing was folded)")
	leave(newbie)
	leave(vet)
	leave(blocker)
	leave(p)
	K.flushErrors("p4garden_ledger")
	K.flushWarnings("p4garden_ledger", { "HomeBuilder is missing", "[DataService]" })
end)

return S
