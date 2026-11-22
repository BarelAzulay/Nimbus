# Step 1 rollback plan (quick-wins goes live)

Rule: **restore first, find the cause after.** A rollback is safe for saves. It was tested with main's own code
(`tools/save_roundtrip.py`, main at `ac552d0`).

## Before you press Publish (5 minutes)

1. Pick a quiet time. Stay at the PC for about 1 hour after.
2. Open two Creator Hub tabs for the MAIN experience and leave them open:
   - **Configurations > Places > (the start place) > Version History**
   - **Configurations > Server management**
3. In Version History, write down the top version that says it is published. That is the one you restore.
4. Join the live game once and write down your own Tokens, Cash, Gems and pet count.

## Roll back when one of these happens (first hour)

| Trigger | How you see it |
|---|---|
| **Any save loss** | Your own numbers or pets are lower after the update, or a player shows a before / after. One real case is enough. |
| **Players can't join** | You or the alt cannot get in, or players sit on the loading screen for more than 1 minute. |
| **Error spike** | The error count in Creator Hub is clearly higher than before the publish and stays high for 5 minutes. |

Not a trigger: a player who sees "Another server is still saving your progress..." for up to 12 seconds after a
server hop. That is the session lock working.

## What to check first (2 minutes, then decide)

1. **Join** with your account and the alt. Do you both get in?
2. **Your save**: are Tokens, Cash, Gems and pets the same as the numbers you wrote down?
3. **Rejoin**: leave, wait 10 seconds, join. Still the same?
4. **Server log**: press F9 in the game, open **Server > Log**. Red lines that start with `[DataService]` are the
   ones that matter: `fetch errored`, `Load failed`, `Save errored`, `recovery errored`. One line now and then during
   a Roblox hiccup is normal. A stream of them is a trigger.
5. **Errors**: Creator Hub > Monitoring (the error report). Compare with the hour before the publish.
6. **Players**: the Discord `#nimbus-bugs` channel.

If any trigger is true, roll back now. Do not debug on the live game.

## How to roll back

Roblox's own steps ([Version History](https://create.roblox.com/docs/projects/version-history),
[Update games](https://create.roblox.com/docs/projects/update-games)):

1. Creator Hub > **Creations** > the MAIN experience.
2. **Configurations > Places** > the start place > **Version History**.
3. Click **Restore** next to the version you wrote down. Confirm.
   Roblox says: this makes a new version, and it does **not** publish it by itself.
4. Open the place in **Studio** and **publish** it (File > Publish to Roblox). Check the name of the experience
   before you confirm.
5. Creator Hub > **Configurations > Server management** > tick the place > **Restart Servers**.
   Tick "Restart only servers with outdated versions". No delay.
   Roblox stops sending players to the old servers and teleports them to the restored version.
6. Join with both accounts. Check your numbers again.
7. Tell the players (texts below). Tell Claude: the time, what you saw, screenshots.

Step 5 matters. Without it, servers of the new version keep running until they empty.

## What a rollback does to saves (tested)

- **Main reads every save quick-wins wrote**, at once, with no error and no warning. Tested on a new player, a
  maxed player, two saves with missing fields, two v1 saves and an empty one.
- **No field main knows is lost or changed.** Tokens, Cash and Gems earned on quick-wins are still there.
- **A lock left by a quick-wins server does not block main.** Main does not read the lock.
- **Old and new servers running together are safe** in both directions: Tokens earned on both end up in the save.
- **quick-wins data waits in the save.** Main writes these back untouched: the Store record, the daily streak, the
  Sky Trove and the Secret pity count. They are there again when quick-wins returns.

**What a player loses if they play on main after the rollback** (small, and only these):

| Field | Effect |
|---|---|
| Raid reward clock, raid loss clock | They restart. A player may get one raid reward sooner than the cooldown. |
| Recent duel notes | Forgotten. The duel reward window for the last opponents restarts. |
| Fast hatch setting | Goes back to off. |

Also true while main is live: the daily streak does not count days (main has no daily gifts), so a streak can step
back by its own 48 hour rule; the leaderboard and the titles are not shown.

**What a rollback does not do:** it does not bring back data that was already lost. It only stops more loss. Roblox
keeps older versions of each save key for about 30 days. Restoring one player's save from those is a separate job:
ask Claude, nothing is built for it yet.

## What to tell players

Rollback, no save problem:

> We rolled back today's update for a fix. Your progress is safe. Sorry for the restart!

Rollback, some saves affected:

> We rolled back today's update because some saves looked wrong. If you lost pets or currency today, post your
> username and what is missing in #nimbus-bugs. We will look at every case.

After the fix is live again:

> The update is back with the fix. Thank you for the reports!

## After a rollback

- Do not publish again until the cause is known and a test shows it fixed.
- Returning to quick-wins later is safe. A lock left by a crashed server is ignored after 6 minutes.
