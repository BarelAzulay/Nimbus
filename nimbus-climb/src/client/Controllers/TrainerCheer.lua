-- TrainerCheer (client, wave 6 "fight focus", docs/superpowers/specs/2026-10-29-fight-focus-wave6-design.md goal 4):
-- the local player's OWN avatar cheers its pets on. On the Champion Ring / PvP podium (the server sets the player attribute
-- Config.Attr.OnPodium) it loops; a "Cheer up!" press in a dungeon / raid plays it once (BattleController, on the
-- server's Cheer event). The animation is the avatar's built-in /cheer emote through the default Animate script's
-- PlayEmote BindableFunction (R15 and R6), so no animation id is shipped (check.mjs asset-id). A rig without PlayEmote
-- plays nothing (the boost still works on the server). Each client plays only its own avatar: Roblox replicates the
-- character's animation to everyone else. No sound here (the sound wave owns that). Plain Lua 5.1-compatible syntax only.
--
-- API
--   TrainerCheer.Play(character) -> bool   invokes Animate.PlayEmote("cheer"); while the pose is not standing (PlayEmote
--                                          answers false) it retries every RETRY s for up to RETRY_FOR s; false when the
--                                          rig has no PlayEmote
--   TrainerCheer.StartLoop(character)      play now, then again every LOOP_GAP (2.5-4 s) until StopLoop / the character
--                                          goes (a second StartLoop restarts it)
--   TrainerCheer.StopLoop()
--   TrainerCheer.IsLooping() -> bool

local TrainerCheer = {}

TrainerCheer.EMOTE = "cheer"
TrainerCheer.RETRY = 0.2
TrainerCheer.RETRY_FOR = 1
TrainerCheer.LOOP_GAP = { 2.5, 4 }

local rng = Random.new()
local loopToken = 0
local looping = false

-- the character's PlayEmote BindableFunction | nil
local function playEmoteOf(character)
	if typeof(character) ~= "Instance" then
		return nil
	end
	local animate = character:FindFirstChild("Animate")
	local fn = animate and animate:FindFirstChild("PlayEmote")
	if fn and fn:IsA("BindableFunction") then
		return fn
	end
	return nil
end

local function invoke(fn)
	local ok, result = pcall(function()
		return fn:Invoke(TrainerCheer.EMOTE)
	end)
	return ok and result ~= false and result ~= nil
end

function TrainerCheer.Play(character)
	local fn = playEmoteOf(character)
	if not fn then
		return false
	end
	if invoke(fn) then
		return true
	end
	-- not standing yet (landing, the podium teleport): a few short retries, never a queue
	task.spawn(function()
		local waited = 0
		while waited < TrainerCheer.RETRY_FOR do
			task.wait(TrainerCheer.RETRY)
			waited = waited + TrainerCheer.RETRY
			if not character.Parent or invoke(fn) then
				return
			end
		end
	end)
	return true
end

function TrainerCheer.StopLoop()
	loopToken = loopToken + 1
	looping = false
end

function TrainerCheer.StartLoop(character)
	loopToken = loopToken + 1
	local token = loopToken
	looping = true
	task.spawn(function()
		while token == loopToken and typeof(character) == "Instance" and character.Parent do
			TrainerCheer.Play(character)
			local gap = TrainerCheer.LOOP_GAP
			task.wait(rng:NextNumber(gap[1], gap[2]))
		end
		if token == loopToken then
			looping = false
		end
	end)
end

function TrainerCheer.IsLooping()
	return looping
end

return TrainerCheer
