# Fight feel: check page + readability pitch (design)

Date: 2026-11-23. Branch `fight-read` (from kit-b 1a55f73). Owner approved this design in chat (away from the PC, on the phone).

## Why
The owner, playing the LIVE game: fights feel off. Of four problems (same-y, choices don't matter, no reason to fight,
feel), the owner fixes **feel** first, and inside feel two things hurt: **hits don't land** and **hard to read**.
The live game has none of the feel work built since: attack-fx (impact package, merged in main but main is not
published), battle-feel + feel-balance (aim at centre, standoff 8, weighty specials with a real cast; on integration),
kit-b motion (Bounce-in melee A, 0.25 s client wind-up, hit stop 0.05, victim knock-back + rock on its paws).
Readability has no pass of its own: boss telegraphs and the parry cue exist, nothing says "who is hitting whom", and
the new effects add noise.

## Approaches (owner picked 1)
1. **Check, then fill the gap (picked).** A phone page now: built hit work next to live, plus a readability pitch.
   Later one Studio fight on kit-b with the owner; build only what still feels weak + the picked readability options.
   Cheapest; nothing built twice.
2. Readability pitch only: trusts the built hit work unseen; risks coming back to hits later.
3. A new feel design from scratch: ignores three branches of unseen, finished work.

## Goals
- Part 1 "What's already built": for each moment (melee bite, special, crit, boss hit), LIVE vs KIT-B side by side,
  pictures that move where motion is the point (GIFs). Each moment: "feels right / still weak" + a note.
- Part 2 "Readability": 3-4 problems, each 2-3 drawn options at real HUD scale (phone 844x390 and PC 1920x1080 where
  it matters), my pick + Gemini's pick marked, disagreements said:
  - who my pet is hitting (target marker);
  - what is dangerous and when to dodge (telegraph style);
  - too much noise (other players' effects in raids / shared fights);
  - damage numbers that read at a glance.
- The owner's choices save to the page (artifact database); I read them back before any build.

## Non-goals / anti-goals
- No game code, no balance numbers, no uploads, no merges. The running run (qw-step1-gate, kitb-p2-fix6) is untouched.
- Anti-goal: a pitch whose options look alike, or text-only options (owner rule: every option is a picture).
- Anti-goal: readability fixes that hide the new hit feel (a marker or dimming that cancels the impact package).

## Constraints
- Every picture from real sources: existing pitch GIFs / renders (attack-fx-pitch, battle-feel pitch, build/PITCH2
  motion GIFs), Blender renders of the real voxel pets, or HUD mock-ups drawn to scale in kit B's tokens. Live
  pictures from main/live code where they exist; where none exist, a Blender re-creation labelled as such.
- Blender only for 3D (owner rule). Kit B look for UI mock-ups.
- Gemini: API is 402; use the web fallback (gemini.google.com via Claude in Chrome) if connected, else mark "Gemini:
  not reached" honestly.

## Left to the builder
Which existing images to reuse per moment, GIF lengths, mock-up layout, exact option set per readability problem
(2-3 each, genuinely different).
