# damage total covers the pet level card (fixed 2026-11-27)

**Report:** screenshot `damage total covers the pet level card.png` (a dungeon fight: the running totals "75" and "59"
sit on the pets' cards; only the "L" of "Lv 4" shows). Owner's Studio: DamageTotal StudsOffset 3.178, HpBar 2.878.

**Cause:** `BattleController` `Fx.Total` placed the total's billboard 0.3 studs over the unit card (`NumberHeight - 0.6`
= height / 2 + 1.2 vs the card's height / 2 + 0.9). Both are fixed-px billboards: at 20 studs and 1080p 0.3 studs is
about 12 px, while the 34 px chip and the 43 px card need 38 px between their centres, so the chip covered the card (and
the further away, the worse).

**Fix** (`src/client/Controllers/BattleController.lua`):
- `Fx.PlateOf(u)`: the billboard the total stands on (the ring champion's tag, else the PetCard "HpBar", else the Phase 3
  bar; none for a raid boss, whose bar is the HUD's top card).
- `Fx.Total`: the total's billboard on the plate's own anchor, its chip `K.TOTAL_GAP` (4) px over the plate's top edge
  (EVOLVE! pill included) through `SizeOffset`, so it holds at every distance and screen size. A raid boss keeps its
  total over its head as before.
- `Fx.Pop`: a hit's pop keeps its place beside the total (0.6 studs over the total's anchor, lifted the same px), so
  Pitch 2 item 04 B's look (stone chip, red lip, the pops beside it) is unchanged.

**Evidence:** `tools/smoke_battle_tags.lua` `battle_tags_clear` (failed 19 checks before the fix): through a perspective
camera at 10 .. 130 studs, at 1920x1080, 2560x1440 and 844x390, the total's chip never overlaps the plate of my Lv 4
unit, a unit showing EVOLVE!, a dungeon mini-boss, the ring champion's tag or the Phase 3 bar, and the pop starts beside
the total, clear of the plate. `damage_numbers_short`, `damage_pops_apart`, the `client_p3battle_*` and card scenarios
pass. Not yet looked at in Studio (the owner was using it).
