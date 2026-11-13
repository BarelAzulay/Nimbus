-- smoke_redo_daily_ui.lua: the Gifts window redone (docs/superpowers/specs/2026-11-06-window-redo-design.md 5.1, 5.3 "Layout"
-- and "The window while locked"; plan docs/superpowers/plans/2026-11-06-window-redo.md Task 9): DailyController as a big
-- centred window (NeonKit.BigRect, 1180 x 720 at 1080p, 820 x 330 on a landscape phone) and its Daily page (card A: glossy
-- day tiles, today raised and gold, Day 7 double-wide with the Week Wisp, the Wisp line and bar, one big CLAIM and the keep
-- line), with the 10-minute lock read from the payload's Unlock { Need, Left }. Client and phone worlds only (client_files,
-- loaded after smoke_redo_geom.lua, whose RedoGeom it uses):
--   client_daily_ui_a      (1920x1080, then 844x390 touch) a ready payload: the window centred in its BigRect box (the Gifts
--                          button stays where it is, hidden while the window is open: owner 2026-11-13), seven tiles, today (Cell3) raised 8 px over Cell2 with the same
--                          bottom, gold and reading "TODAY", Day 7 twice a tile plus the gap with the Week Wisp's viewport,
--                          claimed tiles dimmed with their tick, the header, the streak chip, "Week Wisp in 4 more days"
--                          over the seven-segment bar (claimed / today / open), CLAIM! active and one DailyRequest("Claim")
--                          per tap (none within 1 s), the wait (Countdown "Next gift in ...", the keep line, the next
--                          tile gold but reading its day), Day 7 today
--                          ("Week Wisp today!"), one day left ("in 1 more day"), Layout()
--   client_daily_locked    the pure DailyController.ClaimView(st, now, touch): Locked with "Unlocks after 10 min of play" and
--                          the second line by priority ("Day resets in N min" when the play-day ends before the unlock, else
--                          the paused text per device, else "N min to go", counting down from ServerNow while Active, held
--                          while paused, never below "1 min to go" without a payload), Claim / Repair / Wait / Stale /
--                          Loading, no Unlock field (an older server) = unlocked, Need 0 = the rule off; the window
--                          (1920x1080 and 844x390 touch): the locked CLAIM is greyed out and disabled, shows both lines
--                          (>= 15 px on the phone, fitting the real font widths inside 230 x 64), sends nothing, counts
--                          down on the window's tick, switches to CLAIM! on a payload with Left 0 without reopening; a
--                          locked repair keeps the wide repair button; the Gifts pip only when the claim is unlocked
--   client_daily_layouts   844x390 (touch), 1280x720, 1366x768, 1920x1080 (+ 667x375 touch): RedoGeom.check of
--                          DailyWindow (texts >= 14 px, targets >= 44 px, on the screen under the top bar, the named
--                          controls never overlap) for the ready, locked, wait and repair views and the Play tab; 844x390:
--                          an 820 x 330 box at 12,59 (centred), Layout() "Phone", Roblox's touch controls gone while it is
--                          open and back after; review fix: the HUD's vitals card hidden while the window is open (both
--                          tabs) and back after; a resize while open (1920x1080 -> 844x390 -> 1920x1080) passes each time
--   client_daily_portrait  (phone world, 390x844 touch; and 360x640) Layout() "Portrait", the day tiles four per row (Day 7
--                          the double tile of row 2), RedoGeom.check passes for the ready, locked and wait views and the
--                          Play tab
-- Task 10 (spec 5.4, the Play time page, card B: gift boxes with their own countdowns and CLAIM ALL):
--   client_play_ui_b       the pure DailyController.TierCountdown(i, st, now) ("13:00" mm:ss under an hour, "2h 13m" from
--                          an hour, counting from ServerNow only while Active, never below "0:01" without a payload, ""
--                          for a ready / claimed / missing tier or a Loading payload); the page (1920x1080, then 844x390
--                          touch): PlayHeader "47 min played today . Resets in 5h" (phone "47 min today . ..."), seven
--                          gift boxes (Time, Gift, Reward and one of Claim / Clock / Check), Tier3's CLAIM (its box
--                          pulsing, its gift bobbing), Tier4's clock "13:00" counting down on the window's tick, frozen
--                          while paused (the gold paused header; on touch "Paused: close this and move around!"), held
--                          at "0:01", CLAIM ALL (n) sending one DailyRequest("ClaimPlayAll") (none within 1 s), a box's
--                          CLAIM sending ClaimPlay(i), CLAIM ALL greyed out at 0 in the same place and size; review fix: a
--                          full Berry Basket (Amount 0) reads "Basket is full", keeps its CLAIM and is left out of CLAIM ALL
--   client_play_layouts    844x390 (touch), 1280x720, 1366x768, 1920x1080 (+ 667x375 touch): RedoGeom.check of the
--                          window on the Play tab (the named controls never overlap), with 3 ready and paused; every
--                          text fits with the real font widths; phone: seven boxes in one row (104 x 204 on 844x390,
--                          CLAIM ALL 166 x 44); PC: four boxes on top and three under, both rows centred (260 x 250 and
--                          CLAIM ALL 252 x 60 at 1080p)
--   client_play_portrait   (phone world, 390x844 touch; and 360x640) the boxes four per row (row 2 centred), the check
--                          passes, every text fits
-- Every payload is fired at the client with KC.toClient("DailyState", ...). Every scenario puts the screen, the input
-- flags and the tutorial state back and leaves the window closed. Deterministic: mock clock only. Plain Lua 5.1 syntax.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local fmt = string.format
local abs = math.abs

local function serverScenarios()
	return {}
end

local function clientScenarios()
	local S = {}
	local KC = _G.KC
	local Players = game:GetService("Players")
	local GuiService = game:GetService("GuiService")
	local LocalPlayer = Players.LocalPlayer
	local H = {}
	local DOT = "\194\183"
	local NAMES = { "Tab_Daily", "Tab_Play", "CloseButton", "Header", "StreakChip", "VipChip", "Cells", "WispText", "WispBar", "ClaimButton", "Keep" }

	function H.req(path)
		local root, rest = path:match("^(%a+)/(.+)$")
		local inst = Mock.GetPath(ROOTS[root] .. "/" .. rest)
		local ok, result = pcall(function()
			return inst and require(inst)
		end)
		return ok and type(result) == "table" and result or nil
	end
	function H.dc()
		return (KC.M and KC.M.DailyController) or H.req("client/Controllers/DailyController")
	end
	function H.kit()
		return H.req("client/UI/NeonKit")
	end
	function H.theme()
		return H.req("shared/Theme")
	end
	function H.pg()
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	function H.gui()
		return H.pg():FindFirstChild("NimbusDaily")
	end
	function H.win()
		return RedoGeom.find(H.gui(), "DailyWindow")
	end
	function H.find(name, root)
		return RedoGeom.find(root or H.win(), name)
	end
	function H.cell(i)
		return H.find("Cell" .. i, H.find("Cells"))
	end
	function H.shown(o)
		return o ~= nil and KC.isShown(o)
	end
	function H.text(o)
		return o and tostring(o.Text) or "<nil>"
	end
	function H.now()
		return workspace:GetServerTimeNow()
	end
	function H.fire(payload)
		KC.toClient("DailyState", payload)
		KC.advance(0.05)
	end
	function H.click(o)
		if o then
			Mock.Click(o)
		end
		KC.advance(0.3)
	end
	function H.sent(mark)
		return KC.serverCalls("DailyRequest", mark)
	end
	function H.texts(root)
		local out = {}
		for _, d in ipairs(root and KC.texts(root, true) or {}) do
			out[#out + 1] = tostring(d.Text)
		end
		return table.concat(out, " | ")
	end
	-- the abs box of a gui object: x, y, w, h
	function H.box(o)
		return o.AbsolutePosition.X, o.AbsolutePosition.Y, o.AbsoluteSize.X, o.AbsoluteSize.Y
	end
	function H.near(a, b, tol)
		return a ~= nil and b ~= nil and abs(a - b) <= (tol or 1)
	end
	function H.inside(o, outer)
		if not (o and outer) then
			return false
		end
		local x, y, w, h = H.box(o)
		local X, Y, W, Hh = H.box(outer)
		return x >= X - 1 and y >= Y - 1 and x + w <= X + W + 1 and y + h <= Y + Hh + 1
	end
	function H.disabled(b)
		return b ~= nil and (b:GetAttribute("Disabled") == true or b.Active == false)
	end
	-- the HUD's vitals card (NimbusHud > BottomLeft > Vitals)
	function H.vitals()
		local hud = H.pg():FindFirstChild("NimbusHud")
		return hud and RedoGeom.find(hud, "Vitals") or nil
	end
	-- the Week bar's segment states "Claimed,Claimed,Today,Open,..."
	function H.segs()
		local out = {}
		for i = 1, 7 do
			local s = H.find("Seg" .. i, H.find("WispBar"))
			out[i] = tostring(s and s:GetAttribute("State"))
		end
		return table.concat(out, ",")
	end

	-- the DailyState payload (smoke_daily_ui.lua H.base) with the 10-minute rule already met: Streak 2, Cell 3, Week 2, days
	-- 1-2 claimed, ready a second ago, 47 min played today, tiers 1-3 claimed
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
			Cell = 3, Vip = false, StepBack = 0, Days = days, ServerNow = now, StaleAt = 0,
			Unlock = { Need = 600, Left = 0 },
			Play = { Seconds = 47 * 60, DayEnds = now + 5 * 3600, Active = true, Tiers = tiers },
		}
	end
	-- ready but locked: `left` seconds of play to go
	function H.locked(now, left, active)
		local p = H.base(now)
		p.Unlock.Left = left
		p.Play.Active = active ~= false
		return p
	end
	-- not ready yet: the next gift in 19 h 59 m
	function H.wait(now)
		local p = H.base(now)
		p.Streak, p.Paid, p.Cell = 3, 3, 4
		p.Days[3].Claimed, p.Days[3].Today, p.Days[4].Today = true, false, true
		p.ReadyAt = now + 72000 - 60
		return p
	end
	-- a repair (smoke_fixr_daily_ui.lua H.repair): today's cell re-earns day 3 and pays nothing
	function H.repair(now)
		local p = H.base(now)
		p.Streak, p.Paid, p.Weeks = 3, 3, 0
		p.Repair = true
		p.Days[3].Repair = true
		p.ReadyAt = now - 30 * 3600
		p.KeepUntil = now - 2 * 3600
		return p
	end
	-- a TutorialState payload of the finished tutorial (smoke_daily_ui.lua H.tutorial("done"))
	function H.tutorialDone()
		local Steps = H.req("shared/TutorialSteps")
		local index = #Steps.Steps
		local step = Steps.Steps[index]
		return {
			Step = index, Total = #Steps.Steps, Id = step.Id, Title = step.Title, Text = step.Text, Target = step.Target,
			CompleteOn = step.CompleteOn, Hint = step.Hint, Button = step.Button, Gift = step.Gift == true,
			Done = true, Completed = true, Skipped = false, Reward = 0,
		}
	end
	function H.open(DC, tab)
		DC.Close()
		KC.advance(0.2)
		DC.Open({ Tab = tab or "Daily" })
		KC.advance(0.6)
	end
	-- runs fn(DC) with the window closed before and after, the base payload put back
	function H.with(label, fn)
		local DC = H.dc()
		if not T.check(DC ~= nil and type(DC.Open) == "function", label .. ": DailyController loads") then
			return
		end
		local ok, err = pcall(fn, DC)
		if not ok then
			T.fail(label .. ": error", tostring(err))
		end
		pcall(DC.Close)
		KC.advance(0.3)
		H.fire(H.base(H.now()))
		KC.flushErrors(label)
	end
	-- the window's box against the BigRect rule (screen px; NimbusDaily keeps the gui inset)
	function H.centred(DC, label)
		local NK = H.kit()
		local win = H.win()
		local r = NK and DC.K and NK.BigRect(DC.K)
		if not T.check(win ~= nil and r ~= nil, label .. ": the window and its BigRect box") then
			return
		end
		local x, y, w, h = H.box(win)
		T.check(H.near(x, r.x) and H.near(y + 58, r.y) and H.near(w, r.w) and H.near(h, r.h),
			label .. ": the window fills its BigRect box (centred under the top bar)", fmt("%s vs %d,%d %dx%d", RedoGeom.desc(win), r.x, r.y, r.w, r.h))
		T.check(H.near(x + w / 2, Mock.Viewport.X / 2), label .. ": ...centred across the screen", RedoGeom.desc(win))
	end

	------------------------------------------------------------------------------------------------
	S.client_daily_ui_a = guarded("client_daily_ui_a", function()
		for _, sz in ipairs({ { 1920, 1080, false, "PC" }, { 844, 390, true, "Phone" } }) do
			local label = fmt("daily ui a %dx%d", sz[1], sz[2])
			RedoGeom.at(sz[1], sz[2], sz[3], label, function()
				H.with(label, function(DC)
					local btn = RedoGeom.find(H.gui(), "GiftsButton")
					local bx, by = btn and btn.AbsolutePosition.X, btn and btn.AbsolutePosition.Y
					local now = H.now()
					H.fire(H.base(now))
					H.open(DC, "Daily")
					T.check(DC.IsOpen() and H.shown(H.win()), label .. ": the window opens")
					T.eq(DC.Layout(), sz[4], label .. ": Layout()")
					H.centred(DC, label)
					-- (owner 2026-11-13) the Gifts window hides its own button; it is still laid out where it was
					T.check(btn ~= nil and btn.AbsolutePosition.X == bx and btn.AbsolutePosition.Y == by and not H.shown(btn), label .. ": the Gifts button stays where it is, hidden while its window is open")
					-- the header and the chips
					T.eq(H.text(H.find("Header")), "DAY 3 OF 7 " .. DOT .. " WEEK 2", label .. ": the header") -- (kit-b U6: a Title-role text reads in capitals)
					T.eq(H.text(H.find("StreakChip")), sz[4] == "PC" and "Streak: 2 days" or "Streak: 2", label .. ": the streak chip")
					T.check(not H.shown(H.find("VipChip")), label .. ": no VIP chip without the pass")
					-- the tiles
					local c1, c2, c3, c7 = H.cell(1), H.cell(2), H.cell(3), H.cell(7)
					local n = 0
					for _, c in ipairs(H.find("Cells") and H.find("Cells"):GetChildren() or {}) do
						if c.Name:match("^Cell%d$") and H.shown(c) then
							n = n + 1
						end
					end
					T.eq(n, 7, label .. ": seven day tiles")
					if c1 and c2 and c3 and c7 then
						local _, y2, _, h2 = H.box(c2)
						local _, y3, _, h3 = H.box(c3)
						T.check(H.near(y2 - y3, 8) and H.near(y3 + h3, y2 + h2), label .. ": today (Cell3) is raised 8 px over Cell2, the bottoms level",
							RedoGeom.desc(c2) .. " / " .. RedoGeom.desc(c3))
						local Theme = H.theme()
						local stroke = c3:FindFirstChild("NeonStroke")
						T.check(c3:GetAttribute("Today") == true and stroke ~= nil and stroke.Color == Theme.Neon.Gold, label .. ": today is gold")
						T.eq(H.text(H.find("Day", c3)), "TODAY", label .. ": today's tile reads TODAY")
						T.eq(H.text(H.find("Day", c1)), "Day 1", label .. ": the others read their day")
						local x1, _, w1 = H.box(c1)
						local x2 = c2.AbsolutePosition.X
						local gap = x2 - (x1 + w1)
						T.check(gap > 0 and H.near(c7.AbsoluteSize.X, 2 * w1 + gap), label .. ": Day 7 is twice a tile plus the gap",
							fmt("tile %d, gap %d, day 7 %d", w1, gap, c7.AbsoluteSize.X))
						T.check(H.find("PetViewport", c7) ~= nil and H.text(H.find("Amount", c7)):find("Wisp", 1, true) ~= nil, label .. ": Day 7 shows the Week Wisp", H.text(H.find("Amount", c7)))
						T.check(H.shown(H.find("Check", c1)) and H.shown(H.find("Dim", c1)) and H.shown(H.find("Check", c2)) and not H.shown(H.find("Check", c3)),
							label .. ": claimed tiles are dimmed with their tick")
						T.check(H.text(H.find("Amount", c3)):find("1,450", 1, true) ~= nil, label .. ": today's amount", H.text(H.find("Amount", c3)))
					end
					-- the Week Wisp line and bar
					T.eq(H.text(H.find("WispText")), "Week Wisp in 4 more days", label .. ": the Wisp line")
					T.eq(H.segs(), "Claimed,Claimed,Today,Open,Open,Open,Open", label .. ": the seven-segment bar")
					-- CLAIM!
					local claim = H.find("ClaimButton")
					T.check(H.shown(claim) and claim.Text == "CLAIM!" and not H.disabled(claim) and not H.shown(H.find("Line1", claim)), label .. ": CLAIM! active",
						claim and (claim.Text .. " disabled " .. tostring(H.disabled(claim))) or "no button")
					local want = sz[4] == "PC" and { 360, 88 } or { 230, 64 }
					T.check(claim ~= nil and H.near(claim.AbsoluteSize.X, want[1]) and H.near(claim.AbsoluteSize.Y, want[2]), label .. fmt(": CLAIM! is %dx%d", want[1], want[2]), RedoGeom.desc(claim))
					T.check(H.shown(H.find("Keep")) and H.text(H.find("Keep")) == "Come back tomorrow to keep your streak!", label .. ": the keep line under it")
					local mark = #Mock.RemoteLog
					H.click(claim)
					local sent = H.sent(mark)
					T.check(#sent == 1 and sent[1].args[1] == "Claim", label .. ": CLAIM! -> DailyRequest(\"Claim\")", tostring(#sent))
					mark = #Mock.RemoteLog
					H.click(claim)
					T.eq(#H.sent(mark), 0, label .. ": a second tap within 1 s sends nothing")
					-- the wait after the claim
					H.fire(H.wait(now))
					KC.advance(1.1)
					local count = H.find("Countdown")
					T.check(not H.shown(H.find("ClaimButton")) and H.shown(count) and H.text(count):find("^Next gift in 19h 5%dm$") ~= nil and H.shown(H.find("Keep")),
						label .. ": the wait: the countdown and the keep line", H.text(count))
					T.check(H.cell(3):GetAttribute("Claimed") == true and H.cell(4):GetAttribute("Today") == true and H.text(H.find("Day", H.cell(4))) == "Day 4",
						label .. ": the wait: the next gift's tile stays gold but reads its day (TODAY only when it is due)", H.text(H.find("Day", H.cell(4))))
					-- Day 7 today, one day left
					local d7 = H.base(now)
					d7.Cell, d7.Streak, d7.Paid = 7, 6, 6
					for i = 1, 7 do
						d7.Days[i].Claimed, d7.Days[i].Today = i < 7, i == 7
					end
					H.fire(d7)
					T.eq(H.text(H.find("WispText")), "Week Wisp today!", label .. ": Day 7 today")
					T.eq(H.segs(), "Claimed,Claimed,Claimed,Claimed,Claimed,Claimed,Today", label .. ": ...the bar")
					local d6 = H.base(now)
					d6.Cell = 6
					H.fire(d6)
					T.eq(H.text(H.find("WispText")), "Week Wisp in 1 more day", label .. ": one day left")
				end)
			end)
		end
	end)

	------------------------------------------------------------------------------------------------
	S.client_daily_locked = guarded("client_daily_locked", function()
		local DC = H.dc()
		if not T.check(DC ~= nil and type(DC.ClaimView) == "function", "daily locked: DailyController.ClaimView exists") then
			return
		end
		-- the pure view
		local now = 1000000
		local function view(st, at, touch)
			local ok, v = pcall(DC.ClaimView, st, at or now, touch)
			return ok and type(v) == "table" and v or { Mode = "error: " .. tostring(v) }
		end
		local v = view(H.locked(now, 360, true))
		T.check(v.Mode == "Locked" and v.Line1 == "Unlocks after 10 min of play" and v.Line2 == "6 min to go", "daily locked: locked + Active -> 'Unlocks after 10 min of play' / '6 min to go'",
			fmt("%s / %s / %s", tostring(v.Mode), tostring(v.Line1), tostring(v.Line2)))
		T.eq(view(H.locked(now, 360, false), now, false).Line2, "Paused: move around!", "daily locked: paused on PC")
		T.eq(view(H.locked(now, 360, false), now, true).Line2, "Paused: close this and move!", "daily locked: paused on a touch device")
		local reset = H.locked(now, 360, true)
		reset.Play.DayEnds = now + 240
		T.eq(view(reset).Line2, "Day resets in 4 min", "daily locked: the play-day ends first -> 'Day resets in 4 min'")
		reset.Play.Active = false
		T.eq(view(reset, now, true).Line2, "Day resets in 4 min", "daily locked: ...before the paused text")
		local over = H.locked(now, 600, true)
		over.Play.DayEnds = now - 5 -- the play-day is over: the next tick starts a new one
		T.eq(view(over).Line2, "10 min to go", "daily locked: a play-day already over is not 'Day resets'")
		T.eq(view(H.locked(now, 360, true), now + 60).Line2, "5 min to go", "daily locked: the count goes 6 -> 5 after 60 s while Active")
		T.eq(view(H.locked(now, 360, false), now + 60, false).Line2, "Paused: move around!", "daily locked: ...not while paused")
		local stillLeft = H.locked(now, 360, false)
		T.eq(view(stillLeft, now + 60, false).Mode, "Locked", "daily locked: ...still locked")
		local hold = view(H.locked(now, 360, true), now + 900)
		T.check(hold.Mode == "Locked" and hold.Line2 == "1 min to go", "daily locked: never below '1 min to go' without a payload", fmt("%s / %s", tostring(hold.Mode), tostring(hold.Line2)))
		T.eq(view(H.locked(now, 0, true)).Mode, "Claim", "daily locked: Left 0 -> Claim")
		T.eq(view(H.locked(now, 0, true)).Line1, "CLAIM!", "daily locked: ...its text")
		local older = H.base(now)
		older.Unlock = nil
		T.eq(view(older).Mode, "Claim", "daily locked: a payload with no Unlock (an older server) is unlocked")
		local off = H.locked(now, 360, true)
		off.Unlock.Need = 0
		T.eq(view(off).Mode, "Claim", "daily locked: Need 0 (the rule off) is unlocked")
		local need5 = H.locked(now, 120, true)
		need5.Unlock.Need = 300
		T.eq(view(need5).Line1, "Unlocks after 5 min of play", "daily locked: the minutes come from Need")
		local rep = H.repair(now)
		T.check(view(rep).Mode == "Repair" and view(rep).Line1 == "Repair streak (no gift)", "daily locked: an unlocked repair", tostring(view(rep).Mode))
		rep.Unlock.Left = 300
		local rv = view(rep)
		T.check(rv.Mode == "Locked" and rv.Repair == true and rv.Line1 == "Unlocks after 10 min of play" and rv.Line2 == "5 min to go", "daily locked: a locked repair reads the same, marked Repair",
			fmt("%s %s / %s", tostring(rv.Mode), tostring(rv.Line1), tostring(rv.Line2)))
		local w = view(H.wait(now))
		T.check(w.Mode == "Wait" and tostring(w.Line1):find("^Next gift in 19h 59m$") ~= nil, "daily locked: not ready -> Wait 'Next gift in ...'", tostring(w.Line1))
		local rw = H.wait(now)
		rw.Repair = true
		T.check(tostring(view(rw).Line1):find("^Streak repair in ") ~= nil, "daily locked: a repair's wait -> 'Streak repair in ...'", tostring(view(rw).Line1))
		local lockedWait = H.wait(now)
		lockedWait.Unlock.Left = 600
		T.eq(view(lockedWait).Mode, "Wait", "daily locked: not ready wins over locked (the gift is not due yet)")
		local ld = view({ Loading = true })
		T.check(ld.Mode == "Loading" and ld.Line1 == "Getting your gifts ready...", "daily locked: Loading", tostring(ld.Mode))
		local st = H.base(now)
		st.StaleAt = now - 1
		T.check(view(st).Mode == "Stale" and view(st).Line1 == "Getting your gifts ready...", "daily locked: a stale payload", tostring(view(st).Mode))
		T.eq(view(nil).Mode, "Loading", "daily locked: no payload yet = Loading")

		-- the window
		for _, sz in ipairs({ { 1920, 1080, false, "PC" }, { 844, 390, true, "Phone" } }) do
			local label = fmt("daily locked %dx%d", sz[1], sz[2])
			RedoGeom.at(sz[1], sz[2], sz[3], label, function()
				H.with(label, function(DCx)
					local prevTutorial = nil
					local TC = H.req("client/Controllers/TutorialController")
					if TC and type(TC.GetState) == "function" then
						local okT, stT = pcall(TC.GetState)
						prevTutorial = okT and stT or nil
					end
					KC.toClient("TutorialState", H.tutorialDone())
					KC.advance(21) -- past the pip's delay after a spawn
					local t0 = H.now()
					H.fire(H.locked(t0, 360, true))
					H.open(DCx, "Daily")
					local claim = H.find("ClaimButton")
					local l1, l2 = H.find("Line1", claim), H.find("Line2", claim)
					T.check(H.shown(claim) and H.disabled(claim) and claim.Text == "", label .. ": the locked CLAIM is greyed out and disabled", claim and ("'" .. claim.Text .. "'") or "no button")
					T.check(H.shown(l1) and H.shown(l2) and l1.Text == "Unlocks after 10 min of play" and l2.Text:find("^%d min to go$") ~= nil,
						label .. ": ...its two lines", H.text(l1) .. " / " .. H.text(l2))
					local ok1, d1 = RedoGeom.fits(l1)
					local ok2, d2 = RedoGeom.fits(l2)
					T.check(ok1 and ok2 and H.inside(l1, claim) and H.inside(l2, claim), label .. ": ...both fit inside the button (real font widths)", d1 .. " / " .. d2)
					if sz[4] == "Phone" then
						T.check(claim and H.near(claim.AbsoluteSize.X, 230) and H.near(claim.AbsoluteSize.Y, 64), label .. ": the button stays 230 x 64", RedoGeom.desc(claim))
						T.check(l1 and l2 and l1.TextSize >= 15 and l2.TextSize >= 15, label .. ": both lines >= 15 px on the phone", fmt("%s / %s", tostring(l1 and l1.TextSize), tostring(l2 and l2.TextSize)))
					end
					local mark = #Mock.RemoteLog
					H.click(claim)
					T.eq(#H.sent(mark), 0, label .. ": tapping the locked button sends nothing")
					T.eq(DCx.PipShown(), false, label .. ": no pip while the claim is locked")
					local before = l2 and l2.Text
					KC.advance(60)
					T.check(l2 and l2.Text ~= before and l2.Text:find("^%d min to go$") ~= nil, label .. ": the minutes count down on the window's tick", tostring(before) .. " -> " .. H.text(l2))
					H.fire(H.locked(H.now(), 300, false))
					KC.advance(1.1)
					T.eq(H.text(l2), sz[3] and "Paused: close this and move!" or "Paused: move around!", label .. ": paused")
					-- a locked repair keeps the wide repair button
					local rp = H.repair(H.now())
					rp.Unlock.Left = 300
					H.fire(rp)
					KC.advance(0.2)
					local rw = claim.AbsoluteSize.X
					local rp2 = H.repair(H.now())
					H.fire(rp2)
					KC.advance(0.2)
					T.check(H.shown(claim) and claim.Text == "Repair streak (no gift)" and H.near(claim.AbsoluteSize.X, rw) and rw > (sz[4] == "PC" and 360 or 230) + 1,
						label .. ": a locked repair keeps the repair button's width", fmt("locked %d, unlocked %d '%s'", rw, claim.AbsoluteSize.X, claim.Text))
					-- the payload that unlocks it switches the open window
					H.fire(H.locked(H.now(), 360, true))
					KC.advance(0.2)
					H.fire(H.locked(H.now(), 0, true))
					KC.advance(0.2)
					T.check(DCx.IsOpen() and H.shown(claim) and claim.Text == "CLAIM!" and not H.disabled(claim) and not H.shown(l1), label .. ": a payload with Left 0 shows CLAIM! without reopening",
						claim.Text .. " disabled " .. tostring(H.disabled(claim)))
					-- (owner 2026-11-13) the open window hides the pip with its button: it shows once the window closes
					T.eq(DCx.PipShown(), false, label .. ": ...no pip while the window is open")
					mark = #Mock.RemoteLog
					H.click(claim)
					T.eq(#H.sent(mark), 1, label .. ": ...which claims")
					DCx.Close()
					T.eq(DCx.PipShown(), true, label .. ": ...and the pip once the window closes (the claim not answered yet)")
					KC.toClient("TutorialState", prevTutorial or H.tutorialDone())
					KC.advance(0.2)
				end)
			end)
		end
	end)

	------------------------------------------------------------------------------------------------
	-- RedoGeom.check of the window with the ready, locked, wait and repair views and the Play tab
	function H.checkViews(DC, label)
		local now = H.now()
		local vip = H.base(now)
		vip.Vip = true
		H.fire(vip)
		H.open(DC, "Daily")
		RedoGeom.check(H.win(), label .. " (ready)", { NoOverlap = NAMES })
		local lk = H.locked(now, 360, false)
		lk.Vip = true
		H.fire(lk)
		KC.advance(1.1)
		RedoGeom.check(H.win(), label .. " (locked)", { NoOverlap = NAMES })
		local claim = H.find("ClaimButton")
		local ok1, d1 = RedoGeom.fits(H.find("Line1", claim))
		local ok2, d2 = RedoGeom.fits(H.find("Line2", claim))
		T.check(ok1 and ok2, label .. " (locked): both lines fit (real font widths)", d1 .. " / " .. d2)
		local wt = H.wait(now)
		wt.Vip = true
		H.fire(wt)
		KC.advance(1.1)
		local waitNames = {}
		for _, n in ipairs(NAMES) do
			waitNames[#waitNames + 1] = n == "ClaimButton" and "Countdown" or n
		end
		RedoGeom.check(H.win(), label .. " (wait)", { NoOverlap = waitNames })
		local rp = H.repair(now)
		rp.Vip = true
		H.fire(rp)
		KC.advance(0.2)
		RedoGeom.check(H.win(), label .. " (repair)", { NoOverlap = NAMES })
		local okR, dR = RedoGeom.fits(H.find("ClaimButton"))
		T.check(okR, label .. " (repair): 'Repair streak (no gift)' fits its button", dR)
		H.fire(vip)
		DC.Open({ Tab = "Play" })
		KC.advance(0.5)
		RedoGeom.check(H.win(), label .. " (Play time)", { NoOverlap = { "Tab_Daily", "Tab_Play", "CloseButton", "Tiers" } })
		DC.Open({ Tab = "Daily" })
		KC.advance(0.3)
	end

	S.client_daily_layouts = guarded("client_daily_layouts", function()
		local sizes = { { 844, 390, true, "Phone" }, { 1280, 720, false, "PC" }, { 1366, 768, false, "PC" }, { 1920, 1080, false, "PC" }, { 667, 375, true, "Phone" } }
		for _, sz in ipairs(sizes) do
			local label = fmt("daily layouts %dx%d", sz[1], sz[2])
			RedoGeom.at(sz[1], sz[2], sz[3], label, function()
				H.with(label, function(DC)
					local touchBefore = GuiService.TouchControlsEnabled
					H.checkViews(DC, label)
					T.eq(DC.Layout(), sz[4], label .. ": Layout()")
					H.centred(DC, label)
					if sz[1] == 844 then
						local win = H.win()
						local x, y, w, h = H.box(win)
						T.check(H.near(x, 12) and H.near(y + 58, 59) and H.near(w, 820) and H.near(h, 330), label .. ": an 820 x 330 box at 12,59", RedoGeom.desc(win))
					end
					if sz[3] then
						T.check(GuiService.TouchControlsEnabled == false, label .. ": Roblox's touch controls go while it is open")
						DC.Close()
						KC.advance(0.4)
						T.check(GuiService.TouchControlsEnabled == touchBefore, label .. ": ...and come back after")
					end
					-- (review fix) the HUD's vitals card steps aside while the window is open: at 1080p the window's bottom edge
					-- cut the card in half, at 1280x720 its glow showed under the edge
					DC.Close()
					KC.advance(0.3)
					local vitals = H.vitals()
					T.check(vitals ~= nil and vitals.Visible == true, label .. ": (setup) the HUD's vitals card is shown with the window closed",
						vitals and tostring(vitals.Visible) or "no vitals card")
					H.open(DC, "Daily")
					T.check(vitals ~= nil and vitals.Visible == false, label .. ": the HUD's vitals card is hidden while the window is open")
					DC.Open({ Tab = "Play" })
					KC.advance(0.3)
					T.check(vitals ~= nil and vitals.Visible == false, label .. ": ...on the Play time page too")
					DC.Close()
					KC.advance(0.3)
					T.check(vitals ~= nil and vitals.Visible == true, label .. ": ...and back when it closes")
				end)
			end)
		end
		-- a resize while open
		RedoGeom.at(1920, 1080, false, "daily resize", function()
			H.with("daily resize", function(DC)
				local vip = H.base(H.now())
				vip.Vip = true
				H.fire(vip)
				H.open(DC, "Daily")
				RedoGeom.check(H.win(), "daily resize 1920x1080", { NoOverlap = NAMES })
				Mock.SetViewport(844, 390)
				KC.advance(0.6)
				T.check(DC.IsOpen() and H.shown(H.win()), "daily resize: still open at 844x390")
				RedoGeom.check(H.win(), "daily resize -> 844x390", { NoOverlap = NAMES })
				T.eq(DC.Layout(), "Phone", "daily resize: Phone at 844x390")
				Mock.SetViewport(1920, 1080)
				KC.advance(0.6)
				RedoGeom.check(H.win(), "daily resize -> 1920x1080", { NoOverlap = NAMES })
				T.eq(DC.Layout(), "PC", "daily resize: PC again")
			end)
		end)
	end)

	------------------------------------------------------------------------------------------------
	S.client_daily_portrait = guarded("client_daily_portrait", function()
		for _, sz in ipairs({ { 390, 844 }, { 360, 640 } }) do
			local label = fmt("daily portrait %dx%d", sz[1], sz[2])
			RedoGeom.at(sz[1], sz[2], true, label, function()
				H.with(label, function(DC)
					H.checkViews(DC, label)
					T.eq(DC.Layout(), "Portrait", label .. ": Layout()")
					local c = {}
					for i = 1, 7 do
						c[i] = H.cell(i)
					end
					if T.check(c[1] and c[4] and c[5] and c[7], label .. ": the tiles exist") then
						-- (Cell3 is today, raised: compare the bottoms of row 1)
						local function bottom(o)
							return o.AbsolutePosition.Y + o.AbsoluteSize.Y
						end
						T.check(H.near(bottom(c[1]), bottom(c[4])) and H.near(bottom(c[1]), bottom(c[3])) and c[5].AbsolutePosition.Y > bottom(c[1]) - 1
							and H.near(c[5].AbsolutePosition.X, c[1].AbsolutePosition.X), label .. ": four tiles per row, Day 5 starts row 2",
							RedoGeom.desc(c[1]) .. " / " .. RedoGeom.desc(c[4]) .. " / " .. RedoGeom.desc(c[5]))
						local gap = c[2].AbsolutePosition.X - (c[1].AbsolutePosition.X + c[1].AbsoluteSize.X)
						T.check(H.near(c[7].AbsoluteSize.X, 2 * c[1].AbsoluteSize.X + gap) and H.near(c[7].AbsolutePosition.X + c[7].AbsoluteSize.X, c[4].AbsolutePosition.X + c[4].AbsoluteSize.X),
							label .. ": Day 7 is the double tile at the end of row 2", RedoGeom.desc(c[7]))
					end
				end)
			end)
		end
	end)

	------------------------------------------------------------------------------------------------
	-- Task 10: the Play time page (card B)
	local PLAY_NAMES = { "Tab_Daily", "Tab_Play", "CloseButton", "PlayHeader", "ClaimAll", "Tier1", "Tier2", "Tier3", "Tier4", "Tier5", "Tier6", "Tier7" }
	-- the base payload with tier 3 Ready: 47 min played, tiers 1-2 claimed, 30 min ready, 60 min in 13 min; the play-day
	-- resets in 5 h 10 m (the header says "5h" all through a scenario)
	function H.play(now, active)
		local p = H.base(now)
		p.Play.Tiers[3].Claimed, p.Play.Tiers[3].Ready = false, true
		p.Play.Active = active ~= false
		p.Play.DayEnds = now + 5 * 3600 + 600
		return p
	end
	function H.tier(i)
		return H.find("Tier" .. i, H.find("Tiers"))
	end
	function H.part(i, name)
		return H.find(name, H.tier(i))
	end
	function H.claimAll()
		return H.find("ClaimAll")
	end
	-- the slot a box shows: "Claim" | "Clock" | "Check" (several joined with "+"; "none")
	function H.slot(i)
		local out = {}
		for _, name in ipairs({ "Claim", "Clock", "Check" }) do
			if H.shown(H.part(i, name)) then
				out[#out + 1] = name
			end
		end
		return #out > 0 and table.concat(out, "+") or "none"
	end
	-- TextService measures with the real font widths while fn runs (the controller then picks the texts Roblox would)
	function H.realMeasure(fn)
		game:GetService("TextService")
		local methods = Mock.Classes.TextService.methods
		local old = methods.GetTextSize
		methods.GetTextSize = function(_, text, size, font, frame)
			local w = RedoGeom.realWidth(text, size, font)
			local limit = (typeof(frame) == "Vector2" and frame.X > 0) and frame.X or math.huge
			if w <= limit then
				return Vector2.new(w, size)
			end
			return Vector2.new(limit, 2 * size)
		end
		local ok, err = pcall(fn)
		methods.GetTextSize = old
		if not ok then
			error(err, 0)
		end
	end
	-- every shown text under root fits its box with the real widths
	function H.allFit(root, label)
		local bad = {}
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and KC.isShown(d) then
				local ok, detail = RedoGeom.fits(d)
				if not ok then
					bad[#bad + 1] = detail
				end
			end
		end
		T.check(#bad == 0, label .. ": every text fits its box (real font widths)", table.concat(bad, "; "))
	end

	S.client_play_ui_b = guarded("client_play_ui_b", function()
		local DC = H.dc()
		if not T.check(DC ~= nil and type(DC.TierCountdown) == "function", "play ui b: DailyController.TierCountdown exists") then
			return
		end
		-- the pure countdown
		local now = 1000000
		local st = H.play(now)
		local function cd(i, at, s)
			local ok, v = pcall(DC.TierCountdown, i, s or st, at or now)
			return ok and v or ("error: " .. tostring(v))
		end
		T.eq(cd(4), "13:00", "play ui b: the 60 min gift at 47 min played -> '13:00'")
		T.eq(cd(4, now + 60), "12:00", "play ui b: ...'12:00' a minute later while Active")
		T.eq(cd(4, now + 61.5), "11:59", "play ui b: ...the seconds tick (mm:ss)")
		T.eq(cd(5), "43:00", "play ui b: the 90 min gift -> '43:00'")
		T.eq(cd(6), "1h 13m", "play ui b: the 120 min gift -> '1h 13m'")
		T.eq(cd(7), "2h 13m", "play ui b: the 180 min gift (2 h away) -> '2h 13m'")
		local paused = H.play(now, false)
		T.eq(cd(4, now + 600, paused), "13:00", "play ui b: frozen while the clock is paused")
		local edge = H.play(now)
		edge.Play.Seconds = 0
		T.eq(cd(4, now, edge), "1h 0m", "play ui b: exactly an hour -> '1h 0m'")
		edge.Play.Seconds = 1
		T.eq(cd(4, now, edge), "59:59", "play ui b: under an hour -> mm:ss")
		local near = H.play(now)
		near.Play.Seconds = 60 * 60 - 5
		T.eq(cd(4, now, near), "0:05", "play ui b: five seconds left -> '0:05'")
		T.eq(cd(4, now + 30, near), "0:01", "play ui b: never below '0:01' until a payload marks it Ready")
		T.eq(cd(3), "", "play ui b: a Ready tier has no countdown")
		T.eq(cd(1), "", "play ui b: a claimed tier has no countdown")
		T.eq(cd(9), "", "play ui b: no such tier")
		T.eq(cd(4, now, { Loading = true }), "", "play ui b: a Loading payload counts nothing")

		-- the page
		for _, sz in ipairs({ { 1920, 1080, false, "PC" }, { 844, 390, true, "Phone" } }) do
			local label = fmt("play ui b %dx%d", sz[1], sz[2])
			RedoGeom.at(sz[1], sz[2], sz[3], label, function()
				H.with(label, function(DCx)
					local Theme = H.theme()
					local t0 = H.now()
					H.fire(H.play(t0))
					H.open(DCx, "Play")
					T.check(H.shown(H.find("PlayPage")) and not H.shown(H.find("DailyPage")), label .. ": the Play page is shown")
					local header = H.find("PlayHeader")
					local want = (sz[4] == "PC" and "47 min played today " or "47 min today ") .. DOT .. " Resets in 5h"
					T.eq(H.text(header), want, label .. ": the header")
					-- the boxes
					local n = 0
					for _, c in ipairs(H.find("Tiers") and H.find("Tiers"):GetChildren() or {}) do
						if c.Name:match("^Tier%d$") and H.shown(c) then
							n = n + 1
						end
					end
					T.eq(n, 7, label .. ": seven gift boxes")
					local times, ok = {}, true
					for i, m in ipairs({ 10, 20, 30, 60, 90, 120, 180 }) do
						times[i] = H.text(H.part(i, "Time"))
						if times[i] ~= m .. " min" then
							ok = false
						end
					end
					T.check(ok, label .. ": each box says its minutes on top", table.concat(times, ", "))
					T.check(H.find("Icon", H.part(1, "Gift")) ~= nil and H.text(H.part(1, "Reward")) == "+$200", label .. ": the gift art and the resolved reward", H.text(H.part(1, "Reward")))
					T.check(H.slot(1) == "Check" and H.shown(H.part(1, "Dim")) and H.tier(1):GetAttribute("State") == "Claimed", label .. ": a claimed box: the tick, dimmed", H.slot(1))
					local claim3 = H.part(3, "Claim")
					T.check(H.slot(3) == "Claim" and claim3.Text == "CLAIM" and H.tier(3):GetAttribute("State") == "Ready", label .. ": the ready box: CLAIM", H.slot(3))
					T.check(H.tier(3):GetAttribute("Pulsing") == true and H.part(3, "Gift"):GetAttribute("Bobbing") == true
						and H.tier(4):GetAttribute("Pulsing") ~= true and H.part(4, "Gift"):GetAttribute("Bobbing") ~= true, label .. ": ...its box pulses and its gift bobs (only that one)")
					T.check(H.slot(4) == "Clock" and H.text(H.part(4, "Clock")) == "13:00" and H.tier(4):GetAttribute("State") == "Locked", label .. ": the next box: its clock '13:00'",
						H.slot(4) .. " '" .. H.text(H.part(4, "Clock")) .. "'")
					T.eq(H.text(H.part(5, "Clock")), "43:00", label .. ": the 90 min box '43:00'")
					T.eq(H.text(H.part(7, "Clock")), "2h 13m", label .. ": the 180 min box '2h 13m'")
					-- CLAIM ALL
					local all = H.claimAll()
					local size = sz[4] == "PC" and { 252, 60 } or { 166, 44 }
					T.check(H.shown(all) and all.Text == "CLAIM ALL (1)" and not H.disabled(all), label .. ": CLAIM ALL (1)", all and all.Text or "missing")
					T.check(all ~= nil and H.near(all.AbsoluteSize.X, size[1]) and H.near(all.AbsoluteSize.Y, size[2]), label .. fmt(": CLAIM ALL is %dx%d", size[1], size[2]), RedoGeom.desc(all))
					-- the countdown on the window's tick
					KC.advance(60)
					local c4 = H.text(H.part(4, "Clock"))
					T.check(c4 == "12:00" or c4 == "12:01", label .. ": a minute later the clock reads 12:00 (the window's 1 s tick)", c4)
					DCx.Open({ Tab = "Play" }) -- (a render now, off the tick's phase)
					T.eq(H.text(H.part(4, "Clock")), "12:00", label .. ": ...exactly 12:00 on a render now")
					T.check(H.text(header):find("^48 min ") ~= nil, label .. ": ...and the header counts the live minutes", H.text(header))
					-- paused: frozen, the gold paused header
					H.fire(H.play(H.now(), false))
					KC.advance(1.1)
					T.eq(H.text(header), sz[3] and "Paused: close this and move around!" or "Paused: move around to keep counting!", label .. ": the paused header")
					T.check(header ~= nil and header.TextColor3 == Theme.Neon.Gold, label .. ": ...in gold")
					KC.advance(30)
					T.eq(H.text(H.part(4, "Clock")), "13:00", label .. ": the clock holds while paused")
					-- one second left, no payload: it holds at 0:01
					local nearP = H.play(H.now())
					nearP.Play.Seconds = 60 * 60 - 1
					H.fire(nearP)
					KC.advance(5)
					T.check(H.text(H.part(4, "Clock")) == "0:01" and H.slot(4) == "Clock", label .. ": it holds at '0:01' until a payload says Ready", H.slot(4) .. " '" .. H.text(H.part(4, "Clock")) .. "'")
					-- the payload that marks it Ready: CLAIM, and its border bright at once (not only on the next pulse)
					local stroke4 = H.tier(4):FindFirstChild("NeonStroke")
					local dimBefore = stroke4 and stroke4.Transparency or -1
					local readyP = H.play(H.now())
					readyP.Play.Seconds = 60 * 60 + 5
					readyP.Play.Tiers[4].Ready = true
					KC.toClient("DailyState", readyP)
					KC.advance(0.02)
					T.check(H.slot(4) == "Claim" and dimBefore > 0.3 and stroke4.Transparency < 0.05, label .. ": the Ready payload: CLAIM, the border bright at once",
						fmt("%s, border %.2f -> %.2f", H.slot(4), dimBefore, stroke4 and stroke4.Transparency or -1))
					-- CLAIM ALL sends one request
					H.fire(H.play(H.now()))
					KC.advance(1.1)
					local box = { all.AbsolutePosition.X, all.AbsolutePosition.Y, all.AbsoluteSize.X, all.AbsoluteSize.Y }
					local mark = #Mock.RemoteLog
					H.click(all)
					local sent = H.sent(mark)
					T.check(#sent == 1 and sent[1].args[1] == "ClaimPlayAll" and sent[1].args[2] == nil, label .. ": CLAIM ALL -> one DailyRequest(\"ClaimPlayAll\")", tostring(#sent))
					mark = #Mock.RemoteLog
					H.click(all)
					T.eq(#H.sent(mark), 0, label .. ": a second tap within 1 s sends nothing")
					-- one box's CLAIM
					KC.advance(1.1)
					mark = #Mock.RemoteLog
					H.click(H.part(3, "Claim"))
					sent = H.sent(mark)
					T.check(#sent == 1 and sent[1].args[1] == "ClaimPlay" and sent[1].args[2] == 3, label .. ": a box's CLAIM -> DailyRequest(\"ClaimPlay\", 3)", tostring(#sent))
					-- three ready
					local three = H.play(H.now())
					three.Play.Seconds = 95 * 60
					three.Play.Tiers[4].Ready, three.Play.Tiers[5].Ready = true, true
					H.fire(three)
					T.eq(all.Text, "CLAIM ALL (3)", label .. ": three ready -> CLAIM ALL (3)")
					-- (review fix) a full Berry Basket (the server resolves the tier to Amount 0) pays nothing: its box says so
					-- and CLAIM ALL leaves it for its own CLAIM
					local full = H.play(H.now())
					full.Play.Seconds = 125 * 60
					full.Play.Tiers[4].Claimed, full.Play.Tiers[5].Claimed = true, true
					full.Play.Tiers[6].Ready, full.Play.Tiers[6].Amount = true, 0
					H.fire(full)
					local reward6 = H.text(H.part(6, "Reward"))
					T.check(all.Text == "CLAIM ALL (1)" and H.slot(6) == "Claim", label .. ": a full Basket (Amount 0): CLAIM ALL (1) counts tier 3 only; the box keeps its CLAIM",
						all.Text .. " / " .. H.slot(6))
					T.check(reward6:find("full", 1, true) ~= nil and reward6:find("Full Berry", 1, true) == nil, label .. ": ...the box says the Basket is full", reward6)
					full.Play.Tiers[3].Claimed, full.Play.Tiers[3].Ready = true, false
					H.fire(full)
					T.check(all.Text == "CLAIM ALL (0)" and H.disabled(all), label .. ": ...with only that box ready: CLAIM ALL (0), greyed out", all.Text)
					full.Play.Tiers[6].Amount = 12
					H.fire(full)
					reward6 = H.text(H.part(6, "Reward"))
					T.check(all.Text == "CLAIM ALL (1)" and reward6:find("full", 1, true) == nil and reward6:find("Basket", 1, true) ~= nil,
						label .. ": ...room in the Basket again: counted, and the box reads the Berry Basket", all.Text .. " / " .. reward6)
					-- none ready: greyed out, the same place and size, sends nothing
					KC.advance(1.1)
					H.fire(H.base(H.now()))
					T.check(H.disabled(all) and H.shown(all), label .. ": none ready -> CLAIM ALL greyed out", all.Text)
					T.check(all.AbsolutePosition.X == box[1] and all.AbsolutePosition.Y == box[2] and all.AbsoluteSize.X == box[3] and all.AbsoluteSize.Y == box[4],
						label .. ": ...in the same place and size", RedoGeom.desc(all))
					mark = #Mock.RemoteLog
					H.click(all)
					T.eq(#H.sent(mark), 0, label .. ": ...and sends nothing")
				end)
			end)
		end
	end)

	-- the Play tab's geometry with 3 ready, then paused (real font widths)
	function H.checkPlay(DC, label)
		local three = H.play(H.now())
		three.Play.Seconds = 95 * 60
		three.Play.Tiers[4].Ready, three.Play.Tiers[5].Ready = true, true
		three.Vip = true
		H.fire(three)
		H.open(DC, "Play")
		RedoGeom.check(H.win(), label .. " (3 ready)", { NoOverlap = PLAY_NAMES })
		H.allFit(H.find("PlayPage"), label .. " (3 ready)")
		local p = H.play(H.now(), false)
		H.fire(p)
		KC.advance(1.1)
		RedoGeom.check(H.win(), label .. " (paused)", { NoOverlap = PLAY_NAMES })
		H.allFit(H.find("PlayPage"), label .. " (paused)")
		local tierBad = {}
		for i = 1, 7 do
			if not H.inside(H.tier(i), H.find("Body")) then
				tierBad[#tierBad + 1] = RedoGeom.desc(H.tier(i))
			end
		end
		T.check(#tierBad == 0, label .. ": every box inside the window's body", table.concat(tierBad, "; "))
	end

	S.client_play_layouts = guarded("client_play_layouts", function()
		local sizes = { { 844, 390, true, "Phone" }, { 1280, 720, false, "PC" }, { 1366, 768, false, "PC" }, { 1920, 1080, false, "PC" }, { 667, 375, true, "Phone" } }
		for _, sz in ipairs(sizes) do
			local label = fmt("play layouts %dx%d", sz[1], sz[2])
			RedoGeom.at(sz[1], sz[2], sz[3], label, function()
				H.with(label, function(DC)
					H.realMeasure(function()
						H.checkPlay(DC, label)
					end)
					T.eq(DC.Layout(), sz[4], label .. ": Layout()")
					local t = {}
					for i = 1, 7 do
						t[i] = H.tier(i)
					end
					local win = H.win()
					if sz[4] == "Phone" then
						local row = true
						for i = 2, 7 do
							if not (t[i] and t[1] and H.near(t[i].AbsolutePosition.Y, t[1].AbsolutePosition.Y) and t[i].AbsolutePosition.X > t[i - 1].AbsolutePosition.X + t[i - 1].AbsoluteSize.X - 1) then
								row = false
							end
						end
						T.check(row, label .. ": seven boxes in one row", RedoGeom.desc(t[1]) .. " .. " .. RedoGeom.desc(t[7]))
						if sz[1] == 844 then
							T.check(H.near(t[1].AbsoluteSize.X, 104) and H.near(t[1].AbsoluteSize.Y, 204), label .. ": the boxes are 104 x 204", RedoGeom.desc(t[1]))
						end
					else
						local function y(o)
							return o.AbsolutePosition.Y
						end
						local function mid(a, b)
							return (a.AbsolutePosition.X + b.AbsolutePosition.X + b.AbsoluteSize.X) / 2
						end
						local wx = win.AbsolutePosition.X + win.AbsoluteSize.X / 2
						T.check(H.near(y(t[1]), y(t[4])) and H.near(y(t[5]), y(t[7])) and y(t[5]) >= y(t[1]) + t[1].AbsoluteSize.Y - 1,
							label .. ": four boxes on top, three under", RedoGeom.desc(t[1]) .. " / " .. RedoGeom.desc(t[5]))
						T.check(H.near(mid(t[1], t[4]), wx, 2) and H.near(mid(t[5], t[7]), wx, 2), label .. ": both rows centred in the window",
							fmt("row 1 %.0f, row 2 %.0f, window %.0f", mid(t[1], t[4]), mid(t[5], t[7]), wx))
						if sz[1] == 1920 then
							T.check(H.near(t[1].AbsoluteSize.X, 260) and H.near(t[1].AbsoluteSize.Y, 250), label .. ": the boxes are 260 x 250 at 1080p", RedoGeom.desc(t[1]))
						end
					end
					-- CLAIM ALL at the top right of the body, right of the header line
					local all, header, body = H.claimAll(), H.find("PlayHeader"), H.find("Body")
					local rightGap = all and win and (win.AbsolutePosition.X + win.AbsoluteSize.X) - (all.AbsolutePosition.X + all.AbsoluteSize.X) or -1
					T.check(all ~= nil and header ~= nil and body ~= nil and all.AbsolutePosition.X >= header.AbsolutePosition.X + header.AbsoluteSize.X - 1
						and rightGap >= 0 and rightGap <= 40 and all.AbsolutePosition.Y - body.AbsolutePosition.Y <= 20,
						label .. ": CLAIM ALL at the top right, right of the header", RedoGeom.desc(all) .. " / " .. RedoGeom.desc(header) .. fmt(" gap %.0f", rightGap))
				end)
			end)
		end
	end)

	S.client_play_portrait = guarded("client_play_portrait", function()
		for _, sz in ipairs({ { 390, 844 }, { 360, 640 } }) do
			local label = fmt("play portrait %dx%d", sz[1], sz[2])
			RedoGeom.at(sz[1], sz[2], true, label, function()
				H.with(label, function(DC)
					H.realMeasure(function()
						H.checkPlay(DC, label)
					end)
					T.eq(DC.Layout(), "Portrait", label .. ": Layout()")
					local t = {}
					for i = 1, 7 do
						t[i] = H.tier(i)
					end
					if T.check(t[1] and t[4] and t[5] and t[7], label .. ": the boxes exist") then
						local function y(o)
							return o.AbsolutePosition.Y
						end
						T.check(H.near(y(t[1]), y(t[4])) and H.near(y(t[5]), y(t[7])) and y(t[5]) >= y(t[1]) + t[1].AbsoluteSize.Y - 1,
							label .. ": four boxes a row, the 90 min box starts row 2", RedoGeom.desc(t[1]) .. " / " .. RedoGeom.desc(t[4]) .. " / " .. RedoGeom.desc(t[5]))
						local win = H.win()
						local wx = win.AbsolutePosition.X + win.AbsoluteSize.X / 2
						local m2 = (t[5].AbsolutePosition.X + t[7].AbsolutePosition.X + t[7].AbsoluteSize.X) / 2
						T.check(H.near(m2, wx, 2), label .. ": row 2 centred", fmt("%.0f vs %.0f", m2, wx))
					end
				end)
			end)
		end
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
