-- smoke_redo_geom.lua: the geometry helper of the window redo tests (docs/superpowers/plans/2026-11-06-window-redo.md
-- Task 6). Loaded by tools/smoke.py in the client and phone worlds BEFORE every other smoke_redo_* client file that uses
-- it; it sets the global RedoGeom and returns no scenario:
--   RedoGeom.at(w, h, touch, label, fn)   runs fn() at a w x h screen (touch = a touch-only device: no keyboard, no mouse),
--                                          KC.advance(0.6) after the switch; restores the screen and the input flags and
--                                          reports the client errors raised meanwhile under `label` (the smoke_tb_pets.lua
--                                          H.at shape, without its profile and windows: the caller sets those)
--   RedoGeom.check(root, label, opts) -> boolean   every visible GuiObject under root (root included):
--       * text: every non-empty text is at least opts.MinText (default 14) px on screen (TextSize x the UIScale chain, the
--         FxScale / Pop press and open scales left out, or the box height when TextScaled: the KC.smallTexts rule); a
--         TextBox with no text is measured by its placeholder
--       * targets: every visible active GuiButton and every TextBox is at least opts.MinTarget (default 44) px on both sides
--       * screen: every visible GuiObject lies inside the screen and below the gui inset (58 px) in screen px (the inset is
--         added when its ScreenGui does not ignore it); a descendant of a ScrollingFrame under root is clipped by it, so it
--         only has to touch the scroller's box (one fully outside is scrolled away and skipped by every rule)
--       * overlap: the shown boxes of the descendants named in opts.NoOverlap (each name: the first descendant with it)
--         never intersect each other (touching edges is fine)
--       opts.Skip = { [name] = true } leaves those objects and everything under them out. One T.check per rule; the
--       result is true when all of them passed.
--   RedoGeom.find(root, name)   the first descendant called `name` (breadth first), or nil
--   RedoGeom.desc(o)            "Name x,y wxh" in screen px (nil -> "nil")
--   RedoGeom.realWidth(text, size, font) -> px   (Task 9) the text's width with Roblox's real font advances (the mock
--                                          measures a flat 0.5 em; the table is smoke_fixr_daily_ui.lua's: FredokaOne for
--                                          Display, BuilderSans for Body / Label, Montserrat-Black for the GothamBlack roles)
--   RedoGeom.fits(o) -> ok, detail         (Task 9) does o's text fit its box (less its UIPadding) with the real widths: one
--                                          line, or the word-wrapped rows when TextWrapped; TextScaled always fits
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local fmt = string.format

local INSET = 58
local TOL = 0.51

local G = {}

local function kc()
	return _G.KC
end

-- the UIScale chain of an object (the press "FxScale" and the open "Pop" scales are animation, not layout)
local function scaleOf(inst)
	local scale = 1
	local cur = inst
	while cur and cur ~= game do
		if cur:IsA("GuiObject") then
			for _, c in ipairs(cur:GetChildren()) do
				if c:IsA("UIScale") and c.Name ~= "FxScale" and c.Name ~= "Pop" then
					scale = scale * c.Scale
				end
			end
		end
		cur = cur.Parent
	end
	return scale
end

local function shownIn(obj)
	local cur = obj
	while cur and cur ~= game do
		if cur:IsA("LayerCollector") then
			if cur.Enabled == false then
				return false
			end
		elseif cur:IsA("GuiObject") then
			if cur.Visible == false then
				return false
			end
		end
		cur = cur.Parent
	end
	return true
end

local function boxOf(o)
	local p, s = o.AbsolutePosition, o.AbsoluteSize
	return { x = p.X, y = p.Y, w = s.X, h = s.Y }
end

local function insetOf(o)
	local gui = o:FindFirstAncestorOfClass("ScreenGui")
	if gui and gui.IgnoreGuiInset == false then
		return INSET
	end
	return 0
end

local function intersects(a, b)
	return a.x < b.x + b.w - TOL and b.x < a.x + a.w - TOL and a.y < b.y + b.h - TOL and b.y < a.y + a.h - TOL
end

-- the nearest ScrollingFrame between o (exclusive) and root (inclusive), or nil
local function scrollerOf(o, root)
	local cur = o.Parent
	while cur and cur ~= game do
		if cur:IsA("ScrollingFrame") then
			return cur
		end
		if cur == root then
			return nil
		end
		cur = cur.Parent
	end
	return nil
end

local function isText(o)
	return o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")
end

local function shownText(o)
	local t = tostring(o.Text or "")
	if o:IsA("TextBox") and t == "" then
		t = tostring(o.PlaceholderText or "")
	end
	t = t:gsub("<[^>]*>", "")
	return t
end

function G.desc(o)
	if not o then
		return "nil"
	end
	local b = boxOf(o)
	return fmt("%s %.0f,%.0f %.0fx%.0f", o.Name, b.x, b.y + insetOf(o), b.w, b.h)
end

function G.find(root, name)
	if not root then
		return nil
	end
	local queue, head = { root }, 1
	while head <= #queue do
		local cur = queue[head]
		head = head + 1
		for _, c in ipairs(cur:GetChildren()) do
			if c.Name == name then
				return c
			end
			queue[#queue + 1] = c
		end
	end
	return nil
end

function G.at(w, h, touch, label, fn)
	local KC = kc()
	local UIS = game:GetService("UserInputService")
	local old = { Mock.Viewport.X, Mock.Viewport.Y, UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled }
	UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = touch and true or false, not touch, not touch
	Mock.SetViewport(w, h)
	KC.advance(0.6)
	local ok, err = pcall(fn)
	if not ok then
		T.fail(label .. ": error", tostring(err))
	end
	UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = old[3], old[4], old[5]
	Mock.SetViewport(old[1], old[2])
	KC.advance(0.6)
	KC.flushErrors(label)
	return ok
end

function G.check(root, label, opts)
	opts = opts or {}
	local minText = opts.MinText or 14
	local minTarget = opts.MinTarget or 44
	local skip = opts.Skip or {}
	if not T.check(root ~= nil and shownIn(root), label .. ": the window is shown") then
		return false
	end
	local vw, vh = Mock.Viewport.X, Mock.Viewport.Y
	local small, tiny, outside = {}, {}, {}
	local measured = 0
	local list = { root }
	for _, d in ipairs(root:GetDescendants()) do
		list[#list + 1] = d
	end
	local skipped = {}
	for _, o in ipairs(list) do
		local cut = false
		local cur = o
		while cur and cur ~= root.Parent do
			if skip[cur.Name] or skipped[cur] then
				cut = true
				break
			end
			cur = cur.Parent
		end
		if cut then
			skipped[o] = true
		elseif o:IsA("GuiObject") and shownIn(o) then
			local b = boxOf(o)
			local sc = scrollerOf(o, root)
			local visible = true
			if sc then
				visible = intersects(b, boxOf(sc))
			end
			if visible and b.w > 0 and b.h > 0 then
				-- text
				if isText(o) then
					local t = shownText(o)
					if t:gsub("%s", "") ~= "" then
						measured = measured + 1
						local px = o.TextScaled and b.h or o.TextSize * scaleOf(o)
						if px < minText - 0.01 then
							small[#small + 1] = fmt("%s %.1f px '%s'", o:GetFullName():gsub("^Players%.[^.]+%.PlayerGui%.", ""), px, t:sub(1, 24))
						end
					end
				end
				-- targets
				if (o:IsA("GuiButton") and o.Active ~= false) or o:IsA("TextBox") then
					if b.w < minTarget - TOL or b.h < minTarget - TOL then
						tiny[#tiny + 1] = G.desc(o)
					end
				end
				-- screen (a scroller's child is clipped by the scroller, which is checked itself)
				if not sc then
					local y = b.y + insetOf(o)
					if b.x < -TOL or y < INSET - TOL or b.x + b.w > vw + TOL or y + b.h > vh + TOL then
						outside[#outside + 1] = G.desc(o)
					end
				end
			end
		end
	end
	local ok = true
	ok = T.check(#small == 0 and measured > 0, label .. ": every text is >= " .. minText .. " px on screen", #small .. " of " .. measured .. ": " .. table.concat(small, "; ", 1, math.min(#small, 6))) and ok
	ok = T.check(#tiny == 0, label .. ": every button and text box is >= " .. minTarget .. " px", table.concat(tiny, "; ", 1, math.min(#tiny, 6))) and ok
	ok = T.check(#outside == 0, label .. ": everything is on the screen and under the top bar", fmt("%dx%d: ", vw, vh) .. table.concat(outside, "; ", 1, math.min(#outside, 6))) and ok
	if opts.NoOverlap then
		local boxes, missing, hits = {}, {}, {}
		for _, name in ipairs(opts.NoOverlap) do
			local o = G.find(root, name)
			if o and shownIn(o) then
				boxes[#boxes + 1] = { name = name, b = boxOf(o) }
			else
				missing[#missing + 1] = name
			end
		end
		for i = 1, #boxes do
			for j = i + 1, #boxes do
				if intersects(boxes[i].b, boxes[j].b) then
					hits[#hits + 1] = boxes[i].name .. " x " .. boxes[j].name
				end
			end
		end
		ok = T.check(#missing == 0, label .. ": the named controls are shown", table.concat(missing, ", ")) and ok
		ok = T.check(#hits == 0, label .. ": the named controls never overlap", table.concat(hits, "; ")) and ok
	end
	return ok
end

-- (Task 9) real text widths: the advance widths (1/1000 em) of ASCII 32..126; any other character counts 0.6 em
-- (kit-b U1) + Luckiest: Roblox's shipped LuckiestGuy-Regular.ttf, the Title / Sign / Accent face (was GothamBlack, whose
-- Montserrat Black widths stay the fallback for any other name)
-- (T0 review) the tables live in smoke_common.lua now (SmokeCommon.Advance / SmokeCommon.Faces), shared with the world
-- sign fit check of smoke_polish_worldtext.lua
local ADVANCE = SmokeCommon.Advance
local FACE = SmokeCommon.Faces

function G.realWidth(text, size, font)
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

local function realRows(text, size, font, width)
	local rows, cur = 0, 0
	local space = G.realWidth(" ", size, font)
	for word in tostring(text):gmatch("%S+") do
		local w = G.realWidth(word, size, font)
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

-- (kit-b U1 review) the font o is measured with: a Nunito label (Body / Label / Toast / Script face) reads .Font =
-- Enum.Font.Unknown, as in Roblox, so it is measured with its role's Enum fallback (Builder Sans), 1:1 as before the mock
-- kept the two in step (Nunito ExtraBold runs about 1.0-1.07 x Builder Sans Bold: PIL puts the Altar hint at 342 px in
-- Nunito Regular at 18, Builder Sans Bold 365 px; Theme.MeasureSpare's 1.06 is the layout code's safety margin, not a width)
local themeMod = nil
local function measuredFont(o)
	local font = o.Font
	if font ~= Enum.Font.Unknown then
		return font
	end
	if themeMod == nil then
		local inst = Mock.GetPath(ROOTS.shared .. "/Theme")
		local ok, mod = false, nil
		if inst then
			ok, mod = pcall(require, inst)
		end
		themeMod = (ok and type(mod) == "table") and mod or false
	end
	if not themeMod then
		return font
	end
	return themeMod.FontOf(o)
end

function G.fits(o)
	if not o then
		return false, "nil"
	end
	local text = tostring(o.Text):gsub("<[^>]*>", "")
	if text:gsub("%s", "") == "" or o.TextScaled then
		return true, ""
	end
	local s = math.max(0.01, scaleOf(o))
	local boxW, boxH = o.AbsoluteSize.X / s, o.AbsoluteSize.Y / s
	local pad = o:FindFirstChildOfClass("UIPadding")
	if pad then
		boxW = boxW - pad.PaddingLeft.Offset - pad.PaddingRight.Offset
		boxH = boxH - pad.PaddingTop.Offset - pad.PaddingBottom.Offset
	end
	local font = measuredFont(o)
	local w = G.realWidth(text, o.TextSize, font)
	local detail = fmt("%s '%s' %.1f px at %d (%s) in %.0fx%.0f", o.Name, (text:gsub("[\128-\255]+", "?")), w, o.TextSize, font.Name, boxW, boxH)
	if w <= boxW + 0.5 then
		return true, detail
	end
	if not o.TextWrapped then
		return false, detail
	end
	local rows = realRows(text, o.TextSize, font, boxW)
	return rows * o.TextSize * (o.LineHeight or 1) <= boxH + 1, detail .. " rows " .. tostring(rows)
end

_G.RedoGeom = G
return {}
