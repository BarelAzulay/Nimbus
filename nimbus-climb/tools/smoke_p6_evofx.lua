-- smoke_p6_evofx.lua: the Phase 6 effects of evolved pets (ARCHITECTURE_V3.md "## Phase 6" 6.0.4, 6.1 A6, 6.4;
-- owner: evofx, wave 1). Loaded by tools/smoke.py in BOTH worlds:
--   p6evofx_specs   (server, pure) PetFx.Spec for every element x stage x detail: stage 1 = 1 emitter + light 0.6 /
--                   range 6, stage 2 = 2 emitters + light 1.0 / range 8, total Rate <= 12 (High) and <= 4 (Low), Low
--                   at most half of High, default sprite only (no texture ids), every curve valid; ElementOf
--   p6evofx_build   (server, pure) the real PetBuilder.Build of every catalog pet at stage 0 / 1 / 2 (Low detail; a
--                   few at High): stage 0 has no Body.PetFx, evolved pets get it within budget with the pet's catalog
--                   element, the stage-2 aura glows in the pet's Glow colours and its Neon Aura parts pulse; PetFx
--                   creates no Parts (same BasePart count as NoFx), NoFx / Viewport skip (Viewport + Fx builds), Apply
--                   twice / on a Clone keeps one PetFx, Clear removes it and its pulse flags, every emitter is tagged,
--                   Animate runs on an evolved pet with effects without creating instances
--   client_p6evofx  (client) GraphicsQuality Low = light only: SetQuality("Low") turns off the emitters already in the
--                   game, those built later and those that stream in (server-built), the PointLight stays on; "High"
--                   turns exactly those back on
-- Deterministic: no RNG, catalog order, each scenario destroys what it builds and restores the quality mode.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
local IS_SERVER = game:GetService("RunService"):IsServer()
local CollectionService = game:GetService("CollectionService")
local fmt = string.format

local function req(name)
	local ok, inst = pcall(Mock.GetPath, ROOTS["shared"] .. "/" .. name)
	if not ok or not inst then
		return nil
	end
	local ok2, mod = pcall(require, inst)
	return ok2 and type(mod) == "table" and mod or nil
end

local ELEMENTS = { "Water", "Flame", "Frost", "Nature", "Earth", "Storm", "Celestial", "Shadow" }

local function fxOf(model)
	local body = model and model:FindFirstChild("Body")
	return body and body:FindFirstChild("PetFx") or nil
end

local function countFx(model)
	local body = model and model:FindFirstChild("Body")
	local n = 0
	if body then
		for _, c in ipairs(body:GetChildren()) do
			if c.Name == "PetFx" then
				n = n + 1
			end
		end
	end
	return n
end

local function emittersOf(fx)
	local list, rate = {}, 0
	if fx then
		for _, c in ipairs(fx:GetChildren()) do
			if c:IsA("ParticleEmitter") then
				list[#list + 1] = c
				rate = rate + c.Rate
			end
		end
	end
	return list, rate
end

local function parts(model)
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			n = n + 1
		end
	end
	return n
end

if IS_SERVER then

----------------------------------------------------------------------------------------------------
S.p6evofx_specs = guarded("p6evofx_specs", function()
	local Fx = req("PetFx")
	if not T.check(Fx ~= nil and type(Fx.Apply) == "function" and type(Fx.Clear) == "function" and type(Fx.Spec) == "function",
		"PetFx loads (Apply, Clear, Spec)") then
		return
	end
	local budget = T.tally("PetFx.Spec: every element x stage x detail within the 6.4 budgets")
	for _, e in ipairs(ELEMENTS) do
		budget:case(Fx.Elements[e] ~= nil, e .. ": has a recipe")
		for stage = 1, 2 do
			local hi, lo = Fx.Spec(e, stage, "High"), Fx.Spec(e, stage, "Low")
			local tag = fmt("%s stage %d", e, stage)
			budget:case(hi.Element == e and hi.Stage == stage, tag .. ": spec echoes element / stage")
			budget:case((stage == 1 and hi.Aura == nil) or (stage == 2 and hi.Aura ~= nil and lo.Aura ~= nil), tag .. ": 1 emitter at stage 1, 2 at stage 2")
			budget:case(hi.Rate <= 12 + 1e-6 and lo.Rate <= 4 + 1e-6, tag .. fmt(": rates %.2f (High) / %.2f (Low) within 12 / 4", hi.Rate, lo.Rate))
			budget:case(lo.Rate <= hi.Rate * 0.5 + 1e-6 and lo.Rate > 0, tag .. fmt(": Low detail at most half of High (%.2f vs %.2f)", lo.Rate, hi.Rate))
			local L = stage == 1 and { 0.6, 6 } or { 1.0, 8 }
			budget:case(math.abs(hi.Light.Brightness - L[1]) < 1e-6 and hi.Light.Range == L[2] and lo.Light.Brightness == hi.Light.Brightness,
				tag .. fmt(": light %.1f / range %d", hi.Light.Brightness, hi.Light.Range))
		end
		local s1, s2 = Fx.Spec(e, 1, "High"), Fx.Spec(e, 2, "High")
		budget:case(s2.Rate > s1.Rate and s2.Wide > 1 and s2.Light.Brightness > s1.Light.Brightness and s2.Light.Range > s1.Light.Range,
			e .. ": stage 2 is stronger than stage 1 (more particles, wider, brighter, bigger light)")
		local r = Fx.Elements[e]
		budget:case(r.Texture == nil, e .. ": default sprite only (no texture id)")
		budget:case(r.Lifetime[1] > 0 and r.Lifetime[1] <= r.Lifetime[2] and r.Lifetime[2] <= 3 and r.Speed[1] <= r.Speed[2], e .. ": sane lifetime / speed ranges")
		local function curveOk(c)
			if type(c) ~= "table" or #c < 2 or c[1][1] ~= 0 or c[#c][1] ~= 1 then
				return false
			end
			for i = 2, #c do
				if c[i][1] <= c[i - 1][1] then
					return false
				end
			end
			return true
		end
		budget:case(curveOk(r.Size) and curveOk(r.Transparency) and curveOk(r.Color) and (r.Squash == nil or curveOk(r.Squash)), e .. ": curves start at 0, end at 1, increase")
	end
	budget:report()
	-- ElementOf: explicit > look.Element > catalog (Base, Id, Golden copies) > hybrid style > species
	local PC = req("PetCatalog")
	local tl = T.tally("PetFx.ElementOf follows the catalog")
	for _, def in ipairs(PC and PC.Pets or {}) do
		if type(def.Element) == "string" then
			tl:case(Fx.ElementOf({ Id = def.Id, Base = def.Id, Species = def.Look and def.Look.Species }) == def.Element, def.Id .. " -> " .. def.Element)
			tl:case(Fx.ElementOf({ Id = def.Id .. "@Golden", Species = "Cat" }) == def.Element, def.Id .. "@Golden -> " .. def.Element)
		end
	end
	tl:case(Fx.ElementOf({ Id = "nope", Species = "Phoenix" }) == "Flame", "unknown pet -> its species' element")
	tl:case(Fx.ElementOf({ Id = "nope", Species = "Cat", Element = "Frost" }) == "Frost", "look.Element wins")
	tl:case(Fx.ElementOf({ Id = "nope" }, "Storm") == "Storm", "an explicit element wins")
	tl:case(Fx.ElementOf(nil) == "Celestial", "nil look -> Celestial")
	tl:report()
end)

----------------------------------------------------------------------------------------------------
S.p6evofx_build = guarded("p6evofx_build", function()
	local Fx, PB, PC = req("PetFx"), req("PetBuilder"), req("PetCatalog")
	if not T.check(Fx ~= nil and PB ~= nil and PC ~= nil, "PetFx, PetBuilder and PetCatalog load") then
		return
	end
	local all = T.tally("every evolved pet (Low detail) gets its effects within budget; stage 0 gets none")
	local stage2Seen, pulseSeen, auraColour = 0, 0, 0
	local noParts = T.tally("PetFx creates no Parts (same BasePart count as a NoFx build)")
	for _, def in ipairs(PC.Pets) do
		local maxStage = PB.MaxEvolution(def)
		local m0 = PB.Build(def, { Detail = "Low" })
		all:case(fxOf(m0) == nil, def.Id .. ": stage 0 has no PetFx")
		m0:Destroy()
		for stage = 1, maxStage do
			local m = PB.Build(def, { Detail = "Low", Evolved = stage })
			local fx = fxOf(m)
			local tag = fmt("%s stage %d", def.Id, stage)
			if all:case(fx ~= nil and fx:IsA("Attachment") and fx.Parent == m:FindFirstChild("Body"), tag .. ": Body.PetFx attachment") then
				local list, rate = emittersOf(fx)
				local light = fx:FindFirstChild("FxLight")
				all:case(#list == stage, tag .. fmt(": %d emitter(s)", #list))
				all:case(rate <= 4 + 1e-6 and rate > 0, tag .. fmt(": Low rate %.2f <= 4", rate))
				all:case(light ~= nil and light:IsA("PointLight") and math.abs(light.Brightness - (stage == 2 and 1 or 0.6)) < 1e-6 and light.Shadows == false,
					tag .. ": soft PointLight")
				all:case(fx:GetAttribute("Element") == (def.Element or fx:GetAttribute("Element")) and fx:GetAttribute("Stage") == stage, tag .. ": element " .. tostring(fx:GetAttribute("Element")))
				local tagged = true
				for _, pe in ipairs(list) do
					if not CollectionService:HasTag(pe, Fx.TAG) or pe.Texture ~= "" or not pe.Enabled then
						tagged = false
					end
				end
				all:case(tagged, tag .. ": emitters tagged PetFx, default sprite, on (server)")
				if stage == 2 then
					stage2Seen = stage2Seen + 1
					if (fx:GetAttribute("Pulse") or 0) > 0 then
						pulseSeen = pulseSeen + 1
					end
					local aura = fx:FindFirstChild("FxAura")
					local glow = PB.EvolutionColors(def, 2)
					local mid = aura and aura.Color.Keypoints[2].Value
					if mid and glow and math.abs(mid.R - glow.R) + math.abs(mid.G - glow.G) + math.abs(mid.B - glow.B) < 0.02 then
						auraColour = auraColour + 1
					end
				end
			end
			if def.Id == PC.Pets[1].Id or stage == 2 and stage2Seen <= 2 then
				local plain = PB.Build(def, { Detail = "Low", Evolved = stage, NoFx = true })
				noParts:case(fxOf(plain) == nil, tag .. ": NoFx skips the effects")
				noParts:case(parts(plain) == parts(m), tag .. fmt(": %d parts with effects, %d without", parts(m), parts(plain)))
				plain:Destroy()
			end
			m:Destroy()
		end
	end
	all:report()
	noParts:report()
	T.check(stage2Seen >= 10, "second evolutions were built", stage2Seen .. " stage-2 pets")
	T.check(pulseSeen == stage2Seen, "stage 2: the Neon Aura parts pulse (PB_Pulse)", pulseSeen .. " / " .. stage2Seen)
	T.check(auraColour == stage2Seen, "stage 2: the aura glints take the pet's own Glow colour", auraColour .. " / " .. stage2Seen)

	-- High detail, stage 2: within 12 and stronger than Low; idempotence, Clone, Clear, Viewport, Animate
	local epic = nil
	for _, def in ipairs(PC.Pets) do
		if PB.MaxEvolution(def) == 2 then
			epic = def
			break
		end
	end
	if not T.check(epic ~= nil, "a pet with a second evolution exists") then
		return
	end
	local hi = PB.Build(epic, { Detail = "High", Evolved = 2 })
	local lo = PB.Build(epic, { Detail = "Low", Evolved = 2 })
	local _, rHi = emittersOf(fxOf(hi))
	local _, rLo = emittersOf(fxOf(lo))
	T.check(rHi <= 12 + 1e-6 and rHi > rLo and rLo <= rHi * 0.5 + 1e-6, "High stage 2 rate <= 12, Low at most half", fmt("%.2f / %.2f", rHi, rLo))
	local one = PB.Build(epic, { Detail = "High", Evolved = 1 })
	local _, r1 = emittersOf(fxOf(one))
	T.check(r1 < rHi and fxOf(one).FxLight.Range < fxOf(hi).FxLight.Range, "stage 2 stronger than stage 1", fmt("rates %.2f < %.2f", r1, rHi))
	local nParts = parts(hi)
	local nDesc = #hi:GetDescendants()
	Fx.Apply(hi, { Id = epic.Id, Base = epic.Id }, 2, { Detail = "High", Scale = 1 })
	T.check(countFx(hi) == 1 and #hi:GetDescendants() == nDesc and parts(hi) == nParts, "Apply twice keeps one PetFx (same instance count)", countFx(hi) .. " PetFx, " .. #hi:GetDescendants() .. " vs " .. nDesc)
	local clone = hi:Clone()
	T.check(countFx(clone) == 1 and #emittersOf(fxOf(clone)) == 2, "a Clone carries one PetFx")
	Fx.Apply(clone, { Id = epic.Id, Base = epic.Id }, 1, { Detail = "High" })
	T.check(countFx(clone) == 1 and #emittersOf(fxOf(clone)) == 1 and fxOf(clone):GetAttribute("Stage") == 1, "re-applying on the Clone (stage 1) replaces it")
	local flagged = 0
	for _, p in ipairs(hi:GetChildren()) do
		if p:GetAttribute("PFX_Pulse") then
			flagged = flagged + 1
		end
	end
	Fx.Clear(hi)
	local left = 0
	for _, p in ipairs(hi:GetChildren()) do
		if p:GetAttribute("PFX_Pulse") then
			left = left + 1
		end
	end
	T.check(fxOf(hi) == nil and left == 0, "Clear removes PetFx and its pulse flags", flagged .. " flagged before, " .. left .. " after")
	T.check(parts(hi) == nParts, "Clear touches no Part")
	Fx.Clear(hi)
	T.check(Fx.Apply(hi, {}, 0, {}) == nil and fxOf(hi) == nil, "Clear twice / stage 0 are harmless")
	T.check(Fx.Apply(hi, {}, 2, { Viewport = true }) == nil and fxOf(hi) == nil, "viewports get no effects")
	T.check(Fx.Apply(hi, {}, 2, { Viewport = true, Fx = true }) ~= nil and countFx(hi) == 1, "viewports with opts.Fx = true get them")
	T.check(Fx.Apply(Instance.new("Model"), {}, 2, {}) == nil, "a model without a Body root is ignored")
	-- Animate with the effects on: no new instances, emitters still on the attachment
	local before = #hi:GetDescendants()
	local okAnim = pcall(function()
		for i = 1, 30 do
			PB.Animate(hi, i / 30, {})
		end
	end)
	T.check(okAnim and #hi:GetDescendants() == before and countFx(hi) == 1, "Animate runs on an evolved pet with effects, creating nothing")
	local scaled = PB.Build(epic, { Detail = "Low", Evolved = 2, Scale = 2.5 })
	local sfx = fxOf(scaled)
	T.check(sfx and sfx.FxLight.Range == 20 and math.abs(sfx.FxMain.Speed.Max - fxOf(lo).FxMain.Speed.Max * 2.5) < 1e-6, "effects scale with opts.Scale (light range, speed)")
	for _, m in ipairs({ hi, lo, one, clone, scaled }) do
		m:Destroy()
	end
end)

end -- IS_SERVER

if not IS_SERVER then

----------------------------------------------------------------------------------------------------
S.client_p6evofx = guarded("client_p6evofx", function()
	local Fx, PB, PC = req("PetFx"), req("PetBuilder"), req("PetCatalog")
	if not T.check(Fx ~= nil and PB ~= nil and PC ~= nil, "client: PetFx, PetBuilder and PetCatalog load") then
		return
	end
	local epic = nil
	for _, def in ipairs(PC.Pets) do
		if PB.MaxEvolution(def) == 2 then
			epic = def
			break
		end
	end
	local saved = Fx._Q.Mode
	local holder = Instance.new("Folder")
	holder.Name = "SmokeP6EvoFx"
	holder.Parent = workspace
	Fx.SetQuality("High")
	local a = PB.Build(epic, { Detail = "Low", Evolved = 2 })
	a.Parent = holder
	local la = emittersOf(fxOf(a))
	T.check(#la == 2 and la[1].Enabled and la[2].Enabled, "client High: the emitters are on")
	Fx.SetQuality("Low")
	T.check(not la[1].Enabled and not la[2].Enabled and fxOf(a).FxLight.Enabled, "client Low: emitters already in the game turn off, the light stays")
	local b = PB.Build(epic, { Detail = "Low", Evolved = 1 })
	b.Parent = holder
	local lb = emittersOf(fxOf(b))
	T.check(#lb == 1 and not lb[1].Enabled and fxOf(b).FxLight.Enabled, "client Low: a pet built later gets the light only")
	-- a server-built pet streaming in: its emitters arrive on and tagged
	local streamed = Instance.new("ParticleEmitter")
	streamed.Name = "FxMain"
	CollectionService:AddTag(streamed, Fx.TAG)
	local host = Instance.new("Part")
	host.Name = "StreamHost"
	host.Transparency = 1
	host.Anchored = true
	host.Parent = holder
	streamed.Parent = host
	Mock.Advance(0.1)
	T.check(not streamed.Enabled, "client Low: a server-built pet's emitters that stream in turn off")
	local untouched = Instance.new("ParticleEmitter")
	untouched.Parent = host
	untouched.Enabled = false
	Fx.SetQuality("High")
	T.check(la[1].Enabled and la[2].Enabled and lb[1].Enabled and streamed.Enabled, "client High again: exactly the emitters PetFx turned off are back on")
	T.check(untouched.Enabled == false, "client High: an emitter PetFx never touched stays as it was")
	T.check(Fx.Quality() == "High", "Quality() reports the mode")
	holder:Destroy()
	Fx._Q.Mode = saved
	if saved ~= nil then
		Fx.SetQuality(saved)
	end
end)

end -- not IS_SERVER

return S
