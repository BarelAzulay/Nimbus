-- smoke_kitb_ws_c.lua: kit-b world signs, lane C (the 2026-11-27 audit of the old-look world signs, items 20-30; the
-- owner's "home gui's havent changed"). No new look: the arena's, the portal's, the course's and the downed marker's signs
-- are the kit's stone card tier (WorldTag: a Sign.Stone face, a mitred wood SignEdge, a Lip, ink text with no outline).
-- Server world; registered on its own line in tools/smoke.py.
--   world_signs_kit_c   (server, after boot) per converted builder: no UICorner / UIGradient under its gui, its card (a
--                       tag's Plate, a board's Panel) a kit block (an opaque face, a mitred SignEdge stroke, a visible Lip),
--                       its texts present in the kit's ink (no outline, 4.5:1 on the face under them):
--                       ArenaBuilder: the duel pad tags (PadTag), ARENA EVENTS (BoardGui, its Double Rewards pill and the
--                       raid HP well kit blocks too), TROPHY LEADERS (LeaderGui, the three medal rank blocks), the BATTLE
--                       ARENA gate sign, the bridge arch's two faces, the stand-in gate tag (WorldStyle.BuildGate failing:
--                       its pill a tinted kit block, Pill.Label found as Gates.build reads it); PortalService: the eye-level
--                       countdown face (Disc / TopPill / CountPill blocks) and its stand-in PortalBillboard (a gate with no
--                       GateTag: the status pill and the badge lip turn gold while counting down); CourseBuilder: every
--                       hint tag (CANNON / HOLD THE PLATE / Checkpoint n/N / GOAL / DASH!, the dash line wide enough for
--                       every device's text), the HOW TO CLIMB / TEAMWORK boards and the START / FINISH beams;
--                       DamageService: the DOWNED marker
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local fmt = string.format

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

local function plain(s)
	return (tostring(s or ""):gsub("<[^>]->", ""))
end

-- the round corners and gradients under `root` -> list
local function oldKit(root)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("UICorner") and (d.CornerRadius.Scale > 0 or d.CornerRadius.Offset > 0) then
			out[#out + 1] = "corner on " .. d.Parent.Name
		elseif d:IsA("UIGradient") then
			out[#out + 1] = "gradient on " .. d.Parent.Name
		end
	end
	return out
end

-- a kit block: an opaque face, the mitred SignEdge stroke, a visible Lip
local function isBlock(o)
	if not o then
		return false, "missing"
	end
	local edge = o:FindFirstChild("SignEdge")
	local lip = o:FindFirstChild("Lip")
	local ok = o.BackgroundTransparency == 0 and edge ~= nil and edge:IsA("UIStroke") and edge.LineJoinMode == Enum.LineJoinMode.Miter
		and edge.Thickness >= 1 and lip ~= nil and lip:IsA("Frame") and lip.Visible and lip.Size.Y.Offset > 0
	return ok, fmt("%s: edge %s, lip %s", o.Name, edge and tostring(edge.Thickness) or "-", lip and tostring(lip.Size.Y.Offset) or "-")
end

local function outlined(d)
	for _, c in ipairs(d:GetChildren()) do
		if c:IsA("UIStroke") and c.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual and c.Enabled ~= false and c.Transparency < 1 then
			return true
		end
	end
	return d.TextStrokeTransparency < 0.5
end

-- the face a text reads on: its nearest opaque ancestor inside `gui`
local function faceOf(d, gui)
	local cur = d.Parent
	while cur and cur ~= gui do
		if cur:IsA("GuiObject") and cur.BackgroundTransparency < 0.3 then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

-- One builder's gui: no old kit, `cards` (names found under gui) kit blocks, every `want` text there in ink on a kit
-- face. -> ok (a T.check per point)
local function audit(label, gui, cards, want)
	if not T.check(gui ~= nil, label .. ": built") then
		return false
	end
	local bad = oldKit(gui)
	T.check(#bad == 0, label .. ": no UICorner / UIGradient under " .. gui.Name, table.concat(bad, ", "))
	for _, name in ipairs(cards) do
		local card = gui:FindFirstChild(name, true)
		local ok, why = isBlock(card)
		T.check(ok, label .. ": " .. name .. " is a kit block (opaque face, mitred SignEdge, Lip)", why)
	end
	local texts = {}
	local inkBad = {}
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("TextLabel") and plain(d.Text) ~= "" then
			texts[plain(d.Text):upper()] = d
			local face = faceOf(d, gui)
			local ratio = face and SmokeCommon.Contrast.Ratio(d.TextColor3, face.BackgroundColor3) or 0
			if outlined(d) or not (face and face:FindFirstChild("SignEdge")) or ratio < 4.5 then
				inkBad[#inkBad + 1] = fmt("'%s' (outline %s, on %s, %.1f:1)", plain(d.Text):sub(1, 24), tostring(outlined(d)), face and face.Name or "nothing", ratio)
			end
		end
	end
	local missing = {}
	for _, w in ipairs(want) do
		if not texts[w:upper()] then
			missing[#missing + 1] = w
		end
	end
	T.check(#missing == 0, label .. ": its texts are there", "missing " .. table.concat(missing, ", "))
	T.check(#inkBad == 0, label .. ": every text is the kit's ink on a kit block (no outline, 4.5:1)", table.concat(inkBad, "; "))
	return true
end

local function serverScenarios()
	local S = {}
	local K = _G.K

	S.world_signs_kit_c = guarded("world_signs_kit_c", function()
		local Theme, Config = shared("Theme"), K.config()
		local Sign = Theme and Theme.Sign
		if not T.check(Sign ~= nil and Config ~= nil, "world signs C: (setup) Theme / Config load") then
			return
		end
		Mock.SetViewport(1920, 1080)
		K.advance(0.3)

		------------------------------------------------------------------ ArenaBuilder (items 22-26)
		local arena = workspace:FindFirstChild("BattleArena")
		if T.check(arena ~= nil, "world signs C: (setup) the BattleArena is built") then
			local pads = {}
			for _, d in ipairs(arena:GetDescendants()) do
				if d:IsA("BillboardGui") and d.Name == "PadTag" then
					pads[#pads + 1] = d
				end
			end
			T.check(#pads >= 2, "world signs C: the duel rings carry pad tags", tostring(#pads))
			for i, gui in ipairs(pads) do
				if i <= 2 then
					audit("arena pad tag " .. i, gui, { "Plate" }, { "Challenge a player" })
				end
				local plate = gui:FindFirstChild("Plate")
				T.check(plate ~= nil and plate.AutomaticSize == Enum.AutomaticSize.None and plate.Size.X.Offset > 0
					and plate.Size.X.Offset + 6 <= gui.Size.X.Offset and plate.Size.Y.Offset + 6 <= gui.Size.Y.Offset,
					"world signs C: pad tag " .. i .. "'s card is measured (no AutomaticSize) and fits its 300 x 110 gui",
					plate and tostring(plate.Size) or "no plate")
			end
			local board = arena:FindFirstChild("BoardGui", true)
			if audit("arena event board", board, { "Panel", "DoublePill", "RaidHpBar" }, { "ARENA EVENTS" }) then
				local lip = board.Panel:FindFirstChild("Lip")
				T.check(lip and lip.BackgroundColor3 == Sign.Red, "world signs C: the event board's lip is the arena red", lip and tostring(lip.BackgroundColor3) or "-")
			end
			local leaders = arena:FindFirstChild("LeaderGui", true)
			if audit("arena trophy board", leaders, { "Panel", "RankBlock" }, { "TROPHY LEADERS", "Win duels to earn trophies" }) then
				local medals = 0
				for _, d in ipairs(leaders:GetDescendants()) do
					if d.Name == "RankBlock" and isBlock(d) then
						medals = medals + 1
					end
				end
				T.check(medals == 3, "world signs C: the top three ranks sit in medal blocks", tostring(medals))
			end
			local gateSign = arena:FindFirstChild("GateSign", true)
			audit("arena gate sign", gateSign and gateSign:FindFirstChildOfClass("SurfaceGui"), { "Panel" }, { "BATTLE ARENA", "Duels and boss raids" })
			local arch = arena:FindFirstChild("ArchSign", true)
			local faces = {}
			for _, g in ipairs(arch and arch:GetChildren() or {}) do
				if g:IsA("SurfaceGui") then
					faces[g.Face.Name] = g
				end
			end
			audit("bridge arch (street side)", faces.Front, { "Panel" }, { "BATTLE ARENA" })
			audit("bridge arch (forum side)", faces.Back, { "Panel" }, { "TO THE PLAZA" })
		end

		-- the stand-in gate (item 26): WorldStyle.BuildGate fails, Gates.build builds its own column gate and tag
		local AB = K.mod("ArenaBuilder")
		local WorldStyle = shared("WorldStyle")
		if T.check(AB and AB._Ring and type(AB._Ring.buildPortal) == "function" and WorldStyle, "world signs C: (setup) ArenaBuilder._Ring.buildPortal and WorldStyle load") then
			local folder = Instance.new("Folder")
			folder.Name = "WsCStandIn"
			folder.Parent = workspace
			local saved = WorldStyle.BuildGate
			WorldStyle.BuildGate = function()
				error("world signs C: the stand-in path")
			end
			local ok, err = pcall(AB._Ring.buildPortal, folder, { GateSites = { Ring = CFrame.new(9100, 900, 9100) }, GatesFolder = folder })
			WorldStyle.BuildGate = saved
			if T.check(ok, "world signs C: the stand-in Ring gate builds", tostring(err)) then
				local tag = folder:FindFirstChild("GateTag", true)
				if audit("arena stand-in gate tag", tag, { "Plate", "Pill" }, { AB._Ring.Title or "" }) then
					local pill = tag:FindFirstChild("Pill", true)
					local label = pill and pill:FindFirstChild("Label")
					T.check(label ~= nil and pill:GetAttribute("WorldTag") == true and pill.Lip.BackgroundColor3 == Sign.Gold,
						"world signs C: the stand-in's pill is a tinted kit block (its lip the gate's gold) holding Pill.Label")
				end
			end
			folder:Destroy()
		end

		------------------------------------------------------------------ PortalService (items 20, 21)
		local face = nil
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "CountdownFace" then
				face = d
				break
			end
		end
		local faceGui = face and face:FindFirstChildOfClass("SurfaceGui")
		if faceGui then
			-- (the face is hidden on an empty pad; its texts are built all the same, and an earlier scenario's party may have
			-- left any count on them: checked by name)
			if audit("portal countdown face", faceGui, { "Disc", "TopPill", "CountPill" }, {}) then
				local missing = {}
				for _, name in ipairs({ "NumeralLabel", "TopLabel", "CountLabel" }) do
					local l = faceGui:FindFirstChild(name, true)
					if not (l and l:IsA("TextLabel") and plain(l.Text) ~= "") then
						missing[#missing + 1] = name
					end
				end
				T.check(#missing == 0, "portal countdown face: its numeral, ribbon and head count texts are there", "missing " .. table.concat(missing, ", "))
			end
		else
			T.fail("world signs C: the Obby portal has its CountdownFace")
		end
		local PS = K.mod("PortalService")
		if T.check(PS and type(PS._BuildCards) == "function", "world signs C: (setup) PortalService._BuildCards") then
			local model = Instance.new("Model")
			model.Name = "WsCPortal"
			model.Parent = workspace
			local zone = Instance.new("Part")
			zone.Name = "Zone"
			zone.Anchored = true
			zone.CanCollide = false
			zone.Transparency = 1
			zone.Size = Vector3.new(12, 14, 12)
			zone.CFrame = CFrame.new(9300, 900, 9300)
			zone.Parent = model
			local info = { Model = model, Zone = zone }
			local ok, party = pcall(PS._BuildCards, info, 2, "Countdown")
			if T.check(ok and info.Billboard ~= nil, "world signs C: the stand-in PortalBillboard builds", tostring(party)) then
				local gui = info.Billboard
				local diff = Config.Difficulties[1]
				audit("portal stand-in billboard", gui, { "Plate", "StatusPill" }, { tostring(diff.DisplayName or diff.Id), "2/" .. Config.Match.MaxPlayers .. " players", "Step in to play" })
				local gold = Theme.Colors.Gold or Theme.Colors.Token
				local pill = gui:FindFirstChild("StatusPill", true)
				T.check(gui.Name == "PortalBillboard" and gui.MaxDistance == 55 and pill and pill.Lip.BackgroundColor3 == gold,
					"world signs C: the stand-in billboard keeps its name and 55-stud range; its pill's lip turns gold while counting down")
				local plate = gui:FindFirstChild("Plate")
				T.check(plate and plate.Size.X.Offset > 0 and plate.Size.X.Offset <= gui.Size.X.Offset and plate.Size.Y.Offset <= gui.Size.Y.Offset,
					"world signs C: the stand-in billboard's card is measured and fits its gui", plate and tostring(plate.Size) or "-")
				local disc = info.CountdownFace and info.CountdownFace:FindFirstChild("Disc", true)
				T.check(disc and disc.Lip.BackgroundColor3 == gold and disc.SignEdge.Color == Sign.Wood,
					"world signs C: the stand-in's face badge has a gold lip while counting down, its edge wood")
			end
			model:Destroy()
		end

		------------------------------------------------------------------ CourseBuilder (items 27-29)
		local CB = K.mod("CourseBuilder")
		local help = Config.Course and Config.Course.Help
		if T.check(CB ~= nil and help ~= nil, "world signs C: (setup) CourseBuilder loads") then
			local holder = Instance.new("Folder")
			holder.Name = "WsCCourses"
			holder.Parent = workspace
			local seen, tags, boards, dashWide = {}, 0, 0, true
			for i, diff in ipairs(Config.Difficulties) do
				for seed = 1, 2 do
					local okL, layout = pcall(CB.GenerateLayout, diff.Id, seed)
					local okB, ci = false, nil
					if okL and layout then
						okB, ci = pcall(CB.Build, layout, Vector3.new(90000 + i * 2500 + seed * 1200, 1200, 0), holder)
					end
					if okB and type(ci) == "table" and ci.Folder then
						for _, d in ipairs(ci.Folder:GetDescendants()) do
							if d:IsA("BillboardGui") and d.Name == "HintTag" then
								tags = tags + 1
								local first = ""
								for _, l in ipairs(d:GetDescendants()) do
									if l:IsA("TextLabel") and l.LayoutOrder == 1 then
										first = plain(l.Text):upper()
									end
								end
								local key = first:match("^CHECKPOINT") and "CHECKPOINT" or first
								if not seen[key] then
									seen[key] = true
									audit("course hint tag " .. key, d, { "Plate" }, { first })
								end
								-- the dash line: wide enough for every device's text
								for _, l in ipairs(d:GetDescendants()) do
									if l:IsA("TextLabel") and l:GetAttribute("HelpKey") == "Dash" then
										for _, dev in ipairs({ "Keyboard", "Touch", "Gamepad" }) do
											local need = math.ceil(Theme.Measure(help.Dash[dev], "Body", l.TextSize).X)
											if need > d.Plate.Size.X.Offset then
												dashWide = false
											end
										end
									end
								end
							elseif d:IsA("SurfaceGui") and d.Parent and (d.Parent.Name == "InfoBoard" or d.Parent.Name == "StartBeam" or d.Parent.Name == "FinishBeam") then
								boards = boards + 1
								local word = ({ StartBeam = "START", FinishBeam = "FINISH" })[d.Parent.Name]
								local key = word or (d:FindFirstChild("Text", true) and plain(d:FindFirstChild("Text", true).Text):upper()) or "?"
								if not seen["board " .. key] then
									seen["board " .. key] = true
									audit("course board " .. key, d, { "Panel" }, word and { word } or {})
									T.check(d.Parent.Color == Sign.Wood, "world signs C: the " .. d.Parent.Name .. " part is wood (no navy board)", tostring(d.Parent.Color))
								end
							end
						end
					end
				end
			end
			holder:Destroy()
			local missing = {}
			for _, key in ipairs({ "CHECKPOINT", "GOAL", "DASH!", "board START", "board FINISH", "board HOW TO CLIMB", "board TEAMWORK" }) do
				if not seen[key] then
					missing[#missing + 1] = key
				end
			end
			T.check(#missing == 0, fmt("world signs C: the course signs are all checked (%d hint tags, %d boards)", tags, boards), "missing " .. table.concat(missing, ", "))
			T.check(dashWide, "world signs C: a dash hint's card is wide enough for every device's dash text")
			T.info(fmt("*world signs C: course hint kinds seen: %s", (function()
				local list = {}
				for k in pairs(seen) do
					list[#list + 1] = k
				end
				table.sort(list)
				return table.concat(list, ", ")
			end)()))
		end

		------------------------------------------------------------------ DamageService (item 30)
		local MS, DSv = K.mod("MatchService"), K.mod("DamageService")
		if MS and DSv and K.startMatch then
			local pair = K.freshPlayers(2, "WsCDown")
			local m = K.startMatch(Config.Difficulties[1].Id, pair)
			if m and K.toPlaying(m) then
				if K.waitNotInvulnerable then
					K.waitNotInvulnerable(pair[2])
				end
				K.advance((Config.Damage and Config.Damage.IFrames or 1) + 0.2)
				DSv.Damage(pair[2], 10000, "Void", { IgnoreIFrames = true })
				K.advance(0.4)
				local char = pair[2].Character
				local marker = char and char:FindFirstChild("NimbusDownedMarker", true)
				if audit("downed marker", marker, { "Plate", "TitlePill" }, { "DOWNED", "reach the next checkpoint!" }) then
					T.check(marker.AlwaysOnTop == true and marker.MaxDistance == 250 and marker.Size == UDim2.fromOffset(320, 100),
						"world signs C: the downed marker keeps AlwaysOnTop, its 250-stud range and its 320 x 100 gui")
				end
			else
				T.warn("world signs C: the match did not reach Playing; the downed marker was not checked")
			end
			K.endAllMatches(pair)
			K.removePlayers(pair)
		else
			T.warn("world signs C: no MatchService / DamageService; the downed marker was not checked")
		end
		K.flushErrors("world_signs_kit_c")
	end)

	return S
end

if (ARGS and ARGS.context or "server") == "server" then
	return serverScenarios()
end
return {}
