-- smoke_p3_evolved.lua: the evolved forms of the Phase 3 event pets and the merged developer tools (evolved-pets
-- branch: PetBuilder Evolved = 1 | 2, DevPetShow, DevService pet / pets / evolve / clearpets next to the Phase 3
-- /raid). Loaded by tools/smoke.py in BOTH worlds; ARGS.context picks the half:
--   p3evo_pets          (server, content) the three EventOnly Secret pets (Magma Cub, Rime Wyrmling, Hydralotl) have
--                       bespoke evolved looks that echo their boss, not just their species' generic form: magma cracks,
--                       the basalt volcano and the molten core (Lava Golem); the glacier-crystal crown, frost ferns,
--                       ice horns and glass crystal wings (Frost Wyrm); the hydra heads on the gills and, at the second
--                       evolution, two more big heads (Shadow Hydra). A twin with the same Look but another id gets the
--                       generic form (none of those parts). Every stage builds at High and Low within the evolved part
--                       caps (High 1560 / Low 380, Evolved II High 2000 / Low 520), keeps its wing pairs and aura,
--                       animates without errors or NaN; EvolutionColors gives each its own glow colours; Golden /
--                       Rainbow copies keep the design (within the caps); a fused hybrid with one as its body evolves
--                       with its species' design; no other catalog pet carries the event pets' signature parts
--   p3evo_devtools      (server, booted) the merged developer tools in Studio Play Solo with one player: every
--                       DevService.Commands name has a handler and gets a TextChatCommand ("/" .. name), /raid among
--                       them; /pets, /pets 1 and /pets 2 line up the event pets too; /pet and /evolve find them by a
--                       part of their name; /raid starts a Boss Raid next to the showcase commands (which keep working
--                       while it runs), a second /raid is refused with a reason; /devhelp answers with two side
--                       toasts that list every command and fit a toast (<= 90 characters, info, 8 s); nothing saved
--   client_p3evo_panel  (client, 1920x1080 + 1280x720) the DEV panel lists every button in order (Start Boss Raid and
--                       the showcase among them), docked right, readable, never centred; when its list is taller
--                       than the panel it scrolls (scroll bar, canvas covers the last button, scrolling down brings
--                       "Reset my data" into view); "Start Boss Raid" sends DevCommand("raid"); the two /devhelp toasts
--                       show whole (wrapped inside their cards, not truncated), readable, at the side
--   client_p3evo_lineup (client) EvolutionFx's Phase 4 confetti (opts.Confetti: 20-40 voxel bits at the reveal, all gone at
--                       the end, none without it); DevPetShow builds the /pets 2 lineup with the three event pets in it (Low detail, name
--                       tags) and spawns an event pet's Evolved II at High within its cap
--   client_p3evo_panel_mobile (phone world, 390x844 + 844x390) the same panel and help toast checks on phones (14 px)
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local EVENT_IDS = { "magma_cub", "rime_wyrmling", "hydralotl" }
local CAPS = { [1] = { High = 1560, Low = 380 }, [2] = { High = 2000, Low = 520 } }

local function rgbOf(c)
	return math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)
end

local function sameRGB(c, t)
	local r, g, b = rgbOf(c)
	return math.abs(r - t[1]) <= 1 and math.abs(g - t[2]) <= 1 and math.abs(b - t[3]) <= 1
end

local function partsOf(model)
	local out = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			out[#out + 1] = d
		end
	end
	return out
end

-- parts named after a palette key (PetBuilder names body parts by their key: "Magma", "Magma2", ...)
local function keyed(model, key)
	local n = 0
	for _, p in ipairs(partsOf(model)) do
		local base = string.match(p.Name, "^(.-)%d*$")
		if base == key then
			n = n + 1
		end
	end
	return n
end

local function finiteCF(cf)
	local ok = true
	for _, v in ipairs({ cf:GetComponents() }) do
		if v ~= v or v == math.huge or v == -math.huge then
			ok = false
		end
	end
	return ok
end

----------------------------------------------------------------------------------------------------
-- server world
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local K = _G.K
	local S = {}

	local function req(key)
		if K.M and K.M[key] then
			return K.M[key]
		end
		local inst = K.moduleInstance and K.moduleInstance(key)
		if not inst then
			return nil
		end
		local ok, m = pcall(require, inst)
		return ok and type(m) == "table" and m or nil
	end

	-- the signature parts of each event pet's bespoke design, per stage: { key(s), at least n at High }
	local SIGNS = {
		magma_cub = {
			[1] = { { { "Magma" }, 20, "magma cracks" }, { { "Basalt" }, 2, "the basalt volcano and horns" }, { { "MagmaHot" }, 2, "the glowing crater and core" } },
			[2] = { { { "Magma" }, 20, "magma cracks" }, { { "Basalt" }, 4, "the volcano, its crown of spikes and the shoulder boulders" }, { { "MagmaHot" }, 3, "the erupting crater and core" } },
		},
		rime_wyrmling = {
			[1] = { { { "Crystal", "CrystalDeep" }, 7, "the glacier-crystal crown" }, { { "Frost" }, 6, "frost ferns on the flanks" } },
			[2] = { { { "Crystal", "CrystalDeep" }, 9, "the big crystal crown" }, { { "Frost" }, 6, "frost ferns" }, { { "FrostTip" }, 2, "glowing crown tips" } },
		},
		hydralotl = {
			[1] = { { { "HydraEye" }, 10, "glowing eyes of the six gill heads" }, { { "HydraHead" }, 6, "the gill heads" } },
			[2] = { { { "HydraEye" }, 4, "the glowing eyes of the two big heads" }, { { "HydraHead" }, 6, "the two necks and heads" }, { { "HydraJaw" }, 2, "pale jaws and neck stripes" } },
		},
	}
	local EXPECT_COLORS = {
		magma_cub = { { 255, 112, 30 }, { 255, 176, 56 }, { 255, 92, 24 } },
		rime_wyrmling = { { 70, 186, 255 }, { 150, 232, 255 }, { 226, 248, 255 } },
		hydralotl = { { 176, 255, 96 }, { 120, 255, 196 }, { 196, 255, 110 } },
	}

	local function signCount(model, keys)
		local n = 0
		for _, key in ipairs(keys) do
			n = n + keyed(model, key)
		end
		return n
	end

	local function copyDef(def, newId)
		local out = {}
		for k, v in pairs(def) do
			out[k] = v
		end
		out.Id = newId
		return out
	end

	S.p3evo_pets = guarded("p3evo_pets", function()
		local PB, PC = req("shared/PetBuilder"), req("shared/PetCatalog")
		if not T.check(PB ~= nil and PC ~= nil and type(PB.Build) == "function" and type(PB.MaxEvolution) == "function", "evolved event pets: PetBuilder (Build, MaxEvolution) and PetCatalog load") then
			return
		end
		local holder = Instance.new("Folder")
		holder.Name = "SmokeP3Evolved"
		holder.Parent = workspace
		local events = {}
		if type(PC.EventPets) == "function" then
			for _, def in ipairs(PC.EventPets()) do
				events[def.Id] = def
			end
		end
		for _, id in ipairs(EVENT_IDS) do
			local def = PC.Get and PC.Get(id)
			if T.check(def ~= nil and def.EventOnly == true and events[id] ~= nil, "evolved event pets: " .. id .. " is an EventOnly catalog pet") then
				T.eq(PB.MaxEvolution(def), 2, "evolved event pets: " .. id .. " (Secret) has a second evolution")
				local twin = copyDef(def, id .. "_smoketwin")
				for stage = 1, 2 do
					for _, detail in ipairs({ "High", "Low" }) do
						local label = id .. " stage " .. stage .. " " .. detail
						local ok, m = pcall(PB.Build, def, { Evolved = stage, Detail = detail })
						if T.check(ok and typeof(m) == "Instance" and m.PrimaryPart ~= nil, "evolved event pets: " .. label .. " builds", tostring(m)) then
							m.Parent = holder
							m:PivotTo(CFrame.new(0, 3200, 0))
							local n = #partsOf(m)
							T.check(n >= 150 and n <= CAPS[stage][detail], "evolved event pets: " .. label .. " stays within its part cap (" .. CAPS[stage][detail] .. ")", n .. " parts")
							local w1 = m:FindFirstChild("WingL", true) ~= nil and m:FindFirstChild("WingR", true) ~= nil
							local w2 = m:FindFirstChild("Wing2L", true) ~= nil and m:FindFirstChild("Wing2R", true) ~= nil
							T.check(w1 and (w2 == (stage == 2)), "evolved event pets: " .. label .. " has its wings (a second pair at Evolved II)", "WingL/R " .. tostring(w1) .. ", Wing2L/R " .. tostring(w2))
							if stage == 2 then
								T.check(keyed(m, "Aura") >= 4, "evolved event pets: " .. label .. " has its orbiting element aura", keyed(m, "Aura") .. " aura parts")
							end
							local found = {}
							for _, sign in ipairs(SIGNS[id][stage]) do
								local c = signCount(m, sign[1])
								found[#found + 1] = sign[1][1] .. " " .. c
								local need = (detail == "High") and sign[2] or 1
								T.check(c >= need, "evolved event pets: " .. label .. " shows " .. sign[3], c .. " parts (need " .. need .. ")")
							end
							T.info(label .. ": " .. n .. " parts; " .. table.concat(found, ", "))
							if id == "rime_wyrmling" and detail == "High" then
								local glass = 0
								for _, p in ipairs(partsOf(m)) do
									if string.match(p.Name, "^Wing") and p.Material == Enum.Material.Glass then
										glass = glass + 1
									end
								end
								T.check(glass >= 4, "evolved event pets: " .. label .. " has glacier-crystal (glass) wings", glass .. " glass wing parts")
							end
							if detail == "High" then
								-- animate: no errors, no NaN, the wings flap
								local wing = m:FindFirstChild("WingL", true)
								local c0 = wing and wing.CFrame
								local okA, err, nan, moved = true, nil, false, 0
								for f = 1, 45 do
									okA, err = pcall(PB.Animate, m, f / 30, { Flap = 1 })
									if not okA then
										break
									end
									for _, p in ipairs(partsOf(m)) do
										if not finiteCF(p.CFrame) then
											nan = true
										end
									end
									if wing then
										moved = math.max(moved, (wing.CFrame.Position - c0.Position).Magnitude)
									end
								end
								T.check(okA and not nan and moved > 0.02, "evolved event pets: " .. label .. " animates (no errors, no NaN, the wings flap)", tostring(err or "ok") .. ", wing moved " .. string.format("%.2f", moved))
							end
							m:Destroy()
						end
					end
				end
				-- the same Look under another id: the species' generic evolved form, none of the bespoke parts
				for stage = 1, 2 do
					local ok, m = pcall(PB.Build, twin, { Evolved = stage })
					if T.check(ok and typeof(m) == "Instance", "evolved event pets: a twin of " .. id .. " (same Look, other id) builds stage " .. stage, tostring(m)) then
						local leaks = {}
						for _, sign in ipairs(SIGNS[id][stage]) do
							local c = signCount(m, sign[1])
							if c > 0 then
								leaks[#leaks + 1] = sign[1][1] .. " " .. c
							end
						end
						T.check(#leaks == 0, "evolved event pets: ...the twin gets the generic " .. tostring(def.Look and def.Look.Species) .. " form, so the stage " .. stage .. " design is " .. id .. "'s own", table.concat(leaks, ", "))
						m:Destroy()
					end
				end
				-- the evolution animation's glow colours (EvolutionFx)
				if type(PB.EvolutionColors) == "function" then
					local want = EXPECT_COLORS[id]
					local _, b1 = PB.EvolutionColors(def, 1)
					local a2, b2 = PB.EvolutionColors(def, 2)
					local _, tb1 = PB.EvolutionColors(twin, 1)
					local ta2 = PB.EvolutionColors(twin, 2)
					local function show(c)
						if typeof(c) ~= "Color3" then
							return tostring(c)
						end
						local r, gg, b = rgbOf(c)
						return r .. "," .. gg .. "," .. b
					end
					T.check(typeof(b1) == "Color3" and sameRGB(b1, want[1]) and not sameRGB(tb1, want[1]), "evolved event pets: EvolutionColors(" .. id .. ", 1) glows in its own gem colour", show(b1))
					T.check(typeof(a2) == "Color3" and sameRGB(a2, want[2]) and sameRGB(b2, want[3]) and not sameRGB(ta2, want[2]), "evolved event pets: EvolutionColors(" .. id .. ", 2) uses its own two neon accents", show(a2) .. " / " .. show(b2))
				end
			end
		end
		-- Golden / Rainbow copies keep the design and the caps
		local PK = req("shared/PetKeys")
		if PK and type(PK.Make) == "function" and type(PK.DefOf) == "function" then
			for _, id in ipairs(EVENT_IDS) do
				for _, tier in ipairs({ "Golden", "Rainbow" }) do
					local okD, tdef = pcall(PK.DefOf, PK.Make(id, tier))
					if okD and type(tdef) == "table" then
						for stage = 1, 2 do
							local ok, m = pcall(PB.Build, tdef, { Evolved = stage })
							local n = ok and typeof(m) == "Instance" and #partsOf(m) or -1
							T.check(n > 0 and n <= CAPS[stage].High, "evolved event pets: a " .. tier .. " " .. id .. " evolves (stage " .. stage .. ") within the cap", n .. " parts")
							local sign = SIGNS[id][stage][1]
							T.check(n > 0 and signCount(m, sign[1]) > 0, "evolved event pets: ...and keeps " .. sign[3])
							if ok and typeof(m) == "Instance" then
								m:Destroy()
							end
						end
					else
						T.fail("evolved event pets: PetKeys.DefOf gives a " .. tier .. " " .. id, tostring(tdef))
					end
				end
			end
			-- a fused hybrid with an event pet as its body evolves with its species' design
			if type(PK.HybridKey) == "function" and type(PK.NewHybridId) == "function" then
				local profile = { Hybrids = {} }
				local okU, uid = pcall(PK.NewHybridId, profile, 7)
				if okU and type(uid) == "string" then
					profile.Hybrids[uid] = { Body = "magma_cub", Style = "pip_penguin", Elements = { "Flame", "Frost" }, Name = "Magmguin", Rarity = "Secret", Tier = "Normal" }
					local okH, hdef = pcall(PK.DefOf, PK.HybridKey(uid, "Normal"), profile)
					if okH and type(hdef) == "table" then
						local ok, m = pcall(PB.Build, hdef, { Evolved = 2 })
						local n = ok and typeof(m) == "Instance" and #partsOf(m) or -1
						T.check(n > 0 and n <= CAPS[2].High and keyed(m, "Magma") == 0 and keyed(m, "Basalt") == 0, "evolved event pets: a hybrid with Magma Cub's body evolves with its species' design (no magma cracks), within the cap", n .. " parts")
						if ok and typeof(m) == "Instance" then
							m:Destroy()
						end
					else
						T.info("evolved event pets: no hybrid def from PetKeys (skipped)", tostring(hdef))
					end
				end
			end
		end
		-- the bespoke parts belong to the event pets only
		local leak = T.tally("no other catalog pet's evolved form carries the event pets' signature parts (Magma, Basalt, Frost, HydraEye, HydraHead)")
		for _, def in ipairs(PC.Pets) do
			if not events[def.Id] then
				for stage = 1, PB.MaxEvolution(def) do
					local ok, m = pcall(PB.Build, def, { Evolved = stage })
					if ok and typeof(m) == "Instance" then
						local hits = {}
						for _, key in ipairs({ "Magma", "Basalt", "Frost", "HydraEye", "HydraHead" }) do
							if keyed(m, key) > 0 then
								hits[#hits + 1] = key
							end
						end
						leak:case(#hits == 0, def.Id .. " stage " .. stage .. ": " .. table.concat(hits, ", "))
						m:Destroy()
					end
				end
			end
		end
		leak:report()
		holder:Destroy()
		if K.flushErrors then
			K.flushErrors("p3evo pets")
			K.flushWarnings("p3evo pets")
		end
	end)

	-- Studio Play Solo, one player: the merged developer tools end to end
	S.p3evo_devtools = guarded("p3evo_devtools", function()
		if not K.needBoot() then
			return
		end
		local advance = K.advance
		local Config = K.config()
		local Dev = req("server/Services/DevService")
		local PC, PB = req("shared/PetCatalog"), req("shared/PetBuilder")
		if not T.check(Dev ~= nil and type(Dev.Commands) == "table" and type(Dev.IsAllowed) == "function", "evolved dev tools: DevService loads (Commands, IsAllowed)") then
			return
		end
		-- every command has a handler and a TextChatCommand
		local inst = K.moduleInstance("server/Services/DevService")
		local src = inst and inst.Source or ""
		local handlers = string.match(src, "local HANDLERS = (%b{})") or ""
		local names = {}
		for _, name in ipairs(Dev.Commands) do
			names[name] = true
			T.check(string.find(handlers, "\n%s*" .. name .. "%s*=%s*cmd") ~= nil, "evolved dev tools: '" .. name .. "' (DevService.Commands) has a handler")
		end
		for _, name in ipairs({ "raid", "pet", "pets", "evolve", "clearpets", "devhelp", "petlevel" }) do -- petlevel: Phase 4 (data)
			T.check(names[name] == true, "evolved dev tools: DevService.Commands lists '" .. name .. "'")
		end
		local fnStart = string.find(src, "local function makeChatCommands", 1, true)
		local fnEnd = fnStart and string.find(src, "\nend\n", fnStart, true)
		local body = fnStart and string.sub(src, fnStart, fnEnd or #src) or ""
		local loop = string.match(body, "for _, name in ipairs%(DevService%.Commands%) do(.*)")
		T.check(loop ~= nil and string.find(loop, 'Instance.new("TextChatCommand")', 1, true) ~= nil and string.find(loop, 'PrimaryAlias = "/" .. name', 1, true) ~= nil and string.find(loop, "onChatted", 1, true) ~= nil,
			"evolved dev tools: every DevService.Commands name (" .. #Dev.Commands .. ", /raid among them) gets a TextChatCommand '/<name>' that feeds the chat parser")
		-- the help covers every command
		local okEvt = req("server/Services/EventService") ~= nil
		local BS = req("server/Services/BattleService")
		local ES = req("server/Services/EventService")

		local saved = { Studio = Mock.Options.Studio, Auto = Config.Dev and Config.Dev.StudioAutoGrant }
		Mock.Options.Studio = true
		if Config.Dev then
			Config.Dev.StudioAutoGrant = false
		end
		local p = Mock.AddPlayer("EvoSolo", 986001)
		advance(1.2)
		local function clearRaid()
			if BS and type(BS.GetRaidStatus) == "function" and BS.GetRaidStatus() then
				if ES and type(ES.EndNow) == "function" then
					pcall(ES.EndNow, "BossRaid")
				elseif type(BS.EndRaid) == "function" then
					pcall(BS.EndRaid, "smoke")
				end
				K.waitFor(function()
					return BS.GetRaidStatus() == nil
				end, 10)
			end
		end
		local ok, err = pcall(function()
			T.check(Dev.IsAllowed(p) == true, "evolved dev tools: Studio Play Solo - the only player is a developer")
			local DS = K.mod("DataService")
			local function snapshot()
				local prof = DS.GetProfile(p) or {}
				local n = 0
				for _ in pairs(prof.Pets or {}) do
					n = n + 1
				end
				return tostring(prof.Tokens) .. "/" .. n .. "/" .. tostring(prof.Gems) .. "/" .. tostring(prof.Cash)
			end
			local before = snapshot()
			local function chat(text)
				advance(0.6)
				local mark = K.logSize()
				Mock.FireSignal(p, "Chatted", text)
				advance(0.2)
				return mark
			end
			local function shows(mark)
				local out = {}
				for _, e in ipairs(K.remotesFor("DevPetShow", p.UserId, mark)) do
					out[#out + 1] = { action = e.args[1], payload = e.args[2] or {} }
				end
				return out
			end
			local function toasts(mark)
				local out = {}
				for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark)) do
					local text = tostring(e.args[1])
					if text:sub(1, 4) == "DEV:" then
						out[#out + 1] = { text = text, kind = e.args[2], duration = e.args[3] }
					end
				end
				return out
			end
			local function last(mark)
				local list = toasts(mark)
				return list[#list] or { text = "(no DEV toast)" }
			end
			local function hasAll(list, ids)
				local set = {}
				for _, id in ipairs(list or {}) do
					set[id] = true
				end
				for _, id in ipairs(ids) do
					if not set[id] then
						return false, id
					end
				end
				return true
			end
			local twos = 0
			for _, def in ipairs(PC.Pets) do
				if PB.MaxEvolution(def) == 2 then
					twos = twos + 1
				end
			end
			clearRaid()
			-- /pets, /pets 1, /pets 2 include the event pets
			for _, stage in ipairs({ 0, 1, 2 }) do
				local line = (stage == 0) and "/pets" or ("/pets " .. stage)
				local mark = chat(line)
				local list = shows(mark)
				local e = list[1] or { payload = {} }
				local okAll, missing = hasAll(e.payload.PetIds, EVENT_IDS)
				local want = (stage == 2) and twos or #PC.Pets
				T.check(#list == 1 and e.action == "Lineup" and e.payload.Stage == stage and okAll and #(e.payload.PetIds or {}) == want,
					"evolved dev tools: '" .. line .. "' lines up " .. want .. " pets with the three event pets among them", tostring(missing or "") .. " " .. #(e.payload.PetIds or {}) .. " ids")
			end
			-- /raid next to the showcase
			local mark = chat("/raid")
			local raidToast = last(mark)
			local running = BS and type(BS.GetRaidStatus) == "function" and BS.GetRaidStatus() ~= nil
			T.check(running and raidToast.text:find("raid", 1, true) ~= nil and raidToast.kind ~= "bad" and #raidToast.text <= 90,
				"evolved dev tools: '/raid' in chat starts a Boss Raid, answered with a side toast", raidToast.text)
			mark = chat("/pet magma 2")
			local e = shows(mark)[1] or { payload = {} }
			T.check(e.action == "Spawn" and e.payload.PetId == "magma_cub" and e.payload.Stage == 2, "evolved dev tools: while the raid runs '/pet magma 2' still spawns Magma Cub (Evolved II)", tostring(e.payload.PetId) .. " " .. tostring(e.payload.Stage))
			mark = chat("/pet hydra 1")
			e = shows(mark)[1] or { payload = {} }
			T.check(e.action == "Spawn" and e.payload.PetId == "hydralotl" and e.payload.Stage == 1, "evolved dev tools: '/pet hydra 1' finds the Hydralotl by a part of its name", tostring(e.payload.PetId))
			mark = chat("/evolve rime")
			local st = (shows(mark)[1] or { payload = {} }).payload.Steps or {}
			T.check(#st == 2 and st[1].PetId == "rime_wyrmling" and st[1].From == 0 and st[2].To == 2, "evolved dev tools: '/evolve rime' plays the Rime Wyrmling's whole line (normal -> evolved -> evolved II)", #st .. " steps")
			mark = chat("/raid")
			local again = last(mark)
			T.check(again.kind == "bad" and #again.text > 6, "evolved dev tools: a second '/raid' while one runs is refused with a reason", again.text)
			T.check(BS == nil or BS.GetRaidStatus() ~= nil, "evolved dev tools: ...and the running raid goes on")
			mark = chat("/clearpets")
			T.check((shows(mark)[1] or {}).action == "Clear", "evolved dev tools: '/clearpets' clears the showcase while the raid runs")
			-- /devhelp: two readable side toasts that list every command
			mark = chat("/devhelp")
			local help = toasts(mark)
			local joined, fits = {}, true
			for _, t in ipairs(help) do
				joined[#joined + 1] = t.text
				if #t.text > 90 or t.kind ~= "info" or (tonumber(t.duration) or 0) < 6 then
					fits = false
				end
			end
			local all = table.concat(joined, " ")
			local missing = {}
			for _, name in ipairs(Dev.Commands) do
				if name ~= "tutorial" and not string.find(all, "/" .. name, 1, true) then
					missing[#missing + 1] = name
				end
			end
			T.check(#help == 2 and fits, "evolved dev tools: '/devhelp' answers with two info side toasts that fit a toast (<= 90 characters, >= 6 s)", #help .. " toasts: " .. all)
			T.check(#missing == 0, "evolved dev tools: ...listing every command (the showcase, /raid and the rest)", table.concat(missing, ", "))
			T.eq(snapshot(), before, "evolved dev tools: the showcase, /raid and /devhelp change no saved data")
		end)
		clearRaid()
		Mock.Options.Studio = saved.Studio
		if Config.Dev then
			Config.Dev.StudioAutoGrant = saved.Auto
		end
		K.removePlayers({ p })
		if not ok then
			error(err, 0)
		end
		T.check(okEvt or BS ~= nil, "evolved dev tools: EventService or BattleService present for /raid")
		K.flushErrors("p3evo dev tools")
		K.flushWarnings("p3evo dev tools")
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client worlds
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local KC = _G.KC
	local S = {}
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer

	local function advance(seconds)
		Mock.Advance(seconds)
	end
	local function playerGui()
		return LocalPlayer:FindFirstChild("PlayerGui")
	end
	local function named(root, name)
		if not root then
			return nil
		end
		for _, d in ipairs(root:GetDescendants()) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end
	local function shown(obj)
		return obj ~= nil and KC.isShown(obj)
	end
	local function scaleOf(inst)
		local scale = 1
		local cur = inst
		while cur and cur ~= game do
			if cur:IsA("GuiObject") then
				for _, c in ipairs(cur:GetChildren()) do
					if c:IsA("UIScale") and c.Name ~= "FxScale" then
						scale = scale * c.Scale
					end
				end
			end
			cur = cur.Parent
		end
		return scale
	end
	local function textPx(d)
		return d.TextScaled and d.AbsoluteSize.Y or d.TextSize * scaleOf(d)
	end
	local function centre(inst)
		return inst.AbsolutePosition + inst.AbsoluteSize / 2
	end

	-- run on its own (smoke.py --only), the world may not have booted the client yet
	local function ensureBooted()
		local RS = game:GetService("ReplicatedStorage")
		if not RS:FindFirstChild("Remotes") then
			local Config = require(Mock.GetPath(ROOTS["shared"] .. "/Config"))
			local folder = Instance.new("Folder")
			folder.Name = "Remotes"
			for _, n in ipairs(Config.Remotes) do
				local r = Instance.new("RemoteEvent")
				r.Name = n
				r.Parent = folder
			end
			folder.Parent = RS
		end
		if not playerGui():FindFirstChild("NimbusNotify") then
			Mock.RunScript(Mock.GetPath(ROOTS["client"] .. "/Main"))
			advance(3)
		end
	end

	-- the panel's buttons in order (DevController): id, label
	local BUTTONS = {
		{ "allpets", "Give all pets" }, { "tokens" }, { "cash" }, { "gems" }, { "skiptutorial", "Skip tutorial" },
		{ "raid", "Start Boss Raid" }, { "evolveall", "Evolve every pet" }, { "pets0", "Show all pets" },
		{ "pets1", "Show evolved pets" }, { "pets2", "Show Evolved II pets" }, { "clearpets", "Clear pet show" },
		{ "reset", "Reset my data" },
	}

	-- the two /devhelp toasts as DevService writes them (read from its source; fallbacks if it moved)
	local function helpTexts()
		local out = {}
		local ok, inst = pcall(Mock.GetPath, ROOTS["server"] .. "/Services/DevService")
		local src = ok and inst and inst.Source or ""
		local body = string.match(src, "local function cmdHelp%(player%)(.-)\nend\n") or ""
		local first = string.match(body, 'notify%(player, "(DEV:[^"]*)"')
		local lines = {}
		for text in string.gmatch(body, 'return true, "([^"]*)"') do
			lines[#lines + 1] = text
		end
		out[1] = first or "DEV: /pet <name> [0-2]  /pets [0-2]  /evolve <name|all> [1-2]  /clearpets"
		local second = lines[1] or "/allpets /tokens N /cash N /gems N /reset /tutorial /skiptutorial /raid /devhelp"
		for _, l in ipairs(lines) do
			if #l > #second then
				second = l -- the longest variant
			end
		end
		out[2] = "DEV: " .. second
		return out, first ~= nil and #lines > 0
	end

	-- bothFit: the screen has room for both toasts at once (NotifyController trims the toast column to the screen
	-- height, the oldest leaving first); on a short landscape phone only the newest one stays, which is reported
	local function checkHelpToasts(label, floorPx, bothFit)
		local texts, fromSource = helpTexts()
		T.check(fromSource, label .. ": the /devhelp texts are read from DevService (cmdHelp)")
		for _, t in ipairs(texts) do
			KC.toClient("Notify", t, "info", 8)
		end
		advance(0.8)
		local notify = playerGui():FindFirstChild("NimbusNotify")
		local vp = Mock.Viewport
		for i, t in ipairs(texts) do
			local labelObj = nil
			for _, d in ipairs(notify and notify:GetDescendants() or {}) do
				if d:IsA("TextLabel") and d.Name == "Text" and d.Text == t and shown(d) then
					labelObj = d
				end
			end
			local present = labelObj ~= nil
			if not present and i < #texts and not bothFit then
				T.info("*" .. label .. ": the screen is too short for both /devhelp toasts: toast " .. i .. " (" .. string.sub(t, 1, 30) .. "...) is pushed out by the newer one at once")
			elseif T.check(present, label .. ": /devhelp toast " .. i .. " shows its whole text (not truncated)", t) then
				local bounds = labelObj.TextBounds
				local size = labelObj.AbsoluteSize
				T.check(labelObj.TextWrapped and bounds.X <= size.X + 1 and bounds.Y <= size.Y + 1, label .. ": ...wrapped inside its card", string.format("text %dx%d in %dx%d", bounds.X, bounds.Y, size.X, size.Y))
				T.check(textPx(labelObj) >= floorPx - 0.01, label .. ": ...readable (>= " .. floorPx .. " px)", string.format("%.1f px", textPx(labelObj)))
				local c = centre(labelObj)
				T.check(c.X > vp.X * 0.6 and labelObj.AbsolutePosition.X + size.X <= vp.X + 1 and labelObj.AbsolutePosition.Y >= -1 and labelObj.AbsolutePosition.Y + size.Y <= vp.Y + 1,
					label .. ": ...at the right side, fully on screen (never in the middle)", string.format("centre %d,%d", c.X, c.Y))
			end
		end
		advance(9)
	end

	local function checkPanel(label, floorPx, clickRaid)
		local Dev = require(Mock.GetPath(ROOTS["client"] .. "/Controllers/DevController"))
		local g = playerGui():FindFirstChild("NimbusDev")
		if not T.check(type(Dev) == "table" and type(Dev.Open) == "function" and g ~= nil, label .. ": the DEV tools are on (NimbusDev)") then
			return
		end
		Dev.Open()
		advance(0.8)
		local panel = named(g, "DevPanel")
		if not T.check(shown(panel), label .. ": the 'Developer tools' panel opens") then
			return
		end
		-- every button, in order
		local list = named(g, "List")
		local prevY, order, missing = -math.huge, true, {}
		for _, b in ipairs(BUTTONS) do
			local button = named(g, "Dev_" .. b[1])
			if not (button and button.Visible) or (b[2] and button.Text ~= b[2]) then
				missing[#missing + 1] = b[1]
			else
				if button.AbsolutePosition.Y <= prevY then
					order = false
				end
				prevY = button.AbsolutePosition.Y
			end
		end
		T.check(#missing == 0 and order, label .. ": the panel lists every button in order (Start Boss Raid and the pet showcase among them)", table.concat(missing, ", "))
		-- docked right, never centred, readable
		local vp = Mock.Viewport
		local p0, ps = panel.AbsolutePosition, panel.AbsoluteSize
		T.check(p0.X + ps.X <= vp.X + 1 and p0.X + ps.X >= vp.X - 40 and p0.Y >= -1 and p0.Y + ps.Y <= vp.Y + 1, label .. ": the panel is docked to the right edge, fully on screen", string.format("%d,%d %dx%d", p0.X, p0.Y, ps.X, ps.Y))
		local small = {}
		for _, b in ipairs(BUTTONS) do
			local button = named(g, "Dev_" .. b[1])
			if button and textPx(button) < floorPx - 0.01 then
				small[#small + 1] = string.format("%s %.1f px", b[1], textPx(button))
			end
		end
		T.check(#small == 0, label .. ": every button label is readable (>= " .. floorPx .. " px)", table.concat(small, ", "))
		-- the list scrolls when it is taller than the panel
		if T.check(list ~= nil and list:IsA("ScrollingFrame"), label .. ": the buttons sit in a ScrollingFrame") then
			local first, lastB = named(g, "Dev_allpets"), named(g, "Dev_reset")
			local contentH = (lastB.AbsolutePosition.Y + lastB.AbsoluteSize.Y) - first.AbsolutePosition.Y
			local visibleH = list.AbsoluteSize.Y
			local canvasOk = list.AutomaticCanvasSize == Enum.AutomaticSize.Y or list.CanvasSize.Y.Offset >= contentH
			T.check(canvasOk and list.ScrollingEnabled and list.ScrollingDirection ~= Enum.ScrollingDirection.X, label .. ": its canvas grows with the buttons and scrolls vertically")
			if contentH > visibleH + 1 then
				T.check(list.ScrollBarThickness >= 4, label .. ": the list is taller than the panel: a scroll bar shows", "thickness " .. tostring(list.ScrollBarThickness))
				list.CanvasPosition = Vector2.new(0, math.max(0, contentH - visibleH + 24))
				advance(0.2)
				local bottom = lastB.AbsolutePosition.Y + lastB.AbsoluteSize.Y
				T.check(bottom <= list.AbsolutePosition.Y + visibleH + 1 and lastB.AbsolutePosition.Y >= list.AbsolutePosition.Y - 1, label .. ": scrolling down brings 'Reset my data' into view",
					string.format("button %d-%d, list %d-%d", lastB.AbsolutePosition.Y, bottom, list.AbsolutePosition.Y, list.AbsolutePosition.Y + visibleH))
				list.CanvasPosition = Vector2.new(0, 0)
				advance(0.2)
			else
				T.ok(label .. ": the whole list fits the panel (no scrolling needed)", string.format("%d of %d px", contentH, visibleH))
			end
			T.info(string.format("%s: panel %dx%d, list %d px tall, buttons %d px", label, ps.X, ps.Y, visibleH, contentH))
		end
		if clickRaid then
			local raid = named(g, "Dev_raid")
			list.CanvasPosition = Vector2.new(0, math.max(0, raid.AbsolutePosition.Y - list.AbsolutePosition.Y - 10))
			advance(0.6) -- (the panel ignores taps for 0.4 s after it opens)
			local mark = #Mock.RemoteLog
			Mock.Click(raid)
			advance(0.4)
			local calls = KC.serverCalls("DevCommand", mark)
			local c = calls[#calls]
			T.check(#calls == 1 and c.args[1] == "raid" and c.args[2] == nil, label .. ": 'Start Boss Raid' sends DevCommand('raid')", c and (tostring(c.args[1]) .. " x" .. #calls) or "nothing sent")
			list.CanvasPosition = Vector2.new(0, 0)
		end
		Dev.Close()
		advance(0.4)
	end

	S.client_p3evo_panel = guarded("client_p3evo_panel", function()
		local ok = pcall(function()
			return require(Mock.GetPath(ROOTS["client"] .. "/Controllers/DevController"))
		end)
		if not T.check(ok, "evolved dev panel: DevController loads") then
			return
		end
		ensureBooted()
		playerGui():SetAttribute("NC_Dev", true)
		playerGui():SetAttribute("NC_DevTutorial", nil)
		for _, size in ipairs({ { 1920, 1080, 18, true }, { 1280, 720, 14, false } }) do
			Mock.SetViewport(size[1], size[2])
			advance(1.2)
			local label = "evolved dev panel " .. size[1] .. "x" .. size[2]
			checkPanel(label, size[3], size[4])
			checkHelpToasts(label, (size[2] >= 1000) and 15 or 14, true)
		end
		Mock.SetViewport(1920, 1080)
		playerGui():SetAttribute("NC_Dev", nil)
		advance(0.6)
		KC.flushErrors("p3evo panel")
		KC.flushWarnings("p3evo panel")
	end)

	S.client_p3evo_panel_mobile = guarded("client_p3evo_panel_mobile", function()
		local ok = pcall(function()
			return require(Mock.GetPath(ROOTS["client"] .. "/Controllers/DevController"))
		end)
		if not T.check(ok, "evolved dev panel (phone): DevController loads") then
			return
		end
		ensureBooted()
		playerGui():SetAttribute("NC_Dev", true)
		-- (Phase 5: /devhelp's first toast grew with '/berries [n]'; on a 390x844 phone the toast column now keeps only the
		-- newest of the two at once, like the landscape phone: reported, not a failure)
		for _, size in ipairs({ { 390, 844, false }, { 844, 390, false } }) do
			Mock.SetViewport(size[1], size[2])
			advance(1.2)
			local label = "evolved dev panel phone " .. size[1] .. "x" .. size[2]
			checkPanel(label, 14, false)
			checkHelpToasts(label, 14, size[3])
		end
		Mock.SetViewport(390, 844)
		playerGui():SetAttribute("NC_Dev", nil)
		advance(0.6)
		KC.flushErrors("p3evo panel phone")
		KC.flushWarnings("p3evo panel phone")
	end)

	S.client_p3evo_lineup = guarded("client_p3evo_lineup", function()
		local okShow, Show = pcall(require, Mock.GetPath(ROOTS["client"] .. "/Controllers/DevPetShow"))
		local PC = require(Mock.GetPath(ROOTS["shared"] .. "/PetCatalog"))
		local PB = require(Mock.GetPath(ROOTS["shared"] .. "/PetBuilder"))
		if not T.check(okShow and type(Show) == "table" and type(Show.Handle) == "function", "evolved lineup: DevPetShow loads", tostring(Show)) then
			return
		end
		ensureBooted()
		pcall(Show.Init)
		Mock.SetViewport(1920, 1080)
		Show.Handle("Clear", {})
		advance(0.3)
		local ids = {}
		for _, def in ipairs(PC.Pets) do
			if PB.MaxEvolution(def) == 2 then
				ids[#ids + 1] = def.Id
			end
		end
		Show.Handle("Lineup", { Stage = 2, PetIds = ids })
		local done = Mock.AdvanceUntil(function()
			return not Show.Busy() and Show.Count() >= #ids
		end, 40)
		T.check(done ~= false and Show.Count() == #ids, "evolved lineup: '/pets 2' builds all " .. #ids .. " Evolved II pets", Show.Count() .. " built")
		local folder = Show.Folder and Show.Folder()
		for _, id in ipairs(EVENT_IDS) do
			local m = folder and folder:FindFirstChild("DevPet_" .. id .. "_2")
			local n = m and #partsOf(m) or -1
			T.check(m ~= nil and n > 0 and n <= CAPS[2].Low, "evolved lineup: " .. id .. " stands in the lineup (Low detail, <= " .. CAPS[2].Low .. " parts)", n .. " parts")
			local tag = m and m:FindFirstChildWhichIsA("BillboardGui", true)
			T.check(tag ~= nil, "evolved lineup: ...with its name tag")
		end
		Show.Handle("Clear", {})
		advance(0.3)
		Show.Handle("Spawn", { PetId = "magma_cub", Stage = 2 })
		advance(0.5)
		folder = Show.Folder and Show.Folder()
		local m = folder and folder:FindFirstChild("DevPet_magma_cub_2")
		local n = m and #partsOf(m) or -1
		T.check(m ~= nil and n > CAPS[2].Low and n <= CAPS[2].High and keyed(m, "Magma") > 0, "evolved lineup: '/pet magma 2' spawns Magma Cub's Evolved II at High detail, cracks and all", n .. " parts")
		Show.Handle("Clear", {})
		advance(0.3)
		T.eq(Show.Count(), 0, "evolved lineup: Clear removes the showcase pets")

		-- EvolutionFx (Phase 4, careui): the game's EVOLVE moment adds voxel confetti (opts.Confetti); the showcase keeps none
		local okFx, Fx = pcall(require, Mock.GetPath(ROOTS["client"] .. "/Controllers/EvolutionFx"))
		if T.check(okFx and type(Fx) == "table" and type(Fx.Play) == "function" and type(Fx.Duration) == "function", "evolved fx: EvolutionFx loads") then
			local def = PC.Get("magma_cub")
			local function play(confetti)
				local holder = Instance.new("Folder")
				holder.Name = "EvoFxTest"
				holder.Parent = workspace
				local a, b = PB.Build(def, { Detail = "Low" }), PB.Build(def, { Detail = "Low", Evolved = 1 })
				local pose = CFrame.new(420, 330, 420)
				a:PivotTo(pose)
				a.Parent = holder
				local doneModel = nil
				local h = Fx.Play(a, b, pose, { Parent = holder, Stage = 1, Confetti = confetti, OnDone = function(model)
					doneModel = model
				end })
				advance(2.0 + 0.38 + 0.3) -- charge + burst + a bit of the reveal
				local bits = 0
				for _, d in ipairs(holder:GetDescendants()) do
					if d:IsA("BasePart") and d.Name == "EvolveConfetti" then
						bits = bits + 1
					end
				end
				advance(Fx.Duration(1))
				local fxLeft = holder:FindFirstChild("EvolutionFx")
				return bits, h, doneModel, fxLeft, holder
			end
			local bits, h, model, fxLeft, holder = play(true)
			T.check(bits >= 20 and bits <= 40, "evolved fx: Confetti = true bursts 20-40 voxel confetti bits at the reveal", tostring(bits))
			T.check(h.Done and model ~= nil and fxLeft == nil, "evolved fx: ...and every effect part is gone at the end (OnDone gets the evolved pet)")
			holder:Destroy()
			bits, h, model, fxLeft, holder = play(nil)
			T.eq(bits, 0, "evolved fx: without Confetti (the developer showcase) there is none")
			holder:Destroy()
			T.eq(Fx.Count(), 0, "evolved fx: nothing left playing")
		end
		KC.flushErrors("p3evo lineup")
		KC.flushWarnings("p3evo lineup")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
