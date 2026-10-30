--!nonstrict
-- MapService: the maps. One at a time waits in ServerStorage until it is loaded (owner / admin menu, a vote, a game
-- mode); then it stands far away from the sandbox and the pads link the two ("TeleportPad_City" by the sandbox spawn
-- takes you to the map that is loaded, "TeleportPad_Sandbox" in the map brings you back). Loading another map first
-- sends everybody who is in the old one back to the sandbox, then removes it with all the furniture, cars and items
-- it put there (and whatever people spawned inside it).
-- (v2.0) six maps:
--   city    the city (4 x 4 blocks)
--   horror  Blackwood Asylum: a big dark asylum in a dead forest, fog, a graveyard - and the Crawler on its walls
--   sea     the open sea: a huge ship; fall into the water and an island comes up near you; sharks
--   ikea    the Megastore: a giant furniture store full of props (showrooms, the warehouse, the restaurant)
--   valley  (v2.0) Dust Valley: a desert canyon with a ghost town, the sniper tower in the north, a camp in the south
--   sky     (v2.0) Sky Islands: floating islands joined by plank bridges over a sea of clouds; fall off and the void
--           takes you (MapFeatureService). The big island carries the sniper tower.
-- Every map has: MapSpawn, TeleportPad_Sandbox, ModeSpawn_Red_n / ModeSpawn_Blue_n / ModeSpawn_n, HideSpawn_n,
-- HideWeapon_n, MonsterSpawn_n, ZombieSpawn_n (see build.py); (v2.0) the valley and the sky also SniperSpawn_n,
-- RunnerSpawn_n and HillSpot_n (king of the hill; maps without them use the ModeSpawn_n points). Workspace attributes: MapLoaded = id, CityLoaded.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Modules = script.Parent
local WorldSetup = require(Modules:WaitForChild("WorldSetup"))
local ExplosionService = require(Modules:WaitForChild("ExplosionService"))
local LightingService = require(Modules:WaitForChild("LightingService"))
local PropService = require(Modules:WaitForChild("PropService"))
local FractureService = require(Modules:WaitForChild("FractureService"))

local ModeRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Mode") :: RemoteEvent

local MapService = {}

export type MapDef = { template: string, label: string, center: Vector3, half: number }

MapService.MAPS = {
	city = { template = "CityMap", label = "THE CITY", center = Vector3.new(0, 0, 2600), half = 310 },
	horror = { template = "HorrorMap", label = "BLACKWOOD ASYLUM", center = Vector3.new(2800, 0, 0), half = 420 },
	sea = { template = "SeaMap", label = "THE OPEN SEA", center = Vector3.new(-3000, 0, 0), half = 700 },
	ikea = { template = "IkeaMap", label = "THE MEGASTORE", center = Vector3.new(0, 0, -3300), half = 460 },
	valley = { template = "ValleyMap", label = "DUST VALLEY", center = Vector3.new(2800, 0, 2800), half = 460 },
	sky = { template = "SkyMap", label = "SKY ISLANDS", center = Vector3.new(-3000, 0, 2800), half = 460 },
} :: { [string]: MapDef }
MapService.ORDER = { "city", "horror", "sea", "ikea", "valley", "sky" }

-- (kept for older callers: the city)
MapService.CITY_CENTER = MapService.MAPS.city.center
MapService.CITY_HALF = MapService.MAPS.city.half

-- hooks (CreatureService, SeaService)
MapService.OnLoaded = nil :: ((string, Model) -> ())?
MapService.OnUnloading = nil :: ((string, Model) -> ())?

local current: string? = nil
local loaded: Model? = nil
local markers = nil
local rng = Random.new()
local busy = false

function MapService.Current(): string?
	if loaded and loaded.Parent then
		return current
	end
	return nil
end

function MapService.IsLoaded(): boolean
	return MapService.Current() ~= nil
end

function MapService.Map(): Model?
	return MapService.IsLoaded() and loaded or nil
end
MapService.City = MapService.Map -- (older callers)

function MapService.Def(id: string?): MapDef?
	return id and MapService.MAPS[id] or nil
end

-- the middle of the loaded map (the sandbox: the origin)
function MapService.Center(): Vector3
	local d = MapService.Def(MapService.Current())
	return d and d.center or Vector3.zero
end

function MapService.Half(): number
	local d = MapService.Def(MapService.Current())
	return d and d.half or 500
end

-- is this point inside map `id` (default: the loaded one)?
function MapService.InMap(pos: Vector3, id: string?): boolean
	local d = MapService.Def(id or MapService.Current())
	if not d then
		return false
	end
	local p = pos - d.center
	return math.abs(p.X) < d.half and math.abs(p.Z) < d.half and pos.Y < 400 and pos.Y > -300
end
MapService.InCity = function(pos: Vector3): boolean
	return MapService.InMap(pos)
end

-- which map (id) a point is in, if any
function MapService.MapAt(pos: Vector3): string?
	for id in MapService.MAPS do
		if MapService.InMap(pos, id) then
			return id
		end
	end
	return nil
end

-- where the sandbox spawn is
function MapService.SandboxSpawn(): Vector3
	local map = workspace:FindFirstChild("Map")
	if map then
		local main = map:FindFirstChild("SpawnPad", true) -- (v2.8: the old spawn; the tower has a second one)
		if main and main:IsA("BasePart") then
			return main.Position + Vector3.new(0, main.Size.Y * 0.5, 0)
		end
		for _, d in map:GetDescendants() do
			if d:IsA("SpawnLocation") then
				return d.Position + Vector3.new(0, d.Size.Y * 0.5, 0)
			end
		end
	end
	return Vector3.new(0, 1, 0)
end

function MapService.MapSpawn(): Vector3?
	local c = MapService.Map()
	local p = c and (c:FindFirstChild("MapSpawn", true) or c:FindFirstChild("CitySpawn", true))
	return (p and p:IsA("BasePart")) and p.Position or nil
end
MapService.CitySpawn = MapService.MapSpawn

-- all hidden points of the loaded map whose name starts with `prefix` ("ModeSpawn_Red_", "HideWeapon_", ...)
function MapService.Points(prefix: string): { BasePart }
	local out = {}
	local c = MapService.Map()
	if not c then
		return out
	end
	for _, d in c:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, #prefix) == prefix and string.match(string.sub(d.Name, #prefix + 1), "^%d+$") then
			table.insert(out, d)
		end
	end
	return out
end

-- the player's client moves its own body (it owns it)
function MapService.Teleport(player: Player, pos: Vector3)
	ModeRemote:FireClient(player, "teleport", pos)
end

local function spread(pos: Vector3, r: number): Vector3
	local a = rng:NextNumber(0, math.pi * 2)
	local d = rng:NextNumber(0, r)
	return pos + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
end

local function setPads()
	local sandboxPad = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("TeleportPad_City", true)
	local target = MapService.MapSpawn()
	if sandboxPad and sandboxPad:IsA("BasePart") then
		sandboxPad:SetAttribute("TeleportTo", target)
		local d = MapService.Def(MapService.Current())
		WorldSetup.Label(sandboxPad, (target and d) and ("TO " .. d.label) or "MAP (CLOSED)")
	end
	local c = MapService.Map()
	local mapPad = c and c:FindFirstChild("TeleportPad_Sandbox", true)
	if mapPad and mapPad:IsA("BasePart") then
		-- (v2.0) while a game mode runs there is no way back to the sandbox: the pad is gone
		local modeOn = typeof(workspace:GetAttribute("Mode")) == "string"
		if mapPad:GetAttribute("PadT") == nil then
			mapPad:SetAttribute("PadT", mapPad.Transparency)
		end
		mapPad:SetAttribute("TeleportTo", (not modeOn) and MapService.SandboxSpawn() or nil)
		mapPad.Transparency = modeOn and 1 or (mapPad:GetAttribute("PadT") :: number)
		mapPad.CanCollide = not modeOn
		mapPad.CanTouch = not modeOn
		mapPad.CanQuery = not modeOn
		WorldSetup.Label(mapPad, (not modeOn) and "TO THE SANDBOX" or nil)
	end
end

-- terrain water in the map's WaterVolume parts (the sea)
local function water(model: Model, on: boolean)
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "WaterVolume" then
			pcall(function()
				terrain:FillBlock(d.CFrame, d.Size, on and Enum.Material.Water or Enum.Material.Air)
			end)
		end
	end
end

function MapService.Unload()
	if not MapService.IsLoaded() then
		return
	end
	local id = current :: string
	local c = loaded :: Model
	-- everybody in the map goes back to the sandbox first
	local home = MapService.SandboxSpawn()
	for _, p in Players:GetPlayers() do
		local t = p.Character and p.Character:FindFirstChild("Torso")
		if t and t:IsA("BasePart") and MapService.InMap(t.Position) then
			MapService.Teleport(p, spread(home, 6))
		end
	end
	if MapService.OnUnloading then
		pcall(MapService.OnUnloading, id, c)
	end
	task.wait(0.6)
	if markers then
		markers.Stop()
		markers = nil
	end
	-- what people spawned in the map goes with it
	for _, folderName in { "SpawnedProps", "NPCs", "Dummies", "Corpses" } do
		local f = workspace:FindFirstChild(folderName)
		if f then
			for _, inst in f:GetChildren() do
				local pos = inst:IsA("Model") and inst:GetPivot().Position or (inst:IsA("BasePart") and inst.Position or nil)
				if pos and MapService.InMap(pos, id) and not inst:GetAttribute("DriverId") then
					inst:Destroy()
				end
			end
		end
	end
	ExplosionService.UnregisterDestructibles(c)
	FractureService.Forget(c)
	water(c, false)
	c:Destroy()
	loaded = nil
	current = nil
	setPads()
	workspace:SetAttribute("MapLoaded", nil)
	workspace:SetAttribute("CityLoaded", false)
end

-- load map `id` (default: the city); another loaded map is unloaded first
function MapService.Load(id: string?): Model?
	id = id or "city"
	local def = MapService.Def(id)
	if not def then
		warn("[Ragdoll] unknown map", id)
		return nil
	end
	if MapService.Current() == id then
		return loaded
	end
	while busy do
		task.wait(0.1)
	end
	if MapService.Current() == id then
		return loaded
	end
	busy = true
	local ok, result = pcall(function()
		if MapService.IsLoaded() then
			MapService.Unload()
		end
		local template = ServerStorage:FindFirstChild(def.template)
		if not template then
			warn("[Ragdoll] no " .. def.template .. " in ServerStorage")
			return nil
		end
		local c = template:Clone()
		c.Name = "ActiveMap"
		c:SetAttribute("MapId", id)
		c.Parent = workspace
		loaded = c
		current = id
		water(c, true)
		WorldSetup.ProcessMap(c)
		ExplosionService.RegisterDestructibles(c)
		FractureService.Register(c) -- (v2.0: its walls break)
		LightingService.Register(c)
		markers = WorldSetup.SpawnMarkers(PropService, c)
		setPads()
		workspace:SetAttribute("MapLoaded", id)
		workspace:SetAttribute("CityLoaded", id == "city")
		if MapService.OnLoaded then
			task.spawn(MapService.OnLoaded, id, c)
		end
		return c
	end)
	busy = false
	if not ok then
		warn("[Ragdoll] loading the map failed:", result)
		return nil
	end
	return result
end

-- everybody to the loaded map (loads the city if none is) / back to the sandbox
function MapService.TeleportAll(where: string)
	local target: Vector3?
	if where == "map" or where == "city" then
		if not MapService.IsLoaded() then
			MapService.Load(where == "city" and "city" or nil)
		end
		target = MapService.MapSpawn()
	else
		target = MapService.SandboxSpawn()
	end
	if not target then
		return
	end
	for _, p in Players:GetPlayers() do
		MapService.Teleport(p, spread(target, 10))
	end
end

function MapService.Init()
	workspace:SetAttribute("CityLoaded", false)
	workspace:SetAttribute("MapLoaded", nil)
	setPads()
	workspace:GetAttributeChangedSignal("Mode"):Connect(setPads)
end

return MapService
