-- HomeRoam: the deterministic roaming of the garden pets at home (ARCHITECTURE_V3.md "Phase 5 build contract" 3.5;
-- port of the home design's proto/HomeRoam.lua). The server (TycoonService's Cloud Cash ledger) and every client
-- (HomeFx) compute the SAME walk, eat and poop plan from (seed, slot, cycle) and the shared server clock, so nothing
-- about the motion is ever sent over the network: only the epochs (plot attribute `Roam`) and the drops (`CoinDrops`).
-- Pure Lua 5.1-compatible syntax; no Instances, no services, no yields; plot-local coordinates (X across, Z toward the
-- back fence, the gate at -Z), exactly the frame of TycoonCatalog's slots.
--
-- API (the contract):
--   HomeRoam.Version = 1                         a plot whose RoamVersion differs parks its pets on their beds
--   HomeRoam.Cycle 24 (s, = 3 meals), EatSeconds 3, PoopSeconds 1.5, MinSpeed 4 / MaxSpeed 9 (studs/s), WalkBudget 16.5,
--   MaxRoamCells 36, PoopFrac {0.35, 0.7}, SettleSeconds 20, SettleSpeed 4
--   HomeRoam.Build(layout?) -> nodes             lazy, once per VM: the static walk graph from TycoonCatalog.RoamLayout()
--                                                (or the given layout, tests): a 2-stud grid over |x|, |z| <= Half minus
--                                                every Blocked rect (+ its pad), 8-neighbours in a FIXED order (an edge
--                                                only where the segment is clear: exact segment / rect test)
--                                                (deterministic ties), one BFS field per slot to its eat point
--   HomeRoam.Plan(seed, slot, cycle) -> plan     { Out = { pt... } (eat point -> far point R, corners only), Poop = pt,
--                                                PoopAt (s into the cycle), Speed, OutLen, Idle }; pt = { x = , z = ,
--                                                [1] = x, [2] = z }. Park-Miller PRNG seeded seed x 7919 + slot x 104729
--                                                + cycle x 1299709. Timeline: [0, 3) eat at the eat point; walk out at
--                                                Speed = clamp(2 x OutLen / WalkBudget, 4, 9); the poop point lies ON the
--                                                path at arc fraction 0.35..0.7 (pulled back toward the bowl while within
--                                                3 studs of the Welcome pile; rounded to 0.1 stud); stop PoopSeconds;
--                                                idle at R; walk back to arrive at the eat point at Cycle exactly.
--                                                Cached: the 3 newest cycles per (seed, slot). nil for junk.
--   HomeRoam.At(seed, slot, epoch, now) -> x, z, state, dirX, dirZ   state "Settle" (now < epoch: on its bed, walking
--                                                to the bowl in the last seconds) | "Eat" | "Walk" | "Poop" | "Idle"
--   HomeRoam.PoopTime(seed, slot, epoch, cycle) -> epoch + cycle x Cycle + Plan(seed, slot, cycle).PoopAt
--   HomeRoam.BedPoint(slot) -> x, z              the bed centre (nil for junk)
--   HomeRoam.EatPoint(slot) -> x, z              the bowl centre + EatRing studs at (slot - 1) x 30 degrees
-- RoamSeed = (OwnerUserId % 2147483646) + 1; epochs are workspace:GetServerTimeNow() values on both sides.
-- Cost: Build ~400 nodes once (a few ms); a plan is one gradient walk + string pulling (~1 ms); At is O(path).

local HomeRoam = {}

HomeRoam.Version = 1
HomeRoam.Cycle = 24
HomeRoam.EatSeconds = 3
HomeRoam.PoopSeconds = 1.5
HomeRoam.MinSpeed = 4
HomeRoam.MaxSpeed = 9
HomeRoam.WalkBudget = 16.5 -- seconds of walking per cycle at most (Cycle - Eat - Poop - 3 of idle)
HomeRoam.MaxRoamCells = 36 -- the far point R lies 4..36 grid steps from the eat point
HomeRoam.MinRoamCells = 4
HomeRoam.PoopFrac = { 0.35, 0.7 }
HomeRoam.SettleSeconds = 20 -- a NEW placement: Epoch = now + SettleSeconds (TycoonService)
HomeRoam.SettleSpeed = 4 -- the walk from the bed to the bowl just before the epoch
HomeRoam.WelcomeClear = 3 -- poop points stay this far from the Welcome-back pile
HomeRoam.MaxSlots = 12
HomeRoam.MinIdle = 1 -- a plan whose walk leaves less idle than this picks another far point

local floor, sqrt, huge = math.floor, math.sqrt, math.huge
local MAX_CACHED_SEEDS = 64 -- plans of more homes than this: the cache starts over (a client sees <= 16 homes)

local G = nil -- the built graph (see build below)
local cache = {} -- [seed] = { [slot] = { cycles = {c1, c2, c3}, [cycle] = plan } }
local cachedSeeds = 0

local function finite(v)
	return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function point(x, z)
	return { x = x, z = z, x, z }
end

local function inRect(r, x, z)
	local pad = r.pad or 0
	return x >= r[1] - pad and x <= r[3] + pad and z >= r[2] - pad and z <= r[4] + pad
end

-- does the segment (ax, az) -> (bx, bz) touch the rect grown by its pad? (exact slab test, inclusive edges)
local function segHitsRect(r, ax, az, bx, bz)
	local pad = r.pad or 0
	local x0, z0, x1, z1 = r[1] - pad, r[2] - pad, r[3] + pad, r[4] + pad
	local t0, t1 = 0, 1
	local dx, dz = bx - ax, bz - az
	if dx == 0 then
		if ax < x0 or ax > x1 then
			return false
		end
	else
		local ta, tb = (x0 - ax) / dx, (x1 - ax) / dx
		if ta > tb then
			ta, tb = tb, ta
		end
		if ta > t0 then
			t0 = ta
		end
		if tb < t1 then
			t1 = tb
		end
		if t0 > t1 then
			return false
		end
	end
	if dz == 0 then
		if az < z0 or az > z1 then
			return false
		end
	else
		local ta, tb = (z0 - az) / dz, (z1 - az) / dz
		if ta > tb then
			ta, tb = tb, ta
		end
		if ta > t0 then
			t0 = ta
		end
		if tb < t1 then
			t1 = tb
		end
		if t0 > t1 then
			return false
		end
	end
	return true
end

-- the segment (ax, az) -> (bx, bz) is clear of every blocked rect (+ its pad)
local function clearSeg(ax, az, bx, bz)
	local blocked = G.blocked
	for i = 1, #blocked do
		if segHitsRect(blocked[i], ax, az, bx, bz) then
			return false
		end
	end
	return true
end

local function nearestNode(x, z, needField)
	local best, bd = nil, huge
	for id, n in ipairs(G.nodes) do
		if not needField or needField[id] then
			local d = (n.x - x) ^ 2 + (n.z - z) ^ 2
			if d < bd then
				best, bd = id, d
			end
		end
	end
	return best
end

local function defaultLayout()
	local ok, catalog = pcall(require, script.Parent.TycoonCatalog)
	if ok and type(catalog) == "table" and type(catalog.RoamLayout) == "function" then
		return catalog.RoamLayout()
	end
	return nil
end

function HomeRoam.Build(layout)
	if G and layout == nil then
		return #G.nodes
	end
	layout = layout or defaultLayout()
	if type(layout) ~= "table" or type(layout.Blocked) ~= "table" or type(layout.Bowl) ~= "table" then
		return 0
	end
	local half = layout.Half or 33
	local cell = layout.Cell or 2
	local nx = floor(2 * half / cell) + 1
	G = {
		blocked = layout.Blocked,
		welcome = layout.Welcome,
		bowl = { X = layout.Bowl.X, Z = layout.Bowl.Z, R = layout.Bowl.R },
		eatRing = layout.EatRing or 5,
		nodes = {},
		idOf = {},
		nbr = {},
		fields = {},
		eat = {},
		beds = {},
		bedNodes = {},
		settle = {},
	}
	cache, cachedSeeds = {}, 0
	local nodes, idOf = G.nodes, G.idOf
	for i = 1, nx do
		for j = 1, nx do
			local x, z = -half + (i - 1) * cell, -half + (j - 1) * cell
			local ok = z > -half + 2
			if ok then
				for _, r in ipairs(G.blocked) do
					if inRect(r, x, z) then
						ok = false
						break
					end
				end
			end
			if ok then
				nodes[#nodes + 1] = { i = i, j = j, x = x, z = z }
				idOf[i * 1000 + j] = #nodes
			end
		end
	end
	-- 8 neighbours in a fixed order (deterministic ties), each only when the segment between them is clear
	local D = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
	for id, n in ipairs(nodes) do
		local list = {}
		for _, d in ipairs(D) do
			local o = idOf[(n.i + d[1]) * 1000 + n.j + d[2]]
			if o and clearSeg(n.x, n.z, nodes[o].x, nodes[o].z) then
				list[#list + 1] = o
			end
		end
		G.nbr[id] = list
	end
	-- per slot: the eat point, the BFS field (grid steps to the eat node), the bed and its nearest reachable node
	local B = G.bowl
	for slot = 1, HomeRoam.MaxSlots do
		local a = math.rad((slot - 1) * 30)
		local ex, ez = B.X + math.cos(a) * G.eatRing, B.Z + math.sin(a) * G.eatRing
		G.eat[slot] = point(ex, ez)
		local goal = nearestNode(ex, ez)
		local dist = {}
		if goal then
			dist[goal] = 0
			local q, h = { goal }, 1
			while h <= #q do
				local c = q[h]
				h = h + 1
				for _, o in ipairs(G.nbr[c]) do
					if dist[o] == nil then
						dist[o] = dist[c] + 1
						q[#q + 1] = o
					end
				end
			end
		end
		G.fields[slot] = { dist = dist, goal = goal }
		local bed = type(layout.Beds) == "table" and layout.Beds[slot] or nil
		if type(bed) == "table" and finite(bed[1]) and finite(bed[2]) then
			G.beds[slot] = point(bed[1], bed[2])
			G.bedNodes[slot] = nearestNode(bed[1], bed[2], dist)
		else
			G.beds[slot] = point(ex, ez)
			G.bedNodes[slot] = goal
		end
	end
	return #nodes
end

local function ensureBuilt()
	if not G then
		HomeRoam.Build()
	end
	return G ~= nil and #G.nodes > 0
end

-- Park-Miller PRNG, exact in doubles (16807 x 2^31 < 2^53)
local function rng(seed)
	local s = seed % 2147483646 + 1
	return function()
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end

-- the gradient path from node `from` to the slot's eat node (fixed neighbour order: deterministic)
local function toBowl(slot, from)
	local f = G.fields[slot].dist
	local path, c = { from }, from
	while f[c] and f[c] > 0 do
		local nextId = nil
		for _, o in ipairs(G.nbr[c]) do
			if f[o] and f[o] < f[c] then
				nextId = o
				break
			end
		end
		if not nextId then
			break
		end
		c = nextId
		path[#path + 1] = c
	end
	return path
end

-- string pulling: keep only the corners (pure, deterministic)
local function pull(path)
	local nodes = G.nodes
	local out, a = { path[1] }, 1
	while a < #path do
		local b = #path
		while b > a + 1 and not clearSeg(nodes[path[a]].x, nodes[path[a]].z, nodes[path[b]].x, nodes[path[b]].z) do
			b = b - 1
		end
		out[#out + 1] = path[b]
		a = b
	end
	return out
end

local function polyLen(pts)
	local L = 0
	for k = 2, #pts do
		L = L + sqrt((pts[k].x - pts[k - 1].x) ^ 2 + (pts[k].z - pts[k - 1].z) ^ 2)
	end
	return L
end

-- the eat point first, then the path to node `target` (corners only)
local function outPath(slot, target)
	local back = pull(toBowl(slot, target)) -- target -> eat node
	local out = { G.eat[slot] }
	for k = #back, 1, -1 do
		local n = G.nodes[back[k]]
		out[#out + 1] = point(n.x, n.z)
	end
	return out
end

-- (x, z, dirX, dirZ) at arc length d along pts
local function along(pts, d)
	for k = 2, #pts do
		local ax, az, bx, bz = pts[k - 1].x, pts[k - 1].z, pts[k].x, pts[k].z
		local seg = sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		if d <= seg or k == #pts then
			local t = seg > 0 and math.max(0, math.min(1, d / seg)) or 0
			return ax + (bx - ax) * t, az + (bz - az) * t, bx - ax, bz - az
		end
		d = d - seg
	end
	return pts[1].x, pts[1].z, 0, 0
end

local function validSlot(slot)
	return type(slot) == "number" and slot == floor(slot) and slot >= 1 and slot <= HomeRoam.MaxSlots
end

local function validWhole(v)
	return finite(v) and v == floor(v)
end

local function cacheGet(seed, slot, cycle)
	local bySlot = cache[seed]
	local c = bySlot and bySlot[slot]
	return c and c[cycle]
end

local function cachePut(seed, slot, cycle, plan)
	local bySlot = cache[seed]
	if not bySlot then
		if cachedSeeds >= MAX_CACHED_SEEDS then
			cache, cachedSeeds = {}, 0
		end
		bySlot = {}
		cache[seed] = bySlot
		cachedSeeds = cachedSeeds + 1
	end
	local c = bySlot[slot]
	if not c then
		c = { cycles = {} }
		bySlot[slot] = c
	end
	local list = c.cycles
	list[#list + 1] = cycle
	c[cycle] = plan
	if #list > 3 then
		-- keep the 3 newest cycles (the highest numbers)
		local lowest, at = list[1], 1
		for i = 2, #list do
			if list[i] < lowest then
				lowest, at = list[i], i
			end
		end
		table.remove(list, at)
		c[lowest] = nil
	end
end

function HomeRoam.Plan(seed, slot, cycle)
	if not validWhole(seed) or not validSlot(slot) or not validWhole(cycle) or cycle < 0 or not ensureBuilt() then
		return nil
	end
	local hit = cacheGet(seed, slot, cycle)
	if hit then
		return hit
	end
	local r = rng(seed * 7919 + slot * 104729 + cycle * 1299709)
	local f = G.fields[slot].dist
	local nodes = G.nodes
	local eatS, poopS, cycleS = HomeRoam.EatSeconds, HomeRoam.PoopSeconds, HomeRoam.Cycle
	local out, L
	for _ = 1, 8 do
		local id = 1 + floor(r() * #nodes)
		local steps = f[id]
		if steps and steps >= HomeRoam.MinRoamCells and steps <= HomeRoam.MaxRoamCells then
			local pts = outPath(slot, id)
			local len = polyLen(pts)
			local speed = math.min(HomeRoam.MaxSpeed, math.max(HomeRoam.MinSpeed, 2 * len / HomeRoam.WalkBudget))
			if cycleS - eatS - poopS - 2 * len / speed >= HomeRoam.MinIdle then
				out, L = pts, len
				break
			end
		end
	end
	if not out then
		out = outPath(slot, G.bedNodes[slot] or G.fields[slot].goal)
		L = polyLen(out)
	end
	-- the poop point: ON the walked polyline at arc fraction PoopFrac from the bowl; moved back toward the bowl while
	-- it is within WelcomeClear studs of the Welcome-back pile
	local frac = HomeRoam.PoopFrac[1] + r() * (HomeRoam.PoopFrac[2] - HomeRoam.PoopFrac[1])
	local W = G.welcome
	local clear2 = HomeRoam.WelcomeClear * HomeRoam.WelcomeClear
	local px, pz, ps = out[1].x, out[1].z, 0
	for _ = 1, 6 do
		ps = math.min(L, math.max(math.min(L, G.eatRing * 0.5), frac * L))
		px, pz = along(out, ps)
		if not (W and (px - W[1]) ^ 2 + (pz - W[2]) ^ 2 < clear2) then
			break
		end
		frac = frac * 0.7
	end
	px, pz = floor(px * 10 + 0.5) / 10, floor(pz * 10 + 0.5) / 10
	local speed = math.min(HomeRoam.MaxSpeed, math.max(HomeRoam.MinSpeed, 2 * L / HomeRoam.WalkBudget))
	local plan = {
		Out = out,
		Poop = point(px, pz),
		Speed = speed,
		OutLen = L,
		PoopDist = ps,
		PoopAt = eatS + ps / speed + poopS / 2,
		Idle = math.max(0, cycleS - eatS - poopS - 2 * L / speed),
	}
	cachePut(seed, slot, cycle, plan)
	return plan
end

-- the settle walk of a slot: bed -> its node -> ... -> eat point (built once per slot)
local function settlePath(slot)
	local s = G.settle[slot]
	if not s then
		local pts = { G.beds[slot] }
		local node = G.bedNodes[slot]
		if node then
			local back = pull(toBowl(slot, node))
			for k = 1, #back do
				local n = G.nodes[back[k]]
				pts[#pts + 1] = point(n.x, n.z)
			end
		end
		pts[#pts + 1] = G.eat[slot]
		s = { pts = pts, len = polyLen(pts) }
		G.settle[slot] = s
	end
	return s
end

function HomeRoam.At(seed, slot, epoch, now)
	if not validSlot(slot) or not finite(epoch) or not finite(now) or not ensureBuilt() then
		return 0, 0, "Settle", 0, 1
	end
	local t = now - epoch
	if t < 0 then
		-- on its bed; in the last seconds before the epoch it walks to its eat point (arrives at the epoch)
		local s = settlePath(slot)
		local left = -t * HomeRoam.SettleSpeed
		if left >= s.len then
			local b = G.beds[slot]
			return b.x, b.z, "Settle", 0, 0
		end
		local x, z, dx, dz = along(s.pts, s.len - left)
		return x, z, "Settle", dx, dz
	end
	local cycle = floor(t / HomeRoam.Cycle)
	local u = t - cycle * HomeRoam.Cycle
	local p = HomeRoam.Plan(seed, slot, cycle)
	if not p then
		local b = G.beds[slot]
		return b.x, b.z, "Settle", 0, 0
	end
	local o1 = p.Out[1]
	if u < HomeRoam.EatSeconds then
		return o1.x, o1.z, "Eat", G.bowl.X - o1.x, G.bowl.Z - o1.z
	end
	local walkOut = p.OutLen / p.Speed
	local poopStart = p.PoopAt - HomeRoam.PoopSeconds / 2
	local d
	if u < poopStart then
		d = (u - HomeRoam.EatSeconds) * p.Speed
	elseif u < poopStart + HomeRoam.PoopSeconds then
		local _, _, dx, dz = along(p.Out, p.PoopDist)
		return p.Poop.x, p.Poop.z, "Poop", dx, dz
	else
		local w = u - HomeRoam.PoopSeconds - HomeRoam.EatSeconds
		if w < walkOut then
			d = w * p.Speed
		else
			local back = HomeRoam.Cycle - u
			if back > walkOut then
				local e = p.Out[#p.Out]
				return e.x, e.z, "Idle", 0, 0
			end
			local x, z, dx, dz = along(p.Out, back * p.Speed)
			return x, z, "Walk", -dx, -dz
		end
	end
	local x, z, dx, dz = along(p.Out, d)
	return x, z, "Walk", dx, dz
end

function HomeRoam.PoopTime(seed, slot, epoch, cycle)
	local p = HomeRoam.Plan(seed, slot, cycle)
	if not p or not finite(epoch) then
		return nil
	end
	return epoch + cycle * HomeRoam.Cycle + p.PoopAt
end

function HomeRoam.BedPoint(slot)
	if not validSlot(slot) or not ensureBuilt() then
		return nil
	end
	local b = G.beds[slot]
	return b.x, b.z
end

function HomeRoam.EatPoint(slot)
	if not validSlot(slot) or not ensureBuilt() then
		return nil
	end
	local e = G.eat[slot]
	return e.x, e.z
end

-- tests / tools: the node count and the cached cycles of (seed, slot)
function HomeRoam.NodeCount()
	if not ensureBuilt() then
		return 0
	end
	return #G.nodes
end

function HomeRoam.CachedCycles(seed, slot)
	local bySlot = cache[seed]
	local c = bySlot and bySlot[slot]
	local out = {}
	if c then
		for i, v in ipairs(c.cycles) do
			out[i] = v
		end
		table.sort(out)
	end
	return out
end

return HomeRoam
