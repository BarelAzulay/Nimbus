-- LightingStack: client lighting presets per zone (ARCHITECTURE_V3.md "Phase 5 build contract" 6.4, C3).
-- The server writes Lighting once at boot (LightingService); every later mood change happens HERE, on the client,
-- as a stack of named presets, so two features never fight over Lighting (the dungeon darkening the world while
-- the Low graphics setting has bloom switched off, for example).
--
--   LightingStack.Push(id, preset, seconds)   push (or re-push: it moves to the top) a preset, tweened over `seconds`
--       preset = { Lighting = {...}, Atmosphere = {...}, ColorCorrection = {...}, Bloom = {...}, SunRays = {...},
--                  Clouds = {...}, DepthOfField = {...}, Sky = {...} }   (property name -> value per group)
--   LightingStack.Pop(id, seconds)            removes it and restores what is under it; an unknown id is a no-op
--   LightingStack.Top() -> id | nil           the topmost preset's id
--   LightingStack.Ids() -> { id, ... }        bottom to top (tests / debugging)
--
-- Rules: the first time any preset names a property, its current (replicated) value is snapshotted as the BASE;
-- the effective value of every property = the topmost preset that sets it, else the base. Numbers, Color3 and
-- other tweenable values are tweened (TweenService, client side); booleans / strings / enums switch at once.
-- A new Push / Pop cancels the running tween of each object first, so values never jump back. Missing instances
-- (no Atmosphere / Clouds on this client) are skipped quietly. No per-frame code, no connections.
-- Users: DungeonController ("Dungeon"), GraphicsQuality ("GfxLow"). Nothing else on the client writes Lighting.
-- Plain Lua 5.1-compatible syntax only.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

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

local stack = {} -- { { Id = id, Preset = preset }, ... } bottom -> top
local base = {} -- group -> { prop -> value } (the snapshot of the untouched values)
local tweens = {} -- group -> Tween (the running tween of that group's instance)
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

local function apply(seconds)
	seconds = tonumber(seconds) or 0
	for _, group in ipairs(GROUP_ORDER) do
		local b = base[group]
		local inst = b and GROUPS[group]()
		if inst then
			local running = tweens[group]
			if running then
				tweens[group] = nil
				pcall(function()
					running:Cancel()
				end)
			end
			local goals, any = {}, false
			for _, prop in ipairs(sortedKeys(b)) do
				local want = effective(group, prop)
				if want ~= nil then
					local okCur, current = pcall(function()
						return inst[prop]
					end)
					if not okCur or current ~= want then
						if seconds > 0 and TWEENABLE[typeof(want)] and okCur and typeof(current) == typeof(want) then
							goals[prop] = want
							any = true
						else
							setProp(inst, prop, want)
						end
					end
				end
			end
			if any then
				local ok, tween = pcall(function()
					return TweenService:Create(inst, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goals)
				end)
				if ok and tween then
					tweens[group] = tween
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
	apply(seconds)
end

function LightingStack.Pop(id, seconds)
	local i = indexOf(id)
	if not i then
		return
	end
	table.remove(stack, i)
	apply(seconds)
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
