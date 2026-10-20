"""Boss keys through the bridge: boss_<id>_<joint> (one key per BossBuilder joint group, pivot = the joint's Pivot).
The palette is constant per boss (no Look), so every part's colour recipe is an ["rgb", ...] constant; names are the
BossBuilder palette keys (`Rock`, `RockLight`, `Glow`...), exactly what BattleController looks up today.
Wave 2 (art-creatures) owns catalog/creatures.json and tunes K / budgets there."""
import numpy as np

from bridge import BOSS_VOXEL
from nvox.build import ModelSpec
from nvox.parts import Styles, add_cells


def build_boss_joint(br, entry, k):
    bp = br.boss(entry["boss"], k)
    joint = entry["joint"]
    g = next((x for x in bp["groups"] if x["name"] == joint), None)
    if g is None:
        raise KeyError("%s: boss %s has no joint %s" % (entry["key"], entry["boss"], joint))
    vs = BOSS_VOXEL / k
    pivot = np.asarray(g["pivot"] or [0, 0, 0], float) * BOSS_VOXEL
    m = ModelSpec(entry["key"], "boss", vs, k)
    cells = {(int(x), int(y), int(z)): kk for (x, y, z), kk in zip(g["xyz"].tolist(), g["keys"])}
    add_cells(m, cells, Styles(bp["palette"]), group=joint, naming="key", vs=vs, offset=-pivot, used={})
    m.groups = {}
    m.attachments = {}
    m.meta = {"boss": entry["boss"], "joint": joint, "parent": g["parent"], "pivotStuds": [round(float(v), 4) for v in pivot],
              "K": k}
    return m
