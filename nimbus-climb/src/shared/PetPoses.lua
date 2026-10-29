-- PetPoses: how a pet's body moves with its attacks (docs/superpowers/specs/2026-10-23-pet-attack-vfx-design.md
-- "Pet body animation", plan docs/superpowers/plans/2026-10-23-pet-attack-vfx.md Task 5). Poses ride on PetBuilder's
-- existing weld-free rig: a pose is a body offset (the caller applies it to the root) plus a rotation per animated
-- group kind that PetBuilder.Animate multiplies onto its own idle motion (opts.Pose). Pure: no Instances, no
-- services, no yields (CFrame / Vector3 values only); safe on the server and the client. Plain Lua 5.1-compatible
-- syntax only.
--
-- API:
--   PetPoses.Names = { "Windup", "Strike", "Shoot", "Recoil", "Cast", "Hurt", "Ko", "Victory", "IdleBattle" }
--   PetPoses.Loops = { IdleBattle = true }   p is TIME in seconds (any value; never at rest)
--   PetPoses.Holds = { Ko = true }           p = 1 is the pose's end state, held (the KO'd pet lies on its side until
--                                            the poof covers it and the model is parked); every other one-shot pose
--                                            is exactly at rest at p = 0 and p = 1, so starting / stopping never pops
--   PetPoses.Sample(name, p, ranged, amp, reach) -> {
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
--   Windup     crouch 0.25 studs, wings swept back 25 deg and folded tight, tail up and lashing; ranged rears back
--              (weight back, chin up). Holds the crouch, then springs up (the push-off into Strike).
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
--   Hurt       squash dip + flinch back 0.3 studs, head snaps back, a decaying wobble, wings clamp down, tail tucks,
--              halo knocked askew, lids shut (p 0.04 .. 0.58).
--   Ko         knocked back 0.6 + a little hop, tumbles 90 deg onto its side (overshoot ~95, settle), drops 0.35,
--              wings fold back limp along the body, tail limp (Still -> 1), halo slides askew, eyes shut. Holds at p = 1.
--   Victory    a quick crouch, hop 1.2 studs with a full 360 deg spin (fastest mid-air), chin up, wings open, tail up,
--              halo spinning, then a squash landing that settles.
--   IdleBattle breathing 0.05 studs (1.8 s), and every 2-4 s a glance: a 10-13 deg look aside with a curious head tilt
--              and a tail flick (the rig has no ear / head groups: the glance turns the whole body).

local PetPoses = {}

PetPoses.Names = { "Windup", "Strike", "Shoot", "Recoil", "Cast", "Hurt", "Ko", "Victory", "IdleBattle" }
PetPoses.Loops = { IdleBattle = true }
PetPoses.Holds = { Ko = true }

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
local FLINCH = 0.3
local KO_ROLL = 90
local HOP = 1.2
local BREATH = 0.05
local GLANCE_CELL = 3 -- one glance per cell, starting 0..1 s into it: 2-4 s between two glances
local GLANCE_TIME = 1.1

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

POSES.Windup = function(f, p, ranged)
	local a = smooth(seg(p, 0, 0.5)) -- gather into the crouch
	local r = seg(p, 0.82, 1) -- spring up (accelerating: the push-off)
	a = a * (1 - r * r)
	f.y = -CROUCH * a
	if ranged then
		f.z = 0.2 * a
		f.pitch = 8 * a
	else
		f.z = 0.1 * a
		f.pitch = -7 * a -- head low, eyes on the target
	end
	f.back = WINDUP_BACK * a
	f.raise = -10 * a
	f.lift = 30 * a
	f.sway = 12 * sin(TAU * 2 * p) * a -- the tail lashes before the pounce
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

POSES.Hurt = function(f, p)
	local env = outCubic(seg(p, 0, 0.12)) * settle(seg(p, 0.22, 1), 0.14)
	f.z = FLINCH * env
	f.y = -0.1 * env -- the squash: a quick dip
	f.pitch = 12 * env -- the head snaps back
	f.roll = 6 * sin(TAU * 3 * p) * env -- a decaying wobble
	f.raise = -22 * env -- wings clamp down
	f.back = 10 * env
	f.lift = -30 * env -- tail tucks
	f.haloY = 0.08 * env
	f.haloTilt = 18 * env -- knocked askew
	f.lids = clamp01(p / 0.04) * (1 - seg(p, 0.58, 0.64))
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

----------------------------------------------------------------------
-- Sample
----------------------------------------------------------------------
local function newFrame()
	return {
		x = 0, y = 0, z = 0, pitch = 0, yaw = 0, roll = 0,
		raise = 0, back = 0, lift = 0, sway = 0,
		haloY = 0, haloTilt = 0, haloSpin = 0, orbitSpin = 0,
		lids = 0, still = 0,
	}
end

function PetPoses.Sample(name, p, ranged, amp, reach)
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
		fn(f, p, ranged == true, math.max(1, math.min(PetPoses.LEAP_AMP_MAX, amp)), reach)
	end
	local raise, back = rad(f.raise), rad(f.back)
	return {
		Body = CFrame.new(f.x, f.y, f.z) * CFrame.fromEulerAnglesYXZ(rad(f.pitch), rad(f.yaw), rad(f.roll)),
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
