-- MovementController (client): smooth run, stamina, dash, camera feel and mobile buttons.
--
--   MovementController.Init()
--   MovementController.GetDashCooldownFraction() -> number   -- 0 = ready .. 1 = just used
--
-- How it works
--   * Input is bound once with ContextActionService (high priority, so Shift never toggles
--     Roblox shift-lock and typing in a TextBox never triggers a dash).
--   * Everything that touches the character lives in a per-character context that is created on
--     CharacterAdded and torn down on CharacterRemoving / Died, so nothing leaks across respawns.
--   * WalkSpeed is "owned" by the server (PlayerService freezes/unfreezes it). We watch for
--     changes we did not make and treat that value as the base speed, so a frozen or Downed
--     player can never run or dash, and the server can still change the speed at any time.
--   * The dash is velocity-based: for DashDuration seconds the horizontal velocity of the
--     HumanoidRootPart is re-asserted every physics step while the vertical velocity is left alone.
--   * v2: stamina regenerates (1 + player attribute PerkStaminaRegen) times as fast (pet perk), and the mobile
--     RUN / DASH buttons are laid out around Roblox's jump button, the hotbar and the vitals card above it.
--   * Phase 5 (ARCHITECTURE_V3.md "Phase 5 build contract" 3.9 / 4.4; battleclient): BattleController drives three
--     battle switches on Start / Speed / End:
--       MovementController.SetDashKeys(keys | nil)   in battle Shift = DASH (keys = { LeftShift, RightShift, ButtonB }),
--                                                    Q is left to BattleController's SPECIAL; while Shift dashes, RUN
--                                                    moves to Ctrl (+ L3 / the mobile RUN button) and the mobile DASH
--                                                    button hides (the battle cluster has its own); nil restores Q / B
--       MovementController.SetFreeDash(on, cooldown) a dash costs no stamina while on (cooldown = the battle's
--                                                    DashCooldown; Config.Physics is never touched)
--       MovementController.SetBattleSpeed(walk, run | nil)  the character walks at `walk` (written as the base speed:
--                                                    the "server owns WalkSpeed" watch is suspended, except that a
--                                                    server write of 0 (Downed / frozen) still wins) and runs at `run`
--                                                    (default walk x 1.3) instead of Config.Physics.RunSpeed;
--                                                    SetBattleSpeed(nil) gives the server's base back at once
--     plus MovementController.TryDash() -> bool (the battle DASH button), SetDashListener(fn | nil) (called after every
--     dash: BattleController sends BattleCommand "Dash") and GetSpeedState() (tests).
--   * Dungeon fixes (decision 5): MovementController.SetPetDash(fn | nil): in a battle Shift (+ RightShift, gamepad B)
--     is the PET's dash: the keys call fn() only (BattleController sends BattleCommand "Dash"); the character gets NO
--     velocity impulse, spends no stamina and starts no dash cooldown (tryDash / TryDash refuse while it is set, so
--     the vitals card's dash ring never shows a character dash); RUN moves to Ctrl (as with SetDashKeys) and the
--     mobile DASH button hides (the battle cluster's DASH sends the same command). nil restores Q / B, Shift = run.
--     BattleController uses it instead of SetDashKeys / SetFreeDash / SetDashListener. EXHAUST_RESUME is 22 (15% of the
--     150 MaxStamina). Run / dash input is ignored until UiGate.HasPlayed() (the main menu, 7.2; no UiGate = played).
--   * Bug batch 2 (#19): MovementController.SetZoomMax(n | nil) caps LocalPlayer.CameraMaxZoomDistance at n (DungeonController:
--     14 while a dungeon run lasts, so the camera never leaves the 16-stud rooms); nil gives the normal ZOOM_MAX 40 back.
--     The cap survives a respawn (applyCameraSettings re-applies it); junk (NaN, <= 0, inf, non-numbers) is ignored;
--     CameraMinZoomDistance is only lowered when it would sit above the cap (first person is never forced).
--   * Wave 5 dungeon camera (bugs #15 / #26; DungeonController / BattleController). This controller is the one place
--     that writes Camera.FieldOfView and the character's WalkSpeed every frame, so the cinematics go through it:
--       MovementController.SetFovOverride(fov | nil)  while set the FOV is `fov` (+ a live punch) instead of 70 + run +
--                                                    dash; nil = the normal FOV again
--       MovementController.FovPunch(degrees, seconds) a quick zoom punch: + degrees * (1 - p)^2 over `seconds` on top
--                                                    of whatever is written (a second punch keeps the larger one)
--       MovementController.SetCinematic(walkSpeed | nil)  a scripted walk (the room walk-in): run / dash input is
--                                                    ignored, the mobile buttons dim like Downed, WalkSpeed = walkSpeed
--                                                    (the "server owns WalkSpeed" watch suspended, a server 0 still
--                                                    wins); nil = the normal speed rules at once. GetSpeedState().Cinematic
--   * Unlimited stamina in the lobby: inside Config.InLobbyZone, out of a match and a battle, running drains nothing, a
--     dash costs no stamina (its cooldown stays) and the bar is full, so the HUD simply shows it full. GetSpeedState().StaminaFree
--   * Dev 2x speed (DevService "speed"): while the server's hint NC_DevSpeed is on our PlayerGui, walking and running are
--     written at twice their speed on top of the server's base (never on top of our own write, so it cannot stack). Not in
--     a battle or a scripted walk: BattleService leashes the character to the server fighter there. GetSpeedState().DevSpeed
-- Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local MovementController = {}

-- Luau/Lua 5.1 have math.atan2; Lua 5.3+ folds it into math.atan(y, x). Support both.
local atan2 = math.atan2 or function(y, x)
	return math.atan(y, x)
end

local LocalPlayer = Players.LocalPlayer
local P = Config.Physics
local ATTR = Config.Attr

----------------------------------------------------------------------
-- Tuning (feel only; gameplay numbers live in Config.Physics)
----------------------------------------------------------------------
local BASE_FOV = 70
local RUN_FOV_BOOST = 4 -- extra degrees at full run
local DASH_FOV_BOOST = 12 -- 70 -> 82 -> 70 punch
local PUNCH_ATTACK = 0.07 -- seconds to reach the peak
local PUNCH_TOTAL = 0.5 -- seconds until the punch has fully relaxed

local ZOOM_MAX = 40 -- LocalPlayer.CameraMaxZoomDistance
local zoomMax = ZOOM_MAX -- the cap in force (SetZoomMax: 14 inside a dungeon run)

local EXHAUST_RESUME = 22 -- stamina needed to run again after hitting 0 (Phase 5: 15% of MaxStamina, Config.Movement.ExhaustResume)
local RUN_RAMP_UP = 9 -- exponential smoothing rates (1/s)
local RUN_RAMP_DOWN = 7
local RUN_REGEN_DELAY = 0.25 -- seconds after running before stamina regenerates
local DASH_REGEN_DELAY = 0.5
local DASH_BUFFER = 0.18 -- a dash pressed this close to "ready" is queued
local FROZEN_SPEED = 0.5 -- WalkSpeed below this means "frozen by the server"
local SPEED_EPS = 0.05 -- tolerance when comparing WalkSpeed with what we wrote
local MOVE_EPS = 0.1 -- MoveDirection magnitude that counts as "moving"
local DEV_SPEED_HINT = "NC_DevSpeed" -- PlayerGui attribute set by DevService (only for developers)
local DEV_SPEED_MULT = 2

local LINE_COUNT = 18 -- screen speed lines
local BUTTON_ALPHA = 0.2
local BUTTON_ALPHA_LOCKED = 0.7

local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local initialized = false
local ctx = nil -- active character context, nil when there is none
local bindToken = 0 -- bumps on every bind/unbind so stale async binds can abort

local stamina = P.MaxStamina
local regenMul = 1 -- 1 + attribute PerkStaminaRegen (pet perk, written by the server)
local lastMirrored = nil
local exhausted = false -- hit 0 stamina; blocked from running until EXHAUST_RESUME

local shiftHeld = false -- physical Shift key
local runToggled = false -- mobile button / gamepad L3
local runBlend = 0 -- 0 = walk speed .. 1 = full run speed

local baseSpeed = P.WalkSpeed -- the walk speed we build on: the server's, or the battle walk (Phase 5)
local serverSpeed = P.WalkSpeed -- WalkSpeed as set by the server (the last value we did not write)
local lastWritten = nil -- the WalkSpeed value WE last wrote (nil = we are not overriding)
-- Phase 5 battle switches (BattleController)
local battleSpeed = nil -- { walk = n, run = n } while a battle sets the character's legal speeds
local freeDash = false -- a dash costs no stamina
local dashLength = P.DashCooldown -- the cooldown of the current / last dash (the battle's DashCooldown while free)
local freeDashCooldown = nil
local dashKeys = nil -- the battle's dash keys (nil = the obby keys Q / B)
local dashListener = nil -- called after every dash (BattleController: BattleCommand "Dash")
local cinematic = nil -- wave 5: the walk speed of a scripted walk-in (SetCinematic); run / dash ignored while set
local fovOverride = nil -- wave 5: SetFovOverride (the cinematics' FOV)
local fovPunch = nil -- wave 5: { amount, t0, dur } FovPunch
local petDash = nil -- dungeon fixes: the battle's pet dash (SetPetDash); while set the dash keys call it and the character never dashes
local PET_DASH_KEYS = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonB }
local uiGate = nil -- client/UiGate (menu W3), loaded lazily; false when missing
local regenBlockedUntil = 0

local cooldownEnd = 0
local dashBufferUntil = 0
local dash = nil -- { dir = Vector3, startTime = n, endTime = n } while dashing
local punchStart = -10

local dashRemote = nil
local ui = nil -- { holder, lines, flashToken, mobile } once the GUI is built

-- forward declarations
local unbindCharacter
local tryDash

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function isLocked()
	if LocalPlayer:GetAttribute(ATTR.Downed) == true then
		return true
	end
	return baseSpeed < FROZEN_SPEED
end

-- In the lobby (not in a match or a battle) stamina is unlimited.
local function staminaFree(root)
	if LocalPlayer:GetAttribute(ATTR.InMatch) == true then
		return false
	end
	local inBattle = LocalPlayer:GetAttribute(ATTR.InBattle or "InBattle")
	if inBattle ~= nil and inBattle ~= false and inBattle ~= "" then
		return false
	end
	return Config.InLobbyZone(root.Position)
end

-- 2 while the dev speed is on and nothing else owns the speed (a battle's legal speeds, a scripted walk); else 1.
local function devSpeedMult()
	if battleSpeed or cinematic then
		return 1
	end
	local inBattle = LocalPlayer:GetAttribute(ATTR.InBattle or "InBattle")
	if inBattle ~= nil and inBattle ~= false and inBattle ~= "" then
		return 1
	end
	local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if pg and pg:GetAttribute(DEV_SPEED_HINT) == true then
		return DEV_SPEED_MULT
	end
	return 1
end

-- Phase 5 (7.2): run / dash input waits for PLAY on the main menu (no UiGate module = always open)
local function gateOpen()
	if uiGate == nil then
		uiGate = false
		local client = script.Parent and script.Parent.Parent
		local inst = client and client:FindFirstChild("UiGate")
		if inst then
			local ok, mod = pcall(require, inst)
			if ok and type(mod) == "table" then
				uiGate = mod
			end
		end
	end
	if uiGate and type(uiGate.HasPlayed) == "function" then
		local ok, played = pcall(uiGate.HasPlayed)
		return (not ok) or played ~= false
	end
	return true
end

-- Mirror stamina into the player attribute the HUD reads; throttled to avoid attribute spam.
local function mirrorStamina(force)
	local value = Util.Clamp(stamina, 0, P.MaxStamina)
	if lastMirrored ~= nil and not force then
		if value == lastMirrored then
			return
		end
		local atEdge = value <= 0 or value >= P.MaxStamina
		if not atEdge and math.abs(value - lastMirrored) < 0.1 then
			return
		end
	end
	lastMirrored = value
	LocalPlayer:SetAttribute(ATTR.Stamina, value)
end

local function applyCameraSettings()
	pcall(function()
		if LocalPlayer.CameraMinZoomDistance > zoomMax then
			LocalPlayer.CameraMinZoomDistance = math.min(0.5, zoomMax)
		end
		LocalPlayer.CameraMaxZoomDistance = zoomMax
	end)
end

-- Pet perk: stamina regenerates (1 + PerkStaminaRegen) times as fast. Sanitised because attributes can
-- hold anything; the server already caps the value (Config.Pets.PerkCaps.StaminaRegen).
local function refreshRegenPerk()
	local value = LocalPlayer:GetAttribute(ATTR.PerkStaminaRegen)
	if type(value) ~= "number" or value ~= value then
		value = 0
	end
	regenMul = 1 + Util.Clamp(value, 0, 5)
end

local function tween(instance, seconds, goal, style, direction)
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local t = TweenService:Create(instance, info, goal)
	t:Play()
	return t
end

----------------------------------------------------------------------
-- GUI: screen speed lines + mobile buttons
----------------------------------------------------------------------
local function setMobileVisible(visible)
	if ui and ui.mobile then
		ui.mobile.Gui.Enabled = visible
	end
end

-- Short burst of white streaks radiating from the screen centre.
local function flashSpeedLines()
	if not ui or not ui.holder then
		return
	end
	ui.flashToken = ui.flashToken + 1
	local token = ui.flashToken
	ui.holder.Visible = true
	for _, line in ipairs(ui.lines) do
		local frame = line.Frame
		frame.Position = UDim2.fromScale(line.X, line.Y)
		frame.BackgroundTransparency = 0.35 + line.Alpha
		tween(frame, 0.34, { BackgroundTransparency = 1, Position = UDim2.fromScale(line.OutX, line.OutY) })
	end
	task.delay(0.4, function()
		if ui and ui.flashToken == token then
			ui.holder.Visible = false
		end
	end)
end

local function buildSpeedLines(playerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name = "MovementFx"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local holder = Instance.new("Frame")
	holder.Name = "SpeedLines"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromScale(1, 1)
	holder.Visible = false
	holder.Parent = gui

	local rng = Random.new(11)
	local lines = {}
	for i = 1, LINE_COUNT do
		local angle = ((i - 1) / LINE_COUNT) * math.pi * 2 + rng:NextNumber(-0.09, 0.09)
		local radius = rng:NextNumber(0.3, 0.45)
		local cosA = math.cos(angle)
		local sinA = math.sin(angle)

		local frame = Instance.new("Frame")
		frame.Name = "Line"
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = Theme.Colors.White
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.fromOffset(rng:NextInteger(90, 170), rng:NextInteger(2, 4))
		-- aim the streak along the pixel-space direction of its position (assumes ~16:9)
		frame.Rotation = math.deg(atan2(sinA * 9, cosA * 16))
		frame.Parent = holder

		-- fade the inner end so the streak looks like it comes out of the distance
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new(1, 0)
		gradient.Parent = frame

		table.insert(lines, {
			Frame = frame,
			X = 0.5 + cosA * radius,
			Y = 0.5 + sinA * radius,
			OutX = 0.5 + cosA * (radius + 0.07),
			OutY = 0.5 + sinA * (radius + 0.07),
			Alpha = rng:NextNumber(0, 0.25),
		})
	end

	gui.Parent = playerGui
	return holder, lines
end

-- Round button with a cooldown overlay (UIGradient with a hard edge, so it stays circular).
local function makeCircleButton(parent, name, text, diameter, position, accent, onPress)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(1, 1)
	button.Size = UDim2.fromOffset(diameter, diameter)
	button.Position = position
	button.BackgroundColor3 = Theme.Colors.Panel
	button.BackgroundTransparency = BUTTON_ALPHA
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = parent
	Theme.Corner(button, UDim.new(0.5, 0))
	local stroke = Theme.Stroke(button, accent, 3, 0.1)

	local scale = Instance.new("UIScale")
	scale.Parent = button

	local overlay = Instance.new("Frame")
	overlay.Name = "Cooldown"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Theme.Colors.Ink
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 2
	overlay.Parent = button
	Theme.Corner(overlay, UDim.new(0.5, 0))
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90 -- top (0) -> bottom (1)
	gradient.Parent = overlay

	local label = Theme.Label(text, "Heading", {
		Size = math.floor(diameter * 0.26),
		Props = { Size = UDim2.fromScale(1, 1), ZIndex = 3 },
	})
	label.Parent = button

	local handle = {
		Button = button,
		Stroke = stroke,
		Accent = accent,
		Overlay = overlay,
		Gradient = gradient,
		Label = label,
		LastFrac = nil,
	}

	local lastPress = 0
	button.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
			local now = os.clock()
			tween(scale, 0.07, { Scale = 0.9 })
			if now - lastPress > 0.12 then -- guards against touch + emulated-mouse double events
				lastPress = now
				onPress()
			end
		end
	end)
	button.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
			tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
	end)

	return handle
end

-- frac: 0 = hidden, 1 = fully dimmed, in between the dim area drains toward the bottom.
local function setCooldownOverlay(handle, frac)
	local q = math.floor(Util.Clamp(frac, 0, 1) * 40 + 0.5) / 40
	if handle.LastFrac == q then
		return
	end
	handle.LastFrac = q
	if q <= 0 then
		handle.Overlay.Visible = false
		return
	end
	handle.Overlay.Visible = true
	if q >= 1 then
		handle.Gradient.Transparency = NumberSequence.new(0.45)
		return
	end
	local edge = 1 - q -- strictly inside (0, 1) because q is a multiple of 1/40
	handle.Gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(edge, 1),
		NumberSequenceKeypoint.new(math.min(edge + 0.001, 0.9995), 0.45),
		NumberSequenceKeypoint.new(1, 0.45),
	})
end

local function denyFeedback(handle)
	if not handle then
		return
	end
	handle.Button.Rotation = 9
	tween(handle.Button, 0.35, { Rotation = 0 }, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
	handle.Stroke.Color = Theme.Colors.Bad
	tween(handle.Stroke, 0.4, { Color = handle.Accent })
end

local function toggleRun()
	if not ctx or isLocked() or cinematic then
		return
	end
	if exhausted and not runToggled then
		denyFeedback(ui and ui.mobile and ui.mobile.run)
		return
	end
	runToggled = not runToggled
end

-- Footprints of the other things that live at the bottom of a touch screen. KEEP IN SYNC with
-- HotbarController.lua (SLOT/GAP/TOUCH_BOTTOM, scale 0.75..1.2) and HudController.lua (VITALS_W, VITALS_H /
-- VG.Compact.H, HOTBAR_GAP, scale Theme.ScreenFactor). Only used to keep our buttons clear of them.
-- (On a narrow phone the hotbar slides a few px LEFT of centre to clear the jump button; our buttons are all
-- right of it, so the centred footprint below still covers every spot they could touch.)
-- bug batch 2 #1: the vitals card is bottom-CENTRE now, right above the hotbar (8 px), centred on it; the regular
-- card is 93 design px tall, the compact one (short touch screens, height <= 500) 80. The HUD itself then keeps the
-- card clear of RUN / DASH (it measures them), so this only steers RUN to a spot that leaves the card alone.
local HOTBAR_W, HOTBAR_H, HOTBAR_BOTTOM = 280, 64, 16
local VITALS_W, VITALS_H, VITALS_H_COMPACT, VITALS_GAP = 300, 93, 80, 8

-- Rectangles are { left, bottom, right, top } in pixels from the screen's left / BOTTOM edge.
local function rectsOverlap(a, b)
	return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
end

-- Places DASH and RUN around Roblox's own jump button without covering it, the hotbar (bottom centre)
-- or the vitals card right above it.
--
-- Roblox's default TouchJump is a J x J square (J = 70 when min(screen axis) <= 500, else 120) whose left edge
-- is 1.5 J + 10 px and whose right edge is 0.5 J + 10 px from the screen's right edge; its bottom edge is
-- 20 px (small) or 0.75 J (large) above the screen's bottom.
--   * DASH goes straight above the jump button (the thumb's natural "up" flick);
--   * RUN prefers the spot left of the jump button; on narrow phones that spot runs into the hotbar, so it
--     moves to the diagonal above-left, and as a last resort onto the top of the DASH button.
local function layoutMobileControls(m)
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local w, h = vp.X, vp.Y
	local small = math.min(w, h) <= 500

	local jump = small and 70 or 120
	local jumpRight = jump * 0.5 + 10
	local jumpLeft = jump * 1.5 + 10
	local jumpBottom = small and 20 or jump * 0.75
	local jumpTop = jumpBottom + jump

	local hotbarScale = Util.Clamp(math.min(w / 1280, h / 720), 0.75, 1.2)
	local hotbarHalf = HOTBAR_W * hotbarScale * 0.5 + 8
	local hotbar = {
		w * 0.5 - hotbarHalf,
		HOTBAR_BOTTOM - 4,
		w * 0.5 + hotbarHalf,
		HOTBAR_BOTTOM + HOTBAR_H * hotbarScale + 8,
	}
	local vitalsScale = Theme.ScreenFactor(h)
	local vitalsHalf = VITALS_W * vitalsScale * 0.5 + 8
	local vitalsBottom = HOTBAR_BOTTOM + HOTBAR_H * hotbarScale + VITALS_GAP
	local vitals = {
		w * 0.5 - vitalsHalf,
		vitalsBottom - 4,
		w * 0.5 + vitalsHalf,
		vitalsBottom + (h <= 500 and VITALS_H_COMPACT or VITALS_H) * vitalsScale + 6,
	}
	local jumpRect = { w - jumpLeft - 4, jumpBottom - 4, w - jumpRight + 4, jumpTop + 4 }

	-- DASH
	local dashSize = small and 66 or 84
	local dashRight = math.max(14, jump + 10 - dashSize * 0.5) -- centred over the jump button
	local dashBottom = jumpTop + 10
	local dashRect = { w - dashRight - dashSize, dashBottom, w - dashRight, dashBottom + dashSize }

	-- RUN: first candidate that touches nothing wins; in a battle (the battle cluster has its own DASH, so the
	-- mobile DASH hides) RUN takes the DASH spot straight above the jump button and the cluster goes around it
	local runSize = small and 58 or 72
	if dashKeys then
		local runRight = math.max(14, jump + 10 - runSize * 0.5)
		local runBottom = jumpTop + 10
		m.run.Button.Size = UDim2.fromOffset(runSize, runSize)
		m.run.Label.TextSize = math.floor(runSize * 0.26)
		m.run.Button.Position = UDim2.new(1, -runRight, 1, -runBottom)
		m.dash.Button.Visible = false
		m.rects = {
			jump = { jumpRect[1] + 4, jumpRect[2] + 4, jumpRect[3] - 4, jumpRect[4] - 4 },
			run = { w - runRight - runSize, runBottom, w - runRight, runBottom + runSize },
		}
		return
	end
	m.dash.Button.Visible = true
	local candidates = {
		{ jumpLeft + 12, jumpBottom + 4 }, -- beside the jump button
		{ dashRight + dashSize + 12, jumpTop + 6 }, -- diagonal: above-left of the jump button
		{ dashRight, dashBottom + dashSize + 10 }, -- on top of DASH
	}
	local runRight, runBottom = candidates[3][1], candidates[3][2]
	for _, c in ipairs(candidates) do
		local rect = { w - c[1] - runSize, c[2], w - c[1], c[2] + runSize }
		local onScreen = rect[1] >= 6 and rect[4] <= h - 80
		if onScreen
			and not rectsOverlap(rect, hotbar)
			and not rectsOverlap(rect, vitals)
			and not rectsOverlap(rect, jumpRect)
			and not rectsOverlap(rect, dashRect)
		then
			runRight, runBottom = c[1], c[2]
			break
		end
	end

	m.dash.Button.Size = UDim2.fromOffset(dashSize, dashSize)
	m.dash.Label.TextSize = math.floor(dashSize * 0.26)
	m.dash.Button.Position = UDim2.new(1, -dashRight, 1, -dashBottom)
	m.run.Button.Size = UDim2.fromOffset(runSize, runSize)
	m.run.Label.TextSize = math.floor(runSize * 0.26)
	m.run.Button.Position = UDim2.new(1, -runRight, 1, -runBottom)
	m.rects = {
		jump = { jumpRect[1] + 4, jumpRect[2] + 4, jumpRect[3] - 4, jumpRect[4] - 4 },
		run = { w - runRight - runSize, runBottom, w - runRight, runBottom + runSize },
		dash = dashRect,
	}
end

local function buildMobileControls(playerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name = "MobileControls"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 4
	gui.Enabled = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- an arc above / left of the default jump button, within thumb reach; the exact offsets depend on the
	-- size of Roblox's jump button and on the HUD, so layoutMobileControls places (and sizes) them below
	local dashButton = makeCircleButton(gui, "DashButton", "DASH", 76, UDim2.new(1, -30, 1, -175), Theme.Colors.Stamina, function()
		tryDash()
	end)
	local runButton = makeCircleButton(gui, "RunButton", "RUN", 64, UDim2.new(1, -120, 1, -150), Theme.Colors.Good, function()
		toggleRun()
	end)

	local controls = {
		Gui = gui,
		dash = dashButton,
		run = runButton,
		locked = nil,
		runOn = nil,
		lowStamina = nil,
	}
	layoutMobileControls(controls)

	-- re-lay out when the viewport changes (rotation, window resize, foldables); the gui is built
	-- once and never destroyed, so the only connection to manage is the one on the current camera
	local cameraConn = nil
	local function bindCamera()
		if cameraConn then
			cameraConn:Disconnect()
			cameraConn = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			cameraConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				layoutMobileControls(controls)
			end)
		end
		layoutMobileControls(controls)
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	bindCamera()

	gui.Parent = playerGui
	return controls
end

-- Called every frame from the character step; only touches properties that changed.
local function updateMobileUi(locked)
	local m = ui and ui.mobile
	if not m then
		return
	end
	setCooldownOverlay(m.dash, MovementController.GetDashCooldownFraction())

	if m.locked ~= locked then
		m.locked = locked
		local alpha = BUTTON_ALPHA
		if locked then
			alpha = BUTTON_ALPHA_LOCKED
		end
		m.dash.Button.BackgroundTransparency = alpha
		m.run.Button.BackgroundTransparency = alpha
		m.runOn = nil -- force the run button to refresh its colours
	end

	if m.runOn ~= runToggled then
		m.runOn = runToggled
		if runToggled then
			tween(m.run.Button, 0.15, { BackgroundColor3 = Theme.Colors.Good:Lerp(Theme.Colors.Panel, 0.5) })
		else
			tween(m.run.Button, 0.15, { BackgroundColor3 = Theme.Colors.Panel })
		end
	end

	local lowStamina = (not freeDash) and stamina < P.DashStaminaCost
	if m.lowStamina ~= lowStamina then
		m.lowStamina = lowStamina
		if lowStamina then
			m.dash.Label.TextTransparency = 0.5
		else
			m.dash.Label.TextTransparency = 0
		end
	end
end

local function buildGui()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui", 30)
	if not playerGui then
		return
	end
	local built = { flashToken = 0 }
	local okLines, holder, lines = pcall(buildSpeedLines, playerGui)
	if okLines then
		built.holder = holder
		built.lines = lines
	else
		warn("[MovementController] speed lines failed: " .. tostring(holder))
	end
	if UserInputService.TouchEnabled then
		local okMobile, mobile = pcall(buildMobileControls, playerGui)
		if okMobile then
			built.mobile = mobile
		else
			warn("[MovementController] mobile controls failed: " .. tostring(mobile))
		end
	end
	ui = built
	if ctx then
		setMobileVisible(true)
	end
end

----------------------------------------------------------------------
-- Character effects (trail, dust, bursts)
----------------------------------------------------------------------
local function newEmitter(parent, props)
	local emitter = Instance.new("ParticleEmitter")
	for key, value in pairs(props) do
		emitter[key] = value
	end
	emitter.Parent = parent
	return emitter
end

-- Builds everything under the HumanoidRootPart; returns the fx table and a list to destroy.
local function buildCharacterFx(humanoid, root)
	local fx = {}
	local instances = {}

	local feetOffset = 3
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		feetOffset = humanoid.HipHeight + root.Size.Y * 0.5
	end
	feetOffset = Util.Clamp(feetOffset, 2, 5)

	local feet = Instance.new("Attachment")
	feet.Name = "NC_Feet"
	feet.Position = Vector3.new(0, -feetOffset + 0.15, 0)
	feet.Parent = root
	table.insert(instances, feet)

	-- soft footstep dust (toggled while running on the ground)
	fx.dust = newEmitter(feet, {
		Name = "NC_RunDust",
		Texture = TEX_SMOKE,
		Color = ColorSequence.new(Theme.Colors.Cloud, Theme.Colors.CloudShade),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, 2.2),
		}),
		Lifetime = NumberRange.new(0.35, 0.65),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(35, 35),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-45, 45),
		Acceleration = Vector3.new(0, 3, 0),
		EmissionDirection = Enum.NormalId.Top,
		LightEmission = 0.15,
		LockedToPart = false,
		Rate = 20,
		Enabled = false,
	})

	-- bigger puff for landings and the dash take-off (manual :Emit only)
	fx.puff = newEmitter(feet, {
		Name = "NC_Puff",
		Texture = TEX_SMOKE,
		Color = ColorSequence.new(Theme.Colors.Cloud, Theme.Colors.CloudShade),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 3.4),
		}),
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(6, 11),
		SpreadAngle = Vector2.new(80, 80),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
		Drag = 3,
		Acceleration = Vector3.new(0, 2, 0),
		EmissionDirection = Enum.NormalId.Top,
		LightEmission = 0.1,
		LockedToPart = false,
		Rate = 0,
		Enabled = false,
	})

	-- sparkle burst for the dash
	fx.sparks = newEmitter(root, {
		Name = "NC_DashSparks",
		Texture = TEX_SPARKLES,
		Color = ColorSequence.new(Theme.Colors.White, Theme.Colors.Stamina),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Lifetime = NumberRange.new(0.25, 0.45),
		Speed = NumberRange.new(10, 22),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		LightEmission = 1,
		LockedToPart = false,
		Rate = 0,
		Enabled = false,
	})
	table.insert(instances, fx.dust)
	table.insert(instances, fx.puff)
	table.insert(instances, fx.sparks)

	-- trail through the torso, only enabled while dashing
	local top = Instance.new("Attachment")
	top.Name = "NC_TrailTop"
	top.Position = Vector3.new(0, 1.2, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "NC_TrailBottom"
	bottom.Position = Vector3.new(0, -1.4, 0)
	bottom.Parent = root
	table.insert(instances, top)
	table.insert(instances, bottom)

	local trail = Instance.new("Trail")
	trail.Name = "NC_DashTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.32
	trail.MinLength = 0.1
	trail.FaceCamera = true
	trail.LightEmission = 0.7
	trail.Color = ColorSequence.new(Theme.Colors.White, Theme.Colors.Stamina)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	trail.Enabled = false
	trail.Parent = root
	fx.trail = trail
	table.insert(instances, trail)

	return fx, instances
end

----------------------------------------------------------------------
-- Dash
----------------------------------------------------------------------
-- Horizontal unit vector: move input if any, else the camera look, else the body facing.
-- Second return value tells whether the player was actually steering.
local function computeDashDirection(humanoid, root)
	local md = humanoid.MoveDirection
	local flat = Vector3.new(md.X, 0, md.Z)
	if flat.Magnitude > MOVE_EPS then
		return flat.Unit, true
	end
	local camera = workspace.CurrentCamera
	if camera then
		local look = camera.CFrame.LookVector
		flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.05 then
			return flat.Unit, false
		end
	end
	local facing = root.CFrame.LookVector
	flat = Vector3.new(facing.X, 0, facing.Z)
	if flat.Magnitude > 0.05 then
		return flat.Unit, false
	end
	return Vector3.new(0, 0, 1), false
end

-- Returns nil when a dash may start, otherwise a short reason string.
local function dashBlockedReason()
	local c = ctx
	if not c then
		return "nochar"
	end
	local humanoid = c.humanoid
	if humanoid.Health <= 0 or humanoid.Sit or humanoid.PlatformStand then
		return "state"
	end
	if isLocked() then
		return "locked"
	end
	if cinematic then
		return "cinematic"
	end
	if dash then
		return "dashing"
	end
	if os.clock() < cooldownEnd then
		return "cooldown"
	end
	if not freeDash and stamina < P.DashStaminaCost then
		return "stamina"
	end
	return nil
end

-- Stop the dash. Normally the character is handed a sane post-dash speed so it does not keep
-- flying at DashSpeed (the course generator assumes the dash ends at run speed). With halt = true
-- (Downed / frozen by the server) the horizontal velocity is simply cancelled.
local function endDash(halt)
	local d = dash
	if not d then
		return
	end
	dash = nil
	local c = ctx
	if not c then
		return
	end
	local root = c.root
	local humanoid = c.humanoid
	if not root.Parent or humanoid.Health <= 0 then
		return
	end
	local exitSpeed = 0
	if not halt then
		exitSpeed = humanoid.WalkSpeed
		if humanoid.FloorMaterial == Enum.Material.Air then
			exitSpeed = math.max(exitSpeed, P.RunSpeed)
		end
		exitSpeed = math.min(exitSpeed, P.DashSpeed)
	end
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(d.dir.X * exitSpeed, v.Y, d.dir.Z * exitSpeed)
end

local function playDashFx(c)
	local fx = c.fx
	local now = os.clock()
	if fx.trail then
		fx.trail.Enabled = true
		c.trailOffAt = now + P.DashDuration + 0.06
	end
	if fx.puff then
		fx.puff:Emit(8)
	end
	if fx.sparks then
		fx.sparks:Emit(10)
	end
	flashSpeedLines()
end

function tryDash()
	if petDash then
		return false -- a battle: Shift / B are the pet's dash (onDashAction), the character never dashes
	end
	local reason = dashBlockedReason()
	if reason == "cooldown" then
		-- queue a press that arrives just before the cooldown ends so it still feels instant
		local now = os.clock()
		if cooldownEnd - now <= DASH_BUFFER and (freeDash or stamina >= P.DashStaminaCost) then
			dashBufferUntil = now + DASH_BUFFER
		end
		return false
	elseif reason == "stamina" then
		denyFeedback(ui and ui.mobile and ui.mobile.dash)
		return false
	elseif reason ~= nil then
		return false
	end

	local c = ctx
	local humanoid = c.humanoid
	local root = c.root
	local now = os.clock()
	local dir, steering = computeDashDirection(humanoid, root)

	if not freeDash and not staminaFree(root) then
		stamina = stamina - P.DashStaminaCost
		if stamina <= 0 then
			stamina = 0
			exhausted = true
			runToggled = false
		end
		regenBlockedUntil = now + DASH_REGEN_DELAY
	end
	dashLength = (freeDash and freeDashCooldown) or P.DashCooldown
	cooldownEnd = now + dashLength
	dashBufferUntil = 0
	dash = { dir = dir, startTime = now, endTime = now + P.DashDuration }
	punchStart = now
	mirrorStamina(false)

	-- face the dash when the player was not steering (the humanoid already turns toward input)
	if not steering then
		local pos = root.Position
		root.CFrame = CFrame.new(pos, pos + dir)
	end
	-- apply immediately so the press feels instant; Stepped keeps re-asserting it afterwards
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(dir.X * P.DashSpeed, v.Y, dir.Z * P.DashSpeed)

	playDashFx(c)
	if dashRemote then
		pcall(function()
			dashRemote:FireServer()
		end)
	end
	if dashListener then
		local ok, err = pcall(dashListener)
		if not ok then
			warn("[MovementController] dash listener failed: " .. tostring(err))
		end
	end
	return true
end

-- Runs just before every physics step while a character is bound.
local function onStepped()
	local d = dash
	if not d then
		return
	end
	local c = ctx
	if not c or not c.root.Parent then
		dash = nil
		return
	end
	if isLocked() then
		endDash(true)
		return
	end
	if os.clock() >= d.endTime then
		endDash(false)
		return
	end
	local root = c.root
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(d.dir.X * P.DashSpeed, v.Y, d.dir.Z * P.DashSpeed)
end

----------------------------------------------------------------------
-- Per-frame update (run, stamina, effects, camera)
----------------------------------------------------------------------
local function dashPunchValue(now)
	local t = now - punchStart
	if t < 0 or t >= PUNCH_TOTAL then
		return 0
	end
	if t < PUNCH_ATTACK then
		return t / PUNCH_ATTACK
	end
	local u = (t - PUNCH_ATTACK) / (PUNCH_TOTAL - PUNCH_ATTACK)
	return 1 - u * u * (3 - 2 * u) -- smoothstep release
end

local function step(dt)
	local c = ctx
	if not c then
		return
	end
	local humanoid = c.humanoid
	local root = c.root
	if not humanoid.Parent or not root.Parent or humanoid.Health <= 0 then
		unbindCharacter()
		return
	end
	local now = os.clock()
	dt = Util.Clamp(dt, 0, 0.1)

	-- 1. Whatever WalkSpeed we did not write ourselves belongs to the server (freeze, revive...). In a battle the
	--    battle walk is the base instead, but a server freeze (0) still wins.
	local current = humanoid.WalkSpeed
	if lastWritten == nil or math.abs(current - lastWritten) > SPEED_EPS then
		serverSpeed = current
		lastWritten = nil
	end
	baseSpeed = serverSpeed
	if battleSpeed and serverSpeed >= FROZEN_SPEED then
		baseSpeed = battleSpeed.walk
	end
	if cinematic and serverSpeed >= FROZEN_SPEED then
		baseSpeed = cinematic
	end

	-- 2. Lockout: Downed or frozen players cannot run or dash (nor during a scripted walk-in).
	local locked = isLocked() or cinematic ~= nil
	if locked then
		if dash then
			endDash(true)
		end
		runToggled = false
		runBlend = 0 -- snap back to the server's speed immediately
		dashBufferUntil = 0
	end

	-- 3. Run + stamina (none spent in the lobby: the bar is full there).
	local free = staminaFree(root)
	if free then
		stamina = P.MaxStamina
		exhausted = false
	end
	local moving = humanoid.MoveDirection.Magnitude > MOVE_EPS
	local wantsRun = (shiftHeld or runToggled) and not locked
	local running = wantsRun and moving and not exhausted and stamina > 0 and not humanoid.Sit
	if dash then
		running = false
	end
	if free then
		regenBlockedUntil = 0
	elseif running then
		stamina = stamina - P.RunStaminaDrain * dt
		regenBlockedUntil = math.max(regenBlockedUntil, now + RUN_REGEN_DELAY)
		if stamina <= 0 then
			stamina = 0
			exhausted = true
			runToggled = false
			running = false
		end
	elseif now >= regenBlockedUntil then
		stamina = math.min(P.MaxStamina, stamina + P.StaminaRegen * regenMul * dt)
	end
	if exhausted and stamina >= EXHAUST_RESUME then
		exhausted = false
	end
	mirrorStamina(false)

	-- 4. Smooth run blend (held steady while dashing so the speed does not dip afterwards).
	if not dash then
		local target = 0
		if running then
			target = 1
		end
		local rate = RUN_RAMP_DOWN
		if target > runBlend then
			rate = RUN_RAMP_UP
		end
		runBlend = runBlend + (target - runBlend) * (1 - math.exp(-rate * dt))
		if math.abs(target - runBlend) < 0.005 then
			runBlend = target
		end
	end

	-- 5. Write WalkSpeed: base speed + run boost (the battle run instead of RunSpeed in a battle), times the dev speed.
	--    Outside a battle it stops touching it when not running; in a battle the walk itself is ours to write.
	local speedMult = devSpeedMult()
	if baseSpeed >= FROZEN_SPEED and (runBlend > 0.001 or battleSpeed ~= nil or cinematic ~= nil or speedMult ~= 1) then
		local runTarget = (cinematic and baseSpeed) or (battleSpeed and battleSpeed.run) or math.max(baseSpeed, P.RunSpeed)
		local speed = (baseSpeed + (runTarget - baseSpeed) * runBlend) * speedMult
		if lastWritten == nil or math.abs(speed - lastWritten) > 0.001 or math.abs(current - speed) > SPEED_EPS then
			humanoid.WalkSpeed = speed
			lastWritten = speed
		end
	elseif lastWritten ~= nil then
		humanoid.WalkSpeed = baseSpeed
		lastWritten = nil
	end

	-- 6. Dash end (Stepped normally does this; this is the safety net) and queued dash.
	if dash and now >= dash.endTime then
		endDash(false)
	end
	if dashBufferUntil > 0 then
		if now >= dashBufferUntil then
			dashBufferUntil = 0
		elseif now >= cooldownEnd and not dash then
			dashBufferUntil = 0
			tryDash()
		end
	end

	-- 7. Effects: trail off, dust, landing puff.
	local fx = c.fx
	if fx.trail and fx.trail.Enabled and not dash and now >= c.trailOffAt then
		fx.trail.Enabled = false
	end
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local wantDust = grounded and moving and runBlend > 0.5
	if wantDust ~= c.dustOn then
		c.dustOn = wantDust
		fx.dust.Enabled = wantDust
	end
	local vy = root.AssemblyLinearVelocity.Y
	if grounded and not c.wasGrounded and c.lastVy < -30 then
		fx.puff:Emit(Util.Clamp(math.floor(-c.lastVy / 8), 3, 10))
	end
	c.wasGrounded = grounded
	c.lastVy = vy

	-- 8. Camera FOV: widen while running, punch on dash.
	local camera = workspace.CurrentCamera
	if camera then
		local fov = fovOverride or (BASE_FOV + RUN_FOV_BOOST * runBlend + DASH_FOV_BOOST * dashPunchValue(now))
		local fp = fovPunch
		if fp then
			local p = (now - fp.t0) / fp.dur
			if p >= 1 or p < 0 then
				fovPunch = nil
			else
				fov = fov + fp.amount * (1 - p) * (1 - p)
			end
		end
		if c.lastFov == nil or math.abs(fov - c.lastFov) > 0.01 then
			camera.FieldOfView = fov
			c.lastFov = fov
		end
	end

	-- 9. Mobile button visuals.
	updateMobileUi(locked)
end

----------------------------------------------------------------------
-- Character lifecycle
----------------------------------------------------------------------
function unbindCharacter()
	bindToken = bindToken + 1 -- cancels any bind that is still waiting for children
	local c = ctx
	if not c then
		return
	end
	ctx = nil -- first, so re-entrant calls (Died + CharacterRemoving) are harmless

	dash = nil
	dashBufferUntil = 0
	runToggled = false
	runBlend = 0

	for _, conn in ipairs(c.conns) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	c.conns = {}

	-- give the server's WalkSpeed back untouched if we had it overridden
	if lastWritten ~= nil then
		pcall(function()
			if c.humanoid.Parent then
				c.humanoid.WalkSpeed = serverSpeed
			end
		end)
	end
	lastWritten = nil

	for _, inst in ipairs(c.instances) do
		pcall(function()
			inst:Destroy()
		end)
	end
	c.instances = {}

	fovPunch = nil
	local camera = workspace.CurrentCamera
	if camera and c.lastFov ~= nil and c.lastFov ~= BASE_FOV and fovOverride == nil then
		pcall(function()
			camera.FieldOfView = BASE_FOV
		end)
	end
	setMobileVisible(false)
end

local function bindCharacter(char)
	unbindCharacter()
	local token = bindToken

	local humanoid = char:WaitForChild("Humanoid", 10)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if token ~= bindToken then
		return -- a newer bind/unbind happened while we waited
	end
	if not humanoid or not root or not humanoid:IsA("Humanoid") or not root:IsA("BasePart") then
		return
	end
	if humanoid.Health <= 0 or not char:IsDescendantOf(game) then
		return
	end

	-- fresh state for this life
	stamina = P.MaxStamina
	exhausted = false
	runToggled = false
	runBlend = 0
	serverSpeed = humanoid.WalkSpeed
	baseSpeed = serverSpeed
	if battleSpeed and serverSpeed >= FROZEN_SPEED then
		baseSpeed = battleSpeed.walk
	end
	lastWritten = nil
	regenBlockedUntil = 0
	dashBufferUntil = 0
	dash = nil
	mirrorStamina(true)
	applyCameraSettings()

	local fx, instances = buildCharacterFx(humanoid, root)
	local c = {
		char = char,
		humanoid = humanoid,
		root = root,
		conns = {},
		instances = instances,
		fx = fx,
		dustOn = false,
		wasGrounded = true,
		lastVy = 0,
		trailOffAt = 0,
		lastFov = nil,
	}
	ctx = c

	table.insert(c.conns, RunService.Stepped:Connect(onStepped))
	table.insert(c.conns, RunService.RenderStepped:Connect(step))
	table.insert(c.conns, humanoid.Died:Connect(function()
		if ctx == c then
			unbindCharacter()
		end
	end))
	table.insert(c.conns, char.AncestryChanged:Connect(function()
		if ctx == c and not char:IsDescendantOf(game) then
			unbindCharacter()
		end
	end))

	setMobileVisible(true)
end

----------------------------------------------------------------------
-- Input (ContextActionService)
----------------------------------------------------------------------
local function onRunAction(_name, state, input)
	local isToggleKey = input ~= nil and input.KeyCode == Enum.KeyCode.ButtonL3
	if state == Enum.UserInputState.Begin then
		if UserInputService:GetFocusedTextBox() ~= nil then
			return Enum.ContextActionResult.Pass
		end
		if not gateOpen() then
			return Enum.ContextActionResult.Pass -- the main menu is still up (7.2)
		end
		if isToggleKey then
			toggleRun()
		else
			shiftHeld = true
		end
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		if not isToggleKey then
			shiftHeld = false
		end
	end
	return Enum.ContextActionResult.Sink
end

local function onDashAction(_name, state)
	if state == Enum.UserInputState.Begin then
		if not gateOpen() then
			return Enum.ContextActionResult.Pass -- the main menu is still up (7.2)
		end
		if UserInputService:GetFocusedTextBox() == nil then
			local fn = petDash
			if fn then
				local ok, err = pcall(fn) -- the pet dashes (BattleCommand "Dash"); no impulse, no stamina
				if not ok then
					warn("[MovementController] pet dash failed: " .. tostring(err))
				end
			else
				tryDash()
			end
		end
	end
	return Enum.ContextActionResult.Sink
end

local unpackList = table.unpack or unpack

local DEFAULT_RUN_KEYS = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3 }
local DEFAULT_DASH_KEYS = { Enum.KeyCode.Q, Enum.KeyCode.ButtonB }

-- the run keys that do not dash (Shift dashes in a battle: RUN moves to Ctrl there)
local function runKeys()
	if not dashKeys then
		return DEFAULT_RUN_KEYS
	end
	local taken = {}
	for _, k in ipairs(dashKeys) do
		taken[k] = true
	end
	local out = {}
	for _, k in ipairs(DEFAULT_RUN_KEYS) do
		if not taken[k] then
			out[#out + 1] = k
		end
	end
	if taken[Enum.KeyCode.LeftShift] or taken[Enum.KeyCode.RightShift] then
		out[#out + 1] = Enum.KeyCode.LeftControl
	end
	return out
end

local function bindKeys()
	pcall(function()
		ContextActionService:UnbindAction("NimbusRun")
	end)
	pcall(function()
		ContextActionService:UnbindAction("NimbusDash")
	end)
	-- High priority beats Roblox's shift-lock (Medium), so Shift is ours alone.
	ContextActionService:BindActionAtPriority("NimbusRun", onRunAction, false, Enum.ContextActionPriority.High.Value, unpackList(runKeys()))
	-- a battle's dash keys (Shift) need the High priority too (the run action had them before)
	local priority = dashKeys and Enum.ContextActionPriority.High.Value or Enum.ContextActionPriority.Default.Value
	ContextActionService:BindActionAtPriority("NimbusDash", onDashAction, false, priority, unpackList(dashKeys or DEFAULT_DASH_KEYS))
end

local function bindInput()
	bindKeys()

	-- never leave Shift "stuck" when focus moves away from the game
	UserInputService.WindowFocusReleased:Connect(function()
		shiftHeld = false
	end)
	UserInputService.TextBoxFocused:Connect(function()
		shiftHeld = false
	end)
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
function MovementController.GetDashCooldownFraction()
	local remaining = cooldownEnd - os.clock()
	if remaining <= 0 then
		return 0
	end
	return Util.Clamp(remaining / math.max(0.05, dashLength), 0, 1)
end

----------------------------------------------------------------------
-- Phase 5 battle switches (BattleController; contract 3.9 / 4.4)
----------------------------------------------------------------------
local function finite(v)
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- keys: a list of Enum.KeyCode (in battle { LeftShift, RightShift, ButtonB }); nil restores the obby keys (Q / B)
function MovementController.SetDashKeys(keys)
	local list = nil
	if type(keys) == "table" then
		list = {}
		for _, k in ipairs(keys) do
			if typeof(k) == "EnumItem" then
				list[#list + 1] = k
			end
		end
		if #list == 0 then
			list = nil
		end
	end
	dashKeys = list
	shiftHeld = false -- Shift may have just changed hands
	if initialized then
		pcall(bindKeys)
	end
	-- the battle cluster has its own DASH button: the mobile one steps aside while a battle owns the dash keys and
	-- RUN takes its spot above the jump button (layoutMobileControls)
	local m = ui and ui.mobile
	if m and m.dash and m.dash.Button then
		m.dash.Button.Visible = dashKeys == nil
		pcall(layoutMobileControls, m)
	end
end

-- fn: the battle's pet dash (BattleController: BattleCommand "Dash"); Shift / RightShift / B call it and nothing else
-- (no character impulse, no stamina, no dash cooldown), RUN moves to Ctrl. nil: the obby keys again (Q / B dash,
-- Shift runs)
function MovementController.SetPetDash(fn)
	petDash = type(fn) == "function" and fn or nil
	if petDash and dash then
		endDash(false) -- a dash that was running when the battle started ends now
	end
	MovementController.SetDashKeys(petDash and PET_DASH_KEYS or nil)
end

-- the touch buttons in screen px { left, bottom, right, top } (from the left / BOTTOM edge): jump (Roblox's), run,
-- dash (nil in a battle); nil without the mobile controls
function MovementController.MobileLayout()
	local m = ui and ui.mobile
	return m and m.rects or nil
end

-- on: a dash costs no stamina (and never exhausts); cooldown: the dash cooldown meanwhile (the battle's DashCooldown)
function MovementController.SetFreeDash(on, cooldown)
	freeDash = on == true
	freeDashCooldown = (freeDash and finite(cooldown) and cooldown > 0) and math.min(cooldown, 30) or nil
end

-- walk / run: the fighter's legal battle speeds (BattleCatalog.Fighter.WalkOf / RunOf, the Speed events); nil clears
function MovementController.SetBattleSpeed(walk, run)
	if not finite(walk) or walk <= 0 then
		battleSpeed = nil
	else
		walk = Util.Clamp(walk, 1, 100)
		if not finite(run) or run <= 0 then
			run = walk * 1.3
		end
		battleSpeed = { walk = walk, run = Util.Clamp(math.max(run, walk), 1, 100) }
	end
	-- apply at once (no frame of the old speed)
	local c = ctx
	if not c or not c.humanoid or not c.humanoid.Parent then
		return
	end
	local humanoid = c.humanoid
	local current = humanoid.WalkSpeed
	if lastWritten == nil or math.abs(current - lastWritten) > SPEED_EPS then
		serverSpeed = current -- a server write since our last one
		lastWritten = nil
	end
	if serverSpeed < FROZEN_SPEED then
		return -- frozen / Downed: the server's 0 wins
	end
	if battleSpeed then
		baseSpeed = battleSpeed.walk
		local speed = baseSpeed + (battleSpeed.run - baseSpeed) * runBlend
		humanoid.WalkSpeed = speed
		lastWritten = speed
	else
		baseSpeed = serverSpeed
		if lastWritten ~= nil then
			local speed = baseSpeed
			if runBlend > 0.001 then
				speed = baseSpeed + (math.max(baseSpeed, P.RunSpeed) - baseSpeed) * runBlend
				lastWritten = speed
			else
				lastWritten = nil
			end
			humanoid.WalkSpeed = speed
		end
	end
end

-- the battle DASH button: the same dash as the dash key (-> bool)
function MovementController.TryDash()
	if not gateOpen() then
		return false
	end
	return tryDash() == true
end

-- fn() runs after every dash (nil clears it)
function MovementController.SetDashListener(fn)
	dashListener = type(fn) == "function" and fn or nil
end

-- bug batch 2 (#19): n caps the camera zoom (DungeonController: 14 in a run); nil restores ZOOM_MAX. Junk is ignored.
function MovementController.SetZoomMax(n)
	if n == nil then
		zoomMax = ZOOM_MAX
	elseif finite(n) and n > 0 then
		zoomMax = Util.Clamp(n, 0.5, 400)
	else
		return zoomMax
	end
	if LocalPlayer then
		applyCameraSettings()
	end
	return zoomMax
end

-- tests / tools: the speed ownership state
function MovementController.GetSpeedState()
	return {
		Server = serverSpeed,
		Base = baseSpeed,
		Walk = battleSpeed and battleSpeed.walk or nil,
		Run = battleSpeed and battleSpeed.run or nil,
		RunTarget = battleSpeed and battleSpeed.run or math.max(baseSpeed, P.RunSpeed),
		FreeDash = freeDash,
		DashCooldown = (freeDash and freeDashCooldown) or P.DashCooldown,
		DashKeys = dashKeys,
		PetDash = petDash ~= nil,
		Stamina = stamina,
		ExhaustResume = EXHAUST_RESUME,
		Written = lastWritten,
		Cinematic = cinematic ~= nil,
		FovOverride = fovOverride,
		StaminaFree = ctx ~= nil and staminaFree(ctx.root),
		DevSpeed = devSpeedMult() ~= 1,
	}
end

-- wave 5 (bugs #15 / #26): the cinematics' FOV (nil = 70 + run + dash again); written at once when a character is bound
function MovementController.SetFovOverride(fov)
	if not finite(fov) then
		fovOverride = nil
	else
		fovOverride = Util.Clamp(fov, 20, 110)
	end
	local camera = workspace.CurrentCamera
	local c = ctx
	if camera and fovOverride then
		pcall(function()
			camera.FieldOfView = fovOverride
		end)
		if c then
			c.lastFov = fovOverride
		end
	elseif c then
		c.lastFov = nil -- (the next frame writes the normal FOV)
	elseif camera then
		pcall(function()
			camera.FieldOfView = BASE_FOV -- (no character bound: no frame will write it back)
		end)
	end
end

-- a quick zoom punch (big attacks in a dungeon): + degrees, easing out over `seconds`; the larger of two live punches wins
function MovementController.FovPunch(degrees, seconds)
	if not finite(degrees) or degrees <= 0 then
		return false
	end
	seconds = (finite(seconds) and seconds > 0) and math.min(seconds, 2) or 0.25
	local now = os.clock()
	local live = fovPunch
	if live then
		local p = (now - live.t0) / live.dur
		if p >= 0 and p < 1 and live.amount * (1 - p) * (1 - p) >= degrees then
			return false
		end
	end
	fovPunch = { amount = math.min(degrees, 20), t0 = now, dur = seconds }
	return true
end

-- a scripted walk (the room walk-in): WalkSpeed = walkSpeed, run / dash ignored; nil gives the normal rules back at once
function MovementController.SetCinematic(walkSpeed)
	if not finite(walkSpeed) or walkSpeed <= 0 then
		if cinematic == nil then
			return
		end
		cinematic = nil
		local c = ctx
		if c and c.humanoid and c.humanoid.Parent and lastWritten ~= nil then
			local current = c.humanoid.WalkSpeed
			if math.abs(current - lastWritten) <= SPEED_EPS then
				baseSpeed = (battleSpeed and serverSpeed >= FROZEN_SPEED) and battleSpeed.walk or serverSpeed
				c.humanoid.WalkSpeed = baseSpeed
				lastWritten = battleSpeed and baseSpeed or nil
			end
		end
		return
	end
	cinematic = Util.Clamp(walkSpeed, 1, 100)
	runToggled = false
	runBlend = 0
	if dash then
		endDash(true)
	end
	local c = ctx
	if not c or not c.humanoid or not c.humanoid.Parent then
		return
	end
	local humanoid = c.humanoid
	local current = humanoid.WalkSpeed
	if lastWritten == nil or math.abs(current - lastWritten) > SPEED_EPS then
		serverSpeed = current
		lastWritten = nil
	end
	if serverSpeed < FROZEN_SPEED then
		return -- frozen / Downed: the server's 0 wins
	end
	baseSpeed = cinematic
	humanoid.WalkSpeed = cinematic
	lastWritten = cinematic
end

function MovementController.Init()
	if initialized then
		return
	end
	initialized = true
	if not LocalPlayer then
		return
	end

	stamina = P.MaxStamina
	mirrorStamina(true)
	applyCameraSettings()
	bindInput()

	refreshRegenPerk()
	LocalPlayer:GetAttributeChangedSignal(ATTR.PerkStaminaRegen):Connect(refreshRegenPerk)

	-- Remotes.Get yields until the folder replicates, so never block Init on it
	task.spawn(function()
		local ok, remote = pcall(Remotes.Get, "Dash")
		if ok then
			dashRemote = remote
		else
			warn("[MovementController] Dash remote unavailable: " .. tostring(remote))
		end
	end)
	task.spawn(buildGui)

	LocalPlayer.CharacterAdded:Connect(function(char)
		bindCharacter(char)
	end)
	LocalPlayer.CharacterRemoving:Connect(function()
		unbindCharacter()
	end)
	if LocalPlayer.Character then
		task.spawn(bindCharacter, LocalPlayer.Character)
	end
end

return MovementController
