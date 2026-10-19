-- smoke_p5_battleclient.lua: Phase 5 BattleController (ARCHITECTURE_V3.md "Phase 5 build contract" 4.7, 3.9; owner:
-- battleclient W3) + MovementController's battle switches + PetCard's lives pips. Loaded by tools/smoke.py in the client
-- worlds (desktop 1920x1080 and the 390x844 touch phone). A real BattleSim is stepped at 10 Hz and its Start (with the
-- receiver's Team, like BattleService.startPayload: Buff cooldown keys as STRINGS) / Events / Snapshot / End reach the
-- client through BattleState; the client's BattleCommand calls are forwarded into the sim (Order echoes come back).
--   client_p5hud_fighter   the fighter card (name, Lv, element, HP written only on change, the red loss trail behind a
--                          loss, ENERGY n/100, 3 hearts = lives from the snapshot), the two helper portraits (Lv, buff
--                          name, the cooldown ring from the Buff event, KO greys), late-join cooldowns from Start.Team
--   client_p5hud_enemies   one row per living enemy, the LOCKED row first (gold bracket + TARGET), max 8 + "+n more",
--                          the wind-up "!" flash, the boss bar at the top and never in the screen centre
--   client_p5input         the 4.7 map bound only while fighting (and inert before UiGate.HasPlayed), hold-to-attack at
--                          the fighter's interval, a helper key: tap = Buff, hold 0.5 s = Swap, Tab cycles the lock,
--                          predictions (the ring starts at once) + a rejected Order (owner-only) puts it back and shakes
--                          the button + the 0.6 s timeout; MovementController.SetDashKeys / SetFreeDash /
--                          SetBattleSpeed(walk, run) on Start / Speed / End (WalkSpeed = walk, run target = run, nil
--                          restores the server base, a server 0 still wins), EXHAUST_RESUME 22
--   client_p5models        my fighter drawn at the shoulder of the server position (blended with my character within
--                          2 studs, following the server beyond), helpers behind me that fly on Buff / trade on Swap
--                          (the new fighter rebuilt High), the Winding crouch + yellow flash, DODGED!, the camera shake
--                          x the Shake setting, PetCard lives pips
--   client_p5result        the result card: Lives left, the dungeon's Floor / Room lines on a wipe, no card for a
--                          cleared room (DungeonController shows the loot), bottom right on a wide screen
--   client_p5battle_mobile / client_p5battle_landscape (phone world, 390x844 / 740x360 / 844x390): nothing of the HUD in
--                          the centre 40% of the width (below the top strip, above the bottom strip), action buttons >=
--                          60 design px, the menu column hidden, every text >= 14 px, no HUD over another GUI's button
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local KC = _G.KC
local S = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local abs, floor, max, min = math.abs, math.floor, math.max, math.min

local H = {} -- helpers (one local for the whole harness)

function H.fmt(v, n)
	if type(v) ~= "number" then
		return tostring(v)
	end
	return string.format("%." .. (n or 2) .. "f", v)
end

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

function H.gui()
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	return pg and pg:FindFirstChild("NimbusBattle")
end

function H.shown(obj)
	if not obj then
		return false
	end
	local cur = obj
	while cur and not cur:IsA("ScreenGui") do
		if cur:IsA("GuiObject") and not cur.Visible then
			return false
		end
		cur = cur.Parent
	end
	return cur ~= nil and cur.Enabled
end

function H.find(path)
	local cur = H.gui()
	for name in string.gmatch(path, "[^%.]+") do
		if not cur then
			return nil
		end
		cur = cur:FindFirstChild(name)
	end
	return cur
end

function H.texts(root)
	local out = {}
	for _, d in ipairs(root and root:GetDescendants() or {}) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and H.shown(d) and tostring(d.Text) ~= "" then
			out[#out + 1] = d
		end
	end
	return out
end

function H.hasText(root, needle)
	for _, d in ipairs(H.texts(root)) do
		if tostring(d.Text):gsub("<[^>]*>", ""):find(needle, 1, true) then
			return true, d
		end
	end
	return false
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

function H.warnings(fromIndex)
	for i = fromIndex + 1, #Mock.Output do
		local o = Mock.Output[i]
		if o.kind == "warn" and o.text:find("BattleController", 1, true) then
			return o.text
		end
	end
	return nil
end

-- a GUI object's rectangle in screen px (the top bar inset added for IgnoreGuiInset = false guis)
function H.rect(obj)
	local p, s = obj.AbsolutePosition, obj.AbsoluteSize
	local g = obj:FindFirstAncestorOfClass("ScreenGui")
	local dy = (g and g.IgnoreGuiInset == false) and (Mock.TopInset or 36) or 0
	return { x0 = p.X, y0 = p.Y + dy, x1 = p.X + s.X, y1 = p.Y + s.Y + dy }
end

function H.overlap(a, b)
	return a.x0 < b.x1 - 1 and b.x0 < a.x1 - 1 and a.y0 < b.y1 - 1 and b.y0 < a.y1 - 1
end

function H.rectText(r)
	return r and string.format("%d,%d-%d,%d", r.x0, r.y0, r.x1, r.y1) or "nil"
end

-- a team of `count` combat pets with different specials (skipping `skip` of them)
function H.team(count, skip, level)
	local PC = H.moduleAt("shared", "PetCatalog")
	local out, kinds = {}, {}
	skip = skip or 0
	for _, def in ipairs(PC and PC.Pets or {}) do
		local sp = type(def.Special) == "table" and def.Special.Kind or nil
		if sp and def.Role == "Combat" and not kinds[sp] and def.Rarity ~= "Secret" and not def.EventOnly then
			if skip > 0 then
				skip = skip - 1
			else
				kinds[sp] = true
				out[#out + 1] = { Key = def.Id, PetId = def.Id, Level = level or 12, Tier = "Normal", Slot = #out + 1 }
				if #out >= count then
					break
				end
			end
		end
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- the battle driver: a real BattleSim sent the way BattleService sends it
----------------------------------------------------------------------------------------------------
local Driver = {}
Driver.__index = Driver

-- opts: Mode, Teams, Boss, Side (0 = spectator), Zone, TimeLimit, Wave (entries spawned at once), Dungeon (the extra),
--       Ring, Team (override of Start.Team), Seed
function H.driver(opts)
	local Sim = H.moduleAt("shared", "BattleSim")
	if not Sim then
		return nil, "shared/BattleSim.lua missing"
	end
	local id = "p5bc_" .. tostring(opts.Mode) .. "_" .. tostring(math.random(100000, 999999))
	local sim, why = Sim.new({ Mode = opts.Mode, Seed = opts.Seed or 5, Id = id, Teams = opts.Teams, Boss = opts.Boss, Round = opts.Round,
		Zone = opts.Zone or { X = 44, Z = 44 }, TimeLimit = opts.TimeLimit or 120 })
	if not sim then
		return nil, why
	end
	if opts.Wave then
		local infos = sim:SpawnEnemies(opts.Wave, { Wave = 1, Anchor = { 0, 10 } })
		if not infos then
			return nil, "SpawnEnemies failed"
		end
	end
	local d = setmetatable({ sim = sim, id = id, zoneCF = CFrame.new(0, 200, 0), side = opts.Side or 1, logIndex = #Mock.RemoteLog, events = {}, opts = opts }, Driver)
	d.me = LocalPlayer.UserId
	return d
end

function Driver:startPayload()
	local p = self.sim:Describe()
	p.BattleId = self.id
	p.Zone = { CFrame = self.zoneCF, Size = Vector3.new(p.Zone.X, 30, p.Zone.Z), X = p.Zone.X, Z = p.Zone.Z }
	p.Names = { [tostring(self.me)] = LocalPlayer.Name, ["77"] = "Buddy", ["78"] = "Rival" }
	p.Side = self.side
	p.Spectator = self.side == 0
	p.T = self.sim:Time()
	p.Ring = self.opts.Ring
	p.Dungeon = self.opts.Dungeon
	if self.side ~= 0 then
		local team = self.sim:TeamOf(self.me)
		if team then
			local buff = {}
			for slot, secs in pairs(team.Cooldowns.Buff or {}) do
				buff[tostring(slot)] = secs
			end
			p.Team = { Fighter = team.Fighter, Bench = team.Bench, Lives = team.Lives, Speed = team.Speed,
				Cooldowns = { Element = team.Cooldowns.Element, Dash = team.Cooldowns.Dash, Swap = team.Cooldowns.Swap, Buff = buff } }
		end
		if self.opts.Team then
			for k, v in pairs(self.opts.Team) do
				p.Team[k] = v
			end
		end
	end
	return p
end

function Driver:start()
	KC.toClient("BattleState", "Start", self:startPayload(), self.id)
end

-- the wire form, like BattleService (SnapshotDelta against this driver's baseline)
function Driver:snapshot()
	self.last = self.last or {}
	local snap = self.sim:SnapshotDelta(self.last)
	snap.BattleId = self.id
	return snap
end

-- forwards the client's BattleCommand calls into the sim (like BattleService.Command; a refused one echoes)
function Driver:forward()
	if self.side == 0 or self.noForward then
		self.logIndex = #Mock.RemoteLog
		return
	end
	for _, c in ipairs(H.commands(self.logIndex)) do
		pcall(self.sim.Command, self.sim, self.me, c.action, c.arg)
	end
	self.logIndex = #Mock.RemoteLog
end

-- one 0.1 s server step at `fps` client frames per second; rejected Orders go to their owner only (like BattleService)
function Driver:step(fps, hook)
	self:forward()
	local evs = self.sim:Step(0.1)
	if #evs > 0 then
		for _, e in ipairs(evs) do
			self.events[#self.events + 1] = e
		end
		KC.toClient("BattleState", "Events", evs, self.id)
	end
	local snap = self:snapshot()
	if hook then
		hook(snap)
	end
	KC.toClient("BattleState", "Snapshot", snap, self.id)
	local frames = max(1, floor((fps or 30) * 0.1 + 0.5))
	H.step(frames, 0.1 / frames)
	return evs
end

function Driver:run(seconds, fps, each)
	for _ = 1, floor(seconds / 0.1 + 0.5) do
		local evs = self:step(fps)
		if each then
			each(evs)
		end
		if self.sim:IsFinished() then
			break
		end
	end
end

function Driver:finish(payload)
	payload = payload or {}
	payload.BattleId = self.id
	KC.toClient("BattleState", "End", payload, self.id)
end

function Driver:team()
	return self.sim:TeamOf(self.me)
end

function Driver:unit(id)
	for _, u in ipairs(self.sim.units or {}) do
		if u.id == id then
			return u
		end
	end
	return nil
end

function Driver:enemyIds()
	local out = {}
	for _, u in ipairs(self.sim.units or {}) do
		if u.side ~= 1 and u.alive and not u.gone then
			out[#out + 1] = u.id
		end
	end
	table.sort(out)
	return out
end

-- a dungeon room: my team (3 pets) vs a wave of `n` wild pets (+ a mini-boss when boss)
function H.dungeon(n, boss, extra)
	local wave = H.team(n, 3, 10)
	for _, p in ipairs(wave) do
		p.Wild = true
	end
	if boss and wave[#wave] then
		wave[#wave].Boss = true
	end
	local opts = { Mode = "Dungeon", Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = H.team(3, 0, 14) } }, Wave = wave,
		Dungeon = { Floor = 3, Room = 2, Wave = 1, Waves = 3, Name = "Ember Hall", Boss = boss == true } }
	for k, v in pairs(extra or {}) do
		opts[k] = v
	end
	return H.driver(opts)
end

function H.begin(d)
	LocalPlayer:SetAttribute("InBattle", d.id)
	d:start()
	d:step(30)
	d:step(30)
end

function H.cleanup(BC, d)
	if d and BC.GetBattle() then
		d:finish({ Mode = d.opts.Mode, Outcome = "Left", Won = false, Spectator = false, Reason = "Left" })
	end
	LocalPlayer:SetAttribute("InBattle", nil)
	KC.advance(15)
	local r = H.find("Root.ResultCard.Body.OkButton")
	if r and H.shown(r) then
		Mock.Click(r)
	end
	Mock.Step(0.1)
end

function H.load()
	local BC = H.moduleAt("client", "Controllers/BattleController")
	T.check(BC ~= nil, "BattleController: client/Controllers/BattleController.lua loads")
	return BC
end

----------------------------------------------------------------------------------------------------
-- client_p5hud_fighter
----------------------------------------------------------------------------------------------------
S.client_p5hud_fighter = guarded("client_p5hud_fighter", function()
	local BC = H.load()
	if not BC then
		return
	end
	local out0, err0 = #Mock.Output, #Mock.Errors
	local d, why = H.dungeon(3, false)
	if not T.check(d ~= nil, "p5 hud: a dungeon room driver", tostring(why)) then
		return
	end
	H.begin(d)
	local b = BC.GetBattle()
	local team = d:team()
	T.check(b and b.Fighter and b.FighterId == team.Fighter, "p5 hud: Start.Team names my fighter", b and tostring(b.FighterId) or "nil")
	T.check(BC.IsHudVisible() and H.shown(H.find("Root.Team.Fighter")), "p5 hud: the fighter card shows while fighting")
	local f = d:unit(team.Fighter)
	local card = H.find("Root.Team.Fighter")
	T.check(H.hasText(card, f.name), "p5 hud: the card names the fighter", f.name)
	T.check(H.hasText(card, "Lv " .. tostring(f.level)), "p5 hud: the Lv pill", "Lv " .. tostring(f.level))
	T.check(H.hasText(card, "ENERGY "), "p5 hud: the ENERGY line")
	local nameLbl = H.find("Root.Team.Fighter.Body.PetName")
	local Theme = H.moduleAt("shared", "Theme")
	T.check(nameLbl and Theme and nameLbl.Font == Theme.Fonts.Heading and (nameLbl:GetAttribute("BaseText") or nameLbl.TextSize) == 26, "p5 hud: the name is the Heading role at 26 (design px)")
	local hp = H.find("Root.Team.Fighter.Body.Hp")
	T.check(hp and hp.Size.X.Offset == 320 and hp.Size.Y.Offset == 22, "p5 hud: HP bar 320 x 22", hp and (hp.Size.X.Offset .. "x" .. hp.Size.Y.Offset) or "nil")
	local en = H.find("Root.Team.Fighter.Body.Energy")
	T.check(en and en.Size.X.Offset == 320 and en.Size.Y.Offset == 14, "p5 hud: ENERGY bar 320 x 14", en and (en.Size.X.Offset .. "x" .. en.Size.Y.Offset) or "nil")
	-- hearts = lives (from the fighter's snapshot record)
	local function litHearts()
		local n = 0
		for i = 1, 3 do
			local h = H.find("Root.Team.Fighter.Body.Lives.Heart" .. i)
			if h and h.TextTransparency == 0 then
				n = n + 1
			end
		end
		return n
	end
	T.eq(litHearts(), 3, "p5 hud: three hearts lit (3 lives)")
	d:step(30, function(snap)
		-- white-box on the wire: the fighter's code carries lives 2 (id x 1024 + lives x 256 + ...)
		local U = snap.U
		local i = 1
		while i + 1 <= #U do
			local code = U[i]
			if floor(code / 1024) == team.Fighter then
				U[i] = code - floor(code / 256) % 4 * 256 + 2 * 256
			end
			local mask = floor(code / 8) % 16
			local extra = 0
			for _, bit in ipairs({ 1, 2, 4, 8 }) do
				if mask % (bit * 2) >= bit then
					extra = extra + 1
				end
			end
			i = i + 2 + extra
		end
	end)
	H.step(3, 1 / 30)
	T.eq(litHearts(), 2, "p5 hud: the hearts follow the snapshot's lives (2)")
	d:step(30)
	H.step(3, 1 / 30)
	-- HP writes only on change + the loss trail
	local stats0 = BC.GetStats()
	H.step(30, 1 / 60) -- frames without snapshots
	T.eq(BC.GetStats().HpWrites, stats0.HpWrites, "p5 hud: no HP write on frames without a new value")
	local simF = d:unit(team.Fighter)
	simF.hp = simF.hp * 0.55
	d:step(30)
	H.step(2, 1 / 60)
	local fill = H.find("Root.Team.Fighter.Body.Hp.Fill")
	local loss = H.find("Root.Team.Fighter.Body.Hp.Loss")
	T.check(BC.GetStats().HpWrites > stats0.HpWrites, "p5 hud: a loss writes the HP once it arrives")
	T.check(fill and loss and loss.Size.X.Scale > fill.Size.X.Scale + 0.05, "p5 hud: the red loss trail stays behind the green fill right after a loss",
		fill and loss and (H.fmt(fill.Size.X.Scale) .. " < " .. H.fmt(loss.Size.X.Scale)) or "nil")
	H.step(40, 1 / 60)
	T.check(fill and loss and abs(loss.Size.X.Scale - fill.Size.X.Scale) < 0.02, "p5 hud: ... and drains to it within ~0.4 s", loss and H.fmt(loss.Size.X.Scale) or "nil")
	local frac = simF.hp / simF.maxHp
	T.check(fill and abs(fill.Size.X.Scale - frac) < 0.03, "p5 hud: HP fill = hp / maxHp", fill and (H.fmt(fill.Size.X.Scale) .. " vs " .. H.fmt(frac)) or "nil")
	-- energy
	simF.meter = 60
	d:step(30)
	H.step(2, 1 / 30)
	local okE, lblE = H.hasText(card, "ENERGY ")
	local shownE = lblE and tonumber(tostring(lblE.Text):match("ENERGY (%d+)/100"))
	T.check(okE and shownE and shownE >= 60 and shownE <= 62, "p5 hud: ENERGY 60/100 from the snapshot (+ the meter's own gain)", lblE and lblE.Text or "nil")
	-- helpers: portraits, Lv, buff names, rings from the Buff event
	local bench = team.Bench
	T.eq(#bench, 2, "p5 hud: two helpers on the bench")
	local ok1 = H.shown(H.find("Root.Team.Helpers.Helper1")) and H.shown(H.find("Root.Team.Helpers.Helper2"))
	T.check(ok1, "p5 hud: two helper portraits under the card")
	local h1 = d:unit(bench[1])
	T.check(H.hasText(H.find("Root.Team.Helpers.Helper1"), "Lv " .. tostring(h1.level)), "p5 hud: a portrait shows its Lv")
	local buffName = h1.buffDef and string.upper(h1.buffDef.Name) or "?"
	T.check(H.hasText(H.find("Root.Team.Helpers.Helper1"), buffName), "p5 hud: a portrait shows its buff name", buffName)
	T.check(H.find("Root.Team.Helpers.Helper1.Disc.Portrait.View") ~= nil, "p5 hud: the portrait is a ViewportFrame picture")
	local vf = H.find("Root.Team.Helpers.Helper1.Disc.Portrait.View")
	local built = 0
	for _, c in ipairs(vf and vf:GetChildren() or {}) do
		if c:IsA("Model") then
			built = built + 1
		end
	end
	T.check(built == 1 and vf.CurrentCamera ~= nil, "p5 hud: ... a Low PetBuilder model framed by its own camera", built .. " models")
	local face = H.find("Root.Team.Helpers.Helper1.Disc.Portrait")
	local idx = #Mock.RemoteLog
	Mock.Click(face) -- a tap = the buff
	local cmds = H.commands(idx)
	T.check(#cmds == 1 and cmds[1].action == "Buff" and cmds[1].arg == h1.slot, "p5 hud: tapping a portrait sends its Buff (its team slot)", #cmds > 0 and (tostring(cmds[1].action) .. " " .. tostring(cmds[1].arg)) or "none")
	d:run(0.4, 30)
	b = BC.GetBattle()
	local left = b.Cooldowns.Buff[h1.slot] or 0
	T.check(left > 8 and left <= 15.1, "p5 hud: the Buff event starts that helper's cooldown ring", H.fmt(left) .. " s")
	T.check(b.Pending.Buff == nil, "p5 hud: ... and confirms the prediction")
	H.step(4, 0.1)
	local count = H.find("Root.Team.Helpers.Helper1.Disc.Portrait.Count")
	T.check(count and H.shown(count) and tonumber(count.Text) ~= nil, "p5 hud: the portrait counts its cooldown down", count and count.Text or "nil")
	local ring = H.find("Root.Team.Helpers.Helper1.Disc.Ring.R.Disc")
	T.check(ring ~= nil, "p5 hud: the ring is a two-half pie (UIGradient sweep)")
	-- KO greys the portrait (white-box: the helper goes down)
	local h2 = d:unit(bench[2])
	h2.hp = 0
	h2.alive = false
	h2.state = 5
	d:step(30)
	H.step(4, 0.1)
	T.check(H.shown(H.find("Root.Team.Helpers.Helper2.Disc.Portrait.KO")), "p5 hud: a downed helper's portrait is greyed with KO")
	H.cleanup(BC, d)
	-- a late joiner gets the running cooldowns from Start.Team.Cooldowns (Buff keyed by slot STRINGS)
	local d2 = H.dungeon(2, false, { Team = { Cooldowns = { Element = 5, Dash = 0, Swap = 8, Buff = { ["2"] = 6, ["3"] = 0 } } } })
	H.begin(d2)
	b = BC.GetBattle()
	T.check(b and abs((b.Cooldowns.Element or 0) - 4.8) < 0.5 and abs((b.Cooldowns.Buff[2] or 0) - 5.8) < 0.5 and abs((b.Cooldowns.Swap or 0) - 7.8) < 0.5,
		"p5 hud: late-join cooldowns from Start.Team (Element 5, Swap 8, Buff['2'] 6)", b and (H.fmt(b.Cooldowns.Element) .. " / " .. H.fmt(b.Cooldowns.Swap) .. " / " .. H.fmt(b.Cooldowns.Buff[2])) or "nil")
	local elementCount = H.find("Root.Commands.ElementButton.Face.Count")
	T.check(elementCount and H.shown(elementCount) and tonumber(elementCount.Text) ~= nil and tonumber(elementCount.Text) >= 4, "p5 hud: the ELEMENT button counts the cooldown down", elementCount and elementCount.Text or "nil")
	H.cleanup(BC, d2)
	T.check(H.warnings(out0) == nil and #Mock.Errors == err0, "p5 hud: no BattleController errors or warnings", tostring(H.warnings(out0)))
	KC.flushErrors("client_p5hud_fighter")
end)

----------------------------------------------------------------------------------------------------
-- client_p5hud_enemies
----------------------------------------------------------------------------------------------------
S.client_p5hud_enemies = guarded("client_p5hud_enemies", function()
	local BC = H.load()
	if not BC then
		return
	end
	local out0, err0 = #Mock.Output, #Mock.Errors
	local d = H.dungeon(3, true)
	if not T.check(d ~= nil, "p5 enemies: driver") then
		return
	end
	H.begin(d)
	local ids = d:enemyIds()
	local rows = 0
	for i = 1, 8 do
		if H.shown(H.find("Root.Enemies.Row" .. i)) then
			rows = rows + 1
		end
	end
	T.eq(rows, #ids, "p5 enemies: one row per living enemy")
	local row1 = H.find("Root.Enemies.Row1")
	T.check(row1 and row1.Size.X.Offset == 300 and row1.Size.Y.Offset == 44, "p5 enemies: rows are 300 x 44 (design px)", row1 and (row1.Size.X.Offset .. "x" .. row1.Size.Y.Offset) or "nil")
	T.check(H.find("Root.Enemies.Row1.Hp") ~= nil and H.find("Root.Enemies.Row1.Element") ~= nil and H.find("Root.Enemies.Row1.Icon") ~= nil, "p5 enemies: icon disc, element stripe, HP bar")
	local u3 = d:unit(ids[3])
	T.check(H.hasText(H.find("Root.Enemies"), u3.name), "p5 enemies: the rows name the enemies", u3.name)
	-- lock: clicking the third row locks it; it moves first with the bracket + TARGET
	local third = nil
	for i = 1, 8 do
		local r = H.find("Root.Enemies.Row" .. i)
		if r and H.shown(r) and H.hasText(r, u3.name) then
			third = r
		end
	end
	local idx = #Mock.RemoteLog
	if third then
		Mock.Click(third)
	end
	local cmds = H.commands(idx)
	T.check(#cmds == 1 and cmds[1].action == "Target" and cmds[1].arg == ids[3], "p5 enemies: clicking a row locks it (Target id)", #cmds > 0 and tostring(cmds[1].arg) or "none")
	d:run(0.4, 30)
	T.eq(BC.GetBattle().Lock, ids[3], "p5 enemies: the Order echo keeps the lock")
	row1 = H.find("Root.Enemies.Row1")
	T.check(row1 and H.hasText(row1, u3.name) and H.shown(H.find("Root.Enemies.Row1.Bracket")) and H.shown(H.find("Root.Enemies.Row1.Target")), "p5 enemies: the LOCKED row comes first with the gold bracket + TARGET")
	-- the boss bar (a mini-boss room): top centre under the Roblox bar, never over the screen centre
	local boss = H.find("Root.TopCard.BossBar")
	T.check(H.shown(boss), "p5 enemies: a mini-boss room shows the boss bar")
	if boss then
		local r = H.rect(boss)
		local vp = Mock.Viewport
		T.check(r.y1 < vp.Y * 0.3 and not (r.x0 <= vp.X / 2 and vp.X / 2 <= r.x1 and r.y0 <= vp.Y / 2 and vp.Y / 2 <= r.y1), "p5 enemies: the boss bar sits at the top, not in the centre", H.rectText(r))
	end
	-- the wind-up "!": a Windup event flashes the attacker's row icon until the hit
	local who = ids[1]
	KC.toClient("BattleState", "Events", { { type = "Windup", unit = who, target = d:team().Fighter, at = d.sim:Time() + 0.45 } }, d.id)
	d:step(30)
	d:step(30)
	local alertRow = nil
	for i = 1, 8 do
		local r = H.find("Root.Enemies.Row" .. i)
		if r and H.shown(r) and H.hasText(r, d:unit(who).name) then
			alertRow = r
		end
	end
	T.check(alertRow and H.shown(alertRow:FindFirstChild("Icon") and alertRow.Icon:FindFirstChild("Alert")), "p5 enemies: a winding enemy's row flashes '!'")
	local offOnce = false
	for _ = 1, 20 do
		d:step(30)
		if alertRow and not H.shown(alertRow.Icon.Alert) then
			offOnce = true
		end
	end
	T.check(offOnce, "p5 enemies: ... and stops after the hit")
	H.cleanup(BC, d)
	-- max 8 rows + "+n more"
	local wave = {}
	for i = 1, 10 do
		local t = H.team(1, (i - 1) % 6, 3)[1]
		t.Slot = nil
		t.Wild = true
		wave[i] = t
	end
	local big = H.driver({ Mode = "Dungeon", Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = H.team(3, 0, 40) } }, Wave = wave, Dungeon = { Floor = 1, Room = 1 } })
	if T.check(big ~= nil, "p5 enemies: a 10-enemy room") then
		H.begin(big)
		local shownRows = 0
		for i = 1, 12 do
			if H.shown(H.find("Root.Enemies.Row" .. i)) then
				shownRows = shownRows + 1
			end
		end
		T.eq(shownRows, 8, "p5 enemies: at most 8 rows")
		T.check(H.hasText(H.find("Root.Enemies"), "+2 more"), "p5 enemies: ... and '+2 more'")
		H.cleanup(BC, big)
	end
	T.check(H.warnings(out0) == nil and #Mock.Errors == err0, "p5 enemies: no BattleController errors or warnings", tostring(H.warnings(out0)))
	KC.flushErrors("client_p5hud_enemies")
end)

----------------------------------------------------------------------------------------------------
-- client_p5input
----------------------------------------------------------------------------------------------------
S.client_p5input = guarded("client_p5input", function()
	local BC = H.load()
	if not BC then
		return
	end
	local MC = H.moduleAt("client", "Controllers/MovementController")
	local out0, err0 = #Mock.Output, #Mock.Errors
	local names = { "NimbusBattleAttack", "NimbusBattleElement", "NimbusBattleSpecial", "NimbusBattleTarget", "NimbusBattleHelper" }
	local function bound()
		local n = 0
		for _, nm in ipairs(names) do
			if Mock.BoundActions[nm] then
				n = n + 1
			end
		end
		return n
	end
	T.eq(bound(), 0, "p5 input: no battle keys bound outside a battle (the hotbar keeps 1-4, prompts keep E)")
	local hum = Mock.GetHumanoid(LocalPlayer)
	if hum then
		hum.WalkSpeed = 16
	end
	KC.advance(0.5)
	local d = H.dungeon(3, false)
	if not T.check(d ~= nil, "p5 input: driver") then
		return
	end
	H.begin(d)
	T.eq(bound(), #names, "p5 input: the map is bound while fighting")
	local att = Mock.BoundActions.NimbusBattleAttack
	T.check(att and att.priority == Enum.ContextActionPriority.High.Value, "p5 input: bound at High priority", att and tostring(att.priority) or "nil")
	local function hasKey(action, key)
		local a = Mock.BoundActions[action]
		for _, k in ipairs(a and a.inputs or {}) do
			if typeof(k) == "EnumItem" and k.Name == key then
				return true
			end
		end
		return false
	end
	T.check(hasKey("NimbusBattleAttack", "F") and hasKey("NimbusBattleAttack", "ButtonX") and hasKey("NimbusBattleElement", "E") and hasKey("NimbusBattleElement", "ButtonY")
		and hasKey("NimbusBattleSpecial", "Q") and hasKey("NimbusBattleSpecial", "ButtonR1") and hasKey("NimbusBattleTarget", "Tab") and hasKey("NimbusBattleTarget", "T")
		and hasKey("NimbusBattleHelper", "One") and hasKey("NimbusBattleHelper", "Two") and hasKey("NimbusBattleHelper", "ButtonL1") and hasKey("NimbusBattleHelper", "DPadLeft"),
		"p5 input: F/X attack, E/Y element, Q/RB special, Tab/T lock, 1/2/LB/D-pad helpers")
	-- MovementController: Shift dashes, free dash, the battle speeds from Start.Team.Speed
	local team = d:team()
	if MC and type(MC.GetSpeedState) == "function" then
		local st = MC.GetSpeedState()
		local shiftDash = false
		for _, k in ipairs(st.DashKeys or {}) do
			if k.Name == "LeftShift" then
				shiftDash = true
			end
		end
		T.check(shiftDash and st.FreeDash == true, "p5 input: SetDashKeys (Shift dashes) + SetFreeDash(true) on Start", tostring(shiftDash) .. " " .. tostring(st.FreeDash))
		T.check(st.Walk and abs(st.Walk - team.Speed.Walk) < 0.01 and abs(st.Run - team.Speed.Run) < 0.01, "p5 input: SetBattleSpeed(walk, run) from Start.Team.Speed",
			tostring(st.Walk) .. " / " .. tostring(st.Run))
		T.eq(st.ExhaustResume, 22, "p5 input: EXHAUST_RESUME is 22 (15% of 150)")
		T.check(hasKey("NimbusDash", "LeftShift") and not hasKey("NimbusRun", "LeftShift") and hasKey("NimbusRun", "LeftControl"), "p5 input: Shift = DASH in battle, RUN moves to Ctrl")
		if hum then
			Mock.Step(1 / 30)
			T.check(abs(hum.WalkSpeed - team.Speed.Walk) < 0.05, "p5 input: the character walks at the battle walk", H.fmt(hum.WalkSpeed))
			-- a Speed event (Haste) moves it
			KC.toClient("BattleState", "Events", { { type = "Speed", owner = LocalPlayer.UserId, walk = 19.5, run = 25.35 } }, d.id)
			Mock.Step(1 / 30)
			st = MC.GetSpeedState()
			T.check(abs(st.Walk - 19.5) < 0.01 and abs(st.RunTarget - 25.35) < 0.01 and abs(hum.WalkSpeed - 19.5) < 0.05, "p5 input: a Speed event = SetBattleSpeed (walk written, run target)", H.fmt(hum.WalkSpeed))
			-- the server freezes the character (0): its 0 wins
			hum.WalkSpeed = 0
			H.step(3, 1 / 30)
			T.eq(hum.WalkSpeed, 0, "p5 input: a server WalkSpeed of 0 still wins")
			hum.WalkSpeed = 16
			H.step(3, 1 / 30)
			T.check(abs(hum.WalkSpeed - 19.5) < 0.05, "p5 input: ... and the battle walk comes back after it", H.fmt(hum.WalkSpeed))
		end
	else
		T.fail("p5 input: MovementController.GetSpeedState missing")
	end
	-- hold-to-attack at the fighter's interval
	local idx = #Mock.RemoteLog
	Mock.TriggerAction("NimbusBattleAttack", "Begin", Mock.NewInput("F", "Keyboard", "Begin"))
	d.noForward = true
	H.step(75, 1 / 30) -- 2.5 s held
	local held = H.count(idx, "Attack")
	Mock.TriggerAction("NimbusBattleAttack", "End", Mock.NewInput("F", "Keyboard", "End"))
	local BCat = H.moduleAt("shared", "BattleCatalog")
	local fu = d:unit(team.Fighter)
	local us = BCat and BCat.UnitStats(fu.petId, fu.level, fu.tier, {})
	local interval = us and us.Interval or 1
	local want = floor(2.5 / max(0.2, interval)) + 1
	T.check(held >= want - 1 and held <= want + 1, "p5 input: a held ATTACK repeats at the fighter's interval (" .. H.fmt(interval) .. " s)", held .. " sent, ~" .. want .. " expected")
	local idx2 = #Mock.RemoteLog
	H.step(30, 1 / 30)
	T.eq(H.count(idx2, "Attack"), 0, "p5 input: releasing ATTACK stops the repeat")
	d.noForward = false
	d.logIndex = #Mock.RemoteLog
	-- helper keys: a tap = Buff, held 0.5 s = Swap
	local bench = team.Bench
	local slotA = d:unit(bench[1]).slot
	H.step(10, 0.05)
	idx = #Mock.RemoteLog
	Mock.TriggerAction("NimbusBattleHelper", "Begin", Mock.NewInput("Two", "Keyboard", "Begin"))
	H.step(3, 1 / 30)
	Mock.TriggerAction("NimbusBattleHelper", "End", Mock.NewInput("Two", "Keyboard", "End"))
	local cmds = H.commands(idx)
	local slotB = d:unit(bench[2]).slot
	T.check(#cmds == 1 and cmds[1].action == "Buff" and cmds[1].arg == slotB, "p5 input: tapping 2 sends helper B's Buff", #cmds > 0 and (cmds[1].action .. " " .. tostring(cmds[1].arg)) or "none")
	idx = #Mock.RemoteLog
	Mock.TriggerAction("NimbusBattleHelper", "Begin", Mock.NewInput("One", "Keyboard", "Begin"))
	H.step(20, 1 / 30) -- 0.66 s
	cmds = H.commands(idx)
	T.check(#cmds == 1 and cmds[1].action == "Swap" and cmds[1].arg == slotA, "p5 input: holding 1 for 0.5 s swaps helper A in", #cmds > 0 and (cmds[1].action .. " " .. tostring(cmds[1].arg)) or "none")
	Mock.TriggerAction("NimbusBattleHelper", "End", Mock.NewInput("One", "Keyboard", "End"))
	T.eq(#H.commands(idx), 1, "p5 input: ... and releasing it sends no Buff")
	d:run(0.5, 30)
	T.eq(BC.GetBattle().FighterId, bench[1], "p5 input: the Swap event makes helper A the fighter")
	-- Tab cycles the lock (nearest first), T clears
	local f = d:unit(BC.GetBattle().FighterId)
	local list = {}
	for _, id in ipairs(d:enemyIds()) do
		local e = d:unit(id)
		list[#list + 1] = { id = id, d = (e.x - f.x) ^ 2 + (e.z - f.z) ^ 2 }
	end
	table.sort(list, function(a, c)
		if a.d ~= c.d then
			return a.d < c.d
		end
		return a.id < c.id
	end)
	idx = #Mock.RemoteLog
	Mock.TriggerAction("NimbusBattleTarget", "Begin", Mock.NewInput("Tab", "Keyboard", "Begin"))
	cmds = H.commands(idx)
	T.check(#cmds == 1 and cmds[1].action == "Target" and list[1] and cmds[1].arg == list[1].id, "p5 input: Tab locks the nearest enemy", #cmds > 0 and tostring(cmds[1].arg) or "none")
	d:step(30)
	H.step(8, 1 / 30)
	idx = #Mock.RemoteLog
	Mock.TriggerAction("NimbusBattleTarget", "Begin", Mock.NewInput("Tab", "Keyboard", "Begin"))
	cmds = H.commands(idx)
	T.check(#cmds == 1 and cmds[1].action == "Target" and list[2] and cmds[1].arg == list[2].id, "p5 input: Tab again locks the next one", #cmds > 0 and tostring(cmds[1].arg) or "none")
	d:step(30)
	H.step(8, 1 / 30)
	idx = #Mock.RemoteLog
	Mock.TriggerAction("NimbusBattleTarget", "Begin", Mock.NewInput("T", "Keyboard", "Begin"))
	cmds = H.commands(idx)
	T.check(#cmds == 1 and cmds[1].action == "Target" and cmds[1].arg == nil, "p5 input: T clears the lock")
	d:run(0.3, 30)
	T.check(BC.GetBattle().Lock == nil, "p5 input: ... the echo confirms no lock")
	-- predictions: ELEMENT's ring starts at once; the event confirms
	d:run(0.5, 30)
	idx = #Mock.RemoteLog
	Mock.TriggerAction("NimbusBattleElement", "Begin", Mock.NewInput("E", "Keyboard", "Begin"))
	local b = BC.GetBattle()
	T.check(#H.commands(idx) == 1 and b.Pending.Element == true and b.Cooldowns.Element > 6, "p5 input: E sends Element and its ring starts at once (prediction)", H.fmt(b.Cooldowns.Element))
	d:run(0.3, 30)
	b = BC.GetBattle()
	T.check(b.Pending.Element == nil and b.Cooldowns.Element > 5, "p5 input: the Element event confirms the prediction")
	-- a refused press while the ring runs is held back locally (no traffic) and shakes the button
	local btn = H.find("Root.Commands.ElementButton")
	local shakes0 = btn and (btn:GetAttribute("Shakes") or 0) or 0
	idx = #Mock.RemoteLog
	Mock.TriggerAction("NimbusBattleElement", "Begin", Mock.NewInput("E", "Keyboard", "Begin"))
	T.check(#H.commands(idx) == 0 and btn and (btn:GetAttribute("Shakes") or 0) > shakes0, "p5 input: E during the cooldown is not sent and shakes ELEMENT")
	-- a rejected Order (owner-only) puts the predicted ring back and shakes the button
	H.step(10, 0.05)
	local dashBtn = H.find("Root.Commands.DashButton")
	local dShakes = dashBtn and (dashBtn:GetAttribute("Shakes") or 0) or 0
	d.noForward = true
	T.check(BC.Command("Dash") == true and BC.GetBattle().Pending.Dash == true and BC.GetBattle().Cooldowns.Dash > 2, "p5 input: DASH predicted")
	KC.toClient("BattleState", "Events", { { type = "Order", owner = LocalPlayer.UserId, order = "Dash", rejected = "Stunned" } }, d.id)
	Mock.Step(1 / 30)
	b = BC.GetBattle()
	T.check(b.Pending.Dash == nil and b.Cooldowns.Dash < 0.01 and dashBtn and (dashBtn:GetAttribute("Shakes") or 0) > dShakes, "p5 input: a rejected Order resets DASH's ring and shakes it",
		H.fmt(b.Cooldowns.Dash) .. " s")
	-- the timeout: no event within 0.6 s
	H.step(10, 0.05)
	local shakes1, timeouts1 = BC.GetStats().Shakes, BC.GetStats().Timeouts
	BC.Command("Dash")
	b = BC.GetBattle()
	local predicted = b.Pending.Dash == true
	H.step(25, 1 / 30) -- 0.83 s, nothing forwarded
	b = BC.GetBattle()
	T.check(predicted and b.Pending.Dash == nil and b.Cooldowns.Dash < 0.01 and BC.GetStats().Timeouts > timeouts1 and BC.GetStats().Shakes > shakes1, "p5 input: an unconfirmed prediction times out (ring back, shake)",
		"pending " .. tostring(predicted) .. ", timeouts " .. BC.GetStats().Timeouts)
	d.noForward = false
	d.logIndex = #Mock.RemoteLog
	-- inert before PLAY on the main menu (UiGate.HasPlayed)
	BC.Hooks.Gate = function()
		return false
	end
	idx = #Mock.RemoteLog
	H.step(10, 0.05)
	local r1 = Mock.TriggerAction("NimbusBattleAttack", "Begin", Mock.NewInput("F", "Keyboard", "Begin"))
	Mock.TriggerAction("NimbusBattleAttack", "End", Mock.NewInput("F", "Keyboard", "End"))
	T.check(#H.commands(idx) == 0 and r1 == Enum.ContextActionResult.Pass, "p5 input: the keys are inert (passed through) before UiGate.HasPlayed()")
	BC.Hooks.Gate = nil
	-- the end: everything released, MovementController back to the obby
	d:finish({ Mode = "Dungeon", Outcome = "Win", Won = true, Spectator = false, Reason = "Cleared", Rewards = { Dungeon = true } })
	H.step(3, 0.05)
	T.eq(bound(), 0, "p5 input: the map is released at the end")
	if MC and type(MC.GetSpeedState) == "function" then
		local st = MC.GetSpeedState()
		T.check(st.DashKeys == nil and st.FreeDash == false and st.Walk == nil, "p5 input: End resets SetDashKeys(nil) / SetFreeDash(false) / SetBattleSpeed(nil)")
		T.check(hasKey("NimbusDash", "Q") and hasKey("NimbusRun", "LeftShift"), "p5 input: ... Q dashes and Shift runs again")
		if hum then
			Mock.Step(1 / 30)
			T.check(abs(hum.WalkSpeed - 16) < 0.05, "p5 input: ... and the server's base speed is back", H.fmt(hum.WalkSpeed))
		end
	end
	H.cleanup(BC, d)
	T.check(H.warnings(out0) == nil and #Mock.Errors == err0, "p5 input: no BattleController errors or warnings", tostring(H.warnings(out0)))
	KC.flushErrors("client_p5input")
end)

----------------------------------------------------------------------------------------------------
-- client_p5models
----------------------------------------------------------------------------------------------------
S.client_p5models = guarded("client_p5models", function()
	local BC = H.load()
	if not BC then
		return
	end
	local out0, err0 = #Mock.Output, #Mock.Errors
	local d = H.dungeon(2, false)
	if not T.check(d ~= nil, "p5 models: driver") then
		return
	end
	local root = Mock.GetRoot(LocalPlayer)
	H.begin(d)
	d:run(0.6, 30)
	local team = d:team()
	local fid = team.Fighter
	local simF = d:unit(fid)
	local server = d.zoneCF:PointToWorldSpace(Vector3.new(simF.x, 0, simF.z))
	if root then
		-- my character stands where the server fighter is: the pet floats at my shoulder
		root.CFrame = CFrame.new(server + Vector3.new(0, 3, 0))
		H.step(30, 1 / 30)
		local info = BC.GetUnit(fid)
		local shoulder = root.CFrame:PointToWorldSpace(Vector3.new(1.8, 0.5, 0.6))
		local gap = info and info.Drawn and (info.Drawn - shoulder).Magnitude or 999
		T.check(gap < 1.2, "p5 models: my fighter floats at my character's shoulder (1.8, 0.5, 0.6)", H.fmt(gap) .. " studs")
		-- my character runs 12 studs off: the drawn pet follows the SERVER position, not me
		root.CFrame = CFrame.new(server + Vector3.new(12, 3, 0))
		H.step(30, 1 / 30)
		info = BC.GetUnit(fid)
		local toServer = info and info.Drawn and Vector3.new(info.Drawn.X - server.X, 0, info.Drawn.Z - server.Z).Magnitude or 999
		T.check(toServer < 3.5, "p5 models: beyond 2 studs the drawn fighter follows the server position (what looks in reach is in reach)", H.fmt(toServer) .. " studs from it")
		root.CFrame = CFrame.new(server + Vector3.new(0, 3, 0))
		H.step(20, 1 / 30)
		-- helpers behind me
		local hinfo = BC.GetUnit(team.Bench[1])
		local spotA = root.CFrame:PointToWorldSpace(Vector3.new(-2, 1.2, 2))
		local hgap = hinfo and hinfo.Drawn and (hinfo.Drawn - spotA).Magnitude or 999
		T.check(hgap < 1.5, "p5 models: helper A hovers behind me at (-2, 1.2, 2)", H.fmt(hgap) .. " studs")
		T.check(hinfo and hinfo.Detail == "Low" and BC.GetUnit(fid).Detail == "High", "p5 models: my fighter High, my helpers Low",
			tostring(BC.GetUnit(fid).Detail) .. " / " .. tostring(hinfo and hinfo.Detail))
	else
		T.info("p5 models: no character in this world (the shoulder checks were skipped)")
	end
	-- a Buff: the helper flies to the fighter and back
	d:run(0.3, 30)
	local idx = #Mock.RemoteLog
	BC.Command("Buff", d:unit(team.Bench[1]).slot)
	d:run(0.4, 30)
	local hinfo = BC.GetUnit(team.Bench[1])
	T.check(hinfo and hinfo.FlyAt ~= nil, "p5 models: a Buff sends the helper flying to the fighter", #H.commands(idx) .. " sent")
	d:run(1.0, 30)
	T.check(BC.GetUnit(team.Bench[1]).FlyAt == nil, "p5 models: ... and back within 0.6 s")
	-- a Swap: the two trade places; the new fighter is rebuilt High
	d:run(0.5, 30)
	BC.Command("Swap", d:unit(team.Bench[2]).slot)
	d:run(0.3, 30)
	local newF = BC.GetBattle().FighterId
	T.eq(newF, team.Bench[2], "p5 models: the Swap event makes helper B my fighter")
	T.check(BC.GetUnit(newF) and BC.GetUnit(fid) and (BC.GetUnit(newF).SwapAt ~= nil or BC.GetUnit(fid).SwapAt ~= nil), "p5 models: ... the two trade places (an animated swap)")
	d:run(1.0, 30)
	T.eq(BC.GetUnit(newF).Detail, "High", "p5 models: the new fighter is rebuilt at High detail")
	-- the Winding crouch + its yellow flash (the dash cue)
	local enemy = d:enemyIds()[1]
	local flashes = 0
	d:step(30, function(snap)
		-- white-box on the wire: set the windup bit on the enemy's code
		local U = snap.U
		local i = 1
		while i + 1 <= #U do
			local code = U[i]
			if floor(code / 1024) == enemy and floor(code / 128) % 2 == 0 then
				U[i] = code + 128
			end
			local mask = floor(code / 8) % 16
			local extra = 0
			for _, bit in ipairs({ 1, 2, 4, 8 }) do
				if mask % (bit * 2) >= bit then
					extra = extra + 1
				end
			end
			i = i + 2 + extra
		end
		if not d.markedEnemy then
			-- (a quiet unit sends nothing: force a full record of it)
			d.markedEnemy = true
		end
	end)
	H.step(4, 1 / 30)
	flashes = BC.GetStats().Flashes
	local einfo = BC.GetUnit(enemy)
	T.check(einfo and einfo.Windup == true, "p5 models: a winding enemy crouches (the snapshot's windup bit)")
	T.check(flashes >= 1, "p5 models: ... with a brief yellow highlight", flashes .. " flashes")
	-- DODGED! on a missed hit
	KC.toClient("BattleState", "Events", { { type = "Hit", from = enemy, to = newF, dmg = 0, miss = true } }, d.id)
	d:run(0.4, 30)
	local sawDodged = false
	local fx = workspace:FindFirstChild("ClientBattle") and workspace.ClientBattle:FindFirstChild("Fx")
	for _, g in ipairs(fx and fx:GetDescendants() or {}) do
		if g:IsA("TextLabel") and g.Text == "DODGED!" then
			sawDodged = true
		end
	end
	T.check(sawDodged, "p5 models: a dodged hit shows DODGED! above my fighter")
	-- PetCard lives pips on my fighter's card
	local card = BC.GetUnit(newF).Card
	local pips = card and card.Gui and card.Gui:FindFirstChild("Lives", true)
	T.check(pips and pips.Visible and #pips:GetChildren() >= 3, "p5 models: my fighter's card shows the lives pips (PetCard:SetLives)")
	-- the camera shake follows the Shake setting
	local shakes = BC.GetStats().CameraShakes
	BC.Hooks.Shake = function()
		return false
	end
	KC.toClient("BattleState", "Events", { { type = "KO", unit = newF } }, d.id)
	d:run(0.4, 30)
	local hum = Mock.GetHumanoid(LocalPlayer)
	T.check(BC.GetStats().CameraShakes > shakes and (not hum or hum.CameraOffset.Magnitude < 0.001), "p5 models: with Shake off a KO does not move the camera")
	BC.Hooks.Shake = function()
		return true
	end
	local hit = { type = "Hit", from = enemy, to = d:team().Fighter, dmg = 9999 }
	KC.toClient("BattleState", "Events", { hit }, d.id)
	local moved = false
	for _ = 1, 12 do
		d:step(30)
		if hum and hum.CameraOffset.Magnitude > 0.001 then
			moved = true
		end
	end
	T.check(moved or not hum, "p5 models: with Shake on a hard hit shakes the camera (Humanoid.CameraOffset)")
	H.step(20, 1 / 30)
	T.check(not hum or hum.CameraOffset.Magnitude < 0.001, "p5 models: ... and settles back to 0")
	BC.Hooks.Shake = nil
	H.cleanup(BC, d)
	T.check(H.warnings(out0) == nil and #Mock.Errors == err0, "p5 models: no BattleController errors or warnings", tostring(H.warnings(out0)))
	KC.flushErrors("client_p5models")
end)

----------------------------------------------------------------------------------------------------
-- client_p5result
----------------------------------------------------------------------------------------------------
S.client_p5result = guarded("client_p5result", function()
	local BC = H.load()
	if not BC then
		return
	end
	local out0, err0 = #Mock.Output, #Mock.Errors
	-- a cleared room: no result card (the dungeon's loot card)
	local d = H.dungeon(2, false)
	if not T.check(d ~= nil, "p5 result: driver") then
		return
	end
	H.begin(d)
	d:finish({ Mode = "Dungeon", Outcome = "Win", Won = true, Spectator = false, Reason = "Cleared", Rewards = { Dungeon = true, Extra = { Floor = 3, Room = 2 } } })
	H.step(10, 0.05)
	T.check(not H.shown(H.find("Root.ResultCard")) and not H.shown(H.find("Root.Commands")), "p5 result: a cleared dungeon room shows no result card (DungeonController's loot card)")
	H.cleanup(BC, d)
	-- a wipe in the dungeon: KNOCKED OUT + Floor / Room + Lives left
	d = H.dungeon(2, false)
	H.begin(d)
	d:finish({ Mode = "Dungeon", Outcome = "Loss", Won = false, Spectator = false, Reason = "Wipe", Rewards = { Dungeon = true, Extra = { Floor = 3, Room = 2, Name = "Ember Hall" } } })
	H.step(4, 0.05)
	local res = H.find("Root.ResultCard")
	T.check(H.shown(res) and H.hasText(res, "KNOCKED OUT") and H.hasText(res, "Floor 3 - Room 2") and H.hasText(res, "Lives left"), "p5 result: a dungeon wipe: KNOCKED OUT, Floor 3 - Room 2, Lives left")
	H.cleanup(BC, d)
	-- a duel win: VICTORY, rewards, Lives left 3, bottom right
	local dd = H.driver({ Mode = "Duel", Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = H.team(3, 0, 12) }, { Owner = 78, Side = 2, Pets = H.team(3, 3, 12) } } })
	if T.check(dd ~= nil, "p5 result: duel driver") then
		H.begin(dd)
		T.check(H.hasText(H.find("Root.TopCard"), "DUEL - vs Rival"), "p5 result: the duel's mode line names the rival")
		dd:finish({ Mode = "Duel", Outcome = "Win", Won = true, Spectator = false, Reason = "KO", Rewards = { Tokens = 60, Trophies = 25, Xp = 50 } })
		H.step(4, 0.05)
		res = H.find("Root.ResultCard")
		T.check(H.shown(res) and H.hasText(res, "VICTORY") and H.hasText(res, "+60 Tokens") and H.hasText(res, "Lives left: 3"), "p5 result: VICTORY with the rewards and Lives left: 3")
		T.check(res and res.AnchorPoint.X == 1 and res.AnchorPoint.Y == 1, "p5 result: bottom right on a wide screen (never centred)")
		H.cleanup(BC, dd)
	end
	T.check(not BC.IsHudVisible() and BC.GetBattle() == nil, "p5 result: everything freed afterwards")
	T.check(H.warnings(out0) == nil and #Mock.Errors == err0, "p5 result: no BattleController errors or warnings", tostring(H.warnings(out0)))
	KC.flushErrors("client_p5result")
end)

----------------------------------------------------------------------------------------------------
-- phone world: the compact HUD at 390x844 / 740x360 / 844x390
----------------------------------------------------------------------------------------------------
function H.bootPhone()
	local main = Mock.GetPath(ROOTS["client"] .. "/Main")
	if main and not (LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("NimbusHud")) then
		local Config = H.moduleAt("shared", "Config")
		local RS = game:GetService("ReplicatedStorage")
		if Config and not RS:FindFirstChild("Remotes") then
			local folder = Instance.new("Folder")
			folder.Name = "Remotes"
			for _, n in ipairs(Config.Remotes) do
				local r = Instance.new("RemoteEvent")
				r.Name = n
				r.Parent = folder
			end
			folder.Parent = RS
		end
		Mock.RunScript(main)
		Mock.Advance(8)
	end
end

-- the HUD checks of one screen size (label: the size)
function H.phoneChecks(BC, label)
	local vp = Mock.Viewport
	local W, Hh = vp.X, vp.Y
	local b = BC.GetBattle()
	T.check(b and b.Layout == "Compact", label .. ": the compact layout", b and b.Layout or "nil")
	-- nothing in the centre 40% of the width (between the top strip and the bottom strip)
	local box = { x0 = W * 0.3, x1 = W * 0.7, y0 = Hh * (W > Hh and 0.35 or 0.3), y1 = Hh * (W > Hh and 0.75 or 0.7) }
	local bad = nil
	local root = H.find("Root")
	for _, o in ipairs(root and root:GetDescendants() or {}) do
		if o:IsA("GuiObject") and H.shown(o) and o.BackgroundTransparency < 1 or (o:IsA("TextLabel") and H.shown(o) and o.Text ~= "") then
			local r = H.rect(o)
			if r.x1 - r.x0 > 2 and H.overlap(r, box) then
				bad = o:GetFullName():gsub("^Players%.[^.]+%.PlayerGui%.", "") .. " " .. H.rectText(r)
				break
			end
		end
	end
	local where = ""
	if bad then
		-- (what pushed the right column down: the currency pills' place, the top card's place)
		local pg = LocalPlayer:FindFirstChild("PlayerGui")
		local cur = pg and pg:FindFirstChild("NimbusHud") and pg.NimbusHud:FindFirstChild("Currency", true)
		if cur then
			where = " | Currency " .. H.rectText(H.rect(cur)) .. " " .. tostring(cur.Visible)
		end
		local top = H.find("Root.TopCard")
		if top then
			where = where .. " | TopCard " .. H.rectText(H.rect(top))
		end
	end
	T.check(bad == nil, label .. ": nothing of the HUD in the centre 40% of the width", tostring(bad) .. where)
	-- the action buttons: >= 60 design px, on the screen
	local small = nil
	for _, kind in ipairs({ "Attack", "Element", "Special", "Dash" }) do
		local btn = H.find("Root.Commands." .. kind .. "Button")
		if not (btn and H.shown(btn)) then
			small = kind .. " missing"
		else
			local r = H.rect(btn)
			if btn.Size.X.Offset < 60 or r.x0 < 0 or r.x1 > W + 1 or r.y0 < 0 or r.y1 > Hh + 1 then
				small = kind .. " " .. btn.Size.X.Offset .. " " .. H.rectText(r)
			end
		end
	end
	T.check(small == nil, label .. ": ATTACK / ELEMENT / SPECIAL / DASH >= 60 design px and on the screen", tostring(small))
	-- every text >= 14 px on the screen
	local scale = H.find("Root.ReadScale")
	local f = scale and scale.Scale or 1
	local tiny = nil
	for _, t in ipairs(H.texts(H.gui())) do
		if t.TextSize * f < 13.99 then
			tiny = t:GetFullName() .. " " .. H.fmt(t.TextSize * f)
		end
	end
	T.check(tiny == nil, label .. ": every battle text >= 14 px on the screen", tostring(tiny))
	-- the menu column steps aside while fighting
	T.check(b and b.MenuHidden == true, label .. ": the menu column is hidden while fighting")
	-- no HUD part over another GUI's button (RUN, menu, hotbar, vitals...)
	local mine = {}
	for _, path in ipairs({ "Root.Team.Fighter", "Root.Team.Helpers", "Root.Enemies", "Root.TopCard", "Root.Commands.AttackButton", "Root.Commands.ElementButton", "Root.Commands.SpecialButton", "Root.Commands.DashButton" }) do
		local o = H.find(path)
		if o and H.shown(o) then
			mine[#mine + 1] = { path, H.rect(o) }
		end
	end
	local clash = nil
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	for _, g in ipairs(pg and pg:GetChildren() or {}) do
		if g:IsA("ScreenGui") and g.Name ~= "NimbusBattle" and g.Enabled then
			for _, o in ipairs(g:GetDescendants()) do
				if o:IsA("GuiButton") and H.shown(o) and o.AbsoluteSize.X > 20 and o.AbsoluteSize.X < 300 then
					local r = H.rect(o)
					for _, m in ipairs(mine) do
						if H.overlap(r, m[2]) then
							clash = m[1] .. " over " .. o:GetFullName()
						end
					end
				end
			end
		end
	end
	T.check(clash == nil, label .. ": the battle HUD covers no other button (RUN / DASH, menu, hotbar)", tostring(clash))
end

function H.phoneRun(BC, sizes, scenario)
	H.bootPhone()
	local out0, err0 = #Mock.Output, #Mock.Errors
	for _, sz in ipairs(sizes) do
		Mock.SetViewport(sz[1], sz[2])
		H.step(3, 0.1)
		local d = H.dungeon(4, true)
		if not T.check(d ~= nil, scenario .. ": driver") then
			return
		end
		H.begin(d)
		d:run(0.8, 30)
		H.phoneChecks(BC, sz[1] .. "x" .. sz[2])
		H.cleanup(BC, d)
	end
	Mock.SetViewport(390, 844)
	H.step(3, 0.1)
	T.check(H.warnings(out0) == nil and #Mock.Errors == err0, scenario .. ": no BattleController errors or warnings", tostring(H.warnings(out0)))
	KC.flushErrors(scenario)
end

S.client_p5battle_mobile = guarded("client_p5battle_mobile", function()
	local BC = H.load()
	if BC then
		H.phoneRun(BC, { { 390, 844 } }, "client_p5battle_mobile")
	end
end)

S.client_p5battle_landscape = guarded("client_p5battle_landscape", function()
	local BC = H.load()
	if BC then
		H.phoneRun(BC, { { 740, 360 }, { 844, 390 } }, "client_p5battle_landscape")
	end
end)

return S
