-- smoke_p3_battleclient.lua: Phase 3 BattleController (client/Controllers/BattleController.lua) + the PetController
-- follower hiding. Loaded by tools/smoke.py in the client worlds (desktop 1920x1080 and the 390x844 touch phone).
-- A real BattleSim (shared/BattleSim.lua) is stepped at 10 Hz here and its Start / Events / Snapshot / End reach the
-- client through the BattleState remote exactly the way BattleService sends them (dense snapshot arrays, the battle id
-- as the third argument); the client's BattleCommand calls are forwarded into the sim (Order events come back).
--   client_p3battle_trial     the module + API, followers parked while InBattle and back afterwards, the HUD only
--                             while fighting (top card, one row per team pet, ATTACK / RETREAT), unit models built
--                             within a few frames, intact (static parts welded at the built pose: nothing left at the
--                             origin), smooth interpolation at 60 fps between 10 Hz snapshots (no frame jumps),
--                             damage numbers as pixel-sized world billboards (never a screen-centre text), F / R / 1-4
--                             through ContextActionService (only while fighting), the local throttle, the regroup lock
--                             after RETREAT, SPECIAL only with a full meter (key, button), focus by enemy chip and by a
--                             tap on an enemy in the world (a real perspective camera; a drag or an empty tap does
--                             nothing), Forfeit, the result card at the end (bottom right, rewards, OK, closes by
--                             itself), models freed after the end, no errors
--   client_p3battle_raid      the boss (BossBuilder) on the floor, telegraphs that fill up and vanish after the hit,
--                             the boss HP bar / ENRAGED / minions in the top card, minion waves and a leaving team,
--                             effect caps (pooled parts, numbers), the measured frame cost, BOSS DEFEATED card
--   client_p3battle_spectate  a duel watched from the stands: models but no controls / keys / commands, the slim
--                             WATCHING card, "End" OutOfRange frees everything at once; junk messages are ignored
--   client_p3battle_cards     (Phase 4, 3.9) a PetCard above every unit: own "Unit" (Lv >= 22 px + HP + SPECIAL + XP =
--                             xp / xpNext, full at the cap 100), enemies "Enemy" (Lv + HP only), evolved units built
--                             evolved within petEvoLow / petEvo2Low with their stars, no card write between snapshots
--                             and far fewer writes than frames, HP fill = hp / maxHp, a full meter fills SPECIAL,
--                             End.Rewards.Xp moves the XP bar, every card freed with the battle
--   client_p3battle_ring      (Phase 4, 3.8) a Champion Ring run: CHAMPION RING - Round 1 - Best 12 + the win pay pill,
--                             the crowned champion (gold voxel crown, 22 px tag), a won round's side card (no result
--                             card, Round 2 in 3 counting down, top card + team kept, commands gone, off the centre),
--                             the next Start in the same pocket keeps my pets' models, the old floor freed by battle id,
--                             the run's result card (RUN OVER, Rounds won, Cash, XP, Best), a record run ended between
--                             rounds (RECORD x3 pill, NEW RECORD!), the BOSS pill on round 20, duel OVERTIME
--   client_p3battle_ring_mobile (phone world) unit card Lv >= 14 px, the side card readable, off the centre and clear of
--                             the top / team cards at 390x844 and 844x390, the run's card off the centre
--   client_p3battle_mobile    (phone world) the compact HUD: touch-sized ATTACK / RETREAT, every battle text >= 14 px on
--                             the screen, nothing over the RUN / DASH buttons or in the screen centre, a tap on a team
--                             card casts its special
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local KC = _G.KC
local S = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local abs, floor, max, min, sqrt = math.abs, math.floor, math.max, math.min, math.sqrt

local function fmt(v, n)
	if type(v) ~= "number" then
		return tostring(v)
	end
	return string.format("%." .. (n or 2) .. "f", v)
end

local function moduleAt(top, rest)
	local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	return ok and type(result) == "table" and result or nil
end

local function step(n, dt)
	for _ = 1, n or 1 do
		Mock.Step(dt)
	end
end

local function battleGui()
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	return pg and pg:FindFirstChild("NimbusBattle")
end

local function shown(obj)
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

local function find(path)
	local cur = battleGui()
	for name in string.gmatch(path, "[^%.]+") do
		if not cur then
			return nil
		end
		cur = cur:FindFirstChild(name)
	end
	return cur
end

local function shownTexts(root)
	local out = {}
	if not root then
		return out
	end
	for _, d in ipairs(root:GetDescendants()) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and shown(d) and tostring(d.Text) ~= "" then
			out[#out + 1] = d
		end
	end
	return out
end

local function hasText(root, pattern)
	for _, d in ipairs(shownTexts(root)) do
		if tostring(d.Text):gsub("<[^>]*>", ""):find(pattern) then
			return true, d
		end
	end
	return false
end

local function commandsSince(index)
	local out = {}
	for _, e in ipairs(KC.serverCalls("BattleCommand", index)) do
		out[#out + 1] = { action = e.args[1], arg = e.args[2] }
	end
	return out
end

local function battleWarnings(fromIndex)
	for i = fromIndex + 1, #Mock.Output do
		local o = Mock.Output[i]
		if o.kind == "warn" and o.text:find("BattleController", 1, true) then
			return o.text
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- a real perspective camera for the mock (its own camera projects every point to the screen centre)
----------------------------------------------------------------------------------------------------
local camMethods = Mock.Classes and Mock.Classes.Camera and Mock.Classes.Camera.methods
local savedProject = nil

local function project(self, pos)
	local rel = self.CFrame:PointToObjectSpace(pos)
	local vp = Mock.Viewport
	local depth = -rel.Z
	local f = (vp.Y / 2) / math.tan(math.rad(self.FieldOfView / 2))
	local d = depth
	if abs(d) < 1e-6 then
		d = 1e-6
	end
	local x = vp.X / 2 + rel.X / d * f
	local y = vp.Y / 2 - rel.Y / d * f
	return Vector3.new(x, y, depth), depth > 0 and x >= 0 and x <= vp.X and y >= 0 and y <= vp.Y
end

local function installProjection()
	if camMethods and not savedProject then
		savedProject = { camMethods.WorldToViewportPoint, camMethods.WorldToScreenPoint }
		camMethods.WorldToViewportPoint = project
		camMethods.WorldToScreenPoint = project
	end
	return camMethods ~= nil
end

local function removeProjection()
	if camMethods and savedProject then
		camMethods.WorldToViewportPoint = savedProject[1]
		camMethods.WorldToScreenPoint = savedProject[2]
		savedProject = nil
	end
end

----------------------------------------------------------------------------------------------------
-- the battle driver: a real BattleSim sent the way BattleService sends it
----------------------------------------------------------------------------------------------------
local function catalogTeam(count, skip, level)
	local PC = moduleAt("shared", "PetCatalog")
	local out, kinds = {}, {}
	skip = skip or 0
	for _, def in ipairs(PC and PC.Pets or {}) do
		local sp = type(def.Special) == "table" and def.Special.Kind or nil
		if sp and def.Role == "Combat" and not kinds[sp] and def.Rarity ~= "Secret" and not def.EventOnly then
			if skip > 0 then
				skip = skip - 1
			else
				kinds[sp] = true
				out[#out + 1] = { Key = def.Id, PetId = def.Id, Level = level or 10, Tier = "Normal", Slot = #out + 1 }
				if #out >= count then
					break
				end
			end
		end
	end
	return out
end

local Driver = {}
Driver.__index = Driver

-- opts: Mode, Teams, Trial, Boss, Side (the local player's side; 0 = spectator), Specials, ZoneCF
local function newDriver(opts)
	local Sim = moduleAt("shared", "BattleSim")
	if not Sim then
		return nil, "shared/BattleSim.lua missing"
	end
	local id = "smoke_" .. tostring(opts.Mode) .. "_" .. tostring(math.random(100000, 999999))
	local sim, why = Sim.new({ Mode = opts.Mode, Seed = opts.Seed or 3, Id = id, Teams = opts.Teams, Trial = opts.Trial, Boss = opts.Boss, Specials = opts.Specials,
		Round = opts.Round, Zone = opts.Zone, TimeLimit = opts.TimeLimit })
	if not sim then
		return nil, why
	end
	local d = setmetatable({ sim = sim, id = id, zoneCF = opts.ZoneCF or CFrame.new(0, 200, 0), side = opts.Side or 1, logIndex = #Mock.RemoteLog, events = {}, stepped = 0, ring = opts.Ring }, Driver)
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
	p.Ring = self.ring -- Phase 4: BattleService's "Start".Ring for a Champion Ring round
	return p
end

function Driver:start()
	KC.toClient("BattleState", "Start", self:startPayload(), self.id)
end

function Driver:snapshot()
	local snap = self.sim:Snapshot()
	snap.BattleId = self.id
	local units, top = {}, 0
	for k in pairs(snap.Units) do
		if k > top then
			top = k
		end
	end
	for k = 1, top do
		units[k] = snap.Units[k] or { x = 0, z = 0, hp = 0, state = 5, meter = 0 }
	end
	snap.Units = units
	return snap
end

-- forwards the client's BattleCommand calls into the sim (like BattleService.Command)
function Driver:forward()
	if self.side == 0 then
		self.logIndex = #Mock.RemoteLog
		return
	end
	for _, c in ipairs(commandsSince(self.logIndex)) do
		pcall(self.sim.Command, self.sim, self.me, c.action, c.arg)
	end
	self.logIndex = #Mock.RemoteLog
end

-- one 0.1 s server step at `fps` client frames per second
function Driver:step(fps)
	self:forward()
	local evs = self.sim:Step(0.1)
	self.stepped = self.stepped + 1
	if #evs > 0 then
		for _, e in ipairs(evs) do
			self.events[#self.events + 1] = e
		end
		KC.toClient("BattleState", "Events", evs, self.id)
	end
	KC.toClient("BattleState", "Snapshot", self:snapshot(), self.id)
	local frames = max(1, floor((fps or 30) * 0.1 + 0.5))
	step(frames, 0.1 / frames)
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

function Driver:myUnits()
	local out = {}
	for _, u in ipairs(self.sim.units or {}) do
		if u.owner == self.me then
			out[#out + 1] = u
		end
	end
	return out
end

function Driver:enemyIds()
	local out = {}
	for _, u in ipairs(self.sim.units or {}) do
		if u.side ~= 1 and u.alive and not u.gone then
			out[#out + 1] = u.id
		end
	end
	return out
end

local function followerFolder()
	local root = workspace:FindFirstChild("ClientPets")
	return root and root:FindFirstChild(tostring(LocalPlayer.UserId))
end

-- the parts of a unit model that are far from its root (an unwelded / mis-welded model leaves parts behind)
local function strayParts(model, maxDist)
	local root = model.PrimaryPart or model:FindFirstChild("Body")
	if not root then
		return -1
	end
	local n = 0
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "ShieldCube" and p.Name ~= "Crystal" and (p.Position - root.Position).Magnitude > maxDist then
			n = n + 1
		end
	end
	return n
end

----------------------------------------------------------------------------------------------------
-- scenario: a full trial on the desktop
----------------------------------------------------------------------------------------------------
-- Phase 4 test helpers: the PetCard above a unit (its billboard keeps the Phase 3 name HpBar)
local function cardOf(BC, id)
	local info = BC.GetUnit(id)
	local gui = info and info.Card and info.Card.Gui
	return gui, info
end

local function rowShown(gui, name)
	local f = gui and gui:FindFirstChild("Plate") and gui.Plate:FindFirstChild(name)
	return f ~= nil and f.Visible == true
end

local function fillOf(gui, name)
	local f = gui and gui:FindFirstChild("Plate") and gui.Plate:FindFirstChild(name)
	local fill = f and f:FindFirstChild("Fill")
	return fill and fill.Size.X.Scale or nil
end

local function levelText(gui)
	local l = gui and gui:FindFirstChild("Plate") and gui.Plate:FindFirstChild("Level")
	return l and l.Text or nil, l
end

S.client_p3battle_trial = guarded("client_p3battle_trial", function()
	local Config = KC.env()
	local BC = moduleAt("client", "Controllers/BattleController")
	T.check(BC ~= nil, "BattleController: client/Controllers/BattleController.lua loads")
	if not BC then
		return
	end
	for _, fn in ipairs({ "Init", "Stop", "HandleState", "Command", "Focus", "GetBattle", "GetUnit", "GetStats", "IsHudVisible", "ScreenPick" }) do
		T.check(type(BC[fn]) == "function", "BattleController." .. fn .. " exists")
	end
	local outBefore, errBefore = #Mock.Output, #Mock.Errors
	KC.advance(0.5)
	T.check(BC.GetBattle() == nil and not BC.IsHudVisible(), "BattleController: no battle and no battle HUD in the lobby")
	T.check(not shown(find("Root.Team")) and not shown(find("Root.Commands")), "BattleController: battle controls hidden outside a battle")
	T.check(Mock.BoundActions.NimbusBattleSpecial == nil and Mock.BoundActions.NimbusBattleAttack == nil, "BattleController: keys F / R / 1-4 are not bound outside a battle (the hotbar keeps 1-4)")

	-- a follower to hide
	local PC = moduleAt("shared", "PetCatalog")
	local firstPet = PC and PC.Pets and PC.Pets[1] and PC.Pets[1].Id
	if firstPet then
		LocalPlayer:SetAttribute(Config.Attr.EquippedPets, firstPet)
	end
	KC.advance(1.5)
	local ff = followerFolder()
	T.check(ff ~= nil and ff.Parent ~= nil, "PetController: the local follower is shown before the battle", tostring(ff))

	local d, why = newDriver({ Mode = "Trial", Trial = 3, Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = catalogTeam(3) } }, Specials = false })
	T.check(d ~= nil, "battle driver: BattleSim trial created", tostring(why))
	if not d then
		return
	end
	LocalPlayer:SetAttribute("InBattle", d.id)
	BC.PerfClock = Mock.RealClock -- the mock's os.clock is the fake game clock: measure real time
	BC.ResetStats()
	d:start()
	d:step(30)
	d:step(30)
	local b = BC.GetBattle()
	T.check(b ~= nil and b.Fighter and b.Mode == "Trial" and b.Id == d.id, "BattleController: Start draws the trial as a fighter", b and (tostring(b.Mode) .. " " .. tostring(b.Fighter)) or "nil")
	T.check(BC.IsHudVisible(), "BattleController: the battle HUD shows while fighting")
	T.check(shown(find("Root.TopCard")) and hasText(find("Root.TopCard"), "TRIAL 3"), "battle HUD: the top card names the trial")
	local rows = 0
	for i = 1, 4 do
		if shown(find("Root.Team.Row" .. i)) then
			rows = rows + 1
		end
	end
	T.eq(rows, 3, "battle HUD: one row per team pet")
	T.check(shown(find("Root.Commands.AttackButton")) and shown(find("Root.Commands.RetreatButton")), "battle HUD: ATTACK and RETREAT buttons")
	T.check(hasText(find("Root.Team"), "SPECIAL") or hasText(find("Root.Team"), "%%"), "battle HUD: every row has its SPECIAL button / meter")
	T.check(Mock.BoundActions.NimbusBattleSpecial ~= nil and Mock.BoundActions.NimbusBattleAttack ~= nil and Mock.BoundActions.NimbusBattleRetreat ~= nil, "BattleController: F / R / 1-4 bound while fighting")
	ff = followerFolder()
	T.check(ff == nil or ff.Parent == nil, "PetController: the follower is parked while InBattle (the team fights on the floor)")

	-- models: built within a few frames, intact
	d:run(1.0, 30)
	b = BC.GetBattle()
	T.check(b.Models == b.Units and b.Units == #d.sim.units, "BattleController: every unit has a model within a second", b.Models .. "/" .. b.Units)
	local stray, welded = 0, 0
	for _, u in ipairs(d.sim.units) do
		local info = BC.GetUnit(u.id)
		if info and info.Model then
			stray = stray + max(0, strayParts(info.Model, 12))
			for _, w in ipairs(info.Model:GetDescendants()) do
				if w:IsA("Weld") then
					welded = welded + 1
					break
				end
			end
		end
	end
	T.eq(stray, 0, "BattleController: unit models are intact (no part left behind at the built pose)")
	T.check(welded == #d.sim.units, "BattleController: static parts welded to the root (a pose is one CFrame write)", welded .. "/" .. #d.sim.units)
	-- position: the drawn unit is where the sim says (zone-local x / z on the zone CFrame)
	local u1 = d.sim.units[1]
	local info1 = BC.GetUnit(u1.id)
	local want = d.zoneCF:PointToWorldSpace(Vector3.new(u1.x, 0, u1.z))
	local got = info1 and info1.Model and (info1.Model.PrimaryPart or info1.Model:FindFirstChild("Body")).Position
	local flat = got and Vector3.new(got.X - want.X, 0, got.Z - want.Z).Magnitude or 999
	T.check(flat < 4, "BattleController: a unit is drawn at its zone-local snapshot position (within the interpolation lag)", fmt(flat) .. " studs")
	T.check(got ~= nil and got.Y > want.Y + 0.5 and got.Y < want.Y + 6, "BattleController: pets hover just above the floor", got and fmt(got.Y - want.Y) or "nil")

	-- smoothness: 60 fps frames between 10 Hz snapshots, no jumps
	local maxJump, worst = 0, ""
	local last = {}
	for _ = 1, 20 do
		d:forward()
		local evs = d.sim:Step(0.1)
		if #evs > 0 then
			KC.toClient("BattleState", "Events", evs, d.id)
		end
		KC.toClient("BattleState", "Snapshot", d:snapshot(), d.id)
		for _ = 1, 6 do
			Mock.Step(1 / 60)
			for _, u in ipairs(d.sim.units) do
				local inf = BC.GetUnit(u.id)
				local m = inf and inf.Model
				local r = m and not inf.Parked and (m.PrimaryPart or m:FindFirstChild("Body"))
				if r then
					local p = r.Position
					local prev = last[u.id]
					if prev then
						local jump = Vector3.new(p.X - prev.X, 0, p.Z - prev.Z).Magnitude
						if jump > maxJump then
							maxJump, worst = jump, u.name
						end
					end
					last[u.id] = p
				else
					last[u.id] = nil
				end
			end
		end
	end
	T.check(maxJump < 1.4, "BattleController: smooth interpolation at 60 fps (largest per-frame step)", fmt(maxJump) .. " studs (" .. worst .. ")")

	-- numbers: world billboards in pixels, never a screen-centre text
	local sawNumber, badNumber = false, nil
	d:run(2.0, 30, function()
		local fx = workspace:FindFirstChild("ClientBattle") and workspace.ClientBattle:FindFirstChild("Fx")
		for _, g in ipairs(fx and fx:GetChildren() or {}) do
			if g:IsA("BillboardGui") and g.Enabled then
				sawNumber = true
				local lbl = g:FindFirstChildWhichIsA("TextLabel")
				if g.Size.X.Scale ~= 0 or g.Size.Y.Scale ~= 0 or not lbl or lbl.TextSize < 22 or g.LightInfluence ~= 0 then
					badNumber = g.Name .. " " .. tostring(lbl and lbl.TextSize)
				end
			end
		end
	end)
	T.check(sawNumber, "BattleController: hits show floating damage numbers")
	T.check(badNumber == nil, "BattleController: damage numbers are pixel-sized world billboards (>= 22 px, LightInfluence 0)", tostring(badNumber))
	local centred = {}
	for _, c in ipairs(KC.centredTexts(0.12)) do
		if c.path:find("NimbusBattle", 1, true) then
			centred[#centred + 1] = c
		end
	end
	T.check(#centred == 0, "battle HUD: nothing in the screen centre", KC.describeCentred(centred))

	-- commands: keys through ContextActionService, throttle, regroup lock, specials
	local idx = #Mock.RemoteLog
	d.logIndex = idx
	Mock.TriggerAction("NimbusBattleAttack", "Begin", Mock.NewInput("F", "Keyboard", "Begin"))
	local cmds = commandsSince(idx)
	T.check(#cmds == 1 and cmds[1].action == "Attack" and cmds[1].arg == nil, "controls: F sends BattleCommand Attack", #cmds .. " calls")
	Mock.TriggerAction("NimbusBattleAttack", "Begin", Mock.NewInput("F", "Keyboard", "Begin"))
	T.eq(#commandsSince(idx), 1, "controls: a second ATTACK within the throttle is not sent")
	d:step(30)
	idx = #Mock.RemoteLog
	Mock.TriggerAction("NimbusBattleRetreat", "Begin", Mock.NewInput("R", "Keyboard", "Begin"))
	cmds = commandsSince(idx)
	T.check(#cmds == 1 and cmds[1].action == "Retreat", "controls: R sends BattleCommand Retreat")
	d:step(30)
	d:step(30)
	b = BC.GetBattle()
	T.eq(b.Order, "Retreat", "controls: the Order event confirms the retreat")
	local attackBtn = find("Root.Commands.AttackButton")
	T.check(attackBtn and tostring(attackBtn.Text):find("ATTACK %d") ~= nil and attackBtn:GetAttribute("Disabled") == true, "battle HUD: ATTACK shows the regroup countdown after RETREAT", attackBtn and attackBtn.Text or "nil")
	idx = #Mock.RemoteLog
	Mock.TriggerAction("NimbusBattleAttack", "Begin", Mock.NewInput("F", "Keyboard", "Begin"))
	T.eq(#commandsSince(idx), 0, "controls: ATTACK is held back during the regroup lock")
	d:run(1.6, 30)
	idx = #Mock.RemoteLog
	Mock.TriggerAction("NimbusBattleAttack", "Begin", Mock.NewInput("F", "Keyboard", "Begin"))
	T.eq(#commandsSince(idx), 1, "controls: ATTACK works again after the lock")
	-- special: refused while charging, sent with a full meter (key 1 and the button)
	for _, u in ipairs(d:myUnits()) do
		u.meter = 10
	end
	d:step(30)
	d:step(30)
	idx = #Mock.RemoteLog
	Mock.TriggerAction("NimbusBattleSpecial", "Begin", Mock.NewInput("One", "Keyboard", "Begin"))
	T.eq(#commandsSince(idx), 0, "controls: SPECIAL is not sent while the meter charges")
	local mine = d:myUnits()
	for _, u in ipairs(mine) do
		u.meter = 100
	end
	d.sim.specialsEnabled = true
	d:step(30)
	d:step(30)
	local row1 = find("Root.Team.Row1.Special")
	T.check(row1 and hasText(row1, "SPECIAL"), "battle HUD: a full meter lights the SPECIAL button", row1 and tostring((row1:FindFirstChild("Top") or {}).Text) or "nil")
	idx = #Mock.RemoteLog
	Mock.TriggerAction("NimbusBattleSpecial", "Begin", Mock.NewInput("One", "Keyboard", "Begin"))
	cmds = commandsSince(idx)
	T.check(#cmds == 1 and cmds[1].action == "Special" and cmds[1].arg == 1, "controls: key 1 sends BattleCommand Special 1", #cmds > 0 and (tostring(cmds[1].action) .. " " .. tostring(cmds[1].arg)) or "none")
	local row2 = find("Root.Team.Row2.Special")
	idx = #Mock.RemoteLog
	if row2 then
		Mock.Click(row2)
	end
	cmds = commandsSince(idx)
	T.check(#cmds == 1 and cmds[1].action == "Special" and cmds[1].arg == mine[2].slot, "controls: the SPECIAL button of row 2 sends Special 2")
	Mock.TriggerAction("NimbusBattleSpecial", "Begin", Mock.NewInput("ButtonR1", "Gamepad1", "Begin"))
	d:step(30)

	-- focus: an enemy chip, then a tap on an enemy in the world
	local enemies = d:enemyIds()
	local chip = find("Root.TopCard.Enemy1")
	idx = #Mock.RemoteLog
	if chip then
		Mock.Click(chip)
	end
	cmds = commandsSince(idx)
	T.check(#cmds == 1 and cmds[1].action == "Attack" and type(cmds[1].arg) == "number", "controls: clicking an enemy chip focuses it (Attack with its unit id)")
	d:run(0.4, 30)
	b = BC.GetBattle()
	T.check(b.Focus ~= nil, "controls: the Order event sets the focus (the arrow marks it)", tostring(b.Focus))
	if installProjection() then
		local cam = workspace.CurrentCamera
		local target = BC.GetUnit(enemies[#enemies])
		if cam and target and target.World then
			local center = d.zoneCF.Position
			cam.CFrame = CFrame.lookAt(center + Vector3.new(0, 30, -45), center)
			local p = select(1, cam:WorldToViewportPoint(target.World))
			local inset = Mock.TopInset or 36
			local picked = BC.ScreenPick(p.X, p.Y)
			T.eq(picked, target.Id, "controls: ScreenPick finds the enemy under the tap")
			Mock.Step(0.3) -- past the command throttle
			idx = #Mock.RemoteLog
			local touchPos = Vector3.new(p.X, p.Y - inset, 0)
			Mock.FireSignal(UserInputService, "InputBegan", Mock.NewInput("Unknown", "Touch", "Begin", { Position = touchPos }), false)
			Mock.Step(0.05)
			Mock.FireSignal(UserInputService, "InputEnded", Mock.NewInput("Unknown", "Touch", "End", { Position = touchPos }), false)
			cmds = commandsSince(idx)
			T.check(#cmds == 1 and cmds[1].action == "Attack" and cmds[1].arg == target.Id, "controls: a tap on an enemy in the world focuses it", #cmds > 0 and tostring(cmds[1].arg) or "none")
			Mock.Step(0.3)
			idx = #Mock.RemoteLog
			Mock.FireSignal(UserInputService, "InputBegan", Mock.NewInput("Unknown", "Touch", "Begin", { Position = touchPos }), false)
			Mock.Step(0.05)
			Mock.FireSignal(UserInputService, "InputEnded", Mock.NewInput("Unknown", "Touch", "End", { Position = touchPos + Vector3.new(60, 0, 0) }), false)
			T.eq(#commandsSince(idx), 0, "controls: a camera drag does not focus anything")
			idx = #Mock.RemoteLog
			local empty = Vector3.new(4, 4, 0)
			Mock.FireSignal(UserInputService, "InputBegan", Mock.NewInput("Unknown", "MouseButton1", "Begin", { Position = empty }), false)
			Mock.Step(0.05)
			Mock.FireSignal(UserInputService, "InputEnded", Mock.NewInput("Unknown", "MouseButton1", "End", { Position = empty }), false)
			T.eq(#commandsSince(idx), 0, "controls: a click on empty space sends nothing")
		else
			T.fail("controls: tap focus test could not set up the camera / target")
		end
		removeProjection()
	end
	idx = #Mock.RemoteLog
	T.check(BC.Command("Forfeit") == true and commandsSince(idx)[1] and commandsSince(idx)[1].action == "Forfeit", "controls: Forfeit is sent")
	d.logIndex = #Mock.RemoteLog -- (not forwarded: the trial goes on)
	T.check(BC.Command("Bogus") == false and BC.Command("Special", 9) == false, "controls: unknown actions / slots are refused locally")
	local stats = BC.GetStats()
	T.check(T.finite(stats.AvgMs) and stats.Frames > 0 and stats.AvgMs > 0, "BattleController: frame cost measured", fmt(stats.AvgMs) .. " ms avg, " .. fmt(stats.PeakMs) .. " ms peak over " .. stats.Frames .. " frames (lupa mock)")
	T.info("BattleController trial frame cost (mock)", fmt(stats.AvgMs) .. " ms avg / " .. fmt(stats.PeakMs) .. " ms peak, " .. stats.Units .. " units")

	-- the end: result card, controls gone, models freed, follower back
	d:finish({ Mode = "Trial", Outcome = "Win", Won = true, Spectator = false, Reason = "Wipe", Rewards = { Tokens = 150, Gems = 10, Xp = 90, Trophies = 0, LevelUps = 1, FirstClear = true, Level = 3 } })
	step(2)
	local result = find("Root.ResultCard")
	T.check(shown(result) and hasText(result, "VICTORY") and hasText(result, "150 Tokens") and hasText(result, "First clear"), "result card: VICTORY with the rewards")
	T.check(result and result.AnchorPoint.X == 1 and result.AnchorPoint.Y == 1, "result card: bottom right on a wide screen (never centred)")
	T.check(not shown(find("Root.Commands")) and not shown(find("Root.Team")), "result card: the controls are gone at the end")
	T.check(Mock.BoundActions.NimbusBattleSpecial == nil and Mock.BoundActions.NimbusBattleAttack == nil, "BattleController: F / R / 1-4 released at the end")
	LocalPlayer:SetAttribute("InBattle", nil)
	KC.advance(4)
	T.check(BC.GetBattle() == nil, "BattleController: the battle is freed after the end linger")
	local cb = workspace:FindFirstChild("ClientBattle")
	local left = 0
	for _, c in ipairs(cb and cb:GetChildren() or {}) do
		if c.Name:find("^Battle_") then
			left = left + 1
		end
	end
	T.eq(left, 0, "BattleController: no battle models left behind")
	ff = followerFolder()
	T.check(ff ~= nil and ff.Parent ~= nil, "PetController: the follower is back after the battle")
	local ok = find("Root.ResultCard.OkButton")
	if ok then
		Mock.Click(ok)
	end
	step(2)
	T.check(not shown(find("Root.ResultCard")) and not BC.IsHudVisible(), "result card: OK closes it")
	T.check(battleWarnings(outBefore) == nil and #Mock.Errors == errBefore, "BattleController: no errors or warnings (trial)", tostring(battleWarnings(outBefore)))
	KC.flushErrors("client_p3battle_trial")
end)

----------------------------------------------------------------------------------------------------
-- scenario: a boss raid
----------------------------------------------------------------------------------------------------
S.client_p3battle_raid = guarded("client_p3battle_raid", function()
	local BC = moduleAt("client", "Controllers/BattleController")
	if not BC then
		T.fail("BattleController missing")
		return
	end
	local outBefore, errBefore = #Mock.Output, #Mock.Errors
	BC.PerfClock = Mock.RealClock
	BC.ResetStats()
	local d, why = newDriver({
		Mode = "Raid",
		Boss = "storm_titan",
		Teams = {
			{ Owner = LocalPlayer.UserId, Side = 1, Pets = catalogTeam(4) },
			{ Owner = 77, Side = 1, Pets = catalogTeam(3, 2) },
		},
	})
	T.check(d ~= nil, "battle driver: raid created", tostring(why))
	if not d then
		return
	end
	LocalPlayer:SetAttribute("InBattle", d.id)
	-- where the frame time goes: the model animators (PetBuilder / BossBuilder) timed apart from the controller
	local PB, BBm = moduleAt("shared", "PetBuilder"), moduleAt("shared", "BossBuilder")
	local spent = { Pet = 0, Boss = 0 }
	local origPet, origBoss = PB and PB.Animate, BBm and BBm.Animate
	if origPet then
		PB.Animate = function(...)
			local t0 = Mock.RealClock()
			origPet(...)
			spent.Pet = spent.Pet + (Mock.RealClock() - t0)
		end
	end
	if origBoss then
		BBm.Animate = function(...)
			local t0 = Mock.RealClock()
			origBoss(...)
			spent.Boss = spent.Boss + (Mock.RealClock() - t0)
		end
	end
	d:start()
	local sawTele, fills, teleGone = false, {}, false
	local resetAt = 30 -- steps: the steady-state cost is measured once every model is built
	d:run(11, 30, function()
		resetAt = resetAt - 1
		if resetAt == 0 then
			BC.ResetStats()
			spent.Pet, spent.Boss = 0, 0
		end
		local n = BC.GetStats().Telegraphs
		if n > 0 then
			sawTele = true
			local fx = workspace.ClientBattle:FindFirstChild("Fx")
			local biggest = 0
			for _, p in ipairs(fx and fx:GetChildren() or {}) do
				if p:IsA("BasePart") and p.Shape == Enum.PartType.Cylinder and p.Transparency < 0.5 then
					biggest = max(biggest, p.Size.Y)
				end
			end
			fills[#fills + 1] = biggest
		elseif sawTele then
			teleGone = true
		end
	end)
	local b = BC.GetBattle()
	T.check(b and b.Mode == "Raid" and b.Fighter, "raid: drawn as a fighter")
	local bossModel = nil
	for _, u in ipairs(d.sim.units) do
		if u.kind == "Boss" then
			local inf = BC.GetUnit(u.id)
			bossModel = inf and inf.Model
		end
	end
	T.check(bossModel ~= nil and bossModel.Name:find("Boss_") ~= nil, "raid: the boss is a BossBuilder model on the floor", bossModel and bossModel.Name or "nil")
	T.check(sawTele, "raid: boss telegraphs are drawn on the floor")
	local peak = 0
	for _, v in ipairs(fills) do
		peak = max(peak, v)
	end
	local grows = #fills >= 3 and peak > fills[1] + 0.5
	T.check(grows, "raid: a telegraph fills up before the hit", #fills > 0 and (fmt(fills[1]) .. " -> " .. fmt(peak) .. " studs") or "no samples")
	T.check(teleGone, "raid: a telegraph vanishes after its hit")
	T.check(hasText(find("Root.TopCard"), "Storm Titan") and hasText(find("Root.TopCard"), "BOSS RAID"), "raid HUD: the top card names the boss")
	T.check(shown(find("Root.TopCard.BossHp")), "raid HUD: the boss HP bar")
	T.eq(#(function()
		local n = {}
		for i = 1, 4 do
			if shown(find("Root.Team.Row" .. i)) then
				n[#n + 1] = i
			end
		end
		return n
	end)(), 4, "raid HUD: four team rows (slot 4)")
	-- a minion wave + enrage + a leaving team
	local unitsBefore = BC.GetBattle().Units
	d.sim.boss.hp = d.sim.boss.maxHp * 0.6
	d:run(1.5, 30)
	b = BC.GetBattle()
	T.check(b.Units > unitsBefore, "raid: a minion wave adds units", unitsBefore .. " -> " .. b.Units)
	T.check(hasText(find("Root.TopCard"), "Minions"), "raid HUD: the minion pill")
	KC.toClient("BattleState", "Events", { { type = "Enrage", unit = d.sim.boss.id } }, d.id)
	d:run(0.5, 30)
	T.check(shown(find("Root.TopCard.Pills.Enraged")), "raid HUD: ENRAGED pill after the Enrage event")
	local before = BC.GetBattle().Units
	d.sim:RemoveTeam(77)
	d:run(0.6, 30)
	T.check(BC.GetBattle().Units < before, "raid: a team that leaves is removed from the floor", before .. " -> " .. BC.GetBattle().Units)
	local stats = BC.GetStats()
	if origPet then
		PB.Animate = origPet
	end
	if origBoss then
		BBm.Animate = origBoss
	end
	local frames = max(1, stats.Frames)
	local parts = {}
	for k, v in pairs(stats.Split or {}) do
		parts[#parts + 1] = k .. " " .. fmt(v)
	end
	table.sort(parts)
	T.info("BattleController raid frame cost split (mock)", string.format("PetBuilder.Animate %.2f ms, BossBuilder.Animate %.2f ms per frame; sections (ms/frame, animators included in Units): %s", spent.Pet * 1000 / frames, spent.Boss * 1000 / frames, table.concat(parts, ", ")))
	T.check(stats.FxParts <= 260 and stats.Numbers <= 26 and stats.Flashes <= 8, "raid: effects stay under their caps", stats.FxParts .. " parts, " .. stats.Numbers .. " numbers, " .. stats.Flashes .. " flashes")
	T.info("BattleController raid frame cost (mock)", fmt(stats.AvgMs) .. " ms avg / " .. fmt(stats.PeakMs) .. " ms peak, " .. stats.Units .. " units, " .. stats.Models .. " models")
	d:finish({ Mode = "Raid", Outcome = "Win", Won = true, Spectator = false, Reason = "BossDown", Rewards = { Tokens = 420, Gems = 5, Xp = 180, Trophies = 0, LevelUps = 2, Tier = "Gold", Share = 0.4, Damage = 5000 } })
	step(2)
	T.check(hasText(find("Root.ResultCard"), "BOSS DEFEATED") and hasText(find("Root.ResultCard"), "Gold tier"), "raid: BOSS DEFEATED card with the damage tier")
	LocalPlayer:SetAttribute("InBattle", nil)
	KC.advance(14)
	T.check(BC.GetBattle() == nil and not BC.IsHudVisible(), "raid: freed after the end; the result card closes by itself")
	T.check(battleWarnings(outBefore) == nil and #Mock.Errors == errBefore, "BattleController: no errors or warnings (raid)", tostring(battleWarnings(outBefore)))
	KC.flushErrors("client_p3battle_raid")
end)

----------------------------------------------------------------------------------------------------
-- scenario: watching a duel from the stands + junk messages
----------------------------------------------------------------------------------------------------
S.client_p3battle_spectate = guarded("client_p3battle_spectate", function()
	local BC = moduleAt("client", "Controllers/BattleController")
	if not BC then
		T.fail("BattleController missing")
		return
	end
	local outBefore, errBefore = #Mock.Output, #Mock.Errors
	local d = newDriver({ Mode = "Duel", Side = 0, Teams = { { Owner = 77, Side = 1, Pets = catalogTeam(3) }, { Owner = 78, Side = 2, Pets = catalogTeam(3, 3) } } })
	if not d then
		T.fail("battle driver: duel")
		return
	end
	d:start()
	d:run(1.5, 30)
	local b = BC.GetBattle()
	T.check(b and b.Spectator and not b.Fighter, "spectate: a watched duel is drawn as a spectator")
	T.check(b and b.Models == b.Units, "spectate: both teams are drawn from the stands", b and (b.Models .. "/" .. b.Units) or "nil")
	T.check(not BC.IsHudVisible() and not shown(find("Root.Commands")), "spectate: no battle controls for a spectator")
	T.check(shown(find("Root.TopCard")) and hasText(find("Root.TopCard"), "WATCHING") and hasText(find("Root.TopCard"), "Buddy"), "spectate: the slim WATCHING card names the duellists")
	T.check(Mock.BoundActions.NimbusBattleSpecial == nil, "spectate: no keys bound")
	local idx = #Mock.RemoteLog
	T.check(BC.Command("Attack") == false and BC.Focus(1) == false and #commandsSince(idx) == 0, "spectate: commands are not sent")
	d:finish({ Mode = "Duel", Spectator = true, Reason = "OutOfRange" })
	step(1)
	T.check(BC.GetBattle() == nil, "spectate: End OutOfRange frees the battle at once")
	-- junk
	local okJunk = pcall(function()
		BC.HandleState("Start", nil)
		BC.HandleState("Snapshot", { Units = "x" }, "nope")
		BC.HandleState("Events", { { type = 5 }, "x", { type = "Hit", to = "y" } }, "nope")
		BC.HandleState("End", 7)
		BC.HandleState("Bogus", {})
		BC.HandleState(nil, nil, nil)
	end)
	step(2)
	T.check(okJunk and BC.GetBattle() == nil, "BattleController: junk BattleState messages are ignored")
	-- a lobby status message for the ArenaController is not ours
	KC.toClient("BattleState", "Lobby", { Queue = { Queued = false, Waiting = 0 }, Invites = {} }, nil)
	step(1)
	T.check(BC.GetBattle() == nil, "BattleController: BattleState Lobby is left to the ArenaController")
	T.check(battleWarnings(outBefore) == nil and #Mock.Errors == errBefore, "BattleController: no errors or warnings (spectate)", tostring(battleWarnings(outBefore)))
	KC.flushErrors("client_p3battle_spectate")
end)

----------------------------------------------------------------------------------------------------
-- scenario (phone world): the compact HUD on a 390x844 touch screen
----------------------------------------------------------------------------------------------------
local function screenRect(obj)
	local p, s = obj.AbsolutePosition, obj.AbsoluteSize
	local gui = obj:FindFirstAncestorOfClass("ScreenGui")
	local dy = (gui and gui.IgnoreGuiInset == false) and (Mock.TopInset or 36) or 0
	return { x0 = p.X, y0 = p.Y + dy, x1 = p.X + s.X, y1 = p.Y + s.Y + dy }
end

local function overlap(a, b)
	return a.x0 < b.x1 - 1 and b.x0 < a.x1 - 1 and a.y0 < b.y1 - 1 and b.y0 < a.y1 - 1
end

-- the phone world boots its own client (once)
local function bootPhone()
	-- the phone world boots its own client
	local main = Mock.GetPath(ROOTS["client"] .. "/Main")
	if main and not (LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("NimbusHud")) then
		local Config = moduleAt("shared", "Config")
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

S.client_p3battle_mobile = guarded("client_p3battle_mobile", function()
	local BC = moduleAt("client", "Controllers/BattleController")
	if not BC then
		T.fail("BattleController missing (phone)")
		return
	end
	bootPhone()
	local outBefore, errBefore = #Mock.Output, #Mock.Errors
	local d = newDriver({ Mode = "Trial", Trial = 2, Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = catalogTeam(4) } } })
	if not d then
		T.fail("battle driver: phone trial")
		return
	end
	LocalPlayer:SetAttribute("InBattle", d.id)
	d:start()
	d:run(1.5, 30)
	local b = BC.GetBattle()
	T.check(b and b.Layout == "Compact", "phone: the compact battle HUD", b and b.Layout or "nil")
	local attack, retreat = find("Root.Commands.AttackButton"), find("Root.Commands.RetreatButton")
	local ra, rr = attack and screenRect(attack), retreat and screenRect(retreat)
	T.check(ra and (ra.x1 - ra.x0) >= 56 and (ra.y1 - ra.y0) >= 56 and rr and (rr.x1 - rr.x0) >= 56 and (rr.y1 - rr.y0) >= 56, "phone: ATTACK / RETREAT are touch-sized (>= 56 px)", ra and (fmt(ra.x1 - ra.x0, 0) .. "x" .. fmt(ra.y1 - ra.y0, 0)) or "nil")
	-- every battle text >= 14 px on the screen
	local scale = find("Root.ReadScale")
	local f = scale and scale.Scale or 1
	local small = nil
	for _, t in ipairs(shownTexts(battleGui())) do
		if t.TextSize * f < 13.99 then
			small = t:GetFullName() .. " " .. fmt(t.TextSize * f)
		end
	end
	T.check(small == nil, "phone: every battle HUD text is >= 14 px on the screen", tostring(small))
	-- nothing over the RUN / DASH buttons, the vitals card or the menu column
	local mine = {}
	for _, path in ipairs({ "Root.TopCard", "Root.Commands.AttackButton", "Root.Commands.RetreatButton" }) do
		local o = find(path)
		if o and shown(o) then
			mine[#mine + 1] = { path, screenRect(o) }
		end
	end
	for i = 1, 4 do
		local o = find("Root.Team.Row" .. i)
		if o and shown(o) then
			mine[#mine + 1] = { "Row" .. i, screenRect(o) }
		end
	end
	local clash = nil
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	for _, g in ipairs(pg and pg:GetChildren() or {}) do
		if g:IsA("ScreenGui") and g.Name ~= "NimbusBattle" and g.Enabled then
			for _, o in ipairs(g:GetDescendants()) do
				if o:IsA("GuiButton") and shown(o) and o.AbsoluteSize.X > 20 and o.AbsoluteSize.X < 300 then
					local r = screenRect(o)
					for _, m in ipairs(mine) do
						if overlap(r, m[2]) then
							clash = m[1] .. " over " .. o:GetFullName()
						end
					end
				end
			end
		end
	end
	T.check(clash == nil, "phone: the battle HUD covers no other button (RUN / DASH, menu, hotbar)", tostring(clash))
	local centred = {}
	for _, c in ipairs(KC.centredTexts(0.1)) do
		if c.path:find("NimbusBattle", 1, true) then
			centred[#centred + 1] = c
		end
	end
	T.check(#centred == 0, "phone: nothing of the battle HUD in the screen centre", KC.describeCentred(centred))
	-- a tap on a team card casts its special
	for _, u in ipairs(d:myUnits()) do
		u.meter = 100
	end
	d:step(30)
	d:step(30)
	local card = find("Root.Team.Row1.CardHit")
	local idx = #Mock.RemoteLog
	if card then
		Mock.Click(card)
	end
	local cmds = commandsSince(idx)
	T.check(#cmds == 1 and cmds[1].action == "Special" and cmds[1].arg == 1, "phone: tapping a team card casts its special")
	d:finish({ Mode = "Trial", Outcome = "Loss", Won = false, Spectator = false, Reason = "Wipe", Rewards = { Tokens = 0, Gems = 0, Xp = 0, Trophies = 0, LevelUps = 0, Level = 2 } })
	step(2)
	local res = find("Root.ResultCard")
	T.check(shown(res) and hasText(res, "DEFEAT") and res.AnchorPoint.Y == 0, "phone: the DEFEAT card sits at the top (not centred)")
	-- turned sideways (844x390): the short screen puts the card top right, clear of the screen centre
	Mock.SetViewport(844, 390)
	step(2)
	res = find("Root.ResultCard")
	if res and shown(res) then
		local r = screenRect(res)
		local cx, cy = 844 / 2, 390 / 2
		local covers = r.x0 <= cx and cx <= r.x1 and r.y0 <= cy and cy <= r.y1
		T.check(res.AnchorPoint.X == 1 and not covers, "phone landscape: the result card moves top right, off the screen centre", fmt(r.x0) .. "," .. fmt(r.y0) .. " - " .. fmt(r.x1) .. "," .. fmt(r.y1))
	else
		T.fail("phone landscape: the result card disappeared on rotation")
	end
	Mock.SetViewport(390, 844)
	step(2)
	LocalPlayer:SetAttribute("InBattle", nil)
	KC.advance(14)
	T.check(BC.GetBattle() == nil and not BC.IsHudVisible(), "phone: everything freed afterwards")
	T.check(battleWarnings(outBefore) == nil and #Mock.Errors == errBefore, "BattleController: no errors or warnings (phone)", tostring(battleWarnings(outBefore)))
	KC.flushErrors("client_p3battle_mobile")
end)

----------------------------------------------------------------------------------------------------
-- Phase 4 (ARCHITECTURE_V3.md "Phase 4 build contract" 3.5 / 3.8 / 3.9 / 8.2): unit cards and the Champion Ring
----------------------------------------------------------------------------------------------------
-- an Epic-or-rarer Combat pet (it may evolve twice)
local function epicPet()
	local PC = moduleAt("shared", "PetCatalog")
	for _, def in ipairs(PC and PC.Pets or {}) do
		if def.Role == "Combat" and not def.EventOnly and (def.Rarity == "Epic" or def.Rarity == "Legendary" or def.Rarity == "Mythic") then
			return def.Id
		end
	end
	return nil
end

local function partCount(model)
	local n = 0
	for _, p in ipairs(model and model:GetDescendants() or {}) do
		if p:IsA("BasePart") then
			n = n + 1
		end
	end
	return n
end

local function cardWrites(BC, ids)
	local n = 0
	for _, id in ipairs(ids) do
		local info = BC.GetUnit(id)
		n = n + (info and info.Writes or 0)
	end
	return n
end

S.client_p3battle_cards = guarded("client_p3battle_cards", function()
	local BC = moduleAt("client", "Controllers/BattleController")
	local TC = moduleAt("shared", "TycoonCatalog")
	local PetCard = moduleAt("client", "UI/PetCard")
	if not BC or not TC or not PetCard then
		T.fail("BattleController / TycoonCatalog / PetCard missing")
		return
	end
	local outBefore, errBefore = #Mock.Output, #Mock.Errors
	local cardsBefore = PetCard.Count()
	local budgets = (CONTRACT and CONTRACT.v3 and CONTRACT.v3.partBudget) or {}
	local need20 = TC.XpToNext(20)
	local team = catalogTeam(2, 0, 20)
	team[1].Xp, team[1].XpNext = 1000, need20 -- a level-20 pet a little into its bar
	team[2].Level, team[2].Evo, team[2].Xp = 100, 1, 0 -- at the cap (100): the server leaves XpNext out
	local epic = epicPet()
	if epic then
		team[3] = { Key = epic, PetId = epic, Level = 55, Tier = "Normal", Slot = 3, Evo = 2, Xp = 500, XpNext = TC.XpToNext(55) }
	end
	local d = newDriver({ Mode = "Trial", Trial = 5, Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = team } }, Specials = false })
	if not T.check(d ~= nil, "cards: battle driver (trial 5)") then
		return
	end
	LocalPlayer:SetAttribute("InBattle", d.id)
	d:start()
	d:run(1.0, 30)
	local mineIds, enemyIds, bySlot = {}, {}, {}
	for _, u in ipairs(d.sim.units) do
		if u.owner == LocalPlayer.UserId then
			mineIds[#mineIds + 1] = u.id
			bySlot[u.slot] = u
		else
			enemyIds[#enemyIds + 1] = u.id
		end
	end
	-- own units: level + HP + SPECIAL + XP, pixel-sized, readable
	local bad = nil
	for _, id in ipairs(mineIds) do
		local gui, info = cardOf(BC, id)
		local text, lvl = levelText(gui)
		if not gui then
			bad = "no card on unit " .. id
		elseif gui.Name ~= "HpBar" or info.Card.Mode ~= "Unit" then
			bad = "unit " .. id .. ": " .. gui.Name .. " / " .. tostring(info.Card.Mode)
		elseif not (rowShown(gui, "Hp") and rowShown(gui, "Special") and rowShown(gui, "Xp")) then
			bad = "unit " .. id .. ": rows hidden"
		elseif text ~= "Lv " .. tostring(info.Level) then
			bad = "unit " .. id .. ": " .. tostring(text)
		elseif gui.LightInfluence ~= 0 or gui.Size.X.Scale ~= 0 or gui.Size.Y.Scale ~= 0 or not gui.AlwaysOnTop then
			bad = "unit " .. id .. ": not a pixel billboard"
		elseif not lvl or lvl.TextSize < 22 then
			bad = "unit " .. id .. ": Lv " .. tostring(lvl and lvl.TextSize) .. " px"
		end
	end
	T.check(#mineIds >= 2 and bad == nil, "cards: every own unit carries a PetCard (HpBar, mode Unit: Lv n >= 22 px + HP + SPECIAL + XP, pixel-sized, LightInfluence 0)", tostring(bad))
	local g1 = cardOf(BC, bySlot[1] and bySlot[1].id)
	local g2 = cardOf(BC, bySlot[2] and bySlot[2].id)
	T.near(fillOf(g1, "Xp") or -1, 1000 / need20, 0.01, "cards: the XP fill is xp / xpNext from Start (level 20)")
	T.near(fillOf(g2, "Xp") or -1, 1, 0.001, "cards: a pet at the level cap (100, no xpNext) shows a full XP bar")
	-- enemies: level + HP only
	bad = nil
	for _, id in ipairs(enemyIds) do
		local gui, info = cardOf(BC, id)
		local su = nil
		for _, u in ipairs(d.sim.units) do
			if u.id == id then
				su = u
			end
		end
		if not gui or info.Card.Mode ~= "Enemy" then
			bad = "enemy " .. id .. ": " .. tostring(info and info.Card and info.Card.Mode)
		elseif not rowShown(gui, "Hp") or rowShown(gui, "Special") or rowShown(gui, "Xp") then
			bad = "enemy " .. id .. ": rows"
		elseif su and levelText(gui) ~= "Lv " .. tostring(su.level) then
			bad = "enemy " .. id .. ": " .. tostring(levelText(gui))
		end
	end
	T.check(#enemyIds > 0 and bad == nil, "cards: every enemy carries a PetCard (mode Enemy: Lv n + HP, no SPECIAL / XP)", tostring(bad))
	-- evolved units: PetBuilder opts.Evolved at Low detail within the budgets, stars on the card
	local u2 = bySlot[2] and BC.GetUnit(bySlot[2].id)
	local stars2 = g2 and g2:FindFirstChild("StarBadge")
	T.check(u2 and u2.Evo == 1 and u2.Model and u2.Model:GetAttribute("BC_Evo") == 1 and partCount(u2.Model) <= (budgets.petEvoLow or 380) and stars2 and stars2.Visible,
		"cards: an evolved unit is built evolved (Low, <= petEvoLow parts) with a star on its card", u2 and (tostring(u2.Evo) .. " / " .. partCount(u2.Model) .. " parts") or "nil")
	if epic then
		local u3 = bySlot[3] and BC.GetUnit(bySlot[3].id)
		local g3 = bySlot[3] and cardOf(BC, bySlot[3].id)
		local st = g3 and g3:FindFirstChild("StarBadge")
		T.check(u3 and u3.Evo == 2 and partCount(u3.Model) <= (budgets.petEvo2Low or 520) and st and st.Visible and tostring(st.Stars.Text) == "\226\152\133\226\152\133",
			"cards: a second-evolution unit (Epic+) uses Evolved = 2 within petEvo2Low and shows two stars", u3 and (tostring(u3.Evo) .. " / " .. partCount(u3.Model) .. " parts") or "nil")
	end
	-- fills written only on change: 60 frames without a new snapshot write nothing; a fight writes far less than once per frame
	local all = {}
	for _, id in ipairs(mineIds) do
		all[#all + 1] = id
	end
	for _, id in ipairs(enemyIds) do
		all[#all + 1] = id
	end
	local w0 = cardWrites(BC, all)
	local hp0 = fillOf(g1, "Hp")
	step(60, 1 / 60)
	T.eq(cardWrites(BC, all) - w0, 0, "cards: no card write while the snapshots do not change (never per frame)")
	T.check(fillOf(g1, "Hp") == hp0, "cards: the HP fill is untouched between snapshots")
	w0 = cardWrites(BC, all)
	local frames = 0
	for _ = 1, 20 do
		d:forward()
		local evs = d.sim:Step(0.1)
		if #evs > 0 then
			KC.toClient("BattleState", "Events", evs, d.id)
		end
		KC.toClient("BattleState", "Snapshot", d:snapshot(), d.id)
		step(6, 0.1 / 6)
		frames = frames + 6
	end
	local writes = cardWrites(BC, all) - w0
	T.check(writes <= 2 * 20 * #all and writes < frames * #all / 2, "cards: HP / SPECIAL writes follow the 10 Hz snapshots, not the 60 fps frames", writes .. " writes, " .. frames .. " frames x " .. #all .. " units")
	-- the HP fill matches the drawn HP; a full meter fills the SPECIAL row
	local worst = 0
	for _, id in ipairs(all) do
		local gui, info = cardOf(BC, id)
		local f = fillOf(gui, "Hp")
		if f and info and info.MaxHp > 0 and not info.Parked then
			worst = max(worst, abs(f - max(0, min(1, info.Hp / info.MaxHp))))
		end
	end
	T.check(worst < 0.01, "cards: every HP fill = hp / maxHp of the drawn unit", fmt(worst, 3))
	for _, u in ipairs(d:myUnits()) do
		u.meter = 100
	end
	d:step(30)
	d:step(30)
	T.near(fillOf(g1, "Special") or -1, 1, 0.001, "cards: a full meter fills the SPECIAL row")
	-- the fight's XP (End.Rewards.Xp) moves the XP bars (3.5: the toasts come from the server)
	d:finish({ Mode = "Trial", Outcome = "Win", Won = true, Spectator = false, Reason = "Wipe", Rewards = { Tokens = 100, Gems = 0, Xp = 90, Trophies = 0, LevelUps = 0, Level = 5 } })
	step(2)
	T.near(fillOf(g1, "Xp") or -1, 1090 / need20, 0.01, "cards: End.Rewards.Xp moves the XP fill (level 20: 1000 + 90)")
	T.near(fillOf(g2, "Xp") or -1, 1, 0.001, "cards: a capped pet's XP bar stays full")
	LocalPlayer:SetAttribute("InBattle", nil)
	KC.advance(4)
	local hide = find("Root.ResultCard.OkButton")
	if hide then
		Mock.Click(hide)
	end
	step(2)
	T.eq(PetCard.Count(), cardsBefore, "cards: every unit card is freed with the battle")
	T.check(battleWarnings(outBefore) == nil and #Mock.Errors == errBefore, "BattleController: no errors or warnings (cards)", tostring(battleWarnings(outBefore)))
	KC.flushErrors("client_p3battle_cards")
end)

-- one Champion Ring round, the way BattleService sends it (Start.Ring + the champion team of BattleCatalog)
local function ringDriver(round, best, start, team, seed)
	local BCat = moduleAt("shared", "BattleCatalog")
	if not BCat or type(BCat.ChampionTeam) ~= "function" then
		return nil, "BattleCatalog.ChampionTeam missing"
	end
	local spec = BCat.ChampionTeam(round, seed or 7)
	local ch = spec.Champion or {}
	return newDriver({
		Mode = "Ring", Round = round, Seed = round, Zone = { X = 44, Z = 44 }, TimeLimit = 90,
		Teams = { { Owner = LocalPlayer.UserId, Side = 1, Pets = team }, spec },
		Ring = { Round = round, Best = best, Start = start, Champion = { PetId = ch.PetId, Level = ch.Level, Tier = ch.Tier, Boss = ch.Boss == true, Name = ch.Name } },
	})
end

local function champion(d)
	for _, u in ipairs(d.sim.units) do
		if u.side == 2 then
			return u
		end
	end
	return nil
end

local function ringTeam()
	local team = catalogTeam(2, 0, 30)
	for _, p in ipairs(team) do
		p.Xp, p.XpNext = 100, 6000
	end
	return team
end

-- a won round: { Won, Next, Round, Cash, Xp, Tokens, Record, Seconds, LevelUps }
local function wonEnd(round, cash, record, tokens)
	return { Mode = "Ring", Outcome = "Win", Won = true, Spectator = false, Reason = "Wipe",
		Rewards = { Won = true, Next = round + 1, Round = round, Cash = cash, Xp = 20 + 6 * round, Tokens = tokens or 0, Record = record == true, Seconds = 1.6, LevelUps = 0 } }
end

local function finalEnd(round, run, extra)
	local p = { Mode = "Ring", Outcome = "Loss", Won = false, Spectator = false, Reason = "Wipe",
		Rewards = { Won = false, Final = true, Round = round, Cash = 0, Xp = 0, Run = run } }
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	return p
end

local function centreFree(obj, w, h)
	if not obj or not shown(obj) then
		return false
	end
	local r = screenRect(obj)
	local cx, cy = w / 2, h / 2
	return not (r.x0 <= cx and cx <= r.x1 and r.y0 <= cy and cy <= r.y1)
end

S.client_p3battle_ring = guarded("client_p3battle_ring", function()
	local BC = moduleAt("client", "Controllers/BattleController")
	if not BC then
		T.fail("BattleController missing")
		return
	end
	local outBefore, errBefore = #Mock.Output, #Mock.Errors
	local me = LocalPlayer.UserId
	local team = ringTeam()
	local d1, why = ringDriver(1, 12, 1, team)
	if not T.check(d1 ~= nil, "ring: round 1 driver (BattleSim Mode Ring + ChampionTeam)", tostring(why)) then
		return
	end
	LocalPlayer:SetAttribute("InBattle", d1.id)
	d1:start()
	d1:step(30)
	d1:step(30)
	local b = BC.GetBattle()
	T.check(b and b.Mode == "Ring" and b.Round == 1 and b.Best == 12 and b.Fighter, "ring: Start draws the round as a fighter (Round / Best from Start.Ring)", b and (tostring(b.Round) .. " / " .. tostring(b.Best)) or "nil")
	local top = find("Root.TopCard")
	T.check(shown(top) and hasText(top, "CHAMPION RING") and hasText(top, "Round 1 %- Best 12"), "ring HUD: the top card reads CHAMPION RING - Round 1 - Best 12")
	T.check(hasText(find("Root.TopCard.RingInfo"), "Win: %+%$[%d,%.KMB]+  %+26 XP"), "ring HUD: the Cash and XP of a win (RingRewards: round 1 pays 26 XP)", tostring((find("Root.TopCard.RingInfo.WinPay") or {}).Text))
	T.check(not shown(find("Root.TopCard.RingInfo.Record")) and not shown(find("Root.TopCard.RingInfo.Boss")), "ring HUD: no record / boss pill on round 1 (best 12)")
	T.check(shown(find("Root.Commands.AttackButton")) and shown(find("Root.Commands.RetreatButton")) and (hasText(find("Root.Team"), "SPECIAL") or hasText(find("Root.Team"), "%%")), "ring HUD: the Phase 3 controls (ATTACK / RETREAT / SPECIAL) work in the ring")
	-- the champion: crowned, a name tag above its card
	local ch = champion(d1)
	local cu = ch and BC.GetUnit(ch.id)
	local tag = cu and cu.Model and cu.Model:FindFirstChild("ChampionTag")
	local tagLabel = tag and tag:FindFirstChild("Name", true)
	T.check(cu and cu.Crowned and tag and tagLabel and tostring(tagLabel.Text):find("^Champion") and tagLabel.TextSize >= 22 and tag.LightInfluence == 0 and tag.Size.X.Scale == 0,
		"ring: the champion wears the crown and a 22 px name tag above its card", tagLabel and (tagLabel.Text .. " " .. tagLabel.TextSize .. " px") or "nil")
	-- the crown is PetBuilder's voxel Crown accessory: gold voxels on top of the head
	local gold = 0
	if cu and cu.Model then
		local okB, cf, size = pcall(cu.Model.GetBoundingBox, cu.Model)
		local topY = okB and (cf.Position.Y + size.Y / 2) or nil
		for _, p in ipairs(cu.Model:GetDescendants()) do
			local c = p:IsA("BasePart") and p.Color
			if c and topY and c.R > 0.8 and c.G > 0.55 and c.B < 0.45 and p.Position.Y > topY - size.Y * 0.35 then
				gold = gold + 1
			end
		end
	end
	T.check(gold > 0, "ring: the champion's model wears a gold voxel crown on its head", gold .. " gold parts near the top")
	local chCard = cu and cu.Card
	T.check(chCard and chCard.Mode == "Enemy" and tag and tag.Size.Y.Offset > chCard.Gui.Size.Y.Offset, "ring: the champion's card is an enemy card and the tag clears it", chCard and tostring(chCard.Mode) or "nil")
	-- win the round
	d1:run(25, 30)
	local res = d1.sim:Result()
	T.check(res and res.WinnerSide == 1, "ring: the level-30 team wins round 1", res and tostring(res.WinnerSide) or "running")
	local models = {}
	for _, u in ipairs(d1:myUnits()) do
		models[u.key] = BC.GetUnit(u.id) and BC.GetUnit(u.id).Model
	end
	d1:finish(wonEnd(1, 22, false))
	step(2)
	b = BC.GetBattle()
	local nextCard = find("Root.NextRoundCard")
	T.check(not shown(find("Root.ResultCard")), "ring: a won round shows no result card")
	T.check(shown(nextCard) and hasText(nextCard, "Round 1 won!") and hasText(nextCard, "%+%$22") and hasText(nextCard, "%+26 XP") and hasText(nextCard, "Round 2 in 3"),
		"ring: the side card reads Round 1 won! +$22 +26 XP - Round 2 in 3")
	T.check(b and b.Next == 2 and b.Ended, "ring: GetBattle().Next = 2 between the rounds", b and tostring(b.Next) or "nil")
	T.check(shown(find("Root.TopCard")) and shown(find("Root.Team")) and not shown(find("Root.Commands")), "ring: between rounds the top card and the team stay, the commands go")
	local vp = workspace.CurrentCamera.ViewportSize
	T.check(centreFree(nextCard, vp.X, vp.Y) and not overlap(screenRect(nextCard), screenRect(find("Root.Team"))), "ring: the side card is off the screen centre and clear of the team card")
	KC.advance(1.2)
	T.check(hasText(find("Root.NextRoundCard"), "Round 2 in 2"), "ring: the countdown runs (Round 2 in 2)", tostring((find("Root.NextRoundCard.Countdown") or {}).Text))
	local kept = true
	for _, m in pairs(models) do
		kept = kept and m ~= nil and m.Parent ~= nil
	end
	T.check(kept, "ring: my pets stay on the floor between the rounds")
	-- round 2: a new battle id in the same pocket
	local d2 = ringDriver(2, 12, 1, team)
	LocalPlayer:SetAttribute("InBattle", d2.id)
	d2:start()
	step(1)
	local same, parented = 0, 0
	for _, u in ipairs(d2:myUnits()) do
		local info = BC.GetUnit(u.id)
		if info and info.Model and info.Model == models[u.key] then
			same = same + 1
		end
		if info and info.Model and info.Model.Parent ~= nil then
			parented = parented + 1
		end
	end
	T.check(same == #d2:myUnits() and parented == same, "ring: End -> Start in one pocket keeps my pets' models (no rebuild, no blink)", same .. "/" .. #d2:myUnits())
	b = BC.GetBattle()
	T.check(b and b.Id == d2.id and b.Round == 2 and not b.Ended and b.Next == nil, "ring: the next Start is the new round", b and tostring(b.Round) or "nil")
	T.check(not shown(find("Root.NextRoundCard")) and hasText(find("Root.TopCard"), "Round 2 %- Best 12") and shown(find("Root.Commands.AttackButton")), "ring: the side card goes, the top card says Round 2, the commands are back")
	local cb = workspace:FindFirstChild("ClientBattle")
	T.check(cb and cb:FindFirstChild("Battle_" .. d1.id) == nil, "ring: the won round's floor folder is freed (cleanup keyed by battle id)")
	d2:run(1.0, 30)
	-- the run ends: the result card with the run's Cash / Rounds / Record
	d2:finish(finalEnd(2, { Wins = 1, Cash = 22, Xp = 35, Tokens = 0, Round = 2, Start = 1, Best = 12 }))
	step(2)
	local rc = find("Root.ResultCard")
	T.check(shown(rc) and hasText(rc, "RUN OVER") and hasText(rc, "Rounds won: 1") and hasText(rc, "%+%$22 Cash") and hasText(rc, "%+35 Pet XP") and hasText(rc, "Best: round 12") and not hasText(rc, "VICTORY"),
		"ring: the run's result card: RUN OVER, Rounds won, Cash, XP, the record")
	T.check(rc and rc.AnchorPoint.X == 1 and rc.AnchorPoint.Y == 1, "ring: the result card sits bottom right (never centred)")
	LocalPlayer:SetAttribute("InBattle", nil)
	KC.advance(4)
	T.check(BC.GetBattle() == nil, "ring: the battle is freed after the run")
	local ok = find("Root.ResultCard.OkButton")
	if ok then
		Mock.Click(ok)
	end
	step(2)
	-- a new record, then the run ends between two rounds (its final End names the won round's battle id)
	local d3 = ringDriver(13, 12, 10, team)
	LocalPlayer:SetAttribute("InBattle", d3.id)
	d3:start()
	d3:step(30)
	T.check(shown(find("Root.TopCard.RingInfo.Record")) and hasText(find("Root.TopCard.RingInfo"), "RECORD x3"), "ring HUD: past the record the top card says RECORD x3")
	d3:finish(wonEnd(13, 300, true))
	step(2)
	T.check(hasText(find("Root.NextRoundCard"), "New record! Cash x3") and hasText(find("Root.TopCard"), "Best 13"), "ring: a record round's side card says so and the top card's best follows")
	KC.toClient("BattleState", "End", finalEnd(13, { Wins = 4, Cash = 900, Xp = 400, Tokens = 0, Round = 13, Start = 10, Record = 13, Best = 13 }, { BattleId = d3.id, Outcome = "Left", Reason = "Forfeit", Round = 13 }), d3.id)
	step(2)
	rc = find("Root.ResultCard")
	T.check(shown(rc) and hasText(rc, "NEW RECORD!") and hasText(rc, "Best: round 13!") and hasText(rc, "Rounds won: 4") and hasText(rc, "%+%$900 Cash") and hasText(rc, "left after round 13"),
		"ring: a run that ends between rounds gets its card (NEW RECORD!, the record line)")
	T.check(not shown(find("Root.NextRoundCard")), "ring: the result card replaces the side card")
	LocalPlayer:SetAttribute("InBattle", nil)
	KC.advance(4)
	ok = find("Root.ResultCard.OkButton")
	if ok then
		Mock.Click(ok)
	end
	step(2)
	-- a boss round: the BOSS pill, a giant crowned champion
	local d4 = ringDriver(20, 25, 1, team)
	LocalPlayer:SetAttribute("InBattle", d4.id)
	d4:start()
	d4:run(0.5, 30)
	local boss = champion(d4)
	local bu = boss and BC.GetUnit(boss.id)
	T.check(shown(find("Root.TopCard.RingInfo.Boss")) and bu and bu.Kind == "MiniBoss" and bu.Crowned, "ring HUD: every 10th round shows the BOSS pill and a crowned mini-boss champion", bu and tostring(bu.Kind) or "nil")
	d4:finish(finalEnd(20, { Wins = 0, Cash = 0, Xp = 0, Tokens = 0, Round = 20, Start = 1, Best = 25 }))
	step(2)
	LocalPlayer:SetAttribute("InBattle", nil)
	KC.advance(4)
	ok = find("Root.ResultCard.OkButton")
	if ok then
		Mock.Click(ok)
	end
	step(2)
	-- duel overtime (BattleCatalog.Damage.Overtime): the top card says hits grow
	local dd = newDriver({ Mode = "Duel", Teams = { { Owner = me, Side = 1, Pets = catalogTeam(2) }, { Owner = 78, Side = 2, Pets = catalogTeam(2, 2) } } })
	LocalPlayer:SetAttribute("InBattle", dd.id)
	dd:start()
	dd:step(30)
	T.check(not shown(find("Root.TopCard.RingInfo")), "duel: no overtime line before overtime")
	KC.toClient("BattleState", "Events", { { type = "Overtime", at = 75, perSecond = 0.15 } }, dd.id)
	for _ = 1, 4 do
		dd:step(30)
	end
	b = BC.GetBattle()
	T.check(b and b.Overtime and shown(find("Root.TopCard.RingInfo.Overtime")) and hasText(find("Root.TopCard.RingInfo"), "OVERTIME: hits %+15%% a second"), "duel: the Overtime event puts OVERTIME: hits +15% a second in the top card", b and tostring(b.Overtime) or "nil")
	T.check(centreFree(find("Root.TopCard"), vp.X, vp.Y), "duel: the overtime line stays in the top card (off the screen centre)")
	dd:finish({ Mode = "Duel", Outcome = "Win", Won = true, Spectator = false, Reason = "Wipe", Rewards = { Tokens = 60, Gems = 0, Xp = 60, Trophies = 25, LevelUps = 0 } })
	step(2)
	LocalPlayer:SetAttribute("InBattle", nil)
	KC.advance(4)
	ok = find("Root.ResultCard.OkButton")
	if ok then
		Mock.Click(ok)
	end
	step(2)
	T.check(BC.GetBattle() == nil and not BC.IsHudVisible(), "ring: everything freed afterwards")
	T.check(battleWarnings(outBefore) == nil and #Mock.Errors == errBefore, "BattleController: no errors or warnings (ring)", tostring(battleWarnings(outBefore)))
	KC.flushErrors("client_p3battle_ring")
end)

-- (phone world) the ring's side card and the unit cards on a 390x844 touch screen and turned sideways
S.client_p3battle_ring_mobile = guarded("client_p3battle_ring_mobile", function()
	local BC = moduleAt("client", "Controllers/BattleController")
	if not BC then
		T.fail("BattleController missing (phone)")
		return
	end
	bootPhone()
	local outBefore, errBefore = #Mock.Output, #Mock.Errors
	for _, size in ipairs({ { 390, 844 }, { 844, 390 } }) do
		Mock.SetViewport(size[1], size[2])
		step(2)
		local tagName = size[1] .. "x" .. size[2]
		local d = ringDriver(4, 12, 1, ringTeam())
		LocalPlayer:SetAttribute("InBattle", d.id)
		d:start()
		d:run(1.0, 30)
		local small = nil
		for _, u in ipairs(d.sim.units) do
			local gui = cardOf(BC, u.id)
			local _, lvl = levelText(gui)
			if not lvl or lvl.TextSize < 14 then
				small = "unit " .. u.id .. " " .. tostring(lvl and lvl.TextSize)
			end
		end
		T.check(small == nil, "phone " .. tagName .. ": every unit card's Lv text is >= 14 px", tostring(small))
		d:finish(wonEnd(4, 28, false))
		step(2)
		local nc = find("Root.NextRoundCard")
		local scale = find("Root.ReadScale")
		local f = scale and scale.Scale or 1
		small = nil
		for _, t in ipairs(shownTexts(nc)) do
			if t.TextSize * f < 13.99 then
				small = t.Name .. " " .. fmt(t.TextSize * f)
			end
		end
		T.check(shown(nc) and small == nil, "phone " .. tagName .. ": the side card's texts are >= 14 px", tostring(small))
		T.check(centreFree(nc, size[1], size[2]), "phone " .. tagName .. ": the side card is off the screen centre")
		local clash = nil
		for i = 1, 4 do
			local row = find("Root.Team.Row" .. i)
			if row and shown(row) and overlap(screenRect(row), screenRect(nc)) then
				clash = "Row" .. i
			end
		end
		if shown(find("Root.TopCard")) and overlap(screenRect(find("Root.TopCard")), screenRect(nc)) then
			clash = "TopCard"
		end
		T.check(clash == nil, "phone " .. tagName .. ": the side card covers neither the top card nor the team cards", tostring(clash))
		local r = screenRect(nc)
		T.check(r.x0 >= 0 and r.y0 >= 0 and r.x1 <= size[1] + 1 and r.y1 <= size[2] + 1, "phone " .. tagName .. ": the side card fits the screen", fmt(r.x0) .. "," .. fmt(r.y0) .. " - " .. fmt(r.x1) .. "," .. fmt(r.y1))
		KC.toClient("BattleState", "End", finalEnd(4, { Wins = 1, Cash = 28, Xp = 44, Tokens = 0, Round = 4, Start = 1, Best = 12 }, { BattleId = d.id, Outcome = "Left", Reason = "Forfeit" }), d.id)
		step(2)
		local rc = find("Root.ResultCard")
		T.check(shown(rc) and centreFree(rc, size[1], size[2]) and hasText(rc, "Rounds won: 1"), "phone " .. tagName .. ": the run's card is off the screen centre")
		LocalPlayer:SetAttribute("InBattle", nil)
		KC.advance(4)
		local ok = find("Root.ResultCard.OkButton")
		if ok then
			Mock.Click(ok)
		end
		step(2)
	end
	Mock.SetViewport(390, 844)
	step(2)
	T.check(BC.GetBattle() == nil and not BC.IsHudVisible(), "phone: the ring frees everything afterwards")
	T.check(battleWarnings(outBefore) == nil and #Mock.Errors == errBefore, "BattleController: no errors or warnings (phone ring)", tostring(battleWarnings(outBefore)))
	KC.flushErrors("client_p3battle_ring_mobile")
end)

return S
