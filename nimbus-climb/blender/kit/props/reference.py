"""Reference props (W1 kit): the prototype's Phase 4 portal (git 7aa0df2 buildPortal at 0.5-stud voxels) and the
cloud platform, built through the props API so wave 2 has a working example.  Keys use them only for tests and
previews (catalog key "prop_portal_reference"); the real gates are wave 2's props/gates*.py."""
import numpy as np

from nvox.props import PAD_SHIFT, cloud_platform, portal
from props import prop


@prop("p4_portal")
def p4_portal(entry, kit):
    K = float((entry.get("args") or {}).get("K", 2.0))
    gate, pad, lan, rec, transl, neon = portal(K)
    m = kit.model(entry["key"], "prop", vs=1.0 / K, K=K)
    mats = {k: ("Neon", 0.0) for k in neon}
    for k, t in transl.items():
        mats[k] = ("Neon" if k in neon else "SmoothPlastic", t)
    used = {}
    flat = set(neon) | {"Trim"}
    kit.mesh(m, gate, recipes=rec, group="Gate", vs=1.0 / gate.K, flat=flat, materials=mats, used=used)
    kit.mesh(m, pad, recipes=rec, group="Pad", vs=1.0 / pad.K, offset=PAD_SHIFT, flat=flat, materials=mats,
             shade_opts={k: dict(light=False, dark=False) for k in rec}, used=used)
    kit.mesh(m, lan, recipes=rec, group="Detail", vs=1.0 / lan.K, flat=flat, materials=mats, used=used)
    m.attachments = {"Zone": {"pos": [0, 3.3, 0], "rot": np.eye(3).tolist()}}
    m.meta = {"source": "LobbyBuilder buildPortal at 7aa0df2", "pivot": "pad centre; the gate 9.5 studs behind (+Z)"}
    return m


@prop("cloud_platform")
def cloud(entry, kit):
    K = float((entry.get("args") or {}).get("K", 1.5))
    g, rec, shade_rgb = cloud_platform(K)
    m = kit.model(entry["key"], "prop", vs=1.0 / K, K=K)
    kit.mesh(m, g, recipes=rec, group="Cloud", vs=1.0 / K, used={})
    m.meta = {"pivot": "top centre (the walking surface)"}
    return m
