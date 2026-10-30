--!nonstrict
-- CraneService: keeps the crane's wrecking ball (20+ t) swinging side to side.
-- The ball is a real pendulum (hinge on the jib, rigid cable); the server simulates it and only
-- tops up its energy when it gets slower than the target swing (e.g. after hitting someone).
-- Walk into its path and you get hit by it like by any other heavy object (kinetic energy) and
-- on top of that you are launched far away along its swing.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local DamageService = require(script.Parent:WaitForChild("DamageService"))
local GoreService = require(script.Parent:WaitForChild("GoreService"))

local CraneService = {}

local CABLE = 39 -- pivot to the top of the ball
local RADIUS = 3

-- cable + ball + hinge are made here (a real pendulum under the crane's trolley)
local function build(crane: Instance, pivotAtt: Attachment): (BasePart, HingeConstraint)
	local pivot = pivotAtt.WorldPosition
	local cable = Instance.new("Part")
	cable.Name = "Cable"
	cable.Shape = Enum.PartType.Cylinder
	cable.Size = Vector3.new(CABLE, 0.3, 0.3)
	cable.CFrame = CFrame.new(pivot - Vector3.new(0, CABLE / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	cable.Color = Color3.fromRGB(34, 34, 36)
	cable.Material = Enum.Material.Metal
	cable.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.3, 0, 1, 1)
	cable.CanCollide = false
	cable.Parent = crane
	local ball = Instance.new("Part")
	ball.Name = "WreckingBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(RADIUS * 2, RADIUS * 2, RADIUS * 2)
	ball.CFrame = CFrame.new(pivot - Vector3.new(0, CABLE + RADIUS, 0))
	ball.Color = Color3.fromRGB(46, 46, 50)
	ball.Material = Enum.Material.CorrodedMetal
	-- 113 stud^3 at density 30 = ~3400 RMU = ~26 t
	ball.CustomPhysicalProperties = PhysicalProperties.new(30, 0.4, 0.05, 1, 1)
	ball.Parent = crane
	local hook = Instance.new("Part")
	hook.Name = "Hook"
	hook.Size = Vector3.new(1.2, 1.0, 1.2)
	hook.CFrame = CFrame.new(pivot - Vector3.new(0, CABLE + 0.2, 0))
	hook.Color = Color3.fromRGB(226, 178, 38)
	hook.Material = Enum.Material.Metal
	hook.CanCollide = false
	hook.Parent = crane
	for _, p in { cable, hook } do
		local w = Instance.new("WeldConstraint")
		w.Part0 = ball
		w.Part1 = p
		w.Parent = p
	end
	local top = Instance.new("Attachment")
	top.Name = "CableTop"
	top.Parent = cable
	top.WorldCFrame = pivotAtt.WorldCFrame
	local hinge = Instance.new("HingeConstraint")
	hinge.Name = "CraneHinge"
	hinge.Attachment0 = pivotAtt
	hinge.Attachment1 = top
	hinge.Parent = crane
	return ball, hinge
end

function CraneService.Init()
	local map = workspace:FindFirstChild("Map")
	local crane = map and map:FindFirstChild("Crane")
	local trolley = crane and crane:FindFirstChild("Trolley")
	local pivotAtt = trolley and trolley:FindFirstChild("CranePivot")
	if not crane or not pivotAtt or not pivotAtt:IsA("Attachment") then
		return
	end
	local ball, _hinge = build(crane, pivotAtt)
	-- the server keeps swinging it: players who grab it hang on (force), they do not take it over
	ball:SetAttribute("NoOwnershipGrab", true)
	for _, d in crane:GetDescendants() do
		if d:IsA("BasePart") and not d.Anchored then
			pcall(function()
				d:SetNetworkOwner(nil)
			end)
		end
	end
	local amp = math.rad(Config.WreckingSwing)
	-- whoever the ball hits is launched (the push of a 26 t ball, not only a bump)
	local hitAt: { [Model]: number } = {}
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { crane }
	overlap.RespectCanCollide = false
	local function launchBodies()
		local v = ball.AssemblyLinearVelocity
		local speed = v.Magnitude
		if speed < 8 then
			return
		end
		local now = os.clock()
		for _, p in workspace:GetPartBoundsInRadius(ball.Position, RADIUS + 1.3, overlap) do
			local body = DamageService.BodyOf(p)
			if body and now - (hitAt[body] or 0) > 1 then
				hitAt[body] = now
				local flat = Vector3.new(v.X, 0, v.Z)
				flat = flat.Magnitude > 0.1 and flat.Unit or v.Unit
				DamageService.Blast(body, flat * speed * Config.WreckingLaunch + Vector3.new(0, speed * Config.WreckingLaunch * 0.45, 0), 3)
				GoreService.Sound("heavyHit", ball.Position, 1)
			end
		end
		for m, t in hitAt do
			if now - t > 3 or not m.Parent then
				hitAt[m] = nil
			end
		end
	end
	-- start it swinging
	task.delay(1, function()
		local axis = pivotAtt.WorldCFrame.RightVector
		local arm = ball.Position - pivotAtt.WorldPosition
		local tangent = axis:Cross(arm)
		if tangent.Magnitude > 0.01 then
			ball.AssemblyLinearVelocity = tangent.Unit * 30
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		if not ball.Parent then
			return
		end
		launchBodies()
		local pivot = pivotAtt.WorldPosition
		local arm = ball.Position - pivot
		local L = arm.Magnitude
		local g = workspace.Gravity
		local v = ball.AssemblyLinearVelocity
		local energy = 0.5 * v.Magnitude ^ 2 + g * (ball.Position.Y - (pivot.Y - L))
		local target = g * L * (1 - math.cos(amp))
		local mass = ball.AssemblyMass
		if energy < target * 0.97 then
			local dir: Vector3
			if v.Magnitude > 0.5 then
				dir = v.Unit
			else
				local axis = pivotAtt.WorldCFrame.RightVector
				local t = axis:Cross(arm)
				dir = t.Magnitude > 0.01 and t.Unit or Vector3.xAxis
			end
			ball:ApplyImpulse(dir * mass * 26 * dt)
		elseif energy > target * 1.1 and v.Magnitude > 0.5 then
			ball:ApplyImpulse(-v.Unit * mass * 14 * dt)
		end
	end)
end

return CraneService
