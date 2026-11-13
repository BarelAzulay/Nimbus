-- smoke_kitb_obby.lua: the kit-b OBBY lane (O1-O4 of .superpowers/slop-audit/round3/BUILD_PLAN.md; branch kitb-obby).
-- Loaded by tools/smoke.py in both worlds, ARGS.context picks the half. W0 leaves both halves empty: each wave adds its
-- scenarios here and their names on the OBBY line of tools/smoke.py (that line only).
-- Plain Lua 5.1 syntax only.

local function serverScenarios()
	local S = {}
	return S
end

local function clientScenarios()
	local S = {}
	return S
end

if (ARGS and ARGS.context or "server") == "server" then
	return serverScenarios()
end
return clientScenarios()
