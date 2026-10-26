-- smoke_bug2_lobby.lua: bug batch 2, lane lobby (player reports #4, #7). Loaded by tools/smoke.py in the server world and
-- the client world:
--   bug2lobby_altarportal (server, #4 "add also a small portal from storm altar to lobby") the Storm Altar has a small
--                         return portal (Model ReturnPortal: a navy collidable pad, 8 cyan Neon ring segments, the
--                         ReturnPrompt anchor = StormAltar.GetReturnPad()) beside the landing: 4-10 studs from
--                         GetLanding, off the landing lane, inside the walkable top, outside the stone ring, flush on
--                         the deck with nothing solid over it; GateService's PlazaGatePrompt on it ("Travel" / "Plaza",
--                         E, range 8, no OpenPanel); GateService.Use(player, "Plaza") lands on LobbyInfo.Gates.Altar.
--                         ReturnCFrame (18 studs in front of the Altar gate, >= 14 studs from its PromptPart so the
--                         12-stud Altar prompt does not show on arrival, on the plaza ground, nothing solid there),
--                         fires Teleported (player, "Plaza") once; refused in a battle / dungeon run (InBattle "D7"),
--                         a match, far away (> 8 + 4), inside the 1.5 s cooldown; the prompt itself works (Mock.Trigger);
--                         a rebuilt altar is re-bound at once (StormAltar.Built: a fresh prompt on the new pad); a seated
--                         player is stood up before a gate teleport (the SeatWeld goes, the seat stays)
--   bug2lobby_benches     (server, #7 "benches should be sittable") every lobby bench (plaza lawns + gardens) has two
--                         invisible, non-colliding BenchSeat Seats with Disabled = true and a "Sit" prompt (E, range 7),
--                         their tops on the planks; the prompt seats that player (Occupant, Humanoid.Sit, the seat
--                         enabled only while taken, its prompt hidden); a taken seat refuses a second player who can
--                         take the other seat; leaving (the SeatWeld goes) disables the seat again and shows the prompt;
--                         refused in a battle / dungeon run, in a match, far away, already seated, inside the 0.5 s
--                         cooldown, dead, junk; a seat dragged away by a teleport is freed and put back home
--   client_bug2lobby_petsit (client, #7 "when a player sits on them the pets sit on the ground") 3 followers: while the
--                         owner's Humanoid.Sit is true they settle 2.5-6 studs in front of the owner, side by side without
--                         overlapping, their lowest point on the ground (+-0.35), lying rolled ~LIE_ANGLE (UpVector.Y
--                         < 0.45), facing the owner (looking back along the owner's line of sight), with no jump > 1.6
--                         studs in a 0.05 s step on the way down; InBattle parks them
--                         as before; standing up brings them back to their slots (|slot| +- 1.5), upright, smoothly
-- Deterministic: mock clock only. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, max, min, sqrt = math.abs, math.max, math.min, math.sqrt
local fmt = string.format

local function hdist(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return sqrt(dx * dx + dz * dz)
end

-- lowest world y of a part's box (rotated)
local function partLow(part)
	local cf, s = part.CFrame, part.Size
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	return cf.Position.Y - (abs(r.Y) * s.X + abs(u.Y) * s.Y + abs(l.Y) * s.Z) / 2
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

	local function standAt(player, pos, look)
		local cf = look and CFrame.lookAt(pos + Vector3.new(0, 3, 0), look + Vector3.new(0, 3, 0)) or CFrame.new(pos + Vector3.new(0, 3, 0))
		Mock.Teleport(player, cf)
		K.advance(0.05)
	end

	-- colliding parts (not under `skip`) inside a box
	local function solidIn(cf, size, skip)
		local found = {}
		for _, p in ipairs(workspace:GetPartBoundsInBox(cf, size)) do
			if p.CanCollide and not (skip and p:IsDescendantOf(skip)) then
				local char = false
				for _, pl in ipairs(game:GetService("Players"):GetPlayers()) do
					if pl.Character and p:IsDescendantOf(pl.Character) then
						char = true
					end
				end
				if not char then
					found[#found + 1] = p
				end
			end
		end
		return found
	end

	local function names(list)
		local out = {}
		for i = 1, min(#list, 4) do
			out[i] = list[i]:GetFullName()
		end
		return table.concat(out, "; ")
	end

	------------------------------------------------------------------------------------------------
	-- #4 the Storm Altar's return portal
	------------------------------------------------------------------------------------------------
	S.bug2lobby_altarportal = guarded("bug2lobby_altarportal", function()
		if not K.needBoot() then
			return
		end
		local SA = requireAt("server/Services/StormAltar")
		local GS = requireAt("server/Services/GateService")
		local info = K.W.lobbyInfo
		if not T.check(SA and GS and type(info) == "table", "bug2 altar portal: StormAltar, GateService and LobbyInfo are there") then
			return
		end
		local pad = type(SA.GetReturnPad) == "function" and SA.GetReturnPad() or nil
		if not T.check(typeof(pad) == "Instance" and pad:IsA("BasePart") and pad:IsDescendantOf(SA.GetModel()),
			"bug2 altar portal: StormAltar.GetReturnPad() is a part of the altar model (the small return portal exists)") then
			return
		end
		local portal = pad.Parent
		local A = SA.GetCFrame()
		local landing = SA.GetLanding()
		T.check(portal and portal.Name == "ReturnPortal" and portal:IsA("Model"), "bug2 altar portal: it is Model ReturnPortal", portal and portal:GetFullName() or "")
		-- the look: a navy pad (collidable, flush), a ring of 8 cyan Neon segments
		local padParts, ring, ringCyan = {}, 0, 0
		for _, d in ipairs(portal:GetDescendants()) do
			if d:IsA("BasePart") then
				if d.Name == "Pad" then
					padParts[#padParts + 1] = d
				elseif d.Name == "Ring" then
					ring = ring + 1
					if d.Material == Enum.Material.Neon and d.Color.B > 0.8 and d.Color.G > 0.6 and d.Color.R < 0.4 then
						ringCyan = ringCyan + 1
					end
					T.check(not d.CanCollide, "bug2 altar portal: ring segment does not collide")
				end
			end
		end
		T.check(#padParts >= 1, "bug2 altar portal: a Pad part")
		local navy, collide, flush = true, true, true
		for _, p in ipairs(padParts) do
			navy = navy and p.Color.B > p.Color.R and p.Color.B < 0.45 and p.Material == Enum.Material.SmoothPlastic
			collide = collide and p.CanCollide
			local top = p.Position.Y + p.Size.Y / 2
			flush = flush and abs(top - (A.Position.Y + 0.2)) < 0.05
		end
		T.check(navy, "bug2 altar portal: the pad is navy SmoothPlastic")
		T.check(collide and flush, "bug2 altar portal: the pad collides and its top is 0.2 studs over the deck (walked over, never in the way)")
		T.eq(ring, 8, "bug2 altar portal: 8 ring segments")
		T.eq(ringCyan, 8, "bug2 altar portal: ...all cyan Neon")
		-- placement: beside the landing, on the walkable top, outside the stone ring, off the landing lane
		local c = pad.Position
		local dl = hdist(c, landing.Position)
		T.check(dl >= 4 and dl <= 10, "bug2 altar portal: 4-10 studs from the landing (beside it, not on it)", fmt("%.1f studs", dl))
		local fromA = hdist(c, A.Position)
		T.check(fromA - 2.2 > 13.8 and fromA + 2.2 < 23, "bug2 altar portal: between the stone ring (13.8) and the walkable edge (23)", fmt("%.1f studs from the altar centre", fromA))
		local axis = Vector3.new(landing.Position.X - A.Position.X, 0, landing.Position.Z - A.Position.Z).Unit
		local rel = Vector3.new(c.X - A.Position.X, 0, c.Z - A.Position.Z)
		local lateral = abs(rel.X * -axis.Z + rel.Z * axis.X)
		T.check(lateral - 2.2 >= 2.5, "bug2 altar portal: clear of the landing lane (pad edge >= 2.5 studs off the bridge's centre line)", fmt("pad centre %.1f studs off the line", lateral))
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { portal }
		params.RespectCanCollide = true
		local hit = workspace:Raycast(Vector3.new(c.X, A.Position.Y + 1, c.Z), Vector3.new(0, -4, 0), params)
		T.check(hit ~= nil and abs(hit.Position.Y - A.Position.Y) < 0.6 and hit.Instance:IsDescendantOf(SA.GetModel()), "bug2 altar portal: the island deck is right under the pad", hit and (hit.Instance:GetFullName() .. fmt(" at %+.2f", hit.Position.Y - A.Position.Y)) or "nothing")
		local over = solidIn(CFrame.new(c.X, A.Position.Y + 3.3, c.Z), Vector3.new(4, 6, 4), portal)
		T.check(#over == 0, "bug2 altar portal: nothing solid stands on the pad (6 studs up)", names(over))
		local atLanding = solidIn(CFrame.new(landing.Position.X, A.Position.Y + 2.8, landing.Position.Z), Vector3.new(2.5, 5, 2.5), nil)
		T.check(#atLanding == 0, "bug2 altar portal: the landing spot stays clear", names(atLanding))
		-- the prompt
		local prompt = pad:FindFirstChild("PlazaGatePrompt")
		if T.check(prompt ~= nil and prompt:IsA("ProximityPrompt") and GS.GetPrompt("Plaza") == prompt, "bug2 altar portal: GateService's PlazaGatePrompt sits on the pad anchor (GetPrompt('Plaza'))") then
			T.check(prompt.ActionText == "Travel" and prompt.ObjectText == "Plaza", "bug2 altar portal: 'Travel' / 'Plaza'", prompt.ActionText .. " / " .. prompt.ObjectText)
			T.check(prompt.KeyboardKeyCode == Enum.KeyCode.E and prompt.HoldDuration == 0 and prompt.MaxActivationDistance == 8, "bug2 altar portal: E, no hold, range 8")
			T.check(prompt:GetAttribute("OpenPanel") == nil, "bug2 altar portal: no panel")
		end
		-- the arrival: 18 studs in front of the Altar gate, >= 14 studs from its prompt part, on the plaza
		local ret = info.Gates and info.Gates.Altar and info.Gates.Altar.ReturnCFrame
		local site = info.GateSites and info.GateSites.Altar
		if T.check(typeof(ret) == "CFrame" and typeof(site) == "CFrame", "bug2 altar portal: LobbyInfo.Gates.Altar.ReturnCFrame") then
			T.check(abs(hdist(ret.Position, site.Position) - 18) < 0.5 and (ret.Position - site.Position):Dot(site.LookVector) > 17, "bug2 altar portal: ...18 studs in front of the Altar gate (plaza side)")
			local altarPP = info.Gates.Altar.PromptPart
			if T.check(typeof(altarPP) == "Instance" and altarPP:IsA("BasePart"), "bug2 altar portal: the Altar gate has its PromptPart") then
				local dPP = (ret.Position - altarPP.Position).Magnitude
				T.check(dPP >= 14, "bug2 altar portal: ...the arrival is >= 14 studs from the Altar gate's PromptPart (its 12-stud prompt stays hidden)", fmt("%.2f studs", dPP))
			end
			T.check(ret.LookVector:Dot(site.LookVector) > 0.95, "bug2 altar portal: ...looking at the plaza")
			local okR, hitR = K.groundBelow(ret.Position, 8)
			T.check(okR and abs(hitR.Position.Y - (ret.Position.Y - 3)) < 0.6, "bug2 altar portal: ...3 studs over the plaza ground", okR and fmt("ground %.2f, arrival %.2f", hitR.Position.Y, ret.Position.Y) or "no ground")
			local there = solidIn(ret * CFrame.new(0, 0, 0), Vector3.new(5, 5, 5), nil)
			T.check(#there == 0, "bug2 altar portal: ...nothing solid at the arrival (2.5 studs around: no lamp, bench or prop)", names(there))
		end
		-- the teleport
		local fired = {}
		local conn = GS.Teleported:Connect(function(player, id)
			fired[#fired + 1] = { player, id }
		end)
		local players = K.freshPlayers(3, "AltarBack")
		local a, b, c3 = players[1], players[2], players[3]
		local padGround = Vector3.new(c.X, A.Position.Y + 0.2, c.Z)
		K.advance(2)
		standAt(a, padGround + axis * 1.5)
		a:SetAttribute("InBattle", "D7")
		local mark = K.logSize()
		local ok, why = GS.Use(a, "Plaza")
		T.check(not ok and why == "battle", "bug2 altar portal: refused in a dungeon run / battle (InBattle)", tostring(why))
		T.check(K.notified(a, "Finish your battle", "bad", mark), "bug2 altar portal: ...with 'Finish your battle first!'")
		a:SetAttribute("InBattle", nil)
		a:SetAttribute("InMatch", true)
		ok, why = GS.Use(a, "Plaza")
		T.check(not ok and why == "match", "bug2 altar portal: refused in a match", tostring(why))
		a:SetAttribute("InMatch", nil)
		standAt(a, Vector3.new(A.Position.X, A.Position.Y, A.Position.Z) + axis * 2)
		ok, why = GS.Use(a, "Plaza")
		T.check(not ok and why == "far", "bug2 altar portal: refused from the dais (> 8 + 4 studs)", tostring(why))
		standAt(a, padGround + axis * 1.5)
		local n0 = #fired
		ok, why = GS.Use(a, "Plaza")
		K.advance(0.2)
		T.check(ok == true, "bug2 altar portal: a player on the pad is accepted", tostring(why))
		if typeof(ret) == "CFrame" then
			T.check((K.root(a).Position - ret.Position).Magnitude < 3, "bug2 altar portal: ...and lands in front of the Altar gate", fmt("%.1f studs off", (K.root(a).Position - ret.Position).Magnitude))
		end
		T.check(#fired == n0 + 1 and fired[#fired][1] == a and fired[#fired][2] == "Plaza", "bug2 altar portal: Teleported fires once (player, 'Plaza')")
		standAt(a, padGround)
		ok, why = GS.Use(a, "Plaza")
		T.check(not ok and why == "cooldown" and #fired == n0 + 1, "bug2 altar portal: a second use inside 1.5 s is refused (cooldown), nothing fires", tostring(why))
		-- the prompt path (E on the pad)
		standAt(b, padGround)
		Mock.Trigger(GS.GetPrompt("Plaza"), b)
		K.advance(0.2)
		T.check(typeof(ret) == "CFrame" and (K.root(b).Position - ret.Position).Magnitude < 3, "bug2 altar portal: pressing E on the pad's prompt takes the player to the plaza")
		-- a rebuilt altar: the gate binds to the new pad
		local okB = pcall(SA.Build, info)
		K.advance(0.3)
		local pad2 = SA.GetReturnPad()
		if T.check(okB and pad2 ~= nil and pad2 ~= pad, "bug2 altar portal: (setup) the altar rebuilt with a new pad") then
			T.check(pad2:FindFirstChild("PlazaGatePrompt") ~= nil, "bug2 altar portal: the rebuilt altar's pad gets its prompt at once (StormAltar.Built)")
			K.advance(2)
			standAt(b, Vector3.new(pad2.Position.X, A.Position.Y + 0.2, pad2.Position.Z))
			ok, why = GS.Use(b, "Plaza")
			T.check(ok == true and GS.GetPrompt("Plaza") ~= nil and GS.GetPrompt("Plaza").Parent == pad2, "bug2 altar portal: after a rebuild the new pad carries the prompt and works", tostring(why))
		end
		T.check(pcall(GS.Use, nil, "Plaza") and select(1, GS.Use(a, "Nope")) == false, "bug2 altar portal: junk is refused without errors")
		-- a seated player (a bench) is stood up before a gate teleport: the weld goes, the seat stays where it is
		if typeof(site) == "CFrame" then
			standAt(c3, site.Position + site.LookVector * 5, site.Position)
			local tmp = Instance.new("Seat")
			tmp.Name = "Bug2TmpSeat"
			tmp.Anchored = true
			tmp.CanCollide = false
			tmp.Transparency = 1
			tmp.Size = Vector3.new(2, 0.4, 2)
			tmp.CFrame = K.root(c3).CFrame * CFrame.new(0, -1.5, 0)
			tmp.Parent = workspace
			tmp:Sit(K.hum(c3))
			local home = tmp.CFrame
			if T.check(tmp.Occupant == K.hum(c3), "bug2 altar portal: (setup) a player seated by the Altar gate") then
				ok, why = GS.Use(c3, "Altar")
				K.advance(0.2)
				T.check(ok == true and tmp:FindFirstChild("SeatWeld") == nil and tmp.Occupant == nil and K.hum(c3).Sit == false and (tmp.Position - home.Position).Magnitude < 0.01,
					"bug2 altar portal: a seated player is stood up before a gate teleport (the seat stays)", tostring(why))
			end
			tmp:Destroy()
		end
		conn:Disconnect()
		K.removePlayers(players)
		K.flushErrors("bug2lobby_altarportal")
	end)

	------------------------------------------------------------------------------------------------
	-- #7 sittable benches
	------------------------------------------------------------------------------------------------
	S.bug2lobby_benches = guarded("bug2lobby_benches", function()
		if not K.needBoot() then
			return
		end
		local LB = requireAt("server/Services/LobbyBuilder")
		local info = K.W.lobbyInfo
		local B = LB and LB._Benches
		local lobby = info and info.Folder
		if not T.check(lobby ~= nil, "bug2 benches: the lobby folder") then
			return
		end
		local benches, seats, plaza, garden = {}, {}, 0, 0
		for _, d in ipairs(lobby:GetDescendants()) do
			if d:IsA("Model") and d.Name == "Bench" then
				benches[#benches + 1] = d
				if d:FindFirstAncestor("Gardens") then
					garden = garden + 1
				else
					plaza = plaza + 1
				end
			end
		end
		T.check(plaza >= 3 and garden >= 2, "bug2 benches: benches on the plaza lawns and in the gardens", fmt("%d plaza, %d garden", plaza, garden))
		local shape = T.tally("bug2 benches: every bench has 2 BenchSeat Seats: Disabled, invisible, non-colliding, the top on the planks, a 'Sit' prompt (E, range 7)")
		for _, bench in ipairs(benches) do
			local list = {}
			local plankTop = -1e9
			for _, c in ipairs(bench:GetChildren()) do
				if c:IsA("Seat") and c.Name == "BenchSeat" then
					list[#list + 1] = c
				elseif c:IsA("BasePart") and c.Name == "Seat" then
					plankTop = max(plankTop, c.Position.Y + c.Size.Y / 2)
				end
			end
			local good = #list == 2
			for _, s in ipairs(list) do
				local p = s:FindFirstChild("BenchSitPrompt")
				good = good and s.Disabled == true and s.Transparency == 1 and not s.CanCollide and s.Anchored
					and abs(s.Position.Y + s.Size.Y / 2 - plankTop) < 0.05
					and p ~= nil and p.ActionText == "Sit" and p.KeyboardKeyCode == Enum.KeyCode.E and p.MaxActivationDistance == 7 and p.HoldDuration == 0
				seats[#seats + 1] = s
			end
			if #list == 2 then
				good = good and (list[1].Position - list[2].Position).Magnitude >= 2
			end
			shape:case(good, bench:GetFullName())
		end
		shape:report()
		if not T.check(#seats >= 2 and B ~= nil and type(B.sit) == "function", "bug2 benches: (setup) seats and LobbyBuilder._Benches") then
			return
		end
		local s1, s2 = seats[1], seats[2]
		local p1 = s1:FindFirstChild("BenchSitPrompt")
		local players = K.freshPlayers(3, "Bench")
		local a, b, c = players[1], players[2], players[3]
		local function front(seat)
			return (seat.CFrame * CFrame.new(0, -1.75, -2.5)).Position
		end
		standAt(a, front(s1))
		standAt(b, front(s1))
		-- E on the prompt seats that player
		Mock.Trigger(p1, a)
		K.advance(0.1)
		local ha = K.hum(a)
		T.check(s1.Occupant == ha and ha.Sit == true and ha.SeatPart == s1, "bug2 benches: E on 'Sit' seats the player (Occupant, Humanoid.Sit)")
		T.check(s1.Disabled == false and p1.Enabled == false, "bug2 benches: ...the seat is enabled only while taken, its prompt hidden")
		local ok, why = B.sit(b, s1)
		T.check(not ok and why == "taken" and s1.Occupant == ha, "bug2 benches: a taken seat refuses a second player", tostring(why))
		ok, why = B.sit(a, s2)
		T.check(not ok and why == "seated", "bug2 benches: a seated player cannot take a second seat", tostring(why))
		ok, why = B.sit(b, s2)
		T.check(ok == true and s2.Occupant == K.hum(b), "bug2 benches: the second player takes the bench's other seat", tostring(why))
		-- leaving (a jump: the engine removes the SeatWeld)
		local weld = s1:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		K.advance(0.1)
		T.check(s1.Occupant == nil and s1.Disabled == true and p1.Enabled == true, "bug2 benches: standing up disables the seat again and shows its prompt (running past never sits you)")
		ok, why = B.sit(a, s1)
		T.check(not ok and why == "cooldown", "bug2 benches: sitting again inside 0.5 s is refused (cooldown)", tostring(why))
		local w2 = s2:FindFirstChild("SeatWeld")
		if w2 then
			w2:Destroy()
		end
		K.advance(0.6)
		-- refusals
		a:SetAttribute("InBattle", "D3")
		ok, why = B.sit(a, s1)
		T.check(not ok and why == "busy" and s1.Occupant == nil and s1.Disabled, "bug2 benches: refused in a battle / dungeon run (InBattle)", tostring(why))
		a:SetAttribute("InBattle", nil)
		a:SetAttribute("InMatch", true)
		ok, why = B.sit(a, s1)
		T.check(not ok and why == "busy", "bug2 benches: refused in a match", tostring(why))
		a:SetAttribute("InMatch", nil)
		standAt(c, front(s1) + Vector3.new(0, 0, 0) + (s1.CFrame.LookVector * 12))
		ok, why = B.sit(c, s1)
		T.check(not ok and why == "far", "bug2 benches: refused from > 7 + 3 studs", tostring(why))
		T.check(select(1, B.sit("x", s1)) == false and select(1, B.sit(a, workspace)) == false and pcall(B.sit, nil, nil), "bug2 benches: junk is refused without errors")
		-- the watchdog: a teleport that dragged the welded player (and the seat) away frees the seat at home
		ok = B.sit(a, s1)
		if T.check(ok == true and s1.Occupant == K.hum(a), "bug2 benches: (setup) seated again after the cooldown") then
			local home = s1.CFrame
			s1.CFrame = home + Vector3.new(30, 0, 0)
			Mock.Teleport(a, home + Vector3.new(30, 3, 0))
			K.advance(0.6)
			T.check((s1.Position - home.Position).Magnitude < 0.01 and s1.Occupant == nil and s1.Disabled == true and K.hum(a).Sit == false,
				"bug2 benches: a seat dragged away by a teleport is freed and put back home (Disabled again)")
		end
		-- dead players do not sit
		K.advance(0.6)
		standAt(c, front(s2))
		K.hum(c).Health = 0
		ok, why = B.sit(c, s2)
		T.check(not ok and why == "dead", "bug2 benches: a dead player is refused", tostring(why))
		K.removePlayers(players)
		K.flushErrors("bug2lobby_benches")
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	local KC = _G.KC
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

	local function petOf(PetCatalog, rarity)
		for _, def in ipairs(PetCatalog.Pets) do
			if def.Rarity == rarity and not def.EventOnly then
				return def.Id
			end
		end
		return nil
	end

	-- the lowest point of the pet's body (the welded static parts; the wings / tail flap on their own)
	local function modelLow(model)
		local lo = 1e9
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 and not d.Anchored then
				lo = min(lo, partLow(d))
			end
		end
		return lo
	end

	S.client_bug2lobby_petsit = guarded("client_bug2lobby_petsit", function()
		local pc = KC.M.PetController or moduleAt("client", "Controllers/PetController")
		local PetCatalog = moduleAt("shared", "PetCatalog")
		if not T.check(pc ~= nil and type(pc.GetFollowerInfo) == "function" and PetCatalog ~= nil, "bug2 pet sit: PetController.GetFollowerInfo") then
			return
		end
		local COMMON, EPIC, LEGEND = petOf(PetCatalog, "Common"), petOf(PetCatalog, "Epic"), petOf(PetCatalog, "Legendary")
		local owned = { [COMMON] = 1, [EPIC] = 1, [LEGEND] = 1 }
		KC.toClient("ProfileSync", {
			Tokens = 600, Pets = owned, Equipped = {}, Items = {},
			Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			SpotIndex = 1, Perks = {}, Discovered = owned, IndexClaimed = {},
			Tutorial = { Step = 99, Done = true, Gifted = true },
			PetLevels = { [COMMON] = 3, [EPIC] = 20, [LEGEND] = 30 }, PetGrowth = { [LEGEND] = { Evo = 1 } },
		})
		KC.advance(0.2)
		LocalPlayer:SetAttribute("EquippedPets", "")
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.advance(0.3)
		-- a floor 3.6 studs under the (sitting) owner's root
		local start = Vector3.new(-640, 90, 640)
		local floorTop = start.Y - 3.6
		local floor = Instance.new("Part")
		floor.Name = "Bug2SitFloor"
		floor.Anchored = true
		floor.CanCollide = true
		floor.Size = Vector3.new(80, 2, 80)
		floor.CFrame = CFrame.new(start.X, floorTop - 1, start.Z)
		floor.Parent = workspace
		Mock.Teleport(LocalPlayer, CFrame.new(start)) -- facing -Z
		LocalPlayer:SetAttribute("EquippedPets", table.concat({ COMMON, EPIC, LEGEND }, ","))
		KC.advance(3.5)
		local info = pc.GetFollowerInfo(LocalPlayer)
		local hum = KC.hum()
		if not T.check(#info == 3 and info[1].Model and info[2].Model and info[3].Model and hum ~= nil, "bug2 pet sit: (setup) 3 followers built", tostring(#info)) then
			floor:Destroy()
			return
		end
		local root = KC.root()
		local look = root.CFrame.LookVector
		local slots = {}
		local before = {}
		for i = 1, 3 do
			slots[i] = sqrt((info[i].Side or 0) ^ 2 + (info[i].Back or 0) ^ 2)
			before[i] = info[i].Model:GetPivot().Position
		end
		-- the owner sits
		hum.Sit = true
		local jump = 0
		for _ = 1, 60 do
			KC.advance(0.05)
			for i = 1, 3 do
				local p = info[i].Model:GetPivot().Position
				jump = max(jump, (p - before[i]).Magnitude)
				before[i] = p
			end
		end
		info = pc.GetFollowerInfo(LocalPlayer)
		local o = root.Position
		local inFront, ground, lying, facing, flags = true, true, true, true, true
		local detail = {}
		for i = 1, 3 do
			local m = info[i].Model
			local pv = m:GetPivot()
			local d = pv.Position - o
			local ahead = d.X * look.X + d.Z * look.Z
			local low = modelLow(m)
			detail[#detail + 1] = fmt("#%d ahead %.1f low %+.2f up %.2f", i, ahead, low - floorTop, pv.UpVector.Y)
			inFront = inFront and ahead >= 2.5 and ahead <= 6
			ground = ground and abs(low - floorTop) <= 0.35
			lying = lying and pv.UpVector.Y < 0.45
			-- facing the sitting owner: looking back along the owner's line of sight (the row faces the bench)
			local lv = Vector3.new(pv.LookVector.X, 0, pv.LookVector.Z).Unit
			facing = facing and -(lv.X * look.X + lv.Z * look.Z) > 0.9
			flags = flags and info[i].Sitting == true
		end
		local apart = true
		for i = 1, 2 do
			for j = i + 1, 3 do
				local gap = hdist(info[i].Model:GetPivot().Position, info[j].Model:GetPivot().Position) - (info[i].Width or 0) / 2 - (info[j].Width or 0) / 2
				apart = apart and gap >= -0.05
				detail[#detail + 1] = fmt("gap %d-%d %.2f", i, j, gap)
			end
		end
		local text = table.concat(detail, ", ")
		T.check(flags, "bug2 pet sit: GetFollowerInfo marks every pet Sitting while the owner sits")
		T.check(inFront, "bug2 pet sit: the pets settle 2.5-6 studs in front of the sitting owner", text)
		T.check(ground, "bug2 pet sit: ...on the ground (their lowest point within 0.35 of the floor)", text)
		T.check(lying, "bug2 pet sit: ...lying down (HomeFx's LIE_ANGLE roll)", text)
		T.check(facing, "bug2 pet sit: ...facing the owner", text)
		T.check(apart, "bug2 pet sit: ...side by side without overlapping", text)
		T.check(jump <= 1.6, "bug2 pet sit: they ease down smoothly (no jump > 1.6 studs in a 0.05 s step)", fmt("biggest step %.2f", jump))
		-- a battle still parks them (pets fighting ignore the bench)
		LocalPlayer:SetAttribute("InBattle", "B9")
		KC.advance(0.2)
		T.check(not info[1].Model:IsDescendantOf(workspace), "bug2 pet sit: InBattle parks the followers as before, sitting or not")
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.advance(1.5)
		-- standing up: back to the slots, upright, smoothly
		hum.Sit = false
		info = pc.GetFollowerInfo(LocalPlayer)
		for i = 1, 3 do
			before[i] = info[i].Model:GetPivot().Position
		end
		jump = 0
		for _ = 1, 80 do
			KC.advance(0.05)
			for i = 1, 3 do
				local p = info[i].Model:GetPivot().Position
				jump = max(jump, (p - before[i]).Magnitude)
				before[i] = p
			end
		end
		info = pc.GetFollowerInfo(LocalPlayer)
		local back, upright, cleared = true, true, true
		detail = {}
		for i = 1, 3 do
			local pv = info[i].Model:GetPivot()
			local dist = hdist(pv.Position, root.Position)
			detail[#detail + 1] = fmt("#%d %.1f/%.1f up %.2f", i, dist, slots[i], pv.UpVector.Y)
			back = back and abs(dist - slots[i]) <= 1.5 and pv.Position.Y > root.Position.Y
			upright = upright and pv.UpVector.Y > 0.85
			cleared = cleared and info[i].Sitting ~= true
		end
		T.check(cleared, "bug2 pet sit: standing up clears Sitting")
		T.check(back and upright, "bug2 pet sit: standing up brings the pets back to their slots (|slot| +- 1.5), upright", table.concat(detail, ", "))
		T.check(jump <= 1.6, "bug2 pet sit: ...smoothly (no jump > 1.6 studs in a 0.05 s step)", fmt("biggest step %.2f", jump))
		LocalPlayer:SetAttribute("EquippedPets", "")
		KC.advance(0.5)
		floor:Destroy()
		KC.flushErrors("bug2lobby_petsit")
		KC.flushWarnings("bug2lobby_petsit")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
