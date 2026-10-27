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
--   client_p7vfx_storm  (Task 11 fix round 2) a Storm special in a recorded Duel lands on exactly the enemies the sim's
--               zone hits (BattleController's Atk.Special gathers them: the event names only the aimed one).

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

-- (Task 10 review M2 / I2, test 16) the identity layers keep their COUNT at every rarity, not just one item: the Beam's
-- two spiral arcs (the 4-beam cap with the element's alive beams and the Mythic double crescent cut them to one),
-- Storm's two crackle bolts / cage arcs (a third from Legendary when the cap has room); the wrap streams.
-- { kind = { layerId = at least n } }, checked where the recipe has the layer. -> the shortfalls ({} = fine)
local IDENT_COUNT = { Beam = { Spiral = 2, Wrap = 1 }, Blast = { Crackle = 2 }, Freeze = { Arcs = 2 } }
local function identityShort(kind, recipe, per)
	local out = {}
	for id, want in pairs(IDENT_COUNT[kind] or {}) do
		local has = false
		for _, l in ipairs(recipe.Layers) do
			has = has or l.Id == id
		end
		local n = per[id] or 0
		if has and n < want then
			out[#out + 1] = string.format("%d x %s (want >= %d)", n, id, want)
		end
	end
	return out
end

local SIGNATURE_PETS_C = {
	"ember_phoenix", "sunbeam_bear", "twilight_dragon", "cloudy_dragon", "starlight_unicorn", "stormfang",
	"eclipse_dragon", "obsidian_phoenix", "phantom_kitsune", "magma_cub", "rime_wyrmling", "hydralotl",
}
-- (Task 11, test 17) the 12 signature specials in the engine. env = { Fx, Cat, ctx, run, clock = fn() -> now, A, B,
-- allies = { 4 ally models } }. For each signature at every rarity (7: its own, and lower ones a budget step-down draws)
-- the effect plays within every per-effect cap and DRAWS its signature: every non-light recipe layer has >= 1 item, the
-- lights are min(3, light layers), its alive detail, its core (the signature's key), its actor pieces at their count
-- (x the allies for a per-ally actor, its rim copy for each, others' pets x Density 0.6), the identity counts (Storm
-- Pounce's 2 bolts, Cloud Breath's 2 spiral arcs). Kitsune's nine orbs: all nine on 1, 2 or 4 allies, spread round
-- robin. Low quality: the actor stays, <= 2 emitters. The Eclipse dim: own pet only, given back on end / Cancel / ClearAll.
local SIG_DRAW = {
	ember_phoenix = { Core = "vfx_sig_phoenix_wing" },
	sunbeam_bear = { Actor = 1, PerAlly = true },
	twilight_dragon = { Core = "vfx_star", Actor = 1, Rim = true },
	cloudy_dragon = { Actor = 1, Count = { Spiral = 2 } },
	starlight_unicorn = { Actor = 1, Rim = true },
	stormfang = { Actor = 1, Rim = true, Count = { SigBolts = 2 } },
	eclipse_dragon = { Actor = 1, Rim = true },
	obsidian_phoenix = { Actor = 1, Rim = true, Echo = 2 },
	phantom_kitsune = { Actor = 9 },
	magma_cub = { Core = "vfx_chunk", Actor = 5 },
	rime_wyrmling = { Core = "vfx_sig_glacier" },
	hydralotl = { Actor = 3, Rim = true },
}
local SIG_SUPPORT = { Heal = true, Shield = true, Rally = true, Haste = true }

-- the items of a live effect: per layer id, the core pieces, the actor pieces / rims, the alive items, the actor echoes
local function sigItems(el)
	local per, core, actor, rims, alive, echoes = {}, 0, 0, 0, 0, 0
	for _, it in ipairs(el.Items) do
		local id = it.Layer and it.Layer.Id
		if id then
			per[id] = (per[id] or 0) + 1
		end
		if it.Layer and it.Layer.Alive then
			alive = alive + 1
		end
		if it.Kind == "Solid" and not it.Layer then
			if it.Rim then
				rims = rims + 1
			elseif it.Echo then
				echoes = echoes + 1
			elseif it.Actor then
				actor = actor + 1
			else
				core = core + 1
			end
		end
	end
	return per, core, actor, rims, alive, echoes
end

local function signatureEngine(env)
	local Fx, Cat, ctx, run = env.Fx, env.Cat, env.ctx, env.run
	local function play(pet, rarity, mine, nAllies)
		local s = Cat.Signatures[pet]
		local to = { Unit = 96, Model = env.B }
		if SIG_SUPPORT[s.Kind] then
			to = {}
			for i = 1, nAllies or 4 do
				to[i] = { Unit = 200 + i, Model = env.allies[i] }
			end
		end
		Fx.ClearAll()
		local ok = Fx.Play(ctx({ Element = s.Element, Attack = "Special", Kind = s.Kind, PetId = pet, Rarity = rarity, Mine = mine,
			From = { Unit = 95, Model = env.A }, To = to, Now = env.clock() }))
		return ok and Fx._Live()[#Fx._Live()] or nil, s
	end
	local bad, seen = {}, 0
	for _, pet in ipairs(SIGNATURE_PETS_C) do
		local want = SIG_DRAW[pet]
		for _, rarity in ipairs(Cat.Rarities) do
			for _, mine in ipairs({ true, false }) do
				local el, s = play(pet, rarity, mine)
				local why = {}
				if not el or el.Recipe.Signature ~= pet then
					why[#why + 1] = "did not play the signature"
				else
					local r = el.Recipe
					local per, core, actor, rims, alive, echoes = sigItems(el)
					if el.Emitters > Fx.MAX_EMITTERS.High or el.Beams > Fx.MAX_BEAMS or el.Trails > Fx.MAX_TRAILS or el.Lights > Fx.MAX_LIGHTS or el.Cores > Fx.MAX_CORES then
						why[#why + 1] = fmt("over a cap: %d em %d beams %d trails %d lights %d cores", el.Emitters, el.Beams, el.Trails, el.Lights, el.Cores)
					end
					local lights = 0
					for _, l in ipairs(r.Layers) do
						if l.Kind == "Light" then
							lights = lights + 1
						elseif not per[l.Id] then
							why[#why + 1] = "not drawn: " .. l.Id
						end
					end
					if el.Lights ~= math.min(Fx.MAX_LIGHTS, lights) then
						why[#why + 1] = fmt("%d of %d lights", el.Lights, lights)
					end
					if type(r.Alive) == "table" and r.Alive.Kind and alive == 0 then
						why[#why + 1] = "no alive item"
					end
					if want.Core and not (r.Core.Key == want.Core and core >= 1) then
						why[#why + 1] = fmt("core %s x%d", tostring(r.Core.Key), core)
					end
					if want.Actor then
						local n = want.Actor
						if not mine then
							n = math.max(1, math.floor(n * Cat.OthersDensity + 0.5))
						end
						if want.PerAlly then
							n = n * 4
						end
						if actor ~= n or rims ~= (want.Rim and n or 0) or echoes ~= (want.Echo or 0) * n then
							why[#why + 1] = fmt("%d actor pieces + %d rims + %d echoes (want %d%s, %d echoes)", actor, rims, echoes, n, want.Rim and " + rims" or "", (want.Echo or 0) * n)
						end
					end
					for id, n in pairs(want.Count or {}) do
						if (per[id] or 0) < n then
							why[#why + 1] = fmt("%d x %s (want >= %d)", per[id] or 0, id, n)
						end
					end
				end
				if #why > 0 then
					bad[#bad + 1] = fmt("%s %s %s: %s", pet, rarity, mine and "mine" or "other", table.concat(why, ", "))
				else
					seen = seen + 1
				end
			end
		end
	end
	T.check(#bad == 0 and seen == 12 * #Cat.Rarities * 2,
		"Task 11: each of the 12 signatures at every rarity (mine / others) plays within the caps and draws all its layers, its alive detail, its signature core, its actor pieces + rims at their count (others' x 0.6), Storm Pounce's 2 bolts and Cloud Breath's 2 spiral arcs",
		fmt("%d ok; %s", seen, table.concat(bad, " | ")))

	-- 17a) nine fox-fire orbs whatever the allies: all nine circle one ally; on 2 / 4 allies they are shared round robin
	local foxBad = {}
	for _, n in ipairs({ 1, 2, 4 }) do
		local el = play("phantom_kitsune", "Secret", true, n)
		local by, total = {}, 0
		for _, it in ipairs(el and el.Items or {}) do
			if it.Actor and not it.Rim then
				by[it.Ally] = (by[it.Ally] or 0) + 1
				total = total + 1
			end
		end
		local lo, hi = 99, 0
		for a = 1, n do
			lo, hi = math.min(lo, by[a] or 0), math.max(hi, by[a] or 0)
		end
		if not (el and total == 9 and lo >= 1 and hi - lo <= 1 and el.Cores <= Fx.MAX_CORES) then
			foxBad[#foxBad + 1] = fmt("%d allies: %d orbs, %d..%d per ally", n, total, lo, hi)
		end
	end
	T.check(#foxBad == 0, "Task 11: Foxfire Ward: nine fox-fire orbs on 1, 2 and 4 allies (shared round robin, within the piece cap)", table.concat(foxBad, " | "))

	-- 17b) Low quality keeps the signature: the actor pieces stay, <= 2 emitters (the Burst + its LowKeep), no beams / trails,
	-- and (fix round 1, M1) no rim / echo copies (a second see-through MeshPart per piece: the phone's overdraw cost)
	Fx.SetQuality("Low")
	local lowBad = {}
	for _, pet in ipairs(SIGNATURE_PETS_C) do
		local el = play(pet, Cat.Signatures[pet].Rarity, true)
		local _, core, actor, rims, _, echoes = sigItems(el or { Items = {} })
		local want = SIG_DRAW[pet]
		if not (el and el.Emitters <= 2 and el.Beams == 0 and el.Trails == 0 and (not want.Actor or actor >= 1) and (not want.Core or core >= 1) and rims == 0 and echoes == 0) then
			lowBad[#lowBad + 1] = fmt("%s: %s emitters, %d actor, %d core, %d rims, %d echoes", pet, el and tostring(el.Emitters) or "?", actor, core, rims, echoes)
		end
	end
	Fx.SetQuality("High")
	T.check(#lowBad == 0, "Task 11: Low quality: every signature keeps its actor / core, <= 2 emitters, no beams / trails, no rims / echoes (rims == 0)", table.concat(lowBad, " | "))

	-- 17d) battle timing: the special arrives with the short render lead (DueAt = now + 0.15: the charge is cut to ~0),
	-- yet each signature's own piece is still SEEN after the impact (Cloud Breath's coil, the dusk moon, the black sun on
	-- the floor, the serpents, the orbs, the seals, the spikes, the wishing star; Obsidian's pass: 17e), and the
	-- Hydralotl heads lunge only once they have risen
	local seenBad = {}
	local lunge = { early = 0, late = 0 }
	for _, pet in ipairs(SIGNATURE_PETS_C) do
		local want = SIG_DRAW[pet]
		if want.Actor then
			local s = Cat.Signatures[pet]
			local to = { Unit = 96, Model = env.B }
			if SIG_SUPPORT[s.Kind] then
				to = {}
				for i = 1, 4 do
					to[i] = { Unit = 200 + i, Model = env.allies[i] }
				end
			end
			Fx.ClearAll()
			local now = env.clock()
			Fx.Play(ctx({ Element = s.Element, Attack = "Special", Kind = s.Kind, PetId = pet, Rarity = s.Rarity, Mine = true,
				From = { Unit = 95, Model = env.A }, To = to, Now = now, DueAt = now + 0.15 }))
			local el = Fx._Live()[#Fx._Live()]
			local after = 0.3
			local shown = false
			if el then
				local impact = el.Start + el.Times.Impact
				run(1 / 30, nil)
				local head, p0 = nil, nil
				for _, it in ipairs(el.Items) do
					if it.Actor and not it.Rim and not head then
						head = it
					end
				end
				local stop = (pet == "hydralotl") and math.max(impact + after, el.Start + 0.75) or impact + after
				while env.clock() < stop do
					if pet == "hydralotl" and head and head.Kit then
						-- (the lunge moves the head forward, flat: before the rise is done it must stay put)
						local t = env.clock() - el.Start
						local p = head.Kit.Root.Position
						p = Vector3.new(p.X, 0, p.Z)
						p0 = p0 or p
						local d = (p - p0).Magnitude
						if t < head.T0 + 0.27 then
							lunge.early = math.max(lunge.early, d)
						elseif t > head.T0 + 0.32 and t < head.T0 + 0.62 then
							lunge.late = math.max(lunge.late, d)
						end
					end
					run(1 / 30)
				end
				for _, it in ipairs(el.Items) do
					if it.Actor and not it.Rim and it.Kit and it.Kit.Root.Transparency < 0.98 then
						shown = true
					end
				end
			end
			if not (el and shown and el.Times.Charge < 0.2) then
				seenBad[#seenBad + 1] = fmt("%s: %s (charge %.2f)", pet, el and "actor not seen" or "no effect", el and el.Times.Charge or -1)
			end
		end
	end
	Fx.ClearAll()
	T.check(#seenBad == 0, "Task 11: battle timing (charge cut by a 0.15 s lead): every signature's own piece is still seen after the impact", table.concat(seenBad, " | "))
	T.check(lunge.early < 0.05 and lunge.late > 0.4, "Task 11: battle timing: the Hydralotl serpents rise first, then lunge (not while rising)",
		fmt("moved %.2f studs while rising, %.2f after", lunge.early, lunge.late))

	-- 17e) (Task 11 fix round 1 ruling) Obsidian's Shadowflame Storm hits every enemy in its zone (BattleController gathers
	-- them: client_p7vfx_storm), so no single-target dive: around the
	-- impact (the charge is cut in a battle) the phoenix makes a LOW pass across the whole enemy line, end to end, passing
	-- over every enemy, and the dark fire rain lands on every target. Two groups (4 in a line; 2 far apart on a slant),
	-- each with a battle's 0.15 s lead and with the full /fx charge
	local sweepBad = {}
	local groups = {
		{ Name = "4 in a line", Models = { env.allies[1], env.allies[2], env.allies[3], env.allies[4] } },
		{ Name = "2 far apart", Models = { env.B, env.allies[4] } },
	}
	for _, g in ipairs(groups) do
		for _, lead in ipairs({ 0.15, false }) do
			local label = g.Name .. (lead and " (battle lead)" or " (/fx charge)")
			local to, pts = {}, {}
			for i, m in ipairs(g.Models) do
				to[i] = { Unit = 310 + i, Model = m }
				pts[i] = m:GetPivot().Position
			end
			Fx.ClearAll()
			local now = env.clock()
			Fx.Play(ctx({ Element = "Flame", Attack = "Special", Kind = "Storm", PetId = "obsidian_phoenix", Rarity = "Secret", Mine = true,
				From = { Unit = 95, Model = env.A }, To = to, Now = now, DueAt = lead and (now + lead) or nil }))
			local el = Fx._Live()[#Fx._Live()]
			local bird = nil
			for _, it in ipairs(el and el.Items or {}) do
				if it.Actor and not it.Rim and not it.Echo then
					bird = it
				end
			end
			if not (el and el.Recipe.Signature == "obsidian_phoenix" and bird) then
				sweepBad[#sweepBad + 1] = label .. ": no Obsidian effect / phoenix"
			else
				-- the enemy line: the flat axis through the two targets farthest apart, the targets' extent along it
				local ax, far = nil, 0
				for i = 1, #pts - 1 do
					for j = i + 1, #pts do
						local d = Vector3.new(pts[j].X - pts[i].X, 0, pts[j].Z - pts[i].Z)
						if d.Magnitude > far then
							far, ax = d.Magnitude, d.Unit
						end
					end
				end
				local lo, hi, midY = math.huge, -math.huge, 0
				for _, p in ipairs(pts) do
					local k = p:Dot(ax)
					lo, hi, midY = math.min(lo, k), math.max(hi, k), midY + p.Y / #pts
				end
				local size = el.Size
				local impact = el.Start + el.Times.Impact
				local w0, w1 = impact - 0.4, impact + 0.6 -- (the impact's window)
				local seenLo, seenHi, lowest, atImpact = math.huge, -math.huge, math.huge, nil
				local near = {} -- per target: the closest the phoenix came (flat) in the window
				local land = {} -- per rain piece: its last seen point and time
				for i = 1, #pts do
					near[i] = math.huge
				end
				local stop = math.max(w1, el.Start + el.Times.Linger + 0.4)
				while env.clock() < stop do
					run(1 / 30)
					local t = env.clock()
					local root = bird.Kit and bird.Kit.Root
					if root and root.Transparency < 0.98 and t >= w0 and t <= w1 then
						local p = root.Position
						local k = p:Dot(ax)
						seenLo, seenHi = math.min(seenLo, k), math.max(seenHi, k)
						lowest = math.min(lowest, p.Y - midY)
						for i, q in ipairs(pts) do
							near[i] = math.min(near[i], Vector3.new(p.X - q.X, 0, p.Z - q.Z).Magnitude)
						end
						if not atImpact and t >= impact then
							atImpact = k
						end
					end
					for _, it in ipairs(el.Items) do
						if it.Kind == "Solid" and not it.Layer and not it.Actor and it.Kit and it.Kit.Root.Transparency < 0.98 then
							land[it] = { it.Kit.Root.Position, t }
						end
					end
				end
				local why = {}
				if not (seenLo <= lo and seenHi >= hi) then
					why[#why + 1] = fmt("pass %.1f..%.1f does not span the enemies %.1f..%.1f", seenLo, seenHi, lo, hi)
				end
				if not (atImpact and atImpact >= lo - 3 * size and atImpact <= hi + 3 * size) then
					why[#why + 1] = "not over the enemy line at the impact"
				end
				if lowest > 1 + 1.2 * size then
					why[#why + 1] = fmt("not low: %.1f studs over the enemies at best", lowest)
				end
				for i = 1, #pts do
					if near[i] > 2 then
						why[#why + 1] = fmt("passes %.1f studs wide of enemy %d", near[i], i)
					end
				end
				local covered, pieces = 0, 0
				for i, q in ipairs(pts) do
					local hit = false
					for _, l in pairs(land) do
						if Vector3.new(l[1].X - q.X, 0, l[1].Z - q.Z).Magnitude <= 1.4 * size + 0.3 and l[2] >= w0 and l[2] <= w1 then
							hit = true
						end
					end
					covered = covered + (hit and 1 or 0)
				end
				for _ in pairs(land) do
					pieces = pieces + 1
				end
				if covered ~= #pts then
					why[#why + 1] = fmt("the rain (%d pieces) lands on %d of %d targets in the impact's window", pieces, covered, #pts)
				end
				if el.Cores > Fx.MAX_CORES or el.Emitters > Fx.MAX_EMITTERS.High or el.Beams > Fx.MAX_BEAMS or el.Lights > Fx.MAX_LIGHTS or el.Trails > Fx.MAX_TRAILS then
					why[#why + 1] = fmt("over a cap: %d pieces %d em %d beams %d lights", el.Cores, el.Emitters, el.Beams, el.Lights)
				end
				if #why > 0 then
					sweepBad[#sweepBad + 1] = label .. ": " .. table.concat(why, ", ")
				end
			end
		end
	end
	Fx.ClearAll()
	T.check(#sweepBad == 0,
		"Task 11 fix: Obsidian's Shadowflame Storm: around the impact a low pass spans the whole enemy line (over every enemy), the dark fire rains on every target, within the caps (battle lead and /fx)",
		table.concat(sweepBad, " | "))

	-- 17f) (fix round 2, M7) the pass's axis is frozen when it starts (TP0): two enemies 10 studs apart across the caster's
	-- view turn 150 degrees round their middle during the pass (past square to the caster: a per-frame axis would flip
	-- there and swap the pass's ends). The phoenix keeps going one way along the axis it started on, with no jump
	do
		local m1, m2 = env.allies[1], env.allies[2]
		local cf1, cf2 = m1:GetPivot(), m2:GetPivot()
		local a0 = env.A:GetPivot().Position
		local p0 = env.B:GetPivot().Position
		local dir = Vector3.new(p0.X - a0.X, 0, p0.Z - a0.Z).Unit
		local right = dir:Cross(Vector3.new(0, 1, 0))
		local function place(theta)
			local r = CFrame.Angles(0, theta, 0)
			m1:PivotTo(CFrame.new(p0 + r:VectorToWorldSpace(-right * 5)))
			m2:PivotTo(CFrame.new(p0 + r:VectorToWorldSpace(right * 5)))
		end
		place(0)
		Fx.ClearAll()
		Fx.Play(ctx({ Element = "Flame", Attack = "Special", Kind = "Storm", PetId = "obsidian_phoenix", Rarity = "Secret", Mine = true,
			From = { Unit = 95, Model = env.A }, To = { { Unit = 321, Model = m1 }, { Unit = 322, Model = m2 } }, Now = env.clock() }))
		local el = Fx._Live()[#Fx._Live()]
		local bird = nil
		for _, it in ipairs(el and el.Items or {}) do
			if it.Actor and not it.Rim and not it.Echo then
				bird = it
			end
		end
		local back, jump, frames, prev = 0, 0, 0, nil
		if el and bird and bird.TP0 then
			local tp0, tp1 = el.Start + bird.TP0, el.Start + bird.TP1
			while env.clock() < tp1 do
				local t = env.clock()
				place(math.rad(150) * math.max(0, math.min(1, (t - tp0) / (tp1 - tp0))))
				run(1 / 30)
				local root = bird.Kit and bird.Kit.Root
				if env.clock() > tp0 and env.clock() <= tp1 and root then
					local p = Vector3.new(root.Position.X, 0, root.Position.Z)
					if prev then
						local d = p - prev
						back = math.max(back, -d:Dot(right))
						jump = math.max(jump, d.Magnitude)
						frames = frames + 1
					end
					prev = p
				end
			end
		end
		Fx.ClearAll()
		m1:PivotTo(cf1)
		m2:PivotTo(cf2)
		T.check(el ~= nil and bird ~= nil and frames >= 10 and back < 0.05 and jump < 2.5,
			"Task 11 fix round 2 (M7): Obsidian's pass keeps the axis it started on while its two enemies turn 150 degrees: one way, no jump",
			fmt("%d frames, at most %.2f studs back along the start axis, biggest step %.2f studs", frames, back, jump))
	end

	-- 17c) the Eclipse dim (own pet only): one DimWorld with its own token + the caster's unit, lasting to DimWorld after
	-- the impact; Undim with that token when the effect ends, is cancelled or cleared; nothing for others' pets or another
	-- signature (the hooks found here are put back at the end)
	local dims, undims = {}, {}
	local hooks0 = { Fx.Hooks.DimWorld, Fx.Hooks.Undim }
	Fx.Hooks.DimWorld = function(seconds, token, unit)
		dims[#dims + 1] = { seconds, token, unit }
	end
	Fx.Hooks.Undim = function(token)
		undims[#undims + 1] = token
	end
	local function eclipse(mine, unit)
		Fx.ClearAll()
		dims, undims = {}, {}
		local c = ctx({ Element = "Shadow", Attack = "Special", Kind = "Blast", PetId = "eclipse_dragon", Rarity = "Secret", Mine = mine,
			From = { Unit = unit, Model = env.A }, To = { Unit = 96, Model = env.B }, Now = env.clock() })
		Fx.Play(c)
		local el = Fx._Live()[#Fx._Live()]
		run(1 / 30)
		return el
	end
	local el = eclipse(true, 301)
	local wantSecs = el and (el.Times.Impact - 1 / 30 + el.Recipe.Sig.DimWorld) or -1
	local d1 = dims[1]
	T.check(#dims == 1 and d1[3] == 301 and d1[2] ~= nil and math.abs(d1[1] - wantSecs) < 0.05 and #undims == 0,
		"Task 11: Eclipse Nova (mine) dims once from its first frame to DimWorld after the impact, with its own token and the caster's unit",
		fmt("%d dims, token %s unit %s, %.2f s (want %.2f), %d undims", #dims, tostring(d1 and d1[2]), tostring(d1 and d1[3]), d1 and d1[1] or -1, wantSecs, #undims))
	run((el and (el.End - el.Start) or 3) + 0.2)
	T.check(d1 ~= nil and #undims == 1 and undims[1] == d1[2] and Fx.Stats().Live == 0, "Task 11: ... and gives the light back (Undim with its token) when the effect ends", fmt("%d undims", #undims))
	eclipse(true, 302)
	Fx.Cancel(302)
	T.check(#dims == 1 and #undims == 1 and undims[1] == dims[1][2], "Task 11: Eclipse Nova cancelled (its caster gone): Undim at once", fmt("%d dims, %d undims", #dims, #undims))
	eclipse(true, 303)
	Fx.ClearAll()
	T.check(#dims == 1 and #undims == 1 and undims[1] == dims[1][2], "Task 11: Eclipse Nova cleared (the battle torn down): Undim at once", fmt("%d undims", #undims))
	-- two casts of the same caster: each its own token (the first one's end must never lift the second one's dim)
	eclipse(true, 305)
	Fx.Play(ctx({ Element = "Shadow", Attack = "Special", Kind = "Blast", PetId = "eclipse_dragon", Rarity = "Secret", Mine = true,
		From = { Unit = 305, Model = env.A }, To = { Unit = 96, Model = env.B }, Now = env.clock() }))
	run(1 / 30)
	T.check(#dims == 2 and dims[1][3] == 305 and dims[2][3] == 305 and dims[1][2] ~= dims[2][2], "Task 11: two Eclipse casts of one caster get tokens of their own",
		fmt("%d dims, tokens %s / %s", #dims, tostring(dims[1] and dims[1][2]), tostring(dims[2] and dims[2][2])))
	Fx.ClearAll()
	el = eclipse(false, 304)
	run(3)
	T.check(#dims == 0 and #undims == 0, "Task 11: another player's Eclipse Nova never dims (nor undims)", fmt("%d dims, %d undims", #dims, #undims))
	dims, undims = {}, {}
	play("magma_cub", "Secret", true)
	run(3)
	T.check(#dims == 0 and #undims == 0, "Task 11: no other signature dims the battle", fmt("%d dims", #dims))
	-- (fix round 1, M3) a MISSED Eclipse Nova never dims and its black sun never drops onto the floor (it fades where it
	-- hangs); the same cast that hits drops it flat (the control)
	local function sunLowest(miss)
		Fx.ClearAll()
		dims, undims = {}, {}
		Fx.Play(ctx({ Element = "Shadow", Attack = "Special", Kind = "Blast", PetId = "eclipse_dragon", Rarity = "Secret", Mine = true, Miss = miss,
			From = { Unit = 306, Model = env.A }, To = { Unit = 96, Model = env.B }, Now = env.clock() }))
		local mel = Fx._Live()[#Fx._Live()]
		local sun = nil
		for _, it in ipairs(mel and mel.Items or {}) do
			if it.Actor and not it.Rim and not it.Echo then
				sun = it
			end
		end
		local lowest, lastSeen = math.huge, -1
		local stop = mel and (mel.Start + mel.Times.Impact + 0.6) or env.clock()
		while env.clock() < stop do
			run(1 / 30)
			if sun and sun.Kit and sun.Kit.Root.Transparency < 0.98 then
				lowest, lastSeen = math.min(lowest, sun.Kit.Root.Position.Y), env.clock() - mel.Start - mel.Times.Impact
			end
		end
		return mel ~= nil and sun ~= nil, lowest, #dims, lastSeen
	end
	local floorY = env.B:GetPivot().Position.Y - (2 - 0.5) -- (ctx Ground 0.5: the units' centres 1.5 over it)
	local okHit, lowHit, dimsHit = sunLowest(false)
	local okMiss, lowMiss, dimsMiss, lastMiss = sunLowest(true)
	T.check(okHit and okMiss and dimsMiss == 0 and lowMiss > floorY + 2 and lastMiss <= 0.35 and dimsHit == 1 and lowHit < floorY + 1,
		"Task 11 fix: a MISSED Eclipse Nova never dims the battle and its black sun never drops (it fades where it hangs); a hit dims and drops it",
		fmt("miss: %d dims, lowest %.2f (floor %.2f), seen to impact + %.2f s | hit: %d dims, lowest %.2f", dimsMiss, lowMiss, floorY, lastMiss, dimsHit, lowHit))
	Fx.ClearAll()
	Fx.Hooks.DimWorld, Fx.Hooks.Undim = hooks0[1], hooks0[2]
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
	-- (Task 10 re-review I4) the shield ripple never punches the camera nor glows the screen, even MINE from a Mythic /
	-- Secret shield (it plays on every absorbed hit, a Linger zone's 0.5 s ticks included); the Hurt at Secret still
	-- does (the same hooks, counted: the 0 is not a dead stub)
	do
		punches, glows = {}, 0
		local played = 0
		for _, rarity in ipairs({ "Mythic", "Secret" }) do
			local c = ctx({ Element = "Celestial", Attack = "ShieldHit", Rarity = rarity, Mine = true, Now = clock })
			c.To = nil
			played = played + (Fx.Play(c) and 1 or 0)
			run(1)
		end
		T.check(played == 2 and #punches == 0 and glows == 0, "Mine = true ShieldHit at Mythic / Secret: no camera punch, no screen glow (Hooks stub)",
			fmt("%d played, %d punches, %d glows", played, #punches, glows))
		local c = ctx({ Element = "Celestial", Attack = "Hurt", Rarity = "Secret", Mine = true, Now = clock })
		c.To = nil
		local hurt = Fx.Play(c)
		run(1)
		T.check(hurt and #punches == 1 and glows == 1, "Mine = true Hurt at Secret: still one punch and one glow through the same hooks",
			fmt("played %s, %d punches, %d glows", tostring(hurt), #punches, glows))
		punches = {}
	end
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

	-- 16) Task 10: the 9 special kinds for every element. For every element x kind x rarity at High (the support kinds on
	-- 4 allies) the effect plays within every per-effect cap and DRAWS what makes it that element's kind: every layer of
	-- the recipe has >= 1 item (the emitter / beam budgets fit, so nothing is cut), its alive detail is drawn, and the
	-- lights are min(3, light layers). The identity layers are named on purpose (a recipe that lost them fails here):
	-- Beam Wrap (the element streaming along it), Shield Ward, Rally Roar + AllyRing / Rouse on each ally, Haste Gust +
	-- Wind on each ally, and the per-element pieces (Frost / Earth spike rings, Nature roots, Storm crackle / arcs,
	-- Celestial star spin)
	local allyModels = {}
	for i = 1, 4 do
		allyModels[i] = unitModel(holder, "Ally" .. i, Vector3.new(-6 + 4 * i, 2, 6))
	end
	local SUPPORT = { Heal = true, Shield = true, Rally = true, Haste = true }
	local IDENT = {
		Beam = { "Wrap", "Spiral", "Flare" }, Shield = { "Ward" }, Rally = { "Roar", "AllyRing", "Rouse" }, Haste = { "Gust", "Wind" },
		Heal = { "Spiral" }, Storm = { "Cloud", "Rain" }, Pounce = { "Leap" }, Blast = { "Dome", "Blastwave" }, Freeze = { "Lock" },
	}
	local OWN = {
		Frost = { Pounce = "IceSpikes", Freeze = "IceSpikes@Epic" }, Earth = { Pounce = "RockSpikes", Freeze = "RockSpikes@Epic" },
		Nature = { Blast = "RootBurst", Pounce = "RootBurst", Shield = "RootWard" }, Storm = { Blast = "Crackle", Freeze = "Arcs" },
		Celestial = { Freeze = "StarSpin" },
	}
	local rOrder = {}
	for i, r in ipairs(Cat.Rarities) do
		rOrder[r] = i
	end
	local kindBad, kindSeen = {}, 0
	for _, e in ipairs({ "Flame", "Water", "Frost", "Nature", "Earth", "Storm", "Celestial", "Shadow" }) do
		for _, kind in ipairs(Cat.KindNames) do
			for _, rarity in ipairs(Cat.Rarities) do
				Fx.ClearAll()
				local to = { Unit = 96, Model = B }
				if SUPPORT[kind] then
					to = {}
					for i = 1, 4 do
						to[i] = { Unit = 200 + i, Model = allyModels[i] }
					end
				end
				local played = Fx.Play(ctx({ Element = e, Attack = "Special", Kind = kind, Rarity = rarity, From = { Unit = 95, Model = A }, To = to, Now = clock }))
				local el = played and Fx._Live()[#Fx._Live()] or nil
				local r = el and el.Recipe
				local why = {}
				if not el then
					why[#why + 1] = "did not play"
				else
					local per, alive = {}, 0
					for _, it in ipairs(el.Items) do
						local id = it.Layer and it.Layer.Id
						if id then
							per[id] = (per[id] or 0) + 1
						end
						if it.Layer and it.Layer.Alive then
							alive = alive + 1
						end
					end
					if el.Emitters > Fx.MAX_EMITTERS.High or el.Beams > Fx.MAX_BEAMS or el.Trails > Fx.MAX_TRAILS or el.Lights > Fx.MAX_LIGHTS or el.Cores > Fx.MAX_CORES then
						why[#why + 1] = fmt("over a cap: %d em %d beams %d trails %d lights %d cores", el.Emitters, el.Beams, el.Trails, el.Lights, el.Cores)
					end
					if type(r.Alive) == "table" and r.Alive.Kind and alive == 0 then
						why[#why + 1] = "no alive item"
					end
					local lights = 0
					for _, l in ipairs(r.Layers) do
						if l.Kind == "Light" then
							lights = lights + 1
						elseif not per[l.Id] then
							why[#why + 1] = "not drawn: " .. l.Id
						end
					end
					if el.Lights ~= math.min(Fx.MAX_LIGHTS, lights) then
						why[#why + 1] = fmt("%d of %d lights", el.Lights, lights)
					end
					for _, id in ipairs(IDENT[kind] or {}) do
						if not per[id] then
							why[#why + 1] = "no " .. id
						end
					end
					for _, short in ipairs(identityShort(kind, r, per)) do -- (review M2: at their count, IDENT_COUNT)
						why[#why + 1] = short
					end
					local own = OWN[e] and OWN[e][kind]
					if own then
						local id, from = string.match(own, "^([^@]+)@?(.*)$")
						local due = from == "" or rOrder[rarity] >= rOrder[from]
						if due and not per[id] then
							why[#why + 1] = "no own " .. id
						elseif not due and per[id] then
							why[#why + 1] = id .. " before " .. from
						end
					end
					-- on each ally: the Rally rings and the Haste wind (4 allies)
					if kind == "Rally" and per.AllyRing ~= 4 then
						why[#why + 1] = fmt("%s ally rings", tostring(per.AllyRing))
					elseif kind == "Haste" and per.Wind ~= 4 then
						why[#why + 1] = fmt("%s wind trails", tostring(per.Wind))
					end
					-- the support cores: a shell / ring on each of the 4 allies
					if kind == "Shield" or kind == "Heal" or kind == "Haste" then
						local cores = 0
						for _, it in ipairs(el.Items) do
							if it.Kind == "Solid" and not it.Layer and type(it.Anchor) == "number" then
								cores = cores + 1
							end
						end
						if cores ~= 4 then
							why[#why + 1] = fmt("%d ally cores", cores)
						end
					end
				end
				if #why > 0 then
					kindBad[#kindBad + 1] = fmt("%s %s %s: %s", e, kind, rarity, table.concat(why, ", "))
				else
					kindSeen = kindSeen + 1
				end
			end
		end
	end
	T.check(#kindBad == 0 and kindSeen == 8 * 9 * #Cat.Rarities,
		"Task 10: every element x special kind x rarity plays within the caps and draws all its layers, its alive detail and its kind / element identity at full count (Beam 2 spiral arcs, Storm 2 crackle / cage arcs; support kinds on 4 allies)",
		fmt("%d ok; %s", kindSeen, table.concat(kindBad, " | ")))
	-- 16a) (Task 10 re-review M10 i) KeepCount is what keeps the Beam's 2 spiral arcs (behaviour, not the constant): Storm
	--      Beam Secret drawn with the catalog's Spiral as it is, then with its KeepCount taken off for this check (the
	--      alive strikes then fill the 4-beam cap first and the spiral drops to 1 arc), then put back
	do
		local sp = nil
		for _, l in ipairs(Cat.Specials.Beam.Layers) do
			if l.Id == "Spiral" then
				sp = l
			end
		end
		local function spirals()
			Fx.ClearAll()
			Fx.Play(ctx({ Element = "Storm", Attack = "Special", Kind = "Beam", Rarity = "Secret", From = { Unit = 95, Model = A }, To = { Unit = 96, Model = B }, Now = clock }))
			local el, n = Fx._Live()[#Fx._Live()], 0
			for _, it in ipairs(el and el.Items or {}) do
				if it.Layer and it.Layer.Id == "Spiral" then
					n = n + 1
				end
			end
			return n
		end
		local keep = sp and sp.KeepCount
		local with = spirals()
		if sp then
			sp.KeepCount = nil
		end
		local ok, without = pcall(spirals)
		if sp then
			sp.KeepCount = keep
		end
		T.check(sp ~= nil and keep ~= nil and with >= 2 and ok and without < with,
			"KeepCount (behaviour): Storm Beam Secret draws its 2 spiral arcs with the Spiral's KeepCount and fewer without it",
			fmt("%d arcs with KeepCount %s, %s without", with, tostring(keep), tostring(without)))
	end
	Fx.ClearAll()
	-- 16b) Low quality: every element x kind keeps 2 emitters at most: the Burst and the kind's chosen one (LowKeep)
	Fx.SetQuality("Low")
	local lowBad = {}
	for _, e in ipairs({ "Flame", "Water", "Frost", "Nature", "Earth", "Storm", "Celestial", "Shadow" }) do
		for _, kind in ipairs(Cat.KindNames) do
			Fx.ClearAll()
			Fx.Play(ctx({ Element = e, Attack = "Special", Kind = kind, Rarity = "Secret", From = { Unit = 97, Model = A }, To = { Unit = 98, Model = B }, Now = clock }))
			local el = Fx._Live()[#Fx._Live()]
			local ids = drawnIds(el)
			local want = el and el.Recipe.LowKeep[1]
			local firstKept = nil
			for _, id in ipairs(el and el.Recipe.LowKeep or {}) do
				for _, l in ipairs(el.Recipe.Layers) do
					if l.Id == id and engineEmitter(l) then
						firstKept = firstKept or id
					end
				end
			end
			if not (el and el.Emitters <= 2 and ids.Burst and (firstKept == nil or ids[firstKept]) and el.Beams == 0 and el.Trails == 0) then
				lowBad[#lowBad + 1] = fmt("%s %s: %s emitters, burst %s, keep %s (%s)", e, kind, el and tostring(el.Emitters) or "?", tostring(ids.Burst), tostring(firstKept), tostring(want))
			end
		end
	end
	Fx.SetQuality("High")
	T.check(#lowBad == 0, "Task 10: Low quality: every element's special keeps the Burst + its kind's chosen emitter, no beams / trails", table.concat(lowBad, " | "))
	Fx.ClearAll()

	-- 16c) the Pounce leaps like the melee: its Strike carries Reach = the gap (AttackFx.LeapReach) and a world Landing;
	-- the landing (p 0.26) falls on the slam; Pose(unit, base) shrinks the leap by what the base has covered (the server
	-- moves a pouncing pet to its target) and never below 0; without a base it is the full gap
	local pc = unitModel(holder, "PounceC", Vector3.new(60, 2, 0))
	local pt = unitModel(holder, "PounceT", Vector3.new(60, 2, -12))
	Fx.Play(ctx({ Attack = "Special", Kind = "Pounce", Element = "Earth", Rarity = "Rare", From = { Unit = 110, Model = pc }, To = { Unit = 111, Model = pt }, Now = clock }))
	local pe = Fx._Live()[#Fx._Live()]
	local p0 = pc:GetPivot().Position
	local gap = Fx.LeapReach({ Model = pc, Last = p0 }, { Model = pt, Last = pt:GetPivot().Position })
	local strikeReach, pAtImpact, halfReach, pastReach = nil, nil, nil, nil
	local impactAt = pe and (pe.Start + pe.Times.Impact)
	local trailOn, trailFollows = false, true
	run(1.6, function()
		local po = Fx.Pose(110)
		if po and po.Name == "Strike" then
			strikeReach = strikeReach or po.Reach
			if impactAt and pAtImpact == nil and clock >= impactAt then
				pAtImpact = po.P
			end
			local half = Fx.Pose(110, p0 + Vector3.new(0, 0, -5))
			halfReach = halfReach or (half and half.Reach)
			local past = Fx.Pose(110, p0 + Vector3.new(0, 0, -30))
			pastReach = pastReach or (past and past.Reach)
		end
		-- the leap trail rides the pet: move the caster along (as the drawn pose would) and the trail's host follows
		for _, it in ipairs(pe and pe.Items or {}) do
			if it.Kind == "Trail" and it.Layer and it.Layer.Id == "Leap" and it.On and clock - pe.Start <= it.T1 then
				trailOn = true
				local want = pc:GetPivot().Position + Vector3.new(0, 0.3, 0)
				if (it.Kit.Root.Position - want).Magnitude > 0.05 then
					trailFollows = false
				end
			end
		end
		pc:PivotTo(pc:GetPivot() + Vector3.new(0, 0, -0.05))
	end)
	T.check(type(gap) == "number" and gap > 8 and strikeReach and math.abs(strikeReach - gap) < 1e-3,
		"Pounce: the Strike leaps the whole gap (Reach = AttackFx.LeapReach, like the melee)", fmt("reach %s, gap %s", tostring(strikeReach), tostring(gap)))
	T.check(pAtImpact and math.abs(pAtImpact - 0.26) < 0.05, "Pounce: the leap lands (Strike p 0.26) on the slam (the impact)", tostring(pAtImpact))
	T.check(halfReach and math.abs(halfReach - (gap - 5)) < 1e-3 and pastReach == 0,
		"Pounce: Pose(unit, base) leaps only what is left from the drawn base to the landing (5 studs covered: gap - 5; past it: 0)",
		fmt("%s / %s", tostring(halfReach), tostring(pastReach)))
	T.check(trailOn and trailFollows, "Pounce: the leap trail rides the leaping pet (its pivot), not a scripted arc")
	pc:Destroy()
	pt:Destroy()
	run(2)

	-- 16d) the Beam's wrap streams the element along the beam (mouth -> hit), the Heal's sparkles are upright plus signs
	Fx.ClearAll()
	Fx.Play(ctx({ Attack = "Special", Kind = "Beam", Element = "Flame", Rarity = "Epic", From = { Unit = 112, Model = A }, To = { Unit = 113, Model = B }, Now = clock }))
	local be = Fx._Live()[#Fx._Live()]
	local wrap = nil
	for _, it in ipairs(be and be.Items or {}) do
		if it.Kind == "Emitter" and it.Layer and it.Layer.Id == "Wrap" then
			wrap = it
		end
	end
	local onLine, offLine, spread = 0, 0, {}
	run(1.2, function()
		if wrap and wrap.Seq and wrap.Seq > 0 and not spread[wrap.Seq] then
			spread[wrap.Seq] = true
			local p = wrap.Kit.Root.Position
			local a, b = be.Mouth, be.Hit
			local d = (b - a)
			local u = math.max(0, math.min(1, (p - a):Dot(d) / d:Dot(d)))
			if (a + d * u - p).Magnitude <= 0.6 * be.Size then
				onLine = onLine + 1
			else
				offLine = offLine + 1
			end
		end
	end)
	T.check(wrap and wrap.Kit.Em.Texture ~= "" and wrap.Layer.Texture == "fx_flame" and onLine >= 3 and offLine == 0,
		"Beam: the element streams along the beam (Flame: flame tongues, every emit point on mouth -> hit)", fmt("%d on, %d off", onLine, offLine))
	Fx.ClearAll()
	Fx.Play(ctx({ Attack = "Special", Kind = "Heal", Element = "Nature", Rarity = "Rare", From = { Unit = 114, Model = A }, To = { { Unit = 115, Model = B } }, Now = clock }))
	local he = Fx._Live()[#Fx._Live()]
	local plus = nil
	for _, it in ipairs(he and he.Items or {}) do
		if it.Kind == "Emitter" and it.Layer and it.Layer.Id == "Burst" then
			plus = it.Kit.Em
		end
	end
	T.check(plus and plus.Rotation.Min == 0 and plus.Rotation.Max == 0 and plus.RotSpeed.Min == 0 and plus.RotSpeed.Max == 0,
		"Heal: the sparkles are upright plus signs (no random roll, no spin)")
	Fx.ClearAll()
	-- 17) Task 11: the 12 signature specials (a file-level helper: this function is at the 200-locals limit)
	signatureEngine({ Fx = Fx, Cat = Cat, ctx = ctx, run = run, clock = function()
		return clock
	end, A = A, B = B, allies = allyModels })
	for _, m in ipairs(allyModels) do
		m:Destroy()
	end
	run(1)

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

-- (Task 11) Eclipse Nova's battle dim in a real battle: BattleController's hooks (Me.Dim / Me.Undim) push / pop the
-- LightingStack preset "AttackFxDim". env = { BC, AF, KC, id, pulse, helper, kid, boss, f, bo, info = fn(uid) -> the
-- unit's info }. -> E = { beforeKo(), afterKo(), stray(), torn(label) } for the hook-ins on the existing KO and End
-- sections (a file-level helper: the scenario function is near the 200-locals limit)
local DIM_ID_T = "AttackFxDim"
local function eclipseBattle(env)
	local BC, KC, id, pulse = env.BC, env.KC, env.id, env.pulse
	local LS = moduleAt(ROOTS.client .. "/LightingStack")
	local Lighting = game:GetService("Lighting")
	local E = {}
	local function dimmed()
		for _, x in ipairs(LS and LS.Ids() or {}) do
			if x == DIM_ID_T then
				return true
			end
		end
		return false
	end
	local function exposure()
		return Lighting.ExposureCompensation
	end
	local function eclipseLive(uid)
		for _, e in ipairs(env.AF._Live()) do
			if e.Unit == uid and e.Recipe.Signature == "eclipse_dragon" then
				return e
			end
		end
		return nil
	end
	-- a unit takes Eclipse Dragon's look (a Spawn of the same unit: Units.Add keeps the model, re-reads the look)
	local function skin(uid, on)
		local info = copyOf(env.info(uid) or {})
		if on then
			info.petId, info.rarity, info.element, info.elements = "eclipse_dragon", "Secret", "Shadow", { "Shadow" }
		end
		KC.toClient("BattleState", "Events", { { type = "Spawn", units = { info } } }, id)
		pulse(0.3)
	end
	local function cast(uid)
		local g = BC.GetUnit(uid)
		KC.toClient("BattleState", "Events", { { type = "Special", unit = uid, kind = "Blast", name = "Eclipse Nova", x = g.X, z = g.Z, tx = env.bo.X, tz = env.bo.Z, target = env.boss, targets = { env.boss } } }, id)
	end
	if not T.check(LS ~= nil and type(LS.Value) == "function" and BC._Me ~= nil and env.helper ~= nil and BC.GetUnit(env.helper) ~= nil,
		"Eclipse dim (battle): LightingStack (with Value), the battle's Me and my bench helper (the caster) are there") then
		return nil
	end
	-- the preset over a dungeon's look: every value darker than the one under it (added / the tint multiplied)
	local under = { ExposureCompensation = -0.15, Brightness = -0.12, Saturation = 0.14, TintColor = Color3.fromRGB(236, 226, 212) }
	local pr = BC._Me.DimPreset({ Value = function(_, prop)
		return under[prop]
	end })
	local cc = pr.ColorCorrection or {}
	T.check(pr.Lighting and math.abs(pr.Lighting.ExposureCompensation + 0.9) < 1e-6 and math.abs((cc.Brightness or 0) + 0.18) < 1e-6
		and math.abs((cc.Saturation or 0) + 0.21) < 1e-6 and typeof(cc.TintColor) == "Color3" and cc.TintColor.R < under.TintColor.R
		and cc.TintColor.G < under.TintColor.G and math.abs(cc.TintColor.B - under.TintColor.B) < 1e-6,
		"Eclipse dim (battle): the dim preset is relative: exposure -0.75, brightness -0.06, saturation -0.35, the tint made violet over the look under it")
	-- (an earlier scenario's AttackFx test may have cleared the hooks: point them back at this controller, its public way)
	T.check(BC.FxHooks() == true and type(env.AF.Hooks.DimWorld) == "function" and type(env.AF.Hooks.Undim) == "function",
		"Eclipse dim (battle): BattleController.FxHooks points AttackFx's DimWorld / Undim at the battle")
	local helper = env.helper
	skin(helper, true)
	pulse(1)
	local exp0 = exposure()
	-- 1) mine: dims from the cast, holds through the impact, gives the light back when the effect is over
	cast(helper)
	pulse(0.4)
	local el = eclipseLive(helper)
	local onAt, expDim = dimmed(), exposure()
	local impactAt = el and (el.Start + el.Times.Impact) or nil
	local offAt = nil
	for _ = 1, 40 do
		pulse(0.1)
		if not offAt and not dimmed() then
			offAt = os.clock()
		end
	end
	T.check(el ~= nil and onAt and math.abs(expDim - (exp0 - 0.75)) < 1e-3,
		"Eclipse dim (battle): my Eclipse Nova dims the battle (LightingStack AttackFxDim, exposure 0.75 lower)",
		fmt("live %s, dimmed %s, exposure %.3f (base %.3f)", tostring(el ~= nil), tostring(onAt), expDim, exp0))
	T.check(offAt ~= nil and impactAt ~= nil and offAt >= impactAt and not dimmed() and math.abs(exposure() - exp0) < 1e-6 and eclipseLive(helper) == nil,
		"Eclipse dim (battle): ... it holds through the impact and the light comes back (the base exposure) once it is over",
		fmt("off %.2f s after the impact, exposure %.3f (base %.3f)", (offAt or 0) - (impactAt or 0), exposure(), exp0))
	-- 2) relative to the look under it (a dungeon's darker preset): darker still, and a second cast never dims twice
	pcall(LS.Push, "T11Under", { Lighting = { ExposureCompensation = exp0 - 0.4 } }, 0)
	cast(helper)
	pulse(0.4)
	local e1 = exposure()
	pulse(0.2) -- (the first dim still on: the re-cast overlaps it)
	local stillOn = dimmed()
	cast(helper)
	pulse(0.4)
	local e2 = exposure()
	pulse(4)
	local e3 = exposure()
	pcall(LS.Pop, "T11Under", 0)
	pulse(0.2)
	T.check(stillOn and math.abs(e1 - (exp0 - 1.15)) < 1e-3 and math.abs(e2 - e1) < 1e-6 and math.abs(e3 - (exp0 - 0.4)) < 1e-6 and math.abs(exposure() - exp0) < 1e-6,
		"Eclipse dim (battle): the dim is relative to the look under it (a darker dungeon gets darker), a re-cast never dims twice, the look under it comes back",
		fmt("dim %.3f / re-cast %.3f (want %.3f), after %.3f (want %.3f), popped %.3f", e1, e2, exp0 - 1.15, e3, exp0 - 0.4, exposure()))
	-- 3) another player's Eclipse Nova never dims my battle
	if T.check(env.kid ~= nil and BC.GetUnit(env.kid) ~= nil, "Eclipse dim (battle): player 77's fighter is on the floor") then
		skin(env.kid, true)
		cast(env.kid)
		pulse(0.4)
		local played, d = eclipseLive(env.kid) ~= nil, dimmed()
		pulse(3)
		skin(env.kid, false)
		T.check(played and not d and math.abs(exposure() - exp0) < 1e-6, "Eclipse dim (battle): another player's Eclipse Nova plays but never dims my battle",
			fmt("played %s, dimmed %s", tostring(played), tostring(d)))
	end
	-- the KO hook-in: my Eclipse caster is knocked out mid-cast -> the light comes back when its KO plays, its effect
	-- still plays. (Task 11b: the helper's Special came with no press, so it lands late and its caster's KO in that late
	-- charge is a LAST GASP: the KO plays just after the impact; the light comes back then, still before the dim was due)
	function E.beforeKo()
		local real = env.AF.Hooks.DimWorld
		E.dueAt = nil
		env.AF.Hooks.DimWorld = function(seconds, ...)
			E.dueAt = os.clock() + seconds
			return real(seconds, ...)
		end
		cast(helper)
		pulse(0.2)
		env.AF.Hooks.DimWorld = real
		local el = eclipseLive(helper)
		E.impactAt = el and (el.Start + el.Times.Impact) or nil
		return T.check(dimmed() and el ~= nil and E.dueAt ~= nil, "Eclipse dim (battle KO): my helper's Eclipse Nova dims (before its KO)")
	end
	function E.afterKo()
		-- (the KO arrived 0.3 s ago; a last gasp plays it up to LATE_MAX + LAST_GASP after its time)
		local offAt = (not dimmed()) and os.clock() or nil
		for _ = 1, 4 do
			if offAt then
				break
			end
			pulse(0.1)
			if not dimmed() then
				offAt = os.clock()
			end
		end
		local e = eclipseLive(helper)
		T.check(offAt ~= nil and e ~= nil and offAt < (E.dueAt or 0) and E.impactAt ~= nil and offAt >= E.impactAt - 1e-3,
			"Eclipse dim (battle KO): the caster's KO (a last gasp: after its impact) gives the light back, its effect still playing, the dim not yet due",
			fmt("off %s s after the impact, effect %s, %.2f s before the dim was due", offAt and fmt("%.2f", offAt - (E.impactAt or 0)) or "never",
				tostring(e ~= nil), (E.dueAt or 0) - (offAt or os.clock())))
		pulse(0.4)
		T.check(math.abs(exposure() - exp0) < 1e-6, "Eclipse dim (battle KO): ... back to the base exposure", fmt("%.3f (base %.3f)", exposure(), exp0))
	end
	-- the teardown hook-in: a dim no effect owns any more (DIM_MAX 2.5 s) is cut when the battle's effects are torn down
	function E.stray()
		E.strayAt = os.clock()
		BC._Me.Dim(2.5, "t11stray")
		pulse(0.2)
		return dimmed()
	end
	function E.torn(label)
		T.check(E.strayAt ~= nil and os.clock() - E.strayAt < 2.4 and not dimmed(),
			"Eclipse dim (battle teardown): " .. label .. ": the battle's dim is cut before its time is up",
			fmt("%.2f s after the dim, dimmed %s", os.clock() - (E.strayAt or 0), tostring(dimmed())))
	end
	return E
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
		local seen, bad, wrongLook, leads, lastRip = {}, {}, {}, { n = 0, positive = 0, max = 0 }, {}
		for _, st in ipairs(rec.Steps) do
			for _, ev in ipairs(st.Events) do
				if ev.type == "Spawn" or ev.type == "Wave" then
					learn(ev.units)
				end
				local want = expected(ev)
				local n0 = #calls
				KC.toClient("BattleState", "Events", { ev }, id)
				local got, ripples = {}, {}
				for i = n0 + 1, #calls do
					-- (Task 10 review I1: an absorbed hit also ripples the victim's shield: ShieldHit, apart from the attack's play)
					if calls[i].Attack == "ShieldHit" then
						ripples[#ripples + 1] = calls[i]
					else
						got[#got + 1] = calls[i]
					end
				end
				local label = ev.type .. (ev.kind and (" " .. tostring(ev.kind)) or "") .. " #" .. tostring(ev.from or ev.unit)
				if ev.type == "Hit" then
					local v, a = BC.GetUnit(tonumber(ev.to) or -1), BC.GetUnit(tonumber(ev.from) or -1)
					local rip = (tonumber(ev.absorbed) or 0) > 0 and not ev.miss and v ~= nil and v.Kind ~= "Boss" and drawable(v) and v.Model ~= nil
						and not (a and a.Kind == "Boss" and not v.Mine)
					-- (re-review M8) a zone / burn tick within RIPPLE_TICK_GAP 0.75 s of the victim's last ripple may skip it
					local skipOk = rip and (ev.zone or ev.burn) and lastRip[v.Id] ~= nil and os.clock() - lastRip[v.Id] < 0.75 + 0.05
					if #ripples ~= (rip and 1 or 0) and not (skipOk and #ripples == 0) then
						bad[#bad + 1] = fmt("%s (absorbed %s): %d shield ripples, %d expected", label, tostring(ev.absorbed), #ripples, rip and 1 or 0)
					elseif rip and #ripples == 1 then
						-- (re-review I3) the ripple lands with the hit: a ranged shot's at its DueAt + ImpactLate (<= FX_LATE_MAX 0.3)
						local c, h = ripples[1], got[1]
						local due = h and type(h.DueAt) == "number" and h.DueAt + ((h.Result == true and math.min(tonumber(h.Late) or 0, 0.3)) or 0) or nil
						if c.From ~= v.Id or type(c.DueAt) ~= "number" or (due and math.abs(due - c.DueAt) > 1e-6) then
							bad[#bad + 1] = fmt("%s: the shield ripple from %s at %s (the hit's play at %s, late %s)", label, tostring(c.From), tostring(c.DueAt), tostring(h and h.DueAt), tostring(h and h.Late))
						end
						lastRip[v.Id] = c.DueAt
						seen.ShieldHit = (seen.ShieldHit or 0) + 1
					end
				elseif #ripples > 0 then
					bad[#bad + 1] = label .. ": a shield ripple on a " .. ev.type
				end
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
		-- 2a) Task 10 review I1 (Ruling 17: "a hexagon bubble around each ally, rippling when hit"): after a Shield, every
		--     hit it absorbs plays ShieldHit on the victim at the hit's time (on arrival, the same DueAt as the hit's own
		--     play), in the look of the pet whose shield it is; 1 emitter, no light. A plain hit (nothing absorbed) does not
		--     (re-review M10 iii: the caster is my bench helper, never the fighter itself: a look check against the
		--     victim's own look would pass for nothing)
		if T.check(helper ~= nil and helper ~= fighter and BC.GetUnit(helper) ~= nil, "shield ripple: my bench helper is in the battle (the shield's caster)") then
			local caster = helper
			pulse(1.8)
			KC.toClient("BattleState", "Events", { { type = "Special", unit = caster, kind = "Shield", name = "Test Shield", x = f.X, z = f.Z, shields = { fighter } } }, id)
			pulse(0.6)
			local function hitCalls(ev)
				pulse(0.8)
				local n0 = #calls
				KC.toClient("BattleState", "Events", { ev }, id)
				local got, rip = {}, nil
				for i = n0 + 1, #calls do
					got[#got + 1] = calls[i]
					if calls[i].Attack == "ShieldHit" then
						rip = calls[i]
					end
				end
				local fx = nil
				for _, e in ipairs(AF._Live()) do
					if e.Recipe and e.Recipe.Attack == "ShieldHit" then
						fx = e
					end
				end
				return got, rip, fx
			end
			local look = Cat.Unit(infos[caster] or {})
			local got1, rip1, fx1 = hitCalls({ type = "Hit", from = boss, to = fighter, dmg = 2, absorbed = 6 })
			local hurt1 = nil
			for _, c in ipairs(got1) do
				if c.Attack == "Hurt" then
					hurt1 = c
				end
			end
			T.check(rip1 and rip1.Result == true and rip1.From == fighter and hurt1 and type(rip1.DueAt) == "number" and rip1.DueAt == hurt1.DueAt
				and rip1.DueAt > rip1.At and #got1 == 2,
				"shield ripple: a boss hit my fighter's shield absorbs plays ShieldHit on the fighter (on arrival, the hit's DueAt) beside its Hurt",
				fmt("%d plays, ripple %s from %s due %s (hurt due %s)", #got1, tostring(rip1 and rip1.Result), tostring(rip1 and rip1.From), tostring(rip1 and rip1.DueAt), tostring(hurt1 and hurt1.DueAt)))
			T.check(rip1 and rip1.Element == look.Element and rip1.Rarity == look.Rarity, "shield ripple: in the look of the pet whose Shield it is (its element and rarity)",
				fmt("%s %s, want %s %s", tostring(rip1 and rip1.Element), tostring(rip1 and rip1.Rarity), tostring(look.Element), tostring(look.Rarity)))
			T.check(fx1 and fx1.Emitters <= 1 and fx1.Lights == 0 and fx1.Recipe.Core.Key == "vfx_shell", "shield ripple: the hex shell + one emitter, no light",
				fx1 and fmt("%d emitters, %d lights, core %s", fx1.Emitters, fx1.Lights, tostring(fx1.Recipe.Core.Key)) or "no live ShieldHit")
			local got2, rip2 = hitCalls({ type = "Hit", from = boss, to = fighter, dmg = 5 })
			T.check(rip2 == nil and #got2 == 1 and got2[1].Attack == "Hurt", "shield ripple: a plain hit (nothing absorbed) plays only its Hurt", fmt("%d plays", #got2))
			-- a special's damage the shield absorbs ripples too (its own effect is the special's)
			local got3, rip3 = hitCalls({ type = "Hit", from = boss, to = fighter, dmg = 0, absorbed = 9, special = "Blast" })
			T.check(rip3 and rip3.Result == true and #got3 == 1, "shield ripple: a special's hit the shield absorbs ripples it (one play)", fmt("%d plays", #got3))
			-- (re-review I4 + M10 ii) a Mythic caster's shield: my fighter's ripple in the Mythic look, through the
			-- battle's real hooks (counted): no camera punch, no screen glow. The helper's info is refreshed to Mythic by
			-- a Spawn of the same unit (Units.Add: the info and its look), then put back
			do
				local info0 = infos[caster]
				local mythic = copyOf(info0 or {})
				mythic.rarity = "Mythic"
				KC.toClient("BattleState", "Events", { { type = "Spawn", units = { mythic } } }, id)
				pulse(0.3)
				local punchN, glowN = 0, 0
				local realPunch, realGlow = AF.Hooks.Punch, AF.Hooks.ScreenGlow
				AF.Hooks.Punch = function(...)
					punchN = punchN + 1
					return realPunch and realPunch(...)
				end
				AF.Hooks.ScreenGlow = function(...)
					glowN = glowN + 1
					return realGlow and realGlow(...)
				end
				local got4, rip4 = hitCalls({ type = "Hit", from = boss, to = fighter, dmg = 0, absorbed = 9, special = "Blast" })
				pulse(0.8)
				AF.Hooks.Punch, AF.Hooks.ScreenGlow = realPunch, realGlow
				KC.toClient("BattleState", "Events", { { type = "Spawn", units = { info0 } } }, id)
				pulse(0.3)
				T.check(info0 ~= nil and rip4 and rip4.Result == true and rip4.Rarity == "Mythic" and rip4.Mine == true and #got4 == 1 and punchN == 0 and glowN == 0,
					"shield ripple: a Mythic caster's shield ripples my fighter in the Mythic look with no camera punch and no screen glow (the battle's hooks, counted)",
					fmt("ripple %s %s mine %s, %d plays, %d punches, %d glows", tostring(rip4 and rip4.Result), tostring(rip4 and rip4.Rarity), tostring(rip4 and rip4.Mine), #got4, punchN, glowN))
			end
			-- (re-review I3) a ranged pet's shot the shield absorbs: the ripple lands WITH the shot (its DueAt + the
			-- shot's ctx.ImpactLate: MinTravel keeps its flight past the event), like the BLOCK number and the Hurt pose
			local shooter = nil
			for uid, info in pairs(infos) do
				local g = BC.GetUnit(uid)
				if info.ranged == true and info.kind ~= "Boss" and uid ~= fighter and drawable(g) and g.Model ~= nil and (not shooter or uid < shooter) then
					shooter = uid
				end
			end
			if T.check(shooter ~= nil, "shield ripple: a ranged pet (not my fighter) is on the floor") then
				pulse(1)
				KC.toClient("BattleState", "Events", { { type = "Special", unit = caster, kind = "Shield", name = "Test Shield", x = f.X, z = f.Z, shields = { fighter } } }, id)
				pulse(0.6)
				local got5, rip5 = hitCalls({ type = "Hit", from = shooter, to = fighter, dmg = 1, absorbed = 6 })
				local shot = nil
				for _, c in ipairs(got5) do
					if c.Attack == "Ranged" then
						shot = c
					end
				end
				local want = shot and type(shot.DueAt) == "number" and type(shot.Late) == "number" and shot.DueAt + math.min(shot.Late, 0.3) or nil
				T.check(shot and shot.Result == true and shot.Late > 0.05 and rip5 and rip5.Result == true and want and math.abs(rip5.DueAt - want) < 1e-6,
					"shield ripple: a ranged shot's absorbed hit ripples when the shot lands (its DueAt + ctx.ImpactLate), not before",
					fmt("shot due %s late %s, ripple due %s", tostring(shot and shot.DueAt), tostring(shot and shot.Late), tostring(rip5 and rip5.DueAt)))
			end
			-- (re-review M8) a Linger zone's 0.5 s ticks on a shielded pet ripple every other tick (RIPPLE_TICK_GAP 0.75 s
			-- after the last ripple); a hit from an attacker right after a tick still ripples
			pulse(1)
			local tickRips = {}
			for i = 1, 3 do
				local n0 = #calls
				KC.toClient("BattleState", "Events", { { type = "Hit", from = boss, to = fighter, dmg = 0, absorbed = 2, zone = true, kind = "Storm" } }, id)
				for j = n0 + 1, #calls do
					if calls[j].Attack == "ShieldHit" then
						tickRips[i] = calls[j]
					end
				end
				pulse(0.5)
			end
			local n7 = #calls
			KC.toClient("BattleState", "Events", { { type = "Hit", from = boss, to = fighter, dmg = 0, absorbed = 2, special = "Blast" } }, id)
			local hitRip = calls[n7 + 1] and calls[n7 + 1].Attack == "ShieldHit"
			T.check(tickRips[1] ~= nil and tickRips[2] == nil and tickRips[3] ~= nil and hitRip,
				"shield ripple: zone ticks 0.5 s apart ripple every other tick; an attacker's hit always ripples",
				fmt("ticks %s / %s / %s, hit %s", tostring(tickRips[1] ~= nil), tostring(tickRips[2] ~= nil), tostring(tickRips[3] ~= nil), tostring(hitRip)))
			-- (re-review M9) once the shield is over, a ripple (a shield the client never saw cast: a rejoin snapshot) is in
			-- the victim's own look, not the last caster's
			pulse(7)
			local own, casterLook = Cat.Unit(infos[fighter] or {}), Cat.Unit(infos[caster] or {})
			local _, rip6 = hitCalls({ type = "Hit", from = boss, to = fighter, dmg = 0, absorbed = 3, special = "Blast" })
			T.check((own.Element ~= casterLook.Element or own.Rarity ~= casterLook.Rarity) and rip6 and rip6.Element == own.Element and rip6.Rarity == own.Rarity,
				"shield ripple: after the caster's shield ends, a ripple takes the victim's own look (not a stale caster's)",
				fmt("%s %s, own %s %s, caster %s %s", tostring(rip6 and rip6.Element), tostring(rip6 and rip6.Rarity), tostring(own.Element), tostring(own.Rarity),
					tostring(casterLook.Element), tostring(casterLook.Rarity)))
			pulse(1)
		end
		-- 2a') Task 11: Eclipse Nova's battle dim (own pet only; back on end, KO and teardown: hook-ins below)
		local E11 = eclipseBattle({ BC = BC, AF = AF, KC = KC, id = id, pulse = pulse, helper = helper, kid = rec.Team77 and rec.Team77.Fighter,
			boss = boss, f = f, bo = bo, info = function(uid)
				return infos[uid]
			end })
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
		local koDim = E11 and koUnit == helper and E11.beforeKo() -- (Task 11 hook-in: the caster's KO ends its battle dim)
		local p0 = BC.GetStats().FxParts
		local n0 = #calls
		KC.toClient("BattleState", "Events", { { type = "KO", unit = koUnit } }, id)
		pulse(0.3)
		T.check(#calls == n0 + 1 and calls[n0 + 1].Attack == "Ko" and calls[n0 + 1].Result == true and BC.GetStats().FxParts - p0 <= 0,
			"handlers: a KO plays AttackFx Ko (no cube poof)", fmt("%d plays, %d new parts", #calls - n0, BC.GetStats().FxParts - p0))
		if koDim then
			E11.afterKo()
		end

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
		local strayOn = E11 and E11.stray() -- (Task 11 hook-in: the effects' teardown cuts a battle dim)
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
		if strayOn then
			E11.torn("the End's grace (Atk.ClearAll)")
		end
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

----------------------------------------------------------------------------------------------------------------------
-- client_p7vfx_storm (Task 11 fix round 2, I1): a Storm special in a real battle lands on the enemies in its ZONE.
-- BattleSim's Storm is a Specials.Storm.Radius zone at the aimed target and its Special event names only that target;
-- BattleController's Atk.Special gathers the living enemies in the zone. A recorded Duel (my Obsidian Phoenix against
-- 5 standing NPC frogs: the aimed one, one beside it, one in only by its body (centre past the radius, edge inside),
-- one just out, one far off): the sim's own events go to the client and the
-- Obsidian effect's targets must be exactly the enemies the sim's zone ticks hit: several (#T > 1: the sweep and the
-- spread rain are reached) when they stand together, one (#T == 1) when the aimed enemy stands alone
----------------------------------------------------------------------------------------------------------------------
S.client_p7vfx_storm = guarded("client_p7vfx_storm", function()
	local BC = moduleAt(ROOTS.client .. "/Controllers/BattleController")
	local AF = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
	local Sim = moduleAt(ROOTS.shared .. "/BattleSim")
	if not T.check(BC ~= nil and AF ~= nil and Sim ~= nil and KC ~= nil, "Storm zone (battle): BattleController, AttackFx, BattleSim load") then
		return
	end
	local out0, err0 = #Mock.Output, #Mock.Errors
	local me = LocalPlayer.UserId
	local frogs = {}
	for i = 1, 5 do
		frogs[i] = { PetId = "puddle_frog", Key = "puddle_frog", Level = 20, Tier = "Normal", Slot = i }
	end
	local sim, why = Sim.new({ Mode = "Duel", Seed = 23, Id = "p7vfx_storm", Zone = { X = 60, Z = 60 }, TimeLimit = 300,
		Teams = { { Owner = me, Side = 1, Pets = { { PetId = "obsidian_phoenix", Key = "obsidian_phoenix", Level = 20, Tier = "Normal", Slot = 1 } } },
			{ Owner = "frogs", Side = 2, Npc = true, Pets = frogs } } })
	if not T.check(sim ~= nil, "Storm zone (battle): a Duel of my Obsidian Phoenix against 5 NPC frogs", tostring(why)) then
		return
	end
	-- the frogs stand still (moveSpeed 0) and nobody falls. Round the aimed one at (6, 0), r = BattleCatalog's Storm
	-- Radius: one 3 studs off, one r + 0.6 x its body radius off (in by its edge: inCircle), one r + its radius + 1.5
	-- off (out); one far off at (24, 14). My phoenix stands in the zone too (the zone hits only enemies)
	local BCat = moduleAt(ROOTS.shared .. "/BattleCatalog")
	local r = BCat and BCat.Specials and BCat.Specials.Storm and tonumber(BCat.Specials.Storm.Radius) or nil
	local mine, foes = nil, {}
	for _, u in ipairs(sim.units) do
		u.maxHp, u.hp = 1e7, 1e7
		if u.side == 1 then
			mine = u
			u.x, u.z = 3, 3 -- (inside the zone itself: an ally there is never a target)
		else
			foes[#foes + 1] = u
		end
	end
	if not T.check(r ~= nil and mine ~= nil and #foes == 5, "Storm zone (battle): my fighter + 5 frogs on the floor (and the Storm Radius in BattleCatalog)", fmt("%d frogs, radius %s", #foes, tostring(r))) then
		return
	end
	local rad = foes[1].radius
	local spots = { { 6, 0 }, { 8, 2.2 }, { 6, r + 0.6 * rad }, { 6, -(r + rad + 1.5) }, { 24, 14 } }
	for i, u in ipairs(foes) do
		u.x, u.z, u.moveSpeed = spots[i][1], spots[i][2], 0
	end
	local id = "p7vfx_storm_1"
	local start = sim:Describe()
	start.BattleId = id
	start.Zone = { CFrame = CFrame.new(0, 200, 0), Size = Vector3.new(start.Zone.X, 30, start.Zone.Z), X = start.Zone.X, Z = start.Zone.Z }
	start.Names = { [tostring(me)] = LocalPlayer.Name }
	start.Side, start.Spectator, start.T = 1, false, sim:Time()
	local team = sim:TeamOf(me)
	if team then
		start.Team = { Fighter = team.Fighter, Bench = team.Bench, Lives = team.Lives, Speed = team.Speed,
			Cooldowns = { Element = team.Cooldowns.Element, Dash = team.Cooldowns.Dash, Swap = team.Cooldowns.Swap, Buff = {} } }
	end
	LocalPlayer:SetAttribute("InBattle", id)
	AF.ClearAll()
	AF.SetQuality("High")
	KC.toClient("BattleState", "Start", start, id)
	local last = {}
	-- one server step: its events and its wire snapshot to the client, then the frames of that step
	local function step(dt)
		local evs = sim:Step(dt)
		if #evs > 0 then
			KC.toClient("BattleState", "Events", evs, id)
		end
		local snap = sim:SnapshotDelta(last)
		snap.BattleId = id
		KC.toClient("BattleState", "Snapshot", snap, id)
		for _ = 1, math.max(1, math.floor(dt * 30 + 0.5)) do
			Mock.Step(1 / 30)
		end
		return evs
	end
	for _ = 1, 10 do
		step(0.1)
	end
	-- cast at `aim`: the sim's own Special / Zone / Hit events; -> the enemies the zone's ticks hit (the first 0.7 s),
	-- the Obsidian effect's target units, the Special event
	local function storm(aim)
		mine.meter, mine.castUntil, mine.nextAttack = 100, 0, 0
		sim:Command(me, "Target", aim.id)
		local okC, whyC = sim:Command(me, "Special")
		local hit, special = {}, nil
		local evs = step(0.1)
		local fx = nil
		for _, e in ipairs(AF._Live()) do
			if e.Unit == mine.id and e.Recipe.Signature == "obsidian_phoenix" then
				fx = e
			end
		end
		for _ = 1, 7 do
			for _, ev in ipairs(evs) do
				if ev.type == "Special" and ev.unit == mine.id then
					special = ev
				elseif ev.type == "Hit" and ev.zone and ev.from == mine.id then
					hit[tonumber(ev.to)] = true
				end
			end
			evs = step(0.1)
		end
		local units = {}
		for _, side in ipairs(fx and fx.Targets or {}) do
			units[#units + 1] = side.Unit
		end
		-- (the zone runs out, the meter refills by hand for the next cast)
		for _ = 1, 45 do
			step(0.1)
		end
		return okC and special and hit, units, special, fx, whyC
	end
	local function same(hit, units)
		local n = 0
		for _ in pairs(hit or {}) do
			n = n + 1
		end
		if n ~= #units then
			return false
		end
		for _, u in ipairs(units) do
			if not (hit or {})[u] then
				return false
			end
		end
		return true
	end
	local function list(set)
		local o = {}
		for k in pairs(set or {}) do
			o[#o + 1] = tostring(k)
		end
		table.sort(o)
		return table.concat(o, ",")
	end
	local hitA, unitsA, evA, fxA, whyA = storm(foes[1])
	T.check(evA ~= nil and evA.targets == nil and fxA ~= nil and fxA.Targets[1] and fxA.Targets[1].Unit == foes[1].id,
		"Storm zone (battle): the sim's Storm event names only the aimed frog; my Obsidian's effect plays, aimed at it first",
		fmt("cast %s, event targets %s, effect %s", tostring(whyA or "ok"), tostring(evA and evA.targets), tostring(fxA ~= nil)))
	T.check(fxA ~= nil and #fxA.T > 1 and #fxA.T == 3 and same(hitA, unitsA),
		"Storm zone (battle): 3 frogs in the zone (one by its edge), one just out: the effect lands on exactly the 3 the zone hits (#eff.T > 1: the sweep and the spread rain)",
		fmt("#T %s, effect units {%s}, the zone hit {%s}", tostring(fxA and #fxA.T), table.concat(unitsA, ","), list(hitA)))
	local hitB, unitsB, evB, fxB, whyB = storm(foes[5])
	T.check(evB ~= nil and fxB ~= nil and #fxB.T == 1 and unitsB[1] == foes[5].id and same(hitB, unitsB),
		"Storm zone (battle): the far frog alone in the zone: the effect lands on it alone (#eff.T == 1), as the zone hits",
		fmt("cast %s, #T %s, effect units {%s}, the zone hit {%s}", tostring(whyB or "ok"), tostring(fxB and #fxB.T), table.concat(unitsB, ","), list(hitB)))
	KC.toClient("BattleState", "End", { BattleId = id, Mode = "Duel", Outcome = "Win", Won = true, Spectator = false, Reason = "Wipe",
		Rewards = { Tokens = 0, Gems = 0, Xp = 0, Trophies = 0, LevelUps = 0 } }, id)
	LocalPlayer:SetAttribute("InBattle", nil)
	KC.advance(15)
	local warned = nil
	for i = out0 + 1, #Mock.Output do
		local o = Mock.Output[i]
		if o.kind == "warn" and (o.text:find("BattleController", 1, true) or o.text:find("AttackFx", 1, true)) then
			warned = o.text
			break
		end
	end
	T.check(warned == nil and #Mock.Errors == err0 and AF.Stats().Live == 0, "client_p7vfx_storm: no errors or BattleController / AttackFx warnings, nothing left live", tostring(warned))
	AF.SetQuality(nil)
	KC.flushErrors("client_p7vfx_storm")
end)

----------------------------------------------------------------------------------------------------------------------
-- client_p7vfx_precharge (Task 11b, the Special pre-charge, player option C): real BattleSim Duels fed to the client
-- the way BattleService sends them (events + wire snapshots per 0.1 s step), the press through BattleController.Command.
--   A) my press, its Special event ~0.33 s / ~0.23 s later: the charge shows at once (glow + motes, rim, inhale, Cast);
--      the real effect takes it over: the same glow kit (no restart), its start backdated to the press, >= 0.25 s of
--      charge before the release, the impact exactly on the DueAt the old path gives (its hit's number then), the same
--      inhale token (retimed). B) refused (Order rejected) and C) no event within PRESS_WAIT: it shatters (shards,
--      Recoil, the "interrupted" hook), no Special effect, no impact.
--   D) my pet's Special with no press: the impact lands late (DueAt + ImpactLate, 0 < late <= LATE_MAX); the damage
--      numbers, HP-bar drops, flinches (flashes) and the KO of its targets wait for the impact, a plain hit on the same
--      target in the same window does not. E) a bot's Special: late too, others' cues (inhale mine = false).
--   F) last gasp: a bot KO'd in its own late charge: its effect lands, its KO plays after the impact, not drawn down
--      before. G) a Storm: the zone tick due before the impact is held, a later one plays on time.
--   H) the /fx preview (DevPetShow) plays the full charge once (no prediction, no double charge).
--   (fix round 1) I) a double press: one prediction, one inhale; the rim handed on at the cap; my inhale beats others'.
--   J) two late Specials on one fighter: the first impact releases only its share; the auto-swap waits for the KO.
--   K) a press whose fighter is KO'd fades quietly (the Ko pose holds). L) the killing blow + the sim's End in one
--   batch: the KO! at the late impact, ClearAll after it. Battle 4: an auto-swap waits for a KO held by a flying shot.
-- BattleSim / BattleService are untouched by Task 11b (git diff in the report); their own scenarios guard them.
----------------------------------------------------------------------------------------------------------------------
local PRE_LATE_MAX, PRE_WAIT, PRE_MIN = 0.35, 0.7, 0.25
local FRAME = 1 / 30

-- a Duel: my `myPet` (or a list: the fighter + its bench) against NPC `bots`; -> sim, start payload
local function preDuel(Sim, me, myPet, bots, id, seed)
	local foes, pets = {}, {}
	for i, p in ipairs(bots) do
		foes[i] = { PetId = p, Key = p, Level = 20, Tier = "Normal", Slot = i }
	end
	for i, p in ipairs(type(myPet) == "table" and myPet or { myPet }) do
		pets[i] = { PetId = p, Key = p, Level = 20, Tier = "Normal", Slot = i }
	end
	local sim, why = Sim.new({ Mode = "Duel", Seed = seed or 41, Id = id, Zone = { X = 60, Z = 60 }, TimeLimit = 900,
		Teams = { { Owner = me, Side = 1, Pets = pets },
			{ Owner = "bots", Side = 2, Npc = true, Pets = foes } } })
	if not sim then
		return nil, why
	end
	local start = sim:Describe()
	start.BattleId = id
	start.Zone = { CFrame = CFrame.new(0, 200, 0), Size = Vector3.new(start.Zone.X, 30, start.Zone.Z), X = start.Zone.X, Z = start.Zone.Z }
	start.Names = { [tostring(me)] = LocalPlayer.Name }
	start.Side, start.Spectator, start.T = 1, false, sim:Time()
	local team = sim:TeamOf(me)
	if team then
		start.Team = { Fighter = team.Fighter, Bench = team.Bench, Lives = team.Lives, Speed = team.Speed,
			Cooldowns = { Element = team.Cooldowns.Element, Dash = team.Cooldowns.Dash, Swap = team.Cooldowns.Swap, Buff = {} } }
	end
	return sim, start
end

-- an item of an effect by kind + layer id
local function itemOf(eff, kind, id)
	for _, it in ipairs(eff and eff.Items or {}) do
		if it.Kind == kind and it.Layer and it.Layer.Id == id then
			return it
		end
	end
	return nil
end

-- the live effect of `uid` whose recipe is `attack` (not a prediction)
local function liveOf(AF, uid, attack)
	local found = nil
	for _, e in ipairs(AF._Live()) do
		if e.Unit == uid and e.Recipe.Attack == attack and not e.Pre and not e.Retired then
			found = e
		end
	end
	return found
end

S.client_p7vfx_precharge = guarded("client_p7vfx_precharge", function()
	local BC = moduleAt(ROOTS.client .. "/Controllers/BattleController")
	local AF = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
	local Sim = moduleAt(ROOTS.shared .. "/BattleSim")
	local Config = moduleAt(ROOTS.shared .. "/Config")
	if not T.check(BC ~= nil and AF ~= nil and Sim ~= nil and KC ~= nil and BC._Fx ~= nil and type(BC._Unit) == "function"
		and type(AF.Precharge) == "function" and type(AF.Shatter) == "function", "pre-charge: BattleController (+ test hooks), AttackFx (Precharge / Shatter), BattleSim load") then
		return
	end
	local out0, err0 = #Mock.Output, #Mock.Errors
	local me = LocalPlayer.UserId
	local downState = (Sim.States and Sim.States.Down) or 5
	-- the logs: every AttackFx play, the battle's world numbers / flashes, the charge hooks
	local plays, numbers, flashes, inhales, hushes, shatters = {}, {}, {}, {}, {}, {}
	local realPlay, realNumber, realFlash = AF.Play, BC._Fx.Number, BC._Fx.Flash
	AF.Play = function(ctx)
		local r = realPlay(ctx)
		plays[#plays + 1] = { ctx = ctx, r = r, at = os.clock() }
		return r
	end
	BC._Fx.Number = function(adornee, height, text, ...)
		numbers[#numbers + 1] = { adornee = adornee, text = tostring(text), at = os.clock() }
		return realNumber(adornee, height, text, ...)
	end
	BC._Fx.Flash = function(u, ...)
		flashes[#flashes + 1] = { id = u and u.id, at = os.clock() }
		return realFlash(u, ...)
	end
	BC.FxHooks()
	local hk = AF.Hooks
	local realInhale, realHush, realShatter = hk.Inhale, hk.Hush, hk.Shatter
	hk.Inhale = function(seconds, token, mine)
		inhales[#inhales + 1] = { seconds = seconds, token = token, mine = mine, at = os.clock() }
		return realInhale and realInhale(seconds, token, mine)
	end
	hk.Hush = function(token)
		hushes[#hushes + 1] = { token = token, at = os.clock() }
		return realHush and realHush(token)
	end
	hk.Shatter = function(mine, unit)
		shatters[#shatters + 1] = { mine = mine, unit = unit, at = os.clock() }
		return realShatter and realShatter(mine, unit)
	end
	-- (the inhale's sound: SoundFx's "Whoosh" given an id for this test; the project ships them empty)
	local audio = Config and Config.Audio and Config.Audio.Sfx
	local oldWhoosh = audio and audio.Whoosh
	if audio then
		audio.Whoosh = "rbxassetid://1"
	end
	local function numberAt(uid, since, pred)
		local u = BC._Unit(uid)
		for _, n in ipairs(numbers) do
			if n.at >= since and u and n.adornee == u.root and (not pred or pred(n.text)) then
				return n.at, n.text
			end
		end
		return nil
	end
	local function flashTimes(uid, since)
		local out = {}
		for _, f in ipairs(flashes) do
			if f.id == uid and f.at >= since then
				out[#out + 1] = f.at
			end
		end
		return out
	end
	local function playOf(uid, attack, since, pre)
		for _, p in ipairs(plays) do
			local c = p.ctx
			if p.at >= since and c.Attack == attack and c.From and c.From.Unit == uid and (c.Pre == true) == (pre == true) then
				return p
			end
		end
		return nil
	end
	local AF_SetQ = AF.SetQuality
	local ok, err = pcall(function()
		------------------------------------------------------------------------------------------------------------------
		-- battle 1: my Puddle Frog (Blast) against three NPC frogs
		------------------------------------------------------------------------------------------------------------------
		local sim, start = preDuel(Sim, me, "puddle_frog", { "puddle_frog", "puddle_frog", "puddle_frog" }, "p7vfx_pre_1")
		if not T.check(sim ~= nil, "pre-charge: a Duel of my Blast pet against 3 NPC frogs", tostring(start)) then
			return
		end
		local mine, bots = nil, {}
		for _, u in ipairs(sim.units) do
			u.maxHp, u.hp = 1e6, 1e6
			u.nextAttack = 1e9 -- (no plain attacks: every hit here is a special's, or one the test sends)
			if u.side == 1 then
				mine = u
			else
				bots[#bots + 1] = u
				u.moveSpeed = 0
			end
		end
		if not T.check(mine ~= nil and #bots == 3, "pre-charge: my fighter + 3 frogs") then
			return
		end
		mine.x, mine.z = 0, 0
		bots[1].x, bots[1].z = 5, 0
		bots[2].x, bots[2].z = 5, 3
		bots[3].x, bots[3].z = -16, 12
		local id = start.BattleId
		LocalPlayer:SetAttribute("InBattle", id)
		AF.ClearAll()
		AF.SetQuality("High")
		KC.toClient("BattleState", "Start", start, id)
		local last = {}
		local extra = nil -- events the test adds to the next step's batch (after the sim's own)
		local watch = nil -- per frame
		local function step(dt)
			local evs = sim:Step(dt or 0.1)
			local list = {}
			for _, e in ipairs(evs) do
				list[#list + 1] = e
			end
			for _, e in ipairs(extra or {}) do
				list[#list + 1] = e
			end
			extra = nil
			local sent = os.clock()
			if #list > 0 then
				KC.toClient("BattleState", "Events", list, id)
			end
			local snap = sim:SnapshotDelta(last)
			snap.BattleId = id
			KC.toClient("BattleState", "Snapshot", snap, id)
			for _ = 1, 3 do
				Mock.Step(FRAME)
				if watch then
					watch()
				end
			end
			return evs, sent
		end
		local function steps(n)
			for _ = 1, n do
				step(0.1)
			end
		end
		steps(10)
		local function full()
			mine.meter, mine.castUntil = 100, 0
			if mine.state == Sim.States.Casting then
				mine.state = Sim.States.Idle
			end
		end
		sim:Command(me, "Target", bots[1].id)
		-- A) my press, the event `wait` steps later
		local function press(wait, label)
			full()
			steps(3)
			local P = os.clock()
			local nP = #plays
			local sent = BC.Command("Special")
			local pre = AF.Precharging(mine.id)
			local glow = itemOf(pre, "Emitter", "Charge")
			local glowKit = glow and glow.Kit
			local rim = itemOf(pre, "Rim", "Rim")
			local pose = AF.Pose(mine.id)
			Mock.Step(FRAME)
			local inh = inhales[#inhales]
			local low = nil
			local SSA = game:GetService("SoundService"):FindFirstChild("NimbusSounds")
			for _, s in ipairs(SSA and SSA:GetChildren() or {}) do
				if s.Name:find("Sfx_Whoosh", 1, true) and math.abs(s.PlaybackSpeed - 0.75) < 1e-6 then
					low = s
				end
			end
			T.check(low ~= nil, "pre-charge A" .. label .. ": the inhale sound starts low (PlaybackSpeed 0.75) to rise under the charge")
			T.check(sent and pre ~= nil and glowKit ~= nil and rim ~= nil and pose ~= nil and pose.Name == "Cast" and inh ~= nil and inh.mine == true and inh.at >= P,
				"pre-charge A" .. label .. ": my press shows the charge at once: the glow + motes, the rim light, the Cast pose, the inhale (mine)",
				fmt("sent %s, pre %s, glow %s, rim %s, pose %s, inhale %s", tostring(sent), tostring(pre ~= nil), tostring(glowKit ~= nil), tostring(rim ~= nil),
					tostring(pose and pose.Name), tostring(inh and inh.mine)))
			T.check(#plays == nP + 1 and plays[nP + 1].ctx.Pre == true and plays[nP + 1].ctx.DueAt == nil,
				"pre-charge A" .. label .. ": the prediction is a charge only (no DueAt, no impact)")
			-- the server hears the press `wait` steps later (the round trip)
			steps(wait - 1)
			T.check(AF.Precharging(mine.id) == pre and pre.Items[glow.Index] == glow and glow.Kit == glowKit,
				"pre-charge A" .. label .. ": the predicted charge holds while it waits for the event")
			local okC = sim:Command(me, "Special")
			local _, arrived = step(0.1)
			local p = playOf(mine.id, "Special", arrived, false)
			local eff = liveOf(AF, mine.id, "Special")
			local c = p and p.ctx
			local due = c and c.DueAt
			local g2 = itemOf(eff, "Emitter", "Charge")
			local inh2 = inhales[#inhales]
			T.check(okC and p ~= nil and p.r == true and c.Precharged == true and eff ~= nil and math.abs(eff.Start - P) < 1e-6 and AF.Precharging(mine.id) == nil,
				"pre-charge A" .. label .. ": its Special event takes the charge over: the real effect starts at the press (backdated)",
				fmt("event %.2f s after the press, played %s, precharged %s, start %.3f vs press %.3f", (arrived or 0) - P, tostring(p and p.r), tostring(c and c.Precharged),
					eff and eff.Start or -1, P))
			T.check(g2 ~= nil and g2.Kit == glowKit and g2.Adopted == true,
				"pre-charge A" .. label .. ": the glow did not restart (the real effect's charge glow IS the prediction's emitter, its particles live on)")
			T.check(eff ~= nil and type(due) == "number" and math.abs(eff.Start + eff.Times.Impact - due) < 1e-6 and (c.ImpactLate or 0) == 0,
				"pre-charge A" .. label .. ": the impact is exactly on the DueAt the old path gives (no delay)",
				eff and due and fmt("impact %.4f, DueAt %.4f, late %s", eff.Start + eff.Times.Impact, due, tostring(c.ImpactLate)) or "no effect")
			T.check(eff ~= nil and eff.Times.Release >= PRE_MIN - 1e-6, "pre-charge A" .. label .. ": >= 0.25 s of charge is seen before the release",
				eff and fmt("%.3f s", eff.Times.Release) or "no effect")
			-- the inhale carries on: no new one starts; the same token is retimed to the real release, or (a release that is
			-- already due) hushed right then
			local fresh, retimed, hushed = false, false, false
			for _, x in ipairs(inhales) do
				if x.at >= P and inh and x.token ~= inh.token then
					fresh = true
				elseif x.at >= arrived and inh and x.token == inh.token then
					retimed = true
				end
			end
			for _, h in ipairs(hushes) do
				if inh and h.token == inh.token and h.at >= arrived and eff and h.at <= eff.Start + eff.Times.Release + FRAME + 1e-3 then
					hushed = true
				end
			end
			T.check(inh ~= nil and not fresh and (retimed or hushed),
				"pre-charge A" .. label .. ": the inhale carries on (the same token: retimed to the real release, or hushed at it), never restarts",
				fmt("fresh %s, retimed %s, hushed %s, inh2 %s", tostring(fresh), tostring(retimed), tostring(hushed), tostring(inh2 and inh2.token)))
			-- the special's hit is not held: its number shows at DueAt
			local sp = nil
			for _ = 1, 6 do
				step(0.1)
				sp = sp or numberAt(bots[1].id, arrived)
			end
			T.check(sp ~= nil and due ~= nil and sp >= due - FRAME - 1e-3 and sp <= due + 0.1,
				"pre-charge A" .. label .. ": its hit's damage number shows at the impact (DueAt), not held",
				sp and due and fmt("%.3f s after DueAt", sp - due) or "no number")
			steps(10)
			return eff
		end
		-- (the event's arrival: one frame + (wait - 1) steps after the press: ~0.33 s / ~0.23 s)
		press(4, " (event ~0.33 s)")
		press(3, " (event ~0.23 s)")

		-- B) refused: the server's Order echo `rejected`
		local function broken(label, P, nP)
			local sh = shatters[#shatters]
			local e = nil
			for _, x in ipairs(AF._Live()) do
				if x.Unit == mine.id and x.Retired and itemOf(x, "Emitter", "Shards") then
					e = x
				end
			end
			local pose = AF.Pose(mine.id)
			T.check(sh ~= nil and sh.at >= P and sh.mine == true and AF.Precharging(mine.id) == nil and e ~= nil and pose ~= nil and pose.Name == "Recoil",
				"pre-charge " .. label .. ": the charge shatters (shards fly, the pet rears back, the 'interrupted' sound hook)",
				fmt("shatter %s, prediction left %s, shards %s, pose %s", tostring(sh ~= nil and sh.at >= P), tostring(AF.Precharging(mine.id) ~= nil), tostring(e ~= nil),
					tostring(pose and pose.Name)))
			steps(10)
			T.check(playOf(mine.id, "Special", P, false) == nil and liveOf(AF, mine.id, "Special") == nil,
				"pre-charge " .. label .. ": no Special effect, no impact")
			return sh
		end
		full()
		steps(3)
		local PB, nB = os.clock(), #plays
		BC.Command("Special")
		step(0.1)
		mine.meter = 0 -- (the server's view: not full after all)
		local okB, whyB = sim:Command(me, "Special")
		step(0.1)
		local shB = broken("B (refused)", PB, nB)
		T.check(not okB and shB ~= nil and shB.at - PB < 0.35, "pre-charge B: the refusal arrives before PRESS_WAIT and breaks it at once", fmt("%s, %.2f s", tostring(whyB), shB and shB.at - PB or -1))
		-- C) no event within PRESS_WAIT
		full()
		steps(3)
		local PC = os.clock()
		BC.Command("Special")
		local heldAt = nil
		watch = function()
			if AF.Precharging(mine.id) ~= nil then
				heldAt = os.clock()
			end
		end
		steps(9)
		watch = nil
		mine.meter = 0
		local shC = broken("C (no event)", PC, #plays)
		T.check(shC ~= nil and heldAt ~= nil and heldAt - PC >= PRE_WAIT - FRAME - 1e-3 and shC.at - PC >= PRE_WAIT - 1e-3 and shC.at - PC <= PRE_WAIT + FRAME + 1e-3,
			"pre-charge C: it waits PRESS_WAIT (0.7 s) for the event, then shatters", fmt("held until %.2f s, shattered at %.2f s", (heldAt or PC) - PC, (shC and shC.at or PC) - PC))
		-- C') Low quality: the prediction keeps the LowKeep budget (<= 1 emitter + the shards = 2), no rim Highlight
		AF.SetQuality("Low")
		full()
		steps(3)
		local PL = os.clock()
		BC.Command("Special")
		local preL = AF.Precharging(mine.id)
		local emL, rimL = preL and preL.Emitters, preL and itemOf(preL, "Rim", "Rim")
		steps(9)
		mine.meter = 0
		local shL = nil
		for _, x in ipairs(AF._Live()) do
			if x.Unit == mine.id and x.Retired and itemOf(x, "Emitter", "Shards") then
				shL = x
			end
		end
		T.check(preL ~= nil and emL ~= nil and emL <= 1 and rimL == nil and shL ~= nil and shL.Emitters <= 2 and shatters[#shatters].at >= PL,
			"pre-charge C': at Low the prediction keeps <= 1 emitter (+ the shards: 2, the Low cap), no rim Highlight, and still shatters",
			fmt("emitters %s, rim %s, shattered %s", tostring(emL), tostring(rimL ~= nil), tostring(shL ~= nil)))
		steps(10)
		AF.SetQuality("High")

		-- D) my pet's Special with NO press: late impact; its hits / KO held, a plain hit on the same target not
		bots[1].hp = 5 -- (the Blast knocks it out)
		local hp2 = BC._Unit(bots[2].id).hp
		full()
		steps(3)
		sim:Command(me, "Target", bots[1].id)
		sim:Command(me, "Special")
		extra = { { type = "Hit", from = mine.id, to = bots[2].id, dmg = 3 } } -- a plain hit on bot 2 in the same window
		local dropAt, plainDropAt, downAt = nil, nil, nil
		local maxRims, capsOk = 0, true
		watch = function()
			local u2, u1 = BC._Unit(bots[2].id), BC._Unit(bots[1].id)
			-- (fix round 1, M2) the plain hit's 3 shows on the bar on time; the special's drop waits for the impact
			if not plainDropAt and u2 and u2.hp < hp2 - 2.5 then
				plainDropAt = os.clock()
			end
			if not dropAt and u2 and u2.hp < hp2 - 3.5 then
				dropAt = os.clock()
			end
			if not downAt and u1 and (u1.state == downState or u1.hp <= 0) then
				downAt = os.clock()
			end
			local s = AF.Stats()
			maxRims = math.max(maxRims, s.Rims or 0)
			for _, e in ipairs(AF._Live()) do
				if e.Emitters > 6 or e.Beams > 4 or e.Lights > 3 then
					capsOk = false
				end
			end
		end
		local evsD, A = step(0.1)
		local p = playOf(mine.id, "Special", A, false)
		local c = p and p.ctx
		local eff = liveOf(AF, mine.id, "Special")
		local I = eff and (eff.Start + eff.Times.Impact)
		local spDmg = {}
		for _, e in ipairs(evsD) do
			if e.type == "Hit" and e.special and e.from == mine.id then
				spDmg[e.to] = tostring(math.floor((e.dmg or 0) + 0.5))
			end
		end
		T.check(p ~= nil and p.r == true and c.LateMax == PRE_LATE_MAX and not c.Precharged and eff ~= nil and type(c.ImpactLate) == "number" and c.ImpactLate > 0.1
			and c.ImpactLate <= PRE_LATE_MAX + 1e-6 and math.abs(I - (c.DueAt + c.ImpactLate)) < 1e-6,
			"pre-charge D: my pet's Special with no press lands late: impact = DueAt + late, 0 < late <= LATE_MAX (its charge given back)",
			c and fmt("late %s, impact - DueAt %.3f", tostring(c.ImpactLate), (I or 0) - (c.DueAt or 0)) or "no play")
		T.check(eff ~= nil and eff.Times.Release >= 0.3 and itemOf(eff, "Rim", "Rim") ~= nil and itemOf(eff, "Emitter", "Charge") ~= nil,
			"pre-charge D: its charge is seen (>= 0.3 s) with the rim light and the charge glow", eff and fmt("charge %.2f s", eff.Times.Release) or "")
		for _ = 1, 8 do
			step(0.1)
		end
		watch = nil
		local plainAt = numberAt(bots[2].id, A, function(t)
			return t == "3"
		end)
		local spAt = spDmg[bots[2].id] and numberAt(bots[2].id, A, function(t)
			return t:find(spDmg[bots[2].id], 1, true) ~= nil and t ~= "3"
		end)
		local koAt = numberAt(bots[1].id, A, function(t)
			return t == "KO!"
		end)
		local f2 = flashTimes(bots[2].id, A)
		T.check(I ~= nil and spAt ~= nil and spAt >= I - FRAME - 1e-3 and spAt <= I + 0.12,
			"pre-charge D: the special's damage number waits for the impact", spAt and I and fmt("%.3f s after the impact", spAt - I) or "no number")
		T.check(I ~= nil and plainAt ~= nil and plainAt < I - 0.1, "pre-charge D: a plain hit on the same target in the same window is NOT held",
			plainAt and I and fmt("%.3f s before the impact", I - plainAt) or "no number")
		T.check(I ~= nil and dropAt ~= nil and dropAt >= I - FRAME - 1e-3 and dropAt <= I + 0.15,
			"pre-charge D: the target's drawn HP does not drop before the impact (the snapshots already carry it), then drops",
			dropAt and I and fmt("dropped %.3f s after the impact", dropAt - I) or "never dropped")
		T.check(I ~= nil and plainDropAt ~= nil and plainDropAt < I - 0.1, "pre-charge D: the plain hit's HP drop (3) shows on time while the special's waits (fix round 1, M2)",
			plainDropAt and I and fmt("%.3f s before the impact", I - plainDropAt) or "never")
		local early, atImpact = false, false
		for _, t in ipairs(f2) do
			if t < I - 0.1 then
				early = true
			elseif t >= I - FRAME - 1e-3 and t <= I + 0.12 then
				atImpact = true
			end
		end
		T.check(early and atImpact, "pre-charge D: the special's flinch (hit flash) waits for the impact; the plain hit's flinches on time",
			fmt("%d flashes on bot 2", #f2))
		T.check(I ~= nil and koAt ~= nil and koAt >= I - FRAME - 1e-3 and downAt ~= nil and downAt >= I - FRAME - 1e-3,
			"pre-charge D: the KO of its target waits for the impact (KO! and drawn down not before)",
			fmt("KO! %s, down %s (s after the impact)", koAt and fmt("%.3f", koAt - I) or "never", downAt and fmt("%.3f", downAt - I) or "never"))
		T.check(maxRims >= 1 and maxRims <= AF.MAX_RIMS and capsOk, "pre-charge D: the caps hold (rims <= MAX_RIMS, emitters <= 6, beams <= 4, lights <= 3)",
			fmt("rims %d", maxRims))
		-- the inhale's sound (SoundFx "Whoosh", an existing Sfx name): risen to the top pitch at the release, faded out
		local SS = game:GetService("SoundService")
		local folderS = SS:FindFirstChild("NimbusSounds")
		local whoosh, risen = 0, false
		for _, s in ipairs(folderS and folderS:GetChildren() or {}) do
			if s.Name:find("Sfx_Whoosh", 1, true) then
				whoosh = whoosh + 1
				if math.abs(s.PlaybackSpeed - 1.35) < 1e-6 and s.Volume == 0 then
					risen = true
				end
			end
		end
		T.check(whoosh >= 1 and risen, "pre-charge D: the inhale is SoundFx's Whoosh, its pitch risen to 1.35 by the release, then faded out",
			fmt("%d whoosh sounds", whoosh))

		-- E) a bot's Special (another unit's): late too; its inhale is an other's (mine = false)
		local function botCast(u)
			u.meter, u.autoCastAt = 100, sim:Time()
			for _ = 1, 25 do
				local evs, sent = step(0.1)
				for _, e in ipairs(evs) do
					if e.type == "Special" and e.unit == u.id then
						return e, sent, evs
					end
				end
			end
			return nil
		end
		local nI = #inhales
		local evE, AE, evsE = botCast(bots[2])
		local pE = evE and playOf(bots[2].id, "Special", AE, false)
		local cE = pE and pE.ctx
		local myDmg = nil
		for _, e in ipairs(evsE or {}) do
			if e.type == "Hit" and e.special and e.from == bots[2].id and e.to == mine.id then
				myDmg = tostring(math.floor((e.dmg or 0) + 0.5))
			end
		end
		local effE = liveOf(AF, bots[2].id, "Special")
		local IE = effE and (effE.Start + effE.Times.Impact)
		steps(6)
		local myAt = myDmg and numberAt(mine.id, AE or 0, function(t)
			return t:find(myDmg, 1, true) ~= nil
		end)
		local othersInhale = false
		for i = nI + 1, #inhales do
			if inhales[i].mine == false then
				othersInhale = true
			end
		end
		T.check(cE ~= nil and pE.r == true and cE.Mine == false and (cE.ImpactLate or 0) > 0.1 and othersInhale,
			"pre-charge E: a bot's Special lands late too, with the charge cues (an other's inhale)", cE and fmt("late %s", tostring(cE.ImpactLate)) or "no bot special")
		T.check(IE ~= nil and myAt ~= nil and myAt >= IE - FRAME - 1e-3 and myAt <= IE + 0.12, "pre-charge E: its hit on my pet shows at its (late) impact",
			myAt and IE and fmt("%.3f s after the impact", myAt - IE) or "no number")

		-- F) last gasp: bot 3 is knocked out in its own late charge (by my pressed Special: no late of its own)
		bots[3].hp = 5
		steps(10)
		full()
		sim:Command(me, "Target", bots[3].id)
		steps(2)
		BC.Command("Special")
		local evF, AF1 = botCast(bots[3])
		local effF = liveOf(AF, bots[3].id, "Special")
		local IF = effF and (effF.Start + effF.Times.Impact)
		local downF, liveAtImpact, gaspHp = nil, nil, nil
		watch = function()
			local u3 = BC._Unit(bots[3].id)
			if not downF and u3 and (u3.state == downState or u3.hp <= 0) then
				downF = os.clock()
			end
			if IF and gaspHp == nil and u3 and os.clock() >= IF - 2 * FRAME then
				gaspHp = u3.hp -- (just before its impact: the killing hit has played, the KO waits)
			end
			if IF and liveAtImpact == nil and os.clock() >= IF + 0.02 then
				liveAtImpact = false
				for _, e in ipairs(AF._Live()) do
					if e == effF then
						liveAtImpact = true
					end
				end
			end
		end
		sim:Command(me, "Special")
		local _, A2 = step(0.1)
		steps(8)
		watch = nil
		local koF = numberAt(bots[3].id, A2 or 0, function(t)
			return t == "KO!"
		end)
		T.check(evF ~= nil and effF ~= nil and AF1 ~= nil and A2 ~= nil and IF ~= nil and A2 < IF - 0.15,
			"pre-charge F: (setup) bot 3's late Special, then my Special knocks it out inside its charge", IF and A2 and fmt("KO event %.2f s before its impact", IF - A2) or "")
		T.check(liveAtImpact == true, "pre-charge F: last gasp: the KO'd caster's effect still lands (live past its impact)")
		T.check(IF ~= nil and koF ~= nil and koF >= IF + 0.05 - FRAME - 1e-3 and downF ~= nil and downF >= IF - 1e-3,
			"pre-charge F: last gasp: the caster's KO (KO! / drawn down) plays just after its impact",
			fmt("KO! %s, down %s (s after the impact)", koF and IF and fmt("%.3f", koF - IF) or "never", downF and IF and fmt("%.3f", downF - IF) or "never"))
		T.check(gaspHp ~= nil and gaspHp > 0 and gaspHp <= 1.5, "pre-charge F: last gasp: the killing hit's drop shows (the caster's bar at 1 until its KO, fix round 1 M1)",
			tostring(gaspHp))

		KC.toClient("BattleState", "End", { BattleId = id, Mode = "Duel", Outcome = "Win", Won = true, Spectator = false, Reason = "Wipe",
			Rewards = { Tokens = 0, Gems = 0, Xp = 0, Trophies = 0, LevelUps = 0 } }, id)
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.advance(15)

		------------------------------------------------------------------------------------------------------------------
		-- battle 2 (G): my Obsidian Phoenix's Storm with no press: the zone tick due before the late impact is held
		------------------------------------------------------------------------------------------------------------------
		local sim2, start2 = preDuel(Sim, me, "obsidian_phoenix", { "puddle_frog" }, "p7vfx_pre_2", 43)
		if not T.check(sim2 ~= nil, "pre-charge G: a Duel of my Obsidian Phoenix (Storm) against a frog", tostring(start2)) then
			return
		end
		sim = sim2
		mine, bots = nil, {}
		for _, u in ipairs(sim.units) do
			u.maxHp, u.hp = 1e6, 1e6
			u.nextAttack = 1e9
			if u.side == 1 then
				mine = u
				u.x, u.z = 0, 0
			else
				bots[#bots + 1] = u
				u.x, u.z, u.moveSpeed = 7, 0, 0
			end
		end
		id = start2.BattleId
		last = {}
		LocalPlayer:SetAttribute("InBattle", id)
		KC.toClient("BattleState", "Start", start2, id)
		steps(10)
		full()
		sim:Command(me, "Target", bots[1].id)
		sim:Command(me, "Special")
		step(0.1)
		local zone = sim.zones and sim.zones[#sim.zones]
		local effG = liveOf(AF, mine.id, "Special")
		local IG = effG and (effG.Start + effG.Times.Impact)
		local okG = zone ~= nil and effG ~= nil
		if zone then
			zone.nextTick = sim:Time() -- (the first tick comes in the next step: before the late impact)
		end
		local ticks = {}
		for _ = 1, 10 do
			local evs, sent = step(0.1)
			for _, e in ipairs(evs) do
				if e.type == "Hit" and e.zone and e.from == mine.id then
					ticks[#ticks + 1] = { sent = sent, dmg = tostring(math.floor((e.dmg or 0) + 0.5)) }
				end
			end
		end
		local function tickNumber(k)
			local tk = ticks[k]
			return tk and numberAt(bots[1].id, tk.sent, function(t)
				return t:find(tk.dmg, 1, true) ~= nil
			end)
		end
		local t1, t2 = tickNumber(1), tickNumber(2)
		T.check(okG and #ticks >= 2 and ticks[1].sent < IG - 0.1 and ticks[2].sent > IG, "pre-charge G: (setup) a tick arrives before the late impact, the next after it",
			fmt("%d ticks", #ticks))
		T.check(t1 ~= nil and IG ~= nil and t1 >= IG - FRAME - 1e-3 and t1 <= IG + 0.12, "pre-charge G: the Storm tick due before its impact waits for it",
			t1 and IG and fmt("%.3f s after the impact", t1 - IG) or "no number")
		T.check(t2 ~= nil and ticks[2] ~= nil and t2 - ticks[2].sent <= 0.12 + 0.1 + FRAME, "pre-charge G: a later tick plays on time (not held)",
			t2 and fmt("%.3f s after it arrived", t2 - ticks[2].sent) or "no number")
		KC.toClient("BattleState", "End", { BattleId = id, Mode = "Duel", Outcome = "Win", Won = true, Spectator = false, Reason = "Wipe",
			Rewards = { Tokens = 0, Gems = 0, Xp = 0, Trophies = 0, LevelUps = 0 } }, id)
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.advance(15)

		-- (fix round 1) battle 3 runs in its own closure: the scenario's function is near Luau's 200-locals limit
		local function battle3()
			------------------------------------------------------------------------------------------------------------------
			-- battle 3 (fix round 1): my three frogs (a fighter + two on the bench: auto-swaps) against two NPC frogs
			--   I) a double press within PRESS_WAIT: one prediction, one inhale (M4)
			--   J) two bots' late Specials on my fighter, the second kills it: the first impact releases only its own share of
			--      the hold (I1); the server's auto-swap ("GO!") waits for the held KO (I2)
			--   K) press, then my fighter is KO'd before any Special: the Ko pose holds, no shatter (I3)
			--   L) the battle's killing blow is a bot's late Special with the sim's End in the same batch: the KO! at the late
			--      impact, after the End, and the grace's ClearAll after it (T1 e)
			------------------------------------------------------------------------------------------------------------------
			local sim3, start3 = preDuel(Sim, me, { "puddle_frog", "puddle_frog", "puddle_frog" }, { "puddle_frog", "puddle_frog" }, "p7vfx_pre_3", 47)
			if not T.check(sim3 ~= nil, "pre-charge battle 3: a Duel of my 3 frogs against 2 NPC frogs", tostring(start3)) then
				return
			end
			sim = sim3
			bots = {}
			local myTeam = sim.teamByOwner[me]
			for _, u in ipairs(sim.units) do
				u.maxHp, u.hp = 1e6, 1e6
				u.nextAttack = 1e9
				if u.side ~= 1 then
					bots[#bots + 1] = u
					u.moveSpeed = 0
				end
			end
			mine = myTeam and myTeam.fighter
			if not T.check(mine ~= nil and #bots == 2 and #myTeam.units == 3, "pre-charge battle 3: my fighter + 2 benched, 2 frogs") then
				return
			end
			mine.x, mine.z = 0, 0
			bots[1].x, bots[1].z = 5, 0
			bots[2].x, bots[2].z = 5, 3
			id = start3.BattleId
			last = {}
			LocalPlayer:SetAttribute("InBattle", id)
			KC.toClient("BattleState", "Start", start3, id)
			steps(10)
			sim:Command(me, "Target", bots[1].id)

			-- I) a double press (past CMD_GAP, inside PRESS_WAIT): the second press starts no second prediction / inhale
			full()
			steps(3)
			local PI, nPI, nInhI = os.clock(), #plays, #inhales
			local rimsCap = AF.MAX_RIMS
			AF.MAX_RIMS = 1 -- (M3: the cap full with the prediction's own rim)
			BC.Command("Special")
			local preI = AF.Precharging(mine.id)
			steps(3)
			local sent2 = BC.Command("Special")
			local predsI, tokI, nTokI = 0, {}, 0
			for i = nPI + 1, #plays do
				if plays[i].ctx.Pre == true then
					predsI = predsI + 1
				end
			end
			for i = nInhI + 1, #inhales do
				local x = inhales[i]
				if x.mine and x.at >= PI and not tokI[x.token] then
					tokI[x.token] = true
					nTokI = nTokI + 1
				end
			end
			T.check(preI ~= nil and sent2 == true and predsI == 1 and AF.Precharging(mine.id) == preI and nTokI == 1,
				"pre-charge I: a second press while the first waits starts no second prediction and no second inhale (fix round 1, M4)",
				fmt("second press sent %s, predictions %d, same prediction %s, inhale tokens %d", tostring(sent2), predsI, tostring(AF.Precharging(mine.id) == preI), nTokI))
			sim:Command(me, "Special") -- (the server answers the first press)
			local _, AI = step(0.1)
			local pI = playOf(mine.id, "Special", AI, false)
			local effI = liveOf(AF, mine.id, "Special")
			local rimI = itemOf(effI, "Rim", "Rim")
			AF.MAX_RIMS = rimsCap
			T.check(pI ~= nil and pI.r == true and pI.ctx.Precharged == true and AF.Precharging(mine.id) == nil,
				"pre-charge I: its Special takes the one prediction over")
			T.check(rimI ~= nil and rimI.Adopted == true, "pre-charge I: at the rim cap the real Special still takes the prediction's rim over (fix round 1, M3)",
				fmt("rim %s, adopted %s", tostring(rimI ~= nil), tostring(rimI and rimI.Adopted)))
			steps(10)
			-- M7: my inhale is never refused for others' (two others' rising: the oldest gives way)
			local okO1 = realInhale(1, "p7vfx_other_1", false)
			local okO2 = realInhale(1, "p7vfx_other_2", false)
			local okMine = realInhale(1, "p7vfx_mine_1", true)
			for _, tk in ipairs({ "p7vfx_other_1", "p7vfx_other_2", "p7vfx_mine_1" }) do
				realHush(tk)
			end
			T.check(okO1 == true and okO2 == true and okMine == true, "pre-charge I: my inhale plays even with INHALE_MAX others' rising (fix round 1, M7)",
				fmt("others %s / %s, mine %s", tostring(okO1), tostring(okO2), tostring(okMine)))

			-- J) two bots' late Specials on my fighter; the second kills it (I1), then the auto-swap (I2)
			bots[1].meter, bots[2].meter = 0, 0
			steps(5)
			local f1 = mine
			local hp0 = BC._Unit(f1.id) and BC._Unit(f1.id).hp
			local samples = {}
			watch = function()
				local u = BC._Unit(f1.id)
				samples[#samples + 1] = { at = os.clock(), hp = u and u.hp, down = u ~= nil and (u.state == downState or u.hp <= 0) }
			end
			local evA, AA, evsA = botCast(bots[1])
			local dmgA = nil
			for _, e in ipairs(evsA or {}) do
				if e.type == "Hit" and e.special and e.from == bots[1].id and e.to == f1.id and not e.miss then
					dmgA = (dmgA or 0) + math.floor((e.dmg or 0) + 0.5)
				end
			end
			f1.hp = 1 -- (the sim: bot 2's Special knocks it out)
			local evB, AB, evsB = botCast(bots[2])
			local koIn, swapTo = false, nil
			for _, e in ipairs(evsB or {}) do
				if e.type == "KO" and e.unit == f1.id then
					koIn = true
				elseif e.type == "Swap" and e.out == f1.id and e.auto then
					swapTo = e["in"]
				end
			end
			local effA, effB = liveOf(AF, bots[1].id, "Special"), liveOf(AF, bots[2].id, "Special")
			local IA = effA and (effA.Start + effA.Times.Impact)
			local IB = effB and (effB.Start + effB.Times.Impact)
			steps(10)
			watch = nil
			T.check(evA ~= nil and evB ~= nil and dmgA ~= nil and hp0 ~= nil and koIn and swapTo ~= nil and IA ~= nil and IB ~= nil and AA ~= nil and AB ~= nil
				and AB < IA - 0.05 and IB > IA + 0.05,
				"pre-charge J: (setup) two bots' late Specials on my fighter, the second arrives before the first lands and kills it (KO + auto-swap)",
				fmt("A %s, B %s, dmgA %s, KO %s, swap %s, B arrives %.2f s before A lands, B lands %.2f s after A", tostring(evA ~= nil), tostring(evB ~= nil),
					tostring(dmgA), tostring(koIn), tostring(swapTo), (IA or 0) - (AB or 0), (IB or 0) - (IA or 0)))
			local between, shareOk, downJ = 0, true, nil
			for _, s in ipairs(samples) do
				if IA and IB and s.at > IA + FRAME + 1e-3 and s.at < IB - FRAME - 1e-3 then
					between = between + 1
					if s.down or not s.hp or math.abs(s.hp - (hp0 - (dmgA or 0))) > 1.5 then
						shareOk = false
					end
				end
				if s.down and not downJ then
					downJ = s.at
				end
			end
			T.check(between >= 1 and shareOk,
				"pre-charge J: the first special's impact drops my fighter's drawn HP by its own hit only and keeps it up: the second special's hold stays (fix round 1, I1)",
				fmt("%d frames between the impacts, HP held at hp0 - dmgA: %s", between, tostring(shareOk)))
			local koJ = numberAt(f1.id, AB or 0, function(t)
				return t == "KO!"
			end)
			T.check(IB ~= nil and downJ ~= nil and downJ >= IB - FRAME - 1e-3 and koJ ~= nil and koJ >= IB - FRAME - 1e-3,
				"pre-charge J: my fighter is drawn down and its KO! pops only at the second (killing) impact",
				fmt("down %s, KO! %s (s after the 2nd impact)", downJ and IB and fmt("%.3f", downJ - IB) or "never", koJ and IB and fmt("%.3f", koJ - IB) or "never"))
			local goJ = swapTo and numberAt(swapTo, AB or 0, function(t)
				return t == "GO!"
			end)
			T.check(goJ ~= nil and koJ ~= nil and goJ >= koJ - 1e-3,
				"pre-charge J: the server's auto-swap (the incoming pet's GO!) waits for the held KO! (fix round 1, I2)",
				fmt("GO! %s s after the KO!", goJ and koJ and fmt("%.3f", goJ - koJ) or "-"))

			-- K) press, then my (new) fighter is KO'd by a bot's late Special before any Special of mine: no shatter on it
			mine = myTeam.fighter
			bots[1].meter, bots[2].meter = 0, 0
			steps(15)
			full()
			steps(3)
			local PK, nShK = os.clock(), #shatters
			BC.Command("Special")
			local preK = AF.Precharging(mine.id)
			mine.hp = 1 -- (the sim never hears the press: the bot's Special knocks it out first)
			local evK = botCast(bots[1])
			local koKin = false
			for _ = 1, 8 do
				local evs = step(0.1)
				for _, e in ipairs(evs) do
					if e.type == "KO" and e.unit == mine.id then
						koKin = true
					end
				end
			end
			local poseK = AF.Pose(mine.id)
			local koKnum = numberAt(mine.id, PK, function(t)
				return t == "KO!"
			end)
			T.check(preK ~= nil and evK ~= nil and koKnum ~= nil and os.clock() - PK > PRE_WAIT + FRAME,
				"pre-charge K: (setup) my press predicts, then a bot's Special knocks my fighter out, PRESS_WAIT passes", fmt("KO in a later batch %s", tostring(koKin)))
			T.check(#shatters == nShK and AF.Precharging(mine.id) == nil and poseK ~= nil and poseK.Name == "Ko",
				"pre-charge K: a press whose fighter went down fades quietly: no shards / 'interrupted' sound, the Ko pose holds (fix round 1, I3)",
				fmt("shatters %d, pose %s", #shatters - nShK, tostring(poseK and poseK.Name)))
			-- (AttackFx's half of I3: a loud Shatter on a unit lying in its Ko keeps the Ko: K.PRIO refuses the Recoil)
			local mK = unitModel(workspace, "PreKoPet", Vector3.new(0, 400, 0))
			local sideK = { Unit = 990001, Model = mK }
			local tK = os.clock()
			local okPK = AF.Precharge({ Kind = "Blast", From = sideK, Element = "Water", Rarity = "Common", Stage = 0, Mine = true, Seconds = PRE_WAIT, Now = tK })
			AF.Play({ Attack = "Ko", From = sideK, Element = "Water", Rarity = "Common", Stage = 0, Mine = true, Now = tK })
			Mock.Step(FRAME)
			AF.Shatter(990001, os.clock(), false)
			Mock.Step(FRAME)
			local poseK2 = AF.Pose(990001)
			T.check(okPK == true and poseK2 ~= nil and poseK2.Name == "Ko", "pre-charge K: AttackFx.Shatter on a unit in its Ko pose keeps the Ko (no Recoil over it)",
				fmt("prediction %s, pose %s", tostring(okPK), tostring(poseK2 and poseK2.Name)))
			AF.Cancel(990001)
			mK:Destroy()

			-- L) my last pet is knocked out by a bot's late Special: the sim's End comes in that batch, BattleService's End right
			--    after it
			mine = myTeam.fighter
			bots[1].meter, bots[2].meter = 0, 0
			steps(15)
			mine.hp = 1
			local clears = {}
			local realClear = AF.ClearAll
			AF.ClearAll = function(...)
				clears[#clears + 1] = os.clock()
				return realClear(...)
			end
			local okL, errL = pcall(function()
				local evL, AL, evsL = botCast(bots[1])
				local endIn, koLin = false, false
				for _, e in ipairs(evsL or {}) do
					if e.type == "End" then
						endIn = true
					elseif e.type == "KO" and e.unit == mine.id then
						koLin = true
					end
				end
				local effL = liveOf(AF, bots[1].id, "Special")
				local IL = effL and (effL.Start + effL.Times.Impact)
				KC.toClient("BattleState", "End", { BattleId = id, Mode = "Duel", Outcome = "Lose", Won = false, Spectator = false, Reason = "Wipe",
					Rewards = { Tokens = 0, Gems = 0, Xp = 0, Trophies = 0, LevelUps = 0 } }, id)
				for _ = 1, 45 do
					Mock.Step(FRAME)
				end
				local koL = numberAt(mine.id, AL or 0, function(t)
					return t == "KO!"
				end)
				T.check(evL ~= nil and endIn and koLin and IL ~= nil and AL ~= nil and IL > AL + 0.3,
					"pre-charge L: (setup) the killing blow is a bot's late Special, the sim's End in the same batch",
					fmt("End %s, KO %s, impact %.2f s after the arrival", tostring(endIn), tostring(koLin), (IL or 0) - (AL or 0)))
				T.check(koL ~= nil and IL ~= nil and koL >= IL - FRAME - 1e-3 and koL <= IL + 0.15,
					"pre-charge L: the End is not held, the KO! still pops at the late impact (the End's grace lets it land)",
					fmt("KO! %s", koL and IL and fmt("%.3f s after the impact", koL - IL) or "never"))
				T.check(#clears >= 1 and koL ~= nil and clears[1] >= koL - 1e-3, "pre-charge L: the End grace's ClearAll comes after the KO!",
					fmt("ClearAll %s", clears[1] and koL and fmt("%.3f s after the KO!", clears[1] - koL) or "never"))
			end)
			AF.ClearAll = realClear
			if not okL then
				error(errL, 0)
			end
			LocalPlayer:SetAttribute("InBattle", nil)
			KC.advance(15)
		end
		battle3()

		------------------------------------------------------------------------------------------------------------------
		-- battle 4 (fix round 1, I2 on the older ranged-shot hold): a ranged frog's shot still flying knocks my fighter out;
		-- the KO waits for the shot (Net.Hold), the server's auto-swap ("GO!") waits with it. The Hit / KO / Swap are the
		-- sim's shapes, sent in one batch (the test ends the battle right after)
		------------------------------------------------------------------------------------------------------------------
		local function battle4()
			local sim4, start4 = preDuel(Sim, me, { "puddle_frog", "puddle_frog" }, { "puddle_frog" }, "p7vfx_pre_4", 53)
			if not T.check(sim4 ~= nil, "pre-charge battle 4: a Duel of my 2 frogs against a ranged frog", tostring(start4)) then
				return
			end
			sim = sim4
			local team4 = sim.teamByOwner[me]
			local f4 = team4 and team4.fighter
			local in4, bot4 = nil, nil
			for _, u in ipairs(sim.units) do
				u.maxHp, u.hp = 1e6, 1e6
				u.nextAttack = 1e9
				if u.side ~= 1 then
					bot4 = u
					u.moveSpeed = 0
				elseif u ~= f4 and not in4 then
					in4 = u
				end
			end
			if not T.check(f4 ~= nil and in4 ~= nil and bot4 ~= nil, "pre-charge battle 4: my fighter + 1 benched, 1 frog") then
				return
			end
			f4.x, f4.z = 0, 0
			bot4.x, bot4.z = 24, 0
			for _, info in ipairs(start4.Units or {}) do
				if info.id == bot4.id then
					info.ranged = true -- (the client draws it as a ranged pet: its plain hit is a shot with a flight)
				end
			end
			id = start4.BattleId
			last = {}
			LocalPlayer:SetAttribute("InBattle", id)
			KC.toClient("BattleState", "Start", start4, id)
			steps(10)
			extra = {
				{ type = "Hit", from = bot4.id, to = f4.id, dmg = 7 },
				{ type = "KO", unit = f4.id, by = bot4.id },
				{ type = "Swap", owner = me, out = f4.id, ["in"] = in4.id, auto = true },
			}
			local _, A4 = step(0.1)
			local shot = playOf(bot4.id, "Ranged", A4, false)
			local late4 = shot and tonumber(shot.ctx.ImpactLate) or 0
			steps(8)
			local ko4 = numberAt(f4.id, A4 or 0, function(t)
				return t == "KO!"
			end)
			local go4 = numberAt(in4.id, A4 or 0, function(t)
				return t == "GO!"
			end)
			T.check(shot ~= nil and late4 > 0.05 and ko4 ~= nil and ko4 - A4 >= 0.12 + late4 - FRAME - 1e-3,
				"pre-charge battle 4: (setup) the shot lands late, the KO! waits for it", fmt("late %.3f, KO! %.3f s after the arrival", late4, (ko4 or A4) - A4))
			T.check(go4 ~= nil and ko4 ~= nil and go4 >= ko4 - 1e-3, "pre-charge battle 4: the auto-swap's GO! waits for a KO held by a flying shot too (fix round 1, I2)",
				fmt("GO! %s s after the KO!", go4 and ko4 and fmt("%.3f", go4 - ko4) or "-"))
			KC.toClient("BattleState", "End", { BattleId = id, Mode = "Duel", Outcome = "Lose", Won = false, Spectator = false, Reason = "Wipe",
				Rewards = { Tokens = 0, Gems = 0, Xp = 0, Trophies = 0, LevelUps = 0 } }, id)
			LocalPlayer:SetAttribute("InBattle", nil)
			KC.advance(15)
		end
		battle4()

		------------------------------------------------------------------------------------------------------------------
		-- H) the /fx preview (DevPetShow): the full authored charge, once (no prediction, no late, no double charge)
		------------------------------------------------------------------------------------------------------------------
		local nH = #plays
		KC.toClient("DevPetShow", "Fx", { Element = "Flame", Attack = "Special", Kind = "Blast", Rarity = "Legendary", Stage = 0 })
		Mock.Step(FRAME)
		local specials, preH = 0, 0
		local pH = nil
		for i = nH + 1, #plays do
			local cc = plays[i].ctx
			if cc.Attack == "Special" then
				if cc.Pre then
					preH = preH + 1
				else
					specials = specials + 1
					pH = plays[i]
				end
			end
		end
		local effH = pH and liveOf(AF, pH.ctx.From and pH.ctx.From.Unit, "Special")
		local Cat = moduleAt(ROOTS.shared .. "/AttackFxCatalog")
		local rH = Cat and Cat.Resolve({ Element = "Flame", Attack = "Special", Kind = "Blast", Rarity = "Legendary", Stage = 0, Mine = true })
		T.check(specials == 1 and preH == 0 and pH.r == true and pH.ctx.DueAt == nil and pH.ctx.LateMax == nil and not pH.ctx.Precharged and effH ~= nil and rH ~= nil
			and math.abs(effH.Times.Release - rH.Beats.Charge) < 1e-6,
			"pre-charge H: /fx plays the Special once with its full authored charge (no prediction, no late, not double-charged)",
			fmt("%d plays (%d predictions), charge %s vs %s", specials, preH, effH and fmt("%.2f", effH.Times.Release) or "-", rH and tostring(rH.Beats.Charge) or "-"))
		KC.toClient("DevPetShow", "Clear", {})
		KC.advance(3)
	end)
	AF.Play, BC._Fx.Number, BC._Fx.Flash = realPlay, realNumber, realFlash
	hk.Inhale, hk.Hush, hk.Shatter = realInhale, realHush, realShatter
	if audio then
		audio.Whoosh = oldWhoosh
	end
	AF_SetQ(nil)
	if not ok then
		T.fail("client_p7vfx_precharge raised an error", tostring(err))
	end
	local warned = nil
	for i = out0 + 1, #Mock.Output do
		local o = Mock.Output[i]
		if o.kind == "warn" and (o.text:find("BattleController", 1, true) or o.text:find("AttackFx", 1, true)) then
			warned = o.text
			break
		end
	end
	T.check(warned == nil and #Mock.Errors == err0 and AF.Stats().Live == 0, "client_p7vfx_precharge: no errors or BattleController / AttackFx warnings, nothing left live", tostring(warned))
	KC.flushErrors("client_p7vfx_precharge")
end)

return S
