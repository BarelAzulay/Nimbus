# look2: two sweep.py folders (HEAD and 6042440) -> which renders differ, pixel by pixel, and how the chip's row differs
#   py -3.12 cmp_sweeps.py <dir A (6042440)> <dir B (HEAD)>
import json, os, sys
from PIL import Image, ImageChops
A, B = sys.argv[1], sys.argv[2]


def rows(d):
    out = {}
    with open(os.path.join(d, "measure.jsonl"), encoding="utf-8") as fh:
        for l in fh:
            r = json.loads(l)
            out[(r["scen"], r["w"], r["h"])] = r
    return out


ra, rb = rows(A), rows(B)
same = {"landscape/PC": 0, "portrait": 0}
diff = {"landscape/PC": [], "portrait": []}
missing = []
for key in sorted(set(ra) | set(rb), key=lambda k: (k[1] > k[2], k[1], k[2], k[0])):
    a, b = ra.get(key), rb.get(key)
    if not a or not b or not a.get("png") or not b.get("png"):
        missing.append((key, bool(a and a.get("png")), bool(b and b.get("png"))))
        continue
    kind = "portrait" if key[2] > key[1] else "landscape/PC"
    ia, ib = Image.open(os.path.join(A, a["png"])).convert("RGB"), Image.open(os.path.join(B, b["png"])).convert("RGB")
    box = ImageChops.difference(ia, ib).getbbox() if ia.size == ib.size else (0, 0) + ia.size
    fields = [f for f in ("shown", "chip_ink", "close", "notes", "strip", "card", "run", "errors") if a.get(f) != b.get(f)]
    ta = [(t["text"], t["size"], t["whole"], t["rect"]) for t in a.get("texts", [])]
    tb = [(t["text"], t["size"], t["whole"], t["rect"]) for t in b.get("texts", [])]
    if ta != tb:
        fields.append("texts")
    if box is None and not fields:
        same[kind] += 1
    else:
        diff[kind].append("%s %dx%d: pixels differ in %s; fields %s; was shown=%s ink=%s -> now shown=%s ink=%s %s" % (
            key[0], key[1], key[2], box, fields, a.get("shown"), a.get("chip_ink"), b.get("shown"), b.get("chip_ink"), b.get("notes")))
for kind in ("landscape/PC", "portrait"):
    print("%s: %d identical (pixels and the chip's row), %d differ" % (kind, same[kind], len(diff[kind])))
    for d in diff[kind]:
        print("  DIFF " + d)
print("missing on one side: %d %s" % (len(missing), missing[:10]))
errs = [(k, r["errors"]) for k, r in rb.items() if r.get("errors")] + [(k, r.get("dump_error")) for k, r in rb.items() if r.get("dump_error")]
print("script / dump errors at B: %d %s" % (len(errs), errs[:5]))
