--!nonstrict
-- GearService (v2.0): the new gear.
--   lockon     : the client locks a vehicle (cars, helicopters, jets) and fires; the server checks the lock and the
--                rocket homes on it (ground targets get a top attack). The driver gets a missile warning.
--   flaregun   : a burning red flare on a high arc. It lights everything around where it lands for 30 s, sets the
--                one it hits on fire; fired into the sky it pops and floats down slowly (a parachute flare).
--   taser      : wires to the one hit; they lie there twitching (Config.TaseTime)
--   harpoon    : the harpoon sticks in what it hit, a line runs from the gun to it; hold F = the winch reels in
--                (pulls the thing / body to you, or you to the wall). Reloading cuts the line.
--   flashlight : F = light on / off
--   glue       : F = a coat on what the crosshair is on; the second coat (on something else) joins them: the lighter
--                one is pulled onto the heavier one, glued sides tight together, and held there for good (a living
--                person comes loose after Config.GlueBodyTime)
--   prosthetic : F = fit it to your own missing arm / leg (or to somebody else's): Config.ProstheticTime seconds,
--                then it is a working limb again (a prosthetic arm is a little weaker, a leg a little slower)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TimeScale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TimeScale")) -- (v2.8) the Sandevistan's slow motion
local Items = require(Shared:WaitForChild("Items"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))

local Modules = script.Parent
local DamageService = require(Modules:WaitForChild("DamageService"))
local GoreService = require(Modules:WaitForChild("GoreService"))
local OwnershipService = require(Modules:WaitForChild("OwnershipService"))
local ItemService = require(Modules:WaitForChild("ItemService"))
local GunService = require(Modules:WaitForChild("GunService"))
local FireService = require(Modules:WaitForChild("FireService"))
local RigBuilder = require(Modules:WaitForChild("RigBuilder"))
local PropBuilders = require(Modules:WaitForChild("PropBuilders"))

local FXRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("FX") :: RemoteEvent

local GearService = {}
-- (v2.1) the fitting bar also fits these (SandevistanService, ArmorService): (surgeon, target body, item)
GearService.OnImplant = nil :: ((Player, Model, Model) -> ())?
-- (v2.8) an implant case / a ripper kit was used on somebody: (surgeon, target body, item, key "Cyber" | "Uncyber:<implant>")
GearService.OnCyber = nil :: ((Player, Model, Model, string) -> ())?
GearService.OnArmor = nil :: ((Player, Model, Model) -> ())?

local rng = Random.new()

local function fxFolder(): Instance
	return workspace:FindFirstChild("FX") or workspace
end

local function torsoOf(player: Player): BasePart?
	local c = player.Character
	local t = c and c:FindFirstChild("Torso")
	return (t and t:IsA("BasePart")) and t or nil
end

local function finite(v: any): boolean
	return typeof(v) == "Vector3" and v == v and v.Magnitude < 1e6
end

local function vehicleOf(inst: Instance): Model?
	local m = inst:FindFirstAncestorOfClass("Model")
	while m do
		if m:GetAttribute("Car") then
			return m
		end
		m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
	end
	return nil
end

------------------------------------------------------------------------
-- lock-on launcher
------------------------------------------------------------------------

local lastShot: { [Model]: number } = {}

local function fireLockon(player: Player, gun: Model, origin: Vector3, dir: Vector3, target: any)
	local stats = Config.Guns.lockon
	local now = os.clock()
	if now - (lastShot[gun] or 0) < stats.interval * 0.8 then
		return
	end
	local torso = torsoOf(player)
	local muzzle = Items.Muzzle(gun)
	if not torso or not muzzle then
		return
	end
	if (origin - torso.Position).Magnitude > Config.GunOriginTolerance then
		origin = muzzle.WorldPosition
	end
	local ammo = gun:GetAttribute("Ammo") or 0
	if ammo <= 0 then
		GoreService.FX({ t = "sfx", n = "dryfire", w = origin, v = 1, by = player.UserId })
		return
	end
	lastShot[gun] = now
	gun:SetAttribute("Ammo", ammo - 1)
	for _, p in gun:GetDescendants() do
		if p:IsA("BasePart") and p:GetAttribute("Warhead") then
			p.Transparency = 1
		end
	end
	-- the lock must be real: a vehicle, a body or a creature, in range, roughly where the tube points
	local homing: BasePart? = nil
	local top = true
	if typeof(target) == "Instance" and target:IsA("BasePart") and target:IsDescendantOf(workspace) then
		local to = target.Position - origin
		if to.Magnitude <= Config.LockonRange + 40 and to.Unit:Dot(dir) > math.cos(math.rad(40)) then
			local car = vehicleOf(target)
			local body = DamageService.BodyOf(target)
			local creature = target:FindFirstAncestorOfClass("Model")
			if car and car.PrimaryPart then
				homing = car.PrimaryPart
			elseif body and body ~= player.Character then
				local t = body:FindFirstChild("Torso")
				homing = (t and t:IsA("BasePart")) and t or target
				top = false
			elseif creature and creature:GetAttribute("Creature") and creature.PrimaryPart then
				homing = creature.PrimaryPart
				top = false
			end
		end
	end
	ItemService.LaunchRocket(origin, dir, player, { gun, (player.Character :: any) :: Instance }, homing, { top = top })
end

------------------------------------------------------------------------
-- flare gun
------------------------------------------------------------------------

local function burningFlare(cf: CFrame, weldTo: BasePart?, floating: boolean)
	local f = Instance.new("Part")
	f.Name = "Flare"
	f.Shape = Enum.PartType.Cylinder
	f.Size = Vector3.new(0.6, 0.22, 0.22)
	f.Color = Color3.fromRGB(255, 60, 40)
	f.Material = Enum.Material.Neon
	f.CanCollide = false
	f.CanQuery = false
	f.CanTouch = false
	f.Massless = true
	f.CFrame = cf
	f:SetAttribute("Gore", true)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 70, 50)
	light.Brightness = 6
	light.Range = 55
	light.Shadows = true
	light.Parent = f
	local fire = Instance.new("Fire")
	fire.Color = Color3.fromRGB(255, 80, 50)
	fire.SecondaryColor = Color3.fromRGB(255, 220, 160)
	fire.Size = 2
	fire.Heat = 4
	fire.Parent = f
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(230, 120, 110)
	smoke.Opacity = 0.18
	smoke.RiseVelocity = 3
	smoke.Size = 3
	smoke.Parent = f
	local sparks = Instance.new("Sparkles")
	sparks.SparkleColor = Color3.fromRGB(255, 120, 90)
	sparks.Parent = f
	if weldTo and not weldTo.Anchored then
		local w = Instance.new("WeldConstraint")
		w.Part0 = weldTo
		w.Part1 = f
		w.Parent = f
	else
		f.Anchored = true
	end
	f.Parent = fxFolder()
	GoreService.FX({ t = "sfx", n = "flareBurn", w = f, v = 1 })
	local t0 = os.clock()
	task.spawn(function()
		while f.Parent and os.clock() - t0 < Config.FlareBurnTime do
			local dt = task.wait(0.05)
			-- a parachute flare sinks slowly and sways
			if floating and f.Anchored then
				local age = os.clock() - t0
				f.CFrame = f.CFrame + Vector3.new(math.sin(age * 0.9) * 0.6 * dt, -5 * dt, math.cos(age * 0.7) * 0.6 * dt)
				local below = workspace:Raycast(f.Position, Vector3.new(0, -0.6, 0))
				if below then
					floating = false
				end
			end
			-- flicker
			light.Brightness = 5 + rng:NextNumber(-1.2, 1.4)
		end
		if f.Parent then
			for i = 1, 10 do
				light.Brightness *= 0.75
				fire.Size = math.max(0.2, fire.Size * 0.8)
				task.wait(0.1)
			end
			f:Destroy()
		end
	end)
end

local function fireFlare(player: Player, gun: Model, origin: Vector3, dir: Vector3)
	local stats = Config.Guns.flaregun
	local now = os.clock()
	if now - (lastShot[gun] or 0) < stats.interval * 0.8 then
		return
	end
	local torso = torsoOf(player)
	local muzzle = Items.Muzzle(gun)
	if not torso or not muzzle then
		return
	end
	if (origin - torso.Position).Magnitude > Config.GunOriginTolerance then
		origin = muzzle.WorldPosition
	end
	local ammo = gun:GetAttribute("Ammo") or 0
	if ammo <= 0 then
		GoreService.FX({ t = "sfx", n = "dryfire", w = origin, v = 1, by = player.UserId })
		return
	end
	lastShot[gun] = now
	gun:SetAttribute("Ammo", ammo - 1)
	for _, p in gun:GetDescendants() do
		if p:IsA("BasePart") and p:GetAttribute("Warhead") then
			p.Transparency = 1
		end
	end
	GoreService.FX({ t = "shot", gun = gun, from = origin, hits = {}, by = 0, shotgun = false, kind = "flaregun" })
	GearService.LaunchFlare(origin, dir, { gun, (player.Character :: any) :: Instance }, player, nil)
end

-- the flying flare: a glowing ball with a smoke trail, server stepped. (v2.0) Bots fire it too (bot = its model)
function GearService.LaunchFlare(origin: Vector3, dir: Vector3, ignore: { Instance }, player: Player?, bot: Model?)
	local ball = Instance.new("Part")
	ball.Name = "FlareShot"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(0.4, 0.4, 0.4)
	ball.Color = Color3.fromRGB(255, 70, 50)
	ball.Material = Enum.Material.Neon
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CFrame = CFrame.new(origin)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.15, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.15, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 1.4
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 120, 100), Color3.fromRGB(200, 190, 190))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.WidthScale = NumberSequence.new(1, 6)
	trail.LightEmission = 0.5
	trail.Parent = ball
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 70, 50)
	light.Brightness = 5
	light.Range = 30
	light.Parent = ball
	ball.Parent = fxFolder()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list: { Instance } = { ball, fxFolder() }
	for _, inst in ignore do
		table.insert(list, inst)
	end
	params.FilterDescendantsInstances = list
	local pos = origin
	local vel = dir * Config.FlareSpeed
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not ball.Parent then
			conn:Disconnect()
			return
		end
		if workspace:GetAttribute("TimeStop") then
			t0 += dt -- (time is stopped)
			return
		end
		local ts = TimeScale.Get() -- (v2.8) slow motion
		t0 += dt * (1 - ts)
		dt *= ts
		vel += Vector3.new(0, -TimeScale.Gravity() * 0.32, 0) * dt
		local step = vel * dt
		local hit = workspace:Raycast(pos, step, params)
		local age = os.clock() - t0
		if hit then
			conn:Disconnect()
			ball:Destroy()
			local part = hit.Instance
			local body, region = DamageService.BodyOf(part)
			if body and region then
				if bot then
					DamageService.MarkBotAttacker(body, bot)
				end
				DamageService.ApplyDamage(body, region, Config.FlareDamage, hit.Position, {
					cause = player and ("Flared by " .. player.DisplayName) or "Flared by a bot",
					allowSever = false,
					attacker = player,
				})
				FireService.SetOnFire(body, 4, player)
			end
			burningFlare(CFrame.lookAt(hit.Position + hit.Normal * 0.12, hit.Position + hit.Normal), part:IsA("BasePart") and part or nil, false)
			return
		end
		-- (straight up into the sky: it pops at the top and floats down on its little parachute)
		if (vel.Y < 0 and age > 1.2 and pos.Y - origin.Y > 40) or age > 7 then
			conn:Disconnect()
			ball:Destroy()
			GoreService.FX({ t = "boomSmall", p = pos, d = Vector3.yAxis })
			burningFlare(CFrame.new(pos), nil, true)
			return
		end
		pos += step
		ball.CFrame = CFrame.new(pos)
	end)
end

------------------------------------------------------------------------
-- taser
------------------------------------------------------------------------

local tased: { [Model]: number } = {}

local function tase(body: Model, region: string, point: Vector3, _dir: Vector3, player: Player?, gun: Model)
	local part = body:FindFirstChild(RigInfo.RegionPart[region] or "Torso")
	DamageService.ApplyDamage(body, region, Config.TaseDamage, point, {
		cause = player and ("Tased by " .. player.DisplayName) or "Tased",
		allowSever = false,
		attacker = player,
		quiet = true,
	})
	DamageService.Knock(body, nil, nil, Config.TaseTime)
	GoreService.FX({ t = "taserwire", gun = gun, part = part, p = point, d = Config.TaseTime })
	local victim = Players:GetPlayerFromCharacter(body)
	if victim then
		FXRemote:FireClient(victim, { t = "tased", d = Config.TaseTime })
		return
	end
	-- a dummy / NPC: the server shakes it
	local untilT = os.clock() + Config.TaseTime
	local fresh = tased[body] == nil
	tased[body] = untilT
	if not fresh then
		return
	end
	task.spawn(function()
		while body.Parent and os.clock() < (tased[body] or 0) do
			for _, p in body:GetChildren() do
				if p:IsA("BasePart") and not p.Anchored and rng:NextNumber() < 0.5 then
					pcall(function()
						p:ApplyImpulse(Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0, 1.2), rng:NextNumber(-1, 1)) * 12 * p:GetMass())
					end)
				end
			end
			task.wait(0.09)
		end
		tased[body] = nil
	end)
end

local function taserShot(_player: Player, gun: Model, _origin: Vector3, result: any)
	if typeof(result) ~= "table" or result.k == "body" then
		return
	end
	if typeof(result.to) == "Vector3" then
		local part = result.part
		GoreService.FX({ t = "taserwire", gun = gun, part = (typeof(part) == "Instance" and part:IsA("BasePart")) and part or nil, p = result.to, d = 0.9 })
	end
	for _, p in gun:GetDescendants() do
		if p:IsA("BasePart") and p:GetAttribute("Warhead") then
			p.Transparency = 1
		end
	end
end

------------------------------------------------------------------------
-- harpoon gun
------------------------------------------------------------------------

type Line = { rope: RopeConstraint, a0: Attachment, a1: Attachment, dart: BasePart, by: Player, t0: number, lastReel: number? }
local lines: { [Model]: Line } = {}

local function cutLine(gun: Model)
	local l = lines[gun]
	if not l then
		return
	end
	lines[gun] = nil
	gun:SetAttribute("LineOut", nil)
	for _, inst in { l.rope, l.a0, l.a1 } do
		if inst.Parent then
			inst:Destroy()
		end
	end
	if l.dart.Parent then
		task.delay(25, function()
			if l.dart.Parent then
				l.dart:Destroy()
			end
		end)
	end
end

local function harpoonShot(player: Player, gun: Model, origin: Vector3, result: any)
	for _, p in gun:GetDescendants() do
		if p:IsA("BasePart") and p:GetAttribute("Warhead") then
			p.Transparency = 1
		end
	end
	cutLine(gun)
	if typeof(result) ~= "table" or typeof(result.to) ~= "Vector3" then
		return
	end
	local part = result.part
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part.Parent then
		return
	end
	local dir = (result.to - origin).Unit
	-- the harpoon stuck in what it hit
	local dart = Instance.new("Part")
	dart.Name = "Harpoon"
	dart.Size = Vector3.new(0.07, 0.07, 2.2)
	dart.Color = Color3.fromRGB(150, 154, 160)
	dart.Material = Enum.Material.Metal
	dart.Reflectance = 0.3
	dart.CanCollide = false
	dart.CanQuery = false
	dart.CanTouch = false
	dart.Massless = true
	dart.CFrame = CFrame.lookAt(result.to - dir * 0.9, result.to + dir)
	dart:SetAttribute("Gore", true)
	if part:IsGrounded() then
		dart.Anchored = true
	else
		local w = Instance.new("WeldConstraint")
		w.Part0 = part
		w.Part1 = dart
		w.Parent = dart
	end
	dart.Parent = fxFolder()
	-- the line: from the gun's muzzle to the harpoon, a winch on the gun
	local barrel = gun:FindFirstChild("Barrel")
	local muzzle = Items.Muzzle(gun)
	if not barrel or not barrel:IsA("BasePart") or not muzzle then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "LineStart"
	a0.Parent = barrel
	a0.WorldPosition = muzzle.WorldPosition
	local a1 = Instance.new("Attachment")
	a1.Name = "LineEnd"
	a1.Parent = part:IsGrounded() and dart or part
	a1.WorldPosition = result.to
	local rope = Instance.new("RopeConstraint")
	rope.Name = "HarpoonLine"
	rope.Attachment0 = a0
	rope.Attachment1 = a1
	rope.Visible = true
	rope.Thickness = 0.05
	rope.Color = BrickColor.new("Bright yellow")
	local len = (muzzle.WorldPosition - result.to).Magnitude + 0.5
	rope.Length = len
	rope.WinchEnabled = true
	rope.WinchTarget = len
	rope.WinchSpeed = Config.HarpoonReelSpeed
	rope.WinchForce = 30000
	rope.WinchResponsiveness = 45
	rope.Parent = barrel
	lines[gun] = { rope = rope, a0 = a0, a1 = a1, dart = dart, by = player, t0 = os.clock() }
	gun:SetAttribute("LineOut", true)
	GoreService.Sound("stick", result.to, 1)
	local my = lines[gun]
	task.delay(Config.HarpoonLineTime, function()
		if lines[gun] == my then
			cutLine(gun)
		end
	end)
end

local function reel(player: Player, gun: Model)
	local l = lines[gun]
	if not l or OwnershipService.ItemHolder(gun) ~= player then
		return
	end
	local now = os.clock()
	if now - (l.lastReel or 0) < 0.06 then
		return
	end
	l.lastReel = now
	l.rope.WinchTarget = math.max(2.5, l.rope.WinchTarget - Config.HarpoonReelSpeed * 0.1)
	if l.rope.WinchTarget <= 2.5 then
		-- reeled all the way in
		task.delay(0.6, function()
			if lines[gun] == l then
				cutLine(gun)
			end
		end)
	end
end

------------------------------------------------------------------------
-- flashlight
------------------------------------------------------------------------

local function toggleFlashlight(item: Model)
	local on = not item:GetAttribute("On")
	item:SetAttribute("On", on)
	for _, d in item:GetDescendants() do
		if d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			d.Enabled = on
		end
	end
	local lens = item:FindFirstChild("Lens")
	if lens and lens:IsA("BasePart") then
		lens.Material = on and Enum.Material.Neon or Enum.Material.Glass
		lens.Color = on and Color3.fromRGB(255, 246, 220) or Color3.fromRGB(200, 205, 210)
	end
	if item.PrimaryPart then
		GoreService.Sound("flashlight", item.PrimaryPart, 1)
	end
end

------------------------------------------------------------------------
-- glue
------------------------------------------------------------------------

type Coat = { part: BasePart, lp: Vector3, ln: Vector3, blob: BasePart }
local coats: { [Player]: Coat } = {}

local function clearCoat(player: Player)
	local c = coats[player]
	coats[player] = nil
	if c and c.blob.Parent then
		c.blob:Destroy()
	end
end

local function weight(part: BasePart): number
	if part:IsGrounded() then
		return math.huge
	end
	return part.AssemblyMass
end

-- a frame at `pos` whose Y axis is `normal`, X as close as possible to `xHint`
local function surfaceFrame(pos: Vector3, normal: Vector3, xHint: Vector3): CFrame
	local x = xHint - normal * xHint:Dot(normal)
	if x.Magnitude < 1e-3 then
		x = (math.abs(normal.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis):Cross(normal)
	end
	x = x.Unit
	return CFrame.fromMatrix(pos, x, normal)
end

local function glueBlob(part: BasePart, pos: Vector3, normal: Vector3): BasePart
	local b = Instance.new("Part")
	b.Name = "Glue"
	b.Shape = Enum.PartType.Cylinder
	b.Size = Vector3.new(0.04, 0.9, 0.9)
	b.Color = Color3.fromRGB(240, 226, 150)
	b.Material = Enum.Material.Glass
	b.Transparency = 0.35
	b.Reflectance = 0.25
	b.CanCollide = false
	b.CanQuery = false
	b.CanTouch = false
	b.Massless = true
	-- (a cylinder's axis is X: point it along the normal)
	b.CFrame = CFrame.lookAt(pos + normal * 0.02, pos + normal * 2) * CFrame.Angles(0, math.rad(90), 0)
	b:SetAttribute("Gore", true)
	if part.Anchored then
		b.Anchored = true
	else
		local w = Instance.new("WeldConstraint")
		w.Part0 = part
		w.Part1 = b
		w.Parent = b
	end
	b.Parent = fxFolder()
	return b
end

local function markHeld(inst: Instance, player: Player)
	inst:SetAttribute("LastHolder", player.UserId)
	inst:SetAttribute("LastHeldT", workspace:GetServerTimeNow())
end

local function join(player: Player, a: Coat, bPart: BasePart, bPos: Vector3, bNormal: Vector3)
	local aPart = a.part
	local aPos = aPart.CFrame:PointToWorldSpace(a.lp)
	local aNormal = aPart.CFrame:VectorToWorldSpace(a.ln)
	local wa, wb = weight(aPart), weight(bPart)
	if wa == math.huge and wb == math.huge then
		GoreService.Sound("dryfire", bPos, 0.6)
		return false -- two walls: nothing can move
	end
	-- the lighter one moves
	local light, lPos, lN, heavy, hPos, hN
	if wa <= wb then
		light, lPos, lN, heavy, hPos, hN = aPart, aPos, aNormal, bPart, bPos, bNormal
	else
		light, lPos, lN, heavy, hPos, hN = bPart, bPos, bNormal, aPart, aPos, aNormal
	end
	local xHint = light.CFrame.RightVector
	local att0 = Instance.new("Attachment")
	att0.Name = "GlueA"
	att0.Parent = light
	att0.WorldCFrame = surfaceFrame(lPos, lN, xHint)
	local att1 = Instance.new("Attachment")
	att1.Name = "GlueB"
	att1.Parent = heavy
	-- the heavy side's frame looks the other way (glued faces against each other) and keeps the current twist
	att1.WorldCFrame = surfaceFrame(hPos, -hN, att0.WorldCFrame.RightVector)
	local mass = math.max(light.AssemblyMass, 0.5)
	local pull = Instance.new("AlignPosition")
	pull.Name = "GluePull"
	pull.Mode = Enum.PositionAlignmentMode.TwoAttachment
	pull.Attachment0 = att0
	pull.Attachment1 = att1
	pull.ReactionForceEnabled = true
	pull.MaxForce = mass * workspace.Gravity * 80
	pull.MaxVelocity = 140
	pull.Responsiveness = 70
	pull.Parent = light
	local turn = Instance.new("AlignOrientation")
	turn.Name = "GlueTurn"
	turn.Mode = Enum.OrientationAlignmentMode.TwoAttachment
	turn.Attachment0 = att0
	turn.Attachment1 = att1
	turn.ReactionTorqueEnabled = true
	turn.MaxTorque = mass * 4000
	turn.Responsiveness = 60
	turn.Parent = light
	GoreService.Sound("glue", lPos, 1)
	local lightBody = DamageService.BodyOf(light)
	local livingPlayer = lightBody and Players:GetPlayerFromCharacter(lightBody) and not lightBody:GetAttribute("Dead")
	task.delay(Config.GluePullTime, function()
		if pull.Parent then
			pull:Destroy()
		end
		if turn.Parent then
			turn:Destroy()
		end
		if not att0.Parent or not att1.Parent then
			return
		end
		-- now it is set: rigid, no gap
		local hold = Instance.new("RigidConstraint")
		hold.Name = "GlueJoint"
		hold.Attachment0 = att0
		hold.Attachment1 = att1
		hold.Parent = light
		light:SetAttribute("Glued", true)
		heavy:SetAttribute("Glued", true)
		if livingPlayer then
			-- skin is not a good surface: it comes loose after a while
			task.delay(Config.GlueBodyTime, function()
				for _, inst in { hold, att0, att1 } do
					if inst.Parent then
						inst:Destroy()
					end
				end
			end)
		end
	end)
	markHeld(light, player)
	return true
end

local function applyGlue(player: Player, item: Model, part: any, pos: any, normal: any)
	if OwnershipService.ItemHolder(item) ~= player or Items.Kind(item) ~= "glue" then
		return
	end
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) or not finite(pos) or not finite(normal) then
		return
	end
	local torso = torsoOf(player)
	if not torso or (torso.Position - pos).Magnitude > Config.GlueRange + 4 then
		return
	end
	-- the point must be on that part
	local lp = part.CFrame:PointToObjectSpace(pos)
	local half = part.Size * 0.5 + Vector3.new(0.6, 0.6, 0.6)
	if math.abs(lp.X) > half.X or math.abs(lp.Y) > half.Y or math.abs(lp.Z) > half.Z then
		return
	end
	if Items.ModelOf(part) == item or part.Name == "Glue" then
		return
	end
	local left = item:GetAttribute("Coats") or 0
	if left <= 0 then
		if item.PrimaryPart then
			GoreService.Sound("dryfire", item.PrimaryPart, 0.6)
		end
		return
	end
	local n = normal.Unit
	local first = coats[player]
	if first and (not first.part.Parent or first.part.AssemblyRootPart == part.AssemblyRootPart) then
		clearCoat(player) -- (the same thing again: the coat moves)
		first = nil
	end
	item:SetAttribute("Coats", left - 1)
	if not first then
		coats[player] = {
			part = part,
			lp = lp,
			ln = part.CFrame:VectorToObjectSpace(n),
			blob = glueBlob(part, pos, n),
		}
		GoreService.Sound("glue", pos, 0.8)
		return
	end
	glueBlob(part, pos, n)
	local ok = join(player, first, part, pos, n)
	if first.blob.Parent and ok then
		-- (the first blob stays visible as the glue line for a moment)
		task.delay(6, function()
			if first.blob.Parent then
				first.blob:Destroy()
			end
		end)
		coats[player] = nil
	elseif not ok then
		clearCoat(player)
	end
end

------------------------------------------------------------------------
-- prosthetics
------------------------------------------------------------------------

type Fitting = { item: Model, target: Model, key: string, t0: number }
local fittings: { [Player]: Fitting } = {}

local KIND_KEYS = { Arm = { "LeftArm", "RightArm" }, Leg = { "LeftLeg", "RightLeg" } }

local function fitStart(player: Player, item: Model, target: any, key: any)
	if OwnershipService.ItemHolder(item) ~= player then
		return
	end
	-- (v2.1) the Sandevistan implant (somebody ELSE's body) and body armor (your own) are fitted the same way as a prosthetic
	local special = Items.Kind(item)
	-- (v2.8) cyberware: an implant case (key "Cyber") or a ripper kit (key "Uncyber:<implant>"), always on somebody else
	local cyberKey = typeof(key) == "string" and ((special == "implantcase" and key == "Cyber") or (special == "ripperkit" and string.sub(key, 1, 8) == "Uncyber:"))
	if cyberKey then
		if typeof(target) ~= "Instance" or not target:IsA("Model") or target:GetAttribute("Dead") or target == player.Character then
			return
		end
		if not Players:GetPlayerFromCharacter(target) then
			return
		end
		local torso0 = torsoOf(player)
		local tt0 = target:FindFirstChild("Torso")
		if not torso0 or not tt0 or not tt0:IsA("BasePart") or (torso0.Position - tt0.Position).Magnitude > Config.ProstheticRange + 4 then
			return
		end
		fittings[player] = { item = item, target = target, key = key, t0 = os.clock() }
		target:SetAttribute("Fitting", "Cyber")
		GoreService.Sound("ratchet", tt0, 0.8)
		return
	end
	if (special == "sandevistan" and key == "Sandevistan") or (special == "armor" and key == "Armor") then
		if typeof(target) ~= "Instance" or not target:IsA("Model") or target:GetAttribute("Dead") then
			return
		end
		if special == "sandevistan" and (target == player.Character or target:GetAttribute("Sandevistan") == true or not Players:GetPlayerFromCharacter(target)) then
			return
		end
		if special == "armor" and target ~= player.Character then
			return
		end
		local torso0 = torsoOf(player)
		local tt0 = target:FindFirstChild("Torso")
		if not torso0 or not tt0 or not tt0:IsA("BasePart") or (torso0.Position - tt0.Position).Magnitude > Config.ProstheticRange + 4 then
			return
		end
		fittings[player] = { item = item, target = target, key = key, t0 = os.clock() }
		target:SetAttribute("Fitting", key)
		GoreService.Sound("ratchet", tt0, 0.8)
		return
	end
	local kinfo = Items.Kinds[Items.Kind(item) or ""]
	local limbKind = kinfo and kinfo.prosthetic
	if not limbKind or typeof(target) ~= "Instance" or not target:IsA("Model") or typeof(key) ~= "string" then
		return
	end
	if not table.find(KIND_KEYS[limbKind], key) or target:GetAttribute("Severed_" .. key) ~= true or target:GetAttribute("Dead") then
		return
	end
	local torso = torsoOf(player)
	local tt = target:FindFirstChild("Torso")
	if not torso or not tt or not tt:IsA("BasePart") or (torso.Position - tt.Position).Magnitude > Config.ProstheticRange + 4 then
		return
	end
	fittings[player] = { item = item, target = target, key = key, t0 = os.clock() }
	target:SetAttribute("Fitting", key)
	GoreService.Sound("ratchet", tt, 0.8)
end

local function dressProsthetic(limbKind: string): (BasePart) -> ()
	return function(limb: BasePart)
		local tmp = Instance.new("Model")
		PropBuilders.ProstheticLook(tmp, limb.CFrame, limbKind)
		local folder = Instance.new("Folder")
		folder.Name = "Prosthetic"
		folder.Parent = limb
		for _, p in tmp:GetChildren() do
			if p:IsA("BasePart") then
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.Massless = true
				p.CastShadow = true
				local w = Instance.new("WeldConstraint")
				w.Part0 = limb
				w.Part1 = p
				w.Parent = p
				p.Parent = folder
			end
		end
		tmp:Destroy()
	end
end

local function fitDone(player: Player, item: Model)
	local f = fittings[player]
	fittings[player] = nil
	if not f or f.item ~= item or OwnershipService.ItemHolder(item) ~= player then
		return
	end
	local target = f.target
	target:SetAttribute("Fitting", nil)
	-- (v2.8) cyberware
	if f.key == "Cyber" or string.sub(f.key, 1, 8) == "Uncyber:" then
		if os.clock() - f.t0 < Config.CyberFitTime * 0.85 or not target.Parent or target:GetAttribute("Dead") then
			return
		end
		local t0 = torsoOf(player)
		local tt0 = target:FindFirstChild("Torso")
		if not t0 or not tt0 or not tt0:IsA("BasePart") or (t0.Position - tt0.Position).Magnitude > Config.ProstheticRange + 6 then
			return
		end
		if GearService.OnCyber then
			GearService.OnCyber(player, target, item, f.key)
		end
		return
	end
	-- (v2.1) the implant / the armor: the same checks, their own time, then the service that owns them takes over
	if f.key == "Sandevistan" or f.key == "Armor" then
		local need = f.key == "Sandevistan" and Config.SandevistanImplantTime or Config.ArmorEquipTime
		if os.clock() - f.t0 < need * 0.85 or not target.Parent or target:GetAttribute("Dead") then
			return
		end
		local t0 = torsoOf(player)
		local tt0 = target:FindFirstChild("Torso")
		if not t0 or not tt0 or not tt0:IsA("BasePart") or (t0.Position - tt0.Position).Magnitude > Config.ProstheticRange + 6 then
			return
		end
		local hook = f.key == "Sandevistan" and GearService.OnImplant or GearService.OnArmor
		if hook then
			hook(player, target, item)
		end
		return
	end
	if os.clock() - f.t0 < Config.ProstheticTime * 0.85 then
		return -- (too fast)
	end
	if not target.Parent or target:GetAttribute("Severed_" .. f.key) ~= true or target:GetAttribute("Dead") then
		return
	end
	local torso = torsoOf(player)
	local tt = target:FindFirstChild("Torso")
	if not torso or not tt or not tt:IsA("BasePart") or (torso.Position - tt.Position).Magnitude > Config.ProstheticRange + 6 then
		return
	end
	local def = RigInfo.ByKey[f.key]
	local limb = RigBuilder.Reattach(target, f.key, dressProsthetic(def.kind))
	if not limb then
		return
	end
	local owner = Players:GetPlayerFromCharacter(target)
	if owner then
		pcall(function()
			limb:SetNetworkOwner(owner)
		end)
		local col = limb:FindFirstChild("Collider")
		if col and col:IsA("BasePart") then
			pcall(function()
				col:SetNetworkOwner(owner)
			end)
		end
		FXRemote:FireClient(owner, { t = "limb", body = target, key = f.key })
	end
	GoreService.Sound("metal", tt, 1)
	GoreService.Sound("ratchet", tt, 1)
	-- the prosthetic is used up
	OwnershipService.DropItem(item)
	item:Destroy()
end

local function fitCancel(player: Player)
	local f = fittings[player]
	fittings[player] = nil
	if f and f.target.Parent then
		f.target:SetAttribute("Fitting", nil)
	end
end

------------------------------------------------------------------------

function GearService.Init()
	GunService.OnTase = tase
	GunService.OnTaserShot = taserShot
	GunService.OnHarpoonShot = harpoonShot
	ItemService.OnProjectile = function(player: Player, gun: Model, origin: Vector3, dir: Vector3, target: any)
		local kind = Items.Kind(gun)
		if kind == "lockon" then
			fireLockon(player, gun, origin, dir, target)
		elseif kind == "flaregun" then
			fireFlare(player, gun, origin, dir)
		end
	end
	ItemService.OnUse = function(_player: Player, item: Model, kind: string)
		if kind == "flashlight" then
			toggleFlashlight(item)
		end
	end
	ItemService.OnReload = function(_player: Player, gun: Model)
		if lines[gun] then
			cutLine(gun)
		end
	end
	ItemService.OnAction = function(player: Player, action: string, item: Model, a: any, b: any, c: any)
		if action == "glue" then
			applyGlue(player, item, a, b, c)
		elseif action == "reel" then
			reel(player, item)
		elseif action == "fitstart" then
			fitStart(player, item, a, b)
		elseif action == "fitdone" then
			fitDone(player, item)
		elseif action == "fitcancel" then
			fitCancel(player)
		elseif action == "syringe" then
			-- (v2.8) a syringe into somebody close: Config.SyringeMult x the sleep of a dart. Used up.
			if OwnershipService.ItemHolder(item) ~= player or Items.Kind(item) ~= "syringe" or typeof(a) ~= "Instance" or not a:IsA("Model") then
				return
			end
			local torso = torsoOf(player)
			local tt = a:FindFirstChild("Torso")
			if not torso or not tt or not tt:IsA("BasePart") or (torso.Position - tt.Position).Magnitude > Config.SyringeRange + 4 or a == player.Character then
				return
			end
			local t = (Config.SleepTimeMin + math.random() * (Config.SleepTimeMax - Config.SleepTimeMin)) * Config.SyringeMult
			DamageService.ApplyDamage(a, "Torso", 1, tt.Position, { cause = "A syringe", allowSever = false, attacker = player, quiet = true })
			DamageService.Sleep(a, t, player)
			GoreService.Sound("click", tt, 1)
			OwnershipService.DropItem(item)
			item:Destroy()
		end
	end
	-- a line whose gun was dropped / is gone
	task.spawn(function()
		while true do
			task.wait(0.5)
			for gun, l in lines do
				if not gun.Parent or OwnershipService.ItemHolder(gun) ~= l.by or not l.a1.Parent then
					cutLine(gun)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		clearCoat(p)
		fitCancel(p)
	end)
end

return GearService
