-- AttackFx (client): plays the pet attack effects that shared/AttackFxCatalog resolves (docs/superpowers/specs/
-- 2026-10-23-pet-attack-vfx-design.md "Architecture", "The 5 beats of every attack", "Rarity ladder", "Budgets,
-- quality, readability"; plan docs/superpowers/plans/2026-10-23-pet-attack-vfx.md Task 6). Client only: every
-- instance is local, nothing replicates. BattleController (Task 7) calls Play from its attack handlers and keeps its
-- cube Fx.* call as the fallback whenever Play returns false. Plain Lua 5.1-compatible syntax only.
-- 2026-11-01: docs/superpowers/specs/2026-11-01-attack-fx-design.md (areas drawn as they hit, clouds capped, tails, the kick).
--
-- API:
--   AttackFx.Play(ctx) -> bool     false = not played (the caller draws its cube Fx.* instead): unknown attack /
--       element / kind / shape, no source point, a texture key missing from TextureIds, the budget full, an error.
--       ctx = { Attack ("Melee" | "Ranged" | "Special" | "Element" | "Hurt" | "Ko" | "Victory" | "ShieldHit" (no pose)), Kind (Special),
--               Shape (Element: "Cone" | "Circle" | "Line"), Element, Rarity, Stage, PetId,
--               From = { Unit, Model, Pos }, To = { Unit, Model, Pos } or a list of them (allies / several targets),
--               Mine (own team: full density, camera punch, screen glow), Crit, Strong, Miss,
--               DueAt (clock time the impact must land: the charge is shortened to fit, impact never later, except
--               that a basic Ranged shot keeps its recipe's Beats.MinTravel of flight: player note 1),
--               Angle (Element attacks without a To: the WORLD yaw of the attack, direction (cos a, 0, sin a)),
--               Radius (Cone reach / Circle radius, default 9 / 8; Special Blast / Freeze / Storm, default 7 / 6 / 6),
--               Length (Line, default 24; Special Beam, default 26), Width (Line / Beam, default 4: eff.WidthScale = Width / 4)
--               (the numbers the server used: an evolved pet's areas are drawn as they hit),
--               Ground (world Y of the floor under From; default From.Y - 1.6), Now (the clock; default os.clock()),
--               (evolved forms, 2026-11-02:) Form (a Special's / an Element's stage: absent = the plain recipe), Twist (a form's delayed hit: AttackFxCatalog.Twists; no pose on the caster),
--               Line = { X0, Z0, Angle, Length, Width } (world: a Pounce's real charge line, the wolves run on it; none: from 8 studs behind the caster through the target),
--               Seconds (a Rally's / Haste's: how long from now its aura holds; a predicted charge's Seconds stay the wait), Scale (a Rally's bigger pet),
--               Center (world: where an Element Circle lands, a ranged pet's aim point; default the caster), Band (Rockspire's ring: its depth), AimFixed (with Angle: the aim never follows a target) }
--               (the form fields above: docs/superpowers/specs/2026-11-01-evolved-forms-design.md, plan Task 4, 2026-11-02).
--       Play writes ctx.ImpactLate = seconds the impact lands after DueAt (0 unless a Ranged shot's MinTravel needed
--       more time than DueAt left; BattleController then plays the Hit that much later).
--       A point is Model:GetPivot() while the Model is in the game, else its last known point, else Pos: a unit
--       destroyed mid-travel ends the effect at its last known point; From.Model may be nil (From.Pos only).
--       (battle-feel T1, docs/superpowers/specs/2026-11-10-battle-feel-design.md decision 4) a TARGET's point is its body
--       centre while Config.Battle.Feel.Aim.Mode = "Centre": an Attachment named AimPoint in the model, else its bounding-box
--       centre when that sits over K.AIM_MIN (1 stud) off the pivot (a boss's feet root), else the pivot (pets: unchanged);
--       read once per model. A Melee bite / a Pounce on such a big body lands on its near edge at the caster's height.
--       Ground layers stand on eff.FloorY = ctx.Ground, refined by ONE downward raycast under the target at the Play
--       (Aim.FloorRay; believed within FLOOR_RAY_MAX 6 studs of ctx.Ground), never on the hit minus the caster's drop.
--   AttackFx.AimOf(side) -> Vector3   a side's aim point (the rule above; Mode "Pivot" = its pivot)
--   AttackFx.BitePoint(src, tgt) -> Vector3 | nil   the near edge of tgt on the flat line from src, at src.Last.Y
--   AttackFx.Update(now)            advances every live effect and pose; called from BattleController's existing
--                                   per-frame step (no RenderStepped / Heartbeat connection of its own)
--   AttackFx.Pose(unitId, base?) -> { Name, P, Ranged, Amp?, Reach?, Blend, Prev? } | nil   the pose a battle unit shows now (PetPoses
--       names; P 0..1). Blend = 1 normally; for AttackFx.CROSSFADE (0.12 s) after a pose replaces another mid-way,
--       Blend rises 0 -> 1 and Prev = { Name, P, Ranged } is the replaced pose, still animating. The CALLER blends:
--       root = frame * PoseBody(Prev):Lerp(PoseBody(cur), Blend), Animate with the current pose (Prev while
--       Blend < 0.5; the returned tables are reused per unit: read them at once). The newest play on a unit wins (Ko > Cast > Windup / Strike / Shoot / Victory > Hurt while
--       the higher one is still playing); Melee = Windup + the Strike lunge, Ranged = the ranged Windup (rear back) +
--       Shoot (the head snaps forward, the body kicks back: never the lunge, player note 1); a melee Strike freezes for HIT_STOP (0.05 s) at the impact; Ko holds at P = 1 until
--       Cancel(unitId) / ClearAll(). nil = no attack pose (the caller shows IdleBattle or nothing). A melee Strike carries
--       Amp (the band's leap scale) and Reach (AttackFx.LeapReach at the Play: the leap lands on the target); the caller
--       passes both on to PetBuilder.PoseBody / Animate (PetPoses.Sample's amp, reach). A Pounce (Task 10) leaps like
--       the melee (Reach = the gap, its landing on the slam); with `base` (Vector3, the unit's drawn spot before the pose)
--       its Reach is what is LEFT from the base to the landing spot fixed at the Play: the server moves a pouncing pet to
--       its target, and as the drawn base slides there the leap shrinks, so the pet is never carried past the target.
--   AttackFx.LeapReach(src, tgt) -> number | nil   the melee leap's length in the caster's pose units (studs at scale
--       1): from its front edge to the target's near edge, minus LEAP_MARGIN 0.3, clamped 0 .. LEAP_MAX 12 world studs,
--       / the caster's PB_Scale (the leap's only clamp: PetPoses' LEAP_REACH_MAX is a safety ceiling that a reach from
--       here never meets, so a small pet lands as far as a big one). src / tgt = { Model?, Last = Vector3 }
--   AttackFx.Cancel(unitId)         drops the unit's pose and ends the effects it cast (a unit swapped out / gone)
--   AttackFx.EndAura(unitId?) -> bool  (evolved forms) the unit's Rally / Haste aura ends now (nil = every aura): the kits it held go back, the pet is its size again; its beats play on
--   AttackFx.AuraLeft(unitId, now?) -> seconds | nil   how long the unit's aura still has to run
--   AttackFx.ClearAll()             ends everything (the battle is over)
--   AttackFx.SetQuality("Low" | "High" | nil)   nil = follow client/GraphicsQuality.Effective(). Low: emitters per
--       effect <= 2 (the Burst, then the first of the recipe's LowKeep it has: the element's most characteristic one),
--       particle counts halved, no Beams / Trails / bloom light; switching to Low strips the Beams /
--       Trails of the live effects at once
--   AttackFx.Stats() -> { Live, Stepped, Tails, Emitters, Beams, Trails, Lights, Cores, Rims, Pooled, PoolInstances, Errors }
--       Live = full effects, Stepped = stepped-down ones, Tails = effects past their beats with only their lingering marks left,
--       the rest = kits held by live effects / pooled kits
--   AttackFx.Hooks = { Punch = fn(amount, seconds), ScreenGlow = fn(color, seconds), DimWorld = fn(seconds, token, unit),
--                      Undim = fn(token), Inhale = fn(seconds, token, mine), Hush = fn(token), Shatter = fn(mine, unit), AuraScale = fn(unit, k) }
--       set by the caller: AuraScale (evolved forms) = a Rally's bigger pet, k at the impact and 1 when it ends for any reason (the From model's "AuraScale" attribute says the same; a look only); the camera kick (own attacks, recipe.CameraPunch: by kind and band, about 0.15 s, amount <= PUNCH_MAX
--       0.35, basic hits at most once per its Gap: route it through BattleController's Me.Shake / ShakeScale path), the edge glow
--       (own pet, band 4) and a signature's dimming
--       (own pet: Eclipse Nova; seconds = from now to the recipe's Sig.DimWorld after the impact, token = a number of
--       its own per effect, unit = the caster's unit id or nil); Undim(token) comes when that effect ends for any reason: end, Cancel, ClearAll,
--       error). AttackFx never touches the camera or Lighting itself; other players' effects call no hook.
--   (Task 11b, the Special pre-charge) Play's ctx may also carry LateMax (a battle Special nobody pressed: the charge the
--       render lead cut is given back, up to LateMax seconds, and ctx.ImpactLate = that much: the impact lands after
--       DueAt; BattleController holds that special's hits for it) or Precharged = true (the caster's predicted charge,
--       if one lives, is taken over: the charge is backdated to the press, the impact stays on DueAt, the glow / rim /
--       inhale carry on). A Special with >= CUE_MIN of its charge seen gets the charge cues: a rim Highlight on the caster
--       (High only, MAX_RIMS live) and Hooks.Inhale(seconds to the release, token, mine) (Hooks.Hush(token) when it ends
--       early). At such a battle Special its charge glow ranks right after the Burst / LowKeep.
--   AttackFx.Precharge(ctx) -> bool   a press's predicted charge (Kind, From, To = the likely target, Mine, Seconds =
--       how long the caller waits for the event): the charge at the mouth + rim + inhale + a held Cast (Pounce: Windup)
--       pose, open-ended (<= K.PRE_HOLD); no core, no impact
--   AttackFx.Shatter(unit, now?, quiet?) -> bool   the prediction breaks (refused / no event): shards, the glow fades, Recoil,
--       Hooks.Shatter(mine, unit); false when the unit has none (quiet = true: it only fades).   AttackFx.Precharging(unit) -> effect | nil
--   AttackFx.Folder() -> Folder     workspace.ClientBattle.AttackFx (the kits, live and pooled)
--   Tests: AttackFx._Deps({ MeshLibrary =, TextureIds =, GraphicsQuality = }) (false = the real one again),
--          AttackFx._Live() (the live effects)
--
-- Lingering (attack effects, 2026-11-01): eff.TailAt = the end of the beats (every item ends by it); eff.EndRel = TailAt +
-- recipe.Afterglow x Density (0 at Low, on a miss and on a predicted charge). Past TailAt an effect is a tail (eff.Tail): its
-- Linger layers alone (the ground marks, the embers) stay on, dim, still and only fading, so nobody dodges a ghost; everything else went
-- back to the pool and its dim / inhale ended, as they did before there were tails.
-- An aura (evolved forms: recipe.Aura, a Rally / Haste with its buff's Seconds) is a tail too: eff.AuraRel = when it ends; its Linger layers (AllyRing, Rouse, Wind, Gust) hold and
-- follow the pet until then, and MAX_TAILS never finishes it: it ends with the buff (EndAura, the Seconds), a KO, a swap or a switch to Low.
-- Budget: MAX_LIVE (10) full effects; over it a play steps down one rarity band (MAX_STEPPED more at most), then
-- Play returns false. A tail counts in neither; MAX_TAILS (12) of them at once, a newer one finishes the oldest. Per effect: MAX_EMITTERS (6 High / 2 Low) ParticleEmitters, MAX_BEAMS, MAX_TRAILS,
-- MAX_LIGHTS, MAX_CORES solid pieces. Over a cap the layers are RANKED, never cut in catalog order: emitters by
-- emitterRank (the Burst, LowKeep, impact detail, Sparks ...), beams by beamRank (the alive detail, the recipe's own beams, the
-- ladder's DoubleArc / ShotArcs; one beam each first, then each layer's KeepCount (a kind's identity: the Beam's two
-- spiral arcs, Task 10 review I2), then each layer's own count, best first: beamBudget).
-- Counts are the catalog's FULL density x recipe.Density (0.6 for others' pets)
-- x 0.5 at Low. Emitters stay Enabled = false (Rate 0) and are fired with Emit(): one emitter serves several points
-- (allies, rain) and nothing ever streams on by itself.
--
-- Kits (pooled per kind under the folder, hidden when free, POOL keep sizes below; nothing is created per frame):
--   Emitter  an invisible anchored host Part + a ParticleEmitter (the host's Size gives the Box / Sphere shapes);
--            4x4 sheets: FlipbookLayout Grid4x4, FlipbookMode + FlipbookFramerate from blender/vfx/textures.json
--            (SHEETS below), LightEmission per sheet (glows 1, smoke / dust / rock 0), size + transparency curves
--   Beam     two host Parts with an Attachment each + a Beam (fx_lightning / fx_speedlines strips, or untextured)
--   Trail    a host Part with two Attachments + a Trail
--   Light    a host Part + a PointLight
--   Disc     a flat cylinder carrying a soft glow image (fx_glow) on its top face (untextured ground glows: scorch,
--            ground glow, the Shadow floor darkening; Task 8: a hard Neon plate read as pink plastic). Without the
--            glow texture id it falls back to the plain Neon cylinder.
--   Core     the single MeshPart "Core" of a vfx_* key from MeshLibrary.Assemble, tinted (Color / Material from the
--            recipe; band 2+ adds a hot inner core, band 3+ a twin blade / fins), scaled and faded with easing
-- Cores: a key MeshLibrary.IsReady says is not usable here is skipped: the effect still plays with its texture
-- layers only (every recipe reads without its core: the impact burst, the element detail and the charge glow are
-- all textured). Textures are "rbxassetid://" .. the TextureIds number (Image ids only, never Decal ids).
-- Layer kinds: Emitter (flipbook particles; burst motions Burst, Geyser = an upward column, Implode = pulled
-- inward, Fling, Rise, Shatter, Erupt; Spiral / Fall / trails stream over their beat), Decal (a textured 4x4 sheet
-- drawn as a ground-flat particle (VelocityPerpendicular), else a glow Disc), Beam (path bolts, spirals, arcs, the
-- double crescent, stray strikes, constellation lines), Trail (afterimages, the pounce leap, wind on allies), Light
-- (flash, bloom pulse, the colour-shifting plasma rim), Ring (vfx_ring / vfx_shell expanding), Mesh (vfx_* pieces
-- erupting). Layer Delay = seconds after its beat starts; At "Behind" = behind the caster. Unknown motions play as
-- a plain burst. The signature Actor (vfx_sig_*) moves by its Motion (SpiralUp, ChargeThrough, Eclipse, Sweep,
-- WishRise, Seal, FoxFire, RingRise, RiseRoar, MoonRise, Rise, PackCharge, Shatter: see MOVE.Actor); Task 11: it is built right after the core (the
-- piece cap never cuts it), Count x Density pieces for others' pets, Rim = a bigger glowing copy behind each piece, Echo =
-- dimmer copies trailing it along its path (Obsidian's black-flame wings); Low quality builds neither (fix round 1, M1).
-- A Storm core with Spread = true rains on EVERY target (round robin), not round the aimed one (Obsidian: the enemies in
-- its Storm zone, which BattleController gathers: fix round 2, I1).
-- Task 10 (the 9 special kinds): an Emitter with Along = true streams along mouth -> hit while the beam holds (the Beam's
-- wrap); Drift = true streams off its points over its beat (the Haste gust); Shape "Plus" holds the sheet upright, no
-- roll / spin (the Heal's plus sparkles); a Ring or Mesh layer At "Allies" puts its piece(s) on each ally (the Rally
-- rings, the Nature ward's root); a Mesh layer's Transparency makes it see-through; the Pounce leaps the gap like the
-- melee and its leap trails ride the pet's pivot (scripted hop without a model).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Client = script.Parent and script.Parent.Parent

local AttackFx = {}

AttackFx.MAX_LIVE = 10
AttackFx.MAX_STEPPED = 4
AttackFx.MAX_TAILS = 12
AttackFx.MAX_EMITTERS = { High = 6, Low = 2 }
AttackFx.MAX_BEAMS = 4
AttackFx.MAX_TRAILS = 4
AttackFx.MAX_LIGHTS = 3
AttackFx.MAX_CORES = 14
AttackFx.PUNCH_MAX = 0.35 -- BattleController SHAKE_MAX
AttackFx.CROSSFADE = 0.12
AttackFx.HIT_STOP = 0.05
-- (battle-feel T3, spec decision 5) a special's impact freezes the caster's Cast and each victim's Hurt this long:
-- Config.Battle.Feel.Special.HitStop while Weighty is on (0 off; read per Play, see specialStop)
AttackFx.SPECIAL_HIT_STOP = 0.08
-- (Task 11b) a Special's charge cues: a rim Highlight on the charging pet (at most MAX_RIMS live at once, High only)
-- and the inhale sound hook, both only when at least CUE_MIN seconds of the charge are seen; a press's predicted charge
-- that is refused / never confirmed shatters: its shards fly for SHATTER seconds
AttackFx.MAX_RIMS = 3
AttackFx.CUE_MIN = 0.15
AttackFx.SHATTER = 0.45
AttackFx.Hooks = { Punch = nil, ScreenGlow = nil, DimWorld = nil, Undim = nil, Inhale = nil, Hush = nil, Shatter = nil, AuraScale = nil }

-- (attack effects, 2026-11-01) the Specials with a drawn radius: eff.Reach when ctx.Radius did not come (BattleCatalog's numbers)
local SPECIAL_RADIUS = { Blast = 7, Freeze = 6, Storm = 6 }

local K = {
	PARENT = "ClientBattle",
	FOLDER = "AttackFx",
	KEEP = { Emitter = 24, Beam = 8, Trail = 6, Light = 8, Disc = 24, Rim = 3 }, -- (Disc, review: the tails hold ground marks up to 2 s longer; at 8 a busy fight made and destroyed them)
	CORE_KEEP = 6, -- per vfx_* key
	CORE_KEYS = 22,
	LOW_COUNT = 0.5,
	MAX_ALLIES = 4,
	MOUTH = 0.9, -- studs in front of the caster's centre (x size)
	ABOVE = 5,
	BEHIND = 2.6,
	DROP = 1.6, -- default height of a unit's centre over the floor
	HURT = 0.5,
	KO = 0.9,
	VICTORY = 1.2,
	SHOOT = 0.6, -- the ranged Shoot pose (PetPoses): the head snaps forward, the body kicks back, settles
	LEAP_STEP = 0.08, -- the melee Strike's leap grows by this per rarity band above Common (PetPoses amp, <= 1.25)
	-- (Task 9 player decision: the melee leap lands on the target) its forward reach = the gap between the caster's and
	-- the target's facing edges minus LEAP_MARGIN, clamped 0 .. LEAP_MAX world studs
	LEAP_MARGIN = 0.3,
	LEAP_MAX = 12,
	-- (Task 10) the Pounce's Strike: up to this long, its landing (p 0.26) on the slam. (battle-feel T3: 1.6 -> 2.2: the
	-- Weighty leap flies up to 0.5 s + the release, 0.55 / 0.26 = 2.12 s, so the landing still falls on the slam)
	POUNCE_DUR_MAX = 2.2,
	LEAP_TRAIL_UP = 0.3, -- (Task 10) the leap trails ride the pet this far over its pivot
	BAND_RARITY = { "Common", "Rare", "Legendary", "Secret" },
	PRIO = { Ko = 4, Cast = 3, Windup = 2, Strike = 2, Shoot = 2, Recoil = 2, Victory = 2, Hurt = 1, DashIn = 2, DashBack = 2 },
	-- (Task 11b) the charge cues and the predicted charge
	RIM_IN = 0.3, -- the rim Highlight fades in over this from the charge's start (a backdated charge keeps its rim)
	RIM_OUT = 0.25, -- ... and out over this after the release
	RIM_OUTLINE = 0.2, -- its outline transparency at full
	RIM_FILL = 0.82, -- its fill transparency at full (a faint wash of the element's colour)
	-- seconds a predicted charge lasts at most (BattleController shatters it sooner: its PRESS_WAIT, or (battle-feel T3)
	-- the server cast's end + CAST_WAIT: up to ~1.7 s after a press)
	PRE_HOLD = 2.0,
	PRE_CAST_P = 0.5, -- the predicted charge's Cast pose holds at this p (risen, wings spread, eyes shut gathering power)
	PRE_WINDUP_P = 0.6, -- ... a Pounce's Windup holds at this p (the full crouch)
	PRE_MIN_CHARGE = 0.25, -- a pressed Special shows at least this much charge before its release (travel gives way)
	RETIRE = 0.45, -- a charge given up (shattered, or the part the real effect did not take over) ends this long after
	SHARDS = 8, -- shards of a shattered charge (x 0.5 at Low)
	SHARD_TEX = "fx_sparkle", -- their sheet: four-point glints flung out like glass
	RECOIL = 0.35, -- the shattered caster rears back (PetPoses Recoil) this long
	-- (Studio findings round, 2026-10-27)
	SHELL_FALLBACK = 0.7, -- a Shield dome with no ally model to fit: x its old size (~30 % smaller)
	SHELL_APART = 0.46, -- a dome's radius is at most this x the distance to the nearest other ally (never one blob)
	-- the fx_streak sheet is horizontal (head right): turned upright (FacingCameraWorldUp, Task 11c). (Task 11d, Studio
	-- round 3, S1: at +90 the hot head pointed UP, the falling rain read as "!" marks) -90: the head leads the fall
	STREAK_ROT = -90,
	SEG_GAP = 0.2, -- a segmented Stretch core's default gap (share of each segment)
	BODY_R = 1.2, -- studs: a character's / pet's body radius the Wishing Star keeps clear of (+ its own half-width)
	-- (Task 11c, Studio round 2, 2026-10-27)
	SWEEP_EDGE = 1.2, -- Obsidian's pass runs this far (x size) past the enemy line's ends (was 2.5): inside the zone
	MOON_LIFT = 4.5, -- the dusk moon's height over the hit when the effect has no cloud lift (= the Storm cloud's Height)
	MOON_BACK = 1.2, -- ... and how far (x size) behind the target, away from the caster
	STREAK_SIZE = 0.8, -- the Storm rain's streaks x the Rain layer's Size (review M1: the sheets of hail / petals keep 1)
	-- (Task 11d, Studio round 3, 2026-10-27)
	MOON_GAP = 0.1, -- S4: studs between the storm cloud's top and the dusk moon's lowest point (it sits just above the puffs)
	SERPENT_CLEAR = 0.3, -- S5: the Void Fangs heads' tops stay this far at most over the caster's head (under its name tag)
	SERPENT_GAP = 0.6, -- S5: ... rooted this far (x size) past the caster's body, away from the viewer
	-- (attack effects, 2026-11-01, review) the caps Task 8 judged in Studio: a light's range grows with the Size up to the 1.4 of that
	-- round, its brightness stops at 2 after the crit (a signature's own light over that keeps its number)
	LIGHT_SIZE = 1.4,
	LIGHT_BRIGHT = 2,
	-- (evolved forms) the pack on the real charge line (MOVE.Actor PackCharge)
	PACK_BEHIND = 8, -- no Line: it starts this far behind the caster ...
	PACK_PAST_TARGET = 3, -- ... and ends this far past the target (BattleCatalog's Pounce line)
	PACK_GAP = 0.08, -- the stagger between wolves
	PACK_MIN = 0.3, -- a wolf runs to the target for at least this long: a charge cut to the event still shows it
	PACK_PAST = 0.25, -- ... from the target to the line's end for this long
	PACK_FADE = 0.15, -- ... and fades over this
	PACK_SPREAD = 1.2, -- how far across the line the outer wolves run (x size, <= half the line's width)
	PACK_NEAR = 0.25, -- the share of that left as they pass the target, so all of them reach it
	PACK_CLOSE = 0.35, -- ... closing over this share of the line round it
	SHATTER_RADIUS = 2.4, -- studs (x size) a Shatter actor's pieces fly out, unless the actor says
	-- (evolved forms) a held layer (an aura's Linger)
	AURA_LIFE = 0.5, -- its stream stops this long before the aura's end: the last particles end with it
	AURA_RATE = 0.75, -- its stream's particles a second, x the layer's Count
	AURA_FADE = 0.3, -- its ring fades over this at the end
	WIND_SPIN = 7, -- radians a second round the pet
	-- (battle-feel T1, the centre aim) a model's bounding-box centre is aimed at only when it sits more than this from the
	-- pivot (a boss's feet root); a pet's centre is its pivot, so pets aim exactly as before
	AIM_MIN = 1.0,
	FLOOR_RAY = 80, -- studs: the one downward ray per effect that finds the real floor under the target
	-- (battle-feel T2, the melee dash: AttackFx.Dash) PetPoses.DASH_RUN: DashIn's run reaches the edge at this p (the landing)
	DASH_RUN = 0.78,
	DASH_MAX = 20, -- world studs a dash may run at most (the standoff gap to a boss's near edge is ~6-12)
	LUNGE_DUR = 0.45, -- a flurry's in-place bite: a Strike of Melee.Lunge studs over this long, landing at p 0.26 (PetPoses LEAP_LAND)
	LEAP_LAND = 0.26,
	STREAK_LIFE = 0.12, -- the speed streak's Trail Lifetime (a short smear, never a tether)
	STREAK_HALF = 0.4, -- studs: the streak's half-width
	STREAK_TRANS = { Mine = 0.3, Other = 0.6 }, -- its transparency: my pet's reads first
}
-- (battle-feel T1) the ray's floor is believed only within this of ctx.Ground (a rail or a pit is not the arena floor)
AttackFx.FLOOR_RAY_MAX = 6
AttackFx.POOL_KEEP_TOTAL = K.KEEP.Emitter + K.KEEP.Beam + K.KEEP.Trail + K.KEEP.Light + K.KEEP.Disc + K.KEEP.Rim + K.CORE_KEEP * K.CORE_KEYS

-- the 4x4 sheets of blender/vfx/textures.json: key -> { FlipbookMode, fps, LightEmission }
-- (fx_lightning / fx_speedlines are grid-1 strips: Beams / Trails only)
local SHEETS = {
	fx_flame = { "Loop", 24, 0.75 }, fx_embers = { "Loop", 20, 1 }, fx_smoke = { "OneShot", 16, 0 },
	fx_splash = { "OneShot", 20, 0.35 }, fx_droplets = { "OneShot", 16, 0.25 }, fx_ripple = { "OneShot", 16, 0.4 },
	fx_iceshards = { "Loop", 16, 0.45 }, fx_snow = { "Loop", 12, 0.5 }, fx_frostmist = { "OneShot", 16, 0.3 },
	fx_petals = { "Loop", 16, 0.3 }, fx_leaves = { "Loop", 16, 0.15 }, fx_thorn = { "OneShot", 24, 0.2 },
	fx_rock = { "Loop", 16, 0 }, fx_dust = { "OneShot", 16, 0 }, fx_crack = { "OneShot", 20, 0.6 },
	-- (Task 9 Studio: fully additive, the golden stars / rays summed to a white flare on the pale arena; half-lit they
	-- keep their gold)
	fx_sparks = { "Loop", 24, 1 }, fx_stormcloud = { "Loop", 12, 0.1 }, fx_stars = { "Loop", 16, 0.5 },
	fx_rays = { "OneShot", 20, 0.5 }, fx_sparkle = { "Loop", 16, 1 }, fx_wisps = { "Loop", 16, 0.4 },
	fx_voidring = { "OneShot", 20, 0.5 }, fx_darkglass = { "Loop", 16, 0.2 }, fx_slash = { "OneShot", 30, 1 },
	fx_shock = { "OneShot", 20, 0.9 }, fx_glow = { "Loop", 12, 1 }, fx_streak = { "Loop", 24, 1 },
	fx_hexshield = { "Loop", 16, 0.8 },
}

local sin, cos, abs, min, max, floor, sqrt, huge, pi = math.sin, math.cos, math.abs, math.min, math.max, math.floor, math.sqrt, math.huge, math.pi
local TAU = 2 * pi
local V3 = Vector3.new
local UP = V3(0, 1, 0)
local ONE = V3(1, 1, 1)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

----------------------------------------------------------------------
-- Helpers: easing, numbers
----------------------------------------------------------------------
local function clamp01(x)
	if x ~= x or x < 0 then
		return 0
	elseif x > 1 then
		return 1
	end
	return x
end

-- 0..1 progress of t through [a, b] (an empty window is a step at a)
local function seg(t, a, b)
	if b <= a then
		return (t >= a) and 1 or 0
	end
	return clamp01((t - a) / (b - a))
end

local function smooth(x)
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end

local function outCubic(x)
	x = 1 - clamp01(x)
	return 1 - x * x * x
end

-- ease out with an overshoot (~1.1) that settles at 1
local function outBack(x)
	x = clamp01(x)
	if x == 0 then
		return 0
	end
	local s = 1.70158
	x = x - 1
	return 1 + (s + 1) * x * x * x + s * x * x
end

local function hash(i, salt)
	local h = sin(i * 12.9898 + (salt or 0) * 78.233) * 43758.5453
	return h - floor(h)
end

local function finite(n)
	return type(n) == "number" and n == n and n ~= huge and n ~= -huge
end

local function flat(v)
	return V3(v.X, 0, v.Z)
end

-- CFrame at pos looking along dir (-Z = dir), safe when dir is vertical
local function face(pos, dir)
	if dir.Magnitude < 1e-4 then
		return CFrame.new(pos)
	end
	dir = dir.Unit
	if abs(dir.Y) > 0.985 then
		return CFrame.lookAt(pos, pos + dir, V3(0, 0, -1))
	end
	return CFrame.lookAt(pos, pos + dir)
end

local function kp(t, v)
	return NumberSequenceKeypoint.new(t, v)
end

local function material(name)
	if type(name) == "string" then
		local ok, m = pcall(function()
			return Enum.Material[name]
		end)
		if ok and m then
			return m
		end
	end
	return Enum.Material.Neon
end

----------------------------------------------------------------------
-- Dependencies (lazy; _Deps overrides them in tests)
----------------------------------------------------------------------
local deps = {}
local mods = {}

local function loadModule(parent, name)
	local m = mods[name]
	if m == nil then
		m = false
		local inst = parent and parent:FindFirstChild(name)
		if inst then
			local ok, result = pcall(require, inst)
			if ok and type(result) == "table" then
				m = result
			end
		end
		mods[name] = m
	end
	return m or nil
end

local function dep(name)
	local o = deps[name]
	if o then
		return o
	end
	if name == "GraphicsQuality" then
		return loadModule(Client, name)
	end
	return loadModule(ReplicatedStorage:FindFirstChild("Shared"), name)
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local St = {
	live = {}, -- live effects, in play order
	poses = {}, -- unitId -> { Segs, Prio, Prev?, SwitchAt? }
	pool = { Emitter = {}, Beam = {}, Trail = {}, Light = {}, Disc = {}, Rim = {} },
	corePool = {}, -- key -> { kits }
	pre = {}, -- (Task 11b) unitId -> its predicted charge (an effect with Pre = true)
	forced = nil, -- SetQuality's mode (nil = GraphicsQuality)
	mode = nil, -- the mode applied to the live effects
	now = nil, -- the last Update clock
	folder = nil,
	errors = 0,
	warned = {},
	dimSeq = 0, -- (Task 11) the last battle-dim token handed to Hooks.DimWorld
	cueSeq = 0, -- (Task 11b) the last inhale token handed to Hooks.Inhale
	lastBasicKick = nil, -- (attack effects, 2026-11-01) when a basic hit last kicked the camera (Kick.BasicGap)
	streaks = {}, -- (battle-feel T2) the live dash streaks: { Kit, Unit, Model, T0, T1, Mine } (<= Melee.StreakMax)
}

local function warnOnce(key, msg)
	if not St.warned[key] then
		St.warned[key] = true
		warn("[AttackFx] " .. tostring(msg))
	end
end

local function ensureFolder()
	local f = St.folder
	if f and f.Parent and f.Parent.Parent == Workspace then
		return f
	end
	-- the folder is gone (a battle clean-up destroyed ClientBattle): the pooled kits went with it
	St.pool = { Emitter = {}, Beam = {}, Trail = {}, Light = {}, Disc = {}, Rim = {} }
	St.corePool = {}
	local root = Workspace:FindFirstChild(K.PARENT)
	if not root then
		root = Instance.new("Folder")
		root.Name = K.PARENT
		root.Parent = Workspace
	end
	f = root:FindFirstChild(K.FOLDER)
	if not f then
		f = Instance.new("Folder")
		f.Name = K.FOLDER
		f.Parent = root
	end
	St.folder = f
	return f
end

----------------------------------------------------------------------
-- Kits
----------------------------------------------------------------------
local function hostPart(name)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Transparency = 1
	p.Size = V3(0.2, 0.2, 0.2)
	return p
end

local NEW = {}

function NEW.Emitter(folder)
	local host = hostPart("FxEmitter")
	local em = Instance.new("ParticleEmitter")
	em.Name = "Fx"
	em.Enabled = false
	em.Rate = 0
	em.Parent = host
	host.Parent = folder
	return { Kind = "Emitter", Root = host, Em = em, N = 2 }
end

function NEW.Beam(folder)
	local h0 = hostPart("FxBeam")
	local h1 = hostPart("FxBeamEnd")
	h1.Parent = h0
	local a0 = Instance.new("Attachment")
	a0.Parent = h0
	local a1 = Instance.new("Attachment")
	a1.Parent = h1
	local b = Instance.new("Beam")
	b.Enabled = false
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.FaceCamera = true
	b.LightInfluence = 0
	b.Parent = h0
	h0.Parent = folder
	return { Kind = "Beam", Root = h0, H1 = h1, Beam = b, N = 5 }
end

function NEW.Trail(folder)
	local h = hostPart("FxTrail")
	local a0 = Instance.new("Attachment")
	a0.Position = V3(0, 0.5, 0)
	a0.Parent = h
	local a1 = Instance.new("Attachment")
	a1.Position = V3(0, -0.5, 0)
	a1.Parent = h
	local tr = Instance.new("Trail")
	tr.Enabled = false
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.LightInfluence = 0
	tr.FaceCamera = true
	tr.Parent = h
	h.Parent = folder
	return { Kind = "Trail", Root = h, A0 = a0, A1 = a1, Trail = tr, N = 4 }
end

function NEW.Light(folder)
	local h = hostPart("FxLight")
	local l = Instance.new("PointLight")
	l.Enabled = false
	l.Brightness = 0
	l.Shadows = false
	l.Parent = h
	h.Parent = folder
	return { Kind = "Light", Root = h, Light = l, N = 2 }
end

function NEW.Disc(folder)
	local d = hostPart("FxDisc")
	d.Shape = Enum.PartType.Cylinder
	d.Material = Enum.Material.Neon
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Right -- the cylinder's end cap: up once the disc lies flat
	g.LightInfluence = 0
	g.CanvasSize = Vector2.new(64, 64)
	g.Parent = d
	local im = Instance.new("ImageLabel")
	im.BackgroundTransparency = 1
	im.Size = UDim2.fromScale(1, 1)
	im.ImageTransparency = 1
	im.ImageRectOffset = Vector2.new(256, 256) -- fx_glow is a 4x4 flipbook sheet (1024 px): one frame, not all 16
	im.ImageRectSize = Vector2.new(256, 256)
	im.Parent = g
	d.Parent = folder
	return { Kind = "Disc", Root = d, Gui = g, Img = im, N = 3 }
end

-- (Task 11b) a Special's rim light: a Highlight on the charging pet's model (an outline + a faint wash of its colour)
function NEW.Rim(folder)
	local h = Instance.new("Highlight")
	h.Name = "FxRim"
	h.Enabled = false
	h.FillTransparency = 1
	h.OutlineTransparency = 1
	pcall(function()
		h.DepthMode = "Occluded" -- (never through the arena walls; by name, like BattleController's hit flash)
	end)
	h.Parent = folder
	return { Kind = "Rim", Root = h, Hl = h, N = 1 }
end

local function coreReady(key)
	local ML = dep("MeshLibrary")
	if not (ML and type(ML.IsReady) == "function" and type(key) == "string") then
		return false
	end
	local ok, ready = pcall(ML.IsReady, key)
	return ok and ready == true
end

local function newCore(key, folder)
	local ML = dep("MeshLibrary")
	local ok, model = pcall(ML.Assemble, key, {}, {})
	if not ok or typeof(model) ~= "Instance" then
		return nil
	end
	local part = model:FindFirstChild("Core")
	if not (part and part:IsA("BasePart")) then
		part = model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not part then
		model:Destroy()
		return nil
	end
	part.Parent = folder
	model:Destroy()
	part.Name = "FxCore_" .. key
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	return { Kind = "Core", Key = key, Root = part, Base = part.Size, N = 1 }
end

local function take(kind, key)
	local folder = ensureFolder()
	if kind == "Core" and not coreReady(key) then
		return nil
	end
	local list = (kind == "Core") and St.corePool[key] or St.pool[kind]
	while list and #list > 0 do
		local kit = table.remove(list)
		if kit.Root.Parent == folder then
			return kit
		end
		pcall(kit.Root.Destroy, kit.Root)
	end
	if kind == "Core" then
		return newCore(key, folder)
	end
	return NEW[kind](folder)
end

local function hide(kit)
	local k = kit.Kind
	if k == "Emitter" then
		kit.Em.Enabled = false
		pcall(kit.Em.Clear, kit.Em)
		kit.Root.Size = V3(0.2, 0.2, 0.2)
	elseif k == "Beam" then
		kit.Beam.Enabled = false
	elseif k == "Trail" then
		kit.Trail.Enabled = false
		pcall(kit.Trail.Clear, kit.Trail)
	elseif k == "Light" then
		kit.Light.Enabled = false
		kit.Light.Brightness = 0
	elseif k == "Rim" then
		kit.Hl.Enabled = false
		kit.Hl.Adornee = nil
	else
		kit.Root.Transparency = 1
		if kit.Img then
			kit.Img.ImageTransparency = 1
		end
	end
end

local function give(kit)
	if not kit then
		return
	end
	pcall(hide, kit)
	local folder = St.folder
	local list, keep
	if kit.Kind == "Core" then
		list = St.corePool[kit.Key]
		if not list then
			list = {}
			St.corePool[kit.Key] = list
		end
		keep = K.CORE_KEEP
	else
		list, keep = St.pool[kit.Kind], K.KEEP[kit.Kind]
	end
	if folder and kit.Root.Parent == folder and #list < keep then
		list[#list + 1] = kit
	else
		pcall(kit.Root.Destroy, kit.Root)
	end
end

----------------------------------------------------------------------
-- Points of an effect (refreshed every frame)
----------------------------------------------------------------------
-- a side's point: the model's pivot while it is in the game, else its last known point, else Pos
local function pointOf(side)
	local m = side.Model
	if m then
		if m.Parent then
			local ok, cf = pcall(m.GetPivot, m)
			if ok and typeof(cf) == "CFrame" then
				side.Last = cf.Position
				return side.Last
			end
		else
			side.Model = nil -- destroyed / parked: keep its last known point
		end
	end
	if not side.Last and typeof(side.Pos) == "Vector3" then
		side.Last = side.Pos
	end
	return side.Last
end

-- (battle-feel T1) Config.Battle.Feel[group] (nil without the knob: the old behaviour)
local function feelOf(group)
	local C = dep("Config")
	local B = C and C.Battle
	local F = B and B.Feel
	return type(F) == "table" and F[group] or nil
end

local function centreAim()
	local a = feelOf("Aim")
	return a ~= nil and a.Mode == "Centre"
end

-- (battle-feel T3) the special's hit freeze now: Feel.Special.HitStop while Weighty (else 0); AttackFx.SPECIAL_HIT_STOP
-- follows it
local function specialStop()
	local s = feelOf("Special")
	local v = (s ~= nil and s.Weighty == true and type(s.HitStop) == "number" and s.HitStop == s.HitStop) and max(0, min(0.3, s.HitStop)) or 0
	AttackFx.SPECIAL_HIT_STOP = v
	return v
end

-- (battle-feel T1) per model, read once: its AimPoint attachment (or false), the bounding-box centre's offset from the
-- pivot in pivot space (zero when within K.AIM_MIN: pets) and the box itself in pivot space (the bite's near edge), so
-- nothing scans the model's parts per frame. Weak keys: a destroyed model drops out.
local aimCache = setmetatable({}, { __mode = "k" })
local ZERO = V3(0, 0, 0)

local function aimInfo(m)
	local c = aimCache[m]
	if c then
		return c
	end
	c = { Att = false, Off = ZERO, UseOff = false, Big = false }
	local att = m:FindFirstChild("AimPoint", true)
	if att and att:IsA("Attachment") and att.Parent and att.Parent:IsA("BasePart") then
		c.Att = att
		c.Big = true
	end
	local okP, pv = pcall(m.GetPivot, m)
	local okB, bcf, size = pcall(m.GetBoundingBox, m)
	if okP and okB and typeof(pv) == "CFrame" and typeof(bcf) == "CFrame" and typeof(size) == "Vector3" then
		local off = pv:PointToObjectSpace(bcf.Position)
		if off.Magnitude > K.AIM_MIN then
			c.Off = off
			c.UseOff = true
			c.Big = true
		end
		c.Box = pv:ToObjectSpace(bcf)
		c.Size = size
	end
	aimCache[m] = c
	return c
end

-- (battle-feel T1) a side's aim point: the body centre (the AimPoint attachment, else the cached box centre off the pivot,
-- else the pivot) while Config.Battle.Feel.Aim.Mode = "Centre"; otherwise pointOf (today). side.Last stays the PIVOT (the
-- leap, the distance and the direction read it); side.Aim / side.CF = the last centre / pivot CFrame. A model destroyed or
-- parked keeps its last centre.
local function aimOf(side)
	if not centreAim() then
		return pointOf(side)
	end
	local m = side.Model
	if m then
		if m.Parent then
			local ok, cf = pcall(m.GetPivot, m)
			if ok and typeof(cf) == "CFrame" then
				side.Last = cf.Position
				side.CF = cf
				local c = aimInfo(m)
				local q
				if c.Att and c.Att.Parent then
					q = c.Att.WorldPosition
				elseif c.UseOff then
					q = cf:PointToWorldSpace(c.Off)
				else
					q = side.Last
				end
				side.Aim = q
				return q
			end
		else
			side.Model = nil -- destroyed / parked: keep its last known point
		end
	end
	if side.Aim then
		return side.Aim
	end
	return pointOf(side)
end
AttackFx.AimOf = aimOf

-- (battle-feel T1) is this side a big body (a boss: its centre off its pivot, or an AimPoint)? Bites land on its near
-- edge; a pet is bitten at its pivot as before
local function bigBody(side)
	local m = side.Model
	if not (m and m.Parent and centreAim()) then
		return false
	end
	return aimInfo(m).Big
end

-- (review fix) a big body's box top (world Y) and its flat half-width, from the aim cache placed on its pivot this frame
-- (side.CF, set by aimOf); the last known top once the model is gone; nil for a pet (the "Above" anchor as before)
local function topOf(side)
	if not centreAim() then
		return nil, nil
	end
	local m = side.Model
	if m and m.Parent and side.CF then
		local c = aimInfo(m)
		if c.Big and c.Box and c.Size then
			local b = side.CF * c.Box
			local sz = c.Size
			side.Top = b.Position.Y + 0.5 * (abs(b.RightVector.Y) * sz.X + abs(b.UpVector.Y) * sz.Y + abs(b.LookVector.Y) * sz.Z)
			side.TopR = 0.5 * max(sz.X, sz.Z)
		end
	end
	return side.Top, side.TopR
end

-- the point an "Above" piece hangs over: the hit point, lifted to the box top when it is on a big body (the Storm cloud,
-- its rain, the crescent and the black sun sat inside a boss's upper body over its centre); -> the point, lifted?
-- (worked out once per frame in refresh: eff.Over / eff.Lifted; the rain pieces read it, no Vector3 per piece)
local function liftOf(eff)
	local h = eff.Hit
	local top = eff.TopY
	if top and top > h.Y and eff.T[1] then
		local d = V3(h.X - eff.T[1].X, 0, h.Z - eff.T[1].Z).Magnitude
		if d <= (eff.TopR or 0) + 4 then
			return V3(h.X, top, h.Z), true
		end
	end
	return h, false
end

local function overOf(eff)
	return eff.Over or eff.Hit, eff.Lifted == true
end

-- the floor under an effect's point: eff.FloorY (ctx.Ground, refined by one raycast under the target at the Play), never
-- the hit point minus the caster's drop (a boss's feet root sank the rings under the floor)
local function groundOf(eff, p)
	return V3(p.X, (eff.FloorY or (p.Y - eff.Drop)) + 0.05, p.Z)
end

-- (Studio findings round) the spots a big piece must not pass through: the caster, and ctx.Avoid (a Vector3 or a list)
-- or else the local player's character (the Wishing Star rose through the avatar)
local function avoidSpots(eff, out)
	out[1] = eff.S
	local n = 1
	local a = eff.Avoid
	if typeof(a) == "Vector3" then
		n = n + 1
		out[n] = a
	elseif type(a) == "table" then
		for _, v in ipairs(a) do
			if typeof(v) == "Vector3" then
				n = n + 1
				out[n] = v
			end
		end
	else
		local lp = Players and Players.LocalPlayer
		local ch = lp and lp.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			n = n + 1
			out[n] = root.Position
		end
	end
	for i = #out, n + 1, -1 do
		out[i] = nil
	end
	return n
end

-- p pushed out (flat) to at least r studs from every avoid spot. The caster (spot 1, where the path starts) pushes it
-- straight out (along `fwd` when it sits right on it); every other spot (the player) pushes it SIDEWAYS, across `fwd`,
-- to a side picked once per piece (`sides`, by spot: the side the piece first passed on, +1 when dead on the line).
-- (Task 11c, review I2: pushed radially, recomputed per frame, the star flipped across a spot it crossed: a ~10-stud
-- teleport in one frame with the player on its line, the /fx stance) A sideways push to a fixed side grows from 0 at
-- the keep-out circle's edge and back, so the path bends round the player smoothly.
local function keepClear(eff, p, r, fwd, sides)
	local spots = eff.AvoidPts
	local n = avoidSpots(eff, spots)
	local lat = fwd:Cross(UP)
	for _ = 1, 2 do -- (twice: a push away from one spot may land near the other)
		for i = 1, n do
			local c = spots[i]
			local d = V3(p.X - c.X, 0, p.Z - c.Z)
			local m = d.Magnitude
			if i > 1 and sides then
				local s = d:Dot(lat)
				local side = sides[i]
				if not side then
					side = (s < -0.05) and -1 or 1
					sides[i] = side
				end
				if m < r then
					local a = d:Dot(fwd)
					local need = sqrt(max(0, r * r - a * a))
					if s * side < need then
						p = p + lat * (side * need - s)
					end
				end
			elseif m < r then
				local dir = (m > 0.05) and (d / m) or fwd
				p = V3(c.X, p.Y, c.Z) + dir * r
			end
		end
	end
	return p
end

local function hitOf(eff)
	local hit
	if eff.Path == "Self" then
		hit = eff.S
	elseif eff.Path == "Allies" then
		hit = eff.T[1] or eff.S
	elseif eff.Area == "Cone" then
		hit = eff.S + eff.Dir * (eff.Reach * 0.6)
	elseif eff.Area == "Line" then
		hit = eff.S + eff.Dir * (eff.Reach * 0.5)
	elseif eff.Area == "Circle" then
		hit = eff.Center or eff.S -- (evolved forms: a ranged pet's Circle lands on its aim point)
	else
		hit = eff.T[1] or (eff.S + eff.Dir * 8)
	end
	if eff.Miss and eff.Path ~= "Self" and eff.Path ~= "Allies" then
		hit = hit + eff.Dir * 2.5 + eff.Right * 1.2 -- a miss lands beside the target
	end
	return hit
end

local function refresh(eff)
	local s = pointOf(eff.Src)
	if s then
		eff.S = s
	end
	-- (battle-feel T1) the body centre (aimOf); a bite (Melee, the Pounce) on a big body lands on its near edge at the
	-- caster's height (AttackFx.BitePoint)
	for i, side in ipairs(eff.Targets) do
		local p = aimOf(side)
		if p and eff.Bite and bigBody(side) then
			p = AttackFx.BitePoint(eff.Src, side) or p
		end
		if p then
			eff.T[i] = p
		end
	end
	local side1 = eff.Targets[1]
	if side1 then
		eff.TopY, eff.TopR = topOf(side1)
	end
	local first = eff.T[1]
	if first and not eff.Area and not eff.AimFixed then
		local d = flat(first - eff.S)
		if d.Magnitude > 0.2 then
			eff.Dir = d.Unit
		end
	end
	eff.Right = eff.Dir:Cross(UP)
	eff.Mouth = eff.S + eff.Dir * (K.MOUTH * eff.Size) + UP * 0.25
	eff.Hit = hitOf(eff)
	eff.Over, eff.Lifted = liftOf(eff)
end

-- fills `out` with the world points of an anchor; returns how many
local function atPoints(eff, at, out)
	local n = 1
	if at == "Source" then
		out[1] = eff.Mouth
	elseif at == "Core" then
		out[1] = eff.CorePos or eff.Hit
	elseif at == "Ground" then
		out[1] = groundOf(eff, eff.Hit)
	elseif at == "Above" then
		out[1] = overOf(eff) + UP * (K.ABOVE * eff.Size)
	elseif at == "Behind" then
		out[1] = eff.S - eff.Dir * (K.BEHIND * eff.Size) + UP * 0.5
	elseif at == "Self" then
		out[1] = eff.S
	elseif at == "Allies" then
		n = 0
		for i = 1, min(#eff.T, K.MAX_ALLIES) do
			n = n + 1
			out[n] = eff.T[i]
		end
		if n == 0 then
			n = 1
			out[1] = eff.S
		end
	else
		out[1] = eff.Hit -- Target / Path / unknown
	end
	for i = #out, n + 1, -1 do
		out[i] = nil
	end
	return n
end

-- a solid piece's anchor point (+ its offsets in the effect's right / forward frame)
local function anchorPoint(eff, it)
	local a = it.Anchor
	local p
	if a == "Path" then
		p = eff.S:Lerp(eff.Hit, it.F or 1)
	elseif a == "Self" then
		p = eff.S
	elseif a == "Source" then
		p = eff.Mouth
	elseif a == "Above" then
		p = overOf(eff) + UP * (K.ABOVE * eff.Size)
	elseif a == "Behind" then
		p = eff.S - eff.Dir * (K.BEHIND * eff.Size)
	elseif type(a) == "number" then
		p = eff.T[a] or eff.S
	else
		p = eff.Hit
	end
	return p + eff.Right * (it.OffR or 0) + eff.Dir * (it.OffD or 0)
end

-- where a projectile core is at t (also drives the layers At = "Core"); other paths: the hit point
local function corePosOf(eff, t)
	local core, T = eff.Recipe.Core, eff.Times
	if eff.Path ~= "Projectile" or core.Stretch then
		return eff.Hit
	end
	local launch = eff.Mouth
	if finite(core.Rise) then
		launch = launch + UP * (core.Rise * eff.Size)
	end
	if t <= T.Travel then
		return launch
	elseif t >= T.Impact then
		return eff.Hit
	end
	local u = seg(t, T.Travel, T.Impact)
	local arc = (finite(core.Rise) and 0 or 0.5) * eff.Size * sin(pi * u)
	return launch:Lerp(eff.Hit, u) + UP * arc
end

----------------------------------------------------------------------
-- Solid pieces (cores, rings, meshes, the signature actor): MOVE[...](eff, it, t) -> CFrame, scale (Vector3, x the
-- piece's base size x it.S), transparency; nil = hidden
----------------------------------------------------------------------
local MOVE = {}

local function fadeTo(it, f)
	return it.Trans + (1 - it.Trans) * f
end

-- (Task 11d) away from the viewer: the camera's look direction (flattened when `flatOnly`: a direction along the
-- floor), or `fallback` with no camera / a camera looking straight down. Called per rim piece per frame (Task 11d
-- review I1): no closure, no pcall (reading cam.CFrame cannot throw)
local function viewBack(fallback, flatOnly)
	local cam = Workspace.CurrentCamera
	if cam then
		local lv = cam.CFrame.LookVector
		if flatOnly then
			lv = flat(lv)
		end
		if lv.Magnitude > 0.2 then
			return lv.Unit
		end
	end
	return fallback
end

MOVE.Projectile = function(eff, it, t)
	local T, core = eff.Times, eff.Recipe.Core
	local appear
	if it.Charged then -- the Blast orb grows above the pet through the charge
		appear = outBack(seg(t, 0, max(0.12, T.Release))) * (1 + 0.06 * sin(t * 30) * (1 - seg(t, T.Release - 0.05, T.Release)))
	else
		appear = outBack(seg(t, T.Release, T.Release + 0.08))
	end
	if appear <= 0 then
		return nil
	end
	-- (a basic ranged shot bursts into its explosion at once: Task 9 Studio, Water's orb lingering 0.2 s on the target,
	-- swelling, read as a bubble round it)
	local pop = eff.Recipe.Beats.MinTravel and seg(t, T.Impact, T.Impact + 0.08) or seg(t, T.Impact, T.Linger + 0.05)
	local pos = eff.CorePos
	local look = eff.Hit - pos
	if look.Magnitude < 0.05 then
		look = eff.Dir
	end
	local cf = face(pos, look)
	if core.Spin then
		cf = cf * CFrame.Angles(0, 0, t * 14)
	end
	if it.Role == "Twin" then
		cf = cf * CFrame.Angles(0, 0, pi / 2 + t * 6)
	end
	return cf, (it.Shape or ONE) * (appear * (1 + 0.5 * outCubic(pop))), fadeTo(it, smooth(pop))
end

MOVE.Stretch = function(eff, it, t)
	local T = eff.Times
	local p0 = eff.Mouth
	local p1 = it.Line and (eff.S + eff.Dir * eff.Reach + UP * 0.25) or eff.Hit
	local d = p1 - p0
	local L = d.Magnitude
	local grow = outCubic(seg(t, T.Travel - 0.02, T.Travel + max(0.08, T.Impact - T.Travel)))
	if L < 0.1 or grow <= 0 then
		return nil
	end
	local out = seg(t, T.Linger, eff.TailAt)
	local len = L * grow
	local th = (it.Thick or 1) * (1 + 0.1 * sin(t * 45)) * max(0.05, 1 - smooth(out))
	if it.Segs then
		-- (Studio findings round: Cloud Breath) the grown beam cut in Segs lengths, a Gap share of each left open; the
		-- gaps drift down the beam (the breath flows) and each segment's girth flickers on its own
		-- (Task 11c, review I1 + Studio R2: drifting Segs pieces left the mouth end empty for up to a third of the beam, then
		-- all snapped back a length at the wrap: two boxes with a hole) Segs + 1 pieces, piece Seg starting one length
		-- behind the mouth, each clipped to the beam: one enters at the mouth as another leaves at the target, so the
		-- mouth is always covered, the pattern is the same at the wrap and the only openings are the Gap shares
		local sl = len / it.Segs
		local start = (it.Seg - 2 + (t * 1.6) % 1) * sl
		local s0, s1 = max(0, start), min(len, start + sl * (1 - it.Gap))
		local pl = s1 - s0
		if pl < 0.05 then
			return nil
		end
		local c = p0 + d.Unit * (s0 + pl / 2)
		local tk = th * (0.85 + 0.15 * sin(t * 37 + it.Seg * 2.1))
		return face(c, d), V3(tk, tk, pl / max(0.01, it.Base.Z * it.S)), fadeTo(it, smooth(out) * 0.6)
	end
	local c = p0 + d.Unit * (len / 2)
	return face(c, d), V3(th, th, len / max(0.01, it.Base.Z * it.S)), fadeTo(it, smooth(out) * 0.6)
end

MOVE.Swipe = function(eff, it, t)
	local T = eff.Times
	local t0 = T.Release + (it.Delay or 0)
	local appear = outBack(seg(t, t0, t0 + 0.08))
	if appear <= 0 then
		return nil
	end
	local u = outCubic(seg(t, t0, T.Impact + 0.05))
	local fade = smooth(seg(t, T.Impact + 0.03, it.T1))
	local pos = eff.Hit + UP * (0.9 * eff.Size) - eff.Dir * ((1.0 - 1.4 * u) * eff.Size)
	local yaw = (it.Mirror and -1 or 1) * (0.95 - 1.9 * u)
	local cf = face(pos, eff.Dir) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, it.Tilt or 0.55)
	return cf, (it.Shape or ONE) * (appear * (1 + 0.18 * fade)), fadeTo(it, fade)
end

-- erupts from the ground (spikes, roots, the cage, lava spikes), holds, sinks and fades
MOVE.Rise = function(eff, it, t)
	if t < it.TR then
		return nil
	end
	local base = groundOf(eff, anchorPoint(eff, it))
	local h = it.Base.Y * it.S
	local r = outBack(seg(t, it.TR, it.TR + 0.13))
	local sink = smooth(seg(t, it.TS, it.T1))
	local y = h * (r - 0.5) - h * 0.7 * sink
	return CFrame.new(base + UP * y) * (it.Rot or CFrame.new()), ONE, fadeTo(it, sink)
end

-- expands flat on the ground (shockwave, nova, slam ring) or round (the Blast dome)
MOVE.Ring = function(eff, it, t)
	if t < it.T0 then
		return nil
	end
	local p = anchorPoint(eff, it)
	if it.Flat then
		p = groundOf(eff, p) + UP * 0.1
	end
	local g = it.From + (it.To - it.From) * outCubic(seg(t, it.T0, it.TG))
	local fade = smooth(seg(t, it.TF, it.T1))
	if it.Thin then -- (attack effects, review) wider, not taller: a thin line on the floor, however far it runs
		return CFrame.new(p), V3(g, min(g, 1), g), fadeTo(it, fade)
	end
	if it.Face then -- stood up across the attack's direction (the flat XZ ring turned to face eff.Dir)
		return face(p, eff.Dir) * CFrame.Angles(pi / 2, 0, 0), ONE * g, fadeTo(it, fade)
	end
	return CFrame.new(p) * CFrame.Angles(0, t * (it.Spin or 0), 0), ONE * g, fadeTo(it, fade)
end

-- a bubble / disc around an ally: pops in, ripples at the impact, fades out
MOVE.Shell = function(eff, it, t)
	local a = outBack(seg(t, it.T0, it.T0 + 0.2))
	if t < it.T0 or a <= 0 then
		return nil
	end
	local T = eff.Times
	local p = anchorPoint(eff, it)
	local ripple = 1 + 0.08 * sin(pi * seg(t, T.Impact, T.Impact + 0.3))
	local fade = smooth(seg(t, it.TF, it.T1))
	p = p - UP * (it.Sink or 0) -- (Task 11c I3: a squat pet's dome is sunk so its top stays under the name tag)
	local cf = it.Disc and face(p, eff.Dir) or (CFrame.new(p) * CFrame.Angles(0, t * 0.8, 0))
	return cf, ONE * (a * ripple * (it.Fit or 1)), fadeTo(it, fade)
end

-- (Studio findings round) the Shield dome round a pet fits it: radius core.Fit x the pet's half-width, at most
-- SHELL_APART x the distance to the nearest other ally (one dome each, never one blob) and its top at most TopClear
-- studs over the pet's head (the name tag stays clear); never smaller than the pet's own half-width (a clumped pair
-- may just touch rather than shrink into their bodies). (Task 11c, review I3: on a pet wider than tall the TopClear
-- cap won and the dome sat inside its body) the radius stays >= the half-width and the dome is SUNK by what its top
-- would pass the TopClear line (half in the floor: a squat pet's dome reads fine). `side` = the pet ({ Model }),
-- `others` = the other allies' points (eff.T with `skip` left out; nil: none, the ShieldHit's victim alone).
-- -> it.S multiplier, sink (studs) | nil when the pet has no model in the game (the caller's fallback)
local function fitFor(side, others, skip, base, s, core)
	local m = side and side.Model
	if not (m and m.Parent and finite(core.Fit)) then
		return nil
	end
	local ok, size = pcall(m.GetExtentsSize, m)
	local okP, piv = pcall(m.GetPivot, m)
	if not (ok and typeof(size) == "Vector3" and okP and typeof(piv) == "CFrame") then
		return nil
	end
	local half = max(size.X, size.Z) / 2
	local top = (finite(core.TopClear) and core.TopClear or 0.3) + size.Y / 2 -- (the pivot: the pet's middle)
	local r = min(core.Fit * half, max(top, half)) -- (round when it fits under the tag; never inside the body)
	local p = piv.Position
	for j, q in ipairs(others or {}) do
		if j ~= skip and j <= K.MAX_ALLIES then
			local d = flat(q - p).Magnitude
			if d > 0.5 then
				r = min(r, K.SHELL_APART * d)
			end
		end
	end
	r = max(0.6, half, r) -- (Gemini: clumped pets never get a dome shrunk inside their body)
	return 2 * r / max(0.05, base.X * s), max(0, r - top)
end

-- the Shield dome round ally i (no ally model: SHELL_FALLBACK x the old size, not sunk) -> it.S multiplier, sink
local function shellFit(eff, i, base, s, core)
	local fit, sink = fitFor(eff.Targets[i], eff.T, i, base, s, core)
	if not fit then
		return K.SHELL_FALLBACK, 0
	end
	return fit, sink
end

-- a quick pop (the hurt flash, the KO poof)
MOVE.Pop = function(eff, it, t)
	if t < it.T0 then
		return nil
	end
	local u = seg(t, it.T0, it.T1)
	local s = it.From + (it.To - it.From) * outCubic(u)
	-- (Task 11d, review M1: the ShieldHit ripple fitted to the victim's dome sits at the dome's own centre, not 0.2 over
	-- it; the hurt flash / KO poof keep the +0.2 at the pet's chest)
	return CFrame.new(anchorPoint(eff, it) + UP * ((it.Fitted and 0 or 0.2) - (it.Sink or 0))), ONE * s, fadeTo(it, smooth(seg(u, 0.25, 1)))
end

-- the victory star: rises and spins
MOVE.Star = function(eff, it, t)
	if t < it.T0 then
		return nil
	end
	local u = seg(t, it.T0, it.T1)
	local p = eff.S + UP * (0.8 + 2.6 * outCubic(u))
	return face(p, eff.Dir) * CFrame.Angles(0, t * 6, 0), ONE * outBack(seg(u, 0, 0.2)), fadeTo(it, smooth(seg(u, 0.7, 1)))
end

-- a fanned blade flying out (the Cone element attack); Back: from the cone's end back to the pet (Maelstrom)
MOVE.Fly = function(eff, it, t)
	local T = eff.Times
	if it.Back then
		if t < T.Impact then
			return nil
		end
		local u = 1 - outCubic(seg(t, T.Impact, it.T1 - 0.1))
		local d = eff.Dir * cos(it.Ang) + eff.Right * sin(it.Ang)
		return face(eff.Mouth + d * (eff.Reach * 0.85 * u), -d), ONE * ((0.6 + 0.7 * u) * outBack(seg(t, T.Impact, T.Impact + 0.08))), fadeTo(it, smooth(seg(t, it.T1 - 0.1, it.T1)))
	end
	if t < T.Release then
		return nil
	end
	local u = outCubic(seg(t, T.Release, T.Impact))
	local d = eff.Dir * cos(it.Ang) + eff.Right * sin(it.Ang)
	local p = eff.Mouth + d * (eff.Reach * 0.85 * u)
	local fade = smooth(seg(t, T.Impact, it.T1))
	return face(p, d), ONE * ((0.6 + 0.7 * u) * outBack(seg(t, T.Release, T.Release + 0.08))), fadeTo(it, fade)
end

-- a piece of the Storm special's rain: falls from the cloud, pops on landing (round its own target `Tgt` when the core
-- spreads the rain over the enemies in the Storm zone, else round the hit point)
MOVE.Fall = function(eff, it, t)
	if t < it.TR then
		return nil
	end
	local base = (it.Tgt and eff.T[it.Tgt]) or eff.Hit
	local land = groundOf(eff, base + eff.Right * it.OffR + eff.Dir * it.OffD) + UP * 0.3
	-- (Studio findings round) out of the low cloud (eff.CloudLift: its Height over the hit point) when it has one
	local top = land + UP * (eff.CloudLift and (eff.Drop + eff.CloudLift + 0.3) or (K.ABOVE * eff.Size + 2))
	local over, lifted = overOf(eff)
	if lifted then -- (review fix) over a big body the cloud hangs over its box top: the rain starts there
		top = V3(top.X, over.Y + (eff.CloudLift and (eff.CloudLift + 0.3) or (K.ABOVE * eff.Size + 2)), top.Z)
	end
	local u = seg(t, it.TR, it.TR + it.Drop)
	local fade = seg(t, it.TR + it.Drop, it.TR + it.Drop + 0.15)
	if fade >= 1 then
		return nil
	end
	return face(top:Lerp(land, u * u), V3(0, -1, 0)), ONE * (1 + 0.4 * fade), fadeTo(it, fade)
end

-- the Frost alive detail: shards lying around the target visibly melt
MOVE.Melt = function(eff, it, t)
	if t < it.T0 then
		return nil
	end
	local u = seg(t, it.T0, it.T1)
	local p = groundOf(eff, anchorPoint(eff, it)) + UP * (0.15 * it.S)
	local sv = V3(1 - 0.25 * u, max(0.05, 1 - 0.85 * u), 1 - 0.25 * u) * outBack(seg(u, 0, 0.12))
	return CFrame.new(p) * it.Rot, sv, fadeTo(it, smooth(seg(u, 0.45, 1)))
end

-- the Earth alive detail: chunks scatter and bounce once
MOVE.Bounce = function(eff, it, t)
	if t < it.T0 then
		return nil
	end
	local q = t - it.T0
	local g = 30
	local tb = 2 * it.VY / g
	local y
	if q < tb then
		y = it.VY * q - 0.5 * g * q * q
	else
		local q2 = q - tb
		y = max(0, it.VY * 0.4 * q2 - 0.5 * g * q2 * q2)
	end
	local out = eff.Right * cos(it.Ang) + eff.Dir * sin(it.Ang)
	local p = groundOf(eff, eff.Hit) + out * (0.4 + it.VH * min(q, tb * 1.4)) + UP * (y + 0.3 * it.S)
	return CFrame.new(p) * CFrame.Angles(q * it.SX, q * it.SY, 0), ONE, fadeTo(it, smooth(seg(t, it.T1 - 0.25, it.T1)))
end

-- the middle of the allies a support special lands on (the caster's spot without any)
local function alliesCentre(eff)
	local n = min(#eff.T, K.MAX_ALLIES)
	if n < 1 then
		return eff.S
	end
	local sum = V3(0, 0, 0)
	for i = 1, n do
		sum = sum + eff.T[i]
	end
	return sum / n
end

-- the enemy group a zone special lands on (Task 11 fix round 1: Obsidian's sweep over the enemies in its Storm zone)
-- -> its middle, its long axis (flat: the line through the two targets farthest apart, turned to run along the caster's right; the caster's right
-- itself while they stand within a stud of each other) and the targets' extent along it (lo <= 0 <= hi, from the middle).
-- `fixed` (fix round 2, M7): this axis instead (the Sweep freezes it when its pass starts); the middle and the extent
-- still follow the targets along it
local function fieldLine(eff, fixed)
	local n = #eff.T
	if n < 1 then
		return eff.Hit, fixed or eff.Right, 0, 0
	end
	local c = V3(0, 0, 0)
	for i = 1, n do
		c = c + eff.T[i]
	end
	c = c / n
	local ax = fixed
	if not ax then
		local far = 1
		ax = eff.Right
		for i = 1, n - 1 do
			for j = i + 1, n do
				local d = flat(eff.T[j] - eff.T[i])
				local m = d.Magnitude
				if m > far then
					far, ax = m, d / m
				end
			end
		end
		local side = ax:Dot(eff.Right)
		if side < -0.05 or (side <= 0.05 and ax:Dot(eff.Dir) < 0) then
			ax = -ax
		end
	end
	local lo, hi = 0, 0
	for i = 1, n do
		local k = (eff.T[i] - c):Dot(ax)
		lo, hi = min(lo, k), max(hi, k)
	end
	return c, ax, lo, hi
end
AttackFx._FieldLine = fieldLine -- (tests)

-- the signature actor (a vfx_sig_* piece, Task 11) by its Motion:
-- (In battle the charge is cut to the render lead, ~0.1-0.45 s: every motion keeps its identity AFTER the impact too.)
--   SpiralUp       (Cloudy Dragon) spirals up round the caster through the charge, dives along the beam onto the hit,
--                  then coils once round the target, rising, as it fades
--   ChargeThrough  (Stormfang) from the mouth through the target and 3 studs past it, over the leap
--   Eclipse        (Eclipse Dragon) hangs over the target through the charge, turning; at the impact it drops onto the
--                  target, lies flat on the floor and bursts outward as it fades (a ring on the ground, never a wall)
--                  A MISSED Eclipse Nova (fix round 1, M3): the sun never drops; it fades where it hangs at the impact
--   Sweep          (Obsidian Phoenix; ruling: its Storm hits every enemy IN ITS ZONE, so no single-target dive) waits
--                  over the near end of the enemy line, wings folded; then a low swooping pass ACROSS the whole line,
--                  end to end and past both ends (fieldLine), wings open, its Echo copies trailing as black-flame wings;
--                  the pass is centred on the impact (a battle's cut charge starts it at the first frame instead), as
--                  the dark fire rains on every target; then it climbs out over the far end and fades (Task 11c: all of it
--                  inside the Storm's zone)
--   WishRise       (Starlight Unicorn) rises from the caster (over >= 0.45 s) to high over the allies' middle, swaying
--   Seal           (Sunbeam Bear) lies flat under each ally, turning and pulsing (a sun seal under the bubble)
--   FoxFire        (Phantom Kitsune) the orbs circle the caster through the charge, then fly out and circle their allies
--   RiseRoar       (Hydralotl) rises from the floor behind the caster in a fan and lunges forward once risen
--   MoonRise       (Twilight Dragon) a crescent dusk moon rises to the storm cloud's height just behind the target,
--                  upright, rocking
--   RingRise       (Magma Cub) MOVE.Rise in a ring round the target (set in buildActor); Rise (and unknown motions):
--                  comes up into place, holds, fades
--   PackCharge     (evolved forms: Stormfang's wolves, a Pounce's orbs) on eff.Line, frozen at the Play: from its start through the target (FHit along it, at TA) to its end (at TE), on the
--                  floor, Across to the side but closing on the target as it passes
--   Shatter        (evolved forms) what broke flies apart round the hit: a cage, the glacier, the foxfire
MOVE.Actor = function(eff, it, t)
	local T = eff.Times
	if t < it.T0 then
		return nil
	end
	local m = it.Motion
	local u = seg(t, it.T0, it.T1)
	local fade = smooth(seg(t, it.TF, it.T1))
	if m == "SpiralUp" then
		local top = eff.S + UP * (1 + 4.5 * eff.Size)
		local dive = it.Dive or T.Travel
		local p, look
		if t < dive then
			local v = seg(t, it.T0, dive)
			local a = v * TAU * 1.5 + it.I
			p = eff.S + UP * (1 + 4.5 * eff.Size * smooth(v)) + (eff.Right * cos(a) + eff.Dir * sin(a)) * (1.8 * eff.Size * (1 - 0.6 * v))
			look = eff.Right * -sin(a) + eff.Dir * cos(a) + UP * 0.6
		elseif t >= T.Impact then -- (the coil: once round the target, rising, the radius opening from the dive's end)
			local v = seg(t, T.Impact, it.T1)
			local a = v * TAU * 1.25 - pi / 2
			local r = 1.6 * eff.Size * smooth(min(1, v * 3))
			p = eff.Hit + UP * (0.5 + 2.5 * eff.Size * v) + (eff.Right * cos(a) + eff.Dir * sin(a)) * r
			look = eff.Right * -sin(a) + eff.Dir * cos(a) + UP * 0.5
		else
			local v = seg(t, dive, T.Impact)
			p = top:Lerp(eff.Hit + UP * 0.5, v * v)
			look = eff.Hit - top
		end
		return face(p, look), ONE * outBack(seg(t, it.T0, it.T0 + 0.2)), fadeTo(it, fade)
	elseif m == "ChargeThrough" then
		local p = eff.Mouth:Lerp(eff.Hit + eff.Dir * 3, outCubic(u))
		return face(p, eff.Dir), ONE * outBack(seg(u, 0, 0.15)), fadeTo(it, fade)
	elseif m == "PackCharge" then
		local L = eff.Line
		local f
		if t < it.TA then
			local v = seg(t, it.T0, it.TA)
			f = it.FHit * v * v -- (out of a standing start)
		else
			f = it.FHit + (1 - it.FHit) * seg(t, it.TA, it.TE)
		end
		local lat = it.Across * (K.PACK_NEAR + (1 - K.PACK_NEAR) * min(1, abs(f - it.FHit) / K.PACK_CLOSE))
		local p = L.From + L.Dir * (f * L.Length) + L.Right * lat
		return face(V3(p.X, groundOf(eff, p).Y + it.Base.Y * it.S / 2, p.Z), L.Dir), ONE * outBack(seg(t, it.T0, it.T0 + 0.12)), fadeTo(it, fade)
	elseif m == "Shatter" then
		local v = outCubic(u)
		local out = V3(cos(it.Ang), 0, sin(it.Ang))
		local p = eff.Hit + out * (it.Rad * v) + UP * (eff.Size * (0.5 + 1.2 * sin(pi * v)))
		return face(p, out) * CFrame.Angles(t * 5, 0, t * 3), ONE * outBack(seg(u, 0, 0.12)), fadeTo(it, fade)
	elseif m == "Eclipse" then
		local spin = CFrame.Angles(0, 0, t * 1.4)
		local hang = face(overOf(eff) + UP * (4.2 * eff.Size), -eff.Dir) * spin
		if t < T.Impact then
			return hang, ONE * (outBack(seg(t, it.T0, it.T0 + 0.35)) * (1 + 0.04 * sin(t * 9))), fadeTo(it, 0)
		end
		if eff.Miss then -- (M3: a miss reads as a miss: no drop, no burst; the sun fades where it hangs)
			return hang, ONE, fadeTo(it, smooth(seg(t, T.Impact, T.Impact + 0.3)))
		end
		local v = seg(t, T.Impact, T.Impact + 0.12)
		local flat = CFrame.new(groundOf(eff, eff.Hit) + UP * 0.15) * CFrame.Angles(pi / 2, 0, 0) * spin
		local w = seg(t, T.Impact + 0.08, it.T1)
		return hang:Lerp(flat, v * v), ONE * (1 + 1.3 * outCubic(w)), fadeTo(it, smooth(w))
	elseif m == "Sweep" then
		-- (fix round 2, M7) the axis is frozen on the effect when the pass starts (TP0; the bird, its rim and its echoes
		-- share it): targets moving mid-pass can no longer swap its ends and jump the bird across the line
		local c, ax, lo, hi
		if t >= it.TP0 then
			if not eff.SweepAx then
				local _, a0 = fieldLine(eff)
				eff.SweepAx = a0
			end
			c, ax, lo, hi = fieldLine(eff, eff.SweepAx)
		else
			c, ax, lo, hi = fieldLine(eff)
		end
		-- (Task 11c, Studio round 2, R1: 2.5 x size past each end, then flying on away along the axis and up, the bird hung
		-- ~15 studs off the target over the NPCs as a giant magenta shape) just past the ends (SWEEP_EDGE), a lower climb,
		-- and it climbs out where the pass ends, not away: the whole sweep stays inside the Storm's zone
		local edge = K.SWEEP_EDGE * eff.Size
		local a, b = c + ax * (lo - edge), c + ax * (hi + edge)
		local low, rise = 1 + 0.8 * eff.Size, 1.6 * eff.Size -- (over the targets' middle: the pass's lowest / its climb at the ends)
		local p, dir, k
		if t < it.TP0 then -- waiting high over the near end, wings folded
			k = -1
			p = a + UP * (low + rise + 0.3 * sin(t * 4))
			dir = ax
		elseif t <= it.TP1 then -- the pass: swoops down onto the line, skims it end to end, climbs out past the far end
			local v = seg(t, it.TP0, it.TP1)
			k = 2 * v - 1
			p = a:Lerp(b, v) + UP * (low + rise * k * k)
			dir = (b - a) + UP * (4 * rise * k)
		else -- up out of the far end as it fades (Task 11c R1: no longer away along the axis, out of the zone)
			local w = t - it.TP1
			k = 1
			p = b + UP * (low + rise + 2 * eff.Size * w)
			dir = ax + UP * 0.6
		end
		local open = 0.3 + 0.7 * outBack(seg(t, it.TP0 - 0.16, it.TP0)) -- (the wings snap open as it dives in)
		local flap = 1 + 0.08 * sin(t * 13)
		return face(p, dir) * CFrame.Angles(0, 0, 0.25 * k), V3(open * flap, 1, 1) * outBack(seg(t, it.T0, it.T0 + 0.25)), fadeTo(it, fade)
	elseif m == "WishRise" then
		-- (Studio findings round: the star rose through the player's avatar) pushed Forward toward the allies' side and
		-- kept Clear (+ its own half-width) away from the caster and the player's character the whole way
		local mid = alliesCentre(eff)
		local fwd = flat(mid - eff.S)
		fwd = (fwd.Magnitude > 0.5) and fwd.Unit or eff.Dir
		local top = mid + fwd * ((it.Forward or 0) * eff.Size) + UP * (K.ABOVE * 0.8 * eff.Size)
		local p = (eff.S + UP):Lerp(top, outCubic(seg(t, it.T0, max(T.Travel, it.T0 + 0.45)))) + UP * (0.25 * sin(t * 3))
		if it.ClearK then
			it.Sides = it.Sides or {} -- (Task 11c I2: per piece; its rim / echo copies keep their own, made the same way)
			p = keepClear(eff, p, it.ClearK * eff.Size + K.BODY_R + max(it.Base.X, it.Base.Z) * it.S / 2, fwd, it.Sides)
		end
		local a = 0.6 * sin(t * 1.5)
		return face(p, -(eff.Dir * cos(a) + eff.Right * sin(a))), ONE * outBack(seg(t, it.T0, it.T0 + 0.3)), fadeTo(it, fade)
	elseif m == "Seal" then
		local p = groundOf(eff, anchorPoint(eff, it)) + UP * 0.12
		local pulse = 1 + 0.06 * sin(t * 7)
		return CFrame.new(p) * CFrame.Angles(pi / 2, 0, 0) * CFrame.Angles(0, 0, t * 0.9), ONE * (outBack(seg(t, it.T0, it.T0 + 0.25)) * pulse), fadeTo(it, fade)
	elseif m == "FoxFire" then
		local a1 = it.I / it.N * TAU + t * 4
		local p1 = eff.S + V3(cos(a1) * 1.5 * eff.Size, 0.8 * eff.Size + 0.3 * sin(t * 5 + it.I), sin(a1) * 1.5 * eff.Size)
		local a2 = it.J / it.M * TAU + t * 3
		local p2 = (eff.T[it.Ally] or eff.S) + V3(cos(a2) * 1.6 * eff.Size, 0.3 * sin(t * 4 + it.I), sin(a2) * 1.6 * eff.Size)
		local v = smooth(seg(t, T.Travel, T.Travel + 0.3))
		return CFrame.new(p1:Lerp(p2, v)) * CFrame.Angles(0, -(a1 * (1 - v) + a2 * v), 0), ONE * outBack(seg(t, it.T0, it.T0 + 0.2)), fadeTo(it, fade)
	elseif m == "RiseRoar" then
		-- (Task 11d, Studio round 3, S5: rooted Behind along -eff.Dir (a Rally's Dir points at its first ally, the caster
		-- itself in /fx: world -Z) and 7-8 studs tall, the necks stood in front of the Hydralotl and over its name tag) rooted
		-- it.Back studs past the caster's body AWAY from the viewer (the camera's flat look, frozen per effect; no camera:
		-- behind the caster, -Dir), the fan across that; scaled (it.Fit, the rim copy alike) so the tallest head's top stays
		-- SERPENT_CLEAR at most over the caster's head, its rise overshoot and the rim included
		if not eff.RoarBack then
			eff.RoarBack = viewBack(-eff.Dir, true)
		end
		local back = eff.RoarBack
		if not it.Fit then
			it.Fit = min(1, (it.HMax or huge) / max(0.05, it.Base.Y * (it.STop or it.S) * 1.15))
		end
		local f = it.Fit
		local spread = 0.8 * it.Base.X * (it.STop or it.S) / 1.15 * f -- (the fan's spacing: 0.8 x a side head's width)
		local base = groundOf(eff, eff.S) + back * (it.Back or (K.BEHIND * eff.Size)) + back:Cross(UP) * ((it.FanK or 0) * spread)
		local h = it.Base.Y * it.S * f
		local r = outBack(seg(t, it.T0, it.T0 + 0.3))
		local nodAt = max(T.Release, it.T0 + 0.3) -- (in battle the release comes at once: the lunge waits for the rise)
		local nod = sin(pi * seg(t, nodAt, nodAt + 0.35))
		local yaw = it.Yaw or 0
		local look = eff.Dir * cos(yaw) + eff.Right * sin(yaw)
		return face(base + UP * (h * (r - 0.5)) + look * (0.8 * nod), look) * CFrame.Angles(-0.35 * nod, 0, 0), ONE * f, fadeTo(it, fade)
	elseif m == "MoonRise" then
		-- (the crescent mesh lies flat (thin along Y): a quarter turn about X stands it up, its face to the caster)
		-- (Task 11c, Studio round 2, R3 + Ruling 20: at ABOVE x 1.15 x size (~9 studs) it read as a far-off arch) it rises to
		-- the storm cloud's height over the hit (eff.CloudLift, else MOON_LIFT), MOON_BACK x size just behind the target
		-- (Task 11d, Studio round 3, S4: at the cloud's own height it was lost inside the puffs) its lowest point MOON_GAP
		-- over the cloud's top (eff.CloudTop: the puffs' height + half their size), its centre half its standing height
		-- (the mesh's Z) over that
		local lift = eff.CloudLift or K.MOON_LIFT
		if eff.CloudTop then
			lift = eff.CloudTop + K.MOON_GAP + 0.5 * it.Base.Z * it.S
		end
		local p = overOf(eff) + UP * (lift - 2 * (1 - outCubic(seg(t, it.T0, it.T0 + 0.5)))) + eff.Dir * (K.MOON_BACK * eff.Size)
		return face(p, -eff.Dir) * CFrame.Angles(0, 0, 0.15 * sin(t * 1.6)) * CFrame.Angles(pi / 2, 0, 0), ONE * outBack(seg(t, it.T0, it.T0 + 0.3)), fadeTo(it, fade)
	end
	local p = anchorPoint(eff, it) - UP * (3 * (1 - outCubic(seg(t, it.T0, it.T0 + 0.5))))
	return face(p, -eff.Dir), ONE * outBack(seg(t, it.T0, it.T0 + 0.25)), fadeTo(it, fade)
end

-- an actor's rim (Task 11): the same piece a little bigger, just behind it, in a glowing colour: the black sun's
-- corona, the dark phoenix's magenta edge, the serpents' glitch-pink outline. (Task 11d, Fable review I1: pushed along
-- eff.Dir it sat behind the body only seen from the caster's side; from the target's side (the /fx camera, an enemy's
-- Obsidian in a battle) the see-through magenta copy covered the black bird) pushed along the camera's look, so it is
-- behind the body for whoever watches (no camera: eff.Dir, as before)
MOVE.ActorRim = function(eff, it, t)
	local cf, sv, tr = MOVE.Actor(eff, it, t)
	if not cf then
		return nil
	end
	return cf + viewBack(eff.Dir) * (it.RimBack * it.S), sv * it.RimScale, tr
end

-- an actor's echo (fix round 1): the same piece where it was Lag seconds ago, a little smaller, in its dimmer flame
-- colour: Obsidian's black-flame wings trailing the sweep (only once the pass has begun: never stacked on the waiting bird)
MOVE.ActorEcho = function(eff, it, t)
	if t < (it.TP0 or it.T0) + it.Lag then
		return nil
	end
	local cf, sv, tr = MOVE.Actor(eff, it, t - it.Lag)
	if not cf then
		return nil
	end
	return cf, sv * it.EchoScale, tr
end

----------------------------------------------------------------------
-- Drawing the items every frame
----------------------------------------------------------------------
local DRAW = {}

function DRAW.Solid(eff, it, t)
	local part = it.Kit.Root
	if t < it.T0 or t >= it.T1 then
		if part.Transparency < 1 then
			part.Transparency = 1
		end
		return
	end
	local cf, sv, tr = it.Move(eff, it, t)
	if not cf or tr >= 0.995 then
		if part.Transparency < 1 then
			part.Transparency = 1
		end
		return
	end
	local b, s = it.Base, it.S
	part.Size = V3(max(0.05, b.X * sv.X * s), max(0.05, b.Y * sv.Y * s), max(0.05, b.Z * sv.Z * s))
	part.CFrame = cf
	part.Transparency = tr
	if it.Shift then -- the Secret core's colour-shifting rim: the shell breathing into the rim colour
		-- (Task 9 Studio: breathing from WHITE, every band 4 shell was drawn 50-80 % white whatever its colour: the white
		-- ball / white sheet; it breathes from its own colour now, the white plasma is the heart inside)
		local h, sat, v = it.Shift:ToHSV()
		local own = typeof(it.Color) == "Color3" and it.Color or WHITE
		part.Color = own:Lerp(Color3.fromHSV((h + 0.08 * sin(t * 5)) % 1, sat, v), 0.3 + 0.2 * sin(t * 9))
	end
end

local function emitAt(it, p, n)
	it.Kit.Root.CFrame = CFrame.new(p)
	it.Kit.Em:Emit(n)
end

function DRAW.Emitter(eff, it, t)
	if t < it.T0 then
		return
	end
	local pts = it.Pts
	if it.Mode == "Burst" then
		if it.Fired then
			return
		end
		it.Fired = true
		local n = atPoints(eff, it.At, pts)
		local each = max(1, floor(it.Count / sqrt(n) + 0.5))
		for i = 1, n do
			local p = pts[i]
			if it.Flat then
				-- (At "Ground" is already on the floor)
				p = ((it.At == "Ground") and p or groundOf(eff, p)) + UP * (0.04 + 0.01 * it.Index)
			end
			emitAt(it, p + UP * (it.Lift or 0), each)
		end
		return
	end
	if t > it.T1 + 1e-6 then
		return
	end
	it.Acc = it.Acc + it.Rate * eff.Dt
	local k = floor(it.Acc)
	if k <= 0 then
		return
	end
	it.Acc = it.Acc - k
	if it.Stream == "Along" then -- (Task 10) one particle at each of k points spread along the grown beam
		local p0, p1 = eff.Mouth, eff.Hit
		local reach = outCubic(seg(t, eff.Times.Travel, eff.Times.Impact))
		for i = 1, min(k, 6) do
			it.Seq = (it.Seq or 0) + 1
			local f = (0.08 + 0.9 * hash(it.Seq, 51)) * reach
			local j = (hash(it.Seq, 52) - 0.5) * 0.5 * eff.Size
			emitAt(it, p0:Lerp(p1, f) + eff.Right * j + UP * ((hash(it.Seq, 53) - 0.5) * 0.4 * eff.Size), 1)
		end
		return
	end
	local n = atPoints(eff, it.At, pts)
	local u = seg(t, it.T0, it.T1)
	for i = 1, n do
		local p = pts[i]
		if it.Stream == "Spiral" then
			local a = t * 8 + i * 2.1
			p = p + V3(cos(a) * 1.2 * eff.Size, (u * 2.2 - 0.6) * eff.Size, sin(a) * 1.2 * eff.Size)
		elseif it.Stream == "Alive" then
			p = groundOf(eff, p) + UP * 0.2
		end
		emitAt(it, p + UP * (it.Lift or 0), max(1, floor(k / sqrt(n) + 0.5)))
	end
end

-- beam end points by mode; returns p0, p1, axis (the curve direction) or nil
local BEAM = {}

function BEAM.Path(eff, it, t)
	local p0, p1 = eff.Mouth, eff.Hit
	local grow = outCubic(seg(t, it.T0, it.T0 + max(0.06, (eff.Times.Impact - it.T0) * 0.5)))
	-- (Task 9 Studio, Storm s3: grown on its own clock toward the target's pivot, the bolt raced ahead of the shot, low
	-- over the floor: on a flying shot the strip runs from the mouth to the shot itself, then to the hit)
	local core = eff.Recipe and eff.Recipe.Core
	if eff.Path == "Projectile" and eff.CorePos and not (core and core.Stretch) then
		p1 = (t < eff.Times.Impact) and eff.CorePos or eff.Hit
		grow = 1
	end
	if it.I > 1 or it.Jitter then -- extra bolts jump about the main one
		local f = floor(t * 20) + it.I * 7
		local j = (hash(f, 1) - 0.5) * 1.6 * eff.Size
		local k = (hash(f, 2) - 0.5) * 1.2 * eff.Size
		p0 = p0 + eff.Right * j * 0.4
		p1 = p1 + eff.Right * j + UP * k
	end
	return p0, p0:Lerp(p1, grow), eff.Right
end

function BEAM.Arc(eff, it, t)
	local f = floor(t * 14) + it.I * 13
	local a = hash(f, 3) * TAU
	local c = eff.Hit + V3(cos(a) * 1.2 * eff.Size, (hash(f, 4) - 0.3) * 1.4 * eff.Size, sin(a) * 1.2 * eff.Size)
	local b = hash(f, 5) * TAU
	return c, c + V3(cos(b), hash(f, 6) - 0.5, sin(b)) * (1.6 * eff.Size), eff.Right
end

function BEAM.Crescent(eff, it, t)
	local u = outCubic(seg(t, it.T0, it.T0 + 0.18))
	local tilt = 1.5 - 1.2 * u
	local c = eff.Hit + UP * (0.8 * eff.Size)
	return c + eff.Right * (1.8 * eff.Size) + UP * (tilt * eff.Size * 0.5), c - eff.Right * (1.8 * eff.Size) - UP * (tilt * eff.Size * 0.3), eff.Dir
end

function BEAM.Strike(eff, it, t)
	local f = floor(t * 12) + it.I * 31
	if hash(f, 7) < 0.4 then
		return nil
	end
	local a = hash(it.I + floor(t * 3), 8) * TAU
	local g = groundOf(eff, eff.Hit) + V3(cos(a), 0, sin(a)) * ((1.6 + 1.4 * hash(it.I, 9)) * eff.Size)
	return g + UP * (6 * eff.Size) + V3(hash(f, 10) - 0.5, 0, hash(f, 11) - 0.5), g, eff.Right
end

-- the i-th star of the Celestial constellation around the hit point
local function constellationStar(eff, i)
	local a = hash(i, 12) * TAU
	local r = (1.4 + hash(i, 13)) * eff.Size
	return eff.Hit + V3(cos(a) * r, (1 + 1.6 * hash(i, 14)) * eff.Size, sin(a) * r)
end

function BEAM.Connect(eff, it, t)
	local p0, p1 = constellationStar(eff, it.I), constellationStar(eff, it.I + 1)
	local u = seg(t, it.T0 + (it.I - 1) * 0.08, it.T0 + (it.I - 1) * 0.08 + 0.2)
	if u <= 0 then
		return nil
	end
	return p0, p0:Lerp(p1, outCubic(u)), eff.Right
end

function DRAW.Beam(eff, it, t)
	local b = it.Kit.Beam
	if t < it.T0 or t > it.T1 then
		if b.Enabled then
			b.Enabled = false
		end
		return
	end
	local p0, p1, axis = BEAM[it.Mode](eff, it, t)
	if not p0 or (p1 - p0).Magnitude < 0.05 then
		if b.Enabled then
			b.Enabled = false
		end
		return
	end
	local fwd = axis.Unit
	local upv = (p1 - p0).Unit:Cross(fwd)
	if upv.Magnitude < 1e-3 then -- the beam runs along its curve axis: any perpendicular will do
		upv = fwd:Cross((abs(fwd.Y) < 0.9) and UP or V3(1, 0, 0))
	end
	it.Kit.Root.CFrame = CFrame.fromMatrix(p0, fwd, upv.Unit)
	it.Kit.H1.CFrame = CFrame.fromMatrix(p1, fwd, upv.Unit)
	local env = outCubic(seg(t, it.T0, it.T0 + 0.06)) * (1 - smooth(seg(t, it.T1 - 0.14, it.T1)))
	if it.Flicker then
		env = env * (0.6 + 0.4 * hash(floor(t * 30), it.I))
	end
	if it.Spiral then
		local c = it.Curve * sin(t * 14 + it.I * pi)
		b.CurveSize0 = c
		b.CurveSize1 = -c
	end
	b.Width0 = max(0.01, it.Width0 * env)
	b.Width1 = max(0.01, it.Width1 * env)
	if not b.Enabled then
		b.Enabled = true
	end
end

function DRAW.Trail(eff, it, t)
	local tr = it.Kit.Trail
	if t < it.T0 then
		return
	end
	if t > it.T1 then
		if tr.Enabled then
			tr.Enabled = false
		end
		return
	end
	local p, look
	local u = seg(t, it.T0, it.T1)
	if it.Mode == "Leap" then
		if eff.Src.Model then
			-- (Task 10) the afterimages ride the leaping pet itself: its pivot carries the Strike pose (the drawn root), so
			-- the streak follows the real jump, wherever the gap-based leap lands
			p = eff.S + UP * K.LEAP_TRAIL_UP + eff.Right * it.Side
			look = eff.Dir
		else -- (no model: a scripted hop from the start point to the hit)
			local g0, g1 = it.From or eff.S, eff.Hit
			it.From = g0
			p = g0:Lerp(g1, outCubic(u)) + UP * (1.6 * eff.Size * sin(pi * u)) + eff.Right * it.Side
			look = g1 - g0
		end
	elseif it.Mode == "Wind" then
		local c = eff.T[it.Ally] or eff.S
		local a = u * TAU * 1.5 + it.Ally
		local y = u * 1.6 - 0.6
		if it.Held then -- (evolved forms) an aura's wind circles at its own speed for as long as the buff lasts, breathing up and down
			a = t * K.WIND_SPIN + it.Ally
			y = 0.5 * sin(t * 1.7)
		end
		p = c + V3(cos(a) * 1.4 * eff.Size, y * eff.Size, sin(a) * 1.4 * eff.Size)
		look = V3(-sin(a), 0, cos(a))
	else
		p = (eff.CorePos or eff.Hit) + eff.Right * it.Side
		look = eff.Hit - p
	end
	it.Kit.Root.CFrame = face(p, flat(look).Magnitude > 0.01 and look or eff.Dir)
	if not it.On then
		it.On = true
		pcall(tr.Clear, tr)
		tr.Enabled = true
	end
end

function DRAW.Light(eff, it, t)
	local l = it.Kit.Light
	if t < it.T0 or t > it.T1 then
		if l.Enabled then
			l.Enabled = false
		end
		return
	end
	local n = atPoints(eff, it.At, it.Pts)
	local p = it.Pts[1]
	if n > 1 then
		local sum = V3(0, 0, 0)
		for i = 1, n do
			sum = sum + it.Pts[i]
		end
		p = sum / n
	end
	it.Kit.Root.CFrame = CFrame.new(p + UP * 0.5)
	local b
	if it.Pulse then
		b = it.B * (0.65 + 0.35 * sin(t * 28)) * sin(pi * seg(t, it.T0, it.T1))
	else
		b = it.B * seg(t, it.T0, it.T0 + 0.04) * (1 - smooth(seg(t, it.T0 + 0.04, it.T1)))
	end
	if it.Shift then
		local h, s, v = it.Color:ToHSV()
		l.Color = Color3.fromHSV((h + t * 0.8) % 1, s, v)
	end
	l.Brightness = max(0, b)
	if not l.Enabled then
		l.Enabled = true
	end
end

function DRAW.Disc(eff, it, t)
	local d = it.Kit.Root
	if t < it.T0 or t > it.T1 then
		if d.Transparency < 1 then
			d.Transparency = 1
		end
		if it.Soft and it.Kit.Img.ImageTransparency < 1 then
			it.Kit.Img.ImageTransparency = 1
		end
		return
	end
	atPoints(eff, it.At, it.Pts)
	local p = it.Pts[1]
	if it.At ~= "Ground" then -- (At "Ground" is already on the floor)
		p = groundOf(eff, p)
	end
	p = p + UP * (0.03 + 0.008 * it.Index)
	local main = it.MainEnd or it.T1
	local g = (0.55 + 0.45 * outCubic(seg(t, it.T0, it.T0 + 0.15))) * (1 + 0.1 * seg(t, it.T0, main))
	local size = it.D * g
	d.Size = V3(0.06, size, size)
	d.CFrame = CFrame.new(p) * CFrame.Angles(0, 0, pi / 2)
	local tr
	if it.MainEnd then
		-- (attack effects, 2026-11-01) a lingering mark: down to eff.TailTrans by the end of its own time, then only fading: no pulse, no growth
		if t < main then
			tr = it.Trans + (eff.TailTrans - it.Trans) * smooth(seg(t, it.T0 + (main - it.T0) * 0.4, main))
		else
			tr = eff.TailTrans + (1 - eff.TailTrans) * seg(t, main, it.T1)
		end
	else
		tr = fadeTo(it, smooth(seg(t, it.T0 + (it.T1 - it.T0) * 0.4, it.T1)))
	end
	if it.Soft then
		it.Kit.Img.ImageTransparency = tr
	else
		d.Transparency = tr
	end
end

-- (Task 11b) the rim light on the charging pet: fades in from the charge's start (RIM_IN; a charge backdated to a
-- press keeps the strength its prediction reached), holds to the release, fades out over RIM_OUT
function DRAW.Rim(eff, it, t)
	local hl = it.Kit.Hl
	local m = eff.Src.Model
	local rel = eff.Times.Release
	local a = 0
	if m and m.Parent and t >= 0 then
		if t <= rel then
			a = smooth(t / K.RIM_IN)
		else
			a = 1 - smooth(seg(t, rel, rel + K.RIM_OUT))
		end
	end
	it.A = a
	if a <= 0.01 then
		if hl.Enabled then
			hl.Enabled = false
		end
		return
	end
	if hl.Adornee ~= m then
		hl.Adornee = m
	end
	hl.OutlineTransparency = 1 - (1 - K.RIM_OUTLINE) * a
	hl.FillTransparency = 1 - (1 - K.RIM_FILL) * a
	if not hl.Enabled then
		hl.Enabled = true
	end
end

----------------------------------------------------------------------
-- Building an effect's items
----------------------------------------------------------------------
-- (attack effects, 2026-11-01) does this layer outlive the beats in this effect? (a Linger layer of an effect with an Afterglow, or with an aura: evolved forms)
local function lingers(eff, layer)
	return layer.Linger == true and (eff.Afterglow > 0 or eff.AuraRel ~= nil)
end

-- (evolved forms) ... does it hold through this effect's aura?
local function heldByAura(eff, layer)
	return layer.Linger == true and eff.AuraRel ~= nil
end

local function beatStart(eff, beat)
	local T = eff.Times
	if beat == "Charge" then
		return 0
	end
	return T[beat] or T.Impact
end

local function beatEnd(eff, beat)
	local T = eff.Times
	if beat == "Charge" then
		return T.Release
	elseif beat == "Release" then
		return T.Travel
	elseif beat == "Travel" then
		return T.Impact
	elseif beat == "Impact" then
		return T.Linger
	end
	return eff.TailAt
end

local function addItem(eff, it)
	it.Index = #eff.Items + 1
	eff.Items[it.Index] = it
	return it
end

local function addSolid(eff, key, it)
	if eff.Cores >= AttackFx.MAX_CORES then
		return nil
	end
	local kit = take("Core", key)
	if not kit then
		return nil
	end
	eff.Cores = eff.Cores + 1
	kit.Root.Color = it.Color or WHITE
	kit.Root.Material = it.Material or Enum.Material.Neon
	kit.Root.Transparency = 1
	it.Kind = "Solid"
	it.Kit = kit
	it.Base = kit.Base
	it.Fn = DRAW.Solid
	it.S = it.S or eff.Size
	it.Trans = it.Trans or 0
	it.T0 = it.T0 or 0
	it.T1 = min(it.T1 or eff.TailAt, it.Lingers and eff.EndRel or eff.TailAt) -- (a held piece: an aura's ring)
	return addItem(eff, it)
end

-- the core of the recipe, by its Path
local function buildCore(eff)
	local r = eff.Recipe
	local core, T = r.Core, eff.Times
	local key, path = core.Key, core.Path
	if type(key) ~= "string" then
		return
	end
	local S = eff.Size * (finite(core.Scale) and core.Scale or 1)
	local mat = material(core.Material)
	local trans = finite(core.Transparency) and core.Transparency or 0
	local function look(extra)
		local it = { Color = core.Color, Material = mat, Trans = trans, S = S, Shift = core.RimShift and core.RimColor or nil }
		for k, v in pairs(extra) do
			it[k] = v
		end
		return it
	end
	local endImpact = T.Linger + 0.06
	if path == "Projectile" then
		if core.Stretch then
			local segs = (finite(core.Segments) and core.Segments >= 2) and min(4, floor(core.Segments)) or nil
			for i = 1, segs and (segs + 1) or 1 do -- (Task 11c I1: Segs + 1 pieces, MOVE.Stretch)
				-- (attack effects, 2026-11-01: the Beam runs to its real length, through the target, as wide as it hits)
				addSolid(eff, key, look({ Move = MOVE.Stretch, T0 = T.Travel - 0.02, Line = (eff.Kind == "Beam") or nil, Thick = (core.Thick or 1) * eff.WidthScale, Seg = segs and i or nil, Segs = segs, Gap = finite(core.Gap) and clamp01(core.Gap) or K.SEG_GAP }))
			end
			return
		end
		local charged = core.Grow == true or finite(core.Rise)
		local t0 = charged and 0 or T.Release
		-- core.Girth: the shot's width x (its length stays: a thick bolt, not a longer spear)
		local girth = (finite(core.Girth) and core.Girth > 0) and V3(core.Girth, core.Girth, 1) or ONE
		local main = addSolid(eff, key, look({ Move = MOVE.Projectile, T0 = t0, T1 = endImpact, Charged = charged, Shape = girth }))
		if main and core.InnerColor then -- band 2+: a hot inner core showing through
			main.Trans = max(main.Trans, 0.35)
			addSolid(eff, key, look({ Move = MOVE.Projectile, T0 = t0, T1 = endImpact, Charged = charged, Color = core.InnerColor, Material = Enum.Material.Neon, Trans = 0, Shift = false, S = S * 0.55, Shape = girth }))
		end
		if core.Upgraded then -- band 3+: fins (the twin turned a quarter)
			addSolid(eff, key, look({ Move = MOVE.Projectile, T0 = t0, T1 = endImpact, Charged = charged, Role = "Twin", Shape = V3(0.75, 0.75, 1.1) * girth, Color = core.RimColor or core.InnerColor or core.Color }))
		end
	elseif path == "Swipe" then
		local t1 = T.Linger + 0.2
		local main = addSolid(eff, key, look({ Move = MOVE.Swipe, T0 = T.Release, T1 = t1 }))
		if main and core.InnerColor then
			main.Trans = max(main.Trans, 0.3)
			addSolid(eff, key, look({ Move = MOVE.Swipe, T0 = T.Release, T1 = t1, Color = core.InnerColor, Material = Enum.Material.Neon, Trans = 0, Shift = false, Shape = V3(0.8, 0.6, 0.55) }))
		end
		if core.Upgraded then -- band 3+: a second blade, mirrored and a beat late
			addSolid(eff, key, look({ Move = MOVE.Swipe, T0 = T.Release, T1 = t1 + 0.06, Delay = 0.06, Mirror = true, Tilt = -0.55, S = S * 0.85, Color = core.RimColor or core.InnerColor or core.Color }))
		end
	elseif path == "Ground" then
		if key == "vfx_ring" then -- the Pounce slam: a ring races out over the ground
			addSolid(eff, key, look({ Move = MOVE.Ring, Flat = true, T0 = T.Impact, TG = T.Linger + 0.25, TF = T.Impact + 0.1, T1 = T.Linger + 0.45, From = 0.3, To = finite(core.Grow) and core.Grow or 3 }))
			return
		end
		local n = min(6, finite(core.Count) and core.Count or 1)
		local around = (key == "vfx_root") or n == 1
		local travel = max(0.05, T.Impact - T.Travel)
		for i = 1, n do
			local it = look({ Move = MOVE.Rise, T0 = 0, TS = T.Linger + (eff.TailAt - T.Linger) * 0.3, T1 = eff.TailAt })
			if around then
				local a = (i - 1) / n * TAU + hash(i, 21)
				local rad = (n == 1) and 0 or 0.9 * eff.Size
				it.Anchor, it.OffR, it.OffD = "Hit", cos(a) * rad, sin(a) * rad
				it.TR = T.Travel + travel * 0.6 * (i - 1) / max(1, n - 1)
				it.Rot = CFrame.fromAxisAngle(V3(-sin(a), 0, cos(a)), (n == 1) and 0 or -0.35) * CFrame.Angles(0, hash(i, 22) * TAU, 0)
			else -- spikes along the path, alternating sides
				local f = 0.35 + 0.65 * (i - 1) / max(1, n - 1)
				it.Anchor, it.F, it.OffR = "Path", f, ((i % 2 == 0) and 0.45 or -0.45) * eff.Size
				it.TR = T.Travel + travel * (i - 1) / max(1, n - 1) * 0.85
				it.Rot = CFrame.Angles((hash(i, 23) - 0.5) * 0.4, hash(i, 24) * TAU, (hash(i, 25) - 0.5) * 0.4)
			end
			if core.KeepMaterial then -- the Freeze cage rises a little slower
				it.TR = T.Travel
			end
			addSolid(eff, key, it)
		end
	elseif path == "Area" then
		local travel = max(0.05, T.Impact - T.Travel)
		if core.Fall then -- the Storm special: the element rains out of the cloud
			local n = min(8, finite(core.Count) and core.Count or 6)
			-- (fix round 1: Spread = the storm rains on EVERY target in its zone, round robin, at least one piece each up to
			-- 8 targets: a 9th+ enemy in the zone stays dry, cosmetic)
			local nT = #eff.T
			local spread = core.Spread == true and nT > 1
			if spread then
				n = min(8, max(n, nT))
			end
			for i = 1, n do
				-- (attack effects, 2026-11-01: the rain covers the real zone, evolved too)
				local a, rad = hash(i, 31) * TAU, (0.1 + 0.9 * hash(i, 32)) * eff.Reach
				local tgt = nil
				if spread then
					tgt, rad = (i - 1) % nT + 1, (0.2 + 1.1 * hash(i, 32)) * eff.Size
				end
				addSolid(eff, key, look({ Move = MOVE.Fall, T0 = T.Travel, TR = T.Travel + travel * 0.9 * hash(i, 33), Drop = 0.3, OffR = cos(a) * rad, OffD = sin(a) * rad, Tgt = tgt, T1 = T.Linger + 0.3 }))
			end
		elseif core.Fan then
			local n = min(5, finite(core.Count) and core.Count or 3)
			for i = 1, n do
				local ang = (n == 1) and 0 or (-0.45 + 0.9 * (i - 1) / (n - 1))
				-- (evolved forms: Reversed = Maelstrom's blades run back to the pet, over the whole recipe)
				addSolid(eff, key, look({ Move = MOVE.Fly, T0 = T.Release, T1 = core.Reversed and eff.TailAt or (T.Linger + 0.15), Ang = ang, Back = core.Reversed, Trans = (i == (n + 1) / 2) and trans or max(trans, 0.25) }))
			end
		elseif core.Stretch then
			-- (the recipe's Core.Thick wins: Task 8, the Line core was always 1.2 thick whatever the catalog said)
			addSolid(eff, key, look({ Move = MOVE.Stretch, T0 = T.Travel - 0.02, Line = true, Thick = (finite(core.Thick) and core.Thick or 1.2) * eff.WidthScale }))
		elseif key == "vfx_ring" then -- the Circle nova
			local to = (eff.Reach * 2) / 4 / max(0.1, S)
			addSolid(eff, key, look({ Move = MOVE.Ring, Flat = true, Anchor = eff.Center and "Hit" or "Self", T0 = T.Travel, TG = T.Impact + 0.1, TF = T.Impact, T1 = T.Linger + 0.35, From = 0.3, To = to })) -- (evolved forms: a ranged pet's Circle stands on its aim point)
		else -- the ground elements' spikes / roots over the attack's shape
			local n = min(6, finite(core.Count) and core.Count or 4)
			for i = 1, n do
				local it = look({ Move = MOVE.Rise, T0 = 0, TS = T.Linger + (eff.TailAt - T.Linger) * 0.3, T1 = eff.TailAt, Anchor = eff.Center and "Hit" or "Self" })
				local f = (i - 0.5) / n
				if eff.Area == "Circle" then
					local a = f * TAU
					it.OffR, it.OffD = cos(a) * eff.Reach * 0.6, sin(a) * eff.Reach * 0.6
				else
					local spread = (eff.Area == "Cone") and (((i % 2 == 0) and 1 or -1) * f * eff.Reach * 0.35) or (((i % 2 == 0) and 0.4 or -0.4) * eff.Size)
					it.OffR, it.OffD = spread, (0.15 + 0.85 * f) * eff.Reach
				end
				it.TR = T.Travel + travel * f
				it.Rot = CFrame.Angles((hash(i, 26) - 0.5) * 0.4, hash(i, 27) * TAU, (hash(i, 28) - 0.5) * 0.4)
				addSolid(eff, key, it)
			end
		end
	elseif path == "Self" then
		if key == "vfx_ring" then -- the Rally roar: rings pulse outward
			local n = min(3, finite(core.Pulses) and core.Pulses or 1)
			local span = max(0.2, T.Linger - T.Travel)
			for i = 1, n do
				local t0 = T.Travel + span * (i - 1) / n
				addSolid(eff, key, look({ Move = MOVE.Ring, Flat = true, Anchor = "Self", T0 = t0, TG = t0 + 0.45, TF = t0 + 0.1, T1 = t0 + 0.55, From = 0.3, To = finite(core.Grow) and core.Grow or 3 }))
			end
		elseif core.Flash or core.Poof then
			-- (Task 10 review I1: the ShieldHit ripple sets its own From / To and a see-through shell; the hurt flash / KO
			-- poof keep their defaults)
			local from = finite(core.From) and core.From or (core.Poof and 0.8 or 0.6)
			local to = finite(core.To) and core.To or (core.Poof and 2 or 1.6)
			local pop = addSolid(eff, key, look({ Move = MOVE.Pop, Anchor = "Self", T0 = 0, T1 = core.Poof and min(eff.TailAt, 0.7) or min(eff.TailAt, 0.3), From = from, To = to, Trans = max(trans, core.Poof and 0.3 or 0.15) }))
			-- (Task 11c, review I4) the ShieldHit ripple (core.Fit) is the victim's own dome: it starts at the size the Shield
			-- fitted round that pet (fitFor; the victim alone: no other ally to keep apart from) and swells by To / From;
			-- no victim model: the catalog's From / To
			if pop and finite(core.Fit) then
				local fit, sink = fitFor(eff.Src, nil, nil, pop.Base, pop.S, core)
				if fit then
					pop.From, pop.To, pop.Sink, pop.Fitted = fit, fit * (to / max(0.05, from)), sink, true
				end
			end
		else
			addSolid(eff, key, look({ Move = MOVE.Star, T0 = T.Travel, T1 = eff.TailAt }))
		end
	elseif path == "Allies" then
		local n = min(K.MAX_ALLIES, max(1, #eff.T))
		for i = 1, n do
			if key == "vfx_ring" then
				addSolid(eff, key, look({ Move = MOVE.Ring, Flat = true, Anchor = i, T0 = T.Travel, TG = T.Impact + 0.1, TF = T.Linger, T1 = eff.TailAt, From = 0.4, To = finite(core.Grow) and core.Grow or 1.5, Spin = 1.5 }))
			else
				local disc = string.find(key, "disc", 1, true) ~= nil
				local sh = addSolid(eff, key, look({ Move = MOVE.Shell, Anchor = i, OffD = disc and 1.2 * eff.Size or 0, Disc = disc, T0 = T.Travel, TF = T.Linger + (eff.TailAt - T.Linger) * 0.5, T1 = eff.TailAt }))
				if sh and not disc and finite(core.Fit) then
					sh.Fit, sh.Sink = shellFit(eff, i, sh.Base, sh.S, core)
				end
			end
		end
	end
end

-- the emitter layers this effect can afford, best first (the impact burst, then the impact detail ...); `keep` = the
-- recipe's LowKeep ({ [id] = order }) at Low quality: the element's chosen layer comes right after the Burst
local function emitterRank(layer, keep)
	if layer.Id == "Burst" then
		return 0
	elseif keep and keep[layer.Id] then
		return 0.5 + keep[layer.Id] * 0.01
	elseif layer.Id == "Sparks" then -- (attack effects, 2026-11-01) the impact package's sparks: after the impact detail, before Slash / Travel
		return 1.2
	elseif layer.Beat == "Impact" then
		return 1
	elseif layer.Id == "Slash" then
		return 2
	elseif layer.Beat == "Travel" then
		return 3
	elseif layer.Alive then
		return 4
	elseif layer.Beat == "Linger" or layer.Beat == "Release" then
		return 5
	end
	return 6
end

local function isEmitter(layer)
	return layer.Kind == "Emitter" or (layer.Kind == "Decal" and type(layer.Texture) == "string")
end

-- the beams a Beam layer asks for (addBeamLayer draws at most this many; evolved forms: a KeepCount may ask past the 3, Thunder Pack's 4 strikes)
local function beamWant(layer)
	return min(max(3, finite(layer.KeepCount) and floor(layer.KeepCount) or 0), max(1, finite(layer.Count) and floor(layer.Count) or 1))
end

-- the beam layers this effect can afford, best first, like emitterRank (Task 9 review I1 / M6: built in catalog order
-- with the alive detail appended last, Storm's own Bolt + Crackle took all 4 beams from Rare up and its stray strikes
-- and the Mythic ShotArcs never drew; the Celestial Secret shot drew 1 of its 3 constellation lines): the alive detail,
-- then the recipe's own beams (the element's / attack's / kind's / signature's), then the rarity ladder's arcs
-- (DoubleArc / ShotArcs: a LayerSlots template)
local function beamRank(layer, slots)
	if layer.Alive then
		return 0
	elseif slots and slots[layer.Id] then
		return 2
	end
	return 1
end

-- how many beams each Beam layer gets ({ [layer] = n }) under `cap`: one each first, best first (every beam layer is
-- seen while there is room), then the rest of each layer's own count, best first (the alive detail fills up first)
local function beamBudget(layers, cap)
	local catalog = dep("AttackFxCatalog")
	local slots = type(catalog) == "table" and catalog.LayerSlots or nil
	local ranked = {}
	for i, layer in ipairs(layers) do
		if layer.Kind == "Beam" then
			ranked[#ranked + 1] = { L = layer, R = beamRank(layer, slots), I = i, N = beamWant(layer) }
		end
	end
	table.sort(ranked, function(a, b)
		if a.R ~= b.R then
			return a.R < b.R
		end
		return a.I < b.I
	end)
	local give, left = {}, cap
	for _, e in ipairs(ranked) do
		if left <= 0 then
			break
		end
		give[e.L], left = 1, left - 1
	end
	-- (Task 10 review I2: a layer's KeepCount, the kind's / element's identity like the Beam's two spiral arcs, is
	-- filled before any other layer's second beam; then each layer's own count, best first)
	for pass = 1, 2 do
		for _, e in ipairs(ranked) do
			if left <= 0 then
				break
			end
			local g, k = give[e.L], e.L.KeepCount
			local want = (pass == 2) and e.N or (finite(k) and min(e.N, floor(k)) or 0)
			if g and want > g then
				local more = min(want - g, left)
				give[e.L], left = g + more, left - more
			end
		end
	end
	return give
end

-- a charge glow at the mouth with no charge shown (shortened to fit the event): drawn by nobody, so it never takes
-- one of the effect's emitter slots
local function chargeDropped(eff, layer)
	return (layer.Beat or "Impact") == "Charge" and layer.At == "Source" and not layer.Alive and layer.Kind ~= "Decal"
		and eff.Times.Release <= 0.02
end

local function resetEmitter(em)
	em.Shape = Enum.ParticleEmitterShape.Box
	em.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	em.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	em.EmissionDirection = Enum.NormalId.Top
	em.Orientation = Enum.ParticleOrientation.FacingCamera
	em.SpreadAngle = Vector2.new(180, 180)
	em.Acceleration = V3(0, 0, 0)
	em.Drag = 0
	em.LockedToPart = false
	em.VelocityInheritance = 0
	em.Rotation = NumberRange.new(0, 360)
	em.RotSpeed = NumberRange.new(-60, 60)
	em.ZOffset = 0
	em.TimeScale = 1
	em.Brightness = 1
	em.Rate = 0
	em.Enabled = false
end

-- the emitter's look and motion for this layer (once per play, never per frame)
local function tuneEmitter(eff, it, layer)
	local kit = it.Kit
	local em, host = kit.Em, kit.Root
	resetEmitter(em)
	host.Size = V3(0.2, 0.2, 0.2)
	local key = layer.Texture
	local id = dep("TextureIds")[key]
	em.Texture = "rbxassetid://" .. tostring(id)
	local sheet = SHEETS[key] or { "Loop", 16, 0.5 }
	em.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	em.FlipbookMode = Enum.ParticleFlipbookMode[sheet[1]]
	em.FlipbookFramerate = NumberRange.new(sheet[2])
	em.FlipbookStartRandom = sheet[1] == "Loop"
	-- a layer's LightEmission overrides the sheet's (Task 9: the slash arc half-lit, so it keeps the element's colour)
	-- (review M2 / M3: the lit / hot rules read the EFFECTIVE value: a half-lit override (Storm's BurstLight 0.4 on
	-- fx_glow) neither opens 45 % white nor ignores the scene light, like a sheet of the same value)
	local light = finite(layer.LightEmission) and clamp01(layer.LightEmission) or sheet[3]
	em.LightEmission = light
	em.LightInfluence = (light >= 0.5) and 0 or 0.6
	local c = typeof(layer.Color) == "Color3" and layer.Color or WHITE
	if typeof(layer.Color2) == "Color3" then
		-- (Studio findings round) two tones: born in Color2 (the cloud's lit rim / underside), darkening into Color
		em.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, layer.Color2), ColorSequenceKeypoint.new(0.45, layer.Color2:Lerp(c, 0.6)), ColorSequenceKeypoint.new(1, c) })
	elseif light >= 0.8 then
		em.Color = ColorSequence.new(c:Lerp(WHITE, 0.45), c) -- glows start hot
	else
		em.Color = ColorSequence.new(c, c:Lerp(BLACK, 0.2))
	end
	-- (attack effects, 2026-11-01, Gemini: clouds past x1.6 hide the target) particles and their spread stop at CloudSize; a
	-- flat ground mark lies under the target and takes the full Size
	local S = (layer.Kind == "Decal") and eff.Size or eff.CloudSize
	local sz = (finite(layer.Size) and layer.Size or 1) * S * (eff.Strong and 1.12 or 1)
	local m = it.Preset
	local life = { 0.35, 0.6 }
	local sizeSeq = { 0.4, 1, 0.7 }
	local hold = 0.55
	local start = 0.1
	em.Speed = NumberRange.new(2.5 * S, 5.5 * S)
	em.Drag = 5
	em.Acceleration = V3(0, -3, 0)
	em.ZOffset = 0.4
	if m == "Shatter" then
		em.Speed = NumberRange.new(5 * S, 9 * S)
		em.Drag = 3
		em.Acceleration = V3(0, -22, 0)
		em.RotSpeed = NumberRange.new(-220, 220)
		life = { 0.45, 0.7 }
	elseif m == "Geyser" or m == "Erupt" then -- an upward column (Task 9: a fountain of drops rising from a patch of
		-- ground round the hit, not one clump: at the impact frame a single point read as a bubble)
		-- (round 3, Gemini: at +0.16 s the 2.2-stud patch of rising sheets still caged the target like a bubble: a narrow
		-- base under the target that fans OUT in a V, so the spray bursts away from it)
		host.Size = V3(1.2 * S, 0.3, 1.2 * S)
		em.SpreadAngle = Vector2.new(34, 34)
		em.Speed = NumberRange.new(13 * S, 19 * S)
		em.Drag = 0.5
		em.Acceleration = V3(0, -30, 0)
		life = { 0.5, 0.7 }
		sizeSeq = { 0.5, 1, 0.85 }
	elseif m == "Implode" then -- pulled inward to the centre (Task 9: from a 3.2-stud shell, 4.5 swallowed the target)
		host.Size = V3(3.2, 3.2, 3.2) * S
		em.Shape = Enum.ParticleEmitterShape.Sphere
		em.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		em.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		em.SpreadAngle = Vector2.new(0, 0)
		em.Speed = NumberRange.new(7 * S, 10 * S)
		em.Drag = 0
		em.Acceleration = V3(0, 0, 0)
		life = { 0.28, 0.36 }
		sizeSeq = { 1, 1, 0.25 }
	elseif m == "Fling" then
		em.SpreadAngle = Vector2.new(55, 55)
		em.Speed = NumberRange.new(6 * S, 10 * S)
		em.Drag = 0.5
		em.Acceleration = V3(0, -28, 0)
		life = { 0.5, 0.75 }
	elseif m == "Rise" then
		em.SpreadAngle = Vector2.new(25, 25)
		em.Speed = NumberRange.new(1.5 * S, 3 * S)
		em.Drag = 1
		em.Acceleration = V3(0, 1.5, 0)
		life = { 0.6, 0.95 }
		sizeSeq = { 0.5, 1, 1.3 }
	elseif m == "Slash" then -- one big arc, the sheet sweeps round
		em.Speed = NumberRange.new(0, 0)
		em.SpreadAngle = Vector2.new(0, 0)
		em.Acceleration = V3(0, 0, 0)
		em.Rotation = NumberRange.new(-25, 25)
		em.RotSpeed = NumberRange.new(0, 0)
		em.ZOffset = 0.6
		life = { 0.22, 0.26 }
		sizeSeq = { 0.7, 1, 1.1 }
		start = 0
	elseif m == "Flat" then -- a ground-flat sheet (Decal layers): faces up, stays put
		em.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		em.SpreadAngle = Vector2.new(0, 0)
		em.Speed = NumberRange.new(0.01, 0.01)
		em.Drag = 0
		em.Acceleration = V3(0, 0, 0)
		em.RotSpeed = NumberRange.new(0, 0)
		em.ZOffset = 0
		local secs = finite(layer.Seconds) and layer.Seconds or 0.7
		life = { secs, secs }
		sizeSeq = { 0.55, 1, 1.1 }
		hold = 0.6
		start = 0.3
	elseif m == "Gather" then -- the charge glow: motes pulled in to the mouth
		host.Size = V3(3, 3, 3) * S
		em.Shape = Enum.ParticleEmitterShape.Sphere
		em.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		em.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		em.Speed = NumberRange.new(3 * S, 4.5 * S)
		em.Drag = 0
		em.Acceleration = V3(0, 0, 0)
		em.ZOffset = 0.2
		life = { 0.3, 0.42 }
		sizeSeq = { 0.3, 1, 0.2 }
	elseif m == "Cloud" then
		host.Size = V3(4 * S, 0.6, 4 * S)
		em.Speed = NumberRange.new(0.3, 0.8)
		em.Drag = 1
		em.Acceleration = V3(0, 0, 0)
		em.ZOffset = 0
		life = { 0.9, 1.3 }
		sizeSeq = { 0.6, 1, 1.15 }
		start = 0.25
		hold = 0.7
	elseif m == "Trail" then
		em.Speed = NumberRange.new(0.4, 1.4)
		em.Drag = 2
		em.Acceleration = V3(0, 0.8, 0)
		em.ZOffset = 0.2
		life = { 0.3, 0.5 }
	elseif m == "Spiral" then
		em.SpreadAngle = Vector2.new(15, 15)
		em.Speed = NumberRange.new(1, 2)
		em.Drag = 0.5
		em.Acceleration = V3(0, 1, 0)
		life = { 0.5, 0.8 }
	elseif m == "Fall" then
		host.Size = V3(6 * S, 0.4, 6 * S)
		em.EmissionDirection = Enum.NormalId.Bottom
		em.SpreadAngle = Vector2.new(6, 6)
		em.Speed = NumberRange.new(12, 16)
		em.Drag = 0
		em.Acceleration = V3(0, -10, 0)
		life = { 0.45, 0.6 }
		if layer.Streak and key == "fx_streak" then
			-- (Studio findings round: the Storm rain read as soft round blobs) thin streaks along the fall: the sheet's
			-- horizontal streak turned STREAK_ROT upright, no spin, a narrower host under the cloud
			-- (Task 11c, Studio round 2: R1 asked whether the streaks lay sideways. The rain falls straight down (spread 6
			-- degrees), so the streaks are held upright to the WORLD (FacingCameraWorldUp: the sheet's up is world up, turned
			-- to the camera about Y) rather than to the velocity: upright whichever image axis VelocityParallel would pin
			-- to the velocity; STREAK_SIZE x the layer's Size (M1); R4: brighter, so the rain reads in daylight)
			host.Size = V3(3.6 * S, 0.3, 3.6 * S)
			em.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
			em.Rotation = NumberRange.new(K.STREAK_ROT, K.STREAK_ROT)
			em.RotSpeed = NumberRange.new(0, 0)
			em.FlipbookStartRandom = true
			em.LightEmission = min(light, 0.7)
			em.LightInfluence = 0.1
			em.Brightness = 1.3
			em.Speed = NumberRange.new(16, 20)
			sz = sz * K.STREAK_SIZE
			sizeSeq = { 0.8, 1, 1 }
		end
	elseif m == "Ride" then -- (Studio findings round: the Pounce's storm cloud) puffs shed by the leaping pet, left behind
		-- (review M7, parked: At "Self" follows the model's pivot, which carries the leap pose; a unit with no model (parked /
		-- hidden, never drawn) gets no scripted hop here: its puffs stay at the take-off point)
		host.Size = V3(1.2 * S, 0.5, 1.2 * S)
		em.SpreadAngle = Vector2.new(60, 60)
		em.Speed = NumberRange.new(0.5, 1.5)
		em.Drag = 2
		em.Acceleration = V3(0, 0.6, 0)
		em.ZOffset = -0.2
		life = { 0.45, 0.7 }
		sizeSeq = { 0.5, 1, 1.25 }
		start = 0.2
	elseif m == "Bounce" then
		host.Size = V3(2.4 * S, 0.2, 2.4 * S)
		em.SpreadAngle = Vector2.new(35, 35)
		em.Speed = NumberRange.new(4, 6.5)
		em.Drag = 0
		em.Acceleration = V3(0, -26, 0)
		life = { 0.5, 0.7 }
	elseif m == "SwirlUp" then
		host.Size = V3(1.6 * S, 0.4, 1.6 * S)
		em.SpreadAngle = Vector2.new(20, 20)
		em.Speed = NumberRange.new(2, 4)
		em.Drag = 0.5
		em.Acceleration = V3(0, 2.5, 0)
		em.RotSpeed = NumberRange.new(-180, 180)
		life = { 0.6, 0.9 }
	end
	-- (Task 11d, Studio round 3, S2) an emitter layer's Brightness (self-lit sheets, LightInfluence 0: Cloud Breath's
	-- puff, the grey storm-cloud sheet drawn white-blue instead of a dark navy smudge)
	if finite(layer.Brightness) and layer.Brightness > 0 then
		em.Brightness = layer.Brightness
	end
	-- (Task 10: the Heal's plus-shaped sparkles: the 4-point glint held upright, no random roll or spin = a "+")
	if layer.Shape == "Plus" then
		em.Rotation = NumberRange.new(0, 0)
		em.RotSpeed = NumberRange.new(0, 0)
	end
	-- a layer's SpeedScale (Task 9: Earth's chunks flung further, so the break scatters instead of piling up)
	if finite(layer.SpeedScale) and layer.SpeedScale > 0 then
		em.Speed = NumberRange.new(em.Speed.Min * layer.SpeedScale, em.Speed.Max * layer.SpeedScale)
	end
	-- particles end with the effect: the kit is reused right after it (evolved forms: an aura's stream, with the aura)
	local held = heldByAura(eff, layer)
	local latest = (held and eff.EndRel or eff.TailAt) - it.T1
	local hi = max(0.12, min(life[2], latest))
	local lo = min(life[1], hi)
	-- (attack effects, 2026-11-01) a lingering mark / ember: its particle lives on by the Afterglow, past `knee` (its share of the old life) only fading
	local knee = 1
	if lingers(eff, layer) and not held then
		hi = max(0.12, min((finite(layer.Seconds) and layer.Seconds or life[2]) + eff.Afterglow, eff.EndRel - it.T1))
		lo = (m == "Flat") and hi or hi * 0.75 -- (no quick particle dimming out while the hit still plays)
		knee = min(1, life[2] / hi)
		if m == "SwirlUp" then -- (the embers hang on instead of flying off: "still")
			em.Drag = 1.5
			em.Acceleration = V3(0, 1, 0)
		end
	end
	em.Lifetime = NumberRange.new(lo, hi)
	em.Size = NumberSequence.new({ kp(0, sz * sizeSeq[1]), kp(0.2 * knee, sz * sizeSeq[2]), kp(1, sz * sizeSeq[3]) })
	-- (a layer's Transparency lifts the whole curve: Task 9, the band 4 ladder layers washed out the leap and the target)
	local a = finite(layer.Transparency) and clamp01(layer.Transparency) or 0
	if knee < 1 then
		em.Transparency = NumberSequence.new({ kp(0, a + (1 - a) * start), kp(0.12 * knee, a), kp(hold * knee, a + (1 - a) * 0.1), kp(knee, max(a, eff.TailTrans)), kp(1, 1) })
	else
		em.Transparency = NumberSequence.new({ kp(0, a + (1 - a) * start), kp(0.12, a), kp(hold, a + (1 - a) * 0.1), kp(1, 1) })
	end
end

local EMITTER_MOTIONS = { Geyser = true, Implode = true, Fling = true, Rise = true, Shatter = true, Erupt = true, Burst = true, Bounce = true, SwirlUp = true }

local function addEmitterLayer(eff, layer)
	local T = eff.Times
	local beat = layer.Beat or "Impact"
	local t0 = beatStart(eff, beat) + (finite(layer.Delay) and layer.Delay or 0)
	local t1 = beatEnd(eff, beat)
	local mode, preset, stream = "Burst", "Burst", nil
	local at = layer.At
	if layer.Kind == "Decal" then
		preset = "Flat"
	elseif layer.Alive then
		mode, stream = "Stream", "Alive"
		preset = (layer.Motion == "Bounce" or layer.Motion == "SwirlUp") and layer.Motion or "Rise"
		t1 = min(eff.TailAt - 0.1, t0 + (finite(layer.Seconds) and layer.Seconds or 0.6) * 0.6)
	elseif beat == "Charge" and at == "Source" then
		if chargeDropped(eff, layer) then
			return -- no charge shown (shortened to fit the event)
		end
		mode, preset = "Stream", "Gather"
	elseif beat == "Charge" and at == "Above" then
		-- (Task 11d, Studio round 3, S3: streaming only through the charge, its last puffs faded out by ~1.3 s and the zone
		-- was empty by the hit: the generic Storm read as nothing at 1.4 s) the cloud keeps forming until the impact, so it
		-- hangs over the zone through the rain, the hit and most of the linger
		mode, preset, t1 = "Stream", "Cloud", T.Impact
	elseif layer.Ride then -- (Studio findings round) streams off the leaping pet from the take-off to the landing
		mode, preset, at = "Stream", "Ride", "Self"
		t0, t1 = min(t0, T.Release), T.Impact + 0.05
	elseif layer.Spiral then
		mode, preset, stream = "Stream", "Spiral", "Spiral"
	elseif layer.Along then -- (Task 10: the Beam's wrap) the element streams along mouth -> hit while the beam holds
		mode, preset, stream, t1 = "Stream", "Trail", "Along", T.Linger + 0.15
	elseif layer.Drift then -- (Task 10: the Haste gust) the element streams off each point over the beat
		mode, preset = "Stream", "Trail"
	elseif layer.Fall or layer.Id == "Rain" then
		mode, preset, at, t1 = "Stream", "Fall", "Above", T.Impact + 0.05
	elseif beat == "Travel" and at == "Core" then
		mode, preset = "Stream", "Trail"
	elseif layer.Id == "Slash" then
		preset = "Slash"
		if eff.Path == "Swipe" or eff.Path == "Ground" then
			at = "Target" -- the arc sweeps through the target
		end
	elseif EMITTER_MOTIONS[layer.Motion] then
		preset = layer.Motion
	end
	-- (evolved forms) in an aura it streams (a burst's preset kept) until the aura's near its end
	local held = heldByAura(eff, layer)
	if held then
		mode = "Stream"
		t1 = max(t0, eff.AuraRel - K.AURA_LIFE)
	else
		if mode == "Burst" then
			t1 = t0
		end
		t1 = max(t0, min(t1, eff.TailAt - 0.05))
	end
	local kit = take("Emitter")
	eff.Emitters = eff.Emitters + 1
	local count = (finite(layer.Count) and layer.Count or 1) * eff.Recipe.Density * (eff.Low and K.LOW_COUNT or 1)
	if eff.Crit and beat == "Impact" then
		count = count * 1.3
	end
	count = max(1, floor(count + 0.5))
	if preset == "Flat" then
		count = 1
	end
	-- (Studio findings round) an "Above" layer with a Height sits that many studs over the hit point, not ABOVE x size:
	-- the Storm cloud low over its zone; the rain under it (and the core's falling pieces, MOVE.Fall) start from it
	-- (Task 11c, review M8: eff.CloudLift is resolved before any layer is added (Play's pre-pass), not by the Cloud being
	-- earlier in the catalog than the Rain)
	local lift = nil
	if at == "Above" and eff.CloudLift then
		lift = eff.CloudLift - K.ABOVE * eff.Size
	end
	local it = addItem(eff, {
		Kind = "Emitter", Kit = kit, Layer = layer, At = at, T0 = t0, T1 = t1, Mode = mode, Preset = preset, Stream = stream,
		Count = count, Rate = held and (count * K.AURA_RATE) or (count / max(0.05, t1 - t0)), Acc = held and (count * 0.5) or 1, Pts = {}, Flat = preset == "Flat", Fn = DRAW.Emitter, Lift = lift, Lingers = lingers(eff, layer),
	})
	tuneEmitter(eff, it, layer)
end

-- `allow` = the beams beamBudget gave this layer (nil = its own count)
local function addBeamLayer(eff, layer, allow)
	local T = eff.Times
	local beat = layer.Beat or "Travel"
	local t0 = beatStart(eff, beat) + (finite(layer.Delay) and layer.Delay or 0)
	local mode, t1
	local at = layer.At
	if layer.Alive then
		mode = (layer.Motion == "Connect") and "Connect" or "Strike"
		t1 = min(eff.TailAt, t0 + (finite(layer.Seconds) and layer.Seconds or 0.6))
	elseif layer.Id == "DoubleArc" then
		mode, t1 = "Crescent", T.Impact + 0.2
	elseif layer.Id == "Rain" then -- the Storm special's lightning rain: bolts strike down around the target
		mode, t1 = "Strike", T.Impact + 0.2
	elseif layer.Strike then -- (Studio findings round) bolts strike down round the hit from the beat (the Pounce slam)
		mode, t1 = "Strike", t0 + 0.35
	elseif at == "Path" then
		mode, t1 = "Path", T.Impact + (finite(layer.Seconds) and layer.Seconds or 0.08) -- (evolved forms: Seconds = a twist's bolt, drawn at its impact)
	else
		mode, t1 = "Arc", T.Impact + 0.15
	end
	local n = beamWant(layer)
	if allow then
		n = min(n, allow)
	end
	local id = layer.Texture and dep("TextureIds")[layer.Texture]
	for i = 1, n do
		if eff.Beams >= AttackFx.MAX_BEAMS then
			return
		end
		local kit = take("Beam")
		eff.Beams = eff.Beams + 1
		local b = kit.Beam
		local c = typeof(layer.Color) == "Color3" and layer.Color or WHITE
		b.Color = ColorSequence.new(c:Lerp(WHITE, 0.35), c)
		local a = finite(layer.Transparency) and clamp01(layer.Transparency) or 0 -- (Task 9: a see-through Mythic double arc)
		b.Transparency = NumberSequence.new({ kp(0, a + (1 - a) * 0.35), kp(0.15, a), kp(0.85, a), kp(1, a + (1 - a) * 0.35) })
		-- (Task 9 Studio: additive, the thin lightning strip vanished on the pale sky / floor; drawn mostly opaque in its
		-- colour it reads as a bolt)
		b.LightEmission = finite(layer.LightEmission) and clamp01(layer.LightEmission) or ((layer.Texture == "fx_lightning") and 0.25 or 1)
		b.LightInfluence = 0
		b.FaceCamera = true
		b.CurveSize0 = 0
		b.CurveSize1 = 0
		b.Segments = (mode == "Crescent" or layer.Spiral) and 16 or 2
		if id then
			b.Texture = "rbxassetid://" .. tostring(id)
			if layer.Texture == "fx_lightning" then
				b.TextureMode = Enum.TextureMode.Stretch
				b.TextureLength = 1
				b.TextureSpeed = 2.5
			else
				b.TextureMode = Enum.TextureMode.Wrap
				b.TextureLength = 4
				b.TextureSpeed = 3
			end
		else
			b.Texture = ""
		end
		local w = (finite(layer.Width) and layer.Width or ((mode == "Connect") and 0.12 or (layer.Spiral and 0.5 or 0.9))) * eff.Size
		local it = addItem(eff, {
			Kind = "Beam", Kit = kit, Layer = layer, Mode = mode, I = i, N = n, T0 = t0, T1 = t1, Fn = DRAW.Beam,
			Width0 = (mode == "Crescent") and w * 0.15 or w, Width1 = w, Flicker = layer.Texture == "fx_lightning",
			Spiral = layer.Spiral == true, Curve = (finite(layer.Curve) and layer.Curve or 2.2) * eff.Size,
			Jitter = layer.Id == "SigBolts",
		})
		if mode == "Crescent" then
			b.CurveSize0 = it.Curve
			b.CurveSize1 = -it.Curve
		end
	end
end

local function addTrailLayer(eff, layer)
	local T = eff.Times
	local beat = layer.Beat or "Travel"
	local t0 = beatStart(eff, beat)
	local t1 = beatEnd(eff, beat)
	if beat == "Travel" then
		t1 = T.Impact
	end
	if layer.At == "Self" then -- (Task 10) the leap trails: from the take-off (the Strike starts at the release) to the landing
		t0, t1 = min(t0, T.Release), T.Impact + 0.05
	end
	local list = {}
	if layer.At == "Allies" then
		for a = 1, min(K.MAX_ALLIES, max(1, #eff.T)) do
			list[#list + 1] = { Mode = "Wind", Ally = a, Side = 0 }
		end
	else
		local n = min(2, max(1, finite(layer.Afterimages) and layer.Afterimages or 1))
		for i = 1, n do
			list[#list + 1] = { Mode = (layer.At == "Self") and "Leap" or "Core", Side = (n == 1) and 0 or ((i == 1) and -0.35 or 0.35) * eff.Size }
		end
	end
	local id = layer.Texture and dep("TextureIds")[layer.Texture]
	for _, spec in ipairs(list) do
		if eff.Trails >= AttackFx.MAX_TRAILS then
			return
		end
		local kit = take("Trail")
		eff.Trails = eff.Trails + 1
		local tr = kit.Trail
		local c = typeof(layer.Color) == "Color3" and layer.Color or WHITE
		tr.Color = ColorSequence.new(c:Lerp(WHITE, 0.4), c)
		tr.Transparency = NumberSequence.new({ kp(0, 0.15), kp(1, 1) })
		tr.WidthScale = NumberSequence.new({ kp(0, 1), kp(1, 0.1) })
		-- (a layer's Lifetime wins: Task 8 + Gemini, the ranged Streak at 0.2 s reached back to the mouth mid-flight and
		-- read as a tether, not a shot; a short comet tail instead)
		tr.Lifetime = (finite(layer.Lifetime) and layer.Lifetime > 0) and min(1, layer.Lifetime) or 0.2
		tr.LightEmission = 1
		tr.LightInfluence = 0
		tr.FaceCamera = true
		tr.Texture = id and ("rbxassetid://" .. tostring(id)) or ""
		tr.TextureMode = Enum.TextureMode.Stretch
		local hw = 0.45 * eff.Size
		kit.A0.Position = V3(0, hw, 0)
		kit.A1.Position = V3(0, -hw, 0)
		local held = heldByAura(eff, layer) -- (evolved forms) an aura's wind: until the aura ends
		addItem(eff, { Kind = "Trail", Kit = kit, Layer = layer, Mode = spec.Mode, Ally = spec.Ally, Side = spec.Side, T0 = t0, T1 = held and eff.AuraRel or max(t0 + 0.05, t1), Fn = DRAW.Trail, Lingers = held or nil, Held = held or nil })
	end
end

local function addLightLayer(eff, layer)
	if eff.Lights >= AttackFx.MAX_LIGHTS then
		return
	end
	if eff.Low and (layer.Pulse or layer.Id == "Bloom") then
		return -- Low: no bloom
	end
	local T = eff.Times
	local beat = layer.Beat or "Impact"
	local t0 = beatStart(eff, beat) + (finite(layer.Delay) and layer.Delay or 0)
	local t1 = min(eff.TailAt, (layer.Pulse and T.Impact + 0.2) or (beatEnd(eff, beat) + 0.25))
	if beat == "Travel" and layer.At == "Core" then
		t1 = T.Impact + 0.1
	end
	local kit = take("Light")
	eff.Lights = eff.Lights + 1
	local c = typeof(layer.Color) == "Color3" and layer.Color or WHITE
	kit.Light.Color = c
	kit.Light.Range = (finite(layer.Range) and layer.Range or 8) * min(eff.Size, K.LIGHT_SIZE)
	kit.Light.Brightness = 0
	local base = finite(layer.Brightness) and layer.Brightness or 2
	local b = min(max(K.LIGHT_BRIGHT, base), base * (eff.Crit and 1.3 or 1))
	addItem(eff, { Kind = "Light", Kit = kit, Layer = layer, At = layer.At, T0 = t0, T1 = max(t0 + 0.1, t1), B = b, Pulse = layer.Pulse == true, Shift = layer.ColorShift == true, Color = c, Pts = {}, Fn = DRAW.Light })
end

local function addDiscLayer(eff, layer)
	local beat = layer.Beat or "Impact"
	local t0 = beatStart(eff, beat) + (finite(layer.Delay) and layer.Delay or 0)
	local t1 = min(eff.TailAt, t0 + (finite(layer.Seconds) and layer.Seconds or 0.6))
	if layer.Alive then
		t1 = min(eff.TailAt, t0 + (finite(layer.Seconds) and layer.Seconds or 0.8))
	end
	local mainEnd = nil
	if lingers(eff, layer) then
		mainEnd = t1
		t1 = min(eff.EndRel, t0 + (finite(layer.Seconds) and layer.Seconds or (layer.Alive and 0.8 or 0.6)) + eff.Afterglow)
	end
	local kit = take("Disc")
	local d = kit.Root
	local darken = layer.Motion == "Darken"
	local color = typeof(layer.Color) == "Color3" and layer.Color or WHITE
	d.Color = color
	d.Material = darken and Enum.Material.SmoothPlastic or Enum.Material.Neon
	d.Transparency = 1
	local glow = dep("TextureIds")
	glow = glow and glow.fx_glow
	local soft = glow ~= nil and kit.Img ~= nil
	if kit.Img then
		kit.Img.Image = soft and ("rbxassetid://" .. tostring(glow)) or ""
		kit.Img.ImageColor3 = color
		kit.Img.ImageTransparency = 1
		kit.Gui.LightInfluence = darken and 1 or 0 -- a glow shines; the Shadow darkening is a lit dark blot
		kit.Gui.Brightness = darken and 1 or 1.6
	end
	local at = layer.At
	if at ~= "Allies" and at ~= "Self" and at ~= "Source" then
		at = "Ground"
	end
	addItem(eff, { Kind = "Disc", Kit = kit, Layer = layer, At = at, T0 = t0, T1 = max(t0 + 0.1, t1), D = (finite(layer.Size) and layer.Size or 4) * eff.Size, Trans = soft and 0.2 or 0.5, Soft = soft, Pts = {}, Fn = DRAW.Disc, MainEnd = mainEnd, Lingers = mainEnd ~= nil }) -- (Task 8: the soft sheet fades out to its rim by itself; a plain plate stays half see-through)
end

local function addRingLayer(eff, layer)
	local T = eff.Times
	local key = layer.Key or "vfx_ring"
	local t0 = beatStart(eff, layer.Beat or "Impact") + (finite(layer.Delay) and layer.Delay or 0)
	local flatRing = key == "vfx_ring"
	local anchor = (layer.At == "Self") and "Self" or ((layer.At == "Source") and "Source" or "Hit")
	if layer.Pop == true then -- a quick ball popping out at the anchor and fading (the ranged impact's fireball, note (b))
		addSolid(eff, key, {
			Layer = layer, Move = MOVE.Ring, Anchor = anchor, Color = layer.Color, Material = Enum.Material.Neon,
			Trans = finite(layer.Transparency) and layer.Transparency or 0.2, T0 = t0, TG = t0 + 0.14, TF = t0 + 0.06,
			T1 = min(eff.TailAt, t0 + 0.36), From = 0.35, To = finite(layer.Grow) and layer.Grow or 1,
		})
		return
	end
	if layer.Face == true then -- a quick ring standing up at the anchor, facing the attack (the ranged muzzle shock)
		addSolid(eff, key, {
			Layer = layer, Move = MOVE.Ring, Face = true, Anchor = anchor, Color = layer.Color, Material = Enum.Material.Neon,
			Trans = finite(layer.Transparency) and layer.Transparency or 0.1, T0 = t0, TG = t0 + 0.2, TF = t0 + 0.05,
			T1 = min(eff.TailAt, t0 + 0.32), From = 0.3, To = finite(layer.Grow) and layer.Grow or 1,
		})
		return
	end
	if layer.At == "Allies" then -- (Task 10: the Rally lights up each ally) one ring under each ally (<= MAX_ALLIES)
		local held = heldByAura(eff, layer) -- (evolved forms) an aura's ring stays under its pet, fading only at the end
		for i = 1, min(K.MAX_ALLIES, max(1, #eff.T)) do
			addSolid(eff, key, {
				Layer = layer, Move = MOVE.Ring, Flat = true, Anchor = eff.T[i] and i or "Self", Color = layer.Color, Material = Enum.Material.Neon,
				Trans = finite(layer.Transparency) and layer.Transparency or 0.1, T0 = t0, TG = t0 + 0.35, TF = held and (eff.AuraRel - K.AURA_FADE) or (t0 + 0.12),
				T1 = held and eff.AuraRel or min(eff.TailAt, t0 + 0.6), From = 0.4, To = finite(layer.Grow) and layer.Grow or 1.3, Spin = 1.5, Lingers = held or nil,
			})
		end
		return
	end
	if layer.Each == true then -- (evolved forms: a Beam's mark) a level ring on each target (<= MAX_ALLIES)
		for i = 1, min(K.MAX_ALLIES, #eff.T) do
			addSolid(eff, key, {
				Layer = layer, Move = MOVE.Ring, Anchor = i, Color = layer.Color, Material = Enum.Material.Neon,
				Trans = finite(layer.Transparency) and layer.Transparency or 0.1, T0 = t0, TG = t0 + 0.25, TF = t0 + 0.1,
				T1 = min(eff.TailAt, t0 + 0.5), From = 0.4, To = finite(layer.Grow) and layer.Grow or 1.3,
			})
		end
		return
	end
	local ring = addSolid(eff, key, {
		Layer = layer, Move = MOVE.Ring, Flat = (flatRing and layer.Level ~= true) or layer.At == "Ground", Anchor = anchor, Color = layer.Color, Material = Enum.Material.Neon,
		Trans = finite(layer.Transparency) and layer.Transparency or 0.1, T0 = t0, TG = t0 + max(0.25, T.Linger - T.Impact + 0.2), TF = t0 + 0.08,
		T1 = min(eff.TailAt, t0 + max(0.4, T.Linger - T.Impact + 0.35)), From = 0.35, To = finite(layer.Grow) and layer.Grow or 2.5, Thin = layer.Thin == true,
	})
	-- (Studio findings round: the Eclipse Nova) OrbRadius: the ring's peak radius = this x the Blast orb's peak radius (its
	-- main core piece at the impact: MOVE.Projectile's pop, x1.5)
	if ring and finite(layer.OrbRadius) then
		for _, c in ipairs(eff.Items) do
			if c.Move == MOVE.Projectile then -- (the main piece: buildCore adds it first)
				local orbR = c.Base.X * c.S * 1.5 / 2
				ring.To = layer.OrbRadius * orbR / max(0.01, ring.Base.X * ring.S / 2)
				ring.From = min(ring.From, ring.To * 0.3)
				break
			end
		end
	end
	-- (attack effects, 2026-11-01) Reach: the ring's peak radius = the attack's real radius
	if ring and layer.Reach == true then
		ring.To = eff.Reach / max(0.01, ring.Base.X * ring.S / 2)
		ring.From = min(ring.From, ring.To * 0.3)
	end
	-- (attack effects, review) PeakStuds: at most this wide, and never past the attack's real radius (a Storm's zone)
	if ring and finite(layer.PeakStuds) then
		ring.To = min(ring.To, min(layer.PeakStuds / 2, eff.Reach) / max(0.01, ring.Base.X * ring.S / 2))
		ring.From = min(ring.From, ring.To * 0.3)
	end
end

local function addMeshLayer(eff, layer)
	local key = layer.Key
	if type(key) ~= "string" then
		return
	end
	local T = eff.Times
	local t0 = beatStart(eff, layer.Beat or "Impact") + (finite(layer.Delay) and layer.Delay or 0)
	local n = min(6, max(1, finite(layer.Count) and layer.Count or 1))
	local S = eff.Size * (finite(layer.Scale) and layer.Scale or 1)
	local c = typeof(layer.Color) == "Color3" and layer.Color or WHITE
	local m = layer.Motion
	-- (Task 10) At "Allies": the pieces on each ally (the Nature ward's root); Transparency: see-through (the ice / root
	-- rings of the specials, like the element's see-through spikes)
	local anchors = { "Hit" }
	if layer.At == "Allies" then
		anchors = {}
		for a = 1, min(K.MAX_ALLIES, max(1, #eff.T)) do
			anchors[a] = eff.T[a] and a or "Self"
		end
		n = min(n, max(1, floor(12 / #anchors)))
	end
	local trans = finite(layer.Transparency) and clamp01(layer.Transparency) or nil
	for _, anchor in ipairs(anchors) do
		for i = 1, n do
			local a = (i - 1) / n * TAU + hash(i, 41) * 0.6
			local rad = (n == 1) and 0 or 1.1 * eff.Size
			local it = { Layer = layer, Color = c, S = S, Anchor = anchor, OffR = cos(a) * rad, OffD = sin(a) * rad, T0 = t0, Trans = trans }
			if layer.Alive and m == "Melt" then
				it.Move, it.Material, it.Trans, it.T1 = MOVE.Melt, Enum.Material.Glass, 0.15, min(eff.TailAt, t0 + (finite(layer.Seconds) and layer.Seconds or 1))
				it.Rot = CFrame.Angles(pi / 2 - 0.2, hash(i, 42) * TAU, 0)
			elseif layer.Alive and m == "Bounce" then
				it.Move, it.Material, it.T1 = MOVE.Bounce, Enum.Material.SmoothPlastic, min(eff.TailAt, t0 + (finite(layer.Seconds) and layer.Seconds or 0.8))
				it.T0 = T.Impact
				it.VY, it.VH, it.Ang = (5 + 3 * hash(i, 43)) * eff.Size, (3 + 3 * hash(i, 44)) * eff.Size, a
				it.SX, it.SY = 6 + 6 * hash(i, 45), 4 + 6 * hash(i, 46)
			else -- Erupt / Wrap / anything else: up out of the ground around the target
				it.Move, it.Material = MOVE.Rise, Enum.Material.Neon
				it.TR = t0 + 0.04 * (i - 1)
				it.TS = (layer.Alive and t0 + (finite(layer.Seconds) and layer.Seconds or 0.6) * 0.6) or (T.Linger + (eff.TailAt - T.Linger) * 0.3)
				it.T1 = min(eff.TailAt, layer.Alive and t0 + (finite(layer.Seconds) and layer.Seconds or 0.6) or eff.TailAt)
				it.Rot = CFrame.fromAxisAngle(V3(-sin(a), 0, cos(a)), (m == "Wrap") and -0.5 or -0.2) * CFrame.Angles(0, hash(i, 47) * TAU, 0)
			end
			addSolid(eff, key, it)
		end
	end
end

local function addLayer(eff, layer, beams)
	local kind = layer.Kind
	if eff.Low and layer.NoLow then -- (evolved forms: a Rally's / Haste's stage rings: simple on Graphics Low)
		return
	end
	if isEmitter(layer) then
		addEmitterLayer(eff, layer)
	elseif kind == "Decal" then
		addDiscLayer(eff, layer)
	elseif kind == "Beam" then
		local allow = beams and (beams[layer] or 0) or nil
		if not eff.Low and allow ~= 0 then
			addBeamLayer(eff, layer, allow)
		end
	elseif kind == "Trail" then
		if not eff.Low then
			addTrailLayer(eff, layer)
		end
	elseif kind == "Light" then
		addLightLayer(eff, layer)
	elseif kind == "Ring" then
		addRingLayer(eff, layer)
	elseif kind == "Mesh" then
		addMeshLayer(eff, layer)
	end
end

-- (Task 11b) the charge cues of a Special whose charge is seen (>= CUE_MIN: a battle's late impact or a press's
-- backdated charge, the /fx preview; a charge cut to the render lead shows none): eff.Cue = the inhale (Hooks.Inhale at
-- its first frame) and the rim Highlight on the caster (High only, at most MAX_RIMS live: own and others' alike)
local RIM_LAYER = { Id = "Rim", Kind = "Rim" }

local function liveRims()
	local n = 0
	for _, e in ipairs(St.live) do
		n = n + (e.Rims or 0)
	end
	return n
end

local function addChargeCues(eff, pre)
	local r = eff.Recipe
	if r.Attack ~= "Special" or eff.Miss or eff.Times.Release < AttackFx.CUE_MIN then
		return
	end
	eff.Cue = true
	-- (fix round 1, M3) the prediction this effect takes over hands its rim on: it does not count against the cap
	if eff.Low or not eff.Src.Model or liveRims() - (pre and pre.Rims or 0) >= AttackFx.MAX_RIMS then
		return
	end
	local kit = take("Rim")
	if not kit then
		return
	end
	local pal = type(r.Palette) == "table" and r.Palette or {}
	local edge = typeof(pal.Edge) == "Color3" and pal.Edge or WHITE
	kit.Hl.OutlineColor = (r.Core and typeof(r.Core.RimColor) == "Color3") and r.Core.RimColor or edge
	kit.Hl.FillColor = typeof(pal.Mid) == "Color3" and pal.Mid or edge
	eff.Rims = (eff.Rims or 0) + 1
	addItem(eff, { Kind = "Rim", Kit = kit, Layer = RIM_LAYER, T0 = 0, T1 = eff.Times.Release + K.RIM_OUT, Fn = DRAW.Rim })
end

-- the signature actor (Task 11): its vfx_sig_* piece(s). Built right after the core, so the per-effect piece cap
-- (MAX_CORES) never cuts the pet's identity: Count pieces (other players' pets: Count x Density, at least 1), each with
-- its Rim copy when the actor has one, never more than the pieces left under the cap. At "Allies" puts Count pieces on
-- each ally (the Sunbeam seals); FoxFire spreads its Count over the allies instead (9 orbs: 3 / 2 / 2 / 2 on 4 allies).
-- Echo = { Count, Lag, Color, Transparency? } (fix round 1): dimmer copies trailing each piece along its path (Obsidian's
-- black-flame wings). Low quality (fix round 1, M1) builds no rim and no echo: a second see-through MeshPart per piece
-- is the phone's overdraw cost; the actor itself stays
-- (Task 11d, Studio round 3, S5) the room the Void Fangs heads have round the caster: the highest their tops may reach
-- over the floor (the caster's head + SERPENT_CLEAR: its name tag stays clear) and how far past its middle they root
-- (its half-width + SERPENT_GAP x size). From the caster model's bounding box (the floor eff.Drop under its pivot); no
-- model: a pet 2 x Drop tall, 1 stud half-width
local function roarRoom(eff)
	local top, half = 2 * eff.Drop, 1
	local m = eff.Src and eff.Src.Model
	if m and m.Parent then
		local ok, cf, size = pcall(m.GetBoundingBox, m)
		if ok and typeof(cf) == "CFrame" and typeof(size) == "Vector3" then
			top = cf.Position.Y + size.Y / 2 - (eff.S.Y - eff.Drop)
			half = max(size.X, size.Z) / 2
		end
	end
	return max(0.5, top) + K.SERPENT_CLEAR, half + K.SERPENT_GAP * eff.Size
end

local function buildActor(eff)
	local sig = eff.Recipe.Sig
	local actor = sig and sig.Actor
	if type(actor) ~= "table" or type(actor.Key) ~= "string" then
		return
	end
	local T = eff.Times
	local motion = actor.Motion
	local t0 = beatStart(eff, actor.Beat or "Charge")
	local S = eff.Size * (finite(actor.Scale) and actor.Scale or 1)
	local c = typeof(actor.Color) == "Color3" and actor.Color or WHITE
	local mat = material(actor.Material or "Neon")
	local trans = finite(actor.Transparency) and max(0, min(0.9, actor.Transparency)) or 0
	local rim = (not eff.Low and type(actor.Rim) == "table" and typeof(actor.Rim.Color) == "Color3") and actor.Rim or nil
	local echo = (not eff.Low and type(actor.Echo) == "table" and typeof(actor.Echo.Color) == "Color3") and actor.Echo or nil
	local echoes = echo and min(3, max(0, finite(echo.Count) and floor(echo.Count) or 2)) or 0
	local per = (rim and 2 or 1) + echoes
	local n = min(9, max(1, finite(actor.Count) and floor(actor.Count) or 1))
	local density = finite(eff.Recipe.Density) and eff.Recipe.Density or 1
	if density < 1 then
		n = max(1, floor(n * density + 0.5))
	end
	local room = AttackFx.MAX_CORES - eff.Cores
	local allies = min(K.MAX_ALLIES, max(1, #eff.T))
	local anchors = {}
	if actor.At == "Allies" and motion ~= "FoxFire" then
		n = min(n, floor(room / (allies * per)))
		for a = 1, allies do
			anchors[#anchors + 1] = a
		end
	else
		n = min(n, floor(room / per))
		anchors[1] = actor.At == "Target" and "Hit" or (actor.At or "Hit")
	end
	local tf = T.Linger + (eff.TailAt - T.Linger) * 0.4
	for _, anchor in ipairs(anchors) do
		for i = 1, n do
			local it = { Move = MOVE.Actor, Motion = motion, Anchor = anchor, I = i, N = n, Color = c, S = S, Material = mat, Trans = trans, T0 = t0, T1 = eff.TailAt, TF = tf, Actor = true }
			if motion == "WishRise" then -- (Studio findings round) its keep-out radius: Clear x size + the body + its own half-width
				it.Forward = finite(actor.Forward) and actor.Forward or nil
				if finite(actor.Clear) then
					it.ClearK = actor.Clear
				end
			end
			if motion == "SpiralUp" then
				it.Dive = max(0.1, T.Release - 0.15)
				it.T1 = min(eff.TailAt, T.Impact + 0.75)
				it.TF = T.Impact + (it.T1 - T.Impact) * 0.5
			elseif motion == "ChargeThrough" then
				it.T0, it.T1, it.TF = T.Travel, T.Linger + 0.2, T.Impact + 0.05
			elseif motion == "PackCharge" then
				local L = eff.Line
				it.TA = max(T.Impact, T.Travel + K.PACK_MIN)
				-- (each a beat behind the one before, all on the target at the impact; the last ones run on a little later)
				local lag = min(K.PACK_GAP * (i - 1), (it.TA - T.Travel) * 0.6)
				it.T0 = T.Travel + lag
				it.TE = it.TA + K.PACK_PAST + lag
				it.T1 = it.TE + K.PACK_FADE
				it.TF = it.TE - 0.05
				it.FHit = max(0.05, min(0.95, (eff.Hit - L.From):Dot(L.Dir) / max(0.1, L.Length)))
				it.Across = (n > 1) and ((i - (n + 1) / 2) / ((n - 1) / 2) * min(K.PACK_SPREAD * eff.Size, L.Width / 2)) or 0
			elseif motion == "Shatter" then
				it.Ang = (i - 1) / n * TAU + hash(i, 48) * 0.5
				it.Rad = (finite(actor.Radius) and actor.Radius or K.SHATTER_RADIUS) * eff.Size
				it.T1 = it.T0 + 0.7
				it.TF = it.T0 + 0.25
			elseif motion == "Eclipse" then
				it.T1 = min(eff.TailAt, T.Impact + 0.7)
			elseif motion == "Sweep" then -- (the pass, 0.64 s, centred on the impact; with a cut charge from the first frame)
				it.TP0 = max(it.T0, T.Impact - 0.32)
				it.TP1 = it.TP0 + 0.64
				it.T1 = min(eff.TailAt, it.TP1 + 0.25) -- (Task 11c R1: a quicker fade over the far end)
				it.TF = it.TP1
			elseif motion == "Seal" or motion == "FoxFire" then
				it.TF = T.Linger + (eff.TailAt - T.Linger) * 0.5
				if motion == "FoxFire" then -- (round robin: orb i circles ally Ally, as the J-th of its M orbs)
					it.Ally = (i - 1) % allies + 1
					it.J = floor((i - 1) / allies)
					it.M = floor((n - it.Ally) / allies) + 1
				end
			elseif motion == "RingRise" then
				local a = (i - 1) / n * TAU
				if actor.Gap then
					-- (Studio findings round: Lava Slam) the n spikes share the ring but the slot facing the caster (OffD < 0:
					-- toward it, angle -pi/2) stays open: the target's flinch shows through it
					local open = TAU / (n + 1)
					a = -pi / 2 + open / 2 + (TAU - open) * (i - 0.5) / n
				end
				it.Move = MOVE.Rise
				-- (Task 11c R5: the ring's Radius, studs x size: Lava Slam's spikes spread so the target shows between them)
				local rad = (finite(actor.Radius) and actor.Radius or 2.5) * eff.Size
				-- (evolved forms) ReachK: on the area itself, x its real radius, in the middle of its Band (Rockspire, Fissure)
				if finite(actor.ReachK) then
					rad = eff.Reach * actor.ReachK + (eff.Band or 0) / 2
				end
				it.OffR, it.OffD = cos(a) * rad, sin(a) * rad
				it.TR = t0 + 0.03 * (i - 1)
				it.TS = T.Linger + (eff.TailAt - T.Linger) * 0.3
				it.Rot = CFrame.fromAxisAngle(V3(-sin(a), 0, cos(a)), 0.25)
			elseif motion == "RiseRoar" then -- a fan: the outer heads turn out a little, the middle one stands tallest
				local k = i - (n + 1) / 2
				it.FanK = k -- (Task 11d S5: the fan's spacing follows the fitted heads, MOVE.Actor)
				it.Yaw = k * 0.35
				if abs(k) < 0.25 then
					it.S = S * 1.15
				end
				it.STop = S * 1.15
				it.HMax, it.Back = roarRoom(eff)
			end
			if rim then
				local r = {}
				for key, v in pairs(it) do
					r[key] = v
				end
				r.Move = (it.Move == MOVE.Actor) and MOVE.ActorRim or it.Move
				r.Color, r.Material, r.Rim = rim.Color, Enum.Material.Neon, true
				r.Trans = finite(rim.Transparency) and rim.Transparency or 0.35
				r.RimScale = finite(rim.Scale) and rim.Scale or 1.12
				r.RimBack = finite(rim.Back) and rim.Back or 0.25
				addSolid(eff, actor.Key, r)
			end
			if it.Move == MOVE.Actor then
				for j = 1, echoes do
					local e = {}
					for key, v in pairs(it) do
						e[key] = v
					end
					e.Move, e.Echo, e.Color, e.Material = MOVE.ActorEcho, true, echo.Color, Enum.Material.Neon
					e.Lag = (finite(echo.Lag) and echo.Lag or 0.06) * j
					e.Trans = min(0.9, (finite(echo.Transparency) and echo.Transparency or 0.45) + 0.18 * (j - 1))
					e.EchoScale = 1 - 0.06 * j
					addSolid(eff, actor.Key, e)
				end
			end
			addSolid(eff, actor.Key, it)
		end
	end
end

----------------------------------------------------------------------
-- Poses
----------------------------------------------------------------------
-- `base` (optional, Vector3): the unit's drawn position before the pose; a Pounce leap (seg.Landing) then reaches only
-- from there to its landing spot, so a base the server slides to the target does not carry the pet past it (Task 10)
-- (battle-feel T2) a segment's Until holds its end pose until then (DashIn at the edge until its DashBack); its Forward
-- (pose studs) is an offset along the LookVector the pose does not carry itself (a flurry's bite from the edge)
local function poseSample(entry, now, base)
	local best = nil
	for _, s in ipairs(entry.Segs) do
		if now >= s.T0 and (now < s.T0 + s.Dur or s.Hold or (s.Until and now < s.Until)) then
			best = s
		end
	end
	if not best then
		return nil
	end
	local el = now - best.T0
	if best.StopAt then
		el = el - min(max(0, now - best.StopAt), best.StopDur)
	end
	local reach = best.Reach
	if best.Landing and typeof(base) == "Vector3" then
		local left = (best.Landing - flat(base)):Dot(best.Dir)
		reach = max(0, min(K.LEAP_MAX, finite(left) and left or 0)) / best.Scale
	end
	return best.Name, clamp01(el / best.Dur), best.Ranged == true, best.Amp, reach, best.Forward
end

local function poseActive(entry, at)
	for _, s in ipairs(entry.Segs) do
		if s.Hold or at < s.T0 + s.Dur or (s.Until and at < s.Until) then
			return true
		end
	end
	return false
end

local function setPoses(unit, segs, now)
	if unit == nil or #segs == 0 then
		return
	end
	local prio = 0
	for _, s in ipairs(segs) do
		prio = max(prio, K.PRIO[s.Name] or 1)
	end
	local old = St.poses[unit]
	if old and old.Prio > prio and poseActive(old, segs[1].T0) then
		return -- a higher pose still plays then (a KO'd pet never strikes; an attack is not cut by a flinch)
	end
	local entry = { Segs = segs, Prio = prio }
	if old and poseActive(old, now) then
		entry.Prev = old -- crossfade from the old timeline, still animating
		entry.SwitchAt = max(now, segs[1].T0)
	end
	St.poses[unit] = entry
end

-- a model's oriented bounding box -> its centre's offset from `origin` along the flat unit `dir` and its half-length
-- along it (nil without a model)
local function spanAlong(model, origin, dir)
	if not model then
		return nil
	end
	local ok, cf, size = pcall(model.GetBoundingBox, model)
	if not ok or typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then
		return nil
	end
	local half = 0.5 * (abs(dir:Dot(cf.RightVector)) * size.X + abs(dir:Dot(cf.UpVector)) * size.Y + abs(dir:Dot(cf.LookVector)) * size.Z)
	return (cf.Position - origin):Dot(dir), half
end

-- the melee leap's forward reach (Task 9 player decision: the jump lands on the target): from the caster's front edge
-- to the target's near edge along the ground, minus K.LEAP_MARGIN, clamped 0 .. K.LEAP_MAX world studs; returned in
-- the caster's pose units (PetPoses studs at scale 1: the drawing multiplies the body offset by the model's PB_Scale).
-- Without models the pivots stand in with no size. nil = no target (the fixed hop)
-- the caster's front edge -> the target's near edge along the ground minus K.LEAP_MARGIN (world studs, unclamped; nil when
-- the two stand on one spot) and the caster's PB_Scale (battle-feel T2: the dash reads it unclamped by LEAP_MAX)
local function gapOf(src, tgt)
	local s = src.Model and tonumber(src.Model:GetAttribute("PB_Scale")) or 1
	if not finite(s) or s <= 0 then
		s = 1
	end
	local d = flat(tgt.Last - src.Last)
	local dist = d.Magnitude
	if dist < 0.05 then
		return nil, s
	end
	local u = d / dist
	local c0, ch = spanAlong(src.Model, src.Last, u)
	local t0, th = spanAlong(tgt.Model, src.Last, u)
	local front = (c0 or 0) + (ch or 0)
	local near = (t0 or dist) - (th or 0)
	return near - front - K.LEAP_MARGIN, s
end

function AttackFx.LeapReach(src, tgt)
	if not (src and tgt and typeof(src.Last) == "Vector3" and typeof(tgt.Last) == "Vector3") then
		return nil
	end
	local world, s = gapOf(src, tgt)
	if not world then
		return 0
	end
	return max(0, min(K.LEAP_MAX, world)) / s
end

-- (battle-feel T1) where a bite lands on a target: its near edge along the flat line from the caster's pivot through the
-- target's, at the caster's height (src.Last.Y), never past the caster. The target's box comes from the aim cache (read
-- once per model) placed on its pivot this frame, else from the model, else the pivot stands in with no size.
-- src / tgt = { Model?, Last = Vector3, CF? }; nil without both points
function AttackFx.BitePoint(src, tgt)
	if not (type(src) == "table" and type(tgt) == "table" and typeof(src.Last) == "Vector3" and typeof(tgt.Last) == "Vector3") then
		return nil
	end
	local d = flat(tgt.Last - src.Last)
	local dist = d.Magnitude
	if dist < 0.05 then
		return src.Last
	end
	local u = d / dist
	local t0, th
	local m = tgt.Model
	local c = m and aimCache[m]
	if c and c.Box and typeof(tgt.CF) == "CFrame" then
		local bcf = tgt.CF * c.Box
		local size = c.Size
		th = 0.5 * (abs(u:Dot(bcf.RightVector)) * size.X + abs(u:Dot(bcf.UpVector)) * size.Y + abs(u:Dot(bcf.LookVector)) * size.Z)
		t0 = (bcf.Position - src.Last):Dot(u)
	else
		t0, th = spanAlong(m, src.Last, u)
	end
	local along = max(0, (t0 or dist) - (th or 0))
	return src.Last + u * along
end

local function schedulePoses(eff, now)
	local r = eff.Recipe
	local A = r.Attack
	local T = eff.Times
	local st = eff.Start
	local ranged = A == "Ranged"
	local segs = {}
	local offensive = eff.Path ~= "Self" and eff.Path ~= "Allies"
	if r.Twist then -- (evolved forms) a form's delayed hit: the caster does not cast again; whoever it reached flinches (To = the struck, BattleController)
		offensive = eff.Path ~= "Allies"
	elseif eff.Dashed and (A == "Melee" or A == "Element") then
		-- (battle-feel T2) the dash (AttackFx.Dash, scheduled from the Windup / the Hit; feel-balance: a melee pet's Element)
		-- is this bite's body motion: no Windup / Strike / Cast segment here; the victims' Hurt below stays
	elseif A == "Melee" or A == "Ranged" or (A == "Element" and eff.Area ~= "Circle") or (A == "Special" and r.Kind == "Pounce") then
		if T.Release > 0.04 then
			segs[#segs + 1] = { Name = "Windup", T0 = st, Dur = T.Release, Ranged = ranged }
		end
		if ranged then
			-- a shot, never the melee lunge (player note 1): rear back (the ranged Windup), then Shoot = the head snaps
			-- forward to loose the shot while the body kicks back; the pet stays at its spot
			segs[#segs + 1] = { Name = "Shoot", T0 = st + T.Release, Dur = K.SHOOT, Ranged = true }
		else
			-- (Task 10) the Pounce leaps across the whole gap like the melee: a longer flight, so its Strike may run longer
			-- (POUNCE_DUR_MAX) for the landing (p 0.26) to fall on the slam
			local pounce = A == "Special" and r.Kind == "Pounce"
			local dur = max(0.45, min(pounce and K.POUNCE_DUR_MAX or 0.9, (T.Impact - T.Release) / 0.26))
			-- the leap (player note (a)): it lands on the target at the impact (PetPoses Strike lands at p 0.26); a little
			-- longer and higher per rarity band (Amp). Melee and Pounce: the Reach is the gap to the target, so the leap
			-- lands ON it (Task 9 player decision; Task 10 for the Pounce); an element Cone / Line keeps the short fixed hop
			-- (a blast from the spot)
			local seg = { Name = "Strike", T0 = st + T.Release, Dur = dur, StopAt = (not eff.Miss) and (st + T.Impact) or nil, StopDur = AttackFx.HIT_STOP,
				Amp = 1 + K.LEAP_STEP * ((tonumber(r.Band) or 1) - 1), Reach = (A == "Melee" or pounce) and AttackFx.LeapReach(eff.Src, eff.Targets[1]) or nil }
			if pounce and seg.Reach and eff.Src.Last then
				-- the landing in the world: the server moves a pouncing pet to its target (BattleSim), so its drawn base slides
				-- there at the impact; AttackFx.Pose(unit, base) then shrinks the leap by what the base has covered, and the
				-- pet stays on its landing spot instead of being carried past the target and back
				local s = eff.Src.Model and tonumber(eff.Src.Model:GetAttribute("PB_Scale")) or 1
				if not finite(s) or s <= 0 then
					s = 1
				end
				seg.Landing, seg.Dir, seg.Scale = flat(eff.Src.Last) + eff.Dir * (seg.Reach * s), eff.Dir, s
			end
			segs[#segs + 1] = seg
		end
	elseif A == "Special" or A == "Element" then
		-- Cast's release (p 0.66 .. 0.74) lands as the release beat ends
		segs[1] = { Name = "Cast", T0 = st, Dur = max(0.6, min(1.6, T.Travel / 0.7)) }
		-- (battle-feel T3) a special's impact holds the caster still for SPECIAL_HIT_STOP (the weight of the hit): the Cast
		-- runs that much longer so it still plays out after the freeze; one that has played out before the impact (a
		-- charge cut to a late event) holds its last frame until the freeze ends
		if A == "Special" and not eff.Miss and specialStop() > 0 then
			local seg = segs[1]
			seg.StopAt, seg.StopDur = st + T.Impact, AttackFx.SPECIAL_HIT_STOP
			seg.Until = max(seg.T0 + seg.Dur, seg.StopAt) + seg.StopDur
		end
	elseif A == "Hurt" then
		segs[1] = { Name = "Hurt", T0 = st, Dur = K.HURT }
	elseif A == "Ko" then
		segs[1] = { Name = "Ko", T0 = st, Dur = K.KO, Hold = true }
	elseif A == "Victory" then
		segs[1] = { Name = "Victory", T0 = st, Dur = K.VICTORY }
	end
	if not r.Twist then
		setPoses(eff.Unit, segs, now)
	end
	if offensive and not eff.Miss and (A == "Melee" or A == "Ranged" or A == "Element" or A == "Special") then
		-- (battle-feel T3) a special's victims flinch frozen for SPECIAL_HIT_STOP at the impact, like its caster
		local stop = (A == "Special" and not r.Twist) and specialStop() or 0
		for _, side in ipairs(eff.Targets) do
			if side.Unit ~= nil and side.Unit ~= eff.Unit then
				local seg = { Name = "Hurt", T0 = st + T.Impact, Dur = K.HURT }
				if stop > 0 then
					seg.StopAt, seg.StopDur = st + T.Impact, stop
				end
				setPoses(side.Unit, { seg }, now)
			end
		end
	end
end

----------------------------------------------------------------------
-- Effects: lifecycle
----------------------------------------------------------------------
local function callHook(name, ...)
	local fn = AttackFx.Hooks[name]
	if type(fn) == "function" then
		local ok, err = pcall(fn, ...)
		if not ok then
			warnOnce("hook" .. name, "hook " .. name .. " failed: " .. tostring(err))
		end
	end
end

local function release(eff)
	for _, it in ipairs(eff.Items) do
		if it.Kit then
			give(it.Kit)
			it.Kit = nil
		end
	end
	eff.Items = {}
	eff.Emitters, eff.Beams, eff.Trails, eff.Lights, eff.Cores, eff.Rims = 0, 0, 0, 0, 0, 0
end

-- the sound and the battle dim an effect started end with its beats
local function endCues(eff)
	-- (Task 11b) an inhale still rising ends with its effect (a real effect that took a press's charge over took its
	-- token: the prediction gives none back)
	if eff.InhaleToken ~= nil then
		local token = eff.InhaleToken
		eff.InhaleToken = nil
		callHook("Hush", token)
	end
	-- (Task 11) a signature that dimmed the battle (Eclipse Nova) gives the light back whenever it ends: its own end, a
	-- Cancel (the caster swapped out / gone), ClearAll (the battle torn down) or a failed build / step
	if eff.DimToken ~= nil then
		local token = eff.DimToken
		eff.DimToken = nil
		callHook("Undim", token)
	end
end

-- (evolved forms) a Rally's bigger pet: k, or back to its size (a look only: the attribute and Hooks.AuraScale, whatever draws the pet reads them)
local function setAuraScale(eff, k)
	local m = eff.Src and eff.Src.Model
	if m then
		pcall(m.SetAttribute, m, "AuraScale", k)
	end
	callHook("AuraScale", eff.Unit, k)
end

local function resetAuraScale(eff)
	if eff.ScaleOn then
		eff.ScaleOn = nil
		setAuraScale(eff, 1)
	end
end

local function finish(eff)
	for i = #St.live, 1, -1 do
		if St.live[i] == eff then
			table.remove(St.live, i)
		end
	end
	resetAuraScale(eff)
	if eff.Pre and St.pre[eff.Unit] == eff then
		St.pre[eff.Unit] = nil
	end
	local pose = St.poses[eff.Unit]
	if pose and pose.PreOf == eff then
		St.poses[eff.Unit] = nil -- (a predicted charge's held pose never outlives it)
	end
	release(eff)
	endCues(eff)
end

-- Low quality: drop the Beams / Trails / bloom of a live effect at once
local function strip(eff)
	eff.Low = true
	-- (attack effects, 2026-11-01) and no afterglow: a tail ends at the next Update (evolved forms: no aura, the pet back to its size)
	eff.EndRel = min(eff.EndRel, eff.TailAt)
	eff.End = eff.Start + eff.EndRel
	eff.AuraRel, eff.Scale = nil, nil
	resetAuraScale(eff)
	local keep = {}
	for _, it in ipairs(eff.Items) do
		local layer = it.Layer
		local drop = it.Kind == "Beam" or it.Kind == "Trail" or it.Kind == "Rim" or (it.Kind == "Light" and layer and (layer.Pulse or layer.Id == "Bloom"))
		if drop then
			give(it.Kit)
			it.Kit = nil
			if it.Kind == "Rim" then
				eff.Rims = 0
			elseif it.Kind == "Beam" then
				eff.Beams = eff.Beams - 1
			elseif it.Kind == "Trail" then
				eff.Trails = eff.Trails - 1
			else
				eff.Lights = eff.Lights - 1
			end
		else
			keep[#keep + 1] = it
		end
	end
	eff.Items = keep
end

local function effectiveQuality()
	if St.forced then
		return St.forced
	end
	local gq = dep("GraphicsQuality")
	if gq and type(gq.Effective) == "function" then
		local ok, m = pcall(gq.Effective)
		if ok and m == "Low" then
			return "Low"
		end
	end
	return "High"
end

local function applyQuality()
	local q = effectiveQuality()
	if q == St.mode then
		return q
	end
	St.mode = q
	if q == "Low" then
		for _, eff in ipairs(St.live) do
			strip(eff)
		end
		for i = #St.streaks, 1, -1 do -- (battle-feel T2: no dash streak on Low)
			local sk = St.streaks[i]
			St.streaks[i] = nil
			give(sk.Kit)
		end
	end
	return q
end

local function stepEffect(eff, now)
	local t = now - eff.Start
	eff.Dt = max(0, min(0.1, now - (eff.LastNow or now)))
	eff.LastNow = now
	if t < 0 then
		return
	end
	if eff.Scale and not eff.ScaleOn and t >= eff.Times.Impact then -- (evolved forms) a Rally's bigger pet, from its impact
		eff.ScaleOn = true
		setAuraScale(eff, eff.Scale)
	end
	if eff.Tail then -- (attack effects, 2026-11-01) what is left lies where it fell: the units' moves no longer carry it
		if eff.AuraRel then -- (evolved forms: an aura follows its pet)
			refresh(eff)
		end
		for _, it in ipairs(eff.Items) do
			if it.Kit then
				it.Fn(eff, it, t)
			end
		end
		return
	end
	refresh(eff)
	eff.CorePos = corePosOf(eff, t)
	local r = eff.Recipe
	if not eff.Dimmed then
		eff.Dimmed = true
		-- (Task 11) a signature's battle dim (own pet only): from the first frame to DimWorld seconds after the impact. The
		-- hook gets a token of its own per effect (an older cast's end never lifts a newer cast's dim) and the caster's
		-- unit (BattleController ends that dim early on the caster's KO); finish calls Hooks.Undim(token) whenever the
		-- effect ends, so a cancelled or torn-down effect never leaves the battle dark. A MISSED cast never dims (fix
		-- round 1, M3: a dim + the black sun dropping read as a hit)
		if eff.Mine and not eff.Miss and not eff.Pre and r.Sig and finite(r.Sig.DimWorld) and r.Sig.DimWorld >= 0 then
			St.dimSeq = St.dimSeq + 1
			eff.DimToken = St.dimSeq
			callHook("DimWorld", max(0.2, eff.Times.Impact - t) + r.Sig.DimWorld, eff.DimToken, eff.Unit)
		end
	end
	-- (Task 11b) the inhale under a seen charge: Hooks.Inhale(seconds to the release, token, mine) at the first frame. A
	-- real effect that took a press's predicted charge over keeps its token: the call retimes the same sound (no restart)
	if eff.Cue and not eff.Inhaled then
		eff.Inhaled = true
		local left = (eff.Pre and eff.CueSeconds or eff.Times.Release) - t
		if left > 0.05 then
			if eff.InhaleToken == nil then
				St.cueSeq = St.cueSeq + 1
				eff.InhaleToken = St.cueSeq
			end
			callHook("Inhale", left, eff.InhaleToken, eff.Mine)
		elseif eff.InhaleToken ~= nil then
			-- (a press's inhale taken over by a Special whose release is now: it ends here)
			local token = eff.InhaleToken
			eff.InhaleToken = nil
			callHook("Hush", token)
		end
	end
	if not eff.Punched and t >= eff.Times.Impact then
		eff.Punched = true
		if eff.Mine and not eff.Miss and not eff.Pre then
			-- (attack effects, 2026-11-01) every own attack kicks; a basic hit waits its Gap since the last basic kick (a Special is never swallowed)
			local kick = r.CameraPunch
			if kick and (not kick.Basic or not St.lastBasicKick or now - St.lastBasicKick >= kick.Gap) then
				if kick.Basic then
					St.lastBasicKick = now
				end
				callHook("Punch", min(AttackFx.PUNCH_MAX, kick.Amount + (eff.Crit and kick.Crit or 0)), kick.Seconds)
			end
			if r.ScreenGlow then
				callHook("ScreenGlow", (r.Core and r.Core.RimColor) or (r.Palette and r.Palette.Edge) or WHITE, 0.35)
			end
		end
	end
	for _, it in ipairs(eff.Items) do
		if it.Kit then
			it.Fn(eff, it, t)
		end
	end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
local function sideOf(s)
	if type(s) ~= "table" then
		return nil
	end
	local side = { Unit = s.Unit, Model = (typeof(s.Model) == "Instance") and s.Model or nil, Pos = (typeof(s.Pos) == "Vector3") and s.Pos or nil }
	if not pointOf(side) then
		return nil
	end
	return side
end

-- (battle-feel T1) one downward ray under the target's centre at the Play (Config.Battle.Feel.Aim.FloorRay): the real floor
-- there, believed within AttackFx.FLOOR_RAY_MAX of eff.FloorY (ctx.Ground); the drawn battle (workspace.ClientBattle: the
-- units, the boss, these kits) and the local character are skipped. Never per frame.
local floorParams = nil
local function refineFloor(eff, side)
	local aim = feelOf("Aim")
	if not (aim and aim.FloorRay == true and finite(eff.FloorY)) then
		return
	end
	local at = aimOf(side)
	if typeof(at) ~= "Vector3" then
		return
	end
	if not floorParams then
		floorParams = RaycastParams.new()
		floorParams.FilterType = Enum.RaycastFilterType.Exclude
	end
	local skip = {}
	local cb = Workspace:FindFirstChild(K.PARENT)
	if cb then
		skip[#skip + 1] = cb
	end
	if St.folder and St.folder.Parent and St.folder.Parent ~= cb then
		skip[#skip + 1] = St.folder
	end
	local lp = Players and Players.LocalPlayer
	local ch = lp and lp.Character
	if ch then
		skip[#skip + 1] = ch
	end
	floorParams.FilterDescendantsInstances = skip
	local ok, hit = pcall(Workspace.Raycast, Workspace, at + UP * 1, V3(0, -K.FLOOR_RAY, 0), floorParams)
	-- (an anchored part or the terrain: another player's character standing there is not the floor)
	local inst = ok and hit and hit.Instance
	local solid = inst ~= nil and inst:IsA("BasePart") and (inst.Anchored or inst:IsA("Terrain"))
	if solid and typeof(hit.Position) == "Vector3" and abs(hit.Position.Y - eff.FloorY) <= AttackFx.FLOOR_RAY_MAX then
		eff.FloorY = hit.Position.Y
	end
end

local function resolve(ctx, distance, step)
	local Cat = dep("AttackFxCatalog")
	if not (Cat and type(Cat.Resolve) == "function") then
		return nil
	end
	local rarity = ctx.Rarity
	if step then
		local band = Cat.BandOf(rarity)
		rarity = K.BAND_RARITY[max(1, band - 1)]
	end
	local ok, r = pcall(Cat.Resolve, {
		Element = ctx.Element, Attack = ctx.Attack, Kind = ctx.Kind, Shape = ctx.Shape, Rarity = rarity, Stage = ctx.Stage,
		PetId = ctx.PetId, Mine = ctx.Mine == true, Distance = distance,
		Form = ctx.Form, Twist = ctx.Twist, Seconds = (ctx.Pre ~= true) and ctx.Seconds or nil, -- (a predicted charge's Seconds are its wait)
	})
	if ok and type(r) == "table" and type(r.Beats) == "table" and type(r.Core) == "table" then
		return r
	end
	return nil
end

-- every sheet / strip the recipe uses has an id (else the caller falls back)
local function texturesOk(r)
	local ids = dep("TextureIds")
	if type(ids) ~= "table" then
		return false
	end
	local function ok(key)
		if key == nil then
			return true
		end
		local id = ids[key]
		return type(id) == "number" and id > 0
	end
	for _, layer in ipairs(r.Layers or {}) do
		if not ok(layer.Texture) then
			return false
		end
	end
	return ok(type(r.Alive) == "table" and r.Alive.Texture or nil)
end

-- -> start, charge, release, travel, late (seconds the impact lands AFTER dueAt: only a recipe's MinTravel, a basic
-- ranged shot's flight, is never cut, so the shot is always seen crossing the gap: player note 1)
local function fitTimes0(b, now, dueAt)
	local C, R, Tr = b.Charge or 0, b.Release or 0, b.Travel or 0
	local keep = finite(b.MinTravel) and max(0, min(Tr, b.MinTravel)) or 0
	local start, late = now, 0
	if finite(dueAt) then
		local need = C + R + Tr
		local avail = dueAt - now
		if avail >= need then
			start = dueAt - need -- (may be a little ahead: the effect waits, then lands exactly on the event)
		else
			-- late: shorten the charge first, then the travel (down to its MinTravel), then the release; impact never
			-- after the event, except by what the MinTravel keeps
			local cut = need - max(0, avail)
			local c = min(C, cut)
			C, cut = C - c, cut - c
			c = min(Tr - keep, cut)
			Tr, cut = Tr - c, cut - c
			c = min(R, cut)
			R, cut = R - c, cut - c
			late = cut
		end
	end
	return start, C, R, Tr, late
end

-- (Task 11b) `lateMax` (a battle Special, no press): the charge the cut took is given back, up to lateMax seconds, and
-- the impact lands that much later (late += min(authored charge - the charge the lead left, lateMax); the release and
-- the travel stay as the lead fits them). `from` (a press's predicted charge, a clock time <= now): the charge is
-- backdated to it (start = from) and grows by the time since, so the impact stays on dueAt
local function fitTimes(b, now, dueAt, lateMax, from)
	local start, C, R, Tr, late = fitTimes0(b, now, dueAt)
	if finite(from) and from < start then
		C = C + (start - from)
		start = from
		-- a quick round trip: the charge still reads (>= PRE_MIN_CHARGE before the release), the travel then the release
		-- give way; the impact stays on dueAt
		local short = min(K.PRE_MIN_CHARGE, C + R + Tr) - C
		if short > 0 then
			local c = min(Tr, short)
			Tr, short, C = Tr - c, short - c, C + c
			c = min(R, short)
			R, C = R - c, C + c
		end
		-- (battle-feel T3, spec decision 6) a cast-driven Special (`from` + `lateMax`: TravelHold): the charge stays
		-- backdated, the travel the fit cut is given back up to lateMax, the impact that much after dueAt
		if finite(lateMax) and lateMax > 0 then
			local back = max(0, min((b.Travel or 0) - Tr, lateMax))
			Tr, late = Tr + back, late + back
		end
	elseif finite(lateMax) and lateMax > 0 then
		local extra = max(0, min((b.Charge or 0) - C, lateMax))
		C = C + extra
		late = late + extra
	end
	return start, C, R, Tr, late
end

-- (Task 11b) an effect's counts from the kits it still holds (after a hand-over)
local function recount(eff)
	local n = { Emitter = 0, Beam = 0, Trail = 0, Light = 0, Rim = 0 }
	local cores = 0
	for _, it in ipairs(eff.Items) do
		local kit = it.Kit
		if kit then
			if kit.Kind == "Core" then
				cores = cores + 1
			elseif n[kit.Kind] then
				n[kit.Kind] = n[kit.Kind] + 1
			end
		end
	end
	eff.Emitters, eff.Beams, eff.Trails, eff.Lights, eff.Rims, eff.Cores = n.Emitter, n.Beam, n.Trail, n.Light, n.Rim, cores
end

-- (attack effects, 2026-11-01) the beats are over: only the Linger items stay on; every other kit goes back and the cues end
local function startTail(eff, now)
	eff.Tail = true
	eff.TailSince = now
	local keep = {}
	for _, it in ipairs(eff.Items) do
		if it.Lingers and it.Kit then
			keep[#keep + 1] = it
		elseif it.Kit then
			give(it.Kit)
			it.Kit = nil
		end
	end
	eff.Items = keep
	recount(eff)
	endCues(eff)
end

-- (evolved forms) the aura ends now, whatever is left of it: the kits it held go back, the pet is its size again; the beats, if they still run, play on
local function endAura(eff)
	local keep = {}
	for _, it in ipairs(eff.Items) do
		if it.Lingers and it.Kit then
			give(it.Kit)
			it.Kit = nil
		elseif it.Kit then
			keep[#keep + 1] = it
		end
	end
	eff.Items = keep
	recount(eff)
	eff.AuraRel, eff.Scale = nil, nil
	eff.EndRel = eff.TailAt
	eff.End = eff.Start + eff.TailAt
	resetAuraScale(eff)
end

-- at most MAX_TAILS at once: the oldest makes room (evolved forms: an aura ends with its buff, it never makes room)
local function trimTails()
	while true do
		local n, oldest = 0, nil
		for _, e in ipairs(St.live) do
			if e.Tail and not e.AuraRel then
				n = n + 1
				if not oldest or e.TailSince < oldest.TailSince then
					oldest = e
				end
			end
		end
		if n <= AttackFx.MAX_TAILS then
			return
		end
		pcall(finish, oldest)
	end
end

-- (Task 11b) a charge given up (shattered, or what the real effect did not take over): out of St.pre, its streams stop
-- now, its rim / light fade, the particles already out live on; gone RETIRE seconds from now
local function retire(eff, now)
	if St.pre[eff.Unit] == eff then
		St.pre[eff.Unit] = nil
	end
	eff.Pre = nil
	eff.Retired = true
	if eff.InhaleToken ~= nil then
		local token = eff.InhaleToken -- (fix round 1, M4) a charge given up hushes the inhale it still holds
		eff.InhaleToken = nil
		callHook("Hush", token)
	end
	local tRel = max(0, now - eff.Start)
	eff.Times.Release = min(eff.Times.Release, tRel)
	for _, it in ipairs(eff.Items) do
		if it.Kind == "Emitter" and it.Mode == "Stream" then
			it.T1 = min(it.T1, tRel)
		elseif it.Kind == "Light" then
			it.T1 = min(it.T1, tRel + 0.15)
		end
	end
	eff.TailAt = min(eff.TailAt, tRel + K.RETIRE)
	eff.EndRel = eff.TailAt
	eff.End = eff.Start + eff.EndRel
end

-- (Task 11b) the real Special takes over its press's predicted charge: each of its items with a twin in the prediction
-- (same kind + layer Id: the charge glow / motes, a charge light, the rim) takes the twin's kit (the particles already
-- out, the rim's strength: nothing restarts; its own fresh kit goes back to the pool); the inhale's token passes on
-- (the sound is retimed, not restarted); the rest of the prediction retires
local function adopt(eff, pre, now)
	local twins = {}
	for _, it in ipairs(pre.Items) do
		local id = it.Kit and it.Layer and it.Layer.Id
		if id ~= nil then
			twins[it.Kind .. "|" .. tostring(id)] = it
		end
	end
	for _, it in ipairs(eff.Items) do
		local id = it.Kit and it.Layer and it.Layer.Id
		local old = id ~= nil and twins[it.Kind .. "|" .. tostring(id)] or nil
		if old and old.Kit and old.Kit.Kind == it.Kit.Kind then
			give(it.Kit)
			it.Kit, old.Kit = old.Kit, nil
			it.Acc = old.Acc or it.Acc
			it.Fired = old.Fired
			it.Adopted = true
			eff.Adopted = (eff.Adopted or 0) + 1
		end
	end
	if pre.InhaleToken ~= nil then
		eff.InhaleToken = pre.InhaleToken
		pre.InhaleToken = nil
	end
	eff.PreStart = pre.Start
	recount(pre)
	retire(pre, now)
end

-- (evolved forms) ctx.Line as the pack reads it: { From, Dir, Right, Length, Width }, all in the world
local function chargeLineOf(eff, line)
	if type(line) == "table" and finite(line.X0) and finite(line.Z0) and finite(line.Angle) and finite(line.Length) then
		local dir = V3(cos(line.Angle), 0, sin(line.Angle))
		return { From = V3(line.X0, eff.S.Y, line.Z0), Dir = dir, Right = dir:Cross(UP), Length = line.Length, Width = finite(line.Width) and line.Width or 4 }
	end
	local from = eff.S - eff.Dir * K.PACK_BEHIND
	local gap = flat(eff.Hit - eff.S).Magnitude
	return { From = from, Dir = eff.Dir, Right = eff.Right, Length = K.PACK_BEHIND + gap + K.PACK_PAST_TARGET, Width = 4 }
end

-- (Task 11b) the predicted charge's pose: Cast (a Pounce: its Windup) held at PRE_CAST_P / PRE_WINDUP_P until the real
-- effect's poses replace it (crossfade) or the charge shatters (Recoil)
local function preparePose(eff, now)
	local pounce = eff.Kind == "Pounce"
	local dur = pounce and 1 or 0.6
	local p = pounce and K.PRE_WINDUP_P or K.PRE_CAST_P
	setPoses(eff.Unit, { { Name = pounce and "Windup" or "Cast", T0 = now, Dur = dur, StopAt = now + dur * p, StopDur = K.PRE_HOLD + 1, Hold = true } }, now)
	local entry = St.poses[eff.Unit]
	if entry then
		entry.PreOf = eff
	end
end

----------------------------------------------------------------------
-- (battle-feel T2, spec decisions 1 + 3) the melee dash: a pose pair on the unit, nothing on the wire. The server keeps
-- the unit at its rest spot (Damage.Standoff out); DashIn runs it to the target's near edge so the run ends on the
-- landing (the hit), it bites (today's HIT_STOP freeze), holds Bite + Hold, and DashBack hops it home. A faster tempo
-- than Melee.FlurryBelow stays in: the next bite is a Strike lunge of Melee.Lunge on top of the edge (Forward).
----------------------------------------------------------------------
local function streakOff(i)
	local sk = St.streaks[i]
	table.remove(St.streaks, i)
	if sk then
		give(sk.Kit)
	end
end

-- one pooled Trail kit (fx_speedlines) riding the dashing pet over its run, High only, at most Melee.StreakMax at once:
-- my pet's first (at the cap it takes the oldest other pet's) -> taken?
local function streakFor(unit, model, t0, t1, mine)
	local M = feelOf("Melee")
	if not (M and M.Streak ~= false and model and model.Parent) or effectiveQuality() == "Low" then
		return false
	end
	for i = #St.streaks, 1, -1 do
		if St.streaks[i].Unit == unit then
			streakOff(i)
		end
	end
	local cap = finite(M.StreakMax) and M.StreakMax or 4
	if #St.streaks >= cap then
		local other = nil
		for i, sk in ipairs(St.streaks) do
			if not sk.Mine then
				other = i
				break
			end
		end
		if not mine or not other then
			return false
		end
		streakOff(other)
	end
	local kit = take("Trail")
	if not kit then
		return false
	end
	local tr = kit.Trail
	tr.Enabled = false
	local ok, cf = pcall(model.GetPivot, model)
	if ok and typeof(cf) == "CFrame" then
		kit.Root.CFrame = CFrame.new(cf.Position + UP * K.LEAP_TRAIL_UP)
	end
	pcall(tr.Clear, tr)
	local ids = dep("TextureIds")
	local id = type(ids) == "table" and ids.fx_speedlines or nil
	tr.Color = ColorSequence.new(WHITE)
	tr.Transparency = NumberSequence.new({ kp(0, mine and K.STREAK_TRANS.Mine or K.STREAK_TRANS.Other), kp(1, 1) })
	tr.WidthScale = NumberSequence.new({ kp(0, 1), kp(1, 0.2) })
	tr.Lifetime = K.STREAK_LIFE
	tr.LightEmission = 0.6
	tr.LightInfluence = 0
	tr.FaceCamera = true
	tr.Texture = id and ("rbxassetid://" .. tostring(id)) or ""
	tr.TextureMode = Enum.TextureMode.Stretch
	kit.A0.Position = V3(0, K.STREAK_HALF, 0)
	kit.A1.Position = V3(0, -K.STREAK_HALF, 0)
	St.streaks[#St.streaks + 1] = { Kit = kit, Unit = unit, Model = model, T0 = t0, T1 = t1, Mine = mine == true }
	return true
end

-- the streaks ride their pets (once a frame; no Instance made, the kits are the pool's)
local function stepStreaks(now)
	for i = #St.streaks, 1, -1 do
		local sk = St.streaks[i]
		local m = sk.Model
		if now > sk.T1 or not (m and m.Parent) then
			streakOff(i)
		else
			local ok, cf = pcall(m.GetPivot, m)
			if ok and typeof(cf) == "CFrame" then
				sk.Kit.Root.CFrame = CFrame.new(cf.Position + UP * K.LEAP_TRAIL_UP)
			end
			local on = now >= sk.T0
			if sk.Kit.Trail.Enabled ~= on then
				sk.Kit.Trail.Enabled = on
			end
		end
	end
end

-- "in" from the run's start until its DashBack, "back" while it hops home, else "out"
local function dashState(entry, now)
	local d = entry and entry.Dash
	if not d then
		return "out"
	end
	if now < d.BackAt then
		return "in"
	elseif now < d.BackAt + d.BackDur then
		return "back"
	end
	return "out"
end

local function feelNum(v, default)
	return finite(v) and v or default
end

-- AttackFx.Dash(unit, src, tgt, landAt, now, opts) -> taken? src / tgt = Play's sides ({ Unit, Model, Pos }: src.Pos =
-- the unit's drawn spot before any pose, its rest spot); landAt = when the hit lands (the run ends there); opts =
-- { Mine, Low, Tempo = the seconds since the unit's last attack }. false (the caller plays today's Strike): Melee.Dash
-- off, no gap of Melee.MinGap studs, a higher pose playing (a KO, a cast)
local function dash(unit, src, tgt, landAt, now, opts)
	local M = feelOf("Melee")
	if unit == nil or not (M and M.Dash == true) or type(src) ~= "table" or type(tgt) ~= "table" or not finite(landAt) then
		return false
	end
	now = finite(now) and now or (St.now or os.clock())
	opts = type(opts) == "table" and opts or {}
	-- (battle-feel gate) Melee.Hop reaches PetPoses' DashIn through a module field (PetPoses reads no Config)
	local PPh = dep("PetPoses")
	if PPh then
		PPh.DashHop = max(0, min(3, feelNum(M.Hop, 0.5)))
	end
	local below = feelNum(M.FlurryBelow, 0.75)
	local flurry = finite(opts.Tempo) and opts.Tempo < below
	local backDur = max(0.05, feelNum(M.Back, 0.4))
	local land = landAt
	local bk = flurry and (land + below) or (land + feelNum(M.Bite, 0.08) + feelNum(M.Hold, 0.12))
	local entry = St.poses[unit]
	local d = entry and entry.Dash
	local state = dashState(entry, now)
	if state == "in" then
		-- the flurry: still at the edge, the next bite lunges in place on top of it
		local segs = entry.Segs
		for i = #segs, 1, -1 do
			local sg = segs[i]
			if sg.Lunge and sg.T0 + sg.Dur < now then
				table.remove(segs, i) -- (a long flurry keeps no spent bites)
			end
		end
		local t0 = max(now, land - K.LEAP_LAND * K.LUNGE_DUR)
		segs[#segs + 1] = { Name = "Strike", T0 = t0, Dur = K.LUNGE_DUR, Reach = feelNum(M.Lunge, 0.6), Forward = d.Reach, StopAt = land, StopDur = AttackFx.HIT_STOP, Lunge = true }
		bk = max(bk, t0 + K.LUNGE_DUR)
		d.In.Until, d.Back.T0, d.BackAt, d.LandAt = bk, bk, bk, land
		return true
	end
	local s = { Model = (typeof(src.Model) == "Instance") and src.Model or nil, Pos = (typeof(src.Pos) == "Vector3") and src.Pos or nil }
	local edge, fwd = nil, 0
	local t0 = max(now, land - feelNum(M.In, 0.3))
	if state == "back" then
		-- caught on the way home: the run starts from where the hop back has got to when the run starts (t0; the old
		-- DashBack plays on until then: review fix, sampled at `now` the DashIn snapped forward by the hop's last 0.15 s)
		edge = d.Reach
		local p = clamp01((t0 - d.BackAt) / d.BackDur)
		local PP = dep("PetPoses")
		local smp = nil
		if PP and type(PP.Sample) == "function" then
			local okS, r = pcall(PP.Sample, "DashBack", p, false, 1, edge)
			smp = okS and r or nil
		end
		local cur = (type(smp) == "table" and typeof(smp.Body) == "CFrame") and -smp.Body.Position.Z or edge * (1 - smooth(p))
		fwd = max(0, min(edge, cur))
	else
		-- the gap from the rest spot (the drawn spot, not the posed pivot) to the target's near edge
		s.Last = s.Pos
		if not s.Last and not pointOf(s) then
			return false
		end
		local t = sideOf(tgt)
		if not t then
			return false
		end
		local world, scale = gapOf(s, t)
		if not world or world < feelNum(M.MinGap, 3) then
			return false
		end
		edge = min(K.DASH_MAX, world) / scale
	end
	local run = max(0.05, land - t0)
	local segIn = { Name = "DashIn", T0 = t0, Dur = run / K.DASH_RUN, Reach = edge - fwd, Forward = fwd, Until = bk, StopAt = land, StopDur = AttackFx.HIT_STOP }
	local segBack = { Name = "DashBack", T0 = bk, Dur = backDur, Reach = edge }
	setPoses(unit, { segIn, segBack }, now)
	local e2 = St.poses[unit]
	if not (e2 and e2.Segs[1] == segIn) then
		return false -- (a higher pose plays: a KO'd pet never dashes, a cast is not cut)
	end
	e2.Dash = { Reach = edge, LandAt = land, BackAt = bk, BackDur = backDur, In = segIn, Back = segBack, Mine = opts.Mine == true }
	e2.Dash.Streak = (opts.Low ~= true) and streakFor(unit, s.Model, t0, land + 0.05, opts.Mine == true) or false
	return true
end

function AttackFx.Dash(unit, src, tgt, landAt, now, opts)
	local ok, r = pcall(dash, unit, src, tgt, landAt, now, opts)
	if not ok then
		St.errors = St.errors + 1
		warnOnce("dash", "Dash failed: " .. tostring(r))
		return false
	end
	return r == true
end

-- -> "out" | "in" | "back", and the dash record (read only: Reach = the edge in pose studs, LandAt, BackAt, Streak)
function AttackFx.DashState(unit)
	local entry = St.poses[unit]
	return dashState(entry, St.now or os.clock()), entry and entry.Dash or nil
end

function AttackFx.Play(ctx)
	if type(ctx) ~= "table" then
		return false
	end
	local eff = nil -- (outside the pcall: a build that fails half-way gives back every kit it took)
	local ok, result = pcall(function()
		local now = finite(ctx.Now) and ctx.Now or os.clock()
		local src = sideOf(ctx.From)
		if not src then
			return false
		end
		local targets = {}
		if type(ctx.To) == "table" then
			if ctx.To[1] ~= nil then
				for _, s in ipairs(ctx.To) do
					local side = sideOf(s)
					if side then
						targets[#targets + 1] = side
					end
				end
			else
				targets[1] = sideOf(ctx.To)
			end
		end
		local distance = nil
		if targets[1] then
			distance = (targets[1].Last - src.Last).Magnitude
		end
		-- budget: MAX_LIVE full effects, then MAX_STEPPED a band lower, then no
		local full, stepped = 0, 0
		for _, e in ipairs(St.live) do
			if e.Tail then
				-- (attack effects, 2026-11-01) a lingering tail never blocks a new effect
			elseif e.Stepped then
				stepped = stepped + 1
			else
				full = full + 1
			end
		end
		local step = full >= AttackFx.MAX_LIVE
		if step and stepped >= AttackFx.MAX_STEPPED then
			return false
		end
		local r = resolve(ctx, distance, step)
		if not r or not texturesOk(r) then
			return false
		end
		local quality = applyQuality()
		-- (Task 11b) a press's predicted charge (ctx.Pre: AttackFx.Precharge) / the real Special taking it over
		-- (ctx.Precharged: its charge backdated to the press, the prediction's charge items handed on) / a battle Special
		-- with no press (ctx.LateMax: the charge given back, the impact that much after DueAt)
		local isPre = ctx.Pre == true and r.Attack == "Special"
		local pre = nil
		if ctx.Precharged and not isPre and r.Attack == "Special" then
			local p = St.pre[src.Unit]
			if p and p.Kind == ctx.Kind then
				pre = p
			end
		end
		-- (battle-feel T3) a taken-over charge with a LateMax (a cast-driven Special) gets its travel back (fitTimes)
		local start, C, R, Tr, late = fitTimes(r.Beats, now, ctx.DueAt, (not isPre) and ctx.LateMax or nil, pre and pre.Start or nil)
		ctx.ImpactLate = late
		local Imp, L = r.Beats.Impact or 0.15, r.Beats.Linger or 0.5
		local aliveSecs = (type(r.Alive) == "table" and finite(r.Alive.Seconds)) and r.Alive.Seconds or 0
		local T = { Charge = 0, Release = C, Travel = C + R, Impact = C + R + Tr }
		T.Linger = T.Impact + Imp
		local endRel = T.Linger + max(L, aliveSecs)
		-- (attack effects, 2026-11-01) what outlives the beats: nothing on Low, on a miss (no mark was left) or on a predicted charge
		local afterglow = (quality ~= "Low" and not isPre and ctx.Miss ~= true and finite(r.Afterglow)) and r.Afterglow * r.Density or 0
		if isPre then
			-- open-ended: only the charge, until the real effect takes it over or it shatters (<= PRE_HOLD); its particles
			-- may live their full life (the tuned Lifetime stops at EndRel)
			start, late = now, 0
			ctx.ImpactLate = 0
			T = { Charge = 0, Release = K.PRE_HOLD, Travel = K.PRE_HOLD, Impact = K.PRE_HOLD + 10, Linger = K.PRE_HOLD + 10 }
			endRel = K.PRE_HOLD + 0.5
		end
		local area = (r.Attack == "Element") and (r.Shape or "Cone") or nil
		if r.Twist and not r.Shape then
			area = nil -- (evolved forms: an element's twist with no area of its own: Forked's bolt, Starfall)
		end
		local specialArea = (r.Attack == "Special") and ctx.Kind or nil
		local reach
		if area == "Line" then
			reach = finite(ctx.Length) and ctx.Length or 24
		elseif area == "Circle" then
			reach = finite(ctx.Radius) and ctx.Radius or 8
		elseif specialArea == "Beam" then
			reach = finite(ctx.Length) and ctx.Length or 26
		elseif SPECIAL_RADIUS[specialArea] then
			reach = finite(ctx.Radius) and ctx.Radius or SPECIAL_RADIUS[specialArea]
		else
			reach = finite(ctx.Radius) and ctx.Radius or 9
		end
		local width = finite(ctx.Width) and ctx.Width or 4
		local dir = V3(0, 0, -1)
		if finite(ctx.Angle) then
			dir = V3(cos(ctx.Angle), 0, sin(ctx.Angle))
		end
		local aimFixed = ctx.AimFixed == true and finite(ctx.Angle) -- (evolved forms: a Twin runs where the first beam ran)
		if targets[1] and not aimFixed then
			local d = flat(targets[1].Last - src.Last)
			if d.Magnitude > 0.2 then
				dir = d.Unit
			end
		end
		-- (evolved forms) an aura holds from now for its Seconds (a Rally's / Haste's buff), when that is past its beats; Low: no bigger pet
		local auraRel = nil
		if finite(r.Aura) and (now - start) + r.Aura > endRel then
			auraRel = (now - start) + r.Aura
		end
		local drop = K.DROP
		if finite(ctx.Ground) then
			local d = src.Last.Y - ctx.Ground
			if d >= 0.2 and d <= 8 then
				drop = d
			end
		end
		eff = {
			Recipe = r, Unit = src.Unit, Src = src, Targets = targets, T = {}, S = src.Last, Dir = dir, Right = dir:Cross(UP),
			Path = r.Core.Path, Area = area, Reach = reach, Width = width, WidthScale = width / 4, Drop = drop, Size = r.Size or 1, CloudSize = r.CloudSize or r.Size or 1,
			Start = start, Times = T, TailAt = endRel, Afterglow = afterglow, TailTrans = r.TailTrans, EndRel = auraRel or (endRel + afterglow), End = start + (auraRel or (endRel + afterglow)),
			AuraRel = auraRel, Scale = (auraRel and quality ~= "Low" and finite(ctx.Scale)) and ctx.Scale or nil, AimFixed = aimFixed or nil, Band = finite(ctx.Band) and ctx.Band or nil,
			Center = (typeof(ctx.Center) == "Vector3" and area == "Circle") and ctx.Center or nil,
			Mine = ctx.Mine == true, Crit = ctx.Crit == true, Strong = ctx.Strong == true, Miss = ctx.Miss == true,
			Stepped = step, Low = quality == "Low", Items = {}, Emitters = 0, Beams = 0, Trails = 0, Lights = 0, Cores = 0, Rims = 0,
			Kind = ctx.Kind, Pre = isPre or nil, CueSeconds = isPre and (finite(ctx.Seconds) and max(0.1, ctx.Seconds) or K.PRE_HOLD) or nil,
			Avoid = ctx.Avoid, AvoidPts = {}, -- (Studio findings round) the spots a big piece keeps clear of (avoidSpots)
			-- (battle-feel T1) a bite lands on a big body's near edge; the floor every ground layer stands on
			Bite = (r.Attack == "Melee" or (r.Attack == "Special" and ctx.Kind == "Pounce")) or nil,
			FloorY = finite(ctx.Ground) and ctx.Ground or (src.Last.Y - drop),
			Dashed = (ctx.Dashed == true and (r.Attack == "Melee" or r.Attack == "Element")) or nil, -- (battle-feel T2) the bite's pose is AttackFx.Dash's (feel-balance: an Element's too)
		}
		for i, side in ipairs(targets) do
			eff.T[i] = side.Last
		end
		refresh(eff)
		if targets[1] and not isPre then
			refineFloor(eff, targets[1])
		end
		eff.CorePos = corePosOf(eff, 0)
		-- (evolved forms) one aura a unit: a new cast replaces the one it still wears
		if auraRel then
			for _, e in ipairs(St.live) do
				if e.AuraRel and e.Unit == eff.Unit then
					endAura(e)
				end
			end
		end
		-- (evolved forms) the charge line the pack runs on, frozen now, in the world: the event's, else from behind the caster through the target
		local packs = type(r.Sig) == "table" and type(r.Sig.Actor) == "table" and r.Sig.Actor.Motion == "PackCharge"
		if not isPre and (packs or type(ctx.Line) == "table") then
			eff.Line = chargeLineOf(eff, ctx.Line)
		end
		-- (Task 11c, review M8) the cloud's lift, from the first "Above" layer with a Height, before the core / actor /
		-- layers that read it (the rain emitter, the falling pieces, the dusk moon), whatever the layers' order
		-- (Task 11d, review M5: read from the recipe's layers, so the rain and the falling pieces start from the cloud's
		-- height whether or not the Cloud emitter itself survives the emitter budget; today it always does: it is the
		-- Storm's LowKeep. S4: + the cloud's top, its height + half its puffs' size, for the dusk moon over it)
		for _, layer in ipairs(r.Layers or {}) do
			if layer.At == "Above" and finite(layer.Height) then
				eff.CloudLift = layer.Height
				eff.CloudTop = layer.Height + 0.5 * (finite(layer.Size) and layer.Size or 1) * eff.CloudSize
				break
			end
		end
		-- what this effect draws: the core, the layers it can afford, the alive detail, the signature actor (a predicted
		-- charge: only its charge at the mouth: the glow + motes, a glow light; its target is a guess)
		if not isPre then
			buildCore(eff)
			buildActor(eff) -- (Task 11: before the layers, so the 14-piece cap never cuts the signature's own pieces)
		end
		local layers = {}
		for _, layer in ipairs(r.Layers or {}) do
			if isPre then
				if layer.Beat == "Charge" and layer.At == "Source" and (layer.Kind == "Emitter" or layer.Kind == "Light") then
					layers[#layers + 1] = layer
				end
			elseif not (eff.Miss and (layer.Beat == "Impact" or layer.Beat == "Linger")) then
				layers[#layers + 1] = layer
			end
		end
		if type(r.Alive) == "table" and r.Alive.Kind and not eff.Miss and not isPre then
			local a = {}
			for k, v in pairs(r.Alive) do
				a[k] = v
			end
			a.Id, a.Alive, a.Beat = "Alive", true, "Linger"
			a.At = (eff.Path == "Self" or eff.Path == "Allies") and "Self" or "Target"
			layers[#layers + 1] = a
		end
		local cap = AttackFx.MAX_EMITTERS[quality] or 6
		if isPre then
			cap = cap - 1 -- (room for the shards if it shatters)
		end
		local keep = nil
		if quality == "Low" and type(r.LowKeep) == "table" then
			keep = {}
			for i, id in ipairs(r.LowKeep) do
				keep[id] = keep[id] or i
			end
		end
		-- (Task 11b) a battle Special whose charge is seen keeps its charge glow at the mouth right after the Burst and
		-- the LowKeep (it ranked last: the charge used to be cut to the render lead); the /fx preview (no DueAt) ranks as
		-- before
		local glowFirst = finite(ctx.DueAt) and r.Attack == "Special" and T.Release >= AttackFx.CUE_MIN
		local ranked = {}
		for i, layer in ipairs(layers) do
			-- (attack effects, 2026-11-01) Graphics Low gets rings, lights and ground marks of the impact package, not its emitter
			if isEmitter(layer) and not chargeDropped(eff, layer) and not (quality == "Low" and layer.Id == "Sparks") then
				local rank = emitterRank(layer, keep)
				if glowFirst and layer.Beat == "Charge" and layer.At == "Source" and rank > 0.9 then
					rank = 0.9
				end
				ranked[#ranked + 1] = { L = layer, R = rank, I = i }
			end
		end
		table.sort(ranked, function(a, b)
			if a.R ~= b.R then
				return a.R < b.R
			end
			return a.I < b.I
		end)
		local allowed = {}
		for i = 1, min(cap, #ranked) do
			allowed[ranked[i].L] = true
		end
		local beams = beamBudget(layers, AttackFx.MAX_BEAMS) -- (the alive detail first, the ladder's arcs last)
		for _, layer in ipairs(layers) do
			if not isEmitter(layer) or allowed[layer] then
				addLayer(eff, layer, beams)
			end
		end
		addChargeCues(eff, pre) -- (Task 11b) the rim light + the inhale under a seen charge
		-- (attack effects, 2026-11-01) no Linger item was built (a signature traded them away, the cap cut them): nothing to stay on for
		local anyLinger = false
		for _, it in ipairs(eff.Items) do
			anyLinger = anyLinger or it.Lingers == true
		end
		if not anyLinger then
			eff.Afterglow, eff.EndRel, eff.End = 0, eff.TailAt, eff.Start + eff.TailAt
			eff.AuraRel = nil
		end
		St.live[#St.live + 1] = eff
		if isPre then
			local old = St.pre[eff.Unit]
			if old then
				retire(old, now)
			end
			St.pre[eff.Unit] = eff
			preparePose(eff, now)
		else
			schedulePoses(eff, now)
			if pre then
				adopt(eff, pre, now)
			end
		end
		return true
	end)
	if not ok then
		St.errors = St.errors + 1
		warnOnce("play", "Play failed: " .. tostring(result))
		if eff then
			pcall(finish, eff) -- out of St.live (if it got there) and every kit back to its pool, hidden
		end
		return false
	end
	return result == true
end

-- (Task 11b) a press's predicted charge on the caster: the Special's charge at its mouth (glow + motes), the rim, the
-- inhale and the Cast pose, open-ended (<= PRE_HOLD; ctx.Seconds = how long the caller waits: the inhale's rise). ctx as
-- Play's (Kind, From, To = the target it will likely aim at, Element / Rarity / ..., Mine, Now); no DueAt. The real
-- Special takes it over with Play(ctx with Precharged = true); a refusal / no event: Shatter(unit). A newer prediction
-- on the unit retires the older one.
function AttackFx.Precharge(ctx)
	if type(ctx) ~= "table" then
		return false
	end
	local c = {}
	for k, v in pairs(ctx) do
		c[k] = v
	end
	c.Pre, c.Attack, c.DueAt, c.Precharged, c.LateMax, c.Miss, c.Crit = true, "Special", nil, nil, nil, nil, nil
	return AttackFx.Play(c)
end

-- (Task 11b) the unit's live predicted charge (read only) | nil
function AttackFx.Precharging(unit)
	return St.pre[unit]
end

-- (Task 11b) the predicted charge breaks: a few shards fly off the mouth (K.SHARDS of SHARD_TEX in the edge colour, the
-- Shatter burst), its glow / rim fade (retire), the caster rears back (Recoil), the inhale is hushed and
-- Hooks.Shatter(mine, unit) plays the "interrupted" sound. No impact. `quiet` = it only fades (its Special came but
-- could not play: no shards, no Recoil, no sound). -> true when there was a prediction to break
function AttackFx.Shatter(unit, now, quiet)
	local eff = St.pre[unit]
	if not eff then
		return false
	end
	now = finite(now) and now or (St.now or os.clock())
	local ok, err = pcall(function()
		if eff.InhaleToken ~= nil then
			local token = eff.InhaleToken
			eff.InhaleToken = nil
			callHook("Hush", token)
		end
		retire(eff, now)
		if quiet then
			local e = St.poses[eff.Unit]
			if e and e.PreOf == eff then
				St.poses[eff.Unit] = nil -- (its held charge pose ends with it)
			end
			return
		end
		local tRel = max(0, now - eff.Start)
		local ids = dep("TextureIds")
		local id = type(ids) == "table" and ids[K.SHARD_TEX] or nil
		if type(id) == "number" and id > 0 then
			local pal = type(eff.Recipe.Palette) == "table" and eff.Recipe.Palette or {}
			local layer = { Id = "Shards", Kind = "Emitter", Texture = K.SHARD_TEX, Beat = "Charge", At = "Source", Size = 0.8,
				Color = typeof(pal.Edge) == "Color3" and pal.Edge or WHITE }
			local kit = take("Emitter")
			if kit then
				eff.Emitters = eff.Emitters + 1
				local count = max(2, floor(K.SHARDS * eff.Recipe.Density * (eff.Low and K.LOW_COUNT or 1) + 0.5))
				local it = addItem(eff, { Kind = "Emitter", Kit = kit, Layer = layer, At = "Source", T0 = tRel, T1 = tRel, Mode = "Burst", Preset = "Shatter",
					Count = count, Rate = 0, Acc = 0, Pts = {}, Fn = DRAW.Emitter })
				tuneEmitter(eff, it, layer)
			end
		end
		-- (fix round 1, I3) only the prediction's own held pose gives way at once; any other (a Ko) keeps K.PRIO
		local old = St.poses[eff.Unit]
		local own = old ~= nil and old.PreOf == eff
		if own then
			St.poses[eff.Unit] = nil
		end
		setPoses(eff.Unit, { { Name = "Recoil", T0 = now, Dur = K.RECOIL } }, now)
		local entry = St.poses[eff.Unit]
		if own and entry and entry ~= old then
			entry.Prev, entry.SwitchAt = old, now -- (crossfade from the held charge pose)
		end
		eff.Shattered = true
		callHook("Shatter", eff.Mine, eff.Unit)
	end)
	if not ok then
		St.errors = St.errors + 1
		warnOnce("shatter", "Shatter failed: " .. tostring(err))
		pcall(finish, eff)
	end
	return true
end

function AttackFx.Update(now)
	now = finite(now) and now or os.clock()
	St.now = now
	applyQuality()
	for i = #St.live, 1, -1 do
		local eff = St.live[i]
		if eff then
			local ok, err = pcall(stepEffect, eff, now)
			if not ok then
				St.errors = St.errors + 1
				warnOnce("step", "effect failed: " .. tostring(err))
				pcall(finish, eff)
			elseif now >= eff.End then
				finish(eff)
			elseif not eff.Tail and now >= eff.Start + eff.TailAt then
				startTail(eff, now)
			end
		end
	end
	trimTails()
	stepStreaks(now)
	for unit, entry in pairs(St.poses) do
		local pending = entry.Prev and entry.SwitchAt and now < entry.SwitchAt + AttackFx.CROSSFADE
		if not pending then
			entry.Prev = nil
		end
		if not poseActive(entry, now) and not pending then
			St.poses[unit] = nil
		end
	end
end

-- (the returned table and its Prev are reused per pose entry: read them at once, do not keep them across frames)
function AttackFx.Pose(unit, base)
	local entry = St.poses[unit]
	if not entry then
		return nil
	end
	local now = St.now or os.clock()
	local name, p, ranged, amp, reach, fwd = poseSample(entry, now, base)
	local prev = entry.Prev
	local out = entry.Out
	if not out then
		out = {}
		entry.Out = out
	end
	out.Blend, out.Prev = 1, nil
	if not name then
		if prev and entry.SwitchAt and now < entry.SwitchAt then -- the new pose has not started: the old one plays on
			local n2, p2, r2, a2, x2, f2 = poseSample(prev, now, base)
			if n2 then
				out.Name, out.P, out.Ranged, out.Amp, out.Reach, out.Forward = n2, p2, r2, a2, x2, f2 or 0
				return out
			end
		end
		return nil
	end
	-- (battle-feel T2) out.Forward: pose studs along the LookVector on top of the pose (a flurry's bite from the edge)
	out.Name, out.P, out.Ranged, out.Amp, out.Reach, out.Forward = name, p, ranged, amp, reach, fwd or 0
	if prev and entry.SwitchAt then
		local w = (now - entry.SwitchAt) / AttackFx.CROSSFADE
		if w < 1 then
			local n2, p2, r2, a2, x2, f2 = poseSample(prev, now, base)
			if n2 then
				local po = entry.PrevOut
				if not po then
					po = {}
					entry.PrevOut = po
				end
				po.Name, po.P, po.Ranged, po.Amp, po.Reach, po.Forward = n2, p2, r2, a2, x2, f2 or 0
				out.Blend = max(0, w)
				out.Prev = po
			end
		end
	end
	return out
end

function AttackFx.Cancel(unit)
	St.poses[unit] = nil
	for i = #St.streaks, 1, -1 do
		if St.streaks[i].Unit == unit then
			streakOff(i)
		end
	end
	for i = #St.live, 1, -1 do
		local eff = St.live[i]
		if eff and eff.Unit == unit then
			pcall(finish, eff)
		end
	end
end

-- (evolved forms) the unit's aura ends with its buff (nil = every aura): -> whether one ended
function AttackFx.EndAura(unit)
	local ended = false
	for _, eff in ipairs(St.live) do
		if eff.AuraRel and (unit == nil or eff.Unit == unit) then
			local ok = pcall(endAura, eff)
			ended = ended or ok
		end
	end
	return ended
end

-- (evolved forms) how long the unit's aura still has to run | nil
function AttackFx.AuraLeft(unit, now)
	for _, eff in ipairs(St.live) do
		if eff.AuraRel and eff.Unit == unit then
			return eff.End - (finite(now) and now or (St.now or os.clock()))
		end
	end
	return nil
end

function AttackFx.ClearAll()
	for i = #St.live, 1, -1 do
		pcall(finish, St.live[i])
	end
	St.live = {}
	St.poses = {}
	St.pre = {}
	for i = #St.streaks, 1, -1 do
		streakOff(i)
	end
	St.lastBasicKick = nil
end

function AttackFx.SetQuality(q)
	if q ~= "Low" and q ~= "High" then
		q = nil
	end
	St.forced = q
	applyQuality()
end

function AttackFx.Stats()
	-- (battle-feel T2) Streaks = the dash streaks live (their Trail kits count in Trails too)
	local s = { Live = 0, Stepped = 0, Tails = 0, Emitters = 0, Beams = 0, Trails = #St.streaks, Lights = 0, Cores = 0, Rims = 0, Pooled = 0, PoolInstances = 0, Errors = St.errors, Streaks = #St.streaks }
	for _, eff in ipairs(St.live) do
		if eff.Tail then
			s.Tails = s.Tails + 1
		elseif eff.Stepped then
			s.Stepped = s.Stepped + 1
		else
			s.Live = s.Live + 1
		end
		s.Emitters = s.Emitters + eff.Emitters
		s.Beams = s.Beams + eff.Beams
		s.Trails = s.Trails + eff.Trails
		s.Lights = s.Lights + eff.Lights
		s.Cores = s.Cores + eff.Cores
		s.Rims = s.Rims + (eff.Rims or 0)
	end
	local function count(list)
		for _, kit in ipairs(list) do
			s.Pooled = s.Pooled + 1
			s.PoolInstances = s.PoolInstances + kit.N
		end
	end
	for _, list in pairs(St.pool) do
		count(list)
	end
	for _, list in pairs(St.corePool) do
		count(list)
	end
	return s
end

function AttackFx.Folder()
	return ensureFolder()
end

-- TESTS ONLY: dependency overrides ({ MeshLibrary =, TextureIds =, GraphicsQuality = }; false = the real one)
function AttackFx._Deps(t)
	for k, v in pairs(type(t) == "table" and t or {}) do
		deps[k] = v or nil
	end
end

-- TESTS ONLY: the live effects (read only)
function AttackFx._Live()
	return St.live
end

return AttackFx
