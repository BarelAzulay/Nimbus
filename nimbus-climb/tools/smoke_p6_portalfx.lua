-- smoke_p6_portalfx.lua: the gates' animation (Phase 6 W2b, owner: homeportal; client/Controllers/PortalFxController.lua).
-- Loaded by tools/smoke.py in BOTH worlds:
--   p6portalfx_curves  (server, pure) the animation curves: every level stays in 0..1, the ring light runs round (its
--                      crest moves), gems twinkle one after another and rest, the swirl ripples outward, and nothing
--                      jumps between two 30 Hz frames (smooth, no flashing); Main.client.lua starts the controller
--                      PortalVortex.Mode, the texture layer files + TextureIds stub
--   client_p6portalfx  (client) the vortex in both modes: TextureIds empty = the fallback (Beam arms turning, inward
--                      streaks, rim crackle bursts, the swirl as deep backdrop), fake ids = the SurfaceGui layers (glow,
--                      not on top, arms turning clockwise, the fine layer faster, streaks shrinking inward, a crackle
--                      within 3 s, the swirl hidden; the arch keeps its swirl); built once, nothing per frame, client-only
--                      planes in workspace.PortalFxLocal; and the real controller on real WorldStyle.BuildGate gates: it finds
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
	local _, nNew = src:gsub("Instance%.new%(", "")
	T.check(nNew == 1 and src:find('Instance.new("Folder")', 1, true) ~= nil and not src:find(":Clone(", 1, true),
		"the controller creates only its local folder (the vortex instances are PortalVortex's, built once)")
	T.check(not src:find("%.CFrame%s*=") and not src:find("%.Size%s*=") and not src:find("%.Position%s*=") and not src:find("CanCollide%s*="),
		"the controller never writes CFrame / Size / Position / CanCollide")
	-- PortalVortex: the mode, the layer list, client-only parts that never collide
	local vsrc = readFile("src/client/PortalVortex.lua") or ""
	local fnV = (loadstring or load)(vsrc, "=PortalVortex")
	local okV, PV = false, nil
	if fnV then
		okV, PV = pcall(fnV)
	end
	if T.check(okV and type(PV) == "table" and type(PV.Mode) == "function", "PortalVortex loads (Mode, Layout, Build, Show, Animate, Destroy)") then
		T.eq(PV.Mode({}), "Fallback", "PortalVortex.Mode: no texture ids = the effects-only fallback")
		local ids = {}
		for i, key in ipairs(PV.K.TEXTURE_KEYS) do
			ids[key] = 100 + i
		end
		T.eq(PV.Mode(ids), "Texture", "PortalVortex.Mode: every layer id present = the textured vortex")
		ids.vortex_arms = nil
		T.eq(PV.Mode(ids), "Fallback", "...one missing id falls back")
		T.check(PV.K.ARMS_SPEED > 0 and PV.K.FINE_SPEED > PV.K.ARMS_SPEED and PV.K.CRACKLE_GAP[1] >= 0.5, "two speeds (the fine layer faster), crackles at least 0.5 s apart (soft, no strobe)")
	end
	T.check(not vsrc:find("CanCollide = true", 1, true) and vsrc:find("CanCollide = false", 1, true) ~= nil and vsrc:find("CanQuery = false", 1, true) ~= nil
		and vsrc:find("CanTouch = false", 1, true) ~= nil, "the vortex planes never collide, query or touch")
	-- the texture layers exist and TextureIds is numbers only (empty until the upload session)
	local ti = readFile("src/shared/TextureIds.lua") or ""
	T.check(ti:find("return {", 1, true) ~= nil, "src/shared/TextureIds.lua exists (generated by upload_assets.py --textures)")
	local idx = readFile("blender/textures/textures.json") or ""
	local missing = {}
	for _, key in ipairs({ "vortex_disc", "vortex_core", "vortex_arms", "vortex_fine", "vortex_streaks", "vortex_rim", "vortex_crackle_1", "vortex_crackle_4" }) do
		if not idx:find('"' .. key .. '"', 1, true) or not readFile("blender/textures/vortex/" .. key .. ".png") then
			missing[#missing + 1] = key
		end
	end
	T.check(#missing == 0, "blender/textures: every vortex layer PNG is built and indexed", table.concat(missing, ", "))
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
	local okV, V = pcall(function()
		return require(Mock.GetPath(ROOTS["client"] .. "/PortalVortex"))
	end)
	if not T.check(Fx ~= nil and okWS and type(WS) == "table" and type(WS.BuildGate) == "function" and okV and type(V) == "table",
		"client: PortalFxController, PortalVortex and WorldStyle.BuildGate load") then
		return
	end
	okGQ = okGQ and type(GQ) == "table" and type(GQ.Apply) == "function"
	local K = Fx.K
	Fx.Init() -- Main.client.lua did already: a second call is a no-op
	Fx.SetTextureIds({}) -- shared/TextureIds is empty before the upload session: the fallback vortex
	local cam = workspace.CurrentCamera
	local savedCam = cam and cam.CFrame
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
		return WS.BuildGate(holder, CFrame.new(x, 0, z or 0), { Id = id, Title = id, Info = "", Color = "Blue", Glyph = glyph, Pad = pad })
	end
	local function snapshot(model)
		local snap = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				snap[d] = { Color = d.Color, T = d.Transparency, CF = d.CFrame, Size = d.Size, Collide = d.CanCollide, Query = d.CanQuery, Parent = d.Parent }
			end
		end
		return snap
	end
	local function count(root, cls)
		local n = 0
		for _, d in ipairs(root:GetDescendants()) do
			if not cls or d:IsA(cls) then
				n = n + 1
			end
		end
		return n
	end
	local hoop = gate("FxHoop", 0, "cloud", true)
	local arch = gate("FxArch", 40, "crown", true)
	local far = gate("FxFar", 0, "bolt", false, 600)
	local hoopBefore = snapshot(hoop)
	Mock.Advance(0.7)

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

	------------------------------------------------------------------------------------------------
	-- the fallback vortex (no texture ids): beams + particles, built once, client-only
	------------------------------------------------------------------------------------------------
	local vf = rh.Vortex
	local localFolder = workspace:FindFirstChild("PortalFxLocal")
	if T.check(vf ~= nil and vf.Mode == "Fallback" and vf.Shown, "TextureIds empty: the hoop shows the FALLBACK vortex") then
		local beams = 0
		for _, b in ipairs(vf.Beams) do
			if b:IsA("Beam") and b.Enabled and b.Attachment0 and b.Attachment1 then
				beams = beams + 1
			end
		end
		T.eq(beams, V.K.ARMS + V.K.FINE, "fallback: broad + fine spiral-arm Beams, all on")
		T.check(vf.Streaks:IsA("ParticleEmitter") and vf.Streaks.Enabled and vf.Streaks.ShapeInOut == Enum.ParticleEmitterShapeInOut.Inward
			and vf.Streaks.Shape == Enum.ParticleEmitterShape.Disc, "fallback: light streaks pulled inward (Disc, Inward), on")
		T.check(localFolder ~= nil and vf.Plane.Parent == localFolder and vf.SpinA.Parent == localFolder and count(hoop, "Beam") == 0,
			"the vortex lives in workspace.PortalFxLocal, nothing is added to the gate")
		local planeOk = true
		for _, p in ipairs({ vf.Plane, vf.SpinA, vf.SpinB }) do
			if not (p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch and p.Transparency == 1) then
				planeOk = false
			end
		end
		T.check(planeOk, "its planes are invisible, anchored, never collide / query / touch")
		local look = V.SwirlLook(vf)
		T.check(rh.Swirl[1].Part.Transparency == look.Transparency and rh.Swirl[1].Part.Color == look.Color, "the old swirl becomes the vortex's deep backdrop")
		local a0 = vf.SpinA.CFrame
		local emitted0 = Mock.Stats_ and Mock.Stats_.particlesEmitted or 0
		local inst0 = count(localFolder)
		local parts0 = count(workspace, "BasePart")
		Mock.Advance(2.5)
		T.check(vf.SpinA.CFrame ~= a0 and (vf.SpinA.CFrame.Position - a0.Position).Magnitude < 1e-3, "the arms turn in place (the spinner rotates about the centre)")
		T.check(not Mock.Stats_ or Mock.Stats_.particlesEmitted > emitted0, "rim crackles burst at seeded times (Emit)")
		T.eq(count(localFolder), inst0, "no instance is created per frame (the vortex's folder keeps its count)")
		T.eq(count(workspace, "BasePart"), parts0, "no part is created per frame")
	end

	-- the Neon ring, gems and light keep their soft animation
	local colorsSeen, lightMin, lightMax = {}, math.huge, 0
	local ringPart = rh.Ring[1].Part
	local farBase = snapshot(far)
	local farStill = true
	for _ = 1, 30 do
		Mock.Advance(0.1)
		colorsSeen[tostring(ringPart.Color)] = true
		lightMin = math.min(lightMin, rh.Light.Brightness)
		lightMax = math.max(lightMax, rh.Light.Brightness)
		for inst, v in pairs(farBase) do
			if inst.Color ~= v.Color or inst.Transparency ~= v.T then
				farStill = false
			end
		end
	end
	local nColors = 0
	for _ in pairs(colorsSeen) do
		nColors = nColors + 1
	end
	T.check(nColors >= 5, "the glow ring changes colour over time (a soft light running round)", nColors .. " colours in 3 s")
	local lb = rh.LightBase
	T.check(lightMax - lightMin > 0.1 and lightMin >= lb * (1 - K.LIGHT_AMP) - 0.01 and lightMax <= lb * (1 + K.LIGHT_AMP) + 0.01,
		"GateLight pulses softly (x 1 +- LIGHT_AMP)", fmt("%.2f..%.2f (base %.2f)", lightMin, lightMax, lb))
	T.check(farStill and Fx.Gate(far).Vortex == nil, "a gate " .. K.RANGE .. "+ studs from the camera stands still and builds no vortex (distance cull)")
	-- the gate's own parts: never moved, resized, re-parented, made to collide
	local geomOk = true
	local after = snapshot(hoop)
	for inst, v in pairs(hoopBefore) do
		local a = after[inst]
		if not a or a.CF ~= v.CF or a.Size ~= v.Size or a.Collide ~= v.Collide or a.Query ~= v.Query or a.Parent ~= v.Parent then
			geomOk = false
		end
	end
	T.check(geomOk, "no gate part is moved, resized, re-parented or changes CanCollide / CanQuery")
	local w0 = Fx.Stats().Writes
	Mock.Advance(1)
	local per = Fx.Stats().Writes - w0
	T.check(per < (Fx.Stats().Parts + 20) * K.UPDATE_HZ, "a property is written only when its value changes", fmt("%d writes in 1 s", per))

	------------------------------------------------------------------------------------------------
	-- the textured vortex (fake ids): SurfaceGui layers turning at their own speeds
	------------------------------------------------------------------------------------------------
	local fake = {}
	for i, key in ipairs({ "vortex_disc", "vortex_core", "vortex_arms", "vortex_fine", "vortex_streaks", "vortex_rim",
		"vortex_crackle_1", "vortex_crackle_2", "vortex_crackle_3", "vortex_crackle_4" }) do
		fake[key] = 7000 + i
	end
	local oldPlane = vf and vf.Plane
	Fx.SetTextureIds(fake)
	Mock.Advance(0.7)
	local vt = rh.Vortex
	T.check(oldPlane == nil or oldPlane.Parent == nil, "switching modes destroys the old vortex")
	if T.check(vt ~= nil and vt.Mode == "Texture" and vt.Shown and vt.Front and vt.Front.Enabled, "fake TextureIds: the hoop shows the TEXTURED vortex") then
		local g = vt.Front
		T.check(g:IsA("SurfaceGui") and g.LightInfluence == 0 and g.Brightness >= 1.5 and g.AlwaysOnTop == false and g.Adornee == vt.Plane,
			"its SurfaceGui glows (LightInfluence 0, Brightness 2) and is not drawn over the world (AlwaysOnTop false)")
		local byName = {}
		for _, e in ipairs(vt.Layers) do
			byName[e.Spec.Name] = e.Label
		end
		T.check(byName.Arms and byName.Arms.Image == "rbxassetid://" .. fake.vortex_arms and byName.Rim and byName.Disc, "the layers use the ids of TextureIds")
		T.check(rh.Swirl[1].Part.Transparency == 1, "the old Neon swirl is hidden locally behind the textured disc")
		local arms0, fine0, s0 = byName.Arms.Rotation, byName.Fine.Rotation, byName.StreaksA.Size
		local crackleSeen = false
		for _ = 1, 30 do
			Mock.Advance(0.1)
			for _, c in ipairs(vt.Crackles) do
				if c.Label.Visible and c.Label.ImageTransparency < 0.9 then
					crackleSeen = true
				end
			end
		end
		local function turned(a, b)
			return ((b - a) % 360)
		end
		local dA, dF = turned(arms0, byName.Arms.Rotation), turned(fine0, byName.Fine.Rotation)
		T.check(dA > 0 and dF > 0 and math.abs(dA - (V.K.ARMS_SPEED * 3) % 360) < 25, "the arms turn clockwise at ARMS_SPEED", fmt("%.1f / %.1f deg in 3 s", dA, dF))
		T.check(byName.StreaksA.Size ~= s0, "the streak layers shrink toward the centre (pulled inward)")
		T.check(crackleSeen, "a lightning crackle flickers on the rim within 3 s (seeded)")
		local ar = Fx.Gate(arch)
		T.check(ar and ar.Vortex and ar.Vortex.Arch and ar.Swirl[1].Part.Transparency < 1, "the crowned arch keeps its swirl as backdrop behind a round vortex")
	end

	-- Low graphics: a still vortex, the ring, gems and light at their built values
	if okGQ then
		GQ.Apply("Low")
		Mock.Advance(0.7)
		local bad = nil
		for _, list in ipairs({ rh.Ring, rh.Gems }) do
			for _, e in ipairs(list) do
				if e.Part.Color ~= e.Base then
					bad = e.Part.Name
				end
			end
		end
		if rh.Light.Brightness ~= rh.LightBase then
			bad = "GateLight"
		end
		T.check(bad == nil, "Low graphics: the ring, gems and light are back to their built values", tostring(bad))
		local v = rh.Vortex
		local rot0 = v and v.Layers and v.Layers[3].Label.Rotation
		Mock.Advance(1.5)
		T.check(v and v.Shown and v.Layers[3].Label.Rotation == rot0, "Low graphics: the vortex stays, still (no turning)")
		Fx.SetTextureIds({})
		Mock.Advance(0.7)
		local vl = rh.Vortex
		local cf0 = vl and vl.SpinA.CFrame
		Mock.Advance(1)
		T.check(vl and vl.Shown and not vl.Streaks.Enabled and vl.SpinA.CFrame == cf0, "Low graphics, fallback: still arms, no streaks")
		GQ.Apply("High")
		Mock.Advance(1.5)
		T.check(Fx.Stats().Active >= 2 and rh.Vortex and rh.Vortex.Streaks.Enabled, "High again: the gates and their vortex move again", tostring(Fx.Stats().Active))
	else
		T.check(false, "client/GraphicsQuality loads (Apply / Effective)")
	end

	-- distance cull: the camera walks away -> the vortex hides, the swirl comes back
	if cam then
		cam.CFrame = CFrame.new(0, 12, -2000)
		Mock.Advance(0.7)
		local vv = rh.Vortex
		T.check(Fx.Stats().Active == 0 and (vv == nil or not vv.Shown) and rh.Swirl[1].Part.Transparency == rh.Swirl[1].BaseT
			and ringPart.Color == rh.Ring[1].Base, "the camera " .. K.RANGE .. "+ studs away: no gate animates, the vortex hides, values restored")
		cam.CFrame = CFrame.new(0, 12, -50)
		Mock.Advance(0.7)
	end

	-- at most MAX_ACTIVE gates animate (and show a vortex) at once
	local many = {}
	for i = 1, K.MAX_ACTIVE + 3 do
		many[i] = gate("FxMany" .. i, (i - 6) * 12, "cloud", false, 40) -- all within ~80 studs of the camera
	end
	Mock.Advance(0.7)
	local st = Fx.Stats()
	T.check(st.Active == K.MAX_ACTIVE and st.Vortices <= K.MAX_ACTIVE, "at most MAX_ACTIVE gates animate and show a vortex at once", st.Active .. " / " .. st.Vortices .. " of " .. st.Gates)
	local built = Fx.Stats().Built
	Mock.Advance(2)
	T.eq(Fx.Stats().Built, built, "every vortex is built once (no rebuild while it animates)")

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
	late:SetAttribute("ML_DressKey", "gate_test")
	late:SetAttribute("ML_Keep", "Swirl")
	rl.Dirty = true
	Mock.Advance(0.7)
	T.check(#rl.Ring == 0 and #rl.Swirl >= 1, "Neon parts a mesh dress hides are never animated (ML_Keep is honoured)", fmt("ring %d swirl %d", #rl.Ring, #rl.Swirl))

	-- removal: the record and its vortex go, nothing errors
	local errors0 = #Mock.Errors
	local n0 = Fx.Stats().Gates
	local plane = rh.Vortex and rh.Vortex.Plane
	hoop:Destroy()
	Mock.Advance(0.7)
	T.check(Fx.Gate(hoop) == nil and Fx.Stats().Gates == n0 - 1 and (plane == nil or plane.Parent == nil), "a removed gate is forgotten and its vortex destroyed", tostring(Fx.Stats().Gates))
	holder:Destroy()
	Mock.Advance(0.7)
	T.check(Fx.Gate(arch) == nil and count(workspace:FindFirstChild("PortalFxLocal") or holder, "BasePart") == 0, "removing the folder forgets every gate and clears every vortex")
	T.eq(#Mock.Errors, errors0, "no script errors while gates come and go")

	Fx.SetTextureIds({})
	if okGQ then
		GQ.Apply("Auto")
	end
	if cam and savedCam then
		cam.CFrame = savedCam
	end
end)

end

return S
