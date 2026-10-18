-- smoke_p4_fix_client.lua: regression checks for the Phase 4 review fixes on the client (MenuController's Home window).
-- Loaded by tools/smoke.py in the client worlds (desktop 1920x1080 and the 390x844 touch phone):
--   client_p4fix_home_rows    the My Home window on landscape phone sizes (740x360, 812x375, 667x375): the list column
--                             is too slim for one-line station rows, so every row stacks like portrait (row height
--                             STATION_ROW_H_TALL): each station name fits on one line at its smallest text size, the
--                             info line keeps >= 200 design px, the name / info never run under the price + Upgrade
--                             box and the level pips never touch the price; the summary column stays (two columns);
--                             at 844x390 the rows read either way; at 1280x720 and 1920x1080 they stay one line
--                             (STATION_ROW_H)
--   client_p4fix_mobile       (phone world) the same at 740x360 and 667x375 on the touch phone, then back to portrait
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
local KC = _G.KC

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local function advance(seconds)
	if KC and KC.advance then
		KC.advance(seconds)
	else
		Mock.Advance(seconds)
	end
end

local function moduleAt(top, rest)
	local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	return ok and type(result) == "table" and result or nil
end

local Config = moduleAt("shared", "Config")
local PetCatalog = moduleAt("shared", "PetCatalog")

local function pg()
	return LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

local function menu()
	return (KC and KC.M and KC.M.MenuController) or moduleAt("client", "Controllers/MenuController")
end

local function shown(obj)
	local cur = obj
	while cur and cur ~= game do
		if cur:IsA("LayerCollector") then
			if cur.Enabled == false then
				return false
			end
		elseif cur:IsA("GuiObject") and cur.Visible == false then
			return false
		end
		cur = cur.Parent
	end
	return true
end

local function find(root, name)
	for _, d in ipairs(root and root:GetDescendants() or {}) do
		if d.Name == name then
			return d
		end
	end
	return nil
end

local function bootIfNeeded()
	if not ReplicatedStorage:FindFirstChild("Remotes") then
		local folder = Instance.new("Folder")
		folder.Name = "Remotes"
		for _, n in ipairs(Config.Remotes) do
			local r = Instance.new("RemoteEvent")
			r.Name = n
			r.Parent = folder
		end
		folder.Parent = ReplicatedStorage
	end
	if not (pg() and pg():FindFirstChild("NimbusMenu")) then
		Mock.RunScript(Mock.GetPath(ROOTS["client"] .. "/Main"))
		advance(3)
	end
end

local plot = nil
local function setPlot()
	local lobby = workspace:FindFirstChild("NimbusLobby")
	if not lobby then
		lobby = Instance.new("Folder")
		lobby.Name = "NimbusLobby"
		lobby.Parent = workspace
	end
	if not plot or not plot.Parent then
		plot = Instance.new("Folder")
		plot.Name = "Spot_07"
		plot:SetAttribute("SpotIndex", 7)
		plot.Parent = lobby
	end
	local attrs = { CollectorCash = 1840, IncomePerSecond = 38.5, GardenSlots = 4, HomeLevel = 22, Prestige = 1 }
	for _, k in ipairs({ "CollectorCash", "IncomePerSecond", "GardenSlots", "HomeLevel", "Prestige" }) do
		plot:SetAttribute(k, attrs[k])
	end
	LocalPlayer:SetAttribute(Config.Attr.SpotIndex, 7)
end

local function firstPet()
	for _, def in ipairs(PetCatalog.Pets) do
		if not def.EventOnly and def.Rarity == "Common" then
			return def.Id
		end
	end
	return PetCatalog.Pets[1].Id
end

-- a home in the middle of Phase 4 with stations below their max (so the price + Upgrade box is shown)
local function sync()
	setPlot()
	local id = firstPet()
	local snap = {
		Tokens = 900,
		Pets = { [id] = 1 },
		Equipped = { id },
		Items = {},
		Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
		Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
		Discovered = { [id] = true },
		IndexClaimed = {},
		Tutorial = { Step = 99, Done = true, Gifted = true },
		Cash = 250000,
		Gems = 50,
		Home = {
			Level = 22,
			Prestige = 1,
			Stations = { Garden = 2, Press1 = 5, Press2 = 3, Collector = 2, Kitchen = 2, Gym = 2, Vault = 1, House = 3 },
			Garden = { id, "", "", "" },
			Gym = {},
			CollectorCash = 1840,
		},
		Food = {},
		PetLevels = { [id] = { Level = 12, Xp = 300 } },
		PetGrowth = {},
		Ring = { Best = 0, Runs = 0 },
	}
	LocalPlayer:SetAttribute(Config.Attr.Cash, snap.Cash)
	LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
	Mock.ToClient(ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("ProfileSync"), snap)
	advance(0.4)
end

local function cleanup()
	local M = menu()
	if M and M.Close then
		M.Close()
	end
	advance(0.3)
	LocalPlayer:SetAttribute(Config.Attr.SpotIndex, nil)
	if plot then
		plot:Destroy()
		plot = nil
	end
	advance(0.3)
end

local function design(inst)
	local b = Mock.GuiBox(inst)
	local s = (b.scale and b.scale > 0) and b.scale or 1
	return { x = b.x / s, y = b.y / s, w = b.w / s, h = b.h / s, r = (b.x + b.w) / s, b = (b.y + b.h) / s }
end

-- tol: design px two boxes may share (the one-line rows' name box ends 2 px into the price box by design)
local function overlap(a, b, tol)
	tol = tol or 0.5
	return a.x < b.r - tol and b.x < a.r - tol and a.y < b.b - tol and b.y < a.b - tol
end

local function minSize(label)
	local c = label:FindFirstChildOfClass("UITextSizeConstraint")
	if label.TextScaled and c then
		return c.MinTextSize
	end
	return label.TextSize
end

-- the station rows of the open Home window at the current viewport: a list of problems (empty = fine)
local function rowProblems(win, wantStacked)
	-- MenuController's K.STATION_ROW_H_TALL / K.STATION_ROW_H (wantStacked nil: either, as long as the rows read)
	local wantH = (wantStacked == true and 132) or (wantStacked == false and 96) or nil
	local out, rows = {}, 0
	local list = {}
	for _, d in ipairs(win:GetDescendants()) do
		if d:IsA("GuiObject") and d.Name:sub(1, 8) == "Station_" and shown(d) then
			list[#list + 1] = d
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	for _, row in ipairs(list) do
		rows = rows + 1
		local id = row.Name:sub(9)
		local name, info, right = find(row, "Name"), find(row, "Info"), find(row, "Action")
		local price, pips = find(row, "Price"), find(row, "Pips")
		local fb = design(row)
		if wantH and math.abs(fb.h - wantH) > 0.5 then
			out[#out + 1] = string.format("%s row h=%.0f (want %d)", id, fb.h, wantH)
		end
		if name then
			local nb = design(name)
			local need = #tostring(name.Text) * 0.5 * minSize(name)
			if nb.w + 0.5 < need then
				out[#out + 1] = string.format("%s name '%s' w=%.0f < %.0f", id, name.Text, nb.w, need)
			end
			if right and shown(right) and overlap(nb, design(right), 4) then
				out[#out + 1] = id .. " name under the price box"
			end
		end
		if info and info.Text ~= "" then
			local ib = design(info)
			if ib.w < 200 then
				out[#out + 1] = string.format("%s info w=%.0f < 200", id, ib.w)
			end
			if right and shown(right) and overlap(ib, design(right), 4) then
				out[#out + 1] = id .. " info under the price box"
			end
		end
		if price and pips and shown(price) and shown(pips) and price.Text ~= "" and overlap(design(price), design(pips)) then
			out[#out + 1] = id .. " price on the level pips"
		end
	end
	if rows < 4 then
		out[#out + 1] = "only " .. rows .. " station rows shown"
	end
	return out
end

local function checkSizes(tag, sizes)
	local M = menu()
	local before = Mock.Viewport
	for _, sz in ipairs(sizes) do
		M.Close()
		Mock.SetViewport(sz[1], sz[2])
		advance(0.4)
		M.Open("Home")
		advance(0.8)
		local win = pg():FindFirstChild("NimbusMenu") and pg().NimbusMenu:FindFirstChild("Window_Home")
		if T.check(win ~= nil and win.Visible, string.format("p4fix %s %dx%d: the Home window opens", tag, sz[1], sz[2])) then
			local probs = rowProblems(win, sz[3])
			local how = (sz[3] == true and "stack like portrait") or (sz[3] == false and "stay one line") or "read"
			T.check(#probs == 0, string.format("p4fix %s %dx%d: station rows %s (whole names, info line, price clear of the pips)",
				tag, sz[1], sz[2], how), string.format("list w=%.0f; ", design(find(win, "Stations")).w) .. table.concat(probs, "; "))
			if sz[4] then
				local summary = find(win, "Summary")
				local cw = find(win, "CoinsWaiting")
				T.check(summary ~= nil and shown(summary) and cw ~= nil and shown(cw) and cw:IsDescendantOf(summary),
					string.format("p4fix %s %dx%d: the summary column stays beside the list (two columns)", tag, sz[1], sz[2]))
			end
		end
	end
	M.Close()
	Mock.SetViewport(before.X, before.Y)
	advance(0.4)
end

S.client_p4fix_home_rows = guarded("client_p4fix_home_rows", function()
	bootIfNeeded()
	local M = menu()
	if not T.check(type(M) == "table" and type(M.Open) == "function", "p4fix: MenuController loads with Open") then
		return
	end
	if M.Init then
		M.Init()
	end
	sync()
	-- { w, h, stacked rows?, two columns? }
	checkSizes("home", {
		{ 740, 360, true, true },
		{ 812, 375, true, true },
		{ 667, 375, true, true },
		{ 844, 390, nil, true },
		{ 1280, 720, false, true },
		{ 1920, 1080, false, true },
	})
	cleanup()
end)

S.client_p4fix_mobile = guarded("client_p4fix_mobile", function()
	bootIfNeeded()
	local M = menu()
	if not T.check(type(M) == "table" and type(M.Open) == "function", "p4fix phone: MenuController loads with Open") then
		return
	end
	if M.Init then
		M.Init()
	end
	sync()
	checkSizes("phone", {
		{ 740, 360, true, true },
		{ 667, 375, true, true },
	})
	cleanup()
end)

return S
