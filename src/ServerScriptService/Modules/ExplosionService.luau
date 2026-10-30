--!nonstrict
-- ExplosionService: grenades, C4, explosive barrels, exploding cars and the admin nuke.
--   * every body part in range takes damage by distance (limbs can be ripped off), the whole body
--     is thrown away from the blast
--   * loose props are pushed, explosive barrels and grenades in range go off too (chain reaction)
--   * ropes close to the blast tear
--   * walls marked "Destructible" break into loose bricks; they rebuild after a while
--   * cars in range lose (hidden) HP
--   * walls shield: the blast that gets through falls off with how thick the walls in between are
--     (a thin wooden wall takes some of it, a thick concrete wall almost all)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))

local Modules = script.Parent
local DamageService = require(Modules:WaitForChild("DamageService"))
local GoreService = require(Modules:WaitForChild("GoreService"))

local ExplosionService = {}
ExplosionService.OnItemBlast = nil :: ((Model, number) -> ())?

-- set by VehicleService: (car, damage, attacker)
ExplosionService.OnCar = nil :: ((Model, number, Player?) -> ())?
-- set by Main (ItemService): grenades in the blast go off, ropes close to it tear
ExplosionService.OnGrenade = nil :: ((Model, Player?) -> ())?
ExplosionService.OnFire = nil :: ((Vector3, number, number, Player?) -> ())? -- start a fire (FireService)
ExplosionService.OnBlast = nil :: ((Vector3, number) -> ())?
-- (v2.0) set by Main: knock a hole into a building wall (FractureService.Fracture)
ExplosionService.OnFracture = nil :: ((BasePart, Vector3, number, Vector3, number) -> boolean)?

local function closestOn(part: BasePart, p: Vector3): Vector3
	local l = part.CFrame:PointToObjectSpace(p)
	local h = part.Size * 0.5
	return part.CFrame:PointToWorldSpace(Vector3.new(math.clamp(l.X, -h.X, h.X), math.clamp(l.Y, -h.Y, h.Y), math.clamp(l.Z, -h.Z, h.Z)))
end

type Opts = { radius: number, damage: number, power: number, attacker: Player?, cause: string?, ignore: Instance?, kind: string?, sound: string?, bot: Model? }

------------------------------------------------------------------------
-- destructible walls
------------------------------------------------------------------------

local original: { [BasePart]: CFrame } = {}
local groups: { [string]: { parts: { BasePart }, lastBreak: number, broken: boolean, center: Vector3, radius: number } } = {}
-- glass that is broken right now (see Shatter below)
local shattered: { [BasePart]: { t: number, transp: number, cc: boolean, cq: boolean, ct: boolean, repair: boolean } } = {}

local function registerDestructibles(root: Instance?)
	local touched: { [string]: boolean } = {}
	for _, d in (root or workspace):GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Destructible") and d.Anchored and not original[d] then
			local name = tostring(d:GetAttribute("Destructible"))
			original[d] = d.CFrame
			local g = groups[name]
			if not g then
				g = { parts = {}, lastBreak = 0, broken = false, center = Vector3.zero, radius = 0 }
				groups[name] = g
			end
			table.insert(g.parts, d)
			touched[name] = true
		end
	end
	for name in touched do
		local g = groups[name]
		local sum = Vector3.zero
		for _, p in g.parts do
			sum += p.Position
		end
		g.center = sum / math.max(1, #g.parts)
		g.radius = 0
		for _, p in g.parts do
			g.radius = math.max(g.radius, (p.Position - g.center).Magnitude)
		end
	end
end

-- a map that was loaded later (the city): its walls and windows break and get repaired too
function ExplosionService.RegisterDestructibles(root: Instance)
	registerDestructibles(root)
end

-- ... and forgets them again when that map is removed
function ExplosionService.UnregisterDestructibles(root: Instance)
	for name, g in groups do
		for i = #g.parts, 1, -1 do
			local p = g.parts[i]
			if p == root or p:IsDescendantOf(root) or not p.Parent then
				original[p] = nil
				shattered[p] = nil
				table.remove(g.parts, i)
			end
		end
		if #g.parts == 0 then
			groups[name] = nil
		end
	end
end

-- glass: a bullet, a thrown thing or a blast shatters it. The pane vanishes in a rain of shards
-- (everybody sees them) and comes back with the rest of the repairs; a car window stays broken.

local function canShatter(part: BasePart): boolean
	if part.Material ~= Enum.Material.Glass or part.Transparency >= 0.98 or shattered[part] then
		return false
	end
	local m = part:FindFirstAncestorOfClass("Model")
	if m and (m:GetAttribute("Item") or m:GetAttribute("RagdollRig")) then
		return false -- (a bottle, a scope lens)
	end
	if m and m.PrimaryPart == part and not m:GetAttribute("Car") then
		return false -- (the screen of a TV is the TV)
	end
	return true
end
ExplosionService.CanShatter = canShatter

function ExplosionService.Shatter(part: BasePart, point: Vector3?, dir: Vector3?): boolean
	if not canShatter(part) then
		return false
	end
	local car = part:FindFirstAncestorOfClass("Model")
	local isCar = car ~= nil and car:GetAttribute("Car") == true
	shattered[part] = {
		t = os.clock(),
		transp = part.Transparency,
		cc = part.CanCollide,
		cq = part.CanQuery,
		ct = part.CanTouch,
		repair = not isCar,
	}
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	local p = point or part.Position
	GoreService.FX({ t = "glass", cf = part.CFrame, s = part.Size, p = p, d = dir or Vector3.zero, c = part.Color })
	GoreService.Sound("glass", p, 1)
	local g = groups[tostring(part:GetAttribute("Destructible"))]
	if g then
		g.broken = true
		g.lastBreak = os.clock()
	end
	return true
end

-- knock one brick loose
function ExplosionService.Break(part: BasePart, velocity: Vector3)
	if not original[part] or not part.Anchored then
		return
	end
	if part.Material == Enum.Material.Glass then
		ExplosionService.Shatter(part, part.Position, velocity.Magnitude > 0 and velocity.Unit or nil)
		return
	end
	part.Anchored = false
	part:SetAttribute("Settled", nil)
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
	part.AssemblyLinearVelocity = velocity
	part.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 12
	local g = groups[tostring(part:GetAttribute("Destructible"))]
	if g then
		g.broken = true
		g.lastBreak = os.clock()
	end
end

local function repairLoop()
	while true do
		task.wait(4)
		local now = os.clock()
		-- (v2.8) bricks of a broken wall that lie still are pinned there until the repair (no physics for a pile of rubble)
		for _, g in groups do
			if g.broken and now - g.lastBreak > 5 then
				for _, p in g.parts do
					if p.Parent and not p.Anchored and p.AssemblyLinearVelocity.Magnitude < 0.8 and p.AssemblyAngularVelocity.Magnitude < 1 then
						p.Anchored = true
						p:SetAttribute("Settled", true)
					end
				end
			end
		end
		for p, sh in shattered do
			if not p.Parent then
				shattered[p] = nil
			elseif sh.repair and not original[p] and now - sh.t > Config.DestructionRepairTime then
				local blocked = false
				for _, plr in Players:GetPlayers() do
					local t = plr.Character and plr.Character:FindFirstChild("Torso")
					if t and (t.Position - p.Position).Magnitude < p.Size.Magnitude * 0.5 + 3 then
						blocked = true
					end
				end
				if not blocked then
					shattered[p] = nil
					p.Transparency = sh.transp
					p.CanCollide = sh.cc
					p.CanQuery = sh.cq
					p.CanTouch = sh.ct
				end
			end
		end
		for _, g in groups do
			if g.broken and now - g.lastBreak > Config.DestructionRepairTime then
				-- not while someone stands in the way
				local blocked = false
				for _, plr in Players:GetPlayers() do
					local t = plr.Character and plr.Character:FindFirstChild("Torso")
					if t and (t.Position - g.center).Magnitude < g.radius + 4 then
						blocked = true
					end
				end
				if not blocked then
					g.broken = false
					for _, p in g.parts do
						local sh = shattered[p]
						if sh and p.Parent then
							shattered[p] = nil
							p.Transparency = sh.transp
							p.CanCollide = sh.cc
							p.CanQuery = sh.cq
							p.CanTouch = sh.ct
						end
						if p.Parent then
							p.Anchored = true
							p:SetAttribute("Settled", nil)
							p.AssemblyLinearVelocity = Vector3.zero
							p.AssemblyAngularVelocity = Vector3.zero
							p.CFrame = original[p]
						end
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- explosions
------------------------------------------------------------------------

local function bodyOf(part: Instance): Model?
	local m = part:FindFirstAncestorOfClass("Model")
	while m do
		if m:GetAttribute("RagdollRig") then
			return m
		end
		m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function modelWith(inst: Instance, attr: string): Model?
	local m = inst:FindFirstAncestorOfClass("Model")
	while m do
		if m:GetAttribute(attr) then
			return m
		end
		m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local shieldParams = RaycastParams.new()
shieldParams.FilterType = Enum.RaycastFilterType.Exclude
shieldParams.RespectCanCollide = true
shieldParams.IgnoreWater = true

-- how far a line entering `part` at `p` along `dir` runs inside it (box approximation)
local function chordLength(part: BasePart, p: Vector3, dir: Vector3, maxLen: number): number
	local o = part.CFrame:PointToObjectSpace(p)
	local d = part.CFrame:VectorToObjectSpace(dir)
	local h = part.Size * 0.5
	local t = maxLen
	for _, pair in { { d.X, o.X, h.X }, { d.Y, o.Y, h.Y }, { d.Z, o.Z, h.Z } } do
		local dv, ov, hv = pair[1], pair[2], pair[3]
		if math.abs(dv) > 1e-6 then
			local exit = ((dv > 0 and hv or -hv) - ov) / dv
			t = math.min(t, math.max(exit, 0))
		end
	end
	return math.clamp(t, 0, maxLen)
end

-- how much a part stops a blast per stud of it
local function blastWeight(part: BasePart): number
	if bodyOf(part) then
		return 0.25 -- a body in front of you takes a little of it
	end
	if part.Transparency > 0.45 then
		return 0.3 -- glass
	end
	local w = 1
	local mat = part.Material
	if mat == Enum.Material.Wood or mat == Enum.Material.WoodPlanks or mat == Enum.Material.Fabric or mat == Enum.Material.Plastic then
		w = 0.6
	elseif mat == Enum.Material.Concrete or mat == Enum.Material.Brick or mat == Enum.Material.Slate or mat == Enum.Material.Granite or mat == Enum.Material.Rock then
		w = 1.25
	elseif mat == Enum.Material.Metal or mat == Enum.Material.DiamondPlate or mat == Enum.Material.CorrodedMetal then
		w = 1.4
	end
	if not part.Anchored then
		w *= 0.6 -- loose things get blown away themselves
	end
	return w
end

-- 0..1: how much of a blast at `from` reaches `to`; `k` = how strongly walls stop it (per stud)
local function shielding(from: Vector3, to: Vector3, ignore: { Instance }, k: number): number
	local total = to - from
	local len = total.Magnitude
	if len < 0.1 then
		return 1
	end
	local unit = total / len
	local ign = table.clone(ignore)
	local thick = 0
	local origin = from
	for _ = 1, 10 do
		shieldParams.FilterDescendantsInstances = ign
		local rest = to - origin
		if rest.Magnitude < 0.05 then
			break
		end
		local hit = workspace:Raycast(origin, rest, shieldParams)
		if not hit or not hit.Instance:IsA("BasePart") then
			break
		end
		local part = hit.Instance :: BasePart
		local remaining = (to - hit.Position).Magnitude
		thick += chordLength(part, hit.Position, unit, remaining) * blastWeight(part)
		table.insert(ign, part)
		origin = hit.Position
		if thick * k > 6 then
			break
		end
	end
	return math.exp(-thick * k)
end
ExplosionService.Shielding = shielding

-- the best way through for a body: the torso or the head (peeking over a wall still gets hit)
local function bodyShield(model: Model, pos: Vector3, ignoreBase: { Instance }, k: number): number
	local ign = table.clone(ignoreBase)
	table.insert(ign, model)
	local best = 0
	for _, name in { "Torso", "Head" } do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			best = math.max(best, shielding(pos, p.Position, ign, k))
		end
	end
	return best
end

------------------------------------------------------------------------
-- (v2.0) craters: a blast on the ground leaves one - a scorched pit with a broken lip of earth / asphalt / concrete
-- round it and lumps thrown about. The ground heals: after a while it fades away. (The ground itself stays whole:
-- nobody falls out of the world.)
------------------------------------------------------------------------

local craters: { Model } = {}
local GROUND_NAMES = { Baseplate = true, SiteGround = true, HorrorGround = true, ParkingLot = true, CityGround = true, Courtyard = true,
	Road = true, Sidewalk = true, Grass = true, StoreFoundation = true, Runway = true, Ground = true }

local function makeCrater(pos: Vector3, R: number)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = {}
	for _, n in { "FX", "SpawnedProps", "Corpses", "Gibs", "NPCs", "Dummies", "Creatures", "Ties" } do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(skip, f)
		end
	end
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(skip, plr.Character)
		end
	end
	rp.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -(3 + R * 0.4), 0), rp)
	if not hit or not hit.Instance:IsA("BasePart") or not hit.Instance.Anchored or hit.Normal.Y < 0.8 then
		return
	end
	local ground = hit.Instance :: BasePart
	if not GROUND_NAMES[ground.Name] and ground.Size.Magnitude < 60 then
		return -- (a table, a crate: no crater in that)
	end
	local r = math.clamp(R * 0.42, 2.5, 26)
	local c = Instance.new("Model")
	c.Name = "Crater"
	local at = hit.Position
	local mat = ground.Material
	local burnt = ground.Color:Lerp(Color3.fromRGB(26, 22, 20), 0.75)
	local soil = ground.Color:Lerp(Color3.fromRGB(96, 76, 58), 0.45)
	local function p(name: string, size: Vector3, cf: CFrame, color: Color3, collide: boolean, cls: string?): BasePart
		local q = Instance.new(cls or "Part") :: BasePart
		q.Name = name
		q.Size = size
		q.CFrame = cf
		q.Color = color
		q.Material = mat
		q.Anchored = true
		q.CanCollide = collide
		q.CanQuery = false
		q.CanTouch = false
		if collide then
			q.CollisionGroup = "Crater" -- (v2.8: props and cars bump into it, bodies walk through)
		end
		q.TopSurface = Enum.SurfaceType.Smooth
		q.BottomSurface = Enum.SurfaceType.Smooth
		q.Parent = c
		return q
	end
	-- the scorched pit (two discs: the black middle, the burnt ring)
	local flat = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90))
	local pit = p("CraterPit", Vector3.new(0.12, r * 2, r * 2), flat * CFrame.new(0.06, 0, 0), burnt, false)
	pit.Shape = Enum.PartType.Cylinder
	local core = p("CraterCore", Vector3.new(0.14, r * 1.1, r * 1.1), flat * CFrame.new(0.08, 0, 0), Color3.fromRGB(14, 12, 12), false)
	core.Shape = Enum.PartType.Cylinder
	-- the lip: chunks of the ground pushed up and outward all round, sloping into the pit
	local n = math.clamp(math.floor(r * 2.2), 8, 26)
	for i = 1, n do
		local a = (i + math.random() * 0.4) / n * math.pi * 2
		local w = (2 * math.pi * r / n) * 1.35
		local h = r * (0.18 + math.random() * 0.12)
		local d = r * (0.35 + math.random() * 0.15)
		local cf = CFrame.new(at) * CFrame.Angles(0, a, 0) * CFrame.new(0, h * 0.5 - 0.1, -r) * CFrame.Angles(math.rad(math.random(-8, 8)), 0, math.rad(math.random(-6, 6)))
		p("CraterLip", Vector3.new(w, h, d), cf, i % 3 == 0 and burnt or soil, true, "WedgePart") -- (v2.8: only props and cars collide with it, bodies pass)
	end
	-- lumps thrown out round it
	for _ = 1, math.clamp(math.floor(r), 4, 14) do
		local a = math.random() * math.pi * 2
		local dist = r * (1.2 + math.random() * 1.4)
		local s = r * (0.06 + math.random() * 0.1)
		p("CraterLump", Vector3.new(s * 1.4, s, s * 1.2), CFrame.new(at + Vector3.new(math.cos(a) * dist, s * 0.4, math.sin(a) * dist)) * CFrame.Angles(math.random() * 3, math.random() * 3, 0),
			soil, true)
	end
	c.Parent = workspace:FindFirstChild("FX") or workspace
	table.insert(craters, c)
	while #craters > Config.CraterMax do
		local old = table.remove(craters, 1)
		if old and old.Parent then
			old:Destroy()
		end
	end
	-- and it heals
	task.delay(Config.CraterTime, function()
		if not c.Parent then
			return
		end
		for k = 1, 10 do
			for _, q in c:GetChildren() do
				if q:IsA("BasePart") then
					q.Transparency = k / 10
				end
			end
			task.wait(0.2)
		end
		c:Destroy()
		local i = table.find(craters, c)
		if i then
			table.remove(craters, i)
		end
	end)
end

function ExplosionService.Explode(pos: Vector3, opts: Opts)
	local R = opts.radius
	if R >= Config.CraterMinRadius and opts.kind ~= "laser" then
		pcall(makeCrater, pos, R)
	end
	GoreService.FX({ t = "boom", p = pos, r = R, k = opts.kind })
	GoreService.Sound(opts.sound or "explosion", pos, 1)
	if ExplosionService.OnBlast then
		ExplosionService.OnBlast(pos, R)
	end

	local fx = workspace:FindFirstChild("FX")
	local ignoreBase = { fx }
	if opts.ignore then
		table.insert(ignoreBase, opts.ignore)
	end

	-- bodies
	for model, state in DamageService.Bodies() do
		local torso = model.Parent and model:FindFirstChild("Torso") :: BasePart?
		if not torso or (opts.ignore ~= nil and model == opts.ignore) then
			continue -- (v2.0: the one it is ignoring - the laser's owner - is not hurt by it)
		end
		local dist = (torso.Position - pos).Magnitude
		if dist > R + 3 then
			continue
		end
		local c = bodyShield(model, pos, ignoreBase, Config.BlastWallStop)
		if c < 0.02 then
			continue
		end
		for partName, region in RigInfo.PartRegion do
			local p = model:FindFirstChild(partName)
			if p and p:IsA("BasePart") and not model:GetAttribute("Severed_" .. region) then
				local d = (p.Position - pos).Magnitude
				if d < R then
					local f = (1 - d / R) ^ 1.6 * c
					local dmg = opts.damage * f * (Config.LimbMultiplier[region] or 1)
					if dmg >= 2 then
						if opts.bot then
							DamageService.MarkBotAttacker(model, opts.bot) -- (v2.0: a bot's rocket counts for that bot)
						end
						DamageService.ApplyDamage(model, region, dmg, p.Position, {
							cause = opts.cause or "Blown up",
							allowSever = true,
							severAt = Config.ExplosionSeverDamage,
							attacker = opts.attacker,
							blast = true, -- (v2.8: BLASTWEAVE)
						})
					end
				end
			end
		end
		if dist < R then
			local f = (1 - dist / R) * c
			local dir = (torso.Position - pos)
			dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.yAxis
			local v = (dir + Vector3.new(0, 0.8, 0)).Unit * opts.power * f
			DamageService.MarkAttacker(model, opts.attacker)
			DamageService.Blast(model, v, f > 0.15 and math.clamp(1.5 + f * 2.5, 1.5, 3.6) or nil)
		end
	end

	-- props, barrels, cars, walls
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = ignoreBase
	local seen = {}
	local carsHit = {}
	local boxesHit = {}
	for _, p in workspace:GetPartBoundsInRadius(pos, R, op) do
		if bodyOf(p) then
			continue
		end
		local d = (p.Position - pos).Magnitude
		local f = math.clamp(1 - d / R, 0, 1)
		local dir = (p.Position - pos)
		dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.yAxis
		if d < R * 0.85 and canShatter(p) then
			ExplosionService.Shatter(p, p.Position, dir) -- (every window near a blast, car windows too)
			continue
		end
		if p.Anchored then
			if p:GetAttribute("Destructible") and d < R * 0.8 then
				ExplosionService.Break(p, (dir + Vector3.new(0, 0.5, 0)).Unit * opts.power * (0.4 + f))
			elseif p:GetAttribute("Fracture") and ExplosionService.OnFracture then
				-- (v2.0) the wall gets a hole the size of the blast
				local cp = closestOn(p, pos)
				local dd = (cp - pos).Magnitude
				if dd < R * 0.7 then
					local holeR = math.clamp(R * 0.42 * (1 - dd / R) + 0.8, 1.2, 14)
					local away = cp - pos
					ExplosionService.OnFracture(p, cp, holeR, away.Magnitude > 0.1 and away.Unit or dir, opts.power * (0.5 + f))
				end
			end
			continue
		end
		local car = modelWith(p, "Car")
		if car then
			if not carsHit[car] then
				carsHit[car] = true
				if ExplosionService.OnCar then
					ExplosionService.OnCar(car, opts.damage * (0.4 + f) * 1.4, opts.attacker)
				end
			end
		end
		local barrel = modelWith(p, "Explosive")
		if barrel and not barrel:GetAttribute("Exploded") then
			task.delay(0.12 + math.random() * 0.15, ExplosionService.Detonate, barrel, opts.attacker)
		end
		local grenade = modelWith(p, "Item")
		local gk = grenade and grenade:GetAttribute("Item")
		if grenade and (gk == "grenade" or gk == "c4" or gk == "flash" or gk == "molotov") and ExplosionService.OnGrenade and d < R * 0.7 then
			task.delay(0.1 + math.random() * 0.15, ExplosionService.OnGrenade, grenade, opts.attacker)
		end
		if grenade and gk == "boombox" and ExplosionService.OnItemBlast and not boxesHit[grenade] then
			boxesHit[grenade] = true
			ExplosionService.OnItemBlast(grenade, opts.damage * (0.4 + f) * 1.2) -- (v1.9.1: a blast breaks a boombox)
		end
		local root = p.AssemblyRootPart
		if not root or seen[root] or root.Anchored then
			continue -- (anchored: the world, or a spear / C4 pinned in it - never push it)
		end
		seen[root] = true
		local ign = table.clone(ignoreBase)
		table.insert(ign, (car or root:FindFirstAncestorOfClass("Model") or root) :: Instance)
		local sh = shielding(pos, root.Position, ign, Config.BlastWallStop)
		local v = (dir + Vector3.new(0, 0.6, 0)).Unit * opts.power * f * sh * (car and 0.35 or 1)
		if v.Magnitude < 1 then
			continue
		end
		local ok, owner = pcall(function()
			return root:GetNetworkOwner()
		end)
		if ok and owner == nil then
			pcall(function()
				root:ApplyImpulse(v * root.AssemblyMass)
				root.AssemblyAngularVelocity += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 8 * f
			end)
		else
			-- the owner of the object applies the push
			GoreService.FX({ t = "push", part = root, i = v * root.AssemblyMass, p = root.Position })
		end
	end
end

-- explosive barrels (and anything else marked "Explosive")
function ExplosionService.Detonate(model: Model, attacker: Player?)
	if not model.Parent or model:GetAttribute("Exploded") then
		return
	end
	model:SetAttribute("Exploded", true)
	local pos = model:GetPivot().Position
	model:Destroy()
	if ExplosionService.OnFire then
		ExplosionService.OnFire(pos, Config.BarrelFireRadius, Config.BarrelFireTime, attacker) -- (burning fuel)
	end
	ExplosionService.Explode(pos, {
		radius = Config.BarrelRadius,
		damage = Config.BarrelDamage,
		power = Config.BarrelPower,
		attacker = attacker,
		cause = "Blown up",
		kind = "barrel",
	})
end

------------------------------------------------------------------------
-- the nuke (admin): fireball, then a huge shockwave that travels outwards (walls shield)
------------------------------------------------------------------------

function ExplosionService.Nuke(pos: Vector3, attacker: Player?)
	GoreService.FX({ t = "nuke", p = pos, r = Config.NukeRadius, s = Config.NukeShockRadius, v = Config.NukeShockSpeed })
	local R = Config.NukeRadius
	local S = Config.NukeShockRadius
	local fireball = R * 0.3
	-- bodies: the fireball vaporises, the shockwave arrives later the further away you are
	for model in DamageService.Bodies() do
		local torso = model.Parent and model:FindFirstChild("Torso") :: BasePart?
		if not torso then
			continue
		end
		local dist = (torso.Position - pos).Magnitude
		if dist > S then
			continue
		end
		local delay = math.max(0, dist - fireball) / Config.NukeShockSpeed
		task.delay(delay, function()
			if not model.Parent then
				return
			end
			local t2 = model:FindFirstChild("Torso") :: BasePart?
			if not t2 then
				return
			end
			local d = (t2.Position - pos).Magnitude
			DamageService.MarkAttacker(model, attacker)
			-- inside the fireball nothing helps; further out, walls take the wave by their thickness
			local sh = d < fireball and 1 or bodyShield(model, pos + Vector3.new(0, 6, 0), { workspace:FindFirstChild("FX") :: any }, Config.NukeWallStop)
			if sh < 0.03 then
				return
			end
			if d < R then
				local f = (1 - d / R) ^ 1.2 * sh
				for partName, region in RigInfo.PartRegion do
					local p = model:FindFirstChild(partName)
					if p and p:IsA("BasePart") and not model:GetAttribute("Severed_" .. region) then
						DamageService.ApplyDamage(model, region, 40 + 900 * f, p.Position, {
							cause = d < fireball and "Vaporized" or "Nuked",
							allowSever = true,
							severAt = 120,
							attacker = attacker,
							quiet = d > R * 0.6,
							blast = true,
							nuke = true,
						})
					end
				end
			end
			local dir = t2.Position - pos
			dir = Vector3.new(dir.X, 0, dir.Z)
			dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.xAxis
			local k = (1 - math.clamp(d / S, 0, 1)) * sh
			DamageService.heavyHit = true -- (v2.8) the nuke throws even a COLOSSUS
			DamageService.Blast(model, dir * (70 + 430 * k) * sh + Vector3.new(0, (45 + 200 * k) * sh, 0), 2.5 + 3.5 * k)
			DamageService.heavyHit = false
		end)
	end
	-- the world: walls break, barrels / grenades / C4 go off, cars burn, loose things fly
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	local fx = workspace:FindFirstChild("FX")
	op.FilterDescendantsInstances = fx and { fx } or {}
	local seen = {}
	local fractured = 0
	for _, p in workspace:GetPartBoundsInRadius(pos, S, op) do
		if bodyOf(p) or p.Name == "Baseplate" then
			continue
		end
		local d = (p.Position - pos).Magnitude
		local delay = math.max(0, d - fireball) / Config.NukeShockSpeed
		local dir = p.Position - pos
		dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.yAxis
		local k = 1 - math.clamp(d / S, 0, 1)
		if p.Anchored then
			if p:GetAttribute("Destructible") and d < R then
				task.delay(delay, ExplosionService.Break, p, (dir + Vector3.new(0, 0.6, 0)).Unit * (60 + 200 * k))
			elseif p:GetAttribute("Fracture") and ExplosionService.OnFracture and fractured < 48 then
				-- (v2.0) the buildings close to it get torn open (the nearest ones; not every wall of the map)
				local cp = closestOn(p, pos)
				local dd = (cp - pos).Magnitude
				if dd < R * 0.6 then
					fractured += 1
					local away = cp - pos
					task.delay(delay, ExplosionService.OnFracture, p, cp, math.clamp(18 * (1 - dd / R), 4, 16), away.Magnitude > 0.1 and away.Unit or dir, 200 * k + 60)
				end
			end
			continue
		end
		local car = modelWith(p, "Car")
		if car and not seen[car] then
			seen[car] = true
			if ExplosionService.OnCar and d < R then
				task.delay(delay, ExplosionService.OnCar, car, 2000, attacker)
			end
		end
		local barrel = modelWith(p, "Explosive")
		if barrel and not seen[barrel] and d < R then
			seen[barrel] = true
			task.delay(delay + math.random() * 0.3, ExplosionService.Detonate, barrel, attacker)
		end
		local item = modelWith(p, "Item")
		local ik = item and item:GetAttribute("Item")
		if item and not seen[item] and (ik == "grenade" or ik == "c4" or ik == "flash" or ik == "molotov") and d < R and ExplosionService.OnGrenade then
			seen[item] = true
			task.delay(delay + math.random() * 0.3, ExplosionService.OnGrenade, item, attacker)
		end
		local root = p.AssemblyRootPart
		if not root or seen[root] or root.Anchored then
			continue -- (anchored: the world, or a spear / C4 pinned in it - never push it)
		end
		seen[root] = true
		local v = (dir + Vector3.new(0, 0.7, 0)).Unit * (50 + 420 * k)
		task.delay(delay, function()
			if not root.Parent then
				return
			end
			if d > fireball then
				local ignM = { (fx or workspace) :: Instance, (root:FindFirstAncestorOfClass("Model") or root) :: Instance }
				v *= shielding(pos + Vector3.new(0, 6, 0), root.Position, ignM, Config.NukeWallStop)
				if v.Magnitude < 2 then
					return
				end
			end
			local ok, owner = pcall(function()
				return root:GetNetworkOwner()
			end)
			if ok and owner == nil then
				pcall(function()
					root.AssemblyLinearVelocity += v
					root.AssemblyAngularVelocity += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 10 * k
				end)
			else
				GoreService.FX({ t = "push", part = root, i = v * root.AssemblyMass, p = root.Position })
			end
		end)
	end
	if ExplosionService.OnBlast then
		ExplosionService.OnBlast(pos, R)
	end
end

function ExplosionService.Init()
	registerDestructibles()
	task.spawn(repairLoop)
	-- an explosive barrel or a grenade that crashes into something hard (or falls far) goes off
	local lastSpeed: { [Model]: number } = {}
	RunService.Heartbeat:Connect(function()
		for _, folderName in { "SpawnedProps", "Map" } do
			local f = workspace:FindFirstChild(folderName)
			if not f then
				continue
			end
			for _, m in f:GetChildren() do
				if not m:IsA("Model") or not m.PrimaryPart then
					continue
				end
				local barrel = m:GetAttribute("Explosive") == true
				local ik = m:GetAttribute("Item")
				local grenade = ik == "grenade" or ik == "flash" or ik == "molotov"
				if barrel or grenade then
					local v = m.PrimaryPart.AssemblyLinearVelocity.Magnitude
					local last = lastSpeed[m] or 0
					local limit = barrel and Config.BarrelImpactSpeed or (ik == "molotov" and Config.MolotovBreakSpeed or Config.GrenadeImpactSpeed)
					if last - v > limit and not m:GetAttribute("HolderId") then
						lastSpeed[m] = nil
						local by = DamageService.AttackerOf(m.PrimaryPart)
						if barrel then
							ExplosionService.Detonate(m, by)
						elseif ExplosionService.OnGrenade then
							ExplosionService.OnGrenade(m, by)
						end
					else
						lastSpeed[m] = v
					end
				end
			end
		end
		for m in lastSpeed do
			if not m.Parent then
				lastSpeed[m] = nil
			end
		end
	end)
end

return ExplosionService
