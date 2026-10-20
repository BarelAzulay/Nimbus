-- smoke_p4_pets_client.lua: Phase 4 pet cards and the follow-behind pets (ARCHITECTURE_V3.md "Phase 4 build contract"
-- 3.6 / 3.9 / 3.10 / 8.1, pets engineer). Loaded by tools/smoke.py in the client worlds (desktop 1920x1080 and the
-- 390x844 touch phone):
--   client_p4pets_cards      client/UI/PetCard.lua (every mode's rows, MaxDistance, pixel sizes, "Lv" 22 px with a
--                            stroke, stars, fills written only when they moved by > 0.004, the EVOLVE! pill as an Active
--                            button that calls OnEvolve, SetTimer, SetMode, Destroy) and PetController's cards: own
--                            followers "Lv n" + XP = xp / XpToNext from State (refreshed on ProfileSync), the EVOLVE! pill
--                            at level 20 (a tap opens the Pets panel on that pet), another player's card with the level
--                            and stars from EquippedInfo only (no XP bar, MaxDistance 60), every card hidden while its
--                            owner is InBattle and back afterwards, no card write while nothing changes, 6 players x 3
--                            pets: at most 12 other players' cards (nearest first), one root write per pet unchanged
--   client_p4pets_follow     the trailing formation (Phase 5 size-aware windows, 3.8): 1 / 2 / 3 pets at their slot
--                            (|slot| +- 1.5) behind at rest (never beside or ahead), walking (24 studs/s) along and across
--                            the facing direction: every pet behind the owner along the travel direction (offset <= +0.5
--                            studs once the formation swung round), lag <= back + 9, settles <= |slot| + 1
--   client_p4pets_evolved    evolved followers: own evolved pets are Low detail within contract.json petEvoLow 380 /
--                            petEvo2Low 520 (stage passed through opts.Evolved: the model is measured and trails further
--                            back), other players' evolved models only within 40 studs and at most 6 (nearest first), the
--                            rest normal Low with stars on the card
--   client_p4pets_evolution  PetController.PlayEvolution(key, stage) parks the follower (model + card gone), keeps it parked
--                            while the animation plays, release() brings it back evolved (from the given spot)
--   client_p4pets_portal     the portal dive: HomePortal open + the owner walks in and is teleported home -> the followers
--                            fly into the portal centre (0.4 s), then pop out behind the owner; a plain teleport snaps
--   client_p4pets_mobile     (phone world) the card's "Lv" text >= 14 px on 390x844, the card stays compact
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local KC = _G.KC
local S = {}

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local abs, max, min, sqrt = math.abs, math.max, math.min, math.sqrt
local fmt = string.format

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

local function PC()
	return KC.M.PetController or moduleAt("client", "Controllers/PetController")
end

local PetCatalog = moduleAt("shared", "PetCatalog")
local TycoonCatalog = moduleAt("shared", "TycoonCatalog")

-- first catalog pet of a rarity (no event pets)
local function petOf(rarity, skip)
	for _, def in ipairs(PetCatalog.Pets) do
		if def.Rarity == rarity and not def.EventOnly and def.Id ~= skip then
			return def.Id
		end
	end
	return nil
end

local COMMON = petOf("Common")
local COMMON2 = petOf("Common", COMMON)
local EPIC = petOf("Epic")
local LEGEND = petOf("Legendary")

local function snapshot(levels, growth, pets)
	local owned = {}
	for _, id in ipairs(pets or { COMMON, COMMON2, EPIC, LEGEND }) do
		owned[id] = 1
	end
	return {
		Tokens = 600,
		Pets = owned,
		Equipped = {},
		Items = {},
		Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
		SpotIndex = 1,
		Perks = {},
		Discovered = owned,
		IndexClaimed = {},
		Tutorial = { Step = 99, Done = true, Gifted = true },
		PetLevels = levels or {},
		PetGrowth = growth or {},
	}
end

local function sync(levels, growth)
	KC.toClient("ProfileSync", snapshot(levels, growth))
	advance(0.2)
end

local function root()
	return KC.root()
end

local function modelsOf(player)
	local folder = workspace:FindFirstChild("ClientPets")
	local f = folder and folder:FindFirstChild(tostring(player.UserId))
	local out = {}
	for _, c in ipairs(f and f:GetChildren() or {}) do
		if c:IsA("Model") then
			out[#out + 1] = c
		end
	end
	return out
end

local function infoOf(player)
	local pc = PC()
	return pc and pc.GetFollowerInfo and pc.GetFollowerInfo(player) or {}
end

local function cardsOf(userId)
	local out = {}
	local pc = PC()
	for _, c in ipairs(pc and pc.GetCards and pc.GetCards() or {}) do
		if userId == nil or c.UserId == userId then
			out[#out + 1] = c
		end
	end
	return out
end

local function levelLabel(gui)
	local plate = gui and gui:FindFirstChild("Plate")
	return plate and plate:FindFirstChild("Level")
end

local function stroked(label)
	local s = label and label:FindFirstChild("TextOutline")
	return (s ~= nil and s:IsA("UIStroke") and s.Thickness >= 1 and s.Transparency <= 0.5) or (label ~= nil and label.TextStrokeTransparency <= 0.5)
end

local function barShown(gui, name)
	local plate = gui and gui:FindFirstChild("Plate")
	local bar = plate and plate:FindFirstChild(name)
	return bar ~= nil and bar.Visible, bar and bar:FindFirstChild("Fill")
end

local function fillOf(gui, name)
	local _, fill = barShown(gui, name)
	return fill and fill.Size.X.Scale or nil
end

local function resetLocal()
	LocalPlayer:SetAttribute("EquippedPets", "")
	LocalPlayer:SetAttribute("EquippedInfo", nil)
	LocalPlayer:SetAttribute("InBattle", nil)
	LocalPlayer:SetAttribute("HomePortal", nil)
	advance(0.6)
end

----------------------------------------------------------------------------------------------------
-- PetCard on its own + PetController's cards
----------------------------------------------------------------------------------------------------
S.client_p4pets_cards = guarded("client_p4pets_cards", function()
	local PetCard = moduleAt("client", "UI/PetCard")
	if not T.check(PetCard ~= nil and type(PetCard.New) == "function", "PetCard loads (client/UI/PetCard.lua) with PetCard.New") then
		return
	end
	Mock.SetViewport(1920, 1080)
	advance(0.2)
	local part = Instance.new("Part")
	part.Anchored = true
	part.Parent = workspace
	local tapped = 0
	local card = PetCard.New(part, "Follower", 2.5, { OnEvolve = function()
		tapped = tapped + 1
	end })
	local gui = card.Gui
	T.check(gui ~= nil and gui:IsA("BillboardGui") and gui.Adornee == part, "PetCard.New makes a BillboardGui adorned to the part")
	T.check(gui.Parent == LocalPlayer:FindFirstChildOfClass("PlayerGui"), "...in the PlayerGui (so the EVOLVE! pill can be tapped)", tostring(gui.Parent))
	T.check(gui.Size.X.Scale == 0 and gui.Size.Y.Scale == 0 and gui.Size.X.Offset == 96, "...pixel-sized, 96 px wide at 1080p", tostring(gui.Size))
	T.check(gui.LightInfluence == 0 and gui.MaxDistance == 90 and abs(gui.StudsOffset.Y - 2.5) < 1e-6, "...LightInfluence 0, MaxDistance 90 (own follower), StudsOffset = heightStuds")
	card:SetLevel(12, 0, false)
	local lv = levelLabel(gui)
	T.check(lv and lv.Text == "Lv 12" and lv.TextSize >= 22 and stroked(lv) and not lv.TextScaled, "\"Lv 12\" at >= 22 px with a dark stroke", lv and fmt("'%s' %d px", lv.Text, lv.TextSize) or "no label")
	local plate = gui:FindFirstChild("Plate")
	T.check(plate and plate.BackgroundTransparency <= 0.25, "...on a solid plate")
	T.check(barShown(gui, "Xp") and not barShown(gui, "Hp") and not barShown(gui, "Special") and not barShown(gui, "Timer"), "Follower mode: level + XP bar only")
	local xpBar = plate:FindFirstChild("Xp")
	T.eq(xpBar and xpBar.AbsoluteSize.Y, 6, "XP bar 6 px at 1080p")
	-- fills: written only when they moved by more than 0.004
	local fill = xpBar.Fill
	local writes = 0
	local conn = fill:GetPropertyChangedSignal("Size"):Connect(function()
		writes = writes + 1
	end)
	card:SetXp(0.5)
	card:SetXp(0.502)
	card:SetXp(0.5039)
	card:SetXp(0.5)
	T.eq(writes, 1, "a fill is written only when it moved by > 0.004 (4 calls, 1 write)")
	card:SetXp(0.51)
	T.eq(writes, 2, "...and written again once it moved enough")
	conn:Disconnect()
	T.check(abs(fillOf(gui, "Xp") - 0.51) < 1e-6, "XP fill = the fraction given")
	-- stars + EVOLVE! pill
	local hBefore = gui.Size.Y.Offset
	card:SetLevel(20, 1, true)
	local badge = gui:FindFirstChild("StarBadge")
	local stars = badge and badge:FindFirstChild("Stars")
	T.check(badge and badge.Visible and stars and stars.Text == "\226\152\133", "stage 1: one gold star (U+2605) on the card", stars and stars.Text or "none")
	local pill = gui:FindFirstChild("Evolve")
	T.check(pill and pill:IsA("TextButton") and pill.Visible and pill.Active and pill.Text == "EVOLVE!" and pill.TextSize >= 20, "ready: a gold \"EVOLVE!\" pill (an Active button, >= 20 px)")
	T.check(gui.Size.Y.Offset > hBefore and gui.Size.X.Offset == 96, "...above the plate (the card grows upwards, width kept)", fmt("%d -> %d px", hBefore, gui.Size.Y.Offset))
	Mock.FireSignal(pill, "Activated")
	T.eq(tapped, 1, "a tap on the pill calls OnEvolve")
	card:SetLevel(55, 2, false)
	T.check(stars.Text == "\226\152\133\226\152\133" and not pill.Visible, "stage 2: two stars; not ready: the pill is gone")
	advance(1.0)
	T.eq(stars.Text, "\226\152\133\226\152\133", "(stars stay)")
	-- modes
	card:SetMode("Unit")
	T.check(barShown(gui, "Hp") and barShown(gui, "Special") and barShown(gui, "Xp") and gui.MaxDistance == 140, "Unit mode: level + HP + SPECIAL + XP, MaxDistance 140")
	T.eq(plate:FindFirstChild("Hp").AbsoluteSize.Y, 9, "HP bar 9 px at 1080p")
	card:SetHp(0.25)
	card:SetSpecial(1, true)
	T.check(abs(fillOf(gui, "Hp") - 0.25) < 1e-6 and abs(fillOf(gui, "Special") - 1) < 1e-6, "SetHp / SetSpecial fill their bars")
	local own = plate.Hp.Fill.BackgroundColor3
	card:SetMode("Enemy")
	local enemy = plate.Hp.Fill.BackgroundColor3
	T.check(barShown(gui, "Hp") and not barShown(gui, "Special") and not barShown(gui, "Xp") and own.G > own.R and enemy.R > enemy.G, "Enemy mode: level + HP, red instead of green")
	card:SetMode("Other")
	T.check(not barShown(gui, "Hp") and not barShown(gui, "Xp") and gui.MaxDistance == 60, "Other mode: level only, MaxDistance 60")
	card:SetMode("Training")
	card:SetTimer(0.4, "2:10")
	local tt = plate:FindFirstChild("TimerText")
	T.check(barShown(gui, "Timer") and tt and tt.Visible and tt.Text == "2:10" and tt.TextSize >= 18 and abs(fillOf(gui, "Timer") - 0.4) < 1e-6, "Training mode: + a purple timer bar with \"2:10\" (>= 18 px)")
	local live = PetCard.Count and PetCard.Count() or 0
	card:Destroy()
	card:Destroy()
	T.check(gui.Parent == nil and (not PetCard.Count or PetCard.Count() == live - 1), "Destroy removes the card (twice is safe)")
	part:Destroy()

	-- PetController: own followers
	local pc = PC()
	if not T.check(pc ~= nil and type(pc.GetCards) == "function", "PetController.GetCards exists (debug helper)") then
		return
	end
	resetLocal()
	Mock.Teleport(LocalPlayer, Vector3.new(0, 40, 0))
	local need = TycoonCatalog.XpToNext(12)
	sync({ [COMMON] = { Level = 12, Xp = math.floor(need / 4) }, [COMMON2] = { Level = 20, Xp = 0 } })
	LocalPlayer:SetAttribute("EquippedPets", COMMON .. "," .. COMMON2)
	advance(1.5)
	local mine = cardsOf(LocalPlayer.UserId)
	T.eq(#mine, 2, "own followers each get a pet card")
	local byKey = {}
	for _, c in ipairs(mine) do
		byKey[c.Key] = c
	end
	local c1, c2 = byKey[COMMON], byKey[COMMON2]
	if c1 and c2 then
		local l1 = levelLabel(c1.Gui)
		T.check(l1.Text == "Lv 12" and l1.TextSize >= 22 and stroked(l1), "own card: \"Lv 12\" (State.PetLevel) at >= 22 px with a stroke", l1.Text)
		T.check(abs(fillOf(c1.Gui, "Xp") - math.floor(need / 4) / need) < 0.005, "...XP fill = xp / TycoonCatalog.XpToNext(level)", tostring(fillOf(c1.Gui, "Xp")))
		T.check(c1.Shown and c1.Gui.Adornee ~= nil and c1.Gui.Adornee:IsDescendantOf(workspace), "...shown, floating over the follower")
		local why = {}
		for _, fi in ipairs(infoOf(LocalPlayer)) do
			why[#why + 1] = fmt("%s Lv %s stage %s want %s", tostring(fi.Key), tostring(fi.Level), tostring(fi.Stage), tostring(fi.Want))
		end
		T.check(c2.Gui.Evolve.Visible and not c1.Gui.Evolve.Visible, "level 20 and not evolved: the EVOLVE! pill shows (level 12 has none)", table.concat(why, " | "))
		-- a tap opens the Pets panel on that pet
		local MC = KC.M.MenuController or moduleAt("client", "Controllers/MenuController")
		local opened = nil
		if MC then
			local real = MC.Open
			MC.Open = function(panel, args)
				opened = { panel, args }
			end
			Mock.FireSignal(c2.Gui.Evolve, "Activated")
			MC.Open = real
		end
		T.check(opened and opened[1] == "Pets" and type(opened[2]) == "table" and opened[2].Key == COMMON2, "a tap on EVOLVE! opens the Pets panel on that pet", opened and tostring(opened[1]) or "nothing opened")
		-- level-up through a ProfileSync
		sync({ [COMMON] = { Level = 13, Xp = 0 }, [COMMON2] = { Level = 20, Xp = 0 } })
		T.check(l1.Text == "Lv 13" and fillOf(c1.Gui, "Xp") < 0.005, "a ProfileSync refreshes the card (Lv 13, empty bar)", l1.Text)
		-- no writes while nothing changes
		local writes2 = 0
		local conns = {}
		for _, c in ipairs(mine) do
			for _, d in ipairs(c.Gui:GetDescendants()) do
				if d:IsA("GuiObject") then
					conns[#conns + 1] = d:GetPropertyChangedSignal("Size"):Connect(function()
						writes2 = writes2 + 1
					end)
				end
				if d:IsA("TextLabel") then
					conns[#conns + 1] = d:GetPropertyChangedSignal("Text"):Connect(function()
						writes2 = writes2 + 1
					end)
				end
			end
		end
		advance(2)
		sync({ [COMMON] = { Level = 13, Xp = 0 }, [COMMON2] = { Level = 20, Xp = 0 } })
		for _, cn in ipairs(conns) do
			cn:Disconnect()
		end
		T.eq(writes2, 0, "no card write per frame, none for an unchanged ProfileSync")
		-- InBattle hides the cards
		LocalPlayer:SetAttribute("InBattle", "smoke-battle")
		advance(0.3)
		local hidden = true
		for _, c in ipairs(cardsOf(LocalPlayer.UserId)) do
			hidden = hidden and not c.Gui.Enabled
		end
		T.check(hidden, "cards are hidden while the owner is InBattle (the followers are parked)")
		LocalPlayer:SetAttribute("InBattle", nil)
		advance(0.5)
		local back = #cardsOf(LocalPlayer.UserId) == 2
		for _, c in ipairs(cardsOf(LocalPlayer.UserId)) do
			back = back and c.Gui.Enabled
		end
		T.check(back, "...and back after the battle")
	end

	-- another player: level (and stars) from EquippedInfo only
	local other = Mock.AddPlayer("CardFriend", 7101)
	advance(0.6)
	Mock.Teleport(other, root().Position + Vector3.new(20, 0, 0))
	other:SetAttribute("EquippedInfo", "23:1,5:0")
	other:SetAttribute("EquippedPets", COMMON .. "," .. EPIC)
	advance(1.5)
	local theirs = cardsOf(other.UserId)
	T.eq(#theirs, 2, "another player's followers get cards")
	local o1, o2 = nil, nil
	for _, c in ipairs(theirs) do
		if c.Key == COMMON then
			o1 = c
		else
			o2 = c
		end
	end
	if o1 and o2 then
		T.check(levelLabel(o1.Gui).Text == "Lv 23" and o1.Gui.StarBadge.Visible and levelLabel(o2.Gui).Text == "Lv 5" and not o2.Gui.StarBadge.Visible,
			"...\"Lv 23\" with a star and \"Lv 5\" from EquippedInfo \"23:1,5:0\"", levelLabel(o1.Gui).Text .. " / " .. levelLabel(o2.Gui).Text)
		T.check(not barShown(o1.Gui, "Xp") and not o1.Gui.Evolve.Visible and o1.Gui.MaxDistance == 60, "...level only (no XP bar, no EVOLVE!), MaxDistance 60")
		other:SetAttribute("EquippedInfo", "24:1,5:0")
		advance(0.3)
		T.eq(levelLabel(o1.Gui).Text, "Lv 24", "...and follows EquippedInfo changes")
	end
	Mock.Teleport(other, root().Position + Vector3.new(90, 0, 0))
	advance(1.2)
	T.eq(#cardsOf(other.UserId), 0, "another player's cards go beyond 60 studs")
	Mock.RemovePlayer(other)
	advance(0.6)

	-- 6 players x 3 pets: at most 12 other cards, nearest first; one root write per pet unchanged
	local trio = COMMON .. "," .. COMMON2 .. "," .. EPIC
	LocalPlayer:SetAttribute("EquippedPets", trio)
	local others = {}
	for i = 1, 5 do
		others[i] = Mock.AddPlayer("Crowd" .. i, 7200 + i)
	end
	advance(0.8)
	local centre = root().Position
	for i, p in ipairs(others) do
		local a = i / #others * math.pi * 2
		Mock.Teleport(p, centre + Vector3.new(math.cos(a) * (10 + i * 6), 0, math.sin(a) * (10 + i * 6)))
		p:SetAttribute("EquippedInfo", "3:0,4:0,5:1")
		p:SetAttribute("EquippedPets", trio)
	end
	advance(4)
	local otherCards, nearest = 0, true
	local farthestWithCard = 0
	for i, p in ipairs(others) do
		local n = #cardsOf(p.UserId)
		otherCards = otherCards + n
		if n > 0 then
			farthestWithCard = i
		end
		if i <= 4 and n ~= 3 then
			nearest = false
		end
	end
	T.check(otherCards == 12 and nearest and farthestWithCard == 4, "6 players x 3 pets: 12 other players' cards, the nearest players first", fmt("%d cards, farthest player with cards #%d", otherCards, farthestWithCard))
	T.eq(#cardsOf(LocalPlayer.UserId), 3, "...plus the 3 own cards")
	local stats = pc.GetMoveStats()
	local models = 0
	for _, p in ipairs(others) do
		models = models + #modelsOf(p)
	end
	models = models + #modelsOf(LocalPlayer)
	T.check(stats.Pivot == 0 and stats.Rigid == models and models == 18, "...one root write per pet per frame (cards add none)", fmt("rigid %d, pivot %d, models %d", stats.Rigid, stats.Pivot, models))
	for _, p in ipairs(others) do
		Mock.RemovePlayer(p)
	end
	resetLocal()
	KC.flushErrors("p4pets cards")
	KC.flushWarnings("p4pets cards")
end)

----------------------------------------------------------------------------------------------------
-- the trailing formation
----------------------------------------------------------------------------------------------------
S.client_p4pets_follow = guarded("client_p4pets_follow", function()
	resetLocal()
	local keys = { COMMON, COMMON2, EPIC }
	for n = 1, 3 do
		local list = {}
		for i = 1, n do
			list[i] = keys[i]
		end
		Mock.Teleport(LocalPlayer, Vector3.new(0, 40, 0)) -- facing -Z
		LocalPlayer:SetAttribute("EquippedPets", table.concat(list, ","))
		advance(3)
		local mine = modelsOf(LocalPlayer)
		local r = root().Position
		local ok, detail = #mine == n, {}
		-- Phase 5 (3.8): size-aware windows: each pet rests at its slot |slot| +- 1.5 (FormationFor of the measured widths)
		local slotDist = {}
		for _, i in ipairs(infoOf(LocalPlayer)) do
			if i.Model then
				slotDist[i.Model] = sqrt((i.Side or 0) ^ 2 + (i.Back or 0) ^ 2)
			end
		end
		local backMax = 0
		for _, m in ipairs(mine) do
			local off = m:GetPivot().Position - r
			local horiz = sqrt(off.X * off.X + off.Z * off.Z)
			local want = slotDist[m] or 5
			backMax = max(backMax, want)
			detail[#detail + 1] = fmt("%.1f (slot %.1f) back %.1f up %.1f", horiz, want, off.Z, off.Y)
			-- behind = +Z for an owner facing -Z; never beside (|side| < back)
			if abs(horiz - want) > 1.5 or off.Y < -1 or off.Y > 5 or off.Z < 2 or abs(off.X) > off.Z then
				ok = false
			end
		end
		T.check(ok, n .. " pet(s) at rest: at their slot (|slot| +- 1.5) BEHIND the owner (not beside), up to 5 above", table.concat(detail, "; "))
		-- walk along the facing direction, then across it
		local worst, lag = -1e9, 0
		for _, dir in ipairs({ Vector3.new(0, 0, -1), Vector3.new(1, 0, 0) }) do
			local start = root().Position
			for step = 1, 30 do
				Mock.Teleport(LocalPlayer, start + dir * (step * 1.2)) -- 24 studs/s
				advance(0.05)
				if step * 0.05 >= 0.5 then
					local o = root().Position
					for _, m in ipairs(mine) do
						local d = m:GetPivot().Position - o
						worst = max(worst, d.X * dir.X + d.Z * dir.Z)
					end
				end
			end
			advance(0.1)
			for _, m in ipairs(mine) do
				lag = max(lag, (m:GetPivot().Position - root().Position).Magnitude)
			end
			advance(3)
		end
		T.check(worst <= 0.5, n .. " pet(s) walking: never ahead of the owner along the travel direction (<= +0.5 studs)", fmt("furthest ahead %.2f studs", worst))
		T.check(lag <= backMax + 9, n .. " pet(s): keep up with a walking owner (lag <= back + 9)", fmt("%.1f studs (slot %.1f)", lag, backMax))
		local settle = 0
		for _, m in ipairs(mine) do
			local off = m:GetPivot().Position - root().Position
			settle = max(settle, sqrt(off.X * off.X + off.Z * off.Z) - (slotDist[m] or 5))
		end
		T.check(settle <= 1, n .. " pet(s): settle back at their slots (<= |slot| + 1)", fmt("%.1f studs past the slot", settle))
	end
	resetLocal()
	KC.flushErrors("p4pets follow")
	KC.flushWarnings("p4pets follow")
end)

----------------------------------------------------------------------------------------------------
-- evolved followers
----------------------------------------------------------------------------------------------------
local function partsOf(model)
	return Mock.CountDescendants(model, "BasePart")
end

S.client_p4pets_evolved = guarded("client_p4pets_evolved", function()
	local budget = CONTRACT.v3.partBudget
	resetLocal()
	Mock.Teleport(LocalPlayer, Vector3.new(0, 40, 0))
	sync({ [COMMON] = { Level = 25, Xp = 0 }, [EPIC] = { Level = 55, Xp = 0 }, [LEGEND] = { Level = 3, Xp = 0 } },
		{ [COMMON] = { Evo = 1 }, [EPIC] = { Evo = 2 } })
	LocalPlayer:SetAttribute("EquippedPets", COMMON .. "," .. EPIC .. "," .. LEGEND)
	advance(4)
	local info = {}
	for _, i in ipairs(infoOf(LocalPlayer)) do
		info[i.Key] = i
	end
	local e1, e2, n0 = info[COMMON], info[EPIC], info[LEGEND]
	if T.check(e1 and e2 and n0 and e1.Model and e2.Model and n0.Model, "three own followers built (stage 1, stage 2, not evolved)") then
		local p1, p2, p0 = partsOf(e1.Model), partsOf(e2.Model), partsOf(n0.Model)
		-- the > petLow floor counts voxels; a Blender-mesh pet (ML_Mesh, recipe 4.9) only has to stay under the cap
		local floor1 = e1.Model:GetAttribute("ML_Mesh") == true and 0 or budget.petLow
		T.check(e1.Stage == 1 and e1.Model:GetAttribute("PB_Detail") == "Low" and p1 > floor1 and p1 <= budget.petEvoLow,
			"own evolved follower (stage 1): Low detail within petEvoLow " .. budget.petEvoLow, fmt("stage %s, %s, %d parts", tostring(e1.Stage), tostring(e1.Model:GetAttribute("PB_Detail")), p1))
		T.check(e2.Stage == 2 and e2.Model:GetAttribute("PB_Detail") == "Low" and p2 <= budget.petEvo2Low,
			"own second evolution (stage 2, Epic): Low detail within petEvo2Low " .. budget.petEvo2Low, fmt("stage %s, %d parts", tostring(e2.Stage), p2))
		T.check(n0.Stage == 0 and n0.Model:GetAttribute("PB_Detail") == "High" and p0 <= budget.petHigh, "an own pet that never evolved stays High detail", fmt("%d parts", p0))
		-- Phase 5 (3.8): the slots come from the measured widths (FormationFor): a wider evolved pet stands further out
		T.check((e1.Width or 0) > (n0.Width or 0) and (e2.Width or 0) > (n0.Width or 0) and e2.Back > n0.Back and math.abs(e1.Side or 0) > math.abs(n0.Side or 0) - 1e-6,
			"evolved followers are measured wider and get roomier slots (FormationFor: the biggest behind the right one)",
			fmt("widths %.1f / %.1f / %.1f, back %.1f / %.1f / %.1f", e1.Width or 0, e2.Width or 0, n0.Width or 0, e1.Back or 0, e2.Back or 0, n0.Back or 0))
		local total = p1 + p2 + p0
		T.check(total <= budget.petEvoLow + budget.petEvo2Low + budget.petHigh, "own followers' parts stay within the evolved budgets", total .. " parts")
		-- a stage 2 for a Common is capped at its first evolution
		sync({ [COMMON] = { Level = 60, Xp = 0 }, [EPIC] = { Level = 55, Xp = 0 }, [LEGEND] = { Level = 3, Xp = 0 } },
			{ [COMMON] = { Evo = 2 }, [EPIC] = { Evo = 2 } })
		advance(1.5)
		for _, i in ipairs(infoOf(LocalPlayer)) do
			if i.Key == COMMON then
				T.eq(i.Stage, 1, "a Common never shows a second evolution (PetCatalog.MaxEvolution)")
			end
		end
	end
	-- other players: evolved only within 40 studs and at most 6 (nearest first)
	LocalPlayer:SetAttribute("EquippedPets", "")
	local others = {}
	for i = 1, 4 do
		others[i] = Mock.AddPlayer("EvoFriend" .. i, 7300 + i)
	end
	advance(0.8)
	local centre = root().Position
	for i, p in ipairs(others) do
		Mock.Teleport(p, centre + Vector3.new(8 + i * 6, 0, 0)) -- 14, 20, 26, 32 studs
		p:SetAttribute("EquippedInfo", "30:1,30:1,30:1")
		p:SetAttribute("EquippedPets", COMMON .. "," .. COMMON2 .. "," .. COMMON)
	end
	advance(5)
	local evolved, perPlayer = 0, {}
	for i, p in ipairs(others) do
		perPlayer[i] = 0
		for _, inf in ipairs(infoOf(p)) do
			if inf.Model and inf.Stage > 0 then
				evolved = evolved + 1
				perPlayer[i] = perPlayer[i] + 1
				T.check(partsOf(inf.Model) <= budget.petEvoLow, "(others' evolved model within petEvoLow)", tostring(partsOf(inf.Model)))
			end
		end
	end
	T.check(evolved == 6 and perPlayer[1] == 3 and perPlayer[2] == 3 and perPlayer[3] == 0 and perPlayer[4] == 0,
		"other players' evolved models: at most 6 at a time, the nearest first", fmt("%d evolved (%d/%d/%d/%d)", evolved, perPlayer[1], perPlayer[2], perPlayer[3], perPlayer[4]))
	local starred = true
	for _, c in ipairs(cardsOf(others[3].UserId)) do
		starred = starred and c.Gui.StarBadge.Visible
	end
	T.check(#cardsOf(others[3].UserId) == 3 and starred, "...the others keep the normal Low model with a star on the card")
	for _, inf in ipairs(infoOf(others[3])) do
		T.check(inf.Model and inf.Model:GetAttribute("PB_Detail") == "Low" and partsOf(inf.Model) <= budget.petLow, "(normal Low model)", inf.Model and tostring(partsOf(inf.Model)) or "none")
		break
	end
	-- beyond 40 studs nobody is evolved
	Mock.Teleport(others[1], centre + Vector3.new(0, 0, 55))
	Mock.Teleport(others[2], centre + Vector3.new(0, 0, -55))
	Mock.Teleport(others[3], centre + Vector3.new(-50, 0, 0))
	Mock.Teleport(others[4], centre + Vector3.new(-50, 0, 10))
	advance(4)
	local far = 0
	for _, p in ipairs(others) do
		for _, inf in ipairs(infoOf(p)) do
			if inf.Model and inf.Stage > 0 then
				far = far + 1
			end
		end
	end
	T.eq(far, 0, "beyond 40 studs other players' pets use the normal Low model")
	for _, p in ipairs(others) do
		Mock.RemovePlayer(p)
	end
	resetLocal()
	KC.flushErrors("p4pets evolved")
	KC.flushWarnings("p4pets evolved")
end)

----------------------------------------------------------------------------------------------------
-- PlayEvolution parks and restores the follower
----------------------------------------------------------------------------------------------------
S.client_p4pets_evolution = guarded("client_p4pets_evolution", function()
	local pc = PC()
	if not T.check(pc and type(pc.PlayEvolution) == "function", "PetController.PlayEvolution exists") then
		return
	end
	resetLocal()
	Mock.Teleport(LocalPlayer, Vector3.new(0, 40, 0))
	sync({ [COMMON] = { Level = 20, Xp = 0 }, [COMMON2] = { Level = 4, Xp = 0 } })
	LocalPlayer:SetAttribute("EquippedPets", COMMON .. "," .. COMMON2)
	advance(2)
	local release = pc.PlayEvolution(COMMON, 1, { Seconds = 6 })
	advance(0.2)
	local function get(key)
		for _, i in ipairs(infoOf(LocalPlayer)) do
			if i.Key == key then
				return i
			end
		end
	end
	local a, b = get(COMMON), get(COMMON2)
	T.check(a and a.Parked and a.Model == nil and a.Card == nil, "PlayEvolution parks the follower of that key (model and card gone)")
	T.check(b and not b.Parked and b.Model ~= nil, "...the other followers stay")
	-- the server's stage arrives meanwhile: still parked
	sync({ [COMMON] = { Level = 20, Xp = 0 }, [COMMON2] = { Level = 4, Xp = 0 } }, { [COMMON] = { Evo = 1 } })
	advance(2)
	a = get(COMMON)
	T.check(a.Parked and a.Model == nil, "...and keeps it parked while the animation plays")
	local spot = root().Position + Vector3.new(0, 1, -5.5)
	release(spot)
	advance(0.05)
	a = get(COMMON)
	T.check(not a.Parked, "release() ends the park")
	advance(0.3)
	a = get(COMMON)
	T.check(a.Model ~= nil and a.Stage == 1, "...the follower is rebuilt evolved (stage 1)", tostring(a.Stage))
	T.check(a.Card ~= nil and levelLabel(a.Card).Text == "Lv 20" and a.Card.StarBadge.Visible and not a.Card.Evolve.Visible, "...with a star and without the EVOLVE! pill")
	advance(3)
	local d = a.Model and (a.Model:GetPivot().Position - root().Position).Magnitude or 99
	T.check(d < 9, "...flying back into its slot", fmt("%.1f studs", d))
	-- a park that is never released ends by itself
	local _ = pc.PlayEvolution(COMMON2, 1, 0.5)
	advance(0.2)
	T.check(get(COMMON2).Parked, "a park with a time limit ...")
	advance(1.2)
	T.check(not get(COMMON2).Parked and get(COMMON2).Model ~= nil, "...ends by itself")
	-- a PlayEvolution stage State never confirms (a /reset, a pet that came back fresh) must not stick for the session:
	-- the EVOLVE! pill and the plain model come back once the animation is long over (State wins)
	sync({ [COMMON] = { Level = 20, Xp = 0 }, [COMMON2] = { Level = 20, Xp = 0 } }, { [COMMON] = { Evo = 1 } })
	local _2 = pc.PlayEvolution(COMMON2, 1, 0.5)
	advance(1.5)
	local c2 = get(COMMON2)
	T.check(c2 and not c2.Parked and c2.Want == 1, "an unconfirmed PlayEvolution stage shows right after the animation (State may lag)", c2 and tostring(c2.Want))
	advance(20)
	sync({ [COMMON] = { Level = 20, Xp = 0 }, [COMMON2] = { Level = 20, Xp = 0 } }, { [COMMON] = { Evo = 1 } })
	advance(1.5)
	c2 = get(COMMON2)
	T.check(c2 and c2.Want == 0 and c2.Stage == 0 and c2.Card ~= nil and c2.Card.Evolve.Visible,
		"...but State wins long after it: stage 0 again and the EVOLVE! pill is back (level 20, not evolved)",
		c2 and fmt("want %s stage %s pill %s", tostring(c2.Want), tostring(c2.Stage), tostring(c2.Card and c2.Card.Evolve.Visible)))
	resetLocal()
	KC.flushErrors("p4pets evolution")
	KC.flushWarnings("p4pets evolution")
end)

----------------------------------------------------------------------------------------------------
-- the home portal dive
----------------------------------------------------------------------------------------------------
S.client_p4pets_portal = guarded("client_p4pets_portal", function()
	resetLocal()
	Mock.Teleport(LocalPlayer, Vector3.new(0, 40, 0))
	LocalPlayer:SetAttribute("EquippedPets", COMMON .. "," .. COMMON2)
	advance(3)
	local portal = root().Position + Vector3.new(0, -3, -6)
	LocalPlayer:SetAttribute("HomePortal", fmt("%.2f,%.2f,%.2f,0,%d", portal.X, portal.Y, portal.Z, 99999))
	advance(0.3)
	-- walk into the portal
	local start = root().Position
	for step = 1, 10 do
		Mock.Teleport(LocalPlayer, start:Lerp(portal + Vector3.new(0, 3, 0), step / 10))
		advance(0.05)
	end
	-- the server teleports home and clears the portal in the same step
	local home = Vector3.new(600, 40, 600)
	Mock.Teleport(LocalPlayer, home)
	LocalPlayer:SetAttribute("HomePortal", nil)
	LocalPlayer:SetAttribute("PortalArrived", 1)
	advance(0.15)
	local inf = infoOf(LocalPlayer)
	local diving = #inf == 2 and inf[1].Diving
	local towards = true
	for _, i in ipairs(inf) do
		if i.Model then
			local p = i.Model:GetPivot().Position
			towards = towards and (p - portal).Magnitude < 8 and (p - home).Magnitude > 100
		end
	end
	T.check(diving and towards, "the portal was used: the followers dive into the portal centre (they do not snap home)")
	advance(0.4)
	advance(1.5)
	inf = infoOf(LocalPlayer)
	local homeOk = #inf == 2 and not inf[1].Diving
	for _, i in ipairs(inf) do
		homeOk = homeOk and i.Model ~= nil and (i.Model:GetPivot().Position - root().Position).Magnitude < 9
	end
	T.check(homeOk, "...then pop out behind the owner at home")
	-- a plain teleport (no portal) snaps
	Mock.Teleport(LocalPlayer, Vector3.new(-400, 40, 0))
	advance(0.1)
	inf = infoOf(LocalPlayer)
	local snapped = #inf == 2 and not inf[1].Diving
	for _, i in ipairs(inf) do
		snapped = snapped and i.Model ~= nil and (i.Model:GetPivot().Position - root().Position).Magnitude < 12
	end
	T.check(snapped, "a teleport without the portal snaps the followers (no dive)")
	resetLocal()
	KC.flushErrors("p4pets portal")
	KC.flushWarnings("p4pets portal")
end)

----------------------------------------------------------------------------------------------------
-- phone
----------------------------------------------------------------------------------------------------
S.client_p4pets_mobile = guarded("client_p4pets_mobile", function()
	local PetCard = moduleAt("client", "UI/PetCard")
	if not T.check(PetCard ~= nil, "PetCard loads on the phone") then
		return
	end
	for _, size in ipairs({ { 390, 844 }, { 844, 390 } }) do
		Mock.SetViewport(size[1], size[2])
		advance(0.2)
		local card = PetCard.New(nil, "Unit", 2)
		card:SetLevel(57, 1, true)
		local lv = levelLabel(card.Gui)
		local stars = card.Gui.StarBadge.Stars
		local pill = card.Gui.Evolve
		local small = min(lv.TextSize, stars.TextSize, pill.TextSize)
		T.check(small >= 14 and lv.TextSize >= 17, fmt("%dx%d: card texts >= 14 px (Lv %d, stars %d, EVOLVE! %d)", size[1], size[2], lv.TextSize, stars.TextSize, pill.TextSize))
		T.check(card.Gui.Size.X.Offset <= 96 and card.Gui.Size.Y.Offset <= 120, fmt("%dx%d: the card stays compact", size[1], size[2]), tostring(card.Gui.Size))
		card:Destroy()
	end
	Mock.SetViewport(390, 844)
	advance(0.2)
	KC.flushErrors("p4pets mobile")
	KC.flushWarnings("p4pets mobile")
end)

return S
