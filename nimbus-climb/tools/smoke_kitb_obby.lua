-- smoke_kitb_obby.lua: the kit-b OBBY lane (O1-O4 of .superpowers/slop-audit/round3/BUILD_PLAN.md; branch kitb-obby).
-- Loaded by tools/smoke.py in both worlds, ARGS.context picks the half. Each wave adds its scenarios here and their
-- names on the OBBY line of tools/smoke.py (that line only).
--
-- O1 "far clouds and the cloud sea on Blender cumulus" (server world, pure: CourseBuilder.Build with a private
-- MeshLibrary config, 5 difficulties x the quick seeds, built once and shared by the scenarios below):
--   obby_far_clouds_tagged            with the cloud ids configured every far and sea puff of the layout is ONE invisible
--                                     anchor tagged with a cloud key from the list (ML_DressKey), no Ball part and no
--                                     Sphere SpecialMesh is left of the old jelly puffs, and a far puff under 24 studs
--                                     wears the small cumulus, a bigger one and every sea puff the big one (a puff whose
--                                     cloud would reach a step even at the key's smallest scale is left out)
--   obby_far_cloud_scale_clamped      ML_Scale = clamp(2r / width) inside the key's clamp (small 0.6-1.0, big
--                                     0.45-1.0), sea puffs at 1, the clamp floor only where the full size reaches a step;
--                                     a far cloud's lowest voxel sits on the puff's base, a sea cloud's highest voxel at
--                                     the puff's top (so a tall cumulus never rises into the route); every cloud stays
--                                     clear of every step (and a moving step's slide) with the course's head clearance
--   obby_far_clouds_detail_tag        every cloud anchor is tagged NC_Detail (Low graphics hides it) and is pure decor:
--                                     anchored, no collision / touch / query / shadow, Transparency 1
--   obby_mesh_missing_keeps_part_build with empty MeshIds the old Part build (FarCloud balls) is still there and nothing
--                                     is tagged: today's game
--   obby_part_limit                   every build (ids and no ids): the builder's counter (BuildParts + 7 per token)
--                                     stays at or under PART_LIMIT 2450, the folder under the contract's 2500, and a
--                                     course with ids never has more parts than without
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local abs, max, min, sqrt = math.abs, math.max, math.min, math.sqrt

-- the audit's numbers re-stated (world_clouds.md finding 1), never read from the Config under test:
-- Width / Lift / Top / Reach are the manifest Bounds (X size, -Min.Y, Max.Y, the farthest X / Z from the pivot)
local FIT = {
	cloud_sky_small = { Width = 68, Lift = 10, Top = 22, Reach = 37, Min = 0.6, Max = 1.0 },
	cloud_sky_big = { Width = 117, Lift = 15, Top = 36, Reach = 61.5, Min = 0.45, Max = 1.0 },
}
local CLOUD_KEYS = {
	cloud_sky_small = true, cloud_sky_big = true,
	cloud_obby_far_1 = true, cloud_obby_far_2 = true, cloud_obby_far_3 = true, cloud_obby_far_4 = true,
	cloud_obby_sea_1 = true, cloud_obby_sea_2 = true,
}
local PART_LIMIT = 2450 -- CourseBuilder PART_LIMIT: the counter's aim, tokens included
local TOKEN_PARTS = 7 -- CourseBuilder TOKEN_PARTS: what the builder books per token
local COURSE_BUDGET = 2500 -- tools/contract.json v2.partBudget.course
local HEAD = 13 -- Config.Course.Clearance: the free air above a walkable top
local DETAIL_TAG = "NC_Detail"
local ORIGIN = Vector3.new(42000, 900, 0)

local function clamp(v, lo, hi)
	return max(lo, min(hi, v))
end

local function isPuffPart(d)
	return d:IsA("BasePart") and (d.Name == "FarCloud" or d.Name == "SeaCloud")
end

local function isRound(d)
	if not d:IsA("BasePart") then
		return false
	end
	if d:IsA("Part") and d.Shape == Enum.PartType.Ball then
		return true
	end
	for _, c in ipairs(d:GetChildren()) do
		if c:IsA("SpecialMesh") and c.MeshType == Enum.MeshType.Sphere then
			return true
		end
	end
	return false
end

local function serverScenarios()
	local K = _G.K
	local S = {}

	-- the clearance guard's own case: Easy seed 1 plus two far puffs (r 30: the big cumulus at 0.513) beside one step,
	-- their base 4 studs under its top, on a side where no other step is within the full reach. One is 29.5 studs past
	-- the step's half-diagonal: the full size (reach 31.5) reaches it, the clamp floor 0.45 (27.7) does not. The other
	-- is 10 studs past it: even the floor reaches.
	local function halfDiag(st)
		return 0.5 * sqrt(st.Size.X ^ 2 + st.Size.Z ^ 2)
	end
	local function guardLayout(CB)
		local layout = CB.GenerateLayout("Easy", 1) -- a fresh table (the shared layout cache is never touched)
		local steps = layout.Steps
		for i = #steps, 1, -1 do
			local st = steps[i]
			for k = 0, 23 do
				local a = k * math.pi / 12
				local dir = Vector3.new(math.cos(a), 0, math.sin(a))
				local p = st.Pos + dir * (halfDiag(st) + 29.5)
				local lonely = true
				for j, other in ipairs(steps) do
					if j ~= i then
						local q = { other.Pos }
						if other.Hazard and typeof(other.Hazard.EndOffset) == "Vector3" then
							q[2] = other.Pos + other.Hazard.EndOffset
						end
						for _, c in ipairs(q) do
							if sqrt((c.X - p.X) ^ 2 + (c.Z - p.Z) ^ 2) < 61.5 * 0.52 + halfDiag(other) + 1 then
								lonely = false
							end
						end
					end
				end
				if lonely then
					for _, d in ipairs({ halfDiag(st) + 29.5, halfDiag(st) + 10 }) do
						layout.Scenery[#layout.Scenery + 1] = {
							Type = "Puff", Stage = 0, Layer = "Far", Pos = st.Pos + dir * d - Vector3.new(0, 4, 0), Yaw = 0,
							Radius = 30, Height = 18, Seed = 1, Tint = 1,
						}
					end
					return layout
				end
			end
		end
		error("no lonely side for the guard puffs in Easy seed 1")
	end

	-- builds every pick once per mode ("ids": the two sky cumulus uploaded; "empty": no ids; "guard": ids, the guard
	-- layout only) and keeps only numbers, so the scenarios share one set of builds and no course stays in the workspace
	local cache = {}
	local function collect(mode)
		if cache[mode] then
			return cache[mode]
		end
		local Config = K.config()
		local CB = K.mod("CourseBuilder")
		local ML = K.mod("MeshLibrary")
		assert(CB and ML and type(ML._Configure) == "function", "CourseBuilder / MeshLibrary._Configure did not load")
		local picks = {}
		if mode == "guard" then
			picks[1] = { who = "Easy seed 1 + two puffs by step 2", layout = guardLayout(CB) }
		else
			for _, diff in ipairs(Config.Difficulties) do
				for seed = 1, (ARGS and ARGS.quick) and 2 or 3 do
					local cacheL = K.W and K.W.layoutCache and K.W.layoutCache[diff.Id]
					picks[#picks + 1] = { who = diff.Id .. " seed " .. seed, layout = cacheL and cacheL[seed] or CB.GenerateLayout(diff.Id, seed) }
				end
			end
		end
		local RS = game:GetService("ReplicatedStorage")
		local hadFolder = RS:FindFirstChild("MeshLibrary") ~= nil
		local ids = {}
		if mode ~= "empty" then
			ids = { cloud_sky_small = 9301, cloud_sky_big = 9302 }
		end
		ML._Reset()
		ML._Configure({ Ids = ids, DressTag = "KitbObbyDress" }) -- a private tag: no game listener dresses these
		pcall(ML.Start) -- the mock has no LoadAsset: a configured key stays "loading" (never "missing")
		local holder = Instance.new("Folder")
		holder.Name = "SmokeKitbObby"
		holder.Parent = workspace
		local out = { builds = {}, errors = {} }
		local ok, err = pcall(function()
			for _, pick in ipairs(picks) do
				do
					local layout, who = pick.layout, pick.who
					local okB, info = pcall(CB.Build, layout, ORIGIN, holder)
					if not okB or type(info) ~= "table" then
						out.errors[#out.errors + 1] = who .. ": " .. tostring(info)
					else
						local b = { who = who, layout = layout, anchors = {}, round = 0, oldPuffs = 0, tagged = 0 }
						b.parts = Mock.CountDescendants(info.Folder, "BasePart")
						b.counter = info.Folder:GetAttribute("BuildParts")
						b.tokens = layout.TokenCount or 0
						for _, d in ipairs(info.Folder:GetDescendants()) do
							if d:IsA("BasePart") then
								if type(d:GetAttribute("ML_DressKey")) == "string" then
									b.tagged = b.tagged + 1
								end
								if isPuffPart(d) then
									if isRound(d) then
										b.round = b.round + 1
										b.oldPuffs = b.oldPuffs + 1
									elseif type(d:GetAttribute("ML_DressKey")) == "string" then
										b.anchors[#b.anchors + 1] = {
											name = d.Name, key = d:GetAttribute("ML_DressKey"),
											scale = d:GetAttribute("ML_Scale"), pos = d.Position,
											detail = d:HasTag(DETAIL_TAG), anchored = d.Anchored, collide = d.CanCollide,
											touch = d.CanTouch, query = d.CanQuery, shadow = d.CastShadow,
											transparency = d.Transparency, children = #d:GetChildren(),
										}
									end
								end
							end
						end
						out.builds[#out.builds + 1] = b
						info.Folder:Destroy()
					end
				end
			end
		end)
		holder:Destroy()
		ML._Reset()
		local f = RS:FindFirstChild("MeshLibrary")
		if f and not hadFolder then
			f:Destroy()
		end
		assert(ok, tostring(err))
		cache[mode] = out
		return out
	end

	-- the layout puff an anchor stands for: same X / Z as the puff (the anchor is the mesh pivot straight above it)
	local function puffOf(b, a)
		local best, bestD = nil, math.huge
		for _, item in ipairs(b.layout.Scenery or {}) do
			if item.Type == "Puff" then
				local p = ORIGIN + item.Pos
				local d = sqrt((p.X - a.pos.X) ^ 2 + (p.Z - a.pos.Z) ^ 2)
				if d < bestD then
					best, bestD = item, d
				end
			end
		end
		if bestD > 0.05 then
			return nil
		end
		return best
	end

	local function puffCount(layout)
		local n = 0
		for _, item in ipairs(layout.Scenery or {}) do
			if item.Type == "Puff" then
				n = n + 1
			end
		end
		return n
	end

	local function noBuildErrors(data, label)
		return T.check(#data.errors == 0 and #data.builds > 0, label .. ": every pick builds", table.concat(data.errors, " | "))
	end

	-- true when a cloud reaching `reach` studs from the column (x, z) over [lo, hi] keeps clear of every step, a moving
	-- step's slide end and the head clearance above each top (circles round both: conservative)
	local function clearOf(layout, x, z, reach, lo, hi)
		for j, st in ipairs(layout.Steps or {}) do
			local top = ORIGIN.Y + st.Pos.Y
			if hi > top - st.Size.Y and lo < top + HEAD then
				local need = reach + 0.5 * sqrt(st.Size.X ^ 2 + st.Size.Z ^ 2)
				local ends = { ORIGIN + st.Pos }
				if st.Hazard and typeof(st.Hazard.EndOffset) == "Vector3" then
					ends[2] = ORIGIN + st.Pos + st.Hazard.EndOffset
				end
				for _, p in ipairs(ends) do
					local d = sqrt((p.X - x) ^ 2 + (p.Z - z) ^ 2)
					if d < need then
						return false, string.format("%.1f studs from step %d (needs %.1f)", d, j, need)
					end
				end
			end
		end
		return true
	end

	-- what O1 promises for one puff with the two sky cumulus uploaded: { key, s, y = pivot Y } or { key, left = true }
	-- (the cloud would reach a step even at the key's smallest scale)
	local function planOf(layout, item)
		local sea = item.Layer == "Sea"
		local key = (not sea and item.Radius < 24) and "cloud_sky_small" or "cloud_sky_big"
		local fit = FIT[key]
		local s = sea and 1 or clamp(2 * item.Radius / fit.Width, fit.Min, fit.Max)
		local p = ORIGIN + item.Pos
		for _, sc in ipairs({ s, fit.Min }) do
			local y = sea and (p.Y + item.Height - fit.Top * sc) or (p.Y + fit.Lift * sc)
			if clearOf(layout, p.X, p.Z, fit.Reach * sc, y - fit.Lift * sc, y + fit.Top * sc) then
				return { key = key, s = sc, y = y, shrunk = sc ~= s }
			end
		end
		return { key = key, left = true }
	end

	-- the anchor standing over a layout puff (same X / Z: the pivot is straight above or below the puff's base)
	local function anchorAt(b, item)
		local p = ORIGIN + item.Pos
		for _, a in ipairs(b.anchors) do
			if abs(a.pos.X - p.X) <= 0.05 and abs(a.pos.Z - p.Z) <= 0.05 then
				return a
			end
		end
		return nil
	end

	S.obby_far_clouds_tagged = guarded("obby_far_clouds_tagged", function()
		local data = collect("ids")
		if not noBuildErrors(data, "obby clouds (ids)") then
			return
		end
		local every = T.tally("obby clouds: with ids every far / sea puff is one anchor (none only when even the smallest scale reaches a step)")
		local keys = T.tally("obby clouds: the key is from the cloud list (small cumulus under r 24, else big; sea = big)")
		local round = T.tally("obby clouds: with ids no Ball part / Sphere SpecialMesh puff is left (FarCloud / SeaCloud)")
		local total, small, big, sea, shrunk, left = 0, 0, 0, 0, 0, 0
		for _, b in ipairs(data.builds) do
			local want, matched = puffCount(b.layout), 0
			round:case(b.round == 0, b.who .. ": " .. b.round .. " round puff parts")
			for _, item in ipairs(b.layout.Scenery or {}) do
				if item.Type == "Puff" then
					local plan = planOf(b.layout, item)
					local a = anchorAt(b, item)
					if plan.left then
						left = left + 1
						every:case(a == nil, b.who .. ": a puff that reaches a step still got " .. tostring(a and a.key))
					else
						every:case(a ~= nil, b.who .. ": no anchor for the puff at " .. tostring(item.Pos) .. " (r " .. string.format("%.1f", item.Radius) .. ")")
						if plan.shrunk then
							shrunk = shrunk + 1
						end
					end
					if a then
						matched = matched + 1
						total = total + 1
						sea = sea + ((item.Layer == "Sea") and 1 or 0)
						small = small + ((a.key == "cloud_sky_small") and 1 or 0)
						big = big + ((a.key == "cloud_sky_big") and 1 or 0)
						keys:case(CLOUD_KEYS[a.key] == true and a.key == plan.key,
							b.who .. ": " .. a.name .. " " .. tostring(a.key) .. " (want " .. tostring(plan.key) .. ", r " .. string.format("%.1f", item.Radius) .. ")")
					end
				end
			end
			every:case(want > 0 and matched == #b.anchors, b.who .. ": " .. #b.anchors .. " anchors, " .. matched .. " over a layout puff")
		end
		every:report()
		keys:report()
		round:report()
		T.info(string.format("*obby clouds: %d anchors over %d builds (small %d, big %d, of them sea %d); %d at the smallest scale, %d left out (would reach a step)",
			total, #data.builds, small, big, sea, shrunk, left))
		K.flushErrors("obby_far_clouds_tagged")
	end)

	S.obby_far_cloud_scale_clamped = guarded("obby_far_cloud_scale_clamped", function()
		local data = collect("ids")
		if not noBuildErrors(data, "obby clouds (ids)") then
			return
		end
		local scale = T.tally("obby clouds: ML_Scale = clamp(2r / width) in the key's clamp (small 0.6-1, big 0.45-1), sea at 1 (the clamp floor only to clear a step)")
		local seat = T.tally("obby clouds: a far cloud's lowest voxel sits on its puff's base, a sea cloud's top at the puff's top")
		local clear = T.tally("obby clouds: no cloud reaches a step (or a moving step's slide) or its head clearance")
		local any = 0
		for _, b in ipairs(data.builds) do
			for _, a in ipairs(b.anchors) do
				local item = puffOf(b, a)
				local fit = FIT[a.key]
				if item and fit then
					any = any + 1
					local s = tonumber(a.scale) or 1
					local plan = planOf(b.layout, item)
					local want = plan.s or -1
					scale:case(abs(s - want) <= 1e-3 and s >= fit.Min - 1e-6 and s <= fit.Max + 1e-6,
						b.who .. ": " .. a.key .. " r " .. string.format("%.2f", item.Radius) .. " scale " .. tostring(a.scale) .. " (want " .. string.format("%.3f", want) .. ")")
					local base = ORIGIN.Y + item.Pos.Y
					local lo, hi = a.pos.Y - fit.Lift * s, a.pos.Y + fit.Top * s
					if item.Layer == "Sea" then
						seat:case(abs(hi - (base + item.Height)) <= 0.05, b.who .. ": sea top " .. string.format("%.2f", hi) .. " vs puff top " .. string.format("%.2f", base + item.Height))
					else
						seat:case(abs(lo - base) <= 0.05, b.who .. ": lowest voxel " .. string.format("%.2f", lo) .. " vs puff base " .. string.format("%.2f", base))
					end
					local ok, why = clearOf(b.layout, a.pos.X, a.pos.Z, fit.Reach * s, lo, hi)
					clear:case(ok, b.who .. ": " .. a.key .. " " .. tostring(why))
				end
			end
		end
		T.check(any > 0, "obby clouds: there are tagged clouds to measure", tostring(any))
		-- the guard's own case: a puff beside a step shrinks to the clamp floor, one closer is left out
		local g = collect("guard")
		local gb = g.builds[1]
		if T.check(#g.errors == 0 and gb ~= nil, "obby clouds guard: the guard layout builds", table.concat(g.errors, " | ")) then
			local n = #gb.layout.Scenery
			local near, nearer = gb.layout.Scenery[n - 1], gb.layout.Scenery[n]
			local pNear, pNearer = planOf(gb.layout, near), planOf(gb.layout, nearer)
			local aNear, aNearer = anchorAt(gb, near), anchorAt(gb, nearer)
			T.check(pNear.shrunk == true and pNearer.left == true, "obby clouds guard: the two puffs are the cases they stand for (one shrinks, one is left out)",
				tostring(pNear.shrunk) .. " / " .. tostring(pNearer.left))
			T.check(aNear ~= nil and abs((tonumber(aNear.scale) or 1) - 0.45) <= 1e-3 and aNear.key == "cloud_sky_big",
				"obby clouds guard: a big cumulus whose full size reaches a step is built at the clamp floor 0.45", tostring(aNear and aNear.scale))
			T.check(aNearer == nil, "obby clouds guard: a cumulus that reaches a step even at the floor is left out (no Part build either)", tostring(aNearer and aNearer.key))
			T.check(gb.round == 0, "obby clouds guard: no round Part puff appears in its place", tostring(gb.round))
		end
		scale:report()
		seat:report()
		clear:report()
		K.flushErrors("obby_far_cloud_scale_clamped")
	end)

	S.obby_far_clouds_detail_tag = guarded("obby_far_clouds_detail_tag", function()
		local data = collect("ids")
		if not noBuildErrors(data, "obby clouds (ids)") then
			return
		end
		local detail = T.tally("obby clouds: every cloud anchor is tagged NC_Detail (the Low graphics setting hides it)")
		local decor = T.tally("obby clouds: an anchor is invisible pure decor (anchored, no collide / touch / query / shadow, empty)")
		local any = 0
		for _, b in ipairs(data.builds) do
			for _, a in ipairs(b.anchors) do
				any = any + 1
				detail:case(a.detail, b.who .. ": " .. a.name .. " " .. tostring(a.key))
				decor:case(a.anchored and not a.collide and not a.touch and not a.query and not a.shadow and a.transparency >= 0.999 and a.children == 0,
					b.who .. ": " .. a.name .. " T " .. tostring(a.transparency) .. " collide " .. tostring(a.collide) .. " children " .. a.children)
			end
		end
		T.check(any > 0, "obby clouds: there are cloud anchors to check", tostring(any))
		detail:report()
		decor:report()
		K.flushErrors("obby_far_clouds_detail_tag")
	end)

	S.obby_mesh_missing_keeps_part_build = guarded("obby_mesh_missing_keeps_part_build", function()
		local data = collect("empty")
		if not noBuildErrors(data, "obby clouds (no ids)") then
			return
		end
		local old = T.tally("obby clouds: with empty MeshIds the Part build of the puffs is still there (FarCloud balls)")
		local none = T.tally("obby clouds: with empty MeshIds nothing in the course is tagged (ML_DressKey)")
		for _, b in ipairs(data.builds) do
			local want = puffCount(b.layout)
			old:case(want > 0 and b.oldPuffs >= want, b.who .. ": " .. b.oldPuffs .. " FarCloud parts for " .. want .. " puffs")
			none:case(b.tagged == 0 and #b.anchors == 0, b.who .. ": " .. b.tagged .. " tagged parts")
		end
		old:report()
		none:report()
		K.flushErrors("obby_mesh_missing_keeps_part_build")
	end)

	S.obby_part_limit = guarded("obby_part_limit", function()
		local limit = T.tally("obby: the builder's part counter (BuildParts + " .. TOKEN_PARTS .. " per token) stays at or under PART_LIMIT " .. PART_LIMIT)
		local real = T.tally("obby: the parts really in a course folder stay under the contract's " .. COURSE_BUDGET)
		local fewer = T.tally("obby: with cloud ids a course never has more parts than the same course without them")
		local worst = { 0, "" }
		local byWho = {}
		for _, mode in ipairs({ "empty", "ids" }) do
			local data = collect(mode)
			noBuildErrors(data, "obby part limit (" .. mode .. ")")
			for _, b in ipairs(data.builds) do
				local counted = (tonumber(b.counter) or math.huge) + TOKEN_PARTS * b.tokens
				limit:case(counted <= PART_LIMIT, mode .. " " .. b.who .. ": counter " .. tostring(b.counter) .. " + " .. b.tokens .. " tokens = " .. counted)
				real:case(b.parts < COURSE_BUDGET, mode .. " " .. b.who .. ": " .. b.parts .. " parts")
				if mode == "empty" then
					byWho[b.who] = b.parts
				elseif byWho[b.who] then
					fewer:case(b.parts <= byWho[b.who], b.who .. ": " .. b.parts .. " with ids vs " .. byWho[b.who])
				end
				if counted > worst[1] then
					worst = { counted, mode .. " " .. b.who .. " (" .. b.parts .. " parts in the folder)" }
				end
			end
		end
		limit:report()
		real:report()
		fewer:report()
		T.info("*obby part limit: highest count " .. worst[2] .. ": " .. worst[1])
		K.flushErrors("obby_part_limit")
	end)

	return S
end

local function clientScenarios()
	local S = {}
	return S
end

if (ARGS and ARGS.context or "server") == "server" then
	return serverScenarios()
end
return clientScenarios()
