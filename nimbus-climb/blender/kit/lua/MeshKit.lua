-- MeshKit (PROTOTYPE, not wired into the game): builds a model from a Blender-kit mesh template + its manifest,
-- or returns nil so the caller keeps today's Part builder (the fallback rule: every model whose asset id is not
-- set yet is still built from Parts, so the game and tools/smoke.py keep working).
--
--   MeshKit.Has(modelName) -> bool                     an asset id is set in Config.MeshAssets and the manifest exists
--   MeshKit.Template(modelName) -> Model | nil         server: InsertService:LoadAsset once, parked in
--                                                      ReplicatedStorage.MeshTemplates; client: waits for that copy
--   MeshKit.Assemble(modelName, look, opts) -> Model | nil
--        look = PetCatalog Look (Primary / Secondary / Eye / WingColor / Glow)   opts = { Scale = 1, Parent }
--   MeshKit.EvalColor(recipe, look) -> Color3          the kit's colour recipes (nvox/colors.py, same maths)
--
-- Placement: Roblox's importer recentres every MeshPart on its own bounds, so a part goes to
--   pivot * CFrame.new(part.center * scale)  with  Size = part.size * scale   (this also undoes any import scale).
-- Colours: MeshPart.Color = recipe colour; the dark / deep shades are vertex colours (multiplied in by Roblox);
-- "<Region>_Light" parts get Voxel.Lighten(colour); the "Fixed" part keeps Color = white (baked colours).
-- Plain Lua 5.1 syntax (the repo's syntax rule).

local MeshKit = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local manifests = ReplicatedStorage:WaitForChild("Shared"):FindFirstChild("MeshManifests")

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

local function lum(c)
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

-- Voxel.Lighten (the _Light shade; not a multiply, hence its own part)
local function shadeLight(c)
	return Color3.new(clamp(c.R + (1 - c.R) * 0.15, 0, 1), clamp(c.G + (0.98 - c.G) * 0.15, 0, 1), clamp(c.B + (0.9 - c.B) * 0.135, 0, 1))
end

function MeshKit.EvalColor(rec, look)
	local op = rec[1]
	if op == "Primary" or op == "Secondary" or op == "Eye" or op == "WingColor" then
		return look[op] or WHITE
	elseif op == "rgb" then
		return Color3.fromRGB(rec[2], rec[3], rec[4])
	elseif op == "mix" then
		return MeshKit.EvalColor(rec[2], look):Lerp(MeshKit.EvalColor(rec[3], look), rec[4])
	elseif op == "lighten" then
		return MeshKit.EvalColor(rec[2], look):Lerp(WHITE, rec[3])
	elseif op == "darken" then
		return MeshKit.EvalColor(rec[2], look):Lerp(BLACK, rec[3])
	elseif op == "shadeLight" then
		return shadeLight(MeshKit.EvalColor(rec[2], look))
	elseif op == "cuteIris" or op == "cutePupil" or op == "cuteLash" then
		local e = MeshKit.EvalColor(rec[2], look)
		local h, s, v = e:ToHSV()
		if op == "cuteIris" then
			if lum(e) < 0.4 then
				return Color3.fromHSV(h, clamp(s + 0.15, 0.4, 0.75), clamp(v + 0.4, 0.5, 0.66))
			end
			return e
		elseif op == "cutePupil" then
			return Color3.fromHSV(h, clamp(s * 0.8 + 0.25, 0.35, 0.8), rec[3] and 0.2 or 0.12)
		end
		return Color3.fromHSV(h, clamp(s * 0.6 + 0.15, 0.2, 0.6), 0.1)
	elseif op == "ifLum<" then
		local a = MeshKit.EvalColor(rec[2], look)
		return MeshKit.EvalColor((lum(a) < rec[3]) and rec[4] or rec[5], look)
	end
	return WHITE
end

local function manifestOf(name)
	local m = manifests and manifests:FindFirstChild(name)
	if not m then
		return nil
	end
	local ok, data = pcall(require, m)
	return ok and data or nil
end

local function assetId(name)
	local ids = Config.MeshAssets
	local id = type(ids) == "table" and ids[name] or nil
	if type(id) == "number" and id > 0 then
		return id
	end
	return nil
end

function MeshKit.Has(name)
	return assetId(name) ~= nil and manifestOf(name) ~= nil
end

local templates = {}

function MeshKit.Template(name)
	if templates[name] then
		return templates[name]
	end
	local id = assetId(name)
	if not id then
		return nil
	end
	local folder = ReplicatedStorage:FindFirstChild("MeshTemplates")
	if RunService:IsServer() then
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "MeshTemplates"
			folder.Parent = ReplicatedStorage
		end
		local existing = folder:FindFirstChild(name)
		if existing then
			templates[name] = existing
			return existing
		end
		local ok, asset = pcall(function()
			return game:GetService("InsertService"):LoadAsset(id)
		end)
		if not ok or not asset then
			warn("[MeshKit] could not load " .. name .. " (" .. tostring(id) .. "): " .. tostring(asset))
			return nil
		end
		local model = asset:FindFirstChildWhichIsA("Model") or asset
		model.Name = name
		model.Parent = folder
		templates[name] = model
		return model
	end
	local m = folder and folder:WaitForChild(name, 10)
	templates[name] = m
	return m
end

local function vec(t, k)
	return Vector3.new(t[1] * k, t[2] * k, t[3] * k)
end

local function cfOf(a, k)
	local p, r = a.pos, a.rot
	return CFrame.new(p[1] * k, p[2] * k, p[3] * k, r[1][1], r[1][2], r[1][3], r[2][1], r[2][2], r[2][3], r[3][1], r[3][2], r[3][3])
end

-- places the template's parts of one manifest under `model`, relative to `pivot` (a CFrame in model space)
local function placeParts(model, name, look, pivot, k, filter)
	local man, tpl = manifestOf(name), MeshKit.Template(name)
	if not man or not tpl then
		return false
	end
	for _, p in ipairs(man.Parts) do
		if not filter or filter(p) then
			local src = tpl:FindFirstChild(p.name, true)
			if src and src:IsA("MeshPart") then
				local part = src:Clone()
				part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
				part.Size = vec(p.size, k)
				part.CFrame = pivot * CFrame.new(vec(p.center, k))
				if p.color == "vertex" then
					part.Color = WHITE
				elseif type(p.color) == "table" then
					part.Color = MeshKit.EvalColor(p.color, look)
				end
				if p.material == "Neon" or (look.Glow and p.region == "Eye") then
					part.Material = Enum.Material.Neon
				end
				if p.transparency then
					part.Transparency = p.transparency
				end
				if p.group == "Lid" then
					part.Transparency = 1 -- blink lids: shown for a moment by the animator
				end
				part:SetAttribute("MK_Group", p.group)
				part.Parent = model
			end
		end
	end
	return true
end

-- A whole pet: species body (+ tail + lids), the wing style at WingL / WingR, the accessory at Hat.
-- Returns nil when the species mesh is not available (the caller then uses PetBuilder.Build).
function MeshKit.AssemblePet(look, opts)
	opts = opts or {}
	local k = opts.Scale or 1
	local species = "pet_" .. string.lower(tostring(look.Species))
	if not MeshKit.Has(species) then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Pet_" .. tostring(look.Id or species)
	local root = Instance.new("Part")
	root.Name = "Body"
	root.Transparency, root.Anchored, root.CanCollide, root.CanTouch, root.CanQuery = 1, true, false, false, false
	root.Size = Vector3.new(0.9, 1.1, 0.9) * k
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	placeParts(model, species, look, CFrame.new(), k)
	local man = manifestOf(species)
	local wing = "wing_" .. string.lower(tostring(look.WingStyle or "Feather"))
	if MeshKit.Has(wing) then
		for _, side in ipairs({ "WingL", "WingR" }) do
			placeParts(model, wing, look, cfOf(man.Attachments[side], k), k, function(p)
				return p.group == side
			end)
		end
	end
	if look.Accessory then
		local acc = "acc_" .. string.lower(look.Accessory)
		if MeshKit.Has(acc) and man.Attachments.Hat then
			placeParts(model, acc, look, cfOf(man.Attachments.Hat, k), k)
		end
	end
	return model
end

return MeshKit
