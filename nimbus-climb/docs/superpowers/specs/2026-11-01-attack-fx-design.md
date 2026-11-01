# Attack effects: bigger, more, and growing with evolution

Date: 2026-11-01. Status: approved by the owner on the pitch page
(https://claude.ai/artifact/YafvHfM1AQEBqJdbBsq9E5, source `.superpowers/attack-fx-pitch/page.html`) and in chat.
Builds on `docs/superpowers/specs/2026-10-23-pet-attack-vfx-design.md`, whose readability, budget and art rules still hold.

## Why

The owner's words: "all attacks make them look more visual in the game so players can really get impressed by the abilities and are, bigger
explotions, more effects, abilities apply for longer duration". On the page they added: "also gets bigger with evolution. and better abilities".

Today a Common pet's attack is a charge glow and a small burst; rings, flashes and ground marks wait for Rare and Epic. Evolving adds only 5-10%
to an effect's size, and an ability's shape never changes.

## Owner's decisions

| Item | Decision |
|---|---|
| Size | **A. Moderate.** By rarity, Common x1.3 up to Secret x1.6, in even steps: Common 1.3, Uncommon 1.35, Rare 1.4, Epic 1.45, Legendary 1.5, Mythic 1.55, Secret 1.6. |
| Evolution, looks | **Bigger with each evolution**, clearly: x1.15 at the first, x1.3 at the second, on top of rarity (`StageBonus` and `SizeCap` move with it: 1.6 x 1.3 = about 2.08). |
| Evolution, abilities | **Bigger reach and look.** The real hit areas of an evolved pet's abilities grow: x1.15 at the first evolution, x1.3 at the second. This is a real gameplay change, on the server. |
| More effects | **A. Impact package for everyone.** Every hit from every pet at every rarity gets a shockwave ring, a light flash, sparks and a ground mark, plus a quick camera kick on your own attacks. Higher rarities get them stronger. |
| Lasting longer | **A. Visuals only.** Ability timers in `BattleCatalog` stay exactly as they are. Scorch marks, embers and fading zones hang around up to 2 s longer after the effect ends. |

## What "reach" covers

Special `Radius` (Blast, Storm, Freeze), Beam `Length` and `Width`, Pounce `Range`; element attack `Length`, `Radius`, `Width`. Cone `Angle` stays. Durations,
damage scales and stun times stay. The telegraph and effect drawn for a pet must match its real area exactly. The Pets detail shows it in plain words (for
example "Reach +15%"). NPC and enemy pets follow the same rule by their own evolution stage.

## Balance

The reach change must not break the 2026-10-31 balance. `tools/sim_battle.lua` keeps all its targets, with no target loosened to pass; if a target breaks, tune
BattleCatalog numbers and report it. Add a pin: an evolved pet's area is larger by exactly the table, a test pins that every timer in `BattleCatalog.Specials`,
`ElementAttacks` and `Buffs` is unchanged, and duels stay fair.

## Claude's calls (report them)

- **Readability first.** Earlier rounds cut back a 14-stud ring, white flashes and thick sprays because they hid the target, and the code comments record it.
  Particle counts stay near today's: the extra comes from rings, lights and ground marks, which cost little. Bursts leave the target visible. Gemini warned that clouds past x1.6 hide the target and the owner's evolution note goes past that for
  evolved rare pets, so evolved size goes into rings, ground marks and shape, not denser clouds. Light caps (brightness and range) only move if a real Studio check shows the pets aren't washed white, so leave them as they are in code and list them for that check.
- **A lingering visual must not look active.** A fading zone or scorch mark must clearly read as over (dimmer, no pulse), so nobody dodges a ghost or stands in a real one thinking it's safe.
- **Rarity stays visible.** A Secret stays clearly more impressive than a Common. Other players' effects keep `OthersDensity`.
- **Camera kick:** own attacks only, short (about 0.15 s), scaled by kind (a Special more than a basic hit), respecting the Shake setting, never moving the aim or target. Basic hits land often, so their kick must be small or rate limited so a fight doesn't become constant shaking.
- **Budgets:** `MAX_LIVE` and step-down still apply. Graphics Low stays simple: no new work on Low beyond what's cheap.

## Non-goals

- Longer ability timers.
- Evolved forms. The owner then added that evolving must grant a better ability: "stormfang's special is now pounce, evolved makes it shadow storm wolfs charge at the enemy, last evolve makes them even cooler with lightning". That is being pitched and gets its own spec, built on top of this one. So read a unit's stage and reach through one function each, so forms can plug in later, and don't build forms here.
- New textures or meshes: use the existing `fx_*` textures and `vfx_*` meshes. Any new visible model or texture would be made in Blender and uploaded by the keyed session.
- Raids: built separately on branch `raid-boss`. Stay out of its fight service. It adds a lethal telegraph and may touch `BattleSim`'s boss code, so keep your `BattleSim` change small and easy to merge.

## Must keep

- Server authoritative: reach is computed on the server from the stored evolution stage.
- The `p7vfx_*` and `client_p7vfx_*` scenarios keep passing, rewritten only where they pin the old sizes or ladder, and said so.
- Phone first: 844x390, under the existing budgets.
- Only real Studio can judge the look, so the final report lists what the owner must check: size, target visibility, flash strength, camera kick and phone frame rate.
