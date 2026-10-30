--!nonstrict
-- SpinFX (v2.0): how the Spin looks on this screen.
--   * Relic   : the SPIN in the construction site (quest 3): a glass orb with a green core, a golden spiral
--               engraved round it, three rings of light orbiting at different tilts, sparks drifting round it
--   * Absorb  : touching it - streams of gold and green light pour from it into you, a shock ring, a flash
--   * Fill    : the Spin fills a body: light climbs from the feet to the head, limb by limb, a ring and two
--               sparks spiral up round it, then a burst (everybody sees it on whoever found a Spin Circle)
--   * circles : a Spin Circle lying somewhere (QuestService): a magic circle on the ground - two rings, ticks and
--               a golden spiral that turn slowly, sparks rising, a soft hum. No marker anywhere.
-- Everything here is local (made on this screen only) and moved with BulkMoveTo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))

local SpinFX = {}

local GOLD = Color3.fromRGB(255, 214, 70)
local GREEN = Config.SpinBallColor
local SPARKS = "rbxasset://textures/particles/sparkles_main.dds"
local PHI = (1 + math.sqrt(5)) / 2

local function fxFolder(): Instance
	return workspace:FindFirstChild("FX") or workspace
end

local function vpart(parent: Instance, name: string, size: Vector3, color: Color3, mat: Enum.Material?, shape: Enum.PartType?, transparency: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat or Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Transparency = transparency or 0
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKS
	e.LightEmission = 1
	e.LightInfluence = 0
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

-- a ring of short glowing segments (Roblox has no torus): { part, angle } in the ring's own space
type Ring = { parts: { BasePart }, radius: number }
local function makeRing(parent: Instance, name: string, radius: number, count: number, thick: number, color: Color3, transparency: number?): Ring
	local parts: { BasePart } = {}
	local len = 2 * math.pi * radius / count * 1.08
	for _ = 1, count do
		table.insert(parts, vpart(parent, name, Vector3.new(thick, thick, len), color, Enum.Material.Neon, nil, transparency))
	end
	return { parts = parts, radius = radius }
end

local function placeRing(r: Ring, cf: CFrame, spin: number, scale: number?, parts: { BasePart }, cfs: { CFrame })
	local n = #r.parts
	local rad = r.radius * (scale or 1)
	for i, p in r.parts do
		local a = spin + (i - 1) / n * math.pi * 2
		table.insert(parts, p)
		table.insert(cfs, cf * CFrame.Angles(0, a, 0) * CFrame.new(rad, 0, 0))
	end
end

local function ringSize(r: Ring, scale: number)
	local len = 2 * math.pi * r.radius * scale / #r.parts * 1.08
	for _, p in r.parts do
		p.Size = Vector3.new(p.Size.X, p.Size.Y, math.max(0.05, len))
	end
end

------------------------------------------------------------------------
-- the relic
------------------------------------------------------------------------

export type Relic = { model: Model, Step: (Relic, number, CFrame, number?) -> (), Destroy: (Relic) -> () }

function SpinFX.Relic(): Relic
	local m = Instance.new("Model")
	m.Name = "SpinRelicFX"
	local core = vpart(m, "Core", Vector3.new(0.85, 0.85, 0.85), GREEN, Enum.Material.Neon, Enum.PartType.Ball)
	local shell = vpart(m, "Shell", Vector3.new(1.55, 1.55, 1.55), Color3.fromRGB(255, 236, 170), Enum.Material.Glass, Enum.PartType.Ball, 0.55)
	shell.Reflectance = 0.25
	-- the golden spiral round the orb (latitude climbs while it winds round 2.5 times)
	local helix = {}
	local N = 30
	for k = 1, N do
		table.insert(helix, vpart(m, "Helix", Vector3.new(0.12, 0.12, 0.12), GOLD:Lerp(GREEN, (k - 1) / (N - 1) * 0.5), Enum.Material.Neon, Enum.PartType.Ball))
	end
	-- three rings, each with a bead riding on it
	local rings = {
		makeRing(m, "RingA", 1.35, 28, 0.07, GOLD),
		makeRing(m, "RingB", 1.7, 34, 0.06, GREEN),
		makeRing(m, "RingC", 2.1, 40, 0.05, GOLD, 0.25),
	}
	local beads = {}
	for i = 1, 3 do
		table.insert(beads, vpart(m, "Bead", Vector3.new(0.22, 0.22, 0.22), i == 2 and GOLD or GREEN, Enum.Material.Neon, Enum.PartType.Ball))
	end
	-- a faint glow under it and sparks round it
	local glow = vpart(m, "Glow", Vector3.new(3.6, 3.6, 3.6), GREEN, Enum.Material.Neon, Enum.PartType.Ball, 0.93)
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 20
	light.Brightness = 2.4
	light.Shadows = false
	light.Parent = core
	emitter(core, {
		Name = "Orbit",
		Color = ColorSequence.new(GOLD, GREEN),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.8, 1.6),
		Speed = NumberRange.new(1.5, 3.5),
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-200, 200),
		Drag = 2,
		Rate = 26,
	})
	emitter(glow, {
		Name = "Motes",
		Color = ColorSequence.new(GREEN),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0.04) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(2, 3.5),
		Speed = NumberRange.new(0.3, 0.8),
		Acceleration = Vector3.new(0, 0.8, 0),
		SpreadAngle = Vector2.new(180, 180),
		Rate = 14,
	})
	m.PrimaryPart = core
	m.Parent = fxFolder()

	local self: any = { model = m }
	local parts: { BasePart } = {}
	local cfs: { CFrame } = {}
	function self.Step(_s, now: number, cf: CFrame, intensity: number?)
		local k = intensity or 0 -- 0 = resting, 1 = it is about to burst into you (faster, tighter)
		table.clear(parts)
		table.clear(cfs)
		local spin = now * (1.1 + k * 7)
		local pulse = 1 + math.sin(now * 3.2) * 0.04 + k * 0.15
		table.insert(parts, core)
		table.insert(cfs, cf)
		table.insert(parts, shell)
		table.insert(cfs, cf * CFrame.Angles(0, spin * 0.6, 0))
		table.insert(parts, glow)
		table.insert(cfs, cf)
		core.Size = Vector3.new(0.85, 0.85, 0.85) * pulse
		local orb = cf * CFrame.Angles(0, spin * 0.6, 0)
		for i, h in helix do
			local f = (i - 1) / (#helix - 1)
			local lat = math.rad(-72 + 144 * f)
			local lon = f * math.pi * 2 * 2.5
			local r = 0.8
			table.insert(parts, h)
			table.insert(cfs, orb * CFrame.new(math.cos(lat) * math.cos(lon) * r, math.sin(lat) * r, math.cos(lat) * math.sin(lon) * r))
		end
		local shrink = 1 - k * 0.45
		local tilts = {
			CFrame.Angles(math.rad(70), 0, math.rad(15)),
			CFrame.Angles(math.rad(-35), now * 0.3, math.rad(60)),
			CFrame.Angles(math.rad(10), -now * 0.2, math.rad(-25)),
		}
		local speeds = { 1.6, -1.15, 0.8 }
		for i, ring in rings do
			local rcf = cf * tilts[i]
			ringSize(ring, shrink)
			placeRing(ring, rcf, spin * speeds[i] / 1.1, shrink, parts, cfs)
			local a = spin * speeds[i] * 1.7 + i
			table.insert(parts, beads[i])
			table.insert(cfs, rcf * CFrame.Angles(0, a, 0) * CFrame.new(ring.radius * shrink, 0, 0))
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		light.Brightness = 2.4 + k * 4
	end
	function self.Destroy(_s)
		m:Destroy()
	end
	return self :: Relic
end

------------------------------------------------------------------------
-- a shock ring on the ground / in the air (expands and fades)
------------------------------------------------------------------------

function SpinFX.Shock(cf: CFrame, color: Color3, toRadius: number, time: number)
	local holder = Instance.new("Model")
	holder.Name = "SpinShock"
	holder.Parent = fxFolder()
	local ring = makeRing(holder, "Shock", 1, 36, 0.18, color, 0.1)
	local t0 = os.clock()
	local parts: { BasePart } = {}
	local cfs: { CFrame } = {}
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local f = math.clamp((os.clock() - t0) / time, 0, 1)
		if f >= 1 then
			conn:Disconnect()
			holder:Destroy()
			return
		end
		local e = 1 - (1 - f) ^ 3
		local scale = 1 + (toRadius - 1) * e
		ringSize(ring, scale)
		for _, p in ring.parts do
			p.Transparency = 0.1 + 0.9 * f
		end
		table.clear(parts)
		table.clear(cfs)
		placeRing(ring, cf, f * 1.5, scale, parts, cfs)
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end

local function flashBall(pos: Vector3, color: Color3, from: number, to: number, time: number)
	local b = vpart(fxFolder(), "SpinFlash", Vector3.new(from, from, from), color, Enum.Material.Neon, Enum.PartType.Ball, 0.2)
	b.CFrame = CFrame.new(pos)
	TweenService:Create(b, TweenInfo.new(time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(to, to, to), Transparency = 1 }):Play()
	task.delay(time + 0.05, function()
		b:Destroy()
	end)
end

------------------------------------------------------------------------
-- two sparks with light trails spiralling up a body (Fill / Absorb)
------------------------------------------------------------------------

local function spiralSparks(char: Model, duration: number, height0: number, height1: number)
	local torso = char:FindFirstChild("Torso")
	if not (torso and torso:IsA("BasePart")) then
		return
	end
	local sparks = {}
	for i, col in { GOLD, GREEN } do
		local s = vpart(fxFolder(), "SpinSpark", Vector3.new(0.3, 0.3, 0.3), col, Enum.Material.Neon, Enum.PartType.Ball)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.18, 0)
		a0.Parent = s
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.18, 0)
		a1.Parent = s
		local tr = Instance.new("Trail")
		tr.Attachment0 = a0
		tr.Attachment1 = a1
		tr.Lifetime = 0.45
		tr.LightEmission = 1
		tr.Color = ColorSequence.new(col)
		tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
		tr.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
		tr.FaceCamera = true
		tr.Parent = s
		sparks[i] = s
	end
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local f = (os.clock() - t0) / duration
		if f >= 1 or not torso.Parent then
			conn:Disconnect()
			for _, s in sparks do
				s.Transparency = 1
				task.delay(0.5, function()
					s:Destroy()
				end)
			end
			return
		end
		local base = torso.Position
		local h = height0 + (height1 - height0) * f
		local r = 1.7 - 0.6 * math.sin(f * math.pi)
		for i, s in sparks do
			local a = f * math.pi * 2 * 3.2 + (i - 1) * math.pi
			s.CFrame = CFrame.new(base + Vector3.new(math.cos(a) * r, h, math.sin(a) * r))
		end
	end)
end

------------------------------------------------------------------------
-- touching the relic: its light pours into you
------------------------------------------------------------------------

function SpinFX.Absorb(from: Vector3, char: Model)
	local torso = char:FindFirstChild("Torso")
	if not (torso and torso:IsA("BasePart")) then
		return
	end
	local anchor = vpart(fxFolder(), "AbsorbFrom", Vector3.new(0.2, 0.2, 0.2), GOLD, Enum.Material.Neon, nil, 1)
	anchor.CFrame = CFrame.new(from)
	local a0 = Instance.new("Attachment")
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Name = "AbsorbTo"
	a1.Parent = torso
	local beams = {}
	for i = 1, 3 do
		local b = Instance.new("Beam")
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.Texture = SPARKS
		b.TextureMode = Enum.TextureMode.Wrap
		b.TextureLength = 1.6
		b.TextureSpeed = 4 + i
		b.LightEmission = 1
		b.LightInfluence = 0
		b.FaceCamera = true
		b.Segments = 24
		b.CurveSize0 = ({ 3, -3, 0 })[i]
		b.CurveSize1 = ({ -2, 2, 2.5 })[i]
		b.Width0 = 1.1
		b.Width1 = 0.35
		b.Color = ColorSequence.new(i == 2 and GREEN or GOLD, i == 2 and GOLD or GREEN)
		b.Transparency = NumberSequence.new(0.1)
		b.Parent = anchor
		table.insert(beams, b)
	end
	SpinFX.Shock(CFrame.new(from), GOLD, 9, 0.7)
	SpinFX.Shock(CFrame.new(from) * CFrame.Angles(math.rad(90), 0, 0), GREEN, 7, 0.6)
	flashBall(from, GOLD, 1.5, 8, 0.5)
	spiralSparks(char, 1.6, -3, 2.4)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 1.3 do
			local f = (os.clock() - t0) / 1.3
			for _, b in beams do
				b.Transparency = NumberSequence.new(0.1 + 0.9 * f * f)
				b.Width0 = 1.1 * (1 - f)
			end
			RunService.RenderStepped:Wait()
		end
		anchor:Destroy()
		a1:Destroy()
	end)
end

------------------------------------------------------------------------
-- the Spin fills a body (from the feet up)
------------------------------------------------------------------------

local ORDER = {
	{ "Left Leg", 0 },
	{ "Right Leg", 0.12 },
	{ "Torso", 0.6 },
	{ "Left Arm", 1.0 },
	{ "Right Arm", 1.1 },
	{ "Head", 1.55 },
}

function SpinFX.Fill(char: Model)
	if typeof(char) ~= "Instance" or not char:IsA("Model") then
		return
	end
	local torso = char:FindFirstChild("Torso")
	if not (torso and torso:IsA("BasePart")) then
		return
	end
	local holder = Instance.new("Model")
	holder.Name = "SpinFill"
	holder.Parent = fxFolder()
	local shells: { { part: BasePart, shell: BasePart, t: number } } = {}
	for i, o in ORDER do
		local p = char:FindFirstChild(o[1])
		if p and p:IsA("BasePart") then
			local isHead = o[1] == "Head"
			local size = isHead and Vector3.new(1.42, 1.42, 1.42) or (p.Size + Vector3.new(0.14, 0.14, 0.14))
			local col = GREEN:Lerp(GOLD, (i - 1) / (#ORDER - 1))
			local s = vpart(holder, "Shell", size, col, Enum.Material.Neon, isHead and Enum.PartType.Ball or nil, 1)
			table.insert(shells, { part = p, shell = s, t = o[2] })
		end
	end
	local ring = makeRing(holder, "FillRing", 1.6, 22, 0.12, GOLD, 0.1)
	local burst = vpart(holder, "Burst", Vector3.new(0.2, 0.2, 0.2), GOLD, Enum.Material.Neon, nil, 1)
	local sparks = emitter(burst, {
		Name = "Burst",
		Color = ColorSequence.new(GOLD, GREEN),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.5, 1.1),
		Speed = NumberRange.new(10, 22),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 3,
		Rate = 0,
	})
	local rising = emitter(burst, {
		Name = "Rising",
		Color = ColorSequence.new(GREEN, GOLD),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(2, 5),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(35, 35),
		Rate = 60,
	})
	SoundLibrary.Play("spinPower", torso.Position, 0.8, 0.7)
	spiralSparks(char, 2.3, -3, 2.6)
	local FILL, HOLD, FADE = 2.3, 0.4, 1.5
	local t0 = os.clock()
	local bursted = false
	local parts: { BasePart } = {}
	local cfs: { CFrame } = {}
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > FILL + HOLD + FADE or not torso.Parent then
			conn:Disconnect()
			holder:Destroy()
			return
		end
		table.clear(parts)
		table.clear(cfs)
		for _, s in shells do
			if s.part.Parent then
				table.insert(parts, s.shell)
				table.insert(cfs, s.part.CFrame)
				local on = math.clamp((t - s.t) / 0.45, 0, 1)
				local off = t > FILL + HOLD and math.clamp((t - FILL - HOLD) / FADE, 0, 1) or 0
				local flicker = 0.06 * math.sin(t * 22 + s.t * 7)
				s.shell.Transparency = math.clamp(1 - on * 0.55 + flicker + off * 0.55, 0, 1)
			else
				s.shell.Transparency = 1
			end
		end
		-- the ring climbs from the feet to the head while it spins, then widens and fades
		local f = math.clamp(t / FILL, 0, 1)
		local y = -3 + 5.6 * f
		local wide = t > FILL and math.clamp((t - FILL) / 0.5, 0, 1) or 0
		local scale = 1 + wide * 1.8
		ringSize(ring, scale)
		for _, p in ring.parts do
			p.Transparency = 0.1 + 0.9 * wide
		end
		placeRing(ring, CFrame.new(torso.Position + Vector3.new(0, y, 0)), t * 9, scale, parts, cfs)
		table.insert(parts, burst)
		table.insert(cfs, CFrame.new(torso.Position + Vector3.new(0, y - 0.3, 0)))
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		if t > FILL then
			rising.Enabled = false
		end
		if not bursted and t >= FILL then
			bursted = true
			sparks:Emit(70)
			flashBall(torso.Position + Vector3.new(0, 0.6, 0), GREEN, 2, 10, 0.6)
			SpinFX.Shock(CFrame.new(torso.Position - Vector3.new(0, 2.9, 0)), GOLD, 10, 0.8)
			SoundLibrary.Play("spinPower", torso.Position, 1, 1.25)
		end
	end)
end

------------------------------------------------------------------------
-- Spin Circles on the ground
------------------------------------------------------------------------

type Circle = { part: BasePart, model: Model, outer: Ring, inner: Ring, spiral: { { part: BasePart, a: Vector3, b: Vector3 } }, ticks: { { part: BasePart, a: number } }, hum: Sound? }
local circles: { [BasePart]: Circle } = {}

local function buildCircle(part: BasePart)
	if circles[part] then
		return
	end
	local m = Instance.new("Model")
	m.Name = "SpinCircleFX"
	local R = Config.SpinCircleRadius
	local outer = makeRing(m, "Outer", R, 40, 0.12, GOLD)
	local inner = makeRing(m, "Inner", R * 0.76, 32, 0.09, GREEN)
	for _, p in outer.parts do
		p.Size = Vector3.new(0.14, 0.05, p.Size.Z)
	end
	for _, p in inner.parts do
		p.Size = Vector3.new(0.1, 0.05, p.Size.Z)
	end
	-- a golden spiral from the middle out (each turn PHI^4 wider)
	local spiral = {}
	local b = math.log(PHI) / (math.pi / 2)
	local turns = 3.2
	local n = 44
	local maxR = R * 0.68
	local r0 = maxR / math.exp(b * turns * math.pi * 2)
	local prev = nil
	for k = 0, n do
		local th = k / n * turns * math.pi * 2
		local r = r0 * math.exp(b * th)
		local pt = Vector3.new(math.cos(th) * r, 0, math.sin(th) * r)
		if prev then
			local len = (pt - prev).Magnitude
			local seg = vpart(m, "Spiral", Vector3.new(0.07 + 0.05 * k / n, 0.05, len + 0.04), GOLD:Lerp(GREEN, 1 - k / n), Enum.Material.Neon)
			table.insert(spiral, { part = seg, a = prev, b = pt })
		end
		prev = pt
	end
	local ticks = {}
	for i = 1, 12 do
		local t = vpart(m, "Tick", Vector3.new(R * 0.2, 0.05, 0.08), GOLD, Enum.Material.Neon)
		table.insert(ticks, { part = t, a = (i - 1) / 12 * math.pi * 2 })
	end
	local glow = vpart(m, "Glow", Vector3.new(R * 2, 0.06, R * 2), GREEN, Enum.Material.Neon, Enum.PartType.Cylinder, 0.9)
	glow.Size = Vector3.new(0.06, R * 2, R * 2)
	local light = Instance.new("PointLight")
	light.Color = GREEN
	light.Range = 12
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = glow
	emitter(glow, {
		Name = "Rising",
		Color = ColorSequence.new(GREEN, GOLD),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.2, 2.2),
		Speed = NumberRange.new(1.5, 3.5),
		EmissionDirection = Enum.NormalId.Right, -- (the disc is a cylinder lying on its side: +X is up)
		SpreadAngle = Vector2.new(12, 12),
		Rate = 18,
	})
	m.Parent = fxFolder()
	local hum = SoundLibrary.Loop("relicHum", glow)
	if hum then
		hum.Volume = 0.3
		hum.RollOffMaxDistance = 45
		hum:Play()
	end
	circles[part] = { part = part, model = m, outer = outer, inner = inner, spiral = spiral, ticks = ticks, hum = hum }
end

local function removeCircle(part: BasePart)
	local c = circles[part]
	if c then
		circles[part] = nil
		c.model:Destroy()
	end
end

local cparts: { BasePart } = {}
local ccfs: { CFrame } = {}
local function stepCircles(now: number)
	for part, c in circles do
		if not part.Parent then
			removeCircle(part)
			continue
		end
		table.clear(cparts)
		table.clear(ccfs)
		local base = CFrame.new(part.Position + Vector3.new(0, 0.05, 0))
		placeRing(c.outer, base, now * 0.25, 1, cparts, ccfs)
		placeRing(c.inner, base, -now * 0.4, 1, cparts, ccfs)
		local rot = base * CFrame.Angles(0, now * 0.6, 0)
		for _, s in c.spiral do
			local mid = (s.a + s.b) / 2
			table.insert(cparts, s.part)
			table.insert(ccfs, rot * CFrame.lookAt(mid, s.b))
		end
		local R = Config.SpinCircleRadius
		for _, t in c.ticks do
			table.insert(cparts, t.part)
			table.insert(ccfs, base * CFrame.Angles(0, t.a + now * 0.25, 0) * CFrame.new(R * 0.88, 0, 0))
		end
		local glow = c.model:FindFirstChild("Glow")
		if glow and glow:IsA("BasePart") then
			table.insert(cparts, glow)
			table.insert(ccfs, base * CFrame.Angles(0, 0, math.rad(90)))
			glow.Transparency = 0.88 + math.sin(now * 2.4) * 0.04
		end
		workspace:BulkMoveTo(cparts, ccfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function SpinFX.Init()
	local function consider(d: Instance)
		if d:IsA("BasePart") and d.Name == "SpinCircle" and d:GetAttribute("SpinCircle") then
			buildCircle(d)
		end
	end
	for _, d in workspace:GetChildren() do
		consider(d)
	end
	workspace.ChildAdded:Connect(function(d)
		task.defer(consider, d)
	end)
	workspace.ChildRemoved:Connect(function(d)
		if d:IsA("BasePart") then
			removeCircle(d)
		end
	end)
	RunService.RenderStepped:Connect(function()
		stepCircles(os.clock())
	end)
end

return SpinFX
