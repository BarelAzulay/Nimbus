-- smoke_afx_linger.lua: lingering visuals and the camera kick (docs/superpowers/specs/2026-11-01-attack-fx-design.md "Lasting longer",
-- "Claude's calls"; plan Task 3), loaded by tools/smoke.py in the client world:
--   client_afx_linger     Afterglow by band (none on support casts, reactions and misses); past TailAt only the Linger layers are left,
--                         dim, still and fading; others' pets get it x Density, Graphics Low none; a signature's dim and the inhale still
--                         end with the beats
--   client_afx_tails      a tail never blocks a new effect (it is in neither count of the budget); MAX_TAILS, the oldest makes room; a
--                         sustained fight reuses its ground discs (the pool does not churn) and keeps them for the next
--   client_afx_kick       every own attack kicks by kind and band, basic hits at most once per BasicGap, a Special is never swallowed;
--                         others' pets, reactions, support casts and misses do not kick; through BattleController: Shake off leaves
--                         Humanoid.CameraOffset alone, Shake on moves it for about 0.15 s; a small kick never cuts a stronger shake
--   client_afx_zone_tail  a pet Storm's zone holds a dim disc ZONE_TAIL past its seconds, its cloud gone; a boss zone ends on time
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local abs = math.abs
local fmt = string.format

local function near(a, b, tol)
	return type(a) == "number" and type(b) == "number" and abs(a - b) <= (tol or 1e-6)
end

local S = {}
local KC = _G.KC
local LocalPlayer = game:GetService("Players").LocalPlayer

local function moduleAt(path)
	local inst = Mock.GetPath(path)
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	return ok and type(result) == "table" and result or nil
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
			p.Size = Vector3.new(2, 2, 2)
			p.Anchored = true
			p.Parent = m
			return m
		end,
	}
end

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

-- the engine on a fake clock: a caster, a target, play(over) -> eff, run(seconds, each)
local function rig(name, startAt)
	local Fx = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
	local Cat = moduleAt(ROOTS.shared .. "/AttackFxCatalog")
	Fx.ClearAll()
	Fx._Deps({ MeshLibrary = fakeMeshLibrary() })
	Fx.SetQuality("High")
	local holder = Instance.new("Folder")
	holder.Name = name
	holder.Parent = workspace
	local R = { Fx = Fx, Cat = Cat, holder = holder, clock = startAt, errs0 = Fx.Stats().Errors } -- (Errors is the engine's running count: client_p7vfx_engine raises one on purpose)
	R.A = unitModel(holder, "A", Vector3.new(0, 2, 0))
	R.B = unitModel(holder, "B", Vector3.new(0, 2, -12))
	function R.ctx(over)
		local c = { Attack = "Melee", Element = "Flame", Rarity = "Secret", Stage = 0, Mine = true,
			From = { Unit = 1, Model = R.A }, To = { Unit = 2, Model = R.B }, Ground = 0.5, Now = R.clock }
		for k, v in pairs(over or {}) do
			c[k] = v
		end
		return c
	end
	function R.play(over)
		if not Fx.Play(R.ctx(over)) then
			return nil
		end
		return Fx._Live()[#Fx._Live()]
	end
	function R.run(seconds, each)
		for _ = 1, math.ceil(seconds * 30 - 1e-9) do
			R.clock = R.clock + 1 / 30
			Fx.Update(R.clock)
			if each then
				each()
			end
		end
	end
	-- runs until `rel` seconds into the effect
	function R.runTo(eff, rel, each)
		while R.clock - eff.Start < rel do
			R.clock = R.clock + 1 / 30
			Fx.Update(R.clock)
			if each then
				each()
			end
		end
	end
	function R.finish()
		Fx.ClearAll()
		Fx.SetQuality("High")
		Fx.Hooks.Punch = R.oldPunch
		Fx._Deps({ MeshLibrary = false })
		holder:Destroy()
	end
	R.oldPunch = Fx.Hooks.Punch
	return R
end

local function itemOf(eff, id)
	for _, it in ipairs(eff.Items) do
		if it.Layer and it.Layer.Id == id then
			return it
		end
	end
	return nil
end

local function discTrans(it)
	if it.Soft then
		return it.Kit.Img.ImageTransparency
	end
	return it.Kit.Root.Transparency
end

S.client_afx_linger = guarded("client_afx_linger", function()
	local R = rig("SmokeAfxLinger", 9000)
	local Fx, Cat = R.Fx, R.Cat
	local function afterglow(req)
		req.Element = req.Element or "Flame"
		req.Rarity = req.Rarity or "Secret"
		req.Mine = true
		local r = Cat.Resolve(req)
		return r and r.Afterglow
	end
	-- the look that says "over": one number for the marks and the zone tail, dimmer than a live zone's 0.62 disc
	T.check(near(Cat.TailTransparency, 0.85), "afx linger: AttackFxCatalog.TailTransparency = 0.85", tostring(Cat.TailTransparency))
	-- the zone-sized mark does not linger: a live zone's size on the floor must be a live zone
	local field = Cat.Resolve({ Element = "Frost", Attack = "Melee", Rarity = "Secret", Mine = true })
	local fieldLayer = nil
	for _, l in ipairs(field and field.Layers or {}) do
		if l.Id == "Field" then
			fieldLayer = l
		end
	end
	T.check(fieldLayer ~= nil and fieldLayer.Linger ~= true, "afx linger: the Field (14 studs at Secret Evo 2, a Storm zone is 12) has no afterglow")
	-- the catalog
	local want = { Common = 0.8, Uncommon = 0.8, Rare = 1.2, Epic = 1.2, Legendary = 1.6, Mythic = 1.6, Secret = 2.0 }
	local byBand = T.tally("afx linger: Afterglow by band: 0.8, 1.2, 1.6, 2.0")
	for rarity, secs in pairs(want) do
		byBand:case(near(afterglow({ Attack = "Melee", Rarity = rarity }), secs), fmt("%s: %s", rarity, tostring(afterglow({ Attack = "Melee", Rarity = rarity }))))
	end
	byBand:report()
	T.check(near(Cat.Afterglow[4], 2.0) and #Cat.Afterglow == 4, "afx linger: AttackFxCatalog.Afterglow has one number a band, 2 s at most (the spec's 'up to 2 s')")
	local offensive = T.tally("afx linger: every damaging attack has an Afterglow")
	for _, req in ipairs({ { Attack = "Melee" }, { Attack = "Ranged" }, { Attack = "Element", Shape = "Cone" }, { Attack = "Element", Shape = "Circle" }, { Attack = "Element", Shape = "Line" },
		{ Attack = "Special", Kind = "Blast" }, { Attack = "Special", Kind = "Beam" }, { Attack = "Special", Kind = "Pounce" }, { Attack = "Special", Kind = "Freeze" }, { Attack = "Special", Kind = "Storm" } }) do
		offensive:case(near(afterglow(req), 2.0), req.Attack .. " " .. tostring(req.Kind or req.Shape))
	end
	offensive:report()
	local none = T.tally("afx linger: no Afterglow on support casts and reactions")
	for _, req in ipairs({ { Attack = "Special", Kind = "Heal" }, { Attack = "Special", Kind = "Shield" }, { Attack = "Special", Kind = "Rally" }, { Attack = "Special", Kind = "Haste" },
		{ Attack = "Hurt" }, { Attack = "Ko" }, { Attack = "Victory" }, { Attack = "ShieldHit" } }) do
		none:case(afterglow(req) == 0, req.Attack .. " " .. tostring(req.Kind))
	end
	none:report()

	-- a Secret Flame melee: the beats end, then the scorch and the embers stay on, dim and still
	local eff = R.play({ Element = "Flame", Rarity = "Secret" })
	if not T.check(eff ~= nil, "afx linger: a Secret Flame melee plays") then
		R.finish()
		return
	end
	local beats = eff.Recipe.Beats
	local tailAt = beats.Charge + beats.Release + beats.Travel + beats.Impact + math.max(beats.Linger, eff.Recipe.Alive.Seconds or 0)
	T.check(near(eff.TailAt, tailAt, 1e-6) and near(eff.EndRel, tailAt + 2.0, 1e-6) and near(eff.End - eff.Start, tailAt + 2.0, 1e-6), "afx linger: the effect ends Afterglow after its beats",
		fmt("TailAt %s EndRel %s, beats %s", tostring(eff.TailAt), tostring(eff.EndRel), tostring(tailAt)))
	local late = {}
	for _, it in ipairs(eff.Items) do
		local linger = it.Layer and it.Layer.Linger == true
		if not linger and it.T1 > tailAt + 0.26 then
			late[#late + 1] = tostring(it.Layer and it.Layer.Id or it.Kind) .. " " .. tostring(it.T1)
		end
	end
	T.check(#late == 0, "afx linger: every other item ends by the old end, as today (bar a light's own 0.25 s)", table.concat(late, ", "))
	local scorch, embers, glow = itemOf(eff, "Scorch"), itemOf(eff, "Alive"), itemOf(eff, "GroundGlow")
	T.check(scorch ~= nil and embers ~= nil and glow ~= nil, "afx linger: the Scorch, the GroundGlow and the embers are in the effect")
	T.check(embers ~= nil and embers.T1 <= tailAt, "afx linger: nothing is emitted after TailAt", tostring(embers and embers.T1))
	local em = embers and embers.Kit.Em
	-- (Seconds + Afterglow, but never past the effect's end: the kit is reused right after it, a particle cut there would pop)
	T.check(em ~= nil and near(em.Lifetime.Max, math.min(0.9 + 2.0, eff.EndRel - embers.T1), 1e-6) and em.Lifetime.Max > 0.9 + 1.0, "afx linger: the embers live on by the Afterglow and the last one ends with the effect", em and tostring(em.Lifetime.Max))
	local tKeys = em and em.Transparency.Keypoints or {}
	T.check(#tKeys >= 2 and tKeys[#tKeys].Value == 1 and tKeys[#tKeys - 1].Value >= 0.85, "afx linger: the embers' curve ends dim (>= 0.85, then gone)", #tKeys >= 2 and tostring(tKeys[#tKeys - 1].Value) or "")

	-- bright before the tail: the mark at its first second reads as the hit
	local seenBright = 1
	R.runTo(eff, eff.Times.Impact + 0.25, function()
		seenBright = math.min(seenBright, discTrans(scorch))
	end)
	T.check(seenBright <= 0.5, "afx linger: the Scorch is a clear mark while the hit plays", tostring(seenBright))
	-- past the beats
	local s0 = Fx.Stats()
	T.check(s0.Live == 1 and s0.Tails == 0, "afx linger: during its beats the effect is Live", fmt("Live %d Tails %d", s0.Live, s0.Tails))
	local holder2 = R.B:GetPivot()
	R.runTo(eff, tailAt + 0.05)
	local s1 = Fx.Stats()
	T.check(s1.Live == 0 and s1.Stepped == 0 and s1.Tails == 1 and eff.Tail == true, "afx linger: a tail is reported as a Tail, not Live", fmt("Live %d Stepped %d Tails %d", s1.Live, s1.Stepped, s1.Tails))
	local leftovers = {}
	for _, it in ipairs(eff.Items) do
		if it.Kit and not (it.Layer and it.Layer.Linger == true) then
			leftovers[#leftovers + 1] = tostring(it.Layer and it.Layer.Id or it.Kind)
		end
	end
	T.check(#leftovers == 0, "afx linger: past TailAt only the Linger items hold a kit", table.concat(leftovers, ", "))
	T.check(s1.Cores == 0 and s1.Beams == 0 and s1.Trails == 0 and s1.Lights == 0, "afx linger: a tail holds no core, beam, trail or light", fmt("%d %d %d %d", s1.Cores, s1.Beams, s1.Trails, s1.Lights))
	T.check(scorch.Kit ~= nil and discTrans(scorch) >= 0.85 and embers.Kit ~= nil, "afx linger: the Scorch is dim at TailAt (>= 0.85, dimmer than a live zone's 0.62) and the embers still live", scorch.Kit and tostring(discTrans(scorch)))
	-- the mark stays where it fell and only fades: never brighter, no pulse, not growing, the target's walk does not carry it
	local spot = scorch.Kit.Root.Position
	local size = scorch.Kit.Root.Size
	R.B:PivotTo(holder2 * CFrame.new(9, 0, 0))
	local prev, rose, moved, grew = discTrans(scorch), 0, 0, 0
	R.runTo(eff, eff.EndRel - 0.05, function()
		if scorch.Kit then
			local tr = discTrans(scorch)
			if tr < prev - 1e-9 then
				rose = rose + 1
			end
			prev = tr
			if (scorch.Kit.Root.Position - spot).Magnitude > 1e-6 then
				moved = moved + 1
			end
			if (scorch.Kit.Root.Size - size).Magnitude > 1e-6 then
				grew = grew + 1
			end
		end
	end)
	T.check(rose == 0, "afx linger: a tail's mark only fades (no pulse: it clearly reads as over)", tostring(rose))
	T.check(moved == 0 and grew == 0, "afx linger: a tail's mark lies still where it fell (not following the target, not growing)", fmt("moved %d, grew %d", moved, grew))
	T.check(prev > 0.9, "afx linger: it has nearly faded out by the end", tostring(prev))
	R.B:PivotTo(holder2)
	R.runTo(eff, eff.EndRel + 0.05)
	local s2 = Fx.Stats()
	T.check(s2.Live == 0 and s2.Tails == 0 and #Fx._Live() == 0 and s2.Emitters == 0, "afx linger: the effect is gone at EndRel, every kit back", fmt("Tails %d, %d live, %d emitters", s2.Tails, #Fx._Live(), s2.Emitters))

	-- a textured ground mark (a flat flipbook particle): lives on, dim, as long as the disc
	local earth = R.play({ Element = "Earth", Rarity = "Secret" })
	local crack = earth and itemOf(earth, "GroundCrack")
	if T.check(crack ~= nil, "afx linger: Earth's GroundCrack (a textured mark) plays") then
		local e = crack.Kit.Em
		local life = e.Lifetime.Max
		T.check(near(life, math.min(1.0 + 2.0, earth.EndRel - crack.T1), 1e-6) and life > 1.0 + 1.0, "afx linger: a flat mark's particle lives on by the Afterglow, ending with the effect", tostring(life))
		local keys = e.Transparency.Keypoints
		local knee = keys[#keys - 1]
		T.check(near(knee.Time, 1.0 / life, 1e-6) and knee.Value >= 0.85 and keys[#keys].Value == 1, "afx linger: its curve keeps the old second bright, then only fades", fmt("%s at %s", tostring(knee.Value), tostring(knee.Time)))
		local sizeKeys = e.Size.Keypoints
		T.check(near(sizeKeys[2].Time, 0.2 / life, 1e-6), "afx linger: it grows in as fast as before", tostring(sizeKeys[2].Time))
	end
	Fx.ClearAll()

	-- other players' pets: x OthersDensity
	local theirs = R.play({ Mine = false })
	T.check(theirs ~= nil and near(theirs.EndRel, theirs.TailAt + 2.0 * 0.6, 1e-6), "afx linger: others' effects keep Afterglow x 0.6", theirs and tostring(theirs.EndRel - theirs.TailAt))
	Fx.ClearAll()
	-- a miss leaves nothing behind
	local miss = R.play({ Miss = true })
	T.check(miss ~= nil and near(miss.EndRel, miss.TailAt, 1e-9), "afx linger: a miss has no tail", miss and tostring(miss.EndRel - miss.TailAt))
	Fx.ClearAll()
	-- a support cast
	local heal = R.play({ Attack = "Special", Kind = "Heal", Element = "Nature", To = { Unit = 1, Model = R.A } })
	T.check(heal ~= nil and near(heal.EndRel, heal.TailAt, 1e-9), "afx linger: a Heal has no tail", heal and tostring(heal.EndRel - heal.TailAt))
	Fx.ClearAll()
	-- Graphics Low: no tail, and the marks last as before
	Fx.SetQuality("Low")
	local low = R.play({})
	T.check(low ~= nil and near(low.EndRel, low.TailAt, 1e-9), "afx linger: Graphics Low has no tail", low and tostring(low.EndRel - low.TailAt))
	local lowScorch = low and itemOf(low, "Scorch")
	T.check(lowScorch ~= nil and near(lowScorch.T1, lowScorch.T0 + 0.9, 1e-6), "afx linger: ...and its Scorch lasts its own Seconds", lowScorch and tostring(lowScorch.T1 - lowScorch.T0))
	Fx.SetQuality("High")
	Fx.ClearAll()
	-- switching to Low mid-effect: the tail goes
	local going = R.play({})
	R.runTo(going, going.TailAt + 0.1)
	T.check(Fx.Stats().Tails == 1, "afx linger: a tail is playing")
	Fx.SetQuality("Low")
	R.run(0.1)
	T.check(Fx.Stats().Tails == 0 and #Fx._Live() == 0, "afx linger: switching to Low ends a tail at once", tostring(Fx.Stats().Tails))
	local fresh = R.play({})
	T.check(fresh ~= nil and near(fresh.EndRel, fresh.TailAt, 1e-9), "afx linger: played at Low, no tail")
	Fx.SetQuality("High")
	Fx.ClearAll()

	-- a signature's battle dim and an inhale end with the beats, not with the tail
	local undim, hush = {}, {}
	local oldUndim, oldDim, oldHush, oldInhale = Fx.Hooks.Undim, Fx.Hooks.DimWorld, Fx.Hooks.Hush, Fx.Hooks.Inhale
	Fx.Hooks.DimWorld = function() end
	Fx.Hooks.Undim = function(token)
		undim[#undim + 1] = R.clock
	end
	Fx.Hooks.Inhale = function() return true end
	Fx.Hooks.Hush = function(token)
		hush[#hush + 1] = R.clock
	end
	local nova = R.play({ Element = "Shadow", Attack = "Special", Kind = "Blast", PetId = "eclipse_dragon", Rarity = "Secret" })
	T.check(nova ~= nil and nova.EndRel > nova.TailAt, "afx linger: Eclipse Nova has a tail")
	if nova then
		R.runTo(nova, nova.TailAt + 0.1)
		T.check(#undim == 1 and nova.DimToken == nil, "afx linger: a signature's battle dim lifts when the beats end, not after the tail", tostring(#undim))
		R.runTo(nova, nova.EndRel + 0.05)
		T.check(#undim == 1, "afx linger: ...once", tostring(#undim))
	end
	Fx.Hooks.Undim, Fx.Hooks.DimWorld, Fx.Hooks.Hush, Fx.Hooks.Inhale = oldUndim, oldDim, oldHush, oldInhale

	-- Cancel and ClearAll end a tail too
	local c1 = R.play({})
	R.runTo(c1, c1.TailAt + 0.1)
	Fx.Cancel(1)
	T.check(Fx.Stats().Tails == 0 and #Fx._Live() == 0, "afx linger: Cancel(caster) ends its tail")
	local c2 = R.play({})
	R.runTo(c2, c2.TailAt + 0.1)
	Fx.ClearAll()
	T.check(Fx.Stats().Tails == 0 and #Fx._Live() == 0, "afx linger: ClearAll ends a tail")
	T.eq(Fx.Stats().Errors, R.errs0, "afx linger: no effect ended by an error")
	R.finish()
end)

-- Review Focus 4: a lingering tail never blocks a new effect
S.client_afx_tails = guarded("client_afx_tails", function()
	local R = rig("SmokeAfxTails", 19000)
	local Fx = R.Fx
	T.eq(Fx.MAX_TAILS, 12, "afx tails: AttackFx.MAX_TAILS = 12")
	local first = {}
	for i = 1, 10 do
		first[i] = R.play({ From = { Unit = 100 + i, Model = R.A } })
	end
	T.check(first[10] ~= nil and Fx.Stats().Live == 10, "afx tails: 10 full effects")
	local refused = Fx.Play(R.ctx({}))
	T.check(refused == true and Fx._Live()[#Fx._Live()].Stepped == true, "afx tails: the 11th now steps down, as before")
	Fx.ClearAll()
	for i = 1, 10 do
		first[i] = R.play({ From = { Unit = 100 + i, Model = R.A } })
	end
	R.runTo(first[10], first[10].TailAt + 0.1)
	local s = Fx.Stats()
	T.check(s.Live == 0 and s.Tails == 10, "afx tails: 10 effects in their afterglow", fmt("Live %d Tails %d", s.Live, s.Tails))
	local e11 = R.play({ From = { Unit = 111, Model = R.A } })
	T.check(e11 ~= nil and e11.Stepped == false and Fx.Stats().Live == 1, "afx tails: an 11th play is a full play: not stepped, not refused", e11 and tostring(e11.Stepped))
	local e12 = R.play({ From = { Unit = 112, Model = R.A } })
	local e13 = R.play({ From = { Unit = 113, Model = R.A } })
	T.check(e12 ~= nil and e13 ~= nil and e13.Stepped == false, "afx tails: ...and the next two")
	local oldest = first[1]
	local oldestItems = oldest.Items
	local kits = {}
	for _, it in ipairs(oldestItems) do
		if it.Kit then
			kits[#kits + 1] = it
		end
	end
	T.check(#kits > 0, "afx tails: the oldest tail holds its marks", tostring(#kits))
	R.runTo(e13, e13.TailAt - 0.1)
	T.check(Fx.Stats().Tails == 10, "afx tails: the three are not tails yet", tostring(Fx.Stats().Tails))
	R.runTo(e13, e13.TailAt + 0.1)
	s = Fx.Stats()
	T.check(s.Tails == 12, "afx tails: never more than MAX_TAILS at once: 13 tails -> 12", tostring(s.Tails))
	local gone = true
	for _, e in ipairs(Fx._Live()) do
		gone = gone and e ~= oldest
	end
	local holding = 0
	for _, it in ipairs(kits) do
		holding = holding + (it.Kit and 1 or 0)
	end
	T.check(gone and holding == 0, "afx tails: the oldest tail is finished at once, every kit back", fmt("gone %s, %d kits held", tostring(gone), holding))
	T.check(first[2].Tail == true and #first[2].Items > 0, "afx tails: the second-oldest plays on")
	-- nothing is stepped twice or skipped: every tail still ends on its clock
	R.run(4)
	s = Fx.Stats()
	T.check(s.Live == 0 and s.Tails == 0 and #Fx._Live() == 0 and s.Emitters == 0, "afx tails: all gone after their afterglow", fmt("Live %d Tails %d left %d", s.Live, s.Tails, #Fx._Live()))
	T.eq(s.Errors, R.errs0, "afx tails: no effect ended by an error")

	-- a sustained 3v3 at Mythic: ~6 hits a second, in batches of three, for 12 s: after the first seconds the fight lives off its pool
	Fx.ClearAll()
	Fx.Folder():Destroy()
	local folder = Fx.Folder()
	local seen, created = {}, 0
	local function countNew()
		for _, c in ipairs(folder:GetChildren()) do
			if c.Name == "FxDisc" and not seen[c] then
				seen[c] = true
				created = created + 1
			end
		end
	end
	local warm, lastCreated = 0, 0
	for batch = 1, 24 do
		for u = 1, 3 do
			R.play({ Element = "Flame", Rarity = "Mythic", From = { Unit = 200 + u, Model = R.A } })
		end
		R.run(0.5, countNew)
		if batch == 8 then
			warm = created
		end
		lastCreated = created
	end
	T.check(lastCreated - warm == 0, "afx tails: after 4 s of a sustained fight no new ground disc is made: the pool does not churn", fmt("%d at 4 s, %d at 12 s", warm, lastCreated))
	R.run(5)
	local after = Fx.Stats()
	local kept = 0
	for _, c in ipairs(folder:GetChildren()) do
		kept = kept + ((c.Name == "FxDisc") and 1 or 0)
	end
	print(fmt("  [afx pool] sustained fight: %d discs made in 4 s, %d in 12 s, %d kept after it, %d pooled instances", warm, lastCreated, kept, after.PoolInstances))
	T.check(kept >= math.min(lastCreated, 24), "afx tails: the discs are kept for the next fight, not destroyed and made again", fmt("%d of %d kept", kept, lastCreated))
	T.check(after.Pooled <= Fx.POOL_KEEP_TOTAL, "afx tails: the pool stays under its keep size", fmt("%d <= %d", after.Pooled, Fx.POOL_KEEP_TOTAL))
	T.eq(after.Errors, R.errs0, "afx tails: the sustained fight ended no effect by an error")
	R.finish()
end)

-- Review Focus 5
S.client_afx_kick = guarded("client_afx_kick", function()
	local R = rig("SmokeAfxKick", 29000)
	local Fx, Cat = R.Fx, R.Cat
	local punches = {}
	Fx.Hooks.Punch = function(amount, seconds)
		punches[#punches + 1] = { amount, seconds, R.clock }
	end
	local Kick = Cat.Kick
	T.check(type(Kick) == "table" and Kick.Basic == 0.05 and Kick.Element == 0.10 and Kick.Special == 0.14 and Kick.BandStep == 0.03 and Kick.Crit == 0.04 and Kick.Seconds == 0.15 and Kick.BasicGap == 0.6,
		"afx kick: AttackFxCatalog.Kick is the plan's table")
	local function kickOf(over)
		punches = {}
		Fx.ClearAll()
		R.clock = R.clock + 2 -- (past any basic gap)
		local eff = R.play(over)
		if not eff then
			return nil
		end
		R.runTo(eff, eff.Times.Impact + 0.1)
		return punches[1] and punches[1][1], #punches, punches[1] and punches[1][2]
	end
	local a, n, secs = kickOf({ Attack = "Melee", Rarity = "Common" })
	T.check(near(a, 0.05, 1e-6) and n == 1 and near(secs, 0.15, 1e-9), "afx kick: a Common basic hit kicks 0.05 for 0.15 s", fmt("%s x%s, %s s", tostring(a), tostring(n), tostring(secs)))
	a = kickOf({ Attack = "Ranged", Rarity = "Common" })
	T.check(near(a, 0.05, 1e-6), "afx kick: ...a ranged shot too", tostring(a))
	a = kickOf({ Attack = "Element", Shape = "Cone", Rarity = "Common" })
	T.check(near(a, 0.10, 1e-6), "afx kick: a Common element attack kicks 0.10", tostring(a))
	a = kickOf({ Attack = "Special", Kind = "Blast", Rarity = "Common" })
	T.check(near(a, 0.14, 1e-6), "afx kick: a Common Special kicks 0.14", tostring(a))
	a = kickOf({ Attack = "Special", Kind = "Blast", Rarity = "Legendary" })
	T.check(near(a, 0.20, 1e-6), "afx kick: a Legendary Special kicks 0.20 (PUNCH_BIG: the dungeon's FOV punch keeps its threshold)", tostring(a))
	a = kickOf({ Attack = "Special", Kind = "Blast", Rarity = "Secret", Crit = true })
	T.check(near(a, 0.27, 1e-6) and a <= Fx.PUNCH_MAX, "afx kick: a Secret Special crit kicks 0.27, under PUNCH_MAX", tostring(a))
	-- the recipe's own table, every attack under the cap
	local capped = T.tally("afx kick: recipe.CameraPunch = { Amount <= 0.35, Seconds 0.15, Basic } for an own attack at every band")
	for _, rarity in ipairs(Cat.Rarities) do
		for _, req in ipairs({ { Attack = "Melee" }, { Attack = "Ranged" }, { Attack = "Element", Shape = "Line" }, { Attack = "Special", Kind = "Storm" } }) do
			local r = Cat.Resolve({ Element = "Storm", Attack = req.Attack, Kind = req.Kind, Shape = req.Shape, Rarity = rarity, Mine = true })
			local p = r and r.CameraPunch
			local basic = req.Attack == "Melee" or req.Attack == "Ranged"
			capped:case(type(p) == "table" and p.Amount <= 0.35 and p.Seconds == 0.15 and p.Basic == basic, fmt("%s %s: %s", rarity, req.Attack, tostring(p and p.Amount)))
		end
	end
	capped:report()

	-- none: others' pets, reactions, support casts, misses
	for _, case in ipairs({
		{ "Mine = false", { Attack = "Special", Kind = "Blast", Mine = false } },
		{ "Hurt", { Attack = "Hurt" } },
		{ "Ko", { Attack = "Ko" } },
		{ "Victory", { Attack = "Victory" } },
		{ "ShieldHit", { Attack = "ShieldHit" } },
		{ "a Heal", { Attack = "Special", Kind = "Heal" } },
		{ "a Shield", { Attack = "Special", Kind = "Shield" } },
		{ "a Rally", { Attack = "Special", Kind = "Rally" } },
		{ "a Haste", { Attack = "Special", Kind = "Haste" } },
		{ "a miss", { Attack = "Melee", Miss = true } },
	}) do
		local _, cnt = kickOf(case[2])
		T.check(cnt == 0, "afx kick: " .. case[1] .. " does not kick", tostring(cnt))
	end

	-- the rate limit: BasicGap between two basic kicks
	punches = {}
	Fx.ClearAll()
	R.clock = R.clock + 2
	local m1 = R.play({ Attack = "Melee", Rarity = "Common" })
	R.runTo(m1, m1.Times.Impact + 0.02)
	T.check(#punches == 1, "afx gap: the first basic hit kicks", tostring(#punches))
	-- each next effect's impact lands `gap` after the last one
	local function impactAfter(gap)
		local e = R.play({ Attack = "Melee", Rarity = "Common", DueAt = punches[#punches][3] + gap, From = { Unit = 300 + #punches, Model = R.A } })
		R.runTo(e, e.Times.Impact + 0.02)
		return e
	end
	impactAfter(0.3)
	T.check(#punches == 1, "afx gap: a second basic hit 0.3 s later does not", tostring(#punches))
	-- a hasted fighter: a hit every 0.3 s kicks at most once per BasicGap
	local base = punches[#punches][3]
	local hits = 0
	local at = base + 0.3
	for _ = 1, 8 do
		at = at + 0.3
		hits = hits + 1
		local e = R.play({ Attack = "Melee", Rarity = "Common", DueAt = at, From = { Unit = 400 + hits, Model = R.A } })
		R.runTo(e, e.Times.Impact + 0.02)
	end
	local tooClose = 0
	for i = 2, #punches do
		if punches[i][3] - punches[i - 1][3] < 0.6 - 1e-6 then
			tooClose = tooClose + 1
		end
	end
	T.check(tooClose == 0 and #punches >= 3 and #punches <= 5, "afx gap: a hit every 0.3 s kicks at most once per 0.6 s", fmt("%d kicks of %d hits, %d too close", #punches, hits + 2, tooClose))
	-- never swallowed: a Special right after a basic kick
	Fx.ClearAll()
	R.clock = R.clock + 2
	punches = {}
	local mk = R.play({ Attack = "Melee", Rarity = "Common" })
	R.runTo(mk, mk.Times.Impact + 0.02)
	T.check(#punches == 1, "afx gap: a basic kick", tostring(#punches))
	local sameTime = R.clock
	local melee2 = R.play({ Attack = "Melee", Rarity = "Common", DueAt = sameTime + 0.3, From = { Unit = 501, Model = R.A } })
	local spec = R.play({ Attack = "Special", Kind = "Blast", Rarity = "Common", DueAt = sameTime + 0.35, From = { Unit = 502, Model = R.A } })
	R.run(0.45)
	T.check(melee2 ~= nil and spec ~= nil and #punches == 2 and near(punches[2][1], 0.14, 1e-6), "afx gap: a Melee at 0.3 s is swallowed, a Special at 0.35 s still kicks", fmt("%d kicks, last %s", #punches, tostring(punches[#punches][1])))
	-- a Special's kick does not start the basic gap
	Fx.ClearAll()
	R.clock = R.clock + 2
	punches = {}
	local s1 = R.play({ Attack = "Special", Kind = "Blast", Rarity = "Common" })
	R.runTo(s1, s1.Times.Impact + 0.02)
	local m3 = R.play({ Attack = "Melee", Rarity = "Common", DueAt = R.clock + 0.2, From = { Unit = 503, Model = R.A } })
	R.runTo(m3, m3.Times.Impact + 0.02)
	T.check(#punches == 2, "afx gap: a basic hit right after a Special still kicks (the gap is the basic hits' own)", tostring(#punches))
	R.finish()
end)

-- BattleController's route: Shake off leaves the camera alone
S.client_afx_kick_battle = guarded("client_afx_kick_battle", function()
	local BC = moduleAt(ROOTS.client .. "/Controllers/BattleController")
	local AF = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
	local Sim = moduleAt(ROOTS.shared .. "/BattleSim")
	if not T.check(BC ~= nil and AF ~= nil and Sim ~= nil and KC ~= nil, "afx kick (battle): the modules load") then
		return
	end
	AF.ClearAll()
	AF._Deps({ MeshLibrary = fakeMeshLibrary() })
	AF.SetQuality("High")
	local me = LocalPlayer.UserId
	local id = "afx_kick_battle"
	local sim = Sim.new({ Mode = "Duel", Seed = 23, Id = id, Zone = { X = 90, Z = 90 }, TimeLimit = 300,
		Teams = { { Owner = me, Side = 1, Pets = { { PetId = "puddle_frog", Key = "puddle_frog", Level = 20, Tier = "Normal", Slot = 1 } } },
			{ Owner = "frogs", Side = 2, Npc = true, Specials = false, Pets = { { PetId = "puddle_frog", Key = "puddle_frog", Level = 20, Tier = "Normal", Slot = 1 } } } } })
	local mine, foe = nil, nil
	for _, u in ipairs(sim.units) do
		u.maxHp, u.hp = 1e7, 1e7
		if u.side == 1 then
			mine = u
			u.x, u.z = 0, 0
		else
			foe = u
			u.x, u.z, u.moveSpeed = 10, 0, 0
		end
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
	LocalPlayer:SetAttribute("InBattle", id)
	KC.toClient("BattleState", "Start", start, id)
	local function frames(n)
		for _ = 1, n do
			Mock.Step(1 / 30)
		end
	end
	frames(15)
	local hum = Mock.GetHumanoid(LocalPlayer)
	local oldPunch = AF.Hooks.Punch
	local kicks = 0
	if type(oldPunch) == "function" then
		AF.Hooks.Punch = function(amount, seconds)
			kicks = kicks + 1
			oldPunch(amount, seconds)
		end
	end
	local function blast()
		KC.toClient("BattleState", "Events", { { type = "Special", unit = mine.id, kind = "Blast", name = "Blast", x = mine.x, z = mine.z, tx = foe.x, tz = foe.z, target = foe.id, targets = { foe.id } } }, id)
	end
	if T.check(type(oldPunch) == "function" and hum ~= nil, "afx kick (battle): BattleController hooks the Punch; my character has a Humanoid") then
		local base = hum.CameraOffset
		-- Shake off
		BC.Hooks.Shake = function()
			return false
		end
		blast()
		local moved = 0
		for _ = 1, 60 do
			frames(1)
			if (hum.CameraOffset - base).Magnitude > 1e-4 then
				moved = moved + 1
			end
		end
		T.check(kicks == 1 and moved == 0, "afx kick (battle): Shake OFF leaves Humanoid.CameraOffset untouched", fmt("%d kicks, moved on %d frames", kicks, moved))
		frames(90) -- (past the cast)
		-- Shake on
		BC.Hooks.Shake = function()
			return true
		end
		kicks = 0
		blast()
		local frame = 0
		while kicks == 0 and frame < 90 do
			frames(1)
			frame = frame + 1
		end
		T.check(kicks == 1, "afx kick (battle): the Special's kick comes", tostring(kicks))
		local seen = 0
		for _ = 1, 4 do -- (about 0.13 s)
			frames(1)
			if (hum.CameraOffset - base).Magnitude > 1e-4 then
				seen = seen + 1
			end
		end
		T.check(seen > 0, "afx kick (battle): Shake ON: the offset moves at once", tostring(seen))
		frames(7) -- (0.36 s after the kick)
		T.check((hum.CameraOffset - base).Magnitude < 1e-4, "afx kick (battle): ...and is back at its base by 0.35 s", tostring((hum.CameraOffset - base).Magnitude))
		-- a small kick never cuts a stronger shake that is still playing (the size of a KO's 0.3 s shake, then a basic hit lands)
		frames(30)
		AF.Hooks.Punch(0.3, 0.3)
		frames(1)
		AF.Hooks.Punch(0.05, 0.15)
		local biggest = 0
		for _ = 1, 3 do
			frames(1)
			biggest = math.max(biggest, (hum.CameraOffset - base).Magnitude)
		end
		T.check(biggest > 0.07, "afx kick (battle): a small kick does not cut a stronger shake still playing", tostring(biggest))
		frames(20)
		T.check((hum.CameraOffset - base).Magnitude < 1e-4, "afx kick (battle): ...and the camera settles", tostring((hum.CameraOffset - base).Magnitude))
		-- ...and a strong kick does take over from a small shake
		AF.Hooks.Punch(0.05, 0.15)
		frames(1)
		AF.Hooks.Punch(0.3, 0.3)
		biggest = 0
		for _ = 1, 3 do
			frames(1)
			biggest = math.max(biggest, (hum.CameraOffset - base).Magnitude)
		end
		T.check(biggest > 0.07, "afx kick (battle): a stronger kick takes over from a small shake", tostring(biggest))
		frames(20)
	end
	AF.Hooks.Punch = oldPunch
	BC.Hooks.Shake = nil
	KC.toClient("BattleState", "End", { BattleId = id, Mode = "Duel", Outcome = "Win", Won = true, Spectator = false, Reason = "Wipe",
		Rewards = { Tokens = 0, Gems = 0, Xp = 0, Trophies = 0, LevelUps = 0 } }, id)
	LocalPlayer:SetAttribute("InBattle", nil)
	KC.advance(15)
	AF._Deps({ MeshLibrary = false })
	AF.SetQuality("High")
	KC.flushErrors("client_afx_kick_battle")
end)

S.client_afx_zone_tail = guarded("client_afx_zone_tail", function()
	local BC = moduleAt(ROOTS.client .. "/Controllers/BattleController")
	local AF = moduleAt(ROOTS.client .. "/Controllers/AttackFx")
	local Sim = moduleAt(ROOTS.shared .. "/BattleSim")
	if not T.check(BC ~= nil and AF ~= nil and Sim ~= nil and KC ~= nil, "afx zone tail: the modules load") then
		return
	end
	AF.ClearAll()
	AF._Deps({ MeshLibrary = fakeMeshLibrary() })
	AF.SetQuality("High")
	local me = LocalPlayer.UserId
	local id = "afx_zone_tail"
	local sim = Sim.new({ Mode = "Duel", Seed = 23, Id = id, Zone = { X = 90, Z = 90 }, TimeLimit = 300,
		Teams = { { Owner = me, Side = 1, Pets = { { PetId = "puddle_frog", Key = "puddle_frog", Level = 20, Tier = "Normal", Slot = 1 } } },
			{ Owner = "frogs", Side = 2, Npc = true, Specials = false, Pets = { { PetId = "puddle_frog", Key = "puddle_frog", Level = 20, Tier = "Normal", Slot = 1 } } } } })
	local mine = nil
	for _, u in ipairs(sim.units) do
		u.maxHp, u.hp = 1e7, 1e7
		if u.side == 1 then
			mine = u
		end
	end
	local start = sim:Describe()
	start.BattleId = id
	start.Zone = { CFrame = CFrame.new(0, 200, 0), Size = Vector3.new(start.Zone.X, 30, start.Zone.Z), X = start.Zone.X, Z = start.Zone.Z }
	start.Names = { [tostring(me)] = LocalPlayer.Name }
	start.Side, start.Spectator, start.T = 1, false, sim:Time()
	LocalPlayer:SetAttribute("InBattle", id)
	KC.toClient("BattleState", "Start", start, id)
	local function frames(seconds)
		for _ = 1, math.floor(seconds * 30 + 0.5) do
			Mock.Step(1 / 30)
		end
	end
	frames(0.5)
	local R_DISC = 7.3 -- (no other part in the fixture has this width)
	local function allFx()
		local out = {}
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "BattleFx" then
				out[#out + 1] = d
			end
		end
		return out
	end
	local function discOf()
		for _, p in ipairs(allFx()) do
			if near(p.Size.Y, R_DISC * 2, 1e-6) and near(p.Size.Z, R_DISC * 2, 1e-6) then
				return p
			end
		end
		return nil
	end
	local function visibleOthers(disc)
		local n = 0
		for _, p in ipairs(allFx()) do
			if p ~= disc and p.Transparency < 1 then
				n = n + 1
			end
		end
		return n
	end
	local function zone(kind, attack)
		KC.toClient("BattleState", "Events", { { type = "Zone", unit = mine.id, kind = kind, attack = attack, x = 20, z = 20, r = R_DISC, seconds = 4, side = 1 } }, id)
	end
	-- a pet Storm, its voxel cloud
	zone("Storm")
	frames(2)
	local disc = discOf()
	T.check(disc ~= nil and disc.Transparency < 0.7, "afx zone tail: a live Storm zone has a clear disc", disc and tostring(disc.Transparency))
	T.check(visibleOthers(disc) >= 5, "afx zone tail: ...and its cloud", tostring(visibleOthers(disc)))
	frames(2.2) -- (t 4.2 s: the damage is over)
	disc = discOf()
	T.check(disc ~= nil and disc.Transparency >= 0.85 and disc.Transparency < 1, "afx zone tail: at 4.2 s the disc is still there, dim (>= 0.85)", disc and tostring(disc.Transparency))
	T.check(visibleOthers(disc) == 0, "afx zone tail: ...with no cloud and no bolts", tostring(visibleOthers(disc)))
	local p0 = disc and disc.Transparency
	frames(0.6)
	T.check(disc ~= nil and disc.Transparency >= p0 - 1e-9, "afx zone tail: it only fades", disc and tostring(disc.Transparency))
	frames(0.8) -- (t 5.6 s)
	T.check(discOf() == nil, "afx zone tail: at 5.6 s it is gone", tostring(discOf() ~= nil))
	-- the last moments of the live zone never flash brighter or vanish first: the disc goes straight to its dim look
	zone("Storm")
	frames(3.5)
	disc = discOf()
	local seenOut = false
	for _ = 1, 21 do -- (3.5 .. 4.2 s)
		frames(1 / 30)
		if disc and disc.Parent and disc.Transparency >= 0.999 then
			seenOut = true
		end
	end
	T.check(not seenOut, "afx zone tail: the disc does not vanish and come back at the hand-over")
	frames(2)
	-- a Field zone (the Storm special played: the cloud is AttackFx's, the zone draws only its disc) holds its tail too
	KC.toClient("BattleState", "Events", { { type = "Special", unit = mine.id, kind = "Storm", name = "Storm", x = 0, z = 0, tx = 20, tz = 20, targets = {} } }, id)
	frames(0.1)
	zone("Storm")
	frames(2)
	disc = discOf()
	T.check(disc ~= nil and visibleOthers(disc) == 0, "afx zone tail: a Field zone is the disc alone", tostring(disc and visibleOthers(disc)))
	frames(2.2)
	disc = discOf()
	T.check(disc ~= nil and disc.Transparency >= 0.85, "afx zone tail: at 4.2 s a Field's disc is still there, dim", disc and tostring(disc.Transparency))
	frames(1.4)
	T.check(discOf() == nil, "afx zone tail: ...and gone at 5.6 s", tostring(discOf() ~= nil))
	local Cat = moduleAt(ROOTS.shared .. "/AttackFxCatalog")
	local oldTail = Cat.TailTransparency
	Cat.TailTransparency = 0.95
	zone("Storm")
	frames(4.2)
	local disc95 = discOf()
	Cat.TailTransparency = oldTail
	T.check(oldTail ~= nil and disc95 ~= nil and disc95.Transparency >= 0.95, "afx zone tail: the zone's tail reads AttackFxCatalog.TailTransparency: one number with the marks", disc95 and tostring(disc95.Transparency))
	frames(1.4)
	-- a boss zone ends on time, as before
	zone("Linger", "Slam")
	frames(2)
	T.check(discOf() ~= nil, "afx zone tail: a boss Linger zone plays")
	frames(2.2)
	T.check(discOf() == nil, "afx zone tail: ...and is gone at its seconds: no tail", tostring(discOf() ~= nil))
	-- Graphics Low: no tail (the real route: ClientSettings "Gfx" changes -> Atk.SyncQuality reads GraphicsQuality.Effective)
	local GQ = moduleAt(ROOTS.client .. "/GraphicsQuality")
	local CS = moduleAt(ROOTS.client .. "/ClientSettings")
	if T.check(GQ ~= nil and type(GQ._St) == "table" and CS ~= nil, "afx zone tail: GraphicsQuality and ClientSettings load") then
		local oldEffective, oldStarted, oldGfx = GQ.Effective, GQ._St.Started, CS.Get("Gfx")
		local mode = "Low"
		GQ.Effective, GQ._St.Started = function()
			return mode
		end, true
		CS.Set("Gfx", "Low")
		frames(0.2)
		zone("Storm")
		frames(4.2)
		T.check(discOf() == nil, "afx zone tail: Graphics Low: gone at its seconds, no tail", tostring(discOf() ~= nil))
		mode = "High"
		CS.Set("Gfx", oldGfx)
		frames(0.2)
		GQ.Effective, GQ._St.Started = oldEffective, oldStarted
	end
	KC.toClient("BattleState", "End", { BattleId = id, Mode = "Duel", Outcome = "Win", Won = true, Spectator = false, Reason = "Wipe",
		Rewards = { Tokens = 0, Gems = 0, Xp = 0, Trophies = 0, LevelUps = 0 } }, id)
	LocalPlayer:SetAttribute("InBattle", nil)
	KC.advance(15)
	AF._Deps({ MeshLibrary = false })
	AF.SetQuality("High")
	KC.flushErrors("client_afx_zone_tail")
end)

return S
