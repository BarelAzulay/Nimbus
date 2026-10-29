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
my fights MusicBattle, a dungeon's boss room too), Click / Confirm / Whoosh (menus; Error has no caller yet since
Shatter took over the broken charge), Reward (a won fight, a
dungeon room's loot, the dungeon chest), Inhale / Shatter (a Special's charge and a broken charge, BattleController),
CrowdCheer / DrumLoop (positional loops at the Champion Ring pocket's crowd stand, client/Controllers/RingAmbience;
the drums move to a drummer once one exists: a part named `Drummer`, a crowd model with the attribute `Drummer = true`
(the art-wave branch's drummer) or anything tagged `NC_RingDrummer`; a plaza stand tagged `NC_RingCrowd` gets its own
crowd loop). Slot volumes: `Config.Audio.Volume`. A won dungeon room plays Reward once, with its Loot (not at the
room's End too).

## Wave 2 sound effects (final files, 2026-10-30)

Picked by the player on the wave-2 pages: round 1 https://claude.ai/artifact/2CbUHV6TNPpiHbdrK4ruNM and round 2
https://claude.ai/artifact/QDH2QZcP7duUofuUjaB8Mx (round 2 overrides round 1 for a slot in both). All original,
ElevenLabs sound effects (Creator plan). 29 one-shots, slot `Sfx`, not looped. Skipped by the player (no file):
FountainLoop, TutorialChapter. The NPC voices are not in this batch (being redone without words).

Each file is rebuilt from the RAW ElevenLabs take with the exact chain of its preview
(`.superpowers/audio-pitch/wave2/final/w2_final.py`: 35 Hz high-pass, trim, -18 dBFS active RMS with peaks <= -1 dBFS,
plus the take's own layering / cut), not re-encoded from the mp3 preview; Ogg Vorbis q7, 44.1 kHz, mono when the take
has no real stereo (side/mid RMS under 0.15). Checked against the approved preview with a libvorbis decode
(`w2_verify.py`): same length to the sample, peaks within 1.4 dB of the mp3 peaks (lossy peaks move; all <= -0.9 dBFS), active RMS 0.2-0.8 dB above the
mp3 (the mp3 lost some top end), correlation >= 0.95 (Crit 0.96: its 11 kHz sparkle is what the mp3 cut most).

**Not wired yet**: these keys are in `audio.json` for the upload; `Config.Audio.Keys`, `SoundFx.NAMES` and the call sites
come after the wave-6 branch merges (plan: `.superpowers/audio-pitch/wave2/wiring-plan.md`). Until then they are silent.

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

Upload: one `--audio` run creates these 29 (the 12 above are unchanged and skipped). Roblox counts audio uploads per
account per month (100 with ID verification, which the owner has): 12 used this month, this batch adds 29.
