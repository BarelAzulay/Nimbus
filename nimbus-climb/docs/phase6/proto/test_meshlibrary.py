#!/usr/bin/env python3
"""Run MeshLibrary.lua (the sketch) inside the repo's Roblox mock (tools/robloxmock.lua, read-only use) with fake
LoadAsset results, to check the load / normalise / fallback / client-preload / dress logic.

    python3 test_meshlibrary.py [/path/to/nimbus-climb]
"""
import os
import sys

import lupa.luajit21 as L

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = sys.argv[1] if len(sys.argv) > 1 else "/home/user/roblox/nimbus-climb"

LUA = r'''
local MOCK_PATH, LIB_SRC = ...
local results = {}
local function check(name, cond, detail)
	results[#results + 1] = (cond and "PASS " or "FAIL ") .. name .. ((cond or not detail) and "" or ("  " .. tostring(detail)))
end

local function fakeAsset(name, opts)
	-- what LoadAsset returns: a wrapper Model holding the uploaded Model (MeshParts named after the Blender objects)
	local wrapper = Instance.new("Model")
	local inner = Instance.new("Model")
	inner.Name = name
	inner.Parent = wrapper
	local body = Instance.new("MeshPart")
	body.Name = "Body"
	body.Size = Vector3.new(2, 2, 2)
	body.Anchored = false
	body.Color = Color3.fromRGB(163, 162, 165)
	body.Parent = inner
	local att = Instance.new("Attachment")
	att.Name = "Pivot_Att"
	att.Parent = body
	local wing = Instance.new("MeshPart")
	wing.Name = "Wing_L"
	wing.Size = Vector3.new(0.6, 0.6, 0.6)
	wing.Parent = inner
	if opts and opts.script then
		local s = Instance.new("Script")
		s.Parent = inner
	end
	return wrapper
end

-------------------------------------------------------------------- server
local Mock = dofile(MOCK_PATH)
Mock.Boot("server")
local RS = game:GetService("ReplicatedStorage")
local shared = Instance.new("Folder")
shared.Name = "Shared"
shared.Parent = RS
Mock.Mount(shared, { name = "MeshLibrary", class = "ModuleScript", source = LIB_SRC })
Mock.Mount(shared, { name = "MeshIds", class = "ModuleScript",
	source = "return { PebblePup = 111, Broken = 222, Flaky = 333, NotYet = 0 }" })

local calls = { [111] = 0, [222] = 0, [333] = 0 }
local AS = game:GetService("AssetService")
local IS = game:GetService("InsertService")
AS.LoadAssetAsync = function(self, id)
	calls[id] = (calls[id] or 0) + 1
	if id == 111 then
		task.wait(0.5)
		return fakeAsset("NC PebblePup", { script = true })
	elseif id == 222 then
		error("User is not authorized to access Asset.")
	elseif id == 333 then
		if calls[id] < 3 then
			error("HTTP 500 (Internal Server Error)")
		end
		return fakeAsset("NC Flaky")
	end
	error("unexpected id " .. tostring(id))
end
IS.LoadAsset = function(self, id)
	error("InsertService fallback also failed for " .. tostring(id))
end

local ML = require(shared.MeshLibrary)
local fallbackCalls = 0
local function partBuild()
	fallbackCalls = fallbackCalls + 1
	local m = Instance.new("Model")
	m.Name = "PartBuild"
	return m
end

-- before Start: nothing ready, everything falls back
local m0, kind0 = ML.Build("PebblePup", nil, partBuild)
check("before load: Build falls back to Parts", kind0 == "parts" and fallbackCalls == 1)

local readyFired = false
ML.OnReady("PebblePup", function() readyFired = true end)
ML.Start()
check("loading status while LoadAsset yields", ML.Status("PebblePup") == "loading", ML.Status("PebblePup"))
Mock.Advance(60)

local folder = RS:FindFirstChild("MeshLibrary")
local tpl = folder and folder:FindFirstChild("PebblePup")
check("template parented to ReplicatedStorage.MeshLibrary", tpl ~= nil and tpl:GetAttribute("ML_Status") == "ready")
check("OnReady fired", readyFired)
check("wrapper unwrapped, PrimaryPart = Body", tpl and tpl.PrimaryPart and tpl.PrimaryPart.Name == "Body")
local body = tpl and tpl:FindFirstChild("Body")
check("parts anchored (importer default is unanchored)", body and body.Anchored == true)
check("visual-only: CanCollide/CanQuery off", body and body.CanCollide == false and body.CanQuery == false)
check("MeshPart colour reset to white for vertex colours", body and body.Color == Color3.fromRGB(255, 255, 255))
local hasScript = false
for _, d in ipairs(tpl:GetDescendants()) do if d:IsA("Script") then hasScript = true end end
check("scripts stripped from the asset", not hasScript)
check("Broken: permanent error, no retries", ML.Status("Broken") == "failed" and calls[222] == 1, calls[222])
check("Broken: holder records error", folder:FindFirstChild("Broken") and folder.Broken:GetAttribute("ML_Status") == "failed")
check("Flaky: retried until success", ML.Status("Flaky") == "ready" and calls[333] == 3, calls[333])
check("NotYet (id 0) never loaded", ML.Status("NotYet") == "missing" and folder:FindFirstChild("NotYet") == nil)

local m1, kind1 = ML.Build("PebblePup", { Scale = 2, Tint = { Wing_L = Color3.fromRGB(255, 0, 0) } }, partBuild)
check("after load: Build returns the mesh clone", kind1 == "mesh" and m1 ~= tpl and m1:GetAttribute("ML_Mesh") == true)
check("Tint by part name", m1 and m1.Wing_L.Color == Color3.fromRGB(255, 0, 0))
local m2, kind2 = ML.Build("Broken", nil, partBuild)
check("failed key keeps the Part build", kind2 == "parts" and m2.Name == "PartBuild")

-- server tags a Part build for dressing
local target = Instance.new("Model")
target.Name = "LobbyArch"
local p = Instance.new("Part")
p.Name = "ArchStone"
p.Parent = target
target.Parent = workspace
ML.Tag(target, "PebblePup", { "Sign" })
check("Tag sets attribute + CollectionService tag", target:GetAttribute("ML_DressKey") == "PebblePup"
	and game:GetService("CollectionService"):HasTag(target, "ML_Dress"))

-------------------------------------------------------------------- client
local server = {}
for _, r in ipairs(results) do server[#server + 1] = r end
return server
'''

LUA_CLIENT = r'''
local MOCK_PATH, LIB_SRC = ...
local results = {}
local function check(name, cond, detail)
	results[#results + 1] = (cond and "PASS " or "FAIL ") .. name .. ((cond or not detail) and "" or ("  " .. tostring(detail)))
end
local Mock = dofile(MOCK_PATH)
Mock.Boot("client")
local RS = game:GetService("ReplicatedStorage")
local shared = Instance.new("Folder")
shared.Name = "Shared"
shared.Parent = RS
Mock.Mount(shared, { name = "MeshLibrary", class = "ModuleScript", source = LIB_SRC })
-- what the server replicated: two ready templates
local folder = Instance.new("Folder")
folder.Name = "MeshLibrary"
folder.Parent = RS
local function tpl(name)
	local m = Instance.new("Model")
	m.Name = name
	local b = Instance.new("MeshPart")
	b.Name = "Body"
	b.Parent = m
	m.PrimaryPart = b
	m:SetAttribute("ML_Status", "ready")
	m.Parent = folder
	return m
end
tpl("Good")
tpl("BadOnThisDevice")
-- ContentProvider.PreloadAsync is read-only in the mock: hand the module a game proxy whose ContentProvider
-- reports a failed fetch for one template (what a device that cannot download the mesh sees)
local realGame = game
local fakeCP = {
	PreloadAsync = function(self, list, cb)
		task.wait(0.2)
		local failed = list[1].Name == "BadOnThisDevice"
		if cb then cb("mesh-id", failed and Enum.AssetFetchStatus.Failure or Enum.AssetFetchStatus.Success) end
	end,
}
_G.game = setmetatable({
	GetService = function(self, name)
		if name == "ContentProvider" then return fakeCP end
		return realGame:GetService(name)
	end,
}, { __index = realGame })
-- a server-built Part model tagged for dressing (replicated)
local target = Instance.new("Model")
target.Name = "Arch"
local stone = Instance.new("Part")
stone.Name = "Stone"
stone.Parent = target
local sign = Instance.new("Part")
sign.Name = "Sign"
sign.Parent = target
target:SetAttribute("ML_DressKey", "Good")
target:SetAttribute("ML_Keep", "Sign")
target.Parent = workspace
game:GetService("CollectionService"):AddTag(target, "ML_Dress")
local target2 = target:Clone()
target2:SetAttribute("ML_DressKey", "BadOnThisDevice")
target2.Parent = workspace
game:GetService("CollectionService"):AddTag(target2, "ML_Dress")

local ML = require(shared.MeshLibrary)
ML.Start()
Mock.Advance(5)
check("client: good template usable", ML.IsReady("Good") and ML.Clone("Good") ~= nil)
check("client: failed fetch -> Clone nil (Part build used)", ML.Clone("BadOnThisDevice") == nil and ML.Status("BadOnThisDevice") == "failed")
check("client: dressed target shows mesh", target:FindFirstChild("ML_Mesh") ~= nil)
check("client: dressed parts hidden locally, kept parts visible", stone.Transparency == 1 and sign.Transparency == 0)
check("client: undressable target keeps its Parts", target2:FindFirstChild("ML_Mesh") == nil and target2.Stone.Transparency == 0, tostring(target2:FindFirstChild("ML_Mesh")) .. " " .. tostring(target2.Stone.Transparency) .. " key=" .. tostring(target2:GetAttribute("ML_DressKey")))
local m = ML.Clone("Good", { RenderFidelity = Enum.RenderFidelity.Performance })
check("client: clone with RenderFidelity option", m ~= nil)
return results
'''


def run(src, ctx_name):
    rt = L.LuaRuntime(unpack_returned_tuples=True)
    os.chdir(REPO)  # robloxmock.lua is read from the repo (read-only)
    lib = open(os.path.join(HERE, "MeshLibrary.lua"), encoding="utf-8").read()
    fn = rt.eval("function(src, ...) local f = assert(loadstring(src, '=" + ctx_name + "')); return f(...) end")
    res = fn(src, "tools/robloxmock.lua", lib)
    return [res[i] for i in range(1, len(res) + 1)]


def main():
    out = run(LUA, "server_test") + run(LUA_CLIENT, "client_test")
    for line in out:
        print(line)
    ok = sum(1 for l in out if l.startswith("PASS"))
    print("%d/%d passed" % (ok, len(out)))
    return 0 if ok == len(out) else 1


if __name__ == "__main__":
    sys.exit(main())
