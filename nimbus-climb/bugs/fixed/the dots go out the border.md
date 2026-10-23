# the dots go out the border (fixed 2026-10-23)

**Report:** screenshot `the dots go out the border.png` (tutorial card, step 1 "Hi there, climber!").

**Cause:** on a narrow tutorial card (278 design px here: a small Studio window, UIScale 0.8) the header has 142 px
for the progress pips, but `applyGeometry` never let a pip go below 6 px or the gap below 5 px, so 21 pips needed
~228 px and ran 84 px past the border. The same narrow card also cut "Nimbus" to "Nimb...", truncated the step title,
let "Let's go!" cover "Skip tutorial", and left the skip-confirm question ~30 px.

**Fix** (`src/client/Controllers/TutorialController.lua`):
- Pips and gaps shrink together (2 px ring + 5 gap, then 1 px ring + 3 gap); when even 4 px pips cannot fit, a slim
  progress bar (gold = done, white = current, breathing) replaces them. Width sweep 260-440 px x 5-40 steps: no overflow.
- The name (min 22) and step title (min 18) shrink to fit before truncating.
- Narrow footers show "Skip" instead of "Skip tutorial" and narrow the Next button; the confirm row narrows its
  buttons and asks "Skip?".

**Evidence:** live Studio playtest at the same 278 px card: bar x=260..370 inside the header (edge 372), name and title
`TextFits = true`, Skip ends at 226 and Next starts at 242, confirm row "Skip?" | Skip | Stay all fit.
