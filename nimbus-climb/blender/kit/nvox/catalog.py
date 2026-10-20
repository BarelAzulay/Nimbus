"""Reads the pet Look tables straight from src/shared/PetCatalog.lua (no Lua runtime needed inside Blender).

PetCatalog's lineup entries look like
    { Id = "pebble_pup", Name = "Pebble Pup", Rarity = "Common", ..., Look = { Species = "Dog", Primary = C(190, 154, 114),
      Secondary = C(...), Eye = C(...), Glow = false, Accessory = "Leaf", WingStyle = "Feather", WingColor = C(...) }, ... }
parse_catalog() -> {id: {"Id", "Name", "Rarity", "Look": {Species, Primary (0..1 floats), ..., Glow, WingStyle, ...}}}
A tools/ check (smoke) should compare this against the real module under lupa when the kit moves into the repo.
"""
import re

from .colors import rgb

_ENTRY = re.compile(r'Id\s*=\s*"([^"]+)"\s*,\s*Name\s*=\s*"([^"]*)"\s*,\s*Rarity\s*=\s*"([^"]*)"')
_LOOK = re.compile(r'Look\s*=\s*\{(.*?)\}\s*,', re.S)
_FIELD = re.compile(r'(\w+)\s*=\s*(C\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*\)|"[^"]*"|true|false|-?\d+(?:\.\d+)?)')


def _value(v):
    if v.startswith("C("):
        r, g, b = [int(x) for x in re.findall(r"\d+", v)]
        return rgb(r, g, b)
    if v.startswith('"'):
        return v[1:-1]
    if v in ("true", "false"):
        return v == "true"
    return float(v)


def parse_catalog(path):
    text = open(path, encoding="utf-8").read()
    out = {}
    for m in _ENTRY.finditer(text):
        pid, name, rarity = m.groups()
        lm = _LOOK.search(text, m.end())
        if not lm or lm.start() - m.end() > 600:
            continue
        look = {k: _value(v) for k, v in _FIELD.findall(lm.group(1))}
        look["Id"] = pid
        out[pid] = {"Id": pid, "Name": name, "Rarity": rarity, "Look": look}
    return out


def sample_look(species):
    """PetBuilder's neutral sample look (dump_model.lua species:<X>) for species meshes without a catalog pet."""
    return {"Id": "sample_" + species.lower(), "Species": species, "Primary": rgb(232, 206, 180),
            "Secondary": rgb(250, 238, 222), "Eye": rgb(44, 38, 66), "WingColor": rgb(240, 232, 246),
            "WingStyle": "Feather", "Glow": False}
