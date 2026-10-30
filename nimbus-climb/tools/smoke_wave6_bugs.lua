-- smoke_wave6_bugs.lua: the two bugs of the owner's inbox fixed in wave 6. Loaded by tools/smoke.py in the server
-- world and the client world (ARGS.context):
--   w6bug_wings          (server world, pure) "when some of the evolve pets fly their wings wing cross their face":
--                        every catalog / event pet at every stage (0 = the base form; 1 / 2 the evolved forms) flaps
--                        through two flying beats (PetBuilder.Animate Flap 1.3, Excited 1, PetController's in-air
--                        numbers) and no wing box corner near the midline (|x| < 1 stud at the pet's scale) above the
--                        eye line ever comes further in front of the eyes than it rests (+ 0.15 stud for the small
--                        sweep wiggle; a wing that stays half a stud behind the eyes passes), while every wing still
--                        beats (> 0.1 stud of travel). Before the fix the beat
--                        rolled each wing about its own hinge axis, a spin in the wing's own plane once the hinge
--                        swept it back: the evolved fans and bat wings swung 0.2..1.5 studs in front of the face.
--                        With --mesh the same check runs on the Blender-mesh pets (the hinges come from the manifests)
--   client_w6bug_train   (client world) "doesnt show my pet in the training while hes training": a level-5 Training
--                        Place on a plot of the local player; TrainingPets puts the pet on mat 1 (plain and evolved);
--                        then the mat's Spot1 attachment arrives AFTER the station (join-time replication): the pet
--                        stands on the mat once it is there (before the fix it never appeared that session)
-- Deterministic: mock clock only. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, max, huge = math.abs, math.max, math.huge
local fmt = string.format

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K

	local function req(key)
		local inst = K.moduleInstance and K.moduleInstance(key)
		if not inst then
			return nil
		end
		local ok, m = pcall(require, inst)
		return ok and type(m) == "table" and m or nil
	end

	-- a wing part of a flapping group (WingL / WingR / Wing2L / Wing2R; not the storm cloud halves, kind "cloud")
	local function isWing(p)
		local spec = p:GetAttribute("PB_G")
		return p:IsA("BasePart") and string.match(p.Name, "^Wing") ~= nil
			and (type(spec) ~= "string" or string.match(spec, "^[^:]*:([^:]*)") == "wing")
	end

	S.w6bug_wings = guarded("w6bug_wings", function()
		local PB, PC = req("shared/PetBuilder"), req("shared/PetCatalog")
		if not T.check(PB ~= nil and PC ~= nil and type(PB.Animate) == "function", "w6 wings: PetBuilder (Build, Animate) and PetCatalog load") then
			return
		end
		local holder = Instance.new("Folder")
		holder.Name = "SmokeW6Wings"
		holder.Parent = workspace
		local defs, seen = {}, {}
		local function add(d)
			if type(d) == "table" and d.Id and not seen[d.Id] then
				seen[d.Id] = true
				defs[#defs + 1] = d
			end
		end
		for _, d in ipairs(PC.Pets) do
			add(d)
		end
		if type(PC.EventPets) == "function" then
			for _, d in ipairs(PC.EventPets()) do
				add(d)
			end
		end
		local face = T.tally("w6 wings: flying, no wing comes nearer the face than it rests (every pet, every stage)")
		local beat = T.tally("w6 wings: ...and every wing still beats (> 0.1 stud of travel)")
		local forms, evolved, worst, worstAt = 0, 0, -huge, ""
		for _, def in ipairs(defs) do
			for stage = 0, PB.MaxEvolution(def) do
				local ok, m = pcall(PB.Build, def, { Evolved = stage > 0 and stage or nil })
				if ok and typeof(m) == "Instance" and m.PrimaryPart then
					m.Parent = holder
					m:PivotTo(CFrame.new(0, 3000, 0))
					local inv = m.PrimaryPart.CFrame:Inverse()
					local scale = tonumber(m:GetAttribute("PB_Scale")) or 1
					local ez, ey, n = 0, 0, 0
					local wings = {}
					for _, p in ipairs(m:GetDescendants()) do
						if p:IsA("BasePart") and string.match(p.Name, "^Eye") and not string.match(p.Name, "^EyeLid") then
							local l = inv * p.Position
							ez, ey, n = ez + l.Z, ey + l.Y, n + 1
						elseif isWing(p) then
							wings[#wings + 1] = p
						end
					end
					if n > 0 and #wings > 0 then
						forms = forms + 1
						if stage > 0 then
							evolved = evolved + 1
						end
						ez, ey = ez / n, ey / n
						-- how far the most forward wing corner near the midline above the eye line is in front of the eyes
						local function ahead()
							local w = -huge
							for _, p in ipairs(wings) do
								local cf, h = inv * p.CFrame, p.Size / 2
								for sx = -1, 1, 2 do
									for sy = -1, 1, 2 do
										for sz = -1, 1, 2 do
											local c = cf * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
											if c.Y > ey - scale and abs(c.X) < scale then
												w = max(w, ez - c.Z)
											end
										end
									end
								end
							end
							return w
						end
						local rest = ahead()
						local start = {}
						for i, p in ipairs(wings) do
							start[i] = inv * p.Position
						end
						local fly, travel = rest, 0
						for i = 0, 72 do
							PB.Animate(m, i / 60, { Flap = 1.3, Excited = 1 })
							fly = max(fly, ahead())
							for j, p in ipairs(wings) do
								travel = max(travel, ((inv * p.Position) - start[j]).Magnitude)
							end
						end
						local label = def.Id .. " stage " .. stage
						if fly - rest > worst then
							worst, worstAt = fly - rest, label
						end
						face:case(fly <= max(rest + 0.15 * scale, -0.5 * scale) + 1e-6, label .. fmt(": %.2f in front of the eyes at rest, %.2f flying", rest, fly))
						beat:case(travel > 0.1, label .. fmt(": %.2f studs", travel))
					end
					m:Destroy()
				end
			end
		end
		face:report(fmt("most extra reach flying %.2f studs, %s", worst, worstAt))
		beat:report()
		T.check(forms >= 40 and evolved >= 20, "w6 wings: the check saw the forms (base + evolved)", forms .. " forms, " .. evolved .. " evolved")
		holder:Destroy()
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local KC = _G.KC
	local S = {}
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer
	local advance = KC.advance

	local function moduleAt(top, rest)
		local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end

	local function flat(a, b)
		return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
	end

	S.client_w6bug_train = guarded("client_w6bug_train", function()
		local HF = KC.M.HomeFx or moduleAt("client", "Controllers/HomeFx")
		local HB = moduleAt("server", "Services/HomeBuilder")
		local TC = moduleAt("shared", "TycoonCatalog")
		local St = moduleAt("client", "State")
		if not T.check(HF and type(HF.Garden) == "function" and HB and TC and St, "w6 train: HomeFx (Garden), HomeBuilder, TycoonCatalog and State load in the client world") then
			return
		end
		HF.Init()
		local root = Instance.new("Folder")
		root.Name = "SmokeW6Train"
		root.Parent = workspace
		local f = Instance.new("Folder")
		f.Name = "Spot_91"
		f.Parent = root
		local base = CFrame.new(4000, 300, -4000)
		local spot = { Index = 91, PlotCFrame = base, PlotSize = TC.PlotSize, Center = base.Position, Folder = f }
		HB.PreparePlot(spot)
		HB.SetOwner(spot, LocalPlayer)
		HB.BuildHome(spot, { Stations = { Garden = 1, Kitchen = 1, Gym = 5 }, Prestige = 1 })
		local cam = workspace.CurrentCamera
		local savedCam = cam.CFrame
		cam.CFrame = CFrame.lookAt(base.Position + Vector3.new(-30, 40, -60), base.Position)
		advance(1.0)
		local gym = f.Home:FindFirstChild("Station_Gym")
		local att = gym and gym:FindFirstChild("Spot1", true)
		if not T.check(att ~= nil and att:IsA("Attachment"), "w6 train: the level-5 Training Place has its mat attachment Spot1") then
			root:Destroy()
			return
		end
		local function job()
			return "1=biscuit_bear:Physique:" .. tostring(math.floor(workspace:GetServerTimeNow()) + 300)
		end
		local function onMat()
			local g = HF.Garden(f)
			local e = g and g.Training[1]
			return e ~= nil and e.Model ~= nil and e.Model.Parent ~= nil and flat(e.Model:GetPivot().Position, att.WorldPosition) < 0.6, e
		end
		local saved = St.PetStage
		for _, stage in ipairs({ 0, 1 }) do
			St.PetStage = function()
				return stage
			end
			f:SetAttribute("TrainingPets", job())
			advance(1.0)
			local ok, e = onMat()
			T.check(ok and e.Stage == stage, "w6 train: the training pet stands on its mat (" .. (stage > 0 and "evolved" or "plain") .. ")", tostring(e and e.Stage))
			f:SetAttribute("TrainingPets", "")
			advance(0.5)
		end
		St.PetStage = saved
		-- the join-time order: the station is there, its mats' attachments are not yet
		local deck = att.Parent
		att.Parent = nil
		f:SetAttribute("TrainingPets", job())
		advance(1.0)
		T.check(not onMat(), "w6 train: (setup) without the mat attachment no pet is placed")
		att.Parent = deck
		advance(1.0)
		T.check(onMat(), "w6 train: a mat attachment that arrives after its station: the training pet appears on it")
		f:SetAttribute("TrainingPets", "")
		advance(0.3)
		cam.CFrame = savedCam
		root:Destroy()
		advance(0.2)
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
