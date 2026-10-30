--!nonstrict
-- ChipService (v2.9): the cyberdeck. Everything about neck chips (Shared/Chips) - the 4 slots, buying and programming
-- them, the netrunner quickhacks, viruses, the REFLEX BUFFER dodge, the FIREWALL, and the Blackwall.
--   * every player has Config.ChipSlots (4) neck slots and a bag of chips they own. Both are kept in the profile
--     (Persist) so they come back - videos are the exception (they live for the session only).
--   * COMBAT chips work on their own / on a toggle: REFLEX BUFFER (dodges bullets, here), ZOOM and SCANNER (client).
--   * NETRUNNER quickhacks (K, the netrunner interface): aimed at a person. They land only if your tier is higher than
--     the target's FIREWALL tier. A FIREWALL is antivirus too (a virus of its tier or lower bounces off).
--   * a VIRUS is a programmed blank chip (ComputerService). Pushed into somebody (grab + F) it infects them if their
--     firewall is too low. A virus can also be baked into a VIDEO (a trojan): watching it sets the payload off.
--   * the BLACKWALL: an admin lets it loose on a target (a red beam, ash). Anybody else who slots it is burned themselves.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Chips = require(Shared:WaitForChild("Chips"))
local Items = require(Shared:WaitForChild("Items"))
local Modules = script.Parent
local Persist = require(Modules:WaitForChild("Persist"))

local ChipService = {}

local deps: any = {}
local Remote: RemoteEvent
local rng = Random.new()

-- a chip, in a slot or in the bag or on a held item
export type Chip = {
	uid: number,
	id: string, -- a catalog id, or "virus", or "video"
	kind: string, -- from the catalog, or "virus" / "video"
	tier: number,
	name: string?,
	payload: string?, -- virus / trojan: "explode" | "hallucinate" | "rampage" | "killtarget"
	target: number?, -- killtarget: the userId to go after
	clip: string?, -- video: the clip code (CameraService)
	trojan: boolean?, -- a video that carries a payload
}

type St = {
	slots: { [number]: Chip }, -- 1..Config.ChipSlots
	bag: { Chip },
	dodgeLeft: number,
	dodgeRefill: number,
}
local states: { [Player]: St } = {}
local uidCounter = 0

-- set by ComputerService: is this player standing at a computer right now?
ChipService.NearComputer = nil :: ((Player) -> boolean)?
-- set by CameraService
ChipService.Camera = nil :: any

------------------------------------------------------------------------
-- state
------------------------------------------------------------------------

local function stOf(p: Player): St
	local st = states[p]
	if not st then
		st = { slots = {}, bag = {}, dodgeLeft = 0, dodgeRefill = 0 }
		states[p] = st
	end
	return st
end

local function nextUid(): number
	uidCounter += 1
	return uidCounter
end

local function alive(p: Player): (Model?, BasePart?)
	local c = p.Character
	local t = c and c:FindFirstChild("Torso")
	if c and t and t:IsA("BasePart") and c:GetAttribute("Dead") ~= true and c.Parent then
		return c, t
	end
	return nil, nil
end

-- the best FIREWALL tier a body has right now (0 = none). EMP'd chips count as 0.
local function firewallOf(p: Player): number
	local st = states[p]
	if not st then
		return 0
	end
	local c = p.Character
	if c and typeof(c:GetAttribute("ChipsDisabled")) == "number" and workspace:GetServerTimeNow() < c:GetAttribute("ChipsDisabled") then
		return 0
	end
	local best = 0
	for _, chip in st.slots do
		if chip.id == "firewall" and chip.tier > best then
			best = chip.tier
		end
	end
	return best
end
ChipService.Firewall = firewallOf

-- the tiers of things the client / others need: firewall, the dodge charges, how much capacity we add
local function publicAttrs(p: Player)
	local st = stOf(p)
	p:SetAttribute("ChipFirewall", firewallOf(p) > 0 and firewallOf(p) or nil)
	-- capacity: +tolerance for the cyberware (CyberService reads CyTolBonus)
	local bonus = 0
	for _, chip in st.slots do
		if chip.id == "capacity" then
			bonus += ({ 1, 2, 3 })[math.clamp(chip.tier, 1, 3)]
		end
	end
	p:SetAttribute("CyTolBonus", bonus > 0 and bonus or nil)
	p:SetAttribute("CyTol", Config.CyberTolerance + bonus) -- (the ripperdoc / cyber page shows this)
	p:SetAttribute("ChipDodge", st.dodgeLeft > 0 and st.dodgeLeft or nil)
end

-- a sanitised copy of a chip for the client (the owner sees everything)
local function wire(chip: Chip): any
	return {
		uid = chip.uid, id = chip.id, kind = chip.kind, tier = chip.tier, name = chip.name,
		payload = chip.payload, target = chip.target, trojan = chip.trojan, video = chip.clip ~= nil,
	}
end

local function sendDeck(p: Player)
	local st = stOf(p)
	local slots = {}
	for i = 1, Config.ChipSlots do
		slots[i] = st.slots[i] and wire(st.slots[i]) or false
	end
	local bag = {}
	for _, chip in st.bag do
		table.insert(bag, wire(chip))
	end
	Remote:FireClient(p, "deck", { slots = slots, bag = bag, dodge = st.dodgeLeft })
end
ChipService.SendDeck = sendDeck

local function changed(p: Player)
	publicAttrs(p)
	sendDeck(p)
	-- (persist)
	local prof = Persist.Get(p)
	if prof then
		local out = {}
		local function pack(chip: Chip, slot: number)
			if chip.clip then
				return -- (videos are not saved)
			end
			table.insert(out, { id = chip.id, tier = chip.tier, slot = slot, payload = chip.payload, target = chip.target })
		end
		local st = stOf(p)
		for i, chip in st.slots do
			pack(chip, i)
		end
		for _, chip in st.bag do
			pack(chip, 0)
		end
		prof.chips = out
		Persist.Dirty(p)
	end
end

------------------------------------------------------------------------
-- making / giving chips
------------------------------------------------------------------------

local function newChip(id: string, tier: number, extra: any?): Chip
	local def = Chips.ById[id]
	local chip: Chip = {
		uid = nextUid(), id = id, kind = (def and def.kind) or (id == "virus" and "virus") or (id == "video" and "video") or "blank",
		tier = tier, name = def and def.name or (id == "virus" and "VIRUS" or "VIDEO"),
	}
	if extra then
		for k, v in extra do
			(chip :: any)[k] = v
		end
	end
	return chip
end

-- give a chip to a player's bag
function ChipService.Give(p: Player, id: string, tier: number, extra: any?): Chip
	local st = stOf(p)
	local chip = newChip(id, tier, extra)
	table.insert(st.bag, chip)
	changed(p)
	return chip
end

-- give a video chip (CameraService): a session-only chip that holds a clip
function ChipService.GiveVideo(p: Player, clipCode: string, label: string?): Chip
	return ChipService.Give(p, "video", 1, { clip = clipCode, name = label or "VIDEO", kind = "video" })
end

local function findBag(st: St, uid: number): (number?, Chip?)
	for i, chip in st.bag do
		if chip.uid == uid then
			return i, chip
		end
	end
	return nil, nil
end

------------------------------------------------------------------------
-- slots
------------------------------------------------------------------------

local SLOTTABLE = { combat = true, net = true, firewall = true, capacity = true, blank = true, blackwall = true, virus = true }

local function smite(p: Player)
	-- a non-admin slotted the Blackwall: the beam comes for them
	local char, torso = alive(p)
	if not char or not torso then
		return
	end
	ChipService.BlackwallBeam(torso.Position)
	task.delay(0.8, function()
		local c = p.Character
		local t = c and c:FindFirstChild("Torso")
		if c and t and not c:GetAttribute("Dead") then
			ChipService.Ash(c)
			c:SetAttribute("ForceKill", true)
			c:SetAttribute("NoRegrowth", true)
			c:SetAttribute("SpawnProtect", nil)
			deps.DamageService.Kill(c, "Burned by the Blackwall")
		end
	end)
end

function ChipService.Install(p: Player, uid: number, slot: number): string?
	if typeof(slot) ~= "number" or slot < 1 or slot > Config.ChipSlots then
		return "bad slot"
	end
	local st = stOf(p)
	if st.slots[slot] then
		return "that slot is full"
	end
	local i, chip = findBag(st, uid)
	if not chip then
		return "no such chip"
	end
	if not SLOTTABLE[chip.kind] then
		return "that chip does not go in a slot"
	end
	local def = Chips.ById[chip.id]
	if def and def.admin and not Items.IsOwner(p) and chip.id ~= "blackwall" then
		return "admins only"
	end
	table.remove(st.bag, i :: number)
	st.slots[slot] = chip
	if chip.id == "dodge" then
		st.dodgeLeft = chip.tier
	end
	changed(p)
	Remote:FireClient(p, "msg", (chip.name or "CHIP") .. " SLOTTED.")
	-- the Blackwall: an admin keeps it (the interface); anybody else is smitten
	if chip.id == "blackwall" and not Items.IsOwner(p) then
		Remote:FireClient(p, "msg", "THE BLACKWALL DOES NOT ANSWER TO YOU.")
		task.delay(0.4, smite, p)
	end
	return nil
end

function ChipService.Eject(p: Player, slot: number)
	local st = stOf(p)
	local chip = st.slots[slot]
	if not chip then
		return
	end
	st.slots[slot] = nil
	table.insert(st.bag, chip)
	if chip.id == "dodge" then
		st.dodgeLeft = 0
	end
	changed(p)
end

-- spawn a bag chip as a held item (and take it out of the bag)
function ChipService.Take(p: Player, uid: number)
	local st = stOf(p)
	local i, chip = findBag(st, uid)
	if not chip then
		return
	end
	local char, torso = alive(p)
	if not torso then
		return
	end
	local item = deps.PropService.Place("chip", torso.CFrame * CFrame.new(0, 0.5, -2), p)
	if not item or not item:IsA("Model") then
		return
	end
	ChipService.Dress(item, chip)
	item:SetAttribute("BoundTo", p.UserId) -- (yours: nobody else handles it)
	table.remove(st.bag, i :: number)
	changed(p)
	-- put it in the hand
	if item.PrimaryPart then
		pcall(deps.OwnershipService.Grab, p, item.PrimaryPart, "Right")
	end
end

-- write a chip onto a held item (attributes + colour)
function ChipService.Dress(item: Model, chip: Chip)
	item:SetAttribute("ChipUid", chip.uid)
	item:SetAttribute("ChipId", chip.id)
	item:SetAttribute("ChipKind", chip.kind)
	item:SetAttribute("ChipTier", chip.tier)
	item:SetAttribute("ChipName", chip.name)
	item:SetAttribute("ChipPayload", chip.payload)
	item:SetAttribute("ChipTarget", chip.target)
	item:SetAttribute("ChipClip", chip.clip)
	item:SetAttribute("ChipTrojan", chip.trojan == true or nil)
	item.Name = chip.name or "Chip"
	local core = item:FindFirstChild("Core")
	if core and core:IsA("BasePart") then
		local def = Chips.ById[chip.id]
		if chip.clip then
			core.Color = chip.trojan and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(120, 200, 255)
		elseif chip.id == "virus" then
			core.Color = Color3.fromRGB(120, 255, 120)
		elseif def then
			core.Color = Chips.Color(def)
		end
	end
end

-- read a chip back off a held item
local function chipOfItem(item: Model): Chip?
	local id = item:GetAttribute("ChipId")
	if typeof(id) ~= "string" then
		return nil
	end
	return {
		uid = typeof(item:GetAttribute("ChipUid")) == "number" and item:GetAttribute("ChipUid") or nextUid(),
		id = id, kind = typeof(item:GetAttribute("ChipKind")) == "string" and item:GetAttribute("ChipKind") or "blank",
		tier = typeof(item:GetAttribute("ChipTier")) == "number" and item:GetAttribute("ChipTier") or 1,
		name = item:GetAttribute("ChipName"), payload = item:GetAttribute("ChipPayload"),
		target = item:GetAttribute("ChipTarget"), clip = item:GetAttribute("ChipClip"), trojan = item:GetAttribute("ChipTrojan") == true,
	}
end

------------------------------------------------------------------------
-- buying / programming (ComputerService calls these; the player must be at a computer)
------------------------------------------------------------------------

local function atComputer(p: Player): boolean
	if Items.IsOwner(p) then
		return true
	end
	return ChipService.NearComputer ~= nil and ChipService.NearComputer(p) == true
end

local function cashOf(p: Player): number
	local c = p:GetAttribute("Cash")
	return typeof(c) == "number" and c or 0
end

local function pay(p: Player, n: number, why: string): boolean
	if n <= 0 or Items.IsOwner(p) then
		return true
	end
	if cashOf(p) < n then
		return false
	end
	if deps.SkinService and deps.SkinService.AddCash then
		deps.SkinService.AddCash(p, -n, why)
	end
	return true
end

local function say(p: Player, text: string)
	Remote:FireClient(p, "msg", text)
end

function ChipService.Buy(p: Player, id: any, tier: any)
	if not atComputer(p) then
		say(p, "GET TO A COMPUTER FIRST.")
		return
	end
	local def = typeof(id) == "string" and Chips.ById[id] or nil
	if not def or typeof(tier) ~= "number" then
		return
	end
	tier = math.clamp(math.floor(tier), 1, def.tiers)
	if def.admin and not Items.IsOwner(p) then
		say(p, "ADMINS ONLY.")
		return
	end
	local price = Chips.Price(id, tier)
	if not pay(p, price, "chip") then
		say(p, string.format("THAT IS $%d. YOU HAVE $%d.", price, cashOf(p)))
		return
	end
	ChipService.Give(p, id, tier)
	Remote:FireClient(p, "sound", "cashDing")
	say(p, (def.name .. " T" .. tier) .. " BOUGHT. IT IS IN YOUR CHIPS (K).")
end

function ChipService.Sell(p: Player, uid: any)
	if not atComputer(p) or typeof(uid) ~= "number" then return end
	local st = stOf(p)
	local i, chip = findBag(st, uid)
	if not chip or not i then return end
	local def = Chips.ById[chip.id]
	if not def or def.admin or chip.clip then say(p, "THIS CHIP CANNOT BE SOLD.") return end
	if Items.IsOwner(p) then say(p, "ADMIN CHIPS ARE FREE AND CANNOT BE SOLD.") return end
	local amount = math.floor(Chips.Price(chip.id, chip.tier) * 0.4)
	table.remove(st.bag, i)
	deps.SkinService.AddCash(p, amount, "chip sale")
	changed(p)
	Remote:FireClient(p, "sound", "cashDing")
	say(p, "SOLD " .. def.name .. " FOR $" .. amount)
end

-- program a blank chip (in the bag) into a virus
function ChipService.Program(p: Player, uid: any, payload: any, tier: any, target: any)
	if not atComputer(p) then
		say(p, "GET TO A COMPUTER FIRST.")
		return
	end
	local st = stOf(p)
	local i, chip = findBag(st, uid)
	if not chip or chip.kind ~= "blank" then
		say(p, "PICK A BLANK CHIP TO PROGRAM.")
		return
	end
	if not Chips.PayloadById[payload] then
		return
	end
	tier = math.clamp(typeof(tier) == "number" and math.floor(tier) or 1, 1, 3)
	if not pay(p, Config.VirusPrice, "virus") then
		say(p, string.format("A VIRUS IS $%d.", Config.VirusPrice))
		return
	end
	chip.id = "virus"
	chip.kind = "virus"
	chip.name = "VIRUS: " .. Chips.PayloadById[payload].name
	chip.tier = tier
	chip.payload = payload
	chip.target = (payload == "killtarget" and typeof(target) == "number") and target or nil
	changed(p)
	say(p, chip.name .. " (T" .. tier .. ") WRITTEN. INSERT IT INTO SOMEBODY, OR BAKE IT INTO A VIDEO.")
end

-- bake a virus chip into a video chip (a trojan): the video now carries the payload
function ChipService.MakeTrojan(p: Player, videoUid: any, virusUid: any)
	if not atComputer(p) then
		say(p, "GET TO A COMPUTER FIRST.")
		return
	end
	local st = stOf(p)
	local _, video = findBag(st, videoUid)
	local vi, virus = findBag(st, virusUid)
	if not video or not video.clip then
		say(p, "PICK A VIDEO.")
		return
	end
	if not virus or virus.kind ~= "virus" then
		say(p, "PICK A VIRUS CHIP.")
		return
	end
	video.payload = virus.payload
	video.target = virus.target
	video.tier = virus.tier
	video.trojan = true
	video.name = (video.name or "VIDEO") .. " [TROJAN]"
	table.remove(st.bag, vi :: number) -- (the virus chip is used up)
	changed(p)
	say(p, "THE VIDEO IS A TROJAN NOW. WHOEVER WATCHES IT GETS THE PAYLOAD.")
end

------------------------------------------------------------------------
-- the effects (quickhacks + virus payloads share this)
------------------------------------------------------------------------

local function fxTo(p: Player?, action: string, ...)
	if p then
		Remote:FireClient(p, action, ...)
	end
end

-- apply one effect to a body. `gate` = check the firewall; returns true if it landed.
function ChipService.Hit(victim: Model, effect: string, tier: number, attacker: Player?, gate: boolean): boolean
	if not victim or not victim.Parent or victim:GetAttribute("Dead") then
		return false
	end
	local vp = Players:GetPlayerFromCharacter(victim)
	-- Admin rank is not a firewall. Keep the game's spawn/team rules.
	if deps.DamageService.Protected(victim, attacker) then return false end
	if gate and vp then
		local fw = firewallOf(vp)
		if fw >= tier then
			if attacker then
				say(attacker, "BLOCKED - THEIR FIREWALL (T" .. fw .. ") HELD.")
			end
			fxTo(vp, "blocked")
			return false
		end
	end
	local torso = victim:FindFirstChild("Torso")
	local tpos = (torso and torso:IsA("BasePart")) and torso.Position or victim:GetPivot().Position
	local atkName = attacker and attacker.DisplayName or "a netrunner"

	if effect == "burnout" then
		deps.DamageService.ApplyDamage(victim, "Torso", 25 + 20 * tier, tpos, { cause = "Burned out by " .. atkName, allowSever = false, cyberAttack = true, attacker = attacker })
		deps.GoreService.FX({ t = "burst", p = tpos, d = Vector3.yAxis, n = 8, s = 14 })
		deps.GoreService.Sound("taser", torso or tpos, 1)
		if tier >= 2 then
			deps.DamageService.Knock(victim, "Torso", nil, tier >= 3 and 2.2 or 1.1)
		end
		if tier >= 3 and vp then
			vp.Character:SetAttribute("ChipsDisabled", workspace:GetServerTimeNow() + 5)
		end
	elseif effect == "overheat" then
		deps.FireService.SetOnFire(victim, 3 + 3 * tier, attacker)
		-- Cybernetic heat also affects admin invulnerability; physical fire retains its own rules.
		if victim:GetAttribute("God") then
			task.spawn(function()
				for _ = 1, 3 + 3 * tier do
					task.wait(1)
					if not victim.Parent or victim:GetAttribute("Dead") then break end
					deps.DamageService.ApplyDamage(victim, "Torso", 5 + tier * 2, nil, { cause = "Neural overheat", cyberAttack = true, allowSever = false, attacker = attacker })
				end
			end)
		end
		deps.GoreService.Sound("ignite", torso or tpos, 1)
	elseif effect == "emp" then
		local dur = 4 * tier
		if vp and vp.Character then
			vp.Character:SetAttribute("ChipsDisabled", workspace:GetServerTimeNow() + dur)
		end
		deps.GoreService.FX({ t = "shock", p = tpos, r = 5 })
		deps.GoreService.Sound("taser", torso or tpos, 1)
		deps.DamageService.ApplyDamage(victim, "Torso", 6 * tier, tpos, { cause = "EMP by " .. atkName, allowSever = false, cyberAttack = true, attacker = attacker })
		if tier >= 3 then
			deps.DamageService.Knock(victim, "Torso", nil, 1.6)
		end
		fxTo(vp, "emp", dur)
	elseif effect == "blind" then
		fxTo(vp, "blind", ({ 3, 5, 8 })[math.clamp(tier, 1, 3)])
	elseif effect == "contagion" then
		if deps.VirusService then
			deps.VirusService.Infect(victim, attacker, true)
			deps.DamageService.ApplyDamage(victim, "Torso", 4 * tier, tpos, { cause = "Contagion", allowSever = false, quiet = true, cyberAttack = true, attacker = attacker })
		end
	elseif effect == "psycho" or effect == "rampage" or effect == "killtarget" then
		local dur = ({ 6, 9, 13 })[math.clamp(tier, 1, 3)]
		local targetUserId = nil
		if effect == "killtarget" then
			targetUserId = attacker and attacker.UserId or nil -- (set by the caller via opts normally)
		end
		fxTo(vp, "rampage", dur, targetUserId)
		if not vp then
			-- an NPC / bot: turn it hostile where it stands (best-effort)
			victim:SetAttribute("Rampage", workspace:GetServerTimeNow() + dur)
		end
	elseif effect == "reset" then
		local dur = ({ 6, 9, 13 })[math.clamp(tier, 1, 3)]
		deps.DamageService.Sleep(victim, dur, attacker, true)
		deps.GoreService.Sound("ringing", torso or tpos, 1)
	elseif effect == "glitch" then
		if vp then
			for _, it in deps.OwnershipService.HeldItems(vp) do
				pcall(deps.OwnershipService.DropItem, it)
			end
			if vp.Character then
				vp.Character:SetAttribute("ChipGrabLock", workspace:GetServerTimeNow() + ({ 0, 3, 6 })[math.clamp(tier, 1, 3)])
			end
			fxTo(vp, "glitch")
		end
	elseif effect == "cripple" then
		if vp and vp.Character then
			vp.Character:SetAttribute("ChipCrawl", ({ 0.4, 0.28, 0.18 })[math.clamp(tier, 1, 3)])
			vp.Character:SetAttribute("ChipCrawlUntil", workspace:GetServerTimeNow() + ({ 4, 6, 8 })[math.clamp(tier, 1, 3)])
		end
		deps.GoreService.FX({ t = "shock", p = tpos, r = 3 })
	elseif effect == "explode" then
		deps.ExplosionService.Explode(tpos, { radius = 14 + 4 * tier, damage = 80 + 30 * tier, power = 60, attacker = attacker, cause = "A planted virus", kind = "grenade" })
	elseif effect == "hallucinate" then
		fxTo(vp, "hallucinate", 10 + 10 * tier)
	end
	return true
end

------------------------------------------------------------------------
-- running a quickhack (the netrunner interface)
------------------------------------------------------------------------

local cd: { [Player]: { [number]: number } } = {}

local EFFECT = {
	burnout = "burnout", overheat = "overheat", shortcircuit = "emp", reboot = "blind", contagion = "contagion",
	cyberpsycho = "psycho", sysreset = "reset", weaponglitch = "glitch", cripple = "cripple",
}

local function linked(p: Player, victim: Model): boolean
	local char, root = alive(p)
	if char and (char:GetAttribute("TemporalFrozenUntil") or 0) > workspace:GetServerTimeNow() then return false end
	local target = victim:FindFirstChild("Head") or victim:FindFirstChild("Torso")
	if not root or not target or not target:IsA("BasePart") or victim == char or victim:GetAttribute("Dead") then return false end
	if (target.Position - root.Position).Magnitude > Config.NetRange then return false end
	local head = char:FindFirstChild("Head") or root
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { char, workspace:FindFirstChild("FX") or char }
	local hit = workspace:Raycast(head.Position, target.Position - head.Position, rp)
	return not hit or hit.Instance:IsDescendantOf(victim)
end

local function victimOf(userId: any): Model?
	local p = typeof(userId) == "number" and Players:GetPlayerByUserId(userId) or nil
	return p and p.Character or nil
end

function ChipService.Quickhack(p: Player, slot: any, targetUserId: any)
	local st = stOf(p)
	local chip = typeof(slot) == "number" and st.slots[slot] or nil
	if not chip or chip.kind ~= "net" then
		return
	end
	local c = p.Character
	if c and typeof(c:GetAttribute("ChipsDisabled")) == "number" and workspace:GetServerTimeNow() < c:GetAttribute("ChipsDisabled") then
		say(p, "YOUR CHIPS ARE FRIED - WAIT.")
		return
	end
	local def = Chips.ById[chip.id]
	local now = os.clock()
	cd[p] = cd[p] or {}
	if now < (cd[p][slot] or 0) then
		return
	end
	local victim = victimOf(targetUserId)
	local vp = typeof(targetUserId) == "number" and Players:GetPlayerByUserId(targetUserId) or nil
	local _, mytorso = alive(p)
	local vt = victim and victim:FindFirstChild("Torso")
	if not victim or not vt or not vt:IsA("BasePart") or not mytorso or vp == p then
		say(p, "NO TARGET.")
		return
	end
	if (vt.Position - mytorso.Position).Magnitude > Config.NetRange then
		say(p, "TARGET OUT OF RANGE.")
		return
	end
	if not linked(p, victim) then say(p, "LINK LOST — TARGET OCCLUDED.") return end
	local effect = EFFECT[chip.id]
	if not effect then
		return
	end
	cd[p][slot] = now + (def.cooldown and def.cooldown[chip.tier] or 12)
	p:SetAttribute("ChipCD_" .. slot, workspace:GetServerTimeNow() + (def.cooldown and def.cooldown[chip.tier] or 12))
	-- the uplink line shown to everybody
	Remote:FireAllClients("uplink", p.UserId, targetUserId, Chips.Color(def))
	local landed = ChipService.Hit(victim, effect, chip.tier, p, true)
	if landed then
		say(p, def.ability .. " ON " .. string.upper(vp and vp.DisplayName or "TARGET"))
	end
end

------------------------------------------------------------------------
-- the Blackwall
------------------------------------------------------------------------

function ChipService.BlackwallBeam(pos: Vector3)
	Remote:FireAllClients("blackwall", pos)
end

-- turn a body to ash (FX; the kill is done by the caller)
function ChipService.Ash(victim: Model)
	local torso = victim:FindFirstChild("Torso")
	local p = (torso and torso:IsA("BasePart")) and torso.Position or victim:GetPivot().Position
	Remote:FireAllClients("ash", victim, p)
end

function ChipService.Unleash(p: Player, slot: any, targetUserId: any)
	local st = stOf(p)
	local chip = typeof(slot) == "number" and st.slots[slot] or nil
	if not chip or chip.id ~= "blackwall" or not Items.IsOwner(p) then
		return
	end
	local now = os.clock()
	cd[p] = cd[p] or {}
	if now < (cd[p]["bw"] or 0) then
		return
	end
	local victim = victimOf(targetUserId)
	local vt = victim and victim:FindFirstChild("Torso")
	if not victim or not vt or not vt:IsA("BasePart") then
		return
	end
	if not linked(p, victim) then say(p, "NO CLEAR LINK TO TARGET.") return end
	local char = p.Character
	local off = char and char:GetAttribute("ChipsDisabled")
	if typeof(off) == "number" and off > workspace:GetServerTimeNow() then return end
	cd[p]["bw"] = now + 20
	p:SetAttribute("ChipCD_" .. slot, workspace:GetServerTimeNow() + 20)
	ChipService.BlackwallBeam(vt.Position)
	Remote:FireClient(p, "msg", "BLACKWALL RELEASED.")
	task.delay(0.8, function()
		if victim.Parent and not victim:GetAttribute("Dead") then
			ChipService.Ash(victim)
			victim:SetAttribute("ForceKill", true)
			victim:SetAttribute("NoRegrowth", true)
			deps.DamageService.MarkAttacker(victim, p)
			deps.DamageService.Kill(victim, "Erased by the Blackwall")
		end
	end)
end

------------------------------------------------------------------------
-- held chips: play a video / push a chip into somebody
------------------------------------------------------------------------

local function returnChipToBag(p: Player, item: Model, chip: Chip)
	-- the chip goes back into the bag (not consumed)
	if item.Parent then
		pcall(deps.OwnershipService.DropItem, item)
		item:Destroy()
	end
	local st = stOf(p)
	table.insert(st.bag, chip)
	changed(p)
end

-- F with a chip in hand, nobody grabbed: play its video for yourself
function ChipService.PlayHeld(p: Player, item: Model)
	if deps.OwnershipService.ItemHolder(item) ~= p then
		return
	end
	local chip = chipOfItem(item)
	if not chip then
		return
	end
	if not chip.clip then
		say(p, "THIS CHIP HAS NO VIDEO.")
		return
	end
	if ChipService.Camera then
		ChipService.Camera.Play(p, chip.clip, chip.trojan and chip or nil, p)
	end
end

-- grab somebody + F with a chip in the other hand: push it into them
function ChipService.InsertHeld(p: Player, item: Model)
	if deps.OwnershipService.ItemHolder(item) ~= p then
		return
	end
	local chip = chipOfItem(item)
	if not chip then
		return
	end
	local victim = deps.OwnershipService.HeldBody(p)
	local vp = victim and Players:GetPlayerFromCharacter(victim)
	if not victim or not vp then
		say(p, "GRAB SOMEBODY FIRST (Q / E).")
		return
	end
	-- the chip is used up going in
	if item.Parent then
		pcall(deps.OwnershipService.DropItem, item)
		item:Destroy()
	end
	deps.GoreService.Sound("ratchet", victim:FindFirstChild("Torso"), 1)
	say(p, "CHIP PUSHED INTO " .. string.upper(vp.DisplayName) .. ".")
	if chip.clip then
		-- a video: they watch it; a trojan sets its payload off at the end (if their firewall is too low)
		if ChipService.Camera then
			ChipService.Camera.Play(vp, chip.clip, chip.trojan and chip or nil, p)
		end
	elseif chip.kind == "virus" and chip.payload then
		ChipService.FirePayload(victim, chip, p)
	end
end

-- a virus payload fires on a victim (from a direct insert, or a trojan video ending)
function ChipService.FirePayload(victim: Model, chip: Chip, attacker: Player?)
	local payload = chip.payload
	if not payload then
		return
	end
	local effect = payload
	if payload == "rampage" then
		effect = "psycho"
	end
	local landed
	if payload == "killtarget" then
		-- they go after the attacker (or the stored target)
		local vp = Players:GetPlayerFromCharacter(victim)
		local target = chip.target or (attacker and attacker.UserId) or nil
		if vp and firewallOf(vp) < chip.tier then
			Remote:FireClient(vp, "rampage", 14, target)
			landed = true
		end
	else
		landed = ChipService.Hit(victim, effect, chip.tier, attacker, true)
	end
	if landed and attacker then
		say(attacker, "PAYLOAD DELIVERED.")
	end
end

------------------------------------------------------------------------
-- REFLEX BUFFER: the bullet dodge (chained onto DamageService.ShieldBullet)
------------------------------------------------------------------------

local function dodgeTier(p: Player): number
	local st = states[p]
	if not st then
		return 0
	end
	local c = p.Character
	if c and typeof(c:GetAttribute("ChipsDisabled")) == "number" and workspace:GetServerTimeNow() < c:GetAttribute("ChipsDisabled") then
		return 0
	end
	for _, chip in st.slots do
		if chip.id == "dodge" then
			return chip.tier
		end
	end
	return 0
end

local function tryDodge(model: Model, point: Vector3, dir: Vector3): boolean
	local p = Players:GetPlayerFromCharacter(model)
	if not p then
		return false
	end
	local st = states[p]
	local t = dodgeTier(p)
	if not st or t <= 0 or st.dodgeLeft <= 0 then
		return false
	end
	st.dodgeLeft -= 1
	if st.dodgeLeft <= 0 then
		st.dodgeRefill = os.clock() + 20
	end
	p:SetAttribute("ChipDodge", st.dodgeLeft > 0 and st.dodgeLeft or nil)
	Remote:FireClient(p, "dodge")
	-- tier 3 also nudges the body aside
	if t >= 3 then
		local torso = model:FindFirstChild("Torso")
		if torso and torso:IsA("BasePart") then
			local side = dir:Cross(Vector3.yAxis)
			if side.Magnitude > 0.1 then
				side = side.Unit * (rng:NextNumber() < 0.5 and 1 or -1)
				pcall(function()
					torso:ApplyImpulse(side * 22 * torso.AssemblyMass)
				end)
			end
		end
	end
	local _ = point
	return true
end

------------------------------------------------------------------------

function ChipService.Init(d: any)
	deps = d
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	Remote = Remotes:FindFirstChild("Chip") :: RemoteEvent
	if not Remote then
		local r = Instance.new("RemoteEvent")
		r.Name = "Chip"
		r.Parent = Remotes
		Remote = r
	end
	ChipService.Remote = Remote

	-- the dodge sits in front of whatever else shields a bullet
	local prevBullet = deps.DamageService.ShieldBullet
	deps.DamageService.ShieldBullet = function(model, region, point, dir, shooter, kind)
		if tryDodge(model, point, dir) then
			return true
		end
		return prevBullet ~= nil and prevBullet(model, region, point, dir, shooter, kind) or false
	end

	local requests = {}
	Remote.OnServerEvent:Connect(function(p, action, a, b, c, dd)
		if typeof(action) ~= "string" then return end
		local t = os.clock()
		local r = requests[p]
		if not r or t - r.t > 1 then r = { t = t, n = 0 }; requests[p] = r end
		r.n += 1
		if r.n > 16 then return end
		for _, v in { a, b, c, dd } do
			if typeof(v) == "number" and (v ~= v or math.abs(v) == math.huge) then return end
		end
		if action == "deck" then
			sendDeck(p)
		elseif action == "install" then
			local why = ChipService.Install(p, a, b)
			if why then
				say(p, string.upper(why))
			end
		elseif action == "eject" then
			ChipService.Eject(p, a)
		elseif action == "take" then
			ChipService.Take(p, a)
		elseif action == "hack" then
			ChipService.Quickhack(p, a, b)
		elseif action == "blackwall" then
			ChipService.Unleash(p, a, b)
		elseif action == "play" then
			if typeof(a) == "Instance" and a:IsA("Model") then
				ChipService.PlayHeld(p, a)
			end
		elseif action == "insert" then
			if typeof(a) == "Instance" and a:IsA("Model") then
				ChipService.InsertHeld(p, a)
			end
		elseif action == "buy" then
			ChipService.Buy(p, a, b)
		elseif action == "sell" then
			ChipService.Sell(p, a)
		elseif action == "program" then
			ChipService.Program(p, a, b, c, dd)
		elseif action == "trojan" then
			ChipService.MakeTrojan(p, a, b)
		end
	end)

	-- the profile: chips come back
	local prevLoaded = Persist.OnLoaded
	Persist.OnLoaded = function(p, prof)
		if prevLoaded then
			prevLoaded(p, prof)
		end
		local st = stOf(p)
		if typeof(prof.chips) == "table" then
			for _, rec in prof.chips do
				if typeof(rec) == "table" and typeof(rec.id) == "string" and (Chips.ById[rec.id] or rec.id == "virus") then
					local chip = newChip(rec.id, typeof(rec.tier) == "number" and rec.tier or 1, { payload = rec.payload, target = rec.target })
					local slot = typeof(rec.slot) == "number" and rec.slot or 0
					if slot >= 1 and slot <= Config.ChipSlots and not st.slots[slot] and SLOTTABLE[chip.kind] then
						st.slots[slot] = chip
						if chip.id == "dodge" then
							st.dodgeLeft = chip.tier
						end
					else
						table.insert(st.bag, chip)
					end
				end
			end
		end
		publicAttrs(p)
		sendDeck(p)
	end

	Players.PlayerAdded:Connect(function(p)
		stOf(p)
	end)
	for _, p in Players:GetPlayers() do
		stOf(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		requests[p] = nil
		states[p] = nil
		cd[p] = nil
	end)

	-- refill dodge charges, grab-lock expiry
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = os.clock()
			for p, st in states do
				if not p.Parent then
					continue
				end
				local t = dodgeTier(p)
				if t > 0 and st.dodgeLeft <= 0 and now >= st.dodgeRefill then
					st.dodgeLeft = t
					p:SetAttribute("ChipDodge", t)
				end
			end
		end
	end)
end

-- (v2.9) wipe one player's chips (the admin "WIPE ALL PROGRESS")
function ChipService.Reset(p: Player)
	states[p] = { slots = {}, bag = {}, dodgeLeft = 0, dodgeRefill = 0 }
	p:SetAttribute("ChipFirewall", nil)
	p:SetAttribute("CyTolBonus", nil)
	p:SetAttribute("ChipDodge", nil)
	local prof = Persist.Get(p)
	if prof then
		prof.chips = {}
		Persist.Dirty(p)
	end
	publicAttrs(p)
	sendDeck(p)
end

return ChipService
