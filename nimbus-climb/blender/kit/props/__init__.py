"""World pieces that are new Python designs (recipe 4.1 "props"): gates, lobby props, home stations, arena and
dungeon pieces.  Wave 2 art engineers each own their files: props/gates*.py (art-gates), props/lobby*.py
(art-lobby), props/home*.py (art-home), props/arena*.py + props/dungeon*.py (art-arenadungeon).

A prop module registers builders by name; a catalog entry {"key": "gate_obby", "type": "prop", "prop": "gate",
"args": {...}} calls the builder with (entry, kit) and gets back an nvox.build.ModelSpec:

    from props import prop

    @prop("gate")
    def build_gate(entry, kit):
        m = kit.model(entry["key"], "gate", vs=0.5)
        g = kit.grid(K=2.0, half=40)                       # nvox.grid.VoxelGrid: ell / cap / cone / box / rbox /
        g.torus("Stone", (0, 6, 0), 5, 1, rot=...)          # torus / curve / paint / carve, design units * K
        kit.mesh(m, g, palette={"Stone": (0.9, 0.85, 0.8)}, recipes={"Trim": ["Primary"]}, group="Gate")
        return m

kit.mesh shades the grid like Voxel.Shade (nvox/shade.py: light tops, dark undersides, deep creases), then makes
one MeshPart per (key, shade) with the P4 builder colour key as its name (`Stone`, `StoneLight`, `Trim`...;
naming="group" numbers them after the group instead).  Colour: `recipes[key]` when the runtime tints the key per
instance (["Primary"] = the ML_Primary look attribute, ["Secondary"], ...), otherwise the constant palette colour.
Python-only (numpy); no bpy here.  The P4 portal and cloud of the prototype stay in nvox/props.py as references.
"""
import importlib
import os
import pkgutil

import numpy as np

REGISTRY = {}


def prop(name):
    def deco(fn):
        REGISTRY[name] = fn
        return fn
    return deco


def load_all():
    here = os.path.dirname(os.path.abspath(__file__))
    for info in sorted(pkgutil.iter_modules([here]), key=lambda i: i.name):
        importlib.import_module("props." + info.name)
    return REGISTRY


def cells_from_grid(grid, shade=None):
    """nvox.grid.VoxelGrid (+ optional shade array: 1 light, 0, -1 dark, -2 deep) -> {(x, y, z): key[_Light|_Dark]}"""
    out = {}
    idx = np.argwhere(grid.L != 0)
    for i, j, k in idx:
        key = grid.keys[int(grid.L[i, j, k])]
        if shade is not None:
            s = int(shade[i, j, k])
            if s > 0:
                key = key + "_Light"
            elif s < 0:
                key = key + "_Dark"
        out[(int(i) - grid.half, int(j) - grid.half, int(k) - grid.half)] = key
    return out


class PropKit:
    """helpers handed to every prop builder"""

    def model(self, key, kind="prop", vs=0.5, K=1.0):
        from nvox.build import ModelSpec
        m = ModelSpec(key, kind, vs, K)
        m.groups, m.attachments, m.meta = {}, {}, {}
        return m

    def grid(self, K=1.0, half=64, name="grid"):
        from nvox.grid import VoxelGrid
        return VoxelGrid(K, half=half, name=name)

    # the Look used to evaluate recipes into preview / palette colours (a P4 difficulty orange)
    look = {"Primary": (226 / 255, 150 / 255, 74 / 255), "Secondary": (1.0, 1.0, 1.0), "Eye": (0.2, 0.2, 0.3),
            "WingColor": (1.0, 1.0, 1.0)}

    def mesh(self, model, grid, palette=None, recipes=None, group="Body", naming="key", vs=None, offset=(0, 0, 0),
             rot=None, shade=True, shade_opts=None, flat=(), fixed_keys=(), materials=None, used=None):
        """palette: key -> (r, g, b) 0..1 (default: the recipes evaluated for self.look);
        recipes: key -> colour recipe (nvox/colors.py; ["Primary"] = tinted per instance by the ML_Primary look);
        materials: key -> (material, transparency)"""
        from nvox import colors as C
        from nvox.parts import Styles, add_cells
        from nvox.shade import shade as shade_grid
        if palette is None:
            palette = {k: C.eval_recipe(r, self.look) for k, r in (recipes or {}).items()}
        S = shade_grid(grid, shade_opts or {}, skip=set(flat)) if shade else None
        if S is not None:
            S = np.where(S < -1, -1, S)  # deep creases come from parts.deep_mask
        cells = cells_from_grid(grid, S)
        pal = {}
        for k, c in palette.items():
            mat, tr = (materials or {}).get(k, ("SmoothPlastic", 0.0))
            pal[k] = [c[0], c[1], c[2], mat, tr]
        st = Styles(pal, {k: {"recipe": r} for k, r in (recipes or {}).items()})
        return add_cells(model, cells, st, group=group, naming=naming, vs=vs or model.voxel_studs, rot=rot,
                         offset=offset, fixed_keys=fixed_keys, used=used if used is not None else {})
