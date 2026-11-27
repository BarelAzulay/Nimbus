# Combined release: kit-b look + release step 1 (Store off, save safety) + 104 meshes + 7 images + world signs

**Base:** `main` (`ac552d0`). **Head:** `release-combined`. Final head and place file:
`BUILD: release-combined d33c7b91 (place file built on d33c7b91's sources), 1186 scripts, verify_place OK`.
**Do not merge before the owner says yes in chat.** This PR replaces `step1-pr.md`: step 1 never went to main on its
own, it ships inside this release.

Owner test: `docs/release/combined-test-checklist.md`, in the test experience "Nimbus test 2.0" (universe
10779238980, place 74125226332082). Rollback steps: `docs/release/step1-rollback.md`.

## What is in it

- **Release step 1** (`origin/qw-step1-gate-b`, merged in `0c3bfa17`): quick-wins with its save session lock and the
  Store / Daily / Trove / Pity save fields, the leaderboards, the Shop window, daily gifts, the Sky Trove, titles.
  The Robux Store is **off** (`Config.Store.Enabled = false`): the Shop shows the Eggs tab only, no Robux item or
  prompt. Token spins stay open on every account while the Store is off. A pass is granted only after
  `UserOwnsGamePassAsync` confirms it. A v1-only player keeps the v1 Tokens on main after a crash.
- **kit-b UI polish**: every window, HUD and world sign on one pixel signboard kit (U2 - U9), the Pitch 2 items
  (vitals card C, boss bar A, result card B, tutorial dock B, Daily B, Elements A, Index badge B, stone world tags
  04 B, phone keys "Three buttons", melee "Bounce in", day fade C, "Show the way" guide 13 A, evolved eyes A "Trim"),
  and the look fixes of the kit-b gates.
- **Guide chip B** (the top-bar plank chip, owner's pick B, `3aff40ec`) and the **chip blink** fix (the portrait chip
  comes back only after its spot is clear for 1.0 s, `25c90b59`; reduced, not closed: backlog item 29).
- **Tutorial backlog fixes** (`f6f77bcb`): backlog items 6 (in part), 7, 8, 10 and 16.
- **Match HUD slim bar** (owner's pick A, branch `kitb-matchhud`, at `4113d7e8` on 2026-11-27: `c2492531`,
  `02a3462d`, `72f4de55`, `594ff6a4`, `b32607f6`, `4113d7e8`): on short landscape phones the vitals become one slim
  row in a match and its countdown, the match card puts its checkpoints in the clock row, the pad's vitals step aside.
  The branch also carries kit-b backlog 9 (ring and trial fights on portrait phones, `cad9687d`) and 21 / 31 (the
  NPC dialog on a phone's screen, `1b26ff8b`), and the look fix round for N1 - N3 (final branch head `29d8a699`).
  Merged into kit-b in `d2ee8ca8` (look PASS, 0 new majors; kit-b `949373ff` whole suite 45380 / 0, mesh 1267 / 0),
  then into `release-combined` in `568e185c`.
- **The Store-off pin on kit-b's restyled Shop** (`fec10e06`).
- **104 uploaded meshes** (merged in `0110e4d5`): 98 evolved pet meshes with the smaller eyes (`c7deca0b`, every
  `evo1_*` / `evo2_*` key, High and Low) and the 6 Sky Trove meshes (`598df3bb`, `prop_trove_body` / `_lid` / `_sign`
  and their `_low` twins).
- **7 uploaded images** (I1 - I7, uploaded from Studio with the owner's OK, ids recorded in `79363a36`): I1 icon set B
  (`Config.IconSheet.Id = 94977768447984`), I2 workshop machines A (`Config.MachineSheet.Id = 76428055171576`), I3 the
  L1 voxel logo (`nimbus_logo`), I4 - I7 the four boss heads (`boss_head_*`, the owner kept them as they are). The
  smoke checks moved to the uploaded state, with the drawn fallbacks still tested (`7290ae69`, `e399d6eb`).
- **Battle tag fixes** (branch `fix-battle-tags`, merged in `276a1afc`): the damage total sits on the champion tag /
  card / bar it belongs to and never covers the pet's Lv card (the owner's bug screenshot, `7cb68120`, new
  `tools/smoke_battle_tags.lua`); the egg stage holds a resize during a roll (`91f7b067`).
- **Kit-b world signs** (branch `kitb-world-signs`, merged in `f1315eee`): about 31 world signs that were still on the
  old rounded navy look (home nameplate and avatar disc, gate number, showcase tag, pad / farm / bowl / machine signs,
  FREE HOME sign, closed garden bed, home portal tag, lobby gardens, machines, trove, boards, arch, shop sign, the
  lobby leaderboard, the egg shelf's rarity strip, the obby gate countdown face and portal billboard, arena
  boards and gate signs, course hints, boards and START / FINISH, the DOWNED marker, the champion tag) now use
  `WorldTag.Block` / `Tint` / `Text`, the stone square block with its coloured lip (the owner's "home gui's havent
  changed" report). Two stand-ins stay on the backlog list (`tools/fixtures/world_round_backlog.txt`: GateTag,
  SignGui).
- **Release-check fix** (`d33c7b91`): with the boss heads uploaded, a phone's raid card showed the head too and its
  pills wrapped in a half-width column (the 360 x 640 card reached MOVE); on a phone the pills now go under the head
  at full width where that makes the card shorter.

## What is NOT in it

| Item | State | What players see without it |
|---|---|---|
| The Robux Store, products, passes | off; no product or pass id is set | nothing is sold for Robux, as on main today |

Known and left open (the owner's call): the kit-b look backlog
(`docs/superpowers/backlog/2026-11-24-kitb-look-backlog.md`), among them items 1 - 5 (vitals card and guide chip on
small phones; the slim bar covers the match, pad and countdown on short landscape phones), 11 (fourth machine card cut at 960 x 540 and
1024 x 768), 29 (chip blink in a slower band), 36 (tutorial card on the smallest portrait phones), 37 - 39 (tutorial
card text minors). From step 1: AFK play-time gifts can be farmed (bounded), and the rollback cost of four small
fields and a Week Wisp off the team while main is live (`step1-pr.md`, "Rollback cost").

## Evidence on an earlier head

Run on `a28a7aff` (before the mesh merge and before the slim bar). They are **not** evidence for the final head; the
"Before merge" list runs them again.

| Check | Result on `a28a7aff` |
|---|---|
| `py -3.12 tools/save_roundtrip.py` (main's real code against this branch, one fake DataStore) | 356 passed, 0 failed |
| Lock lists | 772 passed, 0 failed |
| Store switch lists | 938 passed, 0 failed |

The place file committed in `a28a7aff` was stale after `0110e4d5`; it was rebuilt once, on the final head, in
`bb92b05f`.

## Before merge

- [x] Whole suite on the final head: `tools/smoke.py --quick` and the mesh suite `tools/smoke.py --mesh`. On
      `b4f01bbe` (2026-11-27, `d33c7b91`'s code plus docs): whole 46170 passed / 1 failed (6598 s), mesh 1267 / 0,
      save_roundtrip 356 / 0 (main `ac552d0574e0`), `test_render_sheets` ok. The one failure is
      `travel_shows_way` ("after the drawn-machine page ShopEggs' last-built page is the Shop's real Eggs page again"),
      which fails only in the whole run and passes alone (`--only travel_shows_way`: 454 / 0): test order, not the
      game. Earlier heads: `bb92b05f` whole 45661 / 0; `f7516428` whole 46167 / 4 (three fixed in `d33c7b91`, the
      fourth the same `travel_shows_way` order case).
- [x] Place file rebuilt on the final head (`rojo build default.project.json -o play/NimbusClimb.rbxlx`, Rojo 7.7.1)
      and `py -3.12 tools/verify_place.py` OK on it: `d33c7b91`, all 1186 scripts match, no extra scripts.
- [x] `py -3.12 tools/save_roundtrip.py` against `origin/main`: 356 passed, 0 failed (main `ac552d0574e0`) on
      `f7516428`; `d33c7b91` changes no save code. `tools/test_render_sheets.py` ok.
- [ ] The owner's checklist (`docs/release/combined-test-checklist.md`) done on that place file.
- [ ] The owner says yes in chat.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01ACtM8s7SJ44rug3Djr4JS9
