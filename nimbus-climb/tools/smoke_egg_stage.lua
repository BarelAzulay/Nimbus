-- smoke_egg_stage.lua: lobby-shop Task 20 (spec 16.4 "The egg-opening cutscene", 5.5 "The egg stage", 16.5's EggArt API):
-- the plain egg stage core (client/UI/EggStage) and the frame eggs (client/UI/EggArt). Loaded by tools/smoke.py in the
-- CLIENT and PHONE worlds (Tasks 22 / 26 / 27 extend this file):
--   client_egg_art         (client, 1920x1080)
--     the seven eggs at 30 / 64 / 104 / 160 / 380 px: a Frame "Egg_<Rarity>" (0.8 x size wide, size tall) with a round
--       UICorner, the top-to-bottom tone UIGradient "Tone" (EggArt.Tones), the navy UIStroke "Outline" rgb(11,16,48) at
--       size / 20 (>= 2 px, whole), a white "Highlight"; attribute Form Simple (< 48) / Medium (48-140) / Full (> 140) and
--       the instance caps 8 / 14 / 28; opts Name / ZIndex / Form
--     EggArt.Glow (0 / 0 / 0.22 / 0.34 / 0.58 / 0.66 / 0.78), EggArt.Tones (the rarity colour 38% toward white / 28% toward
--       black; Secret rgb(74,68,104) / rgb(18,16,28)), EggArt.Paint -> a table (empty until Task 26)
--     EggArt.Halves -> two CanvasGroups covering the egg's height (top half, bottom half); SetRarity re-skins in place (the
--       instance count kept, the tones and the name follow)
--   client_egg_stage       (client, 1920x1080, the stage alone: EggStage.Show / the _Answer listener body; Task 22 wires Init
--                          into ShopController)
--     a Cloud x1 Epic result: the seven phases in order, Reveal at 5.75 +- 0.1 s; CrackWord "EPIC EGG!", the reveal Word
--       "EPIC!", the notes (new / not new / substitute / pity), New; Skip shown on the first frame and Skip() at t = 0 ->
--       Reveal on the next frame; Back() and gamepad B skip, then are DONE; an Esc InputBegan changes nothing; the
--       character removed mid-Strip; Fast hatch (the toggle -> one SettingsSet 0.4 s later, Reveal 1.92 / 2.66); x3
--       (7.15 s, strips landing 0.25 s apart, cracks in pull order 0.6 s apart, three columns); evolved keys; old-shape
--       results and pulls without a Strip (start at Rise); the request path (FIRE_GAP, the pending flag, a failure, the 7 s
--       timeout, a late success, the queue, SPIN AGAIN, Init's listener); the sounds; <= 12 Cell frames per strip; the
--       instance caps 450 / 750; Stats() zero after every exit (Done, Close, a match start, a phase error); the Camera, the
--       Humanoid and the touch controls as they were; no gem glyph in NimbusHatch
--   client_egg_stage_mobile (phone world): x1 and x3, during Crack and on the reveal, at 640x360, 667x375, 844x390, 360x640,
--       390x844, 1280x720, 1366x768 (RedoGeom.check with the per-phase NoOverlap lists of plan Task 20), the phone fit
--       numbers (the crack stack, the reveal lip, the 44 px Banner), the x3 pets inside the screen, the bottom bar above
--       the bottom inset, and the resize mid-roll (Review Focus 1)
-- Deterministic: mock clock only. SoundFx.Play and MenuController.Hint are spied and put back; the viewport, the Fast hatch
-- setting and the attributes are put back. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local fmt = string.format
local abs = math.abs

local S = {}

local DOT = "\194\183"
local GLYPH = "\226\151\134"
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
local GLOW = { Common = 0, Uncommon = 0, Rare = 0.22, Epic = 0.34, Legendary = 0.58, Mythic = 0.66, Secret = 0.78 }
local STEP = 1 / 30

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
function G.find(root, name)
	return RedoGeom.find(root, name)
end
function G.box(o)
	local p, s = o.AbsolutePosition, o.AbsoluteSize
	return { x = p.X, y = p.Y, w = s.X, h = s.Y }
end
function G.shown(o)
	return o ~= nil and G.KC().isShown(o)
end
function G.intersects(a, b)
	local tol = 0.51
	return a.x < b.x + b.w - tol and b.x < a.x + a.w - tol and a.y < b.y + b.h - tol and b.y < a.y + a.h - tol
end
function G.rgb(c, r, g, b)
	return c ~= nil and abs(c.R * 255 - r) < 1 and abs(c.G * 255 - g) < 1 and abs(c.B * 255 - b) < 1
end
function G.same(a, b)
	return a ~= nil and b ~= nil and abs(a.R - b.R) < 2e-3 and abs(a.G - b.G) < 2e-3 and abs(a.B - b.B) < 2e-3
end
function G.rarityColor(Config, rarity)
	for _, r in ipairs(Config.Rarities) do
		if r.Id == rarity then
			return r.Color
		end
	end
	return nil
end
-- the largest number of Cell frames any Strip<j>.Track holds right now
function G.maxCells()
	local content = G.content()
	local strips = content and content:FindFirstChild("Strips")
	local most = 0
	for _, strip in ipairs(strips and strips:GetChildren() or {}) do
		local track = strip:FindFirstChild("Track")
		local n = 0
		for _, c in ipairs(track and track:GetChildren() or {}) do
			if c.Name:match("^Cell%d+$") then
				n = n + 1
			end
		end
		if n > most then
			most = n
		end
	end
	return most
end
-- a 40-cell strip from the roulette's possible pets with the winner at cell 34
function G.strip(PC, rid, winnerId)
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
function G.pull(PC, rid, def, opts)
	opts = opts or {}
	local isNew = opts.IsNew ~= false
	local p = {
		PetId = def.Id, Key = opts.Key or def.Id, Rarity = def.Rarity, IsNew = isNew, NewDiscovery = isNew, Count = opts.Count or 1,
		PoolSize = #PC.RarityPool(rid, def.Rarity), Pity = opts.Pity, Substitute = opts.Substitute,
	}
	if opts.Strip ~= false then
		p.Strip = G.strip(PC, rid, def.Id)
	end
	return p
end
function G.result(rid, currency, pulls)
	local r = { Ok = true, RouletteId = rid, Currency = currency, Spins = #pulls, UnitPrice = 50, Price = 50 * #pulls, Pulls = pulls, Tokens = 5000, Gems = 5000 }
	local p1 = pulls[1]
	r.PetId, r.Key, r.IsNew, r.NewDiscovery, r.Count, r.Strip = p1.PetId, p1.Key, p1.IsNew, p1.NewDiscovery, p1.Count, p1.Strip
	return r
end
-- plays the stage until the Reveal (or maxT), sampling every step:
--   -> { order = { phases in the order first seen }, at = { [phase] = s after the start }, maxInst, maxCells }
function G.run(ES, maxT, onStep)
	local t0 = os.clock()
	local out = { order = {}, at = {}, maxInst = 0, maxCells = 0 }
	while os.clock() - t0 <= maxT + 1e-6 do
		local ph = ES.Phase()
		if ph and out.at[ph] == nil then
			out.at[ph] = os.clock() - t0
			out.order[#out.order + 1] = ph
		end
		local st = ES.Stats()
		out.maxInst = math.max(out.maxInst, st.Instances or 0)
		out.maxCells = math.max(out.maxCells, G.maxCells())
		if onStep then
			onStep(os.clock() - t0, ph)
		end
		if ph == "Reveal" or ph == nil then
			break
		end
		G.advance(STEP)
	end
	return out
end
-- advances until the stage's elapsed time reaches `t` (seconds after Show at `t0`)
function G.until_(t0, t)
	local left = t - (os.clock() - t0)
	if left > 0 then
		G.advance(left)
	end
end
function G.colPart(j, name)
	local content = G.content()
	local reveal = content and content:FindFirstChild("Reveal")
	local col = reveal and reveal:FindFirstChild("Col" .. j)
	if not col then
		return nil, nil
	end
	if not name then
		return col, col
	end
	return col:FindFirstChild(name, true), col
end
function G.bar(name)
	local content = G.content()
	local bar = content and content:FindFirstChild("BottomBar")
	return bar and bar:FindFirstChild(name) or nil
end
function G.hero(name)
	local content = G.content()
	local hero = content and content:FindFirstChild("Hero")
	return hero and hero:FindFirstChild(name) or nil
end
function G.zeroStats(ES, label)
	local st = ES.Stats()
	T.check(st.Instances == 0 and st.Tweens == 0 and st.Sparks == 0 and st.Effects == 0 and st.Heartbeats == 0 and G.gui() == nil,
		label .. ": Stats() is all zero and NimbusHatch is gone",
		fmt("inst %s tweens %s sparks %s effects %s hb %s gui %s", tostring(st.Instances), tostring(st.Tweens), tostring(st.Sparks), tostring(st.Effects), tostring(st.Heartbeats), tostring(G.gui())))
end
function G.snapshot()
	local cam = workspace.CurrentCamera
	local hum = G.KC().hum()
	return {
		cam.CameraType, cam.CameraSubject, cam.FieldOfView,
		hum and hum.WalkSpeed or -1, hum and hum.JumpPower or -1,
		game:GetService("GuiService").TouchControlsEnabled,
	}
end
function G.sameSnapshot(a, b)
	for i = 1, 6 do
		if a[i] ~= b[i] then
			return false, "field " .. i .. ": " .. tostring(a[i]) .. " -> " .. tostring(b[i])
		end
	end
	return true, ""
end
-- every shown TextLabel / TextButton text under root holding the old gem glyph
function G.glyphs(root)
	local out = {}
	for _, d in ipairs(root and root:GetDescendants() or {}) do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and tostring(d.Text):find(GLYPH, 1, true) and G.shown(d) then
			out[#out + 1] = d.Name
		end
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- client_egg_art
----------------------------------------------------------------------------------------------------
S.client_egg_art = guarded("client_egg_art", function()
	local KC = G.KC()
	local Config = KC.env()
	local EA = G.req("client/UI/EggArt")
	if not T.check(type(EA) == "table" and type(EA.New) == "function" and type(EA.SetRarity) == "function" and type(EA.Halves) == "function"
		and type(EA.Glow) == "function" and type(EA.Tones) == "function" and type(EA.Paint) == "function",
		"egg art: client/UI/EggArt loads (New, SetRarity, Halves, Glow, Tones, Paint)") then
		return
	end
	local oldVp = { Mock.Viewport.X, Mock.Viewport.Y }
	Mock.SetViewport(1920, 1080)
	G.advance(0.2)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SmokeEggs"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = G.pg()
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)

	-- Glow and Tones
	for _, rarity in ipairs(RARITIES) do
		T.check(abs((EA.Glow(rarity) or -1) - GLOW[rarity]) < 1e-9, "egg art: Glow(" .. rarity .. ") = " .. GLOW[rarity], tostring(EA.Glow(rarity)))
		local top, bottom = EA.Tones(rarity)
		local c = G.rarityColor(Config, rarity)
		if rarity == "Secret" then
			T.check(G.rgb(top, 74, 68, 104) and G.rgb(bottom, 18, 16, 28), "egg art: Tones(Secret) = rgb(74,68,104) / rgb(18,16,28)")
		else
			T.check(G.same(top, c:Lerp(WHITE, 0.38)) and G.same(bottom, c:Lerp(BLACK, 0.28)), "egg art: Tones(" .. rarity .. ") = the colour 38% toward white / 28% toward black")
		end
		T.check(type(EA.Paint(rarity)) == "table", "egg art: Paint(" .. rarity .. ") is a table (the motif list; empty until Task 26)")
	end

	-- the seven eggs at five sizes
	local CAP = { Simple = 8, Medium = 14, Full = 28 }
	local bad = T.tally("egg art: every egg at 30 / 64 / 104 / 160 / 380 px is the oval body with its tone, outline and highlight", 4)
	local caps = T.tally("egg art: the instance caps 8 / 14 / 28 by form", 4)
	for _, rarity in ipairs(RARITIES) do
		for _, size in ipairs({ 30, 64, 104, 160, 380 }) do
			local egg = EA.New(root, rarity, size)
			local label = rarity .. " " .. size
			local form = size < 48 and "Simple" or (size <= 140 and "Medium" or "Full")
			local ok = egg ~= nil and egg:IsA("Frame") and egg.Name == "Egg_" .. rarity and egg.Parent == root
			ok = ok and egg.Size.X.Offset == math.floor(0.8 * size + 0.5) and egg.Size.Y.Offset == size and egg.Size.X.Scale == 0
			local corner = egg and egg:FindFirstChildOfClass("UICorner")
			ok = ok and corner ~= nil and corner.CornerRadius.Scale == 0.5
			local tone = egg and egg:FindFirstChild("Tone")
			local top, bottom = EA.Tones(rarity)
			local kps = tone and tone:IsA("UIGradient") and tone.Color.Keypoints or {}
			ok = ok and #kps >= 2 and G.same(kps[1].Value, top) and G.same(kps[#kps].Value, bottom) and tone.Rotation == 90
			local outline = egg and egg:FindFirstChild("Outline")
			local th = outline and outline:IsA("UIStroke") and outline.Thickness or -1
			ok = ok and G.rgb(outline and outline.Color, 11, 16, 48) and th == math.max(2, math.floor(size / 20 + 0.5)) and th == math.floor(th)
			local hl = egg and egg:FindFirstChild("Highlight")
			ok = ok and hl ~= nil and hl:IsA("Frame") and G.rgb(hl.BackgroundColor3, 255, 255, 255)
			ok = ok and egg:GetAttribute("Form") == form and egg:GetAttribute("Rarity") == rarity
			bad:case(ok, label .. (egg and fmt(" (%s, %dx%d, outline %s, form %s)", egg.Name, egg.Size.X.Offset, egg.Size.Y.Offset, tostring(th), tostring(egg:GetAttribute("Form"))) or " (nil)"))
			if egg then
				local n = #egg:GetDescendants() + 1
				caps:case(n <= CAP[form], fmt("%s: %d instances (%s cap %d)", label, n, form, CAP[form]))
			end
		end
	end
	bad:report()
	caps:report()
	local named = EA.New(root, "Rare", 104, { Name = "Egg1", ZIndex = 6, Form = "Simple" })
	T.check(named.Name == "Egg1" and named.ZIndex == 6 and named:GetAttribute("Form") == "Simple", "egg art: opts Name, ZIndex and Form")

	-- SetRarity: re-skins in place
	local egg = EA.New(root, "Common", 104)
	local before = #egg:GetDescendants()
	EA.SetRarity(egg, "Mythic")
	local top, bottom = EA.Tones("Mythic")
	local kps = egg:FindFirstChild("Tone").Color.Keypoints
	T.check(#egg:GetDescendants() == before and egg.Name == "Egg_Mythic" and egg:GetAttribute("Rarity") == "Mythic" and G.same(kps[1].Value, top) and G.same(kps[#kps].Value, bottom),
		"egg art: SetRarity re-skins in place (same instance count, the Mythic tones, the name and attribute follow)", fmt("%d -> %d, %s", before, #egg:GetDescendants(), egg.Name))
	EA.SetRarity(named, "Epic")
	T.check(named.Name == "Egg1" and named:GetAttribute("Rarity") == "Epic", "egg art: SetRarity keeps a custom name")

	-- Halves
	local holder = Instance.new("Frame")
	holder.Name = "HalvesHolder"
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromOffset(400, 200)
	holder.Size = UDim2.fromOffset(160, 200)
	holder.Parent = root
	local topH, botH = EA.Halves(holder, "Legendary", 200)
	local okH = topH ~= nil and botH ~= nil and topH:IsA("CanvasGroup") and botH:IsA("CanvasGroup") and topH.Parent == holder and botH.Parent == holder
	T.check(okH, "egg art: Halves returns two CanvasGroups in the parent")
	if okH then
		local a, b = G.box(topH), G.box(botH)
		T.check(abs(a.y - 200) < 0.6 and abs(b.y + b.h - 400) < 0.6 and a.h + b.h >= 200 - 0.6 and abs(a.w - 160) < 0.6 and abs(b.w - 160) < 0.6 and b.y >= a.y,
			"egg art: the halves cover the egg's height (top from the egg's top, bottom to its bottom, the egg's width)", fmt("top %d..%d, bottom %d..%d, w %d / %d", a.y, a.y + a.h, b.y, b.y + b.h, a.w, b.w))
		local eggTop, eggBot = topH:FindFirstChildWhichIsA("Frame"), botH:FindFirstChildWhichIsA("Frame")
		T.check(eggTop ~= nil and eggBot ~= nil and eggTop:GetAttribute("Rarity") == "Legendary" and eggBot:GetAttribute("Rarity") == "Legendary"
			and abs(eggBot.AbsolutePosition.Y - 200) < 0.6 and abs(eggTop.AbsolutePosition.Y - 200) < 0.6,
			"egg art: each half draws the whole egg, clipped (the bottom half's egg sits at the egg's top)")
	end

	gui:Destroy()
	Mock.SetViewport(oldVp[1], oldVp[2])
	G.advance(0.3)
	KC.flushErrors("client_egg_art")
end)

----------------------------------------------------------------------------------------------------
-- client_egg_stage
----------------------------------------------------------------------------------------------------
S.client_egg_stage = guarded("client_egg_stage", function()
	local KC = G.KC()
	local Config = KC.env()
	local ES = G.req("client/UI/EggStage")
	local EA = G.req("client/UI/EggArt")
	local PC = G.req("shared/PetCatalog")
	local SF = G.req("client/SoundFx")
	local CS = G.req("client/ClientSettings")
	local MC = KC.M.MenuController or G.req("client/Controllers/MenuController")
	local okMod = type(ES) == "table"
	for _, fn in ipairs({ "Init", "Show", "Request", "IsPending", "IsShowing", "Phase", "Skip", "Back", "Done", "Close", "Timings", "NoteText", "Layout", "IsPrewarmed", "Stats", "_Answer" }) do
		okMod = okMod and type(ES[fn]) == "function"
	end
	for _, sig in ipairs({ "Pending", "Answered", "Opened", "Closed" }) do
		okMod = okMod and type(ES[sig]) == "table" and type(ES[sig].Connect) == "function"
	end
	if not T.check(okMod and type(EA) == "table", "egg stage: client/UI/EggStage loads (the API of spec 16.4 + the _Answer listener body, the four signals)") then
		return
	end
	if not T.check(type(SF) == "table" and type(CS) == "table" and type(MC) == "table" and type(PC) == "table", "egg stage: SoundFx, ClientSettings, MenuController, PetCatalog load") then
		return
	end
	local IN_MATCH = Config.Attr.InMatch
	local oldVp = { Mock.Viewport.X, Mock.Viewport.Y }
	Mock.SetViewport(1920, 1080)
	-- the pets
	local epicPool, legPool, rarePool = PC.RarityPool("Cloud", "Epic"), PC.RarityPool("Storm", "Legendary"), PC.RarityPool("Cloud", "Rare")
	local mythPool = PC.RarityPool("Secret", "Mythic")
	if not T.check(#epicPool >= 1 and #legPool >= 1 and #rarePool >= 1 and #mythPool >= 1, "egg stage: the Cloud Epic / Rare, Storm Legendary and Secret Mythic pools have pets") then
		return
	end
	local epic, leg, rare, myth = epicPool[1], legPool[1], rarePool[1], mythPool[1]
	-- a profile: tokens, gems, the epic pet evolved (stage 1) for the ribbon; gem roulettes allowed (the policy attribute)
	local oldTokens, oldPolicy = LocalPlayer:GetAttribute(Config.Attr.Tokens), LocalPlayer:GetAttribute("PaidRandomItemsRestricted")
	LocalPlayer:SetAttribute(Config.Attr.Gems, 5000)
	LocalPlayer:SetAttribute(Config.Attr.Tokens, 50000)
	LocalPlayer:SetAttribute("PaidRandomItemsRestricted", false)
	KC.toClient("ProfileSync", {
		Tokens = 50000, Pets = { [epic.Id] = 1, [rare.Id] = 1 }, Equipped = {}, Items = {}, Discovered = { [epic.Id] = 1 }, IndexClaimed = {},
		Stats = { Matches = 3, Wins = 1, TokensEarned = 40, Spins = 2, BestTimes = {} },
		Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
		Tutorial = { Step = 99, Done = true, Gifted = true }, Cash = 100, Gems = 5000, Berries = 0,
		PetLevels = { [epic.Id] = { Level = 60, Xp = 0 } }, PetGrowth = { [epic.Id] = { Evo = 1 } },
		Teams = { Presets = { {}, {}, {} }, Active = 1, Slots = 3 },
	})
	G.advance(0.5)
	CS.Set("FastHatch", false)
	G.advance(0.5)
	-- spies
	local sounds = {}
	local realPlay = SF.Play
	SF.Play = function(name, opts)
		sounds[#sounds + 1] = { name = name, scale = opts and opts.Scale }
		return nil
	end
	local hints = {}
	local realHint = MC.Hint
	MC.Hint = function(text, kind)
		hints[#hints + 1] = tostring(text)
	end
	local closed = {}
	local closedConn = ES.Closed:Connect(function(reason)
		closed[#closed + 1] = reason
	end)
	local function lastClosed()
		return closed[#closed]
	end
	local function soundsFrom(i)
		local out = {}
		for k = i + 1, #sounds do
			out[#out + 1] = sounds[k]
		end
		return out
	end
	local function hasSound(list, name, scale)
		for _, s in ipairs(list) do
			if s.name == name and (scale == nil or (s.scale ~= nil and abs(s.scale - scale) < 1e-9)) then
				return true
			end
		end
		return false
	end
	local function ensureClosed()
		if ES.IsShowing() then
			ES.Close()
			G.advance(0.1)
		end
	end
	local ok, err = pcall(function()
		------------------------------------------------------------------ pure parts
		local t1, f1 = ES.Timings(false, 1), ES.Timings(true, 1)
		local t3, f3 = ES.Timings(false, 3), ES.Timings(true, 3)
		local function near(a, b)
			return type(a) == "number" and abs(a - b) < 1e-6
		end
		T.check(near(t1.Intro, 0.35) and near(t1.Strip, 3.0) and near(t1.Land, 0.35) and near(t1.Rise, 0.5) and near(t1.Crack, 1.2) and near(t1.Burst, 0.35) and near(t1.RevealAt, 5.75),
			"egg stage: Timings(false, 1) = Intro 0.35, Strip 3, Land 0.35, Rise 0.5, Crack 1.2, Burst 0.35, RevealAt 5.75")
		T.check(near(f1.Intro, 0.15) and near(f1.Strip, 0.8) and near(f1.Land, 0.12) and near(f1.Rise, 0.2) and near(f1.Crack, 0.4) and near(f1.Burst, 0.25) and near(f1.RevealAt, 1.92),
			"egg stage: Timings(true, 1) = 0.15, 0.8, 0.12, 0.2, 0.4, 0.25, RevealAt 1.92")
		T.check(near(t3.Stagger, 0.6) and near(t3.Crack, 0.9) and near(t3.RevealAt, 7.15) and near(f3.Stagger, 0.25) and near(f3.Crack, 0.4) and near(f3.RevealAt, 2.66),
			"egg stage: x3 Stagger 0.6 (fast 0.25), Crack 0.9 (0.4), RevealAt 7.15 (2.66)", fmt("%s %s %s / %s %s %s", tostring(t3.Stagger), tostring(t3.Crack), tostring(t3.RevealAt), tostring(f3.Stagger), tostring(f3.Crack), tostring(f3.RevealAt)))
		T.eq(ES.Layout(), "PC", "egg stage: Layout() at 1920x1080 is PC")
		T.eq(ES.NoteText({ PoolSize = 3, IsNew = true, PetId = epic.Id }, "Epic"), "1 of 3 Epic pets " .. DOT .. " added to your pets", "egg stage: NoteText for a new pet")
		T.eq(ES.NoteText({ PoolSize = 3, IsNew = false, Count = 2, PetId = epic.Id }, "Epic"), "1 of 3 Epic pets " .. DOT .. " you have 2 " .. epic.Name .. " now", "egg stage: NoteText names the pet when it is not new")
		T.eq(ES.NoteText({ PoolSize = 3, IsNew = false, Count = 99, PetId = epic.Id, Substitute = { Tokens = 800 } }, "Epic"), "Stack full: +800 Tokens instead", "egg stage: NoteText for a substitute")
		local pityNote = ES.NoteText({ PoolSize = 4, IsNew = true, PetId = epic.Id, Pity = true }, "Secret")
		T.check(pityNote:sub(-#(" " .. DOT .. " guaranteed")) == " " .. DOT .. " guaranteed", "egg stage: a pity pull's note ends ' \194\183 guaranteed'", pityNote)
		T.check(ES.IsShowing() == false and ES.Phase() == nil and ES.IsPending() == false, "egg stage: idle before any roll")
		G.zeroStats(ES, "egg stage idle")

		------------------------------------------------------------------ x1 Epic, normal timings
		local before = G.snapshot()
		local s0 = #sounds
		local okShow = ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) }))
		local gui = G.gui()
		T.check(okShow == true and ES.IsShowing() and ES.Phase() == "Intro", "egg stage: Show(result) opens the stage at Intro", tostring(okShow) .. " " .. tostring(ES.Phase()))
		T.check(gui ~= nil and gui:IsA("ScreenGui") and gui.DisplayOrder == 25 and gui.IgnoreGuiInset == true and gui.ResetOnSpawn == false,
			"egg stage: NimbusHatch is a ScreenGui at DisplayOrder 25, IgnoreGuiInset, not reset on spawn")
		local skip = G.bar("Skip")
		T.check(skip ~= nil and skip:IsA("GuiButton") and G.shown(skip) and G.shown(G.bar("FastHatch")), "egg stage: Skip and Fast hatch are shown on the first frame")
		local stageRoot = gui and gui:FindFirstChild("Stage")
		T.check(stageRoot ~= nil and stageRoot:FindFirstChild("Dim") ~= nil and stageRoot:FindFirstChild("Content") ~= nil and stageRoot:FindFirstChild("Flash") ~= nil and stageRoot:FindFirstChild("Vignette") ~= nil,
			"egg stage: NimbusHatch > Stage > Dim, Vignette, Content, Flash")
		local bound = Mock.BoundActions.NimbusHatchBack
		local dash = Mock.BoundActions.NimbusDash
		local high, default = Enum.ContextActionPriority.High.Value, Enum.ContextActionPriority.Default.Value
		T.check(bound ~= nil and bound.priority == high + 1, "egg stage: gamepad B is 'NimbusHatchBack' at High + 1 while the stage shows", bound and tostring(bound.priority) or "not bound")
		T.check(dash == nil or dash.priority == high or dash.priority == default, "egg stage: ...above NimbusDash (bound at High or Default)", dash and tostring(dash.priority) or "no dash")
		local crackText = nil
		local run = G.run(ES, 7, function(_, ph)
			if ph == "Crack" and crackText == nil then
				local cw = G.hero("CrackWord")
				crackText = cw and G.shown(cw) and cw.Text or nil
			end
		end)
		T.eq(table.concat(run.order, " "), "Intro Strip Land Rise Crack Burst Reveal", "egg stage: x1 runs the seven phases in order")
		T.check(run.at.Reveal ~= nil and abs(run.at.Reveal - 5.75) <= 0.1, "egg stage: x1 Reveal at 5.75 +- 0.1 s", tostring(run.at.Reveal))
		T.eq(crackText, "EPIC EGG!", "egg stage: CrackWord reads 'EPIC EGG!'")
		T.check(run.maxCells >= 6 and run.maxCells <= 12, "egg stage: a 40-cell strip never holds more than 12 Cell frames", tostring(run.maxCells))
		T.check(run.maxInst > 0 and run.maxInst <= 450, "egg stage: x1 Stats().Instances <= 450 at every phase", tostring(run.maxInst))
		G.advance(0.5)
		local word = G.colPart(1, "Word")
		local note = G.colPart(1, "Note")
		local nameL = G.colPart(1, "Name")
		local newL = G.colPart(1, "New")
		T.eq(word and word.Text, "EPIC!", "egg stage: the reveal Word reads 'EPIC!'")
		T.eq(note and note.Text, "1 of " .. #epicPool .. " Epic pets " .. DOT .. " added to your pets", "egg stage: the reveal note (new)")
		T.eq(nameL and nameL.Text, epic.Name, "egg stage: the reveal names the pet")
		T.check(G.shown(newL), "egg stage: NEW! shows for a new pet")
		T.check(G.colPart(2) == nil, "egg stage: x1 has one column")
		T.check(G.shown(G.bar("SpinAgain")) and G.shown(G.bar("Done")), "egg stage: SPIN AGAIN and DONE on the reveal")
		T.check(ES.Stats().Instances <= 450, "egg stage: x1 reveal within 450 instances", tostring(ES.Stats().Instances))
		RedoGeom.check(G.content(), "egg stage 1920x1080 x1 reveal", { MinText = 18, NoOverlap = { "Banner", "Pedestal1", "Name", "Note", "SpinAgain", "Done", "Skip", "FastHatch" }, Skip = { Rays = true, Flash = true, Vignette = true } })
		local epicSounds = soundsFrom(s0)
		for _, name in ipairs({ "SpinStart", "SpinTick", "SpinLand", "Shatter", "RevealRare" }) do
			T.check(hasSound(epicSounds, name, 0.6), "egg stage: an Epic roll plays " .. name .. " at Scale 0.6")
		end
		local loud = 0
		for _, s in ipairs(epicSounds) do
			if s.scale == nil or s.scale > 0.6 then
				loud = loud + 1
			end
		end
		T.eq(loud, 0, "egg stage: every sound of an Epic roll plays at Scale 0.6")
		T.eq(#G.glyphs(gui), 0, "egg stage: no gem glyph text in NimbusHatch")
		-- gamepad B on the reveal is DONE
		local res = Mock.TriggerAction("NimbusHatchBack", "Begin")
		G.advance(STEP)
		T.check(res == Enum.ContextActionResult.Sink, "egg stage: B returns Sink")
		T.check(ES.IsShowing() == false and lastClosed() == "Done", "egg stage: B on the reveal is DONE (Closed 'Done')", tostring(lastClosed()))
		T.check(Mock.BoundActions.NimbusHatchBack == nil, "egg stage: NimbusHatchBack is unbound once the stage is gone")
		G.zeroStats(ES, "egg stage after DONE")
		local same, why = G.sameSnapshot(before, G.snapshot())
		T.check(same, "egg stage: the Camera (type, subject, field of view), the Humanoid (walk, jump) and the touch controls are as before the roll", why)

		------------------------------------------------------------------ Skip at t = 0, the notes
		local function quickReveal(result, label)
			ES.Show(result)
			ES.Skip()
			G.advance(STEP)
			T.eq(ES.Phase(), "Reveal", "egg stage: " .. label .. ": Skip() at t = 0 -> Reveal on the next frame")
			G.advance(0.4)
		end
		quickReveal(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic, { IsNew = false, Count = 2 }) }), "not new")
		T.eq((G.colPart(1, "Note") or {}).Text, "1 of " .. #epicPool .. " Epic pets " .. DOT .. " you have 2 " .. epic.Name .. " now", "egg stage: the note names the pet (not new)")
		T.check(not G.shown(G.colPart(1, "New")), "egg stage: no NEW! for a pet you had")
		ES.Back()
		G.advance(STEP)
		T.check(lastClosed() == "Done" and not ES.IsShowing(), "egg stage: Back() on the reveal is DONE")
		quickReveal(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic, { IsNew = false, Count = 99, Substitute = { Tokens = 800 } }) }), "substitute")
		T.eq((G.colPart(1, "Note") or {}).Text, "Stack full: +800 Tokens instead", "egg stage: a substitute's note")
		ES.Done()
		G.advance(STEP)
		local secretPool = PC.RarityPool("Secret", "Secret")
		if #secretPool > 0 then
			quickReveal(G.result("Secret", "Gems", { G.pull(PC, "Secret", secretPool[1], { Pity = true }) }), "pity")
			local pn = (G.colPart(1, "Note") or {}).Text or ""
			T.check(pn:sub(-#(" " .. DOT .. " guaranteed")) == " " .. DOT .. " guaranteed", "egg stage: a pity Secret's note ends ' \194\183 guaranteed'", pn)
			T.eq(#G.glyphs(G.gui()), 0, "egg stage: a Gems reveal (SPIN AGAIN with the gem price) shows no gem glyph")
			local again = G.bar("SpinAgain")
			T.check(again ~= nil and again:FindFirstChild("GemIcon", true) ~= nil, "egg stage: a Gems SPIN AGAIN draws its price with a GemIcon")
			ES.Done()
			G.advance(STEP)
		end

		------------------------------------------------------------------ Back / B during Strip skip; Esc does nothing
		ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) }))
		G.advance(1.0)
		T.eq(ES.Phase(), "Strip", "egg stage: at 1 s the strip runs")
		ES.Back()
		G.advance(STEP)
		T.eq(ES.Phase(), "Reveal", "egg stage: Back() during Strip skips to the reveal")
		ES.Back()
		G.advance(STEP)
		T.check(lastClosed() == "Done" and not ES.IsShowing(), "egg stage: ...then Back() is DONE")
		ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) }))
		G.advance(1.0)
		local resB = Mock.TriggerAction("NimbusHatchBack", "Begin")
		G.advance(STEP)
		T.check(resB == Enum.ContextActionResult.Sink and ES.Phase() == "Reveal", "egg stage: B during Strip skips (Sink)", tostring(ES.Phase()))
		Mock.TriggerAction("NimbusHatchBack", "Begin")
		G.advance(STEP)
		T.check(lastClosed() == "Done" and not ES.IsShowing(), "egg stage: ...and B on the reveal is DONE")
		ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) }))
		G.advance(0.8)
		local UIS = game:GetService("UserInputService")
		Mock.FireSignal(UIS, "InputBegan", Mock.NewInput("Escape", "Keyboard", "Begin"), false)
		G.advance(STEP)
		T.check(ES.IsShowing() and ES.Phase() == "Strip", "egg stage: an Esc InputBegan with only the stage alive changes nothing (no Esc handler in EggStage)", tostring(ES.Phase()))
		local h0 = #hints
		ES.Close()
		G.advance(STEP)
		T.check(lastClosed() == "Close" and not ES.IsShowing(), "egg stage: Close() closes the stage (Closed 'Close')")
		T.check(#hints == h0 + 1 and hints[#hints] == "You hatched: " .. epic.Name, "egg stage: Close() toasts the pull not shown yet", hints[#hints])
		G.zeroStats(ES, "egg stage after Close")

		------------------------------------------------------------------ the character removed mid-Strip
		ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) }))
		G.advance(1.2)
		Mock.Respawn(LocalPlayer)
		local runR = G.run(ES, 6)
		T.check(runR.at.Reveal ~= nil, "egg stage: the character removed mid-Strip (a new one added): the roll still reaches the reveal")
		ES.Done()
		G.advance(0.5)

		------------------------------------------------------------------ Fast hatch: the toggle, then the fast timings
		local calls0 = #KC.serverCalls("SettingsSet")
		ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) }))
		local tStart = os.clock()
		Mock.Click(G.bar("FastHatch"))
		G.advance(0.2)
		T.eq(#KC.serverCalls("SettingsSet") - calls0, 0, "egg stage: the Fast hatch toggle sends nothing at once")
		G.advance(0.3)
		local sets = KC.serverCalls("SettingsSet")
		local last = sets[#sets]
		T.check(#sets - calls0 == 1 and last.args[1] == "FastHatch" and last.args[2] == true, "egg stage: ...then one SettingsSet('FastHatch', true) 0.4 s later",
			(#sets - calls0) .. " calls")
		T.check(CS.Get("FastHatch") == true, "egg stage: ClientSettings FastHatch is on")
		G.run(ES, 7)
		T.check(ES.Phase() == "Reveal" and abs((os.clock() - tStart) - 5.75) <= 0.1, "egg stage: the roll that was playing keeps its timings (its reveal still at 5.75 s)",
			fmt("%s at %.2f s", tostring(ES.Phase()), os.clock() - tStart))
		ES.Done()
		G.advance(0.2)
		ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) }))
		local runFast = G.run(ES, 4)
		T.check(runFast.at.Reveal ~= nil and abs(runFast.at.Reveal - 1.92) <= 0.1, "egg stage: Fast hatch -> x1 Reveal at 1.92 +- 0.1", tostring(runFast.at.Reveal))
		ES.Done()
		G.advance(0.2)
		ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic), G.pull(PC, "Cloud", rare), G.pull(PC, "Cloud", epic) }))
		local runFast3 = G.run(ES, 5)
		T.check(runFast3.at.Reveal ~= nil and abs(runFast3.at.Reveal - 2.66) <= 0.1, "egg stage: Fast hatch -> x3 Reveal at 2.66 +- 0.1", tostring(runFast3.at.Reveal))
		ES.Done()
		G.advance(0.2)
		CS.Set("FastHatch", false)
		G.advance(0.5)

		------------------------------------------------------------------ x3, normal timings: pull order, landings, three columns
		local s3 = #sounds
		local pulls3 = { G.pull(PC, "Storm", rare), G.pull(PC, "Storm", leg), G.pull(PC, "Storm", epic, { Key = epic.Id }) }
		ES.Show(G.result("Storm", "Tokens", pulls3))
		local landed, cracked = {}, {}
		local run3 = G.run(ES, 9, function(t)
			local content = G.content()
			local strips = content and content:FindFirstChild("Strips")
			for j = 1, 3 do
				local st = strips and strips:FindFirstChild("Strip" .. j)
				if st and st:GetAttribute("Landed") == true and landed[j] == nil then
					landed[j] = t
				end
				local egg = G.hero("Egg" .. j)
				if egg and egg:GetAttribute("State") == "Crack" and cracked[j] == nil then
					cracked[j] = t
				end
			end
		end)
		T.eq(table.concat(run3.order, " "), "Intro Strip Land Rise Crack Burst Reveal", "egg stage: x3 runs the seven phases in order")
		T.check(run3.at.Reveal ~= nil and abs(run3.at.Reveal - 7.15) <= 0.1, "egg stage: x3 Reveal at 7.15 +- 0.1 s", tostring(run3.at.Reveal))
		T.check(landed[1] and landed[2] and landed[3] and abs(landed[2] - landed[1] - 0.25) <= 0.07 and abs(landed[3] - landed[2] - 0.25) <= 0.07,
			"egg stage: x3 strips land 0.25 s apart", fmt("%s %s %s", tostring(landed[1]), tostring(landed[2]), tostring(landed[3])))
		T.check(cracked[1] and cracked[2] and cracked[3] and cracked[1] < cracked[2] and cracked[2] < cracked[3] and abs(cracked[2] - cracked[1] - 0.6) <= 0.07 and abs(cracked[3] - cracked[2] - 0.6) <= 0.07,
			"egg stage: x3 eggs crack in pull order, 0.6 s apart", fmt("%s %s %s", tostring(cracked[1]), tostring(cracked[2]), tostring(cracked[3])))
		T.check(run3.maxCells <= 12, "egg stage: x3 strips hold at most 12 Cell frames each", tostring(run3.maxCells))
		T.check(run3.maxInst > 0 and run3.maxInst <= 750, "egg stage: x3 Stats().Instances <= 750 at every phase", tostring(run3.maxInst))
		G.advance(0.5)
		local cols = 0
		for j = 1, 3 do
			local col = G.colPart(j)
			if col and G.shown(col) and G.colPart(j, "Note") and G.colPart(j, "Name") then
				cols = cols + 1
			end
		end
		T.eq(cols, 3, "egg stage: x3 reveal shows three columns (name and note each)")
		T.eq((G.colPart(2, "Word") or {}).Text, "LEGENDARY!", "egg stage: column 2 is pull 2 (the server's order, never re-sorted)")
		T.check(G.shown(G.colPart(3, "EvolvedRibbon")) and not G.shown(G.colPart(1, "EvolvedRibbon")), "egg stage: an evolved key's x3 column shows the EvolvedRibbon (only that column)")
		local rev3 = 0
		local list3 = soundsFrom(s3)
		for _, s in ipairs(list3) do
			if s.name:match("^Reveal") then
				rev3 = rev3 + 1
			end
		end
		T.check(rev3 == 1 and hasSound(list3, "RevealLegendary", 1), "egg stage: x3 plays one reveal sound, the best pull's (RevealLegendary at 1)")
		T.check(ES.Stats().Instances <= 750, "egg stage: x3 reveal within 750 instances", tostring(ES.Stats().Instances))
		ES.Done()
		G.advance(0.3)
		G.zeroStats(ES, "egg stage after the x3 DONE")

		------------------------------------------------------------------ Legendary x1: the loud reveal; an evolved x1
		local sL = #sounds
		ES.Show(G.result("Storm", "Tokens", { G.pull(PC, "Storm", leg) }))
		G.run(ES, 7)
		local listL = soundsFrom(sL)
		T.check(hasSound(listL, "RevealLegendary", 1), "egg stage: a Legendary roll plays RevealLegendary at Scale 1")
		T.check(hasSound(listL, "SpinStart", 0.6) and not hasSound(listL, "SpinStart", 1), "egg stage: ...but the strip's start stays at 0.6 (no tell before the landing)")
		ES.Done()
		G.advance(0.2)
		quickReveal(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic, { Key = epic.Id }) }), "evolved")
		local ribbon = G.colPart(1, "EvolvedRibbon")
		T.check(G.shown(ribbon), "egg stage: an evolved key gets the EvolvedRibbon on the x1 reveal")
		local pet = G.colPart(1, "Pet")
		T.check(pet ~= nil and pet:FindFirstChildWhichIsA("ViewportFrame", true) ~= nil, "egg stage: ...over the pet's viewport")
		T.check(ES.IsPrewarmed(epic.Id) == true, "egg stage: IsPrewarmed(petId) after its roll")
		ES.Done()
		G.advance(0.2)

		------------------------------------------------------------------ old-shape results; a pull without a Strip
		ES.Show({ Ok = true, PetId = epic.Id, IsNew = false, Count = 2 })
		local runOld = G.run(ES, 5)
		T.eq(table.concat(runOld.order, " "), "Intro Rise Crack Burst Reveal", "egg stage: an old-shape result without a Strip plays as one pull, starting at Rise")
		G.advance(0.4)
		T.check(G.colPart(1) ~= nil and G.colPart(2) == nil and (G.colPart(1, "Name") or {}).Text == epic.Name, "egg stage: ...one column, the pet named")
		ES.Done()
		G.advance(0.2)
		ES.Show({ Ok = true, PetId = epic.Id, IsNew = true, Count = 1, Strip = G.strip(PC, "Cloud", epic.Id), RouletteId = "Cloud" })
		local runOldS = G.run(ES, 7)
		T.eq(table.concat(runOldS.order, " "), "Intro Strip Land Rise Crack Burst Reveal", "egg stage: an old-shape result with a Strip plays the strip")
		ES.Done()
		G.advance(0.2)
		ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic, { Strip = false }) }))
		local runNoStrip = G.run(ES, 5)
		T.eq(table.concat(runNoStrip.order, " "), "Intro Rise Crack Burst Reveal", "egg stage: a pull with no Strip starts at Rise")
		ES.Done()
		G.advance(0.2)

		------------------------------------------------------------------ the request path
		local b0 = #KC.serverCalls("BuyRoulette")
		T.check(ES.Request("Cloud", "Tokens", 1) == true and ES.IsPending(), "egg stage: Request sends and holds the pending flag")
		local buys = KC.serverCalls("BuyRoulette")
		local lb = buys[#buys]
		T.check(#buys - b0 == 1 and lb.args[1] == "Cloud" and lb.args[2] == "Tokens" and lb.args[3] == 1, "egg stage: ...one BuyRoulette('Cloud', 'Tokens', 1)")
		T.check(ES.Request("Cloud", "Tokens", 1) == false and #KC.serverCalls("BuyRoulette") - b0 == 1, "egg stage: two Requests within 0.3 s -> one fire")
		local h1 = #hints
		ES._Answer({ Ok = false, Reason = "You need more Cloud Tokens.", RouletteId = "Cloud", Currency = "Tokens", Spins = 1 })
		T.check(ES.IsPending() == false and not ES.IsShowing(), "egg stage: a failure answer clears the pending flag at once and never opens the stage")
		T.check(#hints == h1 + 1 and hints[#hints] == "You need more Cloud Tokens.", "egg stage: ...with one toast of the reason", tostring(hints[#hints]))
		T.check(ES.Request("Cloud", "Tokens", 1) == false, "egg stage: a Request within 0.3 s of the last send is refused (FIRE_GAP)")
		G.advance(0.35)
		local h2 = #hints
		T.check(ES.Request("Cloud", "Tokens", 1) == true and #KC.serverCalls("BuyRoulette") - b0 == 2, "egg stage: ...and sends after 0.3 s")
		G.advance(7.2)
		T.check(ES.IsPending() == false and #hints == h2 + 1 and hints[#hints] == "The roulette did not answer. Try again.", "egg stage: 7 s without an answer -> not pending, one toast",
			tostring(hints[#hints]))
		ES._Answer(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) }))
		T.check(ES.IsShowing(), "egg stage: a success after the timeout still plays")
		-- the queue: a result during a roll waits for DONE
		G.advance(1)
		local c0 = #closed
		ES._Answer(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", rare) }))
		T.eq(ES.Phase(), "Strip", "egg stage: a result during a roll waits (the roll goes on)")
		ES.Skip()
		G.advance(0.4)
		T.eq((G.colPart(1, "Name") or {}).Text, epic.Name, "egg stage: ...the first roll reveals first")
		ES.Done()
		G.advance(STEP)
		T.check(ES.IsShowing() and ES.Phase() == "Intro" and #closed == c0, "egg stage: ...DONE plays the waiting result in place (no Closed between)", tostring(ES.Phase()))
		ES.Skip()
		G.advance(0.4)
		T.eq((G.colPart(1, "Name") or {}).Text, rare.Name, "egg stage: ...the queued pull is revealed")
		-- SPIN AGAIN: a new paid request through Request; the reveal stays up until the answer
		G.advance(0.4)
		local b1 = #KC.serverCalls("BuyRoulette")
		local againBtn = G.bar("SpinAgain")
		T.check(againBtn ~= nil and againBtn.Active ~= false and againBtn:GetAttribute("Disabled") ~= true, "egg stage: SPIN AGAIN is enabled (tokens enough)")
		Mock.Click(againBtn)
		local ab = KC.serverCalls("BuyRoulette")
		T.check(#ab - b1 == 1 and ab[#ab].args[1] == "Cloud" and ab[#ab].args[2] == "Tokens" and ab[#ab].args[3] == 1, "egg stage: SPIN AGAIN -> one BuyRoulette(id, currency, spins) through Request")
		Mock.Click(againBtn)
		T.eq(#KC.serverCalls("BuyRoulette") - b1, 1, "egg stage: a second SPIN AGAIN tap while pending sends nothing")
		T.check(ES.IsPending() and ES.Phase() == "Reveal", "egg stage: ...the reveal stays up while the answer is pending")
		local c1 = #closed
		ES._Answer(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) }))
		T.check(ES.Phase() == "Intro" and #closed == c1 and not ES.IsPending(), "egg stage: SPIN AGAIN's answer plays the next roll in place")
		ES.Close()
		G.advance(0.2)
		-- Init: the RouletteResult listener (a failure probe: MenuController's old stage never opens on a failure)
		ES.Init()
		ES.Init()
		local h3 = #hints
		KC.toClient("RouletteResult", { Ok = false, Reason = "Probe reason", RouletteId = "Cloud", Currency = "Tokens", Spins = 1 })
		G.advance(0.1)
		local probes = 0
		for k = h3 + 1, #hints do
			if hints[k] == "Probe reason" then
				probes = probes + 1
			end
		end
		T.eq(probes, 1, "egg stage: Init connects the RouletteResult listener once (Init twice, one toast)")

		------------------------------------------------------------------ a match start; Close mid-Crack; a phase error
		local beforeM = G.snapshot()
		ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) }))
		G.advance(1)
		local hm = #hints
		LocalPlayer:SetAttribute(IN_MATCH, true)
		G.advance(STEP)
		T.check(not ES.IsShowing() and lastClosed() == "Match", "egg stage: a match start closes the stage (Closed 'Match')", tostring(lastClosed()))
		T.check(#hints == hm + 1 and hints[#hints] == "You hatched: " .. epic.Name, "egg stage: ...and toasts the pull not shown", tostring(hints[#hints]))
		local hr = #hints
		T.check(ES.Request("Cloud", "Tokens", 1) == false and hints[hr + 1] == "The shop is closed during a match.", "egg stage: Request in a match is refused with a toast")
		LocalPlayer:SetAttribute(IN_MATCH, nil)
		G.advance(0.4)
		G.zeroStats(ES, "egg stage after the match start")
		local okM, whyM = G.sameSnapshot(beforeM, G.snapshot())
		T.check(okM, "egg stage: after the match start the Camera, Humanoid and touch controls are as before", whyM)
		local beforeC = G.snapshot()
		local t0c = os.clock()
		ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic), G.pull(PC, "Cloud", rare), G.pull(PC, "Cloud", epic) }))
		G.until_(t0c, 5.2)
		T.eq(ES.Phase(), "Crack", "egg stage: x3 at 5.2 s cracks")
		local hc = #hints
		ES.Close()
		G.advance(STEP)
		T.check(lastClosed() == "Close" and #hints == hc + 1 and hints[#hints] == "You hatched: " .. epic.Name .. ", " .. rare.Name .. ", " .. epic.Name,
			"egg stage: Close() mid-Crack toasts the three pulls in one line", tostring(hints[#hints]))
		G.zeroStats(ES, "egg stage after Close mid-Crack")
		local okC, whyC = G.sameSnapshot(beforeC, G.snapshot())
		T.check(okC, "egg stage: after Close mid-Crack the Camera, Humanoid and touch controls are as before", whyC)
		local realHalves = EA.Halves
		EA.Halves = function()
			error("injected phase error")
		end
		local he = #hints
		ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) }))
		G.run(ES, 7)
		EA.Halves = realHalves
		T.check(not ES.IsShowing() and lastClosed() == "Error", "egg stage: a phase error ends the stage through teardown (Closed 'Error')", tostring(lastClosed()))
		T.check(#hints == he + 1 and hints[#hints] == "You hatched: " .. epic.Name, "egg stage: ...and toasts the pull", tostring(hints[#hints]))
		G.zeroStats(ES, "egg stage after a phase error")
		G.advance(0.3)
		-- the PC crack layout (the phone sizes: client_egg_stage_mobile)
		local t0p = os.clock()
		ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) }))
		G.until_(t0p, 4.6)
		RedoGeom.check(G.content(), "egg stage 1920x1080 x1 crack", { MinText = 18, NoOverlap = { "CrackWord", "Egg1", "Pedestal1", "Skip", "FastHatch" }, Skip = { Rays = true, Flash = true, Vignette = true } })
		local egg1, ped1 = G.hero("Egg1"), G.hero("Pedestal1")
		T.check(egg1 and ped1 and abs(egg1.AbsoluteSize.Y - 380) <= 1 and abs(ped1.AbsoluteSize.X - 418) <= 1.5 and abs(ped1.AbsoluteSize.Y - 91.2) <= 1.5,
			"egg stage: PC crack egg 380 px on a 418 x 91 pedestal (1.1 x / 0.24 x)", egg1 and fmt("%d, %dx%d", egg1.AbsoluteSize.Y, ped1.AbsoluteSize.X, ped1.AbsoluteSize.Y) or "missing")
		ES.Close()
		G.advance(0.2)
	end)
	if not ok then
		T.fail("egg stage: scenario error", tostring(err))
	end
	ensureClosed()
	closedConn:Disconnect()
	SF.Play = realPlay
	MC.Hint = realHint
	LocalPlayer:SetAttribute(IN_MATCH, nil)
	LocalPlayer:SetAttribute(Config.Attr.Tokens, oldTokens)
	LocalPlayer:SetAttribute("PaidRandomItemsRestricted", oldPolicy)
	CS.Set("FastHatch", false)
	Mock.SetViewport(oldVp[1], oldVp[2])
	G.advance(0.6)
	KC.flushErrors("client_egg_stage")
end)

----------------------------------------------------------------------------------------------------
-- client_egg_stage_mobile
----------------------------------------------------------------------------------------------------
S.client_egg_stage_mobile = guarded("client_egg_stage_mobile", function()
	local KC = G.KC()
	local ES = G.req("client/UI/EggStage")
	local PC = G.req("shared/PetCatalog")
	local CS = G.req("client/ClientSettings")
	if not T.check(type(ES) == "table" and type(ES.Show) == "function", "egg stage phone: client/UI/EggStage loads") then
		return
	end
	local epic = PC.RarityPool("Cloud", "Epic")[1]
	local rare = PC.RarityPool("Cloud", "Rare")[1]
	local leg = PC.RarityPool("Storm", "Legendary")[1]
	CS.Set("FastHatch", true)
	G.advance(0.5)
	local SKIP = { Rays = true, Flash = true, Vignette = true }
	local BAR = { "SpinAgain", "Done", "Skip", "FastHatch" }
	local function x1()
		return G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) })
	end
	local function x3()
		return G.result("Storm", "Tokens", { G.pull(PC, "Storm", rare), G.pull(PC, "Storm", leg), G.pull(PC, "Storm", epic) })
	end
	local function bottomOk(label, h)
		local bar = G.content() and G.content():FindFirstChild("BottomBar")
		local inset = 0
		pcall(function()
			local _, br = game:GetService("GuiService"):GetGuiInset()
			inset = br.Y
		end)
		local b = bar and G.box(bar)
		T.check(b ~= nil and b.y + b.h <= h - 12 - inset + 0.6, label .. ": the bottom bar sits above the bottom inset (12 px margin)", b and fmt("bar bottom %.1f of %d", b.y + b.h, h) or "no bar")
	end
	local SIZES = {
		{ 640, 360, true }, { 667, 375, true }, { 844, 390, true }, { 360, 640, true }, { 390, 844, true }, { 1280, 720, false }, { 1366, 768, false },
	}
	for _, sz in ipairs(SIZES) do
		local w, h, phone = sz[1], sz[2], sz[3]
		local label = fmt("egg stage %dx%d", w, h)
		local minText = phone and 15 or 14
		RedoGeom.at(w, h, phone, label, function()
			-- x1 during Crack (fast: 1.27 .. 1.67 s) and on the reveal
			local t0 = os.clock()
			ES.Show(x1())
			G.until_(t0, 1.45)
			T.eq(ES.Phase(), "Crack", label .. " x1: cracking at 1.45 s (fast)")
			RedoGeom.check(G.content(), label .. " x1 crack", { MinText = minText, NoOverlap = { "CrackWord", "Egg1", "Pedestal1", "Skip", "FastHatch" }, Skip = SKIP })
			local egg, ped, cw, title = G.hero("Egg1"), G.hero("Pedestal1"), G.hero("CrackWord"), G.content() and G.content():FindFirstChild("Title")
			if egg and ped then
				local e, p = G.box(egg), G.box(ped)
				T.check(abs(p.w - 1.1 * e.h) <= 1.5 and abs(p.h - 0.24 * e.h) <= 1.5 and abs(p.y - (e.y + e.h)) <= 0.6, label .. " x1: the pedestal is 1.1 x / 0.24 x its egg, under it",
					fmt("egg %.1f, pedestal %.1fx%.1f at %.1f (egg bottom %.1f)", e.h, p.w, p.h, p.y, e.y + e.h))
				if phone and w > h then
					local bar = G.content():FindFirstChild("BottomBar")
					T.check(e.h >= 120 - 0.6 and e.h <= 200 + 0.6, label .. " x1: the phone crack egg is 120 .. 200 px", fmt("%.1f", e.h))
					local tb = title and G.box(title)
					T.check(tb ~= nil and cw ~= nil and G.box(cw).y >= tb.y + tb.h - 0.6 and p.y + p.h <= G.box(bar).y + 0.6 and tb.y + tb.h <= 92 + 0.6,
						label .. " x1: the crack stack (word 40 + egg + pedestal) fits between the title band (ends by y 92) and the bottom bar",
						tb and fmt("title ends %.1f, word %.1f, pedestal ends %.1f, bar %.1f", tb.y + tb.h, cw and G.box(cw).y or -1, p.y + p.h, G.box(bar).y) or "no title")
				end
			end
			G.until_(t0, 2.45)
			T.eq(ES.Phase(), "Reveal", label .. " x1: the reveal")
			RedoGeom.check(G.content(), label .. " x1 reveal", { MinText = minText, NoOverlap = { "Banner", "Pedestal1", "Name", "Note", "SpinAgain", "Done", "Skip", "FastHatch" }, Skip = SKIP })
			bottomOk(label .. " x1 reveal", h)
			if phone then
				local banner, petF, lip = G.colPart(1, "Banner"), G.colPart(1, "Pet"), G.hero("Pedestal1")
				T.check(banner ~= nil and abs(banner.AbsoluteSize.Y - 44) <= 0.6 and abs(banner.AbsolutePosition.Y - 60) <= 0.6, label .. " x1: the phone Banner is 44 tall, its top 2 px under the 58 px inset",
					banner and fmt("%.1f at %.1f", banner.AbsoluteSize.Y, banner.AbsolutePosition.Y) or "none")
				if petF and lip then
					local pb, lb = G.box(petF), G.box(lip)
					T.check(abs(lb.h - 12) <= 0.6 and abs((lb.y + lb.h) - (pb.y + pb.h - 8)) <= 0.6 and abs(lb.w - 0.7 * pb.w) <= 1.5, label .. " x1: the phone reveal pedestal is the thin lip (12 px, 0.7 x the pet, its bottom 8 px above the pet frame's)",
						fmt("lip %.1fx%.1f ends %.1f, pet %.1f ends %.1f", lb.w, lb.h, lb.y + lb.h, pb.w, pb.y + pb.h))
					T.check(pb.h >= 110 - 0.6, label .. " x1: the phone reveal pet is at least 110 px", fmt("%.1f", pb.h))
				end
			end
			ES.Done()
			G.advance(0.2)
			-- x3 during Crack (fast: the cracks start at 1.51 s) and on the reveal
			t0 = os.clock()
			ES.Show(x3())
			G.until_(t0, 1.56)
			T.eq(ES.Phase(), "Crack", label .. " x3: cracking at 1.56 s (fast)")
			RedoGeom.check(G.content(), label .. " x3 crack", { MinText = minText, NoOverlap = { "CrackWord", "Egg1", "Egg2", "Egg3", "Pedestal1", "Pedestal2", "Pedestal3", "Skip", "FastHatch" }, Skip = SKIP })
			local ratios = true
			for j = 1, 3 do
				local e, p = G.hero("Egg" .. j), G.hero("Pedestal" .. j)
				if not (e and p and abs(p.AbsoluteSize.X - 1.1 * e.AbsoluteSize.Y) <= 1.5 and abs(p.AbsoluteSize.Y - 0.24 * e.AbsoluteSize.Y) <= 1.5) then
					ratios = false
				end
			end
			T.check(ratios, label .. " x3: every pedestal is 1.1 x / 0.24 x its egg")
			G.until_(t0, 3.2)
			T.eq(ES.Phase(), "Reveal", label .. " x3: the reveal")
			RedoGeom.check(G.content(), label .. " x3 reveal", { MinText = minText, NoOverlap = BAR, Skip = SKIP })
			bottomOk(label .. " x3 reveal", h)
			for j = 1, 3 do
				local col = G.colPart(j)
				RedoGeom.check(col, label .. " x3 column " .. j, { MinText = minText, NoOverlap = { "Banner", "Name", "Note" }, Skip = SKIP })
				local ped, nm = G.hero("Pedestal" .. j), col and col:FindFirstChild("Name")
				T.check(ped ~= nil and nm ~= nil and G.shown(ped) and not G.intersects(G.box(ped), G.box(nm)), label .. " x3: Pedestal" .. j .. " never meets column " .. j .. "'s Name")
				local petF = G.colPart(j, "Pet")
				local pb = petF and G.box(petF)
				T.check(pb ~= nil and pb.x >= -0.6 and pb.y >= 58 - 0.6 and pb.x + pb.w <= w + 0.6 and pb.y + pb.h <= h + 0.6 and pb.w > 0,
					label .. " x3: pet " .. j .. " is inside the screen", pb and fmt("%.0f,%.0f %.0fx%.0f", pb.x, pb.y, pb.w, pb.h) or "no pet")
			end
			ES.Done()
			G.advance(0.2)
		end)
	end
	-- resize mid-roll (Review Focus 1): an x3 started at 844x390, turned to 390x844 during Strip and to 1920x1080 on the reveal
	RedoGeom.at(844, 390, true, "egg stage resize mid-roll", function()
		local t0 = os.clock()
		ES.Show(x3())
		G.until_(t0, 0.5)
		T.eq(ES.Phase(), "Strip", "egg stage resize: the strips run at 0.5 s")
		Mock.SetViewport(390, 844)
		G.advance(0.1)
		RedoGeom.check(G.content(), "egg stage resize: 390x844 during Strip", { MinText = 15, NoOverlap = { "Skip", "FastHatch" }, Skip = SKIP })
		G.until_(t0, 3.2)
		T.eq(ES.Phase(), "Reveal", "egg stage resize: the roll reaches the reveal")
		Mock.SetViewport(1920, 1080)
		G.advance(0.6)
		RedoGeom.check(G.content(), "egg stage resize: 1920x1080 on the reveal", { MinText = 14, NoOverlap = BAR, Skip = SKIP })
		for j = 1, 3 do
			RedoGeom.check(G.colPart(j), "egg stage resize: 1920x1080 column " .. j, { MinText = 14, NoOverlap = { "Banner", "Name", "Note" }, Skip = SKIP })
		end
		T.eq(ES.Phase(), "Reveal", "egg stage resize: still on the reveal after the switches")
		ES.Done()
		G.advance(0.2)
	end)
	if ES.IsShowing() then
		ES.Close()
	end
	CS.Set("FastHatch", false)
	G.advance(0.6)
	KC.flushErrors("client_egg_stage_mobile")
end)

return S
