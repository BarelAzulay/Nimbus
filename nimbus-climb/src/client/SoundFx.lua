-- SoundFx: UI sounds and background music (ARCHITECTURE_V3.md "Phase 5 build contract" 7.2 / 7.3).
-- Ids come from Config.Audio (`Music = { Lobby, Battle, Dungeon }`, `Sfx = { Click, Confirm, Error, Reward, Whoosh }`);
-- an empty id is silent and nothing breaks (the README tells the owner to paste free Creator Store audio ids).
--
--   SoundFx.Play(name)        one-shot Click / Confirm / Error / Reward / Whoosh at Sfx / 10 volume (pooled Sounds,
--                             a slight random pitch so repeats do not tire the ear); returns the Sound or nil
--   SoundFx.Music(context)    "Lobby" | "Battle" | "Dungeon" | nil: loops Config.Audio.Music[context] at Music / 10,
--                             1 s crossfade from the track before; nil fades the music out
--   SoundFx.Current()         -> the music context playing (or nil)
--   SoundFx.Volume(kind)      -> 0..1 for "Music" / "Sfx" (ClientSettings)
--
-- Settings changes apply at once (ClientSettings.Changed). Sounds live in SoundService (client-side, never replicated).
-- Plain Lua 5.1-compatible syntax only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local ClientSettings = require(script.Parent:WaitForChild("ClientSettings"))

local SoundFx = {}

local FADE = 1 -- seconds of the music crossfade
local POOL = 3 -- Sounds per sfx name
local NAMES = { "Click", "Confirm", "Error", "Reward", "Whoosh" }

local St = {
	Folder = nil,
	Pools = {}, -- [name] = { Sound, ... }
	Next = {}, -- [name] = next pool index
	Music = nil, -- the playing music Sound
	Context = nil,
	Hooked = false,
	Rng = Random.new(5),
}
SoundFx._St = St

local function audio()
	return type(Config.Audio) == "table" and Config.Audio or {}
end

local function idOf(group, name)
	local list = audio()[group]
	local id = type(list) == "table" and list[name] or nil
	if type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

function SoundFx.Volume(kind)
	local value = ClientSettings.Get(kind)
	if type(value) ~= "number" then
		return 0
	end
	return math.max(0, math.min(1, value / 10))
end

local function folder()
	if St.Folder and St.Folder.Parent then
		return St.Folder
	end
	local f = Instance.new("Folder")
	f.Name = "NimbusSounds"
	f.Parent = SoundService
	St.Folder = f
	return f
end

local function onChanged(key)
	if key == "Music" and St.Music then
		St.Music.Volume = SoundFx.Volume("Music")
	end
end

local function hook()
	if St.Hooked then
		return
	end
	St.Hooked = true
	ClientSettings.Changed:Connect(onChanged)
end

function SoundFx.Play(name)
	hook()
	local id = idOf("Sfx", name)
	if not id then
		return nil
	end
	local volume = SoundFx.Volume("Sfx")
	if volume <= 0 then
		return nil
	end
	local pool = St.Pools[name]
	if not pool then
		pool = {}
		for i = 1, POOL do
			local s = Instance.new("Sound")
			s.Name = "Sfx_" .. name .. "_" .. i
			s.SoundId = id
			s.Parent = folder()
			pool[i] = s
		end
		St.Pools[name] = pool
		St.Next[name] = 1
	end
	local index = St.Next[name] or 1
	St.Next[name] = index % #pool + 1
	local sound = pool[index]
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = 0.95 + St.Rng:NextNumber() * 0.1
	pcall(function()
		sound:Play()
	end)
	return sound
end

local function fadeOut(sound)
	if not sound then
		return
	end
	local tween = TweenService:Create(sound, TweenInfo.new(FADE), { Volume = 0 })
	tween.Completed:Connect(function()
		pcall(function()
			sound:Stop()
		end)
		sound:Destroy()
	end)
	tween:Play()
end

function SoundFx.Music(context)
	hook()
	if context == St.Context then
		return St.Music
	end
	St.Context = context
	local old = St.Music
	St.Music = nil
	fadeOut(old)
	local id = context and idOf("Music", context) or nil
	if not id then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "Music_" .. tostring(context)
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = folder()
	St.Music = sound
	pcall(function()
		sound:Play()
	end)
	TweenService:Create(sound, TweenInfo.new(FADE), { Volume = SoundFx.Volume("Music") }):Play()
	return sound
end

function SoundFx.Current()
	return St.Context
end

SoundFx.NAMES = NAMES

return SoundFx
