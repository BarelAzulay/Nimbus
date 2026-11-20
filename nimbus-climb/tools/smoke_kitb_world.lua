-- smoke_kitb_world.lua: the Pitch 2 world lane (branch kitb-p2-world; docs/superpowers/specs/2026-11-20-pitch2-build-design.md
-- items 04_world_ui B "Stone tags" and 13_travel_guide A "Gold arrow + dot trail"). Both worlds (ARGS.context picks the
-- half); registered on its own line in tools/smoke.py.
--   world_signs_kit       (server, after boot) item 04 B: the HUD's stone card tier floating in the world. No navy capsule:
--                         the NPC nameplates are one stone card (Sign.Stone face, a 3 px mitred wood edge, a 5 px lip in the
--                         NPC's role colour), the name and the title in the kit's brown ink, the "!" a gold block pinned on
--                         the card's top-right corner (no rotation); the Storm Altar's header is A's hanging board (a wood
--                         beam, two ropes, the stone board, the violet "Secret Roulette" plank); THE GATES face is a stone
--                         card listing only the five gate names at 52 px, each with its pixel icon
--   travel_gate_enter     (server, after boot) item 13 A: the lobby gates' prompts say "Enter" (they said "Travel")
--   client_world_signs_kit (client) item 04 B: the NPCs' "!" never rotates (NpcController's wiggle went); a pet tag is a wood chip with the stars INSIDE it
--                         (the stars never over the level text) and one HP block row under it (SPECIAL and XP live on the
--                         HUD cards); the CREATOR title is a stone tag with a gold lip and the pixel crown; a world prompt is
--                         the kit's plank (the navy key block, the action, a wood tab with the object's name); the folded
--                         menu tab's "!" is a red block wholly on screen, inside the tab
--   damage_numbers_short  item 04 B: a hit pops "+" .. Theme.Short(damage) ("+20.6K"; a crit in gold, a Storm hit in violet)
--                         and each target keeps ONE running total on a stone chip with a red lip ("176K"), so numbers never
--                         stack into a wall; the total clears after a quiet spell; no raw tostring(floor(dmg)) number is left
--   travel_shows_way      item 13 A: the Shop's Secret card says "Show the way" and never teleports (no QuickTravel); a tap
--                         closes the Shop and starts TutorialController.Guide (the voxel arrow over the Altar gate, flat gold
--                         dot blocks from just ahead of the feet, the stone GuideSign beside the arrow; no Neon, no light);
--                         the "Guiding to Storm Altar" chip's X stops it and leaves nothing behind; a second start replaces
--                         the first; at the gate the chip says "You're here: press E" and the guide ends by itself; started
--                         away from the lobby it routes home first (the chip "Home first, then follow the arrow" and the
--                         pointer on the Home tile), then picks up in the lobby; a match / battle ends it; the lobby gates'
--                         prompt says "Enter"; while a match locks the way home the button greys with "Finish the match first"
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local fmt = string.format
local abs = math.abs

local function hex(c)
	if typeof(c) ~= "Color3" then
		return tostring(c)
	end
	return fmt("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function same(a, b)
	return typeof(a) == "Color3" and typeof(b) == "Color3" and abs(a.R - b.R) < 0.01 and abs(a.G - b.G) < 0.01 and abs(a.B - b.B) < 0.01
end

local function req(path)
	local inst = Mock.GetPath(path)
	local ok, mod = false, nil
	if inst then
		ok, mod = pcall(require, inst)
	end
	return ok and mod or nil
end
local function shared(name)
	return req(ROOTS.shared .. "/" .. name)
end
local function client(path)
	return req(ROOTS["client"] .. "/" .. path)
end
local function pg()
	return game:GetService("Players").LocalPlayer.PlayerGui
end
local function rect(o)
	local p, s = o.AbsolutePosition, o.AbsoluteSize
	return { X = p.X, Y = p.Y, R = p.X + s.X, B = p.Y + s.Y, W = s.X, H = s.Y }
end
local function show(r)
	return r and fmt("%.0f,%.0f .. %.0f,%.0f", r.X, r.Y, r.R, r.B) or "nil"
end
local function overlap(a, b)
	return a.X < b.R - 0.5 and b.X < a.R - 0.5 and a.Y < b.B - 0.5 and b.Y < a.B - 0.5
end
-- the round corners, gradients and navy faces under `root` (the old capsule kit) -> list
local function oldKit(root, Theme)
	local out = {}
	local navy = { Theme.Colors.Panel, Theme.Colors.PanelLight, Theme.Colors.Navy, Theme.Sign.Navy }
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("UICorner") and (d.CornerRadius.Scale > 0 or d.CornerRadius.Offset > 0) then
			out[#out + 1] = "corner on " .. d.Parent.Name
		elseif d:IsA("UIGradient") then
			out[#out + 1] = "gradient on " .. d.Parent.Name
		elseif d:IsA("GuiObject") and d.BackgroundTransparency < 0.5 and d.Name ~= "Key" then
			for _, c in ipairs(navy) do
				if same(d.BackgroundColor3, c) then
					out[#out + 1] = "navy face on " .. d.Name
					break
				end
			end
		end
	end
	return out
end
-- a kit block: its face, the mitred SignEdge and the Lip
local function block(o, face, edgePx, lipPx, lipColour)
	if not o then
		return false, "missing"
	end
	local edge = o:FindFirstChild("SignEdge")
	local lip = o:FindFirstChild("Lip")
	local ok = o.BackgroundTransparency == 0 and (face == nil or same(o.BackgroundColor3, face)) and edge ~= nil and edge:IsA("UIStroke")
		and edge.LineJoinMode == Enum.LineJoinMode.Miter and (edgePx == nil or abs(edge.Thickness - edgePx) < 0.01) and lip ~= nil
		and lip.Visible and (lipPx == nil or abs(lip.Size.Y.Offset - lipPx) < 0.01) and (lipColour == nil or same(lip.BackgroundColor3, lipColour))
	return ok, fmt("%s face %s edge %s lip %s %s", o.Name, hex(o.BackgroundColor3), edge and tostring(edge.Thickness) or "-",
		lip and tostring(lip.Size.Y.Offset) or "-", lip and hex(lip.BackgroundColor3) or "-")
end
local function iconIn(root, name)
	for _, d in ipairs(root:GetDescendants()) do
		if d:GetAttribute("PixelIcon") == name then
			return d
		end
	end
	return nil
end

local function serverScenarios()
	local S = {}
	local K = _G.K

	S.world_signs_kit = guarded("world_signs_kit", function()
		local Theme = shared("Theme")
		local Sign = Theme and Theme.Sign
		if not T.check(Theme ~= nil and Sign ~= nil, "world signs: (setup) Theme loads") then
			return
		end
		Mock.SetViewport(1920, 1080)
		K.advance(0.3)
		local CollectionService = game:GetService("CollectionService")

		-- the NPC nameplates (NpcService, replicated), built here as the worldtext audit does when the run has none
		local made = nil
		if #CollectionService:GetTagged("NC_Npc") == 0 then
			local NS = req(ROOTS["server"] .. "/Services/NpcService")
			if NS and type(NS.Init) == "function" then
				local Config = shared("Config")
				local spots = {}
				for i = 1, 6 do
					local a = (i - 1) * math.pi / 3
					local pos = Config.Lobby.Origin + Vector3.new(math.cos(a) * 30, 0, math.sin(a) * 30)
					spots[i] = CFrame.new(pos, Vector3.new(Config.Lobby.Origin.X, pos.Y, Config.Lobby.Origin.Z))
				end
				pcall(NS.Init, { NpcSpots = spots })
				made = workspace:FindFirstChild("NimbusNpcs")
				K.advance(1.5)
			end
		end
		local npcs = CollectionService:GetTagged("NC_Npc")
		if T.check(#npcs > 0, "world signs: (setup) the NPCs exist", tostring(#npcs)) then
			for _, model in ipairs(npcs) do
				local gui = model:FindFirstChild("Nameplate", true)
				local k = "world signs: " .. model.Name
				if T.check(gui ~= nil, k .. ": (setup) its Nameplate") then
					local bad = oldKit(gui, Theme)
					T.check(#bad == 0, k .. ": no navy capsule, no round corner, no gradient", table.concat(bad, ", "))
					local card = gui:FindFirstChild("Card", true)
					local accent = model:GetAttribute("Accent")
					local ok, why = block(card, Sign.Stone, 3, 5)
					T.check(ok, k .. ": one stone card, a 3 px mitred wood edge, a 5 px lip", why)
					local lip = card and card:FindFirstChild("Lip")
					T.check(lip ~= nil and not same(lip.BackgroundColor3, Sign.StoneLip) and typeof(accent) == "Color3",
						k .. ": the lip in the NPC's role colour (not the stone lip)", lip and hex(lip.BackgroundColor3) or "no lip")
					local name, title = card and card:FindFirstChild("Name", true), card and card:FindFirstChild("Title", true)
					T.check(name ~= nil and title ~= nil and same(name.TextColor3, Sign.Text) and same(title.TextColor3, Sign.TextMuted)
						and name.TextSize >= 28 and title.TextSize >= 19,
						k .. ": the name (28 px) and the title (19 px) in the kit's brown ink", name and title and (hex(name.TextColor3) .. " / " .. hex(title.TextColor3)) or "missing")
					local badge = gui:FindFirstChild("Badge", true)
					local okB, whyB = block(badge, Sign.Gold)
					T.check(okB and iconIn(badge, "bang") ~= nil and badge.Rotation == 0, k .. ": the '!' is a gold kit block holding the pixel bang, not rotated", whyB)
					if card and badge then
						local c, b = rect(card), rect(badge)
						local cx, cy = (b.X + b.R) / 2, (b.Y + b.B) / 2
						T.check(abs(cx - c.R) <= 20 and abs(cy - c.Y) <= 20 and b.Y < c.Y and b.R > c.R,
							k .. ": the '!' block is pinned on the card's top-right corner", show(b) .. " card " .. show(c))
					end
				end
			end
		end
		if made then
			made:Destroy()
			K.advance(0.3)
		end

		-- the Storm Altar's header: A's hanging board
		local header, face = nil, nil
		local census = { bb = 0, sg = 0, pp = 0 }
		for _, d in ipairs(workspace:GetDescendants()) do
			census.bb = census.bb + (d:IsA("BillboardGui") and 1 or 0)
			census.sg = census.sg + (d:IsA("SurfaceGui") and 1 or 0)
			census.pp = census.pp + (d:IsA("ProximityPrompt") and 1 or 0)
			if d:IsA("TextLabel") and d.Text == "STORM ALTAR" then
				local bb = d:FindFirstAncestorWhichIsA("BillboardGui")
				header = (bb and bb.Name == "TitleTag") and bb or header
			elseif d:IsA("TextLabel") and d.Text == "THE GATES" then
				face = d:FindFirstAncestorWhichIsA("SurfaceGui") or face
			end
		end
		T.info(fmt("*world signs: the server world holds %d billboards, %d surface guis, %d prompts", census.bb, census.sg, census.pp))
		if T.check(header ~= nil, "world signs: (setup) the Storm Altar's header billboard") then
			local bad = oldKit(header, Theme)
			T.check(#bad == 0, "world signs: the altar header has no navy, no round corner, no gradient", table.concat(bad, ", "))
			local beam, board, pill = header:FindFirstChild("Beam", true), header:FindFirstChild("Board", true), header:FindFirstChild("Pill", true)
			local ropes = 0
			for _, d in ipairs(header:GetDescendants()) do
				ropes = ropes + ((d.Name == "Rope" and d:IsA("Frame")) and 1 or 0)
			end
			T.check(beam ~= nil and same(beam.BackgroundColor3, Sign.Wood) and ropes >= 2, "world signs: the header hangs from a wood beam on ropes", tostring(ropes) .. " ropes")
			local okBoard, whyBoard = block(board, Sign.Stone)
			T.check(okBoard, "world signs: the header board is a stone kit block", whyBoard)
			local title, sub = board and board:FindFirstChild("Title", true), board and board:FindFirstChild("Subtitle", true)
			T.check(title ~= nil and title.Text == "STORM ALTAR" and same(title.TextColor3, Sign.Text) and sub ~= nil and sub.Text == "Secret pets",
				"world signs: 'STORM ALTAR' in brown ink over 'Secret pets'", title and title.Text or "no title")
			local okPill, whyPill = block(pill, Sign.Violet)
			local pillText = pill and pill:FindFirstChildWhichIsA("TextLabel", true)
			T.check(okPill and pillText ~= nil and pillText.Text == "Secret Roulette", "world signs: the violet 'Secret Roulette' plank under the board", whyPill)
		end

		-- THE GATES face: the five names at 52 px with their pixel icons, nothing else
		if T.check(face ~= nil, "world signs: (setup) THE GATES board's face") then
			local badG = oldKit(face, Theme)
			T.check(#badG == 0, "world signs: THE GATES face has no navy, no round corner, no gradient", table.concat(badG, ", "))
			local okG, whyG = block(face:FindFirstChild("Panel"), Sign.Stone, 6, 8)
			T.check(okG, "world signs: THE GATES face is a stone card (6 px wood edge, 8 px lip)", whyG)
			local names, other = {}, {}
			local want = { OBBY = true, DUNGEON = true, RING = true, ARENA = true, ALTAR = true }
			for _, d in ipairs(face:GetDescendants()) do
				if d:IsA("TextLabel") and d.Text ~= "" then
					if want[d.Text] then
						local hasIcon = false
						for _, s in ipairs(d.Parent:GetDescendants()) do
							hasIcon = hasIcon or type(s:GetAttribute("PixelIcon")) == "string"
						end
						names[#names + 1] = d.Text .. "@" .. d.TextSize .. (hasIcon and "+icon" or "")
						T.check(d.TextSize == 52 and hasIcon, "world signs: THE GATES lists " .. d.Text .. " at 52 px with its pixel icon", d.TextSize .. " px, icon " .. tostring(hasIcon))
					elseif d.Text ~= "THE GATES" then
						other[#other + 1] = d.Text
					end
				end
			end
			T.check(#names == 5 and #other == 0, "world signs: THE GATES face holds only the five gate names (no descriptions, no footer)",
				table.concat(names, " ") .. " | other: " .. table.concat(other, " / "))
		end

		K.flushErrors("world_signs_kit")
	end)

	return S
end

local function clientScenarios()
	local S = {}
	local KC = _G.KC

	----------------------------------------------------------------------------------------------------------------
	-- world_signs_kit
	----------------------------------------------------------------------------------------------------------------
	S.client_world_signs_kit = guarded("client_world_signs_kit", function()
		local Theme = shared("Theme")
		local Sign = Theme and Theme.Sign
		if not T.check(Theme ~= nil and Sign ~= nil, "world signs: (setup) Theme loads") then
			return
		end
		Mock.SetViewport(1920, 1080)
		KC.advance(0.3)

		-- (the NpcController "new tips" wiggle turned the '!' block 12 degrees) standing beside an NPC, its '!' stays pinned
		local NS = req(ROOTS["server"] .. "/Services/NpcService")
		local Config = shared("Config")
		local made = nil
		if NS and type(NS.Init) == "function" then
			local spots = {}
			for i = 1, 6 do
				local a = (i - 1) * math.pi / 3
				local pos = Config.Lobby.Origin + Vector3.new(math.cos(a) * 30, 0, math.sin(a) * 30)
				spots[i] = CFrame.new(pos, Vector3.new(Config.Lobby.Origin.X, pos.Y, Config.Lobby.Origin.Z))
			end
			pcall(NS.Init, { NpcSpots = spots })
			made = workspace:FindFirstChild("NimbusNpcs")
			Mock.Teleport(game:GetService("Players").LocalPlayer, CFrame.new(spots[1].Position + Vector3.new(0, 3, 6)))
			KC.advance(1.5)
		end
		local turned, seen = {}, 0
		for _, d in ipairs(made and made:GetDescendants() or {}) do
			if d.Name == "Badge" and d:IsA("GuiObject") then
				seen = seen + 1
				if d.Rotation ~= 0 then
					turned[#turned + 1] = d:GetFullName() .. " " .. tostring(d.Rotation)
				end
			end
		end
		T.check(seen > 0 and #turned == 0, "world signs: the NPCs' '!' blocks never rotate (pinned, no wiggle)", seen .. " seen; " .. table.concat(turned, ", "))
		if made then
			made:Destroy()
			KC.advance(0.3)
		end

		-- a pet tag: the wood chip with the stars inside, one HP row under it
		local PetCard = client("UI/PetCard")
		if T.check(PetCard ~= nil, "world signs: (setup) PetCard loads") then
			local part = Instance.new("Part")
			part.Anchored = true
			part.Parent = workspace
			local card = PetCard.New(part, "Unit", 3)
			card:SetLevel(100, 2, false)
			card:SetHp(0.75)
			card:SetSpecial(0.5, false)
			card:SetXp(0.35)
			KC.advance(0.1)
			local gui = card.Gui
			local plate = gui:FindFirstChild("Plate")
			local okChip, whyChip = block(plate, Sign.Wood)
			T.check(okChip, "world signs: the pet tag is a wood chip (kit block)", whyChip)
			local bad = oldKit(gui, Theme)
			T.check(#bad == 0, "world signs: the pet tag has no navy plaque", table.concat(bad, ", "))
			local badge, level = gui:FindFirstChild("StarBadge"), plate and plate:FindFirstChild("Level")
			if T.check(badge ~= nil and badge.Visible and level ~= nil, "world signs: (setup) the stars and the level") then
				local b, p, l = rect(badge), rect(plate), rect(level)
				T.check(b.X >= p.X - 0.5 and b.R <= p.R + 0.5 and b.Y >= p.Y - 0.5 and b.B <= p.B + 0.5, "world signs: the stars sit INSIDE the chip", show(b) .. " chip " .. show(p))
				T.check(not overlap(b, l), "world signs: the stars never overlap the level tag", show(b) .. " level " .. show(l))
				T.check(badge.BackgroundTransparency == 1 and badge:FindFirstChild("SignEdge") == nil, "world signs: the stars have no plaque of their own")
			end
			local hp, sp, xp = plate and plate:FindFirstChild("Hp"), plate and plate:FindFirstChild("Special"), plate and plate:FindFirstChild("Xp")
			T.check(hp ~= nil and hp.Visible and sp ~= nil and not sp.Visible and xp ~= nil and not xp.Visible,
				"world signs: one HP block row (SPECIAL and XP live on the HUD cards)")
			if hp and plate then
				T.check(rect(hp).Y >= rect(plate).B - 0.5, "world signs: the HP row sits under the chip", show(rect(hp)) .. " chip " .. show(rect(plate)))
			end
			T.check(sp and abs((sp:GetAttribute("Frac") or 0) - 0.5) < 1e-6 and xp and abs((xp:GetAttribute("Frac") or 0) - 0.35) < 1e-6,
				"world signs: SetSpecial / SetXp still keep their fractions (callers unchanged)")
			card:SetMode("Follower")
			KC.advance(0.1)
			local shownRows = 0
			for _, n in ipairs({ "Hp", "Special", "Xp", "Timer" }) do
				local r = plate:FindFirstChild(n)
				shownRows = shownRows + ((r and r.Visible) and 1 or 0)
			end
			T.eq(shownRows, 0, "world signs: a follower's tag is the chip alone")
			card:Destroy()
			part:Destroy()
		end

		-- the CREATOR title: a stone tag, a gold lip, the pixel crown
		local TC = client("Controllers/TitleController")
		if T.check(TC ~= nil and type(TC.TagOf) == "function", "world signs: (setup) TitleController") then
			local Config = shared("Config")
			local p = Mock.AddPlayer("WorldCreator", 987001)
			KC.advance(0.5)
			p:SetAttribute(Config.Attr.TitleRank, 1)
			p:SetAttribute(Config.Attr.Title, "Creator")
			KC.advance(1.2)
			local tag = TC.TagOf(p)
			local plate = tag and tag:FindFirstChild("Plate")
			local okT, whyT = block(plate, Sign.Stone, nil, nil, Sign.GoldLip)
			T.check(okT, "world signs: CREATOR is a stone tag on a gold lip", whyT)
			local crown = plate and iconIn(plate, "crown")
			local label = plate and plate:FindFirstChild("Label")
			if T.check(crown ~= nil and label ~= nil, "world signs: CREATOR wears the pixel crown inside its tag") then
				T.check(rect(crown).R <= rect(label).X + 0.5 + (label.AbsoluteSize.X - label.TextBounds.X) / 2, "world signs: the crown leads the word",
					show(rect(crown)) .. " label " .. show(rect(label)))
			end
			Mock.RemovePlayer(p)
			KC.advance(0.3)
		end

		-- a world prompt: the kit plank (the Storm Altar's 'Secret Roll')
		-- (the client world has no server lobby: a prompt as StormAltar.lua builds it, replicated)
		local promptPart = Instance.new("Part")
		promptPart.Name = "PromptAnchorTest"
		promptPart.Anchored = true
		promptPart.Parent = workspace
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Secret Roll"
		prompt.ObjectText = "Storm Altar"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = promptPart
		if T.check(prompt ~= nil, "world signs: (setup) the Storm Altar's prompt") then
			KC.advance(0.5)
			T.check(prompt.Style == Enum.ProximityPromptStyle.Custom, "world signs: the prompt draws the kit plank (Style Custom), not Roblox's default", tostring(prompt.Style))
			Mock.ShowPrompt(prompt, Enum.ProximityPromptInputType.Keyboard)
			KC.advance(0.1)
			local card = pg():FindFirstChild("PromptCard")
			local plank = card and card:FindFirstChild("Plank", true)
			local key = card and card:FindFirstChild("Key", true)
			local action = card and card:FindFirstChild("Action", true)
			local tab = card and card:FindFirstChild("Tab", true)
			local okP, whyP = block(plank, Sign.Tile, 3, 5)
			T.check(card ~= nil and card:IsA("BillboardGui") and okP, "world signs: the prompt is a stone plank (3 px wood edge, 5 px lip)", whyP)
			local keyText = key and key:FindFirstChildWhichIsA("TextLabel", true)
			T.check(key ~= nil and same(key.BackgroundColor3, Sign.Navy) and keyText ~= nil and keyText.Text == "E", "world signs: the navy key block reads E",
				keyText and keyText.Text or "no key")
			T.check(action ~= nil and action.Text == "Secret Roll" and same(action.TextColor3, Sign.Text), "world signs: the action reads 'Secret Roll' in brown", action and action.Text or "none")
			local tabText = tab and tab:FindFirstChildWhichIsA("TextLabel", true)
			T.check(tab ~= nil and same(tab.BackgroundColor3, Sign.Wood) and tabText ~= nil and tabText.Text == "Storm Altar", "world signs: a wood tab names the object",
				tabText and tabText.Text or "no tab")
			Mock.HidePrompt(prompt)
			KC.advance(0.1)
			local left = pg():FindFirstChild("PromptCard")
			T.check(left == nil or not left.Enabled, "world signs: the plank goes with the prompt")
		end
		promptPart:Destroy()

		-- the folded menu tab: the red "!" block wholly on screen, inside the tab
		local MC = client("Controllers/MenuController")
		local menu = pg():FindFirstChild("NimbusMenu")
		local tab = menu and menu:FindFirstChild("Toggle", true)
		if T.check(MC ~= nil and tab ~= nil, "world signs: (setup) the menu column's tab") then
			local tileBadge = nil
			for _, d in ipairs(menu:GetDescendants()) do
				if d.Name == "Badge" and d:IsA("GuiObject") and d.Parent ~= tab and d:FindFirstAncestor("MenuColumn") then
					tileBadge = tileBadge or d
				end
			end
			if tileBadge then
				tileBadge.Visible = true
			end
			MC.SetColumnCollapsed(true, false)
			KC.advance(0.5)
			local badge = tab:FindFirstChild("Badge")
			if T.check(badge ~= nil and badge.Visible, "world signs: (setup) the folded tab shows its '!' (a tile wants attention)") then
				local b, t = rect(badge), rect(tab)
				local okR, whyR = block(badge, Sign.Red)
				T.check(okR and (badge:FindFirstChild("Mark", true) ~= nil or iconIn(badge, "bang") ~= nil), "world signs: the tab's '!' is a red kit block with its mark", whyR)
				T.check(b.X >= t.X - 0.5 and b.R <= t.R + 0.5 and b.Y >= t.Y - 0.5 and b.B <= t.B + 0.5 and b.X >= 0, "world signs: the '!' lies inside the tab, wholly on screen",
					show(b) .. " tab " .. show(t))
				T.check(abs(t.X) <= 0.5, "world signs: the folded tab sits flush on the left edge", show(t))
			end
			MC.SetColumnCollapsed(false, false)
			if tileBadge then
				tileBadge.Visible = false
			end
			KC.advance(0.3)
		end
		KC.flushErrors("client_world_signs_kit")
	end)

	----------------------------------------------------------------------------------------------------------------
	-- damage_numbers_short
	----------------------------------------------------------------------------------------------------------------
	S.damage_numbers_short = guarded("damage_numbers_short", function()
		local Theme = shared("Theme")
		local Sign = Theme and Theme.Sign
		local BC = client("Controllers/BattleController")
		local Fx = BC and BC._Fx
		if not T.check(Fx ~= nil and type(Fx.HitLook) == "function" and type(Fx.Total) == "function", "damage numbers: BattleController._Fx.HitLook / Total exist") then
			return
		end
		local text, colour = Fx.HitLook(20628, {})
		T.eq(text, "+20.6K", "damage numbers: a hit pops '+' .. Theme.Short (20628 -> +20.6K)")
		local ct, cc, cpx = Fx.HitLook(136205, { crit = true })
		T.check(ct == "+136K" and same(cc, Sign.Gold), "damage numbers: a crit pops '+136K' in gold", tostring(ct) .. " " .. hex(cc))
		local st, sc = Fx.HitLook(18332, { element = true }, "Storm")
		T.check(st == "+18.3K" and same(sc, Sign.Violet), "damage numbers: a Storm hit pops '+18.3K' in violet", tostring(st) .. " " .. hex(sc))
		local bt = Fx.HitLook(20, { burn = true })
		T.check(type(bt) == "string" and bt:find("+20", 1, true) ~= nil, "damage numbers: a burn tick still reads its short number", tostring(bt))
		T.eq(Fx.HitLook(3, {}), "+3", "damage numbers: a small hit reads '+3'")

		local part = Instance.new("Part")
		part.Anchored = true
		part.Parent = workspace
		local u = { root = part, height = 4, id = 991 }
		Fx.Total(u, 20628)
		KC.advance(0.05)
		local gui = u.total and u.total.gui
		local chip = gui and gui:FindFirstChild("Chip", true)
		local label = chip and chip:FindFirstChildWhichIsA("TextLabel", true)
		if T.check(gui ~= nil and gui:IsA("BillboardGui") and gui.Name == "DamageTotal" and gui.Adornee == part and gui.Enabled and label ~= nil,
			"damage numbers: the target's running total is a DamageTotal billboard over it") then
			local edge, lip = chip:FindFirstChild("SignEdge"), chip:FindFirstChild("Lip")
			T.check(same(chip.BackgroundColor3, Sign.Stone) and edge ~= nil and lip ~= nil and same(lip.BackgroundColor3, Sign.RedLip),
				"damage numbers: the total is a stone chip with a red lip", hex(chip.BackgroundColor3))
			T.eq(label.Text, "20.6K", "damage numbers: the total reads Theme.Short (20.6K)")
			Fx.Total(u, 155372)
			T.eq(label.Text, "176K", "damage numbers: the next hit adds to the same chip (20628 + 155372 = 176K)")
			local count = 0
			for _, d in ipairs(workspace:GetDescendants()) do
				count = count + ((d:IsA("BillboardGui") and d.Name == "DamageTotal" and d.Adornee == part and d.Enabled) and 1 or 0)
			end
			T.eq(count, 1, "damage numbers: one total per target")
			Fx.UpdateNumbers(os.clock() + 5)
			T.check(not gui.Enabled, "damage numbers: the total clears after a quiet spell")
			Fx.Total(u, 100)
			T.eq(label.Text, "100", "damage numbers: a new fight starts the total afresh")
			Fx.ClearAll()
			T.check(not gui.Enabled, "damage numbers: Fx.ClearAll hides the totals too")
		end
		part:Destroy()
		-- the source: the hit handler pops through HitLook, no raw tostring(floor(dmg + 0.5)) number left
		local fh = io.open("src/client/Controllers/BattleController.lua", "r")
		local src = fh and fh:read("*a") or ""
		if fh then
			fh:close()
		end
		T.check(src ~= "" and not src:find("tostring%(floor%(dmg %+ 0%.5%)%)") and src:find("Fx.HitLook(dmg", 1, true) ~= nil,
			"damage numbers: the hit handler uses Fx.HitLook (Theme.Short), no raw damage number")
		KC.flushErrors("damage_numbers_short")
	end)

	return S
end

if (ARGS and ARGS.context or "server") == "server" then
	return serverScenarios()
end
return clientScenarios()
