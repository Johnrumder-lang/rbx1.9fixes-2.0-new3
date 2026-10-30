--!nonstrict
-- RAGDOLL SANDBOX - server entry point.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))
local HitMath = require(Shared:WaitForChild("HitMath"))

local Modules = script.Parent:WaitForChild("Modules")
local WorldSetup = require(Modules:WaitForChild("WorldSetup"))
local DamageService = require(Modules:WaitForChild("DamageService"))
local OwnershipService = require(Modules:WaitForChild("OwnershipService"))
local CharacterService = require(Modules:WaitForChild("CharacterService"))
local PropService = require(Modules:WaitForChild("PropService"))
local DummyService = require(Modules:WaitForChild("DummyService"))
local GunService = require(Modules:WaitForChild("GunService"))
local KnockService = require(Modules:WaitForChild("KnockService"))
local ExplosionService = require(Modules:WaitForChild("ExplosionService"))
local VehicleService = require(Modules:WaitForChild("VehicleService"))
local ItemService = require(Modules:WaitForChild("ItemService"))
local KillService = require(Modules:WaitForChild("KillService"))
local CraneService = require(Modules:WaitForChild("CraneService"))
local NPCService = require(Modules:WaitForChild("NPCService"))
local VirusService = require(Modules:WaitForChild("VirusService"))
local AdminService = require(Modules:WaitForChild("AdminService"))
local CalamityService = require(Modules:WaitForChild("CalamityService"))
local VoteService = require(Modules:WaitForChild("VoteService"))
local WeatherService = require(Modules:WaitForChild("WeatherService"))
local DrownService = require(Modules:WaitForChild("DrownService"))
local FireService = require(Modules:WaitForChild("FireService"))
local LightingService = require(Modules:WaitForChild("LightingService"))
local MapService = require(Modules:WaitForChild("MapService"))
local GameModeService = require(Modules:WaitForChild("GameModeService"))
local SettingsService = require(Modules:WaitForChild("SettingsService"))
local GearService = require(Modules:WaitForChild("GearService"))
local SuperService = require(Modules:WaitForChild("SuperService"))
local FractureService = require(Modules:WaitForChild("FractureService"))
local SteelBallService = require(Modules:WaitForChild("SteelBallService"))
local QuestService = require(Modules:WaitForChild("QuestService"))
local CreatureService = require(Modules:WaitForChild("CreatureService"))
local MapFeatureService = require(Modules:WaitForChild("MapFeatureService"))
local BotDriverService = require(Modules:WaitForChild("BotDriverService"))
local RewardService = require(Modules:WaitForChild("RewardService"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ImpactRemote = Remotes:WaitForChild("Impact") :: RemoteEvent

require(Modules:WaitForChild("ProgressEpoch")).Init()
WorldSetup.Init()
KillService.Init()
OwnershipService.Init()
PropService.Init()
VehicleService.Init()
PropService.OnPlaced = function(inst)
	if inst:IsA("Model") and inst:GetAttribute("Car") then
		VehicleService.Register(inst)
	end
end
ExplosionService.Init()
ItemService.Init()
CraneService.Init()
DummyService.Init()
NPCService.Init()
VirusService.Init()
AdminService.Init()
CalamityService.Init()
VoteService.Init()
if not Config.Lite then
	WeatherService.Init()
end
DrownService.Init()
FireService.Init()
LightingService.Init()
WorldSetup.SpawnMarkers(PropService)
MapService.Init()
CreatureService.Init()
MapFeatureService.Init()
BotDriverService.Init()
RewardService.Init()
-- (v2.1) dollars + weapon skins (Persist keeps them between sessions)
do
	local Persist = require(Modules:WaitForChild("Persist"))
	Persist.Init()
	local SkinService = require(Modules:WaitForChild("SkinService"))
	SkinService.Init(DamageService, OwnershipService)
end
GameModeService.Init()
SettingsService.Init()
-- the owner's / admins' menu (M): the maps, the game modes, spawning for everybody, (v2.0) the admin commands
local function torsoOfPlayer(p: Player?): BasePart?
	local c = p and p.Character
	local t = c and c:FindFirstChild("Torso")
	return (t and t:IsA("BasePart")) and t or nil
end
AdminService.OnCommand = function(player, action, value, extra)
	if action == "bring" or action == "goto" then
		local other = typeof(value) == "number" and Players:GetPlayerByUserId(value) or nil
		local mine, theirs = torsoOfPlayer(player), torsoOfPlayer(other)
		if other and mine and theirs then
			if action == "bring" then
				MapService.Teleport(other, mine.Position + mine.CFrame.LookVector * 4)
			else
				MapService.Teleport(player, theirs.Position + theirs.CFrame.LookVector * 4)
			end
		end
		return
	elseif action == "healall" then
		for _, p in Players:GetPlayers() do
			local c = p.Character
			if c and not c:GetAttribute("Dead") then
				DamageService.Heal(c)
				DamageService.StopBleeding(c)
			end
		end
		return
	elseif action == "respawnall" then
		for _, p in Players:GetPlayers() do
			task.spawn(CharacterService.Spawn, p, true)
		end
		return
	elseif action == "gravity" then
		local g = { moon = 32, low = 80, normal = 196.2, heavy = 400 }
		if typeof(value) == "string" and g[value] then
			workspace.Gravity = g[value]
			workspace:SetAttribute("GravityMode", value)
		end
		return
	elseif action == "timestop" then
		SuperService.TimeStop(player, not SuperService.TimeStopped())
		return
	elseif action == "hotdog" then
		local target = nil
		if typeof(value) == "number" then
			target = Players:GetPlayerByUserId(value)
		elseif typeof(value) == "Vector3" and typeof(extra) == "Vector3" and extra.Magnitude > 0.5 then
			target = SuperService.PickTarget(player, value, extra.Unit)
		end
		if target then
			SuperService.Hotdog(player, target)
		end
		return
	elseif action == "sun" then
		task.spawn(SuperService.FireSun, player)
		return
	elseif action == "bots" and typeof(value) == "boolean" then
		workspace:SetAttribute("BotsEnabled", value)
		return
	elseif action == "botcars" and typeof(value) == "boolean" then
		workspace:SetAttribute("BotCars", value) -- (v2.0) BotDriverService: bots drive cars round the city
		return
	elseif action == "psychosis" and typeof(value) == "boolean" then
		-- (v2.8.2) cyberpsychosis for the whole server: off = no hallucinations, no crash outs, however much chrome
		workspace:SetAttribute("PsychosisOff", (not value) or nil)
		return
	elseif action == "quest" and typeof(value) == "string" then
		QuestService.Admin(player, value) -- (the admin's own questline: "spin" / "reset")
		return
	end
	if action == "map" then
		-- (v2.0) "load:<id>" (city / horror / sea / ikea), "unload", "tomap", "tosandbox"
		local id = typeof(value) == "string" and string.match(value, "^load:(%w+)$") or nil
		if value == "load" then
			id = "city"
		end
		if id and MapService.MAPS[id] then
			if GameModeService.Mode() then
				GameModeService.SetNextMap(id) -- (a round is running: the next round is played there)
			else
				task.spawn(MapService.Load, id)
			end
		elseif value == "unload" then
			if GameModeService.Mode() then
				GameModeService.Stop()
			end
			MapService.Unload()
		elseif value == "tomap" or value == "tocity" then
			MapService.TeleportAll("map")
		elseif value == "tosandbox" then
			MapService.TeleportAll("sandbox")
		end
	elseif action == "mode" then
		if value == "stop" then
			GameModeService.Stop()
		elseif typeof(value) == "string" then
			GameModeService.Start(value)
		end
	elseif action == "spawning" and typeof(value) == "boolean" then
		GameModeService.SetSpawning(value)
	elseif action == "weather" and typeof(value) == "string" then
		WeatherService.Set(value)
	end
end
GunService.OnHitCar = VehicleService.Damage
AdminService.OnWonder = CalamityService.SetWonder
CalamityService.PlaceProp = PropService.Place
ItemService.PlaceProp = PropService.Place
-- (v1.9) what a community vote can do: the same things the owner's menu does
VoteService.Commands = {
	city = function()
		MapService.Load("city")
	end,
	-- (v2.0) a map vote: load it and everybody goes there (a running mode: from the next round on)
	map = function(id: string)
		if not MapService.MAPS[id] then
			return
		end
		if GameModeService.Mode() then
			GameModeService.SetNextMap(id)
			return
		end
		MapService.Load(id)
		MapService.TeleportAll("map")
	end,
	mode = function(modeName: string)
		GameModeService.Start(modeName, true) -- (v2.0: a voted game always fills up with bots)
	end,
	nuke = function(pos: Vector3)
		ItemService.SpawnArmedNuke(pos, nil)
	end,
}
GunService.OnHitPart = VehicleService.OnShotPart
GunService.OnGlass = ExplosionService.Shatter
ItemService.OnGlass = ExplosionService.Shatter
ExplosionService.OnFire = FireService.Ignite
VehicleService.OnRocket = ItemService.LaunchRocket
FireService.OnBarrel = ExplosionService.Detonate
GunService.OnHitExplosive = ExplosionService.Detonate
GunService.OnHitGrenade = ItemService.DetonateExplosive
OwnershipService.OnGrabDriver = VehicleService.Exit
ExplosionService.OnGrenade = ItemService.DetonateExplosive
ExplosionService.OnItemBlast = ItemService.DamageBoombox
GunService.OnHitItem = ItemService.DamageBoombox
ItemService.OnFlash = NPCService.Flash
ExplosionService.OnBlast = ItemService.CutRopesNear
GunService.Init()
KnockService.Init()
GearService.Init()
-- (v2.0) steel balls and the Steel Ball Master's questline
SteelBallService.Init()
SteelBallService.OnGlass = ExplosionService.Shatter
do
	local prevAction = ItemService.OnAction
	ItemService.OnAction = function(player, action, item, a, b, c, d, e)
		if action == "ballthrow" then
			SteelBallService.Throw(player, item, a, b, c)
		elseif prevAction then
			prevAction(player, action, item, a, b, c, d, e)
		end
	end
end
QuestService.Init()
-- (v2.0) bots know every weapon: steel balls, rockets, lock-on missiles, flares
NPCService.OnBotThrow = SteelBallService.BotThrow
NPCService.OnBotProjectile = function(bot: Model, gun: Model, kind: string, origin: Vector3, dir: Vector3, target: Model?)
	local ignore: { Instance } = { bot, gun }
	if kind == "flaregun" then
		GearService.LaunchFlare(origin, dir, ignore, nil, bot)
	elseif kind == "lockon" then
		local t = target and target:FindFirstChild("Torso")
		ItemService.LaunchRocket(origin, dir, nil, ignore, (t and t:IsA("BasePart")) and t or nil, { top = false, bot = bot })
	else
		ItemService.LaunchRocket(origin, dir, nil, ignore, nil, { bot = bot })
	end
end
-- (v2.0) buildings break
FractureService.Init()
ExplosionService.OnFracture = FractureService.Fracture
-- (v2.0) the Crawler digs through walls / ceilings and goes through windows
CreatureService.OnDig = function(part: BasePart, point: Vector3, radius: number, dir: Vector3): boolean
	return FractureService.Fracture(part, point, radius, dir, 60)
end
CreatureService.OnGlass = ExplosionService.Shatter
GunService.OnHitWorld = function(part: BasePart, pos: Vector3, dir: Vector3, k: number, _player: Player?)
	FractureService.Bullet(part, pos, dir, k)
end
SuperService.Init()
-- (v2.1) the Black Ledger and Kuro
require(Modules:WaitForChild("LedgerService")).Init({
	DamageService = DamageService,
	OwnershipService = OwnershipService,
	ItemService = ItemService,
	PropService = PropService,
	GoreService = require(Modules:WaitForChild("GoreService")),
	FireService = FireService,
	ExplosionService = ExplosionService,
	MapService = MapService,
})
-- (v2.1) the Sandevistan: an implant that slows the world
GunService.IsSlow = SuperService.SlowMoActive -- (bullets crawl while the Sandevistan runs)
require(Modules:WaitForChild("SandevistanService")).Init({
	DamageService = DamageService,
	OwnershipService = OwnershipService,
	ItemService = ItemService,
	PropService = PropService,
	SuperService = SuperService,
	GearService = GearService,
	GoreService = require(Modules:WaitForChild("GoreService")),
})
-- (v2.1) body armor: helmet, vest, arm and leg plates that stop bullets
require(Modules:WaitForChild("ArmorService")).Init({
	DamageService = DamageService,
	OwnershipService = OwnershipService,
	ItemService = ItemService,
	GearService = GearService,
	GoreService = require(Modules:WaitForChild("GoreService")),
})
-- (v2.8) cyberware: the implants (CyberService) and the ripperdoc (RipperdocService)
do
	local CyberService = require(Modules:WaitForChild("CyberService"))
	CyberService.Init({
		DamageService = DamageService,
		OwnershipService = OwnershipService,
		GoreService = require(Modules:WaitForChild("GoreService")),
		ExplosionService = ExplosionService,
		GunService = GunService,
		KnockService = KnockService,
		CharacterService = CharacterService,
		SandevistanService = require(Modules:WaitForChild("SandevistanService")),
		NPCService = NPCService,
	})
	-- (v2.8.1) REGROWTH CORE and TITAN arms mend the body
	require(Modules:WaitForChild("RegrowthService")).Init({
		CyberService = CyberService,
		CharacterService = CharacterService,
		RigBuilder = require(Modules:WaitForChild("RigBuilder")),
		GoreService = require(Modules:WaitForChild("GoreService")),
	})
	require(Modules:WaitForChild("VanService")).Init({
		DamageService = DamageService,
		OwnershipService = OwnershipService,
		GoreService = require(Modules:WaitForChild("GoreService")),
		PropService = PropService,
		Remote = CyberService.Remote,
	})
	require(Modules:WaitForChild("BountyService")).Init({
		DamageService = DamageService,
		SkinService = require(Modules:WaitForChild("SkinService")),
		Persist = require(Modules:WaitForChild("Persist")),
	})
	require(Modules:WaitForChild("SeverService")).Init({
		DamageService = DamageService,
		GoreService = require(Modules:WaitForChild("GoreService")),
		Remote = CyberService.Remote,
	})
	-- (v2.8.2) the game records itself: kill replays for the replay chair
	local ReplayService = require(Modules:WaitForChild("ReplayService"))
	ReplayService.Init({
		DamageService = DamageService,
		OwnershipService = OwnershipService,
		GoreService = require(Modules:WaitForChild("GoreService")),
	})
	require(Modules:WaitForChild("HospitalService")).Init({
		DamageService = DamageService,
		GoreService = require(Modules:WaitForChild("GoreService")),
		MapService = MapService,
		Remote = CyberService.Remote,
		ReplayService = ReplayService,
	})
	require(Modules:WaitForChild("RipperdocService")).Init({
		DamageService = DamageService,
		OwnershipService = OwnershipService,
		GoreService = require(Modules:WaitForChild("GoreService")),
		SkinService = require(Modules:WaitForChild("SkinService")),
		PropService = PropService,
		MapService = MapService,
		GearService = GearService,
	})
end
-- (v2.9) the CYBERDECK: chips, netrunner quickhacks, viruses, the Blackwall (ChipService), the video camera
-- (CameraService) and the computers (ComputerService)
do
	local ChipService = require(Modules:WaitForChild("ChipService"))
	ChipService.Init({
		DamageService = DamageService,
		OwnershipService = OwnershipService,
		GoreService = require(Modules:WaitForChild("GoreService")),
		ExplosionService = ExplosionService,
		FireService = FireService,
		VirusService = VirusService,
		PropService = PropService,
		SkinService = require(Modules:WaitForChild("SkinService")),
	})
	local CameraService = require(Modules:WaitForChild("CameraService"))
	CameraService.Init({
		ChipService = ChipService,
		DamageService = DamageService,
		GoreService = require(Modules:WaitForChild("GoreService")),
		OwnershipService = OwnershipService,
	})
	ChipService.Camera = CameraService
	require(Modules:WaitForChild("ComputerService")).Init({
		ChipService = ChipService,
		PropService = PropService,
		PropBuilders = require(Modules:WaitForChild("PropBuilders")),
	})
end
-- (v2.8) the STILLWATER quest: the ritual, the Pit, the Pale Heir, the sword and its STILL CUT
do
	local SwordRemote = Remotes:WaitForChild("Sword") :: RemoteEvent
	local GoreService = require(Modules:WaitForChild("GoreService"))
	local StillCutService = require(Modules:WaitForChild("StillCutService"))
	local RivalService = require(Modules:WaitForChild("RivalService"))
	local SwordQuestService = require(Modules:WaitForChild("SwordQuestService"))
	StillCutService.Init({
		DamageService = DamageService,
		OwnershipService = OwnershipService,
		GoreService = GoreService,
		ExplosionService = ExplosionService,
		SuperService = SuperService,
		SeverService = require(Modules:WaitForChild("SeverService")),
		CharacterService = CharacterService,
		PropBuilders = require(Modules:WaitForChild("PropBuilders")),
		Remote = SwordRemote,
	})
	RivalService.Init({
		DamageService = DamageService,
		GoreService = GoreService,
		NPCService = NPCService,
	})
	SwordQuestService.Init({
		DamageService = DamageService,
		OwnershipService = OwnershipService,
		GoreService = GoreService,
		NPCService = NPCService,
		MapService = MapService,
		FireService = FireService,
		RewardService = RewardService,
		Persist = require(Modules:WaitForChild("Persist")),
		PropBuilders = require(Modules:WaitForChild("PropBuilders")),
		StillCutService = StillCutService,
		RivalService = RivalService,
		Remote = SwordRemote,
	})
	SwordRemote.OnServerEvent:Connect(function(player, action, value)
		if action == "admin" and typeof(value) == "string" then
			SwordQuestService.Admin(player, value)
		end
	end)
end
SuperService.MapAround = function(pos: Vector3): (Vector3, number)
	if MapService.InMap(pos) then
		return MapService.Center(), MapService.Half() * 0.75
	end
	return Vector3.new(0, 0, 0), Config.HotdogRadius
end
-- (v2.0) creatures take bullets, blades and blasts
GunService.OnHitCreature = function(model: Model, part: BasePart, dmg: number, player: Player?, pos: Vector3)
	CreatureService.Damage(model, part, dmg, player, pos)
end
ItemService.OnMeleeCreature = function(model: Model, part: BasePart, dmg: number, player: Player, pos: Vector3)
	CreatureService.Damage(model, part, dmg, player, pos)
end
do
	local prevBlast = ExplosionService.OnBlast
	ExplosionService.OnBlast = function(pos: Vector3, radius: number)
		if prevBlast then
			prevBlast(pos, radius)
		end
		CreatureService.Blast(pos, radius, nil)
	end
end

-- Impacts are measured on the owning client (it runs the exact physics of its body).
-- The server sanity-checks and applies them.
--   ("impact", region, dv, point)
--   ("energy", region, energy, point, otherPart)
--   ("pierce", region, speed, point, spikePart)
--   ("crush",  region, damage, point, otherPart)
local budget: { [Player]: { t: number, n: number } } = {}
ImpactRemote.OnServerEvent:Connect(function(player, kind, region, value, point, other)
	if typeof(kind) ~= "string" or typeof(region) ~= "string" or typeof(value) ~= "number" or value ~= value then
		return
	end
	if not RigInfo.RegionPart[region] or typeof(point) ~= "Vector3" then
		return
	end
	local char = player.Character
	if not char or not char:GetAttribute("RagdollRig") then
		return
	end
	-- NOTE: the server's copy of a falling body lags far behind the client (20+ studs at high
	-- speed), so the contact point is only checked loosely
	local part = char:FindFirstChild(RigInfo.RegionPart[region])
	if not part or (part.Position - point).Magnitude > 120 then
		return
	end
	local now = os.clock()
	local b = budget[player]
	if not b or now - b.t > 1 then
		b = { t = now, n = 0 }
		budget[player] = b
	end
	b.n += 1
	if b.n > 40 then
		return
	end

	if kind == "impact" then
		if value >= Config.ImpactMin and value <= 600 then
			DamageService.ApplyImpact(char, region, value, point)
		end
	elseif kind == "energy" then
		if value > 0 and value < 2e6 then
			DamageService.ApplyEnergy(char, region, value, point, nil, (typeof(other) == "Instance" and other:IsA("BasePart")) and other or nil)
		end
	elseif kind == "crush" then
		if value > 0 and value <= 60 then
			DamageService.ApplyCrush(char, region, value, point)
		end
	elseif kind == "pierce" then
		if typeof(other) ~= "Instance" or not other:IsA("BasePart") or value > 600 then
			return
		end
		-- the server re-checks how sharp the object really is
		local sharp = HitMath.Sharpness(other)
		if sharp <= 0.02 or (other.Position - point).Magnitude > other.Size.Magnitude * 0.6 + 3 then
			return
		end
		if value >= HitMath.PierceThreshold(sharp) * 0.85 then
			DamageService.ApplyPierce(char, region, value, sharp, other, point)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	budget[player] = nil
end)

CharacterService.Init()

-- (v2.8.1) every "talk / use" prompt is on F: E and Q are the hands (a prompt left on its default key E gets F)
local function promptOnF(d: Instance)
	if d:IsA("ProximityPrompt") then
		task.defer(function()
			if d.Parent and d.KeyboardKeyCode == Enum.KeyCode.E then
				d.KeyboardKeyCode = Enum.KeyCode.F
			end
		end)
	end
end
workspace.DescendantAdded:Connect(promptOnF)
for _, d in workspace:GetDescendants() do
	promptOnF(d)
end

print(string.format("[%s %s] server ready", Config.GameName, Config.Version))

require(Modules:WaitForChild("JobService")).Init({ NPCService = NPCService, DamageService = DamageService, SkinService = require(Modules.SkinService) })

require(Modules:WaitForChild("PsychosisService")).Init({ DamageService = DamageService, GunService = GunService, ExplosionService = ExplosionService, OwnershipService = OwnershipService, CyberService = require(Modules.CyberService) })
