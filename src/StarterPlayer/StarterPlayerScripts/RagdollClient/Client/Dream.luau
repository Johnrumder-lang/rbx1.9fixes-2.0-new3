--!nonstrict
-- Dream: what you see while you are knocked out (sleep dart). After a moment of black a dream
-- fades in on your screen (a small 3D scene in a ViewportFrame, only for you) and fades out again
-- just before you wake up. The world stays silent; only a soft dream hum and a few chimes.
--   * counting sheep   : sheep jump over a fence under the moon, one after another, counted
--   * falling          : slowly falling through a pink sky past floating shapes
--   * floating island  : a little island with a house, a tree and a waterfall turns in the sunset
--   * the hallway      : an endless warm hallway of doors drifting by

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local SoundLibrary = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SoundLibrary"))

local Dream = {}

local rng = Random.new()
local current: { holder: Frame, conn: RBXScriptConnection?, pad: Sound?, t0: number, duration: number }? = nil

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?, mat: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function gradient(frame: Frame, top: Color3, bottom: Color3)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = frame
end

------------------------------------------------------------------------
-- scenes: build(world, camera, sky, caption) -> update(t)
------------------------------------------------------------------------

local function sheepScene(world: Instance, cam: Camera, sky: Frame, caption: TextLabel)
	gradient(sky, rgb(16, 22, 58), rgb(58, 70, 120))
	part(world, Vector3.new(200, 1, 60), CFrame.new(0, -0.5, 0), rgb(70, 120, 70))
	part(world, Vector3.new(6, 6, 6), CFrame.new(18, 26, 40), rgb(255, 246, 210), Enum.PartType.Ball, Enum.Material.Neon)
	for _ = 1, 40 do
		local s = rng:NextNumber(0.2, 0.45)
		part(world, Vector3.one * s, CFrame.new(rng:NextNumber(-60, 60), rng:NextNumber(10, 40), rng:NextNumber(40, 60)), rgb(255, 255, 230), Enum.PartType.Ball, Enum.Material.Neon)
	end
	-- the fence
	local wood = rgb(140, 100, 60)
	for _, x in { -1.2, 1.2 } do
		part(world, Vector3.new(0.4, 3, 0.4), CFrame.new(x, 1.5, 0), wood)
	end
	part(world, Vector3.new(3.2, 0.3, 0.2), CFrame.new(0, 2.3, 0), wood)
	part(world, Vector3.new(3.2, 0.3, 0.2), CFrame.new(0, 1.2, 0), wood)
	-- a few sheep, reused one after another
	local function makeSheep(): Model
		local m = Instance.new("Model")
		local white = rgb(245, 244, 238)
		for _, o in { Vector3.new(-0.6, 0, 0), Vector3.new(0.3, 0.15, 0), Vector3.new(0.6, -0.1, 0.2) } do
			part(m, Vector3.one * 1.5, CFrame.new(o + Vector3.new(0, 1.6, 0)), white, Enum.PartType.Ball)
		end
		part(m, Vector3.new(0.7, 0.75, 0.6), CFrame.new(1.35, 2.0, 0), rgb(40, 38, 40))
		for _, o in { Vector3.new(-0.7, 0, -0.35), Vector3.new(-0.7, 0, 0.35), Vector3.new(0.6, 0, -0.35), Vector3.new(0.6, 0, 0.35) } do
			part(m, Vector3.new(0.22, 1, 0.22), CFrame.new(o + Vector3.new(0, 0.5, 0)), rgb(40, 38, 40))
		end
		local root = part(m, Vector3.new(0.1, 0.1, 0.1), CFrame.new(), white)
		root.Transparency = 1
		m.PrimaryPart = root
		m.Parent = world
		return m
	end
	local sheep = { makeSheep(), makeSheep(), makeSheep() }
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 4, -16), Vector3.new(0, 2, 0))
	local counted = 0
	local period = 2.6
	return function(t: number)
		for i, m in sheep do
			local k = ((t + (i - 1) * period) % (period * #sheep)) / (period * #sheep) -- 0..1 over its run
			local x = -22 + 44 * k
			local hop = math.max(0, 1 - (x / 4) ^ 2) * 3.4 + math.abs(math.sin(x * 1.3)) * 0.25
			m:PivotTo(CFrame.new(x, hop, 0))
		end
		local n = math.floor((t + period * 0.5) / period)
		if n ~= counted and n > 0 then
			counted = n
			caption.Text = tostring(n)
		end
		cam.CFrame = CFrame.lookAt(Vector3.new(math.sin(t * 0.1) * 3, 4 + math.sin(t * 0.2) * 0.4, -16), Vector3.new(0, 2, 0))
	end
end

local function fallingScene(world: Instance, cam: Camera, sky: Frame, _caption: TextLabel)
	gradient(sky, rgb(250, 170, 200), rgb(120, 90, 190))
	local shapes = {}
	local colors = { rgb(255, 220, 120), rgb(140, 230, 255), rgb(255, 160, 210), rgb(180, 255, 180), rgb(255, 255, 255) }
	for _ = 1, 46 do
		local kind = rng:NextInteger(1, 3)
		local s = rng:NextNumber(1, 4)
		local p = part(world, kind == 3 and Vector3.new(s * 0.4, s * 1.4, s * 1.4) or Vector3.one * s, CFrame.new(), colors[rng:NextInteger(1, #colors)],
			kind == 1 and Enum.PartType.Ball or (kind == 3 and Enum.PartType.Cylinder or nil), rng:NextNumber() < 0.3 and Enum.Material.Neon or nil)
		table.insert(shapes, { p = p, pos = Vector3.new(rng:NextNumber(-30, 30), rng:NextNumber(-80, 20), rng:NextNumber(-30, 30)), spin = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) })
	end
	-- you: a little blocky body falling, arms out
	local me = Instance.new("Model")
	local skin = rgb(230, 190, 150)
	part(me, Vector3.new(2, 2, 1), CFrame.new(0, 0, 0), rgb(60, 110, 200))
	part(me, Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 1.6, 0), skin)
	part(me, Vector3.new(1, 2, 1), CFrame.new(-1.9, 0.6, 0) * CFrame.Angles(0, 0, 1.2), skin)
	part(me, Vector3.new(1, 2, 1), CFrame.new(1.9, 0.6, 0) * CFrame.Angles(0, 0, -1.2), skin)
	part(me, Vector3.new(1, 2, 1), CFrame.new(-0.6, -2, 0) * CFrame.Angles(0, 0, 0.3), rgb(40, 40, 60))
	part(me, Vector3.new(1, 2, 1), CFrame.new(0.6, -2, 0) * CFrame.Angles(0, 0, -0.3), rgb(40, 40, 60))
	local root = part(me, Vector3.new(0.1, 0.1, 0.1), CFrame.new(), skin)
	root.Transparency = 1
	me.PrimaryPart = root
	me.Parent = world
	return function(t: number)
		local fall = t * 9
		for _, s in shapes do
			local y = ((s.pos.Y + fall + 80) % 100) - 80
			s.p.CFrame = CFrame.new(s.pos.X, y, s.pos.Z) * CFrame.Angles(s.spin.X * t, s.spin.Y * t, s.spin.Z * t)
		end
		me:PivotTo(CFrame.new(0, -6 + math.sin(t * 0.8) * 0.6, 0) * CFrame.Angles(0.5 + math.sin(t * 0.5) * 0.2, t * 0.4, math.sin(t * 0.3) * 0.3))
		cam.CFrame = CFrame.lookAt(Vector3.new(math.sin(t * 0.15) * 4, 10, 16), Vector3.new(0, -6, 0))
	end
end

local function islandScene(world: Instance, cam: Camera, sky: Frame, _caption: TextLabel)
	gradient(sky, rgb(255, 150, 110), rgb(255, 214, 160))
	-- the island: stacked rock rings getting smaller downwards, grass on top
	for i = 0, 5 do
		local r = 18 - i * 3
		part(world, Vector3.new(2.4, r, r), CFrame.new(0, -i * 2.2, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(120 - i * 8, 92 - i * 6, 70 - i * 5), Enum.PartType.Cylinder)
	end
	part(world, Vector3.new(0.8, 18.4, 18.4), CFrame.new(0, 1.4, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(90, 170, 80), Enum.PartType.Cylinder)
	-- a little house
	part(world, Vector3.new(4, 3, 3.4), CFrame.new(-2.5, 3.3, 1.5), rgb(240, 230, 210))
	local roof = Instance.new("WedgePart")
	roof.Anchored = true
	roof.Size = Vector3.new(4.4, 1.6, 1.9)
	roof.Color = rgb(190, 70, 60)
	roof.CFrame = CFrame.new(-2.5, 5.6, 2.35)
	roof.Parent = world
	local roof2 = roof:Clone()
	roof2.CFrame = CFrame.new(-2.5, 5.6, 0.65) * CFrame.Angles(0, math.pi, 0)
	roof2.Parent = world
	part(world, Vector3.new(0.9, 1.6, 0.1), CFrame.new(-2.5, 2.6, -0.25), rgb(120, 80, 50))
	-- a tree
	part(world, Vector3.new(0.7, 4, 0.7), CFrame.new(4, 3.8, -2), rgb(110, 75, 45))
	for _, o in { Vector3.new(0, 6.5, 0), Vector3.new(0.9, 5.8, 0.4), Vector3.new(-0.8, 6, -0.5) } do
		part(world, Vector3.one * 2.8, CFrame.new(Vector3.new(4, 0, -2) + o), rgb(70, 150, 70), Enum.PartType.Ball)
	end
	-- the waterfall over the edge
	local fallParts = {}
	for i = 1, 12 do
		table.insert(fallParts, part(world, Vector3.new(1.4, 1.2, 0.3), CFrame.new(0, 0, 0), rgb(160, 220, 255), nil, Enum.Material.Neon))
		fallParts[i].Transparency = 0.25
	end
	-- clouds
	local clouds = {}
	for _ = 1, 10 do
		local c = Instance.new("Model")
		for _ = 1, 4 do
			part(c, Vector3.one * rng:NextNumber(3, 6), CFrame.new(rng:NextNumber(-3, 3), rng:NextNumber(-0.6, 0.6), rng:NextNumber(-1.5, 1.5)), rgb(255, 250, 245), Enum.PartType.Ball)
		end
		local r = part(c, Vector3.new(0.1, 0.1, 0.1), CFrame.new(), rgb(255, 255, 255))
		r.Transparency = 1
		c.PrimaryPart = r
		c.Parent = world
		table.insert(clouds, { m = c, a = rng:NextNumber(0, math.pi * 2), r = rng:NextNumber(26, 40), y = rng:NextNumber(-12, 10) })
	end
	return function(t: number)
		for i, p in fallParts do
			local k = ((t * 0.6 + i / #fallParts) % 1)
			p.CFrame = CFrame.new(8.6, 1 - k * 18, 3)
			p.Transparency = 0.2 + 0.7 * k
		end
		for _, c in clouds do
			local a = c.a + t * 0.05
			c.m:PivotTo(CFrame.new(math.cos(a) * c.r, c.y, math.sin(a) * c.r))
		end
		local a = t * 0.12
		cam.CFrame = CFrame.lookAt(Vector3.new(math.cos(a) * 34, 12 + math.sin(t * 0.3) * 2, math.sin(a) * 34), Vector3.new(0, 1, 0))
	end
end

local function hallwayScene(world: Instance, cam: Camera, sky: Frame, _caption: TextLabel)
	gradient(sky, rgb(40, 30, 24), rgb(20, 14, 10))
	local SEG = 8
	local segs = {}
	local doorColors = { rgb(160, 60, 50), rgb(60, 90, 150), rgb(70, 130, 80), rgb(200, 170, 80), rgb(120, 70, 140) }
	for i = 0, 11 do
		local m = Instance.new("Model")
		part(m, Vector3.new(10, 0.4, SEG), CFrame.new(0, 0, 0), rgb(120, 70, 50), nil, Enum.Material.WoodPlanks)
		part(m, Vector3.new(10, 0.4, SEG), CFrame.new(0, 9, 0), rgb(220, 200, 170))
		part(m, Vector3.new(0.4, 9, SEG), CFrame.new(-5, 4.5, 0), rgb(200, 160, 120))
		part(m, Vector3.new(0.4, 9, SEG), CFrame.new(5, 4.5, 0), rgb(200, 160, 120))
		for _, x in { -4.75, 4.75 } do
			part(m, Vector3.new(0.2, 6, 3), CFrame.new(x, 3.2, 0), doorColors[rng:NextInteger(1, #doorColors)])
			part(m, Vector3.new(0.3, 0.3, 0.3), CFrame.new(x * 0.98, 3.2, 1), rgb(230, 200, 90), Enum.PartType.Ball, Enum.Material.Neon)
		end
		part(m, Vector3.new(1.4, 0.2, 1.4), CFrame.new(0, 8.7, 0), rgb(255, 230, 170), nil, Enum.Material.Neon)
		local r = part(m, Vector3.new(0.1, 0.1, 0.1), CFrame.new(), rgb(0, 0, 0))
		r.Transparency = 1
		m.PrimaryPart = r
		m.Parent = world
		segs[i + 1] = m
	end
	-- the light at the end
	local glow = part(world, Vector3.new(9, 8.6, 0.5), CFrame.new(0, 4.5, -SEG * 12), rgb(255, 250, 235), nil, Enum.Material.Neon)
	return function(t: number)
		local off = (t * 4) % SEG
		for i, m in segs do
			m:PivotTo(CFrame.new(0, 0, -(i - 1) * SEG + off))
		end
		glow.CFrame = CFrame.new(0, 4.5, -SEG * 11.5)
		cam.CFrame = CFrame.lookAt(Vector3.new(math.sin(t * 0.7) * 0.3, 4.8 + math.sin(t * 1.4) * 0.15, 6), Vector3.new(0, 4.4, -40))
	end
end

local SCENES = { sheepScene, fallingScene, islandScene, hallwayScene }

------------------------------------------------------------------------

function Dream.Stop()
	local c = current
	if not c then
		return
	end
	current = nil
	if c.conn then
		c.conn:Disconnect()
	end
	if c.pad then
		c.pad:Destroy()
	end
	c.holder:Destroy()
end

-- `parent`: the black sleep overlay; `duration`: how long until you wake up
function Dream.Start(parent: GuiObject, duration: number)
	Dream.Stop()
	if duration < 4 then
		return
	end
	local holder = Instance.new("Frame")
	holder.Name = "Dream"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.ZIndex = parent.ZIndex + 1
	holder.Parent = parent
	local sky = Instance.new("Frame")
	sky.Name = "Sky"
	sky.Size = UDim2.fromScale(1, 1)
	sky.BackgroundColor3 = Color3.new(1, 1, 1)
	sky.BackgroundTransparency = 1
	sky.BorderSizePixel = 0
	sky.ZIndex = holder.ZIndex
	sky.Parent = holder
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Scene"
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.ImageTransparency = 1
	vp.Ambient = Color3.fromRGB(170, 160, 190)
	vp.LightColor = Color3.fromRGB(255, 240, 225)
	vp.LightDirection = Vector3.new(-0.4, -1, -0.6)
	vp.ZIndex = holder.ZIndex + 1
	vp.Parent = holder
	local cam = Instance.new("Camera")
	cam.FieldOfView = 55
	cam.Parent = vp
	vp.CurrentCamera = cam
	local world = Instance.new("Model")
	world.Name = "DreamWorld"
	world.Parent = vp
	-- soft dark edges (a vignette)
	for _, rot in { 0, 90, 180, 270 } do
		local edge = Instance.new("Frame")
		edge.Size = UDim2.fromScale(1, 1)
		edge.BackgroundColor3 = Color3.new(0, 0, 0)
		edge.BorderSizePixel = 0
		edge.ZIndex = holder.ZIndex + 2
		local g = Instance.new("UIGradient")
		g.Rotation = rot
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.22, 1), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = edge
		edge.Parent = holder
	end
	local caption = Instance.new("TextLabel")
	caption.Name = "Count"
	caption.BackgroundTransparency = 1
	caption.AnchorPoint = Vector2.new(0.5, 0)
	caption.Position = UDim2.fromScale(0.5, 0.1)
	caption.Size = UDim2.fromOffset(200, 60)
	caption.Font = Enum.Font.Sarpanch
	caption.TextSize = 46
	caption.TextColor3 = Color3.fromRGB(255, 250, 235)
	caption.TextTransparency = 1
	caption.Text = ""
	caption.ZIndex = holder.ZIndex + 3
	caption.Parent = holder

	local scene = SCENES[rng:NextInteger(1, #SCENES)]
	local update = scene(world, cam, sky, caption)
	local pad = SoundLibrary.Loop("dreamPad", SoundService)
	if pad then
		pad.Volume = 0
		pad:Play()
	end
	local t0 = os.clock()
	local nextChime = t0 + 3
	local rec = { holder = holder, conn = nil, pad = pad, t0 = t0, duration = duration }
	current = rec
	rec.conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		-- black first, then the dream fades in; it fades out just before you wake up
		local fadeIn = math.clamp((t - 1.4) / 2, 0, 1)
		local fadeOut = math.clamp((duration - 1.2 - t) / 1.6, 0, 1)
		local k = fadeIn * fadeOut
		vp.ImageTransparency = 1 - k
		sky.BackgroundTransparency = 1 - k
		caption.TextTransparency = 1 - k * 0.85
		if pad then
			pad.Volume = 0.2 * k
		end
		if os.clock() > nextChime and k > 0.5 then
			nextChime = os.clock() + rng:NextNumber(2.5, 5)
			SoundLibrary.Play("dreamChime", nil, k)
		end
		pcall(update, t)
	end)
end

function Dream.Active(): boolean
	return current ~= nil
end

return Dream
