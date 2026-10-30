-- LightingStack: client lighting presets per zone (ARCHITECTURE_V3.md "Phase 5 build contract" 6.4, C3).
-- The server writes Lighting once at boot (LightingService); every later mood change happens HERE, on the client,
-- as a stack of named presets, so two features never fight over Lighting (the dungeon darkening the world while
-- the Low graphics setting has bloom switched off, for example).
--
--   LightingStack.Push(id, preset, seconds)   push (or re-push: it moves to the top) a preset, tweened over `seconds`
--       preset = { Lighting = {...}, Atmosphere = {...}, ColorCorrection = {...}, Bloom = {...}, SunRays = {...},
--                  Clouds = {...}, DepthOfField = {...}, Sky = {...} }   (property name -> value per group)
--   LightingStack.Pop(id, seconds)            removes it and restores what is under it; an unknown id is a no-op
--   LightingStack.Value(group, prop, skipId) -> value | nil   what group.prop is without preset skipId (the topmost
--       other preset that sets it, else the base, else the instance's current value)
--   LightingStack.Top() -> id | nil           the topmost preset's id
--   LightingStack.Ids() -> { id, ... }        bottom to top (tests / debugging)
--   LightingStack.SetBase(preset, seconds, instant)   MOVES the base (the living sky): every group.prop `preset` names
--       becomes the new base value (an unseen property is snapshotted first), then the stack re-applies over `seconds`,
--       so the presets above keep winning and a Pop lands on the moved base, not on the boot value. instant (optional)
--       = { group = { prop = true } }: those are set at once in this apply (the sky's clock jump at a phase change);
--       asked while Busy they wait for the next apply, whichever it is
--   LightingStack.Busy() -> boolean           a tween started by Push / Pop (a preset fading in or out) still runs
--   LightingStack.Update(id, preset) -> boolean   replaces the values of a preset already on the stack IN PLACE (its
--       position kept) and applies NOTHING: no running tween is cancelled or re-eased, Busy() is untouched; the next
--       apply (the sky's next SetBase, or any Push / Pop) carries them. false (and no change) when id is not on the stack
--       (GraphicsQuality.Recap: the GfxLow cloud cap follows the sky without restarting the sky's linear tweens)
--
-- Rules: the first time any preset names a property, its current (replicated) value is snapshotted as the BASE;
-- the effective value of every property = the topmost preset that sets it, else the base. The base is no longer
-- fixed: SkyController (the day / night cycle and the raid skies, every Config.Sky.Cycle.Refresh s) is its only
-- writer, through SetBase. A SetBase while Busy only stores the values and applies nothing, so the Dungeon fade is
-- never cancelled or restarted; the next refresh after the fade applies them. Numbers, Color3 and
-- other tweenable values are tweened (TweenService, client side); booleans / strings / enums switch at once, and so
-- do the whole-number properties of shared/SkyCycle.Integer (StarCount) from any preset or the base.
-- A new Push / Pop cancels the running tween of each object first, so values never jump back. Missing instances
-- (no Atmosphere / Clouds on this client) are skipped quietly. No per-frame code, no connections.
-- Users: DungeonController ("Dungeon"), GraphicsQuality ("GfxLow"), BattleController ("AttackFxDim": a signature's
-- brief battle dim, Task 11 of the pet attack VFX), SkyController (SetBase, and "SkyLift": the night battle lift).
-- Nothing else on the client writes Lighting.
-- Plain Lua 5.1-compatible syntax only.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkyCycle = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SkyCycle"))

local LightingStack = {}

-- group name -> function() -> Instance | nil (resolved on every apply: cheap, and survives a replaced instance)
local GROUPS = {
	Lighting = function()
		return Lighting
	end,
	Atmosphere = function()
		return Lighting:FindFirstChildOfClass("Atmosphere")
	end,
	ColorCorrection = function()
		return Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	end,
	Bloom = function()
		return Lighting:FindFirstChildOfClass("BloomEffect")
	end,
	SunRays = function()
		return Lighting:FindFirstChildOfClass("SunRaysEffect")
	end,
	DepthOfField = function()
		return Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	end,
	Sky = function()
		return Lighting:FindFirstChildOfClass("Sky")
	end,
	Clouds = function()
		local terrain = Workspace:FindFirstChildOfClass("Terrain")
		return terrain and terrain:FindFirstChildOfClass("Clouds") or nil
	end,
}
-- a fixed order, so applying never depends on pairs() order
local GROUP_ORDER = { "Lighting", "Atmosphere", "ColorCorrection", "Bloom", "SunRays", "DepthOfField", "Sky", "Clouds" }

local TWEENABLE = { number = true, Color3 = true, Vector3 = true, Vector2 = true, UDim2 = true, CFrame = true }
local INTEGER = SkyCycle.Integer -- prop name -> true: whole numbers, never tweened

local stack = {} -- { { Id = id, Preset = preset }, ... } bottom -> top
local base = {} -- group -> { prop -> value } (the snapshot of the untouched values)
local tweens = {} -- group -> Tween (the running tween of that group's instance)
local fades = {} -- group -> Tween started by Push / Pop (Busy() while one still plays; SetBase tweens are not here)
local instantNext = {} -- group -> { prop -> true }: set at once by the next apply (SetBase's instant set)
local warned = {}

local function warnOnce(key, text)
	if not warned[key] then
		warned[key] = true
		warn("[LightingStack] " .. text)
	end
end

local function indexOf(id)
	for i = 1, #stack do
		if stack[i].Id == id then
			return i
		end
	end
	return nil
end

-- sorted property names of a table (deterministic iteration)
local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		if type(k) == "string" then
			keys[#keys + 1] = k
		end
	end
	table.sort(keys)
	return keys
end

-- record the base value of every property `preset` names that has no base yet
local function snapshot(preset)
	for _, group in ipairs(GROUP_ORDER) do
		local props = preset[group]
		if type(props) == "table" then
			local inst = GROUPS[group]()
			if inst then
				local b = base[group]
				if not b then
					b = {}
					base[group] = b
				end
				for _, prop in ipairs(sortedKeys(props)) do
					if b[prop] == nil then
						local ok, value = pcall(function()
							return inst[prop]
						end)
						if ok and value ~= nil then
							b[prop] = value
						else
							warnOnce(group .. "." .. prop, "unknown property " .. group .. "." .. prop .. " (ignored)")
						end
					end
				end
			end
		end
	end
end

-- the effective value of group.prop: the topmost preset that sets it, else the base
local function effective(group, prop)
	for i = #stack, 1, -1 do
		local props = stack[i].Preset[group]
		if type(props) == "table" and props[prop] ~= nil then
			return props[prop]
		end
	end
	return base[group] and base[group][prop]
end

local function setProp(inst, prop, value)
	pcall(function()
		inst[prop] = value
	end)
end

-- `fade` = this apply comes from Push / Pop (its tweens make Busy() true)
local function apply(seconds, fade)
	seconds = tonumber(seconds) or 0
	local instant = instantNext
	instantNext = {}
	for _, group in ipairs(GROUP_ORDER) do
		local b = base[group]
		local inst = b and GROUPS[group]()
		if inst then
			local running = tweens[group]
			fades[group] = nil
			if running then
				tweens[group] = nil
				pcall(function()
					running:Cancel()
				end)
			end
			local goals, any = {}, false
			local now = instant[group] or {}
			for _, prop in ipairs(sortedKeys(b)) do
				local want = effective(group, prop)
				if want ~= nil then
					local okCur, current = pcall(function()
						return inst[prop]
					end)
					if not okCur or current ~= want then
						if seconds > 0 and TWEENABLE[typeof(want)] and okCur and typeof(current) == typeof(want) and not INTEGER[prop] and not now[prop] then
							goals[prop] = want
							any = true
						else
							setProp(inst, prop, want)
						end
					end
				end
			end
			if any then
				-- a Push / Pop fade eases in and out; the sky's SetBase steps are linear, so back-to-back refreshes
				-- (a new 2 s step every 2 s) join into one steady drift instead of a pulse every step
				local style = fade and Enum.EasingStyle.Sine or Enum.EasingStyle.Linear
				local ok, tween = pcall(function()
					return TweenService:Create(inst, TweenInfo.new(seconds, style, Enum.EasingDirection.InOut), goals)
				end)
				if ok and tween then
					tweens[group] = tween
					if fade then
						fades[group] = tween
					end
					tween:Play()
				else
					for prop, value in pairs(goals) do
						setProp(inst, prop, value)
					end
				end
			end
		end
	end
end

function LightingStack.Push(id, preset, seconds)
	if type(id) ~= "string" or id == "" or type(preset) ~= "table" then
		warnOnce("badpush", "Push needs a string id and a preset table")
		return
	end
	for key in pairs(preset) do
		if not GROUPS[key] then
			warnOnce("group." .. tostring(key), "unknown preset group " .. tostring(key) .. " (ignored)")
		end
	end
	snapshot(preset)
	local i = indexOf(id)
	if i then
		table.remove(stack, i)
	end
	stack[#stack + 1] = { Id = id, Preset = preset }
	apply(seconds, true)
end

function LightingStack.Pop(id, seconds)
	local i = indexOf(id)
	if not i then
		return
	end
	table.remove(stack, i)
	apply(seconds, true)
end

function LightingStack.Update(id, preset)
	local i = indexOf(id)
	if not i or type(preset) ~= "table" then
		return false
	end
	snapshot(preset)
	stack[i].Preset = preset
	return true
end

-- a Push / Pop fade still plays (a finished or cancelled tween is dropped here)
function LightingStack.Busy()
	local busy = false
	for _, group in ipairs(GROUP_ORDER) do
		local tween = fades[group]
		if tween then
			local ok, state = pcall(function()
				return tween.PlaybackState
			end)
			if ok and (state == Enum.PlaybackState.Playing or state == Enum.PlaybackState.Delayed) then
				busy = true
			else
				fades[group] = nil
			end
		end
	end
	return busy
end

-- the base moves (SkyController): only properties whose instance exists and that read back (snapshot) take a value;
-- unknown groups are ignored here (SkyController only names the known ones), junk is a no-op
function LightingStack.SetBase(preset, seconds, instant)
	if type(preset) ~= "table" then
		return
	end
	snapshot(preset)
	if type(instant) == "table" then
		for group, props in pairs(instant) do
			if GROUPS[group] and type(props) == "table" then
				local set = instantNext[group] or {}
				for prop, on in pairs(props) do
					if on == true and type(prop) == "string" then
						set[prop] = true
					end
				end
				instantNext[group] = set
			end
		end
	end
	for _, group in ipairs(GROUP_ORDER) do
		local props, b = preset[group], base[group]
		if type(props) == "table" and b then
			for _, prop in ipairs(sortedKeys(props)) do
				if b[prop] ~= nil and props[prop] ~= nil then
					b[prop] = props[prop]
				end
			end
		end
	end
	if not LightingStack.Busy() then
		apply(seconds, false)
	end
end

-- the value group.prop has (or comes back to) without preset `skipId`: the topmost OTHER preset that sets it, else
-- the base, else the instance's current value (no preset ever named it). nil when the group's instance is missing.
-- A preset made relative to the look under it (BattleController's battle dim: darker than whatever the dungeon /
-- the arena shows) reads it here, so a re-push never dims what it already dimmed, and a running tween never leaks in
function LightingStack.Value(group, prop, skipId)
	for i = #stack, 1, -1 do
		local entry = stack[i]
		local props = entry.Id ~= skipId and entry.Preset[group]
		if type(props) == "table" and props[prop] ~= nil then
			return props[prop]
		end
	end
	if base[group] and base[group][prop] ~= nil then
		return base[group][prop]
	end
	local get = GROUPS[group]
	local inst = get and get()
	if not inst then
		return nil
	end
	local ok, value = pcall(function()
		return inst[prop]
	end)
	return ok and value or nil
end

function LightingStack.Top()
	local top = stack[#stack]
	return top and top.Id or nil
end

function LightingStack.Ids()
	local out = {}
	for i = 1, #stack do
		out[i] = stack[i].Id
	end
	return out
end

return LightingStack
