-- smoke_lobby_shop_world.lua: the lobby-shop world (docs/superpowers/specs/2026-11-07-lobby-shop-design.md 5.9 / 5.6 / 5.11;
-- plan docs/superpowers/plans/2026-11-07-lobby-shop.md Tasks 10 / 12 / 13 / 14). Server world only (booted):
--   lobby_trove_plaza  the Sky Trove on the plaza lawn: its centre at polar 43 degrees r 56 from Config.Lobby.Origin
--                      (+-0.5), facing the plaza centre, <= 60 parts, the sign post at local x -6.2, the PromptPart in
--                      front, LobbyInfo.Shop.ItemShop = { PromptPart, Center, Model, Lid }; the Join sign (JoinAnchor 10.5
--                      studs up, JoinBillboard): "Group rewards coming soon!" at GroupId 0, "Join the group!" over "2,000
--                      Cash + 200 Tokens" when rebuilt with GroupId 123, tagged NC_Bob (BobStuds 0.5, BobSeconds 2.4); the
--                      forced fallback shop (LobbyBuilder._ForceShopFallback) puts its trove on the same plaza spot; one
--                      SkyTrove in a lobby either way; the TroveGroupDone attribute (a stored claim after the load and after
--                      a provisional load's recovery, at the claim, never for a player without the claim); the Egg Guide
--                      at the trove's old spot (at(-21, -8)): the 11 x 8 board reads "Every egg hatches a random pet of
--                      its rarity" and names the seven eggs in rarity colours in Config.Eggs.Order, no text behind the
--                      eggs; the stone shelf 3 studs in front (the plan's 4 touched the Celestial machine) with the seven
--                      eggs (2.25 x 3 x 2.5 ellipsoids, 2.5 studs apart, left to right as the reader sees them) at least
--                      3 studs from every roulette prompt and clear of every other shop prop; the dress requests name
--                      egg_common .. egg_secret on the Egg_<Rarity> parts at the egg's bottom centre; ML_DressKey only
--                      where MeshLibrary.Status(key) ~= "missing" (in --mesh the scenario gives the egg keys fixture
--                      holders, so the check runs there); the rarity board's subtitle; no "plaza decor skipped" warn in
--                      any build; every lobby light within the light rule
-- Rebuilds follow smoke_p6_lobby.lua: the booted lobby is set aside (renamed) and put back, the hooks (_Kit,
-- _ForceShopFallback), Config.Trove.GroupId, the Meadow stats and the fixture holders restored in every path.
-- Deterministic: mock clock only. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local S = {}
if CONTEXT ~= "server" then
	return S
end

local K = _G.K
local fmt = string.format
local CS = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")
local MESH_MODE = (os and os.getenv and os.getenv("NC_MESH_FIXTURES") == "1") or false
local ALLOWED_WARNINGS = { "[DataService]", "[MeshLibrary]", "[LobbyBuilder] shop failed: forced" }
local EGG_KEYS = {
	Common = "egg_common", Uncommon = "egg_uncommon", Rare = "egg_rare", Epic = "egg_epic",
	Legendary = "egg_legendary", Mythic = "egg_mythic", Secret = "egg_secret",
}
local LAWN = 0.4
local SOON_TEXT = "Group rewards coming soon!"
local GUIDE_FOOTER = "Every egg hatches a random pet of its rarity"
local RARITY_SUB = "Every egg hatches a pet of its rarity"

----------------------------------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------------------------------
local function req(path)
	local inst = K.moduleInstance(path)
	if not inst then
		return nil
	end
	local ok, m = pcall(require, inst)
	return (ok and type(m) == "table") and m or nil
end

local function hdist(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function near(a, b, tol)
	return (a - b).Magnitude <= (tol or 0.05)
end

local function sameColor(a, b)
	return math.abs(a.R - b.R) < 0.006 and math.abs(a.G - b.G) < 0.006 and math.abs(a.B - b.B) < 0.006
end

local function countParts(root)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			n = n + 1
		end
	end
	return n
end

local function polar(deg, r)
	local o = K.config().Lobby.Origin
	return Vector3.new(o.X + math.cos(math.rad(deg)) * r, o.Y, o.Z + math.sin(math.rad(deg)) * r)
end

-- LobbyBuilder's shop frame: centre = Origin + ShopOffset on the walking height, -Z towards the plaza centre
local function shopFrame()
	local L = K.config().Lobby
	local o = L.Origin
	local S0 = Vector3.new(o.X + L.ShopOffset.X, o.Y, o.Z + L.ShopOffset.Z)
	return CFrame.lookAt(S0, S0 + flat(o - S0).Unit), S0
end

local function guideFrame()
	local shopCF, S0 = shopFrame()
	local pos = (shopCF * CFrame.new(-21, 0, -8)).Position - Vector3.new(0, LAWN, 0)
	local target = S0 - Vector3.new(0, LAWN, 0)
	return CFrame.lookAt(pos, pos + flat(target - pos).Unit)
end

local function cfFromString(s)
	if type(s) ~= "string" then
		return nil
	end
	local v = {}
	for x in string.gmatch(s, "[^,%s]+") do
		v[#v + 1] = tonumber(x)
	end
	if #v ~= 12 then
		return nil
	end
	return CFrame.new((unpack or table.unpack)(v))
end

-- the four XZ corners of a part's footprint (parts here turn about Y only)
local function corners(p)
	local out = {}
	local hx, hz = p.Size.X / 2, p.Size.Z / 2
	for _, c in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		out[#out + 1] = (p.CFrame * CFrame.new(c[1] * hx, 0, c[2] * hz)).Position
	end
	return out
end

-- horizontal distance from a point to a part's footprint rectangle
local function pointToRect(pt, p)
	local l = p.CFrame:PointToObjectSpace(Vector3.new(pt.X, p.Position.Y, pt.Z))
	local dx = math.max(math.abs(l.X) - p.Size.X / 2, 0)
	local dz = math.max(math.abs(l.Z) - p.Size.Z / 2, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- horizontal gap between two parts' footprints (convex: the nearest point is a corner of one of them)
local function rectGap(a, b)
	local best = math.huge
	for _, c in ipairs(corners(a)) do
		best = math.min(best, pointToRect(c, b))
	end
	for _, c in ipairs(corners(b)) do
		best = math.min(best, pointToRect(c, a))
	end
	return best
end

local function texts(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("TextLabel") then
			out[#out + 1] = d
		end
	end
	return out
end

local function skippedWarns(from)
	local out = {}
	for i = (from or 0) + 1, #Mock.Output do
		local o = Mock.Output[i]
		if string.find(tostring(o.text), "plaza decor skipped", 1, true) then
			out[#out + 1] = o.text
		end
	end
	return out
end

local function troveOf(root)
	local found = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Model") and d.Name == "SkyTrove" then
			found[#found + 1] = d
		end
	end
	return found
end

-- a second LobbyBuilder.Build() next to the booted lobby (set aside, put back): setup(undo) may push restore functions
local function rebuild(label, setup, inspect)
	local LB = req("server/Services/LobbyBuilder")
	local live = workspace:FindFirstChild("NimbusLobby")
	if not T.check(LB ~= nil and live ~= nil, label .. ": (precondition) LobbyBuilder and the booted lobby") then
		return
	end
	local MK = LB._Meadow and LB._Meadow.K
	local savedStats, savedLast = MK and MK.Stats, MK and MK.Last
	local undo = {}
	live.Name = "NimbusLobby_LobbyShopKeep"
	local cursor = #Mock.Output
	local okSetup, errSetup = pcall(setup, undo, LB)
	local okBuild, info = false, "setup failed"
	if okSetup then
		okBuild, info = pcall(LB.Build)
	end
	local okInspect, errInspect = true, nil
	if okBuild and type(info) == "table" and typeof(info.Folder) == "Instance" then
		okInspect, errInspect = pcall(inspect, info, cursor)
	end
	if type(info) == "table" and typeof(info.Folder) == "Instance" then
		info.Folder:Destroy()
	end
	for i = #undo, 1, -1 do
		pcall(undo[i])
	end
	LB._Kit = nil
	LB._ForceShopFallback = nil
	if MK then
		MK.Stats, MK.Last = savedStats, savedLast
	end
	live.Name = "NimbusLobby"
	T.check(okSetup and okBuild and type(info) == "table" and info.Folder ~= nil, label .. ": LobbyBuilder.Build() ran", tostring(errSetup or info))
	T.check(okInspect, label .. ": the checks ran", tostring(errInspect))
end

----------------------------------------------------------------------------------------------------
-- the checks of one built trove / egg guide
----------------------------------------------------------------------------------------------------
local function checkTrovePlace(label, stall)
	local model = stall and stall.Model
	if not T.check(model ~= nil and model.Name == "SkyTrove" and model.PrimaryPart ~= nil, label .. ": ItemShop.Model is the SkyTrove with a PrimaryPart") then
		return nil
	end
	local o = K.config().Lobby.Origin
	local spot = polar(43, 56)
	T.check(typeof(stall.Center) == "Vector3" and hdist(stall.Center, spot) <= 0.5,
		label .. ": the trove's centre stands at polar 43 degrees, r 56 from the origin (+-0.5)", stall.Center and fmt("%.2f off", hdist(stall.Center, spot)) or "no Center")
	local cf = model.PrimaryPart.CFrame
	local toC = flat(o - cf.Position).Unit
	T.check(cf.LookVector:Dot(toC) > 0.99, label .. ": the trove faces the plaza centre", fmt("dot %.4f", cf.LookVector:Dot(toC)))
	T.check(math.abs(cf.Position.Y - 2.6 - (o.Y - LAWN)) <= 0.05, label .. ": the trove stands on the plaza lawn (Origin.Y - 0.4)", fmt("%.2f", cf.Position.Y - 2.6))
	return cf
end

local function checkEggGuide(label, lobby, Config)
	local shop = lobby:FindFirstChild("Shop")
	local guide = shop and shop:FindFirstChild("EggGuide")
	if not T.check(guide ~= nil and guide:IsA("Model"), label .. ": the Shop folder holds the EggGuide model") then
		return
	end
	local gcf = guideFrame()
	T.check(near(guide:GetPivot().Position, gcf.Position), label .. ": the Egg Guide stands at the trove's old spot (at(-21, -8), on the lawn)",
		fmt("%.2f off", (guide:GetPivot().Position - gcf.Position).Magnitude))
	T.check(guide:GetPivot().LookVector:Dot(gcf.LookVector) > 0.999, label .. ": ...facing the shop's centre")
	-- the board
	local board = guide:FindFirstChild("EggGuideBoard")
	local face = board and board:FindFirstChild("Face")
	local gui = face and face:FindFirstChildOfClass("SurfaceGui")
	if T.check(board ~= nil and face ~= nil and gui ~= nil, label .. ": an EggGuideBoard notice board with a SurfaceGui on its Face") then
		T.check(math.abs(face.Size.X - 11) < 0.01 and math.abs(face.Size.Y - 8) < 0.01, label .. ": the board is 11 x 8 (prop_board_s)", tostring(face.Size))
		local rows = {}
		local bad = {}
		for i, r in ipairs(Config.Eggs.Order) do
			local l = gui:FindFirstChild("EggName_" .. r, true)
			local def = nil
			for _, rd in ipairs(Config.Rarities) do
				if rd.Id == r then
					def = rd
				end
			end
			if not (l and l:IsA("TextLabel") and l.Text == Config.Eggs.Names[r]) then
				bad[#bad + 1] = r .. " (name " .. tostring(l and l.Text) .. ")"
			elseif r == "Secret" then
				local c = l.TextColor3
				if not (c.B * 255 >= 200 and c.B > c.R and c.B > c.G) then
					bad[#bad + 1] = "Secret (not violet " .. tostring(c) .. ")"
				end
			elseif not (def and sameColor(l.TextColor3, def.Color)) then
				bad[#bad + 1] = r .. " (colour " .. tostring(l.TextColor3) .. ")"
			end
			if l then
				rows[#rows + 1] = { Id = r, Y = l.Position.Y.Scale, X = l.Position.X.Scale, I = i }
			end
		end
		T.check(#bad == 0, label .. ": the board names the seven eggs (Config.Eggs.Names) in their rarity colours (Secret violet)", table.concat(bad, ", "))
		table.sort(rows, function(a, b)
			if math.abs(a.Y - b.Y) > 1e-3 then
				return a.Y < b.Y
			end
			return a.X < b.X
		end)
		local order = {}
		for _, rw in ipairs(rows) do
			order[#order + 1] = rw.Id
		end
		T.eq(table.concat(order, ","), table.concat(Config.Eggs.Order, ","), label .. ": ...read left to right, row by row, in Config.Eggs.Order")
		local line = gui:FindFirstChild("Sub", true)
		T.check(line ~= nil and line.Text == GUIDE_FOOTER, label .. ": the board's line reads '" .. GUIDE_FOOTER .. "'", line and line.Text)
		-- every text box ends above the eggs' tops (the shelf's eggs stand in front of the board's lower part)
		local shelf0 = guide:FindFirstChild("EggShelf")
		local eggTop = shelf0 and (shelf0.Position.Y + shelf0.Size.Y / 2 + 3) or math.huge
		local faceTop = face.Position.Y + face.Size.Y / 2
		local low = {}
		for _, l in ipairs(texts(gui)) do
			local bottom = faceTop - (l.Position.Y.Scale + l.Size.Y.Scale) * face.Size.Y
			if bottom < eggTop - 1e-3 then
				low[#low + 1] = l.Name .. fmt(" %.2f", bottom - eggTop)
			end
		end
		T.check(#low == 0, label .. ": no board text sits behind the eggs (every text box ends above their tops)", table.concat(low, ", "))
	end
	-- the shelf and the eggs
	local shelf = guide:FindFirstChild("EggShelf")
	if not T.check(shelf ~= nil and shelf:IsA("BasePart"), label .. ": a stone shelf EggShelf") then
		return
	end
	T.check(math.abs(shelf.Size.X - 18) <= 1 and shelf.Size.X >= 17.25 and math.abs(shelf.Size.Y - 0.8) <= 0.2 and math.abs(shelf.Size.Z - 2.6) <= 0.4,
		label .. ": the shelf is about 18 x 0.8 x 2.6 (at least the eggs' 17.25)", tostring(shelf.Size))
	-- 3 studs out, not the plan's 4: at 4 (18 wide) its end touched the Celestial machine's base
	T.check(hdist(shelf.Position, (gcf * CFrame.new(0, 0, -3)).Position) <= 0.05, label .. ": the shelf stands 3 studs in front of the board, centred on it")
	T.check(math.abs(shelf.Position.Y - shelf.Size.Y / 2 - gcf.Position.Y) <= 0.05, label .. ": ...its bottom on the board's ground (the lawn)")
	local top = shelf.Position.Y + shelf.Size.Y / 2
	local right = -gcf.RightVector -- the reader faces the board's front: their right is the board's -X
	local eggs, bad = {}, {}
	for i, r in ipairs(Config.Eggs.Order) do
		local egg = guide:FindFirstChild("Egg_" .. r)
		local def = nil
		for _, rd in ipairs(Config.Rarities) do
			if rd.Id == r then
				def = rd
			end
		end
		local mesh = egg and egg:FindFirstChildOfClass("SpecialMesh")
		local want = (gcf * CFrame.new((4 - i) * 2.5, shelf.Size.Y + 1.5, -3)).Position
		if not (egg and egg:IsA("BasePart")) then
			bad[#bad + 1] = r .. " missing"
		else
			eggs[#eggs + 1] = { Id = r, D = egg.Position:Dot(right) }
			if not near(egg.Size, Vector3.new(2.25, 3, 2.5), 0.01) then
				bad[#bad + 1] = r .. " size " .. tostring(egg.Size)
			end
			if not (mesh and mesh.MeshType == Enum.MeshType.Sphere and mesh.MeshId == "") then
				bad[#bad + 1] = r .. " not an ellipsoid (Sphere SpecialMesh)"
			end
			if egg.Material ~= Enum.Material.SmoothPlastic then
				bad[#bad + 1] = r .. " material " .. tostring(egg.Material)
			end
			if r == "Secret" then
				local c = egg.Color
				if not (c.B > c.R and c.B > c.G and math.max(c.R, c.G, c.B) * 255 <= 110) then
					bad[#bad + 1] = "Secret not dark violet " .. tostring(c)
				end
			elseif not (def and sameColor(egg.Color, def.Color)) then
				bad[#bad + 1] = r .. " colour " .. tostring(egg.Color)
			end
			if not near(egg.Position, want, 0.05) then
				bad[#bad + 1] = r .. fmt(" %.2f off its place", (egg.Position - want).Magnitude)
			end
			if math.abs(egg.Position.Y - 1.5 - top) > 0.05 then
				bad[#bad + 1] = r .. " not standing on the shelf"
			end
		end
	end
	T.check(#bad == 0 and #eggs == 7, label .. ": seven Egg_<Rarity> eggs, 2.25 x 3 x 2.5 ellipsoids in SmoothPlastic and the rarity colour (Secret dark violet), standing on the shelf 2.5 studs apart",
		table.concat(bad, "; "))
	table.sort(eggs, function(a, b)
		return a.D < b.D
	end)
	local order = {}
	for _, e in ipairs(eggs) do
		order[#order + 1] = e.Id
	end
	T.eq(table.concat(order, ","), table.concat(Config.Eggs.Order, ","), label .. ": ...left to right (as the reader sees them) in Config.Eggs.Order")
	-- clear of the machines' prompts and of the other shop props
	local gaps, minGap = {}, math.huge
	for _, rl in ipairs(Config.Roulettes) do
		local m = shop:FindFirstChild("Roulette_" .. rl.Id)
		local pp = m and m:FindFirstChild("PromptPart")
		if pp then
			local g = rectGap(shelf, pp)
			minGap = math.min(minGap, g)
			gaps[#gaps + 1] = rl.Id .. fmt(" %.2f", g)
		else
			gaps[#gaps + 1] = rl.Id .. " (no prompt part)"
			minGap = -1
		end
	end
	T.check(minGap >= 3, label .. ": the shelf stands at least 3 studs from every roulette machine's prompt part", table.concat(gaps, ", "))
	local hits = {}
	for _, d in ipairs(shop:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.99 and not d:IsDescendantOf(guide) and d.Name ~= "ShopNeck" and not string.find(d:GetFullName(), "Ground", 1, true)
			and not string.find(d:GetFullName(), "ShopCloud", 1, true) and d.Position.Y > top - 2 then
			for _, mine in ipairs({ shelf, guide:FindFirstChild("Egg_Common"), guide:FindFirstChild("Egg_Secret") }) do
				if mine and rectGap(mine, d) < 0.3 then
					hits[#hits + 1] = d:GetFullName():gsub("^.-Shop%.", "")
				end
			end
		end
	end
	T.check(#hits == 0, label .. ": the shelf and its end eggs keep clear of every other shop prop", table.concat(hits, ", "))
end

----------------------------------------------------------------------------------------------------
-- lobby_trove_plaza
----------------------------------------------------------------------------------------------------
S.lobby_trove_plaza = guarded("lobby_trove_plaza", function()
	if not K.needBoot() then
		return
	end
	local Config = K.config()
	local info = K.W.lobbyInfo
	local lobby = workspace:FindFirstChild("NimbusLobby")
	local ML = req("shared/MeshLibrary")
	T.check(Config.Tags.Bob == "NC_Bob" and Config.Tags.Spin == "NC_Spin" and Config.Attr.TroveGroupDone == "TroveGroupDone",
		"Config: Tags.Bob = NC_Bob, Tags.Spin = NC_Spin, Attr.TroveGroupDone = TroveGroupDone")

	------------------------------------------------------------------ the booted trove
	local stall = info and info.Shop and info.Shop.ItemShop
	T.check(type(stall) == "table" and stall.PromptPart and typeof(stall.Center) == "Vector3" and stall.Model and stall.Lid,
		"trove plaza: LobbyInfo.Shop.ItemShop keeps { PromptPart, Center, Model, Lid }")
	local cf = checkTrovePlace("trove plaza", stall)
	if cf then
		local model = stall.Model
		T.check(countParts(model) <= 60, "trove plaza: the trove stays <= 60 parts (the Join sign's anchor included)", tostring(countParts(model)))
		local post = model:FindFirstChild("Sign") and model.Sign:FindFirstChild("Post")
		local lx = post and cf:PointToObjectSpace(post.Position).X
		T.check(lx ~= nil and math.abs(lx + 6.2) <= 0.05, "trove plaza: the sign post stands at local x -6.2 (mirrored, clear of the How to play board)", tostring(lx))
		T.check((stall.PromptPart.Position - stall.Center).Magnitude < 10, "trove plaza: the PromptPart stands within 10 studs of the centre")
		T.check(#troveOf(lobby) == 1, "trove plaza: exactly one SkyTrove in the booted lobby", tostring(#troveOf(lobby)))
		local anchor = model:FindFirstChild("JoinAnchor")
		local bb = anchor and anchor:FindFirstChild("JoinBillboard")
		if T.check(anchor ~= nil and anchor:IsA("BasePart") and bb ~= nil and bb:IsA("BillboardGui"), "trove plaza: the JoinAnchor part carries the JoinBillboard") then
			local lift = anchor.Position.Y - (Config.Lobby.Origin.Y - LAWN)
			T.check(anchor.Transparency >= 0.99 and math.abs(lift - 10.5) <= 0.05 and hdist(anchor.Position, stall.Center) <= 0.05,
				"trove plaza: ...an invisible anchor 10.5 studs over the chest's centre", fmt("lift %.2f", lift))
			local list = texts(bb)
			T.check(#list == 1 and list[1].Text == SOON_TEXT, "trove plaza: at GroupId 0 the Join sign reads one line, '" .. SOON_TEXT .. "'",
				#list .. " lines: " .. tostring(list[1] and list[1].Text))
			T.check(CS:HasTag(bb, "NC_Bob") and bb:GetAttribute("BobStuds") == 0.5 and bb:GetAttribute("BobSeconds") == 2.4,
				"trove plaza: the Join sign is tagged NC_Bob with BobStuds 0.5 and BobSeconds 2.4")
			T.check(bb.Size.X.Scale == 0 and bb.Size.Y.Scale == 0 and bb.LightInfluence == 0 and bb.MaxDistance >= 50 and bb.MaxDistance <= 150,
				"trove plaza: ...a pixel-sized tag (the World text rule)")
		end
	end

	------------------------------------------------------------------ the booted Egg Guide, the rarity board
	checkEggGuide("egg guide", lobby, Config)
	local rb = lobby:FindFirstChild("RarityBoard", true)
	local sub = rb and rb:FindFirstChild("Sub", true)
	T.check(sub ~= nil and sub.Text == RARITY_SUB, "rarity board: the subtitle reads '" .. RARITY_SUB .. "'", sub and sub.Text)

	------------------------------------------------------------------ the build log, the light rule
	local skipped = skippedWarns(0)
	T.check(#skipped == 0, "trove plaza: no 'plaza decor skipped' warn in the build log", table.concat(skipped, " | "))
	local Lamps = Config.Sky.Lamps
	local bright, spots = {}, 0
	for _, d in ipairs(lobby:GetDescendants()) do
		if d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			spots = spots + 1
		elseif d:IsA("PointLight") then
			local lamp = d.Parent and Lamps.Names[d.Parent.Name]
			local ok = lamp and (d.Brightness <= 1.2 + 1e-6 and d.Range <= 16 and not d.Shadows) or (not lamp and d.Brightness <= 1.5 + 1e-6 and d.Range <= 28)
			if not ok then
				bright[#bright + 1] = d:GetFullName()
			end
		end
	end
	T.check(#bright == 0 and spots == 0, "trove plaza: every lobby light within the light rule (lamps <= 1.2 / 16, others <= 1.5 / 28, no spot / surface lights)", table.concat(bright, ", "))

	------------------------------------------------------------------ rebuild: GroupId 123 + the dress requests
	rebuild("trove plaza rebuild", function(undo, LB)
		local oldGid = Config.Trove.GroupId
		Config.Trove.GroupId = 123
		undo[#undo + 1] = function()
			Config.Trove.GroupId = oldGid
		end
		LB._Kit = { Targets = {}, Clouds = {} }
		if MESH_MODE then
			-- --mesh: fixture holders for the egg keys in the fixture MeshLibrary's root (Status -> "loading"), removed after
			local root = RS:FindFirstChild("P6PetsMeshLibrary")
			if T.check(root ~= nil, "egg guide (--mesh): the fixture MeshLibrary root exists") then
				for _, key in pairs(EGG_KEYS) do
					local h = Instance.new("Folder")
					h.Name = key
					h.Parent = root
					undo[#undo + 1] = function()
						h:Destroy()
					end
				end
			end
		end
	end, function(built, cursor)
		local LB = req("server/Services/LobbyBuilder")
		local stall2 = built.Shop and built.Shop.ItemShop
		checkTrovePlace("trove plaza rebuild", stall2)
		local bb = stall2 and stall2.Model and stall2.Model:FindFirstChild("JoinBillboard", true)
		local got = {}
		for _, l in ipairs(bb and texts(bb) or {}) do
			got[#got + 1] = l.Text
		end
		table.sort(got)
		T.eq(table.concat(got, " / "), "2,000 Cash + 200 Tokens / Join the group!", "trove plaza: with GroupId 123 the Join sign reads 'Join the group!' over '2,000 Cash + 200 Tokens'")
		T.eq(#troveOf(built.Folder), 1, "trove plaza rebuild: exactly one SkyTrove in the lobby")
		local recs = {}
		for _, rec in ipairs(LB._Kit and LB._Kit.Targets or {}) do
			for r, key in pairs(EGG_KEYS) do
				if rec.Key == key then
					recs[r] = recs[r] or {}
					table.insert(recs[r], rec)
				end
			end
		end
		local guide = built.Folder:FindFirstChild("EggGuide", true)
		local bad = {}
		for _, r in ipairs(Config.Eggs.Order) do
			local list = recs[r] or {}
			local egg = guide and guide:FindFirstChild("Egg_" .. r)
			local rec = list[1]
			if #list ~= 1 or not egg or rec.Target ~= egg then
				bad[#bad + 1] = r .. fmt(" (%d records)", #list)
			elseif not (typeof(rec.Origin) == "CFrame" and near(rec.Origin.Position, egg.Position - Vector3.new(0, 1.5, 0)) and rec.Origin.UpVector.Y > 0.999) then
				bad[#bad + 1] = r .. " (origin not the egg's bottom centre)"
			end
		end
		T.check(#bad == 0, "egg guide: seven dress requests egg_common .. egg_secret on the Egg_<Rarity> parts at the egg's bottom centre", table.concat(bad, ", "))
		local checked, wrong = 0, {}
		for _, r in ipairs(Config.Eggs.Order) do
			local key = EGG_KEYS[r]
			local okSt, st = pcall(ML.Status, key)
			local egg = guide and guide:FindFirstChild("Egg_" .. r)
			if okSt and st ~= "missing" and egg then
				checked = checked + 1
				local off = cfFromString(egg:GetAttribute("ML_Offset"))
				if egg:GetAttribute("ML_DressKey") ~= key or not off or not near((egg:GetPivot() * off).Position, egg.Position - Vector3.new(0, 1.5, 0)) then
					wrong[#wrong + 1] = r
				end
			end
		end
		if MESH_MODE then
			T.check(checked == 7 and #wrong == 0, "egg guide (--mesh): every egg is tagged with its egg_<rarity> key, the mesh pivot on the egg's bottom centre",
				checked .. " checked; wrong: " .. table.concat(wrong, ", "))
		else
			T.check(#wrong == 0, "egg guide: ML_DressKey on the eggs whose key is not missing (" .. checked .. " here; --mesh checks all seven)", table.concat(wrong, ", "))
		end
		local sk = skippedWarns(cursor)
		T.check(#sk == 0, "trove plaza rebuild: no 'plaza decor skipped' warn", table.concat(sk, " | "))
	end)

	------------------------------------------------------------------ rebuild: the forced fallback shop
	rebuild("trove plaza fallback", function(_, LB)
		LB._ForceShopFallback = true
	end, function(built, cursor)
		local folder = built.Folder
		T.check(folder:FindFirstChild("ShopFallback") ~= nil and folder:FindFirstChild("Shop") == nil, "trove plaza fallback: _ForceShopFallback takes the fallbackShop path")
		local stall2 = built.Shop and built.Shop.ItemShop
		T.check(type(stall2) == "table" and stall2.PromptPart and typeof(stall2.Center) == "Vector3" and stall2.Model and stall2.Lid,
			"trove plaza fallback: ItemShop keeps { PromptPart, Center, Model, Lid }")
		T.check(stall2 and stall2.Model and stall2.Model.Parent == folder.ShopFallback and typeof(stall2.Center) == "Vector3" and hdist(stall2.Center, polar(43, 56)) <= 0.5,
			"trove plaza fallback: the fallback trove stands on the same plaza spot (polar 43, r 56)", stall2 and stall2.Center and fmt("%.2f off", hdist(stall2.Center, polar(43, 56))) or "")
		T.eq(#troveOf(folder), 1, "trove plaza fallback: exactly one SkyTrove in the lobby")
		local sk = skippedWarns(cursor)
		T.check(#sk == 0, "trove plaza fallback: no 'plaza decor skipped' warn on that build either", table.concat(sk, " | "))
	end)
	local LB = req("server/Services/LobbyBuilder")
	T.check(LB and LB._ForceShopFallback == nil and LB._Kit == nil, "trove plaza: the hooks are back to nil")
	T.check(workspace:FindFirstChild("NimbusLobby") == lobby and #CS:GetTagged(Config.Tags.TroveLid) == 1, "trove plaza: the booted lobby is back (one tagged lid)")

	------------------------------------------------------------------ TroveGroupDone
	local DS = K.mod("DataService")
	local attr = Config.Attr.TroveGroupDone
	local key = Config.Tokens.DataStoreName .. "/u_"
	local savedFail, savedGid = Mock.DataStore.Fail, Config.Trove.GroupId
	local players = {}
	local function join(name, uid)
		local p = Mock.AddPlayer(name, uid)
		players[#players + 1] = p
		K.advance(1.2)
		return p
	end
	local function loaded(p)
		return K.waitFor(function()
			return DS.GetProfile(p) ~= nil and not DS.IsProvisional(p)
		end, 10)
	end
	local okRun, errRun = pcall(function()
		Mock.DataStore.Data[key .. 986101] = { Version = 2, Tokens = 0, Pets = {}, Equipped = {}, Trove = { Group = true } }
		local a = join("TroveDoneA", 986101)
		T.check(loaded(a), "trove done: (precondition) the stored profile loads")
		K.advance(0.3)
		T.eq(a:GetAttribute(attr), true, "trove done: a stored claim (Trove.Group) sets TroveGroupDone after the load")

		Mock.DataStore.Data[key .. 986102] = { Version = 2, Tokens = 0, Pets = {}, Equipped = {}, Trove = { Group = true } }
		Mock.DataStore.Fail = true
		local b = join("TroveDoneB", 986102)
		local prov = K.waitFor(function()
			return DS.IsProvisional(b) == true
		end, 10)
		T.check(prov and b:GetAttribute(attr) == nil, "trove done: a provisional (outage) load sets nothing")
		Mock.DataStore.Fail = savedFail
		local back = K.waitFor(function()
			return DS.IsProvisional(b) ~= true
		end, 60)
		K.advance(0.3)
		T.check(back and b:GetAttribute(attr) == true, "trove done: ...its recovery (ProfileRebased) sets TroveGroupDone")

		local c = join("TroveDoneC", 986103)
		T.check(loaded(c) and c:GetAttribute(attr) == nil, "trove done: a fresh player has no TroveGroupDone")
		Config.Trove.GroupId = 777
		c.IsInGroupAsync = function(_, gid)
			return gid == 777
		end
		Mock.FromClient(K.remoteFolder().TroveRequest, c, "Joined")
		K.advance(0.5)
		local trove = DS.GetTrove(c)
		T.check(type(trove) == "table" and trove.Group == true and c:GetAttribute(attr) == true, "trove done: the claim sets TroveGroupDone")
		c.IsInGroupAsync = nil
		Config.Trove.GroupId = savedGid

		local d = join("TroveDoneD", 986104)
		T.check(loaded(d), "trove done: (precondition) a second player loads")
		K.advance(0.3)
		T.eq(d:GetAttribute(attr), nil, "trove done: a second player without the claim has no attribute")
	end)
	Mock.DataStore.Fail = savedFail
	Config.Trove.GroupId = savedGid
	for _, p in ipairs(players) do
		if p.Parent then
			Mock.RemovePlayer(p)
		end
	end
	K.advance(1)
	T.check(okRun, "trove done: the scenario body ran", tostring(errRun))
	K.flushErrors("lobby_trove_plaza")
	K.flushWarnings("lobby_trove_plaza", ALLOWED_WARNINGS)
end)

return S
