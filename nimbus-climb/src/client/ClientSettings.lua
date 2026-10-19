-- ClientSettings: the player's settings on the client (ARCHITECTURE_V3.md "Phase 5 build contract" 7.2 / 7.3).
-- The saved values live in the profile (DataService, `Settings = { Music, Sfx, Gfx, Shake, SeenNotes }`) and arrive
-- through ProfileSync (State.Settings()); a change made here is applied locally AT ONCE (Changed fires) and sent to
-- the server with the remote SettingsSet(key, value) after a 0.4 s debounce (one send per key per burst of changes).
--
--   ClientSettings.Get(key)          -> the value (a local change first, then the synced profile, then the default)
--   ClientSettings.All()             -> { Music, Sfx, Gfx, Shake, SeenNotes } (a copy)
--   ClientSettings.Set(key, value)   -> bool  cleaned + clamped like the server does; false for junk / no change
--   ClientSettings.Changed           Util.Signal (key, value); fires on a local Set and when a sync changes a key
--   ClientSettings.Clean(key, value) -> value | nil   (the client copy of the server's validation)
--   ClientSettings.KEYS / DEFAULTS / DEBOUNCE
--
-- Plain Lua 5.1-compatible syntax only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ClientSettings = {}

ClientSettings.KEYS = { "Music", "Sfx", "Gfx", "Shake", "SeenNotes" }
ClientSettings.DEFAULTS = { Music = 6, Sfx = 8, Gfx = "Auto", Shake = true, SeenNotes = 0 }
ClientSettings.GFX = { "Auto", "Low", "High" }
ClientSettings.DEBOUNCE = 0.4
ClientSettings.Changed = Util.Signal()

local St = {
	Local = {}, -- [key] = value set on this client (wins over the synced value)
	Pending = {}, -- [key] = the debounce thread of an unsent change
	Synced = nil, -- the last State.Settings() seen
	State = nil, -- client/State (lazy; false when missing)
	Hooked = false,
}
ClientSettings._St = St

-- the server's rules (DataService.SetSetting): Music / Sfx whole 0..10, Gfx one of 3, Shake boolean, SeenNotes whole
-- 0..1000. Numbers are rounded and clamped here (a slider never sends 7.5); NaN / inf and wrong types give nil.
function ClientSettings.Clean(key, value)
	if key == "Music" or key == "Sfx" then
		if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
			return nil
		end
		return math.max(0, math.min(10, math.floor(value + 0.5)))
	elseif key == "SeenNotes" then
		if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
			return nil
		end
		return math.max(0, math.min(1000, math.floor(value + 0.5)))
	elseif key == "Gfx" then
		for _, name in ipairs(ClientSettings.GFX) do
			if value == name then
				return value
			end
		end
		return nil
	elseif key == "Shake" then
		if type(value) == "boolean" then
			return value
		end
		return nil
	end
	return nil
end

local function getState()
	if St.State == nil then
		St.State = false
		local client = script.Parent
		local module = client and client:FindFirstChild("State")
		if module then
			local ok, mod = pcall(require, module)
			if ok and type(mod) == "table" then
				St.State = mod
			end
		end
	end
	return St.State or nil
end

local function syncedSettings()
	local State = getState()
	if State and type(State.Settings) == "function" then
		local ok, settings = pcall(State.Settings)
		if ok and type(settings) == "table" then
			return settings
		end
	end
	return nil
end

-- a sync that changed a key the player did not just change here: adopt it and tell the listeners
local function onSynced(settings)
	if type(settings) ~= "table" then
		return
	end
	local old = St.Synced or {}
	St.Synced = settings
	for _, key in ipairs(ClientSettings.KEYS) do
		local value = ClientSettings.Clean(key, settings[key])
		if value ~= nil and value ~= old[key] and St.Pending[key] == nil then
			local before = ClientSettings.Get(key)
			St.Local[key] = nil
			if value ~= before then
				ClientSettings.Changed:Fire(key, value)
			end
		end
	end
end

local function hook()
	if St.Hooked then
		return
	end
	St.Hooked = true
	local State = getState()
	if State and State.SettingsChanged and type(State.SettingsChanged.Connect) == "function" then
		State.SettingsChanged:Connect(onSynced)
	end
	St.Synced = syncedSettings()
end

function ClientSettings.Get(key)
	hook()
	local value = St.Local[key]
	if value ~= nil then
		return value
	end
	local settings = syncedSettings()
	if settings then
		value = ClientSettings.Clean(key, settings[key])
		if value ~= nil then
			return value
		end
	end
	return ClientSettings.DEFAULTS[key]
end

function ClientSettings.All()
	local out = {}
	for _, key in ipairs(ClientSettings.KEYS) do
		out[key] = ClientSettings.Get(key)
	end
	return out
end

local function send(key)
	St.Pending[key] = nil
	local value = St.Local[key]
	if value == nil then
		return
	end
	local ok, remote = pcall(Remotes.Get, "SettingsSet")
	if ok and remote then
		pcall(function()
			remote:FireServer(key, value)
		end)
	end
end

function ClientSettings.Set(key, value)
	hook()
	if ClientSettings.DEFAULTS[key] == nil then
		return false
	end
	local clean = ClientSettings.Clean(key, value)
	if clean == nil then
		return false
	end
	if key == "SeenNotes" and clean < (ClientSettings.Get("SeenNotes") or 0) then
		return false -- SeenNotes only goes up (the server refuses less)
	end
	if clean == ClientSettings.Get(key) and St.Pending[key] == nil then
		return false
	end
	St.Local[key] = clean
	ClientSettings.Changed:Fire(key, clean)
	local pending = St.Pending[key]
	if pending then
		pcall(task.cancel, pending)
	end
	St.Pending[key] = task.delay(ClientSettings.DEBOUNCE, send, key)
	return true
end

return ClientSettings
