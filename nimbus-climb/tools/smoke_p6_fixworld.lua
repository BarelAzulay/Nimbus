-- smoke_p6_fixworld.lua: Phase 6 wave 3b fix-world (docs/phase6/review3-findings.md world-0 / world-1; owner:
-- fix-world). Loaded by tools/smoke.py in BOTH worlds:
--   p6fixworld_board   (server) the booted lobby's THE GATES GuideBoard lists the 5 real Gate Court gates (Obby,
--                      Dungeon, Ring, Arena, Altar) and no Home gate (Phase 6 removed it); the way home is a hint
--                      ("Tap Home, then Go home") in the footer
--   client_p6fixworld  (client) GraphicsQuality Low + a mesh rebuild of the sky dragon: the dragon was Part-built and
--                      paused by Low; its keys become ready, watchMeshes rebuilds it from meshes; the new dragon stays
--                      paused (no parent, no RenderStepped connection, it does not move); switching to High does not
--                      throw, flies the new dragon and still runs PetFx.SetQuality("High"); Low again pauses it again;
--                      a _Rebuild while Low stays paused too. Fixture templates (real MeshLibrary, fake ids), _Reset
--                      afterwards and the Part dragon rebuilt, GraphicsQuality put back to what it was.
-- Deterministic: fixed ids, sorted keys, no pairs() order dependence.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
local IS_SERVER = game:GetService("RunService"):IsServer()
local RS = game:GetService("ReplicatedStorage")

local function req(root, path)
	local ok, inst = pcall(Mock.GetPath, ROOTS[root] .. "/" .. path)
	if not ok or not inst then
		return nil
	end
	local ok2, mod = pcall(require, inst)
	return ok2 and type(mod) == "table" and mod or nil
end

----------------------------------------------------------------------------------------------------------------------
if IS_SERVER then
S.p6fixworld_board = guarded("p6fixworld_board", function()
	local board = nil
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == "GuideBoard" and d:IsA("Model") then
			board = d
			break
		end
	end
	if not T.check(board ~= nil, "p6fixworld board: the lobby has its THE GATES GuideBoard") then
		return
	end
	local keys, descs, all = {}, {}, {}
	for _, d in ipairs(board:GetDescendants()) do
		if d:IsA("TextLabel") then
			all[#all + 1] = d.Text
			if d.Name == "Key" then
				keys[#keys + 1] = d.Text
			elseif d.Name == "Desc" then
				descs[#descs + 1] = d.Text
			end
		end
	end
	table.sort(keys)
	T.eq(table.concat(keys, ","), "ALTAR,ARENA,DUNGEON,OBBY,RING", "p6fixworld board: the rows are the 5 real gates (no HOME gate)")
	local text = table.concat(all, " | ")
	T.check(not string.find(text, "Your sky home", 1, true), "p6fixworld board: no 'Your sky home' gate row left", text)
	T.check(string.find(text, "THE GATES", 1, true) ~= nil, "p6fixworld board: the THE GATES title stays")
	T.check(string.find(text, "Tap Home, then Go home", 1, true) ~= nil, "p6fixworld board: the footer tells kids how to go home", text)
	T.eq(#descs, 5, "p6fixworld board: one description per gate row")
end)
end

----------------------------------------------------------------------------------------------------------------------
if not IS_SERVER then
local function headPart(model)
	local head = model and model:FindFirstChild("Head")
	if not head then
		return nil
	end
	if head:IsA("BasePart") then
		return head
	end
	for _, d in ipairs(head:GetDescendants()) do
		if d:IsA("BasePart") then
			return d
		end
	end
	return nil
end

local function installTemplate(ML, root, key)
	local man = ML.Manifest(key)
	if not man then
		return nil
	end
	local tpl = Instance.new("Model")
	tpl.Name = key
	for _, p in ipairs(man.Parts) do
		local part = Instance.new("MeshPart")
		part.Name = p.name
		part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
		part.CFrame = CFrame.new(p.center[1], p.center[2], p.center[3])
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Parent = tpl
	end
	tpl:SetAttribute("ML_Status", "ready")
	tpl.Parent = root
	return tpl
end

S.client_p6fixworld = guarded("client_p6fixworld", function()
	local KC = _G.KC
	local SD = KC and KC.M and KC.M.SkyDragonController
	local GQ = req("client", "GraphicsQuality")
	local ML = req("shared", "MeshLibrary")
	local PetFx = req("shared", "PetFx")
	if not T.check(SD and type(SD._Rebuild) == "function" and type(SD.MeshKeys) == "function" and GQ and type(GQ.Apply) == "function"
		and ML and type(ML._Configure) == "function" and PetFx and type(PetFx.Quality) == "function",
		"p6fixworld client: SkyDragonController, GraphicsQuality, MeshLibrary (_Configure), PetFx.Quality load") then
		return
	end
	local before = GQ.Effective()
	local Config = req("shared", "Config")
	local cam = workspace.CurrentCamera
	local camBefore = cam.CFrame
	if Config and Config.Lobby and Config.Lobby.Origin then
		cam.CFrame = CFrame.lookAt(Config.Lobby.Origin + Vector3.new(0, 20, 80), Config.Lobby.Origin) -- near: the dragon flies here
	end
	local running = type(SD._IsRunning) == "function" and SD._IsRunning or function()
		return nil
	end

	-- the dragon keys as fixture templates, not preloaded on this device yet
	local keys = SD.MeshKeys()
	table.sort(keys)
	ML._Reset()
	local root = Instance.new("Folder")
	root.Name = "P6FixWorldMeshes"
	root.Parent = RS
	local ids = {}
	for i, key in ipairs(keys) do
		ids[key] = 9500 + i
		installTemplate(ML, root, key)
	end
	ML._Configure({ Root = root, Ids = ids })

	local ok, err = pcall(function()
		-- High first, then a fresh Part dragon (its mesh watcher armed on this MeshLibrary generation)
		GQ.Apply("High")
		T.check(SD._Rebuild() == true and not SD.IsMesh(), "p6fixworld client: the Part dragon flies before the keys are ready")
		local partDragon = SD.GetModel()
		T.check(partDragon ~= nil and partDragon.Parent ~= nil and running() ~= false, "p6fixworld client: the Part dragon is in the world and running")

		-- Low pauses it
		T.eq(GQ.Apply("Low"), "Low", "p6fixworld client: GraphicsQuality goes Low")
		T.check(partDragon.Parent == nil, "p6fixworld client: Low takes the Part dragon out of the world")
		T.check(running() ~= true, "p6fixworld client: Low stops the dragon's RenderStepped work")

		-- the keys become ready on this device: the watcher rebuilds the dragon from meshes
		ML.Start()
		Mock.Advance(1)
		Mock.Advance(0.5)
		T.check(ML.IsReady(keys), "p6fixworld client: every dragon key is ready after the preload")
		local meshDragon = SD.GetModel()
		T.check(SD.IsMesh() and meshDragon ~= nil and meshDragon ~= partDragon and meshDragon:GetAttribute("ML_Mesh") == true,
			"p6fixworld client: the dragon was rebuilt from meshes while Low (watchMeshes)")
		if not meshDragon then
			return
		end
		T.check(meshDragon.Parent == nil, "p6fixworld client: the rebuilt mesh dragon stays paused on Low (no parent)",
			tostring(meshDragon.Parent))
		T.check(running() ~= true, "p6fixworld client: the rebuilt mesh dragon has no RenderStepped connection on Low")
		local head = headPart(meshDragon)
		local p0 = head and head.Position
		Mock.Advance(1)
		T.check(head ~= nil and (head.Position - p0).Magnitude < 1e-4, "p6fixworld client: the paused mesh dragon does not move")
		-- the 3 s boot catch-up must not break anything either
		Mock.Advance(3.5)
		T.check(meshDragon.Parent == nil and SD.GetModel() == meshDragon, "p6fixworld client: still paused after the delayed Low catch-up")

		-- High: no error, the new dragon flies, PetFx follows
		PetFx.SetQuality("Low")
		local okHigh, mode = pcall(GQ.Apply, "High")
		T.check(okHigh and mode == "High", "p6fixworld client: switching to High does not throw", tostring(mode))
		T.eq(PetFx.Quality(), "High", "p6fixworld client: High still runs PetFx.SetQuality('High')")
		T.check(meshDragon.Parent ~= nil and running() ~= false, "p6fixworld client: High puts the mesh dragon back and runs it")
		if head then
			local p1 = head.Position
			Mock.Advance(1)
			T.check((head.Position - p1).Magnitude > 0.5, "p6fixworld client: the mesh dragon flies again on High")
		end

		-- Low again pauses the live model; a rebuild while Low stays paused; High once more is clean
		T.eq(GQ.Apply("Low"), "Low", "p6fixworld client: Low again")
		T.check(meshDragon.Parent == nil and running() ~= true, "p6fixworld client: Low pauses the current (rebuilt) dragon again")
		T.check(SD._Rebuild() == true, "p6fixworld client: _Rebuild while Low")
		local again = SD.GetModel()
		T.check(again ~= nil and again ~= meshDragon and again.Parent == nil and running() ~= true,
			"p6fixworld client: a dragon rebuilt while Low is built paused")
		local okHigh2 = pcall(GQ.Apply, "High")
		T.check(okHigh2 and again.Parent ~= nil and running() ~= false, "p6fixworld client: High after a second rebuild flies it, no error")
	end)
	T.check(ok, "client_p6fixworld ran to the end", tostring(err))

	-- clean up: the shipped (empty) MeshIds, the Part dragon, the graphics setting this world had
	ML._Reset()
	root:Destroy()
	local P6 = rawget(_G, "P6Pets")
	if P6 and P6.MeshMode then
		P6.Install(P6.PetKeys())
	end
	pcall(GQ.Apply, "High")
	T.check(SD._Rebuild() == true and not SD.IsMesh() and SD.GetModel() and SD.GetModel().Parent ~= nil,
		"p6fixworld client: after _Reset the Part dragon flies again")
	if before == "Low" then
		pcall(GQ.Apply, "Low")
	end
	cam.CFrame = camBefore
end)
end

return S
