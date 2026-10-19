-- UiGate: "has the player pressed PLAY on the main menu yet?" (ARCHITECTURE_V3.md "Phase 5 build contract" 7.2).
-- The main menu shows BEFORE the character spawns (the server holds it until MenuPlay). Until PLAY, every ScreenGui
-- except the ones in ALLOW is kept Enabled = false by MainMenuController (a DENY-list rule: any future gui is gated
-- too), MovementController / BattleController keys are inert and TutorialController waits for PLAY.
--
--   UiGate.ALLOW            { "NimbusLoading", "NimbusMainMenu", "NimbusNotify" }  the only guis shown before PLAY
--   UiGate.Played           Util.Signal, fires once when the player presses PLAY (or at once with the menu disabled)
--   UiGate.HasPlayed()      -> bool
--   UiGate.WaitForPlay(t)   -> bool  yields until PLAY or t seconds (default 600); true when played
--   UiGate.MarkPlayed()     -> bool  marks PLAY (once; true the first time) and fires Played
--   UiGate.IsAllowed(name)  -> bool  a ScreenGui name in ALLOW
--
-- Plain Lua 5.1-compatible syntax only. No per-frame work (WaitForPlay polls at 4 Hz only while someone waits).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared:WaitForChild("Util"))

local UiGate = {}

UiGate.ALLOW = { "NimbusLoading", "NimbusMainMenu", "NimbusNotify" }
UiGate.Played = Util.Signal()

local played = false
local POLL = 0.25

function UiGate.HasPlayed()
	return played
end

function UiGate.MarkPlayed()
	if played then
		return false
	end
	played = true
	UiGate.Played:Fire()
	return true
end

function UiGate.WaitForPlay(timeout)
	if played then
		return true
	end
	local limit = tonumber(timeout) or 600
	if limit ~= limit or limit < 0 then
		limit = 0
	end
	local waited = 0
	while not played and waited < limit do
		waited = waited + task.wait(POLL)
	end
	return played
end

-- tests only (smoke_p5_menu.lua): back to "not played" so the gate can be exercised again in one client world
function UiGate._ResetForTests()
	played = false
end

function UiGate.IsAllowed(name)
	for _, allowed in ipairs(UiGate.ALLOW) do
		if allowed == name then
			return true
		end
	end
	return false
end

return UiGate
