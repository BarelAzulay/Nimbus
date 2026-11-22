-- smoke_evo_buttons.lua: the buttons of evolved forms (docs/superpowers/specs/2026-11-01-evolved-forms-design.md; plan Task 5), loaded by
-- tools/smoke.py in BOTH worlds (ARGS.context):
--   evo_target_server         (server world, pure) the sim's Target order: junk / a benched enemy / an ally / my own unit -> BadTarget, 50 of them
--                             in one step -> ONE Order { rejected }, Target(nil) clears the lock and the pet keeps its engaged target, the
--                             lock is the engaged target on the next step. (BattleService.Command's table argument needs a booted server:
--                             that pin lives in smoke_p5_battleservice.lua's p5 cmd.)
--   client_evo_target         (client world) F / X / the TARGET button: a tap = ONE Target(the next enemy) on release, ZERO Attack; a hold =
--                             ONE Target(nil) at 0.4 s and nothing on release; no lock: a hold sends nothing; a dead lock is never sent; one
--                             enemy left: nothing sent, the caption says ONE ENEMY; a slide off the button / a Cancel sends nothing; a click or
--                             a tap on an enemy picks it; a click on nothing sends nothing; Tab / RT cycle, T / LT clear; every battle mode
--   client_evo_names          (client world) the Special and Element captions are the attack's name at the pet's stage, a swap changes them;
--                             TARGET flashes NEXT / AUTO; the Pets window names the form
--   client_evo_keys           (client world) the key chips (keyboard and gamepad), Special the big button in Attack's old slot, Target the small
--                             one in Special's old slot, the names under the buttons at 1080p and on a laptop, the help text
--   client_evo_buttons_mobile (phone world) 844x390, 740x360, 749x388, 667x375, 1024x768, 390x844, 360x640: (Pitch 2 item 1b, the three keys) MOVE (Element)
--                             >= 56 px, Dash >= 44, no SPECIAL / TARGET key; nothing overlaps the stick / jump / vitals / Cheer up! / another button;
--                             the longest names (the special's on MOVE with a full meter) fit inside the faces in 2 lines at >= 14 px
--   keys_three_buttons        (phone world) Pitch 2 item 1b option C "Three buttons": MOVE / DASH / RUN only, steady across states, the HOLD special,
--                             TARGET automatic + a tap locks with the LOCKED marker, CHEER / BACK with the helper portraits; (look review r0)
--                             each key one block (glyph over name inside the face, the glyph kept beside a cooldown's seconds), the HOLD tag
--                             pinned across MOVE's top edge, 8 px off Roblox's rings, CHEER / BACK 52 px, the top card off the keys, and the
--                             360 x 640 raid full (top card in its tall column): CHEER / BACK with the team, off the stick and the foot;
--                             (look review r1) CHEER / BACK 40 px off DASH / MOVE / RUN, each helper's Swap (and its hit pad) and cell
--                             off Roblox's stick ring, the helpers' buff names whole, at 360x640, 640x360, 667x375, 390x844 and 844x390;
--                             (look review r2) the HUD's cards (top card, enemy list rows and "+n more", fighter card, helpers) keep
--                             clear of MOVE / DASH / RUN and MOVE's HOLD tag, the list 8 px off Roblox's rings, in the raid, the full
--                             raid, the dungeon, the duel and the ring (at rest and with the meter full) at every phone size, 640x360 too
-- The mock has no real font metrics (TextFits is always true, TextBounds counts 0.5 em a character, TextScaled is not modelled), so a name's fit
-- is judged here by a wrap at a generous 0.62 em a character (Builder Sans Bold capitals), against the label's real box.
-- White-box: the sim's units and teams (same Lua state). Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, floor, huge, max, min = math.abs, math.floor, math.huge, math.max, math.min
local fmt = string.format

----------------------------------------------------------------------------------------------------
-- the server world
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K

	local function shared(name)
		local inst = K.moduleInstance("shared/" .. name)
		if not inst then
			return nil
		end
		local ok, m = pcall(require, inst)
		return ok and type(m) == "table" and m or nil
	end

	local function pets(n)
		local out = {}
		for i = 1, n do
			out[i] = { Key = "biscuit_bear", Level = 18, NoSpecial = true, Slot = i }
		end
		return out
	end

	local function stand(u, x, z)
		u.x, u.z, u.px, u.pz = x, z, x, z
		u.moveSpeed, u.nextAttack, u.hit = 0, huge, 0
		u.maxHp, u.hp = 1e7, 1e7
	end

	S.evo_target_server = guarded("evo_target_server", function()
		local BS = shared("BattleSim")
		if not T.check(BS ~= nil, "evo target server: BattleSim loads") then
			return
		end
		-- me (3 pets) and an ally on side 1, a player's team (fighter + 2 on its bench) and two wild bears on side 2
		local b = BS.new({ Mode = "Duel", Seed = 7, Zone = { X = 160, Z = 160 }, TimeLimit = 300, Teams = {
			{ Owner = 1, Side = 1, Pets = pets(3) },
			{ Owner = 2, Side = 1, Pets = pets(1) },
			{ Owner = 3, Side = 2, Pets = pets(3) },
			{ Owner = "npc", Side = 2, Npc = true, Specials = false, Pets = pets(2) },
		} })
		if not T.check(b ~= nil, "evo target server: (setup) a battle") then
			return
		end
		local tm = b.teams[1]
		local f = tm.fighter
		local ally = b.teams[2].fighter
		local benched, foes = nil, {}
		for _, u in ipairs(b.units) do
			if u.side == 2 then
				if u.benched then
					benched = u
				else
					foes[#foes + 1] = u
				end
			end
			stand(u, u.side == 1 and -8 or 0, 0)
		end
		for i, u in ipairs(foes) do
			stand(u, 10 * i, 10)
		end
		T.check(benched ~= nil and #foes == 3, "evo target server: (setup) a benched enemy and three on the floor", #foes .. " on the floor")
		for _, bad in ipairs({ "junk", 0, -1, 1.5, 999, benched and benched.id, ally.id, f.id, true }) do
			local ok, why = b:Command(1, "Target", bad)
			T.check(ok == false and why == "BadTarget" and tm.lock == nil, "evo target server: Target(" .. tostring(bad) .. ") is refused BadTarget and locks nothing", tostring(why))
		end
		-- every refusal above went out in one step: one echo, and 50 more in the next step: one more
		local function rejected(events)
			local n = 0
			for _, ev in ipairs(events) do
				if ev.type == "Order" and ev.order == "Target" and ev.rejected ~= nil then
					n = n + 1
				end
			end
			return n
		end
		T.check(rejected(b:Step(0.05)) == 1, "evo target server: a step's refusals send one Order { rejected }")
		for _ = 1, 50 do
			b:Command(1, "Target", 999)
		end
		T.check(rejected(b:Step(0.05)) == 1, "evo target server: 50 refused Target commands in one step send one Order { rejected }")
		-- the lock is the engaged target on the next step; Target(nil) clears it and the pet stays on its enemy
		local far = foes[3]
		T.check(b:Command(1, "Target", far.id) == true and tm.lock == far, "evo target server: Target(id) locks it")
		b:Step(0.05)
		T.check(tm.engage ~= nil and tm.engage.target == far, "evo target server: the pet goes after the lock on the next step", tm.engage and tostring(tm.engage.target and tm.engage.target.id) or "no engage")
		local other = foes[1]
		b:Command(1, "Target", other.id)
		b:Step(0.05)
		T.check(tm.engage ~= nil and tm.engage.target == other, "evo target server: a new lock moves the pet to it")
		T.check(b:Command(1, "Target") == true and tm.lock == nil, "evo target server: Target(nil) clears the lock")
		local echo = nil
		local events = b:Step(0.05)
		for _, ev in ipairs(events) do
			if ev.type == "Order" and ev.order == "Target" and ev.owner == 1 then
				echo = ev
			end
		end
		T.check(echo ~= nil and echo.target == nil and echo.rejected == nil, "evo target server: ...and echoes an Order with no target")
		T.check(tm.engage ~= nil and tm.engage.target == other, "evo target server: ...and the pet keeps its engaged target")
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- the client worlds
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local KC = _G.KC
	local S = {}
	local Players = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")
	local LocalPlayer = Players.LocalPlayer

	local H = {}

	function H.moduleAt(top, rest)
		local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end

	function H.step(n, dt)
		for _ = 1, n or 1 do
			Mock.Step(dt)
		end
	end

	function H.find(path)
		local pg = LocalPlayer:FindFirstChild("PlayerGui")
		local cur = pg and pg:FindFirstChild("NimbusBattle")
		for name in string.gmatch(path, "[^%.]+") do
			if not cur then
				return nil
			end
			cur = cur:FindFirstChild(name)
		end
		return cur
	end

	function H.text(kind)
		local cap = H.find("Root.Commands." .. kind .. "Button.Caption")
		return cap and cap.Text or "nil"
	end

	function H.commands(index)
		local out = {}
		for _, e in ipairs(KC.serverCalls("BattleCommand", index)) do
			out[#out + 1] = { action = e.args[1], arg = e.args[2] }
		end
		return out
	end

	function H.count(index, action)
		local n = 0
		for _, c in ipairs(H.commands(index)) do
			if c.action == action then
				n = n + 1
			end
		end
		return n
	end

	local function shownIn(obj)
		local cur = obj
		while cur and cur ~= game do
			if cur:IsA("LayerCollector") then
				if cur.Enabled == false then
					return false
				end
			elseif cur:IsA("GuiObject") and cur.Visible == false then
				return false
			end
			cur = cur.Parent
		end
		return cur ~= nil
	end

	local function rectOf(inst)
		local g = inst:FindFirstAncestorOfClass("ScreenGui")
		local dy = (g and g.IgnoreGuiInset) and -(Mock.TopInset or 0) or 0
		local p, s = inst.AbsolutePosition, inst.AbsoluteSize
		return { x0 = p.X, y0 = p.Y + dy, x1 = p.X + s.X, y1 = p.Y + s.Y + dy }
	end

	local function overlaps(a, b)
		return a.x0 < b.x1 - 1 and b.x0 < a.x1 - 1 and a.y0 < b.y1 - 1 and b.y0 < a.y1 - 1
	end

	local function rstr(r)
		return fmt("%.0f,%.0f-%.0f,%.0f", r.x0, r.y0, r.x1, r.y1)
	end

	-- a battle fed to the client the way BattleService sends it; my BattleCommand calls are forwarded into the sim unless noForward
	local Driver = {}
	Driver.__index = Driver

	-- opts: Mode (Duel), Pets (my team), Spots (standing frogs; Duel), Dungeon wave of 3 / the storm titan / a Ring champion by mode
	function H.fight(opts)
		local Sim = H.moduleAt("shared", "BattleSim")
		local BCat = H.moduleAt("shared", "BattleCatalog")
		if not Sim or not BCat then
			return nil
		end
		local me = LocalPlayer.UserId
		local mode = opts.Mode or "Duel"
		local id = "evo_btn_" .. tostring(math.random(100000, 999999))
		local mine = opts.Pets or { { PetId = "ember_phoenix", Key = "ember_phoenix", Level = 30, Tier = "Normal", Slot = 1 } }
		for i, p in ipairs(mine) do
			p.Slot = i
			p.Key, p.Tier, p.Level = p.Key or p.PetId, p.Tier or "Normal", p.Level or 30
		end
		local setup = { Mode = mode, Seed = 23, Id = id, Zone = { X = 90, Z = 90 }, TimeLimit = 300, Teams = { { Owner = me, Side = 1, Pets = mine } } }
		if mode == "Raid" then
			setup.Boss = "storm_titan"
			-- (keys_three_buttons' raid full: render_gui's battle:raid:full, two more players' teams beside mine)
			for i, pets in ipairs(opts.Allies or {}) do
				setup.Teams[#setup.Teams + 1] = { Owner = 76 + i, Side = 1, Pets = pets, Auto = true }
			end
		elseif mode == "Ring" then
			-- (keys_three_buttons, look review r2: render_gui's "fighter" ring round 8 and its pack of three on the list)
			setup.Round = opts.Round or 1
			setup.Teams[2] = BCat.ChampionTeam(opts.Round or 1, opts.Round and 7 or 1)
		elseif mode == "Duel" then
			local frogs = {}
			for i = 1, #(opts.Spots or { {} }) do
				frogs[i] = { PetId = "puddle_frog", Key = "puddle_frog", Level = 20, Tier = "Normal", Slot = i }
			end
			setup.Teams[2] = { Owner = "frogs", Side = 2, Npc = true, Specials = false, Pets = frogs }
		end
		local sim = Sim.new(setup)
		if not sim then
			return nil
		end
		local d = setmetatable({ sim = sim, id = id, mode = mode, me = me, logIndex = #Mock.RemoteLog, last = {}, raid = opts.Raid,
			dungeon = (mode == "Dungeon") and { Floor = 2, Room = 1, Wave = 1, Waves = 3, Name = "Ember Hall", Element = "Flame" } or nil }, Driver)
		-- (white-box: the pet holds the point it stands on, so the distances the tests read stay put)
		sim.teams[1].noEngage = true
		local foes = 0
		for _, u in ipairs(sim.units) do
			u.maxHp, u.hp = 1e7, 1e7
			if u.side == 1 then
				u.x, u.z, u.px, u.pz = 0, 0, 0, 0
			else
				foes = foes + 1
				local p = opts.Spots and opts.Spots[foes]
				if p then
					u.x, u.z, u.px, u.pz = p[1], p[2], p[1], p[2]
				end
				u.moveSpeed, u.nextAttack, u.hit = 0, huge, 0
				for _, entry in ipairs(u.attacks or {}) do
					entry.nextAt = huge
				end
			end
		end
		d:start()
		d:step()
		if mode == "Dungeon" then
			local wave = {}
			for i = 1, 3 do
				-- (keys_three_buttons, look review r2: render_gui's battle:dungeon has a crowned mini-boss in its wave, its boss card)
				wave[i] = { PetId = "puddle_frog", Key = "puddle_frog", Level = 10, Tier = "Normal", Wild = true, Boss = (opts.MiniBoss and i == 3) or nil }
			end
			for i, info in ipairs(sim:SpawnEnemies(wave, { Wave = 1, Anchor = { 0, 10 } }) or {}) do
				local u = sim.units[info.id]
				u.nextAttack, u.hit, u.maxHp, u.hp, u.moveSpeed = huge, 0, 1e7, 1e7, 0
				u.x, u.z, u.px, u.pz = 6 + 6 * i, 6, 6 + 6 * i, 6
			end
		end
		d:run(1.2)
		return d
	end

	function Driver:start()
		local p = self.sim:Describe()
		p.BattleId = self.id
		p.Zone = { CFrame = CFrame.new(0, 200, 0), Size = Vector3.new(p.Zone.X, 30, p.Zone.Z), X = p.Zone.X, Z = p.Zone.Z }
		p.Names = { [tostring(self.me)] = LocalPlayer.Name }
		p.Side, p.Spectator, p.T = 1, false, self.sim:Time()
		p.Dungeon = self.dungeon
		p.Raid = self.raid -- (a raid's tier and boss id, as BattleService's Start carries them)
		local team = self.sim:TeamOf(self.me)
		p.Team = { Fighter = team.Fighter, Bench = team.Bench, Lives = team.Lives, Speed = team.Speed,
			Cooldowns = { Element = team.Cooldowns.Element, Dash = team.Cooldowns.Dash, Swap = team.Cooldowns.Swap, Cheer = team.Cooldowns.Cheer, Buff = {} } }
		LocalPlayer:SetAttribute("InBattle", self.id)
		KC.toClient("BattleState", "Start", p, self.id)
	end

	function Driver:step()
		if self.noForward then
			self.logIndex = #Mock.RemoteLog
		else
			for _, c in ipairs(H.commands(self.logIndex)) do
				pcall(self.sim.Command, self.sim, self.me, c.action, c.arg)
			end
			self.logIndex = #Mock.RemoteLog
		end
		local evs = self.sim:Step(0.1)
		if #evs > 0 then
			KC.toClient("BattleState", "Events", evs, self.id)
		end
		local snap = self.sim:SnapshotDelta(self.last)
		snap.BattleId = self.id
		KC.toClient("BattleState", "Snapshot", snap, self.id)
		H.step(3, 0.1 / 3)
		return evs
	end

	function Driver:run(seconds)
		for _ = 1, floor(seconds / 0.1 + 0.5) do
			self:step()
		end
	end

	-- the enemies on the floor, nearest to my fighter first (ties by id), the client's own rule
	function Driver:byDistance()
		local f = self.sim.teams[1].fighter
		local list = {}
		for _, u in ipairs(self.sim.units) do
			if u.side ~= 1 and u.alive and not u.gone and not u.benched then
				list[#list + 1] = { id = u.id, d = (u.x - f.x) ^ 2 + (u.z - f.z) ^ 2 }
			end
		end
		table.sort(list, function(a, b)
			if a.d ~= b.d then
				return a.d < b.d
			end
			return a.id < b.id
		end)
		local ids = {}
		for i, e in ipairs(list) do
			ids[i] = e.id
		end
		return ids
	end

	-- enemy `id` is knocked out (white-box), the KO event reaches the client unless `quiet`
	function Driver:kill(id, quiet)
		local u = self.sim.units[id]
		u.alive, u.hp, u.state = false, 0, self.sim.States and self.sim.States.Down or 5
		if not quiet then
			KC.toClient("BattleState", "Events", { { type = "KO", unit = id, owner = u.owner } }, self.id)
		end
		self:run(0.5) -- (events play on the render clock, which the snapshots drive)
	end

	function H.cleanup(BC, d)
		if d and BC.GetBattle() then
			KC.toClient("BattleState", "End", { BattleId = d.id, Mode = d.mode, Outcome = "Left", Won = false, Spectator = false, Reason = "Left" }, d.id)
		end
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.advance(15)
		local r = H.find("Root.ResultCard.Body.OkButton")
		if r and r.Visible then
			Mock.Click(r)
		end
		Mock.Step(0.1)
	end

	-- does `text` fit a box of (w x h) screen px at `px`? -> ok, lines, widest word (a greedy wrap at 0.62 em a character, a line 1.2 em tall)
	function H.fits(text, w, h, px)
		local charW = px * 0.62
		local lines, cur, widest = 1, 0, 0
		for word in text:gmatch("%S+") do
			local wl = #word * charW
			widest = max(widest, wl)
			if cur > 0 and cur + charW + wl > w then
				lines, cur = lines + 1, wl
			else
				cur = (cur > 0) and (cur + charW + wl) or wl
			end
		end
		return lines <= 2 and widest <= w and lines * px * 1.2 <= h, lines, widest
	end

	local FIVE = { { 8, 0 }, { 14, 3 }, { 20, -3 }, { 26, 6 }, { 32, -6 } }

	local function pressKey(name, key, kind, seconds)
		Mock.TriggerAction(name, "Begin", Mock.NewInput(key, kind, "Begin"))
		H.step(max(1, floor(seconds * 30 + 0.5)), 1 / 30)
		Mock.TriggerAction(name, "End", Mock.NewInput(key, kind, "End"))
	end

	------------------------------------------------------------------------------------------------
	-- client_evo_target
	------------------------------------------------------------------------------------------------
	S.client_evo_target = guarded("client_evo_target", function()
		local BC = H.moduleAt("client", "Controllers/BattleController")
		if not T.check(BC ~= nil, "evo target: BattleController loads") then
			return
		end
		local err0 = #Mock.Errors
		Mock.SetViewport(1920, 1080)
		H.step(3, 0.1)
		local d = H.fight({ Spots = FIVE })
		if not T.check(d ~= nil and BC.GetBattle() ~= nil, "evo target: (setup) my pet against five frogs") then
			return
		end
		d.noForward = true
		local order = d:byDistance()
		local start = #Mock.RemoteLog
		T.check(Mock.BoundActions.NimbusBattleSwitch ~= nil and Mock.BoundActions.NimbusBattleAttack == nil, "evo target: F / X is bound to NimbusBattleSwitch, the old action is gone")
		local key = Mock.BoundActions.NimbusBattleSwitch
		local keys = {}
		for _, k in ipairs(key and key.inputs or {}) do
			keys[k.Name] = true
		end
		T.check(keys.F and keys.ButtonX, "evo target: ...on F and ButtonX")
		-- a tap: one Target(the nearest) on release, nothing while it is down
		local idx = #Mock.RemoteLog
		Mock.TriggerAction("NimbusBattleSwitch", "Begin", Mock.NewInput("F", "Keyboard", "Begin"))
		H.step(6, 1 / 30)
		T.check(#H.commands(idx) == 0, "evo target: nothing is sent while F is down (a tap fires on release)", #H.commands(idx) .. " sent")
		Mock.TriggerAction("NimbusBattleSwitch", "End", Mock.NewInput("F", "Keyboard", "End"))
		local cmds = H.commands(idx)
		T.check(#cmds == 1 and cmds[1].action == "Target" and cmds[1].arg == order[1], "evo target: a tap of F sends ONE Target(the nearest enemy)", #cmds > 0 and (tostring(cmds[1].action) .. " " .. tostring(cmds[1].arg)) or "none")
		T.check(BC.GetBattle().Lock == order[1], "evo target: ...and the lock shows at once", tostring(BC.GetBattle().Lock))
		-- again: the next one by distance
		H.step(12, 1 / 30)
		idx = #Mock.RemoteLog
		pressKey("NimbusBattleSwitch", "F", "Keyboard", 0.2)
		cmds = H.commands(idx)
		T.check(#cmds == 1 and cmds[1].action == "Target" and cmds[1].arg == order[2], "evo target: a second tap sends ONE Target(the next enemy)", #cmds > 0 and tostring(cmds[1].arg) or "none")
		-- hold then release (Review Focus 3): Target(nil) at 0.4 s, none before, nothing on the release, never a switch first
		H.step(12, 1 / 30)
		idx = #Mock.RemoteLog
		Mock.TriggerAction("NimbusBattleSwitch", "Begin", Mock.NewInput("F", "Keyboard", "Begin"))
		H.step(9, 1 / 30) -- 0.3 s
		local early = #H.commands(idx)
		H.step(6, 1 / 30) -- 0.5 s
		cmds = H.commands(idx)
		T.check(early == 0 and #cmds == 1 and cmds[1].action == "Target" and cmds[1].arg == nil, "evo target: hold then release: F held 0.5 s sends ONE Target(nil), none before 0.4 s", fmt("early %d, %d sent", early, #cmds))
		T.check(H.text("Target") == "AUTO", "evo target: ...the caption says AUTO", H.text("Target"))
		local atRelease = #Mock.RemoteLog
		Mock.TriggerAction("NimbusBattleSwitch", "End", Mock.NewInput("F", "Keyboard", "End"))
		H.step(30, 1 / 30)
		T.check(#H.commands(atRelease) == 0, "evo target: ...and nothing on the release", #H.commands(atRelease) .. " sent")
		T.check(BC.GetBattle().Lock == nil, "evo target: ...the lock is gone")
		-- no lock: a hold sends nothing
		idx = #Mock.RemoteLog
		pressKey("NimbusBattleSwitch", "F", "Keyboard", 0.6)
		H.step(30, 1 / 30)
		T.eq(#H.commands(idx), 0, "evo target: with no lock a hold sends nothing")
		-- a Cancel (the key is taken away mid-press) sends nothing
		idx = #Mock.RemoteLog
		Mock.TriggerAction("NimbusBattleSwitch", "Begin", Mock.NewInput("F", "Keyboard", "Begin"))
		H.step(3, 1 / 30)
		Mock.TriggerAction("NimbusBattleSwitch", "Cancel", Mock.NewInput("F", "Keyboard", "Cancel"))
		H.step(20, 1 / 30)
		T.eq(#H.commands(idx), 0, "evo target: a cancelled press sends nothing")
		-- the mock camera projects every unit to the screen centre: a click there picks one, a click elsewhere nothing
		local vp = Mock.Viewport
		local centre = Vector3.new(vp.X / 2, vp.Y / 2 - 36, 0)
		idx = #Mock.RemoteLog
		Mock.FireSignal(UserInputService, "InputBegan", Mock.NewInput("Unknown", "MouseButton1", "Begin", { Position = centre }), false)
		H.step(24, 1 / 30)
		Mock.FireSignal(UserInputService, "InputEnded", Mock.NewInput("Unknown", "MouseButton1", "End", { Position = centre }))
		H.step(10, 1 / 30)
		cmds = H.commands(idx)
		local picked = cmds[1] and cmds[1].arg
		T.check(#cmds == 1 and cmds[1].action == "Target" and d.sim.units[picked] ~= nil and d.sim.units[picked].side == 2, "evo target: a world click on an enemy sends ONE Target(its id), held or not", #cmds .. " sent")
		idx = #Mock.RemoteLog
		Mock.FireSignal(UserInputService, "InputBegan", Mock.NewInput("Unknown", "MouseButton1", "Begin", { Position = centre }), false)
		Mock.FireSignal(UserInputService, "InputEnded", Mock.NewInput("Unknown", "MouseButton1", "End", { Position = centre }))
		H.step(10, 1 / 30)
		T.eq(#H.commands(idx), 0, "evo target: a click on the enemy already picked sends nothing")
		idx = #Mock.RemoteLog
		Mock.FireSignal(UserInputService, "InputBegan", Mock.NewInput("Unknown", "MouseButton1", "Begin", { Position = Vector3.new(30, 60, 0) }), false)
		Mock.FireSignal(UserInputService, "InputEnded", Mock.NewInput("Unknown", "MouseButton1", "End", { Position = Vector3.new(30, 60, 0) }))
		H.step(10, 1 / 30)
		T.eq(#H.commands(idx), 0, "evo target: a click on nothing sends nothing")
		-- a tap on a frog's screen point picks it (T clears first, so the tap is a change)
		pressKey("NimbusBattleTarget", "T", "Keyboard", 0.05)
		H.step(12, 1 / 30)
		idx = #Mock.RemoteLog
		local touch = Mock.NewInput("Unknown", "Touch", "Begin", { Position = centre })
		Mock.FireSignal(UserInputService, "InputBegan", touch, false)
		H.step(3, 1 / 30)
		touch.UserInputState = Enum.UserInputState.End
		Mock.FireSignal(UserInputService, "InputEnded", touch, false)
		H.step(3, 1 / 30)
		cmds = H.commands(idx)
		T.check(#cmds == 1 and cmds[1].action == "Target" and d.sim.units[cmds[1].arg] ~= nil, "evo target: a tap on an enemy sends ONE Target(its id)", #cmds .. " sent")
		pressKey("NimbusBattleTarget", "T", "Keyboard", 0.05)
		H.step(12, 1 / 30)
		-- dead lock: the lock's frog dies (the KO event), F tap -> the nearest living one, never the dead id
		idx = #Mock.RemoteLog
		pressKey("NimbusBattleSwitch", "F", "Keyboard", 0.1)
		T.check(BC.GetBattle().Lock == order[1], "evo target: dead lock: (setup) the nearest is locked", tostring(BC.GetBattle().Lock))
		d:kill(order[1])
		H.step(12, 1 / 30)
		idx = #Mock.RemoteLog
		pressKey("NimbusBattleSwitch", "F", "Keyboard", 0.1)
		cmds = H.commands(idx)
		T.check(#cmds == 1 and cmds[1].action == "Target" and cmds[1].arg == order[2], "evo target: dead lock: a tap after the lock's KO picks the nearest living enemy", #cmds > 0 and tostring(cmds[1].arg) or "none")
		-- a lock that died with the KO event still on its way: never the dead id, the next living one
		H.step(12, 1 / 30)
		BC._Unit(order[2]).hp = 0
		idx = #Mock.RemoteLog
		pressKey("NimbusBattleSwitch", "F", "Keyboard", 0.1)
		cmds = H.commands(idx)
		T.check(#cmds == 1 and cmds[1].arg ~= order[2] and cmds[1].arg == order[3], "evo target: dead lock: a lock at 0 HP before its KO event is never sent", #cmds > 0 and tostring(cmds[1].arg) or "none")
		d:kill(order[2])
		-- one enemy: the only enemy IS the lock: nothing sent, the caption says so
		H.step(12, 1 / 30)
		d:kill(order[4])
		T.check(BC.GetBattle().Lock == order[3], "evo target: one enemy: (setup) still locked on the third", tostring(BC.GetBattle().Lock))
		d:kill(order[5])
		local btn = H.find("Root.Commands.TargetButton")
		local shakes = btn and (btn:GetAttribute("Shakes") or 0) or 0
		idx = #Mock.RemoteLog
		pressKey("NimbusBattleSwitch", "F", "Keyboard", 0.1)
		T.eq(#H.commands(idx), 0, "evo target: one enemy: a tap on the only enemy, the lock, sends nothing")
		T.check(H.text("Target") == "ONE ENEMY", "evo target: one enemy: the caption says ONE ENEMY", H.text("Target"))
		T.check(btn and (btn:GetAttribute("Shakes") or 0) == shakes + 1, "evo target: one enemy: the button shakes, the refusal's wiggle")
		H.step(24, 1 / 30)
		T.check(H.text("Target") == "TARGET", "evo target: one enemy: ...for a moment, then TARGET again", H.text("Target"))
		-- the lock clears, one enemy still: nothing sent either
		pressKey("NimbusBattleSwitch", "F", "Keyboard", 0.5)
		H.step(24, 1 / 30)
		T.check(BC.GetBattle().Lock == nil, "evo target: one enemy: a hold still clears the lock")
		idx = #Mock.RemoteLog
		pressKey("NimbusBattleSwitch", "F", "Keyboard", 0.1)
		T.check(#H.commands(idx) == 0 and H.text("Target") == "ONE ENEMY", "evo target: one enemy: no lock: a tap sends nothing and says so too", H.text("Target"))
		H.step(24, 1 / 30)
		T.eq(H.count(start, "Attack"), 0, "evo target: the HUD never sends Attack any more")
		H.cleanup(BC, d)

		-- gamepad X: the same tap / hold; Tab / RT cycle, T / LT clear
		d = H.fight({ Spots = FIVE })
		if T.check(d ~= nil, "evo target: (setup) five frogs for the gamepad") then
			d.noForward = true
			order = d:byDistance()
			start = #Mock.RemoteLog
			idx = #Mock.RemoteLog
			pressKey("NimbusBattleSwitch", "ButtonX", "Gamepad1", 0.15)
			cmds = H.commands(idx)
			T.check(#cmds == 1 and cmds[1].action == "Target" and cmds[1].arg == order[1], "evo target: gamepad X: a tap = Target(the nearest)", #cmds .. " sent")
			H.step(12, 1 / 30)
			idx = #Mock.RemoteLog
			pressKey("NimbusBattleSwitch", "ButtonX", "Gamepad1", 0.6)
			H.step(12, 1 / 30)
			cmds = H.commands(idx)
			T.check(#cmds == 1 and cmds[1].action == "Target" and cmds[1].arg == nil, "evo target: gamepad X: a hold = ONE Target(nil)", #cmds .. " sent")
			idx = #Mock.RemoteLog
			Mock.TriggerAction("NimbusBattleTarget", "Begin", Mock.NewInput("Tab", "Keyboard", "Begin"))
			cmds = H.commands(idx)
			T.check(#cmds == 1 and cmds[1].arg == order[1], "evo target: Tab cycles", #cmds .. " sent")
			H.step(12, 1 / 30)
			idx = #Mock.RemoteLog
			Mock.TriggerAction("NimbusBattleTarget", "Begin", Mock.NewInput("ButtonR2", "Gamepad1", "Begin"))
			cmds = H.commands(idx)
			T.check(#cmds == 1 and cmds[1].arg == order[2], "evo target: RT cycles", #cmds .. " sent")
			H.step(12, 1 / 30)
			idx = #Mock.RemoteLog
			Mock.TriggerAction("NimbusBattleTarget", "Begin", Mock.NewInput("ButtonL2", "Gamepad1", "Begin"))
			cmds = H.commands(idx)
			T.check(#cmds == 1 and cmds[1].action == "Target" and cmds[1].arg == nil, "evo target: LT clears", #cmds .. " sent")
			H.step(12, 1 / 30)
			idx = #Mock.RemoteLog
			Mock.TriggerAction("NimbusBattleTarget", "Begin", Mock.NewInput("Tab", "Keyboard", "Begin"))
			H.step(12, 1 / 30)
			Mock.TriggerAction("NimbusBattleTarget", "Begin", Mock.NewInput("T", "Keyboard", "Begin"))
			cmds = H.commands(idx)
			T.check(#cmds == 2 and cmds[2].action == "Target" and cmds[2].arg == nil, "evo target: T clears", #cmds .. " sent")
			H.step(12, 1 / 30)

			-- the TARGET button: mouse and touch, the same gesture; a slide off it sends nothing
			btn = H.find("Root.Commands.TargetButton")
			T.check(btn ~= nil and shownIn(btn), "evo target: the TARGET button is shown")
			local function onBtn()
				local a, s = btn.AbsolutePosition, btn.AbsoluteSize
				return Vector3.new(a.X + s.X / 2, a.Y + s.Y / 2, 0)
			end
			local function buttonPress(kind, seconds)
				local inp = Mock.NewInput("Unknown", kind, "Begin", { Position = onBtn() })
				Mock.FireSignal(btn, "InputBegan", inp, false)
				H.step(max(1, floor(seconds * 30 + 0.5)), 1 / 30)
				inp.UserInputState = Enum.UserInputState.End
				Mock.FireSignal(btn, "InputEnded", inp, false)
				Mock.FireSignal(UserInputService, "InputEnded", inp, false)
				H.step(20, 1 / 30)
			end
			for _, kind in ipairs(btn and { "MouseButton1", "Touch" } or {}) do
				idx = #Mock.RemoteLog
				buttonPress(kind, 0.15)
				cmds = H.commands(idx)
				T.check(#cmds == 1 and cmds[1].action == "Target" and d.sim.units[cmds[1].arg] ~= nil, "evo target: the button (" .. kind .. "): a tap = ONE Target(next), its own InputEnded and the global one count once", #cmds .. " sent")
				H.step(12, 1 / 30)
				idx = #Mock.RemoteLog
				buttonPress(kind, 0.6)
				cmds = H.commands(idx)
				T.check(#cmds == 1 and cmds[1].action == "Target" and cmds[1].arg == nil, "evo target: the button (" .. kind .. "): a hold = ONE Target(nil)", #cmds .. " sent")
				H.step(12, 1 / 30)
				-- slid off and held past 0.4 s, then released off it
				idx = #Mock.RemoteLog
				local inp = Mock.NewInput("Unknown", kind, "Begin", { Position = onBtn() })
				Mock.FireSignal(btn, "InputBegan", inp, false)
				H.step(4, 1 / 30)
				inp.Position = onBtn() + Vector3.new(-260, -220, 0)
				inp.UserInputState = Enum.UserInputState.Change
				H.step(20, 1 / 30)
				inp.UserInputState = Enum.UserInputState.End
				Mock.FireSignal(UserInputService, "InputEnded", inp, false)
				H.step(10, 1 / 30)
				T.eq(#H.commands(idx), 0, "evo target: the button (" .. kind .. "): a slide off it, held and released off it, sends nothing")
				-- slid off and lifted at 0.1 s, before any frame could see it
				idx = #Mock.RemoteLog
				inp = Mock.NewInput("Unknown", kind, "Begin", { Position = onBtn() })
				Mock.FireSignal(btn, "InputBegan", inp, false)
				inp.Position = onBtn() + Vector3.new(-260, -220, 0)
				inp.UserInputState = Enum.UserInputState.End
				Mock.FireSignal(UserInputService, "InputEnded", inp, false)
				H.step(20, 1 / 30)
				T.eq(#H.commands(idx), 0, "evo target: the button (" .. kind .. "): a lift off it within a frame sends nothing")
			end
			T.eq(H.count(start, "Attack"), 0, "evo target: ...and still no Attack")
			H.cleanup(BC, d)
		end

		-- every battle mode: the key is bound, and a tap switches or says there is only one enemy
		for _, mode in ipairs({ "Dungeon", "Raid", "Ring" }) do
			d = H.fight({ Mode = mode })
			if T.check(d ~= nil and BC.GetBattle() ~= nil, "evo target: (setup) a " .. mode .. " fight") then
				d.noForward = true
				local ids = d:byDistance()
				idx = #Mock.RemoteLog
				pressKey("NimbusBattleSwitch", "F", "Keyboard", 0.1)
				cmds = H.commands(idx)
				if #ids >= 2 then
					T.check(#cmds == 1 and cmds[1].action == "Target" and cmds[1].arg == ids[1], "evo target: " .. mode .. ": a tap = Target(the nearest)", #cmds .. " sent")
				else
					T.check(#cmds == 0 and H.text("Target") == "ONE ENEMY", "evo target: " .. mode .. ": one enemy on the floor: says so, sends nothing", H.text("Target"))
				end
				H.step(24, 1 / 30)
				H.cleanup(BC, d)
			end
		end
		T.check(#Mock.Errors == err0, "evo target: no script errors", tostring(Mock.Errors[#Mock.Errors]))
		KC.flushErrors("client_evo_target")
	end)

	------------------------------------------------------------------------------------------------
	-- client_evo_names
	------------------------------------------------------------------------------------------------
	S.client_evo_names = guarded("client_evo_names", function()
		local BC = H.moduleAt("client", "Controllers/BattleController")
		local BCat = H.moduleAt("shared", "BattleCatalog")
		if not T.check(BC ~= nil and BCat ~= nil, "evo names: BattleController and BattleCatalog load") then
			return
		end
		local err0 = #Mock.Errors
		Mock.SetViewport(1920, 1080)
		H.step(3, 0.1)
		for _, case in ipairs({
			{ Evo = 0, Special = "MARSHMALLOW POUNCE", Element = "RADIANCE", Swap = "SNOW WALL", SwapElement = "FROSTBITE" },
			{ Evo = 1, Special = "MARSHMALLOW STAMPEDE", Element = "HALO", Swap = "SNOWSPIKE WALL", SwapElement = "DEEP FROST" },
		}) do
			local d = H.fight({ Spots = FIVE, Pets = {
				{ PetId = "mallow_kitten", Evo = case.Evo }, { PetId = "pip_penguin", Evo = case.Evo }, { PetId = "pebble_pup" },
			} })
			local tag = "evo names (stage " .. case.Evo .. "): "
			if T.check(d ~= nil and BC.GetBattle() ~= nil, tag .. "(setup) the fight") then
				T.check(H.text("Special") == case.Special, tag .. "the Special button reads the attack's name", H.text("Special"))
				T.check(H.text("Element") == case.Element, tag .. "the Element button reads the element attack's name", H.text("Element"))
				T.check(H.text("Dash") == "DASH", tag .. "DASH stays DASH", H.text("Dash"))
				T.check(H.text("Target") == "TARGET", tag .. "TARGET reads TARGET", H.text("Target"))
				-- a tap flashes NEXT for NEXT_FLASH, a hold flashes AUTO
				d.noForward = true
				pressKey("NimbusBattleSwitch", "F", "Keyboard", 0.1)
				T.check(H.text("Target") == "NEXT", tag .. "a tap flashes NEXT", H.text("Target"))
				H.step(12, 1 / 30)
				T.check(H.text("Target") == "NEXT", tag .. "...still at 0.4 s", H.text("Target"))
				H.step(9, 1 / 30)
				T.check(H.text("Target") == "TARGET", tag .. "...and TARGET after 0.6 s", H.text("Target"))
				pressKey("NimbusBattleSwitch", "F", "Keyboard", 0.45)
				T.check(H.text("Target") == "AUTO", tag .. "a hold flashes AUTO", H.text("Target"))
				H.step(21, 1 / 30)
				T.check(H.text("Target") == "TARGET", tag .. "...and TARGET after 0.6 s", H.text("Target"))
				d.noForward = false
				d.logIndex = #Mock.RemoteLog
				-- a swap: the new fighter's names
				T.check(BC.Command("Swap", 2) == true, tag .. "(setup) swap the Frost pet in")
				d:run(0.6)
				T.check(H.text("Special") == case.Swap, tag .. "a swap: the Special button reads the new fighter's attack", H.text("Special"))
				T.check(H.text("Element") == case.SwapElement, tag .. "a swap: ...and its element attack", H.text("Element"))
				H.cleanup(BC, d)
			end
		end
		-- the Pets window names the form
		local MC = (KC.M and KC.M.MenuController) or H.moduleAt("client", "Controllers/MenuController")
		local Config = H.moduleAt("shared", "Config")
		if T.check(MC ~= nil and Config ~= nil, "evo names: MenuController loads") then
			LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
			local pets = { mallow_kitten = 1, starlight_unicorn = 1, pebble_pup = 1 }
			KC.toClient("ProfileSync", {
				Tokens = 900, Pets = pets, Equipped = { "pebble_pup" }, Items = {}, Discovered = pets, IndexClaimed = {},
				Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
				Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
				Tutorial = { Step = 99, Done = true, Gifted = true }, Cash = 500000, Gems = 50, Berries = 2000,
				PetLevels = { mallow_kitten = { Level = 25, Xp = 0 }, starlight_unicorn = { Level = 60, Xp = 0 }, pebble_pup = { Level = 2, Xp = 0 } },
				PetGrowth = { mallow_kitten = { Evo = 1 }, starlight_unicorn = { Evo = 2 } },
				Teams = { Presets = { { "pebble_pup" }, {}, {} }, Active = 1, Slots = 3 },
			})
			KC.advance(0.5)
			local function perkText(key)
				MC.Open("Pets", { Key = key })
				KC.advance(1.5)
				local gui = LocalPlayer.PlayerGui:FindFirstChild("NimbusPets")
				local perks, special = nil, nil
				for _, o in ipairs(gui and gui:GetDescendants() or {}) do
					if o.Name == "Perks" then
						perks = o
					elseif o.Name == "SpecialText" then
						special = o
					end
				end
				-- (LOOK-ui, kitb-look1) the special sits on its own strip right above the perks list
				local text = (special and special.Text ~= "" and (special.Text .. "\n") or "") .. (perks and tostring(perks.Text) or "")
				MC.Close()
				KC.advance(0.4)
				return text
			end
			local one, two, none = perkText("mallow_kitten"), perkText("starlight_unicorn"), perkText("pebble_pup")
			T.check(one:find("^Special: Marshmallow Stampede\n") ~= nil, "evo names: the Pets window of a stage-1 kitten says Special: Marshmallow Stampede", one)
			T.check(two:find("^Special: Wish Upon the Stars\n") ~= nil, "evo names: ...of a stage-2 unicorn, Wish Upon the Stars", two)
			T.check(none:find("^Special: Fetch Dash") ~= nil, "evo names: ...and a stage-0 pet keeps today's name", none)
		end
		T.check(#Mock.Errors == err0, "evo names: no script errors", tostring(Mock.Errors[#Mock.Errors]))
		KC.flushErrors("client_evo_names")
	end)

	------------------------------------------------------------------------------------------------
	-- client_evo_keys
	------------------------------------------------------------------------------------------------
	S.client_evo_keys = guarded("client_evo_keys", function()
		local BC = H.moduleAt("client", "Controllers/BattleController")
		local ND = H.moduleAt("shared", "NpcDialog")
		if not T.check(BC ~= nil and ND ~= nil, "evo keys: BattleController and NpcDialog load") then
			return
		end
		local err0 = #Mock.Errors
		for _, size in ipairs({ { 1920, 1080, 14 }, { 1366, 768, 14 } }) do
			Mock.SetViewport(size[1], size[2])
			H.step(3, 0.1)
			local tag = "evo keys " .. size[1] .. "x" .. size[2] .. ": "
			local d = H.fight({ Spots = FIVE, Pets = { { PetId = "starlight_unicorn", Evo = 2 } } })
			if T.check(d ~= nil and BC.GetBattle() ~= nil, tag .. "(setup) the fight") then
				local special, target = H.find("Root.Commands.SpecialButton"), H.find("Root.Commands.TargetButton")
				local element, dash = H.find("Root.Commands.ElementButton"), H.find("Root.Commands.DashButton")
				T.check(special ~= nil and target ~= nil and element ~= nil and dash ~= nil and H.find("Root.Commands.AttackButton") == nil, tag .. "SPECIAL, TARGET, ELEMENT, DASH; no ATTACK")
				if special and target then
					T.eq(special.Size.X.Offset, 88, tag .. "Special is the big button (K.ATTACK_D)")
					T.eq(target.Size.X.Offset, 64, tag .. "Target is a small one (K.ACTION_D)")
					-- (kit-b gate, keys look r5 c05, ab11837: a PC cluster now stands high enough for a two-line name tag under
					-- SPECIAL, so below 1920 x 1080 every key rises by the same lift, 4 design px at 1366 x 768; the pinned -98 / -90
					-- went stale. Not weaker: X stays exact, 1920 x 1080 keeps the old spots, both keys share one lift, and the
					-- caption checks below still hold the tag on screen) the spots Attack and Special had, raised together
					local lift = -98 - special.Position.Y.Offset
					T.check(special.Position.X.Offset == -74 and lift >= 0 and lift <= 12 and (size[1] < 1920 or lift == 0), tag .. "Special sits where Attack sat (the PC cluster's lift for SPECIAL's two-line tag: " .. tostring(lift) .. ")", tostring(special.Position))
					T.check(target.Position.X.Offset == -74 - 44 - 26 - 32 and target.Position.Y.Offset == -90 - lift, tag .. "Target sits where Special sat (the same lift)", tostring(target.Position))
					T.check(special.AbsoluteSize.X > element.AbsoluteSize.X and special.AbsoluteSize.X > target.AbsoluteSize.X and special.AbsoluteSize.X > dash.AbsoluteSize.X, tag .. "Special is the biggest button")
				end
				local function chip(kind)
					local t = H.find("Root.Commands." .. kind .. "Button.Key.Text")
					return t and t.Text or "nil"
				end
				T.check(chip("Target") == "F" and chip("Special") == "Q" and chip("Element") == "E", tag .. "the key chips: Target F, Special Q, Element E", chip("Target") .. " " .. chip("Special"))
				Mock.FireSignal(UserInputService, "InputBegan", Mock.NewInput("ButtonA", "Gamepad1", "Begin"), false)
				H.step(2, 1 / 30)
				T.check(chip("Target") == "X" and chip("Special") == "RB" and chip("Element") == "Y", tag .. "...on a gamepad: Target X, Special RB, Element Y", chip("Target") .. " " .. chip("Special"))
				Mock.FireSignal(UserInputService, "InputBegan", Mock.NewInput("F", "Keyboard", "Begin"), false)
				H.step(2, 1 / 30)
				T.check(chip("Target") == "F", tag .. "...and F again on the keyboard", chip("Target"))
				-- the longest name under the button: on screen, at most 2 lines, clear of the next button
				local cap = H.find("Root.Commands.SpecialButton.Caption")
				T.check(cap ~= nil and shownIn(cap) and cap.Text == "WISH UPON THE STARS", tag .. "the Special caption is the long name, shown", cap and cap.Text or "nil")
				if cap then
					local r = rectOf(cap)
					local scale = H.find("Root.ReadScale")
					local px = cap.TextSize * (scale and scale.Scale or 1)
					local ok, lines, widest = H.fits(cap.Text, r.x1 - r.x0, r.y1 - r.y0, px)
					T.check(ok and cap.TextWrapped == true, tag .. "...fits 2 lines under the button", fmt("%d lines, widest %.0f, box %.0fx%.0f, %.1f px", lines, widest, r.x1 - r.x0, r.y1 - r.y0, px))
					T.check(px >= 13.99, tag .. "...at the HUD's readable size", fmt("%.1f px", px))
					T.check(r.x0 >= 0 and r.x1 <= Mock.Viewport.X and r.y1 <= Mock.Viewport.Y - (Mock.TopInset or 0), tag .. "...whole on the screen", rstr(r))
					local tcap = H.find("Root.Commands.TargetButton.Caption")
					-- "MARSHMALLOW" must not break either: a 11-letter word on one line (LOOK-ui2: the tag is sized to the name it
					-- shows, clamped to the key's width + 16 unless a word needs more, so the long name is placed and measured)
					local Hud0 = BC._Hud
					local A0 = Hud0 and Hud0.buttons and Hud0.buttons.Special
					local oldText = cap.Text
					cap.Text = "MARSHMALLOW STAMPEDE"
					Hud0.PlaceFace(A0, A0.Button.Size.X.Offset, Hud0.m)
					local r2 = rectOf(cap)
					ok, lines, widest = H.fits(cap.Text, r2.x1 - r2.x0, r2.y1 - r2.y0, px)
					cap.Text = oldText
					Hud0.PlaceFace(A0, A0.Button.Size.X.Offset, Hud0.m)
					T.check(ok and r2.x0 >= 0 and r2.x1 <= Mock.Viewport.X, tag .. "...and the longest word fits on one line", fmt("widest %.0f, box %.0f", widest, r2.x1 - r2.x0))
					T.check(tcap ~= nil and tcap.Text == "TARGET", tag .. "the Target caption", tcap and tcap.Text or "nil")
					-- Element's two lines stay above Special's top edge
					local ecap = H.find("Root.Commands.ElementButton.Caption")
					local er, sr = rectOf(ecap), rectOf(special)
					T.check(er.y1 <= sr.y0 + 1, tag .. "the Element caption's box ends above the Special button", rstr(er) .. " vs " .. rstr(sr))
				end
				H.cleanup(BC, d)
			end
		end
		Mock.SetViewport(1920, 1080)
		H.step(3, 0.1)
		-- the help text
		local sparky = ND.Get and ND.Get("sparky_fox")
		local all = table.concat(sparky and sparky.Lines or {}, " ")
		T.check(all:find("F = SWITCH TARGET", 1, true) ~= nil and all:find("ATTACK picks who", 1, true) == nil,
			"evo keys: Sparky Fox names SWITCH TARGET and no longer \"ATTACK picks who\"", all)
		local key = false
		for _, k in ipairs(sparky and sparky.Keywords or {}) do
			key = key or k == "SWITCH TARGET"
		end
		T.check(key, "evo keys: ...and it is one of his keywords")
		local coach = ND.Get and ND.Get("coach_corgi")
		T.check(coach ~= nil and coach.Lines[5]:find("tap TARGET for the next enemy, hold for automatic", 1, true) ~= nil and coach.Lines[5]:find("ATTACK", 1, true) == nil, "evo keys: Coach Corgi's team line says what a tap and a hold do", coach and coach.Lines[5] or "nil")
		T.check(#Mock.Errors == err0, "evo keys: no script errors", tostring(Mock.Errors[#Mock.Errors]))
		KC.flushErrors("client_evo_keys")
	end)

	------------------------------------------------------------------------------------------------
	-- client_evo_buttons_mobile
	------------------------------------------------------------------------------------------------
	S.client_evo_buttons_mobile = guarded("client_evo_buttons_mobile", function()
		local BC = H.moduleAt("client", "Controllers/BattleController")
		if not T.check(BC ~= nil, "evo phone: BattleController loads") then
			return
		end
		local err0 = #Mock.Errors
		-- what the cluster must keep clear of (Roblox's stick and jump button: Hud.TouchRects' numbers; the vitals; every other gui's buttons)
		local function obstacles()
			local out = {}
			local pg = LocalPlayer:FindFirstChild("PlayerGui")
			for _, g in ipairs(pg and pg:GetChildren() or {}) do
				if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "NimbusBattle" and g.Name ~= "NimbusBattleFx" then
					for _, o in ipairs(g:GetDescendants()) do
						if o:IsA("GuiButton") and shownIn(o) and o.AbsoluteSize.X > 4 and o.AbsoluteSize.X < 400 then
							out[#out + 1] = { g.Name .. "." .. o.Name, rectOf(o) }
						end
					end
					local vitals = g:FindFirstChild("Vitals", true)
					if vitals and vitals:IsA("GuiObject") and shownIn(vitals) and vitals.AbsoluteSize.X > 0 then
						out[#out + 1] = { g.Name .. ".Vitals", rectOf(vitals) }
					end
				end
			end
			local vp = Mock.Viewport
			local areaY = vp.Y - (Mock.TopInset or 0)
			local small = min(vp.X, vp.Y) <= 500
			local j = small and 70 or 120
			local jb = small and 20 or j * 0.75
			out[#out + 1] = { "Roblox jump", { x0 = vp.X - j * 1.5 - 10, y0 = areaY - jb - j, x1 = vp.X - j * 0.5 - 10, y1 = areaY - jb } }
			local stickW = small and 110 or 190
			local stickH = small and ((vp.Y > vp.X) and 150 or 96) or 210
			out[#out + 1] = { "Roblox stick", { x0 = 0, y0 = areaY - stickH, x1 = stickW, y1 = areaY } }
			local root = H.find("Root")
			for _, block in ipairs(root and root:GetChildren() or {}) do
				if block:IsA("GuiObject") and block.Name ~= "Commands" and block.Name ~= "CheerGlow" and shownIn(block) and block.AbsoluteSize.X > 0 then
					out[#out + 1] = { "Battle." .. block.Name, rectOf(block) }
				end
			end
			-- (kit-b) the enemy list's "+n more" tag by its own box (on a portrait phone it may hang under the list's left end)
			local more = H.find("Root.Enemies.More")
			if more and shownIn(more) and more.AbsoluteSize.X > 0 then
				out[#out + 1] = { "Battle.Enemies.More", rectOf(more) }
			end
			return out
		end
		-- (kit-b Pitch 2 item 1b, option C "Three buttons", the owner's pick 2026-11-20: the four-key phone cluster is gone. A touch
		-- screen's right thumb has MOVE (the ELEMENT key, which also holds the special: its name shows on it with a full meter)
		-- and DASH here, RUN in MobileControls; no SPECIAL and no TARGET key (TARGET is automatic). The sizes, the overlaps and
		-- the names below hold for MOVE and DASH; keys_three_buttons checks the hold, the lock and the steadiness)
		local MIN_PX = { Element = 56, Dash = 44 }
		-- (P2 fix A) a real player's HUD: Cash, Gems and the tokens (three strips: the narrow stack in a battle, so the right
		-- column starts low). Alone this list ran with the tokens strip only and passed; the whole suite (whose earlier lists
		-- set Cash and Gems) found the enemy list on DASH at 360 x 640
		local Config = H.moduleAt("shared", "Config")
		local oldCash, oldGems = LocalPlayer:GetAttribute(Config.Attr.Cash), LocalPlayer:GetAttribute(Config.Attr.Gems)
		LocalPlayer:SetAttribute(Config.Attr.Cash, oldCash or 48200)
		LocalPlayer:SetAttribute(Config.Attr.Gems, oldGems or 320)
		for _, size in ipairs({ { 844, 390 }, { 740, 360 }, { 749, 388 }, { 667, 375 }, { 1024, 768 }, { 390, 844 }, { 360, 640 } }) do
			Mock.SetViewport(size[1], size[2])
			H.step(15, 1 / 30)
			local tag = "evo phone " .. size[1] .. "x" .. size[2] .. ": "
			local d = H.fight({ Mode = "Dungeon", Pets = { { PetId = "starlight_unicorn", Evo = 2 } } })
			if T.check(d ~= nil and BC.GetBattle() ~= nil, tag .. "(setup) a dungeon fight") then
				local rects = {}
				for kind, px in pairs(MIN_PX) do
					local b = H.find("Root.Commands." .. kind .. "Button")
					if T.check(b ~= nil and shownIn(b), tag .. kind .. " is shown") then
						local r = rectOf(b)
						rects[kind] = r
						T.check(r.x1 - r.x0 >= px - 0.01 and r.y1 - r.y0 >= px - 0.01, tag .. kind .. " is at least " .. px .. " px", fmt("%.1f", r.x1 - r.x0))
						T.check(r.x0 >= 0 and r.y0 >= 0 and r.x1 <= size[1] and r.y1 <= size[2] - (Mock.TopInset or 0), tag .. kind .. " is on the screen", rstr(r))
					end
				end
				for _, kind in ipairs({ "Special", "Target" }) do
					local b = H.find("Root.Commands." .. kind .. "Button")
					T.check(b == nil or not shownIn(b), tag .. "no " .. string.upper(kind) .. " key on touch (the three keys)")
				end
				if rects.Element and rects.Dash then
					T.check(rects.Element.x1 - rects.Element.x0 > rects.Dash.x1 - rects.Dash.x0, tag .. "MOVE (the element + the special) is the biggest")
					local kinds = { "Element", "Dash" }
					local bad = {}
					for i, a in ipairs(kinds) do
						for j = i + 1, #kinds do
							if overlaps(rects[a], rects[kinds[j]]) then
								bad[#bad + 1] = a .. " on " .. kinds[j]
							end
						end
						for _, o in ipairs(obstacles()) do
							if overlaps(rects[a], o[2]) then
								bad[#bad + 1] = fmt("%s %s on %s %s", a, rstr(rects[a]), o[1], rstr(o[2]))
							end
						end
					end
					T.check(#bad == 0, tag .. "nothing overlaps (the buttons, the stick, the jump button, the vitals, Cheer up!, another button)", table.concat(bad, "; "))
				end
				-- (kit-b U9-6: the readability floor, 14 px on a phone) the names sit on a stone tag along the face's bottom edge, sized
				-- by the HUD for the name it shows (Hud.PlaceFaceName): never TextScaled, the longest special name in 2 lines at 14 px
				local Hud = BC._Hud
				local function tryName(kind, capName, name)
					local A = Hud and Hud.buttons and Hud.buttons[kind]
					local c = H.find("Root.Commands." .. capName .. ".Caption")
					local old = c.Text
					c.Text = name
					Hud.PlaceFaceName(A, A.Button.Size.X.Offset, false)
					local r = rectOf(c)
					c.Text = old
					Hud.PlaceFaceName(A, A.Button.Size.X.Offset, false)
					return r
				end
				-- (Pitch 2 item 1b) the special's name shows on MOVE (the Element key) once the meter is full: the same fit there
				d.sim.teams[1].fighter.meter = 100
				d:run(0.4)
				local cap = H.find("Root.Commands.ElementButton.Caption")
				local glyph = H.find("Root.Commands.ElementButton.Face.Glyph")
				if T.check(cap ~= nil and shownIn(cap) and cap.Text == "WISH UPON THE STARS", tag .. "a full meter: MOVE shows the special's name", cap and cap.Text or "nil") then
					local readScale = H.find("Root.ReadScale").Scale
					T.check(cap.TextWrapped == true and cap.TextScaled == false and cap.TextSize * readScale >= 14 - 0.01, tag .. "...wrapped, not scaled, at 14 px or more",
						fmt("%s %.1f px", tostring(cap.TextScaled), cap.TextSize * readScale))
					for _, name in ipairs({ "WISH UPON THE STARS", "MARSHMALLOW POUNCE", "MARSHMALLOW STAMPEDE" }) do
						local r = tryName("Element", "ElementButton", name)
						local ok, lines, widest = H.fits(name, r.x1 - r.x0, r.y1 - r.y0, 14)
						T.check(ok, tag .. "\"" .. name .. "\" fits MOVE's name tag in 2 lines at 14 px", fmt("%d lines, widest %.0f, box %.0fx%.0f", lines, widest, r.x1 - r.x0, r.y1 - r.y0))
					end
					local r = rectOf(cap)
					local br = rects.Element
					T.check(br ~= nil and r.y0 >= br.y0 and r.y1 <= br.y1 + 0.5, tag .. "...on the face's bottom edge", rstr(r))
					-- (Pitch 2 item 1b: MOVE is smaller than the old SPECIAL key, so this reads the star as drawn, the PixelIcon at the
					-- key's icon size (Hud.PlaceFaceName: 27 px, 18 where the room is short), where it read the host label's TextSize
					-- (30), which draws nothing: the drawn star fits the room above the name)
					local gr = glyph and rectOf(glyph)
					local icon = glyph and glyph:FindFirstChild("Icon")
					local ir = icon and rectOf(icon)
					T.check(glyph ~= nil and glyph.Size.Y.Scale <= 0.56 and gr.y1 <= r.y0 + 1 and ir ~= nil and ir.y1 - ir.y0 <= gr.y1 - gr.y0 + 0.5 and ir.y0 >= gr.y0 - 0.5 and ir.y1 <= r.y0 + 1,
						tag .. "...the star shrinks to the room above it", fmt("%s glyph %s icon %s", glyph and tostring(glyph.Size) or "nil", gr and rstr(gr) or "-", ir and rstr(ir) or "-"))
				end
				d.sim.teams[1].fighter.meter = 0
				d:run(0.4)
				local ecap = H.find("Root.Commands.ElementButton.Caption")
				if T.check(ecap ~= nil and shownIn(ecap), tag .. "the Element face shows the name") then
					for _, name in ipairs({ "THUNDER LANCE", "BRAMBLE LASH", "WORLDROOT", "MAELSTROM" }) do
						local r = tryName("Element", "ElementButton", name)
						local ok, lines, widest = H.fits(name, r.x1 - r.x0, r.y1 - r.y0, 14)
						T.check(ok, tag .. "\"" .. name .. "\" fits the Element name tag in 2 lines at 14 px", fmt("%d lines, widest %.0f, box %.0fx%.0f", lines, widest, r.x1 - r.x0, r.y1 - r.y0))
					end
				end
				-- (Pitch 2 item 1b: the TARGET key's ONE ENEMY flash is a keyboard / gamepad matter now, client_evo_target; a touch
				-- screen has no TARGET key) the three keys are named: DASH's name sits on its face too, at 14 px or more
				local dcap = H.find("Root.Commands.DashButton.Caption")
				if T.check(dcap ~= nil and shownIn(dcap) and dcap.Text == "DASH", tag .. "DASH carries its name on touch (the three keys are named)", dcap and dcap.Text or "nil") then
					local r = rectOf(dcap)
					T.check((H.fits("DASH", r.x1 - r.x0, r.y1 - r.y0, 14)), tag .. "...and it fits at 14 px", rstr(r))
				end
				H.cleanup(BC, d)
			end
		end
		Mock.SetViewport(390, 844)
		H.step(3, 0.1)
		LocalPlayer:SetAttribute(Config.Attr.Cash, oldCash)
		LocalPlayer:SetAttribute(Config.Attr.Gems, oldGems)
		T.check(#Mock.Errors == err0, "evo phone: no script errors", tostring(Mock.Errors[#Mock.Errors]))
		KC.flushErrors("client_evo_buttons_mobile")
	end)

	------------------------------------------------------------------------------------------------
	-- keys_three_buttons (kit-b Pitch 2 item 1b, option C "Three buttons", the owner's pick 2026-11-20; the approved mock
	-- .superpowers/slop-audit/round3/build/PITCH2/A_battle_hud/repitch/01b_optC*.png, its positions in repitch_01b.py layout_C):
	-- on touch the right thumb has exactly three named buttons, MOVE (the element on a tap; a full meter turns it gold with a
	-- HOLD tag and a hold fires the special), DASH and RUN, each >= 44 px, clear of Roblox's jump button and stick, none moves
	-- or hides from one fight state to the next; TARGET is automatic (no button; a tap on an enemy locks it, a LOCKED marker
	-- over it); CHEER and BACK sit beside the helper portraits (a wide phone) / in a row under them (a tall one); the middle
	-- of a wide screen stays clear
	------------------------------------------------------------------------------------------------
	S.keys_three_buttons = guarded("keys_three_buttons", function()
		local BC = H.moduleAt("client", "Controllers/BattleController")
		local Theme = H.moduleAt("shared", "Theme")
		if not T.check(BC ~= nil and Theme ~= nil and BC._Hud ~= nil and BC._St ~= nil, "keys: BattleController loads") then
			return
		end
		local err0 = #Mock.Errors
		local GuiService = game:GetService("GuiService")
		local function inset()
			local ok, a = pcall(function()
				return GuiService:GetGuiInset()
			end)
			return (ok and typeof(a) == "Vector2") and a.Y or (Mock.TopInset or 0)
		end
		-- Roblox's own jump button and stick (gui-area px, Hud.TouchRects' numbers, as client_evo_buttons_mobile)
		local function roblox(size)
			local areaY = size[2] - (Mock.TopInset or 0)
			local small = min(size[1], size[2]) <= 500
			local j = small and 70 or 120
			local jb = small and 20 or j * 0.75
			local stickW = small and 110 or 190
			local stickH = small and ((size[2] > size[1]) and 150 or 96) or 210
			return { x0 = size[1] - j * 1.5 - 10, y0 = areaY - jb - j, x1 = size[1] - j * 0.5 - 10, y1 = areaY - jb },
				{ x0 = 0, y0 = areaY - stickH, x1 = stickW, y1 = areaY }
		end
		local function apart(a, b) -- the clear px between two boxes (negative: they overlap)
			return max(b.x0 - a.x1, a.x0 - b.x1, b.y0 - a.y1, a.y0 - b.y1)
		end
		-- (look review r0) Roblox's jump and stick rings as render_gui draws them (gui-area px: centre, radius) and the clear px
		-- between a box and a ring: the pitch keeps every control 8 px off them (repitch_01b.py check)
		local function rings(size)
			local areaY = size[2] - (Mock.TopInset or 0)
			local small = min(size[1], size[2]) <= 500
			local j = small and 70 or 120
			local jb = small and 20 or j * 0.75
			return { x = size[1] - j - 10, y = areaY - jb - j / 2, r = j / 2 }, { x = j - 10, y = areaY - 20 - j / 2, r = j / 2 }
		end
		local function offRing(r, ring)
			local dx = max(r.x0 - ring.x, 0, ring.x - r.x1)
			local dy = max(r.y0 - ring.y, 0, ring.y - r.y1)
			return math.sqrt(dx * dx + dy * dy) - ring.r
		end
		local function inside(a, b) -- box a within box b (half a px of rounding)
			return a.x0 >= b.x0 - 0.5 and a.x1 <= b.x1 + 0.5 and a.y0 >= b.y0 - 0.5 and a.y1 <= b.y1 + 0.5
		end
		-- (look review r1, render_gui battle:raid:full at 360 x 640: the team row stood in the right thumb's cluster, BACK
		-- 18 px above DASH, where a thumb reaching up for DASH pulls the team out mid-fight) the team orders keep this many
		-- screen px off every right-thumb key
		local TEAM_OFF_KEYS = 40
		local function offKeys(tag, word, r, keys)
			for n, k in pairs(keys) do
				T.check(apart(r, k) >= TEAM_OFF_KEYS - 0.5, tag .. word .. " keeps 40 px clear of " .. n .. " (a thumb reaching for a key never hits a team order)",
					fmt("%s vs %s: %.1f px", rstr(r), rstr(k), apart(r, k)))
			end
		end
		-- (look review r1: at 360 x 640 the second helper's Swap lay on Roblox's stick ring; on a short landscape phone the
		-- helper column's second Swap reached it too) each helper's cell, its Swap and the Swap's clear 44 px hit pad keep off
		-- Roblox's stick ring: the stick takes every touch there, and a pad over it would take the stick's
		local function helpersOffStick(tag, size)
			local _, sr = rings(size)
			for i = 1, 2 do
				local cell = H.find("Root.Team.Helpers.Helper" .. i)
				if cell and shownIn(cell) then
					for _, part in ipairs({ { "cell", cell }, { "Swap", cell:FindFirstChild("Swap") }, { "Swap's hit pad", cell:FindFirstChild("SwapHit") } }) do
						local o = part[2]
						if o and shownIn(o) and o.AbsoluteSize.X > 1 then
							local r = rectOf(o)
							T.check(offRing(r, sr) >= 0, tag .. "helper " .. i .. "'s " .. part[1] .. " keeps off Roblox's stick ring", fmt("%s ring %.1f", rstr(r), offRing(r, sr)))
						end
					end
				end
			end
		end
		-- (look review r1, 667 x 375: "STONE S...", "TIDE ME..."; 360 x 640: "STON / E...") each helper's buff name is whole:
		-- on one line where its tag holds it, else wrapped on lines its tag holds, no word broken. The mock has no font
		-- metrics: FredokaOne's own advances (tools/fixtures/fonts, em) x 1.055, the heavier face render_gui draws ("STONE
		-- SKIN" 89.3 px at 14.4 px there); anything else 0.75 em. render_gui is the pixel judge
		local FREDOKA = { A = 0.765, B = 0.646, C = 0.679, D = 0.704, E = 0.638, F = 0.637, G = 0.714, H = 0.699, I = 0.257, J = 0.549,
			K = 0.639, L = 0.587, M = 0.87, N = 0.72, O = 0.775, P = 0.632, Q = 0.83, R = 0.631, S = 0.583, T = 0.731, U = 0.726,
			V = 0.783, W = 0.999, X = 0.741, Y = 0.686, Z = 0.643, ["0"] = 0.608, ["1"] = 0.407, ["2"] = 0.609, ["3"] = 0.608,
			["4"] = 0.592, ["5"] = 0.53, ["6"] = 0.56, ["7"] = 0.561, ["8"] = 0.582, ["9"] = 0.56, [" "] = 0.253 }
		local function emOf(s)
			local e = 0
			for ch in tostring(s):gmatch(".") do
				e = e + (FREDOKA[ch] or 0.75) * 1.055
			end
			return e
		end
		local function namesWhole(tag)
			local scale = H.find("Root.ReadScale")
			local sc = scale and scale.Scale or 1
			for i = 1, 2 do
				local lbl = H.find("Root.Team.Helpers.Helper" .. i .. ".Buff")
				if lbl and shownIn(lbl) and lbl.Text ~= "" then
					local pad = lbl:FindFirstChildOfClass("UIPadding")
					local px = lbl.TextSize * sc
					local w = lbl.AbsoluteSize.X - (pad and (pad.PaddingLeft.Offset + pad.PaddingRight.Offset) * sc or 0)
					local ok = emOf(lbl.Text) * px <= w + 0.5
					local lines = 1
					if not ok and lbl.TextWrapped then
						ok, lines = true, 0
						local cur = -1
						for word in lbl.Text:gmatch("%S+") do
							local ww = emOf(word) * px
							ok = ok and ww <= w + 0.5
							local sp = emOf(" ") * px
							if cur < 0 or cur + sp + ww > w + 0.5 then
								lines, cur = lines + 1, ww
							else
								cur = cur + sp + ww
							end
						end
						-- (keys look r4) the lines stand TextSize x LineHeight apart: Roblox's line advance (LineHeight, default 1,
						-- a multiple of the em) and render_gui's (step = size x lineHeight), the pixel judge above. The 1.2 em
						-- assumed here failed whole two-line names the render draws inside their tags (360 x 640 "TIDE / MEND":
						-- 28.8 px of lines in a 32 px tag; 667 x 375 the same): the check keeps its 1 px slack, not the 0.2 em
						local lh = tonumber(lbl.LineHeight) or 1
						ok = ok and lines * px * max(1, lh) <= lbl.AbsoluteSize.Y + 1
					end
					T.check(ok, tag .. "helper " .. i .. "'s buff name is whole ('" .. lbl.Text .. "')",
						fmt("%.1f px of text in %.1f x %.1f, %s, %d line(s)", emOf(lbl.Text) * px, w, lbl.AbsoluteSize.Y, lbl.TextWrapped and "wrapped" or "one line", lines))
				end
			end
		end
		-- (look review r2, render_gui at 640 x 360 in every battle mode: the top card and the enemy list lay on DASH and RUN, RUN
		-- drawn under them and hidden, DASH 58 px under the raid's boss card; in the full raid the list also ran 29 px into
		-- Roblox's jump ring) the keys never move or hide, so the HUD's cards make room: the top card, each enemy row and the
		-- list's "+n more" tag, the fighter card and the helpers keep 4 px clear of MOVE, DASH, RUN and MOVE's HOLD tag, and
		-- the enemy list keeps the pitch's 8 px off Roblox's jump and stick rings
		local function hudCards()
			local out = {}
			for _, path in ipairs({ "TopCard", "Team.Fighter", "Team.Helpers" }) do
				local o = H.find("Root." .. path)
				if o and shownIn(o) and o.AbsoluteSize.X > 1 and o.AbsoluteSize.Y > 1 then
					out[path] = rectOf(o)
				end
			end
			local en = H.find("Root.Enemies")
			if en and shownIn(en) then
				for _, row in ipairs(en:GetChildren()) do
					if row:IsA("GuiObject") and shownIn(row) and row.AbsoluteSize.X > 1 and row.AbsoluteSize.Y > 1 then
						out["Enemies." .. row.Name] = rectOf(row)
					end
				end
			end
			return out
		end
		local function cardsOffKeys(tag, keys, size, state)
			local all = {}
			for n, r in pairs(keys) do
				all[n] = r
			end
			local hold = H.find("Root.Commands.ElementButton.HoldTag")
			if hold and shownIn(hold) then
				all["MOVE's HOLD tag"] = rectOf(hold)
			end
			for _, kind in ipairs({ "Element", "Dash" }) do -- (a long name's tag past its face, Hud.PlaceBlockFace's fallback)
				local plate = H.find("Root.Commands." .. kind .. "Button.NamePlate")
				if plate and shownIn(plate) and plate.AbsoluteSize.X > 1 then
					all[kind .. "'s name tag"] = rectOf(plate)
				end
			end
			local cards = hudCards()
			local names = {}
			for cn in pairs(cards) do
				names[#names + 1] = cn
			end
			table.sort(names)
			local jr, sr = rings(size)
			for _, cn in ipairs(names) do
				local cr, bad = cards[cn], {}
				for kn, kr in pairs(all) do
					if apart(cr, kr) < 4 then
						bad[#bad + 1] = fmt("%s %s: %.1f px", kn, rstr(kr), apart(cr, kr))
					end
				end
				table.sort(bad)
				T.check(#bad == 0, tag .. "the " .. cn .. " keeps clear of MOVE, DASH, RUN and the HOLD tag (" .. state .. ")", rstr(cr) .. " vs " .. table.concat(bad, "; "))
				if cn:sub(1, 8) == "Enemies." then
					T.check(offRing(cr, jr) >= 8 and offRing(cr, sr) >= 8, tag .. "the " .. cn .. " keeps the pitch's 8 px off Roblox's jump and stick rings (" .. state .. ")",
						fmt("%s jump ring %.1f stick ring %.1f", rstr(cr), offRing(cr, jr), offRing(cr, sr)))
				end
			end
		end
		-- every shown button of the right thumb: the battle's Commands and MovementController's MobileControls
		local function thumb()
			local out, names = {}, {}
			local cmd = H.find("Root.Commands")
			for _, b in ipairs(cmd and cmd:GetChildren() or {}) do
				if b:IsA("GuiButton") and shownIn(b) then
					out["Commands." .. b.Name] = rectOf(b)
					names[#names + 1] = "Commands." .. b.Name
				end
			end
			local pg = LocalPlayer:FindFirstChild("PlayerGui")
			local mc = pg and pg:FindFirstChild("MobileControls")
			for _, name in ipairs({ "RunButton", "DashButton" }) do
				local b = mc and mc:FindFirstChild(name, true)
				if b and b:IsA("GuiButton") and shownIn(b) and b.AbsoluteSize.X > 4 then
					out["MobileControls." .. name] = rectOf(b)
					names[#names + 1] = "MobileControls." .. name
				end
			end
			table.sort(names)
			return out, names
		end
		local function lockMark()
			for _, o in ipairs(workspace:GetDescendants()) do
				if o:IsA("BillboardGui") and o.Name == "LockMark" then
					return o
				end
			end
			return nil
		end
		local function press(b, seconds)
			local a, s = b.AbsolutePosition, b.AbsoluteSize
			local inp = Mock.NewInput("Unknown", "Touch", "Begin", { Position = Vector3.new(a.X + s.X / 2, a.Y + s.Y / 2, 0) })
			Mock.FireSignal(b, "InputBegan", inp, false)
			Mock.FireSignal(UserInputService, "InputBegan", inp, true)
			H.step(max(1, floor(seconds * 30 + 0.5)), 1 / 30)
			inp.UserInputState = Enum.UserInputState.End
			Mock.FireSignal(b, "InputEnded", inp, false)
			Mock.FireSignal(UserInputService, "InputEnded", inp, true)
			H.step(2, 1 / 30)
		end
		local WANT = { "Commands.DashButton", "Commands.ElementButton", "MobileControls.RunButton" }
		local PETS = { { PetId = "ember_phoenix" }, { PetId = "starlight_unicorn", Evo = 2 }, { PetId = "puddle_frog" } }
		-- (look review r1: 640 x 360's team orders, helpers and names are checked in the full raid below; look review r2: its
		-- raid too, where the boss card lay on DASH and hid RUN)
		for _, size in ipairs({ { 844, 390 }, { 740, 360 }, { 667, 375 }, { 640, 360 }, { 390, 844 }, { 360, 640 }, { 1024, 768 } }) do
			Mock.SetViewport(size[1], size[2])
			H.step(15, 1 / 30)
			local tag = "keys " .. size[1] .. "x" .. size[2] .. ": "
			local wide = size[1] > size[2]
			local d = H.fight({ Mode = "Raid", Pets = PETS })
			if T.check(d ~= nil and BC.GetBattle() ~= nil, tag .. "(setup) a boss raid with two helpers") then
				local jump, stick = roblox(size)
				local first, names = thumb()
				T.check(table.concat(names, ",") == table.concat(WANT, ","), tag .. "exactly three right-thumb buttons: MOVE, DASH, RUN (no SPECIAL, no TARGET, no second DASH)", table.concat(names, ","))
				for _, n in ipairs(WANT) do
					local r = first[n]
					if r then
						T.check(r.x1 - r.x0 >= 44 - 0.01 and r.y1 - r.y0 >= 44 - 0.01, tag .. n .. " is at least 44 px on the screen", fmt("%.1fx%.1f", r.x1 - r.x0, r.y1 - r.y0))
						T.check(apart(r, jump) >= 4 and apart(r, stick) >= 4, tag .. n .. " keeps clear of Roblox's jump button and stick", fmt("%s jump %.0f stick %.0f", rstr(r), apart(r, jump), apart(r, stick)))
						local jr, sr = rings(size)
						T.check(offRing(r, jr) >= 8 and offRing(r, sr) >= 8, tag .. n .. " keeps the pitch's 8 px off Roblox's jump and stick rings", fmt("%s jump ring %.1f stick ring %.1f", rstr(r), offRing(r, jr), offRing(r, sr)))
					end
				end
				-- (look review r0: DASH and MOVE kept the old touch style, a separate name plate under the face and wider than it, so
				-- only RUN carried its name inside; a cooling MOVE showed only its seconds) the approved mock draws each key as ONE
				-- block: its glyph over its name, both inside the face, no plate; cooling, the glyph stays beside the seconds
				local function oneBlock(kind, state)
					local btn = H.find("Root.Commands." .. kind .. "Button")
					local cap = btn and btn:FindFirstChild("Caption")
					local plate = btn and btn:FindFirstChild("NamePlate")
					local glyph = btn and btn:FindFirstChild("Glyph", true)
					local count = btn and btn:FindFirstChild("Count", true)
					if not T.check(btn ~= nil and cap ~= nil and glyph ~= nil and count ~= nil, tag .. kind .. " has its face parts (" .. state .. ")") then
						return
					end
					local br, cr, gr = rectOf(btn), rectOf(cap), rectOf(glyph)
					local scale = H.find("Root.ReadScale")
					local px = cap.TextSize * (scale and scale.Scale or 1)
					-- (look review r2: 640 x 360 joined this loop; the centre 40% caps its MOVE at 60 px, where the PHOENIX of a full
					-- meter's PHOENIX FLARE is wider than the face at the 14 px floor) Hud.PlaceBlockFace's documented fallback for a
					-- word wider than the face (its 0.62 em estimate, the face less 2 px a side): kit-b's tag over the face's lower
					-- part, on the screen, the floor holding. Every name that fits keeps the one-block check below
					local floorDesign = math.ceil(14 / ((scale and scale.Scale) or 1) - 1e-6)
					local tooWide = false
					for word in cap.Text:gmatch("%S+") do
						tooWide = tooWide or #word * floorDesign * 0.62 > btn.Size.X.Offset - 4
					end
					if tooWide then
						local pr = plate and shownIn(plate) and rectOf(plate)
						T.check(shownIn(cap) and pr and inside(cr, pr) and pr.x0 >= 0 and pr.x1 <= size[1] and pr.y0 < br.y1 and pr.y1 > br.y0 and px >= 14 - 0.01,
							tag .. kind .. "'s name (a word wider than its face at the floor) keeps kit-b's tag over the face, on the screen (" .. state .. ")",
							fmt("'%s' %s on %s, face %s, %.1f px", cap.Text, rstr(cr), pr and rstr(pr) or "no plate", rstr(br), px))
					else
						T.check(shownIn(cap) and inside(cr, br) and not (plate and shownIn(plate)) and px >= 14 - 0.01,
							tag .. kind .. "'s name lies inside its face, no plate (" .. state .. ")", fmt("'%s' %s in %s, plate %s, %.1f px", cap.Text, rstr(cr), rstr(br), tostring(plate and shownIn(plate)), px))
					end
					T.check(shownIn(glyph) and glyph.TextTransparency < 1 and inside(gr, br) and gr.y1 <= cr.y0 + 1,
						tag .. kind .. "'s glyph shows above its name, inside the face (" .. state .. ")", fmt("glyph %s (t %.1f) name %s", rstr(gr), glyph.TextTransparency, rstr(cr)))
					if shownIn(count) and count.Text ~= "" then
						local kr = rectOf(count)
						T.check(inside(kr, br) and not overlaps(kr, gr) and kr.y1 <= cr.y0 + 1,
							tag .. kind .. "'s seconds stand beside its glyph, inside the face (" .. state .. ")", fmt("'%s' %s glyph %s", count.Text, rstr(kr), rstr(gr)))
					end
				end
				oneBlock("Element", "at rest")
				oneBlock("Dash", "at rest")
				-- (look review r0, 667 x 375: DASH's face lay 8 px over the top card's bottom-right corner) the cards keep off the keys
				local topCard = H.find("Root.TopCard")
				if topCard and shownIn(topCard) then
					local tr = rectOf(topCard)
					for _, n in ipairs(WANT) do
						if first[n] then
							T.check(apart(first[n], tr) >= 4, tag .. n .. " keeps clear of the top card", rstr(first[n]) .. " vs " .. rstr(tr))
						end
					end
				end
				cardsOffKeys(tag, first, size, "at rest")
				-- MOVE: the element on a tap
				local Hud = BC._Hud
				local move = H.find("Root.Commands.ElementButton")
				local caps = Hud.CaptionTexts(BC._St.battle)
				local holdTag = H.find("Root.Commands.ElementButton.HoldTag")
				T.check(move ~= nil and H.text("Element") == caps.Element and not (holdTag and shownIn(holdTag)), tag .. "MOVE says the element's attack, no HOLD tag while the meter fills", H.text("Element"))
				-- CHEER and BACK with the team: beside the helper portraits (wide) / a row under them (tall)
				local helpers = H.find("Root.Team.Helpers")
				local cheer, back = H.find("Root.Cheer"), H.find("Root.Retreat")
				local function team()
					if not T.check(helpers ~= nil and shownIn(helpers) and cheer ~= nil and shownIn(cheer) and back ~= nil and shownIn(back), tag .. "the helper portraits, CHEER and BACK are shown") then
						return
					end
					local hr, cr, br = rectOf(helpers), rectOf(cheer), rectOf(back)
					T.check(cheer.Text == "CHEER" and (back.Text == "BACK" or back.Text == "FIGHT"), tag .. "the team orders read CHEER and BACK", cheer.Text .. " / " .. back.Text)
					for _, p in ipairs({ { "CHEER", cr }, { "BACK", br } }) do
						T.check(p[2].x1 - p[2].x0 >= 44 - 0.01 and p[2].y1 - p[2].y0 >= 44 - 0.01, tag .. p[1] .. " is at least 44 px on the screen", rstr(p[2]))
						T.check(apart(p[2], jump) >= 4 and apart(p[2], stick) >= 4, tag .. p[1] .. " keeps clear of Roblox's jump button and stick", rstr(p[2]))
						local jr, sr = rings(size)
						T.check(offRing(p[2], jr) >= 8 and offRing(p[2], sr) >= 8, tag .. p[1] .. " keeps the pitch's 8 px off Roblox's jump and stick rings", fmt("%s jump ring %.1f stick ring %.1f", rstr(p[2]), offRing(p[2], jr), offRing(p[2], sr)))
						-- (look review r0: a tall phone's row narrowed them to 45-50 px, where CHEER at the 14 px floor ran onto its edges,
						-- render_gui's overflow) the mock's 52 px block, which holds the word
						T.check(p[2].x1 - p[2].x0 >= 52 - 0.6, tag .. p[1] .. " is the mock's 52 px block, wide enough for its word", rstr(p[2]))
						for n, r in pairs(first) do
							T.check(apart(p[2], r) >= 4, tag .. p[1] .. " keeps clear of " .. n, rstr(p[2]) .. " vs " .. rstr(r))
						end
						offKeys(tag, p[1], p[2], first)
					end
					helpersOffStick(tag, size)
					if wide then
						local cy, by = (cr.y0 + cr.y1) / 2, (br.y0 + br.y1) / 2
						T.check(cr.x0 >= hr.x1 - 0.5 and cr.x0 - hr.x1 <= 16 and br.x0 >= hr.x1 - 0.5 and br.x0 - hr.x1 <= 16
							and cy >= hr.y0 and cy <= hr.y1 and by >= hr.y0 and by <= hr.y1 and br.y0 >= cr.y1,
							tag .. "CHEER and BACK stand beside the helper portraits, one per helper", rstr(cr) .. " / " .. rstr(br) .. " | helpers " .. rstr(hr))
					else
						T.check(cr.y0 >= hr.y1 - 0.5 and cr.y0 - hr.y1 <= 20 and abs(br.y0 - cr.y0) < 1 and br.x0 >= cr.x1 and cr.x0 >= hr.x0 - 1,
							tag .. "CHEER and BACK are a row under the helper portraits", rstr(cr) .. " / " .. rstr(br) .. " | helpers " .. rstr(hr))
					end
					return cr, br
				end
				local cr0, br0 = team()
				if not (size[1] == 640 and size[2] == 360) then
					namesWhole(tag) -- (640 x 360: one line of name each, cut where longer: the full raid below says why)
				end
				-- the middle of a wide screen stays clear (the HUD's centre 40% of the width, client_p5battle_landscape's box)
				if wide then
					local box = { x0 = size[1] * 0.3, x1 = size[1] * 0.7, y0 = size[2] * 0.35, y1 = size[2] * 0.75 }
					for n, r in pairs(first) do
						T.check(not overlaps(r, box), tag .. n .. " stays out of the middle of the screen", rstr(r))
					end
					for _, p in ipairs({ { "CHEER", cr0 }, { "BACK", br0 } }) do
						if p[2] then
							T.check(not overlaps(p[2], box), tag .. p[1] .. " stays out of the middle of the screen", rstr(p[2]))
						end
					end
				end
				-- none moves or hides: the same three buttons in the same boxes, and CHEER / BACK in theirs, in every state
				local function steady(state)
					local now = thumb()
					local bad = {}
					for _, n in ipairs(WANT) do
						local a, b = first[n], now[n]
						if not (a and b) or abs(a.x0 - b.x0) > 0.5 or abs(a.y0 - b.y0) > 0.5 or abs(a.x1 - b.x1) > 0.5 or abs(a.y1 - b.y1) > 0.5 then
							bad[#bad + 1] = n .. " " .. (a and rstr(a) or "-") .. " -> " .. (b and rstr(b) or "hidden")
						end
					end
					for n in pairs(now) do
						if not first[n] then
							bad[#bad + 1] = n .. " appeared"
						end
					end
					for _, p in ipairs({ { "CHEER", cheer, cr0 }, { "BACK", back, br0 } }) do
						local r = p[2] and shownIn(p[2]) and rectOf(p[2])
						if p[3] and not (r and abs(r.x0 - p[3].x0) <= 0.5 and abs(r.y0 - p[3].y0) <= 0.5) then
							bad[#bad + 1] = p[1] .. " " .. rstr(p[3]) .. " -> " .. (r and rstr(r) or "hidden")
						end
					end
					T.check(#bad == 0, tag .. "nothing moves or hides: " .. state, table.concat(bad, "; "))
				end
				-- TARGET is automatic: no lock, no marker; a tap on an enemy in the world locks it, a LOCKED marker over it
				T.check(BC.GetBattle().Lock == nil and not (lockMark() and lockMark().Enabled), tag .. "TARGET starts automatic: no lock, no LOCKED marker")
				local idx = #Mock.RemoteLog
				local vp = Mock.Viewport
				local centre = Vector3.new(vp.X / 2, vp.Y / 2 - inset(), 0) -- (the mock camera projects every unit to the screen's centre)
				local touch = Mock.NewInput("Unknown", "Touch", "Begin", { Position = centre })
				Mock.FireSignal(UserInputService, "InputBegan", touch, false)
				H.step(3, 1 / 30)
				touch.UserInputState = Enum.UserInputState.End
				Mock.FireSignal(UserInputService, "InputEnded", touch, false)
				H.step(3, 1 / 30)
				local sent = H.commands(idx)
				T.check(#sent == 1 and sent[1].action == "Target" and d.sim.units[sent[1].arg] ~= nil, tag .. "a tap on an enemy sends ONE Target(its id)", #sent .. " sent")
				d:run(0.4)
				local mark = lockMark()
				local word = mark and mark:FindFirstChild("Locked", true)
				local scale = H.find("Root.ReadScale")
				T.check(BC.GetBattle().Lock ~= nil and mark ~= nil and mark.Enabled and mark.Adornee ~= nil and word ~= nil and word.Text == "LOCKED" and word.TextSize >= 14,
					tag .. "...the echo locks it and a LOCKED marker stands over it", fmt("lock %s mark %s", tostring(BC.GetBattle().Lock), tostring(mark and mark.Enabled)))
				steady("an enemy locked")
				-- the HOLD special: a full meter turns MOVE gold with a HOLD tag; a tap is still the element, a hold fires the special
				d.sim.teams[1].fighter.meter = 100
				d:run(0.4)
				d.noForward = true
				local face = H.find("Root.Commands.ElementButton.Face")
				T.check(holdTag ~= nil and shownIn(holdTag) and holdTag.Text == "HOLD" and face ~= nil and face.BackgroundColor3 == Theme.Sign.Gold and H.text("Element") == caps.Special,
					tag .. "a full meter: MOVE turns gold, says the special's name, a HOLD tag on top", fmt("%s / %s", H.text("Element"), tostring(holdTag and shownIn(holdTag))))
				if holdTag and shownIn(holdTag) then
					local hr, mr = rectOf(holdTag), rectOf(move)
					T.check(holdTag.TextSize * (scale and scale.Scale or 1) >= 14 - 0.01 and hr.y0 < mr.y0 and hr.y1 > mr.y0 and hr.x0 >= mr.x0 - 1 and hr.x1 <= mr.x1 + 1,
						tag .. "...the HOLD tag sits on MOVE's top edge at 14 px or more", rstr(hr) .. " on " .. rstr(mr))
					-- (look review r0: the tag hung 18 px over MOVE, 8 px under DASH's plate, and read as DASH's) the mock pins it
					-- across the edge, about half in, so it reads as MOVE's top: well clear of DASH
					local dr = rectOf(H.find("Root.Commands.DashButton"))
					T.check(abs((hr.y0 + hr.y1) / 2 - mr.y0) <= 3 and apart(hr, dr) >= 12,
						tag .. "...pinned across MOVE's top edge, 12 px or more from DASH", fmt("%s on %s, DASH %s %.1f px", rstr(hr), rstr(mr), rstr(dr), apart(hr, dr)))
				end
				oneBlock("Element", "the meter full")
				oneBlock("Dash", "the meter full")
				steady("the meter full")
				cardsOffKeys(tag, first, size, "the meter full")
				idx = #Mock.RemoteLog
				press(move, 0.15)
				T.check(H.count(idx, "Element") == 1 and H.count(idx, "Special") == 0, tag .. "...a tap on the gold MOVE is the element (ONE Element, no Special)", fmt("%d Element, %d Special", H.count(idx, "Element"), H.count(idx, "Special")))
				H.step(12, 1 / 30)
				idx = #Mock.RemoteLog
				local a, s = move.AbsolutePosition, move.AbsoluteSize
				local inp = Mock.NewInput("Unknown", "Touch", "Begin", { Position = Vector3.new(a.X + s.X / 2, a.Y + s.Y / 2, 0) })
				Mock.FireSignal(move, "InputBegan", inp, false)
				H.step(18, 1 / 30)
				T.check(H.count(idx, "Special") == 1 and H.count(idx, "Element") == 0, tag .. "...a hold of MOVE fires the special while it is held (ONE Special)", fmt("%d Special, %d Element", H.count(idx, "Special"), H.count(idx, "Element")))
				inp.UserInputState = Enum.UserInputState.End
				Mock.FireSignal(move, "InputEnded", inp, false)
				Mock.FireSignal(UserInputService, "InputEnded", inp, true)
				H.step(3, 1 / 30)
				T.check(H.count(idx, "Special") == 1 and H.count(idx, "Element") == 0, tag .. "...and nothing more on the release", fmt("%d Special, %d Element", H.count(idx, "Special"), H.count(idx, "Element")))
				steady("the special held")
				d.noForward = false
				d.sim.teams[1].fighter.meter = 0
				d:run(1)
				-- a meter that is not full: a press is the element at once (the unforwarded tap's prediction timed out: no cooldown)
				for _ = 1, 90 do
					if BC.GetBattle().Cooldowns.Element <= 0.05 then
						break
					end
					d:run(0.1)
				end
				idx = #Mock.RemoteLog
				local inp2 = Mock.NewInput("Unknown", "Touch", "Begin", { Position = Vector3.new(a.X + s.X / 2, a.Y + s.Y / 2, 0) })
				Mock.FireSignal(move, "InputBegan", inp2, false)
				H.step(1, 1 / 30)
				T.check(H.count(idx, "Element") == 1 and H.count(idx, "Special") == 0, tag .. "a meter that is not full: a press of MOVE is the element at once", H.count(idx, "Element") .. " sent")
				inp2.UserInputState = Enum.UserInputState.End
				Mock.FireSignal(move, "InputEnded", inp2, false)
				Mock.FireSignal(UserInputService, "InputEnded", inp2, true)
				d:run(0.3)
				-- (the press may find no enemy in reach: the client's own cooldown clock, as a confirmed element sets it)
				local Bc = BC._St.battle
				if Bc and Bc.cd and (Bc.cd.Element or 0) - os.clock() < 1 then
					Bc.cd.Element = os.clock() + 6.5
					H.step(4, 1 / 30)
				end
				local cnt = H.find("Root.Commands.ElementButton.Face.Count")
				T.check(cnt ~= nil and shownIn(cnt) and cnt.Text ~= "", tag .. "(setup) MOVE counts its cooldown down", cnt and cnt.Text or "nil")
				oneBlock("Element", "the element cooling down")
				steady("the element cooling down")
				local dash = H.find("Root.Commands.DashButton")
				if dash then
					press(dash, 0.1)
					d:run(0.3)
				end
				oneBlock("Dash", "the dash cooling down")
				steady("the dash cooling down")
				Mock.Click(back)
				d:run(0.5)
				T.check(BC.GetBattle().Retreated == true, tag .. "(setup) BACK pulls the team back")
				steady("the team pulled back")
				Mock.Click(back)
				d:run(0.5)
				H.cleanup(BC, d)
			end
		end
		-- (look review r0, render_gui battle:raid:full at 360 x 640: the top card stacked into its tall column under the fighter
		-- card, the helper portraits under it reached Roblox's stick, and the CHEER / BACK row under them landed on the stick, 2 px
		-- from the screen's foot) the full raid: its tier, three players, the boss enraged with its minion waves. The team orders
		-- stay with the team (beside the portraits, or a row under them) and off the stick, the keys and the foot
		-- (look review r1) the same full raid at every phone size the review names: 360 x 640 in the render's no-strip layout,
		-- 640 x 360, 667 x 375, 390 x 844 and 844 x 390 as they lay out
		-- render_gui's teams (dump_gui battleTeam / BCDUMP.team): the catalog's combat pets with a special of their own kind,
		-- `skip` of them passed over, levels from `level` up by 2
		local Catalog = H.moduleAt("shared", "PetCatalog")
		local function renderTeam(skip, level)
			local out, kinds = {}, {}
			for _, def in ipairs(Catalog and Catalog.Pets or {}) do
				local sp = type(def.Special) == "table" and def.Special.Kind or nil
				if sp and def.Role == "Combat" and not kinds[sp] and def.Rarity ~= "Secret" and not def.EventOnly then
					if skip > 0 then
						skip = skip - 1
					else
						kinds[sp] = true
						out[#out + 1] = { Key = def.Id, PetId = def.Id, Level = level + (#out + 1) * 2, Tier = "Normal", Slot = #out + 1 }
						if #out >= 3 then
							break
						end
					end
				end
			end
			return out
		end
		-- (render_gui's HUD: the tokens strip alone; an earlier list of the whole suite may have left Cash / Gems set)
		local Config = H.moduleAt("shared", "Config")
		local oldCash, oldGems = LocalPlayer:GetAttribute(Config.Attr.Cash), LocalPlayer:GetAttribute(Config.Attr.Gems)
		LocalPlayer:SetAttribute(Config.Attr.Cash, nil)
		LocalPlayer:SetAttribute(Config.Attr.Gems, nil)
		for _, size in ipairs({ { 360, 640 }, { 640, 360 }, { 667, 375 }, { 390, 844 }, { 844, 390 } }) do
			Mock.SetViewport(size[1], size[2])
			H.step(15, 1 / 30)
			local tag = fmt("keys %dx%d raid full: ", size[1], size[2])
			local wide = size[1] > size[2]
			local mine = renderTeam(0, 30)
			if mine[2] then
				mine[2].Evo = 1
				-- (the render's 9 s of fighting knock out its first fighter: the second, evolved, fights with both helpers'
				-- two-line buff names in the column)
				mine[1], mine[2] = mine[2], mine[1]
			end
			local d = H.fight({ Mode = "Raid", Pets = mine, Allies = { renderTeam(2, 26), renderTeam(4, 28) }, Raid = { Tier = "Starter", BossId = "storm_titan" } })
			if T.check(d ~= nil and BC.GetBattle() ~= nil, tag .. "(setup) a full boss raid") then
				if d.sim.boss then
					d.sim.boss.hp = d.sim.boss.maxHp * 0.28 -- (the next step enrages it and sends its minion waves)
				end
				d:run(1.5)
				local Hd = BC._Hud
				local bandMode = Hd.BandMode
				local noStrip = size[1] == 360 and size[2] == 640
				if noStrip then
					-- (white-box) after the render's 9 s of fighting the boss strip's block runs a few px past the room above the
					-- stick: the no-strip layout. This short fight fits the strip with 3.5 design px to spare, so the strip is
					-- turned down here to reach the render's layout
					Hd.BandMode = function()
						return false
					end
				end
				Hd.Rebuild()
				d:run(0.3)
				local top = H.find("Root.TopCard")
				local tr = top and shownIn(top) and rectOf(top)
				if noStrip then
					-- (look review r1: was "the top card stacks into its tall column" under the fighter card, which pushed the
					-- helpers onto Roblox's stick and the team row into the keys; the no-strip card now goes under the enemy list,
					-- so the left column holds the team as the mock's) the render's layout: no strip across the top
					T.check(tr and (tr.x1 - tr.x0) < 0.9 * size[1], tag .. "(setup) the no-strip layout (the top card is not the strip)", tr and rstr(tr) or "hidden")
				end
				local areaY = size[2] - (Mock.TopInset or 0)
				local jump, stick = roblox(size)
				local jr, sr = rings(size)
				local keys = thumb()
				-- (look review r2: at 640 x 360 the list lay 43 px on DASH and RUN, the boss card 8 px on DASH, the list 29 px in
				-- Roblox's jump ring)
				cardsOffKeys(tag, keys, size, "the full raid")
				local helpers, cheer, back = H.find("Root.Team.Helpers"), H.find("Root.Cheer"), H.find("Root.Retreat")
				if T.check(helpers ~= nil and shownIn(helpers) and cheer ~= nil and shownIn(cheer) and back ~= nil and shownIn(back), tag .. "the helper portraits, CHEER and BACK are shown") then
					local hr = rectOf(helpers)
					local others = { TopCard = tr or nil, Fighter = H.find("Root.Team.Fighter") and rectOf(H.find("Root.Team.Fighter")), Helpers = hr }
					local en = H.find("Root.Enemies")
					if en and shownIn(en) then
						others.Enemies = rectOf(en)
					end
					local cr, br = rectOf(cheer), rectOf(back)
					for _, p in ipairs({ { "CHEER", cr }, { "BACK", br } }) do
						local r = p[2]
						T.check(r.x1 - r.x0 >= 44 - 0.01 and r.y1 - r.y0 >= 44 - 0.01 and r.x0 >= 4 and r.x1 <= size[1] - 4 and r.y1 <= areaY - 4,
							tag .. p[1] .. " is touch-sized and whole on the screen, off its foot", rstr(r) .. fmt(" (area foot %.0f)", areaY))
						T.check(apart(r, stick) >= 4 and apart(r, jump) >= 4 and offRing(r, sr) >= 8 and offRing(r, jr) >= 8,
							tag .. p[1] .. " keeps clear of Roblox's stick and jump (8 px off their rings)", fmt("%s stick %.0f ring %.1f", rstr(r), apart(r, stick), offRing(r, sr)))
						-- (look review r1: was 8 px, BACK stood 18 px over DASH) 40 px off every key
						offKeys(tag, p[1], r, keys)
						for n, o in pairs(others) do
							T.check(not overlaps(r, o), tag .. p[1] .. " covers nothing of the " .. n, rstr(r) .. " vs " .. rstr(o))
						end
					end
					T.check(apart(cr, br) >= 4, tag .. "CHEER and BACK stand apart", rstr(cr) .. " / " .. rstr(br))
					-- with the team, as the mock: beside the helper portraits (a wide phone), a row under them (a tall one; under the
					-- enemy list where it lies under the fighter's block)
					local foot = hr.y1
					if others.Enemies and others.Enemies.x0 < hr.x1 and others.Enemies.y0 >= hr.y1 - 1 then
						foot = max(foot, others.Enemies.y1)
					end
					local beside = cr.x0 >= hr.x1 - 0.5 and cr.x0 - hr.x1 <= 16 and cr.y0 < hr.y1 and cr.y1 > hr.y0 and br.x0 >= hr.x1 - 0.5 and br.y0 < hr.y1 and br.y1 > hr.y0
					local under = cr.y0 >= foot - 0.5 and cr.y0 - foot <= 20 and cr.x0 >= hr.x0 - 1 and abs(br.y0 - cr.y0) < 1 and br.x0 >= cr.x1
					T.check(wide and beside or (not wide and under), tag .. "CHEER and BACK stay with the team (" .. (wide and "beside the helper portraits" or "a row under them") .. ")",
						rstr(cr) .. " / " .. rstr(br) .. " | helpers " .. rstr(hr))
				end
				helpersOffStick(tag, size)
				-- (look review r1: at 640 x 360 one line of name each, cut where longer; keys look r4: the cells' tighter rows
				-- give 640 x 360 two whole lines above the stick too) every size's names whole
				namesWhole(tag)
				Hd.BandMode = bandMode
				H.cleanup(BC, d)
			end
		end
		-- (look review r2: at 640 x 360 the dungeon's list lay 47 / 48 px on DASH / RUN, the ring's ("fighter:ready") 36 / 26 px,
		-- RUN under "+1 more", and the duel's 12 / 2 px: a mode card too wide for the gap between the team and the keys went
		-- into the right column, the list under it onto the keys) every other mode, its enemy list full ("+n more"), at every
		-- phone size: the cards keep off the keys at rest and with the meter full (the HOLD tag up), and CHEER / BACK where
		-- they show keep their 40 px off the keys
		for _, size in ipairs({ { 640, 360 }, { 667, 375 }, { 740, 360 }, { 844, 390 }, { 360, 640 }, { 390, 844 } }) do
			Mock.SetViewport(size[1], size[2])
			H.step(15, 1 / 30)
			-- (render_gui's battle:dungeon: a crowned mini-boss, its boss card; battle:fighter: a ring round 8 with a pack of three)
			for _, v in ipairs({ { "Dungeon", "dungeon" }, { "Dungeon", "dungeon mini-boss", MiniBoss = true }, { "Duel", "duel", Spots = FIVE }, { "Ring", "ring round 8", Round = 8 } }) do
				local mode = v[1]
				local tag = fmt("keys %dx%d %s: ", size[1], size[2], v[2])
				local d = H.fight({ Mode = mode, Pets = renderTeam(0, 30), Spots = v.Spots, MiniBoss = v.MiniBoss, Round = v.Round })
				if T.check(d ~= nil and BC.GetBattle() ~= nil, tag .. "(setup) the fight") then
					local en = H.find("Root.Enemies")
					local rows = 0
					for _, row in ipairs(en and en:GetChildren() or {}) do
						if row:IsA("GuiObject") and shownIn(row) and row.Name ~= "More" and row.AbsoluteSize.Y > 1 then
							rows = rows + 1
						end
					end
					-- (a ring champion's bench is not on the list: its fighter's row; a portrait phone's list keeps one row above the
					-- keys and the band where it has to, its "+n more" tag beside or under it)
					T.check(en ~= nil and shownIn(en) and rows >= 1, tag .. "(setup) the enemy list shows", rows .. " rows")
					if v.MiniBoss then
						T.check(BC._Hud.BossUnit(BC._St.battle) ~= nil, tag .. "(setup) the mini-boss's card (its boss bar)")
					end
					local keys, names = thumb()
					T.check(table.concat(names, ",") == table.concat(WANT, ","), tag .. "exactly three right-thumb buttons: MOVE, DASH, RUN", table.concat(names, ","))
					cardsOffKeys(tag, keys, size, "at rest")
					for _, p in ipairs({ { "CHEER", H.find("Root.Cheer") }, { "BACK", H.find("Root.Retreat") } }) do
						if p[2] and shownIn(p[2]) then
							offKeys(tag, p[1], rectOf(p[2]), keys)
						end
					end
					d.sim.teams[1].fighter.meter = 100
					d:run(0.4)
					local hold = H.find("Root.Commands.ElementButton.HoldTag")
					T.check(hold ~= nil and shownIn(hold), tag .. "(setup) the meter full: MOVE's HOLD tag shows")
					local now = thumb()
					cardsOffKeys(tag, now, size, "the meter full")
					H.cleanup(BC, d)
				end
			end
		end
		LocalPlayer:SetAttribute(Config.Attr.Cash, oldCash)
		LocalPlayer:SetAttribute(Config.Attr.Gems, oldGems)
		Mock.SetViewport(390, 844)
		H.step(3, 0.1)
		T.check(#Mock.Errors == err0, "keys: no script errors", tostring(Mock.Errors[#Mock.Errors]))
		KC.flushErrors("keys_three_buttons")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
