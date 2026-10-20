-- smoke_p6_portalfx.lua: the gates' animation (Phase 6 W2b, owner: homeportal; client/Controllers/PortalFxController.lua).
-- Loaded by tools/smoke.py in BOTH worlds:
--   p6portalfx_curves  (server, pure) the animation curves: every level stays in 0..1, the ring light runs round (its
--                      crest moves), gems twinkle one after another and rest, the swirl ripples outward, and nothing
--                      jumps between two 30 Hz frames (smooth, no flashing); Main.client.lua starts the controller
--   client_p6portalfx  (client) the real controller on real WorldStyle.BuildGate gates (hoop + crowned arch): it finds
--                      them by GateId (also gates that stream in and parts that arrive later), animates only the Neon
--                      Glow / Swirl / Gem parts, the GateLight and the Sparkles (values change over mock time and stay in
--                      range), never moves, resizes or creates a part, skips Neon parts MeshLibrary hides for a mesh,
--                      animates at most MAX_ACTIVE gates and none beyond RANGE studs, is static on Low graphics (every
--                      value back to the built one), and forgets a removed gate after restoring nothing it should not
-- Deterministic: no RNG; the time is the mock clock; every gate is destroyed and the quality mode restored at the end.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
local IS_SERVER = game:GetService("RunService"):IsServer()
local fmt = string.format

local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

-- the controller module (client tree; in the server world it is read as a plain chunk for the pure curves)
local function loadFx()
	if not IS_SERVER then
		local ok, inst = pcall(Mock.GetPath, ROOTS["client"] .. "/Controllers/PortalFxController")
		if ok and inst then
			local ok2, mod = pcall(require, inst)
			if ok2 and type(mod) == "table" then
				return mod
			end
		end
		return nil
	end
	local src = readFile("src/client/Controllers/PortalFxController.lua")
	if not src then
		return nil
	end
	local fn = (loadstring or load)(src, "=PortalFxController")
	if not fn then
		return nil
	end
	-- `script` is only touched lazily (quality()); give the chunk a harmless stand-in
	local env = setmetatable({ script = { Parent = nil } }, { __index = _G })
	if setfenv then
		setfenv(fn, env)
	end
	local ok, mod = pcall(fn)
	return ok and type(mod) == "table" and mod or nil
end

if IS_SERVER then

----------------------------------------------------------------------------------------------------
S.p6portalfx_curves = guarded("p6portalfx_curves", function()
	local Fx = loadFx()
	if not T.check(Fx ~= nil and type(Fx.RingLevel) == "function" and type(Fx.SwirlLevel) == "function" and type(Fx.GemLevel) == "function"
		and type(Fx.Breath) == "function" and type(Fx.Init) == "function" and type(Fx.Stop) == "function" and type(Fx.Stats) == "function",
		"PortalFxController loads (Init, Stop, Stats, Step, RingLevel, SwirlLevel, GemLevel, Breath)") then
		return
	end
	local K = Fx.K
	T.check(K.RANGE <= 160 and K.MAX_ACTIVE <= 8 and K.UPDATE_HZ <= 60 and K.RANGE_OUT >= K.RANGE, "budget: range <= 160 studs, <= 8 gates, <= 60 Hz",
		fmt("range %s, %s gates, %s Hz", tostring(K.RANGE), tostring(K.MAX_ACTIVE), tostring(K.UPDATE_HZ)))
	T.check(K.BREATH_PERIOD >= 2 and K.RING_PERIOD >= 2 and K.GEM_TWINKLE >= 0.5, "slow and soft: breath / lap >= 2 s, a twinkle lasts >= 0.5 s")
	local range = T.tally("every curve stays in 0..1")
	local smooth = T.tally("no jump between two 30 Hz frames (smooth, no flashing)")
	local dt = 1 / 30
	local worst = 0
	for i = 0, 360 do
		local t = i * 0.05
		for _, angle in ipairs({ -3, -1.5, 0, 0.7, 2, 3.1 }) do
			local a, b = Fx.RingLevel(t, angle, 0.4), Fx.RingLevel(t + dt, angle, 0.4)
			range:case(a >= 0 and a <= 1, fmt("ring t %.2f angle %.1f = %.3f", t, angle, a))
			worst = math.max(worst, math.abs(b - a))
		end
		for _, d in ipairs({ 0, 2, 4.5 }) do
			local a, b = Fx.SwirlLevel(t, d, 1), Fx.SwirlLevel(t + dt, d, 1)
			range:case(a >= 0 and a <= 1, fmt("swirl t %.2f = %.3f", t, a))
			worst = math.max(worst, math.abs(b - a))
		end
		for g = 1, 8 do
			local a, b = Fx.GemLevel(t, g, 8, 2), Fx.GemLevel(t + dt, g, 8, 2)
			range:case(a >= 0 and a <= 1, fmt("gem %d t %.2f = %.3f", g, t, a))
			worst = math.max(worst, math.abs(b - a))
		end
		local br = Fx.Breath(t, 0)
		range:case(br >= 0 and br <= 1, "breath")
	end
	range:report()
	smooth:case(worst <= 0.2, fmt("largest change in one frame %.3f", worst))
	smooth:report()
	-- the ring's crest moves round the ring
	local function crest(t)
		local best, at = -1, 0
		for k = 0, 71 do
			local a = k / 72 * 2 * math.pi
			local v = Fx.RingLevel(t, a, 0)
			if v > best then
				best, at = v, a
			end
		end
		return at
	end
	local c0, c1 = crest(0), crest(K.RING_PERIOD / 4)
	local moved = math.abs(((c1 - c0) + math.pi) % (2 * math.pi) - math.pi)
	T.check(moved > 1.2 and moved < 1.9, "the ring's light runs round: a quarter lap moves its crest ~90 degrees", fmt("%.2f rad", moved))
	-- gems twinkle in turn: gem 1 peaks before gem 2, and all rest at the end of the period
	local function peak(g)
		local best, at = -1, 0
		for k = 0, 400 do
			local t = k * 0.01
			local v = Fx.GemLevel(t, g, 3, 0)
			if v > best then
				best, at = v, t
			end
		end
		return at, best
	end
	local p1, v1 = peak(1)
	local p2 = peak(2)
	local p3 = peak(3)
	T.check(v1 > 0.9 and p1 < p2 and p2 < p3, "gems twinkle one after another (left -> right)", fmt("%.2f %.2f %.2f", p1, p2, p3))
	local quiet = true
	local period = math.max(K.GEM_PERIOD, 3 * K.GEM_SPACING + K.GEM_TWINKLE)
	for g = 1, 3 do
		if Fx.GemLevel(period - 0.05, g, 3, 0) > 0 then
			quiet = false
		end
	end
	T.check(quiet, "...then rest before the next sweep")
	T.check(Fx.SwirlLevel(1.0, 0, 0) ~= Fx.SwirlLevel(1.0, 4, 0), "the swirl ripples: the middle and the edge are out of step")
	-- Main.client.lua starts it with one pcall-guarded line
	local main = readFile("src/client/Main.client.lua") or ""
	T.check(main:find("PortalFxController", 1, true) ~= nil and main:find("pcall(PortalFx.Init)", 1, true) ~= nil,
		"Main.client.lua starts PortalFxController (pcall-guarded)")
	-- client only: no server code requires it
	local src = readFile("src/client/Controllers/PortalFxController.lua") or ""
	T.check(not src:find("Instance.new", 1, true) and not src:find(":Clone(", 1, true), "the controller never creates an instance (no Instance.new / Clone)")
	T.check(not src:find("%.CFrame%s*=") and not src:find("%.Size%s*=") and not src:find("%.Position%s*=") and not src:find("CanCollide%s*="),
		"the controller never writes CFrame / Size / Position / CanCollide")
end)

else

----------------------------------------------------------------------------------------------------
S.client_p6portalfx = guarded("client_p6portalfx", function()
	local Fx = loadFx()
	local okWS, WS = pcall(function()
		return require(Mock.GetPath(ROOTS["shared"] .. "/WorldStyle"))
	end)
	local okGQ, GQ = pcall(function()
		return require(Mock.GetPath(ROOTS["client"] .. "/GraphicsQuality"))
	end)
	if not T.check(Fx ~= nil and okWS and type(WS) == "table" and type(WS.BuildGate) == "function", "client: PortalFxController and WorldStyle.BuildGate load") then
		return
	end
	okGQ = okGQ and type(GQ) == "table" and type(GQ.Apply) == "function"
	local K = Fx.K
	Fx.Init() -- Main.client.lua did already: a second call is a no-op
	local cam = workspace.CurrentCamera
	local savedCam = cam and cam.CFrame
	local savedQ = okGQ and GQ.Effective() or "High"
	if okGQ then
		GQ.Apply("High")
	end
	if cam then
		cam.CFrame = CFrame.new(0, 12, -50)
	end
	local holder = Instance.new("Folder")
	holder.Name = "SmokeP6PortalFx"
	holder.Parent = workspace

	local function gate(id, x, glyph, pad, z)
		local m = WS.BuildGate(holder, CFrame.new(x, 0, z or 0), { Id = id, Title = id, Info = "", Color = "Blue", Glyph = glyph, Pad = pad })
		return m
	end
	local hoop = gate("FxHoop", 0, "cloud", true)
	local arch = gate("FxArch", 40, "crown", true)
	local far = gate("FxFar", 0, "bolt", false, 600)
	Mock.Advance(0.7)

	local function snapshot(model)
		local snap = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				snap[d] = { Color = d.Color, T = d.Transparency, CF = d.CFrame, Size = d.Size, Collide = d.CanCollide }
			elseif d:IsA("PointLight") then
				snap[d] = { B = d.Brightness, R = d.Range }
			end
		end
		return snap
	end
	local function countParts()
		local n = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") then
				n = n + 1
			end
		end
		return n
	end

	local rh, ra = Fx.Gate(hoop), Fx.Gate(arch)
	T.check(rh ~= nil and ra ~= nil and Fx.Gate(far) ~= nil, "the controller finds the gates by GateId (workspace.DescendantAdded)")
	if not (rh and ra) then
		holder:Destroy()
		return
	end
	T.check(#rh.Ring >= 8 and #rh.Swirl >= 1 and #rh.Gems >= 2 and rh.Light ~= nil and rh.Emitter ~= nil,
		"hoop: the Neon ring, the swirl, the gems (keystone + star crest), GateLight and Sparkles are tracked",
		fmt("ring %d swirl %d gems %d", #rh.Ring, #rh.Swirl, #rh.Gems))
	T.check(#ra.Ring >= 2 and #ra.Swirl >= 1 and #ra.Gems >= 6, "crowned arch: its glow frame, swirl and gems are tracked", fmt("ring %d swirl %d gems %d", #ra.Ring, #ra.Swirl, #ra.Gems))
	local onlyNeon = true
	for _, list in ipairs({ rh.Ring, rh.Swirl, rh.Gems, ra.Ring, ra.Swirl, ra.Gems }) do
		for _, e in ipairs(list) do
			if e.Part.Material ~= Enum.Material.Neon or not (e.Part.Name == "Glow" or e.Part.Name == "Swirl" or e.Part.Name == "Gem" or e.Part.Name == "StarGem") then
				onlyNeon = false
			end
		end
	end
	T.check(onlyNeon, "only Neon Glow / Swirl / Gem / StarGem parts are animated (stone, frame, trim: never)")

	-- base values (taken from a fresh gate with the same palette: the tracked gates may already be mid-animation)
	local ref = WS.BuildGate(nil, CFrame.new(0, 0, 0), { Id = "Ref", Title = "R", Info = "", Color = "Blue", Glyph = "cloud", Pad = true })
	local refSwirlT = nil
	for _, d in ipairs(ref:GetChildren()) do
		if d.Name == "Swirl" then
			refSwirlT = d.Transparency
		end
	end
	ref:Destroy()
	local before = snapshot(hoop)
	local nParts = countParts()
	local writes0 = Fx.Stats().Writes
	-- animate 3 s, sampling
	local colorsSeen, swirlMin, swirlMax, lightMin, lightMax = {}, 1, 0, math.huge, 0
	local ringPart = rh.Ring[1].Part
	local swirlPart = rh.Swirl[1].Part
	local farBase = snapshot(far)
	local farStill = true
	for _ = 1, 30 do
		Mock.Advance(0.1)
		colorsSeen[tostring(ringPart.Color)] = true
		swirlMin = math.min(swirlMin, swirlPart.Transparency)
		swirlMax = math.max(swirlMax, swirlPart.Transparency)
		lightMin = math.min(lightMin, rh.Light.Brightness)
		lightMax = math.max(lightMax, rh.Light.Brightness)
		for inst, v in pairs(farBase) do
			if inst:IsA("BasePart") and (inst.Color ~= v.Color or inst.Transparency ~= v.T) then
				farStill = false
			end
		end
	end
	local nColors = 0
	for _ in pairs(colorsSeen) do
		nColors = nColors + 1
	end
	T.check(nColors >= 5, "the glow ring changes colour over time (a soft light running round)", nColors .. " colours in 3 s")
	T.check(refSwirlT ~= nil and swirlMax - swirlMin >= 0.08 and swirlMin >= refSwirlT - K.SWIRL_AMP - 0.011 and swirlMax <= refSwirlT + K.SWIRL_AMP + 0.011,
		"the swirl breathes around its built transparency (+- SWIRL_AMP)", fmt("%.2f..%.2f around %s", swirlMin, swirlMax, tostring(refSwirlT)))
	local lb = rh.LightBase
	T.check(lightMax - lightMin > 0.1 and lightMin >= lb * (1 - K.LIGHT_AMP) - 0.01 and lightMax <= lb * (1 + K.LIGHT_AMP) + 0.01,
		"GateLight pulses softly (x 1 +- LIGHT_AMP)", fmt("%.2f..%.2f (base %.2f)", lightMin, lightMax, lb))
	local okAcc, acc = pcall(function()
		return rh.Emitter.Acceleration
	end)
	T.check(not okAcc or (typeof(acc) == "Vector3" and acc.Y > 0), "the sparkles drift upward while the gate is animated")
	T.check(Fx.Stats().Writes > writes0, "property writes happen", tostring(Fx.Stats().Writes - writes0))
	T.check(farStill, "a gate " .. K.RANGE .. "+ studs from the camera stands still (distance cull)")
	-- never moved, resized, made to collide, and no parts created per frame
	local geomOk = true
	local after = snapshot(hoop)
	for inst, v in pairs(before) do
		local a = after[inst]
		if inst:IsA("BasePart") and (not a or a.CF ~= v.CF or a.Size ~= v.Size or a.Collide ~= v.Collide) then
			geomOk = false
		end
	end
	T.check(geomOk, "no gate part is moved, resized or changes CanCollide")
	T.eq(countParts(), nParts, "no parts are created while animating (workspace BasePart count unchanged)")
	-- writes only on change: a second of animation writes far fewer than (parts x frames)
	local w0 = Fx.Stats().Writes
	Mock.Advance(1)
	local per = Fx.Stats().Writes - w0
	local tracked = Fx.Stats().Parts
	T.check(per < tracked * K.UPDATE_HZ, "a property is written only when its value changes", fmt("%d writes in 1 s for %d parts", per, tracked))

	-- Low graphics: static, every value back to the built one
	if okGQ then
		local dirtyStill = function()
			for _, list in ipairs({ rh.Ring, rh.Swirl, rh.Gems }) do
				for _, e in ipairs(list) do
					if e.Part.Color ~= e.Base or (e.BaseT and e.Part.Transparency ~= e.BaseT) then
						return e.Part.Name
					end
				end
			end
			if rh.Light.Brightness ~= rh.LightBase then
				return "GateLight"
			end
			return nil
		end
		GQ.Apply("Low")
		Mock.Advance(0.7)
		local bad = dirtyStill()
		T.check(bad == nil and Fx.Stats().Active == 0, "Low graphics: every gate is static and back to its built values", tostring(bad))
		Mock.Advance(1)
		T.check(dirtyStill() == nil, "...and stays static")
		GQ.Apply("High")
		Mock.Advance(1.5)
		T.check(Fx.Stats().Active >= 2, "High again: the gates animate again", tostring(Fx.Stats().Active))
	else
		T.check(false, "client/GraphicsQuality loads (Apply / Effective)")
	end

	-- distance cull: the camera walks away
	if cam then
		cam.CFrame = CFrame.new(0, 12, -2000)
		Mock.Advance(0.7)
		T.check(Fx.Stats().Active == 0 and swirlPart.Transparency == rh.Swirl[1].BaseT and ringPart.Color == rh.Ring[1].Base,
			"the camera " .. K.RANGE .. "+ studs away: no gate animates, values restored")
		cam.CFrame = CFrame.new(0, 12, -50)
		Mock.Advance(0.7)
	end

	-- at most MAX_ACTIVE gates animate at once
	local many = {}
	for i = 1, K.MAX_ACTIVE + 3 do
		many[i] = gate("FxMany" .. i, (i - 6) * 12, "cloud", false, 40) -- all within ~80 studs of the camera
	end
	Mock.Advance(0.7)
	local st = Fx.Stats()
	T.check(st.Active == K.MAX_ACTIVE, "at most MAX_ACTIVE gates animate at once (the nearest)", st.Active .. " of " .. st.Gates)

	-- streaming: a gate model whose parts arrive later (rescan), a Neon part MeshLibrary hides (skipped)
	local late = Instance.new("Model")
	late.Name = "Portal_Late"
	late:SetAttribute("GateId", "Late")
	late.Parent = holder
	Mock.Advance(0.6)
	local rl = Fx.Gate(late)
	T.check(rl ~= nil and rl.Parts == 0, "a gate model that streams in empty is tracked")
	local donor = WS.BuildGate(nil, CFrame.new(-10, 0, -10), { Id = "Late", Title = "L", Info = "", Color = "Red", Glyph = "cloud", Pad = false })
	for _, c in ipairs(donor:GetChildren()) do
		c.Parent = late
	end
	donor:Destroy()
	Mock.Advance(0.7)
	T.check(rl and rl.Parts >= 10 and #rl.Ring >= 8, "parts that stream in later are picked up (rescan)", rl and tostring(rl.Parts) or "nil")
	-- MeshLibrary.Tag on the gate keeping only the swirl: the glow ring would be hidden for the mesh, so it is skipped
	late:SetAttribute("ML_DressKey", "gate_test")
	late:SetAttribute("ML_Keep", "Swirl")
	rl.Dirty = true
	Mock.Advance(0.7)
	T.check(#rl.Ring == 0 and #rl.Swirl >= 1, "Neon parts a mesh dress hides are never animated (ML_Keep is honoured)", fmt("ring %d swirl %d", #rl.Ring, #rl.Swirl))

	-- removal: the record is forgotten, nothing errors
	local errors0 = #Mock.Errors
	local n0 = Fx.Stats().Gates
	hoop:Destroy()
	Mock.Advance(0.7)
	T.check(Fx.Gate(hoop) == nil and Fx.Stats().Gates == n0 - 1, "a removed gate is forgotten", tostring(Fx.Stats().Gates))
	holder:Destroy()
	Mock.Advance(0.7)
	T.check(Fx.Stats().Gates == 0 or Fx.Gate(arch) == nil, "removing the folder forgets every gate in it")
	T.eq(#Mock.Errors, errors0, "no script errors while gates come and go")

	if okGQ then
		GQ.Apply(savedQ)
	end
	if cam and savedCam then
		cam.CFrame = savedCam
	end
end)

end

return S
