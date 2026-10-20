-- MeshFallback (Phase 6, review3 runtime-2; owner fix-meshlib): the per-device Part fallback for SERVER-built mesh pets.
--
-- NPC pets, the lobby fountain statue, the podium pets and the Storm Altar Stormfang are built (or swapped) on the
-- server and replicate as MeshParts. A device whose ContentProvider:PreloadAsync failed for one of their keys
-- (MeshLibrary.Status(key) == "failed" here) cannot draw them. On such a device this watcher hides the model's
-- MeshParts LOCALLY and puts a local Part copy inside it (PetBuilder.Build(PetBuilder.ServerDef(model)) with Parts =
-- true), welded to the model's root so it follows every move (PivotTo / root CFrame); the server model, its tags,
-- prompts and PetFx stay untouched. Recipe 4.8: "a client fetch failure degrades per key to the Part build".
--
-- Why this and not "hide the mesh only": hiding alone leaves an invisible pet; the server cannot keep a hidden Part
-- copy either (thousands of extra replicated parts for every player). The definition is already on the model
-- (PetBuilder.MESH.stamp: PBD_* attributes), so the copy is the exact Part pet this device would have built itself.
--
-- Cost: nothing while MeshIds is empty (Start returns before connecting anything = today's game). Otherwise one
-- CollectionService signal + one MeshLibrary.Changed handler; never per frame. A model is checked when it streams in
-- and when a key it uses changes status here; at most once rebuilt (weak-keyed memo).
--
--   MeshFallback.Start() / Init()   idempotent (Start(true): tests only, skips the MeshIds check); MeshFallback.Stop() disconnects (tests)
--   MeshFallback.Check(model) -> bool   (true = this device shows the Part copy for it)

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshFallback = {}

local COPY_NAME = "ML_PartCopy"
local started = false
local conns = {}
local done = setmetatable({}, { __mode = "k" }) -- model -> true once handled (copy made or nothing to do ever)
local ML, PB = nil, nil

local function shared(name)
	local folder = ReplicatedStorage:FindFirstChild("Shared")
	local mod = folder and folder:FindFirstChild(name)
	if not mod then
		return nil
	end
	local ok, res = pcall(require, mod)
	return ok and res or nil
end

local function keysOf(model)
	local raw = model:GetAttribute("PBD_Keys")
	if type(raw) ~= "string" or raw == "" then
		raw = model:GetAttribute("ML_Keys")
	end
	local out = {}
	for key in string.gmatch(type(raw) == "string" and raw or "", "[^,]+") do
		out[#out + 1] = key
	end
	return out
end

local function brokenHere(model)
	for _, key in ipairs(keysOf(model)) do
		if ML.Status(key) == "failed" then
			return true
		end
	end
	return false
end

-- the server model's own mesh parts go invisible here (local writes); lids / pulses keep their hidden value
local function hideMesh(model, copy)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("MeshPart") and not d:IsDescendantOf(copy) then
			d.Transparency = 1
			if d:GetAttribute("PB_T0") ~= nil then
				d:SetAttribute("PB_T0", 1)
			end
			if d:GetAttribute("PB_Pulse") ~= nil then
				d:SetAttribute("PB_Pulse", 1)
			end
		end
	end
end

function MeshFallback.Check(model)
	if not started or typeof(model) ~= "Instance" or not model:IsA("Model") or done[model] or not model.Parent then
		return false
	end
	if model:GetAttribute("ML_Mesh") ~= true or not brokenHere(model) then
		return false
	end
	done[model] = true
	local def, opts = PB.ServerDef(model)
	if not def then
		return false
	end
	local ok, copy = pcall(PB.Build, def, opts)
	if not ok or typeof(copy) ~= "Instance" then
		warn("[MeshFallback] no Part copy for " .. model:GetFullName() .. ": " .. tostring(copy))
		return false
	end
	copy.Name = COPY_NAME
	pcall(function()
		copy:PivotTo(model:GetPivot())
	end)
	local root = model.PrimaryPart
	for _, p in ipairs(copy:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.Massless = true
			if root then
				p.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Name = "ML_Weld"
				weld.Part0 = root
				weld.Part1 = p
				weld.Parent = p
			end
		end
	end
	hideMesh(model, copy)
	copy.Parent = model
	return true
end

-- testIds (TESTS ONLY, tools/smoke_p6_pets.lua): skip the MeshIds check (the fixture ids live in MeshLibrary._Configure)
function MeshFallback.Start(testIds)
	if started then
		return
	end
	local okIds, ids = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeshIds", 10))
	end)
	if testIds ~= true and (not okIds or type(ids) ~= "table" or next(ids) == nil) then
		return -- empty MeshIds: today's game, nothing connected
	end
	ML, PB = shared("MeshLibrary"), shared("PetBuilder")
	if type(ML) ~= "table" or type(ML.Status) ~= "function" or type(PB) ~= "table" or type(PB.ServerDef) ~= "function" then
		return
	end
	started = true
	local tag = PB.ServerMeshTag or "PB_ServerMesh"
	conns[#conns + 1] = CollectionService:GetInstanceAddedSignal(tag):Connect(MeshFallback.Check)
	if type(ML.Changed) == "table" then
		conns[#conns + 1] = ML.Changed:Connect(function(key)
			if ML.Status(key) ~= "failed" then
				return
			end
			for _, model in ipairs(CollectionService:GetTagged(tag)) do
				if not done[model] then
					MeshFallback.Check(model)
				end
			end
		end)
	end
	for _, model in ipairs(CollectionService:GetTagged(tag)) do
		MeshFallback.Check(model)
	end
end

function MeshFallback.Init()
	MeshFallback.Start()
end

function MeshFallback.Stop()
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	conns = {}
	started = false
	done = setmetatable({}, { __mode = "k" })
end

return MeshFallback
