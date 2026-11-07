-- smoke_lobby_fx.lua: lobby-shop Task 25 (spec 5.12 lobby motion, 5.9 the Join sign per player, 16.5 the shelf eggs'
-- turntable): client/Controllers/LobbyFxController. Loaded by tools/smoke.py in the CLIENT world:
--   client_lobby_fx   (client) stand-ins far from the client world's own parts (the client world has no lobby), the
--                     camera at their centre, the graphics quality stubbed through LobbyFxController._S.Quality0:
--     a part tagged NC_Spin 50 studs from the camera turns about its Y within 1 s, bobs within +-BobStuds (0.6), never
--       drifts sideways and stays upright; Moving() lists it; one 200 studs away stays exactly put and is not listed
--     an Egg_Epic part on a shelf (SpinSeconds 14, BobStuds 0.12, BobSeconds 3.2) turns once in 14 s (+-0.5 s) and bobs
--       within +-0.12; an Egg_Rare dressed mid-turn (an ML_Mesh child built at the egg's current pivot, as
--       MeshLibrary.Dress does) keeps its offset to the egg while it turns
--     a tagged Model (the world gem's shape: WorldPivot set, two parts) turns about its pivot with every part keeping its
--       offset; a mesh dressed mid-turn at its GetPivot() rides along; a part that streams in late at its built place
--       joins the motion at the right offset
--     a BillboardGui tagged NC_Bob (the Join sign) bobs its StudsOffset.Y within +-0.5 of its base, X and Z unchanged
--     Gfx Low: nothing moves, every target (and its mesh) rests at its built pivot, the sign at its base offset, none in
--       Moving(); back to High: they move again
--     TroveGroupDone true -> JoinBillboard.Enabled false; cleared -> true
--     lobby rebuilt (Review Focus 4): the trove (a new JoinBillboard), a spin target and the Egg Guide destroyed and built
--       again while the player has claimed -> the new sign is hidden, the new targets move, the old ones leave Moving()
--       and the controller keeps no record of them, no error
--     a target parked outside the workspace (GraphicsQuality's Low holder in ReplicatedStorage: no tag signal) rests at
--       its built pivot, and moves again once put back
-- Deterministic: the controller is stepped by hand (LobbyFxController.Step) with the camera put back before each step;
-- the mock clock only moves for the tag signals. Every stand-in is destroyed at the end. Plain Lua 5.1 syntax.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local fmt = string.format
local abs, max = math.abs, math.max
local TWO_PI = math.pi * 2

local S = {}

local Players = game:GetService("Players")
local CS = game:GetService("CollectionService")
local LocalPlayer = Players.LocalPlayer

local G = {}
G.O = Vector3.new(4000, 300, 4000) -- the stand-ins' centre: far from anything the client world builds
function G.req(key)
	local inst = Mock.GetPath(ROOTS[key:match("^(%a+)/")] .. "/" .. key:gsub("^%a+/", ""))
	if not inst then
		return nil
	end
	local ok, mod = pcall(require, inst)
	return ok and type(mod) == "table" and mod or nil
end
function G.part(name, pos, size, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.Size = size or Vector3.new(2, 2, 2)
	p.CFrame = typeof(pos) == "CFrame" and pos or CFrame.new(pos)
	p.Parent = parent or workspace
	return p
end
-- the builders' order: attributes, then the tag
function G.tag(inst, tag, spin, bob, bobT)
	if spin then
		inst:SetAttribute("SpinSeconds", spin)
	end
	inst:SetAttribute("BobStuds", bob)
	inst:SetAttribute("BobSeconds", bobT)
	CS:AddTag(inst, tag)
end
-- the yaw of a CFrame (radians, about the world Y)
function G.yaw(cf)
	local l = cf.LookVector
	return math.atan2(-l.X, -l.Z)
end
function G.wrap(a)
	while a > math.pi do
		a = a - TWO_PI
	end
	while a < -math.pi do
		a = a + TWO_PI
	end
	return a
end
function G.flat(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
-- two CFrames within eps (position and every axis)
function G.same(a, b, eps)
	eps = eps or 1e-4
	return (a.Position - b.Position).Magnitude <= eps and (a.LookVector - b.LookVector).Magnitude <= eps
		and (a.UpVector - b.UpVector).Magnitude <= eps and (a.RightVector - b.RightVector).Magnitude <= eps
end
function G.has(list, inst)
	for _, v in ipairs(list) do
		if v == inst then
			return true
		end
	end
	return false
end
function G.anyOf(list, set)
	local out = {}
	for _, inst in ipairs(set) do
		if G.has(list, inst) then
			out[#out + 1] = inst.Name
		end
	end
	return out
end
-- a stand-in for LobbyBuilder's trove Join sign: Model SkyTrove > JoinAnchor (invisible part) > JoinBillboard (NC_Bob)
function G.trove(at)
	local trove = Instance.new("Model")
	trove.Name = "SkyTrove"
	local anchor = G.part("JoinAnchor", at, Vector3.new(1, 1, 1), trove)
	anchor.Transparency = 1
	local join = Instance.new("BillboardGui")
	join.Name = "JoinBillboard"
	join.Size = UDim2.new(0, 360, 0, 110)
	join.StudsOffset = Vector3.new(0, 1, 0)
	join.Parent = anchor
	G.tag(join, "NC_Bob", nil, 0.5, 2.4)
	trove.Parent = workspace
	return trove, join
end
-- a stand-in for LobbyBoardBuilder.EggGuide: Model EggGuide > EggShelf + Egg_Epic + Egg_Rare (2.25 x 3 x 2.5, the shelf
-- turntable's attributes)
function G.guide(at)
	local guide = Instance.new("Model")
	guide.Name = "EggGuide"
	G.part("EggShelf", at + Vector3.new(0, -0.4, 0), Vector3.new(17.6, 0.8, 2.6), guide)
	local epic = G.part("Egg_Epic", at + Vector3.new(0, 1.5, 0), Vector3.new(2.25, 3, 2.5), guide)
	local rare = G.part("Egg_Rare", at + Vector3.new(2.5, 1.5, 0), Vector3.new(2.25, 3, 2.5), guide)
	G.tag(epic, "NC_Spin", 14, 0.12, 3.2)
	G.tag(rare, "NC_Spin", 14, 0.12, 3.2)
	guide.Parent = workspace
	return guide, epic, rare
end

S.client_lobby_fx = guarded("client_lobby_fx", function()
	local KC = _G.KC
	local Config = KC.env()
	local LF = G.req("client/Controllers/LobbyFxController")
	if not T.check(type(LF) == "table" and type(LF.Init) == "function" and type(LF.Step) == "function" and type(LF.Moving) == "function",
		"lobby fx: client/Controllers/LobbyFxController loads (Init, Step, Moving)") then
		return
	end
	local St = LF._S
	if not T.check(type(St) == "table" and type(St.Recs) == "table", "lobby fx: LobbyFxController._S with its records (tests stub the graphics quality)") then
		return
	end
	if not T.check(type(Config.Tags) == "table" and Config.Tags.Spin == "NC_Spin" and Config.Tags.Bob == "NC_Bob" and Config.Attr.TroveGroupDone == "TroveGroupDone",
		"lobby fx: Config.Tags.Spin / Bob and Config.Attr.TroveGroupDone") then
		return
	end
	local DONE = Config.Attr.TroveGroupDone
	local O = G.O
	local cam = workspace.CurrentCamera
	local cam0 = cam.CFrame
	local q0 = St.Quality0
	local done0 = LocalPlayer:GetAttribute(DONE)
	local mode = "High"
	St.Quality0 = { Effective = function()
		return mode
	end }
	local made = {}
	local function look()
		cam.CFrame = CFrame.new(O + Vector3.new(0, 5, 0))
	end
	-- steps the controller by hand for `seconds` (the camera put back before each step); each(t) after every step
	local function run(seconds, dt, each)
		dt = dt or 1 / 30
		local n = math.floor(seconds / dt + 0.5)
		for i = 1, n do
			look()
			LF.Step(dt)
			if each then
				each(i * dt)
			end
		end
	end
	local ok, err = pcall(function()
		LF.Init() -- idempotent: Main.client.lua has started it
		look()

		------------------------------------------------------------------ near turns and bobs, far stays put
		local near = G.part("FxNear", O + Vector3.new(50, 0, 0))
		local far = G.part("FxFar", O + Vector3.new(200, 0, 0))
		made[#made + 1] = near
		made[#made + 1] = far
		G.tag(near, "NC_Spin", 4, 0.6, 2)
		G.tag(far, "NC_Spin", 4, 0.6, 2)
		local nearBase, farBase = near.CFrame, far.CFrame
		KC.advance(0.05)
		local maxDy, maxFlat, maxTurn, minUp = 0, 0, 0, 1
		run(1, 1 / 30, function()
			maxDy = max(maxDy, abs(near.Position.Y - nearBase.Position.Y))
			maxFlat = max(maxFlat, G.flat(near.Position, nearBase.Position))
			maxTurn = max(maxTurn, abs(G.wrap(G.yaw(near.CFrame) - G.yaw(nearBase))))
			minUp = math.min(minUp, near.CFrame.UpVector.Y)
		end)
		T.check(maxTurn > 0.05, "lobby fx: a tagged part 50 studs from the camera turns about its Y within 1 s", fmt("%.3f rad", maxTurn))
		T.check(maxDy > 0.05 and maxDy <= 0.6 + 1e-6, "lobby fx: ...and bobs within +-0.6 (its BobStuds)", fmt("%.3f", maxDy))
		T.check(maxFlat < 1e-3 and minUp > 0.9999, "lobby fx: ...on its own spot (no sideways drift) and upright", fmt("drift %.4f, up %.5f", maxFlat, minUp))
		local moving = LF.Moving()
		T.check(G.has(moving, near) and not G.has(moving, far), "lobby fx: Moving() lists the near part, not the far one", fmt("%d moving", #moving))
		T.check(G.same(far.CFrame, farBase, 1e-9), "lobby fx: a tagged part 200 studs away stays exactly put")

		------------------------------------------------------------------ the shelf eggs: one turn in 14 s, bob +-0.12
		local guide, epic, rare = G.guide(O + Vector3.new(0, 0, 30))
		made[#made + 1] = guide
		local eBase = epic.CFrame
		KC.advance(0.05)
		run(0.6) -- the next pass picks it
		T.check(G.has(LF.Moving(), epic), "lobby fx: the shelf egg Egg_Epic moves")
		local dt, t, acc = 0.05, 0, 0
		local prev = G.yaw(epic.CFrame)
		local turnAt, eDy, eFlat = nil, 0, 0
		local meshPart, meshRel, meshErr = nil, nil, 0
		for i = 1, 300 do
			look()
			LF.Step(dt)
			t = t + dt
			local y = G.yaw(epic.CFrame)
			acc = acc + abs(G.wrap(y - prev))
			prev = y
			if not turnAt and acc >= TWO_PI - 1e-6 then
				turnAt = t
			end
			eDy = max(eDy, abs(epic.Position.Y - eBase.Position.Y))
			eFlat = max(eFlat, G.flat(epic.Position, eBase.Position))
			if i == 40 then
				-- dressed mid-turn: MeshLibrary.Dress builds the ML_Mesh at the target's current pivot * its offset
				local mesh = Instance.new("Model")
				mesh.Name = "ML_Mesh"
				meshRel = CFrame.new(0, 0.2, 0.3)
				meshPart = G.part("Shell", rare:GetPivot() * meshRel, Vector3.new(2.2, 3, 2.2), mesh)
				mesh.Parent = rare
			elseif meshPart then
				meshErr = max(meshErr, ((rare:GetPivot():Inverse() * meshPart.CFrame).Position - meshRel.Position).Magnitude)
			end
		end
		T.check(turnAt ~= nil and abs(turnAt - 14) <= 0.5, "lobby fx: the shelf egg turns once in 14 s (+-0.5 s)", tostring(turnAt))
		T.check(eDy > 0.05 and eDy <= 0.12 + 1e-6 and eFlat < 1e-3, "lobby fx: ...bobs within +-0.12 on its spot", fmt("bob %.3f, drift %.4f", eDy, eFlat))
		T.check(meshPart ~= nil and meshErr <= 1e-4 and G.same(rare:GetPivot():Inverse() * meshPart.CFrame, meshRel, 1e-4),
			"lobby fx: an egg dressed mid-turn (ML_Mesh at its current pivot) keeps the mesh at its offset while it turns")

		------------------------------------------------------------------ a tagged Model: pivot, parts, mesh, a late part
		local gem = Instance.new("Model")
		gem.Name = "FxGem"
		local gemCF = CFrame.new(O + Vector3.new(-30, 6, 0))
		local a = G.part("Gem", gemCF * CFrame.Angles(math.rad(45), 0, math.rad(45)), Vector3.new(4, 4, 4), gem)
		local b = G.part("Tip", gemCF * CFrame.new(0, 3, 1), Vector3.new(1, 1, 1), gem)
		gem.WorldPivot = gemCF
		G.tag(gem, "NC_Spin", 8, 0.6, 3)
		gem.Parent = workspace
		made[#made + 1] = gem
		local relA, relB = gemCF:Inverse() * a.CFrame, gemCF:Inverse() * b.CFrame
		KC.advance(0.05)
		run(1.2)
		local pivot = gem:GetPivot()
		T.check(abs(G.wrap(G.yaw(pivot) - G.yaw(gemCF))) > 0.05 and G.flat(pivot.Position, gemCF.Position) < 1e-3,
			"lobby fx: a tagged Model turns about its pivot (GetPivot follows)", fmt("%.3f rad", abs(G.wrap(G.yaw(pivot) - G.yaw(gemCF)))))
		T.check(G.same(pivot:Inverse() * a.CFrame, relA) and G.same(pivot:Inverse() * b.CFrame, relB), "lobby fx: ...every part keeps its offset to the pivot")
		local gmesh = Instance.new("Model")
		gmesh.Name = "ML_Mesh"
		local gRel = CFrame.new(0.5, -0.5, 0)
		local gPart = G.part("GemMesh", gem:GetPivot() * gRel, Vector3.new(3, 3, 3), gmesh)
		gmesh.Parent = gem
		local late = G.part("Late", gemCF * CFrame.new(1, 0, 0), Vector3.new(0.5, 0.5, 0.5), gem) -- streamed in at its built place
		run(1)
		pivot = gem:GetPivot()
		T.check(G.same(pivot:Inverse() * gPart.CFrame, gRel), "lobby fx: a mesh dressed on the Model mid-turn rides along at its offset")
		T.check(G.same(pivot:Inverse() * late.CFrame, CFrame.new(1, 0, 0)), "lobby fx: a part that streams in late at its built place joins the motion at the right offset")

		------------------------------------------------------------------ the Join sign bobs
		local trove, join = G.trove(O + Vector3.new(-20, 10, 20))
		made[#made + 1] = trove
		KC.advance(0.05)
		run(0.6)
		local sMin, sMax, sXZ = math.huge, -math.huge, 0
		run(2.4, 1 / 30, function()
			local so = join.StudsOffset
			sMin, sMax = math.min(sMin, so.Y), max(sMax, so.Y)
			sXZ = max(sXZ, abs(so.X) + abs(so.Z))
		end)
		T.check(sMax - sMin > 0.4 and sMin >= 1 - 0.5 - 1e-6 and sMax <= 1 + 0.5 + 1e-6 and sXZ < 1e-9,
			"lobby fx: a BillboardGui tagged NC_Bob bobs its StudsOffset.Y within +-0.5 of its base (X, Z unchanged)", fmt("%.3f .. %.3f", sMin, sMax))

		------------------------------------------------------------------ Gfx Low: nothing moves, everything rests
		mode = "Low"
		run(0.6)
		local rested = {}
		local function restCheck()
			local bad = {}
			if not G.same(near.CFrame, nearBase) then
				bad[#bad + 1] = "FxNear"
			end
			if not G.same(epic.CFrame, eBase) then
				bad[#bad + 1] = "Egg_Epic"
			end
			if not G.same(gem:GetPivot(), gemCF) or not G.same(a.CFrame, gemCF * relA) or not G.same(late.CFrame, gemCF * CFrame.new(1, 0, 0)) or not G.same(gPart.CFrame, gemCF * gRel) then
				bad[#bad + 1] = "FxGem"
			end
			if not G.same(meshPart.CFrame, rare:GetPivot() * meshRel) or (rare.Position - (eBase.Position + Vector3.new(2.5, 0, 0))).Magnitude > 1e-4 then
				bad[#bad + 1] = "Egg_Rare"
			end
			if (join.StudsOffset - Vector3.new(0, 1, 0)).Magnitude > 1e-9 then
				bad[#bad + 1] = "JoinBillboard " .. tostring(join.StudsOffset)
			end
			return bad
		end
		rested = restCheck()
		local all = { near, epic, rare, gem, join }
		T.check(#rested == 0, "lobby fx: Gfx Low -> every target rests at its built pivot (meshes too), the sign at its base offset", table.concat(rested, ", "))
		T.check(#G.anyOf(LF.Moving(), all) == 0, "lobby fx: Gfx Low -> nothing in Moving()", table.concat(G.anyOf(LF.Moving(), all), ", "))
		run(1)
		rested = restCheck()
		T.check(#rested == 0, "lobby fx: Gfx Low -> nothing moves a second later", table.concat(rested, ", "))
		mode = "High"
		run(0.7)
		T.check(G.has(LF.Moving(), near) and G.has(LF.Moving(), epic) and G.has(LF.Moving(), join) and not G.same(near.CFrame, nearBase),
			"lobby fx: back to High -> they move again")

		------------------------------------------------------------------ the Join sign per player
		LocalPlayer:SetAttribute(DONE, true)
		KC.advance(0.05)
		T.eq(join.Enabled, false, "lobby fx: TroveGroupDone true -> JoinBillboard.Enabled false")
		LocalPlayer:SetAttribute(DONE, nil)
		KC.advance(0.05)
		T.eq(join.Enabled, true, "lobby fx: TroveGroupDone cleared -> JoinBillboard.Enabled true")

		------------------------------------------------------------------ the lobby rebuilt (Review Focus 4)
		LocalPlayer:SetAttribute(DONE, true)
		KC.advance(0.05)
		local old = { near, epic, rare, join }
		trove:Destroy()
		near:Destroy()
		guide:Destroy()
		KC.advance(0.05)
		local trove2, join2 = G.trove(O + Vector3.new(-20, 10, 24))
		local near2 = G.part("FxNear", O + Vector3.new(50, 0, 4))
		G.tag(near2, "NC_Spin", 4, 0.6, 2)
		local guide2, epic2 = G.guide(O + Vector3.new(0, 0, 34))
		made[#made + 1] = trove2
		made[#made + 1] = near2
		made[#made + 1] = guide2
		KC.advance(0.05)
		T.eq(join2.Enabled, false, "lobby fx: lobby rebuilt -> the new Join sign is hidden for the player who claimed")
		run(1)
		moving = LF.Moving()
		T.check(G.has(moving, near2) and G.has(moving, epic2) and G.has(moving, join2), "lobby fx: lobby rebuilt -> the new targets move (spin part, shelf egg, sign)")
		T.check(#G.anyOf(moving, old) == 0, "lobby fx: lobby rebuilt -> the old targets leave Moving()", table.concat(G.anyOf(moving, old), ", "))
		local kept = {}
		for _, inst in ipairs(old) do
			if St.Recs[inst] ~= nil then
				kept[#kept + 1] = inst.Name
			end
		end
		T.check(#kept == 0, "lobby fx: lobby rebuilt -> no record kept for a destroyed target", table.concat(kept, ", "))

		------------------------------------------------------------------ parked and put back (GraphicsQuality's holder)
		-- Low graphics parks NC_Detail decor in a ReplicatedStorage folder and High puts it back: the target never leaves the
		-- game, so no tag signal fires; it must rest while parked and move again once back
		local near2Base = CFrame.new(O + Vector3.new(50, 0, 4))
		local park = Instance.new("Folder")
		park.Name = "FxParked"
		park.Parent = game:GetService("ReplicatedStorage")
		made[#made + 1] = park
		near2.Parent = park
		run(0.6)
		T.check(not G.has(LF.Moving(), near2) and G.same(near2.CFrame, near2Base), "lobby fx: a target parked outside the workspace rests at its built pivot and stops")
		near2.Parent = workspace
		run(0.7)
		T.check(G.has(LF.Moving(), near2) and not G.same(near2.CFrame, near2Base), "lobby fx: ...and moves again once it is put back")

		KC.flushErrors("client_lobby_fx")
		KC.flushWarnings("client_lobby_fx")
	end)
	for _, inst in ipairs(made) do
		pcall(function()
			inst:Destroy()
		end)
	end
	LocalPlayer:SetAttribute(DONE, done0)
	St.Quality0 = q0
	cam.CFrame = cam0
	KC.advance(0.1)
	if not ok then
		error(err, 0)
	end
end)

return S
