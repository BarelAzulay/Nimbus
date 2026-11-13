-- smoke_kitb.lua: the kit-b scaffold (W0 of .superpowers/slop-audit/round3/BUILD_PLAN.md). Loaded by tools/smoke.py,
-- server world only; the lanes keep their own files (smoke_kitb_sky.lua, smoke_kitb_obby.lua, ...):
--   kitb_preview_all_off  (server, pure) Config.Preview holds the staged kit-b looks (TitleShots, SkyAir, ThinClouds),
--                         every switch a boolean and false on the branch default, and nothing else in the table, so a
--                         look built behind a switch never ships on by accident
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

-- the switches W0 adds; a lane that stages a new look adds its name here and to Config.Preview together
local SWITCHES = { "TitleShots", "SkyAir", "ThinClouds" }

local function serverScenarios()
	local K = _G.K
	local S = {}

	S.kitb_preview_all_off = guarded("kitb_preview_all_off", function()
		local Config = K.config()
		local P = Config and Config.Preview
		if not T.check(type(P) == "table", "kitb preview: Config.Preview is a table", tostring(P)) then
			return
		end
		local known = {}
		for _, name in ipairs(SWITCHES) do
			known[name] = true
			T.check(P[name] == false, "kitb preview: Config.Preview." .. name .. " is false on the branch default", tostring(P[name]))
		end
		local extra = {}
		for k in pairs(P) do
			if not known[k] then
				extra[#extra + 1] = tostring(k)
			end
		end
		table.sort(extra)
		T.check(#extra == 0, "kitb preview: Config.Preview holds only the listed switches", table.concat(extra, ", "))
		K.flushErrors("kitb_preview_all_off")
	end)

	return S
end

if (ARGS and ARGS.context or "server") == "server" then
	return serverScenarios()
end
return {}
