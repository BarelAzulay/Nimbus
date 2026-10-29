-- smoke_bug5_dungeon.lua: bug #5 "all dungeon rooms need a big Blender improve" (the player's pick B "The Weatherworks"
-- + the note "every dungeon level needs a different design ... the higher level of the dungeon the more serious it
-- looks"). Loaded by tools/smoke.py in the server world and the client world:
--   bug5dgn_styles  (server) the look follows the run's floor: StyleTiers c 1-3, b 4-8, a 9-12 (every floor 1..12 has a
--                   style, deeper = a higher Rank = more serious), a run's holder carries DungeonStyle + its mood
--                   (MoodAmbient / Brightness: darker with depth), its rooms are built in its style (their wall keys)
--   bug5dgn_throne  (server) the boss room in every style: fix 1 the four banners hang BETWEEN the side torches (z 0 / 18,
--                   >= 4 studs from every torch), fix 2 every wall-mounted banner / shield / rack / hearth / wine rack
--                   touches its wall face and its brackets touch it too (nothing floats), fix 3 the throne / dais /
--                   carpet / statues / braziers / arch tops / banners / curios carry their style keys (Part builds
--                   stay as the collider), fix 4 no cellar clutter (hay, barrels, crates, tables, puddles, moss
--                   squares) and two curios instead; the doorways stay 8 studs clear and the Entrance / Threshold
--                   markers sit where Geo puts them; weathering anchors never overlap a prop
--   bug5dgn_review  (server) the review's fix round: every floor's mood >= the P4 preset and no in-tier light dimming,
--                   the tall _low weathering (Shadow, Nature) collides over its footprint, the B astrolabe clears the
--                   ceiling by >= 0.3, Style.Cur survives an error in BuildRun / PlaceRoom, the b rooms have no cellar
--                   leftovers (hay, barrels, wine rack, cauldron, bones, skulls)
--   client_bug5dgn_spin (client) DungeonFx turns an NC_DungeonSpin part about its local Y near the camera, rests it on
--                   Stop()
--   client_bug5dgn_mood (client) the tier mood is clamped to the P4 preset on the client too; re-read for >= 5 s
-- Deterministic: templates built fresh (Template(name, style) with a style), mock clock only. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local function serverScenarios()
	local S = {}
	local K = _G.K

	local function box(p)
		local cf, s = p.CFrame, p.Size
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local hx = math.abs(r.X) * s.X / 2 + math.abs(u.X) * s.Y / 2 + math.abs(l.X) * s.Z / 2
		local hy = math.abs(r.Y) * s.X / 2 + math.abs(u.Y) * s.Y / 2 + math.abs(l.Y) * s.Z / 2
		local hz = math.abs(r.Z) * s.X / 2 + math.abs(u.Z) * s.Y / 2 + math.abs(l.Z) * s.Z / 2
		local c = cf.Position
		return { c.X - hx, c.Y - hy, c.Z - hz, c.X + hx, c.Y + hy, c.Z + hz }
	end
	-- the gap between two boxes (0 when they touch or overlap)
	local function gap(a, b)
		local d = 0
		for i = 1, 3 do
			local g = math.max(a[i] - b[i + 3], b[i] - a[i + 3], 0)
			d = math.max(d, g)
		end
		return d
	end

	S.bug5dgn_styles = guarded("bug5dgn_styles", function()
		if not K.needBoot() then
			return
		end
		local db = K.mod("DungeonBuilder")
		if not T.check(db and type(db.StyleFor) == "function" and type(db.Styles) == "table", "bug5 styles: DungeonBuilder.StyleFor + Styles") then
			return
		end
		local want = { "c", "c", "c", "b", "b", "b", "b", "b", "a", "a", "a", "a" }
		local got, ok = {}, true
		local lastRank = 0
		for f = 1, 12 do
			local s = db.StyleFor(f)
			got[#got + 1] = tostring(s)
			if s ~= want[f] then
				ok = false
			end
			local st = db.Styles[s]
			if not st or st.Rank < lastRank then
				ok = false
			end
			lastRank = st and st.Rank or lastRank
		end
		T.check(ok, "bug5 styles: floors 1-3 The Root Conservatory (c), 4-8 The Weatherworks (b), 9-12 The Cloudkeep Undercroft (a); seriousness never drops with depth", table.concat(got, " "))
		T.eq(db.DefaultStyle, "b", "bug5 styles: the player's pick (The Weatherworks) is the default look")
		-- a run per tier: holder attributes + its rooms' wall keys in the run's style; deeper = darker mood
		local seen, amb = {}, {}
		for i, f in ipairs({ 2, 6, 11 }) do
			local okR, pocket = pcall(db.BuildRun, 9 + i, f, 900 + f)
			if T.check(okR and pocket and pocket.Model, "bug5 styles: a floor " .. f .. " run builds", tostring(pocket)) then
				local h = pocket.Model
				local s = h:GetAttribute("DungeonStyle")
				T.eq(s, db.StyleFor(f), "bug5 styles: floor " .. f .. "'s holder says its style")
				local a = h:GetAttribute("MoodAmbient")
				T.check(typeof(a) == "Color3" and type(h:GetAttribute("MoodBrightness")) == "number" and typeof(h:GetAttribute("MoodTint")) == "Color3", "bug5 styles: floor " .. f .. "'s holder carries its mood for the client lighting")
				amb[#amb + 1] = typeof(a) == "Color3" and (a.R + a.G + a.B) or 0
				pcall(db.PlaceRoom, pocket, 2)
				-- (the run's pieces are clones of the style's templates: each carries the template's Style attribute)
				local wrong = {}
				for _, d in ipairs(h:GetDescendants()) do
					local ps = d:IsA("Model") and d:GetAttribute("Style")
					if ps then
						seen[f] = (seen[f] or 0) + 1
						if ps ~= s then
							wrong[#wrong + 1] = d.Name .. "=" .. tostring(ps)
						end
					end
				end
				T.check((seen[f] or 0) >= 2 and #wrong == 0, "bug5 styles: floor " .. f .. "'s hall and rooms are the " .. tostring(s) .. " templates", (seen[f] or 0) .. " pieces; wrong " .. table.concat(wrong, ", "))
				db.FreeRun(9 + i)
			end
		end
		T.check(#amb == 3 and amb[1] > amb[2] and amb[2] > amb[3], "bug5 styles: deeper tiers are darker (ambient c > b > a)")
		K.flushErrors("bug5dgn_styles")
	end)

	S.bug5dgn_throne = guarded("bug5dgn_throne", function()
		if not K.needBoot() then
			return
		end
		local db = K.mod("DungeonBuilder")
		if not T.check(db and type(db.Template) == "function", "bug5 throne: DungeonBuilder.Template") then
			return
		end
		local Mesh = db._Mesh
		local CLUTTER = { BarrelSet = true, HayBale = true, CrateBox = true, TableSet = true, Puddle = true, Moss = true }
		local MOUNTED = { BannerHang = true, ShieldMount = true, RackSet = true, HearthSet = true, WineRackSet = true }
		local BRACKET = { BannerBracket = true, ShieldBracket = true }
		for _, st in ipairs(db.StyleOrder or { "c", "b", "a" }) do
			local model = db.Template("Throne_1", st)
			local g = db.Geo.Throne_1
			if T.check(model ~= nil and g ~= nil, "bug5 throne: the " .. st .. " boss room builds") then
				local inv = model.PrimaryPart.CFrame:Inverse()
				local torches, banners, walls, clutter, curios = {}, {}, {}, {}, 0
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("Model") and d.Name == "WallTorch" and d.PrimaryPart then
						torches[#torches + 1] = (inv * d.PrimaryPart.CFrame).Position
					elseif d:IsA("Model") and d.Name == "BannerHang" then
						local pole = d:FindFirstChild("BannerPole")
						if pole then
							banners[#banners + 1] = (inv * pole.CFrame).Position
						end
					elseif d:IsA("Model") and d.Name == "CurioSet" then
						curios = curios + 1
					end
					if CLUTTER[d.Name] then
						clutter[#clutter + 1] = d.Name
					end
					if d:IsA("BasePart") and d.Name == "Wall" then
						walls[#walls + 1] = box(d)
					end
				end
				-- fix 1: the side banners between the side torches
				local near = {}
				for _, b in ipairs(banners) do
					for _, t in ipairs(torches) do
						if math.abs(math.abs(b.X) - math.abs(t.X)) < 3 and math.abs(b.Z - t.Z) < 4 then
							near[#near + 1] = string.format("banner z %.0f / torch z %.0f", b.Z, t.Z)
						end
					end
				end
				T.check(#banners == 4 and #near == 0, "bug5 throne (" .. st .. "): four banners, none within 4 studs of a torch", #banners .. " banners; " .. table.concat(near, ", "))
				-- fix 2: wall-mounted pieces touch a wall, and so do their brackets
				local floating = {}
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("Model") and MOUNTED[d.Name] then
						local best = math.huge
						for _, p in ipairs(d:GetDescendants()) do
							if p:IsA("BasePart") and p.Transparency < 1 then
								for _, w in ipairs(walls) do
									best = math.min(best, gap(box(p), w))
								end
							end
						end
						if best > 0.06 then
							floating[#floating + 1] = d.Name .. string.format(" %.2f", best)
						end
						for _, p in ipairs(d:GetDescendants()) do
							if p:IsA("BasePart") and BRACKET[p.Name] then
								local bb = math.huge
								for _, w in ipairs(walls) do
									bb = math.min(bb, gap(box(p), w))
								end
								if bb > 0.06 then
									floating[#floating + 1] = d.Name .. "." .. p.Name .. string.format(" %.2f", bb)
								end
							end
						end
					end
				end
				T.check(#floating == 0, "bug5 throne (" .. st .. "): every banner / shield / rack / hearth / wine rack and its brackets touch the wall", table.concat(floating, ", "))
				-- fix 4: the boss room's own props
				T.check(#clutter == 0 and curios == 2, "bug5 throne (" .. st .. "): no cellar clutter (hay, barrels, crates, tables, puddles, moss), two curios", table.concat(clutter, ", ") .. " / curios " .. curios)
				-- fix 3: the designed pieces carry their style keys
				local keys = {}
				for target, r in pairs(Mesh and Mesh.Placed or {}) do
					if target.Parent and target:IsDescendantOf(model) then
						keys[r.Key] = true
					end
				end
				local miss = {}
				for _, k in ipairs({ "throne", "dais", "carpet", "statue", "brazier", "arch_10", "banner", "curio", "torch", "wall_72", "floor_60x72" }) do
					if not keys["dungeon_" .. st .. "_" .. k] then
						miss[#miss + 1] = k
					end
				end
				if st == "b" and not (keys.dungeon_b_cloud and keys.dungeon_b_ring) then
					miss[#miss + 1] = "astrolabe"
				end
				if st == "a" and not keys.dungeon_a_window then
					miss[#miss + 1] = "window"
				end
				T.check(#miss == 0, "bug5 throne (" .. st .. "): the throne, dais, carpet, statues, braziers, arch tops, banners, curios and shell carry dungeon_" .. st .. "_* keys", table.concat(miss, ", "))
				-- the astrolabe rings turn on the client (tag + speed) and their mesh rides them (ML_Weld)
				if st == "b" then
					local rings = 0
					for _, d in ipairs(model:GetDescendants()) do
						if d.Name == "AstroRing" and game:GetService("CollectionService"):HasTag(d, "NC_DungeonSpin") and type(d:GetAttribute("SpinSpeed")) == "number" and d:GetAttribute("ML_Weld") == true then
							rings = rings + 1
						end
					end
					T.eq(rings, 3, "bug5 throne (b): three astrolabe rings tagged NC_DungeonSpin with a SpinSpeed, welded meshes")
				end
				-- the markers the walk-in branch relies on: Entrance / Threshold where Geo puts them
				local base = model.PrimaryPart
				local ent = base:FindFirstChild("Entrance")
				T.check(ent and math.abs(ent.Position.X - g.Entrance.X) < 0.01 and math.abs(ent.Position.Z - g.Entrance.Z) < 0.01 and base:FindFirstChild("Threshold") ~= nil, "bug5 throne (" .. st .. "): the Entrance / Threshold markers are unchanged")
				-- sound sources tagged for the audio branch (no playback here)
				local kinds = {}
				for _, d in ipairs(model:GetDescendants()) do
					local k = d:GetAttribute("DungeonSound")
					if k and game:GetService("CollectionService"):HasTag(d, db.SoundTag) then
						kinds[string.match(k, "^(%a+)")] = true
					end
				end
				T.check(kinds.torch and kinds.brazier and kinds.curio and (st ~= "b" or kinds.astrolabe), "bug5 throne (" .. st .. "): torches, braziers, curios (and the astrolabe) are tagged " .. tostring(db.SoundTag) .. " for the audio branch")
			end
		end
		-- fix 2 in every room of every style: the wall-mounted pieces touch a wall run
		local loose = {}
		for _, st in ipairs(db.StyleOrder or {}) do
			for _, name in ipairs(db.Templates) do
				local model = db.Template(name, st)
				local walls = {}
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") and (d.Name == "Wall" or d.Name == "Plinth") then
						walls[#walls + 1] = box(d)
					end
				end
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("Model") and MOUNTED[d.Name] then
						local best = math.huge
						for _, p in ipairs(d:GetDescendants()) do
							if p:IsA("BasePart") and p.Transparency < 1 then
								for _, w in ipairs(walls) do
									best = math.min(best, gap(box(p), w))
								end
							end
						end
						if best > 0.06 then
							loose[#loose + 1] = st .. "/" .. name .. "." .. d.Name .. string.format(" %.2f", best)
						end
					end
				end
			end
		end
		T.check(#loose == 0, "bug5 rooms: in every template of every style the banners, shields, racks, hearths and wine racks touch their wall", table.concat(loose, ", "):sub(1, 300))
		-- the doors stay 8 studs clear in every style (the walk-in branch's lanes are +-3.6)
		local narrow = {}
		for _, st in ipairs(db.StyleOrder or {}) do
			db._Style.Cur = db.Styles[st]
			local holder = Instance.new("Model")
			local door = db._KitFns.door(holder, CFrame.new(), "Door_Probe", 8)
			db._Style.Cur = nil
			local xs = {}
			for _, p in ipairs(door:GetChildren()) do
				if p:IsA("BasePart") and p.Name == "Jamb" then
					local b = box(p)
					xs[#xs + 1] = b
				end
			end
			if #xs == 2 then
				local inner = math.min(math.abs(xs[1][4] - xs[2][1]), math.abs(xs[2][4] - xs[1][1]))
				if inner < 8 - 1e-3 then
					narrow[#narrow + 1] = st .. string.format(" %.2f", inner)
				end
			else
				narrow[#narrow + 1] = st .. " jambs " .. #xs
			end
			holder:Destroy()
		end
		T.check(#narrow == 0, "bug5 throne: every style's doorway is 8 studs clear between the jambs", table.concat(narrow, ", "))
		-- weathering anchors never overlap a prop (a placed room per style, its element)
		local bad = {}
		for i, f in ipairs({ 3, 7, 12 }) do
			local okR, pocket = pcall(db.BuildRun, 9 + i, f, 700 + f)
			if okR and pocket then
				pcall(db.PlaceRoom, pocket, 2)
				local props, anchors = {}, {}
				for _, d in ipairs(pocket.Model:GetDescendants()) do
					if d:IsA("BasePart") then
						if d.Name == "Weather" then
							anchors[#anchors + 1] = d
						elseif d:FindFirstAncestor("NC_Detail") or d.Parent.Name == "StatueSet" or d.Parent.Name == "BrazierSet" then
							props[#props + 1] = box(d)
						end
					end
				end
				for _, a in ipairs(anchors) do
					local ab = box(a)
					for _, p in ipairs(props) do
						if gap(ab, p) == 0 then
							bad[#bad + 1] = "floor " .. f
							break
						end
					end
				end
				db.FreeRun(9 + i)
			end
		end
		T.check(#bad == 0, "bug5 throne: no element weathering anchor overlaps a prop", table.concat(bad, ", "))
		K.flushErrors("bug5dgn_throne")
	end)

	-- the review's fix round: the readability floor of the mood, no in-tier light dimming, the tall weathering clusters
	-- collide, the astrolabe clears the ceiling, Style.Cur survives an error, the machine halls carry no cellar leftovers
	S.bug5dgn_review = guarded("bug5dgn_review", function()
		if not K.needBoot() then
			return
		end
		local db = K.mod("DungeonBuilder")
		if not T.check(db and db.MoodFloor and db.WeatherLowSolid and db._KitFns and db._Style, "bug5 review: DungeonBuilder.MoodFloor / WeatherLowSolid / _KitFns / _Style") then
			return
		end
		local fl = db.MoodFloor
		for i = 7, 9 do
			pcall(db.FreeRun, i)
		end
		-- 1. every floor's mood is at or above the P4 preset (ambient per channel, brightness); the lights keep their
		--    template brightness on every floor but the first (floor 1's +0.3 is the only change)
		local dark, dimmed = {}, {}
		for f = 1, 12 do
			local okR, pocket = pcall(db.BuildRun, 7, f, 500 + f)
			if okR and pocket and pocket.Model then
				local h = pocket.Model
				local a, b = h:GetAttribute("MoodAmbient"), h:GetAttribute("MoodBrightness")
				local o = h:GetAttribute("MoodOutdoor")
				local e = 1e-4
				if not (typeof(a) == "Color3" and a.R >= fl.Ambient.R - e and a.G >= fl.Ambient.G - e and a.B >= fl.Ambient.B - e
					and typeof(o) == "Color3" and o.R >= fl.Outdoor.R - e and o.G >= fl.Outdoor.G - e and o.B >= fl.Outdoor.B - e
					and type(b) == "number" and b >= fl.Brightness - 1e-6) then
					dark[#dark + 1] = "floor " .. f
				end
				if f > 1 then
					for _, m in ipairs(h:GetDescendants()) do
						local idx = m:IsA("Model") and m:GetAttribute("PieceIndex")
						local piece = idx and pocket.Layout.Pieces[idx]
						if piece then
							local tpl = db.Template(piece.Name, pocket.Style)
							local la, lb = {}, {}
							for _, d in ipairs(tpl:GetDescendants()) do
								if d:IsA("PointLight") then
									la[#la + 1] = d.Brightness
								end
							end
							for _, d in ipairs(m:GetDescendants()) do
								if d:IsA("PointLight") then
									lb[#lb + 1] = d.Brightness
								end
							end
							for i = 1, math.min(#la, #lb) do
								if lb[i] < la[i] - 1e-4 then
									dimmed[#dimmed + 1] = "floor " .. f .. " " .. piece.Name
									break
								end
							end
						end
					end
				end
				db.FreeRun(7)
			else
				dark[#dark + 1] = "floor " .. f .. " (no run: " .. tostring(pocket) .. ")"
			end
		end
		T.check(#dark == 0, "bug5 review: every floor's mood is at or above the P4 preset (ambient 70,62,86 per channel, brightness -0.12)", table.concat(dark, ", "))
		T.check(#dimmed == 0, "bug5 review: no floor dims its lights (the deeper look is the palette + Deepen, not darker torches)", table.concat(dimmed, ", "):sub(1, 300))
		local amb = db.Styles.a.Mood.Ambient
		T.check(amb.R >= fl.Ambient.R - 1e-4 and amb.G >= fl.Ambient.G - 1e-4 and amb.B >= fl.Ambient.B - 1e-4 and db.Styles.a.Mood.Brightness >= fl.Brightness - 1e-6, "bug5 review: the deepest tier's own mood is not below the preset")
		-- 2. the tall _low weathering (Shadow crystals, Nature ferns) stands on a collider over its footprint; the low
		--    sets not listed stay under the 1.1 step (their anchors stay walk-through)
		local lows, solid, wrong = 0, 0, {}
		for _, f in ipairs({ 1, 8 }) do
			local okR, pocket = pcall(db.BuildRun, 8, f, 610 + f)
			if okR and pocket then
				for r = 2, 6 do
					pcall(db.PlaceRoom, pocket, r)
				end
				local el = pocket.Layout.Def.Element
				local want = db.WeatherLowSolid[el]
				for _, d in ipairs(pocket.Model:GetDescendants()) do
					if d:IsA("BasePart") and d.Name == "Weather" then
						local rec = db._Mesh and db._Mesh.Placed and db._Mesh.Placed[d]
						local key = rec and rec.Key or ""
						if string.sub(key, -4) == "_low" then
							lows = lows + 1
							if want then
								local sz = Vector3.new(want.X1 - want.X0, want.Y1, want.Z1 - want.Z0)
								if d.CanCollide and d.Transparency >= 1 and (d.Size - sz).Magnitude < 1e-3 and d.Size.Y > 1.1 then
									solid = solid + 1
								else
									wrong[#wrong + 1] = el .. " " .. tostring(d.Size)
								end
							end
						end
					end
				end
				db.FreeRun(8)
			end
		end
		T.check(db.WeatherLowSolid.Shadow ~= nil and db.WeatherLowSolid.Nature ~= nil, "bug5 review: the Shadow and Nature _low clusters (over the 1.1 step) have colliders")
		T.check(lows >= 1 and solid == lows and #wrong == 0, "bug5 review: every Shadow / Nature _low weathering anchor collides over the cluster's footprint (bug batch 2 #3: no prop a player stands inside)", lows .. " low anchors, " .. solid .. " solid; " .. table.concat(wrong, ", "))
		-- 3. the B astrolabe's swept rings clear the ceiling slab by >= 0.3 stud (the ring mesh reaches 0.1 past its Part)
		local tb = db.Template("Throne_1", "b")
		local heart, ceil, reach = nil, nil, 0
		for _, d in ipairs(tb:GetDescendants()) do
			if d:IsA("BasePart") then
				if d.Name == "CloudHeart" then
					heart = d
				elseif d.Name == "Ceiling" then
					ceil = math.min(ceil or math.huge, d.Position.Y - d.Size.Y / 2)
				elseif d.Name == "AstroRing" then
					reach = math.max(reach, math.max(d.Size.X, d.Size.Y, d.Size.Z) / 2 + 0.1)
				end
			end
		end
		local base = tb.PrimaryPart
		local ceilY = ceil or (base and base.Position.Y + base.Size.Y / 2 + 15.8)
		T.check(heart ~= nil and reach > 2 and heart.Position.Y + reach <= ceilY - 0.3, "bug5 review: the astrolabe's outer ring clears the ceiling by >= 0.3 stud",
			heart and string.format("hub %.2f + %.2f vs ceiling %.2f", heart.Position.Y, reach, ceilY) or "no CloudHeart")
		-- 4. an error in a run's styled section leaves Style.Cur as it was (BuildRun's hall and PlaceRoom)
		local Kit = db._KitFns
		local realDoor = Kit.door
		db._Style.Cur = nil
		Kit.door = function()
			error("probe door failure", 0)
		end
		local okA = pcall(db.BuildRun, 9, 5, 77)
		Kit.door = realDoor
		T.check(not okA and db._Style.Cur == nil, "bug5 review: a failing BuildRun hall restores Style.Cur (no leak into later Kit calls)", tostring(db._Style.Cur and db._Style.Cur.Id))
		pcall(db.FreeRun, 9)
		local okB, pocket = pcall(db.BuildRun, 9, 10, 78)
		if T.check(okB and pocket, "bug5 review: a floor 10 run builds", tostring(pocket)) then
			Kit.door = function()
				error("probe door failure", 0)
			end
			local okP = pcall(db.PlaceRoom, pocket, 2)
			Kit.door = realDoor
			T.check(not okP and db._Style.Cur == nil, "bug5 review: a failing PlaceRoom restores Style.Cur", tostring(db._Style.Cur and db._Style.Cur.Id))
			db.FreeRun(9)
		end
		Kit.door = realDoor
		db._Style.Cur = nil
		-- 5. the machine halls (b) carry no cellar leftovers (hay, barrels, wine racks, cauldrons); the other looks keep them
		local LEFT = { BarrelSet = true, HayBale = true, WineRackSet = true, CauldronSet = true }
		local inB, inC = {}, 0
		for _, name in ipairs(db.Templates) do
			for _, d in ipairs(db.Template(name, "b"):GetDescendants()) do
				if (d:IsA("Model") and LEFT[d.Name]) or (d:IsA("BasePart") and (d.Name == "Bone" or d.Name == "Skull")) then
					inB[#inB + 1] = name .. "." .. d.Name
				end
			end
			for _, d in ipairs(db.Template(name, "c"):GetDescendants()) do
				if d:IsA("Model") and LEFT[d.Name] then
					inC = inC + 1
				end
			end
		end
		T.check(#inB == 0 and inC > 0, "bug5 review: the Weatherworks rooms swap the hay / barrels / wine rack / cauldron / bones / skulls for crates, the stand-pipe, a coil, pipe offcuts and toolboxes (the cellar looks keep them)", table.concat(inB, ", ") .. " | c " .. inC)
		K.flushErrors("bug5dgn_review")
	end)

	return S
end

local function clientScenarios()
	local S = {}
	local KC = _G.KC

	S.client_bug5dgn_spin = guarded("client_bug5dgn_spin", function()
		local ok, Fx = pcall(require, Mock.GetPath(ROOTS["client"] .. "/Controllers/DungeonFx"))
		if not T.check(ok and type(Fx) == "table" and type(Fx.Init) == "function", "bug5 spin: DungeonFx loads", tostring(Fx)) then
			return
		end
		local cam = workspace.CurrentCamera
		local at = cam and cam.CFrame.Position or Vector3.new()
		local ring = Instance.new("Part")
		ring.Name = "AstroRingProbe"
		ring.Anchored = true
		ring.Size = Vector3.new(4.8, 0.3, 0.3)
		ring.CFrame = CFrame.new(at + Vector3.new(0, 0, -20))
		ring:SetAttribute("SpinSpeed", 1)
		ring:SetAttribute("SpinIndex", 1)
		ring.Parent = workspace
		game:GetService("CollectionService"):AddTag(ring, "NC_DungeonSpin")
		local rest = ring.CFrame
		pcall(Fx.Init)
		for _ = 1, 30 do
			Fx.Step(1 / 30)
		end
		local turned = ring.CFrame
		local stats = Fx.Stats()
		T.check(stats.Rings >= 1 and (turned.Position - rest.Position).Magnitude < 1e-3 and turned.LookVector:Dot(rest.LookVector) < 0.99, "bug5 spin: a tagged ring near the camera turns about its own Y (and stays in place)", string.format("rings %d moving %d", stats.Rings, stats.Moving))
		T.check(math.abs(turned.UpVector:Dot(rest.UpVector) - 1) < 1e-3, "bug5 spin: the turn keeps the ring's local Y")
		Fx.Stop()
		T.check((ring.CFrame.Position - rest.Position).Magnitude < 1e-3 and ring.CFrame.LookVector:Dot(rest.LookVector) > 0.9999, "bug5 spin: Stop() puts the ring back at rest")
		ring:Destroy()
		KC.flushErrors("client_bug5dgn_spin")
	end)

	-- the review's fix round: the client never lights a run darker than the P4 preset, and it keeps re-reading the
	-- tier mood for a while when the run's holder is not there yet (streaming, a slow join)
	S.client_bug5dgn_mood = guarded("client_bug5dgn_mood", function()
		local ok, DC = pcall(require, Mock.GetPath(ROOTS["client"] .. "/Controllers/DungeonController"))
		local M = ok and type(DC) == "table" and DC._Mood
		if not T.check(M and type(M.Read) == "function" and type(M.Preset) == "table", "bug5 mood: DungeonController._Mood (the tier mood reader)", tostring(DC)) then
			return
		end
		local P = M.Preset
		T.check(M.Read(nil) == nil and M.Read(Instance.new("Model")) == nil, "bug5 mood: no holder / no mood attributes = the plain preset (nil)")
		local h = Instance.new("Model")
		h:SetAttribute("MoodAmbient", Color3.fromRGB(10, 10, 10))
		h:SetAttribute("MoodOutdoor", Color3.fromRGB(12, 12, 12))
		h:SetAttribute("MoodBrightness", -0.5)
		h:SetAttribute("MoodContrast", 0.2)
		h:SetAttribute("MoodTint", Color3.fromRGB(200, 200, 200))
		local m = M.Read(h)
		local a, pa = m and m.Lighting.Ambient, P.Lighting.Ambient
		T.check(m ~= nil and a.R >= pa.R - 1e-4 and a.G >= pa.G - 1e-4 and a.B >= pa.B - 1e-4 and m.ColorCorrection.Brightness >= P.ColorCorrection.Brightness - 1e-6,
			"bug5 mood: a too-dark mood is clamped to the P4 preset (ambient per channel, brightness)")
		T.check(m ~= nil and math.abs(m.ColorCorrection.Contrast - 0.2) < 1e-6, "bug5 mood: the tier's contrast still comes through")
		T.check((tonumber(M.Tries) or 0) * (tonumber(M.Retry) or 0) >= 5 and (tonumber(M.Tries) or 0) >= 3, "bug5 mood: the mood is re-read for >= 5 s (several tries) when the holder is not found at the push",
			tostring(M.Tries) .. " x " .. tostring(M.Retry))
		KC.flushErrors("client_bug5dgn_mood")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
