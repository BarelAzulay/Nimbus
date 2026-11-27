# Combined release test checklist (owner, about 60 minutes)

This is the test of the ONE combined release: kit-b's new look, the guide chip, the tutorial fixes, the slim match bar,
step 1's Store off and save safety, and the 104 new meshes (evolved pet eyes and the Sky Trove chest).
After this test it goes to MAIN, but only after your yes in the chat.

Where: the test experience **"Nimbus test 2.0"** (universe 10779238980, place 74125226332082). **Never MAIN.**

`BUILD: <filled in by Claude after the final rebuild>`

(Claude writes the commit id and the number of scripts on the line above. If it still says "filled in by Claude",
stop and ask Claude. Do not test an unnamed build.)

How to use this page:
- Do the parts in order. The save part comes first, before anything changes your save.
- Each step has a tick box and a **You should see** line. Tick it when you saw that.
- F9 in the game opens the Developer Console. **Server > Log** is the server log (you see it as the owner).
  **Client > Log** is your own log.
- Something looks wrong? See "If something is wrong" at the end.

These look different on purpose for now. Do not report them:
- The small icons (menu tiles, wallet strip, Shop tabs) are little pixel drawings. The new carved icon picture is
  not uploaded yet.
- The egg machines in the Shop are the drawn ones. The new machine picture is not uploaded yet.
- The title and loading screens show the "Storm plaque" logo. The new voxel logo is not uploaded yet.
- The raid's top card has no boss face. The boss portraits are not made yet.
- The Sky Trove says "Coming soon". That is right: it has no group yet.

## Setup (10 minutes)

- [ ] **1. Open the right file.** In Studio: File > Open from file. Pick
      `Projects Main\Nimbus\.worktrees\release-combined\nimbus-climb\play\NimbusClimb.rbxlx`
      (branch `release-combined`). Do **not** use the MAIN place window: its saved copy is an old dev build.
      A Rojo popup appears: press **Dismiss**. Never press Connect.
      **You should see:** the Studio window title says `NimbusClimb.rbxlx`.
- [ ] **2. Publish to the test experience.** File > Publish to Roblox As > **Nimbus test 2.0**. Read the name twice
      before you confirm.
      **You should see:** Studio says it published to Nimbus test 2.0. Nothing else.
- [ ] **3. One player per server.** Creator Hub > Nimbus test 2.0 > the place > settings > Access: maximum players
      **1**. (Button names can differ a little.)
      **You should see:** maximum players is 1. Now every rejoin starts a new server. The save steps need that.
- [ ] **4. No old server left.** Creator Hub > Nimbus test 2.0 > Configurations > Server management >
      **Restart Servers**.
      **You should see:** Creator Hub says the servers restart.

## Save (solo, 15 minutes)

You played this account on the live build in Nimbus test 2.0 before. You did not write the numbers down, and that is
fine: check by eye that it looks like before.

- [ ] **5. Join.** Join Nimbus test 2.0 on the PC.
      **You should see:** you are in the lobby in under 15 seconds. F9 > Server > Log shows `[NimbusClimb] ready`.
      No `[DataService]` line in red or yellow.
- [ ] **6. Your old save is there.** Look at Tokens, Cash, Gems, your pets and the pets that follow you.
      Take a screenshot (it helps for step 8).
      **You should see:** about the same as before. No pet is missing. No number is 0 that was not 0.
- [ ] **7. Play 5 minutes.** Play normally: finish a climb, spin an egg with Tokens. Before you leave, take a
      screenshot of Tokens, Cash, Gems and the pet count.
      **You should see:** the game plays normally. F9 > Server > Log has no `[DataService] Save errored` line.
- [ ] **8. Rejoin.** Leave. Wait 10 seconds. Join again.
      **You should see:** the numbers from your step 7 screenshot. The new pet is there.
- [ ] **9. Quick server hop.** Earn a few Tokens. Leave and join again at once (inside 3 seconds).
      **You should see:** maybe "Another server is still saving your progress..." for up to 12 seconds. Then the game
      loads with the Tokens you just earned. Nothing lost, nothing doubled.
- [ ] **10. Same account on two devices.** Stay in the game on the PC. Join with the SAME account on your phone.
      **You should see:** Roblox disconnects the PC ("same account launched from a different device"). The phone
      loads, maybe after the "still saving" line, with the same numbers. Close the phone, join on the PC again: same
      numbers.

## Store off (5 minutes)

- [ ] **11. Shop from the top bar.** Open the Shop.
      **You should see:** the rail on the left has **one tab: Eggs**. No Gems, Packs, Passes or Boosts tab.
      No "ROBUX ITEMS". No "PREVIEW". No Robux price anywhere.
- [ ] **12. Shop from an egg machine, and on the phone.** Walk to an egg machine in the lobby and press E. Then open
      the Shop on the phone too.
      **You should see:** the same: only the Eggs tab, on both.
- [ ] **13. Token spins work.** On a machine card, press **Spin**, then **x3**, paid with Tokens.
      **You should see:** Tokens go down, the pets hatch. The button never says "Locked". No "Checking your account".
- [ ] **14. No Robux anywhere.** Open every menu tile (Pets, Index, Gifts, Stats, Settings, Home, Travel) and walk
      up to the Sky Trove chest.
      **You should see:** no window asks for Robux. F9 > Server > Log has the line
      `[StoreService] the Store is OFF (Config.Store.Enabled = false)`.

## Look checks (25 minutes)

Look at each place on the PC first. Steps marked **(small phone)** are done in Studio's device emulator:
open the same file in Studio (Dismiss the Rojo popup), Test tab > **Device**, pick **iPhone SE** in the bar above the
game view, turn it to **landscape** with the rotate button, then press **Play**. Leave the real game first.

What "looks right" means everywhere: sharp pixel edges (no blur), whole words (no "Pick Your Te..."), nothing on top
of anything else, nothing on the RUN / DASH / jump buttons.

### Lobby

- [ ] **15. Title and loading screens.** Join again and watch the loading and title screens.
      **You should see:** the carved wooden signboard look, the Storm plaque logo, no cut words.
- [ ] **16. Lobby screen.** Look at the menu tiles, the wallet strip (Cash, Tokens, Gems) and your vitals card.
      **You should see:** the vitals card has a wooden name tab with your whole name, and HP and stamina in blocks.
      Everything sharp and in one style.
- [ ] **17. The world.** Walk around the lobby. Type `/sky sunset` in the game chat (it changes no save).
      **You should see:** stone name tags over the places. The sun sets behind the clouds, with no hard jump.
- [ ] **18. Show the way.** In the Shop, on the Secret Roulette card, press "Show the way". Follow the gold arrow to
      the Storm Altar gate. Jump at the gate a few times.
      **You should see:** the arrow always shows. The guide chip ("Guiding to Storm Altar") sits on the top bar's
      wooden plank, steps aside for signs, and does not blink on and off while you jump. At the gate it says
      "You're here: press E".

### Shop

- [ ] **19. Eggs tab.** Open the Shop and look at the whole Eggs tab.
      **You should see:** the Secret Roulette at the top, four machine cards with their odds chips, all four cards
      whole on the PC.
- [ ] **20. Hatch.** Spin once with Tokens. Next time press Skip.
      **You should see:** the egg cutscene on the wooden kit, the pet appears. Skip works at once. You are back in the
      Shop.

### Pets and gifts

- [ ] **21. Pets and Index.** Open Pets, then Index.
      **You should see:** your team and its power clear of the close button. In the Index the reward sits on the tab's
      row and the group names are on one line.
- [ ] **22. Elements and care.** Open Elements. Open Training, then Fusion (the pet picker).
      **You should see:** Elements as its own window in the middle. The pet picker fills the screen. A busy pet keeps
      its picture with a thin strip on it, not a cover.
- [ ] **23. Gifts.** Open Gifts, then the Daily page.
      **You should see:** the Daily page as a prize stand. CLAIM is locked until you have played 10 minutes today.

### Tutorial

- [ ] **24. Tutorial on the PC.** Type `/tutorial` in the game chat. (This starts the tutorial again on this account.
      Its gifts are never paid twice.) Go through the first steps.
      **You should see:** the folded tutorial is a quest strip. A tap opens its card. Titles are whole. Next and Skip
      work.
- [ ] **25. Tutorial (small phone).** In Studio's emulator, iPhone SE landscape, then portrait.
      **You should see:** the strip and its chip are not on the wallet strip, RUN, or the match panel. In portrait a
      tap opens the card.

### Match HUD (small phone)

- [ ] **26. Countdown.** In the emulator, iPhone SE landscape, walk into the **Easy** portal. Wait for the countdown.
      **You should see:** the match panel on a stone signboard. Your vitals are **one slim row** at the bottom between
      the stick and RUN: heart, HP blocks, bolt, stamina blocks. Your name on its wooden tag, whole. Nothing on RUN,
      DASH or the jump button.
- [ ] **27. In the match.** Play the climb to the end.
      **You should see:** the match card shows the clock, the checkpoint blocks and the tokens in one row
      (like `8:53 [blocks] 7 / 24`). At the end, one result card. Nothing covers the buttons.
- [ ] **28. Pet battle on the phone.** In the emulator, start a pet battle in the Arena.
      **You should see:** three action keys as clean blocks, Cheer up! and Retreat apart from each other, the team
      list whole. A melee pet bounces in, bites and hops back.

### Raid boss bar

- [ ] **29. Raid.** On the PC, type `/raid` in the game chat and go to the boss.
      **You should see:** the raid's top card is one stone card with the boss's whole name, one timer, and the minion
      wave. Do it once more in the emulator (iPhone SE landscape): the same, nothing cut.
- [ ] **30. Raid end.** Finish or lose the raid.
      **You should see:** one result card that says when the rewards come again.

### Sky Trove (lobby)

- [ ] **31. The chest.** Walk to the FREE GIFT chest in the lobby (the Sky Trove).
      **You should see:** a smooth, solid chest with a lid and a sign, not a pile of blocks. F9 > Client > Log has no
      `stays on the Part build` line with `prop_trove`.
- [ ] **32. Open it.** Press E (Open).
      **You should see:** the panel on the right side with its two rows. The group row says "Coming soon", no JOIN
      button, no Robux.

### Evolved pet eyes

- [ ] **33. Evolved pets.** Type `/pets 1` in the game chat, look, then `/pets 2`, look, then `/clearpets`.
      (These show pets in front of you. They change no save.)
      **You should see:** every evolved pet has smaller eyes, centred in the face. No pet is missing its eyes or its
      body. F9 > Client > Log has no `stays on the Part build` line with `evo1_` or `evo2_`.

## Later, with the alt account (another day, 15 minutes)

- [ ] **34. Let the alt in.** Add the alt as a collaborator who can play, or set the audience to friends and friend
      the alt. The alt joins and plays 3 minutes the normal way, with no DEV tools: a climb, a spin with Tokens, a
      visit home.
      **You should see:** no error on screen. The Token Spin works (never "Locked", never "Token spins are not
      available on your account").
- [ ] **35. The alt rejoins.** The alt leaves, waits 10 seconds, joins again.
      **You should see:** the alt's numbers and pets are kept.
- [ ] **36. Leaderboards.** Look at the lobby board. It turns a page every 15 seconds and reads the saved list every
      4 minutes.
      **You should see:** the TOP PETS FOUND page shows both accounts with the right numbers. No red
      `[LeaderboardService]` line in the server log. Empty pages are fine.
- [ ] **37. Practise the rollback.** Follow `docs/release/step1-rollback.md` once in Nimbus test 2.0: Creator Hub >
      the place > Version History > **Restore** the version before this release (the live build you played).
      Restart Servers. Both accounts join.
      **You should see:** the game loads at once. Tokens, Cash, Gems and pets are not lower than before.
- [ ] **38. Back to this release.** Publish this release's file again (Setup steps 1, 2 and 4). Both accounts join.
      **You should see:** the numbers include what you earned on the old build. The Shop shows only Eggs.

## Result

- [ ] **39. All ticked** (the alt part may come later): tell Claude "combined test passed". The PR can be merged
      only after your yes in the chat.
- [ ] **40. Any step failed:** tell Claude the step number. **Do not publish to MAIN.**

## If something is wrong

1. Take a screenshot of it.
2. Save it into `nimbus-climb\bugs\`. The file name is the problem, for example `vitals bar on RUN iPhone SE.png`.
3. Tell Claude the step number.
4. Never publish to MAIN to "fix" it.

Known and left for later (no need to report, the owner's call in the kit-b backlog
`docs/superpowers/backlog/2026-11-24-kitb-look-backlog.md`): the fourth machine card cut on 960 x 540 and 1024 x 768
windows; the guide chip still blinks a little when you jump
slowly at the gate; the tutorial card does not open on the smallest portrait phones (320 wide or 568 tall).
