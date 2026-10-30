--!strict
-- Cyberware (v2.8): the catalog of implants (all names and brands are made up for this game).
--   * an implant has 1-3 TIERS; a higher tier does more and costs more (dollars from kills: Config.KillCash).
--   * it goes into a SLOT of the body (one implant per slot; arms and forearms have a left and a right slot).
--   * every implant has a LOAD per tier. Your TOLERANCE is Config.CyberTolerance (20). Carry more
--     load than that and CYBERPSYCHOSIS creeps in: hallucinations that grow, and when somebody touches you or you shoot
--     somebody you can CRASH OUT (you lose control and shoot at everything that moves). Admins / COLOSSUS: no side effects.
--   * implants stay in through death and rejoining (Persist) until somebody operates them out. You can never put one in
--     (or take one out) yourself: the ripperdoc does it (pay, wait your turn, take the syringe, dream), or another player
--     with an implant case / a ripper kit.
--   * implants with an ABILITY get a key on the cyber bar (1-9 by default, M > CYBER to change them).
--   * (v2.8) 18 slot kinds - 20 places in a body (arms and forearms twice) - and 21 implants. (v2.8.1) + BONE MARROW:
--     REGROWTH CORE (22 implants).

local Cyberware = {}

export type Def = {
	id: string,
	name: string,
	brand: string,
	slot: string, -- a slot kind (see Slots)
	tiers: number,
	price: { number },
	load: { number },
	desc: { string }, -- what each tier does (one line each)
	info: string, -- what it is (the shop's text)
	ability: string?, -- the label on the cyber bar (nil = passive)
	cooldown: { number }?, -- s per tier
	admin: boolean?, -- only admins (or what an admin gifted) may have it
}

-- the slots of a body (side = the slot exists twice: _L and _R)
Cyberware.Slots = {
	{ id = "eyes", name = "OPTICS", side = false },
	{ id = "brain", name = "CORTEX", side = false },
	{ id = "os", name = "OPERATING SYSTEM", side = false },
	{ id = "spine", name = "SPINE", side = false },
	{ id = "chest", name = "CHEST", side = false },
	{ id = "arm", name = "ARM", side = true },
	{ id = "fore", name = "FOREARM", side = true },
	{ id = "palms", name = "PALMS", side = false },
	{ id = "legs", name = "LEGS", side = false },
	{ id = "nerves", name = "NERVOUS SYSTEM", side = false },
	{ id = "skin", name = "SKIN", side = false },
	{ id = "dermis", name = "DERMIS", side = false },
	{ id = "subdermal", name = "SUBDERMAL", side = false },
	{ id = "frame", name = "SKELETON", side = false },
	{ id = "blood", name = "CIRCULATION", side = false },
	{ id = "lungs", name = "LUNGS", side = false },
	{ id = "ears", name = "EARS", side = false },
	{ id = "marrow", name = "BONE MARROW", side = false },
	{ id = "stance", name = "STANCE", side = false }, -- (v2.8.2)
	{ id = "shell", name = "ARMOUR SHELL", side = false }, -- (v2.8.2)
	{ id = "core", name = "PROTOCOL", side = false },
}

Cyberware.List = {
	{
		id = "optics", name = "WARDEN OPTICS", brand = "HALDEN OPTICS", slot = "eyes", tiers = 3,
		price = { 250, 700, 1600 }, load = { 1, 2, 3 },
		desc = {
			"Marks the target at your crosshair: you see it through walls, with its distance.",
			"Aiming a gun pulls your aim onto the marked target.",
			"Hard lock: your aim stays on it. Red combat vision (toggle with the key held).",
		},
		info = "Replacement eyes with a targeting lens. One lens at tier 1, three at tier 3.",
		ability = "LOCK", cooldown = { 0.4, 0.4, 0.4 },
	},
	{
		id = "cortex", name = "HUNTER CORTEX", brand = "GRAYLINE NEURAL", slot = "brain", tiers = 3,
		price = { 300, 800, 1800 }, load = { 1, 2, 3 },
		desc = {
			"Pick one person (crosshair): you see them through walls, anywhere.",
			"An arrow on your screen always points to them, with the distance.",
			"Your hits on them do 25% more damage.",
		},
		info = "A hunting program behind the temples. One target at a time.",
		ability = "HUNT", cooldown = { 2, 2, 2 },
	},
	{
		id = "sandevistan", name = "SANDEVISTAN", brand = "SPINE OS", slot = "os", tiers = 1,
		price = { 4000 }, load = { 5 },
		desc = { "Double-tap SHIFT: the world runs in slow motion for a few seconds while you do not." },
		info = "The spine implant that slows the world. Burns out if you use it twice in a row.",
	},
	{
		id = "keel", name = "KEEL SPINE", brand = "MERIDIAN BIOWORKS", slot = "spine", tiers = 3,
		price = { 200, 550, 1200 }, load = { 1, 1, 2 },
		desc = {
			"Better balance: you stay on your feet more often, you get up faster.",
			"Shots to the body no longer knock you over.",
			"Hits knock you down for a third of the time.",
		},
		info = "Gyroscopic vertebrae down the lower back.",
	},
	{
		id = "aegis", name = "AEGIS CORE", brand = "TENRYU SYSTEMS", slot = "chest", tiers = 3,
		price = { 350, 900, 2000 }, load = { 2, 2, 3 },
		desc = { "A shield of 30 that takes damage first.", "Shield 60.", "Shield 100, recharges faster." },
		info = "A field emitter in the chest. It recharges after a few seconds without being hit.",
	},
	{
		id = "titan", name = "TITAN FRAME ARM", brand = "VOSS KINETIC", slot = "arm", tiers = 3,
		price = { 300, 750, 1700 }, load = { 1, 2, 3 },
		desc = {
			"A full metal arm: +20% durability, health and power.",
			"+35% durability, health and power.",
			"+50% durability, health and power; it can not be cut off.",
		},
		info = "Replaces the whole arm. Every one is built different: random model, random finish.",
	},
	{
		id = "howler", name = "HOWLER ARM CANNON", brand = "PALE HORSE ARMORY", slot = "fore", tiers = 3,
		price = { 600, 1400, 2800 }, load = { 2, 3, 4 },
		desc = { "Fires a shell from the forearm (6 s).", "4 s between shots, bigger shells.", "2.5 s, heavy shells." },
		info = "A cannon built into the forearm. Shell (explosive / shock / slug) and colour: M > CYBERWARE.",
		ability = "CANNON", cooldown = { 6, 4, 2.5 },
	},
	{
		id = "shiftgun", name = "SHIFTGUN FOREARM", brand = "PALE HORSE ARMORY", slot = "fore", tiers = 3,
		price = { 500, 1200, 2400 }, load = { 2, 3, 3 },
		desc = {
			"The forearm opens into a gun: F fires while the hand is empty.",
			"Faster fire, more damage.",
			"Full auto, armour-piercing.",
		},
		info = "A gun that folds into your arm. Press its key to open / close it.",
		ability = "ARM GUN", cooldown = { 1, 1, 1 },
	},
	{
		id = "sickles", name = "SICKLE BLADES", brand = "VOSS KINETIC", slot = "fore", tiers = 3,
		price = { 550, 1300, 2600 }, load = { 2, 3, 3 },
		desc = {
			"Blades out of the forearm: your punches slash (bleeding).",
			"They cut limbs off.",
			"Longer blades; a jump while they are out is a lunge.",
		},
		info = "Folding blades along the forearm. Press their key to open / close them.",
		ability = "BLADES", cooldown = { 1, 1, 1 },
	},
	{
		id = "lodestone", name = "LODESTONE PALMS", brand = "VOSS KINETIC", slot = "palms", tiers = 3,
		price = { 250, 650, 1500 }, load = { 1, 1, 2 },
		desc = {
			"Electromagnets: pull the item you look at to you (30 studs). The locked item shows on screen.",
			"60 studs.",
			"90 studs - and it rips a gun out of somebody's hand.",
		},
		info = "Coils in both palms.",
		ability = "PULL", cooldown = { 3, 2, 1.5 },
	},
	{
		id = "strider", name = "STRIDER LEGS", brand = "VOSS KINETIC", slot = "legs", tiers = 3,
		price = { 300, 750, 1600 }, load = { 1, 2, 3 },
		desc = {
			"+12% speed, +15% jump, -30% fall damage.",
			"+22% speed, +30% jump, -55% fall damage.",
			"+32% speed, +50% jump, -80% fall damage.",
		},
		info = "Reinforced legs with pistons in the calves.",
	},
	{
		id = "sentry", name = "SENTRY REFLEX", brand = "GRAYLINE NEURAL", slot = "nerves", tiers = 3,
		price = { 300, 800, 1900 }, load = { 1, 2, 3 },
		desc = {
			"Somebody shoots at you: a red marker shows where from.",
			"Your body turns towards the shooter on its own.",
			"Your gun arm snaps onto the shooter too.",
		},
		info = "Threat detection wired into the spinal cord.",
	},
	{
		id = "ghostskin", name = "GHOSTSKIN", brand = "HALDEN OPTICS", slot = "skin", tiers = 3,
		price = { 700, 1500, 3000 }, load = { 2, 3, 3 },
		desc = { "Invisible for 6 s.", "10 s.", "15 s." },
		info = "Light-bending skin. Attacking shows you for a moment.",
		ability = "CLOAK", cooldown = { 30, 25, 20 },
	},
	{
		id = "dermis", name = "STATIC DERMIS", brand = "TENRYU SYSTEMS", slot = "dermis", tiers = 3,
		price = { 300, 750, 1600 }, load = { 1, 2, 2 },
		desc = {
			"Whoever hurts you close up (punch, kick, blade) gets a shock.",
			"A stronger shock that knocks them down.",
			"It throws them back.",
		},
		info = "Capacitors under the skin.",
	},
	{
		id = "blastweave", name = "BLASTWEAVE", brand = "MERIDIAN BIOWORKS", slot = "subdermal", tiers = 3,
		price = { 300, 750, 1600 }, load = { 1, 2, 2 },
		desc = { "-35% explosion damage, -30% blast push.", "-55% / -50%.", "-70% / -65%." },
		info = "A woven armour layer under the skin.",
	},
	{
		id = "bulk", name = "BULK FRAME", brand = "MERIDIAN BIOWORKS", slot = "frame", tiers = 3,
		price = { 400, 1000, 2200 }, load = { 2, 3, 4 },
		desc = { "You are 12% bigger and take 13% less damage.", "22% bigger, 25% less damage.", "35% bigger, 35% less damage." },
		info = "A lengthened, reinforced skeleton.",
	},
	{
		id = "pump", name = "IRONHEART PUMP", brand = "MERIDIAN BIOWORKS", slot = "blood", tiers = 3,
		price = { 350, 850, 1800 }, load = { 1, 2, 3 },
		desc = {
			"Wounds bleed 40% less, and you heal sooner after a hit.",
			"Bleeding -60%, healing twice as fast.",
			"Bleeding -80%, healing much faster - and open wounds close by themselves.",
		},
		info = "A second heart that keeps the pressure up and the blood in.",
	},
	{
		id = "lungs", name = "DEEPWATER LUNGS", brand = "TENRYU SYSTEMS", slot = "lungs", tiers = 3,
		price = { 200, 500, 1100 }, load = { 1, 1, 2 },
		desc = { "You hold your breath twice as long.", "Four times as long.", "You never drown, and the virus can not get in." },
		info = "Oxygen reservoirs and filters behind the ribs.",
	},
	{
		id = "echo", name = "ECHO EARS", brand = "HALDEN OPTICS", slot = "ears", tiers = 3,
		price = { 250, 600, 1300 }, load = { 1, 1, 2 },
		desc = {
			"A radar of footsteps: players moving within 45 studs show on it.",
			"75 studs - bots and NPCs too.",
			"120 studs, and it shows who is above or below you.",
		},
		info = "Microphones in both ears and a map of the sounds in the corner of your eye.",
	},
	{
		id = "regrowth", name = "REGROWTH CORE", brand = "MERIDIAN BIOWORKS", slot = "marrow", tiers = 3,
		price = { 450, 1100, 2600 }, load = { 2, 3, 4 },
		desc = {
			"Regenerates 2 HP/s per intact limb; broken bones mend in 10-16 s.",
			"Regenerates 4 HP/s, closes bleeding, regrows arms and legs in 8-12 s.",
			"Regenerates 7 HP/s; limbs in 5-8 s. Lost head or torso recovers in 10-16 s, once per 120 s.",
		},
		info = "Engineered marrow repairs tissue, seals bleeding and rebuilds missing limbs.",
	},
	-- (v2.8.2)
	{
		id = "anchor", name = "BEDROCK STABILIZER", brand = "VOSS KINETIC", slot = "stance", tiers = 3,
		price = { 500, 1200, 2600 }, load = { 2, 3, 4 },
		desc = {
			"Kicks, punches, shots and blades never knock you over, and barely push you: a drop kick and you just stand there.",
			"Things and cars that crash into you do not either.",
			"Nothing does - not even an explosion or a hard landing. You stand where you stand.",
		},
		info = "Gyro-stabilised hips and locking knee joints. You still feel every hit - you just do not fall.",
	},
	{
		id = "bastion", name = "BASTION SHELL", brand = "PALE HORSE ARMORY", slot = "shell", tiers = 3,
		price = { 650, 1500, 3000 }, load = { 2, 3, 4 },
		desc = {
			"When somebody shoots at you, metal plates fold out over your body for 6 s: bullets do 50% less.",
			"8 s, bullets do 70% less.",
			"10 s, bullets do 90% less. It has gaps: the head, the sides under the arms and the backs of the legs.",
		},
		info = "Folded plates along the spine and the limbs. They close round you the moment a threat is seen.",
	},
	-- admins only (or gifted by one)
	{
		id = "zerohour", name = "ZERO HOUR", brand = "ADMIN", slot = "core", tiers = 1,
		price = { 0 }, load = { 0 },
		desc = { "Freezes every other player and every bot on the server for 8 s." },
		info = "Admins only.",
		ability = "FREEZE", cooldown = { 20 },
		admin = true,
	},
	{
		id = "colossus", name = "COLOSSUS PROTOCOL", brand = "ADMIN", slot = "core", tiers = 1,
		price = { 0 }, load = { 0 },
		desc = { "Three times your size. Normal bullets do nothing, only big blasts, cars and nukes knock you over. Every best implant, a Sandevistan, no side effects." },
		info = "Admins only.",
		admin = true,
	},
} :: { Def }

Cyberware.ById = {} :: { [string]: Def }
for _, d in Cyberware.List do
	Cyberware.ById[d.id] = d
end

Cyberware.SlotName = {} :: { [string]: string }
for _, s in Cyberware.Slots do
	Cyberware.SlotName[s.id] = s.name
end

-- the slot key an implant takes ("arm_L" / "arm_R" for the sided ones)
function Cyberware.SlotKey(def: Def, side: string?): string
	for _, s in Cyberware.Slots do
		if s.id == def.slot and s.side then
			return def.slot .. "_" .. (side == "L" and "L" or "R")
		end
	end
	return def.slot
end

-- a key in a body's implant list: "<id>" or "<id>_L" / "<id>_R" (sided)
function Cyberware.Key(id: string, side: string?): string
	local d = Cyberware.ById[id]
	if d then
		for _, s in Cyberware.Slots do
			if s.id == d.slot and s.side then
				return id .. "_" .. (side == "L" and "L" or "R")
			end
		end
	end
	return id
end

function Cyberware.Split(key: string): (string, string?)
	local id, side = string.match(key, "^(%a+)_([LR])$")
	if id then
		return id, side
	end
	return key, nil
end

-- the load of a body's implants (key -> tier)
function Cyberware.Load(list: { [string]: number }): number
	local n = 0
	for key, tier in list do
		local id = Cyberware.Split(key)
		local d = Cyberware.ById[id]
		if d then
			n += d.load[math.clamp(tier, 1, d.tiers)] or 0
		end
	end
	return n
end

-- the price of installing (or the refund-free price of removing: Config.CyberRemoveShare of it)
function Cyberware.Price(id: string, tier: number): number
	local d = Cyberware.ById[id]
	return d and (d.price[math.clamp(tier, 1, d.tiers)] or 0) or 0
end

-- an implant list in one attribute: "optics=3,titan_L=2,..."
function Cyberware.Encode(list: { [string]: number }): string
	local parts = {}
	for key, tier in list do
		table.insert(parts, key .. "=" .. tostring(tier))
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

function Cyberware.Decode(s: any): { [string]: number }
	local out = {}
	if typeof(s) ~= "string" then
		return out
	end
	for key, tier in string.gmatch(s, "([%w_]+)=(%d)") do
		local id = Cyberware.Split(key)
		local d = Cyberware.ById[id]
		local t = tonumber(tier)
		if d and t then
			out[key] = math.clamp(t, 1, d.tiers)
		end
	end
	return out
end

-- the tier of an implant in a decoded list (either side for a sided one)
function Cyberware.Tier(list: { [string]: number }, id: string): number
	local best = list[id] or 0
	local l, r = list[id .. "_L"], list[id .. "_R"]
	if l and l > best then
		best = l
	end
	if r and r > best then
		best = r
	end
	return best
end

-- finishes of a TITAN arm (random per arm): name, plate colour, seam glow
Cyberware.Finishes = {
	{ name = "CHROME", plate = Color3.fromRGB(196, 202, 212), dark = Color3.fromRGB(58, 62, 70), glow = Color3.fromRGB(90, 220, 255), refl = 0.35 },
	{ name = "GUNMETAL", plate = Color3.fromRGB(78, 82, 90), dark = Color3.fromRGB(30, 32, 36), glow = Color3.fromRGB(255, 70, 70), refl = 0.15 },
	{ name = "CARBON", plate = Color3.fromRGB(32, 33, 37), dark = Color3.fromRGB(16, 16, 18), glow = Color3.fromRGB(80, 255, 160), refl = 0.05 },
	{ name = "BRASS", plate = Color3.fromRGB(196, 160, 82), dark = Color3.fromRGB(70, 52, 30), glow = Color3.fromRGB(255, 190, 90), refl = 0.25 },
	{ name = "CRIMSON", plate = Color3.fromRGB(150, 26, 36), dark = Color3.fromRGB(34, 20, 22), glow = Color3.fromRGB(255, 220, 120), refl = 0.15 },
	{ name = "CERAMIC", plate = Color3.fromRGB(226, 228, 232), dark = Color3.fromRGB(70, 74, 82), glow = Color3.fromRGB(255, 120, 200), refl = 0.05 },
	{ name = "COBALT", plate = Color3.fromRGB(38, 70, 150), dark = Color3.fromRGB(18, 24, 44), glow = Color3.fromRGB(120, 200, 255), refl = 0.2 },
}
Cyberware.Models = { "PLATED", "SKELETAL", "HEAVY" }

-- the HOWLER's shells and colours (M > CYBERWARE)
Cyberware.Shells = { "EXPLOSIVE", "SHOCK", "SLUG" }
Cyberware.Colors = {
	{ name = "RED", c = Color3.fromRGB(255, 60, 50) },
	{ name = "CYAN", c = Color3.fromRGB(60, 230, 255) },
	{ name = "GREEN", c = Color3.fromRGB(90, 255, 120) },
	{ name = "VIOLET", c = Color3.fromRGB(190, 90, 255) },
	{ name = "AMBER", c = Color3.fromRGB(255, 180, 50) },
	{ name = "WHITE", c = Color3.fromRGB(240, 240, 255) },
}

-- the default keys of the cyber bar
Cyberware.DefaultKeys = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }

return Cyberware
