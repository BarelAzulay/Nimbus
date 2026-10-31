-- smoke_hud_tools.lua: the owner's batch "Travel -> a Lobby portal, unlimited stamina in the lobby, new dev tools".
-- Loaded by tools/smoke.py in the server world and the client worlds:
--   hudtools_portal    (server, booted) the Travel press (Remotes.QuickTravel -> GateService.Travel) opens the SAME home
--                      portal (the HomePortal attribute) and moves nobody; the owner walking in lands on the lobby spawn,
--                      PortalArrived is written, PortalUsed is NOT fired (the "Portal Home" tutorial step stays open) and
--                      Teleported fires (player, "Plaza"); a second press after the shared 3 s cooldown replaces the open
--                      portal, also from Go home to Travel and back, and the portal keeps the destination of the last
--                      press; a press inside the cooldown changes nothing; the same refusals and toasts as Go home; it
--                      opens at a home plot, on the Arena island and on the Altar island; junk never errors; the Court is
--                      gone (no CourtCFrame, no "Court" destination)
--   hudtools_zone      (server, booted) Config.InLobbyZone on the real lobby: the spawn, the Gate Court gates, the shop, the
--                      garden islands and the spoke bridges are in it; every home plot, the ring street, the Arena island,
--                      the Altar island, the arena floor and a match course are not
--   hudtools_security  (server, booted) a non-developer in the live game runs none of the new commands, by remote or chat,
--                      with any argument: nobody is kicked or banned, no data changes, no speed hint
--   hudtools_kick      (server, booted) /kick by partial unique name with a filtered reason; refuses yourself, an ambiguous
--                      or unknown name and junk; a failed filter drops the reason, never shows it raw
--   hudtools_ban       (server, booted) /ban and /unban against the docs' BanAsync / UnbanAsync config (Duration -1); online
--                      by partial name, offline by exact name or userId; refuses yourself and other developers, online or
--                      offline; a failing API, BanningEnabled off and Studio each give their real reason, never a success
--   hudtools_pets      (server, booted) /evolvepets, /levelall, /maxpets: every owned key (stacks, tier copies, hybrids; not
--                      only equipped), the Epic+ rule, no cost, keys and copies untouched, team / equipped / garden / training
--                      state kept, a training job finishes on /maxpets and the pet comes back; battle and provisional
--                      refusals; range and junk; Sync after a change
--   hudtools_speed     (server, booted) /speed toggles the hint NC_DevSpeed on the developer's PlayerGui (never on the
--                      Player), it survives a respawn and nothing is saved; /devhelp lists the new commands
--   client_hudtools_stamina (client) in the lobby running drains nothing and a dash costs no stamina, the dash cooldown stays
--                      and the bar stays full; in a match, a battle, on a home plot, the arena and the altar it drains
--   client_hudtools_speed   (client) NC_DevSpeed doubles walking and running, never stacks, stands aside in a battle and a
--                      scripted walk, a server freeze still wins, survives a respawn
--   client_hudtools_panel   (client) the panel's new controls and what they send; the player list follows the server and the
--                      Ban button asks "Are you sure?" first
--   client_hudtools_panel_mobile (phone world) the same controls are big enough for a thumb
-- Deterministic: mock clock only. Everything the scenarios change is restored at the end. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local fmt = string.format

local SPEED_HINT = "NC_DevSpeed"

----------------------------------------------------------------------------------------------------
-- server half
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K
	local advance = K.advance

	local OWNER_ID = 31338 -- (not smoke_dev's owner: the mock's DataStore keeps a profile per UserId)

	local function shared(name)
		local inst = Mock.GetPath(ROOTS["shared"] .. "/" .. name)
		local ok, result = pcall(function()
			return inst and require(inst)
		end)
		return ok and type(result) == "table" and result or nil
	end

	local function hintOf(p, name)
		local pg = p:FindFirstChildOfClass("PlayerGui")
		return pg and pg:GetAttribute(name)
	end

	-- the published game owned by OWNER_ID for the length of fn; everything is put back, also when fn errors
	local function liveGame(Config, fn)
		local saved = { Studio = Mock.Options.Studio, CreatorId = game.CreatorId, CreatorType = game.CreatorType, Admins = Config.Dev.Admins }
		Mock.Options.Studio = false
		game.CreatorType = Enum.CreatorType.User
		game.CreatorId = OWNER_ID
		local ok, err = pcall(fn)
		Mock.Options.Studio = saved.Studio
		game.CreatorId = saved.CreatorId
		game.CreatorType = saved.CreatorType
		Config.Dev.Admins = saved.Admins
		if not ok then
			T.fail("hudtools: scenario errored: " .. tostring(err))
		end
	end

	local function join(list, name, userId)
		local p = Mock.AddPlayer(name, userId)
		advance(1)
		list[#list + 1] = p
		return p
	end

	local function leaveAll(list)
		for _, p in ipairs(list) do
			if p.Parent then
				Mock.RemovePlayer(p)
			end
		end
		advance(0.5)
	end

	local function devToasts(p, mark)
		local out = {}
		for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark or 0)) do
			local text = tostring(e.args[1])
			if text:sub(1, 4) == "DEV:" then
				out[#out + 1] = { text = text, kind = e.args[2] }
			end
		end
		return out
	end

	local function lastToast(p, mark)
		local list = devToasts(p, mark)
		return list[#list] or { text = "(no DEV toast)", kind = nil }
	end

	-- every command is spaced out so the 4-per-2-seconds limit never hides a result
	local function send(p, command, arg)
		advance(0.55)
		local mark = K.logSize()
		Mock.FromClient(K.remoteFolder().DevCommand, p, command, arg)
		advance(0.15)
		return mark
	end

	local function chat(p, text)
		advance(0.55)
		local mark = K.logSize()
		Mock.FireSignal(p, "Chatted", text)
		advance(0.15)
		return mark
	end

	local function has(text, needle)
		return string.find(string.lower(tostring(text)), string.lower(needle), 1, true) ~= nil
	end

	local function portalPoint(p, Config)
		local text = p:GetAttribute(Config.Attr.HomePortal)
		if type(text) ~= "string" then
			return nil
		end
		local x, y, z = string.match(text, "^([^,]+),([^,]+),([^,]+),")
		return Vector3.new(tonumber(x), tonumber(y), tonumber(z))
	end

	-- the 0.2 s portal loop finds the owner's root on the point
	local function walkIn(p, point)
		Mock.Teleport(p, CFrame.new(point + Vector3.new(0, 3, 0)))
		advance(0.3)
	end

	S.hudtools_portal = guarded("hudtools_portal", function()
		if not K.needBoot() then
			return
		end
		local Config = K.config()
		local GS = K.mod("GateService")
		local Ty = K.mod("TycoonService")
		local PS = K.mod("PlayerService")
		local AB = K.mod("ArenaBuilder")
		local Altar = K.mod("StormAltar")
		local PortalService = K.mod("PortalService")
		local remote = K.remoteFolder() and K.remoteFolder():FindFirstChild("QuickTravel")
		if not T.check(type(GS) == "table" and type(GS.Travel) == "function" and remote ~= nil and type(Ty) == "table", "hudtools: GateService.Travel, TycoonService and the QuickTravel remote exist") then
			return
		end
		T.eq(GS.CourtCFrame, nil, "hudtools: GateService.CourtCFrame is gone")

		local players = K.freshPlayers(2, "Lobbyer")
		local a, b = players[1], players[2]
		local spawn = PS.GetLobbySpawnCFrame()
		local attr = Config.Attr.HomePortal
		local used, teleported = {}, {}
		local c1 = Ty.PortalUsed:Connect(function(p)
			used[#used + 1] = p
		end)
		local c2 = GS.Teleported:Connect(function(p, id)
			if p == a then
				teleported[#teleported + 1] = id
			end
		end)
		advance(3.5)

		-- a press opens the portal where the player stands and moves nobody
		local away = spawn * CFrame.new(0, 0, -60)
		Mock.Teleport(a, away)
		advance(0.1)
		local mark = K.logSize()
		Mock.FromClient(remote, a, "Plaza")
		advance(0.1)
		local point = portalPoint(a, Config)
		if T.check(point ~= nil, "hudtools: Travel opens the home portal (the HomePortal attribute)", tostring(a:GetAttribute(attr))) then
			T.check(K.planar(point, away.Position) <= 6.6, "hudtools: ...about 6 studs ahead of the player, like Go home", fmt("%.1f studs", K.planar(point, away.Position)))
			T.check(K.planar(K.root(a).Position, away.Position) < 1, "hudtools: ...and moves nobody by itself")
			T.eq(#K.remotesFor("Notify", a.UserId, mark), 0, "hudtools: ...with no toast")

			-- another player in the portal goes nowhere
			walkIn(b, point)
			T.check(K.planar(K.root(b).Position, point) < 1 and a:GetAttribute(attr) ~= nil, "hudtools: another player in the portal is not teleported")
			Mock.Teleport(b, spawn * CFrame.new(10, 0, 40))

			walkIn(a, point)
			T.check(K.planar(K.root(a).Position, spawn.Position) <= 3, "hudtools: walking in lands on the lobby spawn plaza", fmt("%.1f studs", K.planar(K.root(a).Position, spawn.Position)))
			T.eq(a:GetAttribute(attr), nil, "hudtools: ...the portal closes")
			local arrived = a:GetAttribute(Config.Attr.PortalArrived)
			T.check(type(arrived) == "number" and math.abs(arrived - workspace:GetServerTimeNow()) <= 1.5, "hudtools: ...PortalArrived is written (the arrival ring and sound)", tostring(arrived))
			T.eq(#used, 0, "hudtools: ...PortalUsed does not fire (the tutorial's Portal Home step needs the way home)")
			T.check(#teleported == 1 and teleported[1] == "Plaza", "hudtools: ...GateService.Teleported fires (player, 'Plaza')", table.concat(teleported, ","))
		end

		-- one portal, one cooldown: Go home right after a Travel press changes nothing; later it replaces the portal
		advance(3.1)
		Mock.Teleport(a, away)
		advance(0.1)
		local okOpen = GS.Travel(a, "Plaza")
		local first = a:GetAttribute(attr)
		T.check(okOpen == true and type(first) == "string", "hudtools: GateService.Travel(player, 'Plaza') -> true with the portal open", tostring(first))
		Mock.Teleport(a, away * CFrame.new(0, 0, -30))
		advance(0.5)
		local okSoon = Ty.OpenHomePortal(a)
		T.check(okSoon ~= true and a:GetAttribute(attr) == first, "hudtools: Go home inside the shared 3 s cooldown leaves the Travel portal as it is", tostring(a:GetAttribute(attr)))
		local _, reasonSoon = GS.Travel(a, "Plaza")
		T.check(a:GetAttribute(attr) == first and reasonSoon ~= nil, "hudtools: ...and so does a second Travel press", tostring(reasonSoon))
		advance(3)
		T.eq(select(1, Ty.OpenHomePortal(a)), true, "hudtools: Go home after the cooldown is accepted")
		local second = a:GetAttribute(attr)
		T.check(type(second) == "string" and second ~= first, "hudtools: ...and replaces the open portal", tostring(second))
		advance(3.1)
		T.eq(select(1, GS.Travel(a, "Plaza")), true, "hudtools: Travel after the cooldown is accepted")
		local third = a:GetAttribute(attr)
		T.check(type(third) == "string" and third ~= second, "hudtools: ...a second press of Travel replaces the portal (new closing time)", tostring(third))
		local lastPoint = portalPoint(a, Config)
		walkIn(a, lastPoint)
		T.check(K.planar(K.root(a).Position, spawn.Position) <= 3, "hudtools: the portal goes where the LAST press said (home -> lobby)")
		T.eq(#used, 0, "hudtools: ...and PortalUsed stays silent")

		-- refusals: the same rules and the same toast style as Go home
		advance(3.1)
		Mock.Teleport(a, away)
		advance(0.1)
		for _, case in ipairs({
			{ "InMatch", true, "Finish your match first", "an obby match" },
			{ "InBattle", "B7", "Finish your battle first", "a battle / the Ring / a dungeon run" },
			{ "PortalLocked", "Obby", "Leave the portal party first", "a portal party countdown" },
		}) do
			local name = (Config.Attr[case[1]] or case[1])
			a:SetAttribute(name, case[2])
			mark = K.logSize()
			advance(1.1) -- (the side toast throttles repeats of one text)
			mark = K.logSize()
			local ok, why = GS.Travel(a, "Plaza")
			advance(0.05)
			local toasts = K.remotesFor("Notify", a.UserId, mark)
			T.check(ok ~= true and a:GetAttribute(attr) == nil, "hudtools: refused in " .. case[4], tostring(why))
			T.check(#toasts == 1 and has(toasts[1].args[1], case[3]) and toasts[1].args[2] == "bad", "hudtools: ...with Go home's toast '" .. case[3] .. "'",
				toasts[1] and tostring(toasts[1].args[1]) or "no toast")
			a:SetAttribute(name, nil)
			advance(0.05)
		end
		-- a portal already open is closed when the player is in a battle at the moment they walk in
		advance(3.1)
		T.eq(select(1, GS.Travel(a, "Plaza")), true, "hudtools: (setup) a portal is open")
		local inBattlePoint = portalPoint(a, Config)
		a:SetAttribute(Config.Attr.InBattle, "B8")
		walkIn(a, inBattlePoint)
		T.check(a:GetAttribute(attr) == nil and K.planar(K.root(a).Position, spawn.Position) > 20, "hudtools: walking into it in a battle closes it and moves nobody")
		a:SetAttribute(Config.Attr.InBattle, nil)

		-- wherever Go home works: a home plot, the Arena island, the Altar island
		local places = {}
		local spots = K.W.lobbyInfo.Spots
		if type(spots) == "table" and spots[1] and typeof(spots[1].SpawnCFrame) == "CFrame" then
			places[#places + 1] = { "a home plot", spots[1].SpawnCFrame }
		end
		local ainfo = AB and AB.GetInfo and AB.GetInfo()
		if ainfo and typeof(ainfo.Spawn) == "CFrame" then
			places[#places + 1] = { "the Arena island", ainfo.Spawn }
		end
		local landing = Altar and Altar.GetLanding and Altar.GetLanding()
		if typeof(landing) == "CFrame" then
			places[#places + 1] = { "the Altar island", landing }
		end
		T.eq(#places, 3, "hudtools: (setup) a home plot, the arena and the altar are found")
		for _, place in ipairs(places) do
			advance(3.1)
			Mock.Teleport(a, place[2] * CFrame.new(0, 3, 0))
			advance(0.1)
			local okHere, whyHere = GS.Travel(a, "Plaza")
			local here = portalPoint(a, Config)
			if T.check(okHere == true and here ~= nil, "hudtools: Travel opens on " .. place[1], tostring(whyHere)) then
				walkIn(a, here)
				T.check(K.planar(K.root(a).Position, spawn.Position) <= 3, "hudtools: ...and leads back to the lobby from " .. place[1])
			end
		end

		-- junk: a known destination only; garbage never errors and opens nothing
		advance(3.1)
		Mock.Teleport(a, away)
		advance(0.1)
		local errs = #Mock.Errors
		Mock.FromClient(remote, a, nil)
		for _, junk in ipairs({ 1, {}, "Court", "Home", "Plaza\0", string.rep("x", 100), true }) do
			Mock.FromClient(remote, a, junk)
			T.eq(select(2, GS.Travel(a, junk)), "junk", "hudtools: destination " .. (type(junk) == "string" and fmt("%q", string.sub(junk, 1, 8)) or type(junk)) .. " is junk")
		end
		T.eq(select(2, GS.Travel(nil, "Plaza")), "junk", "hudtools: a nil player is junk")
		advance(0.1)
		T.eq(#Mock.Errors, errs, "hudtools: QuickTravel with garbage raises no errors")
		T.eq(a:GetAttribute(attr), nil, "hudtools: ...and opens no portal (the Court destination is gone)")

		-- a spamming client gets one portal per 3 s
		local opened = 0
		for _ = 1, 8 do
			local before = a:GetAttribute(attr)
			Mock.FromClient(remote, a, "Plaza")
			advance(0.1)
			if a:GetAttribute(attr) ~= before then
				opened = opened + 1
			end
		end
		T.eq(opened, 1, "hudtools: QuickTravel spam (8 presses in 0.8 s) opens one portal")

		-- locked on the Obby pad in its party countdown: the real thing, untouched by a press
		advance(3.1)
		advance(10.5)
		Mock.Teleport(a, away)
		advance(0.1)
		K.enterPortal(a)
		advance(0.6)
		if T.check(PortalService.IsLocked(a), "hudtools: (setup) standing on the Obby pad locks the player in its countdown") then
			local party = PortalService.GetParty("Obby")
			local countdown = party and party.Countdown
			local okLocked = GS.Travel(a, "Plaza")
			party = PortalService.GetParty("Obby")
			T.check(okLocked ~= true and a:GetAttribute(attr) == nil and PortalService.IsLocked(a) and party and party.Countdown == countdown,
				"hudtools: refused on a portal pad's countdown, and the countdown is untouched")
		end
		PortalService.CancelParty("Obby")
		K.leavePortalArea(a)
		advance(0.5)

		c1:Disconnect()
		c2:Disconnect()
		K.removePlayers(players)
		K.flushErrors("hudtools_portal")
	end)

	S.hudtools_zone = guarded("hudtools_zone", function()
		if not K.needBoot() then
			return
		end
		local Config = K.config()
		local inZone = Config.InLobbyZone
		if not T.check(type(inZone) == "function", "hudtools zone: Config.InLobbyZone exists") then
			return
		end
		local info = K.W.lobbyInfo
		local O = Config.Lobby.Origin
		local PS = K.mod("PlayerService")
		local up = Vector3.new(0, 3, 0)
		T.check(inZone(PS.GetLobbySpawnCFrame().Position), "hudtools zone: the lobby spawn is in the zone")
		T.check(inZone(O + up), "hudtools zone: the plaza's middle is in the zone")
		for id, site in pairs(info.GateSites or {}) do
			T.check(inZone(site.Position + up), "hudtools zone: the Gate Court's " .. tostring(id) .. " gate is in the zone")
		end
		local shop = O + Config.Lobby.ShopOffset + up
		T.check(inZone(shop), "hudtools zone: the shop island is in the zone")
		for _, r in ipairs({ Config.Lobby.PlazaRadius, 221, 280 }) do
			T.check(inZone(O + Vector3.new(r, 3, 0)), "hudtools zone: " .. r .. " studs out (the plaza's rim, the garden islands, the spoke bridges) is in the zone")
		end
		T.check(not inZone(O + Vector3.new(0, 120, 0)) and not inZone(O + Vector3.new(0, -120, 0)), "hudtools zone: far above or below the plaza is not")
		T.check(not inZone(Vector3.new(0 / 0, 0, 0)) and not inZone(nil) and not inZone("plaza"), "hudtools zone: junk is not in the zone")

		-- every part of every home plot, the street, the arena island and the altar island: measured on the real build
		local function outside(label, model)
			if not T.check(model ~= nil, "hudtools zone: (setup) " .. label .. " exists") then
				return
			end
			local inside, total, sample = 0, 0, nil
			local list = model:IsA("BasePart") and { model } or model:GetDescendants()
			for _, part in ipairs(list) do
				if part:IsA("BasePart") then
					total = total + 1
					if inZone(part.Position) then
						inside = inside + 1
						sample = sample or part.Name
					end
				end
			end
			T.check(total > 0 and inside == 0, "hudtools zone: no part of " .. label .. " is in the zone", fmt("%d of %d, e.g. %s", inside, total, tostring(sample)))
		end
		local plots = 0
		for _, spot in ipairs(info.Spots or {}) do
			if typeof(spot.SpawnCFrame) == "CFrame" then
				plots = plots + 1
				T.check(not inZone(spot.SpawnCFrame.Position), "hudtools zone: home plot " .. plots .. "'s spawn is not in the zone")
			end
		end
		T.eq(plots, Config.Lobby.SpotCount, "hudtools zone: (setup) every home plot was checked")
		outside("the Battle Arena island", workspace:FindFirstChild("BattleArena"))
		outside("the Storm Altar island", info.Folder and info.Folder:FindFirstChild("StormAltar"))
		local Altar = K.mod("StormAltar")
		T.check(not inZone(Altar.GetLanding().Position), "hudtools zone: the Altar island's landing is not in the zone")
		T.check(typeof(workspace:GetAttribute(Config.Lobby.ZoneAltarAttr)) == "Vector3", "hudtools zone: the island's place is a Workspace attribute (the client reads it)")
		-- the plaza around the altar's direction stays lobby: the hole starts past the plaza's rim
		local at = workspace:GetAttribute(Config.Lobby.ZoneAltarAttr)
		local dirX, dirZ = at.X - O.X, at.Z - O.Z
		local len = math.sqrt(dirX * dirX + dirZ * dirZ)
		T.check(inZone(O + Vector3.new(dirX / len * Config.Lobby.PlazaRadius, 3, dirZ / len * Config.Lobby.PlazaRadius)), "hudtools zone: the plaza's rim right before the altar is still the lobby")
		local street = Config.Lobby.SpotRingRadius - (Config.Lobby.PlotSize / 2 + 4 + 7) -- the ring street's centre line
		T.check(not inZone(O + Vector3.new(street, 3, 0)), "hudtools zone: the ring street in front of the homes is not in the zone")
		T.check(not inZone(Config.Match.ArenaOrigin), "hudtools zone: a match course is not in the zone")
		K.flushErrors("hudtools_zone")
	end)

	S.hudtools_security = guarded("hudtools_security", function()
		if not K.needBoot() then
			return
		end
		local Config = K.config()
		local DS = K.mod("DataService")
		local joined = {}
		liveGame(Config, function()
			local owner = join(joined, "SecOwner", OWNER_ID)
			local stranger = join(joined, "SecStranger", 41001)
			local victim = join(joined, "SecVictim", 41002)
			local PetKeys = shared("PetKeys")
			T.check(PetKeys.Add(DS.GetProfile(stranger), shared("PetCatalog").Pets[1].Id, 1), "hudtools security: (setup) the stranger owns a pet")
			local key = PetKeys.List(DS.GetProfile(stranger))[1]
			local function snapshot()
				local levels = DS.GetProfile(stranger).PetLevels[key]
				local g = DS.GetGrowth(stranger, key)
				return tostring(levels and levels.Level) .. "/" .. tostring(g.Evo) .. "/" .. tostring(g.Speed)
			end
			local before = snapshot()
			local kicked, bans, unbans = #Mock.KickedPlayers, #Mock.BanLog, #Mock.UnbanLog
			local calls = {
				{ "kick", "SecVictim" }, { "kick", "SecVictim bye" }, { "ban", "SecVictim" }, { "ban", "41002 forever" }, { "unban", "41002" },
				{ "evolvepets" }, { "levelall", 50 }, { "maxpets" }, { "speed" },
				{ "kick" }, { "ban", {} }, { "levelall", "lots" }, { "speed", "on" },
			}
			for _, call in ipairs(calls) do
				send(stranger, call[1], call[2])
			end
			for _, line in ipairs({ "/kick SecVictim", "/ban SecVictim", "/unban SecVictim", "/evolvepets", "/levelall 100", "/maxpets", "/speed" }) do
				chat(stranger, line)
			end
			T.eq(#Mock.KickedPlayers, kicked, "hudtools security: a non-developer kicks nobody")
			T.eq(#Mock.BanLog, bans, "hudtools security: ...bans nobody")
			T.eq(#Mock.UnbanLog, unbans, "hudtools security: ...unbans nobody")
			T.check(victim.Parent ~= nil and owner.Parent ~= nil, "hudtools security: ...everybody is still in the server")
			T.eq(snapshot(), before, "hudtools security: ...their pets do not change")
			T.eq(hintOf(stranger, SPEED_HINT), nil, "hudtools security: ...and they get no speed hint")
			T.eq(#devToasts(stranger, 0), 0, "hudtools security: ...nor a DEV toast: nothing tells them the tools exist")
			-- the panel's list is only a hint for the developer: the server names no developer to anyone
			T.eq(stranger:GetAttribute(SPEED_HINT), nil, "hudtools security: the speed hint is never on the Player")
		end)
		leaveAll(joined)
		K.flushErrors("hudtools_security")
	end)

	S.hudtools_kick = guarded("hudtools_kick", function()
		if not K.needBoot() then
			return
		end
		local Config = K.config()
		local joined = {}
		liveGame(Config, function()
			local owner = join(joined, "KickOwner", OWNER_ID)
			local sam = join(joined, "SamTheKickable", 42001)
			local twinA = join(joined, "TwinAlpha", 42002)
			local twinB = join(joined, "TwinBeta", 42003)
			local exactA = join(joined, "Dana", 42004)
			local exactB = join(joined, "Danaher", 42005)

			local kicked = #Mock.KickedPlayers
			local mark = chat(owner, "/kick thekick griefing the lobby")
			T.check(sam.Parent == nil and #Mock.KickedPlayers == kicked + 1 and Mock.KickedPlayers[#Mock.KickedPlayers].player == sam, "hudtools kick: /kick with a partial unique name removes the player")
			T.check(has(Mock.KickedPlayers[#Mock.KickedPlayers].message, "griefing the lobby"), "hudtools kick: ...with the reason, through the text filter", tostring(Mock.KickedPlayers[#Mock.KickedPlayers].message))
			T.check(Mock.LastFiltered ~= nil and Mock.LastFiltered.From == OWNER_ID and Mock.LastFiltered.To == 42001, "hudtools kick: ...filtered from the developer to that player")
			local toast = lastToast(owner, mark)
			T.check(toast.kind == "good" and has(toast.text, "SamTheKickable"), "hudtools kick: ...and the developer's toast names them", toast.text)

			kicked = #Mock.KickedPlayers
			mark = chat(owner, "/kick twin")
			toast = lastToast(owner, mark)
			T.check(twinA.Parent ~= nil and twinB.Parent ~= nil and toast.kind == "bad" and has(toast.text, "TwinAlpha") and has(toast.text, "TwinBeta"), "hudtools kick: an ambiguous name kicks nobody and names the candidates", toast.text)

			mark = send(owner, "kick", "Dana")
			T.check(exactA.Parent == nil and exactB.Parent ~= nil, "hudtools kick: an exact name wins over a longer partial match")

			mark = chat(owner, "/kick KickOwner")
			toast = lastToast(owner, mark)
			T.check(owner.Parent ~= nil and toast.kind == "bad" and has(toast.text, "yourself"), "hudtools kick: you cannot kick yourself", toast.text)
			mark = chat(owner, "/kick nobodycalledthis")
			toast = lastToast(owner, mark)
			T.check(toast.kind == "bad" and has(toast.text, "nobodycalledthis"), "hudtools kick: an unknown name is refused", toast.text)
			kicked = #Mock.KickedPlayers
			for _, junk in ipairs({ 5, {}, true, "", "   ", string.rep("x", 400) }) do
				mark = send(owner, "kick", junk)
				T.eq(lastToast(owner, mark).kind, "bad", "hudtools kick: junk argument (" .. type(junk) .. (type(junk) == "string" and (" of " .. #junk) or "") .. ") is refused")
			end
			mark = send(owner, "kick")
			T.eq(lastToast(owner, mark).kind, "bad", "hudtools kick: no name is refused")
			T.eq(#Mock.KickedPlayers, kicked, "hudtools kick: ...and junk kicks nobody")

			-- no reason: a plain message; a filter that fails: the reason is dropped, never shown raw
			local noReason = join(joined, "NoReasonPlayer", 42006)
			send(owner, "kick", "NoReasonPlayer")
			T.check(noReason.Parent == nil and type(Mock.KickedPlayers[#Mock.KickedPlayers].message) == "string" and #Mock.KickedPlayers[#Mock.KickedPlayers].message > 0, "hudtools kick: without a reason the player still gets a plain message")
			local filterFail = join(joined, "FilterFailPlayer", 42007)
			Mock.FilterError = "HTTP 500"
			send(owner, "kick", "FilterFailPlayer secret words")
			Mock.FilterError = nil
			T.check(filterFail.Parent == nil and not has(Mock.KickedPlayers[#Mock.KickedPlayers].message, "secret words"), "hudtools kick: a failing text filter drops the reason (never the raw text)", tostring(Mock.KickedPlayers[#Mock.KickedPlayers].message))
		end)
		leaveAll(joined)
		K.flushErrors("hudtools_kick")
	end)

	S.hudtools_ban = guarded("hudtools_ban", function()
		if not K.needBoot() then
			return
		end
		local Config = K.config()
		local joined = {}
		liveGame(Config, function()
			local owner = join(joined, "BanOwner", OWNER_ID)
			local rude = join(joined, "RudeRalph", 43001)
			local admin = join(joined, "AdminAmy", 43002)
			Config.Dev.Admins = { 43002, 43003 } -- 43003: an admin who is not in the server
			Mock.KnownUsers = { OfflineOlga = 43004, OfflineAdmin = 43003, BanOwner = OWNER_ID }

			local bans = #Mock.BanLog
			local mark = chat(owner, "/ban rude spamming everyone")
			local entry = Mock.BanLog[#Mock.BanLog]
			if T.check(#Mock.BanLog == bans + 1 and entry ~= nil, "hudtools ban: /ban by partial name calls Players:BanAsync") then
				T.check(type(entry.UserIds) == "table" and #entry.UserIds == 1 and entry.UserIds[1] == 43001, "hudtools ban: ...for that one userId")
				T.eq(entry.Duration, -1, "hudtools ban: ...permanent (Duration -1)")
				T.eq(entry.ApplyToUniverse, true, "hudtools ban: ...for the whole universe")
				T.check(has(entry.DisplayReason, "spamming everyone") and #entry.DisplayReason <= 400, "hudtools ban: ...the reason is the DisplayReason (<= 400)", tostring(entry.DisplayReason))
				T.check(type(entry.PrivateReason) == "string" and has(entry.PrivateReason, tostring(OWNER_ID)) and #entry.PrivateReason <= 1000, "hudtools ban: ...the PrivateReason records who did it", tostring(entry.PrivateReason))
			end
			T.eq(rude.Parent, nil, "hudtools ban: ...and the engine removes the player")
			local toast = lastToast(owner, mark)
			T.check(toast.kind == "good" and has(toast.text, "RudeRalph"), "hudtools ban: ...the toast names them", toast.text)

			-- offline, by exact name or userId
			bans = #Mock.BanLog
			mark = chat(owner, "/ban OfflineOlga")
			T.check(#Mock.BanLog == bans + 1 and Mock.BanLog[#Mock.BanLog].UserIds[1] == 43004, "hudtools ban: an offline player by exact name", lastToast(owner, mark).text)
			T.check(type(Mock.BanLog[#Mock.BanLog].DisplayReason) == "string" and #Mock.BanLog[#Mock.BanLog].DisplayReason > 0, "hudtools ban: ...no reason still sends a DisplayReason (it is required)")
			bans = #Mock.BanLog
			chat(owner, "/ban 43005 botting")
			T.check(#Mock.BanLog == bans + 1 and Mock.BanLog[#Mock.BanLog].UserIds[1] == 43005, "hudtools ban: an offline player by userId")

			-- who cannot be banned: nothing reaches the API
			bans = #Mock.BanLog
			for _, case in ipairs({
				{ "/ban BanOwner", "yourself", "yourself by name" },
				{ "/ban " .. OWNER_ID, "yourself", "yourself by userId" },
				{ "/ban AdminAmy", "developer", "an allowed developer in the server" },
				{ "/ban 43002", "developer", "an allowed developer in the server, by userId" },
				{ "/ban OfflineAdmin", "developer", "an allowed developer who is offline, by name" },
				{ "/ban 43003", "developer", "an allowed developer who is offline, by userId" },
				{ "/ban nobody_at_all", "nobody_at_all", "an unknown name" },
			}) do
				mark = chat(owner, case[1])
				toast = lastToast(owner, mark)
				T.check(toast.kind == "bad" and has(toast.text, case[2]), "hudtools ban: refuses " .. case[3], toast.text)
			end
			T.check(admin.Parent ~= nil, "hudtools ban: ...the developer stays")
			-- a group-owned game: the group's owner cannot be told apart offline here, so nothing happens (no ban on a guess)
			game.CreatorType = Enum.CreatorType.Group
			game.CreatorId = 4040
			local savedRank = Mock.Classes.Player.methods.GetRankInGroup
			Mock.Classes.Player.methods.GetRankInGroup = function(self)
				return self.UserId == OWNER_ID and 255 or 0
			end
			mark = chat(owner, "/ban 43009")
			toast = lastToast(owner, mark)
			T.check(toast.kind == "bad" and has(toast.text, "nothing was done"), "hudtools ban: a group game whose owner cannot be read refuses an offline ban", toast.text)
			Mock.Classes.Player.methods.GetRankInGroup = savedRank
			game.CreatorType = Enum.CreatorType.User
			game.CreatorId = OWNER_ID
			for _, junk in ipairs({ 5, {}, true, "", "0", "-7", "1.5", "99999999999999999999999", string.rep("x", 400) }) do
				mark = send(owner, "ban", junk)
				T.eq(lastToast(owner, mark).kind, "bad", "hudtools ban: junk argument " .. fmt("%q", tostring(junk):sub(1, 12)) .. " is refused")
			end
			T.eq(#Mock.BanLog, bans, "hudtools ban: ...and none of that reached the API")

			-- the API's real answer, never a false success
			Mock.BanError = "HTTP 503 (service unavailable)"
			mark = chat(owner, "/ban 43006")
			toast = lastToast(owner, mark)
			T.check(toast.kind == "bad" and has(toast.text, "HTTP 503"), "hudtools ban: a failing BanAsync shows the real reason", toast.text)
			Mock.BanError = nil
			local Players = game:GetService("Players")
			Players.BanningEnabled = false
			mark = chat(owner, "/ban 43006")
			toast = lastToast(owner, mark)
			T.check(toast.kind == "bad" and has(toast.text, "BanningEnabled"), "hudtools ban: BanningEnabled off is said plainly", toast.text)
			mark = chat(owner, "/unban 43006")
			T.check(lastToast(owner, mark).kind == "bad" and has(lastToast(owner, mark).text, "BanningEnabled"), "hudtools ban: ...for /unban too", lastToast(owner, mark).text)
			Players.BanningEnabled = true

			-- Studio: bans run on live servers only (the docs): the toast says so, it never claims a ban
			Mock.Options.Studio = true
			bans = #Mock.BanLog
			mark = chat(owner, "/ban 43006")
			toast = lastToast(owner, mark)
			T.check(toast.kind == "bad" and has(toast.text, "Studio"), "hudtools ban: in Studio the toast says the ban does not apply", toast.text)
			Mock.Options.Studio = false

			-- unban
			local unbans = #Mock.UnbanLog
			mark = chat(owner, "/unban OfflineOlga")
			local un = Mock.UnbanLog[#Mock.UnbanLog]
			T.check(#Mock.UnbanLog == unbans + 1 and un.UserIds[1] == 43004 and un.ApplyToUniverse == true, "hudtools ban: /unban by name, in the ban's scope (ApplyToUniverse true)")
			T.eq(lastToast(owner, mark).kind, "good", "hudtools ban: ...with a good toast")
			unbans = #Mock.UnbanLog
			chat(owner, "/unban 43005")
			T.check(#Mock.UnbanLog == unbans + 1 and Mock.UnbanLog[#Mock.UnbanLog].UserIds[1] == 43005, "hudtools ban: /unban by userId")
			Mock.BanError = "HTTP 429"
			mark = chat(owner, "/unban 43005")
			T.check(lastToast(owner, mark).kind == "bad" and has(lastToast(owner, mark).text, "HTTP 429"), "hudtools ban: a failing UnbanAsync shows the real reason", lastToast(owner, mark).text)
			Mock.BanError = nil
			unbans = #Mock.UnbanLog
			for _, junk in ipairs({ 5, {}, "", "0", "-1", "nobody_at_all", string.rep("y", 400) }) do
				mark = send(owner, "unban", junk)
				T.eq(lastToast(owner, mark).kind, "bad", "hudtools ban: /unban junk " .. fmt("%q", tostring(junk):sub(1, 12)) .. " is refused")
			end
			T.eq(#Mock.UnbanLog, unbans, "hudtools ban: ...and reaches no API")
			Mock.KnownUsers = nil
		end)
		Mock.BanError = nil
		leaveAll(joined)
		K.flushErrors("hudtools_ban")
	end)

	S.hudtools_pets = guarded("hudtools_pets", function()
		if not K.needBoot() then
			return
		end
		local Config = K.config()
		local DS = K.mod("DataService")
		local PetKeys = shared("PetKeys")
		local PC = shared("PetCatalog")
		local BC = shared("BattleCatalog")
		local Care = K.mod("PetCareService")
		local joined = {}
		liveGame(Config, function()
			local owner = join(joined, "PetOwner", OWNER_ID)
			local prof = DS.GetProfile(owner)

			-- one Common stack of 3, one Epic (two evolutions), a Golden copy of it and a hybrid
			local common, epic = nil, nil
			for _, def in ipairs(PC.Pets) do
				if not common and PC.MaxEvolution(def) == 1 then
					common = def.Id
				elseif not epic and PC.MaxEvolution(def) == 2 then
					epic = def.Id
				end
			end
			if not T.check(common ~= nil and epic ~= nil, "hudtools pets: (setup) a one-stage and a two-stage pet exist") then
				return
			end
			local golden = PetKeys.Make(epic, "Golden")
			T.check(PetKeys.Add(prof, common, 3) and PetKeys.Add(prof, epic, 1) and PetKeys.Add(prof, golden, 1), "hudtools pets: (setup) the copies are owned")
			local hybrid = PetKeys.HybridKey("toolhyb1")
			T.check(PetKeys.Add(prof, hybrid, 1, { Body = common, Style = epic, Name = "Toolhyb" }), "hudtools pets: (setup) a hybrid is owned")
			advance(0.2)
			local keys = PetKeys.List(prof)
			T.check(#keys >= 4, "hudtools pets: (setup) the owner has every kind of key", table.concat(keys, ","))

			local function copies()
				local out = {}
				for _, key in ipairs(PetKeys.List(prof)) do
					out[#out + 1] = key .. "=" .. PetKeys.Count(prof, key)
				end
				table.sort(out)
				return table.concat(out, ",")
			end
			local function wallet()
				return fmt("%s/%s/%s/%s", tostring(prof.Tokens), tostring(prof.Cash), tostring(prof.Gems), tostring(prof.Berries))
			end
			local copiesBefore, walletBefore = copies(), wallet()

			-- equipped, on a team, in the garden, in training
			T.check(K.mod("PetService").Equip(owner, common) ~= false, "hudtools pets: (setup) the Common stack is equipped")
			prof.Teams.Presets[1] = { epic }
			advance(0.5)
			prof.Home.Garden = prof.Home.Garden or {}
			prof.Home.Garden[1] = golden
			local jobEnds = os.time() + 3600
			T.check(DS.MutateGrowth(owner, function(g)
				g[hybrid] = { Job = { Stat = "Speed", Ends = jobEnds, Rank = 1, Slot = 1, From = "Free", Paid = 300 } }
			end), "hudtools pets: (setup) the hybrid is training")

			----------------------------------------------------------------
			-- /evolvepets
			----------------------------------------------------------------
			local syncs = #K.remotesFor("ProfileSync", owner.UserId, 0)
			local evolved = {}
			local conn = Care.Evolved:Connect(function(p, key, stage)
				if p == owner then
					evolved[key] = stage
				end
			end)
			local mark = chat(owner, "/evolvepets")
			local toast = lastToast(owner, mark)
			T.check(toast.kind == "good" and has(toast.text, "evolved"), "hudtools pets: /evolvepets answers with a DEV toast", toast.text)
			T.eq(DS.GetEvolution(owner, common), 1, "hudtools pets: a level 1 Common stack evolves (no level requirement)")
			T.eq(DS.GetEvolution(owner, epic), 1, "hudtools pets: an Epic goes up ONE stage")
			T.eq(DS.GetEvolution(owner, golden), 1, "hudtools pets: a Golden copy has its own stage")
			T.check(DS.GetEvolution(owner, hybrid) >= 1, "hudtools pets: a hybrid evolves too")
			T.eq(evolved[common], 1, "hudtools pets: ...PetCareService.Evolved fires like the real EVOLVE (the podium pet rebuilds)")
			T.eq(copies(), copiesBefore, "hudtools pets: ...keys and copy counts do not change (the stage lives on the key)")
			T.eq(wallet(), walletBefore, "hudtools pets: ...it costs nothing")
			T.check(#K.remotesFor("ProfileSync", owner.UserId, 0) > syncs, "hudtools pets: ...and the client gets a Sync")
			local job = DS.GetGrowth(owner, hybrid).Job
			T.check(type(job) == "table" and job.Ends == jobEnds, "hudtools pets: ...a training pet keeps its running job", tostring(job))
			T.check(prof.Teams.Presets[1][1] == epic and prof.Home.Garden[1] == golden, "hudtools pets: ...the team and the garden keep their pets")
			T.check(#prof.Equipped >= 1 and prof.Equipped[1] == common, "hudtools pets: ...the equipped pet stays equipped")
			mark = send(owner, "evolvepets")
			T.eq(DS.GetEvolution(owner, epic), 2, "hudtools pets: a second press takes the Epic to stage 2")
			T.eq(DS.GetEvolution(owner, common), 1, "hudtools pets: ...the Common stays at 1: the 2nd evolution is Epic+ only")
			mark = send(owner, "evolvepets")
			mark = send(owner, "evolvepets")
			toast = lastToast(owner, mark)
			T.check(toast.kind == "info" and has(toast.text, "already"), "hudtools pets: with nothing left to evolve the toast says so", toast.text)
			T.eq(DS.GetEvolution(owner, epic), 2, "hudtools pets: ...and no stage goes above the top")
			conn:Disconnect()
			send(owner, "evolvepets", "all")
			T.eq(DS.GetEvolution(owner, common), 1, "hudtools pets: /evolvepets with a junk value is refused")

			owner:SetAttribute(Config.Attr.InBattle, "B9")
			local fresh = "__none"
			for _, def in ipairs(PC.Pets) do
				if def.Id ~= common and def.Id ~= epic then
					fresh = def.Id
					break
				end
			end
			PetKeys.Add(prof, fresh, 1)
			mark = send(owner, "evolvepets")
			T.check(lastToast(owner, mark).kind == "bad" and DS.GetEvolution(owner, fresh) == 0, "hudtools pets: /evolvepets is refused in a battle, like EVOLVE", lastToast(owner, mark).text)
			owner:SetAttribute(Config.Attr.InBattle, nil)

			local realProvisional = DS.IsProvisional
			DS.IsProvisional = function(p)
				return p == owner
			end
			for _, cmd in ipairs({ { "evolvepets" }, { "levelall", 7 }, { "maxpets" } }) do
				mark = send(owner, cmd[1], cmd[2])
				T.check(lastToast(owner, mark).kind == "bad" and has(lastToast(owner, mark).text, "loading"), "hudtools pets: /" .. cmd[1] .. " is refused on a provisional profile", lastToast(owner, mark).text)
			end
			DS.IsProvisional = realProvisional
			T.eq(DS.GetEvolution(owner, fresh), 0, "hudtools pets: ...nothing changed")

			----------------------------------------------------------------
			-- /levelall
			----------------------------------------------------------------
			mark = chat(owner, "/levelall 37")
			toast = lastToast(owner, mark)
			T.check(toast.kind == "good" and has(toast.text, "37"), "hudtools pets: /levelall answers with a DEV toast", toast.text)
			local allThere = true
			for _, key in ipairs(PetKeys.List(prof)) do
				local lv = DS.GetPetLevel(owner, key)
				if lv ~= 37 then
					allThere = false
				end
			end
			T.check(allThere, "hudtools pets: every pet I own is level 37, not only the equipped ones")
			send(owner, "levelall", 12)
			T.eq(DS.GetPetLevel(owner, epic), 12, "hudtools pets: levels may also go down (the panel's number box)")
			T.eq(DS.GetEvolution(owner, epic), 2, "hudtools pets: ...levels never touch the stage")
			for _, junk in ipairs({ 0, -3, 101, 1.5, 0 / 0, math.huge, "abc", {}, true }) do
				mark = send(owner, "levelall", junk)
				T.eq(lastToast(owner, mark).kind, "bad", "hudtools pets: /levelall " .. tostring(junk):sub(1, 8) .. " is refused")
			end
			mark = send(owner, "levelall")
			T.eq(lastToast(owner, mark).kind, "bad", "hudtools pets: /levelall without a number is refused")
			mark = chat(owner, "/levelall abc")
			T.eq(lastToast(owner, mark).kind, "bad", "hudtools pets: /levelall abc in chat is refused")
			T.eq(DS.GetPetLevel(owner, epic), 12, "hudtools pets: ...and no refused value changed a level")
			send(owner, "levelall", 100)
			T.eq(DS.GetPetLevel(owner, common), 100, "hudtools pets: /levelall 100 reaches the top")

			----------------------------------------------------------------
			-- /maxpets
			----------------------------------------------------------------
			send(owner, "levelall", 5)
			local powerBefore = BC.UnitPower({ PetId = common, Key = common, Level = DS.GetPetLevel(owner, common), Evo = DS.GetEvolution(owner, common) })
			owner:SetAttribute(Config.Attr.InBattle, "B9")
			mark = send(owner, "maxpets")
			T.check(lastToast(owner, mark).kind == "bad" and DS.GetPetLevel(owner, common) == 5, "hudtools pets: /maxpets is refused in a battle", lastToast(owner, mark).text)
			owner:SetAttribute(Config.Attr.InBattle, nil)
			local returned = {}
			local c2 = Care.TrainingDone:Connect(function(_, key, stat, rank)
				returned[#returned + 1] = tostring(key) .. ":" .. tostring(stat) .. ":" .. tostring(rank)
			end)
			mark = chat(owner, "/maxpets")
			c2:Disconnect()
			toast = lastToast(owner, mark)
			T.check(toast.kind == "good" and has(toast.text, "100"), "hudtools pets: /maxpets answers with a DEV toast", toast.text)
			local top = true
			local report = {}
			for _, key in ipairs(PetKeys.List(prof)) do
				local g = DS.GetGrowth(owner, key)
				local def = PetKeys.DefOf(key, prof)
				if DS.GetPetLevel(owner, key) ~= 100 or g.Evo ~= PC.MaxEvolution(def) or g.Speed ~= 10 or g.Physique ~= 10 or g.Ability ~= 10 or g.Defense ~= 10 then
					top = false
					report[#report + 1] = key
				end
			end
			T.check(top, "hudtools pets: every pet is level 100, at its top stage, with Speed, Physique, Ability and Defense at rank 10", table.concat(report, ","))
			T.eq(DS.GetGrowth(owner, hybrid).Job, nil, "hudtools pets: ...the training job is finished")
			T.check(#returned == 1 and returned[1] == hybrid .. ":Speed:1", "hudtools pets: ...through the real completion (TrainingDone), so the pet comes back", table.concat(returned, ";"))
			T.check(next(DS.TrainingKeys(owner)) == nil, "hudtools pets: ...and no pet is left locked in training")
			T.eq(copies():gsub(fresh .. "=1,?", ""), (copiesBefore:gsub(fresh .. "=1,?", "")), "hudtools pets: ...keys and copies do not change (tiers are other copies, not a level)")
			T.eq(wallet(), walletBefore, "hudtools pets: ...no currency moved (no refund for the finished job either)")
			T.check(prof.Teams.Presets[1][1] == epic and prof.Home.Garden[1] == golden and prof.Equipped[1] == common, "hudtools pets: ...team, garden and equipped keep their pets")
			local powerAfter = BC.UnitPower({ PetId = common, Key = common, Level = 100, Evo = 1, Train = DS.GetGrowth(owner, common) })
			T.check(powerAfter > powerBefore * 2, "hudtools pets: ...the battle power really rises", fmt("%d -> %d", powerBefore, powerAfter))

			-- the store keeps it: the session's values are what the next save merges
			mark = send(owner, "maxpets")
			T.eq(lastToast(owner, mark).kind, "info", "hudtools pets: a second /maxpets finds nothing to change", lastToast(owner, mark).text)
		end)
		leaveAll(joined)
		K.flushErrors("hudtools_pets")
	end)

	S.hudtools_speed = guarded("hudtools_speed", function()
		if not K.needBoot() then
			return
		end
		local Config = K.config()
		local DS = K.mod("DataService")
		local joined = {}
		liveGame(Config, function()
			local owner = join(joined, "SpeedOwner", OWNER_ID)
			T.eq(hintOf(owner, SPEED_HINT), nil, "hudtools speed: off by default")
			local mark = chat(owner, "/speed")
			T.eq(hintOf(owner, SPEED_HINT), true, "hudtools speed: /speed turns the hint on (on the developer's PlayerGui)")
			T.eq(owner:GetAttribute(SPEED_HINT), nil, "hudtools speed: ...never on the Player, which every client reads")
			T.check(has(lastToast(owner, mark).text, "on"), "hudtools speed: ...the toast says on", lastToast(owner, mark).text)
			if owner.LoadCharacter then
				owner:LoadCharacter()
				advance(1)
			end
			T.eq(hintOf(owner, SPEED_HINT), true, "hudtools speed: ...it survives a respawn")
			local prof = DS.GetProfile(owner)
			T.eq(prof.DevSpeed, nil, "hudtools speed: ...nothing is saved")
			mark = send(owner, "speed")
			T.eq(hintOf(owner, SPEED_HINT), nil, "hudtools speed: a second /speed turns it off")
			T.check(has(lastToast(owner, mark).text, "off"), "hudtools speed: ...the toast says off", lastToast(owner, mark).text)
			mark = send(owner, "speed", "fast")
			T.check(hintOf(owner, SPEED_HINT) == nil and lastToast(owner, mark).kind == "bad", "hudtools speed: a junk value is refused")

			-- a fresh session starts off (nothing was saved)
			send(owner, "speed")
			Mock.RemovePlayer(owner)
			advance(1)
			local back = join(joined, "SpeedOwner", OWNER_ID)
			T.eq(hintOf(back, SPEED_HINT), nil, "hudtools speed: back in a new session it is off again")

			-- /devhelp names everything (each toast fits a side toast)
			mark = chat(back, "/devhelp")
			local all = {}
			local fits = true
			for _, t in ipairs(devToasts(back, mark)) do
				all[#all + 1] = t.text
				fits = fits and #t.text <= 90
			end
			local text = table.concat(all, " ")
			for _, word in ipairs({ "/kick", "/ban", "/unban", "/evolvepets", "/levelall", "/speed", "/maxpets" }) do
				T.check(has(text, word), "hudtools speed: /devhelp lists " .. word, text)
			end
			T.check(fits, "hudtools speed: ...and every toast fits (<= 90 characters)", text)
			for _, word in ipairs({ "kick", "ban", "unban", "evolvepets", "levelall", "speed", "maxpets" }) do
				local listed = false
				for _, name in ipairs(require(Mock.GetPath(ROOTS["server"] .. "/Services/DevService")).Commands) do
					listed = listed or name == word
				end
				T.check(listed, "hudtools speed: DevService.Commands has " .. word)
			end
		end)
		leaveAll(joined)
		K.flushErrors("hudtools_speed")
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client half
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	local KC = _G.KC
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer
	local advance = KC.advance

	local function controller(name)
		if KC.M and KC.M[name] then
			return KC.M[name]
		end
		local inst = Mock.GetPath(ROOTS["client"] .. "/Controllers/" .. name)
		local ok, result = pcall(function()
			return inst and require(inst)
		end)
		return ok and type(result) == "table" and result or nil
	end
	local function playerGui()
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	local function press(action, state)
		return Mock.TriggerAction(action, state, Mock.NewInput(action == "NimbusDash" and "Q" or "LeftShift", "Keyboard", state))
	end
	local function named(root, name)
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end
	local function stamina()
		return LocalPlayer:GetAttribute("Stamina")
	end

	-- the character stands at `pos`, moving; everything is back to normal after fn
	local function standAt(pos, fn)
		local root = KC.root()
		local h = KC.hum()
		local savedCf = root.CFrame
		root.CFrame = CFrame.new(pos)
		h.MoveDirection = Vector3.new(0, 0, -1)
		advance(0.1)
		local ok, err = pcall(fn, h, root)
		Mock.KeysDown.LeftShift = false
		press("NimbusRun", "End")
		h.MoveDirection = Vector3.new(0, 0, 0)
		root.CFrame = savedCf
		advance(1.5)
		if not ok then
			T.fail("hudtools client: errored: " .. tostring(err))
		end
	end

	S.client_hudtools_stamina = guarded("client_hudtools_stamina", function()
		local MC = controller("MovementController")
		local Config = KC.env()
		local P = Config.Physics
		if not T.check(type(MC) == "table" and type(MC.GetSpeedState) == "function" and type(Config.InLobbyZone) == "function", "hudtools stamina: MovementController and Config.InLobbyZone exist") then
			return
		end
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		LocalPlayer:SetAttribute(Config.Attr.InBattle, nil)
		local O = Config.Lobby.Origin
		local plaza = O + Vector3.new(30, 3, 30)
		advance(6)

		standAt(plaza, function(h)
			T.check(stamina() >= P.MaxStamina - 0.01, "hudtools stamina: (setup) a full bar on the plaza", tostring(stamina()))
			Mock.KeysDown.LeftShift = true
			press("NimbusRun", "Begin")
			advance(P.MaxStamina / P.RunStaminaDrain + 3)
			T.check(stamina() >= P.MaxStamina - 0.01, "hudtools stamina: running on the plaza drains nothing, the bar stays full", tostring(stamina()))
			T.check(h.WalkSpeed > P.WalkSpeed + 6, "hudtools stamina: ...and the character still runs", tostring(h.WalkSpeed))
			T.eq(MC.GetSpeedState().Stamina, P.MaxStamina, "hudtools stamina: ...the stamina value itself is full")
			Mock.KeysDown.LeftShift = false
			press("NimbusRun", "End")
			advance(0.5)
			-- dashes: no stamina, the cooldown stays
			T.eq(MC.TryDash(), true, "hudtools stamina: a dash works on the plaza")
			advance(0.05)
			T.check(stamina() >= P.MaxStamina - 0.01, "hudtools stamina: ...and costs no stamina", tostring(stamina()))
			T.check(MC.GetDashCooldownFraction() > 0, "hudtools stamina: ...the dash cooldown still runs", tostring(MC.GetDashCooldownFraction()))
			T.eq(MC.TryDash(), false, "hudtools stamina: ...a second dash at once is refused by the cooldown")
			advance(P.DashCooldown + 0.3)
			T.eq(MC.TryDash(), true, "hudtools stamina: ...the next one works after the cooldown")
			advance(0.6)
		end)

		-- drains everywhere else
		local function drainsAt(label, pos, attrName, attrValue)
			advance(6)
			standAt(pos, function()
				if attrName then
					LocalPlayer:SetAttribute(attrName, attrValue)
				end
				advance(0.1)
				local before = stamina()
				Mock.KeysDown.LeftShift = true
				press("NimbusRun", "Begin")
				advance(1.2)
				T.check(stamina() < before - 5, "hudtools stamina: running drains " .. label, fmt("%.1f -> %.1f", before, stamina()))
				Mock.KeysDown.LeftShift = false
				press("NimbusRun", "End")
				if attrName then
					LocalPlayer:SetAttribute(attrName, attrName == Config.Attr.InMatch and false or nil)
				end
			end)
		end
		drainsAt("on the plaza in a match", plaza, Config.Attr.InMatch, true)
		drainsAt("on the plaza in a battle", plaza, Config.Attr.InBattle, "B1")
		drainsAt("on a home plot", O + Vector3.new(Config.Lobby.SpotRingRadius, 3, 0))
		drainsAt("past the homes (the Arena island)", O + Vector3.new(Config.Lobby.SpotRingRadius + 110, 3, 0))
		local altarAttr = Config.Lobby.ZoneAltarAttr
		local savedAltar = workspace:GetAttribute(altarAttr)
		workspace:SetAttribute(altarAttr, O + Vector3.new(-221, 0, 0))
		drainsAt("on the Altar island (inside the zone's radius, its hole)", O + Vector3.new(-221, 3, 0))
		drainsAt("on the Altar island's bridge", O + Vector3.new(-270, 3, 4))
		workspace:SetAttribute(altarAttr, savedAltar)
		drainsAt("far from the lobby (an obby course)", Config.Match.ArenaOrigin + Vector3.new(0, 3, 0))

		-- walking back in: a tired player gets the full bar at once, no exhaustion left
		advance(6)
		standAt(O + Vector3.new(Config.Lobby.SpotRingRadius, 3, 0), function(_, root)
			Mock.KeysDown.LeftShift = true
			press("NimbusRun", "Begin")
			advance(P.MaxStamina / P.RunStaminaDrain + 0.4)
			T.check(stamina() < P.MaxStamina * 0.5, "hudtools stamina: (setup) tired on a home plot", tostring(stamina()))
			root.CFrame = CFrame.new(plaza)
			advance(0.2)
			T.check(stamina() >= P.MaxStamina - 0.01, "hudtools stamina: stepping into the lobby fills the bar", tostring(stamina()))
		end)
		KC.flushErrors("client_hudtools_stamina")
	end)

	S.client_hudtools_speed = guarded("client_hudtools_speed", function()
		local MC = controller("MovementController")
		local Config = KC.env()
		local P = Config.Physics
		if not T.check(type(MC) == "table", "hudtools speed client: MovementController loads") then
			return
		end
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		LocalPlayer:SetAttribute(Config.Attr.InBattle, nil)
		local pg = playerGui()
		local O = Config.Lobby.Origin
		standAt(O + Vector3.new(0, 3, 40), function(h)
			h.WalkSpeed = P.WalkSpeed
			advance(0.3)
			T.near(h.WalkSpeed, P.WalkSpeed, 0.5, "hudtools speed client: off by default: normal walking speed")
			pg:SetAttribute(SPEED_HINT, true)
			advance(0.2)
			T.near(h.WalkSpeed, P.WalkSpeed * 2, 0.5, "hudtools speed client: on: walking is twice as fast")
			advance(2)
			T.near(h.WalkSpeed, P.WalkSpeed * 2, 0.5, "hudtools speed client: ...it does not stack with itself over time")
			pg:SetAttribute(SPEED_HINT, nil)
			advance(0.1)
			pg:SetAttribute(SPEED_HINT, true)
			advance(0.1)
			pg:SetAttribute(SPEED_HINT, nil)
			advance(0.1)
			pg:SetAttribute(SPEED_HINT, true)
			advance(0.2)
			T.near(h.WalkSpeed, P.WalkSpeed * 2, 0.5, "hudtools speed client: ...nor from toggling")
			Mock.KeysDown.LeftShift = true
			press("NimbusRun", "Begin")
			advance(1.5)
			T.near(h.WalkSpeed, P.RunSpeed * 2, 0.8, "hudtools speed client: running is twice as fast too")
			Mock.KeysDown.LeftShift = false
			press("NimbusRun", "End")
			advance(1.5)
			T.near(h.WalkSpeed, P.WalkSpeed * 2, 0.8, "hudtools speed client: ...back to twice the walk")

			-- the server still owns the base: a freeze wins and the base it writes back is doubled, once
			h.WalkSpeed = 0
			advance(0.2)
			T.near(h.WalkSpeed, 0, 0.01, "hudtools speed client: a server freeze (0) wins")
			h.WalkSpeed = P.WalkSpeed
			advance(0.2)
			T.near(h.WalkSpeed, P.WalkSpeed * 2, 0.5, "hudtools speed client: ...and after it the speed is twice the server's, once")

			-- a battle has legal speeds the server checks (the fighter's leash): they stand
			MC.SetBattleSpeed(14, 18)
			advance(0.2)
			T.near(h.WalkSpeed, 14, 0.5, "hudtools speed client: a battle's walk is not doubled (the server leash would pull the player back)")
			MC.SetBattleSpeed(nil)
			advance(0.2)
			T.near(h.WalkSpeed, P.WalkSpeed * 2, 0.5, "hudtools speed client: ...doubled again after it")
			LocalPlayer:SetAttribute(Config.Attr.InBattle, "D1")
			advance(0.2)
			T.near(h.WalkSpeed, P.WalkSpeed, 0.5, "hudtools speed client: no doubling while InBattle is set (a dungeon run between its fights)")
			LocalPlayer:SetAttribute(Config.Attr.InBattle, nil)
			advance(0.2)
			MC.SetCinematic(9)
			advance(0.2)
			T.near(h.WalkSpeed, 9, 0.5, "hudtools speed client: a scripted walk is not doubled")
			MC.SetCinematic(nil)
			advance(0.2)
			T.near(h.WalkSpeed, P.WalkSpeed * 2, 0.5, "hudtools speed client: ...doubled again after it")

			pg:SetAttribute(SPEED_HINT, nil)
			advance(0.2)
			T.near(h.WalkSpeed, P.WalkSpeed, 0.5, "hudtools speed client: off: the server's speed exactly")
		end)
		-- a respawn while it is on: the hint is still there, the new humanoid is doubled once
		pg:SetAttribute(SPEED_HINT, true)
		advance(0.2)
		Mock.Respawn(LocalPlayer)
		advance(1)
		local h2 = KC.hum()
		h2.MoveDirection = Vector3.new(0, 0, -1)
		advance(0.3)
		T.near(h2.WalkSpeed, P.WalkSpeed * 2, 0.5, "hudtools speed client: after a respawn it is still on, doubled once")
		h2.MoveDirection = Vector3.new(0, 0, 0)
		pg:SetAttribute(SPEED_HINT, nil)
		advance(0.3)
		KC.flushErrors("client_hudtools_speed")
	end)

	-- the panel open on the current screen: gui, controller
	local function openPanel()
		local Dev = controller("DevController")
		local pg = playerGui()
		pg:SetAttribute("NC_Dev", true)
		advance(1)
		local g = pg:FindFirstChild("NimbusDev")
		if Dev.IsOpen() then
			Dev.Close()
			advance(0.2)
		end
		Dev.Open()
		advance(0.6)
		return g, Dev
	end
	local function lastCall(from)
		local calls = KC.serverCalls("DevCommand", from)
		return calls[#calls], #calls
	end

	S.client_hudtools_panel = guarded("client_hudtools_panel", function()
		local old = { Mock.Viewport.X, Mock.Viewport.Y }
		Mock.SetViewport(1920, 1080)
		local g, Dev = openPanel()
		if not T.check(g ~= nil and Dev ~= nil and Dev.IsOpen(), "hudtools panel: the Developer tools panel opens") then
			return
		end
		advance(0.5)

		-- what each new button sends
		for _, case in ipairs({ { "Dev_evolvepets", "evolvepets" }, { "Dev_maxpets", "maxpets" }, { "Dev_speed", "speed" } }) do
			local button = named(g, case[1])
			if T.check(button ~= nil, "hudtools panel: button " .. case[1] .. " exists") then
				local mark = #Mock.RemoteLog
				Mock.Click(button)
				advance(0.5)
				local call, n = lastCall(mark)
				T.check(n == 1 and call.args[1] == case[2], "hudtools panel: ..." .. case[1] .. " sends DevCommand('" .. case[2] .. "')", tostring(n))
			end
		end

		-- the level box
		local box, level = named(g, "Dev_levelbox"), named(g, "Dev_levelall")
		if T.check(box ~= nil and box:IsA("TextBox") and level ~= nil, "hudtools panel: a number box and a Level all pets button exist") then
			for _, case in ipairs({ { "50", 50 }, { "  7 ", 7 }, { "100", 100 }, { "1", 1 } }) do
				box.Text = case[1]
				local mark = #Mock.RemoteLog
				Mock.Click(level)
				advance(0.5)
				local call, n = lastCall(mark)
				T.check(n == 1 and call.args[1] == "levelall" and call.args[2] == case[2], "hudtools panel: the box '" .. case[1] .. "' sends levelall " .. case[2], call and tostring(call.args[2]) or "none")
			end
			-- junk still reaches the server, which refuses it with a toast (the box is only a hint)
			box.Text = "abc"
			local mark = #Mock.RemoteLog
			Mock.Click(level)
			advance(0.5)
			local call = lastCall(mark)
			T.check(call and call.args[2] == "abc", "hudtools panel: a junk box is sent as it is: the server's refusal toast answers", call and tostring(call.args[2]) or "none")
		end

		-- the speed toggle shows on / off
		local speed = named(g, "Dev_speed")
		if speed then
			T.check(string.find(string.lower(speed.Text), "off", 1, true) ~= nil, "hudtools panel: the 2x speed toggle says off", speed.Text)
			playerGui():SetAttribute(SPEED_HINT, true)
			advance(0.1)
			T.check(string.find(string.lower(speed.Text), "on", 1, true) ~= nil and string.find(string.lower(speed.Text), "off", 1, true) == nil, "hudtools panel: ...on when the server says so", speed.Text)
			playerGui():SetAttribute(SPEED_HINT, nil)
			advance(0.1)
			T.check(string.find(string.lower(speed.Text), "off", 1, true) ~= nil, "hudtools panel: ...and off again", speed.Text)
		end

		-- the player list: everyone in the server, live
		local me = named(g, "DevPlayer_" .. LocalPlayer.UserId)
		T.check(me ~= nil, "hudtools panel: the list shows me")
		T.check(me and named(me, "Dev_kick_" .. LocalPlayer.UserId) == nil and named(me, "Dev_ban_" .. LocalPlayer.UserId) == nil, "hudtools panel: ...without Kick / Ban on my own row")
		local other = Mock.AddPlayer("PanelVictim", 77001)
		advance(0.5)
		local row = named(g, "DevPlayer_77001")
		local kick = row and named(row, "Dev_kick_77001")
		local ban = row and named(row, "Dev_ban_77001")
		if T.check(row ~= nil and kick ~= nil and ban ~= nil, "hudtools panel: a player who joins gets a row with Kick and Ban") then
			local mark = #Mock.RemoteLog
			Mock.Click(kick)
			advance(0.5)
			local call, n = lastCall(mark)
			T.check(n == 1 and call.args[1] == "kick" and call.args[2] == "PanelVictim", "hudtools panel: Kick sends DevCommand('kick', name)", call and tostring(call.args[2]) or "none")

			local banText = ban.Text
			mark = #Mock.RemoteLog
			Mock.Click(ban)
			advance(0.1)
			T.eq(select(2, lastCall(mark)), 0, "hudtools panel: the first tap on Ban sends nothing")
			T.check(string.find(ban.Text, "sure", 1, true) ~= nil, "hudtools panel: ...it asks 'Are you sure?'", ban.Text)
			Mock.Click(ban)
			advance(0.1)
			T.eq(select(2, lastCall(mark)), 0, "hudtools panel: a double tap never bans")
			advance(0.7)
			Mock.Click(ban)
			advance(0.2)
			call, n = lastCall(mark)
			T.check(n == 1 and call.args[1] == "ban" and call.args[2] == "PanelVictim", "hudtools panel: the second, separate tap sends DevCommand('ban', name)", call and tostring(call.args[2]) or "none")
			T.eq(ban.Text, banText, "hudtools panel: ...and the button goes back to its label")
			advance(0.7)
			mark = #Mock.RemoteLog
			Mock.Click(ban)
			advance(5)
			T.eq(ban.Text, banText, "hudtools panel: an armed Ban disarms itself")
			Mock.Click(ban)
			advance(0.1)
			T.eq(select(2, lastCall(mark)), 0, "hudtools panel: ...and then needs two taps again")
			Dev.Close()
			advance(0.2)
			T.eq(ban.Text, banText, "hudtools panel: closing the panel disarms it")
			Dev.Open()
			advance(0.6)
		end
		Mock.RemovePlayer(other)
		advance(0.5)
		T.eq(named(g, "DevPlayer_77001"), nil, "hudtools panel: a player who leaves loses the row")
		Dev.Close()
		advance(0.3)
		playerGui():SetAttribute("NC_Dev", nil)
		advance(0.5)
		Mock.SetViewport(old[1], old[2])
		advance(0.5)
		KC.flushErrors("client_hudtools_panel")
	end)

	S.client_hudtools_panel_mobile = guarded("client_hudtools_panel_mobile", function()
		local other = Mock.AddPlayer("PhoneVictim", 77002)
		for _, size in ipairs({ { 390, 844 }, { 844, 390 } }) do
			Mock.SetViewport(size[1], size[2])
			advance(1)
			local g, Dev = openPanel()
			if T.check(g ~= nil and Dev ~= nil and Dev.IsOpen(), "hudtools phone: the panel opens at " .. size[1] .. "x" .. size[2]) then
				for _, name in ipairs({ "Dev_evolvepets", "Dev_maxpets", "Dev_speed", "Dev_levelbox", "Dev_levelall", "Dev_kick_77002", "Dev_ban_77002" }) do
					local inst = named(g, name)
					if T.check(inst ~= nil, "hudtools phone: " .. name .. " exists") then
						T.check(inst.AbsoluteSize.Y >= 36 and inst.AbsoluteSize.X >= 44, fmt("hudtools phone %dx%d: %s is a thumb's size (>= 44 x 36 px)", size[1], size[2], name), fmt("%.0f x %.0f", inst.AbsoluteSize.X, inst.AbsoluteSize.Y))
					end
				end
				local kick, ban = named(g, "Dev_kick_77002"), named(g, "Dev_ban_77002")
				if kick and ban then
					local a, b = kick.AbsolutePosition, ban.AbsolutePosition
					local apart = a.X + kick.AbsoluteSize.X <= b.X or b.X + ban.AbsoluteSize.X <= a.X
					T.check(apart, "hudtools phone: Kick and Ban do not overlap")
					T.check(ban.TextSize * 0.8 >= 14, "hudtools phone: the row's text stays readable (>= 14 px)", tostring(ban.TextSize))
				end
				Dev.Close()
				advance(0.3)
			end
		end
		Mock.RemovePlayer(other)
		playerGui():SetAttribute("NC_Dev", nil)
		advance(0.5)
		Mock.SetViewport(390, 844)
		advance(0.5)
		KC.flushErrors("client_hudtools_panel_mobile")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
