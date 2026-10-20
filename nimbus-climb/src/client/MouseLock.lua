-- MouseLock: the optional mouse lock (docs/dungeon-fixes/plan.md decision 6). With the setting MouseLock on (Settings
-- window "Mouse lock", or the L key) the cursor stays locked in the screen centre and the mouse turns the camera, like
-- Roblox's shift-lock without holding a key. Keyboard + mouse devices only: touch / gamepad-only devices are untouched.
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
-- the tutorial card (NimbusTutorial.TutorialPanel + its Main card shown; the folded bubble does not hold) and a focused
-- TextBox (chat). BattleController holds for its result card / LEAVE confirm itself (pcall'd require).
-- Plain Lua 5.1-compatible syntax only; task.* only.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MouseLock = {}

local K = {
	BIND = "NimbusMouseLock",
	KEY = Enum.KeyCode.L, -- the quick toggle (free: nothing in src/client binds L)
	KEY_NAME = "L",
}
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
	else
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

local WATCHERS = {
	NimbusLoading = watchLoading,
	NimbusNotify = watchNotify,
	NimbusTutorial = watchTutorial,
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
