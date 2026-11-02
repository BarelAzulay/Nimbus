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
--   client_evo_buttons_mobile (phone world) 844x390, 740x360, 749x388, 667x375, 1024x768, 390x844, 360x640: Special >= 72 px, Target >= 44, Element >= 56, Dash >= 44; nothing overlaps the
--                             stick / jump / vitals / Cheer up! / another button; the longest names fit inside the faces in 2 lines at >= 11 px
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
		elseif mode == "Ring" then
			setup.Round = 1
			setup.Teams[2] = BCat.ChampionTeam(1, 1)
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
		local d = setmetatable({ sim = sim, id = id, mode = mode, me = me, logIndex = #Mock.RemoteLog, last = {},
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
				wave[i] = { PetId = "puddle_frog", Key = "puddle_frog", Level = 10, Tier = "Normal", Wild = true }
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
				local perks = nil
				for _, o in ipairs(gui and gui:GetDescendants() or {}) do
					if o.Name == "Perks" then
						perks = o
					end
				end
				local text = perks and tostring(perks.Text) or ""
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
					T.check(special.Position.X.Offset == -74 and special.Position.Y.Offset == -98, tag .. "Special sits where Attack sat", tostring(special.Position))
					T.check(target.Position.X.Offset == -74 - 44 - 26 - 32 and target.Position.Y.Offset == -90, tag .. "Target sits where Special sat", tostring(target.Position))
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
					-- "MARSHMALLOW" must not break either: a 11-letter word on one line
					ok, lines, widest = H.fits("MARSHMALLOW STAMPEDE", r.x1 - r.x0, r.y1 - r.y0, px)
					T.check(ok, tag .. "...and the longest word fits on one line", fmt("widest %.0f, box %.0f", widest, r.x1 - r.x0))
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
			return out
		end
		local MIN_PX = { Special = 72, Target = 44, Element = 56, Dash = 44 }
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
				if rects.Special and rects.Target and rects.Element and rects.Dash then
					T.check(rects.Special.x1 - rects.Special.x0 > rects.Element.x1 - rects.Element.x0, tag .. "Special is the biggest")
					local kinds = { "Special", "Target", "Element", "Dash" }
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
				-- the names sit inside the face: the longest special name in 2 lines at >= 11 px
				local cap = H.find("Root.Commands.SpecialButton.Caption")
				local glyph = H.find("Root.Commands.SpecialButton.Face.Glyph")
				if T.check(cap ~= nil and shownIn(cap) and cap.Text == "WISH UPON THE STARS", tag .. "the Special face shows the name", cap and cap.Text or "nil") then
					T.check(cap.TextWrapped == true and cap.TextScaled == true, tag .. "...wrapped and scaled")
					local c = cap:FindFirstChildOfClass("UITextSizeConstraint")
					T.check(c ~= nil and c.MinTextSize >= 11 and c.MaxTextSize <= 15, tag .. "...between 11 and 15 px", c and fmt("%s..%s", tostring(c.MinTextSize), tostring(c.MaxTextSize)) or "no constraint")
					local r = rectOf(cap)
					local w, h = r.x1 - r.x0, r.y1 - r.y0
					for _, name in ipairs({ "WISH UPON THE STARS", "MARSHMALLOW POUNCE", "MARSHMALLOW STAMPEDE" }) do
						local ok, lines, widest = H.fits(name, w, h, 11)
						T.check(ok, tag .. "\"" .. name .. "\" fits the Special face in 2 lines at 11 px", fmt("%d lines, widest %.0f, box %.0fx%.0f", lines, widest, w, h))
					end
					local br = rects.Special
					T.check(br ~= nil and r.y0 >= (br.y0 + br.y1) / 2 and r.y1 <= br.y1 + 0.5, tag .. "...in the lower part of the face", rstr(r))
					T.check(glyph ~= nil and glyph.Size.Y.Scale <= 0.56 and glyph.TextSize * 1 <= glyph.AbsoluteSize.Y / (H.find("Root.ReadScale").Scale), tag .. "...the star shrinks to the top of it", glyph and tostring(glyph.Size) or "nil")
				end
				local ecap = H.find("Root.Commands.ElementButton.Caption")
				if T.check(ecap ~= nil and shownIn(ecap), tag .. "the Element face shows the name") then
					local r = rectOf(ecap)
					for _, name in ipairs({ "THUNDER LANCE", "BRAMBLE LASH", "WORLDROOT", "MAELSTROM" }) do
						local ok, lines, widest = H.fits(name, r.x1 - r.x0, r.y1 - r.y0, 11)
						T.check(ok, tag .. "\"" .. name .. "\" fits the Element face in 2 lines at 11 px", fmt("%d lines, widest %.0f, box %.0fx%.0f", lines, widest, r.x1 - r.x0, r.y1 - r.y0))
					end
				end
				-- TARGET: its caption shows on touch; ONE ENEMY takes the whole face while it shows
				local tcap = H.find("Root.Commands.TargetButton.Caption")
				local tglyph = H.find("Root.Commands.TargetButton.Face.Glyph")
				if T.check(tcap ~= nil and shownIn(tcap) and tcap.Text == "TARGET", tag .. "the TARGET face says TARGET", tcap and tcap.Text or "nil") then
					local r = rectOf(tcap)
					T.check((H.fits("TARGET", r.x1 - r.x0, r.y1 - r.y0, 11)), tag .. "...and it fits", rstr(r))
					d.noForward = true
					for _, id in ipairs(d:byDistance()) do
						if id ~= d:byDistance()[1] then
							d:kill(id)
						end
					end
					T.eq(#d:byDistance(), 1, tag .. "(setup) one enemy left")
					local tb = H.find("Root.Commands.TargetButton")
					local a, s = tb.AbsolutePosition, tb.AbsoluteSize
					local inp = Mock.NewInput("Unknown", "Touch", "Begin", { Position = Vector3.new(a.X + s.X / 2, a.Y + s.Y / 2, 0) })
					local idx = #Mock.RemoteLog
					Mock.FireSignal(tb, "InputBegan", inp, false)
					H.step(3, 1 / 30)
					inp.UserInputState = Enum.UserInputState.End
					Mock.FireSignal(tb, "InputEnded", inp, false)
					Mock.FireSignal(UserInputService, "InputEnded", inp, false)
					H.step(1, 1 / 30)
					T.check(#H.commands(idx) == 0 and tcap.Text == "ONE ENEMY", tag .. "a tap with one enemy left says ONE ENEMY and sends nothing", tcap.Text)
					r = rectOf(tcap)
					local ok, lines, widest = H.fits("ONE ENEMY", r.x1 - r.x0, r.y1 - r.y0, 11)
					T.check(ok and tglyph ~= nil and not shownIn(tglyph), tag .. "...over the whole face, in 2 lines at 11 px", fmt("%d lines, widest %.0f, box %.0fx%.0f", lines, widest, r.x1 - r.x0, r.y1 - r.y0))
					H.step(24, 1 / 30)
					T.check(tcap.Text == "TARGET" and tglyph ~= nil and shownIn(tglyph), tag .. "...then TARGET and its glyph are back", tcap.Text)
				end
				local dcap = H.find("Root.Commands.DashButton.Caption")
				T.check(dcap ~= nil and not shownIn(dcap), tag .. "DASH keeps its plain face on touch")
				H.cleanup(BC, d)
			end
		end
		Mock.SetViewport(390, 844)
		H.step(3, 0.1)
		T.check(#Mock.Errors == err0, "evo phone: no script errors", tostring(Mock.Errors[#Mock.Errors]))
		KC.flushErrors("client_evo_buttons_mobile")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
