-- smoke_titles.lua: lobby-shop Task 19 (spec 16.6 "Client", "Tests"): the rank and Creator titles above the head
-- (client/Controllers/TitleController) and the VIP crown drawn inside a titled player's tag (VipController). Loaded by
-- tools/smoke.py in the CLIENT world:
--   client_titles   (client, 1920x1080)
--     the tag per kind on dummy players: a BillboardGui TitleTag on the head (240 x 40 px: the 36 px plate and its 2 px
--       edge inside the clipping gui, StudsOffset (0, 2.0, 0), SizeOffset.Y == 0.5 + (26 - 2) / H, MaxDistance 90, not on top, LightInfluence 0) > Plate > Label; the texts
--       "TOP 10 \194\183 #3" / "TOP 100" / "CREATOR" at >= 20 px; (kit-b U9-3, finding 15) the Plate a flat kit B tag of the
--       text's width, centred: opaque, its role's face (Top10 gold, Top100 stone, Creator navy) in a wood edge with its lip,
--       square; the Label FredokaOne (Nameplate) in the look's ink, no outline; no gradient and no tween (the Top10 rainbow
--       and the gold / cyan-violet gradients went)
--     hidden while that player is InBattle; the local player's tag hidden with the camera at the head and shown at 12
--       studs (another player's tag ignores the camera); the tag looks the same on Low graphics (nothing to pause)
--     a titled VIP: the Crown inside the TitleTag (34 x 34, centred, 4 px above the Plate, the billboard 240 x 76) and no
--       VipCrown on that head; the crown follows VipController's rule (gone in InMatch and on Low graphics, back after);
--       the title cleared on a VIP -> the VipCrown back at 2.4 studs; an untitled VIP -> the VipCrown, no TitleTag
--     respawn (Review Focus 5): one tag on the new head, the old one destroyed; the attribute cleared -> the tag removed;
--       ten Top10 players -> no tween and no per-frame connection added (Heartbeat / RenderStepped / Stepped / PreRender /
--       Pre- and PostSimulation counts unchanged); a tag holds at most 6 instances (the crown's two pixel crowns on top);
--       every tag gone once the dummies leave
-- Deterministic: mock clock only. The graphics answer (GraphicsQuality.Effective is stubbed, as smoke_gem_icon does),
-- the camera, the viewport and the local player's attributes are put back; the dummy players leave. Plain Lua 5.1 syntax.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local fmt = string.format
local abs = math.abs

local S = {}

local DOT = "\194\183"
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local LocalPlayer = Players.LocalPlayer

local G = {}
function G.KC()
	return _G.KC
end
function G.req(key)
	local inst = Mock.GetPath(ROOTS[key:match("^(%a+)/")] .. "/" .. key:gsub("^%a+/", ""))
	if not inst then
		return nil
	end
	local ok, mod = pcall(require, inst)
	return ok and type(mod) == "table" and mod or nil
end
function G.advance(seconds)
	Mock.Advance(seconds)
end
function G.head(player)
	local char = player and player.Character
	return char and char:FindFirstChild("Head") or nil
end
function G.find(root, name)
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
function G.vipCrown(player)
	return G.find(player.Character, "VipCrown")
end
-- every TitleTag BillboardGui in the workspace
function G.allTags()
	local out = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == "TitleTag" and d:IsA("BillboardGui") then
			out[#out + 1] = d
		end
	end
	return out
end
-- TitleTags inside this player's current character
function G.tagsOf(player)
	local n = 0
	local char = player.Character
	for _, t in ipairs(G.allTags()) do
		if char and t:IsDescendantOf(char) then
			n = n + 1
		end
	end
	return n
end
-- the tag's Plate and Label (TitleTag > Plate > Label)
function G.parts(tag)
	local plate = tag and tag:FindFirstChild("Plate")
	local label = plate and plate:FindFirstChild("Label")
	return plate, label
end
function G.target(tw)
	local ok, target = pcall(function()
		return tw.Instance
	end)
	return ok and target or nil
end
-- playing tweens on anything under a TitleTag that is still in the world
function G.titleTweens()
	local n = 0
	for tw in pairs(Mock.ActiveTweens) do
		local target = G.target(tw)
		if target and tw.PlaybackState.Name == "Playing" then
			local cur = target.Parent
			while cur and cur.Name ~= "TitleTag" do
				cur = cur.Parent
			end
			if cur and cur:IsDescendantOf(workspace) then
				n = n + 1
			end
		end
	end
	return n
end
function G.textWidth(label)
	return TextService:GetTextSize(label.Text, label.TextSize, label.Font, Vector2.new(4096, 1024)).X
end
-- per-frame connections alive (any signal the engine fires every frame)
function G.frameConns()
	local r = Mock.ConnectionReport()
	local n = 0
	for _, name in ipairs({ "Heartbeat", "RenderStepped", "Stepped", "PreRender", "PreSimulation", "PostSimulation", "PreAnimation" }) do
		n = n + (r[name] or 0)
	end
	return n
end
function G.same(a, b)
	return a ~= nil and b ~= nil and abs(a.R - b.R) < 1e-3 and abs(a.G - b.G) < 1e-3 and abs(a.B - b.B) < 1e-3
end

S.client_titles = guarded("client_titles", function()
	local KC = G.KC()
	local Config, _, Theme = KC.env()
	local TC = G.req("client/Controllers/TitleController")
	local VC = G.req("client/Controllers/VipController")
	local GQ = G.req("client/GraphicsQuality")
	if not T.check(type(TC) == "table" and type(TC.Init) == "function" and type(TC.TagOf) == "function" and type(TC.SetCrown) == "function",
		"titles: client/Controllers/TitleController loads (Init, TagOf, SetCrown)") then
		return
	end
	if not T.check(type(VC) == "table" and type(GQ) == "table" and type(GQ.Effective) == "function", "titles: VipController and GraphicsQuality load") then
		return
	end
	local RT = Config.Leaderboard and Config.Leaderboard.RankTitles
	local A_TITLE, A_RANK = Config.Attr.Title, Config.Attr.TitleRank
	if not T.check(A_TITLE == "Title" and A_RANK == "TitleRank" and type(RT) == "table" and type(RT.Tag) == "table", "titles: Config names Title / TitleRank and RankTitles (Task 18)") then
		return
	end
	local IN_MATCH = Config.Attr.InMatch

	-- saved state (put back at the end)
	local realEffective = GQ.Effective
	local gfx = "High"
	GQ.Effective = function()
		return gfx
	end
	local cam = workspace.CurrentCamera
	local oldCam = cam.CFrame
	local oldVp = { Mock.Viewport.X, Mock.Viewport.Y }
	local old = { LocalPlayer:GetAttribute(A_TITLE), LocalPlayer:GetAttribute(A_RANK) }
	Mock.SetViewport(1920, 1080)
	local added = {}
	local function add(name, userId)
		local p = Mock.AddPlayer(name, userId)
		added[#added + 1] = p
		return p
	end
	local function title(p, kind, rank)
		p:SetAttribute(A_TITLE, kind)
		p:SetAttribute(A_RANK, rank)
	end
	G.advance(0.3)

	------------------------------------------------------------------ the three tags
	local p10 = add("TitleTopTen", 985001)
	local p100 = add("TitleTopHundred", 985002)
	local pc = add("TitleCreator", 985003)
	G.advance(0.5)
	title(p10, "Top10", 3)
	title(p100, "Top100", 57)
	title(pc, "Creator", 3)
	G.advance(0.5)
	local kinds = {
		{ p = p10, kind = "Top10", text = RT.Tag.Top10 .. " " .. DOT .. " #3", size = 22 },
		{ p = p100, kind = "Top100", text = RT.Tag.Top100, size = 22 },
		{ p = pc, kind = "Creator", text = RT.Tag.Creator, size = 24 },
	}
	for _, w in ipairs(kinds) do
		local k = "titles: " .. w.kind
		local tag = TC.TagOf(w.p)
		local head = G.head(w.p)
		local okTag = T.check(tag ~= nil and tag:IsA("BillboardGui") and tag.Name == "TitleTag" and head ~= nil and tag.Adornee == head and tag:IsDescendantOf(head),
			k .. " gets one BillboardGui TitleTag on the head", tag and tag:GetFullName() or "no tag")
		T.eq(G.tagsOf(w.p), 1, k .. ": exactly one TitleTag on that character")
		if okTag then
			local H = tag.Size.Y.Offset
			T.check(tag.Size.X.Scale == 0 and tag.Size.Y.Scale == 0 and tag.Size.X.Offset == 240 and H == 40, k .. ": 240 x 40 px (a constant on-screen size; the plate's 36 and its 2 px edge each side)", tostring(tag.Size))
			T.check(tag.StudsOffset.X == 0 and abs(tag.StudsOffset.Y - 2.0) < 1e-6 and tag.StudsOffset.Z == 0, k .. ": StudsOffset (0, 2.0, 0)", tostring(tag.StudsOffset))
			T.check(tag.SizeOffset.X == 0 and abs(tag.SizeOffset.Y - (0.5 + 24 / H)) < 1e-6, k .. ": SizeOffset.Y == 0.5 + (26 - 2) / H (the plate 26 px above the anchor at any distance)", tostring(tag.SizeOffset))
			T.check(tag.MaxDistance == 90 and tag.AlwaysOnTop == false and tag.LightInfluence == 0 and tag.Enabled == true, k .. ": MaxDistance 90, not on top, LightInfluence 0, shown",
				fmt("max %s, top %s, light %s, enabled %s", tostring(tag.MaxDistance), tostring(tag.AlwaysOnTop), tostring(tag.LightInfluence), tostring(tag.Enabled)))
			T.check(#tag:GetDescendants() <= 6, k .. ": at most 6 instances inside the tag (no crown)", tostring(#tag:GetDescendants()))
			local plate, label = G.parts(tag)
			if T.check(plate ~= nil and plate:IsA("Frame") and label ~= nil and label:IsA("TextLabel"), k .. ": TitleTag > Plate > Label") then
				T.eq(label.Text, w.text, k .. ": the text")
				T.check(label.TextSize == w.size and label.TextSize >= 20 and label:GetAttribute("FontRole") == "Nameplate", k .. ": " .. w.size .. " px (>= 20) in the Nameplate role",
					fmt("%s px, %s", tostring(label.TextSize), tostring(label:GetAttribute("FontRole"))))
				-- (kit-b U9-3) a flat kit B tag: an opaque face in its role's colour, a wood edge, its lip, square; no outline,
				-- no gradient
				local face = ({ Top10 = Theme.Sign.Gold, Top100 = Theme.Sign.Tile, Creator = Theme.Sign.Navy })[w.kind]
				T.check(label:FindFirstChildWhichIsA("UIStroke") == nil, k .. ": no outline on the text (it sits on an opaque face)")
				T.check(G.same(plate.BackgroundColor3, face) and plate.BackgroundTransparency == 0 and plate:FindFirstChildWhichIsA("UICorner") == nil
					and plate:FindFirstChild("SignEdge") ~= nil and plate:FindFirstChild("Lip") ~= nil, k .. ": an opaque square plate in its role's colour, a wood edge and its lip")
				local gradients = 0
				for _, d in ipairs(tag:GetDescendants()) do
					gradients = gradients + (d:IsA("UIGradient") and 1 or 0)
				end
				T.eq(gradients, 0, k .. ": no gradient in the tag")
				local tw = G.textWidth(label)
				local px, pw = plate.AbsolutePosition.X, plate.AbsoluteSize.X
				local lx, lw = label.AbsolutePosition.X, label.AbsoluteSize.X
				T.check(pw >= tw and pw <= tw + 40 and abs(px + pw / 2 - 120) <= 1, k .. ": the plate is the text's width (plus padding), centred",
					fmt("plate %d at %d, text %d", pw, px, tw))
				local textX = lx + (lw - tw) / 2
				T.check(label.TextXAlignment == Enum.TextXAlignment.Center and textX >= px - 0.5 and textX + tw <= px + pw + 0.5, k .. ": the text sits centred inside the plate",
					fmt("text %d..%d, plate %d..%d", textX, textX + tw, px, px + pw))
				T.eq(G.titleTweens(), 0, k .. ": nothing in a tag tweens (no rainbow)")
			end
		end
	end

	------------------------------------------------------------------ hidden in a battle
	p100:SetAttribute("InBattle", "B1")
	G.advance(0.3)
	local t100 = TC.TagOf(p100)
	T.check(t100 == nil or t100.Enabled == false, "titles: hidden while that player is InBattle")
	p100:SetAttribute("InBattle", nil)
	G.advance(0.3)
	t100 = TC.TagOf(p100)
	T.check(t100 ~= nil and t100.Enabled, "titles: back after the battle")

	------------------------------------------------------------------ Low graphics: the same flat tag
	local tag10 = TC.TagOf(p10)
	gfx = "Low"
	G.advance(0.6)
	T.check(TC.TagOf(p10) == tag10 and tag10 ~= nil and tag10.Enabled, "titles: the Top10 tag still shows on Low, unchanged (kit B: nothing to pause)")
	T.eq(G.titleTweens(), 0, "titles: no tween on Low")
	gfx = "High"
	G.advance(0.6)
	T.eq(G.titleTweens(), 0, "titles: ...nor on High")

	------------------------------------------------------------------ the local player: third person only
	title(LocalPlayer, "Top100", 40)
	G.advance(0.5)
	local myTag = TC.TagOf(LocalPlayer)
	local myHead = G.head(LocalPlayer)
	if T.check(myTag ~= nil and myHead ~= nil, "titles: the local player gets their own tag") then
		cam.CFrame = CFrame.new(myHead.Position + Vector3.new(0, 0.3, 0.5))
		G.advance(0.6)
		T.check(myTag.Enabled == false, "titles: the local player's tag hides with the camera at the head (first person)")
		cam.CFrame = CFrame.new(myHead.Position + Vector3.new(0, 3, 12))
		G.advance(0.6)
		T.check(myTag.Enabled == true, "titles: ...and shows with the camera 12 studs away (third person)")
		local otherHead = G.head(p100)
		cam.CFrame = CFrame.new(otherHead.Position + Vector3.new(0, 0.2, 0.3))
		G.advance(0.6)
		T.check(TC.TagOf(p100) ~= nil and TC.TagOf(p100).Enabled, "titles: another player's tag ignores the camera distance")
	end
	cam.CFrame = oldCam
	title(LocalPlayer, nil, nil)
	G.advance(0.3)
	T.check(TC.TagOf(LocalPlayer) == nil and G.tagsOf(LocalPlayer) == 0, "titles: the local player's tag goes with the title")

	------------------------------------------------------------------ the VIP crown inside a titled tag
	local pv = add("TitleVip", 985004)
	G.advance(0.5)
	pv:SetAttribute("OwnedPasses", "VIP")
	G.advance(0.5)
	local vc = G.vipCrown(pv)
	T.check(vc ~= nil and vc.Enabled, "titles: an untitled VIP has the VipCrown")
	title(pv, "Top100", 40)
	G.advance(0.5)
	local function crownCheck(label)
		local tag = TC.TagOf(pv)
		local crown = tag and tag:FindFirstChild("Crown")
		local plate = tag and tag:FindFirstChild("Plate")
		if not T.check(crown ~= nil and crown:IsA("GuiObject") and crown.Visible ~= false and plate ~= nil, "titles: " .. label .. ": a titled VIP's Crown is drawn inside the TitleTag") then
			return
		end
		T.check(G.vipCrown(pv) == nil, "titles: " .. label .. ": no VipCrown billboard on that head")
		T.check(tag.Size.X.Offset == 240 and tag.Size.Y.Offset == 76 and abs(tag.SizeOffset.Y - (0.5 + 24 / 76)) < 1e-6, "titles: " .. label .. ": the billboard is 240 x 76 with the crown slot, SizeOffset.Y 0.5 + (26 - 2) / 76",
			fmt("%s, %s", tostring(tag.Size), tostring(tag.SizeOffset)))
		T.check(crown.AbsoluteSize.X == 34 and crown.AbsoluteSize.Y == 34 and abs(crown.AbsolutePosition.X + 17 - 120) <= 1, "titles: " .. label .. ": the Crown is 34 x 34, centred",
			fmt("%dx%d at %d", crown.AbsoluteSize.X, crown.AbsoluteSize.Y, crown.AbsolutePosition.X))
		T.check(abs(plate.AbsolutePosition.Y - (crown.AbsolutePosition.Y + 34) - 4) <= 0.5 and abs(plate.AbsolutePosition.Y + plate.AbsoluteSize.Y - 74) <= 0.5,
			"titles: " .. label .. ": the Crown sits 4 px above the Plate, the Plate 2 px (its edge) above the bottom", fmt("crown y %d, plate y %d h %d", crown.AbsolutePosition.Y, plate.AbsolutePosition.Y, plate.AbsoluteSize.Y))
		-- (kit-b U7a) the crown is a PixelIcon: its host, its Frame and one Frame per merged run; (U9-3) twice (the gold crown
		-- over its wood lip) in a holder, on top of the tag's 6
		local PI = G.req("shared/PixelIcon")
		local budget = 6 + 1 + 2 * (2 + (PI and #PI.Runs("crown") or 0))
		T.check(#tag:GetDescendants() <= budget, "titles: " .. label .. ": at most " .. budget .. " instances inside the tag with the crown (6 + the crown on its lip)", tostring(#tag:GetDescendants()))
	end
	local function noCrown(label)
		local tag = TC.TagOf(pv)
		local crown = tag and tag:FindFirstChild("Crown")
		T.check(tag ~= nil and (crown == nil or crown.Visible == false) and G.vipCrown(pv) == nil, "titles: " .. label .. ": no crown at all")
		T.check(tag ~= nil and abs(tag.SizeOffset.Y - (0.5 + 24 / tag.Size.Y.Offset)) < 1e-6, "titles: " .. label .. ": SizeOffset.Y follows the billboard's height")
	end
	crownCheck("title over VIP")
	pv:SetAttribute(IN_MATCH, true)
	G.advance(1.2)
	noCrown("in a match")
	pv:SetAttribute(IN_MATCH, nil)
	G.advance(1.2)
	crownCheck("after the match")
	gfx = "Low"
	G.advance(1.2)
	noCrown("Low graphics")
	gfx = "High"
	G.advance(1.2)
	crownCheck("back on High")
	title(pv, nil, nil)
	G.advance(0.5)
	T.check(TC.TagOf(pv) == nil and G.tagsOf(pv) == 0, "titles: the title cleared on a VIP removes the tag")
	vc = G.vipCrown(pv)
	T.check(vc ~= nil and vc:IsA("BillboardGui") and vc.Enabled and abs(vc.StudsOffset.Y - 2.4) < 1e-6, "titles: ...and the VipCrown is back at 2.4 studs",
		vc and tostring(vc.StudsOffset) or "none")
	local pu = add("TitleVipPlain", 985005)
	G.advance(0.5)
	pu:SetAttribute("OwnedPasses", "VIP")
	G.advance(0.5)
	vc = G.vipCrown(pu)
	T.check(vc ~= nil and vc.Enabled and abs(vc.StudsOffset.Y - 2.4) < 1e-6 and TC.TagOf(pu) == nil and G.tagsOf(pu) == 0, "titles: an untitled VIP: the VipCrown at 2.4 studs, no TitleTag")

	------------------------------------------------------------------ respawn (Review Focus 5)
	local oldTag = TC.TagOf(p10)
	Mock.Respawn(p10)
	G.advance(0.5)
	local newTag = TC.TagOf(p10)
	T.check(newTag ~= nil and newTag ~= oldTag and newTag.Adornee == G.head(p10) and newTag:IsDescendantOf(p10.Character), "titles: respawn -> a tag on the new head")
	T.eq(G.tagsOf(p10), 1, "titles: respawn -> exactly one tag on the new character")
	T.check(oldTag ~= nil and oldTag.Parent == nil, "titles: respawn -> the old tag is gone")

	------------------------------------------------------------------ the attribute cleared
	title(p10, nil, nil)
	G.advance(0.3)
	T.check(TC.TagOf(p10) == nil and G.tagsOf(p10) == 0 and newTag.Parent == nil, "titles: the attribute cleared -> the tag removed")

	------------------------------------------------------------------ ten Top10 players: no tween, no per-frame work
	title(p100, nil, nil)
	title(pc, nil, nil)
	G.advance(0.3)
	local ten = {}
	for i = 1, 10 do
		ten[i] = add("TitleTen" .. i, 985100 + i)
	end
	G.advance(0.5)
	local frames0, tweens0 = G.frameConns(), G.titleTweens()
	T.eq(tweens0, 0, "titles: no tag tween before the ten")
	for i, p in ipairs(ten) do
		title(p, "Top10", i)
	end
	G.advance(1)
	T.eq(G.titleTweens(), 0, "titles: ten Top10 players -> no tween (kit B: a flat tag)")
	T.eq(G.frameConns(), frames0, "titles: ten Top10 players -> no per-frame connection added")
	local _, label7 = G.parts(TC.TagOf(ten[7]))
	T.eq(label7 and label7.Text, RT.Tag.Top10 .. " " .. DOT .. " #7", "titles: rank 7 reads #7")

	------------------------------------------------------------------ everyone leaves
	for _, p in ipairs(added) do
		Mock.RemovePlayer(p)
	end
	G.advance(0.5)
	T.eq(#G.allTags(), 0, "titles: every tag is gone once the players leave")
	T.eq(G.titleTweens(), 0, "titles: no tag tween left playing")
	local stale = 0
	for _, p in ipairs(added) do
		if TC.TagOf(p) ~= nil then
			stale = stale + 1
		end
	end
	T.eq(stale, 0, "titles: TagOf answers nil for players who left")

	GQ.Effective = realEffective
	cam.CFrame = oldCam
	title(LocalPlayer, old[1], old[2])
	Mock.SetViewport(oldVp[1], oldVp[2])
	G.advance(0.6)
	KC.flushErrors("client_titles")
	KC.flushWarnings("client_titles")
end)

return S
