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
the drums move to a drummer once one exists). Slot volumes: `Config.Audio.Volume`.
