-- ClientSettings: the player's settings on the client (ARCHITECTURE_V3.md "Phase 5 build contract" 7.2 / 7.3).
-- The saved values live in the profile (DataService, `Settings = { Music, Sfx, Gfx, Shake, SeenNotes, MouseLock }`) and
-- arrive through ProfileSync (State.Settings(); a key State does not know yet, like MouseLock, is read from the raw
-- ProfileSync payload, see rawSync); a change made here is applied locally AT ONCE (Changed fires) and sent to
-- the server with the remote SettingsSet(key, value) after a 0.4 s debounce (one send per key per burst of changes).
--
--   ClientSettings.Get(key)          -> the value (a local change first, then the synced profile, then the default)
--   ClientSettings.All()             -> { Music, Sfx, Gfx, Shake, SeenNotes, MouseLock } (a copy)
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

ClientSettings.KEYS = { "Music", "Sfx", "Gfx", "Shake", "SeenNotes", "MouseLock" }
ClientSettings.DEFAULTS = { Music = 6, Sfx = 8, Gfx = "Auto", Shake = true, SeenNotes = 0, MouseLock = true }
ClientSettings.GFX = { "Auto", "Low", "High" }
ClientSettings.DEBOUNCE = 0.4
ClientSettings.Changed = Util.Signal()

local St = {
	Local = {}, -- [key] = value set on this client (wins over the synced value)
	Pending = {}, -- [key] = the debounce thread of an unsent change
	Synced = nil, -- the last synced settings seen (State.Settings() + the raw keys State does not carry)
	Raw = nil, -- the Settings table of the last raw ProfileSync payload (see rawSync)
	RawHooked = false,
	State = nil, -- client/State (lazy; false when missing)
	Hooked = false,
}
ClientSettings._St = St

-- the server's rules (DataService.SetSetting): Music / Sfx whole 0..10, Gfx one of 3, Shake / MouseLock boolean,
-- SeenNotes whole 0..1000. Numbers are rounded and clamped here (a slider never sends 7.5); NaN / inf and wrong types give nil.
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
	elseif key == "Shake" or key == "MouseLock" then
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

local function stateSettings()
	local State = getState()
	if State and type(State.Settings) == "function" then
		local ok, settings = pcall(State.Settings)
		if ok and type(settings) == "table" then
			return settings
		end
	end
	return nil
end

-- State's settings, with the keys it does not carry (an older State.lua drops MouseLock) taken from the raw payload
local function syncedSettings()
	local settings = stateSettings()
	local raw = St.Raw
	if not raw then
		return settings
	end
	local out = {}
	for _, key in ipairs(ClientSettings.KEYS) do
		local value = settings and settings[key]
		if value == nil then
			value = raw[key]
		end
		out[key] = value
	end
	return out
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
			-- the value the listeners saw so far (St.Synced is the new table already, so not ClientSettings.Get)
			local before = St.Local[key]
			if before == nil then
				before = ClientSettings.Clean(key, old[key])
				if before == nil then
					before = ClientSettings.DEFAULTS[key]
				end
			end
			St.Local[key] = nil
			if value ~= before then
				ClientSettings.Changed:Fire(key, value)
			end
		end
	end
end

-- the raw ProfileSync payload (a second listener next to State's): keeps the keys State.lua does not know
local function rawSync()
	if St.RawHooked then
		return
	end
	St.RawHooked = true
	task.spawn(function()
		local ok, remote = pcall(Remotes.Get, "ProfileSync")
		if not (ok and remote and remote.OnClientEvent) then
			return
		end
		remote.OnClientEvent:Connect(function(snapshot)
			if type(snapshot) == "table" then
				St.Raw = type(snapshot.Settings) == "table" and snapshot.Settings or {} -- none: the defaults (like State)
				onSynced(syncedSettings())
			end
		end)
	end)
end

local function hook()
	if St.Hooked then
		return
	end
	St.Hooked = true
	local State = getState()
	if State and State.SettingsChanged and type(State.SettingsChanged.Connect) == "function" then
		State.SettingsChanged:Connect(function()
			onSynced(syncedSettings())
		end)
	end
	St.Synced = syncedSettings()
	rawSync()
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
