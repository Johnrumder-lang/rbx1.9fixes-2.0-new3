--!nonstrict
-- SoundLibrary: every sound effect, played on clients.
--
-- The ids come from the free Roblox Creator Store (mostly the official ProSoundEffects library,
-- which any experience may use). Each sound has fallbacks: if an id fails to load (moderated,
-- private, removed) the next one is used, ending with Roblox's built-in engine sounds.

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local SoundLibrary = {}

local function ids(...: any): { any }
	local out = {}
	for _, v in { ... } do
		if typeof(v) == "number" then
			table.insert(out, "rbxassetid://" .. tostring(v))
		else
			table.insert(out, v) -- (a string, or an alt(): a candidate with its own pitch / effects)
		end
	end
	return out
end

-- (v2.0) a candidate with its own pitch factor and effect chain: the shaped stand-in after a real sample
local function alt(id: number | string, pitchMul: number?, chain: { any }?): any
	return { id = typeof(id) == "number" and ("rbxassetid://" .. tostring(id)) or id, pm = pitchMul or 1, fx = chain }
end

-- (v2.0) effect chains (Roblox SoundEffects on the Sound), applied in this order:
--   { "dist", level } { "trem", hz, depth, duty } { "flange", rate, depth, mix } { "chorus", rate, depth, mix }
--   { "eq", low, mid, high } { "echo", delay, feedback, wet } { "reverb", decay, wet } { "octave", x }
local B = "rbxasset://sounds/" -- (Roblox's built-in sounds: they always load)

-- name -> { variants = { {candidates...}, ... }, volume, pitch = {min, max}, range }
SoundLibrary.Defs = {
	gunshot = { variants = { ids(800000246, "rbxasset://sounds/Rocket shot.wav") }, volume = 0.9, pitch = { 0.95, 1.05 }, range = 400 },
	dryfire = { variants = { ids(484110242, "rbxasset://sounds/clickfast.wav") }, volume = 0.6, pitch = { 0.95, 1.05 }, range = 40 },
	casing = { variants = { ids(9113631067) }, volume = 0.25, pitch = { 1.1, 1.3 }, range = 30 },
	ricochet = { variants = { ids(7842386350) }, volume = 0.5, pitch = { 0.9, 1.15 }, range = 150 },
	bulletWorld = { variants = { ids(131554175554758, "rbxasset://sounds/collide.wav") }, volume = 0.6, pitch = { 0.9, 1.1 }, range = 120 },
	bulletFlesh = { variants = { ids(9114487369), ids(9114486901) }, volume = 0.8, pitch = { 0.9, 1.1 }, range = 90 },
	boneCrack = {
		variants = { ids(9119559518), ids(9113542363), ids(9119559825) },
		volume = 0.9,
		pitch = { 0.9, 1.1 },
		range = 120,
	},
	gore = { variants = { ids(330595293, "rbxasset://sounds/splat.wav"), ids(8164951181, "rbxasset://sounds/splat.wav") }, volume = 0.8, pitch = { 0.9, 1.1 }, range = 110 },
	stab = { variants = { ids(9114486901), ids(9114487171), ids(9114487369) }, volume = 0.9, pitch = { 0.9, 1.05 }, range = 100 },
	thud = {
		variants = { ids(9113480917, "rbxasset://sounds/action_jump_land.mp3"), ids(9113480915, "rbxasset://sounds/action_jump_land.mp3") },
		volume = 0.7,
		pitch = { 0.9, 1.1 },
		range = 90,
	},
	-- getting hit
	bodyHit = {
		variants = { ids(96268858305059, 9113525643, "rbxasset://sounds/action_jump_land.mp3"), ids(9113525643, 96268858305059, "rbxasset://sounds/action_jump_land.mp3") },
		volume = 0.85,
		pitch = { 0.92, 1.08 },
		range = 110,
	},
	-- (v1.9) weather loops. I could not verify any rain asset id offline, so these use a built-in noise sample as
	-- a stand-in (deep and slow = wind, a bit higher = rain). Put real rain / wind asset ids in front of the
	-- built-in one (e.g. ids(1234567, "rbxasset://sounds/Rocket flight.wav")) and they are used instead.
	rainLoop = { variants = { ids("rbxasset://sounds/action_falling.mp3") }, volume = 0.5, pitch = { 1.3, 1.3 }, range = 0 },
	windLoop = { variants = { ids("rbxasset://sounds/action_falling.mp3") }, volume = 0.4, pitch = { 0.6, 0.6 }, range = 0 },
	heavyHit = { variants = { ids(9120270688, "rbxasset://sounds/action_jump_land.mp3") }, volume = 0.9, pitch = { 0.9, 1.05 }, range = 160 },
	-- fists
	punch = {
		variants = {
			ids(133317945673668, 138382448405483, "rbxasset://sounds/swordslash.wav"),
			ids(136699507852787, 133317945673668, "rbxasset://sounds/swordslash.wav"),
			ids(138382448405483, 136699507852787, "rbxasset://sounds/swordslash.wav"),
		},
		volume = 0.8,
		pitch = { 0.92, 1.1 },
		range = 80,
	},
	metal = { variants = { ids(9116673678), ids(9116673944) }, volume = 0.6, pitch = { 0.9, 1.1 }, range = 100 },
	shotgun = {
		variants = { ids(132255180302885, 96109655199855, 18338446873, "rbxasset://sounds/Rocket shot.wav") },
		volume = 1,
		pitch = { 0.95, 1.05 },
		range = 450,
	},
	pump = { variants = { ids(113837896417526, 7129228370, "rbxasset://sounds/clickfast.wav") }, volume = 0.6, pitch = { 0.95, 1.05 }, range = 40 },
	slash = {
		variants = { ids(125132253621935, 105063425595261, "rbxasset://sounds/swordslash.wav"), ids(105063425595261, 5789211405, "rbxasset://sounds/swordslash.wav") },
		volume = 0.7,
		pitch = { 0.9, 1.1 },
		range = 60,
	},
	explosion = {
		variants = {
			ids(138533090376585, 134825578212679, 18161535641, "rbxasset://sounds/Rocket shot.wav"),
			ids(134825578212679, 138533090376585, 18161535641, "rbxasset://sounds/Rocket shot.wav"),
		},
		volume = 1,
		pitch = { 0.92, 1.05 },
		range = 700,
	},
	pin = { variants = { ids(9114659662, 9114659833, "rbxasset://sounds/clickfast.wav") }, volume = 0.8, pitch = { 0.95, 1.05 }, range = 40 },
	beep = { variants = { ids("rbxasset://sounds/electronicpingshort.wav") }, volume = 0.45, pitch = { 1.4, 1.4 }, range = 50 },
	bandage = { variants = { ids(131079594340516, 9117203790, "rbxasset://sounds/clickfast.wav") }, volume = 0.8, pitch = { 0.95, 1.05 }, range = 40 },
	carCrash = { variants = { ids(9116546326, 9116546593), ids(9116547012, 9116546358) }, volume = 0.9, pitch = { 0.9, 1.08 }, range = 200 },
	engine = { variants = { ids(80317022777602, 5830439961) }, volume = 0.5, pitch = { 1, 1 }, range = 120 },
	door = { variants = { ids("rbxasset://sounds/clickfast.wav") }, volume = 0.5, pitch = { 0.7, 0.8 }, range = 40 },
	oof = { variants = { ids("rbxasset://sounds/uuhhh.mp3") }, volume = 0.8, pitch = { 1, 1 }, range = 120 },
	step = { variants = { ids("rbxasset://sounds/action_footsteps_plastic.mp3") }, volume = 0.25, pitch = { 0.9, 1.1 }, range = 40 },
	jump = { variants = { ids("rbxasset://sounds/action_jump.mp3") }, volume = 0.3, pitch = { 0.95, 1.05 }, range = 40 },
	getup = { variants = { ids("rbxasset://sounds/action_get_up.mp3") }, volume = 0.35, pitch = { 0.95, 1.05 }, range = 40 },
	wind = { variants = { ids("rbxasset://sounds/action_falling.mp3") }, volume = 0.5, pitch = { 1, 1 }, range = 60 },
	reload = { variants = { ids(113837896417526, "rbxasset://sounds/clickfast.wav") }, volume = 0.7, pitch = { 0.8, 0.9 }, range = 40 },
	rope = { variants = { ids(131079594340516, "rbxasset://sounds/clickfast.wav") }, volume = 0.7, pitch = { 0.6, 0.7 }, range = 50 },
	teleport = { variants = { ids("rbxasset://sounds/electronicpingshort.wav") }, volume = 0.5, pitch = { 0.7, 0.75 }, range = 40 },
	physgun = { variants = { ids("rbxasset://sounds/electronicpingshort.wav") }, volume = 0.4, pitch = { 0.5, 0.55 }, range = 60 },
	-- v1.6
	rocketLaunch = { variants = { ids("rbxasset://sounds/Launching rocket.wav", "rbxasset://sounds/Rocket shot.wav") }, volume = 1, pitch = { 0.9, 1 }, range = 400 },
	glass = { variants = { ids(9116673678, "rbxasset://sounds/collide.wav") }, volume = 0.8, pitch = { 2.2, 2.6 }, range = 80 },
	blowdart = { variants = { ids("rbxasset://sounds/action_jump.mp3") }, volume = 0.5, pitch = { 2.4, 2.8 }, range = 40 },
	sneeze = { variants = { ids("rbxasset://sounds/action_jump.mp3") }, volume = 0.9, pitch = { 2.0, 2.3 }, range = 60 },
	retch = { variants = { ids("rbxasset://sounds/uuhhh.mp3") }, volume = 0.9, pitch = { 0.55, 0.65 }, range = 60 },
	whisper = { variants = { ids("rbxasset://sounds/action_falling.mp3") }, volume = 0.6, pitch = { 0.3, 0.38 }, range = 0 },
	sting = { variants = { ids(138533090376585, 134825578212679, "rbxasset://sounds/Rocket shot.wav") }, volume = 0.9, pitch = { 1.9, 2.3 }, range = 0 },
	groan = { variants = { ids("rbxasset://sounds/uuhhh.mp3") }, volume = 0.7, pitch = { 0.3, 0.4 }, range = 0 },
	heartbeat = { variants = { ids(9113480917, "rbxasset://sounds/action_jump_land.mp3") }, volume = 0.5, pitch = { 0.45, 0.5 }, range = 0 },
	toss = { variants = { ids("rbxasset://sounds/action_jump.mp3") }, volume = 0.35, pitch = { 1.45, 1.65 }, range = 40 },
	javelin = { variants = { ids(125132253621935, 105063425595261, "rbxasset://sounds/swordlunge.wav") }, volume = 0.8, pitch = { 0.55, 0.65 }, range = 70 },
	bolt = { variants = { ids(113837896417526, 7129228370, "rbxasset://sounds/clickfast.wav") }, volume = 0.7, pitch = { 0.7, 0.75 }, range = 50 },
	scope = { variants = { ids("rbxasset://sounds/clickfast.wav") }, volume = 0.35, pitch = { 0.6, 0.65 }, range = 0 },
	magOut = { variants = { ids(9114659662, "rbxasset://sounds/clickfast.wav") }, volume = 0.6, pitch = { 0.75, 0.85 }, range = 40 },
	stick = { variants = { ids(131079594340516, 9117203790, "rbxasset://sounds/splat.wav") }, volume = 0.8, pitch = { 0.55, 0.65 }, range = 60 },
	detonator = { variants = { ids("rbxasset://sounds/clickfast.wav") }, volume = 0.9, pitch = { 0.5, 0.55 }, range = 40 },
	-- a body whoosh (air), not a blade: the wind sound, fast and cut short
	kickSwoosh = { variants = { ids("rbxasset://sounds/action_falling.mp3") }, volume = 0.75, pitch = { 2.4, 2.9 }, range = 50, cut = 0.28 },
	clink = { variants = { ids(9116673678), ids(9116673944) }, volume = 0.35, pitch = { 1.6, 1.9 }, range = 60 },
	itemDrop = { variants = { ids(9113480917, "rbxasset://sounds/action_jump_land.mp3"), ids(9113480915, "rbxasset://sounds/action_jump_land.mp3") }, volume = 0.4, pitch = { 1.2, 1.4 }, range = 50 },
	sniper = {
		variants = { ids(800000246, "rbxasset://sounds/Rocket shot.wav") },
		volume = 1,
		pitch = { 0.62, 0.68 },
		range = 900,
	},
	boomFar = {
		variants = { ids(138533090376585, 134825578212679, 18161535641, "rbxasset://sounds/Rocket shot.wav") },
		volume = 1,
		pitch = { 0.35, 0.42 },
		range = 5000,
	},
	debris = { variants = { ids(9116546326, 9116546593), ids(9116547012, 9116546358) }, volume = 0.5, pitch = { 1.2, 1.5 }, range = 160 },
	siren = { variants = { ids("rbxasset://sounds/electronicpingshort.wav") }, volume = 0.8, pitch = { 0.5, 0.5 }, range = 0 },
	geiger = { variants = { ids("rbxasset://sounds/clickfast.wav") }, volume = 0.25, pitch = { 1.6, 2.2 }, range = 0 },
	click = { variants = { ids("rbxasset://sounds/electronicpingshort.wav") }, volume = 0.25, pitch = { 1.1, 1.2 }, range = 0 },
	-- v1.7
	dropKick = { variants = { ids(9120270688, "rbxasset://sounds/action_jump_land.mp3") }, volume = 1, pitch = { 0.8, 0.9 }, range = 160 },
	dropKickWhoosh = { variants = { ids("rbxasset://sounds/action_falling.mp3") }, volume = 0.9, pitch = { 1.6, 1.9 }, range = 60, cut = 0.45 },
	ringing = { variants = { ids("rbxasset://sounds/electronicpingshort.wav") }, volume = 0.35, pitch = { 2.6, 2.8 }, range = 0, loop = true, cut = 2.6 },
	flashbang = {
		variants = { ids(138533090376585, 134825578212679, 18161535641, "rbxasset://sounds/Rocket shot.wav") },
		volume = 1,
		pitch = { 1.7, 1.9 },
		range = 500,
	},
	tirePop = {
		variants = { ids(138533090376585, 134825578212679, "rbxasset://sounds/Rocket shot.wav") },
		volume = 0.7,
		pitch = { 2.6, 3 },
		range = 160,
	},
	hiss = { variants = { ids("rbxasset://sounds/action_falling.mp3") }, volume = 0.6, pitch = { 3.2, 3.6 }, range = 50, cut = 1.6 },
	splash = { variants = { ids("rbxasset://sounds/impact_water.mp3", "rbxasset://sounds/splat.wav") }, volume = 0.9, pitch = { 0.9, 1.1 }, range = 120 },
	swim = { variants = { ids("rbxasset://sounds/action_swim.mp3", "rbxasset://sounds/impact_water.mp3") }, volume = 0.45, pitch = { 0.9, 1.1 }, range = 50 },
	gurgle = { variants = { ids("rbxasset://sounds/impact_water.mp3") }, volume = 0.6, pitch = { 0.35, 0.45 }, range = 40 },
	bubbles = { variants = { ids("rbxasset://sounds/impact_water.mp3") }, volume = 0.35, pitch = { 1.8, 2.2 }, range = 30 },
	tvOn = { variants = { ids("rbxasset://sounds/clickfast.wav") }, volume = 0.6, pitch = { 0.55, 0.6 }, range = 40 },
	tvNote = { variants = { ids("rbxasset://sounds/electronicpingshort.wav") }, volume = 0.35, pitch = { 1, 1 }, range = 60 },
	static = { variants = { ids("rbxasset://sounds/action_falling.mp3") }, volume = 0.25, pitch = { 3.8, 4 }, range = 40, cut = 0.5 },
	carDoor = { variants = { ids(9116546326, "rbxasset://sounds/clickfast.wav") }, volume = 0.5, pitch = { 1.5, 1.7 }, range = 60 },
	tether = { variants = { ids(131079594340516, "rbxasset://sounds/clickfast.wav") }, volume = 0.8, pitch = { 0.5, 0.55 }, range = 60 },
	ropeSnap = { variants = { ids("rbxasset://sounds/swordslash.wav") }, volume = 0.6, pitch = { 1.6, 1.8 }, range = 60 },
	flyOn = { variants = { ids("rbxasset://sounds/electronicpingshort.wav") }, volume = 0.4, pitch = { 0.8, 0.8 }, range = 0 },
	flyOff = { variants = { ids("rbxasset://sounds/electronicpingshort.wav") }, volume = 0.4, pitch = { 0.55, 0.55 }, range = 0 },
	lung = { variants = { ids("rbxasset://sounds/uuhhh.mp3") }, volume = 0.6, pitch = { 1.25, 1.4 }, range = 50 },
	leap = { variants = { ids("rbxasset://sounds/action_jump.mp3") }, volume = 0.5, pitch = { 0.75, 0.85 }, range = 60 },
	dreamPad = { variants = { ids("rbxasset://sounds/action_falling.mp3") }, volume = 0.18, pitch = { 0.22, 0.26 }, range = 0, loop = true, noGroup = true },
	dreamChime = { variants = { ids("rbxasset://sounds/electronicpingshort.wav") }, volume = 0.18, pitch = { 0.5, 0.9 }, range = 0, noGroup = true },
	shellDrop = { variants = { ids(9113631067) }, volume = 0.3, pitch = { 0.8, 0.95 }, range = 30 },
	-- v1.8
	ignite = { variants = { ids("rbxasset://sounds/action_falling.mp3") }, volume = 0.7, pitch = { 0.55, 0.65 }, range = 80 },
	fireWhoosh = { variants = { ids(9120270688, "rbxasset://sounds/action_falling.mp3") }, volume = 1, pitch = { 0.4, 0.5 }, range = 160 },
	fireLoop = { variants = { ids("rbxasset://sounds/action_falling.mp3") }, volume = 0.35, pitch = { 0.3, 0.32 }, range = 60, loop = true },
	flame = { variants = { ids("rbxasset://sounds/action_falling.mp3") }, volume = 0.8, pitch = { 0.45, 0.45 }, range = 120, loop = true },
	spinUp = { variants = { ids("rbxasset://sounds/action_falling.mp3") }, volume = 0.6, pitch = { 1.4, 1.5 }, range = 120, cut = 0.5 },
	punchBoom = { variants = { ids(138533090376585, 134825578212679, "rbxasset://sounds/Rocket shot.wav") }, volume = 1, pitch = { 0.7, 0.8 }, range = 300 },
	laserEyes = { variants = { ids("rbxasset://sounds/action_falling.mp3") }, volume = 0.55, pitch = { 1.7, 1.7 }, range = 160, loop = true, fx = { { "dist", 0.5 }, { "flange", 9, 0.8, 0.7 }, { "eq", 2, 4, -6 } } },
	rotor = { variants = { ids("rbxasset://sounds/action_falling.mp3") }, volume = 0.9, pitch = { 0.22, 0.22 }, range = 400, loop = true },
	glassTinkle = { variants = { ids(9116673678, "rbxasset://sounds/collide.wav") }, volume = 0.4, pitch = { 3.2, 3.8 }, range = 60 },
	splinter = { variants = { ids(9116546326, "rbxasset://sounds/collide.wav") }, volume = 0.6, pitch = { 1.8, 2.1 }, range = 80 },
	-- v2.0. Each sound has its own shape: a real sample first where one exists, then a stand-in made from a
	-- sample that always loads, bent by an effect chain (distortion, tremolo, flanger, eq, reverb...) so that
	-- no two sounds are the same sample at another pitch.
	suppressed = { variants = { ids(800000246, B .. "Rocket shot.wav") }, volume = 0.3, pitch = { 1.55, 1.7 }, range = 90, fx = { { "eq", 4, -6, -26 }, { "dist", 0.1 } }, layers = { { "gunMech", 0, 0.8 } } },
	garandShot = { variants = { ids(800000246, B .. "Rocket shot.wav") }, volume = 1, pitch = { 0.78, 0.84 }, range = 600, fx = { { "eq", 6, 0, -2 }, { "reverb", 2.2, -8 } }, layers = { { "boomFar", 0.05, 0.25 } } },
	garandPing = { variants = { ids(9116673678), ids(9116673944) }, volume = 0.9, pitch = { 2.6, 2.75 }, range = 90, fx = { { "reverb", 1.2, -6 } } },
	mp5Shot = { variants = { ids(800000246, B .. "Rocket shot.wav") }, volume = 0.6, pitch = { 1.18, 1.26 }, range = 300, fx = { { "dist", 0.18 }, { "eq", -2, 3, 1 } } },
	gunMech = { variants = { ids(B .. "clickfast.wav") }, volume = 0.45, pitch = { 1.25, 1.4 }, range = 30 },
	flareShot = { variants = { ids(B .. "Launching rocket.wav", B .. "Rocket shot.wav") }, volume = 0.6, pitch = { 1.5, 1.6 }, range = 250, fx = { { "eq", -6, 2, 4 } } },
	flareBurn = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.35, pitch = { 3, 3.2 }, range = 60, loop = true, fx = { { "trem", 14, 0.35 }, { "dist", 0.35 } } },
	-- the taser: a real stun gun crackle first; the stand-in is noise chopped at the top tremolo rate and driven
	taser = {
		variants = { ids(4620812971, 1092713556, 2935387043, 157325701, alt(B .. "action_falling.mp3", 4.2, { { "trem", 20, 1, 0.3 }, { "dist", 0.85 }, { "eq", -12, 2, 6 } })) },
		volume = 0.75,
		pitch = { 0.95, 1.05 },
		range = 70,
		cut = 1.1,
		layers = { { "zap", 0 }, { "zap", 0.25, 0.7 } },
	},
	-- the crackle on whoever is tased (a loop for as long as it lasts)
	taserBuzz = {
		variants = { ids(186130717, alt(B .. "action_falling.mp3", 3.4, { { "trem", 20, 1, 0.22 }, { "dist", 0.9 }, { "eq", -16, 0, 4 } })) },
		volume = 0.5,
		pitch = { 1, 1 },
		range = 60,
		loop = true,
	},
	zap = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.32, pitch = { 2.6, 3.2 }, range = 40, fx = { { "dist", 0.9 }, { "trem", 20, 0.9, 0.4 } } },
	harpoon = { variants = { ids(B .. "swordslash.wav") }, volume = 1, pitch = { 0.4, 0.45 }, range = 160, fx = { { "eq", 6, 0, -4 } }, layers = { { "clink", 0.02, 0.8 } } },
	reel = { variants = { ids(131079594340516, B .. "clickfast.wav") }, volume = 0.45, pitch = { 1.3, 1.45 }, range = 40 },
	bulletWhiz = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.6, pitch = { 4.2, 5 }, range = 30, cut = 0.12, fx = { { "flange", 12, 0.6, 0.5 } } },
	lockBeep = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.35, pitch = { 1.1, 1.1 }, range = 0 },
	lockTone = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.5, pitch = { 2, 2 }, range = 0, fx = { { "trem", 18, 0.6, 0.5 } } },
	missileWarn = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.6, pitch = { 2.6, 2.6 }, range = 0, fx = { { "dist", 0.3 } } },
	glue = { variants = { ids(131079594340516, 9117203790, B .. "splat.wav") }, volume = 0.6, pitch = { 1.4, 1.6 }, range = 40 },
	ratchet = { variants = { ids(113837896417526, B .. "clickfast.wav") }, volume = 0.6, pitch = { 1.5, 1.8 }, range = 40 },
	weave = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.45, pitch = { 3.4, 3.9 }, range = 30, cut = 0.18 },
	flashlight = { variants = { ids(B .. "clickfast.wav") }, volume = 0.5, pitch = { 1.3, 1.4 }, range = 20 },
	-- reloads: every weapon type its own steps (mag out, mag in, the bolt / slide)
	magIn = { variants = { ids(9114659662, B .. "clickfast.wav") }, volume = 0.65, pitch = { 1.05, 1.15 }, range = 40, fx = { { "eq", 3, 0, -2 } } },
	slideRack = { variants = { ids(7129228370, 113837896417526, B .. "clickfast.wav") }, volume = 0.7, pitch = { 1.2, 1.3 }, range = 40 },
	shellIn = { variants = { ids(9113631067, B .. "clickfast.wav") }, volume = 0.5, pitch = { 0.6, 0.7 }, range = 30, layers = { { "gunMech", 0.05, 0.5 } } },
	-- the crossbow: a string, not a gun. A heavy wooden thwack, the limbs ringing, the bolt hissing off
	crossbow = {
		variants = { ids(alt(B .. "swordlunge.wav", 0.45, { { "eq", 8, 0, -6 }, { "dist", 0.12 } })) },
		volume = 0.95,
		pitch = { 0.95, 1.05 },
		range = 120,
		layers = { { "bowString", 0 }, { "bulletWhiz", 0.03, 0.6 } },
	},
	bowString = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.4, pitch = { 0.42, 0.46 }, range = 60, cut = 0.35, fx = { { "trem", 20, 0.7, 0.5 }, { "eq", 4, 0, -14 } } },
	crossbowReload = { variants = { ids(113837896417526, B .. "clickfast.wav") }, volume = 0.6, pitch = { 0.55, 0.62 }, range = 40, fx = { { "eq", 5, 0, -4 } }, layers = { { "creak", 0.1, 0.6 }, { "ratchet", 0.35, 0.8 } } },
	-- monsters, sharks, zombies, the sea, the horror map
	monsterScreech = {
		variants = { ids(alt(B .. "uuhhh.mp3", 0.24, { { "dist", 0.6 }, { "flange", 6, 0.8, 0.6 }, { "reverb", 2.5, -6 } })) },
		volume = 1,
		pitch = { 0.9, 1.1 },
		range = 320,
		layers = { { "monsterShriek", 0.05, 0.6 } },
	},
	monsterShriek = { variants = { ids(B .. "uuhhh.mp3") }, volume = 0.7, pitch = { 0.62, 0.7 }, range = 300, fx = { { "dist", 0.85 }, { "octave", 1.6 }, { "echo", 0.12, 0.35, -8 } } },
	monsterGrowl = { variants = { ids(B .. "uuhhh.mp3") }, volume = 0.85, pitch = { 0.13, 0.17 }, range = 130, fx = { { "dist", 0.45 }, { "trem", 11, 0.55, 0.5 }, { "eq", 8, 0, -10 } } },
	monsterSkitter = { variants = { ids(9116546326, B .. "collide.wav") }, volume = 0.4, pitch = { 2.6, 3.4 }, range = 80, fx = { { "trem", 20, 0.8, 0.3 } } },
	monsterLeap = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.8, pitch = { 1.3, 1.5 }, range = 120, cut = 0.45, layers = { { "monsterShriek", 0, 0.7 } } },
	monsterDig = { variants = { ids(9116546326, 9116546593, B .. "collide.wav") }, volume = 0.9, pitch = { 0.55, 0.7 }, range = 160, fx = { { "eq", 8, 0, -4 }, { "reverb", 1.2, -8 } }, layers = { { "debris", 0.1, 0.7 } } },
	monsterStep = { variants = { ids(9113480917, B .. "action_jump_land.mp3") }, volume = 0.5, pitch = { 0.5, 0.6 }, range = 70, fx = { { "eq", 6, 0, -12 } } },
	crunch = { variants = { ids(9119559518), ids(9113542363), ids(9119559825) }, volume = 1, pitch = { 0.6, 0.75 }, range = 120, layers = { { "gore", 0.02, 0.6 } } },
	sharkBite = { variants = { ids(9119559518), ids(9113542363) }, volume = 1, pitch = { 0.8, 0.9 }, range = 120, fx = { { "eq", 6, 0, -8 } }, layers = { { "splash", 0, 0.5 } } },
	zombieGroan = {
		variants = { ids(alt(B .. "uuhhh.mp3", 0.5, { { "dist", 0.3 }, { "trem", 6, 0.45, 0.5 }, { "reverb", 1.4, -10 } })), ids(alt(B .. "uuhhh.mp3", 0.38, { { "dist", 0.4 }, { "trem", 4, 0.5, 0.6 }, { "eq", 5, 0, -8 } })) },
		volume = 0.75,
		pitch = { 0.9, 1.1 },
		range = 90,
	},
	zombieBite = { variants = { ids(9119559518), ids(9119559825) }, volume = 1, pitch = { 0.85, 1 }, range = 110, layers = { { "gore", 0, 0.9 }, { "zombieGroan", 0.1, 0.6 } } },
	zombieLeap = { variants = { ids(B .. "action_jump.mp3") }, volume = 0.6, pitch = { 0.55, 0.65 }, range = 80, layers = { { "zombieGroan", 0, 0.9 } } },
	waves = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.35, pitch = { 0.42, 0.42 }, range = 0, loop = true, fx = { { "trem", 0.15, 0.5, 0.5 }, { "eq", 4, 0, -10 } } },
	shipHorn = { variants = { ids(B .. "uuhhh.mp3") }, volume = 1, pitch = { 0.1, 0.1 }, range = 1500, fx = { { "chorus", 0.4, 0.4, 0.6 }, { "reverb", 4, -2 } } },
	thunder = { variants = { ids(9116546326, B .. "Rocket shot.wav") }, volume = 1, pitch = { 0.25, 0.32 }, range = 0, fx = { { "reverb", 6, 0 }, { "eq", 8, 0, -8 } } },
	creak = { variants = { ids(B .. "uuhhh.mp3") }, volume = 0.4, pitch = { 0.5, 0.65 }, range = 60, fx = { { "trem", 9, 0.7, 0.4 }, { "eq", -6, 2, 0 } } },
	-- admin
	hotdogCharge = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.9, pitch = { 0.5, 0.5 }, range = 600, loop = true, fx = { { "flange", 3, 0.7, 0.6 } } },
	sonicBoom = { variants = { ids(138533090376585, 134825578212679, B .. "Rocket shot.wav") }, volume = 1, pitch = { 0.45, 0.5 }, range = 2000, fx = { { "reverb", 3, -4 } } },
	-- the sun cannon: a deep growing hum with a crackle in it (SuperFX bends the pitch up over the charge),
	-- a roaring beam, the sun's throb, and the supernova: a slow giant blast with a long tail
	sunCharge = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.75, pitch = { 0.22, 0.22 }, range = 900, loop = true, fx = { { "flange", 0.5, 0.9, 0.8 }, { "chorus", 0.8, 0.6, 0.5 }, { "eq", 8, 0, -6 } } },
	sunCrackle = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.35, pitch = { 2.8, 2.8 }, range = 600, loop = true, fx = { { "trem", 20, 1, 0.15 }, { "dist", 0.9 }, { "eq", -20, 0, 4 } } },
	sunBeam = { variants = { ids(B .. "action_falling.mp3") }, volume = 1, pitch = { 0.38, 0.38 }, range = 3000, loop = true, fx = { { "dist", 0.65 }, { "flange", 2.5, 0.7, 0.5 }, { "eq", 10, 2, -6 } } },
	sunFire = { variants = { ids(138533090376585, B .. "Rocket shot.wav") }, volume = 1, pitch = { 0.32, 0.36 }, range = 3000, fx = { { "reverb", 5, -2 }, { "eq", 8, 0, -4 } }, layers = { { "sonicBoom", 0.15, 0.7 } } },
	sunThrob = { variants = { ids(B .. "uuhhh.mp3") }, volume = 0.8, pitch = { 0.08, 0.08 }, range = 0, loop = true, fx = { { "trem", 0.8, 0.7, 0.5 }, { "dist", 0.3 }, { "reverb", 6, -4 } } },
	supernova = { variants = { ids(138533090376585, B .. "Rocket shot.wav") }, volume = 1, pitch = { 0.2, 0.24 }, range = 0, fx = { { "reverb", 12, 0 }, { "echo", 0.6, 0.45, -6 }, { "eq", 10, 0, -6 } }, layers = { { "boomFar", 0.4, 1 }, { "thunder", 1.2, 0.8 } } },
	timeStop = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.9, pitch = { 0.35, 0.35 }, range = 0, fx = { { "reverb", 4, -2 }, { "chorus", 0.3, 0.8, 0.6 } } },
	-- the jet: a turbine whine over a roar
	jetEngine = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.9, pitch = { 0.55, 0.55 }, range = 900, loop = true, fx = { { "eq", 6, 0, 3 }, { "flange", 0.3, 0.3, 0.35 }, { "dist", 0.2 } } },
	jetWhine = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.18, pitch = { 1.6, 1.6 }, range = 500, loop = true, fx = { { "chorus", 6, 0.4, 0.6 } } },
	-- slide, steel balls, the questline
	slideStart = { variants = { ids(B .. "action_jump.mp3") }, volume = 0.55, pitch = { 0.6, 0.7 }, range = 50, layers = { { "kickSwoosh", 0, 0.7 } } },
	slideScrape = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.6, pitch = { 1, 1 }, range = 60, loop = true, fx = { { "eq", -10, 2, -6 }, { "trem", 16, 0.35, 0.5 }, { "dist", 0.25 } } },
	steelThrow = { variants = { ids(B .. "swordslash.wav") }, volume = 0.6, pitch = { 1.25, 1.4 }, range = 60, fx = { { "eq", -4, 0, 4 } }, layers = { { "steelWhir", 0.02, 0.8 } } },
	steelWhir = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.5, pitch = { 2.3, 2.5 }, range = 60, cut = 0.5, fx = { { "trem", 20, 0.75, 0.5 }, { "flange", 8, 0.5, 0.5 } } },
	steelHit = { variants = { ids(9116673678), ids(9116673944) }, volume = 0.9, pitch = { 1.4, 1.6 }, range = 140, fx = { { "reverb", 0.9, -8 } }, layers = { { "heavyHit", 0, 0.6 } } },
	steelHead = { variants = { ids(9116673678), ids(9116673944) }, volume = 1, pitch = { 1.1, 1.2 }, range = 220, fx = { { "reverb", 1.6, -4 }, { "dist", 0.2 } }, layers = { { "boneCrack", 0, 1 }, { "heavyHit", 0, 0.9 } } },
	steelSpin = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.45, pitch = { 2.6, 2.6 }, range = 60, loop = true, fx = { { "trem", 20, 0.7, 0.5 }, { "chorus", 4, 0.5, 0.5 } } },
	steelCatch = { variants = { ids(9116673678), ids(9116673944) }, volume = 0.5, pitch = { 2.3, 2.5 }, range = 40, layers = { { "gunMech", 0, 0.5 } } },
	spinPower = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.9, pitch = { 0.5, 0.5 }, range = 0, fx = { { "chorus", 2, 0.8, 0.6 }, { "reverb", 3, -2 } } },
	relicHum = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.5, pitch = { 0.3, 0.3 }, range = 50, loop = true, fx = { { "chorus", 0.6, 0.8, 0.7 }, { "eq", 4, 0, -12 } } },
	-- (v2.8.2) the quest and notification sounds are little tunes now, not one beep: soft bell notes (the ping with its
	-- click filtered off, a chorus and a room round it) played as chords and runs
	chimeC = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.5, pitch = { 1.0, 1.0 }, range = 0, fx = { { "eq", 3, 0, -16 }, { "chorus", 1.2, 0.35, 0.4 }, { "reverb", 1.6, -6 } } },
	chimeE = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.5, pitch = { 1.26, 1.26 }, range = 0, fx = { { "eq", 3, 0, -16 }, { "chorus", 1.2, 0.35, 0.4 }, { "reverb", 1.6, -6 } } },
	chimeG = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.5, pitch = { 1.498, 1.498 }, range = 0, fx = { { "eq", 3, 0, -16 }, { "chorus", 1.2, 0.35, 0.4 }, { "reverb", 1.6, -6 } } },
	chimeA = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.45, pitch = { 1.682, 1.682 }, range = 0, fx = { { "eq", 3, 0, -16 }, { "chorus", 1.2, 0.35, 0.4 }, { "reverb", 1.6, -6 } } },
	chimeC2 = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.5, pitch = { 2.0, 2.0 }, range = 0, fx = { { "eq", 3, 0, -14 }, { "chorus", 1.2, 0.35, 0.4 }, { "reverb", 2.2, -5 } } },
	chimeHi = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.22, pitch = { 3.0, 3.0 }, range = 0, fx = { { "eq", 0, 0, -10 }, { "trem", 12, 0.4, 0.5 }, { "reverb", 2.5, -4 } } },
	chimeBass = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.55, pitch = { 0.5, 0.5 }, range = 0, fx = { { "eq", 8, 0, -20 }, { "reverb", 2, -6 } } },
	chimeLow = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.45, pitch = { 0.749, 0.749 }, range = 0, fx = { { "eq", 6, 0, -18 }, { "reverb", 1.6, -6 } } },
	-- a quest step done: two rising notes
	questDing = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.5, pitch = { 1.498, 1.498 }, range = 0, fx = { { "eq", 3, 0, -16 }, { "chorus", 1.2, 0.35, 0.4 }, { "reverb", 1.6, -6 } }, layers = { { "chimeC2", 0.11, 1 } } },
	-- a quest finished: a fanfare - a bass note and a run up the chord, a sparkle on top
	questDone = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.55, pitch = { 1.0, 1.0 }, range = 0, fx = { { "eq", 3, 0, -16 }, { "chorus", 1.2, 0.35, 0.4 }, { "reverb", 1.6, -6 } },
		layers = { { "chimeBass", 0, 1 }, { "chimeE", 0.09, 1 }, { "chimeG", 0.18, 1 }, { "chimeC2", 0.3, 1.1 }, { "chimeG", 0.3, 0.6 }, { "chimeE", 0.3, 0.5 }, { "chimeHi", 0.42, 1 } } },
	-- something failed: two falling notes, low
	questFail = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.45, pitch = { 0.94, 0.94 }, range = 0, fx = { { "eq", 6, 0, -18 }, { "reverb", 1.4, -6 } }, layers = { { "chimeLow", 0.16, 1 } } },
	-- a notice on the screen: a soft "ding-dong"
	notify = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.38, pitch = { 1.26, 1.26 }, range = 0, fx = { { "eq", 3, 0, -16 }, { "chorus", 1.2, 0.35, 0.4 }, { "reverb", 1.4, -7 } }, layers = { { "chimeC", 0.14, 0.9 } } },
	bombWhistle = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.8, pitch = { 1.7, 1.9 }, range = 400, cut = 2.5, fx = { { "flange", 1, 0.4, 0.4 } } },
	-- the chainsaw: a two-stroke motor (a small engine sped up, driven and chopped), the pull cord, the cut
	chainsawStart = { variants = { ids(113837896417526, B .. "clickfast.wav") }, volume = 0.8, pitch = { 0.5, 0.55 }, range = 60, layers = { { "chainsawRev", 0.3, 1 } } },
	chainsawRev = { variants = { ids(80317022777602, 5830439961) }, volume = 0.9, pitch = { 2.6, 2.8 }, range = 120, cut = 0.8, fx = { { "dist", 0.7 }, { "trem", 20, 0.4, 0.6 }, { "eq", -6, 4, 0 } } },
	chainsawIdle = { variants = { ids(80317022777602, 5830439961) }, volume = 0.7, pitch = { 1.9, 1.9 }, range = 110, loop = true, fx = { { "dist", 0.6 }, { "trem", 20, 0.45, 0.55 }, { "eq", -8, 4, 0 } } },
	chainsawCut = { variants = { ids(9116546326, 9116546593, B .. "collide.wav") }, volume = 0.5, pitch = { 1.6, 2 }, range = 90, fx = { { "dist", 0.5 } } },
	chainsawStop = { variants = { ids(80317022777602, 5830439961) }, volume = 0.6, pitch = { 1.1, 1.2 }, range = 80, cut = 0.4, fx = { { "dist", 0.5 }, { "eq", -6, 2, -4 } } },
	-- the parachute: the canopy snaps open, flutters while you hang under it, and folds up when you land
	chuteOpen = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.9, pitch = { 1.5, 1.7 }, range = 120, cut = 0.35, fx = { { "eq", 6, 2, -6 } }, layers = { { "thud", 0.12, 0.6 } } },
	chuteFlutter = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.3, pitch = { 0.9, 0.9 }, range = 60, loop = true, fx = { { "trem", 7, 0.6, 0.5 }, { "eq", 0, 2, -8 } } },
	chuteFold = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.5, pitch = { 0.8, 0.9 }, range = 50, cut = 0.9, fx = { { "trem", 5, 0.5, 0.5 }, { "eq", 2, 0, -10 } } },
	-- laser eyes: a searing hum, and a blast where the beam lands
	laserHum = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.6, pitch = { 1.7, 1.7 }, range = 160, loop = true, fx = { { "dist", 0.5 }, { "flange", 9, 0.8, 0.7 }, { "eq", 2, 4, -6 } } },
	laserBlast = { variants = { ids(138533090376585, 134825578212679, B .. "Rocket shot.wav") }, volume = 0.75, pitch = { 1.2, 1.4 }, range = 220, fx = { { "dist", 0.4 }, { "eq", 4, 0, 2 } } },
	-- fists of the brawler NPC, getting up
	brawlerShout = { variants = { ids(B .. "uuhhh.mp3") }, volume = 0.6, pitch = { 0.7, 0.8 }, range = 70, fx = { { "dist", 0.25 } } },
	-- breaking things
	concreteBreak = { variants = { ids(9116546326, 9116546593, 9116547012) }, volume = 0.95, pitch = { 0.5, 0.65 }, range = 220, fx = { { "eq", 8, 0, -6 }, { "reverb", 1.5, -8 } }, layers = { { "debris", 0.08, 0.8 } } },
	groundCrack = { variants = { ids(9116546326, 9116547012, B .. "Rocket shot.wav") }, volume = 1, pitch = { 0.3, 0.38 }, range = 300, fx = { { "eq", 10, 0, -10 }, { "reverb", 2.5, -4 } } },
	lightOn = { variants = { ids(B .. "clickfast.wav") }, volume = 0.4, pitch = { 0.9, 1 }, range = 20 },
	-- (v2.0) cash, skins, the roll
	cashDing = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.3, pitch = { 2.1, 2.2 }, range = 0, fx = { { "reverb", 0.8, -10 } } },
	rollTick = { variants = { ids(B .. "clickfast.wav") }, volume = 0.35, pitch = { 1.5, 1.7 }, range = 0 },
	rollWin = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.9, pitch = { 0.75, 0.75 }, range = 0, fx = { { "chorus", 2, 0.7, 0.6 }, { "reverb", 2.5, -3 } }, layers = { { "questDone", 0.1, 0.8 }, { "cashDing", 0.3, 1 } } },
	-- (v2.0) the hex doll: the needle, the thread, Tatter's voice, his munching; the fates
	stitch = { variants = { ids(B .. "clickfast.wav") }, volume = 0.4, pitch = { 0.55, 0.7 }, range = 20, fx = { { "eq", 4, 0, -6 } } },
	threadPull = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.35, pitch = { 3, 3.4 }, range = 20, cut = 0.22, fx = { { "eq", -6, 2, 4 } } },
	tatterTalk = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.16, pitch = { 2.2, 2.9 }, range = 0, cut = 0.07, fx = { { "trem", 16, 0.6, 0.5 }, { "eq", -4, 4, -6 } } },
	tatterGiggle = { variants = { ids(B .. "electronicpingshort.wav") }, volume = 0.3, pitch = { 1.7, 1.9 }, range = 0, cut = 0.6, fx = { { "trem", 13, 0.95, 0.5 }, { "chorus", 3, 0.5, 0.5 }, { "reverb", 1.2, -10 } } },
	tatterHum = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.12, pitch = { 0.45, 0.45 }, range = 0, loop = true, fx = { { "chorus", 0.8, 0.9, 0.7 }, { "eq", 2, 0, -14 } } },
	munch = { variants = { ids(9119559518), ids(9113542363) }, volume = 0.45, pitch = { 1.4, 1.7 }, range = 30 },
	hexCast = { variants = { ids(9116546326, B .. "Rocket shot.wav") }, volume = 0.6, pitch = { 0.42, 0.48 }, range = 0, fx = { { "reverb", 4, -2 }, { "eq", 6, 0, -10 } }, layers = { { "tatterGiggle", 0.4, 0.8 } } },
	neckSnap = { variants = { ids(9119559518), ids(9119559825) }, volume = 1, pitch = { 1.3, 1.5 }, range = 120, layers = { { "splinter", 0, 0.7 } } },
	slipSquelch = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.6, pitch = { 3.4, 3.8 }, range = 60, cut = 0.25, fx = { { "flange", 6, 0.8, 0.6 } } },
	fallingWhistle = { variants = { ids(B .. "action_falling.mp3") }, volume = 0.7, pitch = { 1.4, 1.5 }, range = 300, cut = 1.8, fx = { { "flange", 1.5, 0.5, 0.4 } } },
}

local failed: { [string]: boolean } = {}
local holder: Part? = nil
local master: SoundGroup? = nil

-- every sound this client plays goes through one group: knocked out = silence
function SoundLibrary.Master(): SoundGroup?
	if not RunService:IsClient() then
		return nil
	end
	if master and master.Parent then
		return master
	end
	local g = Instance.new("SoundGroup")
	g.Name = "Master"
	g.Volume = 1
	g.Parent = game:GetService("SoundService")
	master = g
	return g
end

local muted = false
local volume = 1

function SoundLibrary.SetMuted(on: boolean)
	muted = on
	local g = SoundLibrary.Master()
	if g then
		g.Volume = muted and 0 or volume
	end
end

-- the player's volume setting (menu, M)
function SoundLibrary.SetVolume(v: number)
	volume = math.clamp(v, 0, 1)
	SoundLibrary.SetMuted(muted)
end

local function getHolder(): Part
	if holder and holder.Parent then
		return holder
	end
	local fx = workspace:FindFirstChild("FX") or workspace
	local h = Instance.new("Part")
	h.Name = "SoundHolder"
	h.Anchored = true
	h.CanCollide = false
	h.CanQuery = false
	h.CanTouch = false
	h.Transparency = 1
	h.Size = Vector3.new(0.1, 0.1, 0.1)
	h.CFrame = CFrame.new(0, -2000, 0)
	h.Parent = fx
	holder = h
	return h
end

local function candId(c: any): string
	return typeof(c) == "table" and c.id or c
end

local function pickId(def): any
	local variant = def.variants[math.random(1, #def.variants)]
	for _, c in variant do
		if not failed[candId(c)] then
			return c
		end
	end
	return nil
end

local FX_CLASS = {
	dist = "DistortionSoundEffect",
	trem = "TremoloSoundEffect",
	flange = "FlangeSoundEffect",
	chorus = "ChorusSoundEffect",
	eq = "EqualizerSoundEffect",
	echo = "EchoSoundEffect",
	reverb = "ReverbSoundEffect",
	octave = "PitchShiftSoundEffect",
}

local function applyFx(s: Sound, chain: { any }?)
	if not chain then
		return
	end
	for i, e in chain do
		local cls = FX_CLASS[e[1]]
		if not cls then
			continue
		end
		local ok, fx = pcall(Instance.new, cls)
		if not ok then
			continue
		end
		local k = e[1]
		pcall(function()
			if k == "dist" then
				fx.Level = math.clamp(e[2] or 0.5, 0, 1)
			elseif k == "trem" then
				fx.Frequency = math.clamp(e[2] or 8, 0.1, 20)
				fx.Depth = math.clamp(e[3] or 0.5, 0, 1)
				fx.Duty = math.clamp(e[4] or 0.5, 0, 1)
			elseif k == "flange" or k == "chorus" then
				fx.Rate = math.clamp(e[2] or 1, 0, 20)
				fx.Depth = math.clamp(e[3] or 0.5, 0.01, 1)
				fx.Mix = math.clamp(e[4] or 0.5, 0, 1)
			elseif k == "eq" then
				fx.LowGain = e[2] or 0
				fx.MidGain = e[3] or 0
				fx.HighGain = e[4] or 0
			elseif k == "echo" then
				fx.Delay = math.clamp(e[2] or 0.2, 0.01, 10)
				fx.Feedback = math.clamp(e[3] or 0.3, 0, 1)
				fx.WetLevel = e[4] or -6
			elseif k == "reverb" then
				fx.DecayTime = math.clamp(e[2] or 1.5, 0.1, 20)
				fx.WetLevel = e[3] or -4
			elseif k == "octave" then
				fx.Octave = math.clamp(e[2] or 1, 0.5, 2)
			end
			fx.Priority = #chain - i + 1 -- (the first in the list runs first)
		end)
		fx.Parent = s
	end
end

-- Preload everything once on the client and remember which ids failed.
function SoundLibrary.Preload()
	if not RunService:IsClient() then
		return
	end
	task.spawn(function()
		local sounds = {}
		for _, def in SoundLibrary.Defs do
			for _, variant in def.variants do
				for _, c in variant do
					local s = Instance.new("Sound")
					s.SoundId = candId(c)
					table.insert(sounds, s)
				end
			end
		end
		pcall(function()
			ContentProvider:PreloadAsync(sounds, function(assetId: string, status: Enum.AssetFetchStatus)
				if status ~= Enum.AssetFetchStatus.Success then
					failed[assetId] = true
				end
			end)
		end)
		for _, s in sounds do
			s:Destroy()
		end
	end)
end

-- where: BasePart (sound follows it), Vector3 (one-shot at a position) or nil (2D / UI)
function SoundLibrary.Play(name: string, where: (BasePart | Vector3)?, volumeScale: number?, pitchScale: number?): Sound?
	local def = SoundLibrary.Defs[name]
	if not def then
		return nil
	end
	local cand = pickId(def)
	if not cand then
		return nil
	end
	-- (v2.0) layered sounds: the others play with it (a shot = the bang + the mechanism, a bite = crunch + gore)
	if def.layers then
		for _, l in def.layers do
			local lname, ldelay, lvol = l[1], l[2] or 0, l[3] or 1
			if ldelay > 0 then
				task.delay(ldelay, function()
					if typeof(where) ~= "Instance" or (where :: Instance).Parent then
						SoundLibrary.Play(lname, where, (volumeScale or 1) * lvol, pitchScale)
					end
				end)
			else
				SoundLibrary.Play(lname, where, (volumeScale or 1) * lvol, pitchScale)
			end
		end
	end
	local s = Instance.new("Sound")
	s.SoundId = candId(cand)
	if not def.noGroup then
		s.SoundGroup = SoundLibrary.Master()
	end
	s.Looped = def.loop == true
	s.Volume = def.volume * (volumeScale or 1)
	local pm = typeof(cand) == "table" and cand.pm or 1
	s.PlaybackSpeed = (def.pitch[1] + math.random() * (def.pitch[2] - def.pitch[1])) * (pitchScale or 1) * pm
	applyFx(s, typeof(cand) == "table" and cand.fx or def.fx)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 6
	s.RollOffMaxDistance = def.range > 0 and def.range or 10000
	local cleanup: Instance = s
	if typeof(where) == "Instance" then
		s.Parent = where
	elseif typeof(where) == "Vector3" then
		local a = Instance.new("Attachment")
		a.Parent = getHolder()
		a.WorldPosition = where
		s.Parent = a
		cleanup = a
	else
		s.Parent = game:GetService("SoundService")
	end
	s:Play()
	if def.cut then
		-- only the start of the sound (a whoosh out of a long wind sound); fades out
		task.delay(def.cut, function()
			if s.Parent then
				local v0 = s.Volume
				for i = 1, 6 do
					s.Volume = v0 * (1 - i / 6)
					task.wait(0.03)
				end
				s:Stop()
			end
		end)
	end
	Debris:AddItem(cleanup, def.loop and math.max(def.cut or 8, 1) + 0.5 or 8)
	return s
end

-- for a moment everything sounds dull (a blast close by, a flash grenade, under water)
local muffleToken = 0
function SoundLibrary.Muffle(seconds: number, amount: number?)
	local g = SoundLibrary.Master()
	if not g then
		return
	end
	local eq = g:FindFirstChild("Muffle") :: EqualizerSoundEffect?
	if not eq then
		local e = Instance.new("EqualizerSoundEffect")
		e.Name = "Muffle"
		e.LowGain = 0
		e.MidGain = 0
		e.HighGain = 0
		e.Parent = g
		eq = e
	end
	local k = math.clamp(amount or 1, 0, 1)
	muffleToken += 1
	local token = muffleToken
	local e = eq :: EqualizerSoundEffect
	e.HighGain = -60 * k
	e.MidGain = -24 * k
	e.LowGain = 2 * k
	task.spawn(function()
		task.wait(seconds * 0.6)
		local steps = 20
		for i = 1, steps do
			if muffleToken ~= token or not e.Parent then
				return
			end
			local f = 1 - i / steps
			e.HighGain = -60 * k * f
			e.MidGain = -24 * k * f
			e.LowGain = 2 * k * f
			task.wait(seconds * 0.4 / steps)
		end
	end)
end

-- a lasting muffle (under water): on until switched off
function SoundLibrary.SetUnderwater(on: boolean)
	local g = SoundLibrary.Master()
	if not g then
		return
	end
	local eq = g:FindFirstChild("Underwater") :: EqualizerSoundEffect?
	if on and not eq then
		local e = Instance.new("EqualizerSoundEffect")
		e.Name = "Underwater"
		e.HighGain = -45
		e.MidGain = -18
		e.LowGain = 4
		e.Parent = g
	elseif not on and eq then
		eq:Destroy()
	end
end

-- Looping sound attached to a part (e.g. falling wind). Caller manages it.
function SoundLibrary.Loop(name: string, parent: Instance): Sound?
	local def = SoundLibrary.Defs[name]
	local cand = def and pickId(def)
	if not cand then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = candId(cand)
	if not def.noGroup then
		s.SoundGroup = SoundLibrary.Master()
	end
	s.Looped = true
	s.Volume = 0
	local pm = typeof(cand) == "table" and cand.pm or 1
	s.PlaybackSpeed = (def.pitch and def.pitch[1] or 1) * pm
	s:SetAttribute("BaseSpeed", s.PlaybackSpeed) -- (callers that bend the pitch scale this)
	applyFx(s, typeof(cand) == "table" and cand.fx or def.fx)
	s.RollOffMaxDistance = def.range
	s.Parent = parent
	return s
end

return SoundLibrary
