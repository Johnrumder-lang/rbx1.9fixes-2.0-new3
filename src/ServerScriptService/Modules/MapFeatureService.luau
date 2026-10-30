--!nonstrict
-- MapFeatureService (v2.0): what the new maps do by themselves.
--   horror : the Crawler roams the asylum while the map is loaded (it comes back a minute after it was killed).
--            The MONSTER game mode brings its own, stronger one instead.
--   sea    : sharks; and whoever falls into the water gets an island: it comes up out of the sea near them, a random
--            size, with palms, rocks and sometimes something useful lying on the sand.
--   valley : (v2.0) the wind rolls tumbleweeds through the canyon.
--   sky    : (v2.0) the void: whoever falls below the islands (Config.SkyVoidY) is gone - a whistle on the way down;
--            things that fall off are cleared away.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Water = require(Shared:WaitForChild("Water"))

local Modules = script.Parent
local MapService = require(Modules:WaitForChild("MapService"))
local CreatureService = require(Modules:WaitForChild("CreatureService"))
local DrownService = require(Modules:WaitForChild("DrownService"))
local GoreService = require(Modules:WaitForChild("GoreService"))
local PropService = require(Modules:WaitForChild("PropService"))
local DamageService = require(Modules:WaitForChild("DamageService"))

local MapFeatureService = {}

-- set by GameModeService: true while a mode brings its own monster (no roaming one then)
MapFeatureService.ModeMonster = false

local rng = Random.new()
local islands: { Model } = {}
local lastIsland: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

local function points(prefix: string): { BasePart }
	return MapService.Points(prefix)
end

local function inMap(id: string): (Vector3) -> boolean
	return function(p: Vector3): boolean
		return MapService.InMap(p, id)
	end
end


function MapFeatureService.SpawnCrawler(mode: boolean, hp: number?): Model?
	local spots = points("MonsterSpawn_")
	local spot = spots[rng:NextInteger(1, math.max(1, #spots))]
	local pos = spot and spot.Position or (MapService.Center() + Vector3.new(0, 3, 0))
	return CreatureService.Spawn("crawler", pos, {
		mapId = MapService.Current(),
		bounds = inMap(MapService.Current() or "horror"),
		mode = mode,
		hp = hp,
		speedK = mode and 1.08 or 1,
	})
end

local function spawnSharks()
	local spots = points("SharkSpawn_")
	for i = 1, Config.SharkCount do
		local spot = spots[(i - 1) % math.max(1, #spots) + 1]
		local base = spot and spot.Position or (MapService.Center() + Vector3.new(rng:NextNumber(-200, 200), -6, rng:NextNumber(-200, 200)))
		CreatureService.Spawn("shark", base, { mapId = "sea", bounds = inMap("sea") })
	end
end

------------------------------------------------------------------------
-- islands
------------------------------------------------------------------------

local function ipart(m: Model, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = m
	return p
end

local function palm(m: Model, base: Vector3, h: number)
	local lean = CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), rng:NextNumber(0, math.pi * 2), math.rad(rng:NextNumber(-12, 12)))
	local trunk = CFrame.new(base) * lean
	local segs = 5
	for i = 0, segs - 1 do
		ipart(m, "PalmTrunk", Vector3.new(0.9 - i * 0.08, h / segs + 0.1, 0.9 - i * 0.08), trunk * CFrame.new(0, h / segs * (i + 0.5), 0), Color3.fromRGB(120 + i * 6, 92, 58), Enum.Material.Wood)
	end
	local top = trunk * CFrame.new(0, h, 0)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		ipart(m, "PalmLeaf", Vector3.new(0.2, 1.4, 5.5), top * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-25), 0, 0) * CFrame.new(0, 0, -2.6),
			Color3.fromRGB(56, 140, 54), Enum.Material.Grass)
	end
	ipart(m, "Coconut", Vector3.new(0.7, 0.7, 0.7), top * CFrame.new(0.4, -0.5, 0.3), Color3.fromRGB(90, 62, 36), Enum.Material.Wood, Enum.PartType.Ball)
end

function MapFeatureService.Island(near: Vector3): Model?
	local map = MapService.Map()
	if MapService.Current() ~= "sea" or not map then
		return nil
	end
	local surf = Water.SurfaceAt(near)
	if not surf then
		return nil
	end
	local r = rng:NextNumber(Config.IslandMin, Config.IslandMax)
	local pos: Vector3? = nil
	for _ = 1, 12 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = r + rng:NextNumber(6, 16)
		local p = Vector3.new(near.X + math.cos(a) * d, surf, near.Z + math.sin(a) * d)
		-- in the sea, clear of the ship and of the other islands
		if MapService.InMap(p + Vector3.new(r, 0, r), "sea") and MapService.InMap(p - Vector3.new(r, 0, r), "sea") and Water.SurfaceAt(p) then
			local clear = true
			local ship = map:FindFirstChild("Ship", true)
			if ship and ship:IsA("Model") then
				local cf, size = ship:GetBoundingBox()
				local lp = cf:PointToObjectSpace(p)
				if math.abs(lp.X) < size.X * 0.5 + r + 6 and math.abs(lp.Z) < size.Z * 0.5 + r + 6 then
					clear = false
				end
			end
			for _, other in islands do
				if other.Parent and (other:GetPivot().Position - p).Magnitude < r + (other:GetAttribute("Radius") or 10) + 4 then
					clear = false
				end
			end
			if clear then
				pos = p
				break
			end
		end
	end
	if not pos then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = "Island"
	m:SetAttribute("Radius", r)
	local h = rng:NextNumber(1.6, 3.4) + r * 0.06
	local sand = Color3.fromRGB(226, 206, 150)
	-- under water down to the sea floor, a sandy top above it, a wet rim
	local base = ipart(m, "IslandBase", Vector3.new(36, r * 2, r * 2), CFrame.new(pos + Vector3.new(0, h - 18, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 180, 128), Enum.Material.Sand, Enum.PartType.Cylinder)
	base.Name = "IslandBase"
	ipart(m, "IslandRim", Vector3.new(1.2, r * 2 + 3, r * 2 + 3), CFrame.new(pos + Vector3.new(0, h - 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(196, 172, 120), Enum.Material.Sand, Enum.PartType.Cylinder)
	ipart(m, "IslandTop", Vector3.new(1.5, r * 1.3, r * 1.3), CFrame.new(pos + Vector3.new(0, h + 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), sand, Enum.Material.Sand, Enum.PartType.Cylinder)
	local top = pos.Y + h
	-- palms and rocks
	local palms = math.clamp(math.floor(r / 6), 1, 5)
	for _ = 1, palms do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(0, r * 0.55)
		palm(m, Vector3.new(pos.X + math.cos(a) * d, top, pos.Z + math.sin(a) * d), rng:NextNumber(9, 15))
	end
	for _ = 1, math.clamp(math.floor(r / 5), 1, 6) do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(r * 0.4, r * 0.9)
		local s = rng:NextNumber(1.5, 4)
		ipart(m, "Rock", Vector3.new(s * 1.3, s, s * 1.1), CFrame.new(pos.X + math.cos(a) * d, top + s * 0.25, pos.Z + math.sin(a) * d) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 6), rng:NextNumber(0, 1)),
			Color3.fromRGB(110, 108, 104), Enum.Material.Slate)
	end
	m.PrimaryPart = base
	-- it rises out of the sea
	local final = m:GetPivot()
	m:PivotTo(final - Vector3.new(0, h + 2.5, 0))
	m.Parent = map
	table.insert(islands, m)
	while #islands > Config.IslandMaxCount do
		local old = table.remove(islands, 1)
		if old and old.Parent then
			old:Destroy()
		end
	end
	GoreService.FX({ t = "splash", p = pos, s = 1.5 })
	GoreService.Sound("splash", pos, 1)
	task.spawn(function()
		local steps = 30
		for i = 1, steps do
			if not m.Parent then
				return
			end
			local k = i / steps
			k = 1 - (1 - k) * (1 - k)
			m:PivotTo(final - Vector3.new(0, (h + 2.5) * (1 - k), 0))
			task.wait(1 / 30)
		end
		m:PivotTo(final)
		-- sometimes there is something on the sand
		if rng:NextNumber() < Config.IslandLootChance then
			local loot = Config.IslandLoot[rng:NextInteger(1, #Config.IslandLoot)]
			local a = rng:NextNumber(0, math.pi * 2)
			local inst = PropService.Place(loot, CFrame.new(pos.X + math.cos(a) * r * 0.3, top + 1.6, pos.Z + math.sin(a) * r * 0.3) * CFrame.Angles(0, 0, math.rad(90)))
			if inst then
				inst:SetAttribute("IslandLoot", true)
			end
		end
	end)
	return m
end

local function onEnterWater(model: Model, pos: Vector3)
	if MapService.Current() ~= "sea" or not MapService.InMap(pos, "sea") then
		return
	end
	if not Players:GetPlayerFromCharacter(model) and not model:GetAttribute("IsNPC") then
		return
	end
	local t = os.clock()
	if t - (lastIsland[model] or -1e9) < Config.IslandCooldown then
		return
	end
	lastIsland[model] = t
	task.wait(0.8)
	MapFeatureService.Island(pos)
end

------------------------------------------------------------------------
-- (v2.0) the sky islands' void, the valley's tumbleweeds
------------------------------------------------------------------------

local whistled: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local function inSkyBox(pos: Vector3): boolean
	local d = MapService.Def("sky")
	if not d then
		return false
	end
	local p = pos - d.center
	return math.abs(p.X) < d.half + 60 and math.abs(p.Z) < d.half + 60
end

local function voidStep()
	if MapService.Current() ~= "sky" then
		return
	end
	for model in DamageService.Bodies() do
		local torso = model.Parent and model:FindFirstChild("Torso")
		if not torso or not torso:IsA("BasePart") or not inSkyBox(torso.Position) then
			continue
		end
		local y = torso.Position.Y
		if y < Config.SkyVoidY + 40 and not whistled[model] and torso.AssemblyLinearVelocity.Y < -30 then
			whistled[model] = true
			GoreService.Sound("fallingWhistle", torso, 1)
		end
		if y < Config.SkyVoidY and not model:GetAttribute("Dead") then
			DamageService.Kill(model, "Fell off the Sky Islands")
		end
		if y > Config.SkyVoidY + 60 then
			whistled[model] = nil
		end
	end
	-- whatever falls off is gone (nobody sees it again anyway)
	local props = workspace:FindFirstChild("SpawnedProps")
	if props then
		for _, inst in props:GetChildren() do
			local pp = inst:IsA("Model") and inst.PrimaryPart or (inst:IsA("BasePart") and inst or nil)
			if pp and pp.Position.Y < Config.SkyVoidY - 80 and inSkyBox(pp.Position) and not inst:GetAttribute("HolderId") then
				inst:Destroy()
			end
		end
	end
end

type Weed = { part: BasePart, home: CFrame }
local weeds: { Weed } = {}
local function setupWeeds(model: Model)
	table.clear(weeds)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Tumbleweed" and not d.Anchored then
			pcall(function()
				d:SetNetworkOwner(nil) -- (the server blows them along)
			end)
			table.insert(weeds, { part = d, home = d.CFrame })
		end
	end
end

local windDir = Vector3.new(1, 0, 0.35).Unit
local function weedStep()
	if MapService.Current() ~= "valley" or #weeds == 0 then
		return
	end
	if rng:NextNumber() < 0.02 then
		-- the wind turns now and then
		local a = rng:NextNumber(0, math.pi * 2)
		windDir = Vector3.new(math.cos(a), 0, math.sin(a))
	end
	local d = MapService.Def("valley")
	for _, w in weeds do
		local p = w.part
		if not p.Parent or p.Anchored then
			continue
		end
		local rel = p.Position - (d and d.center or Vector3.zero)
		if p.Position.Y < -20 or math.abs(rel.X) > 150 or math.abs(rel.Z) > 360 then
			-- blown out of the valley: a new one rolls in where it started
			p.AssemblyLinearVelocity = Vector3.zero
			p.AssemblyAngularVelocity = Vector3.zero
			p.CFrame = w.home
			continue
		end
		if rng:NextNumber() < 0.5 then
			local speed = rng:NextNumber(12, 24)
			local v = windDir * speed + Vector3.new(0, rng:NextNumber() < 0.25 and rng:NextNumber(8, 16) or 0, 0)
			pcall(function()
				p.AssemblyLinearVelocity = Vector3.new(v.X, math.max(p.AssemblyLinearVelocity.Y, v.Y), v.Z)
				p.AssemblyAngularVelocity = windDir:Cross(Vector3.yAxis) * -speed / 1.2
			end)
		end
	end
end

------------------------------------------------------------------------

function MapFeatureService.Init()
	MapService.OnLoaded = function(id: string, model: Model)
		-- (v2.8) the Crawler only exists in the MONSTER mode: no roaming one on the maps any more
		if id == "sea" then
			spawnSharks()
		elseif id == "valley" then
			setupWeeds(model)
		end
	end
	MapService.OnUnloading = function(id: string, _model: Model)
		CreatureService.RemoveWhere(function(c)
			return c.mapId == id
		end)
		table.clear(islands)
		table.clear(weeds)
	end
	DrownService.OnEnterWater = onEnterWater
	-- (v2.0) the void and the wind
	task.spawn(function()
		local acc = 0
		while true do
			task.wait(0.25)
			pcall(voidStep)
			acc += 0.25
			if acc >= 0.75 then
				acc = 0
				pcall(weedStep)
			end
		end
	end)
	-- (v2.8) the Crawler belongs to the MONSTER mode: outside a running monster round every crawler goes (a round that
	-- ended, a mode that was stopped, a map that changed - nothing is left behind)
	task.spawn(function()
		while true do
			task.wait(3)
			local monsterOn = workspace:GetAttribute("Mode") == "monster" and workspace:GetAttribute("ModePhase") == "playing"
			if not monsterOn then
				for m, c in CreatureService.All() do
					if c.kind == "crawler" and c.state ~= "dead" then
						CreatureService.Despawn(m)
					end
				end
			end
			-- dead sharks come back too
			if MapService.Current() == "sea" then
				local n = 0
				for _, c in CreatureService.All() do
					if c.kind == "shark" and c.state ~= "dead" then
						n += 1
					end
				end
				if n < Config.SharkCount and math.random() < 0.08 then
					local spots = points("SharkSpawn_")
					local spot = spots[rng:NextInteger(1, math.max(1, #spots))]
					if spot then
						CreatureService.Spawn("shark", spot.Position, { mapId = "sea", bounds = inMap("sea") })
					end
				end
			end
		end
	end)
end

return MapFeatureService
