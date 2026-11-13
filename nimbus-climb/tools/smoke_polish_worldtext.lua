-- smoke_polish_worldtext.lua: the World text rule (ARCHITECTURE_V3.md; playtest polish key "worldtext": "letters too
-- small, when you zoom a little you can barely read it"). Loaded by tools/smoke.py in BOTH worlds; ARGS.context picks
-- the half:
--   polish_worldtext          (server) a census of every BillboardGui / SurfaceGui put into the workspace during the
--                             whole server run (lobby signs, home nameplates, podium tags, NPC nameplates, portal tags,
--                             courses, downed markers; one destroyed before the audit is checked from a snapshot taken
--                             as it was destroyed), plus fresh course builds of every difficulty and a downed marker
--                             made here. Billboards: pixel-sized (offset UDim2: no studs-scaled billboard with a fixed
--                             TextSize), no TextScaled / TextTruncate, names >= 22 px and info lines >= 18 px, every text
--                             outlined and on a solid plate, the plate compact (sized to its content, no huge empty
--                             panel), LightInfluence 0, MaxDistance 50-150 (AlwaysOnTop beacons may reach further; the
--                             2026-11-12 card range, named exceptions: gate and portal cards GateTag / PortalBillboard
--                             exactly 55 (2026-11-13 owner: 55, was 45; the arena forum's Portal_Return 110, its
--                             documented far-read exception), the
--                             own follower's pet card exactly 25 (2026-11-13 owner: 25, was 15), the Food Bowl sign >= 40). Surface
--                             signs: 40-60 px per stud, LightInfluence 0, no TextScaled, the biggest line >= 0.95 stud
--                             (not on a label strip of info lines only: LABEL_STRIPS, the egg row's RarityStrip) and every
--                             line >= 0.6 stud, the text fits its box. The home nameplate: "Free home" /
--                             "Press E at the gate" with the "+" icon; once claimed with E at the gate (Phase 2) the
--                             owner's name, "Home Level <n>", the headshot (Players:GetUserThumbnailAsync, once per user,
--                             cached) or the silhouette when the request fails; back to free when the owner leaves;
--                             readable from ~80 studs; the "No. N" gate signs; the podium tag of the best pet.
--   client_polish_worldtext   (client, 1920x1080) the tutorial guide sign and the NPC nameplates as the client
--                             controllers show them (their UIScale included); the Phase 4 pet cards (PetCard, in the
--                             PlayerGui): own and another player's follower cards and a ready card with its EVOLVE! pill,
--                             "Lv" >= 22 px with a stroke, every text on a compact solid plate, the own follower's card
--                             at exactly 15 studs (the 2026-11-12 card range), another player's within 50-150.
-- The Storm Altar (another engineer's file, audited by smoke_storm.lua) and transient damage numbers are reported only,
-- except the altar's return sign (lobby shop Task 13): the tag rule on the Part fallback ("To the Plaza"), the full sign
-- rule (title >= 0.95 stud) on the dressed ring's 4 x 1 board ("Plaza", shop-area polish).
-- Players:GetUserThumbnailAsync is the mock's (lobby-shop Task 24: content + isReady, Mock.ThumbnailCalls counts the
-- calls, Mock.ThumbnailFail fails them); this file reads those counters as deltas (it used to add its own stub, which
-- stopped being installed once the mock had the method).
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local NAME_MIN = 22 -- px at 1080p
local INFO_MIN = 18
local TITLE_STUDS = 0.95 -- surface signs: the biggest line
local INFO_STUDS = 0.6
-- label strips: surface signs of info lines only, no title line (ARCHITECTURE_V3's World text rule: "~1 stud for titles and
-- ~0.6 stud for info lines"), so the title floor does not apply to them; every other rule does (shop-area 16.17.2: the egg
-- row's RarityStrip, seven 0.6-stud rarity labels on the shelf's 0.8-stud front)
local LABEL_STRIPS = { RarityStrip = true }
-- the card range (2026-11-12, slop-audit win 2; ARCHITECTURE_V3.md World text rule): only the range shrank, the text keeps
-- its pixel size. Gate and portal cards show within exactly GATE_RANGE studs (WorldStyle.TagRange); the arena forum's
-- Return gate keeps RETURN_RANGE (the forum's lone way home stands ~100 studs from the colosseum's main gate); the own
-- follower's pet card shows within exactly OWN_FOLLOWER_RANGE (PetCard.Modes.Follower). Every other tag keeps 50-150.
local GATE_RANGE = 55 -- 2026-11-13 owner: 55 (was 45)
local RETURN_RANGE = 110
local OWN_FOLLOWER_RANGE = 25 -- 2026-11-13 owner: 25 (was 15)

----------------------------------------------------------------------------------------------------
-- the audit (both worlds)
----------------------------------------------------------------------------------------------------
local function plain(text)
	return (tostring(text or ""):gsub("<[^>]*>", ""))
end

local function utf8len(s)
	local _, n = s:gsub("[^\128-\191]", "")
	return n
end

local function isText(d)
	return d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")
end

-- (T0 review) the font a sign text is measured with: its Enum font, or nil for a FontFace role (Theme.Faces: Nunito), whose
-- Enum font is only a fallback and which has no advance table (the caller keeps the 0.5 em estimate for those)
local faceRoles = nil
local function measuredFont(d)
	if faceRoles == nil then
		faceRoles = {}
		local inst = Mock.GetPath(ROOTS.shared .. "/Theme")
		local ok, Theme = false, nil
		if inst then
			ok, Theme = pcall(require, inst)
		end
		if ok and type(Theme) == "table" and type(Theme.Faces) == "table" then
			faceRoles = Theme.Faces
		end
	end
	local role = d:GetAttribute("FontRole")
	if role and faceRoles[role] then
		return nil
	end
	return d.Font
end

-- product of the UIScales from `d` up to (and including) the layer collector `gui`
local function scaleWithin(d, gui)
	local s = 1
	local cur = d
	while cur do
		for _, c in ipairs(cur:GetChildren()) do
			if c:IsA("UIScale") then
				s = s * c.Scale
			end
		end
		if cur == gui then
			break
		end
		cur = cur.Parent
	end
	return s
end

local function visibleWithin(d, gui)
	local cur = d
	while cur and cur ~= gui do
		if cur:IsA("GuiObject") and not cur.Visible then
			return false
		end
		cur = cur.Parent
	end
	return true
end

local function outlined(d)
	for _, c in ipairs(d:GetChildren()) do
		if c:IsA("UIStroke") and c.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual and c.Thickness >= 1 and c.Transparency <= 0.5 then
			return true
		end
	end
	return d.TextStrokeTransparency <= 0.5
end

-- the outermost solid GuiObject (BackgroundTransparency <= 0.25) between `d` and `gui`, or nil
local function plateOf(d, gui)
	local found = nil
	local cur = d
	while cur and cur ~= gui do
		if cur:IsA("GuiObject") and cur.BackgroundTransparency <= 0.25 then
			found = cur
		end
		cur = cur.Parent
	end
	return found
end

local function shortPath(inst)
	local name = inst:GetFullName()
	name = name:gsub("^Workspace%.", ""):gsub("^NimbusLobby%.", "")
	if #name > 90 then
		name = "..." .. name:sub(-87)
	end
	return name
end

-- a part's face size in studs (the SurfaceGui canvas at 1 px per stud)
local function faceStuds(part, face)
	local s = part.Size
	if face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		return s.X, s.Z
	elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return s.Z, s.Y
	end
	return s.X, s.Y
end

-- box (px) of a label inside a SurfaceGui from the Size chain, or nil when a layout / AutomaticSize decides it
local function signBox(d, gui, canvasW, canvasH)
	local chain = {}
	local cur = d
	while cur and cur ~= gui do
		chain[#chain + 1] = cur
		cur = cur.Parent
	end
	local w, h = canvasW, canvasH
	for i = #chain, 1, -1 do
		local o = chain[i]
		if o:IsA("GuiObject") then
			if o.AutomaticSize ~= Enum.AutomaticSize.None then
				return nil
			end
			w = w * o.Size.X.Scale + o.Size.X.Offset
			h = h * o.Size.Y.Scale + o.Size.Y.Offset
		end
	end
	return w, h
end

-- The exact MaxDistance a named card must have (the card range above), with its reason; nil = the 50-150 rule.
-- opts.PetMode = the PetCard mode the caller knows the card has ("Follower" = the own follower's card).
local function exactRange(gui, opts)
	if type(opts) == "table" and opts.PetMode == "Follower" then
		return OWN_FOLLOWER_RANGE, "the own follower's pet card"
	end
	if gui.Name == "PortalBillboard" then
		return GATE_RANGE, "a portal card"
	end
	if gui.Name == "GateTag" then
		local ret = gui:FindFirstAncestor("Portal_Return")
		if ret and ret:FindFirstAncestor("BattleArena") then
			return RETURN_RANGE, "the arena Return gate (documented exception)"
		end
		return GATE_RANGE, "a gate card"
	end
	return nil
end

-- Audits one BillboardGui / SurfaceGui. Returns { path, name, kind, texts = n, sizes = {px...}, problems = {...},
-- strings = {...} }; a gui without any visible text gets texts = 0 and no verdict. opts: see exactRange.
local function auditGui(gui, opts)
	local rec = { path = shortPath(gui), name = gui.Name, kind = gui.ClassName, texts = 0, sizes = {}, problems = {}, strings = {} }
	local function bad(msg)
		rec.problems[#rec.problems + 1] = msg
	end
	local texts = {}
	for _, d in ipairs(gui:GetDescendants()) do
		if isText(d) and plain(d.Text):gsub("%s", "") ~= "" and visibleWithin(d, gui) then
			texts[#texts + 1] = d
			rec.strings[#rec.strings + 1] = plain(d.Text)
		end
	end
	rec.texts = #texts
	if #texts == 0 then
		return rec
	end
	local isBoard = gui:IsA("SurfaceGui")
	local pps = isBoard and gui.PixelsPerStud or nil
	local maxPx, minPx = 0, math.huge
	local scaled, noOutline, noPlate, truncating = {}, {}, {}, {}
	local plates, plateList = {}, {}
	for _, d in ipairs(texts) do
		local px = d.TextSize * scaleWithin(d, gui)
		rec.sizes[#rec.sizes + 1] = px
		maxPx = math.max(maxPx, px)
		minPx = math.min(minPx, px)
		if d.TextScaled then
			scaled[#scaled + 1] = "'" .. plain(d.Text):sub(1, 20) .. "'"
		end
		-- a world label sizes itself to its text (or has room for it): a name cut to "Granny ..." reads as broken
		if d.TextTruncate ~= Enum.TextTruncate.None then
			truncating[#truncating + 1] = "'" .. plain(d.Text):sub(1, 20) .. "'"
		end
		if not outlined(d) then
			noOutline[#noOutline + 1] = "'" .. plain(d.Text):sub(1, 20) .. "'"
		end
		if not isBoard then
			local plate = plateOf(d, gui)
			if not plate then
				noPlate[#noPlate + 1] = "'" .. plain(d.Text):sub(1, 20) .. "'"
			elseif not plates[plate] then
				plates[plate] = true
				plateList[#plateList + 1] = plate
			end
		end
	end
	-- (kit-b U7b) a PixelIcon drawn in place of a glyph (an empty label hosting it: the closed bed's star) is a mark of its
	-- size: it counts for the biggest line, not for the smallest
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("Frame") and d.Name == "Icon" and type(d:GetAttribute("PixelIcon")) == "string" and d.Parent and isText(d.Parent)
			and plain(d.Parent.Text) == "" and visibleWithin(d, gui) then
			maxPx = math.max(maxPx, d.Size.Y.Offset * scaleWithin(d, gui))
		end
	end
	rec.maxPx, rec.minPx = maxPx, minPx
	if #scaled > 0 then
		bad("TextScaled text " .. table.concat(scaled, ", "))
	end
	if #noOutline > 0 then
		bad("no outline on " .. table.concat(noOutline, ", "))
	end
	if #truncating > 0 then
		bad("truncating text (TextTruncate) " .. table.concat(truncating, ", "))
	end
	if gui.LightInfluence ~= 0 then
		bad("LightInfluence " .. tostring(gui.LightInfluence))
	end

	if not isBoard then
		local size = gui.Size
		local pixel = size.X.Scale == 0 and size.Y.Scale == 0 and size.X.Offset > 0 and size.Y.Offset > 0
		if not pixel then
			bad(string.format("studs-scaled billboard (Size %s) with fixed TextSize %d-%d", tostring(size), math.floor(minPx), math.floor(maxPx)))
		end
		if maxPx < NAME_MIN - 0.01 then
			bad(string.format("biggest text %.1f px < %d px", maxPx, NAME_MIN))
		end
		if minPx < INFO_MIN - 0.01 then
			bad(string.format("smallest text %.1f px < %d px", minPx, INFO_MIN))
		end
		local md = gui.MaxDistance
		local exact, why = exactRange(gui, opts)
		if exact then
			if md ~= exact then
				bad("MaxDistance " .. tostring(md) .. " (want exactly " .. exact .. ": " .. why .. ")")
			end
		elseif gui.AlwaysOnTop then
			if not (md >= 50) then
				bad("MaxDistance " .. tostring(md))
			end
		elseif not (md >= 50 and md <= 150) and not (gui.Name == "BowlSign" and md >= 40) then -- Phase 5 3.4: the Food Bowl sign 40
			bad("MaxDistance " .. tostring(md) .. " (want 50-150)")
		end
		if #noPlate > 0 then
			bad("not on a solid plate: " .. table.concat(noPlate, ", "))
		end
		-- compact: each plate hugs its content (padding, no huge empty panel) and stays tag-sized
		for _, plate in ipairs(plateList) do
			local ps = plate.AbsoluteSize
			local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
			for _, c in ipairs(plate:GetDescendants()) do
				if c:IsA("GuiObject") and visibleWithin(c, plate) and c.AbsoluteSize.X > 0 and c.AbsoluteSize.Y > 0 then
					local p, s = c.AbsolutePosition, c.AbsoluteSize
					minX, minY = math.min(minX, p.X), math.min(minY, p.Y)
					maxX, maxY = math.max(maxX, p.X + s.X), math.max(maxY, p.Y + s.Y)
				end
			end
			if maxX > minX then
				local slackW, slackH = ps.X - (maxX - minX), ps.Y - (maxY - minY)
				if slackW > 64 or slackH > 40 or ps.X > 600 or ps.Y > 200 then
					bad(string.format("plate %s is %dx%d px for %dx%d px of content", plate.Name, ps.X, ps.Y, maxX - minX, maxY - minY))
				end
			end
		end
	else
		if gui.SizingMode ~= Enum.SurfaceGuiSizingMode.PixelsPerStud or not (pps >= 40 and pps <= 60) then
			bad(tostring(gui.SizingMode) .. " at " .. tostring(pps) .. " px per stud (want PixelsPerStud 40-60)")
		end
		if pps and pps > 0 then
			rec.maxStuds, rec.minStuds = maxPx / pps, minPx / pps
			if maxPx / pps < TITLE_STUDS and not LABEL_STRIPS[gui.Name] then
				bad(string.format("biggest letters %.2f stud < %.2f", maxPx / pps, TITLE_STUDS))
			end
			if minPx / pps < INFO_STUDS - 0.001 then
				bad(string.format("smallest letters %.2f stud < %.2f", minPx / pps, INFO_STUDS))
			end
			-- the text fits its box. T0 review: measured with the face's real advance widths (SmokeCommon.RealWidth:
			-- FredokaOne capitals run 0.59-0.66 em, so the flat 0.5 em per character the mock measures with let BATTLE ARENA
			-- spill past its box) plus the outline on both sides; a face outside the table (Nunito) keeps the 0.5 em estimate as
			-- it was (no outline added)
			local part = gui.Adornee or gui.Parent
			if part and part:IsA("BasePart") then
				local fw, fh = faceStuds(part, gui.Face)
				for _, d in ipairs(texts) do
					local w, h = signBox(d, gui, fw * pps, fh * pps)
					if w then
						local px = d.TextSize * scaleWithin(d, gui)
						local ring = 0
						for _, c in ipairs(d:GetChildren()) do
							if c:IsA("UIStroke") and c.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual and c.Enabled ~= false then
								ring = math.max(ring, tonumber(c.Thickness) or 0)
							end
						end
						local lines = 0
						local widest = 0
						for line in (plain(d.Text) .. "\n"):gmatch("([^\n]*)\n") do
							local font = measuredFont(d)
							local real = font and SmokeCommon.RealWidth(line, px, font, true)
							local est = real and (real + 2 * ring) or 0.5 * px * utf8len(line)
							widest = math.max(widest, est)
							lines = lines + math.max(1, math.ceil(est / math.max(1, w)))
						end
						if not d.TextWrapped then
							lines = select(2, plain(d.Text):gsub("\n", "")) + 1
						end
						local tall = lines * px * math.max(1, d.LineHeight)
						if (not d.TextWrapped and widest > w + 2) or tall > h + 4 then
							bad(string.format("'%s' (%d px) overflows its %dx%d px box", plain(d.Text):sub(1, 24), px, w, h))
						end
					end
				end
			end
		end
	end
	return rec
end

-- (Phase 3: "BattleNumber" = BattleController's pooled floating damage numbers, combat text like NC_FloatText: pixel-sized
-- and outlined, never on a name plate. They are in the client world once it has drawn a battle.)
local function exempt(gui)
	local cur = gui
	while cur and cur ~= game do
		local n = cur.Name
		if n == "StormAltar" or n == "StormfangShowcase" or n == "StormAltarSign" or n == "NC_FloatText" or n == "BattleNumber" then
			return n
		end
		cur = cur.Parent
	end
	return nil
end

-- Folds audit records into hard checks (tags / signs) and a report-only line for exempt GUIs.
local function report(label, records)
	local tags = T.tally(label .. ": every BillboardGui tag is pixel-sized with readable text (names >= " .. NAME_MIN .. " px, lines >= " .. INFO_MIN
		.. " px, no TextScaled), outlined on a compact solid plate, LightInfluence 0, MaxDistance 50-150 (beacons further; gate / portal cards exactly "
		.. GATE_RANGE .. ", the arena Return gate " .. RETURN_RANGE .. ", the own follower's pet card " .. OWN_FOLLOWER_RANGE .. ")", 4)
	local signs = T.tally(label .. ": every SurfaceGui sign runs at 40-60 px per stud with fixed text: the biggest line >= " .. TITLE_STUDS
		.. " stud, every line >= " .. INFO_STUDS .. " stud, fitting its box, LightInfluence 0", 4)
	local counts = { BillboardGui = 0, SurfaceGui = 0 }
	local others = {}
	local smallest = { BillboardGui = math.huge, SurfaceGui = math.huge }
	local smallestWhat = {}
	for _, r in ipairs(records) do
		if r.texts > 0 then
			if r.exempt then
				if #r.problems > 0 then
					others[#others + 1] = r.path .. ": " .. table.concat(r.problems, "; ")
				end
			else
				counts[r.kind] = (counts[r.kind] or 0) + 1
				local tl = (r.kind == "SurfaceGui") and signs or tags
				tl:case(#r.problems == 0, r.path .. ": " .. table.concat(r.problems, "; "))
				local m = (r.kind == "SurfaceGui") and r.minStuds or r.minPx
				if m and m < smallest[r.kind] then
					smallest[r.kind] = m
					smallestWhat[r.kind] = r.path
				end
			end
		end
	end
	tags:report(counts.BillboardGui .. " tags")
	signs:report(counts.SurfaceGui .. " signs")
	if smallest.BillboardGui < math.huge then
		T.info(string.format("*%s: smallest tag text %.0f px (%s), smallest sign letters %.2f stud (%s)", label, smallest.BillboardGui,
			tostring(smallestWhat.BillboardGui), smallest.SurfaceGui < math.huge and smallest.SurfaceGui or 0, tostring(smallestWhat.SurfaceGui)))
	end
	if #others > 0 then
		T.info("*" .. label .. ": outside this round (reported, not asserted): " .. table.concat(others, " | ", 1, math.min(#others, 4)))
	end
	return counts
end

----------------------------------------------------------------------------------------------------
-- server world
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}

	-- Players:GetUserThumbnailAsync is the mock's own since lobby-shop Task 24 (content + isReady; Mock.ThumbnailCalls[userId]
	-- counts the calls, every call fails while Mock.ThumbnailFail is set). This file's older stub was installed only on a
	-- mock without the method, so once the mock had one the stub's counters stayed empty: the counts are read from the
	-- mock now, as deltas (other scenarios share Mock.ThumbnailCalls)
	local THUMB = {}
	function THUMB.has()
		local playersClass = Mock.Classes and Mock.Classes.Players
		return playersClass ~= nil and playersClass.methods ~= nil and playersClass.methods.GetUserThumbnailAsync ~= nil
	end
	function THUMB.calls(userId)
		return (type(Mock.ThumbnailCalls) == "table" and Mock.ThumbnailCalls[userId]) or 0
	end
	local function thumbContent(userId)
		return "rbx" .. "thumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150"
	end

	-- census: every BillboardGui / SurfaceGui that enters the workspace. One leaving the workspace (a course torn
	-- down, a marker removed) is audited just before it goes (DescendantRemoving fires with its subtree intact).
	-- Two workspace-level connections only: per-GUI connections would trip the "no leaks across matches" check.
	local census = { list = {}, seen = {}, snaps = {}, snapCount = 0 }
	local function record(d)
		if (d:IsA("BillboardGui") or d:IsA("SurfaceGui")) and not census.seen[d] then
			census.seen[d] = true
			census.list[#census.list + 1] = d
		end
	end
	workspace.DescendantAdded:Connect(function(d)
		pcall(record, d)
	end)
	workspace.DescendantRemoving:Connect(function(d)
		if census.seen[d] and census.snapCount < 800 then
			census.snapCount = census.snapCount + 1
			local ok, rec = pcall(auditGui, d)
			if ok then
				rec.exempt = exempt(d)
				census.snaps[d] = rec
			end
		end
	end)

	S.polish_worldtext = guarded("polish_worldtext", function()
		local K = _G.K
		if not K.needBoot() then
			return
		end
		local advance, mod = K.advance, K.mod
		local info = K.W.lobbyInfo
		local SS, DataS = mod("SpotService"), mod("DataService")
		local Config = K.config()

		-- the audit itself rejects the playtest's nameplate (studs-sized card, TextScaled / tiny fixed text, a huge
		-- dark panel) and a sign with 0.4-stud letters
		do
			local part = Instance.new("Part")
			part.Size = Vector3.new(4.4, 1.8, 0.5)
			local old = Instance.new("BillboardGui")
			old.Size = UDim2.new(18, 0, 5.6, 0)
			old.MaxDistance = 170
			old.Parent = part
			local card = Instance.new("Frame")
			card.Size = UDim2.fromScale(1, 1)
			card.BackgroundTransparency = 0.1
			card.Parent = old
			local scaledName = Instance.new("TextLabel")
			scaledName.Text = "TellingBarel1234"
			scaledName.TextScaled = true
			scaledName.Parent = card
			local small = Instance.new("TextLabel")
			small.Text = "3 pets"
			small.TextSize = 12
			small.Parent = card
			local rec = auditGui(old)
			local text = table.concat(rec.problems, "; ")
			T.check(text:find("studs-scaled", 1, true) and text:find("TextScaled", 1, true) and text:find("smallest text", 1, true) and text:find("MaxDistance", 1, true),
				"the audit rejects a studs-sized billboard with TextScaled / small fixed text and a long MaxDistance", text)
			-- the card range's named exceptions are exact: a gate card at the old 120, a portal card at 60 and an own
			-- follower's card at the old 90 are rejected, though each sits inside 50-150
			local function rangeProblem(name, md, opts)
				local g = Instance.new("BillboardGui")
				g.Name = name
				g.Size = UDim2.fromOffset(200, 60)
				g.MaxDistance = md
				local l = Instance.new("TextLabel")
				l.Text = "Card"
				l.TextSize = 24
				l.Parent = g
				local r = auditGui(g, opts)
				g:Destroy()
				return table.concat(r.problems, "; ")
			end
			local gateText = rangeProblem("GateTag", 120)
			local portalText = rangeProblem("PortalBillboard", 60)
			local petText = rangeProblem("PetCard", 90, { PetMode = "Follower" })
			local fineText = rangeProblem("GateTag", GATE_RANGE) .. rangeProblem("PetCard", OWN_FOLLOWER_RANGE, { PetMode = "Follower" })
			T.check(gateText:find("want exactly " .. GATE_RANGE, 1, true) and portalText:find("want exactly " .. GATE_RANGE, 1, true)
				and petText:find("want exactly " .. OWN_FOLLOWER_RANGE, 1, true) and not fineText:find("MaxDistance", 1, true),
				"the audit holds the card range exactly: GateTag / PortalBillboard " .. GATE_RANGE .. ", the own follower's card " .. OWN_FOLLOWER_RANGE .. " (120 / 60 / 90 rejected)",
				gateText .. " | " .. portalText .. " | " .. petText .. " | " .. fineText)
			local sign = Instance.new("SurfaceGui")
			sign.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sign.PixelsPerStud = 40
			sign.LightInfluence = 0
			sign.Parent = part
			local tiny = Instance.new("TextLabel")
			tiny.Size = UDim2.fromScale(1, 1)
			tiny.Text = "No. 1"
			tiny.TextSize = 16
			tiny.TextStrokeTransparency = 0
			tiny.Parent = sign
			local srec = auditGui(sign)
			local stext = table.concat(srec.problems, "; ")
			T.check(stext:find("biggest letters", 1, true) ~= nil and stext:find("smallest letters", 1, true) ~= nil, "the audit rejects a sign with 0.4-stud letters", stext)
			part:Destroy()
		end
		-- what was already in the workspace before this file's listener (the boot normally happens after it)
		for _, d in ipairs(workspace:GetDescendants()) do
			record(d)
		end

		------------------------------------------------------------------ home nameplates
		local function discOf(spot)
			local gui = spot.Nameplate or (spot.NameLabel and spot.NameLabel:FindFirstAncestorOfClass("BillboardGui"))
			return gui, gui and gui:FindFirstChild("Avatar", true)
		end
		local function avatarState(spot)
			local _, disc = discOf(spot)
			if not disc then
				return "none"
			end
			local shot, sil, free = disc:FindFirstChild("Headshot"), disc:FindFirstChild("Silhouette"), disc:FindFirstChild("FreeIcon")
			local state = {}
			if free and free.Visible then
				state[#state + 1] = "free"
			end
			if sil and sil.Visible then
				state[#state + 1] = "silhouette"
			end
			if shot and shot.Visible then
				state[#state + 1] = "headshot"
			end
			return table.concat(state, "+"), shot and shot.Image or "", disc
		end

		local plates = T.tally("home nameplates: a pixel-sized tag readable from ~80 studs (MaxDistance 80-120), name >= " .. NAME_MIN
			.. " px over an info line >= " .. INFO_MIN .. " px, an avatar disc (Headshot / Silhouette / FreeIcon) and the '#N' badge")
		local free = T.tally("free homes read 'Free home' / 'Press E at the gate' with the '+' on the disc (no headshot)")
		local signs = T.tally("every plot's gate sign reads 'No. N' on both faces in letters >= 1 stud")
		for i, spot in ipairs(info.Spots) do
			local gui, disc = discOf(spot)
			local ok = gui ~= nil and gui:IsA("BillboardGui") and disc ~= nil and gui.Size.X.Scale == 0 and gui.MaxDistance >= 80 and gui.MaxDistance <= 120
				and spot.NameLabel.TextSize >= NAME_MIN and spot.SubLabel.TextSize >= INFO_MIN and not spot.NameLabel.TextScaled
			local badge = gui and gui:FindFirstChild("NumberBadge", true)
			local badgeText = badge and badge:FindFirstChildWhichIsA("TextLabel", true)
			ok = ok and badgeText ~= nil and badgeText.Text == "#" .. i and badgeText.TextSize >= INFO_MIN
			plates:case(ok, "spot " .. i .. ": " .. tostring(gui and gui.Size) .. ", MaxDistance " .. tostring(gui and gui.MaxDistance) .. ", disc " .. tostring(disc ~= nil)
				.. ", badge " .. tostring(badgeText and badgeText.Text))
			if not SS.GetSpot or spot.NameLabel.Text == "Free home" or spot.NameLabel.Text == "Free spot" then
				local state, image = avatarState(spot)
				free:case(spot.NameLabel.Text == "Free home" and spot.SubLabel.Text == "Press E at the gate" and state == "free" and image == "",
					"spot " .. i .. ": '" .. spot.NameLabel.Text .. "' / '" .. spot.SubLabel.Text .. "', disc " .. state)
			end
			local sign = spot.Folder:FindFirstChild("NumberSign", true)
			local faces, good = 0, 0
			for _, sg in ipairs(sign and sign:GetChildren() or {}) do
				if sg:IsA("SurfaceGui") then
					faces = faces + 1
					local label = sg:FindFirstChildWhichIsA("TextLabel", true)
					if label and label.Text == "NO. " .. i and label.TextSize / sg.PixelsPerStud >= 1 and not label.TextScaled then
						good = good + 1
					end
				end
			end
			signs:case(faces == 2 and good == 2, "spot " .. i .. ": " .. faces .. " faces, " .. good .. " readable")
		end
		plates:report()
		free:report()
		signs:report()

		-- Phase 2: a home is claimed with E at its gate (its ClaimPrompt; TycoonService answers it)
		local function claimHome(player)
			local target = SS.FindFreeSpot and SS.FindFreeSpot(nil, nil)
			if not target then
				return nil
			end
			local gate = SS.GateCFrame and SS.GateCFrame(target)
			if gate then
				Mock.Teleport(player, gate * CFrame.new(0, 3, -5))
			end
			for _, d in ipairs(target.Folder:GetDescendants()) do
				if d:IsA("ProximityPrompt") and d.Name == "ClaimPrompt" then
					Mock.Trigger(d, player)
				end
			end
			advance(0.6)
			return SS.GetSpot(player)
		end

		-- an owner: name, "Home Level <n>", the headshot (fetched once), the podium tag
		local p = K.freshPlayers(1, "Wt")[1]
		advance(1.0)
		T.check(THUMB.has(), "the mock has Players:GetUserThumbnailAsync (precondition)")
		local thumbBase = THUMB.calls(p.UserId)
		local spot = claimHome(p)
		if T.check(spot ~= nil, "a player claims a home with E at its gate (precondition)") then
			advance(1.5)
			T.eq(spot.NameLabel.Text, p.DisplayName, "the owner's nameplate shows their display name")
			T.check(tostring(spot.SubLabel.Text):match("^Home Level %d+") ~= nil, "the info line reads 'Home Level <n>' (Phase 2)", spot.SubLabel.Text)
			local state, image, disc = avatarState(spot)
			T.check(state == "headshot" and image == thumbContent(p.UserId), "the avatar disc shows the owner's headshot (Players:GetUserThumbnailAsync)", state .. " '" .. image .. "'")
			T.check(disc ~= nil and disc.BackgroundColor3 == disc:GetAttribute("OwnedColor"), "...on the plot's owned colour")
			T.eq(THUMB.calls(p.UserId) - thumbBase, 1, "the headshot is requested once")
			for _ = 1, 3 do
				DataS.AddTokens(p, 1)
				SS.Refresh(p)
				advance(1.1)
			end
			T.eq(THUMB.calls(p.UserId) - thumbBase, 1, "...not again on every nameplate refresh")

			-- the podium tag of the best pet (the highest rarity the owner has)
			local PC = mod("PetCatalog")
			local def = PC and PC.Pets and PC.Pets[1]
			if def then
				local prof = DataS.GetProfile(p)
				prof.Pets[def.Id] = (prof.Pets[def.Id] or 0) + 1
				DataS.MarkDirty(p)
				DataS.Sync(p)
				SS.Refresh(p) -- the 1 s refresh loop is gone once the 'shutdown' scenario has run (BindToClose)
				advance(1.8)
				local order, best = {}, -1
				for _, r in ipairs(Config.Rarities) do
					order[r.Id] = r.Order or 0
				end
				for id, n in pairs(prof.Pets) do
					local d = PC.Get(id)
					if d and type(n) == "number" and n > 0 then
						best = math.max(best, order[d.Rarity] or 0)
					end
				end
				local tag = spot.Folder:FindFirstChild("ShowcaseTag", true)
				local nameLabel = tag and tag:FindFirstChild("PetName", true)
				local rarity = tag and tag:FindFirstChild("PetRarity", true)
				local shown = nil
				for id, n in pairs(prof.Pets) do
					local d = PC.Get(id)
					if d and n > 0 and nameLabel and d.Name:upper() == nameLabel.Text then
						shown = d
					end
				end
				T.check(tag ~= nil and tag.Enabled and shown ~= nil and rarity ~= nil and rarity.Text == shown.Rarity and (order[shown.Rarity] or 0) == best,
					"the podium tag names the owner's best pet and its rarity", (tag and (tostring(nameLabel and nameLabel.Text) .. " / " .. tostring(rarity and rarity.Text)) or "no tag")
					.. " (owns " .. (function()
						local ids = {}
						for id, n in pairs(prof.Pets) do
							ids[#ids + 1] = tostring(id) .. "=" .. tostring(n)
						end
						table.sort(ids)
						return table.concat(ids, ", ", 1, math.min(#ids, 8)) .. (#ids > 8 and (" +" .. (#ids - 8)) or "")
					end)() .. "; best order " .. best .. "; tag enabled " .. tostring(tag and tag.Enabled) .. ", podium model "
					.. tostring(spot.Folder:FindFirstChild("ShowcasePet", true) ~= nil) .. ", spot " .. tostring(spot.Index) .. ")")

				if tag then
					local rec = auditGui(tag)
					T.check(#rec.problems == 0 and rec.texts == 2, "...as a pixel-sized tag with readable text", table.concat(rec.problems, "; "))
				end
			end

			-- leaving frees the home: "Free home", the "+", no headshot
			local index = spot.Index
			local userId = p.UserId
			K.removePlayers({ p })
			advance(0.5)
			local state2, image2 = avatarState(info.Spots[index])
			T.check(info.Spots[index].NameLabel.Text == "Free home" and info.Spots[index].SubLabel.Text == "Press E at the gate" and state2 == "free" and image2 == "",
				"leaving frees the nameplate: 'Free home' / 'Press E at the gate', the '+', no headshot", info.Spots[index].NameLabel.Text .. " / " .. state2)
			-- coming back: the cached headshot, no second request
			local again = K.joinPlayer("WtAgain", userId)
			advance(1.0)
			claimHome(again)
			advance(0.6)
			local spot2 = SS.GetSpot(again)
			local state3 = spot2 and avatarState(spot2) or "none"
			local asked = THUMB.calls(userId) - thumbBase
			T.check(state3 == "headshot" and asked == 1, "a returning player gets the cached headshot without a new request", state3 .. ", " .. tostring(asked) .. " requests")
			K.removePlayers({ again })
		end

		-- a failing thumbnail request (Studio test players, web outage): the silhouette stays. Every mock call fails while
		-- Mock.ThumbnailFail is set; nobody else claims a home meanwhile
		local q = K.joinPlayer("WtNoThumb", 977001)
		advance(1.0)
		local qBase = THUMB.calls(977001)
		Mock.ThumbnailFail = true
		local okQ, errQ = pcall(function()
			claimHome(q)
			advance(0.6)
			local qs = SS.GetSpot(q)
			local stateQ = qs and avatarState(qs) or "none"
			T.check(stateQ == "silhouette" and THUMB.calls(977001) - qBase >= 1, "a failed headshot request leaves the silhouette built from frames",
				stateQ .. ", " .. tostring(THUMB.calls(977001) - qBase) .. " requests")
		end)
		Mock.ThumbnailFail = nil
		if not okQ then
			T.fail("the failed headshot step errored", tostring(errQ))
		end
		K.removePlayers({ q })
		K.flushErrors("polish worldtext (nameplates)")

		------------------------------------------------------------------ a downed marker, made here
		local MS, DSv = mod("MatchService"), mod("DamageService")
		if MS and DSv and K.startMatch then
			local pair = K.freshPlayers(2, "WtDown")
			local m = K.startMatch(Config.Difficulties[1].Id, pair)
			if m and K.toPlaying(m) then
				if K.waitNotInvulnerable then
					K.waitNotInvulnerable(pair[2])
				end
				advance((Config.Damage and Config.Damage.IFrames or 1) + 0.2)
				DSv.Damage(pair[2], 10000, "Void", { IgnoreIFrames = true })
				advance(0.4)
				local char = pair[2].Character
				local marker = char and char:FindFirstChild("NimbusDownedMarker", true)
				if T.check(marker ~= nil, "a downed player gets the DOWNED marker (precondition)") then
					local rec = auditGui(marker)
					T.check(#rec.problems == 0 and rec.texts == 2, "the DOWNED marker is a pixel-sized tag with readable text on a solid plate", table.concat(rec.problems, "; "))
					T.check(marker.AlwaysOnTop == true and marker.MaxDistance >= 150, "...visible to teammates across the course (AlwaysOnTop, long range)")
				end
			else
				T.warn("polish worldtext: the match did not reach Playing; the downed marker comes from the census only")
			end
			K.endAllMatches(pair)
			K.removePlayers(pair)
		end
		K.flushErrors("polish worldtext (downed)")

		------------------------------------------------------------------ fresh course builds (every difficulty)
		local CB = mod("CourseBuilder")
		local holder = Instance.new("Folder")
		holder.Name = "WorldTextCourses"
		holder.Parent = workspace
		local built, kinds = 0, {}
		for i, diff in ipairs(Config.Difficulties) do
			for seed = 1, 2 do
				local okL, layout = pcall(CB.GenerateLayout, diff.Id, seed)
				if okL and layout then
					local okB, ci = pcall(CB.Build, layout, Vector3.new(60000 + i * 2500 + seed * 1200, 1200, 0), holder)
					if okB and type(ci) == "table" and ci.Folder then
						built = built + 1
						for _, d in ipairs(ci.Folder:GetDescendants()) do
							if d:IsA("TextLabel") then
								local t = plain(d.Text):upper()
								for _, key in ipairs({ "START", "FINISH", "CHECKPOINT", "GOAL", "DASH!", "CANNON", "HOLD THE PLATE", "HOW TO CLIMB", "TEAMWORK" }) do
									if t:find(key, 1, true) then
										kinds[key] = true
									end
								end
							end
						end
					end
				end
			end
		end
		T.check(built >= #Config.Difficulties, "course signs: " .. built .. " fresh courses built for the audit")
		local missing = {}
		for _, key in ipairs({ "START", "FINISH", "CHECKPOINT", "GOAL", "DASH!", "HOW TO CLIMB", "TEAMWORK" }) do
			if not kinds[key] then
				missing[#missing + 1] = key
			end
		end
		T.check(#missing == 0, "...with every kind of course sign (START, FINISH, CHECKPOINT, GOAL, DASH!, boards)", table.concat(missing, ", "))
		T.info("*course sign kinds seen: CANNON " .. tostring(kinds.CANNON == true) .. ", HOLD THE PLATE " .. tostring(kinds["HOLD THE PLATE"] == true))

		------------------------------------------------------------------ the census
		local records = {}
		local live, dead = 0, 0
		for _, gui in ipairs(census.list) do
			local rec = nil
			if not gui:IsDescendantOf(game) then
				rec = census.snaps[gui] -- gone: its audit from the moment it left
			end
			if not rec then
				local ok, r = pcall(auditGui, gui)
				if ok then
					rec = r
					rec.exempt = exempt(gui)
					live = live + 1
				else
					T.fail("polish worldtext: auditing " .. shortPath(gui) .. " raised an error", r)
				end
			else
				dead = dead + 1
			end
			if rec then
				records[#records + 1] = rec
			end
		end
		T.info("*world text census: " .. #census.list .. " GUIs (" .. live .. " live, " .. dead .. " audited when destroyed)")
		report("world text (server)", records)
		local names = {}
		for _, r in ipairs(records) do
			if r.texts > 0 then
				names[r.name] = (names[r.name] or 0) + 1
			end
		end
		-- Phase 5 (6.1): one GateTag per Gate Court gate (workspace.NimbusLobby.Gates) instead of a portal per difficulty
		local lobbyModel = workspace:FindFirstChild("NimbusLobby")
		local gatesFolder = lobbyModel and lobbyModel:FindFirstChild("Gates")
		local gateCount = 0
		local gateRanges = T.tally("polish worldtext: every lobby GateTag (the Gate Court) shows within exactly " .. GATE_RANGE .. " studs (the card range, 2026-11-13 owner: 55, was 45)")
		for _, g in ipairs(gatesFolder and gatesFolder:GetChildren() or {}) do
			local gtag = g:IsA("Model") and g:FindFirstChild("GateTag", true)
			if gtag then
				gateCount = gateCount + 1
				gateRanges:case(gtag:IsA("BillboardGui") and gtag.MaxDistance == GATE_RANGE, g.Name .. ": MaxDistance " .. tostring(gtag.MaxDistance))
			end
		end
		T.check(gateCount >= 3, "polish worldtext: the Gate Court gates carry a GateTag each", gateCount .. " gates with a tag")
		gateRanges:report(gateCount .. " gates")
		-- lobby shop (spec 5.9): + the trove's JoinBillboard; the egg row's RarityStrip is checked by name below
		local want = { Nameplate = Config.Lobby.SpotCount, GateTag = math.max(3, gateCount), PriceBillboard = #Config.Roulettes, TroveBillboard = 1, JoinBillboard = 1, NameTag = 1, SignGui = 6, HintTag = 5 }
		local short = {}
		for name, n in pairs(want) do
			if (names[name] or 0) < n then
				short[#short + 1] = name .. " " .. tostring(names[name] or 0) .. "/" .. n
			end
		end
		table.sort(short)
		T.check(#short == 0, "the census covered the lobby, home, NPC, portal and course GUIs", table.concat(short, ", "))
		-- lobby shop (spec 5.9): the Sky Trove's Join sign is in the census and passes the rule; shop-area 16.17.2: so is the
		-- egg row's RarityStrip (a label strip: seven 0.6-stud rarity labels, no title line)
		local function recFor(needle)
			for _, r in ipairs(records) do
				if r.texts > 0 and string.find(r.path, needle, 1, true) then
					return r
				end
			end
			return nil
		end
		local joinRec, stripRec = recFor("JoinBillboard"), recFor("RarityStrip")
		T.check(joinRec ~= nil and #joinRec.problems == 0, "polish worldtext: the Sky Trove's Join sign is in the census and keeps the World text rule",
			joinRec and table.concat(joinRec.problems, "; ") or "not in the census")
		T.check(stripRec ~= nil and stripRec.kind == "SurfaceGui" and #stripRec.problems == 0 and stripRec.texts == 7 and (stripRec.minStuds or 0) >= INFO_STUDS - 0.001,
			"polish worldtext: the egg row's RarityStrip (seven rarity labels, every line >= 0.6 stud, fitting its box) is in the census and keeps the sign rule",
			stripRec and (stripRec.texts .. " texts; " .. table.concat(stripRec.problems, "; ")) or "not in the census")
		-- lobby shop Task 13 (spec 5.11 c): the Storm Altar is exempt above, but its return sign keeps the rule. On the
		-- Part fallback it is a tag "To the Plaza" (the full tag rule); on the dressed portal_ring mesh the 4 x 1-stud navy
		-- board reads "Plaza" (shop-area polish: "To the Plaza" fit it only at 0.6 stud), so the full sign rule applies,
		-- the 0.95-stud title floor included
		local SAlt = mod("StormAltar")
		local rpad = SAlt and type(SAlt.GetReturnPad) == "function" and SAlt.GetReturnPad()
		local rportal = rpad and rpad.Parent
		local plaza = nil
		for _, d in ipairs(rportal and rportal:GetDescendants() or {}) do
			if (d:IsA("BillboardGui") or d:IsA("SurfaceGui")) and d.Name == "PlazaSign" then
				plaza = d
			end
		end
		if T.check(plaza ~= nil and census.seen[plaza] == true, "polish worldtext: the Storm Altar's 'To the Plaza' sign (ReturnPortal PlazaSign) is in the census") then
			local prec = auditGui(plaza)
			local probs = prec.problems
			local wantText = plaza:IsA("SurfaceGui") and "PLAZA" or "TO THE PLAZA" -- (kit-b U6: a Title-role sign reads in capitals)
			T.check(prec.texts == 1 and prec.strings[1] == wantText and #probs == 0 and (plaza:IsA("BillboardGui") or (prec.minStuds or 0) >= TITLE_STUDS - 0.001),
				"polish worldtext: ...it reads '" .. wantText .. "' and keeps the World text rule, no exemption (" .. plaza.ClassName .. ")",
				tostring(prec.strings[1]) .. "; " .. tostring(prec.minStuds) .. " stud; " .. table.concat(probs, "; "))
		end
		holder:Destroy()
		advance(0.2)
		K.flushErrors("polish worldtext")
		K.flushWarnings("polish worldtext")
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client world (1920x1080)
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}

	S.client_polish_worldtext = guarded("client_polish_worldtext", function()
		local KC = _G.KC
		local advance = KC.advance
		local Config = KC.env()
		local Players = game:GetService("Players")
		local CollectionService = game:GetService("CollectionService")
		local LocalPlayer = Players.LocalPlayer
		Mock.SetViewport(1920, 1080)
		advance(0.3)
		local function req(key)
			local top, rest = key:match("^(%w+)/(.+)$")
			local inst = Mock.GetPath(ROOTS[top])
			for part in rest:gmatch("[^/]+") do
				inst = inst and inst:FindFirstChild(part)
			end
			return inst and require(inst)
		end

		-- the tutorial guide sign over a world target
		local Steps = req("shared/TutorialSteps")
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		local step = Steps.Steps[7] or Steps.Steps[#Steps.Steps]
		local target = { Kind = "Portal", Id = "Easy", Label = "Easy Portal", Position = Config.Lobby.Origin + Vector3.new(60, 0, 40) }
		KC.toClient("TutorialState", {
			Step = 7, Total = #Steps.Steps, Id = step.Id, Title = step.Title, Text = step.Text or "", Target = target,
			CompleteOn = step.CompleteOn, Hint = step.Hint, Button = step.Button, Gift = false, Done = false, Completed = false, Skipped = false, Reward = 0,
		})
		advance(2.5)
		local fx = workspace:FindFirstChild("ClientFx")
		local sign = fx and fx:FindFirstChild("GuideSign", true)
		if T.check(sign ~= nil and sign:IsA("BillboardGui"), "the tutorial guide shows its floating sign (precondition)") then
			local rec = auditGui(sign)
			T.check(rec.texts == 2 and #rec.problems == 0, "the guide sign is pixel-sized: the target name and the distance on a compact plate, readable", table.concat(rec.problems, "; ") .. " (" .. rec.texts .. " texts)")
			T.check(rec.texts == 2 and rec.maxPx >= 24 and rec.minPx >= 19, "...24 px name, 19 px distance at 1080p", string.format("%s-%s px", tostring(rec.minPx), tostring(rec.maxPx)))
			T.check(sign.AlwaysOnTop == true, "...a way-finder seen through the scenery (AlwaysOnTop)")
		end
		KC.toClient("TutorialState", { Step = #Steps.Steps, Total = #Steps.Steps, Id = "done", Text = "", Done = true, Completed = true, Skipped = true, Reward = 0 })
		advance(1.5)

		-- NPC nameplates as NpcController shows them (built by the real NpcService when this world has none)
		local made = nil
		if #CollectionService:GetTagged("NC_Npc") == 0 then
			local NS = req("server/Services/NpcService")
			if NS and type(NS.Init) == "function" then
				local spots = {}
				local origin = Config.Lobby.Origin
				for i = 1, 6 do
					local a = (i - 1) * math.pi / 3
					local pos = origin + Vector3.new(math.cos(a) * 30, 0, math.sin(a) * 30)
					spots[i] = CFrame.new(pos, Vector3.new(origin.X, pos.Y, origin.Z))
				end
				local ok = pcall(NS.Init, { NpcSpots = spots })
				made = ok and workspace:FindFirstChild("NimbusNpcs") or nil
				advance(1.5)
			end
		end
		local records = {}
		for _, model in ipairs(CollectionService:GetTagged("NC_Npc")) do
			local plate = model:FindFirstChild("Nameplate", true)
			if plate then
				local rec = auditGui(plate)
				records[#records + 1] = rec
			end
		end
		if T.check(#records > 0, "the NPC nameplates exist in the client world (precondition)") then
			local tl = T.tally("NPC nameplates (client, NpcController's screen scale applied): pixel-sized, name >= " .. NAME_MIN .. " px, title >= " .. INFO_MIN .. " px, compact plates")
			for _, rec in ipairs(records) do
				tl:case(#rec.problems == 0 and rec.texts >= 2, rec.path .. ": " .. table.concat(rec.problems, "; "))
			end
			tl:report()
		end
		if made then
			made:Destroy()
			advance(0.5)
		end

		-- Phase 4 pet cards (contract 3.9; PetCard BillboardGuis live in the PlayerGui so the EVOLVE! pill can be tapped):
		-- own followers, another player's followers (level + stars from EquippedInfo) and a ready card with its pill
		do
			local PC = KC.M and KC.M.PetController
			local cardMod = req("client/UI/PetCard")
			local friend = Mock.AddPlayer("CardAudit", 7401)
			advance(0.6)
			local here = KC.root() and KC.root().Position or Vector3.new(0, 40, 0)
			Mock.Teleport(friend, here + Vector3.new(16, 0, 0))
			friend:SetAttribute("EquippedInfo", "12:1,57:2")
			friend:SetAttribute("EquippedPets", "pebble_pup,cloudy_dragon")
			LocalPlayer:SetAttribute("EquippedPets", "biscuit_bear")
			advance(2.5)
			local ready = cardMod and cardMod.New(nil, "Follower", 2) or nil
			if ready then
				ready:SetLevel(20, 1, true)
				ready:SetXp(0.3)
			end
			-- the card range (2026-11-12): the own follower's card ("Follower", the ready card too) is held at exactly
			-- OWN_FOLLOWER_RANGE by the audit, another player's ("Other") keeps the 50-150 rule
			local recs = {}
			local ownCards = 0
			for _, c in ipairs(PC and PC.GetCards and PC.GetCards() or {}) do
				if c.Mode == "Follower" then
					ownCards = ownCards + 1
				end
				recs[#recs + 1] = auditGui(c.Gui, { PetMode = c.Mode })
			end
			if ready then
				recs[#recs + 1] = auditGui(ready.Gui, { PetMode = "Follower" })
			end
			T.check(ownCards >= 1, "pet cards: the own follower's card is among them (its exact " .. OWN_FOLLOWER_RANGE .. "-stud range is audited)", tostring(ownCards))
			if T.check(#recs >= 4, "pet cards exist in the client world (precondition: 1 own + 2 of another player + a ready card)", tostring(#recs)) then
				local tl = T.tally("pet cards (PetCard): pixel-sized, \"Lv\" >= " .. NAME_MIN .. " px with a stroke, stars / EVOLVE! >= " .. INFO_MIN .. " px, compact solid plates, LightInfluence 0, MaxDistance 50-150 (the own follower's card exactly " .. OWN_FOLLOWER_RANGE .. ")")
				for _, rec in ipairs(recs) do
					tl:case(#rec.problems == 0 and rec.texts >= 1 and rec.maxPx >= NAME_MIN, rec.path .. ": " .. table.concat(rec.problems, "; ") .. " (max " .. tostring(rec.maxPx) .. " px)")
				end
				tl:report(#recs .. " cards")
			end
			if ready then
				ready:Destroy()
			end
			LocalPlayer:SetAttribute("EquippedPets", "")
			Mock.RemovePlayer(friend)
			advance(0.8)
		end

		-- everything else with text in the client's workspace
		local all = {}
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
				local rec = auditGui(d)
				rec.exempt = exempt(d)
				all[#all + 1] = rec
			end
		end
		report("world text (client)", all)
		KC.flushErrors("polish worldtext client")
		KC.flushWarnings("polish worldtext client")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
