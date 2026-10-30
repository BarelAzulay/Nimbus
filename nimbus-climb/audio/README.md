# Nimbus original audio (final files, 2026-10-27)

Picked by the player on https://claude.ai/artifact/9QjqQB5ht3433DQ2GwPHqC (decisions collection).
All original: music by Suno (paid plan) except the drum loop; SFX and the drum loop by ElevenLabs (Creator plan).

| Slot | File | Source take | Notes |
|---|---|---|---|
| MusicLobby | MusicLobby.ogg | Suno "Sky Pilgrim" take 2 | seamless loop, 85.1 s, 30 bars @ 84.7 BPM |
| MusicBattle | MusicBattle.ogg | Suno "Elemental Clash" take 2 | seamless loop, 79.4 s, 45 bars @ 136 BPM |
| MusicDungeon | MusicDungeon.ogg | Suno "Hollow Spire" take 1 | seamless loop, 93.7 s, 38 bars @ 97.5 BPM |
| DrumLoop | DrumLoop.ogg | ElevenLabs Music "Ring Drummer" take 1 | seamless loop, 26.0 s, 13 bars @ 120 BPM |
| Click | Click.ogg | ElevenLabs SFX Click_1 | trimmed, -18 dBFS active RMS |
| Confirm | Confirm.ogg | ElevenLabs SFX Confirm_B4 (brass singing bowl) | mostly below 250 Hz: check loudness on phone speakers |
| Error | Error.ogg | ElevenLabs SFX Error_3 | |
| Reward | Reward.ogg | ElevenLabs SFX Reward_2, softened (lowpass 4.2 kHz, shelf -3 dB) | player asked "softer" |
| Whoosh | Whoosh.ogg | ElevenLabs SFX Whoosh_1 | |
| Inhale | Inhale.ogg | ElevenLabs SFX Inhale_4 | game ramps PlaybackSpeed 0.75 -> 1.35 |
| Shatter | Shatter.ogg | ElevenLabs SFX Shatter_2 | player asked "more digital" (prompt has a digital glitch crackle) |
| CrowdCheer | CrowdCheer.ogg | ElevenLabs SFX CrowdCheer_3 (loop mode, 10 s) | loops |

Loop details: loops.json (start/end in the source take, bars, BPM).

## In the game

`audio.json` lists every key with its file, the file's `sha256`, its slot (`Music` / `Sfx` / `Ambient`) and `looped`.
The owner's keyed upload session runs `python3 tools/upload_assets.py --audio` (dry run), then
`python3 tools/upload_assets.py --upload --audio`, which writes `src/shared/AudioIds.lua` and `audio/upload_state.json`
(commit both together; docs/phase6/OWNER_UPLOAD.md section 6b). `Config.Audio` reads the ids; a key with no id is
silent. Replacing a file: put the new file here and its new `sha256` in `audio.json`; it uploads as a NEW asset
(audio cannot be updated in place).

Where each plays: MusicLobby / MusicDungeon / MusicBattle (client/SoundFx layers: a dungeon run plays MusicDungeon,
my fights MusicBattle, a dungeon's boss room too), Click / Confirm / Whoosh (menus), Error (a new "bad" toast, a refused
action: client/Controllers/NotifyController), Reward (a won fight, a won Champion Ring round, a
dungeon room's loot, the dungeon chest, the tutorial's finale), Inhale / Shatter (a Special's charge and a broken charge, BattleController),
CrowdCheer / DrumLoop (positional loops at the Champion Ring pocket's crowd stand, client/Controllers/RingAmbience;
the drums move to a drummer once one exists: a part named `Drummer`, a crowd model with the attribute `Drummer = true`
(the art-wave branch's drummer) or anything tagged `NC_RingDrummer`; a plaza stand tagged `NC_RingCrowd` gets its own
crowd loop). Slot volumes: `Config.Audio.Volume`. A won dungeon room plays Reward once, with its Loot (not at the
room's End too).

## Wave 2 sound effects (final files, 2026-10-30)

Picked by the player on the wave-2 pages: round 1 https://claude.ai/artifact/2CbUHV6TNPpiHbdrK4ruNM and round 2
https://claude.ai/artifact/QDH2QZcP7duUofuUjaB8Mx (round 2 overrides round 1 for a slot in both). All original,
ElevenLabs sound effects (Creator plan). 29 one-shots, slot `Sfx`, not looped. Skipped by the player (no file):
FountainLoop, TutorialChapter. The NPC voices are their own section below (round 3, wordless).

Each file is rebuilt from the RAW ElevenLabs take with the exact chain of its preview
(`.superpowers/audio-pitch/wave2/final/w2_final.py`: 35 Hz high-pass, trim, -18 dBFS active RMS with peaks <= -1 dBFS,
plus the take's own layering / cut), not re-encoded from the mp3 preview; Ogg Vorbis q7, 44.1 kHz, mono when the take
has no real stereo (side/mid RMS under 0.15). Checked against the approved preview with a libvorbis decode
(`w2_verify.py`): same length to the sample, peaks within 1.4 dB of the mp3 peaks (lossy peaks move; all <= -0.9 dBFS), active RMS 0.2-0.8 dB above the
mp3 (the mp3 lost some top end), correlation >= 0.95 (Crit 0.96: its 11 kHz sparkle is what the mp3 cut most).

Wired on branch `audio-wire` (section "Wiring" below; plan: `.superpowers/audio-pitch/wave2/wiring-plan.md`). A key
whose id is not uploaded yet stays silent.

| Key | File | Source take (page id) | Length | Ch | Where it will play |
|---|---|---|---|---|---|
| HitWater | HitWater.ogg | HitWater_2 | 0.46 s | mono | a Water pet's hit lands |
| HitFlame | HitFlame.ogg | HitFlame_R2_N2: FlameWoosh_3 (EQ) + FlameIgnite_2 -6 dB + FlameCrackle_1 tail -15 dB | 0.46 s | st | a Flame pet's hit lands |
| HitFrost | HitFrost.ogg | HitFrost_2 | 0.33 s | st | a Frost pet's hit lands |
| HitNature | HitNature.ogg | HitNature_1 | 0.23 s | st | a Nature pet's hit lands |
| HitEarth | HitEarth.ogg | HitEarth_4 | 0.35 s | st | an Earth pet's hit lands |
| HitStorm | HitStorm.ogg | HitStorm_2 | 0.37 s | st | a Storm pet's hit lands |
| HitCelestial | HitCelestial.ogg | HitCelestial_2 | 0.47 s | st | a Celestial pet's hit lands |
| HitShadow | HitShadow.ogg | HitShadow_4 | 0.40 s | st | a Shadow pet's hit lands |
| Crit | Crit.ogg | Crit_4 | 0.68 s | st | a critical hit (over the element hit) |
| KO | KO.ogg | KO_2 (round 1) | 1.20 s | st | a pet is knocked out (rotation 1 of 4) |
| KO2 | KO2.ogg | KO_V1 = KOv_7 | 1.20 s | mono | KO rotation 2 of 4 |
| KO3 | KO3.ogg | KO_V2 = KOv_10 | 1.20 s | st | KO rotation 3 of 4 |
| KO4 | KO4.ogg | KO_V3 = KOv_2 | 1.20 s | st | KO rotation 4 of 4 |
| Dash | Dash.ogg | Dash_9 | 0.30 s | st | a pet's Dash |
| Parry | Parry.ogg | Parry_1 | 0.53 s | st | a timed Dash parries (wave 6) |
| PortalEnter | PortalEnter.ogg | PortalEnter_R2_3 = PortalEnter_3 | 1.10 s | st | my home portal swirls open / a gate travel starts |
| PortalArrive | PortalArrive.ogg | PortalArrive_R2_4 = PortalArrive_7 | 0.70 s | st | I arrive through a portal |
| StationBuild | StationBuild.ogg | StationBuild_R2_2 = StationBuild_2 | 0.11 s | mono | a station of my home pops in |
| HouseTier | HouseTier.ogg | HouseTier_R2_1 = HouseTier_1 | 1.09 s | st | my house reaches a new tier |
| DialogOpen | DialogOpen.ogg | DialogOpen_3 | 0.33 s | st | an NPC dialog opens |
| DialogBlip | DialogBlip.ogg | DialogBlip_3 (one click cut from the take) | 0.03 s | mono | the dialog typewriter (every few letters) |
| DialogNext | DialogNext.ogg | DialogNext_1 | 0.23 s | st | Next in an NPC dialog |
| TutorialStep | TutorialStep.ogg | TutorialStep_3 | 0.91 s | st | a tutorial step is done |
| SpinStart | SpinStart.ogg | SpinStart_R2_1 = SpinStart_1 | 0.33 s | st | the roulette strip starts |
| SpinTick | SpinTick.ogg | SpinTick_2 (one click cut from the take) | 0.04 s | st | each cell passing the roulette pointer |
| SpinLand | SpinLand.ogg | SpinLand_2 | 0.60 s | st | the strip lands on the pet |
| RevealCommon | RevealCommon.ogg | RevealCommon_R2_1 = RevealCommon_1 harp raised one octave (C4) | 0.65 s | mono | reveal card, Common / Uncommon |
| RevealRare | RevealRare.ogg | RevealRare_M: RevealLegendary_1 notes 1-2 + light room tail | 1.22 s | st | reveal card, Rare / Epic |
| RevealLegendary | RevealLegendary.ogg | RevealLegendary_1 | 1.89 s | st | reveal card, Legendary / Mythic / Secret |

## NPC voices (wave 2 round 3, final files, 2026-10-30)

Picked by the player on https://claude.ai/artifact/Wc5ZP5u4RbLLEAwfwJnZXs: one voice per NPC (the player asked for no
words, only vocal sounds like "mhm", "AhA!", "Woo!"). ElevenLabs voices designed for Nimbus (saved as "Nimbus <NPC> A/B"),
multilingual v2 speech. 18 one-shots (greet / hmm / pleased per NPC), slot `Sfx`, not looped. The optional animal takes
(Corgi "Woof!") were not picked. Built from the RAW take with the preview's chain (`.superpowers/audio-pitch/wave2/round3/
scripts/r3_final.py`: 35 Hz high-pass, trim, -18 dBFS active RMS, peaks <= -1 dBFS); correlation with the preview >= 0.9999,
same length and peak level. Wired with the rest of wave 2 (section "Wiring", the NPC voice rule).

| Key | File | Source take (page id = take) | Length | Ch | Where it will play |
|---|---|---|---|---|---|
| NpcCaptainPenguinGreet | NpcCaptainPenguinGreet.ogg | NpcVoice_CaptainPenguin_B_greet = CaptainPenguin_B_greet_3 | 0.69 s | mono | Captain Penguin (voice B): their dialog opens |
| NpcCaptainPenguinHmm | NpcCaptainPenguinHmm.ogg | NpcVoice_CaptainPenguin_B_hmm = CaptainPenguin_B_hmm_1 | 0.81 s | mono | Captain Penguin (voice B): a thinking line |
| NpcCaptainPenguinPleased | NpcCaptainPenguinPleased.ogg | NpcVoice_CaptainPenguin_B_pleased = CaptainPenguin_B_pleased_3 | 0.55 s | mono | Captain Penguin (voice B): a happy line / a done task |
| NpcCoachCorgiGreet | NpcCoachCorgiGreet.ogg | NpcVoice_CoachCorgi_B_greet = CoachCorgi_B_greet_3 | 0.48 s | mono | Coach Corgi (voice B): their dialog opens |
| NpcCoachCorgiHmm | NpcCoachCorgiHmm.ogg | NpcVoice_CoachCorgi_B_hmm = CoachCorgi_B_hmm_1 | 0.82 s | mono | Coach Corgi (voice B): a thinking line |
| NpcCoachCorgiPleased | NpcCoachCorgiPleased.ogg | NpcVoice_CoachCorgi_B_pleased = CoachCorgi_B_pleased_1 | 1.13 s | mono | Coach Corgi (voice B): a happy line / a done task |
| NpcGrannyOwlGreet | NpcGrannyOwlGreet.ogg | NpcVoice_GrannyOwl_B_greet = GrannyOwl_B_greet_3 | 0.83 s | mono | Granny Owl (voice B): their dialog opens |
| NpcGrannyOwlHmm | NpcGrannyOwlHmm.ogg | NpcVoice_GrannyOwl_B_hmm = GrannyOwl_B_hmm_3 | 0.63 s | mono | Granny Owl (voice B): a thinking line |
| NpcGrannyOwlPleased | NpcGrannyOwlPleased.ogg | NpcVoice_GrannyOwl_B_pleased = GrannyOwl_B_pleased_2 | 0.96 s | mono | Granny Owl (voice B): a happy line / a done task |
| NpcMayorPandaGreet | NpcMayorPandaGreet.ogg | NpcVoice_MayorPanda_A_greet = MayorPanda_A_greet_10 | 1.01 s | mono | Mayor Panda (voice A): their dialog opens |
| NpcMayorPandaHmm | NpcMayorPandaHmm.ogg | NpcVoice_MayorPanda_A_hmm = MayorPanda_A_hmm_7 | 0.55 s | mono | Mayor Panda (voice A): a thinking line |
| NpcMayorPandaPleased | NpcMayorPandaPleased.ogg | NpcVoice_MayorPanda_A_pleased = MayorPanda_A_pleased_11 | 0.44 s | mono | Mayor Panda (voice A): a happy line / a done task |
| NpcProfessorAxolotlGreet | NpcProfessorAxolotlGreet.ogg | NpcVoice_ProfessorAxolotl_B_greet = ProfessorAxolotl_B_greet_1 | 0.51 s | mono | Professor Axolotl (voice B): their dialog opens |
| NpcProfessorAxolotlHmm | NpcProfessorAxolotlHmm.ogg | NpcVoice_ProfessorAxolotl_B_hmm = ProfessorAxolotl_B_hmm_1 | 0.50 s | mono | Professor Axolotl (voice B): a thinking line |
| NpcProfessorAxolotlPleased | NpcProfessorAxolotlPleased.ogg | NpcVoice_ProfessorAxolotl_B_pleased = ProfessorAxolotl_B_pleased_4 | 0.92 s | mono | Professor Axolotl (voice B): a happy line / a done task |
| NpcSparkyFoxGreet | NpcSparkyFoxGreet.ogg | NpcVoice_SparkyFox_A_greet = SparkyFox_A_greet_3 | 0.54 s | mono | Sparky Fox (voice A): their dialog opens |
| NpcSparkyFoxHmm | NpcSparkyFoxHmm.ogg | NpcVoice_SparkyFox_A_hmm = SparkyFox_A_hmm_2 | 0.62 s | mono | Sparky Fox (voice A): a thinking line |
| NpcSparkyFoxPleased | NpcSparkyFoxPleased.ogg | NpcVoice_SparkyFox_A_pleased = SparkyFox_A_pleased_1 | 1.04 s | mono | Sparky Fox (voice A): a happy line / a done task |

Upload: one `--audio` run creates the 29 wave-2 effects + these 18 voices = 47 (the 12 above are unchanged and skipped).
Roblox counts audio uploads per account per month (100 with ID verification, which the owner has): 12 used this month,
this batch adds 47 (59 of 100). If the 29 were already uploaded, the run creates only the 18 voices.

## Wiring (branch audio-wire, 2026-10-30)

Every wave-2 key and NPC voice is in `Config.Audio.Keys.Sfx` under its own name (the voices are built from 6 NPCs x
Greet / Hmm / Pleased) and in `SoundFx.NAMES`. All sounds are client-side one-shots through `client/SoundFx.lua`
(`SoundFx.Play(name, { Scale, Gap })`, `SoundFx.PlayVariant`); nothing plays on the server. A key with no id is silent:
no Sound, no warning, no error.

### Where each key plays

| Key | When | Call site |
|---|---|---|
| Hit\<Element\> (8) | a hit lands; the key is the ATTACKER's element. A burn / zone tick, a miss, a hit with no attacker or element: silent | `BattleController` `Handlers[EV.Hit]` |
| Crit | a critical hit, on top of the element hit | same |
| KO / KO2 / KO3 / KO4 | a pet is knocked out: `PlayVariant("KO")`, a boss's KO x1.2 volume | `Handlers[EV.KO]` |
| Dash | one of MY pets dashes | `Me.StartDash` |
| Parry | one of MY pets parries (a parried hit plays no hit sound) | `Handlers[EV.Parry]` |
| Reward (fix) | a won Champion Ring round (before the next round), as a plain win does | `Net.End`, the `ringNext` branch |
| PortalEnter | MY home portal swirls open; I use a lobby Travel gate (`AltarGatePrompt` / `PlazaGatePrompt`) | `HomePortalFx` `P.refresh`, `PromptTriggered` |
| PortalArrive | MY arrival ring | `HomePortalFx` `P.arrive` |
| StationBuild | a station or buy pad of MY home pops in (live, not on load) | `HomeFx` `buildSound` (`onHomeChild`) |
| HouseTier | MY `Station_House` appears at Level 2+ (the server's "<tier> built!"), INSTEAD of StationBuild | same |
| DialogOpen | an NPC dialog opens (not when switching NPCs mid-dialog) | `NpcController` `openRec` |
| DialogBlip | the typewriter, every 3rd visible letter (never a space / punctuation) | `stepTypewriter` |
| DialogNext | Next shows a new line (a Next that only finishes the typewriter is silent) | `NpcController.Advance` |
| Npc\<Name\>Greet / Hmm / Pleased | the NPC voice rule below | `openRec`, `NpcController.Advance` |
| TutorialStep | a tutorial step is done (`celebrate(false)`) | `TutorialController` |
| Reward | the tutorial's finale (`celebrate(true)`; the TutorialChapter take was skipped) | same |
| SpinStart | the roulette strip starts (Cloud Shop and the gems roulette share it) | `MenuController` `beginStage` |
| SpinTick | a cell passes the pointer (not during a skip's jump) | the strip's step loop |
| SpinLand | the strip lands | `land()` |
| RevealCommon / RevealRare / RevealLegendary | the reveal card: Common, Uncommon / Rare, Epic / Legendary, Mythic, Secret | `showReveal()` |
| Error (fix) | a NEW "bad" toast (a refused action); a merged repeat is silent | `NotifyController` `addToast` |
| Fountain (Ambient, key FountainLoop) (fix) | the lobby fountain's positional water loop, InverseTapered 10-70 studs, Sfx setting | `FountainFx` (`SoundFx.Positional`) |

FountainLoop has no approved take yet (skipped this wave), so the fountain stays silent until one is uploaded; the
smoke test lists it as a pending key.

Who hears a fight: my own fight (`B.Fighter`) at full volume; a spectator at half volume (`SFX_SPECTATOR = 0.5`) and
only within 80 studs of the camera (`SFX_HEAR`); Dash and Parry only for my own pets.

### The NPC voice rule (the owner's, 2026-10-30)

NPCs never speak words; every dialog line gets a wordless reaction sound ("Mhm?", "Mhmmm...", "AhA!"). The key is
`Npc<Name><Kind>`, `<Name>` = the NpcDialog Id in CamelCase (`sparky_fox` -> `SparkyFox`).

- **Greet**: 0.12 s (`Config.Audio.Voice.GreetDelay`) after the NPC's dialog opens, only if the card is still open on
  that NPC. Not when switching NPCs mid-dialog.
- **On each Next that shows a new line** (not a Next that only finishes the typewriter): if the new line is the LAST
  line, or its text holds a "!", play **Pleased**; otherwise play **Hmm**. "Again" on the last line shows line 1 again
  and follows the same rule.
- At most one voice per 1.5 s (`Voice.Gap`) per NPC: a Next inside the gap plays no voice. A new voice stops that
  NPC's previous one. An NPC without voice ids is silent, with no error.
- Volume 0.6, pitch 0.98-1.02 (`Config.Audio.Voice`, copied into `Volume` / `Pitch` for every voice key).

### Volumes, pitch, gaps (Config.Audio; starting values, tune by ear in Studio)

Volume is x the player's Sfx setting / 10 (DrumLoop follows Music). Pitch is the PlaybackSpeed range (not listed:
0.95-1.05; a range of 1.0-1.0 never shifts, for tuned motifs). MinGap: seconds a key waits before it can play again
(a play inside the gap is dropped). KO2-KO4 share KO's gap (`PlayVariant` passes `Gap = "KO"`).

| Key | Volume | Pitch | MinGap |
|---|---|---|---|
| HitFlame | 0.45 | 0.93-1.07 | 0.06 |
| HitFrost | 0.42 | 0.93-1.07 | 0.06 |
| HitShadow | 0.38 | 0.93-1.07 | 0.06 |
| HitWater | 0.38 | 0.93-1.07 | 0.06 |
| HitEarth | 0.38 | 0.92-1.06 | 0.06 |
| HitStorm | 0.36 | 0.93-1.07 | 0.06 |
| HitNature | 0.34 | 0.93-1.07 | 0.06 |
| HitCelestial | 0.28 | 0.96-1.04 | 0.06 |
| Crit | 0.55 | 0.97-1.03 | 0.15 |
| KO, KO2, KO3, KO4 | 0.7 | 0.97-1.03 | 0.25 (shared) |
| Dash | 0.6 | 0.95-1.05 | |
| Parry | 0.8 | 1.0 | |
| PortalEnter | 0.65 | 1.0 | 1.0 |
| PortalArrive | 0.6 | 1.0 | |
| StationBuild | 0.6 | 0.95-1.05 | 0.15 (a bought station and the next pad: one pop) |
| HouseTier | 0.85 | 1.0 | |
| DialogOpen | 0.55 | 1.0 | |
| DialogBlip | 0.3 | 0.96-1.04 | 0.045 |
| DialogNext | 0.5 | 1.0 | |
| TutorialStep | 0.7 | 1.0 | |
| SpinStart | 0.65 | 1.0 | |
| SpinTick | 0.4 | 0.98-1.02 | 0.025 |
| SpinLand | 0.75 | 1.0 | |
| RevealCommon | 0.7 | 1.0 | |
| RevealRare | 0.75 | 1.0 | |
| RevealLegendary | 0.8 | 1.0 | |
| Npc\<Name\>\<Kind\> (18) | 0.6 | 0.98-1.02 | (per-NPC Voice.Gap 1.5) |
| Error | 0.7 | 0.95-1.05 | 1.0 |
| FountainLoop (Ambient) | 0.45 | | |

Caps: at most 8 plays of the `Hit*` keys together per 0.25 s (a crowded raid). Variants: `KO = { KO, KO2, KO3, KO4 }`,
a random file that has an id, never the one played last (a missing id drops out of the rotation).

**UnderMusic exemption.** The smoke test's rule "every sound effect sits above the music" (music max 0.5) does not
apply to the frequent / quiet keys listed in `Config.Audio.UnderMusic`: the eight `Hit*`, `SpinTick`, `DialogBlip` and
`DialogNext`. They come many per second (or under a typewriter), so they sit at or under the music on purpose. Every
other effect must still be louder than the music.

Tests: `tools/smoke_audio.lua` (`client_audio_keys` / `_silent` / `_charge` / `_music` / `_ring` / `_mechanics` /
`_battle` / `_sites` / `_npc`; every key in `AUDIO_KEYS`, `PENDING_KEYS = { FountainLoop }`).
