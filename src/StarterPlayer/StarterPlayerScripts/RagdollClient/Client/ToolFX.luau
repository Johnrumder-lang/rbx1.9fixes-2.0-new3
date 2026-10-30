--!nonstrict
-- ToolFX (v2.0): what tools do on every screen while they run.
--   chainsaw : F starts the motor (the server sets SawOn). While it runs: the two-stroke idle loop, exhaust
--              smoke, sawdust off the bar, and the motor revs up while it bites (my own saw)
--   sawSpray : blood and sparks where the running chain bites

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))

local Events = require(script.Parent:WaitForChild("Events"))
local BloodFX = require(script.Parent:WaitForChild("BloodFX"))

local ToolFX = {}

type Saw = { model: Model, loop: Sound?, smoke: ParticleEmitter?, dust: ParticleEmitter?, rev: number }

local saws: { [Model]: Saw } = {}
local controller = nil

function ToolFX.SetController(c)
	controller = c
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function track(m: Instance)
	if not m:IsA("Model") or m:GetAttribute("Item") ~= "chainsaw" or saws[m] then
		return
	end
	saws[m] = { model = m, rev = 0 }
end

local function start(s: Saw)
	local motor = s.model:FindFirstChild("Motor")
	local blade = s.model:FindFirstChild("Blade")
	if not motor or not motor:IsA("BasePart") then
		return
	end
	if not s.loop then
		local l = SoundLibrary.Loop("chainsawIdle", motor)
		if l then
			l.Volume = 0.7
			l:Play()
		end
		s.loop = l
	end
	if not s.smoke then
		local a = Instance.new("Attachment")
		a.Name = "Exhaust"
		a.Position = Vector3.new(0.45, 0.2, 0.3)
		a.Parent = motor
		s.smoke = emitter(a, {
			Name = "Exhaust",
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Rate = 18,
			Lifetime = NumberRange.new(0.6, 1.2),
			Speed = NumberRange.new(1.5, 3),
			SpreadAngle = Vector2.new(25, 25),
			EmissionDirection = Enum.NormalId.Right,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1.4) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(Color3.fromRGB(150, 150, 150), Color3.fromRGB(90, 90, 90)),
			Acceleration = Vector3.new(0, 3, 0),
			Drag = 2,
			LightInfluence = 1,
			RotSpeed = NumberRange.new(-60, 60),
		})
	end
	if not s.dust and blade and blade:IsA("BasePart") then
		local a = Instance.new("Attachment")
		a.Name = "BarTip"
		a.Position = Vector3.new(0, -0.15, -blade.Size.Z * 0.5)
		a.Parent = blade
		s.dust = emitter(a, {
			Name = "Chips",
			Rate = 0,
			Lifetime = NumberRange.new(0.25, 0.5),
			Speed = NumberRange.new(8, 16),
			SpreadAngle = Vector2.new(30, 30),
			EmissionDirection = Enum.NormalId.Bottom,
			Size = NumberSequence.new(0.08),
			Color = ColorSequence.new(Color3.fromRGB(255, 210, 120)),
			LightEmission = 1,
			Acceleration = Vector3.new(0, -40, 0),
		})
	end
end

local function stop(s: Saw)
	if s.loop then
		local l = s.loop
		s.loop = nil
		task.spawn(function()
			for i = 1, 8 do
				if not l.Parent then
					return
				end
				l.Volume *= 0.7
				l.PlaybackSpeed *= 0.94
				task.wait(0.04)
			end
			l:Destroy()
		end)
	end
	for _, k in { "smoke", "dust" } do
		local e = (s :: any)[k]
		if e then
			local at = e.Parent
			e.Enabled = false
			task.delay(1.5, function()
				if at then
					at:Destroy()
				end
			end)
			;(s :: any)[k] = nil
		end
	end
end

local function step(dt: number)
	for m, s in saws do
		if not m.Parent then
			stop(s)
			saws[m] = nil
			continue
		end
		local on = m:GetAttribute("SawOn") == true
		if on and not s.loop then
			start(s)
		elseif not on and s.loop then
			stop(s)
		end
		if on and s.loop then
			-- revving while it bites (my saw: the controller knows; the others: a little random throttle)
			local biting = controller and controller.sawBiteT and os.clock() - controller.sawBiteT < 0.25
			local want = biting and 1 or 0
			s.rev += (want - s.rev) * math.min(1, dt * (biting and 12 or 4))
			local base = s.loop:GetAttribute("BaseSpeed") or 1.9
			s.loop.PlaybackSpeed = base * (1 + s.rev * 0.45) * (1 + math.sin(os.clock() * 31) * 0.015)
			s.loop.Volume = 0.65 + s.rev * 0.35
			if s.dust then
				s.dust.Rate = biting and 80 or 0
			end
			if s.smoke then
				s.smoke.Rate = 14 + s.rev * 30
			end
		end
	end
end

function ToolFX.Init()
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("Item") == "chainsaw" then
			track(d)
		end
	end
	workspace.DescendantAdded:Connect(function(d)
		if d:IsA("Model") then
			task.defer(track, d)
		end
	end)
	RunService.Heartbeat:Connect(step)
	Events.On("sawSpray", function(p)
		if typeof(p.p) ~= "Vector3" then
			return
		end
		local d = typeof(p.d) == "Vector3" and p.d or Vector3.yAxis
		BloodFX.Burst(p.p, -d + Vector3.new(0, 0.6, 0), 7, 20)
	end)
end

return ToolFX
