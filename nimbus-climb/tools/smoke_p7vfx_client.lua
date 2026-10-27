-- smoke_p7vfx_client.lua: the pet attack VFX engine on the client (docs/superpowers/plans/2026-10-23-pet-attack-vfx.md
-- Task 6). Loaded by tools/smoke.py in the CLIENT world.
--   client_p7vfx_engine  client/Controllers/AttackFx: for every element Melee / Ranged / Special (Blast) / Element (Cone)
--               plays at High and is gone after its beats (Charge + Release + Travel + Impact + the longer of Linger and
--               the alive detail); flipbook emitters (Grid4x4, mode + fps of blender/vfx/textures.json, rbxassetid:// +
--               the TextureIds number); 40 simultaneous plays keep Stats() within MAX_LIVE / MAX_STEPPED / the per-effect
--               caps and Play returns false once over; 200 sequential plays leave only the pooled kits (no leaks, steady);
--               Review Focus 1 (no From.Model, the target destroyed mid-travel: no error, ends at its last known point);
--               Review Focus 3 (two plays on one unit 0.05 s apart: Pose shows only the second, with the crossfade info);
--               Review Focus 5 (SetQuality("Low") with 5 live effects: within one Update no Beam / Trail is left, new
--               plays use <= 2 emitters and no bloom); a texture missing from TextureIds = Play false; cores not ready =
--               texture layers only; Mine = false never punches (no hook call) and AttackFx never touches the camera.
-- Deterministic: a fake clock (Update(now) / ctx.Now), a fake MeshLibrary for the cores where the test needs them.
--   client_p7vfx_battle  BattleController plays AttackFx (Task 7): a recorded Boss Raid replayed one event at a time:
--               every Hit / Special / Element / KO plays AttackFx.Play exactly once on arrival (impact due when the event
--               plays) with the unit's element / rarity / stage (boss hits: my pet's Hurt; zone / burn / special / element
--               damage: none), the pets strike and flinch (opts.Pose), the caps (FxParts 260 / Numbers 26 / Flashes 8);
--               handler by handler: no cube Fx while AttackFx plays, the old Fx.* when Play returns false, DODGED! on a
--               miss, Ko replaces the cube poof; a fallback replay (Play always false) is drawn by the cubes; Ruling 12:
--               idle units show PetPoses IdleBattle at their own phase, an attack pose replaces it and it comes back;
--               the KO on the render clock (Ko on arrival, the down snapshot later): the pose holds, the effect plays,
--               no Cancel, parked after KO_PARK_FX; the fallback KO still poofs and parks at 0.3 s; the End message
--               before the sim's End: the winners' Victory starts after the grace and is not cut;
--               Review Focus 4 + Ruling 11: the killing blow + End in one batch: the blow stays live past its impact, no
--               new effect starts, Live == 0 and the pools at keep size within 1.0 s; a Leave mid-effect: at once.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
local IS_SERVER = game:GetService("RunService"):IsServer()
local fmt = string.format

if IS_SERVER then
	return S
end

local ELEMENTS = { "Water", "Flame", "Frost", "Nature", "Earth", "Storm", "Celestial", "Shadow" }

-- "rb": Windows text mode stops at byte 0x1A
local function readFile(rel)
	for _, prefix in ipairs({ "", "../", "nimbus-climb/" }) do
		local fh = io.open(prefix .. rel, "rb")
		if fh then
			local src = fh:read("*a")
			fh:close()
			return src
		end
	end
	return nil
end

local function moduleAt(path)
	local ok, inst = pcall(Mock.GetPath, path)
	if not ok or not inst then
		return nil
	end
	local ok2, mod = pcall(require, inst)
	return ok2 and type(mod) == "table" and mod or nil
end

-- the flipbook of every grid-4 sheet in the manifest: key -> { Mode, Fps }
local function manifestFlipbooks()
	local src = readFile("blender/vfx/textures.json")
	local out = {}
	if not src then
		return out
	end
	for line in string.gmatch(src, "[^\n]+") do
		local key = string.match(line, '"key"%s*:%s*"([%w_]+)"')
		local grid = tonumber(string.match(line, '"grid"%s*:%s*(%d+)'))
		if key and grid == 4 then
			out[key] = { Mode = string.match(line, '"mode"%s*:%s*"(%a+)"'), Fps = tonumber(string.match(line, '"fps"%s*:%s*(%d+)')) }
		end
	end
	return out
end

-- a battle unit stand-in: a Model whose PrimaryPart is its centre
local function unitModel(parent, name, pos)
	local m = Instance.new("Model")
	m.Name = name
	local root = Instance.new("Part")
	root.Name = "Body"
	root.Anchored = true
	root.Size = Vector3.new(2, 2, 2)
	root.CFrame = CFrame.new(pos)
	root.Parent = m
	m.PrimaryPart = root
	m.Parent = parent
	return m
end

-- a MeshLibrary stand-in whose vfx_* cores are all ready (single part "Core", like the real templates)
local function fakeMeshLibrary(counter)
	return {
		IsReady = function(key)
			return type(key) == "string" and string.sub(key, 1, 4) == "vfx_"
		end,
		Assemble = function(spec)
			local key = type(spec) == "string" and spec or (type(spec) == "table" and spec.Key) or "?"
			counter.n = counter.n + 1
			local m = Instance.new("Model")
			m.Name = key
			local p = Instance.new("MeshPart")
			p.Name = "Core"
			p.Size = Vector3.new(2, 2, 2)
			p.Anchored = true
			p.Parent = m
			return m
		end,
	}
end

-- nothing visible left under the effects folder: parts hidden, emitters off, beams / trails / lights off
local function allHidden(folder)
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			return false, d:GetFullName()
		elseif (d:IsA("Beam") or d:IsA("Trail") or d:IsA("ParticleEmitter")) and d.Enabled then
			return false, d:GetFullName()
		elseif d:IsA("Light") and d.Enabled and d.Brightness > 0 then
			return false, d:GetFullName()
		elseif d:IsA("ImageLabel") and d.ImageTransparency < 1 then -- a glow disc's soft sheet
			return false, d:GetFullName()
		end
	end
	return true
end

S.client_p7vfx_engine = guarded("client_p7vfx_engine", function()
	local Fx = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
	local Cat = moduleAt(ROOTS.shared .. "/AttackFxCatalog")
	local Ids = moduleAt(ROOTS.shared .. "/TextureIds")
	if not T.check(Fx ~= nil and type(Fx.Play) == "function" and type(Fx.Update) == "function" and type(Fx.Pose) == "function"
		and type(Fx.Cancel) == "function" and type(Fx.ClearAll) == "function" and type(Fx.SetQuality) == "function"
		and type(Fx.Stats) == "function", "AttackFx loads (Play, Update, Pose, Cancel, ClearAll, SetQuality, Stats)")
		or not T.check(Cat ~= nil and Ids ~= nil, "AttackFxCatalog and TextureIds load") then
		return
	end
	T.eq(Fx.MAX_LIVE, 10, "AttackFx.MAX_LIVE = 10 full effects")
	T.check(type(Fx.MAX_EMITTERS) == "table" and Fx.MAX_EMITTERS.High == 6 and Fx.MAX_EMITTERS.Low == 2, "emitters per effect: 6 High / 2 Low")

	local cores = { n = 0 }
	Fx.ClearAll()
	Fx._Deps({ MeshLibrary = fakeMeshLibrary(cores) })
	Fx.SetQuality("High")
	local punches = {}
	Fx.Hooks.Punch = function(amount, seconds)
		punches[#punches + 1] = { amount, seconds }
	end
	local holder = Instance.new("Folder")
	holder.Name = "SmokeP7VfxEngine"
	holder.Parent = workspace
	local A = unitModel(holder, "A", Vector3.new(0, 2, 0))
	local B = unitModel(holder, "B", Vector3.new(0, 2, -12))

	local clock = 5000
	local DT = 1 / 30
	local function run(seconds, each)
		local n = math.ceil(seconds / DT - 1e-9)
		for _ = 1, n do
			clock = clock + DT
			Fx.Update(clock)
			if each then
				each()
			end
		end
	end
	local function ctx(over)
		local c = {
			Attack = "Melee", Element = "Flame", Rarity = "Common", Stage = 0, Mine = true,
			From = { Unit = 1, Model = A }, To = { Unit = 2, Model = B }, Ground = 0.5, Now = clock,
		}
		for k, v in pairs(over or {}) do
			c[k] = v
		end
		return c
	end
	-- the effect's length from the catalog alone (Distance 12: the units above)
	local function lengthOf(c)
		local r = Cat.Resolve({ Element = c.Element, Attack = c.Attack, Kind = c.Kind, Shape = c.Shape, Rarity = c.Rarity, Stage = c.Stage, PetId = c.PetId, Mine = c.Mine, Distance = 12 })
		if not r then
			return nil
		end
		local alive = (type(r.Alive) == "table" and type(r.Alive.Seconds) == "number") and r.Alive.Seconds or 0
		return r.ImpactAt + r.Beats.Impact + math.max(r.Beats.Linger, alive)
	end
	local folder = Fx.Folder()
	T.check(folder ~= nil and folder.Parent and folder.Parent.Name == "ClientBattle" and folder.Parent.Parent == workspace,
		"the kits live under workspace.ClientBattle.AttackFx")
	if not folder then
		return
	end

	-- 1) every element: Melee / Ranged / Special (Blast) / Element (Cone) at High, gone after its beats -----------------
	local flip = manifestFlipbooks()
	local plays, badPlay, badGone, badLength, flipBad, flipSeen, coreSeen = 0, {}, {}, {}, {}, 0, 0
	local combos = {
		{ Attack = "Melee" }, { Attack = "Ranged" }, { Attack = "Special", Kind = "Blast" }, { Attack = "Element", Shape = "Cone" },
	}
	for _, element in ipairs(ELEMENTS) do
		for _, combo in ipairs(combos) do
			for _, rarity in ipairs({ "Common", "Epic", "Secret" }) do
				local c = ctx({ Element = element, Attack = combo.Attack, Kind = combo.Kind, Shape = combo.Shape, Rarity = rarity, Now = clock })
				local label = fmt("%s %s%s %s", element, combo.Attack, combo.Kind and (" " .. combo.Kind) or (combo.Shape and (" " .. combo.Shape) or ""), rarity)
				local len = lengthOf(c)
				plays = plays + 1
				if not Fx.Play(c) then
					badPlay[#badPlay + 1] = label
				else
					local live = Fx._Live()[1]
					if not (live and len and math.abs(live.End - live.Start - len) < 0.02) then
						badLength[#badLength + 1] = fmt("%s: %s vs %s", label, tostring(live and (live.End - live.Start)), tostring(len))
					end
					local s0 = Fx.Stats()
					if s0.Cores > 0 then
						coreSeen = coreSeen + 1
					end
					-- the flipbooks of this effect's emitters
					for _, d in ipairs(folder:GetDescendants()) do
						if d:IsA("ParticleEmitter") and d.Texture ~= "" then
							local key = nil
							for k, id in pairs(Ids) do
								if d.Texture == "rbxassetid://" .. tostring(id) then
									key = k
								end
							end
							local f = key and flip[key]
							if not (f and d.FlipbookLayout == Enum.ParticleFlipbookLayout.Grid4x4 and d.FlipbookMode == Enum.ParticleFlipbookMode[f.Mode]
								and math.abs(d.FlipbookFramerate.Min - f.Fps) < 1e-6 and d.LightEmission >= 0) then
								flipBad[#flipBad + 1] = label .. " " .. tostring(key or d.Texture)
							else
								flipSeen = flipSeen + 1
							end
						end
					end
					run((len or 3) + 0.1)
					local s = Fx.Stats()
					local hidden, what = allHidden(folder)
					if s.Live ~= 0 or s.Emitters ~= 0 or s.Beams ~= 0 or s.Trails ~= 0 or s.Lights ~= 0 or s.Cores ~= 0 or not hidden then
						badGone[#badGone + 1] = label .. " " .. tostring(what or ("Live " .. s.Live))
					end
				end
			end
		end
	end
	T.check(#badPlay == 0, fmt("High: every element x Melee / Ranged / Special Blast / Element Cone x 3 rarities plays (%d plays)", plays), table.concat(badPlay, ", "))
	T.check(#badLength == 0, "each effect lasts its beats: Charge + Release + Travel + Impact + max(Linger, alive detail)", table.concat(badLength, "; "))
	T.check(#badGone == 0, "each effect is gone after its beats (nothing live, every pooled kit hidden)", table.concat(badGone, ", "))
	T.check(#flipBad == 0 and flipSeen > 0, fmt("textured emitters are 4x4 flipbooks with the manifest mode + fps, rbxassetid:// + the TextureIds number (%d seen)", flipSeen), table.concat(flipBad, ", "))
	T.check(coreSeen == plays and cores.n > 0, fmt("solid cores from MeshLibrary.Assemble play when ready (%d / %d plays, %d assembled)", coreSeen, plays, cores.n))
	T.check(Fx.Stats().Errors == 0, "no effect ended by an error")

	-- 2) 40 simultaneous plays: Stats within the limits; Play false once over --------------------------------------------
	local cap = Fx.MAX_EMITTERS.High
	local within, results, firstFalse, steppedOk = true, {}, nil, true
	local function checkLimits(where)
		local s = Fx.Stats()
		local n = s.Live + s.Stepped
		if s.Live > Fx.MAX_LIVE or s.Stepped > Fx.MAX_STEPPED or s.Emitters > n * cap or s.Beams > n * Fx.MAX_BEAMS or s.Trails > n * Fx.MAX_TRAILS or s.Lights > n * Fx.MAX_LIGHTS then
			within = false
			T.info("over the limits at " .. where, fmt("Live %d Stepped %d Emitters %d Beams %d Trails %d Lights %d", s.Live, s.Stepped, s.Emitters, s.Beams, s.Trails, s.Lights))
		end
	end
	local stress = {}
	for i = 1, 40 do
		local element = ELEMENTS[(i - 1) % #ELEMENTS + 1]
		local combo = combos[(i - 1) % #combos + 1]
		local c = ctx({ Element = element, Attack = combo.Attack, Kind = combo.Kind, Shape = combo.Shape, Rarity = "Secret", Mine = (i % 2 == 0), Now = clock, From = { Unit = 100 + i, Model = A } })
		stress[i] = c
		local before = Fx.Stats()
		results[i] = Fx.Play(c)
		checkLimits("play " .. i)
		if results[i] and before.Live >= Fx.MAX_LIVE then
			-- a stepped-down play: one band below its own
			local live = Fx._Live()
			local e = live[#live]
			if not (e and e.Stepped and e.Recipe.Band == 3) then
				steppedOk = false
			end
		end
		if not results[i] and not firstFalse then
			firstFalse = i
		end
	end
	run(0.6, function()
		checkLimits("update")
	end)
	local trues = 0
	for i = 1, 40 do
		if results[i] then
			trues = trues + 1
		end
	end
	T.check(within, "40 simultaneous plays: Stats() never passes MAX_LIVE / MAX_STEPPED or the per-effect emitter / beam / trail / light caps")
	T.eq(trues, Fx.MAX_LIVE + Fx.MAX_STEPPED, "40 simultaneous plays: MAX_LIVE full + MAX_STEPPED stepped-down effects play")
	T.check(firstFalse == Fx.MAX_LIVE + Fx.MAX_STEPPED + 1, "Play returns false once over (the caller falls back to the cube Fx)", tostring(firstFalse))
	T.check(steppedOk, "over MAX_LIVE an effect steps down one band (Secret -> band 3)")
	run(4)
	T.eq(Fx.Stats().Live + Fx.Stats().Stepped, 0, "the stress plays all end")

	-- 3) 200 sequential plays: only the pooled kits stay (no leaks) -------------------------------------------------------
	local seq = {}
	for _, element in ipairs({ "Flame", "Storm", "Water", "Shadow", "Nature" }) do
		for _, combo in ipairs(combos) do
			seq[#seq + 1] = { Element = element, Attack = combo.Attack, Kind = combo.Kind, Shape = combo.Shape }
		end
	end
	local n100 = nil
	for i = 1, 200 do
		local s = seq[(i - 1) % #seq + 1]
		Fx.Play(ctx({ Element = s.Element, Attack = s.Attack, Kind = s.Kind, Shape = s.Shape, Rarity = (i % 3 == 0) and "Mythic" or "Rare", Now = clock }))
		run(0.12)
		if i % 4 == 0 then
			run(3.2)
		end
		if i == 100 then
			run(3.5)
			n100 = #folder:GetDescendants()
		end
	end
	run(3.5)
	local st = Fx.Stats()
	local n200 = #folder:GetDescendants()
	T.check(st.Live == 0 and n200 == st.PoolInstances, fmt("after 200 plays the effects folder holds exactly the pooled kits (%d instances, Stats %d)", n200, st.PoolInstances))
	T.check(n100 == n200, fmt("the pool is steady: %s instances after 100 plays, %d after 200", tostring(n100), n200))
	T.check(st.Pooled <= Fx.POOL_KEEP_TOTAL, fmt("pooled kits <= the keep size (%d <= %d)", st.Pooled, Fx.POOL_KEEP_TOTAL))

	-- 4) Review Focus 1: no From.Model, the target destroyed mid-travel -----------------------------------------------------
	local C = unitModel(holder, "C", Vector3.new(4, 2, -14))
	local c1 = ctx({ Attack = "Ranged", Element = "Celestial", Rarity = "Legendary", From = { Unit = 7, Pos = Vector3.new(0, 2, 0) }, To = { Unit = 8, Model = C }, Now = clock })
	local errs0 = Fx.Stats().Errors
	T.check(Fx.Play(c1), "RF1: plays with From.Model = nil (From.Pos only)")
	local e1 = Fx._Live()[1]
	local travelMid = e1 and (e1.Times.Travel + e1.Times.Impact) / 2 - (clock - e1.Start) or 0.2
	run(math.max(DT, travelMid))
	local last = C:GetPivot().Position
	C:Destroy()
	local okRun, err = pcall(run, 0.05)
	local e1b = Fx._Live()[1]
	local endPoint = e1b and e1b.Targets[1] and e1b.Targets[1].Last
	T.check(okRun and endPoint ~= nil and (endPoint - last).Magnitude < 1e-3, "RF1: the target destroyed mid-travel: no error, the effect heads for its last known point", tostring(err))
	run(0.4)
	local e1c = Fx._Live()[1]
	local corePos = e1c and e1c.CorePos
	T.check(corePos == nil or (corePos - last).Magnitude < 2.5, "RF1: the impact lands at the last known point", tostring(corePos))
	run(3)
	T.check(Fx.Stats().Errors == errs0 and Fx.Stats().Live == 0, "RF1: the effect ends cleanly (no error)")

	-- 5) Review Focus 3: two plays on one unit 0.05 s apart -> only the second's pose ------------------------------------
	T.check(Fx.Play(ctx({ Attack = "Melee", From = { Unit = 21, Model = A }, Now = clock })), "RF3: the first play")
	run(0.05)
	T.check(Fx.Play(ctx({ Attack = "Ranged", Element = "Water", From = { Unit = 21, Model = A }, Now = clock })), "RF3: the second play 0.05 s later")
	local pose = Fx.Pose(21)
	T.check(pose ~= nil and pose.Name == "Windup" and pose.Ranged == true and pose.P < 0.3, "RF3: Pose shows the second play (ranged Windup from its start)", pose and fmt("%s %.2f %s", tostring(pose.Name), pose.P, tostring(pose.Ranged)))
	T.check(pose ~= nil and type(pose.Blend) == "number" and pose.Blend < 1 and type(pose.Prev) == "table" and pose.Prev.Ranged ~= true,
		"RF3: the switch carries the crossfade info (Prev = the first's pose, Blend < 1)")
	local onlySecond, sawShoot, blendDone = true, false, false
	run(1.6, function()
		local p = Fx.Pose(21)
		if p then
			if p.Ranged ~= true then
				onlySecond = false
			end
			if p.Name == "Shoot" then
				sawShoot = true
			end
			if p.Blend == 1 and p.Prev == nil then
				blendDone = true
			end
		end
	end)
	T.check(onlySecond and sawShoot and blendDone, "RF3: from then on only the second play's poses (ranged Windup -> Shoot), crossfade done after ~0.12 s")
	T.check(Fx.Pose(2) == nil or Fx.Pose(2).Name == "Hurt", "the victim's pose is Hurt (or none)")
	run(3)
	T.check(Fx.Pose(21) == nil, "RF3: no pose once the effects are over")
	-- Ko holds at p = 1 until cancelled
	Fx.Play(ctx({ Attack = "Ko", From = { Unit = 22, Model = A }, To = nil, Now = clock }))
	run(3)
	local ko = Fx.Pose(22)
	T.check(ko ~= nil and ko.Name == "Ko" and ko.P == 1, "Ko: the pose holds at p = 1 after the effect")
	Fx.Cancel(22)
	T.check(Fx.Pose(22) == nil, "Cancel(unit) drops its pose")

	-- 6) Review Focus 5: SetQuality("Low") with 5 live effects ------------------------------------------------------------
	local heavy = {
		{ Attack = "Ranged", Element = "Storm", Rarity = "Secret" },
		{ Attack = "Special", Kind = "Pounce", Element = "Storm", Rarity = "Secret" },
		{ Attack = "Special", Kind = "Beam", Element = "Flame", Rarity = "Mythic" },
		{ Attack = "Melee", Element = "Storm", Rarity = "Mythic" },
		{ Attack = "Ranged", Element = "Shadow", Rarity = "Legendary" },
	}
	for i, h in ipairs(heavy) do
		Fx.Play(ctx({ Attack = h.Attack, Kind = h.Kind, Element = h.Element, Rarity = h.Rarity, From = { Unit = 40 + i, Model = A }, Now = clock }))
	end
	run(0.75)
	local hs = Fx.Stats()
	T.check(hs.Live == 5 and hs.Beams + hs.Trails > 0, fmt("RF5: 5 live effects with Beams / Trails (%d beams, %d trails)", hs.Beams, hs.Trails))
	Fx.SetQuality("Low")
	run(DT)
	local ls = Fx.Stats()
	local liveBeam = false
	for _, d in ipairs(folder:GetDescendants()) do
		if (d:IsA("Beam") or d:IsA("Trail")) and d.Enabled then
			liveBeam = true
		end
	end
	T.check(ls.Beams == 0 and ls.Trails == 0 and not liveBeam, "RF5: within one Update after SetQuality(\"Low\") no live Beam / Trail remains")
	local before = Fx.Stats().Emitters
	T.check(Fx.Play(ctx({ Attack = "Melee", Element = "Storm", Rarity = "Secret", From = { Unit = 60, Model = A }, Now = clock })), "RF5: plays at Low")
	local lowE = Fx._Live()[#Fx._Live()]
	T.check(lowE and lowE.Emitters <= 2 and Fx.Stats().Emitters - before <= 2, "RF5: a new play at Low uses <= 2 emitters", lowE and tostring(lowE.Emitters))
	local lowBloom = false
	for _, it in ipairs(lowE and lowE.Items or {}) do
		if it.Layer and (it.Layer.Id == "Bloom" or it.Layer.Kind == "Beam" or it.Layer.Kind == "Trail") then
			lowBloom = true
		end
	end
	T.check(not lowBloom, "RF5: Low draws no Beam / Trail / bloom layer")
	run(4)
	Fx.SetQuality("High")

	-- 7) a texture key missing from TextureIds -> Play false --------------------------------------------------------------
	local partial = {}
	for k, v in pairs(Ids) do
		if k ~= "fx_flame" then
			partial[k] = v
		end
	end
	Fx._Deps({ TextureIds = partial })
	T.check(Fx.Play(ctx({ Element = "Flame", Attack = "Melee", Now = clock })) == false, "a texture key missing from TextureIds: Play returns false (the caller falls back)")
	T.check(Fx.Play(ctx({ Element = "Water", Attack = "Melee", Now = clock })) == true, "an effect whose textures are all there still plays")
	run(3)
	Fx._Deps({ TextureIds = false })
	T.check(Fx.Play(ctx({ Attack = "Banana", Now = clock })) == false and Fx.Play(ctx({ Element = "Plasma", Now = clock })) == false
		and Fx.Play(ctx({ From = {}, Now = clock })) == false, "unknown attack / element or no source point: Play returns false")

	-- 8) cores not ready: the texture layers only -------------------------------------------------------------------------
	Fx._Deps({ MeshLibrary = { IsReady = function() return false end, Assemble = function() return nil end } })
	T.check(Fx.Play(ctx({ Element = "Flame", Attack = "Ranged", Rarity = "Epic", Now = clock })), "cores not ready: the effect still plays")
	local ns = Fx.Stats()
	T.check(ns.Cores == 0 and ns.Emitters > 0, "cores not ready: texture layers only (no core, emitters on)")
	run(3)
	Fx._Deps({ MeshLibrary = fakeMeshLibrary(cores) })

	-- 9) Mine = false: no camera punch; AttackFx never touches the camera ---------------------------------------------------
	local cam = workspace.CurrentCamera
	local cf0, fov0 = cam and cam.CFrame, cam and cam.FieldOfView
	punches = {}
	Fx.Play(ctx({ Element = "Storm", Attack = "Special", Kind = "Blast", Rarity = "Secret", Mine = false, Now = clock }))
	run(3)
	T.check(#punches == 0 and (not cam or (cam.CFrame == cf0 and cam.FieldOfView == fov0)), "Mine = false: no camera punch, no camera change")
	Fx.Play(ctx({ Element = "Storm", Attack = "Special", Kind = "Blast", Rarity = "Secret", Mine = true, Now = clock }))
	run(3)
	T.check(#punches == 1 and punches[1][1] > 0 and punches[1][1] <= 0.35, "Mine = true at band 3+: one punch through Hooks.Punch, <= SHAKE_MAX 0.35", punches[1] and tostring(punches[1][1]))
	T.check(not cam or (cam.CFrame == cf0 and cam.FieldOfView == fov0), "AttackFx never moves the camera itself (the punch is routed by the caller)")
	punches = {}
	Fx.Play(ctx({ Element = "Storm", Attack = "Special", Kind = "Blast", Rarity = "Common", Mine = true, Now = clock }))
	run(3)
	T.check(#punches == 0, "Mine = true below band 3: no camera punch")
	-- the screen-edge glow (own pet, band 4) and a signature's dimming (own pet) go through hooks too
	local glows, dims = 0, 0
	Fx.Hooks.ScreenGlow = function()
		glows = glows + 1
	end
	Fx.Hooks.DimWorld = function()
		dims = dims + 1
	end
	Fx.Play(ctx({ Element = "Shadow", Attack = "Special", Kind = "Blast", PetId = "eclipse_dragon", Rarity = "Secret", Mine = false, Now = clock }))
	run(3)
	T.check(glows == 0 and dims == 0, "Mine = false: no screen glow, no dimming")
	Fx.Play(ctx({ Element = "Shadow", Attack = "Special", Kind = "Blast", PetId = "eclipse_dragon", Rarity = "Secret", Mine = true, Now = clock }))
	run(3)
	T.check(glows == 1 and dims == 1, "Mine = true: Eclipse Nova calls ScreenGlow once and DimWorld once", fmt("%d glows, %d dims", glows, dims))
	Fx.Hooks.ScreenGlow, Fx.Hooks.DimWorld = nil, nil

	-- 10) DueAt: impact never after the event; an early event waits and lands exactly on it ---------------------------
	local due = clock + 0.05
	Fx.Play(ctx({ Element = "Flame", Attack = "Melee", Rarity = "Legendary", DueAt = due, Now = clock }))
	local ed = Fx._Live()[#Fx._Live()]
	T.check(ed and ed.Start + ed.Times.Impact <= due + 1e-6 and ed.Start >= clock - 1e-6, "DueAt sooner than the beats: the charge is shortened, impact lands by the event")
	run(3)
	due = clock + 2
	Fx.Play(ctx({ Element = "Flame", Attack = "Ranged", Rarity = "Rare", DueAt = due, Now = clock }))
	ed = Fx._Live()[#Fx._Live()]
	T.check(ed and math.abs(ed.Start + ed.Times.Impact - due) < 1e-6, "DueAt later than the beats: the effect waits and impacts exactly at the event")
	run(5)

	-- 10b) player note 1: a Ranged attack is a shot that visibly crosses the gap; Melee stays the close swipe ---------
	local Poses = moduleAt(ROOTS.shared .. "/PetPoses")
	local function posesOf(unit, seconds)
		local names, order, forward = {}, {}, -math.huge
		run(seconds, function()
			local p = Fx.Pose(unit)
			if p and names[p.Name] == nil then
				names[p.Name] = true
				order[#order + 1] = p.Name
			end
			if p and Poses then
				local f = -Poses.Sample(p.Name, p.P, p.Ranged).Body.Position.Z -- (pets face -Z: forward = -Z)
				forward = math.max(forward, f)
			end
		end)
		return names, table.concat(order, " > "), forward
	end
	-- the poses: Ranged = the ranged Windup (rear back) then Shoot, never the Strike lunge; Melee = Windup then Strike
	local rc = ctx({ Attack = "Ranged", Element = "Flame", Rarity = "Rare", From = { Unit = 31, Model = A }, To = { Unit = 32, Model = B }, Now = clock })
	T.check(Fx.Play(rc), "note 1: a Ranged play")
	local rNames, rOrder, rFwd = posesOf(31, 1.5)
	T.check(rNames.Windup and rNames.Shoot and not rNames.Strike and rFwd < 0.05,
		"note 1: the Ranged pose is Windup (rear back) then Shoot, never the Strike lunge (the body never moves forward)", fmt("%s, forward max %.3f", rOrder, rFwd))
	run(3)
	T.check(Fx.Play(ctx({ Attack = "Melee", Element = "Flame", Rarity = "Rare", From = { Unit = 33, Model = A }, To = { Unit = 34, Model = B }, Now = clock })), "note 1: a Melee play")
	local mNames, mOrder, mFwd = posesOf(33, 1.5)
	T.check(mNames.Strike and not mNames.Shoot and mFwd > 1.0, "note 1: Melee is unchanged: Windup then the Strike lunge forward", fmt("%s, forward max %.3f", mOrder, mFwd))
	run(3)
	-- the travel: the shot leaves the mouth, is seen between the two pets mid-flight and lands on the target; a Streak
	-- trail rides it; the flight lasts at least MinTravel even when the event leaves only the render delay (0.12 s)
	local lead = 0.12
	local rl = ctx({ Attack = "Ranged", Element = "Flame", Rarity = "Common", DueAt = clock + lead, Now = clock })
	T.check(Fx.Play(rl), "note 1: a Ranged play with the battle's short lead")
	local es = Fx._Live()[#Fx._Live()]
	local minTravel = Cat.Beats.MinTravel
	local flight = es and (es.Times.Impact - es.Times.Travel) or 0
	T.check(es and flight >= minTravel - 1e-6 and type(rl.ImpactLate) == "number" and math.abs(rl.ImpactLate - (es.Start + es.Times.Impact - (clock + lead))) < 1e-6
		and rl.ImpactLate > 0 and rl.ImpactLate <= minTravel + 1e-6,
		"note 1: a short lead keeps the shot's MinTravel flight; ctx.ImpactLate = how much after the event it lands",
		es and fmt("flight %.3f (min %.2f), late %s", flight, minTravel, tostring(rl.ImpactLate)))
	local streak, life = false, nil
	for _, it in ipairs(es and es.Items or {}) do
		if it.Kind == "Trail" and it.Layer and it.Layer.Id == "Streak" and it.Mode == "Core" then
			streak, life = true, it.Kit and it.Kit.Trail.Lifetime
		end
	end
	T.check(streak, "note 1: a Streak trail rides the shot (even at Common)")
	-- (Task 8: a short comet tail, never a tether back to the mouth: well under the flight time)
	T.check(type(life) == "number" and life > 0 and life <= 0.1 and life < flight * 0.5,
		"note 1: the Streak is a short comet tail (its Lifetime, not the 0.2 s default)", tostring(life))
	local src, dst = A:GetPivot().Position, B:GetPivot().Position
	local gap = (dst - src).Magnitude
	run(es.Times.Travel + flight * 0.5 - (clock - es.Start))
	local mid = es.CorePos
	local along = mid and (mid - src):Dot((dst - src).Unit) or -1
	T.check(mid ~= nil and along > gap * 0.25 and along < gap * 0.85, "note 1: mid-flight the shot is between the caster and the target",
		fmt("%.2f of %.2f studs along", along, gap))
	run(flight * 0.5 + 0.02)
	T.check(es.CorePos ~= nil and (es.CorePos - es.Hit).Magnitude < 0.05, "note 1: ... and it lands on the target")
	run(3)
	local ml = ctx({ Attack = "Melee", Element = "Flame", Rarity = "Common", DueAt = clock + lead, Now = clock })
	Fx.Play(ml)
	local em = Fx._Live()[#Fx._Live()]
	T.check(em and (ml.ImpactLate or 0) == 0 and em.Start + em.Times.Impact <= clock + lead + 1e-6, "note 1: Melee still lands by the event (ImpactLate 0)",
		tostring(ml.ImpactLate))
	run(3)

	-- 11) ground-flat layers lie on the floor (ctx.Ground), not under it ------------------------------------------------
	local crackId = Ids.fx_crack
	Fx.Play(ctx({ Element = "Earth", Attack = "Melee", Rarity = "Rare", Ground = 1.0, Now = clock }))
	local ec = Fx._Live()[#Fx._Live()]
	run((ec.Times.Impact - (clock - ec.Start)) + 0.05)
	local crackY, discY = nil, nil
	for _, it in ipairs(ec.Items) do
		if it.Kind == "Emitter" and it.Layer.Texture == "fx_crack" and it.Kit then
			crackY = it.Kit.Root.Position.Y
		elseif it.Kind == "Disc" and it.Kit then
			discY = it.Kit.Root.Position.Y
		end
	end
	T.check(crackId ~= nil and crackY ~= nil and crackY > 1.0 and crackY < 1.25, "a ground-flat sheet (Earth's crack) lies on the floor", tostring(crackY))
	T.check(discY ~= nil and discY > 1.0 and discY < 1.25, "a glow disc (ground glow) lies on the floor", tostring(discY))
	-- (Task 8: the glow disc is a soft fx_glow sheet on the cylinder's up face, not a hard Neon plate)
	local soft = nil
	for _, it in ipairs(ec.Items) do
		if it.Kind == "Disc" and it.Kit then
			local up = it.Kit.Root.CFrame:VectorToWorldSpace(Vector3.new(1, 0, 0))
			soft = it.Soft == true and it.Kit.Root.Transparency == 1 and it.Kit.Img.ImageTransparency < 1
				and it.Kit.Img.Image == "rbxassetid://" .. tostring(Ids.fx_glow) and it.Kit.Gui.Face == Enum.NormalId.Right and up.Y > 0.99
		end
	end
	T.check(soft == true, "the glow disc is a soft glow image facing up (the part itself stays invisible)")
	run(3)

	-- 12) an error mid-build: Play returns false, counts the error, and every kit taken so far goes back (no orphan) ------
	-- warm-up: the same effect once, so the pools already hold every kit it takes
	local mid = ctx({ Element = "Flame", Attack = "Melee", Rarity = "Common", Now = clock })
	T.check(Fx.Play(mid), "mid-build error: the warm-up play")
	run(3)
	local reads, armed = {}, false
	local throwing = setmetatable({}, {
		__index = function(_, key)
			reads[key] = (reads[key] or 0) + 1
			-- texturesOk reads each key once; the 2nd read of the Burst sheet comes after the core and the charge
			-- emitter were taken
			if armed and key == "fx_flame" and reads[key] >= 2 then
				error("forced mid-build failure")
			end
			return Ids[key]
		end,
	})
	local errBefore = Fx.Stats().Errors
	local poolBefore, descBefore = Fx.Stats().PoolInstances, #folder:GetDescendants()
	Fx._Deps({ TextureIds = throwing })
	armed = true
	mid.Now = clock
	local out0 = #Mock.Output
	local played = Fx.Play(mid)
	armed = false
	Fx._Deps({ TextureIds = false })
	-- AttackFx's own warn() for the forced error is expected here: turned into a print, so the client world's
	-- flushWarnings (client_final) only reports foreign warnings
	local expectedWarn = false
	for i = out0 + 1, #Mock.Output do
		local o = Mock.Output[i]
		if o.kind == "warn" and string.find(o.text, "forced mid-build failure", 1, true) then
			o.kind = "print"
			expectedWarn = true
		end
	end
	T.check(expectedWarn or played == false, "mid-build error: AttackFx warns once (warnOnce) about the failed Play")
	local after = Fx.Stats()
	T.check(played == false and after.Errors == errBefore + 1 and (reads.fx_glow or 0) >= 2,
		"mid-build error (after the core and a layer were taken): Play returns false, Stats().Errors + 1", fmt("played %s, errors %d -> %d", tostring(played), errBefore, after.Errors))
	T.check(after.Live == 0 and after.Emitters == 0 and after.Cores == 0 and after.PoolInstances == poolBefore and #folder:GetDescendants() == descBefore,
		"mid-build error: every kit taken goes back to its pool (no orphan instances)", fmt("pool %d -> %d, folder %d -> %d", poolBefore, after.PoolInstances, descBefore, #folder:GetDescendants()))
	local hidden2, what2 = allHidden(folder)
	T.check(hidden2, "mid-build error: the returned kits are hidden", tostring(what2))

	-- 13) a charge glow dropped for lack of time takes no emitter slot (an over-cap recipe: >= 7 emitter layers, cap 6) --
	-- (Task 9: every catalog recipe fits the cap now, so the over-cap recipe is SYNTHETIC: the real Flame Secret Melee
	-- (a mouth charge glow + 5 more emitters) plus 3 extra impact emitters, through a catalog stand-in)
	local function engineEmitter(l)
		return type(l) == "table" and (l.Kind == "Emitter" or (l.Kind == "Decal" and type(l.Texture) == "string"))
	end
	local synthCat = setmetatable({
		Resolve = function(req)
			local r = Cat.Resolve(req)
			if r and req.Element == "Flame" and req.Attack == "Melee" then
				for i = 1, 3 do
					r.Layers[#r.Layers + 1] = { Id = "Synth" .. i, Kind = "Emitter", Texture = "fx_glow", Beat = "Impact", At = "Target", Color = Color3.new(1, 1, 1), Count = 4, Size = 1 }
				end
			end
			return r
		end,
	}, { __index = Cat })
	local over = nil
	do
		local r = synthCat.Resolve({ Element = "Flame", Attack = "Melee", Rarity = "Secret", Stage = 0, Mine = true, Distance = 12 })
		local n, hasCharge = 0, false
		for _, l in ipairs(r and r.Layers or {}) do
			if engineEmitter(l) then
				n = n + 1
				hasCharge = hasCharge or ((l.Beat or "Impact") == "Charge" and l.At == "Source" and l.Kind ~= "Decal")
			end
		end
		if r and engineEmitter(r.Alive) then
			n = n + 1
		end
		if n >= Fx.MAX_EMITTERS.High + 1 and hasCharge then
			over = { Element = "Flame", Attack = "Melee", N = n }
		end
	end
	Fx._Deps({ AttackFxCatalog = synthCat })
	local function drawnIds(em)
		local ids = {}
		for _, it in ipairs(em and em.Items or {}) do
			if it.Kind == "Emitter" and it.Layer then
				ids[it.Layer.Id] = true
			end
		end
		return ids
	end
	if T.check(over ~= nil, "a synthetic over-cap recipe (7+ emitters with a mouth charge) tests the emitter cap") then
		Fx.Play(ctx({ Element = over.Element, Attack = over.Attack, Kind = over.Kind, Rarity = "Secret", From = { Unit = 70, Model = A }, DueAt = clock, Now = clock }))
		local em = Fx._Live()[#Fx._Live()]
		local ids = drawnIds(em)
		T.check(em and em.Times.Release == 0 and not ids.Charge and ids.Burst and em.Emitters == math.min(Fx.MAX_EMITTERS.High, over.N - 1),
			"no charge time: the dropped charge glow frees its emitter slot (the burst is drawn, the cap filled)",
			fmt("%s %s %s: %d layers, %s emitters", over.Element, over.Attack, tostring(over.Kind), over.N, em and tostring(em.Emitters) or "?"))
		run(3)
		Fx.Play(ctx({ Element = over.Element, Attack = over.Attack, Kind = over.Kind, Rarity = "Secret", From = { Unit = 70, Model = A }, Now = clock }))
		local em2 = Fx._Live()[#Fx._Live()]
		local ids2 = drawnIds(em2)
		T.check(em2 and em2.Emitters == Fx.MAX_EMITTERS.High and ids2.Burst, "over the cap: 6 emitters, the impact burst always kept",
			em2 and tostring(em2.Emitters))
		run(3)
	end
	Fx._Deps({ AttackFxCatalog = false })

	-- 13b) Task 9: Low quality's 2 emitters are chosen on purpose: the Burst + the recipe's LowKeep (the element's most
	-- characteristic emitter), never left to the rank (which would keep an impact layer or the charge glow)
	Fx.SetQuality("Low")
	local lowWant = {
		{ "Water", "Melee", "Ripple" }, { "Flame", "Ranged", "Mantle" }, { "Flame", "Melee", "Alive" }, { "Nature", "Melee", "Thorns" },
		{ "Earth", "Melee", "Dust" }, { "Shadow", "Ranged", "Glass" }, { "Storm", "Melee", "ZigZag" }, { "Celestial", "Ranged", "Rays" },
	}
	local lowBad = {}
	for _, w in ipairs(lowWant) do
		Fx.ClearAll()
		Fx.Play(ctx({ Element = w[1], Attack = w[2], Rarity = "Secret", From = { Unit = 72, Model = A }, Now = clock }))
		local el = Fx._Live()[#Fx._Live()]
		local ids, n = {}, 0
		for _, it in ipairs(el and el.Items or {}) do
			if it.Kind == "Emitter" and it.Layer then
				ids[it.Layer.Alive and "Alive" or it.Layer.Id] = true
				n = n + 1
			end
		end
		if not (el and n == 2 and ids.Burst and ids[w[3]]) then
			local list = {}
			for k in pairs(ids) do
				list[#list + 1] = k
			end
			lowBad[#lowBad + 1] = fmt("%s %s: %s", w[1], w[2], table.concat(list, ","))
		end
		run(3)
	end
	T.check(#lowBad == 0, "Low quality: 2 emitters = the Burst + the element's chosen one (LowKeep)", table.concat(lowBad, " | "))
	Fx.SetQuality("High")
	Fx.ClearAll()

	-- 13c) Task 9 (Studio: every Secret shell drew 50-80 % white, the "white ball"): the band 4 shot's shell breathes from
	-- its OWN colour into the rim's, never toward white; the white plasma is the small heart inside
	local shellBad, shellSeen = {}, 0
	for _, e in ipairs({ "Water", "Nature", "Storm", "Shadow" }) do
		Fx.ClearAll()
		Fx.Play(ctx({ Element = e, Attack = "Ranged", Rarity = "Secret", From = { Unit = 73, Model = A }, Now = clock }))
		local el = Fx._Live()[#Fx._Live()]
		local main = nil
		for _, it in ipairs(el and el.Items or {}) do
			if it.Kind == "Solid" and it.Shift and not main then
				main = it
			end
		end
		local worst = 0
		run(0.6, function()
			local part = main and main.Kit and main.Kit.Root
			if part and part.Transparency < 1 then
				shellSeen = shellSeen + 1
				local c = part.Color
				worst = math.max(worst, math.min(c.R, c.G, c.B)) -- (white = every channel high)
			end
		end)
		if not main or worst > 0.75 then
			shellBad[#shellBad + 1] = fmt("%s: %s", e, main and fmt("min channel up to %.2f", worst) or "no shifting shell")
		end
	end
	T.check(#shellBad == 0 and shellSeen > 0, "band 4 shot: the shifting shell keeps its colour (never drawn near white)", table.concat(shellBad, " | "))
	Fx.ClearAll()
	-- 13d) Task 9 (Studio, Storm s3: the bolt grew toward the target on its own clock, racing ahead of the shot, low over
	-- the floor): on a flying shot the Path bolt runs from the mouth to the shot itself
	Fx.Play(ctx({ Element = "Storm", Attack = "Ranged", Rarity = "Common", From = { Unit = 74, Model = A }, Now = clock }))
	local se = Fx._Live()[#Fx._Live()]
	local bolt = nil
	for _, it in ipairs(se and se.Items or {}) do
		if it.Kind == "Beam" and it.Layer and it.Layer.Id == "Bolt" and it.I == 1 then
			bolt = it
		end
	end
	local onShot, inFlight, worstGap = 0, 0, 0
	run(0.8, function()
		local tt = se and (clock - se.Start) or 0
		if bolt and bolt.Kit.Beam.Enabled and se.CorePos and tt > se.Times.Travel + 0.03 and tt < se.Times.Impact - 0.03 then
			inFlight = inFlight + 1
			local gap = (bolt.Kit.H1.Position - se.CorePos).Magnitude
			worstGap = math.max(worstGap, gap)
			if gap < 0.05 then
				onShot = onShot + 1
			end
		end
	end)
	T.check(bolt ~= nil and inFlight > 0 and onShot == inFlight, "Storm's ranged bolt runs from the mouth to the flying shot (its tip on the shot)",
		fmt("%d / %d frames on the shot, worst gap %.2f", onShot, inFlight, worstGap))
	Fx.ClearAll()
	-- 13e) Task 9 review I1 / I2 (+ M6): the alive detail is DRAWN under the caps, not only in the recipe: for every
	-- element x Melee / Ranged x rarity at High the effect builds >= 1 Alive item (emitter / beam / mesh / disc); a
	-- constellation (Connect) alive draws all its lines; every beam layer of the recipe gets at least one beam when the
	-- recipe has <= MAX_BEAMS beam layers; the beam / emitter caps hold. (Built in catalog order with the alive detail
	-- last, Storm's own Bolt + Crackle took all 4 beams from Rare up: no stray strikes, no Mythic ShotArcs; the Celestial
	-- Secret shot drew 1 of its 3 constellation lines)
	local aliveBad, aliveSeen = {}, 0
	for _, e in ipairs({ "Flame", "Water", "Frost", "Nature", "Earth", "Storm", "Celestial", "Shadow" }) do
		for _, attack in ipairs({ "Melee", "Ranged" }) do
			for _, rarity in ipairs(Cat.Rarities) do
				Fx.ClearAll()
				local played = Fx.Play(ctx({ Element = e, Attack = attack, Rarity = rarity, From = { Unit = 75, Model = A }, Now = clock }))
				local el = played and Fx._Live()[#Fx._Live()] or nil
				local r = el and el.Recipe
				local alive, aliveBeams, beamLayers, beamsOf = 0, 0, {}, {}
				for _, it in ipairs(el and el.Items or {}) do
					if it.Layer and it.Layer.Alive then
						alive = alive + 1
						if it.Kind == "Beam" then
							aliveBeams = aliveBeams + 1
						end
					end
					if it.Kind == "Beam" and it.Layer then
						beamsOf[it.Layer] = (beamsOf[it.Layer] or 0) + 1
					end
				end
				for _, l in ipairs(r and r.Layers or {}) do
					if l.Kind == "Beam" then
						beamLayers[#beamLayers + 1] = l
					end
				end
				local why = nil
				if not el then
					why = "no effect"
				elseif not (type(r.Alive) == "table" and r.Alive.Kind) then
					why = "no alive detail in the recipe"
				elseif alive == 0 then
					why = fmt("no Alive item drawn (%d beams, %d emitters)", el.Beams, el.Emitters)
				elseif r.Alive.Kind == "Beam" and r.Alive.Motion == "Connect" and aliveBeams < math.min(3, r.Alive.Count or 1) then
					why = fmt("%d of %d constellation lines", aliveBeams, math.min(3, r.Alive.Count or 1))
				elseif el.Beams > Fx.MAX_BEAMS or el.Emitters > Fx.MAX_EMITTERS.High then
					why = fmt("over the caps: %d beams, %d emitters", el.Beams, el.Emitters)
				elseif #beamLayers + ((r.Alive.Kind == "Beam") and 1 or 0) <= Fx.MAX_BEAMS then
					for _, l in ipairs(beamLayers) do
						if not beamsOf[l] then
							why = (why and why .. ", " or "beam layer not drawn: ") .. tostring(l.Id)
						end
					end
				end
				if why then
					aliveBad[#aliveBad + 1] = fmt("%s %s %s: %s", e, attack, rarity, why)
				else
					aliveSeen = aliveSeen + 1
				end
			end
		end
	end
	T.check(#aliveBad == 0 and aliveSeen == 8 * 2 * #Cat.Rarities, "every element x Melee / Ranged x rarity draws its alive detail under the caps (beams ranked: alive, own, ladder)",
		fmt("%d ok; %s", aliveSeen, table.concat(aliveBad, " | ")))
	Fx.ClearAll()
	-- 13f) review M2 / M3: an emitter's lit / hot rules read its EFFECTIVE LightEmission (the layer's override, else the
	-- sheet's): Storm's Burst (fx_glow, BurstLight 0.4) is lit by the scene and opens in its own colour (not 45 % white);
	-- the ZigZag sparks (0.5) ignore the scene light, not hot; the plain fx_glow charge (sheet 1) still starts hot
	Fx.Play(ctx({ Element = "Storm", Attack = "Ranged", Rarity = "Secret", From = { Unit = 76, Model = A }, Now = clock }))
	local lit = Fx._Live()[#Fx._Live()]
	local function emOf(id)
		for _, it in ipairs(lit and lit.Items or {}) do
			if it.Kind == "Emitter" and it.Layer and it.Layer.Id == id then
				return it.Kit.Em, it.Layer
			end
		end
		return nil
	end
	local function near(a, b)
		return a and b and math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 1e-3
	end
	local bEm, bL = emOf("Burst")
	local zEm, zL = emOf("ZigZag")
	local cEm, cL = emOf("Charge")
	local litWhy = {}
	if not (bEm and math.abs(bEm.LightEmission - 0.4) < 1e-6 and bEm.LightInfluence == 0.6 and near(bEm.Color.Keypoints[1].Value, bL.Color)) then
		litWhy[#litWhy + 1] = bEm and fmt("Burst LE %.2f LI %.2f", bEm.LightEmission, bEm.LightInfluence) or "no Burst"
	end
	if not (zEm and zEm.LightInfluence == 0 and near(zEm.Color.Keypoints[1].Value, zL.Color)) then
		litWhy[#litWhy + 1] = zEm and fmt("ZigZag LI %.2f", zEm.LightInfluence) or "no ZigZag"
	end
	if not (cEm and cEm.LightEmission == 1 and cEm.LightInfluence == 0 and not near(cEm.Color.Keypoints[1].Value, cL.Color)) then
		litWhy[#litWhy + 1] = cEm and "Charge not hot" or "no Charge"
	end
	T.check(#litWhy == 0, "emitters: lit / hot by the effective LightEmission (a half-lit Burst is scene-lit, not white-hot)", table.concat(litWhy, " | "))
	Fx.ClearAll()
	-- review Important 1: Flame's Lava Slam (the old over-cap case) fits now: its Scorch is a glow disc, no emitter is cut
	Fx.Play(ctx({ Element = "Flame", Attack = "Special", Kind = "Blast", PetId = "magma_cub", Rarity = "Secret", From = { Unit = 71, Model = A }, Now = clock }))
	local fl = Fx._Live()[#Fx._Live()]
	local flIds, scorchDisc = drawnIds(fl), false
	for _, it in ipairs(fl and fl.Items or {}) do
		scorchDisc = scorchDisc or (it.Kind == "Disc" and it.Layer and it.Layer.Id == "Scorch")
	end
	local wantFl = 0
	local fr = Cat.Resolve({ Element = "Flame", Attack = "Special", Kind = "Blast", PetId = "magma_cub", Rarity = "Secret", Stage = 0, Mine = true, Distance = 12 })
	for _, l in ipairs(fr and fr.Layers or {}) do
		if engineEmitter(l) then
			wantFl = wantFl + 1
		end
	end
	wantFl = wantFl + (fr and engineEmitter(fr.Alive) and 1 or 0)
	T.check(fl and scorchDisc and not flIds.Scorch and flIds.SigLavaCrack and flIds.Burst and wantFl <= Fx.MAX_EMITTERS.High and fl.Emitters == wantFl,
		"review Important 1: Flame's Lava Slam fits the cap: Scorch is a glow disc, every emitter layer (lava crack, burst ...) drawn",
		fmt("%s of %d emitters, scorch disc %s", fl and tostring(fl.Emitters) or "?", wantFl, tostring(scorchDisc)))
	run(3)

	-- 14) fix round 3, player note (a): the melee Strike is a leap whose Amp grows with the rarity band (Common 1, Secret
	-- bigger, <= PetPoses.LEAP_AMP_MAX); the ranged Shoot carries none -------------------------------------------------
	local function strikeAmp(rarity, attack)
		Fx.ClearAll()
		Fx.Play(ctx({ Attack = attack or "Melee", Element = "Flame", Rarity = rarity, From = { Unit = 80, Model = A }, To = { Unit = 81, Model = B }, Now = clock }))
		local amp, name = nil, nil
		run(1.6, function()
			local po = Fx.Pose(80)
			if po and (po.Name == "Strike" or po.Name == "Shoot") and amp == nil then
				amp, name = po.Amp, po.Name
			end
		end)
		return amp, name
	end
	local ampC, nameC = strikeAmp("Common")
	local ampS = strikeAmp("Secret")
	local ampR, nameR = strikeAmp("Secret", "Ranged")
	T.check(nameC == "Strike" and ampC == 1 and type(ampS) == "number" and ampS > 1.15 and ampS <= 1.25 + 1e-9 and nameR == "Shoot" and (ampR == nil or ampR == 1),
		"note (a): the melee Strike leap's Amp grows with the band (Common 1 -> Secret ~1.24); the ranged Shoot has none",
		fmt("Common %s, Secret %s, ranged %s %s", tostring(ampC), tostring(ampS), tostring(nameR), tostring(ampR)))

	-- 14b) Task 9 player decision: the melee leap lands on the target. The Strike carries Reach = the gap between the
	-- caster's front edge and the target's near edge minus LEAP_MARGIN (0.3), in the caster's pose units (/ PB_Scale);
	-- drawn as the battle draws it (root = pivot * PoseBody x PB_Scale), the caster's front edge lands LEAP_MARGIN short
	-- of the target's near edge at the landing (p 0.26): the /fx preview (12 studs centre to centre, scale 1) and battle
	-- range (4.5 studs, scale 1.3). Clamped to LEAP_MAX 12 world studs; the ranged Shoot carries no Reach
	local PetPoses = moduleAt(ROOTS.shared .. "/PetPoses")
	local function leapCase(name, gapCentre, scale)
		local caster = unitModel(holder, name .. "C", Vector3.new(30, 2, 0))
		local target = unitModel(holder, name .. "T", Vector3.new(30, 2, -gapCentre))
		if scale then
			caster:SetAttribute("PB_Scale", scale)
		end
		Fx.ClearAll()
		Fx.Play(ctx({ Attack = "Melee", Element = "Flame", Rarity = "Common", From = { Unit = 90, Model = caster }, To = { Unit = 91, Model = target }, Now = clock }))
		local reach = nil
		run(0.6, function()
			local po = Fx.Pose(90)
			if po and po.Name == "Strike" and reach == nil then
				reach = po.Reach
			end
		end)
		local landFront = nil
		if type(reach) == "number" then
			local body = PetPoses.Sample("Strike", 0.26, false, 1, reach).Body
			local s = scale or 1
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = body:GetComponents()
			local drawn = caster:GetPivot() * CFrame.new(x * s, y * s, z * s, r00, r01, r02, r10, r11, r12, r20, r21, r22)
			landFront = -(drawn.Position.Z) + 1 -- the caster's front edge (its body is 2 studs deep, facing -Z)
		end
		local near = gapCentre - 1 -- the target's near edge
		caster:Destroy()
		target:Destroy()
		run(2)
		return reach, landFront, near
	end
	local rP, fP, nP = leapCase("Prev", 12, nil)
	local rB, fB, nB = leapCase("Bat", 4.5, 1.3)
	local rF = leapCase("Far", 40, nil)
	local rF2 = leapCase("Far2", 40, 2)
	local rH, fH = leapCase("FarHalf", 40, 0.5)
	T.check(type(rP) == "number" and math.abs(rP - 9.7) < 1e-3 and fP and math.abs((nP - fP) - 0.3) < 1e-3,
		"leap (/fx preview, 12 studs): Reach 9.7 and the caster's front edge lands 0.3 short of the target's near edge",
		fmt("reach %s, front %s, near %.2f", tostring(rP), tostring(fP), nP))
	T.check(type(rB) == "number" and math.abs(rB - 2.2 / 1.3) < 1e-3 and fB and math.abs((nB - fB) - 0.3) < 1e-3,
		"leap (battle range 4.5 studs, PB_Scale 1.3): a short hop, landing 0.3 short of the target's near edge",
		fmt("reach %s, front %s, near %.2f", tostring(rB), tostring(fB), nB))
	T.check(type(rF) == "number" and math.abs(rF - 12) < 1e-6 and type(rF2) == "number" and math.abs(rF2 - 6) < 1e-6,
		"leap: clamped to LEAP_MAX 12 world studs (40 studs away: 12 at scale 1, 6 pose studs at scale 2)", fmt("%s / %s", tostring(rF), tostring(rF2)))
	-- review M5: clamped ONCE (world studs): at PB_Scale 0.5 the 12-stud leap is 24 pose studs and is drawn 12 studs on
	-- (a second, pose-unit clamp at 12 landed it 6 short)
	T.check(type(rH) == "number" and math.abs(rH - 24) < 1e-6 and fH and math.abs(fH - 13) < 1e-3,
		"leap: clamped once, in world studs (PB_Scale 0.5, 40 studs away: Reach 24 pose studs, the front edge lands 12 studs on)",
		fmt("reach %s, front %s", tostring(rH), tostring(fH)))
	Fx.ClearAll()
	Fx.Play(ctx({ Attack = "Ranged", Element = "Flame", Rarity = "Secret", From = { Unit = 92, Model = A }, To = { Unit = 93, Model = B }, Now = clock }))
	local shootReach, shootSeen = "none", false
	run(1.2, function()
		local po = Fx.Pose(92)
		if po and po.Name == "Shoot" and not shootSeen then
			shootSeen, shootReach = true, po.Reach
		end
	end)
	T.check(shootSeen and shootReach == nil, "leap: the ranged Shoot carries no Reach (ranged is unchanged)", tostring(shootReach))
	run(3)

	-- 15) fix round 3, player note (b): every element's ranged impact explodes at the target: the Boom pop (a solid ball
	-- of the element's colour growing at the hit point), the BoomRing shock on the ground and the BoomFlash light,
	-- at Common and Secret; the burst is the element's own texture. Melee draws none of them -----------------------
	local boomBad, boomSeen = {}, 0
	for _, e in ipairs({ "Flame", "Water", "Frost", "Nature", "Earth", "Storm", "Celestial", "Shadow" }) do
		for _, rarity in ipairs({ "Common", "Secret" }) do
			Fx.ClearAll()
			Fx.Play(ctx({ Attack = "Ranged", Element = e, Rarity = rarity, From = { Unit = 82, Model = A }, To = { Unit = 83, Model = B }, Now = clock }))
			local ef = Fx._Live()[#Fx._Live()]
			local popSeen, popNear, ringSeen, flashSeen, grew = false, false, false, false, false
			local s0 = nil
			if ef then
				local t0 = ef.Start + ef.Times.Impact
				run(math.max(0, t0 - clock) + 0.3, function()
					for _, it in ipairs(ef.Items or {}) do
						local id = it.Layer and it.Layer.Id
						if id == "Boom" and it.Kind == "Solid" and it.Kit and it.Kit.Root.Transparency < 1 then
							popSeen = true
							popNear = popNear or (it.Kit.Root.Position - ef.Hit).Magnitude < 1.5
							local sz = it.Kit.Root.Size.Magnitude
							if s0 == nil then
								s0 = sz
							elseif sz > s0 * 1.3 then
								grew = true
							end
						elseif id == "BoomRing" and it.Kind == "Solid" and it.Kit and it.Kit.Root.Transparency < 1 then
							ringSeen = true
						elseif id == "BoomFlash" and it.Kind == "Light" then
							flashSeen = true
						end
					end
				end)
			end
			boomSeen = boomSeen + 1
			if e == "Water" then -- (Task 9: Water's shot explodes as its geyser splash, no pop ball)
				popSeen, popNear, grew = not popSeen, true, true
			end
			if not (popSeen and popNear and grew and ringSeen and flashSeen) then
				boomBad[#boomBad + 1] = fmt("%s %s: pop %s near %s grew %s ring %s flash %s", e, rarity, tostring(popSeen), tostring(popNear), tostring(grew), tostring(ringSeen), tostring(flashSeen))
			end
		end
	end
	T.check(#boomBad == 0 and boomSeen >= 16, fmt("note (b): every element's ranged impact explodes at the target (Boom pop growing at the hit, BoomRing shock, BoomFlash light; %d plays)", boomSeen),
		table.concat(boomBad, "; "))
	Fx.ClearAll()
	Fx.Play(ctx({ Attack = "Melee", Element = "Flame", Rarity = "Secret", From = { Unit = 84, Model = A }, To = { Unit = 85, Model = B }, Now = clock }))
	local mel = Fx._Live()[#Fx._Live()]
	local melBoom = false
	for _, it in ipairs(mel and mel.Items or {}) do
		local id = it.Layer and it.Layer.Id
		melBoom = melBoom or id == "Boom" or id == "BoomRing" or id == "BoomFlash"
	end
	T.check(mel ~= nil and not melBoom, "note (b): the melee hit keeps its own impact (no ranged explosion layers)")
	run(3)

	-- clean up
	Fx.ClearAll()
	Fx.Hooks.Punch = nil
	Fx._Deps({ MeshLibrary = false, TextureIds = false })
	Fx.SetQuality(nil)
	T.check(Fx.Stats().Live == 0 and Fx.Pose(21) == nil, "ClearAll: nothing live, no poses")
	holder:Destroy()
end)

----------------------------------------------------------------------------------------------------------------------
-- client_p7vfx_battle: BattleController plays AttackFx (plan Task 7)
----------------------------------------------------------------------------------------------------------------------
local KC = _G.KC
local LocalPlayer = game:GetService("Players").LocalPlayer

-- combat catalog pets with different specials (skipping `skip`), like smoke_p5_battleclient's H.team
local function catalogTeam(count, skip, level)
	local PC = moduleAt(ROOTS.shared .. "/PetCatalog")
	local out, kinds = {}, {}
	skip = skip or 0
	for _, def in ipairs(PC and PC.Pets or {}) do
		local sp = type(def.Special) == "table" and def.Special.Kind or nil
		if sp and def.Role == "Combat" and not kinds[sp] and def.Rarity ~= "Secret" and not def.EventOnly then
			if skip > 0 then
				skip = skip - 1
			else
				kinds[sp] = true
				out[#out + 1] = { Key = def.Id, PetId = def.Id, Level = level or 20, Tier = "Normal", Slot = #out + 1 }
				if #out >= count then
					break
				end
			end
		end
	end
	return out
end

-- a recorded Boss Raid (my team + player 77's, both on Auto so specials / elements / buffs come): the Start payload the
-- way BattleService sends it, then per 0.1 s server step its events and its wire snapshot (SnapshotDelta)
local function recordRaid(seconds)
	local Sim = moduleAt(ROOTS.shared .. "/BattleSim")
	if not Sim then
		return nil, "shared/BattleSim missing"
	end
	local me = LocalPlayer.UserId
	local sim, why = Sim.new({ Mode = "Raid", Seed = 11, Id = "p7vfx_raid", Boss = "storm_titan", Zone = { X = 44, Z = 44 }, TimeLimit = 120,
		Teams = { { Owner = me, Side = 1, Pets = catalogTeam(3, 0, 20), Auto = true }, { Owner = 77, Side = 1, Pets = catalogTeam(3, 3, 20), Auto = true } } })
	if not sim then
		return nil, why
	end
	for _, u in ipairs(sim.units or {}) do
		if u.kind ~= "Boss" then
			u.meter = 100 -- the specials come at once
		end
	end
	local start = sim:Describe()
	start.Zone = { CFrame = CFrame.new(0, 200, 0), Size = Vector3.new(start.Zone.X, 30, start.Zone.Z), X = start.Zone.X, Z = start.Zone.Z }
	start.Names = { [tostring(me)] = LocalPlayer.Name, ["77"] = "Buddy" }
	start.Side, start.Spectator, start.T = 1, false, sim:Time()
	local team = sim:TeamOf(me)
	if team then
		local buff = {}
		for slot, secs in pairs(team.Cooldowns.Buff or {}) do
			buff[tostring(slot)] = secs
		end
		start.Team = { Fighter = team.Fighter, Bench = team.Bench, Lives = team.Lives, Speed = team.Speed,
			Cooldowns = { Element = team.Cooldowns.Element, Dash = team.Cooldowns.Dash, Swap = team.Cooldowns.Swap, Buff = buff } }
	end
	local steps, last = {}, {}
	for _ = 1, math.floor(seconds / 0.1 + 0.5) do
		local evs = sim:Step(0.1)
		steps[#steps + 1] = { Events = evs, Snap = sim:SnapshotDelta(last) }
		if sim:IsFinished() then
			break
		end
	end
	return { Start = start, Steps = steps, Team77 = sim:TeamOf(77), Mine = team, Sim = sim, Last = last }
end

local function copyOf(t)
	local c = {}
	for k, v in pairs(t) do
		c[k] = v
	end
	return c
end

S.client_p7vfx_battle = guarded("client_p7vfx_battle", function()
	local BC = moduleAt(ROOTS.client .. "/Controllers/BattleController")
	local AF = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
	local Cat = moduleAt(ROOTS.shared .. "/AttackFxCatalog")
	local PB = moduleAt(ROOTS.shared .. "/PetBuilder")
	if not T.check(BC ~= nil and AF ~= nil and Cat ~= nil and PB ~= nil and KC ~= nil, "BattleController, AttackFx, AttackFxCatalog, PetBuilder load") then
		return
	end
	local out0, err0 = #Mock.Output, #Mock.Errors
	local rec, why = recordRaid(14)
	if not T.check(rec ~= nil and #rec.Steps > 50, "a recorded Boss Raid (14 s of events + snapshots)", tostring(why)) then
		return
	end
	AF.ClearAll()
	AF.SetQuality("High")
	-- the spy: every AttackFx.Play call (force = false: Play refuses, the caller must draw its cube Fx.*)
	local calls, force = {}, nil
	local realPlay, realAnimate = AF.Play, PB.Animate
	AF.Play = function(ctx)
		local c = { Attack = ctx.Attack, Kind = ctx.Kind, Shape = ctx.Shape, Element = ctx.Element, Rarity = ctx.Rarity, Stage = ctx.Stage,
			From = type(ctx.From) == "table" and ctx.From.Unit or nil, Mine = ctx.Mine, Miss = ctx.Miss == true, DueAt = ctx.DueAt, At = os.clock() }
		if force == false then
			c.Result = false
		else
			c.Result = realPlay(ctx)
			c.Late = ctx.ImpactLate
		end
		calls[#calls + 1] = c
		return c.Result
	end
	-- the poses PetBuilder.Animate is given, per unit model
	local posesSeen = {}
	PB.Animate = function(model, t, opts)
		if type(opts) == "table" and type(opts.Pose) == "table" and typeof(model) == "Instance" then
			posesSeen[opts.Pose.Name] = (posesSeen[opts.Pose.Name] or 0) + 1
		end
		return realAnimate(model, t, opts)
	end
	local function frames(seconds)
		for _ = 1, math.max(1, math.floor(seconds * 30 + 0.5)) do
			Mock.Step(1 / 30)
		end
	end
	local peak = { FxParts = 0, Numbers = 0, Flashes = 0, Live = 0, Stepped = 0 }
	local function track()
		local s = BC.GetStats()
		for _, k in ipairs({ "FxParts", "Numbers", "Flashes" }) do
			peak[k] = math.max(peak[k], s[k] or 0)
		end
		local a = s.AttackFx or {}
		peak.Live = math.max(peak.Live, a.Live or 0)
		peak.Stepped = math.max(peak.Stepped, a.Stepped or 0)
	end
	local function poolsAtKeep(label)
		local s = AF.Stats()
		local folder = AF.Folder()
		local hidden, what = allHidden(folder)
		T.check(s.Live == 0 and s.Stepped == 0 and s.Emitters == 0 and s.Beams == 0 and s.Trails == 0 and s.Lights == 0 and s.Cores == 0,
			label .. ": AttackFx.Stats().Live == 0 (nothing live, no kit held)", fmt("Live %d Stepped %d Emitters %d", s.Live, s.Stepped, s.Emitters))
		T.check(s.Pooled <= AF.POOL_KEEP_TOTAL and s.PoolInstances == #folder:GetDescendants() and hidden,
			label .. ": the pools are at their keep size (every kit pooled and hidden, nothing else in the folder)",
			fmt("pooled %d / keep %d, instances %d vs folder %d, %s", s.Pooled, AF.POOL_KEEP_TOTAL, s.PoolInstances, #folder:GetDescendants(), tostring(what)))
	end
	-- the battle's unit infos (Start + Spawn / Wave units) and the client's view of a unit now
	local infos = {}
	local function learn(list)
		for _, info in ipairs(type(list) == "table" and list or {}) do
			if type(info) == "table" and tonumber(info.id) then
				infos[tonumber(info.id)] = info
			end
		end
	end
	local function drawable(g)
		return g ~= nil and not g.Parked and not g.Hidden and not (g.Benched and not g.Mine)
	end
	-- what one event must make BattleController play: nil = nothing, else { Attack, Unit, Kind?, Shape?, Miss?, El? }
	local function expected(ev)
		local t = ev.type
		local function unit(id)
			return BC.GetUnit(tonumber(id) or -1)
		end
		if t == "Hit" then
			if ev.special or ev.element or ev.zone or ev.burn then
				return nil
			end
			local a, v = unit(ev.from), unit(ev.to)
			if not v then
				return nil
			end
			if ev.tele or (a and a.Kind == "Boss") then
				if not ev.miss and v.Kind ~= "Boss" and v.Mine and drawable(v) then
					return { Attack = "Hurt", Unit = v.Id, El = a and Cat.Unit(infos[a.Id] or {}).Element }
				end
				return nil
			end
			if a and drawable(a) then
				return { Attack = (infos[a.Id] or {}).ranged and "Ranged" or "Melee", Unit = a.Id, Miss = ev.miss == true }
			end
		elseif t == "Special" or t == "Element" then
			local u = unit(ev.unit)
			if u and u.Kind ~= "Boss" and drawable(u) then
				return { Attack = t, Unit = u.Id, Kind = (t == "Special") and ev.kind or nil, Shape = (t == "Element") and ev.shape or nil }
			end
		elseif t == "KO" then
			local u = unit(ev.unit)
			if u and u.Kind ~= "Boss" and drawable(u) and u.Model ~= nil then
				return { Attack = "Ko", Unit = u.Id }
			end
		elseif t == "Buff" then
			-- the support special the buff is like, on the fighter (from the helper when it is drawn)
			local h, f = unit(ev.unit), unit(ev.target)
			if h and f and f.Kind ~= "Boss" and drawable(f) and f.Model ~= nil then
				return { Attack = "Special", Unit = (drawable(h) and h.Model ~= nil) and h.Id or nil, LookId = h.Id }
			end
		elseif t == "Swap" then
			local inc = unit(ev["in"])
			if inc and inc.Kind ~= "Boss" and drawable(inc) and inc.Model ~= nil then
				return { Attack = "Victory", Unit = inc.Id }
			end
		end
		return nil
	end

	-- empty wire snapshots (the picture carried forward) keep the render clock moving after a recording ends, so the
	-- crafted events below play
	local live = { id = nil, T = 0 }
	local function pulse(seconds)
		for _ = 1, math.max(1, math.floor(seconds / 0.1 + 0.5)) do
			live.T = live.T + 0.1
			KC.toClient("BattleState", "Snapshot", { BattleId = live.id, T = live.T, U = {} }, live.id)
			frames(0.1)
		end
	end
	local ok, err = pcall(function()
		-- 1) the recorded raid, one event at a time: each Hit / Special / Element / KO plays AttackFx exactly once (on
		--    arrival, impact due when the event plays), with the unit's element and rarity
		local id = "p7vfx_raid_1"
		LocalPlayer:SetAttribute("InBattle", id)
		BC.ResetStats()
		local start = copyOf(rec.Start)
		start.BattleId = id
		learn(start.Units)
		KC.toClient("BattleState", "Start", start, id)
		frames(0.1)
		local seen, bad, wrongLook, leads = {}, {}, {}, { n = 0, positive = 0, max = 0 }
		for _, st in ipairs(rec.Steps) do
			for _, ev in ipairs(st.Events) do
				if ev.type == "Spawn" or ev.type == "Wave" then
					learn(ev.units)
				end
				local want = expected(ev)
				local n0 = #calls
				KC.toClient("BattleState", "Events", { ev }, id)
				local got = {}
				for i = n0 + 1, #calls do
					got[#got + 1] = calls[i]
				end
				local label = ev.type .. (ev.kind and (" " .. tostring(ev.kind)) or "") .. " #" .. tostring(ev.from or ev.unit)
				if want == nil then
					if #got > 0 then
						bad[#bad + 1] = label .. ": " .. #got .. " plays, none expected (" .. tostring(got[1].Attack) .. ")"
					end
				elseif #got ~= 1 then
					bad[#bad + 1] = label .. ": " .. #got .. " plays, 1 expected (" .. want.Attack .. ")"
				else
					local c = got[1]
					local lookId = want.LookId or want.Unit
					local look = Cat.Unit(infos[lookId] or {})
					local el = (want.Attack == "Element" and ev.element) or (want.Attack == "Hurt" and (want.El or look.Element)) or look.Element
					if c.Attack ~= want.Attack or c.From ~= want.Unit or (want.Kind and c.Kind ~= want.Kind) or (want.Shape and c.Shape ~= want.Shape)
						or (want.Miss ~= nil and c.Miss ~= want.Miss) then
						bad[#bad + 1] = fmt("%s: played %s from %s (kind %s shape %s miss %s)", label, tostring(c.Attack), tostring(c.From), tostring(c.Kind), tostring(c.Shape), tostring(c.Miss))
					elseif c.Element ~= el or c.Rarity ~= look.Rarity or c.Stage ~= look.Stage or c.Mine ~= (BC.GetUnit(lookId) or {}).Mine then
						wrongLook[#wrongLook + 1] = fmt("%s: %s %s stage %s mine %s (want %s %s %s)", label, tostring(c.Element), tostring(c.Rarity), tostring(c.Stage), tostring(c.Mine), tostring(el), tostring(look.Rarity), tostring(look.Stage))
					end
					seen[want.Attack] = (seen[want.Attack] or 0) + 1
					if type(c.DueAt) == "number" then
						local lead = c.DueAt - c.At
						leads.n = leads.n + 1
						leads.max = math.max(leads.max, lead)
						if lead > 0.05 then
							leads.positive = leads.positive + 1
						end
					end
				end
			end
			local snap = copyOf(st.Snap)
			snap.BattleId = id
			KC.toClient("BattleState", "Snapshot", snap, id)
			live.id, live.T = id, snap.T
			frames(0.1)
			track()
		end
		local list = {}
		for k, v in pairs(seen) do
			list[#list + 1] = k .. " " .. v
		end
		table.sort(list)
		T.info("client_p7vfx_battle: AttackFx plays in the recorded raid", table.concat(list, ", "))
		T.check(#bad == 0, "raid replay: every Hit / Special / Element / KO event plays AttackFx exactly once (boss hits: my pet's Hurt; zone / burn / special / element damage: none)", table.concat(bad, "; "))
		T.check(#wrongLook == 0, "raid replay: ... with the unit's element, rarity and stage (AttackFxCatalog.Unit) and Mine = my own pet", table.concat(wrongLook, "; "))
		T.check(((seen.Melee or 0) + (seen.Ranged or 0)) >= 5 and (seen.Special or 0) >= 1 and (seen.Element or 0) >= 1,
			"raid replay: basic attacks, specials and element attacks were all played", table.concat(list, ", "))
		T.check(leads.n > 0 and leads.positive > leads.n / 2 and leads.max <= 0.45,
			"raid replay: played on arrival with the impact due when the event plays (the render delay is the charge lead, <= 0.45 s)",
			fmt("%d of %d with lead > 0.05 s, max %.2f s", leads.positive, leads.n, leads.max))
		T.check(peak.FxParts <= 260 and peak.Numbers <= 26 and peak.Flashes <= 8, "raid replay: FxParts <= 260, Numbers <= 26, Flashes <= 8",
			fmt("%d parts, %d numbers, %d flashes", peak.FxParts, peak.Numbers, peak.Flashes))
		T.check(peak.Live >= 1 and peak.Live <= AF.MAX_LIVE and peak.Stepped <= AF.MAX_STEPPED, "raid replay: GetStats().AttackFx reports the live effects within MAX_LIVE / MAX_STEPPED",
			fmt("peak Live %d, Stepped %d", peak.Live, peak.Stepped))
		T.check((posesSeen.Strike or 0) > 0 and (posesSeen.Hurt or 0) > 0, "raid replay: the pets strike and flinch (PetBuilder.Animate gets opts.Pose Strike / Hurt)",
			fmt("Strike %d, Hurt %d, Cast %d, Windup %d", posesSeen.Strike or 0, posesSeen.Hurt or 0, posesSeen.Cast or 0, posesSeen.Windup or 0))

		-- 1b) Ruling 12: between attacks the pets breathe and glance (PetPoses IdleBattle), out of step per unit; an attack
		--     pose replaces it and the idle comes back after the attack
		pulse(2.5)
		local idle = {}
		for uid, info in pairs(infos) do
			local g = BC.GetUnit(uid)
			if info.kind ~= "Boss" and drawable(g) and g.Model and g.Pose == "IdleBattle" and type(g.PoseP) == "number" then
				idle[#idle + 1] = g
			end
		end
		table.sort(idle, function(p, q)
			return p.Id < q.Id
		end)
		T.check(#idle >= 2 and math.abs(idle[1].PoseP - idle[2].PoseP) > 0.05, "idle: battle units with no attack pose show IdleBattle, each at its own phase",
			fmt("%d idle units%s", #idle, (#idle >= 2) and fmt(", p %.2f vs %.2f", idle[1].PoseP, idle[2].PoseP) or ""))
		T.check((posesSeen.IdleBattle or 0) > 0, "idle: PetBuilder.Animate gets opts.Pose IdleBattle", tostring(posesSeen.IdleBattle))
		local bossId = nil
		for uid, info in pairs(infos) do
			if info.kind == "Boss" then
				bossId = uid
			end
		end
		if idle[1] and bossId then
			local who = idle[1].Id
			local n1 = #calls
			KC.toClient("BattleState", "Events", { { type = "Hit", from = who, to = bossId, dmg = 3 } }, id)
			local attackPose, crossfade = nil, false
			for _ = 1, 12 do
				pulse(0.1)
				local g = BC.GetUnit(who)
				if g and g.Pose and g.Pose ~= "IdleBattle" then
					attackPose = attackPose or g.Pose
				end
			end
			T.check(calls[n1 + 1] and calls[n1 + 1].Result == true and (attackPose == "Strike" or attackPose == "Windup" or attackPose == "Shoot"),
				"idle: an attack pose replaces the idle (" .. tostring(attackPose) .. ")")
			pulse(2)
			local back = BC.GetUnit(who)
			T.check(back and back.Pose == "IdleBattle", "idle: ... and IdleBattle returns after the attack", back and tostring(back.Pose) or "gone")
		end

		-- 2) handler by handler: with AttackFx the cube effects stay off, when Play returns false the old Fx.* still runs
		pulse(3) -- (everything of the replay ends)
		local team = rec.Mine
		local fighter = team and team.Fighter
		local boss = nil
		for uid, info in pairs(infos) do
			if info.kind == "Boss" then
				boss = uid
			end
		end
		local helper = team and team.Bench and team.Bench[1]
		local ranged = nil
		for uid, info in pairs(infos) do
			if info.ranged and info.kind ~= "Boss" and drawable(BC.GetUnit(uid)) and BC.GetUnit(uid).Model then
				ranged = uid
			end
		end
		if not T.check(fighter and boss and BC.GetUnit(fighter) and BC.GetUnit(boss), "raid replay: my fighter and the boss are on the floor") then
			return
		end
		local f = BC.GetUnit(fighter)
		local bo = BC.GetUnit(boss)
		local fInfo = infos[fighter] or {}
		local function crafted()
			local list2 = {
				{ "Special Blast", { type = "Special", unit = fighter, kind = "Blast", name = "Test Blast", x = f.X, z = f.Z, tx = bo.X, tz = bo.Z, target = boss, targets = { boss } } },
				{ "Element", { type = "Element", unit = fighter, element = fInfo.element, name = "Test Element", x = f.X, z = f.Z, angle = 0, tx = bo.X, tz = bo.Z, shape = "Cone", targets = { boss } } },
			}
			if ranged then
				list2[#list2 + 1] = { "ranged Hit", { type = "Hit", from = ranged, to = boss, dmg = 7 } }
			end
			if helper then
				list2[#list2 + 1] = { "Buff", { type = "Buff", owner = LocalPlayer.UserId, unit = helper, kind = (infos[helper] and infos[helper].buff and infos[helper].buff.Kind) or "Heal", name = "Heal", target = fighter } }
			end
			return list2
		end
		local fallbackBad, liveBad = {}, {}
		for _, mode in ipairs({ "fx", "fallback" }) do
			if mode == "fallback" then
				force = false
			else
				force = nil
			end
			for _, item in ipairs(crafted()) do
				pulse(1.8)
				local p0 = BC.GetStats().FxParts
				local n0 = #calls
				KC.toClient("BattleState", "Events", { item[2] }, id)
				pulse(0.3)
				local dp = BC.GetStats().FxParts - p0
				local played = calls[n0 + 1] and calls[n0 + 1].Result
				if #calls ~= n0 + 1 then
					liveBad[#liveBad + 1] = mode .. " " .. item[1] .. ": " .. (#calls - n0) .. " plays"
				elseif mode == "fx" and not (played and dp <= 0) then
					liveBad[#liveBad + 1] = fmt("%s: played %s, %d new cube parts", item[1], tostring(played), dp)
				elseif mode == "fallback" and not (dp > 0) then
					fallbackBad[#fallbackBad + 1] = fmt("%s: %d new cube parts (played %s)", item[1], dp, tostring(played))
				end
			end
		end
		force = nil
		T.check(#liveBad == 0, "handlers: Special / Element / ranged Hit / Buff play AttackFx once and draw no cube Fx while it plays", table.concat(liveBad, "; "))
		T.check(#fallbackBad == 0, "handlers: when AttackFx.Play returns false the old cube Fx.* call still runs", table.concat(fallbackBad, "; "))
		-- DODGED! on a miss (both ways)
		local function dodged()
			local fx = workspace:FindFirstChild("ClientBattle") and workspace.ClientBattle:FindFirstChild("Fx")
			for _, g in ipairs(fx and fx:GetDescendants() or {}) do
				if g:IsA("TextLabel") and g.Text == "DODGED!" and g:FindFirstAncestorOfClass("BillboardGui") and g:FindFirstAncestorOfClass("BillboardGui").Enabled then
					return true
				end
			end
			return false
		end
		pulse(1.5)
		KC.toClient("BattleState", "Events", { { type = "Hit", from = ranged or fighter, to = boss, dmg = 0, miss = true } }, id)
		pulse(0.3)
		T.check(dodged(), "handlers: a missed hit still shows DODGED! (with AttackFx playing the miss)")
		-- the KO: AttackFx's Ko poof replaces the cube poof
		local koUnit = helper or fighter
		pulse(1.8)
		local p0 = BC.GetStats().FxParts
		local n0 = #calls
		KC.toClient("BattleState", "Events", { { type = "KO", unit = koUnit } }, id)
		pulse(0.3)
		T.check(#calls == n0 + 1 and calls[n0 + 1].Attack == "Ko" and calls[n0 + 1].Result == true and BC.GetStats().FxParts - p0 <= 0,
			"handlers: a KO plays AttackFx Ko (no cube poof)", fmt("%d plays, %d new parts", #calls - n0, BC.GetStats().FxParts - p0))

		-- 2b) the KO on the render clock (fix round 2): AttackFx's Ko plays on arrival, the snapshot draws the pet down
		--     when the event plays: the Ko pose holds, the effect plays its beats, nothing cancels it, the pet lies until
		--     KO_PARK_FX (1.6 s, not the cube path's 0.3 s); with Play false the cube poof still shows and it parks at 0.3 s
		local Sim = moduleAt(ROOTS.shared .. "/BattleSim")
		local downState = (Sim and Sim.States and Sim.States.Down) or 5
		local cancels = {}
		local realCancel = AF.Cancel
		AF.Cancel = function(unitId)
			cancels[#cancels + 1] = unitId
			return realCancel(unitId)
		end
		-- the sim draws `uid` down: its next wire snapshot (the client decoded the same baseline: rec.Last)
		local function koOnRenderClock(uid)
			for _, su in ipairs(rec.Sim.units or {}) do
				if su.id == uid then
					su.hp = 0
					su.state = downState
				end
			end
			local delta = rec.Sim:SnapshotDelta(rec.Last)
			live.T = live.T + 0.1
			delta.T, delta.BattleId = live.T, id
			local n0 = #calls
			KC.toClient("BattleState", "Events", { { type = "KO", unit = uid, by = boss } }, id)
			KC.toClient("BattleState", "Snapshot", delta, id)
			return calls[n0 + 1], #calls - n0
		end
		local function watchPark(uid, due, seconds, probe)
			local parkedAt = nil
			for i = 1, math.floor(seconds * 30) do
				if i % 3 == 1 then
					live.T = live.T + 0.1
					KC.toClient("BattleState", "Snapshot", { BattleId = live.id, T = live.T, U = {} }, live.id)
				end
				Mock.Step(1 / 30)
				local g = BC.GetUnit(uid)
				if probe then
					probe(os.clock())
				end
				if not parkedAt and g and g.Parked then
					parkedAt = os.clock()
				end
			end
			return parkedAt and due and (parkedAt - due) or nil
		end
		local t77b = rec.Team77
		local kid = t77b and t77b.Fighter
		if T.check(kid ~= nil and drawable(BC.GetUnit(kid)) and BC.GetUnit(kid).Model ~= nil, "KO (render clock): player 77's fighter is on the floor") then
			pulse(2)
			local c0 = #cancels
			local ko, n = koOnRenderClock(kid)
			local due = ko and ko.DueAt
			local poseHeld, effectLive, effectBeats = false, false, nil
			local parkedAfter = watchPark(kid, due, 2.6, function(now)
				if due and now >= due + 0.25 and now < due + 0.3 then
					local p = AF.Pose(kid)
					local g = BC.GetUnit(kid)
					poseHeld = p ~= nil and p.Name == "Ko" and g ~= nil and g.Pose == "Ko"
					for _, e in ipairs(AF._Live()) do
						if e.Unit == kid and e.Recipe.Attack == "Ko" then
							effectLive = true
							effectBeats = e.End - e.Start
						end
					end
				end
			end)
			local cancelled = false
			for i = c0 + 1, #cancels do
				if cancels[i] == kid then
					cancelled = true
				end
			end
			T.check(n == 1 and ko and ko.Attack == "Ko" and ko.Result == true and type(due) == "number" and due > ko.At,
				"KO (render clock): the KO plays AttackFx Ko once on arrival, due when the event plays", ko and fmt("lead %.2f s", (due or 0) - ko.At) or "no play")
			T.check(poseHeld and effectLive, "KO (render clock): after the due time the Ko pose holds and the Ko effect still plays its beats",
				fmt("pose %s, effect %s (%.2f s long)", tostring(poseHeld), tostring(effectLive), effectBeats or 0))
			T.check(not cancelled, "KO (render clock): nothing cancels the Ko (no AttackFx.Cancel on the pet before it is parked)")
			T.check(parkedAfter ~= nil and parkedAfter >= 1.3 and parkedAfter <= 2.2, "KO (render clock): the pet lies and is parked after KO_PARK_FX (~1.6 s, not 0.3 s)",
				parkedAfter and fmt("%.2f s after the due time", parkedAfter) or "never parked")
		end
		-- the cube path: Play false -> the KO handler's cube poof, parked after KO_PARK 0.3 s
		local kid2 = helper
		if kid2 and drawable(BC.GetUnit(kid2)) and BC.GetUnit(kid2).Model then
			pulse(1.5)
			force = false
			local p0 = BC.GetStats().FxParts
			local ko2 = koOnRenderClock(kid2)
			local due2 = ko2 and ko2.DueAt
			local poofParts = 0
			local parkedAfter2 = watchPark(kid2, due2, 1.2, function()
				poofParts = math.max(poofParts, BC.GetStats().FxParts - p0)
			end)
			force = nil
			T.check(ko2 and ko2.Result == false and poofParts > 0, "KO (fallback): with Play false the cube poof still shows", fmt("%d cube parts", poofParts))
			T.check(parkedAfter2 ~= nil and parkedAfter2 < 0.9, "KO (fallback): ... and the pet is parked after KO_PARK (0.3 s)", parkedAfter2 and fmt("%.2f s", parkedAfter2) or "never")
		else
			T.fail("KO (fallback): my helper is on the floor")
		end
		AF.Cancel = realCancel

		-- 2c) player note 1: a ranged pet's shot keeps its flight (MinTravel) even with the render delay's short lead:
		--     its Hit (the damage number) plays when the shot LANDS (Net.Queue holds it by ctx.ImpactLate), not before
		local shooter = nil
		for uid, info in pairs(infos) do
			local g = BC.GetUnit(uid)
			if info.ranged == true and info.kind ~= "Boss" and drawable(g) and g.Model ~= nil and (not shooter or uid < shooter) then
				shooter = uid
			end
		end
		if T.check(shooter ~= nil and bossId ~= nil, "note 1 (battle): a ranged pet and the boss are on the floor") then
			pulse(1.5)
			local n0 = #calls
			KC.toClient("BattleState", "Events", { { type = "Hit", from = shooter, to = bossId, dmg = 7 } }, id)
			local c = calls[n0 + 1]
			local impactAt = nil
			for _, e in ipairs(AF._Live()) do
				if e.Unit == shooter and e.Recipe.Attack == "Ranged" then
					impactAt = e.Start + e.Times.Impact
				end
			end
			local numbers = BC.GetStats().Numbers
			local numberAt = nil
			for i = 1, 30 do
				if i % 3 == 1 then
					live.T = live.T + 0.1
					KC.toClient("BattleState", "Snapshot", { BattleId = live.id, T = live.T, U = {} }, live.id)
				end
				Mock.Step(1 / 30)
				local now = BC.GetStats().Numbers
				if not numberAt and now > numbers then
					numberAt = os.clock()
				end
				numbers = math.min(numbers, now)
			end
			T.check(c ~= nil and c.Attack == "Ranged" and c.Result == true and type(c.Late) == "number" and c.Late > 0.05 and impactAt ~= nil,
				"note 1 (battle): the shot keeps its flight with the short lead (ctx.ImpactLate > 0)", c and fmt("late %s", tostring(c.Late)) or "no play")
			T.check(numberAt ~= nil and impactAt ~= nil and numberAt >= impactAt - 1 / 30 - 1e-3 and numberAt <= impactAt + 0.2,
				"note 1 (battle): the Hit's damage number shows when the shot lands, not before (Net.Queue holds it)",
				fmt("number %.3f s after the impact", (numberAt or 0) - (impactAt or 0)))
		end

		-- 3) Review Focus 4 + Ruling 11: the killing blow and the End arrive together (like the sim's last step): the blow
		--    lands visibly, no new effect starts, everything is gone (pools at keep size) within FX_END_GRACE 1.0 s
		pulse(2.5)
		local n3 = #calls
		KC.toClient("BattleState", "Events", {
			{ type = "Special", unit = fighter, kind = "Blast", name = "Test Blast", x = f.X, z = f.Z, tx = bo.X, tz = bo.Z, target = boss, targets = { boss } },
			{ type = "Hit", from = fighter, to = boss, dmg = 5 },
			-- (a helper swapped in at the last moment: its Victory entrance outlasts the 1.0 s grace)
			{ type = "Swap", owner = LocalPlayer.UserId, out = fighter, ["in"] = (team.Bench and team.Bench[2]) or helper },
			{ type = "End", reason = "BossDown", winnerSide = 1 },
		}, id)
		local blow = calls[n3 + 2]
		local due = blow and blow.DueAt
		local naturalEnd = 0
		for _, e in ipairs(AF._Live()) do
			naturalEnd = math.max(naturalEnd, e.End)
		end
		T.check(blow and blow.Attack == "Melee" or blow and blow.Attack == "Ranged", "Ruling 11: the killing blow plays AttackFx", blow and tostring(blow.Attack) or "no play")
		T.check(type(due) == "number" and naturalEnd > due + 1.0, "Ruling 11: (precondition) the live effects would run past the 1.0 s grace on their own",
			fmt("ends %.2f s after the impact", naturalEnd - (due or 0)))
		local liveAtImpact, zeroAt, lateCalls = nil, nil, nil
		local afterEnd = false
		for i = 1, 60 do
			if i % 3 == 1 then
				live.T = live.T + 0.1
				KC.toClient("BattleState", "Snapshot", { BattleId = live.id, T = live.T, U = {} }, live.id)
			end
			Mock.Step(1 / 30)
			local s = AF.Stats()
			local now = os.clock()
			if due and liveAtImpact == nil and now >= due + 0.05 then
				liveAtImpact = s.Live + s.Stepped
			end
			if due and not afterEnd and now >= due + 0.1 then
				-- a hit that arrives during the grace starts no new AttackFx effect (its cube fallback draws)
				afterEnd = true
				local n4 = #calls
				KC.toClient("BattleState", "Events", { { type = "Hit", from = fighter, to = boss, dmg = 2 } }, id)
				lateCalls = #calls - n4
			end
			if zeroAt == nil and s.Live + s.Stepped == 0 then
				zeroAt = now
			end
		end
		T.check(liveAtImpact ~= nil and liveAtImpact >= 1, "Ruling 11: the End does not cut the killing blow (its effect is still live after the impact)", tostring(liveAtImpact))
		T.check(lateCalls == 0, "Ruling 11: after the End no new AttackFx effect starts", tostring(lateCalls))
		T.check(zeroAt ~= nil and due ~= nil and zeroAt >= due and zeroAt <= due + 1.0 + 0.07,
			"Review Focus 4 (End): AttackFx.Stats().Live == 0 within 1.0 s of the End (not before the impact)",
			(zeroAt and due) and fmt("%.2f s after the impact", zeroAt - due) or "never")
		poolsAtKeep("Review Focus 4 (End event mid-effect, after the grace)")
		T.check(AF.Pose(fighter) == nil and AF.Pose(boss) == nil, "Review Focus 4 (End): no pose is left")
		KC.toClient("BattleState", "End", { BattleId = id, Mode = "Raid", Outcome = "Left", Won = false, Spectator = false, Reason = "Left" }, id)
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.advance(15)
		T.check(BC.GetBattle() == nil, "the first battle is freed after its end")
		poolsAtKeep("after the battle is freed")

		-- 4) a fallback replay (Play always false): the cube effects draw the whole fight
		id = "p7vfx_raid_2"
		LocalPlayer:SetAttribute("InBattle", id)
		start = copyOf(rec.Start)
		start.BattleId = id
		force = false
		KC.toClient("BattleState", "Start", start, id)
		frames(0.1)
		local cubePeak = 0
		for i = 1, math.min(60, #rec.Steps) do
			local st = rec.Steps[i]
			if #st.Events > 0 then
				KC.toClient("BattleState", "Events", st.Events, id)
			end
			local snap = copyOf(st.Snap)
			snap.BattleId = id
			KC.toClient("BattleState", "Snapshot", snap, id)
			live.id, live.T = id, snap.T
			frames(0.1)
			cubePeak = math.max(cubePeak, BC.GetStats().FxParts)
			track()
		end
		T.check(cubePeak > 0 and AF.Stats().Live == 0, "fallback replay: with Play false the fight is drawn by the cube Fx (and nothing of AttackFx)", fmt("peak %d cube parts", cubePeak))
		force = nil

		-- 5) Review Focus 4: player 77 leaves mid-effect -> its effects end at once, the pools at keep size
		pulse(3)
		local t77 = rec.Team77
		local f77 = t77 and t77.Fighter
		local g77 = f77 and BC.GetUnit(f77)
		if T.check(g77 ~= nil and AF.Stats().Live == 0, "Review Focus 4 (Leave): player 77's fighter is on the floor, nothing live") then
			KC.toClient("BattleState", "Events", {
				{ type = "Special", unit = f77, kind = "Blast", name = "Test Blast", x = g77.X, z = g77.Z, tx = bo.X, tz = bo.Z, target = boss, targets = { boss } },
				{ type = "Hit", from = f77, to = boss, dmg = 5 },
			}, id)
			pulse(0.2)
			local mine77 = true
			for _, e in ipairs(AF._Live()) do
				if e.Unit ~= f77 then
					mine77 = false
				end
			end
			T.check(AF.Stats().Live + AF.Stats().Stepped >= 1 and mine77, "Review Focus 4 (Leave): player 77's effects are live", fmt("Live %d", AF.Stats().Live))
			local ids = { f77 } -- (TeamOf: the fighter + the bench ids, like BattleSim's Leave)
			for _, b in ipairs(t77.Bench or {}) do
				ids[#ids + 1] = b
			end
			KC.toClient("BattleState", "Events", { { type = "Leave", owner = 77, units = ids } }, id)
			pulse(0.25)
			poolsAtKeep("Review Focus 4 (Leave event mid-effect)")
			T.check(AF.Pose(f77) == nil and BC.GetUnit(f77) == nil, "Review Focus 4 (Leave): the leaver's unit and pose are gone")
		end
		-- the End MESSAGE before any sim End event plays (fix round 2): the grace starts there, the winners' Victory starts
		-- after it and is never cut by it (a late End event changes nothing)
		local nv = #calls
		local endAt = os.clock()
		KC.toClient("BattleState", "End", { BattleId = id, Mode = "Raid", Outcome = "Win", Won = true, Spectator = false, Reason = "BossDown",
			Rewards = { Tokens = 10, Gems = 0, Xp = 5, Trophies = 0, LevelUps = 0, Tier = "Gold", Share = 0.4, Damage = 500 } }, id)
		KC.toClient("BattleState", "Events", { { type = "End", reason = "BossDown", winnerSide = 1 } }, id)
		local firstVictory, liveAfter = nil, nil
		for _ = 1, 75 do
			Mock.Step(1 / 30)
			for i = nv + 1, #calls do
				if calls[i].Attack == "Victory" and calls[i].Result == true and not firstVictory then
					firstVictory = calls[i].At
				end
			end
			if firstVictory and liveAfter == nil and os.clock() >= firstVictory + 0.5 then
				liveAfter = AF.Stats().Live + AF.Stats().Stepped
			end
		end
		T.check(firstVictory ~= nil and firstVictory >= endAt, "End message first: the winners play AttackFx Victory (after the grace)",
			firstVictory and fmt("%.2f s after the End", firstVictory - endAt) or "no Victory")
		T.check(liveAfter ~= nil and liveAfter >= 1, "End message first: the Victory is not cut by the grace (still live 0.5 s after it starts)", tostring(liveAfter))
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.advance(15)
		poolsAtKeep("after the second battle")
		T.check(type(BC.GetStats().AttackFx) == "table" and BC.GetStats().AttackFx.Live == 0, "GetStats().AttackFx = AttackFx.Stats()")

		-- 6) fix round 3 (review Important 3 + the KO pose pin): the killing SHOT, a pet's KO and the End arrive in one
		--    pulse with the End message right behind them. The shot's Hit and the boss's KO are held for the flying shot
		--    (Net.Queue held): the End plays only the unheld events and drains the held ones on the render clock, so the
		--    damage number and the boss's "KO!" pop when the shot LANDS, not at the End. The KO'd pet lies in its Ko pose
		--    with a constant body offset from End + 1.0 s (the grace clears AttackFx) until it is parked
		id = "p7vfx_raid_3"
		LocalPlayer:SetAttribute("InBattle", id)
		start = copyOf(rec.Start)
		start.BattleId = id
		KC.toClient("BattleState", "Start", start, id)
		live.id, live.T = id, (start.T or 0)
		local function fullSnap()
			local snap = rec.Sim:SnapshotDelta({})
			live.T = live.T + 0.1
			snap.T, snap.BattleId = live.T, id
			KC.toClient("BattleState", "Snapshot", snap, id)
		end
		for _ = 1, 8 do
			fullSnap()
			frames(0.1)
		end
		pulse(1.5)
		local boss3, shooter3, koUnit3 = nil, nil, nil
		for uid, info in pairs(infos) do
			local g = BC.GetUnit(uid)
			if g and info.kind == "Boss" and not g.Parked then
				boss3 = uid
			end
		end
		for uid, info in pairs(infos) do
			local g = BC.GetUnit(uid)
			if info.kind ~= "Boss" and drawable(g) and g.Model ~= nil and g.Hp and g.Hp > 0 then
				if info.ranged == true and (not shooter3 or uid < shooter3) then
					shooter3 = uid
				end
			end
		end
		for uid, info in pairs(infos) do
			local g = BC.GetUnit(uid)
			if uid ~= shooter3 and info.kind ~= "Boss" and drawable(g) and g.Model ~= nil and g.Hp and g.Hp > 0 and (not koUnit3 or uid < koUnit3) then
				koUnit3 = uid
			end
		end
		if T.check(boss3 and shooter3 and koUnit3 and true or false, "End with a shot in flight: a ranged pet, a second pet and the boss are on the floor",
			fmt("boss %s shooter %s ko %s", tostring(boss3), tostring(shooter3), tostring(koUnit3))) then
			local bossModel = BC.GetUnit(boss3).Model
			local koModel = BC.GetUnit(koUnit3).Model
			local function bossLabel(match)
				local fx = workspace:FindFirstChild("ClientBattle") and workspace.ClientBattle:FindFirstChild("Fx")
				for _, g in ipairs(fx and fx:GetDescendants() or {}) do
					if g:IsA("TextLabel") and string.find(g.Text, match, 1, true) then
						local bb = g:FindFirstAncestorOfClass("BillboardGui")
						if bb and bb.Enabled and bb.Adornee and (bb.Adornee == bossModel or bb.Adornee:IsDescendantOf(bossModel)) then
							return true
						end
					end
				end
				return false
			end
			-- the KO'd pet's drawn pose (PetBuilder.Animate's opts.Pose and the body offset it gives)
			local koFrames = {}
			local spyAnimate = PB.Animate
			PB.Animate = function(model, t, opts)
				if model == koModel and type(opts) == "table" then
					local body = PB.PoseBody(opts)
					koFrames[#koFrames + 1] = { At = os.clock(), Name = type(opts.Pose) == "table" and opts.Pose.Name or nil, Pos = body and body.Position, CF = body }
				end
				return spyAnimate(model, t, opts)
			end
			for _, su in ipairs(rec.Sim.units or {}) do
				if su.id == koUnit3 then
					su.hp = 0
					su.state = downState
				end
			end
			local n0 = #calls
			KC.toClient("BattleState", "Events", {
				{ type = "Hit", from = shooter3, to = boss3, dmg = 4321 },
				{ type = "KO", unit = boss3, by = shooter3 },
				{ type = "KO", unit = koUnit3, by = boss3 },
				{ type = "End", reason = "BossDown", winnerSide = 1 },
			}, id)
			fullSnap()
			local endAt = os.clock()
			KC.toClient("BattleState", "End", { BattleId = id, Mode = "Raid", Outcome = "Win", Won = true, Spectator = false, Reason = "BossDown",
				Rewards = { Tokens = 10, Gems = 0, Xp = 5, Trophies = 0, LevelUps = 0, Tier = "Gold", Share = 0.4, Damage = 500 } }, id)
			local shot = nil
			for i = n0 + 1, #calls do
				if calls[i].Attack == "Ranged" and calls[i].From == shooter3 then
					shot = calls[i]
				end
			end
			local impactAt = nil
			for _, e in ipairs(AF._Live()) do
				if e.Unit == shooter3 and e.Recipe.Attack == "Ranged" then
					impactAt = e.Start + e.Times.Impact
				end
			end
			local numberAt, koAt, parkedAt, poseBad = nil, nil, nil, {}
			if bossLabel("4321") then
				numberAt = endAt -- (already up at the End: flushed early)
			end
			for _ = 1, 105 do
				Mock.Step(1 / 30)
				local now = os.clock()
				if not numberAt and bossLabel("4321") then
					numberAt = now
				end
				if not koAt and bossLabel("KO!") then
					koAt = now
				end
				local g = BC.GetUnit(koUnit3)
				if not parkedAt and (g == nil or g.Parked) then
					parkedAt = now
				end
				if not parkedAt and now >= endAt + 1.0 and g and g.Pose ~= "Ko" then
					poseBad[#poseBad + 1] = fmt("%.2f s: drawn %s", now - endAt, tostring(g.Pose))
				end
			end
			PB.Animate = spyAnimate
			T.check(shot ~= nil and shot.Result == true and type(shot.Late) == "number" and shot.Late > 0.05 and impactAt ~= nil and impactAt > endAt + 0.05,
				"End with a shot in flight: (precondition) the killing shot is still flying when the End arrives", shot and fmt("late %s, lands %.2f s after the End", tostring(shot.Late), (impactAt or endAt) - endAt) or "no shot")
			T.check(numberAt ~= nil and impactAt ~= nil and numberAt >= impactAt - 1 / 30 - 1e-3 and numberAt <= impactAt + 0.25,
				"review Important 3: the killing shot's damage number pops when the shot lands, not at the End",
				fmt("number %s s after the impact (impact %.2f s after the End)", numberAt and impactAt and fmt("%.3f", numberAt - impactAt) or "never", (impactAt or endAt) - endAt))
			T.check(koAt ~= nil and impactAt ~= nil and koAt >= impactAt - 1 / 30 - 1e-3 and koAt <= impactAt + 0.25,
				"review Important 3: ... and so does the boss's KO!", fmt("KO! %s s after the impact", koAt and impactAt and fmt("%.3f", koAt - impactAt) or "never"))
			-- the pin: from End + 1.0 s until parked the pet is drawn in its Ko pose with one constant body offset
			local ref, drift, wrong, n = nil, 0, {}, 0
			for _, f in ipairs(koFrames) do
				if f.At >= endAt + 1.0 and (not parkedAt or f.At < parkedAt) then
					n = n + 1
					if f.Name ~= "Ko" or not f.Pos then
						wrong[#wrong + 1] = tostring(f.Name)
					else
						ref = ref or f.CF
						drift = math.max(drift, (f.Pos - ref.Position).Magnitude, (ref.LookVector - f.CF.LookVector).Magnitude, (ref.UpVector - f.CF.UpVector).Magnitude)
					end
				end
			end
			T.check(parkedAt ~= nil and parkedAt > endAt + 1.2 and n >= 3 and #wrong == 0 and #poseBad == 0 and drift < 1e-3,
				"KO pose pin: from End + 1.0 s until it is parked the KO'd pet is drawn in its Ko pose with a constant body offset",
				fmt("parked %s s after the End, %d frames, not Ko: %s / %s, drift %.4f", parkedAt and fmt("%.2f", parkedAt - endAt) or "never", n,
					table.concat(wrong, ","), table.concat(poseBad, ","), drift))
		end
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.advance(15)
		poolsAtKeep("after the third battle")
	end)
	AF.Play = realPlay
	PB.Animate = realAnimate
	force = nil
	if not ok then
		T.fail("client_p7vfx_battle raised an error", tostring(err))
	end
	local warned = nil
	for i = out0 + 1, #Mock.Output do
		local o = Mock.Output[i]
		if o.kind == "warn" and (o.text:find("BattleController", 1, true) or o.text:find("AttackFx", 1, true)) then
			warned = o.text
			break
		end
	end
	T.check(warned == nil and #Mock.Errors == err0, "client_p7vfx_battle: no errors or BattleController / AttackFx warnings", tostring(warned))
	AF.SetQuality(nil)
	KC.flushErrors("client_p7vfx_battle")
end)

return S
