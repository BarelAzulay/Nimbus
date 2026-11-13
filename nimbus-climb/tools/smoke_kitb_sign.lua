-- smoke_kitb_sign.lua: the main menu sign build (branch kitb-sign; the owner's picks on .superpowers/sign-pitch/sign_pitch.html:
-- entrance "A Rope drop" with the note "more gentle shake, make it stay moving gently after dropping", detail
-- "A Workshop" (since replaced by B2 below)), the short-screen fit fix seen in Studio and the U4 minors; then the sign/logo
-- picks (.superpowers/sign-logo-pitch, 2026-11-13): board B2, logo L2 (L1's stand-in), the T1 title exception, the
-- loading board's sway. Client world only; registered on its own
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
--   signkit_rig_parts            (sign/logo build, the owner's pick B2 "Sky-climber's rig", .superpowers/sign-logo-pitch)
--                                SignKit.Rig on the menu board (desktop, phone) and the loading screen's board (and after
--                                a resize): the canopy (canvas face, navy stripes, a scalloped valance with brass piping, no
--                                pink), one stitched patch, four corner lashings, twisted ropes ending in carabiners clipped
--                                to eye-bolts on the canopy's top edge, two propellers (wooden blades, brass hub, bracket)
--                                at its top corners, the brass "V<latest>" plate on the bottom rail, the canvas body's hem
--                                (no seams); exactly B2's five trims; the top pieces fixed-size (offset only, never
--                                stretched); flat Frames in the palette (no stroke, glow, gradient, corner, image); no
--                                Workshop trim left; Credits carries none
--   menu_props_flip              the propellers' 2-frame flip (level / upright, never a rotation) while the board sways;
--                                level with Camera shake OFF; the loading board's the same with its Sway attribute
--   loading_sway_like_menu       the loading board sways as the title screen's (Config.MainMenu.Sway), stops level with its
--                                Sway attribute off, which the title screen sets from Camera shake; no world sign sways
--   logo_fallback_l2             the L1 key (Config.Loading.Images.Logo) has id 0, so the title screen's and the loading
--                                screen's headers show the live L2 logo (letters, bands, outline, sides, bounce, plaque,
--                                bolt; it fits the header); with an id, the L1 picture instead
--   title_outline_exception      U6's Title-only exception: a styled title's ONE outline on its plate passes the stroke
--                                walk; an outlined Heading, a doubled Title and a Title with two outlines still fail
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
	-- the rig pieces under a root, by kind (attribute Rig), and the trims by group (attribute Trim)
	local function rig(root)
		local out, trims = {}, {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:GetAttribute("SignKit") == "Rig" then
				local kind = d:GetAttribute("Rig") or "?"
				out[kind] = out[kind] or {}
				table.insert(out[kind], d)
				local group = d:GetAttribute("Trim")
				if group then
					trims[group] = (trims[group] or 0) + 1
				end
			end
		end
		return out, trims
	end
	-- the blades' look: "Level" (wider than tall) or "Up"
	local function blades(root)
		local out = {}
		for _, b in ipairs((rig(root)).Blade or {}) do
			out[#out + 1] = b.Size.X.Offset > b.Size.Y.Offset and "Level" or "Up"
		end
		return out
	end

	S.signkit_rig_parts = guarded("signkit_rig_parts", function()
		local ok, err = pcall(function()
			local Theme = shared("Theme")
			local SignKit = shared("SignKit")
			local notes = shared("UpdateNotes")
			if not T.check(Theme ~= nil and SignKit ~= nil and type(SignKit.Rig) == "function", "sign rig: SignKit.Rig exists") then
				return
			end
			local Sg = Theme.Sign
			local palette = {}
			for _, c in pairs(Sg) do
				palette[hex(c)] = true
			end
			local pink = { [hex(Sg.Roof)] = true, [hex(Sg.RoofLip)] = true, [hex(Sg.RoofEdge)] = true }
			local function near(a, b, tol)
				return math.abs(a - b) <= tol
			end
			local function checkRig(swing, where, ropes)
				local board = swing:FindFirstChild("Board", true)
				local roof = board and board:FindFirstChild("Roof", true)
				local t, trims = rig(swing)
				local B = rect(board)
				local bw = B.R - B.X
				-- the owner's B2 replaces the Workshop trim (B1 dropped the nails, the grain and the chip)
				local left = 0
				for _ in pairs(trim(swing)) do
					left = left + 1
				end
				T.eq(left, 0, "sign rig: no Workshop trim left (nails, grain, chip) on the " .. where)
				-- the canopy: navy stripes on a canvas face, a scalloped valance with brass piping, no pink anywhere
				local face = roof and roof:FindFirstChild("Face")
				T.check(face ~= nil and hex(face.BackgroundColor3) == hex(Sg.Canvas), "sign rig: the canopy's face is weathered canvas on the " .. where, face and hex(face.BackgroundColor3) or "missing")
				local navy = 0
				for _, st in ipairs(t.Stripe or {}) do
					if hex(st.BackgroundColor3) == hex(Sg.NavyLight) then
						navy = navy + 1
					end
				end
				T.check(navy >= 4, "sign rig: navy stripes across the canopy on the " .. where, tostring(navy))
				T.check(#(t.Scallop or {}) >= 8, "sign rig: a scalloped valance under the canopy on the " .. where, tostring(#(t.Scallop or {})))
				local brass = 0
				for _, p in ipairs(t.Piping or {}) do
					if hex(p.BackgroundColor3) == hex(Sg.Brass) then
						brass = brass + 1
					end
				end
				T.check(brass >= #(t.Scallop or {}), "sign rig: brass piping along the scalloped edge on the " .. where, brass .. " for " .. #(t.Scallop or {}) .. " scallops")
				local pinkHere = {}
				for _, d in ipairs(swing:GetDescendants()) do
					if d:IsA("GuiObject") and d.Visible and d.BackgroundTransparency < 1 and pink[hex(d.BackgroundColor3)] then
						pinkHere[#pinkHere + 1] = d.Name
					end
				end
				T.check(#pinkHere == 0, "sign rig: the pink awning is gone (B2's canopy) on the " .. where, table.concat(pinkHere, ", ", 1, math.min(#pinkHere, 6)))
				-- the patch: one stitched canvas patch on the canopy
				local patch = (t.Patch or {})[1]
				T.check(#(t.Patch or {}) == 1 and patch:IsDescendantOf(roof) and #patch:GetChildren() >= 8, "sign rig: one stitched patch on the canopy on the " .. where,
					patch and (#patch:GetChildren() .. " stitches") or "none")
				-- the corner lashings: four, one on each corner of the frame
				local lash = t.Lashing or {}
				T.eq(#lash, 4, "sign rig: four rope lashings on the " .. where)
				local corners = { TL = false, TR = false, BL = false, BR = false }
				for _, l in ipairs(lash) do
					local r = rect(l)
					local cx, cy = (r.X + r.R) / 2, (r.Y + r.B) / 2
					local h = cx < (B.X + B.R) / 2 and "L" or "R"
					local v = cy < (B.Y + B.B) / 2 and "T" or "B"
					if (h == "L" and r.X <= B.X + 2) or (h == "R" and r.R >= B.R - 2) then
						corners[v .. h] = true
					end
				end
				T.check(corners.TL and corners.TR and corners.BL and corners.BR, "sign rig: the lashings sit on the frame's four corners on the " .. where)
				-- the hang rig: each rope twisted, ending in a carabiner clipped to an eye-bolt on the canopy's top edge
				local twisted, clipped = 0, 0
				for _, rope in ipairs(ropes) do
					local n = 0
					for _, d in ipairs((t.Twist or {})) do
						if d:IsDescendantOf(rope) and hex(d.BackgroundColor3) == hex(Sg.Wood) then
							n = n + 1
						end
					end
					if n >= 3 then
						twisted = twisted + 1
					end
					local rx = rope.AbsolutePosition.X + rope.AbsoluteSize.X / 2
					local roofTop = roof.AbsolutePosition.Y
					local cara, eye = nil, nil
					for _, c in ipairs(t.Carabiner or {}) do
						local r = rect(c)
						if r.X <= rx and r.R >= rx then
							cara = c
						end
					end
					for _, e in ipairs(t.EyeBolt or {}) do
						local r = rect(e)
						if r.X <= rx and r.R >= rx and r.Y <= roofTop + 1 and r.B >= roofTop - 1 then
							eye = e
						end
					end
					if cara and eye and rect(cara).B >= rect(eye).Y - 1 and rect(cara).Y < rect(eye).Y then
						clipped = clipped + 1
					end
				end
				T.eq(twisted, 2, "sign rig: both ropes have the twist pattern on the " .. where)
				T.eq(clipped, 2, "sign rig: each rope ends in a carabiner clipped to an eye-bolt on the canopy's top edge on the " .. where)
				-- the propellers: two, on brass brackets at the canopy's top corners, blades on a hub
				local props = t.Propeller or {}
				T.eq(#props, 2, "sign rig: two propellers on the " .. where)
				local cornersP = 0
				for _, p in ipairs(props) do
					local r = rect(p)
					local cx, cy = (r.X + r.R) / 2, (r.Y + r.B) / 2
					if (near(cx, B.X, 0.1 * bw) or near(cx, B.R, 0.1 * bw)) and cy <= roof.AbsolutePosition.Y + 4 then
						cornersP = cornersP + 1
					end
					local kinds = {}
					for _, d in ipairs(p:GetDescendants()) do
						local k = d:GetAttribute("Rig")
						if k then
							kinds[k] = d
						end
					end
					T.check(kinds.Blade and kinds.Hub and kinds.Bracket and hex(kinds.Blade.BackgroundColor3) == hex(Sg.Post) and hex(kinds.Hub.BackgroundColor3) == hex(Sg.Brass)
						and hex(kinds.Bracket.BackgroundColor3) == hex(Sg.GoldLip), "sign rig: a propeller is wooden blades on a brass hub on a bracket on the " .. where)
				end
				T.eq(cornersP, 2, "sign rig: the propellers stand at the canopy's top corners on the " .. where)
				-- the version plate: brass, riveted to the bottom rail, centred, "V<latest>"
				local plate = (t.Plate or {})[1]
				local label = plate and plate:FindFirstChildWhichIsA("TextLabel", true)
				local want = "V" .. tostring(notes and notes.Latest or "")
				if T.check(#(t.Plate or {}) == 1 and label ~= nil, "sign rig: one version plate on the " .. where) then
					local r = rect(plate)
					T.check(hex(plate.BackgroundColor3) == hex(Sg.GoldLip) and r.Y < B.B and r.B > B.B - 2 and near((r.X + r.R) / 2, (B.X + B.R) / 2, 2),
						"sign rig: the brass plate sits on the bottom rail, centred, on the " .. where, show(r) .. " board " .. show(B))
					T.check(label.Text == want and hex(label.TextColor3) == hex(Sg.Text) and label.TextSize * Theme.ScreenFactor(workspace.CurrentCamera.ViewportSize.Y) >= 14,
						"sign rig: it reads " .. want .. " in brown, 14 screen px or more, on the " .. where, label.Text .. " " .. tostring(label.TextSize))
				end
				-- the canvas body: one sheet with a hem on its sides, no seams
				local body = board:FindFirstChild("Body", true)
				local hems = 0
				for _, h in ipairs(t.Hem or {}) do
					if h:IsDescendantOf(body) and hex(h.BackgroundColor3) == hex(Sg.StoneLip) then
						hems = hems + 1
					end
				end
				T.check(hems >= 3 and #(t.Seam or {}) == 0, "sign rig: the canvas body has its hem (top, left, right) and no seams on the " .. where, tostring(hems))
				-- at most five trims, exactly B2's
				local groups = {}
				for g in pairs(trims) do
					groups[#groups + 1] = g
				end
				table.sort(groups)
				T.check(table.concat(groups, ",") == "HangRig,Lashing,Patch,Plate,Propeller", "sign rig: B2's five trims and nothing else on the " .. where, table.concat(groups, ","))
				-- the top pieces are fixed-size sprites (offset sizes, no slice); flat Frames in the palette, no glow
				local scaled, bad = {}, {}
				for _, list in pairs(t) do
					for _, part in ipairs(list) do
						for _, d in ipairs({ part, unpack(part:GetDescendants()) }) do
							local top = d:IsDescendantOf(roof) or d == roof or (d:GetAttribute("Rig") and ({ Propeller = 1, Blade = 1, Hub = 1, Bracket = 1, Carabiner = 1, EyeBolt = 1, Scallop = 1, Piping = 1, Stripe = 1, Patch = 1 })[d:GetAttribute("Rig")])
							if top and d:IsA("GuiObject") and (d.Size.X.Scale ~= 0 or d.Size.Y.Scale ~= 0) and d:GetAttribute("Rig") ~= "Stripe" then
								scaled[#scaled + 1] = d.Name
							end
							if d:IsA("UIStroke") or d:IsA("UIGradient") or d:IsA("UICorner") or d:IsA("ImageLabel") or d:IsA("ImageButton") then
								bad[#bad + 1] = d.ClassName
							elseif d:IsA("Frame") and d.BackgroundTransparency < 1 and not palette[hex(d.BackgroundColor3)] then
								bad[#bad + 1] = d.Name .. " " .. hex(d.BackgroundColor3)
							end
						end
					end
				end
				T.check(#scaled == 0, "sign rig: the canopy and the top pieces are fixed-size (offset only, never stretched) on the " .. where, table.concat(scaled, ", ", 1, math.min(#scaled, 6)))
				T.check(#bad == 0, "sign rig: flat Frames in the palette only (no stroke, glow, gradient, corner or image) on the " .. where, table.concat(bad, ", ", 1, math.min(#bad, 6)))
			end
			-- the title screen's board, desktop and phone
			local menu, MMC = Menu.open({ Wait = 2.5 })
			local swing = Menu.find(menu, "Swing")
			if T.check(swing ~= nil, "sign rig: (setup) the menu board") then
				checkRig(swing, "menu board", Menu.ropes(swing))
			end
			-- Credits stays as approved: none of the rig in its window
			MMC.OpenCredits()
			KC.advance(0.3)
			local holder = MMC.Window()
			if T.check(holder ~= nil, "sign rig: (setup) the Credits window opens") then
				local n = 0
				for _ in pairs((rig(holder))) do
					n = n + 1
				end
				T.eq(n, 0, "sign rig: the Credits window carries none of the rig (it keeps its approved look)")
			end
			MMC.CloseWindows()
			Menu.close()
			local pmenu = Menu.open({ Size = { 844, 390 }, Input = "Touch" })
			local pswing = Menu.find(pmenu, "Swing")
			if T.check(pswing ~= nil, "sign rig: (setup) the menu board at 844x390") then
				checkRig(pswing, "menu board at 844x390", Menu.ropes(pswing))
			end
			Menu.close()
			-- the loading screen's board wears the same rig, and keeps it fitted after a resize
			local lg = Load.run({ 1920, 1080 })
			local lswing = lg and lg:FindFirstChild("Swing", true)
			if T.check(lswing ~= nil, "sign rig: (setup) the loading screen's board") then
				checkRig(lswing, "loading board", Menu.ropes(lswing))
				Mock.SetViewport(1274, 580)
				KC.advance(0.3)
				checkRig(lswing, "loading board at 1274x580", Menu.ropes(lswing))
			end
		end)
		Menu.close()
		Load.cleanup()
		T.check(ok, "sign rig: the scenario ran", tostring(err))
		KC.flushErrors("signkit_rig_parts")
	end)

	------------------------------------------------------------------------------------------------
	-- B2's propellers turn (a 2-frame flip every 0.5 s: level, then upright; never a rotation) while the board opens or
	-- sways, and rest level when it does not (Camera shake OFF) or after PLAY
	S.menu_props_flip = guarded("menu_props_flip", function()
		local Settings = client("ClientSettings")
		local ok, err = pcall(function()
			local SignKit = shared("SignKit")
			if not T.check(Settings ~= nil and SignKit ~= nil, "sign props: (setup) ClientSettings and SignKit") then
				return
			end
			local function sample(root, seconds)
				local seen = {}
				local t = 0
				while t < seconds do
					KC.advance(0.1)
					t = t + 0.1
					for _, look in ipairs(blades(root)) do
						seen[look] = true
					end
				end
				return seen
			end
			Settings.Set("Shake", true)
			local menu = Menu.open({ Wait = 3 })
			local swing = Menu.find(menu, "Swing")
			if not T.check(swing ~= nil and #blades(swing) == 2, "sign props: (setup) two propellers on the board") then
				return
			end
			local seen = sample(swing, 1.6)
			T.check(seen.Level and seen.Up, "sign props: while the board sways the blades flip level / upright")
			local turned = {}
			for _, b in ipairs((rig(swing)).Blade or {}) do
				if b.Rotation ~= 0 then
					turned[#turned + 1] = tostring(b.Rotation)
				end
			end
			T.check(#turned == 0, "sign props: a flip swaps the blade's size, never a rotation (nothing goes soft)", table.concat(turned, ", "))
			Settings.Set("Shake", false)
			KC.advance(1)
			local still = sample(swing, 1.6)
			T.check(still.Level and not still.Up, "sign props: Camera shake OFF (no sway): the blades rest level")
			Settings.Set("Shake", true)
			KC.advance(1)
			local again = sample(swing, 1.6)
			T.check(again.Level and again.Up, "sign props: Camera shake ON: they turn again")
			-- the loading screen's propellers turn while it sways, and rest with its sway off
			local lg = Load.run({ 1920, 1080 })
			local lswing = lg and lg:FindFirstChild("Swing", true)
			if T.check(lswing ~= nil and #blades(lswing) == 2, "sign props: (setup) two propellers on the loading board") then
				local ls = sample(lswing, 1.6)
				T.check(ls.Level and ls.Up, "sign props: the loading board's blades flip while it sways")
				lg:SetAttribute("Sway", false)
				KC.advance(1)
				local lstill = sample(lswing, 1.6)
				T.check(lstill.Level and not lstill.Up, "sign props: ...and rest level with its sway off")
			end
		end)
		Menu.close()
		Load.cleanup()
		if Settings then
			Settings.Set("Shake", true)
		end
		T.check(ok, "sign props: the scenario ran", tostring(err))
		KC.flushErrors("menu_props_flip")
	end)

	------------------------------------------------------------------------------------------------
	-- (the owner's answer 2026-11-13) the loading board sways like the title screen's: +-Config.MainMenu.Sway.Degrees, a
	-- full back-and-forth every Sway.Period, Sine InOut, endlessly; it stops and rests level when Camera shake is OFF (the
	-- title screen tells it through the gui's Sway attribute, as the setting arrives or changes) and comes back with it ON.
	-- ONLY the two screen signs sway: no world sign (BillboardGui / SurfaceGui, anything outside the two screens) turns
	S.loading_sway_like_menu = guarded("loading_sway_like_menu", function()
		local Settings = client("ClientSettings")
		local ok, err = pcall(function()
			local W = shared("Config").MainMenu.Sway
			if not T.check(Settings ~= nil and type(W) == "table" and W.Degrees > 0, "loading sway: (setup) ClientSettings and Config.MainMenu.Sway") then
				return
			end
			Settings.Set("Shake", true)
			local lg = Load.run({ 1920, 1080 })
			local swing = lg and lg:FindFirstChild("Swing", true)
			if not T.check(swing ~= nil, "loading sway: (setup) the loading board's Swing") then
				return
			end
			local sway = endless(swing, "Rotation")
			local info = sway and sway.TweenInfo
			local goal = sway and Mock.TweenGoals(sway).Rotation
			T.check(info ~= nil and info.Reverses == true and info.EasingStyle == Enum.EasingStyle.Sine and info.EasingDirection == Enum.EasingDirection.InOut
				and math.abs(info.Time - W.Period / 2) < 1e-6, "loading sway: an endless Sine InOut sway, Sway.Period a full back-and-forth (as the title screen's)",
				info and fmt("%.2f s %s", info.Time, tostring(info.EasingStyle)) or "no endless tween")
			T.check(goal ~= nil and math.abs(math.abs(goal) - W.Degrees) < 1e-6 and math.abs(swing.Rotation + goal) < 1e-6,
				"loading sway: ...from -" .. W.Degrees .. " to +" .. W.Degrees .. " degrees", fmt("%.2f -> %s", swing.Rotation, tostring(goal)))
			T.check(swing.AnchorPoint.Y == 0.5 and swing.Position.Y.Scale == 0 and swing.Position.Y.Offset == 0, "loading sway: it turns about the rope tops (the Swing's centre at the screen top)")
			lg:SetAttribute("Sway", false)
			KC.advance(1)
			T.check(endless(swing, "Rotation") == nil and math.abs(swing.Rotation) < 1e-6, "loading sway: Sway off: it stops and rests level", fmt("%.2f", swing.Rotation))
			lg:SetAttribute("Sway", true)
			KC.advance(1)
			T.check(endless(swing, "Rotation") ~= nil, "loading sway: Sway on: it sways again")
			Load.cleanup()
			-- the setting reaches the loading screen through the title screen: Camera shake OFF before it is built, then a change
			Menu.open({ Wait = 0.05 })
			Settings.Set("Shake", false)
			local lg2 = Load.run({ 1920, 1080 })
			local swing2 = lg2 and lg2:FindFirstChild("Swing", true)
			T.check(lg2 ~= nil and lg2:GetAttribute("Sway") == false and swing2 ~= nil and endless(swing2, "Rotation") == nil and math.abs(swing2.Rotation) < 1e-6,
				"loading sway: with Camera shake OFF the loading board rests level (the title screen passes the setting on)", lg2 and tostring(lg2:GetAttribute("Sway")) or "")
			Settings.Set("Shake", true)
			KC.advance(1)
			T.check(lg2 ~= nil and lg2:GetAttribute("Sway") == true and endless(swing2, "Rotation") ~= nil, "loading sway: Camera shake ON while it is up: it sways again")
			-- only the screen signs sway: every endless turn in the game belongs to the title screen or the loading screen
			local others = {}
			for tw in pairs(Mock.ActiveTweens) do
				local inst = tw.Instance
				if tw.TweenInfo.RepeatCount < 0 and Mock.TweenGoals(tw).Rotation ~= nil and inst and inst:IsDescendantOf(game) then
					local gui = inst:FindFirstAncestorWhichIsA("LayerCollector")
					local name = gui and gui.Name or ""
					if not ((name == "NimbusMainMenu" or name == "NimbusLoading") and gui:IsA("ScreenGui")) then
						others[#others + 1] = inst:GetFullName()
					end
				end
			end
			T.check(#others == 0, "loading sway: no world sign sways (only the title screen's and the loading screen's boards)", table.concat(others, "; ", 1, math.min(#others, 6)))
			local signs, turning = 0, {}
			for _, d in ipairs(workspace:GetDescendants()) do
				if d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
					signs = signs + 1
					for _, g in ipairs(d:GetDescendants()) do
						if g:IsA("GuiObject") and math.abs(g.Rotation) > 0.01 and next(tweensOf(g, "Rotation")) then
							turning[#turning + 1] = g:GetFullName()
						end
					end
				end
			end
			T.check(#turning == 0, "loading sway: the lobby's world signs stay still (" .. signs .. " checked)", table.concat(turning, "; ", 1, math.min(#turning, 6)))
		end)
		Menu.close()
		Load.cleanup()
		if Settings then
			Settings.Set("Shake", true)
		end
		T.check(ok, "loading sway: the scenario ran", tostring(err))
		KC.flushErrors("loading_sway_like_menu")
	end)

	------------------------------------------------------------------------------------------------
	-- the logo (the owner's picks 2026-11-13): L1, the voxel storm logo, is a Blender picture that needs one upload after
	-- the owner's OK, so its TextureIds key (Config.Loading.Images.Logo) has no id yet (id 0) and the header shows L2, the
	-- live storm plaque (per-letter FredokaOne, three-band fills, one brown outline, a two-step block side; the cloud plaque
	-- of stepped navy blocks; the pixel bolt). With an id the same header shows the L1 picture instead
	S.logo_fallback_l2 = guarded("logo_fallback_l2", function()
		local ids = shared("TextureIds")
		local Config = shared("Config")
		local key = Config and Config.Loading and Config.Loading.Images and Config.Loading.Images.Logo
		local saved = ids and key and ids[key]
		local ok, err = pcall(function()
			local Theme = shared("Theme")
			local Logo = shared("Logo")
			if not T.check(type(ids) == "table" and type(key) == "string" and Logo ~= nil and type(Logo.Build) == "function", "sign logo: (setup) shared/Logo and the TextureIds key") then
				return
			end
			local Sg = Theme.Sign
			T.check((tonumber(ids[key]) or 0) == 0, "sign logo: the L1 key " .. key .. " has id 0 (not uploaded: the owner's OK first)", tostring(ids[key]))
			T.check(Logo.Key() == key, "sign logo: Logo.Key() is Config.Loading.Images.Logo", tostring(Logo.Key()))
			local function checkL2(logo, board, plate, where)
				if not T.check(logo ~= nil and logo:GetAttribute("Logo") == "L2" and logo.Visible and not logo:IsA("ImageLabel"), "sign logo: id 0 -> the live L2 logo on the " .. where,
					logo and tostring(logo:GetAttribute("Logo")) or "missing") then
					return
				end
				-- each letter's three copies by its place (LogoLetter): the face and its two block-side copies
				local letters = {}
				for _, d in ipairs(logo:GetDescendants()) do
					local i = d:GetAttribute("LogoLetter")
					if i then
						letters[i] = letters[i] or { Bounce = d:GetAttribute("Bounce") }
						letters[i][d.Name] = d
					end
				end
				local word = ""
				for _, l in ipairs(letters) do
					word = word .. (l.LetterFace and l.LetterFace.Text or "?")
				end
				T.eq(word, "NIMBUSCLIMB", "sign logo: eleven letters NIMBUS CLIMB on the " .. where)
				-- each letter: a white face under a hard three-band gradient (cream NIMBUS, gold CLIMB), ONE brown outline,
				-- two block-side copies behind; the bounce (fixed per letter) from the pitch
				local good, bounce = 0, {}
				for i, l in ipairs(letters) do
					local face, s1, s2 = l.LetterFace, l.LetterSide1, l.LetterSide2
					local g = face and face:FindFirstChildOfClass("UIGradient")
					local strokes = 0
					for _, c in ipairs(face and face:GetChildren() or {}) do
						if c:IsA("UIStroke") and c.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
							strokes = strokes + 1
							if hex(c.Color) ~= hex(Sg.Text) then
								strokes = 99
							end
						end
					end
					local top = g and g.Color.Keypoints[1].Value
					local gold = i > 6
					if face and s1 and s2 and g and strokes == 1 and face:GetAttribute("FontRole") == "Title" and face.Font == Enum.Font.FredokaOne
						and hex(top) == hex(gold and Sg.GoldLight or Sg.Tile) and s1.Position.Y.Offset > face.Position.Y.Offset and s2.Position.Y.Offset > s1.Position.Y.Offset
						and hex(s2.TextColor3) == hex(Sg.NavyLip) and s1.Parent.ZIndex < face.Parent.ZIndex and s2.Parent.ZIndex < s1.Parent.ZIndex then
						good = good + 1
					end
					bounce[i] = l.Bounce
				end
				T.eq(good, 11, "sign logo: every letter is a banded face (cream NIMBUS, gold CLIMB), one brown outline, a two-step side, on the " .. where)
				T.eq(table.concat(bounce, ","), "0,-3,2,-2,3,-1,2,-2,3,-3,0", "sign logo: the pitch's fixed bounce per letter on the " .. where)
				-- the plaque (stepped navy blocks, a lighter top, a darker lip; no corner) and the pixel bolt (four gold squares)
				local plaque, bolt, corners = 0, 0, 0
				for _, d in ipairs(logo:GetDescendants()) do
					local part = d:GetAttribute("LogoPart")
					if part == "Plaque" then
						plaque = plaque + 1
					elseif part == "Bolt" and hex(d.BackgroundColor3) == hex(Sg.Gold) then
						bolt = bolt + 1
					end
					if d:IsA("UICorner") then
						corners = corners + 1
					end
				end
				T.check(plaque >= 4 and bolt == 4 and corners == 0, "sign logo: a stepped cloud plaque and a four-block pixel bolt (no round corner) on the " .. where,
					fmt("%d plaque, %d bolt, %d corners", plaque, bolt, corners))
				-- on the header, within the board; the letters 15 screen px or more
				local L, B, P = rect(logo), rect(board), rect(plate)
				T.check(L.X >= B.X + 4 and L.R <= B.R - 4 and L.B <= P.B + 2 and L.Y >= B.Y - 0.25 * (P.B - P.Y), "sign logo: the logo sits on the header, inside the board, its bolt ending at the header's foot, on the " .. where,
					show(L) .. " board " .. show(B) .. " plate " .. show(P))
				local small = math.huge
				local f = Theme.ScreenFactor(workspace.CurrentCamera.ViewportSize.Y)
				for _, l in ipairs(letters) do
					small = math.min(small, l.LetterFace.TextSize * f)
				end
				-- every side under every face: no face is drawn under a neighbour's side
				local faces, sides = {}, {}
				for _, l in ipairs(letters) do
					faces[l.LetterFace.Parent] = true
					sides[l.LetterSide1.Parent] = true
					sides[l.LetterSide2.Parent] = true
				end
				local layered = true
				for fl in pairs(faces) do
					for sl in pairs(sides) do
						layered = layered and fl ~= sl and fl.Parent == sl.Parent and fl.ZIndex > sl.ZIndex
					end
				end
				T.check(layered, "sign logo: every letter's side copies are drawn under every face (a neighbour's side never covers a face) on the " .. where)
				T.check(small >= 15, "sign logo: the letters are 15 screen px or more on the " .. where, fmt("%.1f", small))
			end
			local function menuParts(menu)
				local board = Menu.find(menu, "Board")
				return Menu.find(board, "Logo"), board, Menu.find(board, "Plate")
			end
			local menu = Menu.open({ Wait = 2.5 })
			local logo, board, plate = menuParts(menu)
			checkL2(logo, board, plate, "title screen")
			Menu.close()
			local pmenu = Menu.open({ Size = { 844, 390 }, Input = "Touch" })
			logo, board, plate = menuParts(pmenu)
			checkL2(logo, board, plate, "title screen at 844x390")
			Menu.close()
			local lg = Load.run({ 1920, 1080 })
			local lb = lg and lg:FindFirstChild("Board", true)
			checkL2(lb and lb:FindFirstChild("Logo", true), lb, lb and lb:FindFirstChild("Plate", true), "loading screen")
			Load.cleanup()
			-- with an id (after the owner's OK and the upload): the L1 picture in the same place, no L2
			ids[key] = 4242
			local m2 = Menu.open({ Wait = 2.5 })
			local l1 = Menu.find(Menu.find(m2, "Board"), "Logo")
			T.check(l1 ~= nil and l1:IsA("ImageLabel") and l1.Image == "rbxassetid://4242" and l1:GetAttribute("Logo") == "L1" and l1.ScaleType == Enum.ScaleType.Fit,
				"sign logo: an id -> the L1 picture on the title screen", l1 and tostring(l1:GetAttribute("Logo")) or "missing")
			-- its box has the exported picture's shape (img/final/nimbus_logo_L1_1024.png, 1024 x 259: the pitch's 224 wide),
			-- so Fit never letterboxes it off the header's centre
			local aspect = l1 and l1.Size.Y.Offset > 0 and l1.Size.X.Offset / l1.Size.Y.Offset or 0
			T.check(math.abs(aspect - 1024 / 259) <= 0.08, "sign logo: the L1 box has the exported picture's shape (1024 x 259)", fmt("%.2f", aspect))
			Menu.close()
			local lg2 = Load.run({ 1920, 1080 })
			local l1b = lg2 and lg2:FindFirstChild("Logo", true)
			T.check(l1b ~= nil and l1b:IsA("ImageLabel") and l1b.Image == "rbxassetid://4242" and l1b:GetAttribute("Logo") == "L1", "sign logo: ...and on the loading screen",
				l1b and tostring(l1b:GetAttribute("Logo")) or "missing")
		end)
		if ids and key then
			ids[key] = saved
		end
		Menu.close()
		Load.cleanup()
		T.check(ok, "sign logo: the scenario ran", tostring(err))
		KC.flushErrors("logo_fallback_l2")
	end)

	------------------------------------------------------------------------------------------------
	-- U6's "outline only with no plate", with the owner's ONE exception (T1, 2026-11-13): a Title-role text may carry ONE
	-- outline on a plate (the ribbon's gold letters, the logo's letters). The walk (SmokeCommon.StrokeWalk, the rule the
	-- client walk kitb_text_stroke_or_panel and tools/render_gui.py's stroke_rule apply) passes a styled title on its
	-- plate and still fails an outlined Heading on a plate, a Title with a classic stroke under its outline, and a Title
	-- with two outlines
	S.title_outline_exception = guarded("title_outline_exception", function()
		local gui = nil
		local ok, err = pcall(function()
			local Theme = shared("Theme")
			local walk = SmokeCommon.StrokeWalk
			if not T.check(type(walk) == "function" and Theme ~= nil, "outline rule: (setup) SmokeCommon.StrokeWalk") then
				return
			end
			gui = Instance.new("ScreenGui")
			gui.Name = "KitbRuleProbe"
			gui.Parent = pg()
			local function plate(name, y)
				local p = Instance.new("Frame")
				p.Name = name
				p.BackgroundColor3 = Theme.Sign.Navy
				p.BackgroundTransparency = 0
				p.Position = UDim2.fromOffset(20, y)
				p.Size = UDim2.fromOffset(400, 60)
				p.Parent = gui
				return p
			end
			local function label(role, name, parent)
				local l = Theme.Label("Shop", role, { Size = 34, Color = Theme.Sign.Gold })
				l.Name = name
				l.Size = UDim2.fromScale(1, 1)
				l.Parent = parent
				return l
			end
			local title = label("Title", "Title", plate("TitlePlate", 20))
			Theme.StyleTitle(title)
			local heading = label("Heading", "Heading", plate("HeadingPlate", 100))
			Theme.TextOutline(heading, 2)
			local doubled = label("Title", "Doubled", plate("DoubledPlate", 180))
			Theme.TextOutline(doubled, 2)
			doubled.TextStrokeTransparency = 0
			local two = label("Title", "TwoRings", plate("TwoPlate", 260))
			Theme.TextOutline(two, 2)
			local extra = Instance.new("UIStroke")
			extra.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			extra.Thickness = 2
			extra.Parent = two
			local total, dbl, pan = walk(gui, Theme.OutlineOnPlate)
			local function has(list, pat)
				for _, p in ipairs(list) do
					if p:find(pat) then
						return true
					end
				end
				return false
			end
			T.check(total > 0, "outline rule: (setup) the probe's texts are walked", tostring(total))
			T.check(not has(pan, "TitlePlate") and not has(dbl, "TitlePlate"), "outline rule: a styled title (T1: ONE outline on its ribbon) passes", table.concat(pan, "; "))
			T.check(has(pan, "HeadingPlate"), "outline rule: an outlined Heading on a plate still fails (the exception is the Title role only)")
			T.check(has(dbl, "DoubledPlate"), "outline rule: a Title with a classic stroke under its outline still fails")
			T.check(has(pan, "TwoPlate"), "outline rule: a Title with two outlines on a plate still fails (one outline at most)")
		end)
		if gui then
			gui:Destroy()
		end
		T.check(ok, "outline rule: the scenario ran", tostring(err))
		KC.flushErrors("title_outline_exception")
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
