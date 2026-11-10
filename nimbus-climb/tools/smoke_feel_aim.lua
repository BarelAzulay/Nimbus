-- smoke_feel_aim.lua: the battle feel, Task 1 "Centre aim and the real floor (drawing only)"
-- (docs/superpowers/specs/2026-11-10-battle-feel-design.md decision 4; plan docs/superpowers/plans/2026-11-10-battle-feel.md
-- Task 1). Loaded by tools/smoke.py in the CLIENT world.
--   client_feel_aim_centre  a shot at a BossBuilder boss (its pivot = the Root at the feet) lands in the boss's bounding-box
--                           centre; an AimPoint attachment wins over the box; Config.Battle.Feel.Aim.Mode = "Pivot" gives
--                           today's pivot; the boss destroyed mid-travel: no error, the effect keeps its last centre and ends
--   client_feel_aim_floor   ground layers (the Ranged BoomRing, the Blast Blastwave, the Freeze cage) stand on ctx.Ground,
--                           never under the boss's feet root; the one raycast per Play (none per Update) finds the real floor
--                           under the target; FloorRay = false = no raycast, ctx.Ground
--   client_feel_aim_pets    pets look as today: a Melee and a Ranged pet -> pet hit lands within 0.2 of the pivot, the Strike's
--                           Reach is AttackFx.LeapReach as before
--   client_feel_aim_bite    a Melee bite on a boss lands on AttackFx.BitePoint: the boss's near edge on the flat line at the
--                           caster's height (closer than the pivot); Mode "Pivot" = today's pivot
-- Deterministic: a fake clock (Update(now) / ctx.Now), a fake MeshLibrary (every vfx_* core ready). Plain Lua 5.1 syntax.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
if game:GetService("RunService"):IsServer() then
	return S
end

local fmt = string.format
local abs, sqrt, max = math.abs, math.sqrt, math.max
local V3 = Vector3.new
local G = 3 -- the floor's top (world Y) in these scenarios

local function moduleAt(path)
	local ok, inst = pcall(Mock.GetPath, path)
	if not ok or not inst then
		return nil
	end
	local ok2, mod = pcall(require, inst)
	return ok2 and type(mod) == "table" and mod or nil
end

local function fakeMeshLibrary()
	return {
		IsReady = function(key)
			return type(key) == "string" and string.sub(key, 1, 4) == "vfx_"
		end,
		Assemble = function(spec)
			local key = type(spec) == "string" and spec or (type(spec) == "table" and spec.Key) or "?"
			local m = Instance.new("Model")
			m.Name = key
			local p = Instance.new("MeshPart")
			p.Name = "Core"
			p.Size = V3(2, 2, 2)
			p.Anchored = true
			p.Parent = m
			return m
		end,
	}
end

-- a battle unit stand-in: a Model whose PrimaryPart is its centre
local function unitModel(parent, name, pos, size)
	local m = Instance.new("Model")
	m.Name = name
	local root = Instance.new("Part")
	root.Name = "Body"
	root.Anchored = true
	root.Size = size or V3(2, 2, 2)
	root.CFrame = CFrame.new(pos)
	root.Parent = m
	m.PrimaryPart = root
	m.Parent = parent
	return m
end

local function flatDist(a, b)
	return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- the shared world of the four scenarios: AttackFx, the knob, a lava golem, a floor, the clock
local function setup(tag)
	local env = {}
	env.AF = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
	env.Config = moduleAt(ROOTS.shared .. "/Config")
	env.BB = moduleAt(ROOTS.shared .. "/BossBuilder")
	env.PB = moduleAt(ROOTS.shared .. "/PetBuilder")
	env.PC = moduleAt(ROOTS.shared .. "/PetCatalog")
	local AF = env.AF
	if not T.check(AF ~= nil and type(AF.Play) == "function" and env.BB ~= nil and env.Config ~= nil, tag .. ": AttackFx, Config, BossBuilder load") then
		return nil
	end
	local feel = env.Config.Battle and env.Config.Battle.Feel
	if not T.check(type(feel) == "table" and type(feel.Aim) == "table" and type(feel.Melee) == "table" and type(feel.Special) == "table",
		tag .. ": Config.Battle.Feel holds Melee / Aim / Special (the battle-feel knob)") then
		return nil
	end
	env.Feel = feel
	T.check(type(AF.AimOf) == "function" and type(AF.BitePoint) == "function", tag .. ": AttackFx.AimOf and AttackFx.BitePoint exist")
	if type(AF.AimOf) ~= "function" or type(AF.BitePoint) ~= "function" then
		return nil
	end
	env.saved = { Mode = feel.Aim.Mode, FloorRay = feel.Aim.FloorRay }
	feel.Aim.Mode, feel.Aim.FloorRay = "Centre", true
	AF.ClearAll()
	AF._Deps({ MeshLibrary = fakeMeshLibrary() })
	AF.SetQuality("High")
	-- the drawn units live under workspace.ClientBattle (as BattleController draws them; the floor raycast skips it)
	local cb = workspace:FindFirstChild("ClientBattle")
	if not cb then
		cb = Instance.new("Folder")
		cb.Name = "ClientBattle"
		cb.Parent = workspace
	end
	env.holder = Instance.new("Folder")
	env.holder.Name = "SmokeFeelAim_" .. tag
	env.holder.Parent = cb
	env.floorFolder = Instance.new("Folder")
	env.floorFolder.Name = "SmokeFeelAimFloor_" .. tag
	env.floorFolder.Parent = workspace
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = V3(300, 1, 300)
	floor.CFrame = CFrame.new(0, G - 0.5, 0)
	floor.Parent = env.floorFolder
	env.floor = floor
	env.clock = 7000
	env.DT = 1 / 30
	function env.run(seconds)
		local n = math.ceil(seconds / env.DT - 1e-9)
		for _ = 1, n do
			env.clock = env.clock + env.DT
			AF.Update(env.clock)
		end
	end
	function env.boss(pos, id)
		local m = env.BB.Build(id or "lava_golem", { Detail = "Low", CFrame = CFrame.new(pos) })
		if m then
			m.Parent = env.holder
		end
		return m
	end
	function env.newest()
		local live = AF._Live()
		return live[#live]
	end
	function env.ctx(over)
		local c = { Attack = "Ranged", Element = "Flame", Rarity = "Common", Stage = 0, Mine = true, Ground = G, Now = env.clock }
		for k, v in pairs(over or {}) do
			c[k] = v
		end
		return c
	end
	function env.done()
		AF.ClearAll()
		AF._Deps({ MeshLibrary = false })
		AF.SetQuality(nil)
		feel.Aim.Mode, feel.Aim.FloorRay = env.saved.Mode, env.saved.FloorRay
		pcall(env.holder.Destroy, env.holder)
		pcall(env.floorFolder.Destroy, env.floorFolder)
	end
	return env
end

local function boxCentre(model)
	local cf = model:GetBoundingBox()
	return cf.Position
end

----------------------------------------------------------------------
S.client_feel_aim_centre = guarded("client_feel_aim_centre", function()
	local env = setup("centre")
	if not env then
		return
	end
	local AF = env.AF
	local ok, err = pcall(function()
		local pet = unitModel(env.holder, "Pet", V3(0, G + 1.5, 0))
		local boss = env.boss(V3(0, G, -24))
		if not T.check(boss ~= nil, "feel aim: the lava golem builds") then
			return
		end
		local pivot = boss:GetPivot().Position
		local centre = boxCentre(boss)
		T.check(centre.Y - pivot.Y > 5, fmt("feel aim: the boss's pivot is at its feet, its box centre high above (pivot Y %.2f, centre Y %.2f)", pivot.Y, centre.Y))
		T.check(AF.Play(env.ctx({ From = { Unit = 1, Model = pet }, To = { Unit = 2, Model = boss } })), "feel aim: a Ranged Flame shot at the boss plays")
		local eff = env.newest()
		local side = eff and eff.Targets[1]
		T.check(side ~= nil and abs(AF.AimOf(side).Y - centre.Y) < 0.5, fmt("feel aim: a boss aims at its bounding-box centre, the feet root ignored (aim Y %s, centre Y %.2f)",
			tostring(side and AF.AimOf(side).Y), centre.Y))
		T.check(eff ~= nil and abs(eff.Hit.Y - centre.Y) < 0.5 and abs(eff.Hit.X - centre.X) < 0.5 and abs(eff.Hit.Z - centre.Z) < 0.5,
			fmt("feel aim: the shot's Hit is the body centre (Hit %s, centre %s)", tostring(eff and eff.Hit), tostring(centre)))
		env.run(0.05)
		T.check(eff ~= nil and abs(eff.Hit.Y - centre.Y) < 0.5, "feel aim: the Hit stays on the centre frame after frame")
		AF.ClearAll()

		-- an AimPoint attachment wins over the box (read when the model is first seen)
		local boss2 = env.boss(V3(30, G, -24))
		local p2 = boss2:GetPivot().Position
		local host = nil
		for _, d in ipairs(boss2:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Root" then
				host = d
				break
			end
		end
		local att = Instance.new("Attachment")
		att.Name = "AimPoint"
		att.Position = host.CFrame:PointToObjectSpace(V3(p2.X, p2.Y + 9, p2.Z))
		att.Parent = host
		local pet2 = unitModel(env.holder, "Pet2", V3(30, G + 1.5, 0))
		T.check(AF.Play(env.ctx({ From = { Unit = 3, Model = pet2 }, To = { Unit = 4, Model = boss2 } })), "feel aim: a shot at a boss with an AimPoint plays")
		local e2 = env.newest()
		T.check(e2 ~= nil and abs(AF.AimOf(e2.Targets[1]).Y - (p2.Y + 9)) < 0.1 and abs(e2.Hit.Y - (p2.Y + 9)) < 0.1,
			fmt("feel aim: an AimPoint attachment wins over the box (aim Y %s, want %.2f)", tostring(e2 and AF.AimOf(e2.Targets[1]).Y), p2.Y + 9))

		-- Aim.Mode = "Pivot" restores today's pivot aim
		env.Feel.Aim.Mode = "Pivot"
		local a = AF.AimOf(e2.Targets[1])
		T.check((a - p2).Magnitude < 1e-3, fmt("feel aim: Aim.Mode = \"Pivot\" aims at the pivot as today (%s vs %s)", tostring(a), tostring(p2)))
		env.run(0.04)
		T.check((e2.Hit - p2).Magnitude < 1e-3, "feel aim: ... and the live effect's Hit follows it at once")
		env.Feel.Aim.Mode = "Centre"
		AF.ClearAll()

		-- "target gone": the boss destroyed mid-travel
		local boss3 = env.boss(V3(-30, G, -24))
		local pet3 = unitModel(env.holder, "Pet3", V3(-30, G + 1.5, 0))
		local c3 = boxCentre(boss3)
		local errors0 = AF.Stats().Errors
		T.check(AF.Play(env.ctx({ From = { Unit = 5, Model = pet3 }, To = { Unit = 6, Model = boss3 } })), "feel aim: a shot at the third boss plays")
		local e3 = env.newest()
		env.run(0.1)
		local last = e3.T[1]
		boss3:Destroy()
		local fine = pcall(env.run, 0.3)
		T.check(fine and AF.Stats().Errors == errors0, "feel aim: the target destroyed mid-travel: Update runs with no error")
		T.check(last ~= nil and (e3.T[1] - last).Magnitude < 1e-6 and abs(e3.T[1].Y - c3.Y) < 0.5,
			fmt("feel aim: ... the effect keeps the last known CENTRE (%s, centre %s), never drops to the feet", tostring(e3.T[1]), tostring(c3)))
		env.run(math.max(0.1, e3.End - env.clock) + 0.1)
		local still = false
		for _, e in ipairs(AF._Live()) do
			still = still or e == e3
		end
		T.check(not still, "feel aim: ... and it ends by its End")
	end)
	env.done()
	T.check(ok, "feel aim centre: no error", tostring(err))
end)

----------------------------------------------------------------------
local function itemsBy(eff, pred)
	local out = {}
	for _, it in ipairs(eff and eff.Items or {}) do
		if it.Kit and pred(it) then
			out[#out + 1] = it
		end
	end
	return out
end

local function layerId(id)
	return function(it)
		return type(it.Layer) == "table" and it.Layer.Id == id
	end
end

S.client_feel_aim_floor = guarded("client_feel_aim_floor", function()
	local env = setup("floor")
	if not env then
		return
	end
	local AF = env.AF
	local spatial = Mock._spatial
	local realRay = spatial.raycast
	local rays = 0
	spatial.raycast = function(...)
		rays = rays + 1
		return realRay(...)
	end
	local ok, err = pcall(function()
		local pet = unitModel(env.holder, "Pet", V3(0, G + 1.5, 0))
		local boss = env.boss(V3(0, G, -24))
		local pivot = boss:GetPivot().Position
		T.info("feel aim floor: the boss pivot", fmt("pivot Y %.2f over the floor %.2f", pivot.Y, G))

		local function ringY(over, id)
			AF.ClearAll()
			T.check(AF.Play(env.ctx(over)), fmt("feel floor: %s %s plays (%s)", tostring(over.Attack or "Ranged"), tostring(over.Kind or over.Element or "Flame"), id))
			local eff = env.newest()
			env.run(math.max(0.05, eff.Start + eff.Times.Impact + 0.06 - env.clock))
			local rings = itemsBy(eff, layerId(id))
			if #rings == 0 then
				return nil, eff
			end
			return rings[1].Kit.Root.Position.Y, eff
		end

		-- the Ranged BoomRing on the boss: on the floor (+ the ring's own 0.1 lift), not under the feet root
		local y, eff = ringY({ From = { Unit = 1, Model = pet }, To = { Unit = 2, Model = boss } }, "BoomRing")
		T.check(eff ~= nil and eff.FloorY ~= nil and abs(eff.FloorY - G) < 1e-3, fmt("feel floor: eff.FloorY = ctx.Ground (%s vs %.2f)", tostring(eff and eff.FloorY), G))
		T.check(y ~= nil and abs(y - (G + 0.15)) < 0.05, fmt("feel floor: the Ranged BoomRing on the boss lies on the floor (Y %s, want %.2f = ctx.Ground + 0.05 + the flat ring's 0.1)", tostring(y), G + 0.15))
		-- the Blast Blastwave
		local yb = ringY({ Attack = "Special", Kind = "Blast", Element = "Flame", Rarity = "Legendary", From = { Unit = 1, Model = pet }, To = { Unit = 2, Model = boss } }, "Blastwave")
		T.check(yb ~= nil and abs(yb - (G + 0.15)) < 0.05, fmt("feel floor: the Blast Blastwave on the boss lies on the floor (Y %s, want %.2f)", tostring(yb), G + 0.15))
		-- the Freeze cage (Path Ground) stands on the floor
		AF.ClearAll()
		T.check(AF.Play(env.ctx({ Attack = "Special", Kind = "Freeze", Element = "Frost", Rarity = "Rare", From = { Unit = 1, Model = pet }, To = { Unit = 2, Model = boss } })), "feel floor: a Freeze plays")
		local ef = env.newest()
		local cages = itemsBy(ef, function(it)
			return it.TR ~= nil and it.TS ~= nil and it.Base ~= nil
		end)
		local tMid = ef.Start + (cages[1] and (cages[1].TR + 0.2) or ef.Times.Impact)
		env.run(math.max(0.05, tMid - env.clock))
		local baseY = nil
		if cages[1] then
			local it = cages[1]
			local h = it.Base.Y * it.S
			baseY = it.Kit.Root.Position.Y - 0.5 * h -- risen fully (outBack done), not sinking yet: y = h x 0.5 over the base
		end
		T.check(baseY ~= nil and abs(baseY - (G + 0.05)) < 0.06, fmt("feel floor: the Freeze cage stands on ctx.Ground (base Y %s, want %.2f)", tostring(baseY), G + 0.05))

		-- the raycast: one per Play, none per Update; it finds the real floor under the target (here 0.4 over ctx.Ground)
		env.floor.CFrame = CFrame.new(0, G - 0.5 + 0.4, 0)
		AF.ClearAll()
		rays = 0
		T.check(AF.Play(env.ctx({ From = { Unit = 1, Model = pet }, To = { Unit = 2, Model = boss } })), "feel floor: a shot plays (raised floor)")
		local er = env.newest()
		local afterPlay = rays
		env.run(0.3)
		T.check(afterPlay == 1 and rays == 1, fmt("feel floor: FloorRay = true makes exactly one Raycast per Play, none per Update (%d after Play, %d after 9 Updates)", afterPlay, rays))
		T.check(er ~= nil and abs(er.FloorY - (G + 0.4)) < 0.01, fmt("feel floor: ... and the ray's floor wins over ctx.Ground (FloorY %s, want %.2f)", tostring(er and er.FloorY), G + 0.4))
		-- a floor more than FLOOR_RAY_MAX away from ctx.Ground is not believed
		T.eq(AF.FLOOR_RAY_MAX, 6, "feel floor: AttackFx.FLOOR_RAY_MAX = 6 studs")
		env.floor.CFrame = CFrame.new(0, G - 0.5 - 9, 0)
		AF.ClearAll()
		AF.Play(env.ctx({ From = { Unit = 1, Model = pet }, To = { Unit = 2, Model = boss } }))
		local efar = env.newest()
		T.check(efar ~= nil and abs(efar.FloorY - G) < 1e-3, fmt("feel floor: a ray floor 9 studs off ctx.Ground is ignored (FloorY %s)", tostring(efar and efar.FloorY)))
		-- FloorRay = false: ctx.Ground, no raycast
		env.floor.CFrame = CFrame.new(0, G - 0.5 + 0.4, 0)
		env.Feel.Aim.FloorRay = false
		AF.ClearAll()
		rays = 0
		AF.Play(env.ctx({ From = { Unit = 1, Model = pet }, To = { Unit = 2, Model = boss } }))
		local enr = env.newest()
		env.run(0.2)
		T.check(rays == 0 and enr ~= nil and abs(enr.FloorY - G) < 1e-3, fmt("feel floor: FloorRay = false: no Raycast (%d), FloorY = ctx.Ground (%s)", rays, tostring(enr and enr.FloorY)))
		env.Feel.Aim.FloorRay = true
		-- Aim.Mode = "Pivot" keeps the floor fix: the ring still lies on the floor
		env.Feel.Aim.Mode = "Pivot"
		env.floor.CFrame = CFrame.new(0, G - 0.5, 0)
		local yp = ringY({ From = { Unit = 1, Model = pet }, To = { Unit = 2, Model = boss } }, "BoomRing")
		T.check(yp ~= nil and abs(yp - (G + 0.15)) < 0.05, fmt("feel floor: Aim.Mode = \"Pivot\" keeps the floor fix (ring Y %s)", tostring(yp)))
		env.Feel.Aim.Mode = "Centre"
	end)
	spatial.raycast = realRay
	env.done()
	T.check(ok, "feel aim floor: no error", tostring(err))
end)

----------------------------------------------------------------------
S.client_feel_aim_pets = guarded("client_feel_aim_pets", function()
	local env = setup("pets")
	if not env then
		return
	end
	local AF, PB, PC = env.AF, env.PB, env.PC
	if not T.check(PB ~= nil and PC ~= nil and type(PC.Pets) == "table", "feel aim pets: PetBuilder and PetCatalog load") then
		env.done()
		return
	end
	local ok, err = pcall(function()
		local defs = {}
		for _, def in ipairs(PC.Pets) do
			if def.Role == "Combat" and not def.EventOnly then
				defs[#defs + 1] = def
			end
		end
		local bad, checked, worst = {}, 0, 0
		local step = max(1, math.floor(#defs / 12))
		local i = 1
		local unit = 10
		while i <= #defs and checked < 12 do
			local def = defs[i]
			local ma = PB.Build(def, { Detail = "Low" })
			local mb = PB.Build(def, { Detail = "Low" })
			if ma and mb then
				ma.Parent, mb.Parent = env.holder, env.holder
				ma:PivotTo(CFrame.new(100 + checked * 20, G + 1.5, 0))
				mb:PivotTo(CFrame.new(100 + checked * 20, G + 1.5, -9) * CFrame.Angles(0, math.pi, 0))
				local pivot = mb:GetPivot().Position
				for _, attack in ipairs({ "Ranged", "Melee" }) do
					AF.ClearAll()
					unit = unit + 2
					if AF.Play(env.ctx({ Attack = attack, From = { Unit = unit, Model = ma }, To = { Unit = unit + 1, Model = mb } })) then
						local eff = env.newest()
						local d = (eff.Hit - pivot).Magnitude
						worst = max(worst, d)
						if d > 0.2 then
							bad[#bad + 1] = fmt("%s %s %.2f", tostring(def.Id), attack, d)
						end
						if attack == "Melee" then
							env.run(math.max(0.02, eff.Start + eff.Times.Release + 0.03 - env.clock)) -- (into the Strike)
							local pose = AF.Pose(unit)
							local want = AF.LeapReach({ Model = ma, Last = ma:GetPivot().Position }, { Model = mb, Last = pivot })
							if not (pose and pose.Reach and want and abs(pose.Reach - want) < 1e-6) then
								bad[#bad + 1] = fmt("%s Strike Reach %s vs LeapReach %s", tostring(def.Id), tostring(pose and pose.Reach), tostring(want))
							end
						end
					else
						bad[#bad + 1] = tostring(def.Id) .. " " .. attack .. " did not play"
					end
				end
				checked = checked + 1
			end
			i = i + step
		end
		T.check(checked >= 8 and #bad == 0, fmt("feel aim pets: %d pets, Melee + Ranged pet -> pet: the hit within 0.2 of the pivot as today (worst %.3f), the Strike's Reach = LeapReach", checked, worst),
			table.concat(bad, "; "))
	end)
	env.done()
	T.check(ok, "feel aim pets: no error", tostring(err))
end)

----------------------------------------------------------------------
S.client_feel_aim_bite = guarded("client_feel_aim_bite", function()
	local env = setup("bite")
	if not env then
		return
	end
	local AF = env.AF
	local ok, err = pcall(function()
		local petPos = V3(4, G + 1.5, 0)
		local pet = unitModel(env.holder, "Pet", petPos)
		local boss = env.boss(V3(-2, G, -16))
		local pivot = boss:GetPivot().Position
		T.check(AF.Play(env.ctx({ Attack = "Melee", From = { Unit = 1, Model = pet }, To = { Unit = 2, Model = boss } })), "feel bite: a Melee bite on the boss plays")
		local eff = env.newest()
		local bite = AF.BitePoint(eff.Src, eff.Targets[1])
		T.check(bite ~= nil and (eff.Hit - bite).Magnitude < 1e-3, fmt("feel bite: the bite's Hit is AttackFx.BitePoint (%s vs %s)", tostring(eff.Hit), tostring(bite)))
		T.check(bite ~= nil and abs(bite.Y - petPos.Y) < 1e-3, fmt("feel bite: at the caster's height (Y %s, caster %.2f)", tostring(bite and bite.Y), petPos.Y))
		-- the near edge along the flat line from the caster through the boss's pivot (an independent spanAlong)
		local d = V3(pivot.X - petPos.X, 0, pivot.Z - petPos.Z)
		local u = d.Unit
		local cf, size = boss:GetBoundingBox()
		local half = 0.5 * (abs(u:Dot(cf.RightVector)) * size.X + abs(u:Dot(cf.UpVector)) * size.Y + abs(u:Dot(cf.LookVector)) * size.Z)
		local along = (cf.Position - petPos):Dot(u) - half
		local got = bite and flatDist(bite, petPos) or -1
		T.check(bite ~= nil and abs(got - along) < 0.05, fmt("feel bite: on the boss's near edge (%.2f studs from the caster, want %.2f)", got, along))
		T.check(bite ~= nil and got < d.Magnitude - 0.5, fmt("feel bite: closer to the caster than the pivot (%.2f < %.2f)", got, d.Magnitude))
		T.check(bite ~= nil and flatDist(bite, pivot) > 0.5, "feel bite: not the pivot (the feet root's centre)")
		env.run(0.1)
		T.check((eff.Hit - AF.BitePoint(eff.Src, eff.Targets[1])).Magnitude < 1e-3, "feel bite: the Hit follows the bite point frame after frame")
		-- the Strike's leap is unchanged (LeapReach from the pivots)
		env.run(math.max(0.02, eff.Start + eff.Times.Release + 0.03 - env.clock)) -- (into the Strike)
		local pose = AF.Pose(1)
		local want = AF.LeapReach({ Model = pet, Last = petPos }, { Model = boss, Last = pivot })
		T.check(pose ~= nil and pose.Reach ~= nil and want ~= nil and abs(pose.Reach - want) < 1e-6, fmt("feel bite: the Strike's Reach is LeapReach as today (%s vs %s)", tostring(pose and pose.Reach), tostring(want)))
		-- BitePoint without both points: nil
		T.check(AF.BitePoint({}, { Last = pivot }) == nil and AF.BitePoint(nil, nil) == nil, "feel bite: BitePoint is nil without both points")
		-- Aim.Mode = "Pivot": today's pivot
		env.Feel.Aim.Mode = "Pivot"
		env.run(0.04)
		T.check((eff.Hit - pivot).Magnitude < 1e-3, fmt("feel bite: Aim.Mode = \"Pivot\" bites the pivot as today (%s)", tostring(eff.Hit)))
		env.Feel.Aim.Mode = "Centre"
	end)
	env.done()
	T.check(ok, "feel aim bite: no error", tostring(err))
end)

return S
