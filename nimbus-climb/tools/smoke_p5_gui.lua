-- smoke_p5_gui.lua: the Phase 5 Neon kit and the window rule (ARCHITECTURE_V3.md "Phase 5 build contract" 6.6, 12.1).
-- Loaded by tools/smoke.py in the CLIENT world. Owner: neonkit (W2) writes the scenarios; every window owner adds its
-- scenes to the client_p5gui_cover lists from inside its own named block below (C18: own block only, re-read the file
-- right before each edit; never touch another block or the dispatch).
--   client_p5neon       Card stroke + Glow, Tile fonts + stroke, SideRect == the prototype at 4 sizes
--   client_p5stamina    150 stamina, runs ~10.7 s, refills <= 3.5 s, 4 dashes, 4 ticks
--   client_p5hud_pills  the HUD pills (Cash / Gems / Tokens / Berries) in the Neon style
--   client_p5gui_cover  for every scene of COVER (menu:*, feed, garden, train, ring, arena:*, dungeon, obby, settings) at
--                       1920x1080, 1280x720, 390x844 and 844x390: union <= 60% of the screen, landscape left edge
--                       >= 0.5 W, portrait top >= 0.44 H, no `Backdrop`, smallest text >= the floor (the coverage.py port)
-- Wave 0 (lead): placeholders only; they report info and never fail, so the gate stays green until the owners fill them.
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}

----------------------------------------------------------------------------------------------------
-- COVER: the scenes client_p5gui_cover opens, { Scene = "<dump_gui scene>", Open = function() ... end } entries.
-- Each window owner registers ITS windows inside its own block (append to COVER; a window gets its own controller).
----------------------------------------------------------------------------------------------------
local COVER = {}

-- [owner: neonkit] begin
-- (the kit's own gallery scenes, client_p5neon / client_p5stamina / client_p5hud_pills helpers)
-- [owner: neonkit] end

-- [owner: careui] begin
-- (menu:*, feed, garden, train, looks, home:strip)
-- [owner: careui] end

-- [owner: menu] begin
-- (mainmenu, loading, settings)
-- [owner: menu] end

-- [owner: battleclient] begin
-- (battle:fighter, battle:raid, battle:dungeon, result)
-- [owner: battleclient] end

-- [owner: dungeonclient] begin
-- (ring, arena:*, dungeon, obby)
-- [owner: dungeonclient] end

-- [owner: homefx+pets] begin
-- (follow windows, the home signs if a cover check is wanted)
-- [owner: homefx+pets] end

-- [owner: tutorial] begin
-- (tutorial panel + pointer)
-- [owner: tutorial] end

----------------------------------------------------------------------------------------------------
-- scenarios (neonkit W2 replaces the placeholder bodies)
----------------------------------------------------------------------------------------------------
S.client_p5neon = guarded("client_p5neon", function()
	T.info("*client_p5neon: placeholder until neonkit (W2) lands NeonKit / CloudUI.Panel / Dock")
end)

S.client_p5stamina = guarded("client_p5stamina", function()
	T.info("*client_p5stamina: placeholder until neonkit (W2) lands the HUD stamina ticks (Config.Physics.MaxStamina = 150 is in)")
end)

S.client_p5hud_pills = guarded("client_p5hud_pills", function()
	T.info("*client_p5hud_pills: placeholder until neonkit (W2) lands the HUD pills")
end)

S.client_p5gui_cover = guarded("client_p5gui_cover", function()
	T.info("*client_p5gui_cover: placeholder; " .. #COVER .. " cover scenes registered so far (owners add theirs in their block)")
end)

return S
