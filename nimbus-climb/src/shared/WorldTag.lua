-- WorldTag (shared: the server's world signs and the client's tags alike): Pitch 2 item 04_world_ui, the owner's pick B
-- "Stone tags" (docs/superpowers/specs/2026-11-20-pitch2-build-design.md; mock-up .superpowers/slop-audit/round3/build/
-- PITCH2/D_world/04_world_ui_optB.png, its numbers from pitch_04_world_ui.py). The HUD's own card tier floating in the
-- world: a flat face, a mitred wood edge (a Border UIStroke "SignEdge", drawn outside the face), a darker lip along the
-- bottom (Frame "Lip") in the role colour; square, no glow, no gradient, no round corner. The text sits on the opaque face
-- in the kit's ink (no outline: kit B's "no outline on a panel").
--   WorldTag.Sizes                      design px of a 1080p screen (world billboards keep a fixed pixel size)
--   WorldTag.Block(obj, face, lip, edgeColour, edgePx, lipPx) -> edge, lip   paints obj as a kit block, in place
--   WorldTag.LipOf(accent) -> Color3    a role colour's lip (the mock's lip_of: 32% toward the kit's brown ink)
--   WorldTag.Text(parent, name, text, role, px, colour, props) -> TextLabel   ink on a face: Theme role, no outline
--   WorldTag.Icon(parent, name, px, colour) -> Frame | nil                    a PixelIcon (nil for an unknown name)
--   WorldTag.Bang(parent, z) -> Frame "Badge"   the "!": a gold block (Sizes.Bang) holding the pixel bang in brown
-- Requires only Theme and PixelIcon (Shared). Plain Lua 5.1-compatible syntax only.

local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelIcon = require(script.Parent:WaitForChild("PixelIcon"))

local Sign = Theme.Sign

local WorldTag = {}

WorldTag.Sizes = {
	Edge = 3, -- a stone tag's wood edge (the HUD card tier)
	Lip = 5, -- ... and its lip in the role colour
	Bang = 30, -- the "!" block (outer, its 2 px edge included), pinned on a card's top-right corner ...
	BangEdge = 2,
	BangLip = 4,
	BangIcon = 18, -- ... the pixel bang in it
	BangOut = 13, -- px it reaches past the card's top and right
}

function WorldTag.Block(obj, face, lip, edgeColour, edgePx, lipPx)
	edgePx = tonumber(edgePx) or WorldTag.Sizes.Edge
	lipPx = tonumber(lipPx) or WorldTag.Sizes.Lip
	obj.BackgroundTransparency = 0
	obj.BackgroundColor3 = face or Sign.Stone
	obj.BorderSizePixel = 0
	local edge = obj:FindFirstChild("SignEdge")
	if not edge then
		edge = Instance.new("UIStroke")
		edge.Name = "SignEdge"
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.LineJoinMode = Enum.LineJoinMode.Miter
		edge.Parent = obj
	end
	edge.Color = edgeColour or Sign.Wood
	edge.Thickness = edgePx
	edge.Transparency = 0
	local l = obj:FindFirstChild("Lip")
	if not l then
		l = Instance.new("Frame")
		l.Name = "Lip"
		l.BorderSizePixel = 0
		l.BackgroundTransparency = 0
		l.AnchorPoint = Vector2.new(0, 1)
		l.Position = UDim2.new(0, 0, 1, 0)
		l.Parent = obj
	end
	l.BackgroundColor3 = lip or Theme.SignLipOf(face or Sign.Stone)
	l.Size = UDim2.new(1, 0, 0, lipPx)
	l.Visible = lipPx > 0
	l.ZIndex = obj.ZIndex
	obj:SetAttribute("WorldTag", true)
	return edge, l
end

function WorldTag.LipOf(accent)
	if typeof(accent) ~= "Color3" then
		return Sign.StoneLip
	end
	return accent:Lerp(Sign.Text, 0.32)
end

function WorldTag.Text(parent, name, text, role, px, colour, props)
	local label = Theme.Label(text, role, { Size = px, Color = colour or Sign.Text })
	label.Name = name
	label.BackgroundTransparency = 1
	label.TextWrapped = false
	label.TextScaled = false
	label.TextTruncate = Enum.TextTruncate.None
	for k, v in pairs(props or {}) do
		label[k] = v
	end
	label.Parent = parent
	return label
end

function WorldTag.Icon(parent, name, px, colour)
	local icon = PixelIcon.New(parent, name, px, colour)
	return icon
end

-- the "!" block: Sizes.Bang outer (a 2 px wood edge outside the face), a GoldLip lip, the pixel bang centred above the lip.
-- The caller places it (a card's top-right corner: Position UDim2.new(1, -Bang + BangOut + edge, 0, -BangOut + edge))
function WorldTag.Bang(parent, z)
	local Z = WorldTag.Sizes
	local inner = Z.Bang - 2 * Z.BangEdge
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.Size = UDim2.fromOffset(inner, inner)
	badge.ZIndex = z or 3
	badge.Rotation = 0
	WorldTag.Block(badge, Sign.Gold, Sign.GoldLip, Sign.Wood, Z.BangEdge, Z.BangLip)
	local icon = WorldTag.Icon(badge, "bang", Z.BangIcon, Sign.Text)
	if icon then
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.new(0.5, 0, 0.5, -math.floor(Z.BangLip / 2))
		icon.ZIndex = badge.ZIndex + 1
		for _, cell in ipairs(icon:GetChildren()) do
			cell.ZIndex = badge.ZIndex + 1
		end
	end
	badge.Parent = parent
	return badge
end

return WorldTag
