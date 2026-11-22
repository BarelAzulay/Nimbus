-- save_roundtrip.lua: the in-world half of tools/save_roundtrip.py (release step 1, gate 2: the save round trip).
-- tools/save_roundtrip.py loads this file into every Lua world it boots: worlds of MAIN's code (git archive of the
-- pinned commit) and worlds of this branch's code, all on ONE fake DataStore that lives in Python. Nothing here knows
-- which code it runs beside: it only uses what both versions have (Main.server.lua, DataService, the shared catalogs).
-- No real DataStore, no network: Mock.DataStore.Data is replaced by a proxy onto the Python store.
-- Plain Lua 5.1 syntax only.

local RT = {}
_G.RT = RT

local Players = game:GetService("Players")
local cursor = { Errors = 0, Output = 0 }

local function DS()
	return require(Mock.GetPath(ROOTS.server .. "/Services/DataService"))
end
local function shared(name)
	local inst = Mock.GetPath(ROOTS.shared .. "/" .. name)
	if not inst then
		return nil
	end
	local ok, m = pcall(require, inst)
	return ok and m or nil
end
RT.DS = DS
RT.shared = shared

-- The ONE shared store: every read and write of the mock DataStore goes to Python (pyGet(full) -> a fresh value or
-- nil, pySet(full, value)). The mock deep-copies on both sides of this, as a real DataStore serialises.
function RT.installStore(pyGet, pySet)
	Mock.DataStore.Data = setmetatable({}, {
		__index = function(_, k)
			return pyGet(k)
		end,
		__newindex = function(_, k, v)
			pySet(k, v)
		end,
	})
end

function RT.setClock(seconds)
	Mock.Clock.now = seconds
end
function RT.now()
	return Mock.Clock.now
end
function RT.unix()
	return os.time()
end
function RT.advance(seconds)
	Mock.Advance(seconds)
end

-- boots the real server (Main.server.lua) -> true when it printed its ready line
function RT.boot()
	local main = Mock.GetPath(ROOTS.server .. "/Main")
	if not main then
		return false, "no server/Main"
	end
	local before = #Mock.Output
	Mock.RunScript(main)
	Mock.Advance(2)
	for i = before + 1, #Mock.Output do
		if Mock.Output[i].text:find("[NimbusClimb] ready", 1, true) then
			return true
		end
	end
	return false, "Main.server.lua did not print '[NimbusClimb] ready'"
end

-- this server's lock id (branch code only; main has no session lock)
function RT.setServerId(id)
	local D = DS()
	if type(D._SetServerIdForTest) == "function" then
		return D._SetServerIdForTest(id)
	end
	return false
end

function RT.player(uid)
	return Players:GetPlayerByUserId(uid)
end
function RT.join(uid, name)
	return Mock.AddPlayer(name, uid) ~= nil
end
function RT.leave(uid)
	local p = RT.player(uid)
	if p then
		Mock.RemovePlayer(p)
		return true
	end
	return false
end
function RT.shutdown(maxSeconds)
	Mock.Shutdown(maxSeconds or 30)
end

-- { Here, Loaded, Provisional, Owns, Waiting, Tokens, Cash, Gems }: what this server knows of the player's save
function RT.status(uid)
	local D = DS()
	local p = RT.player(uid)
	local out = { Here = p ~= nil, Loaded = false, Provisional = false, Owns = false, Waiting = false, HasLock = type(D.OwnsSave) == "function" }
	if not p then
		return out
	end
	out.Loaded = D.GetProfile(p) ~= nil
	if type(D.IsProvisional) == "function" then
		out.Provisional = D.IsProvisional(p) == true
	end
	if type(D.OwnsSave) == "function" then
		out.Owns = D.OwnsSave(p) == true
	else
		out.Owns = out.Loaded and not out.Provisional -- main: no lock, a loaded real profile is "owned"
	end
	local Config = shared("Config")
	local attr = Config and Config.Attr and Config.Attr.SaveWaiting
	if attr then
		out.Waiting = p:GetAttribute(attr) == true
	end
	if out.Loaded then
		out.Tokens = D.GetTokens(p)
		out.Cash = type(D.GetCash) == "function" and D.GetCash(p) or nil
		out.Gems = type(D.GetGems) == "function" and D.GetGems(p) or nil
	end
	return out
end

-- a value as a flat map: path -> "n:<%.17g>" | "s:<text>" | "b:true" | "{}" (field-by-field compares in Python)
local function flat(v, path, out, depth)
	local t = type(v)
	if t == "table" then
		if depth > 14 then
			out[path] = "!deep"
			return
		end
		local n = 0
		for k, x in pairs(v) do
			n = n + 1
			local key = type(k) == "number" and ("[" .. string.format("%.17g", k) .. "]") or ("." .. tostring(k))
			flat(x, path .. key, out, depth + 1)
		end
		if n == 0 then
			out[path] = "{}"
		end
	elseif t == "number" then
		out[path] = "n:" .. string.format("%.17g", v)
	elseif t == "boolean" then
		out[path] = "b:" .. tostring(v)
	elseif t == "string" then
		out[path] = "s:" .. v
	else
		out[path] = "!" .. t
	end
end
function RT.flat(v)
	local out = {}
	flat(v, "", out, 0)
	return out
end

-- the player's LIVE profile, flat (nil until it is loaded)
function RT.flatProfile(uid)
	local p = RT.player(uid)
	local prof = p and DS().GetProfile(p)
	if not prof then
		return nil
	end
	return RT.flat(prof)
end

-- runs a Lua chunk given as text with one argument: { DS, player, uid, Config, shared, Mock, RT }; its return value
-- (a plain value or table) goes back to Python
function RT.exec(src, uid)
	local load_ = loadstring or load
	local fn, err = load_(src, "=save_roundtrip.py")
	if not fn then
		error("RT.exec: " .. tostring(err), 0)
	end
	return fn({ DS = DS(), player = uid and RT.player(uid) or nil, uid = uid, Config = shared("Config"), shared = shared, Mock = Mock, RT = RT })
end

-- script errors and warn() lines since the last call (a load must raise neither)
function RT.problems()
	local out = {}
	for i = cursor.Errors + 1, #Mock.Errors do
		local e = Mock.Errors[i]
		out[#out + 1] = "error: " .. tostring(e.msg)
	end
	cursor.Errors = #Mock.Errors
	for i = cursor.Output + 1, #Mock.Output do
		local o = Mock.Output[i]
		if o.kind == "warn" then
			out[#out + 1] = "warn: " .. tostring(o.text)
		end
	end
	cursor.Output = #Mock.Output
	return out
end

----------------------------------------------------------------------------------------------------
-- The raw seed of the MAXED player (it is only the INPUT: the driver lets main's own code load it, then save it, and
-- that saved record is the fixture). Built from this world's own catalogs, so every id is one this code knows:
-- every pet at a full stack, tier copies, hybrids, every level at the cap, a full Home, teams, the battle record,
-- training ranks, the Ring, the Dungeon, berries, settings, 100 gem receipts, every migration marker, big numbers.
----------------------------------------------------------------------------------------------------
function RT.maxedSeed()
	local Config = shared("Config")
	local PetCatalog = shared("PetCatalog")
	local Tycoon = shared("TycoonCatalog")
	local now = os.time()
	local ids = {}
	for _, r in ipairs(Config.Rarities) do
		for _, def in ipairs(PetCatalog.ListByRarity(r.Id, true)) do
			ids[#ids + 1] = def.Id
		end
	end
	table.sort(ids)
	local maxStack = (Config.Pets and Config.Pets.MaxPerStack) or 99
	local maxLevel = (Tycoon and Tycoon.MaxPetLevel) or 100
	local rec = {
		Version = 2,
		Tokens = 987654321,
		Cash = 987654321012345,
		Gems = 876543210,
		Berries = 7654321,
		SpotIndex = 3,
		Pets = {}, Tiers = {}, Hybrids = {}, PetLevels = {}, Discovered = {}, IndexClaimed = {}, PetGrowth = {},
		Items = { heal_cloud = 5, shield_bubble = 4, phoenix_feather = 3 },
		Stats = { Matches = 54321, Wins = 12345, TokensEarned = 876543210, Spins = 43210, BestTimes = {} },
		Tutorial = { Step = 99, Done = true, Gifted = true },
		Food = {},
		GemReceipts = {},
		Migrations = { P4 = true, P5Dungeon = true, P5Home = true, P5MouseLock = true, B2GardenSolo = true, B3ItemsRefund = true, B4TeamFollow = true },
		Ring = { Best = 88, Runs = 321 },
		Dungeon = { Best = 37, Cleared = {}, Runs = 400, Clears = 250 },
		Settings = { Music = 3, Sfx = 7, Gfx = "Low", Shake = false, SeenNotes = 12, MouseLock = true },
	}
	for i, id in ipairs(ids) do
		rec.Pets[id] = maxStack
		rec.Discovered[id] = true
		rec.PetLevels[id] = { Level = maxLevel, Xp = 1000 + i }
		rec.PetGrowth[id] = { Evo = 2, Speed = 10, Physique = 10, Ability = 10, Defense = 10 }
		if i % 2 == 0 then
			rec.Tiers[id] = { Golden = 3 + i % 5, Rainbow = 1 + i % 3 }
			rec.PetLevels[id .. "@Golden"] = { Level = maxLevel - 1, Xp = 500 + i }
			rec.PetLevels[id .. "@Rainbow"] = { Level = maxLevel - 2, Xp = 250 + i }
			rec.PetGrowth[id .. "@Golden"] = { Evo = 1, Speed = 9, Physique = 8, Ability = 7, Defense = 6 }
		end
	end
	for i = 1, 12 do
		local a, b = ids[(i * 3) % #ids + 1], ids[(i * 7 + 2) % #ids + 1]
		local uid = "max" .. tostring(i)
		rec.Hybrids[uid] = { Body = a, Style = b, Name = "Mix " .. tostring(i), Rarity = "Legendary", Tier = (i % 3 == 0) and "Golden" or "Normal",
			Elements = { "Storm", "Sky" } }
		rec.PetLevels["hyb:" .. uid] = { Level = 50 + i, Xp = 10 * i }
		rec.PetGrowth["hyb:" .. uid] = { Evo = 1, Speed = i % 11, Physique = 2, Ability = 3, Defense = 4 }
	end
	for _, d in ipairs(Config.Difficulties) do
		rec.Stats.BestTimes[d.Id] = 31.25 + #d.Id
	end
	for _, g in ipairs(PetCatalog.IndexGroups()) do
		rec.IndexClaimed[g.Id or g.id or tostring(g)] = true
	end
	for i = 1, 37 do
		rec.Dungeon.Cleared[i] = true
	end
	for i = 1, 100 do
		rec.GemReceipts["maxed-receipt-" .. tostring(i)] = now - 86400 - i * 60
	end
	local stations = {}
	for _, id in ipairs((Tycoon and Tycoon.Order) or {}) do
		stations[id] = 3
	end
	rec.Home = {
		Level = 40, Prestige = 4, Stations = stations, CollectorCash = 123456, LastSeen = now - 3600,
		Garden = { ids[1], ids[2], ids[3], ids[4] }, Gym = {},
	}
	rec.Equipped = { ids[5], ids[6], ids[7] }
	rec.Teams = { Active = 2, Presets = { { ids[8], ids[9], ids[10] }, { ids[5], ids[6], ids[7] }, { "hyb:max1", ids[11], ids[12] } } }
	local event = PetCatalog.EventPets and PetCatalog.EventPets() or {}
	local eventPets = {}
	for _, def in ipairs(event) do
		eventPets[type(def) == "table" and def.Id or def] = true
	end
	rec.Battle = { Trophies = 54321, TrialBest = 20, TrialCleared = {}, Raids = 77, RaidBestDamage = 9999999, PvPWins = 432, PvPLosses = 123, EventPets = eventPets }
	for i = 1, 20 do
		rec.Battle.TrialCleared[i] = true
	end
	-- one training job still running (a pet that is on no team and in no bed)
	rec.PetGrowth[ids[13]] = { Evo = 1, Speed = 4, Physique = 4, Ability = 4, Defense = 4,
		Job = { Stat = "Speed", Ends = now + 1800, Rank = 5, Slot = 1, From = "Free", Paid = 4200 } }
	return rec, #ids
end

return RT
