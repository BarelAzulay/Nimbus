-- PixelCrisp (kit B U9-9; the owner's look bar of 2026-11-17: "pixel icons and pixel edges snapped to whole pixels at
-- every screen size, one pixel size per screen, no blurry up-scaled pixels"). The side cards (toasts, the tutorial card,
-- the NPC dialog) are designed in 1080p px under a UIScale of Theme.ScreenFactor() or a fitted scale (0.7 .. 1.25), so a
-- 2 px icon cell would land on 1.6 or 2.5 screen px and draw uneven. Here an icon's holder carries the correction:
--   PixelCrisp.Icon(parent, name, px, colour[, opts]) -> holder, glyph
--        holder: a Frame px x px (design px, AnchorPoint 0.5 at the centre of its parent unless opts.Position /
--        opts.AnchorPoint) with a UIScale "Crisp" = c / (cell * k), k = the product of the UIScales above it, cell = the
--        icon's design cell (floor(px / 9)), c = round(cell * k): each of the 9 cells is c whole screen px. (U9-9 look) A
--        2 px cell never drops to 1 px (c >= 2): an 18 px icon is 18 screen px on every phone, as the top bar's, so a
--        screen has one pixel size (a card shrunk to 0.7 keeps 18 / k design px for the icon's slot). Its top-left lands on
--        a whole screen px too (Box).
--        glyph: a TextLabel filling the holder with no text whose icon is PixelIcon.Host'ed, so a caller fades or tints
--        the icon through glyph.TextTransparency / TextColor3 as it did a letter. opts: ZIndex, Name, Position, AnchorPoint
--   PixelCrisp.Adopt(frame[, cell])  the same correction on an icon Frame PixelIcon drew itself (PixelIcon.Lead's box, the
--                                icon PixelIcon.Host returns) or on any little pixel drawing in cells of `cell` design px
--                                (the NPC's stepped tail, a rivet), in place: a UIScale "Crisp" on it (it grows round its
--                                AnchorPoint); cell defaults to its height / 9. Returns the frame
--   PixelCrisp.Edge(stroke, px)  a border UIStroke of px design px that Refresh keeps at round(px * k) whole screen px
--                                (>= 2 for an edge of 2 design px or more)
--   PixelCrisp.Lip(lip, px)      (U9-9 look) a block's bottom lip (a Frame anchored 0, 1 at the bottom of its block, Size
--                                (1, 0, 0, px)) kept at round(px * k) whole screen px (>= 2 for 2 px or more): a UIScale
--                                "Crisp" on the lip (it grows round its bottom-left corner) and the width's scale undone,
--                                so the lip stays flush with its block. Returns the lip
--   PixelCrisp.Box(frame)        (U9-9 look) the frame's drawn top-left on a whole screen px, measured from its crisp
--                                root (or the screen): a correction in its Position's Scale (Roblox keeps a UDim's Offset
--                                whole, so a 0.4 px nudge cannot go there), kept apart from the caller's own Position. When
--                                the caller (or PixelIcon.Lead) moves the frame again it is snapped again. A frame a
--                                UIListLayout / UIGridLayout places is left alone. Icons and Adopted frames are Boxes too.
--                                (U9-9 look 2) Its right and bottom edges too: a correction in its Size's Scale (any card
--                                scale, a fitted 0.724 as well), so a block, the stone inside its wood frame and a plank are
--                                whole px on all four sides; not for a frame with its own UIScale or an AutomaticSize. Box
--                                the parents with the children: a block lies on whole px of its parent's snapped box
--   PixelCrisp.Root(frame)       (U9-9 look) marks a frame its owner keeps on a whole screen px at rest (a card's root, a
--                                toast that slides in, a dialog's slide): the Boxes under it snap relative to it, so a
--                                slide or a tween of the root never leaves them half a pixel off
--   PixelCrisp.Refresh(root)     re-snaps every holder, edge, lip and box under root (root included): call it after a scale
--                                above them changed (a relayout)
--   PixelCrisp.ScaleAbove(obj) -> k  the product of the UIScales on obj's ancestors (obj's own UIScale not counted)
--   PixelCrisp.Cell(holder) -> c  the screen px of one cell after the last snap
--   PixelCrisp.Px(px, k) -> n     the whole screen px a part of px design px takes at scale k (>= 2 for 2 px or more)
--   PixelCrisp.Len(px, k) -> n    the smallest whole design length >= px that is whole screen px at scale k (a block's
--                                height picked so its edges land on whole px: 28 -> 30 at 0.8)
-- Plain Lua 5.1-compatible syntax only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PixelIcon = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PixelIcon"))

local PixelCrisp = {}

local function round(x)
	return math.floor(x + 0.5)
end

-- the whole screen px of a part of px design px at scale k: never under 2 for a part of 2 px or more (a 2 px cell or edge
-- that dropped to 1 px drew a second pixel size on the screen), never under 1
function PixelCrisp.Px(px, k)
	return math.max(px >= 2 and 2 or 1, round(px * k))
end
local wholePx = PixelCrisp.Px

-- the smallest whole design length >= px that lands on whole screen px at scale k (a UDim's Offset is whole in Roblox, so a
-- block's height is picked, not nudged: 28 -> 30 at 0.8); px itself when none does within 20 design px
function PixelCrisp.Len(px, k)
	local n = math.ceil(px - 1e-6)
	for add = 0, 20 do
		local v = (n + add) * k
		if math.abs(v - round(v)) < 1e-4 then
			return n + add
		end
	end
	return n
end

local function ownScale(obj)
	for _, c in ipairs(obj:GetChildren()) do
		if c:IsA("UIScale") then
			return c
		end
	end
	return nil
end

function PixelCrisp.ScaleAbove(obj)
	local k = 1
	local cur = obj and obj.Parent
	while cur and not cur:IsA("LayerCollector") do
		if cur:IsA("GuiObject") then
			local s = ownScale(cur)
			if s and s.Scale > 0 then
				k = k * s.Scale
			end
		end
		cur = cur.Parent
	end
	return k
end

----------------------------------------------------------------------
-- origins (Box, Root)
----------------------------------------------------------------------
-- the nearest crisp root above obj (nil: the screen)
local function rootOf(obj)
	local cur = obj.Parent
	while cur and not cur:IsA("LayerCollector") do
		if cur:GetAttribute("CrispRoot") == true then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

-- the box a child of `parent` is placed in, in screen px: its AbsoluteSize less its UIPadding
local function contentSize(parent)
	local s = parent.AbsoluteSize
	local w, h = s.X, s.Y
	local pad = parent:FindFirstChildOfClass("UIPadding")
	if pad then
		local own = parent:IsA("GuiObject") and ownScale(parent) or nil
		local k = PixelCrisp.ScaleAbove(parent) * (own and own.Scale or 1)
		w = w - (pad.PaddingLeft.Scale + pad.PaddingRight.Scale) * s.X - (pad.PaddingLeft.Offset + pad.PaddingRight.Offset) * k
		h = h - (pad.PaddingTop.Scale + pad.PaddingBottom.Scale) * s.Y - (pad.PaddingTop.Offset + pad.PaddingBottom.Offset) * k
	end
	return w, h
end

-- a UIListLayout / UIGridLayout of its parent places obj (its Position is not used)
local function laidOut(obj)
	local p = obj.Parent
	return p ~= nil and (p:FindFirstChildOfClass("UIListLayout") ~= nil or p:FindFirstChildOfClass("UIGridLayout") ~= nil)
end

local watched = setmetatable({}, { __mode = "k" }) -- [frame] = true once its Position is watched

-- (U9-9 look 2) a Box's size is snapped too: its right and bottom edges on whole px as well as its top-left (a block of
-- 104 x 32 design px at 0.8 drew 83.2 x 25.6, one side crisp and the other soft). Not for a frame that sizes itself (a
-- UIScale of its own: an icon holder, an Adopted drawing; AutomaticSize). A CloudUI plank's hover / press "FxScale" is
-- allowed: it is snapped at rest (Scale 1)
local function sizes(obj)
	if obj:GetAttribute("CrispBox") ~= true or obj.AutomaticSize ~= Enum.AutomaticSize.None then
		return false
	end
	for _, c in ipairs(obj:GetChildren()) do
		if c:IsA("UIScale") and c.Name ~= "FxScale" then
			return false
		end
	end
	return true
end

local function snapOrigin(obj)
	local parent = obj.Parent
	if not (obj:IsA("GuiObject") and parent and parent:IsA("GuiBase2d")) or laidOut(obj) then
		return
	end
	local fx = obj:FindFirstChild("FxScale")
	if fx and fx:IsA("UIScale") and math.abs(fx.Scale - 1) > 1e-6 then
		return -- (a plank mid hover / press: it grows round its anchor; the next snap finds it at rest)
	end
	local pw, ph = contentSize(parent)
	if pw <= 0 or ph <= 0 then
		return
	end
	local p, z = obj.Position, obj.Size
	local sx, sy, wx, wy = 0, 0, 0, 0
	if obj:GetAttribute("CrispAt") == p then
		sx, sy = obj:GetAttribute("CrispSX") or 0, obj:GetAttribute("CrispSY") or 0
	end
	local sizing = sizes(obj)
	if sizing and obj:GetAttribute("CrispSizeAt") == z then
		wx, wy = obj:GetAttribute("CrispWX") or 0, obj:GetAttribute("CrispWY") or 0
	end
	local a, s = obj.AbsolutePosition, obj.AbsoluteSize
	local ax, ay = obj.AnchorPoint.X, obj.AnchorPoint.Y
	local root = rootOf(obj)
	local o = root and root.AbsolutePosition or Vector2.new(0, 0)
	-- where it sits from its root and how big it is without the corrections (a size nudge moves an anchored frame's
	-- top-left by its AnchorPoint's share), then the nudges (in Scale) that put its edges on whole px
	local w0, h0 = s.X - wx * pw, s.Y - wy * ph
	local rx, ry = a.X - o.X - sx * pw + ax * wx * pw, a.Y - o.Y - sy * ph + ay * wy * ph
	local left, top = round(rx), round(ry)
	local nwx, nwy = 0, 0
	if sizing then
		nwx = (round(rx + w0) - left - w0) / pw
		nwy = (round(ry + h0) - top - h0) / ph
	end
	local nx, ny = (left - rx + ax * nwx * pw) / pw, (top - ry + ay * nwy * ph) / ph
	local same = math.abs(nx - sx) < 1e-7 and math.abs(ny - sy) < 1e-7 and obj:GetAttribute("CrispAt") == p
	if sizing then
		same = same and math.abs(nwx - wx) < 1e-7 and math.abs(nwy - wy) < 1e-7 and obj:GetAttribute("CrispSizeAt") == z
	end
	if same then
		return
	end
	if sizing then
		local newSize = UDim2.new(z.X.Scale - wx + nwx, z.X.Offset, z.Y.Scale - wy + nwy, z.Y.Offset)
		obj:SetAttribute("CrispWX", nwx)
		obj:SetAttribute("CrispWY", nwy)
		obj:SetAttribute("CrispSizeAt", newSize) -- (before the write: a watcher that runs at once sees it done)
		if newSize ~= z then
			obj.Size = newSize
		end
		obj:SetAttribute("CrispSizeAt", obj.Size)
	end
	local new = UDim2.new(p.X.Scale - sx + nx, p.X.Offset, p.Y.Scale - sy + ny, p.Y.Offset)
	obj:SetAttribute("CrispSX", nx)
	obj:SetAttribute("CrispSY", ny)
	obj:SetAttribute("CrispAt", new)
	if new ~= p then
		obj.Position = new
	end
	obj:SetAttribute("CrispAt", obj.Position)
end

local function watch(obj)
	if watched[obj] then
		return
	end
	watched[obj] = true
	-- the caller (a layout, PixelIcon.Lead's place) moved it: snap again from its new Position
	obj:GetPropertyChangedSignal("Position"):Connect(function()
		if obj:GetAttribute("CrispAt") ~= obj.Position and obj.Parent then
			snapOrigin(obj)
		end
	end)
	-- (U9-9 look 2) or resized a Box: its new Size is the caller's own, snapped again
	obj:GetPropertyChangedSignal("Size"):Connect(function()
		if sizes(obj) and obj:GetAttribute("CrispSizeAt") ~= obj.Size and obj.Parent then
			snapOrigin(obj)
		end
	end)
end

function PixelCrisp.Box(frame)
	if frame and frame:IsA("GuiObject") then
		frame:SetAttribute("CrispBox", true)
		watch(frame)
		snapOrigin(frame)
	end
	return frame
end

function PixelCrisp.Root(frame)
	if frame then
		frame:SetAttribute("CrispRoot", true)
	end
	return frame
end

----------------------------------------------------------------------
-- cells, edges, lips
----------------------------------------------------------------------
local function snapHolder(holder)
	local cell = holder:GetAttribute("CrispCell")
	local scale = holder:FindFirstChild("Crisp")
	if type(cell) ~= "number" or cell <= 0 or not scale then
		return
	end
	local k = PixelCrisp.ScaleAbove(holder)
	local c = wholePx(cell, k)
	scale.Scale = c / (cell * k)
	holder:SetAttribute("CrispPx", c)
	snapOrigin(holder)
end

local function snapEdge(stroke)
	local px = stroke:GetAttribute("CrispEdge")
	local host = stroke.Parent
	if type(px) ~= "number" or not host then
		return
	end
	local k = PixelCrisp.ScaleAbove(host) * (ownScale(host) and ownScale(host).Scale or 1)
	if k <= 0 then
		return
	end
	local t = wholePx(px, k) / k
	stroke:SetAttribute("CrispThick", t) -- (before the write: a watcher that runs at once sees it done)
	if stroke.Thickness ~= t then
		stroke.Thickness = t
	end
end

local function snapLip(lip)
	local px = lip:GetAttribute("CrispLip")
	local scale = lip:FindFirstChild("Crisp")
	if type(px) ~= "number" or px <= 0 or not scale then
		return
	end
	local k = PixelCrisp.ScaleAbove(lip)
	if k <= 0 then
		return
	end
	local s = wholePx(px, k) / (px * k)
	-- its own scale grows its width too: the width is undone in its Scale part (a lip runs its block's whole width; a
	-- padded block's lip, CloudUI.SignBlock's, reaches out over the padding by an Offset, which goes into the Scale too)
	local base = lip:GetAttribute("CrispLipBase")
	if typeof(base) ~= "UDim2" or lip:GetAttribute("CrispLipAt") ~= lip.Size then
		base = lip.Size
		lip:SetAttribute("CrispLipBase", base)
	end
	local want
	if base.X.Offset == 0 then
		want = UDim2.new(base.X.Scale / s, 0, 0, px)
	else
		local pw = lip.Parent and lip.Parent:IsA("GuiBase2d") and contentSize(lip.Parent) or 0
		if pw <= 0 then
			return
		end
		local w = pw * base.X.Scale + base.X.Offset * k
		if lip:GetAttribute("CrispLipWhole") == true then
			-- (U9-9 look 2) a free line (a link's underline, its width from its words): its drawn width a whole px too
			w = math.max(1, math.floor(w + 0.5))
		end
		want = UDim2.new(w / (pw * s), 0, 0, px)
	end
	scale.Scale = s
	lip:SetAttribute("CrispLipAt", want) -- (before the write: a watcher that runs at once sees it done)
	if lip.Size ~= want then
		lip.Size = want
	end
	lip:SetAttribute("CrispLipAt", lip.Size)
end

function PixelCrisp.Icon(parent, name, px, colour, opts)
	opts = opts or {}
	px = PixelIcon.Snap(px)
	local holder = Instance.new("Frame")
	holder.Name = opts.Name or "Crisp"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromOffset(px, px)
	holder.AnchorPoint = opts.AnchorPoint or Vector2.new(0.5, 0.5)
	holder.Position = opts.Position or UDim2.fromScale(0.5, 0.5)
	holder.ZIndex = opts.ZIndex or 1
	holder:SetAttribute("CrispCell", math.floor(px / 9))
	local scale = Instance.new("UIScale")
	scale.Name = "Crisp"
	scale.Parent = holder
	local glyph = Instance.new("TextLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.BorderSizePixel = 0
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.Text = ""
	glyph.TextColor3 = colour or Color3.new(1, 1, 1)
	glyph.ZIndex = holder.ZIndex
	glyph.Parent = holder
	glyph:SetAttribute("PixelIcon", name)
	PixelIcon.Host(glyph, name, px)
	holder.Parent = parent
	watch(holder)
	snapHolder(holder)
	return holder, glyph
end

function PixelCrisp.Adopt(frame, cell)
	if not frame then
		return nil
	end
	cell = tonumber(cell) or math.floor(frame.Size.Y.Offset / 9)
	if cell <= 0 then
		return frame
	end
	if not frame:FindFirstChild("Crisp") then
		local scale = Instance.new("UIScale")
		scale.Name = "Crisp"
		scale.Parent = frame
	end
	frame:SetAttribute("CrispCell", cell)
	watch(frame)
	snapHolder(frame)
	-- (merge kitb-look1 x U9-9) PixelIcon fits its icons and Lead boxes to the scales above them: once more with this
	-- correction counted (a Lead box sized before it drew 2.5 px cells), and it watches the correction from now on
	PixelIcon.Refit(frame)
	return frame
end

function PixelCrisp.Edge(stroke, px)
	if stroke then
		stroke:SetAttribute("CrispEdge", tonumber(px) or stroke.Thickness)
		snapEdge(stroke)
		if not watched[stroke] then
			watched[stroke] = true
			-- (U9-9 look) a repaint (CloudUI.SignBlock on a hover or a press) set its design px again: back on whole px
			stroke:GetPropertyChangedSignal("Thickness"):Connect(function()
				local want = stroke:GetAttribute("CrispThick")
				if type(want) ~= "number" or math.abs(stroke.Thickness - want) > 1e-6 then
					stroke:SetAttribute("CrispEdge", stroke.Thickness)
					snapEdge(stroke)
				end
			end)
		end
	end
	return stroke
end

function PixelCrisp.Lip(lip, px)
	if not lip then
		return nil
	end
	px = tonumber(px) or lip.Size.Y.Offset
	if not lip:FindFirstChild("Crisp") then
		local scale = Instance.new("UIScale")
		scale.Name = "Crisp"
		scale.Parent = lip
	end
	lip:SetAttribute("CrispLip", px)
	snapLip(lip)
	if not watched[lip] then
		watched[lip] = true
		-- (U9-9 look) a repaint (a Sign button's press thins its lip) set a new size: its height is the new design px
		lip:GetPropertyChangedSignal("Size"):Connect(function()
			if lip:GetAttribute("CrispLipAt") ~= lip.Size and lip.Parent then
				lip:SetAttribute("CrispLip", lip.Size.Y.Offset)
				snapLip(lip)
			end
		end)
	end
	return lip
end

function PixelCrisp.Refresh(root)
	if not root then
		return
	end
	-- parents before children (GetDescendants walks depth first): a box's place depends on its parent's
	local function one(d)
		if d:IsA("GuiObject") and d:GetAttribute("CrispLip") then
			snapLip(d)
		end
		if d:IsA("Frame") and d:GetAttribute("CrispCell") then
			snapHolder(d)
		elseif d:IsA("GuiObject") and d:GetAttribute("CrispBox") then
			snapOrigin(d)
		elseif d:IsA("UIStroke") and d:GetAttribute("CrispEdge") then
			snapEdge(d)
		end
	end
	one(root)
	for _, d in ipairs(root:GetDescendants()) do
		one(d)
	end
end

function PixelCrisp.Cell(holder)
	return holder and holder:GetAttribute("CrispPx") or nil
end

return PixelCrisp
