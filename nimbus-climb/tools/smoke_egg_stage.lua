-- smoke_egg_stage.lua: lobby-shop Task 20 (spec 16.4 "The egg-opening cutscene", 5.5 "The egg stage", 16.5's EggArt API):
-- the plain egg stage core (client/UI/EggStage) and the frame eggs (client/UI/EggArt). Loaded by tools/smoke.py in the
-- CLIENT and PHONE worlds (Tasks 22 / 26 / 27 extend this file):
--   client_egg_art         (client, 1920x1080; Task 20, rewritten in Task 26 for spec 16.5's forms and paint)
--     the seven eggs at 30 / 64 / 104 / 160 / 380 px: a Frame "Egg_<Rarity>" (0.8 x size wide, size tall) with a round
--       UICorner, the top-to-bottom tone UIGradient "Tone" (EggArt.Tones first and last, <= 20 keypoints), the navy
--       UIStroke "Outline" rgb(11,16,48) at size / 20 (>= 2 px, whole), a white "Highlight"; attribute Form Simple (< 48) /
--       Medium (48-140) / Full (> 140) and the instance caps 8 / 14 / 28; the attribute Motifs: Simple keeps the first
--       motif of EggArt.Paint, Medium the first two as they fit, Full every one; Medium adds the Rim light, Full the Rim,
--       the Specular dot, the contact Shadow, the Sheen and (Epic and up) the Light layer; every paint frame inside the
--       egg's outline; opts Name / ZIndex / Form, and Rim = false + Budget = 9 (the strip's cells, spec 16.4's 14 per cell)
--     EggArt.Glow (0 / 0 / 0.22 / 0.34 / 0.58 / 0.66 / 0.78), EggArt.Tones (the rarity colour 38% toward white / 28% toward
--       black; Secret rgb(74,68,104) / rgb(18,16,28)), EggArt.Paint = spec 16.5's table as { Kind, Count } in order
--     EggArt.Halves -> two CanvasGroups covering the egg's height (top half, bottom half), painted, no sheen / shadow /
--       tween; SetRarity re-paints in place across all seven (no orphan: the count of a new egg of that rarity, <= 28 at
--       Full); Resize(egg, size) moves the size, the outline and every inner stroke
--   client_egg_vfx         (client, 1920x1080 and 844x390; Task 26) Vfx = true adds nothing on Common / Uncommon and 1..8
--       instances, <= 3 tweens on Rare .. Secret (Epic 2, Legendary 2 with the turning Rays, Mythic 1, Secret 3 with its
--       Aura); a Full egg's Sheen sweeps every ~4 s on High; Low graphics: no VFX, no sheen; SetVfx(egg, false) makes an
--       egg still; destroying a Vfx egg stops its tweens; HatchFx: a 16-pool's Burst never lights more than 16 sparks,
--       one Heartbeat while any lives, halved on Low; Ambient sparkles around an egg (Mythic <= 6, none on Low), returned
--       when the egg goes or the pool stops; Stars(parent, 14) twinkle and stop on Destroy; the Shop's Eggs page: the
--       Secret hero's big HeroEgg (Full, VFX), its page-owned pool (<= 16 live, no Heartbeat while the page is hidden,
--       the Shop closed or on Low; none on a phone), the five domes' glass sheen; census: no old gem glyph
--   client_egg_stage       (client, 1920x1080, the stage alone: EggStage.Show / the _Answer listener body; Task 22 wires Init
--                          into ShopController)
--     a Cloud x1 Epic result: the seven phases in order, Reveal at 5.75 +- 0.1 s; CrackWord "EPIC EGG!", the reveal Word
--       "EPIC!", the notes (new / not new / substitute / pity), New; Skip shown on the first frame and Skip() at t = 0 ->
--       Reveal on the next frame; Back() and gamepad B skip, then are DONE; an Esc InputBegan acts once, through the one
--       Esc handler (Task 22: ShopController's, calling EggStage.Back; EggStage has none of its own); the
--       character removed mid-Strip; Fast hatch (the toggle -> one SettingsSet 0.4 s later, Reveal 1.92 / 2.66); x3
--       (7.15 s, strips landing 0.25 s apart, cracks in pull order 0.6 s apart, three columns); evolved keys; old-shape
--       results and pulls without a Strip (start at Rise); the request path (FIRE_GAP, the pending flag, a failure, the 7 s
--       timeout, a late success, the queue, SPIN AGAIN, Init's listener); the sounds; <= 12 Cell frames per strip; the
--       instance caps 450 / 750; Stats() zero after every exit (Done, Close, a match start, a phase error); the Camera, the
--       Humanoid and the touch controls as they were; no gem glyph in NimbusHatch; (review round 2) a double tap and a 2 s
--       mash on the Skip chip / SPIN AGAIN / the Dim / DONE send nothing and never close the reveal (SPIN AGAIN and DONE
--       disabled until 0.8 s into the reveal and 0.5 s after the last tap), a Dim tap 0.6 s in does not close, the armed
--       SPIN AGAIN sends one request, the armed DONE closes; the roll's Skip chip never under SPIN AGAIN / DONE at 1920x1080
--   client_egg_stage_mobile (phone world): x1 and x3, during Crack and on the reveal, at 640x360, 667x375, 844x390, 360x640,
--       390x844, 1280x720, 1366x768 (RedoGeom.check with the per-phase NoOverlap lists of plan Task 20), the phone fit
--       numbers (the crack stack, the reveal lip, the 44 px Banner), the x3 pets inside the screen, (review round 2) the
--       roll's Skip chip never under the reveal's SPIN AGAIN or DONE (x1 and x3, every size), the bottom bar above
--       the bottom inset, and the resize mid-roll (Review Focus 1: during Strip, during Crack (Task 27: the dressed hero
--       refits, the pedestals 1.1 x / 0.24 x their eggs) and on the reveal); the crack eggs measured by their laid-out size
--       (the Size attribute times Fit: the squash and the push-in change their boxes)
--   client_egg_stage_wiring (client, 1920x1080, Task 22): the Shop's Eggs tab drives the stage: a card tap sends BuyRoulette,
--       the success plays the stage over a hidden ShopWindow (the Shop stays open), DONE brings it back; the mouse-lock
--       hold under auto:NimbusHatch; Stats / Pets / Store / Index / ShopController.Open refused while the stage shows; ONE
--       Esc handler (the Shop's, through EggStage.Back): skip, then DONE; B through NimbusHatchBack; SPIN AGAIN + a card tap
--       within 0.3 s = one request; a match start / MenuController.Close() during the roll (one toast, the Shop closed);
--       a late answer after closing the Shop; close while pending by the X / Esc / B / InMatch (Review Focus 2): the cards
--       stay Pending until a success plays, a failure or the 7 s timeout re-enables them
--   client_hatch_cutscene  (client, 1920x1080, Task 27: storyboard A "Pedestal", the owner's pick with Gemini's cloud ring)
--       per phase: Intro (the Dim, the vignette, Lighting.NimbusHatchBlur 14 and the "Hatch" tint -0.08 / -0.25 through the
--       LightingStack, no colour correction added), Strip (speed streaks), Rise (Spot, Pedestal1, Backlight1, CloudRing1,
--       the 380 px Full egg), Crack (CrackWord, the shakes, Cracks 1 -> 3 -> 5, Leaks, the push-in <= 1.06), Burst (Shock,
--       Rays, 28 sparks for an Epic, the ring's swell and colour, the white micro-flash), Reveal (the Word, the pet's pop);
--       Low graphics; Legendary's one gold Flash and its rays; Mythic / Secret confetti; Secret's stars and aura; x3 in
--       pull order with one gold Flash on the best pull's burst; Skip's burst tail; the budgets at every frame; the egg
--       sound keys (today's sounds while their ids are 0, the owner's once given; a skip stops them); never breaks the
--       player (DONE, a match start mid-Crack, an injected phase error, MenuController.Close(), a respawn) with the Shop
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
-- (Task 27) a crack egg's laid-out height on screen: its Size attribute times the stage's Fit (its box changes during the
-- shakes' squash and the push-in, so the layout checks read the egg it was laid out as)
function G.eggH(egg)
	local content = G.content()
	local fit = content and content:FindFirstChild("Fit")
	return (egg:GetAttribute("Size") or egg.AbsoluteSize.Y) * (fit and fit.Scale or 1)
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
-- client_egg_art (Task 20; rewritten in Task 26: the three forms and the paint of spec 16.5)
----------------------------------------------------------------------------------------------------
-- spec 16.5's table as motif kinds, in order (Secret lists its stars first: the Simple rule keeps them; the two rune
-- lines ride in the shell's tone in every form)
local PAINT = {
	Common = { "Spots", "Dots", "Shine" },
	Uncommon = { "ZigzagBand", "Spots", "Dots" },
	Rare = { "Bands", "Dots" },
	Epic = { "StarBand", "Trim", "Stars", "Dots" },
	Legendary = { "Crown", "Trim", "Gems", "Swags" },
	Mythic = { "WaveBands", "Ribbon", "Swirls", "Stars" },
	Secret = { "Stars", "Runes", "Cracks", "Dots" },
}
local LIGHT_FROM = { Epic = true, Legendary = true, Mythic = true, Secret = true }

-- a frame's outline in screen px: a round frame (UICorner >= half its short side) by 16 samples of its capsule, any
-- other by its four corners; turned by its Rotation about its centre
function G.outlinePoints(o)
	local p, s = o.AbsolutePosition, o.AbsoluteSize
	local cx, cy = p.X + s.X / 2, p.Y + s.Y / 2
	local corner = o:FindFirstChildOfClass("UICorner")
	local short = math.min(s.X, s.Y)
	local round = corner ~= nil and (corner.CornerRadius.Scale >= 0.5 or corner.CornerRadius.Offset >= short / 2)
	local pts = {}
	if round then
		local r = short / 2
		local hx, hy = s.X / 2 - r, s.Y / 2 - r
		for i = 0, 15 do
			local a = i * math.pi / 8
			local ux, uy = math.cos(a), math.sin(a)
			pts[#pts + 1] = { (ux >= 0 and hx or -hx) + r * ux, (uy >= 0 and hy or -hy) + r * uy }
		end
	else
		pts = { { -s.X / 2, -s.Y / 2 }, { s.X / 2, -s.Y / 2 }, { s.X / 2, s.Y / 2 }, { -s.X / 2, s.Y / 2 } }
	end
	local th = math.rad(tonumber(o.Rotation) or 0)
	local c, sn = math.cos(th), math.sin(th)
	local out = {}
	for i, q in ipairs(pts) do
		out[i] = { cx + q[1] * c - q[2] * sn, cy + q[1] * sn + q[2] * c }
	end
	return out
end
-- is the screen point inside the egg body's capsule (its box, corners half its width), grown by `grow` px
function G.inCapsule(egg, x, y, grow)
	local p, s = egg.AbsolutePosition, egg.AbsoluteSize
	local r = math.min(s.X, s.Y) / 2
	local yc = math.max(p.Y + r, math.min(p.Y + s.Y - r, y))
	local dx, dy = x - (p.X + s.X / 2), y - yc
	return dx * dx + dy * dy <= (r + grow) * (r + grow)
end
-- the paint frames of an egg poking out of its body (the contact Shadow sits under the egg by design; the VFX frames
-- stand around it): -> { "Name", ... }
function G.strays(egg)
	local out = {}
	local outside = { Shadow = true, Halo = true, Aura = true, Rays = true }
	for _, d in ipairs(egg:GetDescendants()) do
		local skip = false
		local cur = d
		while cur and cur ~= egg do
			if outside[cur.Name] then
				skip = true
			end
			cur = cur.Parent
		end
		if d:IsA("GuiObject") and not skip then
			for _, q in ipairs(G.outlinePoints(d)) do
				if not G.inCapsule(egg, q[1], q[2], 0.75) then
					out[#out + 1] = d.Name
					break
				end
			end
		end
	end
	return out
end
function G.count(inst)
	return inst and (#inst:GetDescendants() + 1) or 0
end
-- the playing tweens whose instance is `root` or under it
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
function G.tweenList(root)
	local out = {}
	for tw in pairs(Mock.ActiveTweens) do
		local ok, inside = pcall(function()
			local inst = tw.Instance
			return tw.PlaybackState == Enum.PlaybackState.Playing and inst ~= nil and (inst == root or inst:IsDescendantOf(root))
		end)
		if ok and inside then
			out[#out + 1] = tw
		end
	end
	return out
end
function G.eggBoard(name)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = G.pg()
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	return gui, root
end

S.client_egg_art = guarded("client_egg_art", function()
	local KC = G.KC()
	local Config = KC.env()
	local EA = G.req("client/UI/EggArt")
	if not T.check(type(EA) == "table" and type(EA.New) == "function" and type(EA.SetRarity) == "function" and type(EA.Halves) == "function"
		and type(EA.Glow) == "function" and type(EA.Tones) == "function" and type(EA.Paint) == "function" and type(EA.Resize) == "function",
		"egg art: client/UI/EggArt loads (New, SetRarity, Halves, Glow, Tones, Paint, Resize)") then
		return
	end
	local oldVp = { Mock.Viewport.X, Mock.Viewport.Y }
	Mock.SetViewport(1920, 1080)
	G.advance(0.2)
	local gui, root = G.eggBoard("SmokeEggs")
	local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)

	-- Glow, Tones and Paint (spec 16.5's table)
	for _, rarity in ipairs(RARITIES) do
		T.check(abs((EA.Glow(rarity) or -1) - GLOW[rarity]) < 1e-9, "egg art: Glow(" .. rarity .. ") = " .. GLOW[rarity], tostring(EA.Glow(rarity)))
		local top, bottom = EA.Tones(rarity)
		local c = G.rarityColor(Config, rarity)
		if rarity == "Secret" then
			T.check(G.rgb(top, 74, 68, 104) and G.rgb(bottom, 18, 16, 28), "egg art: Tones(Secret) = rgb(74,68,104) / rgb(18,16,28)")
		else
			T.check(G.same(top, c:Lerp(WHITE, 0.38)) and G.same(bottom, c:Lerp(BLACK, 0.28)), "egg art: Tones(" .. rarity .. ") = the colour 38% toward white / 28% toward black")
		end
		local paint = EA.Paint(rarity)
		local kinds, counts = {}, true
		for i, m in ipairs(type(paint) == "table" and paint or {}) do
			kinds[i] = tostring(m.Kind)
			counts = counts and type(m.Count) == "number" and m.Count >= 1 and m.Count == math.floor(m.Count)
		end
		T.eq(table.concat(kinds, ","), table.concat(PAINT[rarity], ","), "egg art: Paint(" .. rarity .. ") lists spec 16.5's motifs in order")
		T.check(counts and #kinds > 0, "egg art: ...each with a whole Count >= 1 (" .. rarity .. ")")
	end

	-- the seven eggs at five sizes: the base, the form by size, the caps, the motifs each form keeps, the layers
	local CAP = { Simple = 8, Medium = 14, Full = 28 }
	local bad = T.tally("egg art: every egg at 30 / 64 / 104 / 160 / 380 px is the oval body with its tone, outline and highlight", 4)
	local caps = T.tally("egg art: the instance caps 8 / 14 / 28 by form", 4)
	local motifs = T.tally("egg art: Simple keeps the first motif, Medium the first two (as they fit), Full every motif (attribute Motifs)", 4)
	local layers = T.tally("egg art: Medium adds the Rim light; Full the Rim, the Specular dot, the contact Shadow and the Sheen; the Light layer at Full from Epic up", 4)
	local inside = T.tally("egg art: every paint frame stays inside the egg's outline (no stray frame)", 4)
	local tones = T.tally("egg art: the Tone gradient holds <= 20 keypoints (Roblox's limit)", 4)
	for _, rarity in ipairs(RARITIES) do
		local all = table.concat(PAINT[rarity], ",")
		for _, size in ipairs({ 30, 64, 104, 160, 380 }) do
			local egg = EA.New(root, rarity, size)
			egg.Position = UDim2.fromOffset(500, 300)
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
			tones:case(#kps <= 20, label .. ": " .. #kps .. " keypoints")
			local outline = egg and egg:FindFirstChild("Outline")
			local th = outline and outline:IsA("UIStroke") and outline.Thickness or -1
			ok = ok and G.rgb(outline and outline.Color, 11, 16, 48) and th == math.max(2, math.floor(size / 20 + 0.5)) and th == math.floor(th)
			local hl = egg and egg:FindFirstChild("Highlight")
			ok = ok and hl ~= nil and hl:IsA("Frame") and G.rgb(hl.BackgroundColor3, 255, 255, 255)
			ok = ok and egg:GetAttribute("Form") == form and egg:GetAttribute("Rarity") == rarity
			bad:case(ok, label .. (egg and fmt(" (%s, %dx%d, outline %s, form %s)", egg.Name, egg.Size.X.Offset, egg.Size.Y.Offset, tostring(th), tostring(egg:GetAttribute("Form"))) or " (nil)"))
			local n = G.count(egg)
			caps:case(n <= CAP[form], fmt("%s: %d instances (%s cap %d)", label, n, form, CAP[form]))
			local got = tostring(egg:GetAttribute("Motifs"))
			if form == "Simple" then
				motifs:case(got == PAINT[rarity][1], label .. ": " .. got)
			elseif form == "Medium" then
				local two = PAINT[rarity][1] .. "," .. tostring(PAINT[rarity][2])
				motifs:case(got == PAINT[rarity][1] or got == two, label .. ": " .. got)
			else
				motifs:case(got == all, label .. ": " .. got)
			end
			local has = function(name)
				return egg:FindFirstChild(name) ~= nil
			end
			local okL = true
			if form == "Simple" then
				okL = not has("Rim") and not has("Specular") and not has("Shadow") and not has("Sheen") and not has("Light")
			elseif form == "Medium" then
				okL = has("Rim") and not has("Specular") and not has("Shadow") and not has("Sheen") and not has("Light")
			else
				okL = has("Rim") and has("Specular") and has("Shadow") and has("Sheen") and (has("Light") == (LIGHT_FROM[rarity] == true))
			end
			layers:case(okL, label)
			local strays = G.strays(egg)
			inside:case(#strays == 0, label .. ": " .. table.concat(strays, ", "))
			egg:Destroy()
		end
	end
	bad:report()
	caps:report()
	motifs:report()
	layers:report()
	inside:report()
	tones:report()
	local named = EA.New(root, "Rare", 104, { Name = "Egg1", ZIndex = 6, Form = "Simple" })
	T.check(named.Name == "Egg1" and named.ZIndex == 6 and named:GetAttribute("Form") == "Simple" and G.count(named) <= 8, "egg art: opts Name, ZIndex and Form (a forced Simple keeps its cap)")
	-- the strip's cells (spec 16.4: <= 14 instances per cell): Rim = false and Budget = 9 keep a Medium egg lean
	local lean = T.tally("egg art: opts Rim = false, Budget = 9 (the strip's cells): no Rim, <= 9 instances, the main motif first", 4)
	for _, rarity in ipairs(RARITIES) do
		for _, size in ipairs({ 48, 104, 160 }) do
			local e = EA.New(root, rarity, size, { Form = "Medium", Rim = false, Budget = 9 })
			local got = tostring(e:GetAttribute("Motifs"))
			lean:case(e:FindFirstChild("Rim") == nil and G.count(e) <= 9 and string.sub(got, 1, #PAINT[rarity][1]) == PAINT[rarity][1],
				fmt("%s %d: %d instances, %s", rarity, size, G.count(e), got))
			e:Destroy()
		end
	end
	lean:report()

	-- SetRarity: re-paints in place, no orphan (the same instance count as a new egg of that rarity), both ways round
	local egg = EA.New(root, "Common", 104)
	EA.SetRarity(egg, "Mythic")
	local top, bottom = EA.Tones("Mythic")
	local kps = egg:FindFirstChild("Tone").Color.Keypoints
	local fresh = EA.New(root, "Mythic", 104)
	T.check(G.count(egg) == G.count(fresh) and egg.Name == "Egg_Mythic" and egg:GetAttribute("Rarity") == "Mythic" and G.same(kps[1].Value, top) and G.same(kps[#kps].Value, bottom),
		"egg art: SetRarity re-skins in place (the Mythic tones, the name and attribute follow; the count of a new Mythic egg)", fmt("%d vs %d, %s", G.count(egg), G.count(fresh), egg.Name))
	fresh:Destroy()
	EA.SetRarity(named, "Epic")
	T.check(named.Name == "Egg1" and named:GetAttribute("Rarity") == "Epic", "egg art: SetRarity keeps a custom name")
	local big = EA.New(root, "Common", 380)
	local orphan = T.tally("egg art: SetRarity across all seven on a Full egg keeps it within 28 instances with no orphan (as a new egg of each rarity)", 4)
	local order = {}
	for _, r in ipairs(RARITIES) do
		order[#order + 1] = r
	end
	for i = #RARITIES, 1, -1 do
		order[#order + 1] = RARITIES[i]
	end
	for _, r in ipairs(order) do
		EA.SetRarity(big, r)
		local f = EA.New(root, r, 380)
		orphan:case(G.count(big) == G.count(f) and G.count(big) <= 28 and big:GetAttribute("Motifs") == table.concat(PAINT[r], ",") and #G.strays(big) == 0,
			fmt("%s: %d (new %d), %s", r, G.count(big), G.count(f), tostring(big:GetAttribute("Motifs"))))
		f:Destroy()
	end
	orphan:report()

	-- Resize (EggStage / ShopEggs resize their eggs): the size, the outline and every stroke inside follow
	local rz = EA.New(root, "Rare", 380)
	local function strokes(e)
		local out = {}
		for _, d in ipairs(e:GetDescendants()) do
			if d:IsA("UIStroke") and d.Name ~= "Outline" then
				out[#out + 1] = d.Thickness
			end
		end
		return out
	end
	local before = strokes(rz)
	EA.Resize(rz, 190)
	local after = strokes(rz)
	local okR = #before > 0 and #before == #after
	for i = 1, #before do
		okR = okR and abs(after[i] - math.max(1, before[i] / 2)) <= 1
	end
	T.check(rz.Size.X.Offset == 152 and rz.Size.Y.Offset == 190 and rz:FindFirstChild("Outline").Thickness == 10 and rz:GetAttribute("Size") == 190 and okR,
		"egg art: Resize(egg, 190) sets the size, the outline (10) and halves every inner stroke", fmt("%dx%d, strokes %s -> %s", rz.Size.X.Offset, rz.Size.Y.Offset, table.concat(before, "/"), table.concat(after, "/")))

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
		T.check(eggTop ~= nil and eggTop:GetAttribute("Motifs") == table.concat(PAINT.Legendary, ",") and eggTop:FindFirstChild("Sheen") == nil and eggTop:FindFirstChild("Shadow") == nil
			and G.tweensUnder(holder) == 0, "egg art: the halves are painted (every motif) with no sheen, no shadow and no tween (they fly apart in 0.35 s)",
			eggTop and tostring(eggTop:GetAttribute("Motifs")) .. ", " .. G.tweensUnder(holder) .. " tweens" or "")
	end

	gui:Destroy()
	Mock.SetViewport(oldVp[1], oldVp[2])
	G.advance(0.3)
	KC.flushErrors("client_egg_art")
end)

----------------------------------------------------------------------------------------------------
-- client_egg_stage
----------------------------------------------------------------------------------------------------
-- the egg sound keys (uploaded and approved 2026-11-07: shared/AudioIds has an id for each) and today's sound each falls
-- back to while its id is 0 (false: silent then); Config.Audio.Fallback holds the same map
local EGG_SOUNDS = {
	EggStripTick = "SpinTick", EggStripLand = "SpinLand", EggRise = false, EggShake = false, EggCrack = false, EggBurst = "Shatter",
	EggCloudRing = false, EggRevealCommon = "RevealCommon", EggRevealEpic = "RevealRare", EggRevealLegend = "RevealLegendary",
	EggRevealSecret = "RevealLegendary",
}
-- the id-0 world for a test: every egg id in Config.Audio.Sfx set to 0 (the real ids saved); -> the function that puts
-- them back
local function zeroEggIds(Config)
	local saved = {}
	for key in pairs(EGG_SOUNDS) do
		saved[key] = Config.Audio.Sfx[key]
		Config.Audio.Sfx[key] = 0
	end
	return function()
		for key in pairs(EGG_SOUNDS) do
			Config.Audio.Sfx[key] = saved[key]
		end
	end
end
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
		local rec = { name = name, scale = opts and opts.Scale }
		sounds[#sounds + 1] = rec
		-- the egg keys play for real (SoundFx's pool), so the test reads each Sound's id and volume
		if EGG_SOUNDS[name] ~= nil then
			local okP, snd = pcall(realPlay, name, opts)
			if okP and typeof(snd) == "Instance" then
				rec.id, rec.volume = snd.SoundId, snd.Volume
				return snd
			end
		end
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
		-- (review round 3) an x3 column's note leaves the name out: it sits right above the note, and the 18 px phone column wrapped
		-- "... you have 12 Candy Unicorn now" to three lines in its 36 px box
		T.eq(ES.NoteText({ PoolSize = 3, IsNew = false, Count = 12, PetId = epic.Id }, "Epic", true), "1 of 3 Epic pets " .. DOT .. " you have 12 now", "egg stage: NoteText(pull, rarity, true) (x3) leaves the pet's name out")
		T.eq(ES.NoteText({ PoolSize = 3, IsNew = true, PetId = epic.Id }, "Epic", true), "1 of 3 Epic pets " .. DOT .. " added to your pets", "egg stage: NoteText(..., true) for a new pet is unchanged")
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
		-- the uploaded egg sounds (AudioIds has every egg id): they play, today's roulette sounds do not
		local noId = {}
		for key in pairs(EGG_SOUNDS) do
			local id = Config.Audio.Sfx[key]
			if not (type(id) == "number" and id > 0) then
				noId[#noId + 1] = key
			end
		end
		table.sort(noId)
		T.check(#noId == 0, "egg stage: Config.Audio.Sfx has an id for each of the 11 egg sounds (uploaded 2026-11-07)", table.concat(noId, " "))
		local EPIC_PLAYS = { "SpinStart", "EggStripTick", "EggStripLand", "EggRise", "EggShake", "EggCrack", "EggBurst", "EggCloudRing", "EggRevealEpic" }
		for _, name in ipairs(EPIC_PLAYS) do
			T.check(hasSound(epicSounds, name, 0.6), "egg stage: an Epic roll plays " .. name .. " at Scale 0.6")
		end
		local old = {}
		for _, name in ipairs({ "SpinTick", "SpinLand", "Shatter", "RevealCommon", "RevealRare", "RevealLegendary" }) do
			if hasSound(epicSounds, name) then
				old[#old + 1] = name
			end
		end
		T.check(#old == 0, "egg stage: ...and none of the fallback sounds while the egg ids exist", table.concat(old, " "))
		-- each egg key's Sound: its AudioIds id, at Config.Audio.Volume[key] x 0.6 x the Sfx setting
		local sfxVol = SF.Volume("Sfx")
		local real, wrong = {}, {}
		for _, s in ipairs(epicSounds) do
			if s.volume ~= nil then
				real[s.name] = true
				local want = math.min(1, (Config.Audio.Volume[s.name] or -1) * 0.6 * sfxVol)
				local wantId = "rbxassetid://" .. fmt("%d", Config.Audio.Sfx[s.name] or 0)
				if s.id ~= wantId or abs(s.volume - want) > 1e-6 then
					wrong[#wrong + 1] = fmt("%s %s %.4f (want %s %.4f)", s.name, tostring(s.id), s.volume, wantId, want)
				end
			end
		end
		local unplayed = {}
		for i = 2, #EPIC_PLAYS do
			if not real[EPIC_PLAYS[i]] then
				unplayed[#unplayed + 1] = EPIC_PLAYS[i]
			end
		end
		T.check(sfxVol > 0 and #unplayed == 0 and #wrong == 0, "egg stage: each egg Sound carries its uploaded id at its Config.Audio.Volume x Scale 0.6 x the Sfx setting",
			fmt("sfx %.2f; no Sound: %s; wrong: %s", sfxVol, table.concat(unplayed, " "), table.concat(wrong, ", ")))
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
		-- (Task 22: EggStage still has no Esc handler of its own; ShopController's one handler calls EggStage.Back)
		local UIS = game:GetService("UserInputService")
		local backs, realBack = 0, ES.Back
		ES.Back = function(...)
			backs = backs + 1
			return realBack(...)
		end
		Mock.FireSignal(UIS, "InputBegan", Mock.NewInput("Escape", "Keyboard", "Begin"), false)
		G.advance(STEP)
		ES.Back = realBack
		T.check(ES.IsShowing() and ES.Phase() == "Reveal" and backs == 1, "egg stage: an Esc InputBegan acts once, through the one Esc handler (EggStage.Back): the strip skips",
			tostring(ES.Phase()) .. ", " .. backs .. " Back calls")
		ES.Done()
		G.advance(STEP)
		ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) }))
		G.advance(0.8)
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
			if s.name:match("^Reveal") or s.name:match("^EggReveal") then
				rev3 = rev3 + 1
			end
		end
		T.check(rev3 == 1 and hasSound(list3, "EggRevealLegend", 1), "egg stage: x3 plays one reveal sound, the best pull's (EggRevealLegend at 1)", tostring(rev3))
		T.check(ES.Stats().Instances <= 750, "egg stage: x3 reveal within 750 instances", tostring(ES.Stats().Instances))
		ES.Done()
		G.advance(0.3)
		G.zeroStats(ES, "egg stage after the x3 DONE")

		------------------------------------------------------------------ Legendary x1: the loud reveal; an evolved x1
		local sL = #sounds
		ES.Show(G.result("Storm", "Tokens", { G.pull(PC, "Storm", leg) }))
		G.run(ES, 7)
		local listL = soundsFrom(sL)
		T.check(hasSound(listL, "EggRevealLegend", 1), "egg stage: a Legendary roll plays EggRevealLegend at Scale 1")
		T.check(hasSound(listL, "SpinStart", 0.6) and not hasSound(listL, "SpinStart", 1), "egg stage: ...but the strip's start stays at 0.6 (no tell before the landing)")
		ES.Done()
		G.advance(0.2)

		------------------------------------------------------------------ the reveal sound per rarity (the owner's picks page)
		local REVEAL_MAP = {
			{ "Cloud", "Common", "Tokens", "EggRevealCommon", 0.6 }, { "Cloud", "Uncommon", "Tokens", "EggRevealCommon", 0.6 },
			{ "Cloud", "Rare", "Tokens", "EggRevealCommon", 0.6 }, { "Cloud", "Epic", "Tokens", "EggRevealEpic", 0.6 },
			{ "Storm", "Legendary", "Tokens", "EggRevealLegend", 1 }, { "Secret", "Mythic", "Gems", "EggRevealLegend", 1 },
			{ "Secret", "Secret", "Gems", "EggRevealSecret", 1 },
		}
		local mapWrong, mapRun = {}, 0
		for _, m in ipairs(REVEAL_MAP) do
			local def = PC.RarityPool(m[1], m[2])[1]
			if def then
				mapRun = mapRun + 1
				local sm = #sounds
				ES.Show(G.result(m[1], m[3], { G.pull(PC, m[1], def) }))
				ES.Skip()
				G.advance(0.3)
				local got = {}
				for _, s in ipairs(soundsFrom(sm)) do
					if s.name:match("Reveal") then
						got[#got + 1] = fmt("%s@%s", s.name, tostring(s.scale))
					end
				end
				if #got ~= 1 or got[1] ~= fmt("%s@%s", m[4], tostring(m[5])) then
					mapWrong[#mapWrong + 1] = m[2] .. ": " .. table.concat(got, " ")
				end
				ES.Done()
				G.advance(0.2)
			end
		end
		T.check(mapRun == #REVEAL_MAP and #mapWrong == 0, "egg stage: reveal sounds: Common / Uncommon / Rare EggRevealCommon, Epic EggRevealEpic (0.6); Legendary / Mythic EggRevealLegend, Secret EggRevealSecret (1)",
			fmt("%d of %d rarities run; %s", mapRun, #REVEAL_MAP, table.concat(mapWrong, "; ")))

		------------------------------------------------------------------ the id-0 fallback (the egg ids zeroed in this test, put back after): today's sounds
		local restoreIds = zeroEggIds(Config)
		local okFb, errFb = pcall(function()
			local sF = #sounds
			ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) }))
			G.run(ES, 7)
			local listF = soundsFrom(sF)
			for _, name in ipairs({ "SpinStart", "SpinTick", "SpinLand", "Shatter", "RevealRare" }) do
				T.check(hasSound(listF, name, 0.6), "egg stage: egg ids at 0 -> an Epic roll plays today's " .. name .. " at Scale 0.6")
			end
			local eggPlayed = {}
			for _, s in ipairs(listF) do
				if EGG_SOUNDS[s.name] ~= nil then
					eggPlayed[#eggPlayed + 1] = s.name
				end
			end
			T.check(#eggPlayed == 0, "egg stage: egg ids at 0 -> no egg key reaches SoundFx (EggRise / EggShake / EggCrack / EggCloudRing stay silent)", table.concat(eggPlayed, " "))
			ES.Done()
			G.advance(0.2)
			local sF2 = #sounds
			ES.Show(G.result("Storm", "Tokens", { G.pull(PC, "Storm", leg) }))
			ES.Skip()
			G.advance(0.3)
			T.check(hasSound(soundsFrom(sF2), "RevealLegendary", 1), "egg stage: egg ids at 0 -> a Legendary reveal plays today's RevealLegendary at Scale 1")
			ES.Done()
			G.advance(0.2)
		end)
		restoreIds()
		T.check(okFb, "egg stage: the id-0 fallback step ran", tostring(errFb))
		T.check(type(Config.Audio.Sfx.EggRevealSecret) == "number" and Config.Audio.Sfx.EggRevealSecret > 0, "egg stage: the real egg ids are back after the fallback step")
		quickReveal(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic, { Key = epic.Id }) }), "evolved")
		local ribbon = G.colPart(1, "EvolvedRibbon")
		T.check(G.shown(ribbon), "egg stage: an evolved key gets the EvolvedRibbon on the x1 reveal")
		local pet = G.colPart(1, "Pet")
		T.check(pet ~= nil and pet:FindFirstChildWhichIsA("ViewportFrame", true) ~= nil, "egg stage: ...over the pet's viewport")
		T.check(ES.IsPrewarmed(epic.Id) == true, "egg stage: IsPrewarmed(petId) after its roll")
		ES.Done()
		G.advance(0.2)
		-- (review round 1) a pet whose build fails is tried once per session (not every frame), and the pulls after it
		-- still warm during the strip
		do
			local realBuilder, realWarm = ES._S.Builder, ES._S.Warm
			local calls = {}
			ES._S.Builder = {
				Build = function(def)
					local id = type(def) == "table" and def.Id or "?"
					calls[id] = (calls[id] or 0) + 1
					if id == epic.Id then
						error("planted build failure")
					end
					return Instance.new("Model")
				end,
			}
			ES._S.Warm = {}
			ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic), G.pull(PC, "Cloud", rare), G.pull(PC, "Cloud", epic) }))
			local runW = G.run(ES, 8.5) -- (x3 RevealAt 7.15)
			T.check(runW.at.Reveal ~= nil and (calls[epic.Id] or 0) == 1 and (calls[rare.Id] or 0) == 1 and ES.IsPrewarmed(rare.Id) == true and ES.IsPrewarmed(epic.Id) == false,
				"egg stage: a pet whose build fails is built once (not every frame) and the next pull still warms",
				fmt("epic builds %d, rare builds %d, rare warm %s, reveal %s", calls[epic.Id] or 0, calls[rare.Id] or 0, tostring(ES.IsPrewarmed(rare.Id)), tostring(runW.at.Reveal)))
			ES.Done()
			G.advance(0.2)
			ES._S.Builder, ES._S.Warm = realBuilder, realWarm
		end

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
		-- (review round 1) the request almost always reached the server, so the toast never asks for a retry (a second tap
		-- would be a second paid spin)
		T.check(ES.IsPending() == false and #hints == h2 + 1 and hints[#hints] == "Still waiting for the roulette. Your spin will hatch as soon as it arrives.",
			"egg stage: 7 s without an answer -> not pending, one toast that does not ask to try again", tostring(hints[#hints]))
		T.check(not tostring(hints[#hints]):lower():find("try again", 1, true), "egg stage: ...the timeout toast never says 'try again'")
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
		-- SPIN AGAIN: a new paid request through Request; the reveal stays up until the answer (review round 2: it arms 0.8 s
		-- into the reveal, so this tap comes 0.9 s in)
		G.advance(0.5)
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
		-- (review round 1) SPIN AGAIN's disabled states (spec 5.5): the reason replaces the label, the price hides, the
		-- button is off; it comes back by itself (refreshAgain every 8 heartbeats)
		local function againState()
			local btn = G.bar("SpinAgain")
			local row = btn and btn:FindFirstChild("Row")
			local lbl, price = row and row:FindFirstChild("Label"), row and row:FindFirstChild("Price")
			return {
				Text = lbl and tostring(lbl.Text) or "?",
				Price = price ~= nil and G.shown(price),
				Off = btn ~= nil and (btn:GetAttribute("Disabled") == true or btn.Active == false),
			}
		end
		ES.Skip()
		G.advance(0.6)
		LocalPlayer:SetAttribute(Config.Attr.Tokens, 10)
		G.advance(0.4)
		local stShort = againState()
		T.check(stShort.Text == "Not enough Tokens" and not stShort.Price and stShort.Off, "egg stage: SPIN AGAIN with too few tokens reads 'Not enough Tokens', hides its price and is off",
			fmt("'%s', price %s, off %s", stShort.Text, tostring(stShort.Price), tostring(stShort.Off)))
		LocalPlayer:SetAttribute(Config.Attr.Tokens, 50000)
		G.advance(0.4)
		local stBack = againState()
		T.check(stBack.Text == "SPIN AGAIN" and stBack.Price and not stBack.Off, "egg stage: ...enough tokens again: 'SPIN AGAIN', its price shown, on again",
			fmt("'%s', price %s, off %s", stBack.Text, tostring(stBack.Price), tostring(stBack.Off)))
		ES.Done()
		G.advance(0.2)
		ES._Answer(G.result("Cloud", "Gems", { G.pull(PC, "Cloud", epic) }))
		ES.Skip()
		G.advance(0.6)
		LocalPlayer:SetAttribute("PaidRandomItemsRestricted", true)
		G.advance(0.4)
		local stLock = againState()
		T.check(stLock.Text == "Locked" and not stLock.Price and stLock.Off, "egg stage: a gem SPIN AGAIN while paid random items are restricted reads 'Locked', no price, off",
			fmt("'%s', price %s, off %s", stLock.Text, tostring(stLock.Price), tostring(stLock.Off)))
		LocalPlayer:SetAttribute("PaidRandomItemsRestricted", false)
		G.advance(0.4)
		local stOpen = againState()
		T.check(stOpen.Text == "SPIN AGAIN" and stOpen.Price and not stOpen.Off, "egg stage: ...the policy answered false: 'SPIN AGAIN', its price shown, on again",
			fmt("'%s', price %s, off %s", stOpen.Text, tostring(stOpen.Price), tostring(stOpen.Off)))
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

		------------------------------------------------------------------ (review round 2) the skip finger and the reveal's buttons
		-- a double tap (or a mash) on the Skip chip never spends a spin and never closes the reveal: SPIN AGAIN, DONE and a
		-- tap's close arm 0.8 s after the reveal appeared and 0.5 s after the last tap on the stage (each tap restarts the
		-- wait), shown disabled until then; the roll's Skip chip never sits under SPIN AGAIN or DONE
		do
			local function click(b)
				if b and b.Parent then
					Mock.Click(b)
				end
			end
			local function off(b)
				return b ~= nil and (b:GetAttribute("Disabled") == true or b.Active == false)
			end
			local b2, c2 = #KC.serverCalls("BuyRoulette"), #closed
			ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) }))
			G.advance(1.0)
			local skipBtn = G.bar("Skip")
			local rollSkip = skipBtn and G.shown(skipBtn) and G.box(skipBtn) or nil
			click(skipBtn) -- tap 1: skip
			G.advance(STEP)
			T.eq(ES.Phase(), "Reveal", "egg stage: (round 2) a tap on the Skip chip skips to the reveal")
			local againB, doneB = G.bar("SpinAgain"), G.bar("Done")
			local under = {}
			for _, b in ipairs({ againB, doneB }) do
				if rollSkip and b and G.shown(b) and G.intersects(rollSkip, G.box(b)) then
					under[#under + 1] = b.Name
				end
			end
			T.check(rollSkip ~= nil and #under == 0, "egg stage 1920x1080: the roll's Skip chip never sits under SPIN AGAIN or DONE",
				rollSkip and fmt("Skip %.0f..%.0f under %s", rollSkip.x, rollSkip.x + rollSkip.w, table.concat(under, ", ")) or "no Skip chip")
			T.check(off(againB) and off(doneB), "egg stage: (round 2) SPIN AGAIN and DONE show disabled as the reveal appears",
				fmt("again off %s, done off %s", tostring(off(againB)), tostring(off(doneB))))
			-- tap 2 on SPIN AGAIN 0.15 s after the skip, then a 2 s mash on SPIN AGAIN, the Dim and DONE
			G.advance(0.15)
			click(againB)
			local dim = G.gui() and G.gui():FindFirstChild("Stage") and G.gui().Stage:FindFirstChild("Dim")
			for k = 1, 14 do
				G.advance(0.15)
				click(({ againB, dim, doneB })[k % 3 + 1])
			end
			G.advance(STEP)
			T.eq(#KC.serverCalls("BuyRoulette") - b2, 0, "egg stage: (round 2) a double tap and a 2 s mash on SPIN AGAIN / the Dim / DONE send no BuyRoulette")
			T.check(ES.IsShowing() and ES.Phase() == "Reveal" and #closed == c2, "egg stage: (round 2) ...and never close the reveal", tostring(ES.Phase()) .. ", closed " .. (#closed - c2))
			T.check(off(againB) and off(doneB), "egg stage: (round 2) ...SPIN AGAIN and DONE stay disabled while the taps go on")
			G.advance(0.55)
			T.check(not off(againB) and not off(doneB), "egg stage: (round 2) 0.5 s after the last tap SPIN AGAIN and DONE arm",
				fmt("again off %s, done off %s", tostring(off(againB)), tostring(off(doneB))))
			click(againB)
			T.eq(#KC.serverCalls("BuyRoulette") - b2, 1, "egg stage: (round 2) ...then one SPIN AGAIN tap sends one BuyRoulette")
			ES._Answer(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) }))
			-- a quiet reveal: a Dim tap 0.6 s in (past the old 0.5 s guard) does not close it, one 0.6 s later does
			ES.Skip()
			G.advance(STEP)
			T.eq(ES.Phase(), "Reveal", "egg stage: (round 2) (setup) the next roll skipped to its reveal")
			G.advance(0.6)
			dim = G.gui() and G.gui().Stage:FindFirstChild("Dim")
			click(dim)
			G.advance(STEP)
			T.check(ES.IsShowing() and #closed == c2, "egg stage: (round 2) a Dim tap 0.6 s into the reveal does not close it (0.8 s)")
			G.advance(0.6)
			click(dim)
			G.advance(STEP)
			T.check(not ES.IsShowing() and lastClosed() == "Done", "egg stage: (round 2) ...a tap once armed closes it (Closed 'Done')", tostring(lastClosed()))
			-- DONE once armed closes; B one frame into the reveal is still DONE (a key, never a tap on a paid button: spec 5.5)
			ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) }))
			ES.Skip()
			G.advance(1.0)
			doneB = G.bar("Done")
			T.check(not off(doneB), "egg stage: (round 2) DONE is armed 1 s into an untouched reveal")
			click(doneB)
			G.advance(STEP)
			T.check(not ES.IsShowing() and lastClosed() == "Done", "egg stage: (round 2) ...and closes it", tostring(lastClosed()))
			T.eq(#KC.serverCalls("BuyRoulette") - b2, 1, "egg stage: (round 2) no other BuyRoulette was sent")
			G.advance(0.4)
		end

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
		local o0 = #Mock.Output
		ES.Show(G.result("Cloud", "Tokens", { G.pull(PC, "Cloud", epic) }))
		G.run(ES, 7)
		EA.Halves = realHalves
		-- (the planted fault's one warning belongs to this check: counted, then dropped, so client_final's warn audit sees
		-- only real ones; the smoke_dev.lua pattern)
		local planted = 0
		for i = #Mock.Output, o0 + 1, -1 do
			local o = Mock.Output[i]
			if o.kind == "warn" and tostring(o.text):find("injected phase error", 1, true) then
				planted = planted + 1
				table.remove(Mock.Output, i)
			end
		end
		T.eq(planted, 1, "egg stage: the phase error is reported once (warn)")
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
		T.check(egg1 and ped1 and abs(G.eggH(egg1) - 380) <= 1 and abs(ped1.AbsoluteSize.X - 418) <= 1.5 and abs(ped1.AbsoluteSize.Y - 91.2) <= 1.5,
			"egg stage: PC crack egg 380 px on a 418 x 91 pedestal (1.1 x / 0.24 x)", egg1 and fmt("%d, %dx%d", G.eggH(egg1), ped1.AbsoluteSize.X, ped1.AbsoluteSize.Y) or "missing")
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
	-- (review round 3) an x3 reveal laid out with Roblox's real font widths: RedoGeom.realWidth (Montserrat Black for the
	-- GothamBlack roles, Fredoka One, Builder Sans) through EggStage.Metrics.MEASURE, the hook the live game leaves to TextService.
	-- The mock's flat 0.5 em hid it: two NEW pets with the longest names (Frostling Penguin 175 px, Starlight Unicorn 167 px at
	-- 18 px) were cut beside NEW!, a duplicate's note ("... you have 12 Twilight Dragon now") wrapped to three lines in 36 px,
	-- and Sky's SPIN AGAIN x3 + coin + "3,000" filled the gold button edge to edge at 640x360
	local longNames = { PC.Get("frostling_penguin"), PC.Get("starlight_unicorn"), PC.Get("twilight_dragon") }
	local function realX3(label)
		if not T.check(longNames[1] and longNames[2] and longNames[3], label .. " real x3: the catalog has Frostling Penguin, Starlight Unicorn, Twilight Dragon") then
			return
		end
		local savedMeasure = ES.Metrics.MEASURE
		local savedTokens = LocalPlayer:GetAttribute("CloudTokens")
		ES.Metrics.MEASURE = function(text, size, font)
			return RedoGeom.realWidth(text, size, font)
		end
		LocalPlayer:SetAttribute("CloudTokens", 100000)
		local ok, err = pcall(function()
			local t0 = os.clock()
			ES.Show(G.result("Sky", "Tokens", { G.pull(PC, "Sky", longNames[1]), G.pull(PC, "Sky", longNames[2]), G.pull(PC, "Sky", longNames[3], { IsNew = false, Count = 12 }) }))
			G.until_(t0, 3.2)
			if not T.eq(ES.Phase(), "Reveal", label .. " real x3: the reveal") then
				return
			end
			local bad = {}
			for j = 1, 3 do
				local col = G.colPart(j)
				local nm, note, new = col and col:FindFirstChild("Name"), col and col:FindFirstChild("Note"), col and col:FindFirstChild("New")
				local okName, dName = RedoGeom.fits(nm)
				if not okName then
					bad[#bad + 1] = "col " .. j .. " name " .. tostring(dName)
				end
				local okNote, dNote = RedoGeom.fits(note)
				if not okNote then
					bad[#bad + 1] = "col " .. j .. " note " .. tostring(dNote)
				end
				if j <= 2 then
					if not (new and G.shown(new)) then
						bad[#bad + 1] = "col " .. j .. " no NEW!"
					else
						local nb = G.box(new)
						for _, other in ipairs({ "Name", "Note", "Banner", "EvolvedRibbon" }) do
							local o = col:FindFirstChild(other)
							if o and G.shown(o) and G.intersects(nb, G.box(o)) then
								bad[#bad + 1] = "col " .. j .. " NEW! meets " .. other
							end
						end
						local cb = G.box(col)
						if nb.x < cb.x - 0.6 or nb.x + nb.w > cb.x + cb.w + 0.6 then
							bad[#bad + 1] = fmt("col %d NEW! %.0f..%.0f outside the column %.0f..%.0f", j, nb.x, nb.x + nb.w, cb.x, cb.x + cb.w)
						end
					end
				end
			end
			T.check(#bad == 0, label .. " real x3: with the real font widths every name and note fits; NEW! shows, clear of the name, note, banner and ribbon", table.concat(bad, "; "))
			local again = G.bar("SpinAgain")
			local row = again and again:FindFirstChild("Row")
			local lbl, coin, price = row and row:FindFirstChild("Label"), row and row:FindFirstChild("Coin"), row and row:FindFirstChild("Price")
			if T.check(lbl and coin and price and G.shown(price) and tostring(lbl.Text):find("x3", 1, true) ~= nil, label .. " real x3: SPIN AGAIN x3 shows its label, coin and price", lbl and tostring(lbl.Text) or "no row") then
				local bw = again.Size.X.Offset
				local need = RedoGeom.realWidth(lbl.Text, lbl.TextSize, lbl.Font) + coin.Size.X.Offset + RedoGeom.realWidth(price.Text, price.TextSize, price.Font) + 12
				T.check(need + 8 <= bw + 0.5, label .. " real x3: SPIN AGAIN x3 + coin + price fits its button with 4 px clear each side (real font widths)",
					fmt("'%s' + '%s' = %.1f px in %.1f", tostring(lbl.Text), tostring(price.Text), need, bw))
			end
		end)
		ES.Metrics.MEASURE = savedMeasure
		LocalPlayer:SetAttribute("CloudTokens", savedTokens)
		T.check(ok, label .. " real x3: ran without an error", tostring(err))
		if ES.IsShowing() then
			ES.Done()
		end
		G.advance(0.2)
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
		-- (Task 31, found in the evidence renders) every shown bar button is a 44 px tap target, the PC factor 0.8 included
		for _, name in ipairs(BAR) do
			local btn = bar and (bar:FindFirstChild(name) or bar:FindFirstChild(name, true))
			if btn and (btn:IsA("TextButton") or btn:IsA("ImageButton")) and G.shown(btn) then
				local s = btn.AbsoluteSize
				T.check(math.min(s.X, s.Y) >= 44 - 0.6, label .. ": " .. name .. " is a 44 px tap target", fmt("%.1fx%.1f", s.X, s.Y))
			end
		end
	end
	-- (review round 2) the roll's Skip chip (read during the roll) never sits under the reveal's SPIN AGAIN or DONE: the finger
	-- that skipped rests on "Tap to close" or the Dim, never on a paid button
	local function skipBox()
		local b = G.bar("Skip")
		return b and G.shown(b) and G.box(b) or nil
	end
	local function skipClear(label, rollSkip)
		local under = {}
		for _, name in ipairs({ "SpinAgain", "Done" }) do
			local b = G.bar(name)
			if not (b and G.shown(b)) then
				under[#under + 1] = name .. " missing"
			elseif rollSkip and G.intersects(rollSkip, G.box(b)) then
				local bb = G.box(b)
				under[#under + 1] = fmt("%s %.0f..%.0f", name, bb.x, bb.x + bb.w)
			end
		end
		T.check(rollSkip ~= nil and #under == 0, label .. ": the roll's Skip chip never sits under SPIN AGAIN or DONE",
			rollSkip and fmt("Skip %.0f..%.0f x %.0f..%.0f; %s", rollSkip.x, rollSkip.x + rollSkip.w, rollSkip.y, rollSkip.y + rollSkip.h, table.concat(under, ", ")) or "no Skip chip during the roll")
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
			local rollSkip1 = skipBox()
			RedoGeom.check(G.content(), label .. " x1 crack", { MinText = minText, NoOverlap = { "CrackWord", "Egg1", "Pedestal1", "Skip", "FastHatch" }, Skip = SKIP })
			local egg, ped, cw, title = G.hero("Egg1"), G.hero("Pedestal1"), G.hero("CrackWord"), G.content() and G.content():FindFirstChild("Title")
			if egg and ped then
				local e, p = G.box(egg), G.box(ped)
				local eh = G.eggH(egg)
				T.check(abs(p.w - 1.1 * eh) <= 1.5 and abs(p.h - 0.24 * eh) <= 1.5 and abs(p.y - (e.y + e.h)) <= 0.6, label .. " x1: the pedestal is 1.1 x / 0.24 x its egg, under it",
					fmt("egg %.1f, pedestal %.1fx%.1f at %.1f (egg bottom %.1f)", eh, p.w, p.h, p.y, e.y + e.h))
				if phone and w > h then
					local bar = G.content():FindFirstChild("BottomBar")
					T.check(eh >= 120 - 0.6 and eh <= 200 + 0.6, label .. " x1: the phone crack egg is 120 .. 200 px", fmt("%.1f", eh))
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
			skipClear(label .. " x1", rollSkip1)
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
			local rollSkip3 = skipBox()
			RedoGeom.check(G.content(), label .. " x3 crack", { MinText = minText, NoOverlap = { "CrackWord", "Egg1", "Egg2", "Egg3", "Pedestal1", "Pedestal2", "Pedestal3", "Skip", "FastHatch" }, Skip = SKIP })
			local ratios = true
			for j = 1, 3 do
				local e, p = G.hero("Egg" .. j), G.hero("Pedestal" .. j)
				if not (e and p and abs(p.AbsoluteSize.X - 1.1 * G.eggH(e)) <= 1.5 and abs(p.AbsoluteSize.Y - 0.24 * G.eggH(e)) <= 1.5) then
					ratios = false
				end
			end
			T.check(ratios, label .. " x3: every pedestal is 1.1 x / 0.24 x its egg")
			G.until_(t0, 3.2)
			T.eq(ES.Phase(), "Reveal", label .. " x3: the reveal")
			RedoGeom.check(G.content(), label .. " x3 reveal", { MinText = minText, NoOverlap = BAR, Skip = SKIP })
			bottomOk(label .. " x3 reveal", h)
			skipClear(label .. " x3", rollSkip3)
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
			realX3(label)
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
		-- (Task 27) and back to 844x390 during Crack (fast: the cracks start at 1.51 s): the dressed hero refits at once
		G.until_(t0, 1.6)
		T.eq(ES.Phase(), "Crack", "egg stage resize: cracking at 1.6 s (fast)")
		Mock.SetViewport(844, 390)
		G.advance(0.05)
		RedoGeom.check(G.content(), "egg stage resize: 844x390 during Crack", { MinText = 15, NoOverlap = { "CrackWord", "Egg1", "Egg2", "Egg3", "Pedestal1", "Pedestal2", "Pedestal3", "Skip", "FastHatch" },
			Skip = { Rays = true, Flash = true, Vignette = true, Sparks = true, Shock = true } })
		local refit = true
		for j = 1, 3 do
			local e, p = G.hero("Egg" .. j), G.hero("Pedestal" .. j)
			if not (e and p and abs(p.AbsoluteSize.X - 1.1 * G.eggH(e)) <= 1.5 and abs(p.AbsoluteSize.Y - 0.24 * G.eggH(e)) <= 1.5) then
				refit = false
			end
		end
		T.check(refit, "egg stage resize: during Crack every pedestal is again 1.1 x / 0.24 x its refitted egg")
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

----------------------------------------------------------------------------------------------------
-- client_egg_stage_wiring (Task 22: the Shop and the stage live together)
----------------------------------------------------------------------------------------------------
S.client_egg_stage_wiring = guarded("client_egg_stage_wiring", function()
	local KC = G.KC()
	local Config = KC.env()
	local ES = G.req("client/UI/EggStage")
	local SE = G.req("client/UI/ShopEggs")
	local Shop = G.req("client/Controllers/ShopController")
	local PC = G.req("shared/PetCatalog")
	local CS = G.req("client/ClientSettings")
	local ML = G.req("client/MouseLock")
	local MC = KC.M.MenuController or G.req("client/Controllers/MenuController")
	if not T.check(type(ES) == "table" and type(SE) == "table" and type(Shop) == "table" and type(MC) == "table" and type(PC) == "table",
		"egg wiring: EggStage, ShopEggs, ShopController and MenuController load") then
		return
	end
	local UIS = game:GetService("UserInputService")
	local IN_MATCH = Config.Attr.InMatch
	local oldVp = { Mock.Viewport.X, Mock.Viewport.Y }
	local keep = {}
	for _, name in ipairs({ Config.Attr.Tokens, Config.Attr.Gems, "PaidRandomItemsRestricted", "GemsSettled", "SecretPityLeft" }) do
		keep[name] = LocalPlayer:GetAttribute(name)
	end
	Mock.SetViewport(1920, 1080)
	LocalPlayer:SetAttribute(Config.Attr.Tokens, 50000)
	LocalPlayer:SetAttribute(Config.Attr.Gems, 5000)
	LocalPlayer:SetAttribute("PaidRandomItemsRestricted", false)
	LocalPlayer:SetAttribute("GemsSettled", true)
	LocalPlayer:SetAttribute("SecretPityLeft", 4)
	CS.Set("FastHatch", false)
	Shop.Close()
	MC.Close()
	if ES.IsShowing() then
		ES.Close()
	end
	if type(ES._S) == "table" then
		ES._S.Pending = false
		ES._S.PendToken = (ES._S.PendToken or 0) + 1
		ES._S.LastFire = -10
	end
	G.advance(0.6)
	local epic = PC.RarityPool("Cloud", "Epic")[1]
	local rare = PC.RarityPool("Cloud", "Rare")[1]
	local hints = {}
	local realHint = MC.Hint
	MC.Hint = function(text)
		hints[#hints + 1] = tostring(text)
	end
	local backs = 0
	local realBack = ES.Back
	ES.Back = function(...)
		backs = backs + 1
		return realBack(...)
	end
	local closed = {}
	local conn = ES.Closed:Connect(function(reason)
		closed[#closed + 1] = reason
	end)
	local function win()
		local pg = G.pg()
		local gui = pg and pg:FindFirstChild("NimbusShop")
		return gui and gui:FindFirstChild("ShopWindow") or nil
	end
	local function spinBtn(id, name)
		local w = win()
		local card = w and RedoGeom.find(w, "ShopCard_" .. id)
		return card and card:FindFirstChild(name or "Spin", true) or nil
	end
	local function buys(mark)
		return #KC.serverCalls("BuyRoulette", mark)
	end
	local function esc()
		Mock.FireSignal(UIS, "InputBegan", Mock.NewInput("Escape", "Keyboard", "Begin"), false)
		G.advance(STEP)
	end
	local function answer(pulls)
		KC.toClient("RouletteResult", G.result("Cloud", "Tokens", pulls or { G.pull(PC, "Cloud", epic) }))
		G.advance(STEP)
	end
	local function fail(reason)
		KC.toClient("RouletteResult", { Ok = false, Reason = reason or "Probe reason", RouletteId = "Cloud", Currency = "Tokens", Spins = 1 })
		G.advance(STEP)
	end
	local function states()
		local out = {}
		for _, id in ipairs({ "Secret", "Cloud", "Storm", "Sky", "Celestial" }) do
			out[#out + 1] = tostring(SE.CardState(id))
		end
		return table.concat(out, " ")
	end
	local snap0 = G.snapshot()
	local ok, err = pcall(function()
		------------------------------------------------------------------ a card tap plays the stage over a hidden Shop; DONE brings it back
		Shop.Open({ Tab = "Eggs" })
		G.advance(0.5)
		local mark = #Mock.RemoteLog
		Mock.Click(spinBtn("Cloud"))
		G.advance(STEP)
		local sent = KC.serverCalls("BuyRoulette", mark)
		T.check(#sent == 1 and sent[1].args[1] == "Cloud" and sent[1].args[2] == "Tokens" and sent[1].args[3] == 1, "egg wiring: a card tap sends BuyRoulette('Cloud', 'Tokens', 1)")
		answer()
		T.check(ES.IsShowing() and Shop.IsOpen() and not G.shown(win()), "egg wiring: a success RouletteResult plays the stage and hides ShopWindow (the Shop stays open)",
			tostring(ES.IsShowing()) .. " / open " .. tostring(Shop.IsOpen()) .. " / shown " .. tostring(G.shown(win())))
		-- the cursor: free over the reveal with mouse lock on
		local mlWas = ML and ML.IsEnabled() or false
		if ML then
			pcall(ML.Start)
			ML.SetEnabled(true)
			G.advance(0.2)
			T.check(not ML.IsLocked() and ML.Holds()["auto:NimbusHatch"] ~= nil, "egg wiring: with mouse lock on the cursor is free while the stage shows (a hold under auto:NimbusHatch)")
			T.check(ML.Holds()["auto:NimbusMenu"] == nil, "egg wiring: ...and nothing in NimbusMenu holds it (the old roulette stage is gone)")
		end
		-- the stage refuses every other window
		MC.Open("Stats")
		G.advance(0.3)
		local menu = G.pg():FindFirstChild("NimbusMenu")
		local stats = menu and menu:FindFirstChild("Window_Stats")
		T.check(not (stats and G.shown(stats)), "egg wiring: Stats refuses to open while the stage shows")
		MC.Open("Pets", {})
		G.advance(0.3)
		local PCtl = KC.M.PetsController or G.req("client/Controllers/PetsController")
		T.check(not (PCtl and PCtl.IsOpen()), "egg wiring: the Pets window refuses to open while the stage shows")
		MC.Open("Store", { Tab = "Passes" })
		G.advance(0.3)
		T.check(Shop.Tab() == "Eggs" and not G.shown(win()), "egg wiring: OpenPanel Store refuses while the stage shows (the Shop stays hidden on Eggs)", tostring(Shop.Tab()))
		T.check(Shop.Open({ Tab = "Gems" }) == false and not G.shown(win()), "egg wiring: ShopController.Open refuses while the stage shows")
		MC.Open("Index")
		G.advance(0.3)
		local IC = KC.M.IndexController or G.req("client/Controllers/IndexController")
		T.check(not (IC and type(IC.IsOpen) == "function" and IC.IsOpen()), "egg wiring: the Index refuses to open while the stage shows")
		-- Esc during the strip skips, Esc on the reveal is DONE: one handler (the Shop's, through EggStage.Back)
		G.advance(0.8)
		T.eq(ES.Phase(), "Strip", "egg wiring: the strip runs")
		backs = 0
		esc()
		T.check(ES.Phase() == "Reveal" and backs == 1, "egg wiring: Esc during the strip skips (one EggStage.Back)", tostring(ES.Phase()) .. ", backs " .. backs)
		G.advance(0.6)
		esc()
		T.check(not ES.IsShowing() and closed[#closed] == "Done" and backs == 2 and Shop.IsOpen() and G.shown(win()),
			"egg wiring: Esc on the reveal is DONE, and the Shop is then open and shown (exactly one Esc handler acted)", tostring(closed[#closed]) .. ", backs " .. backs .. ", shown " .. tostring(G.shown(win())))
		if ML then
			G.advance(0.2)
			T.check(not ML.IsLocked() and ML.Holds()["auto:NimbusHatch"] == nil, "egg wiring: ...the cursor is free over the Shop (the stage's hold is released)")
			ML.SetEnabled(mlWas)
			G.advance(0.2)
		end
		------------------------------------------------------------------ B: skip, then DONE; the Shop stays open
		G.advance(0.4)
		Mock.Click(spinBtn("Cloud"))
		G.advance(STEP)
		answer()
		G.advance(0.8)
		Mock.TriggerAction("NimbusHatchBack", "Begin")
		G.advance(STEP)
		T.eq(ES.Phase(), "Reveal", "egg wiring: B during the strip skips")
		G.advance(0.6)
		local res = Mock.TriggerAction("NimbusHatchBack", "Begin")
		G.advance(STEP)
		T.check(res == Enum.ContextActionResult.Sink and not ES.IsShowing() and Shop.IsOpen() and G.shown(win()), "egg wiring: B on the reveal is DONE through NimbusHatchBack and the Shop stays open")
		------------------------------------------------------------------ SPIN AGAIN and a card tap within 0.3 s: one request
		G.advance(0.4)
		Mock.Click(spinBtn("Cloud"))
		G.advance(STEP)
		answer()
		ES.Skip()
		G.advance(0.9) -- (review round 2: SPIN AGAIN arms 0.8 s into the reveal)
		local mA = #Mock.RemoteLog
		local again = G.bar("SpinAgain")
		Mock.Click(again)
		T.eq(buys(mA), 1, "egg wiring: (setup) the armed SPIN AGAIN sends its request")
		ES.Done()
		G.advance(STEP)
		T.check(G.shown(win()), "egg wiring: (setup) DONE after SPIN AGAIN shows the Shop")
		Mock.Click(spinBtn("Cloud"))
		G.advance(STEP)
		T.eq(buys(mA), 1, "egg wiring: SPIN AGAIN and a card tap within 0.3 s send one request")
		fail()
		G.advance(0.4)
		------------------------------------------------------------------ a match start during the roll
		Mock.Click(spinBtn("Cloud"))
		G.advance(STEP)
		answer({ G.pull(PC, "Cloud", epic), G.pull(PC, "Cloud", rare), G.pull(PC, "Cloud", epic) })
		G.advance(1)
		local hm = #hints
		LocalPlayer:SetAttribute(IN_MATCH, true)
		G.advance(0.2)
		local toasts = 0
		for k = hm + 1, #hints do
			if hints[k]:find("You hatched: ", 1, true) == 1 then
				toasts = toasts + 1
			end
		end
		T.check(not ES.IsShowing() and toasts == 1 and hints[#hints] == "You hatched: " .. epic.Name .. ", " .. rare.Name .. ", " .. epic.Name,
			"egg wiring: a match start closes the stage and one toast lists the pulls not shown", tostring(hints[#hints]))
		T.check(not Shop.IsOpen() and not G.shown(win()), "egg wiring: ...ShopWindow stays hidden and the Shop is closed (never shown over the match)")
		LocalPlayer:SetAttribute(IN_MATCH, nil)
		G.advance(0.4)
		T.check(not Shop.IsOpen() and not G.shown(win()), "egg wiring: ...and the match ending does not bring it back")
		------------------------------------------------------------------ MenuController.Close() during the roll
		Shop.Open({ Tab = "Eggs" })
		G.advance(0.5)
		Mock.Click(spinBtn("Cloud"))
		G.advance(STEP)
		answer()
		G.advance(1)
		local hc = #hints
		MC.Close()
		G.advance(0.2)
		T.check(not ES.IsShowing() and closed[#closed] == "Close" and #hints == hc + 1 and hints[#hints] == "You hatched: " .. epic.Name,
			"egg wiring: MenuController.Close() during the roll closes the stage with one toast", tostring(hints[#hints]))
		T.check(not Shop.IsOpen() and not G.shown(win()), "egg wiring: ...and the Shop is closed")
		------------------------------------------------------------------ a late answer after closing the Shop: Esc still skips / DONEs, opens nothing
		Shop.Open({ Tab = "Eggs" })
		G.advance(0.5)
		Mock.Click(spinBtn("Cloud"))
		G.advance(STEP)
		Shop.Close()
		G.advance(0.3)
		answer()
		G.advance(0.8)
		T.check(ES.IsShowing() and not Shop.IsOpen(), "egg wiring: a late answer plays the stage with the Shop closed")
		esc()
		T.eq(ES.Phase(), "Reveal", "egg wiring: ...Esc skips")
		G.advance(0.6)
		esc()
		T.check(not ES.IsShowing() and not Shop.IsOpen() and not G.shown(win()), "egg wiring: ...Esc on the reveal is DONE and opens nothing")
		------------------------------------------------------------------ close while pending (Review Focus 2), once per way of closing
		local ways = {
			{ "the X", function()
				local w = win()
				Mock.Click(w and RedoGeom.find(w, "CloseButton"))
				G.advance(0.3)
			end, "success" },
			{ "Esc", function()
				esc()
				G.advance(0.3)
			end, "failure" },
			{ "B (NimbusShopBack)", function()
				Mock.TriggerAction("NimbusShopBack", "Begin")
				G.advance(0.3)
			end, "timeout" },
			{ "InMatch set then cleared", function()
				LocalPlayer:SetAttribute(IN_MATCH, true)
				G.advance(0.3)
				LocalPlayer:SetAttribute(IN_MATCH, nil)
				G.advance(0.3)
			end, "success" },
		}
		for _, way in ipairs(ways) do
			local tag = "egg wiring: close while pending by " .. way[1]
			G.advance(0.4)
			Shop.Open({ Tab = "Eggs" })
			G.advance(0.4)
			local mP = #Mock.RemoteLog
			Mock.Click(spinBtn("Cloud"))
			G.advance(STEP)
			T.check(buys(mP) == 1 and ES.IsPending(), tag .. ": (setup) the tap is pending")
			way[2]()
			T.check(not Shop.IsOpen(), tag .. ": the Shop closed")
			Shop.Open({ Tab = "Eggs" })
			G.advance(0.4)
			local lit = 0
			for _, id in ipairs({ "Secret", "Cloud", "Storm", "Sky", "Celestial" }) do
				for _, name in ipairs({ "Spin", "Spin3", "SpinGems" }) do
					local b = spinBtn(id, name)
					if b and b:GetAttribute("Disabled") ~= true and b.Active ~= false then
						lit = lit + 1
					end
				end
			end
			T.check(states() == "Pending Pending Pending Pending Pending" and lit == 0, tag .. ": reopened, the cards stay Pending", states() .. ", " .. lit .. " lit")
			if way[3] == "success" then
				answer()
				T.check(ES.IsShowing() and not G.shown(win()), tag .. ": a success then plays")
				ES.Close()
				G.advance(0.3)
			elseif way[3] == "failure" then
				fail("Probe failure")
				T.check(states() == "Ready Ready Ready Ready Ready" and hints[#hints] == "Probe failure", tag .. ": a failure re-enables them", states())
			else
				G.advance(6.6)
				T.eq(states(), "Ready Ready Ready Ready Ready", tag .. ": no answer re-enables them at 7 s")
			end
			Shop.Close()
			G.advance(0.3)
		end
		local same, why = G.sameSnapshot(snap0, G.snapshot())
		T.check(same, "egg wiring: the Camera, the Humanoid and the touch controls are as they were", why)
	end)
	if not ok then
		T.fail("egg wiring: scenario error", tostring(err))
	end
	conn:Disconnect()
	ES.Back = realBack
	MC.Hint = realHint
	if ES.IsShowing() then
		ES.Close()
	end
	Shop.Close()
	LocalPlayer:SetAttribute(IN_MATCH, nil)
	for name, v in pairs(keep) do
		LocalPlayer:SetAttribute(name, v)
	end
	CS.Set("FastHatch", false)
	Mock.SetViewport(oldVp[1], oldVp[2])
	G.advance(0.6)
	KC.flushErrors("client_egg_stage_wiring")
end)

----------------------------------------------------------------------------------------------------
-- client_egg_vfx (Task 26, spec 16.5 "Where the VFX show" and the VFX column)
----------------------------------------------------------------------------------------------------
S.client_egg_vfx = guarded("client_egg_vfx", function()
	local KC = G.KC()
	local Config = KC.env()
	local EA = G.req("client/UI/EggArt")
	local FX = G.req("client/UI/HatchFx")
	local GQ = G.req("client/GraphicsQuality")
	local SE = G.req("client/UI/ShopEggs")
	local Shop = G.req("client/Controllers/ShopController")
	local MC = KC.M.MenuController or G.req("client/Controllers/MenuController")
	if not T.check(type(EA) == "table" and type(EA.SetVfx) == "function" and type(FX) == "table" and type(FX.Pool) == "function"
		and type(FX.Stars) == "function" and type(FX.Stats) == "function" and type(GQ) == "table" and type(SE) == "table" and type(SE.Fx) == "function"
		and type(Shop) == "table", "egg vfx: EggArt (SetVfx), client/UI/HatchFx (Pool, Stars, Stats), GraphicsQuality, ShopEggs (Fx) and ShopController load") then
		return
	end
	local oldVp = { Mock.Viewport.X, Mock.Viewport.Y }
	local oldEff = GQ.Effective
	local mode = "High"
	GQ.Effective = function()
		return mode
	end
	local keep = {}
	for _, name in ipairs({ Config.Attr.Tokens, Config.Attr.Gems, "PaidRandomItemsRestricted", "GemsSettled", "SecretPityLeft" }) do
		keep[name] = LocalPlayer:GetAttribute(name)
	end
	Mock.SetViewport(1920, 1080)
	G.advance(0.2)
	local hb0 = (FX.Stats().Heartbeats or 0)
	local gui, root = G.eggBoard("SmokeEggVfx")
	local okRun, errRun = pcall(function()
		------------------------------------------------------------------ an egg's VFX: Rare and up, <= 8 instances, <= 3 tweens
		local adds = T.tally("egg vfx: Vfx = true adds nothing on Common / Uncommon; on Rare .. Secret 1..8 instances and <= 3 tweens (Full 380 and Medium 104)", 4)
		for _, rarity in ipairs(RARITIES) do
			for _, size in ipairs({ 380, 104 }) do
				local plain = EA.New(root, rarity, size)
				local vfx = EA.New(root, rarity, size, { Vfx = true })
				G.advance(0.1)
				local extra = G.count(vfx) - G.count(plain)
				local tw = G.tweensUnder(vfx) - G.tweensUnder(plain)
				local low = rarity == "Common" or rarity == "Uncommon"
				local ok
				if low then
					ok = extra == 0 and tw == 0 and vfx:GetAttribute("Vfx") ~= true
				else
					ok = extra >= 1 and extra <= 8 and tw >= 0 and tw <= 3 and vfx:GetAttribute("Vfx") == true and vfx:FindFirstChild("Halo") ~= nil
				end
				adds:case(ok, fmt("%s %d: +%d instances, +%d tweens", rarity, size, extra, tw))
				plain:Destroy()
				vfx:Destroy()
			end
		end
		adds:report()
		-- the named effects: Epic flickers and twinkles, Legendary's rays turn, Mythic's ribbon drifts, Secret pulses and twinkles
		local want = { Epic = 2, Legendary = 2, Mythic = 1, Secret = 3 }
		for rarity, n in pairs(want) do
			local plain = EA.New(root, rarity, 380)
			local vfx = EA.New(root, rarity, 380, { Vfx = true })
			G.advance(0.1)
			T.eq(G.tweensUnder(vfx) - G.tweensUnder(plain), n, "egg vfx: a Full " .. rarity .. " egg's VFX plays " .. n .. " endless tweens")
			plain:Destroy()
			vfx:Destroy()
		end
		local leg = EA.New(root, "Legendary", 380, { Vfx = true })
		local rays = leg:FindFirstChild("Rays")
		local rayTw = nil
		for _, tw in ipairs(G.tweenList(leg)) do
			if tw.Instance == rays then
				rayTw = tw
			end
		end
		T.check(rays ~= nil and rayTw ~= nil and rayTw.TweenInfo.RepeatCount == -1 and (Mock.TweenGoals(rayTw).Rotation or 0) >= 360,
			"egg vfx: Legendary's soft rays turn behind the egg (an endless Rotation tween on Rays)")
		leg:Destroy()
		local sec = EA.New(root, "Secret", 380, { Vfx = true })
		T.check(sec:FindFirstChild("Aura") ~= nil and sec:FindFirstChild("Halo") ~= nil, "egg vfx: Secret has its violet Halo and the dark violet Aura ring")
		sec:Destroy()

		------------------------------------------------------------------ the sheen (Full, High only), Low graphics
		local full = EA.New(root, "Epic", 380)
		local sheenTw = nil
		for _, tw in ipairs(G.tweenList(full)) do
			if tw.Instance and tw.Instance.Parent and tw.Instance.Parent.Name == "Sheen" then
				sheenTw = tw
			end
		end
		local info = sheenTw and sheenTw.TweenInfo
		T.check(info ~= nil and info.RepeatCount == -1 and info.Time + info.DelayTime >= 3.5 and info.Time + info.DelayTime <= 4.5 and G.tweensUnder(full) == 1,
			"egg vfx: a Full egg's Sheen sweeps every ~4 s on High (one endless tween; nothing else without Vfx)",
			info and fmt("%.2f + %.2f, %d tweens", info.Time, info.DelayTime, G.tweensUnder(full)) or "no sheen tween")
		full:Destroy()
		mode = "Low"
		local lowOk = T.tally("egg vfx: Low graphics: Vfx = true adds nothing and no sheen plays (Full 380)", 4)
		for _, rarity in ipairs(RARITIES) do
			local plain = EA.New(root, rarity, 380)
			local vfx = EA.New(root, rarity, 380, { Vfx = true })
			G.advance(0.1)
			lowOk:case(G.count(vfx) == G.count(plain) and G.tweensUnder(vfx) == 0 and G.tweensUnder(plain) == 0 and vfx:GetAttribute("Vfx") ~= true,
				fmt("%s: %d vs %d instances, %d tweens", rarity, G.count(vfx), G.count(plain), G.tweensUnder(vfx)))
			plain:Destroy()
			vfx:Destroy()
		end
		lowOk:report()
		mode = "High"

		------------------------------------------------------------------ SetVfx off, destroy: the tweens stop
		local m = EA.New(root, "Mythic", 380)
		local n0 = G.count(m)
		EA.SetVfx(m, true)
		G.advance(0.1)
		local list = G.tweenList(m)
		T.check(G.count(m) > n0 and #list >= 2, "egg vfx: SetVfx(egg, true) adds the VFX to a built egg", fmt("%d -> %d, %d tweens", n0, G.count(m), #list))
		EA.SetVfx(m, false)
		G.advance(0.1)
		local stillOn = 0
		for _, tw in ipairs(list) do
			if tw.PlaybackState == Enum.PlaybackState.Playing then
				stillOn = stillOn + 1
			end
		end
		T.check(G.count(m) == n0 and stillOn == 0 and G.tweensUnder(m) == 0, "egg vfx: SetVfx(egg, false) makes the egg still: the VFX gone (the count back), every tween stopped (the sheen too)",
			fmt("%d (was %d), %d tweens on", G.count(m), n0, stillOn))
		local still = EA.New(root, "Rare", 380, { Still = true })
		G.advance(0.1)
		T.check(G.tweensUnder(still) == 0, "egg vfx: opts.Still builds a Full egg with no tween (the Shop's hero egg waits for its page to show)")
		still:Destroy()
		EA.SetVfx(m, true)
		G.advance(0.1)
		list = G.tweenList(m)
		m:Destroy()
		G.advance(0.1)
		local live = 0
		for _, tw in ipairs(list) do
			if tw.PlaybackState == Enum.PlaybackState.Playing then
				live = live + 1
			end
		end
		T.check(#list >= 2 and live == 0, "egg vfx: destroying a Vfx egg stops every tween it played (the sheen too)", fmt("%d tweens, %d still playing", #list, live))

		------------------------------------------------------------------ HatchFx: the pool, the ambient sparkles, the stars
		local holder = Instance.new("Frame")
		holder.Name = "FxHolder"
		holder.BackgroundTransparency = 1
		holder.Position = UDim2.fromOffset(200, 120)
		holder.Size = UDim2.fromOffset(700, 700)
		holder.Parent = root
		local pool = FX.Pool(holder, 16)
		local spawned = pool:Burst(Vector2.new(350, 350), "Epic", 28)
		G.advance(1 / 30)
		local st = FX.Stats()
		T.check(pool:Live() == 16 and spawned == 16 and st.Heartbeats == hb0 + 1 and st.Pooled >= 16, "egg vfx: a 16-pool's Burst of 28 lights 16 sparks under one Heartbeat",
			fmt("live %d, spawned %s, hb %d, pooled %d", pool:Live(), tostring(spawned), st.Heartbeats, st.Pooled))
		local most = 0
		for _ = 1, 30 do
			G.advance(0.1)
			most = math.max(most, pool:Live())
		end
		T.check(most <= 16 and pool:Live() == 0 and FX.Stats().Heartbeats == hb0, "egg vfx: the sparks fade, return to the pool and the Heartbeat disconnects",
			fmt("most %d, live %d, hb %d", most, pool:Live(), FX.Stats().Heartbeats))
		mode = "Low"
		pool:Burst(Vector2.new(350, 350), "Rare", 8)
		G.advance(1 / 30)
		T.eq(pool:Live(), 4, "egg vfx: Low graphics halves a burst (8 -> 4)")
		G.advance(3)
		local amb = EA.New(holder, "Mythic", 160, { Vfx = true })
		amb.Position = UDim2.fromOffset(286, 270)
		pool:Ambient(amb, "Mythic")
		G.advance(2)
		T.check(pool:Live() == 0 and FX.Stats().Heartbeats == hb0, "egg vfx: Low graphics: no ambient sparkles, no Heartbeat", fmt("live %d", pool:Live()))
		mode = "High"
		pool:SetRunning(false)
		pool:SetRunning(true)
		local peak = 0
		for _ = 1, 30 do
			G.advance(0.1)
			peak = math.max(peak, pool:Live())
		end
		T.check(peak >= 1 and peak <= 6 and pool:Live() >= 1 and FX.Stats().Heartbeats == hb0 + 1, "egg vfx: Ambient keeps Mythic's 6 pastel sparkles (at most) drifting around the egg on High",
			fmt("peak %d, live %d", peak, pool:Live()))
		local near = true
		for _, d in ipairs(holder:GetDescendants()) do
			if d:IsA("GuiObject") and d.Visible and d.Parent and d.Parent.Name == "Sparks" then
				local c = d.AbsolutePosition + d.AbsoluteSize / 2
				local e = amb.AbsolutePosition + amb.AbsoluteSize / 2
				if (c - e).Magnitude > 160 then
					near = false
				end
			end
		end
		T.check(near, "egg vfx: ...within one egg height of the egg's centre")
		pool:SetRunning(false)
		G.advance(0.1)
		T.check(pool:Live() == 0 and FX.Stats().Heartbeats == hb0, "egg vfx: SetRunning(false) returns every spark and drops the Heartbeat", fmt("live %d, hb %d", pool:Live(), FX.Stats().Heartbeats))
		pool:SetRunning(true)
		G.advance(1.5)
		local before = pool:Live()
		amb:Destroy()
		G.advance(0.2)
		T.check(before >= 1 and pool:Live() == 0 and FX.Stats().Heartbeats == hb0, "egg vfx: destroying the egg returns its sparks and stops the Heartbeat", fmt("%d -> %d live", before, pool:Live()))
		pool:Destroy()
		T.check(holder:FindFirstChild("Sparks") == nil and FX.Stats().Heartbeats == hb0, "egg vfx: pool:Destroy() removes its frames")
		local stars = FX.Stars(holder, 14)
		G.advance(0.2)
		local starFrames = 0
		for _, d in ipairs(stars.Frame:GetChildren()) do
			if d:IsA("GuiObject") then
				starFrames = starFrames + 1
			end
		end
		T.check(starFrames == 14 and G.tweensUnder(stars.Frame) == 14 and FX.Stats().Tweens >= 14, "egg vfx: Stars(parent, 14) -> 14 star frames, each twinkling (14 tweens)",
			fmt("%d frames, %d tweens", starFrames, G.tweensUnder(stars.Frame)))
		local starList = G.tweenList(stars.Frame)
		stars.Destroy()
		G.advance(0.1)
		local on = 0
		for _, tw in ipairs(starList) do
			if tw.PlaybackState == Enum.PlaybackState.Playing then
				on = on + 1
			end
		end
		T.check(on == 0 and holder:FindFirstChild("Stars") == nil, "egg vfx: the stars' Destroy stops their tweens and removes them")

		------------------------------------------------------------------ the Shop page (spec 16.5: the Secret hero's big egg, the page's pool)
		LocalPlayer:SetAttribute(Config.Attr.Tokens, 50000)
		LocalPlayer:SetAttribute(Config.Attr.Gems, 5000)
		LocalPlayer:SetAttribute("PaidRandomItemsRestricted", false)
		LocalPlayer:SetAttribute("GemsSettled", true)
		LocalPlayer:SetAttribute("SecretPityLeft", 4)
		if MC and MC.Close then
			MC.Close()
		end
		Shop.Open({ Tab = "Eggs" })
		G.advance(1)
		local shopGui = G.pg():FindFirstChild("NimbusShop")
		local page = shopGui and shopGui:FindFirstChild("Page_Eggs", true)
		local fx = page and SE.Fx(page)
		local hero = page and page:FindFirstChild("ShopCard_Secret", true)
		local egg = hero and hero:FindFirstChild("HeroEgg", true)
		if T.check(fx ~= nil and fx.Pool ~= nil and egg ~= nil and fx.Egg == egg, "egg vfx: the Eggs page owns a HatchFx pool and the hero card's HeroEgg") then
			T.check(G.shown(egg) and egg:GetAttribute("Rarity") == "Secret" and egg:GetAttribute("Form") == "Full" and egg:GetAttribute("Vfx") == true and egg:FindFirstChild("Aura") ~= nil,
				"egg vfx: the Secret hero's big egg: Full, with its VFX, shown on PC", fmt("%s %s %s", tostring(egg:GetAttribute("Form")), tostring(egg:GetAttribute("Vfx")), tostring(G.shown(egg))))
			local most2 = 0
			for _ = 1, 30 do
				G.advance(0.1)
				most2 = math.max(most2, fx.Pool:Live())
			end
			T.check(most2 >= 1 and most2 <= 16 and FX.Stats().Heartbeats == hb0 + 1, "egg vfx: the page's pool keeps the hero egg's sparkles (never over 16) under one Heartbeat while the page shows",
				fmt("most %d, hb %d", most2, FX.Stats().Heartbeats))
			local domes = 0
			for _, d in ipairs(page:GetDescendants()) do
				if d.Name == "GlassSheen" and d:IsA("UIGradient") and G.tweensUnder(d) == 1 then
					domes = domes + 1
				end
			end
			T.eq(domes, 5, "egg vfx: every machine dome's glass carries a slow sheen while the page shows (High)")
			Shop.Open({ Tab = "Gems" })
			G.advance(0.3)
			T.check(fx.Pool:Live() == 0 and FX.Stats().Heartbeats == hb0 and G.tweensUnder(page) == 0, "egg vfx: on another tab the page's pool stops (no live spark, no Heartbeat) and its tweens stop",
				fmt("live %d, hb %d, tweens %d", fx.Pool:Live(), FX.Stats().Heartbeats, G.tweensUnder(page)))
			Shop.Open({ Tab = "Eggs" })
			G.advance(2)
			T.check(fx.Pool:Live() >= 1 and FX.Stats().Heartbeats == hb0 + 1, "egg vfx: back on Eggs the sparkles come back")
			Shop.Close()
			G.advance(0.3)
			T.check(fx.Pool:Live() == 0 and FX.Stats().Heartbeats == hb0 and G.tweensUnder(shopGui) == 0, "egg vfx: the Shop closed: no spark, no Heartbeat, no tween under NimbusShop",
				fmt("live %d, hb %d, tweens %d", fx.Pool:Live(), FX.Stats().Heartbeats, G.tweensUnder(shopGui)))
			mode = "Low"
			Shop.Open({ Tab = "Eggs" })
			G.advance(2)
			T.check(fx.Pool:Live() == 0 and FX.Stats().Heartbeats == hb0 and egg:GetAttribute("Vfx") ~= true and G.tweensUnder(shopGui) == 0,
				"egg vfx: Low graphics: the page shows no sparkle, no VFX, no tween", fmt("live %d, tweens %d", fx.Pool:Live(), G.tweensUnder(shopGui)))
			Shop.Close()
			mode = "High"
			G.advance(0.3)
			Mock.SetViewport(844, 390)
			G.advance(0.6)
			Shop.Open({ Tab = "Eggs" })
			G.advance(1)
			T.check(not G.shown(egg) and fx.Pool:Live() == 0 and FX.Stats().Heartbeats == hb0, "egg vfx: phone: the hero card has no room for the big egg (hidden, no sparkle)")
			Shop.Close()
			Mock.SetViewport(1920, 1080)
			G.advance(0.6)
		end
		-- census: the old gem glyph nowhere in the Shop or on the egg boards
		Shop.Open({ Tab = "Eggs" })
		G.advance(0.5)
		local glyphs = G.glyphs(shopGui)
		for _, n in ipairs(G.glyphs(gui)) do
			glyphs[#glyphs + 1] = n
		end
		T.check(#glyphs == 0, "egg vfx: census: no old gem glyph (\\226\\151\\134) in the Shop or on the egg boards", table.concat(glyphs, ", "))
		Shop.Close()
	end)
	GQ.Effective = oldEff
	pcall(function()
		Shop.Close()
	end)
	gui:Destroy()
	for name, v in pairs(keep) do
		LocalPlayer:SetAttribute(name, v)
	end
	Mock.SetViewport(oldVp[1], oldVp[2])
	G.advance(0.6)
	T.check(okRun, "egg vfx: the scenario body ran", tostring(errRun))
	KC.flushErrors("client_egg_vfx")
end)

----------------------------------------------------------------------------------------------------
-- client_hatch_cutscene (Task 27, spec 16.4 storyboard A "Pedestal" + the owner's pick: Gemini's cloud ring; the egg
-- sound keys of .superpowers/lobby-shop/pitch/CUTSCENE_PICK.md)
----------------------------------------------------------------------------------------------------
-- (EGG_SOUNDS and zeroEggIds: above client_egg_stage)
local SPARKS = { Common = 12, Uncommon = 16, Rare = 20, Epic = 28, Legendary = 40, Mythic = 48, Secret = 48 }
S.client_hatch_cutscene = guarded("client_hatch_cutscene", function()
	local KC = G.KC()
	local Config = KC.env()
	local ES = G.req("client/UI/EggStage")
	local FX = G.req("client/UI/HatchFx")
	local GQ = G.req("client/GraphicsQuality")
	local LS = G.req("client/LightingStack")
	local SF = G.req("client/SoundFx")
	local CS = G.req("client/ClientSettings")
	local ML = G.req("client/MouseLock")
	local PC = G.req("shared/PetCatalog")
	local Shop = G.req("client/Controllers/ShopController")
	local MC = KC.M.MenuController or G.req("client/Controllers/MenuController")
	local okFx = type(FX) == "table"
	for _, fn in ipairs({ "Pool", "Rays", "Shock", "Cracks", "Leaks", "Stars", "Dim", "CloudRing", "Stats" }) do
		okFx = okFx and type(FX[fn]) == "function"
	end
	if not T.check(okFx, "hatch cutscene: client/UI/HatchFx has Pool, Rays, Shock, Cracks, Leaks, Stars, Dim, CloudRing and Stats (spec 16.4 + the cloud ring)") then
		return
	end
	if not T.check(type(ES) == "table" and type(GQ) == "table" and type(LS) == "table" and type(SF) == "table" and type(Shop) == "table" and type(MC) == "table",
		"hatch cutscene: EggStage, GraphicsQuality, LightingStack, SoundFx, ShopController and MenuController load") then
		return
	end
	local Lighting = game:GetService("Lighting")
	local GuiService = game:GetService("GuiService")
	local IN_MATCH = Config.Attr.InMatch
	local oldVp = { Mock.Viewport.X, Mock.Viewport.Y }
	local keep = {}
	for _, name in ipairs({ Config.Attr.Tokens, Config.Attr.Gems, "PaidRandomItemsRestricted", "GemsSettled", "SecretPityLeft" }) do
		keep[name] = LocalPlayer:GetAttribute(name)
	end
	Mock.SetViewport(1920, 1080)
	LocalPlayer:SetAttribute(Config.Attr.Tokens, 50000)
	LocalPlayer:SetAttribute(Config.Attr.Gems, 5000)
	LocalPlayer:SetAttribute("PaidRandomItemsRestricted", false)
	LocalPlayer:SetAttribute("GemsSettled", true)
	LocalPlayer:SetAttribute("SecretPityLeft", 4)
	CS.Set("FastHatch", false)
	Shop.Close()
	if ES.IsShowing() then
		ES.Close()
	end
	G.advance(0.6)
	-- graphics: High unless a step says Low
	local oldEff = GQ.Effective
	local mode = "High"
	GQ.Effective = function()
		return mode
	end
	-- the world's colour correction (LightingStack's "ColorCorrection" target): one exists before the roll
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	local madeCC = false
	if not cc then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "SmokeHatchCC"
		cc.Brightness, cc.Saturation = 0.02, 0.1
		cc.Parent = Lighting
		madeCC = true
	end
	local function ccCount()
		local n = 0
		for _, c in ipairs(Lighting:GetChildren()) do
			if c:IsA("ColorCorrectionEffect") then
				n = n + 1
			end
		end
		return n
	end
	-- sounds: spied (name, scale), each play answered with a real Sound that plays until stopped
	local sounds = {}
	local realPlay = SF.Play
	local box = Instance.new("Folder")
	box.Name = "SmokeHatchSounds"
	box.Parent = game:GetService("SoundService")
	SF.Play = function(name, opts)
		local s = Instance.new("Sound")
		s.Name = tostring(name)
		s.Parent = box
		s:Play()
		sounds[#sounds + 1] = { name = name, scale = opts and opts.Scale, sound = s }
		return s
	end
	local function soundsFrom(i)
		local out = {}
		for k = i + 1, #sounds do
			out[#out + 1] = sounds[k]
		end
		return out
	end
	local function count(list, name, scale)
		local n = 0
		for _, s in ipairs(list) do
			if s.name == name and (scale == nil or (s.scale ~= nil and abs(s.scale - scale) < 1e-9)) then
				n = n + 1
			end
		end
		return n
	end
	local closed = {}
	local closedConn = ES.Closed:Connect(function(reason)
		closed[#closed + 1] = reason
	end)
	local function lastOf(list)
		return list[#list]
	end
	local hb0 = FX.Stats().Heartbeats or 0
	local live0 = FX.Stats().Live or 0
	local pick = function(rid, rarity)
		return PC.RarityPool(rid, rarity)[1]
	end
	local epic, rare, common = pick("Cloud", "Epic"), pick("Cloud", "Rare"), pick("Cloud", "Common")
	local leg, myth, secret = pick("Storm", "Legendary"), pick("Secret", "Mythic"), pick("Secret", "Secret")
	if not T.check(epic and rare and common and leg and myth and secret, "hatch cutscene: a Common, Rare, Epic, Legendary, Mythic and Secret pet to roll") then
		return
	end
	local function stageChild(name)
		local gui = G.gui()
		local stage = gui and gui:FindFirstChild("Stage")
		return stage and stage:FindFirstChild(name) or nil
	end
	local function flashKind()
		local f = stageChild("Flash")
		if not f or not G.shown(f) or f.BackgroundTransparency >= 0.97 then
			return nil
		end
		return G.rgb(f.BackgroundColor3, 242, 182, 68) and "gold" or "white"
	end
	local function segs(egg)
		local holder = egg and egg:FindFirstChild("Cracks")
		local n = 0
		for _, c in ipairs(holder and holder:GetChildren() or {}) do
			if c.Name:match("^Seg%d+$") and c.Visible then
				n = n + 1
			end
		end
		return n
	end
	local function hasHatch()
		for _, id in ipairs(LS.Ids()) do
			if id == "Hatch" then
				return true
			end
		end
		return false
	end
	local function blur()
		return Lighting:FindFirstChild("NimbusHatchBlur")
	end
	local function burstFrame()
		local c = G.content()
		return c and c:FindFirstChild("Burst") or nil
	end
	local function confetti()
		local n = 0
		local b = burstFrame()
		for _, d in ipairs(b and b:GetDescendants() or {}) do
			if d.Name == "Confetti" and d:IsA("GuiObject") and d.Visible then
				n = n + 1
			end
		end
		return n
	end
	local function spinning(inst)
		for _, tw in ipairs(inst and G.tweenList(inst) or {}) do
			if tw.Instance == inst and tw.TweenInfo.RepeatCount == -1 and (Mock.TweenGoals(tw).Rotation or 0) >= 360 then
				return true
			end
		end
		return false
	end
	-- the budgets at one moment (spec 16.4: x1 450 / x3 750 instances, 24 tweens + the Secret stars, 1 Heartbeat, 1 Lighting
	-- effect + the "Hatch" preset); -> a failure text or nil
	local function overBudget(cap, stars)
		local st, fx = ES.Stats(), FX.Stats()
		local gui = G.gui()
		local tw = gui and G.tweensUnder(gui) or 0
		local bad = {}
		if (st.Instances or 0) > cap then
			bad[#bad + 1] = "instances " .. st.Instances
		end
		if tw > 24 + (stars or 0) or (st.Tweens or 0) > 24 + (stars or 0) then
			bad[#bad + 1] = fmt("tweens %d (stage %d)", tw, st.Tweens or 0)
		end
		if (st.Heartbeats or 0) > 1 or (fx.Heartbeats or 0) > hb0 then
			bad[#bad + 1] = fmt("heartbeats %d / fx %d", st.Heartbeats or 0, fx.Heartbeats or 0)
		end
		if (st.Effects or 0) > 2 or ccCount() ~= 1 then
			bad[#bad + 1] = fmt("effects %d, colour corrections %d", st.Effects or 0, ccCount())
		end
		if (st.Sparks or 0) > 64 then
			bad[#bad + 1] = "sparks " .. st.Sparks
		end
		return #bad > 0 and table.concat(bad, ", ") or nil
	end
	local function afterDone(label, b0, s0)
		G.advance(0.45)
		G.zeroStats(ES, label)
		local fx = FX.Stats()
		T.check(blur() == nil and not hasHatch() and ccCount() == 1, label .. ": no NimbusHatchBlur in Lighting, \"Hatch\" gone from the LightingStack, no colour correction added")
		T.check(abs(cc.Brightness - b0) < 1e-3 and abs(cc.Saturation - s0) < 1e-3, label .. ": the colour correction is back to its values before the roll",
			fmt("%.3f / %.3f (was %.3f / %.3f)", cc.Brightness, cc.Saturation, b0, s0))
		T.check((fx.Live or 0) == live0 and (fx.Heartbeats or 0) == hb0, label .. ": every spark back, no live Heartbeat", fmt("live %d, hb %d", fx.Live or 0, fx.Heartbeats or 0))
	end
	-- plays a roll to `untilT` s, sampling every frame: -> rec
	local function watch(result, untilT, cap, stars, onStep)
		local rec = { at = {}, order = {}, over = nil, gold = {}, white = {}, flashPrev = nil }
		ES.Show(result)
		local t0 = os.clock()
		rec.t0 = t0
		while os.clock() - t0 < untilT - 1e-6 do
			local t = os.clock() - t0
			local ph = ES.Phase()
			if ph and rec.at[ph] == nil then
				rec.at[ph] = t
				rec.order[#rec.order + 1] = ph
			end
			local kind = flashKind()
			if kind and kind ~= rec.flashPrev then
				local list = kind == "gold" and rec.gold or rec.white
				list[#list + 1] = t
			end
			rec.flashPrev = kind
			if ph and not rec.over then
				local o = overBudget(cap, stars)
				if o then
					rec.over = fmt("%s at %.2f s (%s)", o, t, ph)
				end
			end
			if onStep then
				onStep(t, ph, rec)
			end
			G.advance(STEP)
		end
		return rec
	end
	local function result(rid, currency, defs)
		local pulls = {}
		for i, def in ipairs(defs) do
			pulls[i] = G.pull(PC, rid, def)
		end
		return G.result(rid, currency, pulls)
	end
	-- the real egg ids, put back after the scenario whatever happens (steps zero them or give fake ones)
	local realEggIds = {}
	for key in pairs(EGG_SOUNDS) do
		realEggIds[key] = Config.Audio.Sfx[key]
	end
	local ok, err = pcall(function()
		------------------------------------------------------------------ x1 Epic, High: the seven phases dressed
		local b0, s0 = cc.Brightness, cc.Saturation
		local cc0 = ccCount()
		-- the id-0 world for this first roll (the egg ids are uploaded; zeroed here, put back after the roll): today's sounds
		local restoreIds = zeroEggIds(Config)
		local s1 = #sounds
		local seen = { dimStart = nil, intro = false, rise = false, cracks = {}, rot = false, push = 1, word = nil, leaks = 0, ring = false }
		local burstAt, burstChecked = nil, false
		local rec = watch(result("Cloud", "Tokens", { epic }), 6.6, 450, 0, function(t, ph)
			local hero = function(name)
				return G.hero(name)
			end
			if seen.dimStart == nil then
				local dim = stageChild("Dim")
				seen.dimStart = dim and dim.BackgroundTransparency or -1
			end
			if not seen.intro and t >= 0.5 then
				seen.intro = true
				local dim, b = stageChild("Dim"), blur()
				T.check(dim ~= nil and seen.dimStart > 0.9 and abs(dim.BackgroundTransparency - 0.45) < 0.02, "hatch cutscene: Intro: the navy Dim fades in (0 -> 0.55)",
					fmt("%.2f -> %.2f", seen.dimStart, dim and dim.BackgroundTransparency or -1))
				T.check(b ~= nil and b:IsA("BlurEffect") and abs(b.Size - 14) < 0.01, "hatch cutscene: Intro: Lighting.NimbusHatchBlur reaches Size 14", b and tostring(b.Size) or "no blur")
				T.check(hasHatch() and ccCount() == cc0, "hatch cutscene: Intro: the \"Hatch\" LightingStack preset is pushed and Lighting holds exactly the colour corrections it held before (none added)")
				T.check(abs(cc.Brightness - (b0 - 0.08)) < 0.005 and abs(cc.Saturation - (s0 - 0.25)) < 0.005, "hatch cutscene: Intro: the tint reaches Brightness -0.08 / Saturation -0.25 under the values before the roll",
					fmt("%.3f / %.3f (from %.3f / %.3f)", cc.Brightness, cc.Saturation, b0, s0))
				local vig = stageChild("Vignette")
				local edges = 0
				for _, e in ipairs(vig and vig:GetChildren() or {}) do
					if e:IsA("Frame") and e.BackgroundTransparency < 0.5 then
						edges = edges + 1
					end
				end
				T.eq(edges, 4, "hatch cutscene: Intro: the four Vignette edges have faded in")
				local strip = G.content() and G.content():FindFirstChild("Strip1", true)
				T.check(strip ~= nil and strip:FindFirstChild("Streaks") ~= nil, "hatch cutscene: Strip: soft speed streaks over the track (High)")
			end
			local egg = hero("Egg1")
			if ph == "Rise" or (ph == "Crack" and not seen.rise) then
				if ph == "Crack" and not seen.rise then
					seen.rise = true
					T.check(G.shown(hero("Spot")) and G.shown(hero("Pedestal1")) and G.shown(hero("Backlight1")), "hatch cutscene: Rise: the Spot cone, Pedestal1 and the rarity Backlight1 are shown")
					T.check(egg ~= nil and egg:GetAttribute("Size") == 380 and egg:GetAttribute("Form") == "Full" and egg:GetAttribute("Vfx") == true,
						"hatch cutscene: Rise: Egg1 is the 380 px Full egg with its VFX", egg and fmt("%s %s %s", tostring(egg:GetAttribute("Size")), tostring(egg:GetAttribute("Form")), tostring(egg:GetAttribute("Vfx"))) or "no egg")
					local ring = hero("CloudRing1")
					seen.ring = ring ~= nil and G.shown(ring) and ring:IsA("CanvasGroup") and spinning(ring)
					T.check(seen.ring, "hatch cutscene: Rise: the rotating cloud ring (CloudRing1, one CanvasGroup) stands behind the pedestal (the owner's pick: Gemini's ring)")
					local ped = hero("Pedestal1")
					local inside = ped ~= nil
					for _, d in ipairs(ped and ped:GetDescendants() or {}) do
						if d:IsA("GuiObject") then
							local a, p = G.box(d), G.box(ped)
							if a.x < p.x - 0.6 or a.y < p.y - 0.6 or a.x + a.w > p.x + p.w + 0.6 or a.y + a.h > p.y + p.h + 0.6 then
								inside = false
							end
						end
					end
					local drawn = false
						for _, d in ipairs(ped and ped:GetDescendants() or {}) do
							if d:IsA("GuiObject") then
								drawn = true
							end
						end
						T.check(inside and not drawn and ped.BackgroundTransparency == 1, "hatch cutscene: Pedestal1 is an empty layout box: no drum, puffs or bars drawn under the pet (owner 2026-11-08)")
				end
			end
			if ph == "Crack" and egg then
				local n = segs(egg)
				if n > 0 and seen.cracks[#seen.cracks] ~= n then
					seen.cracks[#seen.cracks + 1] = n
				end
				if abs(egg.Rotation) > 0.5 then
					seen.rot = true
				end
				local pop = egg:FindFirstChild("Pop")
				if pop then
					seen.push = math.max(seen.push, pop.Scale)
				end
				local lk = egg:FindFirstChild("Leaks")
				if lk then
					local m = 0
					for _, c in ipairs(lk:GetChildren()) do
						if c.Visible and c.Name:match("^Leak%d+$") then
							m = m + 1
						end
					end
					seen.leaks = math.max(seen.leaks, m)
				end
				local cw = hero("CrackWord")
				if seen.word == nil and cw and G.shown(cw) then
					seen.word = cw.Text
				end
			end
			local burst = burstFrame()
			local shock = burst and burst:FindFirstChild("Shock")
			if egg and egg:GetAttribute("State") == "Burst" and burstAt == nil then
				burstAt = t
				seen.shock0 = shock and shock.AbsoluteSize.X or -1
				seen.sparks = burst and burst:GetAttribute("Sparks")
				seen.live = ES.Stats().Sparks
				seen.rays = G.shown(hero("Rays"))
				local ring = hero("CloudRing1")
				local swell = ring and ring:FindFirstChildOfClass("UIScale")
				seen.ringColor = ring and ring.GroupColor3
				seen.swellGoal = 1
				for _, tw in ipairs(ring and G.tweenList(ring) or {}) do
					if tw.Instance == swell then
						seen.swellGoal = Mock.TweenGoals(tw).Scale or 1
					end
				end
			end
			if burstAt and not burstChecked and t >= burstAt + 0.15 then
				burstChecked = true
				-- (the mock's tweens jump to their goals when they end: the Size tween's goal is the ring it grows to)
				local grow = shock and shock.AbsoluteSize.X or -1
				for _, tw in ipairs(shock and G.tweenList(shock) or {}) do
					local goal = tw.Instance == shock and Mock.TweenGoals(tw).Size
					if goal then
						grow = math.max(grow, goal.X.Offset)
					end
				end
				seen.shock1 = grow
			end
		end)
		T.eq(table.concat(rec.order, " "), "Intro Strip Land Rise Crack Burst Reveal", "hatch cutscene: x1 Epic runs the seven phases")
		T.check(rec.at.Reveal and abs(rec.at.Reveal - 5.75) <= 0.1, "hatch cutscene: x1 Reveal at 5.75 +- 0.1 s", tostring(rec.at.Reveal))
		T.eq(seen.word, "EPIC EGG!", "hatch cutscene: Crack: CrackWord reads 'EPIC EGG!'")
		T.check(seen.rot, "hatch cutscene: Crack: Egg1.Rotation leaves 0 during the shakes")
		T.eq(table.concat(seen.cracks, " "), "1 3 5", "hatch cutscene: Crack: the glowing Cracks grow 1 -> 3 -> 5 segments")
		T.check(seen.leaks >= 3 and seen.leaks <= 5, "hatch cutscene: Crack: thin Leaks of light lengthen from the cracks (<= 5)", tostring(seen.leaks))
		T.check(seen.push > 1.01 and seen.push <= 1.06 + 1e-6, "hatch cutscene: Crack: the push-in (the hero egg's UIScale) peaks above 1 and at most 1.06", fmt("%.4f", seen.push))
		T.check(burstAt ~= nil and seen.shock1 ~= nil and seen.shock1 > seen.shock0, "hatch cutscene: Burst: the Shock ring grows", fmt("%s -> %s", tostring(seen.shock0), tostring(seen.shock1)))
		T.check(seen.rays == true, "hatch cutscene: Burst: the Rays flash in")
		T.check(seen.sparks == SPARKS.Epic and (seen.live or 0) >= SPARKS.Epic, "hatch cutscene: Burst: 28 sparks for an Epic", fmt("burst %s, live %s", tostring(seen.sparks), tostring(seen.live)))
		T.check(G.same(seen.ringColor, G.rarityColor(Config, "Epic")) and seen.swellGoal >= 1.3, "hatch cutscene: Burst: the cloud ring swells sharply and pulses in the rarity colour",
			fmt("goal %.2f", seen.swellGoal or -1))
		T.check(#rec.white >= 1 and #rec.gold == 0, "hatch cutscene: Burst: the white micro-flash, no gold Flash for an Epic", fmt("white %d, gold %d", #rec.white, #rec.gold))
		T.check(rec.over == nil, "hatch cutscene: x1 Epic within the budgets at every phase (450 instances, 24 tweens, 1 Heartbeat, blur + preset)", tostring(rec.over))
		local word, pet = G.colPart(1, "Word"), G.colPart(1, "Pet")
		local pop = pet and pet:FindFirstChild("Pop")
		T.eq(word and word.Text, "EPIC!", "hatch cutscene: Reveal: the Banner's Word reads 'EPIC!'")
		T.check(pop ~= nil and abs(pop.Scale - 1) < 1e-6, "hatch cutscene: Reveal: the pet's pop UIScale ends at 1", pop and tostring(pop.Scale) or "no Pop")
		T.check(not G.shown(G.hero("Rays")), "hatch cutscene: Reveal: an Epic keeps no rays (only Legendary and up)")
		local list = soundsFrom(s1)
		T.check(count(list, "SpinStart", 0.6) == 1 and count(list, "SpinTick") >= 8 and count(list, "SpinLand", 0.6) == 1 and count(list, "Shatter", 0.6) == 1 and count(list, "RevealRare", 0.6) == 1,
			"hatch cutscene: with no egg ids the roll plays today's sounds (SpinStart, SpinTick, SpinLand, Shatter, RevealRare at 0.6)")
		-- (review round 1) the tick is throttled to 12 a second (spec 16.4): at most ceil(12 x Strip) + 1 over the strip
		local tickCap = math.ceil(12 * ES.Timings(false, 1).Strip) + 1
		T.check(count(list, "SpinTick") <= tickCap, "hatch cutscene: ...at most " .. tickCap .. " ticks over the 3 s strip (12 a second)", tostring(count(list, "SpinTick")))
		local eggKeys = 0
		for _, s in ipairs(list) do
			if EGG_SOUNDS[s.name] ~= nil then
				eggKeys = eggKeys + 1
			end
		end
		T.eq(eggKeys, 0, "hatch cutscene: ...and no egg key plays while its id is 0")
		ES.Done()
		restoreIds()
		afterDone("hatch cutscene after DONE", b0, s0)

		------------------------------------------------------------------ Low graphics: no blur, no tint, half the sparks, static rays, no streaks
		mode = "Low"
		local lowSeen = {}
		watch(result("Cloud", "Tokens", { epic }), 6.0, 450, 0, function(t, ph)
			if t >= 0.5 and lowSeen.blur == nil then
				lowSeen.blur = blur() ~= nil or hasHatch()
				local strip = G.content() and G.content():FindFirstChild("Strip1", true)
				lowSeen.streaks = strip ~= nil and strip:FindFirstChild("Streaks") ~= nil
			end
			local egg = G.hero("Egg1")
			if egg and egg:GetAttribute("State") == "Burst" and lowSeen.sparks == nil then
				lowSeen.sparks = burstFrame() and burstFrame():GetAttribute("Sparks")
				lowSeen.spin = spinning(G.hero("Rays"))
			end
		end)
		T.check(lowSeen.blur == false and lowSeen.streaks == false, "hatch cutscene: Low graphics: no blur, no \"Hatch\" tint, no speed streaks")
		T.check(lowSeen.sparks == SPARKS.Epic / 2 and lowSeen.spin == false, "hatch cutscene: Low graphics: half the sparks (14) and the rays stay still", fmt("%s sparks, spin %s", tostring(lowSeen.sparks), tostring(lowSeen.spin)))
		ES.Done()
		afterDone("hatch cutscene after a Low DONE", b0, s0)
		mode = "High"

		------------------------------------------------------------------ Legendary x1: the gold Flash once; the rays stay
		local sL = #sounds
		local recL = watch(result("Storm", "Tokens", { leg }), 6.8, 450, 0)
		T.check(#rec.gold == 0 and #recL.gold == 1 and recL.at.Burst and abs(recL.gold[1] - recL.at.Burst) <= 0.1, "hatch cutscene: Legendary: the gold Flash plays once, on the burst",
			fmt("%d gold flashes at %s (burst %s)", #recL.gold, tostring(recL.gold[1]), tostring(recL.at.Burst)))
		T.check(G.shown(G.hero("Rays")) and spinning(G.hero("Rays")), "hatch cutscene: Legendary: slow gold rays stay turning on the reveal")
		T.check(count(soundsFrom(sL), "EggRevealLegend", 1) == 1, "hatch cutscene: Legendary: its reveal sound (EggRevealLegend, the uploaded id) at full volume")
		T.check(recL.over == nil, "hatch cutscene: Legendary within the budgets", tostring(recL.over))
		ES.Done()
		afterDone("hatch cutscene after the Legendary DONE", b0, s0)

		------------------------------------------------------------------ Mythic and Secret: confetti; Secret: the starry backdrop
		for _, case in ipairs({ { myth, "Mythic", 0 }, { secret, "Secret", 14 } }) do
			local most = 0
			local recM = watch(result("Secret", "Gems", { case[1] }), 8.0, 450, case[3], function(t, ph)
				if ph == "Reveal" then
					most = math.max(most, confetti())
				end
			end)
			T.check(most == 24, "hatch cutscene: " .. case[2] .. ": 24 confetti fall on the reveal", tostring(most))
			T.check(recM.over == nil, "hatch cutscene: " .. case[2] .. " within the budgets (stars counted apart)", tostring(recM.over))
			if case[2] == "Secret" then
				local backdrop = stageChild("Stars") or (G.gui() and G.gui():FindFirstChild("Stars", true))
				local stars = 0
				for _, c in ipairs(backdrop and backdrop:GetChildren() or {}) do
					if c:IsA("GuiObject") then
						stars = stars + 1
					end
				end
				T.check(stars == 14 and FX.Stats().Tweens >= 14, "hatch cutscene: Secret: a starry backdrop of 14 twinkling stars", fmt("%d stars, %d tweens", stars, FX.Stats().Tweens))
				T.check(G.colPart(1, "Aura") ~= nil and G.shown(G.colPart(1, "Aura")), "hatch cutscene: Secret: a violet aura behind the pet")
			end
			ES.Done()
			afterDone("hatch cutscene after the " .. case[2] .. " DONE", b0, s0)
		end

		------------------------------------------------------------------ x3 Rare, Legendary, Common: pull order, one gold Flash on Egg2's burst
		local bursts = {}
		local rec3 = watch(result("Storm", "Tokens", { rare, leg, common }), 7.6, 750, 0, function(t)
			for j = 1, 3 do
				local egg = G.hero("Egg" .. j)
				if egg and egg:GetAttribute("State") == "Burst" and bursts[j] == nil then
					bursts[j] = t
				end
			end
		end)
		T.check(bursts[1] and bursts[2] and bursts[3] and abs(bursts[2] - bursts[1] - 0.6) <= 0.07 and abs(bursts[3] - bursts[1] - 1.2) <= 0.07,
			"hatch cutscene: x3: Egg1 bursts first, Egg2 0.6 s later, Egg3 1.2 s later (pull order)", fmt("%s %s %s", tostring(bursts[1]), tostring(bursts[2]), tostring(bursts[3])))
		T.check(#rec3.gold == 1 and bursts[2] and abs(rec3.gold[1] - bursts[2]) <= 0.1, "hatch cutscene: x3: the gold Flash once, on Egg2's burst (the Legendary)",
			fmt("%d at %s", #rec3.gold, tostring(rec3.gold[1])))
		T.check(rec3.at.Reveal and abs(rec3.at.Reveal - 7.15) <= 0.1, "hatch cutscene: x3 Reveal at 7.15 +- 0.1 s", tostring(rec3.at.Reveal))
		T.check(rec3.over == nil, "hatch cutscene: x3 within the budgets at every phase (750 instances)", tostring(rec3.over))
		ES.Done()
		afterDone("hatch cutscene after the x3 DONE", b0, s0)
		CS.Set("FastHatch", true)
		G.advance(0.5)
		local recF = watch(result("Storm", "Tokens", { rare, leg, common }), 3.2, 750, 0)
		T.check(recF.at.Reveal and abs(recF.at.Reveal - 2.66) <= 0.1, "hatch cutscene: x3 Fast hatch Reveal at 2.66 +- 0.1 s", tostring(recF.at.Reveal))
		ES.Done()
		G.advance(0.5)
		CS.Set("FastHatch", false)
		G.advance(0.5)

		------------------------------------------------------------------ Skip (one rule): the reveal next frame, the burst tail over its start
		for _, case in ipairs({ { leg, "Storm", "Legendary", 1 }, { epic, "Cloud", "Epic", 0 } }) do
			ES.Show(result(case[2], "Tokens", { case[1] }))
			G.advance(0.1)
			T.eq(ES.Phase(), "Intro", "hatch cutscene: Skip " .. case[3] .. ": (setup) the intro plays")
			ES.Skip()
			G.advance(STEP)
			T.eq(ES.Phase(), "Reveal", "hatch cutscene: Skip " .. case[3] .. " during Intro -> Reveal on the next frame")
			local gold, white, prev = 0, 0, nil
			local shock, rays = false, false
			for _ = 1, 9 do
				local kind = flashKind()
				if kind and kind ~= prev then
					if kind == "gold" then
						gold = gold + 1
					else
						white = white + 1
					end
				end
				prev = kind
				local b = burstFrame()
				shock = shock or (b ~= nil and G.shown(b:FindFirstChild("Shock")))
				rays = rays or G.shown(G.hero("Rays"))
				G.advance(STEP)
			end
			T.check(gold == case[4] and white == 0, "hatch cutscene: Skip " .. case[3] .. ": the burst tail shows the gold Flash " .. (case[4] == 1 and "exactly once" or "not at all") .. " and no white micro-flash",
				fmt("gold %d, white %d", gold, white))
			T.check(shock and rays, "hatch cutscene: Skip " .. case[3] .. ": the burst tail's shock ring and rays play over the reveal's start")
			ES.Done()
			G.advance(0.5)
		end
		-- sounds stop: a skip mid-Crack with every egg id given (the strip's, the rise's, the shakes' and the crack's sounds)
		local ids = {}
		local n = 0
		for key in pairs(EGG_SOUNDS) do
			n = n + 1
			ids[key] = Config.Audio.Sfx[key]
			Config.Audio.Sfx[key] = 7100000 + n
		end
		local t0k = os.clock()
		local k0 = #sounds
		ES.Show(result("Cloud", "Tokens", { epic }))
		G.until_(t0k, 4.9)
		T.eq(ES.Phase(), "Crack", "hatch cutscene: (setup) cracking at 4.9 s")
		local before = soundsFrom(k0)
		ES.Skip()
		G.advance(STEP)
		local still = {}
		for _, s in ipairs(before) do
			if s.sound.IsPlaying then
				still[#still + 1] = s.name
			end
		end
		T.check(#before >= 3 and #still == 0 and ES.Phase() == "Reveal", "hatch cutscene: Skip: every sound of the roll so far stops", #before .. " played, still: " .. table.concat(still, " "))
		ES.Done()
		G.advance(0.5)
		------------------------------------------------------------------ the owner's egg sounds (ids given): they replace today's
		local k1 = #sounds
		watch(result("Cloud", "Tokens", { epic }), 6.2, 450, 0)
		local eg = soundsFrom(k1)
		T.check(count(eg, "SpinStart", 0.6) == 1 and count(eg, "EggStripTick", 0.6) >= 8 and count(eg, "EggStripLand", 0.6) == 1 and count(eg, "EggRise", 0.6) == 1
			and count(eg, "EggShake", 0.6) == 2 and count(eg, "EggCrack", 0.6) == 1 and count(eg, "EggBurst", 0.6) == 1 and count(eg, "EggCloudRing", 0.6) == 1
			and count(eg, "EggRevealEpic", 0.6) == 1,
			"hatch cutscene: with the egg ids an Epic plays SpinStart, EggStripTick, EggStripLand, EggRise, EggShake x2, EggCrack, EggBurst, EggCloudRing, EggRevealEpic (all at 0.6)",
			fmt("tick %d land %d rise %d shake %d crack %d burst %d ring %d reveal %d", count(eg, "EggStripTick"), count(eg, "EggStripLand"), count(eg, "EggRise"), count(eg, "EggShake"),
				count(eg, "EggCrack"), count(eg, "EggBurst"), count(eg, "EggCloudRing"), count(eg, "EggRevealEpic")))
		T.check(count(eg, "SpinTick") + count(eg, "SpinLand") + count(eg, "Shatter") + count(eg, "RevealRare") == 0, "hatch cutscene: ...and none of today's SpinTick / SpinLand / Shatter / RevealRare")
		local egCap = math.ceil(12 * ES.Timings(false, 1).Strip) + 1
		T.check(count(eg, "EggStripTick") <= egCap, "hatch cutscene: ...at most " .. egCap .. " EggStripTick over the 3 s strip (12 a second, review round 1)", tostring(count(eg, "EggStripTick")))
		ES.Done()
		G.advance(0.5)
		local k2 = #sounds
		ES.Show(result("Secret", "Gems", { secret }))
		ES.Skip()
		G.advance(0.3)
		T.eq(count(soundsFrom(k2), "EggRevealSecret", 1), 1, "hatch cutscene: a Secret reveal plays EggRevealSecret at full volume")
		ES.Done()
		G.advance(0.5)
		local k3 = #sounds
		ES.Show(result("Storm", "Tokens", { leg }))
		ES.Skip()
		G.advance(0.3)
		T.eq(count(soundsFrom(k3), "EggRevealLegend", 1), 1, "hatch cutscene: a Legendary reveal plays EggRevealLegend at full volume")
		ES.Done()
		G.advance(0.5)
		for key in pairs(EGG_SOUNDS) do
			Config.Audio.Sfx[key] = ids[key]
		end

		------------------------------------------------------------------ never breaks the player (Review Focus 3), on a touch device with the Shop open
		RedoGeom.at(1920, 1080, true, "hatch cutscene never breaks", function()
			local UIS = game:GetService("UserInputService")
			local function snap()
				local s = G.snapshot()
				s[7] = ML and ML.IsLocked() or false
				s[8] = ML and ML.IsEnabled() or false
				return s
			end
			-- skip6: the touch controls (field 6) are checked apart where the exit closes the Shop (they come back then)
			local function same(a, b, skip6)
				for i = 1, 8 do
					if a[i] ~= b[i] and not (skip6 and i == 6) then
						return false, "field " .. i .. ": " .. tostring(a[i]) .. " -> " .. tostring(b[i])
					end
				end
				return true, ""
			end
			local function win()
				local gui = G.pg():FindFirstChild("NimbusShop")
				return gui and gui:FindFirstChild("ShopWindow") or nil
			end
			local function lightingClean(label)
				G.advance(0.45)
				T.check(blur() == nil and not hasHatch() and ccCount() == 1 and abs(cc.Brightness - b0) < 1e-3 and abs(cc.Saturation - s0) < 1e-3,
					label .. ": Lighting as it began (no NimbusHatchBlur, no \"Hatch\" preset, the colour correction back)")
				G.zeroStats(ES, label)
			end
			local function openShop()
				Shop.Open({ Tab = "Eggs" })
				G.advance(0.5)
				return Shop.IsOpen() and G.shown(win())
			end
			T.check(UIS.TouchEnabled == true, "hatch cutscene never breaks: (setup) a touch device")
			-- DONE
			T.check(openShop(), "hatch cutscene never breaks: (setup) the Shop is open")
			local base = snap()
			ES.Show(result("Cloud", "Tokens", { epic }))
			G.advance(0.5)
			T.check(GuiService.TouchControlsEnabled == false and not G.shown(win()), "hatch cutscene never breaks: the stage hides the touch controls and the Shop window while it plays")
			ES.Skip()
			G.advance(0.6)
			ES.Done()
			G.advance(STEP)
			local okD, whyD = same(base, snap())
			T.check(okD, "hatch cutscene never breaks: after DONE the Camera, the Humanoid, the mouse lock and the touch controls are as before", whyD)
			T.check(Shop.IsOpen() and G.shown(win()), "hatch cutscene never breaks: ...and ShopWindow is visible again")
			lightingClean("hatch cutscene never breaks after DONE")
			-- a match start mid-Crack
			local t0 = os.clock()
			ES.Show(result("Cloud", "Tokens", { epic }))
			G.until_(t0, 4.6)
			T.eq(ES.Phase(), "Crack", "hatch cutscene never breaks: (setup) mid-Crack")
			LocalPlayer:SetAttribute(IN_MATCH, true)
			G.advance(0.2)
			local okM, whyM = same(base, snap(), true)
			T.check(lastOf(closed) == "Match" and okM, "hatch cutscene never breaks: a match start mid-Crack (Closed 'Match'): everything as before", whyM)
			T.check(not Shop.IsOpen() and not G.shown(win()) and GuiService.TouchControlsEnabled == true, "hatch cutscene never breaks: ...the Shop stays closed and the touch controls are back")
			LocalPlayer:SetAttribute(IN_MATCH, nil)
			lightingClean("hatch cutscene never breaks after the match start")
			-- an injected phase error (the test-only hook, nil by default)
			T.check(ES._InjectPhaseError == nil, "hatch cutscene never breaks: EggStage._InjectPhaseError is nil by default")
			T.check(openShop(), "hatch cutscene never breaks: (setup) the Shop open again")
			local o0 = #Mock.Output
			ES._InjectPhaseError = "Crack"
			ES.Show(result("Cloud", "Tokens", { epic }))
			G.advance(5.0)
			local planted = 0
			for i = #Mock.Output, o0 + 1, -1 do
				local o = Mock.Output[i]
				if o.kind == "warn" and tostring(o.text):find("injected phase error", 1, true) then
					planted = planted + 1
					table.remove(Mock.Output, i)
				end
			end
			local okE, whyE = same(base, snap())
			T.check(planted == 1 and lastOf(closed) == "Error" and not ES.IsShowing() and okE, "hatch cutscene never breaks: an injected Crack error ends through teardown (Closed 'Error', one warn): everything as before",
				planted .. " warns, " .. tostring(lastOf(closed)) .. " " .. whyE)
			T.check(ES._InjectPhaseError == nil, "hatch cutscene never breaks: ...and the hook is reset")
			T.check(Shop.IsOpen() and G.shown(win()), "hatch cutscene never breaks: ...ShopWindow is visible again after the error")
			lightingClean("hatch cutscene never breaks after the error")
			-- (review round 1) an error inside the reveal's own build (the hook "Reveal" raises there): the pulls were never
			-- shown, so teardown toasts them ("a paid x3 is never lost from view", spec 5.5)
			local hintsR, realHintR = {}, MC.Hint
			MC.Hint = function(text)
				hintsR[#hintsR + 1] = tostring(text)
			end
			local o1 = #Mock.Output
			ES._InjectPhaseError = "Reveal"
			ES.Show(result("Cloud", "Tokens", { epic, rare, common }))
			ES.Skip()
			G.advance(0.4)
			MC.Hint = realHintR
			local plantedR = 0
			for i = #Mock.Output, o1 + 1, -1 do
				local o = Mock.Output[i]
				if o.kind == "warn" and tostring(o.text):find("injected phase error", 1, true) then
					plantedR = plantedR + 1
					table.remove(Mock.Output, i)
				end
			end
			local toasted = nil
			for _, h in ipairs(hintsR) do
				if h:find("You hatched: ", 1, true) and h:find(epic.Name, 1, true) and h:find(rare.Name, 1, true) then
					toasted = h
				end
			end
			T.check(plantedR == 1 and lastOf(closed) == "Error" and not ES.IsShowing() and toasted ~= nil,
				"hatch cutscene never breaks: an error inside an x3 reveal's build ends through teardown (Closed 'Error') and toasts the pulls ('You hatched: ...')",
				plantedR .. " warns, " .. tostring(lastOf(closed)) .. ", toasts: " .. table.concat(hintsR, " | "))
			T.check(ES._InjectPhaseError == nil, "hatch cutscene never breaks: ...and the hook is reset after the reveal error")
			lightingClean("hatch cutscene never breaks after the reveal error")
			-- MenuController.Close() mid-roll
			ES.Show(result("Cloud", "Tokens", { epic }))
			G.advance(1.0)
			MC.Close()
			G.advance(0.2)
			local okC, whyC = same(base, snap(), true)
			T.check(lastOf(closed) == "Close" and okC, "hatch cutscene never breaks: MenuController.Close() mid-roll (Closed 'Close'): everything as before", whyC)
			T.check(not Shop.IsOpen() and not G.shown(win()) and GuiService.TouchControlsEnabled == true, "hatch cutscene never breaks: ...the Shop closed and the touch controls back")
			lightingClean("hatch cutscene never breaks after MenuController.Close()")
			-- the character removed mid-Strip (the Shop is closed now: the base again, as it stands)
			local baseR = snap()
			ES.Show(result("Cloud", "Tokens", { epic }))
			G.advance(1.2)
			Mock.Respawn(LocalPlayer)
			local runR = G.run(ES, 6)
			T.check(runR.at.Reveal ~= nil, "hatch cutscene never breaks: the character removed mid-Strip (a new one added): the stage reaches the reveal")
			G.advance(0.6)
			ES.Done()
			G.advance(STEP)
			local okR, whyR = same(baseR, snap())
			T.check(okR, "hatch cutscene never breaks: ...and after DONE everything matches (the new Humanoid's walk and jump)", whyR)
			lightingClean("hatch cutscene never breaks after the respawn")
		end)
	end)
	if not ok then
		T.fail("hatch cutscene: scenario error", tostring(err))
	end
	for key in pairs(EGG_SOUNDS) do
		Config.Audio.Sfx[key] = realEggIds[key]
	end
	ES._InjectPhaseError = nil
	if ES.IsShowing() then
		ES.Close()
	end
	pcall(function()
		Shop.Close()
	end)
	closedConn:Disconnect()
	SF.Play = realPlay
	GQ.Effective = oldEff
	box:Destroy()
	if madeCC then
		cc:Destroy()
	end
	LocalPlayer:SetAttribute(IN_MATCH, nil)
	for name, v in pairs(keep) do
		LocalPlayer:SetAttribute(name, v)
	end
	CS.Set("FastHatch", false)
	Mock.SetViewport(oldVp[1], oldVp[2])
	G.advance(0.6)
	KC.flushErrors("client_hatch_cutscene")
end)

return S
