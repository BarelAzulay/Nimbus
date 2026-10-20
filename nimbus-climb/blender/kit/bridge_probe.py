"""Feasibility probe for a 'lupa bridge': run the REAL PetBuilder sculpt (src/shared/PetBuilder.lua, read-only) at a finer
resolution K inside the repo's own mock, take the blueprint boxes (pre-instantiate), rasterise them back to a voxel grid and
mesh them with the pipeline kit's greedy mesher.  Patches are applied IN MEMORY only (the repo is never written)."""
import sys, os, json, time
sys.dont_write_bytecode = True
REPO = "/home/user/roblox/nimbus-climb"
KIT = "/tmp/claude-0/-home-user/8bec7944-bcd6-57fb-b0e4-c3304e2d2b43/scratchpad/p6design/pipeline/kit"
sys.path.insert(0, os.path.join(REPO, "tools"))
sys.path.insert(0, KIT)
import numpy as np
import render_model as RM
from nvox.mesher import greedy_mesh

K = float(sys.argv[1]) if len(sys.argv) > 1 else 1.38
PET = sys.argv[2] if len(sys.argv) > 2 else "pebble_pup"
STAGE = int(sys.argv[3]) if len(sys.argv) > 3 else 0

orig_fs_node = RM.fs_node
def patched_fs_node(path, name=None):
    spec = orig_fs_node(path, name)
    if spec and spec.get("path", "").endswith("shared/PetBuilder.lua"):
        s = spec["source"]
        a = 'local k = (detail == "Low") and LOW_K or 1\n'
        assert a in s
        s = s.replace(a, 'local k = (detail == "Low") and LOW_K or (_G.MESHK or 1)\n', 1)
        b = 'k = ((detail == "Low") and 0.65 or 1.25) * (lean and 0.85 or 1)'
        assert b in s
        s = s.replace(b, 'k = ((detail == "Low") and 0.65 or 1.25 * (_G.MESHK or 1)) * (lean and 0.85 or 1)', 1)
        c = "local function budgetOf(look, detail)\n"
        s = s.replace(c, c + "\tif _G.MESHK then return { Total = 1e9, Cap = 1e9, Body = 1e9, Wing = 1e9, Wing2 = 1e9, Tail = 1e9, Halo = 1e9, Aura = 1e9 } end\n", 1)
        s = s.replace("\nreturn PetBuilder", "\nPetBuilder._Blueprint = function(def, detail) initConstants(); local look = readLook(def); look.Evolved = (def.Evolved == 2) and 2 or (def.Evolved == 1) or nil; return getBlueprint(look, detail or 'High') end\nreturn PetBuilder", 1)
        spec["source"] = s
    return spec
RM.fs_node = patched_fs_node

t0 = time.time()
W = RM.LuaWorld("server")
rt = W.rt
rt.globals().MESHK = K
fn = rt.eval("""function(petId, stage)
  _G.MESHK = MESHK
  local RS = game:GetService('ReplicatedStorage')
  local Shared = RS:FindFirstChild('Shared')
  local PB = require(Shared.PetBuilder)
  local Cat = require(Shared.PetCatalog)
  local def = nil
  for _, p in pairs(Cat.Pets or Cat) do if type(p)=='table' and p.Id == petId then def = p end end
  if not def and Cat.ById then def = Cat.ById[petId] end
  if not def and Cat.Get then def = Cat.Get(petId) end
  assert(def, 'pet not found '..tostring(petId))
  if stage > 0 then local d = {} for k,v in pairs(def) do d[k]=v end d.Evolved = stage def = d end
  local bp = PB._Blueprint(def, 'High')
  local out = { K = bp.K, Groups = {} }
  for gi, gr in ipairs(bp.Groups) do
    local g = { Name = gr.Name, Kind = gr.Kind, GK = gr.K, N = #gr.Boxes, Boxes = {} }
    for i, b in ipairs(gr.Boxes) do g.Boxes[i] = { b.X0, b.Y0, b.Z0, b.X1, b.Y1, b.Z1, b.Key } end
    out.Groups[gi] = g
  end
  return out
end""")
res = fn(PET, STAGE)
errs = W.script_errors()
def lua2py(v):
    if hasattr(v, "keys"):
        ks = list(v.keys())
        if ks and all(isinstance(k, int) for k in ks):
            return [lua2py(v[k]) for k in sorted(ks)]
        return {k: lua2py(v[k]) for k in ks}
    return v
r = lua2py(res)
report = {"pet": PET, "stage": STAGE, "K": K, "bpK": r["K"], "groups": [], "errors": errs[:3], "seconds": None}
total_tris = 0
for g in r["Groups"]:
    boxes = g.get("Boxes") or []
    if not boxes:
        continue
    arr = np.array([b[:6] for b in boxes], int)
    lo = arr[:, :3].min(0); hi = arr[:, 3:].max(0)
    shape = hi - lo + 3
    keys = {}
    F = np.zeros(shape, np.int32)
    for b in boxes:
        base = b[6].replace("_Light", "").replace("_Dark", "")
        kid = keys.setdefault(b[6], len(keys) + 1)
        x0, y0, z0 = np.array(b[:3]) - lo + 1
        x1, y1, z1 = np.array(b[3:6]) - lo + 1
        F[x0:x1 + 1, y0:y1 + 1, z0:z1 + 1] = kid
    q = greedy_mesh(F, F != 0, 0)
    tris = 2 * sum(len(v) for v in q.values())
    total_tris += tris
    report["groups"].append({"name": g["Name"], "kind": g.get("Kind"), "groupK": g.get("GK"), "luaBoxes": g["N"],
                             "voxels": int((F != 0).sum()), "extent_vox": (hi - lo + 1).tolist(), "keys": len(keys), "meshTris": tris})
report["totalMeshTris"] = total_tris
report["seconds"] = round(time.time() - t0, 1)
print(json.dumps(report, indent=1))
