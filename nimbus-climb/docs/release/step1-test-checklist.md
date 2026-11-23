# Step 1 test checklist (owner + 1 alt, about 40 minutes)

Where: a **separate private experience** called "nimbus TEST". **Never a place inside MAIN's experience**: places in
one experience share the same saves.

You need: the owner account, one alt account, a PC, and a phone (or a second browser) for step B6.
F9 in the game opens the Developer Console. **Server > Log** is the server log (owner only).

Tick each box. If a step fails, stop and tell Claude: the step, what you saw, a screenshot.

## Setup (5 minutes)

- [ ] Create the experience "nimbus TEST" (Studio: File > Publish to Roblox As > new experience). Keep it private.
- [ ] Let the alt in: add the alt as a collaborator who can play, or set the audience to friends and friend the alt.
      (Button names in Creator Hub can differ.)
- [ ] Set the place's maximum players to **1** (place settings > Access). Then every account gets its own server and
      every rejoin starts a new server. That is what the save tests need.

## Part A: make real old saves (8 minutes)

This puts TODAY's live game into TEST, so TEST gets saves in the old format.

- [ ] A1. Open MAIN's live place in Studio. File > Publish to Roblox As > **nimbus TEST**. Read the name twice
      before you confirm.
- [ ] A2. Join TEST with both accounts. Play 3 minutes each: finish the first tutorial steps, hatch a pet, earn some
      Tokens. The owner can use the DEV button for Tokens and Gems.
      **Pass:** both accounts play normally.
- [ ] A3. Write down for each account: Tokens, Cash, Gems, number of pets, the pets that follow you.
- [ ] A4. Both leave. Wait 30 seconds.

## Part B: the quick-wins build (22 minutes)

- [ ] B0. Publish the checked quick-wins `.rbxl` Claude prepared to **nimbus TEST** (same place, overwrite).
      Creator Hub > Configurations > Server management > Restart Servers, so no old server is left.

- [ ] B1. **Join** with both accounts.
      **Pass:** you spawn in the lobby in under 15 seconds. F9 > Server > Log shows `[NimbusClimb] ready` and no red
      `[DataService]` line.

- [ ] B2. **Old save loads.** Compare with the numbers from A3.
      **Pass:** Tokens, Cash, Gems, pets and the pets that follow you are the same or higher. Nothing is missing.

- [ ] B3. **Save.** Earn Tokens (finish a climb or use the DEV button), hatch one more pet. Write the new numbers down.
      Stay 2 more minutes (one autosave).
      **Pass:** no red `[DataService] Save errored` line in the server log.

- [ ] B4. **Rejoin.** Leave, wait 10 seconds, join.
      **Pass:** the numbers from B3 are there. The new pet is there.

- [ ] B5. **Server hop.** Earn a few Tokens, then leave and join again at once (inside 3 seconds). With maximum
      players 1 this is always a new server.
      **Pass:** you may see "Another server is still saving your progress..." for up to 12 seconds, then the game
      loads with the Tokens you just earned. Nothing lost, nothing doubled.

- [ ] B6. **Session lock.** Stay in the game on the PC. Join with the SAME account on the phone.
      **Pass:** the PC is disconnected by Roblox ("same account launched from a different device"). The phone loads,
      maybe after the "still saving" line, with the same numbers. Then close the phone and join on the PC again:
      same numbers.

- [ ] B7. **Leaderboards.** Look at the lobby board now and once more at the end of Part B. It turns a page every
      15 seconds and reads the saved list every 4 minutes.
      **Pass:** the TOP PETS FOUND page shows your own account with the right number. At the end of Part B it shows
      both accounts (each hatched a pet). No red `[LeaderboardService]` line in the server log. Empty Trophies /
      Ring pages are fine in a new experience.

- [ ] B8. **Store hidden.** Open the Shop from the top bar, and again by pressing E at an egg machine.
      **Pass:** the rail on the left shows **one tab: Eggs**. No Gems, Packs, Passes or Boosts tab. No "Robux items".
      No "PREVIEW". No "Coming soon". No Robux price anywhere. The server log has the line
      `[StoreService] the Store is OFF (Config.Store.Enabled = false)`.
      Check it on the phone too. (The Sky Trove chest in the lobby still says "Coming soon". That is not the Store.)

- [ ] B9. **Gems.** The live game sells nothing for Robux today (all four gem packs have no product id), so there
      is nothing to buy and no Robux window can open. Test spending: the owner gives itself 100 gems with the DEV
      button, then spins the Cloud machine with the gem button (20 gems).
      **Pass:** gems go down by 20, a pet hatches, and the gems stay down after a rejoin.
      (If the gem button says Locked, your account's country or age blocks paid random items. That is Roblox's
      policy rule working, not a bug. Skip this step then and say so. The live game has the same rule for gem spins.)
      That rule locks **only the gem button and the Secret Roulette** while the Store is off. The Token **Spin** and
      **x3** buttons on the same card must stay open on every account (owner's pick, 2026-11-23): see B10.

- [ ] B10. **Alt, no DEV tools.** The alt plays 3 minutes the normal way: a climb, a spin with Tokens, a visit home.
      **Pass:** no error message on screen, the numbers are kept after a rejoin.
      The spin with Tokens works on **every** account while the Store is off, as in the live game: also on an
      account Roblox restricts from paid random items, and also in the first seconds after a join, before Roblox's
      policy answer has arrived. **Fail:** the Token Spin button says "Locked", or you read "Token spins are not
      available on your account" or "Checking your account". Tell Claude. (That lock comes back, on purpose, only
      when the Store is turned on and Tokens can be bought.)

## Part C: practise the rollback (8 minutes)

Do the real steps of `step1-rollback.md` once, in TEST, so they are not new on the day.

- [ ] C1. Creator Hub > nimbus TEST > Configurations > Places > the place > Version History > **Restore** the
      version from Part A. Open the place in Studio and publish it. Restart Servers.
- [ ] C2. Join with both accounts.
      **Pass:** the game loads at once (the old build has no lock and does not wait). Tokens, Cash, Gems and pets
      are the numbers from Part B. Nothing is lower.
- [ ] C3. Play 1 minute, earn a few Tokens, leave.
- [ ] C4. Publish the quick-wins `.rbxl` again. Restart Servers. Join.
      **Pass:** the numbers include the Tokens from C3. The Shop still shows only Eggs.

## Result

- [ ] Every box above is ticked: tell Claude "step 1 test passed". The PR can then be merged after your yes in chat.
- [ ] Any box failed: tell Claude which one. Do not publish to MAIN.
