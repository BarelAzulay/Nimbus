-- smoke_redo_hybrid.lua: hybrid move data (docs/superpowers/specs/2026-11-06-window-redo-design.md 5.6 + 6; plan
-- docs/superpowers/plans/2026-11-06-window-redo.md Task 1): a hybrid record's optional SpecialFrom = "Style" makes the Style
-- parent give the special (absent / anything else = the Body's, today's rule), the record's Elements order gives the first
-- element (the normal attack); the def, both save cleaners and the client snapshot keep it. Loaded by tools/smoke.py in the
-- server world (pure + booted) and the client world (ARGS.context picks the half):
--   hybrid_moves_def           (pure) PetKeys.DefOf of a hybrid: SpecialFrom = "Style" -> the Style's special; the record's element
--                              order -> Element; an old record -> today's def exactly; junk SpecialFrom -> Body; the def cache keeps
--                              two records of one uid apart; a missing parent still builds a def with a special; PetKeys.CleanHybrid
--                              keeps exactly "Style" and never counts it toward the 8 extras
--   hybrid_moves_battle        (pure) BattleSim units of an "SS" hybrid (Bolt + Static Storm, Storm first): unitInfo at Evo 0, the
--                              generic Storm form names and the Storm element forms at Evo 1 and 2, FormDpsOf reads the chosen kind
--                              and element; the old "BB" record still gives Flare + Leaf Pounce
--   hybrid_moves_save          (booted) a stored profile with an SS, a junk ("Body") and an old record: the load keeps exactly
--                              "Style", the save keeps it (and drops junk on a changed record), the old record is untouched, the
--                              8 extras + SpecialFrom survive, the ProfileSync snapshot carries it, a second server's save keeps it
--   hybrid_moves_evolve        (booted) the SS hybrid at level 20 evolves through the PetCare remote; its def keeps Static Storm
--   client_hybrid_moves_state  (client) a ProfileSync snapshot through State: State.Hybrids() keeps SpecialFrom = "Style" and
--                              State.DefOf gives Static Storm; junk ("style") and no field give Leaf Pounce
-- Fixture pets (every hybrid test of the plan): Body maple_fox (Uncommon, Flame, "Leaf Pounce" kind Pounce), Style storm_tabby
-- (Rare, Storm, "Static Storm" kind Storm). Element attacks: Flame "Flare", Storm "Bolt".
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local fmt = string.format
local abs = math.abs

local BODY, STYLE = "maple_fox", "storm_tabby"

local function copy(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in pairs(t) do
		out[k] = copy(v)
	end
	return out
end

local function deepEqual(a, b)
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function keysText(t)
	local list = {}
	for k, v in pairs(type(t) == "table" and t or {}) do
		list[#list + 1] = tostring(k) .. "=" .. (type(v) == "table" and ("{" .. table.concat(v, "+") .. "}") or tostring(v))
	end
	table.sort(list)
	return table.concat(list, " ")
end

-- the SS record ("normal attack and special both from Style"): Storm first, the Style's special
local function ssRecord(extra)
	local rec = { Body = BODY, Style = STYLE, Elements = { "Storm", "Flame" }, SpecialFrom = "Style", Rarity = "Rare", Tier = "Normal" }
	for k, v in pairs(extra or {}) do
		rec[k] = v
	end
	return rec
end

-- an old record (today's FusionService: Body's element first, no SpecialFrom)
local function oldRecord(extra)
	local rec = { Body = BODY, Style = STYLE, Elements = { "Flame", "Storm" }, Rarity = "Rare", Tier = "Normal" }
	for k, v in pairs(extra or {}) do
		rec[k] = v
	end
	return rec
end

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K

	local function req(path)
		local inst = K.moduleInstance(path)
		if not inst then
			return nil
		end
		local ok, m = pcall(require, inst)
		if ok and type(m) == "table" then
			return m
		end
		return nil
	end

	------------------------------------------------------------------------------------------------
	-- hybrid_moves_def (pure)
	------------------------------------------------------------------------------------------------
	S.hybrid_moves_def = guarded("hybrid_moves_def", function()
		local PK, PC = req("shared/PetKeys"), req("shared/PetCatalog")
		if not T.check(PK ~= nil and PC ~= nil and type(PK.DefOf) == "function" and type(PK.CleanHybrid) == "function", "hybrid moves def: PetKeys and PetCatalog load") then
			return
		end
		local bodySpecial, styleSpecial = PC.Get(BODY).Special, PC.Get(STYLE).Special
		T.check(bodySpecial.Name == "Leaf Pounce" and bodySpecial.Kind == "Pounce" and styleSpecial.Name == "Static Storm" and styleSpecial.Kind == "Storm",
			"hybrid moves def: (fixture) Maple Fox has Leaf Pounce (Pounce), Storm Tabby Static Storm (Storm)")
		local function defOf(uid, rec)
			return PK.DefOf("hyb:" .. uid, { Hybrids = { [uid] = rec } })
		end

		-- SpecialFrom = "Style": the Style's special, the record's element order
		local def = defOf("hmd1", { Body = BODY, Style = STYLE, Elements = { "Flame", "Storm" }, SpecialFrom = "Style", Rarity = "Rare", Tier = "Normal", Seed = 7 })
		T.check(def ~= nil and type(def.Special) == "table" and def.Special.Name == "Static Storm" and def.Special.Kind == "Storm",
			"hybrid moves def: SpecialFrom = 'Style' -> the Style's special (Static Storm, kind Storm)", def and def.Special and (def.Special.Name .. " / " .. def.Special.Kind) or "no def")
		T.check(def ~= nil and def.Element == "Flame" and def.Elements[1] == "Flame" and def.Elements[2] == "Storm",
			"hybrid moves def: ...and the record's element order (Flame first)", def and table.concat(def.Elements, "+") or "no def")
		T.check(def ~= nil and def.Special ~= styleSpecial and def.Special.Power == styleSpecial.Power and def.Special.Id == styleSpecial.Id,
			"hybrid moves def: ...the special is a copy of the Style's (never the catalog's own table)")

		-- Storm first with no SpecialFrom: the Body's special, Storm as the first element
		def = defOf("hmd2", { Body = BODY, Style = STYLE, Elements = { "Storm", "Flame" }, Rarity = "Rare", Tier = "Normal" })
		T.check(def ~= nil and def.Special.Name == "Leaf Pounce" and def.Element == "Storm" and def.Elements[2] == "Flame",
			"hybrid moves def: Elements { Storm, Flame } and no SpecialFrom -> Leaf Pounce, Element Storm", def and (def.Special.Name .. " / " .. tostring(def.Element)) or "no def")

		-- an old record reads exactly as today
		def = defOf("hmd3", { Body = BODY, Style = STYLE, Elements = { "Flame", "Storm" }, Rarity = "Rare", Tier = "Normal" })
		local same = def ~= nil and type(def.Special) == "table"
		for _, field in ipairs({ "Id", "Name", "Kind", "Power", "Color" }) do
			same = same and def.Special[field] == bodySpecial[field]
		end
		T.check(same, "hybrid moves def: an old record (no SpecialFrom) -> the Body's special field by field (Id, Name, Kind, Power, Color)")
		T.check(def ~= nil and #def.Elements == 2 and def.Elements[1] == "Flame" and def.Elements[2] == "Storm" and def.Element == "Flame",
			"hybrid moves def: ...Elements { Flame, Storm }", def and table.concat(def.Elements, "+") or "no def")
		T.check(def ~= nil and def.Name == PK.BlendName(PC.Get(BODY).Name, PC.Get(STYLE).Name), "hybrid moves def: ...the blended name when the record names none",
			def and tostring(def.Name) .. " vs " .. tostring(PK.BlendName(PC.Get(BODY).Name, PC.Get(STYLE).Name)) or "no def")
		local named = defOf("hmd3n", oldRecord({ Name = "Sparky" }))
		T.check(named ~= nil and named.Name == "Sparky" and named.Special.Name == "Leaf Pounce", "hybrid moves def: ...the record's own name when it has one")

		-- junk SpecialFrom = the Body's special
		for i, junk in ipairs({ "style", "Body", 5, true }) do
			def = defOf("hmdj" .. i, oldRecord({ SpecialFrom = junk }))
			T.check(def ~= nil and def.Special.Name == "Leaf Pounce", "hybrid moves def: SpecialFrom = " .. fmt("%q", tostring(junk)) .. " (" .. type(junk) .. ") -> Leaf Pounce (the Body's)",
				def and def.Special.Name or "no def")
		end

		-- the cache keeps two records of one uid apart
		local first = PK.DefOf("hyb:hmdc", { Hybrids = { hmdc = oldRecord({ SpecialFrom = "Style", Seed = 9 }) } })
		local second = PK.DefOf("hyb:hmdc", { Hybrids = { hmdc = oldRecord({ Seed = 9 }) } })
		T.check(first ~= nil and second ~= nil and first.Special.Name == "Static Storm" and second.Special.Name == "Leaf Pounce" and first ~= second,
			"hybrid moves def: the same uid and key, SpecialFrom 'Style' then absent -> two defs (the second is not the first's cached def)",
			(first and first.Special.Name or "nil") .. " / " .. (second and second.Special.Name or "nil"))
		local again = PK.DefOf("hyb:hmdc", { Hybrids = { hmdc = oldRecord({ SpecialFrom = "Style", Seed = 9 }) } })
		T.check(again ~= nil and again.Special.Name == "Static Storm", "hybrid moves def: ...and back to 'Style' gives the Style's special again")

		-- a missing parent (Review Focus 4): the def still builds with a special
		local okMiss, missStyle = pcall(defOf, "hmdm1", { Body = BODY, Style = "no_such_pet", Elements = { "Flame" }, SpecialFrom = "Style", Rarity = "Rare", Tier = "Normal" })
		T.check(okMiss and missStyle ~= nil and type(missStyle.Special) == "table" and missStyle.Special.Name == "Leaf Pounce",
			"hybrid moves def: Style gone + SpecialFrom 'Style' -> a def with the Body's special (no error)", okMiss and (missStyle and tostring(missStyle.Special and missStyle.Special.Name) or "no def") or tostring(missStyle))
		local okMiss2, missBody = pcall(defOf, "hmdm2", { Body = "no_such_pet", Style = STYLE, Elements = { "Storm" }, SpecialFrom = "Style", Rarity = "Rare", Tier = "Normal" })
		T.check(okMiss2 and missBody ~= nil and type(missBody.Special) == "table" and missBody.Special.Name == "Static Storm",
			"hybrid moves def: Body gone + SpecialFrom 'Style' -> a def with Static Storm (no error)", okMiss2 and (missBody and tostring(missBody.Special and missBody.Special.Name) or "no def") or tostring(missBody))

		-- PetKeys.CleanHybrid
		local clean = PK.CleanHybrid(ssRecord())
		T.check(clean ~= nil and clean.SpecialFrom == "Style" and clean.Elements[1] == "Storm" and clean.Elements[2] == "Flame",
			"hybrid moves def: CleanHybrid keeps SpecialFrom = 'Style' and the element order", clean and keysText(clean) or "nil")
		for _, junk in ipairs({ "style", "Body", 5 }) do
			clean = PK.CleanHybrid(oldRecord({ SpecialFrom = junk }))
			T.check(clean ~= nil and clean.SpecialFrom == nil, "hybrid moves def: CleanHybrid drops SpecialFrom = " .. fmt("%q", tostring(junk)), clean and keysText(clean) or "nil")
		end
		local raw = oldRecord({ SpecialFrom = "Style" })
		for i = 1, 8 do
			raw["X" .. i] = "v" .. i
		end
		clean = PK.CleanHybrid(raw)
		local extras = 0
		for i = 1, 8 do
			if clean and clean["X" .. i] == "v" .. i then
				extras = extras + 1
			end
		end
		T.check(clean ~= nil and extras == 8 and clean.SpecialFrom == "Style", "hybrid moves def: CleanHybrid keeps 8 unknown extras AND SpecialFrom (it is a known field, not an extra)",
			fmt("%d extras, SpecialFrom %s", extras, tostring(clean and clean.SpecialFrom)))
	end)

	------------------------------------------------------------------------------------------------
	-- hybrid_moves_battle (pure)
	------------------------------------------------------------------------------------------------
	S.hybrid_moves_battle = guarded("hybrid_moves_battle", function()
		local PK, PC, BC, BS = req("shared/PetKeys"), req("shared/PetCatalog"), req("shared/BattleCatalog"), req("shared/BattleSim")
		if not T.check(PK ~= nil and PC ~= nil and BC ~= nil and BS ~= nil and type(BS.new) == "function", "hybrid moves battle: PetKeys, PetCatalog, BattleCatalog and BattleSim load") then
			return
		end
		-- my unit's static info in a Duel against one standing bear (the smoke_evo_sim.lua field() shape)
		local function infoFor(key, def, level, evo)
			local teams = {
				{ Owner = 1, Side = 1, Pets = { { Def = def, Key = key, Level = level, Evo = evo, Slot = 1 } } },
				{ Owner = "npc", Side = 2, Npc = true, Specials = false, Pets = { { Key = "biscuit_bear", Level = 18, NoSpecial = true, Slot = 1 } } },
			}
			local b = BS.new({ Mode = "Duel", Seed = 7, Zone = { X = 160, Z = 160 }, TimeLimit = 300, Teams = teams })
			if not b then
				return nil
			end
			for _, info in ipairs(b:StaticUnits()) do
				if info.side == 1 then
					return info
				end
			end
			return nil
		end
		local function hybrid(uid, rec)
			local key = "hyb:" .. uid
			return key, PK.DefOf(key, { Pets = {}, Tiers = {}, Hybrids = { [uid] = rec } })
		end

		local key, def = hybrid("hm1", ssRecord())
		if not T.check(def ~= nil and def.IsHybrid == true, "hybrid moves battle: (setup) the SS hybrid def builds") then
			return
		end
		local info = infoFor(key, def, 30, 0)
		T.check(info ~= nil and info.elementAttack ~= nil and info.elementAttack.Name == "Bolt" and info.special ~= nil and info.special.Name == "Static Storm" and info.element == "Storm",
			"hybrid moves battle: SS at Evo 0 -> Bolt, Static Storm, element Storm",
			info and fmt("%s / %s / %s", tostring(info.elementAttack and info.elementAttack.Name), tostring(info.special and info.special.Name), tostring(info.element)) or "no unit")

		-- stage 1: the Storm kind's generic form name, the Storm element's form
		info = infoFor(key, def, 30, 1)
		T.check(info ~= nil and info.special ~= nil and info.special.Form == 1 and info.special.Name == BC.FormNameOf(key, "Storm", 1) and info.special.Base == "Static Storm"
			and info.elementAttack.Name == BC.ElementFormOf("Storm", 1).Name and BC.FormOf("Storm", 1) ~= nil,
			"hybrid moves battle: SS at Evo 1 -> the generic Storm form name and Storm's element form (" .. tostring(BC.FormNameOf(key, "Storm", 1)) .. ", " .. tostring(BC.ElementFormOf("Storm", 1).Name) .. ")",
			info and fmt("%s / %s", tostring(info.special and info.special.Name), tostring(info.elementAttack and info.elementAttack.Name)) or "no unit")
		-- a Rare hybrid evolves once: a stored 2 is its top form (1)
		info = infoFor(key, def, 60, 2)
		T.check(info ~= nil and info.special ~= nil and info.special.Form == 1 and info.special.Name == BC.FormNameOf(key, "Storm", 1),
			"hybrid moves battle: the Rare SS at a stored Evo 2 is at its top form (1)", info and fmt("form %s %s", tostring(info.special and info.special.Form), tostring(info.special and info.special.Name)) or "no unit")
		-- stage 2: an Epic record (evolves twice) gets the stage-2 names
		local key2, def2 = hybrid("hm2", ssRecord({ Rarity = "Epic" }))
		info = def2 and infoFor(key2, def2, 60, 2)
		T.check(info ~= nil and info.special ~= nil and info.special.Form == 2 and info.special.Name == BC.FormNameOf(key2, "Storm", 2)
			and info.elementAttack.Name == BC.ElementFormOf("Storm", 2).Name and BC.FormOf("Storm", 2) ~= nil,
			"hybrid moves battle: an Epic SS at Evo 2 -> the generic Storm stage-2 name and Storm's stage-2 element form (" .. tostring(BC.FormNameOf(key2, "Storm", 2)) .. ", " .. tostring(BC.ElementFormOf("Storm", 2).Name) .. ")",
			info and fmt("form %s %s / %s", tostring(info.special and info.special.Form), tostring(info.special and info.special.Name), tostring(info.elementAttack and info.elementAttack.Name)) or "no unit")

		-- what a boss's HP counts: the chosen kind (Storm) and element (Storm)
		local dps = BC.FormDpsOf(def, { Evo = 1, Elements = def.Elements })
		local want = BC.FormDps[1] * (BC.FormDps.Storm or 1) * (BC.FormDps.Storm or 1)
		T.check(type(dps) == "number" and abs(dps - want) < 1e-9, "hybrid moves battle: FormDpsOf reads the chosen kind and element (x" .. fmt("%.4f", want) .. ")", tostring(dps))

		-- the old BB record (regression)
		local keyOld, defOld = hybrid("hm3", oldRecord())
		info = defOld and infoFor(keyOld, defOld, 30, 0)
		T.check(info ~= nil and info.elementAttack ~= nil and info.elementAttack.Name == "Flare" and info.special ~= nil and info.special.Name == "Leaf Pounce" and info.element == "Flame",
			"hybrid moves battle: the old BB record -> Flare, Leaf Pounce, element Flame",
			info and fmt("%s / %s / %s", tostring(info.elementAttack and info.elementAttack.Name), tostring(info.special and info.special.Name), tostring(info.element)) or "no unit")
	end)

	------------------------------------------------------------------------------------------------
	-- booted helpers
	------------------------------------------------------------------------------------------------
	local advance, config, mod = K.advance, K.config, K.mod
	local ALLOWED_WARNINGS = { "[DataService]" }

	local userSeq = 0
	local function newUserId()
		userSeq = userSeq + 1
		return 986300 + userSeq
	end

	local function join(prefix, uid)
		local p = Mock.AddPlayer(prefix .. tostring(uid % 1000), uid)
		advance(1.2)
		return p
	end

	local function leave(p)
		if p and p.Parent then
			Mock.RemovePlayer(p)
		end
		advance(0.8)
	end

	local function storeKey(uid)
		return config().Tokens.DataStoreName .. "/u_" .. uid
	end

	local function stored(uid)
		return Mock.DataStore.Data[storeKey(uid)]
	end

	local function statsOf()
		return { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} }
	end

	local function lastSnapshot(player, fromIndex)
		local list = K.remotesFor("ProfileSync", player.UserId, fromIndex or 0)
		local e = list[#list]
		return e and e.args[1] or nil
	end

	local function hookedSignals()
		local out = { game:GetService("Players").PlayerRemoving }
		local folder = K.remoteFolder and K.remoteFolder()
		for _, name in ipairs({ "RequestProfile", "SettingsSet" }) do
			local remote = folder and folder:FindFirstChild(name)
			if remote then
				out[#out + 1] = remote.OnServerEvent
			end
		end
		return out
	end

	-- a second, independent copy of DataService (own cache, same mock store): "another server" (smoke_p7_data.lua's shape)
	local function secondServer(name)
		local inst = K.moduleInstance("server/Services/DataService")
		if not inst then
			return nil
		end
		local marks = {}
		for _, sig in ipairs(hookedSignals()) do
			local conns = type(sig) == "table" and rawget(sig, "_conns") or nil
			marks[#marks + 1] = { conns = conns, n = conns and #conns or 0 }
		end
		local clone = inst:Clone()
		clone.Name = name
		clone.Parent = inst.Parent
		local ok, module = pcall(require, clone)
		if not ok then
			clone:Destroy()
			return nil, module
		end
		local function release()
			clone:Destroy()
			local clean = true
			for _, m in ipairs(marks) do
				if m.conns then
					for i = #m.conns, m.n + 1, -1 do
						local conn = m.conns[i]
						if type(conn) == "table" and conn.Disconnect then
							conn:Disconnect()
						end
					end
					clean = clean and #m.conns == m.n
				else
					clean = false
				end
			end
			return clean
		end
		return module, clone, release
	end

	------------------------------------------------------------------------------------------------
	-- hybrid_moves_save (booted)
	------------------------------------------------------------------------------------------------
	S.hybrid_moves_save = guarded("hybrid_moves_save", function()
		if not K.needBoot() then
			return
		end
		local D = mod("DataService")
		local DSt = Mock.DataStore
		local uid = newUserId()
		local recSS = ssRecord({ Name = "Mapby", Seed = 7 })
		local recJunk = oldRecord({ SpecialFrom = "Body", Name = "Junky", Seed = 8 })
		local recOld = oldRecord({ Name = "Oldie", Seed = 9 })
		DSt.Data[storeKey(uid)] = {
			Version = 2, Tokens = 3, Pets = { maple_fox = 1, storm_tabby = 1 }, Equipped = {}, Items = {}, Stats = statsOf(),
			Hybrids = { h1 = copy(recSS), h2 = copy(recJunk), h3 = copy(recOld) },
		}
		local mark = K.logSize()
		local p = join("HybSave", uid)
		K.waitFor(function()
			return D.GetProfile(p) ~= nil
		end, 10)
		local prof = D.GetProfile(p)
		if not T.check(prof ~= nil and type(prof.Hybrids) == "table" and prof.Hybrids.h1 ~= nil and prof.Hybrids.h2 ~= nil and prof.Hybrids.h3 ~= nil,
			"hybrid moves save: (precondition) the profile loads with its three hybrids") then
			leave(p)
			return
		end
		T.eq(prof.Hybrids.h1.SpecialFrom, "Style", "hybrid moves save: the load keeps SpecialFrom = 'Style'")
		T.eq(prof.Hybrids.h2.SpecialFrom, nil, "hybrid moves save: the load drops SpecialFrom = 'Body' (anything but 'Style' = the Body)")
		T.eq(prof.Hybrids.h3.SpecialFrom, nil, "hybrid moves save: an old record loads without SpecialFrom")
		T.check(prof.Hybrids.h1.Elements[1] == "Storm" and prof.Hybrids.h1.Elements[2] == "Flame", "hybrid moves save: ...and its element order (Storm first)")
		local snap = lastSnapshot(p, mark)
		T.check(snap ~= nil and type(snap.Hybrids) == "table" and snap.Hybrids.h1 ~= nil and snap.Hybrids.h1.SpecialFrom == "Style" and snap.Hybrids.h2 ~= nil and snap.Hybrids.h2.SpecialFrom == nil,
			"hybrid moves save: the ProfileSync snapshot carries h1.SpecialFrom = 'Style' (and none on h2)",
			snap and snap.Hybrids and keysText(snap.Hybrids.h1) or "no snapshot")

		-- this session: a changed SS record (its Name), a new SS record, a new junk one, one with 8 extras + SpecialFrom
		prof.Hybrids.h1.Name = "Mapby II"
		prof.Hybrids.h5 = ssRecord({ Name = "Newby", Seed = 21 })
		prof.Hybrids.h6 = oldRecord({ SpecialFrom = "style", Name = "Lowby", Seed = 22 })
		local wide = oldRecord({ SpecialFrom = "Style", Name = "Wideby", Seed = 23 })
		for i = 1, 7 do
			wide["X" .. i] = "v" .. i
		end
		prof.Hybrids.h7 = wide -- Seed + X1..X7 = 8 extras
		D.AddCash(p, 5)
		D.MarkDirty(p)
		T.eq(D.Save(p), true, "hybrid moves save: the save lands")
		local rec = stored(uid) or {}
		local sh = type(rec.Hybrids) == "table" and rec.Hybrids or {}
		T.check(sh.h1 ~= nil and sh.h1.SpecialFrom == "Style" and sh.h1.Name == "Mapby II", "hybrid moves save: the stored (changed) h1 keeps SpecialFrom = 'Style'", keysText(sh.h1))
		T.check(sh.h5 ~= nil and sh.h5.SpecialFrom == "Style" and sh.h5.Elements[1] == "Storm", "hybrid moves save: a new SS record is stored with SpecialFrom and Storm first", keysText(sh.h5))
		T.check(sh.h6 ~= nil and sh.h6.SpecialFrom == nil, "hybrid moves save: a new record with SpecialFrom = 'style' is stored without it", keysText(sh.h6))
		local extras = 0
		for i = 1, 7 do
			if sh.h7 and sh.h7["X" .. i] == "v" .. i then
				extras = extras + 1
			end
		end
		T.check(sh.h7 ~= nil and extras == 7 and sh.h7.Seed == 23 and sh.h7.SpecialFrom == "Style",
			"hybrid moves save: 8 extras (Seed + X1..X7) AND SpecialFrom all survive the save (SpecialFrom is not an extra)", keysText(sh.h7))
		T.check(deepEqual(sh.h3, recOld), "hybrid moves save: the stored old record h3 deep-equals the record before the load (no key gained)", keysText(sh.h3))
		leave(p)

		-- two servers: A adds h4 (SS) and saves; B (loaded before A's save) changes Cash and saves; h4 keeps SpecialFrom
		local B, cloneB, releaseB = secondServer("DataServiceHybMovesB")
		if not T.check(B ~= nil and type(B.Load) == "function" and type(B.Save) == "function", "hybrid moves save: a second copy of DataService loads as 'server B'", tostring(cloneB)) then
			return
		end
		local saved = { Studio = Mock.Options.Studio, Fail = DSt.Fail }
		local okRun, errRun = pcall(function()
			Mock.Options.Studio = false
			local uid2 = newUserId()
			local q = join("HybSaveAB", uid2)
			D.AddTokens(q, 1)
			T.eq(D.Save(q), true, "hybrid moves save: (setup) the first save on server A")
			B.Load(q)
			advance(0.2)
			local cash0 = (stored(uid2) or {}).Cash or 0
			D.GetProfile(q).Hybrids.h4 = ssRecord({ Name = "Twoby", Seed = 31 })
			D.MarkDirty(q)
			T.eq(D.Save(q), true, "hybrid moves save: server A adds the SS hybrid h4 and saves")
			B.AddCash(q, 7)
			T.eq(B.Save(q), true, "hybrid moves save: server B (older base) changes Cash and saves")
			local r2 = stored(uid2) or {}
			local h4 = type(r2.Hybrids) == "table" and r2.Hybrids.h4 or nil
			T.check(h4 ~= nil and h4.SpecialFrom == "Style" and h4.Elements[1] == "Storm" and r2.Cash == cash0 + 7,
				"hybrid moves save: the stored h4 keeps SpecialFrom = 'Style' after B's save (and B's Cash landed)", keysText(h4) .. " cash " .. tostring(r2.Cash))
			advance(0.3)
			local bh = B.GetProfile(q) and B.GetProfile(q).Hybrids
			T.check(type(bh) == "table" and bh.h4 ~= nil and bh.h4.SpecialFrom == "Style", "hybrid moves save: ...and B's live profile adopts it with SpecialFrom", keysText(bh and bh.h4))
			leave(q)
		end)
		Mock.Options.Studio = saved.Studio
		DSt.Fail = saved.Fail
		advance(12)
		T.check(releaseB() == true, "hybrid moves save: server B's hooks are dropped with it")
		if not okRun then
			error(errRun, 0)
		end
		K.flushErrors("hybrid_moves_save")
		K.flushWarnings("hybrid_moves_save", ALLOWED_WARNINGS)
	end)

	------------------------------------------------------------------------------------------------
	-- hybrid_moves_evolve (booted)
	------------------------------------------------------------------------------------------------
	S.hybrid_moves_evolve = guarded("hybrid_moves_evolve", function()
		if not K.needBoot() then
			return
		end
		local D = mod("DataService")
		local PK, BC = req("shared/PetKeys"), req("shared/BattleCatalog")
		local uid = newUserId()
		local p = join("HybEvolve", uid)
		K.waitFor(function()
			return D.GetProfile(p) ~= nil
		end, 10)
		local prof = D.GetProfile(p)
		if not T.check(prof ~= nil and PK ~= nil, "hybrid moves evolve: (precondition) the profile loads") then
			leave(p)
			return
		end
		local key = "hyb:hm1"
		T.check(PK.Add(prof, key, 1, ssRecord({ Name = "Evoby", Seed = 41 })) == true, "hybrid moves evolve: (setup) the SS hybrid is added")
		D.MarkDirty(p)
		D.SetPetLevel(p, key, 20)
		advance(0.2)
		Mock.FromClient(K.remoteFolder():FindFirstChild("PetCare"), p, "Evolve", key)
		advance(0.6)
		T.eq(D.GetEvolution(p, key), 1, "hybrid moves evolve: PetCare('Evolve', 'hyb:hm1') at level 20 -> stage 1")
		local def = PK.DefOf(key, D.GetProfile(p))
		T.check(def ~= nil and def.Special ~= nil and def.Special.Name == "Static Storm" and def.Element == "Storm",
			"hybrid moves evolve: ...its def keeps Static Storm and Storm first", def and (tostring(def.Special and def.Special.Name) .. " / " .. tostring(def.Element)) or "no def")
		T.check(def ~= nil and BC.FormNameOf(key, def.Special.Kind, 1) == BC.Forms.Storm[1].Id, "hybrid moves evolve: ...its stage-1 form is the Storm kind's generic one",
			def and tostring(BC.FormNameOf(key, def.Special.Kind, 1)) or "no def")
		leave(p)
		K.flushErrors("hybrid_moves_evolve")
		K.flushWarnings("hybrid_moves_evolve", ALLOWED_WARNINGS)
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}

	S.client_hybrid_moves_state = guarded("client_hybrid_moves_state", function()
		local KC = _G.KC
		local advance = KC.advance
		local State = KC.M and KC.M.State
		if not T.check(State ~= nil and type(State.DefOf) == "function" and type(State.Hybrids) == "function", "client hybrid moves: State is loaded") then
			return
		end
		local before = State.Get()
		local function sync(rec)
			KC.toClient("ProfileSync", {
				Tokens = 10, Pets = { maple_fox = 1, storm_tabby = 1 }, Equipped = {}, Items = {},
				Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} }, Perks = {},
				Discovered = {}, IndexClaimed = {}, Tutorial = { Step = 99, Done = true, Gifted = true },
				Cash = 100, Gems = 0, Tiers = {}, Hybrids = { h9 = rec }, PetLevels = {},
			})
			advance(0.1)
		end
		local okRun, errRun = pcall(function()
			sync(ssRecord({ Name = "Mapby", Seed = 7 }))
			local h = State.Hybrids() and State.Hybrids().h9
			T.check(h ~= nil and h.SpecialFrom == "Style" and h.Elements[1] == "Storm", "client hybrid moves: State.Hybrids().h9 keeps SpecialFrom = 'Style' and Storm first", keysText(h))
			local def = State.DefOf("hyb:h9")
			T.check(def ~= nil and def.Special ~= nil and def.Special.Name == "Static Storm" and def.Element == "Storm",
				"client hybrid moves: State.DefOf('hyb:h9') -> Static Storm, Element Storm (the same def as the server's)", def and (tostring(def.Special and def.Special.Name) .. " / " .. tostring(def.Element)) or "no def")
			sync(ssRecord({ Name = "Mapby", Seed = 7, SpecialFrom = "style" }))
			h = State.Hybrids() and State.Hybrids().h9
			def = State.DefOf("hyb:h9")
			T.check(h ~= nil and h.SpecialFrom == nil and def ~= nil and def.Special.Name == "Leaf Pounce",
				"client hybrid moves: SpecialFrom = 'style' (junk) -> dropped, Leaf Pounce", def and def.Special.Name or "no def")
			local plain = ssRecord({ Name = "Mapby", Seed = 7 })
			plain.SpecialFrom = nil
			sync(plain)
			def = State.DefOf("hyb:h9")
			T.check(def ~= nil and def.Special.Name == "Leaf Pounce", "client hybrid moves: no SpecialFrom -> Leaf Pounce", def and def.Special.Name or "no def")
		end)
		KC.toClient("ProfileSync", before)
		advance(0.1)
		if not okRun then
			error(errRun, 0)
		end
		KC.flushErrors("client_hybrid_moves_state")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
