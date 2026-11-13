-- SkyTransition (client): the sky's transition helpers (kit-b SKY lane, .superpowers/slop-audit/round3/BUILD_PLAN.md S2;
-- S3 adds BlurOut here). S2 (sky audit F4): a theme's six 1024 px faces are fetched before its skybox swap, not at the
-- swap itself, so a slow device never shows mismatched or blank faces streaming in one by one.
--
--   SkyTransition.Preload(themeId) -> ids | nil   one ContentProvider:PreloadAsync (in its own thread: never blocks the
--       caller) on the six "rbxassetid://" faces of SkyFaces.For(themeId); nil (nothing fetched) for a theme that is not
--       uploaded or a junk id. SkyController calls it for the next theme when its blend window opens and for the four
--       raid themes after PLAY. No state: Roblox caches what it has fetched, a second call costs nothing.
-- Plain Lua 5.1-compatible syntax only.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SkyFaces = require(Shared:WaitForChild("SkyFaces"))

local SkyTransition = {}

function SkyTransition.Preload(themeId)
	local faces = SkyFaces.For(themeId)
	if not faces then
		return nil
	end
	local ids = {}
	for _, face in ipairs(SkyFaces.Faces) do
		ids[#ids + 1] = faces[SkyFaces.Slot[face]]
	end
	task.spawn(function()
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(ids)
		end)
		if not ok then
			warn("[SkyTransition] preload of " .. tostring(themeId) .. " failed: " .. tostring(err))
		end
	end)
	return ids
end

return SkyTransition
