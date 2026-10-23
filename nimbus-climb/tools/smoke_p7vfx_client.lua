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
	local onlySecond, sawStrike, blendDone = true, false, false
	run(1.6, function()
		local p = Fx.Pose(21)
		if p then
			if p.Ranged ~= true then
				onlySecond = false
			end
			if p.Name == "Strike" then
				sawStrike = true
			end
			if p.Blend == 1 and p.Prev == nil then
				blendDone = true
			end
		end
	end)
	T.check(onlySecond and sawStrike and blendDone, "RF3: from then on only the second play's poses (ranged Windup -> Strike), crossfade done after ~0.12 s")
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

	-- 13) a charge glow dropped for lack of time takes no emitter slot (Lava Slam: 7 emitter layers, cap 6) -------------
	Fx.Play(ctx({ Element = "Flame", Attack = "Special", Kind = "Blast", PetId = "magma_cub", Rarity = "Secret", DueAt = clock, Now = clock }))
	local em = Fx._Live()[#Fx._Live()]
	local crack, charge = false, false
	for _, it in ipairs(em and em.Items or {}) do
		if it.Kind == "Emitter" and it.Layer.Id == "SigLavaCrack" then
			crack = true
		elseif it.Kind == "Emitter" and it.Layer.Id == "Charge" then
			charge = true
		end
	end
	T.check(em and em.Times.Release == 0 and not charge and crack and em.Emitters == Fx.MAX_EMITTERS.High,
		"no charge time: the dropped charge glow frees its emitter slot (the signature lava crack is drawn, 6 emitters)", em and tostring(em.Emitters))
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
			T.check(calls[n1 + 1] and calls[n1 + 1].Result == true and (attackPose == "Strike" or attackPose == "Windup"),
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
