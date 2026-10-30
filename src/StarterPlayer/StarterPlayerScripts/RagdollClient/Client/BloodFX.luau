--!nonstrict
-- BloodFX: all client-side effects.
--   Blood : droplets simulated with raycasts, rectangular splats where they land, growing blood
--           puddles under bleeding bodies, red mist, arterial spurts from stumps, dripping limbs.
--   Guns  : muzzle flash + light, tracers (one per shotgun pellet), sparks / dust / bullet holes,
--           ejected casings / shells.
--   Boom  : explosions (flash, fireball, smoke, debris, shockwave, scorch mark, camera shake).
--   Sound : plays the server's sound events through the SoundLibrary (with fallbacks).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RigInfo = require(Shared:WaitForChild("RigInfo"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))
local Settings = require(Shared:WaitForChild("Settings"))
local Items = require(Shared:WaitForChild("Items"))
local Ballistics = require(Shared:WaitForChild("Ballistics"))
local Config = require(Shared:WaitForChild("Config"))
local TimeScale = require(Shared:WaitForChild("TimeScale"))
local ExplosionFX = require(script.Parent:WaitForChild("ExplosionFX"))
local FireFX = require(script.Parent:WaitForChild("FireFX"))

local FXRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("FX") :: RemoteEvent

local player = Players.LocalPlayer

local BloodFX = {}

local MAX_DROPS = 280
local MAX_SPLATS = 420
local MAX_PUDDLES = 14
local GRAVITY = Vector3.new(0, -workspace.Gravity * 0.9, 0)
local BLOOD_COLORS = {
	Color3.fromRGB(105, 6, 8),
	Color3.fromRGB(122, 10, 12),
	Color3.fromRGB(90, 4, 6),
	Color3.fromRGB(135, 14, 16),
}
local PUDDLE_COLOR = Color3.fromRGB(86, 4, 7)
-- (v2.1) what runs out of a PROSTHETIC limb is black (oil), never red
local BLACK_BLOOD = {
	Color3.fromRGB(8, 8, 10),
	Color3.fromRGB(14, 13, 16),
	Color3.fromRGB(5, 5, 7),
	Color3.fromRGB(20, 18, 22),
}
local RigInfoShared = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("RigInfo"))
local prostheticQuery = OverlapParams.new()
local function nearProsthetic(pos: Vector3): boolean
	for _, part in workspace:GetPartBoundsInRadius(pos, 1.7, prostheticQuery) do
		if part:FindFirstChild("Prosthetic") then
			return true
		end
		local m = part.Parent
		if m and m:IsA("Model") then
			local def = RigInfoShared.ByPartName[part.Name]
			if def and m:GetAttribute("Prosthetic_" .. def.key) == true then
				return true
			end
			-- (v2.8.1) a TITAN arm bleeds oil too
			if def and ((def.key == "LeftArm" and m:GetAttribute("Titan_L") ~= nil) or (def.key == "RightArm" and m:GetAttribute("Titan_R") ~= nil)) then
				return true
			end
		end
	end
	return false
end

local rng = Random.new()
local folder: Folder
local drops = {}
local dropPool: { BasePart } = {}
local splats: { BasePart } = {}
local splatIndex = 0
local splatLayer = 0
local puddles = {} -- { part, size, max, body, t }
local toolSplats: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
local mistAttachment: Attachment
local mistEmitter: ParticleEmitter
local dustEmitter: ParticleEmitter
local sparkEmitter: ParticleEmitter
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
rayParams.IgnoreWater = true

local hooks = {
	onHurt = nil :: ((number, string) -> ())?,
	onKnock = nil :: ((string?, Vector3?, number?, Vector3?, Vector3?) -> ())?,
	onDrag = nil :: ((any) -> ())?,
	onUndrag = nil :: ((Instance?, any?) -> ())?,
	onDragMove = nil :: ((any) -> ())?,
	onBoom = nil :: ((Vector3, number) -> ())?,
	onNukeWarn = nil :: ((number, Vector3?) -> ())?,
	onSleep = nil :: ((number) -> ())?,
	onWake = nil :: (() -> ())?,
	onFlash = nil :: ((Vector3, number) -> ())?,
	onOther = nil :: ((string, any) -> ())?,
}

local function refreshFilter()
	local ignore: { Instance } = { folder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	for _, name in { "Dummies", "Corpses" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
end

local function fxPart(name: string, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

------------------------------------------------------------------------
-- blood: droplets, splats, puddles
------------------------------------------------------------------------

local function newDropPart(): BasePart
	local p = table.remove(dropPool)
	if p then
		return p
	end
	p = fxPart("Drop", Vector3.new(0.2, 0.2, 0.2), BLOOD_COLORS[1])
	p.Shape = Enum.PartType.Ball
	p.Reflectance = 0.15
	p.Parent = folder
	return p
end

local function recycleDrop(p: BasePart)
	p.CFrame = CFrame.new(0, -5000, 0)
	table.insert(dropPool, p)
end

-- frame on a surface: Y axis = normal. (v2.0) Lined up with the world (on a floor the sides run along X and Z, on a
-- wall level with the ground), no random turn: splats and puddles are clean rectangles that sit square to each
-- other and to the floor tiles instead of a heap of crooked shards
local function surfaceFrame(position: Vector3, normal: Vector3, lift: number): CFrame
	local x: Vector3
	if math.abs(normal.Y) > 0.7 then
		x = Vector3.xAxis - normal * normal.X
	else
		x = Vector3.yAxis:Cross(normal)
	end
	x = x.Magnitude > 0.05 and x.Unit or Vector3.xAxis
	return CFrame.fromMatrix(position + normal * lift, x, normal)
end

local function bodyModelOf(inst: Instance): Model?
	local m = inst:FindFirstAncestorOfClass("Model")
	while m do
		if m:GetAttribute("RagdollRig") then
			return m
		end
		m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function makeSplat(position: Vector3, normal: Vector3, hitPart: BasePart, size: number, color: Color3?)
	splatIndex = splatIndex % MAX_SPLATS + 1
	local s = splats[splatIndex]
	if not s then
		s = fxPart("Splat", Vector3.new(1, 0.03, 1), BLOOD_COLORS[1])
		s.Massless = true
		splats[splatIndex] = s
	end
	for _, c in s:GetChildren() do
		c:Destroy()
	end
	s.Parent = nil
	splatLayer = (splatLayer + 1) % 16
	local lift = 0.02 + splatLayer * 0.003
	s.Color = color or BLOOD_COLORS[rng:NextInteger(1, #BLOOD_COLORS)]
	s.Reflectance = rng:NextNumber(0.1, 0.22)
	s.Transparency = 0
	-- rectangular splats, sometimes stretched streaks
	local aspect = rng:NextNumber() < 0.3 and rng:NextNumber(1.8, 3) or rng:NextNumber(0.75, 1.3)
	local final = Vector3.new(size, 0.03, size * aspect)
	if rng:NextNumber() < 0.5 then
		final = Vector3.new(size * aspect, 0.03, size) -- (a streak along the other side)
	end
	s.Size = Vector3.new(final.X * 0.3, 0.03, final.Z * 0.3)
	s.CFrame = surfaceFrame(position, normal, lift)
	if hitPart.Anchored then
		s.Anchored = true
	else
		s.Anchored = false
		local w = Instance.new("WeldConstraint")
		w.Part0 = hitPart
		w.Part1 = s
		w.Parent = s
	end
	s.Parent = folder
	TweenService:Create(s, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = final }):Play()
	local myIndex, mine = splatIndex, s
	task.delay(55 + rng:NextNumber(0, 20), function()
		if splats[myIndex] == mine and mine.Parent then
			TweenService:Create(mine, TweenInfo.new(4), { Transparency = 1 }):Play()
		end
	end)
end

local function spawnDrop(pos: Vector3, vel: Vector3, size: number?, color: Color3?)
	if #drops >= MAX_DROPS or (color == nil and not Settings.Get("blood")) then
		return -- (blood switched off in the settings; vomit and drool still drip)
	end
	local p = newDropPart()
	local s = size or rng:NextNumber(0.14, 0.3)
	p.Size = Vector3.new(s, s, s)
	if color == nil and nearProsthetic(pos) then
		color = BLACK_BLOOD[rng:NextInteger(1, #BLACK_BLOOD)] -- (the drop keeps this colour when it lands as a splat)
	end
	p.Color = color or BLOOD_COLORS[rng:NextInteger(1, #BLOOD_COLORS)]
	p.CFrame = CFrame.new(pos)
	table.insert(drops, { part = p, pos = pos, vel = vel, life = 3, size = s, color = color })
end

-- a rectangular pool of blood that slowly spreads under a bleeding body
local function growPuddle(body: Model, groundPos: Vector3, normal: Vector3, rate: number)
	if not Settings.Get("blood") then
		return
	end
	local rec = nil
	for _, p in puddles do
		if p.body == body and (p.center - groundPos).Magnitude < 4.5 then
			rec = p
			break
		end
	end
	if not rec then
		if #puddles >= MAX_PUDDLES then
			local old = table.remove(puddles, 1)
			if old and old.part then
				TweenService:Create(old.part, TweenInfo.new(3), { Transparency = 1 }):Play()
				Debris:AddItem(old.part, 3.1)
			end
		end
		local part = fxPart("Puddle", Vector3.new(0.3, 0.02, 0.3), PUDDLE_COLOR)
		part.Reflectance = 0.28
		part.CFrame = surfaceFrame(groundPos, normal, 0.012)
		part.Parent = folder
		rec = { part = part, w = 0.3, l = 0.3, maxW = rng:NextNumber(5, 7), maxL = rng:NextNumber(6, 9), body = body, center = groundPos }
		table.insert(puddles, rec)
	end
	rec.w = math.min(rec.maxW, rec.w + rate * 0.5)
	rec.l = math.min(rec.maxL, rec.l + rate * 0.65)
	TweenService:Create(rec.part, TweenInfo.new(1), { Size = Vector3.new(rec.w, 0.02, rec.l) }):Play()
end

local function emitAt(emitter: ParticleEmitter, pos: Vector3, dir: Vector3, count: number, speed: number?)
	if count <= 0 or (emitter == mistEmitter and not Settings.Get("blood")) then
		return
	end
	local up = dir.Magnitude > 0.01 and dir.Unit or Vector3.yAxis
	local right = up:Cross(Vector3.new(0.21, 0.13, 0.97)).Unit
	mistAttachment.WorldCFrame = CFrame.fromMatrix(pos, right, up)
	if speed then
		emitter.Speed = NumberRange.new(speed * 0.3, speed * 0.8)
	end
	emitter:Emit(math.clamp(math.floor(count), 1, 40))
end

local function randomUnit(): Vector3
	local v = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
	return v.Magnitude > 0.01 and v.Unit or Vector3.yAxis
end

function BloodFX.Burst(pos: Vector3, dir: Vector3, amount: number, speed: number, black: boolean?)
	local d = dir.Magnitude > 0.01 and dir.Unit or Vector3.yAxis
	amount = math.max(1, math.floor(amount * 0.55))
	for _ = 1, amount do
		local v = (d * 0.7 + randomUnit() * 0.75)
		v = v.Magnitude > 0.01 and v.Unit or d
		spawnDrop(pos, v * speed * rng:NextNumber(0.35, 1.15) + Vector3.new(0, rng:NextNumber(2, 9), 0), nil,
			black and BLACK_BLOOD[rng:NextInteger(1, #BLACK_BLOOD)] or nil)
	end
	if not black then
		emitAt(mistEmitter, pos, d, amount * 0.5, speed)
	end
end

local function spurt(part: BasePart, offset: Vector3, localDir: Vector3, duration: number, strength: number)
	task.spawn(function()
		local t0 = os.clock()
		while part.Parent and os.clock() - t0 < duration do
			local age = (os.clock() - t0) / duration
			local k = strength * (1 - age * 0.85)
			local pos = part.CFrame:PointToWorldSpace(offset)
			local dir = part.CFrame:VectorToWorldSpace(localDir)
			dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.yAxis
			for _ = 1, math.max(1, math.floor(5 * k)) do
				local v = (dir + randomUnit() * 0.22).Unit * rng:NextNumber(10, 22) * k
				spawnDrop(pos, v + part.AssemblyLinearVelocity, rng:NextNumber(0.12, 0.24))
			end
			if rng:NextNumber() < 0.6 then
				emitAt(mistEmitter, pos, dir, 3 * k, 12 * k)
			end
			task.wait(rng:NextNumber(0.28, 0.42) + age * 0.4)
		end
	end)
end

local function trail(part: BasePart, duration: number)
	task.spawn(function()
		local t0 = os.clock()
		while part.Parent and os.clock() - t0 < duration do
			spawnDrop(part.Position, part.AssemblyLinearVelocity * 0.3 + randomUnit() * 2, rng:NextNumber(0.1, 0.2))
			task.wait(0.07)
		end
	end)
end

local downParams = RaycastParams.new()
downParams.FilterType = Enum.RaycastFilterType.Exclude
downParams.RespectCanCollide = true

-- broken limbs drip, bodies lying still in their own blood make puddles
local stillSince: { [Model]: number } = {}
local function bleedLoop()
	while true do
		task.wait(0.5)
		for b in stillSince do
			if not b.Parent then
				stillSince[b] = nil
			end
		end
		local bodies = {}
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(bodies, p.Character)
			end
		end
		for _, name in { "Dummies", "Corpses", "NPCs" } do
			local f = workspace:FindFirstChild(name)
			if f then
				for _, m in f:GetChildren() do
					table.insert(bodies, m)
				end
			end
		end
		for _, body in bodies do
			if not (body:GetAttribute("RagdollRig") and body:GetAttribute("Bleeding")) then
				continue
			end
			local wounds = 0
			for region, partName in RigInfo.RegionPart do
				local severed = body:GetAttribute("Severed_" .. region)
				if body:GetAttribute("Broken_" .. region) or severed then
					wounds += severed and 2 or 1
				end
				if body:GetAttribute("Broken_" .. region) and not severed then
					local part = body:FindFirstChild(partName)
					if part and part:IsA("BasePart") and rng:NextNumber() < 0.45 then
						local l = Vector3.new(rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.9, 0.9), rng:NextNumber(-0.4, 0.4))
						spawnDrop(part.CFrame:PointToWorldSpace(l), part.AssemblyLinearVelocity * 0.5 + Vector3.new(0, -1, 0), rng:NextNumber(0.1, 0.18))
					end
				end
			end
			local torso = body:FindFirstChild("Torso")
			if torso and torso:IsA("BasePart") and torso.AssemblyLinearVelocity.Magnitude < 1.5 then
				stillSince[body] = stillSince[body] or os.clock()
				if os.clock() - stillSince[body] > 1.5 then
					downParams.FilterDescendantsInstances = { body, folder }
					local hit = workspace:Raycast(torso.Position, Vector3.new(0, -3.2, 0), downParams)
					-- (pools only form on the ground, never on top of another body)
					if hit and hit.Normal.Y > 0.7 and not bodyModelOf(hit.Instance) and not Items.ModelOf(hit.Instance) then
						growPuddle(body, hit.Position, hit.Normal, 0.3 + 0.18 * math.max(1, wounds))
					end
				end
			else
				stillSince[body] = nil
			end
		end
	end
end

------------------------------------------------------------------------
-- guns
------------------------------------------------------------------------

local function muzzleOf(gun: Instance): Attachment?
	return gun:IsA("Model") and Items.Muzzle(gun) or nil
end

local function ejectCasing(gun: Instance)
	local port = gun:FindFirstChild("Ejection", true)
	if not port or not port:IsA("Attachment") then
		return
	end
	local shell = Items.Kind(gun :: any) == "shotgun"
	local cf = port.WorldCFrame
	local c = Instance.new("Part")
	c.Name = "Casing"
	c.Shape = Enum.PartType.Cylinder
	c.Size = shell and Vector3.new(0.34, 0.15, 0.15) or Vector3.new(0.16, 0.07, 0.07)
	c.Color = shell and Color3.fromRGB(170, 30, 28) or Color3.fromRGB(196, 158, 72)
	c.Material = Enum.Material.Metal
	c.Reflectance = 0.25
	c.CanQuery = false
	c.CanTouch = false
	c.CastShadow = false
	c.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0.4, 1, 1)
	c.CFrame = cf * CFrame.Angles(0, math.rad(90), 0)
	c.Parent = folder
	c.AssemblyLinearVelocity = cf.RightVector * rng:NextNumber(6, 9) + Vector3.new(0, rng:NextNumber(5, 8), 0) - cf.LookVector * 1.5
	c.AssemblyAngularVelocity = randomUnit() * 25
	Debris:AddItem(c, 8)
	task.delay(0.5, function()
		if c.Parent then
			SoundLibrary.Play("casing", c.Position, 0.7)
		end
	end)
end

local function muzzleFlash(gun: Instance, big: boolean?)
	local muzzle = muzzleOf(gun)
	if not muzzle then
		return
	end
	local gk = Items.Kind(gun :: any)
	if gk == "sleepdart" or gk == "healdart" or gk == "paradart" then
		SoundLibrary.Play("blowdart", muzzle.WorldPosition, 1)
		return -- a blowgun has no flash
	end
	if gk == "crossbow" then
		SoundLibrary.Play("crossbow", muzzle.WorldPosition, 1)
		return -- (a bow string, no flash)
	end
	local cf = muzzle.WorldCFrame
	local gs = gk and Config.Guns[gk]
	if gs and gs.suppressed then
		-- (v2.0) the USP's suppressor: a dull thump, a tiny flash
		SoundLibrary.Play("suppressed", cf.Position, 1)
		emitAt(dustEmitter, cf.Position, cf.LookVector, 2, 4)
		ejectCasing(gun)
		return
	end
	if gk == "taser" then
		SoundLibrary.Play("taser", cf.Position, 1)
		return
	end
	if gk == "harpoon" then
		SoundLibrary.Play("harpoon", cf.Position, 1)
		return
	end
	local fs = big and 0.8 or 0.45
	local flash = fxPart("Flash", Vector3.new(fs, fs, fs), Color3.fromRGB(255, 214, 120), Enum.Material.Neon)
	flash.Shape = Enum.PartType.Ball
	flash.CFrame = cf * CFrame.new(0, 0, -0.15)
	flash.Parent = folder
	local star = fxPart("Flash", Vector3.new(0.1, 0.1, 0.7), Color3.fromRGB(255, 236, 170), Enum.Material.Neon)
	star.CFrame = cf * CFrame.new(0, 0, -0.35)
	star.Parent = folder
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Brightness = 7
	light.Range = 14
	light.Shadows = true
	light.Parent = flash
	TweenService:Create(flash, TweenInfo.new(0.06), { Transparency = 1, Size = Vector3.new(0.7, 0.7, 0.7) }):Play()
	TweenService:Create(star, TweenInfo.new(0.05), { Transparency = 1 }):Play()
	TweenService:Create(light, TweenInfo.new(0.07), { Brightness = 0 }):Play()
	Debris:AddItem(flash, 0.12)
	Debris:AddItem(star, 0.12)
	emitAt(dustEmitter, cf.Position, cf.LookVector, big and 10 or 4, 6)
	local kind = Items.Kind(gun :: any)
	local snd = (kind == "shotgun" and "shotgun") or (kind == "sniper" and "sniper") or (kind == "garand" and "garandShot")
		or (kind == "mp5" and "mp5Shot") or (kind == "flaregun" and "flareShot") or "gunshot"
	SoundLibrary.Play(snd, cf.Position, (kind == "smg" or kind == "minigun") and 0.7 or 1)
	if big then
		task.delay(0.4, function()
			if gun.Parent then
				ejectCasing(gun)
			end
		end)
	else
		ejectCasing(gun)
	end
end

local tracer, bulletImpact

-- (v2.0) blood sprays forward out of an exit wound, along the bullet's path (it lands on what is behind)
function BloodFX.Spray(pos: Vector3, dir: Vector3, power: number)
	if not Settings.Get("blood") then
		return
	end
	local d = dir.Magnitude > 0.01 and dir.Unit or Vector3.yAxis
	local n = math.clamp(math.floor(10 + power * 16), 6, 30)
	for _ = 1, n do
		local v = d + randomUnit() * rng:NextNumber(0.08, 0.32)
		v = v.Magnitude > 0.01 and v.Unit or d
		spawnDrop(pos, v * rng:NextNumber(26, 62) * (0.6 + 0.4 * power) + Vector3.new(0, rng:NextNumber(0, 4), 0), rng:NextNumber(0.1, 0.24))
	end
	emitAt(mistEmitter, pos, d, 6 + power * 8, 34)
end

-- the shooter's own shot: flash, tracers from the real muzzle and the impacts, all at once
-- (the server's echo of this shot is skipped, see "shot" below)
--   hits = { { to = Vector3, n = Vector3?, mat = string? (world material, nil = body / nothing) } }
function BloodFX.LocalShot(gun: Instance, from: Vector3?, hits: { any }?, shotgun: boolean?)
	muzzleFlash(gun, shotgun)
	local kind = gun:IsA("Model") and Items.Kind(gun :: any) or nil
	if from and hits then
		for _, h in hits do
			tracer(from, h.to, kind, h.mat and function()
				bulletImpact(h.to, h.n or Vector3.yAxis, h.mat)
			end or nil, true)
		end
	end
end

------------------------------------------------------------------------
-- (v2.0) tracers: a short hot streak that flies at the bullet's real speed (not a line that blinks from the
-- muzzle to the target), a faint smoke line behind the heavy rounds, the impact when the bullet arrives, and the
-- crack of a bullet that passes close by your head
------------------------------------------------------------------------

type Tracer = { part: BasePart, from: Vector3, dir: Vector3, dist: number, speed: number, len: number, t: number, arrive: (() -> ())?, heavy: boolean }
local liveTracers: { Tracer } = {}
local tracerPool: { BasePart } = {}
local HEAVY = { sniper = true, garand = true, jet = true, heli = true, minigun = true, revolver = true }

local function tracerPart(): BasePart
	local p = table.remove(tracerPool)
	if p then
		return p
	end
	p = fxPart("Tracer", Vector3.new(0.06, 0.06, 1), Color3.fromRGB(255, 214, 140), Enum.Material.Neon)
	p.Parent = folder
	return p
end

local function smokeLine(from: Vector3, to: Vector3)
	local len = (to - from).Magnitude
	if len < 1 then
		return
	end
	local l = fxPart("BulletSmoke", Vector3.new(0.05, 0.05, len), Color3.fromRGB(205, 205, 200))
	l.Transparency = 0.82
	l.CFrame = CFrame.lookAt((from + to) * 0.5, to)
	l.Parent = folder
	TweenService:Create(l, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1, Size = Vector3.new(0.18, 0.18, len) }):Play()
	Debris:AddItem(l, 1)
end

-- from -> to at the gun's bullet speed; `arrive` runs when it gets there; `mine` = my own shot (no crack)
function tracer(from: Vector3, to: Vector3, kind: string?, arrive: (() -> ())?, mine: boolean?)
	local dist = (to - from).Magnitude
	local speed = Ballistics.TracerSpeed(kind)
	if dist < 0.5 or not Settings.Get("tracers") then
		if arrive then
			task.delay(math.min(dist / speed, 0.5), arrive)
		end
		return
	end
	local dir = (to - from) / dist
	local heavy = kind ~= nil and HEAVY[kind] == true
	local w = heavy and 0.075 or 0.05
	local p = tracerPart()
	p.Size = Vector3.new(w, w, 0.1)
	p.Transparency = 0.05
	p.CFrame = CFrame.lookAt(from, to)
	table.insert(liveTracers, {
		part = p,
		from = from,
		dir = dir,
		dist = dist,
		speed = speed,
		len = math.min(Config.TracerLength * (heavy and 1.3 or 1), math.max(dist * 0.6, 1)),
		t = 0,
		arrive = arrive,
		heavy = heavy,
	})
	-- a bullet passing close by: the crack (somebody else's shot)
	if not mine then
		local cam = workspace.CurrentCamera
		if cam then
			local c = cam.CFrame.Position
			local along = math.clamp((c - from):Dot(dir), 0, dist)
			local closest = from + dir * along
			local miss = (c - closest).Magnitude
			if miss < 7 and along > 6 and along < dist - 1 then
				task.delay(along / speed, function()
					SoundLibrary.Play("bulletWhiz", closest, math.clamp(1.2 - miss / 7, 0.3, 1))
				end)
			end
		end
	end
end

local function stepTracers(dt: number)
	if #liveTracers == 0 then
		return
	end
	dt *= TimeScale.Get() -- (v2.8) the Sandevistan: a bullet already flying crawls too
	local parts, cfs = {}, {}
	for i = #liveTracers, 1, -1 do
		local tr = liveTracers[i]
		tr.t += dt
		local head = math.min(tr.dist, tr.t * tr.speed)
		local tail = math.max(0, tr.t * tr.speed - tr.len)
		if head >= tr.dist and tr.arrive then
			local f = tr.arrive
			tr.arrive = nil
			task.spawn(f)
			if tr.heavy then
				smokeLine(tr.from, tr.from + tr.dir * tr.dist)
			end
		end
		if tail >= tr.dist then
			tr.part.CFrame = CFrame.new(0, -5000, 0)
			table.insert(tracerPool, tr.part)
			table.remove(liveTracers, i)
		else
			local mid = tr.from + tr.dir * ((head + tail) * 0.5)
			local w = tr.part.Size.X
			tr.part.Size = Vector3.new(w, w, math.max(0.1, head - tail))
			table.insert(parts, tr.part)
			table.insert(cfs, CFrame.lookAt(mid, mid + tr.dir))
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function bulletImpact(pos: Vector3, normal: Vector3, material: string)
	emitAt(sparkEmitter, pos, normal, 8, 30)
	emitAt(dustEmitter, pos, normal, 6, 8)
	local hole = fxPart("BulletHole", Vector3.new(0.16, 0.025, 0.16), Color3.fromRGB(25, 25, 27))
	hole.CFrame = surfaceFrame(pos, normal, 0.013)
	hole.Parent = folder
	Debris:AddItem(hole, 40)
	local metal = string.find(material, "Metal") or string.find(material, "Plate") or material == "Foil"
	SoundLibrary.Play(metal and "ricochet" or "bulletWorld", pos, 0.9)
end

-- (v2.0) the M1 Garand's empty en-bloc clip flies out of the top
local function ejectClip(gun: Instance)
	local port = gun:FindFirstChild("Ejection", true)
	if not port or not port:IsA("Attachment") then
		return
	end
	local cf = port.WorldCFrame
	local c = Instance.new("Part")
	c.Name = "Clip"
	c.Size = Vector3.new(0.12, 0.22, 0.36)
	c.Color = Color3.fromRGB(150, 150, 140)
	c.Material = Enum.Material.Metal
	c.Reflectance = 0.2
	c.CanQuery = false
	c.CanTouch = false
	c.CastShadow = false
	c.CFrame = cf
	c.Parent = folder
	c.AssemblyLinearVelocity = cf.UpVector * rng:NextNumber(16, 22) + cf.RightVector * rng:NextNumber(1, 3)
	c.AssemblyAngularVelocity = randomUnit() * 18
	Debris:AddItem(c, 10)
end

------------------------------------------------------------------------
-- frame update
------------------------------------------------------------------------

local filterTimer = 0
local function step(dt: number)
	filterTimer -= dt
	if filterTimer <= 0 then
		filterTimer = 1
		refreshFilter()
	end
	if #drops == 0 then
		return
	end
	local parts, cfs = {}, {}
	for i = #drops, 1, -1 do
		local d = drops[i]
		d.life -= dt
		local vel = d.vel + GRAVITY * dt
		vel *= (1 - math.min(0.9, 0.35 * dt))
		local delta = vel * dt
		local hit = workspace:Raycast(d.pos, delta, rayParams)
		if hit and hit.Instance:IsA("BasePart") then
			local item = Items.ModelOf(hit.Instance)
			local hitBody = not item and bodyModelOf(hit.Instance)
			if item then
				-- weapons / tools only get a few small specks, never big stains
				local n = toolSplats[item] or 0
				if n < 5 then
					toolSplats[item] = n + 1
					makeSplat(hit.Position, hit.Normal, hit.Instance, rng:NextNumber(0.1, 0.2))
				end
			elseif hitBody then
				-- bodies (NPCs, people lying around) only get small spatters, never big stains
				local n = toolSplats[hitBody] or 0
				if n < 14 then
					toolSplats[hitBody] = n + 1
					makeSplat(hit.Position, hit.Normal, hit.Instance, rng:NextNumber(0.12, 0.3), d.color)
				end
			else
				makeSplat(hit.Position, hit.Normal, hit.Instance, math.clamp(d.size * rng:NextNumber(3.4, 6), 0.45, 1.8), d.color)
			end
			recycleDrop(d.part)
			table.remove(drops, i)
		elseif d.life <= 0 or (d.pos.Y < -200 and not Config.InPit(d.pos)) then
			recycleDrop(d.part)
			table.remove(drops, i)
		else
			d.pos += delta
			d.vel = vel
			table.insert(parts, d.part)
			table.insert(cfs, CFrame.new(d.pos))
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function BloodFX.SetHooks(h)
	hooks.onHurt = h.onHurt
	hooks.onKnock = h.onKnock
	hooks.onDrag = h.onDrag
	hooks.onUndrag = h.onUndrag
	hooks.onDragMove = h.onDragMove
	hooks.onBoom = h.onBoom
	hooks.onNukeWarn = h.onNukeWarn
	hooks.onSleep = h.onSleep
	hooks.onWake = h.onWake
	hooks.onFlash = h.onFlash
	hooks.onOther = h.onOther
end

------------------------------------------------------------------------
-- explosions
------------------------------------------------------------------------

function BloodFX.Bubbles(pos: Vector3)
	ExplosionFX.Bubbles(pos)
end

function BloodFX.Boom(pos: Vector3, radius: number, kind: string?)
	ExplosionFX.Boom(pos, radius, kind)
end

function BloodFX.Nuke(pos: Vector3, R: number, S: number, speed: number)
	ExplosionFX.Nuke(pos, R, S, speed)
end

-- items clink / thud when they land, the boombox glows with the music
local itemSpeed: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
local METAL = { pistol = true, revolver = true, rifle = true, smg = true, shotgun = true, sniper = true, grenade = true, c4 = true, detonator = true, katana = true, blade = true, axe = true, sledge = true, physgun = true, nuke = true }
local function itemLoop()
	while true do
		task.wait(0.05)
		for _, folderName in { "SpawnedProps", "Map" } do
			local f = workspace:FindFirstChild(folderName)
			if not f then
				continue
			end
			for _, m in f:GetChildren() do
				local kind = m:IsA("Model") and m:GetAttribute("Item")
				local root = kind and m.PrimaryPart
				if not root then
					continue
				end
				local v = root.AssemblyLinearVelocity.Magnitude
				local last = itemSpeed[m] or 0
				itemSpeed[m] = v
				if last - v > 14 and not m:GetAttribute("HolderId") then
					SoundLibrary.Play(METAL[kind] and "clink" or "itemDrop", root.Position, math.clamp((last - v) / 40, 0.3, 1))
				end
				if kind == "boombox" then
					local glow = m:FindFirstChild("Glow")
					local music = root:FindFirstChild("Music")
					if music and music:IsA("Sound") and music.SoundGroup == nil then
						music.SoundGroup = SoundLibrary.Master()
					end
					if glow and glow:IsA("BasePart") then
						local loud = (music and music:IsA("Sound") and music.IsPlaying) and math.clamp(music.PlaybackLoudness / 400, 0, 1) or 0
						glow.Color = Color3.fromRGB(40, 40, 60):Lerp(Color3.fromRGB(80, 220, 255), loud)
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- heal dart, virus, lasers
------------------------------------------------------------------------

function BloodFX.HealSparkle(pos: Vector3)
	for i = 1, 10 do
		local s = fxPart("Heal", Vector3.new(0.25, 0.25, 0.25), Color3.fromRGB(110, 255, 140), Enum.Material.Neon)
		s.Shape = Enum.PartType.Ball
		s.CFrame = CFrame.new(pos + randomUnit() * 1.2)
		s.Parent = folder
		TweenService:Create(s, TweenInfo.new(0.8 + i * 0.04, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = s.CFrame + Vector3.new(0, rng:NextNumber(2, 4), 0),
			Transparency = 1,
			Size = Vector3.new(0.05, 0.05, 0.05),
		}):Play()
		Debris:AddItem(s, 1.4)
	end
	SoundLibrary.Play("teleport", pos, 0.8, 1.3)
end

local VIRUS_GREEN = Color3.fromRGB(110, 230, 70)
local VOMIT = { Color3.fromRGB(150, 160, 60), Color3.fromRGB(120, 130, 40), Color3.fromRGB(170, 150, 70) }

function BloodFX.VirusCloud(pos: Vector3, r: number, duration: number)
	-- glass shards
	for _ = 1, 10 do
		local g = fxPart("Shard", Vector3.new(0.15, 0.05, 0.25), Color3.fromRGB(200, 230, 210), Enum.Material.Glass)
		g.Transparency = 0.4
		g.Anchored = false
		g.CanCollide = true
		g.CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
		g.Parent = folder
		g.AssemblyLinearVelocity = randomUnit() * rng:NextNumber(8, 20) + Vector3.new(0, 8, 0)
		Debris:AddItem(g, 8)
	end
	-- the cloud: slow green puffs
	for i = 1, 14 do
		local s0 = rng:NextNumber(0.3, 0.55) * r
		local puff = fxPart("VirusCloud", Vector3.one * 2, VIRUS_GREEN, Enum.Material.SmoothPlastic)
		puff.Shape = Enum.PartType.Ball
		puff.Transparency = 1
		puff.CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-r, r) * 0.45, rng:NextNumber(0, r * 0.3), rng:NextNumber(-r, r) * 0.45))
		puff.Parent = folder
		local inT = 0.6 + i * 0.05
		TweenService:Create(puff, TweenInfo.new(inT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * s0, Transparency = 0.72 }):Play()
		task.delay(inT, function()
			if puff.Parent then
				TweenService:Create(puff, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
					Size = Vector3.one * s0 * 1.5,
					Transparency = 1,
					CFrame = puff.CFrame + Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(1, 4), rng:NextNumber(-3, 3)),
				}):Play()
			end
		end)
		Debris:AddItem(puff, duration + inT + 0.2)
	end
	-- a green splash where it broke
	local hit = workspace:Raycast(pos + Vector3.new(0, 1, 0), Vector3.new(0, -6, 0), rayParams)
	if hit then
		makeSplat(hit.Position, hit.Normal, hit.Instance, bodyModelOf(hit.Instance) and 0.3 or 2.4, Color3.fromRGB(90, 200, 60))
	end
end

-- a sick body sneezes / vomits (the tumbling is a real knock-over from the server)
function BloodFX.Symptom(body: Instance, kind: string?)
	local head = body:FindFirstChild("Head")
	local torso = body:FindFirstChild("Torso")
	if not head or not head:IsA("BasePart") or not torso or not torso:IsA("BasePart") then
		return
	end
	local look = torso.CFrame.LookVector
	if kind == "sneeze" then
		SoundLibrary.Play("sneeze", head, 1)
		local mouth = head.CFrame:PointToWorldSpace(Vector3.new(0, -0.2, -0.6))
		for _ = 1, 10 do
			spawnDrop(mouth, (look + randomUnit() * 0.35).Unit * rng:NextNumber(12, 22), rng:NextNumber(0.06, 0.1), Color3.fromRGB(200, 230, 190))
		end
		emitAt(dustEmitter, mouth, look, 8, 18)
		if body == player.Character and hooks.onBoom then
			hooks.onBoom(head.Position, 0.5)
		end
	elseif kind == "barf" then
		SoundLibrary.Play("retch", head, 1)
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 2.4 and head.Parent do
				local cf = head.CFrame
				local mouth = cf:PointToWorldSpace(Vector3.new(0, -0.3, -0.6))
				local dir = (cf.LookVector * 0.8 + Vector3.new(0, -0.6, 0)).Unit
				for _ = 1, 4 do
					spawnDrop(mouth, (dir + randomUnit() * 0.18).Unit * rng:NextNumber(6, 13), rng:NextNumber(0.12, 0.24), VOMIT[rng:NextInteger(1, #VOMIT)])
				end
				task.wait(0.06)
			end
		end)
		if body == player.Character and hooks.onBoom then
			hooks.onBoom(head.Position, 0.7)
		end
	end
end

-- laser pointers: every client draws every laser that is on (its own one exactly)
local laserBeams: { [Instance]: { beam: BasePart, dot: BasePart } } = {}
local laserParams = RaycastParams.new()
laserParams.FilterType = Enum.RaycastFilterType.Exclude
local function updateLasers()
	local seen = {}
	local f = workspace:FindFirstChild("SpawnedProps")
	if f then
		for _, m in f:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Item") == "laser" and m:GetAttribute("On") then
				local muzzle = m:FindFirstChild("Muzzle", true)
				if not muzzle or not muzzle:IsA("Attachment") then
					continue
				end
				seen[m] = true
				local rec = laserBeams[m]
				if not rec then
					local beam = fxPart("LaserBeam", Vector3.new(0.04, 0.04, 1), Color3.fromRGB(255, 30, 30), Enum.Material.Neon)
					beam.Transparency = 0.25
					beam.Parent = folder
					local dot = fxPart("LaserDot", Vector3.new(0.28, 0.28, 0.28), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
					dot.Shape = Enum.PartType.Ball
					dot.Parent = folder
					local l = Instance.new("PointLight")
					l.Color = Color3.fromRGB(255, 40, 40)
					l.Range = 5
					l.Brightness = 2
					l.Parent = dot
					rec = { beam = beam, dot = dot }
					laserBeams[m] = rec
				end
				local from = muzzle.WorldPosition
				local dir = muzzle.WorldCFrame.LookVector
				local ignore: { Instance } = { m, folder }
				if player.Character then
					local holder = m:GetAttribute("HolderId")
					if holder == player.UserId then
						table.insert(ignore, player.Character)
					end
				end
				laserParams.FilterDescendantsInstances = ignore
				local hit = workspace:Raycast(from, dir * 900, laserParams)
				local to = hit and hit.Position or (from + dir * 900)
				local len = (to - from).Magnitude
				rec.beam.Size = Vector3.new(0.04, 0.04, len)
				rec.beam.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -len / 2)
				rec.dot.CFrame = CFrame.new(to)
				rec.dot.Transparency = hit and 0 or 1
			end
		end
	end
	for m, rec in laserBeams do
		if not seen[m] then
			rec.beam:Destroy()
			rec.dot:Destroy()
			laserBeams[m] = nil
		end
	end
end

local function makeEmitter(texture: string, color: ColorSequence, size: NumberSequence, life: NumberRange, accel: Vector3, light: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = color
	e.Size = size
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = life
	e.Rate = 0
	e.SpreadAngle = Vector2.new(35, 35)
	e.Acceleration = accel
	e.Drag = 4
	e.LightEmission = light
	e.LightInfluence = 1 - light
	e.RotSpeed = NumberRange.new(-90, 90)
	e.Rotation = NumberRange.new(0, 360)
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = mistAttachment
	return e
end

function BloodFX.Init()
	SoundLibrary.Preload()
	local shared = workspace:WaitForChild("FX", 30)
	if not shared then
		local f = Instance.new("Folder")
		f.Name = "FX"
		f.Parent = workspace
		shared = f
	end
	local localFolder = Instance.new("Folder")
	localFolder.Name = "LocalBlood"
	localFolder.Parent = shared
	folder = localFolder

	local holder = fxPart("EmitterHolder", Vector3.new(0.2, 0.2, 0.2), Color3.new())
	holder.Transparency = 1
	holder.CFrame = CFrame.new(0, -1000, 0)
	holder.Parent = folder
	mistAttachment = Instance.new("Attachment")
	mistAttachment.Parent = holder
	local smoke = "rbxasset://textures/particles/smoke_main.dds"
	mistEmitter = makeEmitter(smoke, ColorSequence.new(Color3.fromRGB(140, 10, 12), Color3.fromRGB(70, 4, 6)),
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.9) }),
		NumberRange.new(0.35, 0.8), Vector3.new(0, -40, 0), 0)
	dustEmitter = makeEmitter(smoke, ColorSequence.new(Color3.fromRGB(190, 186, 176)),
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1.4) }),
		NumberRange.new(0.5, 1.1), Vector3.new(0, 2, 0), 0)
	sparkEmitter = makeEmitter("rbxasset://textures/particles/sparkles_main.dds", ColorSequence.new(Color3.fromRGB(255, 210, 120)),
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0) }),
		NumberRange.new(0.12, 0.3), Vector3.new(0, -60, 0), 1)

	refreshFilter()
	FireFX.Init(folder)
	ExplosionFX.Setup(folder, rayParams, function(amount: number)
		if hooks.onBoom and amount > 0.02 then
			hooks.onBoom(Vector3.zero, amount)
		end
	end)
	RunService.Heartbeat:Connect(step)
	task.spawn(bleedLoop)
	task.spawn(itemLoop)
	RunService.RenderStepped:Connect(updateLasers)
	RunService.RenderStepped:Connect(stepTracers)

	FXRemote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		local t = payload.t
		local mine = payload.by == player.UserId
		if t == "burst" and typeof(payload.p) == "Vector3" then
			BloodFX.Burst(payload.p, payload.d or Vector3.yAxis, payload.n or 10, payload.s or 16, payload.black == true)
		elseif t == "spurt" and typeof(payload.part) == "Instance" and payload.part:IsA("BasePart") then
			spurt(payload.part, payload.o or Vector3.zero, payload.d or Vector3.yAxis, payload.dur or 5, payload.k or 1)
		elseif t == "trail" and typeof(payload.part) == "Instance" and payload.part:IsA("BasePart") then
			trail(payload.part, payload.dur or 1)
		elseif t == "sfx" then
			if mine and payload.n == "dryfire" then
				return
			end
			local w = payload.w
			if typeof(w) == "Instance" and not w.Parent then
				return
			end
			SoundLibrary.Play(payload.n, w :: any, payload.v)
		elseif t == "shot" then
			local kind = typeof(payload.kind) == "string" and payload.kind or nil
			local from = payload.from
			if typeof(from) ~= "Vector3" or typeof(payload.hits) ~= "table" then
				return
			end
			local speed = Ballistics.TracerSpeed(kind)
			-- (v2.0) blood sprays out of the exit wounds when the bullet gets there (my own shots too: only the
			-- server knows where a bullet came out)
			for _, h in payload.hits do
				if typeof(h) == "table" and typeof(h.ex) == "table" and typeof(h.to) == "Vector3" then
					local dir = (h.to - from).Magnitude > 0.01 and (h.to - from).Unit or Vector3.yAxis
					for _, e in h.ex do
						if typeof(e) == "table" and typeof(e.p) == "Vector3" then
							local delay = mine and 0 or math.min((e.p - from).Magnitude / speed, 0.5)
							task.delay(delay, BloodFX.Spray, e.p, dir, typeof(e.k) == "number" and e.k or 1)
						end
					end
				end
			end
			if mine and not payload.slow and not payload.arm then
				return -- (flash, tracer and impacts were already drawn by LocalShot)
			end
			-- (v2.8) a slow bullet (Sandevistan) arrived: the server flew it, here are only its impacts
			if not payload.slow and typeof(payload.gun) == "Instance" and payload.gun.Parent then
				muzzleFlash(payload.gun, payload.shotgun == true)
			end
			for _, h in payload.hits do
				if typeof(h) == "table" and typeof(h.to) == "Vector3" then
					tracer(from, h.to, kind, h.k == "world" and function()
						bulletImpact(h.to, h.n or Vector3.yAxis, h.mat or "")
					end or nil, false)
				end
			end
		elseif t == "clip" and typeof(payload.gun) == "Instance" then
			ejectClip(payload.gun)
		elseif t == "push" and typeof(payload.part) == "Instance" and payload.part:IsA("BasePart") then
			pcall(function()
				payload.part:ApplyImpulseAtPosition(payload.i, payload.p)
			end)
		elseif t == "hurt" then
			if hooks.onHurt then
				hooks.onHurt(payload.a or 10, payload.r or "Torso")
			end
		elseif t == "knock" then
			if hooks.onKnock then
				hooks.onKnock(payload.r, payload.i, payload.rt, payload.p, payload.all)
			end
		elseif t == "drag" then
			if hooks.onDrag then
				hooks.onDrag(payload)
			end
		elseif t == "undrag" then
			if hooks.onUndrag then
				hooks.onUndrag(payload.body, payload.snap)
			end
		elseif t == "dragpos" then
			if hooks.onDragMove then
				hooks.onDragMove(payload)
			end
		elseif t == "boom" and typeof(payload.p) == "Vector3" then
			BloodFX.Boom(payload.p, payload.r or 15, typeof(payload.k) == "string" and payload.k or nil)
		elseif t == "fire" and typeof(payload.p) == "Vector3" then
			FireFX.Patch(payload.p, typeof(payload.r) == "number" and payload.r or 4, typeof(payload.l) == "number" and payload.l or 6, typeof(payload.n) == "Vector3" and payload.n or nil)
		elseif t == "glass" and typeof(payload.cf) == "CFrame" and typeof(payload.s) == "Vector3" and typeof(payload.p) == "Vector3" then
			ExplosionFX.Glass(payload.cf, payload.s, payload.p, typeof(payload.d) == "Vector3" and payload.d or Vector3.zero, typeof(payload.c) == "Color3" and payload.c or nil)
		elseif t == "flash" and typeof(payload.p) == "Vector3" then
			ExplosionFX.Flash(payload.p)
			if hooks.onFlash then
				hooks.onFlash(payload.p, payload.r or 40)
			end
		elseif t == "nuke" and typeof(payload.p) == "Vector3" then
			BloodFX.Nuke(payload.p, payload.r or 300, payload.s or 1500, payload.v or 320)
		elseif t == "sleep" then
			if hooks.onSleep then
				hooks.onSleep(payload.d or 15)
			end
		elseif t == "wake" then
			if hooks.onWake then
				hooks.onWake()
			end
		elseif t == "heal" and typeof(payload.p) == "Vector3" then
			BloodFX.HealSparkle(payload.p)
		elseif t == "virusCloud" and typeof(payload.p) == "Vector3" then
			BloodFX.VirusCloud(payload.p, payload.r or 12, payload.d or 8)
		elseif t == "symptom" and typeof(payload.body) == "Instance" then
			BloodFX.Symptom(payload.body, payload.k)
		elseif t == "splash" and typeof(payload.p) == "Vector3" then
			ExplosionFX.Splash(payload.p, typeof(payload.s) == "number" and payload.s or 1)
		elseif t == "boomSmall" and typeof(payload.p) == "Vector3" then
			ExplosionFX.Small(payload.p, typeof(payload.d) == "Vector3" and payload.d or Vector3.yAxis)
		elseif t == "nukewarn" then
			if hooks.onNukeWarn then
				hooks.onNukeWarn(payload.n or 0, payload.p)
			end
		elseif t == "taserwire" and typeof(payload.gun) == "Instance" and typeof(payload.p) == "Vector3" then
			BloodFX.TaserWire(payload.gun, typeof(payload.part) == "Instance" and payload.part or nil, payload.p, typeof(payload.d) == "number" and payload.d or 1)
		elseif hooks.onOther then
			hooks.onOther(t, payload) -- (v2.0: tased, a new limb, missile warnings, admin events ...)
		end
	end)
end

-- (v2.0) the taser's two wires from the gun to where the darts hit, crackling for `duration`
-- (v2.0) electricity crawling over a body: jagged bolts between its limbs that re-strike every frame or two,
-- a flickering blue glow and bursts of sparks (the taser; also anything else that shocks)
local ARC_COLOR = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 240, 255)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 200, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 250, 255)),
})

local function jaggedBolt(holder: BasePart, n: number): { a: { Attachment }, beams: { Beam } }
	local a, beams = {}, {}
	for i = 1, n do
		local at = Instance.new("Attachment")
		at.Name = "Arc"
		at.Parent = holder
		a[i] = at
		if i > 1 then
			local b = Instance.new("Beam")
			b.Attachment0 = a[i - 1]
			b.Attachment1 = at
			b.Width0 = 0.14
			b.Width1 = 0.1
			b.FaceCamera = true
			b.LightEmission = 1
			b.LightInfluence = 0
			b.Brightness = 6
			b.Color = ARC_COLOR
			b.Transparency = NumberSequence.new(0.05)
			b.Segments = 1
			b.Parent = at
			table.insert(beams, b)
		end
	end
	return { a = a, beams = beams }
end

local function strike(bolt, from: Vector3, to: Vector3, jitter: number)
	local n = #bolt.a
	local dir = to - from
	local side = dir:Cross(Vector3.new(0.3, 1, 0.2))
	side = side.Magnitude > 0.01 and side.Unit or Vector3.xAxis
	local up = dir:Cross(side)
	up = up.Magnitude > 0.01 and up.Unit or Vector3.yAxis
	for i, at in bolt.a do
		local t = (i - 1) / (n - 1)
		local off = (i == 1 or i == n) and Vector3.zero or (side * rng:NextNumber(-1, 1) + up * rng:NextNumber(-1, 1)) * jitter * math.sin(t * math.pi)
		at.WorldPosition = from + dir * t + off
	end
	for _, b in bolt.beams do
		b.Width0 = rng:NextNumber(0.06, 0.18)
		b.Width1 = rng:NextNumber(0.04, 0.12)
		b.Enabled = rng:NextNumber() < 0.92
	end
end

function BloodFX.Electrocute(body: Model, duration: number, from: Vector3?)
	local torso = body:FindFirstChild("Torso") or body:FindFirstChild("UpperTorso") or body.PrimaryPart
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local parts = {}
	for _, p in body:GetChildren() do
		if p:IsA("BasePart") and p.Transparency < 1 and p.Name ~= "HumanoidRootPart" then
			table.insert(parts, p)
		end
	end
	if #parts < 2 then
		return
	end
	local made: { Instance } = {}
	local bolts = {}
	for _ = 1, 4 do
		local b = jaggedBolt(torso, 7)
		table.insert(bolts, b)
		for _, at in b.a do
			table.insert(made, at)
		end
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(130, 200, 255)
	light.Range = 14
	light.Brightness = 3
	light.Shadows = false
	light.Parent = torso
	table.insert(made, light)
	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.fromRGB(120, 200, 255)
	hl.OutlineColor = Color3.fromRGB(220, 245, 255)
	hl.FillTransparency = 0.75
	hl.OutlineTransparency = 0.2
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = body
	hl.Parent = folder
	table.insert(made, hl)
	local buzz = SoundLibrary.Loop("taserBuzz", torso)
	if buzz then
		buzz.Volume = 0.5
		buzz:Play()
		table.insert(made, buzz)
	end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration and body.Parent and torso.Parent do
			local fade = math.clamp((duration - (os.clock() - t0)) / 0.8, 0, 1)
			for i, b in bolts do
				local pa = parts[rng:NextInteger(1, #parts)]
				local pb = parts[rng:NextInteger(1, #parts)]
				if i == 1 and from then
					-- the first bolt runs from where the darts went in
					strike(b, from, pb.Position + randomUnit() * 0.4, 0.55)
				elseif pa ~= pb and pa.Parent and pb.Parent then
					strike(b, pa.Position + randomUnit() * 0.5, pb.Position + randomUnit() * 0.5, 0.6)
				end
				for _, beam in b.beams do
					beam.Transparency = NumberSequence.new(1 - 0.95 * fade)
				end
			end
			light.Brightness = (rng:NextNumber(1.5, 5)) * fade
			hl.FillTransparency = 0.6 + rng:NextNumber() * 0.35
			hl.OutlineTransparency = 1 - (0.5 + rng:NextNumber() * 0.5) * fade
			if rng:NextNumber() < 0.35 then
				local sp = parts[rng:NextInteger(1, #parts)]
				if sp.Parent then
					emitAt(sparkEmitter, sp.Position, randomUnit(), 4, 18)
				end
			end
			if buzz then
				buzz.Volume = 0.5 * fade
				buzz.PlaybackSpeed = (buzz:GetAttribute("BaseSpeed") or 1) * rng:NextNumber(0.9, 1.1)
			end
			task.wait(rng:NextNumber(0.03, 0.07))
		end
		for _, inst in made do
			if inst.Parent then
				inst:Destroy()
			end
		end
	end)
end

function BloodFX.TaserWire(gun: Instance, part: Instance?, point: Vector3, duration: number)
	local muzzle = gun:IsA("Model") and Items.Muzzle(gun) or nil
	if not muzzle then
		return
	end
	local holder: BasePart
	local local0 = true
	if part and part:IsA("BasePart") then
		holder = part
	else
		holder = fxPart("WireEnd", Vector3.new(0.1, 0.1, 0.1), Color3.new())
		holder.Transparency = 1
		holder.CFrame = CFrame.new(point)
		holder.Parent = folder
		local0 = false
	end
	local made: { Instance } = {}
	local ends = {}
	for i, off in { Vector3.new(0, 0.12, 0), Vector3.new(0, -0.12, 0) } do
		local a = Instance.new("Attachment")
		a.Name = "TaserDart"
		a.Parent = holder
		a.WorldPosition = point + off * (local0 and 1.5 or 1)
		table.insert(made, a)
		table.insert(ends, a)
		local b = Instance.new("Beam")
		b.Attachment0 = muzzle
		b.Attachment1 = a
		b.Width0 = 0.03
		b.Width1 = 0.03
		b.Color = ColorSequence.new(Color3.fromRGB(70, 70, 74))
		b.Transparency = NumberSequence.new(0)
		b.CurveSize0 = i == 1 and 0.6 or -0.6
		b.CurveSize1 = 0
		b.Segments = 10
		b.Parent = a
	end
	if not local0 then
		table.insert(made, holder)
	end
	-- (v2.0) in a body: the current runs through it
	local body = part and part:IsA("BasePart") and part.Parent
	if body and body:IsA("Model") and body:FindFirstChild("Torso") and duration > 1.5 then
		BloodFX.Electrocute(body, duration, point)
	end
	local wires = {}
	for _, e in ends do
		local b = e:FindFirstChildOfClass("Beam")
		if b then
			b.LightInfluence = 0.5
			table.insert(wires, b)
		end
	end
	task.spawn(function()
		local t0 = os.clock()
		local pulse = 0
		while os.clock() - t0 < duration and gun.Parent and holder.Parent do
			local e = ends[rng:NextInteger(1, #ends)]
			if e.Parent then
				emitAt(sparkEmitter, e.WorldPosition, randomUnit(), 5, 16)
				if rng:NextNumber() < 0.45 then
					SoundLibrary.Play("zap", e.WorldPosition, 0.8)
				end
			end
			-- the current pulses down the wires (a blue flash running along them)
			pulse = (pulse + 1) % 3
			for _, w in wires do
				local lit = pulse == 0 or rng:NextNumber() < 0.25
				w.Color = ColorSequence.new(lit and Color3.fromRGB(140, 210, 255) or Color3.fromRGB(70, 70, 74))
				w.LightEmission = lit and 1 or 0
				w.Width0 = lit and 0.07 or 0.03
				w.Width1 = lit and 0.07 or 0.03
			end
			task.wait(rng:NextNumber(0.06, 0.14))
		end
		for _, inst in made do
			if inst.Parent then
				inst:Destroy()
			end
		end
	end)
end

return BloodFX
