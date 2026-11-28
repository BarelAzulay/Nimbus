-- smoke_battle_tags.lua: the owner's bug inbox, 2026-11-27 (branch fix-battle-tags). Client world only; registered on
-- its own line in tools/smoke.py.
--   battle_tags_clear  bug "damage total covers the pet level card": in a dungeon the running damage total (BattleController
--                      Fx.Total, BillboardGui "DamageTotal") sat 0.3 studs over the unit card (PetCard "HpBar": "Lv 4" +
--                      the HP row), so at fighting distance its chip covered the card but for the "L". Both are fixed-px
--                      billboards, so the check is in screen px through a real perspective camera at 10 .. 130 studs, at
--                      1920x1080, 2560x1440 and 844x390: the total's chip never overlaps its unit's plate. Cases: my unit
--                      (Lv 4, the owner's height 3.956), a unit showing the EVOLVE! pill, a dungeon mini-boss (a tall
--                      enemy with its Enemy card), the ring champion (its gold name tag over the card), the Phase 3 bar
--                      (addBar: PetCard.New failing). A hit's pop still starts beside the total (Pitch 2 item 04 B), clear
--                      of the card; a raid boss (no world plate) keeps its total over its head as before.
-- Plain Lua 5.1 syntax only. Deterministic: mock clock only; the viewport, the camera and PetCard.New are put back.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local fmt = string.format
local abs = math.abs

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
local function overlap(a, b)
	return a.X < b.R - 0.5 and b.X < a.R - 0.5 and a.Y < b.B - 0.5 and b.Y < a.B - 0.5
end
local function show(r)
	return r and fmt("%.0f,%.0f .. %.0f,%.0f", r.X, r.Y, r.R, r.B) or "nil"
end

-- a perspective camera's screen point of `pos` (px; y down), as Roblox projects it
local function project(cam, pos)
	local rel = cam.CFrame:PointToObjectSpace(pos)
	local vp = Mock.Viewport
	local d = math.max(1e-6, -rel.Z)
	local f = (vp.Y / 2) / math.tan(math.rad(cam.FieldOfView / 2))
	return vp.X / 2 + rel.X / d * f, vp.Y / 2 - rel.Y / d * f
end
-- a billboard's centre on the screen: its adornee + StudsOffset (camera space) + StudsOffsetWorldSpace, moved by its
-- SizeOffset (a share of its own px size; +Y up)
local function centre(cam, g)
	local so, cf = g.StudsOffset, cam.CFrame
	local x, y = project(cam, g.Adornee.Position + g.StudsOffsetWorldSpace + cf.RightVector * so.X + cf.UpVector * so.Y)
	return x + g.SizeOffset.X * g.Size.X.Offset, y - g.SizeOffset.Y * g.Size.Y.Offset
end
local function box(cx, cy, w, h)
	return { X = cx - w / 2, Y = cy - h / 2, R = cx + w / 2, B = cy + h / 2 }
end

local function clientScenarios()
	local S = {}
	local KC = _G.KC

	----------------------------------------------------------------------------------------------------------------
	-- battle_tags_clear
	----------------------------------------------------------------------------------------------------------------
	S.battle_tags_clear = guarded("battle_tags_clear", function()
		local BC = client("Controllers/BattleController")
		local Fx = BC and BC._Fx
		local Cards = BC and BC._Cards
		local PetCard = client("UI/PetCard")
		local Theme = shared("Theme")
		local cam = workspace.CurrentCamera
		if not T.check(Fx ~= nil and type(Fx.Total) == "function" and type(Fx.Pop) == "function" and type(Cards) == "table" and type(Cards.Add) == "function"
			and type(PetCard) == "table" and Theme ~= nil and cam ~= nil, "battle tags: (setup) BattleController._Fx / _Cards, PetCard, the camera") then
			return
		end
		local Config = shared("Config")
		local origin = (Config.Lobby and Config.Lobby.Origin) or Vector3.new(0, 300, 0)
		local saved = { cam.CFrame, cam.FieldOfView, Mock.Viewport.X, Mock.Viewport.Y, PetCard.New }
		local made = {}
		local nextId = 99400
		-- one unit as Units builds it: a model with its root part, the card through Cards.Add (PetCard, or the Phase 3 bar)
		local function unit(opts)
			nextId = nextId + 1
			local model = Instance.new("Model")
			model.Name = "Unit_" .. nextId
			local part = Instance.new("Part")
			part.Name = "Body"
			part.Anchored = true
			part.Size = Vector3.new(2, opts.height, 2)
			part.CFrame = CFrame.new(origin + Vector3.new(0, opts.height / 2, -60))
			part.Parent = model
			model.PrimaryPart = part
			model.Parent = workspace
			made[#made + 1] = model
			local u = {
				id = nextId, root = part, model = model, height = opts.height, centerY = opts.height / 2, mine = opts.mine == true,
				ally = false, kind = opts.kind, crowned = opts.crowned, isBoss = opts.isBoss, level = opts.level or 4, evo = 0,
				hp = 80, maxHp = 100, meter = 0, name = opts.name or "Mochi",
			}
			if not opts.isBoss then
				local B = { Ring = opts.crowned and { Champion = { Name = "Mochi" } } or nil }
				Cards.Add(B, u, part)
				if opts.ready and u.card then
					u.card:SetLevel(u.level, 0, true) -- the EVOLVE! pill over the chip
				end
			end
			return u
		end
		-- the plate a total must clear: the champion's tag (it holds the card under its plate), the card, the bar
		local function plateOf(u)
			return u.tag or (u.card and u.card.Gui) or u.bar
		end
		local ok, err = pcall(function()
			cam.FieldOfView = 70
			for _, size in ipairs({ { 1920, 1080 }, { 2560, 1440 }, { 844, 390 } }) do
				Mock.SetViewport(size[1], size[2])
				KC.advance(0.1)
				local cases = {
					{ "my unit Lv 4", { height = 3.956, mine = true } },
					{ "EVOLVE! shown", { height = 3.956, mine = true, ready = true, level = 20 } },
					{ "dungeon mini-boss", { height = 7.5, kind = "MiniBoss", level = 12, name = "Grub King" } },
					{ "ring champion", { height = 3.956, crowned = true } },
					{ "Phase 3 bar", { height = 3.956, mine = true, bar = true } },
				}
				for _, case in ipairs(cases) do
					local name, opts = case[1], case[2]
					local tag = fmt("battle tags %dx%d %s", size[1], size[2], name)
					local warn0 = #Mock.Output
					if opts.bar then
						PetCard.New = function()
							error("smoke: no PetCard (the Phase 3 bar)")
						end
					end
					local u = unit(opts)
					PetCard.New = saved[5]
					if opts.bar then
						for i = #Mock.Output, warn0 + 1, -1 do
							if tostring(Mock.Output[i].text):find("smoke: no PetCard", 1, true) then
								table.remove(Mock.Output, i) -- (the planted failure's one warning belongs to this case)
							end
						end
					end
					local plate = plateOf(u)
					local want = (opts.bar and u.bar ~= nil) or (opts.crowned and u.tag ~= nil) or (not opts.bar and not opts.crowned and u.card ~= nil)
					if T.check(plate ~= nil and want, tag .. ": (setup) the unit's plate", fmt("card %s bar %s tag %s", tostring(u.card ~= nil), tostring(u.bar ~= nil), tostring(u.tag ~= nil))) then
						if opts.ready then
							local pill = plate:FindFirstChild("Evolve")
							T.check(pill ~= nil and pill.Visible, tag .. ": (setup) the EVOLVE! pill shows")
						end
						-- a hit: the pop beside the total (the hit handler's path), then the total read at every distance
						local text, colour, px = Fx.HitLook(17, {})
						local pop, total = Fx.Pop(u, u.root, Fx.NumberHeight(u), text, colour, px, 17)
						if T.check(total ~= nil and pop ~= nil, tag .. ": (setup) the hit shows a total and its pop") then
							local g, chip = total.gui, total.chip
							local edge = (chip:FindFirstChild("SignEdge") and chip.SignEdge.Thickness) or 0
							local worst, popBad = nil, nil
							for _, dist in ipairs({ 10, 20, 40, 80, 130 }) do
								local head = u.root.Position + Vector3.new(0, u.height / 2, 0)
								cam.CFrame = CFrame.lookAt(head + Vector3.new(0, 0.25 * dist, dist), head)
								local px0, py0 = centre(cam, plate)
								local pr = box(px0, py0, plate.Size.X.Offset, plate.Size.Y.Offset)
								local tx, ty = centre(cam, g)
								local tr = box(tx, ty, chip.Size.X.Offset + 2 * edge, chip.Size.Y.Offset + 2 * edge)
								local gap = pr.Y - tr.B
								if overlap(tr, pr) and (worst == nil or gap < worst.gap) then
									worst = { gap = gap, why = fmt("at %d studs the total %s covers the plate %s", dist, show(tr), show(pr)) }
								end
								-- the pop at its birth: beside the total's chip (right of its centre), never over the card
								local label = pop.label
								local qx, qy = centre(cam, pop.gui)
								local w = math.max(1, #label.Text) * 0.62 * label.TextSize
								local qr = box(qx, qy, w, label.TextSize)
								if not popBad and (overlap(qr, pr) or qx <= tx or qy > ty + 1) then
									popBad = fmt("at %d studs the pop %s, the total %s, the plate %s", dist, show(qr), show(tr), show(pr))
								end
							end
							T.check(worst == nil, tag .. ": the damage total's chip never covers the unit's plate (10 .. 130 studs)", worst and worst.why or "-")
							T.check(popBad == nil, tag .. ": the hit's pop starts beside the total, clear of the plate", popBad or "-")
						end
					end
					Fx.ClearAll()
					Cards.Free(u)
					if u.bar then
						u.bar:Destroy()
						u.bar = nil
					end
					if u.tag then
						u.tag:Destroy()
						u.tag = nil
					end
				end
				-- a raid boss draws no world plate (its bar is the HUD's top card): its total stays over its head, where its
				-- pops start, as before
				local boss = unit({ height = 20, isBoss = true })
				local total = Fx.Total(boss, 1200)
				local plates = 0
				for _, d in ipairs(boss.model:GetDescendants()) do
					plates = plates + ((d:IsA("BillboardGui") and d.Name ~= "DamageTotal") and 1 or 0)
				end
				T.check(total ~= nil and plates == 0 and abs(total.gui.StudsOffset.Y - (Fx.NumberHeight(boss) - 0.6)) < 1e-6 and abs(total.gui.SizeOffset.Y) < 1e-6,
					fmt("battle tags %dx%d raid boss: no world plate, the total over its head (NumberHeight - 0.6)", size[1], size[2]),
					total and fmt("plates %d, studs %.2f, size offset %.3f", plates, total.gui.StudsOffset.Y, total.gui.SizeOffset.Y) or "no total")
				-- (playtest 2026-11-28 C60: the total stood at Root + height x 0.5 + 2, mid-body on a 20-stud boss: BossBuilder
				-- roots a boss at its feet) the boss's total and pops start over its head: the Root plus its height
				T.check(total ~= nil and total.gui.StudsOffset.Y >= boss.height and Fx.NumberHeight(boss) >= boss.height + 1,
					fmt("battle tags %dx%d raid boss: the total and pops start over its head (Root at its feet + its height)", size[1], size[2]),
					total and fmt("studs %.2f, NumberHeight %.2f, height %.1f", total.gui.StudsOffset.Y, Fx.NumberHeight(boss), boss.height) or "no total")
				Fx.ClearAll()
			end
		end)
		PetCard.New = saved[5]
		pcall(Fx.ClearAll)
		for _, m in ipairs(made) do
			m:Destroy()
		end
		cam.CFrame, cam.FieldOfView = saved[1], saved[2]
		Mock.SetViewport(saved[3], saved[4])
		KC.advance(0.1)
		T.check(ok, "battle tags: the scenario ran", tostring(err))
		KC.flushErrors("battle_tags_clear")
	end)

	----------------------------------------------------------------------------------------------------------------
	-- egg_stage_resize_in_build (owner's Studio log 2026-11-27: "[EggStage] resize: ...HatchLook:1326: attempt to index
	-- nil with 'FindFirstChild'"): H.startRoll published the roll (S.Roll) before B.roll had built its chips, so the
	-- stage's AbsoluteSize hook (H.open) relaid a half-built roll and H.applyBar sized a Skip chip that did not exist
	-- yet. A new NimbusHatch gets its size on its first layout, which Roblox can run (and signal at once) while the roll
	-- is still being built; here the screen turns during B.roll (before B.bar). No warning, and the stage that comes up
	-- is laid out for the new screen; a resize after the build still relays it out
	----------------------------------------------------------------------------------------------------------------
	S.egg_stage_resize_in_build = guarded("egg_stage_resize_in_build", function()
		local ES = client("UI/EggStage")
		local HL = client("UI/HatchLook")
		local PC = shared("PetCatalog")
		local pool = PC and PC.RarityPool and PC.RarityPool("Cloud", "Epic") or {}
		if not T.check(type(ES) == "table" and type(ES.Show) == "function" and type(ES._S) == "table" and type(HL) == "table" and type(HL.Word) == "function" and #pool >= 1,
			"egg stage resize in build: (setup) EggStage, HatchLook.Word, a Cloud Epic pet") then
			return
		end
		local def = pool[1]
		local pull = { PetId = def.Id, Key = def.Id, Rarity = def.Rarity, IsNew = true, NewDiscovery = true, Count = 1, PoolSize = #pool }
		local result = { Ok = true, RouletteId = "Cloud", Currency = "Tokens", Spins = 1, UnitPrice = 50, Price = 50, Pulls = { pull }, Tokens = 5000, Gems = 5000,
			PetId = pull.PetId, Key = pull.Key, IsNew = true, NewDiscovery = true, Count = 1 }
		local oldVp = { Mock.Viewport.X, Mock.Viewport.Y }
		Mock.SetViewport(1920, 1080)
		KC.advance(0.2)
		local realWord = HL.Word
		local turned = false
		HL.Word = function(...)
			-- B.roll's crack word: the roll is published, its bottom bar (B.bar) not built yet
			if not turned then
				turned = true
				Mock.SetViewport(844, 390)
			end
			return realWord(...)
		end
		local o0 = #Mock.Output
		local ok, err = pcall(ES.Show, result)
		HL.Word = realWord
		local resizeWarns = {}
		for i = o0 + 1, #Mock.Output do
			local o = Mock.Output[i]
			if o.kind == "warn" and tostring(o.text):find("[EggStage] resize", 1, true) then
				resizeWarns[#resizeWarns + 1] = tostring(o.text)
			end
		end
		T.check(ok and turned, "egg stage resize in build: (setup) the stage opens, the screen turned during B.roll", tostring(err))
		T.check(#resizeWarns == 0, "egg stage resize in build: a resize while the roll is built warns nothing (no half-built roll relaid)", resizeWarns[1] or "-")
		local S = ES._S
		local content = S.Content
		local bar = content and content:FindFirstChild("BottomBar")
		local skip = bar and bar:FindFirstChild("Skip")
		T.check(S.Lay ~= nil and S.Lay.W == 844 and bar ~= nil and bar.Size.X.Offset == 844 and skip ~= nil and skip:FindFirstChild("Pill") ~= nil,
			"egg stage resize in build: the stage comes up laid out for the turned screen (844 wide, its Skip chip built)",
			fmt("lay %s, bar %s", S.Lay and tostring(S.Lay.W) or "nil", bar and tostring(bar.Size.X.Offset) or "nil"))
		-- a resize after the build still relays the stage out
		KC.advance(0.3)
		Mock.SetViewport(1920, 1080)
		KC.advance(0.1)
		T.check(S.Lay ~= nil and S.Lay.W == 1920 and bar ~= nil and bar.Size.X.Offset == 1920, "egg stage resize in build: a resize after the build relays it out (1920 wide)",
			fmt("lay %s, bar %s", S.Lay and tostring(S.Lay.W) or "nil", bar and tostring(bar.Size.X.Offset) or "nil"))
		if ES.IsShowing() then
			ES.Close()
		end
		KC.advance(0.6)
		Mock.SetViewport(oldVp[1], oldVp[2])
		KC.advance(0.2)
		KC.flushErrors("egg_stage_resize_in_build")
	end)

	return S
end

return clientScenarios()
