-- BattleService (Phase 3, battleservice): runs every pet battle on the server (ARCHITECTURE_V3.md "Phase 3: Pet
-- battles", "Phase 3 build contract" and its "Interfaces between the Phase 3 modules"). The server simulates, the
-- clients draw: every battle is a pure BattleSim stepped at a FIXED dt of 0.1 s (10 Hz, deterministic for its seed);
-- the participants and the spectators within range get compact BattleState messages; nothing here moves a part every
-- frame (Replication rule): characters are only placed when a battle starts / ends (teleports).
--
-- Contract API
--   BattleService.Init(deps)      deps = { DataService, PetService, PetCareService, TycoonService, ArenaBuilder,
--                                 ArenaInfo } (every dep optional; players already in the game are handled)
--   BattleService.StartTrial(player, level) -> ok, battleId | reason
--   BattleService.Challenge(a, b) -> ok, reason          a challenges b to a duel (b answers with ChallengeReply)
--   BattleService.StartRaid(bossId|nil) -> ok, raidId | reason       EventService: opens a Boss Raid on the arena floor
--   BattleService.EndRaid() -> ok                         EventService: ends it (a running fight ends as a timeout)
--   BattleService.GetRaidStatus() -> { Active, BossId, Name, Hp, MaxHp, Players, EndsIn, Enraged, Joinable, JoinEndsIn,
--                                 Waiting, BattleId } | nil                       (ArenaState.Raid)
--   BattleService.StartRing(player, startRound) -> ok, battleId | reason     Phase 4: the Champion Ring (see "Modes")
--   BattleService.KeysInBattle(player) -> { [key] = true }   the pet keys in the player's running battle or ring run
--                                 (PetCareService Feed / Train / Evolve, FusionService and GardenSet refuse them)
--   BattleService.GetBattle(player) -> { BattleId, Mode, Side, Level, BossId, Round (Ring), State, Zone = { CFrame,
--                                 Size } } | nil   (a ring run between two rounds reads State "Intermission")
--   BattleService.IsInBattle(player) -> bool
--   BattleService.BattleEnded     Util.Signal (exists at module load): Fire(battleId, result), once per battle,
--                                 AFTER the rewards were paid. result = { Mode, Winners = {userId...}, Losers =
--                                 {userId...}, Level (Trial), BossId (Raid), Round + Won (Ring), Damage = {[userId] =
--                                 n}, Forfeit = bool } plus the extras BattleId, Reason, Draw, WinnerSide, Duration,
--                                 Shares = {[userId] = 0..1}, Participants = {userId...} (everyone who ever joined),
--                                 Fighters = {userId...} (the participants still in at the end: raid leavers are
--                                 not), Rewards = {[userId] = rewards}, RewardsPaid = true, BossHp, BossMaxHp.
-- Extras: StartDuel(a, b) -> ok, battleId | reason, ReplyChallenge(player, fromUserId, accept) -> ok, reason,
--   Queue(player) / Unqueue(player) -> ok, reason, JoinRaid(player) / LeaveRaid(player) -> ok, reason,
--   Command(player, action, arg) -> ok, reason (what BattleCommand does), Forfeit(player) -> ok,
--   SetDoubleRewards(active, seconds|nil) (EventService may push the Double Rewards hour; it is also read from
--   EventService itself), IsDoubleRewards(), SetArena(arenaInfo, arenaBuilder), GetNetStats(), EstimateBytes(value),
--   ListBattles() -> { summary... }, signals BattleStarted(battleId, info) and RaidJoined(player, battleId),
--   flag BattleService.PayRaidRewards (default true: this service pays the raid tiers; see "Rewards"),
--   Shutdown() (what game:BindToClose runs; tests call it: every running battle ends void with Reason "Shutdown", new
--   battles are refused), SetClosing(bool) (tests: reopen after a Shutdown),
--   BattleService.Debug = nil | { FailEnd = n } (tests: the next n battle ends fail, to exercise the fail-safe that
--   frees the players, ring / pocket / raid, sends "End" and fires BattleEnded with Reason "Error" exactly once).
--
-- Modes
--   * Trial: BattleRequest("Trial", level) near Portal_Trials (ArenaInfo.TrialPortal, TRIAL_RANGE studs). Level 1 is
--     always open; level N needs level N-1 cleared (Battle.TrialCleared / TrialBest). The fight runs in a private
--     pocket (ArenaBuilder.BuildPocket(index), one free index per trial, FreePocket afterwards): the player is
--     teleported to the pocket's Spawn and, TRIAL_RETURN_DELAY seconds after the end, back to ArenaInfo.ReturnCFrame (in
--     front of the Trial Portal). One battle at a time per player; refused in an obby match (InMatch), while locked in
--     a portal party (PortalLocked), during another battle, without a team, while the profile loads (GetBattle nil).
--   * Duel: both players inside the Battle Arena (ArenaBuilder.InArena). "Challenge" (userId) -> an invite that expires
--     after CHALLENGE_TIMEOUT seconds -> "ChallengeReply" (userId, true) starts it (a challenge back to someone who
--     already challenged you accepts it). Or the quick "Queue": every second the queue pairs the two closest trophy
--     counts within an allowance that grows with the wait (QUEUE_GAP_BASE + QUEUE_GAP_PER_SECOND x seconds). The
--     duel runs on a free arena ring (ArenaInfo.Rings, the ring's zone): the challenger fights from side 1 (the ring's
--     -Z pad), the other from side 2 (+Z). Status: BattleState("Lobby", { Queue = { Queued, Waiting (players in the
--     queue), Seconds (my wait) }, Invites = { { FromUserId, FromName, Trophies, Power, ExpiresIn }... }, Sent =
--     { ToUserId, ToName, ExpiresIn } | nil }) to every player whose duel / queue status changed.
--   * Raid: EventService calls StartRaid(bossId); for BattleCatalog.Events.JoinWindowSeconds players inside the arena
--     may "JoinRaid" (the first joiner creates the BattleSim with the boss, later ones AddTeam: the boss HP grows per
--     participant, BattleCatalog.BossHp / GroupFactor); a joiner is placed on the floor's rim at their team's place.
--     "LeaveRaid" / leaving the arena / a disconnect removes the team (RemoveTeam: the boss sheds that share). The raid
--     ends when the sim ends (boss down, wipe, the boss's time limit, everybody left) or on EndRaid(); a raid nobody
--     joined closes at the end of the join window. ArenaState.Raid = GetRaidStatus().
--   * Ring (Phase 4, ARCHITECTURE_V3.md "Phase 4 build contract" 3.8 / 3.11 / 5.1-5.4; every helper lives in the
--     RingRun table): BattleRequest("Ring", startRound) near Portal_Ring (ArenaInfo.RingPortal, else the Portal_Ring
--     model, else the Trial Portal as the zero-part fallback; RING_RANGE studs) -> StartRing. The entry checks, in
--     this order with their toasts: a home claimed this session (TycoonService.GetPlot, "Claim your home first"), at
--     least one owned pet ("You need a pet"), the fighters (the active team with training pets skipped, else the
--     equipped keys, else the best owned pets by UnitPower, up to GetTeams().Slots), canBattle, within RING_RANGE of
--     the portal ("Walk to the Champion Ring portal"), the profile loaded and not provisional ("Your save is still
--     loading, try again in a moment"), the start round (1, or a boss round 10k with Ring.Best >= 10k). One RingRun per
--     player: { Id, Player, UserId, Name, Pocket, PocketIndex, Zone, Round, Start, Seed, Keys (fixed at the start; the
--     spec is rebuilt from them every round, so levels won meanwhile count), Wins, Cash, Xp, Tokens, Record, Best0,
--     State = "Fighting" | "Intermission" | "Ending" | "Ended" }. The run's pocket comes from the shared pool
--     (St.pocketBusy) via ArenaBuilder.BuildPocket(index, "Ring") (pcall; the trial pocket is the fallback). Every
--     round is a fresh BattleSim (Mode "Ring", Zone 44 x 44, Teams = { the player's spec, BattleCatalog.ChampionTeam
--     (round, seed) }, TimeLimit 90: a timeout is a loss). A WIN pays once (payOnce / RingRun.pay: Cash =
--     BattleCatalog.RingRewards(round, TycoonService.IncomePerSecond(player), isRecord) with the record x3 and the first
--     boss clear's Tokens decided inside ONE DataService.MutateRing; XP 20 + 6r per team pet through
--     PetCareService.GrantXp source "Ring"), sends "End" with Rewards.Next / Cash / Record / Tokens, keeps the
--     participant (the new InBattle id is written by the next round's addParticipant BEFORE the old one is let go:
--     no gap, followers stay parked, GoHome / portals stay refused), waits Ring.Intermission seconds and starts the
--     next round in the same pocket. A loss, a timeout, Forfeit, leaving the pocket, a respawn elsewhere, an obby
--     match, a disconnect or a shutdown ends the run the trial way (the return teleport TRIAL_RETURN_DELAY later,
--     release, FreePocket, Ring.Runs + 1 written at once: on a leave it travels with the leave save) and the round
--     that ends the run pays a third of its XP under the trial-loss gate (BattleCatalog.LossXp; never for a forfeit,
--     a leave, a disconnect or a shutdown). The final "End" carries Rewards.Final = true and Rewards.Run = { Wins,
--     Cash, Xp, Tokens, Round, Start, Record, Best } (the result card). Forfeit during an intermission ends the run
--     cleanly (the last round kept). "Start" carries Ring = { Round, Best, Start, Champion = { PetId, Level, Tier,
--     Boss, Name } }; BattleEnded fires with Mode "Ring", Round and Won. When a run ends the Portal_Ring attribute
--     RingBoard = "Alex|31;Sam|24;Kim|20" (the best records in this server) is rewritten.
--
-- The loop: on Heartbeat every running battle runs the fixed 0.1 s steps that are due against the wall clock (a
-- stalled server catches up at most MAX_CATCHUP steps per frame, merging their events into one message). After each
-- step: "Events" (the Step() events) to the receivers that already have the battle, "Start" to new receivers, then
-- "Snapshot". Messages (BattleState(kind, payload, battleId): the battle id rides along as a third argument, so a
-- client can route a bare "Events" list too):
--   "Start"    battle:Describe() + Zone = { CFrame (floor centre), Size (Vector3: X, height, Z), X, Z } + Names =
--              { [tostring(userId)] = name } + Side (the receiver's side, 0 for a spectator) + Spectator + T (+ Trial =
--              { Level, Name, Chapter } for trials). Unit static info carries slot (the owner's team slot 1-4).
--   "Snapshot" battle:SnapshotDelta(last) = { BattleId, T, U = { number... } }: the units whose picture changed since the
--              receiver's previous snapshot, as flat numbers (code, pos [, hp] [, meter] [, shield] [, target] per unit;
--              BattleSim.DecodeSnapshot turns it back into { [id] = { x, z, hp, state, target, meter, shield } }); x / z
--              are studs relative to the zone centre (floor at the zone CFrame's height). Down units are sent once and
--              then left out, hp / meter / shield / target only when they change. Fighters get a snapshot every step
--              (10 Hz), spectators every other step (5 Hz); a new receiver gets a full snapshot right after its "Start".
--   "Events"   the list of Step() events ({ type = "Hit" | "Special" | "KO" | "Telegraph" | "Spawn" | "Enrage" |
--              "Order" | "Zone" | "Leave" | "End", ... }), only when the step produced any.
--   "End"      { BattleId, Mode, Result (the public result: owner maps keyed by tostring(userId)), Rewards (the
--              receiver's own, nil for spectators), Outcome = "Win" | "Loss" | "Draw" | "Left" | nil, Won, Spectator,
--              Reason }. A spectator who walks out of range (or switches to a nearer battle) also gets an "End" with
--              Spectator = true and Reason = "OutOfRange" (it frees the client's models).
--   Spectators: a player who is in no battle watches the NEAREST running battle within SPECTATE_MARGIN studs of its
--   zone (one battle per client at a time; refreshed once a second). Bandwidth: EstimateBytes approximates the
--   remote encoding; GetNetStats() reports bytes per second per client over the last window. Measured by
--   tools/smoke_p3_battleservice.lua and tools/smoke_p3_fix_server.lua (estimate per client): a trial or a duel a few
--   KB/s, an 8-player raid well under 20 KB/s and a full 16-player raid under ~20 KB/s (the delta snapshots).
--
-- Teams: the active preset (DataService.ActiveTeamKeys, at most GetTeams().Slots pets: the 4th at Prestige 1), each key
--   as { Key, PetId, Def = PetKeys.DefOf(key, profile), Level = DataService.GetPetLevel, Tier, Slot, Evo, Train = {
--   Speed, Physique, Ability, Defense }, Xp, XpNext } (hybrids and tier copies keep their own stats; Phase 4: the
--   stored evolution stage and training ranks from DataService.GetGrowth ride as the UnitStats extras, so evolution and
--   training count in trials, duels, raids and the ring; training keys are skipped: DataService.TrainingKeys); the team
--   is fixed for the whole battle (a ring run rebuilds it from its fixed key list every round).
-- Owners and anchors: a team's owner is the player's UserId. Twice a second every participant's position (zone-local)
--   becomes their team's anchor (battle:SetAnchor), so RETREAT means "back to me".
-- BattleCommand (action, a): "Attack" (target unit id | nil), "Retreat", "Special" (team slot 1-4), "Forfeit". Only the
--   caller's own team (the owner is always the caller), only in the caller's running battle, only while their character
--   stands inside that battle's zone (Forfeit works anywhere), type-checked, token-bucket rate limited.
-- BattleRequest (action, a, b): "TeamSet" (preset 1-3, {keys}), "TeamSelect" (preset) (DataService validates: owned,
--   unique, not training (a garden pet may fight: Phase 4), slot 4 at Prestige 1), "Trial" (level), "Challenge" (userId),
--   "ChallengeReply" (userId, accept), "Queue", "Unqueue", "JoinRaid", "LeaveRaid", "Ring" (startRound). Type-checked, a
--   cooldown per action plus a shared burst bucket; refusals answer with a side toast (Notify, never centred; repeats
--   throttled).
--
-- Leaving, forfeits, tricks ("nobody loses pets": no pet is ever taken)
--   * A trial player who forfeits, leaves the game, respawns elsewhere or ends up away from the pocket (teleported,
--     an exploit) loses the trial (no reward); the pocket is freed. Falling off the pocket puts them back on its spawn.
--   * A duel player who forfeits, leaves the game, leaves the arena or joins an obby match loses the duel at once: the
--     forfeit penalty (BattleCatalog.Trophies.Forfeit, a PvP loss) is written right away (before their profile is
--     saved on leave); the opponent wins. When BOTH duellists leave together (a server shutdown, "migrate to the
--     latest update", two friends quitting) the duel is void: nobody is penalised (a penalty already written to the
--     first leaver is given back while DataService still holds the profile).
--   * Duel rewards are gated against farming (payDuel): the winner's trophies, tokens and XP are withheld for a forfeit
--     before FORFEIT_MIN_SECONDS and for a loser who dealt no damage (an alt that quits at once or never fights; the
--     win still counts in PvPWins); the same two players earn from at most PAIR_LIMIT duels per PAIR_WINDOW seconds
--     (in this server's memory); a duel between teams more than DUEL_POWER_GAP apart in TeamPower is a PRACTICE duel
--     (a clear side toast: no trophies, tokens, XP or PvP counters for either side).
--   * A raid player who leaves the arena / the game is removed from the raid (no reward); a raider whose pets never hit
--     the boss (damage 0) gets no reward either (BattleCatalog.RaidTier nil); any hit earns at least the Helper tier.
--   * game:BindToClose -> Shutdown(): every running battle ends void (Reason "Shutdown"): duels and trials pay nothing
--     and penalise nobody, raids pay the tier of each fighter's current share (no event-pet roll); meanwhile new
--     battles are refused and leaving players are not treated as forfeiting.
--   * The player attribute InBattle holds the battle id (a string) while the player takes part (nil otherwise); trials
--     keep it until the player is back at the Trial Portal. ArenaBuilder's teleports and DevService refuse during it.
-- Rewards (paid exactly once per player per battle: the record is marked before anything is paid, every payment is a
--   non-yielding DataService call; BattleEnded fires afterwards with RewardsPaid = true):
--   * Trial win: BattleCatalog.TrialRewards(level, double).Tokens (+ FirstClear.Tokens / Gems on the first clear, decided
--     inside DataService.MutateBattle and paid only when it returned true) and Xp to every team pet. A trial LOSS pays
--     a third of that XP when it was a real loss (BattleCatalog.LossXp: the fight lasted >= 20 s or the team dealt >= 20%
--     of the enemy team's HP; never a forfeit, a leave, a disconnect or a shutdown).
--   * Ring round won: Cash (seconds of the climber's own garden income, floor 20 + 2r, x3 on a new record), XP 20 + 6r
--     per team pet, +100 Tokens for the first clear of a boss round; the run's last round: the loss third (see "Modes").
--   * Duel: BattleCatalog.Trophies (Win / Loss / Draw / Forfeit, Tokens, Xp); PvPWins / PvPLosses.
--   * Raid (only to the teams still in it at the end, when BattleService.PayRaidRewards is true): the tier of the
--     player's damage share, BattleCatalog.RaidTier(share, won): Tokens, Xp, a GemChance of Gems and an EventPetChance
--     of an event pet (BattleCatalog.EventPets(), one the player has not won yet: Battle.EventPets + a Normal copy);
--     Raids + 1, RaidBestDamage.
--   * Double Rewards (EventService's hour) doubles the Tokens (BattleCatalog.Events.DoubleRewardsMultiplier).
--   * Pet XP goes through PetCareService.GrantXp (level caps, level-up toasts); DataService.AddPetXp without it.
-- EventService integration (what EventService can rely on):
--   * StartRaid(bossId) opens the raid at once (no countdown here: announce it before calling); GetRaidStatus() is
--     non-nil from then until the raid is over (Waiting = true until the first player joins, Joinable while the join
--     window is open); BattleEnded fires once for the raid id (Mode "Raid", Reason "BossDown" | "Wipe" | "Timeout" |
--     "Abandoned" | "NoPlayers" | "Ended") after the rewards were paid: result.Rewards[userId] holds each fighter's tier,
--     tokens, gems and event pet, result.RewardsPaid = true. Do not pay the tiers again (or set
--     BattleService.PayRaidRewards = false before the raid ends to pay them yourself).
--   * The fight runs on the boss's own clock (its TimeLimit counts from the first join): let it end by itself (wait for
--     GetRaidStatus() == nil). EndRaid() ends a running fight at once as a timeout (the Loss tier for the fighters).
--   * Double Rewards: call SetDoubleRewards(true, seconds) / SetDoubleRewards(false) when the hour starts / ends, or
--     expose EventService.IsDoubleRewards() -> bool (also read: IsDoubleActive, DoubleRewardsActive, IsDouble,
--     GetDouble() -> { Active }, EventService.Double = { Active }), or set the workspace attribute DoubleRewards.
-- Plain Lua 5.1-compatible syntax only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local BattleService = {}
BattleService.BattleEnded = Util.Signal() -- Fire(battleId, result) once per battle, after the rewards were paid
BattleService.BattleStarted = Util.Signal() -- extra: Fire(battleId, { Mode, Players = {userId...}, Level, BossId })
BattleService.RaidJoined = Util.Signal() -- extra: Fire(player, battleId)
BattleService.PayRaidRewards = true -- extra: EventService may set false to pay the raid tiers itself
BattleService.Debug = nil -- extra (tests): { FailEnd = n } makes the next n battle ends fail (the fail-safe path)

----------------------------------------------------------------------
-- Shared modules (a build without one refuses battles instead of erroring)
----------------------------------------------------------------------
local function loadShared(name)
	local inst = Shared:FindFirstChild(name)
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	if ok and type(result) == "table" then
		return result
	end
	warn("[BattleService] shared/" .. name .. " failed to load: " .. tostring(result))
	return nil
end

local BattleSim = loadShared("BattleSim")
local BattleCatalog = loadShared("BattleCatalog")
local PetKeys = loadShared("PetKeys")
local PetCatalog = loadShared("PetCatalog")
local TycoonCatalog = loadShared("TycoonCatalog") -- Phase 4: XpToNext for the pet cards' xp / xpNext in "Start"

----------------------------------------------------------------------
-- Tunables (Config.Battle does not exist: local constants, listed as a deviation)
----------------------------------------------------------------------
local C = {
	ATTR_IN_BATTLE = "InBattle", -- Config.Attr.InBattle is missing (lead-owned): the attribute name from the contract
	ATTR_PORTAL_LOCKED = "PortalLocked", -- PortalService: the player is locked on a portal pad for a party countdown
	STEP = 0.1, -- fixed simulation step (BattleCatalog.StepSeconds)
	MAX_CATCHUP = 3, -- steps one loop tick may run for a battle that fell behind
	MONITOR_PERIOD = 0.5, -- presence checks + anchors
	HOUSEKEEPING_PERIOD = 1, -- invites, queue pairing, spectators, raid window
	OUT_STRIKES = 2, -- consecutive failed presence checks before a forfeit / leave (1 s)
	TRIAL_RANGE = 30, -- studs from the Trial Portal where a trial may start
	RING_RANGE = 30, -- studs from Portal_Ring where a Champion Ring run may start (Phase 4 contract 3.8)
	TRIAL_RETURN_DELAY = 4, -- seconds between a trial's (or a ring run's) end and the teleport back
	POCKET_LEASH = 140, -- studs (horizontal) from the pocket centre before a trial player counts as gone
	POCKET_FALL = 25, -- studs under the pocket floor where a falling player is put back on the spawn
	MAX_POCKETS = 64,
	RING_COOLDOWN = 4, -- a ring stays reserved this long after its duel (the result fx play out)
	ZONE_MARGIN = 8, -- studs of slack around a zone part for commands
	ZONE_FALLBACK_MARGIN = 16, -- ... around the floor rectangle when there is no zone part
	SPECTATE_MARGIN = 80, -- studs beyond the zone's half diagonal where spectators receive a battle
	SPECTATE_SWITCH = 10, -- a nearer battle must be this much nearer to switch
	SPECTATE_COOLDOWN = 3, -- seconds after leaving a battle before the player can spectate it
	CHALLENGE_TIMEOUT = 30,
	MAX_INVITES = 5, -- incoming invites per player
	QUEUE_GAP_BASE = 60, -- trophies apart two queued players may be at once ...
	QUEUE_GAP_PER_SECOND = 15, -- ... growing with the longer wait
	FORFEIT_MIN_SECONDS = 15, -- a duel that ends sooner (a forfeit, a stomp) pays the winner no trophies / tokens / XP
	PAIR_LIMIT = 3, -- rewarded duels between the same two players ...
	PAIR_WINDOW = 1800, -- ... per this many seconds
	DUEL_POWER_GAP = 3, -- a duel between teams whose TeamPower differs by more than this factor is practice (no rewards)
	RAID_RIM = 6, -- studs outside the raid floor where a joiner is placed
	DUEL_PAD_OUTSIDE = 5, -- studs outside the duel floor where the duellists stand (the ring's pads)
	ZONE_HEIGHT = 30, -- Size.Y of the zone in "Start"
	SPECTATOR_SNAPSHOT_EVERY = 2, -- spectators get every 2nd snapshot (5 Hz)
	TOAST_GAP = 1.5, -- the same toast text is not repeated within this many seconds
	COMMAND_BURST = 10, -- BattleCommand token bucket
	COMMAND_REFILL = 5, -- per second
	REQUEST_BURST = 6, -- BattleRequest token bucket
	REQUEST_REFILL = 2,
	MAX_ACTION_LENGTH = 16,
	MAX_KEY_LENGTH = 48,
	MAX_UNIT_ID = 256,
	NET_WINDOW = 5, -- seconds per bandwidth window
	REQUEST_COOLDOWNS = {
		TeamSet = 0.4,
		TeamSelect = 0.3,
		Trial = 1.5,
		Challenge = 2,
		ChallengeReply = 0.5,
		Queue = 1,
		Unqueue = 0.5,
		JoinRaid = 1,
		LeaveRaid = 1,
		Ring = 1.5, -- Phase 4: BattleRequest("Ring", startRound)
	},
}
if BattleCatalog and type(BattleCatalog.StepSeconds) == "number" and BattleCatalog.StepSeconds > 0 then
	C.STEP = BattleCatalog.StepSeconds
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local St = {
	initialized = false,
	running = false,
	deps = {},
	arenaInfo = nil,
	arenaBuilder = nil,
	remotes = {}, -- name -> RemoteEvent
	battles = {}, -- [battleId] = battle record
	order = {}, -- battle ids in start order (stable iteration)
	battleOf = {}, -- [Player] = battle record (participant, from the start until the cleanup)
	watching = {}, -- [Player] = battle record (spectator)
	watchCooldown = {}, -- [Player] = { [battleId] = os.clock() until which it may not spectate that battle }
	seq = 0,
	raid = nil, -- { Id, BossId, Opened, JoinUntil, Battle }
	ringBusy = {}, -- [ringIndex] = battleId | os.clock() of release
	pocketBusy = {}, -- [pocketIndex] = battleId
	invitesFrom = {}, -- [fromUserId] = invite
	invitesTo = {}, -- [toUserId] = { [fromUserId] = invite }
	queue = {}, -- [Player] = { Since, Trophies }
	pairs = {}, -- ["lo:hi"] = { os.clock() ... } duel starts between two players
	buckets = {}, -- [Player] = { cmd = {tokens, t}, req = {tokens, t} }
	cooldowns = {}, -- [Player] = { [action] = os.clock() }
	toasts = {}, -- [Player] = { [text] = os.clock() }
	net = {}, -- [userId] = { bytes, since, rate, peak, messages }
	double = nil, -- pushed Double Rewards state { Active, Until }
	eventService = nil, -- resolved lazily (false = missing)
	tycoonService = nil, -- resolved lazily when Init got none (false = missing): GetPlot / IncomePerSecond for the ring
	closing = false, -- Shutdown() ran: battles are refused, leavers are not forfeits
	rng = Random.new(),
	ringRuns = {}, -- [Player] = RingRun record (Phase 4 Champion Ring; see the header)
	ringSeq = 0,
	ringBoard = {}, -- [userId] = { Name, Best }: the best records seen in this server (the Portal_Ring RingBoard attribute)
	ringBoardText = nil,
	ringPortal = nil, -- the Portal_Ring model found in the workspace (cached)
}

-- Phase 4 Champion Ring helpers (one table: Lua's 200-locals limit; ARCHITECTURE_V3.md "Phase 4 build contract" 6)
local RingRun = {}

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local floor, ceil, max, min, abs, sqrt = math.floor, math.ceil, math.max, math.min, math.abs, math.sqrt

local function now()
	return os.clock()
end

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function isInteger(n)
	return finite(n) and n == floor(n)
end

-- whole seconds left of a countdown (60.0000001 still reads 60)
local function secondsLeft(x)
	return max(0, ceil(x - 0.001))
end

local function isPlayer(p)
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players
end

local function nameOf(player)
	if typeof(player) ~= "Instance" then
		return "?"
	end
	local display = player.DisplayName
	if type(display) == "string" and display ~= "" then
		return display
	end
	return player.Name
end

local function shortName(player, limit)
	local s = nameOf(player)
	limit = limit or 20
	if #s > limit then
		s = s:sub(1, limit - 1) .. "."
	end
	return s
end

local function getRemote(name)
	local cached = St.remotes[name]
	if cached ~= nil then
		return cached or nil
	end
	local ok, remote = pcall(Remotes.Get, name)
	if ok and remote then
		St.remotes[name] = remote
		return remote
	end
	St.remotes[name] = false
	return nil
end

-- Side toast (NotifyController: right edge, never centred). The same text is not repeated within TOAST_GAP seconds.
local function notify(player, text, kind, duration)
	if not isPlayer(player) or type(text) ~= "string" or text == "" then
		return
	end
	local list = St.toasts[player]
	if not list then
		list = {}
		St.toasts[player] = list
	end
	local t = now()
	local last = list[text]
	if last and t - last < C.TOAST_GAP then
		return
	end
	list[text] = t
	local remote = getRemote("Notify")
	if remote then
		if #text > 90 then
			text = text:sub(1, 89) .. "."
		end
		pcall(function()
			remote:FireClient(player, text, kind or "info", duration or 3)
		end)
	end
end

local function dataService()
	return St.deps.DataService
end

local function petCareService()
	return St.deps.PetCareService
end

local function hasFn(mod, name)
	return type(mod) == "table" and type(mod[name]) == "function"
end

-- calls mod[name](...) under pcall; returns up to four results, or nil when it is missing or errored
local function try(mod, name, ...)
	if not hasFn(mod, name) then
		return nil
	end
	local ok, a, b, c, d = pcall(mod[name], ...)
	if not ok then
		warn("[BattleService] " .. name .. " failed: " .. tostring(a))
		return nil
	end
	return a, b, c, d
end

local function setInBattle(player, battleId)
	if typeof(player) == "Instance" and player.Parent then
		pcall(function()
			player:SetAttribute(C.ATTR_IN_BATTLE, battleId)
		end)
	end
end

----------------------------------------------------------------------
-- Bandwidth: an estimate of the remote encoding (a type byte per value, numbers as doubles, strings and dictionary
-- keys length-prefixed). Good enough to compare payloads and to keep the per-client rate modest.
----------------------------------------------------------------------
local function estimateBytes(value, depth)
	depth = depth or 0
	local kind = typeof(value)
	if kind == "nil" then
		return 1
	elseif kind == "boolean" then
		return 2
	elseif kind == "number" then
		return 9
	elseif kind == "string" then
		return 2 + #value
	elseif kind == "table" then
		if depth > 12 then
			return 2
		end
		local n = 2
		for k, v in pairs(value) do
			if type(k) == "string" then
				n = n + 2 + #k
			end
			n = n + estimateBytes(v, depth + 1)
		end
		return n
	elseif kind == "Vector3" or kind == "Color3" then
		return 13
	elseif kind == "CFrame" then
		return 49
	elseif kind == "Vector2" then
		return 9
	elseif kind == "EnumItem" then
		return 6
	end
	return 9
end

local function countBytes(player, bytes)
	local uid = player.UserId
	local rec = St.net[uid]
	local t = now()
	if not rec then
		rec = { bytes = 0, since = t, rate = 0, peak = 0, messages = 0 }
		St.net[uid] = rec
	end
	if t - rec.since >= C.NET_WINDOW then
		rec.rate = rec.bytes / max(t - rec.since, 0.001)
		if rec.rate > rec.peak then
			rec.peak = rec.rate
		end
		rec.bytes = 0
		rec.since = t
	end
	rec.bytes = rec.bytes + bytes
	rec.messages = rec.messages + 1
end

-- BattleState(kind, payload, battleId) to one player; `bytes` = the payload estimate when the caller has it already
local function send(player, kind, payload, battleId, bytes)
	local remote = getRemote("BattleState")
	if not remote or not isPlayer(player) then
		return false
	end
	local ok, err = pcall(function()
		remote:FireClient(player, kind, payload, battleId)
	end)
	if not ok then
		warn("[BattleService] BattleState " .. tostring(kind) .. " failed: " .. tostring(err))
		return false
	end
	countBytes(player, (bytes or estimateBytes(payload)) + 4 + #kind + (type(battleId) == "string" and #battleId + 2 or 1))
	return true
end

----------------------------------------------------------------------
-- Characters, the arena, zones
----------------------------------------------------------------------
-- root, humanoid, character of a living character (nil otherwise)
local function aliveRoot(player)
	local char = typeof(player) == "Instance" and player.Character
	if not char then
		return nil
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil
	end
	return root, humanoid, char
end

local function teleport(player, cf)
	local root, _, char = aliveRoot(player)
	if not root or typeof(cf) ~= "CFrame" then
		return false
	end
	local ok = pcall(function()
		char:PivotTo(cf)
	end)
	if not ok then
		return false
	end
	pcall(function()
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end)
	return true
end

local function arena()
	if St.arenaInfo then
		return St.arenaInfo
	end
	local builder = St.arenaBuilder
	if hasFn(builder, "GetInfo") then
		local ok, info = pcall(builder.GetInfo)
		if ok and type(info) == "table" then
			St.arenaInfo = info
			return info
		end
	end
	return nil
end

local function inArena(position)
	if typeof(position) ~= "Vector3" then
		return false
	end
	local info = arena()
	if not info then
		return false
	end
	local fn = type(info.InArena) == "function" and info.InArena or nil
	if not fn and hasFn(St.arenaBuilder, "InArena") then
		fn = St.arenaBuilder.InArena
	end
	if fn then
		local ok, result = pcall(fn, position)
		if ok then
			return result == true
		end
	end
	-- fallback: a disc around the arena centre
	if typeof(info.Center) == "CFrame" then
		local radius = tonumber(info.Radius) or 160
		local rel = position - info.Center.Position
		return rel.X * rel.X + rel.Z * rel.Z <= radius * radius and rel.Y > -30 and rel.Y < 80
	end
	return false
end

local function playerInArena(player)
	local root = aliveRoot(player)
	return root ~= nil and inArena(root.Position)
end

-- where trial starts are accepted: the Trial Portal's pad (ArenaInfo.TrialPortal), else the Portal_Trials model
local function trialPortalPosition()
	local info = arena()
	local pad = info and info.TrialPortal
	if typeof(pad) == "Instance" and pad:IsA("BasePart") and pad:IsDescendantOf(Workspace) then
		return pad.Position
	end
	local model = St.trialPortal
	if not (typeof(model) == "Instance" and model:IsDescendantOf(Workspace)) then
		model = Workspace:FindFirstChild("Portal_Trials", true)
		St.trialPortal = model
	end
	if model then
		if model:IsA("BasePart") then
			return model.Position
		end
		local ok, cf = pcall(function()
			return model:GetPivot()
		end)
		if ok and typeof(cf) == "CFrame" then
			return cf.Position
		end
	end
	return nil
end

-- { CFrame (floor centre), X, Z (floor size), Part (the NC_BattleZone part) }
local function zoneFrom(cf, size, part)
	local x, z = 44, 44
	if typeof(size) == "Vector3" then
		x, z = size.X, size.Z
	elseif type(size) == "table" then
		x = tonumber(size.X or size[1]) or x
		z = tonumber(size.Z or size[3] or size[2]) or z
	elseif finite(size) and size > 0 then
		x, z = size, size
	end
	local zonePart = nil
	if typeof(part) == "Instance" and part:IsA("BasePart") then
		zonePart = part
	end
	return { CFrame = cf, X = x, Z = z, Part = zonePart }
end

-- zone-local x, y, z (studs from the floor centre)
local function zoneLocal(zone, position)
	local rel = zone.CFrame:PointToObjectSpace(position)
	return rel.X, rel.Y, rel.Z
end

-- inside the battle zone (its NC_BattleZone part, else the floor rectangle), with some slack
local function insideZone(zone, position)
	if typeof(position) ~= "Vector3" then
		return false
	end
	local part = zone.Part
	if part and part.Parent then
		local rel = part.CFrame:PointToObjectSpace(position)
		local s = part.Size
		local m = C.ZONE_MARGIN
		return abs(rel.X) <= s.X / 2 + m and abs(rel.Y) <= s.Y / 2 + m and abs(rel.Z) <= s.Z / 2 + m
	end
	local x, y, z = zoneLocal(zone, position)
	local m = C.ZONE_FALLBACK_MARGIN
	return abs(x) <= zone.X / 2 + m and abs(z) <= zone.Z / 2 + m and y > -12 and y < 45
end

local function lookFrom(position, target)
	local flat = Vector3.new(target.X, position.Y, target.Z)
	if (flat - position).Magnitude < 0.01 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, flat)
end

----------------------------------------------------------------------
-- Teams and records
----------------------------------------------------------------------
local function battleRecord(player)
	local rec = try(dataService(), "GetBattle", player)
	if type(rec) == "table" then
		return rec
	end
	return nil
end

local function trophiesOf(player)
	local rec = battleRecord(player)
	return rec and tonumber(rec.Trophies) or 0
end

-- The BattleSim team spec of the player's active preset: { Owner = userId, Side, Name, Pets = { { Key, PetId, Def,
-- Level, Tier, Slot, Evo, Train, Xp, XpNext }... } }, or nil + a reason for a toast. `fallback` (Phase 4, the Champion
-- Ring): a fixed key list used INSTEAD of the active preset (the run's fighters); the empty-team refusal stays for
-- trials, duels and raids. Training keys (DataService.TrainingKeys) are skipped either way; the stored evolution stage
-- and training ranks (DataService.GetGrowth) ride on each entry as the UnitStats extras.
local function teamOf(player, side, fallback)
	local DS = dataService()
	if not hasFn(DS, "ActiveTeamKeys") or not PetKeys then
		return nil, "Battles are not ready yet"
	end
	local teams = try(DS, "GetTeams", player)
	if type(teams) ~= "table" then
		return nil, "Your data is still loading"
	end
	local keys = fallback
	if type(keys) ~= "table" then
		keys = try(DS, "ActiveTeamKeys", player)
		if type(keys) ~= "table" or #keys == 0 then
			return nil, "Pick your battle team first (Menu > Team)"
		end
	end
	local training = try(DS, "TrainingKeys", player)
	if type(training) ~= "table" then
		training = {}
	end
	local slots = tonumber(teams.Slots) or 3
	local profile = try(DS, "GetProfile", player)
	local pets = {}
	for i, key in ipairs(keys) do
		if i > slots then
			break
		end
		if type(key) == "string" and not training[key] then
			local okP, parsed = pcall(PetKeys.Parse, key)
			local okD, def = pcall(PetKeys.DefOf, key, profile)
			if okP and type(parsed) == "table" and okD and type(def) == "table" and type(def.Stats) == "table" then
				local level, xp = try(DS, "GetPetLevel", player, key)
				if not isInteger(level) or level < 1 then
					level = 1
				end
				local growth = try(DS, "GetGrowth", player, key)
				local evo, train = 0, nil
				if type(growth) == "table" then
					evo = isInteger(growth.Evo) and growth.Evo or 0
					train = { Speed = growth.Speed, Physique = growth.Physique, Ability = growth.Ability, Defense = growth.Defense }
				end
				local xpNext = nil
				if TycoonCatalog and type(TycoonCatalog.XpToNext) == "function" then
					local okX, v = pcall(TycoonCatalog.XpToNext, level)
					if okX and type(v) == "number" then
						xpNext = v
					end
				end
				pets[#pets + 1] = {
					Key = key,
					PetId = parsed.PetId or def.PetId,
					Def = def,
					Level = level,
					Tier = parsed.Tier or "Normal",
					Slot = i,
					Evo = evo,
					Train = train,
					Xp = finite(xp) and xp or 0,
					XpNext = xpNext,
				}
			end
		end
	end
	if #pets == 0 then
		return nil, "Your team has no pets that can fight"
	end
	return { Owner = player.UserId, Side = side, Name = nameOf(player), Pets = pets }
end

local function powerOf(spec)
	if not spec or not BattleCatalog or type(BattleCatalog.TeamPower) ~= "function" then
		return 0
	end
	local list = {}
	for i, pet in ipairs(spec.Pets) do
		-- Evo / Train ride along: TeamPower honours them (a trained team is not undercounted by DUEL_POWER_GAP)
		list[i] = { Def = pet.Def, Level = pet.Level, Tier = pet.Tier, Evo = pet.Evo, Train = pet.Train }
	end
	local ok, power = pcall(BattleCatalog.TeamPower, list)
	if ok and finite(power) then
		return floor(power + 0.5)
	end
	return 0
end

-- ok, reason: may this player start or join a battle right now?
local function canBattle(player)
	if not isPlayer(player) then
		return false, "That player is not here"
	end
	if not BattleSim or not BattleCatalog then
		return false, "Battles are not ready yet"
	end
	if St.closing then
		-- first: while the server closes nothing starts, whatever else the player is doing (a ring climber whose void
		-- round just ended is still InBattle for TRIAL_RETURN_DELAY seconds)
		return false, "The server is restarting: battles will be back in a moment"
	end
	if player:GetAttribute(Config.Attr.InMatch) == true then
		return false, "Finish your obby match first"
	end
	local locked = player:GetAttribute(C.ATTR_PORTAL_LOCKED)
	if locked ~= nil and locked ~= false and locked ~= "" then
		return false, "Leave the portal party first"
	end
	if St.battleOf[player] or St.ringRuns[player] then
		return false, "You are already in a battle"
	end
	if not aliveRoot(player) then
		return false, "Wait until you respawn"
	end
	return true
end

----------------------------------------------------------------------
-- Battle records + messages
----------------------------------------------------------------------
local function newBattleId()
	St.seq = St.seq + 1
	return "B" .. St.seq
end

local function newSeed()
	return St.rng:NextInteger(1, 2147483646)
end

local function newBattle(id, mode, sim, zone)
	return {
		Id = id,
		Mode = mode,
		Sim = sim,
		Zone = zone,
		Parts = {}, -- [userId] = participant
		PartList = {},
		Receivers = {}, -- [Player] = true: got "Start", gets every step
		Pending = {}, -- [Player] = true: gets "Start" after the next step's events
		Spectators = {}, -- [Player] = true
		Names = {}, -- [tostring(userId)] = display name
		Clock0 = now(),
		Steps = 0,
		State = "Running",
		EventBuf = {},
		LastFighters = {}, -- the fighters' last snapshot picture (BattleSim:SnapshotDelta updates it; cleared = full next)
		LastSpectators = {}, -- the spectators' (they get every 2nd snapshot)
		Paid = {}, -- [userId] = rewards | false (marked before paying)
		Broken = 0,
		TickErrors = 0,
		Started = now(),
	}
end

local function register(b)
	St.battles[b.Id] = b
	St.order[#St.order + 1] = b.Id
end

local function unregister(b)
	St.battles[b.Id] = nil
	for i, id in ipairs(St.order) do
		if id == b.Id then
			table.remove(St.order, i)
			break
		end
	end
end

-- the running battles, in start order (a copy: the loop may end some)
local function runningBattles()
	local out = {}
	for _, id in ipairs(St.order) do
		local b = St.battles[id]
		if b and b.State == "Running" then
			out[#out + 1] = b
		end
	end
	return out
end

local function addParticipant(b, player, side, spec)
	local keys = {}
	for i, pet in ipairs(spec.Pets) do
		keys[i] = pet.Key
	end
	local root = aliveRoot(player)
	local part = {
		Player = player,
		UserId = player.UserId,
		Side = side,
		Keys = keys,
		Spec = spec,
		Joined = now(),
		Strikes = 0,
		Origin = root and root.CFrame or nil,
		Power = powerOf(spec),
		Forfeited = false,
		Left = false,
	}
	b.Parts[player.UserId] = part
	b.PartList[#b.PartList + 1] = part
	b.Names[tostring(player.UserId)] = nameOf(player)
	St.battleOf[player] = b
	setInBattle(player, b.Id)
	return part
end

local function startPayload(b, player, spectator)
	local ok, d = pcall(b.Sim.Describe, b.Sim)
	if not ok or type(d) ~= "table" then
		return nil
	end
	d.BattleId = b.Id
	d.Zone = {
		CFrame = b.Zone.CFrame,
		Size = Vector3.new(b.Zone.X, C.ZONE_HEIGHT, b.Zone.Z),
		X = b.Zone.X,
		Z = b.Zone.Z,
	}
	d.Names = b.Names
	local part = player and b.Parts[player.UserId]
	d.Side = (part and not part.Left and part.Side) or 0
	d.Spectator = spectator == true
	d.T = b.Sim:Time()
	if b.TrialInfo then
		d.Trial = b.TrialInfo
	end
	if b.Mode == "Ring" then
		d.Ring = RingRun.startInfo(b)
	end
	return d
end

local function sendStart(b, player, spectator)
	b.Pending[player] = nil
	local payload = startPayload(b, player, spectator)
	if payload and send(player, "Start", payload, b.Id) then
		b.Receivers[player] = true
		return true
	end
	return false
end

-- the wire snapshot for one receiver group (see the header): only what changed since that group's last one
local function buildSnapshot(b, last)
	local ok, snap = pcall(b.Sim.SnapshotDelta, b.Sim, last)
	if not ok or type(snap) ~= "table" or type(snap.U) ~= "table" then
		return nil
	end
	snap.BattleId = b.Id
	return snap
end

-- to every receiver; `who` narrows it to "fighters" (participants) or "spectators"
local function broadcast(b, kind, payload, who)
	local bytes = estimateBytes(payload)
	for player in pairs(b.Receivers) do
		if isPlayer(player) then
			local spectator = b.Spectators[player] == true
			if who == nil or (who == "spectators") == spectator then
				send(player, kind, payload, b.Id, bytes)
			end
		else
			b.Receivers[player] = nil
		end
	end
end

-- after the steps of one tick: the events, the "Start" of new receivers, then the snapshots (a tick that sent a
-- "Start" sends everyone a FULL snapshot; spectators get theirs every SPECTATOR_SNAPSHOT_EVERY ticks)
local function flush(b)
	if #b.EventBuf > 0 then
		local list = b.EventBuf
		b.EventBuf = {}
		broadcast(b, "Events", list)
	end
	local pending = {}
	for player in pairs(b.Pending) do
		pending[#pending + 1] = player
	end
	local started = false
	for _, player in ipairs(pending) do
		if isPlayer(player) then
			if sendStart(b, player, b.Spectators[player] == true) then
				started = true
			end
		else
			b.Pending[player] = nil
		end
	end
	if started then
		b.LastFighters, b.LastSpectators = {}, {}
	end
	local snap = buildSnapshot(b, b.LastFighters)
	if snap then
		broadcast(b, "Snapshot", snap, "fighters")
	end
	-- (counted in sim steps since the last spectator snapshot: a tick that ran several steps never skips them for good)
	if started or b.Steps - (b.SpectatorStep or -math.huge) >= C.SPECTATOR_SNAPSHOT_EVERY then
		local spectators = false
		for player in pairs(b.Spectators) do
			if b.Receivers[player] then
				spectators = true
				break
			end
		end
		if spectators then
			local snapS = buildSnapshot(b, b.LastSpectators)
			if snapS then
				b.SpectatorStep = b.Steps
				broadcast(b, "Snapshot", snapS, "spectators")
			end
		end
	end
end

local function stepOnce(b)
	b.Steps = b.Steps + 1
	local ok, events = pcall(b.Sim.Step, b.Sim, C.STEP)
	if not ok then
		b.Broken = b.Broken + 1
		warn("[BattleService] battle " .. b.Id .. " step failed: " .. tostring(events))
		return
	end
	if type(events) == "table" then
		local buf = b.EventBuf
		for _, ev in ipairs(events) do
			buf[#buf + 1] = ev
		end
	end
end

local function simFinished(b)
	local ok, finished = pcall(b.Sim.IsFinished, b.Sim)
	return (ok and finished == true) or b.Broken >= 5
end

----------------------------------------------------------------------
-- Double Rewards: pushed by SetDoubleRewards, else read from EventService (resolved lazily: it may be missing or
-- written later), else the workspace attribute DoubleRewards.
----------------------------------------------------------------------
local function eventService()
	if St.eventService == nil then
		St.eventService = false
		local folder = script.Parent
		local inst = folder and folder:FindFirstChild("EventService")
		if inst then
			local ok, mod = pcall(require, inst)
			if ok and type(mod) == "table" then
				St.eventService = mod
			end
		end
	end
	return St.eventService or nil
end

function BattleService.IsDoubleRewards()
	local pushed = St.double
	if pushed then
		if pushed.Until and now() >= pushed.Until then
			St.double = nil
		else
			return pushed.Active == true
		end
	end
	local es = eventService()
	if es then
		for _, name in ipairs({ "IsDoubleRewards", "IsDoubleActive", "DoubleRewardsActive", "IsDouble" }) do
			if type(es[name]) == "function" then
				local ok, v = pcall(es[name])
				if ok and type(v) == "boolean" then
					return v
				end
			end
		end
		for _, name in ipairs({ "GetDouble", "GetDoubleRewards" }) do
			if type(es[name]) == "function" then
				local ok, v = pcall(es[name])
				if ok and type(v) == "table" then
					return v.Active == true
				elseif ok and type(v) == "boolean" then
					return v
				end
			end
		end
		if type(es.Double) == "table" then
			return es.Double.Active == true
		end
		if type(es.DoubleActive) == "boolean" then
			return es.DoubleActive
		end
	end
	return Workspace:GetAttribute("DoubleRewards") == true
end

function BattleService.SetDoubleRewards(active, seconds)
	if active == nil then
		St.double = nil
		return
	end
	local untilT = nil
	if finite(seconds) and seconds > 0 then
		untilT = now() + seconds
	end
	St.double = { Active = active == true, Until = untilT }
end

local function doubleMultiplier()
	local events = BattleCatalog and BattleCatalog.Events
	local m = type(events) == "table" and tonumber(events.DoubleRewardsMultiplier) or 2
	if not finite(m) or m < 1 then
		m = 2
	end
	return m
end

----------------------------------------------------------------------
-- Rewards (every call here is a non-yielding DataService / PetCareService call)
----------------------------------------------------------------------
local function grantTokens(player, n)
	if finite(n) and n > 0 then
		try(dataService(), "AddTokens", player, floor(n + 0.5))
	end
end

local function grantGems(player, n)
	if finite(n) and n > 0 then
		return try(dataService(), "AddGems", player, floor(n + 0.5)) == true
	end
	return false
end

-- pet XP to every key of the team (PetCareService.GrantXp: level caps + level-up toasts; DataService.AddPetXp without
-- it). Returns the levels gained in total.
local function grantXp(player, keys, xp, source)
	if not finite(xp) or xp <= 0 or type(keys) ~= "table" then
		return 0
	end
	local care = petCareService()
	local DS = dataService()
	local ups = 0
	for _, key in ipairs(keys) do
		local done = false
		if hasFn(care, "GrantXp") then
			local ok, given, levels, why = pcall(care.GrantXp, player, key, xp, source)
			if ok and not (given == 0 and why == "Pet care is not ready yet") then
				done = true
				ups = ups + (tonumber(levels) or 0)
			end
		end
		if not done and hasFn(DS, "AddPetXp") then
			ups = ups + (tonumber(try(DS, "AddPetXp", player, key, xp)) or 0)
		end
	end
	return ups
end

local function petName(petId)
	local def = PetCatalog and type(PetCatalog.Get) == "function" and PetCatalog.Get(petId)
	return (def and (def.Name or def.DisplayName)) or tostring(petId)
end

-- an event pet the player has not won yet (BattleCatalog.EventPets(): catalog pets with EventOnly = true): decided
-- inside MutateBattle (Battle.EventPets only grows), then one Normal copy joins the player's pets
local function grantEventPet(player)
	if not BattleCatalog or type(BattleCatalog.EventPets) ~= "function" or not PetKeys or not PetCatalog then
		return nil
	end
	local okL, list = pcall(BattleCatalog.EventPets)
	if not okL or type(list) ~= "table" or #list == 0 then
		return nil
	end
	local DS = dataService()
	local profile = try(DS, "GetProfile", player)
	if type(profile) ~= "table" then
		return nil
	end
	local maxStack = (Config.Pets and tonumber(Config.Pets.MaxPerStack)) or 99
	local chosen = nil
	local ok = try(DS, "MutateBattle", player, function(rec)
		if type(rec.EventPets) ~= "table" then
			rec.EventPets = {}
		end
		local candidates = {}
		for _, id in ipairs(list) do
			if type(id) == "string" and rec.EventPets[id] ~= true and PetCatalog.Get(id) and PetKeys.Count(profile, id) < maxStack then
				candidates[#candidates + 1] = id
			end
		end
		if #candidates == 0 then
			return false
		end
		chosen = candidates[St.rng:NextInteger(1, #candidates)]
		rec.EventPets[chosen] = true
	end)
	if ok ~= true or not chosen then
		return nil
	end
	local okAdd, added = pcall(PetKeys.Add, profile, chosen, 1)
	if not okAdd or not added then
		return nil
	end
	try(DS, "MarkDiscovered", player, chosen)
	try(DS, "MarkDirty", player)
	if hasFn(DS, "SyncSoon") then
		try(DS, "SyncSoon", player)
	else
		try(DS, "Sync", player)
	end
	notify(player, "Event pet! " .. petName(chosen) .. " joined your pets!", "good", 6)
	return chosen
end

local function emptyRewards()
	return { Tokens = 0, Gems = 0, Xp = 0, Trophies = 0, LevelUps = 0, Double = false }
end

local function payTrial(b, part, res)
	local player = part.Player
	local level = b.Level
	local rw = emptyRewards()
	rw.Level = level
	rw.FirstClear = false
	if res.WinnerSide ~= 1 or part.Forfeited then
		-- Phase 4 (3.5): a REAL loss (>= 20 s or >= 20% of the enemy HP dealt; never a forfeit / leave / disconnect /
		-- shutdown, which all arrive as part.Forfeited or Reason "Shutdown") pays a third of the win XP
		local xp = 0
		if not part.Forfeited and not part.Left and res.Reason ~= "Shutdown" and res.Reason ~= "Error" and type(BattleCatalog.LossXp) == "function" then
			local okL, lossXp = pcall(BattleCatalog.LossXp, tonumber(BattleCatalog.TrialRewards(level, false).Xp) or 0, res.Duration, RingRun.dealtShare(res))
			if okL and finite(lossXp) and lossXp > 0 then
				xp = floor(lossXp)
			end
		end
		if xp > 0 then
			rw.LevelUps = grantXp(player, part.Keys, xp, "Trial")
			rw.Xp = xp
			notify(player, "Trial " .. tostring(level) .. " lost, but your pets learned: +" .. xp .. " XP each", "info", 4)
		else
			notify(player, "Trial " .. tostring(level) .. " lost. Train your team and try again!", "bad", 4)
		end
		return rw
	end
	local double = BattleService.IsDoubleRewards()
	local R = BattleCatalog.TrialRewards(level, double)
	local first = false
	local okM = try(dataService(), "MutateBattle", player, function(rec)
		if type(rec.TrialCleared) ~= "table" then
			rec.TrialCleared = {}
		end
		if rec.TrialCleared[level] ~= true then
			rec.TrialCleared[level] = true
			first = true
		end
		if (tonumber(rec.TrialBest) or 0) < level then
			rec.TrialBest = level
		end
	end)
	first = okM == true and first
	local tokens = tonumber(R.Tokens) or 0
	local gems = 0
	if first and type(R.FirstClear) == "table" then
		tokens = tokens + (tonumber(R.FirstClear.Tokens) or 0)
		gems = tonumber(R.FirstClear.Gems) or 0
	end
	grantTokens(player, tokens)
	if gems > 0 and not grantGems(player, gems) then
		gems = 0
	end
	local xp = tonumber(R.Xp) or 0
	rw.LevelUps = grantXp(player, part.Keys, xp, "Trial")
	rw.Tokens, rw.Gems, rw.Xp, rw.FirstClear, rw.Double = tokens, gems, xp, first, double
	local text = "Trial " .. level .. " cleared! +" .. tokens .. " tokens"
	if gems > 0 then
		text = text .. ", +" .. gems .. " gems"
	end
	if first then
		text = text .. " (first clear!)"
	end
	notify(player, text, "good", 5)
	return rw
end

-- the forfeit penalty of a duel (written the moment the player forfeits / leaves). Only while DataService still holds
-- the profile: on a leave it is in memory until the leave save is done (a change made now travels with that save or
-- its retry); once released, a write would only create a stray cache entry.
local function payDuelForfeit(b, part)
	local player = part.Player
	local T = BattleCatalog.Trophies or {}
	local delta = tonumber(T.Forfeit) or tonumber(T.Loss) or 0
	if b.Practice then
		-- a practice duel counts for nothing either way: leaving it costs no trophies and no PvP loss
		local rw = emptyRewards()
		rw.Forfeit = true
		rw.Practice = true
		return rw
	end
	if type(try(dataService(), "GetProfile", player)) ~= "table" then
		local rw = emptyRewards()
		rw.Forfeit = true
		return rw
	end
	local before = trophiesOf(player)
	try(dataService(), "MutateBattle", player, function(rec)
		rec.PvPLosses = (tonumber(rec.PvPLosses) or 0) + 1
	end)
	local okT, total = try(dataService(), "AddTrophies", player, delta)
	local rw = emptyRewards()
	rw.Forfeit = true
	if okT and finite(total) then
		rw.Trophies = total - before
		rw.TrophiesTotal = total
	else
		rw.Trophies = delta
	end
	return rw
end

-- gives a forfeit penalty back (a duel that turned out void: both left, or the server is closing) while DataService
-- still holds the profile; the rewards record becomes Void
local function refundForfeit(b, part)
	local rw = b.Paid[part.UserId]
	if type(rw) ~= "table" or rw.Forfeit ~= true or rw.Refunded then
		return
	end
	local player = part.Player
	if rw.Practice ~= true and type(try(dataService(), "GetProfile", player)) == "table" then
		if finite(rw.Trophies) and rw.Trophies ~= 0 then
			try(dataService(), "AddTrophies", player, -rw.Trophies)
		end
		try(dataService(), "MutateBattle", player, function(rec)
			rec.PvPLosses = max(0, (tonumber(rec.PvPLosses) or 0) - 1)
		end)
	end
	local void = emptyRewards()
	void.Void = true
	void.Refunded = true
	b.Paid[part.UserId] = void
end

-- The anti-farming gates of a duel's rewards (trophies, tokens and XP move together): a practice duel (a huge power
-- gap) pays nothing to anyone and counts for nothing; past the pair limit nothing is paid; a winner is not paid for a
-- forfeit before FORFEIT_MIN_SECONDS or over a loser who dealt no damage (the win still counts in PvPWins). A duel
-- fought to the end between comparable teams is always paid, however fast it went.
local function payDuel(b, part, res)
	local player = part.Player
	local T = BattleCatalog.Trophies or {}
	local tokensT = type(T.Tokens) == "table" and T.Tokens or {}
	local xpT = type(T.Xp) == "table" and T.Xp or {}
	local won = res.WinnerSide == part.Side
	local draw = res.WinnerSide == nil
	local short = (tonumber(res.Duration) or 0) < C.FORFEIT_MIN_SECONDS
	local loserIdle = false
	if won then
		for _, other in ipairs(b.PartList) do
			if other ~= part and (tonumber(type(res.Damage) == "table" and res.Damage[other.UserId]) or 0) <= 0 then
				loserIdle = true
			end
		end
	end
	local stomp = won and ((res.Forfeit == true and short) or loserIdle)
	local rewarded = b.PairOk and not b.Practice
	local trophies, tokens, xp = 0, 0, 0
	if rewarded and won and not stomp then
		trophies, tokens, xp = tonumber(T.Win) or 0, tonumber(tokensT.Win) or 0, tonumber(xpT.Win) or 0
	elseif rewarded and draw then
		trophies, tokens, xp = tonumber(T.Draw) or 0, tonumber(tokensT.Draw) or 0, tonumber(xpT.Loss) or 0
	elseif rewarded and not won then
		trophies, tokens, xp = tonumber(T.Loss) or 0, tonumber(tokensT.Loss) or 0, tonumber(xpT.Loss) or 0
	end
	local double = tokens > 0 and BattleService.IsDoubleRewards()
	if double then
		tokens = floor(tokens * doubleMultiplier() + 0.5)
	end
	if not b.Practice then
		try(dataService(), "MutateBattle", player, function(rec)
			if won then
				rec.PvPWins = (tonumber(rec.PvPWins) or 0) + 1
			elseif not draw then
				rec.PvPLosses = (tonumber(rec.PvPLosses) or 0) + 1
			end
		end)
	end
	local rw = emptyRewards()
	local before = trophiesOf(player)
	if trophies ~= 0 then
		local okT, total = try(dataService(), "AddTrophies", player, trophies)
		if okT and finite(total) then
			rw.TrophiesTotal = total
			trophies = total - before
		end
	else
		rw.TrophiesTotal = before
	end
	grantTokens(player, tokens)
	rw.LevelUps = grantXp(player, part.Keys, xp, "Duel")
	rw.Trophies, rw.Tokens, rw.Xp, rw.Double = trophies, tokens, xp, double
	rw.Early = (won and res.Forfeit == true and short) or nil
	rw.Practice = b.Practice or nil
	rw.Unpaid = (won and not rewarded) or (won and stomp) or nil
	local text
	if b.Practice then
		text = (won and "Practice duel won!" or (draw and "Practice duel: a draw." or "Practice duel lost.")) .. " No rewards for practice."
	elseif won and res.Forfeit == true and short then
		text = "Your opponent left early: the win counts, no rewards."
	elseif won and loserIdle then
		text = "Your opponent never fought back: the win counts, no rewards."
	elseif won and not rewarded then
		text = "Victory! You two dueled a lot lately: no rewards this time."
	elseif won then
		text = "Victory! +" .. trophies .. " trophies, +" .. tokens .. " tokens"
	elseif draw then
		text = "Draw! +" .. tokens .. " tokens"
	else
		text = "Defeat. " .. trophies .. " trophies, +" .. tokens .. " tokens"
	end
	notify(player, text, (won or draw) and "good" or "info", 5)
	return rw
end

local function payRaid(b, part, res)
	if BattleService.PayRaidRewards == false then
		return nil -- EventService pays the tiers itself
	end
	local player = part.Player
	local uid = part.UserId
	local shutdown = res.Reason == "Shutdown"
	local won = res.WinnerSide == 1 or shutdown -- a shutdown pays the tier of the share so far
	local share = (type(res.Shares) == "table" and tonumber(res.Shares[uid])) or 0
	local damage = (type(res.Damage) == "table" and tonumber(res.Damage[uid])) or 0
	local tier = BattleCatalog.RaidTier(share, won)
	if not tier or damage <= 0 then
		-- no damage at all (an idle joiner whose pets never hit the boss): nothing, not even the Loss tier
		local rw = emptyRewards()
		rw.Tier, rw.Share, rw.Damage = "None", floor(share * 1000 + 0.5) / 1000, floor(damage)
		notify(player, "No raid reward this time: your pets never hit the boss.", "info", 5)
		return rw
	end
	local double = BattleService.IsDoubleRewards()
	local tokens = tonumber(tier.Tokens) or 0
	if double and tokens > 0 then
		tokens = floor(tokens * doubleMultiplier() + 0.5)
	else
		double = false
	end
	local gems = 0
	local gemChance = tonumber(tier.GemChance) or 0
	if gemChance > 0 and St.rng:NextNumber() < gemChance then
		gems = tonumber(tier.Gems) or 0
	end
	try(dataService(), "MutateBattle", player, function(rec)
		rec.Raids = (tonumber(rec.Raids) or 0) + 1
		if damage > (tonumber(rec.RaidBestDamage) or 0) then
			rec.RaidBestDamage = floor(damage)
		end
	end)
	local eventPet = nil
	local petChance = tonumber(tier.EventPetChance) or 0
	if petChance > 0 and not shutdown and St.rng:NextNumber() < petChance then
		eventPet = grantEventPet(player)
	end
	grantTokens(player, tokens)
	if gems > 0 and not grantGems(player, gems) then
		gems = 0
	end
	local xp = tonumber(tier.Xp) or 0
	local rw = emptyRewards()
	rw.LevelUps = grantXp(player, part.Keys, xp, "Raid")
	rw.Tokens, rw.Gems, rw.Xp, rw.Double = tokens, gems, xp, double
	rw.Tier, rw.Share, rw.Damage, rw.EventPet = tier.Id, floor(share * 1000 + 0.5) / 1000, floor(damage), eventPet
	local text
	if shutdown then
		text = "The server is restarting: " .. tostring(tier.Id) .. " tier for your damage so far, +" .. tokens .. " tokens"
	elseif won then
		text = "Boss defeated! " .. tostring(tier.Id) .. " tier: +" .. tokens .. " tokens"
	else
		text = "The boss won this time. +" .. tokens .. " tokens"
	end
	if gems > 0 then
		text = text .. ", +" .. gems .. " gems"
	end
	notify(player, text, won and "good" or "info", 5)
	return rw
end

local PAY = {
	Trial = payTrial,
	Duel = payDuel,
	Raid = payRaid,
	Ring = function(b, part, res) -- Phase 4 (defined below with the other Champion Ring helpers)
		return RingRun.pay(b, part, res)
	end,
}

-- pays one participant exactly once (marked before anything is paid); returns the rewards record or nil
local function payOnce(b, part, res)
	local uid = part.UserId
	if b.Paid[uid] ~= nil then
		return b.Paid[uid] or nil
	end
	b.Paid[uid] = false
	if res.Reason == "Error" or (res.Reason == "Shutdown" and b.Mode ~= "Raid") then
		-- void: nothing paid, nothing lost (raids on a shutdown pay the share so far: payRaid)
		local rw = emptyRewards()
		rw.Void = true
		if b.Mode == "Ring" then
			-- the running round is void; the run is over (the wins already paid stay paid): the result card data
			rw.Final = true
			rw.Round = b.Round
			rw.Run = RingRun.summary(b.Ring, b.Round)
		end
		b.Paid[uid] = rw
		if res.Reason == "Shutdown" then
			local what = (b.Mode == "Duel" and "duel") or (b.Mode == "Ring" and "ring round") or "trial"
			notify(part.Player, "The server is restarting: this " .. what .. " does not count.", "info", 5)
		end
		return rw
	end
	local fn = PAY[b.Mode]
	local ok, rw = pcall(fn, b, part, res)
	if not ok then
		warn("[BattleService] rewards for " .. tostring(uid) .. " in " .. b.Id .. " failed: " .. tostring(rw))
		rw = nil
	end
	b.Paid[uid] = rw or false
	return rw
end

----------------------------------------------------------------------
-- Spectators: a player in no battle watches the nearest running battle within range (one at a time)
----------------------------------------------------------------------
local function spectateRange(b)
	return sqrt((b.Zone.X / 2) ^ 2 + (b.Zone.Z / 2) ^ 2) + C.SPECTATE_MARGIN
end

local function stopWatching(player, reason)
	local b = St.watching[player]
	if not b then
		return
	end
	St.watching[player] = nil
	local had = b.Receivers[player] == true
	b.Receivers[player] = nil
	b.Pending[player] = nil
	b.Spectators[player] = nil
	if had and reason and b.State == "Running" and isPlayer(player) then
		send(player, "End", { BattleId = b.Id, Mode = b.Mode, Spectator = true, Reason = reason }, b.Id)
	end
end

local function startWatching(player, b)
	St.watching[player] = b
	b.Spectators[player] = true
	b.Pending[player] = true -- "Start" goes out after the battle's next step
end

local function refreshSpectators()
	local t = now()
	local running = runningBattles()
	for _, player in ipairs(Players:GetPlayers()) do
		if St.battleOf[player] then
			if St.watching[player] then
				stopWatching(player, "Joined")
			end
		else
			local root = aliveRoot(player)
			local current = St.watching[player]
			local best, bestD, currentD = nil, math.huge, math.huge
			if root then
				local cooldowns = St.watchCooldown[player]
				for _, b in ipairs(running) do
					local blocked = cooldowns and cooldowns[b.Id] and t < cooldowns[b.Id]
					if not blocked then
						local d = (root.Position - b.Zone.CFrame.Position).Magnitude
						if d <= spectateRange(b) then
							if d < bestD then
								best, bestD = b, d
							end
							if b == current then
								currentD = d
							end
						end
					end
				end
			end
			if current and current.State == "Running" and currentD < math.huge then
				if best and best ~= current and bestD + C.SPECTATE_SWITCH < currentD then
					stopWatching(player, "OutOfRange")
					startWatching(player, best)
				end
			else
				if current then
					stopWatching(player, "OutOfRange")
				end
				if best then
					startWatching(player, best)
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- The end of a battle: result, rewards (once), "End" messages, BattleEnded, then the cleanup
----------------------------------------------------------------------
local function contains(list, value)
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

local function outcomeOf(result, part)
	if part.Left then
		return "Left"
	end
	if contains(result.Winners, part.UserId) then
		return "Win"
	end
	if result.Draw then
		return "Draw"
	end
	if contains(result.Losers, part.UserId) or part.Forfeited then
		return "Loss"
	end
	return nil
end

-- the client copy of a result: maps keyed by owner become string keyed (remote tables keep string keys only)
local function publicResult(result)
	local function stringKeys(map)
		local out = {}
		if type(map) == "table" then
			for k, v in pairs(map) do
				out[tostring(k)] = v
			end
		end
		return out
	end
	return {
		BattleId = result.BattleId,
		Mode = result.Mode,
		Reason = result.Reason,
		WinnerSide = result.WinnerSide,
		Draw = result.Draw,
		Forfeit = result.Forfeit,
		Winners = result.Winners,
		Losers = result.Losers,
		Level = result.Level,
		BossId = result.BossId,
		Round = result.Round,
		Won = result.Won,
		Duration = result.Duration,
		BossHp = result.BossHp,
		BossMaxHp = result.BossMaxHp,
		Damage = stringKeys(result.Damage),
		Shares = stringKeys(result.Shares),
		Participants = result.Participants,
	}
end

local function releaseZone(b)
	local part = b.Zone and b.Zone.Part
	if part and part.Parent then
		pcall(function()
			if part:GetAttribute("BattleId") == b.Id then
				part:SetAttribute("BattleId", nil)
			end
		end)
	end
end

local function releaseParticipant(b, part)
	local player = part.Player
	if St.battleOf[player] == b then
		St.battleOf[player] = nil
		setInBattle(player, nil)
	end
	if isPlayer(player) then
		St.watchCooldown[player] = { [b.Id] = now() + C.SPECTATE_COOLDOWN }
	end
end

local function returnCFrame(part, mode)
	local info = arena()
	if mode == "Ring" then
		-- ring climbers come back in front of the Champion Ring portal (built like ReturnCFrame from the trial site),
		-- else where they pressed START (within RING_RANGE of it); an older lobby without RingSite: the Trial Portal
		local site = info and info.RingSite
		if typeof(site) == "CFrame" then
			local cfr = CFrame.lookAt(site.Position + site.LookVector * 12 + Vector3.new(0, 3, 0),
				site.Position + site.LookVector * 30 + Vector3.new(0, 3, 0))
			return cfr * CFrame.new(St.rng:NextNumber(-3, 3), 0, St.rng:NextNumber(-2, 2))
		end
		if typeof(part.Origin) == "CFrame" then
			return part.Origin
		end
	end
	local cf = info and info.ReturnCFrame
	if typeof(cf) == "CFrame" then
		return cf * CFrame.new(St.rng:NextNumber(-3, 3), 0, St.rng:NextNumber(-2, 2))
	end
	return part.Origin
end

-- trials: back to the Trial Portal (only a player still at the pocket), then the pocket goes
local function finishTrial(b)
	for _, part in ipairs(b.PartList) do
		local player = part.Player
		if isPlayer(player) and St.battleOf[player] == b then
			local root = aliveRoot(player)
			if root then
				local x, _, z = zoneLocal(b.Zone, root.Position)
				if sqrt(x * x + z * z) <= C.POCKET_LEASH + 40 then
					teleport(player, returnCFrame(part))
				end
			end
		end
		releaseParticipant(b, part)
	end
	local index = b.Zone.PocketIndex
	if index and hasFn(St.arenaBuilder, "FreePocket") then
		pcall(St.arenaBuilder.FreePocket, b.Zone.Pocket or index)
	end
	if index and St.pocketBusy[index] == b.Id then
		St.pocketBusy[index] = nil
	end
	unregister(b)
end

-- frees everything a battle holds (players, ring, pocket, raid, zone) and forgets it: the way out when its end failed
local function forceRelease(b)
	b.State = "Ended"
	if b.Ring then
		pcall(RingRun.abandon, b.Ring)
	end
	for _, part in ipairs(b.PartList) do
		if (b.Mode == "Trial" or b.Mode == "Ring") and isPlayer(part.Player) and St.battleOf[part.Player] == b then
			-- nobody stays stranded in a pocket far out in the sky
			pcall(function()
				local root = aliveRoot(part.Player)
				if root then
					local x, _, z = zoneLocal(b.Zone, root.Position)
					if sqrt(x * x + z * z) <= C.POCKET_LEASH + 40 then
						teleport(part.Player, returnCFrame(b.Mode == "Ring" and b.Ring or part, b.Mode))
					end
				end
			end)
		end
		pcall(releaseParticipant, b, part)
	end
	for player in pairs(b.Spectators) do
		if St.watching[player] == b then
			St.watching[player] = nil
		end
	end
	b.Receivers, b.Pending, b.Spectators = {}, {}, {}
	pcall(releaseZone, b)
	if b.RingIndex and St.ringBusy[b.RingIndex] == b.Id then
		St.ringBusy[b.RingIndex] = nil
	end
	local index = b.Zone and b.Zone.PocketIndex
	if index and St.pocketBusy[index] == b.Id then
		if hasFn(St.arenaBuilder, "FreePocket") then
			pcall(St.arenaBuilder.FreePocket, b.Zone.Pocket or index)
		end
		St.pocketBusy[index] = nil
	end
	if St.raid and St.raid.Battle == b then
		St.raid = nil
	end
	unregister(b)
	if not b.EndedFired then
		-- the clients and the listeners still learn that this battle is over (exactly once)
		b.EndedFired = true
		local participants, rewards = {}, {}
		for _, part in ipairs(b.PartList) do
			participants[#participants + 1] = part.UserId
			if b.Paid[part.UserId] then
				rewards[part.UserId] = b.Paid[part.UserId]
			end
			if not part.Left and isPlayer(part.Player) then
				send(part.Player, "End", { BattleId = b.Id, Mode = b.Mode, Spectator = false, Reason = "Error" }, b.Id)
			end
		end
		BattleService.BattleEnded:Fire(b.Id, {
			BattleId = b.Id,
			Mode = b.Mode,
			Reason = "Error",
			Winners = {},
			Losers = {},
			Draw = true,
			Forfeit = false,
			Level = b.Level,
			BossId = b.BossId,
			Round = b.Round,
			Won = (b.Mode == "Ring") and false or nil,
			Damage = {},
			Shares = {},
			Participants = participants,
			Rewards = rewards,
			RewardsPaid = true,
		})
	end
end

local function finalizeBody(b, forcedReason)
	local dbg = BattleService.Debug
	if type(dbg) == "table" and (tonumber(dbg.FailEnd) or 0) > 0 then
		dbg.FailEnd = dbg.FailEnd - 1
		error("injected end failure (BattleService.Debug.FailEnd)", 0)
	end
	local res = nil
	local okR, r = pcall(b.Sim.Result, b.Sim)
	if okR and type(r) == "table" then
		res = r
	end
	if not res then
		local okT, t = pcall(b.Sim.Time, b.Sim)
		res = {
			Mode = b.Mode,
			Reason = forcedReason or "Error",
			Winners = {},
			Losers = {},
			Draw = true,
			Forfeit = false,
			Damage = {},
			Shares = {},
			Duration = okT and t or 0,
		}
	end
	local result = {
		BattleId = b.Id,
		Mode = b.Mode,
		Reason = res.Reason,
		WinnerSide = res.WinnerSide,
		Draw = res.Draw == true,
		Forfeit = res.Forfeit == true,
		Winners = {},
		Losers = {},
		Level = b.Level,
		BossId = b.BossId,
		Round = b.Round,
		Damage = {},
		Shares = {},
		Duration = res.Duration,
		BossHp = res.BossHp,
		BossMaxHp = res.BossMaxHp,
		Participants = {},
		Rewards = {},
		RewardsPaid = true,
	}
	for _, owner in ipairs(type(res.Winners) == "table" and res.Winners or {}) do
		if type(owner) == "number" then
			result.Winners[#result.Winners + 1] = owner
		end
	end
	for _, owner in ipairs(type(res.Losers) == "table" and res.Losers or {}) do
		if type(owner) == "number" then
			result.Losers[#result.Losers + 1] = owner
		end
	end
	for owner, n in pairs(type(res.Damage) == "table" and res.Damage or {}) do
		if type(owner) == "number" then
			result.Damage[owner] = n
		end
	end
	for owner, s in pairs(type(res.Shares) == "table" and res.Shares or {}) do
		if type(owner) == "number" then
			result.Shares[owner] = s
		end
	end
	-- a duel both players left (or that the shutdown ended) is void: no winner, no loser, nothing paid
	if b.Mode == "Duel" and (b.Void or res.Reason == "Shutdown") then
		result.Winners, result.Losers, result.WinnerSide, result.Draw = {}, {}, nil, true
		if res.Reason ~= "Shutdown" then
			result.Reason = "Void"
		end
		res = { Reason = result.Reason, Draw = true, Forfeit = res.Forfeit, Damage = res.Damage, Shares = res.Shares, Duration = res.Duration }
		for _, part in ipairs(b.PartList) do
			refundForfeit(b, part)
		end
	end
	if b.Mode == "Ring" then
		-- Won: the climber's round was won (a forfeit, a leave, a shutdown and an error all count as not won)
		local climber = b.Ring and b.Ring.UserId or (b.PartList[1] and b.PartList[1].UserId)
		local part = climber and b.Parts[climber]
		result.Won = climber ~= nil and contains(result.Winners, climber) and part ~= nil and not part.Forfeited and not part.Left and res.Reason ~= "Shutdown"
	end
	-- rewards: every participant still in the battle, once (a duel leaver was settled when they left)
	result.Fighters = {}
	for _, part in ipairs(b.PartList) do
		result.Participants[#result.Participants + 1] = part.UserId
		if not part.Left then
			result.Fighters[#result.Fighters + 1] = part.UserId
		end
		local rw = nil
		if b.Paid[part.UserId] ~= nil then
			rw = b.Paid[part.UserId] or nil
		elseif not part.Left and isPlayer(part.Player) then
			if res.Draw and result.Reason == "Void" then
				rw = emptyRewards()
				rw.Void = true
				b.Paid[part.UserId] = rw
			else
				rw = payOnce(b, part, res)
			end
		end
		if rw then
			result.Rewards[part.UserId] = rw
		end
	end
	b.Result = result
	-- "End" to every receiver and every participant still here
	local public = publicResult(result)
	local told = {}
	for _, part in ipairs(b.PartList) do
		local player = part.Player
		if not part.Left and isPlayer(player) then
			told[player] = true
			local outcome = outcomeOf(result, part)
			send(player, "End", {
				BattleId = b.Id,
				Mode = b.Mode,
				Result = public,
				Rewards = result.Rewards[part.UserId],
				Outcome = outcome,
				Won = outcome == "Win",
				Spectator = false,
				Reason = result.Reason,
			}, b.Id)
		end
	end
	for player in pairs(b.Receivers) do
		if not told[player] and isPlayer(player) then
			told[player] = true
			send(player, "End", { BattleId = b.Id, Mode = b.Mode, Result = public, Spectator = true, Reason = result.Reason }, b.Id)
		end
	end
	for player in pairs(b.Spectators) do
		if St.watching[player] == b then
			St.watching[player] = nil
		end
	end
	b.Receivers, b.Pending, b.Spectators = {}, {}, {}
	releaseZone(b)
	-- the participants are free again (trials: once they are back at the portal; a ring WIN keeps the participant and
	-- chains the next round, a ring loss ends the run the trial way)
	if b.Mode == "Trial" then
		task.delay(C.TRIAL_RETURN_DELAY, function()
			local ok, err = pcall(finishTrial, b)
			if not ok then
				warn("[BattleService] trial cleanup failed: " .. tostring(err))
			end
		end)
	elseif b.Mode == "Ring" then
		RingRun.afterBattle(b, result)
	else
		for _, part in ipairs(b.PartList) do
			releaseParticipant(b, part)
		end
		if b.Mode == "Duel" and b.RingIndex then
			St.ringBusy[b.RingIndex] = now() + C.RING_COOLDOWN
		end
		if b.Mode == "Raid" and St.raid and St.raid.Battle == b then
			St.raid = nil
		end
		unregister(b)
	end
	b.EndedFired = true
	BattleService.BattleEnded:Fire(b.Id, result)
end

local function finalize(b, forcedReason)
	if b.State ~= "Running" then
		return
	end
	b.State = "Ended"
	b.EndedAt = now()
	local ok, err = pcall(finalizeBody, b, forcedReason)
	if not ok then
		warn("[BattleService] the end of " .. b.Id .. " failed: " .. tostring(err))
		forceRelease(b) -- nobody may stay stuck in a battle
	end
end

local function tickBattle(b, t)
	if b.State ~= "Running" then
		return
	end
	local due = floor((t - b.Clock0) / C.STEP + 1e-6)
	local n = 0
	while b.Steps < due and n < C.MAX_CATCHUP and b.State == "Running" do
		stepOnce(b)
		n = n + 1
		if simFinished(b) then
			break
		end
	end
	if b.Steps < due - C.MAX_CATCHUP then
		b.Clock0 = t - b.Steps * C.STEP -- a long stall is forgiven, never fast-forwarded
	end
	if n > 0 then
		flush(b)
		if simFinished(b) then
			finalize(b, b.Broken >= 5 and "Error" or nil)
		end
	end
end

----------------------------------------------------------------------
-- Forfeits and leaving
----------------------------------------------------------------------
local function forfeitTrial(b, part, why)
	if part.Forfeited or part.Left or b.State ~= "Running" then
		return false
	end
	part.Forfeited = true
	pcall(b.Sim.Command, b.Sim, part.UserId, "Forfeit")
	if why then
		notify(part.Player, why, "bad", 4)
	end
	return true
end

local function forfeitDuel(b, part, why)
	if part.Forfeited or part.Left or b.State ~= "Running" then
		return false
	end
	part.Forfeited = true
	pcall(b.Sim.Command, b.Sim, part.UserId, "Forfeit")
	-- both duellists gone (the other already forfeited / left, or is no longer here): the duel is void, no penalties
	local opponentLeft = false
	for _, other in ipairs(b.PartList) do
		if other ~= part and (other.Forfeited or other.Left or not isPlayer(other.Player)) then
			opponentLeft = true
		end
	end
	if St.closing or opponentLeft then
		for _, other in ipairs(b.PartList) do
			refundForfeit(b, other)
		end
		if b.Paid[part.UserId] == nil then
			local void = emptyRewards()
			void.Void = true
			b.Paid[part.UserId] = void
		end
		b.Void = true
		return true
	end
	-- the penalty is written now: the player may be leaving the game this very moment (their profile saves next)
	if b.Paid[part.UserId] == nil then
		b.Paid[part.UserId] = false
		local ok, rw = pcall(payDuelForfeit, b, part)
		if not ok then
			warn("[BattleService] forfeit penalty failed: " .. tostring(rw))
			rw = nil
		end
		b.Paid[part.UserId] = rw or false
	end
	if why then
		notify(part.Player, why, "bad", 4)
	end
	for _, other in ipairs(b.PartList) do
		if other ~= part and not other.Left and isPlayer(other.Player) then
			notify(other.Player, shortName(part.Player) .. " left the duel: you win!", "good", 4)
		end
	end
	return true
end

local function leaveRaid(b, part, why)
	if part.Left then
		return false
	end
	part.Left = true
	pcall(b.Sim.RemoveTeam, b.Sim, part.UserId)
	local player = part.Player
	b.Receivers[player] = nil
	b.Pending[player] = nil
	b.Spectators[player] = nil
	if isPlayer(player) then
		local payload = { BattleId = b.Id, Mode = "Raid", Outcome = "Left", Won = false, Spectator = false, Reason = "Left" }
		send(player, "End", payload, b.Id)
	end
	releaseParticipant(b, part)
	if why then
		notify(player, why, "info", 4)
	end
	return true
end

-- the right way out for each mode
local function dropOut(b, part, why)
	if b.Mode == "Raid" then
		return leaveRaid(b, part, why)
	elseif b.Mode == "Duel" then
		return forfeitDuel(b, part, why)
	elseif b.Mode == "Ring" then
		return RingRun.dropOut(b, part, why)
	end
	return forfeitTrial(b, part, why)
end

----------------------------------------------------------------------
-- Duels: invites, the quick queue, the rings
----------------------------------------------------------------------
local function lobbyPayload(player)
	local t = now()
	local uid = player.UserId
	local mine = St.queue[player]
	local waiting = 0
	for _ in pairs(St.queue) do
		waiting = waiting + 1
	end
	local payload = {
		Queue = { Queued = mine ~= nil, Waiting = waiting, Seconds = mine and floor(t - mine.Since) or 0 },
		Invites = {},
	}
	local incoming = St.invitesTo[uid]
	if incoming then
		for _, inv in pairs(incoming) do
			if inv.Expires > t then
				payload.Invites[#payload.Invites + 1] = {
					FromUserId = inv.FromUserId,
					FromName = inv.FromName,
					Trophies = inv.Trophies,
					Power = inv.Power,
					ExpiresIn = max(0, floor(inv.Expires - t + 0.5)),
				}
			end
		end
		table.sort(payload.Invites, function(x, y)
			return x.ExpiresIn > y.ExpiresIn
		end)
	end
	local sent = St.invitesFrom[uid]
	if sent and sent.Expires > t then
		payload.Sent = { ToUserId = sent.ToUserId, ToName = sent.ToName, ExpiresIn = max(0, floor(sent.Expires - t + 0.5)) }
	end
	return payload
end

local function sendLobby(player)
	if isPlayer(player) then
		send(player, "Lobby", lobbyPayload(player), nil)
	end
end

local function sendLobbyToQueue()
	for player in pairs(St.queue) do
		sendLobby(player)
	end
end

local function inviteRemove(inv)
	if St.invitesFrom[inv.FromUserId] == inv then
		St.invitesFrom[inv.FromUserId] = nil
	end
	local map = St.invitesTo[inv.ToUserId]
	if map and map[inv.FromUserId] == inv then
		map[inv.FromUserId] = nil
		if next(map) == nil then
			St.invitesTo[inv.ToUserId] = nil
		end
	end
end

-- drops every invite from or to the player; the others involved get a fresh "Lobby". -> true when one was dropped
local function clearInvitesOf(player, silent)
	local uid = player.UserId
	local touched = {}
	local dropped = false
	local out = St.invitesFrom[uid]
	if out then
		inviteRemove(out)
		touched[out.To] = true
		dropped = true
	end
	local incoming = St.invitesTo[uid]
	if incoming then
		local list = {}
		for _, inv in pairs(incoming) do
			list[#list + 1] = inv
		end
		for _, inv in ipairs(list) do
			inviteRemove(inv)
			touched[inv.From] = true
			dropped = true
		end
	end
	if not silent then
		touched[player] = true
	end
	for p in pairs(touched) do
		if p ~= player or not silent then
			sendLobby(p)
		end
	end
	return dropped
end

local function removeFromQueue(player, silent)
	if not St.queue[player] then
		return false
	end
	St.queue[player] = nil
	if not silent then
		sendLobby(player)
	end
	sendLobbyToQueue()
	return true
end

-- a player who enters a battle leaves the queue and drops their invites; their own "Lobby" is refreshed when that
-- changed anything (the duel start refreshes both duellists itself)
local function leaveLobby(player)
	local queued = removeFromQueue(player, true)
	local invited = clearInvitesOf(player, true)
	if queued or invited then
		sendLobby(player)
	end
end

local function freeRing(info)
	local t = now()
	for i, ring in ipairs(info.Rings) do
		local busy = St.ringBusy[i]
		if type(busy) == "number" and t >= busy then
			St.ringBusy[i] = nil
			busy = nil
		end
		if busy == nil and type(ring) == "table" and typeof(ring.CFrame) == "CFrame" then
			return i, ring
		end
	end
	return nil
end

-- the two duellists stand on the ring's pads, outside the fighting floor: side 1 on the -Z pad, side 2 on +Z
local function duelStand(zone, ring, side)
	local centre = zone.CFrame.Position
	local want = (side == 1) and -1 or 1
	if type(ring.Pads) == "table" then
		for _, pad in ipairs(ring.Pads) do
			if typeof(pad) == "Instance" and pad:IsA("BasePart") then
				local _, _, z = zoneLocal(zone, pad.Position)
				if z * want > 0 then
					return lookFrom(pad.Position + Vector3.new(0, 3, 0), centre)
				end
			end
		end
	end
	local pos = (zone.CFrame * CFrame.new(0, 3, want * (zone.Z / 2 + C.DUEL_PAD_OUTSIDE))).Position
	return lookFrom(pos, centre)
end

local function pairKey(pa, pb)
	local x, y = pa.UserId, pb.UserId
	if x > y then
		x, y = y, x
	end
	return tostring(x) .. ":" .. tostring(y)
end

-- true while these two players have fought fewer than PAIR_LIMIT trophy duels in the last PAIR_WINDOW seconds
-- (counts this one)
local function pairAllows(pa, pb)
	local key = pairKey(pa, pb)
	local t = now()
	local fresh = {}
	for _, at in ipairs(St.pairs[key] or {}) do
		if t - at < C.PAIR_WINDOW then
			fresh[#fresh + 1] = at
		end
	end
	local ok = #fresh < C.PAIR_LIMIT
	fresh[#fresh + 1] = t
	St.pairs[key] = fresh
	return ok
end

local function beginBattle(b)
	register(b)
	b.Clock0 = now()
	local zonePart = b.Zone.Part
	if zonePart and zonePart.Parent then
		pcall(function()
			zonePart:SetAttribute("BattleId", b.Id)
		end)
	end
	local players = {}
	for _, part in ipairs(b.PartList) do
		players[#players + 1] = part.UserId
		if isPlayer(part.Player) then
			sendStart(b, part.Player, false)
		end
	end
	BattleService.BattleStarted:Fire(b.Id, { Mode = b.Mode, Players = players, Level = b.Level, BossId = b.BossId, Round = b.Round })
end

-- ok, battleId | reason, culprit (the player the refusal is about; nil = no free ring / no arena)
local function startDuel(pa, pb)
	if pa == pb then
		return false, "You cannot duel yourself", pa
	end
	for _, p in ipairs({ pa, pb }) do
		local ok, why = canBattle(p)
		if not ok then
			return false, why, p
		end
		if not playerInArena(p) then
			return false, shortName(p) .. " is not in the Battle Arena", p
		end
	end
	local specA, whyA = teamOf(pa, 1)
	if not specA then
		return false, whyA, pa
	end
	local specB, whyB = teamOf(pb, 2)
	if not specB then
		return false, whyB, pb
	end
	local info = arena()
	if not info or type(info.Rings) ~= "table" or #info.Rings == 0 then
		return false, "The duel rings are closed", nil
	end
	local ringIndex, ring = freeRing(info)
	if not ring then
		return false, "Every duel ring is busy. Try again in a moment!", nil
	end
	local zone = zoneFrom(ring.CFrame, ring.Size, ring.Zone)
	local id = newBattleId()
	local okS, sim, why = pcall(BattleSim.new, {
		Mode = "Duel",
		Id = id,
		Seed = newSeed(),
		Zone = { X = zone.X, Z = zone.Z },
		Teams = { specA, specB },
	})
	if not okS or type(sim) ~= "table" then
		warn("[BattleService] duel setup failed: " .. tostring(okS and why or sim))
		return false, "The duel could not start", nil
	end
	local b = newBattle(id, "Duel", sim, zone)
	b.RingIndex = ringIndex
	St.ringBusy[ringIndex] = id
	-- a huge power gap makes it a practice duel (nothing paid, nothing counted); the pair limit is only taken for real duels
	local powerA, powerB = powerOf(specA), powerOf(specB)
	b.Practice = max(powerA, powerB) > max(1, min(powerA, powerB)) * C.DUEL_POWER_GAP
	b.PairOk = b.Practice or pairAllows(pa, pb)
	for _, p in ipairs({ pa, pb }) do
		stopWatching(p, "Joined")
		removeFromQueue(p, true)
		clearInvitesOf(p, true)
	end
	addParticipant(b, pa, 1, specA)
	addParticipant(b, pb, 2, specB)
	teleport(pa, duelStand(zone, ring, 1))
	teleport(pb, duelStand(zone, ring, 2))
	beginBattle(b)
	sendLobby(pa)
	sendLobby(pb)
	notify(pa, "Duel vs " .. shortName(pb) .. "! F = attack, R = retreat, 1-4 = specials", "info", 4)
	notify(pb, "Duel vs " .. shortName(pa) .. "! F = attack, R = retreat, 1-4 = specials", "info", 4)
	if b.Practice then
		local strong = (powerA >= powerB) and pa or pb
		local text = "Practice duel: " .. shortName(strong) .. "'s team is far stronger. No trophies or rewards."
		notify(pa, text, "info", 5)
		notify(pb, text, "info", 5)
	elseif not b.PairOk then
		notify(pa, "You two dueled a lot lately: no trophies or rewards this time.", "info", 4)
		notify(pb, "You two dueled a lot lately: no trophies or rewards this time.", "info", 4)
	end
	return true, id
end

function BattleService.StartDuel(pa, pb)
	if not isPlayer(pa) or not isPlayer(pb) then
		return false, "That player is not here"
	end
	local ok, idOrWhy = startDuel(pa, pb)
	return ok, idOrWhy
end

function BattleService.ReplyChallenge(player, fromUserId, accept)
	if not isPlayer(player) then
		return false, "That player is not here"
	end
	local incoming = St.invitesTo[player.UserId]
	local inv = incoming and incoming[fromUserId]
	if not inv then
		return false, "That challenge has expired"
	end
	if inv.Expires <= now() or not isPlayer(inv.From) then
		inviteRemove(inv)
		sendLobby(player)
		sendLobby(inv.From)
		return false, "That challenge has expired"
	end
	local from = inv.From
	if accept ~= true then
		inviteRemove(inv)
		sendLobby(player)
		sendLobby(from)
		notify(from, shortName(player) .. " declined your duel.", "info", 4)
		return true
	end
	local ok, idOrWhy, culprit = startDuel(from, player)
	if not ok then
		if culprit == from then
			-- the challenger cannot fight any more: the invite is void
			inviteRemove(inv)
			sendLobby(player)
			sendLobby(from)
			return false, shortName(from) .. " cannot duel right now"
		end
		return false, idOrWhy
	end
	return true, idOrWhy
end

-- a challenges b: an invite b can accept for CHALLENGE_TIMEOUT seconds
function BattleService.Challenge(a, b)
	if not isPlayer(a) or not isPlayer(b) then
		return false, "That player is not here"
	end
	if a == b then
		return false, "You cannot challenge yourself"
	end
	local ok, why = canBattle(a)
	if not ok then
		return false, why
	end
	if not playerInArena(a) then
		return false, "Go to the Battle Arena to duel"
	end
	local okB = canBattle(b)
	if not okB then
		return false, shortName(b) .. " cannot duel right now"
	end
	if not playerInArena(b) then
		return false, shortName(b) .. " is not in the Battle Arena"
	end
	local spec, reason = teamOf(a, 1)
	if not spec then
		return false, reason
	end
	local t = now()
	-- b already challenged a: this counts as a yes
	local back = St.invitesTo[a.UserId] and St.invitesTo[a.UserId][b.UserId]
	if back and back.Expires > t then
		return BattleService.ReplyChallenge(a, b.UserId, true)
	end
	local existing = St.invitesFrom[a.UserId]
	if existing and existing.ToUserId == b.UserId and existing.Expires > t then
		return false, "You already challenged " .. shortName(b)
	end
	local count = 0
	for _ in pairs(St.invitesTo[b.UserId] or {}) do
		count = count + 1
	end
	if count >= C.MAX_INVITES then
		return false, shortName(b) .. " has too many challenges right now"
	end
	if existing then
		inviteRemove(existing)
		sendLobby(existing.To)
	end
	local inv = {
		From = a,
		To = b,
		FromUserId = a.UserId,
		ToUserId = b.UserId,
		FromName = nameOf(a),
		ToName = nameOf(b),
		Trophies = trophiesOf(a),
		Power = powerOf(spec),
		Expires = t + C.CHALLENGE_TIMEOUT,
	}
	St.invitesFrom[a.UserId] = inv
	St.invitesTo[b.UserId] = St.invitesTo[b.UserId] or {}
	St.invitesTo[b.UserId][a.UserId] = inv
	sendLobby(a)
	sendLobby(b)
	notify(b, shortName(a) .. " challenges you to a duel! Answer in the Arena panel.", "info", 6)
	notify(a, "Challenge sent to " .. shortName(b) .. ".", "info", 3)
	return true
end

function BattleService.Queue(player)
	local ok, why = canBattle(player)
	if not ok then
		return false, why
	end
	if not playerInArena(player) then
		return false, "Go to the Battle Arena to join the queue"
	end
	local spec, reason = teamOf(player, 1)
	if not spec then
		return false, reason
	end
	if St.queue[player] then
		return false, "You are already in the queue"
	end
	St.queue[player] = { Since = now(), Trophies = trophiesOf(player) }
	sendLobbyToQueue()
	notify(player, "Looking for an opponent...", "info", 3)
	return true
end

function BattleService.Unqueue(player)
	if not isPlayer(player) or not St.queue[player] then
		return false, "You are not in the queue"
	end
	removeFromQueue(player)
	return true
end

local function expireInvites()
	local t = now()
	local expired = {}
	for _, inv in pairs(St.invitesFrom) do
		if inv.Expires <= t or not isPlayer(inv.From) or not isPlayer(inv.To) then
			expired[#expired + 1] = inv
		end
	end
	for _, inv in ipairs(expired) do
		inviteRemove(inv)
		if isPlayer(inv.From) then
			sendLobby(inv.From)
			if inv.Expires <= t then
				notify(inv.From, "Your challenge to " .. tostring(inv.ToName) .. " expired.", "info", 3)
			end
		end
		sendLobby(inv.To)
	end
end

-- pairs the queue: oldest first, each with the closest trophy count within the allowance of the longer wait
local function pairQueue()
	local t = now()
	local list = {}
	local changed = false
	for player, q in pairs(St.queue) do
		if not isPlayer(player) then
			St.queue[player] = nil
			changed = true
		else
			local ok, why = canBattle(player)
			if ok and not playerInArena(player) then
				ok, why = false, "You left the Battle Arena"
			end
			if not ok then
				St.queue[player] = nil
				changed = true
				sendLobby(player)
				notify(player, "Duel queue cancelled: " .. tostring(why), "info", 4)
			else
				list[#list + 1] = { p = player, q = q }
			end
		end
	end
	table.sort(list, function(x, y)
		return x.q.Since < y.q.Since
	end)
	local used = {}
	for i, a in ipairs(list) do
		if not used[a.p] then
			local best, bestGap = nil, math.huge
			for j, other in ipairs(list) do
				if j ~= i and not used[other.p] then
					local gap = abs(a.q.Trophies - other.q.Trophies)
					local waited = max(t - a.q.Since, t - other.q.Since)
					if gap <= C.QUEUE_GAP_BASE + C.QUEUE_GAP_PER_SECOND * waited and gap < bestGap then
						best, bestGap = other, gap
					end
				end
			end
			if best then
				local ok, why, culprit = startDuel(a.p, best.p)
				if ok then
					used[a.p], used[best.p] = true, true
					changed = true
				elseif culprit and St.queue[culprit] then
					St.queue[culprit] = nil
					used[culprit] = true
					changed = true
					sendLobby(culprit)
					notify(culprit, "Duel queue cancelled: " .. tostring(why), "info", 4)
				elseif not culprit then
					break -- no free ring: the rest waits for the next second
				end
			end
		end
	end
	if changed then
		sendLobbyToQueue()
	end
end

----------------------------------------------------------------------
-- Trials (private pockets)
----------------------------------------------------------------------
function BattleService.StartTrial(player, level)
	local ok, why = canBattle(player)
	if not ok then
		return false, why
	end
	if not isInteger(level) then
		return false, "Pick a trial level"
	end
	local count = tonumber(BattleCatalog.TrialCount) or #(BattleCatalog.Trials or {})
	if level < 1 or level > count or type(BattleCatalog.Trials) ~= "table" or not BattleCatalog.Trials[level] then
		return false, "That trial does not exist"
	end
	local rec = battleRecord(player)
	if not rec then
		return false, "Your data is still loading"
	end
	if level > 1 then
		local cleared = type(rec.TrialCleared) == "table" and rec.TrialCleared[level - 1] == true
		if not cleared and (tonumber(rec.TrialBest) or 0) < level - 1 then
			return false, "Beat Trial " .. (level - 1) .. " first"
		end
	end
	local portal = trialPortalPosition()
	if not portal then
		return false, "The Trial Portal is closed"
	end
	local root = aliveRoot(player)
	if (root.Position - portal).Magnitude > C.TRIAL_RANGE then
		return false, "Go to the Trial Portal to start a trial"
	end
	local spec, reason = teamOf(player, 1)
	if not spec then
		return false, reason
	end
	local builder = St.arenaBuilder
	if not hasFn(builder, "BuildPocket") then
		return false, "The trial arenas are closed"
	end
	local index = nil
	for i = 1, C.MAX_POCKETS do
		if not St.pocketBusy[i] then
			index = i
			break
		end
	end
	if not index then
		return false, "Every trial arena is busy. Try again soon!"
	end
	local okP, pocket = pcall(builder.BuildPocket, index)
	if not okP or type(pocket) ~= "table" or typeof(pocket.CFrame) ~= "CFrame" then
		warn("[BattleService] BuildPocket(" .. index .. ") failed: " .. tostring(pocket))
		return false, "The trial arena could not open"
	end
	local zone = zoneFrom(pocket.CFrame, pocket.Size, pocket.Zone)
	zone.Spawn = pocket.Spawn
	if typeof(zone.Spawn) ~= "CFrame" then
		zone.Spawn = lookFrom((pocket.CFrame * CFrame.new(0, 3, -(zone.Z / 2 - 5))).Position, pocket.CFrame.Position)
	end
	zone.Pocket = pocket
	zone.PocketIndex = index
	local id = newBattleId()
	local okS, sim, simWhy = pcall(BattleSim.new, {
		Mode = "Trial",
		Id = id,
		Seed = newSeed(),
		Zone = { X = zone.X, Z = zone.Z },
		Teams = { spec },
		Trial = level,
	})
	if not okS or type(sim) ~= "table" then
		warn("[BattleService] trial setup failed: " .. tostring(okS and simWhy or sim))
		pcall(builder.FreePocket, pocket)
		return false, "The trial could not start"
	end
	St.pocketBusy[index] = id
	stopWatching(player, "Joined")
	leaveLobby(player)
	local b = newBattle(id, "Trial", sim, zone)
	b.Level = level
	local trial = BattleCatalog.Trials[level]
	b.TrialInfo = { Level = level, Name = trial.Name, Chapter = trial.Chapter, MiniBoss = trial.MiniBoss == true }
	addParticipant(b, player, 1, spec)
	teleport(player, zone.Spawn)
	beginBattle(b)
	notify(player, "Trial " .. level .. ": " .. tostring(trial.Name) .. "! F = attack, R = retreat", "info", 4)
	return true, id
end

----------------------------------------------------------------------
-- The Champion Ring (Phase 4, contract 3.8): one RingRun per player, a fresh BattleSim per round in one private pocket.
-- Every helper lives in RingRun (see the header for the run record and the flow).
----------------------------------------------------------------------
-- TycoonService: from Init's deps, else the sibling module (resolved lazily; false = missing)
function RingRun.tycoon()
	local dep = St.deps.TycoonService
	if type(dep) == "table" then
		return dep
	end
	if St.tycoonService == nil then
		St.tycoonService = false
		local folder = script.Parent
		local inst = folder and folder:FindFirstChild("TycoonService")
		if inst then
			local ok, mod = pcall(require, inst)
			if ok and type(mod) == "table" then
				St.tycoonService = mod
			end
		end
	end
	return St.tycoonService or nil
end

-- the Position of a part, a model (its pivot) or an ArenaInfo entry { Pad | Part | Model | CFrame | Position }
function RingRun.positionOf(thing)
	if type(thing) == "table" then
		if typeof(thing.Position) == "Vector3" then
			return thing.Position
		end
		if typeof(thing.CFrame) == "CFrame" then
			return thing.CFrame.Position
		end
		return RingRun.positionOf(thing.Pad or thing.Part or thing.Model)
	end
	if typeof(thing) ~= "Instance" or not thing:IsDescendantOf(Workspace) then
		return nil
	end
	if thing:IsA("BasePart") then
		return thing.Position
	end
	local ok, cf = pcall(function()
		return thing:GetPivot()
	end)
	if ok and typeof(cf) == "CFrame" then
		return cf.Position
	end
	return nil
end

-- the Portal_Ring model in the workspace (cached; nil in a build without one)
function RingRun.portalModel()
	local model = St.ringPortal
	if not (typeof(model) == "Instance" and model:IsDescendantOf(Workspace)) then
		model = Workspace:FindFirstChild("Portal_Ring", true)
		St.ringPortal = model
	end
	return model
end

-- where ring starts are accepted: ArenaInfo.RingPortal, else the Portal_Ring model, else the Trial Portal (the
-- contract's zero-part fallback: the Ring prompt sits on Portal_Trials)
function RingRun.portalPosition()
	local info = arena()
	local pos = info and RingRun.positionOf(info.RingPortal)
	if pos then
		return pos
	end
	pos = RingRun.positionOf(RingRun.portalModel())
	if pos then
		return pos
	end
	return trialPortalPosition()
end

-- the instances that carry the RingBoard attribute (Portal_Ring and ArenaInfo.RingPortal's part / model)
function RingRun.portalInstances()
	local out, seen = {}, {}
	local function add(inst)
		if typeof(inst) == "Instance" and not seen[inst] then
			seen[inst] = true
			out[#out + 1] = inst
		end
	end
	add(RingRun.portalModel())
	local info = arena()
	local portal = info and info.RingPortal
	if type(portal) == "table" then
		add(portal.Model)
		add(portal.Pad)
		add(portal.Part)
	else
		add(portal)
	end
	return out
end

-- the owned keys (PetKeys.List), {} without a profile
function RingRun.ownedKeys(player)
	local profile = try(dataService(), "GetProfile", player)
	if type(profile) ~= "table" or not PetKeys or type(PetKeys.List) ~= "function" then
		return {}
	end
	local ok, list = pcall(PetKeys.List, profile)
	if ok and type(list) == "table" then
		return list
	end
	return {}
end

-- The ring's fighters, in the contract's order: the active team (training pets skipped), else the equipped keys, else
-- the best owned pets by UnitPower; training pets skipped everywhere; at most GetTeams().Slots. -> keys, source
function RingRun.fighters(player, owned)
	local DS = dataService()
	local training = try(DS, "TrainingKeys", player)
	if type(training) ~= "table" then
		training = {}
	end
	local teams = try(DS, "GetTeams", player)
	local slots = (type(teams) == "table" and tonumber(teams.Slots)) or 3
	local function pick(list)
		local out, seen = {}, {}
		for _, key in ipairs(type(list) == "table" and list or {}) do
			if #out >= slots then
				break
			end
			if type(key) == "string" and not training[key] and not seen[key] then
				seen[key] = true
				out[#out + 1] = key
			end
		end
		return out
	end
	local keys = pick(try(DS, "ActiveTeamKeys", player))
	if #keys > 0 then
		return keys, "Team"
	end
	local equipped = try(St.deps.PetService, "GetEquipped", player)
	local profile = try(DS, "GetProfile", player)
	if type(equipped) ~= "table" and type(profile) == "table" then
		equipped = profile.Equipped
	end
	keys = pick(equipped)
	if #keys > 0 then
		return keys, "Equipped"
	end
	local scored = {}
	for _, key in ipairs(type(owned) == "table" and owned or {}) do
		if type(key) == "string" and not training[key] and PetKeys then
			local okD, def = pcall(PetKeys.DefOf, key, profile)
			if okD and type(def) == "table" and type(def.Stats) == "table" then
				local okP, parsed = pcall(PetKeys.Parse, key)
				local level = try(DS, "GetPetLevel", player, key)
				local power = 0
				if BattleCatalog and type(BattleCatalog.UnitPower) == "function" then
					local okU, p = pcall(BattleCatalog.UnitPower, def, isInteger(level) and level or 1, (okP and type(parsed) == "table" and parsed.Tier) or "Normal", try(DS, "GetGrowth", player, key))
					if okU and finite(p) then
						power = p
					end
				end
				scored[#scored + 1] = { Key = key, Power = power, Order = #scored }
			end
		end
	end
	table.sort(scored, function(x, y)
		if x.Power ~= y.Power then
			return x.Power > y.Power
		end
		return x.Order < y.Order
	end)
	local list = {}
	for _, s in ipairs(scored) do
		list[#list + 1] = s.Key
	end
	return pick(list), "Best"
end

-- the climber's garden income per second (0 without a home / garden pets: the floor only)
function RingRun.income(player)
	local v = try(RingRun.tycoon(), "IncomePerSecond", player)
	if finite(v) and v > 0 then
		return v
	end
	return 0
end

-- the share of the enemy side's HP a result says the player's side dealt (the loss-XP gate), 0..1
function RingRun.dealtShare(res)
	local left = type(res) == "table" and type(res.Hp) == "table" and tonumber(res.Hp[2]) or nil
	if not finite(left) then
		return 0
	end
	return max(0, min(1, 1 - left))
end

function RingRun.intermission()
	local R = BattleCatalog and BattleCatalog.Ring
	local s = type(R) == "table" and tonumber(R.Intermission) or 3
	if not finite(s) or s < 0 then
		s = 3
	end
	return s
end

-- "2,571" for the toasts (whole Cash)
function RingRun.money(n)
	local s = tostring(floor((tonumber(n) or 0) + 0.5))
	local out = s
	while true do
		local k
		out, k = out:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return out
end

-- the result card data of a run (final "End" Rewards.Run; `round` = the round the run ended on)
function RingRun.summary(run, round)
	if type(run) ~= "table" then
		return { Wins = 0, Cash = 0, Xp = 0, Tokens = 0, Round = round or 1, Start = 1, Best = 0 }
	end
	return {
		Wins = run.Wins,
		Cash = run.Cash,
		Xp = run.Xp,
		Tokens = run.Tokens,
		Round = round or run.Round,
		Start = run.Start,
		Record = run.Record, -- the round of the new record set in this run, or nil
		Best = max(tonumber(run.Best0) or 0, tonumber(run.Record) or 0),
	}
end

-- "Run over after round 12: 11 wins, +$2,571, +806 XP. New record: round 11!"
function RingRun.cardText(run, round)
	local s = RingRun.summary(run, round)
	local text = "Run over after round " .. tostring(s.Round) .. ": " .. s.Wins .. (s.Wins == 1 and " win" or " wins")
	if s.Wins > 0 then
		text = text .. ", +$" .. RingRun.money(s.Cash) .. ", +" .. s.Xp .. " XP"
	end
	if s.Record then
		text = text .. ". New record: round " .. s.Record .. "!"
	else
		text = text .. "."
	end
	return text
end

-- "Start".Ring: { Round, Best, Start, Champion = { PetId, Level, Tier, Boss, Name } }
function RingRun.startInfo(b)
	local run = b.Ring
	local ch = type(b.Champion) == "table" and b.Champion or {}
	return {
		Round = b.Round or (run and run.Round) or 1,
		Best = run and max(tonumber(run.Best0) or 0, tonumber(run.Record) or 0) or 0,
		Start = run and run.Start or 1,
		Champion = { PetId = ch.PetId, Level = ch.Level, Tier = ch.Tier, Boss = ch.Boss == true, Name = ch.Name },
	}
end

-- the final "End" rewards of a run that ended between two rounds (nothing is paid: the last round was already paid)
function RingRun.finalRewards(run, round)
	local rw = emptyRewards()
	rw.Cash = 0
	rw.Round = round
	rw.Won = false
	rw.Final = true
	rw.Run = RingRun.summary(run, round)
	return rw
end

-- Ring.Runs + 1 exactly once per run (written the moment the run ends: on a leave it travels with the leave save),
-- then the RingBoard
function RingRun.closeRecord(run)
	if run.Recorded then
		return
	end
	run.Recorded = true
	local DS = dataService()
	if type(try(DS, "GetProfile", run.Player)) == "table" then
		try(DS, "MutateRing", run.Player, function(ring)
			ring.Runs = (tonumber(ring.Runs) or 0) + 1
		end)
	end
	RingRun.updateBoard(run)
end

-- the best records seen in this server -> the Portal_Ring attribute RingBoard = "Alex|31;Sam|24;Kim|20"
function RingRun.updateBoard(run)
	local best = max(tonumber(run.Best0) or 0, tonumber(run.Record) or 0)
	local ring = try(dataService(), "GetRing", run.Player)
	if type(ring) == "table" then
		best = max(best, tonumber(ring.Best) or 0)
	end
	if best <= 0 then
		return
	end
	local entry = St.ringBoard[run.UserId]
	if not entry or best > entry.Best then
		St.ringBoard[run.UserId] = { Name = run.Name, Best = best }
	end
	RingRun.writeBoard()
end

function RingRun.writeBoard()
	local list = {}
	for _, e in pairs(St.ringBoard) do
		list[#list + 1] = e
	end
	table.sort(list, function(x, y)
		if x.Best ~= y.Best then
			return x.Best > y.Best
		end
		return x.Name < y.Name
	end)
	local parts = {}
	for i = 1, min(3, #list) do
		parts[i] = tostring(list[i].Name):gsub("[|;]", "") .. "|" .. tostring(list[i].Best)
	end
	local text = table.concat(parts, ";")
	if text == St.ringBoardText then
		return
	end
	St.ringBoardText = text
	for _, inst in ipairs(RingRun.portalInstances()) do
		pcall(function()
			inst:SetAttribute("RingBoard", text)
		end)
	end
end

-- the rewards of one ring round (payOnce -> PAY.Ring): a WIN pays Cash (seconds of the climber's own garden income,
-- the floor, x3 on a new record decided inside ONE MutateRing together with the first boss clear's Tokens) and XP to
-- every team pet; the round that ENDS the run pays a third of its XP under the trial-loss gate (never for a forfeit,
-- a leave or a shutdown) and carries the result card data (Final, Run)
function RingRun.pay(b, part, res)
	local run = b.Ring
	local player = part.Player
	local round = tonumber(b.Round) or (run and run.Round) or 1
	local R = BattleCatalog.Ring or {}
	local winXp = (tonumber(R.XpBase) or 20) + (tonumber(R.XpPerRound) or 6) * round
	local rw = emptyRewards()
	rw.Cash, rw.Round, rw.Won = 0, round, false
	if res.WinnerSide == 1 and not part.Forfeited and not part.Left then
		local isRecord = false
		local okM = try(dataService(), "MutateRing", player, function(ring)
			if round > (tonumber(ring.Best) or 0) then
				ring.Best = round
				isRecord = true
			end
		end)
		isRecord = okM == true and isRecord
		local rewards = BattleCatalog.RingRewards(round, RingRun.income(player), isRecord)
		local cash = tonumber(rewards.Cash) or 0
		if cash > 0 and try(dataService(), "AddCash", player, cash) ~= true then
			cash = 0
		end
		local tokens = tonumber(rewards.Tokens) or 0
		grantTokens(player, tokens)
		rw.LevelUps = grantXp(player, part.Keys, winXp, "Ring")
		rw.Cash, rw.Xp, rw.Tokens, rw.Record, rw.Next, rw.Won = cash, winXp, tokens, isRecord, round + 1, true
		rw.Seconds = rewards.Seconds
		if run then
			run.Wins = run.Wins + 1
			run.Cash = run.Cash + cash
			run.Xp = run.Xp + winXp
			run.Tokens = run.Tokens + tokens
			if isRecord then
				run.Record = round
			end
		end
		local text = "Round " .. round .. " won! +$" .. RingRun.money(cash) .. ", +" .. winXp .. " XP"
		if isRecord then
			text = text .. " (new record: x3 Cash!)"
		end
		if tokens > 0 then
			text = text .. " +" .. tokens .. " Tokens"
		end
		notify(player, text, "good", 4)
		return rw
	end
	local xp = 0
	if not part.Forfeited and not part.Left and res.Reason ~= "Shutdown" and res.Reason ~= "Error" and type(BattleCatalog.LossXp) == "function" then
		local okL, lossXp = pcall(BattleCatalog.LossXp, winXp, res.Duration, RingRun.dealtShare(res))
		if okL and finite(lossXp) and lossXp > 0 then
			xp = floor(lossXp)
		end
	end
	if xp > 0 then
		rw.LevelUps = grantXp(player, part.Keys, xp, "Ring")
	end
	rw.Xp = xp
	if run then
		run.Xp = run.Xp + xp
	end
	rw.Final = true
	rw.Run = RingRun.summary(run, round)
	notify(player, RingRun.cardText(run, round), "info", 6)
	return rw
end

-- a free index of the shared pocket pool (trials and ring runs)
function RingRun.freePocketIndex()
	for i = 1, C.MAX_POCKETS do
		if not St.pocketBusy[i] then
			return i
		end
	end
	return nil
end

-- ArenaBuilder.BuildPocket(index, "Ring") under pcall; the trial pocket is the fallback. -> pocket info | nil
function RingRun.buildPocket(builder, index)
	local okP, pocket = pcall(builder.BuildPocket, index, "Ring")
	if okP and type(pocket) == "table" and typeof(pocket.CFrame) == "CFrame" then
		return pocket
	end
	warn("[BattleService] BuildPocket(" .. index .. ", Ring) failed: " .. tostring(pocket) .. " (the trial pocket stands in)")
	okP, pocket = pcall(builder.BuildPocket, index)
	if okP and type(pocket) == "table" and typeof(pocket.CFrame) == "CFrame" then
		return pocket
	end
	warn("[BattleService] BuildPocket(" .. index .. ") failed: " .. tostring(pocket))
	return nil
end

-- starts the run's current round: a fresh BattleSim in the run's pocket; the new InBattle id is written by
-- addParticipant BEFORE the previous battle lets the player go (no gap). -> ok, battleId | reason
function RingRun.startRound(run)
	local player = run.Player
	if St.ringRuns[player] ~= run or run.State == "Ending" or run.State == "Ended" then
		return false, "The run is over"
	end
	if St.closing then
		return false, "The server is restarting: battles will be back in a moment"
	end
	if not isPlayer(player) or not aliveRoot(player) then
		return false, "Wait until you respawn"
	end
	local spec, reason = teamOf(player, 1, run.Keys)
	if not spec then
		return false, reason
	end
	local okC, champion = pcall(BattleCatalog.ChampionTeam, run.Round, run.Seed)
	if not okC or type(champion) ~= "table" or type(champion.Pets) ~= "table" then
		warn("[BattleService] ChampionTeam(" .. tostring(run.Round) .. ") failed: " .. tostring(champion))
		return false, "The Champion Ring could not start"
	end
	local R = BattleCatalog.Ring or {}
	local id = newBattleId()
	local okS, sim, simWhy = pcall(BattleSim.new, {
		Mode = "Ring",
		Id = id,
		Seed = newSeed(),
		Round = run.Round,
		Zone = { X = run.Zone.X, Z = run.Zone.Z },
		Teams = { spec, champion },
		TimeLimit = tonumber(R.TimeLimit) or 90,
	})
	if not okS or type(sim) ~= "table" then
		warn("[BattleService] ring round setup failed: " .. tostring(okS and simWhy or sim))
		return false, "The Champion Ring could not start"
	end
	local b = newBattle(id, "Ring", sim, run.Zone)
	b.Ring = run
	b.Round = run.Round
	b.Champion = champion.Champion
	run.LastId = id
	run.Battle = b
	run.State = "Fighting"
	addParticipant(b, player, 1, spec) -- St.battleOf + InBattle move to the new round at once
	St.pocketBusy[run.PocketIndex] = id
	beginBattle(b)
	return true, id
end

-- the intermission timer fired: the next round of a run that is still waiting for it
function RingRun.nextRound(run, round)
	local player = run.Player
	if St.ringRuns[player] ~= run or run.State ~= "Intermission" or run.Round ~= round then
		return
	end
	if St.closing then
		RingRun.endRun(run, nil, "Shutdown")
		return
	end
	if not isPlayer(player) or not aliveRoot(player) then
		RingRun.endRun(run, nil, "Left")
		return
	end
	local ok, why = RingRun.startRound(run)
	if not ok then
		notify(player, why or "The Champion Ring could not continue", "bad", 4)
		RingRun.endRun(run, nil, "Error")
	end
end

-- after a ring battle's rewards and "End" went out (finalizeBody): a WIN keeps the participant and chains the next
-- round; anything else ends the run the trial way
function RingRun.afterBattle(b, result)
	local run = b.Ring
	if not run then
		task.delay(C.TRIAL_RETURN_DELAY, function()
			pcall(finishTrial, b)
		end)
		return
	end
	local player = run.Player
	if result.Won == true and run.State == "Fighting" and St.ringRuns[player] == run and isPlayer(player) and not St.closing then
		run.State = "Intermission"
		run.Round = run.Round + 1
		run.Battle = nil
		run.Strikes = 0
		St.pocketBusy[run.PocketIndex] = run.Id -- the pocket stays ours between the rounds
		unregister(b) -- the battle is over; the participant record keeps the player InBattle until the next Start
		local round = run.Round
		task.delay(RingRun.intermission(), function()
			local ok, err = pcall(RingRun.nextRound, run, round)
			if not ok then
				warn("[BattleService] ring round " .. tostring(round) .. " failed: " .. tostring(err))
				pcall(RingRun.endRun, run, nil, "Error")
			end
		end)
		return
	end
	RingRun.endRun(run, b, result.Reason)
end

-- the run is over (b = its last battle, nil when it ended between two rounds): Ring.Runs + 1 and the RingBoard now,
-- the final "End" when no battle carried it, the return teleport + release + FreePocket TRIAL_RETURN_DELAY later
function RingRun.endRun(run, b, reason)
	if run.State == "Ending" or run.State == "Ended" then
		return
	end
	run.State = "Ending"
	run.Battle = nil
	local player = run.Player
	RingRun.closeRecord(run)
	if b == nil and isPlayer(player) then
		-- between two rounds: the client only knows the last round was won; the result card data goes out now
		local round = max(1, (tonumber(run.Round) or 1) - 1)
		send(player, "End", {
			BattleId = run.LastId,
			Mode = "Ring",
			Round = round,
			Rewards = RingRun.finalRewards(run, round),
			Outcome = "Left",
			Won = false,
			Spectator = false,
			Reason = reason or "Left",
		}, run.LastId)
		if reason ~= "Forfeit" then
			notify(player, RingRun.cardText(run, round), "info", 6)
		end
	end
	task.delay(C.TRIAL_RETURN_DELAY, function()
		local ok, err = pcall(RingRun.finish, run, b)
		if not ok then
			warn("[BattleService] ring cleanup failed: " .. tostring(err))
		end
	end)
end

-- the cleanup of an ended run: back to the portal (a player still at the pocket), the participant released, the
-- pocket freed, the run forgotten
function RingRun.finish(run, b)
	local player = run.Player
	if St.ringRuns[player] == run then
		St.ringRuns[player] = nil
	end
	if isPlayer(player) then
		local root = aliveRoot(player)
		if root then
			local x, _, z = zoneLocal(run.Zone, root.Position)
			if sqrt(x * x + z * z) <= C.POCKET_LEASH + 40 then
				teleport(player, returnCFrame({ Origin = run.Origin }, "Ring"))
			end
		end
	end
	local held = St.battleOf[player]
	if held and held.Ring == run then
		St.battleOf[player] = nil
		setInBattle(player, nil)
		if isPlayer(player) then
			St.watchCooldown[player] = { [held.Id] = now() + C.SPECTATE_COOLDOWN }
		end
	end
	if b then
		unregister(b)
	end
	local index = run.PocketIndex
	if index then
		local busy = St.pocketBusy[index]
		if busy == run.Id or (b and busy == b.Id) or busy == run.LastId then
			if hasFn(St.arenaBuilder, "FreePocket") then
				pcall(St.arenaBuilder.FreePocket, run.Pocket or index)
			end
			St.pocketBusy[index] = nil
		end
	end
	run.State = "Ended"
end

-- the fail-safe path (forceRelease of a ring battle): the record closed, the run forgotten (the pocket is freed by
-- forceRelease itself)
function RingRun.abandon(run)
	RingRun.closeRecord(run)
	if St.ringRuns[run.Player] == run then
		St.ringRuns[run.Player] = nil
	end
	local index = run.PocketIndex
	if index and St.pocketBusy[index] == run.Id then
		if hasFn(St.arenaBuilder, "FreePocket") then
			pcall(St.arenaBuilder.FreePocket, run.Pocket or index)
		end
		St.pocketBusy[index] = nil
	end
	run.State = "Ended"
end

-- the way out of a running ring round (Forfeit, the leash, a respawn, an obby match, a disconnect): the record is
-- closed at once (a leaver's Runs + 1 travels with the leave save), then the round is forfeited like a trial
function RingRun.dropOut(b, part, why)
	local run = b.Ring
	if run and St.ringRuns[run.Player] == run and run.State == "Fighting" then
		-- the run stays "Fighting" until its battle ends (finalizeBody -> afterBattle -> endRun does the cleanup);
		-- only the record is closed now, so a leaver's Runs + 1 is in the profile before the leave save
		run.Dropped = true
		RingRun.closeRecord(run)
	end
	return forfeitTrial(b, part, why)
end

-- PlayerRemoving: a run between two rounds ends now (a run mid-round was closed by dropOut and ends with its battle)
function RingRun.leave(run)
	if run.State == "Intermission" then
		RingRun.endRun(run, nil, "Left")
	elseif run.State == "Fighting" then
		RingRun.closeRecord(run)
	end
end

-- the presence check of a run between two rounds (monitorTick): alive, not in an obby match, at the pocket
function RingRun.monitor(run)
	local player = run.Player
	if run.State ~= "Intermission" or St.ringRuns[player] ~= run then
		return
	end
	if not isPlayer(player) then
		RingRun.endRun(run, nil, "Left")
		return
	end
	if player:GetAttribute(Config.Attr.InMatch) == true then
		notify(player, "You left the battle for an obby match.", "info", 4)
		RingRun.endRun(run, nil, "Left")
		return
	end
	local root = aliveRoot(player)
	local here = false
	if root then
		local x, y, z = zoneLocal(run.Zone, root.Position)
		here = sqrt(x * x + z * z) <= C.POCKET_LEASH and y <= 220
		if here and y < -C.POCKET_FALL and run.Zone.Spawn then
			teleport(player, run.Zone.Spawn) -- slipped off the pocket between two rounds: back on the spawn
		end
	end
	if here then
		run.Strikes = 0
		return
	end
	run.Strikes = (run.Strikes or 0) + 1
	if run.Strikes >= C.OUT_STRIKES then
		notify(player, "You left the ring: the run is over.", "bad", 4)
		RingRun.endRun(run, nil, "Left")
	end
end

-- BattleRequest("Ring", startRound) -> the entry checks of contract 3.8, IN ORDER, each with its toast; then the run
function BattleService.StartRing(player, startRound)
	if not isPlayer(player) then
		return false, "That player is not here"
	end
	if not BattleSim or not BattleCatalog or not PetKeys or type(BattleCatalog.ChampionTeam) ~= "function" or type(BattleCatalog.RingRewards) ~= "function" then
		return false, "Battles are not ready yet"
	end
	-- 1) a home claimed this session
	if type(try(RingRun.tycoon(), "GetPlot", player)) ~= "table" then
		return false, "Claim your home first"
	end
	-- 2) at least one owned pet
	local owned = RingRun.ownedKeys(player)
	if #owned == 0 then
		return false, "You need a pet"
	end
	-- 3) the fighters: the team, else the equipped pets, else the best owned pets (training pets skipped)
	local keys, source = RingRun.fighters(player, owned)
	if #keys == 0 then
		return false, "Your pets are all training right now"
	end
	-- 4) free to battle
	local ok, why = canBattle(player)
	if not ok then
		return false, why
	end
	-- 5) at the Champion Ring portal
	local portal = RingRun.portalPosition()
	local root = aliveRoot(player)
	if not portal or not root or (root.Position - portal).Magnitude > C.RING_RANGE then
		return false, "Walk to the Champion Ring portal"
	end
	-- 6) the save is loaded and not provisional
	local DS = dataService()
	local ring = try(DS, "GetRing", player)
	if type(ring) ~= "table" or try(DS, "IsProvisional", player) == true then
		return false, "Your save is still loading, try again in a moment"
	end
	-- 7) the start round: 1, or a boss round the player already beat
	local R = BattleCatalog.Ring or {}
	local every = tonumber(R.BossEvery) or 10
	local first = startRound
	if first == nil then
		first = 1
	end
	if not isInteger(first) or first < 1 or first > (tonumber(R.MaxRound) or 100000) then
		return false, "Start from round 1 or a boss round you beat"
	end
	if first > 1 and (first % every ~= 0 or (tonumber(ring.Best) or 0) < first) then
		return false, "Start from round 1 or a boss round you beat"
	end
	-- 8) the spec (the keys stay fixed for the whole run)
	local spec, reason = teamOf(player, 1, keys)
	if not spec then
		return false, reason
	end
	-- 9) the pocket
	local builder = St.arenaBuilder
	if not hasFn(builder, "BuildPocket") then
		return false, "The Champion Ring is closed"
	end
	local index = RingRun.freePocketIndex()
	if not index then
		return false, "Every ring is busy. Try again soon!"
	end
	local pocket = RingRun.buildPocket(builder, index)
	if not pocket then
		return false, "The Champion Ring could not open"
	end
	local zone = zoneFrom(pocket.CFrame, (type(BattleCatalog.Zones) == "table" and BattleCatalog.Zones.Ring) or { X = 44, Z = 44 }, pocket.Zone)
	zone.Spawn = pocket.Spawn
	if typeof(zone.Spawn) ~= "CFrame" then
		zone.Spawn = lookFrom((pocket.CFrame * CFrame.new(0, 3, -(zone.Z / 2 - 5))).Position, pocket.CFrame.Position)
	end
	zone.Pocket = pocket
	zone.PocketIndex = index
	St.ringSeq = St.ringSeq + 1
	local run = {
		Id = "R" .. St.ringSeq,
		Player = player,
		UserId = player.UserId,
		Name = shortName(player, 16),
		Pocket = pocket,
		PocketIndex = index,
		Zone = zone,
		Round = first,
		Start = first,
		Seed = newSeed(),
		Keys = keys,
		Source = source,
		Wins = 0,
		Cash = 0,
		Xp = 0,
		Tokens = 0,
		Record = nil,
		Best0 = tonumber(ring.Best) or 0,
		State = "Intermission",
		Battle = nil,
		LastId = nil,
		Recorded = false,
		Strikes = 0,
		Origin = root.CFrame,
	}
	St.ringRuns[player] = run
	St.pocketBusy[index] = run.Id
	stopWatching(player, "Joined")
	leaveLobby(player)
	teleport(player, zone.Spawn)
	local okR, idOrWhy = RingRun.startRound(run)
	if not okR then
		run.Recorded = true -- nothing happened: no run to count
		St.ringRuns[player] = nil
		if St.pocketBusy[index] == run.Id then
			if hasFn(builder, "FreePocket") then
				pcall(builder.FreePocket, pocket)
			end
			St.pocketBusy[index] = nil
		end
		teleport(player, root.CFrame)
		return false, idOrWhy or "The Champion Ring could not start"
	end
	local champion = type(spec) == "table" and St.battles[idOrWhy] and St.battles[idOrWhy].Champion or nil
	local who = (type(champion) == "table" and champion.Name) and (": " .. tostring(champion.Name)) or ""
	notify(player, "Champion Ring, round " .. first .. who .. "! F = attack, R = retreat, 1-4 = specials", "info", 4)
	return true, idOrWhy
end

-- { [key] = true }: the pet keys of the player's running battle or ring run (a run's fixed list also between rounds)
function BattleService.KeysInBattle(player)
	local set = {}
	if typeof(player) ~= "Instance" then
		return set
	end
	local run = St.ringRuns[player]
	if run and run.State ~= "Ended" then
		for _, key in ipairs(run.Keys) do
			set[key] = true
		end
	end
	local b = St.battleOf[player]
	if b and b.State == "Running" then
		local part = b.Parts[player.UserId]
		if part and not part.Left then
			for _, key in ipairs(part.Keys) do
				set[key] = true
			end
		end
	end
	return set
end

----------------------------------------------------------------------
-- Boss raids (EventService opens / ends them; players join inside the arena)
----------------------------------------------------------------------
local function bossName(bossId)
	local boss = BattleCatalog and type(BattleCatalog.Bosses) == "table" and BattleCatalog.Bosses[bossId]
	return (boss and boss.Name) or tostring(bossId)
end

local function raidEndedWithoutPlayers(raid, reason)
	if St.raid == raid then
		St.raid = nil
	end
	BattleService.BattleEnded:Fire(raid.Id, {
		BattleId = raid.Id,
		Mode = "Raid",
		Reason = reason or "NoPlayers",
		Winners = {},
		Losers = {},
		BossId = raid.BossId,
		Damage = {},
		Shares = {},
		Forfeit = false,
		Draw = false,
		Participants = {},
		Rewards = {},
		RewardsPaid = true,
	})
end

function BattleService.StartRaid(bossId)
	if not BattleSim or not BattleCatalog or type(BattleCatalog.Bosses) ~= "table" then
		return false, "Battles are not ready yet"
	end
	if St.raid then
		return false, "A raid is already running"
	end
	St.raidCount = (St.raidCount or 0) + 1
	if bossId == nil and type(BattleCatalog.NextBoss) == "function" then
		bossId = BattleCatalog.NextBoss(St.raidCount)
	end
	if type(bossId) ~= "string" or not BattleCatalog.Bosses[bossId] then
		return false, "Unknown boss"
	end
	local info = arena()
	if not info or type(info.Floor) ~= "table" or typeof(info.Floor.CFrame) ~= "CFrame" then
		return false, "The Battle Arena is closed"
	end
	local events = type(BattleCatalog.Events) == "table" and BattleCatalog.Events or {}
	local window = tonumber(events.JoinWindowSeconds) or 60
	local t = now()
	St.raid = { Id = newBattleId(), BossId = bossId, Opened = t, JoinUntil = t + window, Battle = nil }
	return true, St.raid.Id
end

-- where a raid team stands: on the floor's rim at its anchor's angle, looking at the boss
local function raidStand(b, uid)
	local okT, team = pcall(b.Sim.TeamOf, b.Sim, uid)
	local ax, az = 0, -1
	if okT and type(team) == "table" and type(team.Anchor) == "table" then
		ax, az = tonumber(team.Anchor.x) or 0, tonumber(team.Anchor.z) or -1
	end
	local len = sqrt(ax * ax + az * az)
	if len < 0.01 then
		ax, az, len = 0, -1, 1
	end
	local r = max(b.Zone.X, b.Zone.Z) / 2 + C.RAID_RIM
	local pos = (b.Zone.CFrame * CFrame.new(ax / len * r, 3, az / len * r)).Position
	return lookFrom(pos, b.Zone.CFrame.Position)
end

function BattleService.JoinRaid(player)
	local raid = St.raid
	if not raid then
		return false, "There is no boss raid right now"
	end
	local b = raid.Battle
	if b and b.Parts[player.UserId] then
		return false, b.Parts[player.UserId].Left and "You left this raid" or "You are already in the raid"
	end
	if now() > raid.JoinUntil then
		return false, "The raid has started. Join the next one!"
	end
	local ok, why = canBattle(player)
	if not ok then
		return false, why
	end
	if not playerInArena(player) then
		return false, "Go to the Battle Arena to join the raid"
	end
	local spec, reason = teamOf(player, 1)
	if not spec then
		return false, reason
	end
	if not b then
		local info = arena()
		if not info or type(info.Floor) ~= "table" or typeof(info.Floor.CFrame) ~= "CFrame" then
			return false, "The Battle Arena is closed"
		end
		local zone = zoneFrom(info.Floor.CFrame, info.Floor.Size, info.Floor.Zone)
		local okS, sim, simWhy = pcall(BattleSim.new, {
			Mode = "Raid",
			Id = raid.Id,
			Seed = newSeed(),
			Zone = { X = zone.X, Z = zone.Z },
			Teams = { spec },
			Boss = raid.BossId,
		})
		if not okS or type(sim) ~= "table" then
			warn("[BattleService] raid setup failed: " .. tostring(okS and simWhy or sim))
			return false, "The raid could not start"
		end
		b = newBattle(raid.Id, "Raid", sim, zone)
		b.BossId = raid.BossId
		raid.Battle = b
		stopWatching(player, "Joined")
		addParticipant(b, player, 1, spec)
		teleport(player, raidStand(b, player.UserId))
		beginBattle(b)
	else
		if b.State ~= "Running" then
			return false, "The raid is over"
		end
		local okA, infos, addWhy = pcall(b.Sim.AddTeam, b.Sim, spec)
		if not okA or type(infos) ~= "table" then
			warn("[BattleService] raid join failed: " .. tostring(okA and addWhy or infos))
			return false, "Could not join the raid"
		end
		if St.watching[player] == b then
			-- a spectator of this raid becomes a fighter: a fresh "Start" after the next step (not this Spawn event)
			St.watching[player] = nil
			b.Spectators[player] = nil
			b.Receivers[player] = nil
		else
			stopWatching(player, "Joined")
		end
		addParticipant(b, player, 1, spec)
		b.Pending[player] = true
		teleport(player, raidStand(b, player.UserId))
	end
	leaveLobby(player)
	BattleService.RaidJoined:Fire(player, b.Id)
	notify(player, "You joined the raid on " .. bossName(raid.BossId) .. "! RETREAT from glowing circles and lines.", "info", 4)
	return true, b.Id
end

function BattleService.LeaveRaid(player)
	local b = isPlayer(player) and St.battleOf[player]
	if not b or b.Mode ~= "Raid" or b.State ~= "Running" then
		return false, "You are not in a raid"
	end
	local part = b.Parts[player.UserId]
	if not part or part.Left then
		return false, "You are not in a raid"
	end
	leaveRaid(b, part, "You left the raid.")
	return true
end

-- ends the raid now: a running fight ends as a timeout (the participants get the raid's loss tier unless the boss
-- falls in that last step); a raid nobody joined just closes
function BattleService.EndRaid(reason)
	local raid = St.raid
	if not raid then
		return false
	end
	local b = raid.Battle
	if not b then
		raidEndedWithoutPlayers(raid, type(reason) == "string" and reason or "Ended")
		return true
	end
	if b.State == "Running" then
		local sim = b.Sim
		pcall(function()
			if type(sim.timeLimit) == "number" then
				sim.timeLimit = sim:Time()
			end
		end)
		stepOnce(b)
		if not simFinished(b) then
			-- the sim did not take the timeout: everybody leaves (an abandoned raid pays nothing)
			for _, part in ipairs(b.PartList) do
				if not part.Left then
					pcall(sim.RemoveTeam, sim, part.UserId)
				end
			end
			stepOnce(b)
		end
		flush(b)
		finalize(b, "Ended")
	end
	if St.raid == raid then
		St.raid = nil
	end
	return true
end

function BattleService.GetRaidStatus()
	local raid = St.raid
	if not raid then
		return nil
	end
	local t = now()
	local joinLeft = max(0, raid.JoinUntil - t)
	local status = {
		Active = true,
		BattleId = raid.Id,
		BossId = raid.BossId,
		Name = bossName(raid.BossId),
		Hp = 0,
		MaxHp = 0,
		Players = 0,
		EndsIn = secondsLeft(joinLeft),
		Enraged = false,
		Joinable = joinLeft > 0,
		JoinEndsIn = secondsLeft(joinLeft),
		Waiting = true,
	}
	local b = raid.Battle
	if b then
		local ok, bs = pcall(b.Sim.BossStatus, b.Sim)
		if ok and type(bs) == "table" then
			status.Hp = tonumber(bs.Hp) or 0
			status.MaxHp = tonumber(bs.MaxHp) or 0
			status.Players = tonumber(bs.Players) or 0
			status.EndsIn = secondsLeft(tonumber(bs.EndsIn) or 0)
			status.Enraged = bs.Enraged == true
			status.Name = bs.Name or status.Name
		end
		status.Waiting = false
		status.Joinable = joinLeft > 0 and b.State == "Running"
		status.Active = b.State == "Running"
	end
	return status
end

----------------------------------------------------------------------
-- Reads
----------------------------------------------------------------------
function BattleService.IsInBattle(player)
	return typeof(player) == "Instance" and St.battleOf[player] ~= nil
end

function BattleService.GetBattle(player)
	local b = typeof(player) == "Instance" and St.battleOf[player]
	if not b then
		return nil
	end
	local part = b.Parts[player.UserId]
	local okT, t = pcall(b.Sim.Time, b.Sim)
	local run = St.ringRuns[player]
	local state = b.State
	if run and run.State == "Intermission" then
		state = "Intermission" -- a ring run between two rounds (the next Start comes by itself)
	end
	return {
		BattleId = b.Id,
		Mode = b.Mode,
		Side = part and part.Side or 0,
		Level = b.Level,
		BossId = b.BossId,
		Round = (run and run.Round) or b.Round,
		State = state,
		T = okT and t or 0,
		Zone = { CFrame = b.Zone.CFrame, Size = Vector3.new(b.Zone.X, C.ZONE_HEIGHT, b.Zone.Z) },
	}
end

-- extra (tests, tools): a summary of every battle the service still tracks
function BattleService.ListBattles()
	local out = {}
	for _, id in ipairs(St.order) do
		local b = St.battles[id]
		if b then
			local players, receivers = {}, 0
			for _, part in ipairs(b.PartList) do
				players[#players + 1] = part.UserId
			end
			for _ in pairs(b.Receivers) do
				receivers = receivers + 1
			end
			local okT, t = pcall(b.Sim.Time, b.Sim)
			out[#out + 1] = {
				BattleId = b.Id,
				Mode = b.Mode,
				State = b.State,
				Players = players,
				Steps = b.Steps,
				T = okT and t or 0,
				Receivers = receivers,
				Level = b.Level,
				BossId = b.BossId,
				Round = b.Round,
				RingIndex = b.RingIndex,
				PocketIndex = b.Zone.PocketIndex,
			}
		end
	end
	return out
end

function BattleService.GetNetStats()
	local out = { Clients = {}, Max = 0 }
	local t = now()
	for uid, rec in pairs(St.net) do
		local elapsed = t - rec.since
		local current = elapsed > 0.5 and rec.bytes / elapsed or 0
		local rate = max(rec.rate, current)
		out.Clients[uid] = { Rate = rate, Last = rec.rate, Peak = max(rec.peak, current), Messages = rec.messages }
		if rate > out.Max then
			out.Max = rate
		end
	end
	return out
end

function BattleService.EstimateBytes(value)
	return estimateBytes(value)
end

function BattleService.SetArena(info, builder)
	if type(info) == "table" then
		St.arenaInfo = info
	end
	if type(builder) == "table" then
		St.arenaBuilder = builder
	end
end

----------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------
function BattleService.Forfeit(player)
	if typeof(player) ~= "Instance" then
		return false, "NoBattle"
	end
	local run = St.ringRuns[player]
	if run and run.State == "Intermission" then
		-- between two ring rounds: the run ends cleanly, the last round (already paid) is kept
		RingRun.endRun(run, nil, "Forfeit")
		notify(player, "You left the Champion Ring.", "info", 4)
		return true
	end
	local b = St.battleOf[player]
	if not b or b.State ~= "Running" then
		return false, "NoBattle"
	end
	local part = b.Parts[player.UserId]
	if not part or part.Left or part.Forfeited then
		return false, "NoBattle"
	end
	if b.Mode == "Raid" then
		leaveRaid(b, part, "You left the raid.")
	elseif b.Mode == "Duel" then
		forfeitDuel(b, part, "You forfeited the duel.")
	elseif b.Mode == "Ring" then
		RingRun.dropOut(b, part, "You left the Champion Ring.")
	else
		forfeitTrial(b, part, "You left the trial.")
	end
	return true
end

-- what BattleCommand does: only the caller's own team (the owner is always the caller), only in their running battle,
-- only from inside its zone (Forfeit works anywhere)
function BattleService.Command(player, action, arg)
	if not isPlayer(player) then
		return false, "NoPlayer"
	end
	-- Forfeit first: between two ring rounds the won round's battle is already Ended, and Forfeit does its own checks
	if action == "Forfeit" then
		return BattleService.Forfeit(player)
	end
	local b = St.battleOf[player]
	if not b or b.State ~= "Running" then
		return false, "NoBattle"
	end
	local part = b.Parts[player.UserId]
	if not part or part.Left or part.Forfeited then
		return false, "NoBattle"
	end
	if action ~= "Attack" and action ~= "Retreat" and action ~= "Special" then
		return false, "UnknownAction"
	end
	local root = aliveRoot(player)
	if not root or not insideZone(b.Zone, root.Position) then
		return false, "NotInZone"
	end
	local value = nil
	if action == "Attack" then
		if arg ~= nil then
			if not isInteger(arg) or arg < 1 or arg > C.MAX_UNIT_ID then
				return false, "BadTarget"
			end
			value = arg
		end
	elseif action == "Special" then
		if not isInteger(arg) or arg < 1 or arg > 4 then
			return false, "BadSlot"
		end
		value = arg
	end
	local ok, accepted, reason, extra = pcall(b.Sim.Command, b.Sim, player.UserId, action, value)
	if not ok then
		warn("[BattleService] command failed: " .. tostring(accepted))
		return false, "Error"
	end
	return accepted == true, reason, extra
end

----------------------------------------------------------------------
-- Presence monitor (twice a second): participants stay where their battle is; anchors follow the owners
----------------------------------------------------------------------
-- true while the participant is where they belong (trial: at their pocket; duel / raid: inside the arena)
local function present(b, part, root)
	local pos = root.Position
	if b.Mode == "Trial" or b.Mode == "Ring" then
		local x, y, z = zoneLocal(b.Zone, pos)
		if sqrt(x * x + z * z) > C.POCKET_LEASH or y > 220 then
			return false
		end
		if y < -C.POCKET_FALL and b.Zone.Spawn then
			teleport(part.Player, b.Zone.Spawn) -- slipped off the pocket: back on the spawn, no forfeit
		end
		return true
	end
	return inArena(pos)
end

local function monitorBattle(b)
	for _, part in ipairs(b.PartList) do
		if b.State ~= "Running" then
			return
		end
		if not part.Left and not part.Forfeited then
			local player = part.Player
			if not isPlayer(player) then
				dropOut(b, part, nil)
			elseif player:GetAttribute(Config.Attr.InMatch) == true then
				dropOut(b, part, b.Mode == "Raid" and "You left the raid for an obby match." or "You left the battle for an obby match.")
			else
				local root = aliveRoot(player)
				if root and present(b, part, root) then
					part.Strikes = 0
					local x, _, z = zoneLocal(b.Zone, root.Position)
					pcall(b.Sim.SetAnchor, b.Sim, part.UserId, x, z)
				else
					part.Strikes = part.Strikes + 1
					if part.Strikes >= C.OUT_STRIKES then
						local why
						if b.Mode == "Raid" then
							why = "You left the arena: you are out of the raid."
						elseif b.Mode == "Duel" then
							why = "You left the arena: the duel is lost."
						elseif b.Mode == "Ring" then
							why = "You left the ring: the run is over."
						else
							why = "You left the trial: it is lost."
						end
						dropOut(b, part, why)
					end
				end
			end
		end
	end
end

local function monitorTick()
	for _, b in ipairs(runningBattles()) do
		local ok, err = pcall(monitorBattle, b)
		if not ok then
			warn("[BattleService] monitor failed for " .. b.Id .. ": " .. tostring(err))
		end
	end
	-- ring runs between two rounds (no battle runs): the climber must stay at the pocket, alive and out of matches
	local runs = {}
	for _, run in pairs(St.ringRuns) do
		if run.State == "Intermission" then
			runs[#runs + 1] = run
		end
	end
	for _, run in ipairs(runs) do
		local ok, err = pcall(RingRun.monitor, run)
		if not ok then
			warn("[BattleService] ring monitor failed for " .. tostring(run.Id) .. ": " .. tostring(err))
		end
	end
end

local function housekeeping()
	expireInvites()
	pairQueue()
	refreshSpectators()
	local raid = St.raid
	if raid and not raid.Battle and now() >= raid.JoinUntil then
		raidEndedWithoutPlayers(raid, "NoPlayers")
	end
	-- forget old duel pairs
	local t = now()
	for key, list in pairs(St.pairs) do
		if #list == 0 or t - list[#list] >= C.PAIR_WINDOW then
			St.pairs[key] = nil
		end
	end
end

----------------------------------------------------------------------
-- Remotes
----------------------------------------------------------------------
local function takeToken(player, key, burst, refill)
	local rec = St.buckets[player]
	if not rec then
		rec = {}
		St.buckets[player] = rec
	end
	local t = now()
	local bucket = rec[key]
	if not bucket then
		bucket = { tokens = burst, t = t }
		rec[key] = bucket
	end
	bucket.tokens = min(burst, bucket.tokens + (t - bucket.t) * refill)
	bucket.t = t
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens = bucket.tokens - 1
	return true
end

local function cooldown(player, action, seconds)
	local rec = St.cooldowns[player]
	if not rec then
		rec = {}
		St.cooldowns[player] = rec
	end
	local t = now()
	local last = rec[action]
	if last and t - last < seconds then
		return false
	end
	rec[action] = t
	return true
end

local function onCommand(player, action, a)
	if not isPlayer(player) or type(action) ~= "string" or #action > C.MAX_ACTION_LENGTH then
		return
	end
	if not takeToken(player, "cmd", C.COMMAND_BURST, C.COMMAND_REFILL) then
		return
	end
	local ok, reason = BattleService.Command(player, action, a)
	if not ok then
		if reason == "NotInZone" then
			notify(player, "Step into the battle zone to command your pets.", "bad", 3)
		elseif reason == "Regrouping" then
			notify(player, "Your pets are regrouping...", "info", 2)
		end
	end
end

local function teamSet(player, preset, keys)
	if not isInteger(preset) or preset < 1 or preset > 3 then
		return false, "Pick a team from 1 to 3"
	end
	if type(keys) ~= "table" then
		return false, "That team is not valid"
	end
	local clean, n = {}, 0
	for k, v in pairs(keys) do
		n = n + 1
		if n > 8 or not isInteger(k) or k < 1 or k > 4 then
			return false, "That team is not valid"
		end
		if v ~= false and (type(v) ~= "string" or #v > C.MAX_KEY_LENGTH) then
			return false, "That team is not valid"
		end
		clean[k] = v
	end
	local DS = dataService()
	if not hasFn(DS, "SetTeam") then
		return false, "Teams are not ready yet"
	end
	local ok, why = try(DS, "SetTeam", player, preset, clean)
	if ok == true then
		notify(player, "Team " .. preset .. " saved.", "good", 2)
		return true
	end
	return false, type(why) == "string" and why or "That team is not valid"
end

local function teamSelect(player, preset)
	if not isInteger(preset) or preset < 1 or preset > 3 then
		return false, "Pick a team from 1 to 3"
	end
	local DS = dataService()
	if not hasFn(DS, "SelectTeam") then
		return false, "Teams are not ready yet"
	end
	local ok, why = try(DS, "SelectTeam", player, preset)
	if ok == true then
		notify(player, "Team " .. preset .. " is your battle team.", "good", 2)
		return true
	end
	return false, type(why) == "string" and why or "Pick a team from 1 to 3"
end

local function playerById(userId)
	if not isInteger(userId) or userId <= 0 then
		return nil
	end
	local p = Players:GetPlayerByUserId(userId)
	if isPlayer(p) then
		return p
	end
	return nil
end

local function onRequest(player, action, a, b)
	if not isPlayer(player) or type(action) ~= "string" or #action > C.MAX_ACTION_LENGTH then
		return
	end
	local gap = C.REQUEST_COOLDOWNS[action]
	if not gap then
		return
	end
	if not takeToken(player, "req", C.REQUEST_BURST, C.REQUEST_REFILL) or not cooldown(player, action, gap) then
		return
	end
	local ok, why = false, nil
	if action == "TeamSet" then
		ok, why = teamSet(player, a, b)
	elseif action == "TeamSelect" then
		ok, why = teamSelect(player, a)
	elseif action == "Trial" then
		if isInteger(a) then
			ok, why = BattleService.StartTrial(player, a)
		else
			why = "Pick a trial level"
		end
	elseif action == "Challenge" then
		local target = playerById(a)
		if target then
			ok, why = BattleService.Challenge(player, target)
		else
			why = "That player is not here"
		end
	elseif action == "ChallengeReply" then
		if isInteger(a) and type(b) == "boolean" then
			ok, why = BattleService.ReplyChallenge(player, a, b)
		else
			why = "That challenge has expired"
		end
	elseif action == "Queue" then
		ok, why = BattleService.Queue(player)
	elseif action == "Unqueue" then
		ok, why = BattleService.Unqueue(player)
	elseif action == "JoinRaid" then
		ok, why = BattleService.JoinRaid(player)
	elseif action == "LeaveRaid" then
		ok, why = BattleService.LeaveRaid(player)
	elseif action == "Ring" then
		-- Phase 4: the Champion Ring (a missing start round means round 1; junk is refused inside StartRing)
		ok, why = BattleService.StartRing(player, a)
	end
	if not ok and type(why) == "string" then
		notify(player, why, "bad", 3)
	end
end

local function onPlayerRemoving(player)
	local b = St.battleOf[player]
	if b and b.State == "Running" and not St.closing then
		local part = b.Parts[player.UserId]
		if part and not part.Left and not part.Forfeited then
			-- a duel leaver's loss (and a ring run's Runs + 1) is written right now, before their profile is saved
			dropOut(b, part, nil)
		end
	end
	local run = St.ringRuns[player]
	if run then
		-- a ring run between two rounds (no battle runs), or one whose record was not closed yet
		pcall(RingRun.leave, run)
	end
	St.battleOf[player] = nil
	if St.watching[player] then
		stopWatching(player, nil)
	end
	for _, other in pairs(St.battles) do
		other.Receivers[player] = nil
		other.Pending[player] = nil
		other.Spectators[player] = nil
	end
	if St.queue[player] then
		St.queue[player] = nil
		sendLobbyToQueue()
	end
	clearInvitesOf(player, true)
	St.buckets[player] = nil
	St.cooldowns[player] = nil
	St.toasts[player] = nil
	St.watchCooldown[player] = nil
	St.net[player.UserId] = nil
end

----------------------------------------------------------------------
-- Loops + Init
----------------------------------------------------------------------
-- Heartbeat: every running battle steps whenever its fixed 0.1 s steps are due (one snapshot per step at 60 fps, a
-- stalled frame runs at most MAX_CATCHUP steps in one message)
local function onHeartbeat()
	if not St.running or #St.order == 0 then
		return
	end
	local t = now()
	for _, b in ipairs(runningBattles()) do
		local ok, err = pcall(tickBattle, b, t)
		if not ok then
			b.TickErrors = b.TickErrors + 1
			warn("[BattleService] battle " .. b.Id .. " tick failed: " .. tostring(err))
			if b.TickErrors >= 5 and b.State == "Running" then
				b.Broken = 5
				pcall(finalize, b, "Error")
				if b.State == "Running" then
					forceRelease(b) -- even the end failed: free the players and forget the battle
				end
			end
		end
	end
end

-- game:BindToClose (tests call it too): every running battle ends void with Reason "Shutdown" (duels / trials pay
-- nothing and penalise nobody, raids pay the share so far), new battles are refused and leavers are no forfeits
function BattleService.Shutdown()
	St.closing = true
	for _, b in ipairs(runningBattles()) do
		local ok, err = pcall(function()
			local _, events = b.Sim:Abort("Shutdown")
			if type(events) == "table" then
				for _, ev in ipairs(events) do
					b.EventBuf[#b.EventBuf + 1] = ev
				end
			end
			flush(b)
		end)
		if not ok then
			warn("[BattleService] shutdown of " .. b.Id .. " failed: " .. tostring(err))
		end
		finalize(b, "Shutdown")
	end
	-- ring runs between two rounds (no battle runs) end too: Runs + 1, the pocket freed, the result card data
	local runs = {}
	for _, run in pairs(St.ringRuns) do
		if run.State == "Intermission" then
			runs[#runs + 1] = run
		end
	end
	for _, run in ipairs(runs) do
		local ok, err = pcall(RingRun.endRun, run, nil, "Shutdown")
		if not ok then
			warn("[BattleService] shutdown of ring run " .. tostring(run.Id) .. " failed: " .. tostring(err))
		end
	end
	local raid = St.raid
	if raid and not raid.Battle then
		raidEndedWithoutPlayers(raid, "Shutdown")
	end
	return true
end

-- extra (tests): reopens battles after a Shutdown()
function BattleService.SetClosing(flag)
	St.closing = flag == true
end

local function every(period, fn, label)
	task.spawn(function()
		while St.running do
			task.wait(period)
			local ok, err = pcall(fn)
			if not ok then
				warn("[BattleService] " .. label .. " failed: " .. tostring(err))
			end
		end
	end)
end

function BattleService.Init(deps)
	if St.initialized then
		return
	end
	St.initialized = true
	deps = type(deps) == "table" and deps or {}
	St.deps = deps
	if type(deps.ArenaBuilder) == "table" then
		St.arenaBuilder = deps.ArenaBuilder
	end
	if type(deps.ArenaInfo) == "table" then
		St.arenaInfo = deps.ArenaInfo
	end
	if not BattleSim or not BattleCatalog or not PetKeys then
		warn("[BattleService] BattleSim / BattleCatalog / PetKeys missing: battles are refused")
	end
	if not getRemote("BattleState") then
		warn("[BattleService] remote BattleState missing: clients will not see battles")
	end
	local commandRemote = getRemote("BattleCommand")
	if commandRemote then
		commandRemote.OnServerEvent:Connect(function(player, action, a)
			local ok, err = pcall(onCommand, player, action, a)
			if not ok then
				warn("[BattleService] BattleCommand failed: " .. tostring(err))
			end
		end)
	end
	local requestRemote = getRemote("BattleRequest")
	if requestRemote then
		requestRemote.OnServerEvent:Connect(function(player, action, a, b)
			local ok, err = pcall(onRequest, player, action, a, b)
			if not ok then
				warn("[BattleService] BattleRequest failed: " .. tostring(err))
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		local ok, err = pcall(onPlayerRemoving, player)
		if not ok then
			warn("[BattleService] PlayerRemoving failed: " .. tostring(err))
		end
	end)
	local okClose, closeErr = pcall(function()
		game:BindToClose(function()
			local ok, err = pcall(BattleService.Shutdown)
			if not ok then
				warn("[BattleService] Shutdown failed: " .. tostring(err))
			end
		end)
	end)
	if not okClose then
		warn("[BattleService] BindToClose failed: " .. tostring(closeErr))
	end
	-- players already in the game (Init runs after PlayerService): nobody starts in a battle
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute(C.ATTR_IN_BATTLE) ~= nil then
			setInBattle(player, nil)
		end
	end
	St.running = true
	RunService.Heartbeat:Connect(onHeartbeat)
	every(C.MONITOR_PERIOD, monitorTick, "monitor")
	every(C.HOUSEKEEPING_PERIOD, housekeeping, "housekeeping")
end

return BattleService
