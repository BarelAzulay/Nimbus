-- Nimbus Climb client bootstrap (LocalScript).
--
-- 1. State.Init() (the client mirror of the saved profile: pets, items, stats) starts first.
-- 2. Then every client controller is required and initialised, in the order listed below.
--
-- Each step runs in its own thread inside pcall: controllers wait for remotes and GUIs inside Init, and one
-- slow, broken or missing controller must never delay or take down the others. A failure only logs a
-- warning. Threads are started in the order listed here, and task.spawn runs a new thread immediately until
-- it first yields, so State.Init() has already registered itself before the first controller starts.
-- The loading screen (src/first/LoadingScreen.client.lua) runs from ReplicatedFirst before this script.
-- Plain Lua 5.1-compatible syntax only.

local CONTROLLER_NAMES = {
	"MovementController",
	"MainMenuController", -- Phase 5 (7.2): gates every other ScreenGui until PLAY; the server holds the character meanwhile
	"HudController",
	"DamageFx",
	"NotifyController",
	"MenuController",
	"HotbarController",
	"PetController",
	"TokenFx",
	-- v3 (ARCHITECTURE_V3.md)
	"SkyDragonController",
	"IndexController",
	"NpcController",
	"TutorialController",
	"ShowcaseController",
	"DevController",
	"DevPetShow", -- the developer pet showcase (/pet, /pets, /evolve; client/Controllers/EvolutionFx.lua)
	-- Phase 2
	"HomeFx",
	"FusionController",
	-- Phase 3
	"BattleController",
	"ArenaController",
	-- Phase 4 (ARCHITECTURE_V3.md "Phase 4 build contract")
	"CareController", -- Food Machine feed list, garden picker, Training Place window, the EVOLVE moment
	"HomePortalFx", -- the home portal and the arrival ring
	-- Phase 5 (ARCHITECTURE_V3.md "Phase 5 build contract" 5.6, 6.3)
	"DungeonController", -- the Dungeon window, run cards, chest prompt, the dungeon lighting preset
	"ObbyController", -- the obby level picker at the Obby gate
	-- bug #13
	"FountainFx", -- the lobby fountain's paper boat (and its water loop when Config.Audio.Ambient.Fountain is set)
	-- bug #12
	"MeadowFx", -- the lobby's grass and wildflowers (grown here from the server's scatter) and their wind sway
	-- bug #11
	"RingCrowdFx", -- the Champion Ring's sky-sailor crowd: the drum beat, cheers, caps, bell, flags (animation only; sounds: audio branch)
	-- bug #5
	"DungeonFx", -- the dungeon's turning parts (the Weatherworks' astrolabe rings over the boss chair)
	-- the original audio (Config.Audio): the Champion Ring's crowd + drums as positional loops
	"RingAmbience",
}

local TAG = "[NimbusClimb] "

-- Newer controllers that a build may not contain yet: skip them quietly when absent.
local OPTIONAL = { SkyDragonController = true, IndexController = true, NpcController = true, TutorialController = true,
	ShowcaseController = true, DevController = true, DevPetShow = true,
	HomeFx = true, FusionController = true,
	BattleController = true, ArenaController = true,
	CareController = true, HomePortalFx = true,
	MainMenuController = true, DungeonController = true, ObbyController = true, FountainFx = true,
	MeadowFx = true, RingCrowdFx = true, DungeonFx = true,
	RingAmbience = true }

local client = script.Parent
task.spawn(function() local okMesh, MeshLibrary = pcall(function() return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("MeshLibrary", 30)) end) if okMesh and type(MeshLibrary) == "table" then MeshLibrary.Start() end end) -- Phase 6: Blender meshes
task.spawn(function() local okMf, MeshFallback = pcall(function() return require(client:WaitForChild("Controllers"):WaitForChild("MeshFallback", 30)) end) if okMf and type(MeshFallback) == "table" then pcall(MeshFallback.Start) end end) -- Phase 6: Part fallback for server mesh pets on a device whose preload failed
task.spawn(function() local okMl, MouseLock = pcall(function() return require(client:WaitForChild("MouseLock", 30)) end) if okMl and type(MouseLock) == "table" then pcall(MouseLock.Start) end end) -- dungeon fixes: the mouse lock option
task.spawn(function() local okFx, PortalFx = pcall(function() return require(client:WaitForChild("Controllers"):WaitForChild("PortalFxController", 30)) end) if okFx and type(PortalFx) == "table" and type(PortalFx.Init) == "function" then local okInit, err = pcall(PortalFx.Init) if not okInit then warn(TAG .. "PortalFxController.Init failed: " .. tostring(err)) end end end) -- Phase 6: the gates' animation

-- 1. State
task.spawn(function()
	local okRequire, State = pcall(function()
		return require(client:WaitForChild("State", 30))
	end)
	if not okRequire then
		warn(TAG .. "State failed to load: " .. tostring(State))
		return
	end
	if type(State) ~= "table" or type(State.Init) ~= "function" then
		warn(TAG .. "State has no Init function")
		return
	end
	local okInit, err = pcall(State.Init)
	if not okInit then
		warn(TAG .. "State.Init failed: " .. tostring(err))
	end
end)

-- 2. Controllers
local controllers = client:WaitForChild("Controllers")

for _, name in ipairs(CONTROLLER_NAMES) do
	task.spawn(function()
		local moduleScript = controllers:FindFirstChild(name)
		if not moduleScript then
			if not OPTIONAL[name] then
				warn(TAG .. "missing client controller: " .. name)
			end
			return
		end
		local okRequire, controller = pcall(require, moduleScript)
		if not okRequire then
			warn(TAG .. name .. " failed to load: " .. tostring(controller))
			return
		end
		if type(controller) ~= "table" or type(controller.Init) ~= "function" then
			warn(TAG .. name .. " has no Init function")
			return
		end
		local okInit, err = pcall(controller.Init)
		if not okInit then
			warn(TAG .. name .. ".Init failed: " .. tostring(err))
		end
	end)
end

print(TAG .. "client ready")
