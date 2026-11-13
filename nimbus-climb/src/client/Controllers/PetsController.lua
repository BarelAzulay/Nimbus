-- PetsController (client, team balance, spec s.3): the Pets window. One big window with no tabs and the team's 3 slots always
-- in view; it replaces the Pets and Team tabs of MenuController's old Window_Inventory.
--
--   PetsController.Init()
--   PetsController.Open(args)     args = { Key = string | nil (select this pet), Pick = 1..3 | nil (open in pick mode on that
--                                 slot), Preset = 1..3 | nil (show that team), ReturnTo = table | nil (handed back on close),
--                                 Action = "Evolve" | nil (with Key: the floating card's EVOLVE! pill, the confirm on top) }
--   PetsController.Close(silent)  closes the window; silent = true when something else takes over: ReturnTo is dropped
--   PetsController.IsOpen() -> bool
--   PetsController.SetSort("Strongest" | "Rarest" | "Level"), PetsController.Sort() -> mode
--   PetsController.Layout() -> "PC" | "Phone"
--   PetsController.ReturnArgs()   Open args that bring this window back as it is when a panel waits behind it, else nil (an
--                                 Evolve's cinematic closes the window silently: CareController opens it again after it)
--   PetsController.Opened         Util.Signal, Fire() per opening
--   PetsController.Closed         Util.Signal, Fire(returnTo | nil). ReturnTo (where a close that is not silent goes back to):
--                                 { Window = "Ring", Start, Portal } -> ArenaController.OpenRing(Start, Portal), { Window = "Dungeon", Floor,
--                                 Portal } -> DungeonController.Open(Floor, Portal), { Window = "Arena", Tab } -> ArenaController.OpenArena(Tab),
--                                 { Window = "Loss" } -> LossScreen.Reopen()
-- MenuController.Open("Pets" | "Team" | "Inventory", args), OpenTeam(preset) and the Pets tile come here; an opening fires
-- MenuController.WindowOpened("Pets") (the tutorial's Equipped hook; the other windows close on it), MenuController.Close()
-- closes this one silently.
--
-- Screen: ScreenGui "NimbusPets" (DisplayOrder 19, just under NimbusMenu's 20: MenuController's side hint, the toast of a
-- refused action, shows over the window; IgnoreGuiInset = true), Frame "PetsWindow" (a CloudUI.Panel). Sizes in screen px: a
-- 1920x1080 screen 1260x900 centred, a phone 844x390 820x330 under Roblox's top bar, others between (K.RECT). The layout is
-- "Phone" when the window is under K.PHONE_W x K.SHORT design px: there the design is in screen px (scale 1, texts >= 15).
--   PC: Slot1..3 (Face, Tag FIGHTER | HELPER, PetName, Level, Power, Busy, Glow, Empty), TeamPower, TeamBreakdown, AutoFill, ClearTeam
--       ("Tap again to clear" for 3 s), PresetA..C (attribute Selected on the active team, Shown on the team shown), Undo (6 s
--       after AutoFill); a GridWell with SortButton, PickBanner + PickCancel and Grid (the ONLY ScrollingFrame) of Card_<key>
--       (Picture, Level, Element, Power, a UIStroke Rarity, Number, Busy, Tier, Stars, Count, Name); Detail: the selected pet (Name,
--       Meta, XpBar, Row_Income | Power | Health | Speed with Label + Value, Work, Perks, ActPut | ActFighter + ActRemove, ActFeed,
--       ActTrain, ActGarden, ActEvolve).
--   Phone: the slots in a column on the left (a row on top when the screen is portrait), the same controls on the top row, 104 x
--       130 cards, and the Detail frame is the Sheet (renamed): over the grid, never over the slots, its actions at the bottom edge.
-- Picking: a tap on a slot = pick mode (banner + glow); a tap on a pet drops it in at once (BattleRequest "TeamSet", the slot shows
-- it with a pop and a heavy sound); a pet in another slot swaps; the slot's own pet ends pick mode on its details (Remove);
-- tap the slot again or X to cancel. Every write is a draft until a sync shows it: a "bad" Notify, or no sync in K.ANSWER s,
-- drops it AT ONCE with a toast and arms the same slot again (a pick that came from pick mode). A gardening pet asks first
-- (PetBits.askRecall, HomeAction "GardenRecall" stores the team in ONE request); a training pet is refused on the spot.
-- A hole ("") in a TeamSet keeps the others at their index: the server's kept rule lets a busy pet stay only in its slot.
-- Remotes used: BattleRequest ("TeamSet", "TeamSelect"), HomeAction ("GardenSet", "GardenRecall"), Notify (in).
-- Plain Lua 5.1-compatible syntax only. All text goes through Theme roles; no asset ids.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local PixelIcon = require(Shared:WaitForChild("PixelIcon")) -- (kit-b U7b) the power sword, the stars, the busy marks
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local CloudUI = require(Client:WaitForChild("UI"):WaitForChild("CloudUI"))
local NeonKit = require(Client:WaitForChild("UI"):WaitForChild("NeonKit"))
local Bits = require(Client:WaitForChild("UI"):WaitForChild("PetBits"))
local State = require(Client:WaitForChild("State"))
local SoundFx = require(Client:WaitForChild("SoundFx"))

local PetCatalog = require(Shared:WaitForChild("PetCatalog"))
local BattleCatalog = require(Shared:WaitForChild("BattleCatalog"))

local PetsController = {}
PetsController.Opened = Util.Signal()
PetsController.Closed = Util.Signal()

local K = {
	DISPLAY_ORDER = 19,
	MARGIN = 12, -- screen px left and right of the window
	RECT = { H0 = 390, W0 = 820, Y0 = 330, H1 = 1080, W1 = 1260, Y1 = 900 }, -- window px at the two screen heights
	PHONE_W = 900, -- design px: narrower, or lower than SHORT, is the phone layout (the PC top row needs this much)
	SHORT = 560,
	PC_MIN_H = 600, -- a landscape screen this tall keeps the window under PC_MAX_W of its width
	PC_MAX_W = 0.76,
	SLOTS = 3,
	PRESETS = 3,
	SEND_GAP = 0.45, -- seconds between two TeamSet / TeamSelect (the server's cooldowns are 0.4 / 0.3: a closer one is dropped)
	SEND_BURST = 4, -- the server's shared BattleRequest bucket (BattleService REQUEST_BURST / REFILL, 4 and 1/s; a miss gets no answer)
	SEND_REFILL = 0.9, -- per second, a little under the server's: a late send followed by a quick one still arrives inside it
	ANSWER = 2.5, -- seconds a write waits for the sync or a refusal
	UNDO_SECONDS = 6,
	CLEAR_SECONDS = 3,
	FIRE_GAP = 0.3, -- client-side spacing of the same HomeAction
	TICK = 1, -- seconds between two refreshes of the shown training time
	BUILD_BUDGET = 0.004, -- card viewports: the first of a frame always, more while the frame spent < this many seconds
	BUILD_MAX = 3,
	BACK_ACTION = "NimbusPetsBack", -- owns gamepad B while the window is open (it would also dash)
	SORTS = { "Strongest", "Rarest", "Level" },
	TOUCH = 44, -- screen px: the smallest tap target
	PHONE_CHIPS = { 96, 116, 88 }, -- Sort, Auto-fill, Clear on a landscape phone's top row; they share what the close button leaves
	PC_CARD = { 116, 170, 8 }, -- w, h, gap
	POWER_W = 240, -- design px Team power needs beside the button columns (a big number at 24 px); with less (a tablet) the top row stacks
	STACK_W = 446, -- design px of a stacked top row: Auto-fill + Clear + the three team buttons
	STACK_CLEAR_W = 100, -- ... Clear's (or Undo's) part of it
	WIDE_ROWS_W = 380, -- design px of the detail's rows: below this the two columns share them unevenly
	WIDE_W = 1150, -- design px: from this window width the buttons and the detail take their full size
	PHONE_CARD = { 104, 130, 6 },
}

local Colors = Theme.Colors
local WHITE = Colors.White
local NAVY = Colors.Navy or Colors.Ink
local MUTED = Colors.Muted or Colors.CloudShade
local GOLD = Colors.Gold or Colors.Token
local GOOD = Colors.Good
local INSET_COLOR = Color3.fromRGB(20, 30, 70)
local POWER_GOLD = Color3.fromRGB(255, 214, 110)
local FIGHTER_COLOR = Theme.Neon.Red
local HELPER_COLOR = Theme.Neon.Blue
local GARDEN_COLOR = Color3.fromRGB(120, 196, 90)
local TRAIN_COLOR = Color3.fromRGB(150, 122, 226)
local TIER_COLORS = { Golden = Color3.fromRGB(246, 196, 64), Rainbow = Color3.fromRGB(226, 110, 214), Hybrid = Color3.fromRGB(150, 110, 232) }
local XP_COLOR = Color3.fromRGB(120, 200, 255)
local ROW_COLORS = { Income = Colors.Cash or Color3.fromRGB(112, 204, 98), Power = Color3.fromRGB(236, 112, 96), Health = Color3.fromRGB(240, 120, 150), Speed = Color3.fromRGB(98, 172, 232) }
local ROWS = { { "Income", "Coins" }, { "Power", "Battle power" }, { "Health", "Health" }, { "Speed", "Speed" } }

-- typography (kit-b U7b: the sword, the stars and the busy / work marks are PixelIcons, ICON; the emoji went)
local G = {
	Bullet = "\194\183",
	Close = "\195\151",
}
local ICON = { Power = "sword", Star = "star", Training = "weight", Garden = "sprout", Evolve = "sparkle" }

local frame, text, corner, round, stroke = Bits.frame, Bits.text, Bits.corner, Bits.round, Bits.stroke

local initialized = false
local LocalPlayer = nil
local U = { Slots = {}, Cards = {}, Rows = {} } -- widgets
local S = {
	Open = false,
	Built = false,
	Token = 0,
	Sort = "Strongest",
	Selected = nil,
	Pick = nil, -- the slot in pick mode
	View = nil, -- the team shown when it is not the active one (Open's Preset)
	SheetOpen = false,
	Mode = "PC", -- "PC" | "Phone"
	Portrait = false,
	Draft = nil, -- { Preset, Keys (dense, shown), Send (holes kept), Sent, Pick } the write waiting for its sync
	Active = nil, -- { Preset, Sent } the team change waiting for its sync
	LastSend = 0,
	LastSelect = 0,
	SendTokens = K.SEND_BURST,
	SendAt = 0,
	Scale = 1,
	Waiting = false,
	TouchOff = false,
	Ready = {}, -- key -> true once the card has its viewport
	Filling = false,
	Order = {},
	Power = {}, -- key -> UnitPower (this refresh)
	ClearArmed = 0, -- a token while Clear waits for its second tap
	UndoId = 0,
	Undo = nil, -- { Preset, Keys } what Undo sends
	ReturnTo = nil,
	LastFire = {},
	Warned = {},
}
local H = {}

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function warnOnce(key, err)
	if not S.Warned[key] then
		S.Warned[key] = true
		warn("[PetsController] " .. tostring(key) .. ": " .. tostring(err))
	end
end

local function safe(key, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		warnOnce(key, a)
	end
	return ok, a, b
end

local function commas(n)
	return Util.Commas(tonumber(n) or 0)
end

local function place(inst, x, y, w, h)
	inst.AnchorPoint = Vector2.new(0, 0)
	inst.Position = UDim2.fromOffset(x, y)
	inst.Size = UDim2.fromOffset(w, h)
end

function H.controller(name)
	local module = script.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, mod = pcall(require, module)
	if ok and type(mod) == "table" then
		return mod
	end
	return nil
end

function H.hint(message, kind)
	local menu = H.controller("MenuController")
	if menu and type(menu.Hint) == "function" then
		safe("hint", menu.Hint, message, kind or "info")
	end
end

function H.inMatch()
	return LocalPlayer ~= nil and LocalPlayer:GetAttribute(Config.Attr.InMatch) == true
end

function H.remote(name)
	local ok, remote = pcall(Remotes.Get, name)
	return ok and remote or nil
end

function H.fireHome(key, action, arg)
	local now = os.clock()
	if S.LastFire[key] and now - S.LastFire[key] < K.FIRE_GAP then
		return false
	end
	local remote = H.remote("HomeAction")
	if not remote then
		return false
	end
	S.LastFire[key] = now
	return (pcall(function()
		remote:FireServer(action, arg)
	end))
end

----------------------------------------------------------------------
-- The team: what is shown = the draft while one waits, else the synced preset
----------------------------------------------------------------------
function H.teams()
	local ok, teams = pcall(State.Teams)
	if ok and type(teams) == "table" and type(teams.Presets) == "table" then
		return teams
	end
	return { Presets = { {}, {}, {} }, Active = 1, Slots = K.SLOTS }
end

function H.activePreset()
	if S.Active then
		return S.Active.Preset
	end
	local a = math.floor(tonumber(H.teams().Active) or 1)
	if a < 1 or a > K.PRESETS then
		a = 1
	end
	return a
end

function H.shownPreset()
	return S.View or H.activePreset()
end

function H.keys()
	local preset = H.shownPreset()
	if S.Draft and S.Draft.Preset == preset then
		return S.Draft.Keys
	end
	return H.teams().Presets[preset] or {}
end

local function sameList(a, b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

-- the three slots with false for an empty one (edits keep the others at their index)
function H.slotList()
	local keys = H.keys()
	local list = {}
	for i = 1, K.SLOTS do
		list[i] = keys[i] or false
	end
	return list
end

function H.indexOf(key)
	for i, k in ipairs(H.keys()) do
		if k == key then
			return i
		end
	end
	return nil
end

function H.powerOf(key)
	local cached = S.Power[key]
	if cached then
		return cached
	end
	local def = Bits.defOfKey(key)
	local level = Bits.petLevel(key)
	local power = def and Bits.battlePower(key, def, level) or 0
	S.Power[key] = power or 0
	return S.Power[key]
end

-- the strongest free pets (busy pets excluded): Auto-fill best
function H.best(count)
	local rows = {}
	for _, key in ipairs(Bits.ownedKeys()) do
		if not Bits.busyOf(key) then
			rows[#rows + 1] = key
		end
	end
	table.sort(rows, function(a, b)
		local x, y = H.powerOf(a), H.powerOf(b)
		if x ~= y then
			return x > y
		end
		return a < b
	end)
	local out = {}
	for i = 1, math.min(count, #rows) do
		out[i] = rows[i]
	end
	return out
end

function H.trainingText(key)
	local job = Bits.job(key)
	local name = Bits.displayName(key)
	if job then
		return name .. " is training (" .. Bits.jobLeft(job) .. " left)"
	end
	return name .. " is training"
end

----------------------------------------------------------------------
-- Writes: a draft shows at once; the sync confirms it, a refusal or silence drops it at once and says so
----------------------------------------------------------------------
function H.newDraft(preset, list, pickSlot)
	local last = 0
	for i = 1, K.SLOTS do
		if list[i] then
			last = i
		end
	end
	local dense, send = {}, {}
	for i = 1, last do
		send[i] = list[i] or ""
		if list[i] then
			dense[#dense + 1] = list[i]
		end
	end
	-- Before: the saved team this write replaces (a sync that changed it answered this write, whatever it now holds)
	local prior = S.Draft
	local before = H.teams().Presets[preset] or {}
	if prior and prior.Preset == preset then
		before = prior.Sent and prior.Keys or prior.Before
	end
	return { Preset = preset, Keys = dense, Send = send, Before = { unpack(before) }, Pick = pickSlot, Sent = false }
end

-- seconds until the server's request bucket lets one more through (the mirror of BattleService's takeToken)
function H.bucketWait()
	local now = os.clock()
	S.SendTokens = math.min(K.SEND_BURST, S.SendTokens + (now - S.SendAt) * K.SEND_REFILL)
	S.SendAt = now
	return S.SendTokens >= 1 and 0 or (1 - S.SendTokens) / K.SEND_REFILL
end

function H.armAnswer(draft)
	task.delay(K.ANSWER, function()
		if S.Draft == draft then
			H.dropDraft("Your team could not save. Try again!")
		end
	end)
end

function H.flushDraft()
	local draft = S.Draft
	if not draft or draft.Sent then
		return
	end
	local wait = math.max(K.SEND_GAP - (os.clock() - S.LastSend), H.bucketWait())
	if wait > 0 then
		if not S.Waiting then
			S.Waiting = true
			task.delay(wait, function()
				S.Waiting = false
				H.flushDraft()
			end)
		end
		return
	end
	S.LastSend = os.clock()
	S.SendTokens = S.SendTokens - 1
	draft.Sent = true
	local remote = H.remote("BattleRequest")
	if remote then
		safe("TeamSet", function()
			remote:FireServer("TeamSet", draft.Preset, draft.Send)
		end)
	end
	H.armAnswer(draft)
end

function H.write(list, pickSlot)
	S.Draft = H.newDraft(H.shownPreset(), list, pickSlot)
	H.flushDraft()
end

-- the write is gone: the slots show the saved team again at once; a pick is armed again on its slot
function H.dropDraft(message)
	local draft = S.Draft
	S.Draft = nil
	if draft and draft.Pick and S.Open then
		S.Pick = draft.Pick
	end
	if message then
		H.hint(message, "bad")
	end
	H.refresh()
end

function H.selectTeam(preset)
	S.Pick = nil
	S.View = nil
	S.Draft = nil
	if preset == math.floor(tonumber(H.teams().Active) or 1) and not S.Active then
		H.refresh()
		return
	end
	local want = { Preset = preset, Sent = false }
	S.Active = want
	H.flushSelect()
	H.refresh()
end

function H.flushSelect()
	local want = S.Active
	if not want or want.Sent then
		return
	end
	local wait = math.max(K.SEND_GAP - (os.clock() - S.LastSelect), H.bucketWait())
	if wait > 0 then
		task.delay(wait, H.flushSelect)
		return
	end
	S.LastSelect = os.clock()
	S.SendTokens = S.SendTokens - 1
	want.Sent = true
	local remote = H.remote("BattleRequest")
	if remote then
		safe("TeamSelect", function()
			remote:FireServer("TeamSelect", want.Preset)
		end)
	end
	task.delay(K.ANSWER, function()
		if S.Active == want then
			S.Active = nil
			H.hint("Your team could not change. Try again!", "bad")
			H.refresh()
		end
	end)
end

-- a "bad" Notify while a write waits: that was the server's answer
function H.onNotify(message, kind)
	if kind ~= "bad" or type(message) ~= "string" then
		return
	end
	local handled = false
	if S.Active and S.Active.Sent then
		S.Active = nil
		handled = true
	end
	if S.Draft and S.Draft.Sent then
		H.dropDraft(nil)
		handled = true
	end
	if handled then
		H.hint(message, "bad")
		H.refresh()
	end
end

-- a sync: the writes it confirms are done
function H.settle()
	local teams = H.teams()
	local draft = S.Draft
	if draft and draft.Sent then
		local saved = teams.Presets[draft.Preset] or {}
		if sameList(draft.Keys, saved) or not sameList(draft.Before, saved) then
			S.Draft = nil
		end
	end
	if S.Active and S.Active.Sent and S.Active.Preset == teams.Active then
		S.Active = nil
	end
end

----------------------------------------------------------------------
-- Picking
----------------------------------------------------------------------
function H.pop(slot)
	local item = U.Slots[slot]
	if item then
		item.Pop.Scale = 1.16
		Util.Tween(item.Pop, 0.26, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	local name = SoundFx.Id("Sfx", "SpinLand") and "SpinLand" or "Confirm"
	safe("snap", SoundFx.Play, name)
end

-- `slot` gets `key` (a swap when the pet sits in another slot). armed: the tap came from pick mode, so a refusal keeps it.
function H.placeKey(key, slot, armed)
	local list = H.slotList()
	local at = H.indexOf(key)
	if at == slot then
		-- the slot's own pet: its details offer Remove
		S.Pick = nil
		S.Selected = key
		S.SheetOpen = S.Mode == "Phone"
		H.refresh()
		return
	end
	local refusalSlot = armed and slot or nil
	if at then
		list[at] = list[slot]
		list[slot] = key
	else
		local busy = Bits.busyOf(key)
		if busy == "Training" then
			H.hint(H.trainingText(key), "bad")
			return
		end
		list[slot] = key
		if busy == "Garden" then
			-- ONE request takes it out and stores the team; No keeps everything as it is, pick mode armed
			local draft = H.newDraft(H.shownPreset(), list, refusalSlot)
			Bits.askRecall(U.Gui, key, { To = "Team", Preset = draft.Preset, Keys = draft.Send }, function()
				draft.Sent = true
				S.Draft = draft
				S.Pick = nil
				S.Selected = key
				S.SheetOpen = false
				H.armAnswer(draft)
				H.pop(slot)
				H.refresh()
			end, nil, function(action, arg)
				return H.fireHome("Recall", action, arg)
			end)
			return
		end
	end
	H.write(list, refusalSlot)
	S.Pick = nil
	S.Selected = key
	S.SheetOpen = false
	H.pop(slot)
	H.refresh()
end

function H.tapSlot(index)
	index = math.min(index, #H.keys() + 1)
	if S.Pick == index then
		S.Pick = nil
	else
		S.Pick = index
		S.Selected = H.keys()[index] or S.Selected
		S.SheetOpen = false
	end
	H.refresh()
end

function H.tapCard(key)
	if S.Pick then
		H.placeKey(key, S.Pick, true)
		return
	end
	S.Selected = key
	S.SheetOpen = S.Mode == "Phone"
	H.refresh()
end

function H.putInTeam()
	local key = S.Selected
	if not key or H.indexOf(key) then
		return
	end
	local count = #H.keys()
	if count >= K.SLOTS then
		S.Pick = 1
		S.SheetOpen = false
		H.refresh()
		return
	end
	H.placeKey(key, count + 1, false)
end

function H.makeFighter()
	local at = S.Selected and H.indexOf(S.Selected)
	if not at or at == 1 then
		return
	end
	local list = H.slotList()
	list[at], list[1] = list[1], list[at]
	H.write(list)
	S.SheetOpen = false
	H.pop(1)
	H.hint(Bits.displayName(S.Selected) .. " is your fighter now!", "good")
	H.refresh()
end

function H.removeSelected()
	local at = S.Selected and H.indexOf(S.Selected)
	if not at then
		return
	end
	local list = H.slotList()
	list[at] = false
	H.write(list)
	S.SheetOpen = false
	H.refresh()
end

function H.autoFill()
	local best = H.best(K.SLOTS)
	if #best == 0 then
		H.hint("You have no free pet to put in your team.", "bad")
		return
	end
	local preset = H.shownPreset()
	local previous = {}
	for i, key in ipairs(H.keys()) do
		previous[i] = key
	end
	S.Pick = nil
	H.write({ best[1] or false, best[2] or false, best[3] or false })
	H.hint("Team filled", "good")
	S.UndoId = S.UndoId + 1
	local mine = S.UndoId
	S.Undo = { Preset = preset, Keys = previous }
	task.delay(K.UNDO_SECONDS, function()
		if S.UndoId == mine then
			S.Undo = nil
			H.refreshTop()
		end
	end)
	H.refresh()
end

function H.undoFill()
	local undo = S.Undo
	if not undo then
		return
	end
	S.Undo = nil
	S.UndoId = S.UndoId + 1
	S.Draft = H.newDraft(undo.Preset, { undo.Keys[1] or false, undo.Keys[2] or false, undo.Keys[3] or false })
	H.flushDraft()
	H.refresh()
end

function H.clearTeam()
	if S.ClearArmed == 0 then
		S.ClearArmed = (S.ClearToken or 0) + 1
		S.ClearToken = S.ClearArmed
		local mine = S.ClearArmed
		task.delay(K.CLEAR_SECONDS, function()
			if S.ClearArmed == mine then
				S.ClearArmed = 0
				H.refreshTop()
			end
		end)
		H.refreshTop()
		return
	end
	S.ClearArmed = 0
	S.Pick = nil
	H.write({ false, false, false })
	H.refresh()
end

----------------------------------------------------------------------
-- Actions (today's behaviour and rules; a refusal says why at once)
----------------------------------------------------------------------
function H.careOpen(panelId)
	local key = S.Selected
	local care = H.controller("CareController")
	if not key then
		return
	end
	if not care then
		H.hint("Pet care is getting ready. Try again in a moment!", "info")
		return
	end
	if H.inMatch() then
		H.hint(panelId == "Feed" and "Pets eat at home, after the match." or "Pets are busy climbing during a match.", "info")
		return
	end
	if panelId == "Evolve" then
		safe("evolve confirm", care.ConfirmEvolve, key)
		return
	end
	-- the care window takes this one's place and comes back to it on the same pet, with what this one was given
	safe("care open", care.Open, panelId, { Key = key, ReturnTo = { Window = "Pets", Key = key, Preset = S.View, ReturnTo = S.ReturnTo } })
end

function H.doGarden()
	local key = S.Selected
	local def = key and Bits.defOfKey(key)
	if not def then
		return
	end
	if H.inMatch() then
		H.hint("Pets are busy climbing during a match.", "info")
		return
	end
	local home = Bits.homeData()
	local map = type(home.Garden) == "table" and home.Garden or {}
	local slots = Bits.catalogCall("GardenSlots", home) or 0
	local placed = Bits.slotsHolding(map, key)
	if #placed > 0 then
		H.fireHome("Garden", "GardenSet", { Slot = placed[#placed] })
		return
	end
	local job = Bits.job(key)
	if job then
		H.hint(Bits.displayName(key, def) .. " is training (" .. Bits.jobLeft(job) .. " left).", "info")
		return
	end
	if slots <= 0 then
		H.hint("Build the Pet Garden at your home first.", "info")
		return
	end
	local free = Bits.firstFreeSlot(map, slots)
	if not free then
		H.hint("Your Garden is full (" .. slots .. "/" .. slots .. "). Prestige for one more place!", "info")
		return
	end
	H.fireHome("Garden", "GardenSet", { Slot = free, Key = key })
end

----------------------------------------------------------------------
-- Building
----------------------------------------------------------------------
function H.chipButton(name, label, style, callback)
	local button = CloudUI.Button({
		Name = name,
		Text = label,
		Style = style,
		TextSize = 20,
		ZIndex = 2,
		Callback = function()
			safe(name, callback)
		end,
		Parent = U.Content,
	})
	button.TextWrapped = true
	button.TextTruncate = Enum.TextTruncate.None
	button.LineHeight = 0.92
	return button
end

function H.buildSlot(index)
	local item = { Index = index }
	local button = Util.Create("TextButton", {
		Name = "Slot" .. index,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = U.Content,
	})
	item.Button = button
	corner(button, 14)
	item.Stroke = stroke(button, NAVY, 3, 0)
	item.Gradient = Util.Create("UIGradient", { Rotation = 90, Parent = button })
	item.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = button })
	item.Face = frame(button, "Face", { ZIndex = 2 })
	-- (kit-b U6) FIGHTER / HELPER is a tag: the Tag role (Theme keeps it in capitals)
	item.Tag = text(button, "Tag", "HELPER", "Tag", 18, WHITE, { BackgroundTransparency = 0, BackgroundColor3 = HELPER_COLOR, ZIndex = 5 })
	corner(item.Tag, 8)
	stroke(item.Tag, NAVY, 2, 0)
	item.Name = text(button, "PetName", "", "Heading", 18, WHITE, { TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 })
	item.Level = text(button, "Level", "", "Heading", 18, WHITE, { TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
	item.Power = text(button, "Power", "", "Heading", 18, POWER_GOLD, { TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })
	PixelIcon.Lead(item.Power, ICON.Power) -- (kit-b U7b)
	item.Busy = text(button, "Busy", "", "Heading", 18, WHITE, {
		BackgroundTransparency = 0.35,
		BackgroundColor3 = Color3.fromRGB(12, 16, 36),
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		ZIndex = 6,
	})
	corner(item.Busy, 14)
	item.Empty = text(button, "Empty", "Empty", "Heading", 20, MUTED, {
		Size = UDim2.new(1, -8, 1, 0),
		Position = UDim2.fromOffset(4, 0),
		TextWrapped = true,
		ZIndex = 4,
	})
	item.Glow = frame(button, "Glow", { Position = UDim2.fromOffset(-3, -3), Size = UDim2.new(1, 6, 1, 6), Visible = false, ZIndex = 7 })
	corner(item.Glow, 16)
	stroke(item.Glow, GOLD, 4, 0)
	button.Activated:Connect(function()
		safe("slot", H.tapSlot, index)
	end)
	U.Slots[index] = item
	return item
end

function H.buildCard(key)
	local item = { Key = key }
	local button = Util.Create("TextButton", {
		Name = "Card_" .. key,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		BackgroundColor3 = WHITE,
		Parent = U.Grid,
	})
	item.Button = button
	corner(button, 12)
	item.Rarity = stroke(button, NAVY, 3, 0)
	item.Rarity.Name = "Rarity"
	item.Gradient = Util.Create("UIGradient", { Rotation = 90, Parent = button })
	item.Picture = frame(button, "Picture", { ZIndex = 2 })
	item.Name = text(button, "Name", "", "Body", 18, WHITE, { TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 })
	item.Level = text(button, "Level", "", "Heading", 18, WHITE, { TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
	item.Power = text(button, "Power", "", "Heading", 18, POWER_GOLD, { TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 })
	PixelIcon.Lead(item.Power, ICON.Power) -- (kit-b U7b)
	item.Element = text(button, "Element", "", "Button", 18, WHITE, { BackgroundTransparency = 0, ZIndex = 4 })
	round(item.Element)
	stroke(item.Element, NAVY, 2, 0)
	item.Number = text(button, "Number", "", "Button", 18, WHITE, { BackgroundTransparency = 0, BackgroundColor3 = GOOD, Visible = false, ZIndex = 6 })
	round(item.Number)
	stroke(item.Number, NAVY, 2.5, 0)
	item.Tier = frame(button, "Tier", { BackgroundTransparency = 0, BackgroundColor3 = WHITE, Visible = false, ZIndex = 5 })
	round(item.Tier)
	stroke(item.Tier, NAVY, 2, 0)
	item.TierMark = text(item.Tier, "Mark", "", "Button", 18, WHITE, { Size = UDim2.new(1, 0, 1, 0), ZIndex = 6 })
	item.Stars = text(button, "Stars", "", "Title", 18, GOLD, { Visible = false, ZIndex = 5 })
	item.Count = text(button, "Count", "", "Heading", 18, WHITE, { TextXAlignment = Enum.TextXAlignment.Right, Visible = false, ZIndex = 4 })
	item.Busy = text(button, "Busy", "", "Heading", 18, WHITE, {
		BackgroundTransparency = 0.35,
		BackgroundColor3 = Color3.fromRGB(12, 16, 36),
		TextWrapped = true,
		Visible = false,
		ZIndex = 7,
	})
	corner(item.Busy, 12)
	button.Activated:Connect(function()
		safe("card", H.tapCard, key)
	end)
	U.Cards[key] = item
	H.layoutCard(item)
	return item
end

function H.buildDetail()
	local d = {}
	U.D = d
	d.Frame = frame(U.Content, "Detail", { BackgroundTransparency = 0.1, BackgroundColor3 = INSET_COLOR, Active = true, ZIndex = 20 })
	corner(d.Frame, 14)
	d.Stroke = stroke(d.Frame, Colors.WellEdge or NAVY, 3, 0.15)
	d.Hint = text(d.Frame, "Hint", "Pick a pet to see its details.", "Body", 19, MUTED, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, -40, 0, 60),
		TextWrapped = true,
		ZIndex = 21,
	})
	d.Glow = frame(d.Frame, "Glow", { BackgroundTransparency = 0.78, BackgroundColor3 = GOLD, ZIndex = 21 })
	round(d.Glow)
	d.Picture = frame(d.Frame, "Picture", { ZIndex = 22 })
	d.Name = text(d.Frame, "Name", "", "Title", 30, WHITE, { TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 21 })
	d.Meta = text(d.Frame, "Meta", "", "Body", 19, Color3.fromRGB(201, 212, 234), { TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 21 })
	d.Xp = CloudUI.Bar({ Name = "XpBar", Height = 26, TextSize = 18, Color = XP_COLOR, Parent = d.Frame })
	d.Xp.Root.ZIndex = 21
	for _, row in ipairs(ROWS) do
		local holder = frame(d.Frame, "Row_" .. row[1], { ZIndex = 21 })
		local label = text(holder, "Label", row[2], "Body", 18, Color3.fromRGB(201, 212, 234), { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 })
		local value = text(holder, "Value", "", "Heading", 19, ROW_COLORS[row[1]], { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 22 })
		U.Rows[row[1]] = { Frame = holder, Label = label, Value = value }
	end
	d.Work = text(d.Frame, "Work", "", "Heading", 18, Theme.Lighten(GOOD, 0.35), {
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 21,
	})
	d.Perks = text(d.Frame, "Perks", "", "Body", 18, Theme.Lighten(GOOD, 0.3), {
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 21,
	})
	local function action(name, label, style, callback)
		local button = CloudUI.Button({
			Name = name,
			Text = label,
			Style = style,
			TextSize = 22,
			ZIndex = 23,
			Callback = function()
				safe(name, callback)
			end,
			Parent = d.Frame,
		})
		button.TextWrapped = true
		button.TextTruncate = Enum.TextTruncate.None
		button.LineHeight = 0.92
		d[name] = button
		return button
	end
	action("ActPut", "Put in team", "Green", H.putInTeam)
	action("ActFighter", "Make fighter", "Red", H.makeFighter)
	action("ActRemove", "Remove", "Pink", H.removeSelected)
	action("ActFeed", "Feed", "Gold", function()
		H.careOpen("Feed")
	end)
	action("ActTrain", "Train", "Red", function()
		H.careOpen("Train")
	end)
	action("ActGarden", "Garden", "Blue", H.doGarden)
	action("ActEvolve", "Evolve", "Gold", function()
		H.careOpen("Evolve")
	end)
	d.Close = CloudUI.Button({
		Name = "SheetClose",
		Text = "",
		Style = "Red",
		TextSize = 22,
		ZIndex = 23,
		Callback = function()
			S.SheetOpen = false
			H.refresh()
		end,
		Parent = d.Frame,
	})
	NeonKit.CloseMark(d.Close) -- slop audit 2026-11-12: a drawn X (no "X" letter, no glyph)
end

function H.build()
	if S.Built then
		return
	end
	S.Built = true
	U.Holder = frame(U.Gui, "Window_Pets", { Visible = false, ZIndex = 3 })
	U.Fit = Util.Create("UIScale", { Name = "Fit", Scale = 1, Parent = U.Holder })
	U.Panel = CloudUI.Panel({
		Name = "PetsWindow",
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Title = "Pets",
		Closable = true,
		Category = "Pets",
		Accent = Theme.Neon.Orange,
		OnClose = function()
			PetsController.Close()
		end,
		Parent = U.Holder,
	})
	U.Pop = Util.Create("UIScale", { Name = "Pop", Scale = 1, Parent = U.Panel.Root })
	U.Content = U.Panel.Content
	U.Content.BackgroundTransparency = 1
	for i = 1, K.SLOTS do
		H.buildSlot(i)
	end
	U.TeamPower = text(U.Content, "TeamPower", "", "Heading", 28, POWER_GOLD, { TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2 })
	U.Breakdown = text(U.Content, "TeamBreakdown", "", "Body", 18, Color3.fromRGB(201, 212, 234), {
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 2,
	})
	U.AutoFill = H.chipButton("AutoFill", "Auto-fill best", "Blue", H.autoFill)
	U.Clear = H.chipButton("ClearTeam", "Clear", "Gray", H.clearTeam)
	U.Undo = H.chipButton("Undo", "Undo", "Gold", H.undoFill)
	U.Undo.Visible = false
	U.Undo.ZIndex = 3
	U.Presets = {}
	for i = 1, K.PRESETS do
		local letter = string.sub("ABC", i, i)
		U.Presets[i] = H.chipButton("Preset" .. letter, letter, "Gray", function()
			H.selectTeam(i)
		end)
	end
	U.Well = frame(U.Content, "GridWell", { BackgroundTransparency = 0.42, BackgroundColor3 = INSET_COLOR, ZIndex = 2 })
	corner(U.Well, 12)
	U.WellStroke = stroke(U.Well, Colors.WellEdge or NAVY, 3, 0.15)
	U.Grid = CloudUI.Grid(U.Well, UDim2.fromOffset(116, 170), UDim2.fromOffset(8, 8))
	U.Grid.Name = "Grid"
	U.Grid.ZIndex = 3
	U.GridLayout = U.Grid:FindFirstChild("Layout")
	U.GridPad = U.Grid:FindFirstChildWhichIsA("UIPadding")
	U.Sort = H.chipButton("SortButton", "Strongest", "Blue", function()
		for i, mode in ipairs(K.SORTS) do
			if mode == S.Sort then
				PetsController.SetSort(K.SORTS[i % #K.SORTS + 1])
				return
			end
		end
	end)
	U.Banner = text(U.Content, "PickBanner", "", "Heading", 20, GOLD, {
		BackgroundTransparency = 0.1,
		BackgroundColor3 = INSET_COLOR,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 9,
	})
	corner(U.Banner, 10)
	stroke(U.Banner, GOLD, 2, 0)
	U.PickCancel = H.chipButton("PickCancel", G.Close, "Red", function()
		S.Pick = nil
		H.refresh()
	end)
	U.PickCancel.Visible = false
	U.PickCancel.ZIndex = 10
	U.Empty = frame(U.Well, "Empty", { Size = UDim2.new(1, 0, 1, 0), Visible = false, ZIndex = 5 })
	U.EmptyTitle = text(U.Empty, "Title", "No pets yet!", "Title", 26, WHITE, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.5, -34),
		Size = UDim2.new(1, -24, 0, 34),
		ZIndex = 6,
	})
	U.EmptyBody = text(U.Empty, "Body", "", "Body", 18, MUTED, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -8),
		Size = UDim2.new(1, -24, 0, 44),
		TextWrapped = true,
		ZIndex = 6,
	})
	U.EmptyButton = CloudUI.Button({
		Name = "OpenShop",
		Text = "Open Shop",
		Style = "Gold",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 20),
		Size = UDim2.fromOffset(200, 48),
		TextSize = 20,
		ZIndex = 7,
		Callback = function()
			local menu = H.controller("MenuController")
			if menu then
				-- lobby shop 16.3 (Task 23): the Shop's Eggs tab (a bare open would show the session's last tab)
				safe("shop", menu.Open, "Shop", { Tab = "Eggs" })
			end
		end,
		Parent = U.Empty,
	})
	H.buildDetail()
	local mouseLock = Client:FindFirstChild("MouseLock")
	if mouseLock then
		local ok, mod = pcall(require, mouseLock)
		if ok and type(mod) == "table" and type(mod.WatchVisible) == "function" then
			safe("mouse lock", mod.WatchVisible, "Dock:" .. U.Holder.Name, U.Holder)
		end
	end
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------
function H.viewport()
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize
	if vp and vp.X > 2 and vp.Y > 2 then
		return vp.X, vp.Y
	end
	return 1280, 720
end

function H.rect()
	local w, h = H.viewport()
	local inset = 58
	pcall(function()
		inset = GuiService:GetGuiInset().Y
	end)
	local R = K.RECT
	local t = math.max(0, math.min(1, (h - R.H0) / (R.H1 - R.H0)))
	local factor = Theme.ScreenFactor(h)
	local big = math.max(1, factor)
	local pxW = math.min((R.W0 + (R.W1 - R.W0) * t) * big, w - 2 * K.MARGIN)
	if w > h and h >= K.PC_MIN_H then
		pxW = math.min(pxW, w * K.PC_MAX_W) -- the menu tiles and the currency pills stay free
	end
	local pxH = math.min((R.Y0 + (R.Y1 - R.Y0) * t) * big, h - inset - 2)
	local phone = pxW / factor < K.PHONE_W or pxH / factor < K.SHORT
	local scale = phone and 1 or factor
	return {
		x = math.floor((w - pxW) / 2 + 0.5),
		y = math.floor(inset + (h - inset - pxH) / 2 + 0.5),
		w = pxW,
		h = pxH,
		scale = scale,
		mode = phone and "Phone" or "PC",
		portrait = pxH > pxW,
	}
end

function H.layoutCard(item)
	local phone = S.Mode == "Phone"
	local w, h = (phone and K.PHONE_CARD or K.PC_CARD)[1], (phone and K.PHONE_CARD or K.PC_CARD)[2]
	local fs = phone and 15 or 18
	for _, label in ipairs({ item.Level, item.Power, item.Name, item.Count, item.Busy, item.Number, item.Stars }) do
		label.TextSize = fs
	end
	if phone then
		place(item.Picture, 2, 2, w - 4, 80)
		place(item.Level, 6, 84, 44, 22)
		place(item.Power, 4, 106, w - 10, 22)
		item.Name.Visible = false
	else
		place(item.Picture, 2, 2, w - 4, 94)
		place(item.Level, 6, 72, 52, 24)
		place(item.Name, 4, 96, w - 8, 42)
		place(item.Power, 4, 142, w - 10, 24)
		item.Name.Visible = true
	end
	item.Element.TextSize = fs
	item.TierMark.TextSize = fs
	place(item.Element, w - 30, 4, 26, 26)
	place(item.Number, 4, 4, 26, 26)
	place(item.Tier, 4, 34, 26, 26)
	place(item.Stars, w / 2 - 18, 2, 36, 22)
	place(item.Count, w - 44, phone and 84 or 74, 40, 22)
	place(item.Busy, 0, 0, w, phone and 82 or 96)
	item.Busy.TextWrapped = true
end

-- the slot's parts: a square on PC, a short wide card on a phone
function H.layoutSlot(item, w, h)
	local phone = S.Mode == "Phone"
	local fs = phone and 15 or 18
	for _, label in ipairs({ item.Tag, item.Name, item.Level, item.Power, item.Busy }) do
		label.TextSize = fs
	end
	item.Empty.TextSize = phone and 16 or 20
	if phone then
		place(item.Tag, 4, 4, 70, 22)
		place(item.Face, w - 58, 2, 56, math.min(56, h - 26))
		place(item.Level, 8, 28, 52, 22)
		place(item.Power, 6, h - 24, w - 12, 22)
		item.Name.Visible = false
	else
		place(item.Tag, 6, 6, 92, 26)
		place(item.Face, 14, 26, w - 28, h - 26 - 54)
		place(item.Name, 6, h - 54, w - 12, 24)
		place(item.Level, 8, h - 30, 50, 26)
		place(item.Power, 50, h - 30, w - 58, 26)
		item.Name.Visible = true
	end
end

-- design px of a tap target: the PC layout runs under a UIScale, 0.8 on a small screen or a tablet
function H.touchSize()
	return math.max(K.TOUCH, math.ceil(K.TOUCH / S.Scale))
end

-- the four rows in two columns. On PC the right column is the wider one under the full detail's width: 'Battle power' is the long
-- label there and a pet's power the long number.
function H.placeRows(x, y, totalW, rowH, gap, phone)
	local leftW = math.floor((totalW - gap) / 2)
	local rightW = leftW
	if not phone and totalW < K.WIDE_ROWS_W then
		leftW = math.floor((totalW - gap) * 0.41)
		rightW = totalW - gap - leftW
	end
	for i, row in ipairs(ROWS) do
		local right, line = (i - 1) % 2 == 1, math.floor((i - 1) / 2)
		place(U.Rows[row[1]].Frame, right and x + leftW + gap or x, y + line * rowH, right and rightW or leftW, rowH)
	end
end

function H.layoutDetail(w, h)
	local d = U.D
	local phone = S.Mode == "Phone"
	local narrow = w < 420
	local pad = phone and 10 or 14
	local fs = phone and 15 or 18
	d.Name.TextSize = phone and 22 or 30
	d.Meta.TextSize = fs
	d.Work.TextSize = fs
	d.Perks.TextSize = fs
	for _, row in pairs(U.Rows) do
		row.Label.TextSize = fs
		row.Value.TextSize = phone and 15 or 19
	end
	d.Xp.Root.Parent = d.Frame
	local buttonH = phone and 48 or math.max(h < 560 and 52 or 58, H.touchSize())
	local gap = phone and 6 or 8
	local bottomY = h - pad - buttonH
	d.ButtonH, d.Gap, d.BottomY, d.CareY = buttonH, gap, bottomY, bottomY - gap - buttonH
	local textW = w - 2 * pad
	local y
	if phone or h < 560 then
		-- the pet beside its name
		local pic = phone and (narrow and 96 or 120) or 96
		place(d.Glow, pad + 4, 12, pic - 8, pic - 8)
		place(d.Picture, pad, 8, pic, pic)
		local x = pad + pic + 8
		local nameW = w - x - pad - (phone and 50 or 0)
		place(d.Name, x, 6, nameW, phone and 28 or 34)
		place(d.Meta, x, phone and 36 or 42, w - x - pad - (phone and narrow and 50 or 0), 22)
		d.Meta.TextWrapped = narrow
		place(d.Xp.Root, x, phone and 60 or 68, w - x - pad, 24)
		y = phone and 88 or 108
		if narrow then
			y = pic + 14
		end
		local rowX = (narrow or not phone) and pad or x
		H.placeRows(rowX, y, w - rowX - pad, 24, 8, phone)
		y = y + 2 * 24 + 2
		if phone and not narrow then
			y = math.max(y, pic + 12)
		end
	else
		-- the pet on top
		local pic = h >= 620 and 170 or 130
		place(d.Glow, math.floor(w / 2 - pic / 2) + 8, 12, pic - 16, pic - 16)
		place(d.Picture, math.floor(w / 2 - pic / 2), 4, pic, pic)
		y = pic + 6
		place(d.Name, pad, y, textW, 36)
		place(d.Meta, pad, y + 38, textW, 24)
		d.Meta.TextWrapped = false
		place(d.Xp.Root, pad, y + 66, textW, 26)
		y = y + 98
		H.placeRows(pad, y, textW, 28, 12, phone)
		y = y + 2 * 28 + 4
	end
	d.TextY = y
	d.TextW = textW
	d.Pad = pad
	d.W = w
	if phone then
		place(d.Close, w - 50, 6, 44, 44)
	end
	d.Close.Visible = phone
	H.placeActions()
end

-- the actions along the bottom: team row at the very bottom on a phone, on top of the care row on PC
function H.placeActions()
	local d = U.D
	if not d or not d.W then
		return
	end
	local phone = S.Mode == "Phone"
	local pad, gap, w = d.Pad, d.Gap, d.W
	local innerW = w - 2 * pad
	local teamY = phone and d.BottomY or d.BottomY - 2 * (d.ButtonH + gap)
	local careY = phone and d.CareY or nil
	local fs = phone and 16 or 22
	local inTeam = d.InTeam
	local isFighter = d.IsFighter
	d.ActPut.Visible = not inTeam
	d.ActFighter.Visible = inTeam == true and not isFighter
	d.ActRemove.Visible = inTeam == true
	place(d.ActPut, pad, teamY, innerW, d.ButtonH)
	if isFighter then
		place(d.ActRemove, pad, teamY, innerW, d.ButtonH)
	else
		local half = math.floor((innerW - gap) / 2)
		place(d.ActFighter, pad, teamY, half, d.ButtonH)
		place(d.ActRemove, pad + half + gap, teamY, half, d.ButtonH)
	end
	local list = { d.ActFeed, d.ActTrain, d.ActGarden }
	if d.ActEvolve.Visible then
		list[4] = d.ActEvolve
	end
	if phone then
		local cellW = math.floor((innerW - (#list - 1) * gap) / #list)
		for i, button in ipairs(list) do
			place(button, pad + (i - 1) * (cellW + gap), careY, cellW, d.ButtonH)
		end
	else
		-- Feed | Train, Garden | Evolve (Garden takes the whole row while there is no Evolve)
		local half = math.floor((innerW - gap) / 2)
		local y1, y2 = teamY + d.ButtonH + gap, teamY + 2 * (d.ButtonH + gap)
		place(d.ActFeed, pad, y1, half, d.ButtonH)
		place(d.ActTrain, pad + half + gap, y1, half, d.ButtonH)
		if d.ActEvolve.Visible then
			place(d.ActGarden, pad, y2, half, d.ButtonH)
			place(d.ActEvolve, pad + half + gap, y2, half, d.ButtonH)
		else
			place(d.ActGarden, pad, y2, innerW, d.ButtonH)
		end
	end
	for _, button in ipairs({ d.ActPut, d.ActFighter, d.ActRemove, d.ActFeed, d.ActTrain, d.ActGarden, d.ActEvolve }) do
		button.TextSize = fs
	end
	local bottomText = (phone and d.CareY or teamY) - gap
	local workH = d.Work.Text ~= "" and (phone and 20 or 24) * (d.WorkLines or 1) or 0
	place(d.Work, pad, d.TextY, d.TextW, workH)
	d.Work.Visible = workH > 0 and d.TextY + workH <= bottomText
	local perksY = d.TextY + workH + 2
	local perksH = bottomText - perksY
	place(d.Perks, pad, perksY, d.TextW, math.max(0, perksH))
	d.PerksH = perksH
	d.PerkLineH = phone and 18 or 22
end

function H.gridPad(px)
	if U.GridPad then
		U.GridPad.PaddingLeft = UDim.new(0, px)
		U.GridPad.PaddingRight = UDim.new(0, px)
		U.GridPad.PaddingTop = UDim.new(0, px)
		U.GridPad.PaddingBottom = UDim.new(0, px)
	end
end

function H.layoutPC(W, H0)
	local x0, gap = 20, 8
	local slot = math.max(116, math.min(168, math.floor(H0 * 0.19)))
	local top = 4
	local presetW, buttonW = 192, W >= K.WIDE_W and 190 or 160
	local right = W - x0
	local presetX = right - presetW
	local buttonX = presetX - 12 - buttonW
	local powerX = x0 + 3 * (slot + gap) + 4
	local powerW = buttonX - 12 - powerX
	-- a tablet has no room for Team power between the slots and the two button columns: power and breakdown go on top, the buttons
	-- in one row under them, and the slots give up what that row still lacks
	local stacked = powerW < K.POWER_W
	U.TopStacked = stacked
	if stacked then
		slot = math.max(116, math.min(slot, math.floor((right - K.STACK_W - 4 - x0) / 3) - gap))
		powerX = x0 + 3 * (slot + gap) + 4
		powerW = right - powerX
	end
	for i, item in ipairs(U.Slots) do
		place(item.Button, x0 + (i - 1) * (slot + gap), top, slot, slot)
		H.layoutSlot(item, slot, slot)
		item.Tag.Visible = true
	end
	U.Breakdown.Visible = true
	U.AutoFill.TextSize, U.Clear.TextSize, U.Undo.TextSize = 22, 20, 22
	if stacked then
		local barY = top + slot - 60
		local clearW = K.STACK_CLEAR_W
		local clearX = presetX - 8 - clearW
		U.TeamPower.TextSize = 28
		place(U.TeamPower, powerX, top, powerW, 34)
		place(U.Breakdown, powerX, top + 34, powerW, barY - top - 34 - 2)
		place(U.AutoFill, powerX, barY, clearX - 8 - powerX, 60)
		U.AutoFill.TextSize = 20
		place(U.Clear, clearX, barY, clearW, 60)
		place(U.Undo, clearX, barY, clearW, 60)
		for i, button in ipairs(U.Presets) do
			place(button, presetX + (i - 1) * 66, barY, 60, 60)
			button.TextSize = 26
		end
	else
		U.TeamPower.TextSize = powerW >= 250 and 28 or 24
		place(U.TeamPower, powerX, top + 8, powerW, 36)
		place(U.Breakdown, powerX, top + 50, powerW, slot - 54)
		place(U.AutoFill, buttonX, top + 8, buttonW, 60)
		place(U.Clear, buttonX, top + 80, buttonW, 60)
		for i, button in ipairs(U.Presets) do
			place(button, presetX + (i - 1) * 66, top + 8, 60, 60)
			button.TextSize = 26
		end
		place(U.Undo, presetX, top + 80, presetW, 60)
	end
	-- the well and the detail below
	local bodyY = top + slot + 14
	local bodyH = H0 - 62 - bodyY - 16
	local detailW = W >= K.WIDE_W and 425 or 360
	local wellW = W - 2 * x0 - detailW - 15
	place(U.Well, x0, bodyY, wellW, bodyH)
	U.Well.Visible = true
	local tap = H.touchSize()
	local cancelW = math.max(46, tap)
	place(U.Sort, x0 + 14, bodyY + 10, 150, tap)
	U.Sort.TextSize = 20
	place(U.Banner, x0 + 172, bodyY + 10, wellW - 172 - cancelW - 20, tap)
	U.Banner.TextSize = 20
	place(U.PickCancel, x0 + wellW - 14 - cancelW, bodyY + 10, cancelW, tap)
	U.PickCancel.TextSize = 24
	place(U.Grid, 8, 16 + tap, wellW - 16, bodyH - 24 - tap)
	place(U.D.Frame, W - x0 - detailW, bodyY, detailW, bodyH)
	U.D.Frame.Name = "Detail"
	H.layoutDetail(detailW, bodyH)
	U.GridLayout.CellSize = UDim2.fromOffset(K.PC_CARD[1], K.PC_CARD[2])
	U.GridLayout.CellPadding = UDim2.fromOffset(K.PC_CARD[3], K.PC_CARD[3])
	H.gridPad(6)
	U.Grid.ScrollBarThickness = 10
end

function H.layoutPhone(W, H0)
	local x0 = 10
	local closeW = 44
	local top = 4
	local chipH = 44
	local gridX, gridY, gridW, gridH
	local sheetX, sheetY, sheetW, sheetH
	if S.Portrait then
		-- the slots in a row under the controls, the grid below them
		place(U.Presets[1], 110, top, 46, chipH)
		place(U.Presets[2], 160, top, 46, chipH)
		place(U.Presets[3], 210, top, 46, chipH)
		local rowY = top + chipH + 4
		local cell = math.floor((W - 2 * x0 - 2 * 6) / 3)
		place(U.Sort, x0, rowY, cell, chipH)
		place(U.AutoFill, x0 + cell + 6, rowY, cell, chipH)
		place(U.Clear, x0 + 2 * (cell + 6), rowY, cell, chipH)
		place(U.Undo, x0 + 2 * (cell + 6), rowY, cell, chipH)
		place(U.TeamPower, x0, rowY + chipH + 2, W - 2 * x0, 22)
		local slotY = rowY + chipH + 26
		local slotW = cell
		for i, item in ipairs(U.Slots) do
			place(item.Button, x0 + (i - 1) * (slotW + 6), slotY, slotW, 92)
			H.layoutSlot(item, slotW, 92)
		end
		place(U.Banner, x0, rowY, W - 2 * x0 - 52, chipH)
		place(U.PickCancel, W - x0 - 46, rowY, 46, chipH)
		gridX, gridY = 6, slotY + 92 + 6
		gridW, gridH = W - 12, H0 - gridY - 6
		sheetX, sheetY, sheetW, sheetH = 6, gridY, W - 12, gridH
	else
		-- the slots in a column on the left, the controls on the top row
		local slotH = math.floor((H0 - 42 - 6 - 2 * 4) / 3)
		for i, item in ipairs(U.Slots) do
			place(item.Button, x0, 42 + (i - 1) * (slotH + 4), 128, slotH)
			H.layoutSlot(item, 128, slotH)
		end
		local x = x0 + 128 + 8
		for i, button in ipairs(U.Presets) do
			place(button, x + (i - 1) * 50, top, 46, chipH)
		end
		x = x + 3 * 50
		-- the chips share what is left before the close button (a 16:9 phone is under 660 design px wide)
		local chips = K.PHONE_CHIPS
		local fit = math.min(1, (W - closeW - 12 - x - 2 * 4) / (chips[1] + chips[2] + chips[3]))
		local sortW, fillW, clearW = math.floor(chips[1] * fit), math.floor(chips[2] * fit), math.floor(chips[3] * fit)
		place(U.Sort, x, top, sortW, chipH)
		x = x + sortW + 4
		place(U.AutoFill, x, top, fillW, chipH)
		x = x + fillW + 4
		place(U.Clear, x, top, clearW, chipH)
		place(U.Undo, x, top, clearW, chipH)
		x = x + clearW + 4
		local powerW = W - closeW - 8 - x
		U.PhonePowerRoom = powerW >= 100
		place(U.TeamPower, x, top, math.max(0, powerW), chipH)
		local bannerX = x0 + 128 + 8
		place(U.Banner, bannerX, top, W - closeW - 8 - bannerX - 52, chipH)
		place(U.PickCancel, W - closeW - 8 - 48, top, 46, chipH)
		gridX, gridY = bannerX, 52
		gridW, gridH = W - bannerX - 6, H0 - 58
		sheetX, sheetY, sheetW, sheetH = bannerX, 4, W - bannerX - 6, H0 - 8
	end
	U.TeamPower.TextSize = 15
	U.Breakdown.Visible = false
	for _, button in ipairs(U.Presets) do
		button.TextSize = 18
	end
	U.Sort.TextSize, U.AutoFill.TextSize, U.Clear.TextSize, U.Undo.TextSize = 15, 15, 15, 16
	U.Banner.TextSize = 16
	U.PickCancel.TextSize = 22
	-- the grid fills the well; the well is the grid's own frame here
	place(U.Well, gridX, gridY, gridW, gridH)
	U.Well.BackgroundTransparency = 1
	U.WellStroke.Enabled = false
	place(U.Grid, 0, 0, gridW, gridH)
	U.GridLayout.CellSize = UDim2.fromOffset(K.PHONE_CARD[1], K.PHONE_CARD[2])
	U.GridLayout.CellPadding = UDim2.fromOffset(K.PHONE_CARD[3], K.PHONE_CARD[3])
	H.gridPad(2)
	U.Grid.ScrollBarThickness = 6
	place(U.D.Frame, sheetX, sheetY, sheetW, sheetH)
	U.D.Frame.Name = "Sheet"
	H.layoutDetail(sheetW, sheetH)
end

function H.layout()
	if not S.Built then
		return
	end
	local r = H.rect()
	local modeChanged = S.Mode ~= r.mode or S.Portrait ~= r.portrait or S.Laid == nil
	S.Mode, S.Portrait, S.Scale = r.mode, r.portrait, r.scale
	local W, H0 = r.w / r.scale, r.h / r.scale
	U.Holder.AnchorPoint = Vector2.new(0, 0)
	U.Holder.Position = UDim2.fromOffset(r.x, r.y)
	U.Holder.Size = UDim2.fromOffset(math.floor(W + 0.5), math.floor(H0 + 0.5))
	U.Fit.Scale = r.scale
	local key = table.concat({ math.floor(W + 0.5), math.floor(H0 + 0.5), r.mode, tostring(r.portrait), math.floor(r.scale * 100) }, "|")
	if S.Laid == key then
		H.coverColumn(r)
		return
	end
	S.Laid = key
	W, H0 = math.floor(W + 0.5), math.floor(H0 + 0.5)
	-- the panel's frame: the content takes the whole window; the title sits over its top-left corner
	local panel = U.Panel
	local phone = r.mode == "Phone"
	U.Content.Position = UDim2.fromOffset(0, phone and 0 or 62)
	U.Content.Size = UDim2.new(1, 0, 1, phone and 0 or -62)
	if panel.TitleBar then
		panel.TitleBar.Position = UDim2.fromOffset(phone and 2 or 12, phone and 2 or 6)
		panel.TitleBar.Size = phone and UDim2.fromOffset(S.Portrait and 104 or 134, 38) or UDim2.new(1, -24, 0, 50)
		panel.TitleLabel.TextSize = phone and 24 or 34
		U.TitleSize = U.TitleSize or panel.TitleLabel.Size
		panel.TitleLabel.Size = phone and UDim2.new(1, -8, 1, 0) or U.TitleSize
	end
	if panel.CloseButton then
		local size = phone and K.TOUCH or H.touchSize()
		panel.CloseButton.Size = UDim2.fromOffset(size, size)
		panel.CloseButton.AnchorPoint = Vector2.new(0, 0)
		panel.CloseButton.Position = phone and UDim2.new(1, -(size + 6), 0, 4) or UDim2.new(1, -(size + 16), 0, 8)
	end
	U.Well.BackgroundTransparency = 0.42
	U.WellStroke.Enabled = true
	if phone then
		H.layoutPhone(W, H0)
	else
		H.layoutPC(W, H0)
	end
	if modeChanged then
		for _, item in pairs(U.Cards) do
			H.layoutCard(item)
		end
	end
	H.coverColumn(r)
end

-- The phone window fills the screen and a tablet's reaches them: Roblox's thumbstick and jump button would sit over slot 3
-- and the cards, or the Detail's buttons. They go while it is up and come back as they were: MenuController keeps ONE
-- owner set for every window (re-review 2: the Store opened over this window, or this one over the Store, lays out
-- before WindowOpened closes the other, so a snapshot per window would bring back the other's false).
function H.syncTouch()
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local want = S.Open and (S.Mode == "Phone" or touchOnly)
	if want == S.TouchOff then
		return
	end
	S.TouchOff = want
	local menu = H.controller("MenuController")
	if menu and type(menu.SetTouchHidden) == "function" then
		safe("touch", menu.SetTouchHidden, "Pets", want)
		return
	end
	pcall(function()
		if want then
			S.TouchWas = GuiService.TouchControlsEnabled
			GuiService.TouchControlsEnabled = false
		else
			GuiService.TouchControlsEnabled = S.TouchWas ~= false
		end
	end)
end

-- a window that reaches over the menu tiles (phones, tablets) hides them while it is open
function H.coverColumn(r)
	local menu = H.controller("MenuController")
	if menu and type(menu.SetColumnCovered) == "function" then
		safe("cover", menu.SetColumnCovered, S.Open and r and r.x or nil)
	end
	H.syncTouch()
end

----------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------
function H.teamEntries(keys)
	local entries = {}
	for _, key in ipairs(keys) do
		local def = Bits.defOfKey(key)
		if def and not Bits.busyOf(key) then
			entries[#entries + 1] = Bits.battleEntry(key, def, (Bits.petLevel(key)))
		end
	end
	return entries
end

function H.refreshSlots(keys)
	local fighterSeen = false
	for i, item in ipairs(U.Slots) do
		local key = keys[i]
		local def = key and Bits.defOfKey(key) or nil
		local busy = key and Bits.busyOf(key) or nil
		local fighter = false
		if key and not busy and not fighterSeen then
			fighter, fighterSeen = true, true
		elseif not key and i == 1 then
			fighter = true
		end
		item.Tag.Text = fighter and "FIGHTER" or "HELPER"
		item.Tag.BackgroundColor3 = fighter and FIGHTER_COLOR or HELPER_COLOR
		local tint = def and CloudUI.RarityColor(def.Rarity) or Color3.fromRGB(70, 92, 150)
		item.Gradient.Color = ColorSequence.new(Theme.Lighten(INSET_COLOR, 0.28):Lerp(tint, 0.35), Theme.Darken(INSET_COLOR, 0.1):Lerp(tint, 0.18))
		item.Stroke.Color = def and Theme.Lighten(tint, 0.15) or NAVY
		item.Empty.Visible = def == nil
		item.Empty.Text = S.Pick == i and "Tap a pet" or "Empty"
		item.Level.Visible = def ~= nil and not (busy and S.Mode == "Phone")
		item.Power.Visible = def ~= nil
		item.Face.Visible = def ~= nil
		item.Name.Visible = def ~= nil and S.Mode == "PC"
		item.Glow.Visible = S.Pick == i
		item.Busy.Visible = busy ~= nil
		item.Busy.Text = busy == "Training" and "Training" or (busy and "Gardening" or "")
		PixelIcon.Mark(item.Busy, busy == "Training" and ICON.Training or (busy and ICON.Garden or nil)) -- (kit-b U7b)
		local stage = def and Bits.stage(key) or 0
		local viewKey = def and (key .. "|" .. stage) or nil
		if item.ViewKey ~= viewKey then
			if item.Viewport then
				item.Viewport.Destroy()
				item.Viewport = nil
			end
			item.ViewKey = viewKey
			if def then
				local ok, handle = pcall(CloudUI.PetViewport, item.Face, def, UDim2.new(1, 0, 1, 0), {
					Spin = "sway",
					Animate = true,
					Detail = stage >= 1 and "Low" or "High",
					Evolved = stage >= 1 and stage or nil,
					ZIndex = 2,
				})
				if ok then
					item.Viewport = handle
				end
			end
		end
		if def then
			local level = Bits.petLevel(key)
			item.Name.Text = Bits.displayName(key, def)
			item.Level.Text = "L" .. level
			item.Power.Text = commas(H.powerOf(key))
		end
	end
end

function H.refreshTop()
	if not S.Built then
		return
	end
	local keys = H.keys()
	local entries = H.teamEntries(keys)
	local battle = Bits.battleCatalog()
	local power = 0
	if battle then
		local ok, p = pcall(battle.TeamPower, entries)
		power = ok and tonumber(p) or 0
	end
	U.TeamPower.Text = "Team power " .. commas(power)
	local phone = S.Mode == "Phone"
	local picking = S.Pick ~= nil
	U.TeamPower.Visible = not (phone and picking and not S.Portrait) and (S.Portrait or not phone or U.PhonePowerRoom == true)
	if #entries == 0 then
		U.Breakdown.Text = #keys == 0 and "Tap a slot, then a pet. The fighter battles, two helpers back it up." or "Your whole team is busy: training or gardening."
	else
		local parts = "Fighter " .. commas(H.powerOf(entries[1].Key))
		local helpers = {}
		for i = 2, #entries do
			helpers[#helpers + 1] = commas(H.powerOf(entries[i].Key))
		end
		if #helpers > 0 then
			parts = parts .. " + " .. (#helpers > 1 and "helpers " or "helper ") .. table.concat(helpers, ", ")
		end
		local bonus = nil
		if battle and type(battle.SynergyBonus) == "function" then
			local ok, syn = pcall(battle.SynergyBonus, entries)
			bonus = ok and type(syn) == "table" and type(syn.Entries) == "table" and #syn.Entries > 0
		end
		U.Breakdown.Text = parts .. (bonus and " + team bonus" or "")
	end
	local active, shown = H.activePreset(), H.shownPreset()
	for i, button in ipairs(U.Presets) do
		button:SetAttribute("Selected", i == active)
		button:SetAttribute("Shown", i == shown)
		CloudUI.SetStyle(button, i == active and "Blue" or (i == shown and "Gold" or "Gray"))
		button.Visible = not (phone and picking and not S.Portrait)
	end
	-- pick mode takes the controls' row on a phone, the sort's side on PC
	local rowHidden = phone and picking
	for _, button in ipairs({ U.Sort, U.AutoFill, U.Clear }) do
		button.Visible = not rowHidden
	end
	U.Banner.Visible = picking
	U.PickCancel.Visible = picking
	if picking then
		U.Banner.Text = S.Pick == 1 and "Pick your fighter" or ("Pick a helper for slot " .. S.Pick)
	end
	U.Clear.Text = S.ClearArmed ~= 0 and "Tap again to clear" or "Clear"
	CloudUI.SetStyle(U.Clear, S.ClearArmed ~= 0 and "Red" or "Gray")
	local undo = S.Undo ~= nil and not (phone and picking)
	U.Undo.Visible = undo
	if phone or U.TopStacked then
		U.Clear.Visible = U.Clear.Visible and not undo -- Undo sits in Clear's place
	end
	U.Sort.Text = S.Sort
end

function H.sortedKeys()
	local owned = Bits.ownedKeys()
	local rows = {}
	for i, key in ipairs(owned) do
		local def = Bits.defOfKey(key)
		rows[i] = { Key = key, Power = H.powerOf(key), Rarity = Bits.rarityOrder(def and def.Rarity), Level = (Bits.petLevel(key)), Index = i }
	end
	local sort = S.Sort
	table.sort(rows, function(a, b)
		if sort == "Rarest" and a.Rarity ~= b.Rarity then
			return a.Rarity > b.Rarity
		elseif sort == "Level" and a.Level ~= b.Level then
			return a.Level > b.Level
		end
		if a.Power ~= b.Power then
			return a.Power > b.Power
		end
		return a.Index < b.Index
	end)
	local out = {}
	for i, row in ipairs(rows) do
		out[i] = row.Key
	end
	return out
end

-- Card viewports attach under a per-frame time budget, so a big collection never builds ~30 models in the frame the window
-- opens; until then a card is its rarity tile.
function H.fillCards()
	if S.Filling then
		return
	end
	S.Filling = true
	task.spawn(function()
		task.wait()
		while S.Open do
			local start = os.clock()
			local count, more = 0, false
			for _, key in ipairs(S.Order) do
				local item = U.Cards[key]
				if item and not S.Ready[key] then
					if count >= K.BUILD_MAX or (count > 0 and os.clock() - start >= K.BUILD_BUDGET) then
						more = true
						break
					end
					S.Ready[key] = true
					count = count + 1
					local def = Bits.defOfKey(key)
					if def then
						local stage = Bits.stage(key)
						local ok, handle = pcall(CloudUI.PetViewport, item.Picture, def, UDim2.new(1, 0, 1, 0), {
							Spin = "sway",
							Animate = false,
							Detail = "Low",
							Evolved = stage >= 1 and stage or nil,
							ZIndex = 2,
						})
						if ok then
							item.Viewport = handle
							item.ViewStage = stage
							if stage >= 1 then
								handle.Frame.Name = "EvolvedView"
							end
						end
					end
				end
			end
			if not more then
				break
			end
			task.wait()
		end
		S.Filling = false
	end)
end

function H.refreshCards(keys)
	local order = H.sortedKeys()
	local owned, slotOf = {}, {}
	for _, key in ipairs(order) do
		owned[key] = true
	end
	for i, key in ipairs(keys) do
		slotOf[key] = i
	end
	for key, item in pairs(U.Cards) do
		if not owned[key] then
			if item.Viewport then
				item.Viewport.Destroy()
			end
			item.Button:Destroy()
			U.Cards[key] = nil
			S.Ready[key] = nil
		end
	end
	S.Order = order
	for index, key in ipairs(order) do
		local def = Bits.defOfKey(key)
		local item = U.Cards[key] or H.buildCard(key)
		item.Button.LayoutOrder = index
		local level = Bits.petLevel(key)
		local stage = Bits.stage(key)
		if item.Viewport and item.ViewStage ~= stage then
			item.Viewport.Destroy()
			item.Viewport = nil
			S.Ready[key] = nil
		end
		local tint = CloudUI.RarityColor(def.Rarity)
		item.Gradient.Color = ColorSequence.new(Theme.Lighten(INSET_COLOR, 0.3):Lerp(tint, 0.38), Theme.Darken(INSET_COLOR, 0.05):Lerp(tint, 0.2))
		local selected = key == S.Selected
		item.Rarity.Color = selected and GOLD or Theme.Lighten(tint, 0.1)
		item.Rarity.Thickness = selected and 4 or 3
		item.Name.Text = Bits.displayName(key, def)
		item.Level.Text = "L" .. level
		item.Power.Text = commas(H.powerOf(key))
		local element = Bits.elementsOf(def)[1]
		local info = element and Config.Elements.Info[element]
		item.Element.Visible = info ~= nil
		if info then
			item.Element.BackgroundColor3 = info.Color
			item.Element.Text = element:sub(1, 1)
		end
		local slot = slotOf[key]
		item.Number.Visible = slot ~= nil
		item.Number.Text = slot and tostring(slot) or ""
		local tier = Bits.tierOf(key, def)
		local hybrid = Bits.isHybrid(key, def)
		local mark = (hybrid and "H") or (tier == "Rainbow" and "R") or (tier == "Golden" and "G") or nil
		item.Tier.Visible = mark ~= nil
		if mark then
			item.Tier.BackgroundColor3 = (hybrid and TIER_COLORS.Hybrid) or TIER_COLORS[tier]
			item.TierMark.Text = mark
		end
		item.Stars.Visible = stage > 0
		if stage > 0 then
			PixelIcon.Mark(item.Stars, ICON.Star, { Count = math.min(2, stage), Of = math.min(2, stage) }) -- (kit-b U7b)
		end
		local copies = State.OwnedCount(key)
		item.Count.Visible = copies > 1
		item.Count.Text = "x" .. copies
		local busy = Bits.busyOf(key)
		item.Busy.Visible = busy ~= nil
		item.Busy.Text = busy == "Training" and "Training" or (busy and "Gardening" or "")
		PixelIcon.Mark(item.Busy, busy == "Training" and ICON.Training or (busy and ICON.Garden or nil)) -- (kit-b U7b)
		item.Busy.TextColor3 = WHITE
		item.Busy.BackgroundColor3 = busy == "Training" and Theme.Darken(TRAIN_COLOR, 0.55) or (busy and Theme.Darken(GARDEN_COLOR, 0.55) or NAVY)
	end
	U.Grid.Visible = #order > 0
	U.Empty.Visible = #order == 0
	if #order == 0 then
		local loaded = State.IsLoaded == nil or State.IsLoaded()
		U.EmptyTitle.Text = loaded and "No pets yet!" or "Loading..."
		U.EmptyBody.Text = loaded and "Spin a roulette in the Shop to hatch your first winged friend." or "Fetching your pets from the clouds."
		U.EmptyButton.Visible = loaded
	end
	H.fillCards()
	return order
end

function H.refreshDetail(keys, order)
	local d = U.D
	local key = S.Selected
	local def = key and Bits.defOfKey(key) or nil
	local has = def ~= nil and State.OwnedCount(key) > 0
	if S.Mode == "Phone" then
		d.Frame.Visible = has and S.SheetOpen
		d.Frame.BackgroundTransparency = 0
	else
		d.Frame.Visible = #order > 0
		d.Frame.BackgroundTransparency = 0.1
	end
	-- (a landscape sheet's own X sits where the window's is: one X at a time, the top one closes the top thing)
	U.Panel.CloseButton.Visible = not (d.Frame.Visible and S.Mode == "Phone" and not S.Portrait)
	d.Hint.Visible = not has
	for _, part in ipairs({ d.Glow, d.Picture, d.Name, d.Meta, d.Xp.Root, d.Work, d.Perks, d.ActPut, d.ActFighter, d.ActRemove, d.ActFeed, d.ActTrain, d.ActGarden, d.ActEvolve }) do
		part.Visible = has
	end
	for _, row in pairs(U.Rows) do
		row.Frame.Visible = has
	end
	if not has then
		if d.Viewport then
			d.Viewport.Destroy()
			d.Viewport = nil
			d.ViewKey = nil
		end
		return
	end
	local stage = Bits.stage(key)
	local viewKey = key .. "|" .. stage
	if d.ViewKey ~= viewKey then
		if d.Viewport then
			d.Viewport.Destroy()
		end
		-- (an evolved pet shows its evolved form: Low detail keeps the big Evolved II models cheap)
		d.Viewport = CloudUI.PetViewport(d.Picture, def, UDim2.new(1, 0, 1, 0), {
			Spin = "spin",
			ZIndex = 2,
			Evolved = stage > 0 and stage or nil,
			Detail = stage > 0 and "Low" or nil,
		})
		d.ViewKey = viewKey
	end
	local tier = Bits.tierOf(key, def)
	local tint = CloudUI.RarityColor(def.Rarity)
	d.Glow.BackgroundColor3 = TIER_COLORS[tier] or tint
	d.Name.Text = Bits.displayName(key, def)
	d.Name.TextColor3 = def.Rarity == "Secret" and Color3.fromRGB(196, 168, 255) or Theme.Lighten(tint, 0.3)
	-- "Lv 1 / 100, Epic, Celestial", the copy's tier / evolution in the same line
	local level, xp = Bits.petLevel(key)
	local cap = Bits.levelCap(key, def)
	local meta = { "Lv " .. level .. " / " .. cap, tostring(def.Rarity) }
	if tier ~= "Normal" then
		meta[#meta + 1] = tier
	end
	if Bits.isHybrid(key, def) then
		meta[#meta + 1] = "Hybrid"
	end
	for _, element in ipairs(Bits.elementsOf(def)) do
		meta[#meta + 1] = element
	end
	d.Meta.Text = table.concat(meta, " " .. G.Bullet .. " ")
	-- (kit-b U7b) the evolution stars after the line, drawn
	PixelIcon.Mark(d.Meta, stage > 0 and ICON.Star or nil, { After = true, Count = math.min(2, stage), Of = math.min(2, stage), Colour = GOLD })
	local need = Bits.xpToNext(level)
	if level >= cap then
		d.Xp.SetFraction(1)
		d.Xp.SetText("MAX LEVEL")
		d.Xp.SetColor(GOLD)
	else
		d.Xp.SetFraction(need > 0 and need < math.huge and math.min(1, xp / need) or 0)
		d.Xp.SetText(commas(math.floor(xp)) .. " / " .. commas(need) .. " XP")
		d.Xp.SetColor(XP_COLOR)
	end
	local stats = Bits.battleStatsAt(def, key, level) or {}
	local home = Bits.homeData()
	U.Rows.Income.Value.Text = Bits.formatRate(Bits.coinsPerSecond(key, def, home)) .. "/s"
	U.Rows.Power.Value.Text = commas(H.powerOf(key))
	U.Rows.Health.Value.Text = commas(math.floor((tonumber(stats.Health) or 0) + 0.5))
	U.Rows.Speed.Value.Text = commas(math.floor((tonumber(stats.Speed) or 0) + 0.5))
	-- where it works / trains, and its evolution
	local job = Bits.job(key)
	local map = type(home.Garden) == "table" and home.Garden or {}
	local placed = #Bits.slotsHolding(map, key) > 0
	local ready = Bits.canEvolve(key, def, level)
	local work, workColor, lines, mark = "", Theme.Lighten(GOOD, 0.35), 1, nil
	if job then
		work, mark = "Training " .. Bits.skillName(job.Stat) .. " (" .. Bits.jobLeft(job) .. " left)", ICON.Training
		workColor = Theme.Lighten(TRAIN_COLOR, 0.35)
	elseif placed then
		work, mark = "Working in your Garden", ICON.Garden
	end
	if ready then
		if work ~= "" then
			work = work .. "\n"
			lines = 2
		end
		work = work .. "Ready to evolve!"
		mark = mark or ICON.Evolve
	end
	d.Work.Text = work
	PixelIcon.Mark(d.Work, lines == 1 and mark or nil) -- (kit-b U7b) a one-line work note leads with its mark
	d.Work.TextColor3 = workColor
	d.WorkLines = lines
	-- the special, then the follow perks
	local perkLines = {}
	if type(def.Special) == "table" then
		perkLines[1] = "Special: " .. tostring(BattleCatalog.FormNameOf(def.Id, def.Special.Kind, stage) or def.Special.Name or "Special")
	end
	if stage >= 1 then
		perkLines[#perkLines + 1] = string.format("Reach +%d%%", math.floor((BattleCatalog.ReachOf(stage) - 1) * 100 + 0.5))
	end
	if type(def.Perks) == "table" then
		local mult = Bits.tierMultiplier(key, def)
		for _, perkKey in ipairs(PetCatalog.PerkOrder or {}) do
			local value = def.Perks[perkKey]
			if type(value) == "number" and value ~= 0 then
				perkLines[#perkLines + 1] = PetCatalog.PerkLabel(perkKey, value * mult)
			end
		end
	end
	d.PerkLines = #perkLines > 0 and perkLines or { "No perks" }
	-- the actions
	local at = H.indexOf(key)
	d.InTeam = at ~= nil
	d.IsFighter = at == 1
	d.ActEvolve.Visible = ready ~= nil
	d.ActTrain.Text = job and "Training" or "Train"
	d.ActGarden.Text = placed and "Leave Garden" or "Garden"
	CloudUI.SetStyle(d.ActGarden, placed and "Pink" or "Blue")
	H.placeActions()
	d.Perks.Visible = d.PerksH >= d.PerkLineH
	local shown = {}
	for i = 1, math.min(#d.PerkLines, math.floor(d.PerksH / d.PerkLineH)) do
		shown[i] = d.PerkLines[i]
	end
	d.Perks.Text = table.concat(shown, "\n")
end

function H.refresh()
	if not (S.Built and S.Open) then
		return
	end
	S.Power = {}
	local keys = H.keys()
	local order = H.refreshCards(keys)
	-- keep the selection valid: prefer a team pet, else the strongest
	if not (S.Selected and State.OwnedCount(S.Selected) > 0) then
		S.Selected = nil
		for _, key in ipairs(keys) do
			if State.OwnedCount(key) > 0 then
				S.Selected = key
				break
			end
		end
		S.Selected = S.Selected or order[1]
		H.refreshCards(keys)
	end
	if S.Pick and S.Pick > #keys + 1 then
		S.Pick = #keys + 1
	end
	H.refreshSlots(keys)
	H.refreshTop()
	H.refreshDetail(keys, order)
end

----------------------------------------------------------------------
-- Back: the recall question, the sheet, pick mode, then the window
----------------------------------------------------------------------
function H.back()
	if Bits.closeRecall() then
		return
	end
	if S.SheetOpen then
		S.SheetOpen = false
		H.refresh()
		return
	end
	if S.Pick then
		S.Pick = nil
		H.refresh()
		return
	end
	PetsController.Close()
end

function H.syncBack()
	if S.Open and not S.BackBound then
		S.BackBound = true
		pcall(function()
			ContextActionService:BindActionAtPriority(K.BACK_ACTION, function(_, inputState)
				if inputState == Enum.UserInputState.Begin then
					safe("back", H.back)
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		end)
	elseif not S.Open and S.BackBound then
		S.BackBound = false
		pcall(function()
			ContextActionService:UnbindAction(K.BACK_ACTION)
		end)
	end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
function PetsController.IsOpen()
	return S.Open
end

function PetsController.Sort()
	return S.Sort
end

function PetsController.SetSort(mode)
	for _, known in ipairs(K.SORTS) do
		if known == mode then
			S.Sort = mode
			H.refresh()
			return
		end
	end
end

function PetsController.Layout()
	if S.Open then
		return S.Mode
	end
	return H.rect().mode
end

function PetsController.ReturnArgs()
	if S.Open and S.ReturnTo then
		return { Key = S.Selected, Preset = S.View, ReturnTo = S.ReturnTo }
	end
	return nil
end

function PetsController.Open(args)
	if not initialized then
		PetsController.Init()
	end
	if not U.Gui then
		return false
	end
	args = type(args) == "table" and args or {}
	H.build()
	local wasOpen = S.Open
	S.Open = true
	S.Token = S.Token + 1
	if type(args.ReturnTo) == "table" then
		S.ReturnTo = args.ReturnTo
	elseif not wasOpen then
		S.ReturnTo = nil
	end
	local preset = tonumber(args.Preset)
	if preset and preset >= 1 and preset <= K.PRESETS and preset == math.floor(preset) then
		S.View = preset
	elseif not wasOpen then
		S.View = nil
	end
	if S.View and S.View == H.activePreset() then
		S.View = nil
	end
	local pick = tonumber(args.Pick)
	if pick and pick >= 1 and pick <= K.SLOTS and pick == math.floor(pick) then
		S.Pick = math.min(math.floor(pick), #H.keys() + 1)
	elseif not wasOpen then
		S.Pick = nil
	end
	H.layout()
	if type(args.Key) == "string" and State.OwnedCount(args.Key) > 0 then
		S.Selected = args.Key
		S.SheetOpen = S.Mode == "Phone"
	elseif not wasOpen then
		S.SheetOpen = false
	end
	U.Holder.Visible = true
	if not wasOpen then
		U.Pop.Scale = 0.86
		Util.Tween(U.Pop, 0.22, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	H.syncBack()
	H.settle()
	H.refresh()
	if not wasOpen then
		-- the training time ticks while the window is open
		local mine = S.Token
		task.spawn(function()
			while S.Open and S.Token == mine do
				task.wait(K.TICK)
				if S.Open and S.Token == mine and S.Selected and Bits.job(S.Selected) then
					safe("tick", H.refresh)
				end
			end
		end)
		PetsController.Opened:Fire()
		local menu = H.controller("MenuController")
		if menu and menu.WindowOpened then
			menu.WindowOpened:Fire("Pets")
		end
	end
	if args.Action == "Evolve" and type(args.Key) == "string" then
		-- the floating card's EVOLVE! pill: this window on that pet, with the EVOLVE confirm on top
		task.defer(function()
			if S.Open and S.Selected == args.Key then
				H.careOpen("Evolve")
			end
		end)
	end
	return true
end

-- ReturnTo: where the player goes when the window closes (not a silent close)
function H.returnTo(back)
	local arena = (back.Window == "Ring" or back.Window == "Arena") and H.controller("ArenaController") or nil
	if back.Window == "Loss" then
		local loss = H.controller("LossScreen")
		if loss then
			safe("back to loss", loss.Reopen)
		end
	elseif back.Window == "Ring" and arena then
		safe("back to ring", arena.OpenRing, back.Start, back.Portal)
	elseif back.Window == "Arena" and arena then
		safe("back to arena", arena.OpenArena, back.Tab)
	elseif back.Window == "Dungeon" then
		local dungeon = H.controller("DungeonController")
		if dungeon then
			safe("back to dungeon", dungeon.Open, back.Floor, back.Portal)
		end
	end
end

function PetsController.Close(silent)
	if not S.Open then
		return
	end
	S.Open = false
	S.Token = S.Token + 1
	local mine = S.Token
	local back = S.ReturnTo
	S.ReturnTo = nil
	S.Pick = nil
	S.SheetOpen = false
	S.View = nil
	S.ClearArmed = 0
	Bits.closeRecall()
	H.syncBack()
	H.coverColumn(nil)
	Util.Tween(U.Pop, 0.12, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.13, function()
		if S.Token == mine and not S.Open then
			U.Holder.Visible = false
		end
	end)
	PetsController.Closed:Fire(silent ~= true and back or nil)
	if silent ~= true and back then
		H.returnTo(back)
	end
end

function PetsController.Init()
	if initialized then
		return
	end
	initialized = true
	LocalPlayer = Players.LocalPlayer
	pcall(State.Init)
	U.Gui = CloudUI.NewScreenGui("NimbusPets", K.DISPLAY_ORDER)
	U.Gui.IgnoreGuiInset = true
	U.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if S.Open then
			safe("relayout", H.layout)
			safe("refresh", H.refresh)
		end
	end)
	State.Changed:Connect(function()
		H.settle()
		safe("refresh", H.refresh)
	end)
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape and S.Open then
			local care = H.controller("CareController")
			if not (care and type(care.IsOpen) == "function" and care.IsOpen()) then
				safe("back", H.back)
			end
		end
	end)
	task.spawn(function()
		local remote = H.remote("Notify")
		if remote then
			remote.OnClientEvent:Connect(function(message, kind)
				safe("notify", H.onNotify, message, kind)
			end)
		end
	end)
end

return PetsController
