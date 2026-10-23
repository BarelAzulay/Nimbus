-- smoke_p7vfx.lua: the pet attack VFX (docs/superpowers/plans/2026-10-23-pet-attack-vfx.md). Loaded by tools/smoke.py
-- in the server world.
--   p7vfx_ids   (pure) the uploaded ids: every key of blender/vfx/textures.json is in shared/TextureIds as a positive
--               integer (an Image id, checked in Studio when uploaded; the file is written by tools/upload_assets.py
--               --textures), TextureIds has no key besides those and the gate vortex layers (blender/textures/
--               textures.json), and every vfx_* key of blender/catalog/vfx.json is in shared/MeshIds (the 22 cores).
-- Deterministic: keys are read from the committed manifests in file order. Plain Lua 5.1 syntax.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local S = {}
local fmt = string.format

-- "rb": Windows text mode stops at byte 0x1A
local function readFile(rel)
	for _, prefix in ipairs({ "", "../", "nimbus-climb/" }) do
		local fh = io.open(prefix .. rel, "rb")
		if fh then
			local src = fh:read("*a")
			fh:close()
			return src
		end
	end
	return nil
end

-- every "key": "<name>" of a manifest whose name starts with `prefix`, in file order
local function manifestKeys(rel, prefix)
	local src = readFile(rel)
	if not src then
		return nil
	end
	local keys = {}
	for k in string.gmatch(src, '"key"%s*:%s*"([%w_]+)"') do
		if string.sub(k, 1, #prefix) == prefix then
			keys[#keys + 1] = k
		end
	end
	return keys
end

local function sharedModule(name)
	local ok, inst = pcall(Mock.GetPath, ROOTS.shared .. "/" .. name)
	if not ok or not inst then
		return nil
	end
	local ok2, mod = pcall(require, inst)
	return ok2 and type(mod) == "table" and mod or nil
end

S.p7vfx_ids = guarded("p7vfx_ids", function()
	local texKeys = manifestKeys("blender/vfx/textures.json", "")
	local coreKeys = manifestKeys("blender/catalog/vfx.json", "vfx_")
	local TextureIds = sharedModule("TextureIds")
	local MeshIds = sharedModule("MeshIds")
	if not T.check(texKeys ~= nil and #texKeys > 0, "p7vfx ids: blender/vfx/textures.json lists texture keys")
		or not T.check(coreKeys ~= nil and #coreKeys > 0, "p7vfx ids: blender/catalog/vfx.json lists vfx_* keys")
		or not T.check(TextureIds ~= nil and MeshIds ~= nil, "p7vfx ids: shared/TextureIds and shared/MeshIds load as tables") then
		return
	end

	-- textures: every manifest key, as a positive integer Image id (check.mjs texture-ids: numbers only)
	local known, okTex = {}, 0
	for _, key in ipairs(texKeys) do
		known[key] = true
		local v = TextureIds[key]
		if v == nil then
			T.fail("p7vfx ids: TextureIds missing " .. key)
		elseif type(v) ~= "number" or v <= 0 or v ~= math.floor(v) then
			T.fail("p7vfx ids: TextureIds." .. key .. " is not a positive integer id", tostring(v))
		else
			okTex = okTex + 1
		end
	end
	T.check(okTex == #texKeys, fmt("p7vfx ids: every texture key has a positive integer Image id (%d / %d)", okTex, #texKeys))

	-- no extra keys: TextureIds = the VFX keys + (once uploaded) the gate vortex layers of the uploader's other Image
	-- index blender/textures/textures.json ({ "keys": { key: { ... } } }); nothing else
	local vortexSrc = readFile("blender/textures/textures.json") or ""
	local vortex = {}
	for k in string.gmatch(vortexSrc, '"([%w_]+)"%s*:%s*{') do
		if k ~= "keys" then
			vortex[k] = true
		end
	end
	local extra = {}
	for k in pairs(TextureIds) do
		if not known[k] and not vortex[k] then
			extra[#extra + 1] = tostring(k)
		end
	end
	table.sort(extra)
	T.check(#extra == 0, "p7vfx ids: TextureIds has no key outside blender/vfx/textures.json + the vortex layers", table.concat(extra, ","))

	-- cores: every vfx_* key of the catalog is uploaded
	local okCore = 0
	for _, key in ipairs(coreKeys) do
		if MeshIds[key] == nil then
			T.fail("p7vfx ids: MeshIds missing " .. key)
		else
			okCore = okCore + 1
		end
	end
	T.check(okCore == #coreKeys, fmt("p7vfx ids: every vfx_* core key is in MeshIds (%d / %d)", okCore, #coreKeys))
end)

return S
