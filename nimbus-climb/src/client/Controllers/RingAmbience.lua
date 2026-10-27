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
}
RingAmbience.K = K

local St = {
	started = false,
	sites = {}, -- [pocket Model] = { crowd = Sound|nil, drum = Sound|nil, drumHost = Instance|nil }
	tagged = {}, -- [tagged Instance] = Sound
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

function RingAmbience.Attach(host, name, offset)
	local SF = soundFx()
	if typeof(host) ~= "Instance" or not SF or type(SF.Positional) ~= "function" then
		return nil
	end
	local parent = nil
	if host:IsA("Attachment") then
		parent = host
	else
		local part = anchorPart(host)
		local centre = bounds(host)
		if not part or not centre then
			return nil
		end
		local att = Instance.new("Attachment")
		att.Name = K.ANCHOR .. name
		att.Position = part.CFrame:PointToObjectSpace(centre + (offset or Vector3.new(0, K.CROWD_LIFT, 0)))
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

local function drop(sound)
	if typeof(sound) == "Instance" then
		local att = sound.Parent
		sound:Destroy()
		if att and att:IsA("Attachment") and string.sub(att.Name, 1, #K.ANCHOR) == K.ANCHOR then
			att:Destroy()
		end
	end
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
		site = {}
		St.sites[pocket] = site
	end
	local crowd = pocket:FindFirstChild(K.CROWD)
	if crowd and not (site.crowd and site.crowd.Parent) then
		site.crowd = RingAmbience.Attach(crowd, "CrowdCheer")
	end
	local drummer = drummerOf(pocket)
	local host = drummer or crowd
	if host and (site.drumHost ~= host or not (site.drum and site.drum.Parent)) then
		drop(site.drum)
		local offset = Vector3.new(0, 0, 0) -- (at the drummer itself)
		if not drummer then
			local _, size = bounds(crowd)
			size = size or Vector3.new(30, 4, 8)
			offset = Vector3.new(size.X * K.DRUM_SPOT.X, K.DRUM_SPOT.Y, size.Z * K.DRUM_SPOT.Z)
		end
		site.drum = RingAmbience.Attach(host, "DrumLoop", offset)
		site.drumHost = site.drum and host or nil
	end
	return site
end

local function isPocket(inst)
	return inst:IsA("Model") and string.sub(inst.Name, 1, #K.POCKET_PREFIX) == K.POCKET_PREFIX
end

local function watchPocket(pocket)
	if not isPocket(pocket) or St.sites[pocket] then
		return
	end
	RingAmbience.Scan(pocket)
	-- a crowd / drummer that replicates after the pocket itself
	table.insert(St.conns, pocket.DescendantAdded:Connect(function(d)
		if d.Name == K.CROWD or isDrummer(d) then
			RingAmbience.Scan(pocket)
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
	if St.tagged[inst] and St.tagged[inst].Parent then
		return
	end
	-- a drummer inside a ring pocket is the pocket's (Scan moves the drums there)
	for pocket in pairs(St.sites) do
		if inst:IsDescendantOf(pocket) then
			RingAmbience.Scan(pocket)
			return
		end
	end
	St.tagged[inst] = RingAmbience.Attach(inst, name)
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
	for _, s in pairs(St.tagged) do
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
