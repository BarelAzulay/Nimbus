-- PromptController (client): Pitch 2 item 04_world_ui, the owner's pick B "Stone tags" (docs/superpowers/specs/
-- 2026-11-20-pitch2-build-design.md; mock-up .superpowers/slop-audit/round3/build/PITCH2/D_world/04_world_ui_optB.png,
-- pitch_04_world_ui.py prompt "B"). Roblox's default ProximityPrompt (the grey rounded pill) was the last old-kit piece
-- in the world: every prompt in the workspace is set to Style Custom here (the engine still handles its key, range and
-- line of sight) and draws the kit's plank instead, a BillboardGui "PromptCard" in the PlayerGui on the prompt's part:
--   Tab    the wood tab (2 px dark wood edge, 3 px lip, its lit line) naming the object ("Storm Altar"), 18 px stone ink,
--          peeking over the plank's top-left; none when the prompt has no ObjectText
--   Plank  the Tile plank (3 px wood edge, 5 px lip in the stone lip): a TextButton, so a tap or a click holds the prompt
--          (prompt:InputHoldBegin / InputHoldEnd, as the default prompt's ClickablePrompt did)
--   Hit    (look review r0: the plank is 50 design px, 40 screen px under a phone's 0.8) a clear TextButton over the whole
--          plank, its edges included, at least K.TOUCH screen px tall (HitFor "Plank"): the thumb's target; same input
--   Key    the navy key block (2 px wood edge, 3 px lip) with the key in stone ink: E (its KeyboardKeyCode), X on a pad,
--          TAP on a touch screen
--   Action the ActionText ("Secret Roll") at 26 px in the kit's brown ink
--   Hold   a prompt with a HoldDuration fills the plank's lip in grass while it is held (a tween: no Lua per frame)
-- Sizes are 1080p design px under a UIScale (Theme.ScreenFactor). One card a shown prompt; it goes when the prompt hides,
-- is disabled or leaves. A text change while shown redraws it. Plain Lua 5.1-compatible syntax only.
--   PromptController.Init()                    idempotent
--   PromptController.CardOf(prompt) -> BillboardGui | nil
--   PromptController.Custom(prompt)            sets one prompt's Style (the watch calls it for every new prompt)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local CloudUI = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("CloudUI"))

local Sign = Theme.Sign

local PromptController = {}

local K = {
	NAME = "PromptCard",
	TAB_H = 28, -- the tab, its 2 px edge included
	TAB_X = 10,
	TAB_PAD = 10, -- px each side of the object name
	TAB_EDGE = 2,
	TAB_LIP = 3,
	TAB_OVER = 3, -- px of the tab behind the plank's top edge
	PLANK_H = 56, -- the plank, its 3 px edge included
	PLANK_EDGE = 3,
	PLANK_LIP = 5,
	KEY = 34, -- the key block, its 2 px edge included
	KEY_X = 10, -- px from the plank's face to the key
	KEY_EDGE = 2,
	KEY_LIP = 3,
	KEY_PX = 20,
	TAP_PX = 18, -- (look review r0) 16 drew 12.8 px under a phone's 0.8: 18 keeps TAP at 14.4 (Theme.Readability.MinPx 14)
	TOUCH = 44, -- (look review r0) screen px: the clear Hit button over the plank is at least this tall at any scale
	GAP = 12, -- the key to the action
	RIGHT = 18, -- px after the action
	ACTION_PX = 26,
	OBJECT_PX = 18,
	MAX_DISTANCE = 100,
	MAX_LIFT = 12, -- studs: the most a prompt's CardLift floats its plank
}
PromptController.K = K

local S = { started = false, cards = {}, conns = {} }
PromptController._S = S

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function pg()
	local player = Players.LocalPlayer
	return player and player:FindFirstChildOfClass("PlayerGui")
end

function PromptController.Custom(prompt)
	if typeof(prompt) == "Instance" and prompt:IsA("ProximityPrompt") and prompt.Style ~= Enum.ProximityPromptStyle.Custom then
		pcall(function()
			prompt.Style = Enum.ProximityPromptStyle.Custom
		end)
	end
end

local function adorneeOf(prompt)
	local p = prompt.Parent
	if p and (p:IsA("BasePart") or p:IsA("Attachment")) then
		return p
	end
	if p and p:IsA("Model") then
		return p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function keyText(prompt, inputType)
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP", K.TAP_PX
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		local code = prompt.GamepadKeyCode
		local name = (typeof(code) == "EnumItem" and code.Name) or "ButtonX"
		return (name:gsub("^Button", "")), K.KEY_PX
	end
	local code = prompt.KeyboardKeyCode
	local name = (typeof(code) == "EnumItem" and code.Name) or "E"
	return name, K.KEY_PX
end

local function width(text, role, px)
	return math.ceil(Theme.Measure(text, role, px).X)
end

local function drop(prompt)
	local rec = S.cards[prompt]
	S.cards[prompt] = nil
	if rec then
		for _, c in ipairs(rec.conns) do
			c:Disconnect()
		end
		if rec.tween then
			pcall(rec.tween.Cancel, rec.tween)
		end
		if rec.holding then
			pcall(function()
				prompt:InputHoldEnd()
			end)
		end
		rec.gui:Destroy()
	end
end

local function build(prompt, inputType)
	drop(prompt)
	local parent = pg()
	local adornee = adorneeOf(prompt)
	if not parent or not adornee then
		return nil
	end
	local action = tostring(prompt.ActionText or "")
	local object = tostring(prompt.ObjectText or "")
	local key, keyPx = keyText(prompt, inputType)
	local keyW = math.max(K.KEY, width(key, "Button", keyPx) + 12)
	local actionW = width(action, "Heading", K.ACTION_PX)
	local tabW = (object ~= "") and (width(object, "Heading", K.OBJECT_PX) + 2 * K.TAB_PAD) or 0
	local W = math.max(K.PLANK_EDGE + K.KEY_X + keyW + K.GAP + actionW + K.RIGHT + K.PLANK_EDGE, tabW + 2 * K.TAB_X)
	local plankY = (tabW > 0) and (K.TAB_H - K.TAB_OVER) or 0
	local H = plankY + K.PLANK_H
	local scale = 1
	pcall(function()
		scale = Theme.ScreenFactor()
	end)

	-- (look review r1, M2) a prompt's CardLift attribute (studs, 0..K.MAX_LIFT; GateService's gate prompts) floats the plank
	-- that far over its anchor
	local lift = tonumber(prompt:GetAttribute("CardLift")) or 0
	lift = (lift == lift) and math.clamp(lift, 0, K.MAX_LIFT) or 0
	local gui = make("BillboardGui", {
		Name = K.NAME,
		Adornee = adornee,
		StudsOffsetWorldSpace = Vector3.new(0, lift, 0),
		Size = UDim2.fromOffset(math.ceil(W * scale), math.ceil(H * scale)),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = K.MAX_DISTANCE,
		ResetOnSpawn = false,
		Active = true,
		ClipsDescendants = false,
	})
	gui:SetAttribute("Prompt", prompt:GetFullName())
	local root = make("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromOffset(W, H) }, gui)
	make("UIScale", { Name = "ReadScale", Scale = scale }, root)

	if tabW > 0 then
		local e = K.TAB_EDGE
		local tab = make("Frame", {
			Name = "Tab",
			Position = UDim2.fromOffset(K.TAB_X + e, e),
			Size = UDim2.fromOffset(tabW - 2 * e, K.TAB_H - 2 * e),
			ZIndex = 1,
		}, root)
		CloudUI.SignBlock(tab, "Stone", { Face = Sign.Wood, Edge = Sign.WoodDark, Lip = Sign.WoodDark, EdgePx = e, LipPx = K.TAB_LIP, Pad = false, Finish = "Lean" })
		local t = Theme.Label(object, "Heading", { Size = K.OBJECT_PX, Color = Sign.Stone })
		t.Name = "Object"
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, 0, 1, -K.TAB_LIP)
		t.TextXAlignment = Enum.TextXAlignment.Center
		t.ZIndex = 2
		t.Parent = tab
	end

	local pe = K.PLANK_EDGE
	local plank = make("TextButton", {
		Name = "Plank",
		Text = "",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(pe, plankY + pe),
		Size = UDim2.fromOffset(W - 2 * pe, K.PLANK_H - 2 * pe),
		ZIndex = 3,
		Active = true,
		Selectable = false,
	}, root)
	CloudUI.SignBlock(plank, "Stone", { Face = Sign.Tile, Edge = Sign.Wood, Lip = Sign.StoneLip, EdgePx = pe, LipPx = K.PLANK_LIP, Pad = false, Finish = "Lean" })
	local faceH = K.PLANK_H - 2 * pe - K.PLANK_LIP

	local ke = K.KEY_EDGE
	local keyBlock = make("Frame", {
		Name = "Key",
		Position = UDim2.fromOffset(K.KEY_X + ke, math.floor((faceH - K.KEY) / 2) + ke),
		Size = UDim2.fromOffset(keyW - 2 * ke, K.KEY - 2 * ke),
		ZIndex = 4,
	}, plank)
	CloudUI.SignBlock(keyBlock, "Navy", { Face = Sign.Navy, Edge = Sign.Wood, Lip = Sign.NavyLip, EdgePx = ke, LipPx = K.KEY_LIP, Pad = false, Finish = false })
	local kt = Theme.Label(key, "Button", { Size = keyPx, Color = Sign.Stone })
	kt.Name = "KeyText"
	kt.BackgroundTransparency = 1
	kt.Size = UDim2.new(1, 0, 1, -K.KEY_LIP)
	kt.TextXAlignment = Enum.TextXAlignment.Center
	kt.ZIndex = 5
	kt.Parent = keyBlock

	local ax = K.KEY_X + keyW + K.GAP
	local at = Theme.Label(action, "Heading", { Size = K.ACTION_PX, Color = Sign.Text })
	at.Name = "Action"
	at.BackgroundTransparency = 1
	at.Position = UDim2.fromOffset(ax, 0)
	at.Size = UDim2.new(1, -ax, 0, faceH)
	at.TextXAlignment = Enum.TextXAlignment.Left
	at.ZIndex = 4
	at.Parent = plank

	-- the hold: the lip fills in grass over HoldDuration
	local hold = make("Frame", {
		Name = "Hold",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(0, 0, 0, K.PLANK_LIP),
		BackgroundColor3 = Sign.Grass,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, plank)

	-- the thumb's target: the whole plank with its edges, never under K.TOUCH screen px tall (centred on the plank)
	local hitH = math.max(K.PLANK_H, math.ceil(K.TOUCH / math.max(scale, 0.01)))
	local hitBtn = make("TextButton", {
		Name = "Hit",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, plankY + math.floor((K.PLANK_H - hitH) / 2)),
		Size = UDim2.fromOffset(W, hitH),
		ZIndex = 6,
		Active = true,
		Selectable = false,
	}, root)
	hitBtn:SetAttribute("HitFor", "Plank")

	local rec = { gui = gui, conns = {}, prompt = prompt, input = inputType, holding = false }
	local function holdBegin()
		if rec.holding then
			return
		end
		rec.holding = true
		pcall(function()
			prompt:InputHoldBegin()
		end)
	end
	local function holdEnd()
		if not rec.holding then
			return
		end
		rec.holding = false
		pcall(function()
			prompt:InputHoldEnd()
		end)
	end
	local function onInput(io)
		local t = io.UserInputType
		return t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1
	end
	for _, button in ipairs({ plank, hitBtn }) do
		rec.conns[#rec.conns + 1] = button.InputBegan:Connect(function(io)
			if onInput(io) and prompt.ClickablePrompt ~= false then
				holdBegin()
			end
		end)
		rec.conns[#rec.conns + 1] = button.InputEnded:Connect(function(io)
			if onInput(io) then
				holdEnd()
			end
		end)
	end
	rec.conns[#rec.conns + 1] = prompt.PromptButtonHoldBegan:Connect(function()
		local d = tonumber(prompt.HoldDuration) or 0
		if d > 0 then
			hold.Size = UDim2.new(0, 0, 0, K.PLANK_LIP)
			local ok, tween = pcall(function()
				return TweenService:Create(hold, TweenInfo.new(d, Enum.EasingStyle.Linear), { Size = UDim2.new(1, 0, 0, K.PLANK_LIP) })
			end)
			if ok and tween then
				rec.tween = tween
				pcall(tween.Play, tween)
			end
		end
	end)
	rec.conns[#rec.conns + 1] = prompt.PromptButtonHoldEnded:Connect(function()
		if rec.tween then
			pcall(rec.tween.Cancel, rec.tween)
			rec.tween = nil
		end
		hold.Size = UDim2.new(0, 0, 0, K.PLANK_LIP)
	end)
	for _, prop in ipairs({ "ActionText", "ObjectText" }) do
		rec.conns[#rec.conns + 1] = prompt:GetPropertyChangedSignal(prop):Connect(function()
			if S.cards[prompt] == rec then
				task.defer(function()
					if S.cards[prompt] == rec then
						build(prompt, rec.input)
					end
				end)
			end
		end)
	end
	rec.conns[#rec.conns + 1] = prompt.AncestryChanged:Connect(function(_, newParent)
		if newParent == nil or not prompt:IsDescendantOf(workspace) then
			drop(prompt)
		end
	end)
	gui.Parent = parent
	S.cards[prompt] = rec
	return gui
end

function PromptController.CardOf(prompt)
	local rec = S.cards[prompt]
	return rec and rec.gui or nil
end

function PromptController.Init()
	if S.started then
		return
	end
	S.started = true
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.ClassName == "ProximityPrompt" then
			PromptController.Custom(d)
		end
	end
	S.conns[#S.conns + 1] = workspace.DescendantAdded:Connect(function(d)
		if d.ClassName == "ProximityPrompt" then
			PromptController.Custom(d)
		end
	end)
	local pps = game:GetService("ProximityPromptService")
	S.conns[#S.conns + 1] = pps.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style == Enum.ProximityPromptStyle.Custom then
			local ok, err = pcall(build, prompt, inputType)
			if not ok then
				warn("[PromptController] the plank failed: " .. tostring(err))
			end
		end
	end)
	S.conns[#S.conns + 1] = pps.PromptHidden:Connect(function(prompt)
		drop(prompt)
	end)
end

return PromptController
