-- PixelCrisp (kit B U9-9; the owner's look bar of 2026-11-17: "pixel icons and pixel edges snapped to whole pixels at
-- every screen size, one pixel size per screen, no blurry up-scaled pixels"). The side cards (toasts, the tutorial card,
-- the NPC dialog) are designed in 1080p px under a UIScale of Theme.ScreenFactor() or a fitted scale (0.7 .. 1.25), so a
-- 2 px icon cell would land on 1.6 or 2.5 screen px and draw uneven. Here an icon's holder carries the correction:
--   PixelCrisp.Icon(parent, name, px, colour[, opts]) -> holder, glyph
--        holder: a Frame px x px (design px, AnchorPoint 0.5 at the centre of its parent unless opts.Position /
--        opts.AnchorPoint) with a UIScale "Crisp" = c / (cell * k), k = the product of the UIScales above it, cell = the
--        icon's design cell (floor(px / 9)), c = round(cell * k) (at least 1): each of the 9 cells is c whole screen px.
--        glyph: a TextLabel filling the holder with no text whose icon is PixelIcon.Host'ed, so a caller fades or tints
--        the icon through glyph.TextTransparency / TextColor3 as it did a letter. opts: ZIndex, Name, Position, AnchorPoint
--   PixelCrisp.Adopt(frame[, cell])  the same correction on an icon Frame PixelIcon drew itself (PixelIcon.Lead's box, the
--                                icon PixelIcon.Host returns), in place: a UIScale "Crisp" on it (it grows round its
--                                AnchorPoint); cell defaults to its height / 9. Returns the frame
--   PixelCrisp.Edge(stroke, px)  a border UIStroke of px design px that Refresh keeps at round(px * k) whole screen px
--   PixelCrisp.Refresh(root)     re-snaps every holder and edge under root (root included): call it after a scale above
--                                them changed (a relayout)
--   PixelCrisp.ScaleAbove(obj) -> k  the product of the UIScales on obj's ancestors (obj's own UIScale not counted)
--   PixelCrisp.Cell(holder) -> c  the screen px of one cell after the last snap
-- Plain Lua 5.1-compatible syntax only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PixelIcon = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PixelIcon"))

local PixelCrisp = {}

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

local function snapHolder(holder)
	local cell = holder:GetAttribute("CrispCell")
	local scale = holder:FindFirstChild("Crisp")
	if type(cell) ~= "number" or cell <= 0 or not scale then
		return
	end
	local k = PixelCrisp.ScaleAbove(holder)
	local c = math.max(1, math.floor(cell * k + 0.5))
	scale.Scale = c / (cell * k)
	holder:SetAttribute("CrispPx", c)
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
	stroke.Thickness = math.max(1, math.floor(px * k + 0.5)) / k
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
	snapHolder(frame)
	return frame
end

function PixelCrisp.Edge(stroke, px)
	if stroke then
		stroke:SetAttribute("CrispEdge", tonumber(px) or stroke.Thickness)
		snapEdge(stroke)
	end
	return stroke
end

function PixelCrisp.Refresh(root)
	if not root then
		return
	end
	local function one(d)
		if d:IsA("Frame") and d:GetAttribute("CrispCell") then
			snapHolder(d)
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
