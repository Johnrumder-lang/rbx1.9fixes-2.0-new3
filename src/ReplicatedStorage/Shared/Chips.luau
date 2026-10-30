--!strict
-- Chips (v2.9): the catalog of neck chips for the cyberdeck. All names and effects are made up for this game
-- (a cyberpunk sandbox), like the implants in Shared/Cyberware.
--   * a body has Config.ChipSlots (4) neck slots. A chip sits in one slot.
--   * KINDS:
--       "combat"   a fast skill that works on its own or on a toggle (REFLEX BUFFER dodges bullets, ZOOM, SCANNER).
--       "net"      a NETRUNNER QUICKHACK: aimed at a person in the netrunner interface (K). It lands only if your
--                  tier is higher than their FIREWALL tier (a FIREWALL chip). A higher tier does more.
--       "firewall" passive defence: antivirus + quickhack resistance. A virus / quickhack of this tier or lower bounces.
--       "capacity" passive: +cyberware tolerance (so more implants fit without cyberpsychosis).
--       "blank"    nothing until you program it at a computer (it becomes a virus chip).
--       "blackwall" admins only. An admin opens the netrunner interface and lets it loose on someone (a red beam, ash).
--                  Anybody who is not an admin that slots it is smitten by the beam themselves.
--   * a VIDEO chip is not in this catalog - the camera makes it (CameraService). It can carry a virus (a trojan).

local Chips = {}

export type Def = {
	id: string,
	name: string,
	kind: string, -- "combat" | "net" | "firewall" | "capacity" | "blank" | "blackwall"
	tiers: number,
	price: { number },
	desc: { string }, -- what each tier does (one line each)
	info: string,
	ability: string?, -- the label (combat toggles / net quickhacks); nil = passive
	cooldown: { number }?, -- s per tier (net quickhacks, combat actives)
	color: { number }, -- {r,g,b} the chip's glow
	admin: boolean?,
}

Chips.List = {
	-- combat / active
	{
		id = "dodge", name = "REFLEX BUFFER", kind = "combat", tiers = 3,
		price = { 400, 1000, 2200 },
		desc = {
			"The next bullet that would hit you is dodged. 20 s between charges.",
			"The next 2 bullets are dodged.",
			"The next 3 bullets trigger a sidestep into a clear lane.",
		},
		info = "Reads the shot before it lands and steps your body out of the line. It works on its own.",
		ability = "DODGE", cooldown = { 20, 20, 20 }, color = { 90, 220, 255 },
	},
	{
		id = "zoom", name = "ZOOM OPTICS", kind = "combat", tiers = 3,
		price = { 150, 400, 900 },
		desc = { "Zoom in (toggle in the deck, K).", "Zoom in further.", "A long-range scope." },
		info = "A lens that magnifies what you look at. Toggle it in the cyberdeck (K).",
		ability = "ZOOM", color = { 120, 200, 255 },
	},
	{
		id = "scan", name = "SCANNER", kind = "combat", tiers = 3,
		price = { 250, 650, 1500 },
		desc = {
			"Everything on your screen is boxed and named (people, items, cars).",
			"It also reads their health and what chrome they carry.",
			"It reads their FIREWALL too - who you can hack and who you can not.",
		},
		info = "An identify routine. Draws a box round everything you see. Toggle it in the cyberdeck (K).",
		ability = "SCAN", color = { 120, 255, 200 },
	},
	-- netrunner quickhacks (aimed at a person in the netrunner interface, K)
	{
		id = "burnout", name = "BURNOUT", kind = "net", tiers = 3,
		price = { 500, 1200, 2600 },
		desc = {
			"Overloads a target: a jolt of damage. Beats a FIREWALL below its tier.",
			"More damage, and it stuns them for a moment.",
			"A heavy overload: big damage, it knocks them down and burns their chrome for a few seconds.",
		},
		info = "Pushes a surge back down the link. The classic quickhack.",
		ability = "BURNOUT", cooldown = { 16, 14, 12 }, color = { 255, 90, 70 },
	},
	{
		id = "overheat", name = "OVERHEAT", kind = "net", tiers = 3,
		price = { 450, 1100, 2400 },
		desc = { "Sets the target on fire.", "A bigger fire, longer.", "They burn hard and can not put it out fast." },
		info = "Spins their cooling the wrong way until they cook.",
		ability = "OVERHEAT", cooldown = { 18, 16, 14 }, color = { 255, 140, 40 },
	},
	{
		id = "shortcircuit", name = "SHORT CIRCUIT", kind = "net", tiers = 3,
		price = { 450, 1100, 2400 },
		desc = {
			"A shock, and their chips go dead for 4 s (no quickhacks, no dodge, no implants).",
			"8 s dead, more shock.",
			"12 s dead, a heavy shock that drops them.",
		},
		info = "An EMP down the link: it shuts their chrome off for a while.",
		ability = "EMP", cooldown = { 20, 18, 16 }, color = { 120, 200, 255 },
	},
	{
		id = "reboot", name = "REBOOT OPTICS", kind = "net", tiers = 3,
		price = { 400, 1000, 2200 },
		desc = { "Blinds the target for 3 s.", "Blinds them for 5 s.", "Blinds them for 8 s, and scrambles their aim." },
		info = "Reboots their eyes: their screen goes white.",
		ability = "BLIND", cooldown = { 16, 14, 12 }, color = { 240, 240, 255 },
	},
	{
		id = "contagion", name = "CONTAGION", kind = "net", tiers = 3,
		price = { 550, 1300, 2800 },
		desc = {
			"Infects the target with the virus (it spreads to whoever is near them).",
			"Faster, and it hurts more.",
			"A hard strain that spreads fast and far.",
		},
		info = "Loads the biological virus into their blood over the link. It spreads like the bottle does.",
		ability = "CONTAGION", cooldown = { 22, 20, 18 }, color = { 120, 255, 120 },
	},
	{
		id = "cyberpsycho", name = "CYBERPSYCHOSIS", kind = "net", tiers = 3,
		price = { 700, 1600, 3400 },
		desc = {
			"The target crashes out for a few seconds: they attack whoever is nearest.",
			"Longer, and harder to shake.",
			"A full crash out: they go on a rampage until it wears off.",
		},
		info = "Floods them with chrome-madness. They stop being yours to reason with.",
		ability = "PSYCHO", cooldown = { 28, 26, 24 }, color = { 190, 90, 255 },
	},
	{
		id = "sysreset", name = "SYSTEM RESET", kind = "net", tiers = 3,
		price = { 600, 1400, 3000 },
		desc = { "Knocks the target out cold for a while.", "Longer.", "They drop like a stone and stay down." },
		info = "Flatlines their system to standby: they fall asleep where they stand.",
		ability = "RESET", cooldown = { 30, 28, 26 }, color = { 80, 180, 255 },
	},
	{
		id = "weaponglitch", name = "WEAPON GLITCH", kind = "net", tiers = 3,
		price = { 350, 850, 1800 },
		desc = { "The target drops what is in their hands.", "They drop it and can not grab for 3 s.", "They can not grab for 6 s." },
		info = "Jams the grip servos in their hands: whatever they hold slips out.",
		ability = "GLITCH", cooldown = { 16, 14, 12 }, color = { 255, 200, 70 },
	},
	{
		id = "cripple", name = "CRIPPLE MOVEMENT", kind = "net", tiers = 3,
		price = { 350, 850, 1800 },
		desc = { "Slows the target to a crawl for 4 s.", "6 s, slower.", "8 s, they can barely move." },
		info = "Locks their leg servos half-shut.",
		ability = "CRIPPLE", cooldown = { 16, 14, 12 }, color = { 150, 170, 255 },
	},
	-- defence / passive
	{
		id = "firewall", name = "FIREWALL", kind = "firewall", tiers = 3,
		price = { 400, 1000, 2200 },
		desc = {
			"A firewall of tier 1: viruses and quickhacks of tier 1 bounce off you.",
			"Tier 2: tier 1 and 2 bounce.",
			"Tier 3: only a stronger netrunner can touch you.",
		},
		info = "Antivirus. A virus or quickhack only lands if it is a higher tier than your firewall.",
		color = { 90, 255, 170 },
	},
	{
		id = "capacity", name = "RAM EXPANSION", kind = "capacity", tiers = 3,
		price = { 500, 1200, 2600 },
		desc = {
			"+1 cyberware tolerance (room for more implants before cyberpsychosis).",
			"+2 tolerance.",
			"+3 tolerance.",
		},
		info = "More memory for your chrome. You can carry more implants without crashing out.",
		color = { 255, 210, 90 },
	},
	{
		id = "blank", name = "BLANK CHIP", kind = "blank", tiers = 1,
		price = { 80 },
		desc = { "Empty. Program it at a computer into a virus, or load a video onto it." },
		info = "A blank chip. Take it to a computer to make a virus, or record onto it.",
		color = { 150, 150, 160 },
	},
	{
		id = "blackwall", name = "BLACKWALL SHARD", kind = "blackwall", tiers = 1,
		price = { 0 },
		desc = { "A sliver of the Blackwall. An admin can let it loose on someone: a red beam, and they are ash." },
		info = "Admins only. Anyone else who slots it is burned by the beam themselves.",
		ability = "BLACKWALL", cooldown = { 20 }, color = { 255, 30, 40 }, admin = true,
	},
}

Chips.ById = {} :: { [string]: Def }
for _, d in Chips.List do
	Chips.ById[d.id] = d
end

-- the payloads a virus (a programmed blank chip, or a trojan in a video) can carry
Chips.Payloads = {
	{ id = "explode", name = "DETONATE", info = "They blow up." },
	{ id = "hallucinate", name = "HALLUCINATE", info = "They start seeing things that are not there." },
	{ id = "rampage", name = "RAMPAGE", info = "They crash out and attack whoever is near." },
	{ id = "killtarget", name = "KILL A TARGET", info = "Choose a target when inserting. After 15 s, the carrier is controlled until the target dies." },
}
Chips.PayloadById = {} :: { [string]: { id: string, name: string, info: string } }
for _, p in Chips.Payloads do
	Chips.PayloadById[p.id] = p
end

function Chips.Color(d: Def): Color3
	local c = d.color
	return Color3.fromRGB(c[1], c[2], c[3])
end

function Chips.Price(id: string, tier: number): number
	local d = Chips.ById[id]
	return d and (d.price[math.clamp(tier, 1, d.tiers)] or 0) or 0
end

return Chips
