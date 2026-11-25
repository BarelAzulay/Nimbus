# look review of kitb-chip-b: static sweep of guidechip:<state> at the sizes (read-only on the repo)
#   py -3.12 sweep.py <repo> <out dir> <sizes csv> <states csv> [touch]
import json, os, re, subprocess, sys, time, types
ROOT, OUT, SIZES, STATES = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
FORCE_TOUCH = (len(sys.argv) > 5 and sys.argv[5] == "touch")
FORCE_PC = (len(sys.argv) > 5 and sys.argv[5] == "notouch")
os.makedirs(OUT, exist_ok=True)
os.chdir(ROOT)
sys.path.insert(0, os.path.join(ROOT, "tools"))
import look_pins as LP
c = LP.Ctx(False)
RG, BH = c.RG, c.BH
args = types.SimpleNamespace(mark_small=None, scale=1.0, ss=2, bg="lobby", no_chrome=False, no_labels=False, boxes=False, crop=None)

def free_gb():
    out = subprocess.run(["powershell", "-NoProfile", "-Command", "(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory"],
                         capture_output=True, text=True).stdout.strip()
    return int(out) / 1048576.0

def wait_mem():
    for i in range(11):
        g = free_gb()
        if g >= 2.0:
            return g
        if i == 10:
            break
        print("LOW MEMORY %.2f GB, sleeping 120 s (%d/10)" % (g, i + 1), flush=True)
        time.sleep(120)
    print("ABORT: memory stayed under 2 GB", flush=True)
    sys.exit(3)

fh = open(os.path.join(OUT, "measure.jsonl"), "a", encoding="utf-8")
for size in SIZES.split(","):
    w, h = [int(v) for v in size.split("x")]
    touch = True if FORCE_TOUCH else (False if FORCE_PC else RG.is_touch(w, h, None))
    g = wait_mem()
    for scen in STATES.split(","):
        if scen == "guidechip:mousehint" and touch:
            continue
        t0 = time.time()
        row = {"scen": scen, "w": w, "h": h, "touch": touch}
        try:
            d = RG.dump_scenario(scen, w, h, touch, c.fonts)
        except SystemExit as exc:
            row["dump_error"] = str(exc)[:400]
            fh.write(json.dumps(row) + "\n"); fh.flush()
            print("ERR", scen, size, str(exc)[:200], flush=True)
            continue
        nodes = BH.nodes_of(d)
        inset = float(d.get("inset", 0) or 0)
        row["inset"] = inset
        row["errors"] = [str(e).splitlines()[0][:200] for e in (d.get("errors") or [])][:5]
        row["notes"] = [s for s in d.get("notes", []) if str(s).startswith("guidechip ")]
        chip = nodes.get("NimbusGuide.Chip")
        ink = BH.ink_of(chip, RG, c.fonts) if chip else []
        row["shown"] = bool(ink)
        if ink:
            ui = BH.union(ink)
            row["chip_face"] = LP.rect(chip)
            row["chip_ink"] = ui
            close = nodes.get("NimbusGuide.Chip.Close")
            if close and float(close["w"]) > 1:
                cr = LP.rect(close)
                row["close"] = cr
                cf = nodes.get("NimbusGuide.Chip.Close.Face")
                row["close_face"] = LP.rect(cf) if cf else None
                dots = LP.roblox_buttons(w, h, inset).get("Roblox '...'")
                row["x_off_dots"] = BH.gap(cr, dots) if dots else None
            texts = []
            for p, n in nodes.items():
                t = n.get("text")
                if p.startswith("NimbusGuide.Chip.") and isinstance(t, dict) and str(t.get("text", "")).strip() and float(n["w"]) > 1:
                    ok, how = c.whole(n)
                    texts.append({"path": p, "text": t["text"], "size": float(t.get("size", 0)), "whole": ok, "how": how, "rect": LP.rect(n)})
            row["texts"] = texts
            # nearest pieces: every other node (any depth) that paints, its own drawn rects (not its subtree), by gap to the chip's ink
            near = []
            for p, n in nodes.items():
                if p.startswith("NimbusGuide"):
                    continue
                if float(n["w"]) <= 1 or float(n["h"]) <= 1:
                    continue
                for r in BH.drawn_rects(n, RG, c.fonts):
                    if (r[2] - r[0]) > 0.9 * w and (r[3] - r[1]) > 0.6 * h:
                        continue
                    gp = min(BH.gap(a, r) for a in ink)
                    if gp < 12:
                        near.append((round(gp, 1), p, [round(v, 1) for v in r]))
            near.sort()
            row["near"] = near[:8]
            rb = []
            for name, r in LP.roblox_buttons(w, h, inset).items():
                rb.append((round(min(BH.gap(a, r) for a in ink), 1), name))
            if touch:
                for name, (cen, rad) in BH.rings(w, h).items():
                    rb.append((round(min(BH.ring_gap(r, cen, rad) for r in ink), 1), name + " ring"))
            row["roblox"] = sorted(rb)[:3]
            orders = {gg.get("name"): float(gg.get("displayOrder", 0) or 0) for gg in d.get("guis", [])}
            row["order"] = orders.get("NimbusGuide")
        # pieces by name for the record
        for key, pat in (("card", r"^NimbusHud\.\w+\.Vitals\.Body\.Card$"), ("tab", r"^NimbusHud\.\w+\.Vitals\.Body\.NameTab$"),
                         ("strip", r"^NimbusTutorial\..*QuestStrip$"), ("run", r"^MobileControls\.RunButton$"), ("dash", r"^MobileControls\.DashButton$")):
            n = next((n for p, n in nodes.items() if re.match(pat, p)), None)
            if n is not None and float(n["w"]) > 1:
                ik = BH.ink_of(n, RG, c.fonts)
                row[key] = BH.union(ik) if ik else LP.rect(n)
        try:
            img, _ = RG.render_one(d, c.fonts, args)
            name = "%s_%dx%d%s.png" % (scen.replace(":", "_"), w, h, "_touch" if FORCE_TOUCH else ("_pc" if FORCE_PC else ""))
            img.save(os.path.join(OUT, name))
            row["png"] = name
        except Exception as exc:
            row["render_error"] = str(exc)[:200]
        fh.write(json.dumps(row) + "\n"); fh.flush()
        print("%-28s %-10s %s %s %.1fs" % (scen, size, "shown" if row["shown"] else "HIDDEN", ("ink %s" % LP.fmt(row["chip_ink"])) if row["shown"] else (row["notes"][:1] or ""), time.time() - t0), flush=True)
fh.close()
