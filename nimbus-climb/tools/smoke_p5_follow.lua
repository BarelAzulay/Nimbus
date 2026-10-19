-- smoke_p5_follow.lua: the Phase 5 followers and the Wild look (ARCHITECTURE_V3.md "Phase 5 build contract" 3.7, 3.8,
-- C13; homefx+pets, wave 3). Loaded by tools/smoke.py in the client world:
--   client_p5follow_formation  PetController.FormationFor on 7 width mixes == the 3.8 formulas (+-0.05) and the
--                              prototype's slots (1 small, 3 small, 3 big, small + evolved + big), the smaller pet on the
--                              left whatever the order, ties keep the order, junk widths, pure (no Instances)
--   client_p5follow_motion     the real PetController with 3 followers of different sizes (a small pet, an evolved and
--                              a second-evolution pet): at rest |slot| +- 1.5 and the camera channel >= 1.0; walking 16 /
--                              24 / 27 studs/s straight, a 90-degree turn and a reverse: gaps pet-pet and pet-owner >= 0
--                              at every sample, lag <= back + 9, never ahead (<= 0.5 after 0.6 s straight), settle <=
--                              |slot| + 1 afterwards
--   client_p5wild              PetBuilder: PB_Evolved = the built stage (0 / 1 / 2, a Common asked for 2 gets 1),
--                              opts.Wild = { Tint, Eyes }: Neon eyes in the Eyes colour, a darker body, PB_Wild, the
--                              cached template untouched (the next plain build has its own colours)
-- Plain Lua 5.1 syntax only; deterministic (fixed widths, scripted owner paths, the mock clock).

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local KC = _G.KC
local S = {}

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local abs, max, min, sqrt = math.abs, math.max, math.min, math.sqrt
local fmt = string.format

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

local function petOf(rarity, skip)
	for _, def in ipairs(PetCatalog.Pets) do
		if def.Rarity == rarity and not def.EventOnly and def.Id ~= skip then
			return def.Id
		end
	end
	return nil
end

-- the 3.8 formulas written out again (the test's own copy)
local F = { R = 1.5, G = 2.5, P = 1.0, C = 1.2, D = 0.35 }
local function expected(widths)
	local n = #widths
	local order = {}
	for i = 1, n do
		order[i] = i
	end
	table.sort(order, function(a, b)
		if widths[a] ~= widths[b] then
			return widths[a] < widths[b]
		end
		return a < b
	end)
	local out = {}
	if n == 1 then
		local w = widths[1]
		out[1] = { F.C + w / 2, F.R + F.G + w / 2 - F.D * w / 2 }
		return out
	end
	local a, b = order[1], order[2]
	local row = F.R + F.G + max(widths[a], widths[b]) / 2 - F.D * min(widths[a], widths[b]) / 2
	out[a] = { -(F.C + widths[a] / 2), row }
	out[b] = { F.C + widths[b] / 2, row }
	if n == 3 then
		local c = order[3]
		out[c] = { F.C + widths[c] / 2, row + widths[b] / 2 + F.P + widths[c] / 2 }
	end
	return out
end

local function sameSlots(got, want, tol)
	if type(got) ~= "table" or #got ~= #want then
		return false, "count " .. tostring(type(got) == "table" and #got or got)
	end
	local parts = {}
	local ok = true
	for i = 1, #want do
		local g, w = got[i], want[i]
		if type(g) ~= "table" or abs(g[1] - w[1]) > tol or abs(g[2] - w[2]) > tol then
			ok = false
		end
		parts[#parts + 1] = type(g) == "table" and fmt("(%.2f, %.2f)", g[1], g[2]) or "?"
	end
	return ok, table.concat(parts, " ")
end

----------------------------------------------------------------------------------------------------
S.client_p5follow_formation = guarded("client_p5follow_formation", function()
	local pc = PC()
	if not T.check(pc ~= nil and type(pc.FormationFor) == "function", "PetController.FormationFor exists (contract 3.8)") then
		return
	end
	local before = #game:GetDescendants()
	local mixes = {
		{ 3.2 },
		{ 8.5 },
		{ 3.2, 4.9 },
		{ 4.9, 3.2 },
		{ 3.2, 3.2, 3.2 },
		{ 8.5, 8.5, 8.5 },
		{ 8.5, 3.2, 4.9 },
	}
	for _, w in ipairs(mixes) do
		local ok, detail = sameSlots(pc.FormationFor(w), expected(w), 0.05)
		T.check(ok, "FormationFor {" .. table.concat(w, ", ") .. "} == the 3.8 formulas (+-0.05)", detail)
	end
	-- the prototype's slots (p5design home 6)
	local proto = {
		{ { 3.2 }, { { 2.8, 5.0 } } },
		{ { 3.2, 3.2, 3.2 }, { { -2.8, 5.0 }, { 2.8, 5.0 }, { 2.8, 9.2 } } },
		{ { 8.5, 8.5, 8.5 }, { { -5.5, 6.8 }, { 5.5, 6.8 }, { 5.5, 16.3 } } },
		{ { 3.2, 4.9, 8.5 }, { { -2.8, 5.9 }, { 3.7, 5.9 }, { 5.5, 13.6 } } },
	}
	for _, row in ipairs(proto) do
		local ok, detail = sameSlots(pc.FormationFor(row[1]), row[2], 0.06)
		T.check(ok, "FormationFor {" .. table.concat(row[1], ", ") .. "} == the prototype's slots", detail)
	end
	local two = pc.FormationFor({ 4.9, 3.2 })
	T.check(two[2][1] < 0 and two[1][1] > 0, "2 pets: the smaller one is on the left whatever the order")
	local junk = pc.FormationFor({ "x", -1, 0 / 0 })
	local ok3 = sameSlots(junk, expected({ 3.2, 3.2, 3.2 }), 0.05)
	T.check(ok3, "junk widths count as the stage-0 median (3.2)")
	T.eq(#pc.FormationFor({}), 0, "no pets -> no slots")
	T.eq(#pc.FormationFor(nil), 0, "nil -> no slots")
	local a1, a2 = pc.FormationFor({ 8.5, 3.2, 4.9 }), pc.FormationFor({ 8.5, 3.2, 4.9 })
	T.check(sameSlots(a1, a2, 0) and #game:GetDescendants() == before, "FormationFor is pure (same answer twice, no Instances)")
	-- every slot behind the owner and outside the camera channel
	local inChannel = false
	for _, w in ipairs(mixes) do
		for i, s in ipairs(pc.FormationFor(w)) do
			if abs(s[1]) - w[i] / 2 < 1.2 - 1e-6 or s[2] <= 0 then
				inChannel = true
			end
		end
	end
	T.check(not inChannel, "every slot is behind the owner with the pet's inner edge >= 1.2 studs off the centre line")
	KC.flushErrors("p5follow formation")
end)

----------------------------------------------------------------------------------------------------
-- the follow motion through the real PetController (own followers, the mock clock)
----------------------------------------------------------------------------------------------------
local COMMON = petOf("Common")
local EPIC = petOf("Epic")
local LEGEND = petOf("Legendary")

local function snapshot(levels, growth, pets)
	local owned = {}
	for _, id in ipairs(pets) do
		owned[id] = 1
	end
	return {
		Tokens = 600, Pets = owned, Equipped = {}, Items = {},
		Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
		SpotIndex = 1, Perks = {}, Discovered = owned, IndexClaimed = {},
		Tutorial = { Step = 99, Done = true, Gifted = true },
		PetLevels = levels or {}, PetGrowth = growth or {},
	}
end

local function root()
	return KC.root()
end

S.client_p5follow_motion = guarded("client_p5follow_motion", function()
	local pc = PC()
	if not T.check(pc ~= nil and type(pc.GetFollowerInfo) == "function", "PetController.GetFollowerInfo exists") then
		return
	end
	-- a small pet, an evolved Legendary and a second-evolution Epic (the biggest)
	KC.toClient("ProfileSync", snapshot({ [COMMON] = 3, [LEGEND] = 30, [EPIC] = 60 }, { [LEGEND] = { Evo = 1 }, [EPIC] = { Evo = 2 } }, { COMMON, LEGEND, EPIC }))
	KC.advance(0.2)
	LocalPlayer:SetAttribute("EquippedPets", "")
	LocalPlayer:SetAttribute("InBattle", nil)
	KC.advance(0.3)
	local start = Vector3.new(400, 60, 400)
	Mock.Teleport(LocalPlayer, start) -- facing -Z
	LocalPlayer:SetAttribute("EquippedPets", table.concat({ COMMON, LEGEND, EPIC }, ","))
	KC.advance(3.5)
	local info = pc.GetFollowerInfo(LocalPlayer)
	if not T.check(#info == 3 and info[1].Model and info[2].Model and info[3].Model, "3 followers built (small, evolved, second evolution)", tostring(#info)) then
		return
	end
	T.check(info[2].Stage == 1 and info[3].Stage == 2 and (info[3].Width or 0) > (info[1].Width or 0), "the evolved followers are built evolved and measured wider",
		fmt("stages %s/%s/%s widths %.1f/%.1f/%.1f", tostring(info[1].Stage), tostring(info[2].Stage), tostring(info[3].Stage), info[1].Width or 0, info[2].Width or 0, info[3].Width or 0))
	local widths = { info[1].Width, info[2].Width, info[3].Width }
	local want = expected(widths)
	local slotsOk = true
	for i = 1, 3 do
		if abs((info[i].Side or 0) - want[i][1]) > 0.05 or abs((info[i].Back or 0) - want[i][2]) > 0.05 then
			slotsOk = false
		end
	end
	T.check(slotsOk, "the follower slots == FormationFor(measured widths)")
	local function horiz(v)
		return sqrt(v.X * v.X + v.Z * v.Z)
	end
	-- at rest: |slot| +- 1.5, the camera channel >= 1.0
	local r = root().Position
	local rest, channel = true, true
	local detail = {}
	for i = 1, 3 do
		local off = info[i].Model:GetPivot().Position - r
		local slot = sqrt(want[i][1] ^ 2 + want[i][2] ^ 2)
		detail[#detail + 1] = fmt("%.1f/%.1f", horiz(off), slot)
		if abs(horiz(off) - slot) > 1.5 then
			rest = false
		end
		if abs(off.X) - widths[i] / 2 < 1.0 or off.Z <= 0 then
			channel = false
		end
	end
	T.check(rest, "at rest every pet stands |slot| +- 1.5 studs from the owner", table.concat(detail, " "))
	T.check(channel, "at rest the camera channel holds: every pet's inner edge >= 1.0 stud off the owner's centre line, behind")
	-- the moves: straight at 16 / 24 / 27, a 90-degree turn and a reverse at 24
	local moves = {
		{ "straight 16", 16, { Vector3.new(0, 0, -1) } },
		{ "straight 24", 24, { Vector3.new(0, 0, -1) } },
		{ "straight 27", 27, { Vector3.new(0, 0, -1) } },
		{ "turn 90", 24, { Vector3.new(0, 0, -1), Vector3.new(1, 0, 0) } },
		{ "reverse", 24, { Vector3.new(0, 0, -1), Vector3.new(0, 0, 1) } },
	}
	local backMax = max(want[1][2], want[2][2], want[3][2])
	for _, mv in ipairs(moves) do
		local name, speed, legs = mv[1], mv[2], mv[3]
		Mock.Teleport(LocalPlayer, start)
		KC.advance(3)
		local minPP, minPO, lag, ahead = 1e9, 1e9, 0, -1e9
		local pos = root().Position
		for li, dir in ipairs(legs) do
			for step = 1, 30 do
				pos = pos + dir * (speed * 0.05)
				Mock.Teleport(LocalPlayer, pos)
				KC.advance(0.05)
				local o = root().Position
				local p = {}
				for i = 1, 3 do
					p[i] = info[i].Model:GetPivot().Position
				end
				for i = 1, 2 do
					for j = i + 1, 3 do
						local d = horiz(p[i] - p[j]) - widths[i] / 2 - widths[j] / 2
						minPP = min(minPP, d)
					end
				end
				for i = 1, 3 do
					minPO = min(minPO, horiz(p[i] - o) - 1.5 - widths[i] / 2)
					lag = max(lag, horiz(p[i] - o))
					if #legs == 1 and step * 0.05 >= 0.6 then
						local d = p[i] - o
						ahead = max(ahead, d.X * dir.X + d.Z * dir.Z)
					end
				end
			end
			if li < #legs then
				KC.advance(0.05)
			end
		end
		T.check(minPP >= -0.01 and minPO >= -0.01, name .. ": the pets never touch each other or the owner (gaps >= 0 at every sample)", fmt("pet-pet %.2f, pet-owner %.2f", minPP, minPO))
		T.check(lag <= backMax + 9, name .. ": lag <= back + 9", fmt("%.1f (back %.1f)", lag, backMax))
		if #legs == 1 then
			T.check(ahead <= 0.5, name .. ": never ahead of the owner after 0.6 s (<= 0.5)", fmt("%.2f", ahead))
		end
		KC.advance(3)
		local o = root().Position
		local settle = true
		for i = 1, 3 do
			local slot = sqrt(want[i][1] ^ 2 + want[i][2] ^ 2)
			if horiz(info[i].Model:GetPivot().Position - o) > slot + 1 then
				settle = false
			end
		end
		T.check(settle, name .. ": the pets settle back to |slot| + 1")
	end
	LocalPlayer:SetAttribute("EquippedPets", "")
	KC.advance(0.5)
	KC.flushErrors("p5follow motion")
	KC.flushWarnings("p5follow motion")
end)

----------------------------------------------------------------------------------------------------
S.client_p5wild = guarded("client_p5wild", function()
	local PB = moduleAt("shared", "PetBuilder")
	if not T.check(PB ~= nil and type(PB.Build) == "function", "PetBuilder loads in the client world") then
		return
	end
	local common = PetCatalog.Get(COMMON)
	local epic = PetCatalog.Get(EPIC)
	local m0 = PB.Build(common, { Detail = "Low" })
	local m1 = PB.Build(common, { Detail = "Low", Evolved = 1 })
	local m2 = PB.Build(epic, { Detail = "Low", Evolved = 2 })
	local mc2 = PB.Build(common, { Detail = "Low", Evolved = 2 })
	T.check(m0:GetAttribute("PB_Evolved") == 0 and m1:GetAttribute("PB_Evolved") == 1 and m2:GetAttribute("PB_Evolved") == 2,
		"PB_Evolved = the built stage (0 / 1 / 2)", fmt("%s %s %s", tostring(m0:GetAttribute("PB_Evolved")), tostring(m1:GetAttribute("PB_Evolved")), tostring(m2:GetAttribute("PB_Evolved"))))
	T.eq(mc2:GetAttribute("PB_Evolved"), 1, "a Common asked for stage 2 is built (and marked) at its first evolution")
	local eyes = Color3.fromRGB(255, 60, 40)
	local tint = Color3.fromRGB(80, 40, 120)
	local w = PB.Build(common, { Detail = "Low", Wild = { Tint = tint, Eyes = eyes } })
	T.check(w:GetAttribute("PB_Wild") == true and m0:GetAttribute("PB_Wild") == nil, "opts.Wild marks the model PB_Wild (a plain build does not)")
	local function byName(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				out[d.Name] = d
			end
		end
		return out
	end
	local plain, wild = byName(m0), byName(w)
	local eyeOk, eyesSeen, darker, compared = true, 0, 0, 0
	for name, p in pairs(wild) do
		local base = string.match(name, "^(%a+)") or name
		local q = plain[name]
		if base == "EyeIris" or base == "EyePupil" or base == "EyeRing" then
			eyesSeen = eyesSeen + 1
			if p.Material ~= Enum.Material.Neon or (p.Color.R - eyes.R) ^ 2 + (p.Color.G - eyes.G) ^ 2 + (p.Color.B - eyes.B) ^ 2 > 1e-4 then
				eyeOk = false
			end
		elseif q and p.Transparency < 1 and base ~= "EyeShine" and base ~= "EyeGlint" and base ~= "Body" then
			compared = compared + 1
			local _, _, v1 = q.Color:ToHSV()
			local _, _, v2 = p.Color:ToHSV()
			if v2 <= v1 + 1e-6 then
				darker = darker + 1
			end
		end
	end
	T.check(eyesSeen > 0 and eyeOk, "Wild: every iris / pupil / eye ring is Neon in the Eyes colour", eyesSeen .. " eye parts")
	T.check(compared > 10 and darker >= compared * 0.9, "Wild: the body is darker than the plain look", darker .. " / " .. compared)
	local again = byName(PB.Build(common, { Detail = "Low" }))
	local same = true
	for name, p in pairs(plain) do
		local q = again[name]
		if q and (q.Color ~= p.Color or q.Material ~= p.Material) then
			same = false
		end
	end
	T.check(same, "Wild never touches the cached template: the next plain build has the plain colours")
	for _, m in ipairs({ m0, m1, m2, mc2, w }) do
		m:Destroy()
	end
	KC.flushErrors("p5wild")
end)

return S
