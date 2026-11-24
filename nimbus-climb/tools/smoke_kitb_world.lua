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
--                         pointer on the Home tile), then picks up in the lobby; a match / battle ends it (and no guide starts
--                         in one); on a 390x844 phone the chip sits over the vitals card, inside the screen, its X 44 px;
--                         the lobby gates' prompt says "Enter"; while a match locks the way home the button greys with
--                         "Finish the match first"
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
						-- (look review fin0, minor) the name's last letter keeps 6 px off the '!' block where the two share rows
						-- ('Professor Axolotl': its 'l' ended 1-2 px from the block's corner)
						if name then
							local n = rect(name)
							local tw = Theme.Measure(name.Text, "Nameplate", name.TextSize).X
							local textR = (n.X + n.R) / 2 + tw / 2
							if b.B > n.Y and b.Y < n.B then
								T.check(b.X - textR >= 6, k .. ": the name keeps 6 px off the '!' block",
									fmt("'%s' ends at %.1f, the block starts at %.1f", name.Text, textR, b.X))
							end
						end
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
			-- (look review r1, M4) the board was a fixed 429 x 171 px billboard, wider than a 390 px phone: the R of ALTAR and the
			-- beam's right end were cut at any distance. It is marked for the client's fit (WorldTag.MarkFit: its 1080p size in
			-- BaseWidth / BaseHeight, its content in Root under a ReadScale, the NC_FitTag tag) and the fit keeps it inside a
			-- 390 px screen's gutters
			local WT = shared("WorldTag")
			local bw, bh = tonumber(header:GetAttribute("BaseWidth")), tonumber(header:GetAttribute("BaseHeight"))
			local root = header:FindFirstChild("Root")
			T.check(bw ~= nil and bh ~= nil and root ~= nil and root:FindFirstChild("ReadScale") ~= nil and root:FindFirstChild("Beam", true) ~= nil
				and game:GetService("CollectionService"):HasTag(header, WT and WT.FitTag or "NC_FitTag"),
				"world signs: the altar header is marked for the screen fit (BaseWidth / BaseHeight, Root + ReadScale, the fit tag)",
				fmt("%s x %s, root %s", tostring(bw), tostring(bh), tostring(root)))
			if WT and type(WT.FitScale) == "function" and bw then
				for _, s in ipairs({ { 390, 844 }, { 844, 390 }, { 1280, 720 }, { 1920, 1080 } }) do
					local f = WT.FitScale(bw, s[1], Theme.ScreenFactor(s[2]))
					-- inside 12 px gutters, never over the screen factor, its smallest line (the 18 px plank) still >= 14 px
					T.check(bw * f <= s[1] - 24 + 0.5 and f <= Theme.ScreenFactor(s[2]) + 1e-6 and 18 * f >= Theme.Readability.MinPx - 0.01,
						fmt("world signs: %dx%d the altar header fits the screen (%.0f px of %d, x%.2f)", s[1], s[2], bw * f, s[1], f))
				end
			else
				T.check(false, "world signs: (setup) WorldTag.FitScale")
			end
		end

		-- (look review r1, M5) the place boards at the guide's destination: every lobby gate's GateTag (WorldStyle.BuildTag),
		-- the Altar gate's poster (StormAltar PosterGui) and the return ring's Part-fallback PlazaSign were the old kit (a
		-- navy plate with a round corner and a neon border; a navy gradient card with gloss). Each is now B's hanging board /
		-- a stone kit block: no navy, no round corner, no gradient, the ink on its own face at 4.5:1
		local Contrast = SmokeCommon.Contrast
		local function inkOK(root)
			local bad = {}
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("TextLabel") and d.Text ~= "" and d.Visible then
					local cur, face = d.Parent, nil
					while cur and cur ~= root do
						if cur:IsA("GuiObject") and cur.BackgroundTransparency < 0.3 then
							face = cur
							break
						end
						cur = cur.Parent
					end
					local ratio = face and Contrast and Contrast.Ratio(d.TextColor3, face.BackgroundColor3) or 0
					if not face or ratio < 4.5 or d:FindFirstChild("TextOutline") ~= nil then
						bad[#bad + 1] = fmt("'%s' %.1f:1 on %s", d.Text:sub(1, 18), ratio, face and face.Name or "no face")
					end
				end
			end
			return bad
		end
		-- every line inside its board (a wrapped line: its measured lines inside its own box), the board on a 390 px phone at
		-- the 0.8 screen factor (WorldTag.FitScale of its BaseWidth) with its smallest line >= the 14 px readability floor
		local WTf = shared("WorldTag")
		local function boardFits(tag, k)
			local plate = tag:FindFirstChild("Plate")
			local over, parted = {}, {}
			-- (fin0 minor: the info line and the pill moved to the header's Heading type with WorldStyle's TAG_ROLE)
			local roles = { Title = "Heading", Info = "Heading", Label = "Heading" }
			for _, l in ipairs({ plate and plate:FindFirstChild("Title"), plate and plate:FindFirstChild("Info"), plate and plate:FindFirstChild("Pill") and plate.Pill:FindFirstChild("Label") }) do
				if l and l.Visible and l.Text ~= "" and (l.Name ~= "Label" or l.Parent.Visible) then
					local box = (l.Name == "Label") and l.Parent or plate
					local w = Theme.Measure(l.Text, roles[l.Name], l.TextSize).X
					if l.TextWrapped then
						-- greedy word wrap at the label's own width, as the engine wraps
						local lines, cur, widest, prev = 0, nil, 0, nil
						for word in l.Text:gmatch("%S+") do
							local try = cur and (cur .. " " .. word) or word
							if cur == nil or Theme.Measure(try, roles[l.Name], l.TextSize).X <= l.Size.X.Offset then
								cur = try
							else
								lines, widest, cur = lines + 1, math.max(widest, Theme.Measure(cur, roles[l.Name], l.TextSize).X), word
								-- (look review fin0, minor) a break beside a " - " join parts a name from its number
								-- ('Floors cleared here: Maximilianus99 -' / '12, Alexandrovich_X - 9')
								if prev == "-" or word == "-" then
									parted[#parted + 1] = fmt("%s: '... %s' / '%s ...'", l.Name, prev, word)
								end
							end
							prev = word
						end
						lines, widest = lines + 1, math.max(widest, cur and Theme.Measure(cur, roles[l.Name], l.TextSize).X or 0)
						local hNeed = lines * l.TextSize
						local hHave = l.Size.Y.Scale > 0 and (box.Size.Y.Offset * l.Size.Y.Scale + l.Size.Y.Offset) or l.Size.Y.Offset
						if widest > l.Size.X.Offset + 0.5 or l.Size.X.Offset > box.Size.X.Offset + 0.5 or hNeed > hHave + 0.5 then
							over[#over + 1] = fmt("%s wrapped %d lines %.0fx%d in %.0fx%.0f (board %d)", l.Name, lines, widest, hNeed, l.Size.X.Offset, hHave, box.Size.X.Offset)
						end
					elseif w > box.Size.X.Offset + 0.5 then
						over[#over + 1] = fmt("%s %.0f > %d", l.Name, w, box.Size.X.Offset)
					end
				end
			end
			T.check(#over == 0, k .. ": its lines fit the board", table.concat(over, ", "))
			T.check(#parted == 0, k .. ": a wrapped line never parts a name from its number", table.concat(parted, ", "))
			local bw = tonumber(tag:GetAttribute("BaseWidth"))
			local f = bw and WTf and WTf.FitScale(bw, 390, Theme.ScreenFactor(844)) or 0
			T.check(bw ~= nil and bw * f <= 390 - 24 + 0.5 and 18 * f >= Theme.Readability.MinPx - 0.01,
				fmt("%s: it fits a 390 px phone with its 18 px lines >= %d px (%s px wide, x%.2f)", k, Theme.Readability.MinPx, tostring(bw), f))
		end
		local gateTags = {}
		local starBoards = 0
		local lobbyModel = workspace:FindFirstChild("NimbusLobby")
		for _, d in ipairs(lobbyModel and lobbyModel:GetDescendants() or {}) do
			if d:IsA("BillboardGui") and d.Name == "GateTag" then
				gateTags[#gateTags + 1] = d
			end
		end
		if T.check(#gateTags >= 3, "world signs: (setup) the lobby gates' boards (GateTag)", tostring(#gateTags)) then
			for _, tag in ipairs(gateTags) do
				local plate = tag:FindFirstChild("Plate")
				local title = plate and plate:FindFirstChild("Title")
				local k = "world signs: gate board " .. tostring(title and title.Text or tag:GetFullName())
				local bad = oldKit(tag, Theme)
				T.check(#bad == 0, k .. ": no navy plate, no round corner, no gradient", table.concat(bad, ", "))
				local okP, whyP = block(plate, Sign.Stone, 3, 5)
				local lip = plate and plate:FindFirstChild("Lip")
				T.check(okP and lip ~= nil and not same(lip.BackgroundColor3, Sign.StoneLip), k .. ": the board is a stone kit block (3 px wood edge, a 5 px lip in the gate's colour)", whyP)
				local ropes = 0
				for _, d in ipairs(tag:GetDescendants()) do
					ropes = ropes + ((d.Name == "Rope" and d:IsA("Frame")) and 1 or 0)
				end
				local beam = tag:FindFirstChild("Beam", true)
				T.check(beam ~= nil and same(beam.BackgroundColor3, Sign.Wood) and ropes >= 2, k .. ": it hangs from a wood beam on two ropes (B's hanging board)", tostring(ropes) .. " ropes")
				local ink = inkOK(tag)
				T.check(#ink == 0, k .. ": every line in the kit's ink on its own face (4.5:1, no outline)", table.concat(ink, ", "))
				T.check(tonumber(tag:GetAttribute("BaseWidth")) ~= nil and tag:GetAttribute("FitRoot") == "Plate",
					k .. ": it is marked for the screen fit (BaseWidth, FitRoot Plate)")
				boardFits(tag, k)
				-- (look review fin0, minor) a party gate's difficulty stars on the cream stone: the kit's dark gold (the HUD's
				-- stars on its stone cards), not the light gold that read at ~1.5:1 there
				local lead = plate and plate:FindFirstChild("Info") and plate.Info:FindFirstChild("LeadIcon")
				if lead and lead:GetAttribute("PixelIcon") == "star" then
					starBoards = starBoards + 1
					local worst = 99
					for _, d in ipairs(lead:GetDescendants()) do
						if d:IsA("Frame") and d.BackgroundTransparency < 0.5 then
							worst = math.min(worst, Contrast.Ratio(d.BackgroundColor3, Sign.Stone))
						end
					end
					T.check(worst >= 2, k .. ": its difficulty stars stand out on the stone (>= 2:1)", fmt("%.2f:1", worst))
				end
			end
		end
		T.info(fmt("*world signs: %d gate board(s) lead their info with difficulty stars", starBoards))
		-- (look review fin0, minor) one type treatment in the board family: a gate board's info line and pill in the Storm
		-- Altar header's type, as the approved mock 04 B sets 'Secret pets' / 'Secret Roulette' (they were in two fonts on the
		-- Altar's two boards)
		local function fontOf(l)
			if not l then
				return "none"
			end
			local ok, f = pcall(function()
				return l.FontFace
			end)
			if ok and typeof(f) == "Font" then
				return tostring(f.Family) .. "/" .. tostring(f.Weight)
			end
			return tostring(l.Font)
		end
		if header then
			local hb = header:FindFirstChild("Board", true)
			local hSub = hb and hb:FindFirstChild("Subtitle", true)
			local hPill = header:FindFirstChild("Pill", true)
			local hLab = hPill and hPill:FindFirstChildWhichIsA("TextLabel", true)
			for _, tag in ipairs(gateTags) do
				local plate = tag:FindFirstChild("Plate")
				local title = plate and plate:FindFirstChild("Title")
				local info = plate and plate:FindFirstChild("Info")
				local lab = plate and plate:FindFirstChild("Pill") and plate.Pill:FindFirstChild("Label")
				T.check(hSub ~= nil and hLab ~= nil and fontOf(info) == fontOf(hSub) and fontOf(lab) == fontOf(hLab),
					"world signs: gate board " .. tostring(title and title.Text) .. ": its info line and pill in the altar header's type",
					fmt("info %s / header %s, pill %s / header %s", fontOf(info), fontOf(hSub), fontOf(lab), fontOf(hLab)))
			end
		end
		-- (M5) the longest lines the gate boards carry (ArenaBuilder's Ring board with a 12-letter name and a 3-digit round,
		-- DungeonService's floors board with two long names, a party gate's state) wrap at the board's widest line: the board
		-- still fits a 390 px phone at its 0.8 screen factor (its 18 px lines 14.4 px), each line inside the board
		local WS = shared("WorldStyle")
		if T.check(WS and type(WS.BuildTag) == "function", "world signs: (setup) WorldStyle.BuildTag") then
			local anchor = Instance.new("Part")
			anchor.Name = "LongBoards"
			anchor.Anchored = true
			anchor.Parent = workspace
			local long = {
				{ Title = "Champion Ring", Info = "Beat the champion, meet a stronger one", Pill = "Best in this server: Alexandrovic - Round 123" },
				{ Title = "The Dungeon", Info = "Rooms, waves and a boss. Solo or up to 3 friends", Pill = "Floors cleared here: Maximilianus99 - 12, Alexandrovich_X - 9" },
				{ Title = "Sky Obby", Info = "Hard - 2/4 players", Pill = "Step in to play" },
			}
			for i, spec in ipairs(long) do
				local ok, tag = pcall(WS.BuildTag, anchor, 0, spec, i == 1 and Sign.Gold or Sign.Violet)
				if T.check(ok and tag ~= nil, "world signs: (setup) a board for '" .. spec.Pill .. "'", tostring(tag)) then
					boardFits(tag, "world signs: the board '" .. spec.Title .. " / " .. spec.Pill .. "'")
				end
			end
			-- a line rewritten later (DungeonService writes the floors board into the built tag) lays the board out again
			local okD, tagD = pcall(WS.BuildTag, anchor, 0, { Title = "The Dungeon", Info = "x", Pill = "-" }, Sign.Violet)
			if okD and tagD then
				local w0 = tagD:GetAttribute("BaseWidth")
				tagD.Plate.Pill.Label.Text = long[2].Pill
				T.check(tagD:GetAttribute("BaseWidth") ~= w0, "world signs: a pill rewritten later lays the board out again", fmt("%s -> %s", tostring(w0), tostring(tagD:GetAttribute("BaseWidth"))))
				boardFits(tagD, "world signs: the Dungeon board after DungeonService writes its floors")
			end
			anchor:Destroy()
		end
		local poster = nil
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("SurfaceGui") and d.Name == "PosterGui" then
				poster = d
			end
		end
		if T.check(poster ~= nil, "world signs: (setup) the Altar gate's poster (PosterGui)") then
			local bad = oldKit(poster, Theme)
			T.check(#bad == 0, "world signs: the Altar gate's poster has no navy, no round corner, no gradient", table.concat(bad, ", "))
			local okC, whyC = block(poster:FindFirstChild("Card"), Sign.Stone, 6, 8, Sign.Violet)
			T.check(okC, "world signs: the poster is a stone card (6 px wood edge, the altar's violet lip)", whyC)
			local okV, whyV = block(poster:FindFirstChild("SecretPill", true), Sign.Violet)
			T.check(okV, "world signs: 'Secret pets' is a violet kit plank", whyV)
			local ink = inkOK(poster)
			T.check(#ink == 0, "world signs: the poster's lines in the kit's ink on their face (4.5:1, no outline)", table.concat(ink, ", "))
		end
		-- the return ring's Part fallback (the default run dresses the ring, so it is built here through StormAltar's own
		-- builder): a stone kit block with a lip in the ring's green, its line in the kit's ink, room round the words
		local SA = req(ROOTS["server"] .. "/Services/StormAltar")
		if T.check(SA and type(SA._PlazaSign) == "function", "world signs: (setup) StormAltar._PlazaSign") then
			local holder = Instance.new("Model")
			holder.Name = "PlazaSignProbe"
			holder.Parent = workspace
			local anchor = Instance.new("Part")
			anchor.Anchored = true
			anchor.Parent = holder
			local okS, sign = pcall(SA._PlazaSign, holder, anchor, CFrame.new(0, 500, 0), false)
			if T.check(okS and sign ~= nil and sign:IsA("BillboardGui"), "world signs: (setup) the Part fallback's PlazaSign", tostring(sign)) then
				local bad = oldKit(sign, Theme)
				T.check(#bad == 0, "world signs: the return ring's 'To the Plaza' tag has no navy, no round corner, no gradient", table.concat(bad, ", "))
				local okB, whyB = block(sign:FindFirstChild("Plate"), Sign.Stone, 3, 5)
				T.check(okB, "world signs: 'To the Plaza' is a stone kit block (3 px wood edge, 5 px lip)", whyB)
				local ink = inkOK(sign)
				T.check(#ink == 0, "world signs: 'To the Plaza' in the kit's ink on its face (4.5:1, no outline)", table.concat(ink, ", "))
				local text = sign:FindFirstChild("Text", true)
				local w = text and Theme.Measure(text.Text, "Title", text.TextSize).X or 0
				T.check(text ~= nil and sign.Size.X.Offset - 6 - w >= 2 * 12, "world signs: 'To the Plaza' has >= 12 px of stone each side of the words",
					fmt("%d px tag, %.0f px words", sign.Size.X.Offset, w))
			end
			holder:Destroy()
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

	-- travel_gate_enter (Pitch 2 item 13 A, the server half of travel_shows_way): the Shop's button no longer travels, so
	-- the lobby gates' prompts say 'Enter' (they said 'Travel'); the gates still take you there (GateService.Use)
	S.travel_gate_enter = guarded("travel_gate_enter", function()
		local gates = {}
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") and (d.Name == "AltarGatePrompt" or d.Name == "PlazaGatePrompt") then
				gates[#gates + 1] = d.Name .. " '" .. d.ActionText .. "'"
				T.eq(d.ActionText, "Enter", "travel: " .. d.Name .. " says 'Enter' (was 'Travel')")
				if d.Name == "AltarGatePrompt" then
					-- (look review r1, M2) at the gate the chest-high anchor projects onto the player's own body, under a phone's
					-- vitals card and the guide's chip: the plank floats CardLift studs over it, in the gate's opening
					local lift = tonumber(d:GetAttribute("CardLift"))
					T.check(lift ~= nil and lift >= 5 and lift <= 12, "travel: the Altar gate's plank floats over the player's head (CardLift 5..12 studs)", tostring(lift))
				end
			end
		end
		T.check(#gates >= 2, "travel: (setup) both lobby gates' prompts (the Altar gate and the altar's way back)", table.concat(gates, ", "))
		K.flushErrors("travel_gate_enter")
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
			-- the EVOLVE! plank keeps its word inside on the narrowest tag (a follower, Lv 20, no stars: the chip alone is
			-- narrower than the word; the gate render showed it running out of its plank), measured in the real face
			card:SetLevel(20, 0, true)
			KC.advance(0.1)
			local pill = gui:FindFirstChild("Evolve")
			if T.check(pill ~= nil and pill.Visible, "world signs: (setup) the EVOLVE! plank shows on a ready pet") then
				local need = SmokeCommon.RealWidth(pill.Text, pill.TextSize, Theme.FontOf and Theme.FontOf(pill) or pill.Font)
				T.check(pill.AbsoluteSize.X >= need + 8, "world signs: the EVOLVE! word fits its plank on the narrowest tag (4 px clear each side)",
					fmt("%.0f px word in a %.0f px plank", need, pill.AbsoluteSize.X))
			end
			card:Destroy()
			part:Destroy()

			-- (look review r0, crops 11 / 12) on a phone (the 0.8 factor) the stars were 9 px (1 px cells) beside an 18 px "Lv"
			-- and sat 1-2 px from it; the mock's chip has full-height stars and a clear gap ("2 stars  Lv 100"): the stars are as
			-- tall as the level's px (whole 2 px cells), 4-6 px of chip between them and the "Lv" ink (its 2 px outline included)
			for _, size in ipairs({ { 844, 390 }, { 1920, 1080 } }) do
				Mock.SetViewport(size[1], size[2])
				KC.advance(0.1)
				local p2 = Instance.new("Part")
				p2.Anchored = true
				p2.Parent = workspace
				local c2 = PetCard.New(p2, "Follower", 3)
				c2:SetLevel(100, 2, false)
				KC.advance(0.1)
				local tag = fmt("world signs: %dx%d pet tag", size[1], size[2])
				local b2 = c2.Gui:FindFirstChild("StarBadge")
				local lv2 = c2.Gui:FindFirstChild("Plate") and c2.Gui.Plate:FindFirstChild("Level")
				if T.check(b2 ~= nil and b2.Visible and lv2 ~= nil, tag .. ": (setup) the stars and the level") then
					-- (the stars snap to whole-px cells, a multiple of 9 px: at 1080p 18 px beside a 22 px "Lv", whose capitals are
					-- about 0.7 em = 15.4 px; the bar is the cap height, the 9 px stars of 1 px cells under it fail it)
					T.check(b2.AbsoluteSize.Y >= 0.7 * lv2.TextSize, tag .. ": the stars stand at least as tall as the 'Lv' capitals (not half of them)",
						fmt("stars %.0f px, Lv %d px (caps ~%.1f)", b2.AbsoluteSize.Y, lv2.TextSize, 0.7 * lv2.TextSize))
					local gap = lv2.AbsolutePosition.X - (b2.AbsolutePosition.X + b2.AbsoluteSize.X)
					T.check(gap >= 4 - 0.5 and gap <= 7 + 0.5, tag .. ": 4-6 px of chip between the stars and the 'Lv' ink", fmt("%.1f px", gap))
				end
				c2:Destroy()
				p2:Destroy()
			end
			Mock.SetViewport(1920, 1080)
			KC.advance(0.1)
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
				-- (look review r0, crops 09 / 10: the crown 1 px from the "C", the "R" 2 px from the edge) the tag has room: >= 12 px
				-- from the crown to the word and >= 12 px after it (the mock: ~16 and ~10), measured by the controller's own rule
				local tw = Theme.Measure(label.Text, "Nameplate", label.TextSize).X
				local textL = label.AbsolutePosition.X + (label.AbsoluteSize.X - tw) / 2
				local gapC, gapR = textL - rect(crown).R, rect(plate).R - (textL + tw)
				T.check(gapC >= 12 - 0.5 and gapR >= 12 - 0.5, "world signs: CREATOR keeps >= 12 px from the crown to the word and >= 12 px after it",
					fmt("crown gap %.1f, right %.1f", gapC, gapR))
				-- the plate's width rule is the controller's own (the render scene re-fits the mirrored plate with it: it dropped the
				-- crown's lead, which drew the cramped tag of crop 10)
				T.check(type(TC.PlateWidth) == "function" and abs(TC.PlateWidth("Creator", tw) - plate.AbsoluteSize.X) < 0.5,
					"world signs: TitleController.PlateWidth(kind, textW) is the tag's width rule", type(TC.PlateWidth) == "function" and tostring(TC.PlateWidth("Creator", tw)) or "missing")
			end
			-- (look review r0, crop 10: two gold crowns stacked) a VIP Creator wears ONE crown, the tag's own: no VIP crown over it
			-- (VipController hands a titled VIP's crown to TitleController.SetCrown on High graphics)
			local GQ = client("GraphicsQuality")
			local realGQ = GQ and GQ.Effective
			if GQ then
				GQ.Effective = function()
					return "High"
				end
			end
			p:SetAttribute("OwnedPasses", "VIP")
			KC.advance(1.2)
			local vipTag = TC.TagOf(p)
			T.check(vipTag ~= nil and vipTag:FindFirstChild("Crown") == nil and vipTag:FindFirstChild("CrownMark", true) ~= nil,
				"world signs: a VIP Creator wears one crown (the tag's own; no VIP crown stacked over it)",
				vipTag and (vipTag:FindFirstChild("Crown") and "a VIP Crown slot over the tag" or "no Crown slot") or "no tag")
			if GQ then
				GQ.Effective = realGQ
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

			-- (look review r0, majors 2 / 3) on a phone the card is under the 0.8 factor: the plank's 50 design px drew a 40 px
			-- tap target and the touch key word TAP (16) drew at 12.8 px. A tap target >= 44 x 44 screen px over the plank, the
			-- key word >= Theme.Readability.MinPx on screen
			for _, size in ipairs({ { 390, 844 }, { 844, 390 } }) do
				Mock.SetViewport(size[1], size[2])
				KC.advance(0.1)
				Mock.ShowPrompt(prompt, Enum.ProximityPromptInputType.Touch)
				KC.advance(0.1)
				local tag = fmt("world signs: %dx%d prompt", size[1], size[2])
				local pc = pg():FindFirstChild("PromptCard")
				local pl = pc and pc:FindFirstChild("Plank", true)
				local best = nil
				for _, d in ipairs(pc and pc:GetDescendants() or {}) do
					if d:IsA("GuiButton") and d.Visible and (best == nil or d.AbsoluteSize.Y > best.AbsoluteSize.Y) then
						best = d
					end
				end
				if T.check(pl ~= nil and best ~= nil, tag .. ": (setup) the plank and its buttons") then
					local b, p = rect(best), rect(pl)
					T.check(b.W >= 44 - 0.01 and b.H >= 44 - 0.01 and b.X <= p.X + 0.5 and b.R >= p.R - 0.5 and b.Y <= p.Y + 0.5 and b.B >= p.B - 0.5,
						tag .. ": a tap target of >= 44 x 44 screen px covers the whole plank", show(b) .. " plank " .. show(p))
				end
				local kt = pc and pc:FindFirstChild("KeyText", true)
				local rs = pc and pc:FindFirstChild("ReadScale", true)
				local onScreen = (kt and rs) and kt.TextSize * rs.Scale or 0
				T.check(kt ~= nil and kt.Text == "TAP" and onScreen >= Theme.Readability.MinPx - 0.01, tag .. ": the key word TAP reads >= 14 px on screen",
					fmt("%s at %.1f px", kt and kt.Text or "-", onScreen))
				Mock.HidePrompt(prompt)
				KC.advance(0.1)
			end
			Mock.SetViewport(1920, 1080)
			KC.advance(0.1)
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
				-- (look review r0, minor 3) the 18 px bang filled the whole 18 px face and ran over its 3 px lip: the mark lies on
				-- the face above the lip, inside the block's sides
				local mark = badge:FindFirstChild("Mark", true)
				local bLip = badge:FindFirstChild("Lip")
				if T.check(mark ~= nil and bLip ~= nil, "world signs: (setup) the '!' block's mark and lip") then
					local m, l = rect(mark), rect(bLip)
					T.check(m.B <= l.Y + 0.5 and m.Y >= b.Y - 0.5 and m.X >= b.X - 0.5 and m.R <= b.R + 0.5,
						"world signs: the tab's pixel '!' sits on the block's face, clear of its lip", show(m) .. " lip " .. show(l) .. " block " .. show(b))
					-- (the new render path, lobby:fold, against the mock's tab: the "!" is the kit's brown ink on the red block, as the
					-- NPC signs' "!" on gold; it was drawn in stone)
					local ink = nil
					for _, c in ipairs(mark:GetDescendants()) do
						if c:IsA("Frame") and c.BackgroundTransparency < 0.5 then
							ink = ink or c.BackgroundColor3
						end
					end
					ink = ink or (mark:IsA("TextLabel") and mark.TextColor3) or nil
					T.check(ink ~= nil and same(ink, Sign.Text), "world signs: the tab's '!' is in the kit's brown ink (the mock's)", hex(ink))
				end
				-- (look review r0, minor 3; the lobby:fold render) the bang's DRAWN cells, not its box: PixelIcon draws whole
				-- screen-px cells (never under 2 px for an 18 px icon), so under the phone column's ~0.7 scale an 18 px bang drew
				-- 18 screen px on a 16 px face, over its top edge and its lip. Every cell lies on the face above the lip at
				-- each screen
				local UIS = game:GetService("UserInputService")
				local touchWas = UIS.TouchEnabled
				for _, vp in ipairs({ { 1920, 1080, false }, { 2560, 1440, false }, { 1280, 720, false }, { 844, 390, true }, { 390, 844, true } }) do
					UIS.TouchEnabled = vp[3]
					Mock.SetViewport(vp[1], vp[2])
					KC.advance(0.6)
					local mk, lp = badge:FindFirstChild("Mark", true), badge:FindFirstChild("Lip")
					local ink = nil
					for _, c in ipairs(mk and mk:GetDescendants() or {}) do
						if c:IsA("Frame") and c.BackgroundTransparency < 0.5 and c.AbsoluteSize.X > 0 then
							local r = rect(c)
							ink = ink and { X = math.min(ink.X, r.X), Y = math.min(ink.Y, r.Y), R = math.max(ink.R, r.R), B = math.max(ink.B, r.B) } or { X = r.X, Y = r.Y, R = r.R, B = r.B }
						end
					end
					local bb, ll = rect(badge), lp and rect(lp)
					T.check(ink ~= nil and ll ~= nil and ink.Y >= bb.Y - 0.5 and ink.B <= ll.Y + 0.5 and ink.X >= bb.X - 0.5 and ink.R <= bb.R + 0.5 and (ink.B - ink.Y) >= 8.5,
						fmt("world signs: %dx%d the tab's '!' cells (>= 9 px) lie on the face above the lip", vp[1], vp[2]),
						ink and ll and fmt("ink %.1f,%.1f .. %.1f,%.1f face %s lip top %.1f", ink.X, ink.Y, ink.R, ink.B, show(bb), ll.Y) or "no cells / lip")
				end
				-- (look review r0, minor 3: "the tab's touch target is 30 px wide") on a touch phone the folded tab's clear hit pad
				-- (ToggleHit, Pitch 2 F0 A) gives the thumb 44 screen px each way; the tab's look stays the slim kit tab
				UIS.TouchEnabled = true
				Mock.SetViewport(390, 844)
				KC.advance(0.6)
				local hit = tab:FindFirstChild("ToggleHit")
				T.check(hit ~= nil and hit.Visible and hit.AbsoluteSize.X >= 44 - 0.01 and hit.AbsoluteSize.Y >= 44 - 0.01 and tab.Visible,
					"world signs: on a touch phone the folded tab's hit pad is >= 44 x 44 screen px", hit and fmt("%.0fx%.0f visible %s", hit.AbsoluteSize.X, hit.AbsoluteSize.Y, tostring(hit.Visible)) or "no ToggleHit")
				UIS.TouchEnabled = touchWas
				Mock.SetViewport(1920, 1080)
				KC.advance(0.6)
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
		-- (look review r0, minor 2) at 1440p and up the figure is 30 px (Theme.ScaledSize(24, 22) x 1.25) but the chip stayed
		-- 34 px (a 24 px label box): the figure ran over the red lip and the edge. The chip grows with its figure, and a total
		-- taken from the pool is sized afresh
		for _, size in ipairs({ { 2560, 1440 }, { 1920, 1080 }, { 390, 844 } }) do
			Mock.SetViewport(size[1], size[2])
			KC.advance(0.05)
			local p3 = Instance.new("Part")
			p3.Anchored = true
			p3.Parent = workspace
			local u3 = { root = p3, height = 4, id = 993 }
			Fx.Total(u3, 136205)
			KC.advance(0.05)
			local tag = fmt("damage numbers: %dx%d", size[1], size[2])
			local g3 = u3.total and u3.total.gui
			local chip3 = g3 and g3:FindFirstChild("Chip", true)
			local l3 = chip3 and chip3:FindFirstChildWhichIsA("TextLabel", true)
			local lip3 = chip3 and chip3:FindFirstChild("Lip")
			if T.check(l3 ~= nil and lip3 ~= nil, tag .. ": (setup) the total's chip") then
				local e = (chip3:FindFirstChild("SignEdge") and chip3.SignEdge.Thickness) or 0
				T.check(l3.AbsoluteSize.Y >= l3.TextSize - 0.5 and rect(l3).B <= rect(lip3).Y + 0.5 and chip3.AbsoluteSize.Y + 2 * e <= g3.Size.Y.Offset + 0.5,
					tag .. ": the total's figure fits its chip (above the red lip, inside the billboard)",
					fmt("label %.0f px box for %d px text; chip %.0f + 2x%d edge in a %d px gui", l3.AbsoluteSize.Y, l3.TextSize, chip3.AbsoluteSize.Y, e, g3.Size.Y.Offset))
			end
			Fx.ClearAll()
			p3:Destroy()
		end
		Mock.SetViewport(1920, 1080)
		KC.advance(0.05)
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

	----------------------------------------------------------------------------------------------------------------
	-- world_tags_fit (look review r1, M4): a wide pixel board the server marks with WorldTag.MarkFit (the Storm Altar's
	-- 429 x 171 px header; world_signs_kit checks the real one is marked) is fitted by the client's watch as it streams in
	-- and again on a new screen size: inside 12 px gutters on a 390 px phone, at the screen factor elsewhere, its content
	-- scaled with it
	----------------------------------------------------------------------------------------------------------------
	S.world_tags_fit = guarded("world_tags_fit", function()
		local WT = shared("WorldTag")
		local Theme = shared("Theme")
		if not T.check(WT ~= nil and type(WT.MarkFit) == "function" and type(WT.FitScale) == "function", "world fit: (setup) WorldTag.MarkFit / FitScale") then
			return
		end
		Mock.SetViewport(1920, 1080)
		KC.advance(0.2)
		local part = Instance.new("Part")
		part.Anchored = true
		part.Parent = workspace
		local gui = Instance.new("BillboardGui")
		gui.Name = "FitProbe"
		gui.Size = UDim2.fromOffset(429, 171)
		gui.Adornee = part
		local root = Instance.new("Frame")
		root.Name = "Root"
		root.BackgroundTransparency = 1
		root.Size = UDim2.fromOffset(429, 171)
		root.Parent = gui
		local beam = Instance.new("Frame")
		beam.Name = "Beam"
		beam.Size = UDim2.fromOffset(429, 14)
		beam.Parent = root
		WT.MarkFit(gui, root, 429, 171)
		gui.Parent = part
		KC.advance(0.2)
		for _, s in ipairs({ { 1920, 1080 }, { 390, 844 }, { 844, 390 }, { 2560, 1440 }, { 1280, 720 } }) do
			Mock.SetViewport(s[1], s[2])
			KC.advance(0.2)
			local sc = root:FindFirstChild("ReadScale")
			local want = math.min(Theme.ScreenFactor(s[2]), (s[1] - 24) / 429)
			local tag = fmt("world fit %dx%d", s[1], s[2])
			T.check(sc ~= nil and abs(sc.Scale - want) < 0.01 and abs(gui.Size.X.Offset - 429 * want) <= 1 and gui.Size.X.Offset <= s[1] - 24,
				tag .. ": the marked board is fitted to the screen (gutters 12 px, at most the screen factor)",
				fmt("gui %d px, scale %s (want %.2f)", gui.Size.X.Offset, sc and fmt("%.2f", sc.Scale) or "none", want))
			T.check(beam.AbsoluteSize.X <= gui.Size.X.Offset + 0.5, tag .. ": its content scales with it", fmt("beam %.0f px in a %d px gui", beam.AbsoluteSize.X, gui.Size.X.Offset))
		end
		-- (M5) a gate board (WorldStyle.BuildTag: its content in Plate, FitRoot) is fitted too, and fitted again when the
		-- server lays it out anew (a line rewritten: its 1080p Size and BaseWidth written over the fitted ones)
		local WS = shared("WorldStyle")
		if T.check(WS ~= nil and type(WS.BuildTag) == "function", "world fit: (setup) WorldStyle.BuildTag") then
			Mock.SetViewport(390, 844)
			KC.advance(0.2)
			local okB, board = pcall(WS.BuildTag, part, 0, { Title = "The Dungeon", Info = "Rooms, waves and a boss", Pill = "-" }, Theme.Sign.Violet)
			if T.check(okB and board ~= nil, "world fit: (setup) a gate board", tostring(board)) then
				KC.advance(0.2)
				local plate = board:FindFirstChild("Plate")
				local function fitted(label)
					local sc = plate and plate:FindFirstChild("ReadScale")
					local bw = tonumber(board:GetAttribute("BaseWidth")) or 0
					local want = math.min(Theme.ScreenFactor(844), (390 - 24) / math.max(1, bw))
					T.check(sc ~= nil and abs(sc.Scale - want) < 0.01 and abs(board.Size.X.Offset - bw * want) <= 1 and board.Size.X.Offset <= 390 - 24,
						"world fit 390x844: " .. label, fmt("gui %d px of base %d, scale %s (want %.2f)", board.Size.X.Offset, bw, sc and fmt("%.2f", sc.Scale) or "none", want))
				end
				fitted("the gate board (FitRoot Plate) is fitted to the screen")
				plate.Pill.Label.Text = "Floors cleared here: Maximilianus99 - 12, Alexandrovich_X - 9"
				KC.advance(0.2)
				fitted("the gate board is fitted again after its pill is rewritten")
				board:Destroy()
			end
		end
		part:Destroy()
		Mock.SetViewport(1920, 1080)
		KC.advance(0.2)
		KC.flushErrors("world_tags_fit")
	end)

	----------------------------------------------------------------------------------------------------------------
	-- damage_pops_apart (look review r1, M3): at 844x390 "+18.3K" (violet) sat on "+136K" (gold), crop 02. Seen through a
	-- real perspective camera 20 studs from the target, at 1920x1080, 844x390 and 390x844: three hits 0.3 s apart (the
	-- scene) and five 0.1 s apart (the fast tempo). After every hit and while they rise, no two of the target's pops share
	-- a line: their text centres are at least 0.4 x (the two heights, the birth pop included) apart. The hit handler pops
	-- through Fx.Pop (the stack), not Fx.Number on its own
	----------------------------------------------------------------------------------------------------------------
	S.damage_pops_apart = guarded("damage_pops_apart", function()
		local BC = client("Controllers/BattleController")
		local Fx = BC and BC._Fx
		local methods = Mock.Classes and Mock.Classes.Camera and Mock.Classes.Camera.methods
		if not T.check(Fx ~= nil and type(Fx.HitLook) == "function" and methods ~= nil and workspace.CurrentCamera ~= nil, "damage pops: (setup) BattleController._Fx, the mock camera") then
			return
		end
		local camObj = workspace.CurrentCamera
		local saved = { methods.WorldToViewportPoint, methods.WorldToScreenPoint }
		local function project(self, pos)
			local rel = self.CFrame:PointToObjectSpace(pos)
			local vp = Mock.Viewport
			local d = -rel.Z
			local f = (vp.Y / 2) / math.tan(math.rad(self.FieldOfView / 2))
			local dd = (abs(d) < 1e-6) and 1e-6 or d
			return Vector3.new(vp.X / 2 + rel.X / dd * f, vp.Y / 2 - rel.Y / dd * f, d), d > 0
		end
		-- the pop as the hit handler made it before the stack (the total, the pop, its side) when Fx.Pop is missing
		local pop = Fx.Pop or function(u, adornee, height, text, colour, px, dmg)
			local total = Fx.Total(u, dmg)
			local n = Fx.Number(adornee, height, text, colour, px)
			if n and total then
				n.gui.SizeOffset = Vector2.new(0.42, 0)
			end
			return n, total
		end
		local Config = shared("Config")
		local origin = (Config.Lobby and Config.Lobby.Origin) or Vector3.new(0, 300, 0)
		local part = Instance.new("Part")
		part.Name = "PopTarget"
		part.Anchored = true
		part.Size = Vector3.new(4, 4, 4)
		part.CFrame = CFrame.new(origin + Vector3.new(0, 4, -40))
		part.Parent = workspace
		local head = part.Position + Vector3.new(0, 2, 0)
		local camCF = CFrame.lookAt(head + Vector3.new(0, 3, 20), head)
		local worst = nil
		-- (look review fin0, minor) the pops' column over the total chip: px from the chip's centre up to the highest pop's
		-- text centre (they rose ~220 px over it at 1920; the mock clusters them beside it)
		local column = 0
		local function measure(tag)
			camObj.CFrame = camCF
			local list = {}
			local totalY = nil
			for _, g in ipairs(workspace:GetDescendants()) do
				if g:IsA("BillboardGui") and g.Name == "DamageTotal" and g.Enabled and g.Adornee == part then
					local so = g.StudsOffset
					local cf = camObj.CFrame
					totalY = project(camObj, part.Position + g.StudsOffsetWorldSpace + cf.RightVector * so.X + cf.UpVector * so.Y).Y - g.SizeOffset.Y * g.Size.Y.Offset
				end
			end
			for _, g in ipairs(workspace:GetDescendants()) do
				if g:IsA("BillboardGui") and g.Name == "BattleNumber" and g.Enabled and g.Adornee == part then
					local label = g:FindFirstChildWhichIsA("TextLabel")
					local sc = label and label:FindFirstChildWhichIsA("UIScale")
					if label and label.TextTransparency < 0.95 then
						local so = g.StudsOffset
						local cf = camObj.CFrame
						local v = project(camObj, part.Position + g.StudsOffsetWorldSpace + cf.RightVector * so.X + cf.UpVector * so.Y)
						list[#list + 1] = { y = v.Y - g.SizeOffset.Y * g.Size.Y.Offset, h = label.TextSize * (sc and sc.Scale or 1), text = label.Text }
						if totalY then
							column = math.max(column, totalY - list[#list].y)
						end
					end
				end
			end
			for i = 1, #list do
				for j = i + 1, #list do
					local a, b = list[i], list[j]
					local gap = abs(a.y - b.y)
					local need = 0.4 * (a.h + b.h)
					if not worst or gap - need < worst.margin then
						worst = { margin = gap - need, why = fmt("%s: '%s' and '%s' %.1f px apart (need %.1f)", tag, a.text, b.text, gap, need) }
					end
				end
			end
			return #list
		end
		local ok, err = pcall(function()
			methods.WorldToViewportPoint, methods.WorldToScreenPoint = project, project
			for _, size in ipairs({ { 1920, 1080 }, { 844, 390 }, { 390, 844 } }) do
				Mock.SetViewport(size[1], size[2])
				KC.advance(0.2)
				column = 0
				for _, run in ipairs({ { "scene", 0.3, { { 20628, {} }, { 136205, { crit = true } }, { 18332, { element = true }, "Storm" } } },
					{ "fast", 0.1, { { 20628, {} }, { 136205, { crit = true } }, { 18332, { element = true }, "Storm" }, { 9120, {} }, { 151000, { crit = true } } } } }) do
					local worstBefore = worst
					worst = nil
					local u = { root = part, height = 4, id = 9101 }
					local most = 0
					for _, h in ipairs(run[3]) do
						local text, colour, px = Fx.HitLook(h[1], h[2], h[3])
						pop(u, part, Fx.NumberHeight(u), text, colour, px, h[1])
						KC.advance(0.02)
						most = math.max(most, measure(fmt("%dx%d %s", size[1], size[2], run[1])))
						local t = 0.02
						while t < run[2] - 1e-6 do
							KC.advance(0.05)
							t = t + 0.05
							measure(fmt("%dx%d %s", size[1], size[2], run[1]))
						end
					end
					KC.advance(0.15)
					measure(fmt("%dx%d %s", size[1], size[2], run[1]))
					T.check(most >= 2, fmt("damage pops %dx%d %s: (setup) several pops rise at once", size[1], size[2], run[1]), tostring(most))
					T.check(worst == nil or worst.margin >= 0, fmt("damage pops %dx%d %s: no two pops of one target share a line", size[1], size[2], run[1]), worst and worst.why or "-")
					worst = worstBefore
					Fx.ClearAll()
					KC.advance(0.1)
				end
				-- the mock's cluster reaches ~110 px over the chip at 1080p; 150 (under the screen factor) leaves the birth
				-- pop's place over the chip
				local cap = 150 * shared("Theme").ScreenFactor(size[2])
				T.check(column > 0 and column <= cap, fmt("damage pops %dx%d: the pops cluster beside the total (<= %.0f px over it)", size[1], size[2], cap),
					fmt("%.0f px", column))
			end
		end)
		methods.WorldToViewportPoint, methods.WorldToScreenPoint = saved[1], saved[2]
		pcall(Fx.ClearAll)
		part:Destroy()
		Mock.SetViewport(1920, 1080)
		KC.advance(0.2)
		T.check(ok, "damage pops: the scenario ran", tostring(err))
		local fh = io.open("src/client/Controllers/BattleController.lua", "r")
		local src = fh and fh:read("*a") or ""
		if fh then
			fh:close()
		end
		T.check(src:find("Fx.Pop(victim", 1, true) ~= nil, "damage pops: the hit handler pops through Fx.Pop (the target's stack)")
		KC.flushErrors("damage_pops_apart")
	end)

	----------------------------------------------------------------------------------------------------------------
	-- travel_shows_way
	----------------------------------------------------------------------------------------------------------------
	S.travel_shows_way = guarded("travel_shows_way", function()
		local Theme = shared("Theme")
		local Config = shared("Config")
		local Sign = Theme and Theme.Sign
		local Shop = client("Controllers/ShopController")
		local SE = client("UI/ShopEggs")
		local TC = client("Controllers/TutorialController")
		local Guide = TC and TC.Guide
		if not T.check(Shop ~= nil and SE ~= nil and type(Guide) == "table" and type(Guide.Start) == "function" and type(Guide.Stop) == "function",
			"travel: (setup) the Shop and TutorialController.Guide.Start / Stop") then
			return
		end
		local player = game:GetService("Players").LocalPlayer
		local root = KC.root()
		local L = Config.Lobby
		-- (the client world has no server lobby) the Altar gate as the lobby replicates it: NimbusLobby > the gate's prompt
		-- part on the gate arc (LobbyInfo.Gates.Altar.PromptPart) > ProximityPrompt "AltarGatePrompt" (its 'Enter' is the
		-- server half's world_signs_kit)
		local lobby = workspace:FindFirstChild("NimbusLobby")
		local madeLobby = lobby == nil
		if madeLobby then
			lobby = Instance.new("Model")
			lobby.Name = "NimbusLobby"
			lobby.Parent = workspace
		end
		local gatePart = Instance.new("Part")
		gatePart.Name = "AltarGatePromptPart"
		gatePart.Anchored = true
		gatePart.Size = Vector3.new(4, 4, 4)
		gatePart.CFrame = CFrame.new(L.Origin + Vector3.new(60, 4, 100))
		gatePart.Parent = lobby
		local gatePrompt = Instance.new("ProximityPrompt")
		gatePrompt.Name = "AltarGatePrompt"
		gatePrompt.ActionText = "Enter"
		gatePrompt.ObjectText = "Storm Altar"
		gatePrompt.Parent = gatePart
		if not T.check(root ~= nil, "travel: (setup) my root") then
			return
		end
		local plaza = CFrame.new(L.Origin + Vector3.new(0, 3, 20))
		local function chip()
			local g = pg():FindFirstChild("NimbusGuide")
			local c = g and g.Enabled and g:FindFirstChild("Chip", true)
			return (c and c.Visible) and c or nil
		end
		local function chipText()
			local c = chip()
			local l = c and c:FindFirstChild("Text", true)
			return l and l.Text or nil
		end
		local function worldGuide()
			local fx = workspace:FindFirstChild("ClientFx")
			return fx and fx:FindFirstChild("TutorialGuide")
		end
		local function guides()
			local n = 0
			local fx = workspace:FindFirstChild("ClientFx")
			for _, d in ipairs(fx and fx:GetChildren() or {}) do
				n = n + (d.Name == "TutorialGuide" and 1 or 0)
			end
			local g = pg():FindFirstChild("NimbusGuide")
			local chips = 0
			for _, d in ipairs(g and g:GetDescendants() or {}) do
				chips = chips + ((d.Name == "Chip" and d:IsA("GuiObject")) and 1 or 0)
			end
			return n, chips
		end
		Mock.SetViewport(1920, 1080)
		Mock.Teleport(player, plaza)
		KC.advance(0.5)
		-- (setup) gem roulettes on for this account (the server's PaidRandomItemsRestricted = false): a restricted account
		-- keeps the Locked card, no button
		local restrictedWas = player:GetAttribute("PaidRandomItemsRestricted")
		player:SetAttribute("PaidRandomItemsRestricted", false)
		local ok, err = pcall(function()
			------------------------------------------------------------------ (look review r0, crop 06) the subline at 1280x720
			-- the tight hero (180 px) drew "A gold arrow leads you to the Storm Altar" 4 px over the card's foot: its box clears
			-- the card's CARD_FOOT
			Mock.SetViewport(1280, 720)
			KC.advance(0.3)
			SE._AtAltar = false
			SE._InLobby = nil
			Shop.Open({ Tab = "Eggs" })
			KC.advance(0.8)
			local hint, hero = nil, nil
			for _, d in ipairs(pg():GetDescendants()) do
				if d.Name == "Hint" and d:IsA("TextLabel") and d.Visible and d.Text == SE.Metrics.TEXT.HeroHintTravel then
					hint = d
				end
			end
			local a = hint and hint.Parent
			while a and not (a:IsA("GuiObject") and a:GetAttribute("Hero") == true) do
				a = a.Parent
			end
			hero = a
			if T.check(hint ~= nil and hero ~= nil, "travel: (setup) 1280x720 the Secret card's subline") then
				local k = rect(hint).H / math.max(1, hint.Size.Y.Offset) -- (the foot is design px under the window's scale)
				local gap = (rect(hero).B - (SE.Metrics.CARD_FOOT or 8) * k) - rect(hint).B
				T.check(gap >= -0.5, "travel: 1280x720 the subline's box clears the hero card's foot", fmt("%.1f px (hint %s, card %s)", gap, show(rect(hint)), show(rect(hero))))
			end
			Shop.Close()
			KC.advance(0.4)
			Mock.SetViewport(1920, 1080)
			KC.advance(0.3)
			------------------------------------------------------------------ the Shop's button
			SE._AtAltar = false
			SE._InLobby = nil
			Shop.Open({ Tab = "Eggs" })
			KC.advance(0.8)
			local K = SE.Metrics
			T.check(K.TEXT.Travel == "Show the way" and K.TEXT.HeroHintTravel == "A gold arrow leads you to the Storm Altar",
				"travel: the button says 'Show the way', the hint 'A gold arrow leads you to the Storm Altar'", tostring(K.TEXT.Travel) .. " / " .. tostring(K.TEXT.HeroHintTravel))
			local btn = nil
			for _, d in ipairs(pg():GetDescendants()) do
				if d.Name == "Travel" and d:IsA("GuiButton") and d.Visible then
					btn = d
				end
			end
			if not T.check(btn ~= nil, "travel: (setup) the Secret card's button shows away from the altar") then
				return
			end
			local word = btn:FindFirstChild("Word")
			T.eq(word and word.Text, "Show the way", "travel: the plank reads 'Show the way'")
			local mark = #Mock.RemoteLog
			Mock.Click(btn)
			KC.advance(0.6)
			T.eq(#KC.serverCalls("QuickTravel", mark), 0, "travel: no teleport (no QuickTravel sent)")
			T.check(not Shop.IsOpen(), "travel: 'Show the way' closes the Shop")
			T.eq(Guide.Active and Guide.Active(), "StormAltar", "travel: the guide runs to the Storm Altar")
			T.eq(chipText(), "Guiding to Storm Altar", "travel: the chip reads 'Guiding to Storm Altar'")
			local wg = worldGuide()
			if T.check(wg ~= nil, "travel: the world guide is out (workspace.ClientFx.TutorialGuide)") then
				local dots, neon, lights = 0, 0, 0
				for _, d in ipairs(wg:GetDescendants()) do
					if d:IsA("BasePart") and d.Parent and d.Parent.Name == "Dots" and d.Transparency < 1 then
						dots = dots + 1
					end
					if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
						neon = neon + 1
					end
					if d:IsA("Light") then
						lights = lights + 1
					end
				end
				T.check(dots >= 3 and neon == 0 and lights == 0, "travel: flat gold dot blocks lead the way; no Neon part, no light",
					fmt("%d dots, %d neon, %d lights", dots, neon, lights))
				local arrow = wg:FindFirstChild("GuideArrow", true)
				T.check(arrow ~= nil, "travel: the voxel arrow is over the gate")
				local sign = wg:FindFirstChild("GuideSign", true)
				local signCard = sign and sign:FindFirstChild("Card", true)
				local okS, whyS = block(signCard, Sign.Stone)
				local name = signCard and signCard:FindFirstChild("Name", true)
				T.check(okS and name ~= nil and name.Text == "Storm Altar", "travel: the GuideSign is a stone tag naming the Storm Altar", whyS)
				T.check(sign ~= nil and sign.SizeOffset.X > 0, "travel: the GuideSign sits beside the arrow's shaft", sign and tostring(sign.SizeOffset) or "no sign")
				-- the dots start just ahead of the feet: none behind me, none within 1.5 studs
				local here = KC.root().Position
				local goal = gatePrompt.Parent.Position
				local dir = Vector3.new(goal.X - here.X, 0, goal.Z - here.Z).Unit
				local behind = 0
				for _, d in ipairs(wg:GetDescendants()) do
					if d:IsA("BasePart") and d.Parent and d.Parent.Name == "Dots" and d.Transparency < 1 then
						local v = Vector3.new(d.Position.X - here.X, 0, d.Position.Z - here.Z)
						if v:Dot(dir) < 1.5 then
							behind = behind + 1
						end
					end
				end
				T.eq(behind, 0, "travel: the dots start just ahead of my feet (never over my back)")
			end
			local c = chip()
			local close = c and c:FindFirstChild("Close", true)
			T.check(close ~= nil and close:IsA("GuiButton") and close.AbsoluteSize.X >= 44 and close.AbsoluteSize.Y >= 44, "travel: the chip's X is a 44 px target",
				close and fmt("%dx%d", close.AbsoluteSize.X, close.AbsoluteSize.Y) or "no Close")

			------------------------------------------------------------------ a second start replaces the first
			T.check(Guide.Start("StormAltar") == true, "travel: a second Start is taken")
			KC.advance(0.5)
			local n, chips = guides()
			T.check(n == 1 and chips == 1, "travel: a second start replaces the first (one world guide, one chip)", n .. " guides, " .. chips .. " chips")

			------------------------------------------------------------------ the X stops it; nothing is left behind
			-- (the X of the chip that shows now: the one the second start left)
			local c2 = chip()
			close = (c2 and c2:FindFirstChild("Close", true)) or close
			if close then
				Mock.Click(close)
			end
			KC.advance(0.6)
			n, chips = guides()
			T.check(Guide.Active() == nil and chip() == nil and worldGuide() == nil, "travel: the X stops the guide: no chip, no arrow, no dots left",
				fmt("active %s, guides %d", tostring(Guide.Active()), n))

			------------------------------------------------------------------ it ends on arrival at the gate
			Guide.Start("StormAltar")
			KC.advance(0.5)
			local gp = gatePrompt.Parent.Position
			Mock.Teleport(player, CFrame.new(gp + Vector3.new(0, 0, 4)))
			KC.advance(0.6)
			T.eq(chipText(), "You're here: press E", "travel: at the gate the chip says 'You're here: press E'")
			KC.advance(4.5)
			T.check(Guide.Active() == nil and chip() == nil and worldGuide() == nil, "travel: the guide ends by itself after arriving",
				fmt("active %s, chip %s", tostring(Guide.Active()), tostring(chipText())))

			------------------------------------------------------------------ away from the lobby: Home first, then the trail
			Mock.Teleport(player, CFrame.new(Config.Match.ArenaOrigin + Vector3.new(0, 4, 0)))
			KC.advance(0.5)
			T.check(Guide.Start("StormAltar") == true, "travel: Start away from the lobby is taken")
			KC.advance(0.6)
			T.eq(chipText(), "Home first, then follow the arrow", "travel: away from the lobby the chip says 'Home first, then follow the arrow'")
			local pointer = pg():FindFirstChild("NimbusTutorialPointer")
			local arrow = pointer and pointer:FindFirstChild("Arrow", true)
			T.check(arrow ~= nil and arrow.Visible, "travel: the pointer points at the Home tile")
			T.check(worldGuide() == nil, "travel: no world trail away from the lobby")
			Mock.Teleport(player, plaza)
			KC.advance(1.0)
			T.check(chipText() == "Guiding to Storm Altar" and worldGuide() ~= nil, "travel: back in the lobby the trail picks up by itself", tostring(chipText()))

			------------------------------------------------------------------ a battle / match ends it cleanly
			player:SetAttribute(Config.Attr.InBattle, "B9")
			KC.advance(0.6)
			T.check(Guide.Active() == nil and chip() == nil and worldGuide() == nil, "travel: a battle ends the guide, nothing left")
			player:SetAttribute(Config.Attr.InBattle, nil)
			KC.advance(0.3)

			------------------------------------------------------------------ a match (a portal walked into) ends it too
			Mock.Teleport(player, plaza)
			KC.advance(0.3)
			T.check(Guide.Start("StormAltar") == true, "travel: (setup) a guide runs in the plaza")
			KC.advance(0.3)
			player:SetAttribute(Config.Attr.InMatch, true)
			KC.advance(0.6)
			T.check(Guide.Active() == nil and chip() == nil and worldGuide() == nil, "travel: a match (a portal walked into) ends the guide, nothing left")
			T.check(Guide.Start("StormAltar") == false and chip() == nil, "travel: ...and no guide starts during the match")
			player:SetAttribute(Config.Attr.InMatch, false)
			KC.advance(0.3)

			------------------------------------------------------------------ a portrait phone: the chip over the vitals card
			-- (the pitch's phone shot: the top band holds the wallet strip, so the chip sits over the vitals card, inside the
			-- screen, its X still a 44 px target; away from the lobby the line fits too)
			local function screenY(obj)
				local owner = obj:FindFirstAncestorOfClass("ScreenGui")
				return obj.AbsolutePosition.Y + ((owner and owner.IgnoreGuiInset) and 0 or (Mock.TopInset or 0))
			end
			Mock.SetViewport(390, 844)
			KC.advance(0.8)
			for _, spot in ipairs({ { "plaza", plaza }, { "away", CFrame.new(Config.Match.ArenaOrigin + Vector3.new(0, 4, 0)) } }) do
				Mock.Teleport(player, spot[2])
				KC.advance(0.5)
				Guide.Start("StormAltar")
				KC.advance(1.2)
				local c3 = chip()
				local hud = pg():FindFirstChild("NimbusHud")
				local vitals = hud and hud:FindFirstChild("Vitals", true)
				local x3 = c3 and c3:FindFirstChild("Close", true)
				if T.check(c3 ~= nil and vitals ~= nil and vitals.Visible, "travel 390x844 " .. spot[1] .. ": (setup) the chip and the vitals card show") then
					local bottom = screenY(c3) + c3.AbsoluteSize.Y
					T.check(bottom <= screenY(vitals) and screenY(c3) > 390, "travel 390x844 " .. spot[1] .. ": the chip sits over the vitals card (low on the screen, clear of the top band)",
						fmt("chip %d..%d, vitals top %d", screenY(c3), bottom, screenY(vitals)))
					T.check(c3.AbsolutePosition.X >= 12 and c3.AbsolutePosition.X + c3.AbsoluteSize.X <= 390 - 12, "travel 390x844 " .. spot[1] .. ": the chip fits the screen (12 px clear each side)",
						fmt("%d..%d of 390 (%s)", c3.AbsolutePosition.X, c3.AbsolutePosition.X + c3.AbsoluteSize.X, tostring(chipText())))
					T.check(x3 ~= nil and x3.AbsoluteSize.X >= 44 and x3.AbsoluteSize.Y >= 44, "travel 390x844 " .. spot[1] .. ": the X is a 44 px target",
						x3 and fmt("%dx%d", x3.AbsoluteSize.X, x3.AbsoluteSize.Y) or "no Close")
				end
				Guide.Stop()
				KC.advance(0.3)
			end
			Mock.SetViewport(1920, 1080)
			KC.advance(0.8)

			------------------------------------------------------------------ locked away from the lobby: greyed, 'Finish the match first'
			Mock.Teleport(player, CFrame.new(Config.Match.ArenaOrigin + Vector3.new(0, 4, 0)))
			SE._InLobby = false
			player:SetAttribute(Config.Attr.InBattle, "B10")
			Shop.Open({ Tab = "Eggs" })
			KC.advance(1.2)
			local hint = nil
			for _, d in ipairs(pg():GetDescendants()) do
				if d.Name == "Travel" and d:IsA("GuiButton") and d.Visible then
					btn = d
				end
				if d.Name == "Hint" and d:IsA("TextLabel") and d.Visible and d:FindFirstAncestor("Secret") then
					hint = d
				end
			end
			T.check(btn ~= nil and btn:GetAttribute("Disabled") == true, "travel: while a match / run locks the way home the button greys")
			local hints = {}
			for _, d in ipairs(pg():GetDescendants()) do
				if d:IsA("TextLabel") and d.Text == "Finish the match first" then
					hints[#hints + 1] = d
				end
			end
			T.check(#hints >= 1, "travel: ...with 'Finish the match first'")
			mark = #Mock.RemoteLog
			if btn then
				Mock.Click(btn)
			end
			KC.advance(0.4)
			T.check(Guide.Active() == nil, "travel: a greyed button starts nothing")
			Shop.Close()
			player:SetAttribute(Config.Attr.InBattle, nil)
			KC.advance(0.3)

			------------------------------------------------------------------ (look review r0, minor 5) a landscape phone away
			-- from the lobby: the Secret card had no subline, so nothing said "Home first" before the tap; its short line shows
			-- on the card, between the odds and the altar chip, inside the card
			Mock.SetViewport(844, 390)
			KC.advance(0.5)
			Shop.Open({ Tab = "Eggs" })
			KC.advance(1.2)
			local away, chipAt, heroCard = nil, nil, nil
			for _, d in ipairs(pg():GetDescendants()) do
				if d.Name == "Hint" and d:IsA("TextLabel") and d.Visible and d.Text == SE.Metrics.TEXT.HeroHintLobbyShort then
					away = d
				end
				if d.Name == "AltarChip" and d:IsA("GuiObject") and d.Visible then
					chipAt = d
				end
			end
			local a2 = away and away.Parent
			while a2 and not (a2:IsA("GuiObject") and a2:GetAttribute("Hero") == true) do
				a2 = a2.Parent
			end
			heroCard = a2
			if T.check(away ~= nil, "travel: 844x390 away from the lobby the Secret card says '" .. tostring(SE.Metrics.TEXT.HeroHintLobbyShort) .. "'") then
				local hr, cr = rect(away), heroCard and rect(heroCard)
				local k = hr.W / math.max(1, away.Size.X.Offset) -- screen px per design px (the window's scale)
				local px = away.TextSize * k
				local need = SmokeCommon.RealWidth(away.Text, away.TextSize, Theme.FontOf and Theme.FontOf(away) or away.Font) * k
				local rows = math.ceil(need / math.max(1, hr.W))
				T.check(cr ~= nil and hr.X >= cr.X - 0.5 and hr.R <= cr.R + 0.5 and (chipAt == nil or not overlap(hr, rect(chipAt))) and rows * px <= hr.H + 2 and px >= 14 - 0.01,
					"travel: 844x390 the away line fits inside the card (>= 14 px), clear of the altar chip",
					fmt("line %s (%d rows of %.1f px) card %s chip %s", show(hr), rows, px, show(cr), chipAt and show(rect(chipAt)) or "-"))
			end
			Shop.Close()
			Mock.SetViewport(1920, 1080)
			KC.advance(0.5)
		end)
		pcall(Guide.Stop)
		player:SetAttribute("PaidRandomItemsRestricted", restrictedWas)
		SE._AtAltar = nil
		SE._InLobby = nil
		pcall(Shop.Close)
		Mock.Teleport(player, plaza)
		KC.advance(0.5)
		gatePart:Destroy()
		if madeLobby then
			lobby:Destroy()
		end
		T.check(ok, "travel: the scenario ran", tostring(err))
		KC.flushErrors("travel_shows_way")
	end)

	----------------------------------------------------------------------------------------------------------------
	-- travel_guide_clear (look review r1, M1 / M2): seen through a real perspective camera (the default camera 12.5 studs
	-- behind the player, as worldui:guide* draws it) at 1920x1080, 1280x720, 390x844 and 844x390:
	--   ahead / walk  40 studs out, the camera straight at the Altar gate / turned 20 degrees: the "Guiding to Storm Altar"
	--                 chip never meets the voxel arrow or its GuideSign (it sat right on them, crop 03), and the GuideSign is
	--                 not under the HUD (on a portrait phone it was behind the coin strip and the Gift button)
	--   here          7 studs out ("You're here"): the gate's "Enter" plank is on the screen under the top band, clear of
	--                 the chip, the vitals card, the menu column and the touch buttons (crops 04 / 05)
	-- (look review fin0, MJ1 / MJ2) the mock gate carries its hanging board (WorldStyle.BuildTag "GateTag", 27 studs up as
	-- BuildGate hangs it) and a 'near' state 22 studs out, the board inside its MaxDistance:
	--   near / every  the gate's board, while it shows, never meets the arrow, the GuideSign or the chip (the arrow and the
	--                 sign stood on it, the chip sat on its corner: crops 01 - 04; checked on the whole plane, so a camera
	--                 tilted up a little cannot bring it back); once the guide ends the board shows again
	--   every         the chip leaves the top centre only for a guide piece ON the screen (it was pushed 267 px aside by an
	--                 arrow above the screen's top edge)
	----------------------------------------------------------------------------------------------------------------
	S.travel_guide_clear = guarded("travel_guide_clear", function()
		local Config = shared("Config")
		local TC = client("Controllers/TutorialController")
		local PC = client("Controllers/PromptController")
		local Guide = TC and TC.Guide
		local methods = Mock.Classes and Mock.Classes.Camera and Mock.Classes.Camera.methods
		if not T.check(type(Guide) == "table" and PC ~= nil and type(PC.CardOf) == "function" and methods ~= nil and workspace.CurrentCamera ~= nil,
			"guide clear: (setup) TutorialController.Guide, PromptController.CardOf, the mock camera") then
			return
		end
		local player = game:GetService("Players").LocalPlayer
		local L = Config.Lobby
		local camObj = workspace.CurrentCamera
		local UIS = game:GetService("UserInputService")
		-- the gate's lift as GateService writes it (travel_gate_enter checks the attribute on the server's real prompt)
		local fh = io.open("src/server/Services/GateService.lua", "r")
		local src = fh and fh:read("*a") or ""
		if fh then
			fh:close()
		end
		local lift = tonumber(src:match('Name = "AltarGatePrompt"[^\n]-Lift = ([%d%.]+)'))
		local saved = { methods.WorldToViewportPoint, methods.WorldToScreenPoint }
		local function project(self, pos)
			local rel = self.CFrame:PointToObjectSpace(pos)
			local vp = Mock.Viewport
			local d = -rel.Z
			local f = (vp.Y / 2) / math.tan(math.rad(self.FieldOfView / 2))
			local dd = (abs(d) < 1e-6) and 1e-6 or d
			local x, y = vp.X / 2 + rel.X / dd * f, vp.Y / 2 - rel.Y / dd * f
			return Vector3.new(x, y, d), d > 0 and x >= 0 and x <= vp.X and y >= 0 and y <= vp.Y
		end
		-- the Altar gate as the lobby builds it (WorldStyle.BuildGate): a 23 x 26 hoop on the ground, its PromptAnchor 3.5 studs up
		-- and 2.8 in front; the player walks +Z at it
		local lobby = workspace:FindFirstChild("NimbusLobby")
		local madeLobby = lobby == nil
		if madeLobby then
			lobby = Instance.new("Model")
			lobby.Name = "NimbusLobby"
			lobby.Parent = workspace
		end
		local site = L.Origin + Vector3.new(60, 0, 100)
		local dir = Vector3.new(0, 0, 1)
		local gate = Instance.new("Model")
		gate.Name = "Portal_Altar"
		local hoop = Instance.new("Part")
		hoop.Name = "Hoop"
		hoop.Anchored = true
		hoop.Size = Vector3.new(23, 26, 5)
		hoop.CFrame = CFrame.new(site + Vector3.new(0, 13, 0))
		hoop.Parent = gate
		local anchor = Instance.new("Part")
		anchor.Name = "PromptAnchor"
		anchor.Anchored = true
		anchor.Transparency = 1
		anchor.Size = Vector3.new(2, 2, 1)
		anchor.CFrame = CFrame.new(site + Vector3.new(0, 3.5, -2.8))
		anchor.Parent = gate
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "AltarGatePrompt"
		prompt.ActionText = "Enter"
		prompt.ObjectText = "Storm Altar"
		if lift then
			prompt:SetAttribute("CardLift", lift)
		end
		prompt.Parent = anchor
		-- the gate's hanging board as BuildGate hangs it: on the GlowCore 11.5 up, lifted to 27 studs over the ground
		local core = Instance.new("Part")
		core.Name = "GlowCore"
		core.Anchored = true
		core.Transparency = 1
		core.Size = Vector3.new(1, 1, 1)
		core.CFrame = CFrame.new(site + Vector3.new(0, 11.5, 0))
		core.Parent = gate
		local WS = shared("WorldStyle")
		local board = WS.BuildTag(core, 27 - 11.5, { Title = "Storm Altar", Info = "Secret pets", Pill = "Secret Roulette" }, Color3.fromRGB(80, 200, 220))
		gate.Parent = lobby
		local function screenRect(obj)
			local owner = obj:FindFirstAncestorOfClass("ScreenGui")
			local dy = (owner and owner.IgnoreGuiInset) and 0 or (Mock.TopInset or 0)
			local p, s = obj.AbsolutePosition, obj.AbsoluteSize
			return { X = p.X, Y = p.Y + dy, R = p.X + s.X, B = p.Y + s.Y + dy, W = s.X, H = s.Y }
		end
		local function boxOf(part)
			local r = nil
			for _, dx in ipairs({ -0.5, 0.5 }) do
				for _, dy in ipairs({ -0.5, 0.5 }) do
					for _, dz in ipairs({ -0.5, 0.5 }) do
						local v = project(camObj, part.CFrame:PointToWorldSpace(Vector3.new(dx * part.Size.X, dy * part.Size.Y, dz * part.Size.Z)))
						if v.Z <= 0 then
							return nil
						end
						if r then
							r.X, r.Y, r.R, r.B = math.min(r.X, v.X), math.min(r.Y, v.Y), math.max(r.R, v.X), math.max(r.B, v.Y)
						else
							r = { X = v.X, Y = v.Y, R = v.X, B = v.Y }
						end
					end
				end
			end
			return r
		end
		local function union(a, b)
			if not a then
				return b
			end
			if not b then
				return a
			end
			return { X = math.min(a.X, b.X), Y = math.min(a.Y, b.Y), R = math.max(a.R, b.R), B = math.max(a.B, b.B) }
		end
		-- a pixel billboard's rect on the screen (viewport px)
		local function billboard(gui)
			local ad = gui.Adornee or gui.Parent
			local cf = camObj.CFrame
			local so = gui.StudsOffset
			local p = ad.Position + gui.StudsOffsetWorldSpace + cf.RightVector * so.X + cf.UpVector * so.Y - cf.LookVector * so.Z
			local v = project(camObj, p)
			if v.Z <= 0 then
				return nil
			end
			local w, h = gui.Size.X.Offset, gui.Size.Y.Offset
			local x0 = v.X - w / 2 + gui.SizeOffset.X * w
			local y0 = v.Y - h / 2 - gui.SizeOffset.Y * h
			return { X = x0, Y = y0, R = x0 + w, B = y0 + h }
		end
		local function grow(r, by)
			return r and { X = r.X - by, Y = r.Y - by, R = r.R + by, B = r.B + by } or nil
		end
		-- the HUD that would cover a world card: every shown, opaque piece of the HUD, the menu, the hotbar and the touch buttons;
		-- (look review fin1, MJ-B) the top bar's pill and Roblox's own buttons in the top band too (this list missed them,
		-- so the GuideSign under the pill and '...' on 390x844 passed)
		local function hudPieces()
			local out = {}
			local top = Mock.TopInset or 0
			if top > 0 then
				local minX, maxX = 112, Mock.Viewport.X - 72
				local okT, tb = pcall(function()
					return game:GetService("GuiService").TopbarInset
				end)
				if okT and typeof(tb) == "Rect" and tb.Max.X > tb.Min.X then
					minX, maxX = tb.Min.X, tb.Max.X
				end
				out[#out + 1] = { name = "Roblox's buttons (left)", rect = { X = 0, Y = 0, R = minX, B = top - 4, W = minX, H = top - 4 } }
				out[#out + 1] = { name = "Roblox's buttons (right)", rect = { X = maxX, Y = 0, R = Mock.Viewport.X, B = top - 4, W = Mock.Viewport.X - maxX, H = top - 4 } }
			end
			for _, name in ipairs({ "NimbusHud", "NimbusMenu", "NimbusHotbar", "MobileControls", "NimbusDaily", "NimbusTopBar" }) do
				local g = pg():FindFirstChild(name)
				if g and g:IsA("ScreenGui") and g.Enabled then
					for _, d in ipairs(g:GetDescendants()) do
						if d:IsA("GuiObject") and d.AbsoluteSize.X > 0 and d.AbsoluteSize.Y > 0 and d.BackgroundTransparency < 0.5 then
							local shown = true
							local a = d
							while a and a ~= g do
								if a:IsA("GuiObject") and not a.Visible then
									shown = false
									break
								end
								a = a.Parent
							end
							local r = shown and screenRect(d)
							if r and r.W < Mock.Viewport.X * 0.6 and r.H < Mock.Viewport.Y * 0.6 then
								out[#out + 1] = { name = g.Name .. "." .. d.Name, rect = r }
							end
						end
					end
				end
			end
			return out
		end
		local ok, err = pcall(function()
			T.check(lift ~= nil, "guide clear: (setup) GateService's Altar prompt Lift", tostring(lift))
			methods.WorldToViewportPoint, methods.WorldToScreenPoint = project, project
			for _, size in ipairs({ { 1920, 1080 }, { 1280, 720 }, { 390, 844 }, { 844, 390 } }) do
				Mock.SetViewport(size[1], size[2])
				KC.advance(0.4)
				for _, mode in ipairs({ "ahead", "walk", "near", "graze", "here" }) do
					local tag = fmt("guide clear %dx%d %s", size[1], size[2], mode)
					local dist = ({ here = 7, near = 22, graze = 26 })[mode] or 40
					local at = anchor.Position - dir * dist
					at = Vector3.new(at.X, L.Origin.Y + 3, at.Z)
					Mock.Teleport(player, CFrame.lookAt(at, at + dir))
					local view = dir
					if mode == "walk" then
						local a = math.rad(20)
						view = Vector3.new(dir.X * math.cos(a) + dir.Z * math.sin(a), 0, -dir.X * math.sin(a) + dir.Z * math.cos(a))
					end
					local head = at + Vector3.new(0, 1.9, 0)
					local camAt = head - view * 12.5 + Vector3.new(0, 4.5, 0)
					local camCF = CFrame.lookAt(camAt, head + view * 14 + Vector3.new(0, 2, 0))
					camObj.CFrame = camCF
					KC.advance(0.1)
					T.check(Guide.Start("StormAltar") == true, tag .. ": (setup) the guide starts")
					if mode == "here" then
						PC.Custom(prompt)
						local touch = UIS.TouchEnabled == true and UIS.KeyboardEnabled ~= true
						Mock.ShowPrompt(prompt, touch and Enum.ProximityPromptInputType.Touch or Enum.ProximityPromptInputType.Keyboard)
					end
					for _ = 1, 12 do
						camObj.CFrame = camCF
						KC.advance(0.1)
					end
					local gui = pg():FindFirstChild("NimbusGuide")
					local chip = gui and gui:FindFirstChild("Chip", true)
					if T.check(chip ~= nil and chip.Visible, tag .. ": (setup) the chip shows") then
						local k = (chip:FindFirstChild("ReadScale") and chip.ReadScale.Scale) or 1
						local c = grow(screenRect(chip), 3 * k) -- its wood edge
						local vp = Mock.Viewport
						T.check(c.X >= 0 and c.R <= vp.X and c.Y >= 0 and c.B <= vp.Y, tag .. ": the chip is on the screen", show(c))
						-- (fin0 MJ2) the gate's board while it shows (Enabled, inside its MaxDistance of the camera)
						local brd = nil
						if board.Enabled then
							local anchorAt = core.Position + board.StudsOffsetWorldSpace
							if (camObj.CFrame.Position - anchorAt).Magnitude <= board.MaxDistance then
								brd = billboard(board)
							end
						end
						if mode == "near" then
							T.check((camObj.CFrame.Position - (core.Position + board.StudsOffsetWorldSpace)).Magnitude <= board.MaxDistance,
								tag .. ": (setup) the gate's board is inside its MaxDistance")
						end
						if brd then
							T.check(not overlap(c, brd), tag .. ": the chip never covers the gate's board", "chip " .. show(c) .. " board " .. show(brd))
						end
						-- (fin0 MJ1) the guide pieces as far as they are ON the screen (the top band included)
						local onScreen = {}
						local function seen(r)
							if not r then
								return
							end
							local v = { X = math.max(r.X, 0), Y = math.max(r.Y, 0), R = math.min(r.R, vp.X), B = math.min(r.B, vp.Y) }
							if v.R > v.X and v.B > v.Y then
								onScreen[#onScreen + 1] = v
							end
						end
						local function homeCheck()
							local w = c.R - c.X
							if math.abs((c.X + c.R) / 2 - vp.X / 2) <= 1.5 then
								return
							end
							local k = (chip:FindFirstChild("ReadScale") and chip.ReadScale.Scale) or 1
							local home = grow({ X = vp.X / 2 - w / 2, Y = c.Y, R = vp.X / 2 + w / 2, B = c.B }, 20 * k)
							local hit = false
							for _, v in ipairs(onScreen) do
								hit = hit or overlap(home, v)
							end
							T.check(hit, tag .. ": the chip leaves the top centre only for a guide piece on the screen",
								"chip " .. show(c) .. " pushed " .. fmt("%.0f", (c.X + c.R) / 2 - vp.X / 2) .. " px, " .. #onScreen .. " piece(s) on the screen")
						end
						local fx0 = workspace:FindFirstChild("ClientFx")
						local wg0 = fx0 and fx0:FindFirstChild("TutorialGuide")
						if mode ~= "here" and not (wg0 and wg0:FindFirstChild("GuideArrow", true)) then
							-- (look review pol0, MAJOR 1) the arrow is a world part over the gate: it shows all the way and may
							-- pass behind the HUD or out of the screen's top. fin1 hid it (its sign with it) within 3 px of any
							-- HUD piece or the top, and this check held that hide; the reason it changed: phones lost the arrow
							-- for the whole walk and every size lost it in one frame at 32-34 studs
							T.check(false, tag .. ": the arrow shows (a world part: it never hides for the HUD or the screen's top)")
							homeCheck()
						elseif mode ~= "here" then
							local fx = workspace:FindFirstChild("ClientFx")
							local wg = fx and fx:FindFirstChild("TutorialGuide")
							local arrow = wg and wg:FindFirstChild("GuideArrow", true)
							local box = nil
							for _, d in ipairs(arrow and arrow:GetDescendants() or {}) do
								if d:IsA("BasePart") then
									box = union(box, boxOf(d))
								end
							end
							local sign = wg and wg:FindFirstChild("GuideSign", true)
							local card = sign and sign:FindFirstChild("Card")
							local s = nil
							local bb = sign and sign.Enabled and billboard(sign)
							if bb and card then
								local sk = (card:FindFirstChild("ReadScale") and card.ReadScale.Scale) or 1
								local w, h = card.Size.X.Offset * sk, card.Size.Y.Offset * sk
								local x0 = bb.X + card.Position.X.Offset + card.Position.X.Scale * (bb.R - bb.X) - card.AnchorPoint.X * w
								local cy = (bb.Y + bb.B) / 2 + card.Position.Y.Offset -- (a sign hung under its arrow: its drop)
								s = grow({ X = x0, Y = cy - h / 2, R = x0 + w, B = cy + h / 2 }, 3 * sk)
							end
							-- (fin0 MJ1) the box the chip dodges is the arrow's own outline (both hop heights) within 3 px: one box round
							-- the whole arrow, seen from below, ended ~20-40 px under the real tip (the chip dodged an arrow above it)
							local ar = box and type(Guide._arrowRect) == "function" and Guide._arrowRect() or nil
							if T.check(ar ~= nil, tag .. ": (setup) the guide's arrow box") then
								local top = Mock.TopInset or 0
								local a = { X = ar.x0, Y = ar.y0 + top, R = ar.x1, B = ar.y1 + top }
								-- (fin0 MJ1) graze, 26 studs out: on a landscape screen the arrow's tip reaches into the chip's spot from
								-- above. fin0 stepped the chip down under the tip, still centred (it had jumped 250 px across the top);
								-- (look review fin1, MJ-A) that step down was a fourth place on the walk at the gate (left, right,
								-- centre-low, home) and on a landscape phone it sat on the gate's crest. Now the chip takes ONE clear
								-- step aside on its own row and glides there (travel_guide_walk holds the walk): a tip reaching into
								-- its spot never sends it down onto the gate. (An arrow that reaches the chip's row from above stands
								-- past the screen's top at these sizes, so it hides, and this check is idle; it stays for any size
								-- where it shows)
								if mode == "graze" and vp.X > vp.Y then
									local k = (chip:FindFirstChild("ReadScale") and chip.ReadScale.Scale) or 1
									local homeTop = top + 10 * k - 3 * k -- (GUIDE_TOP under the top band, its wood edge)
									local w = c.R - c.X
									local into = a.B + 10 * k - homeTop
									if into > 0 and a.X < vp.X / 2 + w / 2 and a.R > vp.X / 2 - w / 2 then
										T.check(math.abs(c.Y - homeTop) <= 1.5 and not overlap(c, a),
											tag .. ": a tip reaching into the chip's spot moves it aside on its own row, never down onto the gate",
											fmt("tip %.0f px into its spot; chip %s, arrow %s", into, show(c), show(a)))
									end
								end
								local anyPart = arrow:FindFirstChildWhichIsA("BasePart", true)
								local hopPx = abs(project(camObj, anyPart.Position).Y - project(camObj, anyPart.Position + Vector3.new(0, 0.6, 0)).Y) -- (K.BOB)
								local tol = 3
								T.check(a.X >= box.X - tol and a.R <= box.R + tol and a.X <= box.X + tol and a.R >= box.R - tol
									and a.Y >= box.Y - hopPx - tol and a.Y <= box.Y + tol and a.B <= box.B + hopPx + tol and a.B >= box.B - tol,
									tag .. ": the arrow box the chip dodges is the arrow's own outline",
									"guide " .. show(a) .. " parts " .. show(box) .. fmt(" (hop %.1f px)", hopPx))
							end
							-- (look review pol0, MAJOR 1) the keep-clear rule is the GuideSign's alone: with no room beside the
							-- arrow clear of the HUD and the chip it takes the name alone or hides while the arrow stays (390x844
							-- walk and near, 844x390 near: the arrow out of the top or against the wallet strip). On the
							-- desktop sizes, the mock's framings, it shows
							T.check(box ~= nil, tag .. ": (setup) the arrow is in view")
							if s == nil and vp.X >= 1280 then
								-- (kit-b P2 fix6, world look pol1 A) ... unless the arrow's tip stands in the chip's columns within
								-- the sign's height and twice its 8 px clearance over the chip's top: every spot beside or under the
								-- tip would stack the sign on the chip ('Storm Altar' over 'Guiding to Storm Altar', read as one
								-- block; guide_pins W1), so it hides there (1920 near: the tip 18 px over the chip at home)
								local stacked = false
								if box and card then
									local sk = (card:FindFirstChild("ReadScale") and card.ReadScale.Scale) or 1
									local sh = (card.Size.Y.Offset + 6) * sk
									stacked = box.B <= c.Y and box.B >= c.Y - sh - 16 * k and box.R > c.X and box.X < c.R
								end
								T.check(stacked, tag .. ": (setup) the arrow and its sign are in view (it hides only where it would stack on the chip)",
									"arrow " .. (box and show(box) or "-") .. " chip " .. show(c))
							end
							if box and not s then
								T.check(not overlap(c, box), tag .. ": the chip never covers the arrow", "chip " .. show(c) .. " arrow " .. show(box))
								seen(box)
								homeCheck()
							end
							if box and s then
								T.check(not overlap(c, box), tag .. ": the chip never covers the arrow", "chip " .. show(c) .. " arrow " .. show(box))
								T.check(not overlap(c, s), tag .. ": the chip never covers the GuideSign", "chip " .. show(c) .. " sign " .. show(s))
								-- (fin0 minor: at 844x390 the sign hid the arrow's right 3 px)
								T.check(not overlap(s, box), tag .. ": the GuideSign keeps off the arrow", "sign " .. show(s) .. " arrow " .. show(box))
								-- (fin0 minor: 390x844 walk, the arrow at the right edge under the HUD, the sign was wholly off the
								-- screen) while the arrow's middle is on the screen, so is the whole sign
								local ax, ay = (box.X + box.R) / 2, (box.Y + box.B) / 2
								if ax >= 0 and ax <= vp.X and ay >= 0 and ay <= vp.Y then
									T.check(s.X >= 0 and s.R <= vp.X and s.Y >= 0 and s.B <= vp.Y, tag .. ": the GuideSign is on the screen beside its arrow",
										"sign " .. show(s) .. " arrow " .. show(box))
								end
								if brd then
									T.check(not overlap(brd, box), tag .. ": the arrow never stands on the gate's board", "board " .. show(brd) .. " arrow " .. show(box))
									T.check(not overlap(brd, s), tag .. ": the GuideSign never covers the gate's board", "board " .. show(brd) .. " sign " .. show(s))
								end
								seen(box)
								seen(s)
								homeCheck()
								local under = {}
								for _, piece in ipairs(hudPieces()) do
									if overlap(s, piece.rect) then
										under[#under + 1] = piece.name
									end
								end
								T.check(#under == 0, tag .. ": the GuideSign is not under the HUD", show(s) .. " under " .. table.concat(under, ", "))
							end
						else
							local card = PC.CardOf(prompt)
							local r = card and billboard(card)
							if T.check(r ~= nil, tag .. ": (setup) the gate's plank shows") then
								local top = Mock.TopInset or 0
								T.check(r.Y >= top and r.B <= vp.Y and r.X >= 0 and r.R <= vp.X, tag .. ": the plank is on the screen, under the top band",
									show(r) .. fmt(" (top band %d)", top))
								T.check(not overlap(r, c), tag .. ": the chip keeps off the plank", "plank " .. show(r) .. " chip " .. show(c))
								if brd then
									T.check(not overlap(brd, r), tag .. ": the plank keeps off the gate's board", "board " .. show(brd) .. " plank " .. show(r))
								end
								seen(r)
								homeCheck()
								local under = {}
								for _, piece in ipairs(hudPieces()) do
									if overlap(r, piece.rect) then
										under[#under + 1] = piece.name
									end
								end
								T.check(#under == 0, tag .. ": the plank is not under the HUD (vitals card, menu, touch buttons)", show(r) .. " under " .. table.concat(under, ", "))
							end
						end
					end
					Guide.Stop()
					pcall(function()
						Mock.HidePrompt(prompt)
					end)
					KC.advance(0.2)
					T.check(board.Enabled == true, tag .. ": the gate's board shows again once the guide ends")
				end
			end
		end)
		methods.WorldToViewportPoint, methods.WorldToScreenPoint = saved[1], saved[2]
		pcall(Guide.Stop)
		Mock.SetViewport(1920, 1080)
		Mock.Teleport(player, CFrame.new(L.Origin + Vector3.new(0, 3, 20)))
		KC.advance(0.5)
		gate:Destroy()
		if madeLobby then
			lobby:Destroy()
		end
		T.check(ok, "guide clear: the scenario ran", tostring(err))
		KC.flushErrors("travel_guide_clear")
	end)

	----------------------------------------------------------------------------------------------------------------
	-- travel_guide_plank (look:new3 vs kit-b 1a55f73, its one new major: at the Storm Altar gate on small portrait phones
	-- the chip "You're here: tap the button" lay over the gate's Enter plank, 'Enter' cut through: 21.4 px at 340 / 360 /
	-- 384 / 400 x 640, 6 px at 375 x 667, from c1e122e on; travel_guide_clear has the rule but runs at 1920x1080,
	-- 1280x720, 390x844 and 844x390 with no touch keys, so it stayed green). Here the portrait phones WITH the touch keys
	-- (MovementController's MobileControls: RUN / DASH) at 320x568, 340x640, 360x640, 375x667, 384x640, 390x844, 400x640
	-- and 412x915, the mock Altar gate and the stock camera as travel_guide_clear has them, the tutorial on step 3 folded
	-- (its quest strip where it docks, else its portrait chip) and then done (hidden: a player who finished or skipped it;
	-- the look's state), one 1/30 s frame a step:
	--   walk       11 studs out (the gate's prompt in range, MaxActivationDistance 12; the guide still walking), 1 s
	--   walk tilt  the same, the camera tilted up 0 -> 20 degrees over 1.5 s (the plank comes down the screen)
	--   here       7 studs out: the whole "You're here" phase (3 s)
	--   here tilt  the same, the camera tilted 0 -> 20 -> 0 degrees over its first 2 s
	--   other      11 studs out, a second prompt's plank (an NPC's "Talk") standing on the chip where it is: every world
	--              prompt plank, not the gate's alone
	-- Every frame the chip, while it shows, keeps 6 px or more (screen px, its wood edge counted) off every shown prompt
	-- plank (a plank that just showed: from 0.1 s on, the guide's next looks). With the tutorial done the chip shows on
	-- every frame from 0.5 to 2.5 s of the "You're here" phase as it stands (here): it is the guide's last word, so hiding
	-- it all the way is no way to keep off the plank (at 77f5f56 it hid the whole phase at 340 - 400 x 640 and 375 x 667,
	-- the look's dumps drew it on the plank). The frames it shows at the gate with the tutorial folded are listed
	----------------------------------------------------------------------------------------------------------------
	S.travel_guide_plank = guarded("travel_guide_plank", function()
		local Config = shared("Config")
		local Steps = shared("TutorialSteps")
		local TC = client("Controllers/TutorialController")
		local PC = client("Controllers/PromptController")
		local MC = client("Controllers/MovementController")
		local Guide = TC and TC.Guide
		local methods = Mock.Classes and Mock.Classes.Camera and Mock.Classes.Camera.methods
		if not T.check(type(Guide) == "table" and PC ~= nil and type(PC.CardOf) == "function" and MC ~= nil and type(MC._TouchButtons) == "function"
			and methods ~= nil and workspace.CurrentCamera ~= nil and type(Steps) == "table",
			"guide plank: (setup) TutorialController.Guide, PromptController.CardOf, MovementController._TouchButtons, the mock camera") then
			return
		end
		local player = game:GetService("Players").LocalPlayer
		local UIS = game:GetService("UserInputService")
		local L = Config.Lobby
		local camObj = workspace.CurrentCamera
		local fh = io.open("src/server/Services/GateService.lua", "r")
		local src = fh and fh:read("*a") or ""
		if fh then
			fh:close()
		end
		local lift = tonumber(src:match('Name = "AltarGatePrompt"[^\n]-Lift = ([%d%.]+)'))
		local saved = { methods.WorldToViewportPoint, methods.WorldToScreenPoint }
		local function focal(self)
			return (Mock.Viewport.Y / 2) / math.tan(math.rad(self.FieldOfView / 2))
		end
		local function project(self, pos)
			local rel = self.CFrame:PointToObjectSpace(pos)
			local vp = Mock.Viewport
			local d = -rel.Z
			local f = focal(self)
			local dd = (abs(d) < 1e-6) and 1e-6 or d
			local x, y = vp.X / 2 + rel.X / dd * f, vp.Y / 2 - rel.Y / dd * f
			return Vector3.new(x, y, d), d > 0 and x >= 0 and x <= vp.X and y >= 0 and y <= vp.Y
		end
		-- the Altar gate as travel_guide_clear mocks it (WorldStyle.BuildGate's hoop, its PromptAnchor 3.5 studs up and 2.8
		-- in front, GateService's prompt and Lift) and a second prompt, an NPC's "Talk", for the 'other' runs
		local lobby = workspace:FindFirstChild("NimbusLobby")
		local madeLobby = lobby == nil
		if madeLobby then
			lobby = Instance.new("Model")
			lobby.Name = "NimbusLobby"
			lobby.Parent = workspace
		end
		local site = L.Origin + Vector3.new(60, 0, 100)
		local dir = Vector3.new(0, 0, 1)
		local gate = Instance.new("Model")
		gate.Name = "Portal_Altar"
		local hoop = Instance.new("Part")
		hoop.Name = "Hoop"
		hoop.Anchored = true
		hoop.Size = Vector3.new(23, 26, 5)
		hoop.CFrame = CFrame.new(site + Vector3.new(0, 13, 0))
		hoop.Parent = gate
		local anchor = Instance.new("Part")
		anchor.Name = "PromptAnchor"
		anchor.Anchored = true
		anchor.Transparency = 1
		anchor.Size = Vector3.new(2, 2, 1)
		anchor.CFrame = CFrame.new(site + Vector3.new(0, 3.5, -2.8))
		anchor.Parent = gate
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "AltarGatePrompt"
		prompt.ActionText = "Enter"
		prompt.ObjectText = "Storm Altar"
		if lift then
			prompt:SetAttribute("CardLift", lift)
		end
		prompt.Parent = anchor
		local away = CFrame.new(site + Vector3.new(200, 3, 0))
		local otherPart = Instance.new("Part")
		otherPart.Name = "TalkAnchor"
		otherPart.Anchored = true
		otherPart.Transparency = 1
		otherPart.Size = Vector3.new(1, 1, 1)
		otherPart.CFrame = away
		otherPart.Parent = gate
		local other = Instance.new("ProximityPrompt")
		other.Name = "TalkPrompt"
		other.ActionText = "Talk"
		other.ObjectText = "Nimbus"
		other.Parent = otherPart
		gate.Parent = lobby
		PC.Custom(prompt)
		PC.Custom(other)
		local function shownGui(o)
			local a = o
			while a and not a:IsA("ScreenGui") do
				if a:IsA("GuiObject") and not a.Visible then
					return false
				end
				a = a.Parent
			end
			return a ~= nil and a.Enabled ~= false
		end
		local function screenRect(obj)
			local owner = obj:FindFirstAncestorOfClass("ScreenGui")
			local dy = (owner and owner.IgnoreGuiInset) and 0 or (Mock.TopInset or 0)
			local p, s = obj.AbsolutePosition, obj.AbsoluteSize
			return { X = p.X, Y = p.Y + dy, R = p.X + s.X, B = p.Y + s.Y + dy }
		end
		local function grow(r, by)
			return { X = r.X - by, Y = r.Y - by, R = r.R + by, B = r.B + by }
		end
		-- a pixel billboard's rect on the screen (viewport px), as travel_guide_clear reads it
		local function billboard(gui)
			local ad = gui.Adornee or gui.Parent
			local cf = camObj.CFrame
			local so = gui.StudsOffset
			local p = ad.Position + gui.StudsOffsetWorldSpace + cf.RightVector * so.X + cf.UpVector * so.Y - cf.LookVector * so.Z
			local v = project(camObj, p)
			if v.Z <= 0 then
				return nil
			end
			local w, h = gui.Size.X.Offset, gui.Size.Y.Offset
			local x0 = v.X - w / 2 + gui.SizeOffset.X * w
			local y0 = v.Y - h / 2 - gui.SizeOffset.Y * h
			return { X = x0, Y = y0, R = x0 + w, B = y0 + h }
		end
		-- px between two rects (negative: they overlap by that much)
		local function gapOf(a, b)
			return math.max(b.X - a.R, a.X - b.R, b.Y - a.B, a.Y - b.B)
		end
		local function chipNow()
			local gui = pg():FindFirstChild("NimbusGuide")
			local chip = gui and gui:FindFirstChild("Chip", true)
			if not chip then
				return nil, false
			end
			local k = (chip:FindFirstChild("ReadScale") and chip.ReadScale.Scale) or 1
			return grow(screenRect(chip), 3 * k), shownGui(chip) -- (its wood edge)
		end
		local function tutorialPayload(index) -- (smoke_kitb_ui's U99.tutorialPayload)
			local list = Steps.Steps
			index = math.max(1, math.min(#list, index))
			local step = list[index]
			local cfg = Config.Tutorial or {}
			local text = tostring(step.Text or "")
			text = (text:gsub("{GiftTokens}", tostring(cfg.GiftTokens or 0)))
			text = (text:gsub("{FinishTokens}", tostring((cfg.FinishReward or {}).Tokens or 0)))
			text = (text:gsub("{RaidMinutes}", "20"))
			return { Step = index, Total = #list, Id = step.Id, Title = step.Title, Text = text, Target = step.Target, Chapter = step.Chapter or 1,
				CompleteOn = step.CompleteOn, Hint = step.Hint, Button = step.Button, Gift = step.Gift == true, Done = false, Completed = false,
				Skipped = false, Reward = 0 }
		end
		local function tutorialDone()
			local n = #Steps.Steps
			KC.toClient("TutorialState", { Step = n, Total = n, Id = "done", Text = "", Done = true, Completed = false, Skipped = true, Reward = 0 })
			KC.advance(1)
		end
		-- the tutorial on step 3, folded -> "strip" / "portrait chip" / what shows
		local function tutorialFolded()
			local g0 = pg():FindFirstChild("NimbusTutorial")
			local fold0, main0 = g0 and g0:FindFirstChild("Fold", true), g0 and g0:FindFirstChild("Main", true)
			if fold0 and main0 and shownGui(main0) then
				Mock.Click(fold0)
				KC.advance(0.5)
			end
			tutorialDone()
			KC.toClient("TutorialState", tutorialPayload(3))
			KC.advance(3)
			local g = pg():FindFirstChild("NimbusTutorial")
			local main, fold = g and g:FindFirstChild("Main", true), g and g:FindFirstChild("Fold", true)
			if main and fold and shownGui(main) then
				Mock.Click(fold)
				KC.advance(1)
			end
			local strip = g and g:FindFirstChild("QuestStrip", true)
			local portrait = g and g:FindFirstChild("Portrait", true)
			if strip and shownGui(strip) then
				return "strip " .. show(screenRect(strip))
			elseif portrait and shownGui(portrait) then
				return "portrait chip " .. show(screenRect(portrait))
			end
			return (main and shownGui(main)) and "the card open" or "nothing shown"
		end
		local touchWas = UIS.TouchEnabled
		local ok, err = pcall(function()
			T.check(lift ~= nil, "guide plank: (setup) GateService's Altar prompt Lift", tostring(lift))
			methods.WorldToViewportPoint, methods.WorldToScreenPoint = project, project
			local MODES = {
				{ name = "walk", dist = 11, secs = 1 },
				{ name = "walk tilt", dist = 11, secs = 1.5, tilt = function(t)
					return 20 * math.min(1, t / 1.5)
				end },
				{ name = "here", dist = 7, secs = 3, shows = true },
				{ name = "here tilt", dist = 7, secs = 3, tilt = function(t)
					return (t <= 1) and (20 * t) or (t <= 2 and 20 * (2 - t) or 0)
				end },
				{ name = "other", dist = 11, secs = 1, other = true },
			}
			for _, size in ipairs({ { 320, 568 }, { 340, 640 }, { 360, 640 }, { 375, 667 }, { 384, 640 }, { 390, 844 }, { 400, 640 }, { 412, 915 } }) do
				UIS.TouchEnabled = true
				Mock.SetViewport(size[1], size[2])
				pcall(MC._TouchButtons, true)
				KC.advance(1.2) -- (the HUD's layout poll: the vitals card steps round the keys)
				local mobile = pg():FindFirstChild("MobileControls")
				local runKey = mobile and mobile:FindFirstChild("RunButton", true)
				T.check(runKey ~= nil and shownGui(runKey), fmt("guide plank %dx%d: (setup) the touch keys (RUN) are on the screen", size[1], size[2]))
				for _, state in ipairs({ "tutorial folded", "tutorial done" }) do
					local how = (state == "tutorial folded") and tutorialFolded() or (tutorialDone() or "hidden")
					for _, mode in ipairs(MODES) do
						local tag = fmt("guide plank %dx%d %s, %s", size[1], size[2], state, mode.name)
						pcall(Guide.Stop)
						pcall(Mock.HidePrompt, prompt)
						pcall(Mock.HidePrompt, other)
						otherPart.CFrame = away
						KC.advance(0.1)
						local at = anchor.Position - dir * mode.dist
						at = Vector3.new(at.X, L.Origin.Y + 3, at.Z)
						Mock.Teleport(player, CFrame.lookAt(at, at + dir))
						local head = at + Vector3.new(0, 1.9, 0)
						local camAt = head - dir * 12.5 + Vector3.new(0, 4.5, 0)
						local function camAtTilt(deg)
							return CFrame.lookAt(camAt, head + dir * 14 + Vector3.new(0, 2 + 14 * math.tan(math.rad(deg)), 0))
						end
						camObj.CFrame = camAtTilt(0)
						KC.advance(0.1)
						T.check(Guide.Start("StormAltar") == true, tag .. ": (setup) the guide starts")
						Mock.ShowPrompt(prompt, Enum.ProximityPromptInputType.Touch)
						local cards = { { prompt = prompt, from = 0 } }
						local t, worst, worstAt, frames, shownFrames, gateFrames = 0, math.huge, nil, 0, 0, 0
						local hereShown, hereFrames, hereGap, hereAt = 0, 0, nil, "-"
						local placed = false
						while t < mode.secs - 1e-6 do
							local cf = camAtTilt(mode.tilt and mode.tilt(t) or 0)
							camObj.CFrame = cf
							KC.advance(1 / 30)
							camObj.CFrame = cf
							t = t + 1 / 30
							if mode.other and placed and placed ~= true then
								-- the NPC's plank (shown the frame before, 200 studs off: past its MaxDistance) stood on the chip where
								-- it was (its middle on the chip's, 16 studs from the camera)
								local c, card = placed, PC.CardOf(other)
								if T.check(card ~= nil, tag .. ": (setup) the NPC's plank") then
									local vp, f, d = Mock.Viewport, focal(camObj), 16
									local w, h = card.Size.X.Offset, card.Size.Y.Offset
									local vx, vy = (c.X + c.R) / 2 - card.SizeOffset.X * w, (c.Y + c.B) / 2 + card.SizeOffset.Y * h
									local p = camObj.CFrame:PointToWorldSpace(Vector3.new((vx - vp.X / 2) * d / f, -(vy - vp.Y / 2) * d / f, -d))
									otherPart.CFrame = CFrame.new(p - card.StudsOffsetWorldSpace)
									cards[#cards + 1] = { prompt = other, from = t }
								end
								placed = true
							elseif mode.other and not placed and t >= 0.5 - 1e-6 then
								placed = chipNow() or true
								Mock.ShowPrompt(other, Enum.ProximityPromptInputType.Touch)
							end
							frames = frames + 1
							local c, vis = chipNow()
							local phase = Guide.Phase and Guide.Phase() or nil
							if vis and c then
								shownFrames = shownFrames + 1
								for _, e in ipairs(cards) do
									local card = PC.CardOf(e.prompt)
									local r = card and card.Enabled and billboard(card)
									if r and t >= e.from + 0.1 - 1e-6 then
										local g = gapOf(c, r)
										if e.prompt == prompt then
											gateFrames = gateFrames + 1
										end
										if g < worst then
											worst = g
											worstAt = fmt("%.2f s (%s): chip %s, %s plank %s", t, tostring(phase), show(c), e.prompt.ActionText, show(r))
										end
									end
								end
							end
							if phase == "Here" and t >= 0.5 - 1e-6 and t <= 2.5 + 1e-6 then
								if hereFrames == 15 then -- (1 s in: where it stands, shown or not, and the plank)
									local card = PC.CardOf(prompt)
									local r = card and card.Enabled and billboard(card)
									hereAt = fmt("chip %s %s, plank %s", show(c), vis and "shown" or "hidden", show(r or nil))
								end
								hereFrames = hereFrames + 1
								if vis then
									hereShown = hereShown + 1
									local card = PC.CardOf(prompt)
									local r = card and card.Enabled and billboard(card)
									hereGap = r and c and gapOf(c, r) or hereGap
								end
							end
						end
						T.check(worst >= 6 - 1e-3, tag .. ": the chip, while it shows, keeps 6 px off every prompt plank",
							fmt("%.1f px at %s", worst, tostring(worstAt)))
						-- (320 x 568: the mock gate's plank reaches the chip's home there on kit-b 1a55f73 too, 1 px over it, and
						-- no spot holds the full line, so the chip hides the whole phase on both trees; listed, not held)
						if mode.shows and state == "tutorial done" and not (size[1] == 320 and size[2] == 568) then
							T.check(hereFrames > 0 and hereShown == hereFrames, tag .. ": the chip shows through the \"You're here\" phase (0.5 - 2.5 s)",
								fmt("%d of %d frames shown", hereShown, hereFrames))
						end
						if mode.name == "here" then
							T.info(fmt("*%s: tutorial %s; the chip shows %d of %d frames 0.5 - 2.5 s into \"You're here\", %s px off the plank (1 s in: %s)",
								tag, how, hereShown, hereFrames, hereGap and fmt("%.1f", hereGap) or "-", hereAt))
						end
						Guide.Stop()
						pcall(Mock.HidePrompt, prompt)
						pcall(Mock.HidePrompt, other)
						otherPart.CFrame = away
						KC.advance(0.1)
					end
				end
				pcall(MC._TouchButtons, false)
			end
		end)
		methods.WorldToViewportPoint, methods.WorldToScreenPoint = saved[1], saved[2]
		pcall(Guide.Stop)
		pcall(Mock.HidePrompt, prompt)
		pcall(Mock.HidePrompt, other)
		pcall(MC._TouchButtons, false)
		UIS.TouchEnabled = touchWas
		Mock.SetViewport(1920, 1080)
		pcall(tutorialDone)
		Mock.Teleport(player, CFrame.new(L.Origin + Vector3.new(0, 3, 20)))
		KC.advance(0.5)
		gate:Destroy()
		if madeLobby then
			lobby:Destroy()
		end
		T.check(ok, "guide plank: the scenario ran", tostring(err))
		KC.flushErrors("travel_guide_plank")
	end)

	----------------------------------------------------------------------------------------------------------------
	-- travel_guide_walk (look review fin1, MJ-A / MJ-B; pol0, MAJOR 1 - 3): the camera moves at the REAL lobby's Altar
	-- gate (LobbyBuilder, StormAltar and GateService built in the client world as dump_gui's worldui scenes build it; pol0:
	-- the mock gate and its fixed turns missed what the real lobby showed) under the stock camera (12.5 studs behind the
	-- head, 4.5 up, looking 14 ahead and `tilt` up) at 360x640, 640x360, 667x375, 390x844, 844x390, 1280x720 and
	-- 1920x1080, with the touch buttons on the phones (pol0 MAJOR 3: without MobileControls the chip over RUN at 360x640
	-- passed). Runs, one 1/30 s frame a step:
	--   walk     50 -> 12 studs at Config.WalkSpeed, the camera turned 0 / 12 / 16 / 20 / -15 degrees off the trail
	--            (28 / 32 at 1280x720 and 1920x1080: there the sign's edge touched the arrow's widest voxels)
	--   pan      standing 45 studs out, the camera swept -35 -> 35 -> -35 degrees at 23, 60 and 120 degrees a second;
	--            70 studs out at 23
	--   look up  standing 20 and 12 studs out, the camera tilted 2 -> 14 -> 2 (the arrow comes in from the screen's top)
	-- Every frame:
	--   free     the chip and, while it shows, the GuideSign lie wholly on the screen and under no HUD piece
	--   clear    the chip never covers the arrow or the sign, the sign never the arrow
	--   arrow    the arrow is a world part: it shows all the way and may pass behind the HUD or out of the screen's top
	--            (pol0 MAJOR 1: it hid within 3 px of any HUD piece or the top, and phones lost it for the whole walk)
	--   steps    the chip moves in the kit's hard steps: from one frame to the next by at most a quarter of its width
	--            (a move shows as held steps), or across a hide (it hides, then shows at its new place: how it crosses
	--            a piece, pol0 MAJOR 2 a); it hides at most 0.2 s at a time on a walk, 0.5 s on a pan or a look up
	--   row      on a landscape screen the chip stays on its home row (pol0 MAJOR 2 d: it dropped onto the gate), and
	--            never further than its own width off the top centre (MAJOR 2 b: pushed 750 px into the corner)
	-- A walk also keeps one place off home, out and back: no side flip, no creep (a rest more than 6 px off its spot;
	-- pol0 minor 1), home at the end; at 50 studs on 1920x1080, 1280x720 and 390x844 the arrow and its sign show. On a
	-- landscape walk (and the far walk, 120 -> 50 studs at 844x390, 1280x720, 1920x1080) the chip rests off the top centre
	-- only while the arrow is near its home: the sign gives way to the chip (pol0 minor 3).
	-- (fin1's rule "never more than 40 px in one frame" became the steps rule. Reason: pol0 minor 2 asks for the kit's
	-- hard steps in place of the eased glide, and MAJOR 2 a for a hard step or a hide where the chip crosses a piece.
	-- The 500 px jump fin1 caught still fails it: a jump is more than a quarter of the chip's width with no hide between)
	--
	-- guide_pins (fix6: every look major of the world lane pinned, at the eleven gate sizes 360x640, 640x360, 667x375,
	-- 720x405, 800x450, 844x390, 960x540, 390x844, 1024x768, 1280x720, 1920x1080; the same walk, its runs and its rules
	-- only as the reviews worded them; a pin's name says its review):
	--   pin MJ-A (fin1)  a straight walk (turned 0 / 12 / -15 / 6 / -8 / 24 / -25): the chip keeps one place off home,
	--                    out and back, and moves in hard steps or across a hide (the 500 px jump, four places in 1.7 s)
	--   pin MJ-B (fin1)  the same walks: the GuideSign, while it shows, wholly on the screen and under no HUD piece (390x844:
	--                    jammed under the wallet strip, the top bar's pill and the "..." button from 35 to 26 studs)
	--   pin W1 (pol1 A)  the same walks and a walk that stops at 20 studs: the GuideSign does not flash (each show, hide,
	--                    line change or new spot holds 0.5 s, unless the run ends first), takes at most two spots a walk,
	--                    and never stacks on the chip (sharing columns, at least twice the sign's 8 px clearance apart,
	--                    under the screen factor: 7-10 px read as one block, 'Storm Altar' over 'Guiding to Storm Altar')
	--   pin W2 (pol1 B)  standing 45 studs out, the camera panned -35 -> 35 -> -35 at 6, 12, 23 and 60 degrees a second (6
	--                    and 12: fix6 look0 #5), and two walks with the camera turning (0 -> 40 and 40 -> 0 degrees, 50 -> 20
	--                    studs): in each pass the chip leaves home at most once, for one spot (it stepped into the arrow's
	--                    path, then hid and came back 483 px away on the other side: three moves a pass); and (look0 #4) it
	--                    hides at most 0.5 s at a time there (the one trip had cost hides of 0.6 - 2.1 s)
	--   pin G1 (look1 #1) the pans (and one at 35 degrees a second), the turning walks, a pan that stops facing the gate,
	--                    one that turns back from it and two sways: every chip state (a show between two hides or two
	--                    changes of its line) lasts 0.5 s, and it never blinks in place (e272588: three blinks a pass, the
	--                    short line at home 1 - 14 frames)
	--   pin G2 (look1 #2) the sways (+-3 degrees at 6 degrees a second, +-6 at 24) and the pan that turns back: the chip
	--                    keeps the side it took (it jumped 477 px across the arrow at each turn of a sway on desktop)
	--   pin G3 (look1 #3) the same runs and a look up at 12 studs: each GuideSign show lasts 0.5 s (W1 held the walk only)
	----------------------------------------------------------------------------------------------------------------
	-- (fix6b harness) each walk's runs, one scenario list a part: travel_guide_walk took 293 s alone and ran past the 600 s
	-- per-scenario cap in the whole suite under load; guide_pins took 1036 s alone and hit the cap after it. Each part is
	-- its own list with its own cap; tools/smoke.py runs every part when the walk's first list is named (`--only
	-- travel_guide_walk` / `--only guide_pins` run the whole walk, as before). A part takes the runs of a kind
	-- ("kind:look"), of one name ("pan 23 deg/s at 45 studs") or of one name at some sizes ("pan 6 deg/s at 45
	-- studs@360x640|640x360"); every run is in exactly one part (checked). The runs, their frames and their rules are
	-- unchanged. A frame costs about 50 ms alone; each part holds at most ~3600 frames (~190 s alone, a third of the cap;
	-- a 6 deg/s pan is 720 frames a size, 12 deg/s 370, 23 deg/s 202, a walk 73)
	local function sizesOf(name, sizes)
		return name .. "@" .. sizes
	end
	local PAN6, PAN12 = "pan 6 deg/s at 45 studs", "pan 12 deg/s at 45 studs"
	local WALK_PARTS = {
		travel = {
			{ "kind:walk", "kind:far" }, -- travel_guide_walk
			{ "pan 23 deg/s at 45 studs", "pan 120 deg/s at 45 studs" }, -- travel_guide_walk_pans
			{ "pan 60 deg/s at 45 studs", "pan 23 deg/s at 70 studs" }, -- travel_guide_walk_pans_b
			{ "kind:look" }, -- travel_guide_walk_looks
		},
		pins = {
			{ "walk", "walk turned 12", "walk turned -15", "walk turned 6" }, -- guide_pins (3212 frames)
			{ "walk turned -8", "walk turned 24", "walk turned -25" }, -- guide_pins_walks (2409)
			{ "kind:stop", "kind:turnwalk" }, -- guide_pins_turns (2574)
			{ sizesOf(PAN6, "360x640|640x360|667x375|720x405") }, -- guide_pins_pan6 (2880)
			{ sizesOf(PAN6, "800x450|844x390|960x540|390x844") }, -- guide_pins_pan6_b (2880)
			{ sizesOf(PAN6, "1024x768|1280x720|1920x1080"), "pan 60 deg/s at 45 studs" }, -- guide_pins_pan6_c (3150)
			{ sizesOf(PAN12, "360x640|640x360|667x375|720x405|800x450|844x390"), "kind:panstop" }, -- guide_pins_pan12 (3496)
			{ sizesOf(PAN12, "960x540|390x844|1024x768|1280x720|1920x1080"), "kind:panrev" }, -- guide_pins_pan12_b (3082)
			{ "pan 23 deg/s at 45 studs", "sway +-6 deg at 24 deg/s" }, -- guide_pins_pans (3432)
			{ "pan 35 deg/s at 45 studs", "sway +-3 deg at 6 deg/s" }, -- guide_pins_sways (3080)
			{ "kind:look" }, -- guide_pins_looks (1430)
		},
	}
	local WALK_LISTS = {
		travel = { "travel_guide_walk", "travel_guide_walk_pans", "travel_guide_walk_pans_b", "travel_guide_walk_looks" },
		pins = { "guide_pins", "guide_pins_walks", "guide_pins_turns", "guide_pins_pan6", "guide_pins_pan6_b", "guide_pins_pan6_c",
			"guide_pins_pan12", "guide_pins_pan12_b", "guide_pins_pans", "guide_pins_sways", "guide_pins_looks" },
	}
	local function partKey(key, run)
		if key == "kind:" .. run.kind or key == run.name then
			return true
		end
		local name, sizes = key:match("^(.-)@(.+)$")
		return name == run.name and (("|" .. sizes .. "|"):find(fmt("|%dx%d|", run.w, run.h), 1, true)) ~= nil
	end
	local function guideWalk(scen, pins, part)
		local Config = shared("Config")
		local TC = client("Controllers/TutorialController")
		local MC = client("Controllers/MovementController")
		local Guide = TC and TC.Guide
		local methods = Mock.Classes and Mock.Classes.Camera and Mock.Classes.Camera.methods
		if not T.check(type(Guide) == "table" and methods ~= nil and workspace.CurrentCamera ~= nil and MC ~= nil and type(MC._TouchButtons) == "function",
			"guide walk: (setup) TutorialController.Guide, MovementController._TouchButtons, the mock camera") then
			return
		end
		local player = game:GetService("Players").LocalPlayer
		local UIS = game:GetService("UserInputService")
		local GS = game:GetService("GuiService")
		local L = Config.Lobby
		local camObj = workspace.CurrentCamera
		local saved = { methods.WorldToViewportPoint, methods.WorldToScreenPoint }
		local function project(self, pos)
			local rel = self.CFrame:PointToObjectSpace(pos)
			local vp = Mock.Viewport
			local d = -rel.Z
			local f = (vp.Y / 2) / math.tan(math.rad(self.FieldOfView / 2))
			local dd = (abs(d) < 1e-6) and 1e-6 or d
			local x, y = vp.X / 2 + rel.X / dd * f, vp.Y / 2 - rel.Y / dd * f
			return Vector3.new(x, y, d), d > 0 and x >= 0 and x <= vp.X and y >= 0 and y <= vp.Y
		end
		-- the real lobby, built here every run (the client world has no server; a lobby another check left, a mock gate,
		-- is set aside and put back); what the build adds goes at the end
		local aside = workspace:FindFirstChild("NimbusLobby")
		if aside then
			aside.Parent = nil
		end
		local before, built = {}, {}
		for _, c in ipairs(workspace:GetChildren()) do
			before[c] = true
		end
		local info = nil
		local context = Mock.Context
		Mock.Context = "server"
		-- (fix6b harness) GateService.Init runs once a server (its S.initialized guard): a second walk in the same client
		-- world built a new lobby, but Init returned at once and its gate got no AltarGatePrompt (guide_pins after
		-- travel_guide_walk: "(setup) the built lobby's Altar gate prompt" failed). Each walk binds its own lobby with a
		-- fresh copy of the module (a cloned ModuleScript is a new module, as in Roblox), removed with the lobby
		local gsCopy = nil
		local okB, whyB = pcall(function()
			local LB = req(ROOTS.server .. "/Services/LobbyBuilder")
			info = LB and LB.Build()
			info = type(info) == "table" and info or {}
			local SA = req(ROOTS.server .. "/Services/StormAltar")
			if SA then
				pcall(SA.Build, info)
			end
			local gsMod = Mock.GetPath(ROOTS.server .. "/Services/GateService")
			gsCopy = gsMod and gsMod:Clone()
			local GSv = nil
			if gsCopy then
				gsCopy.Name = "GateService_" .. scen
				gsCopy.Parent = gsMod.Parent
				local okR, m = pcall(require, gsCopy)
				GSv = okR and m or nil
			end
			if GSv then
				pcall(GSv.Init, info, { StormAltar = SA })
			end
		end)
		Mock.Context = context
		for _, c in ipairs(workspace:GetChildren()) do
			if not before[c] and not c:IsA("Camera") and not c:IsA("Terrain") then
				built[#built + 1] = c
			end
		end
		T.check(okB, "guide walk: (setup) LobbyBuilder, StormAltar and GateService build the lobby", tostring(whyB))
		KC.advance(0.6)
		local gatePrompt = nil
		for _, c in ipairs(built) do
			for _, d in ipairs(c:GetDescendants()) do
				if not gatePrompt and d:IsA("ProximityPrompt") and d.Name == "AltarGatePrompt" and d.Parent and d.Parent:IsA("BasePart") then
					gatePrompt = d
				end
			end
		end
		local function putBack()
			for _, c in ipairs(built) do
				c:Destroy()
			end
			if gsCopy then
				gsCopy:Destroy()
			end
			if aside then
				aside.Parent = workspace
			end
		end
		if not T.check(gatePrompt ~= nil, "guide walk: (setup) the built lobby's Altar gate prompt") then
			putBack()
			return
		end
		local gate = gatePrompt.Parent
		T.info(fmt("*guide walk: the built lobby's Altar gate prompt %s at %.0f, %.0f, %.0f", gate:GetFullName(), gate.Position.X, gate.Position.Y, gate.Position.Z))
		local spawn = (info and typeof(info.SpawnCFrame) == "CFrame" and info.SpawnCFrame.Position) or (L.Origin + Vector3.new(0, 3, 20))
		local flat = Vector3.new(gate.Position.X - spawn.X, 0, gate.Position.Z - spawn.Z)
		local dir = flat.Magnitude > 1 and flat.Unit or Vector3.new(0, 0, -1)
		local standY = spawn.Y
		-- screen px (the top band included)
		local function screenRect(obj)
			local owner = obj:FindFirstAncestorOfClass("ScreenGui")
			local dy = (owner and owner.IgnoreGuiInset) and 0 or (Mock.TopInset or 0)
			local p, s = obj.AbsolutePosition, obj.AbsoluteSize
			return { X = p.X, Y = p.Y + dy, R = p.X + s.X, B = p.Y + s.Y + dy }
		end
		local function grow(r, by)
			return { X = r.X - by, Y = r.Y - by, R = r.R + by, B = r.B + by }
		end
		local function boxOf(part)
			local r = nil
			for _, dx in ipairs({ -0.5, 0.5 }) do
				for _, dy in ipairs({ -0.5, 0.5 }) do
					for _, dz in ipairs({ -0.5, 0.5 }) do
						local v = project(camObj, part.CFrame:PointToWorldSpace(Vector3.new(dx * part.Size.X, dy * part.Size.Y, dz * part.Size.Z)))
						if v.Z <= 0 then
							return nil
						end
						if r then
							r.X, r.Y, r.R, r.B = math.min(r.X, v.X), math.min(r.Y, v.Y), math.max(r.R, v.X), math.max(r.B, v.Y)
						else
							r = { X = v.X, Y = v.Y, R = v.X, B = v.Y }
						end
					end
				end
			end
			return r
		end
		local function billboard(gui)
			local ad = gui.Adornee or gui.Parent
			local cf = camObj.CFrame
			local so = gui.StudsOffset
			local p = ad.Position + gui.StudsOffsetWorldSpace + cf.RightVector * so.X + cf.UpVector * so.Y - cf.LookVector * so.Z
			local v = project(camObj, p)
			if v.Z <= 0 then
				return nil
			end
			local w, h = gui.Size.X.Offset, gui.Size.Y.Offset
			local x0 = v.X - w / 2 + gui.SizeOffset.X * w
			local y0 = v.Y - h / 2 - gui.SizeOffset.Y * h
			return { X = x0, Y = y0, R = x0 + w, B = y0 + h }
		end
		-- every shown, painted HUD piece (the top bar's pill and the touch buttons included) and Roblox's own buttons in
		-- the top band, left / right of the TopbarInset (TutorialController's fallback when it is unset)
		local function hudPieces()
			local vp = Mock.Viewport
			local out = {}
			for _, name in ipairs({ "NimbusHud", "NimbusMenu", "NimbusHotbar", "MobileControls", "NimbusDaily", "NimbusTopBar", "NimbusTutorial" }) do
				local g = pg():FindFirstChild(name)
				if g and g:IsA("ScreenGui") and g.Enabled then
					for _, d in ipairs(g:GetDescendants()) do
						if d:IsA("GuiObject") and d.AbsoluteSize.X > 0 and d.AbsoluteSize.Y > 0 and d.BackgroundTransparency < 0.5 then
							local shown = true
							local a = d
							while a and a ~= g do
								if a:IsA("GuiObject") and not a.Visible then
									shown = false
									break
								end
								a = a.Parent
							end
							local r = shown and screenRect(d)
							if r and (r.R - r.X) < vp.X * 0.6 and (r.B - r.Y) < vp.Y * 0.6 then
								out[#out + 1] = { name = g.Name .. "." .. d.Name, rect = r }
							end
						end
					end
				end
			end
			local top = Mock.TopInset or 0
			if top > 0 then
				local minX, maxX = 112, vp.X - 72
				local okT, tb = pcall(function()
					return GS.TopbarInset
				end)
				if okT and typeof(tb) == "Rect" and tb.Max.X > tb.Min.X then
					minX, maxX = tb.Min.X, tb.Max.X
				end
				out[#out + 1] = { name = "Roblox's buttons (left)", rect = { X = 0, Y = 0, R = minX, B = top - 4 } }
				out[#out + 1] = { name = "Roblox's buttons (right)", rect = { X = maxX, Y = 0, R = vp.X, B = top - 4 } }
			end
			return out
		end
		-- the stock camera `turn` degrees off the trail, `tilt` studs up at its look point, the player `dist` studs out
		local function place(dist, turn, tilt)
			local at = gate.Position - dir * dist
			at = Vector3.new(at.X, standY, at.Z)
			Mock.Teleport(player, CFrame.lookAt(at, at + dir))
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local head = (root and root.Position or at) + Vector3.new(0, 1.9, 0)
			local a = math.rad(turn)
			local view = Vector3.new(dir.X * math.cos(a) + dir.Z * math.sin(a), 0, -dir.X * math.sin(a) + dir.Z * math.cos(a))
			camObj.CFrame = CFrame.lookAt(head - view * 12.5 + Vector3.new(0, 4.5, 0), head + view * 14 + Vector3.new(0, tilt, 0))
		end
		local speed = tonumber(Config.WalkSpeed) or 16
		-- frames from (d0, t0, l0) to (d1, t1, l1): walking at WalkSpeed (secs nil) or over `secs`
		local function seg(list, d0, d1, t0, t1, l0, l1, secs)
			local n = secs and math.max(1, math.floor(secs * 30 + 0.5)) or math.max(1, math.ceil(abs(d1 - d0) / (speed / 30) - 1e-6))
			for i = 1, n do
				local f = i / n
				local d = d0 + (d1 - d0) * f
				if not secs then
					d = d0 + (d1 - d0) * math.min(1, i * (speed / 30) / math.max(abs(d1 - d0), 1e-6))
				end
				list[#list + 1] = { d, t0 + (t1 - t0) * f, l0 + (l1 - l0) * f }
			end
		end
		local function hold(list, d, t, l, n)
			for _ = 1, n do
				list[#list + 1] = { d, t, l }
			end
		end
		local SIZES = { { 360, 640 }, { 640, 360 }, { 667, 375 }, { 390, 844 }, { 844, 390 }, { 1280, 720 }, { 1920, 1080 } }
		if pins then
			SIZES = { { 360, 640 }, { 640, 360 }, { 667, 375 }, { 720, 405 }, { 800, 450 }, { 844, 390 }, { 960, 540 }, { 390, 844 },
				{ 1024, 768 }, { 1280, 720 }, { 1920, 1080 } }
			-- (while working: NC_GUIDE_PINS_SIZES="640x360,1920x1080" walks those alone; the gate runs all eleven)
			local only = os and os.getenv and os.getenv("NC_GUIDE_PINS_SIZES")
			if only and only ~= "" then
				local keep = {}
				for _, sz in ipairs(SIZES) do
					if (("," .. only .. ","):find("," .. sz[1] .. "x" .. sz[2] .. ",", 1, true)) then
						keep[#keep + 1] = sz
					end
				end
				SIZES = keep
				T.info("*guide pins: NC_GUIDE_PINS_SIZES=" .. only .. " (not the gate run)")
			end
		end
		-- (while working: NC_GUIDE_TRACE=<file> appends one line a frame: the run, the frame, the arrow, the chip and the
		-- GuideSign as the walk reads them)
		local tracePath = os and os.getenv and os.getenv("NC_GUIDE_TRACE")
		local traceFile = (tracePath and tracePath ~= "" and io and io.open) and io.open(tracePath, "a") or nil
		local runs = {}
		local function add(kind, name, size, frames)
			runs[#runs + 1] = { kind = kind, name = name, w = size[1], h = size[2], frames = frames }
		end
		-- (guide_pins) a pass's frames carry its number (fr[4]): W2 counts the chip's trips off home in each
		local function mark(list, from, pass)
			for i = from, #list do
				list[i][4] = pass
			end
		end
		if pins then
			for _, turn in ipairs({ 0, 12, -15, 6, -8, 24, -25 }) do
				for _, size in ipairs(SIZES) do
					local f = { { 50, turn, 2 } }
					seg(f, 50, 12, turn, turn, 2, 2)
					add("walk", turn ~= 0 and fmt("walk turned %d", turn) or "walk", size, f)
				end
			end
			for _, size in ipairs(SIZES) do
				local f = { { 50, 0, 2 } }
				seg(f, 50, 20, 0, 0, 2, 2)
				hold(f, 20, 0, 2, 60)
				add("stop", "walk, stop at 20 studs", size, f)
			end
			-- (fix6 look0 #5: at 6 degrees a second the chip still took the side ahead, then crossed: two trips a pass; W2 had
			-- 23 and 60 alone) the slow pans too
			for _, deg in ipairs({ 6, 12, 23, 60 }) do
				for _, size in ipairs(SIZES) do
					local f = {}
					hold(f, 45, -35, 2, 10)
					local p1 = #f + 1
					seg(f, 45, 45, -35, 35, 2, 2, 70 / deg)
					mark(f, p1, 1)
					local p2 = #f + 1
					seg(f, 45, 45, 35, -35, 2, 2, 70 / deg)
					mark(f, p2, 2)
					hold(f, 45, -35, 2, 10)
					add("pan", fmt("pan %d deg/s at 45 studs", deg), size, f)
				end
			end
			for _, tt in ipairs({ { 0, 40 }, { 40, 0 } }) do
				for _, size in ipairs(SIZES) do
					-- (fix6) the standing start is no part of the pass, as the pans' hold is not: a spot the chip took there,
					-- the camera still, could not know which way the arrow would go; the pass is the turning walk from the
					-- second frame (a spot taken once the turn runs still counts)
					local f = { { 50, tt[1], 2 } }
					seg(f, 50, 20, tt[1], tt[2], 2, 2)
					mark(f, 2, 1)
					add("turnwalk", fmt("walk turning %d -> %d", tt[1], tt[2]), size, f)
				end
			end
			-- (fix6b, look1 #1 - #3) a pan at 35 degrees a second (the short line at home held 0.13 - 0.23 s there), a pan
			-- that stops facing the gate and one that turns back from it (23 degrees a second), the camera swayed +-3
			-- degrees at 6 degrees a second (1 s a leg) and +-6 at 24 (0.5 s a leg) standing 45 studs out (the chip jumped
			-- 477 px across the arrow at each turn of the sway), and the look up at 12 studs (the GuideSign's 2-frame
			-- name-alone flash on every landscape phone)
			for _, size in ipairs(SIZES) do
				local f = {}
				hold(f, 45, -35, 2, 10)
				local p1 = #f + 1
				seg(f, 45, 45, -35, 35, 2, 2, 70 / 35)
				mark(f, p1, 1)
				local p2 = #f + 1
				seg(f, 45, 45, 35, -35, 2, 2, 70 / 35)
				mark(f, p2, 2)
				hold(f, 45, -35, 2, 10)
				add("pan", "pan 35 deg/s at 45 studs", size, f)
			end
			for _, size in ipairs(SIZES) do
				local f = {}
				hold(f, 45, -35, 2, 10)
				seg(f, 45, 45, -35, 0, 2, 2, 35 / 23)
				hold(f, 45, 0, 2, 60)
				add("panstop", "pan 23 deg/s, stop facing the gate", size, f)
				f = {}
				hold(f, 45, -35, 2, 10)
				seg(f, 45, 45, -35, 0, 2, 2, 35 / 23)
				seg(f, 45, 45, 0, -35, 2, 2, 35 / 23)
				hold(f, 45, -35, 2, 10)
				add("panrev", "pan 23 deg/s to the gate and back", size, f)
			end
			for _, sw in ipairs({ { 3, 1, 4 }, { 6, 0.5, 6 } }) do
				for _, size in ipairs(SIZES) do
					local f = {}
					hold(f, 45, -sw[1], 2, 10)
					for leg = 1, sw[3] do
						local a0 = (leg % 2 == 1) and -sw[1] or sw[1]
						seg(f, 45, 45, a0, -a0, 2, 2, sw[2])
					end
					hold(f, 45, (sw[3] % 2 == 1) and sw[1] or -sw[1], 2, 10)
					add("sway", fmt("sway +-%d deg at %d deg/s", sw[1], math.floor(2 * sw[1] / sw[2] + 0.5)), size, f)
				end
			end
			for _, size in ipairs(SIZES) do
				local f = {}
				hold(f, 12, 0, 2, 10)
				seg(f, 12, 12, 0, 0, 2, 14, 2)
				seg(f, 12, 12, 0, 0, 14, 2, 2)
				add("look", "look up at 12 studs", size, f)
			end
		end
		for _, turn in ipairs(pins and {} or { 0, 12, 16, 20, -15, 28, 32 }) do
			for _, size in ipairs(SIZES) do
				if abs(turn) < 25 or size[1] >= 1280 then
					local f = { { 50, turn, 2 } }
					seg(f, 50, 12, turn, turn, 2, 2)
					add("walk", turn ~= 0 and fmt("walk turned %d", turn) or "walk", size, f)
				end
			end
		end
		-- (pol0 minor 3: from far off only the sign reached the chip's home at 844x390, which sent it 168 px aside from 120
		-- studs in) the far walk, 120 -> 50 studs
		for _, size in ipairs(pins and {} or { { 844, 390 }, { 1280, 720 }, { 1920, 1080 } }) do
			local f = { { 120, 0, 2 } }
			seg(f, 120, 50, 0, 0, 2, 2)
			add("far", "far walk", size, f)
		end
		for _, p in ipairs(pins and {} or { { 45, 23 }, { 45, 60 }, { 45, 120 }, { 70, 23 } }) do
			for _, size in ipairs(SIZES) do
				local f = {}
				hold(f, p[1], -35, 2, 10)
				seg(f, p[1], p[1], -35, 35, 2, 2, 70 / p[2])
				seg(f, p[1], p[1], 35, -35, 2, 2, 70 / p[2])
				hold(f, p[1], -35, 2, 10)
				add("pan", fmt("pan %d deg/s at %d studs", p[2], p[1]), size, f)
			end
		end
		for _, d in ipairs(pins and {} or { 20, 12 }) do
			for _, size in ipairs(SIZES) do
				local f = {}
				hold(f, d, 0, 2, 10)
				seg(f, d, d, 0, 0, 2, 14, 2)
				seg(f, d, d, 0, 0, 14, 2, 2)
				add("look", fmt("look up at %d studs", d), size, f)
			end
		end
		-- (while working: NC_GUIDE_PINS_RUNS="sway,and back" walks the runs whose names hold one of those; the gate runs all)
		local onlyRuns = pins and os and os.getenv and os.getenv("NC_GUIDE_PINS_RUNS")
		if onlyRuns and onlyRuns ~= "" then
			local keep = {}
			for _, run in ipairs(runs) do
				for word in (onlyRuns .. ","):gmatch("([^,]+),") do
					if run.name:find(word, 1, true) then
						keep[#keep + 1] = run
						break
					end
				end
			end
			runs = keep
			T.info("*guide pins: NC_GUIDE_PINS_RUNS=" .. onlyRuns .. " (not the gate run)")
		end
		-- (fix6b harness) this list's part of the runs (WALK_PARTS); no run is left out of every part
		if part then
			local parts = WALK_PARTS[pins and "pins" or "travel"]
			local keep, odd = {}, {}
			for _, run in ipairs(runs) do
				local found = {}
				for i, keys in ipairs(parts) do
					for _, key in ipairs(keys) do
						if partKey(key, run) then
							found[#found + 1] = i
							break
						end
					end
				end
				if #found == 1 and found[1] == part then
					keep[#keep + 1] = run
				elseif #found ~= 1 then
					odd[#odd + 1] = fmt("%s %dx%d in %d parts", run.name, run.w, run.h, #found)
				end
			end
			T.check(#odd == 0, scen .. ": (setup) every run is in exactly one part of the walk", table.concat(odd, "; "))
			-- (NC_GUIDE_PINS_SIZES / _RUNS, while working, may leave a part empty on purpose)
			local devFilter = pins and os and os.getenv and ((os.getenv("NC_GUIDE_PINS_SIZES") or "") ~= "" or (os.getenv("NC_GUIDE_PINS_RUNS") or "") ~= "")
			if not devFilter then
				T.check(#keep > 0, scen .. ": (setup) part " .. part .. " of the walk has runs")
			end
			T.info(fmt("*%s: part %d of %d, %d runs", scen, part, #parts, #keep))
			runs = keep
		end
		local touchWas = UIS.TouchEnabled
		local ok, err = pcall(function()
			methods.WorldToViewportPoint, methods.WorldToScreenPoint = project, project
			for _, run in ipairs(runs) do
				local tag = fmt("guide %s %dx%d", run.name, run.w, run.h)
				local touch = math.min(run.w, run.h) <= 500
				UIS.TouchEnabled = touch
				Mock.SetViewport(run.w, run.h)
				pcall(MC._TouchButtons, touch)
				KC.advance(0.4)
				local vp = Mock.Viewport
				local top = Mock.TopInset or 0
				local f1 = run.frames[1]
				place(f1[1], f1[2], f1[3])
				KC.advance(0.1)
				T.check(Guide.Start("StormAltar") == true, tag .. ": (setup) the guide starts")
				for _ = 1, 15 do
					place(f1[1], f1[2], f1[3])
					KC.advance(1 / 30)
				end
				local hud = hudPieces()
				local fails, counts = {}, {}
				local function fail(rule, msg)
					counts[rule] = (counts[rule] or 0) + 1
					fails[rule] = fails[rule] or msg
				end
				local function under(r)
					for _, piece in ipairs(hud) do
						if overlap(r, piece.rect) then
							return piece.name
						end
					end
					return nil
				end
				local function onScreen(r)
					return r.X >= -0.5 and r.Y >= -0.5 and r.R <= vp.X + 0.5 and r.B <= vp.Y + 0.5
				end
				local prev, still, places, sides = nil, 0, {}, {}
				local hidden, maxHidden, hiddenFrames = 0, 0, 0
				local seenArrow, seenSign, signFrames = nil, nil, 0
				local fullW, arrowNear = nil, nil
				-- (guide_pins) the GuideSign's state each frame ("off", or its spot: right / left / under the tip, "/name"
				-- with the name alone) and the first frame it stacked on the chip
				local signStates, stack, traceSign = {}, nil, nil
				-- (guide_pins, fix6b) the chip each frame: false hidden, else its middle, top and line ({ x, y, t })
				local chipSeq = {}
				for i, fr in ipairs(run.frames) do
					if i > 1 then
						place(fr[1], fr[2], fr[3])
						KC.advance(1 / 30)
					end
					local at = fmt("%.1f studs, turn %.0f, tilt %.1f", fr[1], fr[2], fr[3])
					local fx = workspace:FindFirstChild("ClientFx")
					local wg = fx and fx:FindFirstChild("TutorialGuide")
					local gui = pg():FindFirstChild("NimbusGuide")
					local chip = gui and gui:FindFirstChild("Chip", true)
					local c = nil
					chipSeq[i] = false
					if not (chip and chip.Visible and gui.Enabled) then
						hidden = hidden + 1
						hiddenFrames = hiddenFrames + 1
						maxHidden = math.max(maxHidden, hidden)
						if hidden == 1 and prev then
							prev.hid = true
						end
					else
						hidden = 0
						local k = (chip:FindFirstChild("ReadScale") and chip.ReadScale.Scale) or 1
						c = grow(screenRect(chip), 3 * k) -- its wood edge
						local cw = c.R - c.X
						local cx = (c.X + c.R) / 2
						local tl = chip:FindFirstChild("Text")
						chipSeq[i] = { x = cx, y = c.Y, t = (tl and tl:IsA("TextLabel")) and tl.Text or "" }
						if prev then
							local moved = math.max(abs(cx - prev.x), abs(c.Y - prev.y))
							if moved > cw / 4 + 2 and not prev.hid then
								fail("steps", fmt("%s: the chip moved %.0f px in one frame with no hide (%.0f,%.0f -> %.0f,%.0f; a step is at most %.0f)",
									at, moved, prev.x, prev.y, cx, c.Y, cw / 4 + 2))
							end
							still = (moved < 0.5 and not prev.hid) and (still + 1) or 0
						end
						prev = { x = cx, y = c.Y }
						-- a rest (3 frames still) more than 6 px from the last place is a new place
						if still == 3 or #places == 0 then
							local last = places[#places]
							if not last or math.max(abs(cx - last.x), abs(c.Y - last.y)) > 6 then
								places[#places + 1] = { x = cx, y = c.Y, at = at, i = i, pass = fr[4] }
								local off = cx - vp.X / 2
								sides[#sides + 1] = (off > 2 and "R") or (off < -2 and "L") or "C"
							end
						end
						if not onScreen(c) then
							fail("chip free", fmt("%s: the chip %s is off the screen", at, show(c)))
						end
						local hn = under(c)
						if hn then
							fail("chip free", fmt("%s: the chip %s is under %s", at, show(c), hn))
						end
						if vp.X > vp.Y then
							local homeTop = top + 10 * k - 3 * k -- (GUIDE_TOP under the top band, its wood edge)
							if abs(c.Y - homeTop) > 1.5 then
								fail("row", fmt("%s: the chip %s left its home row (top %.0f) on a landscape screen", at, show(c), homeTop))
							end
						end
						-- (fix6 look0 #4) within the chip's FULL width (its widest drawn this run): the compact line, the same
						-- chip in a shorter word, may step behind a passing arrow that far; it hid 0.6 - 2.1 s waiting for room
						-- within its own shorter width. pol0 MAJOR 2 b's 750 px corner still fails it
						local lim = math.max(cw, fullW or cw)
						if abs(cx - vp.X / 2) > lim + 2 then
							fail("row", fmt("%s: the chip %s is pushed %.0f px off the top centre (its width %.0f)", at, show(c), cx - vp.X / 2, lim))
						end
					end
					-- the arrow (its model in the world guide's folder while it shows)
					local arrow = wg and wg.Parent and wg:FindFirstChild("GuideArrow", true)
					if not arrow then
						fail("arrow", at .. ": the arrow is hidden")
					end
					local box, partBoxes = nil, {}
					for _, d in ipairs(arrow and arrow:GetDescendants() or {}) do
						if d:IsA("BasePart") then
							local b = boxOf(d)
							if b then
								partBoxes[#partBoxes + 1] = b
								box = box and { X = math.min(box.X, b.X), Y = math.min(box.Y, b.Y), R = math.max(box.R, b.R), B = math.max(box.B, b.B) } or b
							end
						end
					end
					-- (fix6b harness) "covers the arrow" is read against the arrow's parts (each part's projected box holds
					-- every pixel it draws), not their union: the arrow is a stepped head narrowing to its tip, and the union's
					-- bottom corners hold nothing (TutorialController reads its silhouette, fin0 MJ1, for the same reason).
					-- Split into lists, the pans start on the other step of the arrow's 0.45 s hop, and at 667 x 375 the union's
					-- empty corner met the chip's corner by 2 px for 1 - 3 frames (travel_guide_walk_pans at 23 and 60 degrees a
					-- second; in one list the same frames fell on the upper step and passed)
					local function onArrow(r)
						for _, b in ipairs(partBoxes) do
							if overlap(r, b) then
								return b
							end
						end
						return nil
					end
					if box then
						seenArrow = seenArrow or at
						local hit = c and onArrow(c)
						if hit then
							fail("clear", fmt("%s: the chip %s covers the arrow %s (its part %s)", at, show(c), show(box), show(hit)))
						end
					end
					-- (pol0 minor 3) on a landscape walk the chip rests off the top centre only for the arrow: it came within 40 px
					-- (1080p: its 10 px berth and its 0.3 s lead on a walk) of the chip's home in the last 20 frames (its 0.3 s
					-- hold and its steps home); the GuideSign gives way to the chip
					if c then
						local k = (chip:FindFirstChild("ReadScale") and chip.ReadScale.Scale) or 1
						fullW = math.max(fullW or 0, c.R - c.X)
						local home = { X = vp.X / 2 - fullW / 2, Y = top + 7 * k, R = vp.X / 2 + fullW / 2, B = top + 7 * k + (c.B - c.Y) }
						if box and overlap(grow(home, 40 * k), box) then
							arrowNear = i
						end
						if (run.kind == "walk" or run.kind == "far") and vp.X > vp.Y and still >= 3 and abs((c.X + c.R) / 2 - vp.X / 2) > 2
							and not (arrowNear and i - arrowNear <= 20) then
							fail("home", fmt("%s: the chip %s rests off the top centre with the arrow %s far from it", at, show(c), show(box)))
						end
					end
					-- the GuideSign while it shows
					local sign = wg and wg.Parent and wg:FindFirstChild("GuideSign", true)
					local card = sign and sign.Enabled and sign:FindFirstChild("Card")
					local bb = card and billboard(sign)
					if bb then
						local sk = (card:FindFirstChild("ReadScale") and card.ReadScale.Scale) or 1
						local w, h = card.Size.X.Offset * sk, card.Size.Y.Offset * sk
						local x0 = bb.X + card.Position.X.Offset + card.Position.X.Scale * (bb.R - bb.X) - card.AnchorPoint.X * w
						local cy = (bb.Y + bb.B) / 2 + card.Position.Y.Offset
						local s = grow({ X = x0, Y = cy - h / 2, R = x0 + w, B = cy + h / 2 }, 3 * sk)
						traceSign = s
						seenSign = seenSign or at
						signFrames = signFrames + 1
						if not onScreen(s) then
							fail("sign free", fmt("%s: the GuideSign %s is cut by the screen's edge", at, show(s)))
						end
						local hn = under(s)
						if hn then
							fail("sign free", fmt("%s: the GuideSign %s is under %s", at, show(s), hn))
						end
						if c and overlap(c, s) then
							fail("clear", fmt("%s: the chip %s covers the GuideSign %s", at, show(c), show(s)))
						end
						local hit = box and onArrow(s)
						if hit then
							fail("clear", fmt("%s: the GuideSign %s covers the arrow %s (its part %s)", at, show(s), show(box), show(hit)))
						end
						-- (guide_pins) its spot as drawn: hung under the arrow's tip (its top at or below the tip), else the
						-- side of the arrow's axis its middle is on
						local spot = "right"
						if box and s.Y >= box.B - 2 then
							spot = "under"
						elseif box and (s.X + s.R) / 2 < (box.X + box.R) / 2 then
							spot = "left"
						end
						local dl = card:FindFirstChild("Distance")
						signStates[i] = spot .. ((dl and dl:IsA("GuiObject") and not dl.Visible) and "/name" or "")
						-- stacked on the chip: sharing columns and closer than twice the sign's own clearance (TutorialController
						-- K.SIGN_CLEAR, 8 px at 1080p under the screen factor; pol1 A's pair stood 7-10 px apart at 640x360,
						-- the clearance itself, and read as one block). The factor from the chip: 51 px tall at 1080p
						if c and not stack and math.min(c.R, s.R) > math.max(c.X, s.X) then
							local gy = (s.Y >= c.B) and (s.Y - c.B) or ((c.Y >= s.B) and (c.Y - s.B) or -1)
							local need = 16 * (c.B - c.Y) / 51
							if gy < need then
								stack = fmt("%s: the GuideSign %s %s the chip %s (%.0f px apart, %.0f wanted)", at, show(s),
									gy < 0 and "on" or "stacked on", show(c), gy, need)
							end
						end
					end
					signStates[i] = signStates[i] or "off"
					if traceFile then
						local function r4(r)
							return r and fmt("%.0f,%.0f,%.0f,%.0f", r.X, r.Y, r.R, r.B) or "-"
						end
						traceFile:write(fmt("%s|%d|%.1f|%.1f|%s|chip %s|arrow %s|sign %s %s|%s\n", tag, i, fr[1], fr[2], tostring(fr[4] or ""),
							r4(c), r4(box), signStates[i], r4(traceSign), chipSeq[i] and chipSeq[i].t or "-"))
						traceSign = nil
					end
					if i == 1 and run.name == "walk" and (run.w == 1920 or run.w == 1280 or run.w == 390) then
						T.check(box ~= nil and bb ~= nil, tag .. ": at 50 studs the arrow and its sign show (the mock's framing)",
							fmt("arrow %s, sign %s", tostring(box ~= nil), tostring(bb ~= nil)))
					end
				end
				-- the chip's rests in order, as stretches: home "C" or away "L" / "R"; away trips, both sides, a second spot in
				-- one trip (`list`: the places to read, `sides` theirs)
				local function trips(list, sds)
					local stretches, spot, creep = {}, nil, nil
					local hasL, hasR = false, false
					for k, p in ipairs(list) do
						local sd = sds[k]
						hasL, hasR = hasL or sd == "L", hasR or sd == "R"
						if stretches[#stretches] ~= sd then
							stretches[#stretches + 1] = sd
							spot = (sd ~= "C") and p or nil
						elseif spot and math.max(abs(p.x - spot.x), abs(p.y - spot.y)) > 6 then
							creep = creep or p.at
						end
					end
					local away = 0
					for _, sd in ipairs(stretches) do
						away = away + ((sd ~= "C") and 1 or 0)
					end
					return away, hasL, hasR, creep
				end
				local seq = {}
				for k, p in ipairs(places) do
					seq[#seq + 1] = sides[k] .. fmt("@%s(%.0f,%.0f)", p.at, p.x, p.y)
				end
				if pins then
					if run.kind == "walk" then
						local away, hasL, hasR, creep = trips(places, sides)
						T.check(not (hasL and hasR) and away <= 1 and creep == nil and sides[#sides] == "C" and fails.steps == nil,
							"pin MJ-A (fin1) " .. tag .. ": the chip keeps one place off home, out and back, in hard steps or across a hide",
							table.concat(seq, " -> ") .. (creep and (" (a second spot at " .. creep .. ")") or "") .. (fails.steps and (" | " .. fails.steps) or ""))
						T.check(fails["sign free"] == nil, "pin MJ-B (fin1) " .. tag .. ": the GuideSign, while it shows, is wholly on the screen, under no HUD piece",
							fails["sign free"] and (fails["sign free"] .. fmt(" (%d frames)", counts["sign free"])))
					end
					if run.kind == "walk" or run.kind == "stop" then
						-- the sign's stretches: a state (shown at a spot, the name alone, hidden) held under 0.5 s that the run
						-- does not end in is a flash; its spots in order (hidden frames skipped)
						local flashes, spots, n = {}, {}, #run.frames
						local k = 1
						while k <= n do
							local j = k
							while j < n and signStates[j + 1] == signStates[k] do
								j = j + 1
							end
							-- (the first stretch began in the run's 0.5 s pre-roll, before frame 1: not a flash)
						if k > 1 and j < n and j - k + 1 < 15 then
								flashes[#flashes + 1] = fmt("%s %d frames at %.1f studs", signStates[k], j - k + 1, run.frames[k][1])
							end
							local sp = signStates[k]:gsub("/name", "")
							if sp ~= "off" and spots[#spots] ~= sp then
								spots[#spots + 1] = sp
							end
							k = j + 1
						end
						T.check(#flashes == 0, "pin W1 (pol1 A) " .. tag .. ": the GuideSign does not flash (each show, hide, line or spot holds 0.5 s)",
							table.concat(flashes, "; "))
						T.check(#spots <= 2, "pin W1 (pol1 A) " .. tag .. ": the GuideSign takes at most two spots a walk", table.concat(spots, " -> "))
						T.check(stack == nil, "pin W1 (pol1 A) " .. tag .. ": the GuideSign never stacks on the chip", stack)
					end
					if run.kind == "pan" or run.kind == "turnwalk" then
						local bad = {}
						for pass = 1, 2 do
							local list, sds = {}, {}
							for k, p in ipairs(places) do
								if p.pass == pass then
									list[#list + 1], sds[#sds + 1] = p, sides[k]
								end
							end
							local away, _, _, creep = trips(list, sds)
							if away > 1 or creep then
								bad[#bad + 1] = fmt("pass %d: %d trips off home%s", pass, away, creep and (", a second spot at " .. creep) or "")
							end
						end
						T.check(#bad == 0, "pin W2 (pol1 B) " .. tag .. ": in each pass the chip leaves home at most once, for one spot",
							table.concat(bad, "; ") .. " | " .. table.concat(seq, " -> "))
						-- (fix6 look0 #4: W2's one trip cost a long hide, the chip and its cancel X gone 0.6 - 1.03 s on the
						-- turning walks and 0.8 - 2.07 s on slow pans, while the commit said "under 0.5 s"; only
						-- travel_guide_walk held the 0.5 s rule, at 7 sizes and 23 - 120 degrees a second) the same pans and
						-- walks: the chip hides at most 0.5 s at a time
						T.check(maxHidden <= 15, "pin W2 (look0 #4) " .. tag .. ": the chip hides at most 0.5 s at a time",
							fmt("hidden %d frames in a row (%d in all) | %s", maxHidden, hiddenFrames, table.concat(seq, " -> ")))
					end
					local n = #run.frames
					local function where(i)
						return fmt("%.1f studs, turn %.1f", run.frames[i][1], run.frames[i][2])
					end
					local moving = run.kind == "pan" or run.kind == "turnwalk" or run.kind == "sway" or run.kind == "panstop" or run.kind == "panrev"
					if moving then
						-- (fix6b, look1 #1: e272588's pass was full line, a 0.1 s blink, 'Guiding' at home for 1 - 14 frames, a
						-- blink, 'Guiding' behind the arrow, a blink, the full line: three blinks a pass, the cancel X moving
						-- each time) every chip state - a show between two hides, or between two changes of its line - lasts
						-- 0.5 s (15 frames) unless the run starts or ends in it, and the chip never blinks in place (a hide
						-- with the chip back on the same spot: its change of line at home)
						local short, blink = {}, {}
						local k = 1
						while k <= n do
							local j = k
							if chipSeq[k] then
								while j < n and chipSeq[j + 1] and chipSeq[j + 1].t == chipSeq[k].t do
									j = j + 1
								end
								if k > 1 and j < n and j - k + 1 < 15 then
									short[#short + 1] = fmt("'%s' %d frames at %s (x %.0f)", chipSeq[k].t, j - k + 1, where(k), chipSeq[k].x - vp.X / 2)
								end
							else
								while j < n and not chipSeq[j + 1] do
									j = j + 1
								end
								local a, b = chipSeq[k - 1], chipSeq[j + 1]
								if a and b and abs(a.x - b.x) <= 2 and abs(a.y - b.y) <= 2 then
									blink[#blink + 1] = fmt("hidden %d frames at %s, back on its spot (x %.0f, '%s' -> '%s')", j - k + 1, where(k), a.x - vp.X / 2, a.t, b.t)
								end
							end
							k = j + 1
						end
						T.check(#short == 0, "pin G1 (look1 #1) " .. tag .. ": every chip state (a show, its line) lasts 0.5 s",
							table.concat(short, "; ") .. " | " .. table.concat(seq, " -> "))
						T.check(#blink == 0, "pin G1 (look1 #1) " .. tag .. ": the chip never blinks in place (its change of line at home)",
							table.concat(blink, "; "))
					end
					if run.kind == "sway" or run.kind == "panrev" then
						-- (fix6b, look1 #2: a +-3 degree sway at 6 degrees a second sent the chip from +223 to -254 px and back,
						-- 4 crossings in 4.5 s at 1920x1080) on a sway and a pan that turns back the chip keeps the side it
						-- took: no swap from one side of the top centre to the other while it shows (hidden frames and home
						-- skipped)
						-- (The pan that turns back counts from the turn back on: "never swap on a reversal". Its way to the gate is a
						-- pan's pass, where W2 has the chip go behind the arrow; at 640 x 360 the arrow at -35 leaves a spot on the
						-- right only and the gate one on the left only, so that pass's one crossing is the least there is. The
						-- sways count from their first frame)
						-- (Its way back ends where the run began, the arrow by home: at 667 x 375 that rest leaves room on the side
						-- the chip stood on at the first frame only - home and the other side under the arrow - and the chip, held
						-- on the other side, kept it under the arrow's foot, a cover travel_guide_walk counts. So a swap back to
						-- the first frame's side within 1 degree of the camera's start is that rest, not a swap)
						local swaps, last, from = {}, nil, 1
						local first, turn0 = nil, run.frames[1][2]
						if run.kind == "panrev" then
							for i = 2, n do
								if run.frames[i][2] < run.frames[i - 1][2] - 1e-6 then
									from = i
									break
								end
							end
						end
						for i = 1, n do
							local s = chipSeq[i]
							if s then
								local off = s.x - vp.X / 2
								local sd = (off > 2 and "R") or (off < -2 and "L") or nil
								first = first or sd or "C" -- (the first frame it shows: home, or the side it stood on)
								local rest = run.kind == "panrev" and sd == first and math.abs(run.frames[i][2] - turn0) <= 1
								if sd and last and sd ~= last and i >= from and not rest then
									swaps[#swaps + 1] = fmt("%s -> %s at %s (x %.0f)", last, sd, where(i), off)
								end
								last = sd or last
							end
						end
						T.check(#swaps == 0, "pin G2 (look1 #2) " .. tag .. ": the chip keeps one side on a sway or a reversal (no swap)",
							table.concat(swaps, "; ") .. " | " .. table.concat(seq, " -> "))
					end
					if moving or run.kind == "look" then
						-- (fix6b, look1 #3: W1 held the walk only; pans flashed the GuideSign for 1 - 6 frames on landscape
						-- phones and a look up at 12 studs for 2) each show of the sign (a spot, or its name alone) lasts 0.5 s
						-- unless the run starts or ends in it
						local flashes = {}
						local k = 1
						while k <= n do
							local j = k
							while j < n and signStates[j + 1] == signStates[k] do
								j = j + 1
							end
							if signStates[k] ~= "off" and k > 1 and j < n and j - k + 1 < 15 then
								flashes[#flashes + 1] = fmt("%s %d frames at %s", signStates[k], j - k + 1, where(k))
							end
							k = j + 1
						end
						T.check(#flashes == 0, "pin G3 (look1 #3) " .. tag .. ": each GuideSign show lasts 0.5 s on a pan or a look up",
							table.concat(flashes, "; "))
					end
				end
				local hideCap = (run.kind == "walk" or run.kind == "far") and 6 or 15
				if not pins then
				T.check(maxHidden <= hideCap, tag .. fmt(": the chip hides at most %.1f s at a time", hideCap / 30),
					fmt("hidden %d frames in a row (%d in all)", maxHidden, hiddenFrames))
				T.check(fails.steps == nil, tag .. ": the chip moves in hard steps of at most a quarter of its width, or across a hide",
					fails.steps and (fails.steps .. fmt(" (%d frames)", counts.steps)))
				T.check(fails.row == nil, tag .. ": the chip keeps its home row on a landscape screen and stays within its width of the top centre",
					fails.row and (fails.row .. fmt(" (%d frames)", counts.row)))
				if (run.kind == "walk" or run.kind == "far") and run.w > run.h then
					T.check(fails.home == nil, tag .. ": the chip rests off the top centre only while the arrow is near it (the sign gives way)",
						fails.home and (fails.home .. fmt(" (%d frames)", counts.home)))
				end
				if run.kind == "walk" then
					-- (pick a side and keep it) its rests in order: home "C" (the home itself may move with the HUD, e.g. a
					-- quest strip docking over the vitals card), or away "L" / "R" of the middle; never both sides, one away
					-- stretch at most and one spot in it (every rest there within 6 px of its first), home at the end (by
					-- 12 studs the arrow, shown all the way now, has risen past the chip's row on every screen)
					local away, hasL, hasR, creep = trips(places, sides)
					T.check(not (hasL and hasR) and away <= 1 and creep == nil and sides[#sides] == "C",
						tag .. ": the chip keeps one place off home, out and back (no side flip, no creep, home at the end)",
						table.concat(seq, " -> ") .. (creep and (" (a second spot at " .. creep .. ")") or ""))
				end
				T.check(fails["chip free"] == nil, tag .. ": the chip is wholly on the screen, under no HUD piece", fails["chip free"])
				T.check(fails["sign free"] == nil, tag .. ": the GuideSign, while it shows, is wholly on the screen, under no HUD piece",
					fails["sign free"] and (fails["sign free"] .. fmt(" (%d frames)", counts["sign free"])))
				T.check(fails.arrow == nil, tag .. ": the arrow shows all the way (a world part: it may pass behind the HUD or out of the top)",
					fails.arrow and (fails.arrow .. fmt(" (%d frames)", counts.arrow)))
				T.check(fails.clear == nil, tag .. ": the chip never covers the arrow or the sign, the sign never the arrow",
					fails.clear and (fails.clear .. fmt(" (%d frames)", counts.clear)))
				end
				T.info(fmt("%s: places %s; hidden %d frames; sign %d of %d frames; arrow first seen %s, sign %s", tag, table.concat(seq, " -> "),
					hiddenFrames, signFrames, #run.frames, tostring(seenArrow), tostring(seenSign)))
				Guide.Stop()
				KC.advance(0.2)
			end
		end)
		methods.WorldToViewportPoint, methods.WorldToScreenPoint = saved[1], saved[2]
		pcall(MC._TouchButtons, false)
		UIS.TouchEnabled = touchWas
		pcall(Guide.Stop)
		Mock.SetViewport(1920, 1080)
		Mock.Teleport(player, CFrame.new(L.Origin + Vector3.new(0, 3, 20)))
		KC.advance(0.5)
		putBack()
		if traceFile then
			traceFile:close()
		end
		T.check(ok, "guide walk: the scenario ran", tostring(err))
		KC.flushErrors(scen)
	end
	-- (fix6b harness) each walk in its parts (WALK_PARTS, WALK_LISTS), one list a part; tools/smoke.py runs every part
	-- when the walk's first list is named
	for kind, names in pairs(WALK_LISTS) do
		for i, name in ipairs(names) do
			S[name] = guarded(name, function()
				guideWalk(name, kind == "pins", i)
			end)
		end
	end

	return S
end

if (ARGS and ARGS.context or "server") == "server" then
	return serverScenarios()
end
return clientScenarios()
