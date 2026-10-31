-- smoke_sky_server.lua: the living sky's server half (plan docs/superpowers/plans/2026-10-30-living-sky.md Task 4):
-- server/Services/SkyService publishes the sky clock as Workspace attributes and the raid event sky; DevService's /sky.
-- Loaded by tools/smoke.py in the server world only (booted: Main.server.lua ran SkyService.Init).
--   skysvc_attrs          boot publishes SkyEpoch (the server time at boot), SkySpeed (Config.Sky.Speed.Default),
--                         SkyOffset 0, SkyEvent "" and SkyEventAt (Config.Sky.Attr names); Init again changes none of
--                         them (the epoch, a dev speed and offset are kept), and never wires the same signal twice
--   skysvc_raid_start_end EventService.EventStarted BossRaid <boss> -> SkyEvent <boss> + SkyEventAt = now, for every
--                         BattleCatalog.Bosses id (each has a Config.Sky.RaidThemes sky); DoubleRewards and unknown
--                         bosses change nothing; BattleService.BattleEnded Mode "Raid" -> "" (SkyEventAt moves again)
--   skysvc_raid_end_reasons every Raid end Reason (BossDown / Wipe / Error / Timeout / NoPlayers) clears; a second raid
--                         start replaces the first and the first raid's late end leaves the second's sky up; a non-Raid
--                         or junk BattleEnded never clears; EventEnded BossRaid clears; the watchdog (every
--                         Config.Sky.EventWatch s) clears a raid sky whose raid is gone, puts up the sky of a raid that
--                         started without EventStarted, and leaves a dev preview alone
--   skysvc_dev_refuses    /sky speed 0 / -5 -> 0.1, 1e9 -> 120, abc / nan / inf refused (SkySpeed stays finite), a speed
--                         change keeps the loop position, /sky noon and /sky raid nope refused, /sky dawn|day|sunset|night
--                         start that phase now, /sky raid <boss> / clear, /sky alone names the phase, the chat path, a
--                         non-developer is refused and changes nothing, /devhelp lists /sky (three toasts <= 90), no NaN in
--                         the preset the attributes give
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local Workspace = game:GetService("Workspace")

local abs = math.abs

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function serverScenarios()
	local S = {}
	local K = _G.K
	local advance = K.advance

	local function req(key)
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

	local function now()
		return Workspace:GetServerTimeNow()
	end

	-- SkyService + Config.Sky (with its Attr names), or nil after one failed check
	local function sky()
		local Sky = req("server/Services/SkyService")
		local Config = req("shared/Config")
		if not T.check(Sky ~= nil and type(Sky.Init) == "function" and type(Sky.SetPhase) == "function" and type(Sky.SetSpeed) == "function"
			and type(Sky.SetEvent) == "function" and type(Sky.ClearEvent) == "function" and type(Sky.Status) == "function",
			"SkyService exists with Init / SetPhase / SetSpeed / SetEvent / ClearEvent / Status", "src/server/Services/SkyService.lua missing or incomplete") then
			return nil
		end
		local cfg = Config and Config.Sky
		if not T.check(type(cfg) == "table" and type(cfg.Attr) == "table" and type(cfg.EventWatch) == "number", "Config.Sky has Attr (the attribute names) and EventWatch") then
			return nil
		end
		return Sky, cfg, Config
	end

	local function attrs(cfg)
		local A = cfg.Attr
		return {
			Epoch = Workspace:GetAttribute(A.Epoch),
			Speed = Workspace:GetAttribute(A.Speed),
			Offset = Workspace:GetAttribute(A.Offset),
			Event = Workspace:GetAttribute(A.Event),
			EventAt = Workspace:GetAttribute(A.EventAt),
		}
	end

	-- puts the clock attributes back as they were (the dev scenarios move them)
	local function restore(cfg, saved)
		local A = cfg.Attr
		Workspace:SetAttribute(A.Speed, saved.Speed)
		Workspace:SetAttribute(A.Offset, saved.Offset)
		Workspace:SetAttribute(A.Event, saved.Event)
		Workspace:SetAttribute(A.EventAt, saved.EventAt)
	end

	-- stand-in EventService / BattleService: only the signals (and the raid status) SkyService listens to
	local function fakes(statusFn)
		local Util = req("shared/Util")
		local ES = { EventStarted = Util.Signal(), EventEnded = Util.Signal(), EventAnnounced = Util.Signal() }
		local BS = { BattleEnded = Util.Signal(), GetRaidStatus = statusFn }
		return ES, BS
	end

	-- SkyService wired to stand-ins for fn(ES, BS, ...), then back to the real services (the watchdog reads the newest)
	local function withFakes(Sky, cfg, statusFn, fn)
		local saved = attrs(cfg)
		local ES, BS = fakes(statusFn)
		Sky.Init({ EventService = ES, BattleService = BS })
		Sky.ClearEvent()
		local ok, err = pcall(fn, ES, BS)
		Sky.Init({ EventService = req("server/Services/EventService"), BattleService = req("server/Services/BattleService") })
		restore(cfg, saved)
		if not ok then
			error(err, 0)
		end
	end

	local function raidStart(ES, bossId, battleId)
		ES.EventStarted:Fire("BossRaid", { Kind = "BossRaid", BossId = bossId, Name = tostring(bossId), BattleId = battleId, Source = "smoke" })
		advance(0.1)
	end

	local function raidEnd(BS, battleId, reason, mode, bossId)
		BS.BattleEnded:Fire(battleId, { BattleId = battleId, Mode = mode == nil and "Raid" or mode, Reason = reason, BossId = bossId, Winners = {}, Losers = {} })
		advance(0.1)
	end

	-- skysvc_attrs
	S.skysvc_attrs = guarded("skysvc_attrs", function()
		if not K.needBoot() then
			return
		end
		local Sky, cfg = sky()
		if not Sky then
			return
		end
		local a = attrs(cfg)
		T.check(finite(a.Epoch) and a.Epoch <= now() + 1e-6, "boot: Workspace." .. cfg.Attr.Epoch .. " is the server time at boot (a finite number, not in the future)", tostring(a.Epoch))
		T.eq(a.Speed, cfg.Speed.Default, "boot: " .. cfg.Attr.Speed .. " = Config.Sky.Speed.Default")
		T.eq(a.Offset, 0, "boot: " .. cfg.Attr.Offset .. " = 0")
		T.eq(a.Event, "", "boot: " .. cfg.Attr.Event .. " = \"\" (no raid sky)")
		T.check(finite(a.EventAt), "boot: " .. cfg.Attr.EventAt .. " is a server time", tostring(a.EventAt))
		-- Init again (and with a dev speed set): nothing is rewritten
		local saved = attrs(cfg)
		Sky.SetSpeed(4)
		local moved = attrs(cfg)
		advance(1)
		Sky.Init({ EventService = req("server/Services/EventService"), BattleService = req("server/Services/BattleService") })
		local b = attrs(cfg)
		T.check(b.Epoch == a.Epoch and b.Speed == 4 and b.Offset == moved.Offset and b.Event == moved.Event and b.EventAt == moved.EventAt,
			"Init twice keeps the epoch, the dev speed / offset and the event", tostring(b.Epoch) .. " " .. tostring(b.Speed) .. " " .. tostring(b.Offset))
		restore(cfg, saved)
		-- the same stand-in signal handed to Init twice is wired once (one handler, one change)
		local ES = fakes()
		Sky.Init({ EventService = ES })
		Sky.Init({ EventService = ES })
		local n = 0
		for _, h in ipairs(ES.EventStarted._handlers or {}) do
			if h.connected then
				n = n + 1
			end
		end
		T.eq(n, 1, "Init twice with the same EventService connects EventStarted once")
		Sky.Init({ EventService = req("server/Services/EventService"), BattleService = req("server/Services/BattleService") })
		restore(cfg, saved)
	end)

	-- skysvc_raid_start_end
	S.skysvc_raid_start_end = guarded("skysvc_raid_start_end", function()
		if not K.needBoot() then
			return
		end
		local Sky, cfg = sky()
		if not Sky then
			return
		end
		local BC = req("shared/BattleCatalog")
		withFakes(Sky, cfg, nil, function(ES, BS)
			local A = cfg.Attr
			local t0 = now()
			raidStart(ES, "storm_titan", "R1")
			T.eq(Workspace:GetAttribute(A.Event), "storm_titan", "EventStarted BossRaid storm_titan -> SkyEvent storm_titan")
			T.check(abs((Workspace:GetAttribute(A.EventAt) or -1) - t0) < 0.5, "...and SkyEventAt = the server time of the start", tostring(Workspace:GetAttribute(A.EventAt)))
			ES.EventStarted:Fire("DoubleRewards", { Kind = "DoubleRewards", Seconds = 60 })
			advance(0.1)
			T.eq(Workspace:GetAttribute(A.Event), "storm_titan", "a DoubleRewards start leaves the raid sky")
			advance(1)
			local t1 = now()
			raidEnd(BS, "R1", "BossDown")
			T.eq(Workspace:GetAttribute(A.Event), "", "BattleEnded Mode Raid -> SkyEvent \"\"")
			T.check(abs((Workspace:GetAttribute(A.EventAt) or -1) - t1) < 0.5, "...and SkyEventAt moves to the end (the 3 s blend back)", tostring(Workspace:GetAttribute(A.EventAt)))
			-- every boss of the catalog has a raid sky and puts it up
			local bosses = {}
			for id in pairs((BC and BC.Bosses) or {}) do
				bosses[#bosses + 1] = id
			end
			table.sort(bosses)
			T.check(#bosses >= 4, "BattleCatalog.Bosses has the raid bosses", tostring(#bosses))
			for i, id in ipairs(bosses) do
				T.check(type(cfg.RaidThemes[id]) == "string", "boss " .. id .. " has a Config.Sky.RaidThemes sky")
				raidStart(ES, id, "RB" .. i)
				T.eq(Workspace:GetAttribute(A.Event), id, "EventStarted BossRaid " .. id .. " -> SkyEvent " .. id)
				raidEnd(BS, "RB" .. i, "Wipe")
				T.eq(Workspace:GetAttribute(A.Event), "", "...cleared at its end")
			end
			-- an unknown boss or a junk payload changes nothing
			raidStart(ES, "not_a_boss", "RX")
			T.eq(Workspace:GetAttribute(A.Event), "", "an unknown boss id puts up no raid sky")
			ES.EventStarted:Fire("BossRaid", nil)
			ES.EventStarted:Fire("BossRaid", "junk")
			ES.EventStarted:Fire(nil, { BossId = "storm_titan" })
			advance(0.1)
			T.eq(Workspace:GetAttribute(A.Event), "", "junk EventStarted payloads change nothing")
		end)
		K.flushErrors("skysvc_raid_start_end")
	end)

	-- skysvc_raid_end_reasons
	S.skysvc_raid_end_reasons = guarded("skysvc_raid_end_reasons", function()
		if not K.needBoot() then
			return
		end
		local Sky, cfg = sky()
		if not Sky then
			return
		end
		local A = cfg.Attr
		withFakes(Sky, cfg, nil, function(ES, BS)
			for i, reason in ipairs({ "BossDown", "Wipe", "Error", "Timeout", "NoPlayers" }) do
				raidStart(ES, "lava_golem", "E" .. i)
				raidEnd(BS, "E" .. i, reason)
				T.eq(Workspace:GetAttribute(A.Event), "", "a raid that ends with Reason " .. reason .. " clears the raid sky")
			end
			-- back to back: the second start replaces the first; the first raid's late end leaves the second's sky up
			raidStart(ES, "storm_titan", "A1")
			raidStart(ES, "frost_wyrm", "A2")
			T.eq(Workspace:GetAttribute(A.Event), "frost_wyrm", "a second raid start replaces the first raid's sky")
			raidEnd(BS, "A1", "BossDown")
			T.eq(Workspace:GetAttribute(A.Event), "frost_wyrm", "...the first raid's late BattleEnded leaves the second raid's sky")
			raidEnd(BS, "A2", "Wipe")
			T.eq(Workspace:GetAttribute(A.Event), "", "...and the second raid's end clears it")
			-- a non-Raid end never clears
			raidStart(ES, "shadow_hydra", "N1")
			for _, mode in ipairs({ "Duel", "Ring", "Dungeon", "Trial", "PvP" }) do
				raidEnd(BS, "N1", "BossDown", mode)
			end
			BS.BattleEnded:Fire("N1", nil)
			BS.BattleEnded:Fire("N1", "junk")
			BS.BattleEnded:Fire(nil, { Mode = 42 })
			advance(0.1)
			T.eq(Workspace:GetAttribute(A.Event), "shadow_hydra", "a non-Raid (or junk) BattleEnded never clears the raid sky")
			-- EventEnded BossRaid clears too (the events owner's own end)
			ES.EventEnded:Fire("DoubleRewards", { Kind = "DoubleRewards" })
			advance(0.1)
			T.eq(Workspace:GetAttribute(A.Event), "shadow_hydra", "EventEnded DoubleRewards leaves the raid sky")
			ES.EventEnded:Fire("BossRaid", { Kind = "BossRaid", BossId = "shadow_hydra", BattleId = "N1" })
			advance(0.1)
			T.eq(Workspace:GetAttribute(A.Event), "", "EventEnded BossRaid clears the raid sky")
			-- a raid end with no battle id still clears (never a stale sky)
			raidStart(ES, "storm_titan", "Z1")
			raidEnd(BS, nil, "Error")
			T.eq(Workspace:GetAttribute(A.Event), "", "a Raid BattleEnded without a battle id clears")
		end)
		-- the watchdog: the raid status is the truth every Config.Sky.EventWatch seconds
		local status = nil
		withFakes(Sky, cfg, function()
			return status
		end, function(ES)
			raidStart(ES, "storm_titan", "W1")
			advance(cfg.EventWatch + 0.5)
			T.eq(Workspace:GetAttribute(A.Event), "", "watchdog: a raid sky whose raid is gone (no end signal heard) clears within EventWatch s")
			status = { Active = true, BossId = "lava_golem", BattleId = "W2" }
			advance(cfg.EventWatch + 0.5)
			T.eq(Workspace:GetAttribute(A.Event), "lava_golem", "watchdog: a raid that started without EventStarted gets its sky")
			advance(cfg.EventWatch + 0.5)
			T.eq(Workspace:GetAttribute(A.Event), "lava_golem", "watchdog: ...and keeps it while the raid runs (no flicker)")
			status = nil
			advance(cfg.EventWatch + 0.5)
			T.eq(Workspace:GetAttribute(A.Event), "", "watchdog: ...cleared once the raid is gone")
			Sky.SetEvent("frost_wyrm", "dev")
			advance(cfg.EventWatch * 2 + 0.5)
			T.eq(Workspace:GetAttribute(A.Event), "frost_wyrm", "watchdog: a dev preview (/sky raid) is left alone")
			Sky.ClearEvent()
		end)
		K.flushErrors("skysvc_raid_end_reasons")
	end)

	-- skysvc_dev_refuses
	S.skysvc_dev_refuses = guarded("skysvc_dev_refuses", function()
		if not K.needBoot() then
			return
		end
		local Sky, cfg, Config = sky()
		if not Sky then
			return
		end
		local Dev = req("server/Services/DevService")
		local SC = req("shared/SkyCycle")
		if not T.check(Dev ~= nil and type(Dev.Run) == "function" and SC ~= nil, "DevService.Run and SkyCycle exist") then
			return
		end
		local A = cfg.Attr
		local OWNER_ID, STRANGER_ID = 31338, 92071
		local saved = { Studio = Mock.Options.Studio, CreatorId = game.CreatorId, CreatorType = game.CreatorType, attrs = attrs(cfg) }
		local joined = {}
		local ok, err = pcall(function()
			Mock.Options.Studio = false
			game.CreatorType = Enum.CreatorType.User
			game.CreatorId = OWNER_ID
			local owner = K.joinPlayer("SkyOwner", OWNER_ID)
			local stranger = K.joinPlayer("SkyStranger", STRANGER_ID)
			joined = { owner, stranger }
			advance(1)

			-- one command, spaced out so the 4-per-2-seconds limit never hides a result; -> ok, message, last DEV toast
			local function run(p, arg)
				advance(0.55)
				local mark = K.logSize()
				local okRun, msg = Dev.Run(p, "sky", arg, "smoke")
				advance(0.1)
				local toast = nil
				for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark)) do
					local text = tostring(e.args[1])
					if text:sub(1, 4) == "DEV:" then
						toast = { text = text, kind = e.args[2] }
					end
				end
				return okRun, tostring(msg), toast or { text = "(no DEV toast)" }
			end
			local function at()
				local a = attrs(cfg)
				return SC.At(now(), a.Epoch, a.Speed, a.Offset), a
			end

			-- speed: clamped, junk refused, never NaN
			local okS, msg = run(owner, "speed 0")
			T.check(okS and Workspace:GetAttribute(A.Speed) == cfg.Speed.Min, "/sky speed 0 -> clamped to " .. cfg.Speed.Min, msg)
			okS, msg = run(owner, "speed -5")
			T.check(okS and Workspace:GetAttribute(A.Speed) == cfg.Speed.Min, "/sky speed -5 -> " .. cfg.Speed.Min, msg)
			okS, msg = run(owner, "speed 1e9")
			T.check(okS and Workspace:GetAttribute(A.Speed) == cfg.Speed.Max, "/sky speed 1e9 -> " .. cfg.Speed.Max, msg)
			for _, junk in ipairs({ "speed abc", "speed nan", "speed inf", "speed -inf", "speed", "speed 1 2" }) do
				local before = Workspace:GetAttribute(A.Speed)
				local okJ, msgJ, toast = run(owner, junk)
				T.check(okJ == false and toast.kind == "bad" and Workspace:GetAttribute(A.Speed) == before, "/sky " .. junk .. " is refused with a bad toast, the speed stays", msgJ .. " | " .. toast.text)
			end
			T.check(finite(Workspace:GetAttribute(A.Speed)) and finite(Workspace:GetAttribute(A.Offset)), "SkySpeed / SkyOffset stay finite")
			-- a speed change keeps the loop position (no jump)
			run(owner, "speed 1")
			local p0 = at()
			advance(0.55)
			Sky.SetSpeed(20)
			local p1 = at()
			T.check(p0.Phase == p1.Phase and abs(p0.LoopT - p1.LoopT) < 0.002, "a speed change keeps the loop position", p0.Phase .. " " .. p0.LoopT .. " -> " .. p1.Phase .. " " .. p1.LoopT)
			Sky.SetSpeed(1)

			-- phases start now
			for _, name in ipairs({ "sunset", "Night", "DAWN", "day" }) do
				local okP, msgP = run(owner, name)
				local p = at()
				T.check(okP and p.Phase:lower() == name:lower() and p.T < 0.01, "/sky " .. name .. " starts that phase now", msgP .. " -> " .. p.Phase .. " T " .. p.T)
			end
			local okN, msgN, toastN = run(owner, "noon")
			T.check(okN == false and toastN.kind == "bad", "/sky noon is refused with a bad toast", msgN)

			-- raid preview + clear
			local okR, msgR = run(owner, "raid storm_titan")
			T.check(okR and Workspace:GetAttribute(A.Event) == "storm_titan", "/sky raid storm_titan previews the raid sky", msgR)
			local okX, msgX, toastX = run(owner, "raid nope")
			T.check(okX == false and toastX.kind == "bad" and Workspace:GetAttribute(A.Event) == "storm_titan", "/sky raid nope is refused, the preview stays", msgX)
			local okC, msgC = run(owner, "clear")
			T.check(okC and Workspace:GetAttribute(A.Event) == "", "/sky clear takes the raid sky down", msgC)

			-- /sky alone names the phase
			local okQ, msgQ = run(owner, nil)
			local q = at()
			T.check(okQ and msgQ:find(q.Phase, 1, true) ~= nil, "/sky alone names the current phase", msgQ)

			-- the chat path
			advance(0.55)
			Mock.FireSignal(owner, "Chatted", "/sky speed 5")
			advance(0.2)
			T.eq(Workspace:GetAttribute(A.Speed), 5, "chat '/sky speed 5' sets the speed")
			advance(0.55)
			Mock.FireSignal(owner, "Chatted", "/SKY Night")
			advance(0.2)
			T.eq((at()).Phase, "Night", "chat '/SKY Night' starts the night")
			-- the remote with a number value (not a text) is refused
			local okV, msgV, toastV = run(owner, 5)
			T.check(okV == false and toastV.kind == "bad", "DevCommand('sky', 5) (a number, not a text) is refused with a bad toast", msgV .. " | " .. toastV.text)

			-- a non-developer is refused and changes nothing
			local before = attrs(cfg)
			for _, arg in ipairs({ "night", "speed 120", "raid storm_titan", "clear" }) do
				local okD = run(stranger, arg)
				T.check(okD == false, "a normal player's /sky " .. arg .. " is refused")
			end
			advance(0.55)
			Mock.FireSignal(stranger, "Chatted", "/sky speed 99")
			advance(0.2)
			local after = attrs(cfg)
			T.check(before.Speed == after.Speed and before.Offset == after.Offset and before.Event == after.Event, "...and changes no sky attribute")

			-- /devhelp lists /sky in three toasts that fit
			advance(2.1)
			local mark = K.logSize()
			Dev.Run(owner, "devhelp", nil, "smoke")
			advance(0.2)
			local help, fits = {}, true
			for _, e in ipairs(K.remotesFor("Notify", OWNER_ID, mark)) do
				local text = tostring(e.args[1])
				if text:sub(1, 4) == "DEV:" then
					help[#help + 1] = text
					fits = fits and #text <= 90
				end
			end
			local all = table.concat(help, " | ")
			T.check(#help == 3 and fits and all:find("/sky", 1, true) ~= nil, "/devhelp lists /sky (three toasts, <= 90 characters each)", all)

			-- whatever the dev did, the preset from the attributes has no NaN
			local p = at()
			local preset = SC.Preset(p, Workspace:GetAttribute(A.Event), 1)
			local bad = nil
			for group, props in pairs(preset) do
				for prop, v in pairs(props) do
					if type(v) == "number" and not finite(v) then
						bad = group .. "." .. prop
					end
				end
			end
			T.check(bad == nil, "the preset from the dev-moved attributes has no NaN / inf", tostring(bad))
		end)
		Mock.Options.Studio = saved.Studio
		game.CreatorId = saved.CreatorId
		game.CreatorType = saved.CreatorType
		restore(cfg, saved.attrs)
		K.removePlayers(joined)
		if not ok then
			error(err, 0)
		end
		K.flushErrors("skysvc_dev_refuses")
	end)

	return S
end

return serverScenarios()
