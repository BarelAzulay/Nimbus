-- smoke_bug11_ring.lua: bug #11 "ground logo bugged & looks bad, crowd needs animation and sound" (art wave, the
-- player's pick: option A "Sky-Sailors' Ring" + "add a drummer like in option b"). Loaded by tools/smoke.py in the
-- server world and the client world:
--   bug11ring_server (server) a built Champion Ring pocket (ArenaBuilder.BuildPocket):
--                    the logo bug: no EmblemCrown / EmblemGem (the old crown read as a giant letter E, its gems were
--                    buried under the baked floor), the compass star is its own RingEmblem model (its own key,
--                    arena_emblem), every emblem top sits above the canvas (0.068) so nothing z-fights, the star reaches
--                    out on all four sides (not an E), no Neon in it; the crowd: one Model per Ring.CAST cloud, tagged
--                    RingCrowd, Body / ArmL / ArmR / Cap / Drum roots carry ML_Weld + CrowdKey + CrowdOff, each key has a
--                    committed manifest, the Lua cast matches the Blender attachments (Cap, ShoulderL / R), exactly one
--                    drummer (Drizzle) with a Drum and two sticks, every cloud sits on its step and faces the ring; the
--                    rigging (masts, flag line, bell) beside it; the steps' tops at 1.75 / 3.75 stand-local; the pads
--                    stay kept Parts of arena_pocket; dress targets never nest; a key without an id is not tagged;
--                    Config.Audio.Crowd holds the 8 crowd sound names as strings (empty = silent)
--   client_bug11ring_crowd (client) RingCrowdFx: Pose / StickAngle are pure and in time (left stick on even beats,
--                    right on odd, idle motion small), the cues (Hit lean + the captain's flash, Won hop + caps up,
--                    Lost slump, Boss roll + forward lean), a tagged fake stand near the camera moves (Body, arms, cap,
--                    drum ride the seat; anchored kids keep their offsets), the flag line swings, the boss round darkens
--                    and the colours come back, out of range / Stop() / untagging put every part exactly at rest, Low graphics = LOW_HZ,
--                    HandleState with fake BattleState payloads (ring Start + boss, big-hit Events, End won / lost,
--                    another battle's Events ignored, a Duel ignored), no Sound without an id
-- Deterministic: mock clock only. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, max, min = math.abs, math.max, math.min
local fmt = string.format

local CROWD_SOUNDS = { "Ambient", "Ooh", "Applause", "Aww", "Bell", "Thunder", "Drum", "DrumRoll" }

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

	local function corners(part)
		local h = part.Size / 2
		local out = {}
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					out[#out + 1] = part.CFrame * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
				end
			end
		end
		return out
	end

	S.bug11ring_server = guarded("bug11ring_server", function()
		if not K.needBoot() then
			return
		end
		local AB = requireAt("server/Services/ArenaBuilder")
		local Ring = AB and AB._Ring
		local Mesh = AB and AB._Mesh
		local ML = requireAt("shared/MeshLibrary")
		if not T.check(type(Ring) == "table" and type(Ring.CAST) == "table" and type(Ring.RIG) == "table" and type(Ring.DRUM) == "table"
			and type(Mesh) == "table" and type(Mesh.Placed) == "table" and type(ML) == "table", "bug11 ring: ArenaBuilder._Ring (CAST, RIG, DRUM), _Mesh and MeshLibrary load") then
			return
		end
		local rp = AB.BuildPocket(43, "Ring")
		if not T.check(type(rp) == "table" and rp.Model and rp.Model.Parent, "bug11 ring: a Champion Ring pocket builds") then
			return
		end
		local root, cf = rp.Model, rp.CFrame
		local CS = game:GetService("CollectionService")
		local function L(v)
			return cf:PointToObjectSpace(v)
		end

		-- 1. the logo bug
		local old = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d.Name == "EmblemCrown" or d.Name == "EmblemGem" then
				old[#old + 1] = d.Name
			end
		end
		T.check(#old == 0, "bug11 ring: the old crown + gems (read as a letter E, gems buried in the floor) are gone", table.concat(old, ", "))
		local emblem = root:FindFirstChild("RingEmblem")
		if T.check(emblem ~= nil and emblem:IsA("Model"), "bug11 ring: the compass star is its own RingEmblem model (beside RingBase, not in the bake)") then
			local low, neon, n = math.huge, {}, 0
			local reach = { px = 0, nx = 0, pz = 0, nz = 0 }
			for _, p in ipairs(emblem:GetDescendants()) do
				if p:IsA("BasePart") then
					n = n + 1
					local top = -math.huge
					for _, c in ipairs(corners(p)) do
						local l = L(c)
						top = max(top, l.Y)
						if p.Name == "EmblemStar" then
							reach.px, reach.nx = max(reach.px, l.X), max(reach.nx, -l.X)
							reach.pz, reach.nz = max(reach.pz, l.Z), max(reach.nz, -l.Z)
						end
					end
					low = min(low, top)
					if p.Material == Enum.Material.Neon then
						neon[#neon + 1] = p.Name
					end
				end
			end
			T.check(n >= 8 and low > 0.068 + 0.02, "bug11 ring: every emblem part's top is above the canvas (0.068): no z-fighting", fmt("%d parts, lowest top %.3f", n, low))
			T.check(#neon == 0, "bug11 ring: no Neon in the emblem (gems never glow through the floor again)", table.concat(neon, ", "))
			local r = { reach.px, reach.nx, reach.pz, reach.nz }
			local rmin, rmax = math.huge, 0
			for _, v in ipairs(r) do
				rmin, rmax = min(rmin, v), max(rmax, v)
			end
			T.check(rmin >= 5.5 and rmax - rmin <= 1.0, "bug11 ring: the star reaches out evenly on all four sides (a compass, not an E)", fmt("+x %.2f -x %.2f +z %.2f -z %.2f", reach.px, reach.nx, reach.pz, reach.nz))
			local rec = Mesh.Placed[emblem]
			T.check(rec ~= nil and rec.Key == "arena_emblem", "bug11 ring: RingEmblem is the arena_emblem dress target", rec and rec.Key)
			T.check(type(ML.Manifest("arena_emblem")) == "table", "bug11 ring: arena_emblem has a committed manifest")
		end
		local base = root:FindFirstChild("RingBase")
		local baseRec = base and Mesh.Placed[base]
		if T.check(baseRec ~= nil and baseRec.Key == "arena_pocket", "bug11 ring: RingBase is the arena_pocket dress target") then
			local keep = {}
			for _, k in ipairs(baseRec.Keep or {}) do
				keep[k] = true
			end
			T.check(keep.SpawnPad and keep.ChampionPad and keep.SpawnGlow and keep.ChampionGlow and keep.RingRimInlay,
				"bug11 ring: the pads, their glows and the rim inlay stay kept Parts (the bake no longer swallows the pads)")
		end

		-- 2. the crowd
		local crowd = root:FindFirstChild("Crowd")
		if not T.check(crowd ~= nil, "bug11 ring: the pocket has its Crowd (beside RingBase)") then
			return
		end
		local standCF = cf * CFrame.new(0, Ring.StandY, Ring.FloorA + 4.6)
		local stand = base and base:FindFirstChild("Stand")
		local tops = {}
		if stand then
			for _, p in ipairs(stand:GetDescendants()) do
				if p:IsA("BasePart") and p.Name == "StandStep" then
					tops[#tops + 1] = standCF:PointToObjectSpace(p.Position).Y + p.Size.Y / 2
				end
			end
		end
		table.sort(tops)
		T.check(#tops == 2 and abs(tops[1] - 1.75) < 1e-3 and abs(tops[2] - 3.75) < 1e-3, "bug11 ring: the two steps' tops are at 1.75 / 3.75 stand-local (where the clouds sit)",
			table.concat((function()
				local o = {}
				for i, v in ipairs(tops) do
					o[i] = fmt("%.3f", v)
				end
				return o
			end)(), ", "))
		local Ids = requireAt("shared/MeshIds") or {}
		local byName = {}
		for _, m in ipairs(crowd:GetChildren()) do
			if m:IsA("Model") and m:GetAttribute("Spectator") then
				byName[m:GetAttribute("Spectator")] = m
			end
		end
		local drummers = 0
		local roots = T.tally("bug11 ring: every crowd root carries ML_Weld + CrowdKey + CrowdOff and its key has a manifest")
		local frames = T.tally("bug11 ring: the Lua cast matches the Blender body keys' attachments (Cap, ShoulderL, ShoulderR)")
		local seats = T.tally("bug11 ring: every cloud sits on its step (its body pivot at the seat) and faces the ring centre")
		local quiet = T.tally("bug11 ring: a crowd root is tagged exactly when its key has a shipped id (none yet: the Part build stands alone)")
		for _, spec in ipairs(Ring.CAST) do
			local m = byName[spec.Name]
			if T.check(m ~= nil and CS:HasTag(m, Ring.CrowdTag) and Ring.CrowdTag == "RingCrowd", "bug11 ring: " .. spec.Name .. " is its own Model tagged RingCrowd") then
				local want = { Body = "arena_crowd_" .. spec.Name, ArmL = "arena_crowd_" .. spec.Arms[1], ArmR = "arena_crowd_" .. spec.Arms[2] }
				if spec.Cap then
					want.Cap = (spec.Cap == "captain") and "arena_crowd_captaincap" or "arena_crowd_cap"
				end
				if spec.Drummer then
					want.Drum = "arena_crowd_drum"
				end
				for piece, key in pairs(want) do
					local p = m:FindFirstChild(piece)
					local ok = p and p:IsA("BasePart") and p:GetAttribute("ML_Weld") == true and p:GetAttribute("CrowdKey") == key
						and typeof(p:GetAttribute("CrowdOff")) == "CFrame" and type(ML.Manifest(key)) == "table"
					roots:case(ok, spec.Name .. "." .. piece, p and tostring(p:GetAttribute("CrowdKey")) or "missing")
					if p then
						-- ArenaBuilder's rule (p3arena_mesh): tagged exactly when the key has a shipped id
						local dk = p:GetAttribute("ML_DressKey")
						local okStatus, status = pcall(ML.Status, key)
						local shipped = okStatus and status ~= "missing"
						quiet:case((dk ~= nil) == shipped and (dk == nil or dk == key), spec.Name .. "." .. piece, tostring(dk) .. " / " .. tostring(status) .. " / id " .. tostring(Ids[key]))
					end
				end
				if not spec.Cap then
					roots:case(m:FindFirstChild("Cap") == nil, spec.Name .. ": no cap (the spec has none)")
				end
				if spec.Drummer then
					drummers = drummers + 1
					T.check(m:GetAttribute("Drummer") == true and spec.Arms[1] == "stick" and spec.Arms[2] == "stick" and m:FindFirstChild("Drum") ~= nil,
						"bug11 ring: the drummer (" .. spec.Name .. ") has the Drummer attribute, a Drum and two drumsticks (the player's note)")
				end
				local man = ML.Manifest("arena_crowd_" .. spec.Name)
				local att = man and man.Attachments
				local cap, shL, shR = Ring.bodyFrame(spec)
				local function same(a, v)
					local pos = a and (a.Pos or a.pos)
					return pos and abs(pos[1] - v.X) < 1e-3 and abs(pos[2] - v.Y) < 1e-3 and abs(pos[3] - v.Z) < 1e-3
				end
				frames:case(att and same(att.Cap, cap) and same(att.ShoulderL, shL) and same(att.ShoulderR, shR), spec.Name)
				local body = m:FindFirstChild("Body")
				if body and typeof(body:GetAttribute("CrowdOff")) == "CFrame" then
					local pivot = body.CFrame * body:GetAttribute("CrowdOff")
					local l = standCF:ToObjectSpace(pivot)
					local onSeat = abs(l.Position.X - spec.Seat[1]) < 1e-3 and abs(l.Position.Y - spec.Seat[2]) < 1e-3 and abs(l.Position.Z - spec.Seat[3]) < 1e-3
					local toCentre = (Vector3.new(cf.Position.X, pivot.Position.Y, cf.Position.Z) - pivot.Position)
					local faces = toCentre.Magnitude > 1 and pivot.LookVector:Dot(toCentre.Unit) > 0.9
					seats:case(onSeat and faces, spec.Name, fmt("%.2f, %.2f, %.2f", l.Position.X, l.Position.Y, l.Position.Z))
				end
			end
		end
		roots:report()
		frames:report()
		seats:report()
		quiet:report()
		T.eq(drummers, 1, "bug11 ring: exactly one drummer in the crowd")
		local count = 0
		for _ in pairs(byName) do
			count = count + 1
		end
		T.eq(count, #Ring.CAST, "bug11 ring: one Model per cast cloud")
		-- the rigging, the flag line, the bell
		local rig = crowd:FindFirstChild("Rigging")
		local line = crowd:FindFirstChild("FlagLine")
		local bell = crowd:FindFirstChild("Bell")
		T.check(rig and Mesh.Placed[rig] and Mesh.Placed[rig].Key == "arena_crowd_rig", "bug11 ring: the rigging is the arena_crowd_rig dress target")
		T.check(line and line:GetAttribute("CrowdKey") == "arena_crowd_flags" and line:GetAttribute("ML_Weld") == true, "bug11 ring: the flag line is a moving root (arena_crowd_flags, ML_Weld)")
		T.check(bell and bell:GetAttribute("CrowdKey") == "arena_crowd_bell" and bell:GetAttribute("ML_Weld") == true, "bug11 ring: the ship's bell is a moving root (arena_crowd_bell, ML_Weld)")
		local masts = 0
		if rig then
			for _, p in ipairs(rig:GetChildren()) do
				if p.Name == "Mast" then
					masts = masts + 1
					-- the apron is a 16-gon whose edges (the kerbs) sit 45.5 from the centre at multiples of 22.5 degrees
					local l = L(p.Position)
					local ang = math.atan2(l.X, l.Z)
					local step = math.pi / 8
					local off = ang - math.floor(ang / step + 0.5) * step
					local d = Vector3.new(l.X, 0, l.Z).Magnitude * math.cos(off) + max(p.Size.X, p.Size.Z) / 2
					T.check(d <= 45.5 - 0.05, "bug11 ring: a mast stands on the apron (inside its 16-gon kerb line, 45.5)", fmt("outer edge %.2f", d))
				end
			end
		end
		T.eq(masts, 2, "bug11 ring: two flag masts")
		-- 3. dress targets never nest
		local set, nested = {}, {}
		for target in pairs(Mesh.Placed) do
			if target.Parent and (target == root or target:IsDescendantOf(root)) then
				set[target] = true
			end
		end
		for target in pairs(set) do
			local p = target.Parent
			while p do
				if set[p] then
					nested[#nested + 1] = target.Name .. " in " .. p.Name
					break
				end
				p = p.Parent
			end
		end
		T.check(#nested == 0, "bug11 ring: dress targets never nest (one dress per subtree)", table.concat(nested, ", "))
		-- 4. the crowd's sounds: names only, strings (empty = silent until the player uploads them)
		local Config = requireAt("shared/Config")
		local A = Config and Config.Audio and Config.Audio.Crowd
		if T.check(type(A) == "table", "bug11 ring: Config.Audio.Crowd exists") then
			local bad = {}
			for _, n in ipairs(CROWD_SOUNDS) do
				local v = A[n]
				if type(v) ~= "string" or (v ~= "" and not v:match("^rbxassetid://%d+$")) then
					bad[#bad + 1] = n .. "=" .. tostring(v)
				end
			end
			T.check(#bad == 0, "bug11 ring: every crowd sound is a string ('' or rbxassetid://<n>)", table.concat(bad, ", "))
		end
		AB.FreePocket(43)
		K.flushErrors("bug11ring_server")
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

	-- a fake stand (the shape ArenaBuilder builds): Crowd folder > Spectator model (Body / ArmL / ArmR / Cap / Drum roots
	-- with CrowdOff and anchored kids) + FlagLine + Bell
	local function part(parent, name, cf, size, color)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.Size = size or Vector3.new(1, 1, 1)
		p.CFrame = cf
		p.Color = color or Color3.fromRGB(200, 210, 230)
		p.Parent = parent
		return p
	end
	local function root(parent, name, key, origin, centre, color)
		local p = part(parent, name, centre, Vector3.new(1, 1, 1), color)
		p:SetAttribute("ML_Weld", true)
		p:SetAttribute("CrowdKey", key)
		p:SetAttribute("CrowdOff", centre:Inverse() * origin)
		return p
	end
	local function fakeStand(at, drummer, name)
		local crowd = Instance.new("Folder")
		crowd.Name = "Crowd"
		crowd.Parent = workspace
		local m = Instance.new("Model")
		m.Name = "Spectator_" .. name
		m:SetAttribute("Spectator", name)
		if drummer then
			m:SetAttribute("Drummer", true)
		end
		m.Parent = crowd
		local seat = CFrame.new(at)
		local body = root(m, "Body", "arena_crowd_" .. name, seat, seat * CFrame.new(0, 1.2, 0), Color3.fromRGB(196, 222, 246))
		part(body, "PuffEye", seat * CFrame.new(0.4, 1.2, -1), Vector3.new(0.4, 0.6, 0.1), Color3.fromRGB(42, 46, 70))
		local armKind = drummer and "stick" or "arm"
		local armL = root(m, "ArmL", "arena_crowd_" .. armKind, seat * CFrame.new(-1.3, 1.4, 0), seat * CFrame.new(-1.3, 1.0, -0.3))
		local armR = root(m, "ArmR", "arena_crowd_" .. armKind, seat * CFrame.new(1.3, 1.4, 0), seat * CFrame.new(1.3, 1.0, -0.3))
		part(armL, "Drumstick", seat * CFrame.new(-1.0, 0.9, -1.2), Vector3.new(0.14, 0.14, 1))
		local cap = root(m, "Cap", "arena_crowd_cap", seat * CFrame.new(0, 2.4, 0), seat * CFrame.new(0, 2.65, 0))
		local drum
		if drummer then
			drum = root(m, "Drum", "arena_crowd_drum", seat * CFrame.new(0, 0.44, -1.41), seat * CFrame.new(0, 0.44, -1.41))
		end
		local line = root(crowd, "FlagLine", "arena_crowd_flags", seat * CFrame.new(0, 11, 5), seat * CFrame.new(0, 9.8, 5))
		part(line, "Flag", seat * CFrame.new(3, 9, 5), Vector3.new(1.5, 1.5, 0.12))
		local bell = root(crowd, "Bell", "arena_crowd_bell", seat * CFrame.new(-6, 6.8, 3.6), seat * CFrame.new(-6, 6.1, 3.6))
		return { Crowd = crowd, Model = m, Body = body, ArmL = armL, ArmR = armR, Cap = cap, Drum = drum, Line = line, Bell = bell }
	end
	local function snapshot(f)
		local out = {}
		for _, d in ipairs(f.Crowd:GetDescendants()) do
			if d:IsA("BasePart") then
				out[d] = { CF = d.CFrame, Color = d.Color }
			end
		end
		return out
	end
	local function atRest(snap, within)
		local worst = 0
		local colour = true
		for p, s in pairs(snap) do
			if not within or p:IsDescendantOf(within) then
				worst = max(worst, (p.Position - s.CF.Position).Magnitude, (p.CFrame.LookVector - s.CF.LookVector).Magnitude)
				if p.Color ~= s.Color then
					colour = false
				end
			end
		end
		return worst < 1e-5 and colour, worst
	end

	S.client_bug11ring_crowd = guarded("client_bug11ring_crowd", function()
		local FX = KC.M.RingCrowdFx or moduleAt("client", "Controllers/RingCrowdFx")
		if not T.check(FX and type(FX.Init) == "function" and type(FX.Step) == "function" and type(FX.Stop) == "function" and type(FX.Pose) == "function"
			and type(FX.StickAngle) == "function" and type(FX.HandleState) == "function" and type(FX.Cue) == "function" and type(FX.Stats) == "function",
			"bug11 crowd: RingCrowdFx loads (Init, Step, Stop, Pose, StickAngle, Cue, HandleState, Stats)") then
			return
		end
		local K = FX.K

		-- 1. pure motion: the drum keeps time, idle stays small
		local beatsOk = true
		for b = 0, 7 do
			local l, r = FX.StickAngle(-1, b, "idle"), FX.StickAngle(1, b, "idle")
			if b % 2 == 0 then
				beatsOk = beatsOk and abs(l) < 1e-6 and abs(r - K.STICK_UP) < 1e-6
			else
				beatsOk = beatsOk and abs(r) < 1e-6 and abs(l - K.STICK_UP) < 1e-6
			end
		end
		T.check(beatsOk, "bug11 crowd: the drummer's sticks alternate in time (left on even beats, right on odd)")
		local rollMax, missOk = 0, FX.StickAngle(-1, 3.3, "miss") > K.STICK_UP
		for i = 0, 40 do
			rollMax = max(rollMax, FX.StickAngle(1, i * 0.05, "roll"))
		end
		T.check(rollMax > 0 and rollMax <= K.STICK_UP * 0.3 + 1e-6 and missOk, "bug11 crowd: a boss drum roll is fast and small; a miss holds both sticks up")
		local spec = { Name = "drizzle", Phase = 0.3, Drummer = true, Captain = false, Cap = "sailor" }
		local cap = { Name = "captain", Phase = 0.1, Drummer = false, Captain = true, Cap = "captain" }
		local idleMax, jump = 0, 0
		local prev = FX.Pose(spec, 0, nil, 0, 0)
		for i = 1, 200 do
			local p = FX.Pose(spec, i * 0.05, nil, 0, 0)
			idleMax = max(idleMax, p.Lift, abs(p.Roll) * 10, abs(p.Lean) * 10)
			jump = max(jump, abs(p.Lift - prev.Lift), abs(p.Roll - prev.Roll))
			prev = p
		end
		local idleBound = max(K.BOB + K.DRUM_DIP, (K.SWAY + K.DRUM_ROLL) * 10, (K.BREATHE + K.DRUM_LEAN) * 10)
		T.check(idleMax <= idleBound + 1e-6 and idleMax > 0.02 and jump < 0.05, "bug11 crowd: idle sway / bob stays bounded and smooth", fmt("max %.3f (bound %.3f) jump %.4f", idleMax, idleBound, jump))
		-- fix round: the idle must read from the fighter's spawn (~45 studs), not only close up
		local sun = { Name = "sun", Phase = 0.6, Drummer = false, Captain = false, Cap = "sailor" }
		local lo, hi, rlo, rhi, llo, lhi = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
		for i = 0, 160 do
			local p = FX.Pose(sun, i * 0.05, nil, 0, 0)
			lo, hi = min(lo, p.Lift), max(hi, p.Lift)
			rlo, rhi = min(rlo, p.Roll), max(rhi, p.Roll)
			llo, lhi = min(llo, p.Lean), max(lhi, p.Lean)
		end
		T.check(hi - lo >= 0.25 and rhi - rlo >= 0.15 and lhi - llo >= 0.06, "bug11 crowd: the idle bob / sway / breathing are big enough to see at gameplay distance", fmt("bob %.2f sway %.2f lean %.2f", hi - lo, rhi - rlo, lhi - llo))
		local onBeat, offBeat = FX.Pose(spec, 1.0, nil, 0, 0), FX.Pose(spec, 1.25, nil, 0, 0) -- beat 2 / half way to beat 3
		T.check(onBeat.Lift < 0.02 and offBeat.Lift - onBeat.Lift >= 0.15 and onBeat.Lean < offBeat.Lean - 0.05 and onBeat.DrumDip <= -0.05 and abs(offBeat.DrumDip) < 0.02,
			"bug11 crowd: Drizzle drops onto every stroke ON the beat (body dip + lean in + the drum dips), floats up between",
			fmt("lift %.2f / %.2f dip %.2f", onBeat.Lift, offBeat.Lift, onBeat.DrumDip))
		local buf = {}
		local same = FX.Pose(spec, 2.3, nil, 0, 0, buf)
		local fresh = FX.Pose(spec, 2.3, nil, 0, 0)
		T.check(same == buf and abs(buf.Lift - fresh.Lift) < 1e-9 and abs(buf.Roll - fresh.Roll) < 1e-9, "bug11 crowd: Pose fills a caller's table in place (no per-tick allocation)")
		local hit = FX.Pose(cap, 3, "Hit", 0.05, 0)
		T.check(hit.Lean > 0.01 and hit.Flash > 0.8 and hit.ArmL > 0.05, "bug11 crowd: Hit = lean in, arms up, the captain's flash", fmt("lean %.2f flash %.2f", hit.Lean, hit.Flash))
		local won = FX.Pose(spec, 3, "Won", 0.55, 0)
		T.check(won.CapUp > 1.5 and won.ArmL > 1 and won.BellSwing ~= 0, "bug11 crowd: Won = arms high, caps fly, the bell swings", fmt("cap %.2f arms %.2f", won.CapUp, won.ArmL))
		local lost = FX.Pose(spec, 3, "Lost", 1.1, 0)
		T.check(lost.ArmL < -0.4 and lost.Lean < -0.05, "bug11 crowd: Lost = arms down, a slump", fmt("arms %.2f lean %.2f", lost.ArmL, lost.Lean))
		local boss = FX.Pose(spec, 3, nil, 0, 1)
		T.check(boss.Lean <= K.BOSS_LEAN + K.BREATHE + 1e-6 and boss.StickL <= K.STICK_UP * 0.3 + 1e-6, "bug11 crowd: a boss round = lean forward, a drum roll")
		local after = FX.Pose(spec, 9, "Won", K.WON_TIME + 0.5, 0)
		T.check(after.CapUp == 0 and after.ArmL <= K.ARM_IDLE + 1e-6, "bug11 crowd: a cue ends (back to idle after its time)")

		-- 2. a tagged fake stand near the camera
		local CS = game:GetService("CollectionService")
		local St = FX._St
		local savedQ = St and St.Quality0
		local mode = "High"
		if St then
			St.Quality0 = { Effective = function()
				return mode
			end }
		end
		FX.Stop()
		local cam = workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.new(0, 0, 0)
		local f = fakeStand(camPos + Vector3.new(4, -2, -14), true, "drizzle")
		local farStand = fakeStand(camPos + Vector3.new(K.RANGE + 80, 0, 0), false, "sun")
		local rest, restFar = snapshot(f), snapshot(farStand)
		CS:AddTag(f.Model, K.TAG)
		FX.Init()
		CS:AddTag(farStand.Model, K.TAG)
		local stickOff = f.ArmL.CFrame:ToObjectSpace(f.ArmL:FindFirstChild("Drumstick").CFrame)
		local eyeOff = f.Body.CFrame:ToObjectSpace(f.Body:FindFirstChild("PuffEye").CFrame)
		local bodyMax, armMoved, drumRide, lineMoved, kidErr = 0, false, 0, false, 0
		local drumLocal = (f.Body.CFrame * f.Body:GetAttribute("CrowdOff")):ToObjectSpace(f.Drum.CFrame * f.Drum:GetAttribute("CrowdOff"))
		for _ = 1, 60 do
			KC.advance(0.05)
			bodyMax = max(bodyMax, (f.Body.Position - rest[f.Body].CF.Position).Magnitude)
			armMoved = armMoved or f.ArmL.CFrame.LookVector:Dot(rest[f.ArmL].CF.LookVector) < 0.9999
			lineMoved = lineMoved or f.Line.CFrame.UpVector:Dot(rest[f.Line].CF.UpVector) < 0.99999
			local seatNow = f.Body.CFrame * f.Body:GetAttribute("CrowdOff")
			local drumNow = f.Drum.CFrame * f.Drum:GetAttribute("CrowdOff")
			drumRide = max(drumRide, (seatNow:ToObjectSpace(drumNow).Position - drumLocal.Position).Magnitude)
			kidErr = max(kidErr, (f.ArmL:FindFirstChild("Drumstick").Position - (f.ArmL.CFrame * stickOff).Position).Magnitude,
				(f.Body:FindFirstChild("PuffEye").Position - (f.Body.CFrame * eyeOff).Position).Magnitude)
		end
		local st = FX.Stats()
		T.check(st.Spectators >= 2 and st.Moving >= 1, "bug11 crowd: RingCrowdFx tracks tagged spectators and moves the near one", fmt("%d tracked, %d moving", st.Spectators, st.Moving))
		T.check(bodyMax > 0.1 and bodyMax <= K.BOB + K.DRUM_DIP + 0.35, "bug11 crowd: the cloud bobs visibly in idle (and stays on its seat)", fmt("%.3f", bodyMax))
		T.check(armMoved, "bug11 crowd: the drummer's stick arms beat")
		T.check(drumRide > 0.02 and drumRide <= K.DRUM_BOUNCE + 1e-4, "bug11 crowd: the drum rides the drummer's seat (at its belly) and dips under the strokes", fmt("%.5f", drumRide))
		T.check(kidErr < 1e-4, "bug11 crowd: anchored kids (sticks, eyes) keep their offsets from their root", fmt("%.5f", kidErr))
		T.check(lineMoved, "bug11 crowd: the flag line swings in the wind")
		T.check(st.Beats > 0, "bug11 crowd: the beat counter runs (the drum sound's clock)")
		local farOk = atRest(restFar)
		T.check(farOk, "bug11 crowd: a stand beyond RANGE stays at rest")
		-- cues: the boss darkens and the colours come back
		FX.Cue("Boss")
		KC.advance(2.0)
		local darker = f.Body.Color ~= rest[f.Body].Color
		local dark0 = f.Body.Color
		f.Body.Color = Color3.fromRGB(1, 2, 3) -- a sentinel: once the fade is done nothing re-writes the colours
		KC.advance(0.4)
		T.check(f.Body.Color == Color3.fromRGB(1, 2, 3), "bug11 crowd: a steady boss round makes no per-tick colour writes")
		f.Body.Color = dark0
		FX.Cue("BossEnd")
		KC.advance(3.0)
		T.check(darker and f.Body.Color == rest[f.Body].Color, "bug11 crowd: a boss round darkens the clouds toward the storm colour, and they come back after")
		FX.Cue("Won")
		KC.advance(0.55)
		local capUp = (f.Cap.Position - rest[f.Cap].CF.Position).Y
		T.check(capUp > 1.0, "bug11 crowd: a won round sends the caps up", fmt("%.2f", capUp))
		KC.advance(K.WON_TIME)
		-- no Sound without an id (Config.Audio.Crowd is empty until the player uploads)
		local sounds = 0
		for _, d in ipairs(f.Crowd:GetDescendants()) do
			if d:IsA("Sound") and (d.SoundId == "" or d.SoundId == nil) then
				sounds = sounds + 1
			end
		end
		T.check(sounds == 0, "bug11 crowd: no empty Sound is ever made (a crowd sound plays only with an id)")
		-- Low graphics: the crowd still cheers (it is cheap: ~40 parts) but at LOW_HZ (fewer writes), weather off
		if St then
			local w0 = FX.Stats().Writes
			KC.advance(1.0)
			local high = FX.Stats().Writes - w0
			mode = "Low"
			KC.advance(K.REFRESH + 0.1)
			local w1 = FX.Stats().Writes
			KC.advance(1.0)
			local low = FX.Stats().Writes - w1
			T.check(FX.Stats().Quality == "Low" and low > 0 and low < high * 0.75, "bug11 crowd: Low graphics moves the crowd at LOW_HZ (fewer writes per second)", fmt("high %d low %d", high, low))
			mode = "High"
			KC.advance(K.REFRESH + 0.2)
			T.check(FX.Stats().Quality == "High" and FX.Stats().Moving >= 1, "bug11 crowd: ...and High is back at full rate")
		end
		-- a spectator tagged before its Body replicated is picked up by the 2 Hz refresh
		do
			local late = Instance.new("Model")
			late.Name = "Spectator_late"
			late:SetAttribute("Spectator", "rain")
			late.Parent = f.Crowd
			CS:AddTag(late, K.TAG)
			local n0 = FX.Stats().Spectators
			local seatL = CFrame.new(camPos + Vector3.new(-4, -2, -14))
			root(late, "Body", "arena_crowd_rain", seatL, seatL * CFrame.new(0, 1.2, 0))
			KC.advance(K.REFRESH + 0.1)
			T.check(n0 == FX.Stats().Spectators - 1 and St.Specs[late] ~= nil, "bug11 crowd: a spectator whose Body replicates after its tag is still tracked (refresh retries)", fmt("%d -> %d", n0, FX.Stats().Spectators))
			CS:RemoveTag(late, K.TAG)
			late:Destroy()
		end
		-- the idle drum tap plays only during a ring fight (a test id in Config.Audio.Crowd.Drum)
		do
			local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
			local cfgMod = shared and shared:FindFirstChild("Config")
			local okC, Config = pcall(function()
				return cfgMod and require(cfgMod)
			end)
			local crowdIds = okC and type(Config) == "table" and type(Config.Audio) == "table" and Config.Audio.Crowd
			if T.check(type(crowdIds) == "table", "bug11 crowd: Config.Audio.Crowd is reachable from the client (ReplicatedStorage.Shared.Config)") then
				local saved = crowdIds.Drum
				crowdIds.Drum = "rbxassetid://1"
				local function drumSounds()
					local n = 0
					for _, d in ipairs(f.Crowd:GetDescendants()) do
						if d:IsA("Sound") and d.Name == "Crowd_Drum" then
							n = n + 1
						end
					end
					return n
				end
				St.Battle = nil
				KC.advance(K.REFRESH + 1.0)
				local idleTaps = drumSounds()
				St.Battle = { Id = "tap", Hits = 0, Sum = 0, LastCue = -math.huge }
				KC.advance(1.0)
				local fightTaps = drumSounds()
				St.Battle = nil
				crowdIds.Drum = saved
				KC.advance(K.REFRESH + 0.1)
				T.check(idleTaps == 0 and fightTaps >= 1, "bug11 crowd: the drum tap keeps time only during a ring fight (silent between rounds)", fmt("idle %d fight %d", idleTaps, fightTaps))
				for _, d in ipairs(f.Crowd:GetDescendants()) do
					if d:IsA("Sound") then
						d:Destroy()
					end
				end
				for part in pairs(St.Sounds) do
					St.Sounds[part] = nil
				end
			end
		end
		-- 3. HandleState with fake BattleState payloads
		FX.HandleState("Start", { Mode = "Duel", BattleId = "d1" }, "d1")
		T.check(FX.Stats().Boss == false and St.Battle == nil, "bug11 crowd: a Duel start is ignored (only the Champion Ring cheers)")
		FX.HandleState("Start", { Mode = "Ring", BattleId = "r1", Ring = { Champion = { Boss = true } } }, "r1")
		T.check(FX.Stats().Boss == true, "bug11 crowd: a ring Start against a boss champion starts the boss round")
		KC.advance(2.2)
		FX.HandleState("Events", { { type = "Hit", dmg = 10 }, { type = "Hit", dmg = 10 }, { type = "Hit", dmg = 10 } }, "r1")
		T.check(St.Cue == nil or St.Cue.Name ~= "Hit" or (St.Time - St.Cue.T0) > 0.5, "bug11 crowd: ordinary hits don't cue the crowd")
		FX.HandleState("Events", { { type = "Hit", dmg = 40 } }, "other")
		T.check(St.Cue == nil or St.Cue.Name ~= "Hit", "bug11 crowd: another battle's events are ignored")
		FX.HandleState("Events", { { type = "Hit", dmg = 40 } }, "r1")
		T.check(St.Cue ~= nil and St.Cue.Name == "Hit", "bug11 crowd: a big hit (>= BIG_HIT x the average) makes the crowd gasp")
		FX.HandleState("Events", { { type = "Hit", dmg = 0, miss = true }, { type = "KO" } }, "r1")
		FX.HandleState("End", { BattleId = "r1", Won = true, Outcome = "Win" }, "r1")
		T.check(St.Cue and St.Cue.Name == "Won" and FX.Stats().Boss == false and St.Battle == nil, "bug11 crowd: End won = the crowd cheers, the boss round ends")
		FX.HandleState("Start", { Mode = "Ring", BattleId = "r2", Ring = { Champion = { Boss = false } } }, "r2")
		FX.HandleState("End", { BattleId = "r2", Outcome = "Loss" }, "r2")
		T.check(St.Cue and St.Cue.Name == "Lost", "bug11 crowd: End lost = the crowd groans")
		local okJunk = pcall(function()
			FX.HandleState("Events", nil, nil)
			FX.HandleState("Start", "junk", nil)
			FX.HandleState("End", nil, nil)
			FX.HandleState("Snapshot", { U = {} }, "r2")
		end)
		T.check(okJunk, "bug11 crowd: junk payloads never error")
		-- 4. Stop: everything exactly at rest, nothing moves after, client bits gone
		KC.advance(0.3)
		FX.Stop()
		local ok, worst = atRest(rest)
		T.check(ok, "bug11 crowd: Stop() returns every part to its rest frame and colour", fmt("%.6f", worst))
		local leftovers = 0
		for _, d in ipairs(f.Crowd:GetDescendants()) do
			if d.Name:sub(1, 8) == "CrowdFx_" then
				leftovers = leftovers + 1
			end
		end
		T.check(leftovers == 0, "bug11 crowd: Stop() removes the client particles / flash / bolt", tostring(leftovers))
		local before = f.Body.CFrame
		KC.advance(0.5)
		T.check(f.Body.CFrame == before, "bug11 crowd: after Stop() nothing moves it")
		-- untagging (streamed out) leaves it at rest
		FX.Init()
		KC.advance(0.5)
		CS:RemoveTag(f.Model, K.TAG)
		local ok2 = atRest(rest, f.Model)
		T.check(ok2, "bug11 crowd: an untagged (streamed-out) spectator is left at rest")
		FX.Stop()
		f.Crowd:Destroy()
		farStand.Crowd:Destroy()
		if St then
			St.Quality0 = savedQ
		end
		FX.Init()
		KC.advance(0.1)
		KC.flushErrors("bug11ring_crowd")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
