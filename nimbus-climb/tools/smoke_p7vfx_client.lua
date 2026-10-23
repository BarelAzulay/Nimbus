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

	-- clean up
	Fx.ClearAll()
	Fx.Hooks.Punch = nil
	Fx._Deps({ MeshLibrary = false, TextureIds = false })
	Fx.SetQuality(nil)
	T.check(Fx.Stats().Live == 0 and Fx.Pose(21) == nil, "ClearAll: nothing live, no poses")
	holder:Destroy()
end)

return S
