-- smoke_bug2_dungeon.lua: bug batch 2, lane dungeon (player reports #3, #25, #19). Loaded by tools/smoke.py in the
-- server world and the client world:
--   bug2dgn_colliders  (server, #3 "a player shouldnt be able to walk through objects") every room template, every
--                      variant: the Cellar cell's 12 CellBars collide (CanCollide + CanQuery) and their gaps are
--                      narrower than a character; the generic rule "no visible prop a player can stand inside": a
--                      visible, non-colliding part (not Neon / Glass / ForceField) that reaches body height (bottom < 5,
--                      >= 1 stud tall above the floor) sits inside the footprint of ONE colliding part (+0.35) that
--                      rises high enough (top >= min(part top, part bottom + 5) - 0.6): rack, hearth, statue,
--                      brazier, throne back, lamp posts, hay, stalagmites, pool rim; (#19) every ceiling is opaque, colliding
--                      and queryable, so the camera occlusion keeps the capped camera inside the room
--   bug2dgn_doorlanes  (server, #25 "theres a table blocking the entrance") every template, every variant: no colliding
--                      prop (walls / floor / ceiling aside) inside a door lane = 6 studs either side of a doorway's
--                      centre line, from the doorway 12 studs into the room, 0.3 .. 7 studs high; a side without a
--                      doorway (Entrance_1's back wall, Treasure_1's portal wall) has no lane
--   client_bug2dgn_zoom (client, #19 "player shouldnt be able to zoom out the dungeon") MovementController.SetZoomMax:
--                      40 by default, 14 from the first Run payload, kept across a respawn inside the run, 40 again on
--                      End, on a run that vanished without an End (InBattle released), and when S.Run is dropped any
--                      other way; junk values ignored; CameraMinZoomDistance stays below the cap (first person is not
--                      forced)
-- Deterministic: templates built fresh from DungeonBuilder.Geo (never the cached ServerStorage set), mock clock only.
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K
	local G = {}

	local EFFECT = { [Enum.Material.Neon] = true, [Enum.Material.Glass] = true, [Enum.Material.ForceField] = true }
	local STRUCT_GROUP = { WallRun = true, FloorTiles = true }
	local STRUCT_NAME = { Floor = true, Ceiling = true, SafetyFloor = true }

	-- the world AABB of a part: { x0, x1, y0, y1, z0, z1 }
	function G.box(p)
		local cf, s = p.CFrame, p.Size
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local hx = math.abs(r.X) * s.X / 2 + math.abs(u.X) * s.Y / 2 + math.abs(l.X) * s.Z / 2
		local hy = math.abs(r.Y) * s.X / 2 + math.abs(u.Y) * s.Y / 2 + math.abs(l.Y) * s.Z / 2
		local hz = math.abs(r.Z) * s.X / 2 + math.abs(u.Z) * s.Y / 2 + math.abs(l.Z) * s.Z / 2
		local c = cf.Position
		return { x0 = c.X - hx, x1 = c.X + hx, y0 = c.Y - hy, y1 = c.Y + hy, z0 = c.Z - hz, z1 = c.Z + hz }
	end

	function G.structural(p, model)
		if STRUCT_NAME[p.Name] then
			return true
		end
		local a = p.Parent
		while a and a ~= model do
			if STRUCT_GROUP[a.Name] then
				return true
			end
			a = a.Parent
		end
		return false
	end

	-- a fresh build of every template (Geo.build: never the cached ServerStorage copies)
	function G.templates()
		local db = K.mod("DungeonBuilder")
		local out = {}
		if not db or type(db.Geo) ~= "table" or type(db.Templates) ~= "table" then
			return out, db
		end
		for _, name in ipairs(db.Templates) do
			local g = db.Geo[name]
			if g and type(g.build) == "function" then
				local ok, model = pcall(g.build)
				if ok and model then
					out[#out + 1] = { Name = name, Model = model, Geo = g }
				else
					T.fail("bug2 dungeon: template " .. name .. " builds", tostring(model))
				end
			end
		end
		return out, db
	end

	function G.free(list)
		for _, t in ipairs(list) do
			pcall(function()
				t.Model:Destroy()
			end)
		end
	end

	function G.parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Base" then
				out[#out + 1] = d
			end
		end
		return out
	end

	------------------------------------------------------------------------------------------------
	-- #3: colliders
	------------------------------------------------------------------------------------------------
	S.bug2dgn_colliders = guarded("bug2dgn_colliders", function()
		if not K.needBoot() then
			return
		end
		local list = G.templates()
		if not T.check(#list >= 17, "bug2 dungeon #3: every template builds (" .. #list .. ")") then
			G.free(list)
			return
		end
		-- the Cellar cell: 12 bars, colliding, gaps < 2 studs (a character is 2 wide)
		local cellars = 0
		for _, t in ipairs(list) do
			if t.Name:match("^Cellar_") then
				cellars = cellars + 1
				local bars, bad = {}, {}
				for _, p in ipairs(G.parts(t.Model)) do
					if p.Name == "CellBar" then
						bars[#bars + 1] = p
						if not (p.CanCollide and p.CanQuery) then
							bad[#bad + 1] = string.format("(%.1f, %.1f)", p.Position.X, p.Position.Z)
						end
					end
				end
				T.check(#bars == 12 and #bad == 0, "bug2 dungeon #3: " .. t.Name .. ": the cell's 12 CellBars collide (CanCollide + CanQuery)", #bars .. " bars, not colliding: " .. table.concat(bad, " "))
				-- the widest gap between neighbouring bars along each side
				local widest = 0
				for _, axis in ipairs({ "X", "Z" }) do
					local other = (axis == "X") and "Z" or "X"
					local rows = {}
					for _, b in ipairs(bars) do
						local key = string.format("%.2f", b.Position[other])
						rows[key] = rows[key] or {}
						table.insert(rows[key], b)
					end
					for _, row in pairs(rows) do
						if #row >= 3 then
							table.sort(row, function(a, b)
								return a.Position[axis] < b.Position[axis]
							end)
							for i = 2, #row do
								local gap = (row[i].Position[axis] - row[i - 1].Position[axis]) - (row[i].Size[axis] + row[i - 1].Size[axis]) / 2
								widest = math.max(widest, gap)
							end
						end
					end
				end
				T.check(widest > 0 and widest < 2, "bug2 dungeon #3: " .. t.Name .. ": no gap between the cell's bars a character fits through", string.format("widest gap %.2f", widest))
			end
		end
		T.eq(cellars, 3, "bug2 dungeon #3: all three Cellar variants checked")
		-- #19 (camera): every template has a ceiling the camera's occlusion sees (Poppercam stops only at colliding,
		-- queryable parts), so the zoom cap of 14 cannot lift the camera through it on a steep downward look
		local noCeiling = {}
		for _, t in ipairs(list) do
			local n, ok = 0, true
			for _, p in ipairs(G.parts(t.Model)) do
				if p.Name == "Ceiling" then
					n = n + 1
					ok = ok and p.CanCollide and p.CanQuery and p.Transparency < 0.25
				end
			end
			if n == 0 or not ok then
				noCeiling[#noCeiling + 1] = t.Name .. (n == 0 and " (none)" or "")
			end
		end
		T.check(#noCeiling == 0, "bug2 dungeon #19: every template's ceiling is opaque, colliding and queryable (the camera stays inside the room)", table.concat(noCeiling, ", "))
		-- the generic rule: no visible prop a player can stand inside
		local offenders = {}
		for _, t in ipairs(list) do
			local parts = G.parts(t.Model)
			local solids = {}
			for _, p in ipairs(parts) do
				if p.CanCollide then
					solids[#solids + 1] = G.box(p)
				end
			end
			for _, p in ipairs(parts) do
				if not p.CanCollide and p.Transparency < 0.99 and not EFFECT[p.Material] then
					local b = G.box(p)
					local y0 = math.max(0, b.y0)
					if y0 < 5 and b.y1 - y0 >= 1 then
						local need = math.min(b.y1, y0 + 5) - 0.6
						local backed = false
						for _, q in ipairs(solids) do
							if q.y1 >= need and q.x0 - 0.35 <= b.x0 and q.x1 + 0.35 >= b.x1 and q.z0 - 0.35 <= b.z0 and q.z1 + 0.35 >= b.z1 then
								backed = true
								break
							end
						end
						if not backed then
							local key = t.Name .. "." .. p.Name
							if not offenders[key] then
								offenders[key] = 0
								offenders[#offenders + 1] = key
							end
							offenders[key] = offenders[key] + 1
						end
					end
				end
			end
		end
		local text = {}
		for i, key in ipairs(offenders) do
			text[i] = key .. " x" .. offenders[key]
		end
		T.check(#offenders == 0, "bug2 dungeon #3: every template: no visible prop a player can stand inside (each body-height part is backed by a collider)",
			#offenders .. " kinds: " .. table.concat(text, ", "))
		G.free(list)
		K.flushErrors("bug2dgn_colliders")
	end)

	------------------------------------------------------------------------------------------------
	-- #25: door lanes
	------------------------------------------------------------------------------------------------
	local LANE_HALF = 6 -- studs either side of the door's centre line (the approved fix)
	local LANE_DEPTH = 12 -- from the doorway into the room

	S.bug2dgn_doorlanes = guarded("bug2dgn_doorlanes", function()
		if not K.needBoot() then
			return
		end
		local list = G.templates()
		if not T.check(#list >= 17, "bug2 dungeon #25: every template builds (" .. #list .. ")") then
			G.free(list)
			return
		end
		local offenders, lanes, perTemplate = {}, 0, {}
		for _, t in ipairs(list) do
			local parts = G.parts(t.Model)
			local walls = {}
			for _, p in ipairs(parts) do
				if p.CanCollide and G.structural(p, t.Model) then
					walls[#walls + 1] = G.box(p)
				end
			end
			-- a side has a doorway when no wall stands in it at head height
			local function doorway(at, inward)
				local x, y, z = at.X, 4, at.Z - inward * 0.5
				for _, w in ipairs(walls) do
					if x > w.x0 and x < w.x1 and y > w.y0 and y < w.y1 and z > w.z0 and z < w.z1 then
						return false
					end
				end
				return true
			end
			local mine = 0
			for _, side in ipairs({ { Name = "Entrance", At = t.Geo.Entrance, Inward = 1 }, { Name = "Exit", At = t.Geo.Exit, Inward = -1 } }) do
				if doorway(side.At, side.Inward) then
					lanes = lanes + 1
					mine = mine + 1
					local zA, zB = side.At.Z, side.At.Z + side.Inward * LANE_DEPTH
					local lz0, lz1 = math.min(zA, zB), math.max(zA, zB)
					local lx0, lx1 = side.At.X - LANE_HALF, side.At.X + LANE_HALF
					for _, p in ipairs(parts) do
						if p.CanCollide and not G.structural(p, t.Model) then
							local b = G.box(p)
							if b.x1 > lx0 and b.x0 < lx1 and b.z1 > lz0 and b.z0 < lz1 and b.y1 > 0.3 and b.y0 < 7 then
								offenders[#offenders + 1] = string.format("%s %s: %s (%.1f, %.1f, %.1f)", t.Name, side.Name, p.Name, p.Position.X, p.Position.Y, p.Position.Z)
							end
						end
					end
				end
			end
			perTemplate[#perTemplate + 1] = t.Name .. " " .. mine
		end
		-- two doorways on the 11 wave rooms, the Throne and the 3 corridors (open at both ends); one on Entrance_1 and Treasure_1
		T.check(lanes == 32, "bug2 dungeon #25: door lanes found on every template (" .. lanes .. " = 15 x 2 + 2)", table.concat(perTemplate, ", "))
		T.check(#offenders == 0, "bug2 dungeon #25: no colliding prop within 6 studs of a door's centre line (12 studs into the room) on any template / variant",
			#offenders .. ": " .. table.concat(offenders, ", ", 1, math.min(#offenders, 24)))
		-- the two reported tables, by name: off the door axis now
		local tables = {}
		for _, t in ipairs(list) do
			if t.Name == "Cellar_2" or t.Name == "Hall_3" then
				for _, p in ipairs(G.parts(t.Model)) do
					if p.Name == "TableTop" or (p.Name == "Bench" and t.Name == "Cellar_2") then
						local b = G.box(p)
						if b.x1 > -LANE_HALF and b.x0 < LANE_HALF then
							tables[#tables + 1] = string.format("%s.%s x %.1f..%.1f", t.Name, p.Name, b.x0, b.x1)
						end
					end
				end
			end
		end
		T.check(#tables == 0, "bug2 dungeon #25: the Cellar_2 table + bench and the Hall_3 table sit off the door axis", table.concat(tables, ", "))
		G.free(list)
		K.flushErrors("bug2dgn_doorlanes")
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	local KC = _G.KC

	local function mod(name)
		if KC.M and KC.M[name] then
			return KC.M[name]
		end
		local ok, m = pcall(require, Mock.GetPath(ROOTS["client"] .. "/Controllers/" .. name))
		return ok and m or nil
	end

	S.client_bug2dgn_zoom = guarded("client_bug2dgn_zoom", function()
		local MC, DC = mod("MovementController"), mod("DungeonController")
		local LP = game:GetService("Players").LocalPlayer
		if not T.check(MC ~= nil and DC ~= nil, "bug2 zoom: MovementController + DungeonController load") then
			return
		end
		pcall(DC.Init)
		local function zoom()
			return LP.CameraMaxZoomDistance
		end
		local function run(id)
			return { RunId = id, Floor = 1, Name = "Mossy Cellar", Element = "Earth", Room = 1, RoomCount = 4, Wave = 1, Waves = 2, State = "Fight",
				Members = { { UserId = LP.UserId, Name = LP.Name, Downed = false, Left = false } }, Joinable = false }
		end
		LP:SetAttribute("InBattle", nil)
		KC.advance(0.5)
		T.eq(zoom(), 40, "bug2 zoom: outside a dungeon the camera zooms out to 40")
		if not T.check(type(MC.SetZoomMax) == "function", "bug2 zoom: MovementController.SetZoomMax exists") then
			return
		end
		-- the API: a number caps the zoom, nil restores 40, junk is ignored
		MC.SetZoomMax(20)
		T.eq(zoom(), 20, "bug2 zoom: SetZoomMax(20) caps the zoom at 20")
		for _, junk in ipairs({ 0 / 0, -5, 0, "14", {}, math.huge }) do
			MC.SetZoomMax(junk)
		end
		T.eq(zoom(), 20, "bug2 zoom: SetZoomMax ignores junk (NaN, <= 0, strings, tables, inf)")
		MC.SetZoomMax(nil)
		T.eq(zoom(), 40, "bug2 zoom: SetZoomMax(nil) restores the normal 40")

		-- path 1: Run -> respawn inside the run -> End
		LP:SetAttribute("InBattle", "D71")
		KC.toClient("DungeonState", "Run", run("D71"))
		KC.advance(0.03)
		T.eq(zoom(), 10, "wave5 zoom nudge: a run starts zoomed in to 10")
		KC.advance(0.47)
		T.eq(zoom(), 14, "bug2 zoom: the first Run payload caps the zoom at 14")
		T.check(LP.CameraMinZoomDistance < 14 and LP.CameraMinZoomDistance <= 4, "bug2 zoom: the min zoom stays below the cap (first person is not forced)", tostring(LP.CameraMinZoomDistance))
		Mock.Kill(LP)
		Mock.Advance(1)
		Mock.Respawn(LP)
		KC.advance(2)
		T.eq(zoom(), 14, "bug2 zoom: a respawn inside the run keeps the cap at 14")
		KC.toClient("DungeonState", "Run", run("D71"))
		KC.advance(0.3)
		T.eq(zoom(), 14, "bug2 zoom: later Run payloads keep 14")
		LP:SetAttribute("InBattle", nil)
		KC.toClient("DungeonState", "End", { Floor = 1, Name = "Mossy Cellar", Cleared = false, Reason = "Quit", Room = 1, Totals = { Cash = 0, Tokens = 0, Xp = 0, Gems = 0 } })
		KC.advance(0.5)
		T.eq(zoom(), 40, "bug2 zoom: End restores 40")

		-- path 2: a run that vanishes without an End (InBattle released, the pocket left)
		LP:SetAttribute("InBattle", "D72")
		KC.toClient("DungeonState", "Run", run("D72"))
		KC.advance(0.5)
		T.eq(zoom(), 14, "bug2 zoom: a second run caps at 14 again")
		KC.advance(3.5)
		LP:SetAttribute("InBattle", nil)
		KC.advance(4)
		T.eq(zoom(), 40, "bug2 zoom: a run that vanished without an End restores 40")

		-- path 3: a fresh character after leaving: still 40
		Mock.Kill(LP)
		Mock.Advance(1)
		Mock.Respawn(LP)
		KC.advance(2)
		T.eq(zoom(), 40, "bug2 zoom: a respawn outside a run keeps 40")
		-- the End card is closed so later scenarios start clean
		pcall(function()
			local rg = LP.PlayerGui:FindFirstChild("NimbusDungeonRun")
			local ok = rg and rg:FindFirstChild("OkButton", true)
			if ok then
				Mock.Click(ok)
			end
		end)
		KC.advance(0.4)
		KC.flushErrors("client_bug2dgn_zoom")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
