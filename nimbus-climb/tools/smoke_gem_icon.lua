-- smoke_gem_icon.lua: lobby-shop Task 15 (spec 5.7 "How gems look", gemlook A): every gem in the GUI is the drawn cut gem
-- of client/UI/GemIcon, and the old gem glyph ("\226\151\134") is gone from the client UI. Loaded by tools/smoke.py in the
-- CLIENT world:
--   client_gem_icon   (client, 1920x1080)
--     sizes 16 / 20 / 24 / 32 / 96: Simple under 28 px (no Facet, no Star, a whole navy outline >= 2 px), the full gem at
--       32 / 96 (outline size / 16, three tones); Shine (registered with the one driver) at >= 20 px with Gfx High only, and
--       never with opts.Shine = false; the shine bar sweeps while High and stays hidden while Low
--     Pile 1 / 2 / 3 / 4 / 6 -> that many GemIcon children at the pitch's PILE offsets; Amount(1250).Value = "1,250",
--       SetAmount re-measures; NeonKit.Icon("Gems") = a TextLabel "Icon" with no text hosting a GemIcon
--     the HUD Gems coin holds a GemIcon at coin size, its badge is the navy panel fill with a cyan UIStroke ring
--     census: the HUD, the Shop (Gems tab; the Store's Currency tab before lobby-shop Task 21; the Eggs tab and the egg
--       stage's gem reveal since Task 22), Daily, Arena (Raid), the
--       Dungeon window, Pets, Index, the Care feed list,
--       Train, the pet picker, the Trove panel and Fusion (Upgrade and Mix): no shown TextLabel / TextButton text holds the
--       glyph; and no client source (MenuController's old shop aside: Tasks 16-18 replace it) spells the glyph or
--       Theme.Currency.Gems.Glyph (the run / end cards of the Dungeon, which the census does not open)
--     churn (Review Focus 5): 500 icons made and destroyed over 50 frames, then 5 viewport changes (the HUD coin is rebuilt)
--       -> GemIcon.Driver().Count equals the live shining icons; no client error
-- Deterministic: mock clock only. The viewport, the attributes, the Gfx answer, the gem product ids and the windows are put
-- back at the end. Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local fmt = string.format

local S = {}

local GLYPH = "\226\151\134"
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local G = {}
function G.KC()
	return _G.KC
end
function G.req(key)
	local inst = Mock.GetPath(ROOTS[key:match("^(%a+)/")] .. "/" .. key:gsub("^%a+/", ""))
	if not inst then
		return nil
	end
	local ok, mod = pcall(require, inst)
	return ok and type(mod) == "table" and mod or nil
end
function G.ctrl(name)
	local KC = G.KC()
	return (KC.M and KC.M[name]) or G.req("client/Controllers/" .. name)
end
function G.pg()
	return LocalPlayer:FindFirstChildOfClass("PlayerGui")
end
function G.advance(seconds)
	Mock.Advance(seconds)
end
-- every shown TextLabel / TextButton in PlayerGui whose text holds the gem glyph (full names)
function G.glyphTexts()
	local KC = G.KC()
	local out = {}
	for _, g in ipairs(G.pg():GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled then
			for _, d in ipairs(g:GetDescendants()) do
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and tostring(d.Text):find(GLYPH, 1, true) and KC.isShown(d) then
					out[#out + 1] = d:GetFullName():gsub("^Players%.[^.]+%.PlayerGui%.", "") .. " = '" .. tostring(d.Text) .. "'"
				end
			end
		end
	end
	return out
end
function G.firstPet(skip)
	local n = 0
	for _, def in ipairs(G.req("shared/PetCatalog").Pets) do
		if not def.EventOnly and def.Rarity ~= "Secret" then
			n = n + 1
			if n > (skip or 0) then
				return def.Id
			end
		end
	end
	return nil
end
-- a profile with pets, a home with a Fusion Machine, Cash and Gems (the windows of the census have something to show)
function G.profile()
	local Config = G.req("shared/Config")
	local ids = {}
	for _, def in ipairs(G.req("shared/PetCatalog").Pets) do
		if not def.EventOnly and def.Rarity ~= "Secret" and #ids < 6 then
			ids[#ids + 1] = def.Id
		end
	end
	local pets, levels = {}, {}
	for i, id in ipairs(ids) do
		pets[id] = (i == 1) and 5 or 1
		levels[id] = { Level = 10 + i * 5, Xp = 10 }
	end
	LocalPlayer:SetAttribute(Config.Attr.Gems, 1250)
	LocalPlayer:SetAttribute(Config.Attr.Cash, 12400)
	G.KC().toClient("ProfileSync", {
		Tokens = 900, Pets = pets, Equipped = { ids[1] }, Items = {}, Discovered = pets, IndexClaimed = {},
		Stats = { Matches = 3, Wins = 1, TokensEarned = 40, Spins = 2, BestTimes = {} },
		Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
		Tutorial = { Step = 99, Done = true, Gifted = true }, Cash = 12400, Gems = 1250, Berries = 1240,
		Home = { Level = 21, Prestige = 1, Stations = { Garden = 3, Press1 = 13, Kitchen = 2, Gym = 2, Vault = 1, House = 2, FusionMachine = 1 },
			Garden = { ids[2], ids[3], "", "" }, Gym = {} },
		PetLevels = levels, PetGrowth = {},
		Teams = { Presets = { { ids[1], ids[4], ids[5] }, {}, {} }, Active = 1, Slots = 3 },
	})
	G.advance(0.5)
	return ids
end
function G.closeAll()
	for _, name in ipairs({ "MenuController", "CareController", "IndexController", "FusionController", "ShopController", "DailyController",
		"ArenaController", "DungeonController", "TroveController", "PetsController" }) do
		local m = G.ctrl(name)
		if m and type(m.Close) == "function" then
			pcall(m.Close)
		end
	end
	local PP = G.req("client/UI/PetPicker")
	if PP and type(PP.Close) == "function" then
		pcall(PP.Close)
	end
end
-- the Daily payload: a gem day and gem play tiers on the card
function G.dailyPayload()
	local now = workspace:GetServerTimeNow()
	local days = {
		{ Kind = "Cash", Amount = 400, Claimed = true, Today = false },
		{ Kind = "Tokens", Amount = 50, Claimed = true, Today = false },
		{ Kind = "Gems", Amount = 25, Claimed = false, Today = true },
		{ Kind = "Cash", Amount = 1000, Claimed = false, Today = false },
		{ Kind = "Tokens", Amount = 250, Claimed = false, Today = false },
		{ Kind = "Gems", Amount = 25, Claimed = false, Today = false },
		{ Kind = "Pet", PetId = "week_wisp", Claimed = false, Today = false },
	}
	local tiers = {
		{ Min = 10, Kind = "Cash", Amount = 200, Claimed = true, Ready = false },
		{ Min = 60, Kind = "Gems", Amount = 10, Claimed = false, Ready = false },
		{ Min = 180, Kind = "Gems", Amount = 25, Claimed = false, Ready = false },
	}
	return {
		Loading = false, Streak = 2, Paid = 2, Weeks = 0, Pet = true, ReadyAt = now - 1, KeepUntil = now + 28 * 3600, StaleAt = 0,
		Cell = 3, Repair = false, Vip = false, StepBack = 0, Days = days, ServerNow = now,
		Unlock = { Need = 600, Left = 0 },
		Play = { Seconds = 36 * 60, DayEnds = now + 5 * 3600, Active = true, Tiers = tiers },
	}
end
-- live GemIcons registered with the shine driver (Shine attribute) in PlayerGui (where every GUI gem lives)
function G.liveShining()
	local n = 0
	for _, d in ipairs(G.pg():GetDescendants()) do
		if d.Name == "GemIcon" and d:IsA("Frame") and d:GetAttribute("Shine") == true then
			n = n + 1
		end
	end
	return n
end

S.client_gem_icon = guarded("client_gem_icon", function()
	local KC = G.KC()
	local Config, _, Theme = KC.env()
	local GemIcon = G.req("client/UI/GemIcon")
	local NeonKit = G.req("client/UI/NeonKit")
	local GQ = G.req("client/GraphicsQuality")
	local okMod = T.check(type(GemIcon) == "table" and type(GemIcon.New) == "function" and type(GemIcon.Pile) == "function"
		and type(GemIcon.Amount) == "function" and type(GemIcon.SetAmount) == "function" and type(GemIcon.Driver) == "function",
		"gem icon: client/UI/GemIcon loads (New, Pile, Amount, SetAmount, Driver)")
	if not T.check(type(GQ) == "table" and type(NeonKit) == "table", "gem icon: GraphicsQuality and NeonKit load") then
		return
	end
	if not okMod then
		-- (no module yet: the census and the source check still run, so they show what is left to swap)
		GemIcon = nil
	end
	local oldViewport = { Mock.Viewport.X, Mock.Viewport.Y }
	local oldGems, oldCash = LocalPlayer:GetAttribute(Config.Attr.Gems), LocalPlayer:GetAttribute(Config.Attr.Cash)
	local realEffective = GQ.Effective
	local gfx = "High"
	GQ.Effective = function()
		return gfx
	end
	local INK = Color3.fromRGB(11, 16, 48)
	local LIGHT, MID, DARK = Theme.Currency.Gems.Glow, Theme.Currency.Gems.Color, Color3.fromRGB(40, 120, 200)
	Mock.SetViewport(1920, 1080)
	G.advance(0.3)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SmokeGems"
	gui.ResetOnSpawn = false
	gui.Parent = G.pg()
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	local row = nil -- the HUD's Currency_Gems row
	------------------------------------------------------------------ sizes
	if GemIcon then
	local function hasColor(seq, c)
		for _, kp in ipairs(seq and seq.Keypoints or {}) do
			if kp.Value == c then
				return true
			end
		end
		return false
	end
	for _, size in ipairs({ 16, 20, 24, 32, 96 }) do
		local label = fmt("gem icon %d px", size)
		local icon = GemIcon.New(root, size)
		local simple = size < 28
		T.check(icon ~= nil and icon:IsA("Frame") and icon.Name == "GemIcon" and icon.Parent == root and icon.Size == UDim2.fromOffset(size, size),
			label .. ": a square Frame 'GemIcon' in its parent")
		if icon then
			T.eq(icon:GetAttribute("Simple"), simple, label .. ": attribute Simple (true under 28 px)")
			T.eq(icon:GetAttribute("Shine"), size >= 20, label .. ": attribute Shine (>= 20 px, Gfx High)")
			-- (review round 1) the star is "Glint": a test lookup of "Star" made tools/mesh_names.py count the Blender palette
			-- key Star as looked up by name and broke the kit selftest for six evolved-pet manifests
			local facet, star = icon:FindFirstChild("Facet", true), icon:FindFirstChild("Glint", true)
			if simple then
				T.check(facet == nil and star == nil, label .. ": the simple form has no facet and no star")
			else
				T.check(facet ~= nil and star ~= nil, label .. ": the full form has the inner facet and the white star")
			end
			local outline = icon:FindFirstChild("Outline", true)
			local th = outline and outline:IsA("UIStroke") and outline.Thickness or -1
			T.check(outline ~= nil and outline:IsA("UIStroke") and outline.Color == INK, label .. ": a navy UIStroke 'Outline' rgb(11,16,48)")
			if simple then
				T.check(th >= 2 and th == math.floor(th), label .. ": the outline is >= 2 px and whole", tostring(th))
			else
				T.check(math.abs(th - size / 16) < 1e-6, label .. ": the outline is size / 16", tostring(th))
			end
			local body = icon:FindFirstChild("Body", true)
			local clip = icon:FindFirstChild("Clip")
			T.check(clip ~= nil and clip.ClipsDescendants == true and clip.Rotation == 0 and body ~= nil and body.Rotation == 45 and body:IsDescendantOf(clip),
				label .. ": a 45-degree diamond inside an unrotated clipping frame (the cut)")
			local cut = icon:FindFirstChild("Cut")
			T.check(cut ~= nil and cut.BackgroundColor3 == INK and cut.BackgroundTransparency == 0, label .. ": a navy bar on the cut")
			local tone = body and body:FindFirstChild("Tone")
			local seq = tone and tone:IsA("UIGradient") and tone.Color
			if simple then
				T.check(hasColor(seq, LIGHT) and hasColor(seq, MID) and not hasColor(seq, DARK), label .. ": two tones (light top, mid bottom)")
			else
				T.check(hasColor(seq, LIGHT) and hasColor(seq, MID) and hasColor(seq, DARK), label .. ": the three tones (light, mid, dark)")
			end
		end
	end
	gfx = "Low"
	local low = GemIcon.New(root, 32)
	T.eq(low:GetAttribute("Shine"), false, "gem icon: Gfx Low -> no Shine at 32 px")
	gfx = "High"
	local off = GemIcon.New(root, 32, { Shine = false, ZIndex = 7, Name = "Quiet" })
	T.check(off.Name == "Quiet" and off:GetAttribute("Shine") == false and off.ZIndex == 7, "gem icon: opts Shine = false, Name and ZIndex")

	-- the shine sweeps (High only)
	local shiny = GemIcon.New(root, 40)
	local bar = shiny:FindFirstChild("ShineBar", true)
	local seenOn = 0
	for _ = 1, 90 do
		G.advance(0.05)
		if bar and bar.Visible then
			seenOn = seenOn + 1
		end
	end
	T.check(bar ~= nil and seenOn >= 4 and seenOn <= 40, "gem icon: the shine bar sweeps across the gem (every ~3.5 s for 0.6 s)", tostring(seenOn) .. " of 90 samples")
	gfx = "Low"
	local seenLow = 0
	for _ = 1, 90 do
		G.advance(0.05)
		if bar and bar.Visible then
			seenLow = seenLow + 1
		end
	end
	T.eq(seenLow, 0, "gem icon: ...and stays hidden while the graphics setting is Low")
	gfx = "High"

	------------------------------------------------------------------ Pile, Amount, NeonKit.Icon
	local PILE = { [1] = { { 0.5, 0.55, 0.8 } }, [2] = { { 0.36, 0.6, 0.62 }, { 0.64, 0.5, 0.7 } } }
	for _, n in ipairs({ 1, 2, 3, 4, 6 }) do
		local pile = GemIcon.Pile(root, 120, n)
		local count = 0
		for _, c in ipairs(pile and pile:GetChildren() or {}) do
			if c.Name == "GemIcon" then
				count = count + 1
			end
		end
		T.check(pile ~= nil and pile.Name == "GemPile" and pile.Size == UDim2.fromOffset(120, 120) and count == n,
			fmt("gem pile %d: a 120 px 'GemPile' with %d GemIcon children", n, n), tostring(count))
		if pile and PILE[n] then
			local okPos = true
			local kids = {}
			for _, c in ipairs(pile:GetChildren()) do
				if c.Name == "GemIcon" then
					kids[#kids + 1] = c
				end
			end
			for i, p in ipairs(PILE[n]) do
				local g = p[3] * 120
				local c = kids[i]
				okPos = okPos and c ~= nil and math.abs(c.Size.X.Offset - g) < 0.51
					and math.abs(c.Position.X.Offset - (p[1] * 120 - g / 2)) < 0.51 and math.abs(c.Position.Y.Offset - (p[2] * 120 - g / 2)) < 0.51
			end
			T.check(okPos, fmt("gem pile %d: the pitch's PILE offsets and sizes", n))
		end
	end
	local amount = GemIcon.Amount(root, 1250)
	local value = amount and amount:FindFirstChild("Value")
	T.check(amount ~= nil and amount.Name == "GemAmount" and amount:FindFirstChild("GemIcon") ~= nil and value ~= nil and value.Text == "1,250",
		"gem amount: 'GemAmount' holds a GemIcon and Value '1,250'", value and value.Text or "none")
	if amount and value then
		local w0 = amount.Size.X.Offset
		GemIcon.SetAmount(amount, 98765432)
		T.check(value.Text == "98,765,432" and amount.Size.X.Offset > w0, "gem amount: SetAmount writes the number and re-measures the width",
			value.Text .. " " .. w0 .. " -> " .. amount.Size.X.Offset)
		local icon = amount:FindFirstChild("GemIcon")
		T.check(value.Position.X.Offset >= icon.Size.X.Offset and amount.Size.X.Offset >= value.Position.X.Offset + value.TextBounds.X - 0.5,
			"gem amount: the number sits right of the gem, inside the frame")
		GemIcon.SetAmount(amount, "12.3M")
		T.eq(value.Text, "12.3M", "gem amount: SetAmount takes a ready string too (short numbers)")
	end
	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromOffset(60, 60)
	holder.Parent = root
	local nk = NeonKit.Icon(holder, "Gems", 40)
	local nkGem = nk and nk:FindFirstChild("GemIcon")
	T.check(nk ~= nil and nk:IsA("TextLabel") and nk.Name == "Icon" and nk.Text == "" and nkGem ~= nil and nkGem.Size == UDim2.fromOffset(40, 40),
		"gem icon: NeonKit.Icon('Gems') is a TextLabel 'Icon' with no text hosting a 40 px GemIcon", nk and (nk.ClassName .. " '" .. tostring(nk.Text) .. "'") or "none")
	T.check(NeonKit.Icon(holder, "Tokens", 40):GetAttribute("PixelIcon") == "token", "gem icon: NeonKit.Icon('Tokens') draws its own icon (kit-b U7a: the token PixelIcon)")

	------------------------------------------------------------------ the HUD coin
	LocalPlayer:SetAttribute(Config.Attr.Gems, 85)
	G.advance(1)
	local hud = G.pg():FindFirstChild("NimbusHud")
	row = hud and hud:FindFirstChild("Currency_Gems", true)
	local coin = row and row:FindFirstChild("Coin")
	local coinGem = coin and coin:FindFirstChild("GemIcon")
	T.check(coinGem ~= nil and coinGem.Size.X.Offset == coin.Size.X.Offset, "gem hud: the Gems coin holds a GemIcon at coin size",
		coin and (tostring(coin.Size.X.Offset) .. " / " .. tostring(coinGem and coinGem.Size.X.Offset)) or "no coin")
	local grad = coin and coin:FindFirstChildOfClass("UIGradient")
	local ring = coin and coin:FindFirstChildOfClass("UIStroke")
	local kps = grad and grad.Color.Keypoints or {}
	T.check(#kps >= 2 and kps[1].Value == Theme.Colors.PanelTop and kps[#kps].Value == Theme.Colors.PanelBottom,
		"gem hud: the Gems badge is the navy panel fill (PanelTop -> PanelBottom)")
	T.check(ring ~= nil and ring.Color == Theme.Currency.Gems.Color, "gem hud: ...with a cyan UIStroke ring (Theme.Currency.Gems.Color)")
	local glyphLabel = coin and coin:FindFirstChild("Glyph")
	T.check(glyphLabel == nil or tostring(glyphLabel.Text) == "", "gem hud: no glyph text on the Gems coin")
	local cashCoin = hud and hud:FindFirstChild("Currency_Tokens", true)
	cashCoin = cashCoin and cashCoin:FindFirstChild("Coin")
	T.check(cashCoin ~= nil and cashCoin:FindFirstChild("GemIcon") == nil and cashCoin:FindFirstChild("Glyph") ~= nil, "gem hud: the other coins are unchanged (their glyph)")
	end -- (GemIcon)

	------------------------------------------------------------------ census
	gui.Enabled = false
	G.closeAll()
	G.advance(0.5)
	local ids = G.profile()
	local savedProducts = {}
	for i, p in ipairs(Config.Gems.Products) do
		savedProducts[i] = p.Id
	end
	local restrictedBefore = LocalPlayer:GetAttribute("PaidRandomItemsRestricted")
	local settledBefore = LocalPlayer:GetAttribute(Config.Attr.GemsSettled or "GemsSettled")
	local census = {
		{ "the HUD", function() end },
		{ "the Shop (Gems tab)", function()
			-- (lobby-shop Task 21: the Store's Currency tab is the one Shop window's Gems tab)
			for i, p in ipairs(Config.Gems.Products) do
				p.Id = 7100 + i
			end
			G.ctrl("ShopController").Open({ Tab = "Gems" })
		end },
		{ "the Shop (Eggs tab)", function()
			-- (lobby-shop Task 22: the Secret Roulette hero and every machine card's Gems button draw the GemIcon)
			LocalPlayer:SetAttribute("PaidRandomItemsRestricted", false)
			LocalPlayer:SetAttribute(Config.Attr.GemsSettled or "GemsSettled", true)
			G.ctrl("ShopController").Open({ Tab = "Eggs" })
		end },
		{ "the egg stage (a gem spin's reveal)", function()
			-- (lobby-shop Task 22: every spin plays through EggStage; a gem spin's SPIN AGAIN carries the gem price)
			local PetCatalog = G.req("shared/PetCatalog")
			local pet = PetCatalog.ListByRarity("Mythic")[1]
			KC.toClient("RouletteResult", { Ok = true, RouletteId = "Secret", Currency = "Gems", Spins = 1, PetId = pet and pet.Id, IsNew = false, Count = 2 })
			G.advance(7)
		end },
		{ "Daily", function()
			KC.toClient("DailyState", G.dailyPayload())
			G.advance(0.3)
			G.ctrl("DailyController").Open({ Tab = "Daily" })
		end },
		{ "Arena (Raid)", function()
			KC.toClient("ArenaState", {
				Next = { Kind = "BossRaid", BossId = "storm_titan", Name = "Storm Titan", StartsIn = 1180 },
				Raid = { Active = true, BossId = "lava_golem", Name = "Lava Golem", BattleId = "R1", FloorTier = "High", FloorHiddenIn = 0, NextBoss = "storm_titan", NextBossIn = 1180, Closed = {},
					Fights = { High = { Tier = "High", Floor = true, Players = 3, Hp = 61000, MaxHp = 90000, EndsIn = 214 } } },
				Double = { Active = false, EndsIn = 0 }, Leaderboard = {},
			})
			G.advance(0.3)
			G.ctrl("ArenaController").OpenArena("Raid")
		end },
		{ "the Dungeon window", function()
			local cleared = {}
			for f = 1, 12 do
				cleared[f] = f <= 4
			end
			KC.toClient("DungeonState", "Lobby", { Parties = {}, Record = { Best = 4, Cleared = cleared, Runs = 12, Clears = 7 } })
			G.advance(0.3)
			G.ctrl("DungeonController").Open(3)
		end },
		{ "Pets", function()
			G.ctrl("MenuController").Open("Pets", {})
		end },
		{ "Index", function()
			G.ctrl("MenuController").Open("Index", {})
		end },
		{ "the Care feed list", function()
			G.ctrl("CareController").Open("Feed", { Slot = 4 })
		end },
		{ "Train", function()
			G.ctrl("CareController").Open("Train", { Key = ids[1] })
		end },
		{ "the pet picker", function()
			G.req("client/UI/PetPicker").Open({ Context = "Train", Title = "Pick a pet to train" })
		end },
		{ "the Trove panel", function()
			G.ctrl("TroveController").Open({})
		end },
		{ "Fusion (Upgrade)", function()
			G.ctrl("FusionController").Open("Upgrade", { Key = ids[1] })
		end },
		{ "Fusion (Mix)", function()
			G.ctrl("FusionController").Open("Mix", { Key = ids[1], KeyB = ids[2] })
		end },
	}
	for _, entry in ipairs(census) do
		local name, open = entry[1], entry[2]
		LocalPlayer:SetAttribute(Config.Attr.Gems, 1250)
		local okOpen, err = pcall(open)
		G.advance(1.2)
		local bad = G.glyphTexts()
		T.check(okOpen, "gem census: " .. name .. " opens", tostring(err))
		T.check(#bad == 0, "gem census: " .. name .. ": no shown text holds the gem glyph", table.concat(bad, "; "))
		G.closeAll()
		G.advance(0.4)
	end
	for i, p in ipairs(Config.Gems.Products) do
		p.Id = savedProducts[i] or 0
	end
	LocalPlayer:SetAttribute("PaidRandomItemsRestricted", restrictedBefore)
	LocalPlayer:SetAttribute(Config.Attr.GemsSettled or "GemsSettled", settledBefore)
	-- the client sources (MenuController's old shop aside) never spell the glyph or the theme's gem glyph
	local spelled = {}
	local clientRoot = Mock.GetPath(ROOTS["client"])
	local scanned = 0
	for _, d in ipairs(clientRoot and clientRoot:GetDescendants() or {}) do
		if d:IsA("ModuleScript") or d:IsA("LocalScript") then
			local ok, src = pcall(function()
				return d.Source
			end)
			if ok and type(src) == "string" and src ~= "" then
				scanned = scanned + 1
				if d.Name ~= "MenuController" and (src:find("\\226\\151\\134", 1, true) or src:find("Gems.Glyph", 1, true) or src:find(GLYPH, 1, true)) then
					spelled[#spelled + 1] = d.Name
				end
			end
		end
	end
	T.check(scanned >= 20 and #spelled == 0, "gem census: no client source but MenuController spells the gem glyph or Theme.Currency.Gems.Glyph",
		scanned .. " scanned; " .. table.concat(spelled, ", "))

	------------------------------------------------------------------ churn (Review Focus 5)
	if GemIcon then
	gui.Enabled = true
	root:ClearAllChildren()
	G.advance(0.2)
	local made, alive = 0, {}
	for frame = 1, 50 do
		for _, icon in ipairs(alive) do
			icon:Destroy()
		end
		alive = {}
		for i = 1, 10 do
			local size = 16 + ((frame * 10 + i) % 6) * 6 -- 16 .. 46: simple and full, with and without the shine
			if i % 3 == 0 then
				alive[#alive + 1] = GemIcon.Pile(root, size * 2, 1 + (i % 4))
			elseif i % 3 == 1 then
				alive[#alive + 1] = GemIcon.Amount(root, frame * 37, { TextSize = 20 })
			else
				alive[#alive + 1] = GemIcon.New(root, size)
			end
			made = made + 1
		end
		G.advance(1 / 60)
	end
	for _, icon in ipairs(alive) do
		icon:Destroy()
	end
	for i, size in ipairs({ { 1280, 720 }, { 844, 390 }, { 2560, 1440 }, { 640, 360 }, { 1920, 1080 } }) do
		Mock.SetViewport(size[1], size[2])
		G.advance(0.6)
		if i == 2 then
			local dc = GemIcon.Driver()
			T.check(type(dc) == "table" and dc.Count == G.liveShining(), "gem churn: mid-resize the driver counts only live icons",
				tostring(dc and dc.Count) .. " vs " .. G.liveShining())
		end
	end
	local d = GemIcon.Driver()
	T.check(made == 500, "gem churn: 500 icons made and destroyed over 50 frames", tostring(made))
	T.check(type(d) == "table" and d.Count == G.liveShining(), "gem churn: Driver().Count equals the live shining icons (dead ones dropped)",
		tostring(d and d.Count) .. " vs " .. G.liveShining())
	coin = row and row:FindFirstChild("Coin")
	local gems = 0
	for _, c in ipairs(coin and coin:GetChildren() or {}) do
		if c.Name == "GemIcon" then
			gems = gems + 1
		end
	end
	T.eq(gems, 1, "gem churn: the HUD coin holds exactly one GemIcon after the relayouts")
	end -- (GemIcon)

	gui:Destroy()
	G.advance(0.2)
	if GemIcon then
		local after = GemIcon.Driver()
		T.check(after.Count == G.liveShining(), "gem churn: icons out of the tree drop out of the driver", tostring(after.Count) .. " vs " .. G.liveShining())
	end
	GQ.Effective = realEffective
	LocalPlayer:SetAttribute(Config.Attr.Gems, oldGems)
	LocalPlayer:SetAttribute(Config.Attr.Cash, oldCash)
	Mock.SetViewport(oldViewport[1], oldViewport[2])
	G.advance(0.6)
	KC.flushErrors("client_gem_icon")
end)

return S
