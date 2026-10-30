--!nonstrict
-- NPCService: hostile NPCs (spawn menu, BODIES): a gunman with a random gun or a brawler with a
-- random melee weapon. They are active ragdolls like the players (same rig, muscles, balance,
-- hover spring), simulated by the server:
--   * pathfinding to the nearest player (PathfindingService), jumping where the path says so
--   * gunmen keep their distance, look for cover (something solid between them and you, low
--     enough to shoot over or around), crouch behind it and pop up to shoot
--   * brawlers rush you and swing
--   * hits knock them over (they go limp, then get up again); with a broken / missing leg they
--     crawl on their belly; somebody holding them (hand or physics gun) = limp
--   * on death they drop the weapon (you can pick it up)
--   * the weapon is held in a hand: break or cut off that arm and it falls. With the other arm
--     still working they sprint to the nearest weapon lying around (also the one they dropped)
--     and pick it up. No working arm, no weapon anywhere near, or nearly dead: they run away
--   * they sprint to cover, to weapons and when far away; brawlers leap at you from a few
--     metres, crawlers lunge forward on their arms
--   * gunmen really reload: the gun comes in front of the chest, the other hand changes the
--     magazine (slower with one arm), they duck while doing it

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TimeScale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TimeScale")) -- (v2.8) the Sandevistan's slow motion
local RigInfo = require(Shared:WaitForChild("RigInfo"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local Items = require(Shared:WaitForChild("Items"))
local Water = require(Shared:WaitForChild("Water"))

local Modules = script.Parent
local RigBuilder = require(Modules:WaitForChild("RigBuilder"))
local BodyFactory = require(Modules:WaitForChild("BodyFactory"))
local DamageService = require(Modules:WaitForChild("DamageService"))
local ServerImpactSensor = require(Modules:WaitForChild("ServerImpactSensor"))
local PropBuilders = require(Modules:WaitForChild("PropBuilders"))
local GunService = require(Modules:WaitForChild("GunService"))
local GoreService = require(Modules:WaitForChild("GoreService"))
local OwnershipService = require(Modules:WaitForChild("OwnershipService"))

local NPCService = {}
NPCService.OnCyber = nil :: ((Model, any) -> ())? -- (v2.8) a chromed merc was spawned (CyberService gives it cyberware)
NPCService.OnThink = nil :: ((any) -> ())? -- (v2.8) every think of every NPC

-- (v2.0) bots in game modes: who may this NPC go for? (nil = players only, like the sandbox hostiles)
NPCService.CanTarget = nil :: ((Model, Model) -> boolean)?
-- more bodies it may go for besides the players (other bots, the Crawler ...)
NPCService.ExtraTargets = nil :: (() -> { Model })?
-- (v2.0) GameModeService: where a mode bot has to be. nil = fight as usual; otherwise a table:
--   { kind = "chase", target = Model }  go for this one wherever it is (the sniper on its tower)
--   { kind = "tag", target = Model }    run into them, no fighting (hot potato: the bomb passes on touch)
--   { kind = "flee", from = Model }     keep away from them (the bomb's holder); far away it wanders
--   { kind = "idle" }                   wander about
--   { kind = "goto", pos = Vector3, radius = number }  get there (shooting on the way), then fight from there
NPCService.ModeGoal = nil :: ((Model) -> any)?
-- a zombie bot got its teeth into somebody
NPCService.OnZombieBite = nil :: ((Model, Model) -> ())?
-- (v2.0, set by Main) a bot throws a steel ball / fires a rocket, a lock-on missile or a flare
NPCService.OnBotThrow = nil :: ((Model, Vector3, Vector3) -> ())?
NPCService.OnBotProjectile = nil :: ((Model, Model, string, Vector3, Vector3, Model?) -> ())?

local GUNS = { "pistol", "revolver", "rifle", "smg", "shotgun", "sniper", "usp", "mp5", "garand" }
local MELEE = { "blade", "katana", "axe", "bat", "sledge", "spear" }
-- (v2.0) what a bot also picks up and knows how to use (the spawn weapons stay the ones above)
local EXTRA_USABLE = { "steelball", "crossbow", "machete", "knife", "chainsaw", "taser", "harpoon", "flaregun", "sleepdart", "minigun" }

-- (v2.0) how a bot uses an item: "gun" (Config.Guns - bullets, darts, the taser, the harpoon, rockets and flares
-- through NPCService.OnBotProjectile), "throw" (steel balls), "melee" (everything else)
local function useKind(kind: string): string
	if Config.Guns[kind] then
		return "gun"
	elseif kind == "steelball" then
		return "throw"
	end
	return "melee"
end
local DOWN = Vector3.new(0, -1, 0)
local PRONE_ROT = CFrame.Angles(-math.pi / 2, 0, 0)
local rng = Random.new()

type Limb = { part: BasePart, def: any, muscle: AlignOrientation?, target: Attachment?, collider: BasePart? }
type NPC = {
	model: Model,
	kind: string, -- "gun" | "melee" (what it fights with right now)
	weaponKind: string,
	weapon: Model?,
	weld: Instance?,
	weaponSide: string, -- "Right" | "Left"
	wantWeapon: Model?,
	fleeing: boolean,
	reloading: boolean,
	leapT0: number,
	nextGroan: number?,
	leapHit: boolean,
	nextLeap: number,
	nextCrawlLeap: number,
	blindUntil: number,
	torso: BasePart,
	head: BasePart,
	limbs: { [string]: Limb },
	balance: AlignOrientation?,
	drive: VectorForce?,
	mass: number,
	state: string, -- "Active" | "Ragdoll" | "GettingUp" | "Dead"
	ragdollUntil: number,
	getUp: number,
	crawling: boolean,
	crouch: boolean,
	phase: number,
	moveDir: Vector3,
	moveSpeed: number,
	face: Vector3,
	aimAt: Vector3?,
	target: Model?,
	seenSince: number,
	lastSeen: number,
	path: { PathWaypoint }?,
	pathIndex: number,
	pathGoal: Vector3?,
	pathAt: number,
	computing: boolean,
	cover: Vector3?,
	coverUntil: number,
	peekUntil: number,
	nextCover: number,
	ammo: number,
	reloadUntil: number,
	nextShot: number,
	burst: number,
	swingT0: number,
	swingHit: boolean,
	nextThink: number,
	lastHP: number,
	stuckRef: Vector3?,
	holdPos: Vector3?, -- (v2.0) a game mode spot it keeps to (king of the hill)
	stuckT: number,
	jumpLock: number,
	airTime: number,
	strafe: number,
	strafeUntil: number,
	spawner: number?,
	rayParams: RaycastParams,
	ownerCheck: number?,
	zombie: boolean?,
	bot: boolean?,
	civilian: boolean?, -- (v2.0) a bot driver: never fights, walks away from trouble
	boxer: boolean?, -- (v2.0) the spawnable boxer: no weapon, comes at you with its fists
	standup: boolean?, -- (v2.0) the stand-up dummy: never attacks, always gets back up, faces you with its guard up
	punchSide: number?,
	seated: boolean?, -- (v2.0) sits in a car (the car carries it, no balance / walking)
	scaredUntil: number?,
}

local npcs: { [Model]: NPC } = {}

local function folder(): Folder
	local f = workspace:FindFirstChild("NPCs")
	if not f then
		f = Instance.new("Folder")
		f.Name = "NPCs"
		f.Parent = workspace
	end
	return f :: Folder
end

local function propFolder(): Instance
	return workspace:FindFirstChild("SpawnedProps") or workspace
end

local function totalHP(model: Model): number
	local hp = 0
	for _, r in RigInfo.Regions do
		local v = model:GetAttribute("HP_" .. r)
		hp += math.max(0, typeof(v) == "number" and v or 100)
	end
	return hp
end

local function legOK(model: Model, key: string): boolean
	return not model:GetAttribute("Severed_" .. key) and not model:GetAttribute("Broken_" .. key)
end

------------------------------------------------------------------------
-- weapon in the right hand (welded like a player's item, nobody else can take it)
------------------------------------------------------------------------

local function armUsable(npc: NPC, side: string): boolean
	local key = side == "Left" and "LeftArm" or "RightArm"
	return not npc.model:GetAttribute("Severed_" .. key) and not npc.model:GetAttribute("Broken_" .. key) and npc.limbs[key] ~= nil
end

-- weld an item into a hand (nobody else can take it while the NPC holds it)
local function equip(npc: NPC, item: Model, side: string): boolean
	local key = side == "Left" and "LeftArm" or "RightArm"
	local hand = npc.limbs[key] and npc.limbs[key].part
	local handle = item.PrimaryPart
	local grip = handle and handle:FindFirstChild("GripAttachment")
	if not hand or not handle or not grip or not grip:IsA("Attachment") then
		return false
	end
	item:SetAttribute("HolderId", -1)
	item:SetAttribute("NPCHeld", true)
	item:SetAttribute("Stuck", nil)
	local att = Instance.new("Attachment")
	att.Name = "ItemHandServer"
	att.CFrame = RigInfo.GunHandCFrame
	att.Parent = hand
	local weld = Instance.new("RigidConstraint")
	weld.Name = "ItemWeld"
	weld.Attachment0 = att
	weld.Attachment1 = grip
	for _, ip in item:GetDescendants() do
		if ip:IsA("BasePart") then
			ip.Massless = true
			for _, bp in npc.model:GetDescendants() do
				if bp:IsA("BasePart") and (bp.CanCollide or bp.Name == "Collider") then
					local nc = Instance.new("NoCollisionConstraint")
					nc.Part0 = ip
					nc.Part1 = bp
					nc.Parent = weld
				end
			end
		end
	end
	weld.Parent = handle
	-- move it to the hand first (the constraint keeps it there)
	item:PivotTo((hand.CFrame * RigInfo.GunHandCFrame) * (handle.CFrame * grip.CFrame):Inverse() * item:GetPivot())
	if item.Parent ~= propFolder() then
		item.Parent = propFolder()
	end
	for _, d in item:GetDescendants() do
		if d:IsA("BasePart") and not d.Anchored then
			pcall(function()
				d:SetNetworkOwner(nil)
			end)
		end
	end
	local kind = Items.Kind(item) or "bat"
	npc.weapon = item
	npc.weld = weld
	npc.weaponKind = kind
	npc.weaponSide = side
	npc.kind = useKind(kind)
	if kind == "chainsaw" then
		item:SetAttribute("SawOn", true) -- (a bot's chainsaw always runs)
	end
	local stats = Config.Guns[kind]
	if stats then
		local a = item:GetAttribute("Ammo")
		npc.ammo = typeof(a) == "number" and a or stats.mag
	end
	npc.reloading = false
	npc.reloadUntil = 0
	return true
end

-- the spawn weapon: built in the right hand
local function arm(npc: NPC)
	local builder = PropBuilders[npc.weaponKind]
	local hand = npc.limbs.RightArm and npc.limbs.RightArm.part
	if not builder or not hand then
		return
	end
	local item = builder(hand.CFrame * RigInfo.GunHandCFrame)
	if not equip(npc, item, "Right") then
		item:Destroy()
	end
end

local function dropWeapon(npc: NPC, fling: boolean?)
	local item = npc.weapon
	if not item then
		return
	end
	-- (v2.8.1) the Pale Heir never lets go of her blade (nobody picks STILLWATER up before she is beaten; it is gone with her)
	if item:GetAttribute("RivalBlade") then
		return
	end
	npc.weapon = nil
	npc.reloading = false
	if npc.weld then
		local att = npc.weld:IsA("RigidConstraint") and npc.weld.Attachment0
		npc.weld:Destroy()
		if att then
			att:Destroy()
		end
		npc.weld = nil
	end
	if not item.Parent then
		return
	end
	item:SetAttribute("HolderId", nil)
	item:SetAttribute("NPCHeld", nil)
	item:SetAttribute("SawOn", nil)
	for _, p in item:GetDescendants() do
		if p:IsA("BasePart") then
			p.Massless = false
		end
	end
	local stats = Config.Guns[npc.weaponKind]
	if stats then
		item:SetAttribute("Ammo", math.max(0, npc.ammo))
	end
	if fling and item.PrimaryPart then
		pcall(function()
			item.PrimaryPart:ApplyImpulse((npc.face * 6 + Vector3.new(0, 8, 0)) * item.PrimaryPart.AssemblyMass)
		end)
	end
end

-- weapons an NPC can use (guns it can fire with a hitscan shot, melee weapons)
local USABLE: { [string]: boolean } = {}
for _, k in GUNS do
	USABLE[k] = true
end
for _, k in MELEE do
	USABLE[k] = true
end
for _, k in EXTRA_USABLE do
	USABLE[k] = true
end

local claimed: { [Model]: Model } = {} -- weapon -> the NPC going for it

-- the nearest weapon lying around that nobody holds
local function findWeapon(npc: NPC): Model?
	local pos = npc.torso.Position
	local best, bestD = nil, Config.NPCWeaponSearch
	for _, folderName in { "SpawnedProps", "Map" } do
		local f = workspace:FindFirstChild(folderName)
		if not f then
			continue
		end
		for _, m in f:GetChildren() do
			if not m:IsA("Model") or not m.PrimaryPart then
				continue
			end
			local k = Items.Kind(m)
			if not k or not USABLE[k] or m:GetAttribute("HolderId") or m:GetAttribute("Stuck") or Items.IsOwnerOnly(m) or m:GetAttribute("BoundTo") then
				continue
			end
			local c = claimed[m]
			if c and c ~= npc.model and c.Parent then
				continue
			end
			local d = (m.PrimaryPart.Position - pos).Magnitude
			if d < bestD then
				best, bestD = m, d
			end
		end
	end
	return best
end

------------------------------------------------------------------------
-- spawn / remove
------------------------------------------------------------------------

-- opts (v2.0, game mode bots): weapon = item id, zombie = true (no weapon, bites), team = "Red" / "Blue" / ...,
-- name = what it is called, bot = true (a mode bot: it goes for whoever NPCService.CanTarget allows),
-- civilian = true (a bot driver: no weapon, never fights), colors = { Head, Torso, Arms, Legs }
local zombieNo = 0
function NPCService.Spawn(kind: string, cf: CFrame, spawner: Player?, opts: any?): Model?
	opts = opts or {}
	local o: any = opts
	-- (v2.8) a chromed merc: a gunman with random cyberware (CyberService.chromeNPC)
	local chromed = kind == "cyber"
	if chromed then
		o.name = o.name or "Chromed Merc"
		o.colors = o.colors or { Head = Color3.fromRGB(196, 150, 118), Torso = Color3.fromRGB(24, 26, 30), Arms = Color3.fromRGB(196, 150, 118), Legs = Color3.fromRGB(30, 30, 36) }
	end
	-- (v2.0) two more kinds from the spawn menu: the boxer (fists) and the stand-up dummy
	if kind == "boxer" then
		o.boxer = true
		o.colors = o.colors or { Head = Color3.fromRGB(204, 160, 130), Torso = Color3.fromRGB(196, 40, 40), Arms = Color3.fromRGB(204, 160, 130), Legs = Color3.fromRGB(36, 36, 44) }
		o.name = o.name or "Hostile Boxer"
	elseif kind == "standup" then
		o.standup = true
		o.colors = o.colors or { Head = Color3.fromRGB(214, 190, 150), Torso = Color3.fromRGB(196, 168, 120), Arms = Color3.fromRGB(214, 190, 150), Legs = Color3.fromRGB(150, 126, 90) }
		o.name = o.name or "Stand-up Dummy"
	end
	kind = kind == "melee" and "melee" or "gun"
	if opts.boxer or opts.standup then
		kind = "melee"
	end
	if opts.weapon then
		kind = Config.Guns[opts.weapon] and "gun" or "melee"
	end
	-- caps: oldest go first
	if spawner then
		local mine = {}
		for m, n in npcs do
			if n.spawner == spawner.UserId then
				table.insert(mine, m)
			end
		end
		if #mine >= Config.NPCMaxPerPlayer then
			mine[1]:Destroy()
		end
	end
	-- (v2.0) mode bots have their own budget: a sandbox spawn never removes a mode bot, and a mode bot
	-- only pushes out sandbox NPCs once the total gets too high
	local loose, total = {}, 0
	for m in npcs do
		if m:GetAttribute("Hellborn") then
			continue -- (v2.8) the Pit's own (the Hollows, the Pale Heir) have a budget of their own
		end
		total += 1
		if not m:GetAttribute("Bot") then
			table.insert(loose, m)
		end
	end
	if opts.hellborn then
		-- (nothing up here makes room for them)
	elseif opts.bot then
		if total >= Config.NPCMax + Config.ModeBotFill and loose[1] then
			loose[1]:Destroy()
		end
	elseif #loose >= Config.NPCMax then
		loose[1]:Destroy()
	end
	local colors = {
		Head = Color3.fromRGB(204, 160, 130),
		Torso = kind == "gun" and Color3.fromRGB(56, 62, 50) or Color3.fromRGB(120, 30, 30),
		Arms = Color3.fromRGB(204, 160, 130),
		Legs = Color3.fromRGB(40, 40, 46),
	}
	if opts.team == "Red" then
		colors.Torso = Color3.fromRGB(176, 44, 40)
	elseif opts.team == "Blue" then
		colors.Torso = Color3.fromRGB(40, 84, 176)
	end
	if opts.zombie then
		colors = { Head = Config.ZombieColor, Torso = Color3.fromRGB(70, 64, 52), Arms = Config.ZombieColor, Legs = Color3.fromRGB(46, 44, 40) }
	end
	if opts.colors then
		colors = opts.colors
	end
	local defaultName = kind == "gun" and "Hostile Gunman" or "Hostile Brawler"
	local model = BodyFactory.BuildR6({ name = opts.name or (opts.zombie and "Zombie" or defaultName), humanoid = false, colors = colors })
	RigBuilder.Build(model, { colliders = true, muscles = true })
	model:SetAttribute("IsNPC", true)
	model:SetAttribute("Hostile", not opts.bot and not opts.standup)
	if opts.hellborn then
		model:SetAttribute("Hellborn", true)
	end
	if spawner then
		model:SetAttribute("Spawner", spawner.UserId) -- (v2.0: your own NPCs pay no cash)
	end
	if opts.standup then
		model:SetAttribute("StandUp", true)
	elseif opts.boxer then
		model:SetAttribute("Boxer", true)
	end
	if opts.bot then
		model:SetAttribute("Bot", true)
		model:SetAttribute("DisplayName", opts.name or "BOT")
	end
	if opts.team then
		model:SetAttribute("Team", opts.team)
	end
	if opts.zombie then
		model:SetAttribute("Zombie", true)
		zombieNo += 1
		model:SetAttribute("BotNo", zombieNo) -- (v2.0: the pack spreads out by this)
	end
	if opts.civilian then
		model:SetAttribute("Civilian", true)
	end
	if spawner then
		model:SetAttribute("Spawner", spawner.UserId)
	end
	-- a balaclava so they look like trouble
	local head = model:FindFirstChild("Head") :: BasePart
	local face = head and head:FindFirstChild("face")
	if face and face:IsA("Decal") then
		face.Texture = "rbxasset://textures/face.png"
	end
	local mask = Instance.new("Part")
	mask.Name = opts.zombie and "Rot" or "Mask"
	if opts.civilian then
		mask.Name = "Cap"
	end
	mask.Size = Vector3.new(1.3, 0.55, 1.3)
	mask.Color = opts.zombie and Color3.fromRGB(70, 96, 52) or (opts.bot and Color3.fromRGB(30, 30, 34) or Color3.fromRGB(20, 20, 22))
	mask.Material = opts.zombie and Enum.Material.Slate or Enum.Material.Fabric
	if opts.zombie then
		mask.Size = Vector3.new(1.26, 0.3, 1.26)
	end
	mask.CanCollide = false
	mask.CanQuery = false
	mask.CanTouch = false
	mask.Massless = true
	if opts.civilian then
		-- a cap, not a balaclava
		mask.Size = Vector3.new(1.26, 0.32, 1.26)
		mask.Color = (colors.Torso :: Color3):Lerp(Color3.new(0, 0, 0), 0.35)
	end
	if opts.standup then
		-- (a training dummy: a padded red cap)
		mask.Name = "Pad"
		mask.Size = Vector3.new(1.26, 0.34, 1.26)
		mask.Color = Color3.fromRGB(200, 60, 50)
		mask.Material = Enum.Material.Leather
	elseif opts.boxer then
		mask.Name = "Headgear"
		mask.Size = Vector3.new(1.3, 0.42, 1.3)
		mask.Color = Color3.fromRGB(176, 30, 34)
		mask.Material = Enum.Material.Leather
	end
	mask.CFrame = head.CFrame * CFrame.new(0, (opts.civilian or opts.standup) and 0.5 or 0.28, 0)
	local mw = Instance.new("WeldConstraint")
	mw.Part0 = head
	mw.Part1 = mask
	mw.Parent = mask
	mask.Parent = model
	model:PivotTo(cf)
	model.Parent = folder()

	local torso = model:FindFirstChild("Torso") :: BasePart
	local rig = model:FindFirstChild("Rig")
	local limbs = {}
	local mass = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not d.Massless then
			mass += d:GetMass()
		end
	end
	for _, def in RigInfo.Limbs do
		local part = model:FindFirstChild(def.partName)
		if part and part:IsA("BasePart") then
			limbs[def.key] = {
				part = part,
				def = def,
				muscle = rig and rig:FindFirstChild("Muscle_" .. def.key) :: AlignOrientation?,
				target = torso:FindFirstChild("M_" .. def.key) :: Attachment?,
				collider = part:FindFirstChild("Collider") :: BasePart?,
			}
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local npc: NPC = {
		model = model,
		kind = kind,
		weaponKind = opts.weapon or (kind == "gun" and GUNS[rng:NextInteger(1, #GUNS)] or MELEE[rng:NextInteger(1, #MELEE)]),
		torso = torso,
		head = head,
		limbs = limbs,
		balance = rig and rig:FindFirstChild("Balance") :: AlignOrientation?,
		drive = rig and rig:FindFirstChild("Drive") :: VectorForce?,
		mass = mass,
		state = "Active",
		ragdollUntil = 0,
		getUp = 1,
		crawling = false,
		crouch = false,
		phase = 0,
		moveDir = Vector3.zero,
		moveSpeed = 0,
		face = cf.LookVector,
		target = nil,
		seenSince = 0,
		lastSeen = 0,
		path = nil,
		pathIndex = 1,
		pathAt = 0,
		computing = false,
		coverUntil = 0,
		peekUntil = 0,
		nextCover = os.clock() + rng:NextNumber(2, 5),
		ammo = 0,
		reloadUntil = 0,
		weaponSide = "Right",
		fleeing = false,
		reloading = false,
		leapT0 = -10,
		leapHit = true,
		nextLeap = 0,
		nextCrawlLeap = 0,
		blindUntil = 0,
		nextShot = 0,
		burst = 0,
		swingT0 = -10,
		swingHit = true,
		nextThink = 0,
		lastHP = 600,
		stuckT = 0,
		jumpLock = 0,
		airTime = 0,
		strafe = 1,
		strafeUntil = 0,
		spawner = spawner and spawner.UserId or nil,
		rayParams = params,
		zombie = opts.zombie == true,
		bot = opts.bot == true,
		civilian = opts.civilian == true,
		boxer = opts.boxer == true,
		standup = opts.standup == true,
		punchSide = 1,
	}
	npcs[model] = npc
	if npc.civilian or npc.boxer or npc.standup then
		npc.kind = "melee"
	elseif not npc.zombie then
		arm(npc)
	else
		npc.kind = "melee"
	end
	npc.lastHP = totalHP(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not d.Anchored then
			pcall(function()
				d:SetNetworkOwner(nil)
			end)
		end
	end
	DamageService.Register(model, {
		onDeath = function()
			npc.state = "Dead"
			dropWeapon(npc)
			if npc.drive then
				npc.drive.Force = Vector3.zero
			end
			Debris:AddItem(model, 90)
		end,
	})
	ServerImpactSensor.Add(model)
	model.Destroying:Connect(function()
		npcs[model] = nil
		for w, by in claimed do
			if by == model then
				claimed[w] = nil
			end
		end
		if npc.weapon and npc.weapon.Parent and npc.weapon:GetAttribute("NPCHeld") then
			npc.weapon:Destroy()
		end
	end)
	if chromed and NPCService.OnCyber then
		task.spawn(NPCService.OnCyber, model, npc)
	end
	return model
end

-- (v2.0) gun game: a new weapon in the hand (the old one is gone)
function NPCService.SetWeapon(model: Model, weaponKind: string)
	local npc = npcs[model]
	if not npc or npc.state == "Dead" or npc.zombie then
		return
	end
	local old = npc.weapon
	dropWeapon(npc)
	if old and old.Parent then
		old:Destroy()
	end
	npc.weaponKind = weaponKind
	npc.kind = useKind(weaponKind)
	arm(npc)
end

function NPCService.Weapon(model: Model): Model?
	local npc = npcs[model]
	return npc and npc.weapon or nil
end

function NPCService.All(): { Model }
	local out = {}
	for m in npcs do
		table.insert(out, m)
	end
	return out
end

-- a flash grenade went off: NPCs that see it are blinded (close up: knocked over too)
function NPCService.Flash(pos: Vector3, radius: number, _by: Player?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	for model, npc in npcs do
		if npc.state == "Dead" or not npc.head.Parent then
			continue
		end
		local to = pos - npc.head.Position
		local d = to.Magnitude
		if d > radius then
			continue
		end
		params.FilterDescendantsInstances = { model, workspace:FindFirstChild("FX") or model }
		local hit = workspace:Raycast(npc.head.Position, to, params)
		if hit and (hit.Position - pos).Magnitude > 1.5 then
			continue -- behind a wall
		end
		local facing = math.clamp(npc.face:Dot(MathUtil.SafeUnit(MathUtil.Flat(to), npc.face)), 0, 1)
		local k = (1 - d / radius) * (0.4 + 0.6 * facing)
		npc.blindUntil = math.max(npc.blindUntil, os.clock() + Config.FlashNPCStun * k + 0.5)
		if d < 7 then
			NPCService.Ragdoll(model, 1.2)
		end
	end
end

function NPCService.IsNPC(model: Model): boolean
	return npcs[model] ~= nil
end

-- (v2.0) a bot driver sits in a car (VehicleService welds it and poses it) / gets out again
function NPCService.SetSeated(model: Model, on: boolean)
	local npc = npcs[model]
	if not npc then
		return
	end
	npc.seated = on or nil
	npc.moveDir = Vector3.zero
	npc.aimAt = nil
	if not on and npc.state ~= "Dead" then
		if npc.drive then
			npc.drive.Enabled = true
		end
		-- out of the car: it stumbles for a moment, then gets up
		npc.state = "Ragdoll"
		npc.ragdollUntil = os.clock() + 0.8
	end
end

-- (v2.0) something scary happened to a civilian (carjacked, shot at): it runs for a while
function NPCService.Scare(model: Model, seconds: number)
	local npc = npcs[model]
	if npc then
		npc.scaredUntil = os.clock() + seconds
	end
end

-- knocked over: limp for a while, then get up
function NPCService.Ragdoll(model: Model, duration: number)
	local npc = npcs[model]
	if not npc or npc.state == "Dead" then
		return
	end
	npc.state = "Ragdoll"
	npc.ragdollUntil = math.max(npc.ragdollUntil, os.clock() + math.clamp(duration, 0.4, 25))
end

------------------------------------------------------------------------
-- body control (runs every physics frame)
------------------------------------------------------------------------

local function setLegCollision(npc: NPC, on: boolean)
	for _, k in { "LeftLeg", "RightLeg" } do
		local L = npc.limbs[k]
		if L and L.collider and L.collider.Parent then
			L.collider.CanCollide = on
		end
	end
end

local function probe(npc: NPC): RaycastResult?
	npc.rayParams.FilterDescendantsInstances = { npc.model, npc.weapon or npc.model, workspace:FindFirstChild("FX") or npc.model }
	local best: RaycastResult? = nil
	local origin = npc.torso.Position
	for _, off in { Vector3.zero, Vector3.new(0.5, 0, 0), Vector3.new(-0.5, 0, 0), npc.moveDir * 0.9 } do
		local r = workspace:Raycast(origin + off, Vector3.new(0, -6, 0), npc.rayParams)
		if r and r.Normal.Y > 0.6 and (not best or r.Position.Y > best.Position.Y) and (not best or r.Position.Y - best.Position.Y < 2.2) then
			best = r
		end
	end
	return best
end

local function aimRel(npc: NPC, L: Limb, point: Vector3, invTorso: CFrame): CFrame
	local shoulder = npc.torso.CFrame:PointToWorldSpace(L.def.torsoPivot)
	local dirLocal = invTorso:VectorToWorldSpace(MathUtil.SafeUnit(point - shoulder, npc.face))
	dirLocal = MathUtil.SafeUnit(Vector3.new(dirLocal.X, math.min(dirLocal.Y, 0.95), math.min(dirLocal.Z, 0.3)), DOWN)
	return MathUtil.RotationBetween(DOWN, dirLocal)
end

local function bodyStep(npc: NPC, dt: number)
	local model = npc.model
	local torso = npc.torso
	if not torso.Parent then
		return
	end
	local now = os.clock()
	local g = workspace.Gravity * TimeScale.ForField(nil, torso.Position) ^ 2
	local M = npc.mass
	local W = M * g
	local vel = torso.AssemblyLinearVelocity
	local vh = MathUtil.Flat(vel)

	-- held by a player (hand / physics gun): their client moves the body, it just goes limp
	local held = OwnershipService.IsHeldBody(model)
	if not held and now > (npc.ownerCheck or 0) then
		npc.ownerCheck = now + 1
		-- let go: the server simulates it again
		local ok, owner = pcall(function()
			return torso:GetNetworkOwner()
		end)
		if ok and owner ~= nil then
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and not d.Anchored then
					pcall(function()
						d:SetNetworkOwner(nil)
					end)
				end
			end
		end
	end
	if model:GetAttribute("Asleep") then
		held = true
	end

	-- hurt: a hard hit knocks it over
	local hp = totalHP(model)
	if npc.civilian and hp < npc.lastHP - 1 then
		npc.scaredUntil = now + 12
	end
	if hp < npc.lastHP - 28 and npc.state ~= "Dead" then
		NPCService.Ragdoll(model, 0.9 + (npc.lastHP - hp) / 120)
	end
	npc.lastHP = hp
	npc.crawling = not legOK(model, "LeftLeg") or not legOK(model, "RightLeg") or (model:GetAttribute("HP_Torso") or 100) < 22
	-- the arm holding the weapon is broken / gone: it falls out of the hand
	if npc.weapon and (not armUsable(npc, npc.weaponSide) or not npc.weapon.Parent) then
		dropWeapon(npc, true)
	end

	local s = npc.state
	if s == "Dead" or held then
		if npc.drive then
			npc.drive.Force = Vector3.zero
		end
		if npc.balance then
			npc.balance.Enabled = false
		end
		for _, L in npc.limbs do
			if L.muscle then
				L.muscle.Enabled = false
			end
		end
		setLegCollision(npc, true)
		if held and s ~= "Dead" then
			npc.state = "Ragdoll"
			npc.ragdollUntil = math.max(npc.ragdollUntil, now + 1)
		end
		return
	end
	if npc.seated then
		-- (v2.0) in a car: the seat holds the torso, VehicleService poses the limbs
		if npc.drive then
			npc.drive.Force = Vector3.zero
		end
		if npc.balance then
			npc.balance.Enabled = false
		end
		return
	end
	if s == "Ragdoll" then
		if npc.drive then
			npc.drive.Force = Vector3.zero
		end
		if npc.balance then
			npc.balance.Enabled = false
		end
		for _, L in npc.limbs do
			if L.muscle then
				L.muscle.Enabled = false
			end
		end
		setLegCollision(npc, true)
		if now > npc.ragdollUntil and vel.Magnitude < 6 then
			npc.state = "GettingUp"
			npc.getUp = 0
		end
		return
	end
	if s == "Leap" then
		-- flying at you, arms first; whoever it reaches gets hit and thrown
		local t = now - npc.leapT0
		if npc.drive then
			npc.drive.Force = Vector3.zero
		end
		if npc.balance then
			npc.balance.CFrame = CFrame.lookAt(Vector3.zero, MathUtil.SafeUnit(MathUtil.Flat(npc.face), Vector3.new(0, 0, -1))) * CFrame.Angles(-1.25, 0, 0)
			npc.balance.MaxTorque = Config.BalanceTorque * 0.7
			npc.balance.Enabled = true
		end
		for key, L in npc.limbs do
			if L.muscle and L.target and not model:GetAttribute("Severed_" .. key) then
				L.muscle.Enabled = true
				L.muscle.MaxTorque = (L.def.kind == "Leg" and Config.LegMuscleTorque or Config.ArmMuscleTorque) * 1.2
				L.target.CFrame = CFrame.new(L.def.torsoPivot) * (L.def.kind == "Leg" and CFrame.Angles(-0.1, 0, L.def.side * 0.12) or CFrame.Angles(2.9, 0, L.def.side * 0.15))
			end
		end
		local target = npc.target
		local tt = target and target:FindFirstChild("Torso")
		if not npc.leapHit and tt and tt:IsA("BasePart") and (tt.Position - torso.Position).Magnitude < (npc.zombie and 4.6 or 3.8) then
			npc.leapHit = true
			NPCService.LeapHit(npc, target :: Model)
		end
		local ground = t > 0.25 and probe(npc)
		if (ground and torso.Position.Y - ground.Position.Y < 2.4) or t > 1.3 then
			npc.state = "GettingUp"
			npc.getUp = 0.35
		end
		return
	end
	if s == "GettingUp" then
		npc.getUp = math.min(1, npc.getUp + dt / Config.NPCGetUpTime)
		if npc.getUp >= 1 then
			npc.state = "Active"
		end
	end

	local ground = probe(npc)
	local heading = CFrame.lookAt(Vector3.zero, MathUtil.SafeUnit(MathUtil.Flat(npc.face), Vector3.new(0, 0, -1)))
	local crawl = npc.crawling
	setLegCollision(npc, crawl)

	-- hover spring + drive (same model as the players)
	local force = Vector3.zero
	local tk = TimeScale.ForField(nil, torso.Position) -- (v2.8) the Sandevistan: NPCs live in slow motion too
	local cySpeed = model:GetAttribute("CySpeed") -- (v2.8) a chromed merc with STRIDER legs
	local speed = npc.moveSpeed * (crawl and 0.22 or 1) * (npc.crouch and 0.5 or 1) * tk * (typeof(cySpeed) == "number" and cySpeed or 1)
	local desired = npc.moveDir * speed
	npc.jumpLock = math.max(0, npc.jumpLock - dt)
	local surf = Water.SurfaceAt(torso.Position)
	if surf and torso.Position.Y < surf - 0.5 then
		-- in the pool: paddle at the surface (no legs or no arms: it goes down)
		npc.airTime = 0
		local canSwim = not ((model:GetAttribute("Severed_LeftLeg") and model:GetAttribute("Severed_RightLeg"))
			or (model:GetAttribute("Severed_LeftArm") and model:GetAttribute("Severed_RightArm")))
		local fy = canSwim and M * (g * 0.15 + 10 * (surf - 0.4 - torso.Position.Y) - 5 * vel.Y) or -M * g * 0.6
		fy = math.clamp(fy, -W * 1.5, W * 1.5)
		local fh = MathUtil.ClampMagnitude((npc.moveDir * Config.SwimSpeed - vh) * 3 * M, M * 30)
		force = Vector3.new(fh.X, fy, fh.Z)
	elseif ground then
		npc.airTime = 0
		local height = torso.Position.Y - ground.Position.Y
		if crawl then
			local err = Config.ProneHeight - height
			local fy = math.clamp(M * (g * 0.8 + 120 * tk * tk * err - 12 * tk * vel.Y), 0, W * 1.1)
			local lunging = now - (npc.nextCrawlLeap - Config.NPCCrawlLeapGap) < 0.45
			local fh = MathUtil.ClampMagnitude((desired - vh) * (lunging and 0.8 or 6) * tk * M, M * 24 * tk * tk)
			force = Vector3.new(fh.X, fy, fh.Z)
			-- crawlers lunge forward on their arms
			if desired.Magnitude > 1 * tk and now > npc.nextCrawlLeap and npc.getUp >= 1 then
				npc.nextCrawlLeap = now + Config.NPCCrawlLeapGap * rng:NextNumber(0.8, 1.3)
				local push = (MathUtil.SafeUnit(desired, npc.face) * Config.NPCCrawlLeapSpeed + Vector3.new(0, 9, 0)) * tk
				for _, d in model:GetChildren() do
					if d:IsA("BasePart") and not d.Anchored then
						pcall(function()
							d.AssemblyLinearVelocity += push
						end)
					end
				end
				GoreService.Sound("thud", torso, 0.6)
			end
		elseif npc.jumpLock <= 0 then
			local amp = math.rad(Config.StepAmplitude) * math.clamp(vh.Magnitude / Config.WalkSpeed, 0, 1.3)
			local legAngle = amp * math.abs(math.sin(npc.phase))
			local standH = Config.TorsoHalfHeight + Config.LegLength * math.cos(legAngle * Config.WalkBob) + Config.FootClearance
			if npc.crouch then
				standH = Config.TorsoHalfHeight + Config.LegLength * math.cos(math.rad(Config.CrouchLegAngle)) * 0.85 + Config.FootClearance
			end
			local support = 0.35 + 0.65 * npc.getUp
			local fy = M * (g + Config.SpringK * tk * tk * (standH - height) - Config.SpringD * tk * vel.Y)
			fy = math.clamp(fy, 0, W * Config.MaxSupportFactor) * support
			local fh = MathUtil.ClampMagnitude((desired * npc.getUp - vh) * Config.VelocityGain * tk * M, M * Config.GroundAccel * tk * tk)
			force = Vector3.new(fh.X, fy, fh.Z)
		end
	else
		npc.airTime += dt
		local acc = MathUtil.ClampMagnitude((desired - vh) * 2 * tk, Config.AirAccel * tk * tk)
		force = Vector3.new(acc.X, 0, acc.Z) * M
		if npc.airTime > 0.9 then
			NPCService.Ragdoll(model, 1.2) -- falling: tumble
		end
	end
	if npc.drive then
		npc.drive.Enabled = true
		npc.drive.Force = force
	end
	if npc.balance then
		local cf = crawl and heading * PRONE_ROT or heading * CFrame.Angles(npc.crouch and -math.rad(18) or -math.rad(5) * math.clamp(vh.Magnitude / 12, 0, 1), 0, 0)
		npc.balance.CFrame = cf
		npc.balance.MaxTorque = Config.BalanceTorque * (crawl and 0.45 or math.max(0.05, npc.getUp ^ 1.5))
		npc.balance.Responsiveness = crawl and 12 or Config.BalanceResponsiveness
		npc.balance.Enabled = true
	end

	-- limbs
	local moving = vh.Magnitude > 1
	npc.phase += dt * (crawl and 3.5 or math.clamp(vh.Magnitude, 0, 20) * 0.62)
	local invTorso = torso.CFrame.Rotation:Inverse()
	local amp = math.rad(Config.StepAmplitude) * math.clamp(vh.Magnitude / Config.WalkSpeed, 0, 1.3)
	for key, L in npc.limbs do
		if not L.muscle or not L.target or model:GetAttribute("Severed_" .. key) then
			continue
		end
		local def = L.def
		local side = def.side
		local broken = model:GetAttribute("Broken_" .. key)
		L.muscle.Enabled = true
		local base = def.kind == "Leg" and Config.LegMuscleTorque or Config.ArmMuscleTorque
		L.muscle.MaxTorque = base * (broken and Config.BrokenLimbStrength or 1) * (0.2 + 0.8 * npc.getUp)
		local rel: CFrame
		if def.kind == "Leg" then
			if crawl then
				rel = CFrame.Angles(moving and 0.22 * math.sin(npc.phase + (side > 0 and math.pi or 0)) or 0, 0, side * 0.12)
			elseif npc.crouch then
				local world = heading * CFrame.fromAxisAngle(Vector3.xAxis, math.rad(Config.CrouchLegAngle)) * CFrame.Angles(0, 0, side * math.rad(Config.CrouchLegSplay))
				rel = invTorso * world.Rotation
			else
				-- legs swing along the walking direction (also when it backs off or strafes)
				local theta = (side < 0 and 1 or -1) * amp * math.sin(npc.phase)
				local localMove = heading:VectorToObjectSpace(MathUtil.SafeUnit(vh, heading.LookVector))
				local axis = MathUtil.SafeUnit(localMove:Cross(Vector3.yAxis), Vector3.xAxis)
				local world = heading * CFrame.fromAxisAngle(axis, theta) * CFrame.Angles(0, 0, side * math.rad(Config.IdleLegSplay))
				rel = invTorso * world.Rotation
			end
		else
			local aim: Vector3? = nil
			local swingT = now - npc.swingT0
			local weaponSign = npc.weaponSide == "Left" and -1 or 1
			local isWeaponArm = side == weaponSign and npc.weapon ~= nil
			local reloadingNow = npc.reloading and npc.weapon ~= nil
			if reloadingNow then
				-- the gun in front of the chest, the other hand at it (changing the magazine)
				local chest = torso.CFrame:PointToWorldSpace(Vector3.new(-weaponSign * 0.3, 0.1, -1.8))
				if isWeaponArm then
					aim = chest
				else
					local gunPt = npc.weapon and npc.weapon.PrimaryPart and npc.weapon.PrimaryPart.Position
					aim = gunPt and (gunPt + Vector3.new(0, -0.4 + 0.3 * math.sin(now * 9), 0)) or chest
				end
				L.muscle.MaxTorque = base * 1.6
			elseif isWeaponArm and npc.kind == "melee" and swingT < 0.45 then
				-- the swing: from high on the right across and down
				local d = npc.face
				local k = math.clamp((swingT - 0.05) / 0.25, 0, 1)
				local k2 = k * k * (3 - 2 * k)
				local up = Vector3.yAxis
				local yaw = math.rad(-70) * (1 - k2) + math.rad(50) * k2
				local pitch = math.rad(60) * (1 - k2) + math.rad(-30) * k2
				local dir = CFrame.fromAxisAngle(up, yaw):VectorToWorldSpace(d)
				local r2 = MathUtil.SafeUnit(dir:Cross(up), Vector3.xAxis)
				dir = CFrame.fromAxisAngle(r2, pitch):VectorToWorldSpace(dir)
				local shoulder = torso.CFrame:PointToWorldSpace(def.torsoPivot)
				aim = shoulder + dir * 3
				L.muscle.MaxTorque = base * 3
			elseif npc.aimAt and npc.weapon and (isWeaponArm or npc.kind == "gun") then
				if not isWeaponArm then
					-- the other hand supports the gun
					local gunPt = npc.weapon.PrimaryPart and npc.weapon.PrimaryPart.Position
					aim = gunPt and (gunPt + npc.face * 1.2) or npc.aimAt
				else
					aim = npc.aimAt
				end
				L.muscle.MaxTorque = base * 1.6
			end
			if not aim and npc.zombie and not crawl then
				-- (v2.0) arms out in front, reaching
				aim = torso.Position + npc.face * 4 + Vector3.new(side * 0.4, 0.9 + 0.25 * math.sin(now * 3 + side), 0)
			end
			if aim then
				rel = aimRel(npc, L, aim, invTorso)
			elseif npc.fleeing and not crawl then
				rel = CFrame.Angles(0.4 + 0.9 * math.sin(npc.phase + (side > 0 and math.pi or 0)), 0, side * 0.15)
			elseif crawl then
				local ph = npc.phase + (side > 0 and math.pi or 0)
				rel = moving and CFrame.Angles(2.45 + 0.6 * math.sin(ph), 0, side * (0.35 + 0.15 * math.cos(ph))) or CFrame.Angles(2.3, 0, side * 0.45)
			else
				rel = CFrame.Angles(0.15 - (side < 0 and 1 or -1) * amp * math.sin(npc.phase) * 0.6, 0, side * 0.12)
			end
		end
		L.target.CFrame = CFrame.new(def.torsoPivot) * rel
	end
end

------------------------------------------------------------------------
-- brain (5x a second)
------------------------------------------------------------------------

local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
sightParams.RespectCanCollide = true

-- is the line from `from` to `to` free? (bodies and held items do not block)
local function clearLine(from: Vector3, to: Vector3, ignore: { Instance }): boolean
	sightParams.FilterDescendantsInstances = ignore
	local d = to - from
	local hit = workspace:Raycast(from, d, sightParams)
	if not hit then
		return true
	end
	local m = hit.Instance:FindFirstAncestorOfClass("Model")
	if m and m:GetAttribute("RagdollRig") then
		return true
	end
	return (hit.Position - to).Magnitude < 1.5
end

local function ignoreList(npc: NPC, extra: Instance?): { Instance }
	local list: { Instance } = { npc.model }
	if npc.weapon then
		table.insert(list, npc.weapon)
	end
	local fx = workspace:FindFirstChild("FX")
	if fx then
		table.insert(list, fx)
	end
	if extra then
		table.insert(list, extra)
	end
	return list
end

local function candidates(): { Model }
	local list: { Model } = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		if c and not p:GetAttribute("InLobby") then
			table.insert(list, c)
		end
	end
	if NPCService.ExtraTargets then
		for _, m in NPCService.ExtraTargets() do
			table.insert(list, m)
		end
	end
	return list
end

local function findTarget(npc: NPC): (Model?, boolean)
	local best, bestD, bestVis = nil, math.huge, false
	local eye = npc.head.Position
	for _, c in candidates() do
		local t = c:FindFirstChild("Torso")
		if c == npc.model or not t or not t:IsA("BasePart") or c:GetAttribute("Dead") then
			continue
		end
		if NPCService.CanTarget then
			if not NPCService.CanTarget(npc.model, c) then
				continue
			end
		elseif not Players:GetPlayerFromCharacter(c) then
			continue -- (a sandbox hostile: players only)
		end
		local d = (t.Position - eye).Magnitude
		if d > Config.NPCSightRange * (npc.zombie and 3 or 1) then
			continue -- (zombies smell you from much further)
		end
		local vis = clearLine(eye, (t :: BasePart).Position, ignoreList(npc, c))
		-- prefer somebody it can see
		local score = d * (vis and 1 or 2.2)
		if score < bestD then
			best, bestD, bestVis = c, score, vis
		end
	end
	return best, bestVis
end

-- (v2.0) a zombie bot's prey: the closest one it may go for, anywhere on the map (walls or not). It sticks with
-- whoever it is after unless somebody else is much closer.
local function zombiePrey(npc: NPC): Model?
	local pos = npc.torso.Position
	local cur = npc.target
	local curD = math.huge
	local best, bestD = nil, math.huge
	for _, c in candidates() do
		local t = c:FindFirstChild("Torso")
		if c == npc.model or not t or not t:IsA("BasePart") or c:GetAttribute("Dead") or c:GetAttribute("Zombie") then
			continue
		end
		if NPCService.CanTarget then
			if not NPCService.CanTarget(npc.model, c) then
				continue
			end
		elseif not Players:GetPlayerFromCharacter(c) then
			continue
		end
		local d = (t.Position - pos).Magnitude
		if c == cur then
			curD = d
		end
		if d < bestD then
			best, bestD = c, d
		end
	end
	if cur and curD < math.huge and curD < bestD * 1.6 then
		return cur
	end
	return best
end

local function computePath(npc: NPC, goal: Vector3)
	if npc.computing then
		return
	end
	npc.computing = true
	npc.pathAt = os.clock()
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = 1.6,
			AgentHeight = 5.2,
			AgentCanJump = true,
			AgentCanClimb = false,
			WaypointSpacing = 4,
		})
		local ok = pcall(function()
			path:ComputeAsync(npc.torso.Position, goal)
		end)
		npc.computing = false
		if ok and path.Status == Enum.PathStatus.Success then
			local wps = path:GetWaypoints()
			npc.path = wps
			npc.pathIndex = math.min(2, #wps)
			npc.pathGoal = goal
		else
			npc.path = nil
			npc.pathGoal = goal -- (walk straight at it)
		end
	end)
end

-- a spot near the NPC where something solid is between it (crouched) and the target
local function findCover(npc: NPC, targetPos: Vector3): Vector3?
	local here = npc.torso.Position
	local best, bestScore = nil, -math.huge
	local ignore = ignoreList(npc)
	for _, r in { 5, 9, 14, 20, Config.NPCCoverSearch } do
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			local p = here + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			sightParams.FilterDescendantsInstances = ignore
			local down = workspace:Raycast(p + Vector3.new(0, 8, 0), Vector3.new(0, -20, 0), sightParams)
			if not down or down.Normal.Y < 0.7 then
				continue
			end
			local g = down.Position
			local low = g + Vector3.new(0, 2.2, 0)
			local high = g + Vector3.new(0, 4.6, 0)
			local toT = targetPos - low
			local block = workspace:Raycast(low, toT.Unit * math.min(toT.Magnitude, 8), sightParams)
			if not block then
				continue -- nothing in front of it
			end
			local bm = block.Instance:FindFirstAncestorOfClass("Model")
			if bm and bm:GetAttribute("RagdollRig") then
				continue
			end
			if not block.Instance.Anchored and block.Instance.AssemblyMass < 20 then
				continue -- a crate that flies away is no cover
			end
			local canShoot = clearLine(high, targetPos, ignore)
			local score = -r * 0.6 - (g - targetPos).Magnitude * 0.05 + (canShoot and 12 or 0)
			if score > bestScore then
				best, bestScore = g, score
			end
		end
	end
	return best
end

local function walkTo(npc: NPC, goal: Vector3, speed: number, repathDist: number?, repathTime: number?)
	local now = os.clock()
	if not npc.pathGoal or (npc.pathGoal - goal).Magnitude > (repathDist or 6) or now - npc.pathAt > (repathTime or 2.5) then
		computePath(npc, goal)
	end
	local pos = npc.torso.Position
	local wp: Vector3 = goal
	local path = npc.path
	if path and npc.pathIndex <= #path then
		local w = path[npc.pathIndex]
		wp = w.Position
		if MathUtil.Flat(wp - pos).Magnitude < 2.2 then
			if w.Action == Enum.PathWaypointAction.Jump then
				npc.jumpLock = 0.3
				pcall(function()
					npc.torso:ApplyImpulse(Vector3.new(0, 40, 0) * npc.mass)
				end)
			end
			npc.pathIndex += 1
		end
	end
	npc.moveDir = MathUtil.SafeUnit(MathUtil.Flat(wp - pos), Vector3.zero)
	npc.moveSpeed = speed
	-- stuck: jump and think again
	if not npc.stuckRef or (pos - npc.stuckRef).Magnitude > 2 then
		npc.stuckRef = pos
		npc.stuckT = now
	elseif now - npc.stuckT > 1.6 then
		npc.stuckT = now
		npc.jumpLock = 0.3
		pcall(function()
			npc.torso:ApplyImpulse(Vector3.new(0, 42, 0) * npc.mass)
		end)
		computePath(npc, goal)
	end
end

local function shoot(npc: NPC, targetPos: Vector3)
	local gun = npc.weapon
	local muzzle = gun and Items.Muzzle(gun)
	if not gun or not muzzle then
		return
	end
	local now = os.clock()
	local stats = Config.Guns[npc.weaponKind] or Config.Guns.pistol
	if now < npc.nextShot or npc.reloading then
		return
	end
	if npc.ammo <= 0 then
		NPCService.StartReload(npc)
		return
	end
	local origin = muzzle.WorldPosition
	local want = targetPos - origin
	-- only when the barrel points roughly at the target
	if want.Magnitude < 1 or muzzle.WorldCFrame.LookVector:Dot(want.Unit) < 0.9 then
		return
	end
	if stats.projectile and not stats.flare and want.Magnitude < 16 then
		return -- (a rocket this close would blow the bot up too)
	end
	npc.ammo -= 1
	local auto = stats.auto
	if auto then
		npc.burst += 1
		if npc.burst >= rng:NextInteger(4, 7) then
			npc.burst = 0
			npc.nextShot = now + rng:NextNumber(0.5, 1.0)
		else
			npc.nextShot = now + stats.interval * 1.3
		end
	else
		npc.nextShot = now + stats.interval * rng:NextNumber(1.8, 3)
	end
	local spread = math.rad(Config.NPCAccuracy + (npc.moveSpeed > 1 and 2 or 0) + (stats.spread or 0) * 0.5)
	local dirs = {}
	local pellets = npc.weaponKind == "shotgun" and Config.ShotgunPellets or 1
	for i = 1, pellets do
		local s = spread + (pellets > 1 and math.rad(Config.ShotgunSpread) or 0)
		dirs[i] = (CFrame.lookAt(Vector3.zero, want.Unit) * CFrame.Angles(rng:NextNumber(-s, s), rng:NextNumber(-s, s), 0)).LookVector
	end
	if stats.projectile then
		-- (v2.0) rockets, lock-on missiles, flares
		if NPCService.OnBotProjectile then
			NPCService.OnBotProjectile(npc.model, gun, npc.weaponKind, origin, dirs[1], npc.target)
		end
	else
		GunService.ServerShot(npc.model, gun, origin, dirs, 0.65)
	end
	-- kick
	local hand = npc.limbs.RightArm
	if hand then
		pcall(function()
			hand.part:ApplyImpulse((Vector3.new(0, stats.recoil or 7, 0) - want.Unit * (stats.recoil or 7) * 0.5) * hand.part.AssemblyMass * 0.6)
		end)
	end
end

-- reloading takes time and both hands (one arm: much slower); the magazine is full at the end
function NPCService.StartReload(npc: NPC)
	local gun = npc.weapon
	local stats = Config.Guns[npc.weaponKind]
	if not gun or not stats or npc.reloading then
		return
	end
	local other = npc.weaponSide == "Left" and "Right" or "Left"
	local oneHand = not armUsable(npc, other)
	npc.reloading = true
	npc.reloadUntil = os.clock() + stats.reload * (oneHand and Config.NPCOneHandReload or Config.NPCReloadMult)
	GoreService.Sound("magOut", gun.PrimaryPart or npc.torso, 1)
end

local function updateReload(npc: NPC)
	if not npc.reloading then
		return
	end
	if not npc.weapon then
		npc.reloading = false
		return
	end
	if os.clock() >= npc.reloadUntil then
		npc.reloading = false
		local stats = Config.Guns[npc.weaponKind] or Config.Guns.pistol
		npc.ammo = stats.mag
		GoreService.Sound(npc.weaponKind == "shotgun" and "pump" or "reload", npc.weapon.PrimaryPart or npc.torso, 1)
	end
end

local function swing(npc: NPC, target: Model)
	local now = os.clock()
	if now - npc.swingT0 < 0.95 then
		return
	end
	npc.swingT0 = now
	npc.swingHit = false
	GoreService.Sound("slash", npc.torso, 0.8)
	task.delay(0.18, function()
		if npc.state ~= "Active" or not target.Parent then
			return
		end
		local tt = target:FindFirstChild("Torso")
		if not tt or not tt:IsA("BasePart") then
			return
		end
		local to = tt.Position - npc.torso.Position
		if to.Magnitude > Config.NPCMeleeReach + 1 or MathUtil.Flat(to).Unit:Dot(MathUtil.Flat(npc.face).Unit) < 0.2 then
			return
		end
		local regions = { "Torso", "Torso", "Head", "LeftArm", "RightArm", "LeftLeg" }
		local region = regions[rng:NextInteger(1, #regions)]
		if target:GetAttribute("Severed_" .. region) then
			region = "Torso"
		end
		local melee = Items.Kinds[npc.weaponKind] and Items.Kinds[npc.weaponKind].melee or "blunt"
		local heavy = npc.weaponKind == "sledge" or npc.weaponKind == "axe"
		local dmg = Config.NPCMeleeDamage * (heavy and 1.4 or 1) * (Config.LimbMultiplier[region] or 1)
		local partName = RigInfo.RegionPart[region]
		local hitPart = target:FindFirstChild(partName)
		local point = (hitPart and hitPart:IsA("BasePart")) and hitPart.Position or tt.Position
		local dir = MathUtil.SafeUnit(to, npc.face)
		DamageService.MarkBotAttacker(target, npc.model)
		if melee == "slash" then
			GoreService.Sound("slash", point, 1)
			DamageService.ApplyDamage(target, region, dmg, point, {
				cause = "Cut down by a hostile",
				allowSever = true,
				severAt = region == "Head" and 70 or 46,
				bleed = 0.8,
				bleedTime = 15,
			})
			DamageService.Knock(target, region, dir * 14 * DamageService.PartMass(target, region), heavy and 1.2 or nil, point)
		elseif melee == "stab" then
			GoreService.Sound("stab", point, 1)
			DamageService.ApplyDamage(target, region, dmg * 1.1, point, { cause = "Speared by a hostile", allowSever = false, bleed = 1, bleedTime = 20 })
			DamageService.Knock(target, region, dir * 18 * DamageService.PartMass(target, region), nil, point)
		else
			GoreService.Sound(heavy and "heavyHit" or "punch", point, 1)
			DamageService.ApplyDamage(target, region, dmg * 0.8, point, { cause = "Beaten by a hostile", allowSever = false })
			DamageService.Blast(target, dir * (heavy and 45 or 28) + Vector3.new(0, 12, 0), heavy and 2.2 or 1.4)
		end
	end)
end

-- a brawler's leap reached somebody
function NPCService.LeapHit(npc: NPC, target: Model)
	local tt = target:FindFirstChild("Torso")
	if not tt or not tt:IsA("BasePart") then
		return
	end
	if npc.zombie then
		-- (v2.0) a zombie lands on you teeth first: a bite
		local dirZ = MathUtil.SafeUnit(MathUtil.Flat(tt.Position - npc.torso.Position), npc.face)
		DamageService.MarkBotAttacker(target, npc.model)
		DamageService.ApplyDamage(target, "Torso", Config.ZombieBiteDamage * 1.3, tt.Position, { cause = "Eaten by zombies", allowSever = false, bleed = 0.9, bleedTime = 14 })
		DamageService.Blast(target, dirZ * 30 + Vector3.new(0, 8, 0), 1.6)
		GoreService.Sound("zombieBite", tt.Position, 1)
		if NPCService.OnZombieBite then
			NPCService.OnZombieBite(npc.model, target)
		end
		return
	end
	local dir = MathUtil.SafeUnit(MathUtil.Flat(tt.Position - npc.torso.Position), npc.face)
	local region = rng:NextNumber() < 0.3 and "Head" or "Torso"
	local melee = npc.weapon and Items.Melee(npc.weapon) or "blunt"
	local dmg = Config.NPCLeapDamage * (Config.LimbMultiplier[region] or 1)
	DamageService.ApplyDamage(target, region, dmg, tt.Position, {
		cause = "Jumped by a hostile",
		allowSever = melee == "slash",
		severAt = 60,
		bleed = melee ~= "blunt" and 0.8 or nil,
		bleedTime = 12,
	})
	DamageService.Blast(target, dir * Config.NPCLeapKnock + Vector3.new(0, Config.NPCLeapKnock * 0.3, 0), 2)
	GoreService.Sound(melee == "blunt" and "heavyHit" or "stab", tt.Position, 1)
end

local function leap(npc: NPC, target: Model)
	local tt = target:FindFirstChild("Torso")
	if not tt or not tt:IsA("BasePart") then
		return
	end
	local now = os.clock()
	npc.state = "Leap"
	npc.leapT0 = now
	npc.leapHit = false
	npc.nextLeap = now + (npc.zombie and rng:NextNumber(2.5, 4.5) or rng:NextNumber(4, 7))
	local to = MathUtil.Flat(tt.Position - npc.torso.Position)
	local speed = npc.zombie and math.clamp(to.Magnitude * 2.3, Config.NPCLeapSpeed, Config.ZombieLeapSpeed) or Config.NPCLeapSpeed
	local v = MathUtil.SafeUnit(to, npc.face) * speed + Vector3.new(0, npc.zombie and 22 or 16, 0)
	for _, d in npc.model:GetChildren() do
		if d:IsA("BasePart") and not d.Anchored then
			pcall(function()
				d.AssemblyLinearVelocity = v
			end)
		end
	end
	GoreService.Sound(npc.zombie and "zombieLeap" or "leap", npc.torso, 1)
	GoreService.Sound("lung", npc.torso, 0.8)
end

-- run away from whoever is closest (sprinting, looking back now and then)
local function flee(npc: NPC, target: Model?)
	npc.fleeing = true
	npc.aimAt = nil
	npc.crouch = false
	local pos = npc.torso.Position
	local away = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
	local tt = target and target:FindFirstChild("Torso")
	if tt and tt:IsA("BasePart") then
		away = MathUtil.Flat(pos - tt.Position)
	end
	away = MathUtil.SafeUnit(away, Vector3.new(1, 0, 0))
	if not npc.pathGoal or (npc.pathGoal - pos).Magnitude < 10 or MathUtil.Flat(npc.pathGoal - pos).Unit:Dot(away) < 0.3 then
		npc.pathGoal = nil
	end
	walkTo(npc, npc.pathGoal or (pos + away * 60), Config.NPCSprintSpeed)
	npc.face = MathUtil.SafeUnit(npc.moveDir, away)
end

-- no weapon: get one (sprint to the nearest weapon lying around), or run
local function unarmed(npc: NPC, target: Model?): boolean
	local side = armUsable(npc, "Right") and "Right" or (armUsable(npc, "Left") and "Left" or nil)
	if not side then
		return false
	end
	local w = npc.wantWeapon
	if not w or not w.Parent or not w.PrimaryPart or w:GetAttribute("HolderId") or w:GetAttribute("Stuck") then
		if w then
			claimed[w] = nil
		end
		w = findWeapon(npc)
		npc.wantWeapon = w
		if w then
			claimed[w] = npc.model
		end
	end
	if not w or not w.PrimaryPart then
		return false
	end
	local wp = w.PrimaryPart.Position
	local d = MathUtil.Flat(wp - npc.torso.Position).Magnitude
	if d < 3.4 and math.abs(wp.Y - npc.torso.Position.Y) < 5 then
		claimed[w] = nil
		npc.wantWeapon = nil
		if equip(npc, w, side) then
			GoreService.Sound("click", npc.torso, 0.8)
		end
		npc.moveDir = Vector3.zero
		return true
	end
	npc.fleeing = false
	npc.aimAt = nil
	npc.crouch = false
	walkTo(npc, wp, Config.NPCSprintSpeed)
	npc.face = MathUtil.SafeUnit(npc.moveDir, npc.face)
	if target then
		-- (it keeps an eye on you)
		npc.target = target
	end
	return true
end

local function think(npc: NPC)
	local now = os.clock()
	if npc.seated then
		npc.moveDir = Vector3.zero
		npc.aimAt = nil
		return
	end
	updateReload(npc)
	if npc.state ~= "Active" and npc.state ~= "GettingUp" then
		npc.moveDir = Vector3.zero
		npc.aimAt = nil
		return
	end
	if NPCService.OnThink then
		pcall(NPCService.OnThink, npc) -- (v2.8) chromed mercs use their cyberware
	end
	-- blinded by a flash grenade: stumbles around, can't aim
	if now < npc.blindUntil then
		npc.aimAt = nil
		npc.crouch = false
		npc.fleeing = false
		if rng:NextNumber() < 0.3 then
			npc.moveDir = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit
			npc.moveSpeed = Config.NPCWalkSpeed * 0.5
			npc.face = npc.moveDir
		end
		return
	end
	-- (v2.0) a civilian (a bot driver out of its car): never fights. Scared or somebody close: it runs away,
	-- otherwise it walks off slowly
	if npc.civilian then
		npc.crouch = false
		npc.aimAt = nil
		local near, nearD = nil, 9
		for _, p in Players:GetPlayers() do
			local t = p.Character and p.Character:FindFirstChild("Torso")
			if t and t:IsA("BasePart") then
				local d = (t.Position - npc.torso.Position).Magnitude
				if d < nearD then
					near, nearD = p.Character, d
				end
			end
		end
		if now < (npc.scaredUntil or 0) or near then
			flee(npc, near)
		else
			npc.fleeing = false
			if rng:NextNumber() < 0.08 or npc.moveDir.Magnitude < 0.1 then
				local a = rng:NextNumber(0, math.pi * 2)
				npc.moveDir = Vector3.new(math.cos(a), 0, math.sin(a))
			end
			npc.moveSpeed = Config.NPCWalkSpeed * 0.6
			npc.face = npc.moveDir
		end
		return
	end
	-- (v2.0) the stand-up dummy: it stays where it is, turns to face whoever is closest, guard up. Knocked over
	-- (shot, kicked, blown up), it always gets back up (its body does that by itself: GettingUp)
	if npc.standup then
		npc.fleeing = false
		npc.crouch = false
		npc.aimAt = nil
		npc.moveDir = Vector3.zero
		local near, nearD = nil, 40
		for _, p in Players:GetPlayers() do
			local t = p.Character and p.Character:FindFirstChild("Torso")
			if t and t:IsA("BasePart") then
				local d = (t.Position - npc.torso.Position).Magnitude
				if d < nearD then
					near, nearD = t, d
				end
			end
		end
		if near then
			npc.face = MathUtil.SafeUnit(MathUtil.Flat(near.Position - npc.torso.Position), npc.face)
		end
		return
	end
	local target, visible = findTarget(npc)
	npc.target = target
	-- (v2.0) the game mode's goal for this bot
	npc.holdPos = nil
	local chasing = false
	local goal = NPCService.ModeGoal and NPCService.ModeGoal(npc.model)
	if goal then
		local kind = goal.kind
		if kind == "chase" and goal.target then
			local gt = goal.target:FindFirstChild("Torso")
			if gt and gt:IsA("BasePart") then
				target = goal.target
				visible = clearLine(npc.head.Position, gt.Position, ignoreList(npc, goal.target))
				npc.target = target
				chasing = true
			end
		elseif kind == "tag" or kind == "flee" or kind == "idle" then
			npc.crouch = false
			npc.aimAt = nil
			if kind == "tag" and goal.target then
				local gt = goal.target:FindFirstChild("Torso")
				if gt and gt:IsA("BasePart") then
					local to = gt.Position - npc.torso.Position
					npc.fleeing = false
					npc.target = goal.target
					npc.face = MathUtil.SafeUnit(MathUtil.Flat(to), npc.face)
					if to.Magnitude < 16 and math.abs(to.Y) < 4 then
						-- close: straight at them, where they are going
						npc.moveDir = MathUtil.SafeUnit(MathUtil.Flat(to + gt.AssemblyLinearVelocity * 0.3), npc.face)
						npc.moveSpeed = Config.NPCSprintSpeed
					else
						walkTo(npc, gt.Position, Config.NPCSprintSpeed, 3, 0.8)
					end
					return
				end
			elseif kind == "flee" and goal.from then
				local ft = goal.from:FindFirstChild("Torso")
				if ft and ft:IsA("BasePart") and (ft.Position - npc.torso.Position).Magnitude < 60 then
					npc.target = goal.from
					flee(npc, goal.from)
					return
				end
			end
			-- nothing close: wander about
			npc.fleeing = false
			if rng:NextNumber() < 0.06 or npc.moveDir.Magnitude < 0.1 then
				local a = rng:NextNumber(0, math.pi * 2)
				npc.moveDir = Vector3.new(math.cos(a), 0, math.sin(a))
			end
			npc.moveSpeed = Config.NPCWalkSpeed * 0.7
			npc.face = MathUtil.SafeUnit(npc.moveDir, npc.face)
			return
		elseif kind == "goto" and goal.pos then
			local to = MathUtil.Flat(goal.pos - npc.torso.Position)
			if to.Magnitude > (goal.radius or 6) then
				-- on the way there: it shoots whoever it sees but keeps going
				npc.fleeing = false
				npc.crouch = false
				npc.cover = nil
				walkTo(npc, goal.pos, Config.NPCSprintSpeed)
				local tt = target and target:FindFirstChild("Torso")
				if visible and tt and tt:IsA("BasePart") and npc.weapon and Config.Guns[npc.weaponKind] and not npc.reloading then
					if now - npc.lastSeen > 1.5 then
						npc.seenSince = now
					end
					npc.lastSeen = now
					npc.face = MathUtil.SafeUnit(MathUtil.Flat(tt.Position - npc.torso.Position), npc.face)
					npc.aimAt = tt.Position
					if now - npc.seenSince > Config.NPCReaction then
						shoot(npc, tt.Position)
					end
				else
					npc.aimAt = nil
					npc.face = MathUtil.SafeUnit(npc.moveDir, npc.face)
				end
				return
			end
			npc.holdPos = goal.pos -- (there: it fights from here and does not walk off after anybody)
		end
	end
	-- (v2.0) the boxer: fists only. It closes in, keeps its guard up, throws jabs (left, right) and now and then a
	-- big haymaker that knocks you down; it backs off a step after a combo
	if npc.boxer then
		npc.fleeing = false
		npc.crouch = false
		npc.aimAt = nil
		if not target then
			npc.moveDir = Vector3.zero
			return
		end
		local bt = target:FindFirstChild("Torso") :: BasePart
		local to = bt.Position - npc.torso.Position
		npc.face = MathUtil.SafeUnit(MathUtil.Flat(to), npc.face)
		local reach = Config.BoxerReach
		if to.Magnitude < reach then
			npc.moveDir = Vector3.zero
			if now - npc.swingT0 > Config.BoxerPunchEvery then
				npc.swingT0 = now
				npc.punchSide = -(npc.punchSide or 1)
				local heavy = rng:NextNumber() < 0.25
				local victim = target
				local side = npc.punchSide
				-- the arm shoots out (a jab the body throws), the hit lands a moment later
				local armName = side > 0 and "Right Arm" or "Left Arm"
				local armPart = npc.model:FindFirstChild(armName)
				if armPart and armPart:IsA("BasePart") and not npc.model:GetAttribute(side > 0 and "Severed_RightArm" or "Severed_LeftArm") then
					pcall(function()
						armPart:ApplyImpulse(MathUtil.SafeUnit(to, npc.face) * (heavy and 70 or 45) * armPart:GetMass())
						npc.torso:ApplyImpulse(MathUtil.Flat(to).Unit * (heavy and 14 or 6) * npc.torso:GetMass())
					end)
				else
					return
				end
				task.delay(0.14, function()
					local vt = victim:FindFirstChild("Torso")
					if npc.state ~= "Active" or not vt or not vt:IsA("BasePart") or (vt.Position - npc.torso.Position).Magnitude > reach + 1.2 then
						GoreService.Sound("weave", npc.torso, 0.6) -- (whiff)
						return
					end
					if DamageService.Dodged(victim) then
						return -- (slipped: weave)
					end
					local region = rng:NextNumber() < 0.35 and "Head" or "Torso"
					local hp = victim:FindFirstChild(region == "Head" and "Head" or "Torso")
					local point = (hp and hp:IsA("BasePart")) and hp.Position or vt.Position
					local dir = MathUtil.SafeUnit(MathUtil.Flat(vt.Position - npc.torso.Position), npc.face)
					DamageService.MarkBotAttacker(victim, npc.model)
					DamageService.ApplyDamage(victim, region, (heavy and Config.BoxerHeavyDamage or Config.BoxerPunchDamage) * (Config.LimbMultiplier[region] or 1), point, {
						cause = "Knocked out by a boxer",
						allowSever = false,
					})
					GoreService.Sound(heavy and "punchBoom" or "punch", point, heavy and 0.6 or 1)
					if heavy then
						DamageService.Blast(victim, dir * 52 + Vector3.new(0, 16, 0), 2.2)
					else
						DamageService.Knock(victim, region, dir * 22 * DamageService.PartMass(victim, region), region == "Head" and 0.8 or nil, point)
					end
				end)
			end
		elseif visible and to.Magnitude < 18 then
			-- bob and weave on the way in
			local sideStep = MathUtil.Flat(to):Cross(Vector3.yAxis).Unit * math.sin(now * 3 + npc.torso.Position.X) * 0.6
			npc.moveDir = MathUtil.SafeUnit(MathUtil.Flat(to).Unit + sideStep, Vector3.zero)
			npc.moveSpeed = Config.NPCRunSpeed * 0.95
		else
			walkTo(npc, bt.Position, Config.NPCRunSpeed)
		end
		return
	end
	-- (v2.0) a zombie: no weapon, no fear. Shamble at them, arms out, and bite
	if npc.zombie then
		npc.fleeing = false
		npc.crouch = false
		npc.aimAt = nil
		-- (v2.0) hunters, not stalkers: always after the closest one, wherever they are, straight at them
		local prey = zombiePrey(npc)
		if prey then
			target = prey
			npc.target = prey
			local pt = prey:FindFirstChild("Torso") :: BasePart
			visible = clearLine(npc.head.Position, pt.Position, ignoreList(npc, prey))
		end
		if not target then
			npc.moveDir = Vector3.zero
			return
		end
		local zt = target:FindFirstChild("Torso") :: BasePart
		local to = zt.Position - npc.torso.Position
		npc.face = MathUtil.SafeUnit(MathUtil.Flat(to), npc.face)
		-- (v2.0) a long leap at you from a distance - teeth first
		if visible and not npc.crawling and npc.state == "Active" and to.Magnitude > 7 and to.Magnitude < Config.ZombieLeapRange and now > npc.nextLeap and math.abs(to.Y) < 6 then
			leap(npc, target)
			return
		end
		if to.Magnitude < Config.NPCMeleeReach then
			npc.moveDir = Vector3.zero
			if now - npc.swingT0 > Config.ZombieBiteEvery then
				npc.swingT0 = now
				local victim = target
				task.delay(0.2, function()
					local vt = victim:FindFirstChild("Torso")
					if npc.state == "Active" and vt and vt:IsA("BasePart") and (vt.Position - npc.torso.Position).Magnitude < Config.NPCMeleeReach + 1.2 then
						GoreService.Sound("zombieBite", vt.Position, 1)
						DamageService.MarkBotAttacker(victim, npc.model)
						DamageService.ApplyDamage(victim, "Torso", Config.ZombieBiteDamage, vt.Position, { cause = "Eaten by zombies", allowSever = false, bleed = 0.6, bleedTime = 12 })
						if NPCService.OnZombieBite then
							NPCService.OnZombieBite(npc.model, victim)
						end
					end
				end)
			end
		elseif visible and math.abs(to.Y) < 5 then
			-- in sight: straight at them, aiming where they are going (no going round the side, no waiting)
			local lead = zt.AssemblyLinearVelocity * math.clamp(to.Magnitude / 30, 0, 0.6)
			npc.moveDir = MathUtil.SafeUnit(MathUtil.Flat(to + lead), MathUtil.Flat(to).Unit)
			npc.moveSpeed = (to.Magnitude > 22 and Config.NPCSprintSpeed or Config.NPCRunSpeed) * Config.ZombieBotSpeed
		else
			-- out of sight: the shortest way to them, the path redone as soon as they move
			walkTo(npc, zt.Position, Config.NPCSprintSpeed * Config.ZombieBotSpeed, 3, 0.8)
		end
		if now > (npc.nextGroan or 0) then
			npc.nextGroan = now + rng:NextNumber(4, 9)
			GoreService.Sound("zombieGroan", npc.torso, 0.9)
		end
		return
	end
	-- nothing to fight with / nearly dead: get a weapon or run (a runner going for the sniper: on with its fists)
	if not npc.weapon and not chasing then
		if unarmed(npc, target) then
			return
		end
		if target then
			flee(npc, target)
		else
			npc.fleeing = false
			npc.moveDir = Vector3.zero
		end
		return
	end
	if totalHP(npc.model) < Config.NPCFleeHP and target and not chasing and not npc.holdPos then
		flee(npc, target)
		return
	end
	npc.fleeing = false
	if not target then
		-- nobody around: stand still, look around a little; top up the gun
		npc.moveDir = Vector3.zero
		npc.aimAt = nil
		npc.crouch = false
		npc.face = CFrame.Angles(0, math.sin(now * 0.4) * 0.02, 0):VectorToWorldSpace(npc.face)
		local st = Config.Guns[npc.weaponKind]
		if st and npc.ammo < st.mag then
			NPCService.StartReload(npc)
		end
		return
	end
	local tt = target:FindFirstChild("Torso") :: BasePart
	local tpos = tt.Position
	local pos = npc.torso.Position
	local dist = (tpos - pos).Magnitude
	if visible then
		if now - npc.lastSeen > 1.5 then
			npc.seenSince = now
		end
		npc.lastSeen = now
	end
	npc.face = MathUtil.SafeUnit(MathUtil.Flat(tpos - pos), npc.face)

	if npc.kind == "throw" then
		-- (v2.0) steel balls: it keeps a throwing distance, leads you and throws hard and straight
		npc.crouch = false
		npc.aimAt = visible and tpos or nil
		if visible and dist < Config.SteelBallRange * 0.4 then
			if now >= npc.nextShot and dist > 3 then
				npc.nextShot = now + Config.SteelBallCooldown * rng:NextNumber(2.4, 4)
				local key = npc.weaponSide == "Left" and "LeftArm" or "RightArm"
				local L = npc.limbs[key]
				local origin = (L and L.part.CFrame:PointToWorldSpace(Vector3.new(0, -1.1, 0))) or (npc.head.Position + npc.face * 1.5)
				local lead = tt.AssemblyLinearVelocity * (dist / Config.SteelBallSpeed)
				local drop = Vector3.new(0, 0.5 * TimeScale.Gravity() * Config.SteelBallGravity * (dist / Config.SteelBallSpeed) ^ 2, 0)
				local aim = tpos + lead + drop + Vector3.new(0, rng:NextNumber() < 0.2 and 1.4 or 0.2, 0)
				local s = math.rad(Config.NPCAccuracy * 0.8)
				local dir = (CFrame.lookAt(Vector3.zero, (aim - origin).Unit) * CFrame.Angles(rng:NextNumber(-s, s), rng:NextNumber(-s, s), 0)).LookVector
				if L then
					pcall(function()
						L.part:ApplyImpulse(dir * 40 * L.part.AssemblyMass) -- (the throwing arm snaps forward)
					end)
				end
				if NPCService.OnBotThrow then
					NPCService.OnBotThrow(npc.model, origin, dir)
				end
			end
			if dist > 45 then
				walkTo(npc, tpos, Config.NPCRunSpeed)
			elseif dist < 10 then
				npc.moveDir = MathUtil.SafeUnit(MathUtil.Flat(pos - tpos), Vector3.zero)
				npc.moveSpeed = Config.NPCRunSpeed * 0.8
			else
				if now > npc.strafeUntil then
					npc.strafeUntil = now + rng:NextNumber(0.8, 2)
					npc.strafe = rng:NextNumber() < 0.5 and -1 or 1
				end
				npc.moveDir = MathUtil.SafeUnit(npc.face:Cross(Vector3.yAxis) * npc.strafe, Vector3.zero)
				npc.moveSpeed = Config.NPCWalkSpeed
			end
		else
			walkTo(npc, tpos, dist > 60 and Config.NPCSprintSpeed or Config.NPCRunSpeed)
		end
		return
	end
	if npc.kind == "melee" then
		npc.crouch = false
		npc.aimAt = nil
		if dist < Config.NPCMeleeReach then
			npc.moveDir = Vector3.zero
			swing(npc, target)
		elseif visible and not npc.crawling and npc.state == "Active" and dist > 6 and dist < Config.NPCLeapRange and now > npc.nextLeap and math.abs(tpos.Y - pos.Y) < 4 then
			leap(npc, target)
		elseif visible and dist < 14 then
			npc.moveDir = MathUtil.SafeUnit(MathUtil.Flat(tpos - pos), Vector3.zero)
			npc.moveSpeed = Config.NPCRunSpeed
		else
			walkTo(npc, tpos, dist > 40 and Config.NPCSprintSpeed or Config.NPCRunSpeed)
		end
		return
	end
	-- out of ammo / few left and nobody in sight: reload now
	local stats = Config.Guns[npc.weaponKind]
	if stats and not npc.reloading and (npc.ammo <= 0 or (not visible and npc.ammo < stats.mag * 0.4)) then
		NPCService.StartReload(npc)
	end
	if npc.reloading then
		-- duck while reloading (behind cover if it has some)
		npc.aimAt = nil
		npc.crouch = true
		if npc.cover and MathUtil.Flat(npc.cover - pos).Magnitude > 1.8 and now < npc.coverUntil then
			npc.crouch = false
			walkTo(npc, npc.cover, Config.NPCSprintSpeed)
		else
			npc.moveDir = Vector3.zero
		end
		return
	end

	-- gunman
	local head = target:FindFirstChild("Head")
	local aimPoint = (head and head:IsA("BasePart") and rng:NextNumber() < 0.25) and head.Position or tpos
	npc.aimAt = visible and aimPoint or nil
	local canFire = visible and now - npc.seenSince > Config.NPCReaction

	-- taking cover: crouch behind it, pop up to shoot, duck again
	if npc.cover and now < npc.coverUntil then
		local toCover = MathUtil.Flat(npc.cover - pos)
		if toCover.Magnitude > 1.8 then
			npc.crouch = false
			walkTo(npc, npc.cover, Config.NPCSprintSpeed)
			if canFire then
				shoot(npc, aimPoint)
			end
			return
		end
		npc.moveDir = Vector3.zero
		if now < npc.peekUntil then
			npc.crouch = false
			if canFire then
				shoot(npc, aimPoint)
			end
		else
			npc.crouch = true
			npc.aimAt = nil
			if now > npc.peekUntil + rng:NextNumber(1.2, 2.6) then
				npc.peekUntil = now + rng:NextNumber(1.4, 2.6)
			end
		end
		return
	end
	npc.cover = nil
	npc.crouch = false
	-- look for cover now and then (more often when hurt)
	local hurt = totalHP(npc.model) < 420
	if visible and now > npc.nextCover and dist < 140 then
		npc.nextCover = now + rng:NextNumber(hurt and 3 or 6, hurt and 6 or 12)
		if rng:NextNumber() < (hurt and 0.85 or 0.5) then
			local spot = findCover(npc, tpos)
			if spot then
				npc.cover = spot
				npc.coverUntil = now + rng:NextNumber(7, 14)
				npc.peekUntil = now + 0.5
				return
			end
		end
	end
	local near, far = Config.NPCShootRange[1], Config.NPCShootRange[2]
	if npc.weaponKind == "shotgun" then
		near, far = 6, 22
	elseif npc.weaponKind == "sniper" then
		near, far = 40, 200
	elseif npc.weaponKind == "launcher" or npc.weaponKind == "lockon" then
		near, far = 26, 220 -- (v2.0: never at point blank)
	elseif npc.weaponKind == "taser" then
		near, far = 4, 30
	elseif npc.weaponKind == "flaregun" or npc.weaponKind == "harpoon" or npc.weaponKind == "sleepdart" then
		near, far = 8, 90
	end
	if (not visible or dist > far) and npc.holdPos then
		-- (holding a spot: it stays there)
		local back = MathUtil.Flat((npc.holdPos :: Vector3) - pos)
		npc.moveDir = back.Magnitude > 3 and back.Unit or Vector3.zero
		npc.moveSpeed = Config.NPCRunSpeed
	elseif not visible or dist > far then
		walkTo(npc, tpos, dist > far + 30 and Config.NPCSprintSpeed or Config.NPCRunSpeed)
	elseif dist < near then
		-- too close: back off while shooting
		npc.moveDir = MathUtil.SafeUnit(MathUtil.Flat(pos - tpos), Vector3.zero)
		npc.moveSpeed = Config.NPCWalkSpeed
	else
		-- in range: strafe a little
		if now > npc.strafeUntil then
			npc.strafeUntil = now + rng:NextNumber(1, 2.5)
			npc.strafe = rng:NextNumber() < 0.5 and -1 or (rng:NextNumber() < 0.5 and 1 or 0)
		end
		local side = npc.face:Cross(Vector3.yAxis)
		npc.moveDir = MathUtil.SafeUnit(side * npc.strafe, Vector3.zero)
		npc.moveSpeed = Config.NPCWalkSpeed * 0.6
	end
	if canFire then
		shoot(npc, aimPoint)
	end
end

function NPCService.Init()
	DamageService.OnRagdoll = function(model: Model, t: number)
		if npcs[model] then
			NPCService.Ragdoll(model, t)
		end
	end
	RunService.Heartbeat:Connect(function(dt)
		dt = math.min(dt, 1 / 20)
		local now = os.clock()
		for model, npc in npcs do
			if not model.Parent or not npc.torso.Parent then
				continue
			end
			if (model:GetAttribute("TemporalFrozenUntil") or 0) > workspace:GetServerTimeNow() then continue end
			local ts = TimeScale.ForField(nil, npc.torso.Position)
			if npc.state ~= "Dead" and now >= npc.nextThink then
				npc.nextThink = now + 0.2 / ts
				think(npc)
			end
			bodyStep(npc, dt * ts)
			if npc.torso.Position.Y < -200 and not Config.InPit(npc.torso.Position) then
				model:Destroy()
			end
		end
	end)
end

return NPCService
