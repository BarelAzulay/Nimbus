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
--
-- O2 "cloud undersides under the platforms" (server world, pure, the same builds; the "ids" mode also has cloud_puff_s):
--   obby_underside_tagged             with the puff id every platform with an underside (all but Beam / Vanishing) has
--                                     ONE target wearing cloud_puff_s: a static one a Model "Underside" holding the old
--                                     Part build (ML_At), a moving cloud its welded puff; no loose Puff / Stalactite /
--                                     RimPuff / Belly part is left; with empty MeshIds no Model is made (today's game).
--                                     A platform whose puff would reach another step even at 0.6 keeps its Part build
--   obby_underside_scale_and_turn     ML_Scale = clamp(min(sx, sz) / 14, 0.6, 1.4) (then 1, then 0.6, only when the
--                                     bigger puff reaches another step's slab or the head clearance above it), the mesh
--                                     pivot 3 * s under the slab's underside (the puff's top voxel at +3 meets the slab),
--                                     upright, its 21-stud X axis along the platform's long side (turned 90 degrees when
--                                     sz > sx); no puff reaches another step (a moving one along its whole slide, a
--                                     moving cloud's own puff along its slide too) or a PlateBridge's span / plate
--                                     islands; the review's pinned cases (Medium seed 38, Hard seeds 39 and 4) are what
--                                     they stand for: clear to the old start-only, steps-only guard, not to this one
--   obby_moving_cloud_mesh_welded     a moving cloud's target is a BasePart welded to its slab, ML_Weld = true, no ML_At
--                                     (a fixed spot would leave the mesh behind), its dress spot = the slab's underside
--                                     spot; its route rail and two stops hang 0.8 under the dressed puff's lowest voxel
--                                     (5.2 under the slab where the Part build stays, and with empty MeshIds)
-- The O2 scenarios also build the "pinned" picks (ids, the review's seeds).
--   obby_vanish_step_has_no_underside_mesh  a vanishing step has no underside target and nothing tagged under it (a
--                                     client mesh would not fade with the server's Transparency tween)
--
-- O3 "storm cloud, rain and course particles" (server world, pure, the same builds plus a "storm" mode: a storm cloud
-- key with an id; every build is attached to HazardService once, with a private FxSprites id table):
--   obby_storm_volume_invisible       every StormCloud volume is invisible (Transparency 1) and still the damage
--                                     trigger it was (tagged, touchable, no collision, its DPS)
--   obby_storm_puffs_tagged           with a storm cloud key that has an id every storm wears 2-3 invisible anchors of
--                                     that key inside its box footprint (scale clamp(box X / width, 0.6, what keeps the
--                                     top voxel under the head clearance), lowest voxel 4.5-4.9 over the top, upright),
--                                     no ball StormPuff is left, and they are NOT NC_Detail (a hazard tell stays on Low);
--                                     with the shipped key list (cloud_storm_puff has an id but reads as a box, so it is
--                                     not on the list) the Part puffs stay
--   obby_rain_uses_droplets           HazardService's rain is the Droplet sprite (fx_droplets, Grid4x4) and a slow Wisp
--                                     layer (fx_wisps) drifts under the cloud
--   obby_no_stock_particle_paths      no course or hazard emitter (built, or made by HazardService.Attach) shows a
--                                     rbxasset://textures/particles path or an empty texture: each wears an FxSprites
--                                     role's sheet; the CourseBuilder / HazardService sources name no stock path and
--                                     create every emitter through FxSprites
--   obby_storm_zone_tinted            a storm platform's top (under the cloud) is darker than a plain platform's top in
--                                     the same stage
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
-- the underside numbers re-stated (world_clouds.md finding 2): cloud_puff_s is 21 x 13 x 14, top voxel at +3
-- (manifest Bounds Min / Max = Lo / Hi)
local UNDER = {
	Key = "cloud_puff_s", Short = 14, Top = 3, Min = 0.6, Max = 1.4,
	Lo = Vector3.new(-10.5, -10, -6.5), Hi = Vector3.new(10.5, 3, 7.5),
}
local UNDER_PARTS = { Puff = true, Stalactite = true, RimPuff = true, Belly = true }
-- the O2 review's seeds (layout-only probe over 200 courses): a moving cloud's puff that only reaches a step along its
-- slide (Medium 38: MovingCloud_27 over Checkpoint 17; Hard 39: MovingCloud_45 over PendulumPlatform 29) and puffs
-- that only reach a PlateBridge's span / plate island (Hard 4: steps 28 and 29 over bridge 18)
local PINNED_PICKS = { { "Medium", 38 }, { "Hard", 39 }, { "Hard", 4 } }
local PINNED = {
	{ who = "Medium seed 38", index = 27, via = "slide" },
	{ who = "Hard seed 39", index = 45, via = "slide" },
	{ who = "Hard seed 4", index = 28, via = "bridge" },
	{ who = "Hard seed 4", index = 29, via = "bridge" },
}
local RAIL_DROP = 5.2 -- KB.Moving: the rail under the slab's underside while the Part build stays
local RAIL_GAP = 0.8 -- the rail under a dressed puff's lowest voxel
local ZERO = Vector3.new(0, 0, 0)
-- O3: the storm cloud numbers re-stated (cloud_storm_puff manifest Bounds: X 11.2, Min.Y -3.5, Max.Y 2.1; the cloud's
-- lowest voxel Base studs over the platform top plus up to Jitter, its top voxel under HEAD)
local STORM = { Key = "cloud_storm_puff", Width = 11.2, Lift = 3.5, Top = 2.1, Base = 4.5, Jitter = 0.4, Min = 0.6 }
local STOCK_PATH = "rbxasset://textures/particles"
local DARKER = 0.9 -- a storm top's brightness at most this share of a plain top's in the same stage

local function clamp(v, lo, hi)
	return max(lo, min(hi, v))
end

-- a module of the mounted sources by path under its src root ("shared", "FxSprites"), or nil
local function srcInstance(root, rel)
	local path = ROOTS and ROOTS[root]
	return path and Mock.GetPath(path .. "/" .. rel) or nil
end

local function sharedModule(name)
	local inst = srcInstance("shared", name)
	if not inst then
		return nil
	end
	local ok, m = pcall(require, inst)
	return ok and type(m) == "table" and m or nil
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
		elseif mode == "pinned" then
			for _, p in ipairs(PINNED_PICKS) do
				picks[#picks + 1] = { who = p[1] .. " seed " .. p[2], layout = CB.GenerateLayout(p[1], p[2]) }
			end
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
			-- cloud_storm_puff has an id in the real MeshIds too: the shipped storm key list must still skip it
			ids = { cloud_sky_small = 9301, cloud_sky_big = 9302, cloud_puff_s = 9303, cloud_storm_puff = 9304 }
		end
		ML._Reset()
		ML._Configure({ Ids = ids, DressTag = "KitbObbyDress" }) -- a private tag: no game listener dresses these
		pcall(ML.Start) -- the mock has no LoadAsset: a configured key stays "loading" (never "missing")
		-- O3: "storm" = a storm cloud key with an id on the list (the shipped list waits for obby_storm_cloud)
		local clouds = Config.Course and Config.Course.Clouds
		local stormList = clouds and clouds.Storm
		if mode == "storm" and clouds then
			clouds.Storm = { STORM.Key }
		end
		-- O3: a private FxSprites id table (every role uploaded) and HazardService for the runtime emitters
		local HS = K.mod("HazardService")
		local FX = sharedModule("FxSprites")
		local fxIds = {}
		if FX and type(FX.Roles) == "table" then
			local n = 0
			for _, r in pairs(FX.Roles) do
				n = n + 1
				fxIds[r.Key] = 7100 + n
			end
			FX._Deps({ TextureIds = fxIds })
		end
		local holder = Instance.new("Folder")
		holder.Name = "SmokeKitbObby"
		holder.Parent = workspace
		local out = { builds = {}, errors = {}, fxIds = fxIds, roleTex = {} }
		if FX then
			for role in pairs(FX.Roles) do
				out.roleTex[role] = FX.Texture(role)
			end
		end
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
						-- O2: the slabs, the underside targets (static Models / moving welded parts) and loose underside parts
						b.slabs, b.unders, b.movers, b.loose, b.loosePos, b.rails = {}, {}, {}, 0, {}, {}
						for _, d in ipairs(info.Folder:GetDescendants()) do
							if d:IsA("BasePart") and d:GetAttribute("StepIndex") ~= nil then
								b.slabs[#b.slabs + 1] = {
									name = d.Name, index = d:GetAttribute("StepIndex"), cf = d.CFrame, size = d.Size, part = d, tagged = 0,
									eo = d:GetAttribute("EndOffset"),
								}
							end
							if d:IsA("BasePart") and (d.Name == "MoveRail" or d.Name == "MoveStop") then
								b.rails[#b.rails + 1] = { name = d.Name, pos = d.Position }
							end
							if d:IsA("Model") and d.Name == "Underside" then
								b.unders[#b.unders + 1] = {
									key = d:GetAttribute("ML_DressKey"), scale = d:GetAttribute("ML_Scale"), at = ML._DressAt(d),
									pinned = d:GetAttribute("ML_At") ~= nil, parts = Mock.CountDescendants(d, "BasePart"),
								}
							elseif d:IsA("BasePart") and d:GetAttribute("ML_Weld") == true then
								local w = d:FindFirstChildOfClass("WeldConstraint")
								b.movers[#b.movers + 1] = {
									key = d:GetAttribute("ML_DressKey"), scale = d:GetAttribute("ML_Scale"), at = ML._DressAt(d),
									pinned = d:GetAttribute("ML_At") ~= nil, root = w and w.Part0, anchored = d.Anchored,
								}
							elseif d:IsA("BasePart") and UNDER_PARTS[d.Name] and not d:FindFirstAncestor("Underside") then
								b.loose = b.loose + 1
								b.loosePos[#b.loosePos + 1] = d.Position
							end
						end
						for _, sl in ipairs(b.slabs) do
							for _, d in ipairs(sl.part:GetDescendants()) do
								if d:GetAttribute("ML_DressKey") ~= nil then
									sl.tagged = sl.tagged + 1
								end
							end
							sl.stage = sl.part:GetAttribute("Stage")
							sl.part = nil
						end
						-- O3: storm volumes, storm puffs (balls / anchors), top plates, and every emitter after Attach
						b.storms, b.stormBalls, b.stormAnchors, b.tops, b.emitters = {}, 0, {}, {}, {}
						for _, d in ipairs(info.Folder:GetDescendants()) do
							if d:IsA("BasePart") then
								if d:HasTag(K.config().Tags.StormCloud) then
									b.storms[#b.storms + 1] = {
										transparency = d.Transparency, touch = d.CanTouch, collide = d.CanCollide, dps = d:GetAttribute("DPS"),
									}
								end
								if d.Name == "StormPuff" then
									if type(d:GetAttribute("ML_DressKey")) == "string" then
										b.stormAnchors[#b.stormAnchors + 1] = {
											key = d:GetAttribute("ML_DressKey"), scale = d:GetAttribute("ML_Scale"), at = ML._DressAt(d),
											detail = d:HasTag(DETAIL_TAG), transparency = d.Transparency, collide = d.CanCollide,
											query = d.CanQuery, touch = d.CanTouch,
										}
									else
										b.stormBalls = b.stormBalls + 1
									end
								end
								if d.Name == "TopPlate" then
									b.tops[#b.tops + 1] = { pos = d.Position, color = d.Color }
								end
							end
						end
						if HS and type(HS.Attach) == "function" then
							local okA, stop = pcall(HS.Attach, info.Folder, { IsActive = function() return false end })
							if not okA then
								out.errors[#out.errors + 1] = who .. ": HazardService.Attach " .. tostring(stop)
							end
							for _, d in ipairs(info.Folder:GetDescendants()) do
								if d:IsA("ParticleEmitter") then
									b.emitters[#b.emitters + 1] = {
										where = d:GetFullName(), name = d.Name, parent = d.Parent and d.Parent.Name, texture = tostring(d.Texture),
										role = FX and FX.RoleOf(tostring(d.Texture)), flip = d.FlipbookLayout, speed = d.Speed, rate = d.Rate,
									}
								end
							end
							if okA and type(stop) == "function" then
								pcall(stop)
							end
						end
						out.builds[#out.builds + 1] = b
						info.Folder:Destroy()
					end
				end
			end
		end)
		holder:Destroy()
		if clouds then
			clouds.Storm = stormList
		end
		if FX then
			FX._Deps(false)
		end
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

	-- O2 ------------------------------------------------------------------------------------------------------------
	local function startsWith(s, p)
		return string.sub(s, 1, #p) == p
	end

	-- a slab that gets an underside (Beam: Under = false; Vanishing: Slab = true)
	local function hasUnder(sl)
		return not (startsWith(sl.name, "Beam_") or startsWith(sl.name, "VanishCloud_"))
	end

	-- two upright boxes (centre CFrame, size) overlap, each swept along its slide (va / vb, nil = still): their Y ranges
	-- (stretched by the slides' rise) and their X / Z shapes (rectangle + slide segment) on the separating axes: both
	-- rectangles' edge axes and the normal of each slide
	local function boxesMeet(ca, sa, cb, sb, va, vb)
		va, vb = va or ZERO, vb or ZERO
		local d = (cb.Position + vb * 0.5) - (ca.Position + va * 0.5)
		if abs(d.Y) >= (sa.Y + sb.Y + abs(va.Y) + abs(vb.Y)) / 2 - 1e-6 then
			return false
		end
		local axes = { ca.RightVector, ca.LookVector, cb.RightVector, cb.LookVector, Vector3.new(-va.Z, 0, va.X), Vector3.new(-vb.Z, 0, vb.X) }
		for _, ax in ipairs(axes) do
			ax = Vector3.new(ax.X, 0, ax.Z)
			if ax.Magnitude > 1e-6 then
				ax = ax.Unit
				local ra = abs(ca.RightVector:Dot(ax)) * sa.X / 2 + abs(ca.LookVector:Dot(ax)) * sa.Z / 2 + abs(va:Dot(ax)) / 2
				local rb = abs(cb.RightVector:Dot(ax)) * sb.X / 2 + abs(cb.LookVector:Dot(ax)) * sb.Z / 2 + abs(vb:Dot(ax)) / 2
				if abs(d:Dot(ax)) >= ra + rb - 1e-6 then
					return false
				end
			end
		end
		return true
	end

	-- the walkable solids a puff keeps out of, each its slab plus the head clearance above (a box centre and size): every
	-- step (a moving one with its slide) and, unless noBridges, every PlateBridge's span and two plate islands, built as
	-- CourseBuilder builds them (span yaw Span.Yaw or 0, an island's Side.Yaw or the step's). key "s<i>" = step i,
	-- "b<i>" = its span, "b<i>_<k>" = its island k
	local function underSolids(layout, noBridges)
		local out = {}
		local function add(key, what, pos, size, yaw, slide)
			local F = CFrame.new(ORIGIN + pos) * CFrame.Angles(0, math.rad(yaw or 0), 0)
			out[#out + 1] = {
				key = key, what = what, slide = slide,
				cf = F * CFrame.new(0, (HEAD - size.Y) / 2, 0), size = Vector3.new(size.X, size.Y + HEAD, size.Z),
			}
		end
		for _, st in ipairs(layout.Steps or {}) do
			local h = type(st.Hazard) == "table" and st.Hazard or {}
			add("s" .. st.Index, "step " .. tostring(st.Index) .. " (" .. tostring(st.Kind) .. ")", st.Pos, st.Size, st.Yaw,
				typeof(h.EndOffset) == "Vector3" and h.EndOffset or nil)
			if st.Kind == "PlateBridge" and not noBridges then
				if type(h.Span) == "table" then
					add("b" .. st.Index, "the bridge span of step " .. st.Index, h.Span.Pos, h.Span.Size, h.Span.Yaw or 0)
				end
				for k, side in ipairs(h.Sides or {}) do
					add("b" .. st.Index .. "_" .. k, "plate island " .. k .. " of step " .. st.Index, side.Pos, side.Size, side.Yaw or st.Yaw)
				end
			end
		end
		return out
	end

	-- which solid a slab is (a plate island is built with its bridge step's StepIndex)
	local function solidKey(sl)
		local i, k = string.match(sl.name, "^PlateIsland_(%d+)_(%d+)$")
		if i then
			return "b" .. i .. "_" .. k
		end
		return "s" .. tostring(sl.index)
	end

	-- nil when the puff's box (UNDER Lo / Hi at scale s, pivot `cf`), swept along its own solid's slide, keeps out of
	-- every other solid (a moving one swept along its slide), else what it reaches. opts.still: the old guard's view (the
	-- puff only where it starts); opts.noBridges: the old guard's solids (the steps only)
	local function underHits(layout, key, cf, s, opts)
		opts = opts or {}
		local ms = (UNDER.Hi - UNDER.Lo) * s
		local mc = cf * CFrame.new((UNDER.Lo + UNDER.Hi) * (0.5 * s))
		local solids = underSolids(layout, opts.noBridges)
		local own
		for _, so in ipairs(solids) do
			if so.key == key and not opts.still then
				own = so.slide
			end
		end
		for _, so in ipairs(solids) do
			if so.key ~= key and boxesMeet(mc, ms, so.cf, so.size, own, so.slide) then
				return "reaches " .. so.what .. (own and " (along its slide)" or "")
			end
		end
		return nil
	end

	-- what O2 promises under one slab: { s, cf = the mesh pivot, long = the slab's long axis (world), turned, shrunk } at
	-- the first scale of { clamp(min(sx, sz) / 14), at most 1, the clamp floor } that keeps clear of the other solids, or
	-- { left = true } (the Part build stays). opts: underHits' (the old guard's view, for the pinned cases)
	local function underPlan(b, sl, opts)
		local sx, sy, sz = sl.size.X, sl.size.Y, sl.size.Z
		local s0 = clamp(min(sx, sz) / UNDER.Short, UNDER.Min, UNDER.Max)
		local turned = sz > sx
		for _, s in ipairs({ s0, min(s0, 1), UNDER.Min }) do
			local cf = sl.cf * CFrame.new(0, -sy / 2 - UNDER.Top * s, 0)
			if turned then
				cf = cf * CFrame.Angles(0, math.pi / 2, 0)
			end
			if underHits(b.layout, solidKey(sl), cf, s, opts) == nil then
				return { s = s, cf = cf, turned = turned, shrunk = s ~= s0, long = turned and sl.cf.LookVector or sl.cf.RightVector }
			end
		end
		return { left = true }
	end

	-- the underside targets (static Models or moving parts) whose dress spot is straight under `sl` (same X / Z, below)
	local function underOf(list, sl)
		local found = {}
		for _, u in ipairs(list) do
			local p = typeof(u.at) == "CFrame" and u.at.Position
			if p and abs(p.X - sl.cf.Position.X) <= 0.05 and abs(p.Z - sl.cf.Position.Z) <= 0.05 and p.Y < sl.cf.Position.Y then
				found[#found + 1] = u
			end
		end
		return found
	end

	local function targetsOf(b, sl)
		local moving = startsWith(sl.name, "MovingCloud_")
		return underOf(moving and b.movers or b.unders, sl), underOf(moving and b.unders or b.movers, sl)
	end

	-- the route rail of a moving slab: its two stops (under the slab's centre at the start and at start + EndOffset) and
	-- the rail between them, `drop` under the slab's underside; nil = fine, else why not
	local function railProblem(b, sl, drop)
		local eo = sl.eo
		if typeof(eo) ~= "Vector3" then
			return "no EndOffset on the slab"
		end
		local a = sl.cf.Position - Vector3.new(0, sl.size.Y / 2 + drop, 0)
		local flat = Vector3.new(eo.X, 0, eo.Z)
		local want = { { "MoveStop", a }, { "MoveStop", a + flat } }
		if flat.Magnitude >= 0.05 then
			want[3] = { "MoveRail", a + flat * 0.5 }
		end
		for _, w in ipairs(want) do
			local ok, seen = false, nil
			for _, r in ipairs(b.rails) do
				if r.name == w[1] and abs(r.pos.X - w[2].X) <= 0.05 and abs(r.pos.Z - w[2].Z) <= 0.05 then
					seen = r.pos.Y
					ok = ok or abs(r.pos.Y - w[2].Y) <= 0.05
				end
			end
			if not ok then
				return string.format("%s at y %s (want %.2f, %.2f under the slab)", w[1], seen and string.format("%.2f", seen) or "none", w[2].Y, drop)
			end
		end
		return nil
	end

	-- the O2 builds: the "ids" picks plus the review's pinned seeds (built with the same ids)
	local function underData()
		local out = { builds = {}, errors = {} }
		for _, d in ipairs({ collect("ids"), collect("pinned") }) do
			for _, b in ipairs(d.builds) do
				out.builds[#out.builds + 1] = b
			end
			for _, e in ipairs(d.errors) do
				out.errors[#out.errors + 1] = e
			end
		end
		return out
	end

	-- the spot / scale / axes of one target against its plan; nil = fine, else why not
	local function spotProblem(u, plan)
		local s = tonumber(u.scale) or 1
		if abs(s - plan.s) > 1e-3 then
			return string.format("scale %.3f (want %.3f)", s, plan.s)
		end
		local d = (u.at.Position - plan.cf.Position).Magnitude
		if d > 0.05 then
			return string.format("pivot %.2f studs off (y %.2f, want %.2f)", d, u.at.Position.Y, plan.cf.Position.Y)
		end
		if u.at.UpVector:Dot(plan.cf.UpVector) < 0.999 then
			return "not upright"
		end
		if abs(u.at.RightVector:Dot(plan.long)) < 0.999 then
			return "the 21-stud axis is not along the long side" .. (plan.turned and " (turned case)" or "")
		end
		return nil
	end

	-- true when a loose underside part hangs under a slab whose puff was left out (its Part build stays)
	local function underLeft(b, pos, left)
		for _, sl in ipairs(left) do
			local q = sl.cf:PointToObjectSpace(pos)
			if abs(q.X) <= sl.size.X / 2 + 1 and abs(q.Z) <= sl.size.Z / 2 + 1 and q.Y < sl.size.Y / 2 then
				return true
			end
		end
		return false
	end

	S.obby_underside_tagged = guarded("obby_underside_tagged", function()
		local data = underData()
		if not noBuildErrors(data, "obby undersides (ids)") then
			return
		end
		local one = T.tally("obby undersides: with the puff id every platform with an underside has ONE target (Model, or a moving cloud's welded puff), none where the puff would reach another step")
		local key = T.tally("obby undersides: a static underside is a Model 'Underside' pinned at its spot (ML_At), wearing cloud_puff_s, holding the old Part build")
		local loose = T.tally("obby undersides: with the puff id no loose Puff / Stalactite / RimPuff / Belly part is left (except under a platform whose puff was left out)")
		local n, left = 0, 0
		for _, b in ipairs(data.builds) do
			local leftSlabs = {}
			for _, sl in ipairs(b.slabs) do
				if hasUnder(sl) then
					local found, other = targetsOf(b, sl)
					local plan = underPlan(b, sl)
					if plan.left then
						left = left + 1
						leftSlabs[#leftSlabs + 1] = sl
						one:case(#found == 0 and #other == 0, b.who .. ": " .. sl.name .. " would reach a step but has " .. #found .. " / " .. #other .. " targets")
					else
						one:case(#found == 1 and #other == 0, b.who .. ": " .. sl.name .. " has " .. #found .. " / " .. #other .. " targets")
					end
					n = n + #found
				end
			end
			for _, u in ipairs(b.unders) do
				key:case(u.key == UNDER.Key and u.pinned and u.parts >= 1, b.who .. ": Underside " .. tostring(u.key) .. " pinned " .. tostring(u.pinned) .. " parts " .. u.parts)
			end
			for _, m in ipairs(b.movers) do
				key:case(m.key == UNDER.Key, b.who .. ": moving puff " .. tostring(m.key))
			end
			local stray = 0
			for _, pos in ipairs(b.loosePos) do
				if not underLeft(b, pos, leftSlabs) then
					stray = stray + 1
				end
			end
			loose:case(stray == 0, b.who .. ": " .. stray .. " loose underside parts (" .. b.loose .. " in all, " .. #leftSlabs .. " platforms left out)")
		end
		T.check(n > 0, "obby undersides: there are underside targets", tostring(n))
		local empty = collect("empty")
		if noBuildErrors(empty, "obby undersides (no ids)") then
			local keep = T.tally("obby undersides: with empty MeshIds no Underside Model / welded mesh target, the Part build stays loose")
			for _, b in ipairs(empty.builds) do
				keep:case(#b.unders == 0 and #b.movers == 0 and b.loose > 0, b.who .. ": " .. #b.unders .. " Models, " .. #b.movers .. " movers, " .. b.loose .. " loose parts")
			end
			keep:report()
		end
		one:report()
		key:report()
		loose:report()
		T.info(string.format("*obby undersides: %d targets over %d builds, %d platforms keep the Part build (the puff would reach another step)", n, #data.builds, left))
		K.flushErrors("obby_underside_tagged")
	end)

	S.obby_underside_scale_and_turn = guarded("obby_underside_scale_and_turn", function()
		local data = underData()
		if not noBuildErrors(data, "obby undersides (ids)") then
			return
		end
		local fit = T.tally("obby undersides: scale clamp(min(sx, sz) / 14, 0.6, 1.4) (1, then 0.6, only to clear another step), pivot 3 * s under the slab, upright, 21-stud axis along the long side")
		local clear = T.tally("obby undersides: no puff reaches another step's slab or the head clearance above it (a moving step along its slide, a moving cloud's puff along its own) or a bridge span / plate island")
		local n, turned, shrunk, lo, hi = 0, 0, 0, math.huge, -math.huge
		for _, b in ipairs(data.builds) do
			for _, sl in ipairs(b.slabs) do
				if hasUnder(sl) then
					local found = targetsOf(b, sl)
					if #found == 1 then
						local u = found[1]
						local plan = underPlan(b, sl)
						local why = plan.left and "should have been left out" or spotProblem(u, plan)
						fit:case(why == nil, b.who .. ": " .. sl.name .. " " .. string.format("%.1f x %.1f", sl.size.X, sl.size.Z) .. ": " .. tostring(why))
						local hit = underHits(b.layout, solidKey(sl), u.at, tonumber(u.scale) or 1)
						clear:case(hit == nil, b.who .. ": " .. sl.name .. " " .. tostring(hit))
						n = n + 1
						turned = turned + ((plan.turned and 1) or 0)
						shrunk = shrunk + ((plan.shrunk and 1) or 0)
						local s = tonumber(u.scale) or 1
						lo, hi = min(lo, s), max(hi, s)
					end
				end
			end
		end
		T.check(n > 0 and turned > 0 and turned < n, "obby undersides: both the plain and the turned case are measured", n .. " measured, " .. turned .. " turned")
		fit:report()
		clear:report()
		-- the review's pinned cases: at the scale the old guard (the puff where it starts, the steps only) would pick, the
		-- puff reaches what the case stands for, so this guard shrinks it or leaves it out (the tallies above check how)
		local pinned = collect("pinned")
		for _, pc in ipairs(PINNED) do
			local b, sl
			for _, pb in ipairs(pinned.builds) do
				if pb.who == pc.who then
					b = pb
				end
			end
			for _, ps in ipairs(b and b.slabs or {}) do
				if solidKey(ps) == "s" .. pc.index then
					sl = ps
				end
			end
			local old = sl and underPlan(b, sl, (pc.via == "slide") and { still = true, noBridges = true } or { noBridges = true })
			local hit = old and not old.left and underHits(b.layout, solidKey(sl), old.cf, old.s)
			T.check(type(hit) == "string" and (pc.via == "bridge") == (string.find(hit, "bridge span", 1, true) ~= nil or string.find(hit, "plate island", 1, true) ~= nil),
				"obby undersides pinned: " .. pc.who .. " step " .. pc.index .. " is clear to the old guard but reaches " .. ((pc.via == "slide") and "a step along its slide" or "a bridge"),
				tostring(sl and sl.name) .. " old scale " .. tostring(old and old.s) .. ": " .. tostring(hit))
		end
		T.info(string.format("*obby undersides: %d measured, %d turned, %d shrunk to clear a step, scale %.2f-%.2f", n, turned, shrunk, lo, hi))
		K.flushErrors("obby_underside_scale_and_turn")
	end)

	S.obby_moving_cloud_mesh_welded = guarded("obby_moving_cloud_mesh_welded", function()
		local data = underData()
		if not noBuildErrors(data, "obby undersides (ids)") then
			return
		end
		local weld = T.tally("obby moving clouds: the underside target is welded to its slab, ML_Weld, no fixed ML_At, unanchored")
		local spot = T.tally("obby moving clouds: the mesh's dress spot is the slab's underside spot (scale, pivot, turn)")
		local rail = T.tally("obby moving clouds: the route rail and its stops hang " .. RAIL_GAP .. " under a dressed puff's lowest voxel (13 * s under the slab), " .. RAIL_DROP .. " under the slab where the Part build stays")
		local n, dressed = 0, 0
		for _, b in ipairs(data.builds) do
			for _, sl in ipairs(b.slabs) do
				if startsWith(sl.name, "MovingCloud_") then
					n = n + 1
					local plan = underPlan(b, sl)
					local found = underOf(b.movers, sl)
					local m = found[1]
					local drop = plan.left and RAIL_DROP or ((UNDER.Hi.Y - UNDER.Lo.Y) * plan.s + RAIL_GAP)
					local why = railProblem(b, sl, drop)
					rail:case(why == nil, b.who .. ": " .. sl.name .. ": " .. tostring(why))
					if plan.left then
						weld:case(#found == 0, b.who .. ": " .. sl.name .. " would reach a step but has " .. #found .. " targets")
					else
						dressed = dressed + 1
						weld:case(#found == 1 and m.root ~= nil and m.root.Name == sl.name and not m.pinned and m.anchored == false,
							b.who .. ": " .. sl.name .. " " .. #found .. " targets, root " .. tostring(m and m.root and m.root.Name) .. ", pinned " .. tostring(m and m.pinned))
						if m then
							local why = spotProblem(m, plan)
							spot:case(why == nil, b.who .. ": " .. sl.name .. ": " .. tostring(why))
						end
					end
				end
			end
		end
		T.check(dressed > 0, "obby moving clouds: the builds have dressed moving clouds", dressed .. " of " .. n)
		weld:report()
		spot:report()
		rail:report()
		local empty = collect("empty")
		if noBuildErrors(empty, "obby moving clouds (no ids)") then
			local keep = T.tally("obby moving clouds: with empty MeshIds the route rail stays " .. RAIL_DROP .. " under the slab")
			for _, b in ipairs(empty.builds) do
				for _, sl in ipairs(b.slabs) do
					if startsWith(sl.name, "MovingCloud_") then
						local why = railProblem(b, sl, RAIL_DROP)
						keep:case(why == nil, b.who .. ": " .. sl.name .. ": " .. tostring(why))
					end
				end
			end
			keep:report()
		end
		K.flushErrors("obby_moving_cloud_mesh_welded")
	end)

	S.obby_vanish_step_has_no_underside_mesh = guarded("obby_vanish_step_has_no_underside_mesh", function()
		local data = underData()
		if not noBuildErrors(data, "obby undersides (ids)") then
			return
		end
		local none = T.tally("obby vanishing steps: no underside target and nothing tagged on / under the slab")
		local n = 0
		for _, b in ipairs(data.builds) do
			for _, sl in ipairs(b.slabs) do
				if startsWith(sl.name, "VanishCloud_") then
					n = n + 1
					local a, m = underOf(b.unders, sl), underOf(b.movers, sl)
					none:case(#a == 0 and #m == 0 and sl.tagged == 0, b.who .. ": " .. sl.name .. " " .. #a .. " Models, " .. #m .. " movers, " .. sl.tagged .. " tagged")
				end
			end
		end
		T.check(n > 0, "obby vanishing steps: the builds have vanishing steps", tostring(n))
		none:report()
		K.flushErrors("obby_vanish_step_has_no_underside_mesh")
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

	-- O3 ------------------------------------------------------------------------------------------------------------
	local function stormSteps(layout)
		local out = {}
		for _, st in ipairs(layout.Steps or {}) do
			if st.Kind == "StormPlatform" and type(st.Hazard) == "table" and type(st.Hazard.Box) == "table" then
				out[#out + 1] = st
			end
		end
		return out
	end

	local function lum(c)
		return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
	end

	S.obby_storm_volume_invisible = guarded("obby_storm_volume_invisible", function()
		local seen = 0
		local hidden = T.tally("obby storms: the StormCloud volume is invisible (Transparency 1)")
		local trigger = T.tally("obby storms: the volume is still the damage trigger (touchable, no collision, DPS)")
		for _, mode in ipairs({ "empty", "ids" }) do
			local data = collect(mode)
			noBuildErrors(data, "obby storms (" .. mode .. ")")
			for _, b in ipairs(data.builds) do
				for _, v in ipairs(b.storms) do
					seen = seen + 1
					hidden:case(v.transparency >= 0.999, mode .. " " .. b.who .. ": Transparency " .. tostring(v.transparency))
					trigger:case(v.touch == true and v.collide == false and type(v.dps) == "number" and v.dps > 0,
						mode .. " " .. b.who .. ": touch " .. tostring(v.touch) .. " collide " .. tostring(v.collide) .. " DPS " .. tostring(v.dps))
				end
			end
		end
		T.check(seen > 0, "obby storms: the builds have storm volumes", tostring(seen))
		hidden:report()
		trigger:report()
		K.flushErrors("obby_storm_volume_invisible")
	end)

	S.obby_storm_puffs_tagged = guarded("obby_storm_puffs_tagged", function()
		local data = collect("storm")
		if not noBuildErrors(data, "obby storm puffs (storm key)") then
			return
		end
		local count = T.tally("obby storm puffs: with a storm key id every storm wears 2-3 anchors of that key inside its box footprint")
		local fit = T.tally("obby storm puffs: scale clamp(box X / width, 0.6, top voxel under the head clearance), lowest voxel 4.5-4.9 over the top, upright")
		local hazard = T.tally("obby storm puffs: an anchor is invisible, no collide / touch / query, and NOT NC_Detail (the hazard tell stays on Low)")
		local balls = T.tally("obby storm puffs: with a storm key id no ball StormPuff is left")
		local storms, anchors = 0, 0
		local smax = (HEAD - STORM.Base - STORM.Jitter) / (STORM.Lift + STORM.Top)
		for _, b in ipairs(data.builds) do
			local steps = stormSteps(b.layout)
			local used = {}
			for _, st in ipairs(steps) do
				storms = storms + 1
				local box = st.Hazard.Box
				local BF = CFrame.new(ORIGIN + box.Pos) * CFrame.Angles(0, math.rad(box.Yaw or 0), 0)
				local mine = {}
				for i, a in ipairs(b.stormAnchors) do
					local q = typeof(a.at) == "CFrame" and BF:PointToObjectSpace(a.at.Position)
					if q and abs(q.X) <= box.Size.X / 2 + 0.01 and abs(q.Z) <= box.Size.Z / 2 + 0.01 and q.Y > 0 and q.Y < HEAD + 4 then
						mine[#mine + 1] = a
						used[i] = true
					end
				end
				count:case(#mine >= 2 and #mine <= 3, b.who .. ": storm step " .. st.Index .. " has " .. #mine .. " anchors")
				local want = clamp(box.Size.X / STORM.Width, STORM.Min, smax)
				for _, a in ipairs(mine) do
					anchors = anchors + 1
					local s = tonumber(a.scale) or 1
					local low = a.at.Position.Y - STORM.Lift * s - (ORIGIN.Y + box.Pos.Y)
					local high = a.at.Position.Y + STORM.Top * s - (ORIGIN.Y + box.Pos.Y)
					fit:case(a.key == STORM.Key and abs(s - want) <= 1e-3 and low >= STORM.Base - 0.01 and low <= STORM.Base + STORM.Jitter + 0.01
						and high <= HEAD + 0.01 and a.at.UpVector.Y >= 0.999,
						b.who .. ": step " .. st.Index .. " " .. tostring(a.key) .. string.format(" scale %.3f (want %.3f), lowest %.2f, top %.2f", s, want, low, high))
					hazard:case(not a.detail and a.transparency >= 0.999 and not a.collide and not a.touch and not a.query,
						b.who .. ": step " .. st.Index .. " detail " .. tostring(a.detail) .. " T " .. tostring(a.transparency))
				end
			end
			local stray = 0
			for i in ipairs(b.stormAnchors) do
				if not used[i] then
					stray = stray + 1
				end
			end
			count:case(stray == 0, b.who .. ": " .. stray .. " storm anchors outside every storm box")
			balls:case(#steps == 0 or b.stormBalls == 0, b.who .. ": " .. b.stormBalls .. " ball StormPuff parts")
		end
		T.check(storms > 0 and anchors > 0, "obby storm puffs: the builds have storms to dress", storms .. " storms, " .. anchors .. " anchors")
		count:report()
		fit:report()
		hazard:report()
		balls:report()
		-- the shipped key list: cloud_storm_puff (an id in MeshIds, but 8 boxes: it reads as a box) is not on it
		local ids = collect("ids")
		if noBuildErrors(ids, "obby storm puffs (shipped list)") then
			local keep = T.tally("obby storm puffs: with the shipped key list (no storm cloud id) the Part puffs stay, nothing tagged")
			for _, b in ipairs(ids.builds) do
				if #stormSteps(b.layout) > 0 then
					keep:case(b.stormBalls > 0 and #b.stormAnchors == 0, b.who .. ": " .. b.stormBalls .. " balls, " .. #b.stormAnchors .. " anchors")
				end
			end
			keep:report()
		end
		K.flushErrors("obby_storm_puffs_tagged")
	end)

	S.obby_rain_uses_droplets = guarded("obby_rain_uses_droplets", function()
		local data = collect("empty")
		if not noBuildErrors(data, "obby rain") then
			return
		end
		local rain = T.tally("obby rain: every storm's rain is the Droplet sprite (fx_droplets on its Grid4x4 flipbook)")
		local wisp = T.tally("obby rain: every storm has a slow Wisp layer (fx_wisps, at most 2 studs/s) drifting under the cloud")
		local n = 0
		for _, b in ipairs(data.builds) do
			local storms = #stormSteps(b.layout)
			if storms > 0 then
				local rains, wisps = 0, 0
				for _, e in ipairs(b.emitters) do
					if e.parent == "StormRain" then
						if e.name == "Rain" then
							rains = rains + 1
							rain:case(e.texture == data.roleTex.Droplet and e.flip == Enum.ParticleFlipbookLayout.Grid4x4,
								b.who .. ": Rain '" .. e.texture .. "' (want '" .. tostring(data.roleTex.Droplet) .. "')")
						elseif e.texture == data.roleTex.Wisp then
							wisps = wisps + 1
							wisp:case(e.speed.Max <= 2 and e.rate > 0, b.who .. ": " .. e.name .. " speed " .. tostring(e.speed.Max) .. " rate " .. tostring(e.rate))
						end
					end
				end
				n = n + storms
				rain:case(rains == storms, b.who .. ": " .. rains .. " rain emitters for " .. storms .. " storms")
				wisp:case(wisps == storms, b.who .. ": " .. wisps .. " wisp layers for " .. storms .. " storms")
			end
		end
		T.check(n > 0, "obby rain: the builds have storms", tostring(n))
		rain:report()
		wisp:report()
		K.flushErrors("obby_rain_uses_droplets")
	end)

	S.obby_no_stock_particle_paths = guarded("obby_no_stock_particle_paths", function()
		local own = T.tally("obby particles: every course / hazard emitter (built or attached) wears an FxSprites role's sheet, no stock path")
		local n, byRole = 0, {}
		for _, mode in ipairs({ "empty", "ids", "storm" }) do
			local data = collect(mode)
			noBuildErrors(data, "obby particles (" .. mode .. ")")
			for _, b in ipairs(data.builds) do
				for _, e in ipairs(b.emitters) do
					n = n + 1
					local ok = e.role ~= nil and e.texture ~= "" and not e.texture:find(STOCK_PATH, 1, true)
						and e.texture:find("^rbxassetid://") ~= nil and e.flip == Enum.ParticleFlipbookLayout.Grid4x4
					own:case(ok, mode .. " " .. b.who .. ": " .. e.where .. " = '" .. e.texture .. "'")
					if e.role then
						byRole[e.role] = (byRole[e.role] or 0) + 1
					end
				end
			end
		end
		T.check(n > 0, "obby particles: the builds have emitters", tostring(n))
		own:report()
		local parts = {}
		for role, c in pairs(byRole) do
			parts[#parts + 1] = role .. " " .. c
		end
		table.sort(parts)
		T.info("*obby particles: " .. n .. " emitters (" .. table.concat(parts, ", ") .. ")")
		-- the sources: no stock path, every ParticleEmitter made next to an FxSprites call
		for _, rel in ipairs({ "Services/CourseBuilder", "Services/HazardService" }) do
			local inst = srcInstance("server", rel)
			local src = inst and tostring(inst.Source or "") or ""
			if T.check(src ~= "", "obby particles: server/" .. rel .. " is mounted") then
				local stock, bare = {}, {}
				local lines = {}
				for line in (src .. "\n"):gmatch("([^\n]*)\n") do
					lines[#lines + 1] = line:gsub("%-%-.*$", "")
				end
				for i, code in ipairs(lines) do
					if code:find(STOCK_PATH, 1, true) then
						stock[#stock + 1] = tostring(i)
					end
					if code:find('Instance.new("ParticleEmitter")', 1, true) then
						local found = false
						for j = i, math.min(#lines, i + 3) do
							found = found or lines[j]:find("FxSprites", 1, true) ~= nil
						end
						if not found then
							bare[#bare + 1] = tostring(i)
						end
					end
				end
				T.check(#stock == 0, "obby particles: server/" .. rel .. " names no rbxasset particle path", "lines " .. table.concat(stock, ", "))
				T.check(#bare == 0, "obby particles: server/" .. rel .. " hands every new ParticleEmitter to FxSprites", "lines " .. table.concat(bare, ", "))
			end
		end
		K.flushErrors("obby_no_stock_particle_paths")
	end)

	S.obby_storm_zone_tinted = guarded("obby_storm_zone_tinted", function()
		local data = collect("empty")
		if not noBuildErrors(data, "obby storm tint") then
			return
		end
		local darker = T.tally("obby storm tint: a storm platform's top is at most " .. DARKER .. " as bright as a plain platform's top in its stage")
		local found = T.tally("obby storm tint: every storm platform has its top plate")
		local pairsSeen = 0
		local function topOf(b, sl)
			local want = sl.cf.Position + Vector3.new(0, sl.size.Y / 2 + 0.05, 0)
			for _, t in ipairs(b.tops) do
				if (t.pos - want).Magnitude <= 0.05 then
					return t
				end
			end
			return nil
		end
		for _, b in ipairs(data.builds) do
			for _, sl in ipairs(b.slabs) do
				if startsWith(sl.name, "StormPlatform_") then
					local top = topOf(b, sl)
					found:case(top ~= nil, b.who .. ": " .. sl.name)
					if top then
						for _, other in ipairs(b.slabs) do
							if startsWith(other.name, "Cloud_") and other.stage == sl.stage then
								local ot = topOf(b, other)
								if ot then
									pairsSeen = pairsSeen + 1
									darker:case(lum(top.color) <= DARKER * lum(ot.color),
										b.who .. ": " .. sl.name .. string.format(" %.3f vs ", lum(top.color)) .. other.name .. string.format(" %.3f", lum(ot.color)))
								end
							end
						end
					end
				end
			end
		end
		T.check(pairsSeen > 0, "obby storm tint: there are storm and plain platforms in one stage to compare", tostring(pairsSeen))
		found:report()
		darker:report()
		K.flushErrors("obby_storm_zone_tinted")
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
