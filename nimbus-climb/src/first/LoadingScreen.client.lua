pcall(function() game:GetService("ReplicatedFirst"):RemoveDefaultLoadingScreen() end)
-- LoadingScreen (ReplicatedFirst; ARCHITECTURE_V3.md "Phase 5 build contract" 7.1). Roblox runs it before every other
-- client script, so it may only use what is already there: ReplicatedStorage.Shared (Config, Theme, Util, UpdateNotes)
-- and plain Roblox services. Never a PlayerScripts module (boot order, m13).
--
-- ScreenGui "NimbusLoading" (DisplayOrder 100, IgnoreGuiInset, ResetOnSpawn false): a violet sky gradient
-- (60,50,150) -> (190,110,200) with a soft cloud bank and a few sparkles; once Shared.Theme exists (no text before:
-- fonts only through Theme roles) the logo NIMBUS / CLIMB (one line, or two when the screen is narrower than 700 px),
-- the tag line, the Cyan neon bar (min(0.6 W, 640 f) x 26 f), "Loading the sky... 64%", a tip from
-- UpdateNotes.Tips that changes every 5 s, and SKIP after Config.Loading.SkipAfter (6) seconds.
--
-- Progress = 5 weighted stages, each 0..1; the bar only moves forward (0.25 s tween):
--   game loaded 0.30 (game:IsLoaded()) | shared modules 0.10 (Config, Theme, Util, Voxel present)
--   lobby replicated 0.30 (BaseParts under workspace.NimbusLobby vs its PartCount attribute; counted once, then by
--     DescendantAdded; after game:IsLoaded() a lobby / PartCount that is not there counts as done: the initial
--     replication is complete) | assets 0.15 (ContentProvider:PreloadAsync of the Sky and this gui)
--   profile 0.15 (the player attribute ProfileLoaded = true, written by DataService when the profile is loaded or
--     provisional)
-- Finish at 100%, at Config.Loading.MaxSeconds (25) or on SKIP: attribute Done = true on the gui. MainMenuController
-- fades it (0.4 s) and destroys it; with the menu disabled (Config.MainMenu.Enabled ~= true) this script fades it
-- after 2 s itself, and it also does so 12 s after Done if nobody took it (a menu that failed to load).
-- One 0.25 s poll loop that ends at Done; no per-frame work. Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	return
end

local L = {
	POLL = 0.25,
	TIP_EVERY = 5,
	SELF_FADE = 2, -- seconds after Done when no main menu runs
	ORPHAN_FADE = 12, -- seconds after Done when the menu should take it but never does
	FADE = 0.4,
	TOP = Color3.fromRGB(60, 50, 150),
	BOTTOM = Color3.fromRGB(190, 110, 200),
	INK = Color3.fromRGB(14, 12, 40),
	CYAN = Color3.fromRGB(64, 226, 236),
	GOLD = Color3.fromRGB(255, 196, 64),
	PURPLE = Color3.fromRGB(176, 104, 255),
	WHITE = Color3.new(1, 1, 1),
	WEIGHTS = { Loaded = 0.30, Shared = 0.10, Lobby = 0.30, Assets = 0.15, Profile = 0.15 },
	STAGES = { "Loaded", "Shared", "Lobby", "Assets", "Profile" },
	SHARED = { "Config", "Theme", "Util", "Voxel" },
}

-- live state (tests read it through the gui's attributes: Progress, Done, Tip)
local St = {
	Stage = { Loaded = 0, Shared = 0, Lobby = 0, Assets = 0, Profile = 0 },
	Shown = 0, -- the bar's value (never goes down)
	Done = false,
	Elapsed = 0,
	TipIndex = 0,
	TipAt = 0,
	Lobby = nil, -- the NimbusLobby being counted
	LobbyParts = 0,
	LobbyConn = nil,
	Ui = {},
	Theme = nil,
	Config = nil,
	Tips = {},
}

----------------------------------------------------------------------
-- the gui (background first: no text until Theme arrives)
----------------------------------------------------------------------

local function make(className, props, parent)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function corner(parent, px)
	return make("UICorner", { CornerRadius = px and UDim.new(0, px) or UDim.new(1, 0) }, parent)
end

local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local gui = make("ScreenGui", {
	Name = "NimbusLoading",
	DisplayOrder = 100,
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)
gui:SetAttribute("Progress", 0)
gui:SetAttribute("Done", false)

local sky = make("Frame", {
	Name = "Sky",
	BackgroundColor3 = L.WHITE,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	Active = true, -- swallows clicks meant for the world behind
}, gui)
make("UIGradient", {
	Color = ColorSequence.new(L.TOP, L.BOTTOM),
	Rotation = 90,
}, sky)
St.Ui.Sky = sky

-- a soft cloud bank along the bottom and a few sparkles: pure decoration, slow looping tweens (no Lua per frame)
local function cloudBank()
	-- two layers of round puffs (circles: their size follows the screen HEIGHT) along the bottom edge
	local layers = {
		{ Name = "CloudsBack", Color = Color3.fromRGB(214, 150, 222), T = 0, Y = 0.86, Puffs = {
			{ 0.02, 0.2 }, { 0.13, 0.26 }, { 0.26, 0.19 }, { 0.38, 0.27 }, { 0.52, 0.21 }, { 0.64, 0.28 }, { 0.78, 0.2 }, { 0.9, 0.27 }, { 1.0, 0.22 },
		} },
		{ Name = "CloudsFront", Color = Color3.fromRGB(250, 214, 246), T = 0, Y = 0.96, Puffs = {
			{ -0.02, 0.18 }, { 0.09, 0.23 }, { 0.2, 0.16 }, { 0.31, 0.22 }, { 0.45, 0.17 }, { 0.57, 0.24 }, { 0.7, 0.18 }, { 0.83, 0.23 }, { 0.96, 0.18 },
		} },
	}
	for li, layer in ipairs(layers) do
		local bank = make("Frame", {
			Name = layer.Name,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1 + li,
		}, sky)
		local base = make("Frame", {
			Name = "Base",
			BackgroundColor3 = layer.Color,
			BackgroundTransparency = layer.T,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, layer.Y),
			Size = UDim2.fromScale(1, 1 - layer.Y),
			ZIndex = 1 + li,
		}, bank)
		local _ = base
		for i, p in ipairs(layer.Puffs) do
			local puff = make("Frame", {
				Name = "Puff" .. i,
				BackgroundColor3 = layer.Color,
				BackgroundTransparency = layer.T,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				SizeConstraint = Enum.SizeConstraint.RelativeYY,
				Position = UDim2.fromScale(p[1], layer.Y),
				Size = UDim2.fromScale(p[2], p[2]),
				ZIndex = 1 + li,
			}, bank)
			corner(puff)
		end
		local drift = li == 1 and 0.012 or -0.016
		TweenService:Create(bank, TweenInfo.new(14 + li * 4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Position = UDim2.fromScale(drift, 0),
		}):Play()
	end
	local stars = { { 0.12, 0.14 }, { 0.83, 0.1 }, { 0.92, 0.32 }, { 0.07, 0.4 }, { 0.72, 0.22 }, { 0.3, 0.08 }, { 0.55, 0.12 }, { 0.2, 0.3 } }
	for i, p in ipairs(stars) do
		local star = make("Frame", {
			Name = "Sparkle" .. i,
			BackgroundColor3 = L.WHITE,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(p[1], p[2]),
			Size = UDim2.fromOffset(i % 3 == 0 and 8 or 5, i % 3 == 0 and 8 or 5),
			ZIndex = 2,
		}, sky)
		corner(star)
		TweenService:Create(star, TweenInfo.new(1.6 + i * 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			BackgroundTransparency = 0.85,
		}):Play()
	end
end
pcall(cloudBank)

----------------------------------------------------------------------
-- the text and the bar (after Theme)
----------------------------------------------------------------------

local function viewport()
	local camera = Workspace.CurrentCamera
	local size = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	if size.X < 2 or size.Y < 2 then
		size = Vector2.new(1920, 1080)
	end
	return size
end

local function label(name, text, role, size, props, parent)
	local Theme = St.Theme
	local obj = make("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Text = text,
		ZIndex = 5,
	}, parent)
	Theme.Style(obj, role, { Size = size, Stroke = 1, Outline = props.Outline, OutlineColor = L.INK, Color = props.Color })
	for key, value in pairs(props) do
		if key ~= "Outline" and key ~= "Color" then
			obj[key] = value
		end
	end
	return obj
end

-- design px (1080p) under one UIScale of the readability factor clamp(H / 1080, 0.8, 1.25)
local function buildContent()
	local Theme = St.Theme
	local vp = viewport()
	local f = Theme.ScreenFactor(vp.Y)
	local designW = vp.X / f
	local short = vp.Y / f < 600
	local twoLines = vp.X < 700
	local root = make("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, short and 0.5 or 0.46),
		Size = UDim2.fromOffset(math.floor(designW), twoLines and 560 or 420),
		ZIndex = 5,
	}, sky)
	make("UIScale", { Name = "ReadScale", Scale = f }, root)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, short and 6 or 10),
	}, root)
	St.Ui.Content = root

	-- the logo: NIMBUS (white) CLIMB (gold), one line or two
	local logoSize = short and 74 or (twoLines and 92 or 100)
	local logo = make("Frame", {
		Name = "Logo",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(math.floor(designW), twoLines and logoSize * 2 or logoSize + 6),
		LayoutOrder = 1,
		ZIndex = 5,
	}, root)
	local wordW = math.floor(logoSize * 4.1)
	local nimbus = label("Nimbus", "NIMBUS", "Title", logoSize, { Outline = 5, Color = L.WHITE }, logo)
	local climb = label("Climb", "CLIMB", "Title", logoSize, { Outline = 5, Color = L.GOLD }, logo)
	if twoLines then
		nimbus.Size = UDim2.new(1, 0, 0, logoSize)
		climb.Size = UDim2.new(1, 0, 0, logoSize)
		climb.Position = UDim2.fromOffset(0, logoSize)
	else
		nimbus.AnchorPoint = Vector2.new(1, 0)
		nimbus.Position = UDim2.new(0.5, -6, 0, 0)
		nimbus.Size = UDim2.fromOffset(wordW, logoSize + 6)
		nimbus.TextXAlignment = Enum.TextXAlignment.Right
		climb.Position = UDim2.new(0.5, 14, 0, 0)
		climb.Size = UDim2.fromOffset(wordW, logoSize + 6)
		climb.TextXAlignment = Enum.TextXAlignment.Left
	end
	St.Ui.Logo = logo

	label("Tagline", "Pets  \226\128\162  Homes  \226\128\162  Battles  \226\128\162  Sky obbies", "Heading", short and 20 or 24, {
		Outline = 2,
		Color = Color3.fromRGB(255, 232, 252),
		Size = UDim2.fromOffset(math.floor(designW), 32),
		LayoutOrder = 2,
	}, root)
	make("Frame", { Name = "Gap", BackgroundTransparency = 1, Size = UDim2.fromOffset(10, short and 8 or 26), LayoutOrder = 3 }, root)

	-- the neon bar: a dark track with a cyan neon border + glow ring, a cyan fill with a light sheen
	local barW = math.floor(math.min(0.6 * vp.X, 640 * f) / f)
	local bar = make("Frame", {
		Name = "Bar",
		BackgroundColor3 = L.INK,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(barW, 26),
		LayoutOrder = 4,
		ZIndex = 5,
	}, root)
	corner(bar)
	make("UIStroke", { Color = L.CYAN, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, bar)
	local glow = make("Frame", {
		Name = "Glow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 8, 1, 8),
		ZIndex = 4,
	}, bar)
	corner(glow)
	make("UIStroke", { Color = L.CYAN, Thickness = 5, Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, glow)
	local fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = L.WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(0, 0, 1, -8),
		ZIndex = 6,
	}, bar)
	corner(fill)
	make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(150, 246, 255), L.CYAN),
		Rotation = 90,
	}, fill)
	St.Ui.Bar, St.Ui.Fill, St.Ui.BarW = bar, fill, barW

	St.Ui.Caption = label("Caption", "Loading the sky... 0%", "Heading", 22, {
		Outline = 2,
		Size = UDim2.fromOffset(barW, 30),
		LayoutOrder = 5,
	}, root)
	make("Frame", { Name = "Gap2", BackgroundTransparency = 1, Size = UDim2.fromOffset(10, short and 4 or 22), LayoutOrder = 6 }, root)

	-- the tip: a dark glass card with a purple neon edge
	local tipW = math.floor(math.min(designW - 48, short and 760 or 880))
	local tipCard = make("Frame", {
		Name = "TipCard",
		BackgroundColor3 = L.INK,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(tipW, twoLines and 96 or (short and 64 or 74)),
		LayoutOrder = 7,
		ZIndex = 5,
	}, root)
	corner(tipCard, 18)
	make("UIStroke", { Color = L.PURPLE, Thickness = 2, Transparency = 0.25, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tipCard)
	local tipHead = label("TipHead", "TIP", "Button", 18, {
		Color = L.INK,
		BackgroundTransparency = 0,
		BackgroundColor3 = L.GOLD,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(52, 30),
		ZIndex = 6,
	}, tipCard)
	tipHead.TextStrokeTransparency = 1
	corner(tipHead, 10)
	St.Ui.Tip = label("Tip", "", "Body", 21, {
		Outline = 2,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(84, 6),
		Size = UDim2.new(1, -100, 1, -12),
		ZIndex = 6,
	}, tipCard)
	St.Ui.TipCard = tipCard

	-- SKIP (bottom-right, appears after SkipAfter seconds)
	local skip = make("TextButton", {
		Name = "Skip",
		AutoButtonColor = true,
		BackgroundColor3 = L.INK,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -math.floor(24 * f), 1, -math.floor(24 * f)),
		Size = UDim2.fromOffset(math.floor(150 * f), math.floor(54 * f)),
		Text = "SKIP  \226\150\182",
		Visible = false,
		ZIndex = 8,
	}, sky)
	Theme.Style(skip, "Button", { Size = math.floor(22 * f), Stroke = 1, Outline = 2, OutlineColor = L.INK })
	corner(skip)
	make("UIStroke", { Color = L.WHITE, Thickness = 2, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, skip)
	skip.Activated:Connect(function()
		St.Skipped = true
	end)
	St.Ui.Skip = skip
end

----------------------------------------------------------------------
-- progress
----------------------------------------------------------------------

local function countLobby(lobby)
	if St.Lobby == lobby then
		return
	end
	if St.LobbyConn then
		St.LobbyConn:Disconnect()
	end
	St.Lobby = lobby
	local n = 0
	for _, d in ipairs(lobby:GetDescendants()) do
		if d:IsA("BasePart") then
			n = n + 1
		end
	end
	St.LobbyParts = n
	St.LobbyConn = lobby.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			St.LobbyParts = St.LobbyParts + 1
		end
	end)
end

local function measure()
	local loaded = game:IsLoaded()
	St.Stage.Loaded = loaded and 1 or 0
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local have = 0
	for _, name in ipairs(L.SHARED) do
		if shared and shared:FindFirstChild(name) then
			have = have + 1
		end
	end
	St.Stage.Shared = have / #L.SHARED
	local lobby = Workspace:FindFirstChild("NimbusLobby")
	local total = lobby and lobby:GetAttribute("PartCount") or nil
	if lobby and type(total) == "number" and total > 0 then
		countLobby(lobby)
		St.Stage.Lobby = math.min(1, St.LobbyParts / total)
	elseif loaded then
		St.Stage.Lobby = 1
	end
	local attr = (St.Config and St.Config.Attr and St.Config.Attr.ProfileLoaded) or "ProfileLoaded"
	St.Stage.Profile = LocalPlayer:GetAttribute(attr) == true and 1 or 0
	local sum = 0
	for _, name in ipairs(L.STAGES) do
		sum = sum + L.WEIGHTS[name] * St.Stage[name]
	end
	return sum
end

local function showProgress(value, force)
	if value <= St.Shown and not force then
		return
	end
	St.Shown = math.min(1, math.max(St.Shown, value))
	gui:SetAttribute("Progress", St.Shown)
	local ui = St.Ui
	if ui.Fill then
		local w = math.floor((ui.BarW - 8) * St.Shown + 0.5)
		TweenService:Create(ui.Fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, w, 1, -8),
		}):Play()
	end
	if ui.Caption then
		ui.Caption.Text = "Loading the sky... " .. math.floor(St.Shown * 100 + 0.5) .. "%"
	end
end

local function nextTip()
	local tips = St.Tips
	if #tips == 0 or not St.Ui.Tip then
		return
	end
	St.TipIndex = St.TipIndex % #tips + 1
	St.Ui.Tip.Text = tips[St.TipIndex]
	gui:SetAttribute("Tip", St.TipIndex)
end

----------------------------------------------------------------------
-- fade out (used when no main menu takes the screen)
----------------------------------------------------------------------

local function fadeAndDestroy()
	if not gui.Parent or gui:GetAttribute("Fading") then
		return
	end
	gui:SetAttribute("Fading", true)
	local info = TweenInfo.new(L.FADE)
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("GuiObject") then
			TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				TweenService:Create(d, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		end
	end
	task.delay(L.FADE, function()
		gui:Destroy()
	end)
end

local function finish()
	if St.Done then
		return
	end
	St.Done = true
	showProgress(1)
	gui:SetAttribute("Done", true)
	if St.LobbyConn then
		St.LobbyConn:Disconnect()
		St.LobbyConn = nil
	end
	local menuOn = St.Config and type(St.Config.MainMenu) == "table" and St.Config.MainMenu.Enabled == true
	task.delay(menuOn and L.ORPHAN_FADE or L.SELF_FADE, fadeAndDestroy)
end

----------------------------------------------------------------------
-- boot
----------------------------------------------------------------------

task.spawn(function()
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local okConfig, Config = pcall(function()
		return require(shared:WaitForChild("Config"))
	end)
	St.Config = okConfig and Config or nil
	local okTheme, Theme = pcall(function()
		return require(shared:WaitForChild("Theme"))
	end)
	if not okTheme or type(Theme) ~= "table" or not gui.Parent then
		return
	end
	St.Theme = Theme
	local okNotes, notes = pcall(function()
		return require(shared:WaitForChild("UpdateNotes", 10))
	end)
	if okNotes and type(notes) == "table" and type(notes.Tips) == "table" then
		St.Tips = notes.Tips
	end
	if #St.Tips > 0 then
		St.TipIndex = (LocalPlayer.UserId % #St.Tips) -- nextTip() moves to the first one shown
	end
	local okBuild, err = pcall(buildContent)
	if not okBuild then
		warn("[LoadingScreen] " .. tostring(err))
	end
	nextTip()
	St.TipAt = St.Elapsed
	local okMeasure, value = pcall(measure)
	showProgress(okMeasure and value or St.Shown, true)
	-- assets: the sky faces and this gui
	task.spawn(function()
		local list = { gui }
		local skyInst = Lighting:FindFirstChildOfClass("Sky")
		if skyInst then
			list[#list + 1] = skyInst
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		St.Stage.Assets = 1
	end)
end)

task.spawn(function()
	local loading = (St.Config and St.Config.Loading) or {}
	while not St.Done and gui.Parent do
		local dt = task.wait(L.POLL)
		St.Elapsed = St.Elapsed + (tonumber(dt) or L.POLL)
		loading = (St.Config and St.Config.Loading) or loading
		local ok, value = pcall(measure)
		if ok then
			showProgress(value)
		end
		if St.Ui.Skip and not St.Ui.Skip.Visible and St.Elapsed >= (tonumber(loading.SkipAfter) or 6) then
			St.Ui.Skip.Visible = true
		end
		if St.Elapsed - St.TipAt >= L.TIP_EVERY then
			St.TipAt = St.Elapsed
			nextTip()
		end
		if St.Skipped or St.Shown >= 0.999 or St.Elapsed >= (tonumber(loading.MaxSeconds) or 25) then
			finish()
		end
	end
end)
