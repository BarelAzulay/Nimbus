-- smoke_bug13_fountain.lua: bug #13 "improve waterful design and fix animation to it" (art wave, the player's pick:
-- option C "Sky-Oasis Steps"). Loaded by tools/smoke.py in the server world and the client world:
--   bug13fountain_server (server) the booted lobby's Fountain model (LobbyBuilder buildFountain):
--                        the bug: no emitter sits inside the Nimbus statue (the old Spray started at centre + 10.6, in
--                        its body), none uses the sparkle star, none is named Spray, every emitter texture is one of
--                        Roblox's own particle textures (nothing to upload); the animation: three falls, each a Core
--                        Beam + >= 2 Streak Beams with a scrolling texture (TextureSpeed ~= 0, Wrap) between attachments
--                        on the "Falls" anchor (tagged OasisFalls), the lip above the impact, the impact on the water /
--                        the island it lands on, the streaks scroll lip -> impact (Oasis.Flow = -1: the Beam docs say a
--                        positive TextureSpeed runs A0 -> A1, and A0 is the impact); a Splash part at every impact with
--                        Drops and Foam, a Ripples part with flat ripple rings; the big fall has Mist and LipDrops;
--                        phone budget: Splash / LipDrops / SpringBubbles are NC_Detail (Low graphics parks them) and Low
--                        leaves at most 3 fountain emitters running (the ripples); the climbs: LadderTruss and
--                        RopeTruss are colliding TrussParts whose tops sit on the upper island (0..0.2 above its grass)
--                        and whose bottoms are reachable from the lower one; the statue stands on the nest floor at
--                        OASIS.StatueScale; the paper boat is a tagged OasisBoat root with ML_Weld, its sail Anchored
--                        under it (every lobby part stays Anchored; FountainFx moves both);
--                        the four oasis meshes are tagged (or absent from MeshIds) and their committed manifests fit
--                        OASIS (inside the rim, the islands' top under the statue, the water at its height)
--   client_bug13fountain_boat (client) FountainFx: a tagged boat near the camera drifts / bobs (small, smooth), its
--                        anchored sail keeps its offset from the root while moving, Stats counts it; Low graphics and
--                        Stop() put both back exactly at rest; a boat beyond RANGE rests
-- Deterministic: mock clock only. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, max, sqrt = math.abs, math.max, math.sqrt
local fmt = string.format

local function hdist(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return sqrt(dx * dx + dz * dz)
end

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K

	local function requireAt(key)
		local inst = K.moduleInstance(key)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		if ok and type(result) == "table" then
			return result
		end
		return nil
	end

	-- the lobby's fountain model: the Model holding the "Falls" anchor
	local function findFountain()
		local lobby = workspace:FindFirstChild("NimbusLobby")
		if not lobby then
			return nil
		end
		for _, d in ipairs(lobby:GetDescendants()) do
			if d:IsA("Model") and d.Name == "Fountain" and d:FindFirstChild("Falls") then
				return d
			end
		end
		return nil
	end

	local function inBox(cf, size, pos, pad)
		local p = cf:PointToObjectSpace(pos)
		return abs(p.X) <= size.X / 2 + pad and abs(p.Y) <= size.Y / 2 + pad and abs(p.Z) <= size.Z / 2 + pad
	end

	S.bug13fountain_server = guarded("bug13fountain_server", function()
		if not K.needBoot() then
			return
		end
		local LB = requireAt("server/Services/LobbyBuilder")
		local O = LB and LB._Oasis
		if not T.check(type(O) == "table" and type(O.Falls) == "table", "bug13 fountain: LobbyBuilder._Oasis (the layout) is exported") then
			return
		end
		local m = findFountain()
		if not T.check(m ~= nil, "bug13 fountain: the lobby has its Fountain model (with the Falls anchor)") then
			return
		end
		local anchor = m:FindFirstChild("Falls")
		local ground = anchor.CFrame -- the fountain frame (origin = the ground under the pool centre)
		local CS = game:GetService("CollectionService")
		T.check(CS:HasTag(anchor, "OasisFalls"), "bug13 fountain: the Falls anchor is tagged OasisFalls (client FountainFx finds it)")
		T.check(abs(ground.UpVector.Y - 1) < 1e-3, "bug13 fountain: the fountain frame is upright")
		local function L(v)
			return ground:PointToObjectSpace(v)
		end

		-- the statue: on the nest floor, at OASIS.StatueScale
		local statue = m:FindFirstChild("NimbusStatue")
		local sCf, sSize
		if statue then
			sCf, sSize = statue:GetBoundingBox()
			local lowY = L(sCf.Position).Y - sSize.Y / 2
			local c = L(sCf.Position)
			T.check(abs(lowY - O.Nest.Floor) <= 0.3, "bug13 fountain: Nimbus stands on the nest floor (+-0.3)", fmt("low %.2f floor %.2f", lowY, O.Nest.Floor))
			T.check(hdist(c, Vector3.new(O.Nest.C[1], 0, O.Nest.C[2])) <= 1.5, "bug13 fountain: ...in the nest (centre within 1.5 studs)", fmt("%.2f, %.2f", c.X, c.Z))
			T.check(O.StatueScale <= 2.2, "bug13 fountain: the statue is scaled down (<= 2.2) so the top island shows", tostring(O.StatueScale))
		else
			T.info("bug13 fountain: no NimbusStatue", "PetBuilder / PetCatalog not in this build: the statue checks are skipped")
		end

		-- the bug: the water's emitters (no spray in the statue, no sparkle star, built-in textures only). The statue's
		-- own pet effects (PetBuilder's RaritySparkles) belong to Nimbus, not to the water: skipped here.
		local statueParts = {}
		if statue then
			for _, d in ipairs(statue:GetDescendants()) do
				if d:IsA("BasePart") then
					statueParts[#statueParts + 1] = d
				end
			end
		end
		local emitters, inside, sparkle, sprayNamed, foreign = 0, {}, {}, {}, {}
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("ParticleEmitter") and not (statue and d:IsDescendantOf(statue)) then
				emitters = emitters + 1
				local host = d.Parent
				if host:IsA("BasePart") then
					for _, sp in ipairs(statueParts) do
						if inBox(sp.CFrame, sp.Size, host.Position, 0.1) then
							inside[#inside + 1] = host.Name .. "/" .. d.Name .. " in " .. sp.Name
							break
						end
					end
				end
				local tex = string.lower(tostring(d.Texture))
				if tex:find("sparkle") then
					sparkle[#sparkle + 1] = d.Name
				end
				if tex ~= "" and tex:sub(1, 30) ~= "rbxasset://textures/particles/" then
					foreign[#foreign + 1] = d.Name .. "=" .. tex
				end
			end
			if d.Name == "Spray" then
				sprayNamed[#sprayNamed + 1] = d:GetFullName()
			end
		end
		T.check(emitters >= 10, "bug13 fountain: the water has its emitters (splashes, foam, ripples, mist, bubbles)", tostring(emitters))
		T.check(#inside == 0, "bug13 fountain: no emitter starts inside the Nimbus statue (the old spray did)", table.concat(inside, ", "))
		T.check(#sparkle == 0, "bug13 fountain: no emitter uses the sparkle star (water, not glitter)", table.concat(sparkle, ", "))
		T.check(#sprayNamed == 0, "bug13 fountain: the old Spray is gone", table.concat(sprayNamed, ", "))
		T.check(#foreign == 0, "bug13 fountain: every emitter texture is Roblox's own (rbxasset particles: nothing to upload)", table.concat(foreign, ", "))
		-- phones: GraphicsQuality's Low parks every NC_Detail-tagged decor (emitters off). The fountain keeps only its
		-- ripple rings (and the Beams) running on Low.
		local function detailed(inst)
			local p = inst
			while p and p ~= m.Parent do
				if CS:HasTag(p, "NC_Detail") then
					return true
				end
				p = p.Parent
			end
			return false
		end
		local lowOn, lowNames = 0, {}
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("ParticleEmitter") and not (statue and d:IsDescendantOf(statue)) and not detailed(d) then
				lowOn = lowOn + 1
				lowNames[#lowNames + 1] = d.Parent.Name .. "/" .. d.Name
			end
		end
		T.check(lowOn <= 3, "bug13 fountain: Low graphics leaves at most 3 fountain emitters running (the ripples)", lowOn .. ": " .. table.concat(lowNames, ", "))
		for _, n in ipairs({ "Fall1Splash", "Fall2Splash", "Fall3Splash", "Fall2LipDrops", "SpringBubbles" }) do
			local p = m:FindFirstChild(n)
			T.check(p ~= nil and CS:HasTag(p, "NC_Detail"), "bug13 fountain: " .. n .. " is NC_Detail (Low graphics parks it)")
		end

		-- the animation: the falls
		T.check(#O.Falls == 3, "bug13 fountain: three falls (spring -> middle, the big one into the pool, the west seep)")
		for i, f in ipairs(O.Falls) do
			local tag = "Fall" .. i
			local core = anchor:FindFirstChild(tag .. "Core")
			local okCore = core and core:IsA("Beam") and core.Attachment0 and core.Attachment1
				and core.Attachment0.Parent == anchor and core.Attachment1.Parent == anchor
			if T.check(okCore, "bug13 fountain: fall " .. i .. " has its Core Beam between two attachments on the anchor") then
				local imp = L(core.Attachment0.WorldPosition)
				local lip = L(core.Attachment1.WorldPosition)
				T.check(lip.Y > imp.Y + 1.5, "bug13 fountain: fall " .. i .. ": Attachment1 (the lip) is above Attachment0 (the impact)", fmt("lip %.2f impact %.2f", lip.Y, imp.Y))
				T.check(abs(imp.Y - f.Land) <= 0.05, "bug13 fountain: fall " .. i .. " lands at its Land height", fmt("%.2f vs %.2f", imp.Y, f.Land))
				T.check(abs(lip.Y - f.Lip[2]) <= 0.3 and hdist(lip, Vector3.new(f.Lip[1], 0, f.Lip[3])) <= 0.5,
					"bug13 fountain: fall " .. i .. " starts at its lip", fmt("%.2f, %.2f, %.2f", lip.X, lip.Y, lip.Z))
				local outward = Vector3.new(imp.X - lip.X, 0, imp.Z - lip.Z)
				T.check(outward.Magnitude > 0.2 and outward.Unit:Dot(Vector3.new(f.Dir[1], 0, f.Dir[2]).Unit) > 0.9,
					"bug13 fountain: fall " .. i .. " is thrown outward over the rim (impact beyond the lip)")
				T.check(core.CurveSize0 > 0 and core.CurveSize1 > 0, "bug13 fountain: fall " .. i .. " is curved (CurveSize0 / 1 > 0)")
			end
			local streaks, moving = 0, 0
			for _, b in ipairs(anchor:GetChildren()) do
				if b:IsA("Beam") and b.Name:sub(1, #tag + 6) == tag .. "Streak" then
					streaks = streaks + 1
					if abs(b.TextureSpeed) > 0.5 and b.TextureMode == Enum.TextureMode.Wrap and b.Texture ~= "" then
						moving = moving + 1
					end
				end
			end
			T.check(streaks >= (f.Big and 3 or 2) and moving == streaks,
				"bug13 fountain: fall " .. i .. " has scrolling streak Beams (Wrap, TextureSpeed set: the water runs)", fmt("%d streaks, %d moving", streaks, moving))
			local uphill = {}
			for _, b in ipairs(anchor:GetChildren()) do
				if b:IsA("Beam") and b.Name:sub(1, #tag + 6) == tag .. "Streak" and b.Attachment0 and b.Attachment1 then
					-- docs: + scrolls A0 -> A1. Downhill = toward the lower attachment.
					local a0y, a1y = L(b.Attachment0.WorldPosition).Y, L(b.Attachment1.WorldPosition).Y
					local towardA1 = b.TextureSpeed > 0
					local down = (towardA1 and a1y < a0y) or (not towardA1 and a0y < a1y)
					if not down then
						uphill[#uphill + 1] = b.Name
					end
				end
			end
			T.check(#uphill == 0, "bug13 fountain: fall " .. i .. "'s streaks scroll downhill by the Beam docs (+ = A0 -> A1; Flow -1)", table.concat(uphill, ", "))
			local splash = m:FindFirstChild(tag .. "Splash")
			local rings = m:FindFirstChild(tag .. "Ripples")
			if T.check(splash and splash:IsA("BasePart") and rings and rings:IsA("BasePart"), "bug13 fountain: fall " .. i .. " has its Splash and Ripples parts") then
				local sp = L(splash.Position)
				T.check(abs(sp.Y - (f.Land + 0.1)) <= 0.1, "bug13 fountain: fall " .. i .. ": the splash sits on the water it lands in", fmt("%.2f", sp.Y))
				if okCore then
					T.check(hdist(sp, L(core.Attachment0.WorldPosition)) <= 0.1, "bug13 fountain: fall " .. i .. ": the splash is under the impact")
				end
				T.check((rings.Position - splash.Position).Magnitude < 0.01, "bug13 fountain: fall " .. i .. ": the ripples ring out from the splash")
				local need = { "Drops", "Foam", "Ripples" }
				local got = {}
				for _, n in ipairs(need) do
					local e = (n == "Ripples" and rings or splash):FindFirstChild(n)
					if e and e:IsA("ParticleEmitter") and e.Rate > 0 then
						got[#got + 1] = n
					end
				end
				T.check(#got == #need, "bug13 fountain: fall " .. i .. ": drops, foam and ripples", table.concat(got, ", "))
				local rip = rings:FindFirstChild("Ripples")
				T.check(rip and rip.Orientation == Enum.ParticleOrientation.VelocityPerpendicular, "bug13 fountain: fall " .. i .. ": the ripples lie flat on the water")
				if f.Big then
					T.check(splash:FindFirstChild("Mist") ~= nil and m:FindFirstChild(tag .. "LipDrops") ~= nil, "bug13 fountain: the big fall has mist and drops breaking off its lip")
				end
			end
		end

		-- the climbs
		for _, spec in ipairs({ { "LadderTruss", O.Ladder, 1, 2 }, { "RopeTruss", O.Rope, 2, 3 } }) do
			local t = m:FindFirstChild(spec[1])
			local c = spec[2]
			if T.check(t and t:IsA("TrussPart") and t.CanCollide, "bug13 fountain: " .. spec[1] .. " is a colliding TrussPart (climbable)") then
				local p = L(t.Position)
				local top, bottom = p.Y + t.Size.Y / 2, p.Y - t.Size.Y / 2
				local upper, lower = O.Islands[spec[4]].Top, O.Islands[spec[3]].Top
				T.check(abs(top - c.Y1) <= 0.02 and abs(bottom - c.Y0) <= 0.02, "bug13 fountain: " .. spec[1] .. " spans OASIS Y0..Y1", fmt("%.2f..%.2f", bottom, top))
				T.check(top - upper >= 0 and top - upper <= 0.2, "bug13 fountain: " .. spec[1] .. "'s top is flush with the upper island's landing", fmt("top %.2f island %.2f", top, upper))
				T.check(bottom <= lower + 0.1, "bug13 fountain: " .. spec[1] .. " starts within reach of the lower island", fmt("bottom %.2f island %.2f", bottom, lower))
			end
		end

		-- the paper boat
		local boat = m:FindFirstChild("PaperBoat")
		if T.check(boat and boat:IsA("BasePart") and CS:HasTag(boat, "OasisBoat"), "bug13 fountain: the paper boat is a BasePart tagged OasisBoat") then
			T.check(boat:GetAttribute("ML_Weld") == true, "bug13 fountain: the boat root carries ML_Weld (the mesh rides it when FountainFx moves it)")
			local sail = boat:FindFirstChild("Sail")
			local welded = false
			if sail then
				for _, w in ipairs(sail:GetChildren()) do
					if w:IsA("WeldConstraint") and w.Part0 == boat and w.Part1 == sail then
						welded = true
					end
				end
			end
			T.check(sail ~= nil and sail:IsA("BasePart") and sail.Anchored == true and boat.Anchored == true and not welded,
				"bug13 fountain: the boat and its sail are Anchored (the lobby invariant; FountainFx moves both, no weld)")
			T.check(abs(L(boat.Position).Y - O.Water) <= 0.4, "bug13 fountain: the boat floats on the water")
		end

		-- the meshes: committed manifests fit the layout; tagged only when uploaded
		local Ids = requireAt("shared/MeshIds") or {}
		local rim = O.RimR + 1.6
		for _, key in ipairs({ "prop_oasis_pool", "prop_oasis_islands", "prop_oasis_water", "prop_oasis_boat" }) do
			local man = requireAt("shared/MeshManifests/" .. key)
			if T.check(type(man) == "table" and type(man.Bounds) == "table", "bug13 fountain: " .. key .. " has a committed manifest") then
				local b = man.Bounds
				local reach = max(abs(b.Min[1]), abs(b.Max[1]), abs(b.Min[3]), abs(b.Max[3]))
				if key == "prop_oasis_boat" then
					T.check(b.Size[1] < 2 and b.Size[3] < 2.5 and b.Size[2] < 1.5, "bug13 fountain: the boat mesh is boat-sized", fmt("%.1f x %.1f x %.1f", b.Size[1], b.Size[2], b.Size[3]))
				else
					T.check(reach <= rim, "bug13 fountain: " .. key .. " stays inside the pool rim", fmt("reach %.2f rim %.2f", reach, rim))
					T.check(b.Min[2] >= -0.6, "bug13 fountain: " .. key .. " does not sink under the plaza", fmt("%.2f", b.Min[2]))
				end
				if key == "prop_oasis_pool" then
					T.check(reach >= O.PoolIn, "bug13 fountain: the pool mesh reaches the rim wall")
				elseif key == "prop_oasis_islands" then
					T.check(b.Max[2] >= O.Islands[3].Top and b.Max[2] <= O.Islands[3].Top + 2.5, "bug13 fountain: the islands mesh tops out at the top island (+ tree / nest)", fmt("%.2f", b.Max[2]))
				elseif key == "prop_oasis_water" then
					T.check(b.Min[2] <= O.Water and b.Max[2] <= O.Islands[3].Top + 0.2, "bug13 fountain: the water mesh spans the pool to the spring", fmt("%.2f..%.2f", b.Min[2], b.Max[2]))
				end
			end
			local hasId = type(Ids[key]) == "number"
			local tagged = false
			for _, d in ipairs(m:GetDescendants()) do
				if d:GetAttribute("ML_DressKey") == key then
					tagged = true
				end
			end
			if hasId then
				T.check(tagged, "bug13 fountain: " .. key .. " is uploaded and tagged on the fountain")
			else
				T.check(not tagged, "bug13 fountain: " .. key .. " is not uploaded yet: the Part build stands alone (no tag)")
			end
		end
		for _, d in ipairs(m:GetDescendants()) do
			local k = d:GetAttribute("ML_DressKey")
			if k == "prop_fountain" or k == "prop_fountain_water" then
				T.fail("bug13 fountain: the retired prop_fountain keys are not used", d:GetFullName())
				break
			end
		end
		K.flushErrors("bug13fountain_server")
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	local KC = _G.KC

	local function moduleAt(top, rest)
		local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end

	S.client_bug13fountain_boat = guarded("client_bug13fountain_boat", function()
		local FX = KC.M.FountainFx or moduleAt("client", "Controllers/FountainFx")
		if not T.check(FX and type(FX.Init) == "function" and type(FX.Step) == "function" and type(FX.Stop) == "function"
			and type(FX.Offset) == "function" and type(FX.Stats) == "function", "bug13 boat: FountainFx loads (Init, Step, Stop, Offset, Stats)") then
			return
		end
		local K = FX.K
		-- Offset is small and smooth
		local biggest, jump = 0, 0
		local prev = FX.Offset(0, 0.3).Position
		for i = 1, 400 do
			local p = FX.Offset(i * 0.05, 0.3).Position
			biggest = max(biggest, p.Magnitude)
			jump = max(jump, (p - prev).Magnitude)
			prev = p
		end
		T.check(biggest <= sqrt(K.DRIFT ^ 2 + K.BOB ^ 2) + 1e-3 and biggest > 0.1, "bug13 boat: the drift stays small (within DRIFT + BOB of rest)", fmt("%.3f", biggest))
		T.check(jump < 0.05, "bug13 boat: ...and smooth (< 0.05 stud per 0.05 s)", fmt("%.4f", jump))

		local CS = game:GetService("CollectionService")
		local St = FX._St
		local savedQ = St and St.Quality0
		local mode = "High"
		if St then
			St.Quality0 = { Effective = function()
				return mode
			end }
		end
		FX.Init()
		local cam = workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.new(0, 0, 0)
		local near = Instance.new("Part")
		near.Name = "SmokeBoatNear"
		near.Anchored = true
		near.CFrame = CFrame.new(camPos + Vector3.new(6, -2, -12)) * CFrame.Angles(0, 0.5, 0)
		near.Parent = workspace
		local far = Instance.new("Part")
		far.Name = "SmokeBoatFar"
		far.Anchored = true
		far.CFrame = CFrame.new(camPos + Vector3.new(K.RANGE + 60, 0, 0))
		far.Parent = workspace
		local sail = Instance.new("Part") -- an anchored part under the root (the Part boat's sail)
		sail.Name = "Sail"
		sail.Anchored = true
		sail.CFrame = near.CFrame * CFrame.new(0, 0.4, 0.1)
		sail.Parent = near
		local restNear, restFar = near.CFrame, far.CFrame
		local restSail = sail.CFrame
		local sailOff = restNear:ToObjectSpace(restSail)
		CS:AddTag(near, K.BOAT_TAG)
		CS:AddTag(far, K.BOAT_TAG)
		local moved, maxOff, sailErr = false, 0, 0
		for _ = 1, 60 do
			KC.advance(0.05)
			local off = (near.Position - restNear.Position).Magnitude
			maxOff = max(maxOff, off)
			moved = moved or off > 0.01 or near.CFrame.LookVector:Dot(restNear.LookVector) < 0.99999
			sailErr = max(sailErr, (sail.Position - (near.CFrame * sailOff).Position).Magnitude)
		end
		T.check(sail.Anchored and sailErr < 1e-4 and (sail.Position - restSail.Position).Magnitude > 1e-4,
			"bug13 boat: the anchored sail moves with the root at its rest offset", fmt("err %.5f", sailErr))
		local st = FX.Stats()
		T.check(st.Boats >= 2, "bug13 boat: FountainFx tracks tagged boats as they arrive", tostring(st.Boats))
		T.check(moved, "bug13 boat: a boat near the camera drifts and bobs (the water feels alive)", fmt("max offset %.3f", maxOff))
		T.check(maxOff <= sqrt(K.DRIFT ^ 2 + K.BOB ^ 2) + 0.01, "bug13 boat: ...only a little", fmt("%.3f", maxOff))
		T.check((far.CFrame.Position - restFar.Position).Magnitude < 1e-6, "bug13 boat: a boat beyond RANGE stays at rest")
		-- Low graphics: back at rest
		if St then
			mode = "Low"
			KC.advance(K.REFRESH + 0.1)
			T.check((near.CFrame.Position - restNear.Position).Magnitude < 1e-6 and (sail.Position - restSail.Position).Magnitude < 1e-6
				and FX.Stats().Moving == 0, "bug13 boat: Low graphics puts the boat and its sail back at rest")
			mode = "High"
			KC.advance(K.REFRESH + 0.1)
			T.check((near.CFrame.Position - restNear.Position).Magnitude > 1e-4 or FX.Stats().Moving >= 1, "bug13 boat: ...and High starts it again")
		end
		-- Stop: every boat back exactly at rest, nothing connected
		FX.Stop()
		T.check((near.CFrame.Position - restNear.Position).Magnitude < 1e-6, "bug13 boat: Stop() returns the boat to its rest frame")
		local before = near.CFrame
		KC.advance(0.5)
		T.check(near.CFrame == before, "bug13 boat: after Stop() nothing moves it")
		-- untagging forgets it
		FX.Init()
		KC.advance(0.3)
		CS:RemoveTag(near, K.BOAT_TAG)
		T.check((near.CFrame.Position - restNear.Position).Magnitude < 1e-6, "bug13 boat: an untagged (streamed-out) boat is left at rest")
		near:Destroy()
		far:Destroy()
		KC.advance(0.1)
		if St then
			St.Quality0 = savedQ
		end
		KC.flushErrors("bug13fountain_boat")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
