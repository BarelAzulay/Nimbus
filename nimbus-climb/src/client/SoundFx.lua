-- SoundFx: UI sounds, background music and the positional loops (ARCHITECTURE_V3.md "Phase 5 build contract" 7.2 / 7.3;
-- the original audio: Config.Audio, shared/AudioIds.lua written by tools/upload_assets.py --audio).
-- Ids come from Config.Audio (`Music = { Lobby, Battle, Dungeon }`, `Sfx = { Click, Confirm, Error, Reward, Whoosh,
-- Inhale, Shatter }`, `Ambient = { CrowdCheer, DrumLoop }`: AudioIds numbers). A missing id is silent and nothing breaks:
-- no Sound is made, nothing is warned.
--
--   SoundFx.Play(name)        one-shot (any NAMES entry) at its slot volume x the Sfx setting (pooled Sounds, a slight
--                             random pitch so repeats do not tire the ear); returns the Sound or nil
--   SoundFx.Music(context)    "Lobby" | "Battle" | "Dungeon" | nil: loops Config.Audio.Music[context] at its slot volume x
--                             the Music setting, Config.Audio.Fade crossfade from the track before (Lobby / Dungeon resume
--                             where they stopped); nil fades the music out
--   SoundFx.SetLayer(name, on) the game state's music: "Battle" (BattleController) over "Dungeon" (DungeonController) over
--                             the base "Lobby"; plays the top layer that is on -> the context
--   SoundFx.Positional(name, parent, opts) -> Sound | nil   a looped 3D Sound of Ambient[name] (or any NAMES entry) in
--                             `parent` (a BasePart or an Attachment): RollOffMode InverseTapered, Config.Audio.Positional
--                             Min / Max studs (opts.Min / opts.Max win), slot volume x its setting; follows the settings
--   SoundFx.Current()         -> the music context playing (or nil)
--   SoundFx.Volume(kind)      -> 0..1 for "Music" / "Sfx" (ClientSettings)
--   SoundFx.SlotVolume(name, group) -> 0..1: Config.Audio.Volume[key] x the setting that key follows
--   SoundFx.Id(group, name)   -> "rbxassetid://<id>" | nil
--
-- Settings changes apply at once (ClientSettings.Changed) to the music and every positional loop. Sounds live in
-- SoundService (music, one-shots) or in their world part (positional); all client-side, never replicated.
-- Plain Lua 5.1-compatible syntax only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local ClientSettings = require(script.Parent:WaitForChild("ClientSettings"))

local SoundFx = {}

local POOL = 3 -- Sounds per sfx name
local NAMES = { "Click", "Confirm", "Error", "Reward", "Whoosh", "Inhale", "Shatter", "CrowdCheer", "DrumLoop" }
local LAYERS = { "Battle", "Dungeon" } -- SetLayer priority (first on wins); none on = BASE
local BASE = "Lobby"

local St = {
	Folder = nil,
	Pools = {}, -- [name] = { Sound, ... }
	Next = {}, -- [name] = next pool index
	Music = nil, -- the playing music Sound
	FadeIn = nil, -- its fade-in Tween while it runs (a settings change cancels it: the new volume wins)
	Context = nil,
	Layers = {}, -- [layer] = true while on
	Pos = {}, -- [context] = TimePosition when it faded out (Config.Audio.Resume)
	Loops = {}, -- [Sound] = { name, group } (positional loops: the settings follow them)
	Hooked = false,
	Rng = Random.new(5),
}
SoundFx._St = St

local function audio()
	return type(Config.Audio) == "table" and Config.Audio or {}
end

-- the group a name lives in ("Sfx" first: Play("CrowdCheer") finds it in Ambient)
local function groupOf(name)
	for _, group in ipairs({ "Sfx", "Ambient", "Music" }) do
		local keys = type(audio().Keys) == "table" and audio().Keys[group] or nil
		if type(keys) == "table" and keys[name] ~= nil then
			return group
		end
	end
	return "Sfx"
end

-- -> "rbxassetid://<id>" for an AudioIds number (Config.Audio), nil while it has no id. A non-empty string id is
-- taken as it is (the tools' drivers give one).
function SoundFx.Id(group, name)
	local list = audio()[group]
	local id = type(list) == "table" and list[name] or nil
	if type(id) == "number" and id > 0 and id == math.floor(id) then
		local digits = string.format("%d", id) -- (never tostring: a 15-digit id must not print as 1.2e+14)
		return "rbxassetid://" .. digits
	end
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

-- the AudioIds key of a name in its group (Config.Audio.Keys), the name itself when unlisted
local function keyOf(group, name)
	local keys = type(audio().Keys) == "table" and audio().Keys[group] or nil
	local key = type(keys) == "table" and keys[name] or nil
	return type(key) == "string" and key or name
end

local function settingOf(group, name)
	local map = type(audio().Setting) == "table" and audio().Setting or {}
	local s = map[keyOf(group, name)]
	if s == "Music" or s == "Sfx" then
		return s
	end
	return group == "Music" and "Music" or "Sfx"
end

function SoundFx.SlotVolume(name, group)
	group = group or groupOf(name)
	local volumes = type(audio().Volume) == "table" and audio().Volume or {}
	local slot = tonumber(volumes[keyOf(group, name)]) or 1
	return math.max(0, math.min(1, slot)) * SoundFx.Volume(settingOf(group, name))
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
	if key ~= "Music" and key ~= "Sfx" then
		return
	end
	if key == "Music" and St.Music and St.Context then
		if St.FadeIn then
			pcall(function()
				St.FadeIn:Cancel() -- (else the fade-in would still end on the volume of the old setting)
			end)
			St.FadeIn = nil
		end
		St.Music.Volume = SoundFx.SlotVolume(St.Context, "Music")
	end
	for sound, rec in pairs(St.Loops) do
		if not sound.Parent then
			St.Loops[sound] = nil
		elseif settingOf(rec.group, rec.name) == key then
			sound.Volume = SoundFx.SlotVolume(rec.name, rec.group)
		end
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
	local group = groupOf(name)
	local id = SoundFx.Id(group, name)
	if not id then
		return nil
	end
	local volume = SoundFx.SlotVolume(name, group)
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

local function fade()
	return math.max(0, tonumber(audio().Fade) or 1)
end

local function fadeOut(sound, context)
	if not sound then
		return
	end
	local resume = type(audio().Resume) == "table" and audio().Resume or {}
	if context and resume[context] then
		St.Pos[context] = sound.TimePosition
	end
	local tween = TweenService:Create(sound, TweenInfo.new(fade()), { Volume = 0 })
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
	local oldContext = St.Context
	St.Context = context
	local old = St.Music
	St.Music = nil
	St.FadeIn = nil
	fadeOut(old, oldContext)
	local id = context and SoundFx.Id("Music", context) or nil
	if not id then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "Music_" .. tostring(context)
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = 0
	sound.TimePosition = St.Pos[context] or 0
	sound.Parent = folder()
	St.Music = sound
	pcall(function()
		sound:Play()
	end)
	local tween = TweenService:Create(sound, TweenInfo.new(fade()), { Volume = SoundFx.SlotVolume(context, "Music") })
	St.FadeIn = tween
	tween.Completed:Connect(function()
		if St.FadeIn == tween then
			St.FadeIn = nil
		end
	end)
	tween:Play()
	return sound
end

-- the context the layers ask for: the first LAYERS entry that is on, else BASE
function SoundFx.Wanted()
	for _, layer in ipairs(LAYERS) do
		if St.Layers[layer] then
			return layer
		end
	end
	return BASE
end

function SoundFx.SetLayer(name, on)
	if type(name) ~= "string" then
		return St.Music
	end
	St.Layers[name] = on and true or nil
	return SoundFx.Music(SoundFx.Wanted())
end

function SoundFx.Positional(name, parent, opts)
	hook()
	if typeof(parent) ~= "Instance" or not (parent:IsA("BasePart") or parent:IsA("Attachment")) then
		return nil
	end
	local group = groupOf(name)
	local id = SoundFx.Id(group, name)
	if not id then
		return nil
	end
	opts = type(opts) == "table" and opts or {}
	local ranges = type(audio().Positional) == "table" and audio().Positional[keyOf(group, name)] or nil
	ranges = type(ranges) == "table" and ranges or {}
	local minD = tonumber(opts.Min) or tonumber(ranges.Min) or 20
	local maxD = tonumber(opts.Max) or tonumber(ranges.Max) or 100
	local sound = Instance.new("Sound")
	sound.Name = opts.Name or ("Loop_" .. name)
	sound.SoundId = id
	sound.Looped = true
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = math.max(1, minD)
	sound.RollOffMaxDistance = math.max(minD + 1, maxD)
	sound.Volume = SoundFx.SlotVolume(name, group)
	sound.Parent = parent
	St.Loops[sound] = { name = name, group = group }
	sound.AncestryChanged:Connect(function()
		if not sound.Parent then
			St.Loops[sound] = nil
		end
	end)
	pcall(function()
		sound:Play()
	end)
	return sound
end

function SoundFx.Current()
	return St.Context
end

SoundFx.NAMES = NAMES
SoundFx.LAYERS = LAYERS

return SoundFx
