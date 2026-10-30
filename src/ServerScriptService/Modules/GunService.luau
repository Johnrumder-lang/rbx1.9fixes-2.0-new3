--!nonstrict
-- GunService: server-side shooting (pistol, revolver, rifle, SMG, shotgun, sniper). Stats per gun in
-- Config.Guns. Reloading is done by hand (ItemService.Reload). You can shoot yourself.
-- Revolver and sniper hits can take limbs off (severLimbs).
--
-- The shooter's client sees its own gun and body exactly, the server only sees a copy that lags
-- behind. So the client reports where the muzzle is, which way each bullet / pellet flies and what
-- it hit; the server checks all of it (you hold this gun, ammo, fire rate, the muzzle is at your
-- body, the hit lies on the line of fire, no wall in between, the hit part is really there) and
-- only then applies the damage. A claim that fails a check falls back to the server's own raycast.
--
-- Hits: bodies (damage + the hit body part is knocked), cars (hidden HP), explosive barrels and
-- grenades (boom), loose props (pushed).
-- Shotgun: the pellets that hit the same body part are added up into one hit. Up close every pellet
-- does more (x2.2 point blank) and a body part that takes enough in one shot is blown off.
-- (v2.0) Bullets go THROUGH bodies when the gun is strong enough (Config.Penetration): the bullet leaves an
-- exit wound, sprays blood forward along its path and flies on with what is left (hits the next body part,
-- the next person, the wall behind). A sniper round goes through several people.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TimeScale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TimeScale")) -- (v2.8) the Sandevistan's slow motion
local Items = require(Shared:WaitForChild("Items"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))
local Ballistics = require(Shared:WaitForChild("Ballistics"))

local Modules = script.Parent
local DamageService = require(Modules:WaitForChild("DamageService"))
local GoreService = require(Modules:WaitForChild("GoreService"))
local OwnershipService = require(Modules:WaitForChild("OwnershipService"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GunRemote = Remotes:WaitForChild("Gun") :: RemoteEvent

local GunService = {}
GunService.IsSlow = nil :: (() -> boolean)?
GunService.OnShotLine = nil :: ((Player, Vector3, Vector3, number) -> ())? -- (v2.8) a shot was fired (SENTRY REFLEX feels it) -- (v2.1) slow motion runs: bullets fly instead of hitting at once

-- set by Main (avoids require cycles): hooks for things that react to bullets
GunService.OnHitItem = nil :: ((Model, number) -> ())?
GunService.OnHitCar = nil :: ((Model, number, Player?) -> ())? -- (car, damage, shooter)
GunService.OnHitPart = nil :: ((BasePart, Player?) -> ())? -- any world part hit (tires pop)
GunService.OnGlass = nil :: ((BasePart, Vector3, Vector3) -> boolean)? -- shatter glass (true = it broke)
GunService.OnHitExplosive = nil :: ((Model, Player) -> ())?
GunService.OnHitGrenade = nil :: ((Model, Player) -> ())?
-- (v2.0)
GunService.OnHitWorld = nil :: ((BasePart, Vector3, Vector3, number, Player?) -> ())? -- a building wall was hit
GunService.OnHitCreature = nil :: ((Model, BasePart, number, Player?, Vector3) -> ())? -- (v2.0) a creature's hit box
GunService.OnTase = nil :: ((Model, string, Vector3, Vector3, Player?, Model) -> ())? -- the taser hit a body
GunService.OnTaserShot = nil :: ((Player, Model, Vector3, any) -> ())? -- the taser was fired (wires)
GunService.OnHarpoonShot = nil :: ((Player, Model, Vector3, any) -> ())? -- the harpoon gun was fired (the line)

local lastShot: { [Model]: number } = {}

local function finite(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
end

local function holdsGun(player: Player, gun: Model): boolean
	local char = player.Character
	if not char or char:GetAttribute("Dead") or not gun.PrimaryPart then
		return false
	end
	local holder = OwnershipService.ItemHolder(gun)
	if holder then
		return holder == player
	end
	-- (no server weld yet, e.g. the grab request is still on its way)
	local id = gun:GetAttribute("HolderId")
	local torso = char:FindFirstChild("Torso")
	return (id == nil or id == player.UserId) and torso ~= nil and (torso.Position - gun.PrimaryPart.Position).Magnitude < 20
end

local function lagTolerance(part: BasePart): number
	if part.Anchored then
		return 0.75
	end
	if DamageService.BodyOf(part) then
		return Config.GunHitTolerance
	end
	return 5
end

local function baseParams(gun: Model, extra: Instance?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = false
	local ignore: { Instance } = { gun }
	if extra then
		table.insert(ignore, extra)
	end
	local fx = workspace:FindFirstChild("FX")
	if fx then
		table.insert(ignore, fx)
	end
	params.FilterDescendantsInstances = ignore
	return params
end

-- the client's claimed hit, or nil if it does not hold up
local function checkClaim(gun: Model, origin: Vector3, dir: Vector3, range: number, part: any, pos: any, normal: any)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then
		return nil
	end
	if typeof(pos) ~= "Vector3" or not finite(pos) then
		return nil
	end
	local toHit = pos - origin
	local dist = toHit.Magnitude
	if dist > range + 2 or dist < 0.05 then
		return nil
	end
	if toHit.Unit:Dot(dir) < math.cos(math.rad(2)) then
		return nil -- not on the line of fire
	end
	local localPos = part.CFrame:PointToObjectSpace(pos)
	local half = part.Size * 0.5
	local outside = Vector3.new(math.max(0, math.abs(localPos.X) - half.X), math.max(0, math.abs(localPos.Y) - half.Y), math.max(0, math.abs(localPos.Z) - half.Z))
	if outside.Magnitude > lagTolerance(part) then
		return nil -- the part is not there
	end
	-- no static wall between the muzzle and the hit (moving things are skipped, they may lag)
	local params = baseParams(gun)
	local walls = workspace:Raycast(origin, toHit.Unit * math.max(0, dist - 0.3), params)
	local guard = 0
	while walls and guard < 6 do
		guard += 1
		local w = walls.Instance
		if w == part then
			break
		end
		if w.Material == Enum.Material.Glass and GunService.OnGlass then
			GunService.OnGlass(w, walls.Position, dir) -- (the bullet goes through the window)
		elseif w.Anchored and w.CanCollide and w.Transparency < 0.95 then
			return nil
		end
		local ignore = params.FilterDescendantsInstances
		table.insert(ignore, w)
		params.FilterDescendantsInstances = ignore
		walls = workspace:Raycast(origin, toHit.Unit * math.max(0, dist - 0.3), params)
	end
	return {
		Instance = part,
		Position = pos,
		Normal = (typeof(normal) == "Vector3" and finite(normal) and normal.Magnitude > 0.5) and normal.Unit or -dir,
		Material = part.Material,
	}
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

-- one bullet / pellet. Body hits go to `onBody` (the caller applies the damage; `keep` = what is left of the
-- bullet's damage after the body parts it already went through). `pen` = studs of body it can go through.
local function resolve(player: Player?, gun: Model, origin: Vector3, dir: Vector3, range: number, claim, pellet: boolean, push: number, onBody: (Model, string, Vector3, Vector3, number) -> (), shooterBody: Instance?, pen: number?)
	local params = baseParams(gun, shooterBody)
	local function cast(from: Vector3, dist: number)
		local r = workspace:Raycast(from, dir * dist, params)
		return r and { Instance = r.Instance, Position = r.Position, Normal = r.Normal, Material = r.Material } or nil
	end
	local function skip(inst: Instance)
		local list = params.FilterDescendantsInstances
		table.insert(list, inst)
		params.FilterDescendantsInstances = list
	end
	local hit = nil
	if typeof(claim) == "table" then
		hit = checkClaim(gun, origin, dir, range, claim.part, claim.pos, claim.n)
	end
	if not hit then
		hit = cast(origin, range)
	end
	local left = pellet and 0 or (pen or 0)
	local keep = 1
	local through = 0
	local panes = 0
	local exits = {}
	local kind = "none"
	while hit do
		local part = hit.Instance
		-- glass shatters and the bullet flies on (through up to 3 panes)
		if panes < 3 and GunService.OnGlass and part:IsA("BasePart") and part.Material == Enum.Material.Glass then
			if GunService.OnGlass(part, hit.Position, dir) then
				panes += 1
				skip(part)
				local rest = range - (hit.Position - origin).Magnitude
				hit = rest > 0.5 and cast(hit.Position, rest) or nil
				continue
			end
		end
		local body, region = DamageService.BodyOf(part)
		if body and region then
			onBody(body, region, hit.Position, dir, keep)
			-- does it come out the other side?
			local bp = body:FindFirstChild(RigInfo.RegionPart[region] or "")
			if left > 0 and through < Config.PenetrationMaxParts and bp and bp:IsA("BasePart") and not body:GetAttribute("Wonder") then
				local thick = Ballistics.ExitDistance(bp, hit.Position, dir)
				if thick <= left then
					left -= thick
					through += 1
					local exitPos = hit.Position + dir * thick
					table.insert(exits, { p = exitPos, k = keep })
					GoreService.ExitHole(bp, exitPos, keep * (pen or 1))
					-- (v2.0) and a real hole through it, on every screen (WoundHoles)
					GoreService.FX({ t = "tunnel", part = bp, a = bp.CFrame:PointToObjectSpace(hit.Position), b = bp.CFrame:PointToObjectSpace(exitPos), k = keep * (pen or 1) })
					keep *= Config.PenetrationDamageKeep
					skip(bp)
					if part ~= bp then
						skip(part)
					end
					local rest = range - (exitPos - origin).Magnitude
					hit = rest > 0.5 and cast(exitPos, rest) or nil
					kind = "none"
					continue
				end
			end
			kind = "body"
			break
		end
		kind = "world"
		local car = modelWith(part, "Car")
		local boom = modelWith(part, "Explosive")
		local item = Items.ModelOf(part)
		if car and GunService.OnHitCar then
			GunService.OnHitCar(car, (pellet and Config.CarBulletDamage * 0.4 or Config.CarBulletDamage) * keep, player)
		end
		if item and Items.Kind(item) == "boombox" and GunService.OnHitItem then
			GunService.OnHitItem(item, pellet and 9 or 28) -- (v1.9.1: bullets break a boombox)
		end
		if GunService.OnHitPart and part:IsA("BasePart") then
			GunService.OnHitPart(part, player)
		end
		-- (v2.0) the Crawler, sharks
		local creature = modelWith(part, "Creature")
		if creature and GunService.OnHitCreature then
			local st = Config.Guns[Items.Kind(gun) or ""]
			local dmg = Config.BulletDamage.Torso * ((st and st.damageMult) or 0.62) * keep * (pellet and 0.35 or 1)
			GunService.OnHitCreature(creature, part, dmg, player, hit.Position)
		end
		if boom and GunService.OnHitExplosive then
			GunService.OnHitExplosive(boom, player)
		end
		local ik = item and Items.Kind(item)
		if item and (ik == "grenade" or ik == "flash" or ik == "c4" or ik == "virus" or ik == "molotov") and GunService.OnHitGrenade then
			GunService.OnHitGrenade(item, player)
		end
		if GunService.OnHitWorld and part:IsA("BasePart") then
			GunService.OnHitWorld(part, hit.Position, dir, (pellet and 0.4 or 1) * keep, player) -- (v2.0: buildings crumble)
		end
		if part:IsA("BasePart") and not part.Anchored then
			-- the owner of the object applies the push
			GoreService.FX({ t = "push", part = part, i = dir * (pellet and push * 0.4 or push * 0.7) * keep * math.min(part.AssemblyMass, 4), p = hit.Position })
		end
		break
	end
	return {
		to = hit and hit.Position or (origin + dir * range),
		n = hit and hit.Normal or Vector3.yAxis,
		k = kind,
		mat = hit and hit.Material.Name or "",
		part = hit and hit.Instance or nil,
		ex = #exits > 0 and exits or nil,
	}
end

function GunService.Fire(player: Player, gun: Model, originIn: any, shots: any)
	if player.Character and (player.Character:GetAttribute("TemporalFrozenUntil") or 0) > workspace:GetServerTimeNow() then return end
	if not holdsGun(player, gun) then
		return
	end
	local kind = Items.Kind(gun) or "pistol"
	local stats = Config.Guns[kind] or Config.Guns.pistol
	if stats.projectile then
		return -- (the rocket launcher fires through ItemService.FireRocket)
	end
	local shotgun = kind == "shotgun"
	local now = os.clock()
	if now - (lastShot[gun] or 0) < stats.interval * 0.8 or gun:GetAttribute("Reloading") then
		return
	end
	lastShot[gun] = now
	local muzzle = Items.Muzzle(gun)
	local char = player.Character
	local torso = char and char:FindFirstChild("Torso")
	if not muzzle or not torso then
		return
	end

	-- where the shot starts: the shooter's own (exact) muzzle, if it is plausibly at their body
	local origin = muzzle.WorldPosition
	if typeof(originIn) == "Vector3" and finite(originIn) and (originIn - torso.Position).Magnitude <= Config.GunOriginTolerance then
		origin = originIn
	end

	local ammo = gun:GetAttribute("Ammo") or 0
	if ammo <= 0 then
		GoreService.FX({ t = "sfx", n = "dryfire", w = origin, v = 1, by = player.UserId })
		return
	end
	gun:SetAttribute("Ammo", ammo - 1)
	if stats.bolt and ammo - 1 <= 0 then
		for _, p in gun:GetDescendants() do
			if p:IsA("BasePart") and p:GetAttribute("Warhead") then
				p.Transparency = 1 -- (the bolt is gone from the rail)
			end
		end
	end

	local barrel = muzzle.WorldCFrame.LookVector
	local count = shotgun and Config.ShotgunPellets or 1
	-- (v2.0) a gun can reach further than its kind (the sniper mode's rifle: RangeMult)
	local rm = gun:GetAttribute("RangeMult")
	local range = (stats.range or Config.GunRange) * ((typeof(rm) == "number" and rm >= 1 and rm <= 10) and rm or 1)
	local list = typeof(shots) == "table" and shots or {}
	local results = {}
	local pushMult = stats.push / Config.Guns.pistol.push
	-- (v2.1) in the Sandevistan's slow motion a bullet is a SLOW bullet: you can see it crawl, and it hits when it arrives
	-- (v2.8) a slow bullet resolves from where it is when it arrives (flown: the studs it covered; nil = from the muzzle)
	local function resolveAll(flown: number?)
	-- body hits of this shot, added up per body part
	local bodyHits: { [Model]: { [string]: { n: number, point: Vector3, dir: Vector3 } } } = {}
	local function onBody(body: Model, region: string, point: Vector3, dir: Vector3, keep: number)
		if stats.dart then
			GunService.Dart(body, region, point, dir, stats.dart, player)
			return
		end
		if stats.taser then
			if GunService.OnTase then
				GunService.OnTase(body, region, point, dir, player, gun)
			end
			return
		end
		if stats.harpoon then
			DamageService.ApplyDamage(body, region, Config.HarpoonDamage * (Config.LimbMultiplier[region] or 1), point, {
				cause = "Harpooned by " .. player.DisplayName,
				allowSever = false,
				attacker = player,
				bleed = Config.BulletBleed.Limb,
				bleedTime = Config.BulletBleedTime,
			})
			return
		end
		if not shotgun then
			local limb = region ~= "Head" and region ~= "Torso"
			DamageService.ApplyBullet(body, region, point, dir, player, false, {
				mult = stats.damageMult * ((limb and stats.limbMult) or 1) * keep,
				push = pushMult * keep,
				allowSever = stats.severLimbs == true and limb,
				kind = kind,
			})
			if stats.knockback and keep >= 0.99 then
				-- (sniper) the whole body is thrown back; a killing head shot sends it flying
				local st = DamageService.Get(body)
				if st and st.dead and region == "Head" then
					DamageService.Fling(body, dir * stats.knockback * 1.7 + Vector3.new(0, stats.knockback * 0.5, 0), dir)
				else
					DamageService.Blast(body, dir * stats.knockback + Vector3.new(0, stats.knockback * 0.25, 0), 2.6)
				end
			end
			return
		end
		bodyHits[body] = bodyHits[body] or {}
		local h = bodyHits[body][region]
		if h then
			h.n += 1
		else
			bodyHits[body][region] = { n = 1, point = point, dir = dir }
		end
	end
	for i = 1, count do
		local s = list[i]
		local dir = barrel
		if typeof(s) == "table" and typeof(s.dir) == "Vector3" and finite(s.dir) and s.dir.Magnitude > 0.5 then
			dir = s.dir.Unit
		elseif shotgun then
			local rng = Random.new()
			local spread = math.rad(Config.ShotgunSpread)
			dir = (CFrame.lookAlong(Vector3.zero, barrel) * CFrame.Angles(rng:NextNumber(-spread, spread), rng:NextNumber(-spread, spread), 0)).LookVector
		end
		if flown then
			local from = origin + dir * math.max(0, flown - 1)
			table.insert(results, resolve(player, gun, from, dir, math.max(2, range - flown + 1), nil, shotgun, stats.push, onBody, char, Ballistics.Pen(kind)))
		else
			table.insert(results, resolve(player, gun, origin, dir, range, s, shotgun, stats.push, onBody, nil, Ballistics.Pen(kind)))
		end
	end
	-- (v2.0) the M1 Garand throws its empty clip out with its famous "ping" after the last round
	if stats.enbloc and ammo - 1 <= 0 then
		GoreService.FX({ t = "clip", gun = gun })
		GoreService.Sound("garandPing", origin, 1)
	end
	-- (v2.0) the taser's wires stay on whatever it hit for a moment
	if stats.taser and GunService.OnTaserShot then
		GunService.OnTaserShot(player, gun, origin, results[1])
	end
	if stats.harpoon and GunService.OnHarpoonShot then
		GunService.OnHarpoonShot(player, gun, origin, results[1])
	end
	-- shotgun: one hit per body part with all its pellets; closer = harder, point blank blows it off
	for body, regions in bodyHits do
		for region, h in regions do
			local dist = (h.point - origin).Magnitude
			local close = 1 + 1.2 * math.clamp(1 - dist / Config.ShotgunCloseRange, 0, 1)
			local opts = { mult = stats.damageMult * close, count = h.n, push = pushMult * math.sqrt(h.n) }
			if dist <= Config.ShotgunGibRange then
				opts.severAt = Config.ShotgunSeverDamage
			end
			DamageService.ApplyBullet(body, region, h.point, h.dir, player, true, opts)
		end
	end

	-- crossbow: the bolt stays where it hit (in a body, a prop, a wall)
	if stats.bolt then
		for _, r in results do
			local hp = r.part
			local owner = hp and hp:FindFirstAncestorOfClass("Model")
			if hp and hp:IsA("BasePart") and hp.Parent and not (owner and owner:GetAttribute("Wonder") == true) then
				GunService.StickBolt(hp, r.to, (r.to - origin).Unit) -- (v1.9.1: never into a Wonder player)
			end
		end
	end

	GoreService.FX({
		t = "shot",
		gun = gun,
		from = flown and (origin + barrel * math.max(0, flown - 2)) or origin,
		hits = results,
		by = player.UserId,
		shotgun = shotgun,
		kind = kind,
		slow = flown ~= nil,
	})
	end
	if GunService.OnShotLine then
		pcall(GunService.OnShotLine, player, origin, barrel, range)
	end
	if GunService.IsSlow and GunService.IsSlow() then
		GoreService.FX({ t = "shot", gun = gun, from = origin, hits = {}, by = player.UserId, shotgun = shotgun, kind = kind }) -- (the flash)
		-- (v2.8) a bullet fired in the Sandevistan's slow motion FLIES: at SlowBulletSpeed x the world's time scale. It
		-- crawls while the slow motion runs and is a normal bullet again the moment it ends (the same bullet, at full
		-- speed). It hits whatever is in its way when it gets there - somebody who steps out of the line is missed.
		local params = baseParams(gun, char)
		local flown = 0
		local pos = origin
		local b = Instance.new("Part")
		b.Name = "SlowBullet"
		b.Anchored = true
		b.CanCollide, b.CanQuery, b.CanTouch = false, false, false
		b.CastShadow = false
		b.Material = Enum.Material.Neon
		b.Color = Color3.fromRGB(255, 226, 150)
		b.Size = Vector3.new(0.14, 0.14, 1.4)
		b.CFrame = CFrame.lookAlong(origin, barrel)
		local fx = workspace:FindFirstChild("FX")
		b.Parent = fx or workspace
		local conn: RBXScriptConnection? = nil
		conn = RunService.Heartbeat:Connect(function(dt)
			if not b.Parent then
				if conn then
					conn:Disconnect()
				end
				return
			end
			if workspace:GetAttribute("TimeStop") then
				return
			end
			local step = Config.SlowBulletSpeed * TimeScale.Get() * math.min(dt, 1 / 15)
			local left = range - flown
			step = math.min(step, left)
			local hit = workspace:Raycast(pos, barrel * step, params)
			if hit or step >= left - 0.01 then
				if conn then
					conn:Disconnect()
				end
				b:Destroy()
				flown += hit and (hit.Position - pos).Magnitude or step
				resolveAll(flown)
				return
			end
			flown += step
			pos += barrel * step
			b.CFrame = CFrame.lookAlong(pos, barrel)
		end)
	else
		resolveAll()
	end
end

-- a gun mounted on a vehicle (the helicopter's nose gun): one bullet from origin along dir
function GunService.VehicleShot(player: Player, vehicle: Model, origin: Vector3, dir: Vector3)
	local char = player.Character
	local gunKind = vehicle:GetAttribute("Jet") and "jet" or "heli"
	local mult = gunKind == "jet" and Config.JetGunDamage or Config.HeliGunDamage
	local function onBody(body: Model, region: string, point: Vector3, d: Vector3, keep: number)
		if body == char then
			return
		end
		DamageService.ApplyBullet(body, region, point, d, player, false, { mult = mult * keep, push = keep })
	end
	local r = resolve(player, vehicle, origin, dir, Config.HeliGunRange, nil, false, Config.Guns.rifle.push, onBody, char, Ballistics.Pen(gunKind))
	GoreService.FX({
		t = "shot",
		gun = vehicle,
		from = origin,
		hits = { r },
		by = 0,
		shotgun = false,
		kind = gunKind,
	})
end

function GunService.StickBolt(part: BasePart, point: Vector3, dir: Vector3)
	if part.Transparency >= 0.99 then
		return
	end
	local bolt = Instance.new("Part")
	bolt.Name = "Bolt"
	bolt.Size = Vector3.new(0.06, 0.06, 1.2)
	bolt.Color = Color3.fromRGB(80, 56, 34)
	bolt.Material = Enum.Material.Wood
	bolt.CanCollide = false
	bolt.CanQuery = false
	bolt.CanTouch = false
	bolt.Massless = true
	bolt.CFrame = CFrame.lookAt(point - dir * 0.35, point + dir)
	local fletch = Instance.new("Part")
	fletch.Name = "Fletching"
	fletch.Size = Vector3.new(0.22, 0.02, 0.25)
	fletch.Color = Color3.fromRGB(200, 40, 36)
	fletch.Material = Enum.Material.Fabric
	fletch.CanCollide = false
	fletch.CanQuery = false
	fletch.CanTouch = false
	fletch.Massless = true
	fletch.CFrame = bolt.CFrame * CFrame.new(0, 0, 0.5)
	local fw = Instance.new("WeldConstraint")
	fw.Part0 = bolt
	fw.Part1 = fletch
	fw.Parent = fletch
	fletch.Parent = bolt
	if part:IsGrounded() then
		bolt.Anchored = true -- (pinned in the world on its own, never welded to it)
	else
		local w = Instance.new("WeldConstraint")
		w.Part0 = part
		w.Part1 = bolt
		w.Parent = bolt
	end
	bolt:SetAttribute("Gore", true)
	bolt.Parent = workspace:FindFirstChild("FX") or workspace
	task.delay(Config.CrossbowBoltLife, function()
		bolt:Destroy()
	end)
end

-- a blow dart went into a body: sleep (knocked out) or heal
function GunService.Dart(body: Model, region: string, point: Vector3, dir: Vector3, kind: string, shooter: Player?)
	local partName = RigInfo.RegionPart[region]
	local part = partName and body:FindFirstChild(partName)
	if part and part:IsA("BasePart") then
		-- a little dart sticks out of the body part for a while
		local dart = Instance.new("Part")
		dart.Name = "Dart"
		dart.Size = Vector3.new(0.05, 0.05, 0.45)
		dart.Color = kind == "sleep" and Color3.fromRGB(150, 80, 230) or (kind == "para" and Color3.fromRGB(240, 210, 40) or Color3.fromRGB(80, 230, 110))
		dart.Material = Enum.Material.Neon
		dart.CanCollide = false
		dart.CanQuery = false
		dart.CanTouch = false
		dart.Massless = true
		dart.CFrame = CFrame.lookAt(point - dir * 0.15, point + dir)
		local w = Instance.new("WeldConstraint")
		w.Part0 = part
		w.Part1 = dart
		w.Parent = dart
		dart:SetAttribute("Gore", true)
		dart.Parent = workspace:FindFirstChild("FX") or workspace
		task.delay(18, function()
			dart:Destroy()
		end)
	end
	if kind == "sleep" then
		DamageService.ApplyDamage(body, region, 2, point, { cause = "Darted", allowSever = false, attacker = shooter, quiet = true })
		DamageService.Sleep(body, Config.SleepTimeMin + math.random() * (Config.SleepTimeMax - Config.SleepTimeMin), shooter)
	elseif kind == "para" then
		-- (v2.8) paralysed: down and limp for Config.ParalysisTime s, but awake (no dream, the screen stays on)
		DamageService.ApplyDamage(body, region, 2, point, { cause = "Paralysed", allowSever = false, attacker = shooter, quiet = true })
		DamageService.Paralyze(body, Config.ParalysisTime, shooter)
	else
		DamageService.Heal(body)
	end
end

-- a shot fired by the server itself (hostile NPCs): same hits and effects as a player's shot
function GunService.ServerShot(shooterBody: Model, gun: Model, origin: Vector3, dirs: { Vector3 }, mult: number)
	local kind = Items.Kind(gun) or "pistol"
	local stats = Config.Guns[kind] or Config.Guns.pistol
	local shotgun = kind == "shotgun"
	local range = stats.range or Config.GunRange
	local results = {}
	local bodyHits: { [Model]: { [string]: { n: number, point: Vector3, dir: Vector3 } } } = {}
	local function onBody(body: Model, region: string, point: Vector3, dir: Vector3, keep: number)
		DamageService.MarkBotAttacker(body, shooterBody) -- (v2.0: gun game / zombies count bot kills)
		-- (v2.0) the special guns do for a bot what they do for a player
		if stats.dart then
			GunService.Dart(body, region, point, dir, stats.dart, nil)
			return
		end
		if stats.taser then
			if GunService.OnTase then
				GunService.OnTase(body, region, point, dir, nil, gun)
			end
			return
		end
		if stats.harpoon then
			DamageService.ApplyDamage(body, region, Config.HarpoonDamage * (Config.LimbMultiplier[region] or 1), point, {
				cause = "Harpooned by a bot",
				allowSever = false,
				bleed = Config.BulletBleed.Limb,
				bleedTime = Config.BulletBleedTime,
			})
			DamageService.Blast(body, -dir * 18 + Vector3.new(0, 6, 0), 1.2) -- (and yanked towards the bot)
			return
		end
		if not shotgun then
			local limb = region ~= "Head" and region ~= "Torso"
			DamageService.ApplyBullet(body, region, point, dir, nil, false, {
				mult = stats.damageMult * mult * ((limb and stats.limbMult) or 1) * keep,
				allowSever = stats.severLimbs == true and limb,
			})
			if stats.knockback and keep >= 0.99 then
				local st = DamageService.Get(body)
				if st and st.dead and region == "Head" then
					DamageService.Fling(body, dir * stats.knockback * 1.3 + Vector3.new(0, stats.knockback * 0.4, 0), dir)
				else
					DamageService.Blast(body, dir * stats.knockback * 0.7 + Vector3.new(0, stats.knockback * 0.2, 0), 2.2)
				end
			end
			return
		end
		bodyHits[body] = bodyHits[body] or {}
		local h = bodyHits[body][region]
		if h then
			h.n += 1
		else
			bodyHits[body][region] = { n = 1, point = point, dir = dir }
		end
	end
	for _, dir in dirs do
		table.insert(results, resolve(nil, gun, origin, dir, range, nil, shotgun, stats.push, onBody, shooterBody, Ballistics.Pen(kind)))
	end
	if stats.taser and GunService.OnTaserShot then
		pcall(GunService.OnTaserShot, nil, gun, origin, results[1]) -- (the wires)
	end
	for body, regions in bodyHits do
		for region, h in regions do
			local dist = (h.point - origin).Magnitude
			local close = 1 + 1.2 * math.clamp(1 - dist / Config.ShotgunCloseRange, 0, 1)
			local opts = { mult = stats.damageMult * mult * close, count = h.n, push = math.sqrt(h.n) }
			if dist <= Config.ShotgunGibRange then
				opts.severAt = Config.ShotgunSeverDamage
			end
			DamageService.ApplyBullet(body, region, h.point, h.dir, nil, true, opts)
		end
	end
	GoreService.FX({ t = "shot", gun = gun, from = origin, hits = results, by = 0, shotgun = shotgun, kind = kind })
end

-- (v2.8) a shot from an implant (the SHIFTGUN forearm): one bullet of `kind` from `origin` along `dir`, the player gets the
-- credit. `host` (the arm part) is left out of the ray. The clients draw it (FX "shot" with arm = true).
function GunService.ArmShot(player: Player, host: Instance, origin: Vector3, dir: Vector3, mult: number, kind: string)
	local char = player.Character
	local stats = Config.Guns[kind] or Config.Guns.rifle
	local range = stats.range or Config.GunRange
	local function onBody(body: Model, region: string, point: Vector3, d: Vector3, keep: number)
		if body == char then
			return
		end
		DamageService.ApplyBullet(body, region, point, d, player, false, { mult = stats.damageMult * mult * keep, push = keep, kind = kind })
	end
	local r = resolve(player, host :: any, origin, dir.Unit, range, nil, false, stats.push, onBody, char, Ballistics.Pen(kind))
	GoreService.FX({ t = "shot", from = origin, hits = { r }, by = player.UserId, shotgun = false, kind = kind, arm = true })
	if GunService.OnShotLine then
		GunService.OnShotLine(player, origin, dir.Unit, range)
	end
	return r
end

function GunService.Init()
	GunRemote.OnServerEvent:Connect(function(player, gun, origin, shots)
		if typeof(gun) ~= "Instance" or not gun:IsA("Model") or not Items.IsGun(gun) then
			return
		end
		if not gun:IsDescendantOf(workspace) then
			return
		end
		GunService.Fire(player, gun, origin, shots)
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, d in workspace:GetDescendants() do
			if d:IsA("Model") and d:GetAttribute("HolderId") == player.UserId then
				d:SetAttribute("HolderId", nil)
			end
		end
	end)
end

return GunService
