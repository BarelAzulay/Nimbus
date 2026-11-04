-- smoke_fixr_daily_ui.lua: the store build's review fixes on the Gifts UI and the boost chips (docs/superpowers/specs/
-- 2026-11-04-shop-retention-design.md 5.2 / 8 / C5; review findings 5 / 6 / 7 / 12 / 13 / 14 + the owner's Play-time note),
-- loaded by tools/smoke.py in the client worlds only (ARGS.context = "client"; the server half is empty):
--   client_fixr_daily_week        (1920x1080) a repair claim (Streak 6 -> 7 with Paid 7, Weeks unchanged) plays no week
--                                 celebration (no banner, no confetti, no DailyWeek); a paid week (Weeks rises) does; the
--                                 same at 14
--   client_fixr_daily_play_cells  (1920x1080) the Play time tab is a grid of seven reward cells, one per tier, each its own
--                                 saturated colour (Fill UIGradient + NeonStroke), the time and the reward, the states
--                                 Claimed / Ready (CLAIM -> ClaimPlay(tier)) / Locked ("n min to go"); the Daily cells are
--                                 coloured per day too (today Gold)
--   client_fixr_boost_toast       "x2 Pet XP started!" only for a potion that starts during this view: a second potion
--                                 after an expired one (the attribute still holds the old end), never a potion bought
--                                 earlier that arrives late (a provisional recovery / a slow profile), never an end in the
--                                 past, never the first value seen, never an extension
--   client_fixr_daily_phone       (phone world) 360x640 portrait: the window inside the screen with the 12 px side margins,
--                                 the X, both tabs, the seven cells, CLAIM! and the seven tier cells reachable, every target
--                                 >= 44, texts >= 15; 844x390: the X, the tabs and the tier CLAIM buttons are 44 px tall
-- Every payload is fired at the client with KC.toClient("DailyState", ...). The viewport, the graphics level, the
-- attributes, SoundFx.Play and MenuController.Hint are restored at the end of each scenario.
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local abs = math.abs
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
	local H = {}

	-- a module of the client build (the H.moduleAt shape of smoke_daily_ui.lua; ROOTS is smoke.py's)
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
	-- MenuController.Hint is wrapped for the scenario (every side hint counted)
	function H.watchMenu(MC)
		local w = { hints = {} }
		local real = MC and MC.Hint
		if MC then
			MC.Hint = function(text, kind)
				w.hints[#w.hints + 1] = tostring(text)
				return real(text, kind)
			end
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
			end
		end
		return w
	end
	-- SoundFx.Play is wrapped for the scenario (every sound id counted)
	function H.watchSound()
		local SFX = H.moduleAt("client", "SoundFx")
		local w = { played = {} }
		local real = SFX and SFX.Play
		if SFX then
			SFX.Play = function(id, ...)
				w.played[#w.played + 1] = tostring(id)
				return real(id, ...)
			end
		end
		function w.count(id)
			local n = 0
			for _, p in ipairs(w.played) do
				if p == id then
					n = n + 1
				end
			end
			return n
		end
		function w.restore()
			if SFX then
				SFX.Play = real
			end
		end
		return w
	end

	-- the DailyState payload (smoke_daily_ui.lua H.base): Streak 2, Cell 3, Week 2, days 1-2 claimed, ready a second ago,
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
	-- the DailyService shape of a streak (DailyService.State: Cell, Claimed per day, Weeks = floor(Paid / 7))
	function H.streak(now, streak, paid)
		local p = H.base(now)
		p.Streak, p.Paid, p.Weeks = streak, paid, math.floor(paid / 7)
		p.Cell = (streak % 7) + 1
		p.ReadyAt = now + 72000
		for i = 1, 7 do
			local claimed = streak > 0 and i <= ((streak - 1) % 7) + 1 and paid >= math.floor((streak - 1) / 7) * 7 + i
			p.Days[i].Claimed = claimed
			p.Days[i].Today = (i == p.Cell) and not claimed
		end
		return p
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
	function H.cell(i)
		return H.find(H.find(H.win(), "Cells"), "Cell" .. i)
	end
	function H.tier(i)
		return H.find(H.find(H.win(), "Tiers"), "Tier" .. i)
	end
	function H.tierButton(i)
		local b = H.find(H.tier(i), "Claim")
		return H.shown(b) and b or nil
	end
	function H.tab(name)
		return H.find(H.win(), name)
	end
	function H.tapTab(name)
		H.tap(H.tab(name))
	end
	function H.stroke(card)
		local s = card and card:FindFirstChild("NeonStroke")
		return s and s:IsA("UIStroke") and s or nil
	end
	function H.fill(card)
		local g = card and card:FindFirstChild("Fill")
		return g and g:IsA("UIGradient") and g or nil
	end
	function H.key(c)
		return c and fmt("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) or "nil"
	end
	-- the most saturated channel spread of a colour (0..255): a saturated neon is far from grey
	function H.spread(c)
		local r, g, b = c.R * 255, c.G * 255, c.B * 255
		return math.max(r, g, b) - math.min(r, g, b)
	end
	function H.rect(o)
		return o.AbsolutePosition.X, o.AbsolutePosition.Y, o.AbsoluteSize.X, o.AbsoluteSize.Y
	end
	function H.inside(o, x0, y0, x1, y1)
		if not o then
			return false
		end
		local x, y, w, h = H.rect(o)
		return x >= x0 - 1 and y >= y0 - 1 and x + w <= x1 + 1 and y + h <= y1 + 1
	end
	function H.desc(o)
		if not o then
			return "missing"
		end
		local x, y, w, h = H.rect(o)
		return fmt("%s %d,%d %dx%d", o.Name, x, y, w, h)
	end
	function H.smallest(root)
		local min, which = math.huge, ""
		for _, d in ipairs(KC.texts(root, true)) do
			if tostring(d.Text):gsub("%s", "") ~= "" and d.TextSize < min then
				min, which = d.TextSize, d:GetFullName()
			end
		end
		return min, which
	end

	S.client_fixr_daily_week = guarded("client_fixr_daily_week", function()
		local restoreScreen = H.saveScreen()
		H.setScreen(1920, 1080, false)
		local DC = H.moduleAt("client", "Controllers/DailyController")
		local GQ = H.moduleAt("client", "GraphicsQuality")
		if not T.check(DC ~= nil, "fixr daily week: DailyController exists") then
			restoreScreen()
			return
		end
		if GQ then
			GQ.Apply("High")
		end
		local sound = H.watchSound()
		KC.advance(6) -- an earlier banner has run out (WEEK_SECONDS + the 1 s render tick)
		local now = H.now()
		-- week 1 paid (Streak 7, Paid 7, Weeks 1), then two missed days: the repair claims step back to 6, then climb to 7
		H.fire(H.streak(now, 7, 7))
		DC.Open({ Tab = "Daily" })
		KC.advance(0.3)
		H.fire(H.streak(now, 6, 7))
		local before = sound.count("DailyWeek")
		H.fire(H.streak(now, 7, 7))
		T.check(H.body():find("WEEK DONE!", 1, true) == nil and H.confetti() == 0 and sound.count("DailyWeek") == before,
			"fixr daily week: a repaired day 7 (Paid 7, Weeks 1 unchanged) plays no week celebration",
			fmt("banner %s, confetti %d, DailyWeek %d", tostring(H.body():find("WEEK DONE!", 1, true) ~= nil), H.confetti(), sound.count("DailyWeek") - before))
		T.check(H.cell(7) ~= nil and H.cell(7):GetAttribute("Claimed") == true, "fixr daily week: ...the repaired day 7 still shows claimed")
		-- a real week: 13 -> 14 paid (Weeks 1 -> 2)
		H.fire(H.streak(now, 13, 13))
		before = sound.count("DailyWeek")
		H.fire(H.streak(now, 14, 14))
		T.check(H.body():find("WEEK DONE! Week Wisp is yours!", 1, true) ~= nil and H.confetti() == 24 and sound.count("DailyWeek") == before + 1,
			"fixr daily week: a paid day 7 (Weeks 1 -> 2) celebrates: banner, 24 confetti, DailyWeek",
			fmt("confetti %d, DailyWeek %d", H.confetti(), sound.count("DailyWeek") - before))
		KC.advance(6) -- WEEK_SECONDS 4.5 + the 1 s render tick
		T.check(H.body():find("WEEK DONE!", 1, true) == nil, "fixr daily week: the banner runs out", fmt("open %s, banner visible %s, time %.2f", tostring(DC.IsOpen()), tostring(H.find(H.win(), "WeekBanner") and H.find(H.win(), "WeekBanner").Visible), time()))
		-- the same at 14: a step-back to 13 (Paid 14) and back to 14 is a repair
		H.fire(H.streak(now, 13, 14))
		before = sound.count("DailyWeek")
		H.fire(H.streak(now, 14, 14))
		T.check(H.body():find("WEEK DONE!", 1, true) == nil and H.confetti() == 0 and sound.count("DailyWeek") == before,
			"fixr daily week: a repaired day 14 (Weeks 2 unchanged) plays no week celebration",
			fmt("confetti %d, DailyWeek %d", H.confetti(), sound.count("DailyWeek") - before))
		-- the join payload never celebrates (a Loading one first)
		H.fire({ Loading = true })
		before = sound.count("DailyWeek")
		H.fire(H.streak(now, 21, 21))
		T.check(H.body():find("WEEK DONE!", 1, true) == nil and sound.count("DailyWeek") == before, "fixr daily week: the first payload after a Loading one never celebrates")
		DC.Close()
		KC.advance(0.3)
		H.fire(H.base(H.now()))
		sound.restore()
		restoreScreen()
		KC.flushErrors("client_fixr_daily_week")
		KC.flushWarnings("client_fixr_daily_week")
	end)

	S.client_fixr_daily_play_cells = guarded("client_fixr_daily_play_cells", function()
		local restoreScreen = H.saveScreen()
		H.setScreen(1920, 1080, false)
		local DC = H.moduleAt("client", "Controllers/DailyController")
		if not T.check(DC ~= nil, "fixr play cells: DailyController exists") then
			restoreScreen()
			return
		end
		local now = H.now()
		local p = H.base(now)
		p.Play.Tiers[4].Ready = true
		p.Play.Seconds = 62 * 60
		H.fire(p)
		DC.Open({ Tab = "Play" })
		KC.advance(0.3)
		local win = H.win()
		local tiersFrame = H.find(win, "Tiers")
		local n = 0
		for _, c in ipairs(tiersFrame and tiersFrame:GetChildren() or {}) do
			if c.Name:match("^Tier%d$") and H.shown(c) then
				n = n + 1
			end
		end
		T.check(n == 7 and H.find(win, "Rows") == nil, "fixr play cells: seven reward cells (Tiers > Tier1..7), one per tier, no rows", fmt("%d cells", n))
		-- each tier its own saturated colour: the cell's NeonStroke and its Fill gradient
		local seen, distinct, saturated, gradients = {}, 0, true, true
		local detail = {}
		for i = 1, 7 do
			local c = H.tier(i)
			local st, g = H.stroke(c), H.fill(c)
			local col = st and st.Color
			if col and not seen[H.key(col)] then
				seen[H.key(col)] = true
				distinct = distinct + 1
			end
			if not col or H.spread(col) < 120 then
				saturated = false
			end
			local kp = g and g.Color and g.Color.Keypoints
			if not (kp and #kp >= 2 and H.spread(kp[1].Value) >= 50) then
				gradients = false
			end
			detail[#detail + 1] = H.key(col)
		end
		T.check(distinct == 7 and saturated, "fixr play cells: seven distinct saturated cell outlines (NeonStroke)", table.concat(detail, " / "))
		T.check(gradients, "fixr play cells: every cell carries a coloured Fill gradient (UIGradient)")
		-- the time and the reward
		local t1, t6 = H.texts(H.tier(1)), H.texts(H.tier(6))
		T.check(t1:find("10 min", 1, true) ~= nil and t1:find("+$200", 1, true) ~= nil and t6:find("120 min", 1, true) ~= nil and t6:find("Full Berry Basket", 1, true) ~= nil,
			"fixr play cells: each cell shows its time and its reward", t1 .. " || " .. t6)
		T.check(H.find(H.tier(1), "Icon") ~= nil, "fixr play cells: the reward's icon")
		-- the states
		local function state(i)
			local c = H.tier(i)
			return c and c:GetAttribute("State")
		end
		T.check(state(1) == "Claimed" and H.shown(H.find(H.tier(1), "Check")) and H.texts(H.tier(1)):find("Claimed", 1, true) ~= nil and H.tierButton(1) == nil,
			"fixr play cells: a claimed tier says Claimed with its check", H.texts(H.tier(1)))
		local b4 = H.tierButton(4)
		T.check(state(4) == "Ready" and b4 ~= nil and b4.Text == "CLAIM" and not H.shown(H.find(H.tier(4), "ToGo")), "fixr play cells: a ready tier has its CLAIM", H.texts(H.tier(4)))
		T.check(state(5) == "Locked" and H.tierButton(5) == nil and H.texts(H.tier(5)):find("28 min to go", 1, true) ~= nil and not H.shown(H.find(H.tier(5), "Check")),
			"fixr play cells: a locked tier says how long to go", H.texts(H.tier(5)))
		local s4, s5 = H.stroke(H.tier(4)), H.stroke(H.tier(5))
		T.check(s4 and s5 and s4.Transparency < s5.Transparency, "fixr play cells: a ready cell's outline is brighter than a locked one's",
			fmt("ready %s, locked %s", tostring(s4 and s4.Transparency), tostring(s5 and s5.Transparency)))
		local mark = #Mock.RemoteLog
		H.tap(b4)
		local sent = KC.serverCalls("DailyRequest", mark)
		T.check(#sent == 1 and sent[1].args[1] == "ClaimPlay" and sent[1].args[2] == 4, "fixr play cells: CLAIM -> DailyRequest(\"ClaimPlay\", 4)", tostring(#sent))
		-- every cell inside the window
		local inside = true
		local wx, wy, ww, wh = H.rect(win)
		for i = 1, 7 do
			if not H.inside(H.tier(i), wx, wy, wx + ww, wy + wh) then
				inside = false
				detail[#detail + 1] = H.desc(H.tier(i))
			end
		end
		T.check(inside, "fixr play cells: every cell inside the window", H.desc(win))
		-- the Daily strip: coloured per day too, today Gold
		H.tapTab("Tab_Daily")
		local Theme = select(3, KC.env())
		local dseen, dn, dsat, dgrad = {}, 0, true, true
		for i = 1, 7 do
			local c = H.cell(i)
			local st, g = H.stroke(c), H.fill(c)
			local col = st and st.Color
			if col and not dseen[H.key(col)] then
				dseen[H.key(col)] = true
				dn = dn + 1
			end
			if not col or H.spread(col) < 120 then
				dsat = false
			end
			local kp = g and g.Color and g.Color.Keypoints
			if not (kp and #kp >= 2 and H.spread(kp[1].Value) >= 50) then
				dgrad = false
			end
		end
		local today = H.stroke(H.cell(3))
		T.check(dn == 7 and dsat and dgrad, "fixr play cells: the Daily cells are coloured per day (outline + Fill gradient)", tostring(dn))
		T.check(today ~= nil and H.key(today.Color) == H.key(Theme.Neon.Gold), "fixr play cells: today's Daily cell stays Gold", today and H.key(today.Color) or "")
		DC.Close()
		KC.advance(0.3)
		H.fire(H.base(H.now()))
		restoreScreen()
		KC.flushErrors("client_fixr_daily_play_cells")
		KC.flushWarnings("client_fixr_daily_play_cells")
	end)

	S.client_fixr_boost_toast = guarded("client_fixr_boost_toast", function()
		local BB = H.moduleAt("client", "Controllers/BoostBadgeController")
		local MC = H.moduleAt("client", "Controllers/MenuController")
		if not T.check(BB ~= nil and MC ~= nil, "fixr boost toast: BoostBadgeController and MenuController exist") then
			return
		end
		local w = H.watchMenu(MC)
		local oldPasses, oldEnds = LocalPlayer:GetAttribute("OwnedPasses"), LocalPlayer:GetAttribute("XpBoostEnds")
		LocalPlayer:SetAttribute("OwnedPasses", "")
		LocalPlayer:SetAttribute("XpBoostEnds", 0)
		KC.advance(1.1)
		local START = "x2 Pet XP started!"
		-- potion A: a short one that runs out; the server leaves XpBoostEnds at its old end (finding 14)
		LocalPlayer:SetAttribute("XpBoostEnds", H.now() + 2)
		KC.advance(3.2)
		T.check(BB.Chips().Xp == nil and (LocalPlayer:GetAttribute("XpBoostEnds") or 0) > 0, "fixr boost toast: potion A ran out, its old end stays on the attribute")
		local n = w.count(START)
		LocalPlayer:SetAttribute("XpBoostEnds", H.now() + 3600)
		KC.advance(0.2)
		T.eq(w.count(START) - n, 1, "fixr boost toast: a second potion of the session (the attribute held an expired end) says started")
		-- an extension of a running potion is not a start
		n = w.count(START)
		LocalPlayer:SetAttribute("XpBoostEnds", (LocalPlayer:GetAttribute("XpBoostEnds") or 0) + 3600)
		KC.advance(0.2)
		T.eq(w.count(START) - n, 0, "fixr boost toast: extending a running potion says nothing")
		-- a provisional recovery / a slow profile: 0, then the end of a potion bought earlier (finding 7)
		LocalPlayer:SetAttribute("XpBoostEnds", 0)
		KC.advance(0.2)
		n = w.count(START)
		LocalPlayer:SetAttribute("XpBoostEnds", H.now() + 2000)
		KC.advance(0.2)
		T.eq(w.count(START) - n, 0, "fixr boost toast: a 1 h potion bought earlier (2000 s left) arriving late says nothing")
		LocalPlayer:SetAttribute("XpBoostEnds", 0)
		KC.advance(0.2)
		LocalPlayer:SetAttribute("XpBoostEnds", H.now() + 10200)
		KC.advance(0.2)
		T.eq(w.count(START) - n, 0, "fixr boost toast: a 3 h potion bought 10 min earlier arriving late says nothing")
		-- an end already in the past
		LocalPlayer:SetAttribute("XpBoostEnds", 0)
		KC.advance(0.2)
		LocalPlayer:SetAttribute("XpBoostEnds", H.now() - 100)
		KC.advance(0.2)
		T.eq(w.count(START) - n, 0, "fixr boost toast: an end in the past says nothing")
		-- the first value seen (no attribute yet, then the server's first write) is the baseline, never a start
		LocalPlayer:SetAttribute("XpBoostEnds", nil)
		KC.advance(0.2)
		LocalPlayer:SetAttribute("XpBoostEnds", H.now() + 3600)
		KC.advance(0.2)
		T.eq(w.count(START) - n, 0, "fixr boost toast: the first value seen is never announced")
		-- and a fresh 3 h potion after none still says started
		LocalPlayer:SetAttribute("XpBoostEnds", 0)
		KC.advance(0.2)
		LocalPlayer:SetAttribute("XpBoostEnds", H.now() + 10800)
		KC.advance(0.2)
		T.eq(w.count(START) - n, 1, "fixr boost toast: a fresh 3 h potion says started")
		LocalPlayer:SetAttribute("OwnedPasses", oldPasses)
		LocalPlayer:SetAttribute("XpBoostEnds", oldEnds)
		KC.advance(0.3)
		w.restore()
		KC.flushErrors("client_fixr_boost_toast")
		KC.flushWarnings("client_fixr_boost_toast")
	end)

	S.client_fixr_daily_phone = guarded("client_fixr_daily_phone", function()
		local restoreScreen = H.saveScreen()
		H.setScreen(360, 640, true)
		local DC = H.moduleAt("client", "Controllers/DailyController")
		if not T.check(DC ~= nil, "fixr daily phone: DailyController exists") then
			restoreScreen()
			return
		end
		local now = H.now()
		local p = H.base(now)
		p.Play.Tiers[4].Ready, p.Play.Tiers[5].Ready = true, true
		H.fire(p)
		local btn = H.btn()
		if H.shown(btn) then
			H.tap(btn)
		else
			DC.Open()
			KC.advance(0.3)
		end
		local gui = H.gui()
		local win = H.win()
		local GW, GH = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
		T.check(DC.IsOpen() and win ~= nil and H.inside(win, 12, 0, GW - 12, GH) and win.AbsoluteSize.X >= GW - 24 - 1,
			"fixr daily phone: 360x640 the window fits inside the screen with the 12 px side margins", H.desc(win) .. fmt(" in %dx%d", GW, GH))
		local function targets(names, label)
			local ok, bad = true, {}
			for _, o in ipairs(names) do
				if not (H.shown(o) and H.inside(o, 0, 0, GW, GH) and o.AbsoluteSize.Y >= 44 - 0.5 and o.AbsoluteSize.X >= 44 - 0.5) then
					ok = false
					bad[#bad + 1] = H.desc(o)
				end
			end
			T.check(ok, label, table.concat(bad, "; "))
		end
		targets({ H.tab("CloseButton"), H.tab("Tab_Daily"), H.tab("Tab_Play") }, "fixr daily phone: 360x640 the X and both tabs on screen, >= 44 px")
		local cellsIn, cellBad = true, {}
		for i = 1, 7 do
			if not (H.shown(H.cell(i)) and H.inside(H.cell(i), 0, 0, GW, GH)) then
				cellsIn = false
				cellBad[#cellBad + 1] = H.desc(H.cell(i))
			end
		end
		T.check(cellsIn, "fixr daily phone: 360x640 all seven day cells on screen (days 5-7 included)", table.concat(cellBad, "; "))
		local claim = H.find(win, "ClaimButton")
		targets({ claim }, "fixr daily phone: 360x640 CLAIM! on screen, >= 44 px")
		local m, which = H.smallest(win)
		T.check(m >= 15, "fixr daily phone: 360x640 texts >= 15 (Daily)", fmt("%s at %s", tostring(m), which))
		H.tapTab("Tab_Play")
		local tierIn, tierBad = true, {}
		for i = 1, 7 do
			local wx, wy, ww, wh = H.rect(win)
			if not (H.shown(H.tier(i)) and H.inside(H.tier(i), 0, 0, GW, GH) and H.inside(H.tier(i), wx, wy, wx + ww, wy + wh)) then
				tierIn = false
				tierBad[#tierBad + 1] = H.desc(H.tier(i))
			end
		end
		T.check(tierIn, "fixr daily phone: 360x640 all seven tier cells inside the window and the screen", table.concat(tierBad, "; "))
		targets({ H.tierButton(4), H.tierButton(5) }, "fixr daily phone: 360x640 the tier CLAIM buttons on screen, >= 44 px")
		m, which = H.smallest(win)
		T.check(m >= 15, "fixr daily phone: 360x640 texts >= 15 (Play time)", fmt("%s at %s", tostring(m), which))
		H.tap(H.tab("CloseButton"))
		T.check(not DC.IsOpen(), "fixr daily phone: 360x640 the X closes the window")
		-- 844x390 landscape phone: the same 44 px targets (finding 13)
		H.setScreen(844, 390, true)
		gui = H.gui()
		GW, GH = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
		DC.Open({ Tab = "Play" })
		KC.advance(0.3)
		win = H.win()
		T.check(win ~= nil and abs(win.AbsoluteSize.X - 560) <= 1 and abs(win.AbsoluteSize.Y - 300) <= 1, "fixr daily phone: 844x390 keeps the 560x300 window", H.desc(win))
		targets({ H.tab("CloseButton"), H.tab("Tab_Daily"), H.tab("Tab_Play"), H.tierButton(4), H.tierButton(5) }, "fixr daily phone: 844x390 the X, the tabs and the tier CLAIM buttons >= 44 px")
		local wx, wy, ww, wh = H.rect(win)
		local all = true
		for i = 1, 7 do
			if not H.inside(H.tier(i), wx, wy, wx + ww, wy + wh) then
				all = false
			end
		end
		T.check(all, "fixr daily phone: 844x390 every tier cell inside the window")
		m, which = H.smallest(win)
		T.check(m >= 15, "fixr daily phone: 844x390 texts >= 15 (Play time)", fmt("%s at %s", tostring(m), which))
		DC.Close()
		KC.advance(0.3)
		H.fire(H.base(H.now()))
		restoreScreen()
		KC.flushErrors("client_fixr_daily_phone")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
