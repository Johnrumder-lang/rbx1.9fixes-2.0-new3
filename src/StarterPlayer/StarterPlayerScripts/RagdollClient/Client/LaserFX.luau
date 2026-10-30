--!nonstrict
-- LaserFX: draws the laser eyes of every flying owner (two red beams from the eyes to the point
-- they burn, a glowing spot and sparks there). Your own beams follow your crosshair right away;
-- other players' beams come from the "LaserEyes" attribute the server keeps on their body.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LaserFX = {}

local player = Players.LocalPlayer
local controller = nil
local folder: Instance = workspace

type Rig = { beams: { BasePart }, glows: { BasePart }, spot: BasePart, halo: BasePart, sparks: ParticleEmitter, smoke: ParticleEmitter, light: PointLight, eyeLights: { PointLight }, hum: Sound? }
local rigs: { [Model]: Rig } = {}

local SoundLibrary = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("SoundLibrary"))

local RED = Color3.fromRGB(255, 30, 20)
local HOT = Color3.fromRGB(255, 225, 200)

local function newPart(name: string, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = folder
	return p
end

-- (v2.0) the beams are seen now: a white-hot core in a thick red glow, light at the eyes, and where they burn a
-- blinding spot in a halo, sparks, smoke, and the hum
local function makeRig(head: BasePart): Rig
	local beams, glows = {}, {}
	for i = 1, 2 do
		local b = newPart("LaserBeam", Vector3.new(0.22, 0.22, 1), HOT)
		b.Shape = Enum.PartType.Cylinder
		b.Transparency = 0
		beams[i] = b
		local g = newPart("LaserGlow", Vector3.new(1, 0.75, 0.75), RED)
		g.Shape = Enum.PartType.Cylinder
		g.Transparency = 0.45
		glows[i] = g
	end
	local spot = newPart("LaserSpot", Vector3.new(1.4, 1.4, 1.4), HOT)
	spot.Shape = Enum.PartType.Ball
	spot.Transparency = 0
	local halo = newPart("LaserHalo", Vector3.new(4, 4, 4), RED)
	halo.Shape = Enum.PartType.Ball
	halo.Transparency = 0.6
	local light = Instance.new("PointLight")
	light.Color = RED
	light.Range = 22
	light.Brightness = 6
	light.Parent = spot
	local att = Instance.new("Attachment")
	att.Parent = spot
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Rate = 140
	sparks.Lifetime = NumberRange.new(0.25, 0.6)
	sparks.Speed = NumberRange.new(14, 30)
	sparks.SpreadAngle = Vector2.new(80, 80)
	sparks.Acceleration = Vector3.new(0, -50, 0)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.35, 0)
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), RED)
	sparks.Parent = att
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Rate = 26
	smoke.Lifetime = NumberRange.new(0.8, 1.6)
	smoke.Speed = NumberRange.new(3, 7)
	smoke.SpreadAngle = Vector2.new(30, 30)
	smoke.Acceleration = Vector3.new(0, 6, 0)
	smoke.Drag = 2
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 4) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	smoke.Color = ColorSequence.new(Color3.fromRGB(60, 50, 48))
	smoke.RotSpeed = NumberRange.new(-80, 80)
	smoke.LightInfluence = 1
	smoke.Parent = att
	local eyeLights = {}
	for _ = 1, 1 do
		local l = Instance.new("PointLight")
		l.Name = "LaserEyesLight"
		l.Color = RED
		l.Range = 10
		l.Brightness = 4
		l.Parent = head
		table.insert(eyeLights, l)
	end
	local hum = SoundLibrary.Loop("laserHum", head)
	if hum then
		hum.Volume = 0.55
		hum:Play()
	end
	return { beams = beams, glows = glows, spot = spot, halo = halo, sparks = sparks, smoke = smoke, light = light, eyeLights = eyeLights, hum = hum }
end

local function dropRig(m: Model)
	local r = rigs[m]
	rigs[m] = nil
	if r then
		for _, b in r.beams do
			b:Destroy()
		end
		for _, g in r.glows do
			g:Destroy()
		end
		for _, l in r.eyeLights do
			l:Destroy()
		end
		if r.hum then
			r.hum:Destroy()
		end
		r.halo:Destroy()
		-- the spot cools off (its smoke drifts away)
		r.sparks.Enabled = false
		r.smoke.Enabled = false
		r.spot.Transparency = 1
		local spot = r.spot
		task.delay(1.6, function()
			spot:Destroy()
		end)
	end
end

local function step()
	local seen = {}
	local t = os.clock()
	for _, p in Players:GetPlayers() do
		local char = p.Character
		if not char then
			continue
		end
		local target = nil
		if p == player then
			target = controller and controller.laserTarget or nil
		else
			local a = char:GetAttribute("LaserEyes")
			target = typeof(a) == "Vector3" and a or nil
		end
		local head = char:FindFirstChild("Head")
		if not target or not head or not head:IsA("BasePart") then
			continue
		end
		seen[char] = true
		local r = rigs[char]
		if not r then
			r = makeRig(head)
			rigs[char] = r
		end
		local flicker = 0.85 + math.random() * 0.3
		local pulse = 1 + math.sin(t * 38) * 0.12
		for i, side in { -1, 1 } do
			local eye = head.CFrame:PointToWorldSpace(Vector3.new(side * 0.22, 0.2, -0.5))
			local len = math.max((target - eye).Magnitude, 0.1)
			local cf = CFrame.lookAt((eye + target) * 0.5, target) * CFrame.Angles(0, math.rad(90), 0)
			local b = r.beams[i]
			b.Size = Vector3.new(len, 0.22 * flicker, 0.22 * flicker)
			b.CFrame = cf
			local g = r.glows[i]
			g.Size = Vector3.new(len, 0.8 * pulse, 0.8 * pulse)
			g.CFrame = cf
			g.Transparency = 0.4 + math.random() * 0.15
		end
		r.spot.CFrame = CFrame.new(target)
		r.spot.Size = Vector3.one * (1.1 + math.random() * 0.6)
		r.halo.CFrame = CFrame.new(target)
		r.halo.Size = Vector3.one * (3.4 + math.random() * 1.6) * pulse
		r.light.Brightness = 5 + math.random() * 3
		if r.hum then
			r.hum.PlaybackSpeed = (r.hum:GetAttribute("BaseSpeed") or 1.7) * (0.97 + math.random() * 0.06)
		end
	end
	for m in rigs do
		if not seen[m] then
			dropRig(m)
		end
	end
end

function LaserFX.SetController(c)
	controller = c
end

function LaserFX.Init(fxFolder: Instance?)
	folder = fxFolder or workspace:FindFirstChild("FX") or workspace
	RunService.RenderStepped:Connect(step)
end

return LaserFX
