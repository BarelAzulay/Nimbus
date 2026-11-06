-- smoke_redo_fusion.lua: the Mix move choice on the server (docs/superpowers/specs/2026-11-06-window-redo-design.md 5.6 "Remote
-- and server" + 7; plan docs/superpowers/plans/2026-11-06-window-redo.md Task 2). Fusion("Mix", body, style, moves): moves is
-- "BB" | "BS" | "SB" | "SS" (letter 1 = the parent of the normal attack, letter 2 = the parent of the special, B = Body,
-- S = Style), nil = "BB" (today's rule, an old client); anything else is refused with "Pick the moves again" before anything
-- else is read. The server builds the record through PetKeys.MixMoves: Elements = { attack parent's, the other's } (deduplicated)
-- and SpecialFrom = "Style" when letter 2 is S (left out otherwise). Loaded by tools/smoke.py in the server world (booted) and the
-- client world (ARGS.context picks the half):
--   fusion_moves   (booted; its first part is pure) PetKeys.ValidMoves / PetKeys.MixMoves on the fixture defs; through the remote at
--                  the player's own Fusion Machine: BB / nil / BS / SB / SS build the right record (and nothing else in it changes),
--                  junk moves are refused with one "Pick the moves again" toast and nothing fused or charged, Upgrade ignores a 4th
--                  argument, FusionService.Mix / Preview take the moves (Preview carries Elements and SpecialFrom), and two pets of
--                  one element give a one-element hybrid
--   pet_attr_hybrid_elements          (booted; Task 3, spec 6 "Other players' view") PetService's EquippedHybrids attribute
--                  "uid=Body/Style/Tier/Rarity/Seed/Elements;...": field 6 = the record's Elements joined by "+" (the chosen first
--                  element first), field 5 "" when the record has no Seed (field 6 keeps its place); a record with no Elements
--                  keeps today's 4 / 5-field value byte for byte; junk element entries in a live record never break the value
--   client_pet_attr_hybrid_elements   (client; Task 3) PetController.ParseHybrids reads field 6 into the stand-in record's
--                  Elements, so PetKeys.DefOf gives other players' hybrids the same first element; 4 / 5-field values (older
--                  servers) read as before; junk never errors; another player's 6-field value still draws the follower
-- Fixture pets (every hybrid test of the plan): Body maple_fox (Uncommon, Flame, "Leaf Pounce" kind Pounce), Style storm_tabby
-- (Rare, Storm, "Static Storm" kind Storm); ember_phoenix is a second Flame pet (the equal-elements case).
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local fmt = string.format

local BODY, STYLE, FLAME2 = "maple_fox", "storm_tabby", "ember_phoenix"
local JUNK_TEXT = "Pick the moves again"

local function listText(t)
	if type(t) ~= "table" then
		return tostring(t)
	end
	local out = {}
	for i, v in ipairs(t) do
		out[i] = tostring(v)
	end
	return "{" .. table.concat(out, "+") .. "}"
end

local function sameList(a, b)
	if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
		return false
	end
	for i = 1, #b do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

local function keysText(t)
	local list = {}
	for k, v in pairs(type(t) == "table" and t or {}) do
		list[#list + 1] = tostring(k) .. "=" .. (type(v) == "table" and listText(v) or tostring(v))
	end
	table.sort(list)
	return table.concat(list, " ")
end

local function movesLabel(m)
	if type(m) == "string" then
		return fmt("%q", m)
	end
	return tostring(m) .. " (" .. type(m) .. ")"
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

	S.fusion_moves = guarded("fusion_moves", function()
		------------------------------------------------------------------------------------------------
		-- pure: PetKeys.ValidMoves / PetKeys.MixMoves
		------------------------------------------------------------------------------------------------
		local PK, PC = req("shared/PetKeys"), req("shared/PetCatalog")
		if not T.check(PK ~= nil and PC ~= nil, "fusion moves: PetKeys and PetCatalog load") then
			return
		end
		local bodyDef, styleDef, flameDef = PC.Get(BODY), PC.Get(STYLE), PC.Get(FLAME2)
		T.check(bodyDef ~= nil and styleDef ~= nil and flameDef ~= nil and bodyDef.Element == "Flame" and styleDef.Element == "Storm" and flameDef.Element == "Flame"
			and bodyDef.Special.Name == "Leaf Pounce" and styleDef.Special.Name == "Static Storm",
			"fusion moves: (fixture) Maple Fox is Flame + Leaf Pounce, Storm Tabby Storm + Static Storm, Ember Phoenix Flame")
		local hasValid = T.check(type(PK.ValidMoves) == "function", "fusion moves: PetKeys.ValidMoves is a function")
		local hasMix = T.check(type(PK.MixMoves) == "function", "fusion moves: PetKeys.MixMoves is a function")
		if hasValid then
			T.check(PK.ValidMoves(nil) == true, "fusion moves: ValidMoves(nil) -> true (nil = 'BB', an old client)")
			for _, m in ipairs({ "BB", "BS", "SB", "SS" }) do
				T.check(PK.ValidMoves(m) == true, "fusion moves: ValidMoves(" .. movesLabel(m) .. ") -> true")
			end
			for _, m in ipairs({ "bb", "", "BBB", 1, {}, "XX", "bs", "B", true, "BS " }) do
				T.check(PK.ValidMoves(m) == false, "fusion moves: ValidMoves(" .. movesLabel(m) .. ") -> false")
			end
		end
		if hasMix and bodyDef and styleDef and flameDef then
			local cases = {
				{ "BB", { "Flame", "Storm" }, nil },
				{ "BS", { "Flame", "Storm" }, "Style" },
				{ "SB", { "Storm", "Flame" }, nil },
				{ "SS", { "Storm", "Flame" }, "Style" },
			}
			for _, c in ipairs(cases) do
				local okCall, elements, from = pcall(PK.MixMoves, bodyDef, styleDef, c[1])
				T.check(okCall and sameList(elements, c[2]) and from == c[3],
					fmt("fusion moves: MixMoves(Maple Fox, Storm Tabby, %q) -> %s, SpecialFrom %s", c[1], listText(c[2]), tostring(c[3])),
					okCall and (listText(elements) .. " / " .. tostring(from)) or tostring(elements))
			end
			local okNil, elNil, fromNil = pcall(PK.MixMoves, bodyDef, styleDef, nil)
			T.check(okNil and sameList(elNil, { "Flame", "Storm" }) and fromNil == nil, "fusion moves: MixMoves(..., nil) -> today's rule ({Flame+Storm}, no SpecialFrom)",
				okNil and (listText(elNil) .. " / " .. tostring(fromNil)) or tostring(elNil))
			local okEq, elEq, fromEq = pcall(PK.MixMoves, bodyDef, flameDef, "SB")
			T.check(okEq and sameList(elEq, { "Flame" }) and fromEq == nil, "fusion moves: MixMoves(two Flame pets, 'SB') -> one element {Flame}",
				okEq and (listText(elEq) .. " / " .. tostring(fromEq)) or tostring(elEq))
		end

		------------------------------------------------------------------------------------------------
		-- booted: the remote at the player's own machine, FusionService.Mix / Preview
		------------------------------------------------------------------------------------------------
		if not K.needBoot() then
			return
		end
		local advance, config, mod = K.advance, K.config, K.mod
		local F, D = mod("FusionService") or req("server/Services/FusionService"), mod("DataService")
		local TC = req("shared/TycoonCatalog")
		if not T.check(F ~= nil and D ~= nil and TC ~= nil and type(F.Mix) == "function" and type(F.Preview) == "function", "fusion moves: FusionService and DataService load") then
			return
		end
		local Ty = mod("TycoonService") or req("server/Services/TycoonService")
		local SS = mod("SpotService")

		local p = Mock.AddPlayer("FuseMoves", 987100)
		advance(1.0)
		local prof = D.GetProfile(p)
		if not T.check(prof ~= nil, "fusion moves: (precondition) the profile loads") then
			return
		end

		local function setHome(prestige, stations)
			return D.MutateHome(p, function(h)
				h.Prestige = prestige
				for id in pairs(h.Stations) do
					h.Stations[id] = nil
				end
				for id, lv in pairs(stations or {}) do
					h.Stations[id] = lv
				end
				if type(TC.HomeLevelOf) == "function" then
					h.Level = TC.HomeLevelOf(h)
				end
			end)
		end
		local function give(key, n)
			local ok = PK.Add(D.GetProfile(p), key, n or 1)
			D.MarkDirty(p)
			return ok
		end
		local function count(key)
			return PK.Count(D.GetProfile(p), key)
		end
		local function hybridCount()
			local n = 0
			for _ in pairs(type(D.GetProfile(p).Hybrids) == "table" and D.GetProfile(p).Hybrids or {}) do
				n = n + 1
			end
			return n
		end
		local function results(mark)
			local out = {}
			for _, e in ipairs(K.remotesFor("Fusion", p.UserId, mark)) do
				if e.args[1] == "Result" and type(e.args[2]) == "table" then
					out[#out + 1] = e.args[2]
				end
			end
			return out
		end
		local function toasts(needle, mark)
			local n = 0
			for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark)) do
				if string.find(tostring(e.args[1]), needle, 1, true) then
					n = n + 1
				end
			end
			return n
		end
		local function fusionRemote()
			return K.remoteFolder():FindFirstChild("Fusion")
		end

		-- claim a home, build the machine, stand next to it (smoke_p2_fusion.lua p2fusion_exploits' shape)
		local spots = (K.W.lobbyInfo and K.W.lobbyInfo.Spots) or {}
		local index = nil
		for i = 1, config().Lobby.SpotCount do
			if spots[i] and SS and not SS.GetOwner(i) then
				index = i
				break
			end
		end
		local claimed = index and Ty and Ty.Claim(p, index)
		advance(0.6)
		if not T.check(claimed and true or false, "fusion moves: (precondition) the player claims a home", tostring(index)) then
			Mock.RemovePlayer(p)
			advance(0.6)
			return
		end
		setHome(1, { FusionMachine = 1, Kitchen = 1, Press1 = 1, Collector = 1 })
		D.AddTokens(p, 1000000)
		D.AddGems(p, 1000)
		advance(2.2)
		local machine = spots[index].Folder:FindFirstChild("Station_FusionMachine", true)
		local okRun, errRun = pcall(function()
			if not T.check(machine ~= nil, "fusion moves: (precondition) the plot shows the Fusion Machine") then
				return
			end
			local at = machine:GetPivot().Position
			local function stand()
				Mock.Teleport(p, at + Vector3.new(0, 3, -7))
				advance(0.1)
			end
			stand()
			advance(1)

			-- one fresh pair per case; `send` = the remote's arguments after the action
			local function mixCase(label, body, style, send, wantElements, wantFrom, wantSpecial, wantElement)
				give(body, 1)
				give(style, 1)
				stand()
				local tokens0 = D.GetTokens(p)
				local mark = K.logSize()
				Mock.FromClient(fusionRemote(), p, "Mix", body, style, unpack(send, 1, send.n or #send))
				advance(0.3)
				local res = results(mark)
				local last = res[#res]
				local parsed = last and last.Ok and PK.Parse(last.Key)
				local rec = parsed and parsed.HybridId and D.GetProfile(p).Hybrids[parsed.HybridId]
				if T.check(last ~= nil and last.Ok == true and type(rec) == "table", "fusion moves: Mix " .. label .. " through the remote at the machine fuses",
					last and tostring(last.Reason) or "no answer") then
					T.check(sameList(rec.Elements, wantElements), "fusion moves: Mix " .. label .. " -> Elements " .. listText(wantElements), listText(rec.Elements))
					T.check(rec.SpecialFrom == wantFrom, "fusion moves: Mix " .. label .. " -> SpecialFrom " .. tostring(wantFrom), tostring(rec.SpecialFrom))
					local bodyCat, styleCat = PC.Get(body), PC.Get(style)
					local known = { Body = true, Style = true, Elements = true, Name = true, Rarity = true, Tier = true, Seed = true, SpecialFrom = true }
					local extra = {}
					for k in pairs(rec) do
						if not known[k] then
							extra[#extra + 1] = tostring(k)
						end
					end
					T.check(rec.Body == body and rec.Style == style and rec.Name == PK.BlendName(bodyCat.Name, styleCat.Name) and rec.Tier == "Normal" and type(rec.Seed) == "number"
						and #extra == 0, "fusion moves: Mix " .. label .. " -> nothing else in the record changes (Body, Style, the blended Name, Tier, a Seed, no other field)", keysText(rec))
					local def = PK.DefOf(last.Key, D.GetProfile(p))
					T.check(def ~= nil and def.Special ~= nil and def.Special.Name == wantSpecial and def.Element == wantElement,
						fmt("fusion moves: Mix %s -> the hybrid's def: special %s, first element %s", label, wantSpecial, wantElement),
						def and (tostring(def.Special and def.Special.Name) .. " / " .. tostring(def.Element)) or "no def")
					T.check(count(body) == 0 and count(style) == 0 and D.GetTokens(p) < tokens0, "fusion moves: Mix " .. label .. " -> both inputs are used and the price is paid")
				end
				advance(1)
				return rec
			end

			mixCase("'BB'", BODY, STYLE, { "BB", n = 1 }, { "Flame", "Storm" }, nil, "Leaf Pounce", "Flame")
			mixCase("with 3 arguments (an old client)", BODY, STYLE, { n = 0 }, { "Flame", "Storm" }, nil, "Leaf Pounce", "Flame")
			mixCase("with an explicit nil", BODY, STYLE, { nil, n = 1 }, { "Flame", "Storm" }, nil, "Leaf Pounce", "Flame")
			mixCase("'BS'", BODY, STYLE, { "BS", n = 1 }, { "Flame", "Storm" }, "Style", "Static Storm", "Flame")
			mixCase("'SB'", BODY, STYLE, { "SB", n = 1 }, { "Storm", "Flame" }, nil, "Leaf Pounce", "Storm")
			mixCase("'SS'", BODY, STYLE, { "SS", n = 1 }, { "Storm", "Flame" }, "Style", "Static Storm", "Storm")
			-- two Flame pets: one element whatever the attack letter; the special still follows letter 2
			mixCase("of two Flame pets 'SB'", BODY, FLAME2, { "SB", n = 1 }, { "Flame" }, nil, "Leaf Pounce", "Flame")
			mixCase("of two Flame pets 'SS'", BODY, FLAME2, { "SS", n = 1 }, { "Flame" }, "Style", flameDef.Special.Name, "Flame")

			-- junk moves: refused before anything else is read; one toast; nothing fused or charged
			local junk = { "XX", "bs", "BSS", 5, {}, "", true }
			for _, m in ipairs(junk) do
				advance(1.6) -- past the refusal toast's repeat gap
				give(BODY, 1)
				give(STYLE, 1)
				stand()
				local before = { Body = count(BODY), Style = count(STYLE), Tokens = D.GetTokens(p), Gems = D.GetGems(p), Hybrids = hybridCount() }
				local mark = K.logSize()
				Mock.FromClient(fusionRemote(), p, "Mix", BODY, STYLE, m)
				advance(0.3)
				local res = results(mark)
				T.check(#res == 1 and res[1].Ok == false and res[1].Reason == JUNK_TEXT and res[1].Action == "Mix",
					"fusion moves: Mix with moves " .. movesLabel(m) .. " -> one answer { Ok = false, Reason = '" .. JUNK_TEXT .. "' }",
					#res .. " answers: " .. (res[#res] and (tostring(res[#res].Ok) .. " " .. tostring(res[#res].Reason)) or "none"))
				T.eq(toasts(JUNK_TEXT, mark), 1, "fusion moves: ...one toast '" .. JUNK_TEXT .. "' (" .. movesLabel(m) .. ")")
				T.check(count(BODY) == before.Body and count(STYLE) == before.Style and D.GetTokens(p) == before.Tokens and D.GetGems(p) == before.Gems and hybridCount() == before.Hybrids,
					"fusion moves: ...nothing fused or charged (" .. movesLabel(m) .. ")", fmt("pets %d/%d -> %d/%d, hybrids %d -> %d", before.Body, before.Style, count(BODY), count(STYLE), before.Hybrids, hybridCount()))
				-- clean up the pair for the next case
				PK.Remove(D.GetProfile(p), BODY, count(BODY))
				PK.Remove(D.GetProfile(p), STYLE, count(STYLE))
			end
			-- a burst of junk in one frame toasts once (the refusal toast's repeat gap)
			advance(1.6)
			local markBurst = K.logSize()
			for _ = 1, 3 do
				Mock.FromClient(fusionRemote(), p, "Mix", BODY, STYLE, "XX")
			end
			advance(0.3)
			T.eq(toasts(JUNK_TEXT, markBurst), 1, "fusion moves: three junk requests in one frame -> one toast")

			-- Upgrade ignores a 4th argument
			advance(1)
			give("pip_penguin", 3)
			stand()
			local markUp = K.logSize()
			Mock.FromClient(fusionRemote(), p, "Upgrade", "pip_penguin", nil, "XX")
			advance(0.3)
			local resUp = results(markUp)
			T.check(#resUp >= 1 and resUp[#resUp].Ok == true and count("pip_penguin") == 0 and count("pip_penguin@Golden") == 1 and toasts(JUNK_TEXT, markUp) == 0,
				"fusion moves: Fusion('Upgrade', key, nil, 'XX') upgrades as today (the 4th argument is ignored)",
				resUp[#resUp] and tostring(resUp[#resUp].Reason) or "no answer")

			-- FusionService.Preview carries the moves
			give(BODY, 1)
			give(STYLE, 1)
			local okP, plan = F.Preview(p, "Mix", BODY, STYLE, "SB")
			T.check(okP == true and type(plan) == "table" and type(plan.Elements) == "table" and plan.Elements[1] == "Storm" and plan.Elements[2] == "Flame" and plan.SpecialFrom == nil,
				"fusion moves: Preview(Mix, 'SB') -> Elements {Storm+Flame}, no SpecialFrom", okP and (listText(plan.Elements) .. " / " .. tostring(plan.SpecialFrom)) or tostring(plan))
			okP, plan = F.Preview(p, "Mix", BODY, STYLE, "SS")
			T.check(okP == true and type(plan) == "table" and type(plan.Elements) == "table" and plan.Elements[1] == "Storm" and plan.SpecialFrom == "Style",
				"fusion moves: Preview(Mix, 'SS') -> Elements {Storm+...}, SpecialFrom 'Style'", okP and (listText(plan.Elements) .. " / " .. tostring(plan.SpecialFrom)) or tostring(plan))
			okP, plan = F.Preview(p, "Mix", BODY, STYLE)
			T.check(okP == true and type(plan) == "table" and sameList(plan.Elements, { "Flame", "Storm" }) and plan.SpecialFrom == nil,
				"fusion moves: Preview(Mix) with no moves -> today's rule ({Flame+Storm}, no SpecialFrom)", okP and (listText(plan.Elements) .. " / " .. tostring(plan.SpecialFrom)) or tostring(plan))
			okP, plan = F.Preview(p, "Mix", BODY, STYLE, "XX")
			T.check(okP == false and plan == JUNK_TEXT, "fusion moves: Preview(Mix, 'XX') -> false, '" .. JUNK_TEXT .. "'", tostring(okP) .. " " .. tostring(plan))
			local okPU, planU = F.Preview(p, "Upgrade", "pip_penguin@Golden", nil, "XX")
			T.check(okPU == false and planU ~= JUNK_TEXT, "fusion moves: Preview(Upgrade, ..., 'XX') ignores the moves (refused only for its own reason)", tostring(planU))

			-- FusionService.Mix takes the moves (server code); junk is refused there too
			local before = { Body = count(BODY), Style = count(STYLE), Tokens = D.GetTokens(p), Hybrids = hybridCount() }
			local okJ, whyJ = F.Mix(p, BODY, STYLE, "bs")
			T.check(okJ == false and whyJ == JUNK_TEXT and count(BODY) == before.Body and count(STYLE) == before.Style and D.GetTokens(p) == before.Tokens and hybridCount() == before.Hybrids,
				"fusion moves: FusionService.Mix(p, a, b, 'bs') -> false, '" .. JUNK_TEXT .. "', nothing changed", tostring(okJ) .. " " .. tostring(whyJ))
			if count(BODY) < 1 then
				give(BODY, 1)
			end
			if count(STYLE) < 1 then
				give(STYLE, 1)
			end
			local okM, keyM = F.Mix(p, BODY, STYLE, "SS")
			local parsedM = okM and PK.Parse(keyM)
			local recM = parsedM and D.GetProfile(p).Hybrids[parsedM.HybridId]
			T.check(okM == true and type(recM) == "table" and sameList(recM.Elements, { "Storm", "Flame" }) and recM.SpecialFrom == "Style",
				"fusion moves: FusionService.Mix(p, a, b, 'SS') -> Elements {Storm+Flame}, SpecialFrom 'Style'", recM and keysText(recM) or tostring(keyM))
		end)
		if Ty and type(Ty.Release) == "function" then
			pcall(Ty.Release, p)
		end
		if p.Parent then
			Mock.RemovePlayer(p)
		end
		advance(0.6)
		if not okRun then
			error(errRun, 0)
		end
		K.flushErrors("fusion_moves")
	end)

	S.pet_attr_hybrid_elements = guarded("pet_attr_hybrid_elements", function()
		if not K.needBoot() then
			return
		end
		local advance, mod = K.advance, K.mod
		local D, PS = mod("DataService"), mod("PetService")
		local PK = req("shared/PetKeys")
		if not T.check(D ~= nil and PS ~= nil and PK ~= nil and type(PS.Equip) == "function" and type(PS.Refresh) == "function" and type(D.SetTeam) == "function",
			"pet attr: DataService, PetService and PetKeys load") then
			return
		end
		local ATTR = "EquippedHybrids"
		local p = Mock.AddPlayer("AttrHybrid", 987200)
		advance(1.0)
		local okRun, errRun = pcall(function()
			local prof = D.GetProfile(p)
			local teams = D.GetTeams(p)
			if not T.check(prof ~= nil and type(teams) == "table", "pet attr: (precondition) the profile and the teams load") then
				return
			end
			local function setTeam(keys)
				local ok, why = D.SetTeam(p, teams.Active, keys)
				advance(0.3)
				return ok, why
			end
			local function equip(key)
				advance(0.3)
				local ok, why = PS.Equip(p, key)
				T.check(ok == true, "pet attr: (setup) equip " .. key, tostring(why))
			end
			-- uid -> "Body/Style/Tier/Rarity[/Seed[/Elements]]" of every entry of the attribute
			local function entries()
				local out = {}
				local text = p:GetAttribute(ATTR)
				for entry in string.gmatch(type(text) == "string" and text or "", "[^;]+") do
					local uid, rest = string.match(entry, "^([^=]+)=(.*)$")
					if uid then
						out[uid] = rest
					end
				end
				return out, tostring(text)
			end
			local function add(uid, elements, seed)
				local ok = PK.Add(prof, "hyb:" .. uid, 1, { Body = BODY, Style = STYLE, Rarity = "Rare", Tier = "Normal", Elements = elements, Seed = seed })
				T.check(ok == true, "pet attr: (setup) hybrid " .. uid)
			end
			add("pa1", { "Storm", "Flame" }, 42) -- an SB hybrid (Storm Tabby gives the normal attack) with a Seed
			add("pa2", { "Storm", "Flame" }, nil) -- the same with no Seed
			add("pa3", { "Flame" }, 9) -- two parents of one element
			add("pa4", nil, nil) -- a record from before the element order: no Elements, no Seed
			add("pa5", nil, 7) -- no Elements, a Seed
			D.MarkDirty(p)
			T.check(setTeam({}) == true, "pet attr: (setup) an empty team")

			equip("hyb:pa1")
			local e, raw = entries()
			T.check(string.find(raw, "=maple_fox/storm_tabby/Normal/Rare/42/Storm+Flame", 1, true) ~= nil,
				"pet attr: an equipped SB hybrid with Seed 42 -> EquippedHybrids carries '=maple_fox/storm_tabby/Normal/Rare/42/Storm+Flame'", raw)
			T.eq(e.pa1, "maple_fox/storm_tabby/Normal/Rare/42/Storm+Flame", "pet attr: ...field 6 = the record's Elements in their order, joined by '+'")
			equip("hyb:pa2")
			equip("hyb:pa3")
			e, raw = entries()
			T.check(string.find(raw, "/Rare//Storm+Flame", 1, true) ~= nil, "pet attr: a record with no Seed -> '/Rare//Storm+Flame' (field 5 empty, field 6 keeps its place)", raw)
			T.eq(e.pa2, "maple_fox/storm_tabby/Normal/Rare//Storm+Flame", "pet attr: ...the whole entry of the no-Seed hybrid")
			T.eq(e.pa3, "maple_fox/storm_tabby/Normal/Rare/9/Flame", "pet attr: a one-element hybrid -> field 6 is that element")
			T.eq(e.pa1, "maple_fox/storm_tabby/Normal/Rare/42/Storm+Flame", "pet attr: ...the first hybrid's entry is unchanged next to the others")

			-- records with no Elements keep today's value byte for byte (an older client reads it as before)
			T.check(setTeam({}) == true, "pet attr: (setup) the team emptied again")
			equip("hyb:pa4")
			equip("hyb:pa5")
			e, raw = entries()
			T.eq(e.pa4, "maple_fox/storm_tabby/Normal/Rare", "pet attr: a record with no Elements and no Seed -> today's 4 fields")
			T.eq(e.pa5, "maple_fox/storm_tabby/Normal/Rare/7", "pet attr: a record with no Elements and a Seed -> today's 5 fields")
			T.check(not string.find(raw, "//", 1, true), "pet attr: ...no empty Seed field without an Elements field", raw)

			-- junk in a live record's Elements never breaks the value (only plain names are written)
			T.check(setTeam({}) == true, "pet attr: (setup) the team emptied for the junk case")
			equip("hyb:pa1")
			prof.Hybrids.pa1.Elements = { "Storm", "Fl/ame", 5, "a;b", "x+y", "Flame" }
			PS.Refresh(p)
			advance(0.3)
			e, raw = entries()
			T.eq(e.pa1, "maple_fox/storm_tabby/Normal/Rare/42/Storm+Flame", "pet attr: junk element entries in the live record are left out of field 6")
			prof.Hybrids.pa1.Elements = { "Fl/ame", 5 }
			PS.Refresh(p)
			advance(0.3)
			e, raw = entries()
			T.eq(e.pa1, "maple_fox/storm_tabby/Normal/Rare/42", "pet attr: ...and only junk -> no field 6 (today's 5 fields)")
			T.check(setTeam({}) == true and (p:GetAttribute(ATTR) or "") == "", "pet attr: an empty team clears the attribute", tostring(p:GetAttribute(ATTR)))
		end)
		if p.Parent then
			Mock.RemovePlayer(p)
		end
		advance(0.6)
		if not okRun then
			error(errRun, 0)
		end
		K.flushErrors("pet_attr_hybrid_elements")
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}

	local function moduleAt(top, rest)
		local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end

	S.client_pet_attr_hybrid_elements = guarded("client_pet_attr_hybrid_elements", function()
		local KC = _G.KC
		local advance = KC.advance
		local PCtl = (KC.M and KC.M.PetController) or moduleAt("client", "Controllers/PetController")
		local PK = moduleAt("shared", "PetKeys")
		if not T.check(type(PCtl) == "table" and type(PCtl.ParseHybrids) == "function" and PK ~= nil,
			"client pet attr: PetController.ParseHybrids is a function (and PetKeys loads)") then
			return
		end
		local function parse(text)
			local ok, result = pcall(PCtl.ParseHybrids, text)
			if not ok then
				T.fail("client pet attr: ParseHybrids(" .. movesLabel(text) .. ") does not error", tostring(result))
				return nil, nil
			end
			local h = type(result) == "table" and type(result.Hybrids) == "table" and result.Hybrids or {}
			return result, h
		end
		local function defOf(key, parsed)
			local ok, def = pcall(PK.DefOf, key, parsed)
			return ok and def or nil
		end

		-- six fields: the element order arrives
		local parsed, h = parse("h1=maple_fox/storm_tabby/Normal/Rare/42/Storm+Flame")
		local rec = h and h.h1
		T.check(rec ~= nil and sameList(rec.Elements, { "Storm", "Flame" }) and rec.Seed == 42 and rec.Body == BODY and rec.Style == STYLE and rec.Rarity == "Rare" and rec.Tier == "Normal",
			"client pet attr: ParseHybrids('h1=maple_fox/storm_tabby/Normal/Rare/42/Storm+Flame') -> Elements {Storm+Flame}, Seed 42 (Body, Style, Tier, Rarity as before)", keysText(rec))
		local def = parsed and defOf("hyb:h1", parsed)
		T.check(def ~= nil and def.Element == "Storm" and sameList(def.Elements, { "Storm", "Flame" }),
			"client pet attr: ...PetKeys.DefOf('hyb:h1', parsed).Element == 'Storm' (the owner's chosen first element)", def and (tostring(def.Element) .. " " .. listText(def.Elements)) or "no def")

		-- five fields (an older server): no Elements, today's fallback (the Body's element first)
		parsed, h = parse("h1=maple_fox/storm_tabby/Normal/Rare/42")
		rec = h and h.h1
		T.check(rec ~= nil and rec.Elements == nil and rec.Seed == 42, "client pet attr: the 5-field value -> no Elements, Seed 42", keysText(rec))
		def = parsed and defOf("hyb:h1", parsed)
		T.check(def ~= nil and def.Element == "Flame", "client pet attr: ...DefOf(...).Element == 'Flame' (today's fallback)", def and tostring(def.Element) or "no def")

		-- empty field 5, field 6 present
		parsed, h = parse("h1=maple_fox/storm_tabby/Normal/Rare//Storm+Flame")
		rec = h and h.h1
		T.check(rec ~= nil and rec.Seed == nil and sameList(rec.Elements, { "Storm", "Flame" }),
			"client pet attr: 'h1=maple_fox/storm_tabby/Normal/Rare//Storm+Flame' -> Seed nil, Elements {Storm+Flame}", keysText(rec))
		def = parsed and defOf("hyb:h1", parsed)
		T.check(def ~= nil and def.Element == "Storm", "client pet attr: ...DefOf(...).Element == 'Storm'", def and tostring(def.Element) or "no def")

		-- four fields (the oldest value) still read
		parsed, h = parse("h1=maple_fox/storm_tabby/Golden/Rare")
		rec = h and h.h1
		T.check(rec ~= nil and rec.Seed == nil and rec.Elements == nil and rec.Tier == "Golden" and rec.Rarity == "Rare",
			"client pet attr: the 4-field value reads as before (Tier Golden, Rarity Rare, no Seed, no Elements)", keysText(rec))

		-- several entries keep their own order
		parsed, h = parse("a1=maple_fox/storm_tabby/Normal/Rare/1/Flame+Storm;a2=maple_fox/storm_tabby/Normal/Rare/2/Storm+Flame")
		T.check(h ~= nil and h.a1 ~= nil and h.a2 ~= nil and sameList(h.a1.Elements, { "Flame", "Storm" }) and sameList(h.a2.Elements, { "Storm", "Flame" }),
			"client pet attr: two entries -> each keeps its own element order", h and (keysText(h.a1) .. " | " .. keysText(h.a2)) or "nil")
		local d1, d2 = parsed and defOf("hyb:a1", parsed), parsed and defOf("hyb:a2", parsed)
		T.check(d1 ~= nil and d2 ~= nil and d1.Element == "Flame" and d2.Element == "Storm", "client pet attr: ...and their defs lead with Flame / Storm",
			tostring(d1 and d1.Element) .. " / " .. tostring(d2 and d2.Element))

		-- junk never errors; DefOf drops unknown element names (and falls back to the parents when none is left)
		parsed, h = parse("h1=maple_fox/storm_tabby/Normal/Rare/42/Junk+Storm")
		def = parsed and defOf("hyb:h1", parsed)
		T.check(def ~= nil and def.Element == "Storm", "client pet attr: field 6 'Junk+Storm' -> DefOf leads with Storm (the unknown name dropped)", def and tostring(def.Element) or "no def")
		parsed, h = parse("h1=maple_fox/storm_tabby/Normal/Rare/42/+")
		rec = h and h.h1
		def = parsed and defOf("hyb:h1", parsed)
		T.check(rec ~= nil and rec.Elements == nil and def ~= nil and def.Element == "Flame", "client pet attr: field 6 '+' -> no Elements, today's fallback",
			keysText(rec) .. " / " .. tostring(def and def.Element))
		parsed, h = parse("h1=maple_fox/storm_tabby/Normal/Rare/42/Storm+Flame/more")
		rec = h and h.h1
		T.check(rec ~= nil and sameList(rec.Elements, { "Storm", "Flame" }), "client pet attr: a 7th field (a later server) is ignored, field 6 still read", keysText(rec))
		for _, junk in ipairs({ "", "x", ";;", "h1=", "h1=/", 5 }) do
			local _, hj = parse(junk)
			T.check(hj ~= nil and next(hj) == nil, "client pet attr: junk " .. movesLabel(junk) .. " -> no record, no error")
		end

		-- another player's 6-field value still draws their follower
		local Config = moduleAt("shared", "Config")
		local friend = Mock.AddPlayer("AttrFriend", 6202)
		advance(1.0)
		local okRun, errRun = pcall(function()
			local myRoot = KC.root and KC.root()
			if myRoot then
				Mock.Teleport(friend, myRoot.Position + Vector3.new(18, 0, 0))
			end
			friend:SetAttribute("EquippedHybrids", "g6=maple_fox/storm_tabby/Normal/Rare/42/Storm+Flame")
			friend:SetAttribute(Config.Attr.EquippedPets, "hyb:g6")
			advance(2.0)
			local folder = workspace:FindFirstChild("ClientPets")
			local f = folder and folder:FindFirstChild(tostring(friend.UserId))
			local models = {}
			for _, c in ipairs(f and f:GetChildren() or {}) do
				if c:IsA("Model") then
					models[#models + 1] = c
				end
			end
			T.check(#models == 1 and models[1]:GetAttribute("PetId") == "hyb:g6",
				"client pet attr: another player's hybrid with the 6-field value is drawn as their follower", #models .. " models")
		end)
		Mock.RemovePlayer(friend)
		advance(1.0)
		if not okRun then
			error(errRun, 0)
		end
		KC.flushErrors("client_pet_attr_hybrid_elements")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
