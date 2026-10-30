--!nonstrict
-- CharacterService: spawns every player as an R6 active ragdoll (with their own avatar),
-- handles death, corpses and respawning.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Modules = script.Parent
local RigBuilder = require(Modules:WaitForChild("RigBuilder"))
local BodyFactory = require(Modules:WaitForChild("BodyFactory"))
local DamageService = require(Modules:WaitForChild("DamageService"))
local OwnershipService = require(Modules:WaitForChild("OwnershipService"))
local ServerImpactSensor = require(Modules:WaitForChild("ServerImpactSensor"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ResetRemote = Remotes:WaitForChild("Reset") :: RemoteEvent

local CharacterService = {}

-- set by GameModeService: where a player spawns during a round (a team spawn, the lobby), what
-- happens right after the spawn (a gun in the hand) and when a player dies
CharacterService.SpawnOverride = nil :: ((Player) -> CFrame?)?
CharacterService.OnSpawned = nil :: ((Player, Model) -> ())?
CharacterService.OnDied = nil :: ((Player, Model) -> ())?
CharacterService.RespawnHook = nil :: ((Player, Model) -> boolean)? -- (v2.8.1) true = it brings the player back itself (REGROWTH)
CharacterService.SpawnPose = nil :: ((Player, Model) -> ())? -- (v2.8.2) lays a new body out before it is in the world (REGROWTH)

local descriptionCache: { [Player]: HumanoidDescription } = {}
local corpses: { [Player]: { Model } } = {}
local spawning: { [Player]: boolean } = {}
local rng = Random.new()

local function corpseFolder(): Folder
	local f = workspace:FindFirstChild("Corpses")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Corpses"
		f.Parent = workspace
	end
	return f :: Folder
end

local function getSpawnCFrame(): CFrame
	-- (v2.8) two spawns in the sandbox (the old one and the one at the tower): one of them at random
	local spawnPart: BasePart? = nil
	local map = workspace:FindFirstChild("Map")
	local pads = {}
	for _, d in (map and map:GetDescendants() or {}) do
		if d:IsA("SpawnLocation") then
			table.insert(pads, d)
		end
	end
	if #pads > 0 then
		spawnPart = pads[rng:NextInteger(1, #pads)]
	else
		for _, d in workspace:GetDescendants() do
			if d:IsA("SpawnLocation") then
				spawnPart = d
				break
			end
		end
	end
	local base = spawnPart and spawnPart.Position + Vector3.new(0, spawnPart.Size.Y * 0.5, 0) or Vector3.new(0, 1, 0)
	local offset = Vector3.new(rng:NextNumber(-3, 3), 3.15, rng:NextNumber(-3, 3))
	return CFrame.new(base + offset) * CFrame.Angles(0, math.rad(180), 0)
end

local function getDescription(player: Player): HumanoidDescription
	local cached = descriptionCache[player]
	if cached then
		return cached:Clone()
	end
	local desc: HumanoidDescription? = nil
	if player.UserId > 0 then
		local ok, result = pcall(function()
			return (Players :: any):GetHumanoidDescriptionFromUserIdAsync(player.UserId)
		end)
		if not ok then
			ok, result = pcall(function()
				return (Players :: any):GetHumanoidDescriptionFromUserId(player.UserId)
			end)
		end
		if ok and typeof(result) == "Instance" and result:IsA("HumanoidDescription") then
			desc = result :: any
		end
	end
	local final = desc or Instance.new("HumanoidDescription")
	descriptionCache[player] = final
	return final:Clone()
end

local function createModel(desc: HumanoidDescription): Model
	local ok, model = pcall(function()
		return (Players :: any):CreateHumanoidModelFromDescriptionAsync(desc, Enum.HumanoidRigType.R6)
	end)
	if not ok or typeof(model) ~= "Instance" then
		ok, model = pcall(function()
			return (Players :: any):CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
		end)
	end
	if ok and typeof(model) == "Instance" and model:IsA("Model") and model:FindFirstChild("Torso") then
		return model :: any
	end
	warn("[Ragdoll] avatar load failed, using a blocky body:", model)
	return BodyFactory.BuildR6({ name = "Player", humanoid = true })
end

local function cleanupCorpses(player: Player)
	local list = corpses[player]
	if not list then
		return
	end
	for _, c in list do
		c:Destroy()
	end
	corpses[player] = nil
end

local function turnIntoCorpse(player: Player, model: Model)
	if not model.Parent then
		return
	end
	model.Name = player.Name .. "'s corpse"
	model.Parent = corpseFolder()
	model:SetAttribute("Knocked", true)
	-- (v2.0) a body that was dragged while it was still a character: the dragger holds it like a dummy now
	OwnershipService.BecameCorpse(model)
	-- someone dragging the body keeps it; otherwise the server simulates the corpse
	if not OwnershipService.IsDragged(model) and not OwnershipService.IsHeldBody(model) then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and not d.Anchored then
				pcall(function()
					d:SetNetworkOwner(nil)
				end)
			end
		end
	end
	ServerImpactSensor.Add(model)
	if model:GetAttribute("Impaled") then
		DamageService.ReattachImpales(model)
	end
	local list = corpses[player] or {}
	corpses[player] = list
	table.insert(list, model)
	while #list > Config.MaxCorpsesPerPlayer do
		local old = table.remove(list, 1)
		if old then
			old:Destroy()
		end
	end
	Debris:AddItem(model, Config.CorpseLifetime)
end

-- fresh: a new body right now (a round starts); the old body is removed, not left as a corpse
function CharacterService.Spawn(player: Player, fresh: boolean?)
	if spawning[player] or not player.Parent then
		return
	end
	spawning[player] = true

	local previous = player.Character
	if fresh and previous then
		-- (it disappears as soon as the new body is there; until then nothing can hurt it)
		OwnershipService.ReleaseAll(player)
		OwnershipService.VictimDied(previous)
		previous:SetAttribute("God", true)
	end
	local desc = getDescription(player)
	local model = createModel(desc)
	if not player.Parent then
		model:Destroy()
		spawning[player] = nil
		return
	end
	model.Name = player.Name

	-- no default animation / health scripts: the body is driven by physics
	for _, d in model:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end

	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.PlatformStand = true
	hum.WalkSpeed = 0
	hum.UseJumpPower = true
	hum.JumpPower = 0
	hum.AutoRotate = false
	hum.MaxHealth = 100
	hum.Health = 100
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	-- (v2.0) no default name over the head: TitleClient draws the name and the equipped title
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	RigBuilder.Build(model, { colliders = true, muscles = true })
	model:SetAttribute("OwnerUserId", player.UserId)
	-- (v2.0) spawn protection: nothing hurts you for the first seconds (a shimmer shows it)
	if Config.SpawnProtection > 0 then
		model:SetAttribute("SpawnProtect", workspace:GetServerTimeNow() + Config.SpawnProtection)
		local ff = Instance.new("ForceField")
		ff.Name = "SpawnProtection"
		ff.Visible = true
		ff.Parent = model
		task.delay(Config.SpawnProtection, function()
			if ff.Parent then
				ff:Destroy()
			end
		end)
	end

	local spawnCF = (CharacterService.SpawnOverride and CharacterService.SpawnOverride(player)) or getSpawnCFrame()
	model:PivotTo(spawnCF)
	local balance = model.Rig:FindFirstChild("Balance")
	if balance and balance:IsA("AlignOrientation") then
		balance.CFrame = spawnCF.Rotation
	end
	if CharacterService.SpawnPose then
		pcall(CharacterService.SpawnPose, player, model)
	end
	model.Parent = workspace
	player.Character = model

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not d.Anchored then
			pcall(function()
				d:SetNetworkOwner(player)
			end)
		end
	end

	local died = false
	DamageService.Register(model, {
		player = player,
		humanoid = hum,
		onDeath = function(_cause)
			if died then
				return
			end
			died = true
			OwnershipService.VictimDied(model) -- (dragged: the dragger keeps the corpse)
			OwnershipService.ReleaseAll(player)
			if CharacterService.OnDied then
				task.spawn(CharacterService.OnDied, player, model)
			end
			-- (v2.8.1) REGROWTH tier 3: the body grows back where it lies (RegrowthService brings the player back)
			local hooked = false
			if CharacterService.RespawnHook then
				local ok, r = pcall(CharacterService.RespawnHook, player, model)
				hooked = ok and r == true
			end
			if not hooked then
				task.delay(Config.RespawnTime, function()
					if player.Parent and player.Character == model then
						CharacterService.Spawn(player)
					end
				end)
			end
		end,
	})
	hum.Died:Connect(function()
		DamageService.Kill(model, model:GetAttribute("DeathCause") or "Died")
	end)

	if previous and previous ~= model then
		if fresh then
			DamageService.Unregister(previous)
			previous:Destroy()
		else
			turnIntoCorpse(player, previous)
		end
	end
	spawning[player] = nil
	if CharacterService.OnSpawned then
		task.spawn(CharacterService.OnSpawned, player, model)
	end
end

function CharacterService.Init()
	Players.CharacterAutoLoads = false

	ResetRemote.OnServerEvent:Connect(function(player)
		local c = player.Character
		if c and not c:GetAttribute("Dead") then
			DamageService.Kill(c, "Reset")
		elseif not c then
			CharacterService.Spawn(player)
		end
	end)

	local function onPlayer(player: Player)
		task.spawn(CharacterService.Spawn, player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end

	Players.PlayerRemoving:Connect(function(player)
		cleanupCorpses(player)
		descriptionCache[player] = nil
		local c = player.Character
		if c then
			c:Destroy()
		end
	end)
end

return CharacterService
