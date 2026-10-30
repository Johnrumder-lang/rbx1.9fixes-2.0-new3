--!nonstrict
-- SuperFX (v2.0): what everybody sees of the admins' super powers (SuperService on the server).
--   timestop : the colours drain away from the one who stopped time outwards; everything stands still
--   hotdog   : the giant hotdog hovers and shakes, then races round the map faster and faster (MACH counter, sonic
--              booms, a fire trail that becomes a ring, the tornado wall). The one on it rides it; everybody else
--              is pulled into the tornado by their own client (it owns their body).
--   sun      : the cannons glow and hum while charging, then a giant beam goes into the sun, the sun swells and
--              the sky burns; the supernova turns the whole screen white

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local HotdogPath = require(Shared:WaitForChild("HotdogPath"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))

local Events = require(script.Parent:WaitForChild("Events"))
local UI = require(script.Parent:WaitForChild("UI"))
local Cam = require(script.Parent:WaitForChild("CameraController"))

local player = Players.LocalPlayer
local SuperFX = {}

local controller = nil
local folder: Folder
local gui: ScreenGui
local white: Frame
local machLabel: TextLabel

function SuperFX.SetController(c)
	controller = c
end

local function part(name: string, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function now(): number
	return workspace:GetServerTimeNow()
end

------------------------------------------------------------------------
-- time stop
------------------------------------------------------------------------

local stopCC: ColorCorrectionEffect? = nil

local function timeStop(payload)
	if payload.style == "still" then
		return -- (v2.8) STILL CUT draws its own blue stillness (SwordClient)
	end
	if payload.on then
		SoundLibrary.Play("timeStop", nil, 1)
		local cc = stopCC
		if not cc then
			cc = Instance.new("ColorCorrectionEffect")
			cc.Name = "TimeStop"
			cc.Parent = Lighting
			stopCC = cc
		end
		cc.Enabled = true
		cc.Saturation = 0
		cc.Contrast = 0
		cc.TintColor = Color3.new(1, 1, 1)
		-- first everything flashes inverted-looking, then the colour drains
		cc.Contrast = 0.6
		cc.TintColor = Color3.fromRGB(200, 170, 255)
		TweenService:Create(cc, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Saturation = -1, Contrast = 0.18, TintColor = Color3.fromRGB(215, 225, 255) }):Play()
		-- the sphere of stopped time grows out of the admin
		local center = typeof(payload.p) == "Vector3" and payload.p or Vector3.zero
		local s = part("TimeSphere", Vector3.new(2, 2, 2), Color3.fromRGB(150, 120, 255), Enum.Material.ForceField, Enum.PartType.Ball)
		s.Transparency = 0.2
		s.CFrame = CFrame.new(center)
		s.Parent = folder
		local grow = TweenService:Create(s, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(700, 700, 700), Transparency = 1 })
		grow:Play()
		Debris:AddItem(s, 1.3)
		Cam.Shake(0.8)
	else
		SoundLibrary.Play("timeStop", nil, 0.8, 1.5)
		local cc = stopCC
		if cc then
			local tw = TweenService:Create(cc, TweenInfo.new(0.8), { Saturation = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) })
			tw:Play()
			tw.Completed:Connect(function()
				if not workspace:GetAttribute("TimeStop") then
					cc.Enabled = false
				end
			end)
		end
	end
end

------------------------------------------------------------------------
-- hotdog
------------------------------------------------------------------------

-- (v2.0) a proper hotdog: a glossy sausage with grill marks and round ends in a soft bun (crust outside, crumb
-- inside, round ends), mustard and ketchup in zigzags, onions and relish on top. Everything but the sausage sits at
-- its "Off" from it (placeHotdog). Its length is along X.
local function buildHotdog(): Model
	local m = Instance.new("Model")
	m.Name = "Hotdog"
	local SAUS = Color3.fromRGB(170, 66, 42)
	local SAUS_DARK = Color3.fromRGB(96, 36, 24)
	local CRUST = Color3.fromRGB(196, 128, 62)
	local CRUST_DARK = Color3.fromRGB(160, 96, 44)
	local CRUMB = Color3.fromRGB(242, 214, 160)
	local SP = Enum.Material.SmoothPlastic
	local CYL = Enum.PartType.Cylinder
	local root = part("Sausage", Vector3.new(16, 3.2, 3.2), SAUS, SP, CYL)
	root.Reflectance = 0.18
	root.Parent = m
	local function add(name: string, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): Part
		local p = part(name, size, color, mat or SP, shape)
		p:SetAttribute("Off", off)
		p.Parent = m
		return p
	end
	for _, x in { -8, 8 } do
		add("SausageEnd", Vector3.new(3.2, 3.2, 3.2), CFrame.new(x, 0, 0), SAUS, SP, Enum.PartType.Ball).Reflectance = 0.18
		add("SausageTwist", Vector3.new(0.4, 1.2, 1.2), CFrame.new(x + (x > 0 and 1.65 or -1.65), 0, 0), SAUS_DARK, SP, CYL)
	end
	for i = -3, 3 do
		-- grill marks: dark slanted stripes over the top and down the sides
		for _, side in { -1, 0, 1 } do
			local ang = side * math.rad(48)
			add("Grill", Vector3.new(0.22, 0.08, 1.3), CFrame.new(i * 2.0 + 0.5, 0, 0) * CFrame.Angles(ang, 0, 0) * CFrame.new(0, 1.58, 0) * CFrame.Angles(0, 0.7, 0), SAUS_DARK)
		end
	end
	-- the bun: a crusty base, two rounded sides with crumb on the inside, round ends
	add("BunBase", Vector3.new(15.6, 1.3, 4.4), CFrame.new(0, -1.85, 0), CRUST_DARK)
	for _, z in { -1, 1 } do
		add("BunSide", Vector3.new(15.6, 2.7, 2.7), CFrame.new(0, -0.75, z * 2.05), CRUST, SP, CYL)
		add("BunCrumb", Vector3.new(15.4, 1.6, 0.25), CFrame.new(0, -0.55, z * 1.62), CRUMB)
		add("BunTop", Vector3.new(15.2, 0.25, 1.1), CFrame.new(0, 0.55, z * 1.95), CRUMB)
		for _, x in { -7.8, 7.8 } do
			add("BunEnd", Vector3.new(2.7, 2.7, 2.7), CFrame.new(x, -0.75, z * 2.05), CRUST, SP, Enum.PartType.Ball)
		end
	end
	for _, x in { -7.8, 7.8 } do
		add("BunBaseEnd", Vector3.new(1.3, 4.4, 4.4), CFrame.new(x, -1.85, 0) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, 0, 0), CRUST_DARK, SP, CYL)
	end
	-- mustard and ketchup zigzags (round strands), onions and relish
	local function zigzag(name: string, color: Color3, y: number, phase: number, w: number)
		local n = 12
		local prev: Vector3? = nil
		for i = 0, n do
			local x = -7 + i * (14 / n)
			local z = ((i + phase) % 2 == 0) and w or -w
			local pt = Vector3.new(x, y, z)
			if prev then
				local mid = (prev + pt) / 2
				local len = (pt - prev).Magnitude
				add(name, Vector3.new(len + 0.25, 0.42, 0.42), CFrame.lookAt(mid, pt) * CFrame.Angles(0, math.rad(90), 0), color, SP, CYL).Reflectance = 0.12
			end
			prev = pt
		end
	end
	zigzag("Mustard", Color3.fromRGB(250, 208, 30), 1.68, 0, 0.75)
	zigzag("Ketchup", Color3.fromRGB(200, 30, 30), 1.6, 1, 0.55)
	local rng = Random.new(7)
	for i = 1, 14 do
		add(i % 2 == 0 and "Onion" or "Relish", Vector3.new(0.32, 0.18, 0.32), CFrame.new(rng:NextNumber(-6.5, 6.5), 1.62, rng:NextNumber(-0.7, 0.7)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
			i % 2 == 0 and Color3.fromRGB(246, 242, 228) or Color3.fromRGB(80, 160, 60))
	end
	-- fire trail (becomes a burning ring at speed)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1.6, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1.6, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "Trail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.9
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 80, 30))
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.WidthScale = NumberSequence.new(1.5, 4)
	trail.Enabled = false
	trail.Parent = root
	local fire = Instance.new("Fire")
	fire.Size = 10
	fire.Heat = 0
	fire.Enabled = false
	fire.Parent = root
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 80)
	light.Range = 40
	light.Brightness = 0
	light.Parent = root
	m.PrimaryPart = root
	return m
end

-- (v2.0) the tornado round the hotdog's circle: stacked shimmering walls that widen to the top and turn at their own
-- speeds, wobbling; dust, debris and streaks of wind whirling round it; a skirt of dust at its foot
type Tornado = { Step: (Tornado, number, number) -> (), Destroy: (Tornado) -> () }
local function buildTornado(info: any, parent: Instance): Tornado
	local holder = Instance.new("Model")
	holder.Name = "Tornado"
	holder.Parent = parent
	local R = info.radius * 1.1
	local c = info.center
	local layers = {}
	for i = 0, 6 do
		local fr = i / 6
		local r = R * (0.84 + 0.34 * fr)
		local col = Color3.fromRGB(196, 192, 184):Lerp(Color3.fromRGB(150, 138, 120), (i % 2) * 0.7)
		local p = part("TornadoWall", Vector3.new(26, r * 2, r * 2), col, Enum.Material.ForceField, Enum.PartType.Cylinder)
		p.Transparency = 1
		p.Parent = holder
		table.insert(layers, { p = p, y = 11 + i * 22, speed = 2.0 + fr * 1.8, wob = r * 0.025, ph = i * 0.9 })
	end
	local rng = Random.new()
	local spinners = {}
	for k = 1, 30 do
		local s = part("TornadoSpin", Vector3.new(1, 1, 1), Color3.new(1, 1, 1))
		s.Transparency = 1
		s.Parent = holder
		local dust = Instance.new("ParticleEmitter")
		dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
		dust.Color = ColorSequence.new(Color3.fromRGB(176, 166, 150), Color3.fromRGB(120, 112, 100))
		dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 8), NumberSequenceKeypoint.new(1, 22) })
		dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.55), NumberSequenceKeypoint.new(1, 1) })
		dust.Lifetime = NumberRange.new(1.4, 2.4)
		dust.Speed = NumberRange.new(0, 4)
		dust.RotSpeed = NumberRange.new(-90, 90)
		dust.Rate = 0
		dust.Parent = s
		local bits = Instance.new("ParticleEmitter")
		bits.Color = ColorSequence.new(Color3.fromRGB(90, 72, 54), Color3.fromRGB(60, 60, 60))
		bits.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.3) })
		bits.Lifetime = NumberRange.new(0.6, 1.2)
		bits.Speed = NumberRange.new(4, 10)
		bits.SpreadAngle = Vector2.new(180, 180)
		bits.RotSpeed = NumberRange.new(-400, 400)
		bits.LightInfluence = 1
		bits.Rate = 0
		bits.Parent = s
		local t0 = Instance.new("Attachment")
		t0.Position = Vector3.new(0, 1.5, 0)
		t0.Parent = s
		local t1 = Instance.new("Attachment")
		t1.Position = Vector3.new(0, -1.5, 0)
		t1.Parent = s
		local tr = Instance.new("Trail")
		tr.Attachment0 = t0
		tr.Attachment1 = t1
		tr.Lifetime = 0.5
		tr.Color = ColorSequence.new(Color3.fromRGB(235, 235, 240))
		tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		tr.LightInfluence = 1
		tr.Enabled = false
		tr.Parent = s
		local h = rng:NextNumber(0, 150)
		table.insert(spinners, { p = s, dust = dust, bits = bits, trail = tr, h = h, a0 = rng:NextNumber(0, math.pi * 2), r = R * (0.84 + 0.34 * h / 150) * rng:NextNumber(0.92, 1.08), speed = rng:NextNumber(1.6, 3.0) })
	end
	local skirt = {}
	for k = 1, 16 do
		local a = (k - 1) / 16 * math.pi * 2
		local s = part("TornadoSkirt", Vector3.new(R * 0.4, 2, 6), Color3.new(1, 1, 1))
		s.Transparency = 1
		s.CFrame = CFrame.new(c + Vector3.new(math.cos(a) * R * 0.86, 1, math.sin(a) * R * 0.86)) * CFrame.Angles(0, -a, 0)
		s.Parent = holder
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(184, 172, 150))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 10), NumberSequenceKeypoint.new(1, 30) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(2, 3.5)
		e.Speed = NumberRange.new(6, 14)
		e.SpreadAngle = Vector2.new(40, 40)
		e.EmissionDirection = Enum.NormalId.Top
		e.Rate = 0
		e.Parent = s
		table.insert(skirt, e)
	end
	local self: any = {}
	local parts: { BasePart } = {}
	local cfs: { CFrame } = {}
	function self.Step(_s, t: number, pull: number)
		table.clear(parts)
		table.clear(cfs)
		for _, L in layers do
			table.insert(parts, L.p)
			table.insert(cfs, CFrame.new(c + Vector3.new(math.sin(t * 0.7 + L.ph) * L.wob, L.y, math.cos(t * 0.6 + L.ph) * L.wob))
				* CFrame.Angles(0, t * L.speed, 0) * CFrame.Angles(0, 0, math.rad(90)))
			L.p.Transparency = 1 - pull * 0.6
		end
		for _, s in spinners do
			local a = s.a0 + t * s.speed * (0.6 + pull)
			local y = s.h + math.sin(t * 1.3 + s.a0) * 6
			table.insert(parts, s.p)
			table.insert(cfs, CFrame.new(c + Vector3.new(math.cos(a) * s.r, y, math.sin(a) * s.r)))
			s.dust.Rate = pull * 6
			s.bits.Rate = pull * 10
			s.trail.Enabled = pull > 0.15
		end
		for _, e in skirt do
			e.Rate = pull * 5
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	function self.Destroy(_s)
		holder:Destroy()
	end
	return self :: Tornado
end

local function placeHotdog(m: Model, cf: CFrame)
	local root = m.PrimaryPart
	local parts, cfs = {}, {}
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") then
			local off = p:GetAttribute("Off")
			table.insert(parts, p)
			table.insert(cfs, p == root and cf or cf * (typeof(off) == "CFrame" and off or CFrame.identity))
		end
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	if root then
		root.CFrame = cf
	end
end

local hotdogConn: RBXScriptConnection? = nil

local function hotdog(payload)
	if hotdogConn then
		hotdogConn:Disconnect()
		hotdogConn = nil
	end
	local old = folder:FindFirstChild("Hotdog")
	if old then
		old:Destroy()
	end
	local info = { start = payload.start, center = payload.center, radius = payload.radius, height = payload.height }
	if typeof(info.start) ~= "Vector3" or typeof(info.center) ~= "Vector3" then
		return
	end
	local t0 = typeof(payload.t0) == "number" and payload.t0 or now()
	local mine = payload.target == player.UserId
	local m = buildHotdog()
	m.Parent = folder
	local root = m.PrimaryPart :: BasePart
	local trail = root:FindFirstChild("Trail") :: Trail
	local fire = root:FindFirstChildOfClass("Fire") :: Fire
	local light = root:FindFirstChildOfClass("PointLight") :: PointLight
	local hum = SoundLibrary.Loop("hotdogCharge", root)
	if hum then
		hum.Volume = 0.8
		hum:Play()
	end
	-- the tornado (v2.0: a real funnel of wind round the circle)
	local tornado = buildTornado(info, m)
	local booms = { 1, 5, 10, 20, 30 }
	local nextBoom = 1
	local total = Config.HotdogCharge + Config.HotdogFlight
	local paused = 0
	local lastWall = 0
	hotdogConn = RunService.RenderStepped:Connect(function(dt)
		if workspace:GetAttribute("TimeStop") then
			paused += dt
			return
		end
		local t = now() - t0 - paused
		if t > total + 0.5 or not m.Parent then
			if hotdogConn then
				hotdogConn:Disconnect()
				hotdogConn = nil
			end
			machLabel.Visible = false
			if m.Parent then
				m:Destroy()
			end
			return
		end
		local pos, fwd = HotdogPath.At(info, t)
		local spin = t > Config.HotdogCharge and CFrame.Angles(t * 9, 0, 0) or CFrame.identity
		placeHotdog(m, CFrame.lookAt(pos, pos + fwd) * CFrame.Angles(0, math.rad(90), 0) * spin)
		local mach = HotdogPath.Mach(t)
		local flying = t > Config.HotdogCharge
		trail.Enabled = flying
		fire.Enabled = flying
		light.Brightness = flying and 4 or math.clamp(t / Config.HotdogCharge, 0, 1) * 3
		if hum then
			hum.PlaybackSpeed = 0.5 + math.clamp(t / total, 0, 1) * 2.2
		end
		machLabel.Visible = flying
		machLabel.Text = string.format("MACH %.1f", mach)
		if flying and nextBoom <= #booms and mach >= booms[nextBoom] then
			nextBoom += 1
			SoundLibrary.Play("sonicBoom", nil, 1)
			Cam.Shake(0.7)
			local ring = part("Boom", Vector3.new(0.5, 6, 6), Color3.new(1, 1, 1), Enum.Material.ForceField, Enum.PartType.Cylinder)
			ring.CFrame = CFrame.lookAt(pos, pos + fwd) * CFrame.Angles(0, math.rad(90), 0)
			ring.Parent = folder
			TweenService:Create(ring, TweenInfo.new(0.6), { Size = Vector3.new(0.5, 90, 90), Transparency = 1 }):Play()
			Debris:AddItem(ring, 0.7)
		end
		local pull = HotdogPath.Pull(t)
		if now() - lastWall > 0.03 then
			lastWall = now()
			tornado:Step(t, pull)
		end
		-- my own body
		local c = controller
		local char = player.Character
		local torso = char and char:FindFirstChild("Torso")
		if not c or not c.ready or c.dead or not torso or not torso:IsA("BasePart") then
			return
		end
		if mine then
			-- riding the hotdog, lying on the sausage
			if c.state ~= "Ragdoll" then
				c:Ragdoll(1)
			end
			c.ragdollTimer = math.max(c.ragdollTimer or 0, 0.5)
			local seat = CFrame.lookAt(pos, pos + fwd) * CFrame.new(0, 3.2, 0) * CFrame.Angles(math.rad(-90), 0, 0)
			pcall(function()
				torso.CFrame = seat
				local v = fwd * math.min(HotdogPath.Speed(t), 300)
				for _, p in char:GetChildren() do
					if p:IsA("BasePart") then
						p.AssemblyLinearVelocity = v
					end
				end
			end)
			Cam.Shake(flying and 0.4 or 0.15)
		elseif pull > 0 and not player:GetAttribute("InLobby") then
			local wind = HotdogPath.Wind(info, t, torso.Position)
			if pull > 0.3 and c.state ~= "Ragdoll" and not c.flying then
				c:Ragdoll(1.5)
			end
			if not c.flying then
				local k = math.clamp(pull * dt * 2.5, 0, 1)
				pcall(function()
					for _, p in char:GetChildren() do
						if p:IsA("BasePart") then
							p.AssemblyLinearVelocity = p.AssemblyLinearVelocity:Lerp(wind, k)
						end
					end
				end)
			end
		end
	end)
end

------------------------------------------------------------------------
-- sun cannon
------------------------------------------------------------------------

local sunSaved: { [string]: any }? = nil
local sunConn: RBXScriptConnection? = nil

local function skyOf(): Sky
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		local s = Instance.new("Sky")
		s.Name = "SunCannonSky"
		s.Parent = Lighting
		sky = s
	end
	return sky :: Sky
end

local function sunCharge(payload)
	local list = typeof(payload.cannons) == "table" and payload.cannons or {}
	local charge = typeof(payload.charge) == "number" and payload.charge or Config.SunCharge
	for _, m in list do
		if typeof(m) == "Instance" and m:IsA("Model") then
			local lens = m:FindFirstChild("Lens")
			if lens and lens:IsA("BasePart") then
				local light = Instance.new("PointLight")
				light.Color = Color3.fromRGB(255, 220, 140)
				light.Range = 8
				light.Brightness = 0
				light.Parent = lens
				TweenService:Create(light, TweenInfo.new(charge, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Range = 60, Brightness = 12 }):Play()
				Debris:AddItem(light, charge + Config.SunExpand + 2)
				local sp = Instance.new("Sparkles")
				sp.SparkleColor = Color3.fromRGB(255, 200, 90)
				sp.Parent = lens
				Debris:AddItem(sp, charge)
				-- (v2.0) the hum climbs for the whole charge, a crackle grows in it
				local hum = SoundLibrary.Loop("sunCharge", lens)
				if hum then
					hum.Volume = 0.5
					hum:Play()
					local base = hum:GetAttribute("BaseSpeed") or 0.22
					TweenService:Create(hum, TweenInfo.new(charge, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { PlaybackSpeed = base * 5, Volume = 1 }):Play()
					Debris:AddItem(hum, charge + 0.2)
				end
				local crackle = SoundLibrary.Loop("sunCrackle", lens)
				if crackle then
					crackle.Volume = 0
					crackle:Play()
					TweenService:Create(crackle, TweenInfo.new(charge, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Volume = 0.6 }):Play()
					Debris:AddItem(crackle, charge + 0.2)
				end
				-- light pulled in from all around into the lens
				local well = part("SunWell", Vector3.new(26, 26, 26), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
				well.Transparency = 1
				well.CFrame = lens.CFrame
				well.Parent = folder
				local pull = Instance.new("ParticleEmitter")
				pull.Shape = Enum.ParticleEmitterShape.Sphere
				pull.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
				pull.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
				pull.Rate = 30
				pull.Speed = NumberRange.new(10, 14)
				pull.Lifetime = NumberRange.new(0.9, 1.1)
				pull.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.05) })
				pull.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.1), NumberSequenceKeypoint.new(1, 0) })
				pull.Color = ColorSequence.new(Color3.fromRGB(255, 240, 190), Color3.fromRGB(255, 170, 60))
				pull.LightEmission = 1
				pull.LightInfluence = 0
				pull.Parent = well
				TweenService:Create(pull, TweenInfo.new(charge, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Rate = 260 }):Play()
				Debris:AddItem(well, charge + 0.3)
			end
			-- (v2.0) the coils and the capacitors fill up: orange to white-hot, the core in the plinth throbs, and
			-- lightning jumps between the three prongs at the muzzle more and more often
			for _, p in m:GetChildren() do
				if p:IsA("BasePart") and (p.Name == "Coil" or p.Name == "Capacitor" or p.Name == "CoreGlow" or p.Name == "ProngTip") then
					local was = p.Color
					TweenService:Create(p, TweenInfo.new(charge, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Color = Color3.fromRGB(255, 252, 235), Transparency = 0 }):Play()
					task.delay(charge + Config.SunExpand + 1, function()
						if p.Parent then
							p.Color = was
						end
					end)
				end
			end
			local tips = {}
			for _, p in m:GetChildren() do
				if p:IsA("BasePart") and p.Name == "ProngTip" then
					table.insert(tips, p)
				end
			end
			if #tips >= 2 then
				task.spawn(function()
					local tEnd = os.clock() + charge
					while os.clock() < tEnd and m.Parent do
						local k = 1 - (tEnd - os.clock()) / charge
						if math.random() < 0.15 + k * 0.8 then
							local a = tips[math.random(1, #tips)]
							local b = tips[math.random(1, #tips)]
							if a ~= b then
								local a0 = Instance.new("Attachment")
								a0.Parent = a
								local a1 = Instance.new("Attachment")
								a1.Parent = b
								local arc = Instance.new("Beam")
								arc.Attachment0 = a0
								arc.Attachment1 = a1
								arc.LightEmission = 1
								arc.LightInfluence = 0
								arc.FaceCamera = true
								arc.Segments = 12
								arc.CurveSize0 = math.random(-3, 3)
								arc.CurveSize1 = math.random(-3, 3)
								arc.Width0 = 0.18
								arc.Width1 = 0.18
								arc.Color = ColorSequence.new(Color3.fromRGB(255, 250, 220), Color3.fromRGB(255, 190, 90))
								arc.Parent = a
								Debris:AddItem(a0, 0.09)
								Debris:AddItem(a1, 0.09)
								Debris:AddItem(arc, 0.09)
							end
						end
						task.wait(0.06)
					end
				end)
			end
		end
	end
	task.spawn(function()
		local tEnd = os.clock() + charge
		while os.clock() < tEnd do
			local k = 1 - (tEnd - os.clock()) / charge
			Cam.Shake(0.05 + k * 0.35)
			task.wait(0.25)
		end
	end)
end

local function sunBeam(payload)
	local beams = typeof(payload.beams) == "table" and payload.beams or {}
	local dur = typeof(payload.d) == "number" and payload.d or Config.SunExpand
	-- (v2.0) the shot (a giant blast), then the beam roars and the sun throbs for as long as it lasts
	SoundLibrary.Play("sunFire", nil, 1)
	for _, name in { "sunBeam", "sunThrob" } do
		local l = SoundLibrary.Loop(name, game:GetService("SoundService"))
		if l then
			l.Volume = name == "sunBeam" and 1 or 0.7
			l:Play()
			task.delay(dur, function()
				for i = 1, 10 do
					if not l.Parent then
						return
					end
					l.Volume *= 0.7
					task.wait(0.05)
				end
				l:Destroy()
			end)
		end
	end
	for _, b in beams do
		if typeof(b) == "table" and typeof(b.from) == "Vector3" and typeof(b.dir) == "Vector3" then
			local len = 6000
			local core = part("SunBeam", Vector3.new(len, Config.SunBeamRadius * 2, Config.SunBeamRadius * 2), Color3.fromRGB(255, 252, 238), Enum.Material.Neon, Enum.PartType.Cylinder)
			core.CFrame = CFrame.lookAt(b.from + b.dir * len * 0.5, b.from + b.dir * len) * CFrame.Angles(0, math.rad(90), 0)
			core.Parent = folder
			local glow = part("SunGlow", Vector3.new(len, Config.SunBeamRadius * 4, Config.SunBeamRadius * 4), Color3.fromRGB(255, 190, 80), Enum.Material.Neon, Enum.PartType.Cylinder)
			glow.Transparency = 0.7
			glow.CFrame = core.CFrame
			glow.Parent = folder
			Debris:AddItem(core, dur + 1)
			Debris:AddItem(glow, dur + 1)
			-- (v2.0) a yellow layer between the white core and the orange glow, a faint haze round it all
			local mid = part("SunGlow", Vector3.new(len, Config.SunBeamRadius * 2.8, Config.SunBeamRadius * 2.8), Color3.fromRGB(255, 226, 120), Enum.Material.Neon, Enum.PartType.Cylinder)
			mid.Transparency = 0.45
			mid.CFrame = core.CFrame
			mid.Parent = folder
			local haze = part("SunGlow", Vector3.new(len, Config.SunBeamRadius * 7, Config.SunBeamRadius * 7), Color3.fromRGB(255, 150, 60), Enum.Material.Neon, Enum.PartType.Cylinder)
			haze.Transparency = 0.9
			haze.CFrame = core.CFrame
			haze.Parent = folder
			Debris:AddItem(mid, dur + 1)
			Debris:AddItem(haze, dur + 1)
			-- the blast at the muzzle: a flash, a shock ring, sparks and smoke pouring off the lens for as long as it fires
			local flash = part("SunFlash", Vector3.new(4, 4, 4), Color3.fromRGB(255, 250, 230), Enum.Material.Neon, Enum.PartType.Ball)
			flash.CFrame = CFrame.new(b.from)
			flash.Parent = folder
			TweenService:Create(flash, TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(40, 40, 40), Transparency = 1 }):Play()
			Debris:AddItem(flash, 0.8)
			local shock = part("SunShock", Vector3.new(0.6, 6, 6), Color3.fromRGB(255, 230, 170), Enum.Material.Neon, Enum.PartType.Cylinder)
			shock.CFrame = CFrame.lookAt(b.from, b.from + b.dir) * CFrame.Angles(0, math.rad(90), 0)
			shock.Transparency = 0.2
			shock.Parent = folder
			TweenService:Create(shock, TweenInfo.new(0.9, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(0.6, 120, 120), Transparency = 1 }):Play()
			Debris:AddItem(shock, 1)
			local foot = part("SunFoot", Vector3.new(1, 1, 1), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
			foot.Transparency = 1
			foot.CFrame = CFrame.lookAt(b.from, b.from - b.dir)
			foot.Parent = folder
			Debris:AddItem(foot, dur + 2)
			local sparks = Instance.new("ParticleEmitter")
			sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sparks.Color = ColorSequence.new(Color3.fromRGB(255, 240, 200), Color3.fromRGB(255, 140, 40))
			sparks.LightEmission = 1
			sparks.LightInfluence = 0
			sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
			sparks.Lifetime = NumberRange.new(0.6, 1.4)
			sparks.Speed = NumberRange.new(25, 60)
			sparks.SpreadAngle = Vector2.new(70, 70)
			sparks.EmissionDirection = Enum.NormalId.Back -- (along the beam: lookAt points -Z backwards here)
			sparks.Acceleration = Vector3.new(0, -40, 0)
			sparks.Rate = 160
			sparks.Parent = foot
			local smoke = Instance.new("ParticleEmitter")
			smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
			smoke.Color = ColorSequence.new(Color3.fromRGB(255, 210, 150), Color3.fromRGB(110, 100, 96))
			smoke.LightEmission = 0.3
			smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 14) })
			smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
			smoke.Lifetime = NumberRange.new(1.5, 3)
			smoke.Speed = NumberRange.new(6, 14)
			smoke.SpreadAngle = Vector2.new(180, 180)
			smoke.Rate = 30
			smoke.Parent = foot
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 220, 150)
			light.Range = 60
			light.Brightness = 10
			light.Parent = foot
			task.delay(dur, function()
				sparks.Enabled = false
				smoke.Enabled = false
				light.Enabled = false
			end)
			-- energy streaming up the beam (a moving texture) and a double helix of light winding round its foot
			local s0 = Instance.new("Attachment")
			s0.Parent = foot
			local s1 = Instance.new("Attachment")
			s1.WorldPosition = b.from + b.dir * 1500
			s1.Parent = foot
			local stream = Instance.new("Beam")
			stream.Attachment0 = s0
			stream.Attachment1 = s1
			stream.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			stream.TextureMode = Enum.TextureMode.Wrap
			stream.TextureLength = 18
			stream.TextureSpeed = 9
			stream.LightEmission = 1
			stream.LightInfluence = 0
			stream.FaceCamera = true
			stream.Width0 = Config.SunBeamRadius * 3.2
			stream.Width1 = Config.SunBeamRadius * 3.2
			stream.Color = ColorSequence.new(Color3.fromRGB(255, 250, 220), Color3.fromRGB(255, 200, 100))
			stream.Transparency = NumberSequence.new(0.2)
			stream.Parent = foot
			local helix = {}
			for k = 1, 60 do
				table.insert(helix, part("SunHelix", Vector3.new(4.2, 0.6, 0.6), k % 2 == 0 and Color3.fromRGB(255, 236, 160) or Color3.fromRGB(255, 170, 60), Enum.Material.Neon, Enum.PartType.Cylinder))
				helix[k].Parent = folder
				Debris:AddItem(helix[k], dur + 1)
			end
			task.spawn(function()
				local t0h = os.clock()
				local base = CFrame.lookAt(b.from, b.from + b.dir)
				local parts, cfs = {}, {}
				while os.clock() - t0h < dur and core.Parent do
					local t = os.clock() - t0h
					table.clear(parts)
					table.clear(cfs)
					for k, h in helix do
						local strand = k % 2
						local i = math.floor((k - 1) / 2)
						local z = i * 4.2
						local a = z * 0.08 - t * 9 + strand * math.pi
						local r = Config.SunBeamRadius * (2.2 + 0.6 * math.sin(t * 6 + i * 0.4))
						local p = base * CFrame.new(math.cos(a) * r, math.sin(a) * r, -z - 2)
						local nextP = base * CFrame.new(math.cos(a + 0.34) * r, math.sin(a + 0.34) * r, -z - 6.2)
						table.insert(parts, h)
						table.insert(cfs, CFrame.lookAt(p.Position, nextP.Position) * CFrame.Angles(0, math.rad(90), 0))
						h.Transparency = math.clamp(i / 30, 0, 0.9)
					end
					workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
					RunService.RenderStepped:Wait()
				end
			end)
			-- rings of light running up the beam, sparks off its foot, and the core flickers
			task.spawn(function()
				local t0 = os.clock()
				local r0 = Config.SunBeamRadius
				while os.clock() - t0 < dur and core.Parent do
					local ring = part("SunRing", Vector3.new(1.2, r0 * 5, r0 * 5), Color3.fromRGB(255, 230, 160), Enum.Material.Neon, Enum.PartType.Cylinder)
					ring.Transparency = 0.25
					ring.CFrame = CFrame.lookAt(b.from, b.from + b.dir) * CFrame.Angles(0, math.rad(90), 0)
					ring.Parent = folder
					local goal = b.from + b.dir * 900
					TweenService:Create(ring, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
						CFrame = CFrame.lookAt(goal, goal + b.dir) * CFrame.Angles(0, math.rad(90), 0),
						Size = Vector3.new(1.2, r0 * 9, r0 * 9),
						Transparency = 1,
					}):Play()
					Debris:AddItem(ring, 1.7)
					local f = 1 + math.sin(os.clock() * 40) * 0.08 + math.random() * 0.06
					core.Size = Vector3.new(len, r0 * 2 * f, r0 * 2 * f)
					glow.Size = Vector3.new(len, r0 * 4 * f, r0 * 4 * f)
					glow.Transparency = 0.6 + math.random() * 0.2
					mid.Size = Vector3.new(len, r0 * 2.8 * f, r0 * 2.8 * f)
					haze.Transparency = 0.86 + math.random() * 0.08
					task.wait(0.18)
				end
			end)
		end
	end
	-- the sun swells, the sky burns
	local sky = skyOf()
	local cc = Lighting:FindFirstChild("SunCannonCC") :: ColorCorrectionEffect?
	if not cc then
		local e = Instance.new("ColorCorrectionEffect")
		e.Name = "SunCannonCC"
		e.Parent = Lighting
		cc = e
	end
	if not sunSaved then
		sunSaved = {
			size = sky.SunAngularSize,
			bright = Lighting.Brightness,
			exposure = Lighting.ExposureCompensation,
		}
	end
	local saved = sunSaved :: { [string]: any }
	local t0 = os.clock()
	if sunConn then
		sunConn:Disconnect()
	end
	sunConn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / dur, 0, 1)
		local e = k * k
		sky.SunAngularSize = saved.size + (170 - saved.size) * e
		Lighting.Brightness = saved.bright + 5 * e
		Lighting.ExposureCompensation = saved.exposure + 1.6 * e
		local c = cc :: ColorCorrectionEffect
		c.Enabled = true
		c.TintColor = Color3.new(1, 1 - 0.25 * e, 1 - 0.55 * e)
		c.Brightness = 0.15 * e
		Cam.Shake(0.05 + 0.4 * e)
	end)
end

local function supernova()
	SoundLibrary.Play("supernova", nil, 1)
	white.Visible = true
	white.BackgroundTransparency = 1
	TweenService:Create(white, TweenInfo.new(0.35), { BackgroundTransparency = 0 }):Play()
	Cam.Shake(2)
	task.delay(3.5, function()
		TweenService:Create(white, TweenInfo.new(3), { BackgroundTransparency = 1 }):Play()
		task.delay(3.1, function()
			white.Visible = false
		end)
	end)
end

local function sunReset()
	if sunConn then
		sunConn:Disconnect()
		sunConn = nil
	end
	local saved = sunSaved
	sunSaved = nil
	if saved then
		local sky = skyOf()
		sky.SunAngularSize = saved.size
		Lighting.Brightness = saved.bright
		Lighting.ExposureCompensation = saved.exposure
	end
	local cc = Lighting:FindFirstChild("SunCannonCC")
	if cc then
		cc:Destroy()
	end
	for _, p in folder:GetChildren() do
		if p.Name == "SunBeam" or p.Name == "SunGlow" or p.Name == "SunHelix" or p.Name == "SunFoot" then
			p:Destroy()
		end
	end
end

------------------------------------------------------------------------

function SuperFX.Init()
	local fx = workspace:WaitForChild("FX", 30) or workspace
	local f = Instance.new("Folder")
	f.Name = "SuperFX"
	f.Parent = fx
	folder = f
	gui = UI.make("ScreenGui", { Name = "SuperFX", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40, Parent = player:WaitForChild("PlayerGui") })
	white = UI.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Visible = false, Parent = gui })
	machLabel = UI.label({ Text = "", Font = UI.FONT_TITLE, TextSize = 46, TextColor3 = Color3.fromRGB(255, 200, 80), TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90), Size = UDim2.fromOffset(420, 52), TextStrokeTransparency = 0.3, Visible = false, Parent = gui })
	Events.On("timestop", timeStop)
	Events.On("hotdog", hotdog)
	Events.On("hotdogboom", function()
		machLabel.Visible = false
		local m = folder:FindFirstChild("Hotdog")
		if m then
			m:Destroy()
		end
	end)
	Events.On("suncharge", sunCharge)
	Events.On("sunbeam", sunBeam)
	Events.On("supernova", supernova)
	Events.On("sunreset", sunReset)
	-- the admin keys
	local Items = require(Shared:WaitForChild("Items"))
	local Input = require(script.Parent:WaitForChild("Input"))
	local AdminRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Admin") :: RemoteEvent
	Input.Action:Connect(function(action)
		if not Items.Has(player, "hotdog") or Input.menuOpen or Input.promptOpen then
			return
		end
		if action == "Hotdog" then
			local cam = workspace.CurrentCamera
			local vs = cam.ViewportSize
			local ray = cam:ViewportPointToRay(vs.X * 0.5, vs.Y * 0.5)
			AdminRemote:FireServer("hotdog", ray.Origin, ray.Direction)
		end
	end)
	-- (v2.1 fix) O (time stop) is bound straight to the engine's input at the highest priority. Before it came through Input.Action,
	-- which several things could swallow first (Roblox's own camera takes O for zoom, a stale prompt / menu flag, free cam ...).
	-- This binding sinks the press (no camera zoom), needs no flag, and says so when you may not use it.
	do
		local CAS = game:GetService("ContextActionService")
		local UIS = game:GetService("UserInputService")
		local lastPress = 0
		local function onPress(_, state)
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			if UIS:GetFocusedTextBox() ~= nil then
				return Enum.ContextActionResult.Pass -- (typing an O)
			end
			local now = os.clock()
			if now - lastPress < 0.35 then
				return Enum.ContextActionResult.Sink
			end
			lastPress = now
			if Items.Has(player, "timestop") then
				AdminRemote:FireServer("timestop")
			else
				pcall(function()
					game:GetService("StarterGui"):SetCore("SendNotification", { Title = "TIME STOP", Text = "Only the owner and admins can stop time.", Duration = 3 })
				end)
			end
			return Enum.ContextActionResult.Sink
		end
		-- (v2.8) on the key the player gave it (M > SETTINGS > KEYS), O by default
		local function bind()
			CAS:UnbindAction("RagdollTimeStop")
			CAS:BindActionAtPriority("RagdollTimeStop", onPress, false, Enum.ContextActionPriority.High.Value + 500, Input.KeyFor("TimeStop") or Enum.KeyCode.I)
		end
		bind()
		local Settings = require(Shared:WaitForChild("Settings"))
		Settings.Changed:Connect(function(key)
			if key == "keyBinds" then
				task.defer(bind) -- (after Input took the new keys)
			end
		end)
	end
	-- joining while time is stopped: grey at once
	if workspace:GetAttribute("TimeStop") then
		timeStop({ on = true, p = Vector3.zero })
	end
end

return SuperFX
