-- smoke_p2_fix_client.lua: regression checks for the Phase 2 review fixes on the client (HomeFx). Loaded by
-- tools/smoke.py in the CLIENT world only:
--   client_p2fix_signs  pad signs stay readable (World text rule). A real home (HomeBuilder, as the server builds it)
--                       is owned by the local player and seen through a Roblox classic camera (12.5 studs behind the
--                       character, 15 degrees down, 70 degree field of view) with a real perspective projection (the
--                       mock's camera projects every point to the screen centre, so these scenarios put a real one
--                       on Camera.WorldToViewportPoint and take it off again). From the gate path of a mid-game
--                       Villa at 1920x1080 and on an 844x390 phone (where the old code piled 14 and 7 signs into an
--                       unreadable stack), and along a walk up the path, no shown sign's plate covers the text of
--                       another (checked on the labels' own boxes), the pile really is there (crowded signs), the
--                       nearest sign shows, a sign that is mostly off the screen does not; a still player with a
--                       slightly moving camera sees no sign flicker, a walk shows no flashes and no overlap lasting
--                       past one layout pass; a sign HomeBuilder rebuilds (new price) keeps its pad's answer at
--                       once; standing at a locked pad shows its lock reason; another player's signs stay hidden
--                       (HomeFx.SignState says why for every sign)
--   client_p2fix_pets   garden / gym pets are built under a per-frame budget (the review measured 13 PetBuilder
--                       builds in ONE frame, ~100 ms, when a full neighbour home came into range): a full home
--                       (Garden L8 with 8 pets, Gym L5 with 5) fills in over several frames, never more than
--                       3 models in a frame, a first-time build alone in its frame; with a simulated CPU clock
--                       (5 ms per PetBuilder.Build) only one build fits the 4 ms frame budget; pets of a home that
--                       goes out of range wait in a pool (<= 16 models, unparented) and come back from it without
--                       a single new build, on their own cushions / targets; nothing is left behind
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local abs, floor, max, min, huge = math.abs, math.floor, math.max, math.min, math.huge

local function fmt(v, n)
	if type(v) ~= "number" then
		return tostring(v)
	end
	return string.format("%." .. (n or 2) .. "f", v)
end

local KC = _G.KC
local S = {}
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local function moduleAt(top, rest)
	local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	return ok and type(result) == "table" and result or nil
end

local function step(n)
	for _ = 1, n or 1 do
		Mock.Step()
	end
end

----------------------------------------------------------------------------------------------------
-- a real perspective camera for the mock (vertical field of view, viewport pixels, depth along the look)
----------------------------------------------------------------------------------------------------
local camMethods = Mock.Classes and Mock.Classes.Camera and Mock.Classes.Camera.methods
local savedProject = nil

local function project(self, pos)
	local rel = self.CFrame:PointToObjectSpace(pos)
	local vp = Mock.Viewport
	local depth = -rel.Z
	local f = (vp.Y / 2) / math.tan(math.rad(self.FieldOfView / 2))
	local d = depth
	if abs(d) < 1e-6 then
		d = 1e-6
	end
	local x = vp.X / 2 + rel.X / d * f
	local y = vp.Y / 2 - rel.Y / d * f
	return Vector3.new(x, y, depth), depth > 0 and x >= 0 and x <= vp.X and y >= 0 and y <= vp.Y
end

local function installProjection()
	if camMethods and not savedProject then
		savedProject = { camMethods.WorldToViewportPoint, camMethods.WorldToScreenPoint }
		camMethods.WorldToViewportPoint = project
		camMethods.WorldToScreenPoint = project
	end
	return camMethods ~= nil
end

local function removeProjection()
	if camMethods and savedProject then
		camMethods.WorldToViewportPoint = savedProject[1]
		camMethods.WorldToScreenPoint = savedProject[2]
		savedProject = nil
	end
end

-- Roblox's classic camera behind a character standing at plot-local (sx, sz), looking toward (lx, lz)
local function classicCamera(plotCF, sx, sz, lx, lz, zoom, pitchDeg)
	local pitch = math.rad(pitchDeg or 15)
	local focus = Vector3.new(sx, 4.5, sz)
	local flat = Vector3.new(lx - sx, 0, lz - sz).Unit
	local fwd = Vector3.new(flat.X * math.cos(pitch), -math.sin(pitch), flat.Z * math.cos(pitch))
	local camPos = focus - fwd * (zoom or 12.5)
	return plotCF * CFrame.lookAt(camPos, camPos + fwd)
end

----------------------------------------------------------------------------------------------------
-- the screen boxes of a pad sign: its plate and the boxes of its text labels (as the camera draws them)
----------------------------------------------------------------------------------------------------
local function signBoxes(gui, cam)
	local anchor = gui.Adornee or gui.Parent
	if not anchor or not anchor:IsA("BasePart") then
		return nil
	end
	local world = anchor.Position + gui.StudsOffsetWorldSpace
	if gui.MaxDistance > 0 and (world - cam.CFrame.Position).Magnitude > gui.MaxDistance then
		return nil
	end
	local p = cam:WorldToViewportPoint(world)
	if p.Z <= 0 then
		return nil
	end
	local plate = gui:FindFirstChild("Plate")
	if not plate then
		return nil
	end
	local size = plate.AbsoluteSize
	local bw, bh = gui.Size.X.Offset, gui.Size.Y.Offset
	local cx = p.X + gui.SizeOffset.X * bw
	local bottom = p.Y - gui.SizeOffset.Y * bh + bh / 2
	local box = { x0 = cx - size.X / 2, y0 = bottom - size.Y, x1 = cx + size.X / 2, y1 = bottom, Texts = {} }
	local origin = plate.AbsolutePosition
	for _, d in ipairs(plate:GetDescendants()) do
		if d:IsA("TextLabel") and d.Visible and d.Text ~= "" then
			local ap, as = d.AbsolutePosition, d.AbsoluteSize
			local x0, y0 = box.x0 + ap.X - origin.X, box.y0 + ap.Y - origin.Y
			box.Texts[#box.Texts + 1] = { x0 = x0, y0 = y0, x1 = x0 + as.X, y1 = y0 + as.Y, Name = d.Name }
		end
	end
	return box
end

local EDGE = 3.5 -- px of the plate's outline (HomeBuilder's Edge stroke), drawn outside the plate

local function boxesMeet(a, b, grow)
	grow = grow or 0
	return min(a.x1 + grow, b.x1) > max(a.x0 - grow, b.x0) and min(a.y1 + grow, b.y1) > max(a.y0 - grow, b.y0)
end

-- true when either plate (with its outline) reaches into the other's text
local function coversText(a, b)
	for _, t in ipairs(b.Texts) do
		if boxesMeet(a, t, EDGE) then
			return true
		end
	end
	for _, t in ipairs(a.Texts) do
		if boxesMeet(b, t, EDGE) then
			return true
		end
	end
	return false
end

-- plate share inside the screen
local function onScreen(box)
	local vp = Mock.Viewport
	local w, h = box.x1 - box.x0, box.y1 - box.y0
	local inside = max(0, min(vp.X, box.x1) - max(0, box.x0)) * max(0, min(vp.Y, box.y1) - max(0, box.y0))
	return w > 0 and h > 0 and inside / (w * h) or 0
end

local function padOf(gui)
	local node = gui.Parent
	for _ = 1, 6 do
		if not node then
			return nil
		end
		if node:IsA("Model") and node:GetAttribute("StationId") ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function padSigns(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BillboardGui") and d.Name == "PadSign" then
			local pad = padOf(d)
			out[#out + 1] = { Gui = d, Pad = pad, Id = pad and tostring(pad:GetAttribute("StationId")) or "?", Locked = pad and (pad:GetAttribute("Locked") or "") ~= "" }
		end
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- client_p2fix_signs
----------------------------------------------------------------------------------------------------
S.client_p2fix_signs = guarded("client_p2fix_signs", function()
	local HF = (KC and KC.M and KC.M.HomeFx) or moduleAt("client", "Controllers/HomeFx")
	local HB = moduleAt("server", "Services/HomeBuilder")
	local TC = moduleAt("shared", "TycoonCatalog")
	if not T.check(type(HF) == "table" and type(HF.Init) == "function", "HomeFx fix: client/Controllers/HomeFx.lua loads with Init") then
		return
	end
	T.check(type(HF.SignState) == "function", "HomeFx fix: HomeFx.SignState tells why a pad sign shows or not")
	-- (the overlap checks below only look at Enabled, so they judge any HomeFx; SignState refines them)
	local function signState(gui)
		if type(HF.SignState) ~= "function" then
			return nil
		end
		return HF.SignState(gui)
	end
	if not (HB and TC) then
		T.warn("HomeFx fix: HomeBuilder / TycoonCatalog missing in the client world, sign layout skipped")
		return
	end
	if not installProjection() then
		T.warn("HomeFx fix: the mock has no Camera class table, sign layout skipped")
		return
	end
	HF.Init()
	local outputBefore, errorsBefore = #Mock.Output, #Mock.Errors
	local cam = workspace.CurrentCamera
	local savedCam = cam and cam.CFrame
	local savedViewport = Mock.Viewport
	local character = LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local savedHrp, savedAnchored = hrp and hrp.CFrame, hrp and hrp.Anchored
	local root = Instance.new("Folder")
	root.Name = "SmokeFixSigns"
	root.Parent = workspace
	local neighbour = nil

	local ok, err = pcall(function()
		if not (cam and hrp) then
			T.warn("HomeFx fix: no camera or character in the client world, sign layout skipped")
			return
		end
		hrp.Anchored = true
		local base = CFrame.new(5600, 300, 5600)
		local function makeSpot(index, cf)
			local f = Instance.new("Folder")
			f.Name = string.format("Spot_%02d", index)
			f.Parent = root
			return { Index = index, PlotCFrame = cf, PlotSize = TC.PlotSize, Center = cf.Position, Folder = f }
		end
		local mine = makeSpot(71, base)
		local theirs = makeSpot(72, base * CFrame.new(0, 0, 200))
		neighbour = Mock.AddPlayer("SignNeighbour", 7171, { character = false })
		-- the review's mid-game Villa (17 pads: the old code stacked 14 of them on the screen from the gate path)
		local stations = { Press1 = 5, Press2 = 3, Collector = 3, Garden = 2, Kitchen = 2, Gym = 1, Vault = 1, House = 2, DecorLamps = 1 }
		local home = { Stations = stations, Prestige = 0 }
		for _, sp in ipairs({ mine, theirs }) do
			HB.PreparePlot(sp)
		end
		HB.SetOwner(mine, LocalPlayer)
		HB.SetOwner(theirs, neighbour)
		HB.BuildHome(mine, home)
		HB.SetPads(mine, TC.AvailablePads(home))
		HB.BuildHome(theirs, home)
		HB.SetPads(theirs, TC.AvailablePads(home))
		LocalPlayer:SetAttribute("Cash", 0)
		local plot = mine.PlotCFrame
		local mySigns = padSigns(mine.Folder)
		local theirSigns = padSigns(theirs.Folder)

		local function stand(sx, sz, lx, lz)
			hrp.CFrame = CFrame.new((plot * CFrame.new(sx, 3, sz)).Position)
			cam.CFrame = classicCamera(plot, sx, sz, lx or sx, lz or (sz + 40))
		end

		-- the layout at one view: shown signs never cover each other's text, the pile is real, the nearest shows
		local function audit(label, minShown)
			local shown, crowded, eligible = {}, 0, {}
			local states = {}
			for _, s in ipairs(mySigns) do
				local why = signState(s.Gui)
				states[why or "nil"] = (states[why or "nil"] or 0) + 1
				if why == "Shown" or why == "Crowded" or (why == nil and s.Gui.Enabled) then
					local box = signBoxes(s.Gui, cam)
					if box then
						eligible[#eligible + 1] = { Sign = s, Box = box }
					end
				end
				if s.Gui.Enabled then
					local box = signBoxes(s.Gui, cam)
					if box then
						shown[#shown + 1] = { Sign = s, Box = box }
					end
				end
				if why == "Crowded" then
					crowded = crowded + 1
				end
			end
			local clash, clashText = 0, ""
			for i = 1, #shown do
				for j = i + 1, #shown do
					if coversText(shown[i].Box, shown[j].Box) then
						clash = clash + 1
						clashText = shown[i].Sign.Id .. " / " .. shown[j].Sign.Id
					end
				end
			end
			local pile = 0
			for i = 1, #eligible do
				for j = i + 1, #eligible do
					if coversText(eligible[i].Box, eligible[j].Box) then
						pile = pile + 1
					end
				end
			end
			local cut = 0
			for _, e in ipairs(shown) do
				if onScreen(e.Box) < 0.8 then
					cut = cut + 1
				end
			end
			local parts = {}
			for k, v in pairs(states) do
				parts[#parts + 1] = k .. " " .. v
			end
			table.sort(parts)
			local summary = #shown .. " shown (" .. table.concat(parts, ", ") .. ")"
			T.info("HomeFx fix: " .. label .. ": " .. summary .. ", " .. pile .. " overlapping pairs if all eligible signs showed")
			T.check(#shown >= minShown and clash == 0, "HomeFx fix: " .. label .. ": no shown pad sign covers the text of another (" .. minShown .. "+ shown)",
				summary .. (clash > 0 and (", text covered: " .. clashText) or ""))
			T.check(pile > 0 and crowded > 0, "HomeFx fix: " .. label .. ": ...where every eligible sign at once would stack (the layout held some back)",
				pile .. " overlapping pairs among the eligible signs, " .. crowded .. " crowded")
			T.check(cut == 0, "HomeFx fix: " .. label .. ": no shown sign is cut off by the screen edge", cut .. " cut")
			local st = HF.Stats()
			local enabled = 0
			for _, s in ipairs(mySigns) do
				if s.Gui.Enabled then
					enabled = enabled + 1
				end
			end
			T.check(tonumber(st.SignsShown) ~= nil and tonumber(st.SignsShown) >= enabled and tonumber(st.SignsCrowded) >= crowded,
				"HomeFx fix: " .. label .. ": Stats() counts the shown and crowded signs", "SignsShown " .. tostring(st.SignsShown) .. ", SignsCrowded " .. tostring(st.SignsCrowded))
			return shown
		end

		-- 1. the gate path of the review at 1920x1080, then on an 844x390 phone
		Mock.SetViewport(1920, 1080)
		stand(0, -30, 0, 10)
		KC.advance(1.0)
		local shown = audit("Villa from the gate path at 1920x1080", 4)
		-- the sign nearest the player (on the screen, not locked) shows
		local nearest, nearestD = nil, huge
		for _, s in ipairs(mySigns) do
			local why = signState(s.Gui)
			if (why == "Shown" or why == "Crowded" or (why == nil and s.Gui.Enabled)) and not s.Locked then
				local box = signBoxes(s.Gui, cam)
				local anchor = s.Gui.Adornee or s.Gui.Parent
				local d = (anchor.Position - hrp.Position).Magnitude
				if box and onScreen(box) >= 0.99 and d < nearestD then
					nearest, nearestD = s, d
				end
			end
		end
		T.check(nearest ~= nil and nearest.Gui.Enabled, "HomeFx fix: ...the sign of the pad nearest the player shows", nearest and (nearest.Id .. " " .. tostring(signState(nearest.Gui))) or "none on screen")
		local shownIds = {}
		for _, e in ipairs(shown) do
			shownIds[e.Sign.Gui] = true
		end

		-- 2. a still player, the camera drifting a little (breathing, a nudge of the mouse): nothing flickers
		local toggles = 0
		local last = {}
		for _, s in ipairs(mySigns) do
			last[s.Gui] = s.Gui.Enabled
		end
		local still = classicCamera(plot, 0, -30, 0, 10)
		for i = 1, 90 do
			local wob = math.sin(i * 0.7)
			cam.CFrame = still * CFrame.new(0.15 * wob, 0.1 * math.cos(i * 0.5), 0) * CFrame.Angles(0, math.rad(0.5) * wob, 0)
			step(1)
			for _, s in ipairs(mySigns) do
				if s.Gui.Enabled ~= last[s.Gui] then
					toggles = toggles + 1
					last[s.Gui] = s.Gui.Enabled
				end
			end
		end
		T.check(toggles == 0, "HomeFx fix: a still player with a slightly moving camera sees no sign flicker", toggles .. " toggles in 3 s")

		-- 3. a sign HomeBuilder rebuilds (its price changed) keeps its pad's answer at once: no blink
		cam.CFrame = still
		KC.advance(0.5)
		local shownPad, crowdedPad = nil, nil
		for _, s in ipairs(mySigns) do
			local why = signState(s.Gui)
			if not s.Locked and s.Gui.Parent then
				if why == "Shown" and not shownPad then
					shownPad = s
				elseif why == "Crowded" and not crowdedPad then
					crowdedPad = s
				end
			end
		end
		if shownPad and crowdedPad then
			local pads = TC.AvailablePads(home)
			for _, pad in ipairs(pads) do
				if pad.StationId == shownPad.Id or pad.StationId == crowdedPad.Id then
					pad.Price = (tonumber(pad.Price) or 0) + 7 -- a new price: HomeBuilder builds a new sign
				end
			end
			HB.SetPads(mine, pads)
			local newShown = shownPad.Pad and shownPad.Pad.Parent and shownPad.Pad:FindFirstChild("PadSign", true)
			local newCrowded = crowdedPad.Pad and crowdedPad.Pad.Parent and crowdedPad.Pad:FindFirstChild("PadSign", true)
			T.check(newShown ~= nil and newShown ~= shownPad.Gui and newShown.Enabled and newCrowded ~= nil and newCrowded ~= crowdedPad.Gui and not newCrowded.Enabled,
				"HomeFx fix: a rebuilt pad sign (new price) keeps its pad's answer at once (shown stays shown, crowded stays hidden)",
				shownPad.Id .. " " .. tostring(newShown and newShown.Enabled) .. ", " .. crowdedPad.Id .. " " .. tostring(newCrowded and newCrowded.Enabled))
			KC.advance(0.3)
			mySigns = padSigns(mine.Folder)
		else
			T.fail("HomeFx fix: a rebuilt pad sign keeps its pad's answer", "no shown + crowded unlocked pair to rebuild")
		end

		-- 4. another player's pad signs stay hidden, and SignState says why
		local theirsShown, theirsOther = 0, 0
		for _, s in ipairs(theirSigns) do
			if s.Gui.Enabled then
				theirsShown = theirsShown + 1
			end
			if signState(s.Gui) == "Other" then
				theirsOther = theirsOther + 1
			end
		end
		T.check(#theirSigns > 0 and theirsShown == 0 and theirsOther == #theirSigns, "HomeFx fix: another player's pad signs stay hidden (SignState \"Other\")",
			theirsShown .. " shown, " .. theirsOther .. " of " .. #theirSigns .. " Other")

		-- 5. the phone: the old code covered Cloud Press 1 / 2 and the Pet Garden completely here
		Mock.SetViewport(844, 390)
		stand(0, -30, 0, 10)
		KC.advance(1.0)
		audit("Villa from the gate path on an 844x390 phone", 2)
		Mock.SetViewport(1920, 1080)

		-- 6. a walk up the gate path (16 studs/s): no overlap outlives a layout pass, no flashes
		stand(0, -34, 0, 10)
		KC.advance(1.0)
		local overlapRun, worstRun, worstPair = {}, 0, ""
		local lastOn, lastAt, flashes, flashText = {}, {}, 0, ""
		local frame = 0
		for _, s in ipairs(mySigns) do
			lastOn[s.Gui] = s.Gui.Enabled
		end
		for z = -34, 8, 16 / 30 do
			stand(0, z, 0, z + 40)
			step(1)
			frame = frame + 1
			local live = {}
			for _, s in ipairs(mySigns) do
				if s.Gui.Enabled ~= lastOn[s.Gui] then
					if lastAt[s.Gui] and frame - lastAt[s.Gui] < 9 then
						flashes = flashes + 1
						flashText = s.Id .. " after " .. (frame - lastAt[s.Gui]) .. " frames"
					end
					lastAt[s.Gui] = frame
					lastOn[s.Gui] = s.Gui.Enabled
				end
				if s.Gui.Enabled then
					local box = signBoxes(s.Gui, cam)
					if box then
						live[#live + 1] = { Sign = s, Box = box }
					end
				end
			end
			local now = {}
			for i = 1, #live do
				for j = i + 1, #live do
					if coversText(live[i].Box, live[j].Box) then
						local key = live[i].Sign.Id .. "/" .. live[j].Sign.Id
						now[key] = (overlapRun[key] or 0) + 1
						if now[key] > worstRun then
							worstRun, worstPair = now[key], key
						end
					end
				end
			end
			overlapRun = now
		end
		-- a layout pass every 0.1 s (3 frames): an overlap the walk creates is gone by the next pass
		T.info("HomeFx fix: gate path walk: " .. frame .. " frames, longest overlap " .. worstRun .. " frames, " .. flashes .. " flashes")
		T.check(worstRun <= 4, "HomeFx fix: walking up the gate path, no two signs overlap past one layout pass", "longest overlap " .. worstRun .. " frames (" .. worstPair .. ")")
		T.check(flashes <= 2, "HomeFx fix: ...and signs do not flash on and off (at most 2 changes back within 0.3 s)", flashes .. " flashes" .. (flashText ~= "" and (", e.g. " .. flashText) or ""))

		-- 7. standing right at a locked pad shows why it is locked (its prompt is off: the sign is the only place)
		local lockedSign, lockedD = nil, 0
		local gatePos = (plot * CFrame.new(0, 3, -30)).Position
		for _, s in ipairs(mySigns) do
			local anchor = s.Locked and s.Gui.Parent and (s.Gui.Adornee or s.Gui.Parent)
			local d = anchor and (anchor.Position - gatePos).Magnitude or 0
			if anchor and d > 40 and d > lockedD then
				lockedSign, lockedD = s, d
			end
		end
		if lockedSign then
			local anchor = lockedSign.Gui.Adornee or lockedSign.Gui.Parent
			local lp = plot:PointToObjectSpace(anchor.Position)
			stand(lp.X - 4, lp.Z - 5, lp.X, lp.Z + 10)
			KC.advance(0.8)
			T.check(lockedSign.Gui.Enabled and signState(lockedSign.Gui) == "Shown", "HomeFx fix: standing at a locked pad shows its lock reason even with other signs around",
				lockedSign.Id .. " " .. tostring(signState(lockedSign.Gui)))
			stand(0, -30, 0, 10)
			KC.advance(1.0)
			T.check(not lockedSign.Gui.Enabled and signState(lockedSign.Gui) == "Locked", "HomeFx fix: ...and from afar it is hidden as a locked pad (SignState \"Locked\")",
				tostring(signState(lockedSign.Gui)))
		else
			T.warn("HomeFx fix: no locked pad on the test home, lock-reason check skipped")
		end
	end)
	-- put everything back
	Mock.SetViewport(savedViewport.X, savedViewport.Y)
	removeProjection()
	if hrp and savedHrp then
		hrp.CFrame = savedHrp
		hrp.Anchored = savedAnchored
	end
	if cam and savedCam then
		cam.CFrame = savedCam
	end
	root:Destroy()
	if neighbour then
		Mock.RemovePlayer(neighbour)
	end
	LocalPlayer:SetAttribute("Cash", nil)
	KC.advance(0.3)
	if not ok then
		T.fail("HomeFx fix: sign layout scenario raised an error", tostring(err))
	end
	local warned = nil
	for i = outputBefore + 1, #Mock.Output do
		local o = Mock.Output[i]
		if o.kind == "warn" and o.text:find("HomeFx", 1, true) then
			warned = o.text
		end
	end
	T.check(warned == nil and #Mock.Errors == errorsBefore, "HomeFx fix: no errors or warnings from HomeFx (signs)", tostring(warned))
	KC.flushErrors("client_p2fix_signs")
end)

----------------------------------------------------------------------------------------------------
-- client_p2fix_pets
----------------------------------------------------------------------------------------------------
S.client_p2fix_pets = guarded("client_p2fix_pets", function()
	local HF = (KC and KC.M and KC.M.HomeFx) or moduleAt("client", "Controllers/HomeFx")
	local HB = moduleAt("server", "Services/HomeBuilder")
	local TC = moduleAt("shared", "TycoonCatalog")
	local PC = moduleAt("shared", "PetCatalog")
	local PB = moduleAt("shared", "PetBuilder")
	if not T.check(type(HF) == "table" and type(HF.Stats) == "function", "HomeFx fix: client/Controllers/HomeFx.lua loads with Stats") then
		return
	end
	if not (HB and TC and PC and PB and type(PC.Pets) == "table") then
		T.warn("HomeFx fix: HomeBuilder / TycoonCatalog / PetCatalog / PetBuilder missing in the client world, pet budget skipped")
		return
	end
	HF.Init()
	local outputBefore, errorsBefore = #Mock.Output, #Mock.Errors
	local cam = workspace.CurrentCamera
	local savedCam = cam and cam.CFrame
	local root = Instance.new("Folder")
	root.Name = "SmokeFixPets"
	root.Parent = workspace
	local neighbour = Mock.AddPlayer("PetNeighbour", 7272, { character = false })
	local realClock, realBuild = os.clock, PB.Build
	local stats = HF.Stats
	local function n(st, key)
		return tonumber(st[key]) or 0
	end
	local function petsFolder()
		local cfx = workspace:FindFirstChild("ClientFx")
		return cfx and cfx:FindFirstChild("HomePets")
	end

	local ok, err = pcall(function()
		if not cam then
			T.warn("HomeFx fix: no camera in the client world, pet budget skipped")
			return
		end
		-- 13 different pets (from the end of the catalog: keys no other scenario showed in a home yet)
		local ids = {}
		for i = #PC.Pets, 1, -1 do
			local d = PC.Pets[i]
			if type(d) == "table" and type(d.Id) == "string" and #ids < 13 then
				ids[#ids + 1] = d.Id
			end
		end
		if #ids < 13 then
			T.warn("HomeFx fix: fewer than 13 catalog pets, pet budget skipped")
			return
		end
		local garden, gym = {}, {}
		for i = 1, 8 do
			garden[#garden + 1] = i .. "=" .. ids[i]
		end
		for i = 1, 5 do
			gym[#gym + 1] = i .. "=" .. ids[8 + i]
		end
		local base = CFrame.new(-5600, 300, -5600)
		local function makeHome(index, cf)
			local f = Instance.new("Folder")
			f.Name = string.format("Spot_%02d", index)
			f.Parent = root
			local spot = { Index = index, PlotCFrame = cf, PlotSize = TC.PlotSize, Center = cf.Position, Folder = f }
			HB.PreparePlot(spot)
			HB.SetOwner(spot, neighbour)
			-- an endgame neighbour: Garden L8 (8 places) and Gym L5 (5 places), all taken
			HB.BuildHome(spot, { Stations = { Press1 = 10, Collector = 5, House = 4, Garden = 8, Gym = 5, Kitchen = 4, Vault = 4 }, Prestige = 1 })
			f:SetAttribute("GardenPets", table.concat(garden, ";"))
			f:SetAttribute("GymPets", table.concat(gym, ";"))
			return spot
		end
		local far = base * CFrame.new(0, 60, -600)
		cam.CFrame = CFrame.lookAt(far.Position, far.Position + Vector3.new(0, 0, -1))
		local a = makeHome(73, base)
		local b = makeHome(74, base * CFrame.new(0, 0, 150))
		KC.advance(1.0)
		local st0 = stats()
		local onA = 0 -- pets standing in home A / B right now (models in HomePets near their cushions)
		local function countAt(spot)
			local pf = petsFolder()
			local c = 0
			if not pf then
				return 0
			end
			local center = spot.PlotCFrame.Position
			for _, m in ipairs(pf:GetChildren()) do
				local okPivot, pivot = pcall(function()
					return m:GetPivot()
				end)
				if okPivot and pivot and (pivot.Position - center).Magnitude < 60 then
					c = c + 1
				end
			end
			return c
		end
		T.check(countAt(a) == 0 and countAt(b) == 0, "HomeFx fix: a full home far from the camera shows no pets")

		-- watches frames until `want` pets stand at `spot` (or `limit` frames). Placements per frame are counted on the
		-- pets that newly stand there (so any HomeFx is judged); first-time builds come from Stats().PetColdBuilds
		local function watch(spot, want, limit)
			local before = stats()
			local frames, worst, coldAlone, coldBad = 0, 0, 0, 0
			local standing = countAt(spot)
			local coldPrev = n(before, "PetColdBuilds")
			local reached = standing >= want
			while not reached and frames < limit do
				step(1)
				frames = frames + 1
				local now = countAt(spot)
				local cold = n(stats(), "PetColdBuilds")
				local dp, dc = now - standing, cold - coldPrev
				standing, coldPrev = now, cold
				worst = max(worst, dp)
				if dc > 0 then
					if dc == 1 and dp == 1 then
						coldAlone = coldAlone + 1
					else
						coldBad = coldBad + 1
					end
				end
				reached = now >= want
			end
			local after = stats()
			return {
				Frames = frames,
				Worst = worst,
				ColdAlone = coldAlone,
				ColdBad = coldBad,
				Reached = reached,
				HasStats = before.PetColdBuilds ~= nil and before.PetBuilds ~= nil and before.PetPoolHits ~= nil,
				Builds = n(after, "PetBuilds") - n(before, "PetBuilds"),
				Hits = n(after, "PetPoolHits") - n(before, "PetPoolHits"),
				Cold = n(after, "PetColdBuilds") - n(before, "PetColdBuilds"),
			}
		end

		-- 1. the first approach to home A: 13 pets (first-time builds) fill in over frames, one cold build per frame
		cam.CFrame = CFrame.lookAt((base * CFrame.new(0, 40, -70)).Position, base.Position)
		local r1 = watch(a, 13, 120)
		onA = countAt(a)
		local function info(label, r)
			T.info(string.format("HomeFx fix: %s: %d frames, at most %d a frame, %d built (%d first-time), %d from the pool", label, r.Frames, r.Worst, r.Builds, r.Cold, r.Hits))
		end
		info("first approach to home A", r1)
		T.check(r1.Reached and onA == 13, "HomeFx fix: a full neighbour home (Garden L8 + Gym L5) shows all 13 of its pets", onA .. " pets after " .. r1.Frames .. " frames")
		T.check(r1.Worst <= 3 and r1.Frames >= 5, "HomeFx fix: ...built over several frames, never more than 3 in one (the review saw 13 in one frame)",
			"at most " .. r1.Worst .. " in a frame, " .. r1.Frames .. " frames")
		T.check(r1.HasStats and r1.ColdBad == 0 and (r1.Cold == 0 or r1.ColdAlone == r1.Cold), "HomeFx fix: ...a first-time build is alone in its frame (Stats().PetColdBuilds)",
			r1.Cold .. " first-time builds, " .. r1.ColdAlone .. " alone, " .. r1.ColdBad .. " shared a frame")
		local placedOk = true
		local gardenStation = a.Folder:FindFirstChild("Station_Garden", true)
		local pf = petsFolder()
		for slot = 1, 8 do
			local att = gardenStation and gardenStation:FindFirstChild("Spot" .. slot, true)
			local found = false
			for _, m in ipairs(pf and pf:GetChildren() or {}) do
				local okPivot, pivot = pcall(function()
					return m:GetPivot()
				end)
				if att and okPivot and pivot and (Vector3.new(pivot.X, 0, pivot.Z) - Vector3.new(att.WorldPosition.X, 0, att.WorldPosition.Z)).Magnitude < 0.6 then
					found = true
				end
			end
			if not found then
				placedOk = false
			end
		end
		T.check(placedOk, "HomeFx fix: ...each Garden pet on its own cushion")

		-- 2. home B with the same 13 pets while A still shows them: no pooled model to take, every one a build. A
		-- simulated CPU clock (5 ms per PetBuilder.Build, reset every frame) shows the time budget: one per frame
		local spent, frameAt = 0, -1
		os.clock = function()
			if Mock.Clock.frame ~= frameAt then
				frameAt = Mock.Clock.frame
				spent = 0
			end
			return Mock.Clock.now + spent
		end
		PB.Build = function(...)
			spent = spent + 0.005
			return realBuild(...)
		end
		local mid = base * CFrame.new(0, 0, 75)
		cam.CFrame = CFrame.lookAt((mid * CFrame.new(-30, 40, 0)).Position, mid.Position)
		local r2 = watch(b, 6, 120)
		local onB = countAt(b)
		info("home B with a 5 ms build", r2)
		T.check(r2.Reached and r2.Worst <= 1 and r2.Frames >= 6, "HomeFx fix: at 5 ms a build, the 4 ms frame budget lets only one build in per frame",
			"at most " .. r2.Worst .. " in a frame, " .. r2.Frames .. " frames, " .. onB .. " pets in home B")
		-- the same builds without the slow clock: the count cap (3 a frame) is the limit. (Put back between two
		-- frames: the next os.clock() read is a frame later, so the clock never runs backwards for anyone.)
		PB.Build = realBuild
		os.clock = realClock
		local r3 = watch(b, 13, 120)
		info("home B at normal speed", r3)
		onB = countAt(b)
		T.check(r3.Reached and onB == 13 and r3.Worst == 3, "HomeFx fix: ...and at a normal speed 3 a frame (no more) until all 13 stand", onB .. " pets, at most " .. r3.Worst .. " in a frame")
		T.check(countAt(a) == 13, "HomeFx fix: ...home A keeps its pets meanwhile", tostring(countAt(a)))

		-- 3. walking away: both homes put their pets away into the pool (<= 16 models, unparented)
		local away = base * CFrame.new(0, 60, -700)
		cam.CFrame = CFrame.lookAt(away.Position, away.Position + Vector3.new(0, 0, -1))
		KC.advance(1.5)
		local st3 = stats()
		pf = petsFolder()
		local left = 0
		for _, m in ipairs(pf and pf:GetChildren() or {}) do
			local key = m:GetAttribute("PetKey")
			for _, id in ipairs(ids) do
				if key == id then
					left = left + 1
				end
			end
		end
		T.check(left == 0 and countAt(a) == 0 and countAt(b) == 0, "HomeFx fix: homes out of range put their pets away", left .. " test pets still in HomePets")
		T.check(n(st3, "PetPool") >= 13 and n(st3, "PetPool") <= 16, "HomeFx fix: ...into a small pool (16 models at most, the oldest destroyed first)", "pool " .. n(st3, "PetPool"))

		-- 4. walking back to home A: its pets come back from the pool (no new build), on their cushions
		cam.CFrame = CFrame.lookAt((base * CFrame.new(0, 40, -70)).Position, base.Position)
		local r4 = watch(a, 13, 120)
		info("back to home A", r4)
		T.check(r4.Reached and countAt(a) == 13 and r4.Worst <= 3, "HomeFx fix: walking back, home A's 13 pets return (at most 3 a frame)", countAt(a) .. " pets, at most " .. r4.Worst .. " in a frame")
		-- (both homes show the same 13 pets: whichever 16 models the pool kept, every one home A needs is there)
		T.check(r4.HasStats and r4.Hits >= 13 and r4.Builds == 0, "HomeFx fix: ...re-parented from the pool instead of built again",
			r4.Hits .. " from the pool, " .. r4.Builds .. " built")
		local st4 = stats()
		T.check(n(st4, "PetFrameMost") <= 3 and n(st4, "PetFrameMost") >= 1, "HomeFx fix: Stats().PetFrameMost: never more than 3 pets placed in one frame", tostring(st4.PetFrameMost))
		T.check(n(st4, "PetBuilds") > n(st0, "PetBuilds") and n(st4, "PetColdBuilds") >= n(st0, "PetColdBuilds"), "HomeFx fix: Stats() counts the pet builds")
	end)
	-- put everything back (also when a check above raised)
	os.clock = realClock
	PB.Build = realBuild
	if cam and savedCam then
		cam.CFrame = savedCam
	end
	root:Destroy()
	Mock.RemovePlayer(neighbour)
	KC.advance(1.5)
	if not ok then
		T.fail("HomeFx fix: pet budget scenario raised an error", tostring(err))
	end
	local pf = petsFolder()
	local leftover = 0
	for _, m in ipairs(pf and pf:GetChildren() or {}) do
		local okPivot, pivot = pcall(function()
			return m:GetPivot()
		end)
		if okPivot and pivot and pivot.Position.X < -5000 then
			leftover = leftover + 1
		end
	end
	T.check(leftover == 0, "HomeFx fix: removed homes leave no pets behind", leftover .. " left")
	local warned = nil
	for i = outputBefore + 1, #Mock.Output do
		local o = Mock.Output[i]
		if o.kind == "warn" and o.text:find("HomeFx", 1, true) then
			warned = o.text
		end
	end
	T.check(warned == nil and #Mock.Errors == errorsBefore, "HomeFx fix: no errors or warnings from HomeFx (pets)", tostring(warned))
	KC.flushErrors("client_p2fix_pets")
end)

return S
