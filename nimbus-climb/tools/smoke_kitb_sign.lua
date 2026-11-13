-- smoke_kitb_sign.lua: the main menu sign build (branch kitb-sign; the owner's picks on .superpowers/sign-pitch/sign_pitch.html:
-- entrance "A Rope drop" with the note "more gentle shake, make it stay moving gently after dropping", detail
-- "A Workshop"), the short-screen fit fix seen in Studio and the U4 minors. Client world only; registered on its own
-- line in tools/smoke.py.
--   menu_entrance_after_loading  the board waits lifted while the loading screen is up AND while it fades; it falls only
--                                once NimbusLoading is gone; with no loading screen (/menu) it falls at once
--   menu_drop_gentle             Config.MainMenu.Entrance: a fall on the ropes (Quad In) to the snap, then gentle bounces
--                                (<= 16 design px, at most 2, smaller each time; the pitch had 26 / 7 at a 250 px board)
--                                and a gentle swing (<= 2 degrees; the pitch had 3); never below its rest place, no
--                                instant 2 degree snap; at the snap two flat white pixel dust puffs (Frames only) and the
--                                thunk hook (SoundFx.Play(Entrance.Sound)); the rope tops stay above the screen; the
--                                buttons pop from their centre
--   menu_idle_sway_runs_and_stops after the entrance an endless Sine InOut sway of +-Sway.Degrees (a 3-4 s period) on the
--                                Swing (pivot at the rope tops); the buttons still click; Camera shake OFF stops it (and
--                                ON brings it back); PLAY cancels it and leaves no tween or viewport watch behind; the
--                                release waits for the 0.8 s camera move; a menu opened with shake OFF never sways
--   signkit_workshop_parts       SignKit.Workshop on the menu board and the loading screen's board: wood grain strips
--                                (dark and light), 4 iron nails (a darker bottom-right), a metal ring on each rope, the
--                                striped awning with a notched (stepped) lip, one chipped corner; Frames only, no stroke,
--                                gradient, corner or image, palette colours only; the Credits window has none (opt-out).
--                                Review: sized for the board (about 1.75x the pitch's 250 px board): grain 2 screen px or
--                                wider (phone 0.8 too), nails 10 px+ in the face corners (header ones clear of the
--                                teeth), rings 28 x 20+, the chip a bite that shows what is behind, a crack beside it
--   menu_fits_short_viewport     1274x580 and 1366x600: the (swinging) board ends 16 px or more above the screen bottom,
--                                the CREDITS tag and its "vN" on screen; built at 1920x1080 and resized to 1274x580 the
--                                menu lays itself out again; the loading screen's board fits too (and after a resize)
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local fmt = string.format

local function hex(c)
	if typeof(c) ~= "Color3" then
		return tostring(c)
	end
	return fmt("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function clientScenarios()
	local S = {}
	local KC = _G.KC

	local function shared(name)
		local inst = Mock.GetPath(ROOTS.shared .. "/" .. name)
		local ok, mod = false, nil
		if inst then
			ok, mod = pcall(require, inst)
		end
		return ok and mod or nil
	end
	local function client(path)
		local inst = Mock.GetPath(ROOTS["client"] .. "/" .. path)
		local ok, mod = false, nil
		if inst then
			ok, mod = pcall(require, inst)
		end
		return ok and mod or nil
	end
	local function pg()
		return game:GetService("Players").LocalPlayer.PlayerGui
	end
	local function attr()
		local Config = shared("Config")
		return (Config and Config.Attr and Config.Attr.ProfileLoaded) or "ProfileLoaded"
	end
	local function tweensOf(inst, prop)
		local out = {}
		for tw in pairs(Mock.ActiveTweens) do
			if tw.Instance == inst and Mock.TweenGoals(tw)[prop] ~= nil then
				out[#out + 1] = tw
			end
		end
		return out
	end
	local function endless(inst, prop)
		for _, tw in ipairs(tweensOf(inst, prop)) do
			if tw.TweenInfo.RepeatCount < 0 then
				return tw
			end
		end
		return nil
	end
	local function rect(obj)
		local p, s = obj.AbsolutePosition, obj.AbsoluteSize
		return { X = p.X, Y = p.Y, R = p.X + s.X, B = p.Y + s.Y }
	end
	local function show(r)
		return fmt("%d,%d..%d,%d", r.X, r.Y, r.R, r.B)
	end

	-- the loading screen (src/first/LoadingScreen.client.lua run afresh, the profile held back: no Done)
	local Load = {}
	function Load.run(size, wait)
		if size then
			Mock.SetViewport(size[1], size[2])
			KC.advance(0.1)
		end
		local lp = game:GetService("Players").LocalPlayer
		local folder = ROOTS["first"] and Mock.GetPath(ROOTS["first"]) or nil
		local script = folder and folder:FindFirstChild("LoadingScreen") or nil
		if not script then
			return nil
		end
		local before = {}
		for _, g in ipairs(pg():GetChildren()) do
			before[g] = true
		end
		lp:SetAttribute(attr(), nil)
		Mock.RunScript(script)
		KC.advance(wait or 0.6)
		for _, g in ipairs(pg():GetChildren()) do
			if not before[g] and g.Name == "NimbusLoading" then
				return g
			end
		end
		return nil
	end
	function Load.cleanup()
		game:GetService("Players").LocalPlayer:SetAttribute(attr(), true)
		for _, g in ipairs(pg():GetChildren()) do
			if g.Name == "NimbusLoading" then
				g:SetAttribute("Done", true)
			end
		end
		KC.advance(4)
		for _, g in ipairs(pg():GetChildren()) do
			if g.Name == "NimbusLoading" then
				g:Destroy()
			end
		end
		Mock.SetViewport(1920, 1080)
		KC.advance(0.1)
	end

	-- the title screen (MenuPlay counts as sent, so PLAY never spawns anything)
	local Menu = {}
	function Menu.mmc()
		return client("Controllers/MainMenuController")
	end
	function Menu.open(opts)
		opts = opts or {}
		local UIS = game:GetService("UserInputService")
		Menu.old = Menu.old or { Mock.Viewport, UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled, UIS.GamepadEnabled }
		local input = opts.Input or "Keyboard"
		UIS.TouchEnabled = input == "Touch"
		UIS.KeyboardEnabled = input == "Keyboard"
		UIS.MouseEnabled = input == "Keyboard"
		UIS.GamepadEnabled = input == "Gamepad"
		local size = opts.Size or { 1920, 1080 }
		Mock.SetViewport(size[1], size[2])
		KC.advance(0.1)
		shared("Config").MainMenu.Enabled = true
		local MMC = Menu.mmc()
		MMC._M.SentPlay = true
		MMC.Open()
		KC.advance(opts.Wait or 2.5)
		local gui = pg():FindFirstChild("NimbusMainMenu")
		return gui and gui:FindFirstChild("Menu"), MMC
	end
	function Menu.close()
		local MMC = Menu.mmc()
		if MMC.IsOpen() then
			MMC.CloseWindows()
			MMC.Play()
			KC.advance(1.5)
		end
		shared("Config").MainMenu.Enabled = false
		local old = Menu.old
		if old then
			local UIS = game:GetService("UserInputService")
			Mock.SetViewport(old[1].X, old[1].Y)
			UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled, UIS.GamepadEnabled = old[2], old[3], old[4], old[5]
			KC.advance(0.1)
		end
		Menu.old = nil
	end
	function Menu.find(root, name)
		return root and root:FindFirstChild(name, true) or nil
	end
	function Menu.ropes(swing)
		local out = {}
		for _, d in ipairs(swing:GetChildren()) do
			if d:GetAttribute("SignKit") == "Rope" then
				out[#out + 1] = d
			end
		end
		return out
	end

	-- the workshop trim under a root, by kind (attribute Workshop)
	local function trim(root)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:GetAttribute("SignKit") == "Workshop" then
				local kind = d:GetAttribute("Workshop") or "?"
				out[kind] = out[kind] or {}
				table.insert(out[kind], d)
			end
		end
		return out
	end
	local function count(t, kind)
		return #(t[kind] or {})
	end

	------------------------------------------------------------------------------------------------
	S.menu_entrance_after_loading = guarded("menu_entrance_after_loading", function()
		local lg = nil
		local ok, err = pcall(function()
			lg = Load.run()
			if not T.check(lg ~= nil and lg:GetAttribute("Done") ~= true, "sign after loading: (setup) the loading screen is up, no Done") then
				return
			end
			local menu, MMC = Menu.open({ Wait = 0.05 })
			local swing = Menu.find(menu, "Swing")
			local rest = MMC._M.Ui and MMC._M.Ui.Rest
			if not T.check(swing ~= nil and rest ~= nil, "sign after loading: (setup) the Swing exists") then
				return
			end
			KC.advance(1)
			T.eq(#tweensOf(swing, "Position"), 0, "sign after loading: no fall while the loading screen is up")
			lg:SetAttribute("Done", true)
			KC.advance(0.1)
			T.check(lg.Parent ~= nil, "sign after loading: (setup) the loading screen is fading")
			T.eq(#tweensOf(swing, "Position"), 0, "sign after loading: no fall while the loading screen fades")
			T.check(swing.Position.Y.Offset < rest.Y.Offset - 100, "sign after loading: the board still waits lifted during the fade",
				fmt("%d vs rest %d", swing.Position.Y.Offset, rest.Y.Offset))
			KC.advance(0.45)
			T.check(lg.Parent == nil, "sign after loading: the loading screen has faded away")
			local drop = tweensOf(swing, "Position")[1]
			local goal = drop and Mock.TweenGoals(drop).Position
			T.check(goal ~= nil and goal.Y.Offset == rest.Y.Offset and goal.X.Offset == rest.X.Offset, "sign after loading: then the board falls to its rest place")
			KC.advance(2.5)
			T.check(swing.Position.Y.Offset == rest.Y.Offset, "sign after loading: at rest after the entrance")
			Menu.close()
			-- /menu (no loading screen): the fall starts at once
			local menu2 = Menu.open({ Wait = 0.05 })
			local swing2 = Menu.find(menu2, "Swing")
			T.check(swing2 ~= nil and #tweensOf(swing2, "Position") == 1, "sign after loading: with no loading screen the board falls at once")
		end)
		if lg and lg.Parent then
			lg:SetAttribute("Done", true)
			KC.advance(0.6)
		end
		Menu.close()
		Load.cleanup()
		T.check(ok, "sign after loading: the scenario ran", tostring(err))
		KC.flushErrors("menu_entrance_after_loading")
	end)

	------------------------------------------------------------------------------------------------
	S.menu_drop_gentle = guarded("menu_drop_gentle", function()
		local SoundFx = client("SoundFx")
		local played = {}
		local realPlay = SoundFx and SoundFx.Play
		local ok, err = pcall(function()
			local Config = shared("Config")
			local E = Config.MainMenu.Entrance
			local W = Config.MainMenu.Sway
			if not T.check(type(E) == "table" and type(W) == "table", "sign drop: Config.MainMenu.Entrance and Sway exist") then
				return
			end
			-- gentler than the pitch mock (26 / 7 px at a 250 px board = 46 / 12 design px; 3 / -2 / 1 degrees)
			local bounces = E.Bounce or {}
			T.check(#bounces >= 1 and #bounces <= 2 and bounces[1] <= 16, "sign drop: at most two bounces, the first 16 design px or less", fmt("%d: %s", #bounces, tostring(bounces[1])))
			T.check(#bounces < 2 or bounces[2] < bounces[1], "sign drop: each bounce smaller than the one before")
			local maxSwing = 0
			for _, d in ipairs(E.Swing or {}) do
				maxSwing = math.max(maxSwing, math.abs(d))
			end
			T.check(maxSwing > 0 and maxSwing <= 2, "sign drop: the swing stays within 2 degrees", tostring(maxSwing))
			T.check(type(E.Sound) == "string" and E.Sound ~= "", "sign drop: a named thunk hook (Entrance.Sound)")
			if SoundFx then
				SoundFx.Play = function(name, o)
					played[#played + 1] = name
					return realPlay(name, o)
				end
			end
			local menu, MMC = Menu.open({ Wait = 0.05 })
			local swing = Menu.find(menu, "Swing")
			local rest = MMC._M.Ui and MMC._M.Ui.Rest
			if not T.check(swing ~= nil and rest ~= nil, "sign drop: (setup) the Swing exists") then
				return
			end
			local f = shared("Theme").ScreenFactor(1080)
			local drop = tweensOf(swing, "Position")[1]
			local info = drop and drop.TweenInfo
			T.check(info ~= nil and math.abs(info.Time - E.Drop) < 1e-6 and info.EasingStyle == Enum.EasingStyle.Quad and info.EasingDirection == Enum.EasingDirection.In,
				"sign drop: it falls on its ropes (Position, Entrance.Drop, Quad In)", info and fmt("%.2f %s %s", info.Time, tostring(info.EasingStyle), tostring(info.EasingDirection)) or "no tween")
			T.check(swing.Position.Y.Offset < rest.Y.Offset - 100, "sign drop: ...from above the screen")
			-- the buttons pop from their centre
			for _, name in ipairs({ "PlayButton", "SettingsButton", "UpdatesButton" }) do
				local b = Menu.find(menu, name)
				T.check(b ~= nil and b:FindFirstChild("Pop") ~= nil and b.AnchorPoint.X == 0.5 and b.AnchorPoint.Y == 0.5, "sign drop: " .. name .. " pops from its centre (AnchorPoint 0.5, 0.5)",
					b and tostring(b.AnchorPoint) or "missing")
			end
			-- through the snap and the bounces: sample the tweens every frame
			local lowest, highest, ups, maxDeg, firstRot = rest.Y.Offset, rest.Y.Offset, 0, 0, nil
			local seen, puffs, puffBad, snapRot = {}, 0, {}, nil
			local t = 0
			while t < E.Drop + 2 do
				KC.advance(1 / 30)
				t = t + 1 / 30
				for _, tw in ipairs(tweensOf(swing, "Position")) do
					if not seen[tw] then
						seen[tw] = true
						local y = Mock.TweenGoals(tw).Position.Y.Offset
						lowest = math.max(lowest, y)
						highest = math.min(highest, y)
						if y < rest.Y.Offset then
							ups = ups + 1
						end
					end
				end
				for _, tw in ipairs(tweensOf(swing, "Rotation")) do
					if not seen[tw] then
						seen[tw] = true
						local g = Mock.TweenGoals(tw).Rotation
						if tw.TweenInfo.RepeatCount >= 0 then
							maxDeg = math.max(maxDeg, math.abs(g))
						end
						if firstRot == nil then
							firstRot = g
							snapRot = swing.Rotation
						end
					end
				end
				for _, d in ipairs(menu:GetDescendants()) do
					if d.Name == "DustPuff" and not seen[d] then
						seen[d] = true
						puffs = puffs + 1
						for _, p in ipairs(d:GetDescendants()) do
							if p:IsA("GuiObject") and not p:IsA("Frame") or p:IsA("UIStroke") or p:IsA("UIGradient") or p:IsA("UICorner") then
								puffBad[#puffBad + 1] = p.ClassName
							elseif p:IsA("Frame") and p.BackgroundTransparency < 1 and hex(p.BackgroundColor3) ~= "#FFFFFF" then
								puffBad[#puffBad + 1] = hex(p.BackgroundColor3)
							end
						end
					end
				end
			end
			T.check(lowest <= rest.Y.Offset, "sign drop: never below its rest place (no overshoot past the ropes' length)", fmt("lowest goal %d vs rest %d", lowest, rest.Y.Offset))
			T.check(ups >= 1 and ups <= 2, "sign drop: it bounces back up once or twice after the snap", tostring(ups))
			T.check(rest.Y.Offset - highest <= 16, "sign drop: the bounce is gentle (16 design px or less)", tostring(rest.Y.Offset - highest))
			T.check(firstRot ~= nil and snapRot ~= nil and math.abs(snapRot) < 1e-6, "sign drop: the swing starts from level (no instant 2 degree snap)", tostring(snapRot))
			T.check(maxDeg > 0 and maxDeg <= 2.001, "sign drop: the snap swings it gently (2 degrees or less)", tostring(maxDeg))
			T.eq(puffs, 2, "sign drop: two dust puffs at the snap")
			T.check(#puffBad == 0, "sign drop: the puffs are flat white pixel Frames (no image, stroke, gradient or corner)", table.concat(puffBad, ", "))
			local thunk = false
			for _, name in ipairs(played) do
				if name == E.Sound then
					thunk = true
				end
			end
			T.check(thunk, "sign drop: the thunk hook plays at the snap (SoundFx.Play(" .. tostring(E.Sound) .. "))", table.concat(played, ", "))
			local left = 0
			for _, d in ipairs(menu:GetDescendants()) do
				if d.Name == "DustPuff" then
					left = left + 1
				end
			end
			T.eq(left, 0, "sign drop: the puffs are gone after the entrance")
			T.check(swing.Position.Y.Offset == rest.Y.Offset, "sign drop: at rest after the entrance")
			-- the rope tops stay above the screen top, even at the top of the highest bounce
			local ropes = Menu.ropes(swing)
			local shown = {}
			for _, rope in ipairs(ropes) do
				local top = rope.AbsolutePosition.Y - (rest.Y.Offset - highest) * f
				if top > -8 then
					shown[#shown + 1] = fmt("%.0f", top)
				end
			end
			T.check(#ropes == 2 and #shown == 0, "sign drop: the rope tops stay above the screen through the bounce", table.concat(shown, ", "))
		end)
		if SoundFx and realPlay then
			SoundFx.Play = realPlay
		end
		Menu.close()
		T.check(ok, "sign drop: the scenario ran", tostring(err))
		KC.flushErrors("menu_drop_gentle")
	end)

	------------------------------------------------------------------------------------------------
	S.menu_idle_sway_runs_and_stops = guarded("menu_idle_sway_runs_and_stops", function()
		local Settings = client("ClientSettings")
		local ok, err = pcall(function()
			local Config = shared("Config")
			local W = Config.MainMenu.Sway
			if not T.check(Settings ~= nil and type(W) == "table", "sign sway: (setup) ClientSettings and Config.MainMenu.Sway") then
				return
			end
			Settings.Set("Shake", true)
			local menu, MMC = Menu.open({ Wait = 3 })
			local swing = Menu.find(menu, "Swing")
			if not T.check(swing ~= nil, "sign sway: (setup) the Swing exists") then
				return
			end
			local sway = endless(swing, "Rotation")
			local info = sway and sway.TweenInfo
			local goal = sway and Mock.TweenGoals(sway).Rotation
			T.check(info ~= nil and info.Reverses == true and info.EasingStyle == Enum.EasingStyle.Sine and info.EasingDirection == Enum.EasingDirection.InOut,
				"sign sway: after the entrance the board sways endlessly, back and forth, Sine InOut")
			T.check(info ~= nil and info.Time * 2 >= 3 and info.Time * 2 <= 4, "sign sway: ...a 3-4 s period", info and fmt("%.2f s", info.Time * 2) or "")
			T.check(goal ~= nil and math.abs(math.abs(goal) - W.Degrees) < 1e-6 and math.abs(swing.Rotation + goal) < 1e-6 and W.Degrees <= 1.2,
				"sign sway: ...from -" .. tostring(W.Degrees) .. " to +" .. tostring(W.Degrees) .. " degrees", fmt("%.2f -> %s", swing.Rotation, tostring(goal)))
			T.check(swing.AnchorPoint.Y == 0.5 and swing.Position.Y.Offset == 0, "sign sway: it turns about the rope tops (the Swing's centre at the screen top)")
			-- the buttons still click while it sways
			local settings = Menu.find(menu, "SettingsButton")
			T.check(settings ~= nil and settings.Active, "sign sway: SETTINGS is active while it sways")
			Mock.Click(settings)
			KC.advance(0.2)
			local _, name = MMC.Window()
			T.eq(name, "Settings", "sign sway: a click on SETTINGS opens the window while it sways")
			MMC.CloseWindows()
			KC.advance(0.1)
			T.check(endless(swing, "Rotation") ~= nil, "sign sway: still swaying after the window closed")
			-- Camera shake OFF stops it, ON brings it back
			Settings.Set("Shake", false)
			KC.advance(1)
			T.check(endless(swing, "Rotation") == nil and math.abs(swing.Rotation) < 1e-6, "sign sway: Camera shake OFF stops the sway and levels the board", fmt("%.2f", swing.Rotation))
			Settings.Set("Shake", true)
			KC.advance(1)
			T.check(endless(swing, "Rotation") ~= nil, "sign sway: Camera shake ON brings the sway back")
			-- PLAY: the sway stops, the release waits for the camera move, nothing is left behind
			local camera = workspace.CurrentCamera
			MMC.Play()
			KC.advance(0.05)
			T.check(endless(swing, "Rotation") == nil, "sign sway: PLAY cancels the sway at once")
			KC.advance(0.5)
			T.check(MMC.IsOpen() and camera.CameraType == Enum.CameraType.Scriptable, "sign sway: the release waits while the camera still flies (0.55 s in)")
			KC.advance(0.45)
			T.check(not MMC.IsOpen() and camera.CameraType == Enum.CameraType.Custom, "sign sway: released once the 0.8 s camera move has landed")
			KC.advance(0.5)
			local left = {}
			for tw in pairs(Mock.ActiveTweens) do
				local inst = tw.Instance
				if inst and (inst == swing or inst:IsDescendantOf(menu) or inst == menu) then
					left[#left + 1] = inst.Name
				end
			end
			T.check(#left == 0, "sign sway: no tween left on the old menu after PLAY", table.concat(left, ", "))
			T.check(MMC._M.Resize == nil, "sign sway: the viewport watch is disconnected after PLAY")
			-- a menu opened with Camera shake OFF never sways
			Settings.Set("Shake", false)
			local menu2 = Menu.open({ Wait = 3 })
			local swing2 = Menu.find(menu2, "Swing")
			T.check(swing2 ~= nil and endless(swing2, "Rotation") == nil and math.abs(swing2.Rotation) < 1e-6, "sign sway: with Camera shake OFF the board rests level, no sway",
				swing2 and fmt("%.2f", swing2.Rotation) or "")
		end)
		Menu.close()
		if Settings then
			Settings.Set("Shake", true)
		end
		T.check(ok, "sign sway: the scenario ran", tostring(err))
		KC.flushErrors("menu_idle_sway_runs_and_stops")
	end)

	------------------------------------------------------------------------------------------------
	S.signkit_workshop_parts = guarded("signkit_workshop_parts", function()
		local ok, err = pcall(function()
			local Theme = shared("Theme")
			local SignKit = shared("SignKit")
			if not T.check(Theme ~= nil and SignKit ~= nil and type(SignKit.Workshop) == "function", "sign trim: SignKit.Workshop exists") then
				return
			end
			local allowed = {}
			for _, c in pairs(Theme.Sign) do
				allowed[hex(c)] = true
			end
			for _, c in pairs(SignKit.WorkshopColors or {}) do
				allowed[hex(c)] = true
			end
			-- an opaque Frame under root covering the screen point (x, y)
			local function covered(root, x, y)
				for _, d in ipairs(root:GetDescendants()) do
					if d:IsA("GuiObject") and d.Visible and d.BackgroundTransparency < 1 then
						local r = rect(d)
						if x >= r.X and x < r.R and y >= r.Y and y < r.B then
							return d
						end
					end
				end
				return nil
			end
			local function inside(a, b)
				return a.X >= b.X - 0.5 and a.R <= b.R + 0.5 and a.Y >= b.Y - 0.5 and a.B <= b.B + 0.5
			end
			local function checkTrim(root, where, ropes)
				local t = trim(root)
				T.check(count(t, "Grain") >= 4, "sign trim: wood grain strips in the frame on the " .. where, tostring(count(t, "Grain")))
				-- (review) the grain reads: every strip at least 2 screen px wide (at the phones' 0.8 scale too), never a 1 px shimmer
				local dark, light, thinnest = false, false, math.huge
				for _, g in ipairs(t.Grain or {}) do
					local w = math.min(g.AbsoluteSize.X, g.AbsoluteSize.Y)
					thinnest = math.min(thinnest, w)
					local thin = w <= 4
					if thin and hex(g.BackgroundColor3) == hex(SignKit.WorkshopColors.Grain) then
						dark = true
					elseif thin and hex(g.BackgroundColor3) == hex(SignKit.WorkshopColors.GrainLight) then
						light = true
					end
				end
				T.check(dark and light, "sign trim: the grain has darker and lighter thin strips on the " .. where)
				T.check(thinnest >= 1.99, "sign trim: every grain strip is 2 screen px or wider on the " .. where, fmt("thinnest %.2f px", thinnest))
				T.eq(count(t, "Nail"), 4, "sign trim: four iron nails on the " .. where)
				local nailOk = true
				for _, n in ipairs(t.Nail or {}) do
					local cap = n:FindFirstChild("TrimCap")
					if not (cap and cap.Position.X.Offset == 0 and cap.Position.Y.Offset == 0 and cap.Size.X.Offset < n.Size.X.Offset and cap.Size.Y.Offset < n.Size.Y.Offset
						and hex(n.BackgroundColor3) == hex(SignKit.WorkshopColors.IronDark) and hex(cap.BackgroundColor3) == hex(SignKit.WorkshopColors.Iron)) then
						nailOk = false
					end
				end
				T.check(nailOk, "sign trim: each nail is a square with a darker bottom-right on the " .. where)
				-- (review) nails sized for the board (the pitch's 6 px at 250 px, about 1.75x) and in the face corners as in the
				-- pitch: two on the navy plate below the awning's teeth, two on the body above its lip; none on a rail
				local plate, body = Menu.find(root, "Plate"), Menu.find(root, "Body")
				local teethB = -math.huge
				for _, tooth in ipairs(t.Tooth or {}) do
					for _, d in ipairs({ tooth, unpack(tooth:GetDescendants()) }) do
						teethB = math.max(teethB, rect(d).B)
					end
				end
				local small, onPlate, onBody, underTeeth = {}, 0, 0, 0
				for _, n in ipairs(t.Nail or {}) do
					if n.Size.X.Offset < 10 or n.Size.Y.Offset < 10 then
						small[#small + 1] = fmt("%dx%d", n.Size.X.Offset, n.Size.Y.Offset)
					end
					local r = rect(n)
					if plate and inside(r, rect(plate)) then
						onPlate = onPlate + 1
						if r.Y < teethB + 1 then
							underTeeth = underTeeth + 1
						end
					elseif body and inside(r, rect(body)) then
						onBody = onBody + 1
					end
				end
				T.check(#small == 0, "sign trim: the nails are 10 design px or more on the " .. where, table.concat(small, ", "))
				T.check(onPlate == 2 and onBody == 2, "sign trim: two nails in the header's face corners and two in the body's on the " .. where, fmt("%d on the plate, %d on the body", onPlate, onBody))
				T.eq(underTeeth, 0, "sign trim: the header's nails sit clear of the awning's notched teeth on the " .. where)
				T.eq(count(t, "Ring"), 2, "sign trim: a metal ring where each rope ties on, on the " .. where)
				local ringOk = true
				for _, r in ipairs(t.Ring or {}) do
					if r.Size.X.Offset < 28 or r.Size.Y.Offset < 20 then
						ringOk = false
					end
				end
				T.check(ringOk, "sign trim: the rope rings are sized for the board (28 x 20 design px or more) on the " .. where)
				local onRopes = 0
				for _, r in ipairs(t.Ring or {}) do
					for _, rope in ipairs(ropes) do
						if r.Parent == rope then
							onRopes = onRopes + 1
						end
					end
				end
				T.eq(onRopes, 2, "sign trim: the rings sit on the two ropes on the " .. where)
				T.check(count(t, "Stripe") >= 10, "sign trim: the awning is striped on the " .. where, tostring(count(t, "Stripe")))
				T.check(count(t, "Tooth") >= 10, "sign trim: the awning has a notched lip on the " .. where, tostring(count(t, "Tooth")))
				T.eq(count(t, "Chip"), 1, "sign trim: one chipped corner on the " .. where)
				-- (review) the chip is a bite out of the board's bottom-right corner (through the frame into the body) that shows
				-- what is behind the board, a dark crack beside it; the rail further left is still wood
				local wood = Menu.find(root, "Wood")
				if wood and body then
					local w, b = rect(wood), rect(body)
					local hit0 = covered(root, w.R - 1, w.B - 1)
					local hit1 = covered(root, b.R - 1, b.B - 1)
					T.check(hit0 == nil and hit1 == nil, "sign trim: the chipped corner shows what is behind the board (frame and body corner bitten) on the " .. where,
						fmt("%s / %s", hit0 and hit0:GetFullName() or "clear", hit1 and hit1:GetFullName() or "clear"))
					T.check(covered(root, w.R - 0.25 * (w.R - w.X), w.B - 1) ~= nil and covered(root, w.R - 1, w.B - 0.5 * (w.B - w.Y)) ~= nil,
						"sign trim: the rails away from the chip are still wood on the " .. where)
					local crack = false
					for _, c in ipairs(t.Chip or {}) do
						for _, d in ipairs(c:GetDescendants()) do
							local r = rect(d)
							if d:IsA("Frame") and hex(d.BackgroundColor3) == hex(SignKit.WorkshopColors.Grain) and r.X > w.R - 40 and r.Y > w.B - 40 then
								crack = true
							end
						end
					end
					T.check(crack, "sign trim: a dark crack beside the chip on the " .. where)
				end
				local bad = {}
				for _, list in pairs(t) do
					for _, part in ipairs(list) do
						for _, d in ipairs({ part, unpack(part:GetDescendants()) }) do
							if d:IsA("UIStroke") or d:IsA("UIGradient") or d:IsA("UICorner") or d:IsA("ImageLabel") or d:IsA("ImageButton") or d:IsA("TextLabel") then
								bad[#bad + 1] = d.ClassName
							elseif d:IsA("Frame") and d.BackgroundTransparency < 1 and not allowed[hex(d.BackgroundColor3)] then
								bad[#bad + 1] = d.Name .. " " .. hex(d.BackgroundColor3)
							end
						end
					end
				end
				T.check(#bad == 0, "sign trim: flat Frames in the palette only (no stroke, gradient, corner, image) on the " .. where, table.concat(bad, ", ", 1, math.min(#bad, 6)))
				return t
			end
			-- the title screen's board
			local menu, MMC = Menu.open({ Wait = 2.5 })
			local swing = Menu.find(menu, "Swing")
			if T.check(swing ~= nil, "sign trim: (setup) the menu board") then
				local t = checkTrim(swing, "menu board", Menu.ropes(swing))
				-- the notched lip fits under the awning
				local roof = Menu.find(swing, "Roof")
				local over = 0
				for _, tooth in ipairs(t.Tooth or {}) do
					local r = rect(tooth)
					if r.X < roof.AbsolutePosition.X - 0.5 or r.R > roof.AbsolutePosition.X + roof.AbsoluteSize.X + 0.5 then
						over = over + 1
					end
				end
				T.eq(over, 0, "sign trim: the notched lip stays within the awning's width")
			end
			-- Credits opts out: none of the trim in its window
			MMC.OpenCredits()
			KC.advance(0.3)
			local holder = MMC.Window()
			if T.check(holder ~= nil, "sign trim: (setup) the Credits window opens") then
				local n = 0
				for _ in pairs(trim(holder)) do
					n = n + 1
				end
				T.eq(n, 0, "sign trim: the Credits window carries none of the workshop trim (opt-out)")
			end
			MMC.CloseWindows()
			Menu.close()
			-- (review) on a phone (factor 0.8) the trim still reads: grain 2 screen px or wider, the nails, the chip
			local pmenu = Menu.open({ Size = { 844, 390 }, Input = "Touch" })
			local pswing = Menu.find(pmenu, "Swing")
			if T.check(pswing ~= nil, "sign trim: (setup) the menu board at 844x390") then
				checkTrim(pswing, "menu board at 844x390", Menu.ropes(pswing))
			end
			Menu.close()
			-- the loading screen's board gets the same trim (once SignKit is there), and keeps it fitted after a resize
			local lg = Load.run({ 1920, 1080 })
			local lswing = lg and lg:FindFirstChild("Swing", true)
			if T.check(lswing ~= nil, "sign trim: (setup) the loading screen's board") then
				checkTrim(lswing, "loading board", Menu.ropes(lswing))
				Mock.SetViewport(1274, 580)
				KC.advance(0.3)
				local roof = lswing:FindFirstChild("Roof", true)
				local over = 0
				local t = checkTrim(lswing, "loading board at 1274x580", Menu.ropes(lswing))
				for _, tooth in ipairs(t.Tooth or {}) do
					local r = rect(tooth)
					if r.R > roof.AbsolutePosition.X + roof.AbsoluteSize.X + 0.5 then
						over = over + 1
					end
				end
				T.check(count(t, "Tooth") >= 10 and over == 0, "sign trim: after a resize the loading screen's notched lip still fits its awning", fmt("%d teeth, %d past the edge", count(t, "Tooth"), over))
			end
		end)
		Menu.close()
		Load.cleanup()
		T.check(ok, "sign trim: the scenario ran", tostring(err))
		KC.flushErrors("signkit_workshop_parts")
	end)

	------------------------------------------------------------------------------------------------
	S.menu_fits_short_viewport = guarded("menu_fits_short_viewport", function()
		local ok, err = pcall(function()
			local Theme = shared("Theme")
			local function fits(menu, w, h, tag)
				local board = Menu.find(menu, "Board")
				local credits = Menu.find(menu, "CreditsButton")
				local version = credits and credits.Parent and credits.Parent:FindFirstChild("Version")
				if not T.check(board ~= nil and credits ~= nil and version ~= nil, "sign fit: (setup) the board and the CREDITS tag at " .. tag) then
					return
				end
				local b = rect(board)
				local droop = math.ceil(0.5 * b.R - 0.5 * b.X) * math.sin(math.rad(1.5))
				T.check(b.B + droop <= h - 16, "sign fit: the (swinging) board ends 16 px or more above the screen bottom at " .. tag, show(b) .. fmt(" + %.1f droop, screen %d", droop, h))
				T.check(b.Y >= -0.5, "sign fit: the board's top is on screen at " .. tag, show(b))
				for _, part in ipairs({ credits, version }) do
					local r = rect(part)
					T.check(r.X >= -0.5 and r.R <= w + 0.5 and r.Y >= -0.5 and r.B <= h + 0.5, "sign fit: " .. part.Name .. " is on screen at " .. tag, show(r))
				end
			end
			for _, s in ipairs({ { 1274, 580 }, { 1366, 600 } }) do
				local tag = s[1] .. "x" .. s[2]
				local menu = Menu.open({ Size = s })
				fits(menu, s[1], s[2], tag)
				Menu.close()
			end
			-- built for a bigger screen, then the window settles at 1274x580: the menu lays itself out again
			local menu, MMC = Menu.open({ Size = { 1920, 1080 }, Wait = 0.2 })
			local board0 = Menu.find(menu, "Board")
			local w0 = board0 and board0.AbsoluteSize.X
			Mock.SetViewport(1274, 580)
			KC.advance(3)
			local gui = pg():FindFirstChild("NimbusMainMenu")
			local menus = 0
			for _, c in ipairs(gui and gui:GetChildren() or {}) do
				if c.Name == "Menu" then
					menus = menus + 1
				end
			end
			T.eq(menus, 1, "sign fit: one menu after the resize")
			local menu2 = gui and gui:FindFirstChild("Menu")
			local board = Menu.find(menu2, "Board")
			T.check(board ~= nil and w0 ~= nil and math.abs(board.AbsoluteSize.X - 440 * Theme.ScreenFactor(580)) < 2, "sign fit: the board was laid out again for 1274x580",
				board and fmt("%.0f px wide (was %s)", board.AbsoluteSize.X, tostring(w0)) or "missing")
			fits(menu2, 1274, 580, "1920x1080 -> 1274x580")
			T.check(MMC._M.Ui.Swing and MMC._M.Ui.Swing.Position.Y.Offset == MMC._M.Ui.Rest.Y.Offset, "sign fit: the board rests in its new place after the resize")
			Menu.close()
			-- the loading screen's board at the same sizes, and after a resize
			for _, s in ipairs({ { 1274, 580 }, { 1366, 600 } }) do
				local tag = "loading " .. s[1] .. "x" .. s[2]
				local lg = Load.run(s)
				local board = lg and lg:FindFirstChild("Board", true)
				if T.check(board ~= nil, "sign fit: (setup) the loading board at " .. tag) then
					local b = rect(board)
					local droop = 0.5 * (b.R - b.X) * math.sin(math.rad(1.5))
					T.check(b.B + droop <= s[2] - 16, "sign fit: the loading board ends 16 px or more above the bottom at " .. tag, show(b))
				end
				Load.cleanup()
			end
			local lg = Load.run({ 1920, 1080 })
			Mock.SetViewport(1274, 580)
			KC.advance(0.3)
			local board = lg and lg:FindFirstChild("Board", true)
			if T.check(board ~= nil, "sign fit: (setup) the loading board after a resize") then
				local b = rect(board)
				local droop = 0.5 * (b.R - b.X) * math.sin(math.rad(1.5))
				T.check(b.B + droop <= 580 - 16, "sign fit: the loading board fits after 1920x1080 -> 1274x580", show(b))
			end
		end)
		Menu.close()
		Load.cleanup()
		T.check(ok, "sign fit: the scenario ran", tostring(err))
		KC.flushErrors("menu_fits_short_viewport")
	end)

	return S
end

if (ARGS and ARGS.context or "server") == "server" then
	return {}
end
return clientScenarios()
