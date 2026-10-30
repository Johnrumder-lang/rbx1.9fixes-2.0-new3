--!nonstrict
-- SteelBallFX (v2.0): what everybody sees of the steel balls (the server flies them, see SteelBallService).
--   "steelball"  a ball leaves a hand: straight and fast. Steel with a faint streak; with the Spin green, glowing,
--                with a yellow trail and a whirr. (The thrower's own client starts its ball at once - LocalThrow -
--                and only takes over the server's id.)
--   "ballend"    it hit / stopped (with the Spin it waits there for "ballreturn")
--   "ballreturn" with the Spin: it flies back to the thrower's hand in an arc (SteelBallService.Arc)
--   "ballcatch"  (only to the thrower) the ball is back: the hand closes on it
--   "spinfx"     a golden swirl around somebody a Spin ball hit; "spun" (only to them) = they spin
-- The thrower's client hides the item it let go (LocalTransparencyModifier) until it is back in the world.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))

local Events = require(script.Parent:WaitForChild("Events"))

local player = Players.LocalPlayer

local SteelBallFX = {}

type Vis = {
	model: Model,
	ball: BasePart,
	pos: Vector3,
	vel: Vector3,
	spin: boolean,
	phase: string, -- "out" | "wait" | "back"
	by: number,
	side: string,
	from: Vector3?,
	t0: number,
	dur: number,
	dist: number,
	angle: number,
	stopAt: number,
	id: number?,
	loop: Sound?,
	born: number,
}

local controller = nil
local list: { Vis } = {}
local byId: { [number]: Vis } = {}
local pending: { Vis } = {} -- my own throws, waiting for the server's id
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local STEEL = Color3.fromRGB(150, 154, 162)

function SteelBallFX.SetController(c)
	controller = c
end

local function fxFolder(): Instance
	return workspace:FindFirstChild("FX") or workspace
end

-- the same arc as SteelBallService.Arc
local function arc(a: Vector3, b: Vector3, t: number): Vector3
	local d = (b - a).Magnitude
	local ctrl = (a + b) * 0.5 + Vector3.new(0, d * 0.3 + 5, 0)
	local u = 1 - t
	return a * (u * u) + ctrl * (2 * u * t) + b * (t * t)
end

local function handOf(userId: number, side: string): Vector3?
	local p = Players:GetPlayerByUserId(userId)
	local c = p and p.Character
	if not c then
		return nil
	end
	local arm = c:FindFirstChild(side == "Left" and "Left Arm" or "Right Arm")
	if not arm or not arm:IsA("BasePart") then
		arm = c:FindFirstChild(side == "Left" and "Right Arm" or "Left Arm")
	end
	if arm and arm:IsA("BasePart") then
		return arm.CFrame:PointToWorldSpace(Vector3.new(0, -1.1, -0.3))
	end
	local t = c:FindFirstChild("Torso")
	return (t and t:IsA("BasePart")) and t.Position or nil
end

local function showItem(item: any)
	if typeof(item) ~= "Instance" then
		return
	end
	for _, d in item:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 0
		end
	end
end

local function make(pos: Vector3, spin: boolean): (Model, BasePart, Sound?)
	local m = Instance.new("Model")
	m.Name = "SteelBallFX"
	local ball = Instance.new("Part")
	ball.Name = "Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(0.95, 0.95, 0.95)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Material = spin and Enum.Material.SmoothPlastic or Enum.Material.Metal
	ball.Reflectance = spin and 0.15 or 0.35
	ball.Color = spin and Config.SpinBallColor or STEEL
	ball.CFrame = CFrame.new(pos)
	ball.Parent = m
	local ring = Instance.new("Part")
	ring.Name = "Groove"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.06, 0.97, 0.97)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Color = spin and Color3.fromRGB(24, 92, 40) or Color3.fromRGB(44, 46, 52)
	ring.Material = Enum.Material.Metal
	ring.CFrame = ball.CFrame
	ring.Parent = m
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.32, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.32, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.FaceCamera = true
	if spin then
		trail.Lifetime = 0.45
		trail.Color = ColorSequence.new(Config.SpinTrailColor, Color3.fromRGB(255, 160, 30))
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
		trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0.2) })
		trail.LightEmission = 1
		local light = Instance.new("PointLight")
		light.Color = Config.SpinBallColor
		light.Range = 9
		light.Brightness = 2
		light.Parent = ball
		local sparks = Instance.new("ParticleEmitter")
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.Color = ColorSequence.new(Config.SpinTrailColor)
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		sparks.Lifetime = NumberRange.new(0.25, 0.5)
		sparks.Speed = NumberRange.new(1, 3)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Rate = 40
		sparks.Parent = ball
	else
		-- (v2.0) a hard steel streak with an air wake round it
		trail.Lifetime = 0.24
		trail.Color = ColorSequence.new(Color3.fromRGB(240, 242, 246), Color3.fromRGB(150, 160, 175))
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.05) })
		trail.LightEmission = 0.35
		local wake = Instance.new("ParticleEmitter")
		wake.Name = "Wake"
		wake.Color = ColorSequence.new(Color3.fromRGB(235, 238, 245))
		wake.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1) })
		wake.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.9) })
		wake.Lifetime = NumberRange.new(0.12, 0.22)
		wake.Speed = NumberRange.new(0.5, 1.5)
		wake.SpreadAngle = Vector2.new(180, 180)
		wake.Rate = 70
		wake.LightInfluence = 1
		wake.Parent = ball
	end
	trail.Parent = ball
	m.PrimaryPart = ball
	m.Parent = fxFolder()
	local loop = nil
	if spin then
		loop = SoundLibrary.Loop("steelSpin", ball)
		if loop then
			loop:Play()
		end
	end
	return m, ball, loop
end

local function newVis(pos: Vector3, vel: Vector3, spin: boolean, by: number): Vis
	local m, ball, loop = make(pos, spin)
	local v: Vis = {
		model = m,
		ball = ball,
		pos = pos,
		vel = vel,
		spin = spin,
		phase = "out",
		by = by,
		side = "Right",
		t0 = os.clock(),
		dur = 1,
		dist = 0,
		angle = 0,
		stopAt = os.clock() + 6,
		loop = loop,
		born = os.clock(),
	}
	table.insert(list, v)
	return v
end

local function kill(v: Vis)
	if v.model.Parent then
		v.model:Destroy()
	end
	if v.id then
		byId[v.id] = nil
	end
	v.phase = "dead"
end

-- my own throw: it flies at once (the server's copy takes over its id a moment later)
function SteelBallFX.LocalThrow(origin: Vector3, vel: Vector3, spin: boolean)
	local v = newVis(origin, vel, spin, player.UserId)
	table.insert(pending, v)
end

local function step(v: Vis, dt: number, now: number)
	if v.phase == "out" then
		v.vel += Vector3.new(0, -workspace.Gravity * Config.SteelBallGravity * dt, 0)
		local s = v.vel * dt
		local ignore: { Instance } = { fxFolder() }
		local p = Players:GetPlayerByUserId(v.by)
		if p and p.Character then
			table.insert(ignore, p.Character)
		end
		params.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(v.pos, s, params)
		if hit then
			v.pos = hit.Position - s.Unit * 0.45
			v.phase = "wait"
			v.stopAt = now + (v.spin and 3 or 1)
		else
			v.pos += s
			v.dist += s.Magnitude
			if v.dist > Config.SteelBallRange then
				v.phase = "wait"
				v.stopAt = now + (v.spin and 3 or 1)
			end
		end
	elseif v.phase == "wait" then
		if now > v.stopAt then
			kill(v)
			return
		end
	elseif v.phase == "back" then
		local hand = handOf(v.by, v.side)
		local t = (now - v.t0) / v.dur
		if not hand or t >= 1 then
			kill(v)
			return
		end
		v.pos = arc(v.from or v.pos, hand, t)
	end
	v.angle += dt * (v.spin and 34 or 12)
	local cf = CFrame.new(v.pos) * CFrame.Angles(v.angle, v.angle * 0.37, 0)
	v.ball.CFrame = cf
	local ring = v.model:FindFirstChild("Groove")
	if ring and ring:IsA("BasePart") then
		ring.CFrame = cf
	end
end

-- the ball that came back: into the hand it was thrown from (or the other one, if that one is busy)
local function catch(item: any, side: any)
	if typeof(item) ~= "Instance" or not item:IsA("Model") then
		return
	end
	showItem(item)
	local function ready(): boolean
		return item.PrimaryPart ~= nil and item:IsDescendantOf(workspace) and controller ~= nil and controller.ready == true
			and controller.character == player.Character and not controller.dead
	end
	for _ = 1, 20 do
		if ready() then
			break
		end
		task.wait(0.05)
	end
	if not ready() then
		return
	end
	local s = side == "Left" and "Left" or "Right"
	if controller.hands[s].grip then
		s = s == "Left" and "Right" or "Left"
		if controller.hands[s].grip then
			return
		end
	end
	pcall(function()
		controller.hands[s].armed = true
		controller:_gripItem(s, item)
	end)
end

-- a golden swirl around a body a Spin ball hit
local function spinFX(part: any, d: number)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return
	end
	local a = Instance.new("Attachment")
	a.Name = "SpinFX"
	a.Parent = part
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Config.SpinTrailColor, Config.SpinBallColor)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.4, 0.8)
	e.Speed = NumberRange.new(4, 8)
	e.SpreadAngle = Vector2.new(180, 30)
	e.RotSpeed = NumberRange.new(-360, 360)
	e.Rate = 70
	e.Parent = a
	local l = Instance.new("PointLight")
	l.Color = Config.SpinTrailColor
	l.Range = 10
	l.Brightness = 1.6
	l.Parent = a
	task.delay(d, function()
		e.Enabled = false
		l:Destroy()
		task.wait(0.8)
		a:Destroy()
	end)
end

-- (v2.0) where a ball lands: sparks off the steel, a puff of dust and a flat shock ring (bigger on a body,
-- and a flash on a headshot)
local function impact(pos: Vector3, normal: Vector3, onBody: boolean, head: boolean)
	local n = normal.Magnitude > 0.01 and normal.Unit or Vector3.yAxis
	local holder = Instance.new("Part")
	holder.Name = "SteelImpact"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.lookAt(pos, pos + n)
	holder.Parent = fxFolder()
	local a = Instance.new("Attachment")
	a.CFrame = CFrame.Angles(math.rad(-90), 0, 0) -- (emit along the surface normal)
	a.Parent = holder
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 236, 170), Color3.fromRGB(255, 150, 60))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.15, 0.4)
	sparks.Speed = NumberRange.new(18, 34)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Acceleration = Vector3.new(0, -60, 0)
	sparks.Drag = 3
	sparks.Rate = 0
	sparks.Parent = a
	sparks:Emit(onBody and 6 or 18)
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(onBody and Color3.fromRGB(150, 40, 36) or Color3.fromRGB(170, 160, 145))
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 2.2) })
	dust.Lifetime = NumberRange.new(0.4, 0.8)
	dust.Speed = NumberRange.new(4, 9)
	dust.SpreadAngle = Vector2.new(70, 70)
	dust.Drag = 5
	dust.RotSpeed = NumberRange.new(-90, 90)
	dust.LightInfluence = 1
	dust.Rate = 0
	dust.Parent = a
	dust:Emit(onBody and 10 or 14)
	-- the shock ring, flat on the surface
	local ring = Instance.new("Part")
	ring.Name = "Shock"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = head and Color3.fromRGB(255, 240, 220) or Color3.fromRGB(230, 236, 245)
	ring.Transparency = 0.35
	ring.Size = Vector3.new(0.08, 0.6, 0.6)
	ring.CFrame = CFrame.lookAt(pos + n * 0.05, pos + n * 1.05) * CFrame.Angles(0, math.rad(90), 0)
	ring.Parent = fxFolder()
	local r = onBody and (head and 7 or 4.5) or 3.2
	game:GetService("TweenService"):Create(ring, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.04, r, r), Transparency = 1 }):Play()
	if head then
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 230, 200)
		l.Range = 12
		l.Brightness = 4
		l.Parent = holder
		game:GetService("TweenService"):Create(l, TweenInfo.new(0.25), { Brightness = 0 }):Play()
	end
	game:GetService("Debris"):AddItem(holder, 1.2)
	game:GetService("Debris"):AddItem(ring, 0.4)
end

function SteelBallFX.Init()
	Events.On("steelimpact", function(p)
		if typeof(p.p) == "Vector3" then
			impact(p.p, typeof(p.n) == "Vector3" and p.n or Vector3.yAxis, p.body == true, p.head == true)
		end
	end)
	Events.On("steelball", function(p)
		if typeof(p.p) ~= "Vector3" or typeof(p.v) ~= "Vector3" or typeof(p.id) ~= "number" then
			return
		end
		if p.by == player.UserId and #pending > 0 then
			local v = table.remove(pending, 1) :: Vis
			v.id = p.id
			byId[p.id] = v
			return
		end
		local v = newVis(p.p, p.v, p.spin == true, typeof(p.by) == "number" and p.by or 0)
		v.id = p.id
		byId[p.id] = v
		SoundLibrary.Play("steelThrow", p.p, 0.9)
	end)
	Events.On("ballend", function(p)
		local v = typeof(p.id) == "number" and byId[p.id] or nil
		if p.item and p.by == player.UserId then
			showItem(p.item)
		end
		if not v then
			return
		end
		if p.keep then
			v.phase = "wait"
			if typeof(p.p) == "Vector3" then
				v.pos = p.p
			end
			v.stopAt = os.clock() + 3
		else
			kill(v)
		end
	end)
	Events.On("ballreturn", function(p)
		if typeof(p.a) ~= "Vector3" or typeof(p.dur) ~= "number" then
			return
		end
		local v = typeof(p.id) == "number" and byId[p.id] or nil
		if not v or v.phase == "dead" then
			v = newVis(p.a, Vector3.zero, true, typeof(p.by) == "number" and p.by or 0)
			v.id = p.id
			byId[p.id] = v
		end
		v.phase = "back"
		v.from = p.a
		v.side = p.side == "Left" and "Left" or "Right"
		v.t0 = os.clock()
		v.dur = math.max(0.2, p.dur)
	end)
	Events.On("ballcatch", function(p)
		catch(p.item, p.side)
	end)
	Events.On("spinfx", function(p)
		spinFX(p.part, typeof(p.d) == "number" and p.d or 2)
	end)
	Events.On("spun", function(p)
		if controller and controller.ready and controller._spun then
			controller:_spun(typeof(p.d) == "number" and p.d or Config.SpinVictimTime)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local stopped = workspace:GetAttribute("TimeStop") ~= nil
		for i = #list, 1, -1 do
			local v = list[i]
			if v.phase == "dead" then
				table.remove(list, i)
				continue
			end
			if stopped then
				v.t0 += dt
				v.stopAt += dt
				continue
			end
			if now - v.born > 12 then
				kill(v)
				continue
			end
			step(v, dt, now)
		end
		-- a throw the server never confirmed
		for i = #pending, 1, -1 do
			if now - pending[i].born > 1.5 then
				table.remove(pending, i)
			end
		end
	end)
end

return SteelBallFX
