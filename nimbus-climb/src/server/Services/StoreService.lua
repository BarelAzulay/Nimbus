-- StoreService (store 2026-11-04; docs/superpowers/specs/2026-11-04-shop-retention-design.md 5.1 / 5.4 / 7): the Robux
-- Store's server half: the ONE grant path of a paid receipt (ApplyGrant), the game-pass cache, the purchase prompt
-- behind StoreRequest and the StorePreview flag. GemService keeps MarketplaceService.ProcessReceipt and routes every
-- receipt here through StoreCatalog.ProductById; the client reads only the three attributes Multipliers writes.
--
-- * ApplyGrant(player, item, purchaseId) -> ok, granted: non-yielding, CHECK then WRITE. The ONLY false is "profile
--   not loaded or provisional" (GemService answers NotProcessedYet and Roblox retries). A PAID receipt is never eaten
--   (Z7): a pet whose stack is full pays its rarity's Config.Index.Rewards[r].Tokens instead ("Stack full: +2,000
--   Tokens instead", recorded in granted.Substitute and added to granted.Tokens), a potion extends past the 7-day cap
--   (the cap only dims the card), a Once pack bought before is granted again with a warn. `granted` = what was REALLY
--   given: { Cash, Tokens, Gems, Pets = {[id] = n}, Boost = {[id] = seconds}, Substitute = {[id] = tokens} }
--   (GemService hands it to DataService.NoteReceiptGrant: the twin rule of the cross-server merge).
-- * Thank(player, item, granted, purchaseId): the "Thank you! <GrantLines joined by ', '>" toast (the client plays
--   StoreBuy on a text starting with "Thank you") and Purchased:Fire, once per purchase, called by GemService when the
--   purchase is granted for good (the save landed; in Studio also after a failed save).
-- * Passes (Z3): on join every Pass with Id > 0 is asked ONCE with pcall(MarketplaceService:UserOwnsGamePassAsync); a
--   failure keeps "Checking" (fail closed) and is retried after 5 / 15 / 45 / 120 s, then every 300 s. true -> Owned +
--   DataService.MarkPassSeen. PromptGamePassPurchaseFinished(player, id, true) marks Owned at once. With
--   Config.Store.TrustLedgerAfter > 0, that many seconds of failures let the stored Store.Passes ledger count as Owned
--   (0 = never). Owns / PassState read THIS server's cache only; the attributes are written, never read back.
-- * StoreRequest ("Buy", key): a live player, a string key, 1 request/s, refused in a match ("The Store is closed
--   during a match"), for an Id 0 item (preview or not), a bought Once pack or an owned pass ("You already have
--   that!"); else PromptPurchase -> PromptGamePassPurchase / PromptProductPurchase. A prompt never grants (Z1).
-- * StorePreview: written once at the join, true in Studio (RunService:IsStudio()) or for DevService.IsAllowed(player)
--   (may yield once: a task.spawn), never on a timer.
--
-- Public API
--   StoreService.Init(deps)                       deps = { DataService, PetService, DevService? }
--   StoreService.ApplyGrant(player, item, purchaseId) -> ok, granted | reason    (non-yielding)
--   StoreService.Thank(player, item, granted, purchaseId)   the thank-you toast + Purchased, once
--   StoreService.PromptPurchase(player, key) -> ok, reason
--   StoreService.Owns(player, key) -> bool                  this server's cache only (Z3)
--   StoreService.PassState(player, key) -> "Owned" | "NotOwned" | "Checking" | "Unavailable"
--   StoreService.IsPreview(player) -> bool
--   StoreService.BoostEnds(player, id) -> unix seconds | 0
--   StoreService.Refresh(player)                  fires Changed (Multipliers rewrites the attributes)
--   StoreService.Purchased   Util.Signal Fire(player, key, granted, purchaseId)   once per purchase, after the save that lands
--   StoreService.Changed     Util.Signal Fire(player)   after any ownership / bought / boost change and every pass answer
--
-- Plain Lua 5.1-compatible syntax only. Nothing here yields between a check and its write.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local StoreCatalog = require(Shared.StoreCatalog)

local StoreService = {}
StoreService.Purchased = Util.Signal() -- Fire(player, key, granted, purchaseId)
StoreService.Changed = Util.Signal() -- Fire(player)

local REQUEST_REMOTE = "StoreRequest"
local REQUEST_GAP = 1 -- seconds between two StoreRequests of one player
local PROMPT_COOLDOWN = 1 -- seconds between two purchase prompts of one player
local PASS_RETRY = { 5, 15, 45, 120 } -- seconds before the retries of a failed pass lookup...
local PASS_RETRY_LATER = 300 -- ...then every this many seconds
local PASS_TICK = 1 -- the retry loop looks for due lookups this often
local THANKS_SECONDS = 5
local TEXT = {
	Match = "The Store is closed during a match",
	Have = "You already have that!",
	Unknown = "That item is not in the Store",
	NotYet = "That item is not on sale yet",
	Wait = "Please wait a moment",
	Window = "The purchase window could not open",
	Loading = "Your save is still loading",
	StackFull = "Stack full: +%s Tokens instead",
}

local S = {
	DS = nil,
	PS = nil,
	Dev = nil,
	Passes = {}, -- [player] = { [key] = { State = "Checking"|"Owned"|"NotOwned", Busy, Fails, NextTry, FirstFail } }
	Preview = {}, -- [player] = bool (the computed flag; the attribute is only written)
	PromptAt = {}, -- [player] = os.clock() of the last purchase prompt
	LastCall = {}, -- [player] = { [key] = os.clock() }
	Warned = {}, -- [key] = true: one warning per problem per server
	Started = false,
}
StoreService._S = S

----------------------------------------------------------------------
-- helpers (the GemService shapes; its locals are not reachable from here)
----------------------------------------------------------------------
local function isFinite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function wholeNumber(n)
	if not isFinite(n) or n ~= math.floor(n) then
		return nil
	end
	return n
end

local function isPlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function warnOnce(key, text)
	if S.Warned[key] then
		return
	end
	S.Warned[key] = true
	warn(text)
end

local function rateLimited(player, key, interval)
	local record = S.LastCall[player]
	if not record then
		record = {}
		S.LastCall[player] = record
	end
	local now = os.clock()
	local last = record[key]
	if last and now - last < interval then
		return true
	end
	record[key] = now
	return false
end

local function notify(player, text, kind, duration)
	local ok, remote = pcall(Remotes.Get, "Notify")
	if ok and remote and isPlayer(player) then
		remote:FireClient(player, text, kind or "info", duration or 3)
	end
end

local function storeConfig()
	return type(Config.Store) == "table" and Config.Store or {}
end

local function attrName(key)
	local name = Config.Attr and Config.Attr[key]
	return type(name) == "string" and name or nil
end

-- the Pass items of the catalog (Config order), read on every call: the owner pastes ids, tests change them
local function passItems()
	local out = {}
	for _, item in ipairs(StoreCatalog.List()) do
		if item.Kind == "Pass" then
			out[#out + 1] = item
		end
	end
	return out
end

local function passItem(key)
	for _, item in ipairs(passItems()) do
		if item.Key == key then
			return item
		end
	end
	return nil
end

-- the stored Store record (a copy), or nil until loaded / while provisional
local function storeOf(player)
	local DS = S.DS
	if not DS or type(DS.GetStore) ~= "function" then
		return nil
	end
	local ok, store = pcall(DS.GetStore, player)
	if ok and type(store) == "table" then
		return store
	end
	return nil
end

local function rarityTokens(petId)
	local ok, catalog = pcall(function()
		return require(Shared.PetCatalog)
	end)
	local def = ok and type(catalog) == "table" and type(catalog.Get) == "function" and catalog.Get(petId) or nil
	local rewards = type(Config.Index) == "table" and type(Config.Index.Rewards) == "table" and Config.Index.Rewards or {}
	local entry = def and rewards[def.Rarity] or nil
	local tokens = type(entry) == "table" and wholeNumber(entry.Tokens) or nil
	return tokens and tokens > 0 and tokens or 0
end

----------------------------------------------------------------------
-- The grant (one non-yielding step after GemService marked the receipt)
----------------------------------------------------------------------
function StoreService.ApplyGrant(player, item, purchaseId)
	if not isPlayer(player) then
		return false, "Player unavailable"
	end
	if type(item) ~= "table" or type(item.Grants) ~= "table" then
		return false, "Unknown item"
	end
	local DS = S.DS
	if not DS or type(DS.GetProfile) ~= "function" then
		return false, TEXT.Loading
	end
	local profile = DS.GetProfile(player)
	if not profile or (type(DS.IsProvisional) == "function" and DS.IsProvisional(player) == true) then
		return false, TEXT.Loading
	end
	local grants = item.Grants
	local granted = {}
	local cash = wholeNumber(grants.Cash)
	if cash and cash >= 1 and type(DS.AddCash) == "function" and DS.AddCash(player, cash) then
		granted.Cash = cash
	end
	local tokens = wholeNumber(grants.Tokens)
	if tokens and tokens >= 1 and type(DS.AddTokens) == "function" then
		DS.AddTokens(player, tokens)
		granted.Tokens = tokens
	end
	local gems = wholeNumber(grants.Gems)
	if gems and gems >= 1 and type(DS.AddGems) == "function" and DS.AddGems(player, gems) then
		granted.Gems = gems
	end
	if type(grants.Pets) == "table" then
		local PS = S.PS
		for petId, spec in pairs(grants.Pets) do
			local count = type(spec) == "table" and wholeNumber(spec.Count) or 1
			local level = type(spec) == "table" and spec.Level or nil
			if count and count >= 1 then
				local given = 0
				if PS and type(PS.GrantPet) == "function" then
					local ok, result = PS.GrantPet(player, petId, { Count = count, Level = level })
					if ok and type(result) == "table" then
						given = wholeNumber(result.Granted) or 0
					elseif result ~= "Stack full" then
						warnOnce("pet-" .. tostring(petId), "[StoreService] could not grant pet " .. tostring(petId) .. " of " .. tostring(item.Key) .. ": " .. tostring(result))
					end
				else
					warnOnce("no-petservice", "[StoreService] PetService.GrantPet is missing: pets of a pack are paid as Tokens")
				end
				if given > 0 then
					granted.Pets = granted.Pets or {}
					granted.Pets[petId] = given
				end
				local left = count - given
				if left > 0 then
					-- Z7: the stack is full: the rarity's Index Tokens instead, per copy (a paid receipt is never eaten)
					local sub = rarityTokens(petId) * left
					if sub > 0 and type(DS.AddTokens) == "function" then
						DS.AddTokens(player, sub)
						granted.Tokens = (granted.Tokens or 0) + sub
						granted.Substitute = granted.Substitute or {}
						granted.Substitute[petId] = sub
					end
				end
			end
		end
	end
	if type(grants.Boost) == "table" and type(DS.AddBoost) == "function" then
		for id, seconds in pairs(grants.Boost) do
			local secs = wholeNumber(seconds)
			if type(id) == "string" and secs and secs >= 1 then
				local ok = DS.AddBoost(player, id, secs) -- past the cap too: the cap only dims the card
				if ok then
					granted.Boost = granted.Boost or {}
					granted.Boost[id] = secs
				end
			end
		end
	end
	if item.Once and type(DS.MarkBought) == "function" then
		if not DS.MarkBought(player, item.Key) then
			warn("[StoreService] " .. tostring(item.Key) .. " was bought before: Roblox sold it again (receipt " .. tostring(purchaseId) .. "), granted again (Z7)")
		end
	end
	StoreService.Changed:Fire(player)
	return true, granted
end

-- the GrantLines table of what was really granted (pets with the pack's Level for the "(Lv n)" text)
local function linesOf(item, granted)
	local lines = {}
	if type(granted) ~= "table" then
		return lines
	end
	if type(granted.Pets) == "table" then
		local pets = {}
		for petId, n in pairs(granted.Pets) do
			local spec = type(item.Grants) == "table" and type(item.Grants.Pets) == "table" and item.Grants.Pets[petId] or nil
			pets[petId] = { Count = n, Level = type(spec) == "table" and spec.Level or nil }
		end
		lines.Pets = pets
	end
	lines.Cash, lines.Tokens, lines.Gems, lines.Boost = granted.Cash, granted.Tokens, granted.Gems, granted.Boost
	if item.Kind == "Pass" and type(item.Grants) == "table" then
		lines.Perks = item.Grants.Perks
	end
	return lines
end

function StoreService.Thank(player, item, granted, purchaseId)
	if type(item) ~= "table" then
		return
	end
	local text = "Thank you! " .. table.concat(StoreCatalog.GrantLines(linesOf(item, granted)), ", ")
	notify(player, text, "good", THANKS_SECONDS)
	if type(granted) == "table" and type(granted.Substitute) == "table" then
		for _ , tokens in pairs(granted.Substitute) do
			notify(player, string.format(TEXT.StackFull, Util.Commas(tokens)), "info", THANKS_SECONDS)
		end
	end
	StoreService.Purchased:Fire(player, item.Key, granted, purchaseId)
end

----------------------------------------------------------------------
-- Passes
----------------------------------------------------------------------
local function passMap(player)
	local map = S.Passes[player]
	if not map then
		map = {}
		S.Passes[player] = map
	end
	return map
end

-- the ledger rule: Checking for TrustLedgerAfter seconds of failures with the pass in the stored Store.Passes = Owned
local function ledgerTrusted(player, entry, key)
	local after = tonumber(storeConfig().TrustLedgerAfter) or 0
	if after <= 0 or entry.State ~= "Checking" or not entry.FirstFail or os.clock() - entry.FirstFail < after then
		return false
	end
	local store = storeOf(player)
	return store ~= nil and type(store.Passes) == "table" and store.Passes[key] ~= nil
end

local function setOwned(player, key)
	local entry = passMap(player)[key]
	if not entry then
		entry = { State = "Checking", Busy = false, Fails = 0 }
		passMap(player)[key] = entry
	end
	entry.State = "Owned"
	entry.NextTry = nil
	if S.DS and type(S.DS.MarkPassSeen) == "function" then
		pcall(S.DS.MarkPassSeen, player, key)
	end
end

-- One lookup (yields inside the MarketplaceService call). A failure keeps the state and schedules a retry.
local function lookupPass(player, key, id)
	local entry = passMap(player)[key]
	if not entry or entry.Busy then
		return
	end
	entry.Busy = true
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
	end)
	entry.Busy = false
	if S.Passes[player] == nil or S.Passes[player][key] ~= entry or player.Parent ~= Players then
		return
	end
	if ok then
		entry.Fails = 0
		entry.FirstFail = nil
		entry.NextTry = nil
		if owns == true then
			setOwned(player, key)
		elseif entry.State ~= "Owned" then
			entry.State = "NotOwned"
		end
	else
		entry.Fails = entry.Fails + 1
		entry.FirstFail = entry.FirstFail or os.clock()
		entry.NextTry = os.clock() + (PASS_RETRY[entry.Fails] or PASS_RETRY_LATER)
		warnOnce("pass-fail", "[StoreService] UserOwnsGamePassAsync failed (" .. tostring(owns) .. "): passes stay unowned for that player until a retry succeeds")
	end
	StoreService.Changed:Fire(player)
end

local function startPasses(player)
	local map = passMap(player)
	for _, item in ipairs(passItems()) do
		if item.Created and not map[item.Key] then
			map[item.Key] = { State = "Checking", Busy = false, Fails = 0, NextTry = nil, FirstFail = nil }
			task.spawn(lookupPass, player, item.Key, item.Id)
		end
	end
end

-- One loop for every retry and the ledger rule (no thread per player, nothing left behind when players leave).
local function passLoop()
	while true do
		task.wait(PASS_TICK)
		local now = os.clock()
		local due, trusted = {}, {}
		for player, map in pairs(S.Passes) do
			for key, entry in pairs(map) do
				if not entry.Busy and entry.NextTry and now >= entry.NextTry then
					due[#due + 1] = { player, key }
				end
				if ledgerTrusted(player, entry, key) then
					trusted[#trusted + 1] = { player, key }
				end
			end
		end
		for _, pair in ipairs(trusted) do
			local player, key = pair[1], pair[2]
			if player.Parent == Players then
				setOwned(player, key)
				StoreService.Changed:Fire(player)
			end
		end
		for _, pair in ipairs(due) do
			local player, key = pair[1], pair[2]
			local entry = S.Passes[player] and S.Passes[player][key]
			local item = passItem(key)
			if entry and item and item.Created and player.Parent == Players then
				entry.NextTry = nil
				task.spawn(lookupPass, player, key, item.Id)
			end
		end
	end
end

function StoreService.PassState(player, key)
	local item = passItem(key)
	if not item or not item.Created then
		return "Unavailable"
	end
	if not isPlayer(player) then
		return "Checking"
	end
	local entry = S.Passes[player] and S.Passes[player][key]
	if not entry then
		return "Checking"
	end
	if entry.State == "Checking" and ledgerTrusted(player, entry, key) then
		setOwned(player, key)
		StoreService.Changed:Fire(player)
	end
	return entry.State
end

function StoreService.Owns(player, key)
	return StoreService.PassState(player, key) == "Owned"
end

function StoreService.IsPreview(player)
	return isPlayer(player) and S.Preview[player] == true
end

function StoreService.BoostEnds(player, id)
	local store = isPlayer(player) and storeOf(player) or nil
	local ends = store and type(store.Boosts) == "table" and store.Boosts[id] or nil
	if isFinite(ends) and ends > 0 then
		return ends
	end
	return 0
end

function StoreService.Refresh(player)
	if isPlayer(player) then
		StoreService.Changed:Fire(player)
	end
end

----------------------------------------------------------------------
-- The prompt (never a grant: Z1)
----------------------------------------------------------------------
function StoreService.PromptPurchase(player, key)
	if not isPlayer(player) then
		return false, "Player unavailable"
	end
	if type(key) ~= "string" then
		return false, TEXT.Unknown
	end
	local inMatch = attrName("InMatch")
	if inMatch and player:GetAttribute(inMatch) == true then
		return false, TEXT.Match
	end
	local item = StoreCatalog.Item(key)
	if not item then
		return false, TEXT.Unknown
	end
	if not item.Created then
		return false, TEXT.NotYet -- Id 0: hidden, preview or not (Z12)
	end
	if item.Kind == "Pass" then
		if StoreService.Owns(player, key) then
			return false, TEXT.Have
		end
	elseif item.Once then
		local store = storeOf(player)
		if store and type(store.Bought) == "table" and store.Bought[key] ~= nil then
			return false, TEXT.Have -- Z6: a bought item is never prompted
		end
	end
	local now = os.clock()
	local last = S.PromptAt[player]
	if last and now - last < PROMPT_COOLDOWN then
		return false, TEXT.Wait
	end
	S.PromptAt[player] = now
	local ok, err = pcall(function()
		if item.Kind == "Pass" then
			MarketplaceService:PromptGamePassPurchase(player, item.Id)
		else
			MarketplaceService:PromptProductPurchase(player, item.Id)
		end
	end)
	if not ok then
		warnOnce("prompt", "[StoreService] the purchase prompt failed: " .. tostring(err))
		return false, TEXT.Window
	end
	return true
end

local function onRequest(player, action, key)
	if not isPlayer(player) or action ~= "Buy" or type(key) ~= "string" then
		return -- junk: nothing, no answer
	end
	if rateLimited(player, REQUEST_REMOTE, REQUEST_GAP) then
		return
	end
	local ok, reason = StoreService.PromptPurchase(player, key)
	if not ok and reason and reason ~= TEXT.Unknown and reason ~= TEXT.NotYet then
		notify(player, tostring(reason), "bad", 3)
	end
end

----------------------------------------------------------------------
-- Players
----------------------------------------------------------------------
local function setPreview(player)
	local preview = RunService:IsStudio()
	if not preview and S.Dev and type(S.Dev.IsAllowed) == "function" then
		local ok, allowed = pcall(S.Dev.IsAllowed, player) -- may yield once (a group-owned game)
		preview = ok and allowed == true
	end
	if player.Parent ~= Players then
		return
	end
	S.Preview[player] = preview
	local attr = attrName("StorePreview")
	if attr then
		player:SetAttribute(attr, preview)
	end
end

local function onPlayerAdded(player)
	if not isPlayer(player) then
		return
	end
	startPasses(player)
	task.spawn(setPreview, player)
end

local function onPlayerRemoving(player)
	S.Passes[player] = nil
	S.Preview[player] = nil
	S.PromptAt[player] = nil
	S.LastCall[player] = nil
end

local function onPassFinished(player, id, wasPurchased)
	if wasPurchased ~= true or not isPlayer(player) then
		return
	end
	local item = StoreCatalog.PassById(id)
	if not item then
		return
	end
	setOwned(player, item.Key)
	StoreService.Thank(player, item, { Perks = item.Grants and item.Grants.Perks }, nil)
	StoreService.Changed:Fire(player)
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
local function checkConfig()
	local ok, problems = StoreCatalog.Validate()
	if not ok then
		for _, problem in ipairs(problems or {}) do
			warn("[StoreService] Config.Store: " .. tostring(problem))
		end
	end
	local onSale, total = 0, 0
	for _, item in ipairs(StoreCatalog.List()) do
		if not item.Gem then
			total = total + 1
			if item.Created then
				onSale = onSale + 1
			end
		end
	end
	print(string.format("[StoreService] %d of %d Store items on sale%s", onSale, total,
		onSale < total and " (Id 0 = not created yet: paste the product / pass ids into Config.Store.Items)" or ""))
end

function StoreService.Init(deps)
	deps = type(deps) == "table" and deps or {}
	S.DS = deps.DataService or S.DS
	S.PS = deps.PetService or S.PS
	S.Dev = deps.DevService or S.Dev
	if S.Started then
		return
	end
	S.Started = true
	local okCheck, errCheck = pcall(checkConfig)
	if not okCheck then
		warn("[StoreService] config check failed: " .. tostring(errCheck))
	end
	local okRemote, remote = pcall(Remotes.Get, REQUEST_REMOTE)
	if okRemote and remote then
		remote.OnServerEvent:Connect(function(player, action, key)
			local ok, err = pcall(onRequest, player, action, key)
			if not ok then
				warn("[StoreService] StoreRequest failed: " .. tostring(err))
			end
		end)
	else
		warn("[StoreService] StoreRequest remote is unavailable: " .. tostring(remote))
	end
	local okEvent, errEvent = pcall(function()
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, id, wasPurchased)
			local ok, err = pcall(onPassFinished, player, id, wasPurchased)
			if not ok then
				warn("[StoreService] PromptGamePassPurchaseFinished failed: " .. tostring(err))
			end
		end)
	end)
	if not okEvent then
		warn("[StoreService] could not connect PromptGamePassPurchaseFinished: " .. tostring(errEvent))
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	task.spawn(passLoop)
end

return StoreService
