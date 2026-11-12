-- smoke_common.lua: result reporting shared by smoke_server.lua and smoke_client.lua.
-- Loaded by smoke.py before the scenario files; exposes the global SmokeCommon = { T = reporter, guarded = fn }.
-- Plain Lua 5.1 syntax only.

local T = { results = {}, section = "" }
_G.T = T

local function add(status, name, detail)
	T.results[#T.results + 1] = { status = status, section = T.section, name = tostring(name), detail = detail == nil and "" or tostring(detail) }
end
function T.ok(name, detail)
	add("ok", name, detail)
end
function T.fail(name, detail)
	add("fail", name, detail)
end
function T.warn(name, detail)
	add("warn", name, detail)
end
function T.info(name, detail)
	add("info", name, detail)
end
function T.check(cond, name, detail)
	if cond then
		add("ok", name)
	else
		add("fail", name, detail)
	end
	return cond and true or false
end
function T.near(actual, expected, tolerance, name)
	local ok = type(actual) == "number" and math.abs(actual - expected) <= tolerance
	if ok then
		add("ok", name)
	else
		add("fail", name, "expected " .. tostring(expected) .. " +- " .. tostring(tolerance) .. ", got " .. tostring(actual))
	end
	return ok
end
function T.eq(actual, expected, name)
	if actual == expected then
		add("ok", name)
		return true
	end
	add("fail", name, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
	return false
end
function T.section_(name)
	T.section = name
end

-- Counts many small cases and reports ONE result line (so 300 seeds do not produce 300 lines):
--   local t = T.tally("Easy: layouts are valid"); t:case(ok, "seed 5: reason"); ...; t:report()
-- A failure line shows "bad/total" and the first few examples.
function T.tally(name, maxExamples)
	local tally = { name = name, n = 0, bad = 0, examples = {}, max = maxExamples or 3 }
	function tally:case(ok, example)
		self.n = self.n + 1
		if not ok then
			self.bad = self.bad + 1
			if #self.examples < self.max then
				self.examples[#self.examples + 1] = tostring(example)
			end
		end
		return ok
	end
	function tally:report(extra)
		if self.bad == 0 then
			add("ok", self.name, extra)
		else
			add("fail", self.name, self.bad .. " of " .. self.n .. " failed" .. (extra and (" (" .. extra .. ")") or "") .. ": " .. table.concat(self.examples, " | "))
		end
		return self.bad == 0
	end
	return tally
end

-- true when `list` (array) contains `value`
function T.contains(list, value)
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

-- Numbers that are not NaN / inf.
function T.finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Runs fn() under xpcall; a Lua error becomes a failed check with a traceback.
local function guarded(name, fn)
	return function(...)
		T.section = name
		local args = { ... }
		local ok, err = xpcall(function()
			return fn(unpack(args))
		end, function(e)
			return debug.traceback(tostring(e), 2)
		end)
		if not ok then
			add("fail", name .. ": scenario aborted", err)
		end
		-- script errors raised in game threads
		return ok
	end
end


SmokeCommon = { T = T, guarded = guarded, add = add }

-- slop-audit win 6 (2026-11-12; review round 1: the ONE check every window's close button goes through, client world).
-- The problems of a close button's drawn X (NeonKit.CloseMark); {} = a good X:
--   a TextButton with no text anywhere on it reading X / x / U+2715 / U+00D7 and no image; a CloseMark Frame child (not
--   Active, the button not clipping, drawn above the button's other children) centred on the button within 1 px and
--   inside it; BarA (+45) / BarB (-45) white bars over InkA / InkB dark bars (larger, drawn under the white ones), every
--   bar shown, not Active, no UIStroke; with opts.MinTap (a phone window: 44) the button is at least that big.
-- opts.Shown: the visibility test (default KC.isShown in the client world).
SmokeCommon.CLOSE_TEXTS = { "X", "x", "\226\156\149", "\195\151" }
function SmokeCommon.closeMarkIssues(button, opts)
	opts = type(opts) == "table" and opts or {}
	local KCw = rawget(_G, "KC")
	local shown = opts.Shown or (KCw and KCw.isShown) or function(o)
		return o.Visible ~= false
	end
	local sfmt, abs = string.format, math.abs
	local out = {}
	if not (button and button:IsA("TextButton")) then
		return { "no TextButton" }
	end
	local list = { button }
	for _, d in ipairs(button:GetDescendants()) do
		list[#list + 1] = d
	end
	for _, d in ipairs(list) do
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			for _, bad in ipairs(SmokeCommon.CLOSE_TEXTS) do
				if tostring(d.Text):find(bad, 1, true) then
					out[#out + 1] = sfmt("%s reads '%s'", d.Name, tostring(d.Text))
					break
				end
			end
		elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
			out[#out + 1] = "an image " .. d.Name
		end
	end
	local bp, bs = button.AbsolutePosition, button.AbsoluteSize
	if opts.MinTap and (bs.X < opts.MinTap or bs.Y < opts.MinTap) then
		out[#out + 1] = sfmt("tap %.0fx%.0f < %d", bs.X, bs.Y, opts.MinTap)
	end
	local mark = button:FindFirstChild("CloseMark")
	if not (mark and mark:IsA("Frame")) then
		out[#out + 1] = "no CloseMark Frame child"
		return out
	end
	if mark.Active ~= false or button.ClipsDescendants then
		out[#out + 1] = sfmt("mark Active %s, button ClipsDescendants %s", tostring(mark.Active), tostring(button.ClipsDescendants))
	end
	for _, c in ipairs(button:GetChildren()) do
		if c ~= mark and c:IsA("GuiObject") and c.ZIndex >= mark.ZIndex then
			out[#out + 1] = sfmt("%s (z %d) is not under the mark (z %d)", c.Name, c.ZIndex, mark.ZIndex)
		end
	end
	local mp, ms = mark.AbsolutePosition, mark.AbsoluteSize
	if abs(bp.X + bs.X / 2 - (mp.X + ms.X / 2)) > 1 or abs(bp.Y + bs.Y / 2 - (mp.Y + ms.Y / 2)) > 1 then
		out[#out + 1] = sfmt("mark centre %.1f,%.1f vs button centre %.1f,%.1f", mp.X + ms.X / 2, mp.Y + ms.Y / 2, bp.X + bs.X / 2, bp.Y + bs.Y / 2)
	end
	if ms.X < 4 or ms.Y < 4 or mp.X < bp.X - 0.5 or mp.Y < bp.Y - 0.5 or mp.X + ms.X > bp.X + bs.X + 0.5 or mp.Y + ms.Y > bp.Y + bs.Y + 0.5 then
		out[#out + 1] = sfmt("mark %.1f,%.1f %.1fx%.1f not inside button %.1f,%.1f %.1fx%.1f", mp.X, mp.Y, ms.X, ms.Y, bp.X, bp.Y, bs.X, bs.Y)
	end
	local parts = {}
	for _, want in ipairs({ { "BarA", 45, true }, { "BarB", -45, true }, { "InkA", 45, false }, { "InkB", -45, false } }) do
		local bar = mark:FindFirstChild(want[1])
		parts[want[1]] = bar
		local c = bar and bar.BackgroundColor3
		if not (bar and bar:IsA("Frame")) then
			out[#out + 1] = "no " .. want[1]
		elseif bar.Rotation ~= want[2] then
			out[#out + 1] = sfmt("%s.Rotation %s (want %d)", want[1], tostring(bar.Rotation), want[2])
		elseif not (shown(bar) and bar.BackgroundTransparency <= 0.2 and bar.AbsoluteSize.X >= 4 and bar.AbsoluteSize.Y >= 1) then
			out[#out + 1] = want[1] .. " is not visible"
		elseif bar.Active ~= false or bar:FindFirstChildOfClass("UIStroke") then
			out[#out + 1] = want[1] .. " is Active or has a UIStroke"
		elseif want[3] and not (c.R > 0.9 and c.G > 0.9 and c.B > 0.9) then
			out[#out + 1] = want[1] .. " is not white " .. tostring(c)
		elseif not want[3] and not (c.R < 0.25 and c.G < 0.25 and c.B < 0.25) then
			out[#out + 1] = want[1] .. " is not dark " .. tostring(c)
		end
	end
	for _, pair in ipairs({ { "BarA", "InkA" }, { "BarB", "InkB" } }) do
		local bar, ink = parts[pair[1]], parts[pair[2]]
		if bar and ink and not (ink.AbsoluteSize.X > bar.AbsoluteSize.X and ink.AbsoluteSize.Y > bar.AbsoluteSize.Y and ink.ZIndex < bar.ZIndex
			and parts.InkA and parts.InkB and bar.ZIndex > math.max(parts.InkA.ZIndex, parts.InkB.ZIndex)) then
			out[#out + 1] = pair[2] .. " is not a larger dark bar under " .. pair[1]
		end
	end
	return out
end

-- (battle-feel T3, the real server cast) a special press's effects land BattleCatalog.Damage.SpecialCast[kind] s after the
-- press (Cast event first, the Special + its hits at `at`). `evs` = the events of the step after the press: when they hold
-- a Cast of unit `unitId` (any unit when nil) and no Special of it, the battle is stepped `dt` (0.05) at a time until its
-- Special. -> the events of the step the Special came in (`evs` itself on the instant path), the battle time it landed at
-- (the time its effects used: the old tests' "t0", the press time on the instant path), and the Cast event (nil on the
-- instant path)
function SmokeCommon.pastCast(battle, evs, unitId, dt)
	local function find(list, kind)
		for _, ev in ipairs(list or {}) do
			if ev.type == kind and (unitId == nil or ev.unit == unitId) then
				return ev
			end
		end
		return nil
	end
	local cast = find(evs, "Cast")
	if not cast or find(evs, "Special") then
		return evs, nil, nil
	end
	local guard = 0
	while guard < 80 do
		guard = guard + 1
		local step = battle:Step(dt or 0.05)
		if find(step, "Special") or find(step, "CastBreak") then
			return step, battle:Time(), cast
		end
	end
	return {}, battle:Time(), cast
end

-- Phase 5 (7.2): every smoke scenario runs with the main menu DISABLED ("what every existing smoke scenario and the mock
-- get unless a test sets Enabled"): the character spawns at once on join and nothing is gated. Set here, in the common
-- boot of every world (smoke.py loads this file right after mounting src/ and before any scenario file), so it does not
-- depend on which scenario files load or in which order; smoke_p5_menu.lua turns it on only inside its menu scenarios.
do
	local okRs, rs = pcall(function()
		return game:GetService("ReplicatedStorage")
	end)
	local shared = okRs and rs and rs:FindFirstChild("Shared")
	local inst = shared and shared:FindFirstChild("Config")
	if inst then
		local ok, Config = pcall(require, inst)
		if ok and type(Config) == "table" and type(Config.MainMenu) == "table" then
			Config.MainMenu.Enabled = false
		end
	end
end
