-- DataService: persistent player profile (tokens, pets, items, stats, the v3 Pet Index / tutorial, the Phase 2
-- tycoon: Cash, Gems, Home, Food, pet levels, tier copies and fused hybrids, the Phase 3 battle teams and battle
-- record, and the Phase 4 pet growth (evolution stages, training), the Champion Ring record and the migration
-- markers) for Nimbus Climb.
--
-- Profile shape (ARCHITECTURE_V2.md section 1, ARCHITECTURE_V3.md section 1 + section 11 + "Phase 2 build contract" +
-- "Phase 3 build contract" + "Phase 4 build contract" section 4):
--   { Version = 2, Tokens, Pets = {[petId]=count}, Equipped = {key...}, Items = {[itemId]=count},
--     Stats = { Matches, Wins, TokensEarned, Spins, BestTimes = {[difficultyId]=seconds} }, SpotIndex,
--     -- v3
--     Discovered = {[petId]=true}, IndexClaimed = {[groupId]=true}, Tutorial = { Step, Done, Gifted },
--     -- Phase 2
--     Cash, Gems,
--     Home = { Level, Prestige, Stations = {[stationId]=level}, Garden = {[slot]=key}, Gym = {[slot]=key},
--              CollectorCash, LastSeen,
--              LegacySlots = n | nil, LegacyPrices = true | nil },     -- Phase 4 (veterans, see below)
--     Food = {[foodId]=count}, PetLevels = {[key]={Level, Xp}}, Tiers = {[petId]={Golden=n, Rainbow=n}},
--     Hybrids = {[uid]={Body, Style, Elements, Name, Rarity, Tier}}, GemReceipts = {[purchaseId]=os.time()},
--     -- Phase 3
--     Teams = { Presets = { [1..3] = {key, key, key, key?} }, Active = 1..3 },
--     Battle = { Trophies, TrialBest, TrialCleared = {[level]=true}, Raids, RaidBestDamage, PvPWins, PvPLosses,
--                EventPets = {[petId]=true} },
--     -- Phase 4 (new TOP-LEVEL fields only: a Phase 3 server still running during the rollout rebuilds Battle,
--     -- Teams, PetLevels entries and slot values from the keys it knows and would erase anything new inside them;
--     -- keepForeign writes unknown top-level and Home keys back untouched)
--     PetGrowth = { [key] = { Evo = 0..2, Speed, Physique, Ability, Defense = 0..10,
--                            Job = { Stat, Ends, Rank, Slot, From, Paid } | nil } },
--     Ring = { Best = 0..100000, Runs },
--     Migrations = { P4 = true, P5Dungeon = true, P5Home = true, P5MouseLock = true, B2GardenSolo = true },
--     -- Phase 5 (ARCHITECTURE_V3.md "Phase 5 build contract" section 9; new TOP-LEVEL fields + new Home keys again, so
--     -- a Phase 4 server still running during the rollout writes them back untouched through keepForeign)
--     Dungeon = { Best = 0..100, Cleared = {[floor]=true} (a dense boolean array in the store), Runs, Clears },
--     Berries = whole number >= 0 (left out while 0),
--     Settings = { Music 0..10, Sfx 0..10, Gfx "Auto"|"Low"|"High", Shake bool, SeenNotes 0..1000, MouseLock bool }
--       (left out while default),
--     Home.DecorCredit = 1..18 | nil, Home.LegacyMagnet = 1..5 | nil, Home.LegacyMagnetStar = the Prestige it was folded at }
--   Phase 5 rules: Teams hold 3 keys per preset (slot 1 = the fighter; a stored 4th key leaves the preset only, the pet
--   stays owned); Dungeon merges Best max / Cleared union / Runs delta / Clears delta (the P5Dungeon migration's own
--   Clears as a max, so two servers migrating one save do not double it); Berries merge as a +/- delta clamped at 0,
--   MINUS the session's own P5Home conversion when the store was already marked P5Home (its twin: two servers
--   converting one save's Food do not double the berries); the live session's Settings win; Food was converted into
--   berries ONCE by the P5Home step and is never written again.
--   Battle teams: a preset lists up to 3 UNIQUE keys in slot order (Phase 5: 3 always, slot 1 = the fighter; the
--   Phase 3 prestige unlock of a 4th slot is gone); every key needs a FREE copy: owned (PetKeys.Count) more often than it
--   works in the Garden or the Gym (bug batch 2 #18, "Remote recall": a Garden pet is BUSY gardening, it can neither
--   follow you (Equipped) nor fight; this replaces the Phase 4 rule "a Garden pet keeps earning at home while it follows
--   you and fights"; Phase 4 empties the Gym on its one-time migration). Only OPEN garden places lock (follow-up): a
--   copy on a place ABOVE the open count (TycoonCatalog.GardenSlots; a Prestige closed it, the pet sleeps there under
--   its "Prestige to open" sign and earns nothing) is not busy (P3.placedCopies skips it, P3.closedSlot); once it
--   follows or joins a preset it leaves that place silently (live: TycoonService after PetService.PerksChanged /
--   TeamsChanged, through ClosedBedOverlap; on load: P3.gardenSolo, closed places first, no toast; in the merge nothing
--   to do: the record keeps the pet with the player and the next load empties the bed). A key that loses its free copy (fused away,
--   released, a developer reset, its last copy placed in the Garden / Gym) is dropped from every preset ("pruned", the
--   pets behind it move up a slot): in every copy taken for a save or a snapshot, in the merge, and in the live profile
--   on every Sync and after a MutateHome that moved pets (TeamsChanged fires then). Equipped follows the same copy rule
--   (normalizeEquipped in the merge, PetService.Equip / its re-validation; TycoonService.GardenSet unequips the copy).
--   Bug batch 2 #18 old saves: a stored profile whose pet is BOTH in the Garden and equipped / in a preset (the Phase 4
--   rule allowed it) is repaired when it is read (P3.gardenSolo in normalizeProfile, before the presets are pruned): the
--   pet STAYS equipped / in its team and LEAVES the Garden (no player loses a fighter, no team is emptied). The repair
--   is deterministic and only acts on such an overlap, so it never loops; the load that moved pets records them
--   (MigratedNow(player, "B2GardenSolo") = { Keys }) and fires Migrated(player, "B2GardenSolo", info) once (TycoonService
--   shows the one explaining toast); the marker Migrations.B2GardenSolo is set on the first loaded, real profile.
--   THE MARKER IS A RECORD, NOT A GATE: the repair runs on EVERY normalizeProfile read (it is idempotent and a no-op
--   without an overlap). So an overlap written later (an old Phase 4 server during the rollout) is repaired again on
--   the next load, with the event and the toast again. Two outcomes, both deterministic and neither looping:
--     * on LOAD (normalizeProfile -> P3.gardenSolo, before the prune): the PLAYER wins: the pet stays equipped / in
--       its team and leaves the Garden;
--     * in the MERGE (applyDelta -> normalizeEquipped with Home, then P3.prune): the GARDEN wins: the placement the
--       other server wrote stands and the pet leaves Equipped / its presets (p5flow_merge pins it).
--   A Phase 2 profile (no Teams / Battle,
--   or the empty Teams reserve) gets the defaults: 3 empty presets, preset 1 active, a zeroed battle record.
--   Phase 4 pet growth, per KEY like levels: Evo is the evolution stage the player unlocked by pressing EVOLVE
--   (0..2; the boost counts only from the stored stage, never from the level alone); Speed / Physique / Ability /
--   Defense are the training ranks (0..10); Job is the running training job: Stat (one of the four), Ends (os.time()
--   when it completes), Rank (the TARGET rank = the stat's rank + 1, so two servers completing the same job give rank
--   3, not 4; a Job whose Rank is not above the stored rank was completed elsewhere and is dropped by P4.cleanGrowth),
--   Slot (the Training Place mat 1..5), From ("Follow" | "Garden:<slot>" | "Free": where the pet goes back to), Paid
--   (the Cash to refund on Stop). An all-zero entry without a Job is not kept.
--   THE TRAINING LOCK is a READ-TIME filter, one source of truth: TrainingKeys(player) = every key with a Job.
--   normalizeEquipped drops such keys from Equipped (a Phase 3 server may have equipped one during the rollout),
--   FieldableKeys and ActiveTeamKeys skip them; P3.checkTeam keeps accepting them in presets and P3.prune is NEVER
--   taught about training (it runs in normalizeProfile, copyProfile, applyDelta and MutateHome's pruneLive and would
--   delete the pet from its preset for good). Garden pets ARE busy (bug batch 2 #18: P3.placedCopies counts the OPEN
--   places of Home.Garden and Home.Gym; unlike training this is a write-time lock: GardenSet unequips the copy and the
--   prune drops the preset; a closed place does not lock, see the team rule above).
--   Ring: Best = the highest Champion Ring round won (0 = never), Runs = finished runs.
--   Migrations: one-time data migrations this profile went through (P4 = the Phase 4 migration, section 4.3).
--   Home.LegacySlots (a veteran's old garden size when it was above 3 + Prestige) and Home.LegacyPrices (true for a
--   veteran who had prestiged on Phase 3: base prices until the next prestige) are written ONLY by the Phase 4
--   migration and cleared by the next prestige (MutateHome clears both whenever the Home's Prestige rises).
--   Pet copies are identified by keys (shared/PetKeys.lua): "petId" (Normal), "petId@Golden", "petId@Rainbow",
--   "hyb:<uid>"; Equipped, PetLevels, Garden and Gym hold keys. Every plain petId of an old profile is a valid key.
--   Garden / Gym slots are whole numbers 1..64 (other valid string slot names are kept as they are).
--   Home.Rooms (the v3 reserve) was migrated into Home.Stations: in the live profile Home.Rooms is the SAME table as
--   Home.Stations (old code that touches Rooms still works); it is never written to the store again.
--   Every field is additive: a stored v2 / v3 profile lacks the newer fields and gets the defaults on load, and every
--   owned pet (Normal or tier copy) always counts as discovered. Version stays 2: no stored v2 field changed its
--   layout, so older tooling keeps reading it (older servers keep the new fields as foreign data, see below).
--
-- Design notes
--   * Everything runs from an in-memory cache, so the game is fully playable when DataStores are
--     unavailable (Studio without "Enable Studio Access to API Services", Roblox outages, ...).
--   * Saves are DELTA based. The cache remembers `Base` (what the store is known to contain);
--     a save sends only "live minus base" and merges it into whatever is stored right now inside
--     UpdateAsync. A failed load can therefore never wipe a saved profile and two servers touching
--     the same player cannot clobber each other. After a failed load, the next save (or a
--     background retry) re-reads the store and merges the session on top of it.
--     Merge rules: Discovered / IndexClaimed only ever grow (set union); Tutorial merges monotonically (Done and
--     Gifted stick once true) so a second server can never replay the tutorial gift; Tokens / Cash / Gems / Food
--     counts / Home.CollectorCash travel as +/- deltas; Home.Stations / Garden / Gym, Tiers, Hybrids and PetLevels
--     are replaced PER KEY when the session changed that key; GemReceipts only grow (bounded to the newest 100);
--     Teams merge PER PRESET (a preset the session changed replaces the stored one, Active is replaced when the
--     session changed it; afterwards the presets are pruned against the merged copies); Battle: Trophies / Raids /
--     PvPWins / PvPLosses travel as +/- deltas (never below 0), TrialBest / RaidBestDamage keep the higher value,
--     TrialCleared / EventPets only grow (union). Home: a HIGHER Home.Prestige wins the whole Home (prestige resets the stations, so
--     the other side's per-station changes are void); at equal prestige the Home merges per key (Level replaced,
--     LastSeen the later one). When both sides prestiged to that star (two runs from the same reset home), each
--     station keeps the higher level, the Home Level grows by what that adds and the session's Collector counts
--     from 0 (its prestige emptied it).
--     Cash follows the same prestige rule, because a prestige resets Cash too: a session that prestiged past the
--     store writes its balance (the Cash of the newest run), a session whose run the store prestiged past loses its
--     Cash delta (that run was reset), and when both sides prestiged to the same star the session's Cash since its
--     prestige joins the store's. A star reward (Gems) both sides paid counts once. Gem purchases: the receipt and
--     its gems merge together (MarkReceipt records the amount): a receipt the store already holds was granted by
--     another server, so its gems are not added again. Phase 4: PetGrowth merges PER KEY: Evo and every rank keep
--     the HIGHER value (never down; a rank is a target value, so two servers completing one job give one rank), the
--     Job is the session's value when the session changed it (a cleared job travels as `false` + the job it ended; a
--     job the session never touched leaves the stored one alone; a stored job that is NEWER than the one the session
--     ended or started, the same skill at a higher target, survives: two servers can race during the rollout or an
--     outage's late leave save), then P4.cleanGrowth drops a Job whose Rank is not above the merged rank (completed
--     elsewhere); a key the session removed travels as `false`. Ring.Best keeps the higher value,
--     Ring.Runs travels as a +/- delta. Migrations only grow (union). Home.LegacySlots / LegacyPrices merge with the
--     Home (per-key replace; a higher Prestige wins the whole Home, which has them cleared).
--     The ONE exception is ResetFields (developer tools only):
--     the fields it names are written over the stored ones at the next successful save instead of merged.
--   * A PROVISIONAL profile (the load failed while the DataStore is reachable, e.g. an outage) holds
--     defaults, not the player's data. One-time rewards must not be decided from it: GetTutorial
--     answers nil and SetTutorial refuses until the background recovery read the real save (then
--     ProfileRebased fires and TutorialService starts from the stored progress), and
--     IsProvisional(player) lets IndexService / DevService refuse claims and resets meanwhile. That
--     is what keeps a failed load from replaying the tutorial gift / finish reward. Per-key data would be
--     overwritten by stand-in values the same way, so GetHome answers nil, MutateHome only lets delta-safe changes
--     (CollectorCash, LastSeen) through and AddPetXp / MarkReceipt refuse while provisional; likewise GetTeams /
--     GetBattle answer nil, ActiveTeamKeys {}, SetTeam / SelectTeam refuse and MutateBattle only lets the fields
--     through that merge as deltas or best values (a first clear or an event pet is never decided from stand-in
--     data). AddTrophies keeps working (a delta). Phase 4: MutateGrowth / SetEvolution / MutateRing / SetPetLevel are
--     refused while provisional (training, evolution, their completion and ring records wait for the real save; the
--     ring does not start); GetRing / GetGrowthMap-based decisions answer nil / {} through TrainingKeys, ActiveTeamKeys
--     and FieldableKeys; MarkMigrated is allowed (a union); the Phase 4 migration does not run on a provisional
--     profile (it runs after the recovery, on ProfileRebased). Without a usable
--     store (Studio without API access) nothing is provisional: everything runs from memory.
--   * Forward compatibility: a save keeps every stored field this version does not know (top level,
--     inside Home and inside Stats) and a newer Version number, so a server still running an older build after
--     a later phase is published never erases that phase's data.
--   * v1 saves ({Tokens = n} in Config.Tokens.LegacyDataStoreName) are migrated once: when the v2
--     key is empty, the legacy key is read and its tokens become the starting balance. The legacy
--     store is never written.
--   * A leaving player's cache entry is only freed once the store holds everything it knows. If the
--     final save failed (outage, throttling, lock timeout, failed load that cannot be recovered), the
--     entry is kept as an "orphan": it is retried in the background with backoff, flushed by the
--     autosave sweep (which walks the cache, not the player list) and by BindToClose, and a quick
--     rejoin simply picks it up again. It is only dropped after a successful write or after
--     ORPHAN_TIMEOUT seconds. DataService alone makes this decision (Release); callers just call it.
--     The leave save starts only after the other PlayerRemoving handlers ran (task.defer), so what they write
--     at leave time (PetCareService refunds the dishes still cooking) is still in the cache and travels with
--     that save or with its orphan retry; a save started at once had nothing to write when the session was
--     already saved, returned without yielding, and Release dropped the entry before those handlers ran.
--   * The store never holds a sparse array: Garden / Gym are written as arrays with "" for empty slots (or a map
--     with string keys when a slot has a name); empty Phase 2 maps (Food, Tiers, Hybrids, GemReceipts) and Teams /
--     Battle while they hold the defaults are left out of the record. ProfileSync uses the same slot encoding (client
--     State decodes it). Battle.TrialCleared is stored and synced as a DENSE array of booleans indexed by level
--     ({true, true, false, true}: false = not cleared), so `TrialCleared[level]` reads the same on both sides.
--
-- Public API
--   Load(player) -> live profile, GetProfile(player), MarkDirty(player), Sync(player), Save(player),
--   StartAutosave(), BindToClose(), AddTokens / SpendTokens / GetTokens, RecordMatch, signal ProfileLoaded.
--   v3: MarkDiscovered(player, petId) -> isNew (marks dirty; the caller Syncs, PetService does right after a roll),
--     GetTutorial(player) -> copy | nil until loaded (and while provisional), SetTutorial(player, t) -> ok
--     (MarkDirty + Sync; Gifted never goes back to false; false while provisional).
--   Phase 2 (all mark the profile dirty; never yield; the balance checks and writes are atomic):
--     GetHome(player) -> deep copy of Home (Garden / Gym keyed by slot number) | nil until loaded / while provisional
--     MutateHome(player, fn) -> ok      fn(home) edits the LIVE Home table and must not yield. It runs under pcall:
--                                       an error, or fn returning false, restores the Home as it was (-> false).
--                                       Afterwards the Home is sanitised in place; a change the client can see
--                                       (anything but CollectorCash / LastSeen) is synced (throttled, see below).
--     AddCash(player, n) -> ok          n > 0 (fractions allowed: income math; the store keeps whole units)
--     SpendCash(player, n) -> ok        false (nothing taken) when the balance is short; never negative
--     GetCash(player) -> whole cash
--     AddGems / SpendGems / GetGems     the same for Gems (whole numbers)
--     AddFood(player, foodId, n) -> ok, SpendFood(player, foodId, n) -> ok, GetFood(player, foodId) -> count
--                                       (GetFood(player) -> a copy of the whole map); Food changes are synced
--     GetPetLevel(player, key) -> level, xp       (1, 0 for a pet that never gained XP)
--     AddPetXp(player, key, xp) -> levelsGained   owned copies only; the curve is TycoonCatalog.XpToNext(level)
--                                       (a local fallback when that module is missing); synced
--     The player attributes Config.Attr.Cash / Config.Attr.Gems mirror the (whole) balances for the HUD.
--   Phase 3 (battle teams + the battle record; nothing here yields; reasons are short texts for a side toast):
--     TeamsChanged                      Util.Signal (exists at module load) Fire(player) after every successful SetTeam /
--                                       SelectTeam, when pruning dropped keys from the live presets, and after a rebase
--     GetTeams(player) -> { Presets = { {key...}, {key...}, {key...} }, Active = 1..3, Slots = 3 | 4 }   a pruned copy
--                                       (the ProfileSync shape) | nil until loaded and while provisional
--     SetTeam(player, preset, keys) -> ok, reason   preset 1..3; keys = the pets in slot order ("" / false = an empty
--                                       slot; the list is compacted). Refused: junk, a pet in a slot past Slots (slot 4
--                                       before the prestige unlock), the same key twice, a key not owned, a key whose
--                                       copies all work in the Garden / Gym ("<pet> is gardening! ..." for a Garden
--                                       pet: the client offers the recall, TycoonService.GardenRecall), a profile not
--                                       loaded or provisional. An empty list clears the preset. MarkDirty + SyncSoon +
--                                       TeamsChanged.
--     CheckTeam(player, preset, keys, freeKey?) -> ok, reason   SetTeam's checks without writing; freeKey counts one
--                                       copy of that key as out of the Garden (bug batch 2 #18: the recall check)
--     SelectTeam(player, preset) -> ok, reason      makes that preset the active one (MarkDirty + SyncSoon + TeamsChanged)
--     FieldableKeys(player) -> {key...}             every owned key with a copy free for a team (not in the Garden or the
--                                       Gym, not in training; bug batch 2 #18: a garden pet is busy)
--     PlacedCopies(player) -> {[key] = n}           copies working in the Garden / Gym (bug batch 2 #18; {} until loaded /
--                                       while provisional): PetService.Equip and its re-validation read it
--     GardenBusyKeys(player) -> {[key] = true}      every owned key with NO copy free of the Garden / Gym (the "gardening"
--                                       badge; BattleService's ring fallback skips them; {} until loaded / provisional)
--     ClosedBedOverlap(player) -> {slot...}         CLOSED garden places (above the open count) whose copy now also
--                                       follows / sits in a preset; TycoonService empties them silently ({} when none)
--     ActiveTeamKeys(player) -> {key...}            the active preset's usable keys in slot order, compacted (Phase 4: a
--                                       training pet is skipped at read time, the preset keeps it); {} when the team
--                                       is empty, the profile is not loaded or is provisional
--     GetBattle(player) -> { Trophies, TrialBest, TrialCleared = {[level]=true}, Raids, RaidBestDamage, PvPWins,
--                                       PvPLosses, EventPets = {[petId]=true} }   a copy | nil until loaded and while
--                                       provisional (stand-in data must never decide a first clear or an event pet)
--     MutateBattle(player, fn) -> ok    fn(battle) edits the LIVE record and must not yield; an error, or fn returning
--                                       false, restores it (-> false). Afterwards it is sanitised in place: whole numbers
--                                       >= 0, TrialCleared / EventPets never lose an entry and TrialBest / RaidBestDamage
--                                       never go down (the store merges them so), TrialBest >= the highest cleared level.
--                                       While provisional only Trophies / Raids / PvPWins / PvPLosses / RaidBestDamage may
--                                       change (they merge safely into the real save): any other change rolls the whole
--                                       call back (-> false). Pay a reward decided inside fn only once this returned true.
--                                       A change is synced (throttled).
--     AddTrophies(player, n) -> ok, total            n is rounded to a whole number and may be negative; the total
--                                       never goes below 0. Works like AddCash (also before the load finished and while
--                                       provisional: trophies merge as a delta). Synced (throttled).
--   Phase 4 (ARCHITECTURE_V3.md "Phase 4 build contract" section 4.2; nothing here yields; every helper lives in the
--   P4 table next to P3):
--     GetGrowth(player, key) -> { Evo, Speed, Physique, Ability, Defense, Job = {...} | nil }   a copy, zeros when
--                                       absent (also before the load and while provisional: display only)
--     GetGrowthMap(player) -> { [key] = entry }   a clean copy of the whole map ({} until loaded / while provisional)
--     MutateGrowth(player, fn) -> ok    fn(growth) edits the LIVE PetGrowth map { [key] = entry } and must not yield.
--                                       Refused until loaded and while provisional. An error, or fn returning false,
--                                       restores the map (-> false). Afterwards it is cleaned in place
--                                       (P4.cleanGrowth) and no Evo / rank may go down (the store merges them as
--                                       the higher value, so a lower write would come back anyway); a changed map is
--                                       synced (throttled). Decide a reward / refund inside fn and pay it only once
--                                       this returned true (the Job and the Cash then travel in the same step).
--     TrainingKeys(player) -> {[key] = true}        every key with a running Job ({} until loaded / while provisional):
--                                       the ONE source of the training lock (PetService.Equip, GardenSet, Fusion,
--                                       teamOf, the ring start and this module's own filters read it)
--     GetEvolution(player, key) -> 0..2             the stored stage (0 when absent)
--     SetEvolution(player, key, stage) -> ok        only up: true when the stage was raised to `stage` (<= 2 and <=
--                                       PetCatalog.MaxEvolution of the key's def when the catalog is there); false
--                                       for a stage not above the stored one, junk, not loaded, provisional
--     GetRing(player) -> { Best, Runs } | nil       a copy; nil until loaded and while provisional
--     MutateRing(player, fn) -> ok      fn(ring) edits the live record (no yields); Best never goes down (max), Runs
--                                       is a whole number >= 0; rollback on error / false; refused while provisional.
--                                       Decide "new record" / "first boss clear" rewards inside fn.
--     IsMigrated(player, name) -> bool | nil        nil until loaded and while provisional (not decidable)
--     MarkMigrated(player, name) -> ok  records Migrations[name] = true (a union: allowed while provisional)
--     MigratedNow(player, name) -> info | nil       info when THIS session ran that migration on this profile (the
--                                       entry remembers it until the player is released): for "P4" { Veteran = bool
--                                       (the profile had a home before), LegacySlots = n | nil, LegacyPrices = bool,
--                                       GymKeys = {key...} (the Gym pets set free), GymPets = #GymKeys,
--                                       CollectorCash = n (the Cash that waited on the Phase 3 Collector) }.
--                                       TycoonService shows the one welcome toast on the first claim when
--                                       MigratedNow(player, "P4").Veteran is true. Because that first claim may
--                                       happen in a LATER session, the migration also persists the marker
--                                       Migrations.P4Veteran (IsMigrated(player, "P4Veteran")); TycoonService
--                                       shows the toast when it is set and "P4Welcome" is not, then
--                                       MarkMigrated(player, "P4Welcome") (a union: never shown twice).
--     Migrated                          Util.Signal (exists at module load) Fire(player, name, info) right after the
--                                       ProfileLoaded / ProfileRebased that ran a migration; bug batch 2 #18:
--                                       "B2GardenSolo" { Keys = {key...} } when the read took pets out of the Garden
--                                       (they stayed equipped / in a team; MigratedNow(player, "B2GardenSolo") too)
--     SetPetLevel(player, key, level) -> ok   developer tools: writes { Level, Xp = 0 } for an OWNED key (1..the curve's
--                                       max level); refused until loaded / while provisional; synced
--   ProfileSync snapshot: Tokens, Pets, Equipped, Items, Stats, SpotIndex, Perks, Discovered, IndexClaimed,
--     Tutorial + Phase 2: Cash, Gems, Home { Level, Prestige, Stations, Garden, Gym, CollectorCash, LegacySlots?,
--     LegacyPrices? } (slot maps encoded like the store), Food, Tiers, Hybrids, PetLevels + Phase 3: Teams { Presets,
--     Active, Slots } (pruned), Battle { Trophies, TrialBest, TrialCleared = {bool...} (index = level), Raids,
--     RaidBestDamage, PvPWins, PvPLosses, EventPets = {[petId]=true} } + Phase 4: PetGrowth { [key] = { Evo?, Speed?,
--     Physique?, Ability?, Defense?, Job? } } (zero numbers left out: the client fills them), Ring { Best, Runs }.
--     Plain tables, never shared with the live profile.
--   Extras (used by PetService / IndexService / DevService / GemService, harmless otherwise): Release(player), Init(),
--     ComputePerks(equippedKeys, profile|nil), IsDiscovered(player, petId), IsProvisional(player),
--     ResetFields(player, { Discovered, IndexClaimed, Tutorial, BestTimes, Home, Tiers, Hybrids, PetLevels, Teams,
--     Battle, PetGrowth, Ring, Migrations = true })
--     -> ok (the session's CURRENT values of those fields replace the stored ones at the next successful save),
--     HasReceipt(player, purchaseId) -> bool | nil, MarkReceipt(player, purchaseId, gems?) -> true (new: grant now) |
--     false (already processed: grant nothing) | nil (not decidable now: profile not loaded or provisional -> answer
--     NotProcessedYet; `gems` = the amount granted with it, so a purchase another server already stored is never
--     added twice), SyncSoon(player) (a throttled Sync: at most one snapshot per 0.25 s, trailing call kept),
--     signal ProfileRebased(player, profile).
--
-- Plain Lua 5.1-compatible syntax only.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local DataService = {}

-- Fired after a profile finished loading: (player, profile). Handlers run on their own thread.
DataService.ProfileLoaded = Util.Signal()
-- Fired when the live profile was replaced by newer stored data (recovered failed load, or another
-- server changed the save): (player, profile). PetService re-validates its attributes on this.
DataService.ProfileRebased = Util.Signal()
-- Phase 3: fired after SetTeam / SelectTeam, when stale keys were pruned from the live presets and after a rebase:
-- (player). Exists at module load so other services can connect before any Init.
DataService.TeamsChanged = Util.Signal()
-- Phase 4: fired right after the ProfileLoaded / ProfileRebased that ran a one-time migration on the profile:
-- (player, name, info) with name "P4" and the info table of MigratedNow (see the header). Exists at module load.
DataService.Migrated = Util.Signal()

local PROFILE_VERSION = 2
local RETRY_DELAY = 1.5 -- seconds between the two attempts of a read/write
local MAX_COUNT = 1000000000 -- sanity cap for tokens and stats
local MAX_CASH = 1000000000000000 -- 1e15: tycoon money grows large; still an exact integer in a double
local MAX_FOOD = 1000000 -- per food type
local MAX_KEY_LENGTH = 48
local MAX_SLOT = 64 -- Garden / Gym slot numbers 1..MAX_SLOT
local MAX_RECEIPTS = 100 -- GemReceipts keeps the newest processed purchase ids
local MAX_TIME = 100000000000 -- sanity cap for os.time() stamps (LastSeen, receipts)
local REQUEST_COOLDOWN = 0.5 -- RequestProfile rate limit (seconds per player)
local SYNC_GAP = 0.25 -- SyncSoon: at most one snapshot per this many seconds per player
local ORPHAN_RETRY_FIRST = 10 -- seconds before the first background retry of an unsaved, departed profile
local ORPHAN_RETRY_MAX = 120 -- the retry delay doubles up to this
local ORPHAN_TIMEOUT = 1800 -- give up on (and drop) a departed profile that still cannot be saved after this long
local IS_STUDIO = RunService:IsStudio()
local STAT_KEYS = { "Matches", "Wins", "TokensEarned", "Spins" }
local MAX_TUTORIAL_STEP = 1000 -- sanity cap for Tutorial.Step (TutorialService clamps to its own step count)
local MAX_LEVEL = 100000 -- sanity cap for home / station / pet levels and prestige
local DEFAULT_MAX_PET_LEVEL = 100 -- AddPetXp cap when TycoonCatalog does not name one
local TIER_NAMES = { "Golden", "Rainbow" }
local VALID_TIER = { Normal = true, Golden = true, Rainbow = true }

-- Fields ResetFields may write over the store (everything else already follows a reset through the normal delta).
-- GemReceipts are deliberately not resettable: they keep developer-product purchases from being granted twice.
local OVERWRITABLE = {
	Discovered = true, IndexClaimed = true, Tutorial = true, BestTimes = true,
	Home = true, Tiers = true, Hybrids = true, PetLevels = true,
	Teams = true, Battle = true, -- Phase 3: the battle record's sets only grow and its best values only rise
	PetGrowth = true, Ring = true, Migrations = true, -- Phase 4: ranks / stages / Best only rise, Migrations only grow
	Dungeon = true, -- Phase 5: Best max / Cleared union would bring a reset record back
}
-- Stored keys this version owns. Anything else in a stored profile belongs to a newer phase and is written back
-- untouched by every save (see keepForeign).
local KNOWN_TOP = {
	Version = true, Tokens = true, Pets = true, Equipped = true, Items = true, Stats = true, SpotIndex = true,
	Discovered = true, IndexClaimed = true, Tutorial = true, Cash = true, Gems = true, Home = true, PetLevels = true,
	Food = true, Tiers = true, Hybrids = true, GemReceipts = true, Teams = true, Battle = true,
	PetGrowth = true, Ring = true, Migrations = true, -- Phase 4
	Dungeon = true, Berries = true, Settings = true, -- Phase 5
	UpdatedAt = true,
}
local KNOWN_HOME = {
	Level = true, Rooms = true, Prestige = true, Stations = true, Garden = true, Gym = true, CollectorCash = true,
	LastSeen = true,
	LegacySlots = true, LegacyPrices = true, -- Phase 4
	DecorCredit = true, LegacyMagnet = true, LegacyMagnetStar = true, -- Phase 5
}
local KNOWN_STATS = { Matches = true, Wins = true, TokensEarned = true, Spins = true, BestTimes = true }

-- cache[userId] = {
--   Profile = live profile table (what every other module reads and mutates),
--   Base = profile the store is known to contain (delta reference),
--   Owner = the Player instance the entry was last announced to (a quick rejoin gets a new one),
--   Loaded, Loading, LoadFailed, Saving, Dirty, RecoveryScheduled = bool flags,
--   Orphan = true while the player is gone but the entry still holds unsaved progress,
--   OrphanSince = os.clock() when it became an orphan, OrphanScheduled = a background retry loop runs,
--   Overwrite = { [field] = true } fields ResetFields asked to write over the store (nil when none is pending;
--     cleared only after a successful write, so orphan retries and BindToClose carry it too),
--   OverwriteGen = counter bumped by every ResetFields (a reset during an in-flight save stays pending),
--   LastSync = os.clock() of the last ProfileSync, SyncQueued = a trailing SyncSoon is scheduled,
--   ReceiptGems = { [purchaseId] = gems } granted with receipts not in the store yet (MarkReceipt; nil when none)
-- }
local cache = {}
local store = nil
local storeResolved = false
local legacyStore = nil
local legacyResolved = false
local storeDisabled = false -- true once the DataStore API is known to be unusable (Studio)
local autosaveStarted = false
local closeBound = false
local shuttingDown = false
local playerHooked = false
local requestHooked = false
local remoteCache = {}
local lastRequest = {} -- [userId] = os.clock() of the last accepted RequestProfile

----------------------------------------------------------------------
-- Optional shared modules (written by other engineers; resolved lazily, every use is guarded)
----------------------------------------------------------------------

local optionalModules = {}
local function getShared(name)
	local entry = optionalModules[name]
	if entry == nil then
		entry = false
		local module = Shared:FindFirstChild(name)
		if module then
			local ok, result = pcall(require, module)
			if ok and type(result) == "table" then
				entry = result
			else
				warn("[DataService] " .. name .. " failed to load: " .. tostring(result))
			end
		end
		optionalModules[name] = entry
	end
	return entry or nil
end

local function getPetCatalog()
	return getShared("PetCatalog")
end

local function getPetKeys()
	return getShared("PetKeys")
end

local function getTycoonCatalog()
	return getShared("TycoonCatalog")
end

-- resolve PetKeys now (DataService's pure merge code counts equipped copies with it inside UpdateAsync), and
-- TycoonCatalog (the merge reads its team-slot unlock when it prunes the battle teams)
getPetKeys()
getTycoonCatalog()

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

local function keyFor(userId)
	return "u_" .. tostring(userId)
end

local function isFinite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- Any value -> non-negative integer within sane bounds.
local function sanitize(n)
	if not isFinite(n) or n < 0 then
		return 0
	end
	if n > MAX_COUNT then
		return MAX_COUNT
	end
	return math.floor(n)
end

local function clampCount(n, maxCount)
	local value = sanitize(n)
	if value > maxCount then
		return maxCount
	end
	return value
end

-- Cash -> whole units in 0..MAX_CASH (the store and the snapshot hold whole cash).
local function sanitizeCash(n)
	if not isFinite(n) or n < 0 then
		return 0
	end
	if n > MAX_CASH then
		return MAX_CASH
	end
	return math.floor(n)
end

-- Cash for the LIVE profile: clamped, fractions kept (per-second income accumulates in fractions).
local function clampCash(n)
	if not isFinite(n) or n < 0 then
		return 0
	end
	if n > MAX_CASH then
		return MAX_CASH
	end
	return n
end

local function sanitizeTime(n)
	if not isFinite(n) or n < 0 then
		return 0
	end
	if n > MAX_TIME then
		return MAX_TIME
	end
	return math.floor(n)
end

-- Seconds for BestTimes: finite, > 0, rounded to 1/100 s. Returns nil when unusable.
local function sanitizeSeconds(n)
	if not isFinite(n) or n <= 0 or n > 10000000 then
		return nil
	end
	return math.floor(n * 100 + 0.5) / 100
end

local function validKey(key)
	return type(key) == "string" and #key > 0 and #key <= MAX_KEY_LENGTH
end

-- hybrid uids: letters, digits, "_" and "-" (they live inside keys and csv attributes)
local function validUid(uid)
	return type(uid) == "string" and #uid >= 1 and #uid <= 24 and string.find(uid, "^[%w_%-]+$") ~= nil
end

local function copyMap(map)
	local out = {}
	if type(map) ~= "table" then
		return out
	end
	for key, value in pairs(map) do
		out[key] = value
	end
	return out
end

local function copyList(list)
	local out = {}
	if type(list) ~= "table" then
		return out
	end
	for i, value in ipairs(list) do
		out[i] = value
	end
	return out
end

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = deepCopy(v)
	end
	return out
end

local function deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in pairs(a) do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function mapsEqual(a, b)
	for key, value in pairs(a) do
		if b[key] ~= value then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function listsEqual(a, b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

local function tableOr(t)
	if type(t) == "table" then
		return t
	end
	return {}
end

----------------------------------------------------------------------
-- Profile construction / validation
----------------------------------------------------------------------

local function newTutorial()
	return { Step = 1, Done = false, Gifted = false }
end

-- Home.Rooms is the same table as Home.Stations (the v3 name, kept for old code). The Phase 4 keys LegacySlots /
-- LegacyPrices are absent (nil) unless the Phase 4 migration wrote them.
local function newHome()
	local stations = {}
	return {
		Level = 0,
		Prestige = 0,
		Stations = stations,
		Rooms = stations,
		Garden = {},
		Gym = {},
		CollectorCash = 0,
		LastSeen = 0,
		LegacySlots = nil,
		LegacyPrices = nil,
		-- Phase 5 (nil unless the P5Home fold wrote them)
		DecorCredit = nil,
		LegacyMagnet = nil,
		LegacyMagnetStar = nil,
	}
end

-- Phase 3 (battle teams + the battle record). Its constants and helpers live in ONE table: the main chunk of this
-- module is close to Lua's limit of 200 local variables. None of the values below is in Config (local constants).
local P3 = {
	PRESETS = 3, -- saved team presets (Teams.Presets[1..3])
	SLOTS = 3, -- pets in a team: a fighter and two helpers (Phase 5, 4.8: the 4th slot is gone; a stored 4-key preset
	MAX_SLOTS = 3, -- keeps its first 3 keys, the 4th pet stays owned with its level and growth)
	MAX_TRIAL_LEVEL = 200, -- sanity cap for TrialBest / TrialCleared levels (the trials go up to 30)
	COUNTERS = { "Trophies", "Raids", "PvPWins", "PvPLosses" }, -- merge as +/- deltas (never below 0)
	BESTS = { "TrialBest", "RaidBestDamage" }, -- merge as the higher value
	-- what MutateBattle may change while the profile is provisional (these merge safely into the real save)
	PROVISIONAL_OK = { Trophies = true, Raids = true, PvPWins = true, PvPLosses = true, RaidBestDamage = true },
}

-- Phase 4 (pet growth: evolution stages + training; the Champion Ring record; migration markers; the veteran Home
-- keys). Like P3, ONE table holds every constant and helper (the one new top-level local of Phase 4). None of the
-- values below is in Config (local constants of the save format; the game rules live in PetCatalog / BattleCatalog /
-- TycoonCatalog and are read lazily where a rule, not the format, decides).
local P4 = {
	STATS = { "Speed", "Physique", "Ability", "Defense" }, -- the training skills (PetGrowth[key][stat] = rank)
	STAT_SET = { Speed = true, Physique = true, Ability = true, Defense = true },
	MAX_RANK = 10, -- training ranks 0..10
	MAX_EVO = 2, -- evolution stages 0..2 (PetCatalog.MaxEvolution decides per rarity; the data clamps at 2)
	MAX_JOB_SLOT = 5, -- Training Place mats 1..5
	MAX_FROM = 16, -- Job.From: "Follow" | "Garden:<slot>" | "Free" (a short string)
	MAX_RING = 100000, -- sanity cap for Ring.Best (the ring is endless; records are a few dozen rounds)
	MIGRATION = "P4", -- Migrations[name] of the one-time Phase 4 migration (section 4.3)
	VETERAN_MARK = "P4Veteran", -- set by that migration when the profile had a home before (the welcome toast is owed)
	WELCOME_MARK = "P4Welcome", -- set by TycoonService (MarkMigrated) once the welcome toast was shown on the first claim
	GARDEN_SLOTS_BASE = 3, -- 3 + Prestige garden places when TycoonCatalog.Prestige.GardenSlotsBase is missing
	GARDEN_SLOTS_PER_STAR = 1,
}

-- Phase 5 (the Dungeon record, Berries, Settings, the P5 migrations and the folded Home keys; ARCHITECTURE_V3.md
-- "Phase 5 build contract" section 9). ONE table again (the one new top-level local of Phase 5). Save-format
-- constants only; the game rules (floors, berry prices, the fold) live in BattleCatalog / TycoonCatalog.
local P5 = {
	MAX_FLOOR = 100, -- Dungeon.Best / Cleared floors 1..100 (the dungeon has 10 floors + endless)
	MIGRATE_MAX_FLOOR = 10, -- the P5Dungeon migration credits at most floor 10
	TRIALS_PER_FLOOR = 3, -- Best = min(10, floor(TrialBest / 3)) (9.2 step 2)
	DUNGEON_MARK = "P5Dungeon", -- Migrations[name] of the one-time dungeon migration
	HOME_MARK = "P5Home", -- Migrations[name] of the one-time home fold (TycoonCatalog.FoldLegacy + the Food -> berries step)
	MOUSELOCK_MARK = "P5MouseLock", -- Migrations[name] of the one-time "mouse lock ON" step (bug batch 2 #21)
	GARDEN_MARK = "B2GardenSolo", -- Migrations[name]: the profile went through the garden-exclusive rule (bug batch 2 #18)
	LEGACY_FOOD = { Snack = 200, Meal = 1200, Feast = 6400 }, -- berries per old food when TycoonCatalog.Berries.LegacyFood is missing
	MAX_BERRIES = 1000000000, -- sanity cap (whole berries)
	BERRIES_GAP = 0.5, -- seconds: the Berries attribute is written at most twice a second (trailing write; 10.2 m6)
	SETTING_KEYS = { "Music", "Sfx", "Gfx", "Shake", "SeenNotes", "MouseLock" },
	-- 7.2 (+ MouseLock: dungeon-fixes 6). Bug batch 2 #21: MouseLock defaults to ON (a new profile, or a stored Settings
	-- table without the key). A stored false is NOT always a choice: since the option landed the store writes the whole
	-- Settings table (MouseLock = false, the old default) as soon as any one setting is non-default, so the one-time
	-- P5MouseLock step (P5.migrateMouseLock) turns the lock on ONCE for a profile without that marker. A player who sets
	-- MouseLock (SetSetting: the L key or the Settings row) marks it too, so a false chosen after this release stays false.
	SETTING_DEFAULTS = { Music = 6, Sfx = 8, Gfx = "Auto", Shake = true, SeenNotes = 0, MouseLock = true },
	GFX = { Auto = true, Low = true, High = true },
	MAX_VOLUME = 10, -- Music / Sfx 0..10
	MAX_NOTES = 1000, -- SeenNotes 0..1000 (UpdateNotes.Latest is a small version number)
	SETTINGS_RATE = 6, -- SettingsSet: 6 per second...
	SETTINGS_BURST = 6, -- ...with a burst of 6
	MAX_DECOR_CREDIT = 18, -- Home.DecorCredit 0..18 (the old decor levels that did not fit into Fence / Fountain)
	MAX_MAGNET = 5, -- Home.LegacyMagnet 1..5 (the old Coin Magnet level)
	buckets = {}, -- [userId] = { tokens, last } SettingsSet rate limit (cleared when the player leaves)
	pushes = {}, -- [userId] = { last = os.clock(), queued = bool } Berries attribute throttle
}

-- The Dungeon record: Best = the highest floor cleared (0 = none), Cleared = { [floor] = true } in the live profile
-- (a dense boolean array in the store and the snapshot, like Battle.TrialCleared), Runs = finished runs, Clears =
-- first clears (counter).
function P5.newDungeon()
	return { Best = 0, Cleared = {}, Runs = 0, Clears = 0 }
end

-- A floor number: a whole number 1..MAX_FLOOR (a numeric string too), or nil.
function P5.floorOf(value)
	local n = value
	if type(value) == "string" and string.find(value, "^%d+$") then
		n = tonumber(value)
	end
	if isFinite(n) and n >= 1 and n <= P5.MAX_FLOOR and n == math.floor(n) then
		return n
	end
	return nil
end

-- Untrusted Dungeon -> a clean record (whole numbers >= 0; Cleared as a set; Best >= the highest cleared floor).
function P5.cleanDungeon(raw)
	local r = tableOr(raw)
	local d = P5.newDungeon()
	d.Best = clampCount(r.Best, P5.MAX_FLOOR)
	d.Runs = sanitize(r.Runs)
	d.Clears = sanitize(r.Clears)
	for key, value in pairs(tableOr(r.Cleared)) do
		local floor = nil
		if value == true then
			floor = P5.floorOf(key)
		elseif type(key) == "number" and type(value) == "number" then
			floor = P5.floorOf(value)
		end
		if floor then
			d.Cleared[floor] = true
		end
	end
	for floor in pairs(d.Cleared) do
		if floor > d.Best then
			d.Best = floor
		end
	end
	return d
end

function P5.isDefaultDungeon(d)
	return d.Best == 0 and d.Runs == 0 and d.Clears == 0 and next(d.Cleared) == nil
end

-- Clean record -> the stored / synced form (Cleared as a dense boolean array; no sparse array for the DataStore).
function P5.encodeDungeon(d)
	local cleared, top = {}, 0
	for floor in pairs(d.Cleared) do
		if floor > top then
			top = floor
		end
	end
	for floor = 1, top do
		cleared[floor] = d.Cleared[floor] == true
	end
	return { Best = d.Best, Cleared = cleared, Runs = d.Runs, Clears = d.Clears }
end

-- The Dungeon delta (both clean), or nil: Best as a candidate when it rose, Cleared = the floors the session added
-- (a union), Runs as a +/- delta, Clears as a +/- delta EXCEPT the part the session's own P5Dungeon migration wrote
-- (`migrated` = that Clears value): it travels as ClearsFloor and merges as a max, so two servers migrating the same
-- save do not double it (9.1 m15).
function P5.diffDungeon(live, base, migrated)
	local d, any = { Best = nil, Cleared = {}, Runs = nil, Clears = nil, ClearsFloor = nil }, false
	if live.Best > base.Best then
		d.Best = live.Best
		any = true
	end
	for floor in pairs(live.Cleared) do
		if not base.Cleared[floor] then
			d.Cleared[floor] = true
			any = true
		end
	end
	if live.Runs ~= base.Runs then
		d.Runs = live.Runs - base.Runs
		any = true
	end
	local floorClears = isFinite(migrated) and migrated > 0 and math.floor(migrated) or 0
	local clearsDelta = live.Clears - base.Clears - floorClears
	if clearsDelta ~= 0 then
		d.Clears = clearsDelta
		any = true
	end
	if floorClears > 0 then
		d.ClearsFloor = floorClears
		any = true
	end
	if not any then
		return nil
	end
	return d
end

function P5.applyDungeon(out, dd)
	if not dd then
		return
	end
	local d = out.Dungeon
	if isFinite(dd.Best) and dd.Best > d.Best then
		d.Best = clampCount(dd.Best, P5.MAX_FLOOR)
	end
	for key, value in pairs(tableOr(dd.Cleared)) do
		local floor = value == true and P5.floorOf(key) or nil
		if floor then
			d.Cleared[floor] = true
			if floor > d.Best then
				d.Best = floor
			end
		end
	end
	if isFinite(dd.Runs) then
		d.Runs = sanitize(d.Runs + dd.Runs) -- never below 0
	end
	if isFinite(dd.ClearsFloor) and dd.ClearsFloor > d.Clears then
		d.Clears = clampCount(dd.ClearsFloor, P5.MAX_FLOOR)
	end
	if isFinite(dd.Clears) then
		d.Clears = sanitize(d.Clears + dd.Clears)
	end
end

-- Berries: a whole number 0..MAX_BERRIES.
function P5.cleanBerries(raw)
	return clampCount(raw, P5.MAX_BERRIES)
end

function P5.newSettings()
	local s = {}
	for _, key in ipairs(P5.SETTING_KEYS) do
		s[key] = P5.SETTING_DEFAULTS[key]
	end
	return s
end

-- One setting's clean value, or nil when `value` is not acceptable for `key` (type -> range; 7.2).
function P5.settingValue(key, value)
	if key == "Music" or key == "Sfx" then
		if isFinite(value) and value >= 0 and value <= P5.MAX_VOLUME and value == math.floor(value) then
			return value
		end
	elseif key == "Gfx" then
		if type(value) == "string" and P5.GFX[value] then
			return value
		end
	elseif key == "Shake" or key == "MouseLock" then
		if type(value) == "boolean" then
			return value
		end
	elseif key == "SeenNotes" then
		if isFinite(value) and value >= 0 and value <= P5.MAX_NOTES and value == math.floor(value) then
			return value
		end
	end
	return nil
end

-- Untrusted Settings -> a clean table with every key (per-key defaults for a missing or malformed value).
function P5.cleanSettings(raw)
	local r = tableOr(raw)
	local s = P5.newSettings()
	for _, key in ipairs(P5.SETTING_KEYS) do
		local value = P5.settingValue(key, r[key])
		if value ~= nil then
			s[key] = value
		end
	end
	return s
end

function P5.isDefaultSettings(s)
	for _, key in ipairs(P5.SETTING_KEYS) do
		if s[key] ~= P5.SETTING_DEFAULTS[key] then
			return false
		end
	end
	return true
end

function P5.settingsEqual(a, b)
	for _, key in ipairs(P5.SETTING_KEYS) do
		if a[key] ~= b[key] then
			return false
		end
	end
	return true
end

-- 3 empty presets, preset 1 active
function P3.newTeams()
	local presets = {}
	for i = 1, P3.PRESETS do
		presets[i] = {}
	end
	return { Presets = presets, Active = 1 }
end

function P3.newBattle()
	return {
		Trophies = 0,
		TrialBest = 0,
		TrialCleared = {},
		Raids = 0,
		RaidBestDamage = 0,
		PvPWins = 0,
		PvPLosses = 0,
		EventPets = {},
	}
end

local function newProfile()
	return {
		Version = PROFILE_VERSION,
		Tokens = 0,
		Pets = {},
		Equipped = {},
		Items = {},
		Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
		SpotIndex = nil,
		-- v3 (ARCHITECTURE_V3.md section 1)
		Discovered = {},
		IndexClaimed = {},
		Tutorial = newTutorial(),
		-- Phase 2 (ARCHITECTURE_V3.md "Phase 2 build contract")
		Cash = 0,
		Gems = 0,
		Home = newHome(),
		PetLevels = {},
		Food = {},
		Tiers = {},
		Hybrids = {},
		GemReceipts = {},
		-- Phase 3 (ARCHITECTURE_V3.md "Phase 3 build contract")
		Teams = P3.newTeams(),
		Battle = P3.newBattle(),
		-- Phase 4 (ARCHITECTURE_V3.md "Phase 4 build contract" section 4)
		PetGrowth = {},
		Ring = { Best = 0, Runs = 0 },
		Migrations = {},
		-- Phase 5 (ARCHITECTURE_V3.md "Phase 5 build contract" section 9)
		Dungeon = P5.newDungeon(),
		Berries = 0,
		Settings = P5.newSettings(),
	}
end

-- Untrusted tutorial table -> a clean copy { Step >= 1, Done, Gifted }.
local function cleanTutorial(raw)
	local t = newTutorial()
	if type(raw) == "table" then
		local step = raw.Step
		if isFinite(step) and step >= 1 then
			t.Step = math.min(math.floor(step), MAX_TUTORIAL_STEP)
		end
		t.Done = raw.Done == true
		t.Gifted = raw.Gifted == true
	end
	return t
end

local function tutorialsEqual(a, b)
	return a.Step == b.Step and a.Done == b.Done and a.Gifted == b.Gifted
end

-- Untrusted pet level entry -> { Level >= 1, Xp >= 0 } (a bare number is read as the level), or nil.
local function cleanPetLevel(raw)
	local level, xp
	if type(raw) == "table" then
		level, xp = raw.Level, raw.Xp
	elseif isFinite(raw) then
		level, xp = raw, 0
	else
		return nil
	end
	if not isFinite(level) or level < 1 then
		level = 1
	end
	return { Level = math.min(math.floor(level), MAX_LEVEL), Xp = sanitize(xp) }
end

local function copyPetLevels(map)
	local out = {}
	for id, entry in pairs(tableOr(map)) do
		local clean = validKey(id) and cleanPetLevel(entry)
		if clean then
			out[id] = clean
		end
	end
	return out
end

-- { [validKey] = 1..cap } (zero / junk entries dropped)
local function cleanCounts(raw, cap)
	local out = {}
	for key, value in pairs(tableOr(raw)) do
		if validKey(key) and isFinite(value) then
			local n = clampCount(value, cap)
			if n > 0 then
				out[key] = n
			end
		end
	end
	return out
end

-- Garden / Gym slot id: a whole number 1..MAX_SLOT (also from a numeric string), or a valid string name.
local function slotId(key)
	local n = key
	if type(key) == "string" and string.find(key, "^%d+$") then
		n = tonumber(key)
	end
	if type(n) == "number" then
		if n == n and n >= 1 and n <= MAX_SLOT and n == math.floor(n) then
			return n
		end
		return nil
	end
	if validKey(key) then
		return key
	end
	return nil
end

-- Untrusted slot map (map, list, or a stored array with "" holes) -> { [slot] = key }.
local function cleanSlots(raw)
	local out = {}
	for key, value in pairs(tableOr(raw)) do
		local slot = slotId(key)
		if slot ~= nil and validKey(value) then
			out[slot] = value
		end
	end
	return out
end

-- { [slot] = key } -> a storable / sendable table: an array with "" for empty slots when every slot is a number,
-- otherwise a map with string keys (stores and remotes mangle sparse arrays).
local function encodeSlots(map)
	local allNumbers, maxSlot = true, 0
	for slot in pairs(map) do
		if type(slot) == "number" then
			if slot > maxSlot then
				maxSlot = slot
			end
		else
			allNumbers = false
		end
	end
	local out = {}
	if allNumbers then
		for i = 1, maxSlot do
			out[i] = map[i] or ""
		end
	else
		for slot, key in pairs(map) do
			out[tostring(slot)] = key
		end
	end
	return out
end

local function cleanStations(raw)
	local out = {}
	for key, value in pairs(tableOr(raw)) do
		if validKey(key) and isFinite(value) then
			local level = clampCount(value, MAX_LEVEL)
			if level > 0 then
				out[key] = level
			end
		end
	end
	return out
end

-- Untrusted home -> a clean home (whole numbers). `migrate`: stored data, so the v3 reserve Home.Rooms is folded
-- into Stations (the higher level wins). The live profile is never migrated again: there Rooms IS Stations.
local function cleanHome(raw, migrate)
	local h = tableOr(raw)
	local home = newHome()
	home.Level = clampCount(h.Level, MAX_LEVEL)
	home.Prestige = clampCount(h.Prestige, MAX_LEVEL)
	local stations = h.Stations
	if type(stations) ~= "table" and not migrate then
		stations = h.Rooms -- a live home whose Stations table was dropped: Rooms is the same table
	end
	for key, level in pairs(cleanStations(stations)) do
		home.Stations[key] = level
	end
	if migrate and type(h.Rooms) == "table" and h.Rooms ~= h.Stations then
		for key, level in pairs(cleanStations(h.Rooms)) do
			if level > (home.Stations[key] or 0) then
				home.Stations[key] = level
			end
		end
	end
	home.Garden = cleanSlots(h.Garden)
	home.Gym = cleanSlots(h.Gym)
	home.CollectorCash = sanitizeCash(h.CollectorCash)
	home.LastSeen = sanitizeTime(h.LastSeen)
	-- Phase 4 (veterans): a whole number of garden places >= 1, or nil; true, or nil
	local legacy = h.LegacySlots
	if isFinite(legacy) and legacy >= 1 then
		home.LegacySlots = math.min(math.floor(legacy), MAX_SLOT)
	end
	if h.LegacyPrices == true then
		home.LegacyPrices = true
	end
	-- Phase 5 (the fold): DecorCredit 1..18 or nil; LegacyMagnet 1..5 with the Prestige it was folded at, or nil
	local credit = h.DecorCredit
	if isFinite(credit) and credit >= 1 then
		home.DecorCredit = math.min(math.floor(credit), P5.MAX_DECOR_CREDIT)
	end
	local magnet = h.LegacyMagnet
	if isFinite(magnet) and magnet >= 1 then
		home.LegacyMagnet = math.min(math.floor(magnet), P5.MAX_MAGNET)
		home.LegacyMagnetStar = clampCount(h.LegacyMagnetStar, MAX_LEVEL)
	end
	return home
end

local function homesEqual(a, b)
	return a.Level == b.Level
		and a.Prestige == b.Prestige
		and a.CollectorCash == b.CollectorCash
		and a.LastSeen == b.LastSeen
		and a.LegacySlots == b.LegacySlots
		and a.LegacyPrices == b.LegacyPrices
		and a.DecorCredit == b.DecorCredit
		and a.LegacyMagnet == b.LegacyMagnet
		and a.LegacyMagnetStar == b.LegacyMagnetStar
		and mapsEqual(a.Stations, b.Stations)
		and mapsEqual(a.Garden, b.Garden)
		and mapsEqual(a.Gym, b.Gym)
end

-- what the client sees of a home (CollectorCash / LastSeen changes alone are not worth a snapshot; neither is
-- LegacyPrices alone: it only ever changes together with a Prestige or in the one-time migration before the first
-- snapshot of the session)
local function homeVisiblyEqual(a, b)
	return a.Level == b.Level
		and a.Prestige == b.Prestige
		and a.LegacySlots == b.LegacySlots
		and mapsEqual(a.Stations, b.Stations)
		and mapsEqual(a.Garden, b.Garden)
		and mapsEqual(a.Gym, b.Gym)
end

-- { [petId] = { Golden = n, Rainbow = n } } with positive counts only
local function cleanTiers(raw)
	local out = {}
	local cap = Config.Pets.MaxPerStack
	for petId, entry in pairs(tableOr(raw)) do
		if validKey(petId) and type(entry) == "table" then
			local clean = nil
			for _, tier in ipairs(TIER_NAMES) do
				local n = isFinite(entry[tier]) and clampCount(entry[tier], cap) or 0
				if n > 0 then
					clean = clean or {}
					clean[tier] = n
				end
			end
			if clean then
				out[petId] = clean
			end
		end
	end
	return out
end

-- One fused hybrid record { Body, Style, Elements, Name?, Rarity?, Tier } (+ up to 8 extra scalar fields the fusion
-- code may keep, e.g. a look seed), or nil. Lenient on purpose: the store keeps what the game made.
local function cleanHybrid(raw)
	if type(raw) ~= "table" or not validKey(raw.Body) or not validKey(raw.Style) then
		return nil
	end
	local rec = { Body = raw.Body, Style = raw.Style, Elements = {}, Tier = "Normal" }
	if VALID_TIER[raw.Tier] then
		rec.Tier = raw.Tier
	end
	local seen = {}
	for _, e in ipairs(tableOr(raw.Elements)) do
		if validKey(e) and not seen[e] and #rec.Elements < 4 then
			seen[e] = true
			rec.Elements[#rec.Elements + 1] = e
		end
	end
	if type(raw.Name) == "string" and #raw.Name >= 1 and #raw.Name <= 32 then
		rec.Name = raw.Name
	end
	if validKey(raw.Rarity) then
		rec.Rarity = raw.Rarity
	end
	local extras = 0
	for k, v in pairs(raw) do
		if rec[k] == nil and k ~= "Name" and k ~= "Rarity" and type(k) == "string" and #k <= 24 and extras < 8 then
			if isFinite(v) or type(v) == "boolean" or (type(v) == "string" and #v <= 64) then
				rec[k] = v
				extras = extras + 1
			end
		end
	end
	return rec
end

local function cleanHybrids(raw)
	local out = {}
	for uid, rec in pairs(tableOr(raw)) do
		local clean = validUid(uid) and cleanHybrid(rec)
		if clean then
			out[uid] = clean
		end
	end
	return out
end

-- Trims a receipt map (in place) to MAX_RECEIPTS entries by evicting the oldest ones (ties: the smaller id).
-- Ids in `keep` (the receipts just processed) are never evicted, so a fresh receipt always survives its own save.
local function trimReceipts(map, keep)
	local list = {}
	local total = 0
	for id, t in pairs(map) do
		total = total + 1
		if not (keep and keep[id]) then
			list[#list + 1] = { Id = id, T = t }
		end
	end
	if total <= MAX_RECEIPTS then
		return map
	end
	table.sort(list, function(a, b)
		if a.T ~= b.T then
			return a.T < b.T
		end
		return a.Id < b.Id
	end)
	local i = 1
	while total > MAX_RECEIPTS and list[i] do
		map[list[i].Id] = nil
		total = total - 1
		i = i + 1
	end
	return map
end

-- { [purchaseId] = os.time() of processing } (a stored `true` counts as time 0). `trim`: bounded to MAX_RECEIPTS
-- (stored data); the live map is bounded by MarkReceipt and copied whole, so a fresh receipt always reaches the delta.
local function cleanReceipts(raw, trim)
	local out = {}
	for id, value in pairs(tableOr(raw)) do
		if validKey(id) then
			if value == true then
				out[id] = 0
			elseif isFinite(value) then
				out[id] = sanitizeTime(value)
			end
		end
	end
	if trim then
		trimReceipts(out)
	end
	return out
end

-- Set-like map { [key] = true } with valid keys only (a stored list of ids is accepted as well).
local function cleanSet(raw)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for key, value in pairs(raw) do
		if validKey(key) and value == true then
			out[key] = true
		elseif type(key) == "number" and validKey(value) then
			out[value] = true
		end
	end
	return out
end

-- Every owned pet counts as discovered (v3 migration rule, kept as an invariant): Normal copies and tier copies.
local function discoverOwned(profile)
	for id, count in pairs(profile.Pets) do
		if validKey(id) and type(count) == "number" and count > 0 then
			profile.Discovered[id] = true
		end
	end
	for id in pairs(tableOr(profile.Tiers)) do
		if validKey(id) then
			profile.Discovered[id] = true
		end
	end
end

-- copies of `key` the profile owns (PetKeys.Count; plain Pets counts without that module)
local function ownedCount(profile, key)
	local keys = getPetKeys()
	if keys and type(keys.Count) == "function" then
		local ok, n = pcall(keys.Count, profile, key)
		if ok and type(n) == "number" then
			return n
		end
		return 0
	end
	local pets = tableOr(profile.Pets)
	local n = pets[key]
	if type(n) == "number" then
		return n
	end
	return 0
end

-- Drops equipped keys that are not owned, are over their owned count, exceed the slot limit, or (Phase 4) are in
-- training (a Phase 3 server may have equipped one during the rollout; the pet comes back by itself when the job
-- ends: PetCareService's auto-return). Runs after Pets, Tiers, Hybrids AND PetGrowth are final: tier and hybrid
-- copies count too, and the training lock reads the clean growth map. Bug batch 2 #18: copies working in the Garden /
-- Gym of profile.Home cannot follow (open places only: a copy resting on a closed one may, P3.placedCopies;
-- normalizeProfile calls this before its Home is read, so a stored overlap is left to P3.gardenSolo there, which keeps
-- the pet equipped and takes it out of the Garden).
local function normalizeEquipped(profile)
	local out = {}
	local used = {}
	local maxEquipped = Config.Pets.MaxEquipped
	local training = P4.trainingSet(profile.PetGrowth)
	local placed = P3.placedCopies(profile)
	for _, id in ipairs(profile.Equipped) do
		if type(id) == "string" and #out < maxEquipped and not training[id] then
			local owned = ownedCount(profile, id) - (placed[id] or 0)
			local count = used[id] or 0
			if count < owned then
				used[id] = count + 1
				table.insert(out, id)
			end
		end
	end
	profile.Equipped = out
end

----------------------------------------------------------------------
-- Phase 3: battle teams + the battle record (pure helpers; they run inside UpdateAsync too)
----------------------------------------------------------------------

-- true for a key a team may hold: a valid key that PetKeys reads as a canonical key (without PetKeys: any valid key)
function P3.teamKey(key)
	if not validKey(key) then
		return false
	end
	local keys = getPetKeys()
	if keys and type(keys.Parse) == "function" then
		local ok, parsed = pcall(keys.Parse, key)
		return ok and parsed ~= nil
	end
	return true
end

-- Untrusted preset -> the keys of its slots 1..MAX_SLOTS in order, each once ("" / false / junk entries are skipped,
-- so the pets behind an empty slot move up).
function P3.cleanPreset(raw)
	local out, seen = {}, {}
	if type(raw) ~= "table" then
		return out
	end
	for i = 1, P3.MAX_SLOTS do
		local key = raw[i]
		if P3.teamKey(key) and not seen[key] then
			seen[key] = true
			out[#out + 1] = key
		end
	end
	return out
end

-- Untrusted Teams -> { Presets = { [1..PRESETS] = {key...} }, Active = 1..PRESETS }: the structure only (ownership is
-- P3.prune's job). Migration: a Phase 2 profile has no Teams, or the empty reserve -> the defaults; a bare list of
-- presets ({ {keys}, ... }) or of keys ({ key, ... } = preset 1) is read leniently.
function P3.cleanTeams(raw)
	local teams = P3.newTeams()
	if type(raw) ~= "table" then
		return teams
	end
	local presets = raw.Presets
	if type(presets) ~= "table" then
		if type(raw[1]) == "table" then
			presets = raw
		elseif type(raw[1]) == "string" then
			presets = { raw }
		else
			presets = {}
		end
	end
	for i = 1, P3.PRESETS do
		local list = presets[i]
		if list == nil then
			list = presets[tostring(i)]
		end
		teams.Presets[i] = P3.cleanPreset(list)
	end
	local active = raw.Active
	if isFinite(active) and active >= 1 and active <= P3.PRESETS and active == math.floor(active) then
		teams.Active = active
	end
	return teams
end

-- Team slots of any profile-like table: 3 always (Phase 5, 4.8: slot 1 = the fighter, 2-3 = the helpers; the Phase 3
-- prestige unlock of a 4th slot is gone).
function P3.slotsOf(_)
	return P3.SLOTS
end

-- { [key] = copies working in the Garden or the Gym } (those copies can neither follow nor fight). Live slot maps or
-- stored arrays (""). Bug batch 2 #18 ("Remote recall"): the Garden counts again (Phase 4 had dropped it: "a garden
-- pet earns at home while it follows you and fights"); a garden pet is busy gardening. Training stays a read-time
-- filter, never a prune. Home.Gym is emptied by the one-time Phase 4 migration (kept so Phase 3 writes during the
-- rollout stay understood). A CLOSED garden place does not count (P3.closedSlot: a copy resting there earns nothing,
-- so it is not busy; it may follow and fight, and leaves that place silently when it does).
function P3.placedCopies(profile)
	local out = {}
	local home = type(profile) == "table" and profile.Home or nil
	if type(home) ~= "table" then
		return out
	end
	local open = P3.gardenOpen(home)
	for slot, key in pairs(tableOr(home.Garden)) do
		if type(key) == "string" and key ~= "" and not P3.closedSlot(slot, open) then
			out[key] = (out[key] or 0) + 1
		end
	end
	for _, key in pairs(tableOr(home.Gym)) do
		if type(key) == "string" and key ~= "" then
			out[key] = (out[key] or 0) + 1
		end
	end
	return out
end

-- Bug batch 2 #18 follow-up: the open garden places of a home (TycoonCatalog.GardenSlots: 3 + 1 per Prestige star, or
-- the veteran's LegacySlots), or nil when that cannot be told (no catalog, or no Garden built: then no place counts as
-- closed, the safe side of the lock).
function P3.gardenOpen(home)
	local catalog = getTycoonCatalog()
	if type(home) ~= "table" or not catalog or type(catalog.GardenSlots) ~= "function" then
		return nil
	end
	local ok, open = pcall(catalog.GardenSlots, home)
	if ok and isFinite(open) and open >= 1 then
		return math.floor(open)
	end
	return nil
end

-- true for a numbered garden place ABOVE the open count (`open` from P3.gardenOpen): a Prestige closed it (the
-- veteran's LegacySlots ended), the pet sleeps on it ("Prestige to open") and earns nothing. Stored arrays and
-- string slot names ("5") read through slotId; a named slot is never closed.
function P3.closedSlot(slot, open)
	local id = slotId(slot)
	return open ~= nil and type(id) == "number" and id > open
end

-- Bug batch 2 #18, old saves (the Phase 4 rule let a Garden pet follow and fight): every key whose copies cannot cover
-- both its Garden places and its other jobs (the equipped copies, or 1 when a preset lists it) LEAVES the Garden
-- (its highest places first) until they do: the pet stays equipped / in its team, no team is emptied. Edits the clean
-- profile in place (Home.Garden keyed by slot, Equipped, Teams clean); deterministic, and a no-op without an overlap
-- (so it never loops). Returns the keys that left an OPEN place (sorted; they get the toast), or nil when none did.
-- Closed places (P3.closedSlot) go first and silently: a copy resting there is not busy (P3.placedCopies skips it),
-- so the pet just leaves that bed, the same as TycoonService's live release after an equip / team change.
function P3.gardenSolo(profile)
	local plan = P3.soloPlan(profile)
	if not plan then
		return nil
	end
	local garden = profile.Home.Garden
	for _, slot in ipairs(plan.Closed) do
		garden[slot] = nil
	end
	for _, slot in ipairs(plan.Open) do
		garden[slot] = nil
	end
	if #plan.Moved == 0 then
		return nil
	end
	return plan.Moved
end

-- The Garden places of a profile whose copy also follows the player / sits in a preset (see P3.gardenSolo), without
-- changing anything: { Closed = {slot...}, Open = {slot...}, Moved = {key...} (the keys of Open, sorted) }, or nil
-- when there is no overlap. Closed places are freed first. The live profile never has an Open overlap (the lock), so
-- DataService.ClosedBedOverlap reads only Closed.
function P3.soloPlan(profile)
	local home = type(profile) == "table" and profile.Home or nil
	local garden = type(home) == "table" and home.Garden or nil
	if type(garden) ~= "table" or next(garden) == nil then
		return nil
	end
	local need = {}
	for _, key in ipairs(tableOr(profile.Equipped)) do
		if type(key) == "string" then
			need[key] = (need[key] or 0) + 1
		end
	end
	local presets = type(profile.Teams) == "table" and profile.Teams.Presets or nil
	for _, list in pairs(tableOr(presets)) do
		for _, key in ipairs(tableOr(list)) do
			if type(key) == "string" and (need[key] or 0) < 1 then
				need[key] = 1
			end
		end
	end
	local open = P3.gardenOpen(home)
	local slotsOf, closedOf = {}, {}
	for slot, key in pairs(garden) do
		if type(key) == "string" and key ~= "" and need[key] then
			local byKey = P3.closedSlot(slot, open) and closedOf or slotsOf
			local list = byKey[key]
			if not list then
				list = {}
				byKey[key] = list
			end
			list[#list + 1] = slot
		end
	end
	if next(slotsOf) == nil and next(closedOf) == nil then
		return nil
	end
	local gym = {}
	for _, key in pairs(tableOr(home.Gym)) do
		if type(key) == "string" and key ~= "" then
			gym[key] = (gym[key] or 0) + 1
		end
	end
	local function highestFirst(a, b)
		if type(a) == type(b) then
			return a > b
		end
		return type(a) == "string" -- named slots go first, then the highest numbers
	end
	local plan = { Closed = {}, Open = {}, Moved = {} }
	for key in pairs(need) do
		local slots, closed = slotsOf[key] or {}, closedOf[key] or {}
		if #slots > 0 or #closed > 0 then
			table.sort(slots, highestFirst)
			table.sort(closed, highestFirst)
			local owned = ownedCount(profile, key) - (gym[key] or 0)
			local want = math.min(need[key], owned) -- (a key owned too rarely is the prune's job, not the Garden's)
			local free = owned - #slots - #closed
			-- closed places first (silent: the copy resting there is not busy), then the open ones (the old-save repair)
			local i = 1
			while free < want and closed[i] ~= nil do
				plan.Closed[#plan.Closed + 1] = closed[i]
				free = free + 1
				i = i + 1
			end
			i = 1
			while free < want and slots[i] ~= nil do
				plan.Open[#plan.Open + 1] = slots[i]
				free = free + 1
				i = i + 1
			end
			if i > 1 then
				plan.Moved[#plan.Moved + 1] = key
			end
		end
	end
	if #plan.Closed == 0 and #plan.Open == 0 then
		return nil
	end
	table.sort(plan.Closed)
	table.sort(plan.Moved)
	return plan
end

-- Drops (in place) every key without a free copy (owned more often than placed in the Garden / Gym) and every key past
-- the profile's team slots. `teams` is a clean Teams table; `profile` any profile-like table whose copies decide (the
-- live profile, a clean copy or a merged record). Returns true when something was dropped.
function P3.prune(profile, teams)
	local placed = P3.placedCopies(profile)
	local slots = P3.slotsOf(profile)
	local free = {}
	local changed = false
	for i = 1, P3.PRESETS do
		local list = teams.Presets[i]
		local kept = {}
		for _, key in ipairs(list) do
			if free[key] == nil then
				free[key] = ownedCount(profile, key) - (placed[key] or 0)
			end
			if free[key] >= 1 and #kept < slots then
				kept[#kept + 1] = key
			end
		end
		if #kept ~= #list then
			teams.Presets[i] = kept
			changed = true
		end
	end
	return changed
end

-- A clean, pruned copy of a profile's Teams.
function P3.teamsOf(profile)
	local teams = P3.cleanTeams(type(profile) == "table" and profile.Teams or nil)
	P3.prune(profile, teams)
	return teams
end

function P3.isDefaultTeams(teams)
	if teams.Active ~= 1 then
		return false
	end
	for i = 1, P3.PRESETS do
		if #teams.Presets[i] > 0 then
			return false
		end
	end
	return true
end

-- clean Teams -> the stored / synced form (Presets as a dense array of PRESETS lists)
function P3.encodeTeams(teams)
	local presets = {}
	for i = 1, P3.PRESETS do
		presets[i] = copyList(teams.Presets[i])
	end
	return { Presets = presets, Active = teams.Active }
end

-- A cleared trial level: a whole number 1..MAX_TRIAL_LEVEL (a numeric string too), or nil.
function P3.trialLevel(value)
	local n = value
	if type(value) == "string" and string.find(value, "^%d+$") then
		n = tonumber(value)
	end
	if isFinite(n) and n >= 1 and n <= P3.MAX_TRIAL_LEVEL and n == math.floor(n) then
		return n
	end
	return nil
end

-- Untrusted cleared set: { [level] = true }, the stored / synced dense array of booleans (false = not cleared) or a
-- list of level numbers -> { [level] = true }.
function P3.cleanCleared(raw)
	local out = {}
	for key, value in pairs(tableOr(raw)) do
		local level = nil
		if value == true then
			level = P3.trialLevel(key)
		elseif type(key) == "number" and type(value) == "number" then
			level = P3.trialLevel(value)
		end
		if level then
			out[level] = true
		end
	end
	return out
end

-- Untrusted Battle -> a clean record: whole numbers >= 0, TrialBest >= the highest cleared level.
function P3.cleanBattle(raw)
	local r = tableOr(raw)
	local battle = P3.newBattle()
	for _, field in ipairs(P3.COUNTERS) do
		battle[field] = sanitize(r[field])
	end
	battle.RaidBestDamage = sanitize(r.RaidBestDamage)
	battle.TrialBest = clampCount(r.TrialBest, P3.MAX_TRIAL_LEVEL)
	battle.TrialCleared = P3.cleanCleared(r.TrialCleared)
	for level in pairs(battle.TrialCleared) do
		if level > battle.TrialBest then
			battle.TrialBest = level
		end
	end
	battle.EventPets = cleanSet(r.EventPets)
	return battle
end

-- { [field] = true } of the fields that differ between two clean records
function P3.battleChanges(a, b)
	local out = {}
	for _, field in ipairs(P3.COUNTERS) do
		if a[field] ~= b[field] then
			out[field] = true
		end
	end
	for _, field in ipairs(P3.BESTS) do
		if a[field] ~= b[field] then
			out[field] = true
		end
	end
	if not mapsEqual(a.TrialCleared, b.TrialCleared) then
		out.TrialCleared = true
	end
	if not mapsEqual(a.EventPets, b.EventPets) then
		out.EventPets = true
	end
	return out
end

function P3.isDefaultBattle(battle)
	return next(P3.battleChanges(battle, P3.newBattle())) == nil
end

-- clean Battle -> the stored / synced form: TrialCleared as a dense array of booleans (index = level, never sparse)
function P3.encodeBattle(battle)
	local cleared, top = {}, 0
	for level in pairs(battle.TrialCleared) do
		if level > top then
			top = level
		end
	end
	for level = 1, top do
		cleared[level] = battle.TrialCleared[level] == true
	end
	return {
		Trophies = battle.Trophies,
		TrialBest = battle.TrialBest,
		TrialCleared = cleared,
		Raids = battle.Raids,
		RaidBestDamage = battle.RaidBestDamage,
		PvPWins = battle.PvPWins,
		PvPLosses = battle.PvPLosses,
		EventPets = copyMap(battle.EventPets),
	}
end

----------------------------------------------------------------------
-- Phase 4: pet growth (evolution stages + training ranks + the running job), the Champion Ring record and the
-- migration markers (pure helpers; they run inside UpdateAsync too). The format rules (ARCHITECTURE_V3.md "Phase 4
-- build contract" 4.1 / 4.2) are in the header.
----------------------------------------------------------------------

-- a growth entry with every number 0 and no Job
function P4.zeroEntry()
	local e = { Evo = 0 }
	for _, stat in ipairs(P4.STATS) do
		e[stat] = 0
	end
	return e
end

-- Untrusted Job -> a clean job for an entry whose ranks are final, or nil (dropped): Stat one of the four skills,
-- Ends a sane os.time() stamp > 0, Rank EXACTLY the stat's rank + 1 (a job whose target rank is not above the stored
-- rank was completed elsewhere and must never re-apply; a target further above cannot happen; rank 10 is the top),
-- Slot a Training Place mat 1..MAX_JOB_SLOT, From a short string (optional), Paid whole Cash >= 0 (the Stop refund).
function P4.cleanJob(raw, entry)
	if type(raw) ~= "table" then
		return nil
	end
	local stat = raw.Stat
	if not P4.STAT_SET[stat] then
		return nil
	end
	local target = entry[stat] + 1
	local rank = raw.Rank
	if not isFinite(rank) or math.floor(rank) ~= target or target > P4.MAX_RANK then
		return nil
	end
	local ends = sanitizeTime(raw.Ends)
	if ends <= 0 then
		return nil
	end
	local slot = raw.Slot
	if not isFinite(slot) or slot < 1 or slot > P4.MAX_JOB_SLOT or slot ~= math.floor(slot) then
		return nil
	end
	local job = { Stat = stat, Ends = ends, Rank = target, Slot = slot, Paid = sanitizeCash(raw.Paid) }
	if type(raw.From) == "string" and #raw.From >= 1 and #raw.From <= P4.MAX_FROM then
		job.From = raw.From
	end
	return job
end

-- Untrusted growth entry -> { Evo 0..2, Speed, Physique, Ability, Defense 0..10, Job? } (fresh tables), or nil for
-- junk and for an entry that is all zeros without a Job (keeps the save small).
function P4.cleanEntry(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local e = P4.zeroEntry()
	e.Evo = clampCount(raw.Evo, P4.MAX_EVO)
	local any = e.Evo > 0
	for _, stat in ipairs(P4.STATS) do
		local rank = clampCount(raw[stat], P4.MAX_RANK)
		e[stat] = rank
		any = any or rank > 0
	end
	local job = P4.cleanJob(raw.Job, e)
	if job then
		e.Job = job
		any = true
	end
	if not any then
		return nil
	end
	return e
end

-- Untrusted PetGrowth map (live, stored or synced) -> { [validKey] = clean entry }
function P4.cleanGrowth(raw)
	local out = {}
	for key, entry in pairs(tableOr(raw)) do
		local clean = validKey(key) and P4.cleanEntry(entry)
		if clean then
			out[key] = clean
		end
	end
	return out
end

-- clean growth -> the stored / synced form: zero numbers left out (every reader fills them: cleanEntry here,
-- State.PetGrowth on the client), the Job copied. ~80 bytes per fully trained, evolved key.
function P4.encodeGrowth(growth)
	local out = {}
	for key, e in pairs(growth) do
		local rec = {}
		if e.Evo > 0 then
			rec.Evo = e.Evo
		end
		for _, stat in ipairs(P4.STATS) do
			if e[stat] > 0 then
				rec[stat] = e[stat]
			end
		end
		if e.Job then
			rec.Job = copyMap(e.Job)
		end
		out[key] = rec
	end
	return out
end

-- { [key] = true } of every key with a running job: the training lock. Any growth map (live, clean or stored); junk
-- is ignored (a junk job never survives a clean anyway).
function P4.trainingSet(growth)
	local out = {}
	for key, entry in pairs(tableOr(growth)) do
		if validKey(key) and type(entry) == "table" and type(entry.Job) == "table" and P4.STAT_SET[entry.Job.Stat] then
			out[key] = true
		end
	end
	return out
end

-- The PetGrowth delta (both clean), or nil: every changed key -> its whole clean live entry, where Job is the live
-- job when the session changed it, `false` when the session cleared a job the base had, and absent when the session
-- left it alone (the stored job then stays: a job another server started is never wiped by a session that never saw
-- it); a key the session removed -> false.
function P4.diffGrowth(live, base)
	local out, any = {}, false
	for key, e in pairs(live) do
		local b = base[key]
		if b == nil or not deepEqual(e, b) then
			local d = P4.zeroEntry()
			d.Evo = e.Evo
			for _, stat in ipairs(P4.STATS) do
				d[stat] = e[stat]
			end
			local liveJob, baseJob = e.Job, b and b.Job or nil
			if liveJob then
				if not (baseJob and deepEqual(liveJob, baseJob)) then
					d.Job = copyMap(liveJob)
				end
			elseif baseJob then
				d.Job = false
				d.JobDone = { Stat = baseJob.Stat, Rank = baseJob.Rank } -- WHICH job ended (P4.newerJob keeps a newer stored one)
			end
			out[key] = d
			any = true
		end
	end
	for key in pairs(base) do
		if live[key] == nil then
			out[key] = false
			any = true
		end
	end
	if not any then
		return nil
	end
	return out
end

-- true when the STORED job `cur` is a newer job of the same key than `ref` (the job a session ended or started): the
-- same skill at a higher target rank. Two servers holding one player (the rollout minutes, an outage's late leave
-- save) can race: server B completes Speed 2 -> 3 and starts 3 -> 4 while server A's later save still ends the 2 -> 3
-- job (or starts its own stale 2 -> 3): A must not wipe B's paid rank-4 job. A job of another skill, or at the same /
-- a lower target, is the same job or an older one and follows the session's value (the sanitizer then drops it when
-- it is stale).
function P4.newerJob(cur, ref)
	return type(cur) == "table" and type(ref) == "table" and cur.Stat == ref.Stat and isFinite(cur.Rank) and isFinite(ref.Rank) and cur.Rank > ref.Rank
end

-- Per key: Evo and every rank keep the HIGHER value (a rank is a target value: two servers completing one job give
-- one rank), the Job follows the delta (a table replaces, false + JobDone clears, absent keeps the stored one; a
-- stored job that is NEWER than the one the session ended or started survives, P4.newerJob), a key marked false goes;
-- then the map is cleaned: a Job whose target rank is not above the merged rank (completed elsewhere) is dropped and
-- empty entries go.
function P4.applyGrowth(out, dg)
	if not dg then
		return
	end
	local map = out.PetGrowth
	for key, d in pairs(dg) do
		if d == false then
			map[key] = nil
		elseif type(d) == "table" then
			local cur = map[key] or P4.zeroEntry()
			cur.Evo = math.max(cur.Evo, clampCount(d.Evo, P4.MAX_EVO))
			for _, stat in ipairs(P4.STATS) do
				cur[stat] = math.max(cur[stat], clampCount(d[stat], P4.MAX_RANK))
			end
			if d.Job == false then
				if not P4.newerJob(cur.Job, d.JobDone) then
					cur.Job = nil
				end
			elseif type(d.Job) == "table" then
				if not P4.newerJob(cur.Job, d.Job) then
					cur.Job = copyMap(d.Job)
				end
			end
			map[key] = cur
		end
	end
	out.PetGrowth = P4.cleanGrowth(map)
end

-- Untrusted ring record -> { Best = 0..MAX_RING, Runs >= 0 } (whole numbers)
function P4.cleanRing(raw)
	local r = tableOr(raw)
	return { Best = clampCount(r.Best, P4.MAX_RING), Runs = sanitize(r.Runs) }
end

function P4.isDefaultRing(ring)
	return ring.Best == 0 and ring.Runs == 0
end

-- The Ring delta (both clean), or nil: Best as a candidate when it rose, Runs as a +/- delta.
function P4.diffRing(live, base)
	local d, any = { Best = nil, Runs = nil }, false
	if live.Best > base.Best then
		d.Best = live.Best
		any = true
	end
	if live.Runs ~= base.Runs then
		d.Runs = live.Runs - base.Runs
		any = true
	end
	if not any then
		return nil
	end
	return d
end

function P4.applyRing(out, dr)
	if not dr then
		return
	end
	local ring = out.Ring
	if isFinite(dr.Best) and dr.Best > ring.Best then
		ring.Best = clampCount(dr.Best, P4.MAX_RING)
	end
	if isFinite(dr.Runs) then
		ring.Runs = sanitize(ring.Runs + dr.Runs) -- never below 0
	end
end

-- Live (possibly messy) profile -> clean profile with whole numbers. Read defensively: other modules mutate it.
local function copyProfile(p)
	local out = newProfile()
	out.Tokens = p.Tokens
	out.Pets = copyMap(p.Pets)
	out.Equipped = copyList(p.Equipped)
	out.Items = copyMap(p.Items)
	for _, key in ipairs(STAT_KEYS) do
		out.Stats[key] = p.Stats[key]
	end
	out.Stats.BestTimes = copyMap(p.Stats.BestTimes)
	out.SpotIndex = p.SpotIndex
	-- v3
	out.Tiers = cleanTiers(p.Tiers) -- before discoverOwned: tier copies count as discovered too
	out.Discovered = cleanSet(p.Discovered)
	discoverOwned(out) -- a pet granted without MarkDiscovered still saves as discovered
	out.IndexClaimed = cleanSet(p.IndexClaimed)
	out.Tutorial = cleanTutorial(p.Tutorial)
	-- Phase 2
	out.Cash = sanitizeCash(p.Cash)
	out.Gems = sanitize(p.Gems)
	out.Home = cleanHome(p.Home, false)
	out.PetLevels = copyPetLevels(p.PetLevels)
	out.Food = cleanCounts(p.Food, MAX_FOOD)
	out.Hybrids = cleanHybrids(p.Hybrids)
	out.GemReceipts = cleanReceipts(p.GemReceipts)
	-- Phase 4 (before the presets: the live Equipped list is copied as it is, but the growth map is read everywhere)
	out.PetGrowth = P4.cleanGrowth(p.PetGrowth)
	out.Ring = P4.cleanRing(p.Ring)
	out.Migrations = cleanSet(p.Migrations)
	-- Phase 5
	out.Dungeon = P5.cleanDungeon(p.Dungeon)
	out.Berries = P5.cleanBerries(p.Berries)
	out.Settings = P5.cleanSettings(p.Settings)
	-- Phase 3 (the copies, the Home and its prestige are final above: the presets are pruned against them)
	out.Teams = P3.cleanTeams(p.Teams)
	P3.prune(out, out.Teams)
	out.Battle = P3.cleanBattle(p.Battle)
	return out
end

-- Untrusted stored value (nil / number / v1 table / v2 table / v3 table / Phase 2 table) -> clean profile. Pure.
-- `info` (optional): a table that receives GardenMoved = { key... } when P3.gardenSolo took pets out of the Garden.
local function normalizeProfile(raw, info)
	local p = newProfile()
	if type(raw) == "number" then
		p.Tokens = sanitize(raw)
		return p
	end
	if type(raw) ~= "table" then
		return p
	end
	p.Tokens = sanitize(raw.Tokens)
	if type(raw.Pets) == "table" then
		for id, n in pairs(raw.Pets) do
			if validKey(id) then
				local count = clampCount(n, Config.Pets.MaxPerStack)
				if count > 0 then
					p.Pets[id] = count
				end
			end
		end
	end
	if type(raw.Items) == "table" then
		for id, n in pairs(raw.Items) do
			if validKey(id) then
				local count = clampCount(n, Config.Items.MaxCarry)
				if count > 0 then
					p.Items[id] = count
				end
			end
		end
	end
	if type(raw.Equipped) == "table" then
		for _, id in ipairs(raw.Equipped) do
			if type(id) == "string" then
				table.insert(p.Equipped, id)
			end
		end
	end
	if type(raw.Stats) == "table" then
		for _, key in ipairs(STAT_KEYS) do
			p.Stats[key] = sanitize(raw.Stats[key])
		end
		if type(raw.Stats.BestTimes) == "table" then
			for id, seconds in pairs(raw.Stats.BestTimes) do
				local clean = sanitizeSeconds(seconds)
				if validKey(id) and clean then
					p.Stats.BestTimes[id] = clean
				end
			end
		end
	end
	local spot = raw.SpotIndex
	if isFinite(spot) and spot >= 1 and spot <= Config.Lobby.SpotCount and spot == math.floor(spot) then
		p.SpotIndex = spot
	end
	-- Phase 2 copies first: the equipped list may hold tier / hybrid keys; Phase 4 growth too: a training key may not
	-- stay equipped (a Phase 3 server may have equipped it during the rollout)
	p.Tiers = cleanTiers(raw.Tiers)
	p.Hybrids = cleanHybrids(raw.Hybrids)
	p.PetGrowth = P4.cleanGrowth(raw.PetGrowth)
	p.Ring = P4.cleanRing(raw.Ring)
	p.Migrations = cleanSet(raw.Migrations)
	-- Phase 5 (absent in older saves: the defaults stay; the P5 migrations run on the live profile after the load)
	p.Dungeon = P5.cleanDungeon(raw.Dungeon)
	p.Berries = P5.cleanBerries(raw.Berries)
	p.Settings = P5.cleanSettings(raw.Settings)
	normalizeEquipped(p)
	-- v3 fields (absent in v2 saves: the defaults from newProfile stay)
	p.Discovered = cleanSet(raw.Discovered)
	discoverOwned(p) -- migration: owned pets count as discovered
	p.IndexClaimed = cleanSet(raw.IndexClaimed)
	p.Tutorial = cleanTutorial(raw.Tutorial)
	p.Cash = sanitizeCash(raw.Cash)
	p.Gems = sanitize(raw.Gems)
	p.Home = cleanHome(raw.Home, true) -- migration: the v3 reserve Home.Rooms becomes Home.Stations
	p.PetLevels = copyPetLevels(raw.PetLevels)
	p.Food = cleanCounts(raw.Food, MAX_FOOD)
	p.GemReceipts = cleanReceipts(raw.GemReceipts, true)
	-- Phase 3 (migration: a Phase 2 profile has no Teams / Battle and gets the defaults; stale keys are pruned)
	p.Teams = P3.cleanTeams(raw.Teams)
	-- bug batch 2 #18: a pet both in the Garden and equipped / in a preset (an old save) leaves the Garden FIRST, so
	-- the prune below (which counts Garden copies now) never takes a fighter out of its team
	local moved = P3.gardenSolo(p)
	if moved and type(info) == "table" then
		info.GardenMoved = moved
	end
	P3.prune(p, p.Teams)
	p.Battle = P3.cleanBattle(raw.Battle)
	return p
end

-- Both arguments are clean profiles (normalizeProfile / copyProfile results).
local function profilesEqual(a, b)
	if a.Tokens ~= b.Tokens or a.SpotIndex ~= b.SpotIndex then
		return false
	end
	if not listsEqual(a.Equipped, b.Equipped) then
		return false
	end
	if not mapsEqual(a.Pets, b.Pets) or not mapsEqual(a.Items, b.Items) then
		return false
	end
	for _, key in ipairs(STAT_KEYS) do
		if a.Stats[key] ~= b.Stats[key] then
			return false
		end
	end
	if not mapsEqual(a.Stats.BestTimes, b.Stats.BestTimes) then
		return false
	end
	-- v3
	if a.Cash ~= b.Cash or a.Gems ~= b.Gems then
		return false
	end
	if not mapsEqual(a.Discovered, b.Discovered) or not mapsEqual(a.IndexClaimed, b.IndexClaimed) then
		return false
	end
	if not tutorialsEqual(a.Tutorial, b.Tutorial) then
		return false
	end
	-- Phase 2
	if not homesEqual(a.Home, b.Home) or not mapsEqual(a.Food, b.Food) or not mapsEqual(a.GemReceipts, b.GemReceipts) then
		return false
	end
	return deepEqual(a.PetLevels, b.PetLevels)
		and deepEqual(a.Tiers, b.Tiers)
		and deepEqual(a.Hybrids, b.Hybrids)
		and deepEqual(a.Teams, b.Teams)
		and deepEqual(a.Battle, b.Battle)
		-- Phase 4
		and deepEqual(a.PetGrowth, b.PetGrowth)
		and deepEqual(a.Ring, b.Ring)
		and mapsEqual(a.Migrations, b.Migrations)
		-- Phase 5
		and deepEqual(a.Dungeon, b.Dungeon)
		and a.Berries == b.Berries
		and P5.settingsEqual(a.Settings, b.Settings)
end

----------------------------------------------------------------------
-- Delta merge (the heart of the safe-save design)
----------------------------------------------------------------------

local function diffCounts(live, base)
	local out = {}
	for id, n in pairs(live) do
		local delta = n - (base[id] or 0)
		if delta ~= 0 then
			out[id] = delta
		end
	end
	for id, n in pairs(base) do
		if live[id] == nil then
			out[id] = -n
		end
	end
	return out
end

-- Keys the session added to a grow-only set (removals never travel).
local function diffSet(live, base)
	local out = {}
	local b = tableOr(base)
	for key, value in pairs(tableOr(live)) do
		if value and not b[key] and validKey(key) then
			out[key] = true
		end
	end
	return out
end

-- Per-key replacements of a clean map: key -> new value, or false when the session removed it.
local function diffReplace(live, base, equal)
	local out = {}
	for key, value in pairs(live) do
		if base[key] == nil or not equal(value, base[key]) then
			out[key] = value
		end
	end
	for key in pairs(base) do
		if live[key] == nil then
			out[key] = false
		end
	end
	return out
end

local function sameValue(a, b)
	return a == b
end

local function samePetLevel(a, b)
	return a.Level == b.Level and a.Xp == b.Xp
end

-- Untrusted best-times map -> { [difficultyId] = seconds } with valid keys and sane seconds only.
local function cleanBestTimes(raw)
	local out = {}
	for id, seconds in pairs(tableOr(raw)) do
		local clean = sanitizeSeconds(seconds)
		if validKey(id) and clean then
			out[id] = clean
		end
	end
	return out
end

-- The values a pending ResetFields writes over the store: the session's CURRENT values of those fields.
local function overwriteValues(live, overwrite)
	if type(overwrite) ~= "table" then
		return nil
	end
	local out = {}
	if overwrite.Discovered then
		out.Discovered = cleanSet(live.Discovered)
	end
	if overwrite.IndexClaimed then
		out.IndexClaimed = cleanSet(live.IndexClaimed)
	end
	if overwrite.Tutorial then
		out.Tutorial = cleanTutorial(live.Tutorial)
	end
	if overwrite.BestTimes then
		out.BestTimes = cleanBestTimes(type(live.Stats) == "table" and live.Stats.BestTimes)
	end
	if overwrite.Home then
		out.Home = cleanHome(live.Home, false)
	end
	if overwrite.Tiers then
		out.Tiers = cleanTiers(live.Tiers)
	end
	if overwrite.Hybrids then
		out.Hybrids = cleanHybrids(live.Hybrids)
	end
	if overwrite.PetLevels then
		out.PetLevels = copyPetLevels(live.PetLevels)
	end
	if overwrite.Teams then
		out.Teams = P3.teamsOf(live)
	end
	if overwrite.Battle then
		out.Battle = P3.cleanBattle(live.Battle)
	end
	-- Phase 4
	if overwrite.PetGrowth then
		out.PetGrowth = P4.cleanGrowth(live.PetGrowth)
	end
	if overwrite.Ring then
		out.Ring = P4.cleanRing(live.Ring)
	end
	if overwrite.Migrations then
		out.Migrations = cleanSet(live.Migrations)
	end
	-- Phase 5 (the dev reset: Best max / Cleared union would bring the record back)
	if overwrite.Dungeon then
		out.Dungeon = P5.cleanDungeon(live.Dungeon)
	end
	if next(out) == nil then
		return nil
	end
	return out
end

-- The Teams delta (both clean): { Presets = { [i] = list } (only the presets the session changed), Active = n | nil },
-- or nil when the session changed nothing.
function P3.diffTeams(live, base)
	local d = { Presets = {}, Active = nil }
	local any = false
	for i = 1, P3.PRESETS do
		if not listsEqual(live.Presets[i], base.Presets[i]) then
			d.Presets[i] = copyList(live.Presets[i])
			any = true
		end
	end
	if live.Active ~= base.Active then
		d.Active = live.Active
		any = true
	end
	if not any then
		return nil
	end
	return d
end

-- Per preset: a changed preset replaces the stored one (the caller prunes once the owned copies are final).
function P3.applyTeams(out, d)
	if not d then
		return
	end
	for i, list in pairs(d.Presets) do
		out.Teams.Presets[i] = copyList(list)
	end
	if d.Active ~= nil then
		out.Teams.Active = d.Active
	end
end

-- The Battle delta (both clean), or nil: counters as +/- deltas, best values as candidates, cleared levels and event
-- pets as additions (removals never travel: those sets only grow).
function P3.diffBattle(live, base)
	local d = { Counters = {}, Best = {}, Cleared = {}, EventPets = {} }
	local any = false
	for _, field in ipairs(P3.COUNTERS) do
		local delta = live[field] - base[field]
		if delta ~= 0 then
			d.Counters[field] = delta
			any = true
		end
	end
	for _, field in ipairs(P3.BESTS) do
		if live[field] > base[field] then
			d.Best[field] = live[field]
			any = true
		end
	end
	for level in pairs(live.TrialCleared) do
		if not base.TrialCleared[level] then
			d.Cleared[level] = true
			any = true
		end
	end
	for id in pairs(live.EventPets) do
		if not base.EventPets[id] then
			d.EventPets[id] = true
			any = true
		end
	end
	if not any then
		return nil
	end
	return d
end

function P3.applyBattle(out, d)
	if not d then
		return
	end
	local battle = out.Battle
	for field, delta in pairs(d.Counters) do
		battle[field] = sanitize(battle[field] + delta) -- Trophies (like every counter) never below 0
	end
	for field, value in pairs(d.Best) do
		if value > battle[field] then
			battle[field] = value
		end
	end
	for level in pairs(d.Cleared) do
		battle.TrialCleared[level] = true
	end
	for id in pairs(d.EventPets) do
		battle.EventPets[id] = true
	end
	out.Battle = P3.cleanBattle(battle) -- TrialBest >= the highest cleared level
end

-- The Home delta, or nil when the session did not change the Home. Whole = the session's complete home (it wins
-- when its prestige is higher than the stored one); the rest is the per-key merge used at equal prestige.
-- BasePrestige / CollectorNow: when the session prestiged to the star the store also holds, its Collector filled up
-- from 0 after that prestige (a delta against the pre-prestige base would wipe the store's Collector).
local function diffHome(liveRaw, baseRaw)
	local live, base = cleanHome(liveRaw, false), cleanHome(baseRaw, false)
	if homesEqual(live, base) then
		return nil
	end
	local d = {
		Whole = live,
		Prestige = live.Prestige,
		BasePrestige = base.Prestige,
		Level = nil,
		Stations = diffReplace(live.Stations, base.Stations, sameValue),
		Garden = diffReplace(live.Garden, base.Garden, sameValue),
		Gym = diffReplace(live.Gym, base.Gym, sameValue),
		CollectorCash = live.CollectorCash - base.CollectorCash,
		CollectorNow = live.CollectorCash,
		LastSeen = nil,
		-- Phase 4 (per-key replace): the new value, false when the session cleared it, nil when untouched
		LegacySlots = nil,
		LegacyPrices = nil,
		-- Phase 5 (per-key replace too): DecorCredit, LegacyMagnet (+ LegacyMagnetStar travels with it)
		DecorCredit = nil,
		LegacyMagnet = nil,
		LegacyMagnetStar = nil,
	}
	if live.Level ~= base.Level then
		d.Level = live.Level
	end
	if live.LastSeen ~= base.LastSeen then
		d.LastSeen = live.LastSeen
	end
	if live.LegacySlots ~= base.LegacySlots then
		d.LegacySlots = live.LegacySlots or false
	end
	if live.LegacyPrices ~= base.LegacyPrices then
		d.LegacyPrices = live.LegacyPrices or false
	end
	if live.DecorCredit ~= base.DecorCredit then
		d.DecorCredit = live.DecorCredit or false
	end
	if live.LegacyMagnet ~= base.LegacyMagnet or live.LegacyMagnetStar ~= base.LegacyMagnetStar then
		d.LegacyMagnet = live.LegacyMagnet or false
		d.LegacyMagnetStar = live.LegacyMagnetStar
	end
	return d
end

-- { [star] = gems } the prestige reward TycoonService paid for every star in fromStars+1 .. toStars (empty without
-- TycoonCatalog). Resolved here, outside UpdateAsync, so the merge itself stays pure.
local function starRewards(fromStars, toStars)
	local out = {}
	local catalog = getTycoonCatalog()
	if toStars <= fromStars or not catalog or type(catalog.PrestigeGems) ~= "function" then
		return out
	end
	for star = fromStars + 1, math.min(toStars, fromStars + 100) do
		local ok, gems = pcall(catalog.PrestigeGems, star)
		if ok and isFinite(gems) and gems >= 1 then
			out[star] = math.floor(gems) -- TycoonService.Prestige pays math.floor(PrestigeGems(stars))
		end
	end
	return out
end

-- What changed between `base` and `live`. Counters travel as +/- deltas, "best" values as
-- candidates, sets as additions, lists / single values as replacements. `live` may be the raw live
-- profile, so every v3 / Phase 2 field is read defensively. `overwrite` (the entry's pending ResetFields, or nil)
-- adds d.Overwrite: whole fields that replace the stored ones before anything else is merged.
-- `opts` (optional): { ReceiptGems = { [purchaseId] = gems } (MarkReceipt), StandIn = true when `base` is not data
-- read from the store (the load has not finished or failed: the delta then merges plainly) }. The delta carries what
-- the prestige rule of applyDelta needs: BasePrestige / LivePrestige, CashNow (the live balance), StarGems (the
-- reward of every star the session reached since its base) and ReceiptGems (the gems of each new receipt).
local function diffProfiles(live, base, overwrite, opts)
	opts = type(opts) == "table" and opts or {}
	local baseStars = clampCount(type(base.Home) == "table" and base.Home.Prestige or 0, MAX_LEVEL)
	local liveStars = clampCount(type(live.Home) == "table" and live.Home.Prestige or 0, MAX_LEVEL)
	local d = {
		Tokens = live.Tokens - base.Tokens,
		Pets = diffCounts(live.Pets, base.Pets),
		Items = diffCounts(live.Items, base.Items),
		Stats = {},
		BestTimes = {},
		Equipped = nil,
		HasSpot = false,
		SpotIndex = nil,
		-- v3
		Discovered = diffSet(live.Discovered, base.Discovered),
		IndexClaimed = diffSet(live.IndexClaimed, base.IndexClaimed),
		Tutorial = nil,
		-- whole units only (like copyProfile), so a fractional live balance can never keep a delta alive
		Cash = sanitizeCash(live.Cash) - sanitizeCash(base.Cash),
		Gems = sanitize(live.Gems) - sanitize(base.Gems),
		PetLevels = diffReplace(copyPetLevels(live.PetLevels), copyPetLevels(base.PetLevels), samePetLevel),
		-- Phase 2
		Home = diffHome(live.Home, base.Home),
		Food = diffCounts(cleanCounts(live.Food, MAX_FOOD), cleanCounts(base.Food, MAX_FOOD)),
		Tiers = diffReplace(cleanTiers(live.Tiers), cleanTiers(base.Tiers), deepEqual),
		Hybrids = diffReplace(cleanHybrids(live.Hybrids), cleanHybrids(base.Hybrids), deepEqual),
		GemReceipts = {},
		-- Phase 3 (the live presets are pruned the way copyProfile prunes them, so a stale key never keeps a delta alive)
		Teams = P3.diffTeams(P3.teamsOf(live), P3.teamsOf(base)),
		Battle = P3.diffBattle(P3.cleanBattle(live.Battle), P3.cleanBattle(base.Battle)),
		-- Phase 4: growth per key (nil when unchanged), the ring record (Best candidate / Runs delta), new markers
		PetGrowth = P4.diffGrowth(P4.cleanGrowth(live.PetGrowth), P4.cleanGrowth(base.PetGrowth)),
		Ring = P4.diffRing(P4.cleanRing(live.Ring), P4.cleanRing(base.Ring)),
		Migrations = diffSet(live.Migrations, base.Migrations),
		-- Phase 5: the dungeon record (Best candidate, Cleared union, Runs / Clears deltas, the migration's Clears as
		-- a floor), berries as a +/- delta, the settings whole when the session changed them (the live session wins)
		Dungeon = P5.diffDungeon(P5.cleanDungeon(live.Dungeon), P5.cleanDungeon(base.Dungeon), opts.DungeonMigrated),
		Berries = P5.cleanBerries(live.Berries) - P5.cleanBerries(base.Berries),
		-- the part of that delta the session's own P5Home step converted from Food (the m15 twin: a store another
		-- server already marked P5Home holds its own conversion, so applyDelta leaves these out there)
		BerriesMigrated = (isFinite(opts.BerriesMigrated) and opts.BerriesMigrated > 0) and math.floor(opts.BerriesMigrated) or nil,
		Settings = nil,
		Overwrite = overwriteValues(live, overwrite),
		-- the prestige rule for Cash and the star rewards (applyDelta); receipt gems (no double grant)
		BasePrestige = baseStars,
		LivePrestige = liveStars,
		CashNow = sanitizeCash(live.Cash),
		StandIn = opts.StandIn == true,
		StarGems = {},
		ReceiptGems = {},
	}
	if not d.StandIn and liveStars > baseStars then
		d.StarGems = starRewards(baseStars, liveStars)
	end
	for _, key in ipairs(STAT_KEYS) do
		local delta = live.Stats[key] - base.Stats[key]
		if delta ~= 0 then
			d.Stats[key] = delta
		end
	end
	for id, seconds in pairs(live.Stats.BestTimes) do
		if base.Stats.BestTimes[id] ~= seconds then
			d.BestTimes[id] = seconds
		end
	end
	if not listsEqual(live.Equipped, base.Equipped) then
		d.Equipped = copyList(live.Equipped)
	end
	if live.SpotIndex ~= base.SpotIndex then
		d.HasSpot = true
		d.SpotIndex = live.SpotIndex
	end
	local liveTutorial = cleanTutorial(live.Tutorial)
	if not tutorialsEqual(liveTutorial, cleanTutorial(base.Tutorial)) then
		d.Tutorial = liveTutorial
	end
	local liveSettings = P5.cleanSettings(live.Settings)
	if not P5.settingsEqual(liveSettings, P5.cleanSettings(base.Settings)) then
		d.Settings = liveSettings
	end
	local baseReceipts = cleanReceipts(base.GemReceipts)
	local receiptGems = type(opts.ReceiptGems) == "table" and opts.ReceiptGems or {}
	for id, t in pairs(cleanReceipts(live.GemReceipts)) do
		if baseReceipts[id] == nil then
			d.GemReceipts[id] = t
			local gems = receiptGems[id]
			if isFinite(gems) and gems >= 1 then
				d.ReceiptGems[id] = math.floor(gems)
			end
		end
	end
	return d
end

local function isEmptyDelta(d)
	return d.Tokens == 0
		and next(d.Pets) == nil
		and next(d.Items) == nil
		and next(d.Stats) == nil
		and next(d.BestTimes) == nil
		and d.Equipped == nil
		and not d.HasSpot
		and next(d.Discovered) == nil
		and next(d.IndexClaimed) == nil
		and d.Tutorial == nil
		and d.Cash == 0
		and d.Gems == 0
		and next(d.PetLevels) == nil
		and d.Home == nil
		and next(d.Food) == nil
		and next(d.Tiers) == nil
		and next(d.Hybrids) == nil
		and next(d.GemReceipts) == nil
		and d.Teams == nil
		and d.Battle == nil
		and d.PetGrowth == nil
		and d.Ring == nil
		and next(d.Migrations) == nil
		and d.Dungeon == nil
		and d.Berries == 0
		and d.Settings == nil
		and d.Overwrite == nil
end

local function applyCounts(target, deltas, maxCount)
	for id, delta in pairs(deltas) do
		local value = clampCount((target[id] or 0) + delta, maxCount)
		if value > 0 then
			target[id] = value
		else
			target[id] = nil
		end
	end
end

local function applyReplace(target, changes)
	for key, value in pairs(changes) do
		if value == false then
			target[key] = nil
		else
			target[key] = deepCopy(value)
		end
	end
end

-- Home merge: a higher prestige wins the whole Home; at equal prestige the session's changes merge per key.
-- When BOTH sides prestiged to the stored star (the session's base is an earlier run), the session's delta against
-- that base mixes its prestige reset with what it built since. Both runs started from the same reset home (decor
-- kept) and stations only go up within a run, so every station keeps the higher of the two levels (a station the
-- session's prestige reset does not remove the one the other run rebuilt), the Home Level grows by what that adds
-- (it is the sum of the station levels), and the session's Collector, which filled from 0 after its prestige, joins
-- the stored one.
local function applyHome(out, dh)
	if not dh then
		return
	end
	local stored = out.Home
	if dh.Prestige > stored.Prestige then
		out.Home = cleanHome(dh.Whole, false) -- the session prestiged past the store
		return
	end
	if stored.Prestige > dh.Prestige then
		return -- another server prestiged past this session: its stations were reset, the session's edits are void
	end
	if isFinite(dh.BasePrestige) and dh.BasePrestige < dh.Prestige then
		local gained = 0
		for key, level in pairs(dh.Stations) do
			local current = stored.Stations[key] or 0
			if isFinite(level) and level > current then
				stored.Stations[key] = level
				gained = gained + (level - current)
			end
		end
		stored.Level = clampCount(stored.Level + gained, MAX_LEVEL)
		stored.CollectorCash = sanitizeCash(stored.CollectorCash + (isFinite(dh.CollectorNow) and dh.CollectorNow or 0))
	else
		if dh.Level ~= nil then
			stored.Level = dh.Level
		end
		applyReplace(stored.Stations, dh.Stations)
		stored.CollectorCash = sanitizeCash(stored.CollectorCash + dh.CollectorCash)
	end
	applyReplace(stored.Garden, dh.Garden) -- garden / gym choices survive a prestige: the session's edits count
	applyReplace(stored.Gym, dh.Gym)
	if dh.LastSeen ~= nil and dh.LastSeen > stored.LastSeen then
		stored.LastSeen = dh.LastSeen
	end
	-- Phase 4: the veteran extras merge per key too (a value replaces, false removes, nil leaves the stored one)
	if dh.LegacySlots == false then
		stored.LegacySlots = nil
	elseif isFinite(dh.LegacySlots) and dh.LegacySlots >= 1 then
		stored.LegacySlots = math.min(math.floor(dh.LegacySlots), MAX_SLOT)
	end
	if dh.LegacyPrices == false then
		stored.LegacyPrices = nil
	elseif dh.LegacyPrices == true then
		stored.LegacyPrices = true
	end
	-- Phase 5: the folded Home keys merge per key the same way (a higher Prestige won the whole Home above and
	-- CARRIES its DecorCredit; the magnet keys are cleared by that prestige)
	if dh.DecorCredit == false then
		stored.DecorCredit = nil
	elseif isFinite(dh.DecorCredit) and dh.DecorCredit >= 1 then
		stored.DecorCredit = math.min(math.floor(dh.DecorCredit), P5.MAX_DECOR_CREDIT)
	end
	if dh.LegacyMagnet == false then
		stored.LegacyMagnet = nil
		stored.LegacyMagnetStar = nil
	elseif isFinite(dh.LegacyMagnet) and dh.LegacyMagnet >= 1 then
		stored.LegacyMagnet = math.min(math.floor(dh.LegacyMagnet), P5.MAX_MAGNET)
		stored.LegacyMagnetStar = clampCount(dh.LegacyMagnetStar, MAX_LEVEL)
	end
end

-- stored profile + delta -> new profile. Pure (runs inside UpdateAsync, which may retry it).
local function applyDelta(stored, d)
	local out = copyProfile(stored)
	-- a pending ResetFields first replaces whole fields, so the union / sticky / best-of / prestige merges below
	-- cannot bring the stored values back (they then merge the session's own changes onto the replaced value)
	local o = d.Overwrite
	if o then
		if o.Discovered then
			out.Discovered = copyMap(o.Discovered)
		end
		if o.IndexClaimed then
			out.IndexClaimed = copyMap(o.IndexClaimed)
		end
		if o.Tutorial then
			out.Tutorial = cleanTutorial(o.Tutorial)
		end
		if o.BestTimes then
			out.Stats.BestTimes = copyMap(o.BestTimes)
		end
		if o.Home then
			out.Home = cleanHome(o.Home, false)
		end
		if o.Tiers then
			out.Tiers = deepCopy(o.Tiers)
		end
		if o.Hybrids then
			out.Hybrids = deepCopy(o.Hybrids)
		end
		if o.PetLevels then
			out.PetLevels = deepCopy(o.PetLevels)
		end
		if o.Teams then
			out.Teams = P3.cleanTeams(o.Teams)
		end
		if o.Battle then
			out.Battle = P3.cleanBattle(o.Battle)
		end
		if o.PetGrowth then
			out.PetGrowth = P4.cleanGrowth(o.PetGrowth)
		end
		if o.Ring then
			out.Ring = P4.cleanRing(o.Ring)
		end
		if o.Migrations then
			out.Migrations = cleanSet(o.Migrations)
		end
		if o.Dungeon then
			out.Dungeon = P5.cleanDungeon(o.Dungeon)
		end
	end
	out.Tokens = sanitize(out.Tokens + d.Tokens)
	applyCounts(out.Pets, d.Pets, Config.Pets.MaxPerStack)
	applyCounts(out.Items, d.Items, Config.Items.MaxCarry)
	for key, delta in pairs(d.Stats) do
		out.Stats[key] = sanitize(out.Stats[key] + delta)
	end
	for id, seconds in pairs(d.BestTimes) do
		local current = out.Stats.BestTimes[id]
		if current == nil or seconds < current then
			out.Stats.BestTimes[id] = seconds
		end
	end
	if d.Equipped then
		out.Equipped = copyList(d.Equipped)
	end
	if d.HasSpot then
		out.SpotIndex = d.SpotIndex
	end
	-- v3
	for id in pairs(d.Discovered) do
		out.Discovered[id] = true
	end
	for id in pairs(d.IndexClaimed) do
		out.IndexClaimed[id] = true
	end
	if d.Tutorial then
		-- the session's step wins; Done and Gifted stick once true (the gift can never be paid twice)
		out.Tutorial = {
			Step = d.Tutorial.Step,
			Done = d.Tutorial.Done or out.Tutorial.Done,
			Gifted = d.Tutorial.Gifted or out.Tutorial.Gifted,
		}
	end
	-- Cash follows the Home's prestige rule (applyHome; a prestige resets Cash like the stations), and a star reward
	-- both sides paid counts once. B = the session's base prestige, L = its live prestige, S = the stored one:
	--   L > B and L > S  the session prestiged past the store: its balance (Cash since that prestige) is the Cash
	--   S > B, L == S    both prestiged to S: the session's Cash since its prestige joins the store's
	--   S > B, L < S     the store prestiged past the session's run: that run's Cash was reset (delta dropped)
	--   otherwise        a plain delta
	-- Skipped for a ResetFields Home (written over the store as it is) and a stand-in base (not store data).
	local cashDelta, gemDelta = d.Cash, d.Gems
	if not (o and o.Home) and not d.StandIn and isFinite(d.BasePrestige) and isFinite(d.LivePrestige) then
		local s, b, l = out.Home.Prestige, d.BasePrestige, d.LivePrestige
		if l > b and l > s then
			cashDelta = sanitizeCash(d.CashNow) - out.Cash
		elseif s > b then
			if l == s then
				cashDelta = sanitizeCash(d.CashNow)
			else
				cashDelta = 0
			end
		end
		-- stars b+1 .. min(l, s) were reached and paid by the server that wrote the store too
		local top = math.min(l, s)
		for star, gems in pairs(type(d.StarGems) == "table" and d.StarGems or {}) do
			if star > b and star <= top and isFinite(gems) then
				gemDelta = gemDelta - gems
			end
		end
	end
	-- a purchase whose receipt the store already holds was granted by another server: its gems are not added again
	-- (out.GemReceipts is still the stored set here: the receipts merge below)
	if type(d.ReceiptGems) == "table" then
		for id in pairs(d.GemReceipts) do
			local gems = d.ReceiptGems[id]
			if out.GemReceipts[id] ~= nil and isFinite(gems) then
				gemDelta = gemDelta - gems
			end
		end
	end
	out.Cash = sanitizeCash(out.Cash + cashDelta)
	out.Gems = sanitize(out.Gems + gemDelta)
	applyReplace(out.PetLevels, d.PetLevels)
	-- Phase 2
	if not (o and o.Home) then
		applyHome(out, d.Home) -- an overwritten Home already is the session's whole Home
	end
	applyCounts(out.Food, d.Food, MAX_FOOD)
	applyReplace(out.Tiers, d.Tiers)
	applyReplace(out.Hybrids, d.Hybrids)
	for id, t in pairs(d.GemReceipts) do
		local current = out.GemReceipts[id]
		if current == nil or t > current then
			out.GemReceipts[id] = t
		end
	end
	trimReceipts(out.GemReceipts, d.GemReceipts)
	-- Phase 3: presets per preset, the battle record by its rules. An overwritten field already is the session's whole
	-- value (its counters must not count the session's delta a second time).
	if not (o and o.Teams) then
		P3.applyTeams(out, d.Teams)
	end
	if not (o and o.Battle) then
		P3.applyBattle(out, d.Battle)
	end
	-- Phase 4: growth per key (the higher Evo / ranks, the session's Job), the ring record (Best max, Runs delta),
	-- the migration markers (union; an overwritten set already holds the session's additions)
	if not (o and o.PetGrowth) then
		P4.applyGrowth(out, d.PetGrowth)
	end
	if not (o and o.Ring) then
		P4.applyRing(out, d.Ring)
	end
	-- Phase 5: whether the STORE already held the P5Home marker before this merge (another server converted the same
	-- Food into berries, or this session's own earlier save landed): read from the stored record itself, before the
	-- union below and regardless of a pending Migrations overwrite
	local homeMarked = tableOr(stored.Migrations)[P5.HOME_MARK] == true
	for name in pairs(tableOr(d.Migrations)) do
		if validKey(name) then
			out.Migrations[name] = true
		end
	end
	-- Phase 5: the dungeon record by its rules (an overwritten record already is the session's whole value), berries
	-- as a delta clamped at 0 (a two-server race costs at most one feed, Y9) MINUS the session's own Food conversion
	-- when the store was already marked P5Home (it holds the conversion then: two servers migrating one Phase 4 save
	-- do not double the berries, the twin of the m15 Clears rule), the settings of the live session
	if not (o and o.Dungeon) then
		P5.applyDungeon(out, d.Dungeon)
	end
	if isFinite(d.Berries) then
		local delta = d.Berries
		if homeMarked and isFinite(d.BerriesMigrated) and d.BerriesMigrated > 0 then
			delta = delta - d.BerriesMigrated
		end
		out.Berries = P5.cleanBerries(out.Berries + delta)
	end
	if type(d.Settings) == "table" then
		out.Settings = P5.cleanSettings(d.Settings)
	end
	-- last: the owned copies (Pets, Tiers, Hybrids), the Home and the growth map (the training lock) are final now
	normalizeEquipped(out)
	discoverOwned(out)
	P3.prune(out, out.Teams)
	return out
end

-- Clean profile -> the table written to the store (no Rooms alias, slot maps encoded, empty Phase 2 maps left out).
local function toStored(p)
	local stats = { BestTimes = copyMap(p.Stats.BestTimes) }
	for _, key in ipairs(STAT_KEYS) do
		stats[key] = p.Stats[key]
	end
	local h = p.Home
	local rec = {
		Version = PROFILE_VERSION,
		Tokens = p.Tokens,
		Pets = copyMap(p.Pets),
		Equipped = copyList(p.Equipped),
		Items = copyMap(p.Items),
		Stats = stats,
		SpotIndex = p.SpotIndex,
		Discovered = copyMap(p.Discovered),
		IndexClaimed = copyMap(p.IndexClaimed),
		Tutorial = cleanTutorial(p.Tutorial),
		Cash = p.Cash,
		Gems = p.Gems,
		Home = {
			Level = h.Level,
			Prestige = h.Prestige,
			Stations = copyMap(h.Stations),
			Garden = encodeSlots(h.Garden),
			Gym = encodeSlots(h.Gym),
			CollectorCash = h.CollectorCash,
			LastSeen = h.LastSeen,
			LegacySlots = h.LegacySlots, -- Phase 4: absent unless the migration wrote them
			LegacyPrices = h.LegacyPrices,
			DecorCredit = h.DecorCredit, -- Phase 5: absent unless the fold wrote them
			LegacyMagnet = h.LegacyMagnet,
			LegacyMagnetStar = h.LegacyMagnetStar,
		},
		PetLevels = deepCopy(p.PetLevels),
	}
	if next(p.Food) ~= nil then
		rec.Food = copyMap(p.Food)
	end
	if next(p.Tiers) ~= nil then
		rec.Tiers = deepCopy(p.Tiers)
	end
	if next(p.Hybrids) ~= nil then
		rec.Hybrids = deepCopy(p.Hybrids)
	end
	if next(p.GemReceipts) ~= nil then
		rec.GemReceipts = copyMap(p.GemReceipts)
	end
	-- Phase 3: left out while they hold the defaults (most players never battle)
	if not P3.isDefaultTeams(p.Teams) then
		rec.Teams = P3.encodeTeams(p.Teams)
	end
	if not P3.isDefaultBattle(p.Battle) then
		rec.Battle = P3.encodeBattle(p.Battle)
	end
	-- Phase 4: left out while empty / default (zero numbers inside growth entries left out too)
	if next(p.PetGrowth) ~= nil then
		rec.PetGrowth = P4.encodeGrowth(p.PetGrowth)
	end
	if not P4.isDefaultRing(p.Ring) then
		rec.Ring = { Best = p.Ring.Best, Runs = p.Ring.Runs }
	end
	if next(p.Migrations) ~= nil then
		rec.Migrations = copyMap(p.Migrations)
	end
	-- Phase 5: left out while default / 0 (Cleared as a dense boolean array)
	if not P5.isDefaultDungeon(p.Dungeon) then
		rec.Dungeon = P5.encodeDungeon(p.Dungeon)
	end
	if p.Berries > 0 then
		rec.Berries = p.Berries
	end
	if not P5.isDefaultSettings(p.Settings) then
		rec.Settings = copyMap(p.Settings)
	end
	return rec
end

-- Forward compatibility (runs inside UpdateAsync, so it stays pure): `record` was rebuilt from the keys this
-- version knows, so it gets back every stored key it does not own (top level, inside Home and inside Stats) and
-- a newer Version number. An older server still running after a later phase is published then never erases that
-- phase's data. Known keys are never copied back (a cleared SpotIndex must stay cleared, spent Food stays spent).
local function keepForeign(record, old)
	if type(old) ~= "table" then
		return record
	end
	for key, value in pairs(old) do
		if not KNOWN_TOP[key] then
			record[key] = value
		end
	end
	if type(old.Home) == "table" then
		for key, value in pairs(old.Home) do
			if not KNOWN_HOME[key] then
				record.Home[key] = value
			end
		end
	end
	if type(old.Stats) == "table" then
		for key, value in pairs(old.Stats) do
			if not KNOWN_STATS[key] then
				record.Stats[key] = value
			end
		end
	end
	if isFinite(old.Version) and old.Version > PROFILE_VERSION then
		record.Version = old.Version
	end
	return record
end

-- Clears `t` and copies `src` into it (deep copies of table values).
local function refill(t, src)
	for key in pairs(copyMap(t)) do
		t[key] = nil
	end
	for key, value in pairs(src) do
		t[key] = deepCopy(value)
	end
end

-- The table at holder[field], created when missing (replaceContents works in place).
local function ensureTable(holder, field)
	local t = holder[field]
	if type(t) ~= "table" then
		t = {}
		holder[field] = t
	end
	return t
end

-- Writes a clean home into the live home table IN PLACE (other modules may hold it); Rooms stays Stations.
local function writeHome(target, src)
	target.Level = src.Level
	target.Prestige = src.Prestige
	local stations = ensureTable(target, "Stations")
	refill(stations, src.Stations)
	target.Rooms = stations
	refill(ensureTable(target, "Garden"), src.Garden)
	refill(ensureTable(target, "Gym"), src.Gym)
	target.CollectorCash = src.CollectorCash
	target.LastSeen = src.LastSeen
	target.LegacySlots = src.LegacySlots -- Phase 4 (nil clears)
	target.LegacyPrices = src.LegacyPrices
	target.DecorCredit = src.DecorCredit -- Phase 5 (nil clears)
	target.LegacyMagnet = src.LegacyMagnet
	target.LegacyMagnetStar = src.LegacyMagnetStar
end

-- Overwrites the fields of `target` with `src` IN PLACE (other modules may hold the table).
local function replaceContents(target, src)
	target.Version = PROFILE_VERSION
	target.Tokens = src.Tokens
	target.SpotIndex = src.SpotIndex
	for _, field in ipairs({ "Pets", "Items", "Discovered", "IndexClaimed", "PetLevels", "Food", "Tiers", "Hybrids", "GemReceipts" }) do
		refill(ensureTable(target, field), src[field])
	end
	local equipped = ensureTable(target, "Equipped")
	for i = #equipped, 1, -1 do
		equipped[i] = nil
	end
	for i, id in ipairs(src.Equipped) do
		equipped[i] = id
	end
	local stats = ensureTable(target, "Stats")
	for _, key in ipairs(STAT_KEYS) do
		stats[key] = src.Stats[key]
	end
	refill(ensureTable(stats, "BestTimes"), src.Stats.BestTimes)
	-- v3 / Phase 2
	target.Cash = src.Cash
	target.Gems = src.Gems
	local tutorial = ensureTable(target, "Tutorial")
	tutorial.Step = src.Tutorial.Step
	tutorial.Done = src.Tutorial.Done
	tutorial.Gifted = src.Tutorial.Gifted
	writeHome(ensureTable(target, "Home"), src.Home)
	-- Phase 3 (in place too)
	refill(ensureTable(target, "Teams"), src.Teams)
	refill(ensureTable(target, "Battle"), src.Battle)
	-- Phase 4 (in place too)
	refill(ensureTable(target, "PetGrowth"), src.PetGrowth)
	refill(ensureTable(target, "Ring"), src.Ring)
	refill(ensureTable(target, "Migrations"), src.Migrations)
	-- Phase 5 (in place too)
	refill(ensureTable(target, "Dungeon"), src.Dungeon)
	target.Berries = src.Berries
	refill(ensureTable(target, "Settings"), src.Settings)
end

-- Prunes the LIVE presets in place (keys that lost their free copy: fused away, released, placed in the Garden / Gym;
-- a junk structure is repaired too). Returns true when the live Teams changed; the caller fires TeamsChanged once it
-- is done (handlers run at once).
function P3.pruneLive(entry)
	local profile = entry.Profile
	local teams = P3.teamsOf(profile)
	if deepEqual(profile.Teams, teams) then
		return false
	end
	refill(ensureTable(profile, "Teams"), teams)
	entry.Dirty = true
	return true
end

-- diffProfiles options of an entry: the gems of the receipts it marked, and whether its Base is a stand-in (the
-- load has not finished, or failed and was not recovered yet: the Base is defaults, not store data).
local function deltaOpts(entry)
	return {
		ReceiptGems = entry.ReceiptGems,
		StandIn = entry.LoadFailed == true or entry.Loaded ~= true,
		-- Phase 5: the Clears the session's own P5Dungeon migration wrote (merge as a max until the store holds them)
		DungeonMigrated = entry.DungeonMigrated,
		-- Phase 5: the berries the session's own P5Home step converted from Food (left out of the merge when the store
		-- already holds another server's conversion)
		BerriesMigrated = entry.BerriesMigrated,
	}
end

-- Drops the receipt amounts the entry no longer needs: receipts the store holds (they are in Base) or the live
-- profile lost (taken back / trimmed). Only receipts still on their way to the store are looked up.
local function pruneReceiptGems(entry)
	local map = entry.ReceiptGems
	if type(map) ~= "table" then
		return
	end
	local live = tableOr(entry.Profile.GemReceipts)
	local saved = type(entry.Base) == "table" and tableOr(entry.Base.GemReceipts) or {}
	for id in pairs(copyMap(map)) do
		if live[id] == nil or saved[id] ~= nil then
			map[id] = nil
		end
	end
	if next(map) == nil then
		entry.ReceiptGems = nil
	end
end

-- Moves the live profile onto freshly read store data while keeping everything the session did
-- since `fromBase`. `newBase` becomes the new "known to be in the store" reference. A pending ResetFields
-- keeps the session's values of its fields (they are still to be written over the store).
local function rebase(entry, fromBase, stored, newBase)
	local d = diffProfiles(entry.Profile, fromBase, entry.Overwrite, deltaOpts(entry))
	local merged = applyDelta(stored, d)
	replaceContents(entry.Profile, merged)
	entry.Base = copyProfile(newBase)
end

----------------------------------------------------------------------
-- Player mirrors + remotes
----------------------------------------------------------------------

-- Mirror a token total onto the player (attribute for the HUD, leaderstats for the leaderboard).
local function pushToPlayer(player, value)
	if not player or not player.Parent then
		return
	end
	player:SetAttribute(Config.Attr.Tokens, value)
	local stats = player:FindFirstChild("leaderstats")
	local tokensValue = stats and stats:FindFirstChild("Tokens")
	if tokensValue then
		tokensValue.Value = value
	end
end

-- Mirror the Cash / Gems balances (whole units) onto the player for the HUD currency stack.
local function pushCurrencies(player, profile)
	if not player or not player.Parent or type(profile) ~= "table" then
		return
	end
	if Config.Attr.Cash then
		player:SetAttribute(Config.Attr.Cash, sanitizeCash(profile.Cash))
	end
	if Config.Attr.Gems then
		player:SetAttribute(Config.Attr.Gems, sanitize(profile.Gems))
	end
end

-- Phase 5: mirrors the whole berries onto the player (Config.Attr.Berries) at most twice a second per player: the
-- first write goes out at once, later ones wait for the end of the BERRIES_GAP window (a trailing write; a Berries-only
-- change never triggers a ProfileSync, C14). `now` forces the write (load, leave).
function P5.pushBerries(player, now)
	if not player or not player.Parent or not Config.Attr.Berries then
		return
	end
	local userId = player.UserId
	local entry = cache[userId]
	if not entry then
		return
	end
	local push = P5.pushes[userId]
	if not push then
		push = { last = -math.huge, queued = false }
		P5.pushes[userId] = push
	end
	local clock = os.clock()
	if now or clock - push.last >= P5.BERRIES_GAP then
		push.last = clock
		player:SetAttribute(Config.Attr.Berries, P5.cleanBerries(entry.Profile.Berries))
		return
	end
	if push.queued then
		return
	end
	push.queued = true
	task.delay(P5.BERRIES_GAP - (clock - push.last), function()
		push.queued = false
		if cache[userId] == entry and player.Parent then
			push.last = os.clock()
			player:SetAttribute(Config.Attr.Berries, P5.cleanBerries(entry.Profile.Berries))
		end
	end)
end

local function pushAll(player, profile)
	pushToPlayer(player, profile.Tokens)
	pushCurrencies(player, profile)
	P5.pushBerries(player, true)
end

local function getRemote(name)
	local cached = remoteCache[name]
	if cached and cached.Parent then
		return cached
	end
	local ok, remote = pcall(Remotes.Get, name)
	if ok and remote then
		remoteCache[name] = remote
		return remote
	end
	return nil
end

local PERK_KEYS = { "MaxHealth", "TokenBonus", "StaminaRegen", "CheckpointHeal" }

-- Perk totals of a list of keys: each copy's perks x its tier multiplier (PetKeys.DefOf + StatMultiplier), each total
-- capped and rounded like PetCatalog.SumPerks (so Normal-only lists give exactly the same numbers).
local function sumKeyPerks(keys, equipped, profile)
	local sums = {}
	for _, key in ipairs(PERK_KEYS) do
		sums[key] = 0
	end
	for _, key in ipairs(equipped) do
		local ok, def = pcall(keys.DefOf, key, profile)
		if ok and type(def) == "table" and type(def.Perks) == "table" then
			local mult = 1
			if def.Tier ~= nil and type(keys.StatMultiplier) == "function" then
				local okMult, m = pcall(keys.StatMultiplier, def.Tier)
				if okMult and isFinite(m) and m > 0 then
					mult = m
				end
			end
			for perk, value in pairs(def.Perks) do
				if sums[perk] ~= nil and type(value) == "number" then
					sums[perk] = sums[perk] + value * mult
				end
			end
		end
	end
	local caps = Config.Pets.PerkCaps
	for perk, total in pairs(sums) do
		local cap = caps[perk]
		if type(cap) == "number" and total > cap then
			total = cap
		end
		sums[perk] = math.floor(total * 10000 + 0.5) / 10000
	end
	return sums
end

-- Equipped keys -> { MaxHealth, TokenBonus, StaminaRegen, CheckpointHeal } (summed, capped). `profile` is needed for
-- hybrid keys (their record); plain pet ids and tier keys work without it.
function DataService.ComputePerks(equipped, profile)
	local perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 }
	if type(equipped) ~= "table" then
		return perks
	end
	local summed = nil
	local keys = getPetKeys()
	if keys and type(keys.DefOf) == "function" then
		local ok, result = pcall(sumKeyPerks, keys, equipped, profile)
		if ok then
			summed = result
		end
	end
	if not summed then
		local catalog = getPetCatalog()
		if catalog and type(catalog.SumPerks) == "function" then
			local ok, result = pcall(catalog.SumPerks, equipped)
			if ok and type(result) == "table" then
				summed = result
			end
		end
	end
	if type(summed) == "table" then
		for _, key in ipairs(PERK_KEYS) do
			local value = summed[key]
			if isFinite(value) and value > 0 then
				local cap = Config.Pets.PerkCaps[key]
				if cap and value > cap then
					value = cap
				end
				perks[key] = value
			end
		end
	end
	return perks
end

-- Discovered ids for the client (owned pets always included): only pets the catalog knows (a retired
-- pet must not count towards "Unlocked: x/N"). Without a catalog the set is sent unfiltered.
local function discoveredSnapshot(profile)
	local set = cleanSet(profile.Discovered)
	for id, count in pairs(tableOr(profile.Pets)) do
		if validKey(id) and type(count) == "number" and count > 0 then
			set[id] = true
		end
	end
	for id in pairs(cleanTiers(profile.Tiers)) do
		set[id] = true
	end
	local catalog = getPetCatalog()
	if not catalog or type(catalog.Get) ~= "function" then
		return set
	end
	local out = {}
	for id in pairs(set) do
		local ok, def = pcall(catalog.Get, id)
		if ok and def then
			out[id] = true
		end
	end
	return out
end

-- What the client sees of the Home (slot maps encoded like the store; no LastSeen).
local function homeSnapshot(rawHome)
	local h = cleanHome(rawHome, false)
	return {
		Level = h.Level,
		Prestige = h.Prestige,
		Stations = h.Stations,
		Garden = encodeSlots(h.Garden),
		Gym = encodeSlots(h.Gym),
		CollectorCash = h.CollectorCash,
		LegacySlots = h.LegacySlots, -- Phase 4 (absent for most homes)
		LegacyPrices = h.LegacyPrices,
		DecorCredit = h.DecorCredit, -- Phase 5 (the fold; absent for most homes)
		LegacyMagnet = h.LegacyMagnet,
		LegacyMagnetStar = h.LegacyMagnetStar,
	}
end

-- What the client (and GetTeams) sees of the battle teams: the pruned presets, the active one and the slot count.
function P3.teamsSnapshot(profile)
	local out = P3.encodeTeams(P3.teamsOf(profile))
	out.Slots = P3.slotsOf(profile)
	return out
end

-- Plain-table snapshot for the client (no Instances, no shared references).
local function buildSnapshot(profile)
	local stats = profile.Stats
	return {
		Tokens = profile.Tokens,
		Pets = copyMap(profile.Pets),
		Equipped = copyList(profile.Equipped),
		Items = copyMap(profile.Items),
		Stats = {
			Matches = stats.Matches,
			Wins = stats.Wins,
			TokensEarned = stats.TokensEarned,
			Spins = stats.Spins,
			BestTimes = copyMap(stats.BestTimes),
		},
		SpotIndex = profile.SpotIndex,
		Perks = DataService.ComputePerks(profile.Equipped, profile),
		-- v3
		Discovered = discoveredSnapshot(profile),
		IndexClaimed = cleanSet(profile.IndexClaimed),
		Tutorial = cleanTutorial(profile.Tutorial),
		-- Phase 2
		Cash = sanitizeCash(profile.Cash),
		Gems = sanitize(profile.Gems),
		Home = homeSnapshot(profile.Home),
		Food = cleanCounts(profile.Food, MAX_FOOD),
		Tiers = cleanTiers(profile.Tiers),
		Hybrids = cleanHybrids(profile.Hybrids),
		PetLevels = copyPetLevels(profile.PetLevels),
		-- Phase 3 (small: 3 presets of up to 4 keys, a handful of numbers, one boolean per trial level)
		Teams = P3.teamsSnapshot(profile),
		Battle = P3.encodeBattle(P3.cleanBattle(profile.Battle)),
		-- Phase 4 (growth entries without their zero numbers; the ring record always whole)
		PetGrowth = P4.encodeGrowth(P4.cleanGrowth(profile.PetGrowth)),
		Ring = P4.cleanRing(profile.Ring),
		-- Phase 5 (<= 60 B dungeon record with a dense Cleared array, the berries, every setting always)
		Dungeon = P5.encodeDungeon(P5.cleanDungeon(profile.Dungeon)),
		Berries = P5.cleanBerries(profile.Berries),
		Settings = P5.cleanSettings(profile.Settings),
	}
end

----------------------------------------------------------------------
-- DataStore access
----------------------------------------------------------------------

-- Records a DataStore failure. Studio without API access is expected, so it stays silent there.
local function noteFailure(what, err)
	local message = tostring(err)
	if
		string.find(message, "StudioAccessToApisNotAllowed", 1, true)
		or string.find(message, "Studio access to APIs", 1, true)
		or string.find(message, "Enable Studio Access", 1, true)
		or string.find(message, "publish this place", 1, true) -- an unpublished place in Studio
	then
		storeDisabled = true -- stop hammering an API that will keep refusing us
		return
	end
	if not IS_STUDIO then
		warn(string.format("[DataService] %s failed: %s", what, message))
	end
end

-- The DataStore object, or nil when unavailable. Resolved lazily and only once.
local function getStore()
	if storeDisabled then
		return nil
	end
	if not storeResolved then
		storeResolved = true
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(Config.Tokens.DataStoreName)
		end)
		if ok then
			store = result
		else
			noteFailure("GetDataStore", result)
		end
	end
	return store
end

-- true while the entry holds stand-in defaults: its load failed although the store is usable (an outage), and the
-- recovery has not read the real save yet. Without a usable store (Studio without API access) the in-memory
-- profile is all there is, so it is never provisional.
local function isProvisional(entry)
	return entry ~= nil and entry.LoadFailed == true and getStore() ~= nil
end

local function getLegacyStore()
	if storeDisabled then
		return nil
	end
	if not legacyResolved then
		legacyResolved = true
		local name = Config.Tokens.LegacyDataStoreName
		if type(name) == "string" and name ~= "" then
			local ok, result = pcall(function()
				return DataStoreService:GetDataStore(name)
			end)
			if ok then
				legacyStore = result
			else
				noteFailure("GetDataStore(legacy)", result)
			end
		end
	end
	return legacyStore
end

-- GetAsync with one retry. Returns ok:boolean, value.
local function readKey(dataStore, key)
	for attempt = 1, 2 do
		local ok, result = pcall(function()
			return dataStore:GetAsync(key)
		end)
		if ok then
			return true, result
		end
		noteFailure("load", result)
		if storeDisabled or attempt == 2 then
			break
		end
		task.wait(RETRY_DELAY)
	end
	return false, nil
end

-- Reads a player's stored profile.
-- Returns ok, profile|nil, migrated. ok=false means "could not read" (nothing may be assumed).
-- profile == nil with ok=true means a brand-new player. migrated=true means the profile was built
-- from a v1 save and the v2 key does not exist yet.
local function fetchProfile(userId)
	local s = getStore()
	if not s then
		return false, nil, false
	end
	local ok, raw = readKey(s, keyFor(userId))
	if not ok then
		return false, nil, false
	end
	if raw ~= nil then
		-- the 4th value: the raw record held a preset longer than 3 keys (Phase 5, 4.8: Load fires TeamsChanged once);
		-- the 5th: the keys P3.gardenSolo took out of the Garden (bug batch 2 #18) or nil
		local info = {}
		local profile = normalizeProfile(raw, info)
		return true, profile, false, P5.hadLongPreset(raw), info.GardenMoved
	end
	-- Nothing in v2: look for a v1 save to migrate.
	local legacy = getLegacyStore()
	if legacy then
		local okLegacy, old = readKey(legacy, keyFor(userId))
		if not okLegacy then
			return false, nil, false
		end
		if old ~= nil then
			local migrated = newProfile()
			if type(old) == "table" then
				migrated.Tokens = sanitize(old.Tokens)
			else
				migrated.Tokens = sanitize(old)
			end
			return true, migrated, true
		end
	end
	return true, nil, false
end

----------------------------------------------------------------------
-- Cache entries, locking, loading
----------------------------------------------------------------------

local function ensureEntry(userId)
	local entry = cache[userId]
	if not entry then
		entry = {
			Profile = newProfile(),
			Base = newProfile(),
			Loaded = false,
			Loading = false,
			LoadFailed = false,
			Saving = false,
			Dirty = false,
			RecoveryScheduled = false,
			Orphan = false,
			OrphanSince = 0,
			OrphanScheduled = false,
		}
		cache[userId] = entry
	end
	return entry
end

-- Waits (bounded) for an in-flight load to finish.
local function waitForLoad(entry)
	local waited = 0
	while entry.Loading and waited < 40 do
		task.wait(0.1)
		waited = waited + 0.1
	end
end

-- Simple per-entry write lock (autosave vs. PlayerRemoving vs. BindToClose vs. recovery).
local function acquire(entry)
	local waited = 0
	while entry.Saving and waited < 20 do
		task.wait(0.25)
		waited = waited + 0.25
	end
	if entry.Saving then
		return false
	end
	entry.Saving = true
	return true
end

local function loadEntry(player)
	local userId = player.UserId
	local entry = ensureEntry(userId)
	if entry.Loaded then
		return entry, false
	end
	if entry.Loading then
		waitForLoad(entry)
		return entry, false
	end

	entry.Loading = true
	local fetched, stored, migrated, trimmed, moved = false, nil, false, false, nil
	local pok, a, b, c, d, e = pcall(fetchProfile, userId)
	if pok then
		fetched, stored, migrated, trimmed, moved = a, b, c, d == true, e
	else
		warn("[DataService] fetch errored: " .. tostring(a))
	end

	if fetched then
		-- Anything the session did before the load finished (early AddTokens) is kept on top.
		local source = stored or newProfile()
		local newBase = newProfile()
		if stored and not migrated then
			newBase = source
		end
		rebase(entry, entry.Base, source, newBase)
		entry.LoadFailed = false
		if trimmed then
			entry.TeamsTrimmed = true -- Phase 5 (4.8): a stored 4-key preset loads with 3; Load fires TeamsChanged once
		end
		entry.GardenMoved = moved -- bug batch 2 #18: pets that left the Garden on this read (P3.gardenAnnounce)
	else
		entry.LoadFailed = true -- play on with defaults; saves/recovery merge with the real data later
	end
	entry.Loaded = true
	entry.Loading = false
	return entry, true
end

-- Tells the player's systems that the live profile changed underneath them.
local function announceRebase(userId, entry)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end
	pushAll(player, entry.Profile)
	-- Phase 4: the one-time migration of a profile that arrives here from a recovered (provisional) load, before the
	-- snapshot and the signals (idempotent: a profile another server already migrated is left alone)
	local migrated = P4.migrateEntry(entry, player)
	local migrated5 = P5.migrateEntry(entry, player) -- Phase 5: after a recovered load too (idempotent)
	local garden = P3.gardenMigrate(entry) -- bug batch 2 #18: the marker + what this read took out of the Garden
	entry.TeamsTrimmed = nil
	DataService.Sync(player)
	DataService.ProfileRebased:Fire(player, entry.Profile)
	DataService.TeamsChanged:Fire(player) -- the presets may have come from another server
	P4.announceMigration(player, migrated)
	P5.announceMigration(player, migrated5)
	P3.gardenAnnounce(player, garden)
end

-- Re-reads the store for an entry whose load failed and merges the session on top of it.
-- Caller holds the entry lock. Returns true on success.
local function recover(entry, userId)
	local fetched, stored, migrated, _, moved = fetchProfile(userId)
	if not fetched then
		return false
	end
	entry.GardenMoved = moved -- bug batch 2 #18 (announced by announceRebase)
	local source = stored or newProfile()
	local newBase = newProfile()
	if stored and not migrated then
		newBase = source
	end
	rebase(entry, entry.Base, source, newBase)
	entry.LoadFailed = false
	announceRebase(userId, entry)
	return true
end

-- After a failed load, keep retrying in the background so the player gets their pets back.
local function scheduleRecovery(userId)
	local entry = cache[userId]
	if not entry or entry.RecoveryScheduled or storeDisabled then
		return
	end
	entry.RecoveryScheduled = true
	task.spawn(function()
		local delays = { 20, 40, 80, 160, 300 }
		for _, seconds in ipairs(delays) do
			task.wait(seconds)
			if cache[userId] ~= entry or not entry.LoadFailed or shuttingDown or storeDisabled then
				break
			end
			if not Players:GetPlayerByUserId(userId) then
				break
			end
			if acquire(entry) then
				local ok, err = pcall(recover, entry, userId)
				entry.Saving = false
				if not ok then
					warn("[DataService] recovery errored: " .. tostring(err))
				end
			end
		end
		entry.RecoveryScheduled = false
	end)
end

----------------------------------------------------------------------
-- Saving
----------------------------------------------------------------------

-- Body of a save; the caller holds the entry lock. Returns true when the store is up to date.
local function writeEntry(entry, userId)
	if entry.LoadFailed then
		if not recover(entry, userId) then
			return false -- never write blind: it could hide a v1 save or a v2 profile we could not read
		end
	end

	for attempt = 1, 2 do
		local s = getStore()
		if not s then
			return false
		end

		local overwriteGen = entry.OverwriteGen
		local snapshot = copyProfile(entry.Profile)
		local delta = diffProfiles(snapshot, entry.Base, entry.Overwrite, deltaOpts(entry))
		if isEmptyDelta(delta) then
			entry.Dirty = false
			return true
		end

		local result = nil
		local ok, err = pcall(function()
			result = s:UpdateAsync(keyFor(userId), function(old)
				-- Must be pure and non-yielding: UpdateAsync may call it more than once.
				local record = keepForeign(toStored(applyDelta(normalizeProfile(old), delta)), old)
				record.UpdatedAt = os.time()
				return record
			end)
		end)

		if ok then
			entry.Dirty = false
			if delta.Overwrite and entry.OverwriteGen == overwriteGen then
				entry.Overwrite = nil -- written; a ResetFields during the write stays pending for the next save
			end
			entry.DungeonMigrated = nil -- Phase 5: the store holds the migration's Clears now (the Base adopts them below)
			entry.BerriesMigrated = nil -- Phase 5: ...and the P5Home step's berries (counted there exactly once)
			if type(result) == "table" then
				local confirmed = normalizeProfile(result)
				if profilesEqual(confirmed, snapshot) then
					entry.Base = snapshot
				else
					-- The store held something different from what we assumed (another server,
					-- a recovered load): adopt it and re-apply whatever changed since the snapshot.
					rebase(entry, snapshot, confirmed, confirmed)
					announceRebase(userId, entry)
				end
			else
				entry.Base = snapshot
			end
			pruneReceiptGems(entry)
			return true
		end

		noteFailure("save", err)
		if storeDisabled then
			return false
		end
		if attempt == 1 then
			task.wait(RETRY_DELAY)
		end
	end
	return false
end

local function saveEntry(userId)
	local entry = cache[userId]
	if not entry then
		return false
	end
	waitForLoad(entry)
	if not getStore() then
		return false -- DataStores unavailable: the in-memory cache is all we have
	end
	if not acquire(entry) then
		return false
	end
	local ok, result = pcall(writeEntry, entry, userId)
	entry.Saving = false
	if not ok then
		if not IS_STUDIO then
			warn("[DataService] Save errored: " .. tostring(result))
		end
		return false
	end
	return result == true
end

-- pcall-safe save by user id (the player may be gone: orphaned entries are saved this way too).
local function safeSave(userId)
	local ok, result = pcall(saveEntry, userId)
	if not ok then
		if not IS_STUDIO then
			warn("[DataService] Save errored: " .. tostring(result))
		end
		return false
	end
	return result == true
end

-- Saves one player (pcall-safe, retries once, silent when DataStores are unavailable).
function DataService.Save(player)
	if not player then
		return false
	end
	return safeSave(player.UserId)
end

-- true when the store already holds everything the entry knows (nothing could be lost by dropping it).
-- An unreadable comparison counts as "not clean": keeping data is always the safe direction.
local function entryIsClean(entry)
	local ok, empty = pcall(function()
		return isEmptyDelta(diffProfiles(entry.Profile, entry.Base, entry.Overwrite, deltaOpts(entry)))
	end)
	return ok and empty == true
end

-- After a save attempt on a departed player's entry: drop it once it is safe (clean) or hopeless
-- (store unusable, or unsaved for ORPHAN_TIMEOUT seconds). A rejoined player owns the entry again.
local function settleOrphan(userId, entry)
	if cache[userId] ~= entry or not entry.Orphan or Players:GetPlayerByUserId(userId) then
		return
	end
	if entryIsClean(entry) then
		cache[userId] = nil
	elseif storeDisabled or os.clock() - entry.OrphanSince >= ORPHAN_TIMEOUT then
		warn(string.format("[DataService] giving up on unsaved progress of user %s", tostring(userId)))
		cache[userId] = nil
	end
end

-- Background retry (with backoff) for a departed player's unsaved entry. One loop per entry; it ends
-- when the entry is saved/dropped, the player rejoined (Load clears Orphan), or the server shuts down
-- (BindToClose makes the last attempt).
local function scheduleOrphanFlush(userId, entry)
	if entry.OrphanScheduled or shuttingDown then
		return
	end
	entry.OrphanScheduled = true
	task.spawn(function()
		local delay = ORPHAN_RETRY_FIRST
		while true do
			task.wait(delay)
			delay = math.min(delay * 2, ORPHAN_RETRY_MAX)
			if shuttingDown or cache[userId] ~= entry or not entry.Orphan then
				break
			end
			safeSave(userId)
			settleOrphan(userId, entry)
			if cache[userId] ~= entry or not entry.Orphan then
				break
			end
		end
		entry.OrphanScheduled = false
	end)
end

-- The player left: frees the cache entry, but ONLY when the store holds everything it knows. A failed
-- final save (outage, throttling, lock timeout, a load that never succeeded) would otherwise throw away
-- the only copy of the session's progress, so a dirty entry stays behind as an orphan and keeps being
-- retried (see the header). Skipped if the same user already rejoined.
function DataService.Release(player)
	if not player then
		return
	end
	local userId = player.UserId
	local current = Players:GetPlayerByUserId(userId)
	if current and current ~= player then
		return
	end
	lastRequest[userId] = nil
	local entry = cache[userId]
	if not entry then
		return
	end
	if storeDisabled or entryIsClean(entry) then
		cache[userId] = nil -- nothing can be (or is left to be) saved
		return
	end
	if not entry.Orphan then
		entry.Orphan = true
		entry.OrphanSince = os.clock()
	end
	scheduleOrphanFlush(userId, entry)
end

----------------------------------------------------------------------
-- Hooks: leave handler + RequestProfile
----------------------------------------------------------------------

local function onPlayerRemoving(player)
	-- PlayerService also saves (it does not release: Release is decided here); doing it here as well
	-- means a missing call can never lose data or leak the cache entry. Saving twice is a no-op
	-- (empty delta). Release keeps the entry when this save failed, see DataService.Release.
	-- Deferred so that the other PlayerRemoving handlers run first (their order is not guaranteed): what they
	-- write at leave time (PetCareService refunds the dishes still cooking, any other late write) is then in the
	-- snapshot of this save, or in its orphan retry. Started at once, a save with nothing to write returned
	-- without yielding and Release dropped the entry inside the dispatch, before those handlers ran: their
	-- writes were lost. A rejoin before this runs is fine: Load picks the entry up again and Release skips it.
	task.defer(function()
		DataService.Save(player)
		DataService.Release(player)
	end)
	-- Phase 5: the per-player SettingsSet bucket and the berries push state go with the player
	P5.buckets[player.UserId] = nil
	P5.pushes[player.UserId] = nil
end

local function hook()
	if not playerHooked then
		playerHooked = true
		Players.PlayerRemoving:Connect(onPlayerRemoving)
	end
	if not requestHooked then
		local remote = getRemote("RequestProfile")
		if remote then
			requestHooked = true
			remote.OnServerEvent:Connect(function(player)
				local userId = player.UserId
				local now = os.clock()
				local last = lastRequest[userId]
				if last and now - last < REQUEST_COOLDOWN then
					return
				end
				lastRequest[userId] = now
				DataService.Sync(player)
			end)
		end
	end
	-- Phase 5 (7.2): SettingsSet(key, value) from the client: 6/s with a burst of 6 per player, then SetSetting's
	-- whitelist / types / ranges (junk is dropped silently, Y11); the client applied the value locally already
	if not P5.settingsHooked then
		local remote = getRemote("SettingsSet")
		if remote then
			P5.settingsHooked = true
			remote.OnServerEvent:Connect(function(player, key, value)
				if not player or type(key) ~= "string" then
					return
				end
				local userId = player.UserId
				local now = os.clock()
				local b = P5.buckets[userId]
				if not b then
					b = { tokens = P5.SETTINGS_BURST, last = now }
					P5.buckets[userId] = b
				end
				b.tokens = math.min(P5.SETTINGS_BURST, b.tokens + (now - b.last) * P5.SETTINGS_RATE)
				b.last = now
				if b.tokens < 1 then
					return
				end
				b.tokens = b.tokens - 1
				DataService.SetSetting(player, key, value)
			end)
		end
	end
end

-- Optional explicit init (Load / StartAutosave / BindToClose do the same lazily).
function DataService.Init()
	hook()
end

----------------------------------------------------------------------
-- Public API: loading + profile access
----------------------------------------------------------------------

-- Phase 5 (7.1): the player attribute ProfileLoaded = true once the profile is loaded or provisional (written once; the
-- loading screen waits for it).
function P5.markProfileLoaded(player)
	local attr = (Config.Attr and Config.Attr.ProfileLoaded) or "ProfileLoaded"
	pcall(function()
		if player:GetAttribute(attr) ~= true then
			player:SetAttribute(attr, true)
		end
	end)
end

-- Never errors. Returns the LIVE profile (mutate, then MarkDirty + Sync).
function DataService.Load(player)
	if not player then
		return newProfile()
	end
	hook()
	local ok, entry, didLoad = pcall(loadEntry, player)
	if not ok or not entry then
		warn("[DataService] Load failed: " .. tostring(entry))
		local fallback = ensureEntry(player.UserId)
		fallback.Loading = false
		fallback.Loaded = true
		fallback.LoadFailed = true
		scheduleRecovery(player.UserId) -- provisional until the real save is read (see the header)
		P5.markProfileLoaded(player)
		return fallback.Profile
	end
	-- A quick rejoin can find the previous session's entry still in memory (its final save was in
	-- flight): the profile is current, but the NEW Player instance still needs its attributes.
	if didLoad or entry.Owner ~= player then
		entry.Owner = player
		entry.Orphan = false -- the (re)joined player owns the entry again; the orphan retry loop stands down
		pushAll(player, entry.Profile)
		if entry.LoadFailed then
			scheduleRecovery(player.UserId)
		end
		-- Phase 4: the one-time migration (section 4.3) of a loaded, non-provisional profile, in the same step as the
		-- load, so TycoonService's ProfileLoaded handler already sees the migrated Home (a provisional profile is
		-- migrated after its recovery, on ProfileRebased)
		local migrated = P4.migrateEntry(entry, player)
		-- Phase 5: the dungeon record from the old Trials and the home fold (section 9.2), in the same step
		local migrated5 = P5.migrateEntry(entry, player)
		-- bug batch 2 #18: the garden-exclusive marker + the pets the read took out of the Garden (old saves)
		local garden = P3.gardenMigrate(entry)
		DataService.Sync(player)
		DataService.ProfileLoaded:Fire(player, entry.Profile)
		if entry.TeamsTrimmed then
			entry.TeamsTrimmed = nil
			DataService.TeamsChanged:Fire(player) -- a stored 4-key preset loaded with 3 (4.8): once
		end
		P4.announceMigration(player, migrated)
		P5.announceMigration(player, migrated5)
		P3.gardenAnnounce(player, garden)
	end
	P5.markProfileLoaded(player)
	return entry.Profile
end

-- The live profile table, or nil until Load finished.
function DataService.GetProfile(player)
	local entry = player and cache[player.UserId]
	if entry and entry.Loaded then
		return entry.Profile
	end
	return nil
end

function DataService.MarkDirty(player)
	local entry = player and cache[player.UserId]
	if entry then
		entry.Dirty = true
	end
end

-- Fires ProfileSync(snapshot) to that player (no-op until the profile is loaded).
function DataService.Sync(player)
	if not player or not player.Parent then
		return
	end
	local entry = cache[player.UserId]
	if not entry or not entry.Loaded then
		return
	end
	-- Phase 3: keys that lost their copy since the last sync (a fusion, a release, ...) leave the live presets
	local pruned = P3.pruneLive(entry)
	local remote = getRemote("ProfileSync")
	if remote then
		entry.LastSync = os.clock()
		local ok, err = pcall(function()
			remote:FireClient(player, buildSnapshot(entry.Profile))
		end)
		if not ok then
			warn("[DataService] Sync failed: " .. tostring(err))
		end
	end
	if pruned then
		DataService.TeamsChanged:Fire(player)
	end
end

-- Extra: a throttled Sync for frequent small changes (food, pet XP, home edits): sends now when the last snapshot
-- is at least SYNC_GAP seconds old, otherwise once at the end of that window (several calls -> one snapshot).
function DataService.SyncSoon(player)
	local entry = player and cache[player.UserId]
	if not entry or not entry.Loaded or entry.SyncQueued then
		return
	end
	local elapsed = os.clock() - (entry.LastSync or -math.huge)
	if elapsed >= SYNC_GAP then
		DataService.Sync(player)
		return
	end
	entry.SyncQueued = true
	task.delay(SYNC_GAP - elapsed, function()
		entry.SyncQueued = false
		if cache[player.UserId] == entry then
			DataService.Sync(player)
		end
	end)
end

----------------------------------------------------------------------
-- v3: Pet Index discovery + tutorial progress
----------------------------------------------------------------------

-- Marks a pet as discovered (seen in the Pet Index). Returns true only the first time. Marks the
-- profile dirty but does not Sync: the caller does (PetService syncs right after every roll).
function DataService.MarkDiscovered(player, petId)
	if not player or not validKey(petId) then
		return false
	end
	local catalog = getPetCatalog()
	if catalog and type(catalog.Get) == "function" then
		local ok, def = pcall(catalog.Get, petId)
		if ok and not def then
			return false -- unknown pet id
		end
	end
	local entry = cache[player.UserId]
	if not entry then
		return false
	end
	local discovered = entry.Profile.Discovered
	if type(discovered) ~= "table" then
		discovered = {}
		entry.Profile.Discovered = discovered
	end
	if discovered[petId] == true then
		return false
	end
	discovered[petId] = true
	entry.Dirty = true
	return true
end

-- Extra: true when the player has discovered (ever owned / rolled) that pet.
function DataService.IsDiscovered(player, petId)
	local entry = player and cache[player.UserId]
	if not entry or type(petId) ~= "string" then
		return false
	end
	local discovered = entry.Profile.Discovered
	return type(discovered) == "table" and discovered[petId] == true
end

-- Extra: true while the player's profile is a stand-in (its load failed during a DataStore outage and the real
-- save has not been read yet). One-time rewards (tutorial gift, Index claims) and developer resets wait for it.
function DataService.IsProvisional(player)
	local entry = player and cache[player.UserId]
	return entry ~= nil and entry.Loaded == true and isProvisional(entry)
end

-- A copy of the tutorial progress { Step, Done, Gifted }, or nil until the profile is loaded. Also nil while the
-- profile is provisional: its defaults would start a returning player's tutorial again (gift and finish reward
-- included). TutorialService keeps polling and starts from the real progress once the recovery fired
-- ProfileRebased.
function DataService.GetTutorial(player)
	local entry = player and cache[player.UserId]
	if not entry or not entry.Loaded or isProvisional(entry) then
		return nil
	end
	return cleanTutorial(entry.Profile.Tutorial)
end

-- Stores tutorial progress (MarkDirty + Sync). Step is clamped to a whole number >= 1; Done and Gifted
-- stick once true (the store merges them the same way, so a gift can never be paid twice).
-- Returns true when stored (false until the profile is loaded, while it is provisional, or for a non-table
-- argument).
function DataService.SetTutorial(player, tutorial)
	if not player or type(tutorial) ~= "table" then
		return false
	end
	local entry = cache[player.UserId]
	if not entry or not entry.Loaded or isProvisional(entry) then
		return false
	end
	local profile = entry.Profile
	local current = cleanTutorial(profile.Tutorial)
	local wanted = cleanTutorial(tutorial)
	local live = profile.Tutorial
	if type(live) ~= "table" then
		live = {}
		profile.Tutorial = live
	end
	live.Step = wanted.Step
	live.Done = wanted.Done or current.Done
	live.Gifted = wanted.Gifted or current.Gifted
	entry.Dirty = true
	DataService.Sync(player)
	return true
end

-- Extra (developer tools only): the session's CURRENT values of the named fields (Discovered, IndexClaimed,
-- Tutorial, BestTimes, Home, Tiers, Hybrids, PetLevels, Teams, Battle, PetGrowth, Ring, Migrations; fields =
-- { Discovered = true, ... }) replace the stored ones at the next successful save instead of being merged (those
-- merges only ever grow, or a higher stored prestige would win the Home back, or the battle record's cleared trials /
-- event pets / best values would come back, or the Phase 4 evolution stages / training ranks / ring record would keep
-- their higher stored values, so a /reset or /tutorial would otherwise return with the next save). The caller changes the
-- live values itself; everything after this call merges on top of them as usual. Pending until a save succeeds
-- (orphan retries and BindToClose carry it). Returns true when recorded (false until the profile is loaded, while it
-- is provisional, or without a known field).
function DataService.ResetFields(player, fields)
	if not player or type(fields) ~= "table" then
		return false
	end
	local entry = cache[player.UserId]
	if not entry or not entry.Loaded or isProvisional(entry) then
		return false
	end
	local pending = {}
	for key in pairs(entry.Overwrite or {}) do
		pending[key] = true
	end
	local any = false
	for key, on in pairs(fields) do
		if on == true and OVERWRITABLE[key] then
			pending[key] = true
			any = true
		end
	end
	if not any then
		return false
	end
	entry.Overwrite = pending
	entry.OverwriteGen = (entry.OverwriteGen or 0) + 1
	entry.Dirty = true
	return true
end

----------------------------------------------------------------------
-- Tokens
----------------------------------------------------------------------

-- Adds earned tokens (n > 0; spending goes through SpendTokens). Also counts Stats.TokensEarned.
function DataService.AddTokens(player, n)
	if not player or not isFinite(n) then
		return
	end
	local amount = math.floor(n + 0.5)
	if amount <= 0 then
		return
	end
	local entry = cache[player.UserId]
	if not entry then
		if not player.Parent then
			return -- a player who already left (and was released) must not recreate a cache entry
		end
		hook()
		entry = ensureEntry(player.UserId)
	end
	local profile = entry.Profile
	profile.Tokens = sanitize(profile.Tokens + amount)
	profile.Stats.TokensEarned = sanitize(profile.Stats.TokensEarned + amount)
	entry.Dirty = true
	pushToPlayer(player, profile.Tokens)
end

-- true if the tokens were taken. Never goes negative.
function DataService.SpendTokens(player, n)
	if not player or not isFinite(n) or n < 0 then
		return false
	end
	local amount = math.ceil(n)
	local entry = cache[player.UserId]
	if not entry then
		return amount == 0
	end
	local profile = entry.Profile
	if amount > profile.Tokens then
		return false
	end
	if amount == 0 then
		return true
	end
	profile.Tokens = profile.Tokens - amount
	entry.Dirty = true
	pushToPlayer(player, profile.Tokens)
	return true
end

function DataService.GetTokens(player)
	if not player then
		return 0
	end
	local entry = cache[player.UserId]
	if entry then
		return entry.Profile.Tokens
	end
	local attr = player:GetAttribute(Config.Attr.Tokens)
	if type(attr) == "number" then
		return attr
	end
	return 0
end

----------------------------------------------------------------------
-- Phase 2: Cash + Gems (delta-saved like Tokens; mirrored on the player attributes)
----------------------------------------------------------------------

-- The cache entry for a currency change (created like AddTokens does when the load has not finished yet).
local function currencyEntry(player)
	local entry = cache[player.UserId]
	if not entry then
		if not player.Parent then
			return nil
		end
		hook()
		entry = ensureEntry(player.UserId)
	end
	return entry
end

-- Adds cash (n > 0; fractions are kept in the live balance, the store and the HUD see whole units).
function DataService.AddCash(player, n)
	if not player or not isFinite(n) or n <= 0 then
		return false
	end
	local entry = currencyEntry(player)
	if not entry then
		return false
	end
	local profile = entry.Profile
	profile.Cash = clampCash((isFinite(profile.Cash) and profile.Cash or 0) + n)
	entry.Dirty = true
	pushCurrencies(player, profile)
	return true
end

-- true if the cash was taken (whole units, n rounded up). Never goes negative; check and write do not yield.
function DataService.SpendCash(player, n)
	if not player or not isFinite(n) or n < 0 then
		return false
	end
	local amount = math.ceil(n)
	local entry = cache[player.UserId]
	if not entry then
		return amount == 0
	end
	local profile = entry.Profile
	local balance = clampCash(profile.Cash)
	if amount > balance then
		return false
	end
	if amount == 0 then
		return true
	end
	profile.Cash = balance - amount
	entry.Dirty = true
	pushCurrencies(player, profile)
	return true
end

function DataService.GetCash(player)
	if not player then
		return 0
	end
	local entry = cache[player.UserId]
	if entry then
		return sanitizeCash(entry.Profile.Cash)
	end
	local attr = Config.Attr.Cash and player:GetAttribute(Config.Attr.Cash)
	if type(attr) == "number" then
		return attr
	end
	return 0
end

-- Adds gems (whole numbers; n rounded to the nearest whole, must be >= 1).
function DataService.AddGems(player, n)
	if not player or not isFinite(n) then
		return false
	end
	local amount = math.floor(n + 0.5)
	if amount <= 0 then
		return false
	end
	local entry = currencyEntry(player)
	if not entry then
		return false
	end
	local profile = entry.Profile
	profile.Gems = sanitize(sanitize(profile.Gems) + amount)
	entry.Dirty = true
	pushCurrencies(player, profile)
	return true
end

-- true if the gems were taken (n rounded up). Never goes negative.
function DataService.SpendGems(player, n)
	if not player or not isFinite(n) or n < 0 then
		return false
	end
	local amount = math.ceil(n)
	local entry = cache[player.UserId]
	if not entry then
		return amount == 0
	end
	local profile = entry.Profile
	local balance = sanitize(profile.Gems)
	if amount > balance then
		return false
	end
	if amount == 0 then
		return true
	end
	profile.Gems = balance - amount
	entry.Dirty = true
	pushCurrencies(player, profile)
	return true
end

function DataService.GetGems(player)
	if not player then
		return 0
	end
	local entry = cache[player.UserId]
	if entry then
		return sanitize(entry.Profile.Gems)
	end
	local attr = Config.Attr.Gems and player:GetAttribute(Config.Attr.Gems)
	if type(attr) == "number" then
		return attr
	end
	return 0
end

----------------------------------------------------------------------
-- Phase 2: Food (delta-saved counts)
----------------------------------------------------------------------

local function wholeAmount(n)
	if n == nil then
		return 1
	end
	if not isFinite(n) then
		return nil
	end
	local amount = math.floor(n + 0.5)
	if amount < 1 then
		return nil
	end
	return amount
end

-- Adds n (default 1) of a food. false for junk ids / amounts or before the profile loaded. Capped per type.
function DataService.AddFood(player, foodId, n)
	local amount = wholeAmount(n)
	if not player or not validKey(foodId) or not amount then
		return false
	end
	local entry = cache[player.UserId]
	if not entry or not entry.Loaded then
		return false
	end
	local food = ensureTable(entry.Profile, "Food")
	local have = isFinite(food[foodId]) and sanitize(food[foodId]) or 0
	food[foodId] = math.min(have + amount, MAX_FOOD)
	entry.Dirty = true
	DataService.SyncSoon(player)
	return true
end

-- Takes n (default 1) of a food: false (nothing taken) when fewer are owned.
function DataService.SpendFood(player, foodId, n)
	local amount = wholeAmount(n)
	if not player or not validKey(foodId) or not amount then
		return false
	end
	local entry = cache[player.UserId]
	if not entry or not entry.Loaded then
		return false
	end
	local food = ensureTable(entry.Profile, "Food")
	local have = isFinite(food[foodId]) and sanitize(food[foodId]) or 0
	if have < amount then
		return false
	end
	if have - amount > 0 then
		food[foodId] = have - amount
	else
		food[foodId] = nil
	end
	entry.Dirty = true
	DataService.SyncSoon(player)
	return true
end

-- Count of one food, or (foodId nil) a copy of the whole { [foodId] = count } map.
function DataService.GetFood(player, foodId)
	local entry = player and cache[player.UserId]
	local food = entry and tableOr(entry.Profile.Food) or {}
	if foodId == nil then
		return cleanCounts(food, MAX_FOOD)
	end
	if not validKey(foodId) then
		return 0
	end
	return isFinite(food[foodId]) and sanitize(food[foodId]) or 0
end

----------------------------------------------------------------------
-- Phase 2: pet levels (per key, replaced per key on save)
----------------------------------------------------------------------

-- XP needed to go from `level` to level + 1 (TycoonCatalog.XpToNext; a local curve without it).
local function xpToNext(level)
	local catalog = getTycoonCatalog()
	if catalog and type(catalog.XpToNext) == "function" then
		local ok, need = pcall(catalog.XpToNext, level)
		if ok and need == math.huge then
			return need -- the top of the curve: no further level
		end
		if ok and isFinite(need) and need > 0 then
			return need
		end
	end
	return math.floor(40 * level ^ 1.35 + 0.5)
end

local function maxPetLevel()
	local catalog = getTycoonCatalog()
	if catalog then
		local fromXp = type(catalog.PetXp) == "table" and catalog.PetXp.MaxLevel or nil
		for _, v in ipairs({ catalog.MaxPetLevel or false, catalog.PetMaxLevel or false, fromXp or false }) do
			if isFinite(v) and v >= 1 then
				return math.min(math.floor(v), MAX_LEVEL)
			end
		end
	end
	return DEFAULT_MAX_PET_LEVEL
end

-- level, xp of a pet key (1, 0 when it never gained XP or the profile is not loaded).
function DataService.GetPetLevel(player, key)
	local entry = player and cache[player.UserId]
	if not entry or not validKey(key) then
		return 1, 0
	end
	local clean = cleanPetLevel(tableOr(entry.Profile.PetLevels)[key])
	if not clean then
		return 1, 0
	end
	return clean.Level, clean.Xp
end

-- Adds XP to an OWNED pet copy and levels it up along the XP curve (capped at the max level, where XP stops).
-- Returns how many levels it gained (0 when refused: junk, not owned, not loaded, provisional profile).
function DataService.AddPetXp(player, key, xp)
	if not player or not validKey(key) or not isFinite(xp) or xp <= 0 then
		return 0
	end
	local entry = cache[player.UserId]
	if not entry or not entry.Loaded or isProvisional(entry) then
		return 0
	end
	local profile = entry.Profile
	if ownedCount(profile, key) <= 0 then
		return 0
	end
	local levels = ensureTable(profile, "PetLevels")
	local raw = levels[key]
	local level, have = 1, 0
	if type(raw) == "table" then
		if isFinite(raw.Level) and raw.Level >= 1 then
			level = math.min(math.floor(raw.Level), MAX_LEVEL)
		end
		if isFinite(raw.Xp) and raw.Xp > 0 then
			have = raw.Xp
		end
	elseif isFinite(raw) and raw >= 1 then
		level = math.min(math.floor(raw), MAX_LEVEL)
	end
	local cap = maxPetLevel()
	local total = have + xp
	local gained = 0
	while level < cap do
		local need = xpToNext(level)
		if total < need then
			break
		end
		total = total - need
		level = level + 1
		gained = gained + 1
	end
	if level >= cap then
		total = 0 -- at the top of the curve XP stops counting
	end
	levels[key] = { Level = level, Xp = math.min(total, MAX_COUNT) }
	entry.Dirty = true
	DataService.SyncSoon(player)
	return gained
end

----------------------------------------------------------------------
-- Phase 2: Home (Stations / Garden / Gym per key, CollectorCash as a delta, a higher prestige wins the whole Home)
----------------------------------------------------------------------

-- The live Home table, repaired in place when another module dropped one of its parts. Rooms stays Stations.
local function liveHome(profile)
	local home = profile.Home
	if type(home) ~= "table" then
		home = newHome()
		profile.Home = home
	end
	if type(home.Stations) ~= "table" then
		home.Stations = type(home.Rooms) == "table" and home.Rooms or {}
	end
	home.Rooms = home.Stations
	ensureTable(home, "Garden")
	ensureTable(home, "Gym")
	return home
end

-- After MutateHome: sanitises the live home IN PLACE (keeps the fraction of CollectorCash).
local function repairHome(home)
	local collector = clampCash(home.CollectorCash)
	writeHome(home, cleanHome(home, false))
	home.CollectorCash = collector
end

-- A deep copy of the Home ({ Level, Prestige, Stations, Garden, Gym, CollectorCash, LastSeen }; Garden / Gym keyed
-- by slot number), or nil until the profile is loaded and while it is provisional (its Home would be defaults).
function DataService.GetHome(player)
	local entry = player and cache[player.UserId]
	if not entry or not entry.Loaded or isProvisional(entry) then
		return nil
	end
	local home = liveHome(entry.Profile)
	local copy = cleanHome(home, false)
	copy.CollectorCash = clampCash(home.CollectorCash)
	return copy
end

-- fn(home) edits the live Home table (no yields). An error, or fn returning false, restores the Home and answers
-- false. While the profile is provisional only CollectorCash / LastSeen may change (they merge as a delta / the
-- later time; stations from stand-in defaults would overwrite the real ones): anything else is rolled back.
function DataService.MutateHome(player, fn)
	if not player or type(fn) ~= "function" then
		return false
	end
	local entry = cache[player.UserId]
	if not entry or not entry.Loaded then
		return false
	end
	local home = liveHome(entry.Profile)
	local before = cleanHome(home, false)
	local beforeCollector = home.CollectorCash
	local ok, result = pcall(fn, home)
	local function restore()
		writeHome(home, before)
		home.CollectorCash = clampCash(beforeCollector)
	end
	if not ok then
		warn("[DataService] MutateHome callback errored (home restored): " .. tostring(result))
		restore()
		return false
	end
	if result == false then
		restore()
		return false
	end
	repairHome(home)
	local after = cleanHome(home, false)
	-- Phase 4: a prestige ends the veteran extras of the one-time migration (the old garden places and the old prices
	-- last "until your next Prestige"; the merge agrees: a higher Prestige wins the whole Home, which has them cleared)
	-- Phase 5: the folded Coin Magnet ends with it too (LegacyMagnet / LegacyMagnetStar); DecorCredit is NEVER cleared
	if after.Prestige > before.Prestige and (after.LegacySlots ~= nil or after.LegacyPrices ~= nil or after.LegacyMagnet ~= nil) then
		home.LegacySlots = nil
		home.LegacyPrices = nil
		home.LegacyMagnet = nil
		home.LegacyMagnetStar = nil
		after = cleanHome(home, false)
	end
	local visible = not homeVisiblyEqual(before, after)
	if visible and isProvisional(entry) then
		restore()
		return false
	end
	entry.Dirty = true
	-- Phase 3: a pet whose last free copy went to the Garden / Gym leaves the battle teams (bug batch 2 #18: the Garden
	-- counts again; the caller unequips the copy, see TycoonService.GardenSet)
	local pruned = visible and P3.pruneLive(entry)
	if visible then
		DataService.SyncSoon(player)
	end
	if pruned then
		DataService.TeamsChanged:Fire(player)
	end
	return true
end

----------------------------------------------------------------------
-- Phase 2: developer-product receipts (GemService: idempotent ProcessReceipt)
----------------------------------------------------------------------

-- true when that purchase id was already processed for the player; nil when that cannot be known yet (profile not
-- loaded, or provisional).
function DataService.HasReceipt(player, purchaseId)
	local entry = player and cache[player.UserId]
	if not entry or not entry.Loaded or isProvisional(entry) or not validKey(purchaseId) then
		return nil
	end
	return tableOr(entry.Profile.GemReceipts)[purchaseId] ~= nil
end

-- Records a processed purchase id. true = new (grant it now, in the same step), false = already processed (grant
-- nothing, the purchase is done), nil = cannot decide now (not loaded / provisional: answer NotProcessedYet).
-- The receipt and the granted gems travel in the same save (one UpdateAsync). `gems` (optional) = what the caller
-- grants for it: the merge then makes the grant follow its receipt atomically. When the stored profile already holds
-- that receipt (another server granted the same purchase while this server's save failed and the player moved on),
-- this session's grant is not added to the store a second time.
function DataService.MarkReceipt(player, purchaseId, gems)
	local entry = player and cache[player.UserId]
	if not entry or not entry.Loaded or isProvisional(entry) or not validKey(purchaseId) then
		return nil
	end
	local receipts = ensureTable(entry.Profile, "GemReceipts")
	if receipts[purchaseId] ~= nil then
		return false
	end
	receipts[purchaseId] = sanitizeTime(os.time())
	trimReceipts(receipts, { [purchaseId] = true })
	if isFinite(gems) and gems >= 1 then
		local amounts = entry.ReceiptGems
		if type(amounts) ~= "table" then
			amounts = {}
			entry.ReceiptGems = amounts
		end
		amounts[purchaseId] = math.floor(gems + 0.5) -- AddGems rounds the same way
	end
	entry.Dirty = true
	return true
end

----------------------------------------------------------------------
-- Phase 3: battle teams (presets merge per preset) + the battle record (counters as deltas, best values, sets that
-- only grow). Nothing here yields; every refusal answers a short reason for a side toast.
----------------------------------------------------------------------

-- The cache entry of a loaded, non-provisional profile (team edits and record reads need the real data), or nil.
function P3.realEntry(player)
	local entry = player and cache[player.UserId]
	if not entry or not entry.Loaded or isProvisional(entry) then
		return nil
	end
	return entry
end

function P3.validPreset(preset)
	return isFinite(preset) and preset >= 1 and preset <= P3.PRESETS and preset == math.floor(preset)
end

-- Checks a requested team against a profile. ok, keys (slot order, compacted) | reason. `freeKey` (optional, bug
-- batch 2 #18): count one copy of that key as free of the Garden (the recall check, before the Garden lets it go).
function P3.checkTeam(profile, keys, freeKey)
	if type(keys) ~= "table" then
		return false, "That team is not valid"
	end
	for index, key in pairs(keys) do
		if type(index) ~= "number" or index ~= math.floor(index) or index < 1 then
			return false, "That team is not valid"
		end
		if index > P3.MAX_SLOTS and key ~= nil and key ~= "" and key ~= false then
			return false, "Teams have 3 pets: a fighter and two helpers" -- Phase 5 (4.8): more than 3 keys
		end
	end
	local placed = P3.placedCopies(profile)
	if type(freeKey) == "string" and (placed[freeKey] or 0) > 0 then
		placed[freeKey] = placed[freeKey] - 1
	end
	local list, seen = {}, {}
	for i = 1, P3.MAX_SLOTS do
		local key = keys[i]
		if key ~= nil and key ~= "" and key ~= false then
			if not P3.teamKey(key) then
				return false, "That team is not valid"
			end
			if seen[key] then
				return false, "A pet can join a team only once"
			end
			seen[key] = true
			local owned = ownedCount(profile, key)
			if owned < 1 then
				return false, "You do not own that pet"
			end
			if owned - (placed[key] or 0) < 1 then
				-- bug batch 2 #18: a Garden pet is busy gardening (the client asks first and recalls it with ONE request,
				-- TycoonService.GardenRecall); a Gym copy stays the old reason
				local home = type(profile.Home) == "table" and profile.Home or {}
				local open = P3.gardenOpen(home)
				for slot, k in pairs(tableOr(home.Garden)) do
					if k == key and not P3.closedSlot(slot, open) then
						return false, "That pet is gardening! Take it out of the garden first"
					end
				end
				return false, "That pet is busy in your Garden or Gym"
			end
			list[#list + 1] = key
		end
	end
	return true, list
end

-- { Presets = { {key...} x3 }, Active, Slots = 3 | 4 } (a pruned copy), or nil until loaded / while provisional.
function DataService.GetTeams(player)
	local entry = P3.realEntry(player)
	if not entry then
		return nil
	end
	return P3.teamsSnapshot(entry.Profile)
end

-- Stores the pets of one preset (slot order; "" / false = an empty slot). ok, reason
function DataService.SetTeam(player, preset, keys)
	if not player or not P3.validPreset(preset) then
		return false, "Pick a team from 1 to " .. P3.PRESETS
	end
	local entry = P3.realEntry(player)
	if not entry then
		return false, "Your data is still loading"
	end
	local profile = entry.Profile
	local ok, result = P3.checkTeam(profile, keys)
	if not ok then
		return false, result
	end
	P3.pruneLive(entry) -- a clean live Teams table (the other presets drop their stale keys too)
	profile.Teams.Presets[preset] = result
	entry.Dirty = true
	DataService.SyncSoon(player)
	DataService.TeamsChanged:Fire(player)
	return true
end

-- Bug batch 2 #18 (the recall check): would SetTeam(player, preset, keys) pass once ONE copy of `freeKey` left the
-- Garden? Changes nothing. ok, reason
function DataService.CheckTeam(player, preset, keys, freeKey)
	if not player or not P3.validPreset(preset) then
		return false, "Pick a team from 1 to " .. P3.PRESETS
	end
	local entry = P3.realEntry(player)
	if not entry then
		return false, "Your data is still loading"
	end
	local ok, result = P3.checkTeam(entry.Profile, keys, freeKey)
	if not ok then
		return false, result
	end
	return true
end

-- Makes a preset the active one. ok, reason
function DataService.SelectTeam(player, preset)
	if not player or not P3.validPreset(preset) then
		return false, "Pick a team from 1 to " .. P3.PRESETS
	end
	local entry = P3.realEntry(player)
	if not entry then
		return false, "Your data is still loading"
	end
	P3.pruneLive(entry)
	entry.Profile.Teams.Active = preset
	entry.Dirty = true
	DataService.SyncSoon(player)
	DataService.TeamsChanged:Fire(player)
	return true
end

-- Every owned key that could join a team right now (a copy not busy in the Garden / Gym, and not in training: Phase
-- 4's read-time lock; bug batch 2 #18: a garden pet is busy): what the Team picker offers and what the tutorial's
-- "team" step counts. {} until loaded or while provisional.
function DataService.FieldableKeys(player)
	local entry = P3.realEntry(player)
	if not entry then
		return {}
	end
	local profile = entry.Profile
	local keys = getPetKeys()
	local owned = {}
	if keys and type(keys.List) == "function" then
		local ok, list = pcall(keys.List, profile)
		if ok and type(list) == "table" then
			owned = list
		end
	else
		for key in pairs(tableOr(profile.Pets)) do
			owned[#owned + 1] = key
		end
	end
	local placed = P3.placedCopies(profile)
	local training = P4.trainingSet(profile.PetGrowth)
	local out = {}
	for _, key in ipairs(owned) do
		if type(key) == "string" and P3.teamKey(key) and not training[key] and ownedCount(profile, key) - (placed[key] or 0) >= 1 then
			out[#out + 1] = key
		end
	end
	return out
end

-- Bug batch 2 #18: { [key] = copies working in the Garden (open places only) / Gym } of the live profile (a copy), {}
-- until loaded / while provisional (stand-in data must not unequip anything). PetService.Equip and its re-validation
-- read it.
function DataService.PlacedCopies(player)
	local entry = P3.realEntry(player)
	if not entry then
		return {}
	end
	return P3.placedCopies(entry.Profile)
end

-- Bug batch 2 #18: { [key] = true } of every owned key with NO copy free of the Garden / Gym (busy gardening: no
-- follow, no team, no fight; the ring fallback skips them). {} until loaded / while provisional.
function DataService.GardenBusyKeys(player)
	local entry = P3.realEntry(player)
	if not entry then
		return {}
	end
	local profile = entry.Profile
	local out = {}
	for key, n in pairs(P3.placedCopies(profile)) do
		local owned = ownedCount(profile, key)
		if owned >= 1 and owned - n < 1 then
			out[key] = true
		end
	end
	return out
end

-- Bug batch 2 #18 follow-up: the CLOSED garden places (above the open count: a Prestige closed them, the pet rests
-- there and earns nothing) whose copy now also follows the player or sits in a battle preset, ascending; {} when
-- none, until loaded / while provisional. Changes nothing: TycoonService empties them silently after an equip / team
-- change (its plot shows the pet leave the bed). Open places never show up here (the lock refuses that overlap).
function DataService.ClosedBedOverlap(player)
	local entry = P3.realEntry(player)
	if not entry then
		return {}
	end
	local plan = P3.soloPlan(entry.Profile)
	local out = {}
	for i, slot in ipairs(plan and plan.Closed or {}) do
		out[i] = slot
	end
	return out
end

-- The usable keys of the active preset in slot order (compacted: a training pet is skipped at read time, the preset
-- keeps it); {} when empty or unknown.
function DataService.ActiveTeamKeys(player)
	local entry = P3.realEntry(player)
	if not entry then
		return {}
	end
	local teams = P3.teamsOf(entry.Profile)
	local training = P4.trainingSet(entry.Profile.PetGrowth)
	local out = {}
	for _, key in ipairs(teams.Presets[teams.Active]) do
		if not training[key] then
			out[#out + 1] = key
		end
	end
	return out
end

-- A copy of the battle record (TrialCleared / EventPets as sets), or nil until loaded / while provisional.
function DataService.GetBattle(player)
	local entry = P3.realEntry(player)
	if not entry then
		return nil
	end
	return P3.cleanBattle(entry.Profile.Battle)
end

-- fn(battle) edits the live record (no yields). See the header for the rules. -> ok
function DataService.MutateBattle(player, fn)
	if not player or type(fn) ~= "function" then
		return false
	end
	local entry = cache[player.UserId]
	if not entry or not entry.Loaded then
		return false
	end
	local live = ensureTable(entry.Profile, "Battle")
	local before = P3.cleanBattle(live)
	local ok, result = pcall(fn, live)
	entry.Profile.Battle = live -- the record stays this table even if fn replaced the field
	if not ok then
		warn("[DataService] MutateBattle callback errored (record restored): " .. tostring(result))
		refill(live, before)
		return false
	end
	if result == false then
		refill(live, before)
		return false
	end
	local after = P3.cleanBattle(live)
	-- the sets only grow and the best values never go down (the store merges them that way)
	for level in pairs(before.TrialCleared) do
		after.TrialCleared[level] = true
	end
	for id in pairs(before.EventPets) do
		after.EventPets[id] = true
	end
	for _, field in ipairs(P3.BESTS) do
		if before[field] > after[field] then
			after[field] = before[field]
		end
	end
	local changes = P3.battleChanges(before, after)
	if isProvisional(entry) then
		for field in pairs(changes) do
			if not P3.PROVISIONAL_OK[field] then
				refill(live, before) -- stand-in data must not decide a first clear or an event pet
				return false
			end
		end
	end
	refill(live, after)
	if next(changes) ~= nil then
		entry.Dirty = true
		DataService.SyncSoon(player)
	end
	return true
end

-- Adds (or with n < 0 takes) trophies; the total never goes below 0. -> ok, total
function DataService.AddTrophies(player, n)
	if not player or not isFinite(n) then
		return false
	end
	local amount
	if n >= 0 then
		amount = math.floor(n + 0.5)
	else
		amount = -math.floor(-n + 0.5)
	end
	local entry = currencyEntry(player)
	if not entry then
		return false
	end
	local battle = ensureTable(entry.Profile, "Battle")
	local before = battle.Trophies
	battle.Trophies = sanitize(sanitize(before) + amount)
	if battle.Trophies ~= before then
		entry.Dirty = true
		DataService.SyncSoon(player)
	end
	return true, battle.Trophies
end

----------------------------------------------------------------------
-- Phase 4: pet growth (evolution stages + training ranks + the running job), the Champion Ring record, the migration
-- markers and the one-time Phase 4 migration (ARCHITECTURE_V3.md "Phase 4 build contract" 4.2 / 4.3). Nothing here
-- yields; every helper lives in P4 (the main chunk is close to Lua's 200-local limit).
----------------------------------------------------------------------

-- The live PetGrowth map of a profile (repaired in place when another module dropped it).
function P4.liveGrowth(profile)
	return ensureTable(profile, "PetGrowth")
end

-- The live Ring record of a profile (repaired in place).
function P4.liveRing(profile)
	local ring = profile.Ring
	if type(ring) ~= "table" then
		ring = { Best = 0, Runs = 0 }
		profile.Ring = ring
	end
	return ring
end

-- true when a clean growth entry has an Evo or a rank above 0
function P4.hasGains(e)
	if e.Evo > 0 then
		return true
	end
	for _, stat in ipairs(P4.STATS) do
		if e[stat] > 0 then
			return true
		end
	end
	return false
end

-- No Evo / rank may go down through MutateGrowth (the store merges them as the higher value, so a lower write would
-- come back anyway): per key the clean `after` keeps the higher of before / after; an entry fn removed while its key is
-- still owned keeps its numbers (its Job goes: to clear a job set Job = nil, never delete a trained pet's entry); an
-- entry of a key no longer owned (fused away, released) may vanish. Returns the re-cleaned map (a Job whose target is
-- no longer the stat's rank + 1 after the max is stale and goes).
function P4.keepGains(profile, before, after)
	for key, e in pairs(before) do
		local a = after[key]
		if a == nil then
			if P4.hasGains(e) and ownedCount(profile, key) > 0 then
				local kept = P4.zeroEntry()
				kept.Evo = e.Evo
				for _, stat in ipairs(P4.STATS) do
					kept[stat] = e[stat]
				end
				after[key] = kept
			end
		else
			a.Evo = math.max(a.Evo, e.Evo)
			for _, stat in ipairs(P4.STATS) do
				a[stat] = math.max(a[stat], e[stat])
			end
		end
	end
	return P4.cleanGrowth(after)
end

-- PetCatalog.MaxEvolution of a key (its def through PetKeys.DefOf when the catalog is there), else the data cap 2.
function P4.maxEvolution(profile, key)
	local catalog = getPetCatalog()
	if not catalog or type(catalog.MaxEvolution) ~= "function" then
		return P4.MAX_EVO
	end
	local subject = key
	local keys = getPetKeys()
	if keys and type(keys.DefOf) == "function" then
		local okDef, def = pcall(keys.DefOf, key, profile)
		if okDef and type(def) == "table" then
			subject = def
		end
	end
	local ok, top = pcall(catalog.MaxEvolution, subject)
	if ok and isFinite(top) and top >= 0 then
		return math.min(math.floor(top), P4.MAX_EVO)
	end
	return P4.MAX_EVO
end

-- A copy of one pet's growth { Evo, Speed, Physique, Ability, Defense, Job = {...} | nil }: zeros when the key has none
-- (also before the load and while provisional: display only).
function DataService.GetGrowth(player, key)
	local entry = player and cache[player.UserId]
	local clean = nil
	if entry and validKey(key) then
		clean = P4.cleanEntry(tableOr(entry.Profile.PetGrowth)[key])
	end
	return clean or P4.zeroEntry()
end

-- A clean copy of the whole growth map { [key] = entry }; {} until loaded and while provisional.
function DataService.GetGrowthMap(player)
	local entry = P3.realEntry(player)
	if not entry then
		return {}
	end
	return P4.cleanGrowth(entry.Profile.PetGrowth)
end

-- fn(growth) edits the LIVE PetGrowth map { [key] = { Evo, Speed, Physique, Ability, Defense, Job } } (no yields).
-- Refused until loaded and while provisional (-> false). An error, or fn returning false, restores the map (-> false).
-- Afterwards the map is cleaned in place (P4.cleanGrowth: junk and stale Jobs dropped, numbers clamped) and no Evo /
-- rank may go down (P4.keepGains); every entry is replaced by a clean copy, so re-read entries with GetGrowth after
-- the call. A changed map is synced (throttled). Decide a reward / refund inside fn and pay it only once this returned
-- true: the Job and the Cash then travel in the same save.
function DataService.MutateGrowth(player, fn)
	if not player or type(fn) ~= "function" then
		return false
	end
	local entry = P3.realEntry(player)
	if not entry then
		return false
	end
	local profile = entry.Profile
	local live = P4.liveGrowth(profile)
	local before = P4.cleanGrowth(live)
	local ok, result = pcall(fn, live)
	profile.PetGrowth = live -- the map stays this table even if fn replaced the field
	if not ok then
		warn("[DataService] MutateGrowth callback errored (growth restored): " .. tostring(result))
		refill(live, before)
		return false
	end
	if result == false then
		refill(live, before)
		return false
	end
	local after = P4.keepGains(profile, before, P4.cleanGrowth(live))
	local changed = not deepEqual(before, after)
	refill(live, after)
	if changed then
		entry.Dirty = true
		DataService.SyncSoon(player)
	end
	return true
end

-- { [key] = true } of every key with a running training Job: the ONE source of the training lock (PetService.Equip,
-- GardenSet, Fusion, teamOf, the ring start and this module's own filters read it). {} until loaded / while
-- provisional.
function DataService.TrainingKeys(player)
	local entry = P3.realEntry(player)
	if not entry then
		return {}
	end
	return P4.trainingSet(entry.Profile.PetGrowth)
end

-- The stored evolution stage of a key (0..2; 0 when absent). The boost counts only from this stored stage.
function DataService.GetEvolution(player, key)
	return DataService.GetGrowth(player, key).Evo
end

-- Raises the stored stage of an OWNED key to `stage` (1..2, at most PetCatalog.MaxEvolution of its def). Only up:
-- false for a stage not above the stored one, junk, a key not owned, a profile not loaded or provisional.
function DataService.SetEvolution(player, key, stage)
	if not player or not validKey(key) or not isFinite(stage) or stage ~= math.floor(stage) or stage < 1 or stage > P4.MAX_EVO then
		return false
	end
	local entry = P3.realEntry(player)
	if not entry then
		return false
	end
	local profile = entry.Profile
	if ownedCount(profile, key) < 1 or stage > P4.maxEvolution(profile, key) then
		return false
	end
	if stage <= DataService.GetGrowth(player, key).Evo then
		return false
	end
	return DataService.MutateGrowth(player, function(growth)
		local e = growth[key]
		if type(e) ~= "table" then
			e = {}
			growth[key] = e
		end
		e.Evo = stage
	end)
end

-- A copy of the Champion Ring record { Best, Runs }, or nil until loaded and while provisional (a stand-in record must
-- never decide a new record or a first boss clear).
function DataService.GetRing(player)
	local entry = P3.realEntry(player)
	if not entry then
		return nil
	end
	return P4.cleanRing(entry.Profile.Ring)
end

-- fn(ring) edits the live record { Best, Runs } (no yields). Refused until loaded and while provisional. An error, or
-- fn returning false, restores it (-> false). Afterwards: whole numbers >= 0, Best never goes down (the store merges it
-- as the higher value), Runs is replaced (it travels as a +/- delta). Decide "new record" / "first boss clear" inside
-- fn and pay only once this returned true. A change is synced (throttled).
function DataService.MutateRing(player, fn)
	if not player or type(fn) ~= "function" then
		return false
	end
	local entry = P3.realEntry(player)
	if not entry then
		return false
	end
	local profile = entry.Profile
	local live = P4.liveRing(profile)
	local before = P4.cleanRing(live)
	local ok, result = pcall(fn, live)
	profile.Ring = live -- the record stays this table even if fn replaced the field
	if not ok then
		warn("[DataService] MutateRing callback errored (record restored): " .. tostring(result))
		refill(live, before)
		return false
	end
	if result == false then
		refill(live, before)
		return false
	end
	local after = P4.cleanRing(live)
	if after.Best < before.Best then
		after.Best = before.Best
	end
	local changed = after.Best ~= before.Best or after.Runs ~= before.Runs
	refill(live, after)
	if changed then
		entry.Dirty = true
		DataService.SyncSoon(player)
	end
	return true
end

-- true / false once the profile is loaded and not provisional (nil before: not decidable).
function DataService.IsMigrated(player, name)
	local entry = P3.realEntry(player)
	if not entry or not validKey(name) then
		return nil
	end
	return tableOr(entry.Profile.Migrations)[name] == true
end

-- Records Migrations[name] = true (a union in the merge, so it is allowed while provisional). true when it is set now.
function DataService.MarkMigrated(player, name)
	if not player or not validKey(name) then
		return false
	end
	local entry = cache[player.UserId]
	if not entry or not entry.Loaded then
		return false
	end
	local migrations = ensureTable(entry.Profile, "Migrations")
	if migrations[name] ~= true then
		migrations[name] = true
		entry.Dirty = true
	end
	return true
end

-- The info of a migration THIS session ran on the profile (remembered until the player is released), or nil. For
-- "P4": { Veteran, LegacySlots, LegacyPrices, GymKeys, GymPets, CollectorCash } (see the header). TycoonService shows
-- the one welcome toast on the first claim when MigratedNow(player, "P4") answers a Veteran.
function DataService.MigratedNow(player, name)
	local entry = player and cache[player.UserId]
	if not entry or type(entry.MigratedNow) ~= "table" or not validKey(name) then
		return nil
	end
	local info = entry.MigratedNow[name]
	if type(info) ~= "table" then
		return nil
	end
	return deepCopy(info)
end

-- Developer tools (/petlevel): writes { Level, Xp = 0 } for an OWNED key, level a whole number 1..the curve's max level
-- (TycoonCatalog.PetXp.MaxLevel, 100). Refused until loaded and while provisional. Synced (throttled).
function DataService.SetPetLevel(player, key, level)
	if not player or not validKey(key) or not isFinite(level) or level ~= math.floor(level) then
		return false
	end
	local entry = P3.realEntry(player)
	if not entry then
		return false
	end
	local profile = entry.Profile
	if level < 1 or level > maxPetLevel() or ownedCount(profile, key) < 1 then
		return false
	end
	ensureTable(profile, "PetLevels")[key] = { Level = level, Xp = 0 }
	entry.Dirty = true
	DataService.SyncSoon(player)
	return true
end

-- Garden places a home has by right (TycoonCatalog.Prestige.GardenSlotsBase / GardenSlotsPerStar; 3 + 1 per star
-- without them), so the migration can see which veterans had more.
function P4.gardenPlaces(stars)
	local base, perStar = P4.GARDEN_SLOTS_BASE, P4.GARDEN_SLOTS_PER_STAR
	local catalog = getTycoonCatalog()
	local prestige = catalog and type(catalog.Prestige) == "table" and catalog.Prestige or nil
	if prestige then
		if isFinite(prestige.GardenSlotsBase) and prestige.GardenSlotsBase >= 0 then
			base = math.floor(prestige.GardenSlotsBase)
		end
		if isFinite(prestige.GardenSlotsPerStar) and prestige.GardenSlotsPerStar >= 0 then
			perStar = math.floor(prestige.GardenSlotsPerStar)
		end
	end
	return base + perStar * sanitize(stars)
end

-- The one-time Phase 4 migration of a LIVE profile (section 4.3), in one non-yielding step; returns its info:
--   1. extra garden places: a Phase 3 Garden's level was its slot count; above 3 + Prestige it becomes LegacySlots
--      ("You keep your extra garden places until your next Prestige")
--   2. old prices: a veteran who had prestiged keeps the base prices until the next Prestige (LegacyPrices)
--   3. the old Gym is emptied (those pets are free again; their Gym XP is already in PetLevels)
--   4. Migrations.P4 = true
-- No one-time Cash payout anywhere (a payout plus a marker can double-pay across two servers); everything else needs
-- no data change (the station ids, Home Level, Prestige, CollectorCash, Food and PetLevels keep their meaning).
function P4.migrateP4(profile)
	local home = liveHome(profile)
	local clean = cleanHome(home, false)
	local info = {
		Veteran = clean.Level > 0 or clean.Prestige > 0 or next(clean.Stations) ~= nil,
		LegacySlots = nil,
		LegacyPrices = false,
		GymKeys = {},
		GymPets = 0,
		CollectorCash = clean.CollectorCash,
	}
	local oldSlots = clean.Stations.Garden or 0
	if oldSlots > P4.gardenPlaces(clean.Prestige) then
		home.LegacySlots = math.min(oldSlots, MAX_SLOT)
		info.LegacySlots = home.LegacySlots
	end
	if clean.Prestige > 0 then
		home.LegacyPrices = true
		info.LegacyPrices = true
	end
	local gym = ensureTable(home, "Gym")
	local slots = {}
	for slot in pairs(gym) do
		slots[#slots + 1] = slot
	end
	table.sort(slots, function(a, b)
		if type(a) == type(b) then
			return a < b
		end
		return type(a) == "number" -- numbered mats first, named slots after
	end)
	for _, slot in ipairs(slots) do
		local key = gym[slot]
		if validKey(key) then
			info.GymKeys[#info.GymKeys + 1] = key
		end
		gym[slot] = nil
	end
	info.GymPets = #info.GymKeys
	repairHome(home) -- whole numbers, the CollectorCash fraction kept
	local migrations = ensureTable(profile, "Migrations")
	migrations[P4.MIGRATION] = true
	if info.Veteran then
		-- persisted (a union like every marker): TycoonService shows the one welcome toast on the FIRST claim, which may
		-- happen in a later session than the migration; it marks P4.WELCOME_MARK itself once the toast was shown
		migrations[P4.VETERAN_MARK] = true
	end
	return info
end

-- Runs the Phase 4 migration on a cache entry when it is due: loaded, not provisional (stand-in defaults must never
-- be migrated: the real save is migrated after the recovery, on ProfileRebased) and not marked yet (idempotent: a
-- profile another server already migrated is left alone; the marker merges as a union). Returns the info, or nil.
function P4.migrateEntry(entry, player)
	if not entry or not entry.Loaded or isProvisional(entry) then
		return nil
	end
	local profile = entry.Profile
	if tableOr(profile.Migrations)[P4.MIGRATION] == true then
		return nil
	end
	local ok, info = pcall(P4.migrateP4, profile)
	if not ok then
		warn("[DataService] Phase 4 migration failed (it runs again on the next load): " .. tostring(info))
		return nil
	end
	entry.Dirty = true
	if type(entry.MigratedNow) ~= "table" then
		entry.MigratedNow = {}
	end
	entry.MigratedNow[P4.MIGRATION] = info
	return info
end

-- (The marker below is a record only, never consulted: the read-time repair itself runs on every load, see the header.)
-- Bug batch 2 #18 on a loaded, real profile: sets the marker Migrations.B2GardenSolo the first time and takes the keys
-- this read moved out of the Garden (entry.GardenMoved, P3.gardenSolo in normalizeProfile) -> info { Keys = {key...} }
-- (also MigratedNow(player, "B2GardenSolo")), or nil when nothing moved. A provisional profile waits for its recovery.
function P3.gardenMigrate(entry)
	if not entry or not entry.Loaded or isProvisional(entry) then
		return nil
	end
	local migrations = ensureTable(entry.Profile, "Migrations")
	if migrations[P5.GARDEN_MARK] ~= true then
		migrations[P5.GARDEN_MARK] = true
		entry.Dirty = true
	end
	local moved = entry.GardenMoved
	entry.GardenMoved = nil
	if type(moved) ~= "table" or #moved == 0 then
		return nil
	end
	entry.Dirty = true -- the store still holds the overlap until the next save (every read repairs it the same way)
	local info = { Keys = copyList(moved) }
	if type(entry.MigratedNow) ~= "table" then
		entry.MigratedNow = {}
	end
	entry.MigratedNow[P5.GARDEN_MARK] = info
	return info
end

-- Fires Migrated(player, "B2GardenSolo", { Keys }) right after the ProfileLoaded / ProfileRebased whose read moved pets
-- out of the Garden (TycoonService shows the one explaining toast).
function P3.gardenAnnounce(player, info)
	if type(info) == "table" and player then
		DataService.Migrated:Fire(player, P5.GARDEN_MARK, deepCopy(info))
	end
end

-- Fires Migrated(player, "P4", info) right after the ProfileLoaded / ProfileRebased that ran the migration.
function P4.announceMigration(player, info)
	if type(info) == "table" and player then
		DataService.Migrated:Fire(player, P4.MIGRATION, deepCopy(info))
	end
end

----------------------------------------------------------------------
-- Phase 5: the Dungeon record, Berries, Settings (ARCHITECTURE_V3.md "Phase 5 build contract" 9.1) and the one-time
-- P5 migrations (9.2). API in the same shape as the Ring / Food / Migrations API above.
----------------------------------------------------------------------

-- The live Dungeon table of a profile (created when missing; Cleared is a table).
function P5.liveDungeon(profile)
	local d = ensureTable(profile, "Dungeon")
	ensureTable(d, "Cleared")
	return d
end

-- { Best, Cleared = { [floor] = true }, Runs, Clears } (a clean copy), or nil until loaded / while provisional.
function DataService.GetDungeon(player)
	local entry = P3.realEntry(player)
	if not entry then
		return nil
	end
	return P5.cleanDungeon(entry.Profile.Dungeon)
end

-- fn(dungeon) edits the live record { Best, Cleared = { [floor] = true }, Runs, Clears } (no yields). Returns ok, first:
-- `first` = this call set a new Cleared[floor] (pay the first clear ONLY when ok and first are both true). An error, or
-- fn returning false, restores the record (-> false). Afterwards: whole numbers, Best never goes down and is >= the
-- highest cleared floor, Cleared only grows (both merge that way in the store), Runs / Clears travel as +/- deltas. While
-- the profile is provisional only Runs may change: a first clear / a higher Best is refused with "Your save is still
-- loading" (nothing changes). A change is synced (throttled).
function DataService.MutateDungeon(player, fn)
	if not player or type(fn) ~= "function" then
		return false, "That is not valid"
	end
	local entry = cache[player.UserId]
	if not entry or not entry.Loaded then
		return false, "Your save is still loading"
	end
	local profile = entry.Profile
	local live = P5.liveDungeon(profile)
	local before = P5.cleanDungeon(live)
	refill(live, before) -- fn sees the clean shape (Cleared as a set)
	local ok, result = pcall(fn, live)
	profile.Dungeon = live -- the record stays this table even if fn replaced the field
	if not ok then
		warn("[DataService] MutateDungeon callback errored (record restored): " .. tostring(result))
		refill(live, before)
		return false, "That is not valid"
	end
	if result == false then
		refill(live, before)
		return false, "That is not valid"
	end
	local after = P5.cleanDungeon(live)
	if after.Best < before.Best then
		after.Best = before.Best
	end
	local first = false
	for floor in pairs(before.Cleared) do
		after.Cleared[floor] = true
	end
	for floor in pairs(after.Cleared) do
		if not before.Cleared[floor] then
			first = true
		end
		if floor > after.Best then
			after.Best = floor
		end
	end
	local progress = first or after.Best ~= before.Best or after.Clears ~= before.Clears
	if progress and isProvisional(entry) then
		refill(live, before)
		return false, "Your save is still loading"
	end
	refill(live, after)
	if progress or after.Runs ~= before.Runs then
		entry.Dirty = true
		DataService.SyncSoon(player)
	end
	return true, first
end

-- Whole berries (0 before the profile loaded).
function DataService.GetBerries(player)
	local entry = player and cache[player.UserId]
	if not entry then
		return 0
	end
	return P5.cleanBerries(entry.Profile.Berries)
end

-- Adds n whole berries (n >= 1 after flooring; the caller keeps its own fractions). Allowed while provisional (a +
-- delta merges safely). The Berries attribute follows (<= 2 writes/s); no ProfileSync (C14). false for junk / early.
function DataService.AddBerries(player, n)
	if not player or not isFinite(n) then
		return false
	end
	local amount = math.floor(n)
	if amount < 1 then
		return false
	end
	local entry = cache[player.UserId]
	if not entry or not entry.Loaded then
		return false
	end
	local profile = entry.Profile
	profile.Berries = P5.cleanBerries(P5.cleanBerries(profile.Berries) + amount)
	entry.Dirty = true
	P5.pushBerries(player, false)
	return true
end

-- Takes n whole berries in ONE step (check, then subtract; no yield in between). false (nothing taken) when fewer are
-- owned, for junk amounts, before the load and while provisional (Y9: never from the client, never a double spend).
function DataService.SpendBerries(player, n)
	if not player or not isFinite(n) then
		return false
	end
	local amount = math.floor(n)
	if amount < 1 then
		return false
	end
	local entry = P3.realEntry(player)
	if not entry then
		return false
	end
	local profile = entry.Profile
	local have = P5.cleanBerries(profile.Berries)
	if have < amount then
		return false
	end
	profile.Berries = have - amount
	entry.Dirty = true
	P5.pushBerries(player, false)
	return true
end

-- { Music, Sfx, Gfx, Shake, SeenNotes, MouseLock } (a clean copy with per-key defaults; the defaults before the load).
function DataService.GetSettings(player)
	local entry = player and cache[player.UserId]
	if not entry then
		return P5.newSettings()
	end
	return P5.cleanSettings(entry.Profile.Settings)
end

-- Stores one setting: key one of P5.SETTING_KEYS, value of its type and range (7.2; SeenNotes never goes down). Allowed
-- while provisional (the live session's settings win the merge). Not synced: the client applied it already. -> ok
function DataService.SetSetting(player, key, value)
	if not player or type(key) ~= "string" or P5.SETTING_DEFAULTS[key] == nil then
		return false
	end
	local clean = P5.settingValue(key, value)
	if clean == nil then
		return false
	end
	local entry = cache[player.UserId]
	if not entry or not entry.Loaded then
		return false
	end
	local settings = ensureTable(entry.Profile, "Settings")
	local current = P5.settingValue(key, settings[key])
	if current == nil then
		current = P5.SETTING_DEFAULTS[key]
	end
	if key == "SeenNotes" and clean < current then
		return false
	end
	if settings[key] ~= clean then
		settings[key] = clean
		entry.Dirty = true
	end
	if key == "MouseLock" then
		-- an explicit choice: the one-time "lock ON" step never overrides it (also a choice made while provisional,
		-- before the step ran on the recovered profile; Migrations is a union, so the marker survives the merge)
		local migrations = ensureTable(entry.Profile, "Migrations")
		if migrations[P5.MOUSELOCK_MARK] ~= true then
			migrations[P5.MOUSELOCK_MARK] = true
			entry.Dirty = true
		end
	end
	return true
end

-- true when a stored record holds a preset with more than 3 keys (a Phase 4 save: the 4th slot), read leniently.
function P5.hadLongPreset(stored)
	local teams = type(stored) == "table" and stored.Teams or nil
	local presets = type(teams) == "table" and teams.Presets or nil
	if type(presets) ~= "table" then
		return false
	end
	for i = 1, P3.PRESETS do
		local list = presets[i]
		if list == nil then
			list = presets[tostring(i)]
		end
		if type(list) == "table" and (list[P3.MAX_SLOTS + 1] ~= nil or #list > P3.MAX_SLOTS) then
			return true
		end
	end
	return false
end

-- berries per old food id (TycoonCatalog.Berries.LegacyFood, else the local table)
function P5.legacyFood(catalog)
	local berries = catalog and type(catalog.Berries) == "table" and catalog.Berries or nil
	local legacy = berries and type(berries.LegacyFood) == "table" and berries.LegacyFood or nil
	return legacy or P5.LEGACY_FOOD
end

-- 9.2 step 2 (P5Dungeon) on a LIVE profile: Best = min(10, floor(TrialBest / 3)), Cleared[1..Best], Clears = Best
-- (only when the record held no clears yet), Runs untouched (0 for a Phase 4 save); the marker. Returns the info
-- { TrialBest, Best, Clears = the Clears this step wrote (the merge floor) }. No Cash, Gems or berries.
function P5.migrateDungeon(profile)
	local battle = P3.cleanBattle(profile.Battle)
	local best = math.min(P5.MIGRATE_MAX_FLOOR, math.floor(battle.TrialBest / P5.TRIALS_PER_FLOOR))
	local live = P5.liveDungeon(profile)
	local d = P5.cleanDungeon(live)
	local wrote = 0
	if best > d.Best then
		d.Best = best
	end
	for floor = 1, best do
		d.Cleared[floor] = true
	end
	if best > 0 and d.Clears == 0 then
		d.Clears = best
		wrote = best
	end
	refill(live, d)
	ensureTable(profile, "Migrations")[P5.DUNGEON_MARK] = true
	return { TrialBest = battle.TrialBest, Best = best, Clears = wrote }
end

-- 9.2 step 3 (P5Home): TycoonCatalog.FoldLegacy(home, firstTime) inside ONE MutateHome; on the first time the Food ->
-- berries step (Snack / Meal / Feast x LegacyFood, the basket cap ignored, Food zeroed) and MarkMigrated("P5Home") in
-- the same non-yielding step, ONLY when the fold ran (without TycoonCatalog.FoldLegacy the whole step is skipped and
-- retried on the next load, m14). After the marker the fold runs again only when it has something to fold (a key a
-- Phase 4 server sold during the rollout, 9.3). Returns the info, or nil when nothing ran.
function P5.migrateHome(entry, player)
	local catalog = getTycoonCatalog()
	local fold = catalog and type(catalog.FoldLegacy) == "function" and catalog.FoldLegacy or nil
	if not fold then
		return nil
	end
	local profile = entry.Profile
	local marked = tableOr(profile.Migrations)[P5.HOME_MARK] == true
	local firstTime = not marked
	-- a dry run on a clean copy: nothing to fold on a marked home -> no MutateHome, no dirty save
	local probe = cleanHome(liveHome(profile), false)
	local okProbe, changes = pcall(fold, probe, firstTime)
	if not okProbe then
		warn("[DataService] TycoonCatalog.FoldLegacy failed (the P5Home step runs again on the next load): " .. tostring(changes))
		return nil
	end
	if marked and changes ~= true then
		return nil
	end
	local before = cleanHome(liveHome(profile), false)
	local info = {
		FirstTime = firstTime,
		Folded = false,
		Veteran = before.Level > 0 or before.Prestige > 0 or next(before.Stations) ~= nil,
		Berries = 0,
		Food = {},
	}
	local ok = DataService.MutateHome(player, function(home)
		info.Folded = fold(home, firstTime) == true -- an error here restores the home: nothing is marked
		if marked and not info.Folded then
			return false
		end
		return true
	end)
	if not ok then
		return nil
	end
	if firstTime then
		local legacy = P5.legacyFood(catalog)
		local berries = 0
		for id, count in pairs(cleanCounts(profile.Food, MAX_FOOD)) do
			info.Food[id] = count
			local each = legacy[id]
			if isFinite(each) and each > 0 then
				berries = berries + count * math.floor(each)
			end
		end
		if berries > 0 then
			profile.Berries = P5.cleanBerries(P5.cleanBerries(profile.Berries) + berries)
			info.Berries = berries
			entry.BerriesMigrated = berries -- left out of the merge against a store another server already marked (m15 twin)
		end
		refill(ensureTable(profile, "Food"), {}) -- converted once; never written again (m16)
		ensureTable(profile, "Migrations")[P5.HOME_MARK] = true
		entry.Dirty = true
		P5.pushBerries(player, true)
	end
	return info
end

-- Bug batch 2 #21 (P5MouseLock) on a LIVE profile: Settings.MouseLock = true and the marker, once. A stored false from
-- before this step was the old default written along with another setting, not a choice (a false set through
-- SetSetting carries the marker already). Returns true when the setting changed.
function P5.migrateMouseLock(profile)
	local settings = ensureTable(profile, "Settings")
	local changed = settings.MouseLock ~= true
	settings.MouseLock = true
	ensureTable(profile, "Migrations")[P5.MOUSELOCK_MARK] = true
	return changed
end

-- Runs the Phase 5 migrations on a cache entry when they are due (loaded, not provisional; each one idempotent through
-- its marker, a profile another server migrated is left alone). Returns { Dungeon = info | nil, Home = info | nil } or nil.
function P5.migrateEntry(entry, player)
	if not entry or not entry.Loaded or isProvisional(entry) then
		return nil
	end
	local profile = entry.Profile
	local out = nil
	if tableOr(profile.Migrations)[P5.DUNGEON_MARK] ~= true then
		local ok, info = pcall(P5.migrateDungeon, profile)
		if ok then
			entry.Dirty = true
			if info.Clears > 0 then
				entry.DungeonMigrated = info.Clears -- merges as a max until the store holds it (m15)
			end
			out = { Dungeon = info }
		else
			warn("[DataService] Phase 5 dungeon migration failed (it runs again on the next load): " .. tostring(info))
		end
	end
	if tableOr(profile.Migrations)[P5.MOUSELOCK_MARK] ~= true then
		-- bug batch 2 #21: no toast, no Migrated signal (the client reads the setting from the Sync right after)
		local okLock, err = pcall(P5.migrateMouseLock, profile)
		if okLock then
			entry.Dirty = true
		else
			warn("[DataService] mouse lock migration failed (it runs again on the next load): " .. tostring(err))
		end
	end
	local okHome, home = pcall(P5.migrateHome, entry, player)
	if not okHome then
		warn("[DataService] Phase 5 home migration failed (it runs again on the next load): " .. tostring(home))
	elseif home then
		out = out or {}
		out.Home = home
	end
	if out then
		if type(entry.MigratedNow) ~= "table" then
			entry.MigratedNow = {}
		end
		if out.Dungeon then
			entry.MigratedNow[P5.DUNGEON_MARK] = out.Dungeon
		end
		if out.Home and out.Home.FirstTime then
			entry.MigratedNow[P5.HOME_MARK] = out.Home
		end
	end
	return out
end

-- Fires Migrated(player, "P5Dungeon" / "P5Home", info) right after the ProfileLoaded / ProfileRebased that ran them.
function P5.announceMigration(player, out)
	if type(out) ~= "table" or not player then
		return
	end
	if type(out.Dungeon) == "table" then
		DataService.Migrated:Fire(player, P5.DUNGEON_MARK, deepCopy(out.Dungeon))
	end
	if type(out.Home) == "table" then
		DataService.Migrated:Fire(player, P5.HOME_MARK, deepCopy(out.Home))
	end
end

----------------------------------------------------------------------
-- Stats
----------------------------------------------------------------------

-- Called by MatchService for every member at match end. `won` = finished on a victory.
function DataService.RecordMatch(player, difficultyId, won, seconds)
	local entry = player and cache[player.UserId]
	if not entry then
		return
	end
	local stats = entry.Profile.Stats
	stats.Matches = sanitize(stats.Matches + 1)
	if won == true then
		stats.Wins = sanitize(stats.Wins + 1)
		local clean = sanitizeSeconds(seconds)
		if clean and type(difficultyId) == "string" and Config.GetDifficulty(difficultyId) then
			local best = stats.BestTimes[difficultyId]
			if best == nil or clean < best then
				stats.BestTimes[difficultyId] = clean
			end
		end
	end
	entry.Dirty = true
end

----------------------------------------------------------------------
-- Autosave + shutdown
----------------------------------------------------------------------

function DataService.StartAutosave()
	hook()
	if autosaveStarted then
		return
	end
	autosaveStarted = true
	task.spawn(function()
		while not shuttingDown do
			local interval = Config.Tokens.AutosaveSeconds or 90
			local slept = 0
			-- Sleep in one-second slices so shutdown ends the loop promptly.
			while slept < interval and not shuttingDown do
				task.wait(1)
				slept = slept + 1
			end
			if shuttingDown then
				break
			end
			-- Walk the cache, not Players:GetPlayers(): entries of players who already left but could
			-- not be saved yet (orphans) must keep being flushed.
			local userIds = {}
			for userId in pairs(cache) do
				table.insert(userIds, userId)
			end
			for _, userId in ipairs(userIds) do
				if shuttingDown then
					break
				end
				local entry = cache[userId]
				if entry then
					safeSave(userId)
					if entry.Orphan then
						settleOrphan(userId, entry)
					end
					task.wait(0.25) -- spread requests out to stay inside the DataStore budget
				end
			end
		end
	end)
end

function DataService.BindToClose()
	hook()
	if closeBound then
		return
	end
	closeBound = true
	game:BindToClose(function()
		shuttingDown = true
		local userIds = {}
		for userId in pairs(cache) do
			table.insert(userIds, userId)
		end
		local pending = #userIds
		for _, userId in ipairs(userIds) do
			task.spawn(function()
				pcall(saveEntry, userId)
				pending = pending - 1
			end)
		end
		-- Roblox gives BindToClose ~30s; leave a margin.
		local waited = 0
		while pending > 0 and waited < 25 do
			task.wait(0.1)
			waited = waited + 0.1
		end
	end)
end

return DataService
