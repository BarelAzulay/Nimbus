-- smoke_daily_ui.lua: the store build's Gifts UI (docs/superpowers/specs/2026-11-04-shop-retention-design.md 5.2 / 8 / 13b; plan
-- Task 8), loaded by tools/smoke.py in the client worlds only (ARGS.context = "client"; the server half is empty):
--   client_daily_window  (1920x1080) the Gifts button 8 px left of the currency strips (56 px), the window on Daily with
--                        WindowOpened("Daily"), the header, seven cells (claimed dim, today pulsing, the resolved amounts),
--                        CLAIM! -> DailyRequest("Claim"), the countdown after a claim, the week banner + 24 confetti (none on
--                        Low), the step-back hint once, the VIP chip, the Play tab cells, the paused header, a tier cell CLAIM ->
--                        ClaimPlay(tier), the window rule (Pets / Shop / Gifts never overlap). gui-redo Task 9: the window is
--                        the big centred one (NeonKit.BigRect: 1180x720 at 1080p, the button stays where it is), so "nothing
--                        in the screen centre" became the Store's form: opening it puts no OTHER text in the middle, and no
--                        Gifts text is left there after Close. gui-redo Task 10: the Play tab is card B's gift boxes, so
--                        the header is PlayHeader and a far tier shows its own clock ("12:50", counting from ServerNow)
--                        instead of "13 min to go". Slop-audit 2026-11-12: win 6, the CloseButton's X is drawn
--                        (NeonKit.CloseMark, >= 44 px); win 5, the Gifts button, its ring and its pip hide behind every
--                        window in DailyController.K.WINDOWS (the menu's Pets window, the Index, the Stats window), not only
--                        the Shop, and are back within 0.4 s of that window closing (its own X, or MenuController switching
--                        ids and closing). Owner 2026-11-13: the Gifts window itself hides them too (at once, back at
--                        once on Close), and so does an open NPC talk box (NpcController.IsOpen, back within K.WINDOW_POLL)
--   client_daily_pip    the pip waits PipDelaySeconds after a spawn and the tutorial's spin step, the shake when a tier
--                        becomes Ready (never on the first payload after a Loading one), the ring's fill and its paused dim,
--                        the button hides in a match
--   client_daily_chips   the boost chips: x2 Cash, x2 XP with the potion's time left, the pass's x2 XP, the started / 5 min
--                        hints, 46x24 at 1080p, right-aligned under the strips
--   client_daily_vip     VipController.IsVip, the gold [VIP] chat prefix, the lobby crown on High only, hidden in a battle,
--                        gone on leave
--   client_daily_mobile  (phone world, 844x390 touch) the 44 px button, the 820x330 window at 12,59 at scale 1 (gui-redo
--                        Task 9: the BigRect box; it was 560x300 under the button), 92x122 tiles (were 64x92), the 44 px X
--                        still drawn and centred (slop-audit win 6), CLAIM! 230x64
--                        (was 200x48), texts >= 15, chips 34x18 text 15
-- No DailyService yet (W2): every payload is fired at the client with KC.toClient("DailyState", ...). The viewport, the
-- graphics level, the tutorial state, the attributes and MenuController.Hint are restored at the end of each scenario.
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs, floor = math.abs, math.floor
local fmt = string.format

local function serverScenarios()
	return {}
end

local function clientScenarios()
	local KC = _G.KC
	local S = {}
	local Players = game:GetService("Players")
	local UIS = game:GetService("UserInputService")
	local LocalPlayer = Players.LocalPlayer
	local DOT = "\194\183"
	local H = {}

	-- a module of the client build (the H.moduleAt shape of smoke_evo_retreat.lua; ROOTS is smoke.py's)
	function H.moduleAt(top, rest)
		local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end
	function H.pg()
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	function H.now()
		return workspace:GetServerTimeNow()
	end
	function H.find(root, name)
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
	function H.shown(obj)
		return obj ~= nil and KC.isShown(obj)
	end
	function H.texts(root)
		local out = {}
		for _, d in ipairs(root and KC.texts(root, true) or {}) do
			out[#out + 1] = tostring(d.Text)
		end
		return table.concat(out, " | ")
	end
	function H.gui()
		return H.pg():FindFirstChild("NimbusDaily")
	end
	function H.btn()
		return H.find(H.gui(), "GiftsButton")
	end
	function H.win()
		return H.find(H.gui(), "DailyWindow")
	end
	function H.page()
		for _, name in ipairs({ "DailyPage", "PlayPage" }) do
			local p = H.find(H.win(), name)
			if H.shown(p) then
				return p
			end
		end
		return nil
	end
	function H.fire(payload)
		KC.toClient("DailyState", payload)
		KC.advance(0.05)
	end
	function H.tap(button)
		if button then
			Mock.Click(button)
		end
		KC.advance(0.3)
	end
	function H.setScreen(w, h, touch)
		UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = touch, not touch, not touch
		Mock.SetViewport(w, h)
		KC.advance(0.5)
	end
	function H.saveScreen()
		local old = { Mock.Viewport.X, Mock.Viewport.Y, UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled }
		return function()
			UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = old[3], old[4], old[5]
			Mock.SetViewport(old[1], old[2])
			KC.advance(0.5)
		end
	end
	-- MenuController.Hint is wrapped for the scenario (every side hint counted), WindowOpened watched
	function H.watchMenu(MC)
		local w = { hints = {}, opened = {} }
		local real = MC and MC.Hint
		if MC then
			MC.Hint = function(text, kind)
				w.hints[#w.hints + 1] = tostring(text)
				return real(text, kind)
			end
			w.conn = MC.WindowOpened:Connect(function(id)
				w.opened[#w.opened + 1] = id
			end)
		end
		function w.last()
			return w.hints[#w.hints] or ""
		end
		function w.count(needle)
			local n = 0
			for _, t in ipairs(w.hints) do
				if t:find(needle, 1, true) then
					n = n + 1
				end
			end
			return n
		end
		function w.restore()
			if MC then
				MC.Hint = real
				if w.conn then
					w.conn:Disconnect()
				end
			end
		end
		return w
	end
	-- a TutorialState payload of step `id` (the smoke_client.lua tutorialPayload shape)
	function H.tutorial(id, over)
		local Steps = H.moduleAt("shared", "TutorialSteps")
		local Config = KC.env()
		local index = Steps.IndexOf[id] or #Steps.Steps
		local step = Steps.Steps[index]
		local text = step.Text:gsub("{GiftTokens}", tostring(Config.Tutorial.GiftTokens))
		text = text:gsub("{FinishTokens}", tostring(Config.Tutorial.FinishReward.Tokens))
		local st = {
			Step = index, Total = #Steps.Steps, Id = step.Id, Title = step.Title, Text = text, Target = step.Target,
			CompleteOn = step.CompleteOn, Hint = step.Hint, Button = step.Button, Gift = step.Gift == true,
			Done = false, Completed = false, Skipped = false, Reward = 0,
		}
		for k, v in pairs(over or {}) do
			st[k] = v
		end
		return st
	end
	function H.restoreTutorial(prev)
		KC.toClient("TutorialState", prev or H.tutorial("done", { Done = true, Completed = true }))
		KC.advance(0.2)
	end

	-- the DailyState payload (plan Task 8 "Produces"): Streak 2, Cell 3, Week 2, days 1-2 claimed, ready a second ago,
	-- 47 min played today, tiers 1-3 claimed, tier 4 (60 min) not ready
	function H.base(now)
		local days = {
			{ Kind = "Cash", Amount = 400, Claimed = true, Today = false },
			{ Kind = "Tokens", Amount = 50, Claimed = true, Today = false },
			{ Kind = "Cash", Amount = 1450, Claimed = false, Today = true },
			{ Kind = "Cash", Amount = 1000, Claimed = false, Today = false },
			{ Kind = "Tokens", Amount = 250, Claimed = false, Today = false },
			{ Kind = "Gems", Amount = 25, Claimed = false, Today = false },
			{ Kind = "Pet", PetId = "week_wisp", Claimed = false, Today = false },
		}
		local tiers = {
			{ Min = 10, Kind = "Cash", Amount = 200, Claimed = true, Ready = false },
			{ Min = 20, Kind = "Tokens", Amount = 40, Claimed = true, Ready = false },
			{ Min = 30, Kind = "Cash", Amount = 600, Claimed = true, Ready = false },
			{ Min = 60, Kind = "Gems", Amount = 10, Claimed = false, Ready = false },
			{ Min = 90, Kind = "Tokens", Amount = 150, Claimed = false, Ready = false },
			{ Min = 120, Kind = "Berries", Claimed = false, Ready = false },
			{ Min = 180, Kind = "Gems", Amount = 25, Claimed = false, Ready = false },
		}
		return {
			Loading = false, Streak = 2, Paid = 2, Weeks = 1, Pet = false, ReadyAt = now - 1, KeepUntil = now + 28 * 3600,
			Cell = 3, Vip = false, StepBack = 0, Days = days, ServerNow = now,
			Play = { Seconds = 47 * 60, DayEnds = now + 5 * 3600, Active = true, Tiers = tiers },
		}
	end

	-- the window's parts (DailyController names them; see its header)
	function H.header()
		-- (gui-redo Task 10: the Play page's line is PlayHeader)
		local h = H.find(H.page(), "Header") or H.find(H.page(), "PlayHeader")
		return H.shown(h) and tostring(h.Text) or ""
	end
	function H.cell(i)
		return H.find(H.find(H.win(), "Cells"), "Cell" .. i)
	end
	function H.cellCount()
		local n = 0
		for _, c in ipairs(H.find(H.win(), "Cells") and H.find(H.win(), "Cells"):GetChildren() or {}) do
			if c.Name:match("^Cell%d$") then
				n = n + 1
			end
		end
		return n
	end
	function H.cellText(i)
		return H.texts(H.cell(i))
	end
	function H.cellDimmed(i)
		return H.shown(H.find(H.cell(i), "Dim")) and H.shown(H.find(H.cell(i), "Check"))
	end
	function H.cellPulsing(i)
		local c = H.cell(i)
		return c ~= nil and c:GetAttribute("Pulsing") == true
	end
	function H.claimButton()
		local b = H.find(H.win(), "ClaimButton")
		return H.shown(b) and b or nil
	end
	-- the Daily page's texts under the tiles (gui-redo Task 9 dropped the Footer frame: the Wisp line, the claim slot and the
	-- keep line sit in the page)
	function H.footer()
		local out = {}
		for _, name in ipairs({ "WispText", "WeekBanner", "ClaimButton", "Countdown", "Keep" }) do
			local o = H.find(H.win(), name)
			if H.shown(o) then
				local t = tostring(o.Text or "")
				local inner = H.texts(o)
				if inner ~= "" then
					t = (t ~= "" and (t .. " | ") or "") .. inner
				end
				if t ~= "" then
					out[#out + 1] = t
				end
			end
		end
		return table.concat(out, " | ")
	end
	-- the window's BigRect box (NimbusDaily keeps the gui inset: AbsolutePosition.Y + 58 = the box's screen y)
	function H.inBox(win, DC)
		local NK = H.moduleAt("client", "UI/NeonKit")
		local r = NK and DC and DC.K and NK.BigRect(DC.K)
		return win ~= nil and r ~= nil and abs(win.AbsolutePosition.X - r.x) <= 1 and abs(win.AbsolutePosition.Y + 58 - r.y) <= 1
			and abs(win.AbsoluteSize.X - r.w) <= 1 and abs(win.AbsoluteSize.Y - r.h) <= 1
			and abs(win.AbsolutePosition.X + win.AbsoluteSize.X / 2 - Mock.Viewport.X / 2) <= 1
	end
	-- the centred texts (KC.centredTexts entries) whose path passes pred
	function H.centredWhere(pred)
		local out = {}
		for _, e in ipairs(KC.centredTexts(0.14)) do
			if pred(e.path) then
				out[#out + 1] = e
			end
		end
		return out
	end
	function H.body()
		return H.texts(H.win())
	end
	function H.confetti()
		local n = 0
		for _, d in ipairs(H.win() and H.win():GetDescendants() or {}) do
			if d.Name == "Confetti" and H.shown(d) then
				n = n + 1
			end
		end
		return n
	end
	function H.activeTab()
		local p = H.page()
		return p and (p.Name == "DailyPage" and "Daily" or "Play") or nil
	end
	function H.tapTab(label)
		for _, d in ipairs(H.win() and H.win():GetDescendants() or {}) do
			if d:IsA("TextButton") and d.Name:sub(1, 4) == "Tab_" and d.Text == label then
				H.tap(d)
				return true
			end
		end
		return false
	end
	-- the Play tab's reward cells (Tiers > Tier1..7; review fix D turned the rows into cells)
	function H.row(i)
		return H.find(H.find(H.win(), "Tiers"), "Tier" .. i)
	end
	function H.rowCount()
		local n = 0
		local rows = H.find(H.win(), "Tiers")
		for _, c in ipairs(rows and rows:GetChildren() or {}) do
			if c.Name:match("^Tier%d$") and H.shown(c) then
				n = n + 1
			end
		end
		return n
	end
	function H.rowText(i)
		return H.texts(H.row(i))
	end
	function H.rowButton(i)
		local b = H.find(H.row(i), "Claim")
		return H.shown(b) and b or nil
	end
	function H.sent(mark)
		return KC.serverCalls("DailyRequest", mark)
	end
	-- slop-audit win 6: the problems of a close button's drawn X ({} = good): the shared check (smoke_common.lua
	-- SmokeCommon.closeMarkIssues, review round 1), with a tap of at least 44 px
	function H.closeMarkIssues(button)
		return SmokeCommon.closeMarkIssues(button, { Shown = H.shown, MinTap = 44 })
	end
	-- win 5: the Gifts button, its ring and its pip as { button, ring, pip } shown flags
	function H.giftsParts()
		local b = H.btn()
		local ring = H.gui() and H.gui():FindFirstChild("Ring")
		return { H.shown(b), H.shown(ring), H.shown(H.find(b, "Pip")) }
	end
	function H.partsText(p)
		return fmt("button %s, ring %s, pip %s", tostring(p[1]), tostring(p[2]), tostring(p[3]))
	end

	S.client_daily_window = guarded("client_daily_window", function()
		local restoreScreen = H.saveScreen()
		H.setScreen(1920, 1080, false)
		local DC = H.moduleAt("client", "Controllers/DailyController")
		local MC = H.moduleAt("client", "Controllers/MenuController")
		local GQ = H.moduleAt("client", "GraphicsQuality")
		local Pets = H.moduleAt("client", "Controllers/PetsController")
		local Theme = select(3, KC.env())
		local w = H.watchMenu(MC)
		if GQ then
			GQ.Apply("High")
		end
		local now = H.now()
		H.fire(H.base(now))
		local gui = H.pg():WaitForChild("NimbusDaily", 2)
		local btn = H.btn()
		local hud = H.pg():FindFirstChild("NimbusHud")
		-- (kit-b U8, restated: the gift sat 8 px left of the strips at y 6) the gift docks under the currency strips where the
		-- HUD says (GiftLeft / GiftTop / GiftSize), 56 px at 1080p (hud_gift_under_strips checks the dock itself)
		local gl, gt, gs = hud and hud:GetAttribute("GiftLeft") or -1, hud and hud:GetAttribute("GiftTop") or -1, hud and hud:GetAttribute("GiftSize") or 0
		local okBtn = T.check(DC ~= nil and gui ~= nil and btn ~= nil and abs(btn.AbsolutePosition.X - gl) <= 1 and abs(btn.AbsolutePosition.Y - gt) <= 1
			and gs == 56 and btn.AbsoluteSize.X == 56 and btn.AbsoluteSize.Y == 56,
			"daily window: the Gifts button docks under the strips (GiftLeft / GiftTop), 56 px at 1080p",
			btn and fmt("button %d,%d %dx%d, dock %s,%s %s", btn.AbsolutePosition.X, btn.AbsolutePosition.Y, btn.AbsoluteSize.X, btn.AbsoluteSize.Y, tostring(gl), tostring(gt), tostring(gs)) or "no NimbusDaily.GiftsButton")
		if not okBtn or not DC then
			w.restore()
			restoreScreen()
			return
		end
		T.eq(gui.DisplayOrder, 19, "daily window: NimbusDaily.DisplayOrder = 19")
		T.eq(gui.IgnoreGuiInset, false, "daily window: NimbusDaily.IgnoreGuiInset = false (the HUD attributes are gui-area px)")
		T.check(type(DC.State()) == "table" and DC.State().Streak == 2, "daily window: State() is the last payload")
		local before = {} -- what else sits in the middle of the screen before the window opens
		for _, e in ipairs(H.centredWhere(function(path)
			return path:find("^NimbusDaily") == nil
		end)) do
			before[e.path] = true
		end
		w.opened = {}
		H.tap(btn)
		T.check(DC.IsOpen() and w.opened[#w.opened] == "Daily" and H.activeTab() == "Daily", "daily window: opens on Daily and fires WindowOpened",
			fmt("open %s, opened %s, tab %s", tostring(DC.IsOpen()), table.concat(w.opened, ","), tostring(H.activeTab())))
		local win = H.win()
		-- (gui-redo Task 9: the big centred window replaced the 760x420 drop-down under the button)
		T.check(win ~= nil and abs(win.AbsoluteSize.X - 1180) <= 1 and abs(win.AbsoluteSize.Y - 720) <= 1 and DC.Layout() == "PC", "daily window: 1180x720 at 1080p (PC)",
			win and fmt("%dx%d %s", win.AbsoluteSize.X, win.AbsoluteSize.Y, tostring(DC.Layout())) or "no window")
		T.check(H.inBox(win, DC) and abs(btn.AbsolutePosition.X - gl) <= 1 and abs(btn.AbsolutePosition.Y - gt) <= 1, -- (kit-b U8: the dock under the strips)
			"daily window: centred in its BigRect box, the Gifts button laid out where it was",
			win and fmt("window %d,%d %dx%d, button %d,%d", win.AbsolutePosition.X, win.AbsolutePosition.Y, win.AbsoluteSize.X, win.AbsoluteSize.Y, btn.AbsolutePosition.X, btn.AbsolutePosition.Y) or "no window")
		-- (owner 2026-11-13) the Gifts window hides its own button, ring and pip too (X / Esc / gamepad B close it)
		local own = H.giftsParts()
		T.check(not own[1] and not own[2] and not own[3], "daily window: (owner 2026-11-13) its own window hides the Gifts button, its ring and its pip at once",
			H.partsText(own))
		T.check(H.header():upper():find("DAY 3 OF 7", 1, true) ~= nil and H.header():upper():find("WEEK 2", 1, true) ~= nil, "daily window: the header", H.header())
		T.check(H.cellCount() == 7 and H.cellText(1):find("$", 1, true) ~= nil and H.cellDimmed(1) and H.cellDimmed(2) and not H.cellDimmed(3) and H.cellPulsing(3)
			and not H.cellPulsing(4), "daily window: 7 cells, claimed dim, today pulsing",
			fmt("%d cells, cell1 '%s', dim %s %s %s, pulse %s", H.cellCount(), H.cellText(1), tostring(H.cellDimmed(1)), tostring(H.cellDimmed(2)), tostring(H.cellDimmed(3)), tostring(H.cellPulsing(3))))
		T.check(H.cellText(3):find("1,450", 1, true) ~= nil, "daily window: amounts are the resolved numbers (13b.3)", H.cellText(3))
		-- (re-review 1: "Week Wisp" is wider than the day cell on every layout, so the cell names the pet by its last word;
		-- the week banner and the toast keep the full name; smoke_fixr_daily_ui.lua client_fixr_daily_fit checks the fit)
		T.check(H.find(H.cell(7), "PetViewport") ~= nil and H.cellText(7):find("Wisp", 1, true) ~= nil, "daily window: day 7 shows the Week Wisp (its viewport, named 'Wisp' in the cell)", H.cellText(7))
		local claim = H.claimButton()
		T.check(claim ~= nil and claim.Text == "CLAIM!" and claim.AbsoluteSize.X >= 260 and claim.AbsoluteSize.Y >= 56, "daily window: CLAIM! when ready",
			claim and fmt("%s %dx%d", claim.Text, claim.AbsoluteSize.X, claim.AbsoluteSize.Y) or H.footer())
		local mark = #Mock.RemoteLog
		H.tap(claim)
		local sent = H.sent(mark)
		T.check(#sent == 1 and sent[1].args[1] == "Claim", "daily window: CLAIM! -> DailyRequest(\"Claim\")", tostring(#sent))
		mark = #Mock.RemoteLog
		H.tap(claim)
		T.eq(#H.sent(mark), 0, "daily window: a second tap within 1 s sends nothing")
		local p2 = H.base(now)
		p2.Streak, p2.Paid, p2.Cell = 3, 3, 4
		p2.Days[3].Claimed, p2.Days[3].Today, p2.Days[4].Today = true, false, true
		p2.ReadyAt = now + 72000
		H.fire(p2)
		KC.advance(1.1)
		T.check(H.cellDimmed(3) and H.claimButton() == nil and H.footer():find("Next gift in 19h 59m", 1, true) ~= nil and H.footer():find("keep your streak", 1, true) ~= nil,
			"daily window: after the claim the cell pops dim and the countdown shows", H.footer())
		local p3 = H.base(now)
		p3.Streak, p3.Paid, p3.Weeks, p3.Cell, p3.ReadyAt = 7, 7, 2, 1, now + 72000 -- a paid week: Weeks rises (1 -> 2)
		for i = 1, 7 do
			p3.Days[i].Claimed, p3.Days[i].Today = true, false
		end
		H.fire(p3)
		T.check(H.body():upper():find("WEEK DONE! WEEK WISP IS YOURS!", 1, true) ~= nil and H.confetti() == 24, "daily window: day 7 = the week banner + confetti inside the window (High)",
			fmt("confetti %d, body %s", H.confetti(), H.body():sub(1, 200)))
		KC.advance(3)
		T.eq(H.confetti(), 0, "daily window: the confetti is gone after its fall")
		if GQ then
			GQ.Apply("Low")
		end
		H.fire(p2)
		H.fire(p3)
		T.check(H.body():find("WEEK DONE!", 1, true) ~= nil and H.confetti() == 0, "daily window: no confetti on Low (the banner stays)", tostring(H.confetti()))
		if GQ then
			GQ.Apply("High")
		end
		KC.advance(4.5)
		local p4 = H.base(now)
		p4.StepBack = 1
		H.fire(p4)
		T.check(w.last():find("You stepped back 1 day", 1, true) ~= nil and w.last():find("Welcome back!", 1, true) ~= nil, "daily window: the step-back hint, once", w.last())
		H.fire(p4)
		T.eq(w.count("stepped back"), 1, "daily window: ...only once")
		local p5 = H.base(now)
		p5.Vip = true
		H.fire(p5)
		T.check(H.body():find("VIP x2", 1, true) ~= nil, "daily window: the VIP chip", H.body():sub(1, 200))
		H.fire(H.base(now))
		T.check(H.body():find("VIP x2", 1, true) == nil, "daily window: no VIP chip without the pass")
		H.tapTab("Play time")
		T.check(H.activeTab() == "Play" and H.header():find("47 min played today", 1, true) ~= nil and H.header():find("Resets in", 1, true) ~= nil
			-- (gui-redo Task 10: the 60 min box shows its own clock, counting from the payload's ServerNow: at most "13:00")
			and H.rowCount() == 7 and (H.find(H.row(4), "Clock") and H.find(H.row(4), "Clock").Text or ""):find("^1[23]:%d%d$") ~= nil
			and H.rowText(1):find("10 min", 1, true) ~= nil and H.rowText(1):find("+$200", 1, true) ~= nil,
			"daily window: the Play tab boxes", fmt("tab %s, header '%s', %d rows, row1 '%s', row4 '%s'", tostring(H.activeTab()), H.header(), H.rowCount(), H.rowText(1), H.rowText(4)))
		T.check(H.find(H.row(1), "Check") ~= nil and H.shown(H.find(H.row(1), "Check")) and H.rowButton(4) == nil, "daily window: a claimed tier has its check, a far one no CLAIM")
		local p6 = H.base(now)
		p6.Play.Active = false
		H.fire(p6)
		T.check(H.header():find("Paused: move around to keep counting!", 1, true) ~= nil, "daily window: the paused header (13b.4)", H.header())
		local p7 = H.base(now)
		p7.Play.Tiers[4].Ready = true
		H.fire(p7)
		mark = #Mock.RemoteLog
		H.tap(H.rowButton(4))
		sent = H.sent(mark)
		T.check(#sent == 1 and sent[1].args[1] == "ClaimPlay" and sent[1].args[2] == 4, "daily window: a tier cell CLAIM -> ClaimPlay(tier)", tostring(#sent))
		-- (gui-redo Task 9: the big window fills the middle by design, as the Store does; what stays pinned is that opening it
		-- puts no OTHER text there and that none of its text is left there after Close)
		local function others(path)
			return path:find("^NimbusDaily") == nil and not before[path]
		end
		local centred = H.centredWhere(others)
		T.check(#centred == 0, "daily window: nothing in the screen centre", KC.describeCentred(centred))
		H.tapTab("Daily")
		centred = H.centredWhere(others)
		T.check(#centred == 0, "daily window: nothing in the screen centre (Daily tab)", KC.describeCentred(centred))
		-- (slop-audit win 6) the X is drawn, never a glyph
		local closeIssues = H.closeMarkIssues(H.find(H.win(), "CloseButton"))
		T.check(#closeIssues == 0, "daily window: the CloseButton's X is drawn (NeonKit.CloseMark: BarA +45 / BarB -45, centred, no text), a tap of at least 44 px",
			table.concat(closeIssues, "; "))
		-- X closes; Esc closes
		H.tap(H.find(H.win(), "CloseButton"))
		T.check(not DC.IsOpen() and not H.shown(H.win()), "daily window: X closes it")
		centred = H.centredWhere(function(path)
			return path:find("^NimbusDaily") ~= nil
		end)
		T.check(#centred == 0, "daily window: no Gifts text is left in the screen centre after Close", KC.describeCentred(centred))
		DC.Open({ Tab = "Play" })
		KC.advance(0.3)
		T.check(DC.IsOpen() and H.activeTab() == "Play", "daily window: Open({ Tab = \"Play\" })")
		Mock.FireSignal(UIS, "InputBegan", Mock.NewInput("Escape", "Keyboard", "Begin"), false)
		KC.advance(0.2)
		T.check(not DC.IsOpen(), "daily window: Esc closes it")
		-- the window rule (spec 8): Store, Gifts and Pets never overlap
		if Pets then
			Pets.Open()
			KC.advance(0.3)
			-- (slop-audit win 5: the Gifts button hides behind the Pets window, so the Gifts window comes from DailyController.Open,
			-- e.g. a hint or the server; the window rule is the same)
			T.check(not H.shown(btn), "daily window: (win 5) the Gifts button hides behind the Pets window", H.partsText(H.giftsParts()))
			DC.Open()
			local atOnce = H.giftsParts()
			KC.advance(0.3)
			T.check(DC.IsOpen() and not Pets.IsOpen(), "daily window: the Gifts window closes the Pets window (MenuController's WindowOpened handler)",
				fmt("gifts %s, pets %s", tostring(DC.IsOpen()), tostring(Pets.IsOpen())))
			-- (owner 2026-11-13: before, its own button and ring came back here; the Gifts window now hides them itself)
			T.check(not atOnce[1] and not atOnce[2] and not H.shown(btn), "daily window: (owner 2026-11-13) ...and its own button and ring stay hidden behind the Gifts window", H.partsText(atOnce))
			Pets.Open()
			KC.advance(0.3)
			T.check(not DC.IsOpen() and Pets.IsOpen(), "daily window: the Pets window closes the Gifts window")
			Pets.Close(true)
			KC.advance(0.3)
		end
		if MC then
			DC.Open()
			KC.advance(0.3)
			MC.Open("Shop")
			KC.advance(0.3)
			T.check(not DC.IsOpen(), "daily window: the Shop closes the Gifts window")
			MC.Close()
			KC.advance(0.3)
		end
		-- slop-audit win 5 (Review Focus 4): the Gifts button, its ring and its pip hide behind EVERY window of
		-- DailyController.K.WINDOWS (not only the Shop) and are back within 0.4 s of that window closing, whatever closed it
		-- (no shared close signal: DailyController polls every K.WINDOW_POLL s)
		local IC = H.moduleAt("client", "Controllers/IndexController")
		local list = type(DC.K.WINDOWS) == "table" and DC.K.WINDOWS or {}
		local inList, wrong = {}, {}
		for _, name in ipairs(list) do
			inList[name] = true
		end
		for _, name in ipairs({ "MenuController", "PetsController", "ShopController", "StoreController", "TroveController", "IndexController", "FusionController",
			"CareController", "TrainController", "DungeonController", "ObbyController", "RaidGateController", "ArenaController", "LossScreen",
			"NpcController" }) do -- (owner 2026-11-13) the NPC talk box too
			if not inList[name] then
				wrong[#wrong + 1] = "missing " .. name
			end
		end
		-- (its own window is asked through its own state, not the list)
		for _, name in ipairs({ "DailyController", "DevController", "MainMenuController" }) do
			if inList[name] then
				wrong[#wrong + 1] = "lists " .. name
			end
		end
		T.check(#wrong == 0 and DC.K.WINDOW_POLL == 0.25, "daily window: (win 5) K.WINDOWS names every window controller and the NPC talk box (never itself, DEV or the title menu), K.WINDOW_POLL 0.25 s",
			fmt("%s; poll %s", table.concat(wrong, ", "), tostring(DC.K.WINDOW_POLL)))
		-- (review round 1) the poll is cheap: every K.WINDOWS module is resolved once and kept, so a tick is only their IsOpen
		-- calls (no FindFirstChild + require 14 times every 0.25 s)
		KC.advance(0.6)
		local cache = type(DC._S) == "table" and DC._S.WindowMods or nil
		local kept = {}
		for _, name in ipairs(list) do
			if type(cache) == "table" and type(cache[name]) == "table" then
				kept[#kept + 1] = name
			end
		end
		T.check(#kept == #list and #list > 0, "daily window: (win 5) the watcher keeps every K.WINDOWS module once resolved (a tick only calls IsOpen)",
			#kept .. " of " .. #list)
		if MC and Pets and IC then
			local TC = H.moduleAt("client", "Controllers/TutorialController")
			local prevTutorial = TC and TC.GetState and TC.GetState() or nil
			KC.toClient("TutorialState", H.tutorial("done", { Done = true, Completed = true }))
			H.fire(H.base(H.now()))
			if not DC.PipShown() then
				KC.advance(21) -- the pip waits PipDelaySeconds after a spawn
			end
			local function all(p)
				return p[1] and p[2] and p[3]
			end
			local function none(p)
				return not p[1] and not p[2] and not p[3]
			end
			local p = H.giftsParts()
			T.check(all(p), "daily window: (win 5) no window up: the Gifts button, its ring and its pip show", H.partsText(p))
			MC.Open("Pets")
			KC.advance(0.3)
			p = H.giftsParts()
			T.check(Pets.IsOpen() and none(p), "daily window: (win 5) the menu's Pets window hides the Gifts button, its ring and its pip",
				fmt("pets %s, %s", tostring(Pets.IsOpen()), H.partsText(p)))
			local petsGui = H.pg():FindFirstChild("NimbusPets")
			local petsWin = petsGui and petsGui:FindFirstChild("PetsWindow", true)
			local petsX = petsWin and petsWin:FindFirstChild("Close")
			if petsX then
				Mock.Click(petsX) -- the Pets window's own (drawn) X
			end
			KC.advance(0.4)
			p = H.giftsParts()
			T.check(petsX ~= nil and not Pets.IsOpen() and all(p), "daily window: (win 5) ...back within 0.4 s of the Pets window's own X",
				fmt("X %s, pets %s, %s", tostring(petsX ~= nil), tostring(Pets.IsOpen()), H.partsText(p)))
			MC.Open("Index")
			KC.advance(0.3)
			p = H.giftsParts()
			T.check(IC.IsOpen() and none(p), "daily window: (win 5) the Pet Index hides them too", fmt("index %s, %s", tostring(IC.IsOpen()), H.partsText(p)))
			MC.Open("Stats")
			KC.advance(0.3)
			p = H.giftsParts()
			T.check(not IC.IsOpen() and MC.IsOpen() and none(p), "daily window: (win 5) MenuController switching to Stats: still hidden",
				fmt("index %s, menu %s, %s", tostring(IC.IsOpen()), tostring(MC.IsOpen()), H.partsText(p)))
			MC.Close()
			KC.advance(0.4)
			p = H.giftsParts()
			T.check(not MC.IsOpen() and all(p), "daily window: (win 5) ...back within 0.4 s of MenuController closing it", fmt("menu %s, %s", tostring(MC.IsOpen()), H.partsText(p)))
			-- (gate fix) the in-game Settings window (the HUD pill's gear) is MainMenuController's, whose IsOpen() is the title
			-- screen only: it must hide the button too
			local MMC = H.moduleAt("client", "Controllers/MainMenuController")
			if MMC and MMC.OpenSettings and MMC.CloseWindows then
				MMC.OpenSettings()
				KC.advance(0.3)
				p = H.giftsParts()
				T.check(MMC.Window() ~= nil and not MMC.IsOpen() and none(p), "daily window: (win 5) the in-game Settings window hides the Gifts button, its ring and its pip",
					fmt("settings %s, %s", tostring(MMC.Window() ~= nil), H.partsText(p)))
				MMC.CloseWindows()
				KC.advance(0.4)
				p = H.giftsParts()
				T.check(MMC.Window() == nil and all(p), "daily window: (win 5) ...back within 0.4 s of Settings closing", H.partsText(p))
			else
				T.fail("daily window: (win 5) needs MainMenuController.OpenSettings / CloseWindows")
			end
			-- (owner 2026-11-13: before, the Gifts window kept its own button) its own window hides them at once and Close
			-- brings them back at once (no poll wait); the pip flow is the same as behind any window
			DC.Open()
			p = H.giftsParts()
			T.check(DC.IsOpen() and none(p), "daily window: (owner 2026-11-13) the Gifts window hides its own button, ring and pip at once", H.partsText(p))
			KC.advance(0.6)
			p = H.giftsParts()
			T.check(DC.IsOpen() and none(p), "daily window: (owner 2026-11-13) ...and keeps them hidden while open (the poll agrees)", H.partsText(p))
			DC.Close()
			p = H.giftsParts()
			T.check(not DC.IsOpen() and all(p), "daily window: (owner 2026-11-13) ...back at once on Close", H.partsText(p))
			KC.advance(0.3)
			-- (owner 2026-11-13) the NPC talk box hides them too, back within K.WINDOW_POLL of it closing. This world has no
			-- NPC models to talk to (client_pets builds and removes its own), so NpcController.IsOpen is stood in for with the
			-- real one's shape (true, npcId) on the very module table the watcher keeps
			local NC = H.moduleAt("client", "Controllers/NpcController")
			if NC and type(NC.IsOpen) == "function" then
				T.check(NC.IsOpen() == false, "daily window: (owner 2026-11-13) NpcController.IsOpen() is false with no talk box up", tostring(NC.IsOpen()))
				local realIsOpen = NC.IsOpen
				NC.IsOpen = function()
					return true, "sparky_fox"
				end
				KC.advance(0.3)
				p = H.giftsParts()
				local keptNpc = type(DC._S) == "table" and DC._S.WindowMods and DC._S.WindowMods.NpcController == NC
				NC.IsOpen = realIsOpen
				T.check(keptNpc and none(p), "daily window: (owner 2026-11-13) an open NPC talk box hides the Gifts button, its ring and its pip",
					fmt("watcher keeps NpcController %s, %s", tostring(keptNpc), H.partsText(p)))
				KC.advance(0.3)
				p = H.giftsParts()
				T.check(NC.IsOpen() == false and all(p), "daily window: (owner 2026-11-13) ...back within K.WINDOW_POLL of the talk box closing", H.partsText(p))
			else
				T.fail("daily window: (owner 2026-11-13) needs NpcController.IsOpen")
			end
			H.restoreTutorial(prevTutorial)
		else
			T.fail("daily window: (win 5) needs MenuController, PetsController and IndexController")
		end
		-- (review round 2) Open hides the button first; a build / layout / render that throws is undone: the window shut,
		-- S.Open false and the button back at once (a phone has no Esc to get out). H.render is stood in for on the
		-- module's own H table (DailyController._H) and restored
		local DH = DC._H
		if type(DH) == "table" and type(DH.render) == "function" then
			KC.advance(0.3)
			T.check(H.shown(btn) and not DC.IsOpen(), "daily window: (review round 2) (setup) the window shut and the Gifts button shown", H.partsText(H.giftsParts()))
			local realRender = DH.render
			DH.render = function()
				error("planted render error")
			end
			local o0 = #Mock.Output
			local okOpen, opened = pcall(DC.Open)
			DH.render = realRender
			local p = H.giftsParts()
			T.check(okOpen and opened == false and not DC.IsOpen() and DC._S.Open == false and DC._S.BackBound ~= true and not H.shown(H.win()) and p[1],
				"daily window: (review round 2) a render that throws in Open: Open returns false, S.Open false, no Back binding, the window hidden, the Gifts button back at once",
				fmt("pcall %s (%s), open %s, back %s, window %s, %s", tostring(okOpen), tostring(opened), tostring(DC._S.Open), tostring(DC._S.BackBound),
					tostring(H.shown(H.win())), H.partsText(p)))
			-- (the planted fault's warning belongs to this check: dropped, so the warn audit sees only real ones)
			for i = #Mock.Output, o0 + 1, -1 do
				local o = Mock.Output[i]
				if o.kind == "warn" and tostring(o.text):find("planted render error", 1, true) then
					table.remove(Mock.Output, i)
				end
			end
			DC.Open()
			KC.advance(0.3)
			T.check(DC.IsOpen() and H.shown(H.win()) and not H.shown(btn), "daily window: (review round 2) ...and the next Open builds the window as usual")
			DC.Close()
			KC.advance(0.3)
		else
			T.fail("daily window: (review round 2) needs DailyController._H.render")
		end
		-- InMatch closes it
		DC.Open()
		KC.advance(0.3)
		LocalPlayer:SetAttribute("InMatch", true)
		KC.advance(0.3)
		T.check(not DC.IsOpen() and not H.shown(btn), "daily window: a match closes the window and hides the button")
		LocalPlayer:SetAttribute("InMatch", nil)
		KC.advance(0.5)
		T.check(H.shown(btn), "daily window: the button is back after the match")
		DC.Close()
		w.restore()
		restoreScreen()
		KC.flushErrors("client_daily_window")
		KC.flushWarnings("client_daily_window")
	end)

	S.client_daily_pip = guarded("client_daily_pip", function()
		local restoreScreen = H.saveScreen()
		H.setScreen(1920, 1080, false)
		local DC = H.moduleAt("client", "Controllers/DailyController")
		local TC = H.moduleAt("client", "Controllers/TutorialController")
		if not T.check(DC ~= nil and H.btn() ~= nil, "daily pip: DailyController and its button exist") then
			restoreScreen()
			return
		end
		local prevTutorial = TC and TC.GetState and TC.GetState() or nil
		KC.toClient("TutorialState", H.tutorial("done", { Done = true, Completed = true }))
		KC.advance(0.2)
		local now = H.now()
		Mock.Respawn(LocalPlayer)
		KC.advance(0.2)
		H.fire(H.base(H.now()))
		T.check(DC.PipShown() == false and not H.shown(H.find(H.btn(), "Pip")), "daily pip: not right after a spawn (nothing is announced on join)")
		KC.advance(21)
		T.check(DC.PipShown() == true and H.shown(H.find(H.btn(), "Pip")), "daily pip: shown PipDelaySeconds after the spawn when a claim is ready")
		local pip = H.find(H.btn(), "Pip")
		local Theme = select(3, KC.env())
		T.check(pip ~= nil and pip.AbsoluteSize.X == 10 and pip.BackgroundColor3 == Theme.Sign.Red and pip:FindFirstChildOfClass("UICorner") == nil,
			"daily pip: a 10 px Sign red square (kit-b U8; was a Neon.Red dot)")
		KC.toClient("TutorialState", H.tutorial("shop"))
		KC.advance(0.2)
		T.eq(DC.PipShown(), false, "daily pip: not before the tutorial's spin step (Id shop, Step 3)")
		KC.toClient("TutorialState", H.tutorial("spin"))
		KC.advance(0.2)
		T.eq(DC.PipShown(), true, "daily pip: from the spin step on")
		KC.toClient("TutorialState", H.tutorial("done", { Done = true, Completed = true }))
		KC.advance(0.2)
		T.eq(DC.PipShown(), true, "daily pip: tutorial done")
		-- nothing ready: no pip; a ready play tier: the pip
		now = H.now()
		local none = H.base(now)
		none.ReadyAt = now + 3600
		H.fire(none)
		T.eq(DC.PipShown(), false, "daily pip: nothing ready, no pip")
		-- the shake: never on the first payload after a Loading one, then when a tier becomes Ready
		local btn = H.btn()
		local function moves(seconds)
			local base = btn.Position.X.Offset
			local moved = false
			local t = 0
			while t < seconds do
				KC.advance(0.05)
				t = t + 0.05
				if btn.Position.X.Offset ~= base then
					moved = true
				end
			end
			return moved, base
		end
		H.fire({ Loading = true })
		T.eq(DC.PipShown(), false, "daily pip: a Loading payload shows no pip")
		local first = H.base(now)
		first.ReadyAt = now + 3600
		first.Play.Tiers[4].Ready = true
		KC.toClient("DailyState", first)
		T.eq(moves(0.45), false, "daily pip: the first payload never shakes (not on join)")
		T.eq(DC.PipShown(), true, "daily pip: a Ready play tier shows the pip")
		local second = H.base(now)
		second.ReadyAt = now + 3600
		second.Play.Tiers[4].Ready, second.Play.Tiers[5].Ready = true, true
		local settled = btn.Position.X.Offset
		KC.toClient("DailyState", second)
		T.eq(moves(0.4), true, "daily pip: a tier that becomes Ready shakes the button within 0.4 s")
		KC.advance(0.3)
		T.eq(btn.Position.X.Offset, settled, "daily pip: ...then it settles")
		-- the ring: Play.Seconds / the next tier's seconds, dimmed while paused
		H.fire(H.base(now))
		local ring = H.find(btn.Parent, "Ring")
		local fill = ring and ring:GetAttribute("Fill")
		T.check(type(fill) == "number" and abs(fill - 47 / 60) <= 0.02, "daily pip: the ring fills 47/60 toward the 60 min tier", tostring(fill))
		local strokeT = function()
			local worst = 1
			for _, d in ipairs(ring and ring:GetDescendants() or {}) do
				if d:IsA("UIStroke") then
					worst = math.min(worst, d.Transparency)
				end
			end
			return worst
		end
		T.check(ring ~= nil and strokeT() < 0.4, "daily pip: the ring is bright while the clock counts", tostring(strokeT()))
		local paused = H.base(now)
		paused.Play.Active = false
		H.fire(paused)
		T.check(strokeT() >= 0.4, "daily pip: the ring dims to 40 % while Play.Active == false", tostring(strokeT()))
		-- the strips hide in a match: the button too
		LocalPlayer:SetAttribute("InMatch", true)
		KC.advance(0.3)
		T.check(not H.shown(btn) and DC.PipShown() == false, "daily pip: InMatch hides the button")
		LocalPlayer:SetAttribute("InMatch", nil)
		KC.advance(0.5)
		T.check(H.shown(btn), "daily pip: the button returns after the match")
		H.fire(H.base(H.now()))
		H.restoreTutorial(prevTutorial)
		restoreScreen()
		KC.flushErrors("client_daily_pip")
		KC.flushWarnings("client_daily_pip")
	end)

	S.client_daily_chips = guarded("client_daily_chips", function()
		local restoreScreen = H.saveScreen()
		H.setScreen(1920, 1080, false)
		local BB = H.moduleAt("client", "Controllers/BoostBadgeController")
		local MC = H.moduleAt("client", "Controllers/MenuController")
		if not T.check(BB ~= nil and type(BB.Chips) == "function", "daily chips: BoostBadgeController exists") then
			restoreScreen()
			return
		end
		local w = H.watchMenu(MC)
		local oldPasses, oldEnds = LocalPlayer:GetAttribute("OwnedPasses"), LocalPlayer:GetAttribute("XpBoostEnds")
		LocalPlayer:SetAttribute("OwnedPasses", "")
		LocalPlayer:SetAttribute("XpBoostEnds", 0)
		KC.advance(1.1)
		T.check(BB.Chips().Cash == false and BB.Chips().Xp == nil, "daily chips: none without a pass or a potion")
		LocalPlayer:SetAttribute("OwnedPasses", "Cash2x")
		KC.advance(0.2)
		local hud = H.pg():FindFirstChild("NimbusHud")
		local bottom = hud and hud:GetAttribute("TopRightBottom") or 0
		local chip = H.find(H.pg():FindFirstChild("NimbusBoosts"), "Chip_Cash")
		local gui = H.pg():FindFirstChild("NimbusBoosts")
		T.check(BB.Chips().Cash == true and H.shown(chip) and tostring(chip.Text) == "x2 Cash", "daily chips: OwnedPasses Cash2x -> the x2 Cash chip")
		T.check(chip ~= nil and abs(chip.AbsolutePosition.Y - (bottom + 4)) <= 1 and abs(chip.AbsolutePosition.X + chip.AbsoluteSize.X - (gui.AbsoluteSize.X - 12)) <= 1,
			"daily chips: right-aligned under the strips at TopRightBottom + 4",
			chip and fmt("chip %d,%d %dx%d; TopRightBottom %s, gui %d", chip.AbsolutePosition.X, chip.AbsolutePosition.Y, chip.AbsoluteSize.X, chip.AbsoluteSize.Y, tostring(bottom), gui.AbsoluteSize.X) or "no chip")
		T.check(chip ~= nil and chip.AbsoluteSize.Y == 24 and chip.AbsoluteSize.X >= 46, "daily chips: 46x24 at 1080p", chip and fmt("%dx%d", chip.AbsoluteSize.X, chip.AbsoluteSize.Y) or "")
		local now = H.now()
		LocalPlayer:SetAttribute("XpBoostEnds", now + 3600) -- one fresh 1 h potion
		KC.advance(0.2)
		T.check(w.count("x2 Pet XP started!") == 1, "daily chips: the hint when the potion starts", w.last())
		LocalPlayer:SetAttribute("XpBoostEnds", now + 58 * 60)
		KC.advance(0.2)
		T.eq(BB.Chips().Xp, "x2 XP " .. DOT .. " 58m", "daily chips: the potion's chip with its time left")
		KC.advance(60)
		T.eq(BB.Chips().Xp, "x2 XP " .. DOT .. " 57m", "daily chips: the time left counts down")
		local xchip = H.find(gui, "Chip_Xp")
		local Theme = select(3, KC.env())
		T.check(H.shown(xchip) and xchip.BackgroundColor3 ~= nil and chip.Parent == xchip.Parent, "daily chips: both chips in the one holder")
		LocalPlayer:SetAttribute("OwnedPasses", "PetXp2x")
		LocalPlayer:SetAttribute("XpBoostEnds", 0)
		KC.advance(0.2)
		T.check(BB.Chips().Xp == "x2 XP" and BB.Chips().Cash == false, "daily chips: the pass's x2 XP (no timer)", tostring(BB.Chips().Xp))
		LocalPlayer:SetAttribute("OwnedPasses", "")
		now = H.now()
		LocalPlayer:SetAttribute("XpBoostEnds", now + 303)
		KC.advance(1.1)
		T.eq(w.count("ends in 5 min"), 0, "daily chips: no warning above WarnSeconds")
		KC.advance(4)
		T.eq(w.count("x2 Pet XP ends in 5 min"), 1, "daily chips: the hint when the potion crosses WarnSeconds")
		KC.advance(5)
		T.eq(w.count("ends in 5 min"), 1, "daily chips: ...once")
		LocalPlayer:SetAttribute("InBattle", "B1")
		KC.advance(0.3)
		T.check(not H.shown(H.find(gui, "Chip_Xp")), "daily chips: hidden with the strips in a battle")
		LocalPlayer:SetAttribute("InBattle", nil)
		LocalPlayer:SetAttribute("OwnedPasses", oldPasses)
		LocalPlayer:SetAttribute("XpBoostEnds", oldEnds)
		KC.advance(0.3)
		w.restore()
		restoreScreen()
		KC.flushErrors("client_daily_chips")
		KC.flushWarnings("client_daily_chips")
	end)

	S.client_daily_vip = guarded("client_daily_vip", function()
		local VC = H.moduleAt("client", "Controllers/VipController")
		local GQ = H.moduleAt("client", "GraphicsQuality")
		if not T.check(VC ~= nil and type(VC.IsVip) == "function", "daily vip: VipController exists") then
			return
		end
		local oldPasses = LocalPlayer:GetAttribute("OwnedPasses")
		LocalPlayer:SetAttribute("OwnedPasses", "")
		T.eq(VC.IsVip(LocalPlayer), false, "daily vip: no pass, not VIP")
		LocalPlayer:SetAttribute("OwnedPasses", "Cash2x,VIP")
		T.eq(VC.IsVip(LocalPlayer), true, "daily vip: OwnedPasses contains VIP")
		LocalPlayer:SetAttribute("OwnedPasses", "VIPX")
		T.eq(VC.IsVip(LocalPlayer), false, "daily vip: a csv entry, not a substring")
		LocalPlayer:SetAttribute("OwnedPasses", "VIP")
		local TCS = game:GetService("TextChatService")
		local cb = TCS.OnIncomingMessage
		T.check(type(cb) == "function", "daily vip: TextChatService.OnIncomingMessage is set")
		-- TextChatMessageProperties is not a mock class: a plain table stands in for this call only
		local realNew = Instance.new
		local function call(message)
			Instance.new = function(class, parent)
				if class == "TextChatMessageProperties" then
					return {}
				end
				return realNew(class, parent)
			end
			local ok, result = pcall(cb, message)
			Instance.new = realNew
			return ok, result
		end
		local GOLD = '<font color="#FFC440">'
		if type(cb) == "function" then
			local ok, props = call({ TextSource = { UserId = LocalPlayer.UserId }, PrefixText = "Me:", Text = "hi" })
			T.check(ok and type(props) == "table" and type(props.PrefixText) == "string" and props.PrefixText:sub(1, #(GOLD .. "[VIP]</font> ")) == GOLD .. "[VIP]</font> "
				and props.PrefixText:find(GOLD .. "Me:</font>", 1, true) ~= nil, "daily vip: a VIP's message gets the gold [VIP] tag and a gold name", ok and tostring(props and props.PrefixText) or tostring(props))
			LocalPlayer:SetAttribute("OwnedPasses", "")
			local ok2, plain = call({ TextSource = { UserId = LocalPlayer.UserId }, PrefixText = "Me:", Text = "hi" })
			T.check(ok2 and (plain == nil or plain.PrefixText == nil), "daily vip: a non-VIP's message is unchanged", tostring(plain))
			local ok3, system = call({ PrefixText = "", Text = "system" })
			T.check(ok3 and system == nil, "daily vip: a system message (no TextSource) is unchanged")
		end
		-- the lobby crown
		local p2 = Mock.AddPlayer("VipBuddy", 983711)
		KC.advance(0.5)
		local function crown()
			local char = p2.Character
			return char and H.find(char, "VipCrown")
		end
		T.check(crown() == nil, "daily vip: no crown without the pass")
		if GQ then
			GQ.Apply("High")
		end
		p2:SetAttribute("OwnedPasses", "VIP")
		KC.advance(0.3)
		local c = crown()
		T.check(c ~= nil and c:IsA("BillboardGui") and c.Enabled and c.MaxDistance == 60 and abs(c.StudsOffset.Y - 2.4) < 1e-6, "daily vip: a VIP's character gets the VipCrown billboard on High",
			c and fmt("enabled %s, max %s, offset %s", tostring(c.Enabled), tostring(c.MaxDistance), tostring(c.StudsOffset)) or "none")
		local glyph = c and H.find(c, "Icon")
		T.check(glyph ~= nil and glyph:GetAttribute("PixelIcon") == "crown", "daily vip: the crown shows the VipCrown icon (kit-b U7a: the pixel crown)")
		p2:SetAttribute("InBattle", "B7")
		KC.advance(0.3)
		c = crown()
		T.check(c == nil or c.Enabled == false, "daily vip: hidden while that player is InBattle")
		p2:SetAttribute("InBattle", nil)
		KC.advance(0.3)
		c = crown()
		T.check(c ~= nil and c.Enabled, "daily vip: back after the battle")
		if GQ then
			GQ.Apply("Low")
			KC.advance(1.2)
			c = crown()
			T.check(c == nil or c.Enabled == false, "daily vip: no crown on Low")
			GQ.Apply("High")
			KC.advance(1.2)
			c = crown()
			T.check(c ~= nil and c.Enabled, "daily vip: the crown is back on High")
		end
		Mock.Respawn(p2)
		KC.advance(0.5)
		c = crown()
		T.check(c ~= nil and c.Enabled, "daily vip: a respawned VIP gets the crown again")
		p2:SetAttribute("OwnedPasses", "")
		KC.advance(0.3)
		T.check(crown() == nil or not crown().Enabled, "daily vip: the crown goes with the pass")
		p2:SetAttribute("OwnedPasses", "VIP")
		KC.advance(0.3)
		Mock.RemovePlayer(p2)
		KC.advance(0.3)
		local left = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			if d.Name == "VipCrown" then
				left = left + 1
			end
		end
		T.eq(left, 0, "daily vip: removed on leave")
		LocalPlayer:SetAttribute("OwnedPasses", oldPasses)
		KC.advance(0.3)
		for _, d in ipairs(workspace:GetDescendants()) do
			if d.Name == "VipCrown" then
				d:Destroy()
			end
		end
		KC.flushErrors("client_daily_vip")
		KC.flushWarnings("client_daily_vip")
	end)

	S.client_daily_mobile = guarded("client_daily_mobile", function()
		local restoreScreen = H.saveScreen()
		H.setScreen(844, 390, true)
		local DC = H.moduleAt("client", "Controllers/DailyController")
		local BB = H.moduleAt("client", "Controllers/BoostBadgeController")
		local now = H.now()
		H.fire(H.base(now))
		local btn = H.btn()
		if not T.check(DC ~= nil and btn ~= nil and btn.AbsoluteSize.X == 44 and btn.AbsoluteSize.Y == 44, "daily mobile: the Gifts button is 44x44 on 844x390",
			btn and fmt("%dx%d", btn.AbsoluteSize.X, btn.AbsoluteSize.Y) or "no button") then
			restoreScreen()
			return
		end
		local hud = H.pg():FindFirstChild("NimbusHud")
		-- (kit-b U8, restated: was 8 px left of the strips at y 6) docked under the strips where the HUD says
		local gl, gt = hud and hud:GetAttribute("GiftLeft") or -1, hud and hud:GetAttribute("GiftTop") or -1
		T.check(abs(btn.AbsolutePosition.X - gl) <= 1 and abs(btn.AbsolutePosition.Y - gt) <= 1, "daily mobile: docked under the strips (GiftLeft / GiftTop)",
			fmt("x %d, y %d, dock %s,%s", btn.AbsolutePosition.X, btn.AbsolutePosition.Y, tostring(gl), tostring(gt)))
		H.tap(btn)
		local win = H.win()
		local gui = H.gui()
		-- (gui-redo Task 9: the BigRect window, 820x330 at 12,59 on 844x390; it was a 560x300 drop-down under the button)
		T.check(DC.IsOpen() and win ~= nil and abs(win.AbsoluteSize.X - 820) <= 1 and abs(win.AbsoluteSize.Y - 330) <= 1 and DC.Layout() == "Phone",
			"daily mobile: the window is 820x330 at scale 1 (Phone)", win and fmt("%dx%d %s", win.AbsoluteSize.X, win.AbsoluteSize.Y, tostring(DC.Layout())) or "none")
		T.check(H.inBox(win, DC) and abs(win.AbsolutePosition.X - 12) <= 1 and abs(win.AbsolutePosition.Y + 58 - 59) <= 1
			and win.AbsolutePosition.Y >= 0 and win.AbsolutePosition.Y + win.AbsoluteSize.Y <= gui.AbsoluteSize.Y,
			"daily mobile: centred at 12,59, inside the screen", win and fmt("%d,%d in %dx%d", win.AbsolutePosition.X, win.AbsolutePosition.Y, gui.AbsoluteSize.X, gui.AbsoluteSize.Y) or "")
		local cell = H.cell(1)
		T.check(cell ~= nil and abs(cell.AbsoluteSize.X - 92) <= 1 and abs(cell.AbsoluteSize.Y - 122) <= 1, "daily mobile: tiles 92x122", cell and fmt("%dx%d", cell.AbsoluteSize.X, cell.AbsoluteSize.Y) or "")
		-- (slop-audit win 6, Review Focus 5) the phone layout re-sizes the X (56 -> 44 px): the drawn mark follows it
		local closeIssues = H.closeMarkIssues(H.find(win, "CloseButton"))
		T.check(#closeIssues == 0, "daily mobile: the 44 px CloseButton keeps its drawn X centred", table.concat(closeIssues, "; "))
		local claim = H.claimButton()
		T.check(claim ~= nil and abs(claim.AbsoluteSize.X - 230) <= 1 and abs(claim.AbsoluteSize.Y - 64) <= 1, "daily mobile: CLAIM! 230x64", claim and fmt("%dx%d", claim.AbsoluteSize.X, claim.AbsoluteSize.Y) or "")
		local function smallest(root)
			local min, which = math.huge, ""
			for _, d in ipairs(KC.texts(root, true)) do
				if tostring(d.Text):gsub("%s", "") ~= "" and d.TextSize < min then
					min, which = d.TextSize, d:GetFullName()
				end
			end
			return min, which
		end
		local m, which = smallest(win)
		T.check(m >= 15, "daily mobile: texts >= 15 (Daily)", fmt("%s at %s", tostring(m), which))
		H.tapTab("Play time")
		m, which = smallest(win)
		T.check(m >= 15 and H.rowCount() == 7, "daily mobile: texts >= 15 (Play time), 7 rows", fmt("%s at %s, %d rows", tostring(m), which, H.rowCount()))
		local inside = true
		for i = 1, 7 do
			local r = H.row(i)
			if not r or r.AbsolutePosition.Y + r.AbsoluteSize.Y > win.AbsolutePosition.Y + win.AbsoluteSize.Y + 1 or r.AbsolutePosition.X + r.AbsoluteSize.X > win.AbsolutePosition.X + win.AbsoluteSize.X + 1 then
				inside = false
			end
		end
		T.check(inside, "daily mobile: every tier cell inside the window")
		DC.Close()
		KC.advance(0.3)
		local oldPasses = LocalPlayer:GetAttribute("OwnedPasses")
		LocalPlayer:SetAttribute("OwnedPasses", "Cash2x")
		KC.advance(0.3)
		local chip = H.find(H.pg():FindFirstChild("NimbusBoosts"), "Chip_Cash")
		T.check(BB ~= nil and chip ~= nil and H.shown(chip) and chip.AbsoluteSize.Y == 18 and chip.AbsoluteSize.X >= 34 and chip.TextSize == 15, "daily mobile: chips 34x18 text 15",
			chip and fmt("%dx%d text %s", chip.AbsoluteSize.X, chip.AbsoluteSize.Y, tostring(chip.TextSize)) or "none")
		LocalPlayer:SetAttribute("OwnedPasses", oldPasses)
		KC.advance(0.3)
		restoreScreen()
		KC.flushErrors("client_daily_mobile")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
