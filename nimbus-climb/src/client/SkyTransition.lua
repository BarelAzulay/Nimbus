-- SkyTransition (client): the sky's transition helpers (kit-b SKY lane, .superpowers/slop-audit/round3/BUILD_PLAN.md S2,
-- S3). S2 (sky audit F4): a theme's six 1024 px faces are fetched before its skybox swap, not at the swap itself, so a
-- slow device never shows mismatched or blank faces streaming in one by one. S3 (sky audit F10): a screen blur eases out
-- instead of vanishing in one frame.
--
--   SkyTransition.Preload(themeId [, wait]) -> ids | nil   one ContentProvider:PreloadAsync on the six "rbxassetid://"
--       faces of SkyFaces.For(themeId), in its own thread (never blocks the caller), or in the caller's thread when `wait`
--       is true (SkyController's raid queue: one theme at a time); nil (nothing fetched) for a theme that is not uploaded
--       or a junk id. SkyController calls it for the next theme when its blend window opens and for the four raid themes
--       a few seconds after PLAY. No state: Roblox caches what it has fetched, a second call costs nothing.
--   SkyTransition.BlurOut(blur [, seconds]) -> tween | nil   a BlurEffect's Size tweened to 0 (Quad In: the screen
--       clears slowly, then fast) over `seconds` (default Config.Sky.Transitions.Screen.Out), destroyed when the tween
--       completes; a cancelled tween (the effect wanted on again) leaves it in place for the caller to reuse. Anything but
--       a BlurEffect -> nil. HatchFx.Dim(false) uses it.
-- Plain Lua 5.1-compatible syntax only.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SkyFaces = require(Shared:WaitForChild("SkyFaces"))

local SkyTransition = {}

function SkyTransition.Preload(themeId, wait)
	local faces = SkyFaces.For(themeId)
	if not faces then
		return nil
	end
	local ids = {}
	for _, face in ipairs(SkyFaces.Faces) do
		ids[#ids + 1] = faces[SkyFaces.Slot[face]]
	end
	local function fetch()
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(ids)
		end)
		if not ok then
			warn("[SkyTransition] preload of " .. tostring(themeId) .. " failed: " .. tostring(err))
		end
	end
	if wait == true then
		fetch()
	else
		task.spawn(fetch)
	end
	return ids
end

function SkyTransition.BlurOut(blur, seconds)
	if typeof(blur) ~= "Instance" or not blur:IsA("BlurEffect") then
		return nil
	end
	seconds = tonumber(seconds)
	if not seconds or seconds ~= seconds or seconds <= 0 then
		local screen = Config.Sky.Transitions and Config.Sky.Transitions.Screen
		seconds = screen and tonumber(screen.Out) or 0.35
	end
	local tween = TweenService:Create(blur, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = 0 })
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			blur:Destroy()
		end
	end)
	tween:Play()
	return tween
end

return SkyTransition
