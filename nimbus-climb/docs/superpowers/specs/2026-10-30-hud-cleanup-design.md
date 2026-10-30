# HUD cleanup + Ring no-heal (design)

Date: 2026-10-30. Source: the owner's requests after a playtest, pitched on
https://claude.ai/artifact/JyHdJtEukQ3unY9X7KDZUb (mock-ups drawn to scale, PC 1920x1080 + phone 844x390). All five
slots approved. Gemini could not take part (its API had no credits); every pitched pick was Claude's.

## The owner's words

"put the settings and the shop UI buttons top left next to [Roblox's topbar], also delete the teams UI button, and add a
create team when you press on a portal that requires a team. and delete the items UI button, the current items in the
game are unnecessary. in the champions ring you full heal every wave, get it removed, they suppose to survive. in the
lobby add a button for portals and lobby."

Ring note on the pitch: "still need to balance the champion ring because the pets levels are getting high but they are
weak and losing to much lower rank pets... make the climb harder, and the enemy pet's level works with stats the same
as the player's pets stats". Team note: "add an autofill best pets button".

## Decisions (approved)

1. **Top-left pill (B).** One grouped pill right of Roblox's topbar buttons (first free x ~212 px on PC; read the real
   inset from GuiService:GetGuiInset / TopbarInset, never hard-code), holding Shop (gold bag icon), Travel (lobby only)
   and Settings (gear). The left column keeps Pets, Index, Home, Stats. Same pill on phone; it must not collide with
   the HUD's phone TopBand (currency strips during battles start at BAND_LEFT 150: move them right of the pill).
   Shop is still refused during a match (same rule as today).
2. **Battle team at the portal (C).** The Team tile goes. Every team portal panel (Dungeon panel, Battle Arena queue /
   raid / duel entry) shows a team strip (the active preset's pets) with **Edit** and **Auto-fill best** buttons.
   Pressing a team portal with an empty team opens a "Pick your battle team" popup (3 slots, Auto-fill best, Save and
   enter, Cancel) and continues into the portal after Save. Team editing otherwise lives in the Pets window as a
   **Team** tab where the Items tab was (the existing P3.BuildTeam editor). The tutorial's "team" step points at the
   new place. The server refusal text "Pick your battle team first (Menu > Team)" changes to match.
3. **Quick Travel (A).** Travel button in the pill, lobby only (hidden in a match, a dungeon run, a battle, the Ring,
   the Arena island and the Altar island). Tap: a small drop-down under the button with Portals (Gate Court) and
   Lobby (spawn plaza). Server-validated teleport (rate-limited remote, only from lobby zones, not while InBattle /
   in a party countdown), short fade.
4. **Items removed (C).** Remove the Items tile, the Items tab, the Shop's Items tab, the hotbar item slots, the three
   obby items (heal_cloud, shield_bubble, phoenix_feather), ItemService buy/use, their remotes and NPC price lines.
   Saved `Items` are refunded once as Tokens at the catalog price (30 / 45 / 150 each) with a message, then cleared
   (a data version flag so it never pays twice). The Item Shop stall stays as decoration, **boarded up** with a
   Closed board, its prompt removed.
5. **Ring (B + note).** Pets keep the HP they end a round with; a fainted pet stays out for the run; no heal between
   rounds. Champion pets get their stats from the SAME level / rarity / stage formula as player pets (no separate
   champion stat path), so a level number means the same strength on both sides. The climb: early rounds easier than
   today, later rounds harder than today, tuned with tools/sim_battle.lua so (a) a team at the panel's suggested power
   clears about as many rounds as today, (b) a high-level team beats a much lower-level champion team, and (c) the top
   rounds stay hard for maxed teams.

## Non-goals

- No new shop items, no new team presets, no change to Obby parties or Dungeon parties.

## Anti-goals

- A topbar pill that overlaps Roblox's buttons or the chat window on any screen size.
- A player stuck in front of a portal with no way to set a team.
- Losing a player's tokens or pets in the item refund.
- A Ring run that ends on round 1-2 for a normal team.

## Left to the builder

Exact icons (simple, matching NeonKit / CloudUI), fade length, the champion level curve per round, how the boarded
stall is built (follow how LobbyBuilder already builds the stall).
