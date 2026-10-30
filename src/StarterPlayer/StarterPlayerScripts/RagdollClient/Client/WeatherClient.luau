--!nonstrict
-- WeatherClient (v1.9): rain and storms, the way the server says (workspace "Weather" / "WeatherK").
--   * thin rain drops that fall around the camera and only fall where nothing roofs them over
--   * a splash where every drop lands, rings in the puddles
--   * puddles that grow while it rains and dry out slowly afterwards (flat floors only, never under a roof)
--   * a rain loop that gets muffled indoors (the rain on the roof, cosy), wind in storms
--   * lightning (flash, a jagged bolt, thunder that arrives later the further away it was)
--   * the sky gets grey and heavy: less sun, more haze, less colour - (v2.8) a storm turns it really dark
--   * (v2.8) SNOW: flakes that drift down and sway, white patches on the ground that grow and melt again, a cold light
--   * (v2.8) FOG: thick haze, the far world fades out, banks of mist roll over the ground round you
--   * (v2.8) CLOUDS: the sky's cloud layer thickens and darkens with the weather, and big soft cloud banks drift high up
-- The sounds use the sound library entries rainLoop / windLoop (see SoundLibrary: put better asset ids there)
-- and the explosion sample played very deep for thunder.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TimeScale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TimeScale"))
local Settings = require(Shared:WaitForChild("Settings"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))

local player = Players.LocalPlayer
local WeatherClient = {}

local rng = Random.new()
local K = 0 -- smoothed strength 0..1 (0.5 = rain, 1 = storm)
local wet = 0 -- how soaked the ground is: grows in rain, dries slowly
local folder: Folder
local drops: { any } = {}
local dropParts: { BasePart } = {}
local dropCFs: { CFrame } = {}
local splashes: { any } = {}
local puddles: { any } = {}
local rainSound: Sound?
local windSound: Sound?
local lowpass: EqualizerSoundEffect?
local flash: Frame

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function ignoreList(): { Instance }
	local list: { Instance } = { folder }
	local fx = workspace:FindFirstChild("FX")
	if fx then
		table.insert(list, fx)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

local function rainFloor(x: number, y: number, z: number): number
	-- where a drop that starts up at (x, y, z) ends: the first thing below it (a roof counts)
	local hit = workspace:Raycast(Vector3.new(x, y, z), Vector3.new(0, -170, 0), rayParams)
	return hit and hit.Position.Y or (y - 150)
end

local function roofAbove(pos: Vector3): boolean
	return workspace:Raycast(pos, Vector3.new(0, 60, 0), rayParams) ~= nil
end

local function newPart(size: Vector3, color: Color3, transparency: number, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Transparency = transparency
	if shape then
		p.Shape = shape
	end
	p.Parent = folder
	return p
end

------------------------------------------------------------------------
-- drops
------------------------------------------------------------------------

local R = 46 -- radius around the camera the rain falls in

local function respawn(d: any, cam: Vector3, initial: boolean)
	local a = rng:NextNumber(0, math.pi * 2)
	local r = math.sqrt(rng:NextNumber()) * R
	local x, z = cam.X + math.cos(a) * r, cam.Z + math.sin(a) * r
	local top = cam.Y + 42
	d.x, d.z = x, z
	d.floor = rainFloor(x, top, z)
	d.y = initial and rng:NextNumber(math.min(d.floor, top), top) or top + rng:NextNumber(0, 8)
	d.vy = -rng:NextNumber(78, 98)
	d.len = rng:NextNumber(1.1, 1.9)
end

local function ensureDrops(want: number, cam: Vector3)
	while #drops < want do
		local p = newPart(Vector3.new(0.03, 1.5, 0.03), Color3.fromRGB(196, 210, 232), 0.5)
		p.Material = Enum.Material.Neon
		local d: any = {}
		respawn(d, cam, true)
		table.insert(drops, d)
		table.insert(dropParts, p)
		table.insert(dropCFs, CFrame.new(0, -1000, 0))
	end
	while #drops > want do
		local p = table.remove(dropParts)
		table.remove(drops)
		table.remove(dropCFs)
		if p then
			p:Destroy()
		end
	end
end

local function splashAt(pos: Vector3, big: boolean)
	for _, s in splashes do
		if not s.live then
			s.age = 0
			s.pos = pos
			s.big = big
			s.live = true
			s.part.Transparency = 0.4
			s.part.CFrame = CFrame.new(pos + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
			return
		end
	end
end

------------------------------------------------------------------------
-- puddles
------------------------------------------------------------------------

local MAX_PUDDLES = 22

local function tryPuddle(cam: Vector3)
	if #puddles >= MAX_PUDDLES then
		return
	end
	local a = rng:NextNumber(0, math.pi * 2)
	local r = rng:NextNumber(6, 44)
	local x, z = cam.X + math.cos(a) * r, cam.Z + math.sin(a) * r
	local hit = workspace:Raycast(Vector3.new(x, cam.Y + 20, z), Vector3.new(0, -80, 0), rayParams)
	if not hit or hit.Normal.Y < 0.985 or not hit.Instance.Anchored then
		return
	end
	-- rain has to reach the spot
	if roofAbove(hit.Position + Vector3.new(0, 0.5, 0)) then
		return
	end
	for _, p in puddles do
		if (p.pos - hit.Position).Magnitude < 5 then
			return
		end
	end
	local part = newPart(Vector3.new(0.05, 1, 1), Color3.fromRGB(34, 42, 56), 0.12, Enum.PartType.Cylinder)
	part.Reflectance = 0.45
	part.Material = Enum.Material.Glass
	part.CFrame = CFrame.new(hit.Position + Vector3.new(0, 0.045, 0)) * CFrame.Angles(0, 0, math.rad(90))
	table.insert(puddles, { part = part, pos = hit.Position, size = 0, target = rng:NextNumber(3, 9), born = os.clock() })
end

------------------------------------------------------------------------
-- lightning
------------------------------------------------------------------------

local function bolt(pos: Vector3)
	local top = pos + Vector3.new(rng:NextNumber(-30, 30), 260, rng:NextNumber(-30, 30))
	local segs = 9
	local prev = top
	local parts = {}
	for i = 1, segs do
		local t = i / segs
		local pt = top:Lerp(pos, t) + (i < segs and Vector3.new(rng:NextNumber(-14, 14), 0, rng:NextNumber(-14, 14)) or Vector3.zero)
		local mid = (prev + pt) / 2
		local len = (pt - prev).Magnitude
		local p = newPart(Vector3.new(0.7, 0.7, len), Color3.fromRGB(220, 232, 255), 0, nil)
		p.Material = Enum.Material.Neon
		p.CFrame = CFrame.lookAt(mid, pt)
		table.insert(parts, p)
		prev = pt
	end
	for _, p in parts do
		TweenService:Create(p, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
		task.delay(0.4, function()
			p:Destroy()
		end)
	end
end

local function onLightning()
	local pos = workspace:GetAttribute("LightningPos")
	if typeof(pos) ~= "Vector3" then
		return
	end
	local cam = workspace.CurrentCamera
	local dist = cam and (cam.CFrame.Position - pos).Magnitude or 200
	local near = math.clamp(1 - dist / 600, 0.12, 1)
	bolt(pos)
	-- flash (two quick ones)
	task.spawn(function()
		for i = 1, 2 do
			flash.BackgroundTransparency = 1 - 0.55 * near
			TweenService:Create(flash, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
			task.wait(0.14)
		end
	end)
	-- thunder arrives later the further away it was
	local delay = math.clamp(dist / 340, 0.15, 5)
	task.delay(delay, function()
		SoundLibrary.Play("explosion", nil, math.clamp(0.3 + near * 0.9, 0.25, 1), 0.33)
		task.wait(0.5)
		SoundLibrary.Play("explosion", nil, math.clamp(0.2 + near * 0.6, 0.15, 0.8), 0.24)
	end)
end

------------------------------------------------------------------------
-- sky
------------------------------------------------------------------------

local baseValues: { [string]: any } = {}
local written: { [string]: any } = {}
local restores: { [string]: () -> () } = {}

-- (the server's day / night cycle and the experimental lighting write these now and then: when somebody else
-- changed one, that is the new base; we put our version over it)
local function same(a: any, b: any): boolean
	if typeof(a) == "number" and typeof(b) == "number" then
		return math.abs(a - b) <= 1e-3 * math.max(1, math.abs(a))
	end
	if typeof(a) == "Color3" and typeof(b) == "Color3" then
		return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.01
	end
	return a == b
end

-- watch = true for the properties that the day / night cycle (or the experimental lighting) rewrites now and then
local function layer(inst: Instance, prop: string, make: (any) -> any, watch: boolean?)
	local key = inst:GetFullName() .. "." .. prop
	local cur = (inst :: any)[prop]
	if written[key] == nil then
		baseValues[key] = cur -- first time (or first time again after the weather was gone): this is the base
	elseif watch and not same(cur, written[key]) then
		baseValues[key] = cur -- somebody else changed it: that is the new base
	end
	local v = make(baseValues[key])
	written[key] = v
	;(inst :: any)[prop] = v
	restores[key] = function()
		pcall(function()
			if (inst :: any)[prop] == written[key] and baseValues[key] ~= nil then
				(inst :: any)[prop] = baseValues[key]
			end
		end)
		written[key] = nil
	end
end

local function applySky(k: number, storm: number, snow: number, fog: number)
	if k <= 0.001 and snow <= 0.001 and fog <= 0.001 then
		-- the weather is gone: everything back to what it was
		for key, fn in restores do
			fn()
			restores[key] = nil
		end
		return
	end
	local grey = math.max(k, snow * 0.7, fog * 0.8) -- (how overcast it is)
	-- (v2.8) a storm really darkens the day (like the clip): less light, a low dark sky, the colours go
	layer(Lighting, "Brightness", function(b)
		return b * math.max(0.25, 1 - 0.3 * k - 0.38 * storm - 0.12 * fog + 0.04 * snow)
	end, true)
	layer(Lighting, "OutdoorAmbient", function(c)
		local out = c:Lerp(Color3.fromRGB(86, 94, 112), 0.6 * k)
		out = out:Lerp(Color3.fromRGB(46, 52, 66), 0.55 * storm)
		out = out:Lerp(Color3.fromRGB(176, 186, 204), 0.35 * snow)
		return out:Lerp(Color3.fromRGB(150, 154, 160), 0.3 * fog)
	end, true)
	layer(Lighting, "ExposureCompensation", function(e)
		return e - 0.55 * storm - 0.12 * fog
	end, true)
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		layer(atm, "Density", function(d)
			local v = d + (0.46 - d) * math.clamp(k * 0.85, 0, 1)
			v += (0.5 - v) * 0.5 * storm
			v += (0.5 - v) * 0.6 * snow
			return v + (0.9 - v) * fog -- (v2.8.1: much thicker fog)
		end)
		layer(atm, "Offset", function(o)
			return o * (1 - fog)
		end)
		layer(atm, "Haze", function(h)
			local v = h + (2.6 - h) * k
			return v + (5.5 - v) * math.max(fog, snow * 0.6)
		end)
		layer(atm, "Glare", function(g)
			return g * (1 - grey)
		end)
		layer(atm, "Color", function(c)
			local out = c:Lerp(Color3.fromRGB(150, 158, 170), 0.7 * k)
			out = out:Lerp(Color3.fromRGB(78, 84, 96), 0.6 * storm)
			out = out:Lerp(Color3.fromRGB(214, 220, 230), 0.6 * snow)
			return out:Lerp(Color3.fromRGB(190, 194, 198), 0.85 * fog)
		end)
		layer(atm, "Decay", function(c)
			local out = c:Lerp(Color3.fromRGB(60, 64, 74), 0.6 * storm)
			return out:Lerp(Color3.fromRGB(170, 174, 180), 0.7 * fog)
		end)
	end
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if cc then
		layer(cc, "Saturation", function(s)
			return s - 0.28 * k - 0.15 * storm - 0.12 * snow - 0.2 * fog
		end)
		layer(cc, "Brightness", function(b)
			return b - 0.03 * k - 0.05 * storm
		end)
		layer(cc, "Contrast", function(c)
			return c + 0.08 * storm - 0.06 * fog
		end)
		layer(cc, "TintColor", function(t)
			return t:Lerp(Color3.fromRGB(226, 236, 255), 0.6 * snow)
		end)
	end
	local sun = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if sun then
		layer(sun, "Intensity", function(i)
			return i * (1 - 0.9 * grey)
		end)
	end
	-- the cloud layer of the sky (Terrain.Clouds): thick and dark in a storm, white and full in snow
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		layer(clouds, "Cover", function(c)
			return c + (1 - c) * math.max(k, snow, fog * 0.8)
		end)
		layer(clouds, "Density", function(d)
			return d + (1 - d) * math.max(storm, snow * 0.6)
		end)
		layer(clouds, "Color", function(c)
			local out = c:Lerp(Color3.fromRGB(150, 156, 166), k)
			out = out:Lerp(Color3.fromRGB(62, 66, 76), storm)
			return out:Lerp(Color3.fromRGB(226, 230, 238), snow)
		end)
	end
end

------------------------------------------------------------------------
-- (v2.8) snow, fog, cloud banks
------------------------------------------------------------------------

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local flakes: { any } = {}
local flakeParts: { BasePart } = {}
local flakeCFs: { CFrame } = {}
local drifts: { any } = {}
local snowCover = 0 -- how white the ground is: grows while it snows, melts afterwards
local mistParts: { BasePart } = {}
local bankParts: { BasePart } = {}
local SR = 50 -- radius around the camera the snow falls in

local function respawnFlake(f: any, cam: Vector3, initial: boolean)
	local a = rng:NextNumber(0, math.pi * 2)
	local r = math.sqrt(rng:NextNumber()) * SR
	f.x, f.z = cam.X + math.cos(a) * r, cam.Z + math.sin(a) * r
	local top = cam.Y + 32
	f.floor = rainFloor(f.x, top, f.z)
	f.y = initial and rng:NextNumber(math.min(f.floor, top), top) or top + rng:NextNumber(0, 6)
	f.vy = -rng:NextNumber(6, 11)
	f.phase = rng:NextNumber(0, math.pi * 2)
	f.sway = rng:NextNumber(0.6, 1.6)
end

local function ensureFlakes(want: number, cam: Vector3)
	while #flakes < want do
		local p = newPart(Vector3.new(0.22, 0.22, 0.22), Color3.fromRGB(246, 248, 255), 0.05, Enum.PartType.Ball)
		local f: any = {}
		respawnFlake(f, cam, true)
		table.insert(flakes, f)
		table.insert(flakeParts, p)
		table.insert(flakeCFs, CFrame.new(0, -1000, 0))
	end
	while #flakes > want do
		local p = table.remove(flakeParts)
		table.remove(flakes)
		table.remove(flakeCFs)
		if p then
			p:Destroy()
		end
	end
end

local MAX_DRIFTS = 26
local function tryDrift(cam: Vector3)
	if #drifts >= MAX_DRIFTS then
		return
	end
	local a = rng:NextNumber(0, math.pi * 2)
	local r = rng:NextNumber(5, 46)
	local x, z = cam.X + math.cos(a) * r, cam.Z + math.sin(a) * r
	local hit = workspace:Raycast(Vector3.new(x, cam.Y + 20, z), Vector3.new(0, -80, 0), rayParams)
	if not hit or hit.Normal.Y < 0.95 or not hit.Instance.Anchored or roofAbove(hit.Position + Vector3.new(0, 0.5, 0)) then
		return
	end
	for _, d in drifts do
		if (d.pos - hit.Position).Magnitude < 5 then
			return
		end
	end
	local part = newPart(Vector3.new(0.06, 1, 1), Color3.fromRGB(242, 245, 250), 0.05, Enum.PartType.Cylinder)
	part.Material = Enum.Material.Snow
	part.CFrame = CFrame.new(hit.Position + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90))
	table.insert(drifts, { part = part, pos = hit.Position, size = 0, target = rng:NextNumber(4, 11) })
end

local function smokeEmitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE
	e.Orientation = Enum.ParticleOrientation.FacingCamera
	e.RotSpeed = NumberRange.new(-4, 4)
	e.Rotation = NumberRange.new(0, 360)
	e.LightInfluence = 1
	for k2, v in props do
		(e :: any)[k2] = v
	end
	e.Parent = parent
	return e
end

-- ground mist (fog) and high cloud banks: emitters on invisible boxes that follow the camera (the puffs stay where they
-- were born, so the world does not slide along)
local function buildAir()
	for i = 1, 6 do
		local p = newPart(Vector3.new(36, 4, 36), Color3.new(1, 1, 1), 1)
		p.Name = "Mist"
		smokeEmitter(p, {
			Name = "Mist",
			Rate = 0,
			Lifetime = NumberRange.new(9, 14),
			Speed = NumberRange.new(0.4, 1.4),
			SpreadAngle = Vector2.new(180, 10),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 14), NumberSequenceKeypoint.new(1, 26) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.7), NumberSequenceKeypoint.new(0.7, 0.74), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(Color3.fromRGB(214, 218, 222)),
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		})
		p:SetAttribute("Slot", i)
		table.insert(mistParts, p)
	end
	for i = 1, 6 do
		local p = newPart(Vector3.new(220, 40, 220), Color3.new(1, 1, 1), 1)
		p.Name = "CloudBank"
		smokeEmitter(p, {
			Name = "Bank",
			Rate = 0,
			Lifetime = NumberRange.new(40, 60),
			Speed = NumberRange.new(0.5, 2),
			SpreadAngle = Vector2.new(180, 6),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 70), NumberSequenceKeypoint.new(1, 130) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.55), NumberSequenceKeypoint.new(0.75, 0.6), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(Color3.fromRGB(240, 242, 246)),
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		})
		p:SetAttribute("Slot", i)
		table.insert(bankParts, p)
	end
end

local function updateAir(cam: Vector3, rain: number, storm: number, snow: number, fog: number, quality: number, inMap: boolean)
	-- mist round you on the ground
	local mistRate = fog * 2.4 * quality -- (v2.8.1: thicker)
	for _, p in mistParts do
		local i = p:GetAttribute("Slot")
		local a = (i / 6) * math.pi * 2 + os.clock() * 0.01
		p.CFrame = CFrame.new(cam.X + math.cos(a) * 26, cam.Y - 3, cam.Z + math.sin(a) * 26)
		local e = p:FindFirstChild("Mist") :: ParticleEmitter
		if e then
			e.Rate = mistRate
		end
	end
	-- banks of cloud high up: a few white ones on a fair day, many grey ones in rain, dark heavy ones in a storm
	local bankRate = (inMap and 0 or (0.12 + 0.35 * rain + 0.3 * storm + 0.3 * snow)) * quality
	local col = Color3.fromRGB(240, 242, 246):Lerp(Color3.fromRGB(150, 154, 162), rain):Lerp(Color3.fromRGB(70, 74, 84), storm)
	for _, p in bankParts do
		local i = p:GetAttribute("Slot")
		local a = (i / 6) * math.pi * 2
		p.CFrame = CFrame.new(cam.X + math.cos(a) * 380, 300 + (i % 3) * 30, cam.Z + math.sin(a) * 380)
		local e = p:FindFirstChild("Bank") :: ParticleEmitter
		if e then
			e.Rate = bankRate
			e.Color = ColorSequence.new(col)
		end
	end
end

------------------------------------------------------------------------
-- (v2.8.2) CLOUDS made of particles: every cloud is a box high up full of big soft smoke puffs (Roblox particles, the
-- puffs ride along with their box) - white and bright on a fair day, grey in rain, dark in a storm, a greyer flatter
-- underside. They drift with the wind round you, more and lower the worse the weather; gone down in the Pit.
-- (They replace the round 3D cloud blobs of v2.8.1.)
------------------------------------------------------------------------

type Cloud = { part: BasePart, top: ParticleEmitter, base: ParticleEmitter, pos: Vector3, scale: number, on: boolean }
local clouds3d: { Cloud } = {}
local cloudParts: { BasePart } = {}
local cloudCFs: { CFrame } = {}
local CLOUDS = 18
local CLOUD_R = 1100 -- how far round the camera they are
local function placeCloud(c: Cloud, cam: Vector3, anywhere: boolean)
	local a = rng:NextNumber(0, math.pi * 2)
	local d = anywhere and math.sqrt(rng:NextNumber()) * CLOUD_R or CLOUD_R * rng:NextNumber(0.85, 1)
	if not anywhere then
		-- (it comes in from upwind: the side the wind blows from)
		a = math.pi + rng:NextNumber(-1.1, 1.1)
	end
	c.pos = Vector3.new(cam.X + math.cos(a) * d, rng:NextNumber(380, 520), cam.Z + math.sin(a) * d)
	-- a cloud that comes back in is a new one: its old puffs go
	c.top:Clear()
	c.base:Clear()
	c.on = false
end

local function buildClouds()
	for _ = 1, CLOUDS do
		local scale = rng:NextNumber(0.7, 1.4)
		local box = newPart(Vector3.new(170 * scale, 26 * scale, 70 * scale), Color3.new(1, 1, 1), 1)
		box.Name = "CloudBox"
		local top = smokeEmitter(box, {
			Name = "Puffs",
			Rate = 0,
			LockedToPart = true,
			Lifetime = NumberRange.new(28, 42),
			Speed = NumberRange.new(0.2, 1.2),
			SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 70 * scale), NumberSequenceKeypoint.new(0.5, 115 * scale), NumberSequenceKeypoint.new(1, 130 * scale) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.2), NumberSequenceKeypoint.new(0.8, 0.28), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(Color3.fromRGB(250, 251, 255)),
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			RotSpeed = NumberRange.new(-1, 1),
		})
		local base = smokeEmitter(box, {
			Name = "Underside",
			Rate = 0,
			LockedToPart = true,
			Lifetime = NumberRange.new(28, 42),
			Speed = NumberRange.new(0, 0.6),
			SpreadAngle = Vector2.new(180, 5),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 60 * scale), NumberSequenceKeypoint.new(1, 95 * scale) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.35), NumberSequenceKeypoint.new(0.8, 0.4), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(Color3.fromRGB(200, 206, 216)),
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			EmissionDirection = Enum.NormalId.Bottom,
			RotSpeed = NumberRange.new(-1, 1),
		})
		local c: Cloud = { part = box, top = top, base = base, pos = Vector3.zero, scale = scale, on = false }
		table.insert(clouds3d, c)
		table.insert(cloudParts, box)
		table.insert(cloudCFs, CFrame.new(0, -5000, 0))
	end
	local cam = workspace.CurrentCamera
	local at = cam and cam.CFrame.Position or Vector3.zero
	for _, c in clouds3d do
		placeCloud(c, at, true)
	end
end

local cloudTint = Color3.fromRGB(250, 251, 255)
local function updateClouds(dt: number, cam: Vector3, rain: number, storm: number, snow: number, fog: number, hidden: boolean)
	local want = hidden and 0 or math.floor(9 + 9 * math.max(rain, snow, fog * 0.6))
	local wind = Vector3.new(5 + 16 * storm, 0, 1.5 + 4 * storm) * dt * TimeScale.Get()
	local lower = 90 * math.max(rain, storm, snow * 0.6)
	local tint = Color3.fromRGB(250, 251, 255):Lerp(Color3.fromRGB(170, 174, 182), rain):Lerp(Color3.fromRGB(78, 82, 92), storm)
	tint = tint:Lerp(Color3.fromRGB(232, 236, 242), snow * 0.5)
	local recolor = (tint.R - cloudTint.R) ^ 2 + (tint.G - cloudTint.G) ^ 2 + (tint.B - cloudTint.B) ^ 2 > 0.0004
	if recolor then
		cloudTint = tint
	end
	for i, c in clouds3d do
		c.pos += wind
		local flat = Vector3.new(c.pos.X - cam.X, 0, c.pos.Z - cam.Z)
		if flat.Magnitude > CLOUD_R * 1.08 then
			placeCloud(c, cam, false)
		end
		local shown = i <= want
		cloudCFs[i] = CFrame.new(c.pos - Vector3.new(0, lower, 0))
		if hidden then
			if c.on then
				c.top:Clear()
				c.base:Clear()
				c.on = false
			end
			c.top.Rate = 0
			c.base.Rate = 0
		elseif shown then
			if not c.on then
				-- (a whole cloud at once, then it keeps itself up)
				c.on = true
				c.top:Emit(math.floor(9 * c.scale + 4))
				c.base:Emit(4)
			end
			c.top.Rate = 0.32 * c.scale
			c.base.Rate = 0.12
		else
			-- (no longer wanted: it thins out by itself)
			c.top.Rate = 0
			c.base.Rate = 0
			c.on = false
		end
		if recolor then
			c.top.Color = ColorSequence.new(tint)
			c.base.Color = ColorSequence.new(tint:Lerp(Color3.new(0, 0, 0), 0.18))
		end
	end
	if #cloudParts > 0 then
		workspace:BulkMoveTo(cloudParts, cloudCFs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function WeatherClient.Init()
	folder = Instance.new("Folder")
	folder.Name = "Weather"
	folder.Parent = workspace.CurrentCamera or workspace

	local gui = Instance.new("ScreenGui")
	gui.Name = "WeatherFlash"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 40
	gui.Parent = player:WaitForChild("PlayerGui")
	flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.fromRGB(230, 238, 255)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Active = false
	flash.Parent = gui

	-- splash rings
	for _ = 1, 50 do
		local p = newPart(Vector3.new(0.04, 0.4, 0.4), Color3.fromRGB(205, 215, 232), 1, Enum.PartType.Cylinder)
		table.insert(splashes, { part = p, age = 1, live = false, pos = Vector3.zero, big = false })
	end

	rainSound = SoundLibrary.Loop("rainLoop", SoundService)
	windSound = SoundLibrary.Loop("windLoop", SoundService)
	if rainSound then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = 0
		eq.MidGain = 0
		eq.HighGain = 0
		eq.Parent = rainSound
		lowpass = eq
		rainSound:Play()
	end
	if windSound then
		windSound:Play()
	end

	local lastLightning = workspace:GetAttribute("LightningId") or 0
	workspace:GetAttributeChangedSignal("LightningId"):Connect(function()
		local id = workspace:GetAttribute("LightningId")
		if id ~= lastLightning then
			lastLightning = id
			onLightning()
		end
	end)

	buildAir()
	buildClouds()
	local snowS, fogS = 0, 0
	local indoors = 0
	local puddleClock = 0
	local roofClock = 0
	local floorSkip = 0
	RunService.RenderStepped:Connect(function(dt)
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local target = workspace:GetAttribute("WeatherK")
		if typeof(target) ~= "number" then
			target = 0
		end
		local snowT = workspace:GetAttribute("SnowK")
		local fogT = workspace:GetAttribute("FogK")
		snowT = typeof(snowT) == "number" and snowT or 0
		fogT = typeof(fogT) == "number" and fogT or 0
		-- (v2.8) down in the Pit there is no weather (SwordClient sets the Pit's own air)
		if Lighting:GetAttribute("PitOverride") == true then
			target, snowT, fogT = 0, 0, 0
			K, snowS, fogS = 0, 0, 0
		end
		K += (target - K) * math.min(1, dt * 1.4)
		snowS += (snowT - snowS) * math.min(1, dt * 1.4)
		fogS += (fogT - fogS) * math.min(1, dt * 1.4)
		local rain = math.clamp(K * 2, 0, 1)
		local storm = math.clamp((K - 0.5) * 2, 0, 1)
		local pos = cam.CFrame.Position
		rayParams.FilterDescendantsInstances = ignoreList()

		-- the ground gets wet while it rains and dries slowly
		if rain > 0.15 then
			wet = math.min(1, wet + dt / 55)
		else
			wet = math.max(0, wet - dt / 30) -- (v1.9.1: dries in half a minute, not minutes)
		end

		-- drops
		local quality = Settings.Get("vfx") == false and 0.4 or 1
		local want = math.floor((60 + 240 * rain) * quality * (rain > 0.02 and 1 or 0))
		ensureDrops(want, pos)
		local drift = Vector3.new(6 + storm * 22, 0, 2 + storm * 8) -- the wind slants the rain
		-- (v2.8.1) a Sandevistan runs: the rain and the snow hang in the air (they fall in slow motion for everybody)
		local sdt = dt * TimeScale.Get()
		for i, d in drops do
			d.y += d.vy * sdt
			d.x += drift.X * sdt * 0.5
			d.z += drift.Z * sdt * 0.5
			if d.y <= d.floor then
				if (Vector3.new(d.x, d.floor, d.z) - pos).Magnitude < 38 then
					splashAt(Vector3.new(d.x, d.floor, d.z), false)
				end
				respawn(d, pos, false)
			elseif math.abs(d.x - pos.X) > R + 8 or math.abs(d.z - pos.Z) > R + 8 then
				respawn(d, pos, false)
			end
			local vel = Vector3.new(drift.X * 0.5, d.vy, drift.Z * 0.5)
			dropCFs[i] = CFrame.lookAt(Vector3.new(d.x, d.y, d.z), Vector3.new(d.x, d.y, d.z) + vel) * CFrame.Angles(math.pi / 2, 0, 0)
		end
		if #dropParts > 0 then
			workspace:BulkMoveTo(dropParts, dropCFs, Enum.BulkMoveMode.FireCFrameChanged)
		end

		-- splashes
		for _, s in splashes do
			if s.live then
				s.age += sdt
				local t = s.age / 0.3
				if t >= 1 then
					s.live = false
					s.part.Transparency = 1
				else
					local sz = (s.big and 1.6 or 0.5) * (0.3 + t)
					s.part.Size = Vector3.new(0.04, sz, sz)
					s.part.Transparency = 0.35 + 0.65 * t
					s.part.CFrame = CFrame.new(s.pos + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
				end
			end
		end

		-- puddles: new ones while it rains, they grow with the wetness and shrink when it dries
		puddleClock += dt
		if puddleClock > 0.6 then
			puddleClock = 0
			if wet > 0.25 and rain > 0.1 then
				tryPuddle(pos)
			end
			-- ripples inside puddles
			if rain > 0.1 then
				for _, p in puddles do
					if p.size > 1.5 and rng:NextNumber() < 0.6 and (p.pos - pos).Magnitude < 40 then
						local a = rng:NextNumber(0, math.pi * 2)
						local rr = math.sqrt(rng:NextNumber()) * p.size * 0.4
						splashAt(p.pos + Vector3.new(math.cos(a) * rr, 0.03, math.sin(a) * rr), true)
					end
				end
			end
		end
		for i = #puddles, 1, -1 do
			local p = puddles[i]
			local want = p.target * math.clamp((wet - 0.2) / 0.8, 0, 1)
			p.size += (want - p.size) * math.min(1, dt * 0.4)
			if p.size < 0.15 and wet < 0.05 then
				p.part:Destroy()
				table.remove(puddles, i)
			else
				local s = math.max(p.size, 0.01)
				p.part.Size = Vector3.new(0.05, s, s * 0.82)
				p.part.Transparency = 0.12 + (1 - math.clamp(wet, 0, 1)) * 0.5
			end
		end

		-- sounds: the rain on the roof when you are inside
		roofClock += dt
		if roofClock > 0.25 then
			roofClock = 0
			local under = roofAbove(pos)
			indoors += ((under and 1 or 0) - indoors) * 0.5
		end
		if rainSound then
			rainSound.Volume = 0.55 * rain * (1 - 0.6 * indoors) * (Settings.Get("volume") or 1)
			rainSound.PlaybackSpeed = 0.88 + rain * 0.12 + storm * 0.1
		end
		if lowpass then
			lowpass.HighGain = -26 * indoors -- cosy: the rain heard through a roof
			lowpass.LowGain = 3 * indoors
		end
		if windSound then
			windSound.Volume = (0.12 * rain + 0.4 * storm) * (1 - 0.5 * indoors) * (Settings.Get("volume") or 1)
			windSound.PlaybackSpeed = 0.55 + 0.1 * math.sin(os.clock() * 0.37) + storm * 0.1
		end

		-- (v2.8) snow: flakes drift down and sway; white patches grow on open ground
		local snowing = math.clamp(snowS, 0, 1)
		local wantFlakes = math.floor((80 + 300 * snowing) * quality * (snowing > 0.02 and 1 or 0))
		ensureFlakes(wantFlakes, pos)
		local t = os.clock()
		for i, f in flakes do
			f.y += f.vy * sdt
			local sx = math.sin(t * 1.3 + f.phase) * f.sway
			local sz = math.cos(t * 1.1 + f.phase) * f.sway * 0.6
			f.x += (sx + 1.5) * sdt
			f.z += sz * sdt
			if f.y <= f.floor or math.abs(f.x - pos.X) > SR + 8 or math.abs(f.z - pos.Z) > SR + 8 then
				respawnFlake(f, pos, false)
			end
			flakeCFs[i] = CFrame.new(f.x, f.y, f.z)
		end
		if #flakeParts > 0 then
			workspace:BulkMoveTo(flakeParts, flakeCFs, Enum.BulkMoveMode.FireCFrameChanged)
		end
		if snowing > 0.2 then
			snowCover = math.min(1, snowCover + dt / 70)
		else
			snowCover = math.max(0, snowCover - dt / 40)
		end
		if snowing > 0.3 and snowCover > 0.15 and rng:NextNumber() < dt * 2 then
			tryDrift(pos)
		end
		for i = #drifts, 1, -1 do
			local d = drifts[i]
			local want = d.target * math.clamp((snowCover - 0.1) / 0.9, 0, 1)
			d.size += (want - d.size) * math.min(1, dt * 0.3)
			if d.size < 0.15 and snowCover < 0.05 then
				d.part:Destroy()
				table.remove(drifts, i)
			else
				local sz = math.max(d.size, 0.01)
				d.part.Size = Vector3.new(0.06, sz, sz * 0.85)
				d.part.Transparency = 0.05 + (1 - math.clamp(snowCover * 1.5, 0, 1)) * 0.6
			end
		end
		local inMap = workspace:GetAttribute("MapLoaded") ~= nil and pos.Y < 400 and (math.abs(pos.X) > 1200 or math.abs(pos.Z) > 1200)
		updateAir(pos, rain, storm, snowing, math.clamp(fogS, 0, 1), Settings.Get("vfx") == false and 0.4 or 1,
			(inMap and fogS < 0.1) or Lighting:GetAttribute("PitOverride") == true)
		if windSound and snowing > 0.05 then
			windSound.Volume = math.max(windSound.Volume, 0.14 * snowing * (1 - 0.5 * indoors) * (Settings.Get("volume") or 1))
		end

		applySky(K, storm, snowing, math.clamp(fogS, 0, 1))
		updateClouds(dt, pos, rain, storm, snowing, math.clamp(fogS, 0, 1), Lighting:GetAttribute("PitOverride") == true)
	end)
end

return WeatherClient
