-- GraphicsQuality: the Graphics setting (ARCHITECTURE_V3.md "Phase 5 build contract" 7.2 / 7.3, 6.4).
--   "Auto"  Low when Roblox's own graphics slider (UserSettings().GameSettings.SavedQualityLevel) is at 1..3,
--           High otherwise (its "Automatic" position counts as High: most players never touch the slider)
--   "Low"   LightingStack.Push("GfxLow"): Bloom / SunRays / DepthOfField off, Terrain clouds Density capped at 0.4 (the
--           lower of 0.4 and the living sky's own density, LightingStack.Value without GfxLow, so the clouds still thin
--           at night on Low; client SkyController calls Recap after each sky refresh); every model
--           tagged NC_Detail (pure decor: LobbyBuilder / HomeBuilder / DungeonBuilder) is moved to a local holder
--           folder outside the workspace (client-side only) with its particle emitters / beams / trails disabled, also
--           decor that streams in later; the Sage Dragon is paused with SkyDragonController.SetHeld(true) (model out
--           of the workspace, RenderStepped loop off, kept across its mesh rebuild)
--   "High"  everything restored (the GfxLow preset popped, the decor and the dragon back where they were, emitters on
--           again exactly where they were on)
--
--   GraphicsQuality.Init()          reads ClientSettings.Gfx and follows ClientSettings.Changed
--   GraphicsQuality.Apply(setting)  "Auto" | "Low" | "High" (tests); -> the effective "Low" | "High"
--   GraphicsQuality.Effective()     -> "Low" | "High"
--   GraphicsQuality.Recap()         while Low: when the cloud cap moved Config.Sky.LowCloudStep or more, updates GfxLow's
--                                   cap in place (LightingStack.Update: no apply, so the sky's linear base tweens are never
--                                   cancelled or re-eased and no fade starts); the sky's next SetBase carries it
--   GraphicsQuality.Resolve(setting, savedLevel) -> "Low" | "High"  (pure; savedLevel = 0 Automatic, 1..10)
--
-- No per-frame work, no polling: CollectionService signals only. Plain Lua 5.1-compatible syntax only.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent
local ClientSettings = require(Client:WaitForChild("ClientSettings"))
local LightingStack = require(Client:WaitForChild("LightingStack"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local GraphicsQuality = {}

local DETAIL_TAG = "NC_Detail"
local PRESET_ID = "GfxLow"
local CLOUD_CAP = 0.4 -- Terrain clouds Density on Low never above this (nor above the sky's own)
local FADE = 0.5 -- seconds of the lighting change
local EMITTERS = { ParticleEmitter = true, Beam = true, Trail = true }

local St = {
	Mode = "High", -- the effective mode applied
	CloudDensity = nil, -- the cloud cap in the GfxLow preset pushed last
	Holder = nil, -- the local folder the hidden decor waits in
	Hidden = {}, -- [model] = original parent
	HiddenList = {}, -- models in the order they were hidden (restored in that order)
	Emitters = {}, -- [emitter] = true (an emitter WE turned off)
	Dragon = nil, -- true while Low holds the dragon (SetHeld); { Parent } on the fallback path
	Conns = {},
	Started = false,
}
GraphicsQuality._St = St

----------------------------------------------------------------------
-- Auto
----------------------------------------------------------------------

function GraphicsQuality.Resolve(setting, savedLevel)
	if setting == "Low" or setting == "High" then
		return setting
	end
	local level = tonumber(savedLevel)
	if level and level >= 1 and level <= 3 then
		return "Low"
	end
	return "High"
end

local function savedQualityLevel()
	local ok, level = pcall(function()
		local value = UserSettings().GameSettings.SavedQualityLevel
		if typeof(value) == "EnumItem" then
			return value.Value
		end
		return tonumber(value)
	end)
	if ok and type(level) == "number" then
		return level
	end
	return 0
end

----------------------------------------------------------------------
-- Decor
----------------------------------------------------------------------

local function holder()
	if St.Holder and St.Holder.Parent then
		return St.Holder
	end
	local f = Instance.new("Folder")
	f.Name = "NimbusGfxHidden"
	f.Parent = ReplicatedStorage
	St.Holder = f
	return f
end

local function setEmitters(root, on)
	local list = root:GetDescendants()
	list[#list + 1] = root
	for _, d in ipairs(list) do
		if EMITTERS[d.ClassName] then
			if on then
				if St.Emitters[d] then
					St.Emitters[d] = nil
					d.Enabled = true
				end
			elseif d.Enabled then
				St.Emitters[d] = true
				d.Enabled = false
			end
		end
	end
end

local function hide(inst)
	if St.Hidden[inst] or not inst.Parent or inst:IsDescendantOf(holder()) then
		return
	end
	-- a tagged part inside a tagged model moves with its model
	local parent = inst.Parent
	while parent and parent ~= game do
		if St.Hidden[parent] or CollectionService:HasTag(parent, DETAIL_TAG) then
			return
		end
		parent = parent.Parent
	end
	St.Hidden[inst] = inst.Parent
	St.HiddenList[#St.HiddenList + 1] = inst
	setEmitters(inst, false)
	inst.Parent = holder()
end

local function showAll()
	for _, inst in ipairs(St.HiddenList) do
		local parent = St.Hidden[inst]
		St.Hidden[inst] = nil
		if parent and parent.Parent and inst.Parent == St.Holder then
			inst.Parent = parent
			setEmitters(inst, true)
		end
	end
	St.HiddenList = {}
	St.Emitters = {}
end

local function dragonModule()
	local controllers = Client:FindFirstChild("Controllers")
	local module = controllers and controllers:FindFirstChild("SkyDragonController")
	if not module then
		return nil
	end
	local ok, mod = pcall(require, module)
	if ok and type(mod) == "table" then
		return mod
	end
	return nil
end

local function dragonModel(mod)
	if mod and type(mod.GetModel) == "function" then
		local okModel, model = pcall(mod.GetModel)
		if okModel and typeof(model) == "Instance" then
			return model
		end
	end
	return nil
end

-- Low pauses the Sage Dragon, High lets it fly again. The controller keeps the flag (SetHeld), so a dragon rebuilt
-- while Low (its mesh rebuild once the dragon keys load, _Rebuild) is built paused and High always finds the LIVE
-- model. Without SetHeld (an older controller): the current model is re-fetched every call and a write to a
-- destroyed model can never throw (Apply always reaches PetFx.SetQuality).
local function pauseDragon(on)
	local mod = dragonModule()
	if mod and type(mod.SetHeld) == "function" then
		St.Dragon = on and true or nil
		pcall(mod.SetHeld, on)
		return
	end
	local model = dragonModel(mod)
	if on then
		if model and model.Parent then
			local parent = model.Parent
			if pcall(function()
				model.Parent = nil
			end) then
				St.Dragon = { Parent = parent }
			end
		end
	elseif St.Dragon then
		local d = St.Dragon
		St.Dragon = nil
		if type(d) == "table" and model and model.Parent == nil and d.Parent and d.Parent.Parent then
			pcall(function()
				model.Parent = d.Parent
			end)
		end
	end
end

----------------------------------------------------------------------
-- Apply
----------------------------------------------------------------------

-- a fresh GfxLow preset: the cloud cap is the lower of CLOUD_CAP and what the sky shows under GfxLow right now
local function lowPreset()
	local density = CLOUD_CAP
	local ok, sky = pcall(LightingStack.Value, "Clouds", "Density", PRESET_ID)
	if ok and type(sky) == "number" and sky == sky then
		density = math.min(CLOUD_CAP, sky)
	end
	St.CloudDensity = density
	return {
		Bloom = { Enabled = false },
		SunRays = { Enabled = false },
		DepthOfField = { Enabled = false },
		Clouds = { Density = density },
	}
end

function GraphicsQuality.Apply(setting)
	local mode = GraphicsQuality.Resolve(setting, savedQualityLevel())
	if mode == "Low" then
		if St.Mode ~= "Low" then
			pcall(LightingStack.Push, PRESET_ID, lowPreset(), FADE)
		end
		St.Mode = "Low"
		for _, inst in ipairs(CollectionService:GetTagged(DETAIL_TAG)) do
			hide(inst)
		end
		pauseDragon(true)
		if not St.Conns.Added then
			St.Conns.Added = CollectionService:GetInstanceAddedSignal(DETAIL_TAG):Connect(function(inst)
				if St.Mode == "Low" then
					task.defer(hide, inst)
				end
			end)
		end
		-- the dragon is built a moment after the boot: catch it once it exists
		task.delay(3, function()
			if St.Mode == "Low" then
				pauseDragon(true)
			end
		end)
	else
		if St.Mode == "Low" then
			pcall(LightingStack.Pop, PRESET_ID, FADE)
		end
		St.Mode = "High"
		if St.Conns.Added then
			St.Conns.Added:Disconnect()
			St.Conns.Added = nil
		end
		showAll()
		pauseDragon(false)
	end
	-- Phase 6 (6.4 / A6): the evolved pets' particles follow the same switch (PetFx: Low = the soft light only)
	pcall(function()
		require(ReplicatedStorage.Shared.PetFx).SetQuality(St.Mode)
	end)
	return St.Mode
end

function GraphicsQuality.Effective()
	return St.Mode
end

-- the living sky moved (SkyController, after an applied refresh): while Low, update GfxLow's cloud cap when it moved at
-- least Config.Sky.LowCloudStep (a few times a loop: the night thins below 0.4 and back). In place, never a re-push: a
-- Push would cancel the SetBase tweens SkyController just started and restart them as an eased fade (Busy, so the
-- next refresh would skip); the cap rides the next refresh's linear SetBase instead (2 s later: the clouds move slowly)
function GraphicsQuality.Recap()
	if St.Mode ~= "Low" then
		return false
	end
	local ok, sky = pcall(LightingStack.Value, "Clouds", "Density", PRESET_ID)
	if not ok or type(sky) ~= "number" or sky ~= sky then
		return false
	end
	local step = (Config.Sky and Config.Sky.LowCloudStep) or 0.02
	if St.CloudDensity and math.abs(math.min(CLOUD_CAP, sky) - St.CloudDensity) < step then
		return false
	end
	local preset = lowPreset()
	local ok2, updated = pcall(LightingStack.Update, PRESET_ID, preset)
	if not (ok2 and updated) then
		pcall(LightingStack.Push, PRESET_ID, preset, FADE) -- GfxLow is not on the stack (never pushed): put it back
	end
	return true
end

function GraphicsQuality.Init()
	if St.Started then
		return
	end
	St.Started = true
	ClientSettings.Changed:Connect(function(key, value)
		if key == "Gfx" then
			GraphicsQuality.Apply(value)
		end
	end)
	GraphicsQuality.Apply(ClientSettings.Get("Gfx"))
end

return GraphicsQuality
