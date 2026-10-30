--!nonstrict
-- Config: every tuning value of the active-ragdoll sandbox lives here.
-- Units: studs, seconds, Roblox mass units (RMU). Angles in degrees unless noted.

local Config = {}

Config.Version = "v3.0"
Config.GameName = "RAGDOLL SANDBOX"

------------------------------------------------------------------------
-- Locomotion
------------------------------------------------------------------------
Config.WalkSpeed = 14
Config.RunSpeed = 21
Config.CrouchSpeed = 7
Config.ProneSpeed = 3.6
Config.CrawlSpeed = 3.2 -- downed (legs gone) crawling speed with both arms
Config.LimpSpeedMultiplier = 0.45 -- one leg broken
Config.GroundAccel = 85 -- max horizontal acceleration while grounded (studs/s^2)
Config.AirAccel = 14
Config.TumbleAirAccel = 5
Config.VelocityGain = 8 -- how hard velocity error is corrected (1/s)
Config.JumpVelocity = 42
Config.JumpCooldown = 0.5
Config.CoyoteTime = 0.12
Config.JumpHoverLock = 0.22 -- seconds after a jump where the standing spring is off

------------------------------------------------------------------------
-- Standing spring (keeps the hips at leg height above the ground)
------------------------------------------------------------------------
Config.LegLength = 2.0 -- hip pivot to sole
Config.TorsoHalfHeight = 1.0
Config.FootClearance = 0.1
Config.SpringK = 175
Config.SpringD = 24
Config.MaxSupportFactor = 2.4 -- spring force cap as a multiple of body weight
Config.GroundTolerance = 0.65 -- how far above stand height we still count as grounded
Config.ProbeExtra = 1.8
Config.StepUpMax = 2.05 -- everything the torso does not touch counts as a step
Config.StepLookAhead = 0.7 -- + speed * StepLookAheadPerSpeed
Config.StepLookAheadPerSpeed = 0.06
Config.WalkBob = 0.7 -- how much the hips drop while the legs swing (1 = full leg geometry)
Config.SlopeFeedForward = 1 -- follow stairs / ramps with the right vertical speed (no lag)
Config.StepAssistRise = 0.35 -- obstacles between this and StepUpMax get a little hop when you walk into them
Config.StepAssistCooldown = 0.35
Config.MaxWalkableSlope = 52
Config.CrouchLegAngle = 42 -- deg forward
Config.CrouchLegSplay = 22
Config.ProneHeight = 0.62 -- torso centre above ground while lying

------------------------------------------------------------------------
-- Balance (torso stays upright with a limited torque so it can be knocked over)
------------------------------------------------------------------------
Config.BalanceTorque = 9000
Config.BalanceResponsiveness = 30
Config.LeanForward = 7 -- deg at full speed
Config.WaddleRoll = 3.5 -- deg side sway per step
Config.ReachLeanDown = 34 -- deg the torso bends when the hands reach to the floor
Config.ReachTwist = 24 -- deg the torso turns towards a hand that reaches sideways
Config.StumbleTilt = 30 -- deg: start stumbling
Config.FallTilt = 62 -- deg: fall over (ragdoll)
Config.StumbleMaxTime = 1.5
Config.StumbleRecoverTilt = 12

-- running into a wall
Config.WallSlamMinSpeed = 15.5 -- horizontal speed before the hit
Config.WallSlamStopRatio = 0.4 -- speed must drop below this fraction within ~0.1 s
Config.WallSlamBounce = 0.75 -- fraction of the speed you are thrown back with
Config.WallSlamHurtSpeed = 26 -- above this the slam also hurts

------------------------------------------------------------------------
-- Procedural legs / arms
------------------------------------------------------------------------
Config.StepAmplitude = 38 -- deg leg swing at walk speed
Config.StepAmplitudeMax = 48
Config.IdleLegSplay = 4
Config.ArmSwingFactor = 0.65
Config.ArmIdleForward = 8
Config.ArmIdleOut = 6
Config.FootIKBlend = 1.0 -- 0 = no foot placement, 1 = feet always on the surface
Config.SlopeFootAlign = 0.45 -- how much legs tilt to stand flat on slopes

Config.LegMuscleTorque = 3400
Config.LegMuscleResponsiveness = 55
Config.ArmMuscleTorque = 2000
Config.ArmMuscleResponsiveness = 42
Config.MuscleMaxAngularVelocity = 30
Config.JointFriction = 22 -- BallSocket MaxFrictionTorque, gives ragdolls a natural damping

-- strength multipliers per state {legs, arms}
Config.StateStrength = {
	Standing = { 1.0, 1.0 },
	Stumbling = { 1.15, 0.8 },
	Airborne = { 0.75, 0.8 },
	Hanging = { 0.3, 1.7 },
	Tumble = { 0.4, 0.45 },
	Ragdoll = { 0.0, 0.0 },
	GettingUp = { 1.2, 0.8 },
	Prone = { 0.35, 1.0 },
	Diving = { 0.6, 0.8 },
	DropKick = { 0.9, 0.7 },
	Flying = { 0.8, 0.9 },
	Swimming = { 0.6, 0.8 },
	Driving = { 0.5, 0.6 },
	Downed = { 0.05, 1.0 },
	Dead = { 0.0, 0.0 },
}
Config.BrokenLimbStrength = 0.02

------------------------------------------------------------------------
-- Falling / ragdoll
------------------------------------------------------------------------
Config.TumbleFallSpeed = 68 -- downward speed that makes you lose control mid-air
Config.TumbleMinAirTime = 0.45
Config.RagdollMinTime = 1.1
Config.RagdollMaxTime = 3.6
Config.GetUpTime = 0.95
Config.ManualRagdollTime = 1.2

------------------------------------------------------------------------
-- Grabbing / climbing
------------------------------------------------------------------------
Config.GrabRadius = 0.6
Config.ArmReach = 1.5 -- shoulder pivot to hand
Config.ReachConverge = 3.6 -- arms converge this far in front of the chest
Config.GripFrictionTorque = 260 -- held objects do not spin freely
Config.GripBreakDistance = 2.4 -- constraint stretched this far -> grip slips
Config.MaxGrabDistanceServer = 16
Config.ClimbPullFactor = 1.8 -- climb assist force cap (x body weight)
Config.ClimbSpeed = 6.5 -- studs/s you pull yourself up while holding Space on a hold
Config.MantleSpeed = 9 -- forward speed when climbing over the top edge
Config.MantlePush = 16 -- (v2.8) studs/s: the push forward onto the top once the hands let go of the edge
Config.ClimbRegripStep = 1.35 -- how much higher the next hand grabs when climbing a wall
Config.ClimbRegripCooldown = 0.32
-- holding something solid never locks you: trying to move without getting anywhere lets go
Config.GripStuckDistance = 0.6 -- studs of torso movement that count as progress
Config.GripStuckTime = 0.6 -- s pushing (walk keys / Space) without progress -> the hand slips off
Config.GripStuckTimeClimb = 1.1 -- same while hanging / climbing
Config.HoldArmSoftness = 0.12 -- arm muscle strength while it just holds on (1 = full): the arm acts like a rope
-- Holding something solid (wall, floor, anchored part): there is NO joint to the world. A force
-- holds the hand at the spot (like a strong spring with a limit), so pulling on the arm or climbing
-- moves YOUR BODY, never the wall, and nothing can lock the body in place.
Config.HoldForce = 2.6 -- x body weight one hand can hold
Config.HoldResponsiveness = 45
Config.KeepAwakeInterval = 0.2 -- s: tiny nudge so the physics engine never puts the body to sleep
Config.FloorPullSpeed = 1.8 -- lying down + holding the floor: drag yourself towards the hand (x crawl speed)
Config.FloorPullDone = 1.1 -- studs: you reached the hand, it lets go so you can grab further ahead
Config.HeavyRatio = 3.5 -- objects heavier than body * ratio count as climbable anchors
Config.ThrowBoost = 0.55 -- extra velocity transferred to light objects on release
-- aim (G or that hand's mouse button) + let go: the item is thrown at the crosshair
Config.ThrowSpeedMax = 110 -- studs/s for light things (heavier = slower)
Config.ThrowSpeedMin = 45
Config.ThrowRange = 260
Config.ThrownBladeDamage = 38 -- a thrown blade / knife that sticks in a body (+ per speed)
Config.ThrownBladeDamagePerSpeed = 0.35
Config.ThrownBluntDamage = 0.11 -- x mass x speed for everything else (a thrown bat, a gun)
Config.ThrownBluntMax = 70
Config.CarrySlowdownRatio = 2.5 -- held mass / body mass where you reach max slowdown
Config.MaxDragRatio = 2.6 -- extra pulling force is computed for at most this much mass (x body mass)
Config.DragStrength = 0.55 -- extra pulling force per unit of held weight
Config.MassToKg = 7.65 -- display only: 1 RMU ~ 7.65 kg (an R6 body ~ 75 kg)

------------------------------------------------------------------------
-- Damage / gore
------------------------------------------------------------------------
Config.ImpactMin = 50 -- velocity change (studs/s) below which nothing happens
Config.DamagePerSpeed = 1.5
Config.KnockdownImpact = 72 -- delta-v that knocks you over
Config.BumpImpact = 34 -- delta-v that makes you stumble
Config.ImpactCooldown = 0.22
Config.LimbMultiplier = {
	Head = 1.4,
	Torso = 0.85,
	LeftArm = 1.0,
	RightArm = 1.0,
	LeftLeg = 0.9,
	RightLeg = 0.9,
}
Config.LimbMaxHP = 100
Config.InjuredHP = 45 -- below this: wounds and light bleeding
Config.SeverHP = -60 -- accumulated HP at which a limb comes off
Config.SeverSingleHit = 130 -- one hit this strong severs instantly
Config.DecapitateHP = -35
Config.DecapitateSingleHit = 120
Config.GibHit = 165 -- torso/head hit that also throws gibs
Config.BleedSevered = 2.2 -- blood/s per severed limb
Config.BleedBroken = 0.45
Config.BleedDuration = 22
Config.HealDelay = 8
Config.HealRate = 1.5 -- HP/s for limbs that are not broken
Config.MaxWoundsPerLimb = 7
Config.RespawnTime = 5
Config.CorpseLifetime = 45
Config.MaxCorpsesPerPlayer = 2

-- getting hit by objects: kinetic energy 0.5 * reduced mass * v^2
Config.ObjectHitMinSpeed = 9 -- relative speed below which object contact is ignored
Config.ObjectEnergyMin = 1100 -- energy that does no damage yet
Config.ObjectEnergyPerDamage = 38
Config.ObjectKnockdownEnergy = 2400
-- being crushed by something resting on you
Config.CrushForceMin = 2100 -- ~ 11 RMU resting on a limb
Config.CrushForcePerDamage = 420 -- (force - min) / this = damage per second

-- sharp things: thin rods, points and blades pierce depending on speed and sharpness
Config.PierceSpeedDull = 100 -- studs/s (~100 km/h) needed for barely sharp objects
Config.PierceSpeedSharp = 18.5 -- studs/s needed for a needle-sharp spike (sprint = 21, walk = 14)
Config.PierceDamage = 1.3 -- damage per stud/s above the threshold
Config.PierceBase = 16
Config.PierceBleedTorso = 1.4 -- blood/s
Config.PierceBleedLimb = 0.7
Config.PierceCooldown = 0.7 -- s: the same body part is not stabbed again right away
Config.PierceKnockSpeed = 32 -- studs/s: stabbed faster than this knocks you over, slower = you stumble
Config.ImpaleTime = 5 -- s: only the stabbed body part sticks to the spike; after this it tears free
Config.ImpaleStruggleTime = 0.9 -- s of holding a move key / Space to tear free sooner
Config.ImpaleTearDamage = 10
Config.PinForce = 5 -- x body weight that holds a stabbed body part on the spike

-- strikes (your hand / held object hitting someone else)
Config.StrikeMinSpeed = 14
Config.StrikeKnockSpeed = 24
Config.StrikeImpulse = 3.2 -- impulse per (speed * striker mass)

------------------------------------------------------------------------
-- Gun (semi-auto pistol, no reload)
------------------------------------------------------------------------
Config.GunMagazine = 12
Config.GunFireInterval = 0.14
Config.GunRange = 650
Config.GunRecoil = 9 -- impulse on the gun (x gun mass)
Config.GunAimAssist = 7 -- deg: if the barrel is this close to what you aim at, the bullet goes exactly there
Config.GunOriginTolerance = 18 -- studs the claimed muzzle may be away from the server's copy of your torso
Config.GunHitTolerance = 10 -- studs a claimed hit on a moving body may be away from the server's copy of it
Config.BulletDamage = {
	Head = 400, -- always fatal
	Torso = 52,
	LeftArm = 58,
	RightArm = 58,
	LeftLeg = 62,
	RightLeg = 62,
}
Config.BulletBleed = { Torso = 1.4, Head = 3, Limb = 0.7 }
Config.BulletBleedTime = 30
Config.BulletImpulse = 14 -- studs/s given to the hit part
Config.BulletTorsoKnockdown = 1.6 -- seconds on the ground after a torso hit
Config.BulletPush = 26 -- studs/s the hit body part is knocked by a pistol bullet (head shots snap the head back)

-- per gun: magazine, time between shots, damage factor, push on the hit body part, reload time
-- (= how long the free hand has to touch the gun), spread in degrees (hip fire), limbMult = damage
-- factor on arms / legs, severLimbs = enough hits shoot a limb off
Config.Guns = {
	pistol = { mag = 12, interval = 0.14, damageMult = 1, push = 26, reload = 1.0, range = 650, recoil = 7, spread = 0 },
	revolver = { mag = 6, interval = 0.42, damageMult = 1.7, limbMult = 0.95, severLimbs = true, push = 44, reload = 1.6, range = 700, recoil = 16, spread = 0 },
	rifle = { mag = 30, interval = 0.095, damageMult = 0.62, push = 18, reload = 1.4, range = 650, recoil = 4, auto = true, spread = 0.9 },
	smg = { mag = 25, interval = 0.065, damageMult = 0.45, push = 14, reload = 1.1, range = 350, recoil = 3, auto = true, spread = 2.4 },
	shotgun = { mag = 6, interval = 0.75, damageMult = 1, push = 11, reload = 1.8, range = 420, recoil = 22, spread = 0 },
	sniper = { mag = 5, interval = 1.3, damageMult = 3.2, severLimbs = true, push = 75, reload = 2.0, range = 2500, recoil = 95, spread = 6, scope = true, knockback = 70 },
	launcher = { mag = 1, interval = 0.8, damageMult = 1, push = 0, reload = 2.4, range = 600, recoil = 45, spread = 0, projectile = true },
	sleepdart = { mag = 3, interval = 0.6, damageMult = 0.05, push = 4, reload = 1.2, range = 160, recoil = 2, spread = 0, dart = "sleep" },
	healdart = { mag = 3, interval = 0.6, damageMult = 0, push = 0, reload = 1.2, range = 160, recoil = 2, spread = 0, dart = "heal" },
	smartpistol = { mag = 15, interval = 0.16, damageMult = 0.85, push = 22, reload = 1.1, range = 500, recoil = 5, spread = 0, smart = true }, -- (v2.8)
	smartsmg = { mag = 30, interval = 0.08, damageMult = 0.4, push = 12, reload = 1.3, range = 300, recoil = 2.5, auto = true, spread = 2.0, smart = true },
	paradart = { mag = 2, interval = 0.8, damageMult = 0.05, push = 4, reload = 1.6, range = 140, recoil = 2, spread = 0, dart = "para" }, -- (v2.8)
	crossbow = { mag = 1, interval = 0.5, damageMult = 2.3, push = 46, reload = 1.5, range = 700, recoil = 5, spread = 0, bolt = true, knockback = 26 },
	minigun = { mag = 150, interval = 0.045, damageMult = 0.5, push = 12, reload = 3.6, range = 500, recoil = 1.6, auto = true, spread = 2.6, spinup = true },
	-- v2.0
	usp = { mag = 12, interval = 0.15, damageMult = 1.05, push = 24, reload = 1.0, range = 650, recoil = 5, spread = 0, suppressed = true },
	mp5 = { mag = 30, interval = 0.075, damageMult = 0.52, push = 15, reload = 1.2, range = 420, recoil = 2.4, auto = true, spread = 1.3 },
	garand = { mag = 8, interval = 0.24, damageMult = 2.7, limbMult = 1.05, severLimbs = true, push = 56, reload = 1.6, range = 1400, recoil = 21, spread = 0.15, knockback = 16, enbloc = true },
	lockon = { mag = 1, interval = 0.8, damageMult = 1, push = 0, reload = 2.8, range = 900, recoil = 40, spread = 0, projectile = true, lockon = true },
	taser = { mag = 1, interval = 0.5, damageMult = 0, push = 6, reload = 1.6, range = 38, recoil = 2, spread = 0, taser = true },
	harpoon = { mag = 1, interval = 0.5, damageMult = 0, push = 0, reload = 1.8, range = 160, recoil = 14, spread = 0, harpoon = true },
	flaregun = { mag = 1, interval = 0.5, damageMult = 0, push = 0, reload = 1.4, range = 600, recoil = 9, spread = 0, projectile = true, flare = true },
}
-- (v2.0) bullets go through bodies: how many studs of body a bullet of this gun can still pass through (a body part
-- is about 1 stud thick front to back, a torso 2 studs side to side). What is left flies on and hits what is
-- behind (another body part, another person, the wall) with less damage, and the exit wound sprays blood forward.
Config.Penetration = {
	pistol = 1.3, usp = 1.4, revolver = 2.2, rifle = 2.8, smg = 1.0, mp5 = 1.2, sniper = 7, garand = 4, minigun = 2.4,
	heli = 3, jet = 4,
}
Config.PenetrationDamageKeep = 0.62 -- x the damage a bullet still does after going through a body part
Config.PenetrationMaxParts = 4 -- body parts one bullet can go through at most
-- (v2.0) tracers: a short glowing streak that flies at the bullet's speed (studs/s) instead of a line that blinks
Config.TracerSpeed = {
	default = 1100, pistol = 900, usp = 900, revolver = 1000, smg = 950, mp5 = 1000, rifle = 1500, minigun = 1400,
	sniper = 2600, garand = 1800, shotgun = 850, heli = 1400, jet = 1700,
}
Config.TracerLength = 9 -- studs, at most
-- taser
Config.RopeYankSpeed = 9 -- (v2.0) studs/s: a vehicle on a rope faster than this knocks down whoever is on the other end
Config.RopeYankDown = 2.2 -- s they stay down (again and again while it drags them)
Config.TaseTime = 9 -- s the one you hit lies there twitching (v2.0: longer)
Config.TaseDamage = 3
-- harpoon gun
Config.HarpoonDamage = 32
Config.HarpoonReelSpeed = 26 -- studs/s the line shortens while F is held
Config.HarpoonLineTime = 20 -- s the line holds at most
-- flare gun
Config.FlareSpeed = 140
Config.FlareBurnTime = 30
Config.FlareDamage = 14
-- lock-on launcher (Javelin style): hold G, keep a vehicle in the box until the lock turns green, F
Config.LockonRange = 950
Config.LockonCone = 7 -- deg around the crosshair
Config.LockonTime = 1.3 -- s to lock
Config.LockonFOV = 30 -- the seeker's zoom
Config.LockonTurnRate = 2.4 -- rad/s the missile can turn
Config.LockonSpeed = 150
Config.LockonMaxSpeed = 230
-- glue
Config.GlueCoats = 6 -- a tube is good for this many coats (two coats = one join)
Config.GlueRange = 12 -- studs from your body
Config.GluePullTime = 0.55 -- s the lighter thing flies onto the heavier one
Config.GlueBodyTime = 20 -- s glue holds a living person (then it gives)
Config.GlueBreakForce = 0 -- 0 = never breaks by force
-- prosthetics
Config.ProstheticTime = 7.5 -- s to fit one (yourself or somebody else)
Config.ProstheticRange = 6
Config.ProstheticArmStrength = 0.9 -- x strength with a prosthetic arm (muscle + melee)
Config.ProstheticLegSpeed = 0.9 -- x speed per prosthetic leg
-- fists (both hands empty: F punches) and weaving (Left Alt: slip to the side)
Config.FistDamage = 7
Config.FistDamagePerSpeed = 0.55
Config.FistKnock = 1.1
Config.FistTime = 0.32 -- s one punch
Config.FistCooldown = 0.38
Config.WeaveTime = 0.38 -- s the slip lasts (punches, kicks and swings miss you)
Config.WeaveCooldown = 0.7
Config.WeaveDash = 11 -- (v2.0) studs/s the slip throws you the way you press (only a bit)
Config.WeaveCounter = 1.6 -- x damage of a punch right after a slip
-- (v2.0) jet (the runway next to the sandbox)
Config.JetGunDamage = 1.1 -- x a pistol bullet (nose cannon, hold F)
Config.JetGunInterval = 0.06
Config.JetMinSpeed = 70 -- studs/s it needs to stay in the air (below that it sinks / stalls)
Config.JetMaxSpeed = 420
Config.JetThrust = 120 -- studs/s^2 at full throttle
Config.JetMissiles = 4 -- homing missiles (lock: keep a target in front of the nose)
Config.JetBombs = 6
Config.JetLockTime = 1.1
Config.JetLockRange = 1300
Config.JetLockCone = 12 -- deg around the nose
Config.JetHP = 260
Config.JetCrashMin = 55 -- velocity change (studs/s) that hurts the jet
Config.JetCrashDamage = 4
Config.JetBombRadius = 30
Config.JetBombDamage = 260
Config.JetBombPower = 170
Config.JetCameraExtra = 30 -- (v2.0: the jet is bigger) was 24
Config.ParachuteTime = 14 -- s the parachute holds after an ejection
Config.ParachuteFall = 16 -- studs/s you fall at most under it
-- (v2.0) admins and private servers
Config.FreeAdminInPrivate = true -- the owner of a private server gets all admin powers there (free)
Config.AdminPassId = 0 -- game pass id of the "Admin" pass (0 = no pass): its owners get the admin powers in private servers
Config.AdminPassOnlyPrivate = true -- the pass works in private servers only
Config.TimeStopMax = 25 -- s a time stop lasts at most
Config.HotdogCharge = 5 -- s the hotdog hovers and charges
Config.HotdogFlight = 18 -- s it flies round and round before it explodes
Config.HotdogRadius = 170 -- studs from the map centre (the sandbox; a loaded map uses its own size)
Config.HotdogHeight = 40
Config.SunCharge = 20 -- s the sun cannon charges
Config.SunExpand = 15 -- s the sun swells after the beam hits it, then: supernova
Config.SunBeamRadius = 7
Config.VoteKickNeed = 0.7 -- more than this share of yes (of the votes cast) kicks the player
Config.VoteKickCooldown = 90 -- s between two vote kicks someone can start
-- (v2.0) breaking buildings
Config.FractureRepairTime = 90 -- s after the last hit (and nobody close) a broken wall is whole again
Config.WallBulletsSoft = 7 -- bullet "power" on one spot of a plaster / wood wall that knocks a small hole
Config.WallBulletsHard = 14 -- the same for concrete / brick
Config.CarWallSpeed = 45 -- studs/s a car needs to crash through a wall
-- (v2.0) bleeding: a free hand presses on the wound by itself (x the bleeding while it does)
Config.WoundPressBleed = 0.45
-- flashlight
Config.FlashlightRange = 70
Config.FlashlightBrightness = 3.2
-- rocket launcher
Config.RocketSpeed = 170
Config.RocketRadius = 22
Config.RocketDamage = 210
Config.RocketPower = 155
-- blow darts
Config.SleepTimeMin = 10 -- s knocked out (screen black, no sound, no moving)
Config.SleepTimeMax = 20
Config.HealDartHP = 45 -- HP back on every body part
Config.HealDartBlood = 35
-- sniper: the shooter is kicked back too
Config.SniperSelfKick = 22
-- G = aim (hold): zoom, the gun arm points exactly at the crosshair, less spread, slower walk
Config.AimFOV = 46
Config.ScopeFOV = 11 -- sniper scope
Config.AimSensitivity = 0.55 -- mouse sensitivity while aiming (scope: x0.35 more)
Config.AimSpreadMult = 0.25 -- spread while aiming (sniper: 0 = dead on)
Config.AimWalkMult = 0.6
-- reloading by hand: the free hand has to touch the gun for the gun's reload time
Config.ReloadTouchDistance = 1.7 -- studs from the free hand to the gun / the hand holding it
Config.ReloadMagnetRadius = 5 -- the free hand snaps to the gun when you point within this distance of it
Config.ReloadForgive = 0.3 -- s the hand may slip off without losing the progress

-- shotgun: 8 pellets in a cone, 6 shells
Config.ShotgunShells = 6
Config.ShotgunFireInterval = 0.75
Config.ShotgunPellets = 8
Config.ShotgunSpread = 3.2 -- deg (cone half angle)
Config.ShotgunRange = 420
Config.PelletDamage = { Head = 62, Torso = 30, LeftArm = 32, RightArm = 32, LeftLeg = 32, RightLeg = 32 }
Config.ShotgunCloseRange = 18 -- studs: closer = more damage per pellet (up to x2.2 point blank)
Config.ShotgunGibRange = 14 -- studs: closer than this the pellets can blow a limb / the head off
Config.ShotgunSeverDamage = 70 -- pellet damage on one body part (one shot) that blows it off
Config.PelletPush = 11 -- per pellet
Config.ShotgunRecoil = 22

------------------------------------------------------------------------
-- Melee (held rigidly like the guns; F = attack)
------------------------------------------------------------------------
Config.MeleeAttackTime = 0.36
Config.SpearStabSpeed = 8 -- studs/s the tip must move into a body to stab
Config.SpearDamage = 20
Config.SpearDamagePerSpeed = 1.5
Config.SpearLunge = 15 -- studs/s forward lunge of the torso on a thrust
Config.SpearThrowSpeed = 150 -- release the spear while aiming (LMB/RMB) = javelin throw (aimed with gravity)
Config.SpearThrowRange = 220 -- studs: the throw is aimed to land on what you point at up to this far
Config.SpearThrowDamage = 55 -- + speed * SpearThrowDamagePerSpeed (x limb multiplier)
Config.SpearThrowDamagePerSpeed = 0.45
Config.BladeSlashSpeed = 11
Config.BladeDamage = 14
Config.BladeDamagePerSpeed = 1.15
Config.BladeSeverDamage = 46 -- one slash this strong cuts a limb off
Config.BladeDecapitateDamage = 62
Config.MeleeCooldown = 0.32 -- s before the same weapon can hurt the same body part again
Config.AxeDamageMult = 1.45
Config.AxeSeverDamage = 36
Config.BatSwingSpeed = 10
Config.BatDamage = 9
Config.BatDamagePerSpeed = 0.95
Config.BatKnock = 1.5 -- knockback per speed (x body part mass)
Config.RopeLength = 3 -- studs of slack when you tie someone to a wall
Config.RopeSearch = 9 -- studs around the body to find a wall / post
Config.BandageTime = 1.3 -- s the wrapping animation takes
Config.KatanaDamageMult = 1.25
Config.KatanaSeverDamage = 34 -- the katana cuts limbs off easily
Config.SledgeDamage = 22
Config.SledgeDamagePerSpeed = 1.6
Config.SledgeKnock = 2.6
-- kick (C): random leg
Config.KickTime = 0.42
Config.KickDamage = 9
Config.KickDamagePerSpeed = 0.7
Config.KickKnock = 1.9 -- knockback per speed (x body part mass)
Config.KickKnockdownSpeed = 14 -- foot speed that knocks somebody over
Config.KickPropImpulse = 30 -- studs/s given to loose things you kick (scaled down for heavy ones)
-- admin flight (B, game owner only; invincible while flying, infinite strength)
Config.FlySpeed = 45 -- studs/s to start with. While flying, N types a new speed: any number, or "inf"
Config.FlySprintMult = 2.5 -- Shift: this times your speed
Config.FlyMaxSpeed = 100000 -- "INF" (and anything above): the fastest the engine still handles (studs/s)
Config.FlyDirectSpeed = 250 -- faster than this the flight sets the body's speed directly (no giant forces on the joints)
Config.FlyGain = 4
Config.FlyAccel = 140 -- studs/s^2 at normal speeds (fast settings reach their speed in about 0.4 s)
Config.FlyLandSpeed = 60 -- landing (B) at a huge speed: you slow down to this first
Config.FlyCarryBreak = 30 -- in flight a carried thing (car, anvil) slips out only if it lags this far behind the hand
Config.FlyThrowBoost = 1 -- letting go of a carried thing while swinging the arm throws it

-- owner powers
Config.SuperPunchCooldown = 1.0 -- s between super punches (L)
Config.SuperPunchTime = 0.35 -- s the dash lasts
Config.SuperPunchSpeed = 150 -- studs/s you shoot forward
Config.SuperPunchDamage = 170 -- on the body part the fist hits (it can come off)
Config.SuperPunchKnock = 240 -- studs/s the one you hit flies away
Config.SuperPunchPropSpeed = 170 -- studs/s a prop / car you punch flies away
Config.LaserEyesRange = 700
Config.LaserEyesDPS = 1500 -- damage per second on the body part the beams burn (v1.9: 10x)
Config.LaserBrickTime = 0.2 -- s of laser until a brick / pane breaks
Config.CraterMinRadius = 8 -- (v2.0) blasts this big leave a crater in the ground ...
Config.CraterTime = 90 -- ... that heals after this many seconds
Config.CraterMax = 24 -- at most this many at once (the oldest goes first)
Config.LaserBlastEvery = 0.3 -- (v2.0) s between the blasts where the laser eyes burn
Config.LaserBlastRadius = 13 -- studs: whoever is this close is thrown away
Config.LaserBlastPower = 120 -- studs/s at the centre
Config.LaserBlastDamage = 30
-- day / night (the owner switches the cycle on / off in the menu, M)
Config.DayLength = 720 -- s for a whole day
Config.StartTime = 14 -- hour of the day the server starts at
-- water (the pool)
Config.SwimSpeed = 10
Config.SwimSprintSpeed = 15
Config.SwimUpSpeed = 9
Config.SinkSpeed = 1.6 -- doing nothing: you slowly go down
Config.SinkSpeedHelpless = 7 -- no legs or no arms: you go down fast
Config.SwimKp = 6
Config.SwimKi = 10
Config.DrownTime = 14 -- s with the head under water before it starts to hurt
Config.DrownDPS = 9 -- torso damage per second after that
Config.DrownDeathTime = 10 -- (for the darkening on screen: about how long until you die)

-- flash grenade
Config.FlashRadius = 45 -- studs: closer and looking at it = blinded longer
Config.FlashMaxBlind = 6 -- s of white screen at most
Config.FlashNPCStun = 5 -- s an NPC that saw it is blind at most

-- tether rope
Config.TetherRange = 45 -- studs you can reach with a click
Config.TetherMax = 6 -- ropes per player (the oldest goes)

-- two hands on an item (Y)
Config.TwoHandRecoil = 0.35 -- recoil / camera kick with both hands on the gun
Config.TwoHandSpread = 0.45 -- bullet spread with both hands on the gun

-- drop kick: C while in the air (jump, then C) - both feet first
-- (v2.0) nerfed: slower, shorter, less damage, less launch and a cooldown
Config.DropKickSpeed = 30 -- studs/s you fly forward (v1.9: 36)
Config.DropKickTime = 0.9 -- s at most in the air (then you tumble) (v1.9: 1.1)
Config.DropKickDamageMult = 1.35 -- (v1.9: 2.2)
Config.DropKickLaunch = 32 -- studs/s the one you hit flies away (v1.9: 55)
Config.DropKickKnockMult = 0.9 -- x the normal kick knock (v1.9: 1.5)
Config.DropKickCooldown = 2.5 -- s between two drop kicks
Config.DropKickLandRagdoll = 0.8 -- s you lie on your back after landing

------------------------------------------------------------------------
-- Grenade / explosions / destruction
------------------------------------------------------------------------
Config.GrenadeFuse = 3.2
Config.GrenadeThrowSpeed = 58
Config.GrenadeRadius = 26
Config.GrenadeDamage = 165
Config.GrenadePower = 115 -- studs/s pushed at the centre
Config.BarrelRadius = 20
Config.BarrelDamage = 190
Config.BarrelPower = 130
Config.ExplosionSeverDamage = 58 -- a blast hit this strong rips the limb off
Config.BarrelImpactSpeed = 55 -- sudden speed loss that sets a barrel off
Config.GrenadeImpactSpeed = 85 -- sudden speed loss that sets a grenade off (pin or not)
Config.C4Radius = 24
Config.C4Damage = 220
Config.C4Power = 145
Config.C4ThrowSpeed = 70
-- admin nuke
Config.NukeCountdown = 30
Config.NukeRadius = 300 -- lethal / damage radius of the blast
Config.NukeShockRadius = 1500 -- the shockwave still throws people this far (the whole map)
Config.NukeShockSpeed = 320 -- studs/s the shockwave travels
-- walls shield from blasts: what gets through = e^(-thickness * stop) (thickness in studs, times
-- the material: wood 0.6, concrete / brick 1.25, metal 1.4, glass 0.3)
Config.BlastWallStop = 0.75 -- grenades, C4, barrels, rockets: 1 stud of wall lets ~47% through
Config.NukeWallStop = 0.2 -- the nuke: 1 stud ~82%, a house (2 walls) ~67%, 10 studs of concrete ~8%
-- explosions use the engine's flame / smoke textures. For a flipbook explosion from the Creator
-- Store instead, add (texture id of the flipbook, its layout and speed):
-- Config.ExplosionFlipbook = { texture = "rbxassetid://0000000", layout = "Grid4x4", fps = 30 }
-- fire (molotov, flamethrower, burning barrels)
Config.MolotovRadius = 7 -- studs of burning fuel where the bottle breaks (+ 3 smaller patches)
Config.MolotovTime = 10 -- s it burns
Config.MolotovBreakSpeed = 40 -- dropped / hits something this fast: the bottle breaks
Config.BurnTime = 7 -- s a body burns after it caught fire (water puts it out, rolling on the ground helps)
Config.BurnDPS = 40 -- damage per second while burning (v1.9: much more)
Config.FireMaxZones = 60
Config.FireBarrelDelay = 2.5 -- s until an explosive barrel in a fire goes off
Config.BarrelFireRadius = 6 -- a blown-up barrel leaves burning fuel
Config.BarrelFireTime = 6
Config.FlameRange = 20 -- flamethrower reach (studs)
Config.FlameAngle = 13 -- deg half-angle of the flame cone
Config.FlameDPS = 140
Config.FlameFuel = 100
Config.FlameFuelUse = 11 -- per second of fire
Config.FlameFuelRegen = 7 -- per second while not firing
-- new melee
Config.KnifeDamageMult = 0.75 -- x spear stab damage (a knife is quick and throwable)
Config.MacheteDamageMult = 1.15 -- x blade damage
Config.MinigunSpinUp = 0.45 -- s the barrels spin before the first shot
Config.CrossbowBoltLife = 30 -- s a bolt stays stuck where it hit
Config.DestructionRepairTime = 50 -- s after the last hit until broken walls rebuild

------------------------------------------------------------------------
-- Bandage
------------------------------------------------------------------------
Config.BandageHeal = 25 -- HP back on the worst limb (broken bones stay broken)
Config.BandageBlood = 12

------------------------------------------------------------------------
-- Cars (raycast suspension, the driver's client simulates the car)
------------------------------------------------------------------------
Config.CarHP = 260 -- hidden; smoke below 40 %, fire below 18 %, then it blows up
Config.CarAccel = 34 -- studs/s^2
Config.CarMaxSpeed = 95
Config.CarReverseSpeed = 30
Config.CarBrake = 70
Config.CarMaxSteer = 32 -- deg
Config.CarGrip = 1.25 -- tire friction coefficient
Config.CarSuspensionRest = 1.15
Config.CarWheelRadius = 1.3
Config.CarPoppedDiameter = 1.9 -- a popped tire is this big (studs)
Config.CarPoppedDrop = 0.35 -- the car sits this much lower on a popped tire
Config.CarPoppedGrip = 0.55 -- grip of a popped tire
Config.CarSag = 0.42 -- static suspension compression
Config.CarDamping = 0.55
Config.CarEnterDistance = 10
Config.CarCrashMin = 28 -- velocity change (studs/s) of the car that damages it
Config.CarCrashDamage = 2.2
-- helicopter (spawn menu -> CARS): pilot + 3 passengers
Config.HeliHP = 300
Config.HeliClimbSpeed = 34 -- studs/s up / down (Space / Ctrl)
Config.HeliTilt = 24 -- deg it tilts forward / back (W / S) and sideways (Q / E)
Config.HeliYawRate = 1.5 -- rad/s turning (A / D)
Config.HeliDrag = 0.8 -- the higher, the lower its top speed
Config.HeliSpinUp = 1.6 -- s until the rotor lifts
Config.HeliGunInterval = 0.09 -- nose gun (hold F)
Config.HeliGunDamage = 0.7 -- x a pistol bullet
Config.HeliGunRange = 900
Config.HeliRocketCooldown = 1.2 -- C: a rocket from the pods
Config.HeliRotorRadius = 12.5
Config.HeliRotorDamage = 95
Config.HeliCameraExtra = 18
Config.CarCrashHurt = 0.6 -- damage to the people inside per stud/s above (CarCrashMin + 25)
Config.CarBulletDamage = 9
Config.CarSmashSpeed = 22 -- studs/s: drive through breakable walls
Config.MaxCarsPerPlayer = 2
Config.CarCameraExtra = 9
Config.RunOverMinSpeed = 9 -- studs/s: slower than this a car only pushes people
Config.RunOverDamage = 2.6 -- damage per stud/s above that
Config.RunOverSeverDamage = 120

------------------------------------------------------------------------
-- Wrecking ball crane
------------------------------------------------------------------------
Config.WreckingSwing = 42 -- deg amplitude the crane keeps the ball swinging at
Config.WreckingLaunch = 1.3 -- people hit fly off at this times the ball speed (about 85 studs/s)

------------------------------------------------------------------------
-- Kills (Tab leaderboard, saved)
------------------------------------------------------------------------
Config.KillCreditTime = 12 -- s: whoever hurt a body last within this time gets the kill
Config.KillStoreName = "RagdollSandbox_Kills_v1"

------------------------------------------------------------------------
-- Sandbox
------------------------------------------------------------------------
Config.MaxPropsPerPlayer = 40
Config.MaxDummies = 6
Config.PropSpawnCooldown = 0.2
Config.MarkerRestock = 20 -- s: armory items that were taken away come back
Config.MarkerMaxCopies = 3 -- at most this many of one armory item lying around
Config.DiveSpeed = 22 -- X in the air: leap forward and land on your belly
Config.DragKnockdown = true -- a player you grab goes limp (so you can drag them)
Config.DragForce = 4 -- x the dragged body weight pulling it to your hand
-- dragging a PLAYER: their own client pulls their body to your hand (nothing changes hands)
Config.DragPullForce = 16 -- x the dragged player's weight (v1.9.1: was 7, players felt too heavy)
Config.DragMaxSpeed = 130 -- studs/s the dragged body may move towards the hand
Config.DragResponsiveness = 60
Config.DragLeadMax = 0.25 -- s the dragged body aims ahead of the hand (hides the network delay)
Config.SpawnProtection = 2 -- (v2.0) s after spawning in which nothing can hurt you
Config.DragOwnerMode = false -- (an earlier v2.0 build; off now) the dragger's machine simulated the grabbed player's body. Roblox
-- keeps a player's own character with that player, so on the victim's screen the body froze where it was grabbed.
Config.DragPuppets = true -- (v2.0) the dragged body stays its player's (their client pulls it to the hand); every other
-- screen hides it and shows a local limp copy hanging right from the dragger's hand (no lag, no stretch, no magnet)
Config.DragLead = 0.6 -- x the network delay the dragged body aims ahead of the hand on its own client
Config.DragThrowMax = 70 -- (v2.0) studs/s: the fastest you can throw a player you let go of with a swing
Config.DragFriction = 0.12 -- (v2.0) friction of a dragged player's body parts (it slides instead of scraping)
Config.DragBreakDistance = 16 -- studs: further than this from your hand for a while = it slips
Config.PhysgunRange = 500
Config.TeleportCooldown = 2
Config.LaserRange = 900
-- virus (owner only): spreads between bodies close to each other, by sneezing, vomit and blood
Config.VirusCloudTime = 8 -- s the cloud from a smashed bottle stays
Config.VirusCloudRadius = 13
Config.VirusIncubation = 6 -- s before the symptoms start
Config.VirusSpreadRadius = 7 -- studs: being this close to a sick body can infect you
Config.VirusSpreadChance = 0.18 -- per second while that close
Config.VirusBloodChance = 0.35 -- per second standing in the blood / vomit of a sick body
Config.VirusSymptomGap = { 5, 11 } -- s between symptoms
Config.VirusDPS = 0.7 -- torso damage per second while sick (a heal dart cures it)
Config.VirusDuration = 150 -- s until the body beats it (if it is still alive)
-- hostile NPCs
Config.NPCMax = 8
Config.NPCMaxPerPlayer = 4
Config.NPCWalkSpeed = 12
Config.NPCRunSpeed = 17
Config.NPCSightRange = 260
Config.NPCShootRange = { 18, 90 } -- gunmen like to stay between these distances
Config.NPCAccuracy = 3.2 -- deg spread of NPC shots (+ more while moving)
Config.NPCReaction = 0.45 -- s before the first shot after seeing you
Config.NPCMeleeReach = 4.2
Config.NPCMeleeDamage = 24
Config.NPCGetUpTime = 1.6
Config.NPCCoverSearch = 30 -- studs around the NPC it looks for cover
Config.NPCSprintSpeed = 24 -- to cover, to a weapon, running away, far from you
Config.NPCWeaponSearch = 80 -- studs an unarmed NPC looks around for a weapon to pick up
Config.NPCFleeHP = 150 -- (of 600) this hurt, it runs away
Config.NPCReloadMult = 1.3 -- reload time x the gun's (both hands)
Config.NPCOneHandReload = 2.6 -- reload time x the gun's with only one working arm
Config.NPCLeapRange = 13 -- brawlers leap at you from this close
Config.BoxerReach = 3.6 -- (v2.0) the boxer: studs it punches from
Config.BoxerPunchEvery = 0.55 -- s between punches
Config.BoxerPunchDamage = 11 -- a jab (x the body part)
Config.BoxerHeavyDamage = 26 -- the haymaker (and it knocks you down)
Config.NPCLeapSpeed = 40
Config.NPCLeapDamage = 30
Config.NPCLeapKnock = 45
Config.NPCCrawlLeapGap = 1.8 -- s between the lunges of a crawling NPC
Config.NPCCrawlLeapSpeed = 20
Config.BoomboxMaxVolume = 1.2
Config.BoomboxRange = 160

------------------------------------------------------------------------
-- Game modes (v1.8; the owner starts them from the menu, M)
------------------------------------------------------------------------
Config.ModeRoundTime = 300 -- s a team fight / FFA round lasts at most
Config.HideTime = 30 -- s the hiders get before the seeker comes in
Config.HideSeekTime = 240 -- s the seeker has to find everybody
Config.ModeIntermission = 8 -- s between two rounds
Config.ModeGiveDelay = 0.6 -- s after the spawn the gun appears in the hand
-- the random guns (team fight, FFA, the seeker)
Config.ModeGuns = { "pistol", "revolver", "shotgun", "rifle", "smg", "sniper", "crossbow", "usp", "mp5", "garand" }
-- what lies around the city in hide and seek (close range only)
Config.HideWeapons = { "knife", "machete", "bat", "axe", "katana", "sledge", "blade" }
Config.SettingsStoreName = "RagdollSandboxSettings_v1"

------------------------------------------------------------------------
-- Camera
------------------------------------------------------------------------
Config.CameraDistance = 11
Config.CameraMinDistance = 4
Config.CameraMaxDistance = 32
Config.CameraShoulderOffset = Vector3.new(1.7, 0.6, 0)
Config.MouseSensitivity = 0.0042
Config.TouchSensitivity = 0.0065
Config.CameraFOV = 72
Config.FirstPersonFOV = 80

------------------------------------------------------------------------
-- v1.9
------------------------------------------------------------------------
-- sliding (sprint + Ctrl)
Config.SlideTime = 2.1 -- s (v2.0: was 0.95)
Config.SlideMaxSpeed = 70 -- studs/s the slide starts at, at most
Config.SlideEndSpeed = 14
Config.SlideCooldown = 0.6
Config.SlideHeight = 1.35 -- (v2.0) torso height while sliding (low, leaned back)
Config.SlideLean = 52 -- degrees the body leans back
-- (v2.0) the slide tackle: slide into somebody's legs and they are swept off their feet
Config.SlideTackleMinSpeed = 14 -- studs/s the slide must still have
Config.SlideTackleRadius = 1.9
Config.SlideTackleDamage = 6
Config.SlideTripTime = 2.0 -- s they lie there
Config.SlideTackleSweep = 1.1 -- how hard their feet fly out (x slide speed x leg mass)

Config.BoomboxHP = 70 -- (v1.9.1) a boombox breaks: bullets, blasts and hard knocks
Config.TwoHandPull = true -- (v2.0) the supporting hand is held on the item by a spring between hand and item
-- (equal and opposite: it can never drag, lift or pin the body). false = the hand is only aimed at the item
Config.TwoHandSpring = 3 -- x the arm's weight: how hard hand and item are pulled together
Config.Lite = false -- (v1.9.1 test build: true switched weather, experimental lighting, spectating, the piano and sliding
-- off. v2.0: everything is back on.)

Config.SuperPunchSafeTime = 1.0 -- s after a super punch (not flying) in which nothing can hurt or cut you
Config.LaserGroundTick = 0.12 -- s between the fires the laser eyes light on the ground (was 0.4)
Config.LaserGroundRadius = 3.6
Config.LaserGroundTime = 5
Config.CharTime = 4 -- s of burning until a body part is coal black
Config.CharColor = Color3.fromRGB(16, 14, 13)

-- helicopter
Config.HeliMissiles = 3 -- rockets in the pods, no reload
Config.HeliSpinDown = 16 -- s the rotor needs to coast to a stop once nobody flies it
Config.HeliCrashMin = 14 -- velocity change (studs/s) that hurts the helicopter
Config.HeliCrashDamage = 6.5 -- x the excess (it blows up much more easily than a car)
Config.HeliBladeCount = 3
Config.HeliBladeSpeed = 26 -- rad/s the rotor turns at full speed (looks)
Config.HeliBladeStrikeCooldown = 0.35
Config.HeliBladeFlySpeed = 20 -- a loose blade hurts above this speed
Config.HeliBladeDamage = 70

-- leaving a moving vehicle
Config.RunawayMinSpeed = 9 -- studs/s: faster than this and the car / helicopter keeps going without you
Config.RunawayTime = 7 -- s a car keeps its last throttle
Config.RunawayHeliTime = 9
Config.BailRagdoll = 2.8 -- s you tumble after jumping out of something fast
Config.BailKick = 7 -- studs/s sideways

------------------------------------------------------------------------
-- v2.0: steel balls, the Steel Ball Master's questline and the Spin
------------------------------------------------------------------------
Config.SteelBallSpeed = 175 -- studs/s: thrown hard and almost straight (v2.0: faster)
Config.SteelBallGravity = 0.06 -- x gravity while it flies (it barely drops)
Config.SteelBallRange = 320 -- studs; then it falls (or, with the Spin, comes back)
Config.SteelBallDamage = 40 -- x Config.LimbMultiplier (v2.0: way more: about 3 hits to the torso)
Config.SteelBallHeadKill = true -- (v2.0) a ball to the head kills on the spot
Config.SteelBallLaunch = 46 -- (v2.0) studs/s the whole body is thrown back by a hit (and knocked down)
Config.SteelBallDownTime = 1.4 -- s on the ground after a hit
Config.SteelBallKnock = 70 -- push on the part it hits (x that part's mass) (v2.0: way more)
Config.SteelBallCooldown = 0.35 -- s between throws
Config.SteelBallWindup = 0.08 -- s the arm winds up before the ball leaves the hand
Config.SteelBallKillWindow = 4 -- s: a kill counts as a steel ball kill when your ball hit them this recently
-- with the Spin: green balls, a yellow trail, the one hit spins in the air, the ball comes back to your hand in an arc
Config.SpinBallDamage = 55
Config.SpinVictimTime = 2.2 -- s the one hit spins (ragdolled)
Config.SpinVictimSpeed = 24 -- rad/s
Config.SpinVictimLift = 2.5 -- studs they float up while they spin
Config.SpinBallReturnSpeed = 110 -- studs/s on the way back
Config.SpinBallColor = Color3.fromRGB(70, 230, 100)
Config.SpinTrailColor = Color3.fromRGB(255, 220, 40)
-- the questline (the Steel Ball Master behind the red brick house)
Config.GiftStoreName = "RagdollGifts_v1" -- (v2.0) gifted powers / admin stay with the player (until taken back)
Config.QuestStoreName = "RagdollQuests_v1" -- DataStore: the stage and the Spin are kept between visits
Config.ProfileStoreName = "RagdollProfile_v1" -- (v2.0) DataStore: redeemed codes, skins, titles, play time (RewardService)
Config.QuestKills = 5 -- quest 1: steel ball kills (players and bots) without dying
Config.QuestThrows = 20 -- quest 2: throw a ball and pick it up again, this many times in one life
Config.QuestTalkRange = 14 -- studs from the master to talk
Config.RelicTouchRadius = 5 -- quest 3: this close to the Spin in the construction site
Config.CutsceneTime = 6.5 -- s

-- (v2.0) the master: her name and EVERYTHING she says can be changed here.
-- In the texts {kills}, {throws} and {prog} are filled in by the game; "\n" starts a new paragraph.
Config.SpinMasterName = "GYRO-SAN" -- the name over her dialog box
Config.SpinMasterTitle = "Gyro-San" -- what the game calls her (prompt, quest notes)
Config.SpinMasterDialog = {
	-- before you touched a Spin Circle she does not talk to you: this is all you get (a speech bubble)
	noSpin = {
		"Hmph. You don't have it in you. The Spin. I can see it.",
		"Go away. I only talk to people the Spin has touched.",
		"...No. Not you. Not yet. Find a Spin Circle first - IF you can.",
	},
	-- stage 0: she offers quest 1
	[0] = {
		text = "W-what? The Spin found YOU? ...Hmph. Fine, I can see it in your eyes.\n"
			.. "These are steel balls. Thrown right, they fly straight and never tire. Thrown with the SPIN... they come back to you.\n"
			.. "Not that I'd teach that to someone like YOU. Unless you prove you're not completely useless: take down {kills} fighters with steel balls (players or bots) - and don't you DARE die while doing it.\n"
			.. "There are balls on my table, on the weapon tables and in the spawn menu. D-don't get the wrong idea. I just don't want them lying around.",
		accept = "I'll do it",
		close = "Not now",
	},
	[1] = { text = "{prog} of {kills}. Steel balls only. And no dying, idiot - die and you start from zero. ...I'm not worried. Obviously.", close = "Hmph" },
	[2] = {
		text = "...You actually did it? Hmph. Beginner's luck.\n"
			.. "Next: throw a ball and pick it up again, {throws} times, all in one life. A ball you leave lying around is a ball you lose - and I am NOT buying you new ones!",
		accept = "Understood",
		close = "Later",
	},
	[3] = { text = "{prog} of {throws} throws picked up again. In one life - die and we count again. I-I'm not watching you or anything.", close = "OK" },
	[4] = {
		text = "Throw, fetch, throw, fetch... and you never got tired. F-fine. You're... not terrible.\n"
			.. "Somewhere in the CONSTRUCTION SITE lies what my family calls the SPIN. Find it, touch it, then come back to me.\n"
			.. "Listen for it: it hums, louder the closer you get. And don't fall off anything. It would be embarrassing. For YOU.",
		accept = "I'll find it",
		close = "Later",
	},
	[5] = { text = "The Spin is in the construction site. Up high, maybe. Follow the hum. ...W-why are you still standing here?!", close = "Going" },
	[6] = {
		text = "You touched it. Your eyes are still spinning, it's kind of... n-never mind!\n"
			.. "Hold out your hands. From now on your steel balls spin: they turn green, they leave a golden trail, whoever they hit spins with them... and they always come back to you.\n"
			.. "Like you always come back here. N-not that I wanted you to!",
		accept = "Take the SPIN",
		close = "Wait",
	},
	[7] = { text = "The Spin is yours. Throw - and let it come back. Whoever it hits spins. ...Use it well. And visit sometimes. B-because the camp needs sweeping, that's all!", close = "Bye" },
}
-- what she mutters in speech bubbles
Config.SpinMasterQuips = {
	first = { "W-what are you staring at?", "This camp is private property! ...Mostly.", "Hmph. Another tourist." },
	busy = { "Shouldn't you be busy? Go!", "I-I wasn't waiting for you!", "Done already? ...No? Then why are you here?!" },
	back = { "You're back. Not that I noticed.", "Took you long enough. ...I mean, whatever.", "Hmph. Fine, talk to me. If you must." },
	done = { "Oh. It's you. ...Hi.", "Still spinning? Good. Not that I care.", "Don't make that face. I'm just sweeping the camp." },
	accept = { "D-don't get the wrong idea!", "It's not like I believe in you or anything!", "Hmph. Try not to embarrass me." },
	learned = { "D-don't thank me! Just... use it well." },
}
-- (v2.0) the Spin Circle: she only talks to whoever touched one. Every SpinCircleEvery seconds there is a
-- 1 in SpinCircleOdds chance that one appears somewhere near the players - a notification, no marker. The first
-- player who has not had it yet and steps in gets it (and it is gone).
Config.SpinCircleEvery = 60 -- s
Config.SpinCircleOdds = 50 -- 1 in this many
Config.SpinCircleLifetime = 300 -- s until it fades if nobody finds it
Config.SpinCircleRadius = 3.5 -- studs: step this close
Config.SpinCircleMinDist = 60 -- studs from the player it is placed near
Config.SpinCircleMaxDist = 260

------------------------------------------------------------------------
-- v2.0: the new maps and their creatures, the new game modes
------------------------------------------------------------------------
-- the Crawler (horror map / MONSTER mode)
Config.CrawlerHP = 2200 -- the one that roams the asylum (and the megastore)
Config.CrawlerSpeed = 20 -- studs/s chasing (you run 21)
Config.CrawlerReach = 5.2 -- studs: it grabs you (v2.0: it is bigger)
Config.CrawlerPounceRange = 50 -- (v2.0: it leaps much further)
Config.CrawlerAggroTime = 14 -- s it stays after whoever hurt it last (it finds them behind walls too)
Config.CrawlerForget = 6 -- s out of sight before it gives up on somebody (unless it is angry at them)
Config.CrawlerHear = 14 -- studs: this close it notices you without seeing you
Config.CrawlerDigAfter = 1.6 -- s without a way to them before it digs through the wall / ceiling (v2.0: much sooner)
Config.CrawlerDigMaxThick = 6 -- studs: walls / floors up to this thick it digs through
Config.CrawlerHuntAfter = 15 -- s without anybody in sight: it picks somebody on the map and hunts them down
Config.CrawlerHuntTime = 30 -- s it keeps after that one (through walls)
Config.CrawlerUnstuckAfter = 7 -- s without getting anywhere: it slips out somewhere else along its way
Config.CrawlerDigTime = 1.6 -- s of clawing for a hole
Config.CrawlerDigRadius = 3.8 -- studs: the hole it makes
Config.CrawlerPounceCooldown = 4.5
Config.CrawlerSense = 140 -- studs it notices you from
Config.CrawlerEatTime = 2.2 -- s from the grab to letting your body fall (the head goes at 65 %)
Config.CrawlerRespawn = 60 -- s after the roaming one died
Config.CreatureBlastDamage = 260 -- an explosion right on a creature
-- sharks (sea map)
Config.SharkCount = 5
Config.SharkHP = 320
Config.SharkSpeed = 30 -- studs/s hunting (you swim 10) (v2.0: faster)
Config.SharkReach = 5
Config.SharkSense = 110
Config.SharkBiteCooldown = 2.2 -- s between bites (v2.0: much less)
Config.SharkFleeTime = 1.4 -- s it swims off after a bite before it turns back
Config.SharkLungeRange = 16 -- studs: from here it lunges
Config.SharkLunge = 1.7 -- x speed in the lunge
-- islands that come up when you fall into the sea
Config.IslandMin = 9 -- radius (studs)
Config.IslandMax = 30
Config.IslandMaxCount = 10
Config.IslandCooldown = 20 -- s per body
Config.IslandLootChance = 0.45
Config.IslandLoot = { "pistol", "knife", "steelball", "harpoon", "flaregun", "bandage", "machete" }
-- game modes
Config.MonsterHP = 3200 -- MONSTER mode: the Crawler's health ...
Config.MonsterHPPerPlayer = 650 -- ... plus this for every fighter
Config.MonsterRoundTime = 240 -- s: survive this long (or kill it) and the fighters win
Config.ZombieRoundTime = 300 -- s: humans alive at the end win
Config.ZombieStart = 0.25 -- share of the players who start as zombies (at least 1)
Config.ZombieBiteTime = 20 -- s after a bite until you turn (a heal dart cures you)
Config.ZombieBiteDamage = 30 -- (v2.0: a bite really hurts now)
Config.ZombieBiteEvery = 0.75 -- s between a zombie bot's bites
Config.ZombieBotSpeed = 1.12 -- x a bot's run speed
Config.ZombieLeapRange = 30 -- studs: a zombie bot leaps at you from this far
Config.ZombieLeapSpeed = 78 -- studs/s at most in that leap
Config.ZombieLeapForward = 58 -- a zombie player's jump while running: studs/s forward ...
Config.ZombieLeapUp = 1.25 -- ... x the normal jump up
Config.ZombieLeapTime = 0.9 -- s in which it bites what it flies into
Config.ZombieExtraBots = 4 -- zombie bots that start every ZOMBIES round on top of everybody else
Config.ZombieKnockdown = false -- zombies are not knocked over (they only go down when both legs are gone)
Config.ZombieSpeed = 1.12 -- x walking / running speed
Config.ZombieColor = Color3.fromRGB(112, 150, 86)
Config.GunGameLadder = { "pistol", "usp", "revolver", "smg", "mp5", "shotgun", "rifle", "garand", "sniper", "crossbow", "minigun", "knife" }
Config.GunGamePool = { -- (v2.0) what the random ladder is drawn from (the knife always ends it)
	"pistol", "usp", "revolver", "smg", "mp5", "shotgun", "rifle", "garand", "sniper", "crossbow", "minigun",
	"launcher", "lockon", "sleepdart", "harpoon", "flaregun", "katana", "axe", "chainsaw", "sledge", "spear", "machete", "steelball",
}
Config.GunGameSteps = 12 -- weapons on the ladder (the last one: the knife)
Config.GunGameRoundTime = 360
Config.ModeRespawnTime = 3 -- s (gun game, zombies)
Config.ModeBotFill = 8 -- bots fill a round up to this many fighters (owner menu: BOTS)
Config.ChainsawDamageMult = 1.35 -- (v2.0) x blade damage; it cuts limbs off like a katana
Config.ChainsawTick = 0.14 -- s between the bites of a running chain (F starts / stops the motor)
Config.ChainsawTickDamage = 7 -- per bite (x the body part's multiplier); a limb comes off when its health is spent
Config.MapVoteTime = 14 -- s between rounds: everybody votes for the next map
-- (v2.0) SNIPER TOWER: one sniper on a tower, everybody else runs at it from far away (no guns, only blades and fists)
Config.SniperRoundTime = 300 -- s: the sniper wins when it runs out
Config.SniperRangeMult = 3 -- x the sniper's range (and its bullets keep their power that far)
Config.SniperRunnerRespawn = 5 -- s until a runner (a bot; players: Config.RespawnTime) who died starts again at the far end
Config.SniperRunnerWeapons = { "knife", "machete", "bat", "axe", "katana", "sledge" }
Config.SniperTowerMaps = { "valley", "sky" } -- maps with a tower (the mode loads the first if the map has none)
-- (v2.0) HOT POTATO: a bomb that goes to whoever the holder touches; when the fuse runs out the holder is out
Config.PotatoFuse = { 16, 26 } -- s (a random fuse for every new bomb)
Config.PotatoTagRange = 4.6 -- studs between two bodies to pass it on
Config.PotatoPassLock = 0.7 -- s after a pass before it can go on again
Config.PotatoNoPassBack = 2 -- s the new holder cannot hand it straight back
Config.PotatoNextBomb = 3 -- s after a bomb went off until the next one comes
Config.PotatoRoundTime = 360
-- (v2.0) KING OF THE HILL: stand in the ring alone to score; more than one inside: nobody scores
Config.HillRadius = 13 -- studs
Config.HillTarget = 60 -- points (1 per second alone in the ring) to win
Config.HillMoveTime = 50 -- s until the ring moves somewhere else
Config.HillRoundTime = 360
-- (v2.0) the sky islands: below this height you have fallen into the void
-- (v2.8.1) THE PIT lies deep under the ritual circle: nobody sees it from the sandbox. Everything that kills / removes what
-- falls too low (the void) leaves this box alone.
Config.PitCenter = Vector3.new(-300, -1500, -40)
Config.PitHalf = 235
function Config.InPit(pos: Vector3): boolean
	local d = pos - Config.PitCenter
	return math.abs(d.X) < Config.PitHalf and math.abs(d.Z) < Config.PitHalf and d.Y > -170 and d.Y < 270
end
Config.SkyVoidY = -60
-- (v2.0) scopes: the mouse wheel zooms in further while you look through one
Config.ScopeZoom = { 1, 2, 3.5, 6 } -- x (the sniper mode's sniper gets one more step)
Config.ScopeZoomSniperMode = 10
-- (v2.0) BOT CARS (owner menu): bots drive cars round the city (BotDriverService)
Config.BotCarMax = 4 -- cars at once
Config.BotCarCruise = 40 -- studs/s on a straight
Config.BotCarTurnSpeed = 16 -- studs/s round a corner
Config.BotCarLane = 4.2 -- right of the centre line (the streets are 26 wide)
Config.BotCarTurnRadius = 15 -- the curve round a corner (a left turn: 1 less)
Config.BotCarStuckTime = 14 -- s stuck (all tries together) before the bot gives up and gets out

------------------------------------------------------------------------
-- (v2.1) money, weapon skins, the Black Ledger
------------------------------------------------------------------------
Config.KillCash = 10 -- dollars for every kill (a player or a bot / NPC; dummies pay nothing)
Config.RandomSkinCost = 200 -- dollars: a random skin
Config.RandomSkinRobux = 29 -- Robux: a random skin (developer product below)
Config.RandomSkinProductId = 3721585481 -- the developer product "random skin" (29 Robux)
Config.SkinRobux = 149 -- Robux: a specific skin (shown on the BUY button)
-- !! PUT YOUR DEVELOPER PRODUCT ID HERE: Creator Hub > this experience > Monetization > Developer Products > create a product
-- priced at 49 Robux, copy its ID. ONE product serves every skin: the game remembers which skin the player picked.
-- 0 = not set up yet: the BUY button tells the player so (in Roblox Studio it gives the skin for free, to test).
Config.SkinProductId = 3722211126 -- the developer product "pick a skin" (149 Robux)
Config.ProfileStoreV2 = "RagdollProfile_v2_1" -- DataStore: dollars, skins you own, equipped skins, ledger quest

-- the Black Ledger (notebook) and its shikigami Kuro
Config.LedgerName = "BLACK LEDGER"
Config.LedgerSpiritName = "Kuro"
Config.LedgerQuestKills = 100 -- kills with the ledger in ONE life ...
Config.LedgerQuestApples = 5 -- ... and this many apples fed to Kuro: the ledger is yours for good (you can spawn it)
Config.LedgerSpawnCooldown = 240 -- s between two uses of a spawned ledger
Config.LedgerWriteTime = 4 -- s the writing lasts before it happens

-- the Sandevistan (cyberware): an implant, put in by ANOTHER player
Config.SlowMoScale = 0.06 -- (v2.8) the speed of the world while the Sandevistan runs (0.06 = 6 %): everybody else, NPCs, rockets, bullets
Config.SlowMoCamera = 0.12 -- how fast a slowed player can still turn their camera (x normal)
Config.SandevistanImplantTime = 20 -- s the implant takes (the patient should be asleep: Sleep dart, or he is hurt a little)
Config.SandevistanDuration = 10 -- s of slowed world (double-tap Shift)
Config.SandevistanHot = 60 -- s after it ended in which the circuits are hot: using it again FRIES them
Config.SandevistanCycle = 300 -- s after the FIRST use until the implant is fresh again; used before that it hurts, the more the closer to the first use
Config.SlowBulletSpeed = 900 -- studs/s: a bullet at NORMAL speed (it is hitscan normally; in slow motion it flies at this x SlowMoScale)
Config.SlowGhostRate = 0.12 -- s between two afterimages (only while you move); they all stay until the Sandevistan ends
Config.ArmorEquipTime = 10 -- s to put the body armor on (the same bar as fitting a prosthetic)
Config.SandevistanSpeed = 2 -- your own walking speed while it runs

-- (v2.8) CYBERWARE (Shared/Cyberware, CyberService, RipperdocService, CyberModels, CyberClient)
Config.CyberTolerance = 20 -- the load of implants a body takes without cyberpsychosis
Config.CyberRemoveShare = 0.25 -- taking an implant out at the ripperdoc costs this share of its price
Config.CyberFitTime = 10 -- s a player needs to put an implant (from a case) into somebody / take one out (ripper kit)
Config.SurgeonShare = 0.3 -- a player who operates inside the ripperdoc or the hospital earns this share of the implant's price
Config.RipperDreamTime = 14 -- s the patient sleeps (and dreams) while the doc works
Config.RipperNpcScale = 1.12 -- (v2.8.2) the doc and the receptionist: as tall as the players
Config.RipperShowUpTime = 60 -- s to lie down on the bed once it is your turn (or the next one comes)
Config.RipperDocName = "DOC KESSLER"
Config.PsychoRate = 0.0035 -- psychosis per second for every point of load over the tolerance
Config.PsychoDecay = 0.01 -- per second while you are under the tolerance again
Config.CrashOutTime = 14 -- s you are not in control when you crash out
Config.CrashOutCooldown = 38 -- s at least between two crash outs
Config.AegisShield = { 30, 60, 100 }
Config.AegisDelay = { 7, 6, 4 } -- s without a hit before it recharges
Config.AegisRate = { 10, 15, 30 } -- shield per second
Config.CloakTime = { 6, 10, 15 }
Config.LodestoneRange = { 30, 60, 90 }
Config.HunterBonus = 1.25 -- tier 3: damage on your target
Config.StriderSpeed = { 1.12, 1.22, 1.32 }
Config.StriderJump = { 1.15, 1.3, 1.5 }
Config.StriderFall = { 0.7, 0.45, 0.2 } -- fall damage x
Config.TitanBonus = { 0.2, 0.35, 0.5 }
Config.BulkScale = { 1.12, 1.22, 1.35 }
Config.BulkArmor = { 0.87, 0.75, 0.65 } -- damage x
Config.BlastDamage = { 0.65, 0.45, 0.3 }
Config.BlastPush = { 0.7, 0.5, 0.35 }
Config.KeelKnock = { 0.75, 0.55, 0.33 } -- knocked-down time x
Config.DermisShock = { 10, 16, 24 } -- damage to who hurt you
Config.ColossusScale = 3
Config.ColossusBigBlast = 150 -- a blast throws a COLOSSUS over only from this push on (C4, the jet's bombs, the nuke)
Config.ZeroHourTime = 8 -- s ZERO HOUR freezes the server
Config.ShiftgunRate = { 0.22, 0.15, 0.09 } -- s between two shots
-- (v2.8.2) BEDROCK STABILIZER: how much of a hit's push is left (tier 1-3); nothing knocks you over
Config.AnchorPush = { 0.3, 0.15, 0.05 }
-- (v2.8.2) BASTION SHELL: how long the plates stay closed after a threat, what is left of a bullet that hits a plate
Config.BastionTime = { 6, 8, 10 }
Config.BastionCut = { 0.5, 0.3, 0.1 }
Config.ShiftgunDamage = { 0.8, 1.0, 1.25 } -- x a rifle bullet
Config.RegrowLimb = { 10, 16 } -- (v2.8.1) s: a broken bone knits / a limb grows back (REGROWTH CORE, TITAN arms)
Config.RegrowCore = { 10, 16 } -- (v2.8.1) s: REGROWTH tier 3 - a lost head / torso grows back while you lie there
Config.RegrowCoreCooldown = 120 -- (v2.8.1) s between two of those
Config.ShiftgunMag = { 12, 18, 30 } -- (v2.8.1) rounds in the arm, then it reloads itself
Config.ShiftgunReload = { 1.8, 1.4, 1.0 } -- (v2.8.1) s the reload takes
Config.HowlerDamage = { 60, 90, 130 }
Config.HowlerRadius = { 7, 9, 11 }
Config.PumpBleed = { 0.6, 0.4, 0.2 } -- (v2.8) IRONHEART PUMP: bleeding x
Config.PumpRegen = { 1.5, 3, 5 } -- HP/s more for every limb that is not broken ...
Config.PumpDelay = { 6, 5, 4 } -- ... once you were not hit for this long
Config.PumpClose = 6 -- tier 3: an open wound closes this long after the last hit
Config.LungsBreath = { 2, 4, 0 } -- DEEPWATER LUNGS: breath x (0 = you never drown)
Config.EchoRange = { 45, 75, 120 } -- ECHO EARS: radar range
Config.ParalysisTime = 40 -- s a paralysis dart keeps you down (awake: no dream)
Config.SyringeMult = 3 -- a syringe puts you to sleep this many times as long as a sleep dart
Config.SyringeRange = 6
Config.Cyber_NPCCannon = 5 -- s between two shells of a chromed merc
Config.BountyMin = 50 -- dollars: the smallest bounty you can put on somebody
Config.BountyMax = 100000
Config.BountyStreak = 5 -- kills in one life: a bounty on you by itself ...
Config.BountyStreakStart = 100 -- ... of this much ...
Config.BountyStreakStep = 50 -- ... and this much more for every kill after that
Config.TankReload = 3.5 -- s between two tank shells
Config.VanHoldTime = 180 -- s a captive player stays held in the back of a van (v2.8.2: they can not get out by themselves)
Config.SeverCooldown = 1.5 -- s between two SEVER slashes (admins / gifted)

-- (v2.8) THE STILLWATER QUEST (SwordQuestService, RivalService, StillCutService, SwordClient)
-- The ritual circle west of the spawn: light the 5 candles, lay a body on the altar - the ground opens (THE PIT).
--   quest 1  BLOOD FOR THE DOOR : kills with a blade (katana, blade, machete, knife, axe, spear, chainsaw)
--   quest 2  THE DESCENT        : jump into the hole, take the sheath from the bone altar down there, climb out alive
--   quest 3  THE PALE HEIR      : go down again and beat her (her SHADE ARMS, her blink step, her own still cut)
-- Then STILLWATER is yours for good: you spawn with it, sheathed at your hip. Draw it (hold Q with an empty left hand),
-- put it back into the SAME pocket (hold Q with it in the left hand): STILL CUT.
Config.RivalName = "VESPER CROWE"
Config.RivalTitle = "THE PALE HEIR"
Config.SwordName = "STILLWATER"
Config.SwordQ1Kills = 6 -- blade kills for quest 1 (players, NPCs and bots; a dummy does not count). They add up, dying does not reset them
Config.SwordCandleTime = 90 -- s a lit candle burns
Config.SwordHoleTime = 120 -- s the hole stays open
Config.SwordHollows = 3 -- HOLLOWS (the things down there) at a time; (v2.8.1) none while the Pale Heir is out
Config.SwordHollowEvery = 7 -- (v2.8.1) s between two new ones
Config.RivalHP = 1200 -- her health (the bar over the screen). Damage to him counts in full, his body only shows it
Config.RivalSeverBelow = 0.35 -- below this share of his health his limbs can come off
Config.RivalBulletCatch = 0.45 -- while the SHADE ARMS are out: the share of bullets they catch
Config.RivalSlam = 30 -- damage of a SHADE ARM slam (and it throws you)
Config.RivalSlash = 32 -- damage of the slash after his blink step
Config.RivalStillCut = 55 -- damage of HER still cut (inside its ring); get out of the ring
Config.RivalStillCutRadius = 16
Config.StillCutCooldown = 40 -- s between two STILL CUTs
Config.StillCutRadius = 42 -- studs round you
Config.StillCutFreeze = 2.6 -- s the world stands still while the cuts appear
Config.StillCutDamage = 55 -- per cut on a body (3 cuts each; a cut through a limb takes it off)
Config.StillCutProps = 8 -- loose things (crates, cars, props) it cuts in two at most
-- what he says (change it here; one line is shown at a time, in order)
Config.RivalLines = {
	ritual = { "Someone knocks.", "You want what I carry? Then come down and take it.", "Not yet. First show me you are more than meat. Bring me blood - on a blade." },
	q1done = { "Enough. I can smell it on you.", "The door knows you now. Knock at the altar and come down.", "Fetch the sheath from my bone altar. If the Hollows let you." },
	pit = { "Welcome to the Pit. Mind the floor - it bites." },
	sheath = { "That sheath has waited a long time.", "Now climb out. The pale light in the south. Alive, if you can." },
	q2done = { "You climbed out. Most do not.", "Come down again. This time I will be waiting." },
	intro = { "So you came.", "This blade does not cut flesh. It cuts the moment between two heartbeats.", "Watch closely. You will want to remember how it is done." },
	phase2 = { "Not bad. Then let us use more hands." },
	phase3 = { "Enough. Be still." },
	stillcut = { "Be still.", "Stop.", "Hold." },
	taunt = { "Too slow.", "Again.", "You hesitate.", "Behind you.", "Is that all?" },
	death = { "...So the blade has chosen.", "Sheathe it, and the world will wait for you." },
	win = { "She is gone. STILLWATER is yours." },
}

-- (v2.9) CHIPS, the video camera, the computer and the netrunner deck (ChipService, CameraService, ComputerService,
-- ChipClient). All of this is made up for the game - a cyberpunk sandbox, like the implants.
Config.ChipSlots = 4 -- the neck slots a body has for chips
Config.DodgeWindow = 6 -- s a REFLEX BUFFER stays armed once it triggers
Config.ScanRange = 260 -- studs the SCANNER marks things within
Config.ZoomFov = { 45, 32, 20 } -- the field of view the ZOOM OPTICS pull to, per tier (lower = closer)
Config.NetRange = 160 -- studs you can run a quickhack / the netrunner interface reaches
Config.VirusPrice = 250 -- a virus bought at the computer (programmed onto a blank chip)
Config.BlankPrice = 80 -- a blank chip at the computer
Config.VirusArmTime = 2.4 -- s after a trojan video ends before the payload fires
-- (v2.9) a local Sandevistan: the slow field only reaches this far round the one who runs it (0 = the old whole-world slow)
Config.SandevistanRadius = 70
-- (v2.9) the STILL CUT only freezes what is inside the ring (bodies around you), not the whole server
Config.StillCutLocal = true

return Config
