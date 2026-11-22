"""keys look r4: tools/battle_hud_no_overlap.py measures what the player sees (a part's ink), not its layout box.

Offline (no game boot): hand-made dump nodes, the cases the look found by eye and the box rule passed:
  - the enemy row's gold target bracket: an Outer 2 px UIStroke on a child 3.2 px wider than the row; a run chip whose
    box clears the row but sits under the bracket is closer than RUNCHIP_GAP;
  - the hearts' 16 px pixel art in a 14.4 px Lives box: the cells past the box count; the element badge's Outer frame
    under it touches it, so the fighter card's parts are under PART_GAP apart;
  - a clipping ancestor cuts a child's ink; an invisible-background node with no stroke paints nothing;
  - a helper's Lv tag above its cell: the cell's ink starts at the tag;
  - two parts 2 px apart fail MIN_GAP, 4 px apart pass.
Run: py -3.12 tools/test_battle_hud_no_overlap.py"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import battle_hud_no_overlap as T  # noqa: E402


def node(path, x, y, w, h, bgT=0.0, strokes=None, children=None, clip=False, **extra):
    n = {"path": path, "name": path.rsplit(".", 1)[-1], "x": x, "y": y, "w": w, "h": h, "bgT": bgT, "clip": clip,
         "children": children or []}
    if strokes:
        n["strokes"] = [{"thickness": t, "position": pos, "mode": "Border", "t": 0, "color": [0, 0, 0]} for t, pos in strokes]
    n.update(extra)
    return n


FAILS = []


def expect(ok, what):
    print(("  ok    " if ok else "  FAIL  ") + what)
    if not ok:
        FAILS.append(what)


def close(a, b, eps=0.01):
    return all(abs(p - q) <= eps for p, q in zip(a, b))


def main():
    B = "NimbusBattle.Root."
    # 1. the target bracket: the row 168 x 32 at (462.4, 67.6); its Bracket child 174.4 x 38.4 at (459.2, 64.4), Outer 2
    row = node(B + "Enemies.Row1", 462.4, 67.6, 168, 32, strokes=[(2, "Outer")], children=[
        node(B + "Enemies.Row1.Bracket", 459.2, 64.4, 174.4, 38.4, bgT=1, strokes=[(2, "Outer")])])
    chip = node("NimbusDungeonRun.RunChip", 545, 103.6, 82, 44.8)
    dump = {"guis": [{"nodes": [row, chip]}]}
    nodes = T.nodes_of(dump)
    ink = T.union(T.ink_of(nodes[B + "Enemies.Row1"], None, None))
    expect(close(ink, (457.2, 62.4, 635.6, 104.8)), "the row's ink is its bracket's Outer ring: %s" % (ink,))
    groups, inks = T.collect(nodes, None, None)
    expect(close(groups["ENEMIES"][0][1], ink), "collect() gives the row its ink, not its box")
    d, _, _ = T.ink_gap(inks[B + "Enemies.Row1"], inks["NimbusDungeonRun.RunChip"], ink, groups["RUNCHIP"][0][1], T.RUNCHIP_GAP)
    expect(d < 0, "the chip under the bracket lies on it (%.1f px), though the boxes are 4 px apart" % d)

    # 2. the hearts: a 14.4 px Lives box, a heart label 14.4 px, its pixel cells 16 px tall from 0.8 px above the label
    cells = [node(B + "Team.Fighter.Body.Lives.Heart1.Icon.C%d" % i, 156.8 + 2 * i, 113.2 + 2 * i, 2, 16 - 2 * i) for i in range(3)]
    lives = node(B + "Team.Fighter.Body.Lives", 156.8, 114.0, 46.4, 14.4, bgT=1, children=[
        node(B + "Team.Fighter.Body.Lives.Heart1", 156.8, 114.0, 14.4, 14.4, bgT=1, children=[
            node(B + "Team.Fighter.Body.Lives.Heart1.Icon", 156.8, 113.2, 18, 16, bgT=1, children=cells)])])
    badge = node(B + "Team.Fighter.Body.Element", 150, 131.2, 17.6, 17.6, strokes=[(2, "Outer")])
    li = T.ink_of(lives, None, None)
    lu = T.union(li)
    expect(abs(lu[3] - 129.2) < 0.01, "the hearts' ink ends at the cells' foot, 129.2 (the box at 128.4): %s" % (lu,))
    bi = T.ink_of(badge, None, None)
    d, _, _ = T.ink_gap(li, bi, lu, T.union(bi), T.PART_GAP)
    expect(d < T.PART_GAP, "the heart's tip on the badge's frame reads %.1f px, under PART_GAP" % d)

    # 3. a clipping ancestor cuts its child; a clear node with no stroke paints nothing
    clipped = node("X.Clip", 0, 0, 50, 50, bgT=1, clip=True, children=[node("X.Clip.Wide", -20, 10, 100, 10)])
    nodes = T.nodes_of({"guis": [{"nodes": [clipped]}]})
    ci = T.ink_of(nodes["X.Clip"], None, None)
    expect(len(ci) == 1 and close(ci[0], (0, 10, 50, 20)), "a clipped child's ink stops at its clip: %s" % (ci,))

    # 4. a helper's Lv tag 4 px above its cell: the cell's ink starts at the tag's ring
    cell = node(B + "Team.Helpers.Helper1", 9.6, 160, 144, 68.8, bgT=1, children=[
        node(B + "Team.Helpers.Helper1.Level", 54.4, 156, 51.2, 19.2, strokes=[(2, "Outer")])])
    hu = T.union(T.ink_of(cell, None, None))
    expect(abs(hu[1] - 154.0) < 0.01, "the cell's ink starts at its Lv tag's ring, 154 (the cell at 160): %s" % (hu,))

    # 5. MIN_GAP: two keys 2 px apart fail it, 4 px apart pass
    a, b, c = (0, 0, 50, 50), (52, 0, 100, 50), (54, 0, 100, 50)
    expect(T.ink_gap([a], [b], a, b, T.MIN_GAP)[0] < T.MIN_GAP, "2 px of air is under MIN_GAP")
    expect(T.ink_gap([a], [c], a, c, T.MIN_GAP)[0] >= T.MIN_GAP, "4 px of air is MIN_GAP")
    print("test_battle_hud_no_overlap: %d failed" % len(FAILS))
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
