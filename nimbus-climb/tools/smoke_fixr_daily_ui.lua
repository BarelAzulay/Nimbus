-- smoke_fixr_daily_ui.lua: the store build's review fixes on the Gifts UI and the boost chips (docs/superpowers/specs/
-- 2026-11-04-shop-retention-design.md 5.2 / 8 / C5; review findings 5 / 6 / 7 / 12 / 13 / 14 + the owner's Play-time note),
-- loaded by tools/smoke.py in the client worlds only (ARGS.context = "client"; the server half is empty):
--   client_fixr_daily_week        (1920x1080) a repair claim (Streak 6 -> 7 with Paid 7, Weeks unchanged) plays no week
--                                 celebration (no banner, no confetti, no DailyWeek); a paid week (Weeks rises) does; the
--                                 same at 14
--   client_fixr_daily_play_cells  (1920x1080) the Play time tab is seven gift boxes (gui-redo Task 10, card B), one per tier,
--                                 each its own saturated colour (Fill UIGradient + NeonStroke), the time, the gift and the
--                                 reward, the states Claimed (the tick over the Dim) / Ready (CLAIM -> ClaimPlay(tier)) /
--                                 Locked (its own clock "28:00"); the Daily cells are coloured per day too (today Gold)
--   client_fixr_boost_toast       "x2 Pet XP started!" only for a potion that starts during this view: a second potion
--                                 after an expired one (the attribute still holds the old end), never a potion bought
--                                 earlier that arrives late (a provisional recovery / a slow profile), never an end in the
--                                 past, never the first value seen, never an extension
--   client_fixr_daily_phone       (phone world) 360x640 portrait: the window inside the screen with the 12 px side margins,
--                                 the X, both tabs, the seven cells, CLAIM! and the seven tier cells reachable, every target
--                                 >= 44, texts >= 15; 844x390 (the 820x330 BigRect window since gui-redo Task 9): the X, the
--                                 tabs and the tier CLAIM buttons are 44 px tall
-- Re-review round 1:
--   client_fixr_daily_repair      (1920x1080, 844x390, 360x640) a repair payload (Streak 3 / Paid 3, a missed day) draws the
--                                 repair: today's gold cell is the repair cell reading "Repair" (no amount) and the footer
--                                 button says "Repair streak (no gift)" (fits, >= 44 px), never CLAIM!; a kept streak is
--                                 CLAIM! with the next day's gift again (finding 2)
--   client_fixr_boost_pass        a PetXp2x owner gets neither "x2 Pet XP started!" nor "x2 Pet XP ends in 5 min" for a
--                                 potion (the pass wins, as Chips() shows); without the pass the crossing warns (finding 3)
--   client_fixr_daily_fit         (1920x1080, 844x390, 360x640) every day cell and play-time cell text fits its box with
--                                 the real font widths (TextService:GetTextSize measures them for the scenario): day 7
--                                 names its pet, tier 6 says what it gives (finding 5)
--   client_fixr_daily_resize      (phone world) the open Portrait window stays shown when the gui width changes while the
--                                 screen stays portrait (360x640 -> 375x667 -> 390x844 -> 360x640); the Gifts button
--                                 hides while it is open and, after Close, its tap opens it again (findings 4 / 7; owner
--                                 2026-11-13: the button no longer closes it)
--   client_fixr_menu_cover        (phone world) 360x640: no NimbusMenu tile draws over the open Gifts window or the Store,
--                                 also when one window opens over another (the Store, the Pets window); the tiles come back
--                                 when every window is closed (open item n1)
-- Re-review round 2:
--   client_fixr_daily_stale       (1920x1080) a payload past its StaleAt (the keep deadline passed since it was built)
--                                 never promises its gift: no CLAIM!, no gold today cell, "Getting your gifts ready..."
--                                 until the server's fresh payload (the repair) arrives (findings 6 / 9)
--   client_fixr_touch_handoff     (phone world) 360x640: the Store opened over the Pets window and the Pets window opened
--                                 over the Store keep Roblox's thumbstick and jump button hidden while one is up and bring
--                                 them back when the last one closes, round after round (finding 4)
-- Re-review round 3:
--   client_fixr_daily_repair_wait (1920x1080, 844x390, 360x640) the wait before a claim that only repairs (Repair, not
--                                 ready yet: right after a repair claim that still leaves Streak + 1 <= Paid) counts down
--                                 "Streak repair in ...", never "Next gift in ..." (fits, inside the window); a paying
--                                 claim's wait still names the next gift (finding 3)
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

	-- Real text widths (the mock measures a flat 0.5 em per character): the advance widths (1/1000 em) of ASCII 32..126 in
	-- Roblox's shipped FredokaOne-Regular.ttf (Display), BuilderSans-Bold.otf (Body / Label) and Montserrat-Black.ttf (the
	-- metric stand-in for GothamBlack, a cloud font: Title / Heading / Button / Toast); any other character counts 0.6 em
	local ADVANCE = {
		Fredoka = { 253, 267, 429, 749, 475, 838, 748, 208, 384, 384, 503, 527, 238, 433, 237, 526, 608, 407, 609, 608, 592, 530, 560, 561, 582, 560, 238, 237, 627, 478, 627, 512, 908, 765, 646, 679, 704, 638, 637, 714, 699, 257, 549, 639, 587, 870, 720, 775, 632, 830, 631, 583, 731, 726, 783, 999, 741, 686, 643, 348, 528, 348, 526, 826, 482, 596, 592, 517, 598, 573, 450, 585, 605, 255, 252, 536, 327, 851, 606, 600, 582, 582, 457, 489, 449, 606, 638, 793, 567, 604, 586, 381, 217, 381, 651 },
		Gotham = { 300, 314, 489, 740, 657, 917, 777, 254, 381, 381, 473, 620, 304, 390, 304, 440, 692, 418, 608, 614, 712, 619, 661, 645, 678, 661, 304, 304, 620, 620, 620, 606, 1037, 806, 773, 744, 826, 673, 644, 769, 804, 350, 574, 765, 617, 954, 804, 848, 743, 848, 745, 657, 654, 784, 786, 1206, 762, 710, 687, 410, 440, 410, 620, 500, 600, 639, 700, 615, 705, 653, 426, 711, 702, 326, 334, 713, 326, 1040, 702, 678, 700, 700, 456, 565, 460, 698, 644, 977, 645, 644, 570, 438, 320, 438, 620 },
		Builder = { 250, 278, 458, 685, 580, 894, 704, 268, 366, 366, 431, 518, 264, 350, 264, 424, 646, 407, 585, 587, 612, 589, 615, 528, 632, 615, 292, 292, 518, 518, 518, 541, 919, 704, 635, 677, 702, 576, 574, 693, 720, 280, 505, 649, 566, 894, 720, 745, 627, 745, 641, 574, 556, 690, 716, 960, 658, 642, 559, 377, 424, 377, 476, 422, 276, 566, 613, 533, 613, 567, 405, 616, 601, 260, 255, 531, 260, 879, 601, 590, 613, 613, 415, 483, 403, 591, 574, 806, 536, 574, 465, 478, 294, 478, 600 },
	}
	local FACE = { FredokaOne = "Fredoka", BuilderSansBold = "Builder", BuilderSans = "Builder", BuilderSansMedium = "Builder", BuilderSansExtraBold = "Builder" }
	function H.realWidth(text, size, font)
		local name = (typeof(font) == "EnumItem" and font.Name) or tostring(font)
		local adv = ADVANCE[FACE[name] or "Gotham"]
		local em = 0
		for ch in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
			local b = ch:byte()
			if #ch == 1 then
				if b >= 32 and b <= 126 then
					em = em + adv[b - 31] / 1000
				end
			else
				em = em + 0.6
			end
		end
		return em * (tonumber(size) or 14)
	end
	-- the word-wrapped rows of `text` in `width` px with the real widths (math.huge: one word alone is wider than the box)
	function H.realRows(text, size, font, width)
		local rows, cur = 0, 0
		local space = H.realWidth(" ", size, font)
		for word in tostring(text):gmatch("%S+") do
			local w = H.realWidth(word, size, font)
			if w > width + 0.5 then
				return math.huge
			end
			if cur > 0 and cur + space + w <= width + 0.5 then
				cur = cur + space + w
			else
				rows = rows + 1
				cur = w
			end
		end
		return math.max(rows, 1)
	end
	-- TextService:GetTextSize measures with the real widths while a scenario runs (Roblox measures its real fonts; the
	-- mock's flat 0.5 em would let a layout pick a text that only fits in the mock). Answers the restore function.
	function H.realMeasure()
		game:GetService("TextService") -- the class is finalized once the service exists
		local methods = Mock.Classes.TextService.methods
		local old = methods.GetTextSize
		methods.GetTextSize = function(_, text, size, font, frame)
			local w = H.realWidth(text, size, font)
			local limit = (typeof(frame) == "Vector2" and frame.X > 0) and frame.X or math.huge
			if w <= limit then
				return Vector2.new(w, size)
			end
			local rows = H.realRows(text, size, font, limit)
			return Vector2.new(limit, (rows == math.huge and 99 or rows) * size)
		end
		return function()
			methods.GetTextSize = old
		end
	end
	-- the product of the UIScales on and above a gui object (the window's Scale / Fit, a cell's Pop)
	function H.scaleOf(o)
		local s, node = 1, o
		while node and not node:IsA("ScreenGui") do
			for _, ch in ipairs(node:GetChildren()) do
				if ch:IsA("UIScale") then
					s = s * ch.Scale
				end
			end
			node = node.Parent
		end
		return s
	end
	-- does a text object's text fit its box with the real widths? One line unless TextWrapped (then the rows by words);
	-- a TextScaled text always fits. Answers ok, detail.
	function H.fits(o)
		local text = tostring(o.Text)
		if text:gsub("%s", "") == "" or o.TextScaled then
			return true, ""
		end
		local s = math.max(0.01, H.scaleOf(o))
		local boxW, boxH = o.AbsoluteSize.X / s, o.AbsoluteSize.Y / s
		local pad = o:FindFirstChildOfClass("UIPadding")
		if pad then
			boxW = boxW - pad.PaddingLeft.Offset - pad.PaddingRight.Offset
			boxH = boxH - pad.PaddingTop.Offset - pad.PaddingBottom.Offset
		end
		local size = o.TextSize
		local w = H.realWidth(text, size, o.Font)
		local detail = fmt("%s '%s' %.1f px at %d (%s) in %.0fx%.0f", o.Name, (text:gsub("[\128-\255]+", "?")), w, size, o.Font.Name, boxW, boxH)
		if w <= boxW + 0.5 then
			return true, detail
		end
		if not o.TextWrapped then
			return false, detail
		end
		local rows = H.realRows(text, size, o.Font, boxW)
		return rows * size * (o.LineHeight or 1) <= boxH + 1, detail .. " rows " .. tostring(rows)
	end
	-- every shown text under `root` that does not fit (a list of details)
	function H.unfit(root)
		local bad = {}
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and KC.isShown(d) then
				local ok, detail = H.fits(d)
				if not ok then
					bad[#bad + 1] = detail
				end
			end
		end
		return bad
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
		T.check(n == 7 and H.find(win, "Rows") == nil, "fixr play cells: seven gift boxes (Tiers > Tier1..7), one per tier, no rows", fmt("%d boxes", n))
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
		-- (re-review 1: "Full Berry Basket" is wider than the PC cell, so the cell says "Berry Basket"; client_fixr_daily_fit
		-- checks that every cell text fits)
		T.check(t1:find("10 min", 1, true) ~= nil and t1:find("+$200", 1, true) ~= nil and t6:find("120 min", 1, true) ~= nil and t6:find("Berry Basket", 1, true) ~= nil,
			"fixr play cells: each cell shows its time and its reward", (t1 .. " || " .. t6):gsub("[\128-\255]+", "?"))
		T.check(H.find(H.find(H.tier(1), "Gift"), "Icon") ~= nil, "fixr play cells: the gift art (gui-redo Task 10: the Gifts icon in every box)")
		-- the states
		local function state(i)
			local c = H.tier(i)
			return c and c:GetAttribute("State")
		end
		T.check(state(1) == "Claimed" and H.shown(H.find(H.tier(1), "Check")) and H.shown(H.find(H.tier(1), "Dim")) and H.tierButton(1) == nil
			and not H.shown(H.find(H.tier(1), "Clock")), "fixr play cells: a claimed box shows its tick over the dim", H.texts(H.tier(1)))
		local b4 = H.tierButton(4)
		T.check(state(4) == "Ready" and b4 ~= nil and b4.Text == "CLAIM" and not H.shown(H.find(H.tier(4), "Clock")), "fixr play cells: a ready box has its CLAIM", H.texts(H.tier(4)))
		local clock5 = H.find(H.tier(5), "Clock")
		T.check(state(5) == "Locked" and H.tierButton(5) == nil and H.shown(clock5) and clock5.Text == "28:00" and not H.shown(H.find(H.tier(5), "Check")),
			"fixr play cells: a locked box counts down to its gift (its own clock)", H.texts(H.tier(5)))
		local s4, s5 = H.stroke(H.tier(4)), H.stroke(H.tier(5))
		T.check(s4 and s5 and s4.Transparency < s5.Transparency, "fixr play cells: a ready box's outline is brighter than a locked one's",
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
		-- (gui-redo Task 9: the BigRect box, 820x330 on 844x390; it was the 560x300 drop-down)
		T.check(win ~= nil and abs(win.AbsoluteSize.X - 820) <= 1 and abs(win.AbsoluteSize.Y - 330) <= 1, "fixr daily phone: 844x390 is the 820x330 window", H.desc(win))
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

	-- the rect of a gui object { x0, y0, x1, y1 } and whether two rects overlap (by more than a pixel)
	function H.box(o)
		local x, y, w, h = H.rect(o)
		return { x0 = x, y0 = y, x1 = x + w, y1 = y + h }
	end
	function H.overlap(a, b)
		return a.x0 < b.x1 - 1 and b.x0 < a.x1 - 1 and a.y0 < b.y1 - 1 and b.y0 < a.y1 - 1
	end
	-- the DailyService shape of a repair (re-review 1, finding 2): Streak 3 / Paid 3, the last claim 50 h ago: the claim
	-- steps back to 2 and re-earns day 3 unpaid, so Cell 3, days 1-2 claimed, day 3 Today + Repair, Repair = true
	function H.repair(now)
		local p = H.streak(now, 2, 3)
		p.Streak, p.Paid, p.Weeks = 3, 3, 0
		p.Repair = true
		p.Days[3].Repair = true
		p.ReadyAt = now - 30 * 3600
		p.KeepUntil = now - 2 * 3600
		return p
	end

	S.client_fixr_daily_repair = guarded("client_fixr_daily_repair", function()
		local restoreScreen = H.saveScreen()
		local DC = H.moduleAt("client", "Controllers/DailyController")
		if not T.check(DC ~= nil, "fixr daily repair: DailyController exists") then
			restoreScreen()
			return
		end
		local restoreMeasure = H.realMeasure()
		local okRun, errRun = pcall(function()
			local REPAIR = "Repair streak (no gift)"
			for _, scr in ipairs({ { 1920, 1080, false }, { 844, 390, true }, { 360, 640, true } }) do
				local tag = fmt("%dx%d", scr[1], scr[2])
				H.setScreen(scr[1], scr[2], scr[3])
				DC.Close()
				KC.advance(0.2)
				local now = H.now()
				H.fire(H.repair(now))
				DC.Open({ Tab = "Daily" })
				KC.advance(0.3)
				local win = H.win()
				local c3, c4 = H.cell(3), H.cell(4)
				T.check(c3 ~= nil and c3:GetAttribute("Today") == true and c4 ~= nil and c4:GetAttribute("Today") ~= true,
					"fixr daily repair: " .. tag .. " today's gold cell is the repair cell (day 3), not day 4's gift")
				local amount = H.find(c3, "Amount")
				T.check(amount ~= nil and amount.Text == "Repair" and H.texts(c3):find("$", 1, true) == nil,
					"fixr daily repair: " .. tag .. " ...it reads 'Repair', no amount", H.texts(c3))
				local claim = H.find(win, "ClaimButton")
				T.check(H.shown(claim) and claim.Text == REPAIR and H.body():find("CLAIM!", 1, true) == nil,
					"fixr daily repair: " .. tag .. " the footer button says 'Repair streak (no gift)', never CLAIM!", claim and claim.Text or "no button")
				local ok, detail = H.fits(claim)
				local wx, wy, ww, wh = H.rect(win)
				T.check(ok and H.inside(claim, wx, wy, wx + ww, wy + wh) and claim.AbsoluteSize.Y >= 44 - 0.5,
					"fixr daily repair: " .. tag .. " ...its text fits (real font widths), inside the window, >= 44 px tall", detail .. " " .. H.desc(claim))
				if scr[1] == 1920 then
					local mark = #Mock.RemoteLog
					H.tap(claim)
					local sent = KC.serverCalls("DailyRequest", mark)
					T.check(#sent == 1 and sent[1].args[1] == "Claim", "fixr daily repair: the repair button sends DailyRequest(\"Claim\")", tostring(#sent))
				end
				-- a kept streak: CLAIM! again at its own size
				local p = H.streak(now, 3, 3)
				p.ReadyAt = now - 1
				p.KeepUntil = now + 28 * 3600
				H.fire(p)
				KC.advance(0.1)
				claim = H.find(H.win(), "ClaimButton")
				T.check(H.shown(claim) and claim.Text == "CLAIM!" and H.cell(4):GetAttribute("Today") == true and H.find(H.cell(4), "Amount").Text ~= "Repair",
					"fixr daily repair: " .. tag .. " a kept streak shows CLAIM! and day 4's gift again", claim and claim.Text or "no button")
				DC.Close()
				KC.advance(0.2)
			end
		end)
		restoreMeasure()
		H.fire(H.base(H.now()))
		restoreScreen()
		if not okRun then
			error(errRun, 0)
		end
		KC.flushErrors("client_fixr_daily_repair")
		KC.flushWarnings("client_fixr_daily_repair")
	end)

	S.client_fixr_boost_pass = guarded("client_fixr_boost_pass", function()
		local BB = H.moduleAt("client", "Controllers/BoostBadgeController")
		local MC = H.moduleAt("client", "Controllers/MenuController")
		if not T.check(BB ~= nil and MC ~= nil, "fixr boost pass: BoostBadgeController and MenuController exist") then
			return
		end
		local w = H.watchMenu(MC)
		local oldPasses, oldEnds = LocalPlayer:GetAttribute("OwnedPasses"), LocalPlayer:GetAttribute("XpBoostEnds")
		local START, WARN = "x2 Pet XP started!", "x2 Pet XP ends in"
		local okRun, errRun = pcall(function()
			-- a PetXp2x owner buys the Starter pack: its 1 h potion lands on XpBoostEnds (the pass already gives x2)
			LocalPlayer:SetAttribute("OwnedPasses", "PetXp2x")
			LocalPlayer:SetAttribute("XpBoostEnds", 0)
			KC.advance(1.1)
			local n = w.count(START)
			LocalPlayer:SetAttribute("XpBoostEnds", H.now() + 3600)
			KC.advance(0.2)
			T.eq(w.count(START) - n, 0, "fixr boost pass: a pass owner's fresh potion says nothing (the pass wins, the potion adds nothing)")
			T.eq(BB.Chips().Xp, "x2 XP", "fixr boost pass: ...the chip stays the pass's untimed 'x2 XP'")
			-- its time left crossing WarnSeconds: no 'ends in 5 min' while the pass keeps x2
			local m = w.count(WARN)
			LocalPlayer:SetAttribute("XpBoostEnds", H.now() + 302)
			KC.advance(1.1)
			KC.advance(3.2)
			T.eq(w.count(WARN) - m, 0, "fixr boost pass: no 'x2 Pet XP ends in 5 min' for a pass owner")
			-- control: without the pass the same crossing warns once
			LocalPlayer:SetAttribute("OwnedPasses", "")
			LocalPlayer:SetAttribute("XpBoostEnds", 0)
			KC.advance(1.1)
			m = w.count(WARN)
			LocalPlayer:SetAttribute("XpBoostEnds", H.now() + 302)
			KC.advance(1.1)
			KC.advance(3.2)
			T.eq(w.count(WARN) - m, 1, "fixr boost pass: (control) without the pass the same crossing warns once")
			-- the pass bought while a potion runs: its end warning stays quiet
			LocalPlayer:SetAttribute("XpBoostEnds", 0)
			KC.advance(1.1)
			m = w.count(WARN)
			LocalPlayer:SetAttribute("XpBoostEnds", H.now() + 303)
			KC.advance(1.1)
			LocalPlayer:SetAttribute("OwnedPasses", "PetXp2x")
			KC.advance(4.2)
			T.eq(w.count(WARN) - m, 0, "fixr boost pass: the pass bought while a potion runs: no end warning for that potion")
		end)
		LocalPlayer:SetAttribute("OwnedPasses", oldPasses)
		LocalPlayer:SetAttribute("XpBoostEnds", oldEnds)
		KC.advance(0.3)
		w.restore()
		if not okRun then
			error(errRun, 0)
		end
		KC.flushErrors("client_fixr_boost_pass")
		KC.flushWarnings("client_fixr_boost_pass")
	end)

	S.client_fixr_daily_fit = guarded("client_fixr_daily_fit", function()
		local restoreScreen = H.saveScreen()
		local DC = H.moduleAt("client", "Controllers/DailyController")
		if not T.check(DC ~= nil, "fixr daily fit: DailyController exists") then
			restoreScreen()
			return
		end
		local restoreMeasure = H.realMeasure()
		local okRun, errRun = pcall(function()
			for _, scr in ipairs({ { 1920, 1080, false, "PC" }, { 844, 390, true, "Phone" }, { 360, 640, true, "Portrait" } }) do
				local tag = fmt("%dx%d (%s)", scr[1], scr[2], scr[4])
				H.setScreen(scr[1], scr[2], scr[3])
				DC.Close()
				KC.advance(0.2)
				local now = H.now()
				local p = H.base(now)
				p.Play.Tiers[4].Ready = true
				p.Play.Seconds = 62 * 60
				H.fire(p)
				DC.Open({ Tab = "Daily" })
				KC.advance(0.3)
				local win = H.win()
				T.check(win ~= nil and DC.IsOpen(), "fixr daily fit: " .. tag .. " (setup) the window opens")
				local bad = H.unfit(H.find(win, "Cells"))
				T.check(#bad == 0, "fixr daily fit: " .. tag .. " every day cell text fits its box (day 7's pet name included)", table.concat(bad, "; "))
				local a7 = H.find(H.cell(7), "Amount")
				T.check(a7 ~= nil and a7.Text ~= "" and a7.Text:find("Wisp", 1, true) ~= nil, "fixr daily fit: " .. tag .. " ...day 7 still names its pet", a7 and a7.Text or "no label")
				H.tapTab("Tab_Play")
				bad = H.unfit(H.find(win, "Tiers"))
				T.check(#bad == 0, "fixr daily fit: " .. tag .. " every play-time cell text fits its box (tier 6's basket included)", table.concat(bad, "; "))
				local r6 = H.find(H.tier(6), "Reward")
				T.check(r6 ~= nil and r6.Text:find("Basket", 1, true) ~= nil, "fixr daily fit: " .. tag .. " ...tier 6 still says what it gives", r6 and r6.Text or "no label")
				DC.Close()
				KC.advance(0.2)
			end
		end)
		restoreMeasure()
		H.fire(H.base(H.now()))
		restoreScreen()
		if not okRun then
			error(errRun, 0)
		end
		KC.flushErrors("client_fixr_daily_fit")
		KC.flushWarnings("client_fixr_daily_fit")
	end)

	S.client_fixr_daily_resize = guarded("client_fixr_daily_resize", function()
		local restoreScreen = H.saveScreen()
		H.setScreen(360, 640, true)
		local DC = H.moduleAt("client", "Controllers/DailyController")
		if not T.check(DC ~= nil, "fixr daily resize: DailyController exists") then
			restoreScreen()
			return
		end
		H.fire(H.base(H.now()))
		DC.Close()
		KC.advance(0.2)
		-- (review round 2) the Gifts button is shown in this world before the window opens (the Close half below needs it)
		local btn = H.btn()
		local shownBefore = H.shown(btn)
		T.check(shownBefore, "fixr daily resize: (setup) the Gifts button is shown at 360x640 before the window opens")
		DC.Open({ Tab = "Daily" })
		KC.advance(0.3)
		T.check(DC.IsOpen() and H.shown(H.win()), "fixr daily resize: (setup) the window is open at 360x640 (Portrait)")
		-- the gui width changes while the screen stays portrait (an emulator switch, a narrow desktop window resized)
		for _, size in ipairs({ { 375, 667 }, { 390, 844 }, { 360, 640 } }) do
			H.setScreen(size[1], size[2], true)
			local gui = H.gui()
			local GW, GH = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
			local win = H.win()
			T.check(DC.IsOpen() and H.shown(win) and H.inside(win, 0, 0, GW, GH),
				fmt("fixr daily resize: %dx%d keeps the open window shown (rebuilt for the new width)", size[1], size[2]), H.desc(win) .. " open " .. tostring(DC.IsOpen()))
		end
		-- (owner 2026-11-13: the Gifts button no longer toggles the open window) the button hides while its window is open;
		-- Close brings it back and its tap opens the window again (never an invisible one)
		T.check(not H.shown(btn), "fixr daily resize: ...the Gifts button hides while its window is open")
		DC.Close()
		local back = H.shown(btn)
		T.check(shownBefore and back, "fixr daily resize: (review round 2) ...the Gifts button is back at once after Close (no poll wait)",
			fmt("shown before %s, after Close %s", tostring(shownBefore), tostring(back)))
		if back then
			H.tap(btn)
			T.check(DC.IsOpen() and H.shown(H.win()), "fixr daily resize: ...after Close the Gifts tap opens it again")
		end
		DC.Close()
		KC.advance(0.3)
		restoreScreen()
		KC.flushErrors("client_fixr_daily_resize")
	end)

	S.client_fixr_menu_cover = guarded("client_fixr_menu_cover", function()
		local restoreScreen = H.saveScreen()
		H.setScreen(360, 640, true)
		local DC = H.moduleAt("client", "Controllers/DailyController")
		local SC = H.moduleAt("client", "Controllers/StoreController")
		local MC = H.moduleAt("client", "Controllers/MenuController")
		if not T.check(DC ~= nil and SC ~= nil and MC ~= nil and type(MC.GetButton) == "function", "fixr menu cover: DailyController, StoreController and MenuController exist") then
			restoreScreen()
			return
		end
		local function tiles()
			local out = {}
			for _, id in ipairs({ "Pets", "Index", "Spot", "Stats" }) do
				local b = MC.GetButton(id)
				if b and H.shown(b) then
					out[#out + 1] = b
				end
			end
			return out
		end
		-- the shown menu tiles that draw over the window `win` (NimbusMenu's DisplayOrder 20 is above the windows' 19)
		local function over(win)
			local out = {}
			if not win then
				return { "no window" }
			end
			local wb = H.box(win)
			for _, b in ipairs(tiles()) do
				if H.overlap(H.box(b), wb) then
					out[#out + 1] = H.desc(b)
				end
			end
			return out
		end
		local function storeWin()
			local gui = H.pg():FindFirstChild("NimbusShop") -- (lobby-shop Task 21: the Store is the Shop window)
			return gui and gui:FindFirstChild("ShopWindow", true)
		end
		local okRun, errRun = pcall(function()
			H.fire(H.base(H.now()))
			DC.Close()
			SC.Close()
			MC.Close()
			KC.advance(0.5)
			T.check(#tiles() > 0, "fixr menu cover: (setup) the menu tiles show at 360x640 with no window open", tostring(#tiles()))
			-- the Gifts window
			DC.Open({ Tab = "Daily" })
			KC.advance(0.5)
			local bad = over(H.win())
			T.check(DC.IsOpen() and #bad == 0, "fixr menu cover: no menu tile draws over the open Gifts window", table.concat(bad, "; ") .. " | " .. H.desc(H.win()))
			DC.Close()
			KC.advance(0.5)
			T.check(#tiles() > 0, "fixr menu cover: ...the tiles come back when it closes")
			-- the Store
			SC.Open()
			KC.advance(0.5)
			bad = over(storeWin())
			T.check(SC.IsOpen() and #bad == 0, "fixr menu cover: no menu tile draws over the open Store", table.concat(bad, "; "))
			-- the Gifts window opened over the Store (the Store closes on WindowOpened): its close never brings the tiles back
			DC.Open({ Tab = "Daily" })
			KC.advance(0.5)
			bad = over(H.win())
			T.check(DC.IsOpen() and not SC.IsOpen() and #bad == 0, "fixr menu cover: the Gifts window opened over the Store stays uncovered", table.concat(bad, "; "))
			-- the Store opened over the Gifts window
			SC.Open()
			KC.advance(0.5)
			bad = over(storeWin())
			T.check(SC.IsOpen() and not DC.IsOpen() and #bad == 0, "fixr menu cover: the Store opened over the Gifts window stays uncovered", table.concat(bad, "; "))
			-- the Pets window, then the Gifts window over it
			SC.Close()
			KC.advance(0.3)
			MC.Open("Pets")
			KC.advance(0.8)
			DC.Open({ Tab = "Daily" })
			KC.advance(0.5)
			bad = over(H.win())
			T.check(DC.IsOpen() and #bad == 0, "fixr menu cover: the Gifts window opened over the Pets window stays uncovered", table.concat(bad, "; "))
			DC.Close()
			MC.Close()
			KC.advance(0.6)
			-- the Sky Trove panel (DisplayOrder 18; a bottom sheet on a portrait phone): no tile over it either
			local TC = H.moduleAt("client", "Controllers/TroveController")
			if TC and type(TC.Open) == "function" then
				TC.Open()
				KC.advance(0.5)
				local tg = H.pg():FindFirstChild("NimbusTrove")
				local tp = tg and tg:FindFirstChild("TrovePanel", true)
				bad = over(tp)
				T.check(TC.IsOpen() and #bad == 0, "fixr menu cover: no menu tile draws over the open Sky Trove panel", table.concat(bad, "; ") .. " | " .. (tp and H.desc(tp) or "no panel"))
				TC.Close()
				KC.advance(0.3)
			end
			T.check(#tiles() > 0, "fixr menu cover: ...and every window closed brings the tiles back", tostring(#tiles()))
		end)
		DC.Close()
		SC.Close()
		MC.Close()
		KC.advance(0.3)
		restoreScreen()
		if not okRun then
			error(errRun, 0)
		end
		KC.flushErrors("client_fixr_menu_cover")
	end)

	S.client_fixr_daily_stale = guarded("client_fixr_daily_stale", function()
		local restoreScreen = H.saveScreen()
		local DC = H.moduleAt("client", "Controllers/DailyController")
		if not T.check(DC ~= nil, "fixr daily stale: DailyController exists") then
			restoreScreen()
			return
		end
		local okRun, errRun = pcall(function()
			H.setScreen(1920, 1080, false)
			DC.Close()
			KC.advance(0.2)
			-- a kept streak (day 3's gift, ready) whose keep deadline passes 2 s from now: DailyService's StaleAt
			local now = H.now()
			local p = H.base(now)
			p.KeepUntil = now + 1
			p.StaleAt = now + 2
			H.fire(p)
			DC.Open({ Tab = "Daily" })
			KC.advance(0.3)
			local claim = H.find(H.win(), "ClaimButton")
			T.check(H.shown(claim) and claim.Text == "CLAIM!" and H.cell(3):GetAttribute("Today") == true,
				"fixr daily stale: (setup) before StaleAt the window shows CLAIM! and day 3's gold cell", claim and claim.Text or "no button")
			KC.advance(3.2) -- the window's 1 s tick runs past StaleAt; no fresh payload yet
			claim = H.find(H.win(), "ClaimButton")
			local count = H.find(H.win(), "Countdown")
			T.check(not H.shown(claim) and H.cell(3):GetAttribute("Today") ~= true,
				"fixr daily stale: past StaleAt the stale payload promises nothing: no CLAIM!, no gold today cell",
				"claim shown " .. tostring(H.shown(claim)) .. " today " .. tostring(H.cell(3):GetAttribute("Today")))
			T.check(H.shown(count) and count.Text == "Getting your gifts ready...", "fixr daily stale: ...the footer waits for the server's fresh payload",
				count and count.Text or "no countdown")
			local mark = #Mock.RemoteLog
			H.tap(claim)
			T.eq(#KC.serverCalls("DailyRequest", mark), 0, "fixr daily stale: ...and nothing can be claimed meanwhile")
			-- the fresh payload (DailyService re-sends it at StaleAt): the repair, its own StaleAt a day later
			now = H.now()
			local fresh = H.repair(now)
			fresh.StaleAt = now + 86400
			H.fire(fresh)
			KC.advance(0.1)
			claim = H.find(H.win(), "ClaimButton")
			T.check(H.shown(claim) and claim.Text == "Repair streak (no gift)" and H.cell(3):GetAttribute("Today") == true,
				"fixr daily stale: the fresh payload shows the repair the claim will make", claim and claim.Text or "no button")
			DC.Close()
			KC.advance(0.2)
		end)
		H.fire(H.base(H.now()))
		restoreScreen()
		if not okRun then
			error(errRun, 0)
		end
		KC.flushErrors("client_fixr_daily_stale")
		KC.flushWarnings("client_fixr_daily_stale")
	end)

	-- re-review round 3, finding 3: the countdown before a claim that will only repair never promises a gift
	S.client_fixr_daily_repair_wait = guarded("client_fixr_daily_repair_wait", function()
		local restoreScreen = H.saveScreen()
		local DC = H.moduleAt("client", "Controllers/DailyController")
		if not T.check(DC ~= nil, "fixr daily repair wait: DailyController exists") then
			restoreScreen()
			return
		end
		local restoreMeasure = H.realMeasure()
		local okRun, errRun = pcall(function()
			for _, scr in ipairs({ { 1920, 1080, false }, { 844, 390, true }, { 360, 640, true } }) do
				local tag = fmt("%dx%d", scr[1], scr[2])
				H.setScreen(scr[1], scr[2], scr[3])
				DC.Close()
				KC.advance(0.2)
				-- right after a repair claim (Paid 10, the missed day took Streak 10 -> 9): the next claim (day 10 <= Paid)
				-- repairs again, 20 h from now (DailyService: Repair = true while not ready yet)
				local now = H.now()
				local p = H.streak(now, 9, 10)
				p.Repair = true
				p.Days[p.Cell].Repair = true
				p.ReadyAt = now + 72000
				p.KeepUntil = now + 48 * 3600
				p.StaleAt = now + 48 * 3600 + 1
				H.fire(p)
				DC.Open({ Tab = "Daily" })
				KC.advance(1.1)
				local win = H.win()
				local claim, count = H.find(win, "ClaimButton"), H.find(win, "Countdown")
				T.check(not H.shown(claim) and H.shown(count) and count.Text:find("^Streak repair in %d+h %d+m$") ~= nil and H.body():find("Next gift", 1, true) == nil,
					"fixr daily repair wait: " .. tag .. " the countdown before a repair claim says 'Streak repair in ...', never 'Next gift in ...'", count and count.Text or "no countdown")
				local ok, detail = H.fits(count)
				local wx, wy, ww, wh = H.rect(win)
				T.check(ok and H.inside(count, wx, wy, wx + ww, wy + wh), "fixr daily repair wait: " .. tag .. " ...its text fits (real font widths), inside the window", detail .. " " .. H.desc(count))
				-- control: the same wait before a paying claim still names the next gift
				local g = H.streak(now, 9, 9)
				g.ReadyAt = now + 72000
				g.KeepUntil = now + 48 * 3600
				H.fire(g)
				KC.advance(1.1)
				count = H.find(H.win(), "Countdown")
				T.check(H.shown(count) and count.Text:find("^Next gift in %d+h %d+m$") ~= nil, "fixr daily repair wait: " .. tag .. " (control) before a paying claim it says 'Next gift in ...'", count and count.Text or "no countdown")
				DC.Close()
				KC.advance(0.2)
			end
		end)
		restoreMeasure()
		H.fire(H.base(H.now()))
		restoreScreen()
		if not okRun then
			error(errRun, 0)
		end
		KC.flushErrors("client_fixr_daily_repair_wait")
		KC.flushWarnings("client_fixr_daily_repair_wait")
	end)

	S.client_fixr_touch_handoff = guarded("client_fixr_touch_handoff", function()
		local restoreScreen = H.saveScreen()
		H.setScreen(360, 640, true)
		local DC = H.moduleAt("client", "Controllers/DailyController")
		local SC = H.moduleAt("client", "Controllers/StoreController")
		local MC = H.moduleAt("client", "Controllers/MenuController")
		local GuiService = game:GetService("GuiService")
		if not T.check(DC ~= nil and SC ~= nil and MC ~= nil, "fixr touch handoff: DailyController, StoreController and MenuController exist") then
			restoreScreen()
			return
		end
		local function touch()
			return GuiService.TouchControlsEnabled
		end
		local okRun, errRun = pcall(function()
			DC.Close()
			SC.Close()
			MC.Close()
			KC.advance(0.6)
			T.check(touch() == true, "fixr touch handoff: (setup) with every window closed the thumbstick and jump button show", tostring(touch()))
			for round = 1, 2 do
				local tag = "fixr touch handoff (round " .. round .. "): "
				-- the Pets window, then the Store over it (the Store lays out before WindowOpened closes the Pets window)
				MC.Open("Pets")
				KC.advance(0.8)
				T.check(touch() == false, tag .. "the Pets window hides Roblox's touch controls", tostring(touch()))
				SC.Open()
				KC.advance(0.5)
				T.check(SC.IsOpen() and touch() == false, tag .. "the Store opened over it keeps them hidden", tostring(touch()))
				SC.Close()
				KC.advance(0.5)
				T.check(not SC.IsOpen() and touch() == true, tag .. "...and closing the Store (the last window) brings them back", tostring(touch()))
				-- the Store, then the Pets window over it (the Pets window lays out before WindowOpened closes the Store)
				SC.Open()
				KC.advance(0.5)
				T.check(touch() == false, tag .. "the Store hides them", tostring(touch()))
				MC.Open("Pets")
				KC.advance(0.8)
				T.check(not SC.IsOpen() and touch() == false, tag .. "the Pets window opened over the Store keeps them hidden", tostring(touch()))
				MC.Close()
				KC.advance(0.6)
				T.check(touch() == true, tag .. "...and closing it (the last window) brings them back", tostring(touch()))
			end
		end)
		DC.Close()
		SC.Close()
		MC.Close()
		KC.advance(0.3)
		restoreScreen()
		if not okRun then
			error(errRun, 0)
		end
		KC.flushErrors("client_fixr_touch_handoff")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
