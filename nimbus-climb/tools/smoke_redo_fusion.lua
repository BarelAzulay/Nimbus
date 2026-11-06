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

	return S
end

----------------------------------------------------------------------------------------------------
-- client half (Task 3 adds its scenario here)
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
