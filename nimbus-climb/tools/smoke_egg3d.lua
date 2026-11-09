-- smoke_egg3d.lua: egg-3d (the owner's pick 2026-11-08 "3D egg + 3D crack"; spec
-- docs/superpowers/specs/2026-11-07-lobby-shop-design.md 16.14 "3D eggs"): client/UI/Egg3D, the real Blender egg in a
-- ViewportFrame in the hatch cutscene's pedestal phases and the Shop's Secret hero, and the crack that splits it into its
-- two Blender halves. Loaded by tools/smoke.py in the CLIENT and PHONE worlds:
--   client_egg3d        (client, 1920x1080) Egg3D's keys (the 21 literals), Usable's reasons (an id of 0 / not loaded
--       -> "missing", Low -> "low"), a view's ViewportFrame (Camera, light, the model from MeshLibrary.Assemble of the key,
--       its slow turn, Destroy); the cutscene with a stubbed MeshLibrary: an x1 Epic with every key "uploaded" shows the
--       ViewportFrame egg (key egg_epic) in Egg1 over the Rise and the Crack with the 2D paint hidden and the backlight,
--       ring, cracks and leaks kept; the halves path: Halves1 Split3D at the crack, at the burst the frame moves into
--       Halves1, the whole egg leaves, EggTop and EggBot come in at its pose and are tweened apart (the cap up and fading,
--       the cup where it stood), all gone after the reveal; the halves-0 fallback: today's 2D HalfTop / HalfBottom under
--       the flash and the ViewportFrame gone at the burst; the id-0, Low graphics and failed-Assemble fallbacks: today's
--       2D egg exactly (no Egg3D, painted); x3 keeps 2D eggs; Skip / Close / DONE leave no view (Egg3D.Live() 0, Stats
--       zero); the Shop hero: the 3D Secret egg while the Eggs page shows, gone (and painted again) when the Shop closes
--   client_egg3d_phone  (phone world, 844x390) the phone limit: one ViewportFrame egg at a time (a second view is refused
--       with "limit" while the cutscene's egg lives); the phone's Shop hero has no room (no view)
-- Deterministic: mock clock only. Egg3D._ML / _High and GraphicsQuality.Effective are put back after each scenario.
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local fmt = string.format

local S = {}

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
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
function G.hero(name)
	local pg = G.pg()
	local gui = pg and pg:FindFirstChild("NimbusHatch")
	local content = gui and gui:FindFirstChild("Content", true)
	local hero = content and content:FindFirstChild("Hero")
	return hero and hero:FindFirstChild(name) or nil
end
function G.shown(o)
	return o ~= nil and G.KC().isShown(o)
end
-- a stand-in MeshLibrary: IsReady answers from `ready` (the keys "uploaded" and loaded here), Assemble builds a small
-- model like the kit's (a Fixed part + a Glow part, pivot at the bottom centre) unless the key is in `fail`
function G.stubML(ready, fail)
	local stub = { Calls = {} }
	function stub.IsReady(key)
		return ready[key] == true
	end
	function stub.Assemble(spec, look, opts)
		local key = spec and spec.Parts and spec.Parts[1] and spec.Parts[1].Key
		stub.Calls[#stub.Calls + 1] = { Key = key, Name = spec and spec.Name, Root = spec and spec.Root, At = opts and opts.At }
		if not key or (fail and fail[key]) then
			return nil
		end
		local m = Instance.new("Model")
		m.Name = spec.Name or key
		local y = key:find("_top$") and 2.4 or (key:find("_bot$") and 0.8 or 1.5)
		local h = key:find("_top$") and 1.2 or (key:find("_bot$") and 1.6 or 3)
		for i, name in ipairs({ "Fixed", "GlowStar" }) do
			local p = Instance.new("Part")
			p.Name = name
			p.Anchored = true
			p.Size = Vector3.new(2.2 - 0.1 * i, h, 2.2 - 0.1 * i)
			p.CFrame = CFrame.new(0, y, 0)
			p.Transparency = 0
			p:SetAttribute("ML_Key", key)
			p.Parent = m
		end
		-- the pivot at the bottom centre like MeshLibrary's (WorldPivot = At). The mock drops a write equal to a
		-- property's default (identity) and then derives the pivot from the bounding box, so it is pinned a hair off
		m.WorldPivot = CFrame.new(0, 0, 1e-9)
		m:SetAttribute("ML_Keys", key)
		return m
	end
	return stub
end
function G.allKeys()
	local out = {}
	for _, r in ipairs(RARITIES) do
		local l = r:lower()
		out["egg_" .. l], out["egg_" .. l .. "_top"], out["egg_" .. l .. "_bot"] = true, true, true
	end
	return out
end
function G.wholeOnly()
	local out = {}
	for _, r in ipairs(RARITIES) do
		out["egg_" .. r:lower()] = true
	end
	return out
end
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
function G.result(PC, rid, defs)
	local pulls = {}
	for i, def in ipairs(defs) do
		pulls[i] = {
			PetId = def.Id, Key = def.Id, Rarity = def.Rarity, IsNew = true, NewDiscovery = true, Count = 1,
			PoolSize = #PC.RarityPool(rid, def.Rarity), Strip = G.strip(PC, rid, def.Id),
		}
	end
	local p1 = pulls[1]
	return {
		Ok = true, RouletteId = rid, Currency = "Tokens", Spins = #pulls, UnitPrice = 50, Price = 50 * #pulls, Pulls = pulls, Tokens = 5000, Gems = 5000,
		PetId = p1.PetId, Key = p1.Key, IsNew = p1.IsNew, NewDiscovery = p1.NewDiscovery, Count = p1.Count, Strip = p1.Strip,
	}
end
-- steps the stage until Phase() == phase (or maxT s) -> the time it took, or nil
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
function G.view(egg)
	return egg and egg:FindFirstChild("Egg3D") or nil
end
function G.modelY(frame, name)
	local m = frame and frame:FindFirstChild(name)
	if not m then
		return nil
	end
	local ok, cf = pcall(function()
		return m:GetPivot()
	end)
	return ok and cf and cf.Position.Y or nil
end
-- the playing tween whose instance is inst (or nil)
function G.tweenOn(inst)
	if not inst then
		return nil
	end
	for tw in pairs(Mock.ActiveTweens) do
		local ok, hit = pcall(function()
			return tw.Instance == inst and tw.PlaybackState == Enum.PlaybackState.Playing
		end)
		if ok and hit then
			return tw
		end
	end
	return nil
end
function G.capT(frame)
	local m = frame and frame:FindFirstChild("EggTop")
	local p = m and m:FindFirstChild("Fixed")
	return p and p.Transparency or nil
end

-- common setup / teardown of both scenarios
function G.setup(w, h)
	local KC = G.KC()
	local Config = KC.env()
	local env = {
		Config = Config,
		ES = G.req("client/UI/EggStage"),
		E3 = G.req("client/UI/Egg3D"),
		GQ = G.req("client/GraphicsQuality"),
		CS = G.req("client/ClientSettings"),
		SF = G.req("client/SoundFx"),
		PC = G.req("shared/PetCatalog"),
		Shop = G.req("client/Controllers/ShopController"),
		SE = G.req("client/UI/ShopEggs"),
		oldVp = { Mock.Viewport.X, Mock.Viewport.Y },
		keep = {},
	}
	for _, name in ipairs({ Config.Attr.Tokens, Config.Attr.Gems, "PaidRandomItemsRestricted", "GemsSettled" }) do
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
	env.mode = "High"
	if env.GQ then
		env.oldEff = env.GQ.Effective
		env.GQ.Effective = function()
			return env.mode
		end
	end
	-- sounds: quiet (a spy that plays nothing)
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
	if env.ES and env.ES.IsShowing() then
		env.ES.Close()
	end
	if env.Shop then
		env.Shop.Close()
	end
	if env.E3 then
		env.E3._ML, env.E3._High = nil, nil
	end
	if env.GQ and env.oldEff then
		env.GQ.Effective = env.oldEff
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

----------------------------------------------------------------------------------------------------
-- client_egg3d
----------------------------------------------------------------------------------------------------
S.client_egg3d = guarded("client_egg3d", function()
	local env = G.setup(1920, 1080)
	local ES, E3, PC, SE, Shop = env.ES, env.E3, env.PC, env.SE, env.Shop
	if not T.check(type(ES) == "table" and type(E3) == "table" and type(PC) == "table" and type(Shop) == "table" and type(SE) == "table",
		"egg3d: EggStage, Egg3D, PetCatalog, ShopController and ShopEggs load") then
		G.restore(env)
		return
	end
	local ok, err = pcall(function()
		------------------------------------------------------------------ the keys: 21 literals, the shelf's whole egg + two halves each
		local okKeys = true
		for _, r in ipairs(RARITIES) do
			local k, l = E3.KEYS[r], r:lower()
			okKeys = okKeys and k ~= nil and k.Whole == "egg_" .. l and k.Top == "egg_" .. l .. "_top" and k.Bot == "egg_" .. l .. "_bot"
		end
		T.check(okKeys, "egg3d: KEYS per rarity = egg_<r> (the shelf's key) / egg_<r>_top / egg_<r>_bot")
		------------------------------------------------------------------ the real MeshLibrary of the mock: nothing loads -> "missing"
		local usable, why = E3.Usable("Epic", {})
		T.check(not usable and why == "missing", "egg3d: with the mock's MeshLibrary (no asset store: the keys never load) Usable is false, \"missing\"", tostring(why))
		------------------------------------------------------------------ Usable's reasons with a stub
		E3._ML = G.stubML(G.allKeys())
		usable, why = E3.Usable("Epic", {})
		T.check(usable and why == nil, "egg3d: a usable key on High -> Usable true", tostring(why))
		env.mode = "Low"
		usable, why = E3.Usable("Epic", {})
		T.check(not usable and why == "low", "egg3d: Low graphics -> Usable false, \"low\"", tostring(why))
		env.mode = "High"
		E3._ML = G.stubML({ egg_rare = true })
		usable, why = E3.Usable("Epic", {})
		T.check(not usable and why == "missing", "egg3d: egg_epic's id 0 (not usable here) -> \"missing\" while egg_rare's works", tostring(why))
		T.check((E3.Usable("Rare", {})), "egg3d: ...and Rare is usable")
		T.check(not E3.Usable("Gold", {}), "egg3d: an unknown rarity is refused")
		------------------------------------------------------------------ a view: the frame, camera, light, model, turn, Destroy
		local stub = G.stubML(G.allKeys())
		E3._ML = stub
		local board = Instance.new("ScreenGui")
		board.Name = "SmokeEgg3D"
		board.Parent = G.pg()
		local host = Instance.new("Frame")
		host.Name = "Host"
		host.Size = UDim2.fromOffset(160, 200)
		host.Parent = board
		local live0 = E3.Live()
		local view = E3.New(host, "Legendary", { Spin = 10 })
		local f = view and view.Frame
		T.check(f ~= nil and f:IsA("ViewportFrame") and f.Name == "Egg3D" and f.Parent == host, "egg3d: New -> a ViewportFrame \"Egg3D\" in its parent")
		if f then
			local cam = f.CurrentCamera
			T.check(cam ~= nil and cam:IsA("Camera") and cam.Parent == f and math.abs(cam.FieldOfView - 20) < 1e-6, "egg3d: its own Camera (FieldOfView 20) is the CurrentCamera")
			T.check(f:GetAttribute("Key") == "egg_legendary" and f:GetAttribute("Rarity") == "Legendary", "egg3d: attributes Key egg_legendary, Rarity Legendary", tostring(f:GetAttribute("Key")))
			local last = stub.Calls[#stub.Calls]
			T.check(last and last.Key == "egg_legendary" and last.Root == false and typeof(last.At) == "CFrame", "egg3d: the model is MeshLibrary.Assemble of the shelf's key (rootless, At the pivot: the way Dress dresses the shelf eggs)")
			T.check(f:FindFirstChild("Egg") ~= nil and f:FindFirstChild("Egg"):IsA("Model"), "egg3d: the model \"Egg\" sits in the frame")
			T.check(f.Ambient ~= Color3.fromRGB(200, 200, 200) and f.LightDirection.Y < 0 and f.LightDirection.Z > 0, "egg3d: lit for its rarity (its own Ambient; the light from above, onto the -Z front)")
			local legLight, secLight = E3.Metrics.LIGHT.Legendary, E3.Metrics.LIGHT.Secret
			T.check(legLight[2].R > legLight[2].B and secLight[2].B > secLight[2].R, "egg3d: Legendary's light is warm, Secret's cool violet")
			T.check(math.abs(f.Size.Y.Scale - 2) < 1e-6 and math.abs(f.Size.X.Scale - 2.5) < 1e-6 and f.AnchorPoint == Vector2.new(0.5, 0.5),
				"egg3d: the frame is 2 egg heights tall (2.5 x 2 of the 2D egg's box, centred): room for the halves to fly")
			-- (the mock's tweens jump to their goal at the end and never apply an endless one: the tween is read, and the
			-- pose is driven by setting the values the tweens drive)
			local turn = f:FindFirstChild("Turn")
			local spin = G.tweenOn(turn)
			local goal = spin and Mock.TweenGoals(spin).Value
			T.check(spin ~= nil and spin.TweenInfo.RepeatCount == -1 and spin.TweenInfo.EasingStyle == Enum.EasingStyle.Linear and goal and math.abs(goal - turn.Value - 360) < 1e-6
				and math.abs(spin.TweenInfo.Time - 10) < 1e-6, "egg3d: Spin(10): an endless Linear tween of the Turn value, one turn in 10 s")
			local model = f:FindFirstChild("Egg")
			local fixed = model and model:FindFirstChild("Fixed")
			turn.Value = 90
			local p90 = fixed and fixed.CFrame
			T.check(p90 and math.abs(p90.LookVector.X) > 0.99 and math.abs(p90.Position.Y - 1.5) < 1e-3, "egg3d: the Turn value turns the egg about its upright axis (90 degrees -> facing sideways, same height)", p90 and (tostring(p90.Position) .. " look " .. tostring(p90.LookVector)) or "no part")
			view:Pose(10, -0.05)
			local pr = fixed and fixed.CFrame
			T.check(pr and math.abs(pr.Position.Y - 1.45) < 0.05 and math.abs(pr.UpVector.X) > 0.1, "egg3d: Pose(10, -0.05) rocks it about its middle and dips it", pr and (tostring(pr.Position) .. " up " .. tostring(pr.UpVector)) or "nil")
			T.check(pr and pr.UpVector.X < 0, "egg3d: ...clockwise on screen like GuiObject.Rotation (its top leans to the screen's right, -X: the camera looks along +Z)")
			view:Pose(0, 0)
			view:Settle(0.4)
			local settle = G.tweenOn(turn)
			T.check(settle ~= nil and settle.TweenInfo.RepeatCount == 0 and settle.TweenInfo.EasingStyle == Enum.EasingStyle.Quad, "egg3d: Settle eases the turn to a stop (Quad Out, no endless tween left)")
			-- the split and the flight, driven by hand
			T.check(view:CanSplit(), "egg3d: both halves usable -> CanSplit")
			T.check(view:Split() and f:FindFirstChild("Egg") == nil and f:FindFirstChild("EggTop") and f:FindFirstChild("EggBot"), "egg3d: Split swaps the whole egg for EggTop and EggBot")
			local top, bot = f:FindFirstChild("EggTop"), f:FindFirstChild("EggBot")
			local tTop, tBot = top and top:GetPivot(), bot and bot:GetPivot()
			T.check(tTop and tBot and (tTop.Position - tBot.Position).Magnitude < 1e-4, "egg3d: ...both at the whole egg's pose (they line up with it)")
			T.check(view:Fly(0.35), "egg3d: Fly starts")
			local fly = G.tweenOn(f:FindFirstChild("Fly"))
			T.check(fly ~= nil and fly.TweenInfo.EasingStyle == Enum.EasingStyle.Quart and math.abs(fly.TweenInfo.Time - 0.35) < 1e-6 and Mock.TweenGoals(fly).Value == 1,
				"egg3d: ...a Quart Out tween of the Fly value from 0 to 1 over the burst")
			local capFix = top:FindFirstChild("Fixed")
			local c0 = capFix.Position
			f:FindFirstChild("Fly").Value = 0.5
			local c5 = capFix.Position
			T.check(c5.Y > c0.Y + 0.5 and c5.X > c0.X + 0.3 and capFix.Transparency == 0,
				"egg3d: half-way: the cap (turning about its own middle) is up and to the screen's left (+X), still solid", tostring(c5))
			f:FindFirstChild("Fly").Value = 1
			local capEnd = top:GetPivot()
			T.check(capFix.Position.Y > c5.Y and capFix.Transparency > 0.99 and math.abs(capEnd.UpVector.Z) > 0.2,
				"egg3d: the end: the cap higher, tumbled (its hollow towards the camera) and faded out", tostring(capEnd.UpVector))
			T.check((bot:GetPivot().Position - tBot.Position).Magnitude < 1e-3, "egg3d: ...the cup back where it stood after its rock")
			T.eq(E3.Live(), live0 + 1, "egg3d: Live() counts the view")
			view:Destroy()
			T.check(f.Parent == nil and view.Dead and E3.Live() == live0 and G.tweenOn(f:FindFirstChild("Fly")) == nil, "egg3d: Destroy removes the frame, its tweens and the count")
		end
		-- a parent destroyed takes the view with it (its Destroying)
		local v2 = E3.New(host, "Common", {})
		host:Destroy()
		T.check(v2 ~= nil and v2.Dead and E3.Live() == live0, "egg3d: destroying the parent ends the view too")
		board:Destroy()
		------------------------------------------------------------------ the cutscene: every key uploaded -> the 3D egg and the 3D halves
		local epic = PC.RarityPool("Cloud", "Epic")[1]
		local rare = PC.RarityPool("Cloud", "Rare")[1]
		E3._ML = G.stubML(G.allKeys())
		ES.Show(G.result(PC, "Cloud", { epic }))
		local t0 = os.clock()
		T.check(G.untilPhase(ES, "Rise", 6) ~= nil, "egg3d cutscene: the roll reaches Rise")
		G.advance(STEP * 2)
		local egg = G.hero("Egg1")
		local vf = G.view(egg)
		T.check(vf ~= nil and vf:IsA("ViewportFrame") and vf:GetAttribute("Key") == "egg_epic", "egg3d cutscene: Rise: Egg1 holds the ViewportFrame egg with the key egg_epic", tostring(vf and vf:GetAttribute("Key")))
		T.check(egg and egg:GetAttribute("Egg3D") == "egg_epic" and egg:GetAttribute("Painted") == false and egg.BackgroundTransparency >= 0.999,
			"egg3d cutscene: ...the 2D paint hidden (attribute Painted false, no body fill)")
		local outline = egg and egg:FindFirstChild("Outline")
		T.check(outline == nil or outline.Enabled == false, "egg3d cutscene: ...and its outline off")
		T.check(G.hero("Backlight1") ~= nil and G.hero("CloudRing1") ~= nil and G.hero("Pedestal1") ~= nil, "egg3d cutscene: ...the backlight, the cloud ring and the pedestal (the flat plinth) stay round it")
		local ped = G.hero("Pedestal1")
		-- (roll-look, spec 16.15: rewritten from "an empty layout box") the box holds only the flat lit plinth: no drum,
		-- no puffs, no bars come back
		local parts = {}
		for _, c in ipairs(ped and ped:GetChildren() or {}) do
			if c:IsA("GuiObject") then
				parts[#parts + 1] = c.Name
			end
		end
		table.sort(parts)
		T.check(ped ~= nil and table.concat(parts, " ") == "Cover Edge Glow1 Glow2 Rim Ring Side Top Wall", "egg3d cutscene: the pedestal holds only the flat plinth (its ellipses: Top + Rim, Side + Wall + Edge, Ring + Cover, its halo; roll-look review round 2): no drum or bars come back", table.concat(parts, " "))
		T.eq(E3.Live(), 1, "egg3d cutscene: one ViewportFrame egg")
		T.check(G.untilPhase(ES, "Crack", 3) ~= nil, "egg3d cutscene: the roll reaches Crack")
		G.advance(0.45)
		local holder = G.hero("Halves1")
		T.check(holder ~= nil and holder:GetAttribute("Split3D") == true and holder:FindFirstChild("HalfTop") == nil, "egg3d cutscene: Crack: Halves1 is set to split in 3D (no 2D halves made)")
		local cracks = egg and egg:FindFirstChild("Cracks")
		T.check(cracks ~= nil and G.view(egg) ~= nil and egg.Rotation == 0, "egg3d cutscene: Crack: the glowing cracks over the 3D egg; the frame stays square (the egg rocks in 3D)")
		local rocked = false
		for _ = 1, 12 do
			G.advance(STEP)
			if cracks and math.abs(cracks.Rotation) > 0.5 then
				rocked = true
			end
		end
		T.check(rocked, "egg3d cutscene: the shakes turn the cracks with the rocking egg")
		T.check(G.untilPhase(ES, "Burst", 2) ~= nil, "egg3d cutscene: the roll reaches Burst")
		G.advance(STEP)
		holder = G.hero("Halves1")
		vf = holder and holder:FindFirstChild("Egg3D")
		T.check(vf ~= nil and holder.Visible and vf:GetAttribute("Split") == true, "egg3d cutscene: Burst: the ViewportFrame moved into the shown Halves1 and split")
		T.check(vf and vf:FindFirstChild("Egg") == nil and vf:FindFirstChild("EggTop") ~= nil and vf:FindFirstChild("EggBot") ~= nil,
			"egg3d cutscene: ...the whole egg left, EggTop and EggBot came in")
		local fly = vf and G.tweenOn(vf:FindFirstChild("Fly"))
		T.check(fly ~= nil and vf:GetAttribute("Flying") == true and Mock.TweenGoals(fly).Value == 1 and math.abs(fly.TweenInfo.Time - 0.35) < 1e-6,
			"egg3d cutscene: ...and tweened apart over the burst (the Fly tween, 0.35 s)")
		local y0, b0 = G.modelY(vf, "EggTop"), G.modelY(vf, "EggBot")
		if vf then
			vf:FindFirstChild("Fly").Value = 0.85 -- (the mock's tween only lands at its end: the pose at 85 % by hand)
		end
		local y1, b1 = G.modelY(vf, "EggTop"), G.modelY(vf, "EggBot")
		local capT = G.capT(vf)
		T.check(y0 and y1 and y1 > y0 and b1 and math.abs(b1 - b0) < 0.2 and capT and capT > 0,
			"egg3d cutscene: ...at 85 %: the cap up and fading, the cup where it stood",
			fmt("cap %s -> %s (T %s), cup %s -> %s", tostring(y0), tostring(y1), tostring(capT), tostring(b0), tostring(b1)))
		T.check(G.untilPhase(ES, "Reveal", 2) ~= nil, "egg3d cutscene: the roll reaches the reveal")
		G.advance(STEP)
		T.check(E3.Live() == 0 and G.hero("Halves1") == nil and G.hero("Egg1") == nil, "egg3d cutscene: Reveal: the halves and the view are gone (Live 0)")
		local st = ES.Stats()
		T.check(st.Instances <= 450, "egg3d cutscene: the x1 instance cap holds (a ViewportFrame counts as one)", tostring(st.Instances))
		G.advance(1)
		ES.Done()
		G.advance(0.5)
		T.check(not ES.IsShowing() and E3.Live() == 0 and ES.Stats().Instances == 0, "egg3d cutscene: DONE: nothing left")
		------------------------------------------------------------------ Skip at the crack and Close at the burst clean the view up
		ES.Show(G.result(PC, "Cloud", { epic }))
		G.untilPhase(ES, "Crack", 6)
		G.advance(0.2)
		T.eq(E3.Live(), 1, "egg3d skip: a 3D egg lives during the crack")
		ES.Skip()
		G.advance(STEP * 2)
		T.check(ES.Phase() == "Reveal" and E3.Live() == 0, "egg3d skip: Skip mid-crack -> the reveal, the view destroyed", fmt("%s / %d", tostring(ES.Phase()), E3.Live()))
		ES.Close()
		G.advance(0.5)
		ES.Show(G.result(PC, "Cloud", { epic }))
		G.untilPhase(ES, "Burst", 7)
		G.advance(STEP)
		T.check(E3.Live() == 1, "egg3d close: the split egg lives during the burst")
		ES.Close()
		G.advance(0.5)
		T.check(E3.Live() == 0 and ES.Stats().Instances == 0 and ES.Stats().Tweens == 0, "egg3d close: Close mid-burst -> no view, no tween, nothing left")
		------------------------------------------------------------------ halves with id 0: the 3D egg, then today's 2D halves under the flash
		E3._ML = G.stubML(G.wholeOnly())
		ES.Show(G.result(PC, "Cloud", { rare }))
		G.untilPhase(ES, "Rise", 6)
		G.advance(STEP * 2)
		T.check(G.view(G.hero("Egg1")) ~= nil, "egg3d halves-0: the whole egg shows in 3D")
		G.untilPhase(ES, "Crack", 3)
		G.advance(STEP)
		holder = G.hero("Halves1")
		T.check(holder ~= nil and holder:GetAttribute("Split3D") == false and holder:FindFirstChild("HalfTop") ~= nil and holder:FindFirstChild("HalfBottom") ~= nil,
			"egg3d halves-0: Crack: the halves' ids are 0 -> today's 2D HalfTop / HalfBottom are made")
		G.untilPhase(ES, "Burst", 2)
		G.advance(STEP)
		holder = G.hero("Halves1")
		T.check(E3.Live() == 0 and holder and holder.Visible and holder:FindFirstChild("Egg3D") == nil and G.shown(holder:FindFirstChild("HalfTop")),
			"egg3d halves-0: Burst: the ViewportFrame goes, the 2D halves fly under the flash")
		ES.Close()
		G.advance(0.5)
		------------------------------------------------------------------ the 2D fallbacks: id 0, Low, a failed Assemble -> today's egg exactly
		local function twoD(label, setup)
			setup()
			ES.Show(G.result(PC, "Cloud", { epic }))
			G.untilPhase(ES, "Rise", 6)
			G.advance(STEP * 2)
			local e = G.hero("Egg1")
			T.check(e ~= nil and G.view(e) == nil and e:GetAttribute("Egg3D") == nil and e:GetAttribute("Painted") ~= false and e.BackgroundTransparency < 0.5,
				label .. ": today's 2D egg (no Egg3D, painted)")
			G.untilPhase(ES, "Crack", 3)
			G.advance(STEP)
			local hd = G.hero("Halves1")
			T.check(hd and hd:FindFirstChild("HalfTop") ~= nil and hd:GetAttribute("Split3D") == false, label .. ": today's 2D halves at the crack")
			T.eq(E3.Live(), 0, label .. ": no ViewportFrame egg")
			ES.Close()
			G.advance(0.5)
		end
		twoD("egg3d id 0", function()
			E3._ML = G.stubML({})
		end)
		twoD("egg3d Low graphics", function()
			E3._ML = G.stubML(G.allKeys())
			env.mode = "Low"
		end)
		env.mode = "High"
		twoD("egg3d failed Assemble", function()
			E3._ML = G.stubML(G.allKeys(), { egg_epic = true })
		end)
		------------------------------------------------------------------ x3 keeps its 2D eggs
		E3._ML = G.stubML(G.allKeys())
		ES.Show(G.result(PC, "Cloud", { epic, rare, epic }))
		G.untilPhase(ES, "Crack", 7)
		G.advance(STEP)
		local any = false
		for j = 1, 3 do
			any = any or G.view(G.hero("Egg" .. j)) ~= nil
		end
		T.check(not any and E3.Live() == 0, "egg3d x3: the three eggs stay 2D (no ViewportFrame)")
		ES.Close()
		G.advance(0.5)
		------------------------------------------------------------------ the Shop's hero egg
		Shop.Open({ Tab = "Eggs" })
		G.advance(1)
		local shopGui = G.pg():FindFirstChild("NimbusShop")
		local page = shopGui and shopGui:FindFirstChild("Page_Eggs", true)
		local fx = page and SE.Fx(page)
		local heroEgg = fx and fx.Egg
		local hv = heroEgg and G.view(heroEgg)
		T.check(hv ~= nil and hv:GetAttribute("Key") == "egg_secret" and fx.Egg3D ~= nil and heroEgg:GetAttribute("Painted") == false,
			"egg3d shop: the Eggs page shows the real Secret egg in a ViewportFrame in HeroEgg (the 2D paint hidden)", tostring(hv and hv:GetAttribute("Key")))
		local spin = hv and G.tweenOn(hv:FindFirstChild("Turn"))
		T.check(spin ~= nil and spin.TweenInfo.RepeatCount == -1 and math.abs(spin.TweenInfo.Time - 16) < 1e-6, "egg3d shop: ...turning slowly (one turn in 16 s, endless)")
		T.check(hv and math.abs(hv.Size.Y.Scale - 1.15) < 1e-6, "egg3d shop: ...in a frame 1.15 egg heights tall (no halves fly here)")
		Shop.Close()
		G.advance(0.5)
		T.check(E3.Live() == 0 and heroEgg and G.view(heroEgg) == nil and heroEgg:GetAttribute("Painted") == true,
			"egg3d shop: the Shop closed -> the view destroyed, the 2D egg painted again")
		env.mode = "Low"
		Shop.Open({ Tab = "Eggs" })
		G.advance(1)
		T.check(heroEgg and G.view(heroEgg) == nil and E3.Live() == 0, "egg3d shop: Low graphics -> the 2D hero egg")
		Shop.Close()
		env.mode = "High"
		G.advance(0.5)
	end)
	if not ok then
		T.check(false, "egg3d: the scenario ran without an error", tostring(err))
	end
	G.restore(env)
end)

----------------------------------------------------------------------------------------------------
-- client_egg3d_phone
----------------------------------------------------------------------------------------------------
S.client_egg3d_phone = guarded("client_egg3d_phone", function()
	local env = G.setup(844, 390)
	local ES, E3, PC, Shop, SE = env.ES, env.E3, env.PC, env.Shop, env.SE
	if not T.check(type(ES) == "table" and type(E3) == "table" and type(PC) == "table", "egg3d phone: EggStage, Egg3D and PetCatalog load") then
		G.restore(env)
		return
	end
	local ok, err = pcall(function()
		T.eq(E3.Limit(true), 1, "egg3d phone: the phone limit is one ViewportFrame egg")
		E3._ML = G.stubML(G.allKeys())
		local epic = PC.RarityPool("Cloud", "Epic")[1]
		ES.Show(G.result(PC, "Cloud", { epic }))
		T.check(ES.Layout() ~= "PC", "egg3d phone: (setup) the stage lays out for a phone", tostring(ES.Layout()))
		G.untilPhase(ES, "Rise", 6)
		G.advance(STEP * 2)
		T.check(G.view(G.hero("Egg1")) ~= nil and E3.Live() == 1, "egg3d phone: the cutscene's x1 egg is the ViewportFrame egg")
		local board = Instance.new("ScreenGui")
		board.Name = "SmokeEgg3DPhone"
		board.Parent = G.pg()
		local v, why = E3.New(board, "Rare", { Phone = true })
		T.check(v == nil and why == "limit" and E3.Live() == 1, "egg3d phone: a second ViewportFrame egg is refused (\"limit\") while one lives", tostring(why))
		board:Destroy()
		ES.Close()
		G.advance(0.5)
		T.eq(E3.Live(), 0, "egg3d phone: closing frees the slot")
		if Shop and SE then
			Shop.Open({ Tab = "Eggs" })
			G.advance(1)
			local shopGui = G.pg():FindFirstChild("NimbusShop")
			local page = shopGui and shopGui:FindFirstChild("Page_Eggs", true)
			local fx = page and SE.Fx(page)
			T.check(fx and fx.Egg3D == nil and E3.Live() == 0, "egg3d phone: the phone's Shop hero has no room for the egg: no ViewportFrame")
			Shop.Close()
			G.advance(0.5)
		end
	end)
	if not ok then
		T.check(false, "egg3d phone: the scenario ran without an error", tostring(err))
	end
	G.restore(env)
end)

return S
