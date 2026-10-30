--!nonstrict
-- GoreService: wounds, fractures with bone splinters, severed stumps (skin / fat / muscle / bone /
-- marrow layers), decapitation, impalement, gibs, and blood + sound FX broadcasts.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local ContactSolver = require(Shared:WaitForChild("ContactSolver"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local FXRemote = Remotes:WaitForChild("FX") :: RemoteEvent

local GoreService = {}

local BLOOD_DARK = Color3.fromRGB(88, 5, 8)
local BLOOD = Color3.fromRGB(122, 11, 14)
local FLESH = Color3.fromRGB(176, 52, 54)
local FLESH_DARK = Color3.fromRGB(118, 24, 28)
local FAT = Color3.fromRGB(226, 196, 140)
local BONE = Color3.fromRGB(231, 223, 198)
local BONE_SHADE = Color3.fromRGB(205, 194, 164)
local MARROW = Color3.fromRGB(140, 30, 34)

local rng = Random.new()

local function getFolder(name: string): Folder
	local f = workspace:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = workspace
	end
	return f :: Folder
end

local function decorPart(name: string, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Reflectance = 0.1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function weldTo(p: BasePart, target: BasePart, cf: CFrame, folderName: string?)
	p.CFrame = cf
	local w = Instance.new("WeldConstraint")
	w.Part0 = target
	w.Part1 = p
	w.Parent = p
	p:SetAttribute("Gore", true)
	local holder = target:FindFirstChild(folderName or "Gore")
	if not holder then
		holder = Instance.new("Folder")
		holder.Name = folderName or "Gore"
		holder.Parent = target
	end
	p.Parent = holder
end

-- Visual size of a body region (the R6 head part is 2x1x1 but the mesh is ~1.25 cube)
local function visualSize(part: BasePart): Vector3
	if part.Name == "Head" then
		return Vector3.new(1.2, 1.2, 1.2)
	end
	return part.Size
end

-- Project a world point onto the nearest face of a part. Returns local point + local normal.
local function surfacePoint(part: BasePart, worldPoint: Vector3): (Vector3, Vector3)
	local size = visualSize(part)
	local half = size * 0.5
	local p = part.CFrame:PointToObjectSpace(worldPoint)
	local rx, ry, rz = math.abs(p.X) / half.X, math.abs(p.Y) / half.Y, math.abs(p.Z) / half.Z
	local function sgn(x: number): number
		return x < 0 and -1 or 1
	end
	local normal
	if rx >= ry and rx >= rz then
		normal = Vector3.new(sgn(p.X), 0, 0)
	elseif ry >= rz then
		normal = Vector3.new(0, sgn(p.Y), 0)
	else
		normal = Vector3.new(0, 0, sgn(p.Z))
	end
	local inset = 0.18
	local clamped = Vector3.new(
		math.clamp(p.X, -half.X + inset, half.X - inset),
		math.clamp(p.Y, -half.Y + inset, half.Y - inset),
		math.clamp(p.Z, -half.Z + inset, half.Z - inset)
	)
	clamped = clamped * (Vector3.one - Vector3.new(math.abs(normal.X), math.abs(normal.Y), math.abs(normal.Z)))
		+ Vector3.new(normal.X * half.X, normal.Y * half.Y, normal.Z * half.Z)
	return clamped, normal
end

------------------------------------------------------------------------
-- FX broadcasts (clients render blood and play sounds)
------------------------------------------------------------------------

function GoreService.FX(payload: { [string]: any })
	FXRemote:FireAllClients(payload)
end

function GoreService.Sound(name: string, where: BasePart | Vector3, volume: number?)
	GoreService.FX({ t = "sfx", n = name, w = where, v = volume or 1 })
end

function GoreService.Burst(position: Vector3, direction: Vector3, amount: number, speed: number?)
	GoreService.FX({ t = "burst", p = position, d = direction, n = math.clamp(math.floor(amount), 1, 60), s = speed or 18 })
end

function GoreService.Spurt(part: BasePart, localOffset: Vector3, localDir: Vector3, duration: number, strength: number?)
	GoreService.FX({ t = "spurt", part = part, o = localOffset, d = localDir, dur = duration, k = strength or 1 })
end

------------------------------------------------------------------------
-- bones
------------------------------------------------------------------------

-- A bone whose shaft starts at cf and points along cf's +X axis.
-- broken = jagged splintered end with marrow; otherwise a rounded joint end.
local function bone(target: BasePart, cf: CFrame, length: number, thick: number, broken: boolean)
	local shaft = decorPart("Bone", Vector3.new(length, thick, thick), BONE, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	shaft.Reflectance = 0.03
	weldTo(shaft, target, cf * CFrame.new(length * 0.5, 0, 0))
	local tipCF = cf * CFrame.new(length, 0, 0)
	if broken then
		-- marrow at the break
		local marrow = decorPart("Marrow", Vector3.new(0.03, thick * 0.62, thick * 0.62), MARROW, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		weldTo(marrow, target, tipCF * CFrame.new(0.005, 0, 0))
		-- jagged splinters sticking out of the break
		for i = 1, 4 do
			local a = (i / 4) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			local len = rng:NextNumber(0.1, 0.24)
			local shard = decorPart("Splinter", Vector3.new(len, thick * 0.18, thick * 0.3), i % 2 == 0 and BONE or BONE_SHADE)
			shard.Reflectance = 0
			local off = Vector3.new(0, math.cos(a) * thick * 0.38, math.sin(a) * thick * 0.38)
			local tilt = CFrame.Angles(a, 0, 0) * CFrame.Angles(0, rng:NextNumber(-0.25, 0.25), rng:NextNumber(-0.35, 0.35))
			weldTo(shard, target, tipCF * CFrame.new(off) * tilt * CFrame.new(len * 0.45, 0, 0))
		end
	else
		-- rounded joint end (two condyles)
		for _, z in { -1, 1 } do
			local knob = decorPart("BoneKnob", Vector3.new(thick * 1.25, thick * 1.25, thick * 1.25), BONE, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			knob.Reflectance = 0.03
			weldTo(knob, target, tipCF * CFrame.new(0, 0, z * thick * 0.3))
		end
	end
end

-- Open joint: skin edge, fat ring, muscle, bone and marrow. cf points X out of the body.
local function stump(target: BasePart, localCF: CFrame, diameter: number, boneLen: number)
	local cf = target.CFrame * localCF
	local layers = {
		{ name = "StumpSkin", d = diameter, t = 0.08, color = FLESH_DARK, off = 0 },
		{ name = "StumpFat", d = diameter * 0.9, t = 0.11, color = FAT, off = 0.005 },
		{ name = "StumpMuscle", d = diameter * 0.8, t = 0.14, color = FLESH, off = 0.01 },
	}
	for _, l in layers do
		local disc = decorPart(l.name, Vector3.new(l.t, l.d, l.d), l.color, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		disc.Reflectance = l.name == "StumpMuscle" and 0.18 or 0.06
		weldTo(disc, target, cf * CFrame.new(l.off, 0, 0))
	end
	-- a few torn flaps around the edge
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		local flap = decorPart("Flap", Vector3.new(0.12, 0.05, diameter * 0.28), FLESH_DARK)
		local r = diameter * 0.46
		weldTo(flap, target, cf * CFrame.new(0.05, math.cos(a) * r, math.sin(a) * r) * CFrame.Angles(a, 0, 0) * CFrame.Angles(0, 0, rng:NextNumber(-0.5, 0.5)))
	end
	bone(target, cf * CFrame.new(0.06, rng:NextNumber(-0.05, 0.05), rng:NextNumber(-0.05, 0.05)), boneLen, diameter * 0.32, true)
end

------------------------------------------------------------------------
-- wounds
------------------------------------------------------------------------

local function countWounds(part: BasePart): number
	local holder = part:FindFirstChild("Wounds")
	return holder and #holder:GetChildren() or 0
end

function GoreService.Wound(part: BasePart, worldPoint: Vector3, severity: number)
	if countWounds(part) >= Config.MaxWoundsPerLimb * 2 then
		return
	end
	local lp, ln = surfacePoint(part, worldPoint)
	local s = math.clamp(0.26 + severity * 0.34, 0.26, 0.62)
	local rot = MathUtil.RotationBetween(Vector3.yAxis, ln) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local base = part.CFrame * CFrame.new(lp + ln * 0.015) * rot

	local patch = decorPart("Wound", Vector3.new(s, 0.04, s * rng:NextNumber(0.55, 0.95)), BLOOD_DARK)
	weldTo(patch, part, base, "Wounds")
	if severity > 0.4 then
		local inner = decorPart("Wound", Vector3.new(s * 0.55, 0.08, s * 0.4), FLESH)
		inner.Reflectance = 0.2
		weldTo(inner, part, base * CFrame.new(rng:NextNumber(-0.05, 0.05), 0.03, rng:NextNumber(-0.05, 0.05)), "Wounds")
	end
	-- runs of blood dripping down from the wound
	if severity > 0.25 then
		local run = decorPart("Wound", Vector3.new(0.09, 0.03, s * rng:NextNumber(0.8, 1.6)), BLOOD)
		weldTo(run, part, base * CFrame.new(0, 0.01, s * 0.5), "Wounds")
	end
end

-- Bandage: white wrap around the middle of a body part (covers its wounds).
function GoreService.Bandage(part: BasePart)
	local holder = part:FindFirstChild("Bandages")
	if holder and #holder:GetChildren() >= 3 then
		return
	end
	local size = visualSize(part)
	local n = holder and #holder:GetChildren() or 0
	local y = (n - 1) * 0.42
	local wrap = decorPart("Bandage", Vector3.new(size.X + 0.06, 0.38, size.Z + 0.06), Color3.fromRGB(236, 232, 222), Enum.Material.Fabric)
	wrap.Reflectance = 0
	weldTo(wrap, part, part.CFrame * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-6, 6))), "Bandages")
	local stain = decorPart("Bandage", Vector3.new(0.3, 0.3, 0.02), Color3.fromRGB(150, 30, 30), Enum.Material.Fabric)
	stain.Reflectance = 0
	weldTo(stain, part, part.CFrame * CFrame.new(rng:NextNumber(-0.2, 0.2), y, -(size.Z * 0.5 + 0.04)), "Bandages")
end

-- Bullet hole: small dark entry wound.
function GoreService.BulletHole(part: BasePart, worldPoint: Vector3)
	local lp, ln = surfacePoint(part, worldPoint)
	local rot = MathUtil.RotationBetween(Vector3.yAxis, ln) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local base = part.CFrame * CFrame.new(lp + ln * 0.016) * rot
	local ring = decorPart("Wound", Vector3.new(0.03, 0.22, 0.22), BLOOD, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	weldTo(ring, part, base * CFrame.Angles(0, 0, math.pi / 2), "Wounds")
	local hole = decorPart("Wound", Vector3.new(0.04, 0.1, 0.1), Color3.fromRGB(25, 0, 0), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	weldTo(hole, part, base * CFrame.new(0, 0.005, 0) * CFrame.Angles(0, 0, math.pi / 2), "Wounds")
	local run = decorPart("Wound", Vector3.new(0.06, 0.025, rng:NextNumber(0.4, 0.9)), BLOOD)
	weldTo(run, part, base * CFrame.new(0, 0.005, 0.3), "Wounds")
end

-- (v2.0) exit wound: where a bullet came out again. Bigger and torn, with flesh showing.
function GoreService.ExitHole(part: BasePart, worldPoint: Vector3, power: number)
	if countWounds(part) >= Config.MaxWoundsPerLimb * 2 then
		return
	end
	local lp, ln = surfacePoint(part, worldPoint)
	local rot = MathUtil.RotationBetween(Vector3.yAxis, ln) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local base = part.CFrame * CFrame.new(lp + ln * 0.016) * rot
	local s = math.clamp(0.26 + power * 0.12, 0.28, 0.5)
	local torn = decorPart("Wound", Vector3.new(0.03, s, s * rng:NextNumber(0.8, 1.1)), BLOOD_DARK, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	weldTo(torn, part, base * CFrame.Angles(0, 0, math.pi / 2), "Wounds")
	local flesh = decorPart("Wound", Vector3.new(0.05, s * 0.55, s * 0.5), FLESH, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	flesh.Reflectance = 0.2
	weldTo(flesh, part, base * CFrame.new(0, 0.006, 0) * CFrame.Angles(0, 0, math.pi / 2), "Wounds")
	local hole = decorPart("Wound", Vector3.new(0.06, s * 0.3, s * 0.3), Color3.fromRGB(25, 0, 0), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	weldTo(hole, part, base * CFrame.new(0, 0.012, 0) * CFrame.Angles(0, 0, math.pi / 2), "Wounds")
	local run = decorPart("Wound", Vector3.new(0.08, 0.025, rng:NextNumber(0.5, 1.1)), BLOOD)
	weldTo(run, part, base * CFrame.new(0, 0.005, s * 0.6), "Wounds")
end

-- Fractured limb: wounds plus broken bone ends piercing out through the skin.
-- (v2.8.2) the broken bone ends are marked (attribute Fracture): healing pulls them back in (GoreService.Mend)
function GoreService.Crush(part: BasePart, worldPoint: Vector3)
	local gore = part:FindFirstChild("Gore")
	local before: { [Instance]: boolean } = {}
	if gore then
		for _, c in gore:GetChildren() do
			before[c] = true
		end
	end
	GoreService._crush(part, worldPoint)
	gore = part:FindFirstChild("Gore")
	if gore then
		for _, c in gore:GetChildren() do
			if not before[c] then
				c:SetAttribute("Fracture", true)
			end
		end
	end
end

-- (v2.8.2) HEALING: over `seconds` the broken bone ends sink back into the body part and shrink away, the wounds and
-- bullet holes fade and close (each screen closes its see-through holes itself: "mend").
function GoreService.Mend(part: BasePart, seconds: number?)
	local dur = seconds or 3
	if not part.Parent then
		return
	end
	local TweenService = game:GetService("TweenService")
	local info = TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local gore = part:FindFirstChild("Gore")
	if gore then
		for _, c in gore:GetChildren() do
			if c:IsA("BasePart") and c:GetAttribute("Fracture") == true then
				-- the fixed weld becomes a sliding one: the piece moves into the middle of the part as it heals
				local rel = part.CFrame:ToObjectSpace(c.CFrame)
				for _, w in c:GetChildren() do
					if w:IsA("WeldConstraint") then
						w:Destroy()
					end
				end
				local wd = Instance.new("Weld")
				wd.Part0 = part
				wd.Part1 = c
				wd.C0 = rel
				wd.Parent = c
				TweenService:Create(wd, info, { C0 = CFrame.new(rel.Position * 0.15) * rel.Rotation }):Play()
				TweenService:Create(c, info, { Size = c.Size * 0.45 }):Play()
				task.delay(dur, function()
					if c.Parent then
						c:Destroy()
					end
				end)
			end
		end
	end
	local wounds = part:FindFirstChild("Wounds")
	if wounds then
		for _, w in wounds:GetDescendants() do
			if w:IsA("BasePart") then
				TweenService:Create(w, info, { Transparency = 1 }):Play()
			elseif w:IsA("Decal") then
				TweenService:Create(w, info, { Transparency = 1 }):Play()
			end
		end
		task.delay(dur + 0.1, function()
			if wounds.Parent then
				wounds:Destroy()
			end
		end)
	end
	GoreService.FX({ t = "mend", part = part, s = dur })
end

function GoreService._crush(part: BasePart, worldPoint: Vector3)
	for _ = 1, 3 do
		local jitter = Vector3.new(rng:NextNumber(-0.5, 0.5), rng:NextNumber(-0.6, 0.6), rng:NextNumber(-0.5, 0.5))
		GoreService.Wound(part, worldPoint + jitter, 0.85)
	end
	local lp, ln = surfacePoint(part, worldPoint)
	local outward = MathUtil.RotationBetween(Vector3.xAxis, ln)
	for i = 1, 2 do
		local along = Vector3.new(0, (i - 1.5) * 0.35, 0)
		local tilt = CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(-0.5, 0.5), rng:NextNumber(-0.5, 0.5))
		bone(part, part.CFrame * CFrame.new(lp + along - ln * 0.12) * outward * tilt, rng:NextNumber(0.32, 0.5), 0.17, true)
	end
end

------------------------------------------------------------------------
-- severing
------------------------------------------------------------------------

local function destroyJoint(model: Model, key: string)
	local rig = model:FindFirstChild("Rig")
	local torso = model:FindFirstChild("Torso")
	if rig then
		for _, n in { "Joint_" .. key, "Muscle_" .. key } do
			local j = rig:FindFirstChild(n)
			if j then
				j:Destroy()
			end
		end
	end
	if torso then
		for _, n in { "J_" .. key, "M_" .. key } do
			local a = torso:FindFirstChild(n)
			if a then
				a:Destroy()
			end
		end
	end
end

local UP = CFrame.Angles(0, 0, math.pi / 2) -- X -> +Y
local DOWN = CFrame.Angles(0, 0, -math.pi / 2) -- X -> -Y
local LEFT = CFrame.Angles(0, math.pi, 0) -- X -> -X

function GoreService.Sever(model: Model, key: string)
	local def = RigInfo.ByKey[key]
	if not def then
		return
	end
	local torso = model:FindFirstChild("Torso") :: BasePart?
	local limb = model:FindFirstChild(def.partName) :: BasePart?
	if not torso or not limb then
		return
	end
	destroyJoint(model, key)
	-- any impale / grip constraints on this limb go too
	for _, c in limb:GetChildren() do
		if c:IsA("Constraint") and c.Name == "Impale" then
			c:Destroy()
		end
	end

	local side = def.side
	if def.kind == "Arm" then
		stump(torso, CFrame.new(side * 1.0, 0.45, 0) * (side < 0 and LEFT or CFrame.identity), 0.86, 0.34)
		stump(limb, CFrame.new(0, 1.0, 0) * UP, 0.86, 0.3)
		GoreService.Spurt(torso, Vector3.new(side * 1.1, 0.45, 0), Vector3.new(side, 0.25, 0), Config.BleedDuration * 0.4, 1.2)
	else
		stump(torso, CFrame.new(side * 0.5, -1.0, 0) * DOWN, 0.9, 0.36)
		stump(limb, CFrame.new(0, 1.0, 0) * UP, 0.9, 0.32)
		GoreService.Spurt(torso, Vector3.new(side * 0.5, -1.1, 0), Vector3.new(side * 0.2, -1, 0.1), Config.BleedDuration * 0.4, 1.3)
	end
	GoreService.Spurt(limb, Vector3.new(0, 1.1, 0), Vector3.new(0, 1, 0), 3.5, 0.7)
	GoreService.Burst(torso.CFrame:PointToWorldSpace(def.torsoPivot), torso.CFrame:VectorToWorldSpace(Vector3.new(side, 0.3, 0)), 45, 26)
	GoreService.Sound("gore", torso, 1)
	GoreService.Sound("boneCrack", torso, 1)
	pcall(function()
		limb:ApplyImpulse((torso.CFrame:VectorToWorldSpace(Vector3.new(side, 0.6, 0)) * 10 + Vector3.new(0, 8, 0)) * limb.AssemblyMass)
	end)
end

function GoreService.Decapitate(model: Model)
	local torso = model:FindFirstChild("Torso") :: BasePart?
	local head = model:FindFirstChild("Head") :: BasePart?
	if not torso or not head then
		return
	end
	for _, holder in { torso, head } do
		local neck = holder:FindFirstChild("Neck")
		if neck then
			neck:Destroy()
		end
	end
	stump(torso, CFrame.new(0, 1.0, 0) * UP, 0.78, 0.4)
	stump(head, CFrame.new(0, -0.58, 0) * DOWN, 0.72, 0.18)
	GoreService.Spurt(torso, Vector3.new(0, 1.1, 0), Vector3.new(0, 1, 0.15), Config.BleedDuration * 0.5, 1.6)
	GoreService.Spurt(head, Vector3.new(0, -0.6, 0), Vector3.new(0, -1, 0), 3, 0.7)
	GoreService.Burst(head.Position, Vector3.new(0, 1, 0), 55, 28)
	GoreService.Sound("gore", head, 1.1)
	GoreService.Sound("boneCrack", head, 1)
	pcall(function()
		head:ApplyImpulse(Vector3.new(rng:NextNumber(-12, 12), 22, rng:NextNumber(-12, 12)) * head.AssemblyMass)
	end)
end

------------------------------------------------------------------------
-- impalement: the body part sticks on the spike
------------------------------------------------------------------------

function GoreService.Impale(part: BasePart, spike: BasePart, worldPoint: Vector3, quiet: boolean?)
	if part:FindFirstChild("Impale") then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "ImpaleA"
	a0.WorldPosition = worldPoint
	a0.Parent = part
	a0.WorldPosition = worldPoint
	local a1 = Instance.new("Attachment")
	a1.Name = "ImpaleB_" .. part.Name
	a1.Parent = spike
	a1.WorldPosition = worldPoint
	local socket = Instance.new("BallSocketConstraint")
	socket.Name = "Impale"
	socket.Attachment0 = a0
	socket.Attachment1 = a1
	socket.MaxFrictionTorque = 400
	socket.Parent = part
	local body = part:FindFirstAncestorOfClass("Model")
	if body then
		ContactSolver.PassThrough(body, spike, worldPoint, socket)
	end
	if quiet then
		return
	end
	GoreService.Wound(part, worldPoint, 1.1)
	GoreService.Wound(part, worldPoint + Vector3.new(0.1, -0.2, 0), 0.8)
	GoreService.Burst(worldPoint, Vector3.yAxis, 35, 14)
	GoreService.Sound("stab", worldPoint, 1)
	GoreService.Sound("gore", worldPoint, 0.7)
	GoreService.Spurt(part, part.CFrame:PointToObjectSpace(worldPoint), Vector3.new(0, 1, 0), 6, 0.6)
end

function GoreService.Unimpale(part: BasePart)
	for _, c in part:GetChildren() do
		if c.Name == "Impale" or c.Name == "ImpaleA" then
			local a1 = c:IsA("BallSocketConstraint") and c.Attachment1
			if a1 then
				a1:Destroy()
			end
			c:Destroy()
		end
	end
	GoreService.Burst(part.Position, Vector3.yAxis, 25, 12)
	GoreService.Sound("gore", part, 0.6)
end

------------------------------------------------------------------------
-- gibs
------------------------------------------------------------------------

function GoreService.Gibs(position: Vector3, count: number, power: number)
	local folder = getFolder("Gibs")
	if #folder:GetChildren() > 80 then
		return
	end
	for i = 1, count do
		local g
		if i % 3 == 0 then
			-- a small bone fragment
			g = Instance.new("Part")
			g.Shape = Enum.PartType.Cylinder
			g.Size = Vector3.new(rng:NextNumber(0.3, 0.55), 0.14, 0.14)
			g.Color = BONE
		else
			local s = rng:NextNumber(0.25, 0.55)
			g = Instance.new("Part")
			g.Size = Vector3.new(s, s * rng:NextNumber(0.5, 1), s * rng:NextNumber(0.6, 1.2))
			g.Color = rng:NextNumber() < 0.5 and FLESH or BLOOD
		end
		g.Name = "Gib"
		g.Material = Enum.Material.SmoothPlastic
		g.Reflectance = 0.15
		g.TopSurface = Enum.SurfaceType.Smooth
		g.BottomSurface = Enum.SurfaceType.Smooth
		g.CFrame = CFrame.new(position + Vector3.new(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 0.6), rng:NextNumber(-0.5, 0.5)))
			* CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
		g.CustomPhysicalProperties = PhysicalProperties.new(1, 0.8, 0.05, 1, 1)
		g.CanTouch = false
		g:SetAttribute("Gore", true)
		g.Parent = folder
		g.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.4, 1.2), rng:NextNumber(-1, 1)) * power
		g.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(-10, 10), rng:NextNumber(-10, 10))
		Debris:AddItem(g, 25)
		GoreService.FX({ t = "trail", part = g, dur = 1.2 })
	end
end

return GoreService
