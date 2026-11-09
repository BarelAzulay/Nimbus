-- smoke_roll_look.lua: roll-look (the owner's pick 2026-11-08 "A + B"; spec docs/superpowers/specs/2026-11-07-lobby-shop-design.md
-- 16.15 "Roll look A+B", plan docs/superpowers/plans/2026-11-08-roll-look.md): the dressed roll and opening of the egg stage
-- (client/UI/HatchLook builds the pieces, client/UI/EggStage plays them). Loaded by tools/smoke.py in the CLIENT and PHONE
-- worlds:
--   client_roll_look_stage  (client, 1920x1080; Task 1) HatchLook.Shade / RarityColor against the spec's colour table (+-1
--       a channel); the HUD hides while the stage shows (every Enabled ScreenGui outside HatchLook.KEEP and Roblox's own
--       guis goes off, NimbusNotify stays) and comes back on every exit (Done, Close, a match start, an injected phase
--       error, Back on the reveal); a gui added mid-roll hides too; a gui someone turns on mid-roll is left alone (and one
--       turned on, then off again, stays off); a gui that was off before the roll stays off; the strip cards (12 cells,
--       each <= 20 instances, a UIGradient face, a Shine line, the rarity Plate with its upper-case white word, a Shadow
--       beside it in the track, the rim by rarity); the gold window (Pointer > Glow, Window, NotchTop, NotchBottom round
--       the landed cell's box + 8 px, its stroke Metrics.GOLD at rest); B's colour tell (Rare and up: the window, glow and
--       notches turn the rarity colour 0.7 s before the land; Common keeps its gold every frame); the overshoot (the
--       winner passes the window by 18 x S px at p = 1, springs back by the end of Land); the land pop (UIScale "Pop"
--       >= 1.14 within 0.12 s, rests at 1.09), one shine "Sweep" gone by Land + 0.4, the other cards dimmed; a resize
--       during Land (the window refits, the pop rests at 1.09, the roll reaches the reveal); the budgets (x1 <= 450, x3
--       <= 750 instances at every frame of the roll)
--   client_roll_look_open  (client, 1920x1080; Task 2) the opening: the lit plinth in Pedestal1 (Top 0.667 of the box with
--       its Rim, Side, Ring, the soft halo Glow1..2; no drum, no puffs, no bars; the Top's centre line on the egg's foot; the box still
--       1.1 x / 0.24 x the egg under it), neutral until the shakes; the rise (the box's UIScale Pop 0.6 -> past 1 -> 1, the
--       Top fading in from 1); Gemini's tweak from Rare up at the first shake (the plinth's rim / ring / glow, the cloud
--       ring and faint turning rays in the rarity colour) and nothing of it below Rare until the burst (Common, Uncommon);
--       the burst's punch (Stage's UIScale "Punch" >= 1.04 within 0.1 s, back to 1 by + 0.4; none on Low), the 2D halves
--       without ids, 28 sparks for an Epic on PC; the plinth in the rarity colour on the reveal; the image keys
--       (HatchLook.IMAGES, HatchLook.Image with HatchLook._Textures, an ImageLabel Glow with an id, the frames without);
--       a resize mid-tweak (snapped, nothing stranded, the roll reaches the reveal); x3 (three plinths, the tweak per egg,
--       the rays only for the best pull); the budgets at every frame (x1 450 / x3 750 instances, 24 tweens, 1 Heartbeat,
--       <= 2 effects)
--   client_roll_look_phone  (phone world; Task 1) 844x390 and 640x360: the x1 cards 130 x 160 with 15 px plate words, the
--       window's 3 px stroke and 10 px notches, every text >= 15 px and nothing off the screen (RedoGeom.check); the x3 lite
--       cards (no Shadow, Tint or Plate; <= 16 instances a cell); (Task 2) the phone plinth (1.1 x / 0.24 x the egg, Top
--       0.667, 2 px rim), the sparks capped at 16 (an Epic's 28), the reveal's 12 px lip (the Top only)
-- Deterministic: mock clock only. SoundFx.Play is spied (quiet) and put back; the viewport, the Fast hatch setting and the
-- attributes are put back. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local fmt = string.format
local abs = math.abs

local S = {}

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
local ORDER = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Secret = 7 }
local STEP = 1 / 30
local FINE = 1 / 60

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
function G.pg()
	return LocalPlayer:FindFirstChildOfClass("PlayerGui")
end
function G.gui()
	local pg = G.pg()
	return pg and pg:FindFirstChild("NimbusHatch") or nil
end
function G.content()
	local gui = G.gui()
	local stage = gui and gui:FindFirstChild("Stage")
	return stage and stage:FindFirstChild("Content") or nil
end
function G.shown(o)
	return o ~= nil and G.KC().isShown(o)
end
function G.count(inst)
	return inst and (#inst:GetDescendants() + 1) or 0
end
-- every channel within 1/255 (the spec's table is rounded to whole channels)
function G.near(a, b, tol)
	tol = (tol or 1.01) / 255
	return a ~= nil and b ~= nil and abs(a.R - b.R) <= tol and abs(a.G - b.G) <= tol and abs(a.B - b.B) <= tol
end
function G.c3(c)
	return c and fmt("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) or "nil"
end
function G.strip(j)
	local content = G.content()
	local strips = content and content:FindFirstChild("Strips")
	return strips and strips:FindFirstChild("Strip" .. (j or 1)) or nil
end
function G.track(j)
	local st = G.strip(j)
	return st and st:FindFirstChild("Track") or nil
end
function G.pointer(j)
	local st = G.strip(j)
	return st and st:FindFirstChild("Pointer") or nil
end
function G.cells(j)
	local out = {}
	local track = G.track(j)
	for _, c in ipairs(track and track:GetChildren() or {}) do
		if c.Name:match("^Cell%d+$") then
			out[#out + 1] = c
		end
	end
	return out
end
-- the cell showing strip index i (the cells carry their index in the attribute Index)
function G.cellAt(j, i)
	for _, c in ipairs(G.cells(j)) do
		if c:GetAttribute("Index") == i and c.Visible then
			return c
		end
	end
	return nil
end
function G.centre(o)
	local p, s = o.AbsolutePosition, o.AbsoluteSize
	return p.X + s.X / 2, p.Y + s.Y / 2
end
function G.stroke(o)
	return o and o:FindFirstChildOfClass("UIStroke") or nil
end
function G.plateWord(cell)
	local plate = cell and cell:FindFirstChild("Plate")
	return plate and plate:FindFirstChild("Word") or nil
end
function G.rarityOf(Config, rarity)
	for _, r in ipairs(Config.Rarities) do
		if r.Id == rarity then
			return r.Color
		end
	end
	return nil
end
function G.stripIds(PC, rid, winnerId)
	local all = {}
	for _, def in ipairs(PC.PossiblePets(rid)) do
		all[#all + 1] = def.Id
	end
	local ids = {}
	for i = 1, 40 do
		ids[i] = all[((i * 7) % #all) + 1]
	end
	ids[34] = winnerId
	return ids
end
function G.result(PC, rid, defs)
	local pulls = {}
	for i, def in ipairs(defs) do
		pulls[i] = {
			PetId = def.Id, Key = def.Id, Rarity = def.Rarity, IsNew = true, NewDiscovery = true, Count = 1,
			PoolSize = #PC.RarityPool(rid, def.Rarity), Strip = G.stripIds(PC, rid, def.Id),
		}
	end
	local p1 = pulls[1]
	return {
		Ok = true, RouletteId = rid, Currency = "Tokens", Spins = #pulls, UnitPrice = 50, Price = 50 * #pulls, Pulls = pulls, Tokens = 5000, Gems = 5000,
		PetId = p1.PetId, Key = p1.Key, IsNew = p1.IsNew, NewDiscovery = p1.NewDiscovery, Count = p1.Count, Strip = p1.Strip,
	}
end
function G.untilPhase(ES, phase, maxT)
	local t0 = os.clock()
	while os.clock() - t0 < (maxT or 8) do
		if ES.Phase() == phase then
			return os.clock() - t0
		end
		G.advance(STEP)
	end
	return nil
end
-- advances until `t` seconds after t0 (the Show)
function G.until_(t0, t)
	local left = t - (os.clock() - t0)
	if left > 0 then
		G.advance(left)
	end
end

function G.setup(w, h)
	local KC = G.KC()
	local Config = KC.env()
	local env = {
		Config = Config,
		ES = G.req("client/UI/EggStage"),
		HL = G.req("client/UI/HatchLook"),
		CS = G.req("client/ClientSettings"),
		SF = G.req("client/SoundFx"),
		PC = G.req("shared/PetCatalog"),
		Shop = G.req("client/Controllers/ShopController"),
		oldVp = { Mock.Viewport.X, Mock.Viewport.Y },
		keep = {},
	}
	for _, name in ipairs({ Config.Attr.Tokens, Config.Attr.Gems, "PaidRandomItemsRestricted", "GemsSettled", Config.Attr.InMatch }) do
		env.keep[name] = LocalPlayer:GetAttribute(name)
	end
	Mock.SetViewport(w, h)
	LocalPlayer:SetAttribute(Config.Attr.Tokens, 50000)
	LocalPlayer:SetAttribute(Config.Attr.Gems, 5000)
	LocalPlayer:SetAttribute("PaidRandomItemsRestricted", false)
	LocalPlayer:SetAttribute("GemsSettled", true)
	if env.CS then
		env.CS.Set("FastHatch", false)
	end
	if env.Shop then
		env.Shop.Close()
	end
	if env.ES and env.ES.IsShowing() then
		env.ES.Close()
	end
	if env.SF then
		env.realPlay = env.SF.Play
		env.SF.Play = function()
			return nil
		end
	end
	G.advance(0.6)
	return env
end
function G.restore(env)
	if env.ES then
		env.ES._InjectPhaseError = nil
		if env.ES.IsShowing() then
			env.ES.Close()
		end
	end
	if env.SF and env.realPlay then
		env.SF.Play = env.realPlay
	end
	for name, v in pairs(env.keep) do
		LocalPlayer:SetAttribute(name, v)
	end
	Mock.SetViewport(env.oldVp[1], env.oldVp[2])
	G.advance(0.6)
end
function G.hero(name)
	local content = G.content()
	local hero = content and content:FindFirstChild("Hero")
	return hero and hero:FindFirstChild(name) or nil
end
function G.stage()
	local gui = G.gui()
	return gui and gui:FindFirstChild("Stage") or nil
end
function G.burstFrame()
	local c = G.content()
	return c and c:FindFirstChild("Burst") or nil
end
function G.tweensUnder(root)
	local n = 0
	for tw in pairs(Mock.ActiveTweens) do
		local ok, inside = pcall(function()
			local inst = tw.Instance
			return tw.PlaybackState == Enum.PlaybackState.Playing and inst ~= nil and (inst == root or inst:IsDescendantOf(root))
		end)
		if ok and inside then
			n = n + 1
		end
	end
	return n
end
function G.spinning(inst)
	for tw in pairs(Mock.ActiveTweens) do
		local ok, yes = pcall(function()
			return tw.Instance == inst and tw.PlaybackState == Enum.PlaybackState.Playing and tw.TweenInfo.RepeatCount == -1 and (Mock.TweenGoals(tw).Rotation or 0) >= 360
		end)
		if ok and yes then
			return true
		end
	end
	return false
end
-- the budgets at one moment (16.4 / 16.15): -> a failure text or nil
function G.over(ES, cap)
	local st = ES.Stats()
	local gui = G.gui()
	local tw = gui and G.tweensUnder(gui) or 0
	local bad = {}
	if (st.Instances or 0) > cap then
		bad[#bad + 1] = "instances " .. st.Instances
	end
	if tw > 24 or (st.Tweens or 0) > 24 then
		bad[#bad + 1] = fmt("tweens %d (stage %d)", tw, st.Tweens or 0)
	end
	if (st.Heartbeats or 0) > 1 then
		bad[#bad + 1] = "heartbeats " .. tostring(st.Heartbeats)
	end
	if (st.Effects or 0) > 2 then
		bad[#bad + 1] = "effects " .. tostring(st.Effects)
	end
	return #bad > 0 and table.concat(bad, ", ") or nil
end
-- the plinth's parts in a Pedestal box
function G.plinth(j)
	local ped = G.hero("Pedestal" .. (j or 1))
	local out = { Box = ped }
	if ped then
		out.Top = ped:FindFirstChild("Top")
		out.Side = ped:FindFirstChild("Side")
		out.Ring = ped:FindFirstChild("Ring")
		out.Pop = ped:FindFirstChild("Pop")
		out.Rim = out.Top and out.Top:FindFirstChildOfClass("UIStroke") or nil
		out.RingStroke = out.Ring and out.Ring:FindFirstChildOfClass("UIStroke") or nil
		out.Glow1 = ped:FindFirstChild("Glow1")
	end
	return out
end
function G.fakeGui(name, enabled)
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.Enabled = enabled
	local f = Instance.new("Frame")
	f.Name = "Body"
	f.Size = UDim2.fromOffset(40, 40)
	f.Parent = g
	g.Parent = G.pg()
	return g
end

----------------------------------------------------------------------------------------------------
-- client_roll_look_stage
----------------------------------------------------------------------------------------------------
S.client_roll_look_stage = guarded("client_roll_look_stage", function()
	local env = G.setup(1920, 1080)
	local ES, HL, PC, Config = env.ES, env.HL, env.PC, env.Config
	if not T.check(type(HL) == "table", "roll look: client/UI/HatchLook loads") or not T.check(type(ES) == "table" and type(PC) == "table", "roll look: EggStage and PetCatalog load") then
		G.restore(env)
		return
	end
	local K = ES.Metrics
	local fakes = {}
	local ok, err = pcall(function()
		------------------------------------------------------------------ Shade / RarityColor: the spec's table (16.15), +-1 a channel
		local rgb = Color3.fromRGB
		local rows = {
			{ "Epic", 0.78, rgb(238, 223, 250) }, { "Epic", 0.22, rgb(193, 140, 237) }, { "Epic", -0.18, rgb(144, 89, 190) }, { "Epic", -0.68, rgb(56, 35, 74) },
			{ "Common", 0.78, rgb(236, 238, 242) }, { "Common", -0.68, rgb(54, 57, 62) }, { "Rare", 0.22, rgb(125, 179, 237) }, { "Legendary", -0.68, rgb(77, 58, 22) },
			{ "Mythic", -0.18, rgb(195, 80, 115) }, { "Uncommon", 0.78, rgb(222, 242, 227) }, { "Secret", 0.22, rgb(197, 173, 255) }, { "Secret", -0.68, rgb(58, 48, 82) },
		}
		local shadeOk, bad = true, ""
		for _, row in ipairs(rows) do
			local got = HL.Shade(HL.RarityColor(row[1]), row[2])
			if not G.near(got, row[3]) then
				shadeOk = false
				bad = bad .. fmt("%s %.2f -> %s; ", row[1], row[2], G.c3(got))
			end
		end
		T.check(shadeOk, "roll look: Shade(RarityColor(r), t) matches the spec's word gradient / outline table (+-1 a channel)", bad)
		T.check(G.near(HL.RarityColor("Secret"), rgb(180, 150, 255)) and G.near(HL.RarityColor("Epic"), rgb(176, 108, 232)), "roll look: RarityColor: Config's colour, Secret the readable violet 180,150,255")
		T.check(G.near(HL.RarityColor("Nope"), rgb(168, 178, 194)), "roll look: RarityColor of an unknown rarity is the neutral 168,178,194")
		T.check(G.near(HL.Shade(rgb(100, 100, 100), 0), rgb(100, 100, 100)) and G.near(HL.Shade(rgb(100, 100, 100), 1), rgb(255, 255, 255)) and G.near(HL.Shade(rgb(100, 100, 100), -1), rgb(0, 0, 0)),
			"roll look: Shade(c, 0) = c, Shade(c, 1) = white, Shade(c, -1) = black")

		local epic = PC.RarityPool("Cloud", "Epic")[1]
		local rare = PC.RarityPool("Cloud", "Rare")[1]
		local common = PC.RarityPool("Cloud", "Common")[1]
		local pg = G.pg()
		------------------------------------------------------------------ the HUD hides while the stage shows, and comes back
		local hudNames = { "NimbusHud", "NimbusTopBar", "NimbusMenu", "NimbusBoosts" }
		local before = {}
		for _, name in ipairs(hudNames) do
			local g = pg:FindFirstChild(name)
			if g and g:IsA("ScreenGui") and g.Enabled then
				before[#before + 1] = g
			end
		end
		T.check(pg:FindFirstChild("NimbusHud") ~= nil and #before >= 1, "roll look: (setup) the game HUD (NimbusHud) is up before the roll", tostring(#before))
		local notify = pg:FindFirstChild("NimbusNotify")
		local notifyOn = notify ~= nil and notify.Enabled
		local offGui = G.fakeGui("SmokeOffGui", false)
		local onGui = G.fakeGui("SmokeOnGui", true)
		local flipGui = G.fakeGui("SmokeFlipGui", true)
		fakes = { offGui, onGui, flipGui }
		ES.Show(G.result(PC, "Cloud", { epic }))
		G.advance(0.2)
		local allOff = true
		for _, g in ipairs(before) do
			allOff = allOff and g.Enabled == false
		end
		T.check(allOff, "roll look: the HUD, top bar, menu and boosts hide while the stage shows")
		T.check(not notifyOn or notify.Enabled == true, "roll look: NimbusNotify stays on (its toasts)")
		T.check(onGui.Enabled == false and flipGui.Enabled == false and offGui.Enabled == false, "roll look: every other Enabled ScreenGui hides too; the one off before stays off")
		T.check(G.gui() ~= nil and G.gui().Enabled == true, "roll look: NimbusHatch itself is on")
		local hiddenNow = HL.HiddenCount()
		T.check(hiddenNow >= #before + 2, "roll look: HiddenCount counts the guis the stage switched off", tostring(hiddenNow))
		local late = G.fakeGui("SmokeLateGui", true)
		fakes[#fakes + 1] = late
		G.advance(STEP)
		T.check(late.Enabled == false, "roll look: a ScreenGui added mid-roll hides too")
		onGui.Enabled = true -- someone opens it mid-roll: it is theirs now
		flipGui.Enabled = true
		G.advance(STEP)
		flipGui.Enabled = false -- ...and closes it again: it must stay closed after the roll
		G.advance(0.2)
		T.check(onGui.Enabled == true, "roll look: a gui someone turns on mid-roll is left on (no fight)")
		G.untilPhase(ES, "Reveal", 8)
		G.advance(0.3)
		ES.Done()
		G.advance(0.3)
		local allBack = true
		for _, g in ipairs(before) do
			allBack = allBack and g.Enabled == true
		end
		T.check(not ES.IsShowing() and allBack, "roll look: DONE -> the HUD is back")
		T.check(late.Enabled == true and onGui.Enabled == true, "roll look: DONE -> the gui added mid-roll is back, the one turned on mid-roll still on")
		T.check(offGui.Enabled == false, "roll look: the gui that was off before the roll stays off (not ours)")
		T.check(flipGui.Enabled == false, "roll look: a gui turned on and off again mid-roll stays off (its owner's choice)")
		T.eq(HL.HiddenCount(), 0, "roll look: DONE -> the hide list is empty")
		------------------------------------------------------------------ every other exit restores it too
		local function exitCase(label, play)
			ES.Show(G.result(PC, "Cloud", { epic }))
			G.advance(0.2)
			local hid = true
			for _, g in ipairs(before) do
				hid = hid and g.Enabled == false
			end
			play()
			local t0 = os.clock()
			while ES.IsShowing() and os.clock() - t0 < 9 do
				G.advance(STEP)
			end
			G.advance(0.2)
			local back = true
			for _, g in ipairs(before) do
				back = back and g.Enabled == true
			end
			T.check(hid and not ES.IsShowing() and back and HL.HiddenCount() == 0 and late.Enabled == true and offGui.Enabled == false,
				"roll look: HUD restore on every exit: " .. label, fmt("hid %s showing %s back %s count %d", tostring(hid), tostring(ES.IsShowing()), tostring(back), HL.HiddenCount()))
		end
		exitCase("Close() mid-strip", function()
			G.advance(1)
			ES.Close()
		end)
		exitCase("a match start mid-crack", function()
			G.untilPhase(ES, "Crack", 8)
			LocalPlayer:SetAttribute(Config.Attr.InMatch, true)
			G.advance(STEP)
		end)
		LocalPlayer:SetAttribute(Config.Attr.InMatch, env.keep[Config.Attr.InMatch])
		G.advance(0.2)
		exitCase("an injected phase error (Crack)", function()
			ES._InjectPhaseError = "Crack"
		end)
		exitCase("Back() on the reveal", function()
			G.untilPhase(ES, "Reveal", 8)
			G.advance(0.3)
			ES.Back()
		end)
		------------------------------------------------------------------ the cards and the window at 2.0 s (an Epic x1)
		local t0 = os.clock()
		ES.Show(G.result(PC, "Cloud", { epic }))
		G.until_(t0, 2.0)
		local cells = G.cells(1)
		local maxInst, worst = 0, ""
		local faceOk, shineOk, plateOk, shadowOk, rimOk, wordOk = true, true, true, true, true, true
		local seen, rimBad, cellW, cellH = 0, "", nil, nil
		local track = G.track(1)
		for _, c in ipairs(cells) do
			local n = G.count(c)
			if n > maxInst then
				maxInst, worst = n, c.Name
			end
			if c.Visible then
				seen = seen + 1
				cellW, cellH = c.AbsoluteSize.X, c.AbsoluteSize.Y
				faceOk = faceOk and c:FindFirstChildOfClass("UIGradient") ~= nil
				shineOk = shineOk and c:FindFirstChild("Shine") ~= nil
				local word = G.plateWord(c)
				plateOk = plateOk and c:FindFirstChild("Plate") ~= nil and word ~= nil and word:IsA("TextLabel")
				local slot = c.Name:match("%d+")
				local sh = track and track:FindFirstChild("Shadow" .. slot)
				shadowOk = shadowOk and sh ~= nil and sh.Visible
				if word and word.Text ~= "" then
					local rarity = nil
					for _, r in ipairs(RARITIES) do
						if string.upper(r) == word.Text then
							rarity = r
						end
					end
					wordOk = wordOk and rarity ~= nil and G.near(word.TextColor3, Color3.new(1, 1, 1)) and word.TextSize == 18
					local stroke = G.stroke(c)
					if rarity and stroke then
						local col = HL.RarityColor(rarity)
						local want = ORDER[rarity] >= 3 and HL.Shade(col, 0.05) or HL.Shade(col, -0.1)
						local alpha = ORDER[rarity] >= 3 and 0 or 0.25
						if not (G.near(stroke.Color, want) and abs(stroke.Transparency - alpha) < 0.01 and stroke.Thickness == 3) then
							rimOk = false
							rimBad = rimBad .. fmt("%s %s a%.2f t%d; ", rarity, G.c3(stroke.Color), stroke.Transparency, stroke.Thickness)
						end
					end
				end
			end
		end
		local tw = track and track.AbsoluteSize.X or 0
		T.check(#cells <= 12 and #cells >= seen and #cells == math.min(12, math.floor(tw / (cellW and cellW * 246 / 230 or 1)) + 2),
			"roll look cards: the recycled cells: as many as can show at once (floor(W / Step) + 2, at most 12)", fmt("%d cells, %d shown, track %.0f", #cells, seen, tw))
		T.check(maxInst <= 20, "roll look cards: an x1 cell is <= 20 instances (the card skin included)", fmt("%s: %d", worst, maxInst))
		T.check(seen >= 5 and faceOk and shineOk, "roll look cards: every shown cell has its UIGradient face and its Shine line", fmt("%d shown", seen))
		T.check(plateOk and wordOk, "roll look cards: the rarity Plate holds the word: upper-case, white, 18 px")
		T.check(shadowOk, "roll look cards: a Shadow<slot> sits under every shown card in the track")
		T.check(rimOk, "roll look cards: the rim: Shade(c, .05) opaque from Rare up, Shade(c, -.1) at 0.25 below, 3 px", rimBad)
		local ptr = G.pointer(1)
		local win = ptr and ptr:FindFirstChild("Window")
		T.check(ptr and win and ptr:FindFirstChild("Glow") and ptr:FindFirstChild("NotchTop") and ptr:FindFirstChild("NotchBottom"), "roll look window: Pointer holds Glow, Window, NotchTop, NotchBottom")
		if ptr and track and cellW then
			local pcx = G.centre(ptr)
			local tcx = G.centre(track)
			T.check(abs(pcx - tcx) <= 1 and abs(ptr.AbsoluteSize.X - (cellW + 16)) <= 1.5 and abs(ptr.AbsoluteSize.Y - (cellH + 16)) <= 1.5,
				"roll look window: centred on the track, the landed cell's box + 8 px a side", fmt("ptr %.1f x %.1f, cell %.1f x %.1f, centre %.1f / %.1f", ptr.AbsoluteSize.X, ptr.AbsoluteSize.Y, cellW, cellH, pcx, tcx))
		end
		local ws = G.stroke(win)
		T.check(ws ~= nil and G.near(ws.Color, K.GOLD) and ws.Thickness == 4, "roll look window: its stroke is Metrics.GOLD, 4 px, at 2.0 s", ws and G.c3(ws.Color) or "no stroke")
		local track2 = G.track(1)
		T.check(track2 and track2:FindFirstChild("FadeL") and track2:FindFirstChild("FadeR"), "roll look track: the two end fades FadeL / FadeR")
		-- the overshoot: the winner passes the window by 18 x S px at p = 1 (the cells travel left), then springs back
		local stripF = G.strip(1)
		Mock.AdvanceUntil(function()
			return stripF ~= nil and stripF:GetAttribute("Landed") == true
		end, 4, FINE)
		local tLand = os.clock()
		local landed = G.cellAt(1, K.WIN)
		local ref = nil
		for _, c in ipairs(G.cells(1)) do
			if c.Visible and c ~= landed then
				ref = c
			end
		end
		if T.check(landed ~= nil and ptr ~= nil and ref ~= nil, "roll look land: the landed cell (Index 34) shows") then
			local s = ref.AbsoluteSize.X / 230
			local over = G.centre(ptr) - G.centre(landed)
			T.check(abs(over - 18 * s) <= 1.5, "roll look land: at p = 1 the winner sits 18 x S px past the window (to its left)", fmt("%.2f px (S %.2f)", over, s))
			local pop = landed:FindFirstChild("Pop")
			local maxPop, sweeps, had, lateSweep, pop12 = 0, 0, false, false, nil
			while os.clock() - tLand < 0.45 do
				Mock.Advance(FINE, FINE)
				local dt = os.clock() - tLand
				pop = pop or landed:FindFirstChild("Pop")
				if pop then
					maxPop = math.max(maxPop, pop.Scale)
					if dt <= 0.125 then
						pop12 = math.max(pop12 or 0, pop.Scale)
					end
				end
				local has = landed:FindFirstChild("Sweep") ~= nil
				if has and not had then
					sweeps = sweeps + 1
				end
				if has and dt > 0.4 then
					lateSweep = true
				end
				had = has
			end
			T.check(pop ~= nil and pop:IsA("UIScale") and (pop12 or 0) >= 1.14, "roll look land: the landed card's UIScale Pop reaches >= 1.14 within 0.12 s", tostring(pop12))
			T.check(pop ~= nil and abs(pop.Scale - 1.09) <= 0.01, "roll look land: ...and rests at 1.09", pop and tostring(pop.Scale) or "nil")
			T.check(sweeps == 1 and not lateSweep, "roll look land: one shine Sweep, gone by Land + 0.4", fmt("%d sweeps, late %s", sweeps, tostring(lateSweep)))
			local back = G.centre(ptr) - G.centre(landed)
			T.check(abs(back) <= 1, "roll look land: by the end of Land the winner is back under the window", fmt("%.2f px", back))
			local dimOk = true
			for _, c in ipairs(G.cells(1)) do
				if c.Visible and c ~= landed and abs(c.BackgroundTransparency - 0.6) > 0.01 then
					dimOk = false
				end
			end
			T.check(dimOk, "roll look land: the other cards dim to 0.6")
			local landedWord = G.plateWord(landed)
			T.check(landedWord and landedWord.Text == "EPIC" and G.stroke(landed) and G.stroke(landed).Thickness == 5, "roll look land: the landed card reads EPIC with a 5 px rim")
		end
		ES.Close()
		G.advance(0.4)
		------------------------------------------------------------------ B's colour tell: Rare turns the window blue 0.7 s before the land
		t0 = os.clock()
		ES.Show(G.result(PC, "Cloud", { rare }))
		local goldOk = true
		while os.clock() - t0 < 2.6 do
			G.advance(STEP)
			local w = G.pointer(1) and G.pointer(1):FindFirstChild("Window")
			local st = G.stroke(w)
			if os.clock() - t0 > 0.4 and not (st and G.near(st.Color, K.GOLD)) then
				goldOk = false
			end
		end
		T.check(goldOk, "roll look tell: the window stays gold until 0.7 s before the land")
		G.until_(t0, 2.95)
		ptr = G.pointer(1)
		local rareC = G.rarityOf(Config, "Rare")
		local wst = G.stroke(ptr and ptr:FindFirstChild("Window"))
		local gst = G.stroke(ptr and ptr:FindFirstChild("Glow"))
		local notch = ptr and ptr:FindFirstChild("NotchTop")
		T.check(wst and G.near(wst.Color, rareC, 2) and gst and G.near(gst.Color, rareC, 2) and notch and G.near(notch.BackgroundColor3, rareC, 2),
			"roll look tell: Rare: at Land - 0.7 + 0.3 s the window, its glow and the notches are the Rare colour", fmt("%s / %s / %s", G.c3(wst and wst.Color), G.c3(gst and gst.Color), G.c3(notch and notch.BackgroundColor3)))
		T.check(ptr and ptr:GetAttribute("Tell") == true, "roll look tell: the Pointer carries Tell = true")
		ES.Close()
		G.advance(0.4)
		t0 = os.clock()
		ES.Show(G.result(PC, "Cloud", { common }))
		local commonGold, told = true, false
		while os.clock() - t0 < 3.9 do
			G.advance(STEP)
			local p = G.pointer(1)
			local st = G.stroke(p and p:FindFirstChild("Window"))
			if p and os.clock() - t0 > 0.4 and not (st and G.near(st.Color, K.GOLD)) then
				commonGold = false
			end
			if p and p:GetAttribute("Tell") then
				told = true
			end
		end
		T.check(commonGold and not told, "roll look tell: no tell below Rare: a Common winner keeps the gold window every frame (no fake tease)")
		ES.Close()
		G.advance(0.4)
		------------------------------------------------------------------ a resize during Land: the window refits, the pop rests, the roll goes on
		ES.Show(G.result(PC, "Cloud", { epic }))
		stripF = G.strip(1)
		Mock.AdvanceUntil(function()
			return stripF ~= nil and stripF:GetAttribute("Landed") == true
		end, 4, FINE)
		G.advance(0.1)
		Mock.SetViewport(844, 390)
		G.advance(STEP)
		ptr = G.pointer(1)
		landed = G.cellAt(1, K.WIN)
		ref = nil
		for _, c in ipairs(G.cells(1)) do
			if c.Visible and c ~= landed then
				ref = c
			end
		end
		local popR = landed and landed:FindFirstChild("Pop")
		T.check(ES.Layout() == "Phone" and popR ~= nil and abs(popR.Scale - 1.09) <= 0.01, "roll look resize during Land: the landed card's pop rests at 1.09 on the new layout", popR and tostring(popR.Scale) or "no Pop")
		if ptr and ref then
			local tr = G.track(1)
			T.check(abs(ptr.AbsoluteSize.X - (ref.AbsoluteSize.X + 12)) <= 1.5 and abs(ptr.AbsoluteSize.Y - (ref.AbsoluteSize.Y + 12)) <= 1.5 and tr and abs(G.centre(ptr) - G.centre(tr)) <= 1,
				"roll look resize during Land: the window refits round the landed cell (+ 6 px a side on the phone)", fmt("ptr %.1f x %.1f, cell %.1f x %.1f", ptr.AbsoluteSize.X, ptr.AbsoluteSize.Y, ref.AbsoluteSize.X, ref.AbsoluteSize.Y))
		else
			T.check(false, "roll look resize during Land: the window and a cell show")
		end
		T.check(G.untilPhase(ES, "Reveal", 6) ~= nil, "roll look resize during Land: the roll reaches the reveal")
		ES.Close()
		Mock.SetViewport(1920, 1080)
		G.advance(0.6)
		------------------------------------------------------------------ budgets: x1 <= 450 and x3 <= 750 instances at every frame
		local function peak(defs, rid)
			ES.Show(G.result(PC, rid, defs))
			local most, at = 0, ""
			local tS = os.clock()
			while os.clock() - tS < 8.5 do
				local st = ES.Stats()
				if (st.Instances or 0) > most then
					most, at = st.Instances, fmt("%s at %.2f s", tostring(ES.Phase()), os.clock() - tS)
				end
				if ES.Phase() == "Reveal" then
					break
				end
				G.advance(STEP)
			end
			ES.Close()
			G.advance(0.4)
			return most, at
		end
		local x1, x1At = peak({ epic }, "Cloud")
		T.check(x1 <= 450, "roll look budget: x1 <= 450 instances at every frame of the roll", fmt("%d (%s)", x1, x1At))
		local storm = function(r)
			return PC.RarityPool("Storm", r)[1]
		end
		local x3, x3At = peak({ storm("Rare") or rare, storm("Legendary") or epic, storm("Common") or epic }, "Storm")
		T.check(x3 <= 750, "roll look budget: x3 <= 750 instances at every frame of the roll", fmt("%d (%s)", x3, x3At))
		T.info("roll look budget peaks", fmt("x1 %d (%s), x3 %d (%s)", x1, x1At, x3, x3At))
	end)
	if not ok then
		T.check(false, "roll look: the scenario ran without an error", tostring(err))
	end
	for _, g in ipairs(fakes) do
		g:Destroy()
	end
	G.restore(env)
end)

----------------------------------------------------------------------------------------------------
-- client_roll_look_open (Task 2: the plinth, the rise, Gemini's tweak, the punch, the image keys)
----------------------------------------------------------------------------------------------------
S.client_roll_look_open = guarded("client_roll_look_open", function()
	local env = G.setup(1920, 1080)
	local ES, HL, PC, Config = env.ES, env.HL, env.PC, env.Config
	local FX = G.req("client/UI/HatchFx")
	local GQ = G.req("client/GraphicsQuality")
	if not T.check(type(HL) == "table" and type(HL.Plinth) == "function" and type(HL.Image) == "function" and type(HL.IMAGES) == "table", "roll look open: HatchLook.Plinth / Image / IMAGES exist")
		or not T.check(type(ES) == "table" and type(PC) == "table" and type(FX) == "table" and type(GQ) == "table", "roll look open: EggStage, PetCatalog, HatchFx and GraphicsQuality load") then
		G.restore(env)
		return
	end
	local K = ES.Metrics
	local oldEff = GQ.Effective
	local mode = "High"
	GQ.Effective = function()
		return mode
	end
	local ok, err = pcall(function()
		local rgb = Color3.fromRGB
		local NEUTRAL = HL.Metrics.PLINTH.Neutral
		local RING_TINT = FX.Metrics.RING_TINT
		local epicC = G.rarityOf(Config, "Epic")
		local epic = PC.RarityPool("Cloud", "Epic")[1]
		local Tm = ES.Timings(false, 1)
		local landEnd = Tm.Intro + Tm.Strip + Tm.Land
		local riseEnd = landEnd + Tm.Rise
		local shake1 = riseEnd + K.SHAKE[1][1] * Tm.Crack
		local burstAt = riseEnd + Tm.Crack
		------------------------------------------------------------------ an Epic x1, every 1/60 s from the Show
		local rec = { maxPop = 0, punchEarly = 0 }
		local t0 = os.clock()
		ES.Show(G.result(PC, "Cloud", { epic }))
		while os.clock() - t0 < Tm.RevealAt + 0.12 do
			Mock.Advance(FINE, FINE)
			local t = os.clock() - t0
			local ph = ES.Phase()
			if (ph == "Rise" or ph == "Crack" or ph == "Burst") and not rec.over then
				local o = G.over(ES, 450)
				if o then
					rec.over = fmt("%s at %.2f s: %s", ph, t, o)
				end
			end
			local p = G.plinth(1)
			if p.Box and not rec.first then
				rec.first = { pop = p.Pop and p.Pop.Scale or -1, top = p.Top and p.Top.BackgroundTransparency or -1, ph = ph }
			end
			if p.Pop and ph == "Rise" then
				rec.maxPop = math.max(rec.maxPop, p.Pop.Scale)
			end
			if t >= riseEnd + 0.02 and not rec.rest then
				local egg, box = G.hero("Egg1"), p.Box
				local kids = {}
				for _, c in ipairs(box and box:GetChildren() or {}) do
					if c:IsA("GuiObject") then
						kids[#kids + 1] = c.Name
					end
				end
				table.sort(kids)
				local fit = G.content() and G.content():FindFirstChild("Fit")
				local eh = egg and (egg:GetAttribute("Size") or 0) * (fit and fit.Scale or 1) or 0
				local rays = G.hero("Rays")
				rec.rest = {
					kids = table.concat(kids, " "), pop = p.Pop and p.Pop.Scale or -1, top = p.Top and p.Top.BackgroundTransparency or -1,
					topH = (p.Top and box) and p.Top.AbsoluteSize.Y / box.AbsoluteSize.Y or -1,
					topMid = (p.Top and box) and (p.Top.AbsolutePosition.Y + p.Top.AbsoluteSize.Y / 2) - box.AbsolutePosition.Y or 99,
					sideEnd = (p.Side and box) and (p.Side.AbsolutePosition.Y + p.Side.AbsoluteSize.Y) - box.AbsolutePosition.Y - 0.667 * box.AbsoluteSize.Y or 99,
					boxW = box and box.AbsoluteSize.X or -1, boxH = box and box.AbsoluteSize.Y or -1, eh = eh,
					foot = (egg and box) and (box.AbsolutePosition.Y - (egg.AbsolutePosition.Y + egg.AbsoluteSize.Y)) or 99,
					rim = p.Rim and p.Rim.Color, rimT = p.Rim and p.Rim.Thickness, rays = rays ~= nil and rays.Visible,
				}
			end
			if t >= shake1 + 0.3 and not rec.tweak then
				local ring = G.hero("CloudRing1")
				local rays = G.hero("Rays")
				rec.tweak = {
					rim = p.Rim and p.Rim.Color, ring = p.RingStroke and p.RingStroke.Color, glow = p.Glow1 and p.Glow1.BackgroundColor3, cloud = ring and ring.GroupColor3,
					rays = rays ~= nil and rays.Visible, raysA = rays and rays.GroupTransparency or 1, spin = rays ~= nil and G.spinning(rays),
				}
			end
			if t >= riseEnd + 0.05 and t < shake1 - 0.02 and not rec.early then
				local rays = G.hero("Rays")
				if rays and rays.Visible then
					rec.early = "the rays show before the first shake"
				elseif not (p.Rim and G.near(p.Rim.Color, HL.Shade(NEUTRAL, 0.25))) then
					rec.early = "the rim is tinted before the first shake: " .. G.c3(p.Rim and p.Rim.Color)
				end
			end
			local stage = G.stage()
			local punch = stage and stage:FindFirstChild("Punch")
			local egg = G.hero("Egg1")
			if egg and egg:GetAttribute("State") == "Burst" and not rec.burstT then
				rec.burstT = t
				rec.sparks = G.burstFrame() and G.burstFrame():GetAttribute("Sparks")
				local holder = G.hero("Halves1")
				rec.halves2D = holder ~= nil and holder:GetAttribute("Split3D") == false and holder:FindFirstChild("HalfTop") ~= nil and holder:FindFirstChild("HalfBottom") ~= nil
			end
			if rec.burstT and t <= rec.burstT + 0.1 and punch then
				rec.punchEarly = math.max(rec.punchEarly, punch.Scale)
			end
		end
		T.check(rec.first ~= nil and rec.first.pop >= 0.6 - 0.005 and rec.first.pop <= 0.72 and rec.first.top >= 0.85,
			"roll look open: the rise's first frame: the plinth box's UIScale Pop starts near 0.6, its Top nearly clear", rec.first and fmt("%s: pop %.3f, top %.2f", rec.first.ph, rec.first.pop, rec.first.top) or "no Pedestal1")
		T.check(rec.maxPop > 1.01, "roll look open: the plinth springs past 1 over the rise (Back Out)", fmt("%.3f", rec.maxPop))
		local r = rec.rest
		if T.check(r ~= nil, "roll look open: (setup) sampled at the rise's end") then
			T.eq(r.kids, "Glow1 Glow2 Ring Side Top", "roll look open: Pedestal1 is the flat lit plinth: Top, Side, Ring, the soft halo Glow1..2 (no drum, no puffs, no bars)")
			T.check(abs(r.pop - 1) <= 0.01 and r.top <= 0.01, "roll look open: at the rise's end the plinth rests: Pop 1, Top opaque", fmt("pop %.3f, top %.3f", r.pop, r.top))
			T.check(abs(r.topH - 0.667) <= 0.01 and abs(r.sideEnd) <= 1.5, "roll look open: the Top is 0.667 of the box tall, the Side shows 0.333 under it", fmt("top %.3f, side end %+.1f px", r.topH, r.sideEnd))
			T.check(abs(r.topMid) <= 1.5, "roll look open: the Top's centre line sits on the egg's foot (the box's top): the egg stands in the middle of the disc", fmt("%+.1f px", r.topMid))
			T.check(abs(r.boxW - 1.1 * r.eh) <= 1.5 and abs(r.boxH - 0.24 * r.eh) <= 1.5 and abs(r.foot) <= 0.6, "roll look open: the box is still 1.1 x / 0.24 x the egg, right under it",
				fmt("egg %.1f, box %.1f x %.1f, gap %.1f", r.eh, r.boxW, r.boxH, r.foot))
			T.check(G.near(r.rim, HL.Shade(NEUTRAL, 0.25)) and r.rimT == 3 and r.rays == false, "roll look open: before the shakes the plinth is neutral (its 3 px rim Shade(neutral, .25)) and no rays show",
				fmt("%s, %s px, rays %s", G.c3(r.rim), tostring(r.rimT), tostring(r.rays)))
		end
		T.check(rec.early == nil, "roll look open: nothing of the tweak before the first shake", tostring(rec.early))
		local w = rec.tweak
		if T.check(w ~= nil, "roll look open: (setup) sampled 0.3 s into the first shake") then
			T.check(G.near(w.rim, HL.Shade(epicC, 0.25)) and G.near(w.ring, HL.Shade(epicC, 0.4)) and G.near(w.glow, HL.Shade(epicC, 0.2)),
				"roll look open: Gemini's tweak (Epic): the plinth's rim, inner ring and glow turn the rarity colour at the first shake", fmt("%s / %s / %s", G.c3(w.rim), G.c3(w.ring), G.c3(w.glow)))
			T.check(G.near(w.cloud, RING_TINT:Lerp(epicC, 0.5), 2), "roll look open: ...the cloud ring's GroupColor3 too (RING_TINT half way to Epic)", G.c3(w.cloud))
			T.check(w.rays and w.raysA <= 0.76 and w.spin, "roll look open: ...and the rays come up faint (GroupTransparency 0.75) and turn", fmt("visible %s, %.2f, spin %s", tostring(w.rays), w.raysA, tostring(w.spin)))
		end
		T.check(rec.over == nil, "roll look open: x1 within the budgets at every frame of Rise / Crack / Burst (450 instances, 24 tweens, 1 Heartbeat, <= 2 effects)", tostring(rec.over))
		local stage = G.stage()
		local punch = stage and stage:FindFirstChild("Punch")
		T.check(stage and punch and punch:IsA("UIScale") and stage.AnchorPoint == Vector2.new(0.5, 0.5), "roll look open: Stage has a UIScale Punch and is anchored at its centre")
		T.check(rec.punchEarly >= 1.04, "roll look open: the burst's punch reaches >= 1.04 within 0.1 s", fmt("%.3f", rec.punchEarly))
		T.check(punch and abs(punch.Scale - 1) <= 0.005, "roll look open: ...and is back to 1 on the reveal", punch and tostring(punch.Scale) or "nil")
		T.check(rec.halves2D == true, "roll look open: without the halves' ids the 2D HalfTop / HalfBottom open (16.14 stands)")
		T.eq(rec.sparks, 28, "roll look open: 28 sparks for an Epic on PC")
		T.eq(ES.Phase(), "Reveal", "roll look open: (setup) the reveal")
		local pr = G.plinth(1)
		T.check(pr.Top and G.shown(pr.Top) and pr.Top.BackgroundTransparency <= 0.01 and G.near(pr.Rim and pr.Rim.Color, HL.Shade(epicC, 0.25)),
			"roll look open: on the reveal the pet stands on the plinth in the rarity colour", G.c3(pr.Rim and pr.Rim.Color))
		ES.Close()
		G.advance(0.4)
		------------------------------------------------------------------ Common / Uncommon: no tweak until the burst
		for _, rarity in ipairs({ "Common", "Uncommon" }) do
			local def = PC.RarityPool("Cloud", rarity)[1]
			local c = G.rarityOf(Config, rarity)
			local bad, ringAt = nil, nil
			t0 = os.clock()
			ES.Show(G.result(PC, "Cloud", { def }))
			while os.clock() - t0 < Tm.RevealAt + 0.1 do
				G.advance(STEP)
				local t = os.clock() - t0
				local p = G.plinth(1)
				local rays = G.hero("Rays")
				if t >= riseEnd + 0.02 and t < burstAt - 0.02 and not bad then
					if rays and rays.Visible then
						bad = fmt("rays at %.2f s", t)
					elseif not (p.Rim and G.near(p.Rim.Color, HL.Shade(NEUTRAL, 0.25))) then
						bad = fmt("rim %s at %.2f s", G.c3(p.Rim and p.Rim.Color), t)
					end
				end
				if t >= shake1 + 0.3 and not ringAt then
					local ring = G.hero("CloudRing1")
					ringAt = ring and ring.GroupColor3
				end
			end
			T.check(bad == nil, "roll look open: no tweak below Rare: " .. rarity .. " keeps the neutral plinth and no rays until the burst", tostring(bad))
			T.check(G.near(ringAt, RING_TINT:Lerp(c, 0.12), 2), "roll look open: " .. rarity .. "'s cloud ring keeps its rest tint through the shakes", G.c3(ringAt))
			local p = G.plinth(1)
			T.check(ES.Phase() == "Reveal" and G.near(p.Rim and p.Rim.Color, HL.Shade(c, 0.25)), "roll look open: " .. rarity .. "'s plinth takes its colour at the burst (on the reveal)", G.c3(p.Rim and p.Rim.Color))
			ES.Close()
			G.advance(0.4)
		end
		------------------------------------------------------------------ Low graphics: no punch
		mode = "Low"
		t0 = os.clock()
		ES.Show(G.result(PC, "Cloud", { epic }))
		local lowMax = 0
		while os.clock() - t0 < Tm.RevealAt + 0.1 do
			Mock.Advance(FINE, FINE)
			local st = G.stage()
			local pu = st and st:FindFirstChild("Punch")
			if pu then
				lowMax = math.max(lowMax, pu.Scale)
			end
		end
		T.check(lowMax <= 1.0001, "roll look open: Low graphics: no punch (Stage's Punch stays 1)", fmt("%.3f", lowMax))
		ES.Close()
		G.advance(0.4)
		mode = "High"
		------------------------------------------------------------------ the image keys and their frame fallbacks
		T.check(HL.IMAGES.Rays == "hatch_rays" and HL.IMAGES.Glow == "hatch_glow" and HL.IMAGES.Sparkle == "hatch_sparkle", "roll look open: HatchLook.IMAGES names the three optional images")
		HL._Textures = { hatch_glow = 123 }
		T.eq(HL.Image("hatch_glow"), "rbxassetid://123", "roll look open: Image(key) joins a TextureIds id")
		T.check(HL.Image("hatch_rays") == nil and HL.Image("hatch_sparkle") == nil, "roll look open: Image(key) is nil without an id")
		t0 = os.clock()
		ES.Show(G.result(PC, "Cloud", { epic }))
		G.until_(t0, shake1 + 0.3)
		local ped = G.hero("Pedestal1")
		local img = ped and ped:FindFirstChild("Glow")
		T.check(img ~= nil and img:IsA("ImageLabel") and img.Image == "rbxassetid://123" and G.near(img.ImageColor3, HL.Shade(epicC, 0.2)) and ped:FindFirstChild("Glow1") == nil,
			"roll look open: with a hatch_glow id the plinth's glow is one ImageLabel Glow tinted Shade(c, .2) (after the tweak)", img and fmt("%s %s %s", img.ClassName, tostring(img.Image), G.c3(img.ImageColor3)) or "none")
		ES.Close()
		G.advance(0.4)
		HL._Textures = {}
		T.check(HL.Image("hatch_glow") == nil, "roll look open: Image(key) is nil when the key has no id")
		t0 = os.clock()
		ES.Show(G.result(PC, "Cloud", { epic }))
		G.until_(t0, riseEnd + 0.05)
		ped = G.hero("Pedestal1")
		T.check(ped and ped:FindFirstChild("Glow") == nil and ped:FindFirstChild("Glow1") and ped:FindFirstChild("Glow2") and ped.Glow1:FindFirstChildOfClass("UIGradient"),
			"roll look open: without an id the frame fallback: Glow1..2, round frames fading out through their UIGradients")
		ES.Close()
		G.advance(0.4)
		HL._Textures = false
		T.check(HL.Image("hatch_glow") == nil and HL.Image("hatch_rays") == nil, "roll look open: _Textures = false reads shared/TextureIds again (no hatch_* ids today)")
		------------------------------------------------------------------ a resize mid-tweak: snapped, nothing stranded
		t0 = os.clock()
		ES.Show(G.result(PC, "Cloud", { epic }))
		G.until_(t0, shake1 + 0.1)
		Mock.SetViewport(1280, 720)
		G.advance(STEP)
		local pz = G.plinth(1)
		local ring = G.hero("CloudRing1")
		local rays = G.hero("Rays")
		T.check(pz.Rim and G.near(pz.Rim.Color, HL.Shade(epicC, 0.25)) and pz.Pop and abs(pz.Pop.Scale - 1) <= 0.01 and pz.Top and pz.Top.BackgroundTransparency <= 0.01,
			"roll look open: a resize mid-tweak snaps the plinth (rarity rim, Pop 1, opaque)", fmt("%s, pop %s", G.c3(pz.Rim and pz.Rim.Color), tostring(pz.Pop and pz.Pop.Scale)))
		T.check(ring and G.near(ring.GroupColor3, RING_TINT:Lerp(epicC, 0.5), 2) and rays and rays.Visible and rays.GroupTransparency <= 0.76 and G.spinning(rays),
			"roll look open: ...the cloud ring keeps the tint and the rays stay faint and turning", fmt("%s, rays %s %.2f", G.c3(ring and ring.GroupColor3), tostring(rays and rays.Visible), rays and rays.GroupTransparency or -1))
		T.check(G.untilPhase(ES, "Reveal", 4) ~= nil, "roll look open: ...and the roll reaches the reveal")
		ES.Close()
		Mock.SetViewport(1920, 1080)
		G.advance(0.6)
		------------------------------------------------------------------ x3 (Storm Rare, Legendary, Common)
		local storm = function(rr)
			return PC.RarityPool("Storm", rr)[1]
		end
		local T3 = ES.Timings(false, 3)
		local rise3 = T3.Intro + T3.Strip + 2 * T3.LandGap + T3.Land + T3.Rise
		local crack = function(j)
			return rise3 + (j - 1) * T3.Stagger
		end
		local first = function(j)
			return crack(j) + K.SHAKE[1][1] * T3.Crack
		end
		local rareC, legC = G.rarityOf(Config, "Rare"), G.rarityOf(Config, "Legendary")
		local x3 = { over = nil }
		-- (Storm has no Common pool: the third pull is a Cloud Common, a below-Rare egg)
		local trio = { storm("Rare") or PC.RarityPool("Cloud", "Rare")[1], storm("Legendary"), storm("Common") or PC.RarityPool("Cloud", "Common")[1] }
		T.check(#trio == 3 and trio[2] ~= nil, "roll look open x3: (setup) a Rare, a Legendary and a Common pull")
		t0 = os.clock()
		ES.Show(G.result(PC, "Storm", trio))
		while os.clock() - t0 < T3.RevealAt + 0.1 do
			G.advance(STEP)
			local t = os.clock() - t0
			local o = G.over(ES, 750)
			if o and not x3.over then
				x3.over = fmt("%s at %.2f s: %s", tostring(ES.Phase()), t, o)
			end
			local n = ES.Stats().Instances or 0
			if n > (x3.peak or 0) then
				x3.peak, x3.peakAt = n, fmt("%s at %.2f s", tostring(ES.Phase()), t)
			end
			if t >= rise3 + 0.05 and not x3.three then
				local n = 0
				for j = 1, 3 do
					local p = G.plinth(j)
					if p.Top and p.Side then
						n = n + 1
					end
				end
				x3.three = n
			end
			if t >= first(1) + 0.3 and not x3.t1 then
				local p1, p3 = G.plinth(1), G.plinth(3)
				local rays = G.hero("Rays")
				x3.t1 = { rim1 = p1.Rim and p1.Rim.Color, rim3 = p3.Rim and p3.Rim.Color, rays = rays ~= nil and rays.Visible }
			end
			local e3 = G.hero("Egg3")
			if t >= rise3 + 0.05 and e3 and e3:GetAttribute("State") ~= "Burst" and e3:GetAttribute("State") ~= "Open" and not x3.bad3 then
				local p3 = G.plinth(3)
				if not (p3.Rim and G.near(p3.Rim.Color, HL.Shade(NEUTRAL, 0.25))) then
					x3.bad3 = fmt("rim %s at %.2f s", G.c3(p3.Rim and p3.Rim.Color), t)
				end
			end
			if t >= first(2) + 0.3 and not x3.t2 then
				local p2 = G.plinth(2)
				x3.t2 = p2.Rim and p2.Rim.Color
			end
		end
		T.eq(x3.three, 3, "roll look open x3: three plinths (Top, Side) at the rise's end")
		T.check(x3.t1 and G.near(x3.t1.rim1, HL.Shade(rareC, 0.25)) and x3.t1.rays == false, "roll look open x3: Egg1 (Rare) tints its own plinth at its first shake; the rays wait for the best pull (Legendary)",
			x3.t1 and fmt("%s, rays %s", G.c3(x3.t1.rim1), tostring(x3.t1.rays)) or "not sampled")
		T.check(G.near(x3.t2, HL.Shade(legC, 0.25)), "roll look open x3: Egg2 (Legendary) tints its plinth at its first shake", G.c3(x3.t2))
		T.check(x3.bad3 == nil, "roll look open x3: Egg3 (Common) keeps the neutral plinth until its burst", tostring(x3.bad3))
		T.check(x3.over == nil, "roll look open x3: within the budgets at every frame (750 instances, 24 tweens)", tostring(x3.over))
		T.info("roll look open x3 peak", fmt("%s (%s)", tostring(x3.peak), tostring(x3.peakAt)))
		ES.Close()
		G.advance(0.4)
	end)
	if not ok then
		T.check(false, "roll look open: the scenario ran without an error", tostring(err))
	end
	HL._Textures = false
	GQ.Effective = oldEff
	G.restore(env)
end)

----------------------------------------------------------------------------------------------------
-- client_roll_look_phone
----------------------------------------------------------------------------------------------------
S.client_roll_look_phone = guarded("client_roll_look_phone", function()
	local env = G.setup(844, 390)
	local ES, HL, PC = env.ES, env.HL, env.PC
	if not T.check(type(HL) == "table" and type(ES) == "table" and type(PC) == "table", "roll look phone: HatchLook, EggStage and PetCatalog load") then
		G.restore(env)
		return
	end
	local ok, err = pcall(function()
		local epic = PC.RarityPool("Cloud", "Epic")[1]
		local SKIP = { Rays = true, Flash = true, Vignette = true }
		for _, size in ipairs({ { 844, 390 }, { 640, 360 } }) do
			local label = fmt("roll look phone %dx%d", size[1], size[2])
			Mock.SetViewport(size[1], size[2])
			G.advance(0.3)
			local t0 = os.clock()
			ES.Show(G.result(PC, "Cloud", { epic }))
			G.until_(t0, 2.0)
			T.check(ES.Layout() == "Phone", label .. ": (setup) the phone layout", tostring(ES.Layout()))
			local cell = nil
			for _, c in ipairs(G.cells(1)) do
				if c.Visible and G.plateWord(c) and G.plateWord(c).Text ~= "" then
					cell = c
				end
			end
			if T.check(cell ~= nil, label .. ": a shown card with its plate") then
				T.check(abs(cell.AbsoluteSize.X - 130) <= 1 and abs(cell.AbsoluteSize.Y - 160) <= 1, label .. ": x1 cards 130 x 160", fmt("%.1f x %.1f", cell.AbsoluteSize.X, cell.AbsoluteSize.Y))
				T.eq(G.plateWord(cell).TextSize, 15, label .. ": the plate word is 15 px")
			end
			local ptr = G.pointer(1)
			local ws = G.stroke(ptr and ptr:FindFirstChild("Window"))
			local notch = ptr and ptr:FindFirstChild("NotchTop")
			T.check(ws and ws.Thickness == 3 and notch and abs(notch.AbsoluteSize.X - 10) <= 0.5, label .. ": the window's stroke 3 px, its notches 10 px", fmt("%s / %s", tostring(ws and ws.Thickness), tostring(notch and notch.AbsoluteSize.X)))
			RedoGeom.check(G.content(), label .. " strip", { MinText = 15, NoOverlap = { "Skip", "FastHatch" }, Skip = SKIP })
			ES.Close()
			G.advance(0.4)
		end
		-- x3 lite cards at 640x360
		Mock.SetViewport(640, 360)
		G.advance(0.3)
		local storm = function(r)
			return PC.RarityPool("Storm", r)[1]
		end
		local t0 = os.clock()
		ES.Show(G.result(PC, "Storm", { storm("Rare") or epic, storm("Legendary") or epic, storm("Common") or epic }))
		G.until_(t0, 2.0)
		local liteOk, most, shadows = true, 0, 0
		for j = 1, 3 do
			local track = G.track(j)
			for _, c in ipairs(track and track:GetChildren() or {}) do
				if c.Name:match("^Shadow%d+$") then
					shadows = shadows + 1
				end
			end
			for _, c in ipairs(G.cells(j)) do
				most = math.max(most, G.count(c))
				if c:FindFirstChild("Plate") or c:FindFirstChild("Tint") then
					liteOk = false
				end
				if c.Visible and not (c:FindFirstChildOfClass("UIGradient") and c:FindFirstChild("Shine")) then
					liteOk = false
				end
			end
		end
		T.check(#G.cells(1) > 0 and liteOk and shadows == 0, "roll look phone x3: lite cards (face and shine; no Shadow, Tint or Plate)", fmt("shadows %d", shadows))
		T.check(most <= 16, "roll look phone x3: an x3 cell is <= 16 instances", tostring(most))
		ES.Close()
		G.advance(0.4)
		-- (Task 2) the phone plinth, the spark cap, the reveal's lip at 844x390
		Mock.SetViewport(844, 390)
		G.advance(0.3)
		local Tm = ES.Timings(false, 1)
		local riseEnd = Tm.Intro + Tm.Strip + Tm.Land + Tm.Rise
		t0 = os.clock()
		ES.Show(G.result(PC, "Cloud", { epic }))
		G.until_(t0, riseEnd + 0.05)
		local p = G.plinth(1)
		local egg = G.hero("Egg1")
		local eh = egg and (egg:GetAttribute("Size") or 0) or 0
		if T.check(p.Box and p.Top and p.Side and egg, "roll look phone plinth: Pedestal1 holds the plinth (Top, Side) under Egg1") then
			T.check(abs(p.Box.AbsoluteSize.X - 1.1 * eh) <= 1.5 and abs(p.Box.AbsoluteSize.Y - 0.24 * eh) <= 1.5 and abs(p.Top.AbsoluteSize.Y / p.Box.AbsoluteSize.Y - 0.667) <= 0.01,
				"roll look phone plinth: 1.1 x / 0.24 x the egg, the Top 0.667 of it", fmt("egg %d, box %.1f x %.1f, top %.1f", eh, p.Box.AbsoluteSize.X, p.Box.AbsoluteSize.Y, p.Top.AbsoluteSize.Y))
			T.check(p.Rim and p.Rim.Thickness == 2, "roll look phone plinth: a 2 px rim", tostring(p.Rim and p.Rim.Thickness))
		end
		local sparks = nil
		while os.clock() - t0 < Tm.RevealAt + 0.1 do
			G.advance(STEP)
			local e = G.hero("Egg1")
			if e and e:GetAttribute("State") == "Burst" and sparks == nil then
				sparks = G.burstFrame() and G.burstFrame():GetAttribute("Sparks")
			end
		end
		T.eq(sparks, 16, "roll look phone: the burst's sparks are capped at 16 (an Epic's 28)")
		T.eq(ES.Phase(), "Reveal", "roll look phone: (setup) the reveal")
		p = G.plinth(1)
		T.check(p.Top and G.shown(p.Top) and abs(p.Top.AbsoluteSize.Y - 12) <= 0.6 and not G.shown(p.Side) and not G.shown(p.Ring) and not G.shown(p.Glow1),
			"roll look phone: the reveal keeps the 12 px lip (the plinth's Top only)", p.Top and fmt("%.1f px", p.Top.AbsoluteSize.Y) or "no Top")
		ES.Close()
		G.advance(0.4)
	end)
	if not ok then
		T.check(false, "roll look phone: the scenario ran without an error", tostring(err))
	end
	G.restore(env)
end)

return S
