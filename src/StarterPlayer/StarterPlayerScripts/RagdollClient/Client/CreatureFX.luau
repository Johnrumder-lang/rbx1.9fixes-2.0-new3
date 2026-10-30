--!nonstrict
-- CreatureFX (v2.0): the creatures as everybody sees them. The server only moves an invisible hit box
-- (CreatureService); here each one gets its body, glides smoothly after the hit box and is animated:
--   crawler : a long pale thing on six spider legs (it walks on whatever it is on - floor, wall, ceiling), a long
--             neck and a head that is mostly jaw. The jaw opens when it eats. It skitters, it growls.
--   shark   : grey back, white belly, a fin that cuts the surface, a tail that beats. Dead: belly up.
-- Also: "grabbed" (only to the one the Crawler holds: your body is held at its jaws), "ungrab", "bloodwater".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))

local Events = require(script.Parent:WaitForChild("Events"))
local Cam = require(script.Parent:WaitForChild("CameraController"))

local player = Players.LocalPlayer

local CreatureFX = {}

local controller = nil

function CreatureFX.SetController(c)
	controller = c
end

type Leg = { hip: Vector3, home: Vector3, foot: Vector3, upper: BasePart, lower: BasePart, phase: number, len1: number, len2: number }
type Vis = {
	kind: string,
	model: Model,
	src: Model,
	cf: CFrame,
	parts: { [string]: BasePart },
	offsets: { [BasePart]: CFrame },
	legs: { Leg },
	walk: number,
	lastPos: Vector3,
	skitter: Sound?,
	nextGrowl: number,
	jaw: number,
	deadT: number?,
}

local visuals: { [Model]: Vis } = {}

local function vpart(m: Model, name: string, size: Vector3, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = m
	return p
end

local function fxFolder(): Instance
	return workspace:FindFirstChild("FX") or workspace
end

------------------------------------------------------------------------
-- building them
------------------------------------------------------------------------

-- (v2.0) the Crawler, much bigger and much worse: an emaciated pale body (a spine of knuckled vertebrae with spikes,
-- a ribcage you can count, the guts dark behind the ribs, a bony pelvis), four long limbs that bend the wrong way and
-- end in hands with long black claws, two small withered arms under the chest that twitch, and a long neck to a
-- skull that is mostly mouth: a lower jaw that drops open, needle teeth in rows, six red eyes.
-- Every limb is a two-bone chain solved each frame (IK) to a foot planted on whatever surface it is on; the feet
-- step in diagonal pairs. The neck turns the head to whoever it hunts; the ribs breathe; the spine sways.
local SKIN = Color3.fromRGB(176, 166, 154)
local SKIN_DARK = Color3.fromRGB(126, 112, 104)
local BONE = Color3.fromRGB(214, 206, 186)
local GUT = Color3.fromRGB(70, 22, 26)
local CLAW = Color3.fromRGB(24, 20, 20)
local GUM = Color3.fromRGB(110, 24, 30)
local EYE = Color3.fromRGB(255, 34, 20)

type Limb = {
	hip: Vector3, -- (body space)
	home: Vector3, -- where its foot wants to be (body space, on the surface)
	foot: Vector3, -- world
	from: Vector3,
	to: Vector3,
	t: number, -- 1 = planted
	group: number, -- 1 / 2: the diagonal pairs step in turn
	len1: number,
	len2: number,
	upper: BasePart,
	lower: BasePart,
	joint: BasePart,
	hand: BasePart,
	fingers: { BasePart },
	front: boolean,
	side: number,
}

local function buildCrawler(src: Model): Vis
	local m = Instance.new("Model")
	m.Name = "CrawlerFX"
	local parts: { [string]: BasePart } = {}
	local offsets: { [BasePart]: CFrame } = {}
	local count = 0
	local function add(name: string, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?)
		count += 1
		local p = vpart(m, name, size, color, mat, shape)
		parts[name .. "#" .. count] = p
		offsets[p] = off
		return p
	end
	local function addNamed(name: string, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?)
		local p = vpart(m, name, size, color, mat, shape)
		parts[name] = p
		offsets[p] = off
		return p
	end
	local CYL_Z = CFrame.Angles(0, math.rad(90), 0)
	-- the spine: knuckled vertebrae from the pelvis to the shoulders, a spike on each
	for i = 0, 8 do
		local z = 4.2 - i * 0.95
		local y = 0.9 + math.sin(i / 8 * math.pi) * 0.35
		add("Vertebra", Vector3.new(0.9, 0.95, 0.95), CFrame.new(0, y, z) * CYL_Z, BONE, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		add("Spike", Vector3.new(0.16, 0.7 - math.abs(i - 4) * 0.06, 0.34), CFrame.new(0, y + 0.6, z + 0.12) * CFrame.Angles(math.rad(-28), 0, 0), BONE)
	end
	-- a bony tail behind the pelvis (it lashes about)
	for i = 1, 6 do
		addNamed("Tail" .. i, Vector3.new(0.9, 0.75 - i * 0.08, 0.75 - i * 0.08), CFrame.new(0, 0.6 - i * 0.12, 4.6 + i * 0.85) * CYL_Z, i % 2 == 0 and BONE or SKIN_DARK, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end
	addNamed("Tail7", Vector3.new(0.14, 0.14, 1.2), CFrame.new(0, -0.3, 10.4), CLAW)
	-- the pelvis and the hips
	add("Pelvis", Vector3.new(2.2, 2.2, 2.2), CFrame.new(0, 0.55, 4.0), SKIN_DARK, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	for _, sx in { -1, 1 } do
		add("HipBone", Vector3.new(1.3, 1.3, 1.3), CFrame.new(sx * 1.15, 0.5, 3.8), SKIN, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	-- the gut behind the ribs, the ribs (each an arc of two bones), the breastbone
	addNamed("Gut", Vector3.new(2.7, 2.7, 2.7), CFrame.new(0, 0.25, -0.6), GUT, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	addNamed("Belly", Vector3.new(2.1, 2.1, 2.1), CFrame.new(0, 0.2, 1.6), SKIN_DARK, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	for i = 0, 5 do
		local z = -2.0 + i * 0.55
		local r = 1.45 - math.abs(i - 2.2) * 0.12
		for _, sx in { -1, 1 } do
			local top = Vector3.new(sx * 0.4, 1.05, z)
			local side = Vector3.new(sx * r, 0.35, z + 0.1)
			local low = Vector3.new(sx * 0.35, -0.55, z + 0.25)
			for k, seg in { { top, side }, { side, low } } do
				local a1, b1 = seg[1], seg[2]
				local mid = (a1 + b1) / 2
				local cf = CFrame.lookAt(mid, b1) * CYL_Z
				add("Rib" .. k, Vector3.new((b1 - a1).Magnitude + 0.1, 0.2, 0.2), cf, BONE, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
			end
		end
	end
	add("Sternum", Vector3.new(0.4, 0.2, 3.2), CFrame.new(0, -0.6, -0.65), BONE)
	-- the shoulders
	for _, sx in { -1, 1 } do
		add("Shoulder", Vector3.new(1.4, 1.4, 1.4), CFrame.new(sx * 1.35, 0.75, -2.0), SKIN, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		add("ShoulderBlade", Vector3.new(1.0, 0.15, 1.3), CFrame.new(sx * 0.85, 1.25, -1.7) * CFrame.Angles(0, 0, sx * -0.35), BONE)
	end
	-- the neck: three segments, turned by the head's aim (stepCrawler)
	for i = 1, 3 do
		addNamed("Neck" .. i, Vector3.new(1.3, 0.85, 0.85), CFrame.new(0, 1.0 + i * 0.18, -2.4 - i * 1.0) * CYL_Z, SKIN, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		addNamed("NeckSpike" .. i, Vector3.new(0.14, 0.5, 0.28), CFrame.new(0, 1.55 + i * 0.18, -2.3 - i * 1.0) * CFrame.Angles(math.rad(-30), 0, 0), BONE)
	end
	-- the head (all parts named "H..." move with the head; "J..." with the lower jaw)
	addNamed("HSkull", Vector3.new(1.7, 1.7, 1.7), CFrame.new(0, 1.95, -6.1), SKIN, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	addNamed("HSnout", Vector3.new(1.35, 0.8, 2.0), CFrame.new(0, 1.75, -7.2), SKIN)
	addNamed("HBrow", Vector3.new(1.6, 0.3, 0.6), CFrame.new(0, 2.25, -6.85) * CFrame.Angles(math.rad(12), 0, 0), SKIN_DARK)
	addNamed("HGumU", Vector3.new(1.25, 0.18, 1.9), CFrame.new(0, 1.32, -7.25), GUM)
	for i = 0, 7 do
		for _, sx in { -1, 1 } do
			local z = -6.5 - i * 0.24
			local x = sx * (0.55 - i * 0.035)
			addNamed("HToothU" .. i .. sx, Vector3.new(0.07, 0.38 - i * 0.015, 0.07), CFrame.new(x, 1.12, z) * CFrame.Angles(0, 0, sx * 0.1), BONE)
		end
	end
	for _, f in { -0.2, 0.2 } do
		addNamed("HFang" .. f, Vector3.new(0.1, 0.62, 0.1), CFrame.new(f, 1.05, -8.15), BONE)
	end
	for k, e in { { 0.5, 2.05, -7.0, 0.24 }, { 0.36, 2.25, -6.7, 0.18 }, { 0.62, 1.82, -6.6, 0.15 } } do
		for _, sx in { -1, 1 } do
			local ep = addNamed("HEye" .. k .. sx, Vector3.new(e[4], e[4], e[4]), CFrame.new(sx * e[1], e[2], e[3]), EYE, Enum.Material.Neon, Enum.PartType.Ball)
			if k == 1 then
				local l = Instance.new("PointLight")
				l.Color = EYE
				l.Range = 9
				l.Brightness = 1.6
				l.Parent = ep
			end
		end
	end
	-- the lower jaw (hinged at the back of the skull)
	addNamed("JJaw", Vector3.new(1.2, 0.32, 2.1), CFrame.new(0, 0.82, -7.15), SKIN_DARK)
	addNamed("JGum", Vector3.new(1.1, 0.12, 1.9), CFrame.new(0, 0.98, -7.15), GUM)
	addNamed("JTongue", Vector3.new(0.5, 0.14, 1.6), CFrame.new(0, 1.04, -7.0), Color3.fromRGB(150, 50, 60))
	for i = 0, 6 do
		for _, sx in { -1, 1 } do
			addNamed("JTooth" .. i .. sx, Vector3.new(0.07, 0.32, 0.07), CFrame.new(sx * (0.5 - i * 0.035), 1.15, -6.55 - i * 0.24), BONE)
		end
	end

	-- the four long limbs (front: arms from the shoulders; back: legs from the hips) and the two small arms
	local limbs: { Limb } = {}
	local function makeLimb(side: number, front: boolean, hip: Vector3, home: Vector3, len1: number, len2: number, thick: number, group: number): Limb
		local upper = vpart(m, "LimbUpper", Vector3.new(len1, thick, thick), SKIN, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		local lower = vpart(m, "LimbLower", Vector3.new(len2, thick * 0.8, thick * 0.8), SKIN_DARK, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		local joint = vpart(m, "LimbJoint", Vector3.new(thick * 1.25, thick * 1.25, thick * 1.25), BONE, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		local hand = vpart(m, "Hand", Vector3.new(0.75, 0.22, 0.8), SKIN_DARK)
		local fingers: { BasePart } = {}
		for _ = 1, 4 do
			table.insert(fingers, vpart(m, "Claw", Vector3.new(0.12, 0.12, 1.05), CLAW))
		end
		return {
			hip = hip,
			home = home,
			foot = Vector3.zero,
			from = Vector3.zero,
			to = Vector3.zero,
			t = 1,
			group = group,
			len1 = len1,
			len2 = len2,
			upper = upper,
			lower = lower,
			joint = joint,
			hand = hand,
			fingers = fingers,
			front = front,
			side = side,
		}
	end
	for _, sx in { -1, 1 } do
		-- diagonal pairs: front left with back right (group 1), front right with back left (group 2)
		table.insert(limbs, makeLimb(sx, true, Vector3.new(sx * 1.5, 0.6, -2.0), Vector3.new(sx * 4.4, -2.1, -5.0), 3.2, 3.6, 0.5, sx < 0 and 1 or 2))
		table.insert(limbs, makeLimb(sx, false, Vector3.new(sx * 1.3, 0.4, 3.8), Vector3.new(sx * 4.6, -2.1, 5.8), 3.4, 3.7, 0.58, sx < 0 and 2 or 1))
	end
	local small = {}
	for _, sx in { -1, 1 } do
		table.insert(small, {
			side = sx,
			upper = vpart(m, "SmallArm", Vector3.new(1.3, 0.22, 0.22), SKIN, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder),
			lower = vpart(m, "SmallArm", Vector3.new(1.2, 0.18, 0.18), SKIN_DARK, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder),
			claw = vpart(m, "SmallClaw", Vector3.new(0.09, 0.09, 0.6), CLAW),
		})
	end
	-- dig debris (thrown while it claws through a wall)
	local digAtt = Instance.new("Attachment")
	local gutPart = parts["Gut"]
	digAtt.Parent = gutPart
	local debris = Instance.new("ParticleEmitter")
	debris.Texture = "rbxasset://textures/particles/smoke_main.dds"
	debris.Color = ColorSequence.new(Color3.fromRGB(150, 140, 128))
	debris.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.4) })
	debris.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	debris.Lifetime = NumberRange.new(0.6, 1.2)
	debris.Speed = NumberRange.new(6, 14)
	debris.SpreadAngle = Vector2.new(50, 50)
	debris.Acceleration = Vector3.new(0, -30, 0)
	debris.Rate = 0
	debris.Parent = digAtt

	m.Parent = fxFolder()
	local v: any = {
		kind = "crawler",
		model = m,
		src = src,
		cf = src.PrimaryPart and src.PrimaryPart.CFrame or CFrame.new(),
		parts = parts,
		offsets = offsets,
		legs = limbs,
		small = small,
		walk = 0,
		lastPos = src.PrimaryPart and src.PrimaryPart.Position or Vector3.zero,
		skitter = nil,
		nextGrowl = os.clock() + 4,
		jaw = 0,
		aimYaw = 0,
		aimPitch = 0,
		squeeze = 0,
		digAtt = digAtt,
		debris = debris,
		lastState = "",
		group = 1,
	}
	for _, L in limbs do
		L.foot = v.cf:PointToWorldSpace(L.home)
		L.from = L.foot
		L.to = L.foot
	end
	local root = src.PrimaryPart
	if root then
		local sk = SoundLibrary.Loop("monsterSkitter", root)
		if sk then
			sk.Volume = 0
			sk:Play()
			v.skitter = sk
		end
	end
	return v
end

local function buildShark(src: Model): Vis
	local m = Instance.new("Model")
	m.Name = "SharkFX"
	local parts: { [string]: BasePart } = {}
	local offsets: { [BasePart]: CFrame } = {}
	local grey = Color3.fromRGB(104, 114, 126)
	local belly = Color3.fromRGB(226, 228, 230)
	local function add(name: string, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?)
		local p = vpart(m, name, size, color, mat, shape)
		parts[name] = p
		offsets[p] = off
		return p
	end
	add("Body", Vector3.new(2.2, 2, 5.4), CFrame.new(0, 0, 0), grey)
	add("Belly", Vector3.new(2.0, 0.6, 5.0), CFrame.new(0, -0.75, 0), belly)
	add("Snout", Vector3.new(1.8, 1.6, 2.4), CFrame.new(0, 0.05, -3.4), grey, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	add("Mouth", Vector3.new(1.3, 0.2, 0.9), CFrame.new(0, -0.55, -3.5), Color3.fromRGB(150, 50, 50))
	add("Tail1", Vector3.new(1.4, 1.3, 2.2), CFrame.new(0, 0.1, 3.6), grey)
	add("Tail2", Vector3.new(0.8, 0.8, 1.6), CFrame.new(0, 0.15, 5.3), grey)
	add("TailFin", Vector3.new(0.2, 3, 1.2), CFrame.new(0, 0.5, 6.3) * CFrame.Angles(math.rad(-20), 0, 0), grey)
	add("Fin", Vector3.new(0.22, 1.9, 1.6), CFrame.new(0, 1.7, -0.3) * CFrame.Angles(math.rad(-28), 0, 0), Color3.fromRGB(90, 98, 110))
	add("FinL", Vector3.new(2.0, 0.15, 1.1), CFrame.new(-1.6, -0.6, -1.0) * CFrame.Angles(0, 0, math.rad(-20)), grey)
	add("FinR", Vector3.new(2.0, 0.15, 1.1), CFrame.new(1.6, -0.6, -1.0) * CFrame.Angles(0, 0, math.rad(20)), grey)
	for _, sx in { -0.75, 0.75 } do
		add("Eye" .. sx, Vector3.new(0.2, 0.2, 0.2), CFrame.new(sx, 0.3, -3.6), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	m.Parent = fxFolder()
	return {
		kind = "shark",
		model = m,
		src = src,
		cf = src.PrimaryPart and src.PrimaryPart.CFrame or CFrame.new(),
		parts = parts,
		offsets = offsets,
		legs = {},
		walk = 0,
		lastPos = src.PrimaryPart and src.PrimaryPart.Position or Vector3.zero,
		skitter = nil,
		nextGrowl = 0,
		jaw = 0,
	}
end

------------------------------------------------------------------------
-- animating them
------------------------------------------------------------------------

local legParams = RaycastParams.new()
legParams.FilterType = Enum.RaycastFilterType.Exclude
legParams.RespectCanCollide = true

-- two-bone IK: the knee / elbow between `a` and `c` with bone lengths l1, l2, bent towards `pole`
local function solveIK(a: Vector3, c: Vector3, l1: number, l2: number, pole: Vector3): Vector3
	local d = c - a
	local dist = math.clamp(d.Magnitude, 0.05, l1 + l2 - 0.02)
	local dir = d.Magnitude > 0.01 and d.Unit or Vector3.yAxis
	local along = (dist * dist + l1 * l1 - l2 * l2) / (2 * dist)
	local h = math.sqrt(math.max(l1 * l1 - along * along, 0))
	local bend = pole - dir * pole:Dot(dir)
	bend = bend.Magnitude > 0.01 and bend.Unit or Vector3.yAxis
	return a + dir * along + bend * h
end

local function placeCyl(p: BasePart, a: Vector3, b: Vector3)
	local d = b - a
	local len = d.Magnitude
	if len < 0.05 then
		return
	end
	p.Size = Vector3.new(len, p.Size.Y, p.Size.Z)
	p.CFrame = CFrame.lookAt((a + b) * 0.5, b) * CFrame.Angles(0, math.rad(90), 0)
end

local function stepCrawler(v: any, dt: number, now: number)
	local root = v.src.PrimaryPart
	if not root then
		return
	end
	local target = root.CFrame
	local dead = v.src:GetAttribute("Dead") == true
	local state = v.src:GetAttribute("State") or "roam"
	if dead then
		v.deadT = v.deadT or now
		-- it curls up and sinks
		local k = math.clamp((now - (v.deadT :: number)) / 1.5, 0, 1)
		target = target * CFrame.new(0, -1.2 * k, 0) * CFrame.Angles(0, 0, math.rad(150) * k)
	end
	if state ~= v.lastState then
		if state == "pounce" then
			SoundLibrary.Play("monsterLeap", root, 1)
		elseif state == "dig" then
			SoundLibrary.Play("monsterDig", root, 1)
		end
		v.lastState = state
	end
	local moved = (root.Position - v.lastPos).Magnitude
	v.lastPos = root.Position
	-- (v2.0 fix) it jumped somewhere (dug through, slipped out, landed): the feet come along instead of staying
	-- behind and stretching the legs
	local airborne = state == "pounce" or state == "fall"
	local wasAir = v.wasAir == true
	v.wasAir = airborne or state == "dig"
	if moved > 6 or (wasAir and not v.wasAir) then
		v.resetFeet = true
	end
	local speed = moved / math.max(dt, 1e-3)
	v.walk += moved
	-- squeezing through a gap: flat and narrow
	local wantSq = v.src:GetAttribute("Squeeze") == true and 1 or 0
	v.squeeze += (wantSq - v.squeeze) * math.min(1, dt * 8)
	local sq = v.squeeze
	-- the body bobs with the gait and sways along the spine
	local bob = math.sin(v.walk * 1.1) * 0.12 * math.clamp(speed / 10, 0, 1)
	v.cf = v.cf:Lerp(target, 1 - math.exp(-dt * 14))
	local cf = v.cf * CFrame.new(0, bob - sq * 0.9, 0)
	-- the head aims at whoever is closest in front of it (players' heads)
	local aimYaw, aimPitch = 0, 0
	local best = 70
	for _, p in Players:GetPlayers() do
		local h = p.Character and p.Character:FindFirstChild("Head")
		if h and h:IsA("BasePart") then
			local lp = cf:PointToObjectSpace(h.Position)
			local d = lp.Magnitude
			if d < best and lp.Z < 2 then
				best = d
				aimYaw = math.clamp(math.atan2(-lp.X, -lp.Z), -1.0, 1.0)
				aimPitch = math.clamp(math.atan2(lp.Y - 1.8, math.sqrt(lp.X * lp.X + lp.Z * lp.Z)), -0.6, 0.7)
			end
		end
	end
	if state == "dig" then
		aimYaw, aimPitch = math.sin(now * 9) * 0.25, -0.15
	end
	v.aimYaw += (aimYaw - v.aimYaw) * math.min(1, dt * 5)
	v.aimPitch += (aimPitch - v.aimPitch) * math.min(1, dt * 5)
	-- the jaw: wide while it eats / screams on a leap, chattering while it hunts
	local wantJaw = (state == "eat" or state == "pounce") and 1 or (state == "chase" and 0.3 + 0.2 * math.sin(now * 13) or (state == "dig" and 0.5 or 0.06))
	v.jaw += (wantJaw - v.jaw) * math.min(1, dt * 9)
	-- head pivot: the base of the neck; the head turns round it, the jaw hinges at the back of the skull
	local neckBase = CFrame.new(0, 1.1, -2.2)
	local headTurn = neckBase * CFrame.Angles(0, v.aimYaw, 0) * CFrame.Angles(v.aimPitch, 0, 0) * neckBase:Inverse()
	local hinge = CFrame.new(0, 1.2, -6.3)
	-- (v2.0 fix) the lower jaw drops DOWN (a positive angle swung it up into the skull)
	local jawCF = hinge * CFrame.Angles(-math.rad(55) * v.jaw, 0, 0) * hinge:Inverse()
	local breathe = 1 + math.sin(now * 2.6) * 0.04
	for p, off in v.offsets do
		if not p.Parent then
			continue
		end
		local n = p.Name
		local o = off
		local c1 = string.sub(n, 1, 1)
		if c1 == "H" and string.sub(n, 1, 2) ~= "Hi" then
			o = headTurn * off
		elseif c1 == "J" then
			o = headTurn * jawCF * off
		elseif string.sub(n, 1, 4) == "Neck" then
			local i = tonumber(string.sub(n, -1)) or 1
			local k = i / 3
			local turn = neckBase * CFrame.Angles(0, v.aimYaw * k, 0) * CFrame.Angles(v.aimPitch * k, 0, 0) * neckBase:Inverse()
			o = turn * off
		elseif string.sub(n, 1, 4) == "Tail" then
			continue -- (the tail is a chain: below)
		elseif n == "Gut" or n == "Belly" then
			p.Size = Vector3.one * (n == "Gut" and 2.7 or 2.1) * breathe
		else
			-- the spine sways side to side along its length
			local z = off.Position.Z
			o = CFrame.Angles(0, math.sin(now * 2 + z * 0.5) * 0.03, 0) * off
		end
		if sq > 0.01 then
			-- (squeezing: pressed flat)
			local pos = o.Position
			o = CFrame.new(pos.X * (1 - 0.35 * sq), pos.Y * (1 - 0.55 * sq), pos.Z) * (o - pos)
		end
		p.CFrame = cf * o
	end
	-- the tail: a chain of segments, each turned a little more than the one before (it lashes)
	do
		local at = CFrame.new(0, 0.55, 4.5)
		for i = 1, 7 do
			local seg = v.parts["Tail" .. i]
			if not seg then
				break
			end
			local yaw = math.sin(now * 3.2 - i * 0.7) * 0.22 + math.sin(now * 1.1 + i) * 0.08
			local pitch = -0.08 + math.sin(now * 2.3 - i) * 0.06
			at = at * CFrame.Angles(pitch, yaw, 0)
			local len = i == 7 and 1.2 or 0.85
			seg.CFrame = cf * at * CFrame.new(0, 0, len * 0.5) * (i == 7 and CFrame.new() or CFrame.Angles(0, math.rad(90), 0))
			at = at * CFrame.new(0, 0, len)
		end
	end
	-- the limbs: plant, step in diagonal pairs, IK
	local fx = workspace:FindFirstChild("FX")
	legParams.FilterDescendantsInstances = { v.model, v.src, fx or v.model, player.Character or v.src }
	local up = cf.UpVector
	local stepDist = 2.4 + math.clamp(speed / 12, 0, 1) * 2.2
	local stepTime = math.clamp(0.32 - speed * 0.008, 0.12, 0.32)
	local anyStepping = { false, false }
	for _, L in v.legs do
		if L.t < 1 then
			anyStepping[L.group] = true
		end
	end
	local resetFeet = v.resetFeet == true
	v.resetFeet = false
	for _, L in v.legs do
		local lead = math.clamp(speed / 20, 0, 1) * 1.6
		local homeLocal = L.home + Vector3.new(0, 0, -lead)
		if sq > 0.01 then
			homeLocal = Vector3.new(homeLocal.X * (1 - 0.4 * sq), homeLocal.Y, homeLocal.Z)
		end
		local home = cf:PointToWorldSpace(homeLocal)
		local hit = workspace:Raycast(home + up * 3.5, -up * 7, legParams)
		if hit then
			home = hit.Position
		end
		if dead then
			L.foot = L.foot:Lerp(cf:PointToWorldSpace(Vector3.new(L.hip.X * 0.5, 2.0, L.hip.Z)), math.min(1, dt * 3))
			L.t = 1
		elseif state == "dig" and L.front then
			-- clawing at the wall in front of it, the two arms in turn
			local ph = now * 11 + (L.side > 0 and math.pi or 0)
			local reach = cf:PointToWorldSpace(Vector3.new(L.side * 1.2, 0.6 + math.sin(ph) * 1.4, -6.4 - math.max(0, math.cos(ph)) * 1.2))
			L.foot = L.foot:Lerp(reach, math.min(1, dt * 20))
			L.t = 1
		elseif state == "pounce" or state == "fall" then
			-- in the air: limbs thrown forward, claws out
			local reachOut = cf:PointToWorldSpace(Vector3.new(L.side * 3.2, L.front and 0.5 or -1.5, L.front and -5.5 or 4.5))
			L.foot = L.foot:Lerp(reachOut, math.min(1, dt * 10))
			L.t = 1
		elseif resetFeet then
			-- (a quick step of every foot to where it belongs now)
			L.from = L.foot
			L.to = home
			L.t = 0.35
		elseif (L.foot - cf:PointToWorldSpace(L.hip)).Magnitude > (L.len1 + L.len2) * 0.98 and L.t >= 1 then
			-- (v2.0 fix) out of reach: this foot steps now, whatever the other pair does
			L.from = L.foot
			L.to = home
			L.t = 0
		elseif L.t < 1 then
			L.t = math.min(1, L.t + dt / stepTime)
			local e = L.t * L.t * (3 - 2 * L.t)
			L.foot = L.from:Lerp(L.to, e) + up * math.sin(L.t * math.pi) * math.min(1.6, (L.to - L.from).Magnitude * 0.45)
			if L.t >= 1 then
				L.foot = L.to
				SoundLibrary.Play("monsterStep", L.foot, 0.35 + math.clamp(speed / 30, 0, 0.5))
			end
		elseif (L.foot - home).Magnitude > stepDist and not anyStepping[3 - L.group] then
			L.from = L.foot
			L.to = home
			L.t = 0
			anyStepping[L.group] = true
		end
		-- the bones: the elbow / knee bends up and out (wrong for a body like this - that is the point)
		local hip = cf:PointToWorldSpace(L.hip)
		local pole = up * 1.6 + cf.RightVector * L.side * 0.8 + cf.LookVector * (L.front and 0.6 or -0.6)
		-- (v2.0 fix) the drawn foot is never further from the hip than the leg is long (no stretched shin)
		local foot = L.foot
		local reach = L.len1 + L.len2 - 0.03
		if (foot - hip).Magnitude > reach then
			foot = hip + (foot - hip).Unit * reach
		end
		local knee = solveIK(hip, foot, L.len1, L.len2, pole)
		placeCyl(L.upper, hip, knee)
		placeCyl(L.lower, knee, foot)
		L.joint.CFrame = CFrame.new(knee)
		local fwd = (foot - knee)
		fwd = Vector3.new(fwd.X, 0, fwd.Z).Magnitude > 0.05 and (foot - knee).Unit or cf.LookVector
		local handCF = CFrame.lookAt(foot, foot + fwd, up)
		L.hand.CFrame = handCF * CFrame.new(0, 0.05, -0.2)
		for i, f in L.fingers do
			local spread = (i - 2.5) * 0.28
			f.CFrame = handCF * CFrame.new(spread * 0.9, -0.05, -0.75) * CFrame.Angles(math.rad(-25), spread, 0)
		end
	end
	-- the two small arms under the chest: they twitch and grasp
	for _, a in v.small do
		local sh = cf:PointToWorldSpace(Vector3.new(a.side * 0.6, -0.6, -1.4))
		local tw = math.sin(now * 7 + a.side) * 0.4 + math.sin(now * 13.3) * 0.15
		local el = cf:PointToWorldSpace(Vector3.new(a.side * (1.0 + tw * 0.3), -1.4, -2.1))
		local hd = cf:PointToWorldSpace(Vector3.new(a.side * (0.5 + tw * 0.2), -1.5 + tw * 0.3, -3.1))
		placeCyl(a.upper, sh, el)
		placeCyl(a.lower, el, hd)
		a.claw.CFrame = CFrame.lookAt(hd, hd + (hd - el).Unit) * CFrame.new(0, 0, -0.25)
	end
	-- digging: dust and chunks off the wall
	if v.debris then
		v.debris.Rate = state == "dig" and 40 or 0
		if v.digAtt then
			v.digAtt.WorldPosition = cf:PointToWorldSpace(Vector3.new(0, 0.8, -6.6))
		end
	end
	-- sound
	if v.skitter then
		v.skitter.Volume = dead and 0 or math.clamp(speed / 18, 0, 1) * 0.5
		v.skitter.PlaybackSpeed = (v.skitter:GetAttribute("BaseSpeed") or 3) * (0.8 + math.clamp(speed / 20, 0, 1) * 0.4)
	end
	if not dead and now > v.nextGrowl then
		v.nextGrowl = now + math.random(4, 9)
		SoundLibrary.Play(math.random() < 0.3 and "monsterScreech" or "monsterGrowl", root, 0.6, 0.85 + math.random() * 0.3)
	end
	if v.src:GetAttribute("Despawn") then
		-- (v2.0) the round is over: it fades away
		v.goneT = v.goneT or now
		local k = math.clamp((now - (v.goneT :: number)) / 1.2, 0, 1)
		for _, p in v.model:GetDescendants() do
			if p:IsA("BasePart") then
				p.Transparency = math.max(p.Transparency, k)
			elseif p:IsA("Light") then
				p.Enabled = k < 0.5
			end
		end
		if v.skitter then
			v.skitter.Volume = 0
		end
	end
	if dead and now - (v.deadT or now) > 3 then
		for _, p in v.model:GetDescendants() do
			if p:IsA("BasePart") then
				p.Transparency = math.clamp((now - (v.deadT :: number) - 3) / 3, 0, 1)
			end
		end
	end
end

local function stepShark(v: Vis, dt: number, now: number)
	local root = v.src.PrimaryPart
	if not root then
		return
	end
	v.cf = v.cf:Lerp(root.CFrame, 1 - math.exp(-dt * 10))
	local cf = v.cf
	local moved = (root.Position - v.lastPos).Magnitude
	v.lastPos = root.Position
	local speed = moved / math.max(dt, 1e-3)
	v.walk += dt * (3 + speed * 0.35)
	local dead = v.src:GetAttribute("Dead") == true
	local wag = dead and 0 or math.sin(v.walk) * 0.35
	for p, off in v.offsets do
		if p.Parent then
			local o = off
			local n = p.Name
			if n == "Tail1" then
				o = CFrame.new(0, 0, 2.5) * CFrame.Angles(0, wag * 0.6, 0) * CFrame.new(0, 0, -2.5) * off
			elseif n == "Tail2" or n == "TailFin" then
				o = CFrame.new(0, 0, 2.5) * CFrame.Angles(0, wag, 0) * CFrame.new(0, 0, -2.5) * off
			elseif n == "Mouth" then
				local open = v.src:GetAttribute("State") == "hunt" and 0.25 or 0
				o = off * CFrame.new(0, -open, 0)
			end
			p.CFrame = cf * o
		end
	end
end

------------------------------------------------------------------------
-- held by the Crawler (only the one it holds gets this)
------------------------------------------------------------------------

local held: { part: BasePart, off: Vector3, untilT: number }? = nil

local function onGrabbed(p: any)
	if typeof(p.part) ~= "Instance" or not p.part:IsA("BasePart") or typeof(p.off) ~= "Vector3" then
		return
	end
	local d = typeof(p.d) == "number" and p.d or 2
	held = { part = p.part, off = p.off, untilT = os.clock() + d + 0.3 }
	if controller and controller.ready and not controller.dead then
		controller:Ragdoll(d + 1.2)
	end
	Cam.Shake(1.2)
	SoundLibrary.Play("heartbeat", nil, 1)
end

local function bloodWater(pos: Vector3)
	local a = Instance.new("Part")
	a.Name = "BloodWater"
	a.Size = Vector3.new(1, 1, 1)
	a.Transparency = 1
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.CanTouch = false
	a.CFrame = CFrame.new(pos)
	a.Parent = fxFolder()
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(150, 10, 10))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 9) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(3, 5)
	e.Speed = NumberRange.new(0.5, 2)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 1.5
	e.Rate = 0
	e.Parent = a
	e:Emit(26)
	task.delay(6, function()
		a:Destroy()
	end)
end

------------------------------------------------------------------------

function CreatureFX.Init()
	Events.On("grabbed", onGrabbed)
	Events.On("ungrab", function(p)
		if p.body == player.Character then
			held = nil
		end
	end)
	Events.On("bloodwater", function(p)
		if typeof(p.p) == "Vector3" then
			bloodWater(p.p)
		end
	end)
	RunService.Heartbeat:Connect(function()
		local h = held
		if not h then
			return
		end
		local c = controller
		if os.clock() > h.untilT or not h.part.Parent or not c or not c.ready or c.dead then
			held = nil
			return
		end
		local target = h.part.CFrame:PointToWorldSpace(h.off)
		pcall(function()
			local to = target - c.torso.Position
			local v = to * 12
			if v.Magnitude > 80 then
				v = v.Unit * 80
			end
			c.torso.AssemblyLinearVelocity = v
		end)
	end)
	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local f = workspace:FindFirstChild("Creatures")
		if f then
			for _, m in f:GetChildren() do
				if m:IsA("Model") and not visuals[m] and m.PrimaryPart then
					local kind = m:GetAttribute("Creature")
					if kind == "crawler" then
						visuals[m] = buildCrawler(m)
					elseif kind == "shark" then
						visuals[m] = buildShark(m)
					end
				end
			end
		end
		for m, v in visuals do
			if not m.Parent then
				v.model:Destroy()
				if v.skitter then
					v.skitter:Destroy()
				end
				visuals[m] = nil
				continue
			end
			-- (only what is near enough to see is animated)
			local cam = workspace.CurrentCamera
			local root = m.PrimaryPart
			if cam and root and (cam.CFrame.Position - root.Position).Magnitude > 600 then
				continue
			end
			local ok, err = pcall(v.kind == "crawler" and stepCrawler or stepShark, v, math.min(dt, 1 / 20), now)
			if not ok then
				warn("[creature fx]", err)
			end
		end
	end)
end

return CreatureFX
