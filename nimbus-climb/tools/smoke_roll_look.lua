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
--   client_roll_look_open  (client, 1920x1080; Task 2) the opening: the lit plinth in Pedestal1 (review round 2: every part a
--       true ellipse of the built-in disc: Top 0.85 of the box with its Rim disc 3 px larger, Side + Wall + Edge, the inner
--       Ring under its Cover, the soft halo Glow1..2; 16 instances; no drum, no puffs, no bars; the Top's centre line on the egg's foot; the box still
--       1.1 x / 0.24 x the egg under it), neutral until the shakes; the rise (the box's UIScale Pop 0.6 -> past 1 -> 1, the
--       Top fading in from 1); Gemini's tweak from Rare up at the first shake (the plinth's rim / ring / glow, the cloud
--       ring and faint turning rays in the rarity colour) and nothing of it below Rare until the burst (Common, Uncommon);
--       the burst's punch (Hero's UIScale "Punch" >= 1.04 within 0.1 s, Burst's following it, the Skip chip unmoved, back
--       to 1 by + 0.4; none on Low), the 2D halves
--       without ids, 28 sparks for an Epic on PC; the plinth in the rarity colour on the reveal; the image keys
--       (HatchLook.IMAGES, HatchLook.Image with HatchLook._Textures, an ImageLabel Glow with an id, the frames without);
--       a resize mid-tweak (snapped, nothing stranded, the roll reaches the reveal); x3 (three plinths, the tweak per egg,
--       the rays only for the best pull); the budgets at every frame (x1 450 / x3 750 instances, 24 tweens, 1 Heartbeat,
--       <= 2 effects). Review round 1: the Side a thin band (PLINTH.Band of the box) shaded darker downward; the title
--       gone once the hero shows; the crack word's gradient Shade(.78 / .22 / -.18) and 5 px outline at 80; every image key
--       wired (one ImageLabel ray fan, image sparks, one backlight image; the frames without ids); a Fast hatch pass (the
--       tell at Land - 0.25 / 0.1, the pop >= 1.14 in 0.06 and 1.09, one sweep gone by Land + 0.15, the tweak at the one
--       shake, the punch, the budgets)
--   client_roll_look_reveal  (client, 1920x1080 and 1280x720; Task 3) the reveal: the rarity word as letters (Col1 > Banner >
--       Word: a Frame with the attribute Text and L1..Ln, each with its UIGradient (Shade .78 / .22 / -.18), UIStroke (Shade
--       -.68, clamp(round(size x 0.06), 2, 6): 5 px at 84) and UIScale Pop) popping one after another 0.05 s apart (0 -> 1.3 -> 1) with its glow
--       behind; no silhouette below Legendary; the name and note sliding up 16 px and fading in from SIL + 0.2, NEW!'s pop at
--       SIL + 0.4; the glossy pills (SpinAgain / Done: Shadow, Face > Body, Shine, Label; SpinAgain's Chip > Coin + Price)
--       56 tall (44.8 real px at the 0.8 floor), disabled (grey, Label 176,184,206) until armed, rising into place by SIL +
--       0.7; the chips (Skip, FastHatch: a 44 px tap box drawing a 36 px Pill; "Tap anywhere to skip / close" + the
--       chevrons); Legendary: the pet's ViewportFrame black until SIL 0.3, then white, the letters waiting for it, the rays
--       resting at 0.55; a Skip / tap into the silhouette and a mash on SPIN AGAIN while the pills rise change nothing (no
--       BuyRoulette, the reveal completes); x3 (three letter words at 56 px, the silhouette only on the Legendary column);
--       the budgets at every frame (x1 450 / x3 750 instances; <= 32 tweens in the reveal's first 0.7 s, <= 24 after).
--       Review round 1: no Shell (x1, x3), the pet's feet (PET_FOOT) on the plinth's centre line over its contact Shadow;
--       a refused answer and the 7 s "Still waiting" shown as toasts in an Enabled gui while the stage is up; the gold flash
--       >= 0.85 clear at the silhouette's + 0.1; SPIN AGAIN disabled until its rise is in place (x3, Legendary best)
--   (client_roll_look_stage, review round 1) a gui its owner marks HudKeepOff mid-roll stays off after DONE;
--       MovementController's MobileControls carries HudKeepOff exactly while it keeps them off
--   (client_roll_look_phone, review round 1) the title gone at the rise's end at 844x390
--   client_roll_look_phone  (phone world; Task 1) 844x390 and 640x360: the x1 cards 130 x 160 with 15 px plate words, the
--       window's 3 px stroke and 10 px notches, every text >= 15 px and nothing off the screen (RedoGeom.check); the x3 lite
--       cards (no Shadow, Tint or Plate; <= 16 instances a cell); (Task 2) the phone plinth (1.1 x / 0.24 x the egg, Top
--       0.85, 2 px rim), the sparks capped at 16 (an Epic's 28), the reveal's 12 px lip (the Top and its Rim disc); (Task 3) the x1
--       landscape reveal side by side (the pet in the left 0.46, the word, name, note and the two 46 px pills in the right
--       column, the chips on the bottom row, nothing overlapping, 15 px text, one ViewportFrame) at 844x390 and 640x360;
--       portrait 360x640 (the stack, the word as 40 px letters in the 44 px band); x3 phone words as one TextLabel; a
--       rotation mid-chain (844x390 -> 390x844 at reveal + 0.15: every letter at 1, the pills in place, the text shown)
--   Review round 2: (open) the plinth's ellipses, its 16 instances, the cylinder shading; the push-in on High only; the Low
--       pass (no punch, no push-in; the tell, the land pop and its sweep, the silhouette, the letter pops stay); no sparkle
--       from the rise to the first shake; the strips above the chips' row over the rise; x3 each strip's own tell colour;
--       (stage) Uncommon keeps the gold window; the window's 13 and an x1 card's 8 instances; (reveal) a 5-letter word 30,
--       the two pills 28, the two chips 13; SPIN AGAIN's idle refreshes do nothing (no PillParts / FitPill / SetPillChip
--       calls), a low balance still shows; the PC Evolved ribbon in the name row after NEW!; (phone) the lip's Rim disc; x3
--       at 640x360 with the real font widths: NEW! and Evolved apart (bottom-left / top-right corners), the Skip chip's label
--       fitting, the notes breaking at their dots; a rotation mid-rise drops the lifted strips
--   (egg-cards, spec 16.18) (stage) HatchLook.EGG_IMAGES / EggImage / Metrics.EGG_PIC; with all seven egg_card ids
--       stubbed every shown card an ImageLabel EggPic of its rarity's id (a square, 160 / 0.9 px on PC, centred, inside
--       its card), no painted egg made, <= 20 instances; the landed card keeps its picture, the winner's goes at the rise;
--       one id (Epic): the Epic cards pictures, the others painted; no ids: no EggPic, today's painted eggs; x3 cells
--       <= 16; (phone) at 844x390 and 640x360, x1 and x3, every picture a square inside its card
-- Deterministic: mock clock only (a tween applies its goal when it completes). SoundFx.Play is spied (quiet) and put back;
-- the viewport, the Fast hatch setting and the attributes are put back. Plain Lua 5.1 syntax only.

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
-- the plinth's parts in a Pedestal box. (review round 2) Its parts are ellipses (ImageLabels of the built-in disc): the
-- rim is the "Rim" disc behind the Top and the inner ring the "Ring" disc under its Cover, read here as snapshots
-- { Color, Thickness, Transparency, Inst } (a stroke's names: the tests read colours and widths, not the drawing)
function G.plinth(j)
	local ped = G.hero("Pedestal" .. (j or 1))
	local out = { Box = ped }
	if ped then
		out.Top = ped:FindFirstChild("Top")
		out.Side = ped:FindFirstChild("Side")
		out.Ring = ped:FindFirstChild("Ring")
		out.Cover = ped:FindFirstChild("Cover")
		out.Edge = ped:FindFirstChild("Edge")
		out.Wall = ped:FindFirstChild("Wall")
		out.Pop = ped:FindFirstChild("Pop")
		local rim = ped:FindFirstChild("Rim")
		out.Rim = rim and { Color = rim.ImageColor3, Thickness = rim:GetAttribute("Thickness"), Transparency = rim.ImageTransparency, Inst = rim } or nil
		out.RingStroke = out.Ring and { Color = out.Ring.ImageColor3, Transparency = out.Ring.ImageTransparency, Inst = out.Ring } or nil
		out.Glow1 = ped:FindFirstChild("Glow1")
	end
	return out
end
-- a plinth part's opacity (0 = opaque) and colour: an ellipse's image, a frame's background
function G.clear(o)
	if not o then
		return -1
	end
	return o:IsA("ImageLabel") and o.ImageTransparency or o.BackgroundTransparency
end
function G.tint(o)
	if not o then
		return nil
	end
	return o:IsA("ImageLabel") and o.ImageColor3 or o.BackgroundColor3
end
-- (Task 3) the reveal's parts
function G.col(j)
	local content = G.content()
	local reveal = content and content:FindFirstChild("Reveal")
	return reveal and reveal:FindFirstChild("Col" .. j) or nil
end
function G.colPart(j, name)
	local col = G.col(j)
	return col and col:FindFirstChild(name, true) or nil
end
function G.bar(name)
	local content = G.content()
	local bar = content and content:FindFirstChild("BottomBar")
	return bar and bar:FindFirstChild(name) or nil
end
function G.box(o)
	local p, s = o.AbsolutePosition, o.AbsoluteSize
	return { x = p.X, y = p.Y, w = s.X, h = s.Y }
end
function G.intersects(a, b)
	local tol = 0.51
	return a.x < b.x + b.w - tol and b.x < a.x + a.w - tol and a.y < b.y + b.h - tol and b.y < a.y + a.h - tol
end
function G.letters(word)
	local out = {}
	local i = 1
	while word and word:FindFirstChild("L" .. i) do
		out[i] = word:FindFirstChild("L" .. i)
		i = i + 1
	end
	return out
end
function G.popOf(o)
	local p = o and o:FindFirstChild("Pop")
	return p and p.Scale or -1
end
function G.view(j)
	local pet = G.colPart(j, "Pet")
	return pet and pet:FindFirstChildWhichIsA("ViewportFrame", true) or nil
end
function G.viewports()
	local n = 0
	local gui = G.gui()
	for _, d in ipairs(gui and gui:GetDescendants() or {}) do
		if d:IsA("ViewportFrame") then
			n = n + 1
		end
	end
	return n
end
-- the reveal's budgets at one moment: instances, tweens (tweenCap: 32 in the reveal's first 0.7 s), Heartbeats, effects
function G.overReveal(ES, cap, tweenCap)
	local st = ES.Stats()
	local gui = G.gui()
	local tw = gui and G.tweensUnder(gui) or 0
	local bad = {}
	if (st.Instances or 0) > cap then
		bad[#bad + 1] = "instances " .. st.Instances
	end
	if tw > tweenCap or (st.Tweens or 0) > tweenCap then
		bad[#bad + 1] = fmt("tweens %d (stage %d) > %d", tw, st.Tweens or 0, tweenCap)
	end
	if (st.Heartbeats or 0) > 1 then
		bad[#bad + 1] = "heartbeats " .. tostring(st.Heartbeats)
	end
	return #bad > 0 and table.concat(bad, ", ") or nil
end
-- shows a result and steps every 1/60 s until its reveal: -> os.clock() at the reveal (nil if it never came); `each(t,
-- phase)` sees every frame
function G.toReveal(ES, result, each)
	local t0 = os.clock()
	ES.Show(result)
	while os.clock() - t0 < 10 do
		Mock.Advance(FINE, FINE)
		if each then
			each(os.clock() - t0, ES.Phase())
		end
		if ES.Phase() == "Reveal" then
			return os.clock()
		end
	end
	return nil
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
		local ownerGui = G.fakeGui("SmokeOwnerGui", true)
		fakes = { offGui, onGui, flipGui, ownerGui }
		ES.Show(G.result(PC, "Cloud", { epic }))
		G.advance(0.2)
		-- (review round 1) its owner switches it off while the stage already has it off: a same-value write the stage cannot
		-- see, so the owner says so with HudKeepOff (MovementController's MobileControls on a death mid-roll)
		T.check(ownerGui.Enabled == false, "roll look: (setup) the owner's gui hides with the HUD")
		ownerGui:SetAttribute("HudKeepOff", true)
		ownerGui.Enabled = false
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
		T.check(ownerGui.Enabled == false, "roll look: a gui its owner marked HudKeepOff mid-roll stays off after DONE (a same-value Enabled write is invisible)")
		T.eq(HL.HiddenCount(), 0, "roll look: DONE -> the hide list is empty")
		local mobile = pg:FindFirstChild("MobileControls")
		if mobile then
			T.check(mobile:GetAttribute("HudKeepOff") == (mobile.Enabled == false), "roll look: MovementController marks MobileControls HudKeepOff exactly while it keeps them off")
		end
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
		-- (review round 2) the budget bookkeeping (spec 16.15 "Budgets"): the window on the Pointer (+ its two dims beside it)
		-- and an x1 card's skin (in the cell: the Face gradient, the Shine, the Plate with its corner, stroke and Word; beside
		-- it: the Shadow with its corner)
		local trackB, stripB = G.track(1), G.strip(1)
		local dims = (stripB and stripB:FindFirstChild("DimL") and 1 or 0) + (stripB and stripB:FindFirstChild("DimR") and 1 or 0)
		T.eq(ptr and (G.count(ptr) - 1 + dims) or -1, 13, "roll look budget: the gold window is 13 instances (Bounce, Glow 3, Window 3, two notches x 2, DimL, DimR)")
		local skinN = -1
		for _, c in ipairs(cells) do
			if c.Visible and c:FindFirstChild("Plate") and skinN < 0 then
				local slot = c.Name:match("%d+")
				local sh = trackB and trackB:FindFirstChild("Shadow" .. slot)
				skinN = (c:FindFirstChild("Face") and 1 or 0) + G.count(c:FindFirstChild("Shine")) + G.count(c:FindFirstChild("Plate")) + G.count(sh)
			end
		end
		T.eq(skinN, 8, "roll look budget: an x1 card's skin is 8 instances (6 in the cell, the Shadow and its corner beside it)")
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
		-- (review round 2: Uncommon too, the pick's "Common / Uncommon stay gold")
		for _, low in ipairs({ { "Common", common }, { "Uncommon", PC.RarityPool("Cloud", "Uncommon")[1] } }) do
			t0 = os.clock()
			ES.Show(G.result(PC, "Cloud", { low[2] }))
			local stayGold, told = true, false
			while os.clock() - t0 < 3.9 do
				G.advance(STEP)
				local p = G.pointer(1)
				local st = G.stroke(p and p:FindFirstChild("Window"))
				if p and os.clock() - t0 > 0.4 and not (st and G.near(st.Color, K.GOLD)) then
					stayGold = false
				end
				if p and p:GetAttribute("Tell") then
					told = true
				end
			end
			T.check(low[2] ~= nil and stayGold and not told, "roll look tell: no tell below Rare: a " .. low[1] .. " winner keeps the gold window every frame (no fake tease)")
			ES.Close()
			G.advance(0.4)
		end
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
		------------------------------------------------------------------ (egg-cards, spec 16.18) the cards' eggs: pictures of the Blender eggs
		local namesOk = type(HL.EGG_IMAGES) == "table" and type(HL.EggImage) == "function"
		for _, r in ipairs(RARITIES) do
			namesOk = namesOk and HL.EGG_IMAGES[r] == "egg_card_" .. r:lower()
		end
		T.check(namesOk, "roll look egg cards: HatchLook.EGG_IMAGES names egg_card_<rarity> for the seven rarities (and EggImage exists)")
		if namesOk then
			local ids = {}
			for i, r in ipairs(RARITIES) do
				ids["egg_card_" .. r:lower()] = 9100 + i
			end
			HL._Textures = {}
			T.check(HL.EggImage("Epic") == nil and HL.EggImage("Nope") == nil, "roll look egg cards: EggImage is nil at id 0 (and for an unknown rarity)")
			HL._Textures = ids
			T.eq(HL.EggImage("Epic"), "rbxassetid://9104", "roll look egg cards: EggImage joins the egg_card id (TextureIds)")
			T.check(HL.Metrics and HL.Metrics.EGG_PIC and abs(HL.Metrics.EGG_PIC.Fill - 0.9) < 1e-6, "roll look egg cards: Metrics.EGG_PIC.Fill = 0.9 (the egg's share of its picture, as build_egg_cards.py frames it)")
			-- reads the shown cells of strip j: -> { pics, painted (shown painted eggs), made (painted eggs at all), bad, most, inside }
			local function cardEggs(j, want)
				local out = { pics = 0, painted = 0, made = 0, bad = "", most = 0, inside = true, sizeOk = true, landedN = 0 }
				for _, c in ipairs(G.cells(j)) do
					-- (the landed card's land dressing, its UIScale Pop and the passing shine Sweep, is the land's: 16.15
					-- counts a cell's budget on the moving strip)
					if c:GetAttribute("Index") == K.WIN and G.strip(j) and G.strip(j):GetAttribute("Landed") == true then
						out.landedN = G.count(c) - G.count(c:FindFirstChild("Pop")) - G.count(c:FindFirstChild("Sweep"))
					else
						out.most = math.max(out.most, G.count(c))
					end
					local egg, pic = nil, c:FindFirstChild("EggPic")
					for _, ch in ipairs(c:GetChildren()) do
						if ch:IsA("Frame") and ch:GetAttribute("Rarity") ~= nil and ch:GetAttribute("Form") ~= nil then
							egg = ch
						end
					end
					if egg then
						out.made = out.made + 1
					end
					local word = G.plateWord(c)
					local rarity = nil
					for _, r in ipairs(RARITIES) do
						if word and string.upper(r) == word.Text then
							rarity = r
						end
					end
					if c.Visible and rarity then
						local id = want[rarity]
						if id then
							if pic and pic:IsA("ImageLabel") and pic.Visible and pic.Image == "rbxassetid://" .. id and not (egg and egg.Visible) then
								out.pics = out.pics + 1
								local pb, cb = G.box(pic), G.box(c)
								if pb.x < cb.x - 0.6 or pb.y < cb.y - 0.6 or pb.x + pb.w > cb.x + cb.w + 0.6 or pb.y + pb.h > cb.y + cb.h + 0.6 then
									out.inside = false
								end
								if abs(pb.w - pb.h) > 0.6 then
									out.sizeOk = false
								end
							else
								out.bad = out.bad .. fmt("%s: pic %s; ", rarity, pic and fmt("%s %s", tostring(pic.Visible), tostring(pic.Image)) or "none")
							end
						else
							if egg and egg.Visible and egg:GetAttribute("Rarity") == rarity and not (pic and pic.Visible) then
								out.painted = out.painted + 1
							else
								out.bad = out.bad .. fmt("%s: painted %s; ", rarity, tostring(egg and egg.Visible))
							end
						end
					end
				end
				return out
			end
			-- all seven ids: every shown card draws its rarity's picture; no painted egg is made at all
			t0 = os.clock()
			ES.Show(G.result(PC, "Cloud", { epic }))
			G.until_(t0, 2.0)
			local all = cardEggs(1, { Common = 9101, Uncommon = 9102, Rare = 9103, Epic = 9104, Legendary = 9105, Mythic = 9106, Secret = 9107 })
			T.check(all.pics >= 5 and all.bad == "" and all.painted == 0, "roll look egg cards: with every id each shown card shows an ImageLabel EggPic of its rarity's id", fmt("%d pictures; %s", all.pics, all.bad))
			T.check(all.made == 0, "roll look egg cards: ...and no painted egg is made (all seven have pictures)", tostring(all.made))
			T.check(all.inside and all.sizeOk, "roll look egg cards: ...each picture a square inside its card")
			T.check(all.most <= 20, "roll look egg cards: an x1 cell with its picture is <= 20 instances", tostring(all.most))
			-- the picture's egg is the painted egg's height: the square is egg px / Fill, centred on the egg's box
			local g = nil
			for _, c in ipairs(G.cells(1)) do
				local pic = c:FindFirstChild("EggPic")
				if c.Visible and pic and pic.Visible and not g then
					g = { pic = G.box(pic), cell = G.box(c) }
				end
			end
			local s = g and g.cell.w / 230 or 1
			T.check(g ~= nil and abs(g.pic.h - 160 * s / 0.9) <= 1 and abs((g.pic.x + g.pic.w / 2) - (g.cell.x + g.cell.w / 2)) <= 1,
				"roll look egg cards: the PC picture is 160 / 0.9 px (the painted egg's 160 px egg), centred across its card", g and fmt("%.1f px (S %.2f)", g.pic.h, s) or "no picture")
			-- the landed card keeps its picture; at the rise the winner's picture lifts out with it
			local stripP = G.strip(1)
			Mock.AdvanceUntil(function()
				return stripP ~= nil and stripP:GetAttribute("Landed") == true
			end, 4, FINE)
			G.advance(0.1)
			local lc = G.cellAt(1, K.WIN)
			local lpic = lc and lc:FindFirstChild("EggPic")
			T.check(lpic ~= nil and lpic.Visible and lpic.Image == "rbxassetid://9104", "roll look egg cards: the landed Epic card shows the Epic picture", lpic and tostring(lpic.Image) or "none")
			G.untilPhase(ES, "Rise", 3)
			G.advance(STEP * 2)
			lc = G.cellAt(1, K.WIN)
			lpic = lc and lc:FindFirstChild("EggPic")
			T.check(lc == nil or lpic == nil or not lpic.Visible, "roll look egg cards: at the rise the winner's picture lifts out of its card (no second egg left behind)")
			ES.Close()
			G.advance(0.4)
			-- one id (Epic): the Epic cards draw the picture, every other card its painted egg
			HL._Textures = { egg_card_epic = 77 }
			ES.Show(G.result(PC, "Cloud", { epic }))
			Mock.AdvanceUntil(function()
				return G.strip(1) ~= nil and G.strip(1):GetAttribute("Landed") == true
			end, 4, FINE)
			G.advance(0.1)
			local one = cardEggs(1, { Epic = 77 })
			T.check(one.pics >= 1 and one.painted >= 2 and one.bad == "", "roll look egg cards: with only egg_card_epic's id the Epic cards show its picture, the others their painted eggs",
				fmt("%d pictures, %d painted; %s", one.pics, one.painted, one.bad))
			T.check(one.most <= 20 and one.landedN <= 20, "roll look egg cards: ...a cell with both (the painted egg and its picture) is <= 20 instances (the landed card's Pop and Sweep aside)",
				fmt("%d, landed %d", one.most, one.landedN))
			ES.Close()
			G.advance(0.4)
			-- no ids (today): no EggPic anywhere, the painted eggs exactly as 16.15
			HL._Textures = {}
			t0 = os.clock()
			ES.Show(G.result(PC, "Cloud", { epic }))
			G.until_(t0, 2.0)
			local none = cardEggs(1, {})
			local anyPic = false
			for _, c in ipairs(G.cells(1)) do
				anyPic = anyPic or c:FindFirstChild("EggPic") ~= nil
			end
			T.check(not anyPic and none.painted >= 5 and none.bad == "", "roll look egg cards: at id 0 no EggPic is made and every card draws its painted egg (today's look)", fmt("%d painted; %s", none.painted, none.bad))
			ES.Close()
			G.advance(0.4)
			-- x3 with every id: lite cells with their pictures stay <= 16 instances
			HL._Textures = ids
			t0 = os.clock()
			ES.Show(G.result(PC, "Storm", { PC.RarityPool("Storm", "Rare")[1] or rare, PC.RarityPool("Storm", "Legendary")[1] or epic, PC.RarityPool("Storm", "Common")[1] or epic }))
			G.until_(t0, 2.0)
			local most3, pics3 = 0, 0
			for j = 1, 3 do
				for _, c in ipairs(G.cells(j)) do
					most3 = math.max(most3, G.count(c))
					local pic = c:FindFirstChild("EggPic")
					if c.Visible and pic and pic.Visible then
						pics3 = pics3 + 1
					end
				end
			end
			T.check(pics3 >= 6 and most3 <= 16, "roll look egg cards: x3 cells show their pictures and stay <= 16 instances", fmt("%d pictures, %d at most", pics3, most3))
			ES.Close()
			G.advance(0.4)
			HL._Textures = false
		end
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
				rec.first = { pop = p.Pop and p.Pop.Scale or -1, top = G.clear(p.Top), ph = ph }
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
					kids = table.concat(kids, " "), pop = p.Pop and p.Pop.Scale or -1, top = G.clear(p.Top),
					topH = (p.Top and box) and p.Top.AbsoluteSize.Y / box.AbsoluteSize.Y or -1,
					-- (review round 2) the disc's aspect (the mock's platA: rx 150 / ry 30 = 5 : 1), its instances, and every
					-- part a true ellipse: an ImageLabel of the built-in disc stretched to its box, no UICorner capsule (the
					-- capsule plinth with a capsule ring read as a loading bar); the Wall the one frame (the band's straight ends)
					aspect = (p.Top and p.Top.AbsoluteSize.Y > 0) and p.Top.AbsoluteSize.X / p.Top.AbsoluteSize.Y or -1,
					parts = box and (G.count(box) - 1) or -1,
					ellipses = (function()
						local bad = {}
						for _, nm in ipairs({ "Top", "Rim", "Side", "Edge", "Ring", "Cover", "Glow1", "Glow2" }) do
							local o = box and box:FindFirstChild(nm)
							if not (o and o:IsA("ImageLabel") and o.Image == HL.Metrics.DISC and o.ScaleType == Enum.ScaleType.Stretch and o:FindFirstChildOfClass("UICorner") == nil and o.BackgroundTransparency >= 0.999) then
								bad[#bad + 1] = nm .. (o and (" " .. o.ClassName) or " missing")
							end
						end
						local wall = box and box:FindFirstChild("Wall")
						if not (wall and wall:IsA("Frame") and wall:FindFirstChildOfClass("UICorner") == nil) then
							bad[#bad + 1] = "Wall"
						end
						return table.concat(bad, ", ")
					end)(),
					-- the Rim disc its Thickness larger than the Top every way, the Cover its ring width smaller than the Ring
					rimPx = (p.Top and p.Rim) and (p.Rim.Inst.AbsoluteSize.X - p.Top.AbsoluteSize.X) / 2 or -1,
					coverPx = (p.Ring and p.Cover) and (p.Ring.AbsoluteSize.X - p.Cover.AbsoluteSize.X) / 2 or -1,
					wallH = (p.Wall and box) and p.Wall.AbsoluteSize.Y / box.AbsoluteSize.Y or -1,
					-- the outline one width all round: the Wall and the Edge reach as far past the box as the Rim
					wallPx = (p.Wall and box) and (p.Wall.AbsoluteSize.X - box.AbsoluteSize.X) / 2 or -1,
					edgePx = (p.Edge and p.Side) and (p.Edge.AbsoluteSize.X - p.Side.AbsoluteSize.X) / 2 or -1,
					topMid = (p.Top and box) and (p.Top.AbsolutePosition.Y + p.Top.AbsoluteSize.Y / 2) - box.AbsolutePosition.Y or 99,
					-- (review round 1) the Side's band under the Top, a share of the box (thickness, not a second bar)
					sideBand = (p.Side and p.Top and box) and ((p.Side.AbsolutePosition.Y + p.Side.AbsoluteSize.Y) - (p.Top.AbsolutePosition.Y + p.Top.AbsoluteSize.Y)) / box.AbsoluteSize.Y or 99,
					sideW = (p.Side and p.Top) and (p.Side.AbsoluteSize.X - p.Top.AbsoluteSize.X) or 99,
					sideGrad = p.Side and p.Side:FindFirstChildOfClass("UIGradient"),
					boxW = box and box.AbsoluteSize.X or -1, boxH = box and box.AbsoluteSize.Y or -1, eh = eh,
					foot = (egg and box) and (box.AbsolutePosition.Y - (egg.AbsolutePosition.Y + egg.AbsoluteSize.Y)) or 99,
					rim = p.Rim and p.Rim.Color, rimT = p.Rim and p.Rim.Thickness, rays = rays ~= nil and rays.Visible,
				}
			end
			if t >= shake1 + 0.3 and not rec.tweak then
				local ring = G.hero("CloudRing1")
				local rays = G.hero("Rays")
				local title = G.content() and G.content():FindFirstChild("Title")
				local cw = G.hero("CrackWord")
				rec.tweak = {
					rim = p.Rim and p.Rim.Color, ring = p.RingStroke and p.RingStroke.Color, edge = p.Edge and p.Edge.ImageColor3, glow = G.tint(p.Glow1), cloud = ring and ring.GroupColor3,
					rays = rays ~= nil and rays.Visible, raysA = rays and rays.GroupTransparency or 1, spin = rays ~= nil and G.spinning(rays),
					-- (review round 1) the title gone once the hero shows (the mock fades it at the rise); the crack word dressed
					titleGone = title == nil or not G.shown(title) or title.TextTransparency >= 0.99,
					cw = cw, cwGrad = cw and cw:FindFirstChildOfClass("UIGradient"), cwStroke = cw and cw:FindFirstChildOfClass("UIStroke"),
				}
			end
			-- (review round 1) the punch scales the stage's world (Hero, Burst), never the chrome (the title, the chips)
			local skipChip = G.bar("Skip")
			if skipChip and not rec.burstT then
				rec.skipBox = G.box(skipChip)
			end
			-- (review round 2) the clutter cap: sparkles only at the burst and the shakes' small pops (no drifting sparks round
			-- the hero egg from the rise to the first shake)
			if t >= landEnd and t < shake1 - 0.02 then
				rec.sparksEarly = math.max(rec.sparksEarly or 0, ES.Stats().Sparks or 0)
			end
			-- (review round 2) the push-in over the shakes (High): the hero egg's UIScale Pop towards K.PUSH
			local eggP = G.hero("Egg1") and G.hero("Egg1"):FindFirstChild("Pop")
			if eggP and ph == "Crack" then
				rec.pushMax = math.max(rec.pushMax or 0, eggP.Scale)
			end
			-- (review round 2) the strips leave over the rise without crossing the bottom bar's chips (the mock's strip
			-- slides 220 px and fades by the rise's end): the part of Strip1 that shows never reaches the chips' row
			local stripsF = G.content() and G.content():FindFirstChild("Strips")
			local track1 = G.track(1)
			local chip = G.bar("Skip")
			if ph == "Rise" and stripsF and stripsF.Visible and track1 and chip and not rec.stripLow then
				local bottom = track1.AbsolutePosition.Y + track1.AbsoluteSize.Y
				if stripsF.ClipsDescendants then
					bottom = math.min(bottom, stripsF.AbsolutePosition.Y + stripsF.AbsoluteSize.Y)
				end
				if bottom > chip.AbsolutePosition.Y + 0.6 then
					rec.stripLow = fmt("%.2f s: the strip shows down to %.0f, the chips start at %.0f", t, bottom, chip.AbsolutePosition.Y)
				end
			end
			if t >= riseEnd + 0.05 and t < shake1 - 0.02 and not rec.early then
				local rays = G.hero("Rays")
				if rays and rays.Visible then
					rec.early = "the rays show before the first shake"
				elseif not (p.Rim and G.near(p.Rim.Color, HL.Shade(NEUTRAL, 0.25))) then
					rec.early = "the rim is tinted before the first shake: " .. G.c3(p.Rim and p.Rim.Color)
				end
			end
			local heroF = G.content() and G.content():FindFirstChild("Hero")
			local punch = heroF and heroF:FindFirstChild("Punch")
			local bpunch = G.burstFrame() and G.burstFrame():FindFirstChildOfClass("UIScale")
			local egg = G.hero("Egg1")
			if egg and egg:GetAttribute("State") == "Burst" and not rec.burstT then
				rec.burstT = t
				rec.sparks = G.burstFrame() and G.burstFrame():GetAttribute("Sparks")
				local holder = G.hero("Halves1")
				rec.halves2D = holder ~= nil and holder:GetAttribute("Split3D") == false and holder:FindFirstChild("HalfTop") ~= nil and holder:FindFirstChild("HalfBottom") ~= nil
			end
			if rec.burstT and t <= rec.burstT + 0.1 and punch then
				rec.punchEarly = math.max(rec.punchEarly, punch.Scale)
				rec.burstFollow = rec.burstFollow ~= false and bpunch ~= nil and abs(bpunch.Scale - punch.Scale) <= 1e-6
				if punch.Scale >= 1.04 and skipChip and rec.skipBox then
					local b = G.box(skipChip)
					rec.chromeMoved = math.max(rec.chromeMoved or 0, abs(b.x - rec.skipBox.x), abs(b.y - rec.skipBox.y), abs(b.w - rec.skipBox.w), abs(b.h - rec.skipBox.h))
				end
			end
		end
		T.check(rec.first ~= nil and rec.first.pop >= 0.6 - 0.005 and rec.first.pop <= 0.72 and rec.first.top >= 0.85,
			"roll look open: the rise's first frame: the plinth box's UIScale Pop starts near 0.6, its Top nearly clear", rec.first and fmt("%s: pop %.3f, top %.2f", rec.first.ph, rec.first.pop, rec.first.top) or "no Pedestal1")
		T.check(rec.maxPop > 1.01, "roll look open: the plinth springs past 1 over the rise (Back Out)", fmt("%.3f", rec.maxPop))
		local r = rec.rest
		if T.check(r ~= nil, "roll look open: (setup) sampled at the rise's end") then
			T.eq(r.kids, "Cover Edge Glow1 Glow2 Rim Ring Side Top Wall", "roll look open: Pedestal1 is the flat lit plinth: Top + Rim, Side + Wall + Edge, the inner Ring + Cover, the soft halo Glow1..2 (no drum, no puffs, no bars)")
			T.check(r.ellipses == "", "roll look open: (review round 2) every plinth part is a true ellipse: an ImageLabel of HatchLook.Metrics.DISC stretched to its box, no capsule (the Wall the one frame)", r.ellipses)
			local PL = HL.Metrics.PLINTH
			T.check(abs(r.rimPx - PL.Rim) <= 0.6 and abs(r.wallPx) <= 0.6 and abs(r.edgePx - PL.Edge) <= 0.6 and abs(r.coverPx - PL.Ring) <= 0.6 and abs(r.wallH - PL.Band) <= 0.01,
				"roll look open: the Rim disc 3 px past the Top, the Wall the box's width and the band's height, the Edge 2 px past the Side, the Ring showing 2 px round its Cover",
				fmt("rim %.1f, wall %+.1f, edge %.1f, ring %.1f, wall h %.3f", r.rimPx, r.wallPx, r.edgePx, r.coverPx, r.wallH))
			T.check(abs(r.pop - 1) <= 0.01 and r.top <= 0.01, "roll look open: at the rise's end the plinth rests: Pop 1, Top opaque", fmt("pop %.3f, top %.3f", r.pop, r.top))
			local sk = r.sideGrad and r.sideGrad.Color.Keypoints or {}
			local lum = function(c)
				return c and (c.R + c.G + c.B) or 0
			end
			local band = HL.Metrics.PLINTH.Band or -1
			T.check(abs(r.topH - 0.85) <= 0.01 and abs(r.sideBand - band) <= 0.01 and band > 0 and band <= 0.15 and abs(r.topH + band - 1) <= 0.01 and abs(r.sideW) <= 0.6,
				"roll look open: the Top is 0.85 of the box tall; the Side is its thickness: the same width, a thin band (<= 0.15 of the box) under it, the two inside the box", fmt("top %.3f, band %.3f, width %+.1f px", r.topH, r.sideBand, r.sideW))
			T.check(r.aspect >= 5 and r.aspect <= 5.6, "roll look open: (review round 2) the disc is about 5 : 1 like the mock's platA (rx 150 / ry 30), not a 7 : 1 bar", fmt("%.2f : 1", r.aspect))
			T.eq(r.parts, 16, "roll look open: the plinth is 16 instances (spec 16.15 Budgets: Pop, two halo discs x 2, Edge, Side 2, Wall 2, Rim, Top 2, Ring, Cover 2)")
			-- (review round 2) the band shows under the Top's front edge (from 1 - Band / Top of the Side's height down): lit
			-- there, darker downward; its middle line (where the ellipse's ends meet the Wall) dark like a cylinder's ends
			local litAt = 1 - band / (HL.Metrics.PLINTH.Top or 1)
			local function at(v)
				local c = sk[1] and sk[1].Value
				for i = 1, #sk - 1 do
					if v >= sk[i].Time and v <= sk[i + 1].Time then
						local k = (sk[i + 1].Time - sk[i].Time) > 0 and (v - sk[i].Time) / (sk[i + 1].Time - sk[i].Time) or 0
						c = sk[i].Value:Lerp(sk[i + 1].Value, k)
					end
				end
				return c
			end
			T.check(r.sideGrad ~= nil and r.sideGrad.Rotation == 90 and #sk >= 2 and lum(at(1)) < lum(at(litAt)) - 0.05 and lum(at(0.5)) < lum(at(litAt)) - 0.05,
				"roll look open: ...shaded darker downward (a vertical UIGradient: lit at the Top's front edge, dark at the bottom and at the ends' middle line)",
				r.sideGrad and fmt("rot %s, mid %s, edge %s, bottom %s", tostring(r.sideGrad.Rotation), G.c3(at(0.5)), G.c3(at(litAt)), G.c3(at(1))) or "no gradient")
			T.check(abs(r.topMid) <= 1.5, "roll look open: the Top's centre line sits on the egg's foot (the box's top): the egg stands in the middle of the disc", fmt("%+.1f px", r.topMid))
			T.check(abs(r.boxW - 1.1 * r.eh) <= 1.5 and abs(r.boxH - 0.24 * r.eh) <= 1.5 and abs(r.foot) <= 0.6, "roll look open: the box is still 1.1 x / 0.24 x the egg, right under it",
				fmt("egg %.1f, box %.1f x %.1f, gap %.1f", r.eh, r.boxW, r.boxH, r.foot))
			T.check(G.near(r.rim, HL.Shade(NEUTRAL, 0.25)) and r.rimT == 3 and r.rays == false, "roll look open: before the shakes the plinth is neutral (its 3 px rim Shade(neutral, .25)) and no rays show",
				fmt("%s, %s px, rays %s", G.c3(r.rim), tostring(r.rimT), tostring(r.rays)))
		end
		T.check(rec.early == nil, "roll look open: nothing of the tweak before the first shake", tostring(rec.early))
		T.eq(rec.sparksEarly, 0, "roll look open: (review round 2) the clutter cap: no sparkle from the rise to the first shake (sparkles only at the burst and the shakes' pops)")
		T.check((rec.pushMax or 0) >= K.PUSH - 0.01, "roll look open: High: the push-in grows the hero egg to K.PUSH over the shakes", fmt("%.3f", rec.pushMax or -1))
		T.check(rec.stripLow == nil, "roll look open: (review round 2) the strips leave over the rise without crossing the chips' row", tostring(rec.stripLow))
		local w = rec.tweak
		if T.check(w ~= nil, "roll look open: (setup) sampled 0.3 s into the first shake") then
			T.check(G.near(w.rim, HL.Shade(epicC, 0.25)) and G.near(w.ring, HL.Shade(epicC, 0.4)) and G.near(w.edge, HL.Shade(epicC, 0.2)) and G.near(w.glow, HL.Shade(epicC, 0.2)),
				"roll look open: Gemini's tweak (Epic): the plinth's rim, inner ring, lit lower rim and glow turn the rarity colour at the first shake", fmt("%s / %s / %s / %s", G.c3(w.rim), G.c3(w.ring), G.c3(w.edge), G.c3(w.glow)))
			T.check(G.near(w.cloud, RING_TINT:Lerp(epicC, 0.5), 2), "roll look open: ...the cloud ring's GroupColor3 too (RING_TINT half way to Epic)", G.c3(w.cloud))
			T.check(w.rays and w.raysA <= 0.76 and w.spin, "roll look open: ...and the rays come up faint (GroupTransparency 0.75) and turn", fmt("visible %s, %.2f, spin %s", tostring(w.rays), w.raysA, tostring(w.spin)))
			T.check(w.titleGone, "roll look open: the machine's title is gone once the hero egg shows (the mock fades it at the rise: no two headlines)")
			local ck = w.cwGrad and w.cwGrad.Color.Keypoints or {}
			T.check(w.cw ~= nil and w.cw.Text == "EPIC EGG!" and w.cw.TextSize == 80 and #ck == 3 and G.near(ck[1].Value, rgb(238, 223, 250)) and G.near(ck[2].Value, rgb(193, 140, 237)) and G.near(ck[3].Value, rgb(144, 89, 190)),
				"roll look open: the crack word is one 80 px label with the word's gradient Shade(Epic, .78 / .22 / -.18) (spec 16.15 Sizes)", w.cw and fmt("%s %d, %s / %s / %s", w.cw.Text, w.cw.TextSize, G.c3(ck[1] and ck[1].Value), G.c3(ck[2] and ck[2].Value), G.c3(ck[3] and ck[3].Value)) or "no CrackWord")
			T.check(w.cwStroke ~= nil and G.near(w.cwStroke.Color, rgb(56, 35, 74)) and w.cwStroke.Thickness == 5 and w.cw and G.near(w.cw.TextColor3, Color3.new(1, 1, 1)),
				"roll look open: ...and its outline Shade(Epic, -.68), 5 px at 80 (white text under the gradient)", w.cwStroke and fmt("%s %s px", G.c3(w.cwStroke.Color), tostring(w.cwStroke.Thickness)) or "no stroke")
		end
		T.check(rec.over == nil, "roll look open: x1 within the budgets at every frame of Rise / Crack / Burst (450 instances, 24 tweens, 1 Heartbeat, <= 2 effects)", tostring(rec.over))
		local stage = G.stage()
		local heroF = G.content() and G.content():FindFirstChild("Hero")
		local punch = heroF and heroF:FindFirstChild("Punch")
		T.check(stage and stage:FindFirstChildOfClass("UIScale") == nil and punch and punch:IsA("UIScale") and heroF.AnchorPoint == Vector2.new(0.5, 0.5),
			"roll look open: the punch's UIScale sits on Hero (anchored at its centre), not on Stage")
		T.check(rec.punchEarly >= 1.04 and rec.burstFollow == true, "roll look open: the burst's punch reaches >= 1.04 within 0.1 s, Burst's UIScale following Hero's", fmt("%.3f, follow %s", rec.punchEarly, tostring(rec.burstFollow)))
		T.check(rec.chromeMoved ~= nil and rec.chromeMoved <= 0.5, "roll look open: ...while the Skip chip keeps its box (the chrome is not punched: nothing clipped at the screen's edges)", tostring(rec.chromeMoved))
		T.check(punch and abs(punch.Scale - 1) <= 0.005, "roll look open: ...and is back to 1 on the reveal", punch and tostring(punch.Scale) or "nil")
		T.check(rec.halves2D == true, "roll look open: without the halves' ids the 2D HalfTop / HalfBottom open (16.14 stands)")
		T.eq(rec.sparks, 28, "roll look open: 28 sparks for an Epic on PC")
		T.eq(ES.Phase(), "Reveal", "roll look open: (setup) the reveal")
		local pr = G.plinth(1)
		T.check(pr.Top and G.shown(pr.Top) and G.clear(pr.Top) <= 0.01 and G.near(pr.Rim and pr.Rim.Color, HL.Shade(epicC, 0.25)),
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
		------------------------------------------------------------------ Low graphics (spec 16.15 "Fallbacks"): no punch, no push-in;
		-- (review round 2) the tell, the land pop, the shine, the letter pops and the silhouette stay (a Legendary x1)
		mode = "Low"
		local legL = PC.RarityPool("Storm", "Legendary")[1]
		local legLC = G.rarityOf(Config, "Legendary")
		local stopL = Tm.Intro + Tm.Strip -- the strip stops (the Land phase starts)
		local low = { punch = 0, push = 0, popUp = 0, sweeps = 0, had = false, letter = 0 }
		t0 = os.clock()
		ES.Show(G.result(PC, "Storm", { legL }))
		while os.clock() - t0 < Tm.RevealAt + 0.3 + 1.0 do
			Mock.Advance(FINE, FINE)
			local t = os.clock() - t0
			local ph = ES.Phase()
			local hf = G.content() and G.content():FindFirstChild("Hero")
			local pu = hf and hf:FindFirstChild("Punch")
			if pu then
				low.punch = math.max(low.punch, pu.Scale)
			end
			local eggP = G.hero("Egg1") and G.hero("Egg1"):FindFirstChild("Pop")
			if eggP and ph == "Crack" then
				low.push = math.max(low.push, eggP.Scale)
			end
			if t >= stopL - 0.4 and not low.tell then
				local ptr = G.pointer(1)
				local ws = G.stroke(ptr and ptr:FindFirstChild("Window"))
				low.tell = { told = ptr ~= nil and ptr:GetAttribute("Tell") == true, color = ws and ws.Color }
			end
			local strip = G.strip(1)
			if strip and strip:GetAttribute("Landed") == true and not low.landT then
				low.landT = t
			end
			local landed = low.landT and G.cellAt(1, K.WIN)
			if landed then
				local pop = landed:FindFirstChild("Pop")
				if pop and t - low.landT <= 0.125 then
					low.popUp = math.max(low.popUp, pop.Scale)
				end
				local has = landed:FindFirstChild("Sweep") ~= nil
				if has and not low.had then
					low.sweeps = low.sweeps + 1
				end
				low.had = has
			end
			if ph == "Reveal" and not low.revT then
				low.revT = t
			end
			if low.revT and t >= low.revT + 0.1 and not low.sil then
				local v = G.view(1)
				low.sil = v and v.ImageColor3 or Color3.new(1, 1, 1)
			end
			for _, l in ipairs(low.revT and G.letters(G.colPart(1, "Word")) or {}) do
				low.letter = math.max(low.letter, G.popOf(l))
			end
		end
		T.check(low.punch <= 1.0001, "roll look open: Low graphics: no punch (Hero's Punch stays 1)", fmt("%.3f", low.punch))
		T.check(low.push > 0 and low.push <= 1.0001, "roll look open: Low graphics: no push-in (the hero egg's Pop stays 1 through the Crack; CARDS.md A: 'push-in off on Low')", fmt("%.3f", low.push))
		T.check(low.tell and low.tell.told and G.near(low.tell.color, legLC, 2), "roll look open: Low graphics: the colour tell stays (Legendary: Tell, its colour at Land - 0.4)",
			low.tell and fmt("%s %s", tostring(low.tell.told), G.c3(low.tell.color)) or "not sampled")
		T.check(low.popUp >= 1.14 and low.sweeps == 1, "roll look open: Low graphics: the land pop (>= 1.14) and its one shine sweep stay", fmt("%.3f, %d sweeps", low.popUp, low.sweeps))
		T.check(low.sil ~= nil and G.near(low.sil, Color3.new(0, 0, 0), 3), "roll look open: Low graphics: the Legendary silhouette stays (black at reveal + 0.1)", G.c3(low.sil))
		T.check(low.letter >= 1.25, "roll look open: Low graphics: the letters still pop (past 1.25)", fmt("%.2f", low.letter))
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
		-- (review round 1) every key is wired: the ray fan, the sparkle and the backlight take the image when it has an id
		local function imagesAt(at)
			local hero = G.content() and G.content():FindFirstChild("Hero")
			local rays = hero and hero:FindFirstChild("Rays")
			local out = { rayImg = nil, rayBars = 0, sparkImg = 0, sparkFrame = 0, backImg = nil, backDiscs = 0 }
			for _, c in ipairs(rays and rays:GetChildren() or {}) do
				if c:IsA("ImageLabel") then
					out.rayImg = c
				elseif c:IsA("Frame") and c.Name:match("^Ray%d+$") then
					out.rayBars = out.rayBars + 1
				end
			end
			local holder = G.burstFrame() and G.burstFrame():FindFirstChild("Sparks")
			for _, s in ipairs(holder and holder:GetChildren() or {}) do
				if s.Visible and s.Name == "Spark" then
					if s:IsA("ImageLabel") then
						out.sparkImg = out.sparkImg + 1
						out.sparkId = s.Image
					else
						out.sparkFrame = out.sparkFrame + 1
					end
				end
			end
			local back = G.hero("Backlight1")
			for _, c in ipairs(back and back:GetChildren() or {}) do
				if c:IsA("ImageLabel") then
					out.backImg = c
				elseif c:IsA("Frame") then
					out.backDiscs = out.backDiscs + 1
				end
			end
			return out
		end
		HL._Textures = { hatch_rays = 11, hatch_sparkle = 12, hatch_glow = 13 }
		t0 = os.clock()
		ES.Show(G.result(PC, "Cloud", { epic }))
		G.until_(t0, burstAt + 0.05)
		local im = imagesAt()
		T.check(im.rayImg ~= nil and im.rayImg.Image == "rbxassetid://11" and im.rayBars == 0, "roll look open: with a hatch_rays id the rays are one ImageLabel fan (no wedges)",
			im.rayImg and tostring(im.rayImg.Image) or fmt("no image, %d wedges", im.rayBars))
		T.check(im.sparkImg >= 10 and im.sparkFrame == 0 and im.sparkId == "rbxassetid://12", "roll look open: with a hatch_sparkle id the burst's sparks are ImageLabels", fmt("%d images (%s), %d squares", im.sparkImg, tostring(im.sparkId), im.sparkFrame))
		T.check(im.backImg ~= nil and im.backImg.Image == "rbxassetid://13" and im.backDiscs == 0, "roll look open: with a hatch_glow id the backlight is one ImageLabel glow", im.backImg and tostring(im.backImg.Image) or fmt("%d discs", im.backDiscs))
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
		G.until_(t0, burstAt + 0.05)
		im = imagesAt()
		T.check(im.rayImg == nil and im.rayBars == 8 and im.sparkImg == 0 and im.sparkFrame >= 10 and im.backImg == nil and im.backDiscs == 4,
			"roll look open: without ids the frame fallbacks: 8 ray bars, square sparks, 4 backlight discs", fmt("rays %s/%d, sparks %d/%d, back %s/%d", tostring(im.rayImg ~= nil), im.rayBars, im.sparkImg, im.sparkFrame, tostring(im.backImg ~= nil), im.backDiscs))
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
		T.check(pz.Rim and G.near(pz.Rim.Color, HL.Shade(epicC, 0.25)) and pz.Pop and abs(pz.Pop.Scale - 1) <= 0.01 and pz.Top and G.clear(pz.Top) <= 0.01,
			"roll look open: a resize mid-tweak snaps the plinth (rarity rim, Pop 1, opaque)", fmt("%s, pop %s", G.c3(pz.Rim and pz.Rim.Color), tostring(pz.Pop and pz.Pop.Scale)))
		T.check(ring and G.near(ring.GroupColor3, RING_TINT:Lerp(epicC, 0.5), 2) and rays and rays.Visible and rays.GroupTransparency <= 0.76 and G.spinning(rays),
			"roll look open: ...the cloud ring keeps the tint and the rays stay faint and turning", fmt("%s, rays %s %.2f", G.c3(ring and ring.GroupColor3), tostring(rays and rays.Visible), rays and rays.GroupTransparency or -1))
		T.check(G.untilPhase(ES, "Reveal", 4) ~= nil, "roll look open: ...and the roll reaches the reveal")
		ES.Close()
		Mock.SetViewport(1920, 1080)
		G.advance(0.6)
		------------------------------------------------------------------ (review round 1) Fast hatch: every new beat's Fast branch
		env.CS.Set("FastHatch", true)
		local TF = ES.Timings(true, 1)
		local fLand = TF.Intro + TF.Strip -- the strip stops (the Land phase starts)
		local fRise = fLand + TF.Land + TF.Rise
		local fShake = fRise + K.SHAKE_FAST[1][1] * TF.Crack
		local fBurst = fRise + TF.Crack
		local fr = { notGold = nil, popUp = 0, sweeps = 0, had = false, late = false, earlyTint = nil, punchUp = 0 }
		t0 = os.clock()
		ES.Show(G.result(PC, "Cloud", { epic }))
		while os.clock() - t0 < TF.RevealAt + 0.2 and ES.Phase() ~= "Reveal" do
			Mock.Advance(FINE, FINE)
			local t = os.clock() - t0
			local ph = ES.Phase()
			if (ph == "Rise" or ph == "Crack" or ph == "Burst") and not fr.over then
				local o = G.over(ES, 450)
				if o then
					fr.over = fmt("%s at %.2f s: %s", ph, t, o)
				end
			end
			local ws = G.stroke(G.pointer(1) and G.pointer(1):FindFirstChild("Window"))
			if t > TF.Intro + 0.05 and t < fLand - 0.25 - 0.02 and ws and not G.near(ws.Color, K.GOLD) and not fr.notGold then
				fr.notGold = fmt("%.2f s: %s", t, G.c3(ws.Color))
			end
			-- (by Land - 0.15; + 0.02: the mock's 1/60 s frames)
			if t >= fLand - 0.15 + 0.02 and not fr.tell then
				fr.tell = ws and ws.Color
			end
			local strip = G.strip(1)
			if strip and strip:GetAttribute("Landed") == true and not fr.landT then
				fr.landT = t
			end
			local landed = fr.landT and G.cellAt(1, K.WIN)
			if landed then
				local pop = landed:FindFirstChild("Pop")
				-- (+ one 1/60 s frame and + 0.03 s: the mock applies a tween's goal on the frame it completes)
				if pop and t - fr.landT <= 0.06 + FINE + 1e-6 then
					fr.popUp = math.max(fr.popUp, pop.Scale)
				end
				if pop and t >= fLand + TF.Land + 0.03 and not fr.popRest and t < fRise then
					fr.popRest = pop.Scale
				end
				local has = landed:FindFirstChild("Sweep") ~= nil
				if has and not fr.had then
					fr.sweeps = fr.sweeps + 1
				end
				if has and t - fr.landT > 0.15 then
					fr.late = true
				end
				fr.had = has
			end
			local p = G.plinth(1)
			if t > fRise + 0.02 and t < fShake - 0.02 and p.Rim and not G.near(p.Rim.Color, HL.Shade(NEUTRAL, 0.25)) and not fr.earlyTint then
				fr.earlyTint = fmt("%.2f s: %s", t, G.c3(p.Rim.Color))
			end
			if t >= fShake + K.LOOK.TWEAK.Fast + 0.03 and t < fBurst and not fr.tint then
				fr.tint = p.Rim and p.Rim.Color
			end
			local hf = G.content() and G.content():FindFirstChild("Hero")
			local pu = hf and hf:FindFirstChild("Punch")
			if pu and t >= fBurst and t <= fBurst + 0.1 then
				fr.punchUp = math.max(fr.punchUp, pu.Scale)
			end
		end
		T.eq(ES.Phase(), "Reveal", "roll look fast: (setup) the Fast hatch roll reaches its reveal")
		T.check(fr.notGold == nil and fr.tell ~= nil and G.near(fr.tell, epicC, 2), "roll look fast: the window is gold until Land - 0.25 and the Epic colour by Land - 0.15 (tell 0.25 / 0.1 s)",
			fmt("%s; %s", tostring(fr.notGold), G.c3(fr.tell)))
		T.check(fr.popUp >= 1.14 and fr.popRest ~= nil and abs(fr.popRest - 1.09) <= 0.01, "roll look fast: the land pop reaches >= 1.14 within 0.06 s and rests at 1.09 by Land's end",
			fmt("%.3f, rest %s", fr.popUp, tostring(fr.popRest)))
		T.check(fr.sweeps == 1 and not fr.late, "roll look fast: one shine Sweep, gone by Land + 0.15", fmt("%d, late %s", fr.sweeps, tostring(fr.late)))
		T.check(fr.earlyTint == nil and fr.tint ~= nil and G.near(fr.tint, HL.Shade(epicC, 0.25)), "roll look fast: Gemini's tweak at the one shake (0.25 x Crack), nothing before it",
			fmt("%s; %s", tostring(fr.earlyTint), G.c3(fr.tint)))
		T.check(fr.punchUp >= 1.04, "roll look fast: the punch still plays in the shorter burst", fmt("%.3f", fr.punchUp))
		local hfR = G.content() and G.content():FindFirstChild("Hero")
		T.check(hfR and hfR:FindFirstChild("Punch") and abs(hfR.Punch.Scale - 1) <= 0.005, "roll look fast: ...and is 1 on the reveal")
		T.check(fr.over == nil, "roll look fast: within the budgets at every frame of Rise / Crack / Burst", tostring(fr.over))
		ES.Close()
		G.advance(0.4)
		env.CS.Set("FastHatch", false)
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
			-- (review round 2) B's tell per strip (spec 16.15: "x3: each strip its own pull's colour"): strip j's window
			-- at its own Land - 0.4 (0.3 s into its tell)
			x3.tell = x3.tell or {}
			for j = 1, 3 do
				local stopJ = T3.Intro + T3.Strip + (j - 1) * T3.LandGap
				if t >= stopJ - 0.4 and not x3.tell[j] then
					local ptr = G.pointer(j)
					local ws = G.stroke(ptr and ptr:FindFirstChild("Window"))
					x3.tell[j] = { told = ptr ~= nil and ptr:GetAttribute("Tell") == true, color = ws and ws.Color }
				end
			end
		end
		local tl = x3.tell or {}
		T.check(tl[1] and tl[1].told and G.near(tl[1].color, rareC, 2) and tl[2] and tl[2].told and G.near(tl[2].color, legC, 2) and tl[3] and not tl[3].told and G.near(tl[3].color, K.GOLD),
			"roll look open x3: each strip tells its own pull's colour (Rare blue, Legendary gold; the Common strip keeps the rest gold, no Tell)",
			fmt("%s %s / %s %s / %s %s", tostring(tl[1] and tl[1].told), G.c3(tl[1] and tl[1].color), tostring(tl[2] and tl[2].told), G.c3(tl[2] and tl[2].color), tostring(tl[3] and tl[3].told), G.c3(tl[3] and tl[3].color)))
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
-- client_roll_look_reveal
----------------------------------------------------------------------------------------------------
local CHEVRONS = "\226\128\186\226\128\186"

S.client_roll_look_reveal = guarded("client_roll_look_reveal", function()
	local env = G.setup(1920, 1080)
	local ES, HL, PC = env.ES, env.HL, env.PC
	if not T.check(type(HL) == "table" and type(HL.Word) == "function" and type(HL.Pill) == "function" and type(HL.Chip) == "function" and type(HL.FastChip) == "function",
		"roll look reveal: HatchLook.Word / Pill / Chip / FastChip exist") or not T.check(type(ES) == "table" and type(PC) == "table", "roll look reveal: EggStage and PetCatalog load") then
		G.restore(env)
		return
	end
	local KC = G.KC()
	local ok, err = pcall(function()
		local rgb = Color3.fromRGB
		local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
		local epic = PC.RarityPool("Cloud", "Epic")[1]
		local leg = PC.RarityPool("Storm", "Legendary")[1]
		------------------------------------------------------------------ an Epic x1 at 1920x1080, every 1/60 s
		local rec = { maxInst = 0, rollSkip = nil, rollFast = nil }
		local tRev = G.toReveal(ES, G.result(PC, "Cloud", { epic }), function(t, ph)
			local st = ES.Stats()
			rec.maxInst = math.max(rec.maxInst, st.Instances or 0)
			if ph == "Strip" and not rec.rollSkip then
				local skip = G.bar("Skip")
				local lbl = skip and skip:FindFirstChild("Label", true)
				rec.rollSkip = lbl and lbl.Text or "?"
			end
		end)
		if not T.check(tRev ~= nil, "roll look reveal: (setup) the Epic x1 reaches its reveal") then
			return
		end
		T.eq(rec.rollSkip, "Tap anywhere to skip " .. CHEVRONS, "roll look chips: the roll's Skip chip reads 'Tap anywhere to skip' + the chevrons")
		local word = G.colPart(1, "Word")
		local letters = G.letters(word)
		T.check(word ~= nil and word:IsA("Frame") and word:GetAttribute("Text") == "EPIC!" and word.Parent and word.Parent.Name == "Banner",
			"roll look word: Col1 > Banner > Word is a Frame with the attribute Text 'EPIC!'", word and (word.ClassName .. " " .. tostring(word:GetAttribute("Text"))) or "no Word")
		local partsOk = #letters == 5
		for _, l in ipairs(letters) do
			partsOk = partsOk and l:IsA("TextLabel") and l:FindFirstChildOfClass("UIGradient") ~= nil and l:FindFirstChildOfClass("UIStroke") ~= nil and l:FindFirstChild("Pop") ~= nil
		end
		T.check(partsOk, "roll look word: five letters L1..L5, each a TextLabel with its UIGradient, UIStroke and UIScale Pop", tostring(#letters))
		local samples = {}
		local function sample(label)
			samples[label] = {}
			for i, l in ipairs(letters) do
				samples[label][i] = G.popOf(l)
			end
			local glow = word and (word:FindFirstChild("Glow1") or word:FindFirstChild("Glow"))
			samples[label].glow = glow and (glow:IsA("ImageLabel") and glow.ImageTransparency or glow.BackgroundTransparency) or -1
		end
		local name, note, new = G.colPart(1, "Name"), G.colPart(1, "Note"), G.colPart(1, "New")
		local view = G.view(1)
		local again, done = G.bar("SpinAgain"), G.bar("Done")
		local function faceOf(btn)
			return btn and btn:FindFirstChild("Face")
		end
		local first = {
			nameY = name and name.AbsolutePosition.Y or 0, nameA = name and name.TextTransparency or -1, noteA = note and note.TextTransparency or -1,
			faceY = faceOf(again) and faceOf(again).Position.Y.Offset or -1, faceA = faceOf(again) and faceOf(again).GroupTransparency or -1,
			view = view and view.ImageColor3 or nil,
		}
		sample("start")
		local newPeak, overEarly, overLate = 0, nil, nil
		local disabled01, labelOff = nil, nil
		while os.clock() - tRev < 1.2 do
			Mock.Advance(FINE, FINE)
			local dt = os.clock() - tRev
			local o = G.overReveal(ES, 450, dt <= 0.7 and 32 or 24)
			if o then
				if dt <= 0.7 then
					overEarly = overEarly or fmt("%.2f s: %s", dt, o)
				else
					overLate = overLate or fmt("%.2f s: %s", dt, o)
				end
			end
			rec.maxInst = math.max(rec.maxInst, ES.Stats().Instances or 0)
			if new then
				newPeak = math.max(newPeak, G.popOf(new))
			end
			if dt >= 0.1 and disabled01 == nil then
				local lbl = again and again:FindFirstChild("Label", true)
				disabled01 = again ~= nil and done ~= nil and again:GetAttribute("Disabled") == true and done:GetAttribute("Disabled") == true
				labelOff = lbl and lbl.TextColor3 or nil
			end
			if dt >= 0.14 and not samples.p14 then
				sample("p14")
			end
			if dt >= 0.36 and not samples.p36 then
				sample("p36")
			end
			if dt >= 0.3 and not samples.p30 then
				sample("p30")
				rec.rays30 = G.hero("Rays") ~= nil and G.shown(G.hero("Rays"))
			end
			if dt >= 0.6 and not samples.p60 then
				sample("p60")
			end
		end
		T.check(samples.start[1] == 0 and samples.start[5] == 0, "roll look word: every letter starts at Pop 0", fmt("L1 %.2f L5 %.2f", samples.start[1], samples.start[5]))
		T.check(samples.p14[1] >= 1.25 and samples.p14[1] <= 1.31 and samples.p14[5] == 0, "roll look word: at + 0.14 s L1 has popped to its 1.3 peak and L5 waits (0.05 s a letter)",
			fmt("L1 %.2f L5 %.2f", samples.p14[1], samples.p14[5]))
		T.check(samples.p36[5] >= 1.25 and math.abs(samples.p36[1] - 1) <= 0.01, "roll look word: at + 0.36 s L5 peaks and L1 is back at 1", fmt("L1 %.2f L5 %.2f", samples.p36[1], samples.p36[5]))
		local allOne = true
		for i = 1, 5 do
			allOne = allOne and math.abs((samples.p60[i] or -1) - 1) <= 0.01
		end
		T.check(allOne, "roll look word: by + 0.6 s every letter rests at 1")
		local glowRest = 1 - HL.Metrics.WORD.GlowA -- (a fallback disc's own transparency at rest; its gradient fades it out)
		T.check(samples.start.glow >= 0.99 and abs(samples.p30.glow - glowRest) <= 0.01, "roll look word: the glow behind fades in by + 0.3 s", fmt("%.2f -> %.2f", samples.start.glow, samples.p30.glow))
		if letters[1] then
			local g = letters[1]:FindFirstChildOfClass("UIGradient")
			local kp = g and g.Color.Keypoints or {}
			local sk = letters[1]:FindFirstChildOfClass("UIStroke")
			T.check(#kp == 3 and G.near(kp[1].Value, rgb(238, 223, 250)) and G.near(kp[2].Value, rgb(193, 140, 237)) and G.near(kp[3].Value, rgb(144, 89, 190)) and g.Rotation == 90,
				"roll look word: L1's gradient is Shade(Epic, .78 / .22 / -.18) top to bottom", fmt("%s / %s / %s", G.c3(kp[1] and kp[1].Value), G.c3(kp[2] and kp[2].Value), G.c3(kp[3] and kp[3].Value)))
			-- (the mock's 0.12 x size SVG stroke is centred on the glyph's edge: 0.06 x size shows outside it, a UIStroke's
			-- whole thickness: 5 px at 84)
			T.check(sk and G.near(sk.Color, rgb(56, 35, 74)) and sk.Thickness == 5 and letters[1].TextSize == 84, "roll look word: L1's outline Shade(Epic, -.68), 5 px at 84 px (the mock's visible outline)", sk and fmt("%s %s, %d px", G.c3(sk.Color), tostring(sk.Thickness), letters[1].TextSize) or "no stroke")
		end
		T.check(first.view ~= nil and G.near(first.view, WHITE), "roll look reveal: an Epic pet is never a silhouette (its ViewportFrame white)", G.c3(first.view))
		-- the name / note slide up 16 px and fade in from + 0.2 s (over 0.25 s); NEW! pops at + 0.4 s
		T.check(name ~= nil and first.nameA >= 0.99 and first.noteA >= 0.99, "roll look reveal: the name and note start transparent", fmt("%.2f / %.2f", first.nameA, first.noteA))
		if name then
			local rise = first.nameY - name.AbsolutePosition.Y
			T.check(math.abs(rise - 16) <= 0.6 and name.TextTransparency <= 0.01 and note.TextTransparency <= 0.01, "roll look reveal: ...rise 16 px into place and show by + 0.45 s",
				fmt("rise %.1f, %.2f / %.2f", rise, name.TextTransparency, note.TextTransparency))
		end
		T.check(newPeak >= 1.25 and new ~= nil and math.abs(G.popOf(new) - 1) <= 0.01, "roll look reveal: NEW! pops past 1.25 and rests at 1", fmt("peak %.2f", newPeak))
		-- the pills
		local function pillParts(btn)
			local face = faceOf(btn)
			return { Shadow = btn and btn:FindFirstChild("Shadow"), Face = face, Body = face and face:FindFirstChild("Body"), Shine = btn and btn:FindFirstChild("Shine", true),
				Label = btn and btn:FindFirstChild("Label", true), Chip = btn and btn:FindFirstChild("Chip", true) }
		end
		local pa, pd = pillParts(again), pillParts(done)
		T.check(again and again:IsA("TextButton") and pa.Shadow and pa.Face and pa.Face:IsA("CanvasGroup") and pa.Body and pa.Body:FindFirstChildOfClass("UIGradient") and pa.Body:FindFirstChildOfClass("UIStroke") and pa.Shine and pa.Label,
			"roll look pills: SPIN AGAIN is a glossy pill (Shadow, Face (CanvasGroup) > Body (gradient + 3 px stroke), Shine, Label)")
		T.check(pa.Chip and pa.Chip:FindFirstChild("Coin") and pa.Chip:FindFirstChild("Price"), "roll look pills: SPIN AGAIN's price chip holds the Coin and the Price")
		T.check(done and done:IsA("TextButton") and pd.Shadow and pd.Face and pd.Body and pd.Shine and pd.Label and pd.Label.Text == "DONE", "roll look pills: DONE is a glossy pill too")
		T.check(again and done and math.abs(again.AbsoluteSize.Y - 56) <= 0.6 and math.abs(done.AbsoluteSize.Y - 56) <= 0.6, "roll look pills: 56 px tall at 1920x1080",
			again and fmt("%.1f / %.1f", again.AbsoluteSize.Y, done.AbsoluteSize.Y) or "none")
		T.check(first.faceY >= 8 and first.faceY <= 20 and first.faceA >= 0.99, "roll look pills: they start lower (up to 20 px: the room under them) and clear", fmt("%.1f px, %.2f", first.faceY, first.faceA))
		T.check(pa.Face and pa.Face.Position.Y.Offset == 0 and pa.Face.GroupTransparency <= 0.01 and pd.Face and pd.Face.Position.Y.Offset == 0, "roll look pills: ...and are in place, shown, by + 0.7 s")
		T.check(disabled01 == true and labelOff ~= nil and G.near(labelOff, rgb(176, 184, 206)), "roll look pills: disabled before ARM_AFTER (grey: the Label 176,184,206)", G.c3(labelOff))
		T.check(again:GetAttribute("Disabled") == false and done:GetAttribute("Disabled") == false and G.near(pa.Label.TextColor3, rgb(58, 34, 0)) and G.near(pd.Label.TextColor3, WHITE),
			"roll look pills: armed: SPIN AGAIN's label ink 58,34,0, DONE's white", fmt("%s / %s", G.c3(pa.Label and pa.Label.TextColor3), G.c3(pd.Label and pd.Label.TextColor3)))
		-- the chips
		local skip, fast = G.bar("Skip"), G.bar("FastHatch")
		-- (PC: the tap box is 56 design px, 44.8 real px at the 0.8 floor: the readability rule; the pill it draws is 36)
		local function chipOk(btn, boxH, pillH)
			local pill = btn and btn:FindFirstChild("Pill")
			return btn ~= nil and btn:IsA("TextButton") and math.abs(btn.AbsoluteSize.Y - boxH) <= 0.6 and pill ~= nil and math.abs(pill.AbsoluteSize.Y - pillH) <= 0.6
		end
		T.check(chipOk(skip, 56, 36) and chipOk(fast, 56, 36), "roll look chips: Skip and Fast hatch are tap boxes (56 design px on PC) drawing a 36 px pill",
			skip and fmt("%.1f / %.1f", skip.AbsoluteSize.Y, skip:FindFirstChild("Pill") and skip:FindFirstChild("Pill").AbsoluteSize.Y or -1) or "none")
		local skipLbl = skip and skip:FindFirstChild("Label", true)
		T.eq(skipLbl and skipLbl.Text, "Tap anywhere to close " .. CHEVRONS, "roll look chips: on the reveal the Skip chip reads 'Tap anywhere to close' + the chevrons")
		local before = env.CS.Get("FastHatch")
		Mock.Click(fast)
		G.advance(STEP)
		T.check(env.CS.Get("FastHatch") == (before ~= true) and fast:GetAttribute("On") == (before ~= true), "roll look chips: Fast hatch toggles ClientSettings and its switch (attribute On)")
		Mock.Click(fast)
		G.advance(STEP)
		-- (review round 2) the budget bookkeeping (spec 16.15 "Budgets"): each dressed piece's instances, counted here so the
		-- spec's numbers stay the ones the next budget change is planned from
		T.eq(word and G.count(word) or -1, 30, "roll look budget: a 5-letter word is 30 instances (its Frame, 3 glow capsules x 3, 5 letters x [TextLabel, UIGradient, UIStroke, UIScale])")
		T.eq((again and G.count(again) or 0) + (done and G.count(done) or 0), 28, "roll look budget: the two pills are 28 instances (SPIN AGAIN 16 with its price chip and coin icon, DONE 12 with its label outline)")
		T.eq((skip and G.count(skip) or 0) + (fast and G.count(fast) or 0), 13, "roll look budget: the two chips are 13 instances (Skip 4, Fast hatch 9)")
		-- (review round 2) SPIN AGAIN's refresh (every 8 heartbeats while the reveal shows) does nothing while nothing changed:
		-- no PillParts lookups, no measuring and fitting, no writes
		local spied, calls = { "PillParts", "FitPill", "SetPillChip" }, {}
		local real = {}
		for _, fname in ipairs(spied) do
			real[fname], calls[fname] = HL[fname], 0
			HL[fname] = function(...)
				calls[fname] = calls[fname] + 1
				return real[fname](...)
			end
		end
		local okSpy, errSpy = pcall(G.advance, 1.0)
		for _, fname in ipairs(spied) do
			HL[fname] = real[fname]
		end
		T.check(okSpy and calls.PillParts == 0 and calls.FitPill == 0 and calls.SetPillChip == 0,
			"roll look pills: an idle reveal's SPIN AGAIN refreshes do nothing (no PillParts / FitPill / SetPillChip calls in 1 s)",
			okSpy and fmt("%d / %d / %d", calls.PillParts, calls.FitPill, calls.SetPillChip) or tostring(errSpy))
		-- ...and a change still shows: too few tokens turns it to "Not enough Tokens" within the next refreshes
		local tokAttr = env.Config.Attr.Tokens
		local tokWas = LocalPlayer:GetAttribute(tokAttr)
		LocalPlayer:SetAttribute(tokAttr, 0)
		G.advance(0.4)
		local lblNow = again and again:FindFirstChild("Label", true)
		T.check(lblNow and lblNow.Text == "Not enough Tokens" and again:GetAttribute("Disabled") == true, "roll look pills: ...a balance too low still shows on SPIN AGAIN (Not enough Tokens, disabled)", lblNow and tostring(lblNow.Text) or "no label")
		LocalPlayer:SetAttribute(tokAttr, tokWas)
		G.advance(0.4)
		T.check(not rec.rays30, "roll look reveal: an Epic's rays are gone by + 0.3 s")
		T.check(rec.maxInst <= 450, "roll look reveal: x1 Stats().Instances <= 450 at every frame", tostring(rec.maxInst))
		T.check(overEarly == nil and overLate == nil, "roll look reveal: <= 32 tweens in the reveal's first 0.7 s, <= 24 after, one Heartbeat", tostring(overEarly or overLate))
		RedoGeom.check(G.content(), "roll look reveal 1920x1080 x1", { MinText = 18, NoOverlap = { "Banner", "Pedestal1", "Name", "Note", "SpinAgain", "Done", "Skip", "FastHatch" }, Skip = { Rays = true, Flash = true, Vignette = true } })
		-- (review round 1) no bowl: the pick's Baseline "the pet stands on a platform, and the shell flies away at the burst"
		local col1 = G.col(1)
		local petF, ped1 = G.colPart(1, "Pet"), G.hero("Pedestal1")
		T.check(col1 ~= nil and col1:FindFirstChild("Shell") == nil, "roll look reveal: no Shell under Col1 (no bowl under the pet: the halves flew away at the burst)")
		if petF and ped1 then
			local feet = petF.AbsolutePosition.Y + (ES.Metrics.LOOK.PET_FOOT or 0) * petF.AbsoluteSize.Y
			T.check(abs(feet - ped1.AbsolutePosition.Y) <= 1.5, "roll look reveal: the pet's feet (PET_FOOT of its frame) stand on the plinth's centre line (its box's top)",
				fmt("feet %.1f, plinth %.1f", feet, ped1.AbsolutePosition.Y))
			local sh = petF:FindFirstChild("Shadow")
			T.check(sh ~= nil and G.shown(sh) and abs((sh.AbsolutePosition.Y + sh.AbsoluteSize.Y / 2) - feet) <= 1 and sh.AbsoluteSize.X < petF.AbsoluteSize.X,
				"roll look reveal: a soft contact Shadow under its feet (inside the pet frame: it pops with the pet)")
		end
		-- (review round 1) the stage's toasts show while the HUD (NimbusMenu, the menu hint's gui) is hidden
		local function toastShown(text)
			for _, g in ipairs(G.pg():GetChildren()) do
				if g:IsA("ScreenGui") and g.Enabled then
					for _, d in ipairs(g:GetDescendants()) do
						if d:IsA("TextLabel") and d.Text:find(text, 1, true) and G.shown(d) then
							return g.Name
						end
					end
				end
			end
			return nil
		end
		ES._Answer({ Ok = false, Reason = "Smoke says no gems" })
		G.advance(0.5)
		local where1 = toastShown("Smoke says no gems")
		T.check(ES.IsShowing() and where1 ~= nil, "roll look reveal: a refused SPIN AGAIN's reason shows as a toast in an Enabled gui while the stage is up", tostring(where1))
		G.advance(5)
		local b0 = #KC.serverCalls("BuyRoulette")
		T.check(ES.Request("Cloud", "Tokens", 1) == true and #KC.serverCalls("BuyRoulette") == b0 + 1, "roll look reveal: (setup) a SPIN AGAIN request leaves")
		G.advance(ES.Metrics.WAIT_TIMEOUT + 0.4)
		local where2 = toastShown(ES.Metrics.TEXT.NoAnswer)
		T.check(ES.IsShowing() and where2 ~= nil, "roll look reveal: no answer in 7 s: 'Still waiting...' shows as a toast while the stage is up", tostring(where2))
		ES.Done()
		G.advance(0.4)
		------------------------------------------------------------------ 1280x720: the pills are 44.8 real px
		Mock.SetViewport(1280, 720)
		G.advance(0.3)
		tRev = G.toReveal(ES, G.result(PC, "Cloud", { epic }))
		G.advance(1.0)
		again = G.bar("SpinAgain")
		T.check(tRev ~= nil and again and math.abs(again.AbsoluteSize.Y - 44.8) <= 0.5 and math.abs(G.bar("Done").AbsoluteSize.Y - 44.8) <= 0.5, "roll look pills: 44.8 real px at 1280x720 (the 0.8 floor)",
			again and fmt("%.1f", again.AbsoluteSize.Y) or "none")
		T.check(G.bar("Skip") and math.abs(G.bar("Skip").AbsoluteSize.Y - 44.8) <= 0.5 and math.abs(G.bar("FastHatch").AbsoluteSize.Y - 44.8) <= 0.5, "roll look chips: 44.8 real px tap boxes at 1280x720")
		RedoGeom.check(G.content(), "roll look reveal 1280x720 x1", { MinText = 14, NoOverlap = { "Banner", "Pedestal1", "Name", "Note", "SpinAgain", "Done", "Skip", "FastHatch" }, Skip = { Rays = true, Flash = true, Vignette = true } })
		ES.Done()
		G.advance(0.4)
		Mock.SetViewport(1920, 1080)
		G.advance(0.3)
		------------------------------------------------------------------ (review round 2) PC: an evolved pull's ribbon rides the name row
		-- (name, NEW!, Evolved), never floating in the sky at the pet frame's corner
		local State = G.req("client/State")
		local savedStage, savedMeasure = State and State.PetStage, ES.Metrics.MEASURE
		if State then
			State.PetStage = function(key)
				if key == epic.Id then
					return 1
				end
				return savedStage and savedStage(key) or 0
			end
		end
		ES.Metrics.MEASURE = function(text, size, font)
			return RedoGeom.realWidth(text, size, font)
		end
		local okRib, errRib = pcall(function()
			G.toReveal(ES, G.result(PC, "Cloud", { epic }))
			G.advance(1.0)
			local rib, nm, nw, petF = G.colPart(1, "EvolvedRibbon"), G.colPart(1, "Name"), G.colPart(1, "New"), G.colPart(1, "Pet")
			if T.check(G.shown(rib) and G.shown(nm) and G.shown(nw) and petF ~= nil, "roll look reveal PC: (setup) the evolved NEW pull shows its name, NEW! and the Evolved ribbon") then
				local rb, nb, wb, pb = G.box(rib), G.box(nm), G.box(nw), G.box(petF)
				local cy = rb.y + rb.h / 2
				T.check(cy >= nb.y and cy <= nb.y + nb.h and rb.x >= wb.x + wb.w - 0.6 and not G.intersects(rb, nb) and not G.intersects(rb, wb) and not G.intersects(rb, pb),
					"roll look reveal PC: the Evolved ribbon sits in the name row after NEW! (clear of the name, NEW! and the pet frame)",
					fmt("ribbon %.0f,%.0f %.0fx%.0f; name %.0f..%.0f x %.0f..%.0f; NEW! ends %.0f", rb.x, rb.y, rb.w, rb.h, nb.x, nb.x + nb.w, nb.y, nb.y + nb.h, wb.x + wb.w))
				local okN = RedoGeom.fits(nm)
				T.check(okN, "roll look reveal PC: ...and the name still fits beside them")
			end
			ES.Done()
			G.advance(0.4)
		end)
		if State then
			State.PetStage = savedStage
		end
		ES.Metrics.MEASURE = savedMeasure
		T.check(okRib, "roll look reveal PC: the evolved step ran", tostring(errRib))
		------------------------------------------------------------------ a Legendary x1: the silhouette holds 0.3 s, the chain waits for it
		if T.check(leg ~= nil, "roll look silhouette: (setup) a Storm Legendary") then
			tRev = G.toReveal(ES, G.result(PC, "Storm", { leg }))
			local s = {}
			local b0 = #KC.serverCalls("BuyRoulette")
			local mashed = 0
			while tRev and os.clock() - tRev < 1.25 do
				Mock.Advance(FINE, FINE)
				local dt = os.clock() - tRev
				local v = G.view(1)
				local l1 = G.letters(G.colPart(1, "Word"))[1]
				local nm = G.colPart(1, "Name")
				if dt >= 0.1 and not s.p10 then
					local fl = G.stage() and G.stage():FindFirstChild("Flash")
					s.p10 = { view = v and v.ImageColor3, l1 = G.popOf(l1), flash = fl and fl.BackgroundTransparency or -1 }
					ES.Skip() -- a skip into the silhouette: the reveal ignores it
					Mock.Click(G.bar("Done")) -- a tap on DONE before ARM_AFTER does nothing
					local dim = G.stage() and G.stage():FindFirstChild("Dim")
					if dim then
						Mock.Click(dim)
					end
				end
				if dt >= 0.44 and not s.p44 then
					s.p44 = { l1 = G.popOf(l1) }
				end
				if dt >= 0.47 and not s.p47 then
					s.p47 = { view = v and v.ImageColor3 }
				end
				if dt >= 0.6 and not s.p60 then
					s.p60 = { nameA = nm and nm.TextTransparency or -1 }
				end
				if dt >= 0.78 and not s.p78 then
					s.p78 = { nameA = nm and nm.TextTransparency or -1, rays = G.hero("Rays") and G.hero("Rays").GroupTransparency or -1 }
				end
				-- a mash on SPIN AGAIN while the pills rise (SIL + 0.4 .. + 0.9)
				if dt >= 0.7 and dt <= 1.2 and mashed < 6 and math.floor(dt * 12) % 2 == 0 then
					Mock.Click(G.bar("SpinAgain"))
					mashed = mashed + 1
				end
			end
			T.check(s.p10 and s.p10.view and G.near(s.p10.view, BLACK, 3) and s.p10.l1 == 0, "roll look silhouette: Legendary: at + 0.1 s the pet is black and no letter has popped",
				s.p10 and fmt("%s, L1 %.2f", G.c3(s.p10.view), s.p10.l1) or "no sample")
			T.check(s.p10 and s.p10.flash >= 0.85, "roll look silhouette: the gold flash has cleared (transparency >= 0.85) by + 0.1 s: a black cut-out, not a sepia smudge",
				s.p10 and fmt("%.2f", s.p10.flash) or "no sample")
			T.check(s.p47 and s.p47.view and G.near(s.p47.view, WHITE, 3), "roll look silhouette: ...white again by + 0.3 + 0.16 s", s.p47 and G.c3(s.p47.view) or "no sample")
			T.check(s.p44 and s.p44.l1 >= 1.25, "roll look silhouette: ...the letters start at SIL 0.3 (L1 at its peak by + 0.44 s)", s.p44 and fmt("%.2f", s.p44.l1) or "no sample")
			T.check(s.p60 and s.p60.nameA >= 0.99 and s.p78 and s.p78.nameA <= 0.01, "roll look silhouette: ...the name waits too (still clear at + 0.6 s, shown by + 0.78 s)",
				fmt("%.2f -> %.2f", s.p60 and s.p60.nameA or -1, s.p78 and s.p78.nameA or -1))
			T.check(s.p78 and math.abs(s.p78.rays - 0.55) <= 0.02, "roll look reveal: Legendary's rays rest at GroupTransparency 0.55 while the text shows", s.p78 and fmt("%.2f", s.p78.rays) or "-")
			T.eq(ES.Phase(), "Reveal", "roll look silhouette: a Skip, a DONE tap and a Dim tap into the silhouette leave the reveal up")
			T.check(mashed >= 6 and #KC.serverCalls("BuyRoulette") - b0 == 0, "roll look pills: a mash on SPIN AGAIN while the pills rise sends no BuyRoulette", fmt("%d taps, %d sends", mashed, #KC.serverCalls("BuyRoulette") - b0))
			local lw = G.letters(G.colPart(1, "Word"))
			local done1 = #lw == 10
			for _, l in ipairs(lw) do
				done1 = done1 and math.abs(G.popOf(l) - 1) <= 0.01
			end
			local fa = G.bar("SpinAgain") and G.bar("SpinAgain"):FindFirstChild("Face")
			local v = G.view(1)
			T.check(done1 and fa and fa.Position.Y.Offset == 0 and fa.GroupTransparency <= 0.01 and v and G.near(v.ImageColor3, WHITE, 3), "roll look silhouette: ...and the reveal is complete by + 1.25 s (colour, ten letters at 1, pills in place)",
				fmt("%d letters", #lw))
			ES.Done()
			G.advance(0.4)
		end
		------------------------------------------------------------------ x3 (Storm Rare / Legendary / Common or Epic) at 1920x1080
		local storm = function(r)
			return PC.RarityPool("Storm", r)[1]
		end
		local d1, d2, d3 = storm("Rare") or epic, leg, storm("Common") or epic
		local maxX3 = 0
		tRev = G.toReveal(ES, G.result(PC, "Storm", { d1, d2, d3 }), function()
			maxX3 = math.max(maxX3, ES.Stats().Instances or 0)
		end)
		local x3over = nil
		local sil3 = nil
		local armEarly, pillsSeen = nil, false
		while tRev and os.clock() - tRev < 1.3 do
			Mock.Advance(FINE, FINE)
			local dt = os.clock() - tRev
			maxX3 = math.max(maxX3, ES.Stats().Instances or 0)
			-- (review round 1) no taps here: SPIN AGAIN stays disabled until its rise is done (the silhouette delays it to 1.0 s)
			local pin, ag = G.bar("PillsIn"), G.bar("SpinAgain")
			local LK = ES.Metrics.LOOK
			local inPlace = LK.SIL.Hold + LK.CHAIN.Pills + LK.CHAIN.PillsIn
			if pin and ag then
				pillsSeen = true
				if (pin.Value < 1 - 1e-6 or dt < inPlace - 0.02) and ag:GetAttribute("Disabled") == false and not armEarly then
					armEarly = fmt("%.2f s: armed with the pills at %.2f", dt, pin.Value)
				end
			end
			local o = G.overReveal(ES, 750, dt <= 0.7 and 32 or 24)
			if o and not x3over then
				x3over = fmt("%.2f s: %s", dt, o)
			end
			if dt >= 0.1 and not sil3 then
				sil3 = {}
				for j = 1, 3 do
					local v = G.view(j)
					sil3[j] = v and v.ImageColor3 or nil
				end
			end
		end
		local wordsOk, bad = true, ""
		for j, def in ipairs({ d1, d2, d3 }) do
			local w = G.colPart(j, "Word")
			local ls = G.letters(w)
			local want = string.upper(def.Rarity) .. "!"
			if not (w and w:GetAttribute("Text") == want and #ls == #want and ls[1].TextSize == 56) then
				wordsOk = false
				bad = bad .. fmt("col %d %s %d letters; ", j, w and tostring(w:GetAttribute("Text")) or "none", #ls)
			end
		end
		T.check(tRev ~= nil and wordsOk, "roll look x3: three letter words at 56 px in the server's order", bad)
		T.check(sil3 and sil3[2] and G.near(sil3[2], BLACK, 3) and sil3[1] and G.near(sil3[1], WHITE) and sil3[3] and G.near(sil3[3], WHITE),
			"roll look x3: the silhouette only on the Legendary column", sil3 and fmt("%s / %s / %s", G.c3(sil3[1]), G.c3(sil3[2]), G.c3(sil3[3])) or "no sample")
		T.check(pillsSeen and armEarly == nil and G.bar("SpinAgain"):GetAttribute("Disabled") == false, "roll look x3 (Legendary best): SPIN AGAIN stays disabled until its rise is in place, then arms",
			tostring(armEarly))
		local shells = 0
		for j = 1, 3 do
			if G.col(j) and G.col(j):FindFirstChild("Shell") then
				shells = shells + 1
			end
		end
		T.eq(shells, 0, "roll look x3: no Shell under any column (no bowls)")
		T.check(maxX3 <= 750, "roll look x3: Stats().Instances <= 750 at every frame", tostring(maxX3))
		T.check(x3over == nil, "roll look x3: <= 32 tweens in the reveal's first 0.7 s, <= 24 after", tostring(x3over))
		ES.Done()
		G.advance(0.4)
	end)
	if not ok then
		T.check(false, "roll look reveal: the scenario ran without an error", tostring(err))
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
		-- (egg-cards, spec 16.18) with the egg_card ids every shown picture is a square inside its card (x1 and x3)
		if type(HL.EGG_IMAGES) == "table" then
			local ids = {}
			for i, r in ipairs(RARITIES) do
				ids["egg_card_" .. r:lower()] = 9100 + i
			end
			HL._Textures = ids
			for _, size in ipairs({ { 844, 390 }, { 640, 360 } }) do
				for _, n in ipairs({ 1, 3 }) do
					local label = fmt("roll look phone %dx%d x%d egg cards", size[1], size[2], n)
					Mock.SetViewport(size[1], size[2])
					G.advance(0.3)
					local t1 = os.clock()
					local defs = n == 1 and { epic } or { epic, epic, epic }
					ES.Show(G.result(PC, "Cloud", defs))
					G.until_(t1, 2.0)
					local pics, outside, most = 0, "", 0
					for j = 1, n do
						for _, c in ipairs(G.cells(j)) do
							most = math.max(most, G.count(c))
							local pic = c:FindFirstChild("EggPic")
							if c.Visible and pic and pic.Visible then
								pics = pics + 1
								local pb, cb = G.box(pic), G.box(c)
								if pb.x < cb.x - 0.6 or pb.y < cb.y - 0.6 or pb.x + pb.w > cb.x + cb.w + 0.6 or pb.y + pb.h > cb.y + cb.h + 0.6 or abs(pb.w - pb.h) > 0.6 then
									outside = outside .. fmt("%s %.0f,%.0f %.0fx%.0f in %.0f,%.0f %.0fx%.0f; ", c.Name, pb.x, pb.y, pb.w, pb.h, cb.x, cb.y, cb.w, cb.h)
								end
							end
						end
					end
					T.check(pics >= 3 and outside == "", label .. ": every shown picture is a square inside its card", fmt("%d pictures; %s", pics, outside))
					T.check(most <= (n == 1 and 20 or 16), label .. ": a cell stays inside its budget", tostring(most))
					ES.Close()
					G.advance(0.4)
				end
			end
			HL._Textures = false
		else
			T.check(false, "roll look phone egg cards: HatchLook.EGG_IMAGES exists")
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
			T.check(abs(p.Box.AbsoluteSize.X - 1.1 * eh) <= 1.5 and abs(p.Box.AbsoluteSize.Y - 0.24 * eh) <= 1.5 and abs(p.Top.AbsoluteSize.Y / p.Box.AbsoluteSize.Y - 0.85) <= 0.015,
				"roll look phone plinth: 1.1 x / 0.24 x the egg, the Top 0.85 of it (an ellipse about 5 : 1)", fmt("egg %d, box %.1f x %.1f, top %.1f", eh, p.Box.AbsoluteSize.X, p.Box.AbsoluteSize.Y, p.Top.AbsoluteSize.Y))
			T.check(p.Rim and p.Rim.Thickness == 2, "roll look phone plinth: a 2 px rim", tostring(p.Rim and p.Rim.Thickness))
		end
		-- (review round 1) the title is gone over the hero (it sat 1 px above the crack word on a landscape phone)
		local titleP = G.content() and G.content():FindFirstChild("Title")
		T.check(titleP == nil or not G.shown(titleP) or titleP.TextTransparency >= 0.99, "roll look phone: the machine's title is gone at the rise's end (no headline glued to the crack word)",
			titleP and fmt("%.2f", titleP.TextTransparency) or "none")
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
		T.check(p.Top and G.shown(p.Top) and abs(p.Top.AbsoluteSize.Y - 12) <= 0.6 and not G.shown(p.Side) and not G.shown(p.Ring) and not G.shown(p.Glow1)
			and not G.shown(p.Wall) and not G.shown(p.Edge) and not G.shown(p.Cover),
			"roll look phone: the reveal keeps the 12 px lip (the plinth's Top only)", p.Top and fmt("%.1f px", p.Top.AbsoluteSize.Y) or "no Top")
		-- (review round 2) ...an ellipse with its rim round it (the Rim disc 2 px past the lip every way)
		local lipRim = p.Rim and p.Rim.Inst
		T.check(lipRim and G.shown(lipRim) and p.Top and abs((lipRim.AbsoluteSize.Y - p.Top.AbsoluteSize.Y) / 2 - 2) <= 0.6 and abs((lipRim.AbsoluteSize.X - p.Top.AbsoluteSize.X) / 2 - 2) <= 0.6,
			"roll look phone: ...the lip's 2 px Rim disc round it", lipRim and fmt("%.1f x %.1f", lipRim.AbsoluteSize.X, lipRim.AbsoluteSize.Y) or "no rim")
		ES.Close()
		G.advance(0.4)
		------------------------------------------------------------------ (Task 3) the x1 landscape reveal side by side
		for _, size in ipairs({ { 844, 390 }, { 640, 360 } }) do
			local W = size[1]
			local label = fmt("roll look phone reveal %dx%d", size[1], size[2])
			Mock.SetViewport(size[1], size[2])
			G.advance(0.3)
			local tRev = G.toReveal(ES, G.result(PC, "Cloud", { epic }))
			G.advance(1.0)
			if T.check(tRev ~= nil and ES.Phase() == "Reveal", label .. ": (setup) the reveal") then
				local split = 0.46 * W
				local pet = G.colPart(1, "Pet")
				local pb = pet and G.box(pet)
				T.check(pb ~= nil and pb.x + pb.w / 2 < split and pb.x >= -0.6 and pb.w >= 110 - 0.6, label .. ": the pet (>= 110 px) stands in the left 0.46 of the screen",
					pb and fmt("%.0f..%.0f (%.0f px) of %.0f", pb.x, pb.x + pb.w, pb.w, split) or "no pet")
				local where = {}
				for _, nm in ipairs({ "Banner", "Name", "Note" }) do
					local b = G.colPart(1, nm) and G.box(G.colPart(1, nm))
					if not (b and b.x >= split - 0.6 and b.x + b.w <= W + 0.6) then
						where[#where + 1] = nm .. (b and fmt(" %.0f..%.0f", b.x, b.x + b.w) or " none")
					end
				end
				for _, nm in ipairs({ "SpinAgain", "Done" }) do
					local b = G.bar(nm) and G.box(G.bar(nm))
					if not (b and b.x >= split - 0.6 and b.x + b.w <= W + 0.6 and abs(b.h - 46) <= 0.6) then
						where[#where + 1] = nm .. (b and fmt(" %.0f..%.0f x %.1f", b.x, b.x + b.w, b.h) or " none")
					end
				end
				T.check(#where == 0, label .. ": the word, name, note and the two 46 px pills sit in the right column", table.concat(where, "; "))
				local note, again, skip = G.colPart(1, "Note"), G.bar("SpinAgain"), G.bar("Skip")
				if note and again and skip then
					local nb, ab, sb = G.box(note), G.box(again), G.box(skip)
					T.check(ab.y >= nb.y + nb.h - 0.6 and ab.y + ab.h <= sb.y + 0.6, label .. ": the pills sit under the note, above the chips' row",
						fmt("note ends %.0f, pills %.0f..%.0f, chips from %.0f", nb.y + nb.h, ab.y, ab.y + ab.h, sb.y))
				end
				for _, nm in ipairs({ "Skip", "FastHatch" }) do
					local o = G.bar(nm)
					local pill = o and o:FindFirstChild("Pill")
					T.check(o ~= nil and abs(o.AbsoluteSize.Y - 44) <= 0.6 and pill ~= nil and abs(pill.AbsoluteSize.Y - 32) <= 0.6, label .. ": the " .. nm .. " chip is a 44 px box drawing a 32 px pill",
						o and fmt("%.1f / %s", o.AbsoluteSize.Y, pill and fmt("%.1f", pill.AbsoluteSize.Y) or "no pill") or "none")
				end
				local ls = G.letters(G.colPart(1, "Word"))
				T.check(#ls == 5 and ls[1].TextSize >= 40 and ls[1].TextSize <= 44, label .. ": the word as letters at 44 px (40 at the least)", ls[1] and tostring(ls[1].TextSize) or "no letters")
				local lip = G.hero("Pedestal1")
				T.check(lip ~= nil and pb ~= nil and abs(lip.AbsoluteSize.Y - 12) <= 0.6 and abs((lip.AbsolutePosition.Y + lip.AbsoluteSize.Y) - (pb.y + pb.h - 8)) <= 0.6,
					label .. ": the 12 px lip under the pet")
				T.eq(G.viewports(), 1, label .. ": exactly one ViewportFrame (the pet's)")
				RedoGeom.check(G.content(), label, { MinText = 15, NoOverlap = { "Banner", "Name", "Note", "SpinAgain", "Done", "Skip", "FastHatch", "Pedestal1" }, Skip = SKIP })
			end
			ES.Done()
			G.advance(0.4)
		end
		------------------------------------------------------------------ portrait 360x640: the stack, the word as letters in the band
		Mock.SetViewport(360, 640)
		G.advance(0.3)
		local tRevP = G.toReveal(ES, G.result(PC, "Cloud", { epic }))
		G.advance(1.0)
		local band = G.colPart(1, "Banner")
		local lsP = G.letters(G.colPart(1, "Word"))
		T.check(tRevP ~= nil and band ~= nil and abs(band.AbsoluteSize.Y - 44) <= 0.6 and abs(band.AbsolutePosition.Y - 60) <= 0.6 and #lsP == 5 and lsP[1].TextSize == 40,
			"roll look phone portrait 360x640: the stack (the 44 px band at the top, the word as 40 px letters)", band and fmt("band %.1f at %.1f, %d letters", band.AbsoluteSize.Y, band.AbsolutePosition.Y, #lsP) or "no band")
		RedoGeom.check(G.content(), "roll look phone portrait 360x640", { MinText = 15, NoOverlap = { "Banner", "Pedestal1", "Name", "Note", "SpinAgain", "Done", "Skip", "FastHatch" }, Skip = SKIP })
		ES.Done()
		G.advance(0.4)
		------------------------------------------------------------------ x3 phone words: one TextLabel each
		Mock.SetViewport(844, 390)
		G.advance(0.3)
		local storm3 = function(r)
			return PC.RarityPool("Storm", r)[1]
		end
		local defs3 = { storm3("Rare") or epic, storm3("Legendary") or epic, storm3("Common") or epic }
		G.toReveal(ES, G.result(PC, "Storm", defs3))
		G.advance(1.0)
		local labelsOk, why = true, ""
		for j, def in ipairs(defs3) do
			local w = G.colPart(j, "Word")
			if not (w and w:IsA("TextLabel") and w:GetAttribute("Text") == string.upper(def.Rarity) .. "!" and w:FindFirstChild("L1") == nil) then
				labelsOk = false
				why = why .. fmt("col %d %s; ", j, w and w.ClassName or "none")
			end
		end
		T.check(labelsOk, "roll look phone x3: each word is one TextLabel (no letters), its Text attribute set", why)
		ES.Done()
		G.advance(0.4)
		------------------------------------------------------------------ (review round 2) x3 at 640x360 with the real font widths: an
		-- evolved NEW pull keeps one sticker over the pet's head, the Skip chip's label is never cut, a note that wraps breaks at
		-- its dot (no one-word line)
		local State = G.req("client/State")
		local savedStage, savedMeasure = State and State.PetStage, ES.Metrics.MEASURE
		local evoId = defs3[3] and defs3[3].Id
		if State then
			State.PetStage = function(key)
				if key == evoId then
					return 1
				end
				return savedStage and savedStage(key) or 0
			end
		end
		ES.Metrics.MEASURE = function(text, size, font)
			return RedoGeom.realWidth(text, size, font)
		end
		local okSmall, errSmall = pcall(function()
			Mock.SetViewport(640, 360)
			G.advance(0.3)
			G.toReveal(ES, G.result(PC, "Storm", defs3))
			G.advance(1.2)
			local new3, rib3, pet3 = G.colPart(3, "New"), G.colPart(3, "EvolvedRibbon"), G.colPart(3, "Pet")
			if T.check(G.shown(new3) and G.shown(rib3) and pet3 ~= nil, "roll look phone x3 640x360: (setup) the evolved NEW pull shows NEW! and the Evolved ribbon") then
				local nb, rb, pb = G.box(new3), G.box(rib3), G.box(pet3)
				T.check(not G.intersects(nb, rb) and nb.y + nb.h / 2 > pb.y + pb.h / 2,
					"roll look phone x3 640x360: NEW! and Evolved never stack over the pet's head (the ribbon on the top corner, NEW! on the bottom one)",
					fmt("NEW! %.0f,%.0f %.0fx%.0f; ribbon %.0f,%.0f %.0fx%.0f; pet %.0f..%.0f", nb.x, nb.y, nb.w, nb.h, rb.x, rb.y, rb.w, rb.h, pb.y, pb.y + pb.h))
				T.check(rb.x >= pb.x - 0.6 and rb.x + rb.w <= pb.x + pb.w + 0.6 and rb.w <= 0.75 * pb.w, "roll look phone x3 640x360: the ribbon stays a corner tag (<= 0.75 of the pet frame), not a band across the pet",
					fmt("%.0f of %.0f px", rb.w, pb.w))
			end
			local skipL = G.bar("Skip") and G.bar("Skip"):FindFirstChild("Label", true)
			local okSkip, dSkip = RedoGeom.fits(skipL)
			T.check(skipL ~= nil and okSkip, "roll look phone x3 640x360: the Skip chip's label fits its chip (never 'Tap to close...')", tostring(dSkip))
			local notes = {}
			for j = 1, 3 do
				local note = G.colPart(j, "Note")
				local s = note and tostring(note.Text) or ""
				local w = note and note.AbsoluteSize.X or 0
				local one = note and RedoGeom.realWidth(s:gsub("\n", " "), note.TextSize, note.Font) or 0
				local bad = nil
				if note and one > w + 0.5 then
					if not s:find("\n", 1, true) then
						bad = "wraps by itself"
					else
						for line in s:gmatch("[^\n]+") do
							if RedoGeom.realWidth(line, note.TextSize, note.Font) > w + 0.5 then
								bad = "line '" .. line .. "' does not fit"
							end
						end
					end
				end
				if bad then
					notes[#notes + 1] = fmt("col %d: %s ('%s', %.0f px in %.0f)", j, bad, (s:gsub("[\128-\255]+", "?")), one, w)
				end
			end
			T.check(#notes == 0, "roll look phone x3 640x360: a note too long for one line breaks at its dot (each line a whole phrase, no orphan word)", table.concat(notes, "; "))
			ES.Done()
			G.advance(0.4)
		end)
		if State then
			State.PetStage = savedStage
		end
		ES.Metrics.MEASURE = savedMeasure
		T.check(okSmall, "roll look phone x3 640x360: the step ran", tostring(errSmall))
		------------------------------------------------------------------ (review round 2) a rotation mid-rise: the lifted strips go at once
		Mock.SetViewport(844, 390)
		G.advance(0.3)
		local T3p = ES.Timings(false, 3)
		local rise3p = T3p.Intro + T3p.Strip + 2 * T3p.LandGap + T3p.Land
		t0 = os.clock()
		ES.Show(G.result(PC, "Storm", defs3))
		G.until_(t0, rise3p + 0.1)
		local n0 = ES.Stats().Instances or 0
		Mock.SetViewport(390, 844)
		G.advance(STEP)
		local n1 = ES.Stats().Instances or 0
		local s1 = G.strip(1)
		T.check(ES.Phase() == "Rise" and (s1 == nil or not G.shown(s1)) and n1 <= n0, "roll look phone: a rotation mid-rise drops the lifted strips (no cards rebuilt, nothing snaps back on screen)",
			fmt("%s, strip %s, %d -> %d instances", tostring(ES.Phase()), tostring(s1 ~= nil and G.shown(s1)), n0, n1))
		T.check(G.untilPhase(ES, "Reveal", 6) ~= nil, "roll look phone: ...and the roll reaches the reveal")
		ES.Close()
		G.advance(0.4)
		------------------------------------------------------------------ a rotation mid-chain: 844x390 -> 390x844 at reveal + 0.15
		Mock.SetViewport(844, 390)
		G.advance(0.3)
		local tRevR = G.toReveal(ES, G.result(PC, "Cloud", { epic }))
		G.advance(0.15)
		Mock.SetViewport(390, 844)
		G.advance(STEP)
		local function chainDone()
			local ls = G.letters(G.colPart(1, "Word"))
			local okL = #ls == 5
			for _, l in ipairs(ls) do
				okL = okL and abs(G.popOf(l) - 1) <= 0.01
			end
			local nm = G.colPart(1, "Name")
			local faces = true
			for _, b in ipairs({ "SpinAgain", "Done" }) do
				local f = G.bar(b) and G.bar(b):FindFirstChild("Face")
				faces = faces and f ~= nil and f.Position.Y.Offset == 0 and f.GroupTransparency <= 0.01
			end
			return okL and faces and nm ~= nil and nm.TextTransparency <= 0.01, fmt("letters %s, faces %s, name %.2f", tostring(okL), tostring(faces), nm and nm.TextTransparency or -1)
		end
		local done1, d1 = chainDone()
		T.check(tRevR ~= nil and done1 and ES.Phase() == "Reveal", "roll look phone: a rotation mid-chain settles it at once (every letter at 1, the pills in place, the text shown)", d1)
		G.advance(1.0)
		local done2, d2 = chainDone()
		T.check(done2 and ES.Phase() == "Reveal", "roll look phone: ...and nothing is left half way a second later", d2)
		RedoGeom.check(G.content(), "roll look phone rotated 390x844", { MinText = 15, NoOverlap = { "Banner", "Pedestal1", "Name", "Note", "SpinAgain", "Done", "Skip", "FastHatch" }, Skip = SKIP })
		ES.Done()
		G.advance(0.4)
	end)
	if not ok then
		T.check(false, "roll look phone: the scenario ran without an error", tostring(err))
	end
	G.restore(env)
end)

return S
