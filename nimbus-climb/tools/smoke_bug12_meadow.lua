-- smoke_bug12_meadow.lua: bug #12 "improve ground (grass,flowers etc) design with blender and gemini" (art wave, the
-- player's pick: option B "Wind-Sown Sky Meadow", note: "make sure the grass/flowers quality is high and the animation
-- is smooth"). Loaded by tools/smoke.py in the server world and the client world:
--   bug12meadow_server (server) the booted lobby:
--                      the bug: no flat flower square is left in any ground layer (plaza lawn patches, shop lawn, garden
--                      islands: no lawn-height part in a FLOWERS colour);
--                      the fix "nothing grows through props": every published clump stands on lawn (a lawn / patch
--                      part under it, at the right layer height) and no path, border, kerb, prop (trunk, roots, lamp,
--                      bench, flower bed, fountain, sack...) box covers its foot; none within 2.5 studs of an NPC spot;
--                      grass thins out at the paths (none within MEADOW.Edge - slack of a path / prop box);
--                      the zones: the wild outer ring is clearly denser than the mown inner lawns, has every kind;
--                      the data: Version / Count / Chunks / Wind / Base / Origin / Kinds / Tint1..6 attributes, every
--                      chunk <= ChunkClumps * 9 characters, decodes to Count clumps, tints only on wildflowers; the
--                      server's Meadow.encode matches this file's reference encoder, decode round-trips within 1/64
--                      stud; the Meadow folder holds no parts (the lobby part budget);
--                      the story: >= 1 SeedSack next to a plaza flower bed, non-colliding, Detail decor, its +X
--                      downwind, its Part build mirrors the kit's SACK; a drift of >= 20 wildflowers in the bed's two
--                      colours streams downwind of each sack; dandelion seeds: a Detail-tagged MeadowSeeds model with
--                      built-in particle textures blowing downwind;
--                      the meshes: a committed manifest for every meadow key (1 part, flowers 2 with a tinted Petal),
--                      clump-sized bounds, and the sack manifest fits the sack Part build
--   client_bug12meadow_sway (client) MeadowFx on a test Meadow folder: Tilt is bounded and smooth at 60 fps, its gust
--                      rolls downwind, Density falls from 1 to 0; the clumps near the camera grow (plain stand-ins with
--                      no mesh ids), far ones do not; every part is local, anchored, never collides / touches / is
--                      queried, casts no shadow; near clumps sway smoothly about their foot (the foot never moves, a
--                      frame-to-frame step stays small), clumps beyond SWAY_FADE stand at rest; a key that becomes
--                      ready swaps its clumps to the mesh template; Low graphics removes every clump, High brings them
--                      back; Stop() removes the holder and nothing moves afterwards
-- Deterministic: mock clock only. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, max, min, sqrt, floor = math.abs, math.max, math.min, math.sqrt, math.floor
local fmt = string.format

local FLOWER_RGB = { { 246, 150, 188 }, { 250, 214, 92 }, { 244, 244, 248 }, { 172, 142, 232 }, { 236, 104, 108 }, { 112, 172, 240 } }

-- the reference encoder (LobbyBuilder Meadow.encode / MeadowFx.Decode must agree with it)
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64(v, n)
	local out = {}
	for i = n, 1, -1 do
		local d = v % 64
		out[i] = string.sub(B64, d + 1, d + 1)
		v = (v - d) / 64
	end
	return table.concat(out)
end
local function refEncode(c)
	local qx = max(0, min(262143, floor((c.X + 2048) * 64 + 0.5)))
	local qz = max(0, min(262143, floor((c.Z + 2048) * 64 + 0.5)))
	local yaw = floor(((c.Yaw % (2 * math.pi)) / (2 * math.pi)) * 64 + 0.5) % 64
	local sc = max(0, min(15, floor((c.Scale - 0.7) / 0.04 + 0.5)))
	return b64((c.Kind - 1) * 8 + (c.Tint or 0), 1) .. b64(qx, 3) .. b64(qz, 3) .. b64(yaw, 1) .. b64(sc + (c.Patch and 16 or 0), 1)
end
local SAMPLES = {
	{ Kind = 1, Tint = 0, X = 112.37, Z = -40.02, Yaw = 0.3, Scale = 1.1, Patch = false },
	{ Kind = 5, Tint = 4, X = -71.5, Z = 44.125, Yaw = 6.1, Scale = 0.74, Patch = true },
	{ Kind = 8, Tint = 0, X = 0.01, Z = 239.9, Yaw = -0.4, Scale = 1.3, Patch = false },
	{ Kind = 7, Tint = 0, X = -250.5, Z = -3.3, Yaw = 3.14159, Scale = 0.9, Patch = true },
}

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

	-- world XZ half extents + top / bottom of a part
	local function extents(p)
		local cf, s = p.CFrame, p.Size
		local rx, ry, rz = cf.RightVector, cf.UpVector, cf.LookVector
		local ex = (abs(rx.X) * s.X + abs(ry.X) * s.Y + abs(rz.X) * s.Z) / 2
		local ey = (abs(rx.Y) * s.X + abs(ry.Y) * s.Y + abs(rz.Y) * s.Z) / 2
		local ez = (abs(rx.Z) * s.X + abs(ry.Z) * s.Y + abs(rz.Z) * s.Z) / 2
		return ex, ey, ez
	end

	-- a point (y = probe height) inside the part's own box, grown by pad on X / Z
	local function covers(p, x, y, z, pad)
		local q = p.CFrame:PointToObjectSpace(Vector3.new(x, y, z))
		local s = p.Size
		return abs(q.X) <= s.X / 2 + pad and abs(q.Z) <= s.Z / 2 + pad and abs(q.Y) <= s.Y / 2 + 0.05
	end

	local function bucketise(list, size)
		local B = {}
		for _, p in ipairs(list) do
			local ex, _, ez = extents(p)
			local pos = p.Position
			for bx = floor((pos.X - ex - 2) / size), floor((pos.X + ex + 2) / size) do
				for bz = floor((pos.Z - ez - 2) / size), floor((pos.Z + ez + 2) / size) do
					local key = bx * 100000 + bz
					local l = B[key]
					if not l then
						l = {}
						B[key] = l
					end
					l[#l + 1] = p
				end
			end
		end
		return function(x, z)
			return B[floor(x / size) * 100000 + floor(z / size)] or {}
		end
	end

	S.bug12meadow_server = guarded("bug12meadow_server", function()
		if not K.needBoot() then
			return
		end
		local LB = requireAt("server/Services/LobbyBuilder")
		local MD = LB and LB._Meadow
		if not T.check(type(MD) == "table" and type(MD.K) == "table" and type(MD.decode) == "function" and type(MD.encode) == "function",
			"bug12 meadow: LobbyBuilder._Meadow (encode / decode / K) is exported") then
			return
		end
		local MK = MD.K
		local lobby = workspace:FindFirstChild("NimbusLobby")
		local folder = lobby and lobby:FindFirstChild("Meadow")
		if not T.check(folder ~= nil and folder:IsA("Folder"), "bug12 meadow: the lobby publishes its Meadow folder") then
			return
		end
		local CS = game:GetService("CollectionService")
		local Config = K.config()
		local TOP = Config.Lobby.Origin.Y
		local Ycheck = TOP - 0.4

		-- 1. the bug: no flat flower square in any ground layer
		local squares = {}
		local visible = {}
		for _, d in ipairs(lobby:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 0.99 then
				visible[#visible + 1] = d
				local _, ey = extents(d)
				local top = d.Position.Y + ey
				if top <= TOP - 0.2 and top >= TOP - 0.5 then
					local c = d.Color
					local r, g, b = floor(c.R * 255 + 0.5), floor(c.G * 255 + 0.5), floor(c.B * 255 + 0.5)
					for _, f in ipairs(FLOWER_RGB) do
						if abs(r - f[1]) <= 1 and abs(g - f[2]) <= 1 and abs(b - f[3]) <= 1 then
							squares[#squares + 1] = d:GetFullName()
							break
						end
					end
				end
			end
		end
		T.check(#squares == 0, "bug12 meadow: no flat flower squares left in the lawn layers (plaza, shop, gardens)",
			#squares .. " e.g. " .. tostring(squares[1]))

		-- 2. the data
		local count = folder:GetAttribute("Count")
		local chunks = folder:GetAttribute("Chunks")
		local wind = folder:GetAttribute("Wind")
		local base = folder:GetAttribute("Base")
		local kinds = folder:GetAttribute("Kinds")
		T.check(folder:GetAttribute("Version") == MK.Version and type(count) == "number" and type(chunks) == "number"
			and typeof(wind) == "Vector3" and abs(wind.Magnitude - 1) < 1e-3 and abs(wind.Y) < 1e-6
			and type(base) == "number" and abs(base - Ycheck) < 1e-6 and kinds == table.concat(MK.Kinds, ","),
			"bug12 meadow: Version / Count / Chunks / Wind (unit, flat) / Base (the lawn top) / Kinds attributes", fmt("%s clumps", tostring(count)))
		local tintsOk = true
		for i, f in ipairs(FLOWER_RGB) do
			local c = folder:GetAttribute("Tint" .. i)
			if typeof(c) ~= "Color3" or abs(c.R * 255 - f[1]) > 1 or abs(c.G * 255 - f[2]) > 1 then
				tintsOk = false
			end
		end
		T.check(tintsOk, "bug12 meadow: Tint1..6 are the flower beds' FLOWERS colours")
		local partsInFolder = 0
		for _, d in ipairs(folder:GetDescendants()) do
			if d:IsA("BasePart") then
				partsInFolder = partsInFolder + 1
			end
		end
		T.check(partsInFolder == 0, "bug12 meadow: the Meadow folder holds no parts (clients grow the clumps: the lobby part budget)")
		local clumps, longest = {}, 0
		for ch = 1, chunks or 0 do
			local s = folder:GetAttribute("Clumps" .. ch)
			if type(s) == "string" then
				longest = max(longest, #s)
				for i = 1, floor(#s / 9) do
					clumps[#clumps + 1] = MD.decode(s, i)
				end
			end
		end
		T.check(#clumps == count and count >= 1000, fmt("bug12 meadow: the chunks decode to Count clumps (%d of %s)", #clumps, tostring(count)))
		T.check(longest <= MK.ChunkClumps * 9, fmt("bug12 meadow: every chunk <= %d characters (longest %d)", MK.ChunkClumps * 9, longest))
		local badKind, badTint = 0, 0
		local perKind = {}
		for _, c in ipairs(clumps) do
			if not MK.Kinds[c.Kind] then
				badKind = badKind + 1
			else
				perKind[c.Kind] = (perKind[c.Kind] or 0) + 1
			end
			if (c.Kind == 5) ~= (c.Tint >= 1 and c.Tint <= 6) then
				badTint = badTint + 1
			end
		end
		T.check(badKind == 0 and badTint == 0, "bug12 meadow: every clump is a known kind; only wildflowers carry a tint (1..6)",
			fmt("%d bad kinds, %d bad tints", badKind, badTint))
		local allKinds = true
		for k = 1, #MK.Kinds do
			if (perKind[k] or 0) < 20 then
				allKinds = false
			end
		end
		T.check(allKinds, "bug12 meadow: every kind grows somewhere (>= 20 each)")
		-- encoding: the server agrees with the reference; decode round-trips
		local encOk, rtErr = true, 0
		for _, c in ipairs(SAMPLES) do
			local s = MD.encode(c)
			if s ~= refEncode(c) or #s ~= 9 then
				encOk = false
			end
			local d = MD.decode(s, 1)
			rtErr = max(rtErr, abs(d.X - c.X), abs(d.Z - c.Z))
			if d.Kind ~= c.Kind or d.Tint ~= c.Tint or d.Patch ~= c.Patch or abs(d.Scale - c.Scale) > 0.021 + (c.Scale > 1.3 and 1 or 0) then
				encOk = false
			end
		end
		T.check(encOk and rtErr <= 1 / 128 + 1e-9, "bug12 meadow: Meadow.encode = the reference encoder (9 chars) and decode round-trips (<= 1/128 stud)",
			fmt("err %.5f", rtErr))

		-- 3. placement: on lawn, never under / in a path, border, kerb or prop, thinner at the edges
		local blocking, lawn = {}, {}
		for _, p in ipairs(visible) do
			local _, ey = extents(p)
			local top, bottom = p.Position.Y + ey, p.Position.Y - ey
			if top > TOP - 0.45 and bottom < TOP + 2.5 then
				if top <= TOP - 0.25 then
					lawn[#lawn + 1] = p
				else
					blocking[#blocking + 1] = p
				end
			end
		end
		local blockAt, lawnAt = bucketise(blocking, 8), bucketise(lawn, 8)
		local origin = folder:GetAttribute("Origin")
		local ox, oz = origin and origin.X or 0, origin and origin.Z or 0
		local onLawn, covered, wrongLayer, nearEdge, layerWhy = 0, {}, 0, 0, ""
		local slack = MK.Edge - 0.55
		for _, c in ipairs(clumps) do
			local x, z = ox + c.X, oz + c.Z
			local y = Ycheck + (c.Patch and 0.1 or 0)
			local under, topUnder = false, -1e9
			for _, p in ipairs(lawnAt(x, z)) do
				if covers(p, x, p.Position.Y, z, 0) then
					under = true
				end
				if covers(p, x, p.Position.Y, z, 0.05) then -- a foot on a patch's edge may take either layer
					local _, ey = extents(p)
					local top = p.Position.Y + ey
					if topUnder < -1e8 or abs(top - y) < abs(topUnder - y) then
						topUnder = top
					end
				end
			end
			if under then
				onLawn = onLawn + 1
				if topUnder > -1e8 and abs(topUnder - y) > 0.06 then
					wrongLayer = wrongLayer + 1
					layerWhy = fmt("(%.2f, %.2f) patch %s, lawn top %.2f", x, z, tostring(c.Patch), topUnder - TOP)
				end
			end
			for _, p in ipairs(blockAt(x, z)) do
				local _, ey = extents(p)
				local probe = max(p.Position.Y - ey + 0.01, min(p.Position.Y + ey - 0.01, y + 0.05))
				if covers(p, x, probe, z, 0.05) then
					if #covered < 4 then
						covered[#covered + 1] = fmt("%s at (%.1f, %.1f)", p:GetFullName(), x, z)
					else
						covered[#covered + 1] = "..."
					end
					break
				elseif covers(p, x, probe, z, slack) then
					nearEdge = nearEdge + 1
					break
				end
			end
		end
		T.check(onLawn == #clumps, fmt("bug12 meadow: every clump stands on lawn (%d of %d)", onLawn, #clumps))
		T.check(wrongLayer == 0, "bug12 meadow: ...at the right height (the lawn -0.4 or a lawn patch -0.3)", wrongLayer .. " " .. layerWhy)
		T.check(#covered == 0, "bug12 meadow: nothing grows under / through a path, kerb, tree, lamp, bench, bed, fountain or sack",
			table.concat(covered, "; "))
		T.check(nearEdge == 0, fmt("bug12 meadow: grass keeps %.2f studs off every path and prop edge (it thins out there)", slack), tostring(nearEdge))
		local npcBad = 0
		for _, s in ipairs((K.W and K.W.lobbyInfo and K.W.lobbyInfo.NpcSpots) or {}) do
			local p = typeof(s) == "CFrame" and s.Position or s
			for _, c in ipairs(clumps) do
				local dx, dz = ox + c.X - p.X, oz + c.Z - p.Z
				if dx * dx + dz * dz < 2.5 * 2.5 then
					npcBad = npcBad + 1
				end
			end
		end
		T.check(npcBad == 0, "bug12 meadow: no clump within 2.5 studs of an NPC spot", tostring(npcBad))
		-- zones: wild outside the circle walk, mown inside
		local wildN, mownN = 0, 0
		local R = (Config.Lobby.PlazaRadius or 150) + 6
		for _, c in ipairs(clumps) do
			local r = sqrt(c.X * c.X + c.Z * c.Z)
			if r > 106 and r < R then
				wildN = wildN + 1
			elseif r < 94 then
				mownN = mownN + 1
			end
		end
		local wildArea = math.pi * (R * R - 106 * 106) * 0.55
		local mownArea = math.pi * (94 * 94 - 36 * 36) * 0.8
		T.check(wildN / wildArea > 1.6 * mownN / mownArea, "bug12 meadow: the wild outer lawns grow clearly thicker than the mown inner lawns",
			fmt("wild %d (%.3f / sq stud), mown %d (%.3f / sq stud)", wildN, wildN / wildArea, mownN, mownN / mownArea))

		-- 4. the story: sacks, drifts, seeds
		local sacks = {}
		for _, d in ipairs(lobby:GetDescendants()) do
			if d:IsA("Model") and d.Name == "SeedSack" then
				sacks[#sacks + 1] = d
			end
		end
		local stats = MK.Stats or {}
		T.check(#sacks >= 1 and #sacks == (stats.Sacks or -1), fmt("bug12 meadow: the torn seed sacks stand in the plaza (%d)", #sacks))
		local beds = {}
		for _, d in ipairs(lobby:GetDescendants()) do
			if d:IsA("Model") and d.Name == "FlowerBed" then
				beds[#beds + 1] = d:GetPivot().Position
			end
		end
		local w = wind or Vector3.new(1, 0, 0)
		for i, sack in ipairs(sacks) do
			local pv = sack:GetPivot()
			local nearBed = false
			for _, b in ipairs(beds) do
				local dx, dz = pv.Position.X - b.X, pv.Position.Z - b.Z
				if dx * dx + dz * dz <= 5.5 * 5.5 then
					nearBed = true
				end
			end
			local collide, decorTag = false, false
			for _, p in ipairs(sack:GetDescendants()) do
				if p:IsA("BasePart") and (p.CanCollide or p.CanQuery) then
					collide = true
				end
			end
			local a = sack.Parent
			while a and a ~= lobby do
				if CS:HasTag(a, "NC_Detail") then
					decorTag = true
				end
				a = a.Parent
			end
			T.check(nearBed and not collide and decorTag and pv.RightVector:Dot(w) > 0.5 and abs(pv.UpVector.Y - 1) < 1e-6
				and abs(pv.Position.Y - Ycheck) <= 0.11,
				fmt("bug12 meadow: sack %d slumps by a flower bed on the lawn, non-colliding Detail decor, its tear (+X) downwind", i))
			local body = sack:FindFirstChild("Sack")
			T.check(body ~= nil and abs(body.Size.Y - MK.Sack.H) < 1e-6 and abs(body.Size.X - MK.Sack.W) < 1e-6,
				"bug12 meadow: ...its Part build is the kit's SACK (W, H)")
		end
		local last = MK.Last or {}
		for i, comet in ipairs(last.Comets or {}) do
			local n, inColour = 0, 0
			for _, c in ipairs(last.Clumps or {}) do
				if c.Drift then
					local rx, rz = c.X + ox - comet.From.X, c.Z + oz - comet.From.Z
					local t = rx * w.X + rz * w.Z
					local side = abs(rx * w.Z - rz * w.X)
					if t >= -1 and t <= MK.Drift.Length + 1 and side <= MK.Drift.Width0 + t * MK.Drift.Spread + 1 then
						n = n + 1
						if c.Kind == 5 and (c.Tint == comet.Tints[1] or c.Tint == comet.Tints[2]) then
							inColour = inColour + 1
						end
					end
				end
			end
			T.check(inColour >= 20 and inColour >= n * 0.7, fmt("bug12 meadow: a drift streams downwind from sack %d in the bed's two colours (%d of %d)", i, inColour, n))
		end
		local seeds = nil
		for _, d in ipairs(lobby:GetDescendants()) do
			if d:IsA("Model") and d.Name == "MeadowSeeds" then
				seeds = d
			end
		end
		local nSeeds, seedsOk = 0, true
		if seeds then
			for _, e in ipairs(seeds:GetDescendants()) do
				if e:IsA("ParticleEmitter") then
					nSeeds = nSeeds + 1
					local tex = tostring(e.Texture)
					if tex:sub(1, 30) ~= "rbxasset://textures/particles/" or e.Acceleration:Dot(w) <= 0 or e.Name ~= "DandelionSeeds" then
						seedsOk = false
					end
					if e.Parent:IsA("BasePart") and (e.Parent.CanCollide or e.Parent.Transparency < 1) then
						seedsOk = false
					end
				end
			end
		end
		T.check(seeds ~= nil and CS:HasTag(seeds, "NC_Detail") and nSeeds >= 1 and nSeeds <= MK.Seeds.Sectors and seedsOk,
			fmt("bug12 meadow: dandelion seeds blow downwind (%d invisible emitter boxes, built-in texture, Detail: Low parks them)", nSeeds))

		-- 5. the meshes (manifests committed with the kit)
		local manOk, manWhy = true, {}
		for _, key in ipairs(MK.Kinds) do
			local man = requireAt("shared/MeshManifests/" .. key)
			if type(man) ~= "table" then
				manOk = false
				manWhy[#manWhy + 1] = key .. " missing"
			else
				local parts = man.Parts or {}
				local size = man.Bounds and man.Bounds.Size
				local sx, sy, sz = size and size[1] or 99, size and size[2] or 99, size and size[3] or 99
				local want = (key == "meadow_flowers") and 2 or 1
				if #parts ~= want or sx > 2 or sz > 2 or sy > 1.6 then
					manOk = false
					manWhy[#manWhy + 1] = fmt("%s %d parts %.2fx%.2fx%.2f", key, #parts, sx, sy, sz)
				end
				if key == "meadow_flowers" then
					local petal = false
					for _, p in ipairs(parts) do
						if p.Name == "Petal" then
							petal = true
						end
					end
					if not petal then
						manOk = false
						manWhy[#manWhy + 1] = "meadow_flowers has no Petal part"
					end
				end
			end
		end
		T.check(manOk, "bug12 meadow: a committed manifest per meadow key (one baked part; flowers + a tinted Petal), clump-sized",
			table.concat(manWhy, "; "))
		local sman = requireAt("shared/MeshManifests/prop_seedsack")
		local hy = type(sman) == "table" and sman.Bounds and sman.Bounds.Max[2] or 0
		T.check(hy >= MK.Sack.H and hy <= MK.Sack.H + 0.7, fmt("bug12 meadow: the prop_seedsack manifest stands as tall as its Part build (%.2f)", hy))
		-- fix round (review finding 1): the four floors re-baked without the squares must not ship their OLD uploaded ids,
		-- or a live client dresses the square-baked meshes over the fixed Part floors (their LayoutSig matches the new
		-- layout). Until the re-upload mints new ids, MeshIds holds none, so the Part floors show (check.mjs mesh-ids-stale
		-- guards every key; upload_assets.py leaves stale keys out of MeshIds.lua).
		local ids = requireAt("shared/MeshIds")
		local shipped, sigOk = {}, true
		for _, key in ipairs({ "floor_plaza_lawnpatches", "floor_shop_2", "floor_garden_blossom_2", "floor_garden_pond_2" }) do
			if type(ids) ~= "table" or ids[key] ~= nil then
				shipped[#shipped + 1] = key
			end
			local fm = requireAt("shared/MeshManifests/" .. key)
			if not (type(fm) == "table" and fm.Attachments and fm.Attachments.LayoutSig) then
				sigOk = false
			end
		end
		T.check(#shipped == 0 and sigOk, "bug12 meadow: the re-baked square-free floors ship no stale id (Part floors until the re-upload)",
			table.concat(shipped, ", "))
		K.flushErrors("bug12meadow_server")
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

	S.client_bug12meadow_sway = guarded("client_bug12meadow_sway", function()
		local FX = KC.M.MeadowFx or moduleAt("client", "Controllers/MeadowFx")
		if not T.check(FX and type(FX.Init) == "function" and type(FX.Step) == "function" and type(FX.Stop) == "function"
			and type(FX.Tilt) == "function" and type(FX.Density) == "function" and type(FX.Decode) == "function"
			and type(FX.Stats) == "function", "bug12 sway: MeadowFx loads (Init, Step, Stop, Tilt, Density, Decode, Stats)") then
			return
		end
		local K = FX.K
		local St = FX._St
		FX.Stop()

		-- the wind: bounded, smooth at 60 fps, rolling downwind
		local amp, fl = 0.2, 0.035
		local hi, lo, jump = -1e9, 1e9, 0
		local prev = FX.Tilt(0, 10, 3, amp, fl, 0.3)
		for i = 1, 60 * 20 do
			local v = FX.Tilt(i / 60, 10, 3, amp, fl, 0.3)
			hi, lo = max(hi, v), min(lo, v)
			jump = max(jump, abs(v - prev))
			prev = v
		end
		T.check(hi <= amp * 1.3 + fl + 1e-9 and lo >= -amp * 0.13 - fl - 1e-9 and hi - lo > amp * 0.6,
			"bug12 sway: the tilt stays within the gust amplitude (a grass tuft ~12 degrees) and really moves",
			fmt("%.3f .. %.3f rad", lo, hi))
		T.check(jump < 0.012, "bug12 sway: ...smoothly (< 0.012 rad between 60 fps frames)", fmt("%.4f", jump))
		-- the gust peak moves downwind: at a later time the strongest tilt sits further along the wind
		local function peakAt(t)
			local best, at = -1e9, 0
			for a = 0, 35, 0.25 do
				local v = FX.Tilt(t, a, 0, 1, 0, 0)
				if v > best then
					best, at = v, a
				end
			end
			return at
		end
		local p0, p1 = peakAt(0), peakAt(1)
		local moved = (p1 - p0) % K.GUST_LEN
		T.check(abs(moved - K.GUST_LEN / K.GUST_PERIOD) < 1.0, "bug12 sway: the gust rolls downwind at GUST_LEN / GUST_PERIOD studs per second",
			fmt("%.2f studs in 1 s", moved))
		local dOk = FX.Density(0) == 1 and FX.Density(K.FULL) == 1 and FX.Density(K.FAR) == 0 and FX.Density(K.FAR + 50) == 0
		local lastD = 1
		for d = K.FULL, K.FAR, 1 do
			local v = FX.Density(d)
			if v > lastD + 1e-9 then
				dOk = false
			end
			lastD = v
		end
		T.check(dOk, "bug12 sway: Density is 1 near the camera, falls smoothly, 0 past FAR")

		-- a test meadow round the camera
		local cam = workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.new(0, 10, 0)
		local base = camPos.Y - 8
		local lobby = workspace:FindFirstChild("NimbusLobby")
		local madeLobby = false
		if not lobby then
			lobby = Instance.new("Folder")
			lobby.Name = "NimbusLobby"
			lobby.Parent = workspace
			madeLobby = true
		end
		local old = lobby:FindFirstChild("Meadow")
		if old then
			old.Parent = nil
		end
		local folder = Instance.new("Folder")
		folder.Name = "Meadow"
		local kinds = { "meadow_tuft_tall", "meadow_tuft_short", "meadow_tuft_seed", "meadow_sprig", "meadow_flowers",
			"meadow_cornflower", "meadow_dandelion", "meadow_clover" }
		local recs, near, far = {}, {}, {}
		for i = 1, 160 do
			local a = i * 2.39996
			local r = 1.5 + (i % 40) * 0.35 -- within 16 studs
			local c = { Kind = (i % 8) + 1, Tint = 0, X = camPos.X + math.cos(a) * r, Z = camPos.Z + math.sin(a) * r,
				Yaw = i * 0.7, Scale = 0.9 + (i % 5) * 0.06, Patch = (i % 3 == 0) }
			if c.Kind == 5 then
				c.Tint = (i % 6) + 1
			end
			recs[#recs + 1] = c
			near[#recs] = true
		end
		for i = 1, 40 do
			local c = { Kind = (i % 8) + 1, Tint = 0, X = camPos.X + K.FAR + 40 + i, Z = camPos.Z, Yaw = 0, Scale = 1, Patch = false }
			if c.Kind == 5 then
				c.Tint = 1
			end
			recs[#recs + 1] = c
			far[#recs] = true
		end
		local enc = {}
		for _, c in ipairs(recs) do
			enc[#enc + 1] = refEncode(c)
		end
		-- decode agrees with the reference encoder
		local decOk = true
		local whole = table.concat(enc)
		for i, c in ipairs(recs) do
			local d = FX.Decode(whole, i)
			if not d or d.Kind ~= c.Kind or d.Tint ~= c.Tint or abs(d.X - c.X) > 1 / 128 or abs(d.Z - c.Z) > 1 / 128 or d.Patch ~= c.Patch then
				decOk = false
			end
		end
		T.check(decOk, "bug12 sway: MeadowFx.Decode reads the server's 9-character records")
		folder:SetAttribute("Version", 1)
		folder:SetAttribute("Count", #recs)
		folder:SetAttribute("Chunks", 2)
		folder:SetAttribute("Clumps1", table.concat(enc, "", 1, 100))
		folder:SetAttribute("Clumps2", table.concat(enc, "", 101, #enc))
		folder:SetAttribute("Wind", Vector3.new(0.96, 0, 0.28).Unit)
		folder:SetAttribute("Base", base)
		folder:SetAttribute("Origin", Vector3.new(0, 0, 0))
		folder:SetAttribute("Kinds", table.concat(kinds, ","))
		for i, f in ipairs(FLOWER_RGB) do
			folder:SetAttribute("Tint" .. i, Color3.fromRGB(f[1], f[2], f[3]))
		end
		folder.Parent = lobby
		for _, k in ipairs(kinds) do
			if not K.SWAY[k] then
				T.fail("bug12 sway: MeadowFx has sway numbers for every server kind", k)
			end
		end

		local mode = "High"
		local readyKeys = {}
		local assembled = 0
		local lib = {
			IsReady = function(key)
				return readyKeys[key] == true
			end,
			Assemble = function(key, look, opts)
				assembled = assembled + 1
				local m = Instance.new("Model")
				local p = Instance.new("Part")
				p.Name = "Fixed"
				p.Size = Vector3.new(0.6, 0.9, 0.5)
				p.CFrame = CFrame.new(0.1, 0.45, 0)
				p:SetAttribute("SmokeMesh", key)
				p.Parent = m
				return m
			end,
		}
		FX.Init()
		St.Quality0 = { Effective = function()
			return mode
		end }
		FX._SetLib(lib)
		KC.advance(0.3)
		for _ = 1, 6 do
			KC.advance(1 / 60)
		end
		local st = FX.Stats()
		local holder = workspace:FindFirstChild("MeadowLocal")
		T.check(st.Clumps == #recs, fmt("bug12 sway: MeadowFx reads the folder (%d of %d clumps)", st.Clumps, #recs))
		local shownNear, shownFar = 0, 0
		for i in pairs(St.Inst) do
			if near[i] then
				shownNear = shownNear + 1
			elseif far[i] then
				shownFar = shownFar + 1
			end
		end
		T.check(shownNear >= 160 * K.FALLBACK_KEEP * 0.3 and shownFar == 0,
			fmt("bug12 sway: the clumps near the camera grow (%d of 160 stand-ins), none past FAR", shownNear))
		local flagsOk, nParts = true, 0
		if holder then
			for _, p in ipairs(holder:GetChildren()) do
				if p:IsA("BasePart") then
					nParts = nParts + 1
					if not p.Anchored or p.CanCollide or p.CanTouch or p.CanQuery or p.CastShadow then
						flagsOk = false
					end
				end
			end
		end
		T.check(holder ~= nil and nParts >= shownNear and flagsOk,
			fmt("bug12 sway: every clump part is local (workspace.MeadowLocal), anchored, never collides / touches / is queried, no shadow (%d parts)", nParts))
		-- smooth sway about the foot
		local idx = nil
		for i in pairs(St.Inst) do
			if near[i] and recs[i].Kind == 1 then
				idx = i
				break
			end
		end
		if T.check(idx ~= nil, "bug12 sway: a near tall tuft is shown") then
			local inst = St.Inst[idx]
			local part = inst.Parts[1]
			local foot = Vector3.new(St.PX[idx], St.PY[idx], St.PZ[idx])
			T.check(abs(St.PY[idx] - (base + (recs[idx].Patch and 0.1 or 0))) < 1e-6 and abs(St.PX[idx] - recs[idx].X) <= 1 / 128,
				"bug12 sway: the clump's foot is the published spot (patches 0.1 higher)")
			local d0 = (part.Position - foot).Magnitude
			local maxStep, footErr, minLook, prevCf = 0, 0, 1, part.CFrame
			local firstUp = part.CFrame.UpVector
			for _ = 1, 240 do
				KC.advance(1 / 60)
				local cf = part.CFrame
				maxStep = max(maxStep, (cf.Position - prevCf.Position).Magnitude)
				footErr = max(footErr, abs((cf.Position - foot).Magnitude - d0))
				minLook = min(minLook, cf.UpVector:Dot(firstUp))
				prevCf = cf
			end
			T.check(minLook < 0.9999, "bug12 sway: a near tuft sways in the wind", fmt("min up-dot %.5f", minLook))
			T.check(footErr < 1e-3, "bug12 sway: ...about its foot (the foot never slides)", fmt("%.5f", footErr))
			T.check(maxStep < 0.02, "bug12 sway: ...smoothly (< 0.02 stud per 60 fps frame)", fmt("%.4f", maxStep))
			-- fix round: the precomputed placement (quaternion foot * Local[j]) is the reference pose
			--   foot(P) * fromAxisAngle(Axis, tilt) * Yaw * (Rot + Pos * scale)   for every part
			local function refErr(i)
				local inst2 = St.Inst[i]
				local sw = K.SWAY[kinds[recs[i].Kind]] or K.SWAY.meadow_tuft_short
				local f = St.Fade[i] or 1
				local moving = false
				for _, m in ipairs(St.Moving) do
					if m == i then
						moving = true
					end
				end
				local tilt = moving and FX.Tilt(St.Time, St.Along[i], St.Cross[i], sw[1] * f, sw[2] * f, St.Phase[i]) or 0
				local foot2 = CFrame.new(St.PX[i], St.PY[i], St.PZ[i]) * CFrame.fromAxisAngle(St.Axis, tilt) * CFrame.Angles(0, St.Yaw[i], 0)
				local err = 0
				for j, p in ipairs(inst2.Parts) do
					local o = inst2.Offs[j]
					local want = foot2 * (o - o.Position) + foot2:VectorToWorldSpace(o.Position * St.Scale[i])
					local got = p.CFrame
					err = max(err, (got.Position - want.Position).Magnitude, (got.UpVector - want.UpVector).Magnitude,
						(got.LookVector - want.LookVector).Magnitude)
				end
				return err, tilt
			end
			local e1, tilt1 = refErr(idx)
			T.check(e1 < 1e-4 and tilt1 ~= 0, "bug12 sway: the fast placement equals the reference pose (tilt about the foot, yaw, scale)",
				fmt("err %.6f tilt %.4f", e1, tilt1))
		end
		-- rest beyond SWAY_FADE: a clump placed there stands exactly at its rest frame
		local movingOk = true
		for _, i in ipairs(St.Moving) do
			local dx, dz = recs[i].X - camPos.X, recs[i].Z - camPos.Z
			if sqrt(dx * dx + dz * dz) > K.SWAY_FADE + 1 then
				movingOk = false
			end
		end
		T.check(movingOk and #St.Moving > 0, fmt("bug12 sway: only clumps within SWAY_FADE move (%d moving)", #St.Moving))
		-- a key that becomes ready swaps its clumps to the mesh
		readyKeys.meadow_tuft_tall = true
		FX._KeyChanged("meadow_tuft_tall")
		for _ = 1, 4 do
			KC.advance(1 / 60)
		end
		KC.advance(0.3)
		local meshN, tallN, meshOther = 0, 0, 0
		for i, inst in pairs(St.Inst) do
			if recs[i].Kind == 1 then
				tallN = tallN + 1
				if inst.Mesh and inst.Parts[1]:GetAttribute("SmokeMesh") == "meadow_tuft_tall" then
					meshN = meshN + 1
				end
			elseif inst.Mesh then
				meshOther = meshOther + 1
			end
		end
		T.check(assembled >= 1 and tallN >= 1 and meshN == tallN and meshOther == 0,
			fmt("bug12 sway: a key that becomes ready swaps exactly its clumps to the mesh template (%d of %d)", meshN, tallN))
		-- fix round: a clump that appears inside the moving ring starts at its wind tilt, not upright (Init's pass runs
		-- outside Heartbeat, so nothing else would fix the pose before the next frame renders)
		FX.Stop()
		FX._SetLib(lib)
		St.Quality0 = { Effective = function()
			return mode
		end }
		FX.Init()
		do
			local worst, tilted, n = 0, 0, 0
			for _, i in ipairs(St.Moving) do
				local inst = St.Inst[i]
				if inst then
					local sw = K.SWAY[kinds[recs[i].Kind]] or K.SWAY.meadow_tuft_short
					local f = St.Fade[i] or 1
					local tilt = FX.Tilt(St.Time, St.Along[i], St.Cross[i], sw[1] * f, sw[2] * f, St.Phase[i])
					local foot2 = CFrame.new(St.PX[i], St.PY[i], St.PZ[i]) * CFrame.fromAxisAngle(St.Axis, tilt) * CFrame.Angles(0, St.Yaw[i], 0)
					local o = inst.Offs[1]
					local want = foot2 * (o - o.Position) + foot2:VectorToWorldSpace(o.Position * St.Scale[i])
					local got = inst.Parts[1].CFrame
					worst = max(worst, (got.Position - want.Position).Magnitude, (got.UpVector - want.UpVector).Magnitude)
					n = n + 1
					if abs(tilt) > 0.01 then
						tilted = tilted + 1
					end
				end
			end
			T.check(n > 0 and tilted > 0 and worst < 1e-4,
				fmt("bug12 sway: clumps spawned inside the moving ring start at their wind tilt (%d moving, %d tilted, err %.6f)", n, tilted, worst))
		end
		holder = workspace:FindFirstChild("MeadowLocal") -- Stop() replaced it
		-- Low / no folder: idle, so the LOD pass runs on the REFRESH timer only, not every frame (review)
		local idleCalls = 0
		mode = "Low"
		KC.advance(K.REFRESH + 0.05)
		local q0 = St.Quality0
		St.Quality0 = { Effective = function()
			idleCalls = idleCalls + 1
			return mode
		end }
		St.LastCam = nil -- as on a device that starts on Low, or before the Meadow folder arrives
		for _ = 1, 30 do
			KC.advance(1 / 60)
		end
		St.Quality0 = q0
		T.check(idleCalls <= 8, fmt("bug12 sway: on Low the LOD pass runs on the REFRESH timer, not every frame (%d passes in 30 frames)", idleCalls))
		mode = "High"
		KC.advance(K.REFRESH + 0.05)
		-- Low graphics: everything goes; High: back
		mode = "Low"
		KC.advance(K.REFRESH + 0.05)
		local lowParts = 0
		if holder then
			for _, p in ipairs(holder:GetChildren()) do
				if p:IsA("BasePart") then
					lowParts = lowParts + 1
				end
			end
		end
		T.check(FX.Stats().Shown == 0 and lowParts == 0, "bug12 sway: Low graphics removes every clump", tostring(lowParts))
		mode = "High"
		KC.advance(K.REFRESH + 0.05)
		KC.advance(1 / 60)
		T.check(FX.Stats().Shown > 0, "bug12 sway: ...and High grows them again", tostring(FX.Stats().Shown))
		-- Stop: holder gone, nothing moves
		FX.Stop()
		T.check(workspace:FindFirstChild("MeadowLocal") == nil and FX.Stats().Shown == 0, "bug12 sway: Stop() removes every clump and the holder")
		local w0 = FX.Stats().Writes
		KC.advance(0.5)
		T.check(FX.Stats().Writes == w0, "bug12 sway: after Stop() nothing runs")
		folder:Destroy()
		if old then
			old.Parent = lobby
		end
		if madeLobby then
			lobby:Destroy()
		end
		FX._SetLib(nil)
		FX.Init()
		KC.flushErrors("bug12meadow_sway")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
