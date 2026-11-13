-- smoke_kitb_fx.lua: the kit-b FX lane (X1-X2 of .superpowers/slop-audit/round3/BUILD_PLAN.md; branch kitb-fx).
-- Loaded by tools/smoke.py in both worlds, ARGS.context picks the half. Each wave adds its scenarios here and their
-- names on the FX line of tools/smoke.py (that line only).
--
-- X1 "FxSprites and the stock-sprite sweep" (rejects audit finding 1 = plan finding 8):
--   fxsprites_roles_resolve          (server, pure) every FxSprites role (the plan's Sparkle, Puff, Glow, Ember, Dust,
--                                    Droplet, Wisp and the element / fountain ones) maps to its fx_* sheet, a positive id in
--                                    shared/TextureIds; Texture(role) = "rbxassetid://<id>"; Apply sets that texture and
--                                    the sheet's flipbook (Grid4x4, blender/vfx/textures.json mode + fps, a random start on
--                                    Loop sheets); RoleOf reads it back; Strip("Dash") = fx_speedlines; Strip("Dots" /
--                                    "Flow" / "Sheet") (guide trail, fountain streaks / core) = their own strip or the old
--                                    stock texture, never "" and never fx_speedlines; an unknown role falls back to
--                                    Sparkle; no role outside the list
--   fxsprites_fallback_when_id_zero  (server, pure) with an id of 0 or a missing key the role's old built-in texture comes
--                                    back with the flipbook off (also on an emitter that had one), Strip("Dash") gives ""
--                                    (a plain Beam), Strip("Dots" / "Flow" / "Sheet") their old stock texture, RoleOf
--                                    still knows it; _Deps(false) restores the real ids
--   fx_no_stock_particles_server     (server, booted) every ParticleEmitter in the booted game plus the builders' extras
--                                    (evolved pets of every element, Legendary / Golden / Rainbow flair, every token
--                                    palette, every home station level, a boss in its High tier) wears an FxSprites
--                                    sprite: no empty Texture (the engine default sparkle), no rbxasset particle path;
--                                    shared + server sources hold no rbxasset://textures/particles path outside
--                                    FxSprites.lua, and every emitter they create goes through FxSprites
--   fx_no_stock_particles_client     (client) the same for the client world's emitters and the client sources
-- The OBBY lane's files (CourseBuilder, HazardService: O3) and their course folders are listed as pending, not failed;
-- O3 removes them from PENDING_O3. AttackFx plays the fx_* sheets through its own engine: the walks accept any fx_*
-- sheet on its Grid4x4 flipbook, and its creation site is not scanned (its scenarios check every played layer).
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local fmt = string.format

-- re-stated from blender/vfx/textures.json (never read from the module under test): role -> { key, mode, fps }
local WANT = {
	Sparkle = { "fx_sparkle", "Loop", 16 },
	Puff = { "fx_smoke", "OneShot", 16 },
	Glow = { "fx_glow", "Loop", 12 },
	Ember = { "fx_embers", "Loop", 20 },
	Dust = { "fx_dust", "OneShot", 16 },
	Droplet = { "fx_droplets", "OneShot", 16 },
	Wisp = { "fx_wisps", "Loop", 16 },
	Snow = { "fx_snow", "Loop", 12 },
	Spark = { "fx_sparks", "Loop", 24 },
	Leaf = { "fx_leaves", "Loop", 16 },
	Star = { "fx_stars", "Loop", 16 },
	Ring = { "fx_ripple", "OneShot", 16 },
}
local PLAN_ROLES = { "Sparkle", "Puff", "Glow", "Ember", "Dust", "Droplet", "Wisp" }
local STOCK = "rbxasset://textures/particles/"
-- X1 review: the Beam strips that must stay visible (strip -> { key, stock fallback while the id is 0 / missing }).
-- fx_speedlines (Dash) is ~93% empty hairlines: never the guide trail or the fountain falls.
local WANT_STRIPS = {
	Dots = { "fx_dots", STOCK .. "sparkles_main.dds" }, -- the tutorial guide trail
	Flow = { "fx_waterflow", STOCK .. "explosion01_implosion_main.dds" }, -- the fountain fall streaks
	Sheet = { "fx_watersheet", STOCK .. "explosion01_implosion_main.dds" }, -- the fountain fall core
}
-- the OBBY lane's emitter files (BUILD_PLAN O3 moves them onto FxSprites)
local PENDING_O3 = { CourseBuilder = true, HazardService = true }
-- textured by their own engine (AttackFx tuneEmitter: every played layer's sheet; smoke_p7vfx_client checks them)
local OWN_ENGINE = { AttackFx = true }
local NEAR_LINES = 40 -- an emitter creation must reach FxSprites within this many lines

local function sortedKeys(t)
	local out = {}
	for k in pairs(t) do
		out[#out + 1] = k
	end
	table.sort(out)
	return out
end

local function ancestorNamed(inst, pattern)
	local p = inst.Parent
	while p and p ~= game do
		if tostring(p.Name):find(pattern) then
			return p
		end
		p = p.Parent
	end
	return nil
end

-- every ParticleEmitter under `roots` whose Texture is neither an FxSprites sprite nor one of the game's fx_* sheets
-- (AttackFx plays them all) on its Grid4x4 flipbook: bad, pending (a course folder)
local function walkEmitters(FX, roots, Ids)
	local sheets = {}
	for key, id in pairs(Ids or {}) do
		if type(key) == "string" and key:find("^fx_") and type(id) == "number" and id > 0 then
			sheets["rbxassetid://" .. tostring(id)] = key
		end
	end
	local bad, pending, count = {}, {}, 0
	for _, root in ipairs(roots) do
		local list = { root }
		for _, d in ipairs(root:GetDescendants()) do
			list[#list + 1] = d
		end
		for _, d in ipairs(list) do
			if d:IsA("ParticleEmitter") then
				count = count + 1
				local tex = tostring(d.Texture)
				local role = FX.RoleOf(tex) or sheets[tex]
				local ownSheet = role ~= nil and tex:find("^rbxassetid://") ~= nil
				local flip = ownSheet and d.FlipbookLayout == Enum.ParticleFlipbookLayout.Grid4x4
				if not (role and (flip or not ownSheet)) then
					local line = d:GetFullName() .. " = '" .. tex .. "'" .. ((role and not flip) and " (no Grid4x4 flipbook)" or "")
					if ancestorNamed(d, "^Course_") then
						pending[#pending + 1] = line
					else
						bad[#bad + 1] = line
					end
				end
			end
		end
	end
	return bad, pending, count
end

-- the role names a source line passes to FxSprites (Apply(..., "Role"), `Sprite = "Role"`, Strip("Role"))
local function rolesOn(code)
	local out = {}
	for role in code:gmatch('Sprite = "(%a+)"') do
		out[#out + 1] = { role, "Roles" }
	end
	local at = code:find(".Apply(", 1, true)
	if at then
		for role in code:sub(at):gmatch('"(%a+)"%)') do
			if role ~= "ParticleEmitter" then
				out[#out + 1] = { role, "Roles" }
			end
		end
	end
	for role in code:gmatch('Strip%("(%a+)"%)') do
		out[#out + 1] = { role, "Strip" }
	end
	return out
end

-- shared / server / client sources: stock paths, emitters created without FxSprites, role names FxSprites does not know
local function scanSources(roots, FX)
	local stock, bare, pending, unknown, files = {}, {}, {}, {}, 0
	for _, root in ipairs(roots) do
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("LuaSourceContainer") then
				local src = tostring(d.Source or "")
				local name = d.Name
				if src ~= "" and name ~= "FxSprites" then
					files = files + 1
					local lines = {}
					for line in (src .. "\n"):gmatch("([^\n]*)\n") do
						lines[#lines + 1] = line
					end
					for i, line in ipairs(lines) do
						local code = line:gsub("%-%-.*$", "")
						local where = fmt("%s:%d", d:GetFullName(), i)
						if code:find("FxSprites", 1, true) or code:find("Sprite = ", 1, true) then
							for _, r in ipairs(rolesOn(code)) do
								local known = (r[2] == "Strip") and (FX.Strip(r[1]) ~= "") or FX.Roles[r[1]] ~= nil
								if not known then
									unknown[#unknown + 1] = where .. " " .. r[1]
								end
							end
						end
						if code:find("rbxasset://textures/particles", 1, true) then
							if PENDING_O3[name] then
								pending[#pending + 1] = where
							else
								stock[#stock + 1] = where
							end
						end
						if not OWN_ENGINE[name] and (code:find('Instance.new("ParticleEmitter")', 1, true) or code:find('("ParticleEmitter", {', 1, true)) then
							local found = false
							for j = i, math.min(#lines, i + NEAR_LINES) do
								if lines[j]:gsub("%-%-.*$", ""):find("FxSprites", 1, true) then
									found = true
									break
								end
							end
							if not found then
								if PENDING_O3[name] then
									pending[#pending + 1] = where .. " (no FxSprites)"
								else
									bare[#bare + 1] = where
								end
							end
						end
					end
				end
			end
		end
	end
	return stock, bare, pending, unknown, files
end

local function report(label, bad, pending, count, what)
	T.check(#bad == 0, label .. ": every " .. what .. " wears an FxSprites sprite (" .. count .. " checked)",
		table.concat(bad, "; ", 1, math.min(#bad, 12)) .. (#bad > 12 and fmt(" ... (%d in all)", #bad) or ""))
	if #pending > 0 then
		T.info("*" .. label .. ": pending the OBBY lane (O3): " .. #pending, table.concat(pending, "; ", 1, math.min(#pending, 6)))
	end
end

local function rootsOf(names)
	local out = {}
	for _, n in ipairs(names) do
		local path = ROOTS and ROOTS[n]
		local inst = path and Mock.GetPath(path)
		if inst then
			out[#out + 1] = inst
		end
	end
	return out
end

local function requireShared(name)
	local path = ROOTS and ROOTS["shared"]
	local inst = path and Mock.GetPath(path .. "/" .. name)
	if not inst then
		return nil
	end
	local ok, mod = pcall(require, inst)
	return ok and type(mod) == "table" and mod or nil
end

local function fxModule()
	local FX = requireShared("FxSprites")
	if not T.check(FX ~= nil and type(FX.Apply) == "function" and type(FX.Texture) == "function" and type(FX.RoleOf) == "function"
		and type(FX.Roles) == "table", "shared/FxSprites loads (Roles, Texture, Apply, RoleOf)", "src/shared/FxSprites.lua is missing") then
		return nil
	end
	return FX
end

local function sourceChecks(label, rootNames, FX)
	local stock, bare, pending, unknown, files = scanSources(rootsOf(rootNames), FX)
	T.check(files > 0, label .. ": the sources are mounted (" .. files .. " scripts)")
	T.check(#stock == 0, label .. ": no rbxasset://textures/particles path outside FxSprites.lua", table.concat(stock, ", "))
	T.check(#bare == 0, label .. ": every ParticleEmitter created in the sources goes through FxSprites (within " .. NEAR_LINES .. " lines)",
		table.concat(bare, ", "))
	T.check(#unknown == 0, label .. ": every role name passed to FxSprites is one it knows", table.concat(unknown, ", "))
	if #pending > 0 then
		T.info("*" .. label .. ": source sites pending the OBBY lane (O3): " .. #pending, table.concat(pending, ", "))
	end
end

local function serverScenarios()
	local S = {}
	local K = _G.K

	S.fxsprites_roles_resolve = guarded("fxsprites_roles_resolve", function()
		local FX = fxModule()
		local Ids = requireShared("TextureIds")
		if not FX or not T.check(type(Ids) == "table", "shared/TextureIds loads") then
			return
		end
		for _, role in ipairs(PLAN_ROLES) do
			T.check(FX.Roles[role] ~= nil, "FxSprites: the plan's role " .. role .. " exists")
		end
		local extra = {}
		for _, role in ipairs(sortedKeys(FX.Roles)) do
			if not WANT[role] then
				extra[#extra + 1] = role
			end
		end
		T.check(#extra == 0, "FxSprites: no role outside the tested list", table.concat(extra, ", "))
		local resolve = T.tally("FxSprites: every role maps to its fx_* sheet with a positive TextureIds id")
		local applied = T.tally("FxSprites.Apply: the sheet's texture and flipbook (Grid4x4, mode, fps, random start on Loop)")
		local readBack = T.tally("FxSprites.RoleOf reads every applied texture back to its role")
		for _, role in ipairs(sortedKeys(WANT)) do
			local w = WANT[role]
			local r = FX.Roles[role]
			local id = Ids[w[1]]
			local okId = type(id) == "number" and id > 0 and id == math.floor(id)
			resolve:case(r ~= nil and r.Key == w[1] and okId and type(r.Stock) == "string" and r.Stock:sub(1, #STOCK) == STOCK,
				fmt("%s: key %s id %s stock %s", role, tostring(r and r.Key), tostring(id), tostring(r and r.Stock)))
			if r and okId then
				local tex = "rbxassetid://" .. tostring(id)
				local e = Instance.new("ParticleEmitter")
				local back = FX.Apply(e, role)
				applied:case(back == e and FX.Texture(role) == tex and e.Texture == tex
					and e.FlipbookLayout == Enum.ParticleFlipbookLayout.Grid4x4
					and e.FlipbookMode == Enum.ParticleFlipbookMode[w[2]]
					and math.abs(e.FlipbookFramerate.Min - w[3]) < 1e-6 and math.abs(e.FlipbookFramerate.Max - w[3]) < 1e-6
					and e.FlipbookStartRandom == (w[2] == "Loop"),
					fmt("%s: %s %s %s %s", role, tostring(e.Texture), tostring(e.FlipbookLayout), tostring(e.FlipbookMode), tostring(e.FlipbookStartRandom)))
				readBack:case(FX.RoleOf(tex) == role, fmt("%s: RoleOf -> %s", role, tostring(FX.RoleOf(tex))))
				e:Destroy()
			end
		end
		resolve:report()
		applied:report()
		readBack:report()
		T.check(FX.RoleOf("") == nil and FX.RoleOf(STOCK .. "sparkles_main.dds") == nil and FX.RoleOf("rbxassetid://1") == nil,
			"FxSprites.RoleOf: an empty texture, a stock path (ids uploaded) or a foreign id is no role")
		local strip = type(FX.Strip) == "function" and FX.Strip("Dash")
		T.check(type(Ids.fx_speedlines) == "number" and strip == "rbxassetid://" .. tostring(Ids.fx_speedlines),
			"FxSprites.Strip(\"Dash\") = fx_speedlines (a single-frame Beam strip)", tostring(strip))
		local strips = T.tally("FxSprites.Strip: the trail / fountain strips are their own sheet, else the old stock texture (never empty, never fx_speedlines)")
		for _, name in ipairs(sortedKeys(WANT_STRIPS)) do
			local w = WANT_STRIPS[name]
			local id = Ids[w[1]]
			local want = (type(id) == "number" and id > 0) and ("rbxassetid://" .. tostring(id)) or w[2]
			local got = type(FX.Strip) == "function" and FX.Strip(name) or nil
			strips:case(got == want and got ~= "" and got ~= strip, fmt("%s: %s (want %s)", name, tostring(got), want))
		end
		strips:report()
		local before = #Mock.Output
		T.check(FX.Texture("NoSuchRole") == FX.Texture("Sparkle"), "FxSprites: an unknown role falls back to Sparkle")
		local warned = false
		for i = before + 1, #Mock.Output do
			local o = Mock.Output[i]
			warned = warned or (o.kind == "warn" and tostring(o.text):find("unknown role NoSuchRole", 1, true) ~= nil)
		end
		T.check(warned, "FxSprites: an unknown role warns (a typo at a call site shows in the output)")
		K.flushWarnings("fxsprites_roles_resolve", { "[FxSprites] unknown role NoSuchRole" })
	end)

	S.fxsprites_fallback_when_id_zero = guarded("fxsprites_fallback_when_id_zero", function()
		local FX = fxModule()
		if not FX or not T.check(type(FX._Deps) == "function", "FxSprites._Deps exists (tests)") then
			return
		end
		local ok, err = pcall(function()
			FX._Deps({ TextureIds = { fx_sparkle = 0, fx_smoke = 0, fx_speedlines = 0 } })
			local fall = T.tally("id 0 / missing: every role's Texture is its old built-in path")
			for _, role in ipairs(sortedKeys(WANT)) do
				local r = FX.Roles[role]
				local tex = FX.Texture(role)
				fall:case(r ~= nil and tex == r.Stock and tex:sub(1, #STOCK) == STOCK and FX.RoleOf(tex) ~= nil, role .. ": " .. tostring(tex))
			end
			fall:report()
			T.eq(FX.Texture("Sparkle"), STOCK .. "sparkles_main.dds", "id 0: Sparkle = the built-in sparkle")
			T.eq(FX.Texture("Puff"), STOCK .. "smoke_main.dds", "id 0: Puff = the built-in smoke")
			local e = Instance.new("ParticleEmitter")
			e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
			FX.Apply(e, "Sparkle")
			T.check(e.Texture == STOCK .. "sparkles_main.dds" and e.FlipbookLayout == Enum.ParticleFlipbookLayout.None,
				"id 0: Apply sets the built-in texture and turns the flipbook off", tostring(e.Texture) .. " " .. tostring(e.FlipbookLayout))
			e:Destroy()
			T.eq(FX.Strip("Dash"), "", "id 0: Strip(\"Dash\") = \"\" (a plain Beam)")
			FX._Deps({ TextureIds = { fx_dots = 0, fx_waterflow = 0, fx_watersheet = 0 } })
			for _, name in ipairs(sortedKeys(WANT_STRIPS)) do
				T.eq(FX.Strip(name), WANT_STRIPS[name][2], "id 0: Strip(\"" .. name .. "\") = its old stock texture (still visible)")
			end
			FX._Deps({ TextureIds = { fx_dots = 4242, fx_waterflow = 4343, fx_watersheet = 4444 } })
			T.check(FX.Strip("Dots") == "rbxassetid://4242" and FX.Strip("Flow") == "rbxassetid://4343" and FX.Strip("Sheet") == "rbxassetid://4444",
				"uploaded: Strip(\"Dots\" / \"Flow\" / \"Sheet\") = their own sheets", FX.Strip("Dots") .. " " .. FX.Strip("Flow") .. " " .. FX.Strip("Sheet"))
		end)
		FX._Deps(false)
		T.check(ok, "fxsprites_fallback_when_id_zero ran without errors", tostring(err))
		local Ids = requireShared("TextureIds")
		T.check(Ids ~= nil and FX.Texture("Sparkle") == "rbxassetid://" .. tostring(Ids.fx_sparkle), "_Deps(false): the real ids are back")
	end)

	S.fx_no_stock_particles_server = guarded("fx_no_stock_particles_server", function()
		if not K.needBoot() then
			return
		end
		local FX = fxModule()
		if not FX then
			return
		end
		-- the builders' extras that the lobby boot does not place
		local extras = Instance.new("Folder")
		extras.Name = "FxSweepExtras"
		local built = {}
		local function keep(label, ok, m)
			if ok and typeof(m) == "Instance" then
				m.Parent = extras
				built[#built + 1] = label
			end
		end
		local PB, PC = requireShared("PetBuilder"), requireShared("PetCatalog")
		if PB and PC and type(PC.Pets) == "table" then
			local seen = {}
			for _, def in ipairs(PC.Pets) do
				local el = def.Element or "?"
				if not seen[el] then
					seen[el] = true
					local stage = (type(PB.MaxEvolution) == "function" and PB.MaxEvolution(def)) or 1
					keep(def.Id .. " evolved " .. stage, pcall(PB.Build, def, { Detail = "High", Evolved = stage }))
				end
				if def.Rarity == "Legendary" and not seen.Legendary then
					seen.Legendary = true
					keep(def.Id .. " Legendary", pcall(PB.Build, def, { Detail = "High" }))
					for _, finish in ipairs({ "Golden", "Rainbow" }) do
						local copy = {}
						for k, v in pairs(def) do
							copy[k] = v
						end
						copy.Finish = finish
						keep(def.Id .. " " .. finish, pcall(PB.Build, copy, { Detail = "High" }))
					end
				end
			end
		end
		local TL = requireShared("TokenLook")
		if TL and type(TL.Palettes) == "table" then
			for _, palette in ipairs(sortedKeys(TL.Palettes)) do
				keep("token " .. palette, pcall(TL.Build, { Palette = palette }))
			end
		end
		local HBi = K.moduleInstance("server/Services/HomeBuilder")
		local okH, HB = false, nil
		if HBi then
			okH, HB = pcall(require, HBi)
		end
		local TC = requireShared("TycoonCatalog")
		if okH and type(HB) == "table" and type(HB.BuildStationModel) == "function" and TC and type(TC.Stations) == "table" then
			for _, def in ipairs(TC.Stations) do
				if def.Kind ~= "Prestige" then
					for level = 1, def.MaxLevel or 1 do
						keep(def.Id .. " " .. level, pcall(HB.BuildStationModel, def.Id, level))
					end
				end
			end
		end
		local BB = requireShared("BossBuilder")
		if BB and type(BB.Ids) == "function" then
			local id = BB.Ids()[1]
			local okB, boss = pcall(BB.Build, id, { Detail = "High" })
			if okB and typeof(boss) == "Instance" then
				pcall(BB.SetTier, boss, "High")
				keep("boss " .. tostring(id) .. " High", true, boss)
			end
		end
		T.check(#built >= 10, "fx sweep: the builders' extras were built (" .. #built .. ")", table.concat(built, ", "))
		local bad, pending, count = walkEmitters(FX, { game, extras }, requireShared("TextureIds"))
		T.check(count >= 20, "fx sweep (server): the booted game and the extras hold emitters (" .. count .. ")")
		report("fx sweep (server)", bad, pending, count, "ParticleEmitter")
		extras:Destroy()
		sourceChecks("fx sweep (shared + server sources)", { "shared", "server" }, FX)
	end)

	return S
end

local function clientScenarios()
	local S = {}

	S.fx_no_stock_particles_client = guarded("fx_no_stock_particles_client", function()
		local FX = fxModule()
		if not FX then
			return
		end
		local bad, pending, count = walkEmitters(FX, { game }, requireShared("TextureIds"))
		report("fx sweep (client)", bad, pending, count, "ParticleEmitter")
		sourceChecks("fx sweep (client sources)", { "client", "first" }, FX)
	end)

	return S
end

if (ARGS and ARGS.context or "server") == "server" then
	return serverScenarios()
end
return clientScenarios()
