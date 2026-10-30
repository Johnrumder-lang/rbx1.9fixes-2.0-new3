--!nonstrict
-- PropService: sandbox spawn menu (crates, metal blocks, balls, planks, dummies...).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PropCatalog = require(Shared:WaitForChild("PropCatalog"))
local Items = require(Shared:WaitForChild("Items"))
local Skins = require(Shared:WaitForChild("Skins"))

local DummyService = require(script.Parent:WaitForChild("DummyService"))
local NPCService = require(script.Parent:WaitForChild("NPCService"))
local PropBuilders = require(script.Parent:WaitForChild("PropBuilders"))

local SandboxRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Sandbox") :: RemoteEvent

local PropService = {}

-- set by Main: called with every placed prop (cars get registered with VehicleService)
PropService.OnPlaced = nil :: ((Instance) -> ())?

local GRID_TEXTURE = "rbxassetid://6372755229"
local lastSpawn: { [Player]: number } = {}

local function propFolder(): Folder
	local f = workspace:FindFirstChild("SpawnedProps")
	if not f then
		f = Instance.new("Folder")
		f.Name = "SpawnedProps"
		f.Parent = workspace
	end
	return f :: Folder
end

local function ownedProps(player: Player): { Instance }
	local list = {}
	for _, p in propFolder():GetChildren() do
		if p:GetAttribute("Spawner") == player.UserId then
			table.insert(list, p)
		end
	end
	return list
end

local function addGrid(part: BasePart, transparency: number)
	for _, face in Enum.NormalId:GetEnumItems() do
		local t = Instance.new("Texture")
		t.Texture = GRID_TEXTURE
		t.Face = face
		t.StudsPerTileU = 4
		t.StudsPerTileV = 4
		t.Transparency = transparency
		t.Color3 = Color3.new(0, 0, 0)
		t.Parent = part
	end
end

-- set by GameModeService: may this player spawn things right now?
PropService.CanSpawn = nil :: ((Player) -> boolean)?

function PropService.Build(item, cf: CFrame): Instance
	if item.builder then
		local builder = PropBuilders[item.builder]
		local inst = builder(cf)
		if item.skin then
			Skins.Apply(inst, item.skin) -- (v2.0: the same weapon, another look)
		end
		return inst
	end
	local p = Instance.new("Part")
	p.Name = item.name
	p.Shape = item.shape or Enum.PartType.Block
	p.Size = item.size
	p.Color = item.color
	p.Material = item.material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CustomPhysicalProperties = PhysicalProperties.new(item.density, item.friction or 0.5, item.elasticity or 0.15, 1, 1)
	p.CFrame = cf
	if item.grid then
		addGrid(p, 0.78)
	end
	return p
end

-- Place a prop in the world (used by the spawn menu and by map markers).
function PropService.Place(itemId: string, cf: CFrame, spawner: Player?): Instance?
	local item = PropCatalog.ById[itemId]
	if not item then
		return nil
	end
	if item.dummy then
		return DummyService.Spawn(cf, spawner and spawner.UserId or nil)
	end
	if item.npc then
		return NPCService.Spawn(item.npc, cf, spawner)
	end
	local inst = PropService.Build(item, cf)
	if spawner then
		inst:SetAttribute("Spawner", spawner.UserId)
	end
	inst.Parent = propFolder()
	if spawner and not item.car then
		local root = inst:IsA("Model") and inst.PrimaryPart or inst
		pcall(function()
			(root :: BasePart):SetNetworkOwner(spawner)
		end)
	end
	if PropService.OnPlaced then
		PropService.OnPlaced(inst)
	end
	return inst
end

local function spawnFor(player: Player, itemId: string)
	if player.Character and player.Character:GetAttribute("ControlActive") then return end
	if itemId == "stillwater_set" then
		local sword = require(script.Parent.StillCutService)
		if not (sword.Owns and sword.Owns(player)) then player:SetAttribute("SpawnDenied", "Complete the Stillwater quest first.|" .. os.clock()); return end
		if os.clock() - (lastSpawn[player] or 0) < 2 then return end
		lastSpawn[player] = os.clock()
		sword.GiveGear(player); player:SetAttribute("StillwaterSummoned", true)
		return
	end
	local item = PropCatalog.ById[itemId]
	if not item or (item.ownerOnly and not Items.Has(player, item.id)) then
		return
	end
	-- (v2.0) a skin: only whoever unlocked it (RewardService sets Skin_<id>; admins have them all)
	if item.skin and player:GetAttribute("Skin_" .. item.skin) ~= true and not Items.IsOwner(player) then
		return
	end
	-- (v2.1) needs = a player attribute that must be true (the Black Ledger: LedgerUnlocked); the owner always may
	if (item.needs and player:GetAttribute(item.needs) ~= true and not Items.IsOwner(player)) or (item.adminOnly and not Items.IsOwner(player)) then
		player:SetAttribute("SpawnDenied", item.name .. "|" .. tostring(os.clock())) -- (the client says why)
		return
	end
	-- a game mode is running / the owner switched spawning off
	if PropService.CanSpawn and not PropService.CanSpawn(player) then
		return
	end
	local now = os.clock()
	if now - (lastSpawn[player] or 0) < Config.PropSpawnCooldown then
		return
	end
	lastSpawn[player] = now

	local char = player.Character
	local torso = char and char:FindFirstChild("Torso") :: BasePart?
	if not torso then
		return
	end
	local look = torso.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
	local dist = 3 + item.size.Magnitude * 0.5
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local hit = workspace:Raycast(torso.Position, look * dist, params)
	if hit then
		dist = math.max(1.5, hit.Distance - item.size.Magnitude * 0.5)
	end
	local pos = torso.Position + look * dist + Vector3.new(0, item.size.Y * 0.5 + 1.5, 0)
	if item.car then
		-- put the car straight on its wheels (no drop)
		local down = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), params)
		if down then
			pos = down.Position + Vector3.new(0, (item :: any).ride or 2.2, 0)
		end
	end
	local cf = CFrame.lookAlong(pos, look)

	local owned = ownedProps(player)
	if item.car then
		local cars = {}
		for _, o in owned do
			if o:GetAttribute("Car") then
				table.insert(cars, o)
			end
		end
		if #cars >= Config.MaxCarsPerPlayer then
			cars[1]:Destroy()
		end
	elseif not item.dummy and not item.npc and #owned >= Config.MaxPropsPerPlayer then
		owned[1]:Destroy()
	end
	PropService.Place(itemId, cf, player)
end

local function clearFor(player: Player)
	for _, p in ownedProps(player) do
		p:Destroy()
	end
	local dummies = workspace:FindFirstChild("Dummies")
	if dummies then
		for _, d in dummies:GetChildren() do
			if d:GetAttribute("Spawner") == player.UserId then
				d:Destroy()
			end
		end
	end
	local gibs = workspace:FindFirstChild("Gibs")
	if gibs then
		gibs:ClearAllChildren()
	end
end

function PropService.Init()
	SandboxRemote.OnServerEvent:Connect(function(player, action, itemId)
		if action == "spawn" and typeof(itemId) == "string" then
			spawnFor(player, itemId)
		elseif action == "clear" then
			clearFor(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		clearFor(player)
		lastSpawn[player] = nil
	end)
end

return PropService
