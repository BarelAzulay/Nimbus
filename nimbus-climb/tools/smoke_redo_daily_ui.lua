-- smoke_redo_daily_ui.lua: the Gifts window redone (docs/superpowers/specs/2026-11-06-window-redo-design.md 5.1, 5.3 "Layout"
-- and "The window while locked"; plan docs/superpowers/plans/2026-11-06-window-redo.md Task 9): DailyController as a big
-- centred window (NeonKit.BigRect, 1180 x 720 at 1080p, 820 x 330 on a landscape phone) and its Daily page (card A: glossy
-- day tiles, today raised and gold, Day 7 double-wide with the Week Wisp, the Wisp line and bar, one big CLAIM and the keep
-- line), with the 10-minute lock read from the payload's Unlock { Need, Left }. Client and phone worlds only (client_files,
-- loaded after smoke_redo_geom.lua, whose RedoGeom it uses):
--   client_daily_ui_a      (1920x1080, then 844x390 touch) a ready payload: the window centred in its BigRect box (the Gifts
--                          button stays where it is), seven tiles, today (Cell3) raised 8 px over Cell2 with the same
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
--                          open and back after; a resize while open (1920x1080 -> 844x390 -> 1920x1080) passes each time
--   client_daily_portrait  (phone world, 390x844 touch; and 360x640) Layout() "Portrait", the day tiles four per row (Day 7
--                          the double tile of row 2), RedoGeom.check passes for the ready, locked and wait views and the
--                          Play tab
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
					T.check(btn ~= nil and btn.AbsolutePosition.X == bx and btn.AbsolutePosition.Y == by and H.shown(btn), label .. ": the Gifts button stays where it is")
					-- the header and the chips
					T.eq(H.text(H.find("Header")), "Day 3 of 7 " .. DOT .. " Week 2", label .. ": the header")
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
					T.eq(DCx.PipShown(), true, label .. ": ...and the pip")
					mark = #Mock.RemoteLog
					H.click(claim)
					T.eq(#H.sent(mark), 1, label .. ": ...which claims")
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

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
