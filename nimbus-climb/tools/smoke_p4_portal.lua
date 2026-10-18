-- smoke_p4_portal.lua: Phase 4 home portal (ARCHITECTURE_V3.md "Phase 4 build contract" 3.10, 3.11, 5.1 / 5.3, X18,
-- 8.1). Loaded by tools/smoke.py in BOTH worlds; ARGS.context picks the half:
--   SERVER (wave 2, tycoon), on the booted game (Main.server.lua):
--   p4portal_home      HomeAction "GoHome" writes the player attribute HomePortal = "x,y,z,yaw,closesAt" (the point
--                      ~6 studs ahead on the ground, closesAt = server time + 10); the server builds no part for it;
--                      pressing again keeps the open one; when the OWNER's root reaches the point the 0.2 s loop
--                      teleports them within 6 studs of their home SpawnCFrame, clears HomePortal, writes PortalArrived
--                      and fires PortalUsed(player); another player at the portal point does not move; a portal
--                      nobody enters expires after 10 s; the 3 s cooldown; GoToSpot (the Home tile) and GoHome without
--                      a home open the portal toward a free gate ("Press E at the gate to claim this home!")
--   p4portal_refusals  refused in an obby match, in a battle (InBattle: "Finish your battle first!"), while locked in
--                      a portal party (PortalLocked), while dead; an open portal closes without a teleport when the
--                      owner enters a battle before walking in; SpotService.Teleport and the GoToSpot remote refuse
--                      InBattle (safe zones: no teleport can pull a player out of a fight); junk arguments
--   CLIENT (wave 3, homefx), client/Controllers/HomePortalFx.lua:
--   client_p4portal_ring  HomePortal draws the ring (<= 30 anchored client parts) on the floor point, across the
--                         owner's yaw, with a 22 px "<name>'s portal" tag (pixel-sized, stroke) and a turning swirl;
--                         another player's portal faded, one beyond 150 studs not drawn; cleared -> it shrinks away,
--                         closesAt passed -> it goes by itself; junk draws nothing; PortalArrived plays the arrival
--                         ring (<= 20 parts, 1.5 s); Stop() removes everything, Init() draws again
--   client_p4portal_dive  the owner walks into their portal and is teleported home: the followers (PetController) dive
--                         into the portal centre while it shrinks away, the arrival ring plays, the pets pop out
--                         behind the owner
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local K = _G.K
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs = math.abs

----------------------------------------------------------------------------------------------------
-- CLIENT half (wave 3, homefx): HomePortalFx draws the portals and the arrival ring (contract 3.10 / 6)
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local KC = _G.KC
	local CS = {}
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer
	local fmt = string.format

	local function advance(seconds)
		KC.advance(seconds)
	end

	local function moduleAt(top, rest)
		local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end

	local function portalText(pos, yaw, closesAt)
		return fmt("%.2f,%.2f,%.2f,%.1f,%.3f", pos.X, pos.Y, pos.Z, yaw, closesAt)
	end

	local function partsOf(model)
		local out = {}
		for _, d in ipairs(model and model:GetDescendants() or {}) do
			if d:IsA("BasePart") then
				out[#out + 1] = d
			end
		end
		return out
	end

	CS.client_p4portal_ring = guarded("client_p4portal_ring", function()
		local outputBefore, errorsBefore = #Mock.Output, #Mock.Errors
		local Fx = KC.M.HomePortalFx or moduleAt("client", "Controllers/HomePortalFx")
		if not T.check(type(Fx) == "table" and type(Fx.Init) == "function" and type(Fx.Stop) == "function" and type(Fx.Portal) == "function",
			"p4 portal client: client/Controllers/HomePortalFx.lua loads with Init / Stop / Portal") then
			return
		end
		Fx.Init()
		local other = Mock.AddPlayer("PortalNeighbour", 8701, { character = false })
		local cam = workspace.CurrentCamera
		local savedCam = cam and cam.CFrame
		local ok, err = pcall(function()
			local at = Vector3.new(4000, 300, 4000)
			if cam then
				cam.CFrame = CFrame.lookAt(at + Vector3.new(0, 8, -24), at)
			end
			LocalPlayer:SetAttribute("HomePortal", nil)
			advance(0.6)
			local now = workspace:GetServerTimeNow()
			LocalPlayer:SetAttribute("HomePortal", portalText(at, 90, now + 10))
			advance(0.6)
			local info = Fx.Portal(LocalPlayer)
			local parts = partsOf(info and info.Model)
			T.check(info ~= nil and info.Model ~= nil and #parts >= 12 and #parts <= 30, "p4 portal client: the HomePortal attribute draws the portal ring (<= 30 voxel parts)",
				tostring(#parts) .. " parts")
			local solid = 0
			for _, p in ipairs(parts) do
				if p.CanCollide or p.CanQuery or p.CanTouch or not p.Anchored then
					solid = solid + 1
				end
			end
			T.check(#parts > 0 and solid == 0, "p4 portal client: ...client parts only, anchored, no collisions / touches / queries")
			T.check(info and info.Center and (info.Center - (at + Vector3.new(0, 3, 0))).Magnitude < 0.05, "p4 portal client: ...standing on the floor point (its centre 3 studs above it)")
			-- facing: the ring stands across the owner's heading (yaw 90: CFrame.Angles(0, rad(90), 0).LookVector)
			local look = CFrame.Angles(0, math.rad(90), 0).LookVector
			local spreadAlong, spreadAcross = 0, 0
			for _, p in ipairs(parts) do
				if p.Name == "Ring" then
					local d = p.Position - info.Center
					spreadAlong = math.max(spreadAlong, math.abs(d:Dot(look)))
					spreadAcross = math.max(spreadAcross, math.abs(d:Dot(look:Cross(Vector3.new(0, 1, 0)))))
				end
			end
			T.check(spreadAlong < 0.5 and spreadAcross > 2, "p4 portal client: ...facing the owner (the ring stands across the yaw)", fmt("%.2f along, %.2f across", spreadAlong, spreadAcross))
			T.check(info and not info.Faded, "p4 portal client: ...the owner's own portal is not faded")
			local gui = info and info.Gui
			local label = gui and gui:FindFirstChild("Name", true)
			local want = (LocalPlayer.DisplayName ~= nil and LocalPlayer.DisplayName ~= "" and LocalPlayer.DisplayName or LocalPlayer.Name) .. "'s portal"
			T.check(label and label.Text == want, "p4 portal client: ...with a name tag \"" .. want .. "\"", label and label.Text or "no tag")
			T.check(gui and gui:IsA("BillboardGui") and gui.Size.X.Scale == 0 and gui.LightInfluence == 0 and label.TextSize >= 22
				and (label.TextStrokeTransparency <= 0.5 or label:FindFirstChild("TextOutline") ~= nil) and gui.MaxDistance >= 60,
				"p4 portal client: ...a pixel-sized 22 px tag with a stroke (World text rule)", label and tostring(label.TextSize) or "")
			local sw = nil
			for _, p in ipairs(parts) do
				if p.Name == "Swirl" then
					sw = p
				end
			end
			local c0 = sw and sw.CFrame
			advance(0.3)
			T.check(sw and c0 and (sw.CFrame.RightVector - c0.RightVector).Magnitude > 0.05, "p4 portal client: ...its swirl turns")
			-- another player's portal: faded; a portal far from the camera: not drawn
			other:SetAttribute("HomePortal", portalText(at + Vector3.new(10, 0, 0), 0, now + 10))
			advance(0.6)
			local oi = Fx.Portal(other)
			local minT = 1
			for _, p in ipairs(partsOf(oi and oi.Model)) do
				if p.Name == "Ring" then
					minT = math.min(minT, p.Transparency)
				end
			end
			T.check(oi and oi.Model and oi.Faded and minT >= 0.5, "p4 portal client: another player's portal is drawn faded (only its owner can go through)", fmt("%.2f", minT))
			other:SetAttribute("HomePortal", portalText(at + Vector3.new(400, 0, 0), 0, now + 10))
			advance(0.6)
			oi = Fx.Portal(other)
			T.check(oi == nil or oi.Model == nil, "p4 portal client: a portal more than 150 studs from the camera is not drawn")
			other:SetAttribute("HomePortal", nil)
			-- used: the attribute is cleared -> it shrinks away
			local model = info and info.Model
			LocalPlayer:SetAttribute("HomePortal", nil)
			advance(0.15)
			local mid = Fx.Portal(LocalPlayer)
			T.check(mid and mid.Closing and mid.Scale < 1 and mid.Scale > 0, "p4 portal client: used (the attribute cleared): the portal shrinks away...", mid and fmt("%.2f", mid.Scale) or "gone at once")
			advance(0.5)
			T.check(Fx.Portal(LocalPlayer) == nil and (model == nil or model.Parent == nil), "p4 portal client: ...and is gone")
			-- expired: closesAt passes while the attribute is still there
			now = workspace:GetServerTimeNow()
			LocalPlayer:SetAttribute("HomePortal", portalText(at, 0, now + 0.6))
			advance(0.4)
			T.check(Fx.Portal(LocalPlayer) ~= nil, "p4 portal client: a new portal opens")
			advance(1.4)
			T.check(Fx.Portal(LocalPlayer) == nil, "p4 portal client: ...and goes by itself when closesAt has passed (expired)")
			LocalPlayer:SetAttribute("HomePortal", nil)
			-- junk
			LocalPlayer:SetAttribute("HomePortal", "nan,1,2")
			advance(0.3)
			T.check(Fx.Portal(LocalPlayer) == nil, "p4 portal client: a junk HomePortal draws nothing")
			LocalPlayer:SetAttribute("HomePortal", nil)
			-- the arrival ring
			local root = KC.root()
			if root then
				if cam then
					cam.CFrame = CFrame.lookAt(root.Position + Vector3.new(0, 8, -24), root.Position)
				end
				LocalPlayer:SetAttribute("PortalArrived", workspace:GetServerTimeNow())
				advance(0.1)
				local st = Fx.Stats()
				T.check(st.Rings == 1 and st.RingParts >= 8 and st.RingParts <= 20, "p4 portal client: PortalArrived plays the arrival ring (<= 20 parts) where the player stands",
					tostring(st.Rings) .. " rings, " .. tostring(st.RingParts) .. " parts")
				advance(1.6)
				st = Fx.Stats()
				T.check(st.Rings == 0 and st.RingParts == 0, "p4 portal client: ...for 1.5 s, then nothing is left")
			else
				T.warn("p4 portal client: no character in the client world, arrival ring skipped")
			end
			-- Stop removes everything, Init again works
			LocalPlayer:SetAttribute("HomePortal", portalText(at, 0, workspace:GetServerTimeNow() + 10))
			advance(0.3)
			Fx.Stop()
			T.check(workspace:FindFirstChild("HomePortalFx") == nil and Fx.Portal(LocalPlayer) == nil, "p4 portal client: HomePortalFx.Stop() removes every part")
			Fx.Init()
			advance(0.4)
			T.check(Fx.Portal(LocalPlayer) ~= nil, "p4 portal client: ...and Init() draws the open portal again")
			LocalPlayer:SetAttribute("HomePortal", nil)
			advance(0.6)
		end)
		if cam and savedCam then
			cam.CFrame = savedCam
		end
		Mock.RemovePlayer(other)
		LocalPlayer:SetAttribute("HomePortal", nil)
		advance(0.3)
		if not ok then
			T.fail("p4 portal client: ring scenario raised an error", tostring(err))
		end
		local warned = nil
		for i = outputBefore + 1, #Mock.Output do
			local o = Mock.Output[i]
			if o.kind == "warn" and o.text:find("HomePortalFx", 1, true) then
				warned = o.text
			end
		end
		T.check(warned == nil and #Mock.Errors == errorsBefore, "p4 portal client: no errors or warnings from HomePortalFx", tostring(warned))
		KC.flushErrors("client_p4portal_ring")
	end)

	-- the followers' dive (PetController, wave 2) with HomePortalFx drawing the same portal
	CS.client_p4portal_dive = guarded("client_p4portal_dive", function()
		local Fx = KC.M.HomePortalFx or moduleAt("client", "Controllers/HomePortalFx")
		local PC = KC.M.PetController or moduleAt("client", "Controllers/PetController")
		local Cat = moduleAt("shared", "PetCatalog")
		if not (Fx and PC and Cat and type(PC.GetFollowerInfo) == "function") then
			T.fail("p4 portal client: HomePortalFx / PetController.GetFollowerInfo load in the client world")
			return
		end
		Fx.Init()
		local ids = {}
		for _, d in ipairs(Cat.Pets) do
			if d.Rarity == "Common" and not d.EventOnly and #ids < 2 then
				ids[#ids + 1] = d.Id
			end
		end
		local owned = {}
		for _, id in ipairs(ids) do
			owned[id] = 1
		end
		KC.toClient("ProfileSync", { Tokens = 600, Pets = owned, Equipped = {}, Items = {}, Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			SpotIndex = 1, Perks = {}, Discovered = owned, IndexClaimed = {}, Tutorial = { Step = 99, Done = true, Gifted = true }, PetLevels = {}, PetGrowth = {} })
		Mock.Teleport(LocalPlayer, Vector3.new(0, 40, 0))
		LocalPlayer:SetAttribute("EquippedPets", table.concat(ids, ","))
		advance(3)
		local root = KC.root()
		local cam = workspace.CurrentCamera
		if cam and root then
			cam.CFrame = CFrame.lookAt(root.Position + Vector3.new(0, 10, -26), root.Position)
		end
		local portal = root.Position + Vector3.new(0, -3, -6)
		LocalPlayer:SetAttribute("HomePortal", fmt("%.2f,%.2f,%.2f,0,%.3f", portal.X, portal.Y, portal.Z, workspace:GetServerTimeNow() + 10))
		advance(0.4)
		T.check(Fx.Portal(LocalPlayer) and Fx.Portal(LocalPlayer).Model ~= nil, "p4 portal client: (the owner's portal is drawn)")
		local start = root.Position
		for step = 1, 10 do
			Mock.Teleport(LocalPlayer, start:Lerp(portal + Vector3.new(0, 3, 0), step / 10))
			advance(0.05)
		end
		local home = Vector3.new(700, 40, 700)
		Mock.Teleport(LocalPlayer, home)
		LocalPlayer:SetAttribute("HomePortal", nil)
		LocalPlayer:SetAttribute("PortalArrived", workspace:GetServerTimeNow())
		advance(0.15)
		local inf = PC.GetFollowerInfo(LocalPlayer) or {}
		local diving = #inf >= 1
		for _, i in ipairs(inf) do
			diving = diving and i.Diving and i.Model ~= nil and (i.Model:GetPivot().Position - portal).Magnitude < 8
		end
		T.check(diving, "p4 portal client: the followers dive into the portal centre after the owner walked in", #inf .. " followers")
		T.check(Fx.Portal(LocalPlayer) and Fx.Portal(LocalPlayer).Closing, "p4 portal client: ...while the used portal shrinks away")
		T.check(Fx.Stats().Rings >= 1, "p4 portal client: ...and the arrival ring plays at home")
		advance(2)
		inf = PC.GetFollowerInfo(LocalPlayer) or {}
		local back = #inf >= 1
		for _, i in ipairs(inf) do
			back = back and not i.Diving and i.Model ~= nil and (i.Model:GetPivot().Position - KC.root().Position).Magnitude < 9
		end
		T.check(back and Fx.Portal(LocalPlayer) == nil, "p4 portal client: ...then the pets pop out behind the owner and the portal is gone")
		LocalPlayer:SetAttribute("EquippedPets", "")
		advance(0.5)
		KC.flushErrors("client_p4portal_dive")
	end)

	return CS
end

local S = {}
if CONTEXT ~= "server" then
	return clientScenarios()
end

local advance, config, mod = K.advance, K.config, K.mod

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

local function TS()
	return requireAt("server/Services/TycoonService")
end

local userSeq = 0
local function join(prefix)
	userSeq = userSeq + 1
	local p = Mock.AddPlayer(prefix .. userSeq, 965000 + userSeq)
	advance(1.0)
	return p
end

local function leave(p)
	if p and p.Parent then
		Mock.RemovePlayer(p)
	end
	advance(0.6)
end

local function spots()
	return (K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
end

local function freeIndex(skip)
	local SS = mod("SpotService")
	for i = 1, config().Lobby.SpotCount do
		if spots()[i] and not SS.GetOwner(i) and i ~= skip then
			return i
		end
	end
	return nil
end

local function claimPromptOf(index)
	local info = spots()[index]
	if info and info.Folder then
		for _, d in ipairs(info.Folder:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Name == "ClaimPrompt" then
				return d
			end
		end
	end
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "ClaimPrompt" and d:GetAttribute("SpotIndex") == index then
			return d
		end
	end
	return nil
end

local function claim(p, index)
	local prompt = claimPromptOf(index)
	local SS = mod("SpotService")
	local gate = SS.GateCFrame(spots()[index])
	if gate and p.Character then
		Mock.Teleport(p, gate * CFrame.new(0, 3, -5))
	end
	if prompt then
		Mock.Trigger(prompt, p)
	end
	advance(0.6)
	return prompt ~= nil
end

local function remote(name)
	return K.remoteFolder():FindFirstChild(name)
end

local function homeAction(p, action, arg)
	Mock.FromClient(remote("HomeAction"), p, action, arg)
end

local function attrPortal(p)
	return p:GetAttribute(config().Attr.HomePortal)
end

-- "x,y,z,yaw,closesAt" -> pos, yaw, closesAt (nil for anything else)
local function parsePortal(text)
	if type(text) ~= "string" then
		return nil
	end
	local parts = {}
	for n in text:gmatch("[^,]+") do
		parts[#parts + 1] = tonumber(n)
	end
	if #parts ~= 5 then
		return nil
	end
	for _, v in ipairs(parts) do
		if type(v) ~= "number" or v ~= v then
			return nil
		end
	end
	return Vector3.new(parts[1], parts[2], parts[3]), parts[4], parts[5]
end

-- the player stands on the plaza looking along +X
local function onPlaza(p)
	local at = config().Lobby.Origin + Vector3.new(20, 4, 20)
	Mock.Teleport(p, CFrame.lookAt(at, at + Vector3.new(1, 0, 0)))
	advance(0.1)
	return at
end

local function walkIn(p, pos)
	Mock.Teleport(p, CFrame.new(pos + Vector3.new(0, 3, 0)))
	advance(0.5) -- two passes of the 0.2 s loop
end

local function countParts(container)
	local n = 0
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("BasePart") then
			n = n + 1
		end
	end
	return n
end

----------------------------------------------------------------------------------------------------
-- p4portal_home
----------------------------------------------------------------------------------------------------
S.p4portal_home = guarded("p4portal_home", function()
	if not K.needBoot() then
		return
	end
	local Config = config()
	local SS = mod("SpotService")
	local Ty = TS()
	if not T.check(Ty ~= nil and type(Ty.OpenHomePortal) == "function" and type(Ty.GoHome) == "function", "p4 portal: TycoonService.OpenHomePortal / GoHome") then
		return
	end
	T.check(type(Config.Attr.HomePortal) == "string" and type(Config.Attr.PortalArrived) == "string", "p4 portal: Config.Attr.HomePortal / PortalArrived exist")
	local a = join("PortalA")
	local index = freeIndex()
	claim(a, index)
	local info = spots()[index]
	if not T.check(SS.GetSpot(a) == info, "p4 portal: (precondition) the plot is claimed") then
		leave(a)
		return
	end

	-- GoHome: the attribute, the point 6 studs ahead, closesAt = server time + 10, no server part
	local at = onPlaza(a)
	local partsBefore = countParts(workspace)
	local used = {}
	local conn = Ty.PortalUsed:Connect(function(pl)
		used[#used + 1] = pl
	end)
	local serverNow = workspace:GetServerTimeNow()
	homeAction(a, "GoHome")
	advance(0.1)
	local text = attrPortal(a)
	local pos, yaw, closesAt = parsePortal(text)
	T.check(pos ~= nil, "p4 portal: HomeAction 'GoHome' writes the player attribute HomePortal = 'x,y,z,yaw,closesAt'", tostring(text))
	if pos then
		local d = K.planar(pos, at)
		T.check(d >= 3 and d <= 6.6, "p4 portal: the portal opens about 6 studs ahead of the character (" .. string.format("%.1f", d) .. " studs)")
		T.check(pos.X > at.X + 2 and abs(pos.Z - at.Z) < 1.5, "p4 portal: ...in the direction the character looks (+X)")
		T.check(abs(pos.Y - at.Y) <= 8, "p4 portal: ...on the ground near the character's height", string.format("%.1f vs %.1f", pos.Y, at.Y))
		T.check(abs(yaw) <= 360 and closesAt >= serverNow + 9.5 and closesAt <= serverNow + 10.6, "p4 portal: ...closesAt = GetServerTimeNow() + 10, yaw in degrees",
			string.format("yaw %.1f closes in %.1f", yaw, closesAt - serverNow))
	end
	T.eq(countParts(workspace), partsBefore, "p4 portal: the server builds no part for the portal (HomePortalFx draws it)")
	-- pressing again keeps the open portal
	advance(0.5)
	homeAction(a, "GoHome")
	Ty.GoHome(a)
	advance(0.1)
	T.eq(attrPortal(a), text, "p4 portal: pressing again keeps the open portal (same attribute)")
	-- standing next to it (not in it): nothing happens
	if pos then
		Mock.Teleport(a, CFrame.new(pos + Vector3.new(5, 3, 0)))
		advance(0.5)
		T.check(attrPortal(a) == text and K.planar(K.root(a).Position, pos) >= 4, "p4 portal: standing 5 studs from the point does not trigger it")
	end
	-- another player at the portal point does not move
	local b = join("PortalB")
	if pos then
		walkIn(b, pos)
		T.check(K.planar(K.root(b).Position, pos) < 1 and attrPortal(a) == text and #used == 0, "p4 portal: another player standing in the portal is not teleported (only the owner is checked)")
		leave(b)
	end
	-- the owner walks in: home, PortalArrived, HomePortal cleared, PortalUsed
	if pos then
		walkIn(a, pos)
		local root = K.root(a)
		T.check(root ~= nil and K.planar(root.Position, info.SpawnCFrame.Position) <= 6 and abs(root.Position.Y - info.SpawnCFrame.Position.Y) <= 6,
			"p4 portal: the owner walking in lands within 6 studs of their home SpawnCFrame", root and string.format("%.1f studs", K.planar(root.Position, info.SpawnCFrame.Position)) or "no root")
		T.eq(attrPortal(a), nil, "p4 portal: ...HomePortal is cleared on use")
		local arrived = a:GetAttribute(Config.Attr.PortalArrived)
		T.check(type(arrived) == "number" and abs(arrived - workspace:GetServerTimeNow()) <= 1.5, "p4 portal: ...PortalArrived = server time (the arrival swirl)", tostring(arrived))
		T.check(#used == 1 and used[1] == a, "p4 portal: ...PortalUsed(player) fired once")
	end
	conn:Disconnect()

	-- expiry: a portal nobody enters closes after 10 s; the cooldown: no new portal within 3 s of the request
	advance(3.1)
	onPlaza(a)
	local okOpen = Ty.OpenHomePortal(a)
	advance(0.1)
	local text2 = attrPortal(a)
	T.check(okOpen == true and parsePortal(text2) ~= nil, "p4 portal: TycoonService.OpenHomePortal(player) opens a portal too")
	local okAgain, whyAgain = Ty.OpenHomePortal(a)
	T.check(okAgain == true and attrPortal(a) == text2, "p4 portal: a second request while it is open keeps it (ok, nothing new)", tostring(whyAgain))
	advance(9.5)
	T.eq(attrPortal(a), text2, "p4 portal: still open at 9.6 s")
	advance(0.9)
	T.eq(attrPortal(a), nil, "p4 portal: the portal expires after 10 s (attribute removed)")
	T.check(K.planar(K.root(a).Position, info.SpawnCFrame.Position) > 20, "p4 portal: ...nobody moved")
	local okCd, whyCd = Ty.OpenHomePortal(a)
	T.check(okCd == true and attrPortal(a) ~= nil, "p4 portal: the cooldown (3 s) has passed during the 10 s: a new portal opens")
	local text3 = attrPortal(a)
	local pos3 = parsePortal(text3)
	walkIn(a, pos3)
	T.eq(attrPortal(a), nil, "p4 portal: (used)")
	onPlaza(a)
	local okFast, whyFast = Ty.OpenHomePortal(a)
	T.check(okFast == false and attrPortal(a) == nil, "p4 portal: a new portal within 3 s of the last request is refused (cooldown)", tostring(whyFast))
	advance(3.1)
	homeAction(a, "GoHome")
	advance(0.1)
	T.check(attrPortal(a) ~= nil, "p4 portal: ...and allowed after 3 s")
	walkIn(a, (parsePortal(attrPortal(a))))

	-- no home: the portal leads to a free gate (GoToSpot and GoHome)
	local c = join("PortalC")
	local mark = K.logSize()
	onPlaza(c)
	Mock.FromClient(remote("GoToSpot"), c)
	advance(0.1)
	local textC = attrPortal(c)
	local posC = parsePortal(textC)
	T.check(posC ~= nil, "p4 portal: GoToSpot without a home opens the portal (toward a free gate)", tostring(textC))
	T.check(K.planar(K.root(c).Position, config().Lobby.Origin + Vector3.new(20, 4, 20)) < 1, "p4 portal: ...and does not move the player by itself")
	local suggested = SS.SuggestSpot(c)
	local gate = suggested and SS.GateCFrame(suggested)
	if posC and gate then
		walkIn(c, posC)
		T.check(K.planar(K.root(c).Position, gate.Position) <= 10 and SS.GetSpot(c) == nil, "p4 portal: walking in lands just outside the suggested free gate (nothing is claimed)",
			string.format("%.1f studs from the gate", K.planar(K.root(c).Position, gate.Position)))
		T.check(K.notified(c, "Press E at the gate to claim this home", "info", mark), "p4 portal: ...with the 'Press E at the gate to claim this home!' toast")
		T.eq(attrPortal(c), nil, "p4 portal: ...HomePortal cleared")
		T.check(type(c:GetAttribute(Config.Attr.PortalArrived)) == "number", "p4 portal: ...PortalArrived written")
	end
	advance(3.1)
	onPlaza(c)
	homeAction(c, "GoHome")
	advance(0.1)
	T.check(parsePortal(attrPortal(c)) ~= nil, "p4 portal: HomeAction 'GoHome' without a home opens the same portal toward a free gate")
	leave(c)
	-- leaving closes the portal state (no stale attribute on a later join is possible: the player is gone)
	leave(a)
	K.flushErrors("p4portal_home")
	K.flushWarnings("p4portal_home", { "HomeBuilder is missing" })
end)

----------------------------------------------------------------------------------------------------
-- p4portal_refusals
----------------------------------------------------------------------------------------------------
S.p4portal_refusals = guarded("p4portal_refusals", function()
	if not K.needBoot() then
		return
	end
	local Config = config()
	local SS = mod("SpotService")
	local Ty = TS()
	if not Ty then
		T.fail("p4 portal: TycoonService loads")
		return
	end
	local inBattleAttr = Config.Attr.InBattle or "InBattle"
	local a = join("PortalR")
	local index = freeIndex()
	claim(a, index)
	local info = spots()[index]
	onPlaza(a)

	-- in a match
	a:SetAttribute(Config.Attr.InMatch, true)
	local mark = K.logSize()
	homeAction(a, "GoHome")
	advance(0.3)
	T.check(attrPortal(a) == nil and K.notified(a, "Finish your match first", "bad", mark), "p4 portal refusals: in an obby match: no portal, 'Finish your match first'")
	a:SetAttribute(Config.Attr.InMatch, false)
	advance(3.1)
	-- in a battle / ring run (the InBattle attribute carries the battle id)
	a:SetAttribute(inBattleAttr, "battle_1")
	mark = K.logSize()
	homeAction(a, "GoHome")
	advance(0.3)
	T.check(attrPortal(a) == nil and K.notified(a, "Finish your battle first!", "bad", mark), "p4 portal refusals: InBattle: no portal, 'Finish your battle first!'")
	local okTp = SS.Teleport(a)
	T.check(okTp == false and K.planar(K.root(a).Position, info.SpawnCFrame.Position) > 20, "p4 portal refusals: SpotService.Teleport refuses InBattle (safe zones: no teleport out of a fight)")
	mark = K.logSize()
	Mock.FromClient(remote("GoToSpot"), a)
	advance(0.3)
	T.check(attrPortal(a) == nil and K.planar(K.root(a).Position, info.SpawnCFrame.Position) > 20 and K.notified(a, "Finish your battle first!", "bad", mark),
		"p4 portal refusals: the GoToSpot remote refuses InBattle with the same toast")
	a:SetAttribute(inBattleAttr, nil)
	advance(3.1)
	-- locked in a portal party
	a:SetAttribute("PortalLocked", "Easy")
	mark = K.logSize()
	homeAction(a, "GoHome")
	advance(0.3)
	T.check(attrPortal(a) == nil and K.notified(a, "portal party", "bad", mark), "p4 portal refusals: locked in a portal party: no portal")
	a:SetAttribute("PortalLocked", nil)
	advance(3.1)
	-- dead
	Mock.Kill(a)
	advance(0.1)
	local okDead, whyDead = Ty.OpenHomePortal(a)
	T.check(okDead == false and attrPortal(a) == nil, "p4 portal refusals: a dead character opens no portal", tostring(whyDead))
	Mock.Respawn(a)
	advance(1.0)
	onPlaza(a)
	-- an open portal closes without a teleport when the owner enters a battle before walking in
	advance(3.1)
	local okOpen = Ty.OpenHomePortal(a)
	local pos = parsePortal(attrPortal(a))
	T.check(okOpen == true and pos ~= nil, "p4 portal refusals: (precondition) a portal is open")
	a:SetAttribute(inBattleAttr, "battle_2")
	if pos then
		Mock.Teleport(a, CFrame.new(pos + Vector3.new(0, 3, 0)))
		advance(0.5)
		T.check(K.planar(K.root(a).Position, pos) < 1 and attrPortal(a) == nil, "p4 portal refusals: walking into an open portal while InBattle teleports nobody and closes the portal")
	end
	a:SetAttribute(inBattleAttr, nil)
	-- the owner's own open portal is never usable by someone else, even from their own plot
	advance(3.1)
	onPlaza(a)
	Ty.OpenHomePortal(a)
	local posA = parsePortal(attrPortal(a))
	local b = join("PortalThief")
	claim(b, freeIndex(index))
	local bInfo = SS.GetSpot(b)
	if posA then
		local before = K.root(b).Position
		Mock.Teleport(b, CFrame.new(posA + Vector3.new(0, 3, 0)))
		advance(0.5)
		T.check(K.planar(K.root(b).Position, posA) < 1 and K.planar(K.root(b).Position, bInfo.SpawnCFrame.Position) > 20 and attrPortal(a) ~= nil,
			"p4 portal refusals: a plot owner in someone else's portal goes nowhere and leaves it open")
		T.check(K.planar(K.root(b).Position, before) > 1, "p4 portal refusals: (the thief did stand in it)")
	end
	-- junk arguments through the remote change nothing
	local junk = { 0 / 0, -1, math.huge, {}, "x", string.rep("y", 500), true }
	for _, arg in ipairs(junk) do
		homeAction(b, "GoHome", arg)
	end
	homeAction(b, "Teleport", 1)
	homeAction(b, string.rep("G", 100), nil)
	advance(0.3)
	T.check(parsePortal(attrPortal(b)) ~= nil or attrPortal(b) == nil, "p4 portal refusals: junk GoHome arguments are ignored (a valid portal or none, never an error)")
	-- no plot and every home taken: no portal, a toast
	leave(b)
	leave(a)
	K.flushErrors("p4portal_refusals")
	K.flushWarnings("p4portal_refusals", { "HomeBuilder is missing" })
end)

return S
