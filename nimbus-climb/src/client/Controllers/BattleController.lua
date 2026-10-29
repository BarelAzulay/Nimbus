-- BattleController (client; Phase 3 battleclient, Phase 5 rewrite of the HUD + controls): draws every pet battle the
-- server simulates and gives the local player the fighter's controls (ARCHITECTURE_V3.md "Phase 5 build contract" 4.7
-- and 3.9; the drawing / effects / unit cards / Ring cards of Phases 3-4 are kept). The server simulates, the clients
-- draw: nothing here is authoritative (Y1). Battle units are built locally (PetBuilder for pets, BossBuilder for raid
-- bosses) and animated between the server's 10 Hz snapshots (Replication rule).
--
-- API
--   BattleController.Init()                 connects BattleState, the frame loop and the input (once)
--   BattleController.Stop()                 tears everything down (tests / hot reload)
--   BattleController.HandleState(kind, payload, battleId)   what the BattleState remote does (tests / dump_gui)
--   BattleController.Command(action, arg) -> bool   sends BattleCommand: "Attack" (unitId|nil), "Element", "Special",
--                                           "Dash", "Target" (unitId|nil), "Buff" (slot), "Swap" (slot), "Forfeit",
--                                           with a local throttle and local checks (a refused press shakes its
--                                           button); false when refused here
--   BattleController.Focus(unitId)          lock an enemy (= Command("Target", unitId)); nil clears the lock
--   BattleController.Cheer() -> bool        wave 6: Cheer up! (= Command("Cheer")): Raid / Dungeon fighters only; the
--                                           button right above the vitals card (CheerUp) does the same
--   BattleController.GetBattle() -> { Id, Mode, Side, Spectator, Fighter, Ended, Units, Models, Lock, Focus (= Lock),
--                                     FighterId, Lives, Hud, Layout = "Wide" | "Compact", Cooldowns = { Element, Dash,
--                                     Swap, Cheer, Buff = { [slot] = s } } (seconds left), Cheering (the Cheer up! glow), Pending = { [action] = true },
--                                     Speed = { Walk, Run }, Dungeon, Threat, Cue ("Dash" | nil), InterpDelay, TeamPlace,
--                                     Round, Best, Next, ... } | nil
--   BattleController.GetUnit(id) -> { Id, Side, Kind, Name, Hp, MaxHp, State, Meter, Model, X, Z, World, Card, Level,
--                                     Evo, Xp, XpNext, Crowned, Writes, Benched, Windup, Drawn (the drawn root position),
--                                     Pose, PoseP (the battle pose drawn: a PetPoses name | nil, its p) }
--   BattleController.GetStats() / ResetStats() / IsHudVisible() / ScreenPick(x, y) / GetTelegraphs()   (as Phase 3;
--                                     GetStats().AttackFx = AttackFx.Stats() once the pet attack VFX are loaded)
--
-- Messages (BattleState(kind, payload, battleId), sent by BattleService)
--   "Start"    battle:Describe() + Zone + Names + Side (0 = spectator) + Spectator + T + Ring / Dungeon (= the encounter's
--              Extra { Floor, Room, Wave, Waves, Name, Boss }) + Team = { Fighter, Bench, Lives, Speed = { Walk, Run },
--              Cooldowns = { Element, Dash, Swap, Buff = { ["2"] = s, ["3"] = s } } } (seconds left; the Buff keys are
--              STRINGS on the wire). A second "Start" for the same battle (a raid spectator who joins) refreshes it.
--   "Snapshot" { BattleId, T, U = { number... } }: BattleSim:SnapshotDelta's wire form (lives + the windup bit packed in
--              the code); the older { BattleId, T, Units } form (the tools' drivers) is taken as it is.
--   "Events"   BattleSim events (Hit, Special, KO, Telegraph, Spawn, Enrage, Order, Zone, Leave, End, Element, Dash,
--              Buff, Swap, Windup, Wave, EnemiesDown, Speed); a rejected Order reaches only its owner (the shake).
--   "End"      { BattleId, Mode, Result, Rewards, Outcome, Won, Spectator, Reason } (Rewards.Dungeon = true + Extra in
--              the dungeon: no result card for a cleared room, DungeonController shows the loot)
--
-- Drawing (kept from Phases 3-4; the Phase 5 lines marked *)
--   * Snapshots are buffered and drawn INTERP_DELAY seconds behind the estimated server clock; events are queued with
--     their arrival time and played on that delayed clock (lunges, numbers and telegraph impacts line up).
--   * Pets hover over the floor, face their target or path, bob, flap, lunge / shoot bolts, hop on a Pounce; static
--     parts welded to the anchored root once per build (a pose is one root CFrame write); raid boss poses; telegraphs
--     that fill until the dodge deadline then flash; hit flashes, pooled world damage numbers (never screen-centre),
--     KO poofs, special VFX; a PetCard above every pet unit (Phase 4, with the fighter's lives pips *).
--   * Pet attack VFX (docs/superpowers/specs/2026-10-23-pet-attack-vfx-design.md, section "Atk"): every Hit / Special /
--     Element / KO / Buff / Swap event and the winners' cheer play client/Controllers/AttackFx FIRST; the cube Fx.* of
--     each handler is the fallback when AttackFx.Play returns false (Low budget, a missing texture, an error). They play
--     when the event ARRIVES with DueAt = the time it plays on the render clock (the INTERP_DELAY lead is the charge
--     beat; the impact lands with the damage number; a ranged pet's shot keeps AttackFx's MinTravel of flight, so when
--     the lead is short its Hit, and the victim's later Hit / KO and the End, play up to FX_LATE_MAX later: Net.Hold /
--     Net.Queue, player note 1). AttackFx's poses (PetBuilder.Animate opts.Pose + the body offset
--     PetBuilder.PoseBody x the build scale on the root write) replace the old lunge / recoil, the wind-up crouch (now
--     PetPoses' Windup held while the snapshot says Winding) and the hurt nudge for the units it drives; between attacks
--     those units breathe and glance (PetPoses IdleBattle, out of step per unit; not on Low, not while my fighter moves
--     under my input; posed every other frame like a strided pet); a KO'd pet tumbles and lies (KO_PARK_FX) before it
--     is parked (its Ko plays on arrival: only a pet drawn down and up again, or a KO no snapshot confirms within
--     KO_CONFIRM, drops it). The sim's End starts no new
--     effect and lets the live ones finish for FX_END_GRACE (1 s: the killing blow lands), then AttackFx.ClearAll (the
--     winners' Victory waits for it); a Leave ends the leavers' own effects at once (AttackFx.Cancel), every teardown
--     clears at once. Camera punch -> Me.Shake (own pets),
--     the Secret screen-edge glow / a signature's dim -> Me.ScreenFx. GraphicsQuality drives AttackFx.SetQuality.
--   * (Task 11b, the Special pre-charge, player option C; no server change) MY SPECIAL press predicts its charge at once
--     when my view says it can go (Atk.PreCharge -> AttackFx.Precharge: glow + motes, rim, inhale, Cast pose); its Special
--     event takes it over (backdated to the press, the impact still on its DueAt); a rejected Order or PRESS_WAIT (0.7 s)
--     without the event shatters it (shards, Recoil, SoundFx "Shatter"). Every other Special (bots, NPCs, allies, enemies,
--     my pet with no press) gets its charge back: its impact lands up to LATE_MAX (0.35 s) after its event, and that
--     special's own hits / Storm ticks due before the impact, the KOs they cause (Net.SpecialHold) and their units' drawn
--     HP (Units.Hold) wait for it; a caster KO'd in its own late charge falls LAST_GASP after its impact. Other hits play
--     on time; the End is not held. The inhale = SoundFx "Inhale" (Me.Inhale), its pitch rising to the release.
--   * Music (client/SoundFx layers): my fight sets the "Battle" layer (Net.Music: at Start, End and Cleanup; a won
--     Champion Ring round keeps it until the next round; a dungeon room keeps the Dungeon track, its boss room plays
--     Battle); a won fight's result plays SoundFx "Reward" with the winners' cheer.
--   * The player's CHARACTER is the fighter's body (B1): my fighter (High) is drawn at the shoulder offset (1.8, 0.5,
--     0.6) of the SERVER fighter position, blended toward the character root while the two are within 2 studs and
--     following the server position beyond (lerp 0.35 per 60 Hz frame), so what looks in reach is in reach. My two
--     helpers (Low) hover behind me at (-2, 1.2, 2) / (2, 1.2, 2), fly to the fighter on a Buff (0.6 s) and trade
--     places with it on a Swap (0.5 s). Other players' helpers are not drawn (~1 unit per player in a 16-raid).
--   * Enemies wind up visibly: Winding plays a crouch + a brief yellow Highlight (the dash cue), their list row flashes
--     "!"; "DODGED!" (cyan) on Hit.miss; buff names float above the fighter in the buff's colour; element attacks draw
--     their cone / circle / line; camera shakes x ClientSettings.Get("Shake") (Humanoid.CameraOffset, tiny, rare).
--   * Wave 5 dungeon camera (bugs #15 / #26): the shake rides on the resting CameraOffset (DungeonController's dungeon
--     shoulder) and gives it back; in a dungeon every hit on my fighter shakes lightly (HIT_SHAKE_LIGHT) and an AttackFx
--     punch >= PUNCH_BIG also punches the FOV (MovementController.FovPunch, FOV_PUNCH 6 degrees x min(1, amount / 0.4));
--     the Shake setting turns off only the shakes (player ruling 2026-10-28: the FOV punch plays regardless). A cleared
--     dungeon room's floor goes after DUNGEON_LINGER 1 s; BattleController.FighterDrawn(userId) says whether a player's
--     dungeon fighter is still drawn (a lost room's KO'd models linger; the followers wait for it); my fighter's first
--     drawn spot is its follower's (PetController), and BattleController.LastDrawn(userId) -> pos, key tells
--     PetController where each player's fighter was drawn last (the followers walk back from there).
--
-- * The battle HUD (only while the local player fights; ScreenGui "NimbusBattle", designed in 1080p px under one
--   UIScale of Theme.ScreenFactor(), NeonKit cards, fonts via Theme roles, nothing in the screen centre):
--   * Team (top left): the FIGHTER card: name (Heading 26) + "Lv 34" pill + element badge + stars; HP 320 x 22 green
--     with a red loss trail draining 0.4 s behind (TweenService; HP written only on change); ENERGY 320 x 14 blue
--     ("ENERGY 72/100", gold at 100); 3 hearts = lives. Under it the two HELPER portraits (a round PetBuilder Low
--     picture in a ViewportFrame built once, a stroke in the pet's element colour) with "Lv n", the buff cooldown
--     ring (a two-half-disc UIGradient pie, written at 10 Hz), the buff name ("HEAL", "STONE SKIN") and the SWAP chip;
--     KO greys the portrait. Tap a portrait / key 1 / 2 = its buff, hold 0.5 s = swap.
--   * Enemies (right): one 300 x 44 row per living enemy (max 8 + "+n more"): icon disc, name, element stripe, red HP
--     bar; the LOCKED row first with a gold bracket + "TARGET"; a winding enemy's icon flashes "!"; rows reorder only
--     on a KO / a spawn / a lock change.
--   * TopCard (top centre, under the Roblox bar): the mode line "CHAMPION RING - Round 8 - Best 12", "DUNGEON - Floor
--     3 - Room 2" (purple), "DUEL - vs Sam", "BOSS RAID" + the timer; the boss bar (raid boss / dungeon mini-boss) with
--     its element / ENRAGED / minions / players / wave pills; the ring's pay pills.
--   * Commands (bottom right): ATTACK (88), ELEMENT, SPECIAL, DASH (64) round buttons with cooldown rings (SPECIAL =
--     the energy, gold at 100) and key chips on desktop; captions under them on wide screens.
--   * Compact layout (touch, or a screen under 900 x 600 px): a smaller fighter card, the portraits in a column, the
--     enemy list 2 rows, the mode line under the list when the top is full, the cluster a 2 x 2 grid above the jump /
--     RUN buttons (portrait) or left of the jump button (landscape); the menu column hides while fighting.
--   * LEAVE (Champion Ring only; two presses -> "Forfeit"), the ring's next-round side card, the result card (bottom
--     right; top right on phones) with "Lives left" and the dungeon's lines.
-- * Prediction: a press starts its button's ring at once and records St.pending; the matching event within 0.6 s
--   confirms it, a rejected Order (owner-only) or the timeout puts the ring back and shakes the button. HP, numbers,
--   kills and the meter are never predicted. Late joiners get their cooldowns from Start.Team.Cooldowns.
-- * MovementController (3.9 / 4.4, dungeon fixes 5): on Start SetPetDash(fn) (Shift / B = the PET's dash: "Dash" only,
--   no character impulse, no stamina; RUN on Ctrl) and SetBattleSpeed(walk, run) (again on every Speed event); both
--   reset on End.
-- * Dungeon fixes (docs/dungeon-fixes/plan.md): enemies spawned after "Start" come in Wave / Spawn events and are
--   added there (root cause A); an enemy whose info says Arrive > 0 arrives with EvolutionFx.Arrive (the model hidden
--   until the flash, then a hop); the fighter attacks by itself (server): ATTACK sends one "Attack" order per press
--   (the enemy clicked / under the screen centre while MouseLock holds the cursor, else nil = the nearest / the next),
--   no hold repeat, no predicted swing (lunges from the server's Hits); the gold arrow shows the enemy the pet attacks
--   (the lock, else its snapshot target, see-through); Dash events draw the pet's dash (mine on arrival); ELEMENT's E
--   passes to a shown ProximityPrompt; MouseLock.Hold / Release ("BattleResult", "BattleLeave") via a pcall'd require.
-- * Bugs #16 / #22 (wave 5): a tap of F / X / ATTACK = Attack() at once (the server KEEPS a live lock in EngageRange:
--   no re-target); HOLD it ATTACK_HOLD (0.4 s) = the next target (Input.CycleTarget -> Target(id), Tab / RT's path; the
--   caption flashes NEXT for NEXT_FLASH); a world click stays one Attack(pick) (holding the mouse never cycles). The
--   server's engage rule walks my pet off to fight while I stand: the shoulder offset fades with the blend share (an
--   engaged pet is drawn where the server has it) and its Engage { on = true } plays the arrival hop.
-- Keys (ContextActionService, High priority, sunk, bound ONLY while fighting and inert before UiGate.HasPlayed()):
-- F / X attack (hold = the next target), E / Y element (E passes while a prompt is shown), Q / RB special, Tab / T / RT / LT
-- lock, 1 / 2 (LB / D-up) buff (hold = swap), D-left / D-right swap; the item hotbar keeps 1-4 outside battles.
--
-- Cost: one RenderStepped connection, alive only while a battle is drawn or effects play. Per frame: one root CFrame
-- write per pet + PetBuilder.Animate per visible pet (strided for far / crowded ones; a strided frame moves the
-- animated parts with the root in one BulkMoveTo), one BossBuilder.Animate, the pooled
-- effects (+ AttackFx.Update(now): AttackFx has no frame loop of its own), HUD writes only when a shown value
-- changes, the rings at 10 Hz. GetStats() reports the measured ms.
-- Plain Lua 5.1-compatible syntax only. Every font comes from a Theme role. No asset ids.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))

local Client = script.Parent.Parent

-- optional modules (a build without one still draws what it can)
local function optional(parent, name, waitSeconds)
	if not parent then
		return nil
	end
	local inst = parent:FindFirstChild(name)
	if not inst and waitSeconds then
		inst = parent:WaitForChild(name, waitSeconds)
	end
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	if ok and type(result) == "table" then
		return result
	end
	warn("[BattleController] " .. name .. " failed to load: " .. tostring(result))
	return nil
end

local PetBuilder = optional(Shared, "PetBuilder", 5)
local PetCatalog = optional(Shared, "PetCatalog", 5)
local PetKeys = optional(Shared, "PetKeys")
local BattleCatalog = optional(Shared, "BattleCatalog")
local BattleSim = optional(Shared, "BattleSim") -- constants only (States / Events); the client never simulates
local BossBuilder = nil -- loaded on the first raid (lazyBoss)
-- Phase 4 (optional too): the shared pet card (every unit's card), the local profile mirror (own pets' level / XP
-- after a fight), the XP curve and the voxel kit (the champion's crown)
local Mods = {
	PetCard = optional(Client:FindFirstChild("UI") or Client:WaitForChild("UI", 10), "PetCard", 5),
	NeonKit = optional(Client:FindFirstChild("UI") or Client:WaitForChild("UI", 10), "NeonKit", 5), -- Phase 5: the HUD's kit
	Movement = nil, -- MovementController (lazy: Hud.Movement)
	UiGate = nil, -- client/UiGate (lazy: Input.GateOpen)
	Settings = nil, -- client/ClientSettings (lazy: Me.ShakeScale)
	State = optional(Client, "State", 5),
	Tycoon = optional(Shared, "TycoonCatalog"),
	Voxel = optional(Shared, "Voxel"),
	Mesh = nil, -- shared/MeshLibrary (lazy: Units.FxMesh); false = unavailable
	Evo = nil, -- client/Controllers/EvolutionFx (lazy: Units.EvoFx, the enemies' arrival)
	MouseLock = nil, -- client/MouseLock (lazy, optional: Me.MouseHold); false = not there (yet)
	AttackFx = nil, -- client/Controllers/AttackFx (lazy: Atk.Mod); false = unavailable (the cube Fx.* draw everything)
	FxCat = nil, -- shared/AttackFxCatalog (lazy: Atk.Look)
	Gfx = nil, -- client/GraphicsQuality (lazy: Atk.SyncQuality)
	Sound = nil, -- client/SoundFx (lazy: Me.Sound: the charge's inhale / shatter, the Battle music layer, Reward); false = unavailable
	Cheer = nil, -- wave 6: client/Controllers/TrainerCheer (lazy: Cheer.Mod); false = unavailable
	HudCtl = nil, -- wave 6: client/Controllers/HudController (lazy: CheerUp.Layout, the vitals card's rect); false = unavailable
}

local BattleController = {}
-- test hooks (smoke tests only): Gate() -> bool replaces UiGate.HasPlayed, Shake() -> bool replaces the Shake setting
BattleController.Hooks = {}

local LocalPlayer = Players.LocalPlayer
local sin, cos, sqrt, abs, floor, max, min, exp, pi = math.sin, math.cos, math.sqrt, math.abs, math.floor, math.max, math.min, math.exp, math.pi
local atan2 = math.atan2 or function(y, x)
	return math.atan(y, x)
end
local TAU = pi * 2

----------------------------------------------------------------------
-- Tuning
----------------------------------------------------------------------
local K = {
	GUI_NAME = "NimbusBattle",
	DISPLAY_ORDER = 12, -- above the HUD (10) and the hotbar (11), below windows (20) and toasts (30)
	FOLDER = "ClientBattle", -- workspace folder of the drawn battles
	INTERP_DELAY = 0.12, -- seconds behind the server clock (snapshots arrive every 0.1 s)
	INTERP_DELAY_SPECTATOR = 0.25, -- spectators get snapshots at 5 Hz (BattleService), so they draw further behind
	-- telegraph deadline: the fill completes when a RETREAT pressed now still reaches the server TELE_RUNOUT seconds
	-- before the hit (the pets need that long to run out: sim_battle "dodge", a 2.2 s telegraph escaped ~90% with a
	-- RETREAT 1.2-1.4 s after the warning); after that the shape flashes until the impact
	TELE_RUNOUT = 0.8,
	TELE_MIN_FILL = 0.5, -- seconds: the fill never gets shorter than this (a very slow connection)
	PING_DEFAULT = 0.1, -- round trip assumed when Player:GetNetworkPing is unavailable
	PING_MAX = 0.5,
	THREAT_PAD = 1.5, -- studs around a pet's centre that count as "in the shape" for the RETREAT! cue
	OFFSET_RATE = 0.1, -- clock offset filter
	MAX_SNAPS = 8,
	PET_SCALE = 1.3, -- battle pets are a little bigger than followers, so they read from the stands
	HOVER = 0.55, -- studs between the floor and a pet's lowest point
	BOB = 0.18,
	FACE_RATE = 10,
	LUNGE_TIME = 0.26,
	LUNGE_DIST = 1.5,
	RECOIL_DIST = 0.35,
	HOP_TIME = 0.4,
	HOP_HEIGHT = 2.6,
	KO_PARK = 0.3, -- seconds after a KO before the downed pet is parked (the poof covers it)
	KO_PARK_FX = 1.6, -- with AttackFx's Ko: the pet tumbles onto its side (KO_TIME) and lies a moment before it is parked
	KO_TIME = 0.9, -- PetPoses Ko (AttackFx K.KO): the tumble, then the pose holds
	KO_CONFIRM = 1.0, -- a played Ko whose pet no snapshot draws down within this long is dropped (no KO after all)
	FX_LEAD_MAX = 0.45, -- seconds an effect may start before its event plays (the render delay: the charge beat)
	-- (Task 11b, the Special pre-charge, player option C) a press predicts the charge; every other Special lands late
	PRESS_WAIT = 0.7, -- a pressed SPECIAL's predicted charge waits this long for its Special event, then shatters
	LATE_MAX = 0.35, -- a Special nobody here pressed: up to this much charge is given back, its impact (and its hits) that late
	LAST_GASP = 0.05, -- a caster KO'd in its own late charge falls this long after the impact
	HOLD_EPS = 0.02, -- (fix round 1, I1) a late Special's hit ends its victim's hold only this close to the hold's end
	UNBENCH_SLACK = 0.25, -- (fix round 2, I2-b) a held auto-swap's incoming pet stays benched until its Swap plays; this
	--                       long past the hold it unbenches anyway (a Swap that never plays never hides a pet for good)
	INHALE_PITCH = { 0.75, 1.35 }, -- the inhale (SoundFx "Inhale") rises from / to this PlaybackSpeed under the charge
	INHALE_IN = 0.08, -- seconds the inhale fades in ...
	INHALE_OUT = 0.12, -- ... and out at the release (or when hushed)
	INHALE_OTHERS = 0.4, -- volume x for others' pets' inhales
	INHALE_MAX = 2, -- inhales at once (a crowded raid: the rest charge silently)
	FX_COVER = 1.6, -- seconds after a played Special / Element during which its targets' hits are AttackFx's (Hurt pose)
	WINDUP_HOLD = 0.6, -- PetPoses Windup is held at this p while Winding (its crouch is full from p 0.5 to 0.82) ...
	WINDUP_IN = 0.25, -- ... reached in this many seconds
	IDLE_PHASE = 2.2, -- the battle idle's per-unit time offset = u.phase (0..2 pi) x this (pets breathe out of step)
	FX_END_GRACE = 1.0, -- after the sim's End: no new AttackFx effect; the live ones finish for at most this long
	FX_LATE_MAX = 0.3, -- seconds a ranged shot's Hit (and the victim's later events) may play after their time: the
	--                    shot's flight is never cut below AttackFx's MinTravel (player note 1)
	RIPPLE_TICK_GAP = 0.75, -- (Task 10 re-review M8) a zone / burn tick's shield ripple waits this long after the unit's
	--                    last ripple: every other 0.5 s zone tick (the cube path's 50 % zone flash, made deterministic)
	-- (Task 11) a signature's battle dim (Eclipse Nova, own pet): LightingStack preset DIM_ID, in over DIM_IN, out over
	-- DIM_OUT once its seconds are up, at once (DIM_CUT) when the battle is torn down
	DIM_ID = "AttackFxDim",
	DIM_IN = 0.15,
	DIM_OUT = 0.3,
	DIM_CUT = 0,
	DIM_MAX = 2.5, -- seconds a dim can be asked for (a bad hook argument never leaves the battle dark)
	BUILD_BUDGET = 0.006, -- seconds of model building per frame (the first build of a frame always runs)
	BUILD_MAX = 4,
	CROWD = 14, -- more units than this: other players' / enemy pets are drawn every other frame
	ANIM_MID = 90, -- studs from the camera: beyond this, other players' / enemy pets are drawn every 3rd frame ...
	ANIM_FAR = 160, -- ... and beyond this every 4th (a whole pet at once: root + wings, so nothing comes apart)
	MAX_FX_PARTS = 260,
	POOL_KEEP = 160,
	MAX_NUMBERS = 26,
	MAX_FLASHES = 8,
	FLASH_TIME = 0.2,
	NUMBER_TIME = 0.95,
	NUMBER_RISE = 2.6,
	NUMBER_PX = 26, -- 1080p pixel size of a damage number (World text rule: >= 22)
	CRIT_PX = 32,
	CALLOUT_PX = 26,
	NUMBER_DISTANCE = 170,
	BAR_DISTANCE = 140,
	END_LINGER = 3.5, -- seconds the floor stays drawn after the end
	DUNGEON_LINGER = 1.0, -- wave 5 (bug #26): a cleared dungeon room's floor goes after this (= PetController.HANDOVER)
	HIT_SHAKE_LIGHT = { 0.07, 0.12 }, -- wave 5 (bug #15): every hit on my fighter in a dungeon (amount, seconds)
	FOV_PUNCH = 6, -- wave 5 (bug #15): degrees of FOV punch on a big attack in a dungeon (AttackFx punch >= PUNCH_BIG)
	FOV_PUNCH_TIME = 0.25,
	PUNCH_BIG = 0.2,
	LAST_DRAWN_AGE = 5, -- seconds a dungeon fighter's last drawn spot is kept for the followers' hand-over
	SPECTATOR_LINGER = 1.5,
	RESULT_SECONDS = 12,
	CMD_GAP = 0.25, -- local throttle between two commands of a kind
	TAP_TIME = 0.35,
	TAP_MOVE = 14, -- px
	TAP_REACH = 64, -- px (1080p, scaled) around an enemy's centre on the screen
	ACTION_ATTACK = "NimbusBattleAttack",
	ACTION_ELEMENT = "NimbusBattleElement",
	ACTION_SPECIAL = "NimbusBattleSpecial",
	ACTION_TARGET = "NimbusBattleTarget",
	ACTION_HELPER = "NimbusBattleHelper",
	ATTACK_GAP = 0.2, -- local throttle of ATTACK (the hold repeats at the fighter's interval)
	CD_SLACK = 0.15, -- a press this close to the end of a cooldown is sent (the server's clock decides)
	PENDING_TIMEOUT = 0.6, -- seconds a prediction waits for its event
	SWAP_HOLD = 0.5, -- hold a helper key / portrait this long = swap
	ATTACK_HOLD = 0.4, -- bug #16: hold F / X / ATTACK this long = the next target (a tap attacks at once)
	NEXT_FLASH = 0.6, -- the ATTACK caption reads NEXT this long after a hold-cycle
	RING_DT = 0.1, -- the rings / countdowns are written at 10 Hz
	LOSS_TIME = 0.4, -- the red HP loss trail drains this long behind a loss
	-- the drawn fighter / helpers (B1, 4.7)
	SHOULDER = Vector3.new(1.8, 0.5, 0.6), -- the fighter's offset from the character (right, up, back)
	BLEND_DIST = 2, -- within this many studs the drawn fighter blends toward the character root
	FOLLOW_LERP = 0.35, -- per 60 Hz frame toward the server position beyond BLEND_DIST
	HELPER_A = Vector3.new(-2, 1.2, 2),
	HELPER_B = Vector3.new(2, 1.2, 2),
	BUFF_FLY = 0.6, -- a helper flies to the fighter and back on its Buff
	SWAP_TIME = 0.5, -- fighter and helper trade places
	DASH_TIME = 0.35, -- the drawn PET dash (dungeon fixes decision 5): out and back along the Dash event's direction
	DASH_DIST = 4.5, -- studs
	WINDUP_FLASH = 0.35, -- the yellow Highlight of a wind-up
	SHAKE_MAX = 0.35, -- studs of camera shake at most (x ClientSettings Shake)
	-- HUD geometry (design px at 1080p)
	COMPACT_W = 900, -- screen px: narrower (or touch) = the compact phone layout
	COMPACT_H = 600,
	EDGE = 12,
	PAD = 10,
	FC_W = 352, -- the fighter card (bars 320)
	FC_H = 130,
	FC_W_COMPACT = 252, -- (bars 232)
	PORTRAIT = 64,
	PORTRAIT_COMPACT = 48,
	RING = 74,
	HELPER_W = 122,
	HELPER_W_COMPACT = 150,
	ROW_W = 300,
	ROW_H = 44,
	ROW_W_COMPACT = 210,
	ROW_H_COMPACT = 40,
	ROW_GAP = 6,
	ROWS_MAX = 8,
	ROWS_COMPACT = 2,
	TOP_W = 470,
	TOP_W_COMPACT = 300,
	MODE_H = 40,
	ATTACK_D = 88,
	ACTION_D = 64,
	MIN_TEXT_PX = 14, -- no HUD text is ever drawn smaller on the screen (Readability rule)
	RESULT_W = 440,
	-- LEAVE (Ring only): the first press arms it for LEAVE_CONFIRM seconds, the second sends "Forfeit"
	LEAVE_CONFIRM = 3,
	LEAVE_W = 150,
	LEAVE_H = 52,
	LEAVE_W_COMPACT = 150,
	LEAVE_W_TOP = 100, -- a landscape phone: right of the mode card
	LEAVE_H_COMPACT = 46,
	LEAVE_CARD_W = 230,
	-- wave 6: Cheer up! (Raid / Dungeon), right above the vitals card
	CHEER_W = 150,
	CHEER_H = 44,
	CHEER_GAP_PX = 8, -- screen px between the button's bottom and the vitals card's top
	CHEER_TOUCH_PX = 46, -- a touch screen: the button is at least this tall (screen px; the 44 px tap rule)
	CHEER_TOUCH_W_PX = 112,
	CHEER_CENTRE_TOL = 0.15, -- the screen middle it never enters (HudController's CENTRE_TOL 0.145 + a margin)
}

local STATES = (BattleSim and BattleSim.States) or { Idle = 0, Moving = 1, Attacking = 2, Benched = 3, Casting = 4, Down = 5, Stunned = 6, Dashing = 7 }
local S_DOWN, S_STUNNED, S_CASTING, S_ATTACKING = STATES.Down, STATES.Stunned, STATES.Casting, STATES.Attacking
local S_BENCHED, S_DASHING, S_MOVING = STATES.Benched or 3, STATES.Dashing or 7, STATES.Moving or 1
local EV = (BattleSim and BattleSim.Events) or {
	Hit = "Hit", Special = "Special", KO = "KO", Telegraph = "Telegraph", Spawn = "Spawn", Enrage = "Enrage",
	Order = "Order", Zone = "Zone", Leave = "Leave", End = "End",
}

local METER_MAX = tonumber(BattleCatalog and type(BattleCatalog.Fighter) == "table" and BattleCatalog.Fighter.SpecialMeterMax) or 100
local SPECIALS = (BattleCatalog and BattleCatalog.Specials) or {}

local COLORS = {
	Mine = Theme.Colors.Health,
	Ally = Color3.fromRGB(98, 172, 232),
	Enemy = Color3.fromRGB(236, 88, 100),
	Gold = Theme.Colors.Gold or Color3.fromRGB(244, 196, 78),
	Heal = Color3.fromRGB(120, 230, 140),
	Shield = Color3.fromRGB(150, 210, 255),
	Ice = Color3.fromRGB(170, 228, 255),
	Weak = Color3.fromRGB(176, 190, 214),
	Strong = Color3.fromRGB(255, 150, 70),
	White = Color3.fromRGB(255, 255, 255),
	Ink = Theme.Colors.TextStroke or Color3.fromRGB(16, 22, 50),
	Panel = Theme.Colors.Panel,
	PanelLight = Theme.Colors.PanelLight,
	Navy = Theme.Colors.Navy or Color3.fromRGB(24, 34, 78),
	Muted = Theme.Colors.Muted or Color3.fromRGB(212, 224, 246),
	Track = Color3.fromRGB(28, 36, 76),
	Storm = Color3.fromRGB(72, 78, 108),
	LateRim = Color3.fromRGB(255, 70, 60), -- a telegraph past its dodge deadline flashes in this
	Wait = Color3.fromRGB(150, 132, 84), -- a SPECIAL with a full meter that waits for ATTACK
	StormLight = Color3.fromRGB(112, 118, 150),
	-- Phase 5 HUD (the Neon kit colours)
	HpGreen = Theme.Neon and Theme.Neon.Green or Color3.fromRGB(72, 224, 120),
	Loss = Color3.fromRGB(236, 60, 72),
	Energy = Theme.Neon and Theme.Neon.Blue or Color3.fromRGB(64, 170, 255),
	EnergyText = Color3.fromRGB(150, 206, 255),
	Life = Color3.fromRGB(255, 86, 112),
	LifeLost = Color3.fromRGB(70, 76, 108),
	LevelPill = Color3.fromRGB(44, 60, 120),
	SwapEdge = Theme.Neon and Theme.Neon.Cyan or Color3.fromRGB(64, 226, 236),
	Alert = Color3.fromRGB(255, 226, 90),
	Dodge = Color3.fromRGB(110, 236, 255),
	Windup = Color3.fromRGB(255, 220, 60),
	Action = {
		Attack = Theme.Neon and Theme.Neon.Red or Color3.fromRGB(255, 76, 100),
		Element = Theme.Neon and Theme.Neon.Blue or Color3.fromRGB(64, 170, 255),
		Special = Theme.Neon and Theme.Neon.Gold or Color3.fromRGB(255, 196, 64),
		Dash = Theme.Neon and Theme.Neon.Cyan or Color3.fromRGB(64, 226, 236),
	},
}

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local St = {
	initialized = false,
	battle = nil, -- the drawn battle (see newBattle)
	old = {}, -- battles that ended and still fade out: { battle, until }
	conns = {}, -- long-lived connections
	loop = nil, -- RenderStepped connection (only while needed)
	folder = nil, -- workspace.ClientBattle
	fxFolder = nil,
	pool = {}, -- free effect parts
	fxLive = 0,
	effects = {}, -- live effects
	numbers = {}, -- live numbers
	numberPool = {},
	flashes = {}, -- live flashes
	flashPool = {},
	lastCmd = {}, -- [action .. arg] = os.clock()
	bound = false, -- ContextActionService bindings active
	gamepad = false, -- the last input was a gamepad
	tap = nil, -- { pos, t } a press that may become a tap
	frameNo = 0,
	fxFrame = 0, -- (fix round 2, M8) the frameNo of the last frame whose loop reached Atk.Update (equal at rest: no frame failed)
	perf = { frames = 0, total = 0, peak = 0, last = 0, builds = 0, split = {} },
	warned = {},
	remoteCmd = nil,
	result = nil, -- result card timer
	prompts = {}, -- [ProximityPrompt] = true while shown to me (E passes through to it: Input.PromptShown)
	mouseHolds = {}, -- [reason] = true: our client/MouseLock holds (the cursor is free)
	holds = {}, -- [key] = { index, t, fired }: a helper key / portrait held (0.5 s = swap)
	movementOn = false, -- MovementController's battle switches are set
	shake = nil, -- { t0, dur, amp, base, last, hum } camera shake (base = the resting CameraOffset, e.g. the dungeon shoulder)
	lastDrawn = {}, -- wave 5 (bug #26): [userId] = { Pos, Key, At } where a dungeon fighter was drawn last (Net.Cleanup)
	dim = nil, -- (Task 11) { t0, dur, token, unit } a signature's battle dim (LightingStack K.DIM_ID pushed)
	pre = nil, -- (Task 11b) { B, unit, t0, untilT } my pressed SPECIAL's predicted charge, waiting for its event
	inhales = {}, -- (Task 11b) token -> { sound, t0, dur, vol } the charges' inhale sounds
	musicOn = nil, -- SoundFx's "Battle" layer as Net.Music last set it
	starting = nil, -- true while Net.Start cleans the battle before (Net.Cleanup leaves the music to Net.Start)
}

local Hud = {} -- the battle HUD (built once, lazily)
local Fx = {} -- pooled effects
local Units = {} -- battle units
local Tele = {} -- telegraphs and zones
local Input = {} -- keys, gamepad, taps
local Net = {} -- messages
local Cards = {} -- Phase 4: the PetCard above every battle unit
local Ring = {} -- Phase 4: the Champion Ring HUD (round / record / next-round side card / run card)
local Leave = {} -- LEAVE (two presses -> BattleCommand "Forfeit"): Champion Ring runs only
local CheerUp = {} -- wave 6: the Cheer up! button (BattleCommand "Cheer"): Raid / Dungeon fighters only
local Me = {} -- Phase 5: my fighter at the character's shoulder, my helpers behind me, the camera shake
local Atk = {} -- pet attack VFX: client/Controllers/AttackFx first (the cube Fx.* as the fallback) + the battle poses

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function clamp(x, lo, hi)
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

local function warnOnce(key, message)
	if St.warned[key] then
		return
	end
	St.warned[key] = true
	warn("[BattleController] " .. tostring(message))
end

local function num(v, default)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	return v
end

local function wrapAngle(a)
	return (a + pi) % TAU - pi
end

local function elementColor(element)
	local info = Config.Elements and Config.Elements.Info and Config.Elements.Info[element]
	if info and typeof(info.Color) == "Color3" then
		return info.Color
	end
	return Color3.fromRGB(170, 180, 200)
end

local function myUserId()
	return LocalPlayer and LocalPlayer.UserId or 0
end

-- seconds the drawing runs behind the estimated server clock (spectators get 5 Hz snapshots)
local function interpDelay(B)
	return (B and B.Spectator) and K.INTERP_DELAY_SPECTATOR or K.INTERP_DELAY
end

-- the round trip to the server in seconds (Player:GetNetworkPing), clamped; a default when unavailable
local function networkPing()
	local ok, v = pcall(function()
		return LocalPlayer:GetNetworkPing()
	end)
	if ok and type(v) == "number" and v == v and v >= 0 then
		return clamp(v, 0, K.PING_MAX)
	end
	return K.PING_DEFAULT
end

local function make(className, props, parent)
	local inst = Instance.new(className)
	if props then
		for key, value in pairs(props) do
			inst[key] = value
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function fmtTime(seconds)
	seconds = max(0, floor(seconds + 0.5))
	return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end

local function lazyBoss()
	if BossBuilder == nil then
		BossBuilder = optional(Shared, "BossBuilder") or false
	end
	return BossBuilder or nil
end

local function battleFolder()
	if St.folder and St.folder.Parent == workspace then
		return St.folder
	end
	local f = workspace:FindFirstChild(K.FOLDER)
	if not f then
		f = make("Folder", { Name = K.FOLDER }, workspace)
	end
	St.folder = f
	return f
end

local function fxFolder()
	if St.fxFolder and St.fxFolder.Parent then
		return St.fxFolder
	end
	St.fxFolder = make("Folder", { Name = "Fx" }, battleFolder())
	return St.fxFolder
end

----------------------------------------------------------------------
-- Effects: pooled voxel parts
----------------------------------------------------------------------
function Fx.Part(color, material, transparency)
	local p = table.remove(St.pool)
	if not p then
		if St.fxLive >= K.MAX_FX_PARTS then
			return nil
		end
		p = make("Part", {
			Name = "BattleFx",
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Massless = true,
			TopSurface = Enum.SurfaceType.Smooth,
			BottomSurface = Enum.SurfaceType.Smooth,
		})
	end
	St.fxLive = St.fxLive + 1
	p.Shape = Enum.PartType.Block
	p.Material = material or Enum.Material.Neon
	p.Color = color or COLORS.White
	p.Transparency = transparency or 0
	p.Parent = fxFolder()
	return p
end

function Fx.Free(p)
	if not p then
		return
	end
	St.fxLive = max(0, St.fxLive - 1)
	if #St.pool < K.POOL_KEEP then
		p.Parent = nil
		St.pool[#St.pool + 1] = p
	else
		p:Destroy()
	end
end

-- registers a live effect: update(e, p, now) -> nothing; e.parts are freed when it ends
function Fx.Add(dur, update, parts, data)
	local e = data or {}
	e.t0 = os.clock()
	e.dur = dur
	e.update = update
	e.parts = parts or {}
	St.effects[#St.effects + 1] = e
	BattleController._wake()
	return e
end

local function burstUpdate(e, p)
	local t = p * e.dur
	local g = e.gravity
	local fade = p * p
	for i, part in ipairs(e.parts) do
		local v = e.vel[i]
		local x = e.ox + v[1] * t
		local y = e.oy + v[2] * t - 0.5 * g * t * t
		local z = e.oz + v[3] * t
		local a = v[4] * t
		local c, s = cos(a), sin(a)
		part.CFrame = CFrame.new(x, y, z, c, 0, s, 0, 1, 0, -s, 0, c)
		local size = e.size * (1 - 0.7 * p)
		part.Size = Vector3.new(size, size, size)
		part.Transparency = e.alpha + (1 - e.alpha) * fade
	end
end

-- a burst of voxel cubes flying out of `pos`
function Fx.Burst(pos, color, count, speed, size, dur, opts)
	opts = opts or {}
	local parts, vel = {}, {}
	local rnd = math.random
	for i = 1, count do
		local c = color
		if opts.color2 and i % 2 == 0 then
			c = opts.color2
		end
		local part = Fx.Part(c, opts.material, opts.alpha or 0)
		if not part then
			break
		end
		local a = rnd() * TAU
		local up = (opts.up or 0.6) + rnd() * 0.6
		local sp = speed * (0.55 + rnd() * 0.6)
		parts[#parts + 1] = part
		vel[#vel + 1] = { cos(a) * sp, up * sp, sin(a) * sp, (rnd() - 0.5) * 12 }
		part.Size = Vector3.new(size, size, size)
		part.CFrame = CFrame.new(pos)
	end
	if #parts == 0 then
		return nil
	end
	return Fx.Add(dur, burstUpdate, parts, {
		ox = pos.X, oy = pos.Y, oz = pos.Z, vel = vel, size = size, gravity = opts.gravity or 18, alpha = opts.alpha or 0,
	})
end

local function ringUpdate(e, p)
	local r = e.r * (0.25 + 0.75 * (1 - (1 - p) * (1 - p)))
	local n = #e.parts
	for i, part in ipairs(e.parts) do
		local a = (i / n) * TAU + e.spin * p
		part.CFrame = CFrame.new(e.ox + cos(a) * r, e.oy + 0.3 + 0.6 * p, e.oz + sin(a) * r)
		part.Transparency = e.alpha + (1 - e.alpha) * p
	end
end

-- a ring of cubes that expands from `pos` to radius r (shock waves)
function Fx.Ring(pos, r, color, count, size, dur, alpha)
	local parts = {}
	for _ = 1, count do
		local part = Fx.Part(color, Enum.Material.Neon, alpha or 0.1)
		if not part then
			break
		end
		part.Size = Vector3.new(size, size * 0.6, size)
		parts[#parts + 1] = part
	end
	if #parts == 0 then
		return nil
	end
	return Fx.Add(dur, ringUpdate, parts, { ox = pos.X, oy = pos.Y, oz = pos.Z, r = r, spin = 0.6, alpha = alpha or 0.1 })
end

local function riseUpdate(e, p)
	local t = p * e.dur
	for i, part in ipairs(e.parts) do
		local v = e.vel[i]
		part.CFrame = CFrame.new(e.ox + v[1], e.oy + v[2] * t, e.oz + v[3])
		part.Transparency = 0.1 + 0.9 * p * p
	end
end

-- cubes rising around a point (heal sparks)
function Fx.Rise(pos, color, count, size, dur, spread)
	local parts, vel = {}, {}
	local rnd = math.random
	for _ = 1, count do
		local part = Fx.Part(color, Enum.Material.Neon, 0.1)
		if not part then
			break
		end
		part.Size = Vector3.new(size, size, size)
		parts[#parts + 1] = part
		local a = rnd() * TAU
		local r = spread * (0.3 + rnd() * 0.7)
		vel[#vel + 1] = { cos(a) * r, 2 + rnd() * 3, sin(a) * r }
	end
	if #parts == 0 then
		return nil
	end
	return Fx.Add(dur, riseUpdate, parts, { ox = pos.X, oy = pos.Y - 0.6, oz = pos.Z, vel = vel })
end

local function boltUpdate(e, p)
	local q = clamp(p * 1.25, 0, 1)
	local x = e.ax + (e.bx - e.ax) * q
	local y = e.ay + (e.by - e.ay) * q + sin(q * pi) * e.arc
	local z = e.az + (e.bz - e.az) * q
	local core = e.parts[1]
	if core then
		core.CFrame = CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(e.bx, e.by, e.bz))
		core.Transparency = (p > 0.8) and 1 or 0
	end
	local tail = e.parts[2]
	if tail then
		local q2 = max(0, q - 0.12)
		tail.CFrame = CFrame.new(e.ax + (e.bx - e.ax) * q2, e.ay + (e.by - e.ay) * q2 + sin(q2 * pi) * e.arc, e.az + (e.bz - e.az) * q2)
		tail.Transparency = (p > 0.8) and 1 or 0.45
	end
	if p >= 0.8 and not e.landed then
		e.landed = true
		Fx.Burst(Vector3.new(e.bx, e.by, e.bz), e.color, 5, 7, 0.28, 0.35, { up = 0.3, gravity = 10 })
	end
end

-- a voxel bolt flying from a to b (ranged attacks), with a small burst where it lands
function Fx.Bolt(a, b, color, size, dur)
	local core = Fx.Part(color, Enum.Material.Neon, 0)
	if not core then
		return nil
	end
	core.Size = Vector3.new(size, size, size * 1.8)
	local tail = Fx.Part(color, Enum.Material.Neon, 0.45)
	if tail then
		tail.Size = Vector3.new(size * 0.6, size * 0.6, size * 0.6)
	end
	local dist = (b - a).Magnitude
	return Fx.Add(dur, boltUpdate, { core, tail }, {
		ax = a.X, ay = a.Y, az = a.Z, bx = b.X, by = b.Y, bz = b.Z, arc = min(2.2, dist * 0.08), color = color,
	})
end

local function beamUpdate(e, p)
	local w = e.width * (1 - p * 0.85)
	local core, glow = e.parts[1], e.parts[2]
	if core then
		core.Size = Vector3.new(w * 0.45, w * 0.45, e.length)
		core.Transparency = p * p
	end
	if glow then
		glow.Size = Vector3.new(w, w, e.length)
		glow.Transparency = 0.55 + 0.45 * p
	end
end

-- a straight beam (Beam specials): cf = the beam's centre frame (LookVector along the beam)
function Fx.Beam(cf, length, width, color, dur)
	local core = Fx.Part(COLORS.White:Lerp(color, 0.35), Enum.Material.Neon, 0)
	if not core then
		return nil
	end
	core.CFrame = cf
	core.Size = Vector3.new(width * 0.45, width * 0.45, length)
	local glow = Fx.Part(color, Enum.Material.Neon, 0.55)
	if glow then
		glow.CFrame = cf
		glow.Size = Vector3.new(width, width, length)
	end
	return Fx.Add(dur, beamUpdate, { core, glow }, { length = length, width = width })
end

local function trailUpdate(e, p)
	for i, part in ipairs(e.parts) do
		local k = i / #e.parts
		part.Transparency = clamp(0.2 + p * 1.2 - k * 0.3, 0, 1)
	end
end

-- a dash trail of fading cubes from a to b (Pounce)
function Fx.Trail(a, b, color, count, dur)
	local parts = {}
	for i = 1, count do
		local part = Fx.Part(color, Enum.Material.Neon, 0.2)
		if not part then
			break
		end
		local k = (i - 0.5) / count
		local s = 0.35 + 0.35 * k
		part.Size = Vector3.new(s, s, s)
		part.CFrame = CFrame.new(a:Lerp(b, k) + Vector3.new(0, sin(k * pi) * 1.2, 0))
		parts[#parts + 1] = part
	end
	if #parts == 0 then
		return nil
	end
	return Fx.Add(dur, trailUpdate, parts, {})
end

local function zoneUpdate(e, p, now)
	local t = now - e.t0
	local fadeIn = clamp(t / 0.3, 0, 1)
	local fadeOut = clamp((e.dur - t) / 0.4, 0, 1)
	local vis = fadeIn * fadeOut
	local disc = e.parts[1]
	if disc then
		disc.Transparency = 1 - (1 - e.discAlpha) * vis
	end
	if e.cloud then
		-- the storm cloud bobs; bolts strike every 0.5 s
		local bob = sin(t * 2.2) * 0.25
		for i = 2, e.cloudEnd do
			local part = e.parts[i]
			local o = e.offsets[i]
			part.CFrame = CFrame.new(e.ox + o.X, e.oy + o.Y + bob, e.oz + o.Z)
			part.Transparency = 1 - (1 - o.alpha) * vis
		end
		local phase = (t % 0.5) / 0.5
		for i = e.cloudEnd + 1, #e.parts do
			local part = e.parts[i]
			if phase < 0.3 and vis > 0.2 then
				if not e.boltFor or e.boltFor ~= floor(t / 0.5) then
					e.boltFor = floor(t / 0.5)
					local rnd = math.random
					local a, r = rnd() * TAU, rnd() * e.r * 0.8
					e.bx, e.bz = e.ox + cos(a) * r, e.oz + sin(a) * r
				end
				local k = i - e.cloudEnd
				local seg = (e.oy - e.floorY) / 3
				local y = e.oy - seg * (k - 0.5) - 0.3
				local jig = (k % 2 == 0) and 0.5 or -0.5
				part.CFrame = CFrame.new(e.bx + jig, y, e.bz - jig * 0.5) * CFrame.Angles(0, 0, jig * 0.4)
				part.Transparency = 0.05
			else
				part.Transparency = 1
			end
		end
	elseif e.bubbles then
		for i = 2, #e.parts do
			local part = e.parts[i]
			local o = e.offsets[i]
			local q = ((t * o.speed) + o.phase) % 1
			part.CFrame = CFrame.new(e.ox + o.X, e.oy + q * 1.4, e.oz + o.Z)
			part.Transparency = 1 - (1 - 0.15) * vis * (1 - q)
		end
	end
end

-- a damaging area on the floor for `seconds`: Storm (a voxel storm cloud with lightning), Field (the disc only: the
-- cloud is AttackFx's) or a lingering pool
function Fx.Zone(floorCF, r, seconds, color, kind)
	local parts = {}
	local disc = Fx.Part(color, Enum.Material.Neon, 0.7)
	if not disc then
		return nil
	end
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.12, r * 2, r * 2)
	disc.CFrame = floorCF * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, pi / 2)
	parts[1] = disc
	local pos = floorCF.Position
	local e = { ox = pos.X, oy = pos.Y, oz = pos.Z, floorY = pos.Y, r = r, offsets = {}, discAlpha = 0.62 }
	local rnd = math.random
	if kind == "Storm" then
		e.cloud = true
		e.oy = pos.Y + 7.5
		local puffs = 9
		for i = 1, puffs do
			local shade = (i % 3 == 0) and COLORS.StormLight or COLORS.Storm
			local part = Fx.Part(shade, Enum.Material.SmoothPlastic, 0.05)
			if not part then
				break
			end
			local a = (i / puffs) * TAU
			local rr = (i == 1) and 0 or r * (0.25 + rnd() * 0.45)
			local s = 1.6 + rnd() * 1.4
			part.Size = Vector3.new(s * 1.3, s * 0.8, s * 1.3)
			parts[#parts + 1] = part
			e.offsets[#parts] = { X = cos(a) * rr, Y = rnd() * 0.8, Z = sin(a) * rr, alpha = 0.05 }
		end
		e.cloudEnd = #parts
		for _ = 1, 3 do
			local bolt = Fx.Part(Color3.fromRGB(230, 236, 255), Enum.Material.Neon, 1)
			if not bolt then
				break
			end
			bolt.Size = Vector3.new(0.25, (e.oy - pos.Y) / 3 + 0.4, 0.25)
			parts[#parts + 1] = bolt
		end
	elseif kind == "Field" then
		e.field = true -- (the disc alone)
	else
		e.bubbles = true
		for _ = 1, 7 do
			local part = Fx.Part(color:Lerp(COLORS.White, 0.25), Enum.Material.Neon, 0.3)
			if not part then
				break
			end
			local a, rr = rnd() * TAU, rnd() * r * 0.85
			local s = 0.35 + rnd() * 0.35
			part.Size = Vector3.new(s, s, s)
			parts[#parts + 1] = part
			e.offsets[#parts] = { X = cos(a) * rr, Z = sin(a) * rr, speed = 0.6 + rnd() * 0.8, phase = rnd() }
		end
	end
	return Fx.Add(seconds, zoneUpdate, parts, e)
end

function Fx.Update(now)
	local list = St.effects
	local i = 1
	while i <= #list do
		local e = list[i]
		local p = (now - e.t0) / e.dur
		local ok = true
		if p < 1 then
			ok = pcall(e.update, e, clamp(p, 0, 1), now)
		end
		if p >= 1 or not ok then
			for _, part in ipairs(e.parts) do
				Fx.Free(part)
			end
			e.parts = {}
			list[i] = list[#list]
			list[#list] = nil
		else
			i = i + 1
		end
	end
end

function Fx.ClearAll()
	for _, e in ipairs(St.effects) do
		for _, part in ipairs(e.parts) do
			Fx.Free(part)
		end
	end
	St.effects = {}
	for _, n in ipairs(St.numbers) do
		n.gui.Enabled = false
		n.gui.Adornee = nil
		St.numberPool[#St.numberPool + 1] = n
	end
	St.numbers = {}
	for _, f in ipairs(St.flashes) do
		f.hl.Enabled = false
		f.hl.Adornee = nil
		St.flashPool[#St.flashPool + 1] = f
	end
	St.flashes = {}
end

----------------------------------------------------------------------
-- Effects: floating numbers (pixel-sized billboards in the world: World text rule) and hit flashes
----------------------------------------------------------------------
local function newNumber()
	local gui = make("BillboardGui", {
		Name = "BattleNumber",
		Size = UDim2.fromOffset(240, 64),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = K.NUMBER_DISTANCE,
		Enabled = false,
	})
	local label = Theme.Label("", "Accent", { Size = K.NUMBER_PX, Stroke = 0, Outline = 2.5 })
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = gui
	local scale = make("UIScale", { Name = "Pop", Scale = 1 }, label)
	return { gui = gui, label = label, scale = scale }
end

-- shows `text` above `adornee` (a BasePart), rising and fading; kind tweaks size / life
function Fx.Number(adornee, height, text, color, px, life)
	if not adornee or not adornee.Parent then
		return nil
	end
	local n = table.remove(St.numberPool)
	if not n then
		if #St.numbers >= K.MAX_NUMBERS then
			n = table.remove(St.numbers, 1) -- recycle the oldest
		else
			n = newNumber()
		end
	end
	if not n then
		return nil
	end
	n.gui.Parent = fxFolder()
	n.gui.Adornee = adornee
	n.label.Text = text
	n.label.TextColor3 = color or COLORS.White
	n.label.TextSize = Theme.ScaledSize(px or K.NUMBER_PX, 22)
	n.label.TextTransparency = 0
	local outline = n.label:FindFirstChild("TextOutline")
	if outline then
		outline.Transparency = 0
	end
	n.t0 = os.clock()
	n.life = life or K.NUMBER_TIME
	n.base = height
	n.jx = (math.random() - 0.5) * 1.4
	n.gui.StudsOffset = Vector3.new(n.jx, height, 0)
	n.gui.Enabled = true
	St.numbers[#St.numbers + 1] = n
	BattleController._wake()
	return n
end

function Fx.UpdateNumbers(now)
	local list = St.numbers
	local i = 1
	while i <= #list do
		local n = list[i]
		local p = (now - n.t0) / n.life
		if p >= 1 or not n.gui.Adornee or not n.gui.Adornee.Parent then
			n.gui.Enabled = false
			n.gui.Adornee = nil
			table.remove(list, i)
			St.numberPool[#St.numberPool + 1] = n
		else
			local rise = 1 - (1 - p) * (1 - p)
			n.gui.StudsOffset = Vector3.new(n.jx, n.base + rise * K.NUMBER_RISE, 0)
			n.scale.Scale = 1 + 0.45 * max(0, 1 - p * 6)
			local fade = clamp((p - 0.6) / 0.4, 0, 1)
			n.label.TextTransparency = fade
			local outline = n.label:FindFirstChild("TextOutline")
			if outline then
				outline.Transparency = fade
			end
			i = i + 1
		end
	end
end

-- a short white (or tinted) flash on a model (a pooled Highlight)
function Fx.Flash(u, color, dur)
	if not u or not u.model or u.parked then
		return
	end
	local f = u.flash
	if not f then
		f = table.remove(St.flashPool)
		if not f then
			if #St.flashes >= K.MAX_FLASHES then
				return
			end
			f = {
				hl = make("Highlight", {
					Name = "HitFlash",
					DepthMode = "Occluded", -- Enum.HighlightDepthMode.Occluded by name (no flash through the arena walls)
					OutlineTransparency = 1,
					FillTransparency = 1,
					Enabled = false,
				}),
			}
		end
		f.hl.Parent = fxFolder()
		St.flashes[#St.flashes + 1] = f
		u.flash = f
		f.unit = u
	end
	f.t0 = os.clock()
	f.dur = dur or K.FLASH_TIME
	f.hl.FillColor = color or COLORS.White
	f.hl.Adornee = u.model
	f.hl.FillTransparency = 0.25
	f.hl.Enabled = true
	BattleController._wake()
end

function Fx.UpdateFlashes(now)
	local list = St.flashes
	local i = 1
	while i <= #list do
		local f = list[i]
		local p = (now - f.t0) / (f.dur or K.FLASH_TIME)
		if p >= 1 or not f.hl.Adornee then
			f.hl.Enabled = false
			f.hl.Adornee = nil
			if f.unit then
				f.unit.flash = nil
				f.unit = nil
			end
			list[i] = list[#list]
			list[#list] = nil
			St.flashPool[#St.flashPool + 1] = f
		else
			f.hl.FillTransparency = 0.25 + 0.75 * p
			i = i + 1
		end
	end
end

----------------------------------------------------------------------
-- Battle record + coordinates
----------------------------------------------------------------------
local function newBattle(payload, battleId)
	local zone = type(payload.Zone) == "table" and payload.Zone or {}
	local cf = zone.CFrame
	if typeof(cf) ~= "CFrame" then
		cf = CFrame.new()
	end
	local size = zone.Size
	local zx = num(zone.X, typeof(size) == "Vector3" and size.X or 60)
	local zz = num(zone.Z, typeof(size) == "Vector3" and size.Z or 60)
	local side = num(payload.Side, 0)
	local spectator = payload.Spectator == true or side == 0
	local B = {
		Id = payload.BattleId or battleId,
		Mode = tostring(payload.Mode or "Duel"),
		Side = side,
		Spectator = spectator,
		Fighter = not spectator,
		ZoneCF = cf,
		ZoneX = zx,
		ZoneZ = zz,
		Names = type(payload.Names) == "table" and payload.Names or {},
		-- Phase 5: the dungeon room's Extra { Floor, Room, Wave, Waves, Name, Boss }
		Dungeon = type(payload.Dungeon) == "table" and payload.Dungeon or nil,
		TimeLimit = num(payload.TimeLimit, 0),
		Level = payload.Level,
		BossId = payload.BossId,
		-- Phase 4: the Champion Ring's "Start".Ring = { Round, Best, Start, Champion = { PetId, Level, Tier, Boss, Name } }
		Ring = type(payload.Ring) == "table" and payload.Ring or nil,
		Round = num(payload.Round or (type(payload.Ring) == "table" and payload.Ring.Round), 0),
		ringNext = nil, -- a won ring round: { Round, Next, Cash, Xp, Tokens, Record, At } until the next "Start"
		units = {},
		list = {},
		mine = {},
		snaps = {},
		offset = 0,
		haveOffset = false,
		renderT = num(payload.T, 0),
		evq = {},
		fxEv = {}, -- [event] = what AttackFx did with it on arrival (Atk.Arrive / Atk.Result)
		fxHold = {}, -- [unit id] = render-clock time a ranged shot at it lands (Net.Queue / Net.Hold: its next events wait)
		teles = {},
		buildQueue = {},
		-- Phase 5: my team (Start.Team), the lock, the cooldowns (os.clock ready times) and the predictions
		fighterId = nil,
		lives = nil,
		speed = nil, -- { Walk, Run }
		lock = nil,
		cd = { Element = 0, Dash = 0, Swap = 0, Cheer = 0, Buff = {} },
		cdLen = { Element = 7, Dash = 2.5, Swap = 10, Cheer = 20, Buff = {} },
		cheerUntil = 0, -- wave 6: os.clock time the Cheer up! glow ends
		pending = {},
		ended = false,
		simEnded = false,
		enraged = false,
		wave = 0,
		folder = nil,
	}
	-- the zone basis, so a zone-local point becomes a world point with plain arithmetic per frame
	local px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	B.basis = { px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 }
	B.folder = make("Folder", { Name = "Battle_" .. tostring(B.Id) }, battleFolder())
	return B
end

-- zone-local (x, y, z) -> world Vector3
local function worldPoint(B, x, y, z)
	local b = B.basis
	return Vector3.new(b[1] + b[4] * x + b[5] * y + b[6] * z, b[2] + b[7] * x + b[8] * y + b[9] * z, b[3] + b[10] * x + b[11] * y + b[12] * z)
end

-- zone-local position + yaw (0 = facing -Z of the zone) -> world CFrame (one allocation)
local function worldFrame(B, x, y, z, yaw)
	local b = B.basis
	local c, s = cos(yaw), sin(yaw)
	-- R = Z * Ry(yaw): columns of Ry are (c,0,-s), (0,1,0), (s,0,c)
	local m00 = b[4] * c - b[6] * s
	local m01 = b[5]
	local m02 = b[4] * s + b[6] * c
	local m10 = b[7] * c - b[9] * s
	local m11 = b[8]
	local m12 = b[7] * s + b[9] * c
	local m20 = b[10] * c - b[12] * s
	local m21 = b[11]
	local m22 = b[10] * s + b[12] * c
	return CFrame.new(
		b[1] + b[4] * x + b[5] * y + b[6] * z,
		b[2] + b[7] * x + b[8] * y + b[9] * z,
		b[3] + b[10] * x + b[11] * y + b[12] * z,
		m00, m01, m02, m10, m11, m12, m20, m21, m22
	)
end

local function yawToward(dx, dz)
	return atan2(-dx, -dz)
end

----------------------------------------------------------------------
-- Units
----------------------------------------------------------------------
-- the definition PetBuilder draws for a unit (its look from the sim; else its key / pet id)
function Units.Def(info)
	local look = info.look
	local base = nil
	if PetCatalog and type(PetCatalog.Get) == "function" then
		if info.petId then
			local ok, d = pcall(PetCatalog.Get, info.petId)
			base = ok and type(d) == "table" and d or nil
		end
		if not base and type(look) == "table" and look.BodyId then
			local ok, d = pcall(PetCatalog.Get, look.BodyId)
			base = ok and type(d) == "table" and d or nil
		end
	end
	if type(look) == "table" then
		return { Id = tostring(info.key or info.petId or info.id), Rarity = base and base.Rarity or nil, Look = look }
	end
	if PetKeys and type(info.key) == "string" then
		local ok, d = pcall(PetKeys.DefOf, info.key)
		if ok and type(d) == "table" then
			return d
		end
	end
	return base
end

local function isAnimatedPart(part)
	local spec = part:GetAttribute("PB_G")
	if type(spec) ~= "string" or type(part:GetAttribute("PB_Base")) ~= "string" then
		return false
	end
	local kind = string.match(spec, "^[^:]*:([^:]*)")
	return kind ~= "lid"
end

-- welds the static parts to the anchored root once: a pose is then one root CFrame write
local function weldStatic(model, root)
	local inv = root.CFrame:Inverse()
	local identity = CFrame.new()
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= root and part.Anchored and not isAnimatedPart(part) then
			make("Weld", { Name = "BattleWeld", Part0 = root, Part1 = part, C0 = inv * part.CFrame, C1 = identity }, part)
			part.Anchored = false
		end
	end
	root.Anchored = true
end

function Units.Add(B, info)
	if type(info) ~= "table" then
		return nil
	end
	local id = tonumber(info.id)
	if not id then
		return nil
	end
	local u = B.units[id]
	if u then
		u.info = info
		u.fxLook = nil -- (Atk.Look reads the new info)
		return u
	end
	local me = myUserId()
	local side = num(info.side, 2)
	local mine = B.Fighter and info.owner == me
	local ally
	if B.Fighter then
		ally = side == B.Side
	else
		ally = side == 1
	end
	u = {
		id = id,
		info = info,
		side = side,
		owner = info.owner,
		slot = num(info.slot, 0),
		kind = tostring(info.kind or "Pet"),
		name = tostring(info.name or "Pet"),
		element = info.element,
		elements = type(info.elements) == "table" and info.elements or { info.element },
		maxHp = max(1, num(info.maxHp, 100)),
		level = num(info.level, 1),
		tier = info.tier,
		scale = num(info.scale, 1),
		ranged = info.ranged == true,
		radius = num(info.radius, 1.8),
		special = type(info.special) == "table" and info.special or nil,
		isBoss = info.kind == "Boss",
		bossId = info.boss,
		-- Phase 4: the stored evolution stage (the model and the card's stars), own pets' XP (the card's XP row), the
		-- ring champion's crown
		evo = clamp(floor(num(info.evo, 0)), 0, 2),
		xp = tonumber(info.xp),
		xpNext = tonumber(info.xpNext),
		crowned = info.crowned == true,
		-- Phase 5: a player team's bench (the static slot of a helper), its role, buff and element attack
		bench = tonumber(info.bench),
		benched = tonumber(info.bench) ~= nil,
		role = info.role,
		lives = nil,
		windup = false,
		mine = mine,
		ally = ally,
		x = 0,
		z = 0,
		seen = false,
		yaw = 0,
		hp = max(1, num(info.maxHp, 100)),
		state = 0,
		meter = 0,
		shield = 0,
		phase = math.random() * TAU,
		animOpts = { Flap = 1, Excited = 0 },
		bossOpts = { CFrame = nil, Progress = 0, Attack = nil, Enraged = false },
		pose = "Idle",
		poseAt = 0,
		poseDur = 0,
	}
	B.units[id] = u
	B.list[#B.list + 1] = u
	if u.isBoss then
		B.boss = u
	end
	if mine and u.slot >= 1 and u.slot <= 4 then
		B.mine[u.slot] = u
	end
	B.buildQueue[#B.buildQueue + 1] = u
	return u
end

-- a Spawn / Wave event's unit infos (server order: they may come after "Start"); a new unit whose info says Arrive > 0
-- (seconds) arrives: EvolutionFx.Arrive at its spot, the model hidden until the flash, then a hop (Units.Arrival)
function Units.AddList(B, list)
	for _, info in ipairs(type(list) == "table" and list or {}) do
		local known = type(info) == "table" and B.units[tonumber(info.id) or -1] ~= nil
		local u = Units.Add(B, info)
		if u and not known then
			local arrive = type(info) == "table" and tonumber(info.Arrive or info.arrive) or nil
			if arrive and arrive > 0 and not u.mine then
				u.arrive = min(arrive, 4)
			end
		end
	end
end

function Units.Destroy(u)
	if u.arriveFx then
		if not u.arriveFx.Done then
			pcall(u.arriveFx.Stop)
		end
		u.arriveFx = nil
	end
	if u.flash then
		u.flash.hl.Adornee = nil
	end
	Cards.Free(u)
	for _, key in ipairs({ "shieldPart", "icePart", "focusMark" }) do
		local p = u[key]
		if p then
			pcall(p.Destroy, p)
			u[key] = nil
		end
	end
	if u.model then
		pcall(u.model.Destroy, u.model)
	end
	u.model = nil
	u.root = nil
	u.bar = nil
	u.gone = true
end

function Units.Remove(B, id)
	local u = B.units[id]
	if not u then
		return
	end
	B.units[id] = nil
	for i, v in ipairs(B.list) do
		if v == u then
			table.remove(B.list, i)
			break
		end
	end
	for slot, v in pairs(B.mine) do
		if v == u then
			B.mine[slot] = nil
		end
	end
	if B.boss == u then
		B.boss = nil
	end
	Atk.Cancel(u.id) -- its own attack effects and its pose end with it
	Units.Destroy(u)
end

-- the pixel HP bar above a unit (no text: World text rule only covers text)
local function addBar(u, adornee, height)
	local color = u.mine and COLORS.Mine or (u.ally and COLORS.Ally or COLORS.Enemy)
	local w, h = Theme.ScaledSize(74, 50), Theme.ScaledSize(11, 8)
	local gui = make("BillboardGui", {
		Name = "HpBar",
		Adornee = adornee,
		Size = UDim2.fromOffset(w, h),
		StudsOffset = Vector3.new(0, height, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = K.BAR_DISTANCE,
	})
	local back = make("Frame", {
		Name = "Back",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLORS.Track,
		BorderSizePixel = 0,
	}, gui)
	Theme.Corner(back, UDim.new(0, 4))
	Theme.Stroke(back, u.mine and COLORS.Gold or COLORS.Ink, u.mine and 2 or 1.5, 0)
	local fill = make("Frame", {
		Name = "Fill",
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, back)
	Theme.Corner(fill, UDim.new(0, 3))
	gui.Parent = u.model
	u.bar = gui
	u.barFill = fill
	u.barFrac = 1
end

-- builds one unit's model (pcall'd by the caller)
local function buildUnit(B, u)
	if u.isBoss then
		local BB = lazyBoss()
		if not BB then
			error("BossBuilder is missing")
		end
		local cf = worldFrame(B, u.x, 0, u.z, u.yaw)
		local model = BB.Build(u.bossId, { Detail = "High", CFrame = cf })
		if not model then
			error("BossBuilder.Build returned nil for " .. tostring(u.bossId))
		end
		local okH, h = pcall(BB.GetHeight, model)
		u.height = (okH and num(h, 20)) or 20
		u.model = model
		u.root = model.PrimaryPart or model:FindFirstChild("Root")
		model.Parent = B.folder
		if B.enraged then
			pcall(BB.SetEnraged, model, true)
		end
		return
	end
	if not PetBuilder then
		error("PetBuilder is missing")
	end
	local def = Units.Def(u.info)
	if not def then
		error("no definition for unit " .. tostring(u.id))
	end
	if u.crowned then
		def = Ring.Crowned(def) -- the ring champion wears PetBuilder's voxel crown
	end
	-- evolved units use the Low evolved form (within the petEvoLow / petEvo2Low budgets), like evolved followers;
	-- Phase 5 (10.3): my fighter High, my helpers Low (a helper swapped in is rebuilt at High: Units.Rebuild)
	-- (fix round 2, I2-b) a held auto-swap's incoming pet (unbenchAt) is my next fighter: High while it waits
	local detail = (u.mine and u.evo == 0 and (not u.benched or u.unbenchAt ~= nil)) and "High" or "Low"
	-- dungeon enemies wear the Wild look (contract 5.6 / C13): darker, tinted toward the floor's element, Neon eyes
	local wild = nil
	if u.info.wild and not u.ally then
		local c = elementColor((B.Dungeon and B.Dungeon.Element) or u.element)
		wild = { Tint = Theme.Darken(c, 0.35), Eyes = Theme.Lighten(c, 0.15) }
	end
	local model = PetBuilder.Build(def, { Scale = K.PET_SCALE * u.scale, Detail = detail, Evolved = u.evo > 0 and u.evo or nil, Wild = wild })
	local root = model.PrimaryPart or model:FindFirstChild("Body")
	if not root or not root:IsA("BasePart") then
		model:Destroy()
		error("pet model without a root")
	end
	local okSize, size = pcall(model.GetExtentsSize, model)
	u.height = (okSize and typeof(size) == "Vector3") and size.Y or 3.5
	u.centerY = u.height / 2 + K.HOVER
	u.pbScale = num(model:GetAttribute("PB_Scale"), K.PET_SCALE * u.scale) -- (the pose body offsets are studs at scale 1)
	-- weld at the built pose FIRST, then move: a pose is one root CFrame write from here on
	local okWeld = pcall(weldStatic, model, root)
	u.rigid = okWeld
	-- the parts PetBuilder.Animate poses (still anchored after the weld): moved with the root on a strided frame
	u.loose = {}
	u.looseBuf = {}
	if okWeld then
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part ~= root and part.Anchored then
				u.loose[#u.loose + 1] = part
			end
		end
	end
	local cf = worldFrame(B, u.x, u.centerY, u.z, u.yaw)
	if okWeld then
		root.CFrame = cf
	else
		pcall(model.PivotTo, model, cf)
	end
	local old = u.model
	u.model = model
	u.root = root
	u.folder = B.folder
	u.detail = detail
	model.Name = "Unit_" .. tostring(u.id)
	model:SetAttribute("BC_Evo", u.evo)
	model:SetAttribute("BC_Detail", detail)
	if old then
		-- a rebuild (a helper that became my fighter): the card moves over, the old model goes
		u.rebuild = nil
		if u.card and u.card.Gui then
			u.card.Gui.Parent = model
			pcall(u.card.SetAdornee, u.card, root, (u.height or 3) / 2 + 0.9)
		end
		if u.flash then
			u.flash.hl.Adornee = nil
		end
		pcall(old.Destroy, old)
		u.parked = false
	else
		Cards.Add(B, u, root)
	end
	model.Parent = B.folder
end

-- my new fighter (a swap) is drawn at High detail: rebuilt by the build queue under its time budget
function Units.Rebuild(B, u)
	if u and u.model and u.detail == "Low" and u.evo == 0 and not u.isBoss and not u.rebuild then
		u.rebuild = true
		B.buildQueue[#B.buildQueue + 1] = u
	end
end

-- Phase 6 (runtime-pets): when MeshLibrary makes a pet's Blender mesh keys usable here (PetBuilder.MeshVersion
-- changes), its Part-built units are queued for a rebuild as mesh pets (KO'd / parked ones stay as they are)
function Units.MeshSweep(B)
	local ver = PetBuilder.MeshVersion()
	if ver == B.meshVer then
		return
	end
	B.meshVer = ver
	local ids = {}
	for id in pairs(B.units) do
		ids[#ids + 1] = id
	end
	table.sort(ids, function(a, b)
		return tostring(a) < tostring(b)
	end)
	for _, id in ipairs(ids) do
		local u = B.units[id]
		if u.model and not u.isBoss and not u.rebuild and not u.parked and not u.gone and PetBuilder.NeedsMeshRebuild(u.model) then
			u.rebuild = true
			B.buildQueue[#B.buildQueue + 1] = u
		end
	end
	-- the helpers' portraits (ViewportFrames) too
	for _, H in ipairs(Hud.helpers or {}) do
		if H.unit and H.model and PetBuilder.NeedsMeshRebuild(H.model) then
			H.built = false
			pcall(Hud.Portrait, H, H.unit)
		end
	end
end

function Units.BuildPending(B)
	if PetBuilder and PetBuilder.MeshVersion and B.units then
		Units.MeshSweep(B)
	end
	local q = B.buildQueue
	if #q == 0 then
		return
	end
	local t0 = os.clock()
	local built = 0
	while #q > 0 and built < K.BUILD_MAX do
		if built > 0 and os.clock() - t0 > K.BUILD_BUDGET then
			break
		end
		local u = table.remove(q, 1)
		if u.benched and not u.mine and not u.isBoss and not u.unbenchAt then
			u.needBuild = true -- another player's helper: not drawn while it sits on the bench
		elseif not u.gone and (not u.model or u.rebuild) then
			local ok, err = pcall(buildUnit, B, u)
			if not ok then
				warnOnce("build_" .. tostring(u.kind) .. tostring(u.info and (u.info.key or u.info.boss)), "could not build unit " .. tostring(u.name) .. ": " .. tostring(err))
				u.failed = true
			end
			built = built + 1
			St.perf.builds = St.perf.builds + 1
		end
	end
end

-- a pet's KO: poof, then the model is parked until the end
local function parkUnit(u, parked)
	if not u.model then
		return
	end
	if parked and not u.parked then
		u.parked = true
		u.model.Parent = nil
	elseif not parked and u.parked then
		u.parked = false
		u.model.Parent = u.folder or u.model.Parent
	end
end

function Units.SetPose(u, pose, dur, attackId)
	u.pose = pose
	u.poseAt = os.clock()
	u.poseDur = dur or 0
	if attackId then
		u.attackId = attackId
	end
end

-- per-frame update of one unit (position from the snapshots, facing, lunge / hop, animation)
local function updateUnit(B, u, now, dt, sa, sb, alpha, animate)
	return Units.Update(B, u, now, dt, sa, sb, alpha, animate)
end

function Units.Update(B, u, now, dt, sa, sb, alpha, animate)
	local a = sa and sa.Units[u.id]
	local b = sb and sb.Units[u.id]
	local x, z = u.x, u.z
	if type(a) == "table" and type(b) == "table" then
		x = a.x + (b.x - a.x) * alpha
		z = a.z + (b.z - a.z) * alpha
	elseif type(a) == "table" then
		x, z = a.x, a.z
	elseif type(b) == "table" then
		x, z = b.x, b.z
	end
	local d = (alpha >= 0.5 and type(b) == "table" and b) or (type(a) == "table" and a) or (type(b) == "table" and b) or nil
	if d then
		local hp, state = num(d.hp, u.hp), num(d.state, u.state)
		-- (Task 11b) a late Special's hit (or a caster's last gasp) not landed yet: the drawn HP never drops under its
		-- hold and the unit is not drawn down before it (Units.Hold); the snapshots already carry the new HP
		if u.holdUntil then
			if now < u.holdUntil then
				if u.holdHp and hp < u.holdHp then
					hp = u.holdHp
				end
				if state == S_DOWN then
					state = u.holdState or STATES.Idle or 0
				end
			else
				Units.Unhold(u)
			end
		end
		u.hp = hp
		u.state = state
		u.target = d.target
		u.meter = num(d.meter, 0)
		u.shield = num(d.shield, 0)
		-- Phase 5: the team's lives, the wind-up bit, the bench
		if d.lives ~= nil then
			u.lives = num(d.lives, u.lives)
		end
		local winding = d.windup == true
		if winding and not u.windup and not u.ally then
			Fx.Flash(u, COLORS.Windup, K.WINDUP_FLASH) -- the dash cue
		end
		if winding and not u.windup then
			u.windAt = now -- (the held Windup pose gathers from here: Atk.PoseOf)
		end
		u.windup = winding
		local onBench = u.state == S_BENCHED
		local benched = onBench
		-- (fix round 2, I2-b) the incoming pet of a held auto-swap stays on the bench until its Swap plays (the handler
		-- unbenches it; UNBENCH_SLACK is the fall-back): another player's is built meanwhile, still parked
		if u.unbenchAt then
			if now < u.unbenchAt then
				benched = true
			else
				u.unbenchAt = nil
			end
		end
		if benched ~= u.benched then
			u.benched = benched
		end
		if not onBench and not u.model and u.needBuild and not u.failed then
			u.needBuild = nil
			B.buildQueue[#B.buildQueue + 1] = u
		end
		if u.mine and d.lives ~= nil and B.Fighter and not benched and (B.fighterId == nil or u.id == B.fighterId) then
			B.lives = u.lives -- (only the fighter's record carries the team's lives)
		end
	end
	x, z = num(x, u.x), num(z, u.z)
	local mx, mz = x - u.x, z - u.z
	if not u.seen then
		u.seen = true
		mx, mz = 0, 0
		-- face the floor centre at first
		u.yaw = yawToward(-x, -z)
	end
	u.x, u.z = x, z
	if u.arrive and Units.Arrival(B, u, now) then
		return -- still arriving: the model stays hidden until the flash
	end
	if not u.model then
		return
	end
	if u.benched and not u.mine and not u.isBoss then
		parkUnit(u, true) -- another player's helper is not drawn (B3)
		return
	end
	local down = u.state == S_DOWN or u.hp <= 0
	if u.isBoss then
		Units.UpdateBoss(B, u, now, down, dt)
		return
	end
	if u.card and (u.cardHp ~= u.hp or u.cardMeter ~= u.meter or u.cardLives ~= u.lives) then
		Cards.Live(u) -- only when the snapshot changed the HP / meter (at most 10 Hz), never a write per frame
	end
	-- downed pets: poof once, then park (AttackFx's Ko: the poof played, the pet tumbles and lies until KO_PARK_FX)
	if down then
		if not u.downAt then
			u.downAt = now
			if not u.poofed then
				u.poofed = true
				local pos = worldPoint(B, x, u.centerY or 1.5, z)
				Fx.Burst(pos, Color3.fromRGB(236, 240, 250), 12, 9, 0.5, 0.6, { color2 = elementColor(u.element), alpha = 0.05 })
			end
		end
		if now - u.downAt >= (u.koAt and K.KO_PARK_FX or K.KO_PARK) then
			parkUnit(u, true)
		end
		if not u.koAt or u.parked then
			return
		end
	else
		-- AttackFx's Ko plays when the KO event ARRIVES, before the render clock draws the pet down: only a pet that was
		-- drawn down and is up again (a revive), or a KO no snapshot confirmed within KO_CONFIRM, ends its Ko pose
		if u.koAt and (u.downAt or now > u.koAt + K.KO_CONFIRM) then
			u.koAt = nil
			u.poofed = nil
			Atk.Cancel(u.id)
		end
		if u.downAt or u.parked then
			u.downAt = nil
			u.poofed = nil -- (up again: its next KO poofs)
			parkUnit(u, false)
		end
	end
	u.accDt = (u.accDt or 0) + dt
	if u.mine and B.Fighter and not B.ended then
		u.accDt = 0
		return Me.Draw(B, u, now, dt, x, z) -- my fighter at my shoulder, my helpers behind me
	end
	if u.parked then
		return
	end
	-- every frame: the root (interpolated position + facing), so a far / crowded pet never stutters; the stride
	-- (animate = false) only skips the pose work (PetBuilder.Animate), its loose parts ride along (Units.CarryLoose)
	if animate then
		u.posed = true
	end
	u.accDt = 0
	-- facing: the target while fighting, else the way it moves
	local want = nil
	local tgt = u.target and B.units[u.target]
	if tgt and (u.state == S_ATTACKING or u.state == S_CASTING or mx * mx + mz * mz < 0.0004) then
		want = yawToward(tgt.x - x, tgt.z - z)
	elseif mx * mx + mz * mz > 0.0004 then
		want = yawToward(mx, mz)
	end
	if want and u.state ~= S_STUNNED then
		local k = 1 - exp(-K.FACE_RATE * dt)
		u.yaw = u.yaw + wrapAngle(want - u.yaw) * k
	end
	-- lunge / recoil / hop
	local ox, oz, oy = 0, 0, 0
	if u.lungeAt then
		local p = (now - u.lungeAt) / K.LUNGE_TIME
		if p >= 1 then
			u.lungeAt = nil
		elseif not u.lungeFx then -- (AttackFx's Strike pose replaces the lunge / recoil of an attack it played)
			local amt = sin(p * pi) * (u.ranged and -K.RECOIL_DIST or K.LUNGE_DIST)
			ox, oz = u.lungeX * amt, u.lungeZ * amt
		end
	end
	if u.hopAt then
		local p = (now - u.hopAt) / K.HOP_TIME
		if p >= 1 then
			u.hopAt = nil
		elseif p > 0 then
			oy = sin(p * pi) * K.HOP_HEIGHT
		end
	end
	if u.hurtAt then
		local p = (now - u.hurtAt) / 0.18
		if p >= 1 then
			u.hurtAt = nil
		elseif not u.hurtFx then -- (AttackFx's Hurt pose replaces the nudge)
			local amt = sin(p * pi) * 0.3
			ox, oz = ox + (u.hurtX or 0) * amt, oz + (u.hurtZ or 0) * amt
		end
	end
	if u.dashAt then
		local amt = K.DASH_DIST * Me.DashAmount(u, now)
		ox, oz = ox + (u.dashX or 0) * amt, oz + (u.dashZ or 0) * amt
	end
	local bob = 0
	local stunned = u.state == S_STUNNED or down
	if not stunned then
		bob = sin(now * 3.1 + u.phase) * K.BOB
	end
	if u.windup and not Atk.Drives(u) then
		oy = oy - 0.35 -- the wind-up crouch (Winding: the dash cue; AttackFx shows its held Windup pose instead)
	end
	local cf = worldFrame(B, x + ox, (u.centerY or 1.5) + bob + oy, z + oz, u.yaw)
	local pose, body = Atk.PoseOf(u, now, down, false, animate, cf.Position)
	if body then
		cf = cf * body
	end
	if u.rigid then
		if not animate or u.animBroken or not PetBuilder then
			Units.CarryLoose(u, cf) -- no Animate this frame: the wings / animated parts keep their pose on the root
		end
		u.root.CFrame = cf
	else
		pcall(u.model.PivotTo, u.model, cf)
	end
	if animate and PetBuilder and not u.animBroken then
		local opts = u.animOpts
		opts.Flap = stunned and 0 or ((u.state == S_DASHING or mx * mx + mz * mz > 0.0004) and 1.8 or 1)
		opts.Excited = u.windup and 1 or ((u.state == S_ATTACKING or u.state == S_CASTING) and 0.6 or 0)
		opts.Pose = pose
		local ok = pcall(PetBuilder.Animate, u.model, now + u.phase, opts)
		if not ok then
			u.animBroken = true
		end
	end
	-- the HP bar (only when it changes)
	local frac = clamp(u.hp / u.maxHp, 0, 1)
	if u.barFill and abs(frac - (u.barFrac or -1)) > 0.004 then
		u.barFrac = frac
		u.barFill.Size = UDim2.new(max(frac, 0.02), -2, 1, -2)
	end
	-- shield cube and ice crystals follow the unit
	Units.UpdateStatus(B, u, now, cf)
end

-- a strided frame (no PetBuilder.Animate): the root moves to cf and the anchored animated parts (wings, tails...) move
-- rigidly with it, keeping their last pose (one BulkMoveTo, a reused buffer: no table per frame)
function Units.CarryLoose(u, cf)
	local list = u.loose
	local n = list and #list or 0
	if n == 0 then
		return
	end
	local delta = cf * u.root.CFrame:Inverse()
	local buf = u.looseBuf
	for i = 1, n do
		buf[i] = delta * list[i].CFrame
	end
	local ok = pcall(workspace.BulkMoveTo, workspace, list, buf, Enum.BulkMoveMode.FireCFrameChanged)
	if not ok then
		for i = 1, n do
			list[i].CFrame = buf[i]
		end
	end
end

-- client/Controllers/EvolutionFx (the arrival effect); nil when missing
function Units.EvoFx()
	if Mods.Evo == nil then
		Mods.Evo = optional(script.Parent, "EvolutionFx") or false
	end
	local m = Mods.Evo
	return (m and type(m.Arrive) == "function") and m or nil
end

-- dungeon fixes (decision 3): an arriving enemy (Units.AddList, info Arrive > 0). Its first frame with a position
-- starts EvolutionFx.Arrive at its spot (effects only: rune ring, pillar, flash, sparkles, shock ring, sparks; Low
-- graphics = flash + ring); the model stays out of the world until the flash, then pops in with a hop. The server
-- keeps it inert and unhittable meanwhile (arriveUntil). -> true while the model is hidden (skip the frame)
function Units.Arrival(B, u, now)
	if u.isBoss then
		u.arrive = nil
		return false
	end
	if not u.arriveFx and not u.arriveShown then
		local fx = Units.EvoFx()
		local h = u.height or (3.2 * u.scale * K.PET_SCALE)
		local c = elementColor((B.Dungeon and B.Dungeon.Element) or u.element)
		local ok, handle = false, nil
		if fx then
			ok, handle = pcall(fx.Arrive, worldFrame(B, u.x, u.centerY or (h / 2 + K.HOVER), u.z, 0), {
				Parent = fxFolder(),
				Colors = { c, Theme.Lighten(c, 0.55) },
				Height = h,
				Radius = max(1, u.radius),
				Ground = worldPoint(B, u.x, 0, u.z).Y,
				Seconds = u.arrive,
				OnFlash = function()
					u.arriveShown = true
				end,
			})
		end
		if not ok or type(handle) ~= "table" then
			u.arrive = nil -- no effect module: the pet is simply there
			return false
		end
		u.arriveFx = handle
		St.arrivals = (St.arrivals or 0) + 1
	end
	if not u.arriveShown then
		u.hidden = true
		if u.model and u.model.Parent then
			u.model.Parent = nil
		end
		return true
	end
	-- the flash: the pet pops in
	u.arrive = nil
	u.hidden = nil
	if u.model and not u.model.Parent and not u.parked then
		u.model.Parent = u.folder or B.folder
	end
	u.hopAt = now
	return false
end

-- Phase 6: the Blender fx meshes (fx_shield / fx_ice / fx_arrow, creatures class) once they are usable on this
-- device: Units.FxMesh(key, scale) -> the MeshParts of a fresh rootless Assemble (sorted by name, Anchored, no
-- collisions) or nil (= the Part build). Same slot names and the same per-frame CFrame code either way.
function Units.FxMesh(key, scale)
	if Mods.Mesh == nil then
		Mods.Mesh = optional(Shared, "MeshLibrary") or false
	end
	local ML = Mods.Mesh
	if not ML or type(ML.Active) ~= "function" or not ML.Active() or not ML.IsReady(key) then
		return nil
	end
	local ok, model = pcall(ML.Assemble, key, nil, { Scale = scale or 1 })
	if not ok or typeof(model) ~= "Instance" then
		return nil
	end
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			parts[#parts + 1] = d
		end
	end
	table.sort(parts, function(a, b)
		return a.Name < b.Name
	end)
	for _, d in ipairs(parts) do
		d.Parent = nil
		d.Anchored = true
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		d.CastShadow = false
	end
	model:Destroy()
	if #parts == 0 then
		return nil
	end
	return parts
end

-- shield bubble (while the snapshot reports a shield) and ice (while stunned)
function Units.UpdateStatus(B, u, now, cf)
	local h = u.height or 3
	if u.shield > 0 then
		local p = u.shieldPart
		if not p then
			local mesh = Units.FxMesh("fx_shield")
			if mesh then
				-- the voxel bubble: one MeshPart sized like the Part cube (MeshPart.Size scales the mesh)
				p = mesh[1]
				p.Name = "ShieldCube"
				p.Size = Vector3.new(h * 1.25, h * 1.15, h * 1.25)
				p.Color = COLORS.Shield
				for i = 2, #mesh do
					mesh[i]:Destroy()
				end
				p.Parent = u.model
				u.shieldPart = p
			end
		end
		if not p then
			p = make("Part", {
				Name = "ShieldCube",
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Material = Enum.Material.ForceField,
				Color = COLORS.Shield,
				Transparency = 0,
				Size = Vector3.new(h * 1.25, h * 1.15, h * 1.25),
			}, u.model)
			u.shieldPart = p
		end
		p.CFrame = cf * CFrame.Angles(0, now * 0.8, 0)
	elseif u.shieldPart then
		u.shieldPart:Destroy()
		u.shieldPart = nil
	end
	local iced = u.state == S_STUNNED or (u.iceUntil and now < u.iceUntil)
	if iced then
		local p = u.icePart
		if not p then
			p = make("Model", { Name = "Ice" }, u.model)
			for i = 1, 5 do
				local a = (i / 5) * TAU
				local s = h * (0.28 + 0.06 * (i % 3))
				-- Phase 6: a Blender ice crystal (fx_ice, 1.1 tall) when ready: its main part is the "Crystal" the
				-- per-frame code moves, the light core rides on it (welded child, also named Crystal)
				local mesh = Units.FxMesh("fx_ice", s * 1.4 / 1.1)
				if mesh then
					local main = mesh[1]
					main.Name = "Crystal"
					main:SetAttribute("Angle", a)
					for k = 2, #mesh do
						local c = mesh[k]
						c.Name = "Crystal"
						c.Anchored = false
						c.Massless = true
						local weld = make("WeldConstraint", { Part0 = main, Part1 = c }, c)
						weld.Name = "IceWeld"
						c.Parent = main
					end
					main.Parent = p
				end
				if not mesh then
					make("Part", {
						Name = "Crystal",
						Anchored = true,
						CanCollide = false,
						CanQuery = false,
						CanTouch = false,
						CastShadow = false,
						Material = Enum.Material.Glass,
						Color = COLORS.Ice,
						Transparency = 0.35,
						Size = Vector3.new(s * 0.45, s * 1.4, s * 0.45),
					}, p):SetAttribute("Angle", a)
				end
			end
			u.icePart = p
		end
		local r = (u.radius or 1.8) * 0.75 * K.PET_SCALE * 0.6
		for _, c in ipairs(p:GetChildren()) do
			local a = c:GetAttribute("Angle") or 0
			c.CFrame = cf * CFrame.new(cos(a) * r, -h * 0.25, sin(a) * r) * CFrame.Angles(0.35 * cos(a), a, 0.35 * sin(a))
		end
	elseif u.icePart then
		u.icePart:Destroy()
		u.icePart = nil
	end
end

-- the raid boss: BossBuilder poses on the interpolated position
function Units.UpdateBoss(B, u, now, down, dt)
	local BB = lazyBoss()
	if not BB then
		return
	end
	local tgt = u.target and B.units[u.target]
	local want = nil
	if u.faceX then
		want = yawToward(u.faceX - u.x, u.faceZ - u.z)
	elseif tgt then
		want = yawToward(tgt.x - u.x, tgt.z - u.z)
	end
	if want and not down then
		u.yaw = u.yaw + wrapAngle(want - u.yaw) * (1 - exp(-3 * (dt or 0.016)))
	end
	local pose = u.pose
	local progress = 0
	if down then
		if pose ~= "Down" then
			Units.SetPose(u, "Down", 1.6)
			pose = "Down"
		end
	end
	if u.poseDur > 0 then
		progress = clamp((now - u.poseAt) / u.poseDur, 0, 1)
		if progress >= 1 and pose ~= "Down" and pose ~= "Windup" then
			Units.SetPose(u, "Idle", 0)
			pose = "Idle"
			u.faceX, u.faceZ = nil, nil
		end
	end
	if pose == "Windup" and u.windupAt then
		progress = clamp((B.renderT - u.windupFrom) / max(0.1, u.windupAt - u.windupFrom), 0, 1)
	end
	local opts = u.bossOpts
	opts.CFrame = worldFrame(B, u.x, 0, u.z, u.yaw)
	opts.Progress = progress
	opts.Attack = u.attackId
	opts.Enraged = B.enraged
	local ok, err = pcall(BB.Animate, u.model, pose, now, opts)
	if not ok then
		warnOnce("bossanim", "BossBuilder.Animate failed: " .. tostring(err))
	end
end

-- the world point of a unit's body centre (effects, numbers)
local function unitCenter(B, u)
	if u.mine and u.drawn and B.Fighter and not u.parked then
		return u.drawn -- my fighter / helpers are drawn at my character, not at the server spot
	end
	local y = u.isBoss and (u.height or 20) * 0.55 or (u.centerY or 1.5)
	return worldPoint(B, u.x, y, u.z)
end

----------------------------------------------------------------------
-- Phase 5 (4.7 Models): my fighter at my character's shoulder, my helpers behind me, the camera shake
----------------------------------------------------------------------
-- the character's HumanoidRootPart (nil without one)
function Me.Root()
	local char = LocalPlayer and LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and root.Parent then
		return root
	end
	return nil
end

-- a zone-local direction (x, z) as a world vector (the zone's rotation)
local function zoneDir(B, x, z)
	local b = B.basis
	return Vector3.new(b[4] * x + b[6] * z, b[7] * x + b[9] * z, b[10] * x + b[12] * z)
end

-- the frame-rate independent share of a per-60-Hz-frame lerp
local function lerpShare(perFrame, dt)
	return 1 - (1 - perFrame) ^ (clamp(dt, 0, 0.25) * 60)
end

-- where my fighter is drawn: the shoulder of the SERVER fighter position (x, z), blended toward the character root
-- while the two are within BLEND_DIST studs (so what looks in reach IS in reach); returns the target and the share
function Me.FighterTarget(B, u, x, z)
	local server = worldPoint(B, x, u.centerY or 1.5, z)
	local root = Me.Root()
	if not root then
		return server, K.FOLLOW_LERP, nil
	end
	local rcf = root.CFrame
	local rp = rcf.Position
	local dx, dz = rp.X - server.X, rp.Z - server.Z
	local d = sqrt(dx * dx + dz * dz)
	local ax, az, share = server.X, server.Z, K.FOLLOW_LERP
	local k = 0
	if d <= K.BLEND_DIST then
		k = 1 - d / K.BLEND_DIST
		ax, az = server.X + dx * k, server.Z + dz * k
		share = 0.6
	end
	-- bug #22: the shoulder offset (and the character's height) fade with the blend share: at my side the pet sits on
	-- the shoulder as before; 2+ studs out (an ENGAGED pet fighting) it is drawn where the server has it
	local offW = rcf:VectorToWorldSpace(K.SHOULDER)
	local off = offW * k
	local y = server.Y + (rp.Y + offW.Y - server.Y) * k -- (the shoulder height scaled by k once, not k^2)
	return Vector3.new(ax + off.X, y, az + off.Z), share, rcf, d
end

-- a helper's spot behind me (index 1 / 2 = HELPER_A / HELPER_B); without a character behind the drawn fighter
function Me.HelperSpot(B, index)
	local off = (index == 2) and K.HELPER_B or K.HELPER_A
	local root = Me.Root()
	if root then
		return root.CFrame:PointToWorldSpace(off)
	end
	local f = B.fighterId and B.units[B.fighterId]
	local base = (f and f.drawn) or worldPoint(B, 0, 2, 0)
	return base + Vector3.new(off.X, off.Y - 0.5, off.Z)
end

-- the bench index (1 / 2) of my helper u, in slot order
function Me.HelperIndex(B, u)
	local i = 0
	for slot = 1, 4 do
		local h = B.mine[slot]
		if h and h.id ~= B.fighterId then
			i = i + 1
			if h == u then
				return i
			end
		end
	end
	return 1
end

-- per frame: my fighter / my helpers (positions + facing + bob + animation; the server never moves these parts)
-- wave 5 (bug #26): a dungeon fighter's first drawn spot is where its follower pet stood (PetController), so the pet
-- walks from the formation to the shoulder instead of popping there; nil = the shoulder as before
function Me.SeedFromFollower(B, u, target)
	if B.Mode ~= "Dungeon" or not LocalPlayer then
		return nil
	end
	if Mods.Pets == nil then
		Mods.Pets = optional(script.Parent, "PetController") or false
	end
	local pc = Mods.Pets
	if not pc or type(pc.GetFollowerInfo) ~= "function" then
		return nil
	end
	local ok, list = pcall(pc.GetFollowerInfo, LocalPlayer)
	if not ok or type(list) ~= "table" then
		return nil
	end
	local key = u.info and u.info.key
	for _, e in ipairs(list) do
		if e.Key == key and typeof(e.Model) == "Instance" then
			local okP, cf = pcall(e.Model.GetPivot, e.Model)
			if okP and typeof(cf) == "CFrame" and (cf.Position - target).Magnitude < 30 then
				return cf.Position
			end
		end
	end
	return nil
end

-- the active fighter unit of a player in battle B (mine: B.fighterId; others: their unit that is not on the bench)
function Me.FighterOf(B, userId)
	if userId == myUserId() and B.Fighter and B.fighterId and B.units[B.fighterId] then
		return B.units[B.fighterId]
	end
	for _, u in ipairs(B.list) do
		if u.owner == userId and not u.benched and u.side == 1 then
			return u
		end
	end
	return nil
end

function Me.SpotOf(u)
	if u.model and u.model.Parent then
		local ok, cf = pcall(u.model.GetPivot, u.model)
		if ok and typeof(cf) == "CFrame" then
			return cf.Position
		end
	end
	return u.drawn
end

-- before a dungeon floor goes: where every player's fighter was drawn (PetController's hand-over reads it)
function Me.RecordDrawn(B)
	local seen = {}
	for _, u in ipairs(B.list) do
		local uid = tonumber(u.owner)
		if uid and not seen[uid] then
			local f = Me.FighterOf(B, uid)
			if f then
				seen[uid] = true
				local pos = Me.SpotOf(f)
				if typeof(pos) == "Vector3" then
					St.lastDrawn[uid] = { Pos = pos, Key = f.info and f.info.key, At = os.clock() }
				end
			end
		end
	end
end

function Me.Draw(B, u, now, dt, x, z)
	if u.parked then
		return
	end
	local isFighter = u.id == B.fighterId or (B.fighterId == nil and not u.benched)
	local target, share, rcf, blendD
	if isFighter then
		target, share, rcf, blendD = Me.FighterTarget(B, u, x, z)
	else
		target, share = Me.HelperSpot(B, Me.HelperIndex(B, u)), 0.25
		-- a Buff: fly to the fighter and back (BUFF_FLY)
		if u.flyAt then
			local p = (now - u.flyAt) / K.BUFF_FLY
			local f = B.fighterId and B.units[B.fighterId]
			if p >= 1 or not f or not f.drawn then
				u.flyAt = nil
			else
				local k = sin(p * pi)
				target = target:Lerp(f.drawn + Vector3.new(0, 1.2, 0), k)
				share = 1
			end
		end
	end
	-- a swap: the two trade places along a little arc (SWAP_TIME)
	if u.swapAt and u.swapFrom then
		local p = (now - u.swapAt) / K.SWAP_TIME
		if p >= 1 then
			u.swapAt, u.swapFrom = nil, nil
		else
			local e = p * p * (3 - 2 * p)
			target = u.swapFrom:Lerp(target, e) + Vector3.new(0, sin(p * pi) * 1.6, 0)
			share = 1
		end
	end
	if not u.drawn then
		u.drawn = (isFighter and Me.SeedFromFollower(B, u, target)) or target
	else
		u.drawn = u.drawn:Lerp(target, lerpShare(share, dt))
	end
	-- facing: my fighter faces the enemy it fights (else where I look); helpers face where I look
	local want = nil
	local tgt = isFighter and ((u.target and B.units[u.target]) or (B.lock and B.units[B.lock])) or nil
	if tgt and tgt.model and not tgt.parked then
		local tp = unitCenter(B, tgt)
		local dx, dz = tp.X - u.drawn.X, tp.Z - u.drawn.Z
		if dx * dx + dz * dz > 0.01 then
			want = atan2(-dx, -dz)
		end
	end
	if not want then
		local look = (rcf or (Me.Root() and Me.Root().CFrame))
		if look then
			local lv = look.LookVector
			want = atan2(-lv.X, -lv.Z)
		end
	end
	u.wyaw = u.wyaw or (want or 0)
	if want and u.state ~= S_STUNNED then
		u.wyaw = u.wyaw + wrapAngle(want - u.wyaw) * (1 - exp(-K.FACE_RATE * dt))
	end
	-- the server's lunges (Hit events only: the pet attacks by itself, nothing is predicted) / hops / recoils and the
	-- pet's dash (zone-local -> world)
	local off = Vector3.new(0, 0, 0)
	if u.dashAt then
		off = off + zoneDir(B, u.dashX or 0, u.dashZ or 0) * (K.DASH_DIST * Me.DashAmount(u, now))
	end
	if u.lungeAt then
		local p = (now - u.lungeAt) / K.LUNGE_TIME
		if p >= 1 then
			u.lungeAt = nil
		elseif not u.lungeFx then -- (AttackFx's Strike pose replaces the lunge / recoil of an attack it played)
			off = off + zoneDir(B, u.lungeX or 0, u.lungeZ or 0) * (sin(p * pi) * (u.ranged and -K.RECOIL_DIST or K.LUNGE_DIST))
		end
	end
	if u.hopAt then
		local p = (now - u.hopAt) / K.HOP_TIME
		if p >= 1 then
			u.hopAt = nil
		elseif p > 0 then
			off = off + Vector3.new(0, sin(p * pi) * K.HOP_HEIGHT, 0)
		end
	end
	if u.hurtAt then
		local p = (now - u.hurtAt) / 0.18
		if p >= 1 then
			u.hurtAt = nil
		elseif not u.hurtFx then -- (AttackFx's Hurt pose replaces the nudge)
			off = off + zoneDir(B, u.hurtX or 0, u.hurtZ or 0) * (sin(p * pi) * 0.3)
		end
	end
	local down = u.state == S_DOWN or u.hp <= 0
	local stunned = u.state == S_STUNNED or down
	local bob = stunned and 0 or sin(now * 3.1 + u.phase) * K.BOB
	local p = u.drawn + off + Vector3.new(0, bob, 0)
	local cf = CFrame.new(p) * CFrame.Angles(0, u.wyaw, 0)
	-- no battle idle while my fighter moves under my input (or a helper flies / swaps)
	-- (bug #22: my walking only counts while the pet is at my side; an engaged pet keeps its battle idle)
	local busy = (isFighter and (u.state == S_MOVING or (Me.Walking() and (blendD == nil or blendD <= K.BLEND_DIST)))) or u.flyAt ~= nil or u.swapAt ~= nil
	-- a helper that only breathes (the battle idle) is posed every other frame, like the other pets (stepBattle)
	local animate = isFighter or u.poseSrc ~= "idle" or (St.frameNo + (u.slot or 0)) % 2 == 0
	local pose, body = Atk.PoseOf(u, now, down, busy, animate, p)
	if body then
		cf = cf * body
	end
	if u.rigid then
		if not animate then
			Units.CarryLoose(u, cf) -- (the wings keep their pose on the root this frame)
		end
		u.root.CFrame = cf
	else
		pcall(u.model.PivotTo, u.model, cf)
	end
	u.posed = true
	if animate and PetBuilder and not u.animBroken then
		local opts = u.animOpts
		local moving = rcf ~= nil and isFighter and u.state == S_MOVING
		opts.Flap = stunned and 0 or ((u.state == S_DASHING or u.dashAt or moving or u.flyAt) and 1.8 or 1)
		opts.Excited = (u.state == S_ATTACKING or u.state == S_CASTING) and 0.6 or 0
		opts.Pose = pose
		local ok = pcall(PetBuilder.Animate, u.model, now + u.phase, opts)
		if not ok then
			u.animBroken = true
		end
	end
	Units.UpdateStatus(B, u, now, cf)
end

local function moveDirection(hum)
	return hum.MoveDirection
end

-- the character walks under the player's input (Humanoid.MoveDirection)
function Me.Walking()
	local char = LocalPlayer and LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return false
	end
	local ok, dir = pcall(moveDirection, hum)
	return ok and typeof(dir) == "Vector3" and dir.Magnitude > 0.1
end

-- the zone-local direction (x, z) of a Dash event: ev.dir (an angle like Element's, or { x, z }), ev.dx / ev.dz, the
-- point ev.tx / ev.tz, else toward the pet's target / my lock, else where it faces (mine: where my character looks)
function Me.DashDir(B, u, ev)
	local dx, dz = nil, nil
	local dir = ev.dir
	if type(dir) == "number" then
		dx, dz = cos(dir), sin(dir)
	elseif type(dir) == "table" then
		dx, dz = tonumber(dir.x or dir.X or dir[1]), tonumber(dir.z or dir.Z or dir[2])
	end
	if not (dx and dz) and tonumber(ev.dx) and tonumber(ev.dz) then
		dx, dz = tonumber(ev.dx), tonumber(ev.dz)
	end
	if not (dx and dz) and tonumber(ev.tx) and tonumber(ev.tz) then
		dx, dz = tonumber(ev.tx) - u.x, tonumber(ev.tz) - u.z
	end
	if not (dx and dz) then
		local t = B.units[tonumber(ev.target) or u.target or (u.mine and B.lock) or -1]
		if t and t ~= u then
			dx, dz = t.x - u.x, t.z - u.z
		end
	end
	if not (dx and dz) and u.mine then
		local root = Me.Root()
		if root then
			-- world -> zone-local: the transpose of the zone's rotation
			local lv, b = root.CFrame.LookVector, B.basis
			dx, dz = b[4] * lv.X + b[7] * lv.Y + b[10] * lv.Z, b[6] * lv.X + b[9] * lv.Y + b[12] * lv.Z
		end
	end
	if not (dx and dz) then
		local yaw = u.wyaw or u.yaw or 0
		dx, dz = -sin(yaw), -cos(yaw)
	end
	local d = sqrt(dx * dx + dz * dz)
	if d < 1e-3 then
		return 0, -1
	end
	return dx / d, dz / d
end

-- starts the drawn dash of pet u (a streak out and back + a trail), once per event
-- my Swap: the incoming pet becomes my fighter (HUD, High detail), the out one goes to the bench, and the two trade
-- places along the SWAP_TIME arc from where they are drawn now. On the Swap's arrival (Net.Pre); a held auto-swap's
-- when it plays (fix round 2, I2-b: the KO'd fighter stays where it stood until its impact, and the arc starts from
-- the real spots: before, it started when the Swap played, after the pets had already slid most of the way)
function Me.Switch(B, ev)
	local old = B.fighterId
	B.fighterId = tonumber(ev["in"]) or B.fighterId
	local incoming = B.units[B.fighterId]
	if incoming then
		incoming.benched = false
		incoming.unbenchAt = nil
		B.fighterEvo = incoming.evo or 0
		Units.Rebuild(B, incoming)
	end
	local out = old and B.units[old]
	if out and out ~= incoming then
		out.benched = true
	end
	pcall(Hud.Rebuild)
	local now = os.clock()
	for _, u in ipairs({ incoming or false, out or false }) do
		if u and u.mine and u.drawn then
			u.swapFrom = u.drawn
			u.swapAt = now
		end
	end
end

function Me.StartDash(B, u, ev)
	u.dashEv = ev
	if not u.model or u.parked or u.hidden then
		return
	end
	u.dashX, u.dashZ = Me.DashDir(B, u, ev)
	u.dashAt = os.clock()
	local a = unitCenter(B, u)
	local b = a + zoneDir(B, u.dashX, u.dashZ) * K.DASH_DIST
	Fx.Trail(a, b, COLORS.Dodge, 6, K.DASH_TIME + 0.1)
	Fx.Burst(a, COLORS.Dodge, 8, 9, 0.4, 0.35, { up = 0.2, alpha = 0.2 })
	St.dashes = (St.dashes or 0) + 1
end

-- 0..1..0 of a running dash (quick out, a softer way back); clears it at the end
function Me.DashAmount(u, now)
	local p = (now - u.dashAt) / K.DASH_TIME
	if p >= 1 or p < 0 then
		u.dashAt = nil
		return 0
	end
	if p < 0.4 then
		local q = 1 - p / 0.4
		return 1 - q * q
	end
	local q = (p - 0.4) / 0.6
	return 1 - q * q * (3 - 2 * q)
end

-- client/MouseLock (the mouse lock option, a separate module: no hard dependency): Hold(reason) frees the cursor while
-- the result card / the LEAVE confirm is up, Release(reason) gives it back; idempotent per reason
function Me.MouseHold(reason, on)
	on = on == true
	if (St.mouseHolds[reason] == true) == on then
		return
	end
	if not Mods.MouseLock then
		local inst = Client:FindFirstChild("MouseLock")
		if inst then
			local ok, m = pcall(require, inst)
			Mods.MouseLock = (ok and type(m) == "table") and m or false
		end
	end
	local ML = Mods.MouseLock
	local fn = ML and ML[on and "Hold" or "Release"]
	if type(fn) == "function" then
		pcall(fn, reason)
	end
	St.mouseHolds[reason] = on or nil
end

-- the camera shake scale: ClientSettings.Get("Shake") (menu W3); 1 when the module is missing
function Me.ShakeScale()
	local hook = BattleController.Hooks.Shake
	if type(hook) == "function" then
		return hook() and 1 or 0
	end
	if Mods.Settings == nil then
		Mods.Settings = optional(Client, "ClientSettings") or false
	end
	local cs = Mods.Settings
	if cs and type(cs.Get) == "function" then
		local ok, v = pcall(cs.Get, "Shake")
		if ok then
			return v and 1 or 0
		end
	end
	return 1
end

-- a tiny, rare camera shake (my fighter hit hard / knocked out): Humanoid.CameraOffset, never the camera itself
function Me.Shake(amount, dur)
	local scale = Me.ShakeScale()
	St.shakeCount = (St.shakeCount or 0) + 1
	if scale <= 0 then
		return
	end
	local old = St.shake
	St.shake = { t0 = os.clock(), dur = dur or 0.18, amp = min(K.SHAKE_MAX, (amount or 0.2) * scale), base = old and old.base, last = old and old.last, hum = old and old.hum }
	BattleController._wake()
end

function Me.UpdateShake(now)
	local sh = St.shake
	if not sh then
		return
	end
	local char = LocalPlayer and LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	-- wave 5 (bug #15): the shake rides on the resting offset (the dungeon shoulder) and gives it back at the end; an
	-- offset someone else wrote meanwhile (DungeonController's shoulder on / off, a new character) becomes the base
	if hum then
		local cur = hum.CameraOffset
		if sh.hum ~= hum or sh.base == nil or sh.last == nil or (cur - sh.last).Magnitude > 1e-4 then
			sh.base = cur
			sh.hum = hum
		end
	end
	local p = (now - sh.t0) / sh.dur
	if p >= 1 or not hum then
		St.shake = nil
		if hum then
			hum.CameraOffset = sh.base or Vector3.new(0, 0, 0)
		end
		return
	end
	local a = sh.amp * (1 - p)
	local v = sh.base + Vector3.new(sin(now * 71) * a, cos(now * 63) * a * 0.6, 0)
	hum.CameraOffset = v
	sh.last = v
end

-- wave 5 (bug #15): a big attack (AttackFx's punch >= PUNCH_BIG: a rare+ special, a crit) punches the FOV, in a
-- dungeon only; the Camera shake setting does NOT gate it (player ruling 2026-10-28: Shake OFF = only the hit shakes
-- go; the punch is a short zoom, not a shake). MovementController owns the FOV
function Me.FovPunch(amount)
	local B = St.battle
	amount = tonumber(amount) or 0
	if not B or B.Mode ~= "Dungeon" or amount < K.PUNCH_BIG then
		return false
	end
	local mc = Hud.Movement()
	if mc and type(mc.FovPunch) == "function" then
		local ok = pcall(mc.FovPunch, K.FOV_PUNCH * min(1, amount / 0.4), K.FOV_PUNCH_TIME)
		return ok
	end
	return false
end

-- AttackFx's screen hooks (own pets only, AttackFx decides when): a soft glow along the screen edges (a Secret pet's
-- hit), on its own ScreenGui UNDER the battle HUD; edge-only and see-through, never over the fight's centre (spec
-- "Never hide the fight"). Built on the first use. (A signature's battle dim is a Lighting preset since Task 11:
-- Me.Dim; the HUD is never darkened.)
function Me.ScreenFx()
	local g = St.screenFx
	if g and g.gui.Parent then
		return g
	end
	local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	local gui = make("ScreenGui", { Name = "NimbusBattleFx", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = K.DISPLAY_ORDER - 3 })
	local edges = {}
	-- { position, size, gradient rotation (0 = opaque at the left) }: 9% of the height / 6% of the width deep
	for i, e in ipairs({
		{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.09), 90 },
		{ UDim2.fromScale(0, 0.91), UDim2.fromScale(1, 0.09), 270 },
		{ UDim2.fromScale(0, 0), UDim2.fromScale(0.06, 1), 0 },
		{ UDim2.fromScale(0.94, 0), UDim2.fromScale(0.06, 1), 180 },
	}) do
		local f = make("Frame", { Name = "Edge" .. i, Position = e[1], Size = e[2], BackgroundColor3 = COLORS.White, BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false }, gui)
		make("UIGradient", { Rotation = e[3], Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) }, f)
		edges[i] = f
	end
	gui.Parent = pg
	g = { gui = gui, edges = edges, glow = nil }
	St.screenFx = g
	return g
end

-- AttackFx.Hooks.ScreenGlow: the edges light up in `color` and fade over `seconds`
function Me.Glow(color, seconds)
	local g = Me.ScreenFx()
	if not g then
		return
	end
	g.glow = { t0 = os.clock(), dur = clamp(num(seconds, 0.35), 0.1, 1.5) }
	for _, f in ipairs(g.edges) do
		f.BackgroundColor3 = typeof(color) == "Color3" and color or COLORS.White
		f.Visible = true
	end
	BattleController._wake()
end

-- (Task 11) the battle dim's look: the world darker, a little desaturated and violet (Eclipse Nova's black sun); the
-- HUD and the effects' Neon stay bright. RELATIVE to the look under it (LightingStack.Value without the dim itself):
-- the arena (server ExposureCompensation -0.15, NimbusColor Brightness 0 / Saturation 0.14) -> -0.9 / -0.06 / -0.21,
-- and a dungeon battle (its own darker ColorCorrection) gets darker still, never brighter. Exposure / Brightness /
-- Saturation are added, the tint multiplies. LightingStack gives the look under it back on the Pop
Me.DIM_DELTA = { Exposure = -0.75, Brightness = -0.06, Saturation = -0.35, Tint = Color3.fromRGB(214, 198, 255) }

function Me.Lights()
	if Mods.Lights == nil then
		Mods.Lights = optional(Client, "LightingStack") or false
	end
	local ls = Mods.Lights
	return (ls and type(ls.Push) == "function" and type(ls.Pop) == "function") and ls or nil
end

-- the dim preset over what the battle shows now (a property whose instance is missing is left out)
function Me.DimPreset(ls)
	local d = Me.DIM_DELTA
	local function value(group, prop)
		if type(ls.Value) ~= "function" then
			return nil
		end
		local ok, v = pcall(ls.Value, group, prop, K.DIM_ID)
		return ok and v or nil
	end
	local preset = {}
	local exp = value("Lighting", "ExposureCompensation")
	if type(exp) == "number" then
		preset.Lighting = { ExposureCompensation = exp + d.Exposure }
	end
	local cc = {}
	local bri, sat, tint = value("ColorCorrection", "Brightness"), value("ColorCorrection", "Saturation"), value("ColorCorrection", "TintColor")
	if type(bri) == "number" then
		cc.Brightness = bri + d.Brightness
	end
	if type(sat) == "number" then
		cc.Saturation = max(-1, sat + d.Saturation)
	end
	if typeof(tint) == "Color3" then
		cc.TintColor = Color3.new(tint.R * d.Tint.R, tint.G * d.Tint.G, tint.B * d.Tint.B)
	end
	if next(cc) then
		preset.ColorCorrection = cc
	end
	return preset
end

-- AttackFx.Hooks.DimWorld (own pet only: AttackFx decides): the battle darkens for `seconds` (LightingStack preset
-- K.DIM_ID, in over DIM_IN; Me.UpdateScreenFx pops it over DIM_OUT when the time is up). `token` = the effect's own
-- token: Me.Undim(token) ends it early (that effect ended); `unit` = the caster's unit id: Me.UndimCaster(unit) ends it
-- on the caster's KO. A new dim replaces the old one (and its token: an older cast's end never lifts it).
function Me.Dim(seconds, token, unit)
	local ls = Me.Lights()
	if not ls then
		return false
	end
	if token == nil then
		token = true
	end
	St.dim = { t0 = os.clock(), dur = clamp(num(seconds, 0.6), 0.2, K.DIM_MAX), token = token, unit = unit }
	pcall(ls.Push, K.DIM_ID, Me.DimPreset(ls), K.DIM_IN)
	BattleController._wake()
	return true
end

-- the light comes back (over `fade` seconds, default DIM_OUT): token nil = whatever dims (a teardown), else only that
-- caster's dim. -> true when a dim ended
function Me.Undim(token, fade)
	local d = St.dim
	if not d or (token ~= nil and d.token ~= token) then
		return false
	end
	St.dim = nil
	local ls = Me.Lights()
	if ls then
		pcall(ls.Pop, K.DIM_ID, fade or K.DIM_OUT)
	end
	return true
end

-- the caster `unit` was knocked out: its battle dim (if the dim is its) ends now. -> true when a dim ended
function Me.UndimCaster(unit)
	local d = St.dim
	if not d or unit == nil or d.unit ~= unit then
		return false
	end
	return Me.Undim(d.token)
end

-- (Task 11b; original audio) the charges' own SoundFx sounds (Config.Audio.Sfx): "Inhale" = the inhale under a
-- Special's charge (PlaybackSpeed rising INHALE_PITCH[1] -> [2] to the release, a short fade in / out), "Shatter" = a
-- shattered charge. A missing id plays nothing and nothing breaks
function Me.Sound()
	if Mods.Sound == nil then
		Mods.Sound = optional(Client, "SoundFx") or false
	end
	return Mods.Sound or nil
end

-- AttackFx Hooks.Inhale: a token's first call starts the sound, a later one (the real Special taking over a press's
-- charge) retimes the same rise from where it is; others' pets at INHALE_OTHERS volume; INHALE_MAX at once
function Me.Inhale(seconds, token, mine)
	if token == nil then
		return false
	end
	seconds = clamp(num(seconds, 0), 0.05, 2)
	local rec = St.inhales[token]
	if not rec then
		local n, oldest = 0, nil
		for tk, r in pairs(St.inhales) do
			n = n + 1
			if not r.mine and (oldest == nil or r.start < St.inhales[oldest].start) then
				oldest = tk
			end
		end
		if mine and n >= K.INHALE_MAX and oldest ~= nil then
			Me.Hush(oldest) -- (fix round 1, M7) my own inhale (the cue this is for) never loses to others' pets'
			n = n - 1
		end
		local SF = n < K.INHALE_MAX and Me.Sound() or nil
		if not SF or type(SF.Play) ~= "function" then
			return false
		end
		local ok, s = pcall(SF.Play, "Inhale")
		if not ok or typeof(s) ~= "Instance" then
			return false
		end
		for tk, r in pairs(St.inhales) do
			if r.sound == s then
				St.inhales[tk] = nil -- (SoundFx's pool handed that sound out again)
			end
		end
		-- (fix round 2, M5') `start` (when it began) picks the oldest; t0 is the last retime
		rec = { sound = s, vol = s.Volume * (mine and 1 or K.INHALE_OTHERS), mine = mine == true, t0 = os.clock(), start = os.clock() }
		St.inhales[token] = rec
		s.PlaybackSpeed = K.INHALE_PITCH[1]
		s.Volume = 0
		pcall(Util.Tween, s, K.INHALE_IN, { Volume = rec.vol })
	end
	local stamp = os.clock()
	rec.t0, rec.dur, rec.stamp = stamp, seconds, stamp
	pcall(Util.Tween, rec.sound, seconds, { PlaybackSpeed = K.INHALE_PITCH[2] }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(seconds, function()
		if St.inhales[token] == rec and rec.stamp == stamp then
			Me.Hush(token)
		end
	end)
	return true
end

-- AttackFx Hooks.Hush (the charge ended early) and the release: the inhale fades out
function Me.Hush(token)
	local rec = token ~= nil and St.inhales[token] or nil
	if not rec then
		return
	end
	St.inhales[token] = nil
	if rec.sound and rec.sound.Parent then
		pcall(Util.Tween, rec.sound, K.INHALE_OUT, { Volume = 0 })
	end
end

-- AttackFx Hooks.Shatter: the "interrupted" cue of a broken press
function Me.ShatterSound(mine)
	local SF = Me.Sound()
	if SF and type(SF.Play) == "function" then
		local ok, s = pcall(SF.Play, "Shatter")
		if ok and typeof(s) == "Instance" and not mine then
			s.Volume = s.Volume * K.INHALE_OTHERS
		end
	end
end

-- per frame while a glow / dim shows; -> true while one does
function Me.UpdateScreenFx(now)
	if St.dim and now - St.dim.t0 >= St.dim.dur then
		Me.Undim(nil, K.DIM_OUT)
	end
	local g = St.screenFx
	if not g or not g.glow then
		return St.dim ~= nil
	end
	if g.glow then
		local p = (now - g.glow.t0) / g.glow.dur
		local a = (p >= 1) and 1 or (0.45 + 0.55 * p * p) -- at most 55% opaque, at the very edge
		for _, f in ipairs(g.edges) do
			f.BackgroundTransparency = a
			f.Visible = p < 1
		end
		if p >= 1 then
			g.glow = nil
		end
	end
	return g.glow ~= nil or St.dim ~= nil
end

----------------------------------------------------------------------
-- Pet attack VFX (docs/superpowers/specs/2026-10-23-pet-attack-vfx-design.md "Architecture", "Timing without server
-- changes", "Budgets, quality, readability"; plan Task 7). client/Controllers/AttackFx plays every pet attack FIRST;
-- each handler keeps its cube Fx.* as the fallback (AttackFx.Play false: the budget, Low limits, a missing texture,
-- an error). Bosses keep their own attack visuals (out of scope); a boss's hit on MY pet plays its Hurt reaction.
----------------------------------------------------------------------
local IDENTITY = CFrame.new()
local SUPPORT_KINDS = { Heal = true, Shield = true, Rally = true, Haste = true }
-- a helper buff's Effect (BattleCatalog.Buffs) -> the support special whose look it borrows
local BUFF_LOOK = { Heal = "Heal", Regen = "Heal", Shield = "Shield", Taken = "Shield", Damage = "Rally", Lifesteal = "Rally", Speed = "Haste", AttackSpeed = "Haste", Chill = "Haste" }
-- the events AttackFx plays (on arrival: Net.Events)
Atk.EVENTS = { [EV.Hit] = true, [EV.Special] = true, [EV.Element or "Element"] = true, [EV.KO] = true, [EV.Buff or "Buff"] = true, [EV.Swap or "Swap"] = true }
Atk.bodyOpts = { Pose = nil } -- (one table for every PetBuilder.PoseBody call)

-- AttackFx's hooks go to Me: camera punch = Me.Shake (the Shake setting and SHAKE_MAX apply), the edge glow, and a
-- signature's battle dim (Me.Dim / Me.Undim, Task 11)
function Atk.Hook(m)
	if type(m) ~= "table" or type(m.Hooks) ~= "table" then
		return
	end
	m.Hooks.Punch = function(amount, seconds)
		Me.Shake(amount, seconds)
		Me.FovPunch(amount)
	end
	m.Hooks.ScreenGlow = function(color, seconds)
		Me.Glow(color, seconds)
	end
	m.Hooks.DimWorld = function(seconds, token, unit)
		Me.Dim(seconds, token, unit)
	end
	m.Hooks.Undim = function(token)
		Me.Undim(token)
	end
	-- (Task 11b) the Special's charge sounds
	m.Hooks.Inhale = function(seconds, token, mine)
		return Me.Inhale(seconds, token, mine) -- (-> true when the sound plays)
	end
	m.Hooks.Hush = function(token)
		Me.Hush(token)
	end
	m.Hooks.Shatter = function(mine)
		Me.ShatterSound(mine)
	end
end

-- client/Controllers/AttackFx (nil when missing); on the first load its hooks go to Me (Atk.Hook) and the Graphics
-- setting is applied
function Atk.Mod()
	if Mods.AttackFx == nil then
		local m = optional(script.Parent, "AttackFx")
		Mods.AttackFx = (m and type(m.Play) == "function" and type(m.Pose) == "function" and type(m.Update) == "function") and m or false
		if Mods.AttackFx then
			Atk.Hook(m)
		end
		Atk.SyncQuality()
	end
	return Mods.AttackFx or nil
end

-- GraphicsQuality.Effective() -> AttackFx.SetQuality (at the first load and on every Graphics change, like PetFx;
-- before GraphicsQuality has started AttackFx follows it by itself)
function Atk.SyncQuality()
	local AF = Mods.AttackFx
	if not AF or type(AF.SetQuality) ~= "function" then
		return
	end
	if Mods.Gfx == nil then
		Mods.Gfx = optional(Client, "GraphicsQuality") or false
	end
	local gq = Mods.Gfx
	if gq and type(gq.Effective) == "function" and type(gq._St) == "table" and gq._St.Started then
		local ok, mode = pcall(gq.Effective)
		if ok and (mode == "Low" or mode == "High") then
			pcall(AF.SetQuality, mode)
			St.fxLow = mode == "Low" -- (no battle idle on the light path: Atk.Idles)
		end
	end
end

-- what a unit's effects look like: AttackFxCatalog.Unit(info) = { Element, Rarity, Stage, PetId, Ranged } (cached)
function Atk.Look(u)
	if u.fxLook then
		return u.fxLook
	end
	if Mods.FxCat == nil then
		Mods.FxCat = optional(Shared, "AttackFxCatalog") or false
	end
	local look = nil
	if Mods.FxCat and type(Mods.FxCat.Unit) == "function" then
		local ok, r = pcall(Mods.FxCat.Unit, u.info)
		look = ok and type(r) == "table" and r or nil
	end
	u.fxLook = look or {}
	return u.fxLook
end

-- drawn on this screen (not parked, not arriving, not another player's helper on the bench)
function Atk.Drawable(u)
	return u ~= nil and not u.gone and not u.parked and not u.hidden and not (u.benched and not u.mine)
end

-- an AttackFx side: the unit's model while it is drawn, else its point
function Atk.Side(B, u)
	return { Unit = u.id, Model = (u.model and not u.parked and not u.hidden) and u.model or nil, Pos = unitCenter(B, u) }
end

local function groundOf(B, u)
	return worldPoint(B, u.x, 0, u.z).Y
end

-- a zone-local angle (direction (cos a, sin a) on the floor, BattleSim's) as AttackFx's WORLD yaw
local function worldAngle(B, a)
	local w = zoneDir(B, cos(a), sin(a))
	return atan2(w.Z, w.X)
end

-- AttackFx.Play (pcall'd) -> true only when it plays (never during the End grace: the cube fallback then)
function Atk.Play(ctx)
	local AF = Atk.Mod()
	if not AF or St.fxEndAt then
		return false
	end
	local ok, played = pcall(AF.Play, ctx)
	return ok and played == true
end

function Atk.Cancel(id)
	local AF = Mods.AttackFx
	if AF and type(AF.Cancel) == "function" then
		pcall(AF.Cancel, id)
	end
end

-- every effect and pose ends now (a teardown: Leave of my team, Net.Cleanup, Stop); a pending End grace is over too
function Atk.ClearAll()
	St.fxEndAt = nil
	St.cheers = {}
	St.pre = nil -- (Task 11b: AttackFx.ClearAll drops the predicted charge too)
	for token in pairs(St.inhales) do
		Me.Hush(token)
	end
	local AF = Mods.AttackFx
	if AF and type(AF.ClearAll) == "function" then
		pcall(AF.ClearAll)
	end
	Me.Undim(nil, K.DIM_CUT) -- (Task 11) a torn-down battle never stays dark (AttackFx's own Undim came first if it could)
end

-- the battle's end (the sim's End event, or the End message if it comes first): no new effect (Atk.Play refuses),
-- the live ones get FX_END_GRACE seconds, then ClearAll; once per battle, so a late End event never cuts the
-- winners' Victory that starts after the grace
function Atk.EndSoon(B)
	if B.fxGrace or not Mods.AttackFx then
		return
	end
	B.fxGrace = true
	if not St.fxEndAt then
		St.fxEndAt = os.clock() + K.FX_END_GRACE
	end
	BattleController._wake()
end

function Atk.Update(now)
	local AF = Mods.AttackFx
	if not AF then
		return
	end
	St.fxFrame = St.frameNo -- (fix round 2, M8) the frame loop stepped AttackFx in this frame (StepsAttackFx)
	-- (Task 11b) a pressed SPECIAL whose event did not come within PRESS_WAIT: its predicted charge shatters
	local pre = St.pre
	if pre and now >= pre.untilT then
		Atk.Shatter(pre.B)
	end
	local ok, err = pcall(AF.Update, now)
	if not ok then
		warnOnce("attackfx", "AttackFx.Update failed: " .. tostring(err))
	end
	-- the End grace: over at its deadline, or as soon as nothing plays any more
	if St.fxEndAt and (now >= St.fxEndAt or not Atk.Busy()) then
		local cheers = St.cheers or {}
		Atk.ClearAll()
		St.cheers = cheers
	end
	-- the winners' cheers wait for the grace (Net.Cheer): Victory, else the old hop
	local list = St.cheers
	if not St.fxEndAt and list and #list > 0 then
		local i = 1
		while i <= #list do
			local c = list[i]
			if now >= c.at then
				table.remove(list, i)
				if c.B == St.battle and not c.u.gone and not c.u.parked and not Atk.Lying(c.u) and not Atk.Victory(c.B, c.u, 0) then
					c.u.hopAt = now
				end
			else
				i = i + 1
			end
		end
	end
end

-- AttackFx still plays something (the frame loop stays awake)
function Atk.Busy()
	local s = Atk.Stats()
	return s ~= nil and ((s.Live or 0) + (s.Stepped or 0)) > 0
end

-- something of the pet attack VFX still needs frames (live effects, the End grace, cheers waiting)
function Atk.Pending()
	return St.fxEndAt ~= nil or (St.cheers ~= nil and #St.cheers > 0) or Atk.Busy()
end

function Atk.Stats()
	local AF = Mods.AttackFx
	if not AF or type(AF.Stats) ~= "function" then
		return nil
	end
	local ok, s = pcall(AF.Stats)
	return (ok and type(s) == "table") and s or nil
end

-- the poses can be drawn (PetBuilder.PoseBody / Animate opts.Pose in this build)
function Atk.Posable()
	return PetBuilder ~= nil and type(PetBuilder.PoseBody) == "function"
end

-- AttackFx drives this unit's body: loaded, poses drawable, and its last attack here was not refused (else the old
-- crouch / lunge / nudge come back until a play succeeds again)
function Atk.Drives(u)
	return (Mods.AttackFx and Atk.Posable() and u.fxDriven ~= false) and true or false
end

-- (Task 11 fix round 2, I1) the living enemies of `u` inside a Storm's zone: BattleSim's castSpecial puts the zone at the
-- aimed target (ev.tx, ev.tz) with radius Specials.Storm.Radius (BattleCatalog, the same table the sim reads) and its
-- tickZones hits a body on the floor whose edge reaches the circle (inCircle: d <= r + its radius). The sim's Special
-- event names only the aimed target, so the effect's targets are gathered here, in the units' list order
local function stormZone(B, u, ev)
	local S = SPECIALS.Storm
	local r = type(S) == "table" and tonumber(S.Radius) or nil
	local x, z = tonumber(ev.tx), tonumber(ev.tz)
	local out = {}
	if not (r and x and z) then
		return out
	end
	for _, e in ipairs(B.list) do
		if e.side ~= u.side and not e.gone and not e.benched and e.hp > 0 and e.state ~= S_DOWN then
			local dx, dz = e.x - x, e.z - z
			local reach = r + num(e.radius, 0)
			if dx * dx + dz * dz <= reach * reach then
				out[#out + 1] = e
			end
		end
	end
	return out
end

-- the hits of a played Special / Element on these sides are AttackFx's (their Hurt pose: no nudge)
local function cover(B, to, dueAt)
	for _, side in ipairs(to) do
		local t = side.Unit and B.units[side.Unit]
		if t then
			t.fxHitUntil = dueAt + K.FX_COVER
		end
	end
end

-- a play's look from the unit (AttackFxCatalog.Unit): Element (unless given), Rarity, Stage, PetId (unless given;
-- false = none: a helper buff never plays its pet's signature special)
local function lookCtx(u, ctx)
	local look = Atk.Look(u)
	ctx.Element = ctx.Element or look.Element
	ctx.Rarity = look.Rarity
	ctx.Stage = look.Stage
	if ctx.PetId == nil then
		ctx.PetId = look.PetId
	elseif ctx.PetId == false then
		ctx.PetId = nil
	end
	return ctx
end

-- a Hit: a pet's plain attack (melee swipe / ranged shot; Miss = it flies past), a boss's hit on MY pet (its Hurt;
-- other players' pets keep the nudge: a boss slam can hit a dozen pets and the budget is for the attacks). The damage
-- of a special / element / zone / burn is drawn by its own event.
-- (Task 10 review I1, Ruling 17) a hit the victim's shield absorbs: the bubble ripples (ShieldHit) on the victim at the
-- hit, in the look of the pet whose Shield it is (u.shieldBy while its shield lasts: u.shieldUntil), else the victim's
-- own. Never on a boss; a boss's hit ripples only MY pets (like its Hurt: one slam can hit a dozen pets).
-- (re-review M8) a zone / burn tick (`tick`) ripples only RIPPLE_TICK_GAP after the unit's last ripple (a Linger zone
-- ticks every 0.5 s on every shielded pet in it); a hit from an attacker always ripples
function Atk.ShieldHit(B, v, a, dueAt, tick)
	if v.isBoss or not v.model or not Atk.Drawable(v) or (a and a.isBoss and not v.mine) then
		return false
	end
	if tick and v.rippleAt and dueAt - v.rippleAt < K.RIPPLE_TICK_GAP then
		return false
	end
	-- (re-review M9) the caster's look only while its shield lasts: a shield the client never saw cast (a rejoin
	-- snapshot) ripples in the victim's own look, not in a stale caster's
	if v.shieldBy and not ((tonumber(v.shieldUntil) or 0) > os.clock()) then
		v.shieldBy = nil
	end
	local by = v.shieldBy and B.units[v.shieldBy] or nil
	local played = Atk.Play(lookCtx(by or v, { Attack = "ShieldHit", PetId = false, From = Atk.Side(B, v), Mine = v.mine == true, DueAt = dueAt, Ground = groundOf(B, v) }))
	if played then
		v.rippleAt = dueAt
	end
	return played
end

-- the Hit's own play (Atk.Hit): its result and the seconds its impact lands after dueAt (a ranged shot's flight)
local function hitPlay(B, ev, dueAt, v, a)
	if ev.special or ev.element or ev.zone or ev.burn then
		return "none", 0
	end
	if ev.tele or (a and a.isBoss) then
		if ev.miss or v.isBoss or not v.mine or not Atk.Drawable(v) then
			return "none", 0
		end
		local el = a and Atk.Look(a).Element or nil
		return Atk.Play(lookCtx(v, { Attack = "Hurt", Element = el, From = Atk.Side(B, v), Mine = true, Crit = ev.crit == true, DueAt = dueAt, Ground = groundOf(B, v) })), 0
	end
	if not a or not Atk.Drawable(a) then
		return "none", 0
	end
	local ctx = lookCtx(a, {
		Attack = a.ranged and "Ranged" or "Melee", From = Atk.Side(B, a), To = Atk.Side(B, v), Mine = a.mine == true,
		Crit = ev.crit == true, Strong = num(ev.elem, 1) > 1, Miss = ev.miss == true, DueAt = dueAt, Ground = groundOf(B, a),
	})
	local played = Atk.Play(ctx)
	a.fxDriven = played
	-- a ranged shot keeps its flight (AttackFx MinTravel): its impact may land after the event's time; Net.Events
	-- then plays the Hit (number, flash) and the victim's next events that much later, so they land with the shot
	local late = played and tonumber(ctx.ImpactLate) or 0
	if late == late and late > 0 then
		ev.fxLate = min(late, K.FX_LATE_MAX)
		return played, ev.fxLate
	end
	return played, 0
end

function Atk.Hit(B, ev, dueAt)
	local v = B.units[tonumber(ev.to) or -1]
	local a = ev.from ~= nil and B.units[tonumber(ev.from) or -1] or nil
	if not v or (ev.from ~= nil and not a) then
		return nil
	end
	local played, late = hitPlay(B, ev, dueAt, v, a)
	-- (any absorbed hit: a plain attack, a special's, an element's, a zone's; the attack's own effect is apart). After
	-- the hit's play (re-review I3): a ranged shot's ripple lands with the shot (dueAt + its late), like the BLOCK
	-- number, the Hurt pose and the impact (Net.Events holds them by ev.fxLate)
	if num(ev.absorbed, 0) > 0 and not ev.miss then
		Atk.ShieldHit(B, v, a, dueAt + late, (ev.zone or ev.burn) and true or false)
	end
	return played
end

-- (Task 11b) my SPECIAL press: when my own view says it can go (my fighter drawn, it has a special, the meter full in
-- the latest snapshot, not stunned / casting / down, the fight on), its charge shows at once on my fighter
-- (AttackFx.Precharge: the glow + motes, the rim, the inhale, the held Cast pose), aimed at my lock (else its snapshot
-- target). Its Special event takes it over (Atk.Special: impact still on the event's time); a rejected Order (Net.Pre)
-- or PRESS_WAIT without the event (Atk.Update) shatters it
function Atk.PreCharge(B, now)
	local f = B and B.fighterId and B.units[B.fighterId] or nil
	-- (fix round 2) never on a fighter whose KO arrived (Atk.Lying): a held auto-swap keeps it my fighter till its impact
	if not f or B.ended or B.simEnded or St.fxEndAt or not f.model or not Atk.Drawable(f) or Atk.Lying(f) then
		return false
	end
	local kind = type(f.special) == "table" and f.special.Kind or nil
	if type(kind) ~= "string" or kind == "" or num(f.meter, 0) < METER_MAX or num(f.hp, 0) <= 0 then
		return false
	end
	if f.state == S_STUNNED or f.state == S_CASTING or f.state == S_DOWN or f.state == S_BENCHED then
		return false
	end
	if St.pre and St.pre.B == B and St.pre.unit == f.id and now < St.pre.untilT then
		return false -- (fix round 1, M4) a second press while the first waits: one prediction (the sim answers the first)
	end
	local AF = Atk.Mod()
	if not AF or type(AF.Precharge) ~= "function" then
		return false
	end
	local tgt = (B.lock and B.units[B.lock]) or (f.target and B.units[f.target]) or nil
	local to = nil
	if tgt and not tgt.gone and not SUPPORT_KINDS[kind] then
		to = { Atk.Side(B, tgt) }
	end
	local ok, played = pcall(AF.Precharge, lookCtx(f, {
		Kind = kind, From = Atk.Side(B, f), To = to, Mine = true, Seconds = K.PRESS_WAIT, Ground = groundOf(B, f), Now = now,
	}))
	if ok and played == true then
		St.pre = { B = B, unit = f.id, t0 = now, untilT = now + K.PRESS_WAIT }
		return true
	end
	return false
end

-- (Task 11b) the predicted charge breaks (refused / no event): AttackFx's shards + Recoil + the "interrupted" sound;
-- `quiet` = it just fades (its Special came but could not play). (fix round 1, I3 / M5) quiet too when the fighter is
-- no longer up (KO'd: its KO arrived or it is drawn down) or no longer my fighter (swapped out): no shards, Recoil or
-- "interrupted" sound on a downed or benched pet
function Atk.Shatter(B, quiet)
	local p = St.pre
	St.pre = nil
	local AF = Mods.AttackFx
	if not p or not AF or type(AF.Shatter) ~= "function" then
		return false
	end
	local PB = p.B or B
	local u = PB and PB.units[p.unit]
	if not u or u.gone or u.parked or u.benched or Atk.Lying(u) or (PB.fighterId ~= nil and PB.fighterId ~= p.unit) then
		quiet = true
	end
	local ok, r = pcall(AF.Shatter, p.unit, os.clock(), quiet == true)
	return ok and r == true
end

-- a Special: the caster's kind (its signature for the 12 top pets: PetId), at its targets / allies / the aimed spot.
-- (Task 11b) my pressed Special takes over its predicted charge (Precharged: backdated to the press, impact on dueAt);
-- every other one (bots, NPCs, allies, enemies, my pet with no press) gets its charge back: LateMax, the impact up to
-- LATE_MAX after dueAt (ev.fxSpLate: Net.Events holds this special's hits, the KOs they cause and a last gasp till then).
-- A Pounce never lands late: the server moves a pouncing bot onto its target at the event, its leap must land then
function Atk.Special(B, ev, dueAt)
	local u = B.units[tonumber(ev.unit) or -1]
	if not u then
		return nil
	end
	if u.isBoss or not Atk.Drawable(u) then
		return "none"
	end
	local kind = tostring(ev.kind or "")
	local to, seen = {}, {}
	local function add(id)
		local t = B.units[tonumber(id) or -1]
		if t and not seen[t] and not t.gone then
			seen[t] = true
			to[#to + 1] = Atk.Side(B, t)
		end
	end
	if kind == "Heal" then
		for _, h in ipairs(type(ev.heals) == "table" and ev.heals or {}) do
			add(type(h) == "table" and h[1] or nil)
		end
	elseif kind == "Shield" then
		for _, id in ipairs(type(ev.shields) == "table" and ev.shields or {}) do
			add(id)
		end
	else
		add(ev.target) -- the aimed target first (AttackFx aims at To[1])
		for _, id in ipairs(type(ev.targets) == "table" and ev.targets or {}) do
			add(id)
		end
		if kind == "Storm" then -- (fix round 2, I1) + every other enemy in the zone (the event carries only the aimed one)
			for _, e in ipairs(stormZone(B, u, ev)) do
				add(e.id)
			end
		end
	end
	if #to == 0 then
		if SUPPORT_KINDS[kind] then
			add(u.id)
		else
			to[1] = { Pos = worldPoint(B, num(ev.tx, u.x), u.centerY or 1.5, num(ev.tz, u.z)) } -- (nobody in reach)
		end
	end
	local pre = St.pre
	local precharged = pre ~= nil and pre.B == B and pre.unit == u.id
	if precharged then
		St.pre = nil
	end
	local ctx = lookCtx(u, {
		Attack = "Special", Kind = kind, From = Atk.Side(B, u), To = to, Mine = u.mine == true, DueAt = dueAt,
		Angle = tonumber(ev.angle) and worldAngle(B, tonumber(ev.angle)) or nil, Ground = groundOf(B, u),
		Precharged = precharged or nil, LateMax = (not precharged and kind ~= "Pounce") and K.LATE_MAX or nil,
	})
	local played = Atk.Play(ctx)
	u.fxDriven = played
	if precharged and not played then
		St.pre = pre
		Atk.Shatter(B, true) -- (the Special came but could not play: its prediction fades, no "interrupted" cue)
	end
	if played then
		local late = tonumber(ctx.ImpactLate) or 0
		if late == late and late > 0 then
			ev.fxSpLate = min(late, K.LATE_MAX)
		end
		cover(B, to, dueAt)
		if kind == "Storm" then
			u.stormFxUntil = dueAt + 1 -- its Zone draws only the damage field (AttackFx's cloud rains)
		end
	end
	return played
end

-- an element attack (Cone / Circle / Line of BattleCatalog.ElementAttacks) along the event's aim
function Atk.Element(B, ev, dueAt)
	local u = B.units[tonumber(ev.unit) or -1]
	if not u then
		return nil
	end
	if u.isBoss or not Atk.Drawable(u) then
		return "none"
	end
	Atk.Look(u) -- (loads AttackFxCatalog)
	local cat = Mods.FxCat or nil
	local element = ev.element
	if not (cat and type(cat.Elements) == "table" and type(element) == "string" and cat.Elements[element]) then
		element = nil -- (lookCtx: the unit's own)
	end
	local shape = ev.shape
	local def = BattleCatalog and type(BattleCatalog.ElementAttacks) == "table" and BattleCatalog.ElementAttacks[ev.element] or nil
	local radius, length = nil, nil
	if type(def) == "table" then
		if shape == "Line" then
			length = tonumber(def.Length)
		elseif shape == "Circle" then
			radius = tonumber(def.Radius)
		else
			radius = tonumber(def.Length)
		end
	end
	-- the targets, the one nearest the aimed point first (AttackFx aims at To[1])
	local tx, tz = num(ev.tx, u.x), num(ev.tz, u.z)
	local list = {}
	for _, id in ipairs(type(ev.targets) == "table" and ev.targets or {}) do
		local t = B.units[tonumber(id) or -1]
		if t and not t.gone then
			list[#list + 1] = t
		end
	end
	table.sort(list, function(p, q)
		local dp = (p.x - tx) * (p.x - tx) + (p.z - tz) * (p.z - tz)
		local dq = (q.x - tx) * (q.x - tx) + (q.z - tz) * (q.z - tz)
		if dp ~= dq then
			return dp < dq
		end
		return p.id < q.id
	end)
	local to = {}
	for i, t in ipairs(list) do
		to[i] = Atk.Side(B, t)
	end
	local played = Atk.Play(lookCtx(u, {
		Attack = "Element", Shape = shape, Element = element, From = Atk.Side(B, u), To = (#to > 0) and to or nil,
		Angle = worldAngle(B, num(ev.angle, 0)), Radius = radius, Length = length, Mine = u.mine == true, DueAt = dueAt,
		Ground = groundOf(B, u),
	}))
	u.fxDriven = played
	if played then
		cover(B, to, dueAt)
	end
	return played
end

-- a KO: the element-coloured poof + the Ko pose (tumbles, then holds: the pet lies until it is parked)
function Atk.Ko(B, ev, dueAt)
	local u = B.units[tonumber(ev.unit) or -1]
	if not u then
		return nil
	end
	if u.isBoss or not u.model or not Atk.Drawable(u) then
		return "none"
	end
	local played = Atk.Play(lookCtx(u, { Attack = "Ko", From = Atk.Side(B, u), Mine = u.mine == true, DueAt = dueAt, Ground = groundOf(B, u) }))
	if played then
		u.koAt = dueAt
		u.poofed = true -- (AttackFx's poof replaces the cube poof)
	end
	return played
end

-- a helper's buff on its fighter: the support special it is like (Heal / Shield / Rally / Haste) on the fighter
function Atk.Buff(B, ev, dueAt)
	local h = B.units[tonumber(ev.unit) or -1]
	local f = B.units[tonumber(ev.target) or -1]
	if not h or not f then
		return nil
	end
	if f.isBoss or not f.model or not Atk.Drawable(f) then
		return "none"
	end
	local def = BattleCatalog and type(BattleCatalog.Buffs) == "table" and BattleCatalog.Buffs[tostring(ev.kind)] or nil
	local kind = BUFF_LOOK[(type(def) == "table" and def.Effect) or tostring(ev.kind)] or "Rally"
	-- (another player's helper is not drawn: the buff rises from its fighter)
	local from = (h.model and Atk.Drawable(h)) and Atk.Side(B, h) or { Pos = unitCenter(B, f) }
	return Atk.Play(lookCtx(h, { Attack = "Special", Kind = kind, PetId = false, From = from, To = { Atk.Side(B, f) }, Mine = h.mine == true, DueAt = dueAt, Ground = groundOf(B, f) }))
end

-- a Swap: the incoming pet's entrance (Victory: hop-spin + sparkles)
function Atk.Swap(B, ev, dueAt)
	local inc = B.units[tonumber(ev["in"]) or -1]
	if not inc then
		return nil
	end
	if inc.isBoss or not inc.model or not Atk.Drawable(inc) then
		return "none"
	end
	return Atk.Play(lookCtx(inc, { Attack = "Victory", From = Atk.Side(B, inc), Mine = inc.mine == true, DueAt = dueAt, Ground = groundOf(B, inc) }))
end

-- the winners' cheer (Net.End): Victory after `delay` seconds; false = the old hop
-- a pet that is KO'd (its Ko played, or drawn down) lies until it is parked: it never cheers (Task 8 fix round 3: the
-- KO pose pin; a KO in the End batch had the pet hop up into Victory 1.4 s after the End)
function Atk.Lying(u)
	return u.koAt ~= nil or u.state == S_DOWN or (tonumber(u.hp) or 1) <= 0
end

function Atk.Victory(B, u, delay)
	if not Atk.Mod() or u.isBoss or not u.model or not Atk.Drawable(u) then
		return false
	end
	return Atk.Play(lookCtx(u, { Attack = "Victory", From = Atk.Side(B, u), Mine = u.mine == true, Now = os.clock() + delay, Ground = groundOf(B, u) }))
end

-- one event: true = AttackFx plays it (the handler draws no cube effect), false = refused (the handler's cube Fx.*),
-- "none" = nothing of AttackFx's, nil = a unit it names is not known yet (asked again when the event plays)
function Atk.Event(B, ev, dueAt)
	if B.ended or not Atk.Mod() then
		return "none"
	end
	local t = ev.type
	if t == EV.Hit then
		return Atk.Hit(B, ev, dueAt)
	elseif t == EV.Special then
		return Atk.Special(B, ev, dueAt)
	elseif t == (EV.Element or "Element") then
		return Atk.Element(B, ev, dueAt)
	elseif t == EV.KO then
		return Atk.Ko(B, ev, dueAt)
	elseif t == (EV.Buff or "Buff") then
		return Atk.Buff(B, ev, dueAt)
	elseif t == (EV.Swap or "Swap") then
		return Atk.Swap(B, ev, dueAt)
	end
	return "none"
end

-- an event ARRIVES (Net.Events): its effect starts now with the impact due when the event plays on the render clock
-- (`lead` seconds from now: the charge beat; AttackFx shortens the charge when the lead is short)
function Atk.Arrive(B, ev, lead)
	if not Atk.EVENTS[ev.type] then
		return
	end
	local ok, r = pcall(Atk.Event, B, ev, os.clock() + lead)
	if not ok then
		warnOnce("attackfx_" .. tostring(ev.type), "AttackFx for " .. tostring(ev.type) .. " failed: " .. tostring(r))
	elseif r ~= nil then
		B.fxEv[ev] = r
	end
end

-- the handler's answer when the event plays: did AttackFx play it? (an event that arrived before a unit it names was
-- known is played now, impact at once)
function Atk.Result(B, ev)
	local r = B.fxEv[ev]
	if r ~= nil then
		B.fxEv[ev] = nil
	else
		local ok, res = pcall(Atk.Event, B, ev, os.clock())
		r = ok and res or false
	end
	return r == true
end

-- PetBuilder.PoseBody of a pose (identity without one)
local function poseBody(pose)
	Atk.bodyOpts.Pose = pose
	local ok, cf = pcall(PetBuilder.PoseBody, Atk.bodyOpts)
	Atk.bodyOpts.Pose = nil
	return (ok and typeof(cf) == "CFrame") and cf or IDENTITY
end

-- the battle idle (PetPoses IdleBattle: breathing, a glance every 2-4 s) shows while AttackFx drives the unit and
-- nothing else does: not on Low graphics (the light path keeps the old drawing), not while down, stunned, winding,
-- dashing or moving under the player's input (my fighter: `busy`), never on a boss
function Atk.Idles(u, down, busy)
	return not busy and not down and not u.windup and not St.fxLow and u.state ~= S_STUNNED and u.state ~= S_DASHING
		and not u.dashAt and Atk.Drives(u)
end

-- the pose a battle pet shows now -> pose (PetBuilder.Animate opts.Pose) and its body offset (studs x the build
-- scale, for the root write: root = frame * body), or nil, nil (no pose: exactly the old drawing). In order:
-- AttackFx's pose (its crossfade honoured: Prev -> current over Blend); the Ko pose held after AttackFx let it go
-- (the End's ClearAll: the pet still lies there); PetPoses' Windup held while the snapshot says Winding (the dash
-- cue's crouch, for a unit AttackFx drives); the battle idle (Atk.Idles; P = time + a per-unit phase, so the pets do
-- not breathe or glance in step). A switch between those sources crossfades over AttackFx.CROSSFADE like AttackFx's
-- own Prev / Blend: the body blends, Animate keeps the previous pose for the first half. `base` = the unit's drawn spot
-- (world, before the pose): AttackFx.Pose shortens a Pounce leap by what the server's slide to the target has covered.
function Atk.PoseOf(u, now, down, busy, animate, base)
	local AF = Mods.AttackFx
	if not AF or u.isBoss or not Atk.Posable() then
		return nil, nil
	end
	if animate == false and not u.poseSwitch and u.poseSrc ~= "fx" then
		return u.poseLast, u.poseScaled -- a strided frame: the last pose rides along (Units.CarryLoose); an attack pose
		-- (src "fx") still runs so its body offset (the Strike lunge) moves every frame
	end
	local pose, body, src = nil, nil, nil
	local ok, ps = pcall(AF.Pose, u.id, base) -- (base: the drawn spot; a Pounce lands where the server slides the pet)
	if ok and type(ps) == "table" and type(ps.Name) == "string" then
		local cur = u.poseCur or {}
		u.poseCur = cur
		cur.Name, cur.P, cur.Ranged, cur.Amp, cur.Reach = ps.Name, ps.P, ps.Ranged, ps.Amp, ps.Reach
		pose, body, src = cur, poseBody(cur), "fx"
		local blend = num(ps.Blend, 1)
		if type(ps.Prev) == "table" and blend < 1 then
			body = poseBody(ps.Prev):Lerp(body, clamp(blend, 0, 1))
			if blend < 0.5 then
				pose = ps.Prev
			end
		end
	else
		local hold = u.poseHold or {}
		u.poseHold = hold
		if down and u.koAt then
			hold.Name, hold.P, hold.Ranged = "Ko", clamp((now - u.koAt) / K.KO_TIME, 0, 1), false
			src = "ko"
		elseif u.windup and not down and Atk.Drives(u) then
			hold.Name, hold.P, hold.Ranged = "Windup", min(K.WINDUP_HOLD, max(0, now - (u.windAt or now)) / K.WINDUP_IN * 0.5), u.ranged == true
			src = "hold"
		elseif Atk.Idles(u, down, busy) then
			hold.Name, hold.P, hold.Ranged = "IdleBattle", now + u.phase * K.IDLE_PHASE, false
			src = "idle"
		end
		if src then
			pose, body = hold, poseBody(hold)
		end
	end
	if src ~= u.poseSrc then
		-- the crossfade starts from what was shown (an IdleBattle keeps running while it fades out)
		u.poseSrc = src
		u.poseFrom = u.poseBody
		u.poseSwitch = now
		local from = u.poseFromPose or {}
		u.poseFromPose = from
		from.Name, from.P, from.Ranged, from.Amp, from.Reach = u.poseShown, u.poseShownP, u.poseShownRanged, u.poseShownAmp, u.poseShownReach
	end
	if u.poseSwitch then
		local w = (now - u.poseSwitch) / num(AF.CROSSFADE, 0.12)
		if w < 1 then
			body = (u.poseFrom or IDENTITY):Lerp(body or IDENTITY, max(0, w))
			local from = u.poseFromPose
			if w < 0.5 and from and from.Name then
				if from.Name == "IdleBattle" then
					from.P = now + u.phase * K.IDLE_PHASE
				end
				pose = from
			end
		else
			u.poseSwitch, u.poseFrom = nil, nil
		end
	end
	u.poseBody = body
	u.poseShown = pose and pose.Name or nil
	u.poseShownP = pose and pose.P or nil
	u.poseShownRanged = pose and pose.Ranged or nil
	u.poseShownAmp = pose and pose.Amp or nil
	u.poseShownReach = pose and pose.Reach or nil
	u.poseLast, u.poseScaled = pose, nil
	if not body then
		return pose, nil
	end
	local s = u.pbScale
	if not s then
		s = (u.model and num(u.model:GetAttribute("PB_Scale"), nil)) or K.PET_SCALE * (u.scale or 1)
		u.pbScale = s
	end
	if s ~= 1 then
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = body:GetComponents()
		body = CFrame.new(x * s, y * s, z * s, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	end
	u.poseScaled = body
	return pose, body
end

----------------------------------------------------------------------
-- Telegraphs (boss attacks) and zones
----------------------------------------------------------------------
function Tele.Start(B, ev)
	local id = ev.id
	if id == nil or B.teles[id] then
		return
	end
	local fill, edge = Color3.fromRGB(255, 110, 90), Color3.fromRGB(255, 220, 160)
	local BB = lazyBoss()
	local boss = ev.boss and B.units[ev.boss]
	local bossId = (boss and boss.bossId) or B.BossId
	if BB and bossId then
		local ok, f, e = pcall(BB.TelegraphColor, bossId, ev.attack)
		if ok and typeof(f) == "Color3" then
			fill = f
			if typeof(e) == "Color3" then
				edge = e
			end
		end
	end
	local hits = max(0.2, num(ev.hits, 1.5))
	local at = num(ev.at, B.renderT + hits)
	local tl = {
		id = id,
		shape = ev.shape == "Line" and "Line" or "Circle",
		x = num(ev.x, 0),
		z = num(ev.z, 0),
		r = num(ev.r, 6),
		angle = num(ev.angle, 0),
		length = num(ev.length, 30),
		width = num(ev.width, 4),
		at = at,
		from = at - hits,
		-- the dodge deadline on the render clock: the render delay + the round trip + the run-out before the hit
		safeAt = max(at - hits + min(K.TELE_MIN_FILL, hits * 0.5), at - (interpDelay(B) + networkPing() + K.TELE_RUNOUT)),
		fill = fill,
		edgeColor = edge,
		freeze = ev.freeze,
	}
	-- the danger area: the pale edge colour tinted toward the fill, so it still shows on the pale arena sand
	local edgePart = Fx.Part(edge:Lerp(fill, 0.35), Enum.Material.Neon, 0.6)
	local fillPart = Fx.Part(fill, Enum.Material.Neon, 0.35)
	tl.edge, tl.fillPart = edgePart, fillPart
	if tl.shape == "Circle" then
		local cf = worldFrame(B, tl.x, 0.08, tl.z, 0) * CFrame.Angles(0, 0, pi / 2)
		if edgePart then
			edgePart.Shape = Enum.PartType.Cylinder
			edgePart.Size = Vector3.new(0.1, tl.r * 2, tl.r * 2)
			edgePart.CFrame = cf
		end
		if fillPart then
			fillPart.Shape = Enum.PartType.Cylinder
			fillPart.Size = Vector3.new(0.14, 0.1, 0.1)
			fillPart.CFrame = cf * CFrame.new(0.04, 0, 0)
		end
	else
		-- a line from (x, z) along angle (atan2(dz, dx) in zone space)
		local dx, dz = cos(tl.angle), sin(tl.angle)
		tl.dx, tl.dz = dx, dz
		local yaw = yawToward(dx, dz)
		tl.yaw = yaw
		if edgePart then
			edgePart.Size = Vector3.new(tl.width, 0.1, tl.length)
			edgePart.CFrame = worldFrame(B, tl.x + dx * tl.length / 2, 0.08, tl.z + dz * tl.length / 2, yaw)
		end
		if fillPart then
			fillPart.Size = Vector3.new(tl.width * 0.96, 0.14, 0.1)
		end
	end
	-- a crisp rim in the saturated telegraph colour: the pale area alone barely reads on the arena's sand, the rim
	-- says exactly where safety starts (16 segments round a circle; two rails and an end cap along a line)
	local rimColor = fill:Lerp(Color3.new(0, 0, 0), 0.22)
	tl.rim = {}
	if tl.shape == "Circle" then
		local segLen = 2 * tl.r * math.tan(pi / 16) + 0.12
		for j = 0, 15 do
			local seg = Fx.Part(rimColor, Enum.Material.Neon, 0.1)
			if not seg then
				break
			end
			seg.Size = Vector3.new(segLen, 0.16, 0.55)
			seg.CFrame = worldFrame(B, tl.x, 0.14, tl.z, 0) * CFrame.Angles(0, j * pi / 8, 0) * CFrame.new(0, 0, -(tl.r - 0.27))
			tl.rim[#tl.rim + 1] = seg
		end
	else
		-- the frame of edgePart: local X across the line, local Z along it
		local mid = worldFrame(B, tl.x + tl.dx * tl.length / 2, 0.14, tl.z + tl.dz * tl.length / 2, tl.yaw)
		local tip = worldFrame(B, tl.x + tl.dx * (tl.length - 0.27), 0.14, tl.z + tl.dz * (tl.length - 0.27), tl.yaw)
		local pieces = {
			{ mid * CFrame.new(tl.width / 2 - 0.27, 0, 0), Vector3.new(0.55, 0.16, tl.length) },
			{ mid * CFrame.new(-(tl.width / 2 - 0.27), 0, 0), Vector3.new(0.55, 0.16, tl.length) },
			{ tip, Vector3.new(tl.width, 0.16, 0.55) },
		}
		for _, piece in ipairs(pieces) do
			local seg = Fx.Part(rimColor, Enum.Material.Neon, 0.1)
			if not seg then
				break
			end
			seg.Size = piece[2]
			seg.CFrame = piece[1]
			tl.rim[#tl.rim + 1] = seg
		end
	end
	B.teles[id] = tl
	-- the boss winds up toward it
	if boss and boss.isBoss then
		Units.SetPose(boss, "Windup", hits, ev.attack)
		boss.windupFrom = tl.from
		boss.windupAt = tl.at
		if tl.shape == "Line" then
			boss.faceX, boss.faceZ = tl.x + (tl.dx or 0) * 10, tl.z + (tl.dz or 0) * 10
		else
			boss.faceX, boss.faceZ = tl.x, tl.z
		end
	end
end

function Tele.Free(tl)
	Fx.Free(tl.edge)
	Fx.Free(tl.fillPart)
	tl.edge, tl.fillPart = nil, nil
	for _, seg in ipairs(tl.rim or {}) do
		Fx.Free(seg)
	end
	tl.rim = nil
end

local function setRim(tl, transparency)
	for _, seg in ipairs(tl.rim or {}) do
		seg.Transparency = transparency
	end
end

-- is the zone-local point (x, z) inside the telegraph's shape (grown by pad studs)?
function Tele.Covers(tl, x, z, pad)
	local dx, dz = x - tl.x, z - tl.z
	if tl.shape == "Line" then
		local along = dx * (tl.dx or 1) + dz * (tl.dz or 0)
		if along < -pad or along > tl.length + pad then
			return false
		end
		return abs(dx * (tl.dz or 0) - dz * (tl.dx or 1)) <= tl.width / 2 + pad
	end
	return dx * dx + dz * dz <= (tl.r + pad) * (tl.r + pad)
end

-- my fighter stands in a telegraph that has not hit yet (the HUD's DASH cue: dash through it)
local function threatened(B, tl)
	for slot = 1, 4 do
		local u = B.mine[slot]
		if u and u.hp > 0 and u.state ~= S_DOWN and u.state ~= S_BENCHED and Tele.Covers(tl, u.x, u.z, K.THREAT_PAD) then
			return true
		end
	end
	return false
end

function Tele.Update(B, now)
	local t = B.renderT
	local threat = false
	for id, tl in pairs(B.teles) do
		if not threat and B.Fighter and t < tl.at and threatened(B, tl) then
			threat = true
		end
		if t >= tl.at then
			if not tl.impactAt then
				tl.impactAt = now
				-- the hit: a flash of the shape + a shock ring / burst
				local center
				if tl.shape == "Circle" then
					center = worldPoint(B, tl.x, 0.4, tl.z)
					Fx.Ring(center, tl.r, tl.edgeColor, 18, 0.9, 0.45, 0.05)
					Fx.Burst(center, tl.fill, 12, 12, 0.6, 0.55, { up = 0.9, color2 = tl.edgeColor })
				else
					local mid = worldPoint(B, tl.x + tl.dx * tl.length / 2, 1.4, tl.z + tl.dz * tl.length / 2)
					Fx.Beam(worldFrame(B, tl.x + tl.dx * tl.length / 2, 1.4, tl.z + tl.dz * tl.length / 2, tl.yaw), tl.length, tl.width * 0.8, tl.fill, 0.4)
					Fx.Burst(mid, tl.edgeColor, 8, 10, 0.5, 0.5, { up = 0.7 })
				end
				if tl.freeze then
					local c = worldPoint(B, tl.x, 0.6, tl.z)
					Fx.Burst(c, COLORS.Ice, 10, 9, 0.55, 0.6, { material = Enum.Material.Glass, alpha = 0.2, up = 0.8 })
				end
				if tl.fillPart then
					tl.fillPart.Transparency = 0.05
				end
				local boss = B.boss
				if boss and boss.pose == "Windup" then
					Units.SetPose(boss, "Attack", 0.7)
					boss.windupAt = nil
				end
			end
			local p = (now - tl.impactAt) / 0.35
			if p >= 1 then
				Tele.Free(tl)
				B.teles[id] = nil
			else
				if tl.edge then
					tl.edge.Transparency = 0.6 + 0.4 * p
				end
				if tl.fillPart then
					tl.fillPart.Transparency = 0.05 + 0.95 * p
				end
				setRim(tl, 0.1 + 0.9 * p)
			end
		else
			-- the fill completes at the dodge deadline (safeAt), then the shape flashes until the hit
			local fillEnd = tl.safeAt or tl.at
			local p = clamp((t - tl.from) / max(0.05, fillEnd - tl.from), 0, 1)
			if t >= fillEnd then
				if not tl.late then
					tl.late = true
					for _, seg in ipairs(tl.rim or {}) do
						seg.Color = COLORS.LateRim
					end
				end
				local on = sin(now * 26) > 0
				if tl.edge then
					tl.edge.Transparency = on and 0.25 or 0.65
				end
				setRim(tl, on and 0 or 0.6)
			else
				local pulse = 0.5 + 0.5 * sin(now * 10)
				if tl.edge then
					tl.edge.Transparency = 0.5 + 0.2 * pulse
				end
				setRim(tl, 0.05 + 0.3 * pulse)
			end
			if tl.fillPart then
				if tl.shape == "Circle" then
					local d = max(0.1, tl.r * 2 * p)
					tl.fillPart.Size = Vector3.new(0.14, d, d)
				else
					local len = max(0.1, tl.length * p)
					tl.fillPart.Size = Vector3.new(tl.width * 0.96, 0.14, len)
					tl.fillPart.CFrame = worldFrame(B, tl.x + tl.dx * len / 2, 0.12, tl.z + tl.dz * len / 2, tl.yaw)
				end
				tl.fillPart.Transparency = 0.45 - 0.25 * p
			end
		end
	end
	B.threat = threat
end

function Tele.ClearAll(B)
	for id, tl in pairs(B.teles) do
		Tele.Free(tl)
		B.teles[id] = nil
	end
end

----------------------------------------------------------------------
-- Events (played on the delayed render clock)
----------------------------------------------------------------------
local function specialColor(u, kind)
	if u and u.special and typeof(u.special.Color) == "Color3" then
		return u.special.Color
	end
	if u then
		return elementColor(u.element)
	end
	if kind == "Heal" then
		return COLORS.Heal
	end
	return COLORS.Gold
end

local function numberHeight(u)
	if u.isBoss then
		return (u.height or 20) * 0.5 + 2
	end
	return (u.height or 3) / 2 + 1.8
end

----------------------------------------------------------------------
-- wave 6: the trainer's cheer (TrainerCheer): my avatar loops the cheer emote while the server holds me on the podium
-- (Config.Attr.OnPodium: Champion Ring / PvP) and plays it once on my own Cheer event (Cheer up!, dungeon / raid).
-- Only my avatar: Roblox replicates a character's animation to everyone else. No sound (the sound wave).
----------------------------------------------------------------------
local Cheer = {}

function Cheer.Mod()
	if Mods.Cheer == nil then
		Mods.Cheer = optional(script.Parent, "TrainerCheer") or false
	end
	return Mods.Cheer or nil
end

-- the podium attribute -> the loop
function Cheer.SyncPodium()
	local m = Cheer.Mod()
	if not m then
		return
	end
	local attr = (Config.Attr and Config.Attr.OnPodium) or "OnPodium"
	if LocalPlayer and LocalPlayer:GetAttribute(attr) == true then
		if not m.IsLooping() then
			m.StartLoop(LocalPlayer.Character)
		end
	else
		m.StopLoop()
	end
end

-- my own Cheer up! landed on the server: one cheer (the button's glow and sweep start on arrival: Net.Pre)
function Cheer.Mine()
	local m = Cheer.Mod()
	if m and LocalPlayer then
		m.Play(LocalPlayer.Character)
	end
end

local Handlers = {}

Handlers[EV.Hit] = function(B, ev)
	local victim = B.units[tonumber(ev.to) or -1]
	local attacker = ev.from and B.units[tonumber(ev.from) or -1]
	if not victim then
		return
	end
	local dmg = num(ev.dmg, 0)
	-- (Task 11b, fix round 1 I1 / M2) a held unit's drawn HP follows each hit's number: the hold's floor drops by this
	-- hit's damage (a plain hit's on time, a late Special's at its impact; never under a last gasp's floor). A late
	-- Special's hit ends the hold only when it is the last one due: another special's hold on the unit stays
	if victim.holdHp and not ev.miss then
		victim.holdHp = max(victim.holdFloor or 0, victim.holdHp - dmg)
	end
	if ev.fxSpHeld and (not victim.holdUntil or os.clock() >= victim.holdUntil - K.HOLD_EPS) then
		Units.Unhold(victim)
	end
	-- AttackFx (played on arrival): a pet's plain attack (its swipe / shot, its Strike pose, the victim's Hurt pose) or
	-- my pet's hurt from a boss; false = the cube bolt / lunge / nudge below
	local played = Atk.Result(B, ev)
	-- Phase 5: a dodged hit (dash i-frames / out of reach at the impact)
	if ev.miss then
		if victim.root and not victim.parked then
			Fx.Number(victim.root, numberHeight(victim) + 0.4, "DODGED!", COLORS.Dodge, K.CALLOUT_PX, 0.9)
		end
		if attacker and not attacker.isBoss then
			local dx, dz = victim.x - attacker.x, victim.z - attacker.z
			local d = sqrt(dx * dx + dz * dz)
			if d > 0.01 then
				attacker.lungeAt = os.clock()
				attacker.lungeX, attacker.lungeZ = dx / d, dz / d
				attacker.lungeFx = played and Atk.Posable()
			end
		end
		return
	end
	-- attacker motion: plain attacks lunge (melee) or shoot a bolt (ranged); my fighter too (it attacks by itself:
	-- its lunges come only from these server hits, never from a press)
	if attacker and not ev.special and not ev.zone and not ev.tele and not ev.element then
		if attacker.isBoss then
			if attacker.pose ~= "Windup" and attacker.pose ~= "Attack" and attacker.pose ~= "Enrage" then
				Units.SetPose(attacker, "Basic", 0.6, ev.attack)
				attacker.faceX, attacker.faceZ = victim.x, victim.z
			end
			Fx.Bolt(unitCenter(B, attacker), unitCenter(B, victim), elementColor(attacker.element), 0.7, 0.35)
		else
			local dx, dz = victim.x - attacker.x, victim.z - attacker.z
			local d = sqrt(dx * dx + dz * dz)
			if d > 0.01 then
				attacker.lungeAt = os.clock()
				attacker.lungeX, attacker.lungeZ = dx / d, dz / d
				attacker.lungeFx = played and Atk.Posable() -- (the Strike pose replaces the lunge offset)
			end
			if not played and attacker.ranged and attacker.model and not attacker.parked then
				Fx.Bolt(unitCenter(B, attacker), unitCenter(B, victim), elementColor(attacker.element), 0.42, 0.24)
			end
		end
	end
	-- my fighter hit hard: a tiny camera shake (x the Shake setting)
	if victim.mine and B.Fighter and victim.id == B.fighterId and dmg >= victim.maxHp * 0.12 then
		Me.Shake(0.18, 0.16)
	elseif victim.mine and B.Fighter and victim.id == B.fighterId and B.Mode == "Dungeon" and dmg > 0 then
		Me.Shake(K.HIT_SHAKE_LIGHT[1], K.HIT_SHAKE_LIGHT[2]) -- wave 5 (bug #15): a light shake on every hit in a dungeon
	end
	-- victim feedback
	if not victim.isBoss and attacker then
		local dx, dz = victim.x - attacker.x, victim.z - attacker.z
		local d = sqrt(dx * dx + dz * dz)
		if d > 0.01 then
			victim.hurtAt = os.clock()
			victim.hurtX, victim.hurtZ = dx / d, dz / d
			-- the Hurt pose instead of the nudge: this hit's effect played, or a played special / element covers it
			victim.hurtFx = Atk.Posable() and (played or (victim.fxHitUntil ~= nil and victim.hurtAt <= victim.fxHitUntil))
		end
	end
	if not ev.zone or math.random() < 0.5 then
		Fx.Flash(victim, (ev.elem and ev.elem > 1) and Color3.fromRGB(255, 226, 190) or COLORS.White)
	end
	local adornee = victim.root
	if not adornee or victim.parked then
		return
	end
	local text, color, px = tostring(floor(dmg + 0.5)), COLORS.White, K.NUMBER_PX
	if ev.crit then
		text = "CRIT " .. text
		color = COLORS.Gold
		px = K.CRIT_PX
	elseif ev.elem and ev.elem > 1 then
		text = text .. "!"
		color = COLORS.Strong
		px = K.NUMBER_PX + 2
	elseif ev.elem and ev.elem < 1 then
		color = COLORS.Weak
	end
	if victim.mine then
		color = (color == COLORS.White) and Color3.fromRGB(255, 196, 196) or color
	end
	if ev.special and attacker then
		color = specialColor(attacker):Lerp(COLORS.White, 0.35)
		px = max(px, K.NUMBER_PX + 2)
	elseif ev.element and attacker then
		color = elementColor(attacker.element):Lerp(COLORS.White, 0.3)
		px = max(px, K.NUMBER_PX + 2)
	elseif ev.burn then
		text, color, px = "BURN " .. text, COLORS.Strong, K.NUMBER_PX - 4
	end
	if dmg > 0 then
		Fx.Number(adornee, numberHeight(victim), text, color, px)
	end
	if num(ev.absorbed, 0) > 0 then
		Fx.Number(adornee, numberHeight(victim) + 0.8, "BLOCK " .. tostring(floor(ev.absorbed + 0.5)), COLORS.Shield, K.NUMBER_PX - 2, 0.8)
	end
	if ev.freeze then
		victim.iceUntil = os.clock() + num(ev.freeze, 2)
	end
end

Handlers[EV.Special] = function(B, ev)
	local u = B.units[tonumber(ev.unit) or -1]
	local kind = tostring(ev.kind or "")
	local color = specialColor(u, kind)
	local S = SPECIALS[kind] or {}
	-- AttackFx (played on arrival) draws the special; the cube Fx.* below only when it did not (the callout, the heal
	-- numbers and the shield / ice bookkeeping stay either way)
	local cubes = not Atk.Result(B, ev)
	if u and u.root and not u.parked then
		local label = tostring(ev.name or kind)
		Fx.Number(u.root, numberHeight(u) + 0.6, string.upper(label) .. "!", color:Lerp(COLORS.White, 0.2), K.CALLOUT_PX, 1.2)
		if cubes then
			Fx.Burst(unitCenter(B, u), color, 8, 6, 0.35, 0.45, { up = 0.9, gravity = 4 })
		end
	end
	local tx, tz = num(ev.tx, num(ev.x, 0)), num(ev.tz, num(ev.z, 0))
	if not cubes then
		for _, h in ipairs(kind == "Heal" and type(ev.heals) == "table" and ev.heals or {}) do
			local a = B.units[tonumber(h[1]) or -1]
			if a and a.root and not a.parked and num(h[2], 0) > 0 then
				Fx.Number(a.root, numberHeight(a), "+" .. tostring(floor(num(h[2], 0) + 0.5)), COLORS.Heal, K.NUMBER_PX)
			end
		end
		local seconds = num(S.Seconds, 6)
		for _, id in ipairs(kind == "Shield" and type(ev.shields) == "table" and ev.shields or {}) do
			local a = B.units[tonumber(id) or -1]
			if a then
				-- (its later absorbed hits ripple in u's look while the shield lasts: Atk.ShieldHit)
				a.shieldUntil = os.clock() + seconds + 0.5
				a.shieldBy = u and u.id or nil
			end
		end
		local stun = num(S.Stun, 1) + 0.4
		for _, id in ipairs(kind == "Freeze" and type(ev.stunned) == "table" and ev.stunned or {}) do
			local a = B.units[tonumber(id) or -1]
			if a then
				a.iceUntil = os.clock() + stun
			end
		end
	elseif kind == "Blast" then
		local c = worldPoint(B, tx, 0.6, tz)
		local r = num(S.Radius, 7)
		Fx.Ring(c, r, color, 20, 0.8, 0.5, 0.05)
		Fx.Burst(c + Vector3.new(0, 0.8, 0), color, 16, 13, 0.6, 0.6, { color2 = COLORS.White:Lerp(color, 0.4), up = 0.8 })
	elseif kind == "Heal" then
		for _, h in ipairs(type(ev.heals) == "table" and ev.heals or {}) do
			local a = B.units[tonumber(h[1]) or -1]
			if a and a.root and not a.parked then
				Fx.Rise(unitCenter(B, a), COLORS.Heal, 8, 0.32, 0.9, 1.6)
				if num(h[2], 0) > 0 then
					Fx.Number(a.root, numberHeight(a), "+" .. tostring(floor(num(h[2], 0) + 0.5)), COLORS.Heal, K.NUMBER_PX)
				end
			end
		end
	elseif kind == "Shield" then
		local seconds = num(S.Seconds, 6)
		for _, id in ipairs(type(ev.shields) == "table" and ev.shields or {}) do
			local a = B.units[tonumber(id) or -1]
			if a and a.root and not a.parked then
				Fx.Ring(unitCenter(B, a), 2.2, COLORS.Shield, 10, 0.4, 0.5, 0.2)
			end
			if a then
				a.shieldUntil = os.clock() + seconds + 0.5
				a.shieldBy = u and u.id or nil
			end
		end
	elseif kind == "Pounce" then
		if u then
			local a = worldPoint(B, num(ev.x, u.x), 1.4, num(ev.z, u.z))
			local b = worldPoint(B, tx, 1.4, tz)
			Fx.Trail(a, b, color, 9, 0.5)
			u.hopAt = os.clock()
		end
		Fx.Burst(worldPoint(B, tx, 1.2, tz), color, 12, 11, 0.5, 0.55, { up = 0.7, color2 = COLORS.White })
	elseif kind == "Freeze" then
		local c = worldPoint(B, tx, 0.5, tz)
		local r = num(S.Radius, 6)
		Fx.Ring(c, r, COLORS.Ice, 16, 0.7, 0.55, 0.1)
		Fx.Burst(c + Vector3.new(0, 0.6, 0), COLORS.Ice, 14, 10, 0.55, 0.7, { material = Enum.Material.Glass, alpha = 0.15, up = 0.8, color2 = COLORS.White })
		local stun = num(S.Stun, 1) + 0.4
		for _, id in ipairs(type(ev.stunned) == "table" and ev.stunned or {}) do
			local a = B.units[tonumber(id) or -1]
			if a then
				a.iceUntil = os.clock() + stun
			end
		end
	elseif kind == "Beam" then
		local length = num(S.Length, 26)
		local width = num(S.Width, 4)
		local angle = num(ev.angle, 0)
		local dx, dz = cos(angle), sin(angle)
		local sx, sz = num(ev.x, u and u.x or 0), num(ev.z, u and u.z or 0)
		local cf = worldFrame(B, sx + dx * length / 2, 1.6, sz + dz * length / 2, yawToward(dx, dz))
		Fx.Beam(cf, length, width * 0.7, color, 0.5)
		Fx.Burst(worldPoint(B, sx + dx * length, 1.6, sz + dz * length), color, 8, 8, 0.4, 0.45, { up = 0.5 })
	elseif kind == "Rally" or kind == "Haste" then
		if u and u.model and not u.parked then
			Fx.Rise(unitCenter(B, u), kind == "Haste" and COLORS.Dodge or COLORS.Gold, 12, 0.34, 0.9, 1.8)
		end
	elseif kind == "Storm" then
		-- the Zone event that follows draws the cloud
		Fx.Burst(worldPoint(B, tx, 5, tz), COLORS.StormLight, 6, 5, 0.6, 0.5, { up = 0.3, gravity = 2 })
	end
end

Handlers[EV.Zone] = function(B, ev)
	local kind = tostring(ev.kind or "")
	local x, z = num(ev.x, 0), num(ev.z, 0)
	local r = num(ev.r, 6)
	local seconds = max(0.5, num(ev.seconds, 4))
	local floorCF = worldFrame(B, x, 0, z, 0)
	if kind == "Storm" then
		local u = B.units[tonumber(ev.unit) or -1]
		-- AttackFx's Storm special rains from its own cloud: the zone then draws only its damage field on the floor
		local field = u and u.stormFxUntil ~= nil and os.clock() <= u.stormFxUntil
		Fx.Zone(floorCF, r, seconds, specialColor(u, "Storm"), field and "Field" or "Storm")
	else
		local color = Color3.fromRGB(255, 120, 60)
		local BB = lazyBoss()
		if BB and B.BossId then
			local ok, f = pcall(BB.TelegraphColor, B.BossId, ev.attack)
			if ok and typeof(f) == "Color3" then
				color = f
			end
		end
		Fx.Zone(floorCF, r, seconds, color, "Linger")
	end
end

Handlers[EV.KO] = function(B, ev)
	local u = B.units[tonumber(ev.unit) or -1]
	if not u then
		return
	end
	Units.Unhold(u) -- (Task 11b) a KO held for a late Special's impact (or a last gasp) plays now
	if St.pre and St.pre.unit == u.id then
		Atk.Shatter(B, true) -- (fix round 1, I3) my pressed fighter went down before its Special: the charge just fades
	end
	Atk.Result(B, ev) -- AttackFx's Ko (played on arrival) marks the pet poofed: no cube poof below, it tumbles and lies
	if u.root and not u.parked then
		Fx.Number(u.root, numberHeight(u) + 0.4, "KO!", Color3.fromRGB(220, 226, 240), K.CALLOUT_PX, 1.1)
		if not u.isBoss and not u.poofed then
			u.poofed = true
			Fx.Burst(unitCenter(B, u), Color3.fromRGB(236, 240, 250), 12, 9, 0.5, 0.6, { color2 = elementColor(u.element), alpha = 0.05 })
		elseif u.isBoss then
			Fx.Burst(unitCenter(B, u), elementColor(u.element), 24, 16, 0.9, 1.1, { color2 = COLORS.White, up = 0.9 })
		end
	end
	u.hp = 0
	u.state = S_DOWN
	Me.UndimCaster(u.id) -- (Task 11) a knocked-out caster's battle dim ends with it (its effect may still finish its beats)
	if B.lock == u.id then
		B.lock = nil
	end
	Hud.enemyDirty = true
	if u.mine and u.id == B.fighterId then
		Me.Shake(0.3, 0.3)
	end
end

Handlers[EV.Telegraph] = function(B, ev)
	Tele.Start(B, ev)
end

Handlers[EV.Spawn] = function(B, ev)
	Units.AddList(B, ev.units)
	if ev.wave then
		B.wave = num(ev.wave, 0)
		local boss = B.boss
		if boss and boss.root then
			Fx.Number(boss.root, numberHeight(boss) + 1, "MINIONS!", COLORS.Enemy:Lerp(COLORS.White, 0.3), K.CALLOUT_PX, 1.4)
		end
	end
	Hud.Rebuild()
end

Handlers[EV.Enrage] = function(B, ev)
	B.enraged = true
	local boss = B.units[tonumber(ev.unit) or -1] or B.boss
	if boss and boss.model then
		local BB = lazyBoss()
		if BB then
			pcall(BB.SetEnraged, boss.model, true)
		end
		Units.SetPose(boss, "Enrage", 1.3)
		if boss.root then
			Fx.Number(boss.root, numberHeight(boss) + 1, "ENRAGED!", COLORS.Enemy, K.CRIT_PX, 1.6)
		end
		Fx.Ring(unitCenter(B, boss), 14, COLORS.Enemy, 24, 1, 0.8, 0.1)
	end
end

Handlers[EV.Order] = function()
	-- (handled on arrival: Net.Pre)
end

-- (Units.Remove ends each leaver's own AttackFx effects and pose: AttackFx.Cancel)
Handlers[EV.Leave] = function(B, ev)
	for _, id in ipairs(type(ev.units) == "table" and ev.units or {}) do
		local u = B.units[tonumber(id) or -1]
		if u then
			if u.root and not u.parked then
				Fx.Burst(unitCenter(B, u), Color3.fromRGB(226, 232, 246), 8, 7, 0.45, 0.5, { alpha = 0.1 })
			end
			Units.Remove(B, u.id)
		end
	end
	Hud.Rebuild()
end

Handlers[EV.End] = function(B)
	B.simEnded = true
	-- the fight is over (Review Focus 4, Ruling 11): no new attack effect from here; the live ones (the killing blow
	-- lands visibly) finish for at most FX_END_GRACE, then AttackFx.ClearAll (Atk.Update)
	Atk.EndSoon(B)
end

-- Phase 5 events (the visuals, on the render clock; the HUD / prediction side runs on arrival in Net.Pre)
local function calloutAbove(u, text, color, px, life)
	if u and u.root and not u.parked then
		Fx.Number(u.root, numberHeight(u) + 0.8, text, color, px or K.CALLOUT_PX, life or 1.1)
	end
end

Handlers[EV.Element or "Element"] = function(B, ev)
	local u = B.units[tonumber(ev.unit) or -1]
	local color = elementColor(ev.element or (u and u.element))
	local sx, sz = num(ev.x, u and u.x or 0), num(ev.z, u and u.z or 0)
	local angle = num(ev.angle, 0)
	local shape = tostring(ev.shape or "Cone")
	local played = Atk.Result(B, ev) -- AttackFx (played on arrival): the shape in the element's textures + the cast pose
	calloutAbove(u, string.upper(tostring(ev.name or ev.element or "")) .. "!", color:Lerp(COLORS.White, 0.25))
	if played then
		return
	end
	if u and u.id ~= B.fighterId then
		u.hopAt = os.clock()
	end
	local dx, dz = cos(angle), sin(angle)
	if shape == "Circle" then
		local c = worldPoint(B, sx, 0.6, sz)
		Fx.Ring(c, 8, color, 22, 0.8, 0.5, 0.05)
		Fx.Burst(c + Vector3.new(0, 0.8, 0), color, 14, 11, 0.55, 0.55, { color2 = COLORS.White, up = 0.8 })
	elseif shape == "Line" then
		local length = 24
		local cf = worldFrame(B, sx + dx * length / 2, 1.6, sz + dz * length / 2, yawToward(dx, dz))
		Fx.Beam(cf, length, 3, color, 0.45)
	else
		-- a cone: bursts fanned out in front of the caster
		for i = -2, 2 do
			local a = angle + i * 0.22
			local r = 9 + abs(i) * 0.8
			Fx.Burst(worldPoint(B, sx + cos(a) * r, 1.2, sz + sin(a) * r), color, 5, 7, 0.45, 0.45, { up = 0.6, color2 = COLORS.White })
		end
		Fx.Trail(worldPoint(B, sx, 1.3, sz), worldPoint(B, sx + dx * 11, 1.3, sz + dz * 11), color, 8, 0.4)
	end
end

-- the PET dashes (the character never does, decision 5): every pet's Dash draws its streak; my own fighter's already
-- started when the event arrived (Net.Pre: no render delay for my own dodge)
Handlers[EV.Dash or "Dash"] = function(B, ev)
	local u = B.units[tonumber(ev.unit) or -1]
	if u and u.dashEv ~= ev then
		Me.StartDash(B, u, ev)
	end
end

-- wave 6: Cheer up! (dungeon / raid): only my own avatar cheers here (the others' avatars replicate)
Handlers[EV.Cheer or "Cheer"] = function(B, ev)
	if tonumber(ev.owner) == myUserId() then
		Cheer.Mine(B, ev)
	end
end

Handlers[EV.Buff or "Buff"] = function(B, ev)
	local helper = B.units[tonumber(ev.unit) or -1]
	local fighter = B.units[tonumber(ev.target) or -1]
	local color = (helper and elementColor(helper.element)) or COLORS.Heal
	local played = Atk.Result(B, ev) -- AttackFx: the support special the buff is like, on the fighter
	if helper and helper.mine then
		helper.flyAt = os.clock() -- fly to the fighter and back
	end
	local bdef = BattleCatalog and type(BattleCatalog.Buffs) == "table" and BattleCatalog.Buffs[tostring(ev.kind)] or nil
	if helper and fighter and type(bdef) == "table" and bdef.Effect == "Shield" then
		-- (the shield's later absorbed hits ripple in the helper's look while it lasts: Atk.ShieldHit)
		fighter.shieldBy = helper.id
		fighter.shieldUntil = os.clock() + num(bdef.Seconds, 6) + 0.5
	end
	if fighter then
		calloutAbove(fighter, string.upper(tostring(ev.name or ev.kind or "BUFF")), color:Lerp(COLORS.White, 0.2), K.CALLOUT_PX, 1.4)
		if not played and fighter.model and not fighter.parked then
			Fx.Rise(unitCenter(B, fighter), color, 10, 0.32, 0.9, 1.6)
		end
	end
end

Handlers[EV.Swap or "Swap"] = function(B, ev)
	local incoming = B.units[tonumber(ev["in"]) or -1]
	-- (fix round 2, I2-b) a held auto-swap: the incoming pet leaves the bench now (another player's is unparked for its
	-- GO!), and my two pets trade places now (Me.Switch; Net.Pre left it for this moment)
	if incoming and incoming.unbenchAt then
		incoming.unbenchAt = nil
		if not incoming.mine and incoming.state ~= S_BENCHED then
			incoming.benched = false
			parkUnit(incoming, false)
		end
	end
	if ev.fxSwitchLate and B.Fighter and not B.ended and ev.owner == myUserId() then
		Me.Switch(B, ev)
	end
	local played = Atk.Result(B, ev) -- AttackFx: the incoming pet's entrance (Victory)
	if incoming and incoming.model and not incoming.parked then
		calloutAbove(incoming, ev.auto and "GO!" or "SWAP!", COLORS.Dodge, K.CALLOUT_PX, 1)
		if not played then
			Fx.Burst(unitCenter(B, incoming), elementColor(incoming.element), 10, 8, 0.45, 0.45, { up = 0.7, color2 = COLORS.White })
		end
	end
	-- (my pets' arc starts at the trade: Me.Switch)
end

Handlers[EV.Windup or "Windup"] = function(B, ev)
	local u = B.units[tonumber(ev.unit) or -1]
	if u then
		-- the list row's "!" until the hit lands (at = sim time of the hit)
		u.windupUntil = os.clock() + max(0.2, num(ev.at, B.renderT + 0.45) - B.renderT) + 0.1
	end
end

-- dungeon fixes (root cause A): the server opens a room's encounter with an EMPTY side 2 ("Start") and spawns every
-- wave afterwards: the Wave event carries the enemies, so they are added here (deduped by id, like Spawn)
Handlers[EV.Wave or "Wave"] = function(B, ev)
	Units.AddList(B, ev.units)
	B.wave = num(ev.index, B.wave or 0)
	if B.Dungeon then
		B.Dungeon.Wave = B.wave
	end
	local f = B.fighterId and B.units[B.fighterId]
	calloutAbove(f, "WAVE " .. tostring(B.wave) .. "!", Theme.Neon and Theme.Neon.Purple or COLORS.Gold, K.CRIT_PX, 1.4)
	Hud.enemyDirty = true
	Hud.Rebuild()
end

Handlers[EV.EnemiesDown or "EnemiesDown"] = function(B)
	local f = B.fighterId and B.units[B.fighterId]
	calloutAbove(f, "WAVE CLEARED!", COLORS.Mine, K.CALLOUT_PX, 1.2)
end

Handlers[EV.Speed or "Speed"] = function()
	-- (handled on arrival: Net.Pre)
end

-- bug #22: my pet leaves me to fight (the server's engage rule): the arrival hop = "it goes"; nothing else (no parts,
-- the same on Low graphics); another player's pet just moves with its snapshots
Handlers[EV.Engage or "Engage"] = function(B, ev)
	if ev.on ~= true or not B.fighterId or tonumber(ev.unit) ~= B.fighterId then
		return
	end
	local u = B.units[B.fighterId]
	if u and u.model and not u.parked then
		u.hopAt = os.clock()
	end
	Hud.enemyDirty = true
end

-- the End: plays every queued event that is not held for a flying shot, in order; true when held ones are left
function Net.PlayUnheld(B)
	local q = B.evq
	local items = {}
	for i = 1, #q do
		items[i] = q[i]
	end
	for i = #q, 1, -1 do
		q[i] = nil
	end
	local held = false
	for _, item in ipairs(items) do
		if item.held then
			q[#q + 1] = item
			held = true
		else
			local fn = Handlers[item.ev.type]
			if fn then
				local ok, err = pcall(fn, B, item.ev)
				if not ok then
					warnOnce("event_" .. tostring(item.ev.type), "event " .. tostring(item.ev.type) .. " failed: " .. tostring(err))
				end
			end
		end
	end
	return held
end

function Net.PlayDue(B, now)
	local q = B.evq
	if #q == 0 then
		return
	end
	local played = 0
	local t = B.renderT
	while #q > 0 and (q[1].t <= t or #q > 400) do
		local item = table.remove(q, 1)
		local fn = Handlers[item.ev.type]
		if fn then
			local ok, err = pcall(fn, B, item.ev)
			if not ok then
				warnOnce("event_" .. tostring(item.ev.type), "event " .. tostring(item.ev.type) .. " failed: " .. tostring(err))
			end
		end
		played = played + 1
		if played > 120 then
			break
		end
	end
end

----------------------------------------------------------------------
-- HUD (Phase 5, contract 4.7: the battle HUD of image 24.png on the Neon kit)
----------------------------------------------------------------------
local function label(parent, text, role, size, props)
	local l = Theme.Label(text, role, { Size = size, Stroke = 0.15, Outline = 2 })
	l.BackgroundTransparency = 1
	if props then
		for key, value in pairs(props) do
			l[key] = value
		end
	end
	l.Parent = parent
	return l
end

local function smallPill(parent, text, color, props)
	local dark = Theme.Darken(color, 0.62)
	local l = Theme.Label(text, "Heading", { Size = 15, Stroke = 0.1, StrokeColor = dark, Outline = 1.5, OutlineColor = dark })
	l.Name = "Pill"
	l.BackgroundTransparency = 0
	l.BackgroundColor3 = color
	l.BorderSizePixel = 0
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromOffset(0, 22)
	l.TextXAlignment = Enum.TextXAlignment.Center
	Theme.Corner(l, UDim.new(0, 11))
	Theme.Stroke(l, COLORS.Navy, 2, 0)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, l)
	if props then
		for key, value in pairs(props) do
			l[key] = value
		end
	end
	l.Parent = parent
	return l
end

-- a thin bar without text (timers): returns { Root, Fill }
local function thinBar(parent, name, height, color, props)
	local root = make("Frame", { Name = name, BackgroundColor3 = COLORS.Track, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, height) }, parent)
	if props then
		for key, value in pairs(props) do
			root[key] = value
		end
	end
	Theme.Corner(root, UDim.new(0, max(2, floor(height / 2))))
	local fill = make("Frame", { Name = "Fill", BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, root)
	Theme.Corner(fill, UDim.new(0, max(2, floor(height / 2))))
	return { Root = root, Fill = fill, frac = 1 }
end

local function setThin(b, frac)
	frac = clamp(frac, 0, 1)
	if abs(frac - (b.frac or -1)) > 0.003 then
		b.frac = frac
		b.Fill.Size = UDim2.fromScale(max(frac, 0.001), 1)
		b.Fill.Visible = frac > 0.002
	end
end

-- a rough width of `text` in px at `size` (bold display fonts run ~0.62 em per character)
local function textWidth(text, size)
	return #tostring(text or "") * size * 0.62
end

local function setText(lbl, text)
	if lbl and lbl.Text ~= text then
		lbl.Text = text
	end
end

local function setVisible(obj, on)
	if obj and obj.Visible ~= (on == true) then
		obj.Visible = on == true
	end
end

-- a NeonKit card (a Theme panel when the kit is missing): { Root, Body, SetColor }
local function neonCard(parent, name, color, props)
	local c
	if Mods.NeonKit and type(Mods.NeonKit.Card) == "function" then
		local ok, result = pcall(Mods.NeonKit.Card, { Name = name, Color = color, Parent = parent, Size = props and props.Size, Glow = props and props.Glow, Floor = props and props.Floor, Class = props and props.Class })
		if ok and type(result) == "table" then
			c = result
		end
	end
	if not c then
		local f = Theme.Panel({ Name = name })
		f.Parent = parent
		c = { Root = f, Body = f, SetColor = function() end }
	end
	if props then
		for key, value in pairs(props) do
			if key ~= "Size" and key ~= "Glow" and key ~= "Floor" and key ~= "Class" then
				c.Root[key] = value
			end
		end
	end
	return c
end

-- the key hint chip (desktop / gamepad)
local function keyChip(parent, text, props)
	local chip = make("Frame", { Name = "Key", BackgroundColor3 = Theme.Colors.PanelInk or COLORS.Navy, BorderSizePixel = 0, Size = UDim2.fromOffset(30, 24), ZIndex = 8 }, parent)
	Theme.Corner(chip, UDim.new(0, 7))
	Theme.Stroke(chip, COLORS.White, 1.5, 0.3)
	local l = label(chip, text, "Heading", 15, { Name = "Text", Size = UDim2.fromScale(1, 1), ZIndex = 9, TextXAlignment = Enum.TextXAlignment.Center })
	if props then
		for key, value in pairs(props) do
			chip[key] = value
		end
	end
	return chip, l
end

-- every HUD text stays >= MIN_TEXT_PX on the screen: design sizes grow to MIN_TEXT_PX / factor on small screens
-- (the 1080p design sizes are kept as the attribute BaseText)
function Hud.FixText(root, factor)
	local minDesign = math.ceil(K.MIN_TEXT_PX / max(0.05, factor) - 1e-6)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			local base = d:GetAttribute("BaseText")
			if type(base) ~= "number" then
				base = d.TextSize
				d:SetAttribute("BaseText", base)
			end
			local want = max(base, minDesign)
			if d.TextSize ~= want then
				d.TextSize = want
			end
		end
	end
end

local function setDisabled(b, disabled)
	if (b:GetAttribute("Disabled") == true) ~= (disabled == true) then
		b:SetAttribute("Disabled", disabled == true)
	end
end

-- a round progress ring (a pie of two clipped half discs with a hard-edged UIGradient each; no asset ids): the
-- `frac` share of the circle from 12 o'clock clockwise in `color`, the rest the dark track. setPie writes only when
-- the shown share moves by a 5 degree step.
local SWEEP = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.501, 1),
	NumberSequenceKeypoint.new(1, 1),
})

local function newPie(parent, name, size, color, z)
	local root = make("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		ZIndex = z or 2,
	}, parent)
	local track = make("Frame", { Name = "Track", BackgroundColor3 = COLORS.Track, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = z or 2 }, root)
	Theme.Corner(track, UDim.new(0.5, 0))
	local pie = { Root = root, Track = track, frac = -1, color = color }
	for _, side in ipairs({ "R", "L" }) do
		local clip = make("Frame", {
			Name = side,
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Position = UDim2.fromScale(side == "R" and 0.5 or 0, 0),
			Size = UDim2.fromScale(0.5, 1),
			ZIndex = z or 2,
		}, root)
		local disc = make("Frame", {
			Name = "Disc",
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(side == "R" and -1 or 0, 0),
			Size = UDim2.fromScale(2, 1),
			Visible = false,
			ZIndex = z or 2,
		}, clip)
		Theme.Corner(disc, UDim.new(0.5, 0))
		local g = make("UIGradient", { Name = "Sweep", Transparency = SWEEP, Rotation = 0 }, disc)
		pie[side] = { clip = clip, disc = disc, g = g }
	end
	return pie
end

local function setPie(pie, frac, color)
	if color and pie.color ~= color then
		pie.color = color
		pie.R.disc.BackgroundColor3 = color
		pie.L.disc.BackgroundColor3 = color
	end
	local q = floor(clamp(frac, 0, 1) * 72 + 0.5) / 72
	if q == pie.frac then
		return
	end
	pie.frac = q
	local a = q * 360
	pie.R.disc.Visible = a > 0
	pie.R.g.Rotation = min(a, 180)
	pie.L.disc.Visible = a > 180
	pie.L.g.Rotation = max(0, a - 180) + 180
	St.ringWrites = (St.ringWrites or 0) + 1
end

local ELEMENT_GLYPH = {
	Water = "\240\159\146\167", -- droplet
	Flame = "\240\159\148\165", -- fire
	Frost = "\226\157\132", -- snowflake
	Nature = "\240\159\141\131", -- leaf
	Earth = "\226\155\176", -- mountain
	Storm = "\226\154\161", -- lightning
	Celestial = "\226\156\168", -- sparkles
	Shadow = "\240\159\140\153", -- moon
}
local GLYPH = {
	Attack = "\226\154\148", -- crossed swords
	Special = "\226\152\133", -- star
	Dash = "\240\159\146\168", -- dash
	Swap = "\226\135\132", -- left-right arrows
	Heart = "\226\153\165", -- heart
	Crown = "\240\159\145\145",
	Star = "\226\152\133",
}

function Hud.Ensure()
	if Hud.gui and Hud.gui.Parent then
		return true
	end
	local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return false
	end
	local old = playerGui:FindFirstChild(K.GUI_NAME)
	if old then
		old:Destroy()
	end
	local gui = make("ScreenGui", {
		Name = K.GUI_NAME,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = K.DISPLAY_ORDER,
		Enabled = true,
	}, playerGui)
	local root = make("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
	Hud.scale = make("UIScale", { Name = "ReadScale", Scale = 1 }, root)
	Hud.gui, Hud.root = gui, root
	Hud.team = make("Frame", { Name = "Team", BackgroundTransparency = 1, Visible = false }, root)
	Hud.enemies = make("Frame", { Name = "Enemies", BackgroundTransparency = 1, Visible = false }, root)
	Hud.top = make("Frame", { Name = "TopCard", BackgroundTransparency = 1, Visible = false, AnchorPoint = Vector2.new(0.5, 0) }, root)
	Hud.cmd = make("Frame", { Name = "Commands", BackgroundTransparency = 1, Visible = false, AnchorPoint = Vector2.new(1, 1) }, root)
	Hud.resultCard = neonCard(root, "ResultCard", "Gold", { Visible = false, Size = UDim2.fromOffset(K.RESULT_W, 200), Floor = false })
	Hud.result = Hud.resultCard.Root
	Hud.rows = {}
	Hud.helpers = {}
	Hud.buttons = {}
	Hud.BuildFighter()
	Hud.BuildActions()
	Hud.BuildTop()
	return true
end

-- the screen in design pixels + the layout kind (Compact = a phone: touch, or a screen under 900 px wide / 600 high)
function Hud.Metrics()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	local inset = 36
	local ok, a = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if ok and typeof(a) == "Vector2" then
		inset = a.Y
	end
	local f = Theme.ScreenFactor(vp.Y)
	local w = vp.X / f
	local h = max(200, vp.Y - inset) / f
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local compact = touch or vp.X < K.COMPACT_W or vp.Y < K.COMPACT_H
	return { W = w, H = h, F = f, Compact = compact, Touch = touch, Landscape = vp.X > vp.Y, VX = vp.X, VY = vp.Y, Inset = inset }
end

-- the key hints (keyboard / gamepad)
function Hud.KeyText(kind, index)
	if St.gamepad then
		return ({ Attack = "X", Element = "Y", Special = "RB", Dash = "B", Buff = (index == 2) and "\226\134\145" or "LB", Swap = (index == 2) and "\226\134\146" or "\226\134\144" })[kind] or ""
	end
	return ({ Attack = "F", Element = "E", Special = "Q", Dash = "\226\135\167", Buff = tostring(index or 1), Swap = "hold " .. tostring(index or 1) })[kind] or ""
end

----------------------------------------------------------------------
-- the fighter card (top left) + the two helper portraits under it
----------------------------------------------------------------------
local function heart(parent, i)
	local l = label(parent, GLYPH.Heart, "Display", 20, { Name = "Heart" .. i, Size = UDim2.fromOffset(22, 22), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = COLORS.Life })
	return l
end

function Hud.BuildFighter()
	local team = Hud.team
	local card = neonCard(team, "Fighter", "Green", { Size = UDim2.fromOffset(K.FC_W, K.FC_H), Floor = true })
	Hud.fighterCard = card
	local body = card.Body
	local F = {}
	F.Name = label(body, "", "Heading", 26, { Name = "PetName", TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	F.Level = smallPill(body, "Lv 1", COLORS.LevelPill, { Name = "Level", AutomaticSize = Enum.AutomaticSize.None })
	F.Level.TextSize = 17
	F.Element = make("Frame", { Name = "Element", BackgroundColor3 = COLORS.Ally, BorderSizePixel = 0 }, body)
	Theme.Corner(F.Element, UDim.new(0.5, 0))
	Theme.Stroke(F.Element, COLORS.White, 1.5, 0.25)
	F.ElementGlyph = label(F.Element, "", "Display", 16, { Name = "Glyph", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	F.Stars = label(body, "", "Heading", 18, { Name = "Stars", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = COLORS.Gold })
	-- HP: track, the red loss trail, the green fill, the numbers
	F.Hp = make("Frame", { Name = "Hp", BackgroundColor3 = COLORS.Track, BorderSizePixel = 0 }, body)
	Theme.Corner(F.Hp, UDim.new(0, 7))
	Theme.Stroke(F.Hp, Theme.Colors.PanelInk or COLORS.Navy, 2, 0)
	F.HpLoss = make("Frame", { Name = "Loss", BackgroundColor3 = COLORS.Loss, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, F.Hp)
	Theme.Corner(F.HpLoss, UDim.new(0, 7))
	F.HpFill = make("Frame", { Name = "Fill", BackgroundColor3 = COLORS.HpGreen, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, F.Hp)
	Theme.Corner(F.HpFill, UDim.new(0, 7))
	make("UIGradient", { Name = "Shine", Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 200, 190)) }, F.HpFill)
	F.HpTag = label(F.Hp, "HP", "Heading", 16, { Name = "Tag", ZIndex = 3, TextXAlignment = Enum.TextXAlignment.Left })
	F.HpText = label(F.Hp, "", "Heading", 16, { Name = "Text", ZIndex = 3, TextXAlignment = Enum.TextXAlignment.Right })
	-- ENERGY (the special meter)
	F.Energy = make("Frame", { Name = "Energy", BackgroundColor3 = COLORS.Track, BorderSizePixel = 0 }, body)
	Theme.Corner(F.Energy, UDim.new(0, 5))
	Theme.Stroke(F.Energy, Theme.Colors.PanelInk or COLORS.Navy, 2, 0)
	F.EnergyFill = make("Frame", { Name = "Fill", BackgroundColor3 = COLORS.Energy, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1) }, F.Energy)
	Theme.Corner(F.EnergyFill, UDim.new(0, 5))
	F.EnergyText = label(body, "ENERGY 0/100", "Label", 15, { Name = "EnergyText", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = COLORS.EnergyText })
	F.Lives = make("Frame", { Name = "Lives", BackgroundTransparency = 1 }, body)
	F.Hearts = {}
	for i = 1, 3 do
		F.Hearts[i] = heart(F.Lives, i)
	end
	Hud.F = F
	-- the helpers: a portrait each (round pet picture in a ViewportFrame, the buff cooldown ring around it, Lv,
	-- the buff name, the SWAP chip, the key hint); tap = buff, hold 0.5 s = swap
	Hud.helperHolder = make("Frame", { Name = "Helpers", BackgroundTransparency = 1 }, team)
	for i = 1, 2 do
		Hud.helpers[i] = Hud.BuildHelper(i)
	end
end

function Hud.BuildHelper(i)
	local H = { index = i }
	local cell = make("Frame", { Name = "Helper" .. i, BackgroundTransparency = 1 }, Hud.helperHolder)
	H.Cell = cell
	H.Disc = make("Frame", { Name = "Disc", BackgroundTransparency = 1 }, cell)
	H.Ring = newPie(H.Disc, "Ring", K.RING, COLORS.Ally, 2)
	local face = make("TextButton", {
		Name = "Portrait",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Colors.PanelTop or COLORS.Navy,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 4,
	}, H.Disc)
	Theme.Corner(face, UDim.new(0.5, 0))
	H.FaceStroke = Theme.Stroke(face, COLORS.Ally, 3, 0)
	H.Face = face
	H.View = make("ViewportFrame", {
		Name = "View",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Ambient = Color3.fromRGB(200, 205, 220),
		LightColor = Color3.fromRGB(255, 250, 235),
	}, face)
	H.Initial = label(face, "", "Display", 26, { Name = "Initial", Size = UDim2.fromScale(1, 1), ZIndex = 6, TextXAlignment = Enum.TextXAlignment.Center })
	H.KO = label(face, "KO", "Title", 22, { Name = "KO", Size = UDim2.fromScale(1, 1), ZIndex = 7, Visible = false, TextColor3 = COLORS.White, BackgroundTransparency = 0.35, BackgroundColor3 = Color3.fromRGB(40, 44, 60) })
	Theme.Corner(H.KO, UDim.new(0.5, 0))
	H.Count = label(face, "", "Display", 24, { Name = "Count", Size = UDim2.fromScale(1, 1), ZIndex = 7, Visible = false, TextXAlignment = Enum.TextXAlignment.Center })
	H.Level = smallPill(cell, "Lv 1", COLORS.LevelPill, { Name = "Level", AutomaticSize = Enum.AutomaticSize.None, ZIndex = 8 })
	H.Level.TextSize = 16
	H.Buff = label(cell, "", "Heading", 15, { Name = "Buff", TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
	H.Swap = make("TextButton", { Name = "Swap", Text = GLYPH.Swap .. " SWAP", AutoButtonColor = true, BackgroundColor3 = Color3.fromRGB(40, 60, 120), BorderSizePixel = 0, ZIndex = 6 }, cell)
	Theme.Style(H.Swap, "Button", { Size = 15, Stroke = 0.2, Outline = 1.5 })
	Theme.Corner(H.Swap, UDim.new(0, 10))
	H.SwapStroke = Theme.Stroke(H.Swap, COLORS.SwapEdge, 2, 0)
	H.SwapFill = make("Frame", { Name = "HoldFill", BackgroundColor3 = COLORS.White, BackgroundTransparency = 0.7, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ZIndex = 7, Visible = false }, H.Swap)
	Theme.Corner(H.SwapFill, UDim.new(0, 10))
	H.Key = keyChip(cell, "1", { Name = "Key" })
	local index = i
	face.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			Input.HoldStart("portrait" .. index, index, os.clock())
		end
	end)
	face.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			Input.HoldEnd("portrait" .. index)
		end
	end)
	H.Swap.Activated:Connect(function()
		Input.Helper("Swap", index)
	end)
	return H
end

-- the round pet picture of a helper (PetBuilder Low in the ViewportFrame, built once per unit)
function Hud.Portrait(H, u)
	if H.unitId == u.id and H.built then
		return
	end
	H.unitId = u.id
	H.built = true
	for _, c in ipairs(H.View:GetChildren()) do
		c:Destroy()
	end
	setText(H.Initial, string.upper(string.sub(u.name or "?", 1, 1)))
	H.Initial.Visible = true
	if not PetBuilder then
		return
	end
	local ok = pcall(function()
		local def = Units.Def(u.info)
		if not def then
			return
		end
		local model = PetBuilder.Build(def, { Detail = "Low", Evolved = u.evo > 0 and u.evo or nil, Viewport = true })
		H.model = model
		local okBox, cf, size = pcall(model.GetBoundingBox, model)
		if not okBox or typeof(cf) ~= "CFrame" then
			cf, size = CFrame.new(), Vector3.new(3, 3, 3)
		end
		model.Parent = H.View
		local cam = make("Camera", { Name = "PortraitCamera", FieldOfView = 30 }, H.View)
		local r = max(size.X, size.Y, size.Z)
		local dist = r * 1.9 + 1
		local c = cf.Position + Vector3.new(0, size.Y * 0.08, 0)
		cam.CFrame = CFrame.new(c + Vector3.new(dist * 0.42, dist * 0.18, -dist * 0.9), c)
		H.View.CurrentCamera = cam
		H.Initial.Visible = false
	end)
	if not ok then
		H.Initial.Visible = true
	end
end

----------------------------------------------------------------------
-- the action cluster (bottom right): ATTACK (big), ELEMENT, SPECIAL, DASH; cooldown rings, key chips on desktop
----------------------------------------------------------------------
local ACTIONS = { "Attack", "Element", "Special", "Dash" }

function Hud.BuildActions()
	for _, kind in ipairs(ACTIONS) do
		local A = { kind = kind }
		local b = make("TextButton", {
			Name = kind .. "Button",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 2,
		}, Hud.cmd)
		A.Button = b
		A.Glow = make("Frame", { Name = "Glow", BackgroundColor3 = COLORS.Gold, BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 14, 1, 14), ZIndex = 1 }, b)
		Theme.Corner(A.Glow, UDim.new(0.5, 0))
		A.Ring = newPie(b, "Ring", 10, COLORS.Action[kind], 2)
		A.Ring.Root.Size = UDim2.new(1, 0, 1, 0)
		local face = make("Frame", { Name = "Face", BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -10, 1, -10), ZIndex = 3 }, b)
		Theme.Corner(face, UDim.new(0.5, 0))
		local base = COLORS.Action[kind]
		A.FaceGradient = make("UIGradient", { Name = "Fill", Rotation = 90, Color = ColorSequence.new(Theme.Darken(base, 0.35), Theme.Darken(base, 0.72)) }, face)
		A.FaceStroke = Theme.Stroke(face, Theme.Lighten(base, 0.25), 2.5, 0)
		A.Face = face
		A.Glyph = label(face, GLYPH[kind] or "", "Display", 30, { Name = "Glyph", Size = UDim2.fromScale(1, 1), ZIndex = 4, TextXAlignment = Enum.TextXAlignment.Center })
		A.Count = label(face, "", "Display", 26, { Name = "Count", Size = UDim2.fromScale(1, 1), ZIndex = 5, Visible = false, TextXAlignment = Enum.TextXAlignment.Center })
		A.Caption = label(b, string.upper(kind), "Heading", 15, { Name = "Caption", AnchorPoint = Vector2.new(0.5, 0), ZIndex = 6, TextXAlignment = Enum.TextXAlignment.Center })
		A.Key = keyChip(b, Hud.KeyText(kind), { Name = "Key", AnchorPoint = Vector2.new(0.5, 0.5) })
		Hud.buttons[kind] = A
		local action = kind
		b.InputBegan:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
				Input.Press(action, true)
				if action == "Attack" then
					-- bug #16: hold 0.4 s = the next target; the hold remembers its input + button so a slide off the button
					-- (whose own InputEnded may never fire) cancels it instead of re-targeting
					Input.HoldStart("attackButton", 0, os.clock(), "Attack", input, b)
				end
			end
		end)
		b.InputEnded:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
				Input.Press(action, false)
				if action == "Attack" then
					Input.HoldEnd("attackButton")
				end
			end
		end)
	end
	Hud.attack = Hud.buttons.Attack.Button
	Hud.leave = Leave.Make(Hud.root, 20)
	CheerUp.Make(Hud.root)
end

----------------------------------------------------------------------
-- the top card (top centre, under the Roblox bar): the mode line + timer; in raids / boss rooms the boss bar
----------------------------------------------------------------------
function Hud.BuildTop()
	local top = Hud.top
	local mode = neonCard(top, "ModeCard", "Blue", { Size = UDim2.fromOffset(K.TOP_W, K.MODE_H), Floor = false })
	Hud.modeCard = mode
	Hud.mode = label(mode.Body, "", "Heading", 20, { Name = "Mode", TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	Hud.timer = label(mode.Body, "", "Display", 24, { Name = "Timer", TextXAlignment = Enum.TextXAlignment.Right })
	local boss = make("Frame", { Name = "BossBar", BackgroundTransparency = 1, Visible = false }, top)
	Hud.boss = boss
	Hud.bossName = label(boss, "", "Heading", 18, { Name = "BossName", TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	Hud.bossTrack = make("Frame", { Name = "Hp", BackgroundColor3 = COLORS.Track, BorderSizePixel = 0 }, boss)
	Theme.Corner(Hud.bossTrack, UDim.new(0, 8))
	Theme.Stroke(Hud.bossTrack, Theme.Colors.PanelInk or COLORS.Navy, 2.5, 0)
	Hud.bossFill = make("Frame", { Name = "Fill", BackgroundColor3 = COLORS.Enemy, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, Hud.bossTrack)
	Theme.Corner(Hud.bossFill, UDim.new(0, 8))
	Hud.bossText = label(Hud.bossTrack, "", "Heading", 16, { Name = "Text", Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0), ZIndex = 3, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
	Hud.pills = make("Frame", { Name = "Pills", BackgroundTransparency = 1 }, top)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, Hud.pills)
	Hud.bossElement = smallPill(Hud.pills, "", COLORS.Enemy, { Name = "Element", LayoutOrder = 1 })
	Hud.enragePill = smallPill(Hud.pills, "ENRAGED", COLORS.Enemy, { Name = "Enraged", LayoutOrder = 2, Visible = false })
	Hud.minionPill = smallPill(Hud.pills, "", Color3.fromRGB(150, 110, 220), { Name = "Minions", LayoutOrder = 3, Visible = false })
	Hud.playersPill = smallPill(Hud.pills, "", COLORS.Ally, { Name = "Players", LayoutOrder = 4, Visible = false })
	Hud.wavePill = smallPill(Hud.pills, "", Theme.Neon.Purple or COLORS.Ally, { Name = "Wave", LayoutOrder = 5, Visible = false })
	Ring.BuildInfo(top)
end

----------------------------------------------------------------------
-- the enemy list (right side): one row per living enemy, the LOCKED one first with a gold bracket + "TARGET"
----------------------------------------------------------------------
local function rowFor(i)
	local row = Hud.rows[i]
	if row then
		return row
	end
	row = {}
	local f = make("TextButton", { Name = "Row" .. i, Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.Colors.PanelTop or COLORS.Panel, BackgroundTransparency = 0.12, BorderSizePixel = 0 }, Hud.enemies)
	Theme.Corner(f, UDim.new(0, 12))
	row.Stroke = Theme.Stroke(f, Theme.Colors.PanelInk or COLORS.Navy, 2, 0)
	make("UIGradient", { Name = "Fill", Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 156, 186)) }, f)
	row.Frame = f
	row.Stripe = make("Frame", { Name = "Element", BorderSizePixel = 0, BackgroundColor3 = COLORS.Ally }, f)
	Theme.Corner(row.Stripe, UDim.new(0, 3))
	row.Icon = make("Frame", { Name = "Icon", BorderSizePixel = 0, BackgroundColor3 = COLORS.Enemy, ZIndex = 2 }, f)
	Theme.Corner(row.Icon, UDim.new(0.5, 0))
	row.IconStroke = Theme.Stroke(row.Icon, COLORS.White, 2, 0.2)
	row.IconText = label(row.Icon, "", "Display", 20, { Name = "Glyph", Size = UDim2.fromScale(1, 1), ZIndex = 3, TextXAlignment = Enum.TextXAlignment.Center })
	row.Alert = label(row.Icon, "!", "Title", 24, { Name = "Alert", Size = UDim2.fromScale(1, 1), ZIndex = 4, Visible = false, TextColor3 = COLORS.Alert, BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(120, 30, 40) })
	Theme.Corner(row.Alert, UDim.new(0.5, 0))
	row.Name = label(f, "", "Body", 18, { Name = "PetName", TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2 })
	row.Hp = thinBar(f, "Hp", 9, COLORS.Enemy, { ZIndex = 2 })
	row.Bracket = make("Frame", { Name = "Bracket", BackgroundTransparency = 1, Size = UDim2.new(1, 8, 1, 8), Position = UDim2.fromOffset(-4, -4), Visible = false, ZIndex = 1 }, f)
	Theme.Corner(row.Bracket, UDim.new(0, 15))
	Theme.Stroke(row.Bracket, COLORS.Gold, 3, 0)
	row.Target = smallPill(f, "TARGET", COLORS.Gold, { Name = "Target", Visible = false, ZIndex = 5 })
	row.Target.TextColor3 = Theme.Colors.PanelInk or COLORS.Navy
	local index = i
	f.Activated:Connect(function()
		local id = row.unitId
		if id then
			local B = St.battle
			if B and B.lock == id and (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then
				BattleController.Focus(nil) -- tap the locked row again: clear
			else
				BattleController.Focus(id)
			end
		end
		return index
	end)
	Hud.rows[i] = row
	return row
end

-- the enemies the list shows, the locked one first (the rest in id order: rows reorder only on a KO / lock change)
function Hud.EnemyList(B)
	local out, locked = {}, nil
	for _, u in ipairs(B.list) do
		if not u.ally and not u.isBoss and u.hp > 0 and u.state ~= S_DOWN and u.state ~= S_BENCHED then
			if B.lock == u.id then
				locked = u
			else
				out[#out + 1] = u
			end
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	if locked then
		table.insert(out, 1, locked)
	end
	return out
end

-- lays the rows out (on Rebuild and when the set / the lock changed); returns the list's height
function Hud.LayoutEnemies(B, m)
	local list = Hud.EnemyList(B)
	Hud.enemyList = list
	local key = tostring(B.lock or 0)
	for _, u in ipairs(list) do
		key = key .. "," .. u.id
	end
	Hud.enemyKey = key
	local maxRows = m.Compact and K.ROWS_COMPACT or K.ROWS_MAX
	local n = min(#list, maxRows)
	local w, h = m.Compact and K.ROW_W_COMPACT or K.ROW_W, m.Compact and K.ROW_H_COMPACT or K.ROW_H
	local y = 0
	for i = 1, max(n, #Hud.rows) do
		local row = (i <= n) and rowFor(i) or Hud.rows[i]
		if row then
			row.Frame.Visible = i <= n
		end
		if i <= n then
			local u = list[i]
			local locked = B.lock == u.id
			row.unitId = u.id
			row.Frame.Size = UDim2.fromOffset(w, h)
			row.Frame.Position = UDim2.fromOffset(0, y)
			row.Stripe.Size = UDim2.fromOffset(5, h - 14)
			row.Stripe.Position = UDim2.fromOffset(6, 7)
			row.Stripe.BackgroundColor3 = elementColor(u.element)
			local icon = h - 10
			row.Icon.Size = UDim2.fromOffset(icon, icon)
			row.Icon.Position = UDim2.fromOffset(16, 5)
			row.Icon.BackgroundColor3 = elementColor(u.element):Lerp(COLORS.Navy, 0.25)
			local boss = u.kind == "MiniBoss" or u.info.boss ~= nil
			setText(row.IconText, boss and GLYPH.Crown or string.upper(string.sub(u.name, 1, 1)))
			row.IconText.TextSize = boss and (icon * 0.55) or (icon * 0.6)
			row.IconText:SetAttribute("BaseText", row.IconText.TextSize)
			local x = 16 + icon + 8
			row.Name.Position = UDim2.fromOffset(x, 3)
			row.Name.Size = UDim2.fromOffset(w - x - 10, h - 18)
			row.Name.TextSize = m.Compact and 16 or 18
			row.Name:SetAttribute("BaseText", row.Name.TextSize)
			setText(row.Name, (u.info.wild and not boss) and ("Wild " .. u.name) or u.name)
			row.Hp.Root.Position = UDim2.fromOffset(x, h - 15)
			row.Hp.Root.Size = UDim2.fromOffset(w - x - 10, 9)
			row.Bracket.Visible = locked
			-- "TARGET": a gold tab on the locked row's top edge (wide screens; a phone keeps the bracket only)
			row.Target.Visible = locked and not m.Compact
			row.Target.AnchorPoint = Vector2.new(1, 0.5)
			row.Target.Position = UDim2.new(1, -10, 0, -2)
			row.Target.Size = UDim2.fromOffset(78, 20)
			row.Target.AutomaticSize = Enum.AutomaticSize.None
			row.Target.TextSize = 15
			row.Stroke.Color = locked and COLORS.Gold or (boss and COLORS.Gold:Lerp(COLORS.Navy, 0.45) or (Theme.Colors.PanelInk or COLORS.Navy))
			row.hpKey = nil
			y = y + h + K.ROW_GAP
		end
	end
	local more = #list - n
	if not Hud.more then
		Hud.more = label(Hud.enemies, "", "Heading", 16, { Name = "More", TextXAlignment = Enum.TextXAlignment.Right })
	end
	Hud.more.Visible = more > 0
	if more > 0 then
		setText(Hud.more, "+" .. more .. " more")
		Hud.more.Position = UDim2.fromOffset(0, y)
		Hud.more.Size = UDim2.fromOffset(w, 22)
		y = y + 24
	end
	Hud.enemies.Size = UDim2.fromOffset(w, max(0, y - K.ROW_GAP))
	return y
end

----------------------------------------------------------------------
-- placement around the other GUIs (measured, not guessed)
----------------------------------------------------------------------
-- the bottom of the HUD's currency pills when they sit at the TOP (a landscape phone's top band / the top right),
-- in design px of our root (gui area below the top bar); 0 when they are elsewhere
function Hud.CurrencyTop(m)
	local pg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
	local hud = pg and pg:FindFirstChild("NimbusHud")
	local cur = hud and hud:FindFirstChild("Currency", true)
	if not cur or not cur:IsA("GuiObject") or not cur.Visible or cur.AbsoluteSize.X <= 0 then
		return 0, 0, 0
	end
	local p, s = cur.AbsolutePosition, cur.AbsoluteSize
	local f = max(0.05, m.F)
	if p.Y > m.VY * 0.3 then
		return 0, 0, 0 -- bottom left: not in our way at the top
	end
	return max(0, math.ceil((p.Y + s.Y) / f)), floor(p.X / f), math.ceil((p.X + s.X) / f)
end

-- the right edge (design px) of MenuController's tile column (NimbusMenu.MenuColumn; its frame keeps its place while
-- the tiles step aside), 0 when there is none
function Hud.MenuRight(m)
	local pg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
	local menu = pg and pg:FindFirstChild("NimbusMenu")
	local col = menu and menu:IsA("ScreenGui") and menu.Enabled and menu:FindFirstChild("MenuColumn", true)
	if not col or not col:IsA("GuiObject") or not col.Visible or col.AbsoluteSize.X <= 0 then
		return 0
	end
	local right = (col.AbsolutePosition.X + col.AbsoluteSize.X) / max(0.05, m.F)
	if right > m.W * 0.3 then
		return 0 -- not a left column
	end
	return math.ceil(right)
end

-- Roblox's touch jump button + MovementController's RUN button (screen px, from the left / BOTTOM edge)
function Hud.TouchRects(m)
	local small = min(m.VX, m.VY) <= 500
	local jump = small and 70 or 120
	local jb = small and 20 or jump * 0.75
	local rects = { jump = { m.VX - jump * 1.5 - 10, jb, m.VX - jump * 0.5 - 10, jb + jump } }
	local mc = Hud.Movement()
	if mc and type(mc.MobileLayout) == "function" then
		local ok, l = pcall(mc.MobileLayout)
		if ok and type(l) == "table" and type(l.run) == "table" then
			rects.run = l.run
		end
	end
	if not rects.run then
		local d = small and 66 or 84
		local right = max(14, jump + 10 - d * 0.5)
		local bottom = jb + jump + 10
		rects.run = { m.VX - right - d, bottom, m.VX - right, bottom + d }
	end
	return rects
end

-- the action buttons' centres + diameters (design px, Commands-local; Commands is anchored at its bottom-right
-- corner = the gui area's bottom-right corner) and the cluster's size. Touch phones: around Roblox's jump button and
-- the RUN button (MovementController puts RUN straight above the jump button in a battle), clear of the centre 40%.
function Hud.ClusterLayout(m)
	local big, small = K.ATTACK_D, K.ACTION_D
	local out = {}
	if not (m.Compact and m.Touch) then
		out.Attack = { -74, -98, big }
		out.Special = { -74 - big / 2 - 26 - small / 2, -90, small }
		out.Element = { -74, -98 - big / 2 - 36 - small / 2, small }
		out.Dash = { -74 - big / 2 - 26 - small / 2, -98 - big / 2 - 28 - small / 2, small }
		out.w, out.h = 236, 270
		return out
	end
	local f = max(0.05, m.F)
	local r = Hud.TouchRects(m)
	local gap = 7 * f
	local bigPx, smallPx = big * f, small * f
	local vx = m.VX
	-- screen px (x from the left, yb from the bottom) -> Commands-local design px
	local function at(cx, cyb, d)
		return { (cx - vx) / f, -cyb / f, d }
	end
	if m.VY >= m.VX then
		-- portrait: up the right edge above the RUN button: ATTACK, then [SPECIAL][ELEMENT], then DASH
		local right = vx - 10 * f
		local base = max(r.jump[4], r.run[4]) + gap + 2
		out.Attack = at(right - bigPx / 2 - 4 * f, base + bigPx / 2, big)
		local row2 = base + bigPx + gap
		out.Element = at(right - smallPx / 2, row2 + smallPx / 2, small)
		out.Special = at(right - smallPx - gap - smallPx / 2, row2 + smallPx / 2, small)
		local row3 = row2 + smallPx + gap
		out.Dash = at(right - smallPx / 2, row3 + smallPx / 2, small)
	else
		-- landscape: [SPECIAL][ATTACK] left of the jump button (the bottom strip), ELEMENT then DASH above ATTACK
		local left = r.jump[1] - gap
		local base = r.jump[2]
		out.Attack = at(left - bigPx / 2, base + bigPx / 2, big)
		out.Special = at(left - bigPx - gap - smallPx / 2, base + smallPx / 2, small)
		local row2 = base + bigPx + gap
		out.Element = at(left - bigPx / 2, row2 + smallPx / 2, small)
		out.Dash = at(left - bigPx / 2, row2 + smallPx + gap + smallPx / 2, small)
	end
	out.w, out.h = 10, 10
	return out
end

----------------------------------------------------------------------
-- (re)builds the HUD for the drawn battle and lays it out for the screen
----------------------------------------------------------------------
function Hud.Rebuild()
	local B = St.battle
	if not Hud.Ensure() then
		return
	end
	local m = Hud.Metrics()
	Hud.m = m
	Hud.scale.Scale = m.F
	Hud.root.Size = UDim2.new(1 / m.F, 0, 1 / m.F, 0)
	if not B then
		Hud.top.Visible = false
		Hud.team.Visible = false
		Hud.cmd.Visible = false
		Hud.enemies.Visible = false
		Hud.SetMenuHidden(false)
		Leave.Place(m, nil, false)
		CheerUp.Place(m, nil, false)
		return
	end
	local isFighting = B.Fighter and not B.ended
	-- between two ring rounds the top card and the fighter card stay (no flicker); the commands go
	local between = B.Fighter and B.ended and B.ringNext ~= nil
	local curBottom, curLeft, curRight = Hud.CurrencyTop(m)
	local topY = K.EDGE
	-- (a landscape phone's currency pills sit in the top band: stay below them where they reach down)
	local cardW = m.Compact and K.FC_W_COMPACT or K.FC_W
	Hud.fcW = nil
	if m.Compact and curBottom > 0 and curLeft >= K.EDGE + 208 and curLeft < K.EDGE + cardW + 8 then
		-- (a phone with the currency pills at the top right: a narrower fighter card fits beside them)
		Hud.fcW = curLeft - K.EDGE - 8
		cardW = Hud.fcW
	end
	local leftY = (curBottom > 0 and curLeft < K.EDGE + cardW + 8) and (curBottom + 6) or topY
	-- fighter card + helpers (top left) ----------------------------------------------------------
	Hud.team.Visible = isFighting or between
	local teamW, teamH = 0, 0
	if isFighting or between then
		teamW, teamH = Hud.LayoutFighter(B, m)
		-- a wide screen keeps the menu tiles (left centre): the fighter block starts right of their column
		local teamX = K.EDGE
		if not m.Compact then
			teamX = max(K.EDGE, Hud.MenuRight(m) + 10)
		end
		Hud.team.Position = UDim2.fromOffset(teamX, leftY)
		Hud.team.Size = UDim2.fromOffset(teamW, teamH)
		Hud.FillFighter(B)
	end
	Hud.teamPlace = (isFighting or between) and "TopLeft" or nil
	-- enemy list (right) -----------------------------------------------------------------------------
	local rightY = (curBottom > 0 and curRight > m.W * m.F - (K.ROW_W + 40) * m.F) and (curBottom + 6) or topY
	Hud.enemies.Visible = isFighting
	local listH = 0
	if isFighting then
		listH = Hud.LayoutEnemies(B, m)
		Hud.enemies.AnchorPoint = Vector2.new(1, 0)
		Hud.enemies.Position = UDim2.fromOffset(m.W - K.EDGE, rightY)
	end
	-- top card (mode line / boss bar) -------------------------------------------------------------
	Hud.LayoutTop(B, m, teamW, listH, rightY, isFighting or between)
	-- action cluster ---------------------------------------------------------------------------------
	Hud.cmd.Visible = isFighting
	if isFighting then
		local L = Hud.ClusterLayout(m)
		Hud.cmd.Size = UDim2.fromOffset(L.w, L.h)
		Hud.cmd.Position = UDim2.fromOffset(m.W, m.H)
		for _, kind in ipairs(ACTIONS) do
			local A = Hud.buttons[kind]
			local spec = L[kind]
			local d = spec[3]
			A.Button.Size = UDim2.fromOffset(d, d)
			A.Button.Position = UDim2.new(1, spec[1], 1, spec[2])
			A.Glyph.TextSize = floor(d * 0.4)
			A.Glyph:SetAttribute("BaseText", A.Glyph.TextSize)
			A.Count.TextSize = floor(d * 0.36)
			A.Count:SetAttribute("BaseText", A.Count.TextSize)
			A.Caption.Visible = not m.Touch
			A.Caption.Position = UDim2.new(0.5, 0, 1, 2)
			A.Caption.Size = UDim2.fromOffset(d + 24, 20)
			A.Caption.TextTruncate = Enum.TextTruncate.AtEnd
			A.Key.Visible = not m.Touch
			A.Key.Position = UDim2.new(0.15, 0, 0.15, 0)
		end
		Hud.Captions(B)
		Hud.Keys()
	end
	Hud.SetMenuHidden((isFighting or between) and m.Compact) -- a phone: the menu column steps aside (wide screens keep it)
	Leave.Place(m, B, isFighting)
	CheerUp.Place(m, B, isFighting)
	Ring.PlaceNext(B)
	Hud.FixText(Hud.root, m.F)
	Hud.last = {}
	Hud.enemyDirty = false
	Hud.Update(B, os.clock(), true)
end

-- the fighter card + helper cells (sizes + positions; Team-local); returns the Team block's size
function Hud.LayoutFighter(B, m)
	local F = Hud.F
	local compact = m.Compact
	local w = compact and (Hud.fcW or K.FC_W_COMPACT) or K.FC_W
	local pad = compact and 10 or 16
	local barW = w - 2 * pad
	local y = compact and 8 or 12
	local nameSize = compact and 20 or 26
	local nameH = compact and 26 or 32
	F.Name.TextSize = nameSize
	F.Name:SetAttribute("BaseText", nameSize)
	local minSize = math.ceil(K.MIN_TEXT_PX / max(0.05, m.F))
	local lvSize = max(compact and 15 or 17, minSize)
	local lvW = floor(textWidth("Lv 100", lvSize) * 0.9) + 14
	local badge = compact and 22 or 26
	local starsW = (B.fighterEvo or 0) > 0 and (compact and 30 or 38) or 0
	local nameW = barW - lvW - badge - starsW - 16
	F.Name.Position = UDim2.fromOffset(pad, y)
	F.Name.Size = UDim2.fromOffset(nameW, nameH)
	F.Level.Size = UDim2.fromOffset(lvW, compact and 22 or 26)
	F.Level.Position = UDim2.fromOffset(pad + nameW + 6, y + (nameH - (compact and 22 or 26)) / 2)
	F.Level.TextSize = lvSize
	F.Level:SetAttribute("BaseText", lvSize)
	F.Element.Size = UDim2.fromOffset(badge, badge)
	F.Element.Position = UDim2.fromOffset(pad + nameW + 6 + lvW + 5, y + (nameH - badge) / 2)
	F.ElementGlyph.TextSize = floor(badge * 0.6)
	F.ElementGlyph:SetAttribute("BaseText", F.ElementGlyph.TextSize)
	F.Stars.Position = UDim2.fromOffset(pad + nameW + 6 + lvW + 5 + badge + 4, y)
	F.Stars.Size = UDim2.fromOffset(starsW, nameH)
	F.Stars.Visible = starsW > 0
	y = y + nameH + (compact and 4 or 6)
	local hpH = compact and 18 or 22
	F.Hp.Position = UDim2.fromOffset(pad, y)
	F.Hp.Size = UDim2.fromOffset(barW, hpH)
	local hpText = compact and 14 or 16
	F.HpTag.TextSize = hpText
	F.HpText.TextSize = hpText
	F.HpTag:SetAttribute("BaseText", hpText)
	F.HpText:SetAttribute("BaseText", hpText)
	F.HpTag.Position = UDim2.fromOffset(8, 0)
	F.HpTag.Size = UDim2.new(0, 40, 1, 0)
	F.HpText.Position = UDim2.fromOffset(40, 0)
	F.HpText.Size = UDim2.new(1, -48, 1, 0)
	y = y + hpH + (compact and 5 or 7)
	local enH = compact and 10 or 14
	F.Energy.Position = UDim2.fromOffset(pad, y)
	F.Energy.Size = UDim2.fromOffset(barW, enH)
	y = y + enH + 3
	local capH = compact and 18 or 22
	local hs = compact and 18 or 22
	-- the caption ends where the lives hearts (anchored right) begin; a narrow card (a phone with the currency
	-- pills top right) drops the "ENERGY" word, so "98/100" never runs under the hearts
	local capW = max(0, barW - (3 * hs + 4) - 6)
	local capSize = compact and 14 or 15
	F.EnergyText.Position = UDim2.fromOffset(pad, y)
	F.EnergyText.Size = UDim2.fromOffset(capW, capH)
	F.EnergyText.TextSize = capSize
	F.EnergyText.TextTruncate = Enum.TextTruncate.AtEnd
	F.EnergyText:SetAttribute("BaseText", capSize)
	Hud.energyShort = textWidth("ENERGY " .. METER_MAX .. "/" .. METER_MAX, max(capSize, minSize)) > capW
	F.Lives.AnchorPoint = Vector2.new(1, 0)
	F.Lives.Position = UDim2.fromOffset(pad + barW, y + (capH - hs) / 2)
	F.Lives.Size = UDim2.fromOffset(3 * hs + 4, hs)
	for i, h in ipairs(F.Hearts) do
		h.Size = UDim2.fromOffset(hs, hs)
		h.Position = UDim2.fromOffset((i - 1) * (hs + 2), 0)
		h.TextSize = hs - 2
		h:SetAttribute("BaseText", hs - 2)
	end
	y = y + capH + (compact and 6 or 10)
	local cardH = y
	Hud.fighterCard.Root.Size = UDim2.fromOffset(w, cardH)
	Hud.fighterCard.Root.Position = UDim2.fromOffset(0, 0)
	-- helpers: side by side under the card (wide) / a column (compact)
	local disc = compact and K.PORTRAIT_COMPACT or K.PORTRAIT
	local ringD = disc + (compact and 8 or 10)
	local cellW = compact and K.HELPER_W_COMPACT or K.HELPER_W
	if compact then
		cellW = max(ringD + 70, min(cellW, floor(m.W * 0.3) - K.EDGE)) -- (a phone: the column ends before the centre 40%)
	end
	Hud.helperCellW = cellW
	local cellH = compact and max(ringD + 4, 56) or (ringD + 70)
	local hy = cardH + (compact and 8 or 10)
	Hud.helperHolder.Position = UDim2.fromOffset(0, hy)
	local shown = 0
	for i, H in ipairs(Hud.helpers) do
		local cell = H.Cell
		cell.Size = UDim2.fromOffset(cellW, cellH)
		if compact then
			-- [portrait] [buff name / SWAP chip]: a narrow column (clear of the vitals card on a landscape phone)
			cell.Position = UDim2.fromOffset(0, (i - 1) * (cellH + 6))
			H.Disc.Position = UDim2.fromOffset(0, 2)
			H.Disc.Size = UDim2.fromOffset(ringD, ringD)
			H.Level.Position = UDim2.fromOffset(ringD / 2 - 24, ringD - 14)
			H.Level.Size = UDim2.fromOffset(48, 18)
			H.Buff.Font = Theme.Fonts.Label
			H.Buff.Position = UDim2.fromOffset(ringD + 6, 0)
			H.Buff.Size = UDim2.fromOffset(cellW - ringD - 6, 22)
			H.Buff.TextXAlignment = Enum.TextXAlignment.Left
			H.Swap.Position = UDim2.fromOffset(ringD + 6, 24)
			H.Swap.Size = UDim2.fromOffset(cellW - ringD - 6, 30)
			H.Key.Position = UDim2.fromOffset(-4, -2)
		else
			cell.Position = UDim2.fromOffset((i - 1) * (cellW + 12), 0)
			H.Disc.Position = UDim2.fromOffset((cellW - ringD) / 2, 0)
			H.Disc.Size = UDim2.fromOffset(ringD, ringD)
			H.Level.Position = UDim2.fromOffset(cellW / 2 - 28, ringD - 12)
			H.Level.Size = UDim2.fromOffset(56, 20)
			H.Buff.Font = Theme.Fonts.Heading
			H.Buff.Position = UDim2.fromOffset(0, ringD + 12)
			H.Buff.Size = UDim2.fromOffset(cellW, 20)
			H.Buff.TextXAlignment = Enum.TextXAlignment.Center
			H.Swap.Position = UDim2.fromOffset((cellW - 104) / 2, ringD + 36)
			H.Swap.Size = UDim2.fromOffset(104, 28)
			H.Key.Position = UDim2.fromOffset((cellW - ringD) / 2 - 6, -4)
		end
		H.Ring.Root.Size = UDim2.fromOffset(ringD, ringD)
		H.Face.Size = UDim2.fromOffset(disc, disc)
		H.Initial.TextSize = floor(disc * 0.45)
		H.Initial:SetAttribute("BaseText", H.Initial.TextSize)
		H.Count.TextSize = floor(disc * 0.42)
		H.Count:SetAttribute("BaseText", H.Count.TextSize)
		H.Key.Visible = not m.Touch
		if cell.Visible then
			shown = shown + 1
		end
	end
	local helpersH = compact and (2 * cellH + 6) or cellH
	Hud.helperHolder.Size = UDim2.fromOffset(compact and cellW or (2 * cellW + 12), helpersH)
	return max(w, compact and cellW or (2 * cellW + 12)), hy + helpersH
end

-- the fighter card's static texts (name, level, element, stars) and the helper cells' pets (on Start / Swap)
function Hud.FillFighter(B)
	local F = Hud.F
	local f = B.fighterId and B.units[B.fighterId]
	if f then
		setText(F.Name, f.name)
		setText(F.Level, "Lv " .. tostring(floor(f.level)))
		F.Element.BackgroundColor3 = elementColor(f.element)
		setText(F.ElementGlyph, ELEMENT_GLYPH[f.element] or "")
		setText(F.Stars, string.rep(GLYPH.Star, clamp(f.evo or 0, 0, 2)))
		if Hud.fighterCard.SetColor then
			pcall(Hud.fighterCard.SetColor, elementColor(f.element):Lerp(Theme.Neon.Green or COLORS.Mine, 0.55))
		end
	end
	local bench = Hud.Bench(B)
	for i, H in ipairs(Hud.helpers) do
		local u = bench[i]
		H.unit = u
		H.Cell.Visible = u ~= nil
		if u then
			H.slot = u.slot
			setText(H.Level, "Lv " .. tostring(floor(u.level)))
			local buff = type(u.info.buff) == "table" and u.info.buff or nil
			H.buffName = buff and string.upper(tostring(buff.Name or buff.Kind or "BUFF")) or "BUFF"
			setText(H.Buff, H.buffName)
			local c = elementColor(u.element)
			H.FaceStroke.Color = c
			setPie(H.Ring, H.Ring.frac >= 0 and H.Ring.frac or 1, c)
			Hud.Portrait(H, u)
		end
		H.stateKey = nil
	end
end

-- my two helpers (benched units, by slot), as the portraits show them
function Hud.Bench(B)
	local out = {}
	for slot = 1, 4 do
		local u = B.mine[slot]
		if u and u.id ~= B.fighterId then
			out[#out + 1] = u
		end
	end
	return out
end

-- the action captions: ATTACK picks the enemy the pet attacks (it attacks by itself), the element attack's name
function Hud.Captions(B)
	local f = B.fighterId and B.units[B.fighterId]
	local ea = f and type(f.info.elementAttack) == "table" and f.info.elementAttack or nil
	local caps = {
		-- bug #16: ATTACK (a tap attacks the lock / the nearest); NEXT for NEXT_FLASH after a hold picked the next target
		Attack = (St.nextFlashUntil and os.clock() < St.nextFlashUntil) and "NEXT" or "ATTACK",
		Element = ea and string.upper(tostring(ea.Name)) or "ELEMENT",
		Special = "SPECIAL",
		Dash = "DASH",
	}
	for kind, A in pairs(Hud.buttons) do
		setText(A.Caption, caps[kind] or kind)
		if kind == "Element" and f then
			setText(A.Glyph, ELEMENT_GLYPH[f.element] or GLYPH.Special)
			local c = elementColor(f.element)
			A.FaceGradient.Color = ColorSequence.new(Theme.Darken(c, 0.3), Theme.Darken(c, 0.7))
			A.FaceStroke.Color = Theme.Lighten(c, 0.25)
			setPie(A.Ring, A.Ring.frac >= 0 and A.Ring.frac or 1, c)
		end
	end
end

-- the top card: the mode line + timer (+ the boss bar in raids / boss rooms, the ring pills); returns nothing
function Hud.LayoutTop(B, m, teamW, listH, rightY, show)
	local top = Hud.top
	local spectator = not B.Fighter
	top.Visible = show or spectator
	if not top.Visible then
		return
	end
	local bossUnit = Hud.BossUnit(B)
	local w = m.Compact and K.TOP_W_COMPACT or K.TOP_W
	local x, y, anchor = m.W / 2, K.EDGE, 0.5
	local underList, leftTop = false, false
	local curBottom, curLeft, curRight = Hud.CurrencyTop(m)
	if m.Compact then
		-- between the fighter card and the enemy list when there is room, else under the enemy list (right)
		local free = m.W - (K.EDGE + teamW + 12) - (K.ROW_W_COMPACT + K.EDGE + 12)
		if free >= w then
			x = K.EDGE + teamW + 12 + free / 2
			if m.Landscape and Leave.Allowed(B) and free >= w + 8 + K.LEAVE_W_TOP then
				x = K.EDGE + teamW + 12 + (free - 8 - K.LEAVE_W_TOP) / 2 -- room for LEAVE on its right
			end
		elseif spectator then
			w = min(w, m.W - 2 * K.EDGE)
		else
			-- a tall phone: under the enemy list at the right edge, clear of the helper column on the left
			w = min(w, m.W - K.EDGE - K.HELPER_W_COMPACT - 24)
			x, anchor = m.W - K.EDGE, 1
			y = rightY + listH + 10
			underList = listH > 0
			local guess = K.MODE_H + 6 + (bossUnit and 32 or 0) + ((B.Mode == "Ring") and 30 or 0)
			if underList and not m.Landscape and Hud.team.Visible and Hud.fighterCard and y + guess > m.H * 0.3 - 4 then
				-- (the right column starts low - currency pills up there - and would reach the centre band: the top
				-- card goes under the fighter card instead, the helper column moves down under it)
				leftTop = true
				w = min(w, m.W - K.EDGE - K.ROW_W_COMPACT - 8 - K.EDGE)
				x, anchor = Hud.team.Position.X.Offset, 0
				y = Hud.team.Position.Y.Offset + Hud.fighterCard.Root.Size.Y.Offset + 8
				underList = false
			end
			if listH <= 0 and Hud.team.Visible and Hud.fighterCard then
				-- (between two ring rounds the enemy list is gone: stay under the fighter card, beside the helpers)
				y = max(y, Hud.team.Position.Y.Offset + Hud.fighterCard.Root.Size.Y.Offset + 8)
			end
		end
	end
	-- (a landscape phone's currency pills in the top band: stay under them where they overlap)
	if curBottom > 0 and anchor == 0.5 and curRight > x - w / 2 and curLeft < x + w / 2 then
		y = max(y, curBottom + 4)
	end
	top.AnchorPoint = Vector2.new(anchor, 0)
	top.Position = UDim2.fromOffset(x, y)
	local modeText, modeColor = Hud.ModeText(B)
	Hud.modeColor = modeColor
	if Hud.modeCard.SetColor then
		pcall(Hud.modeCard.SetColor, modeColor)
	end
	local mh = K.MODE_H
	Hud.modeCard.Root.Size = UDim2.fromOffset(w, mh)
	Hud.mode.Position = UDim2.fromOffset(14, 0)
	Hud.mode.Size = UDim2.fromOffset(w - 14 - 76, mh)
	Hud.mode.TextColor3 = COLORS.White
	Hud.timer.Position = UDim2.new(1, -78, 0, 0)
	Hud.timer.Size = UDim2.fromOffset(66, mh)
	local yy = mh + 6
	local compact = m.Compact
	Hud.boss.Visible = bossUnit ~= nil
	-- (a phone keeps the top card short: the boss's name goes into its bar, only the wave / ENRAGED pills stay)
	Hud.pills.Visible = not compact and (bossUnit ~= nil or B.Mode == "Dungeon")
	Hud.compactTop = compact
	local nameH = compact and 0 or 24
	if bossUnit then
		Hud.boss.Position = UDim2.fromOffset(0, yy)
		Hud.boss.Size = UDim2.fromOffset(w, nameH + 28)
		Hud.bossName.Visible = not compact
		Hud.bossName.Position = UDim2.fromOffset(4, 0)
		Hud.bossName.Size = UDim2.fromOffset(w - 8, 22)
		Hud.bossTrack.Position = UDim2.fromOffset(0, nameH)
		Hud.bossTrack.Size = UDim2.fromOffset(w, 26)
		Hud.bossFill.BackgroundColor3 = elementColor(bossUnit.element):Lerp(COLORS.Enemy, 0.5)
		setText(Hud.bossName, (bossUnit.kind == "MiniBoss" and (GLYPH.Crown .. " ") or "") .. bossUnit.name)
		setText(Hud.bossElement, tostring(bossUnit.element or "?"))
		Hud.bossElement.BackgroundColor3 = elementColor(bossUnit.element)
		yy = yy + nameH + 32
	end
	if Hud.pills.Visible then
		Hud.pills.Position = UDim2.fromOffset(0, yy)
		Hud.pills.Size = UDim2.fromOffset(w, 24)
		Hud.bossElement.Visible = bossUnit ~= nil and not compact
		yy = yy + 28
	end
	yy = Ring.LayoutInfo(B, w, yy)
	top.Size = UDim2.fromOffset(w, yy)
	if leftTop then
		local fcH = Hud.fighterCard.Root.Size.Y.Offset
		Hud.helperHolder.Position = UDim2.fromOffset(0, fcH + 8 + yy + 8)
	end
	if underList and y + yy > m.H * 0.3 - 4 then
		-- (a tall phone whose right column starts low: the top card first, the enemy list under it, both above
		-- the centre band)
		y = rightY
		top.Position = UDim2.fromOffset(x, y)
		Hud.enemies.Position = UDim2.fromOffset(m.W - K.EDGE, y + yy + 8)
	end
	Hud.topH = yy
	Hud.topRect = { x - anchor * w, y, x - anchor * w + w, y + yy }
end

-- the boss the top card shows: the raid boss, else a dungeon / wave mini-boss that is still up
function Hud.BossUnit(B)
	if B.boss then
		return B.boss
	end
	for _, u in ipairs(B.list) do
		if not u.ally and u.kind == "MiniBoss" and u.hp > 0 and u.state ~= S_DOWN then
			return u
		end
	end
	return nil
end

function Hud.Keys()
	for kind, A in pairs(Hud.buttons or {}) do
		local t = A.Key and A.Key:FindFirstChild("Text")
		if t then
			setText(t, Hud.KeyText(kind))
		end
	end
	for i, H in ipairs(Hud.helpers or {}) do
		local t = H.Key and H.Key:FindFirstChild("Text")
		if t then
			setText(t, Hud.KeyText("Buff", i))
		end
	end
end

-- seconds left of a cooldown (B.cd[kind], or the buff of helper slot), clamped >= 0
local function cdLeft(B, kind, slot, now)
	local cd = B.cd
	local readyAt = (kind == "Buff") and (cd.Buff[slot] or 0) or (cd[kind] or 0)
	return max(0, readyAt - now)
end

local function cdLen(B, kind, slot)
	local cd = B.cdLen
	if kind == "Buff" then
		return max(0.1, cd.Buff[slot] or 15)
	end
	return max(0.1, cd[kind] or 1)
end

-- per-frame HUD values: bars / texts only when they change, rings at 10 Hz
function Hud.Update(B, now, force)
	if not Hud.gui or not B then
		return
	end
	local last = Hud.last or {}
	Hud.last = last
	local modeText = Hud.ModeText(B)
	if last.mode ~= modeText then
		last.mode = modeText
		Hud.mode.Text = modeText
	end
	local left = B.TimeLimit > 0 and (B.TimeLimit - B.renderT) or 0
	local timerText = B.TimeLimit > 0 and fmtTime(left) or ""
	if last.timer ~= timerText then
		last.timer = timerText
		Hud.timer.Text = timerText
		Hud.timer.TextColor3 = (left < 15 and B.TimeLimit > 0) and COLORS.Enemy:Lerp(COLORS.White, 0.25) or COLORS.White
	end
	local bossUnit = Hud.boss.Visible and Hud.BossUnit(B) or nil
	if bossUnit then
		if force or last.bossHp ~= bossUnit.hp or last.bossMax ~= bossUnit.maxHp then
			last.bossHp, last.bossMax = bossUnit.hp, bossUnit.maxHp
			Hud.bossFill.Size = UDim2.fromScale(max(0.002, clamp(bossUnit.hp / bossUnit.maxHp, 0, 1)), 1)
			local fb = Hud.compactTop and 1000 or nil
			local numbers = Theme.ShortNumber(clamp(bossUnit.hp, 0, bossUnit.maxHp), fb) .. " / " .. Theme.ShortNumber(bossUnit.maxHp, fb)
			Hud.bossText.Text = Hud.compactTop and (bossUnit.name .. "  " .. Theme.ShortNumber(clamp(bossUnit.hp, 0, bossUnit.maxHp), fb)) or numbers
		end
	end
	if Hud.pills.Visible then
		if last.enraged ~= B.enraged then
			last.enraged = B.enraged
			Hud.enragePill.Visible = B.enraged == true
		end
		local minions, players = 0, {}
		for _, u in ipairs(B.list) do
			if u.kind == "Minion" and u.hp > 0 and u.state ~= S_DOWN then
				minions = minions + 1
			elseif u.side == 1 and u.owner ~= nil and u.kind ~= "Minion" then
				players[u.owner] = true
			end
		end
		local pc = 0
		for _ in pairs(players) do
			pc = pc + 1
		end
		if last.minions ~= minions then
			last.minions = minions
			Hud.minionPill.Visible = minions > 0 and not Hud.compactTop
			Hud.minionPill.Text = "Minions x" .. minions
		end
		local showPlayers = (B.Mode == "Raid" or (B.Mode == "Dungeon" and pc > 1)) and not Hud.compactTop
		if last.players ~= pc then
			last.players = pc
			Hud.playersPill.Visible = showPlayers and pc > 0
			Hud.playersPill.Text = pc == 1 and "1 player" or (pc .. " players")
		end
		local d = B.Dungeon
		local waveText = ""
		if d and num(d.Waves, 0) > 0 then
			waveText = "Wave " .. clamp(max(num(d.Wave, 1), B.wave or 0), 1, num(d.Waves, 1)) .. "/" .. num(d.Waves, 1)
		end
		if last.wave ~= waveText then
			last.wave = waveText
			Hud.wavePill.Visible = waveText ~= ""
			Hud.wavePill.Text = waveText
		end
	end
	if not B.Fighter then
		return
	end
	-- the fighter card ----------------------------------------------------------------------------------
	local F = Hud.F
	local f = B.fighterId and B.units[B.fighterId]
	if f and Hud.team.Visible then
		local hp = max(0, f.hp)
		local frac = clamp(hp / f.maxHp, 0, 1)
		if force or last.hp ~= hp or last.maxHp ~= f.maxHp or last.fid ~= f.id then
			local prev = (last.fid == f.id) and last.hpFrac or nil
			last.hp, last.maxHp, last.fid, last.hpFrac = hp, f.maxHp, f.id, frac
			F.HpFill.Size = UDim2.fromScale(max(frac, 0.001), 1)
			F.HpFill.Visible = frac > 0.002
			F.HpText.Text = Theme.ShortNumber(floor(hp + 0.5)) .. " / " .. Theme.ShortNumber(floor(f.maxHp + 0.5))
			Hud.hpWrites = (Hud.hpWrites or 0) + 1
			-- the red loss trail drains 0.4 s behind a loss; a heal moves it at once
			if Hud.lossTween then
				pcall(Hud.lossTween.Cancel, Hud.lossTween)
				Hud.lossTween = nil
			end
			if prev and frac < prev then
				Hud.lossFrom = prev
				local okT, tween = pcall(Util.Tween, F.HpLoss, K.LOSS_TIME, { Size = UDim2.fromScale(max(frac, 0.001), 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				Hud.lossTween = okT and tween or nil
				if not okT then
					F.HpLoss.Size = UDim2.fromScale(max(frac, 0.001), 1)
				end
			else
				F.HpLoss.Size = UDim2.fromScale(max(frac, 0.001), 1)
			end
		end
		local meter = clamp(floor(f.meter + 0.5), 0, METER_MAX)
		if force or last.meter ~= meter then
			last.meter = meter
			F.EnergyFill.Size = UDim2.fromScale(meter / METER_MAX, 1)
			F.EnergyFill.BackgroundColor3 = (meter >= METER_MAX) and COLORS.Gold or COLORS.Energy
			F.EnergyText.Text = (Hud.energyShort and "" or "ENERGY ") .. meter .. "/" .. METER_MAX
			F.EnergyText.TextColor3 = (meter >= METER_MAX) and COLORS.Gold or COLORS.EnergyText
		end
	end
	local lives = B.lives or 3
	if force or last.lives ~= lives then
		last.lives = lives
		for i, h in ipairs(F.Hearts) do
			h.TextColor3 = (i <= lives) and COLORS.Life or COLORS.LifeLost
			h.TextTransparency = (i <= lives) and 0 or 0.25
		end
	end
	if B.ended then
		return
	end
	-- rows of the enemy list: HP fills on change, the wind-up "!" while an enemy winds up -----------------
	if Hud.enemyDirty then
		Hud.enemyDirty = false
		local list = Hud.EnemyList(B)
		local key = tostring(B.lock or 0)
		for _, u in ipairs(list) do
			key = key .. "," .. u.id
		end
		if key ~= Hud.enemyKey and Hud.m then
			Hud.LayoutEnemies(B, Hud.m)
			Hud.FixText(Hud.enemies, Hud.m.F)
		end
	end
	for i, u in ipairs(Hud.enemyList or {}) do
		local row = Hud.rows[i]
		if row and row.Frame.Visible and row.unitId == u.id then
			setThin(row.Hp, clamp(u.hp / u.maxHp, 0, 1))
			setVisible(row.Alert, u.windupUntil ~= nil and now < u.windupUntil)
		end
	end
	-- 10 Hz: the rings, the countdowns, the helper states -------------------------------------------------
	if not force and now - (Hud.ringAt or 0) < K.RING_DT then
		return
	end
	Hud.ringAt = now
	Input.CheckPending(B, now)
	CheerUp.Update(B, now)
	for kind, A in pairs(Hud.buttons) do
		local frac, color, countText = 1, COLORS.Action[kind], ""
		if kind == "Element" or kind == "Dash" then
			local leftS = cdLeft(B, kind, nil, now)
			frac = 1 - leftS / cdLen(B, kind)
			if leftS > 0.05 then
				countText = tostring(math.ceil(leftS - 0.05))
			end
			if kind == "Element" and f then
				color = elementColor(f.element)
			end
		elseif kind == "Special" then
			frac = f and clamp(f.meter / METER_MAX, 0, 1) or 0
			color = frac >= 1 and COLORS.Gold or COLORS.Action.Special
		end
		setPie(A.Ring, frac, color)
		setText(A.Count, countText)
		setVisible(A.Count, countText ~= "")
		local ready = frac >= 1
		A.Glyph.TextTransparency = (countText ~= "") and 0.7 or 0
		local cue = (kind == "Dash" and B.cue == "Dash") or (kind == "Special" and ready and f ~= nil and f.special ~= nil)
		local glow = cue and (0.45 + 0.35 * (0.5 + 0.5 * sin(now * 8))) or 1
		if abs(A.Glow.BackgroundTransparency - glow) > 0.02 then
			A.Glow.BackgroundTransparency = glow
			A.Glow.BackgroundColor3 = (kind == "Dash") and COLORS.Dodge or COLORS.Gold
		end
		setDisabled(A.Button, kind == "Special" and not ready)
	end
	local swapLeft = cdLeft(B, "Swap", nil, now)
	for i, H in ipairs(Hud.helpers) do
		local u = H.unit
		if u and H.Cell.Visible then
			local down = u.hp <= 0 or u.state == S_DOWN
			local leftS = cdLeft(B, "Buff", u.slot, now)
			setPie(H.Ring, down and 0 or (1 - leftS / cdLen(B, "Buff", u.slot)), down and COLORS.Weak or elementColor(u.element))
			local countText = (not down and leftS > 0.05) and tostring(math.ceil(leftS - 0.05)) or ""
			setText(H.Count, countText)
			setVisible(H.Count, countText ~= "")
			local stateKey = (down and "d" or "a") .. ((swapLeft > 0.05) and "s" or "")
			if H.stateKey ~= stateKey then
				H.stateKey = stateKey
				setVisible(H.KO, down)
				H.View.ImageTransparency = down and 0.6 or 0
				H.View.ImageColor3 = down and Color3.fromRGB(120, 124, 140) or Color3.fromRGB(255, 255, 255)
				H.Buff.TextColor3 = down and COLORS.Weak or COLORS.White
				setDisabled(H.Swap, down or swapLeft > 0.05)
				H.Swap.BackgroundColor3 = (down or swapLeft > 0.05) and Color3.fromRGB(60, 66, 92) or Color3.fromRGB(40, 70, 150)
				H.Swap.TextTransparency = (down or swapLeft > 0.05) and 0.45 or 0
			end
			local hold = Input.HoldFrac(i, now)
			setVisible(H.SwapFill, hold > 0)
			if hold > 0 then
				H.SwapFill.Size = UDim2.fromScale(hold, 1)
			end
			if swapLeft > 0.05 and not down then
				setText(H.Swap, GLYPH.Swap .. " " .. math.ceil(swapLeft - 0.05))
			else
				setText(H.Swap, GLYPH.Swap .. " SWAP")
			end
		end
		H.index = i
	end
end

function Hud.ModeText(B)
	local text, color
	if B.Mode == "Raid" then
		text, color = "BOSS RAID", COLORS.Enemy
	elseif B.Mode == "Dungeon" then
		local d = B.Dungeon or {}
		local compact = Hud.m and Hud.m.Compact
		text, color = "DUNGEON - Floor " .. tostring(num(d.Floor, 1)) .. " - Room " .. tostring(num(d.Room, 1)), Theme.Neon.Purple or COLORS.Ally
		if compact then
			-- (a phone's line is short: the room + the wave; DungeonController's side card shows the floor)
			local waves = num(d.Waves, 0)
			if waves > 1 then
				text = "Room " .. tostring(num(d.Room, 1)) .. " - Wave " .. clamp(max(num(d.Wave, 1), B.wave or 0), 1, waves) .. "/" .. waves
			else
				text = "Floor " .. tostring(num(d.Floor, 1)) .. " - Room " .. tostring(num(d.Room, 1))
			end
		end
		if d.Boss == true and num(d.Room, 0) >= 3 then
			text = text .. " (BOSS)"
		end
	elseif B.Mode == "Ring" then
		text, color = Ring.TitleText(B), Ring.GOLD
	else
		text, color = "DUEL", COLORS.Ally
		if B.Fighter then
			text = "DUEL - vs " .. Hud.SideName(B, B.Side == 1 and 2 or 1)
		end
	end
	if B.Spectator then
		text = "WATCHING - " .. ((B.Mode == "Duel") and (Hud.SideName(B, 1) .. " vs " .. Hud.SideName(B, 2)) or text)
	end
	return text, color
end

function Hud.SideName(B, side)
	local names = {}
	for _, owner in ipairs((B.sides and B.sides[side]) or {}) do
		local n = B.Names[tostring(owner)]
		if n then
			names[#names + 1] = n
		end
	end
	if #names > 0 then
		return table.concat(names, ", ")
	end
	if B.Mode == "Ring" and side == 2 then
		return "The Champion"
	end
	return side == 1 and "Blue side" or "Red side"
end

function Hud.TitleText(B)
	return (Hud.ModeText(B))
end

-- a short "not yet" wiggle (rotation only, so the layout is never disturbed)
function Hud.Shake(obj)
	if not obj or not obj.Parent then
		return
	end
	Hud.shakes = (Hud.shakes or 0) + 1
	obj:SetAttribute("Shakes", (obj:GetAttribute("Shakes") or 0) + 1)
	pcall(function()
		obj.Rotation = 7
		Util.Tween(obj, 0.06, { Rotation = -7 })
		task.delay(0.06, function()
			Util.Tween(obj, 0.1, { Rotation = 0 })
		end)
	end)
end

-- the button of an action (shakes on a refusal)
function Hud.ButtonOf(action, slot)
	if action == "Cheer" then
		return Hud.cheer and Hud.cheer.Button or nil
	end
	if action == "Buff" or action == "Swap" then
		for _, H in ipairs(Hud.helpers or {}) do
			if H.unit and H.unit.slot == slot then
				return action == "Swap" and H.Swap or H.Face
			end
		end
		return nil
	end
	local A = Hud.buttons and Hud.buttons[action]
	return A and A.Button or nil
end

----------------------------------------------------------------------
-- the result card (bottom right; compact: top right; never centred)
----------------------------------------------------------------------
function Hud.ShowResult(B, payload)
	if not Hud.Ensure() then
		return
	end
	local m = Hud.Metrics()
	local res = Hud.result
	local body = res:FindFirstChild("Body") or res
	for _, c in ipairs(body:GetChildren()) do
		if c:GetAttribute("ResultPart") then
			c:Destroy()
		end
	end
	local outcome = payload.Outcome
	if outcome == nil then
		outcome = payload.Won and "Win" or "Loss"
	end
	local raid = B.Mode == "Raid"
	local titleText, color = "DEFEAT", COLORS.Enemy
	if outcome == "Win" then
		titleText, color = raid and "BOSS DEFEATED!" or "VICTORY!", COLORS.Gold
	elseif outcome == "Draw" then
		titleText, color = "DRAW", COLORS.Ally
	elseif outcome == "Left" then
		titleText, color = "YOU LEFT", COLORS.Weak
	elseif raid then
		titleText = "THE BOSS WON"
	end
	local reasons = {
		BossDown = "The boss is down!",
		Wipe = (outcome == "Win") and "Every enemy is knocked out." or "Your team was knocked out.",
		KO = (outcome == "Win") and "Every enemy is knocked out." or "Your team was knocked out.",
		Timeout = "Time is up.",
		Forfeit = (outcome == "Win") and "Your opponent gave up." or "You gave up.",
		Left = "You left the battle.",
		Abandoned = "Everyone left.",
		Ended = "The raid has ended.",
		Error = "The battle was cancelled. No rewards were lost.",
		Void = "Both players left: this duel does not count.",
		Shutdown = raid and "The server is restarting: your damage so far still counts." or "The server is restarting: this battle does not count.",
		Cleared = "Room cleared!",
	}
	local sub = reasons[tostring(payload.Reason)] or ""
	if B.Mode == "Ring" then
		titleText, color, sub = Ring.ResultTitle(B, payload, sub)
	elseif B.Mode == "Dungeon" and outcome ~= "Win" then
		titleText, color = "KNOCKED OUT", Theme.Neon.Purple or COLORS.Enemy
	end
	local card = Hud.resultCard
	if card and card.SetColor then
		pcall(card.SetColor, color)
	end
	local w = m.Compact and min(K.RESULT_W, m.W - 16) or K.RESULT_W
	if m.Compact and m.Landscape then
		w = max(300, min(w, floor(m.W * 0.36)))
	end
	local y = K.PAD + 4
	local function part(inst)
		inst:SetAttribute("ResultPart", true)
		return inst
	end
	local short = m.Compact and m.Landscape
	-- (a short landscape screen: the OK button shares the title's line, long titles step down a size)
	local titleW = w - 2 * K.PAD - 8 - (short and 100 or 0)
	local titleSize = short and (#titleText > 9 and 25 or 30) or 34
	local title = part(label(body, titleText, "Title", titleSize, { Name = "Title", Position = UDim2.fromOffset(K.PAD + 4, y), Size = UDim2.fromOffset(titleW, 40), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = color, TextTruncate = Enum.TextTruncate.AtEnd }))
	title.TextStrokeColor3 = COLORS.Ink
	y = y + 42
	local plain = { Wipe = true, KO = true, Cleared = true, BossDown = true }
	local floorLine = false
	if short and plain[tostring(payload.Reason)] then
		sub = "" -- (the title says it; a short screen keeps the card clear of the buttons under it)
		if B.Mode == "Dungeon" then
			local ex, dg = type(payload.Rewards) == "table" and type(payload.Rewards.Extra) == "table" and payload.Rewards.Extra or {}, B.Dungeon or {}
			sub = "Floor " .. tostring(num(ex.Floor, num(dg.Floor, 1))) .. " - Room " .. tostring(num(ex.Room, num(dg.Room, 1)))
			floorLine = true -- (a full-width line instead of a truncated pill)
		end
	elseif short and B.Mode == "Ring" then
		sub = (sub:gsub("^Champion Ring: (%l)", string.upper)) -- "You left after round 8": one line
	end
	if sub ~= "" then
		part(label(body, sub, "Body", 18, { Name = "Reason", Position = UDim2.fromOffset(K.PAD + 4, y), Size = UDim2.fromOffset(w - 2 * K.PAD - 8, 24), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, TextColor3 = COLORS.Muted }))
		y = y + 28
	end
	local list = part(make("Frame", { Name = "Rewards", BackgroundTransparency = 1, Position = UDim2.fromOffset(K.PAD, y), Size = UDim2.fromOffset(w - 2 * K.PAD, 10) }, body))
	local cols = 2
	local cellW = floor((w - 2 * K.PAD - 8) / cols)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(cellW, 30), CellPadding = UDim2.fromOffset(8, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local rw = type(payload.Rewards) == "table" and payload.Rewards or {}
	local lines = (B.Mode == "Ring") and Ring.ResultLines(B, rw) or Hud.RewardLines(B, rw)
	-- Phase 5: the lives left, the dungeon's lines
	if B.Fighter and B.Mode ~= "Ring" then
		local lives = B.lives or 0
		lines[#lines + 1] = { "Lives left: " .. lives, lives > 0 and COLORS.Life or COLORS.Weak }
	end
	if B.Mode == "Dungeon" then
		-- End.Rewards.Extra first, Start.Dungeon for what it leaves out
		local extra = type(rw.Extra) == "table" and rw.Extra or {}
		local dg = B.Dungeon or {}
		if not floorLine then
			lines[#lines + 1] = { "Floor " .. tostring(num(extra.Floor, num(dg.Floor, 1))) .. " - Room " .. tostring(num(extra.Room, num(dg.Room, 1))), Theme.Neon.Purple or COLORS.Ally }
		end
		local name = extra.Name or dg.Name
		if name then
			lines[#lines + 1] = { tostring(name), Theme.Neon.Purple or COLORS.Ally }
		end
	end
	for i, line in ipairs(lines) do
		local p = smallPill(list, line[1], line[2], { LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.fromScale(1, 1) })
		p.TextSize = short and 14 or 16
		p.TextTruncate = Enum.TextTruncate.AtEnd
	end
	local rowsN = math.ceil(#lines / cols)
	list.Size = UDim2.fromOffset(w - 2 * K.PAD, max(0, rowsN * 36 - 6))
	y = y + rowsN * 36 + (rowsN > 0 and 4 or 0)
	local function okButton(size)
		local b
		if Mods.NeonKit and type(Mods.NeonKit.Button) == "function" then
			local okB, nb = pcall(Mods.NeonKit.Button, { Name = "OkButton", Text = "OK", Color = "Green", Size = size, TextSize = 22, Parent = body, Callback = function()
				Hud.HideResult()
			end })
			b = okB and nb or nil
		end
		if not b then
			b = make("TextButton", { Name = "OkButton", Text = "OK", Size = size, BackgroundColor3 = Theme.Buttons.Green, AutoButtonColor = true }, body)
			Theme.Style(b, "Button", { Size = 22 })
			Theme.Corner(b, UDim.new(0, 12))
			b.Activated:Connect(function()
				Hud.HideResult()
			end)
		end
		return part(b)
	end
	if short then
		local ok = okButton(UDim2.fromOffset(88, 44))
		ok.Position = UDim2.new(1, -K.PAD - 88, 0, K.PAD)
		Hud.resultTimer = thinBar(body, "Timer", 6, COLORS.Muted, { Position = UDim2.fromOffset(K.PAD + 4, y), Size = UDim2.fromOffset(w - 2 * K.PAD - 8, 6) })
		part(Hud.resultTimer.Root)
		y = y + 6 + K.PAD
	else
		local ok = okButton(UDim2.fromOffset(120, 46))
		ok.Position = UDim2.new(1, -K.PAD - 120, 0, y)
		Hud.resultTimer = thinBar(body, "Timer", 8, COLORS.Muted, { Position = UDim2.fromOffset(K.PAD + 4, y + 19), Size = UDim2.fromOffset(w - 2 * K.PAD - 140, 8) })
		part(Hud.resultTimer.Root)
		y = y + 46 + K.PAD
	end
	res.Size = UDim2.fromOffset(w, y)
	if m.Compact then
		-- a phone: top right, under the enemy list's place, never over the screen centre
		local curBottom = Hud.CurrencyTop(m)
		res.AnchorPoint = Vector2.new(1, 0)
		res.Position = UDim2.new(1, -8, 0, max(6, curBottom > 0 and (curBottom + 6) or 6))
	else
		res.AnchorPoint = Vector2.new(1, 1)
		res.Position = UDim2.new(1, -K.EDGE, 1, -K.EDGE)
	end
	res.Visible = true
	Hud.FixText(res, m.F)
	Ring.HideNext()
	Hud.top.Visible = false
	Hud.team.Visible = false
	Hud.cmd.Visible = false
	Hud.enemies.Visible = false
	Hud.teamPlace = nil
	Hud.SetMenuHidden(false)
	Leave.Place(m, nil, false)
	CheerUp.Place(m, nil, false)
	local keep = St.result and St.result.payload == payload and St.result.t0 -- a relayout (rotation) keeps the timer
	St.result = { t0 = keep or os.clock(), dur = K.RESULT_SECONDS, battle = B, payload = payload }
	Me.MouseHold("BattleResult", true) -- the cursor is free for the card's OK
	BattleController._wake()
end

function Hud.RewardLines(B, rw)
	local lines = {}
	local tokens = num(rw.Tokens, 0)
	if tokens > 0 then
		lines[#lines + 1] = { "+" .. Theme.ShortNumber(tokens) .. " Tokens", Theme.Currency.Tokens.Color }
	end
	local gems = num(rw.Gems, 0)
	if gems > 0 then
		lines[#lines + 1] = { "+" .. Theme.ShortNumber(gems) .. " Gems", Theme.Currency.Gems.Color }
	end
	local cash = num(rw.Cash, 0)
	if cash > 0 then
		lines[#lines + 1] = { "+$" .. Theme.ShortNumber(cash) .. " Cash", Theme.Currency.Cash and Theme.Currency.Cash.Color or COLORS.Mine }
	end
	if rw.Practice == true then
		lines[#lines + 1] = { "Practice duel: no rewards", COLORS.Weak }
	end
	local trophies = num(rw.Trophies, 0)
	if trophies ~= 0 or (B.Mode == "Duel" and rw.Practice ~= true and rw.Void ~= true) then
		lines[#lines + 1] = { (trophies >= 0 and "+" or "") .. tostring(trophies) .. " Trophies", trophies >= 0 and COLORS.Gold or COLORS.Enemy }
	end
	local xp = num(rw.Xp, 0)
	if xp > 0 then
		lines[#lines + 1] = { "+" .. Theme.ShortNumber(xp) .. " Pet XP", COLORS.Ally }
	end
	if rw.FirstClear == true then
		lines[#lines + 1] = { "First clear!", COLORS.Mine }
	end
	if rw.Tier == "None" then
		lines[#lines + 1] = { "No hits on the boss: no reward", COLORS.Weak }
	elseif rw.Tier then
		local share = num(rw.Share, 0)
		lines[#lines + 1] = { tostring(rw.Tier) .. " tier", COLORS.Gold }
		lines[#lines + 1] = { tostring(floor(share * 100 + 0.5)) .. "% of the damage", Color3.fromRGB(150, 110, 220) }
	end
	if rw.EventPet then
		local name = tostring(rw.EventPet)
		if PetCatalog and PetCatalog.Get then
			local ok, d = pcall(PetCatalog.Get, rw.EventPet)
			if ok and type(d) == "table" and d.Name then
				name = d.Name
			end
		end
		lines[#lines + 1] = { "New pet: " .. name, Color3.fromRGB(236, 110, 170) }
	end
	local ups = num(rw.LevelUps, 0)
	if ups > 0 then
		lines[#lines + 1] = { ups == 1 and "1 level up!" or (ups .. " level ups!"), COLORS.Mine }
	end
	if rw.Double == true then
		lines[#lines + 1] = { "Double rewards", COLORS.Gold }
	end
	return lines
end

function Hud.HideResult()
	St.result = nil
	Me.MouseHold("BattleResult", false)
	if Hud.result then
		Hud.result.Visible = false
	end
	if not St.battle then
		Hud.SetVisible(false)
	end
end

function Hud.UpdateResult(now)
	local r = St.result
	if not r then
		return
	end
	local p = (now - r.t0) / r.dur
	if p >= 1 then
		Hud.HideResult()
		return
	end
	if Hud.resultTimer then
		setThin(Hud.resultTimer, 1 - p)
	end
end

function Hud.SetVisible(on)
	if not Hud.gui then
		return
	end
	if not on then
		Hud.top.Visible = false
		Hud.team.Visible = false
		Hud.cmd.Visible = false
		Hud.enemies.Visible = false
		Hud.teamPlace = nil
		Hud.SetMenuHidden(false)
		if Hud.leave then
			Hud.leave.Visible = false
		end
		CheerUp.Place(Hud.m or {}, nil, false)
	end
end

-- the menu column (MenuController) steps aside while the battle HUD holds the left edge
function Hud.SetMenuHidden(on)
	on = on == true
	if (Hud.menuHidden == true) == on then
		return
	end
	local module = script.Parent:FindFirstChild("MenuController")
	local ok, menu = pcall(function()
		return module and require(module)
	end)
	if ok and type(menu) == "table" and type(menu.SetColumnHidden) == "function" and pcall(menu.SetColumnHidden, on) then
		Hud.menuHidden = on
	elseif not on then
		Hud.menuHidden = false
	end
end

-- MovementController (the battle dash keys, free dash, battle speed); nil when missing
function Hud.Movement()
	if Mods.Movement == nil then
		Mods.Movement = optional(script.Parent, "MovementController") or false
	end
	return Mods.Movement or nil
end

----------------------------------------------------------------------
-- LEAVE: stops a Champion Ring run (BattleCommand "Forfeit"; the server ends the run cleanly and the climber comes
-- back at the portal). Never in duels (a forfeit costs trophies), raids or the dungeon (DungeonController's LEAVE).
-- Two presses: the first turns it into "Sure? Tap again" for LEAVE_CONFIRM seconds, the second sends it. One button
-- beside the action cluster and one on the ring's next-round card; both share the confirm state.
----------------------------------------------------------------------
Leave.armedUntil = 0
Leave.sentUntil = 0
Leave.buttons = {}

function Leave.Allowed(B)
	return B ~= nil and B.Fighter == true and B.Mode == "Ring"
end

function Leave.Make(parent, textSize)
	local b = make("TextButton", { Name = "LeaveButton", Text = "LEAVE", AutoButtonColor = true, BackgroundColor3 = Theme.Buttons.Pink, BorderSizePixel = 0, Size = UDim2.fromOffset(K.LEAVE_W, K.LEAVE_H), Visible = false, ZIndex = 4 }, parent)
	Theme.Style(b, "Button", { Size = textSize, Stroke = 0.2, Outline = 2 })
	Theme.Corner(b, UDim.new(0, 12))
	Theme.Stroke(b, Theme.Colors.PanelInk or COLORS.Navy, 3, 0)
	b.TextWrapped = true
	b:SetAttribute("BaseText", textSize)
	b:SetAttribute("LeaveStyle", "Pink")
	b.Activated:Connect(function()
		Leave.Press()
	end)
	Leave.buttons[#Leave.buttons + 1] = b
	return b
end

function Leave.State(now)
	if now < Leave.sentUntil then
		return "Leaving...", "Gray"
	elseif now < Leave.armedUntil then
		return "Sure? Tap again", "Red"
	end
	return "LEAVE", "Pink"
end

function Leave.Paint()
	local text, style = Leave.State(os.clock())
	Me.MouseHold("BattleLeave", style ~= "Pink") -- "Sure? Tap again": the cursor is free for the second press
	local live = {}
	for _, b in ipairs(Leave.buttons) do
		if b.Parent then
			live[#live + 1] = b
			setText(b, text)
			if b:GetAttribute("LeaveStyle") ~= style then
				b:SetAttribute("LeaveStyle", style)
				b.BackgroundColor3 = Theme.Buttons[style] or COLORS.Ally
			end
		end
	end
	Leave.buttons = live
end

function Leave.Press()
	local now = os.clock()
	if now < Leave.sentUntil or not Leave.Allowed(St.battle) then
		return
	end
	if now < Leave.armedUntil then
		Leave.armedUntil = 0
		if BattleController.Command("Forfeit") then
			Leave.sentUntil = now + K.LEAVE_CONFIRM -- the run's End normally closes the HUD long before this
		end
	else
		Leave.armedUntil = now + K.LEAVE_CONFIRM
	end
	Leave.Paint()
	task.delay(K.LEAVE_CONFIRM + 0.05, Leave.Paint) -- back to LEAVE when nobody pressed again
end

-- a new battle (a ring round too) and the step from a fight to the next-round card start unarmed
function Leave.Track(B)
	local phase = B and B.ended and "next" or "fight"
	if Leave.battle ~= B or Leave.phase ~= phase then
		Leave.battle = B
		Leave.phase = phase
		Leave.armedUntil = 0
		Leave.sentUntil = 0
		Leave.Paint()
	end
end

-- the fight's LEAVE: wide = left of the action cluster at the bottom; compact = above the cluster, right edge
function Leave.Place(m, B, isFighting)
	local b = Hud.leave
	if not b then
		return
	end
	if B then
		Leave.Track(B)
	end
	b.Visible = B ~= nil and isFighting == true and Leave.Allowed(B)
	if not b.Visible then
		return
	end
	b.AnchorPoint = Vector2.new(1, 1)
	if not m.Compact then
		b.Size = UDim2.fromOffset(K.LEAVE_W, K.LEAVE_H)
		b.Position = UDim2.fromOffset(m.W - K.EDGE - 300, m.H - K.EDGE - 8)
	elseif m.Landscape and Hud.topRect and Hud.top.Visible and Hud.topRect[3] + 8 + K.LEAVE_W_TOP <= m.W - K.EDGE - K.ROW_W_COMPACT - 8 then
		-- a landscape phone: right of the mode card in the top strip (the cluster needs the right edge)
		b.AnchorPoint = Vector2.new(0, 0)
		b.Size = UDim2.fromOffset(K.LEAVE_W_TOP, K.MODE_H)
		b.Position = UDim2.fromOffset(Hud.topRect[3] + 8, Hud.topRect[2])
	else
		-- above the cluster's top row, at the right edge
		local L = Hud.ClusterLayout(m)
		local topY = 0
		for _, kind in ipairs(ACTIONS) do
			local s = L[kind]
			topY = min(topY, s[2] - s[3] / 2)
		end
		b.Size = UDim2.fromOffset(K.LEAVE_W_COMPACT, K.LEAVE_H_COMPACT)
		b.Position = UDim2.fromOffset(m.W - 8, m.H + topY - 10)
	end
	b.TextSize = 20
	Leave.Paint()
end

-- the next-round card's LEAVE: a row at the bottom of the card (returns the card's new height)
function Leave.PlaceOnCard(m, B, w, y, inline)
	local b = Hud.nextLeave
	if not b then
		return y
	end
	Leave.Track(B)
	b.Visible = Leave.Allowed(B)
	if not b.Visible then
		return y
	end
	Leave.Paint()
	if inline then
		-- beside the countdown (a landscape phone)
		b.Size = UDim2.fromOffset(92, 38)
		b.AnchorPoint = Vector2.new(1, 0)
		b.Position = UDim2.new(1, -K.PAD - 4, 0, y)
		return y
	end
	b.Size = UDim2.fromOffset(min(w - 2 * K.PAD - 8, K.LEAVE_CARD_W), K.LEAVE_H_COMPACT)
	b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, -K.PAD - 4, 0, y)
	return y + K.LEAVE_H_COMPACT + K.PAD
end

----------------------------------------------------------------------
-- wave 6: CHEER UP! (Raid / Dungeon fighters): BattleCommand "Cheer"; the server gives my fighter x (1 + CheerBoost) for
-- CheerSeconds, cooldown CheerCooldown (BattleCatalog.Fighter; the server decides). The button sits right above the
-- vitals card (HudController.GetLayout().Vitals: CHEER_GAP_PX above it, centred on it), so it never shares a row with
-- the hotbar, the touch buttons or the action cluster. The gold glow behind it shows the boost, a dark veil that shrinks
-- to the right the cooldown. The trainer's cheer emote is Cheer.Mine (TrainerCheer) on the server's Cheer event.
----------------------------------------------------------------------
function CheerUp.Allowed(B)
	return B ~= nil and B.Fighter == true and not B.ended and (B.Mode == "Raid" or B.Mode == "Dungeon")
end

-- HudController (the vitals card's rect); nil when missing
function CheerUp.Layout()
	if Mods.HudCtl == nil then
		Mods.HudCtl = optional(script.Parent, "HudController") or false
	end
	local hc = Mods.HudCtl
	if not hc or type(hc.GetLayout) ~= "function" then
		return nil
	end
	local ok, layout = pcall(hc.GetLayout)
	local v = ok and type(layout) == "table" and layout.Vitals or nil
	if type(v) == "table" and tonumber(v.X) and tonumber(v.Y) and tonumber(v.W) and tonumber(v.H) then
		return v
	end
	return nil
end

function CheerUp.Make(parent)
	local glow = make("Frame", { Name = "CheerGlow", BackgroundColor3 = COLORS.Gold, BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 3 }, parent)
	Theme.Corner(glow, UDim.new(0, 18))
	local b = make("TextButton", { Name = "Cheer", Text = "Cheer up!", AutoButtonColor = true, BackgroundColor3 = Theme.Buttons.Gold, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(K.CHEER_W, K.CHEER_H), Visible = false, ZIndex = 4 }, parent)
	Theme.Style(b, "Button", { Size = 20, Stroke = 0.2, Outline = 2 })
	Theme.Corner(b, UDim.new(0, 12))
	Theme.Stroke(b, Theme.Colors.PanelInk or COLORS.Navy, 3, 0)
	b:SetAttribute("BaseText", 20)
	local sweep = make("Frame", { Name = "Sweep", BackgroundColor3 = COLORS.Navy, BackgroundTransparency = 0.35, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0, 1), Visible = false, ZIndex = 5 }, b)
	Theme.Corner(sweep, UDim.new(0, 12))
	b.Activated:Connect(function()
		BattleController.Cheer()
	end)
	Hud.cheer = { Button = b, Glow = glow, Sweep = sweep }
	return b
end

function CheerUp.Place(m, B, isFighting)
	local C = Hud.cheer
	if not C then
		return
	end
	local on = B ~= nil and isFighting == true and CheerUp.Allowed(B)
	C.Button.Visible = on
	C.Glow.Visible = on
	if not on then
		CheerUp.placed = nil
		return
	end
	local f = max(0.05, m.F)
	local w, h = K.CHEER_W, K.CHEER_H
	if m.Touch then
		w = max(w, K.CHEER_TOUCH_W_PX / f)
		h = max(h, K.CHEER_TOUCH_PX / f)
	end
	local v = CheerUp.Layout()
	local cx, bottom
	if v then
		cx = (v.X + v.W / 2) / f
		bottom = (v.Y - K.CHEER_GAP_PX) / f
	else
		cx, bottom = m.W / 2, m.H - 150 -- (no vitals card: low in the middle)
	end
	-- the middle of the screen stays free (HudController's CENTRE_TOL band): a landscape phone's card sits so high that the
	-- spot above it is in that band; the button then goes beside the card in its row, on the left (between Roblox's stick
	-- and the card: the right is the action cluster's), its top level with the card's top
	local tol = K.CHEER_CENTRE_TOL
	local bandL, bandR = m.W * (0.5 - tol), m.W * (0.5 + tol)
	local midY = (m.VY / 2 - m.Inset) / f
	local bandT, bandB = midY - m.VY * tol / f, midY + m.VY * tol / f
	if cx + w / 2 > bandL and cx - w / 2 < bandR and bottom > bandT and bottom - h < bandB then
		if v then
			cx = (v.X - K.CHEER_GAP_PX) / f - w / 2
			bottom = v.Y / f + h
		else
			cx = bandL - 4 - w / 2
		end
	end
	cx = clamp(cx, w / 2 + K.EDGE, m.W - w / 2 - K.EDGE)
	C.Button.Size = UDim2.fromOffset(w, h)
	C.Button.Position = UDim2.fromOffset(cx, bottom)
	C.Glow.Size = UDim2.fromOffset(w + 16, h + 16)
	C.Glow.Position = UDim2.fromOffset(cx, bottom - h / 2)
	CheerUp.placed = v and string.format("%d,%d,%d,%d", v.X, v.Y, v.W, v.H) or "-"
end

-- 10 Hz: the sweep, the glow; a vitals card that moved takes the button with it
function CheerUp.Update(B, now)
	local C = Hud.cheer
	if not C or not C.Button.Visible then
		return
	end
	local v = CheerUp.Layout()
	local key = v and string.format("%d,%d,%d,%d", v.X, v.Y, v.W, v.H) or "-"
	if key ~= CheerUp.placed and Hud.m then
		CheerUp.Place(Hud.m, B, B.Fighter and not B.ended)
	end
	local left = cdLeft(B, "Cheer", nil, now)
	setVisible(C.Sweep, left > 0.05)
	if left > 0.05 then
		C.Sweep.Size = UDim2.fromScale(clamp(left / cdLen(B, "Cheer"), 0, 1), 1)
	end
	local cheering = now < (B.cheerUntil or 0)
	local glow = cheering and (0.35 + 0.3 * (0.5 + 0.5 * sin(now * 6))) or 1
	if abs(C.Glow.BackgroundTransparency - glow) > 0.02 then
		C.Glow.BackgroundTransparency = glow
	end
	if C.Button:GetAttribute("Cheering") ~= cheering then
		C.Button:SetAttribute("Cheering", cheering)
	end
end

----------------------------------------------------------------------
-- Phase 4: unit cards (src/client/UI/PetCard.lua; ARCHITECTURE_V3.md "Phase 4 build contract" 3.9)
----------------------------------------------------------------------
-- the card above every pet unit: own pets "Unit" (level + HP + SPECIAL + XP), a teammate's "Ally" (level + HP),
-- enemies / NPCs "Enemy" (level + HP in red). The billboard keeps the Phase 3 name HpBar (its HP fill is
-- Plate.Hp.Fill). Fills are written only when the snapshot changed a value (Cards.Live), never per frame.
function Cards.ModeOf(u)
	if u.mine then
		return "Unit"
	elseif u.ally then
		return "Ally"
	end
	return "Enemy"
end

function Cards.Add(B, u, root)
	local h = (u.height or 3) / 2 + 0.9
	local ok, c = false, nil
	if Mods.PetCard and type(Mods.PetCard.New) == "function" then
		ok, c = pcall(Mods.PetCard.New, root, Cards.ModeOf(u), h, { Parent = u.model, Name = "HpBar" })
	end
	if not ok or type(c) ~= "table" then
		if Mods.PetCard then
			warnOnce("card", "PetCard.New failed: " .. tostring(c))
		end
		addBar(u, root, h) -- the Phase 3 bar (a build without PetCard)
		return
	end
	u.card = c
	u.cardWrites = 0
	u.cardHp, u.cardMeter, u.cardLives = nil, nil, -1
	Cards.Static(u)
	Cards.Live(u)
	if u.crowned then
		pcall(Ring.Tag, B, u, root, h)
	end
end

function Cards.Free(u)
	if u.card then
		pcall(u.card.Destroy, u.card)
		u.card = nil
	end
end

-- the XP curve (TycoonCatalog.XpToNext; nil past the cap) and the pet's cap (PetCatalog: 100 for every rarity)
function Cards.Need(level)
	local TC = Mods.Tycoon
	if TC and type(TC.XpToNext) == "function" then
		local ok, need = pcall(TC.XpToNext, level)
		need = ok and tonumber(need) or nil
		if need and need > 0 and need < math.huge then
			return need
		end
	end
	return nil
end

function Cards.Cap(u)
	if PetCatalog then
		if type(PetCatalog.LevelCap) == "function" then
			local ok, cap = pcall(PetCatalog.LevelCap, u.info and u.info.petId)
			if ok and tonumber(cap) then
				return tonumber(cap)
			end
		end
		if type(PetCatalog.MaxPetLevel) == "function" then
			local ok, cap = pcall(PetCatalog.MaxPetLevel)
			if ok and tonumber(cap) then
				return tonumber(cap)
			end
		end
		if tonumber(PetCatalog.MaxLevel) then
			return tonumber(PetCatalog.MaxLevel)
		end
	end
	return math.huge
end

-- XP bar: xp / xpNext; the server leaves xpNext out at the cap (a full bar); 0 when the XP is unknown
function Cards.XpFrac(u)
	if u.xp == nil then
		return 0
	end
	local need = u.xpNext
	if need == nil or need ~= need or need >= math.huge then
		return 1
	end
	return clamp(u.xp / max(1, need), 0, 1)
end

-- level, stars and XP (on Start, after the rewards, on a State change)
function Cards.Static(u)
	local c = u.card
	if not c then
		return
	end
	c:SetLevel(u.level, u.evo, false)
	if u.mine then
		c:SetXp(Cards.XpFrac(u))
	end
end

-- HP and SPECIAL from the latest snapshot values (called only when one of them changed)
function Cards.Live(u)
	local c = u.card
	if not c then
		return
	end
	if u.cardHp ~= u.hp then
		u.cardHp = u.hp
		c:SetHp(clamp(u.hp / u.maxHp, 0, 1))
		u.cardWrites = (u.cardWrites or 0) + 1
	end
	if u.cardMeter ~= u.meter then
		u.cardMeter = u.meter
		if u.mine then
			local frac = clamp(u.meter / METER_MAX, 0, 1)
			c:SetSpecial(frac, frac >= 1 and u.special ~= nil)
			u.cardWrites = (u.cardWrites or 0) + 1
		end
	end
	-- Phase 5: a player fighter's lives as pips (PetCard:SetLives); NPC units have none
	if u.cardLives ~= u.lives then
		u.cardLives = u.lives
		local player = u.owner ~= nil and St.battle ~= nil and St.battle.Names[tostring(u.owner)] ~= nil
		if type(c.SetLives) == "function" and player and not u.benched then
			pcall(c.SetLives, c, u.lives, max(3, u.lives or 0))
		elseif type(c.SetLives) == "function" then
			pcall(c.SetLives, c, nil)
		end
	end
end

-- a raid spectator who joins the fight: the card switches its mode with the side
function Cards.Restyle(u)
	if u.card then
		u.card:SetMode(Cards.ModeOf(u))
		u.cardHp, u.cardMeter = nil, nil
		Cards.Static(u)
		Cards.Live(u)
	end
end

-- display only: the fight's XP (End.Rewards.Xp per team pet) moves my cards' XP bars (levels roll over on the curve);
-- the next Start / the profile mirror bring the server's numbers
function Cards.AddXp(u, xp)
	if u.xp == nil or xp <= 0 then
		return
	end
	u.xp = u.xp + xp
	local cap, guard = Cards.Cap(u), 0
	while u.xpNext and u.xpNext < math.huge and u.xp >= u.xpNext and guard < 200 do
		u.xp = u.xp - u.xpNext
		u.level = u.level + 1
		guard = guard + 1
		u.xpNext = (u.level < cap) and Cards.Need(u.level) or nil
	end
	Cards.Static(u)
end

function Cards.AfterFight(B, payload)
	local rw = type(payload) == "table" and type(payload.Rewards) == "table" and payload.Rewards or nil
	local xp = rw and num(rw.Xp, 0) or 0
	if xp <= 0 or not B.Fighter or payload.Spectator == true then
		return
	end
	for _, u in pairs(B.mine) do
		Cards.AddXp(u, xp)
	end
end

-- the profile mirror (State.PetLevel) only ever moves a card forward (a stale mirror never undoes the rewards)
function Cards.FromState(B)
	local S = Mods.State
	if not B or not B.Fighter or not S or type(S.PetLevel) ~= "function" then
		return
	end
	if type(S.IsLoaded) == "function" and not S.IsLoaded() then
		return
	end
	for _, u in pairs(B.mine) do
		local key = u.info and u.info.key
		if type(key) == "string" and u.xp ~= nil then
			local ok, lv, xp = pcall(S.PetLevel, key)
			lv, xp = ok and tonumber(lv) or nil, ok and tonumber(xp) or nil
			if lv and xp and (lv > u.level or (lv == u.level and xp > u.xp)) then
				u.level, u.xp = lv, xp
				u.xpNext = (lv < Cards.Cap(u)) and Cards.Need(lv) or nil
				Cards.Static(u)
			end
		end
	end
end

----------------------------------------------------------------------
-- Phase 4: the Champion Ring HUD (contract 3.8)
----------------------------------------------------------------------
Ring.GOLD = Color3.fromRGB(250, 190, 56) -- the ring's champion gold (ArenaBuilder's Ring.Color)
Ring.VIOLET = Color3.fromRGB(156, 96, 238)
Ring.INTERMISSION = tonumber(BattleCatalog and type(BattleCatalog.Ring) == "table" and BattleCatalog.Ring.Intermission) or 3
Ring.LINGER = 15 -- seconds a won round's floor waits for the next Start (BattleService sends it after INTERMISSION)

function Ring.IsFinal(payload)
	return type(payload) == "table" and type(payload.Rewards) == "table" and payload.Rewards.Final == true
end

-- a won round that the next one follows: End.Rewards.Next (never the run's final End)
function Ring.IsNext(B, payload)
	local rw = type(payload.Rewards) == "table" and payload.Rewards or nil
	return B.Mode == "Ring" and rw ~= nil and rw.Next ~= nil and rw.Final ~= true
		and (payload.Won == true or payload.Outcome == "Win" or rw.Won == true)
end

function Ring.Money(n)
	return "$" .. Theme.ShortNumber(num(n, 0))
end

function Ring.TitleText(B)
	local round = B.Round > 0 and B.Round or 1
	local best = B.Ring and num(B.Ring.Best, 0) or 0
	if Hud.m and Hud.m.Compact then
		-- (a phone's mode line is short: the gold card says it is the ring)
		return best > 0 and ("Round " .. round .. " - Best " .. best) or ("Ring - Round " .. round)
	end
	if best > 0 then
		return "CHAMPION RING - Round " .. round .. " - Best " .. best
	end
	return "CHAMPION RING - Round " .. round
end

-- the champion is built wearing PetBuilder's voxel crown accessory (a copy of its definition, cached by look)
function Ring.Crowned(def)
	if type(def) ~= "table" or type(def.Look) ~= "table" then
		return def
	end
	local copy = {}
	for k, v in pairs(def) do
		copy[k] = v
	end
	local look = {}
	for k, v in pairs(def.Look) do
		look[k] = v
	end
	look.Accessory = "Crown"
	copy.Look = look
	return copy
end

-- the champion's name tag: a pixel billboard above its card (same anchor; the tag sits at the top of a taller,
-- transparent frame, so it keeps a fixed pixel gap above the card at any distance)
function Ring.Tag(B, u, root, h)
	local champ = B.Ring and type(B.Ring.Champion) == "table" and B.Ring.Champion or {}
	local name = tostring(champ.Name or u.name or "Champion")
	if not string.find(name, "^Champion") then
		name = "Champion " .. name
	end
	local px = Theme.ScaledSize(22, 16)
	local th = Theme.ScaledSize(32, 24)
	local gap = Theme.ScaledSize(8, 5)
	local cardH = (u.card and u.card.Gui and u.card.Gui.Size.Y.Offset) or th
	local w = floor(min(Theme.ScaledSize(300, 220), textWidth(name, px) + Theme.ScaledSize(30, 22)))
	local gui = make("BillboardGui", {
		Name = "ChampionTag",
		Adornee = root,
		Size = UDim2.fromOffset(w, cardH + 2 * (th + gap)),
		StudsOffset = Vector3.new(0, h, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = K.BAR_DISTANCE,
		ResetOnSpawn = false,
	})
	local plate = make("Frame", { Name = "Plate", BackgroundColor3 = COLORS.Navy, BackgroundTransparency = 0.08, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, th) }, gui)
	Theme.Corner(plate, UDim.new(0, 9))
	Theme.Stroke(plate, Ring.GOLD, 2, 0)
	local l = label(plate, name, "Heading", px, { Name = "Name", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Ring.GOLD })
	l.TextStrokeColor3 = COLORS.Ink
	gui.Parent = u.model
	u.tag = gui
end

-- "Win: +$X +Y XP" (BattleCatalog.RingRewards with the plot's IncomePerSecond, display only: the server pays)
function Ring.Income()
	local index = LocalPlayer and LocalPlayer:GetAttribute(Config.Attr.SpotIndex or "SpotIndex")
	if type(index) ~= "number" then
		return 0
	end
	local folder = Ring.plot
	if not (folder and folder.Parent and folder:GetAttribute("SpotIndex") == index) then
		local lobby = workspace:FindFirstChild("NimbusLobby")
		folder = lobby and lobby:FindFirstChild(string.format("Spot_%02d", index), true) or nil
		Ring.plot = folder
	end
	local value = folder and folder:GetAttribute("IncomePerSecond")
	return type(value) == "number" and value or 0
end

function Ring.Preview(B)
	if B.ringPreview then
		return B.ringPreview
	end
	local round = B.Round > 0 and B.Round or 1
	local best = B.Ring and num(B.Ring.Best, 0) or 0
	local cfg = BattleCatalog and type(BattleCatalog.Ring) == "table" and BattleCatalog.Ring or {}
	local every = num(cfg.BossEvery, 10)
	local champ = B.Ring and type(B.Ring.Champion) == "table" and B.Ring.Champion or {}
	local p = { Round = round, Record = round > best, Boss = champ.Boss == true or (every > 0 and round % every == 0), Cash = 0, Xp = 0, Tokens = 0 }
	if BattleCatalog and type(BattleCatalog.RingRewards) == "function" then
		local ok, r = pcall(BattleCatalog.RingRewards, round, Ring.Income(), p.Record)
		if ok and type(r) == "table" then
			p.Cash, p.Xp, p.Tokens = num(r.Cash, 0), num(r.Xp, 0), num(r.Tokens, 0)
		end
	end
	B.ringPreview = p
	return p
end

-- the info row of the top card: ring (win pay, record, boss round)
function Ring.BuildInfo(top)
	local info = make("Frame", { Name = "RingInfo", BackgroundTransparency = 1, Visible = false }, top)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, info)
	Hud.info = info
	Hud.infoWin = smallPill(info, "", Theme.Currency.Cash.Color, { Name = "WinPay", LayoutOrder = 1 })
	Hud.infoRecord = smallPill(info, "RECORD x3", Ring.GOLD, { Name = "Record", LayoutOrder = 2, Visible = false })
	Hud.infoBoss = smallPill(info, "BOSS", Ring.VIOLET, { Name = "Boss", LayoutOrder = 3, Visible = false })
end

function Ring.LayoutInfo(B, topW, y)
	local info = Hud.info
	if not info then
		return y
	end
	local ring = B.Mode == "Ring" and B.Fighter
	if not ring then
		info.Visible = false
		return y
	end
	info.Visible = true
	Hud.infoWin.Visible = ring
	Hud.infoRecord.Visible = false
	Hud.infoBoss.Visible = false
	if ring then
		local p = Ring.Preview(B)
		-- (a compact top card drops the "Win:" so the pills fit its width)
		local compact = Hud.m and Hud.m.Compact
		setText(Hud.infoWin, (compact and "+" or "Win: +") .. Ring.Money(p.Cash) .. "  +" .. Theme.ShortNumber(p.Xp) .. " XP")
		Hud.infoRecord.Visible = p.Record and B.Round > 1
		Hud.infoBoss.Visible = p.Boss
	end
	info.Position = UDim2.fromOffset(K.PAD, y)
	info.Size = UDim2.fromOffset(topW - 2 * K.PAD, 26)
	return y + 30
end

-- the side card between two rounds: "Round 8 won!" / "+$319  +68 XP" / "Round 9 in 3" (never the screen centre:
-- where the commands were on a wide screen, under the team cards on a tall phone, at the right edge in landscape)
function Ring.EnsureNext()
	if Hud.next and Hud.next.Parent then
		return Hud.next
	end
	if not Hud.root then
		return nil
	end
	local f = neonCard(Hud.root, "NextRoundCard", Ring.GOLD, { Visible = false, Floor = false }).Root
	Hud.next = f
	Hud.nextTitle = label(f, "", "Title", 28, { Name = "Title", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Ring.GOLD })
	Hud.nextTitle.TextStrokeColor3 = COLORS.Ink
	Hud.nextLine = label(f, "", "Heading", 21, { Name = "Pay", TextXAlignment = Enum.TextXAlignment.Left })
	Hud.nextExtra = label(f, "", "Label", 18, { Name = "Extra", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = COLORS.Mine })
	Hud.nextCount = label(f, "", "Display", 24, { Name = "Countdown", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = COLORS.White })
	Hud.nextBar = thinBar(f, "Timer", 8, Ring.GOLD)
	Hud.nextLeave = Leave.Make(f, 20) -- LEAVE between two rounds (BattleService takes "Forfeit" during the intermission)
	return f
end

function Ring.ShowNext(B, payload)
	local rw = payload.Rewards
	local round = num(rw.Round, B.Round)
	B.ringNext = {
		Round = round,
		Next = num(rw.Next, round + 1),
		Cash = num(rw.Cash, 0),
		Xp = num(rw.Xp, 0),
		Tokens = num(rw.Tokens, 0),
		Record = rw.Record == true,
		At = os.clock(),
		Seconds = Ring.INTERMISSION,
	}
	if rw.Record == true and B.Ring then
		B.Ring.Best = max(num(B.Ring.Best, 0), round)
	end
	St.next = B.ringNext
	St.result = nil
	if Hud.result then
		Hud.result.Visible = false
	end
	pcall(Hud.Rebuild) -- top card + team stay, the commands go, Ring.PlaceNext shows the side card
	BattleController._wake()
end

function Ring.PlaceNext(B)
	local nx = B and B.ringNext
	if not nx then
		if Hud.next then
			Hud.next.Visible = false
		end
		return
	end
	local f = Ring.EnsureNext()
	if not f then
		return
	end
	local m = Hud.m or Hud.Metrics()
	setText(Hud.nextTitle, "Round " .. nx.Round .. " won!")
	setText(Hud.nextLine, "+" .. Ring.Money(nx.Cash) .. "   +" .. Theme.ShortNumber(nx.Xp) .. " XP")
	local extra = {}
	if nx.Record then
		extra[#extra + 1] = "New record! Cash x3"
	end
	if nx.Tokens > 0 then
		extra[#extra + 1] = "+" .. Theme.ShortNumber(nx.Tokens) .. " Tokens"
	end
	Hud.nextExtra.Visible = #extra > 0
	setText(Hud.nextExtra, table.concat(extra, "  "))
	local w
	local portraitTop = nil
	if not m.Compact then
		-- where the action cluster was (bottom right)
		w = 380
		f.AnchorPoint = Vector2.new(1, 1)
		f.Position = UDim2.new(1, -K.EDGE, 1, -K.EDGE)
	else
		-- the right edge, under the currency pills / the top card when they reach there; never the screen centre
		w = m.Landscape and max(240, min(320, floor(m.W * 0.3) - 16)) or min(340, m.W - 24)
		local y0 = 6
		local cb = Hud.CurrencyTop(m)
		if cb > 0 then
			y0 = cb + 6
		end
		local tr = Hud.topRect
		if tr and Hud.top.Visible and tr[3] > m.W - w - 20 then
			-- a landscape phone: narrow the card to stay beside the top card (below it would reach the DASH button)
			local w2 = m.W - 8 - (tr[3] + 10)
			if m.Landscape and w2 >= 220 then
				w = w2
			else
				y0 = max(y0, tr[4] + 8)
			end
		end
		if m.Landscape then
			f.AnchorPoint = Vector2.new(1, 0)
			f.Position = UDim2.fromOffset(m.W - 8, y0)
		else
			-- a tall phone: under the top card at the right (clear of the fighter block), above the screen centre;
			-- else the lower right above the jump / RUN buttons (placed once the card's height is known)
			portraitTop = (tr and Hud.top.Visible) and (tr[4] + 8) or y0
			if Hud.team.Visible then
				local teamRight = Hud.team.Position.X.Offset + Hud.team.Size.X.Offset
				local teamBottom = Hud.team.Position.Y.Offset + Hud.team.Size.Y.Offset
				if Hud.fighterCard and portraitTop >= Hud.team.Position.Y.Offset + Hud.fighterCard.Root.Size.Y.Offset then
					teamRight = Hud.team.Position.X.Offset + (Hud.helperCellW or 0) -- (only the helper column reaches down here)
				end
				if teamBottom > portraitTop then
					w = min(w, m.W - 8 - teamRight - 8)
				end
			end
			if w < 240 then
				w = min(340, m.W - 24)
				portraitTop = nil
			end
		end
	end
	local inner = w - 2 * K.PAD - 8
	local y = K.PAD
	Hud.nextTitle.Position = UDim2.fromOffset(K.PAD + 4, y)
	Hud.nextTitle.Size = UDim2.fromOffset(inner, 32)
	y = y + 34
	Hud.nextLine.Position = UDim2.fromOffset(K.PAD + 4, y)
	Hud.nextLine.Size = UDim2.fromOffset(inner, 26)
	y = y + 28
	if #extra > 0 then
		Hud.nextExtra.Position = UDim2.fromOffset(K.PAD + 4, y)
		Hud.nextExtra.Size = UDim2.fromOffset(inner, 22)
		y = y + 26
	end
	-- a landscape phone: LEAVE shares the countdown's row (the card stays clear of the DASH / RUN buttons under it)
	local inline = m.Compact and m.Landscape and Leave.Allowed(B)
	local countW = inline and (inner - 92 - 6) or inner
	Hud.nextShort = countW < 150 -- ("Next in 3" when the row is short)
	Hud.nextCount.Position = UDim2.fromOffset(K.PAD + 4, y + (inline and 4 or 0))
	Hud.nextCount.Size = UDim2.fromOffset(countW, 30)
	local countY = y
	y = y + (inline and 42 or 32)
	Hud.nextBar.Root.Position = UDim2.fromOffset(K.PAD + 4, y)
	Hud.nextBar.Root.Size = UDim2.fromOffset(inner, 8)
	y = y + 8 + K.PAD
	if inline then
		Leave.PlaceOnCard(m, B, w, countY, true)
	else
		y = Leave.PlaceOnCard(m, B, w, y)
	end
	f.Size = UDim2.fromOffset(w, y)
	if m.Compact and not m.Landscape then
		if portraitTop and portraitTop + y <= m.H * 0.5 - 4 then
			f.AnchorPoint = Vector2.new(1, 0)
			f.Position = UDim2.fromOffset(m.W - 8, portraitTop)
		else
			local r = Hud.TouchRects(m)
			local above = (max(r.jump[4], r.run[4]) + 12) / max(0.05, m.F)
			f.AnchorPoint = Vector2.new(1, 1)
			f.Position = UDim2.fromOffset(m.W - 8, m.H - above)
		end
	end
	f.Visible = true
	Hud.FixText(f, m.F)
	Ring.UpdateNext(os.clock())
end

-- the countdown (a text write only when the shown second changes)
function Ring.UpdateNext(now)
	local nx = St.next
	if not nx then
		return
	end
	local f = Hud.next
	if not f or not f.Visible or not St.battle or St.battle.ringNext ~= nx then
		Ring.HideNext()
		return
	end
	local left = nx.Seconds - (now - nx.At)
	local label = Hud.nextShort and "Next" or ("Round " .. nx.Next)
	local text = (left > 0.05) and (label .. " in " .. math.ceil(left - 0.05)) or (label .. "...")
	setText(Hud.nextCount, text)
	setThin(Hud.nextBar, clamp(left / max(0.1, nx.Seconds), 0, 1))
end

function Ring.HideNext()
	St.next = nil
	if Hud.next then
		Hud.next.Visible = false
	end
end

-- the run ended between two rounds (its final End names the last round's id): the result card replaces the side card
function Ring.FinalAfterWin(B, payload)
	B.ringNext = nil
	Net.Music()
	Ring.HideNext()
	B.linger = K.END_LINGER
	B.endAt = os.clock()
	Hud.ShowResult(B, payload)
end

-- my pets' models + cards out of a won round (to be handed to the next round's units of the same key)
function Ring.TakeModels(B)
	local out = {}
	for _, u in pairs(B.mine) do
		local key = u.info and u.info.key
		if type(key) == "string" and u.model and not u.failed and out[key] == nil then
			out[key] = { model = u.model, root = u.root, height = u.height, centerY = u.centerY, rigid = u.rigid, card = u.card, evo = u.evo, x = u.x, z = u.z, yaw = u.yaw }
			u.model, u.root, u.card = nil, nil, nil
			out[key].model.Parent = nil
		end
	end
	return out
end

function Ring.GiveModels(B, carry)
	for _, u in pairs(B.mine) do
		local key = u.info and u.info.key
		local c = type(key) == "string" and carry[key] or nil
		if c and c.evo == u.evo and not u.model then
			carry[key] = nil
			u.model, u.root, u.height, u.centerY, u.rigid, u.card = c.model, c.root, c.height, c.centerY, c.rigid, c.card
			u.x, u.z, u.yaw, u.seen = c.x, c.z, c.yaw, false
			u.folder = B.folder
			u.model.Name = "Unit_" .. tostring(u.id)
			u.model.Parent = B.folder
			u.cardWrites = 0
			u.cardHp, u.cardMeter = nil, nil
			u.carried = true
			if u.card then
				u.card:SetMode(Cards.ModeOf(u))
				Cards.Static(u)
				Cards.Live(u)
			end
		end
	end
	for _, c in pairs(carry) do
		if c.card then
			pcall(c.card.Destroy, c.card)
		end
		pcall(c.model.Destroy, c.model)
	end
end

-- the result card of a run: RUN OVER / NEW RECORD!, where it ended
function Ring.ResultTitle(B, payload, sub)
	local rw = type(payload.Rewards) == "table" and payload.Rewards or {}
	local run = type(rw.Run) == "table" and rw.Run or {}
	local round = num(run.Round, num(rw.Round, B.Round))
	local title = run.Record ~= nil and "NEW RECORD!" or "RUN OVER"
	local why
	if rw.Void == true then
		why = "server restart: round " .. round .. " does not count"
	elseif payload.Outcome == "Left" or payload.Reason == "Forfeit" or payload.Reason == "Left" then
		why = "you left after round " .. round
	elseif payload.Reason == "Timeout" then
		why = "time ran out in round " .. round
	else
		why = "the champion won round " .. round
	end
	return title, Ring.GOLD, "Champion Ring: " .. why
end

-- the run's lines: Rounds won, Cash, XP, Tokens, the record
function Ring.ResultLines(B, rw)
	local run = type(rw.Run) == "table" and rw.Run or nil
	if not run then
		return Hud.RewardLines(B, rw)
	end
	local lines = {}
	local wins = num(run.Wins, 0)
	lines[#lines + 1] = { "Rounds won: " .. wins, COLORS.Gold }
	lines[#lines + 1] = { "+" .. Ring.Money(run.Cash) .. " Cash", Theme.Currency.Cash.Color }
	lines[#lines + 1] = { "+" .. Theme.ShortNumber(num(run.Xp, 0)) .. " Pet XP", COLORS.Ally }
	local tokens = num(run.Tokens, 0)
	if tokens > 0 then
		lines[#lines + 1] = { "+" .. Theme.ShortNumber(tokens) .. " Tokens", Theme.Currency.Tokens.Color }
	end
	-- (level-ups are the server's toasts: the card stays short enough for a landscape phone)
	if run.Record ~= nil then
		lines[#lines + 1] = { "Best: round " .. tostring(run.Record) .. "!", COLORS.Mine }
	elseif num(run.Best, 0) > 0 then
		lines[#lines + 1] = { "Best: round " .. tostring(num(run.Best, 0)), COLORS.Weak }
	end
	return lines
end

----------------------------------------------------------------------
-- Input (contract 4.7 control map; bound through ContextActionService at High priority ONLY while fighting)
--   ATTACK  left click / F / X / the big round button: ONE "Attack" order per press (dungeon fixes decision 4): the
--           fighter attacks by itself (server auto-attack); "Attack"(id) = attack this one (a click on an enemy; with
--           the mouse locked the enemy under the screen centre), "Attack"() = the nearest / the next one
--   ELEMENT E / Y / its button (cooldown ring); E passes through while a ProximityPrompt is shown (exit, chest)
--   SPECIAL Q / RB / its button (lights gold at 100)
--   DASH    Shift / B / its button: the PET dashes ("Dash"; MovementController.SetPetDash: no character impulse, no
--           stamina); RUN moves to Ctrl in a battle
--   lock    Tab cycles (nearest first), click / tap an enemy or its row; T clears; RT cycles, LT clears
--   helpers 1 / 2 (LB / D-up) tap = its buff, hold 0.5 s = swap; the SWAP chip; D-left / D-right swap; the portrait
--           (tap = buff, hold = swap)
----------------------------------------------------------------------
local KEY_HELPER = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.ButtonL1] = 1,
	[Enum.KeyCode.DPadUp] = 2,
}
local KEY_SWAP = {
	[Enum.KeyCode.DPadLeft] = 1,
	[Enum.KeyCode.DPadRight] = 2,
}

local function sink()
	local ok, v = pcall(function()
		return Enum.ContextActionResult.Sink
	end)
	return ok and v or nil
end

local function pass()
	local ok, v = pcall(function()
		return Enum.ContextActionResult.Pass
	end)
	return ok and v or nil
end

local function fighting()
	local B = St.battle
	return B ~= nil and B.Fighter and not B.ended
end

-- the main menu is gone (UiGate.HasPlayed, 7.2); no UiGate module = always
function Input.GateOpen()
	local hook = BattleController.Hooks.Gate
	if type(hook) == "function" then
		return hook() ~= false
	end
	if Mods.UiGate == nil then
		Mods.UiGate = optional(Client, "UiGate") or false
	end
	local g = Mods.UiGate
	if g and type(g.HasPlayed) == "function" then
		local ok, played = pcall(g.HasPlayed)
		return (not ok) or played ~= false
	end
	return true
end

-- a ProximityPrompt shown to me that E would press (dungeon fixes 6: E stays the interaction key)
function Input.PromptShown()
	for prompt in pairs(St.prompts) do
		local ok, live = pcall(function()
			local code = prompt.KeyboardKeyCode
			return prompt.Parent ~= nil and prompt.Enabled ~= false and (code == nil or code == Enum.KeyCode.E)
		end)
		if ok and live then
			return true
		elseif not ok or prompt.Parent == nil then
			St.prompts[prompt] = nil
		end
	end
	return false
end

function Input.OnAction(name, state, input)
	if not fighting() or not Input.GateOpen() then
		return pass()
	end
	local began = state == Enum.UserInputState.Begin
	local key = input and input.KeyCode
	if name == K.ACTION_ELEMENT and key == Enum.KeyCode.E and Input.PromptShown() then
		return pass() -- the shown prompt (the room's exit, a chest) gets the E
	end
	local ended = state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel
	if name == K.ACTION_ATTACK then
		if began then
			Input.Press("Attack", true)
			Input.HoldStart("attackKey", 0, os.clock(), "Attack") -- bug #16: hold 0.4 s = the next target
		elseif ended then
			Input.HoldEnd("attackKey")
		end
	elseif name == K.ACTION_ELEMENT then
		if began then
			Input.Press("Element", true)
		end
	elseif name == K.ACTION_SPECIAL then
		if began then
			Input.Press("Special", true)
		end
	elseif name == K.ACTION_TARGET then
		if began then
			if key == Enum.KeyCode.T or key == Enum.KeyCode.ButtonL2 then
				BattleController.Focus(nil)
			else
				Input.CycleTarget()
			end
		end
	elseif name == K.ACTION_HELPER then
		local index = key and KEY_HELPER[key]
		local swapIndex = key and KEY_SWAP[key]
		if swapIndex then
			if began then
				Input.Helper("Swap", swapIndex)
			end
		elseif index then
			if began then
				Input.HoldStart("key" .. index, index, os.clock())
			elseif ended then
				Input.HoldEnd("key" .. index)
			end
		end
	end
	return sink()
end

function Input.Bind(on)
	if on == St.bound then
		return
	end
	St.bound = on
	if on then
		local priority = 2000
		pcall(function()
			priority = Enum.ContextActionPriority.High.Value
		end)
		pcall(function()
			ContextActionService:BindActionAtPriority(K.ACTION_ATTACK, Input.OnAction, false, priority, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
			ContextActionService:BindActionAtPriority(K.ACTION_ELEMENT, Input.OnAction, false, priority, Enum.KeyCode.E, Enum.KeyCode.ButtonY)
			ContextActionService:BindActionAtPriority(K.ACTION_SPECIAL, Input.OnAction, false, priority, Enum.KeyCode.Q, Enum.KeyCode.ButtonR1)
			ContextActionService:BindActionAtPriority(K.ACTION_TARGET, Input.OnAction, false, priority, Enum.KeyCode.Tab, Enum.KeyCode.T, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonL2)
			ContextActionService:BindActionAtPriority(
				K.ACTION_HELPER, Input.OnAction, false, priority,
				Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.KeypadOne, Enum.KeyCode.KeypadTwo,
				Enum.KeyCode.ButtonL1, Enum.KeyCode.DPadUp, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight
			)
		end)
	else
		for _, name in ipairs({ K.ACTION_ATTACK, K.ACTION_ELEMENT, K.ACTION_SPECIAL, K.ACTION_TARGET, K.ACTION_HELPER }) do
			pcall(function()
				ContextActionService:UnbindAction(name)
			end)
		end
		St.holds = {}
	end
end

-- MovementController's battle switches (contract 3.9 / 4.4, dungeon fixes decision 5): Shift / B = the PET's dash
-- (SetPetDash: the keys only send "Dash", the character gets no impulse and spends no stamina; RUN moves to Ctrl),
-- the battle speeds. (An older MovementController without SetPetDash: the old character dash keys.)
function Input.Movement(B, on)
	local mc = Hud.Movement()
	if not mc then
		return
	end
	if on then
		if type(mc.SetPetDash) == "function" then
			pcall(mc.SetPetDash, Input.PetDash)
		else
			local F = BattleCatalog and BattleCatalog.Fighter or {}
			pcall(mc.SetDashKeys, { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonB })
			pcall(mc.SetFreeDash, true, num(F.DashCooldown, 2.5))
			if type(mc.SetDashListener) == "function" then
				pcall(mc.SetDashListener, Input.PetDash)
			end
		end
		local sp = B and B.speed
		if sp then
			pcall(mc.SetBattleSpeed, sp.Walk, sp.Run)
		end
		St.movementOn = true
	elseif St.movementOn then
		St.movementOn = false
		if type(mc.SetPetDash) == "function" then
			pcall(mc.SetPetDash, nil)
		else
			pcall(mc.SetDashKeys, nil)
			pcall(mc.SetFreeDash, false)
			if type(mc.SetDashListener) == "function" then
				pcall(mc.SetDashListener, nil)
			end
		end
		pcall(mc.SetBattleSpeed, nil)
	end
end

-- Shift / B in a battle (MovementController.SetPetDash calls it): the pet's dash
function Input.PetDash()
	if not fighting() or not Input.GateOpen() then
		return false
	end
	return BattleController.Command("Dash")
end

-- a button press of an action (keys, the round buttons): ONE command per press (ATTACK never repeats: the fighter
-- attacks by itself, ATTACK only tells it which enemy; arg = that enemy's id, nil = the nearest / the next one)
function Input.Press(kind, down, arg)
	if not down or not fighting() then
		return
	end
	if kind == "Attack" then
		BattleController.Command("Attack", arg)
		return
	end
	BattleController.Command(kind)
end

-- per frame: a helper key / portrait held 0.5 s swaps; an ATTACK key / button held 0.4 s locks the next target (bug #16)
function Input.Tick(B, now)
	if not B or not fighting() then
		return
	end
	for key, h in pairs(St.holds or {}) do
		if h.kind == "Attack" and not h.fired and h.gui and h.input and not Input.OnButton(h.input, h.gui) then
			St.holds[key] = nil -- the touch / cursor slid off the ATTACK button: no re-target the player did not ask for
		elseif h.kind == "Attack" then
			if not h.fired and now - h.t >= K.ATTACK_HOLD then
				h.fired = true
				Input.CycleTarget()
				St.nextFlashUntil = os.clock() + K.NEXT_FLASH
				Hud.Captions(B)
			end
		elseif not h.fired and now - h.t >= K.SWAP_HOLD then
			h.fired = true
			Input.Helper("Swap", h.index)
		end
	end
	if St.nextFlashUntil and os.clock() >= St.nextFlashUntil then
		St.nextFlashUntil = nil
		Hud.Captions(B)
	end
end

-- `kind` "Attack" = an ATTACK hold (bug #16: it cycles the target, never a helper's Buff / Swap); `input` / `gui` (the
-- ATTACK button's touch / click): the hold is dropped when that input leaves the button or ends anywhere
function Input.HoldStart(key, index, t, kind, input, gui)
	if not fighting() or not Input.GateOpen() then
		return
	end
	St.holds = St.holds or {}
	St.holds[key] = { index = index, t = t, fired = false, kind = kind, input = input, gui = gui }
	BattleController._wake()
end

function Input.HoldEnd(key)
	local h = St.holds and St.holds[key]
	if not h then
		return
	end
	St.holds[key] = nil
	if not h.fired and h.kind ~= "Attack" then
		Input.Helper("Buff", h.index)
	end
end

-- 0..1 of a running swap hold on helper `index` (the SWAP chip fills; nothing for a short tap)
function Input.HoldFrac(index, now)
	local best = 0
	for _, h in pairs(St.holds or {}) do
		if h.index == index and not h.fired and h.kind ~= "Attack" then
			local p = (now - h.t - 0.1) / (K.SWAP_HOLD - 0.1)
			if p > best then
				best = min(1, p)
			end
		end
	end
	return best
end

-- "Buff" / "Swap" for the helper shown in portrait `index` (its team slot goes to the server)
function Input.Helper(action, index)
	local B = St.battle
	if not B or not fighting() then
		return false
	end
	local H = Hud.helpers and Hud.helpers[index]
	local u = H and H.unit
	if not u then
		local bench = Hud.Bench(B)
		u = bench[index]
	end
	if not u then
		return false
	end
	return BattleController.Command(action, u.slot)
end

-- Tab / RT: lock the next enemy, nearest to my fighter first
function Input.CycleTarget()
	local B = St.battle
	if not B then
		return
	end
	local f = B.fighterId and B.units[B.fighterId]
	local fx, fz = f and f.x or 0, f and f.z or 0
	local list = {}
	for _, u in ipairs(B.list) do
		if not u.ally and u.hp > 0 and u.state ~= S_DOWN and u.state ~= S_BENCHED and not u.hidden and (u.model or u.isBoss) then
			local dx, dz = u.x - fx, u.z - fz
			list[#list + 1] = { u = u, d = dx * dx + dz * dz }
		end
	end
	if #list == 0 then
		return
	end
	table.sort(list, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		return a.u.id < b.u.id
	end)
	local pick = list[1].u
	for i, e in ipairs(list) do
		if e.u.id == B.lock then
			pick = list[(i % #list) + 1].u
			break
		end
	end
	BattleController.Focus(pick.id)
end

-- the enemy a tap / click at viewport pixel (x, y) picks (nearest projected enemy within reach), or nil
function BattleController.ScreenPick(x, y)
	local B = St.battle
	local cam = workspace.CurrentCamera
	if not B or not cam then
		return nil
	end
	local reach = K.TAP_REACH * Theme.ScreenFactor()
	local best, bestD = nil, math.huge
	for _, u in ipairs(B.list) do
		if not u.ally and u.model and not u.parked and not u.hidden and u.hp > 0 and u.state ~= S_DOWN then
			local ok, p, onScreen = pcall(cam.WorldToViewportPoint, cam, unitCenter(B, u))
			if ok and onScreen and p.Z > 0 then
				local dx, dy = p.X - x, p.Y - y
				local d = sqrt(dx * dx + dy * dy)
				local r = reach
				if u.isBoss then
					r = reach * 3
				elseif u.kind == "MiniBoss" then
					r = reach * 1.6
				end
				if d <= r and d < bestD then
					best, bestD = u.id, d
				end
			end
		end
	end
	return best
end

local function guiInset()
	local inset = 36
	local ok, a = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if ok and typeof(a) == "Vector2" then
		inset = a.Y
	end
	return inset
end

function Input.OnBegan(input, processed)
	local t = input.UserInputType
	if t == Enum.UserInputType.Gamepad1 or t == Enum.UserInputType.Gamepad2 then
		if not St.gamepad then
			St.gamepad = true
			Hud.Keys()
		end
	elseif t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		if St.gamepad then
			St.gamepad = false
			Hud.Keys()
		end
	end
	if processed or not fighting() or not Input.GateOpen() then
		return
	end
	if t == Enum.UserInputType.Touch then
		St.tap = { x = input.Position.X, y = input.Position.Y, t = os.clock(), input = input }
	elseif t == Enum.UserInputType.MouseButton1 then
		-- one "Attack" order: the enemy under the cursor (the screen centre while MouseLock holds the cursor there),
		-- else the nearest / the next one
		local x, y = input.Position.X, input.Position.Y + guiInset()
		local cam = workspace.CurrentCamera
		if Input.MouseLocked() and cam then
			x, y = cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2
		end
		Input.Press("Attack", true, BattleController.ScreenPick(x, y))
	end
end

-- the cursor is locked at the screen centre (client/MouseLock's option: MouseBehavior LockCenter)
function Input.MouseLocked()
	local ok, locked = pcall(function()
		return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
	end)
	return ok and locked == true
end

-- is `input` (a touch / the mouse, GUI-inset space) still over `gui` (a few px of slack)?
function Input.OnButton(input, gui)
	local ok, inside = pcall(function()
		local p = input.Position
		local sg = gui:FindFirstAncestorOfClass("ScreenGui")
		local y = p.Y + ((sg and sg.IgnoreGuiInset) and guiInset() or 0)
		local a, s = gui.AbsolutePosition, gui.AbsoluteSize
		local slack = 6
		return gui.Visible and p.X >= a.X - slack and p.X <= a.X + s.X + slack and y >= a.Y - slack and y <= a.Y + s.Y + slack
	end)
	return not ok or inside == true
end

function Input.OnEnded(input)
	local t = input.UserInputType
	-- the ATTACK button's hold ends with its own touch / the mouse button wherever it is released (bug #16 review: a
	-- release off the button never reaches the button's InputEnded)
	local ah = St.holds and St.holds.attackButton
	if ah and ((t == Enum.UserInputType.MouseButton1 and (ah.input == nil or ah.input.UserInputType == t)) or (t == Enum.UserInputType.Touch and (ah.input == nil or ah.input == input))) then
		Input.HoldEnd("attackButton")
	end
	local tap = St.tap
	if not tap or t ~= Enum.UserInputType.Touch then
		return
	end
	St.tap = nil
	if not fighting() or os.clock() - tap.t > K.TAP_TIME then
		return
	end
	local dx, dy = input.Position.X - tap.x, input.Position.Y - tap.y
	if dx * dx + dy * dy > K.TAP_MOVE * K.TAP_MOVE then
		return
	end
	-- input positions are in GUI space (below the top bar); the camera projects into the full viewport
	local id = BattleController.ScreenPick(input.Position.X, input.Position.Y + guiInset())
	if id then
		BattleController.Focus(id)
	end
end

----------------------------------------------------------------------
-- Commands (BattleCommand(action, arg)); the server decides everything, the client predicts only the button's ring
----------------------------------------------------------------------
local VALID_ACTIONS = { Attack = true, Element = true, Special = true, Dash = true, Target = true, Buff = true, Swap = true, Forfeit = true, Cheer = true }

local function commandRemote()
	if St.remoteCmd and St.remoteCmd.Parent then
		return St.remoteCmd
	end
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local r = folder and folder:FindFirstChild("BattleCommand")
	St.remoteCmd = r
	return r
end

-- the cooldown lengths of my team (BattleCatalog.Fighter; a helper's own Cooldown from its unit info)
function Input.CooldownLengths(B)
	local F = BattleCatalog and BattleCatalog.Fighter or {}
	B.cdLen = {
		Element = num(F.ElementCooldown, 7),
		Dash = num(F.DashCooldown, 2.5),
		Swap = num(F.SwapCooldown, 10),
		Cheer = num(F.CheerCooldown, 20),
		Buff = {},
	}
	for slot = 1, 4 do
		local u = B.mine[slot]
		if u then
			local buff = type(u.info.buff) == "table" and u.info.buff or nil
			local default = (u.info.role == "Support") and num(F.SupportCooldown, 12) or num(F.HelperCooldown, 15)
			B.cdLen.Buff[slot] = num(buff and buff.Cooldown, default)
		end
	end
end

-- a local refusal: the button shakes, nothing is sent
local function refuse(action, slot)
	Hud.Shake(Hud.ButtonOf(action, slot))
	return false
end

function BattleController.Command(action, arg)
	local B = St.battle
	if not B or not B.Fighter then
		return false
	end
	-- a ring run can be left between two rounds too: the won round has ended, the next Start has not come yet
	if B.ended and not (action == "Forfeit" and B.Mode == "Ring" and B.ringNext ~= nil) then
		return false
	end
	if not VALID_ACTIONS[action] then
		return false
	end
	local key = action .. tostring(arg)
	local now = os.clock()
	local gap = (action == "Attack") and K.ATTACK_GAP or K.CMD_GAP
	if St.lastCmd[key] and now - St.lastCmd[key] < gap then
		return false
	end
	-- local checks: instant feedback, no pointless traffic (the server decides)
	local f = B.fighterId and B.units[B.fighterId]
	if action == "Element" or action == "Dash" or action == "Swap" then
		if cdLeft(B, action, nil, now) > K.CD_SLACK then
			return refuse(action)
		end
		if action == "Swap" then
			local u = B.mine[tonumber(arg) or 0]
			if not u or u.id == B.fighterId or u.hp <= 0 or u.state == S_DOWN then
				return refuse(action, tonumber(arg))
			end
		end
	elseif action == "Buff" then
		local slot = tonumber(arg) or 0
		local u = B.mine[slot]
		if not u or u.id == B.fighterId or u.hp <= 0 or u.state == S_DOWN or cdLeft(B, "Buff", slot, now) > K.CD_SLACK then
			return refuse(action, slot)
		end
	elseif action == "Special" then
		if not f or not f.special or f.meter < METER_MAX then
			return refuse(action)
		end
	elseif action == "Cheer" then
		-- (wave 6) Raid / Dungeon only; the Ring / PvP podium cheer is the server's
		if not CheerUp.Allowed(B) then
			return false
		end
		if arg ~= nil or cdLeft(B, "Cheer", nil, now) > K.CD_SLACK then
			return refuse(action)
		end
	elseif (action == "Attack" or action == "Target") and arg ~= nil then
		local u = B.units[arg]
		if not u or u.ally or u.hp <= 0 then
			return false
		end
	end
	St.lastCmd[key] = now
	local remote = commandRemote()
	if not remote then
		return false
	end
	local ok = pcall(function()
		if arg ~= nil then
			remote:FireServer(action, arg)
		else
			remote:FireServer(action)
		end
	end)
	if not ok then
		return false
	end
	St.sent = (St.sent or 0) + 1
	if action == "Forfeit" then
		return true -- the run's End does the rest
	end
	Input.Predict(B, action, arg, now)
	return true
end

-- wave 6: Cheer up! (the button does the same)
function BattleController.Cheer()
	return BattleController.Command("Cheer")
end

-- lock-on: Target(id) (nil clears); the server echoes the lock (Order "Target")
function BattleController.Focus(unitId)
	local B = St.battle
	if not B or not B.Fighter or B.ended then
		return false
	end
	if unitId == nil and B.lock == nil then
		return false
	end
	return BattleController.Command("Target", unitId)
end

-- prediction: the button's own ring starts at once; the matching event (Element / Dash / Buff / Swap / Hit /
-- Special / Order) within PENDING_TIMEOUT confirms it, a rejected Order or the timeout puts the old ring back
function Input.Predict(B, action, arg, now)
	local pend = B.pending
	local cd = B.cd
	if action == "Element" or action == "Dash" or action == "Swap" or action == "Cheer" then
		pend[action] = { t = now, prev = cd[action] or 0 }
		cd[action] = now + (B.cdLen[action] or 1)
	elseif action == "Buff" then
		local slot = tonumber(arg) or 0
		pend.Buff = { t = now, slot = slot, prev = cd.Buff[slot] or 0 }
		cd.Buff[slot] = now + (B.cdLen.Buff[slot] or 15)
		local H = nil
		for _, h in ipairs(Hud.helpers or {}) do
			if h.unit and h.unit.slot == slot then
				H = h
			end
		end
		if H then
			Hud.Pop(H.Face)
		end
	elseif action == "Target" then
		pend.Target = { t = now, prev = B.lock }
		B.lock = arg
		Hud.enemyDirty = true
	elseif action == "Attack" then
		-- no swing: the fighter attacks by itself (its lunges come from the server's Hits); a picked enemy shows the
		-- arrow at once (the server's lock echo / snapshot target follow)
		pend.Attack = { t = now, prev = B.lock }
		if arg ~= nil then
			B.lock = arg
			Hud.enemyDirty = true
		end
	elseif action == "Special" then
		pend.Special = { t = now }
		Atk.PreCharge(B, now) -- (Task 11b) its charge shows at once when my view says it can go
	end
	if action ~= "Target" then
		Hud.Pop(Hud.ButtonOf(action, tonumber(arg)))
	end
	Hud.ringAt = 0 -- repaint the rings on the next frame
end

-- the server confirmed `action` (its event arrived)
function Input.Confirm(B, action, slot)
	local p = B.pending[action]
	if p and (action ~= "Buff" or slot == nil or p.slot == slot) then
		B.pending[action] = nil
		return true
	end
	return false
end

-- a refusal or a timeout: the ring goes back to what it showed before the press, the button shakes
function Input.Revert(B, action, shake)
	local p = B.pending[action]
	if not p then
		return
	end
	B.pending[action] = nil
	if action == "Element" or action == "Dash" or action == "Swap" or action == "Cheer" then
		B.cd[action] = p.prev or 0
	elseif action == "Buff" then
		B.cd.Buff[p.slot] = p.prev or 0
	elseif action == "Target" or (action == "Attack" and p.prev ~= B.lock) then
		B.lock = p.prev
		Hud.enemyDirty = true
	end
	if shake then
		Hud.Shake(Hud.ButtonOf(action, p.slot))
	end
	Hud.ringAt = 0
end

-- predictions that no event confirmed in time (10 Hz from Hud.Update)
function Input.CheckPending(B, now)
	for action, p in pairs(B.pending) do
		if now - p.t > K.PENDING_TIMEOUT then
			if action == "Attack" or action == "Special" or action == "Target" then
				B.pending[action] = nil -- nothing to put back (a Target that never echoed keeps the lock)
			else
				Input.Revert(B, action, true)
				St.timeouts = (St.timeouts or 0) + 1
			end
		end
	end
end

-- a small press pop (scale) on a button
function Hud.Pop(obj)
	if not obj or not obj.Parent then
		return
	end
	local s = obj:FindFirstChild("PopScale")
	if not s then
		s = make("UIScale", { Name = "PopScale", Scale = 1 }, obj)
	end
	pcall(function()
		s.Scale = 0.9
		Util.Tween(s, 0.16, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end)
end


----------------------------------------------------------------------
-- Messages
----------------------------------------------------------------------
-- the music: SoundFx's "Battle" layer is on while MY fight runs (a fighter, not a spectator), and between two won
-- Champion Ring rounds (B.ringNext: the floor stays, so does the beat). A dungeon room keeps the Dungeon track
-- (DungeonController's layer) except its boss room. -> the layer's state
function Net.Music()
	local B = St.battle
	local on = false
	if B and B.Fighter and (not B.ended or B.ringNext ~= nil) then
		local d = B.Mode == "Dungeon" and B.Dungeon or nil
		on = B.Mode ~= "Dungeon" or (type(d) == "table" and d.Boss == true and num(d.Room, 0) >= 3)
	end
	if St.musicOn ~= on then
		local SF = Me.Sound()
		if SF and type(SF.SetLayer) == "function" then
			pcall(SF.SetLayer, "Battle", on)
		end
		St.musicOn = on
	end
	return on
end

-- a clear earn moment (a won fight's payout): SoundFx "Reward"
function Net.RewardSound()
	local SF = Me.Sound()
	if SF and type(SF.Play) == "function" then
		pcall(SF.Play, "Reward")
	end
end

function Net.Cleanup(B, immediate)
	if not B then
		return
	end
	if B.Mode == "Dungeon" then
		pcall(Me.RecordDrawn, B)
	end
	Tele.ClearAll(B)
	for _, u in ipairs(B.list) do
		Units.Destroy(u)
	end
	B.list = {}
	B.units = {}
	B.mine = {}
	if B.folder then
		pcall(B.folder.Destroy, B.folder)
		B.folder = nil
	end
	if St.battle == B then
		St.battle = nil
		if B.ringNext then
			Ring.HideNext()
		end
		if B.Mode == "Ring" then
			St.ringLast = B -- a run's final "End" may still come for this battle id (it ended between two rounds)
		end
		Input.Bind(false)
		Input.Movement(B, false)
		if not St.result then
			Hud.SetVisible(false)
		end
	end
	Atk.ClearAll() -- (unit ids restart with every battle: no effect or pose may outlive its floor)
	if immediate then
		Fx.ClearAll()
	end
	if not St.starting then
		Net.Music() -- (a chained Start sets the music once the new battle is in: no Battle -> Lobby -> Battle blink)
	end
end

function Net.Start(payload, battleId)
	if type(payload) ~= "table" then
		return
	end
	local id = payload.BattleId or battleId
	local B = St.battle
	if B and B.Id == id and not B.ended then
		-- a refresh (a raid spectator joins): keep the models, update the side and the units
		local side = num(payload.Side, 0)
		B.Side = side
		B.Spectator = payload.Spectator == true or side == 0
		B.Fighter = not B.Spectator
		B.Names = type(payload.Names) == "table" and payload.Names or B.Names
		B.sides = type(payload.Sides) == "table" and payload.Sides or B.sides
		local keep = {}
		for _, info in ipairs(type(payload.Units) == "table" and payload.Units or {}) do
			local u = Units.Add(B, info)
			if u then
				keep[u.id] = true
				local me = myUserId()
				u.mine = B.Fighter and info.owner == me
				if B.Fighter then
					u.ally = u.side == B.Side
				else
					u.ally = u.side == 1
				end
				if u.mine and u.slot >= 1 then
					B.mine[u.slot] = u
				end
				if u.barFill then
					u.barFill.BackgroundColor3 = u.mine and COLORS.Mine or (u.ally and COLORS.Ally or COLORS.Enemy)
				end
				Cards.Restyle(u)
			end
		end
		for i = #B.list, 1, -1 do
			local u = B.list[i]
			if not keep[u.id] then
				Units.Remove(B, u.id)
			end
		end
		Net.Team(B, payload)
		Input.Bind(B.Fighter)
		Input.Movement(B, B.Fighter)
		Hud.Rebuild()
		Net.Music()
		return
	end
	-- the next Champion Ring round in the same pocket / the next dungeon room: my pets' models (and their cards)
	-- carry over, so nothing blinks between End and Start
	local chain = B and ((B.ringNext and tostring(payload.Mode) == "Ring") or (B.ended and B.Fighter and B.Mode == "Dungeon" and tostring(payload.Mode) == "Dungeon"))
	local carry = chain and Ring.TakeModels(B) or nil
	if B then
		St.starting = true
		local okClean, errClean = pcall(Net.Cleanup, B, false)
		St.starting = nil
		if not okClean then
			error(errClean, 0)
		end
	end
	B = newBattle(payload, battleId)
	B.sides = type(payload.Sides) == "table" and payload.Sides or {}
	St.battle = B
	Atk.Mod() -- (the pet attack VFX load with the first battle)
	B.renderT = num(payload.T, 0)
	for _, info in ipairs(type(payload.Units) == "table" and payload.Units or {}) do
		Units.Add(B, info)
	end
	Net.Team(B, payload)
	if carry then
		Ring.GiveModels(B, carry)
	end
	Ring.HideNext()
	St.ringLast = nil
	-- spread the first positions from the static info until the first snapshot arrives
	if B.Mode == "Raid" then
		local BB = lazyBoss()
		if BB and B.BossId and type(BB.Preload) == "function" then
			pcall(BB.Preload, B.BossId)
		end
	end
	St.result = nil
	if Hud.result then
		Hud.result.Visible = false
	end
	Input.Bind(B.Fighter)
	Input.Movement(B, B.Fighter)
	Hud.Rebuild()
	Net.Music()
	BattleController._wake()
end

-- Phase 5: my team from "Start".Team = { Fighter, Bench, Lives, Speed = { Walk, Run }, Cooldowns } (a late joiner
-- gets the running cooldowns: seconds left; Buff keyed by slot STRINGS on the wire)
function Net.Team(B, payload)
	Input.CooldownLengths(B)
	local team = type(payload.Team) == "table" and payload.Team or nil
	if not B.Fighter then
		return
	end
	local now = os.clock()
	if team then
		B.fighterId = tonumber(team.Fighter) or B.fighterId
		B.lives = tonumber(team.Lives) or B.lives
		if type(team.Speed) == "table" and tonumber(team.Speed.Walk) then
			B.speed = { Walk = tonumber(team.Speed.Walk), Run = tonumber(team.Speed.Run) }
		end
		local cds = type(team.Cooldowns) == "table" and team.Cooldowns or {}
		for _, kind in ipairs({ "Element", "Dash", "Swap", "Cheer" }) do
			local left = num(cds[kind], 0)
			B.cd[kind] = left > 0 and (now + left) or 0
		end
		if type(cds.Buff) == "table" then
			for key, left in pairs(cds.Buff) do
				local slot = tonumber(key)
				if slot then
					B.cd.Buff[slot] = num(left, 0) > 0 and (now + num(left, 0)) or 0
				end
			end
		end
	end
	if not B.fighterId then
		-- (an older Start without Team: my slot-1 pet)
		local u = B.mine[1]
		B.fighterId = u and u.id or nil
	end
	for slot = 1, 4 do
		local u = B.mine[slot]
		if u then
			u.benched = u.id ~= B.fighterId
		end
	end
	local f = B.fighterId and B.units[B.fighterId]
	B.fighterEvo = f and f.evo or 0
	if not B.speed and f then
		local walk, run = tonumber(f.info.walk), tonumber(f.info.run)
		if walk then
			B.speed = { Walk = walk, Run = run }
		end
	end
end

-- Phase 5: what an event changes for MY HUD, on arrival (the visuals play later on the render clock): predictions
-- confirmed / refused, cooldowns started, the lock, the fighter after a swap, the battle speed
function Net.Pre(B, ev)
	if not B.Fighter or B.ended then
		return
	end
	local me = myUserId()
	local t = ev.type
	local now = os.clock()
	if t == EV.Order then
		if ev.owner ~= me then
			return
		end
		local action = tostring(ev.order or "")
		if ev.rejected ~= nil then
			St.rejected = (St.rejected or 0) + 1
			if action == "Special" then
				Atk.Shatter(B) -- (Task 11b) the predicted charge breaks
			end
			local p = B.pending[action]
			if p then
				Input.Revert(B, action, true)
			elseif action ~= "Attack" and action ~= "Target" then
				Hud.Shake(Hud.ButtonOf(action, tonumber(ev.target)))
			end
		elseif action == "Target" or (action == "Attack" and tonumber(ev.target)) then
			-- the lock echo ("Attack"(id) / "Attack"() lock the enemy the pet now attacks)
			B.lock = tonumber(ev.target)
			B.pending[action] = nil
			Hud.enemyDirty = true
		end
	elseif t == EV.Element or t == EV.Dash then
		if t == EV.Dash and B.fighterId and tonumber(ev.unit) == B.fighterId then
			local f = B.units[B.fighterId]
			if f then
				Me.StartDash(B, f, ev) -- my pet's dash shows on arrival (the render clock would add its delay)
			end
		end
		if B.fighterId and tonumber(ev.unit) == B.fighterId then
			local kind = (t == EV.Element) and "Element" or "Dash"
			if not Input.Confirm(B, kind) then
				B.cd[kind] = now + (B.cdLen[kind] or 1)
			end
			Hud.ringAt = 0
		end
	elseif t == (EV.Cheer or "Cheer") then
		if tonumber(ev.owner) == me then
			if not Input.Confirm(B, "Cheer") then
				B.cd.Cheer = now + (B.cdLen.Cheer or 20)
			end
			local F = BattleCatalog and BattleCatalog.Fighter or {}
			B.cheerUntil = now + num(F.CheerSeconds, 5)
			Hud.ringAt = 0
		end
	elseif t == EV.Buff then
		if ev.owner == me then
			local h = B.units[tonumber(ev.unit) or -1]
			local slot = h and h.slot
			if slot and not Input.Confirm(B, "Buff", slot) then
				B.cd.Buff[slot] = now + (B.cdLen.Buff[slot] or 15)
			end
			Hud.ringAt = 0
		end
	elseif t == EV.Swap then
		if ev.owner == me then
			local predicted = Input.Confirm(B, "Swap")
			if not predicted and not ev.auto then
				B.cd.Swap = now + (B.cdLen.Swap or 10)
			end
			-- (fix round 2, I2-b) a held auto-swap (its KO waits for a late impact) trades the pets when it plays
			if not ev.fxSwitchLate then
				Me.Switch(B, ev)
			end
		end
	elseif t == EV.Hit then
		if B.fighterId and tonumber(ev.from) == B.fighterId and not ev.special and not ev.element and not ev.zone then
			Input.Confirm(B, "Attack")
		end
	elseif t == EV.Special then
		if B.fighterId and tonumber(ev.unit) == B.fighterId then
			Input.Confirm(B, "Special")
		end
	elseif t == EV.Speed then
		if ev.owner == me and tonumber(ev.walk) then
			B.speed = { Walk = tonumber(ev.walk), Run = tonumber(ev.run) }
			local mc = Hud.Movement()
			if mc and St.movementOn then
				pcall(mc.SetBattleSpeed, B.speed.Walk, B.speed.Run)
			end
		end
	end
end

function Net.Snapshot(payload, battleId)
	local B = St.battle
	if not B or type(payload) ~= "table" then
		return
	end
	local id = payload.BattleId or battleId
	if id ~= nil and id ~= B.Id then
		return
	end
	local T = num(payload.T, nil)
	if not T then
		return
	end
	local snaps = B.snaps
	local stale = #snaps > 0 and T <= snaps[#snaps].T
	if stale and payload.Units ~= nil then
		return -- out of order / duplicate (the old full form)
	end
	local units = payload.Units
	if type(units) ~= "table" then
		-- the wire form: only what changed since the last snapshot; the rest of the picture is carried forward
		if type(payload.U) ~= "table" or not BattleSim or type(BattleSim.DecodeSnapshot) ~= "function" then
			return
		end
		-- every delta is decoded, even one with no newer T (the server's baseline already counts it as sent)
		units = BattleSim.DecodeSnapshot(payload, B.lastUnits)
		B.lastUnits = units
		if stale then
			if T == snaps[#snaps].T then
				snaps[#snaps].Units = units
			end
			return
		end
	end
	snaps[#snaps + 1] = { T = T, Units = units }
	while #snaps > K.MAX_SNAPS do
		table.remove(snaps, 1)
	end
	local now = os.clock()
	local offset = T - now
	if not B.haveOffset then
		B.haveOffset = true
		B.offset = offset
	else
		-- follow slowly, but never let the render clock run ahead of what arrived
		B.offset = B.offset + (offset - B.offset) * K.OFFSET_RATE
		if offset < B.offset then
			B.offset = offset
		end
	end
end

-- the unit an event lands on (the ranged-shot hold): a Hit's victim, a KO'd unit
local function heldUnitOf(ev)
	if ev.type == EV.Hit then
		return tonumber(ev.to)
	elseif ev.type == EV.KO then
		return tonumber(ev.unit)
	elseif ev.type == (EV.Swap or "Swap") and ev.auto then
		return tonumber(ev.out) -- (fix round 1, I2) the auto-swap of a fighter KO'd by a shot still flying waits with its KO
	end
	return nil
end

-- seconds `ev` (due at t) waits for a ranged shot still flying at its unit (B.fxHold: when the shot lands), <=
-- FX_LATE_MAX; the End waits for every shot (the killing blow lands first)
function Net.Hold(B, ev, t)
	local holds = B.fxHold
	if not holds then
		return 0
	end
	local h = nil
	if ev.type == EV.End then
		for _, v in pairs(holds) do
			if not h or v > h then
				h = v
			end
		end
	else
		local id = heldUnitOf(ev)
		h = id and holds[id]
	end
	if not h or h <= t then
		return 0
	end
	return min(h - t, K.FX_LATE_MAX)
end

-- (Task 11b) the drawn HP / state of unit `id` wait until `untilClock` (os.clock): Units.Update never draws its HP
-- under `floor` (the HP drawn now; a caster's last gasp: 1) nor the unit down before then. A KO / the held hit itself
-- ends it when it plays (Units.Unhold)
function Units.Hold(B, id, untilClock, floor)
	local u = id and B.units[id]
	-- (fix round 2, M2') a unit already held may be drawn at 0 (a plain hit took its floor there): its hold still extends
	if not u or (not u.holdUntil and (u.state == S_DOWN or num(u.hp, 0) <= 0)) then
		return
	end
	if not u.holdUntil or u.holdUntil < untilClock then
		u.holdUntil = untilClock
	end
	local f = floor or u.hp
	u.holdHp = u.holdHp and max(u.holdHp, f) or f
	u.holdState = u.state
	if floor then
		u.holdFloor = max(u.holdFloor or 0, floor) -- (fix round 1) the hits that play during the hold never draw it lower
	end
end

function Units.Unhold(u)
	u.holdUntil, u.holdHp, u.holdState, u.holdFloor = nil, nil, nil, nil
end

-- (Task 11b) seconds `ev` (due at t on the render clock, `lead` s from now) waits for a late Special's impact
-- (B.spHold[caster] = { at, kind, victims }: Net.SpecialArrived): that special's own hits (Hit.special from the caster)
-- and its Storm's zone ticks (Hit.zone + kind) due before the impact, the KO of a unit they hit and the caster's own
-- KO in its late charge (+ LAST_GASP: the effect lands first). Their units' drawn HP waits too (Units.Hold). Other hits
-- on the same units (a plain attack, another unit's) play on time. The End does not wait: its grace (FX_END_GRACE
-- 1 s > LATE_MAX) lets the effect land and the held events drain on the render clock (Net.End, B.drainHeld)
function Net.SpecialHold(B, ev, t, lead)
	local holds = B.spHold
	if not holds then
		return 0
	end
	local now = os.clock()
	local w = 0
	if ev.type == EV.Hit then
		local h = holds[tonumber(ev.from) or -1]
		local v = tonumber(ev.to)
		if h and v and h.at > t and (ev.special ~= nil or (ev.zone and tostring(ev.kind or "") == h.kind)) then
			w = h.at - t
			h.victims[v] = true
			Units.Hold(B, v, now + lead + w)
		end
	elseif ev.type == EV.KO then
		local id = tonumber(ev.unit) or -1
		local own = holds[id]
		local gasp = own ~= nil and own.at > t
		if gasp then
			w = own.at - t + K.LAST_GASP
		end
		for _, h in pairs(holds) do
			if h.victims[id] and h.at > t then
				w = max(w, h.at - t)
			end
		end
		if w > 0 then
			-- (fix round 1, M1) one hold: a last gasp floors the drawn HP at 1 (the killing hit's drop shows)
			Units.Hold(B, id, now + lead + w, gasp and 1 or nil)
		end
	elseif ev.type == (EV.Swap or "Swap") and ev.auto then
		-- (fix round 1, I2) the server's auto-swap of a fighter whose KO waits for a late impact: the "GO!" and the
		-- entrance wait with it (the KO before it in this batch set the out unit's hold)
		local o = B.units[tonumber(ev.out) or -1]
		if o and o.holdUntil then
			w = max(0, o.holdUntil - now - lead)
		end
	end
	if w > 0 then
		ev.fxSpHeld = true
	end
	return min(w, K.LATE_MAX + K.LAST_GASP)
end

-- (Task 11b) a Special that lands late (ev.fxSpLate, Atk.Special): its hold, until the impact on the render clock
function Net.SpecialArrived(B, ev, t)
	local late = ev.type == EV.Special and tonumber(ev.fxSpLate) or nil
	if not late or late <= 0 then
		return
	end
	local holds = B.spHold or {}
	B.spHold = holds
	for id, h in pairs(holds) do
		if h.at < t - 2 then
			holds[id] = nil -- (long past)
		end
	end
	local id = tonumber(ev.unit)
	if id then
		holds[id] = { at = t + late, kind = tostring(ev.kind or ""), victims = {} }
	end
end

-- queue `ev` to play at `due` (in time order: a held event lets the others pass); a Hit whose shot lands late
-- (ev.fxLate, Atk.Hit) holds its victim's next events until then
function Net.Queue(B, ev, due, held)
	local q = B.evq
	local i = #q
	while i > 0 and q[i].t > due do
		i = i - 1
	end
	table.insert(q, i + 1, { t = due, ev = ev, held = held == true })
	if (tonumber(ev.fxLate) or 0) > 0 then
		local id = heldUnitOf(ev)
		if id then
			B.fxHold = B.fxHold or {}
			if (B.fxHold[id] or -math.huge) < due then
				B.fxHold[id] = due
			end
		end
	end
end

function Net.Events(list, battleId)
	local B = St.battle
	if not B or type(list) ~= "table" then
		return
	end
	if battleId ~= nil and battleId ~= B.Id then
		return
	end
	-- played on the delayed render clock: stamp them with the estimated server time of their arrival
	local t = B.haveOffset and (os.clock() + B.offset) or B.renderT
	-- the pet attack VFX start NOW, their impact due when the event plays (t - renderT from now: the render delay)
	local lead = B.haveOffset and clamp(t - B.renderT, 0, K.FX_LEAD_MAX) or 0
	for _, ev in ipairs(list) do
		if type(ev) == "table" and type(ev.type) == "string" then
			-- a victim whose ranged shot is still flying (Net.Hold): its Hit / KO wait for the shot to land
			-- (Task 11b) ... or a late Special's impact: its own hits, the KOs they cause, a last gasp, the End
			local hold = max(Net.Hold(B, ev, t), Net.SpecialHold(B, ev, t, lead))
			if hold > 0 and ev.type == (EV.Swap or "Swap") and ev.auto then
				-- (fix round 2, I2-b) the held auto-swap trades the pets when it plays, not now: my fighter switch waits
				-- (Net.Pre / the Swap handler), the incoming pet stays benched (another player's: parked) till then
				ev.fxSwitchLate = true
				local inc = B.units[tonumber(ev["in"]) or -1]
				if inc then
					inc.unbenchAt = os.clock() + lead + hold + K.UNBENCH_SLACK
					if inc.mine then
						Units.Rebuild(B, inc) -- (my new fighter's High model is built while it waits: its GO! lands on it)
					end
				end
			end
			local okPre, errPre = pcall(Net.Pre, B, ev)
			if not okPre then
				warnOnce("pre_" .. ev.type, "event " .. ev.type .. " (HUD) failed: " .. tostring(errPre))
			end
			Atk.Arrive(B, ev, lead + hold)
			Net.SpecialArrived(B, ev, t)
			-- telegraphs start at once (their fill must complete at the hit), the rest on the render clock
			if ev.type == EV.Telegraph then
				local fn = Handlers[ev.type]
				pcall(fn, B, ev)
			else
				local late = tonumber(ev.fxLate) or 0
				Net.Queue(B, ev, t + hold + late, hold > 0 or late > 0)
			end
		end
	end
end

-- the winners cheer: AttackFx's Victory (hop-spin + sparkles), else the old hop; a little apart (0-0.4 s). During the
-- End grace (Ruling 11: no new effect) the cheers wait for it in St.cheers (Atk.Update plays them)
function Net.Cheer(B)
	local now = os.clock()
	for _, u in ipairs(B.list) do
		if u.ally and u.root and not u.parked and not Atk.Lying(u) then
			local delay = math.random() * 0.4
			if not Atk.Mod() then
				u.hopAt = now + delay
			elseif St.fxEndAt then
				St.cheers = St.cheers or {}
				St.cheers[#St.cheers + 1] = { B = B, u = u, at = St.fxEndAt + delay }
			elseif not Atk.Victory(B, u, delay) then
				u.hopAt = now + delay
			end
		end
	end
end

function Net.End(payload, battleId)
	local B = St.battle
	if type(payload) ~= "table" then
		return
	end
	local id = payload.BattleId or battleId
	if not B and St.ringLast and St.ringLast.Id == id and Ring.IsFinal(payload) then
		Hud.ShowResult(St.ringLast, payload) -- the run's card after the last round's floor was already freed
		St.ringLast = nil
		return
	end
	if not B or (id ~= nil and id ~= B.Id) then
		return
	end
	if B.ended then
		if B.ringNext and Ring.IsFinal(payload) then
			Ring.FinalAfterWin(B, payload) -- the run ended between two rounds (Forfeit, a leave, a shutdown...)
		end
		return
	end
	-- play what is still queued, so the last KO shows. Events held for a ranged shot still in flight (Net.Queue
	-- `held`: its Hit, the victim's KO, the sim's End) keep their time: stepBattle drains them on the render clock
	-- during the End grace, so the killing shot's number and "KO!" pop when it LANDS (Task 8 fix round 3, review
	-- Important 3); the rest play now, like before
	local latest = B.snaps[#B.snaps]
	if Net.PlayUnheld(B) then
		B.drainHeld = true
	else
		B.renderT = max(B.renderT, (latest and latest.T or B.renderT)) + 5
		Net.PlayDue(B, os.clock())
	end
	B.ended = true
	B.endAt = os.clock()
	Atk.EndSoon(B) -- (when the sim's End event has not played: the grace starts now, the cheers wait for it)
	Input.Bind(false)
	Input.Movement(B, false)
	B.pending = {}
	local participant = payload.Spectator ~= true and B.Fighter
	local ringNext = participant and Ring.IsNext(B, payload)
	if not ringNext then
		Net.Music() -- (first: an error in the cards / result below cannot leave the Battle music on; a won ring round sets it at the tail)
	end
	Cards.AfterFight(B, payload)
	local rw = type(payload.Rewards) == "table" and payload.Rewards or nil
	if participant and B.Mode == "Dungeon" and (payload.Outcome == "Win" or payload.Won == true or (rw and rw.Dungeon == true and payload.Reason == "Cleared")) then
		-- a cleared dungeon room: no result card (DungeonController shows the loot); the floor goes after DUNGEON_LINGER
		-- (bug #26: then the followers take over, PetController.HANDOVER)
		B.linger = K.DUNGEON_LINGER
		Hud.SetVisible(false)
		Net.Cheer(B)
	elseif ringNext then
		-- a won Champion Ring round: the side card "Round 8 won! ... Round 9 in 3", the floor stays until the next Start
		B.linger = Ring.LINGER
		Ring.ShowNext(B, payload)
		Net.Cheer(B)
	elseif participant then
		B.linger = K.END_LINGER
		Hud.ShowResult(B, payload)
		-- winners cheer (and hear their payout)
		if payload.Outcome == "Win" or payload.Won then
			Net.Cheer(B)
			Net.RewardSound()
		end
	else
		B.linger = (payload.Reason == "OutOfRange") and 0 or K.SPECTATOR_LINGER
		Hud.SetVisible(false)
	end
	Net.Music() -- (the fight is over: back to the Dungeon / Lobby track; a won ring round keeps the beat)
	if B.linger <= 0 then
		Net.Cleanup(B, false)
	end
end

function BattleController.HandleState(kind, payload, battleId)
	if kind == "Start" then
		Net.Start(payload, battleId)
	elseif kind == "Snapshot" then
		Net.Snapshot(payload, battleId)
	elseif kind == "Events" then
		Net.Events(payload, battleId)
	elseif kind == "End" then
		Net.End(payload, battleId)
	end
end

----------------------------------------------------------------------
-- Frame loop
----------------------------------------------------------------------
local function sampleSnaps(B)
	local snaps = B.snaps
	local n = #snaps
	if n == 0 then
		return nil, nil, 0
	end
	local t = B.renderT
	if t <= snaps[1].T then
		return snaps[1], nil, 0
	end
	for i = n - 1, 1, -1 do
		local a = snaps[i]
		if a.T <= t then
			local b = snaps[i + 1]
			local span = b.T - a.T
			local alpha = span > 0 and clamp((t - a.T) / span, 0, 1) or 1
			return a, b, alpha
		end
	end
	return snaps[n], nil, 0
end

-- per-section cost (only while a test injects BattleController.PerfClock)
local function section(name, t0)
	local clock = BattleController.PerfClock
	if not clock then
		return nil
	end
	local t = clock()
	if t0 then
		local split = St.perf.split
		split[name] = (split[name] or 0) + (t - t0) * 1000
	end
	return t
end

local function stepBattle(B, now, dt)
	local s0 = section()
	if not B.ended then
		if B.haveOffset then
			local latest = B.snaps[#B.snaps]
			local t = now + B.offset - interpDelay(B)
			if latest and t > latest.T + 0.15 then
				t = latest.T + 0.15
			end
			if t > B.renderT then
				B.renderT = t
			end
		end
		Net.PlayDue(B, now)
	elseif B.drainHeld then
		-- the End came with events held for a flying shot (Net.End): they play on the render clock as it lands; at
		-- the latest after the End grace everything left plays and the clock jumps to the end like before
		B.renderT = B.renderT + dt
		if #B.evq == 0 or now - (B.endAt or now) >= K.FX_END_GRACE then
			local latest = B.snaps[#B.snaps]
			B.renderT = max(B.renderT, (latest and latest.T or B.renderT)) + 5
			B.drainHeld = nil
		end
		Net.PlayDue(B, now)
	end
	local sa, sb, alpha = sampleSnaps(B)
	s0 = section("Events", s0)
	Units.BuildPending(B)
	s0 = section("Builds", s0)
	local crowded = #B.list > K.CROWD
	local frameNo = St.frameNo
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position
	for i, u in ipairs(B.list) do
		local animate = true
		if not u.mine and not u.isBoss then
			local stride = crowded and 2 or 1
			if camPos and u.root and not u.parked then
				local p = u.root.Position
				local dx, dy, dz = p.X - camPos.X, p.Y - camPos.Y, p.Z - camPos.Z
				local d2 = dx * dx + dy * dy + dz * dz
				if d2 > K.ANIM_FAR * K.ANIM_FAR then
					stride = 4
				elseif d2 > K.ANIM_MID * K.ANIM_MID then
					stride = 3
				end
			end
			-- a pet that only breathes (the battle idle) is posed every other frame: the idle is slow
			if stride < 2 and u.poseSrc == "idle" then
				stride = 2
			end
			-- a strided frame skips only the pose (PetBuilder.Animate); the root moves every frame and carries the
			-- animated parts rigidly (Units.CarryLoose), so the pet never stutters and never comes apart
			animate = (not u.posed) or ((frameNo + i) % stride) == 0
		end
		local ok, err = pcall(updateUnit, B, u, now, dt, sa, sb, alpha, animate)
		if not ok then
			warnOnce("unit", "unit update failed: " .. tostring(err))
		end
	end
	s0 = section("Units", s0)
	Tele.Update(B, now)
	Units.UpdateFocus(B, now)
	B.cue = B.threat and "Dash" or nil
	Input.Tick(B, now)
	s0 = section("Telegraphs", s0)
	if Hud.gui then
		local ok, err = pcall(Hud.Update, B, now)
		if not ok then
			warnOnce("hud", "HUD update failed: " .. tostring(err))
		end
	end
	section("Hud", s0)
end

-- the enemy my pet attacks: the lock (ATTACK / click / Tab), else the target my fighter auto-attacks (its snapshot
-- target, dungeon fixes decision 4); nil when none is drawn
function Units.FocusUnit(B)
	local u = B.lock and B.units[B.lock]
	local auto = false
	if not u and B.Fighter then
		local f = B.fighterId and B.units[B.fighterId]
		local t = f and f.target and B.units[f.target]
		if t and not t.ally then
			u, auto = t, true
		end
	end
	if not u or not u.model or u.parked or u.hidden or u.hp <= 0 or u.state == S_DOWN then
		return nil, false
	end
	return u, auto
end

-- a bobbing voxel arrow over the enemy my pet attacks (solid = picked, see-through = the one it chose by itself)
function Units.UpdateFocus(B, now)
	local u, auto = Units.FocusUnit(B)
	local mark = B.focusMark
	if not u or B.ended then
		if mark then
			mark.Parent = nil
		end
		return
	end
	if not mark then
		mark = make("Model", { Name = "FocusArrow" })
		local spec = { { 0, 0, 0.9 }, { 0, 0.7, 0.6 }, { 0, 1.3, 0.35 } }
		-- Phase 6: the Blender arrow (fx_arrow, 1 stud wide, pointing down) when ready: 1.4 studs wide like the Part
		-- arrow's top; each MeshPart's Y attribute keeps its manifest height under the same per-frame code
		local mesh = Units.FxMesh("fx_arrow", 1.4)
		if mesh then
			spec = {}
			for _, mp in ipairs(mesh) do
				mp:SetAttribute("Y", -mp.Position.Y / 0.8)
				mp.Parent = mark
			end
		end
		for i, s in ipairs(spec) do
			make("Part", {
				Name = "Arrow" .. i,
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Material = Enum.Material.Neon,
				Color = COLORS.Gold,
				Size = Vector3.new(s[3] * 1.4, 0.5, s[3] * 1.4),
			}, mark):SetAttribute("Y", s[2])
		end
		B.focusMark = mark
	end
	if mark.Parent ~= B.folder then
		mark.Parent = B.folder
	end
	if (B.focusAuto == true) ~= auto then
		B.focusAuto = auto
		for _, p in ipairs(mark:GetChildren()) do
			if p:IsA("BasePart") then
				p.Transparency = auto and 0.4 or 0
			end
		end
	end
	B.focusId = u.id
	local top = u.isBoss and (u.height or 20) + 2 or (u.centerY or 1.5) + (u.height or 3) / 2 + 2.4
	local base = worldPoint(B, u.x, top + sin(now * 4) * 0.35, u.z)
	local spin = now * 2
	for _, p in ipairs(mark:GetChildren()) do
		p.CFrame = CFrame.new(base.X, base.Y - (p:GetAttribute("Y") or 0) * 0.8, base.Z) * CFrame.Angles(0, spin, 0)
	end
end

local function onFrame(dt)
	St.frameNo = St.frameNo + 1 -- (first: a frame that fails before Atk.Update shows in StepsAttackFx, fix round 2 M8)
	local perfClock = BattleController.PerfClock or os.clock
	local p0 = perfClock()
	local t0 = os.clock()
	local now = t0
	local B = St.battle
	if B then
		stepBattle(B, now, dt)
		if B.ended and now - (B.endAt or now) >= (B.linger or 0) then
			Net.Cleanup(B, false)
		end
	end
	local f0 = section()
	Fx.Update(now)
	Fx.UpdateNumbers(now)
	Fx.UpdateFlashes(now)
	Atk.Update(now) -- the pet attack VFX and poses (AttackFx has no frame loop of its own)
	local screenFx = Me.UpdateScreenFx(now)
	Hud.UpdateResult(now)
	Ring.UpdateNext(now)
	Me.UpdateShake(now)
	section("Effects", f0)
	local ms = (perfClock() - p0) * 1000
	local perf = St.perf
	perf.frames = perf.frames + 1
	perf.total = perf.total + ms
	perf.last = ms
	if ms > perf.peak then
		perf.peak = ms
	end
	-- the loop sleeps when nothing is drawn
	if not St.battle and #St.effects == 0 and #St.numbers == 0 and #St.flashes == 0 and not St.result and not St.next and not St.shake
		and not screenFx and not Atk.Pending() then
		if St.loop then
			St.loop:Disconnect()
			St.loop = nil
		end
	end
end

function BattleController._wake()
	if St.loop or not St.initialized then
		return
	end
	St.loop = RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(onFrame, dt)
		if not ok then
			warnOnce("frame", "frame failed: " .. tostring(err))
		end
	end)
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
function BattleController.GetBattle()
	local B = St.battle
	if not B then
		return nil
	end
	local models = 0
	for _, u in ipairs(B.list) do
		if u.model then
			models = models + 1
		end
	end
	return {
		Id = B.Id,
		Mode = B.Mode,
		Side = B.Side,
		Spectator = B.Spectator,
		Fighter = B.Fighter,
		Ended = B.ended,
		Units = #B.list,
		Models = models,
		Focus = B.lock,
		Lock = B.lock,
		FighterId = B.fighterId,
		Lives = B.lives,
		Speed = B.speed and { Walk = B.speed.Walk, Run = B.speed.Run } or nil,
		Dungeon = B.Dungeon,
		Wave = B.wave,
		MenuHidden = Hud.menuHidden == true,
		Cooldowns = (function()
			local now = os.clock()
			local out = { Buff = {} }
			for _, kind in ipairs({ "Element", "Dash", "Swap", "Cheer" }) do
				out[kind] = max(0, (B.cd[kind] or 0) - now)
			end
			for slot, t in pairs(B.cd.Buff) do
				out.Buff[slot] = max(0, t - now)
			end
			return out
		end)(),
		Cheering = os.clock() < (B.cheerUntil or 0),
		Pending = (function()
			local out = {}
			for k in pairs(B.pending) do
				out[k] = true
			end
			return out
		end)(),
		Hud = BattleController.IsHudVisible(),
		Layout = (Hud.m and Hud.m.Compact) and "Compact" or "Wide",
		RenderT = B.renderT,
		Telegraphs = (function()
			local n = 0
			for _ in pairs(B.teles) do
				n = n + 1
			end
			return n
		end)(),
		Threat = B.threat == true,
		Cue = B.cue,
		-- Phase 4: the ring round / record, the won round waiting for the next Start, duel overtime
		Round = B.Round > 0 and B.Round or nil,
		Best = B.Ring and num(B.Ring.Best, 0) or nil,
		Next = B.ringNext and B.ringNext.Next or nil,
		InterpDelay = interpDelay(B),
		TeamPlace = Hud.teamPlace,
	}
end

-- the drawn telegraphs (tests): { { Id, Shape, At, From, SafeAt, Late } ... } on the render clock
function BattleController.GetTelegraphs()
	local B = St.battle
	local out = {}
	for id, tl in pairs(B and B.teles or {}) do
		out[#out + 1] = { Id = id, Shape = tl.shape, At = tl.at, From = tl.from, SafeAt = tl.safeAt, Late = tl.late == true }
	end
	return out
end

function BattleController.GetUnit(id)
	local B = St.battle
	local u = B and B.units[id]
	if not u then
		return nil
	end
	return {
		Id = u.id, Side = u.side, Kind = u.kind, Name = u.name, Hp = u.hp, MaxHp = u.maxHp, State = u.state, Meter = u.meter,
		Model = u.model, X = u.x, Z = u.z, Parked = u.parked == true, Mine = u.mine, Ally = u.ally,
		World = u.model and unitCenter(B, u) or nil,
		-- Phase 4: the unit's PetCard ({ Gui, Mode }), level, evolution stage, XP, the ring champion's crown
		Card = u.card and { Gui = u.card.Gui, Mode = u.card.mode } or nil,
		Level = u.level, Evo = u.evo, Xp = u.xp, XpNext = u.xpNext, Crowned = u.crowned,
		Writes = u.cardWrites or 0,
		-- Phase 5: the bench, the wind-up, the drawn root position (my fighter / helpers), the team's lives, detail
		Benched = u.benched == true, Windup = u.windup == true, Lives = u.lives, Detail = u.detail,
		Drawn = u.root and u.root.Position or nil, FlyAt = u.flyAt, SwapAt = u.swapAt,
		-- dungeon fixes: arriving (the model hidden until the flash), the drawn pet dash, the wild look
		Arriving = u.arrive ~= nil, Hidden = u.hidden == true, ArriveFx = u.arriveFx ~= nil, DashAt = u.dashAt,
		Wild = u.info.wild == true,
		-- pet attack VFX: the battle pose drawn last frame (PetPoses name; nil = none)
		Pose = u.poseShown, PoseP = u.poseShownP,
	}
end

-- wave 5 (bug #26): where the player's dungeon fighter is (still drawn) or was last drawn (<= LAST_DRAWN_AGE s ago)
-- -> Vector3, key | nil (PetController's hand-over: the follower walks back from there)
function BattleController.LastDrawn(userId)
	userId = tonumber(userId)
	if not userId then
		return nil
	end
	local B = St.battle
	if B and B.Mode == "Dungeon" then
		local u = Me.FighterOf(B, userId)
		local pos = u and Me.SpotOf(u)
		if typeof(pos) == "Vector3" then
			return pos, u.info and u.info.key
		end
	end
	local e = St.lastDrawn[userId]
	if e and os.clock() - e.At <= K.LAST_DRAWN_AGE then
		return e.Pos, e.Key
	end
	St.lastDrawn[userId] = nil
	return nil
end

-- wave 5 polish: is the player's dungeon fighter still drawn on the floor (a lost room's KO'd models linger END_LINGER)?
-- PetController keeps the followers parked while it is (never two copies of the team on screen)
function BattleController.FighterDrawn(userId)
	userId = tonumber(userId)
	local B = St.battle
	if not userId or not B or B.Mode ~= "Dungeon" then
		return false
	end
	local u = Me.FighterOf(B, userId)
	return u ~= nil and u.model ~= nil and u.model.Parent ~= nil
end

function BattleController.LastDrawnKey(userId)
	local _, key = BattleController.LastDrawn(userId)
	return key
end

function BattleController.GetStats()
	local perf = St.perf
	local B = St.battle
	local models = 0
	if B then
		for _, u in ipairs(B.list) do
			if u.model then
				models = models + 1
			end
		end
	end
	local teles = 0
	if B then
		for _ in pairs(B.teles) do
			teles = teles + 1
		end
	end
	return {
		Frames = perf.frames,
		AvgMs = perf.frames > 0 and perf.total / perf.frames or 0,
		PeakMs = perf.peak,
		LastMs = perf.last,
		Units = B and #B.list or 0,
		Models = models,
		FxParts = St.fxLive,
		Effects = #St.effects,
		Numbers = #St.numbers,
		Flashes = #St.flashes,
		Telegraphs = teles,
		Builds = perf.builds,
		Bound = St.bound,
		HpWrites = Hud.hpWrites or 0,
		RingWrites = St.ringWrites or 0,
		Shakes = Hud.shakes or 0,
		CameraShakes = St.shakeCount or 0,
		Sent = St.sent or 0,
		Rejected = St.rejected or 0,
		Timeouts = St.timeouts or 0,
		Dashes = St.dashes or 0, -- pet dashes drawn (Dash events)
		Arrivals = St.arrivals or 0, -- arrival effects started (EvolutionFx.Arrive)
		AttackFx = Atk.Stats(), -- AttackFx.Stats() (nil before the first battle loads it)
		Focus = (function()
			local b = St.battle
			local u, auto = nil, false
			if b then
				u, auto = Units.FocusUnit(b)
			end
			return u and { Id = u.id, Auto = auto } or nil
		end)(),
		Split = (function()
			local out = {}
			for k, v in pairs(perf.split or {}) do
				out[k] = perf.frames > 0 and v / perf.frames or 0
			end
			return out
		end)(),
	}
end

function BattleController.ResetStats()
	St.perf = { frames = 0, total = 0, peak = 0, last = 0, builds = 0, split = {} }
end

function BattleController.IsHudVisible()
	return Hud.gui ~= nil and Hud.gui.Parent ~= nil and ((Hud.team and Hud.team.Visible) or (Hud.cmd and Hud.cmd.Visible) or (Hud.result and Hud.result.Visible)) == true
end

function BattleController.Stop()
	if St.battle then
		Net.Cleanup(St.battle, true)
	end
	Fx.ClearAll()
	Atk.ClearAll()
	if St.screenFx then
		pcall(St.screenFx.gui.Destroy, St.screenFx.gui)
		St.screenFx = nil
	end
	Input.Bind(false)
	Input.Movement(nil, false)
	St.shake = nil
	if Mods.Cheer then
		pcall(Mods.Cheer.StopLoop)
	end
	for _, c in ipairs(St.conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	St.conns = {}
	if St.loop then
		St.loop:Disconnect()
		St.loop = nil
	end
	Hud.SetMenuHidden(false)
	Me.MouseHold("BattleResult", false)
	Me.MouseHold("BattleLeave", false)
	St.prompts = {}
	if Hud.gui then
		Hud.gui:Destroy()
	end
	Hud.gui = nil
	Hud.rows = {}
	Hud.helpers = {}
	Hud.buttons = {}
	Hud.more = nil
	Hud.next = nil
	Hud.info = nil
	Hud.leave = nil
	Hud.cheer = nil
	CheerUp.placed = nil
	Leave.buttons = {}
	St.result = nil
	St.next = nil
	St.ringLast = nil
	for _, p in ipairs(St.pool) do
		pcall(p.Destroy, p)
	end
	St.pool = {}
	St.fxLive = 0
	if St.folder then
		pcall(St.folder.Destroy, St.folder)
		St.folder = nil
		St.fxFolder = nil
	end
	St.initialized = false
end

function BattleController.Init()
	if St.initialized then
		return
	end
	St.initialized = true
	local conns = St.conns
	conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, processed)
		local ok, err = pcall(Input.OnBegan, input, processed)
		if not ok then
			warnOnce("input", err)
		end
	end)
	conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
		local ok, err = pcall(Input.OnEnded, input)
		if not ok then
			warnOnce("input2", err)
		end
	end)
	local okGp, gpConn = pcall(function()
		return UserInputService.LastInputTypeChanged:Connect(function(t)
			local gp = t == Enum.UserInputType.Gamepad1 or t == Enum.UserInputType.Gamepad2
			if gp ~= St.gamepad then
				St.gamepad = gp
				pcall(Hud.Keys)
			end
		end)
	end)
	if okGp and gpConn then
		conns[#conns + 1] = gpConn
	end
	-- the prompts shown to me: E presses them, not ELEMENT (Input.PromptShown)
	pcall(function()
		local pps = game:GetService("ProximityPromptService")
		conns[#conns + 1] = pps.PromptShown:Connect(function(prompt)
			St.prompts[prompt] = true
		end)
		conns[#conns + 1] = pps.PromptHidden:Connect(function(prompt)
			St.prompts[prompt] = nil
		end)
	end)
	-- own pets' level / XP from the profile mirror (after a fight's rewards land: the cards follow)
	local okS, sConn = pcall(function()
		return Mods.State and Mods.State.Changed and Mods.State.Changed:Connect(function()
			if St.battle then
				pcall(Cards.FromState, St.battle)
			end
		end)
	end)
	if okS and sConn then
		conns[#conns + 1] = sConn
	end
	-- the Graphics setting drives AttackFx's quality (like PetFx: ClientSettings.Changed "Gfx", then
	-- GraphicsQuality.Effective() once GraphicsQuality has applied it)
	local okG, gConn = pcall(function()
		if Mods.Settings == nil then
			Mods.Settings = optional(Client, "ClientSettings") or false
		end
		local cs = Mods.Settings
		return cs and cs.Changed and cs.Changed:Connect(function(key)
			if key == "Gfx" then
				task.defer(Atk.SyncQuality)
			end
		end)
	end)
	if okG and gConn then
		conns[#conns + 1] = gConn
	end
	local cam = workspace.CurrentCamera
	if cam then
		conns[#conns + 1] = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if St.battle then
				pcall(Hud.Rebuild)
			end
			local r = St.result
			if r and r.battle and Hud.result and Hud.result.Visible then
				pcall(Hud.ShowResult, r.battle, r.payload) -- the card re-places itself (top right on a landscape phone)
			end
		end)
	end
	-- wave 6: the podium cheer loop follows the server's OnPodium attribute
	if LocalPlayer then
		local okP, pConn = pcall(function()
			return LocalPlayer:GetAttributeChangedSignal((Config.Attr and Config.Attr.OnPodium) or "OnPodium"):Connect(function()
				local ok, err = pcall(Cheer.SyncPodium)
				if not ok then
					warnOnce("podium", err)
				end
			end)
		end)
		if okP and pConn then
			conns[#conns + 1] = pConn
		end
		pcall(Cheer.SyncPodium)
	end
	-- the remote (BattleState may arrive a little after the controller starts)
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("Remotes", 30)
		local remote = folder and folder:WaitForChild("BattleState", 30)
		if not remote or not St.initialized then
			if St.initialized then
				warnOnce("remote", "BattleState remote not found: battles will not be drawn")
			end
			return
		end
		conns[#conns + 1] = remote.OnClientEvent:Connect(function(kind, payload, battleId)
			local ok, err = pcall(BattleController.HandleState, kind, payload, battleId)
			if not ok then
				warnOnce("state_" .. tostring(kind), "BattleState " .. tostring(kind) .. " failed: " .. tostring(err))
			end
		end)
		commandRemote()
	end)
end

BattleController._Units = Units -- TESTS ONLY (tools/smoke_p6_creatures.lua: the fx mesh slots)
BattleController._Me = Me -- TESTS ONLY (tools/smoke_p7vfx_client.lua: the Eclipse dim, Task 11)
BattleController._Fx = Fx -- TESTS ONLY (tools/smoke_p7vfx_client.lua: the Special pre-charge, Task 11b: numbers / flashes)

-- TESTS ONLY (Task 11b): the raw battle unit record (its drawn HP, hold, hurt time) and my predicted charge
function BattleController._Unit(id)
	local B = St.battle
	return B and B.units[id] or nil
end

function BattleController._Pre()
	return St.pre
end

-- TESTS ONLY (fix round 2, M5'): the inhale records by token
function BattleController._Inhales()
	return St.inhales
end

-- (Task 11) loads client/Controllers/AttackFx and points its Hooks at this controller (camera punch, edge glow, the
-- battle dim) outside a battle too: the /fx preview (DevPetShow) shows a signature's dim as a battle would. -> loaded
function BattleController.FxHooks()
	local m = Atk.Mod()
	Atk.Hook(m) -- (again: a hook someone cleared is pointed back here)
	return m ~= nil
end

-- (Task 11 fix round 1, M2) true while this controller's frame loop runs and steps AttackFx itself (Atk.Update): the
-- /fx preview (DevPetShow) then leaves its own AttackFx.Update out, so an effect is stepped once a frame (an Eclipse dim
-- in /fx wakes this loop through Me.Dim). The loop keeps running while any AttackFx effect lives (Atk.Pending).
-- (fix round 2, M8) and only while the loop really reaches Atk.Update: the last frame it ran (St.frameNo, counted first
-- thing in onFrame) is the frame Atk.Update stepped (St.fxFrame). A loop that fails earlier in its frame every frame
-- (pcall'd, one warning) stays connected but steps nothing: the caller then steps AttackFx itself. (Either order of the
-- two RenderStepped handlers in a frame: before onFrame both still hold the last frame's numbers, after it this one's)
function BattleController.StepsAttackFx()
	return St.loop ~= nil and Mods.AttackFx ~= nil and Mods.AttackFx ~= false and St.fxFrame == St.frameNo
end

-- TESTS ONLY (tools/smoke_dev.lua, M8): re-arm a once-only warning after a check that faults a frame on purpose
function BattleController._Unwarn(key)
	St.warned[key] = nil
end

return BattleController
