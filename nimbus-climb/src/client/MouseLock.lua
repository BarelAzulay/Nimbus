-- MouseLock: the optional mouse lock (docs/dungeon-fixes/plan.md decision 6). With the setting MouseLock on (Settings
-- window "Mouse lock", or the L key) the cursor stays locked in the screen centre and the mouse turns the camera, like
-- Roblox's shift-lock without holding a key. Keyboard + mouse devices only: touch / gamepad-only devices are untouched.
-- Bug batch 2 #21: the setting defaults to ON (the game is played with E / F prompts); "Mouse lock (recommended)" in
-- Settings, OFF stays possible (not recommended), and a saved OFF is kept. The first lock of a session that lasts
-- HINT_DELAY shows a "press L to free the cursor" pill low on the screen for HINT_SECONDS (NimbusMouseLockHint).
--
--   MouseLock.Start()           idempotent; reads ClientSettings "MouseLock" and follows its Changed signal
--   MouseLock.SetEnabled(on)    turns the lock on / off on this client (not saved; the setting goes through ClientSettings)
--   MouseLock.IsEnabled()       -> bool  the lock is wanted (the setting / SetEnabled)
--   MouseLock.IsLocked()        -> bool  the cursor is locked now (enabled, no hold, keyboard + mouse, started)
--   MouseLock.Hold(reason)      frees the cursor until the matching Release; counted per reason (two Holds = two Releases)
--   MouseLock.Release(reason)   -> bool  false (and harmless) for a reason that holds nothing
--   MouseLock.Holds()           -> { [reason] = count }  a copy (tests, debugging)
--   MouseLock.WatchVisible(reason, guiObject)  holds while guiObject is Visible inside an Enabled ScreenGui in the game
--                               (NeonKit.Dock calls it for every docked window); released when hidden / removed / destroyed
--
-- While locked: ONE RenderStep binding ("NimbusMouseLock", Enum.RenderPriority.Camera.Value + 1, after the camera
-- scripts, which write MouseBehavior every frame) sets UserInputService.MouseBehavior = LockCenter. Unlocked: no
-- binding at all; on the change MouseBehavior = Default and MouseIconEnabled = true are written once.
-- Automatic holds: every NeonKit.Dock window while shown, the main menu (MainMenuController), the loading screen
-- (PlayerGui.NimbusLoading while it exists), NotifyController's result card (NimbusNotify attribute ResultCardLeft > 0),
-- the tutorial card (NimbusTutorial.TutorialPanel + its Main card shown; the folded bubble does not hold), a focused
-- TextBox (chat) and (bug batch 2 #21) the overlays that are not docked windows: MenuController's RouletteStage and
-- OddsPopup (NimbusMenu) and the NPC dialog card (NimbusNpcDialog.NpcDialog). BattleController holds for its result
-- card / LEAVE confirm itself (pcall'd require).
-- Plain Lua 5.1-compatible syntax only; task.* only.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MouseLock = {}

local K = {
	BIND = "NimbusMouseLock",
	KEY = Enum.KeyCode.L, -- the quick toggle (free: nothing in src/client binds L)
	KEY_NAME = "L",
	HINT_GUI = "NimbusMouseLockHint", -- the once-per-session "press L" pill (bug batch 2 #21)
	HINT_DELAY = 0.5, -- seconds the cursor must stay locked before the hint shows (no flash between two windows)
	HINT_SECONDS = 6,
}
MouseLock.HINT_GUI = K.HINT_GUI
MouseLock.KEY_NAME = K.KEY_NAME
MouseLock.BIND = K.BIND

local St = {
	Started = false,
	Enabled = false,
	Holds = {}, -- [reason] = count
	Flags = {}, -- [reason] = true: the automatic holds (one count each)
	Locked = false,
	Bound = false,
	Settings = nil, -- client/ClientSettings (lazy; false when missing)
	Watching = {}, -- [PlayerGui child name] = true (wired once per instance through Wired)
	Wired = setmetatable({}, { __mode = "k" }),
	Hinted = false, -- the "press L" hint was shown (or is pending) this session
	HintGui = nil,
}
MouseLock._St = St

local function priority()
	local ok, value = pcall(function()
		return Enum.RenderPriority.Camera.Value + 1
	end)
	return ok and value or 201
end

-- a keyboard + mouse device (a touch laptop with a keyboard and a mouse counts; a phone / a console does not)
local function desktop()
	local ok, yes = pcall(function()
		return UserInputService.KeyboardEnabled == true and UserInputService.MouseEnabled == true
	end)
	return ok and yes
end

local function step()
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
end

----------------------------------------------------------------------
-- the "press L" hint (bug batch 2 #21: the lock is on by default, so a new player must learn how to free the cursor
-- for the HUD buttons and side cards). Once per session, the first time the cursor stays locked for HINT_DELAY: a
-- small pill low on the screen (70% down) for HINT_SECONDS (ScreenGui "NimbusMouseLockHint"); gone at once on unlock.
----------------------------------------------------------------------
local function hideHint()
	local gui = St.HintGui
	St.HintGui = nil
	if gui then
		pcall(function()
			gui:Destroy()
		end)
	end
end

-- shared/Theme (optional here, no hard dependency): the Button font, ScaledSize, TextOutline (readability rule)
local function hintTheme()
	local ok, theme = pcall(function()
		local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
		local module = shared and shared:FindFirstChild("Theme")
		return module and require(module) or nil
	end)
	return (ok and type(theme) == "table") and theme or nil
end

local function showHint()
	if not St.Locked or St.HintGui then
		if not St.Locked then
			St.Hinted = false -- a lock that did not last: hint at the next one
		end
		return
	end
	local player = Players.LocalPlayer
	local pg = player and player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = K.HINT_GUI
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false -- (it carries text: v2 rule)
	gui.DisplayOrder = 5
	local label = Instance.new("TextLabel")
	label.Name = "Hint"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0.7) -- low, above the hotbar: never in the middle of the screen (v2 rule)
	local theme = hintTheme()
	local size = 20
	if theme then
		pcall(function()
			size = tonumber(theme.ScaledSize(20)) or 20
			label.Font = theme.Fonts.Button
		end)
	end
	label.TextSize = size
	label.Size = UDim2.fromOffset(0, math.floor(size * 2 + 0.5))
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundColor3 = Color3.fromRGB(18, 20, 40)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = "Mouse lock is ON  \194\183  press " .. K.KEY_NAME .. " to free the cursor"
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 18)
	pad.Parent = label
	if theme and type(theme.TextOutline) == "function" then
		pcall(theme.TextOutline, label)
	end
	label.Parent = gui
	gui.Parent = pg
	St.HintGui = gui
	-- short desktop windows: 70 % down would reach the HUD's bottom-centre vitals card (bug batch 2 #1), so the pill
	-- stands just above the card's top (NimbusHud attribute BottomCentreTop, same gui-area pixels: both keep the
	-- inset), but never up into the middle of the screen (the v2 rule's band ends at 64.5 % of the height)
	local hud = pg:FindFirstChild("NimbusHud")
	local top = hud and tonumber(hud:GetAttribute("BottomCentreTop"))
	local areaH = gui.AbsoluteSize.Y
	if top and top > 0 and areaH > 0 then
		local y = math.max(0.65 * areaH, math.min(0.7 * areaH, top - 8 - label.Size.Y.Offset))
		label.Position = UDim2.new(0.5, 0, 0, math.floor(y))
	end
	task.delay(K.HINT_SECONDS, function()
		if St.HintGui == gui then
			hideHint()
		end
	end)
end

local function update()
	if not St.Started then
		return
	end
	local want = St.Enabled and next(St.Holds) == nil and desktop()
	if want then
		if not St.Bound then
			local ok, err = pcall(function()
				RunService:BindToRenderStep(K.BIND, priority(), step)
			end)
			St.Bound = ok
			if not ok then
				warn("[MouseLock] BindToRenderStep failed: " .. tostring(err))
			end
		end
		-- the binding writes LockCenter on the next frame (a hold that comes and goes inside one frame never warps)
		St.Locked = St.Bound
		if St.Locked and not St.Hinted then
			St.Hinted = true
			task.delay(K.HINT_DELAY, showHint)
		end
	else
		hideHint()
		if St.Bound then
			pcall(function()
				RunService:UnbindFromRenderStep(K.BIND)
			end)
			St.Bound = false
		end
		if St.Locked then
			pcall(function()
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = true
			end)
		end
		St.Locked = false
	end
end

function MouseLock.IsEnabled()
	return St.Enabled
end

function MouseLock.IsLocked()
	return St.Locked
end

function MouseLock.SetEnabled(on)
	on = on == true
	if St.Enabled == on then
		return
	end
	St.Enabled = on
	update()
end

local function keyOf(reason)
	if reason == nil then
		return "?"
	end
	return tostring(reason)
end

function MouseLock.Hold(reason)
	local key = keyOf(reason)
	St.Holds[key] = (St.Holds[key] or 0) + 1
	update()
	return key
end

function MouseLock.Release(reason)
	local key = keyOf(reason)
	local n = St.Holds[key]
	if not n then
		return false
	end
	if n <= 1 then
		St.Holds[key] = nil
	else
		St.Holds[key] = n - 1
	end
	update()
	return true
end

function MouseLock.Holds()
	local out = {}
	for key, n in pairs(St.Holds) do
		out[key] = n
	end
	return out
end

-- an automatic hold: one count under `reason` while `on`
local function flag(reason, on)
	on = on == true
	if (St.Flags[reason] == true) == on then
		return
	end
	St.Flags[reason] = on or nil
	if on then
		MouseLock.Hold(reason)
	else
		MouseLock.Release(reason)
	end
end
MouseLock._flag = flag

----------------------------------------------------------------------
-- visibility watchers
----------------------------------------------------------------------
local function shownInGame(obj)
	if not obj or not obj.Parent or not obj.Visible then
		return false
	end
	local gui = obj:FindFirstAncestorOfClass("ScreenGui")
	if not gui or not gui.Enabled then
		return false
	end
	local ok, inGame = pcall(function()
		return gui:IsDescendantOf(game)
	end)
	return ok and inGame
end

local serial = 0

-- holds while `obj` is shown (Visible, in an Enabled ScreenGui, in the game); released on hide / removal / destroy
function MouseLock.WatchVisible(reason, obj)
	if not obj then
		return nil
	end
	serial = serial + 1
	local key = keyOf(reason) .. "#" .. serial
	local conns = {}
	local function refresh()
		flag(key, shownInGame(obj))
	end
	local function bindGui()
		if conns.Gui then
			conns.Gui:Disconnect()
			conns.Gui = nil
		end
		local gui = obj.Parent and obj:FindFirstAncestorOfClass("ScreenGui")
		if gui then
			conns.Gui = gui:GetPropertyChangedSignal("Enabled"):Connect(refresh)
		end
	end
	local function stop()
		for name, c in pairs(conns) do
			c:Disconnect()
			conns[name] = nil
		end
		flag(key, false)
	end
	conns.Visible = obj:GetPropertyChangedSignal("Visible"):Connect(refresh)
	conns.Ancestry = obj.AncestryChanged:Connect(function()
		bindGui()
		refresh()
	end)
	conns.Gone = obj.Destroying:Connect(stop)
	bindGui()
	refresh()
	return { Key = key, Stop = stop, Refresh = refresh }
end

-- PlayerGui watchers for screens owned by other controllers (no edits there): matched by name
local function watchLoading(gui)
	local key = "auto:Loading"
	flag(key, true)
	gui.AncestryChanged:Connect(function()
		if not gui.Parent then
			flag(key, false)
		end
	end)
	gui.Destroying:Connect(function()
		flag(key, false)
	end)
end

local function watchNotify(gui)
	local key = "auto:ResultCard"
	local function refresh()
		local left = gui:GetAttribute("ResultCardLeft")
		flag(key, gui.Parent ~= nil and gui.Enabled and type(left) == "number" and left > 0)
	end
	gui:GetAttributeChangedSignal("ResultCardLeft"):Connect(refresh)
	gui:GetPropertyChangedSignal("Enabled"):Connect(refresh)
	gui.AncestryChanged:Connect(refresh)
	gui.Destroying:Connect(function()
		flag(key, false)
	end)
	refresh()
end

-- the tutorial card: TutorialPanel (Visible while the card is out) > Slide > Main (Visible = not folded)
local function watchTutorial(gui)
	local key = "auto:Tutorial"
	local wired = {}
	local function find()
		local root = gui:FindFirstChild("TutorialPanel")
		local slide = root and root:FindFirstChild("Slide")
		local main = slide and slide:FindFirstChild("Main")
		return root, main
	end
	local function refresh()
		local root, main = find()
		flag(key, gui.Parent ~= nil and gui.Enabled and root ~= nil and root.Visible and main ~= nil and main.Visible)
	end
	local function wire()
		local root, main = find()
		for _, obj in ipairs({ root, main }) do
			if obj and not wired[obj] and obj:IsA("GuiObject") then
				wired[obj] = true
				obj:GetPropertyChangedSignal("Visible"):Connect(refresh)
			end
		end
		refresh()
	end
	gui.DescendantAdded:Connect(function(d)
		if d.Name == "TutorialPanel" or d.Name == "Slide" or d.Name == "Main" then
			wire()
		end
	end)
	gui:GetPropertyChangedSignal("Enabled"):Connect(refresh)
	gui.AncestryChanged:Connect(refresh)
	gui.Destroying:Connect(function()
		flag(key, false)
	end)
	wire()
end

-- overlays that are not NeonKit.Dock windows (bug batch 2 #21, the lock is on by default now): one hold under
-- "auto:<gui name>" while any of the named DIRECT children of the gui is Visible (they come and go: MenuController
-- builds the roulette stage / odds popup per show and destroys them after)
local function watchOverlays(names)
	local wanted = {}
	for _, name in ipairs(names) do
		wanted[name] = true
	end
	return function(gui)
		local key = "auto:" .. gui.Name
		local wired = setmetatable({}, { __mode = "k" })
		local function refresh()
			local on = false
			if gui.Parent ~= nil and gui.Enabled then
				for _, child in ipairs(gui:GetChildren()) do
					if wanted[child.Name] and child:IsA("GuiObject") and child.Visible then
						on = true
						break
					end
				end
			end
			flag(key, on)
		end
		local function wire(child)
			if wanted[child.Name] and child:IsA("GuiObject") and not wired[child] then
				wired[child] = true
				child:GetPropertyChangedSignal("Visible"):Connect(refresh)
			end
			refresh()
		end
		gui.ChildAdded:Connect(wire)
		gui.ChildRemoved:Connect(refresh)
		gui:GetPropertyChangedSignal("Enabled"):Connect(refresh)
		gui.AncestryChanged:Connect(refresh)
		gui.Destroying:Connect(function()
			flag(key, false)
		end)
		for _, child in ipairs(gui:GetChildren()) do
			wire(child)
		end
		refresh()
	end
end

local WATCHERS = {
	NimbusLoading = watchLoading,
	NimbusNotify = watchNotify,
	NimbusTutorial = watchTutorial,
	-- MenuController's full-screen roulette stage (the reveal's buttons) and the odds popup (inside NimbusMenu, not docked)
	NimbusMenu = watchOverlays({ "RouletteStage", "OddsPopup" }),
	-- NpcController's dialog card (Next / Close buttons), like the tutorial card
	NimbusNpcDialog = watchOverlays({ "NpcDialog" }),
}

local function watchChild(child)
	local fn = WATCHERS[child.Name]
	if fn and not St.Wired[child] and child:IsA("ScreenGui") then
		St.Wired[child] = true
		local ok, err = pcall(fn, child)
		if not ok then
			warn("[MouseLock] watcher " .. child.Name .. ": " .. tostring(err))
		end
	end
end

local function watchPlayerGui()
	local player = Players.LocalPlayer
	if not player then
		return
	end
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 30)
	if not pg then
		return
	end
	pg.ChildAdded:Connect(watchChild)
	for _, child in ipairs(pg:GetChildren()) do
		watchChild(child)
	end
end

----------------------------------------------------------------------
-- start
----------------------------------------------------------------------
local function settings()
	if St.Settings == nil then
		St.Settings = false
		local module = script.Parent and script.Parent:FindFirstChild("ClientSettings")
		if module then
			local ok, mod = pcall(require, module)
			if ok and type(mod) == "table" then
				St.Settings = mod
			end
		end
	end
	return St.Settings or nil
end

local function toggle()
	local cs = settings()
	if cs and type(cs.Set) == "function" then
		local ok, changed = pcall(cs.Set, "MouseLock", not St.Enabled)
		if ok and changed then
			return -- Changed fires -> SetEnabled
		end
	end
	MouseLock.SetEnabled(not St.Enabled)
end
MouseLock._toggle = toggle

function MouseLock.Start()
	if St.Started then
		return
	end
	St.Started = true
	local cs = settings()
	if cs then
		local ok, value = pcall(cs.Get, "MouseLock")
		St.Enabled = ok and value == true
		if cs.Changed and type(cs.Changed.Connect) == "function" then
			cs.Changed:Connect(function(key, value2)
				if key == "MouseLock" then
					MouseLock.SetEnabled(value2 == true)
				end
			end)
		end
	end
	for _, prop in ipairs({ "KeyboardEnabled", "MouseEnabled" }) do
		pcall(function()
			UserInputService:GetPropertyChangedSignal(prop):Connect(update)
		end)
	end
	UserInputService.TextBoxFocused:Connect(function()
		flag("auto:TextBox", true)
	end)
	UserInputService.TextBoxFocusReleased:Connect(function()
		flag("auto:TextBox", false)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input and input.KeyCode == K.KEY and desktop() then
			toggle()
		end
	end)
	task.spawn(watchPlayerGui) -- runs at once up to its first yield: the screens up now hold before the first update
	update()
end

return MouseLock
