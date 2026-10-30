--!nonstrict
-- CalamityService (v1.9): the "Wonder" spec.
--
-- A player who has it switched on (the owner, or somebody the owner gave it to) cannot be hurt by other
-- people: a bullet goes straight through the body and leaves a hole that closes again, blades, blasts and
-- thrown things do nothing. Falling still hurts (and so does everything the world does without a person
-- behind it).
--
-- Anyone who TRIES - shoots, stabs, throws something at them, grabs or drags them - is marked. A marked
-- player gets a calamity every 5 seconds to 3 minutes, and only that player: a rock, an anvil, a piano, a
-- car that comes from behind and drives at them before it blows up, a live grenade at their feet,
-- barrels, a ring of fire, a lightning bolt, in the end a meteor. Every event shows a red warning ring on
-- the ground first, so it can be dodged. The more somebody dodges, the worse the next event gets.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))

local Modules = script.Parent
local DamageService = require(Modules:WaitForChild("DamageService"))
local GoreService = require(Modules:WaitForChild("GoreService"))
local ExplosionService = require(Modules:WaitForChild("ExplosionService"))
local FireService = require(Modules:WaitForChild("FireService"))
local OwnershipService = require(Modules:WaitForChild("OwnershipService"))

local CalamityService = {}
CalamityService.PlaceProp = nil :: ((string, CFrame, Player?) -> Instance?)? -- set by Main (PropService.Place)

type Mark = { level: number, nextAt: number, dodges: number, events: number, busy: boolean }
local marks: { [Player]: Mark } = {}
local rng = Random.new()

local MIN_GAP = 5
local MAX_GAP = 180

local function fxFolder(): Instance
	local f = workspace:FindFirstChild("FX")
	if not f then
		f = Instance.new("Folder")
		f.Name = "FX"
		f.Parent = workspace
	end
	return f
end

------------------------------------------------------------------------
-- the spec itself
------------------------------------------------------------------------

function CalamityService.SetWonder(player: Player, on: boolean)
	if on and not Items.Has(player, "wonder") then
		return
	end
	player:SetAttribute("WonderOn", on or nil)
	if player.Character then
		player.Character:SetAttribute("Wonder", on or nil)
	end
end

-- a dark hole through a body part that closes again (entry and, if given, exit)
local function hole(model: Model, partName: string, worldPoint: Vector3, normal: Vector3, size: number)
	local part = model:FindFirstChild(partName)
	if not part or not part:IsA("BasePart") then
		return
	end
	local d = Instance.new("Part")
	d.Name = "WonderHole"
	d.Shape = Enum.PartType.Cylinder
	d.Size = Vector3.new(0.3, size, size) -- (thick: it reads as a hole, not as a sticker)
	d.Color = Color3.fromRGB(8, 6, 6)
	d.Material = Enum.Material.SmoothPlastic
	d.CanCollide = false
	d.CanQuery = false
	d.CanTouch = false
	d.Massless = true
	d.CFrame = CFrame.lookAt(worldPoint, worldPoint + normal) * CFrame.Angles(0, math.rad(90), 0)
	local rim = Instance.new("Part")
	rim.Name = "WonderHoleRim"
	rim.Shape = Enum.PartType.Cylinder
	rim.Size = Vector3.new(0.2, size * 1.45, size * 1.45)
	rim.Color = Color3.fromRGB(120, 18, 14)
	rim.Material = Enum.Material.Neon
	rim.Transparency = 0.35
	rim.CanCollide = false
	rim.CanQuery = false
	rim.CanTouch = false
	rim.Massless = true
	rim.CFrame = d.CFrame * CFrame.new(-0.02, 0, 0)
	for _, p in { rim, d } do
		local w = Instance.new("WeldConstraint")
		w.Part0 = part
		w.Part1 = p
		w.Parent = p
		p.Parent = model
		TweenService:Create(p, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.0), { Transparency = 1 }):Play()
		Debris:AddItem(p, 2.8)
	end
	-- the body opens: a puff of dark mist out of the hole
	local mist = Instance.new("ParticleEmitter")
	mist.Rate = 0
	mist.Lifetime = NumberRange.new(0.5, 1.0)
	mist.Speed = NumberRange.new(2, 6)
	mist.SpreadAngle = Vector2.new(50, 50)
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.5), NumberSequenceKeypoint.new(1, size * 1.4) })
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	mist.Color = ColorSequence.new(Color3.fromRGB(30, 8, 8))
	mist.LightEmission = 0
	mist.Parent = d
	mist:Emit(14)
	GoreService.Sound("ricochet", worldPoint, 0.5)
end

-- who is behind this? (a person, or something a person held / threw last)
local function culprit(opts: any): Player?
	local a = opts and opts.attacker
	if typeof(a) == "Instance" and a:IsA("Player") then
		return a
	end
	return nil
end

-- called by DamageService before it hurts anything: true = nothing happens to this body
function CalamityService.Shield(model: Model, region: string, dmg: number, point: Vector3?, opts: any): boolean
	if model:GetAttribute("Wonder") ~= true then
		return false
	end
	local cause = opts and opts.cause
	if cause == "Fell" then
		return false -- falling still hurts
	end
	local wonderPlayer = Players:GetPlayerFromCharacter(model)
	local who = culprit(opts)
	if who and who ~= wonderPlayer then
		CalamityService.Mark(who, wonderPlayer, "attack", false)
	end
	if point and dmg > 3 then
		local partName = region == "Torso" and "Torso" or (region == "Head" and "Head" or nil)
		local part = partName and model:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			local n = (point - part.Position)
			n = n.Magnitude > 0.05 and n.Unit or part.CFrame.LookVector
			hole(model, partName, part.Position + n * (part.Size.Z * 0.5), n, 2.0)
		end
	end
	return true
end

-- a bullet: it goes through; there is an entry and an exit hole
function CalamityService.ShieldBullet(model: Model, region: string, point: Vector3, dir: Vector3, shooter: Player?): boolean
	if model:GetAttribute("Wonder") ~= true then
		return false
	end
	local wonderPlayer = Players:GetPlayerFromCharacter(model)
	if shooter and shooter ~= wonderPlayer then
		CalamityService.Mark(shooter, wonderPlayer, "shot", false)
	end
	local partName = region == "Head" and "Head" or (region == "Torso" and "Torso" or nil)
	local part = partName and model:FindFirstChild(partName)
	if part and part:IsA("BasePart") and dir.Magnitude > 0.1 then
		local d = dir.Unit
		hole(model, partName, point, -d, 1.9)
		hole(model, partName, point + d * math.max(part.Size.Z, 1), d, 2.3)
	end
	return true
end

-- somebody grabbed / dragged the Wonder player
function CalamityService.OnGrab(grabber: Player, victim: Model)
	local wonderPlayer = Players:GetPlayerFromCharacter(victim)
	if grabber and grabber ~= wonderPlayer then
		CalamityService.Mark(grabber, wonderPlayer, "grab", true)
	end
end

------------------------------------------------------------------------
-- marking
------------------------------------------------------------------------

function CalamityService.Mark(target: Player, wonder: Player?, why: string, immediate: boolean)
	if not target or not target.Parent or target == wonder then
		return
	end
	local now = os.clock()
	local m = marks[target]
	if not m then
		m = { level = 1, nextAt = now + rng:NextNumber(5, 25), dodges = 0, events = 0, busy = false }
		marks[target] = m
	else
		m.level = math.min(m.level + 0.5, 6) -- every further attempt makes it worse
	end
	if immediate then
		m.nextAt = math.min(m.nextAt, now + 1.5)
	end
end

function CalamityService.Marked(target: Player): boolean
	return marks[target] ~= nil
end

------------------------------------------------------------------------
-- the events
------------------------------------------------------------------------

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundBelow(pos: Vector3): Vector3
	local ignore = { fxFolder() }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	groundParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -80, 0), groundParams)
	return hit and hit.Position or (pos - Vector3.new(0, 3, 0))
end

local function telegraph(point: Vector3, radius: number, seconds: number)
	local ring = Instance.new("Part")
	ring.Name = "CalamityRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(point + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(235, 40, 30)
	ring.Transparency = 0.55
	ring.Parent = fxFolder()
	TweenService:Create(ring, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, math.max(1, math.floor(seconds / 0.44)), true), { Transparency = 0.15 }):Play()
	Debris:AddItem(ring, seconds)
end

local function live(player: Player): (Model?, BasePart?)
	local c = player.Character
	if not c or c:GetAttribute("Dead") then
		return nil, nil
	end
	local torso = c:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return nil, nil
	end
	return c, torso
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function hurt(c: Model, region: string, dmg: number, cause: string, knockSeconds: number?, launch: Vector3?)
	if c:GetAttribute("Dead") then
		return
	end
	DamageService.ApplyDamage(c, region, dmg, nil, { cause = cause, allowSever = dmg >= 90 })
	if launch then
		DamageService.Blast(c, launch, knockSeconds or 2)
	elseif knockSeconds then
		DamageService.Knock(c, region, nil, knockSeconds)
	end
end

local function loosePart(size: number, shape: Enum.PartType, color: Color3, material: Enum.Material, cf: CFrame): Part
	local p = Instance.new("Part")
	p.Name = "CalamityRock"
	p.Shape = shape
	p.Size = Vector3.new(size, size, size)
	p.Color = color
	p.Material = material
	p.CFrame = cf
	p.CustomPhysicalProperties = PhysicalProperties.new(4, 0.6, 0.1, 1, 1)
	p.Parent = workspace:FindFirstChild("SpawnedProps") or workspace
	pcall(function()
		p:SetNetworkOwner(nil)
	end)
	Debris:AddItem(p, 14)
	return p
end

-- something falls on the spot where the target stood a moment ago
local function dropOn(player: Player, sev: number, what: string, size: number, damage: number, speed: number): boolean
	local c, torso = live(player)
	if not c or not torso then
		return false
	end
	local p0 = groundBelow(torso.Position)
	local warn = 1.35
	telegraph(p0, size * 0.75 + 1.5, warn)
	task.wait(warn - 0.75)
	local obj: Instance? = nil
	local top = p0 + Vector3.new(0, 55, 0)
	if what == "rock" then
		local r = loosePart(size, Enum.PartType.Ball, Color3.fromRGB(96, 94, 90), Enum.Material.Slate, CFrame.new(top))
		r.AssemblyLinearVelocity = Vector3.new(0, -speed, 0)
		obj = r
	else
		local inst = CalamityService.PlaceProp and CalamityService.PlaceProp(what, CFrame.new(top) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0), nil)
		if inst and inst:IsA("Model") and inst.PrimaryPart then
			inst.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, -speed, 0)
			Debris:AddItem(inst, 30)
			obj = inst
		end
	end
	task.wait(0.78)
	GoreService.Sound("heavyHit", p0, 1)
	local c2, t2 = live(player)
	if not c2 or not t2 then
		return false
	end
	local horiz = flat(t2.Position - p0).Magnitude
	local vert = t2.Position.Y - p0.Y
	if horiz < size * 0.6 + 2.4 and vert < 12 then
		hurt(c2, "Torso", damage, "Crushed by a calamity", 3, nil)
		hurt(c2, "Head", damage * 0.4, "Crushed by a calamity", nil, nil)
		return true
	end
	return false
end

local function carFromBehind(player: Player, sev: number): boolean
	local c, torso = live(player)
	if not c or not torso or not CalamityService.PlaceProp then
		return false
	end
	local vel = flat(torso.AssemblyLinearVelocity)
	local fwd = vel.Magnitude > 4 and vel.Unit or flat(torso.CFrame.LookVector)
	if fwd.Magnitude < 0.1 then
		fwd = Vector3.new(0, 0, -1)
	end
	fwd = fwd.Unit
	local p0 = groundBelow(torso.Position)
	local start = groundBelow(p0 - fwd * 75) + Vector3.new(0, 2.2, 0)
	local car = CalamityService.PlaceProp("car", CFrame.lookAt(start, start + fwd), nil)
	if not car or not car:IsA("Model") or not car.PrimaryPart then
		return false
	end
	telegraph(p0, 4, 1.2)
	GoreService.Sound("carCrash", start, 0.35)
	local root = car.PrimaryPart
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local heading = fwd
	local hit = false
	local t0 = os.clock()
	local lastPos = start
	local lastT = os.clock()
	local passed = 0
	while os.clock() - t0 < 5.5 do
		local dt = RunService.Heartbeat:Wait()
		local c2, t2 = live(player)
		if not car.Parent or not root.Parent then
			break
		end
		local pos = root.Position
		if c2 and t2 then
			local to = flat(t2.Position - pos)
			if to.Magnitude > 0.1 then
				-- it steers towards the target, but not fast: running sideways saves you
				local want = to.Unit
				local ang = math.acos(math.clamp(heading:Dot(want), -1, 1))
				local maxTurn = math.rad(70) * dt
				local k = ang > 0.0001 and math.min(1, maxTurn / ang) or 1
				heading = (heading:Lerp(want, k)).Unit
			end
			if to.Magnitude < 6.5 and math.abs(t2.Position.Y - pos.Y) < 5 and not hit then
				hit = true
				hurt(c2, "Torso", 55 + sev * 18, "Run over by a ghost car", 3, heading * 85 + Vector3.new(0, 38, 0))
				hurt(c2, "LeftLeg", 40, "Run over by a ghost car", nil, nil)
				hurt(c2, "RightLeg", 40, "Run over by a ghost car", nil, nil)
				GoreService.Sound("carCrash", pos, 1)
			end
			if hit then
				passed += dt
			end
		end
		local nextPos = pos + heading * 85 * dt
		local g = groundBelow(nextPos)
		root.Parent:PivotTo(CFrame.lookAt(Vector3.new(nextPos.X, g.Y + 2.2, nextPos.Z), Vector3.new(nextPos.X, g.Y + 2.2, nextPos.Z) + heading))
		if passed > 0.5 then
			break
		end
	end
	local pos = root.Position
	ExplosionService.Explode(pos, { radius = 22, damage = 120, power = 110, cause = "Ghost car explosion" })
	car:Destroy()
	return hit
end

local function grenadeAtFeet(player: Player, sev: number): boolean
	local c, torso = live(player)
	if not c or not torso then
		return false
	end
	local p0 = groundBelow(torso.Position) + Vector3.new(0, 0.5, 0)
	local g = Instance.new("Part")
	g.Name = "CalamityGrenade"
	g.Shape = Enum.PartType.Ball
	g.Size = Vector3.new(0.9, 0.9, 0.9)
	g.Color = Color3.fromRGB(58, 74, 48)
	g.Material = Enum.Material.Metal
	g.CFrame = CFrame.new(p0)
	g.Parent = fxFolder()
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 60, 40)
	light.Range = 8
	light.Parent = g
	pcall(function()
		g:SetNetworkOwner(nil)
	end)
	GoreService.Sound("pin", p0, 1)
	local fuse = math.max(1.1, 2.4 - sev * 0.2)
	local t0 = os.clock()
	local n = 0
	while os.clock() - t0 < fuse do
		n += 1
		light.Enabled = n % 2 == 0
		GoreService.Sound("beep", g, 0.6)
		task.wait(0.28)
	end
	local pos = g.Position
	g:Destroy()
	ExplosionService.Explode(pos, { radius = Config.GrenadeRadius, damage = Config.GrenadeDamage, power = Config.GrenadePower, cause = "Calamity grenade" })
	local c2, t2 = live(player)
	return c2 ~= nil and t2 ~= nil and (t2.Position - pos).Magnitude < Config.GrenadeRadius * 0.75
end

local function barrelRing(player: Player, sev: number): boolean
	local c, torso = live(player)
	if not c or not torso or not CalamityService.PlaceProp then
		return false
	end
	local p0 = groundBelow(torso.Position)
	telegraph(p0, 9, 1.8)
	local barrels = {}
	for i = 1, 3 + math.floor(sev / 2) do
		local a = (i / 6) * math.pi * 2 + rng:NextNumber(0, 1)
		local pos = p0 + Vector3.new(math.cos(a) * 4.5, 2.5, math.sin(a) * 4.5)
		local b = CalamityService.PlaceProp("explosive_barrel", CFrame.new(pos), nil)
		if b then
			table.insert(barrels, b)
			Debris:AddItem(b, 20)
		end
		task.wait(0.12)
	end
	task.wait(1.7)
	for _, b in barrels do
		if b.Parent then
			ExplosionService.Detonate(b)
			task.wait(0.15)
		end
	end
	local c2, t2 = live(player)
	return c2 ~= nil and t2 ~= nil and (t2.Position - p0).Magnitude < 10
end

local function lightning(player: Player, sev: number): boolean
	local c, torso = live(player)
	if not c or not torso then
		return false
	end
	local p0 = groundBelow(torso.Position)
	telegraph(p0, 7, 1.1)
	task.wait(1.1)
	local bolt = Instance.new("Part")
	bolt.Name = "CalamityBolt"
	bolt.Anchored = true
	bolt.CanCollide = false
	bolt.CanQuery = false
	bolt.Material = Enum.Material.Neon
	bolt.Color = Color3.fromRGB(190, 220, 255)
	bolt.Size = Vector3.new(1.2, 140, 1.2)
	bolt.CFrame = CFrame.new(p0 + Vector3.new(0, 70, 0))
	bolt.Parent = fxFolder()
	Debris:AddItem(bolt, 0.18)
	ExplosionService.Explode(p0, { radius = 16, damage = 100, power = 70, cause = "Struck by lightning" })
	local c2, t2 = live(player)
	if c2 and t2 and flat(t2.Position - p0).Magnitude < 8 then
		FireService.SetOnFire(c2, 6, nil)
		return true
	end
	return false
end

local function fireRing(player: Player, sev: number): boolean
	local c, torso = live(player)
	if not c or not torso then
		return false
	end
	local p0 = groundBelow(torso.Position)
	telegraph(p0, 8, 1.4)
	task.wait(1.2)
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		FireService.Ignite(p0 + Vector3.new(math.cos(a) * 5.5, 0, math.sin(a) * 5.5), 3.2, 9, nil)
	end
	FireService.Ignite(p0, 4, 9, nil)
	local c2, t2 = live(player)
	return c2 ~= nil and t2 ~= nil and flat(t2.Position - p0).Magnitude < 8
end

local function meteor(player: Player, sev: number): boolean
	local c, torso = live(player)
	if not c or not torso then
		return false
	end
	local p0 = groundBelow(torso.Position)
	telegraph(p0, 24, 2.4)
	GoreService.Sound("explosion", p0 + Vector3.new(0, 40, 0), 0.4)
	task.wait(1.4)
	local m = loosePart(13, Enum.PartType.Ball, Color3.fromRGB(70, 40, 30), Enum.Material.Basalt, CFrame.new(p0 + Vector3.new(0, 160, 0)))
	m.Anchored = true
	local glow = Instance.new("Fire")
	glow.Size = 22
	glow.Heat = 20
	glow.Parent = m
	local t0 = os.clock()
	while os.clock() - t0 < 1.0 do
		local dt = RunService.Heartbeat:Wait()
		m.Position = m.Position - Vector3.new(0, 150 * dt, 0)
	end
	m:Destroy()
	ExplosionService.Explode(p0, { radius = 42, damage = 320, power = 200, cause = "Hit by a meteor" })
	FireService.Ignite(p0, 14, 14, nil)
	local c2, t2 = live(player)
	return c2 ~= nil and t2 ~= nil and flat(t2.Position - p0).Magnitude < 28
end

-- a plane comes down on the target: the reward for dodging everything else
local function planeCrash(player: Player, sev: number): boolean
	local c, torso = live(player)
	if not c or not torso then
		return false
	end
	local p0 = groundBelow(torso.Position)
	local dir = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
	dir = dir.Magnitude > 0.2 and dir.Unit or Vector3.new(0, 0, 1)
	telegraph(p0, 30, 3.2)
	GoreService.Sound("explosion", p0 + Vector3.new(0, 80, 0), 0.5)
	-- the plane (simple parts), burning, comes in low and steep
	local plane = Instance.new("Model")
	plane.Name = "CalamityPlane"
	local function pp(name: string, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CFrame = off
		p.Parent = plane
		return p
	end
	local startPos = p0 - dir * 260 + Vector3.new(0, 200, 0)
	local base = CFrame.lookAt(startPos, p0)
	local body = pp("Fuselage", Vector3.new(4, 4, 26), base, Color3.fromRGB(205, 208, 212), Enum.Material.Metal)
	pp("Nose", Vector3.new(3.6, 3.6, 4), base * CFrame.new(0, 0, -14), Color3.fromRGB(170, 172, 176), Enum.Material.Metal)
	pp("Wing", Vector3.new(34, 0.6, 6), base * CFrame.new(0, -0.4, -1), Color3.fromRGB(190, 192, 196), Enum.Material.Metal)
	pp("TailFin", Vector3.new(0.5, 6, 4), base * CFrame.new(0, 4, 11), Color3.fromRGB(190, 40, 36), Enum.Material.Metal)
	pp("TailWing", Vector3.new(11, 0.4, 3), base * CFrame.new(0, 0.8, 11.5), Color3.fromRGB(190, 192, 196), Enum.Material.Metal)
	for _, x in { -9, 9 } do
		pp("Engine", Vector3.new(2.4, 2.4, 6), base * CFrame.new(x, -1.6, -3), Color3.fromRGB(80, 82, 86), Enum.Material.Metal)
	end
	for _, part in plane:GetChildren() do
		local f = Instance.new("Fire")
		f.Size = 10
		f.Heat = 14
		f.Parent = part
		if part.Name == "Engine" or part.Name == "Fuselage" then
			local s = Instance.new("Smoke")
			s.Size = 14
			s.Opacity = 0.5
			s.Color = Color3.fromRGB(30, 30, 30)
			s.Parent = part
		end
	end
	plane.PrimaryPart = body
	plane.Parent = fxFolder()
	local t0 = os.clock()
	local dur = 2.6
	while os.clock() - t0 < dur do
		local alpha = (os.clock() - t0) / dur
		local pos = startPos:Lerp(p0 + Vector3.new(0, 4, 0), alpha * alpha * (3 - 2 * alpha) * 0.2 + alpha * 0.8)
		plane:PivotTo(CFrame.lookAt(pos, p0 + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, alpha * 0.5))
		RunService.Heartbeat:Wait()
	end
	plane:Destroy()
	GoreService.Sound("explosion", p0, 1)
	ExplosionService.Explode(p0, { radius = 50, damage = 420, power = 240, cause = "A plane fell on them" })
	ExplosionService.Explode(p0 + dir * 14, { radius = 28, damage = 160, power = 140, cause = "A plane fell on them" })
	FireService.Ignite(p0, 18, 16, nil)
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		FireService.Ignite(p0 + Vector3.new(math.cos(a) * 12, 0, math.sin(a) * 12), 5, 12, nil)
	end
	local c2, t2 = live(player)
	return c2 ~= nil and t2 ~= nil and flat(t2.Position - p0).Magnitude < 32
end

-- name, lowest severity it can show up at, function (returns: did it hit)
local EVENTS: { { name: string, min: number, run: (Player, number) -> boolean } } = {
	{ name = "rock", min = 1, run = function(p, s) return dropOn(p, s, "rock", 2.4 + s * 1.3, 14 + s * 12, 55) end },
	{ name = "crate", min = 1, run = function(p, s) return dropOn(p, s, "crate_big", 3.2, 16 + s * 10, 60) end },
	{ name = "anvil", min = 2, run = function(p, s) return dropOn(p, s, "anvil", 2.6, 40 + s * 18, 90) end },
	{ name = "piano", min = 3, run = function(p, s) return dropOn(p, s, "piano", 5, 60 + s * 20, 80) end },
	{ name = "grenade", min = 2, run = grenadeAtFeet },
	{ name = "car", min = 3, run = carFromBehind },
	{ name = "barrels", min = 3, run = barrelRing },
	{ name = "fire", min = 3, run = fireRing },
	{ name = "lightning", min = 4, run = lightning },
	{ name = "meteor", min = 5, run = meteor },
	{ name = "plane", min = 6, run = planeCrash },
}

local function severity(m: Mark): number
	return math.clamp(math.floor(m.level + m.dodges), 1, 6) -- (6 = a long dodge streak: a plane comes down)
end

local function runEvent(player: Player, m: Mark)
	m.busy = true
	local sev = severity(m)
	local eligible = {}
	for _, e in EVENTS do
		if e.min <= sev then
			-- the more severe, the more the heavy ones are preferred
			local weight = 1 + math.max(0, e.min - 1) * (sev - 1) * 0.6
			for _ = 1, math.ceil(weight) do
				table.insert(eligible, e)
			end
		end
	end
	local e = eligible[rng:NextInteger(1, #eligible)]
	local ok, hit = pcall(e.run, player, sev)
	if not ok then
		warn("calamity event failed:", e.name, hit)
		hit = true -- (do not punish a broken event with a worse one)
	end
	m.events += 1
	if hit then
		m.dodges = math.max(0, m.dodges - 1)
	else
		m.dodges += 1 -- it dodged: the next one is worse
	end
	local gap = MIN_GAP + (MAX_GAP - MIN_GAP) * (rng:NextNumber() ^ 2)
	m.nextAt = os.clock() + gap
	m.busy = false
end

------------------------------------------------------------------------

function CalamityService.Init()
	DamageService.Shield = CalamityService.Shield
	DamageService.ShieldBullet = CalamityService.ShieldBullet
	OwnershipService.OnGrabWonder = CalamityService.OnGrab

	local function setup(player: Player)
		player.CharacterAdded:Connect(function(char)
			if player:GetAttribute("WonderOn") then
				char:SetAttribute("Wonder", true)
			end
		end)
	end
	for _, p in Players:GetPlayers() do
		setup(p)
	end
	Players.PlayerAdded:Connect(setup)
	Players.PlayerRemoving:Connect(function(p)
		marks[p] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = os.clock()
			for player, m in marks do
				if not player.Parent then
					marks[player] = nil
				elseif not m.busy and now >= m.nextAt then
					local c = player.Character
					if c and not c:GetAttribute("Dead") and not c:GetAttribute("God") and not c:GetAttribute("InLobby") then
						task.spawn(runEvent, player, m)
					else
						m.nextAt = now + 4 -- (dead / flying / waiting: later)
					end
				end
				local c = player.Character
				if c and c:GetAttribute("Dead") then
					marks[player] = nil -- (v1.9.1) death ends the mark: no dying again and again
				end
			end
		end
	end)
end

return CalamityService
