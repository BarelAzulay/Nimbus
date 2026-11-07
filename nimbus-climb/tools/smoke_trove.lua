-- smoke_trove.lua: the Sky Trove (docs/superpowers/specs/2026-11-04-shop-retention-design.md 5.3 / 8 / 13b.5; plan
-- docs/superpowers/plans/2026-11-04-store.md, Task 6 by W1-lobby), loaded by tools/smoke.py in BOTH worlds (ARGS.context
-- picks the half):
--   trove_build          (server world, booted) LobbyInfo.Shop.ItemShop points at the SkyTrove model (PromptPart, Center, Lid),
--                        the boarded-up stall is gone, <= 60 parts, one tagged lid, the service-made prompt, Theme fonts only;
--                        lobby shop (spec 5.9): the chest stands on the plaza lawn (polar 43, r 56), off the shop island
--   trove_group_once     (server world, booted) the prompt opens the panel, NO IsInGroupAsync before Joined, ONE call, the exact
--                        grant ($2,000 + 200 Tokens), the ask set; a second Joined grants nothing and makes no call; saved
--   trove_stale_once     (server world, booted) a false answer: "Rejoin the game" toast, State Checked, a second Joined on the
--                        same server makes no call; a rejoin (a new Player) asks again and grants once
--   trove_provisional    (server world, booted) a provisional save: no call, no grant, State Loading; after the recovery once
--   trove_two_servers    (server world, booted) A grants through the service and its save fails, the player leaves; B (a
--                        second DataService copy: there is no seam for a second TroveService, so B is driven directly with
--                        MarkTrove + AddCash + AddTokens) saves; A's orphan retry lands: the grant is in the store ONCE
--   trove_no_discord     (server world) no source under src/ says "discord"; State's two asks (Like has no Reward)
--   trove_exploits       (server world, booted) from afar / in a match / in a battle: no panel; the 5 s cooldown; junk
--                        TroveRequest; 20 Joined in a second = at most one call; GroupId 0 = Soon; StorePreview = Preview
--   client_trove         (client world) the panel at 1920x1080: docked right, the rows and the footer, JOIN -> PromptJoinAsync
--                        (Pending = the hint, Joined = one TroveRequest), DONE plays the lid and the coins (High) or the lid
--                        only (Low), Checked / Soon / Preview, nothing in the screen centre, the window rule
--   client_trove_mobile  (phone world) 844x390: 352 x 236 at scale 1, 12 px from the right, top = inset + 8, texts >= 15 px,
--                        the button >= 44 px, Roblox's touch controls stay
-- White-box: the doubles are written straight onto the player / GroupService (props, never methods). Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded
local CONTEXT = (ARGS and ARGS.context) or "server"

local REWARD_TEXT = "The Sky Trove paid you $2,000 and 200 Cloud Tokens!"
local CHECKED_NEEDLE = "Rejoin the game"
local FOOTER = "Community links are on our game page. Prizes go straight to you. Once per player."
local PENDING_HINT = "Your request is waiting for the group. Come back later!"

----------------------------------------------------------------------------------------------------
-- server world
----------------------------------------------------------------------------------------------------
local function serverScenarios()
	local S = {}
	local K = _G.K
	local CollectionService = game:GetService("CollectionService")

	local function requireAt(key)
		local inst = K.moduleInstance(key)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		if ok and type(result) == "table" then
			return result
		end
		return nil
	end
	local function DS()
		return K.mod("DataService")
	end
	local function TS()
		return requireAt("server/Services/TroveService")
	end
	local function countParts(root)
		local n = 0
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				n = n + 1
			end
		end
		return n
	end
	local userSeq = 0
	local function newUserId()
		userSeq = userSeq + 1
		return 985100 + userSeq
	end
	local function join(prefix, uid)
		local p = Mock.AddPlayer(prefix .. tostring(uid % 1000), uid)
		K.advance(1.2)
		return p
	end
	local function leave(p)
		if p and p.Parent then
			Mock.RemovePlayer(p)
		end
		K.advance(0.8)
	end
	local function loaded(p)
		return K.waitFor(function()
			return DS().GetProfile(p) ~= nil and not DS().IsProvisional(p)
		end, 10)
	end
	local function standAt(p, pos)
		local r = K.root(p)
		if r then
			r.CFrame = CFrame.new(pos)
		end
	end
	local function remote(name)
		return K.remoteFolder()[name]
	end
	local function stored(uid)
		return Mock.DataStore.Data[K.config().Tokens.DataStoreName .. "/u_" .. uid]
	end
	local function shop()
		return K.W.lobbyInfo and K.W.lobbyInfo.Shop
	end
	local function trovePrompt()
		local s = shop()
		local part = s and s.ItemShop and s.ItemShop.PromptPart
		return part and part:FindFirstChildOfClass("ProximityPrompt")
	end
	local function near(p)
		standAt(p, shop().ItemShop.Center + Vector3.new(0, 3, -6))
	end
	local function lastState(p, mark)
		local e = K.lastRemote("TroveState", p.UserId, mark)
		local st = e and e.args[1]
		return type(st) == "table" and st or nil
	end
	local function groupState(st)
		return st and type(st.Asks) == "table" and st.Asks[1] and st.Asks[1].State or nil
	end
	local function toasts(p, needle, mark)
		local n = 0
		for _, e in ipairs(K.remotesFor("Notify", p.UserId, mark or 0)) do
			if string.find(tostring(e.args[1]), needle, 1, true) then
				n = n + 1
			end
		end
		return n
	end
	-- runs fn with Config.Trove.GroupId = gid and restores the old id and the player's double afterwards
	local function withGroup(gid, fn)
		local Config = K.config()
		local old = Config.Trove.GroupId
		Config.Trove.GroupId = gid
		local ok, err = pcall(fn)
		Config.Trove.GroupId = old
		if not ok then
			T.fail("trove: the scenario body raised", tostring(err))
		end
	end

	S.trove_build = guarded("trove_build", function()
		if not K.needBoot() then
			return
		end
		local Config, Theme = K.config(), K.M["shared/Theme"]
		local s = shop()
		local stall = s and s.ItemShop
		local model = stall and stall.Model
		if not T.check(model and model.Name == "SkyTrove" and stall.PromptPart and stall.Lid and stall.Lid:IsA("Model"), "trove build: LobbyInfo.Shop.ItemShop points at the SkyTrove model with its PromptPart and Lid", model and model.Name) then
			return
		end
		T.check(typeof(stall.Center) == "Vector3" and model.PrimaryPart ~= nil, "trove build: Center is a Vector3 and the model has a PrimaryPart")
		T.check(workspace.NimbusLobby.Shop:FindFirstChild("ItemShop") == nil, "trove build: the boarded-up stall is gone")
		T.check(#model:GetDescendants() > 0 and countParts(model) <= 60, "trove build: <= 60 parts", tostring(countParts(model)))
		T.check(#CollectionService:GetTagged(Config.Tags.TroveLid) == 1 and CollectionService:GetTagged(Config.Tags.TroveLid)[1] == stall.Lid, "trove build: one tagged lid (the Lid model)")
		T.check(stall.Lid.PrimaryPart ~= nil, "trove build: the lid has a PrimaryPart (the hinge the client swings)")
		local prompt = trovePrompt()
		T.check(prompt and prompt.ObjectText == "Sky Trove" and prompt.ActionText == "Open" and prompt.MaxActivationDistance == 10 and prompt.HoldDuration == 0 and prompt.RequiresLineOfSight == false, "trove build: the prompt (service-made)")
		local detail = 0
		for _, d in ipairs(model:GetDescendants()) do
			if CollectionService:HasTag(d, "NC_Detail") and (d:FindFirstChildOfClass("PointLight") or d:FindFirstChildOfClass("ParticleEmitter")) then
				detail = detail + 1
			end
		end
		T.check(detail >= 1, "trove build: the gap's light and sparkles sit on an NC_Detail part (Low graphics parks them)")
		-- world-text census: every TextLabel under the model uses a Theme font role
		local fonts = {}
		for _, f in pairs(Theme.Fonts) do
			fonts[f] = true
		end
		local bad, labels, title = {}, 0, nil
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("TextLabel") then
				labels = labels + 1
				if not fonts[d.Font] then
					bad[#bad + 1] = d.Name
				end
				if d.Name == "Title" then
					title = d
				end
			end
		end
		T.check(labels > 0 and #bad == 0, "trove build: every TextLabel under the model uses a Theme font role", table.concat(bad, ", "))
		T.check(title ~= nil and title.Text == "SKY TROVE" and title:IsDescendantOf(stall.Lid), "trove build: the lid plate's Title reads SKY TROVE", title and title.Text)
		local bb = model:FindFirstChild("TroveBillboard", true)
		T.check(bb ~= nil and bb:IsA("BillboardGui") and bb:IsDescendantOf(stall.Lid), "trove build: the TroveBillboard rides the lid")
		local front = (stall.PromptPart.Position - stall.Center)
		T.check(front.Magnitude < 10, "trove build: the PromptPart stands in front of the chest", tostring(front.Magnitude))
		-- lobby shop (spec 5.9): the chest stands on the plaza lawn (polar 43 degrees, r 56), off the shop island
		local L = Config.Lobby
		local o = L.Origin
		local spot = Vector3.new(o.X + math.cos(math.rad(43)) * 56, 0, o.Z + math.sin(math.rad(43)) * 56)
		local off = Vector3.new(stall.Center.X - spot.X, 0, stall.Center.Z - spot.Z).Magnitude
		local shopC = Vector3.new(o.X + L.ShopOffset.X, 0, o.Z + L.ShopOffset.Z)
		local fromShop = Vector3.new(stall.Center.X - shopC.X, 0, stall.Center.Z - shopC.Z).Magnitude
		T.check(off <= 0.5 and fromShop > 60, "trove build: the chest stands on the plaza lawn (polar 43, r 56), not on the shop island",
			string.format("%.2f off the spot, %.1f from the shop's centre", off, fromShop))
	end)

	S.trove_group_once = guarded("trove_group_once", function()
		if not K.needBoot() then
			return
		end
		local prompt = trovePrompt()
		if not T.check(prompt ~= nil and TS() ~= nil, "trove once: (precondition) the prompt and TroveService exist") then
			return
		end
		local p = join("Trove", newUserId())
		T.check(loaded(p), "trove once: (precondition) the profile loads")
		withGroup(777, function()
			local calls = 0
			p.IsInGroupAsync = function(_, gid)
				calls = calls + 1
				return gid == 777
			end
			local before, beforeTokens = DS().GetCash(p), DS().GetTokens(p)
			near(p)
			local mark = K.logSize()
			Mock.Trigger(prompt, p)
			K.advance(0.1)
			local open = K.lastRemote("OpenPanel", p.UserId, mark)
			local st = lastState(p, mark)
			T.check(open ~= nil and open.args[1] == "Trove" and groupState(st) == "Open", "trove once: the prompt opens the panel with the Group row Open", tostring(open and open.args[1]) .. " / " .. tostring(groupState(st)))
			T.check(st ~= nil and st.GroupId == 777 and st.Asks[1].Reward and st.Asks[1].Reward.Cash == 2000 and st.Asks[1].Reward.Tokens == 200, "trove once: the state carries the group id and the reward")
			T.eq(calls, 0, "trove once: no IsInGroupAsync before Joined")
			mark = K.logSize()
			Mock.FromClient(remote("TroveRequest"), p, "Joined")
			K.advance(0.5)
			local trove = DS().GetTrove and DS().GetTrove(p)
			T.check(calls == 1 and DS().GetCash(p) == before + 2000 and DS().GetTokens(p) == beforeTokens + 200 and type(trove) == "table" and trove.Group == true, "trove once: ONE call, the exact grant, the ask set", string.format("calls %d cash +%s tokens +%s", calls, tostring(DS().GetCash(p) - before), tostring(DS().GetTokens(p) - beforeTokens)))
			T.eq(toasts(p, REWARD_TEXT, mark), 1, "trove once: the reward toast once")
			T.eq(groupState(lastState(p, mark)), "Done", "trove once: TroveState says Done")
			Mock.FromClient(remote("TroveRequest"), p, "Joined")
			K.advance(1.5)
			Mock.FromClient(remote("TroveRequest"), p, "Joined")
			K.advance(0.5)
			T.check(calls == 1 and DS().GetCash(p) == before + 2000, "trove once: a second Joined grants nothing and makes no call", "calls " .. calls)
			DS().Save(p)
			local rec = stored(p.UserId) or {}
			T.check(type(rec.Trove) == "table" and rec.Trove.Group == true and (rec.Cash or 0) >= 2000, "trove once: saved with its grant")
			p.IsInGroupAsync = nil
		end)
		leave(p)
	end)

	S.trove_stale_once = guarded("trove_stale_once", function()
		if not K.needBoot() then
			return
		end
		local uid = newUserId()
		local p = join("TroveStale", uid)
		T.check(loaded(p), "trove stale: (precondition) the profile loads")
		withGroup(777, function()
			local calls, answer = 0, false
			local function double(_, gid)
				calls = calls + 1
				return answer and gid == 777
			end
			p.IsInGroupAsync = double
			local mark = K.logSize()
			Mock.FromClient(remote("TroveRequest"), p, "Joined")
			K.advance(0.5)
			T.check(calls == 1 and toasts(p, CHECKED_NEEDLE, mark) == 1 and groupState(lastState(p, mark)) == "Checked", "trove stale: a false answer = one call, the Rejoin toast, State Checked", "calls " .. calls)
			T.check(groupState(TS().State(p)) == "Checked", "trove stale: TroveService.State agrees (Checked)")
			answer = true
			K.advance(1.2)
			mark = K.logSize()
			Mock.FromClient(remote("TroveRequest"), p, "Joined")
			K.advance(0.5)
			T.check(calls == 1 and (DS().GetTrove and DS().GetTrove(p) or {}).Group ~= true, "trove stale: a second Joined on the same server makes no call and grants nothing", "calls " .. calls)
			T.eq(toasts(p, CHECKED_NEEDLE, mark), 1, "trove stale: ...it answers the Rejoin copy again")
			p.IsInGroupAsync = nil
			leave(p)
			local p2 = join("TroveStale", uid)
			T.check(loaded(p2), "trove stale: (precondition) the rejoin loads")
			p2.IsInGroupAsync = double
			local cash = DS().GetCash(p2)
			Mock.FromClient(remote("TroveRequest"), p2, "Joined")
			K.advance(0.5)
			T.check(calls == 2 and (DS().GetTrove and DS().GetTrove(p2) or {}).Group == true and DS().GetCash(p2) == cash + 2000, "trove stale: a rejoin asks again (call 2) and grants once", "calls " .. calls)
			p2.IsInGroupAsync = nil
			leave(p2)
		end)
	end)

	S.trove_provisional = guarded("trove_provisional", function()
		if not K.needBoot() then
			return
		end
		local savedFail = Mock.DataStore.Fail
		Mock.DataStore.Fail = true
		local p = join("TroveProv", newUserId())
		local isProv = K.waitFor(function()
			return DS().IsProvisional(p) == true
		end, 10)
		T.check(isProv, "trove provisional: (precondition) a load during an outage leaves a provisional profile")
		withGroup(777, function()
			local calls = 0
			p.IsInGroupAsync = function(_, gid)
				calls = calls + 1
				return gid == 777
			end
			local mark = K.logSize()
			Mock.FromClient(remote("TroveRequest"), p, "Joined")
			K.advance(0.5)
			T.check(calls == 0 and groupState(lastState(p, mark)) == "Loading", "trove provisional: Joined makes no call and answers State Loading", "calls " .. calls .. " state " .. tostring(groupState(lastState(p, mark))))
			T.check(DS().GetProfile(p) == nil or (DS().GetProfile(p).Trove or {}).Group ~= true, "trove provisional: ...and grants nothing")
			Mock.DataStore.Fail = savedFail
			local back = K.waitFor(function()
				return DS().IsProvisional(p) ~= true
			end, 60)
			T.check(back, "trove provisional: (precondition) the recovery reads the real save")
			K.advance(1.2)
			local cash = DS().GetCash(p)
			Mock.FromClient(remote("TroveRequest"), p, "Joined")
			K.advance(0.5)
			T.check(calls == 1 and (DS().GetTrove and DS().GetTrove(p) or {}).Group == true and DS().GetCash(p) == cash + 2000, "trove provisional: after the recovery Joined grants once", "calls " .. calls)
			p.IsInGroupAsync = nil
		end)
		Mock.DataStore.Fail = savedFail
		leave(p)
	end)

	-- a second, independent copy of DataService ("server B": its own cache, the same mock DataStore; the
	-- smoke_p4_data.lua secondServer shape); release() destroys the clone and drops the PlayerRemoving / remote hooks
	local function secondServer(name)
		local inst = K.moduleInstance("server/Services/DataService")
		if not inst then
			return nil
		end
		local sigs = { game:GetService("Players").PlayerRemoving }
		for _, rn in ipairs({ "RequestProfile", "SettingsSet" }) do
			local r = K.remoteFolder():FindFirstChild(rn)
			if r then
				sigs[#sigs + 1] = r.OnServerEvent
			end
		end
		local marks = {}
		for i, sig in ipairs(sigs) do
			local conns = type(sig) == "table" and rawget(sig, "_conns") or nil
			marks[i] = { conns = conns, n = conns and #conns or 0 }
		end
		local clone = inst:Clone()
		clone.Name = name
		clone.Parent = inst.Parent
		local ok, module = pcall(require, clone)
		if not ok then
			clone:Destroy()
			return nil, module
		end
		local function release()
			clone:Destroy()
			for _, m in ipairs(marks) do
				if m.conns then
					for i = #m.conns, m.n + 1, -1 do
						local c = m.conns[i]
						if type(c) == "table" and c.Disconnect then
							c:Disconnect()
						end
					end
				end
			end
		end
		return module, clone, release
	end

	S.trove_two_servers = guarded("trove_two_servers", function()
		if not K.needBoot() then
			return
		end
		local prompt = trovePrompt()
		local uid = newUserId()
		local p = join("TroveTwo", uid)
		T.check(loaded(p), "trove two servers: (precondition) the profile loads")
		local savedFail = Mock.DataStore.Fail
		withGroup(777, function()
			DS().Save(p)
			-- the store fails from here on (no autosave may carry A's grant before B reads the store)
			Mock.DataStore.Fail = true
			p.IsInGroupAsync = function(_, gid)
				return gid == 777
			end
			near(p)
			Mock.Trigger(prompt, p)
			K.advance(0.1)
			Mock.FromClient(remote("TroveRequest"), p, "Joined")
			K.advance(0.5)
			T.check((DS().GetTrove and DS().GetTrove(p) or {}).Group == true, "trove two servers: server A granted through the service")
			DS().AddCash(p, 7) -- A's marker: proves A's orphan retry landed
			local liveCash, liveTokens = DS().GetCash(p), DS().GetTokens(p)
			p.IsInGroupAsync = nil
			T.eq(DS().Save(p), false, "trove two servers: server A's save fails")
			leave(p)
			Mock.DataStore.Fail = savedFail
			local B, cloneB, releaseB = secondServer("DataServiceTroveB")
			if T.check(B ~= nil and type(B.MarkTrove) == "function", "trove two servers: a second copy of DataService loads as server B (with MarkTrove)", tostring(cloneB)) then
				local okB, errB = pcall(function()
					B.Load(p)
					local reward = { Cash = 2000, Tokens = 200 }
					T.check(B.MarkTrove(p, "Group", reward) == true, "trove two servers: server B marks the ask (it loaded the store before A's save)")
					B.AddCash(p, 2000)
					B.AddTokens(p, 200)
					T.eq(B.Save(p), true, "trove two servers: server B saves its grant")
				end)
				T.check(okB, "trove two servers: server B ran", tostring(errB))
				releaseB()
				local landed = K.waitFor(function()
					local rec = stored(uid)
					return rec ~= nil and rec.Cash == liveCash
				end, 40)
				local rec = stored(uid) or {}
				T.check(landed and rec.Cash == liveCash and rec.Tokens == liveTokens and type(rec.Trove) == "table" and rec.Trove.Group == true, "trove two servers: A's orphan retry lands: Cash +2000 once, Tokens +200 once, Trove.Group true", string.format("stored cash %s / %s, tokens %s / %s", tostring(rec.Cash), tostring(liveCash), tostring(rec.Tokens), tostring(liveTokens)))
			end
		end)
		Mock.DataStore.Fail = savedFail
	end)

	S.trove_no_discord = guarded("trove_no_discord", function()
		local scanned, hits = 0, {}
		for _, d in ipairs(game:GetDescendants()) do
			local cls = d.ClassName
			if cls == "ModuleScript" or cls == "Script" or cls == "LocalScript" then
				local ok, src = pcall(function()
					return d.Source
				end)
				if ok and type(src) == "string" and src ~= "" then
					scanned = scanned + 1
					if src:lower():find("discord", 1, true) then
						hits[#hits + 1] = d:GetFullName()
					end
				end
			end
		end
		T.check(scanned >= 100, "trove no discord: (precondition) the mounted src/ sources were scanned", tostring(scanned))
		T.check(#hits == 0, "trove no discord: no source under src/ says discord", table.concat(hits, ", "))
		local svc = TS()
		if not T.check(svc ~= nil and type(svc.State) == "function", "trove no discord: TroveService.State exists") then
			return
		end
		local p = Mock.AddPlayer("TroveAsks", newUserId())
		K.advance(0.5)
		local st = svc.State(p)
		T.check(type(st) == "table" and #st.Asks == 2 and st.Asks[1].Id == "Group" and st.Asks[2].Id == "Like" and st.Asks[2].Reward == nil, "trove no discord: State has two asks, Group and Like (no reward on Like)")
		Mock.RemovePlayer(p)
		K.advance(0.5)
	end)

	S.trove_exploits = guarded("trove_exploits", function()
		if not K.needBoot() then
			return
		end
		local Config = K.config()
		local prompt = trovePrompt()
		if not T.check(prompt ~= nil and TS() ~= nil, "trove exploits: (precondition) the prompt and TroveService exist") then
			return
		end
		local p = join("TroveX", newUserId())
		loaded(p)
		local function opens(mark)
			return #K.remotesFor("OpenPanel", p.UserId, mark)
		end
		withGroup(777, function()
			-- from afar
			standAt(p, shop().ItemShop.Center + Vector3.new(30, 3, 0))
			local mark = K.logSize()
			Mock.Trigger(prompt, p)
			K.advance(0.1)
			T.eq(opens(mark), 0, "trove exploits: a Trigger from 30 studs away opens nothing")
			-- in a match / in a battle
			near(p)
			p:SetAttribute(Config.Attr.InMatch, true)
			mark = K.logSize()
			Mock.Trigger(prompt, p)
			K.advance(0.1)
			T.eq(opens(mark), 0, "trove exploits: in a match: nothing")
			p:SetAttribute(Config.Attr.InMatch, false)
			p:SetAttribute(Config.Attr.InBattle, "B1")
			mark = K.logSize()
			Mock.Trigger(prompt, p)
			K.advance(0.1)
			T.eq(opens(mark), 0, "trove exploits: in a battle: nothing")
			p:SetAttribute(Config.Attr.InBattle, nil)
			-- the cooldown
			near(p)
			mark = K.logSize()
			Mock.Trigger(prompt, p)
			K.advance(1)
			Mock.Trigger(prompt, p)
			K.advance(0.1)
			T.eq(opens(mark), 1, "trove exploits: two Triggers within 5 s = one OpenPanel")
			K.advance(5)
			mark = K.logSize()
			Mock.Trigger(prompt, p)
			K.advance(0.1)
			T.eq(opens(mark), 1, "trove exploits: ...and the next one after the cooldown opens again")
			-- junk
			local errs = #Mock.Errors
			local calls = 0
			p.IsInGroupAsync = function()
				calls = calls + 1
				return false
			end
			mark = K.logSize()
			for _, junk in ipairs({ "Buy", 5, {}, false }) do
				Mock.FromClient(remote("TroveRequest"), p, junk)
			end
			K.advance(0.2)
			T.check(#Mock.Errors == errs and calls == 0 and #K.remotesFor("Notify", p.UserId, mark) == 0 and #K.remotesFor("TroveState", p.UserId, mark) == 0, "trove exploits: junk TroveRequest does nothing and raises nothing")
			-- a burst
			K.advance(1.2)
			for _ = 1, 20 do
				Mock.FromClient(remote("TroveRequest"), p, "Joined")
				K.advance(0.05)
			end
			K.advance(0.5)
			T.check(calls <= 1, "trove exploits: 20 Joined in a second = at most one IsInGroupAsync call", "calls " .. calls)
			T.eq(#Mock.Errors, errs, "trove exploits: ...and nothing raised")
			p.IsInGroupAsync = nil
		end)
		withGroup(0, function()
			local calls = 0
			p.IsInGroupAsync = function()
				calls = calls + 1
				return true
			end
			p:SetAttribute(Config.Attr.StorePreview, false)
			K.advance(1.2)
			local mark = K.logSize()
			Mock.FromClient(remote("TroveRequest"), p, "Joined")
			K.advance(0.3)
			local trove = DS().GetTrove and DS().GetTrove(p)
			T.check(calls == 0 and (trove == nil or trove.Group ~= true), "trove exploits: GroupId 0 = Joined refused, no call", "calls " .. calls)
			T.eq(groupState(TS().State(p)), "Soon", "trove exploits: GroupId 0 = State Soon")
			p:SetAttribute(Config.Attr.StorePreview, true)
			T.eq(groupState(TS().State(p)), "Preview", "trove exploits: GroupId 0 under the StorePreview attribute = State Preview")
			T.eq(TS().State(p).Preview, true, "trove exploits: ...and Preview = true")
			p:SetAttribute(Config.Attr.StorePreview, nil)
			p.IsInGroupAsync = nil
		end)
		leave(p)
	end)

	return S
end

----------------------------------------------------------------------------------------------------
-- client world
----------------------------------------------------------------------------------------------------
local function clientScenarios()
	local S = {}
	local KC = _G.KC
	local CollectionService = game:GetService("CollectionService")
	local GuiService = game:GetService("GuiService")
	local Players = game:GetService("Players")

	-- a module of the client build (the H.moduleAt shape of smoke_evo_retreat.lua; ROOTS is smoke.py's)
	local function moduleAt(top, rest)
		local inst = Mock.GetPath(ROOTS[top] .. "/" .. rest)
		if not inst then
			return nil
		end
		local ok, result = pcall(require, inst)
		return ok and type(result) == "table" and result or nil
	end
	local function find(root, name)
		if not root then
			return nil
		end
		for _, d in ipairs(root:GetDescendants()) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end
	local function shownButtons(root)
		local out = {}
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if d:IsA("TextButton") and KC.isShown(d) then
				out[#out + 1] = d
			end
		end
		return out
	end
	local function disabled(b)
		return b:GetAttribute("Disabled") == true or b.Active == false
	end
	local function stateOf(groupState, gid)
		return { GroupId = gid or 777, Preview = groupState == "Preview", Asks = { { Id = "Group", State = groupState, Reward = { Cash = 2000, Tokens = 200 } }, { Id = "Like" } } }
	end
	local function insetY()
		local inset = 58
		pcall(function()
			inset = GuiService:GetGuiInset().Y
		end)
		return inset
	end
	-- a stand-in for the lobby's tagged lid (the client world has no LobbyBuilder): a hinge PrimaryPart and a slab
	local function fakeLid(Config)
		for _, old in ipairs(CollectionService:GetTagged(Config.Tags.TroveLid)) do
			old:Destroy()
		end
		local m = Instance.new("Model")
		m.Name = "TroveLidTest"
		local hinge = Instance.new("Part")
		hinge.Name = "Hinge"
		hinge.Anchored = true
		hinge.Size = Vector3.new(0.4, 0.4, 0.4)
		hinge.CFrame = CFrame.new(10, 5, 10) * CFrame.Angles(math.rad(18), 0, 0)
		hinge.Parent = m
		local slab = Instance.new("Part")
		slab.Name = "Slab"
		slab.Anchored = true
		slab.Size = Vector3.new(9, 1, 6)
		slab.CFrame = hinge.CFrame * CFrame.new(0, 0.5, -3)
		slab.Parent = m
		m.PrimaryPart = hinge
		m.Parent = workspace
		CollectionService:AddTag(m, Config.Tags.TroveLid)
		return m
	end
	local function coinCount()
		local f = workspace:FindFirstChild("TroveCoins")
		local n = 0
		for _, d in ipairs(f and f:GetChildren() or {}) do
			if d:IsA("BasePart") then
				n = n + 1
			end
		end
		return n
	end

	S.client_trove = guarded("client_trove", function()
		local Config, _, Theme = KC.env()
		local TC = moduleAt("client", "Controllers/TroveController")
		if not T.check(type(TC) == "table" and type(TC.Open) == "function" and type(TC.IsOpen) == "function", "client trove: TroveController loads") then
			return
		end
		local GQ = moduleAt("client", "GraphicsQuality")
		local LocalPlayer = Players.LocalPlayer
		local old = { Mock.Viewport.X, Mock.Viewport.Y }
		Mock.SetViewport(1920, 1080)
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		LocalPlayer:SetAttribute(Config.Attr.InBattle, nil)
		if GQ and GQ.Apply then
			pcall(GQ.Apply, "High")
		end
		local lid = fakeLid(Config)
		KC.advance(0.3)
		KC.toClient("OpenPanel", "Trove")
		KC.toClient("TroveState", stateOf("Open"))
		KC.advance(0.4)
		local gui = KC.gui():FindFirstChild("NimbusTrove")
		local panel = gui and gui:FindFirstChild("TrovePanel")
		if not T.check(gui ~= nil and gui:IsA("ScreenGui") and gui.DisplayOrder == 18 and panel ~= nil and KC.isShown(panel) and TC.IsOpen(), "client trove: OpenPanel('Trove') shows NimbusTrove (DisplayOrder 18)") then
			Mock.SetViewport(old[1], old[2])
			return
		end
		local f = Theme.ScreenFactor(1080)
		local right = panel.AbsolutePosition.X + panel.AbsoluteSize.X
		T.check(1920 - right >= 0 and 1920 - right <= 12 * f + 1, "client trove: docked right, 12 x factor from the edge", tostring(1920 - right))
		T.check(panel.AbsoluteSize.X <= 0.44 * 1920, "client trove: width <= 0.44 W", tostring(panel.AbsoluteSize.X))
		local guiTop = gui.IgnoreGuiInset and 0 or insetY() -- AbsolutePosition is in the gui's area (below the top bar unless IgnoreGuiInset)
		T.check(math.abs(panel.AbsolutePosition.Y + guiTop - (insetY() + 8 * f)) <= 1, "client trove: top = inset + 8 x factor (screen space)", tostring(panel.AbsolutePosition.Y + guiTop))
		local join = find(panel, "JoinButton")
		T.check(join ~= nil and KC.isShown(join) and join.Text == "JOIN" and not disabled(join), "client trove: JOIN enabled", join and join.Text)
		local like = find(panel, "Row_Like")
		T.check(like ~= nil and #shownButtons(like) == 0 and find(like, "Label") ~= nil and find(like, "Label").Text == "Enjoying it? A thumbs up on our game page helps a lot!", "client trove: the Like row has its line and no button")
		local footer = find(panel, "Footer")
		T.check(footer ~= nil and footer.Text == FOOTER, "client trove: the footer line", footer and footer.Text)
		local glabel = find(find(panel, "Row_Group"), "Label")
		T.check(glabel ~= nil and glabel.Text == "Join the Nimbus Climb group" and KC.findText("$2,000", panel) ~= nil and KC.findText("200 Tokens", panel) ~= nil, "client trove: the Group row's label and reward chips")
		-- JOIN: the GroupService double
		local GroupS = game:GetService("GroupService")
		GroupS.PromptJoinAsync = function()
			return Enum.GroupMembershipStatus.JoinRequestPending
		end
		local mark = #Mock.RemoteLog
		Mock.Click(join)
		KC.advance(0.3)
		local hint = find(panel, "Hint")
		T.check(hint ~= nil and KC.isShown(hint) and hint.Text == PENDING_HINT, "client trove: JoinRequestPending = the hint", hint and hint.Text)
		T.eq(#KC.serverCalls("TroveRequest", mark), 0, "client trove: ...and no TroveRequest")
		GroupS.PromptJoinAsync = function()
			return Enum.GroupMembershipStatus.Joined
		end
		mark = #Mock.RemoteLog
		Mock.Click(join)
		KC.advance(0.3)
		local calls = KC.serverCalls("TroveRequest", mark)
		T.check(#calls == 1 and calls[1].args[1] == "Joined", "client trove: Joined = TroveRequest('Joined') once", tostring(#calls))
		GroupS.PromptJoinAsync = nil
		-- DONE plays the claim (High)
		local before = lid.PrimaryPart.CFrame
		KC.toClient("TroveState", stateOf("Done"))
		KC.advance(0.1)
		join = find(panel, "JoinButton")
		T.check(join ~= nil and join.Text == "DONE" and disabled(join), "client trove: Done = DONE, disabled", join and join.Text)
		T.eq(coinCount(), 18, "client trove: 18 coin parts fly (High)")
		KC.advance(0.4)
		local moved = (lid.PrimaryPart.CFrame.LookVector - before.LookVector).Magnitude > 0.1
		T.check(moved, "client trove: the lid swung within 0.5 s (High)")
		KC.advance(1.6)
		T.eq(coinCount(), 0, "client trove: the coins are gone within 2 s")
		-- Low: the lid only
		if GQ and GQ.Apply then
			KC.toClient("TroveState", stateOf("Open"))
			KC.advance(0.1)
			pcall(GQ.Apply, "Low")
			KC.advance(0.6)
			KC.toClient("TroveState", stateOf("Done"))
			KC.advance(0.1)
			T.eq(coinCount(), 0, "client trove: Low = no coin parts")
			pcall(GQ.Apply, "High")
			KC.advance(0.6)
		end
		-- the other states
		KC.toClient("TroveState", stateOf("Checked"))
		KC.advance(0.1)
		T.eq(#shownButtons(find(panel, "Row_Group")), 0, "client trove: Checked = no button")
		KC.toClient("TroveState", stateOf("Soon", 0))
		KC.advance(0.1)
		glabel = find(find(panel, "Row_Group"), "Label")
		T.check(#shownButtons(find(panel, "Row_Group")) == 0 and glabel and glabel.Text == "Coming soon", "client trove: GroupId 0 (Soon) = Coming soon, no button", glabel and glabel.Text)
		KC.toClient("TroveState", stateOf("Preview", 0))
		KC.advance(0.1)
		join = find(panel, "JoinButton")
		T.check(join ~= nil and KC.isShown(join) and join.Text == "PREVIEW" and disabled(join), "client trove: Preview = PREVIEW, disabled", join and join.Text)
		-- nothing in the middle 30 % of the screen
		local centred = {}
		for _, d in ipairs(gui:GetDescendants()) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and KC.isShown(d) and tostring(d.Text) ~= "" then
				local cx = d.AbsolutePosition.X + d.AbsoluteSize.X / 2
				local cy = d.AbsolutePosition.Y + d.AbsoluteSize.Y / 2 + guiTop
				if math.abs(cx - 960) < 0.15 * 1920 and math.abs(cy - 540) < 0.15 * 1080 then
					centred[#centred + 1] = d.Name
				end
			end
		end
		T.check(#centred == 0, "client trove: no text in the middle 30 % of the screen", table.concat(centred, ", "))
		-- the window rule (spec 8): the controller's own listener closes it on any other window
		local PC = moduleAt("client", "Controllers/PetsController")
		local MC = moduleAt("client", "Controllers/MenuController")
		if PC and type(PC.Open) == "function" then
			TC.Open(stateOf("Open"))
			KC.advance(0.3)
			pcall(PC.Open, {})
			KC.advance(0.4)
			T.check(TC.IsOpen() == false, "client trove: PetsController.Open() over the open Trove closes the Trove")
			pcall(PC.Close)
			KC.advance(0.3)
			-- (green once Task 7's MenuController WindowOpened handler closes Pets on "Trove")
			pcall(PC.Open, {})
			KC.advance(0.4)
			local petsWas = PC.IsOpen()
			KC.toClient("OpenPanel", "Trove")
			KC.advance(0.4)
			T.check(petsWas and PC.IsOpen() == false, "client trove: OpenPanel('Trove') over the Pets window closes Pets (MenuController's WindowOpened handler, Task 7)", "pets open before " .. tostring(petsWas))
			pcall(PC.Close)
		end
		-- a match closes it
		TC.Open(stateOf("Open"))
		KC.advance(0.2)
		LocalPlayer:SetAttribute(Config.Attr.InMatch, true)
		KC.advance(0.3)
		T.check(TC.IsOpen() == false, "client trove: entering a match closes it")
		LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		pcall(TC.Close)
		if MC and MC.Close then
			pcall(MC.Close)
		end
		lid:Destroy()
		Mock.SetViewport(old[1], old[2])
		KC.advance(0.5)
		KC.flushErrors("client_trove")
	end)

	S.client_trove_mobile = guarded("client_trove_mobile", function()
		local Config = KC.env()
		local TC = moduleAt("client", "Controllers/TroveController")
		if not T.check(type(TC) == "table" and type(TC.Open) == "function", "trove mobile: TroveController loads") then
			return
		end
		local old = { Mock.Viewport.X, Mock.Viewport.Y }
		Mock.SetViewport(844, 390)
		Players.LocalPlayer:SetAttribute(Config.Attr.InMatch, false)
		KC.advance(0.3)
		TC.Open(stateOf("Open"))
		KC.advance(0.4)
		local gui = KC.gui():FindFirstChild("NimbusTrove")
		local panel = gui and gui:FindFirstChild("TrovePanel")
		if not T.check(panel ~= nil and KC.isShown(panel), "trove mobile: the panel opens") then
			Mock.SetViewport(old[1], old[2])
			return
		end
		local scale = panel:FindFirstChildOfClass("UIScale")
		T.check(math.abs(panel.AbsoluteSize.X - 352) <= 1 and math.abs(panel.AbsoluteSize.Y - 236) <= 1 and (scale == nil or scale.Scale == 1), "trove mobile: 352 x 236 at scale 1", string.format("%.0fx%.0f", panel.AbsoluteSize.X, panel.AbsoluteSize.Y))
		local right = 844 - (panel.AbsolutePosition.X + panel.AbsoluteSize.X)
		T.check(math.abs(right - 12) <= 1, "trove mobile: 12 px from the right", tostring(right))
		local guiTop = gui.IgnoreGuiInset and 0 or insetY()
		T.check(math.abs(panel.AbsolutePosition.Y + guiTop - (insetY() + 8)) <= 1, "trove mobile: top = inset + 8 (screen space)", tostring(panel.AbsolutePosition.Y + guiTop))
		local small = {}
		for _, d in ipairs(panel:GetDescendants()) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and KC.isShown(d) and tostring(d.Text) ~= "" and d.TextSize < 15 then
				small[#small + 1] = d.Name .. " " .. d.TextSize
			end
		end
		T.check(#small == 0, "trove mobile: every text >= 15 px", table.concat(small, ", "))
		local join = find(panel, "JoinButton")
		T.check(join ~= nil and join.AbsoluteSize.Y >= 44, "trove mobile: the button is >= 44 px tall", join and tostring(join.AbsoluteSize.Y))
		T.check(GuiService.TouchControlsEnabled == true, "trove mobile: Roblox's touch controls stay")
		pcall(TC.Close)
		Mock.SetViewport(old[1], old[2])
		KC.advance(0.5)
		KC.flushErrors("client_trove_mobile")
	end)

	return S
end

if CONTEXT == "server" then
	return serverScenarios()
end
return clientScenarios()
