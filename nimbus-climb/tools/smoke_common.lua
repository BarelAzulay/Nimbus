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

-- Real text widths (moved here from smoke_redo_geom.lua, T0 review: the world sign fit check of smoke_polish_worldtext.lua
-- needs them in the server world too): the advance widths (1/1000 em) of ASCII 32..126 per face; any other character
-- counts 0.6 em. Luckiest: Roblox's shipped LuckiestGuy-Regular.ttf; Fredoka: FredokaOne; Builder: Builder Sans Bold;
-- Gotham (Montserrat Black widths) is the fallback for any other name.
SmokeCommon.Advance = {
	Luckiest = { 195, 279, 480, 606, 437, 725, 630, 232, 389, 382, 542, 456, 223, 382, 222, 505, 633, 388, 509, 528, 539, 531, 573, 506, 571, 555, 248, 247, 455, 391, 455, 554, 665, 626, 594, 515, 583, 479, 487, 626, 626, 297, 510, 614, 452, 791, 704, 638, 596, 691, 606, 531, 543, 623, 613, 908, 588, 607, 487, 366, 505, 365, 485, 302, 283, 626, 594, 513, 584, 577, 488, 627, 626, 294, 510, 603, 451, 898, 652, 638, 597, 691, 606, 532, 545, 611, 614, 910, 595, 605, 496, 410, 287, 402, 576 },
	Fredoka = { 253, 267, 429, 749, 475, 838, 748, 208, 384, 384, 503, 527, 238, 433, 237, 526, 608, 407, 609, 608, 592, 530, 560, 561, 582, 560, 238, 237, 627, 478, 627, 512, 908, 765, 646, 679, 704, 638, 637, 714, 699, 257, 549, 639, 587, 870, 720, 775, 632, 830, 631, 583, 731, 726, 783, 999, 741, 686, 643, 348, 528, 348, 526, 826, 482, 596, 592, 517, 598, 573, 450, 585, 605, 255, 252, 536, 327, 851, 606, 600, 582, 582, 457, 489, 449, 606, 638, 793, 567, 604, 586, 381, 217, 381, 651 },
	Gotham = { 300, 314, 489, 740, 657, 917, 777, 254, 381, 381, 473, 620, 304, 390, 304, 440, 692, 418, 608, 614, 712, 619, 661, 645, 678, 661, 304, 304, 620, 620, 620, 606, 1037, 806, 773, 744, 826, 673, 644, 769, 804, 350, 574, 765, 617, 954, 804, 848, 743, 848, 745, 657, 654, 784, 786, 1206, 762, 710, 687, 410, 440, 410, 620, 500, 600, 639, 700, 615, 705, 653, 426, 711, 702, 326, 334, 713, 326, 1040, 702, 678, 700, 700, 456, 565, 460, 698, 644, 977, 645, 644, 570, 438, 320, 438, 620 },
	Builder = { 250, 278, 458, 685, 580, 894, 704, 268, 366, 366, 431, 518, 264, 350, 264, 424, 646, 407, 585, 587, 612, 589, 615, 528, 632, 615, 292, 292, 518, 518, 518, 541, 919, 704, 635, 677, 702, 576, 574, 693, 720, 280, 505, 649, 566, 894, 720, 745, 627, 745, 641, 574, 556, 690, 716, 960, 658, 642, 559, 377, 424, 377, 476, 422, 276, 566, 613, 533, 613, 567, 405, 616, 601, 260, 255, 531, 260, 879, 601, 590, 613, 613, 415, 483, 403, 591, 574, 806, 536, 574, 465, 478, 294, 478, 600 },
}
SmokeCommon.Faces = { FredokaOne = "Fredoka", BuilderSansBold = "Builder", BuilderSans = "Builder", BuilderSansMedium = "Builder", BuilderSansExtraBold = "Builder", LuckiestGuy = "Luckiest" }

-- the width in px of `text` at `size` in `font` (an Enum.Font or its name). known = true: nil for a face outside the
-- table but Gotham's own (the caller keeps its own estimate); otherwise any other face measures as Gotham
function SmokeCommon.RealWidth(text, size, font, known)
	local name = (typeof(font) == "EnumItem" and font.Name) or tostring(font)
	local face = SmokeCommon.Faces[name] or ((name:find("^Gotham") or not known) and "Gotham" or nil)
	if not face then
		return nil
	end
	local adv = SmokeCommon.Advance[face]
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

-- kit-b U6 review: the contrast rule (client world). kit B gives a text no outline on a surface; it reads by its colour
-- against what is painted under it. For a text with no outline (no Contextual UIStroke, no classic stroke): the sample
-- point is the centre of its glyphs (TextBounds placed by its alignment inside its padded box); its backdrop is the last
-- opaque fill (0.7 or more: BackgroundTransparency times its UIGradient's transparency) painted before the text whose box,
-- inside its clipping ancestors, holds that point (paint order as Roblox and tools/render_gui.py: ScreenGuis by
-- DisplayOrder, Sibling = parent then children by ZIndex, Global = every object by ZIndex); see-through plates painted
-- between them are blended in. A gradient fill is read where the glyphs are (the centre and four points across the
-- text's bounds, the gradient laid out as Roblox / the renderer draw it) and the worst point counts. The contrast must be
-- 3:1 for text of 18 px and up, 4.5:1 below (WCAG). An image, a viewport or a turned object over the point means "unknown" (not checked),
-- so does no backdrop at all (text over the world keeps one outline instead: the stroke walk); colour emoji are not
-- checked (Roblox draws them in their own colours). tools/render_gui.py's contrast_rule is the same rule over the dumps.
local Contrast = {}
SmokeCommon.Contrast = Contrast

local function lin(v)
	if v <= 0.04045 then
		return v / 12.92
	end
	return ((v + 0.055) / 1.055) ^ 2.4
end
function Contrast.Ratio(a, b)
	local la = 0.2126 * lin(a.R) + 0.7152 * lin(a.G) + 0.0722 * lin(a.B)
	local lb = 0.2126 * lin(b.R) + 0.7152 * lin(b.G) + 0.0722 * lin(b.B)
	if la < lb then
		la, lb = lb, la
	end
	return (la + 0.05) / (lb + 0.05)
end

-- a NumberSequence's value at time t (linear between keypoints)
local function seqAt(seq, t)
	local kps = seq and seq.Keypoints
	if not kps or #kps == 0 then
		return 0
	end
	for i = 1, #kps - 1 do
		local a, b = kps[i], kps[i + 1]
		if t >= a.Time and t <= b.Time then
			local f = (b.Time > a.Time) and (t - a.Time) / (b.Time - a.Time) or 0
			return a.Value + (b.Value - a.Value) * f
		end
	end
	return kps[#kps].Value
end

-- a ColorSequence's colour at time t (linear between keypoints)
local function colorAt(seq, t)
	local kps = seq and seq.Keypoints
	if not kps or #kps == 0 then
		return Color3.new(1, 1, 1)
	end
	for i = 1, #kps - 1 do
		local a, b = kps[i], kps[i + 1]
		if t >= a.Time and t <= b.Time then
			local f = (b.Time > a.Time) and (t - a.Time) / (b.Time - a.Time) or 0
			return a.Value:Lerp(b.Value, f)
		end
	end
	return kps[#kps].Value
end

-- the colours an opaque fill (list item) shows at the sample points {{x, y}, ...}: its colour (times its UIGradient
-- there) where it is 0.7 opaque or more; {} when it is opaque at none of them
local function fillColors(item, points)
	local obj = item.obj
	local base = obj.BackgroundColor3
	local alpha = 1 - (tonumber(obj.BackgroundTransparency) or 1)
	local g = obj:FindFirstChildWhichIsA("UIGradient")
	if not (g and g.Enabled ~= false) then
		return alpha > 0.7 and { base } or {}
	end
	local b = item.box
	local w, h = math.max(b[3] - b[1], 1e-6), math.max(b[4] - b[2], 1e-6)
	local okOff, off = pcall(function()
		return g.Offset
	end)
	if not (okOff and typeof(off) == "Vector2") then
		off = Vector2.new(0, 0)
	end
	local th = math.rad(tonumber(g.Rotation) or 0)
	local out = {}
	for _, p in ipairs(points) do
		local xs = (p[1] - b[1]) / w - off.X - 0.5
		local ys = (p[2] - b[2]) / h - off.Y - 0.5
		local t = math.min(1, math.max(0, 0.5 + xs * math.cos(th) + ys * math.sin(th)))
		if alpha * (1 - seqAt(g.Transparency, t)) > 0.7 then
			local c = colorAt(g.Color, t)
			out[#out + 1] = Color3.new(base.R * c.R, base.G * c.G, base.B * c.B)
		end
	end
	return out
end

-- true when every visible character is a colour emoji (a 4-byte UTF-8 code point, U+10000 and up, or a variation selector
-- / joiner): Roblox draws those in their own colours, whatever TextColor3 says
local function colourEmoji(text)
	local rest = text:gsub("[\240-\244][\128-\191][\128-\191][\128-\191]", ""):gsub("\239\184\143", ""):gsub("\226\128\141", "")
	return rest == "" and text ~= ""
end

local function isText(o)
	return o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")
end

local function outlined(o)
	if (tonumber(o.TextStrokeTransparency) or 1) < 0.95 then
		return true
	end
	for _, c in ipairs(o:GetChildren()) do
		if c:IsA("UIStroke") and c.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual and c.Enabled ~= false and (tonumber(c.Thickness) or 0) > 0 and (tonumber(c.Transparency) or 0) < 0.95 then
			return true
		end
	end
	return false
end

-- every shown GuiObject of the ScreenGuis under `pg` in paint order: { obj, box = {x0, y0, x1, y1} (screen px), clip =
-- {x0, y0, x1, y1} or nil, turned = bool, gui = ScreenGui }
function Contrast.PaintList(pg)
	local Mock = rawget(_G, "Mock")
	local guis = {}
	for i, g in ipairs(pg:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled ~= false then
			guis[#guis + 1] = { g = g, i = i }
		end
	end
	table.sort(guis, function(a, b)
		local da, db = tonumber(a.g.DisplayOrder) or 0, tonumber(b.g.DisplayOrder) or 0
		if da ~= db then
			return da < db
		end
		return a.i < b.i
	end)
	local list = {}
	for _, entry in ipairs(guis) do
		local g = entry.g
		local inset = (g.IgnoreGuiInset == false) and (Mock.TopInset or 0) or 0
		local flat = {}
		local function visit(o, clip, turned, global)
			local b = Mock.GuiBox(o)
			local item = { obj = o, box = { b.x, b.y + inset, b.x + b.w, b.y + b.h + inset }, clip = clip, gui = g,
				turned = turned or math.abs(tonumber(o.Rotation) or 0) >= 1, n = #flat + 1 }
			flat[#flat + 1] = item
			local childClip = clip
			if o.ClipsDescendants == true or o:IsA("ScrollingFrame") then
				local bx = item.box
				childClip = clip and { math.max(clip[1], bx[1]), math.max(clip[2], bx[2]), math.min(clip[3], bx[3]), math.min(clip[4], bx[4]) } or bx
			end
			local kids = {}
			for i, c in ipairs(o:GetChildren()) do
				if c:IsA("GuiObject") and c.Visible ~= false and not (c:IsA("CanvasGroup") and (tonumber(c.GroupTransparency) or 0) > 0.5) then
					kids[#kids + 1] = { c = c, i = i }
				end
			end
			if not global then
				table.sort(kids, function(a, b)
					if a.c.ZIndex ~= b.c.ZIndex then
						return a.c.ZIndex < b.c.ZIndex
					end
					return a.i < b.i
				end)
			end
			for _, k in ipairs(kids) do
				visit(k.c, childClip, item.turned, global)
			end
		end
		local global = g.ZIndexBehavior == Enum.ZIndexBehavior.Global
		local tops = {}
		for i, c in ipairs(g:GetChildren()) do
			if c:IsA("GuiObject") and c.Visible ~= false then
				tops[#tops + 1] = { c = c, i = i }
			end
		end
		table.sort(tops, function(a, b)
			if a.c.ZIndex ~= b.c.ZIndex then
				return a.c.ZIndex < b.c.ZIndex
			end
			return a.i < b.i
		end)
		for _, t in ipairs(tops) do
			visit(t.c, nil, false, global)
		end
		if global then
			table.sort(flat, function(a, b)
				if a.obj.ZIndex ~= b.obj.ZIndex then
					return a.obj.ZIndex < b.obj.ZIndex
				end
				return a.n < b.n
			end)
		end
		for _, item in ipairs(flat) do
			list[#list + 1] = item
		end
	end
	return list
end

local function holds(item, x, y)
	local b, c = item.box, item.clip
	if x < b[1] or x > b[3] or y < b[2] or y > b[4] then
		return false
	end
	return not c or (x >= c[1] and x <= c[3] and y >= c[2] and y <= c[4])
end

-- the glyph sample points of a text item: its glyph centre first, then four points across its text bounds, those its
-- clip shows (nil when it shows none)
local function samplePoints(item)
	local o, b = item.obj, item.box
	local x0, y0, x1, y1 = b[1], b[2], b[3], b[4]
	local s = (rawget(_G, "Mock").GuiBox(o).scale) or 1
	local pad = o:FindFirstChildWhichIsA("UIPadding")
	if pad then
		local w, h = x1 - x0, y1 - y0
		x0 = x0 + pad.PaddingLeft.Scale * w + pad.PaddingLeft.Offset * s
		x1 = x1 - pad.PaddingRight.Scale * w - pad.PaddingRight.Offset * s
		y0 = y0 + pad.PaddingTop.Scale * h + pad.PaddingTop.Offset * s
		y1 = y1 - pad.PaddingBottom.Scale * h - pad.PaddingBottom.Offset * s
	end
	local ok, tb = pcall(function()
		return o.TextBounds
	end)
	local tw = (ok and tb) and math.min(tb.X * s, x1 - x0) or (x1 - x0)
	local th = (ok and tb) and math.min(tb.Y * s, y1 - y0) or (y1 - y0)
	local x, y = (x0 + x1) / 2, (y0 + y1) / 2
	if o.TextXAlignment == Enum.TextXAlignment.Left then
		x = x0 + tw / 2
	elseif o.TextXAlignment == Enum.TextXAlignment.Right then
		x = x1 - tw / 2
	end
	if o.TextYAlignment == Enum.TextYAlignment.Top then
		y = y0 + th / 2
	elseif o.TextYAlignment == Enum.TextYAlignment.Bottom then
		y = y1 - th / 2
	end
	-- a clip keeps the points strictly inside it; the first one shown is where the backdrop is looked up
	local c = item.clip
	local pts = {}
	local function add(px, py)
		if not c or (px > c[1] and px < c[3] and py > c[2] and py < c[4]) then
			pts[#pts + 1] = { px, py }
		end
	end
	add(x, y)
	for _, dx in ipairs({ -1, 1 }) do
		for _, dy in ipairs({ -1, 1 }) do
			add(x + dx * tw * 0.35, y + dy * th * 0.3)
		end
	end
	return (#pts > 0) and pts or nil
end

-- the contrast reading of the text at list[index]: nil when not checked (outlined, faded, empty, turned, no known
-- backdrop), else { ratio, need, backdrop = obj, color = the worst stop, size = px }
function Contrast.Read(list, index)
	local item = list[index]
	local o = item.obj
	if not isText(o) or item.turned or outlined(o) or (tonumber(o.TextTransparency) or 0) > 0.5 then
		return nil
	end
	local text = tostring(o.Text or ""):gsub("<[^>]->", ""):gsub("%s", "")
	if text == "" or colourEmoji(text) then
		return nil
	end
	local pts = samplePoints(item)
	if not pts then
		return nil
	end
	local x, y = pts[1][1], pts[1][2]
	local top, fills, veils = nil, nil, {}
	for i = index, 1, -1 do
		local it = list[i]
		local p = it.obj
		if holds(it, x, y) then
			local image = ((p:IsA("ImageLabel") or p:IsA("ImageButton")) and tostring(p.Image or "") ~= "" and (tonumber(p.ImageTransparency) or 0) < 0.3)
				or p:IsA("ViewportFrame") or p:IsA("VideoFrame")
			local inside = {}
			for _, q in ipairs(pts) do
				local b = it.box
				if q[1] >= b[1] and q[1] <= b[3] and q[2] >= b[2] and q[2] <= b[4] then
					inside[#inside + 1] = q
				end
			end
			local colors = fillColors(it, inside)
			if i < index and (image or (it.turned and #colors > 0)) then
				return nil -- an image, a viewport or a turned plate: unknown
			end
			if #colors > 0 then
				top, fills = p, colors
				break
			end
			local a = 1 - (tonumber(p.BackgroundTransparency) or 1)
			if a > 0.01 then
				local vc = p.BackgroundColor3
				local g = p:FindFirstChildWhichIsA("UIGradient")
				if g and g.Enabled ~= false then
					local b = it.box
					local th = math.rad(tonumber(g.Rotation) or 0)
					local xs = (x - b[1]) / math.max(b[3] - b[1], 1e-6) - 0.5
					local ys = (y - b[2]) / math.max(b[4] - b[2], 1e-6) - 0.5
					local t = math.min(1, math.max(0, 0.5 + xs * math.cos(th) + ys * math.sin(th)))
					local gc = colorAt(g.Color, t)
					vc, a = Color3.new(vc.R * gc.R, vc.G * gc.G, vc.B * gc.B), a * (1 - seqAt(g.Transparency, t))
				end
				veils[#veils + 1] = { vc, a } -- a see-through plate over the fill: blended in
			end
		end
	end
	if not top then
		return nil
	end
	for v = #veils, 1, -1 do
		local vc, va = veils[v][1], veils[v][2]
		for k, f in ipairs(fills) do
			fills[k] = f:Lerp(vc, va)
		end
	end
	local s = (rawget(_G, "Mock").GuiBox(o).scale) or 1
	local size = (tonumber(o.TextSize) or 14) * s
	if o.TextScaled then
		size = math.min(item.box[4] - item.box[2], 100 * s)
	end
	local need = size >= 18 and 3 or 4.5
	local worst, worstColor = math.huge, nil
	for _, c in ipairs(fills) do
		local r = Contrast.Ratio(o.TextColor3, c)
		if r < worst then
			worst, worstColor = r, c
		end
	end
	return { ratio = worst, need = need, backdrop = top, color = worstColor, size = size }
end

-- tools/fixtures/contrast_backlog.txt as Lua patterns: the texts U6 left below the rule outside the review's families (a GUI
-- path per line, "*" = any run of characters but a dot, "#" a comment); a hit there is counted, not failed. `file` reads
-- another backlog of the same form (U7a: tools/fixtures/emoji_backlog.txt)
function Contrast.Backlog(file)
	local out = {}
	local fh = io and io.open and io.open(file or "tools/fixtures/contrast_backlog.txt", "r")
	if not fh then
		return out
	end
	for line in fh:lines() do
		line = line:gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" then
			out[#out + 1] = "^" .. line:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", "[^.]*") .. "$"
		end
	end
	fh:close()
	return out
end

-- every text under `pg` below its need and not in the backlog: { "path: #RRGGBB on #RRGGBB (backdrop) 2.1:1 < 3 at 26 px" },
-- the count read, and the count of backlog hits
function Contrast.Walk(pg)
	local list = Contrast.PaintList(pg)
	local backlog = Contrast.Backlog()
	local bad, read, owed = {}, 0, 0
	local function hx(c)
		return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
	end
	for i = 1, #list do
		local r = Contrast.Read(list, i)
		if r then
			read = read + 1
			if r.ratio < r.need then
				local o = list[i].obj
				local path = o:GetFullName():gsub("^Players%.[^.]+%.PlayerGui%.", "")
				local known = false
				for _, pattern in ipairs(backlog) do
					if path:find(pattern) then
						known = true
						break
					end
				end
				if known then
					owed = owed + 1
				else
					bad[#bad + 1] = string.format("%s \"%s\": %s on %s (%s) %.1f:1 < %g at %.0f px", path, tostring(o.Text):sub(1, 24),
						hx(o.TextColor3), hx(r.color), r.backdrop.Name, r.ratio, r.need, r.size)
				end
			end
		end
	end
	table.sort(bad)
	return bad, read, owed
end

-- (kit-b U7a) the emoji rule, the same ranges as render_gui.is_emoji (tools/stroke_walk.py --emoji): kit B draws its icons
-- (PixelIcon), so a shown text carries no emoji and no pictographic symbol (arrows, the clocks, geometric shapes, the
-- miscellaneous symbols and dingbats, the stars block, U+1F000 and up, the emoji joiners); typography stays
local Emoji = {}
SmokeCommon.Emoji = Emoji
Emoji.BACKLOG = "tools/fixtures/emoji_backlog.txt"

function Emoji.Is(cp)
	return cp >= 0x1F000 or cp == 0xFE0F or cp == 0x200D or cp == 0x20E3 or (cp >= 0x2190 and cp <= 0x21FF)
		or (cp >= 0x2300 and cp <= 0x23FF) or (cp >= 0x25A0 and cp <= 0x27BF) or (cp >= 0x2900 and cp <= 0x297F)
		or (cp >= 0x2B00 and cp <= 0x2BFF)
end

-- the emoji code points of a UTF-8 string, as "U+XXXX" strings (rich-text tags dropped)
function Emoji.Find(s)
	s = tostring(s or ""):gsub("<[^>]*>", "")
	local out, i = {}, 1
	while i <= #s do
		local c = s:byte(i)
		local n, cp = 1, c
		if c >= 0xF0 then
			n, cp = 4, c % 0x08
		elseif c >= 0xE0 then
			n, cp = 3, c % 0x10
		elseif c >= 0xC0 then
			n, cp = 2, c % 0x20
		end
		for k = 1, n - 1 do
			cp = cp * 64 + ((s:byte(i + k) or 0x80) % 0x40)
		end
		if Emoji.Is(cp) then
			out[#out + 1] = string.format("U+%04X", cp)
		end
		i = i + n
	end
	return out
end

-- is a text object shown: its own text not see-through, every GuiObject up to its LayerCollector Visible, that Enabled
function Emoji.Shown(o)
	if (tonumber(o.TextTransparency) or 0) >= 0.99 then
		return false
	end
	local p = o
	while p do
		if p:IsA("LayerCollector") then
			return p.Enabled ~= false
		end
		if p:IsA("GuiObject") and p.Visible == false then
			return false
		end
		p = p.Parent
	end
	return true
end

-- every shown text under `pg` with an emoji code point: hits[path] = "text U+XXXX ...", and backlog hits counted apart
-- (owed[path] = true); `hits` / `owed` may be passed in to gather several walks
function Emoji.Walk(pg, hits, owed)
	hits, owed = hits or {}, owed or {}
	local backlog = Contrast.Backlog(Emoji.BACKLOG)
	for _, d in ipairs(pg:GetDescendants()) do
		if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and Emoji.Shown(d) then
			local cps = Emoji.Find(d.Text)
			if #cps > 0 then
				local path = d:GetFullName():gsub("^Players%.[^.]+%.PlayerGui%.", "")
				local known = false
				for _, pattern in ipairs(backlog) do
					if path:find(pattern) then
						known = true
						break
					end
				end
				if known then
					owed[path] = true
				else
					hits[path] = table.concat(cps, " ")
				end
			end
		end
	end
	return hits, owed
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
