-- PetPoses: how a pet's body moves with its attacks (docs/superpowers/specs/2026-10-23-pet-attack-vfx-design.md
-- "Pet body animation", plan docs/superpowers/plans/2026-10-23-pet-attack-vfx.md Task 5). Poses ride on PetBuilder's
-- existing weld-free rig: a pose is a body offset (the caller applies it to the root) plus a rotation per animated
-- group kind that PetBuilder.Animate multiplies onto its own idle motion (opts.Pose). Pure: no Instances, no
-- services, no yields (CFrame / Vector3 values only); safe on the server and the client. Plain Lua 5.1-compatible
-- syntax only.
--
-- API:
--   PetPoses.Names = { "Windup", "Strike", "Shoot", "Recoil", "Cast", "Hurt", "Ko", "Victory", "IdleBattle", "DashIn", "DashBack",
--                      "DashBite", "DashDouble", "DashThorns", "DashReady" }
--   PetPoses.Loops = { IdleBattle = true, DashReady = true }   p is TIME in seconds (any value)
--   PetPoses.Holds = { Ko = true, DashIn = true, DashBite = true, DashThorns = true }  p = 1 is the pose's end state, held
--                                            (the KO'd pet lies on its side until the poof covers it and the model is
--                                            parked; a dashed-in pet stands at the target's edge until its DashBack);
--                                            every other one-shot pose is exactly at rest at p = 1 and at p = 0 too, but
--                                            DashBack (starts at the edge DashIn holds), DashDouble / DashThorns (start
--                                            from the bite's nose-down landing, as the chomp they replace)
--   PetPoses.DASH_RUN = 5 / 7                DashIn's / DashBite's hops land the bite at this p (AttackFx times it on the hit)
--   PetPoses.WINDUP_LOAD = 0.82              the melee Windup is fully loaded here (a dash's wind-up ends on it)
--   PetPoses.TREMBLE_HZ = 12.5, TREMBLE_MIN = 0.3   the melee Windup's tremble (real seconds) and the shortest wind-up
--                                            (to its load) that trembles
--   PetPoses.BACK_POSE = 1.4, BACK_HOME = 0.625   DashBack lasts Melee.Back x BACK_POSE; it is home at p BACK_HOME
--   PetPoses.DOUBLE_DUR = 0.15, DOUBLE_BITE = 0.6, THORN_DUR = 0.34, THORN_BACK = 1.3, REBOUND = 0.7, READY_BOUNCE = 0.17
--   PetPoses.FEET = { Down, Front, Hind }    a typical pet's paw lines (pose studs) when Sample gets no `feet` (a `feet`
--                                            Hop weighs the hops: an evolved form's 0.78, the mock's heavy lanes)
--   PetPoses.Landings[name] = { p, ... }     where the melee motion's hops come down (the landing dust's beats)
--   PetPoses.Offset(name, p, ranged, amp, reach, feet) -> Vector3   the pose's own move without its turn (where a
--                                            paw-pivoted pose's paw lines are: its Body position also carries the turn about
--                                            them)
--   PetPoses.HURT_SECS = 0.62                a hit's reaction (Hurt) in seconds after its hit stop (AttackFx's K.HURT);
--                                            a re-hit's Sample reach lists every hit it plays (see Hurt below)
--   PetPoses.DashHop = nil                   Config Melee.Hop in studs (0..3; nil = 0.5), set by AttackFx.Dash: every Bounce in
--                                            hop height x max(0.25, DashHop) / 0.5 (DashIn's first hop peaks at 1.1 x it;
--                                            0 still hops 0.275: a flatter hop lands like a slide)
--   PetPoses.Sample(name, p, ranged, amp, reach, feet) -> {
--       Body   = CFrame   offset of the pet's root in its OWN frame (the pet faces -Z = LookVector, up +Y, right
--                        +X; PetBuilder header), studs as written below (battle units: BattleController writes
--                        root = frame * Body; PetBuilder.PoseBody(opts) returns it)
--       Groups = { [kind] = CFrame }   per PetBuilder group kind ("wing", "cloud", "tail", "bob", "orbit"): a turn
--                        (+ lift) in the PET's frame about the group's hinge point, written for the LEFT side (Side =
--                        1: the left wing reaches towards -X). Pet-frame axes keep "swept back 25 deg" the same on
--                        every form (hinges are swept back 0.5 .. 1.35 rad and tilted, differently per form). Animate
--                        mirrors it for Side = -1 and scales the "bob" lift by the model's PB_Scale. Wings: "open" /
--                        "spread" = swung forward towards broadside (a bigger silhouette); they are never raised by
--                        more than ~10 deg (evolved wings already rest near upright: more would fold them over the back)
--       Lids   = 0..1    eyelids closed (Animate shows the EyeLid parts at >= 0.5)
--       Still  = 0..1    how much of the idle wing flap / tail wag / halo bob to hold back (1 = frozen at rest:
--                        wings held open, a limp KO'd tail)
--   }   p is clamped to 0..1 (one-shot poses; nil / NaN = 0); `ranged` = the ranged variant (Strike: a kick back
--       instead of the lunge; Windup / Recoil: rear back). An unknown name = rest. `amp` (number, default 1, clamped
--       1 .. LEAP_AMP_MAX 1.25) scales the melee Strike's leap (length and height grow a little with rarity: AttackFx
--       passes 1 + 0.08 per band above Common); every other pose ignores it. `reach` (studs at scale 1, optional,
--       >= 0, a safety ceiling LEAP_REACH_MAX 240 (the real clamp is AttackFx's, in world studs); nil = the fixed 1.5 x
--       amp hop): the melee Strike's forward distance, so the leap
--       lands on the target (Task 9 player decision: AttackFx measures the gap between the two models' facing edges,
--       minus a contact margin, and divides it by the caster's PB_Scale); the hop gets higher with it.
--
-- The shapes (spec + plan values; the extra motion is the "feel": anticipation, overshoot, settle):
--   Windup     melee (Pitch 2 item 5, the owner: "the wind-up looked wrong": the old crouch sank the paws 0.25 studs
--              into the floor): it rocks back onto its hind paws (9 deg in 0.12 s, pitched about the paw line: nothing
--              sinks), trembles (TREMBLE_HZ 12.5, +-1.4 deg), loads deeper (15 deg in its last 0.07 s, at WINDUP_LOAD 0.82:
--              a dash's wind-up ends there, DashIn starts from it), then springs back to rest (the push-off into Strike);
--              wings swept back 25 deg and folded tight, tail up and lashing. Its beats are in real seconds (gate review r0):
--              `reach` = the pose's length in seconds (nil = WINDUP_SECS, the strip's 0.45 s to the load); a wind-up under
--              TREMBLE_MIN 0.3 s to its load (the real NPC one, 0.25 s on the client since 2026-11-20; a fighter's 0.10)
--              rocks and loads in one eased gather (exactly 60 % / 40 %, nothing held between), no tremble. Ranged rears
--              back (crouch 0.25, weight back, chin up), unchanged.
--   Strike     melee (player note (a), fix round 3): a LEAP at the target: a hop arc 0.8 studs high (x amp) that carries
--              the body 1.5 studs (x amp) along the LookVector (with `reach`: exactly `reach` studs, the hop
--              min(LEAP_H_MAX, (0.8 + 0.12 x reach) x amp) high: Task 9), chin up on take-off, nose down coming in, landing at
--              p = 0.26 exactly when the hit lands (AttackFx times the pose so), a small squash on landing, then the
--              recoil: it settles back with a small overshoot behind the start. Wings snap open 35 deg (overshoot ~38).
--              ranged: a kick back 0.35 studs, chin up, wings snap open 35 deg, settle.
--   Shoot      the basic ranged attack's release (player note 1: a shot, never the melee lunge; it follows the ranged
--              Windup's rear-back): the head snaps forward and down 14 deg to loose the shot (a spit / a slap of the
--              air) while the body kicks back 0.45 studs and a little up, wings brace forward 20 deg with a downbeat,
--              tail flicks up; then settles. The body never moves forward of its spot.
--   Recoil     rear back: 0.5 studs back (ranged 0.35), up and nose high, wings flare forward to brace, tail down.
--   Cast       rise 0.6 studs, wings spread 50 deg and held, tail up, eyes shut gathering power, a hover bob, then the
--              release: a forward thrust + nod and a wing downbeat; soft landing.
--   Hurt       (Pitch 2 item 5 "Bounce in" A, the approved mock's bitten pet; it was a squash dip into the floor + a flinch
--              0.3 turned about the middle) one rigid body pivoted on its paw lines (`feet`): knocked back 0.38 in a 0.10
--              jolt off the floor (0.12 s), the head snapped back (~7 deg nose up), a springy rock (~4 deg nose down onto
--              the front paws, back) dying away, home over the mock's 0.30 .. 0.62 s with a low lift (0.025); nothing
--              under the floor, nothing slides; an evolved body (feet Hop) x its Hop; beats in seconds (p 1 = HURT_SECS
--              0.62, AttackFx's K.HURT). `amp` = the hit's power (nil = 1). `reach` = a re-hit's hits: { Secs, { Age,
--              Power }, ... }: each reacts on its own time and the reactions add (the mock's), so a re-hit starts where the
--              pet is, never pulled toward its biter, and stacks on top. Wings clamp down, tail tucks, halo knocked askew,
--              lids shut (0.02 .. 0.29 s).
--   Ko         knocked back 0.6 + a little hop, tumbles 90 deg onto its side (overshoot ~95, settle), drops 0.35,
--              wings fold back limp along the body, tail limp (Still -> 1), halo slides askew, eyes shut. Holds at p = 1.
--   Victory    a quick crouch, hop 1.2 studs with a full 360 deg spin (fastest mid-air), chin up, wings open, tail up,
--              halo spinning, then a squash landing that settles.
--   IdleBattle breathing 0.05 studs (1.8 s), and every 2-4 s a glance: a 10-13 deg look aside with a curious head tilt
--              and a tail flick (the rig has no ear / head groups: the glance turns the whole body).
--   DashIn     (battle-feel T2; Pitch 2 item 5 "Bounce in" A, docs/superpowers/specs/2026-11-20-pitch2-build-design.md) the
--              melee dash in, timed on Melee.In 0.30 s (p 0 .. DASH_RUN 5/7) then the chomp (DASH_RUN .. 1, 0.12 s): from
--              the melee Windup's loaded pose (rocked back 15 deg on the hind paws) a hop to 48 % of `reach` (0.13 s, 0.55
--              studs high), a nod as it lands on its front paws (0.04 s), a hop-bite onto the target (0.13 s, 0.36 high, nose
--              down 15) landing at DASH_RUN exactly when the hit lands, then the chomp (the head snaps up and bites down
--              again), upright at p 1, held there (Holds) at exactly (0, 0, -reach). reach nil = 1.5 x amp.
--   DashBack   the way home (AttackFx: Dur = Melee.Back x BACK_POSE 1.4 = 0.56 s): from (0, 0, -reach) a hop back to 45 %
--              (0.16 s, 0.42 high, nose up), a rock on the hind paws as it lands (0.03 s), a hop home (0.16 s, 0.32 high) landing
--              at BACK_HOME 0.625, then a rocking settle on the spot (0.21 s); exactly at rest at p 1.
--   DashBite   (item 5) a flurry's bite (bites closer than Melee.FlurryBelow: no trip home): `reach` = studs behind the face it
--              starts (0 at the face); a rebound hop back to REBOUND 0.7 behind the face (in place when it already stands that
--              far back; 12 / 30 of the run), a rock as it lands (the strip's 0.06 s: 12 / 30 .. 18 / 30), a hop-bite onto
--              the face landing at DASH_RUN on the hit, the chomp; held there.
--   DashDouble (item 5) a Double strike's second chomp at the face (0.15 s): the second bite lands at DOUBLE_BITE 0.6.
--   DashThorns (item 5) a bite on a Thorns shield: the prick snaps the head back (rocked onto the hind paws, eyes shut), a hop
--              away `reach` studs (nil = THORN_BACK 1.3), a rock as it lands; held there (Holds), upright.
--   DashReady  (item 5, loops: p = time) the flurry's ready bounce on the spot between bites: READY_BOUNCE 0.17 s hops of
--              0.07 studs with a little rock, on the floor (and level) at every multiple of READY_BOUNCE.
--   The melee motion is ONE rigid body (the rig has no scale channel and no leg groups): a pitch turns it about its paw line
--   on the floor (hind paws nose up, front paws nose down: f.paw) and about its middle in the air, blended
--   over the first BLEND_H of a hop; Sample's `feet` (AttackFx.FeetOf: pose studs, scale 1) places the paw lines, nil =
--   FEET. Nothing goes under the floor (a paw that would dips lifts the whole body) and nothing slides (a paw on the floor
--   never moves along it: every move along the ground is a hop).

local PetPoses = {}

PetPoses.Names = { "Windup", "Strike", "Shoot", "Recoil", "Cast", "Hurt", "Ko", "Victory", "IdleBattle", "DashIn", "DashBack",
	"DashBite", "DashDouble", "DashThorns", "DashReady" }
PetPoses.Loops = { IdleBattle = true, DashReady = true }
PetPoses.Holds = { Ko = true, DashIn = true, DashBite = true, DashThorns = true }

local PI = math.pi
local TAU = 2 * math.pi
local sin, cos, rad, floor = math.sin, math.cos, math.rad, math.floor

-- Strike / Recoil / Hurt / Victory values (studs, degrees)
local LUNGE = 1.5
local LEAP_H = 0.8 -- the melee Strike's hop height at amp 1 (studs)
local LEAP_LAND = 0.26 -- the leap lands (and the hit lands) at this p
PetPoses.LEAP_AMP_MAX = 1.25
-- studs (scale 1): a safety ceiling only (Task 9 review M5: the leap is clamped ONCE, by AttackFx.LeapReach, at LEAP_MAX
-- 12 WORLD studs, then divided by the caster's PB_Scale; a pose clamp of 12 bit first below scale 1 and landed short).
-- 240 = 12 / PetBuilder's smallest scale 0.05, so a reach AttackFx sends never meets it
PetPoses.LEAP_REACH_MAX = 240
local LEAP_H_PER = 0.12 -- extra hop height per stud of reach (a longer jump goes higher)
local LEAP_H_MAX = 2.4 -- studs: the highest hop
local RANGED_KICK = 0.35
local SHOOT_KICK = 0.45
local CROUCH = 0.25
local WINDUP_BACK = 25
local SNAP_OPEN = 35
local CAST_RISE = 0.6
local CAST_SPREAD = 50
-- (Pitch 2 item 5 "Bounce in" A) the bitten pet of the approved mock (Hurt, motion_pitch.enemy_new): one hit's reaction
-- in seconds of its own time (after the hit stop): AttackFx's K.HURT. (look review r2, major 2) home at 0.62 like the
-- mock (the hit + 0.67), not 0.50: at the fast tempo the bear stays knocked back and the bites stack
local HURT_SECS = 0.62
PetPoses.HURT_SECS = HURT_SECS
local KNOCK = 0.38 -- studs: knocked back
local JOLT = 0.10 -- studs: the small jolt off the floor the knock-back flies in
local HURT_OUT = 0.12 -- s: knocked back in that jolt (in the air: nothing slides)
local HURT_ROCK = 13 -- deg: the springy rock's first swing (the head snapped back)
local HURT_HOME0 = 0.30 -- s: the way home starts (the mock's), home at HURT_SECS
-- studs: (look review r2, minor 1: the 0.06 hop at 0.28 .. 0.50 read as a second bounce) the way home is one low, slow
-- lift over the mock's whole way home (nothing slides)
local HURT_HOME = 0.025
local HURT_WINGS = 0.5 -- s: the wings / tail / halo / lids keep their beats at the old length
local KO_ROLL = 90
local HOP = 1.2
local BREATH = 0.05
local GLANCE_CELL = 3 -- one glance per cell, starting 0..1 s into it: 2-4 s between two glances
local GLANCE_TIME = 1.1
-- (battle-feel T2; Pitch 2 item 5 "Bounce in" A) the dash: Melee.In 0.30 s of hops, then the 0.12 s chomp
PetPoses.DASH_RUN = 5 / 7 -- DashIn's / DashBite's hops end (the bite lands) at this p
PetPoses.WINDUP_LOAD = 0.82 -- the melee Windup's deepest load (a dash's wind-up ends here; DashIn starts from it)
-- (gate review r0, major 1) the melee Windup in real seconds (Sample's `reach` = its length; AttackFx passes the Dur)
PetPoses.TREMBLE_HZ = 12.5 -- the tremble while the telegraph is up (the strip's 13 Hz)
PetPoses.TREMBLE_MIN = 0.3 -- s to the load: a shorter wind-up (the real NPC one, 0.25 s on the client) does not tremble
local WINDUP_SECS = 0.45 / 0.82 -- the length when none is given (the strip's 0.45 s to the load: BattleController's hold)
local ROCK_T, DEEP_T = 0.12, 0.07 -- s: the rock back to 9 deg, the load to 15 deg before the run (at most 60 % / 40 % of it)
local TREMBLE = 1.4 -- deg
PetPoses.BACK_POSE = 1.4 -- DashBack's Dur = Melee.Back x this (0.40 -> 0.56 s)
PetPoses.BACK_HOME = 0.625 -- DashBack's second hop lands home at this p (0.35 of 0.56 s); the settle after it
PetPoses.DOUBLE_DUR = 0.15 -- s: DashDouble (the Double strike's second chomp) ...
PetPoses.DOUBLE_BITE = 0.6 -- ... its bite lands at this p (0.09 s in)
PetPoses.THORN_DUR = 0.34 -- s: DashThorns (the prick 0.12, the hop away 0.16, the landing 0.06)
PetPoses.THORN_BACK = 1.3 -- studs: the hop away from a Thorns shield
PetPoses.REBOUND = 0.7 -- studs: a flurry bite's rebound hop back from the face
PetPoses.READY_BOUNCE = 0.17 -- s: one DashReady bounce
-- a typical pet's paw lines (pose studs from the root: AttackFx.FeetOf measures each model; this when none is given)
PetPoses.FEET = { Down = 1.3, Front = 0.5, Hind = 0.5 } -- (the Maple Fox, measured)
-- the p at which each hop comes down with a rock (AttackFx kicks the landing dust there): DashIn's nod on the front
-- paws, DashBack's two hops home, DashBite's rebound, DashThorns' hop away. Not the bite's own landing (the hit's
-- impact plays there) nor DashReady's little bounces
PetPoses.Landings = {
	DashIn = { 13 / 30 * PetPoses.DASH_RUN },
	DashBack = { 0.16 / 0.56, 0.35 / 0.56 },
	DashBite = { 12 / 30 * PetPoses.DASH_RUN },
	DashThorns = { 0.28 / PetPoses.THORN_DUR },
}
local BLEND_H = 0.25 -- studs: a hop's pivot moves from the paw line to the middle over its first BLEND_H of height
local HOP_MIN = 0.25 -- Melee.Hop under this hops as this (half the shipped hops: a flatter hop lands like a slide)
-- the Bounce in's hop heights (studs at Melee.Hop 0.5; each x max(HOP_MIN, Hop) / 0.5)
local BH = { In1 = 0.55, In2 = 0.36, Back1 = 0.42, Back2 = 0.32, Rebound = 0.26, Bite = 0.30, Thorn = 0.34, Ready = 0.07 }
local DASH_HOP = 0.5 -- studs: the default of Config.Battle.Feel.Melee.Hop (the pose stays pure: no Config here)
-- (battle-feel gate) PetPoses.DashHop = the knob's studs (0..3), set by AttackFx.Dash before it schedules a DashIn; nil = DASH_HOP
PetPoses.DashHop = nil
local function dashHop()
	local h = PetPoses.DashHop
	if type(h) ~= "number" or h ~= h or h == math.huge or h == -math.huge then
		return DASH_HOP
	end
	return math.max(0, math.min(3, h))
end
-- the Bounce in's hop height scale (Melee.Hop / 0.5, at least HOP_MIN / 0.5)
local function hopK()
	return math.max(HOP_MIN, dashHop()) / DASH_HOP
end
-- (review minor: "evolved pets hop x0.78 heavier", the mock's heavy lanes) the body's weight from Sample's `feet`: its
-- Hop (AttackFx.FeetOf: EVO_HOP 0.78 for an evolved form), 1 when none is given (finite, 0.25 .. 1.5)
local function heavyOf(feet)
	local v = type(feet) == "table" and tonumber(feet.Hop) or nil
	if v == nil or v ~= v or v < 0.25 or v > 1.5 then
		return 1
	end
	return v
end

----------------------------------------------------------------------
-- Easing
----------------------------------------------------------------------
local function clamp01(x)
	if x ~= x or x < 0 then
		return 0
	elseif x > 1 then
		return 1
	end
	return x
end

-- 0..1 progress of p through [a, b]
local function seg(p, a, b)
	return clamp01((p - a) / (b - a))
end

local function smooth(x)
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end

local function outCubic(x)
	x = 1 - clamp01(x)
	return 1 - x * x * x
end

-- ease out with an overshoot of the target (s = 1.70158: peaks at 1.1)
local function outBack(x, s)
	x = clamp01(x)
	if x == 0 then
		return 0 -- exactly (the formula leaves a rounding crumb)
	end
	x = x - 1
	return 1 + (s + 1) * x * x * x + s * x * x
end

-- 1 -> 0, ease in-out, dipping softly past 0 (by about os / 4) before coming to rest; still at both ends
local function settle(u, os)
	u = clamp01(u)
	local b = sin(PI * seg(u, 0.45, 1))
	return 1 - smooth(u) - os * b * b
end

-- 0 -> 1 -> 0 over [a, d]: up through [a, b], held, down through [c, d] (smooth)
local function plateau(p, a, b, c, d)
	return smooth(seg(p, a, b)) * (1 - smooth(seg(p, c, d)))
end

-- deterministic 0..1 per integer
local function hash(k)
	local x = sin(k * 12.9898 + 78.233) * 43758.5453
	return x - floor(x)
end

-- (Pitch 2 item 5) a smoothstepped key track { t1, v1, t2, v2, ... } at u (held before the first key and after the last)
local function keys(u, k)
	if u <= k[1] then
		return k[2]
	end
	for i = 1, #k - 3, 2 do
		local t0, v0, t1, v1 = k[i], k[i + 1], k[i + 2], k[i + 3]
		if u < t1 then
			return v0 + (v1 - v0) * smooth((u - t0) / (t1 - t0))
		end
	end
	return k[#k]
end

-- (Pitch 2 item 5) a ballistic hop of f over u in [t0, t1): along z0 -> z1 (near linear, a little ease at both ends: it
-- leaves and lands moving), up a parabola h studs high, the pitch eased pa -> pb. -> whether u is inside it
local function hop(f, u, t0, t1, z0, z1, h, pa, pb)
	if u >= t0 and u < t1 then
		local q = (u - t0) / (t1 - t0)
		f.z = z0 + (z1 - z0) * (0.8 * q + 0.2 * smooth(q))
		f.y = 4 * h * q * (1 - q)
		f.pitch = pa + (pb - pa) * smooth(q)
		return true
	end
	return false
end

-- (Pitch 2 item 5) the chomp after a bite (q 0..1 over 0.12 s): the head snaps up and bites down again, then upright
local CHOMP = { 0, -15, 0.4167, -4, 0.75, -9, 1, 0 }

-- (Pitch 2 item 5) on the floor the pivot is the paw line, in the air the middle: blended over the hop's first BLEND_H
-- of height (pawBody)
local function grounded(f)
	f.paw = true
end

----------------------------------------------------------------------
-- The poses: each fills a frame of plain numbers (studs, degrees)
----------------------------------------------------------------------
--   x, y, z          body offset (z + = back: the pet faces -Z)
--   pitch, yaw, roll body rotation (pitch + = nose up)
--   raise, back      wings, about the hinge in the pet's frame (left wing: raise + = tip up, back + = tip swept
--                    back, back - = swung forward / open)
--   lift, sway       tail (lift + = up)
--   haloY, haloTilt, haloSpin   the floating halo ("bob"); orbitSpin = the aura ("orbit")
--   lids, still
local POSES = {}

POSES.Windup = function(f, p, ranged, _, secsIn)
	local load = PetPoses.WINDUP_LOAD
	local r = seg(p, load, 1) -- spring up (accelerating: the push-off)
	local a
	local lashes = 2
	if ranged then
		a = smooth(seg(p, 0, 0.5)) * (1 - r * r) -- gather into the crouch
		f.y = -CROUCH * a
		f.z = 0.2 * a
		f.pitch = 8 * a
	else
		-- (Pitch 2 item 5) rocked back onto the hind paws (pitched about the paw line: nothing sinks, nothing slides), a
		-- tremble while the telegraph is up (0 at both its ends), loaded deeper at WINDUP_LOAD, then back to rest.
		-- (gate review r0, major 1) its beats run in real seconds: `secsIn` = the pose's length (nil = WINDUP_SECS), so the
		-- tremble is TREMBLE_HZ however long the wind-up is, and a wind-up under TREMBLE_MIN to its load (the real NPC one:
		-- 0.25 s on the client) is one eased rock back and load with no tremble (at ~40 Hz it was a jitter)
		local L = (secsIn and secsIn > 0) and secsIn or WINDUP_SECS
		local W = load * L -- seconds to the load
		local t = math.min(p, load) * L
		local long = W >= PetPoses.TREMBLE_MIN
		-- (the owner, 2026-11-20: the NPC's wind-up is 0.25 s on the client) a short one is exactly 60 % rock and 40 % load,
		-- one gather with no frozen stretch between (the fixed 0.12 s rock held 9 deg for 0.06 s of a 0.25 s wind-up)
		local rockT, deepT = 0.6 * W, 0.4 * W
		if long then
			rockT, deepT = math.min(ROCK_T, rockT), math.min(DEEP_T, deepT)
		end
		local rk = long and outCubic(seg(t, 0, rockT)) or smooth(seg(t, 0, rockT)) -- (a short one eases in: no snap)
		local deep = smooth(seg(t, W - deepT, W))
		local trem = 0
		if long then
			local a0, a1 = rockT, W - deepT -- held between the rock and the load
			trem = TREMBLE * sin(TAU * PetPoses.TREMBLE_HZ * (t - a0)) * smooth(seg(t, a0, a0 + 0.05)) * (1 - smooth(seg(t, a1 - 0.06, a1)))
		end
		a = rk * (1 - r * r)
		f.pitch = (9 * rk + 6 * deep + trem) * (1 - r * r)
		f.paw = true
		lashes = math.max(1, floor(W / 0.2 + 0.5)) -- (about 4.4 a second: a short wind-up lashes once, not at 13 Hz)
	end
	f.back = WINDUP_BACK * a
	f.raise = -10 * a
	f.lift = 30 * a
	-- the tail lashes before the pounce (melee: whole lashes by the load, level there, so DashIn takes over without a pop)
	f.sway = 12 * sin(TAU * lashes * (ranged and p or math.min(1, p / load))) * a
	f.haloY = 0.05 * a -- the halo lags as the body drops
	f.still = 0.35 * a
end

POSES.Strike = function(f, p, ranged, amp, reachIn)
	-- the wings snap open early, hold, and fold back with the settle
	local wings = outBack(seg(p, 0, 0.14), 1.70158) * settle(seg(p, 0.4, 1), 0.15)
	f.back = -SNAP_OPEN * wings -- swung forward, broadside: the silhouette opens
	f.raise = 6 * wings
	f.still = 0.6 * math.min(1, wings)
	if ranged then
		local e = outCubic(seg(p, 0, 0.1)) * settle(seg(p, 0.22, 1), 0.12)
		f.z = RANGED_KICK * e
		f.y = 0.04 * e
		f.pitch = 10 * e
		f.lift = 10 * e
		f.haloTilt = -8 * e
	else
		-- the leap (player note (a)): take-off at p = 0, the hop arc, landing on the target at LEAP_LAND (the hit)
		amp = amp or 1
		local air = seg(p, 0, LEAP_LAND)
		local reach, hop = LUNGE * amp, LEAP_H * amp
		if reachIn then -- (Task 9: the measured gap: the leap lands on the target's near edge)
			reach = reachIn
			hop = math.min(LEAP_H_MAX, (LEAP_H + LEAP_H_PER * reach) * amp)
		end
		-- the recoil's overshoot behind the start stays small on a long leap (<= 0.27 studs)
		local lunge = reach * smooth(air) * settle(seg(p, 0.38, 1), 0.18 * math.min(1, LUNGE / math.max(reach, 1e-3)))
		local k = reach > 1e-3 and math.min(1, lunge / LUNGE) or 0
		f.z = -lunge
		f.y = hop * sin(PI * air) -- the hop: up, over, down onto the target
			- 0.08 * sin(PI * seg(p, LEAP_LAND, 0.36)) -- a little squash on landing
		-- chin up on take-off, then nose down onto the hit (eased back with the recoil)
		f.pitch = 12 * sin(PI * seg(air, 0, 0.5)) - 16 * smooth(seg(air, 0.4, 1)) * settle(seg(p, 0.38, 1), 0)
		f.lift = -20 * k -- the tail streams flat behind
		f.haloY = -0.06 * k
		f.haloTilt = 10 * k
	end
end

POSES.Shoot = function(f, p)
	local kick = outCubic(seg(p, 0, 0.12)) * settle(seg(p, 0.3, 1), 0) -- the body kicks back, then settles (no overshoot: never forward)
	local snap = sin(PI * seg(p, 0, 0.18)) -- the head snaps forward and back (0 -> 1 -> 0)
	f.z = SHOOT_KICK * kick -- (+ = back: never forward of its spot)
	f.y = 0.08 * kick
	f.pitch = -14 * snap + 8 * kick * seg(p, 0.1, 0.24) -- nose down to loose the shot, then the chin comes up
	f.back = -20 * kick -- wings brace forward
	f.raise = -10 * snap + 4 * kick -- a downbeat with the shot
	f.lift = 22 * kick
	f.sway = 8 * sin(TAU * 1.5 * p) * kick
	f.haloTilt = -8 * kick
	f.still = 0.45 * kick
end

POSES.Recoil = function(f, p, ranged)
	local e = outCubic(seg(p, 0, 0.2)) * settle(seg(p, 0.35, 1), 0.12)
	f.z = (ranged and RANGED_KICK or 0.5) * e
	f.y = 0.12 * e
	f.pitch = 16 * e
	f.back = -15 * e -- wings flare forward to brace
	f.raise = 6 * e
	f.lift = -20 * e
	f.haloTilt = -10 * e
	f.still = 0.3 * e
end

POSES.Cast = function(f, p)
	local r = smooth(seg(p, 0, 0.42)) -- rise
	local up = outCubic(seg(p, 0.66, 0.74)) -- the release
	local rb = up * (1 - smooth(seg(p, 0.74, 0.95)))
	local hover = 0.03 * sin(TAU * seg(p, 0.42, 0.66) * 2) * plateau(p, 0.42, 0.48, 0.6, 0.66)
	local down = seg(p, 0.78, 1)
	local held = 1 - smooth(down)
	f.y = CAST_RISE * r * settle(down, 0.15) + hover
	f.z = -0.2 * rb -- a forward thrust with the release
	f.pitch = 10 * r * (1 - up) - 10 * rb -- looking up while gathering, a nod at the target on release
	f.back = -CAST_SPREAD * r * held -- spread wide (broadside)
	f.raise = r * held * (8 - 22 * rb) -- a downbeat on release
	f.lift = 25 * r * held
	f.haloY = 0.25 * r * held
	f.haloSpin = TAU * smooth(p)
	f.orbitSpin = TAU * smooth(p)
	f.lids = (p >= 0.32 and p < 0.62) and 1 or 0 -- eyes shut, gathering power
	f.still = 0.6 * r * held
end

-- (Pitch 2 item 5) one hit's reaction at t seconds of its own time (t <= 0: still to land; >= HURT_SECS: home) ->
-- knock-back 0..1 of KNOCK, lift (studs), pitch (deg), the wings' envelope 0..1, lids 0..1. The mock's
-- motion_pitch.enemy_new: knocked back in a jolt over HURT_OUT, the head snapped back, a springy rock dying away (faded
-- out by HURT_SECS), home over HURT_HOME0 .. HURT_SECS with a low lift (HURT_HOME: nothing slides)
local function hurtHit(t)
	if not (t > 0 and t < HURT_SECS) then
		return 0, 0, 0, 0, 0
	end
	local out = seg(t, 0, HURT_OUT)
	local home = seg(t, HURT_HOME0, HURT_SECS)
	local knock = outCubic(out) * (1 - smooth(home))
	local lift = JOLT * sin(PI * out) + HURT_HOME * sin(PI * home)
	local pitch = HURT_ROCK * outCubic(seg(t, 0, 0.06)) * math.exp(-t / 0.13) * cos(TAU * t / 0.3) * (1 - smooth(seg(t, 0.36, HURT_SECS)))
	local q = t / HURT_WINGS
	local env = outCubic(seg(q, 0, 0.12)) * settle(seg(q, 0.22, 1), 0.14)
	local lids = clamp01(q / 0.04) * (1 - seg(q, 0.58, 0.64))
	return knock, lift, pitch, env, lids
end

-- a hit's power (nil = 1; 0 .. 2)
local function hurtPower(v)
	v = tonumber(v)
	if v == nil or v ~= v then
		return 1
	end
	return math.max(0, math.min(2, v))
end

-- (Pitch 2 item 5 "Bounce in" A: the bitten pet of the approved mock; the old Hurt turned about the body's middle, dipped
-- 0.1 into the floor and rolled a side paw under it) one rigid body like the melee motion, pivoted on its paw lines:
-- knocked back KNOCK in the air (a JOLT off the floor over HURT_OUT: nothing slides), the head snapped back (nose up), a
-- springy rock (nose down onto the front paws, up again) dying away, home over the mock's way home with a low lift
-- (HURT_HOME: nothing slides); an evolved body (feet Hop 0.78) moves x its Hop. Its beats run in seconds: p 1 =
-- HURT_SECS (AttackFx's K.HURT). `amp` = the hit's power (nil = 1; a Double strike's re-hit 0.5). `hits` (Sample's reach;
-- look review r2, major 2: the mock ADDS each hit's reaction) = a re-hit's list of every hit it plays, its own included:
-- { Secs = its length in seconds (p 1), { Age = the hit's own reaction time at p 0 (an earlier hit > 0; its own, landing
-- after its hit stop, < 0), Power }, ... }; amp is then unused. Each hit reacts on its own time and the reactions add,
-- so a re-hit starts exactly where the pet is (never pulled toward its biter) and stacks on top
POSES.Hurt = function(f, p, _, amp, hits, feet)
	local w = heavyOf(feet)
	local list = type(hits) == "table" and hits or nil
	local secs = list and tonumber(list.Secs) or HURT_SECS
	if not (secs and secs == secs and secs > 0 and secs < 10) then
		secs = HURT_SECS
	end
	local t = p * secs
	local z, y, pitch, env, lids = 0, 0, 0, 0, 0
	local function add(at, power)
		if power <= 0 then
			return
		end
		local k, l, r, e, s = hurtHit(at)
		z, y, pitch = z + power * k, y + power * l, pitch + power * r
		env, lids = math.max(env, e), math.max(lids, s)
	end
	if list then
		for _, h in ipairs(list) do
			if type(h) == "table" then
				local age = tonumber(h.Age) or 0
				add(t + ((age == age) and age or 0), hurtPower(h.Power))
			end
		end
	else
		add(t, hurtPower(amp))
	end
	f.z = KNOCK * w * z
	f.y = w * y
	f.pitch = w * pitch
	f.paw = true
	f.raise = -22 * env -- wings clamp down
	f.back = 10 * env
	f.lift = -30 * env -- tail tucks
	f.haloY = 0.08 * env
	f.haloTilt = 18 * env -- knocked askew
	f.lids = lids
	f.still = 0.7 * env
end

POSES.Ko = function(f, p)
	f.z = 0.6 * outCubic(seg(p, 0, 0.45)) -- knocked back
	f.y = 0.3 * sin(PI * seg(p, 0, 0.32)) -- a little hop
		- 0.35 * smooth(seg(p, 0.2, 0.55)) -- down onto its side
		+ 0.05 * sin(PI * seg(p, 0.5, 0.64)) -- a small bounce
	f.roll = KO_ROLL * outBack(seg(p, 0.06, 0.5), 1.2) -- tumbles over (~95), settles at 90
	f.pitch = 10 * sin(PI * seg(p, 0, 0.4))
	local limp = smooth(seg(p, 0.25, 0.7))
	f.raise = -20 * limp
	f.back = 45 * limp -- folded back along the body (lying on its side, they stay out of the floor)
	f.lift = -25 * limp
	f.haloTilt = 35 * smooth(seg(p, 0.2, 0.7))
	f.haloY = -0.12 * smooth(seg(p, 0.2, 0.7))
	f.lids = seg(p, 0.2, 0.24)
	f.still = smooth(seg(p, 0.15, 0.6))
end

POSES.Victory = function(f, p)
	local crouch = smooth(seg(p, 0, 0.14)) * (1 - smooth(seg(p, 0.14, 0.2)))
	local u = seg(p, 0.16, 0.74) -- in the air
	local air = sin(PI * u)
	local land = outCubic(seg(p, 0.74, 0.8)) * settle(seg(p, 0.8, 1), 0.1)
	f.y = -0.15 * crouch + HOP * 4 * u * (1 - u) - 0.12 * land
	f.yaw = 360 * smooth(u)
	f.pitch = 12 * air
	f.back = -30 * air -- opened wide in the air
	f.raise = 10 * air - 10 * land
	f.lift = 30 * air
	f.haloY = 0.12 * air
	f.haloSpin = TAU * smooth(seg(p, 0.2, 0.85))
	f.orbitSpin = TAU * smooth(u)
end

POSES.IdleBattle = function(f, t)
	local breath = sin(TAU * t / 1.8)
	f.y = BREATH * breath
	f.pitch = 1.2 * sin(TAU * t / 1.8 - 0.7)
	f.raise = 3 * breath
	-- the glance of this cell (cells never overlap: it starts 0..1 s in and lasts GLANCE_TIME)
	local cell = floor(t / GLANCE_CELL)
	local start = cell * GLANCE_CELL + hash(cell)
	local u = (t - start) / GLANCE_TIME
	if u > 0 and u < 1 then
		local env = outCubic(seg(u, 0, 0.25)) * (1 - smooth(seg(u, 0.6, 1)))
		local dir = (hash(cell + 7919) < 0.5) and -1 or 1
		f.yaw = dir * (10 + 3 * hash(cell + 104729)) * env
		f.roll = -dir * 3 * env -- a curious head tilt
		f.sway = dir * 15 * env -- and a tail flick
	end
end

-- (Pitch 2 item 5) the wings snap open into a bite and fold back with the chomp; the tail streams flat while it hops
local function biteWings(f, p, air)
	local R = PetPoses.DASH_RUN
	local wings = outBack(seg(p, R - 0.08, R), 1.70158) * (1 - smooth(seg(p, R + 0.4 * (1 - R), 1)))
	f.back = f.back - SNAP_OPEN * wings
	f.raise = f.raise + 6 * wings
	f.lift = f.lift - 20 * air
	f.haloTilt = 10 * air
	f.still = math.max(f.still, 0.6 * math.min(1, wings + air))
end

-- (battle-feel T2; Pitch 2 item 5 "Bounce in" A) the melee dash in: from the Windup's load, hop, nod on the front paws,
-- hop-bite onto the target on the hit (DASH_RUN), the chomp, held at the edge (p 1 = exactly (0, 0, -reach), upright)
POSES.DashIn = function(f, p, _, amp, reachIn, feet)
	local reach = reachIn or LUNGE * (amp or 1)
	local R = PetPoses.DASH_RUN
	local k = hopK() * heavyOf(feet)
	local u = seg(p, 0, R) -- through Melee.In: hop 0.13 s, nod 0.04, hop-bite 0.13
	local mid = -0.48 * reach
	if p < R then
		if not hop(f, u, 0, 13 / 30, 0, mid, BH.In1 * k, 15, -6) then
			if u < 17 / 30 then -- the nod: landed on the front paws, the nose dips and comes up (dust)
				f.z = mid
				f.pitch = keys(u, { 13 / 30, -6, 15 / 30, -10, 17 / 30, -2 })
			else
				hop(f, u, 17 / 30, 1, mid, -reach, BH.In2 * k, -2, -15)
			end
		end
	else
		f.z = -reach
		f.pitch = keys(seg(p, R, 1), CHOMP)
	end
	-- the wind-up's sweep (wings back, tail up, halo lagging) lets go over the first hop
	local wound = 1 - smooth(seg(u, 0, 0.35))
	f.back = WINDUP_BACK * wound
	f.raise = -10 * wound
	f.lift = 30 * wound
	f.haloY = 0.05 * wound
	f.still = 0.35 * wound
	biteWings(f, p, (p < R) and sin(PI * u) or 0)
	grounded(f)
end

-- (battle-feel T2; Pitch 2 item 5) the way home: hop back, a rock on the hind paws as it lands, hop home (at BACK_HOME),
-- a rocking settle on the spot; from (0, 0, -reach) at p 0 to rest at p 1
POSES.DashBack = function(f, p, _, amp, reachIn, feet)
	local reach = reachIn or LUNGE * (amp or 1)
	local k = hopK() * heavyOf(feet)
	local t = p * 0.56 -- the beats in seconds at Melee.Back 0.40 (Dur 0.56)
	local mid = -0.45 * reach
	if not hop(f, t, 0, 0.16, -reach, mid, BH.Back1 * k, 0, 9) then
		if t < 0.19 then -- landed on the hind paws first: rocks back, then level
			f.z = mid
			f.pitch = keys(t, { 0.16, 9, 0.175, 12, 0.19, 3 })
		elseif not hop(f, t, 0.19, 0.35, mid, 0, BH.Back2 * k, 3, 8) then
			f.pitch = keys(t, { 0.35, 8, 0.41, -5, 0.48, 2, 0.56, 0 }) -- home: the rocking settle
		end
	end
	local air = clamp01(f.y / 0.3)
	f.back = -20 * air -- wings flare to brake
	f.raise = 4 * air
	f.lift = 15 * air
	f.still = 0.4 * air
	grounded(f)
end

-- (Pitch 2 item 5) a flurry's bite (no trip home): a rebound hop back, a rock, a hop-bite onto the face on the hit, the
-- chomp; `offIn` = studs behind the face it starts (0 at the face); held at the face (p 1 = (0, 0, -off), upright)
POSES.DashBite = function(f, p, _, _, offIn, feet)
	local off = math.max(0, offIn or 0)
	local R = PetPoses.DASH_RUN
	local k = hopK() * heavyOf(feet)
	local rb = math.max(0, PetPoses.REBOUND - off) -- (in place when it already stands that far back)
	-- through the run: rebound 0.12 s, rock 0.06, hop-bite 0.12 (gate review r0: the rock was 0.03 s, an 8.8 deg snap in
	-- one 60 fps frame; the strip's rock is 0.06 s: 7 -> 10 deg in 0.02, back to level in 0.04)
	local u = seg(p, 0, R)
	if p < R then
		if not hop(f, u, 0, 12 / 30, 0, rb, BH.Rebound * k, 0, 7) then
			if u < 18 / 30 then
				f.z = rb
				f.pitch = keys(u, { 12 / 30, 7, 14 / 30, 10, 18 / 30, 0 })
			else
				hop(f, u, 18 / 30, 1, rb, -off, BH.Bite * k, 0, -15)
			end
		end
	else
		f.z = -off
		f.pitch = keys(seg(p, R, 1), CHOMP)
	end
	biteWings(f, p, (p < R) and clamp01(f.y / 0.2) or 0)
	grounded(f)
end

-- (Pitch 2 item 5) a Double strike's second chomp at the face: up, the second bite down at DOUBLE_BITE, upright
POSES.DashDouble = function(f, p)
	f.pitch = keys(p, { 0, -15, 0.33, -3, PetPoses.DOUBLE_BITE, -17, 1, 0 })
	local w = (p < 1) and sin(PI * p) or 0 -- (exactly 0 at rest: sin(pi) leaves a crumb)
	f.back = -SNAP_OPEN * 0.5 * w
	f.raise = 4 * w
	f.still = 0.5 * w
	grounded(f)
end

-- (Pitch 2 item 5) a bite on a Thorns shield: the prick snaps the head back (rocked onto the hind paws, eyes shut), a hop
-- away `back` studs (nil = THORN_BACK), a rock as it lands; held there (p 1 = (0, 0, +back), upright)
POSES.DashThorns = function(f, p, _, _, backIn, feet)
	local back = math.max(0, backIn or PetPoses.THORN_BACK)
	local t = p * PetPoses.THORN_DUR
	if t < 0.12 then
		f.pitch = keys(t, { 0, -15, 0.05, 14, 0.12, 8 })
	elseif not hop(f, t, 0.12, 0.28, 0, back, BH.Thorn * hopK() * heavyOf(feet), 8, 6) then
		f.z = back
		f.pitch = keys(t, { 0.28, 6, 0.31, 9, 0.34, 0 })
	end
	local env = (t < 0.24) and sin(PI * t / 0.24) or 0
	f.raise = -15 * env -- wings clamp down, the tail tucks (the sting)
	f.lift = -30 * env
	f.haloTilt = 12 * env
	f.lids = (t >= 0.02 and t < 0.14) and 1 or 0
	f.still = 0.6 * env
	grounded(f)
end

-- (Pitch 2 item 5) ready on the spot between a flurry's bites (t = seconds): little hops, a rock with each, on the floor
-- and level at every multiple of READY_BOUNCE
POSES.DashReady = function(f, t)
	local b = PetPoses.READY_BOUNCE
	local s = sin(PI * t / b)
	f.y = BH.Ready * hopK() * math.abs(s)
	f.pitch = 1.5 * s
	f.lift = 10 * math.abs(s)
	f.still = 0.3
	grounded(f)
end

----------------------------------------------------------------------
-- Sample
----------------------------------------------------------------------
local function newFrame()
	return {
		x = 0, y = 0, z = 0, pitch = 0, yaw = 0, roll = 0,
		raise = 0, back = 0, lift = 0, sway = 0,
		haloY = 0, haloTilt = 0, haloSpin = 0, orbitSpin = 0,
		lids = 0, still = 0,
		paw = nil, -- (Pitch 2 item 5) nil = the old turn about the root; true = about the paw line on the floor (pawBody)
	}
end

-- (Pitch 2 item 5) a paw-line value from `feet` (finite, 0 .. 50 studs) or the typical pet's
local function footOf(feet, key)
	local v = type(feet) == "table" and tonumber(feet[key]) or nil
	if v == nil or v ~= v or v < 0 or v > 50 then
		return PetPoses.FEET[key]
	end
	return v
end

-- (Pitch 2 item 5) the body of a paw-pivoted frame: the turn about the paw line it rocks onto on the floor (hind paws for
-- nose up, front paws for nose down), about the root in the air, blended by its height; then lifted if a paw line would go
-- under the floor (the floor is Down under the root at rest)
local function pawBody(f, rot, feet)
	local down, front, hind = footOf(feet, "Down"), footOf(feet, "Front"), footOf(feet, "Hind")
	local paw = (f.pitch >= 0) and hind or front
	-- the blend height: at least BLEND_H, and never so low that the paw it left dips back under the floor while the body
	-- rises (a long body pitched far: its paw would stay on the floor and slide)
	local blend = math.max(BLEND_H, 1.25 * paw * math.abs(sin(rad(f.pitch))))
	local gw = 1 - clamp01(f.y / blend)
	local piv = Vector3.new(0, -down * gw, ((f.pitch >= 0) and hind or -front) * gw)
	local body = CFrame.new(f.x, f.y, f.z) * CFrame.new(piv) * rot * CFrame.new(-piv)
	local lo = math.min((body * Vector3.new(0, -down, hind)).Y, (body * Vector3.new(0, -down, -front)).Y) + down
	if lo < 0 then
		body = CFrame.new(0, -lo, 0) * body
	end
	return body
end

-- the frame of plain numbers of `name` at p (Sample's arguments checked; `feet` handed on: the melee motion's weight)
local function frameOf(name, p, ranged, amp, reach, feet)
	local fn = POSES[name]
	local f = newFrame()
	p = tonumber(p) or 0
	if p ~= p or p == math.huge or p == -math.huge then
		p = 0
	end
	if fn then
		if not PetPoses.Loops[name] then
			p = clamp01(p)
		end
		if name == "Hurt" then
			-- (Pitch 2 item 5, look review r2) the Hurt reads its own power (amp, under 1 for a Double strike's re-hit) and
			-- its re-hit's hits (reach: a table); it checks both itself
			fn(f, p, ranged == true, amp, reach, feet)
			return f
		end
		amp = tonumber(amp) or 1
		if amp ~= amp then
			amp = 1
		end
		reach = tonumber(reach)
		if reach ~= nil and (reach ~= reach or reach == math.huge or reach == -math.huge) then
			reach = nil
		elseif reach ~= nil then
			reach = math.max(0, math.min(PetPoses.LEAP_REACH_MAX, reach))
		end
		fn(f, p, ranged == true, math.max(1, math.min(PetPoses.LEAP_AMP_MAX, amp)), reach, feet)
	end
	return f
end

-- (Pitch 2 item 5) PetPoses.Offset(name, p, ranged, amp, reach, feet) -> Vector3: the pose's own move (studs, the pet's
-- frame) without its turn: where a paw-pivoted pose's paw lines have got to (the Body's position also carries the turn
-- about them). AttackFx starts a run caught on the way home from it. `feet` (optional): its Hop weighs the hops
function PetPoses.Offset(name, p, ranged, amp, reach, feet)
	local f = frameOf(name, p, ranged, amp, reach, feet)
	return Vector3.new(f.x, f.y, f.z)
end

-- Sample(name, p, ranged, amp, reach, feet): `feet` (Pitch 2 item 5, optional) = { Down, Front, Hind } pose studs from
-- the root to the floor / the front paw line (forward) / the hind paw line (back), and Hop (the body's weight: its hops
-- x Hop, an evolved form's 0.78); only the melee motion and the Hurt read it
function PetPoses.Sample(name, p, ranged, amp, reach, feet)
	local f = frameOf(name, p, ranged, amp, reach, feet)
	local raise, back = rad(f.raise), rad(f.back)
	local rot = CFrame.fromEulerAnglesYXZ(rad(f.pitch), rad(f.yaw), rad(f.roll))
	return {
		Body = f.paw and pawBody(f, rot, feet) or (CFrame.new(f.x, f.y, f.z) * rot),
		Groups = {
			wing = CFrame.Angles(0, back, -raise),
			cloud = CFrame.Angles(0, 0.3 * back, -0.3 * raise), -- Stormfang's cloud halves: a mild echo, they never spread
			tail = CFrame.Angles(-rad(f.lift), rad(f.sway), 0),
			bob = CFrame.new(0, f.haloY, 0) * CFrame.fromEulerAnglesYXZ(0, f.haloSpin, rad(f.haloTilt)),
			orbit = CFrame.Angles(0, f.orbitSpin, 0),
		},
		Lids = clamp01(f.lids),
		Still = clamp01(f.still),
	}
end

return PetPoses
