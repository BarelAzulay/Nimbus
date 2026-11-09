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
--   client_roll_look_phone  (phone world; Task 1) 844x390 and 640x360: the x1 cards 130 x 160 with 15 px plate words, the
--       window's 3 px stroke and 10 px notches, every text >= 15 px and nothing off the screen (RedoGeom.check); the x3 lite
--       cards (no Shadow, Tint or Plate; <= 16 instances a cell)
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
	end)
	if not ok then
		T.check(false, "roll look phone: the scenario ran without an error", tostring(err))
	end
	G.restore(env)
end)

return S
