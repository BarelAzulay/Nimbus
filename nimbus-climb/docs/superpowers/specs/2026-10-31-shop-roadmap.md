# Robux shop and paid content (roadmap, saved for a later build)

Date: 2026-10-31. Status: **not started, not approved item by item.** The owner asked for this to be remembered and built later,
when the gameplay is finished. Before building, pitch it as an artifact page with visual options (the standing design pitch rule).
Prices and contents below are starting proposals; nothing here has been measured or tested on players.

## The owner's words

"i want the shop gui to look something like this to make it look really good and making players to want to really buy from the
shop for robux, it needs to look colorful and shiny, we need a game pass, starter packs, pro packs etc, (later on when the gameplay
is finished we'll also make house skins/special home design progress, pets aquipments, pet mount paid pass etc, More xp paid
options, more tokens/coins paid options etc, Pets stats boosts etc. remember all those after brainstorming the best options also
with gemini and save it for later build."

## The look: the three references (images were in the chat and are not saved here)

1. "Store": category tabs on the left with big icons (Pets, Passes, Wins, Boosts), a tall rainbow-gradient VIP hero card with a
   crown, Buy button and price, and a grid of square cards with saturated gradients and big glossy icons. A bold purple title banner
   and a big red X.
2. "Gamepasses": big picture banner cards with bold words and prices (+20% EXP with a crossed-out sale price, 1.5X Damage, x2
   Coins, Loot Boost, VIP), then four gem packs with growing art (one gem to a chest pile), a funny line each, and Save / Best Deal
   ribbons.
3. "Shop": stacked wide cards on a thick black-outlined frame: Server Luck (a shared buff), Starter Pack and Pro Pack, each with
   three item tiles (two pets, a money bag) and a bright green Robux button.

What they share, and what to take: saturated gradients, thick dark outlines, big glossy art that fills the card, chunky white
outlined words, one loud green buy button, and a clear hero item. Shine in Roblox: a slowly rotating `UIGradient` on hero cards, a
sheen sweep across a card now and then, a small pulse on the buy button; respect the Graphics setting and keep it cheap.

## Layout (phone 844x390 first; Claude and Gemini agree)

Vertical tabs on the left: **Packs, Passes, Boosts, Currency**, and **Home** once skins exist. One scroller of wide stacked cards, a
tall VIP hero first. The buy button is always visible on a card and at least 44 px high. The window follows the new Pets window's
sizing: nearly full screen on a phone, under Roblox's topbar.

## What to sell first

Proposal, Robux prices to be checked against similar games at pitch time:

| Item | Type | Price (R$) | Notes |
|---|---|---|---|
| Starter Pack | one purchase per account | 99 | A level 5 pet, 1,000 Cash, a 1 hour x2 XP potion (Gemini). Enough to feel it, not enough to skip the game |
| Pro Pack | one purchase per account | 799 | An exclusive pet, 5,000 Tokens, plus a PvE-only perk to be settled at the pitch |
| VIP | game pass | 399 | Daily reward, chat tag and colour, name plate |
| x2 Cash | game pass | 399 | |
| x2 Pet XP | game pass | 450 | The honest power path: speeds levels, which decide fights since the 2026-10-31 balance |
| Pet Mount | game pass | 250 | Ride your pet at home and in the lobby. Needs rideable rigs per species: a big art job |
| Auto-roll | game pass | 150 | Gemini said "Auto-Hatch"; this game has roulettes, not eggs |
| Gems | 4 developer products | to set | Exist already as `Config.Gems.Products` (100 / 550 / 1,200 / 6,500), all with `Id = 0`: not created yet |
| Tokens and Cash packs | developer products | to set | Same growing-pile cards as the gems |
| XP potions | developer products | to set | Timed x2 XP, stacking in time only |

Later, when the gameplay is finished: house skins and special home designs, pet equipment, a pet mount pass line, Server Luck-style
shared buffs. House skins, equipment and mounts are visible models, so they are hand-made in Blender and uploaded by the keyed
session. Icons and banners use Blender renders of the game's own pets. Any sound is original (Suno / ElevenLabs).

## Care needed: where Gemini and Claude pushed back

1. **Pet stat boosts: both advise against raw stats.** The owner listed them. After the 2026-10-31 balance, level decides fights, so
   selling stats undoes that and makes duels pay-to-win. If kept: timed, capped, PvE only (Dungeon, raids), off in duels and off in
   Ring records. x2 XP gives most of the same feeling. **The owner decides at the pitch.**
2. **Fake "Limited Time": both advise against it.** Reference 3 uses it. The audience is young, a timer that resets is deception, and
   it risks moderation (check Roblox's current rules at build time). Real limits are fine: one-per-account packs, event items with a
   real end date, and sale prices that were really charged before.
3. **Selling at the wall: Claude's caution.** Gemini wants the Starter Pack aimed at the Ring round 3 wall. Offer it in the shop and
   mention it calmly, but no popup on the loss screen: that screen's job is showing the pet got stronger, and a free retry must always
   be enough to progress.
4. **+1 Pet Equip: Claude rejects Gemini's pick.** The team is exactly the 3 pets following you (`Config.Pets.MaxEquipped` = 3, team =
   followers, decided 2026-10-31), so a 4th slot breaks the team model. Extra A / B / C team slots could sell instead.
5. **Fast Walk: Claude's caution.** Gemini's 99 R$ pass must not apply in obby matches or battles. The lobby already has free
   stamina, so it may not be worth selling.
6. **Paid random items.** The Secret roulette already has a policy check (`GemService.SecretRouletteState`) and shown odds. Any new paid
   random item follows the same path; check Roblox's rules at build time.
7. **Build order: Gemini disagrees with the owner.** It says to build money hooks alongside the core loop, not after. Claude's middle:
   the owner's order stands, but the plan keeps the hooks cheap to add (multipliers in one place, pack grants through the server), and
   the shop's look can be pitched as soon as the battle work settles.

## Rules for the build

- Server authoritative: `ProcessReceipt` idempotent per purchase, grants survive a failed save, never trust the client. Passes checked on
  the server with `UserOwnsGamePassAsync` and cached per session.
- Creating passes and products on Roblox, and uploads, are the owner's or the keyed session's step. Not from the PCs.
- Re-check the balance sims with every paid multiplier: a paid team must still fit the sim targets' idea of fair.

## Suggested order

1. The shop window and look, with gems (the products already exist in code).
2. Starter Pack and Pro Pack.
3. Passes: VIP, x2 Cash, x2 XP, Auto-roll.
4. Tokens, Cash and XP potions.
5. Home skins and designs, then pet equipment, then the mount (art first, each in Blender).
6. Whatever the owner decides on stat boosts.
