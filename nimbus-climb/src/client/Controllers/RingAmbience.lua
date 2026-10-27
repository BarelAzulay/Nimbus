-- RingAmbience (client, original audio): the Champion Ring's crowd and drums as positional loops.
--
-- Where: every Champion Ring pocket (workspace.BattlePockets.RingPocket_<i>, ArenaBuilder.BuildPocket: the ring on its
-- cloud with the cheering crowd on a stone bleacher behind the champion's side, the child model "Crowd"). Its crowd
-- gets SoundFx "CrowdCheer" at the middle of the bleacher; "DrumLoop" plays from the pocket's drummer when there is one
-- and, until a drummer exists, from the bleacher's back step at one end (the drummer's spot). Both are
-- SoundFx.Positional loops: RollOffMode InverseTapered, Config.Audio.Positional Min / Max studs (heard only near the
-- ring; pockets are 380 studs apart), slot volumes under the music (Config.Audio.Volume), the player's settings applied
-- (CrowdCheer: Sfx, DrumLoop: Music). A sound without an id (AudioIds) is simply not made.
--
-- THE DRUMMER HOOK (no drummer model exists in this branch): a model or part named "Drummer" anywhere in a ring pocket,
-- one with the attribute Drummer = true (the art-wave branch's crowd: ArenaBuilder Ring.spectator marks its drummer
-- "Spectator_drizzle" so), or ANY instance tagged "NC_RingDrummer" (CollectionService; e.g. a drummer at a plaza ring),
-- gets the DrumLoop; in a pocket it then replaces the fallback at the bleacher. Likewise "NC_RingCrowd" gives any
-- crowd / stand a CrowdCheer (a plaza ring with stands only has to tag them). Everything is client-side and never
-- replicated; a destroyed pocket takes its sounds with it.
--
-- LATE PARTS: a model replicates before its parts (a player joining while the pockets are still streaming in), so a
-- Scan can find a Crowd / drummer / tagged stand with no BasePart yet, or only some of them. Every BasePart that lands
-- in a pocket's Crowd or drummer (or in a tagged model) queues one deferred re-scan; the loop is made once the host has
-- a part and moved when its anchor part changes or its spot moves more than K.MOVE_EPS studs. A battle's VFX parts
-- elsewhere in the pocket do not trigger it.
--
--   RingAmbience.Init()                 watches workspace.BattlePockets and the two tags (once)
--   RingAmbience.Scan(pocket)           attaches the pocket's sounds now (idempotent; tests / a late child)
--   RingAmbience.Attach(host, name, offset) -> Sound | nil   a positional `name` loop at `host` (a Model, BasePart or
--                                       Attachment); offset = a world Vector3 from the host's centre
--   RingAmbience.Stats() -> { Sites, Crowd, Drums }
--
-- Plain Lua 5.1-compatible syntax only.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent

local RingAmbience = {}

local K = {
	FOLDER = "BattlePockets",
	POCKET_PREFIX = "RingPocket_",
	CROWD = "Crowd", -- ArenaBuilder's crowd stand in the pocket
	DRUMMER = "Drummer", -- the hook: a drummer model / part in the pocket
	CROWD_TAG = "NC_RingCrowd",
	DRUMMER_TAG = "NC_RingDrummer",
	ANCHOR = "RingAudio_", -- the Attachments made here
	CROWD_LIFT = 3, -- studs above the bleacher's centre (the puffs' heads)
	DRUM_SPOT = { X = 0.36, Y = 1.5, Z = 0.25 }, -- the fallback drummer spot: x / z share of the stand's size from its centre
	MOVE_EPS = 4, -- studs: a re-scan moves a playing loop only when its anchor part changes or its spot moves this far
}
RingAmbience.K = K

local St = {
	started = false,
	sites = {}, -- [pocket Model] = { crowd = Sound|nil, drum = Sound|nil, drumHost = Instance|nil, crowdE / drumE = placement }
	tagged = {}, -- [tagged Instance] = { sound, host, part, at }
	pending = {}, -- [pocket Model] = true while a deferred re-scan is queued
	conns = {},
	SF = nil, -- client/SoundFx (lazy); false = unavailable
}
RingAmbience._St = St

local function soundFx()
	if St.SF == nil then
		local module = Client:FindFirstChild("SoundFx")
		local ok, result = false, nil
		if module then
			ok, result = pcall(require, module)
		end
		St.SF = (ok and type(result) == "table") and result or false
	end
	return St.SF or nil
end

-- the biggest BasePart of a host (a stand's long step), the host itself when it is one
local function anchorPart(host)
	if host:IsA("BasePart") then
		return host
	end
	local best, bestV = nil, -1
	for _, d in ipairs(host:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > bestV then
				best, bestV = d, v
			end
		end
	end
	return best
end

-- the host's world centre and size
local function bounds(host)
	if host:IsA("BasePart") then
		return host.Position, host.Size
	end
	if host:IsA("Model") then
		local ok, cf, size = pcall(function()
			return host:GetBoundingBox()
		end)
		if ok and cf then
			return cf.Position, size
		end
	end
	local part = anchorPart(host)
	if part then
		return part.Position, part.Size
	end
	return nil, nil
end

-- where a loop for `host` goes: the anchor part and the world spot (nil while the host has no BasePart yet)
local function placement(host, offset)
	if host:IsA("Attachment") then
		return host, host.WorldPosition
	end
	local part = anchorPart(host)
	local centre = bounds(host)
	if not part or not centre then
		return nil, nil
	end
	return part, centre + (offset or Vector3.new(0, K.CROWD_LIFT, 0))
end

-- a positional `name` loop on `part` at the world spot `at` (an Attachment host takes it directly)
local function attachAt(host, part, at, name)
	local SF = soundFx()
	if not SF or type(SF.Positional) ~= "function" then
		return nil
	end
	local parent = host
	if not host:IsA("Attachment") then
		local att = Instance.new("Attachment")
		att.Name = K.ANCHOR .. name
		att.Position = part.CFrame:PointToObjectSpace(at)
		att.Parent = part
		parent = att
	end
	local ok, sound = pcall(SF.Positional, name, parent)
	if ok and typeof(sound) == "Instance" then
		return sound
	end
	if parent ~= host then
		parent:Destroy() -- (no id: no sound, no empty anchor left behind)
	end
	return nil
end

function RingAmbience.Attach(host, name, offset)
	if typeof(host) ~= "Instance" then
		return nil
	end
	local part, at = placement(host, offset)
	if not part then
		return nil
	end
	return attachAt(host, part, at, name)
end

local function drop(sound)
	if typeof(sound) == "Instance" then
		local att = sound.Parent
		sound:Destroy()
		if att and att:IsA("Attachment") and string.sub(att.Name, 1, #K.ANCHOR) == K.ANCHOR then
			att:Destroy()
		end
	end
end

local function alive(sound)
	return typeof(sound) == "Instance" and sound.Parent ~= nil
end

-- keeps entry (= { sound, host, part, at }) a `name` loop at `host`: kept while its anchor part and spot hold; moved
-- (dropped + made again) when the host changes or its parts arrive later (a model replicates before its parts: the
-- first part to land would otherwise be the anchor and the "centre" for good). A host with no part yet keeps what is on.
local function ensure(entry, host, name, offset)
	if not host then
		return entry.sound
	end
	local part, at = placement(host, offset)
	if not part then
		return alive(entry.sound) and entry.sound or nil
	end
	if alive(entry.sound) and entry.host == host and entry.part == part and entry.at and (at - entry.at).Magnitude <= K.MOVE_EPS then
		return entry.sound
	end
	drop(entry.sound)
	entry.sound = attachAt(host, part, at, name)
	if entry.sound then
		entry.host, entry.part, entry.at = host, part, at
	else
		entry.host, entry.part, entry.at = nil, nil, nil
	end
	return entry.sound
end

local function isDrummer(inst)
	return inst.Name == K.DRUMMER or inst:GetAttribute(K.DRUMMER) == true
end

-- the pocket's drummer: a descendant named Drummer, marked Drummer = true or tagged NC_RingDrummer
local function drummerOf(pocket)
	local named = pocket:FindFirstChild(K.DRUMMER, true)
	if named then
		return named
	end
	for _, d in ipairs(pocket:GetDescendants()) do
		if d:GetAttribute(K.DRUMMER) == true then
			return d
		end
	end
	for _, inst in ipairs(CollectionService:GetTagged(K.DRUMMER_TAG)) do
		if inst:IsDescendantOf(pocket) then
			return inst
		end
	end
	return nil
end

function RingAmbience.Scan(pocket)
	if typeof(pocket) ~= "Instance" or not pocket.Parent then
		return nil
	end
	local site = St.sites[pocket]
	if not site then
		site = { crowdE = {}, drumE = {} }
		St.sites[pocket] = site
	end
	local crowd = pocket:FindFirstChild(K.CROWD)
	site.crowd = ensure(site.crowdE, crowd, "CrowdCheer")
	-- the drums: at the drummer once it has a part, else at the bleacher's back step at one end (the drummer's spot)
	local drummer = drummerOf(pocket)
	if drummer and not placement(drummer, Vector3.new(0, 0, 0)) then
		drummer = nil
	end
	local host, offset = drummer, Vector3.new(0, 0, 0)
	if not drummer and crowd then
		local _, size = bounds(crowd)
		size = size or Vector3.new(30, 4, 8)
		host, offset = crowd, Vector3.new(size.X * K.DRUM_SPOT.X, K.DRUM_SPOT.Y, size.Z * K.DRUM_SPOT.Z)
	end
	site.drum = ensure(site.drumE, host, "DrumLoop", offset)
	site.drumHost = site.drum and site.drumE.host or nil
	return site
end

local function isPocket(inst)
	return inst:IsA("Model") and string.sub(inst.Name, 1, #K.POCKET_PREFIX) == K.POCKET_PREFIX
end

-- a part of the crowd or of a drummer (walks up to the pocket: a few levels), not a battle's VFX part in the pocket
local function inCrowdOrDrummer(d, pocket)
	local a = d.Parent
	while a and a ~= pocket do
		if a.Name == K.CROWD or isDrummer(a) then
			return true
		end
		a = a.Parent
	end
	return false
end

-- one deferred re-scan per pocket for a burst of arriving parts
local function rescanSoon(pocket)
	if St.pending[pocket] then
		return
	end
	St.pending[pocket] = true
	task.defer(function()
		St.pending[pocket] = nil
		if St.sites[pocket] then
			RingAmbience.Scan(pocket)
		end
	end)
end

local function watchPocket(pocket)
	if not isPocket(pocket) or St.sites[pocket] then
		return
	end
	RingAmbience.Scan(pocket)
	-- a crowd / drummer that replicates after the pocket itself, and their parts that replicate after them
	table.insert(St.conns, pocket.DescendantAdded:Connect(function(d)
		if d.Name == K.CROWD or isDrummer(d) then
			RingAmbience.Scan(pocket)
		elseif d:IsA("BasePart") and inCrowdOrDrummer(d, pocket) then
			rescanSoon(pocket)
		end
	end))
	table.insert(St.conns, pocket.AncestryChanged:Connect(function()
		if not pocket.Parent then
			St.sites[pocket] = nil
		end
	end))
end

local function watchFolder(folder)
	for _, child in ipairs(folder:GetChildren()) do
		watchPocket(child)
	end
	table.insert(St.conns, folder.ChildAdded:Connect(watchPocket))
end

local function onTagged(inst, name)
	-- a drummer inside a ring pocket is the pocket's (Scan moves the drums there)
	for pocket in pairs(St.sites) do
		if inst:IsDescendantOf(pocket) then
			RingAmbience.Scan(pocket)
			return
		end
	end
	local entry = St.tagged[inst]
	if not entry then
		entry = {}
		St.tagged[inst] = entry
		-- a tagged model's parts can land after it (and after its tag): place the loop again as they arrive
		if not inst:IsA("BasePart") and not inst:IsA("Attachment") then
			local pending = false
			table.insert(St.conns, inst.DescendantAdded:Connect(function(d)
				if d:IsA("BasePart") and not pending then
					pending = true
					task.defer(function()
						pending = false
						if St.tagged[inst] and inst.Parent then
							ensure(St.tagged[inst], inst, name)
						end
					end)
				end
			end))
		end
		table.insert(St.conns, inst.AncestryChanged:Connect(function()
			if not inst.Parent then
				St.tagged[inst] = nil
			end
		end))
	end
	ensure(entry, inst, name)
end

function RingAmbience.Init()
	if St.started then
		return
	end
	St.started = true
	local folder = Workspace:FindFirstChild(K.FOLDER)
	if folder then
		watchFolder(folder)
	end
	table.insert(St.conns, Workspace.ChildAdded:Connect(function(child)
		if child.Name == K.FOLDER and child:IsA("Folder") then
			watchFolder(child)
		end
	end))
	for tag, name in pairs({ [K.CROWD_TAG] = "CrowdCheer", [K.DRUMMER_TAG] = "DrumLoop" }) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			onTagged(inst, name)
		end
		table.insert(St.conns, CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			onTagged(inst, name)
		end))
	end
end

function RingAmbience.Stats()
	local sites, crowd, drums = 0, 0, 0
	for pocket, site in pairs(St.sites) do
		if pocket.Parent then
			sites = sites + 1
			if site.crowd and site.crowd.Parent then
				crowd = crowd + 1
			end
			if site.drum and site.drum.Parent then
				drums = drums + 1
			end
		end
	end
	for _, entry in pairs(St.tagged) do
		local s = entry.sound
		if typeof(s) == "Instance" and s.Parent then
			if s.Name == "Loop_DrumLoop" then
				drums = drums + 1
			else
				crowd = crowd + 1
			end
		end
	end
	return { Sites = sites, Crowd = crowd, Drums = drums }
end

return RingAmbience
