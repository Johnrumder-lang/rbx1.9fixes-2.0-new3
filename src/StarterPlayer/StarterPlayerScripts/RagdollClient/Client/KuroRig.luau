--!nonstrict
-- KuroRig (v2.1c): Kuro, the shikigami of the Black Ledger. A tall figure in a black coat with leather-brown straps, belt, bracers and boots -
-- no glowing parts at all. He WALKS (legs, arms, a little lean), his head turns to look at you, his jaw moves when he talks, he blinks.
-- Built from ~200 plain parts, drawn only on the keeper's screen.
-- KuroRig.new() -> rig;  KuroRig.Update(rig, dt, rootCF, lookAt, speak, move);  KuroRig.SetFade(rig, 0..1);  KuroRig.Burst(rig);  KuroRig.Destroy(rig)
--   rootCF = where his feet are (on the ground), facing where he looks;  move = 0 (standing) .. 1 (walking) .. 2 (running)

local KuroRig = {}

local BLACK = Color3.fromRGB(9, 8, 10)
local BLACK2 = Color3.fromRGB(18, 16, 18)
local SHEEN = Color3.fromRGB(26, 22, 26)
local LEATHER = Color3.fromRGB(96, 60, 34)
local LEATHER_D = Color3.fromRGB(62, 38, 22)
local LEATHER_L = Color3.fromRGB(124, 82, 48)
local BONE = Color3.fromRGB(226, 220, 204)
local TOOTH = Color3.fromRGB(236, 233, 222)
local EYE = Color3.fromRGB(240, 238, 230)

local okLeather, leatherMat = pcall(function()
	return Enum.Material.Leather
end)
local LEATHER_MAT: Enum.Material = okLeather and leatherMat or Enum.Material.Fabric

type Entry = { part: BasePart, bone: string, off: CFrame, base: number }
export type Rig = {
	model: Model, head: BasePart, entries: { Entry }, eyes: { { part: BasePart, size: Vector3 } }, aura: BasePart, burst: ParticleEmitter,
	parts: { BasePart }, cfs: { CFrame }, blinkAt: number, speak: number, fade: number, alive: boolean, phase: number, amt: number,
}

local function mkPart(model: Model, name: string, size: Vector3, color: Color3, mat: Enum.Material?, ellipsoid: boolean?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if ellipsoid then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	p.Parent = model
	return p
end

function KuroRig.new(): Rig
	local model = Instance.new("Model")
	model.Name = "Kuro"
	local entries: { Entry } = {}
	local eyes = {}
	local function add(p: BasePart, bone: string, off: CFrame?)
		table.insert(entries, { part = p, bone = bone, off = off or CFrame.identity, base = p.Transparency })
		return p
	end
	local R = math.rad
	local THIGH, SHIN = 1.35, 1.35

	------------------------------------------------------------------ legs: thigh, shin, a leather boot
	for _, s in { -1, 1 } do
		local n = s == -1 and "L" or "R"
		add(mkPart(model, "Thigh", Vector3.new(0.62, THIGH, 0.66), BLACK2, Enum.Material.Fabric), "th" .. n, CFrame.new(0, -THIGH / 2, 0))
		add(mkPart(model, "Knee", Vector3.new(0.5, 0.5, 0.5), LEATHER_D, LEATHER_MAT, true), "sn" .. n, CFrame.new(0, 0.05, 0))
		add(mkPart(model, "Shin", Vector3.new(0.5, SHIN, 0.54), BLACK, Enum.Material.Fabric), "sn" .. n, CFrame.new(0, -SHIN / 2, 0))
		add(mkPart(model, "ThighStrap", Vector3.new(0.7, 0.14, 0.74), LEATHER, LEATHER_MAT), "th" .. n, CFrame.new(0, -0.55, 0))
		add(mkPart(model, "ThighBuckle", Vector3.new(0.16, 0.18, 0.06), LEATHER_L, Enum.Material.Metal), "th" .. n, CFrame.new(0, -0.55, -0.4))
		add(mkPart(model, "BootShaft", Vector3.new(0.62, 0.8, 0.66), LEATHER, LEATHER_MAT), "sn" .. n, CFrame.new(0, -SHIN + 0.35, 0))
		add(mkPart(model, "BootCuff", Vector3.new(0.7, 0.14, 0.74), LEATHER_L, LEATHER_MAT), "sn" .. n, CFrame.new(0, -SHIN + 0.8, 0))
		add(mkPart(model, "BootStrap", Vector3.new(0.66, 0.1, 0.7), LEATHER_D, LEATHER_MAT), "sn" .. n, CFrame.new(0, -SHIN + 0.5, 0))
		add(mkPart(model, "Foot", Vector3.new(0.64, 0.42, 1.2), LEATHER, LEATHER_MAT), "ft" .. n, CFrame.new(0, -0.2, -0.28))
		add(mkPart(model, "Sole", Vector3.new(0.68, 0.1, 1.26), BLACK, Enum.Material.SmoothPlastic), "ft" .. n, CFrame.new(0, -0.4, -0.28))
	end

	------------------------------------------------------------------ body: hip, chest, straps, belt, collar
	add(mkPart(model, "Hips", Vector3.new(1.4, 0.8, 0.9), BLACK, Enum.Material.Fabric), "hip", CFrame.new(0, 0.05, 0))
	add(mkPart(model, "Belt", Vector3.new(1.5, 0.28, 1.0), LEATHER, LEATHER_MAT), "hip", CFrame.new(0, 0.5, 0))
	add(mkPart(model, "BeltPlate", Vector3.new(0.3, 0.3, 0.06), LEATHER_L, Enum.Material.Metal), "hip", CFrame.new(0, 0.5, -0.53))
	for _, x in { -0.62, 0.62 } do
		add(mkPart(model, "Pouch", Vector3.new(0.4, 0.5, 0.3), LEATHER_D, LEATHER_MAT), "hip", CFrame.new(x, 0.1, -0.5))
		add(mkPart(model, "PouchFlap", Vector3.new(0.42, 0.18, 0.32), LEATHER, LEATHER_MAT), "hip", CFrame.new(x, 0.3, -0.5))
	end
	-- a dagger on his hip in a leather sheath
	add(mkPart(model, "Sheath", Vector3.new(0.22, 1.2, 0.3), LEATHER_D, LEATHER_MAT), "hip", CFrame.new(0.88, -0.45, 0.15) * CFrame.Angles(0, 0, math.rad(-12)))
	add(mkPart(model, "SheathTip", Vector3.new(0.26, 0.14, 0.34), LEATHER_L, Enum.Material.Metal), "hip", CFrame.new(0.78, -1.05, 0.15) * CFrame.Angles(0, 0, math.rad(-12)))
	add(mkPart(model, "DaggerHilt", Vector3.new(0.16, 0.5, 0.16), LEATHER, LEATHER_MAT), "hip", CFrame.new(0.99, 0.35, 0.15) * CFrame.Angles(0, 0, math.rad(-12)))
	add(mkPart(model, "DaggerGuard", Vector3.new(0.4, 0.08, 0.14), BLACK, Enum.Material.Metal), "hip", CFrame.new(0.96, 0.08, 0.15) * CFrame.Angles(0, 0, math.rad(-12)))
	add(mkPart(model, "Chest", Vector3.new(2.0, 2.0, 1.05), BLACK2, Enum.Material.Fabric), "chest")
	-- the shoulder mantle: a wide black collar of three layers over the shoulders, with a leather edge
	add(mkPart(model, "Mantle1", Vector3.new(3.3, 0.3, 1.5), BLACK, Enum.Material.Fabric), "chest", CFrame.new(0, 1.02, 0.05))
	add(mkPart(model, "Mantle2", Vector3.new(3.7, 0.26, 1.7), BLACK2, Enum.Material.Fabric), "chest", CFrame.new(0, 0.82, 0.05))
	add(mkPart(model, "Mantle3", Vector3.new(4.0, 0.22, 1.9), BLACK, Enum.Material.Fabric), "chest", CFrame.new(0, 0.64, 0.05))
	add(mkPart(model, "MantleEdge", Vector3.new(4.06, 0.08, 1.96), LEATHER, LEATHER_MAT), "chest", CFrame.new(0, 0.5, 0.05))
	add(mkPart(model, "Neck", Vector3.new(0.6, 0.7, 0.6), BLACK2, Enum.Material.Fabric), "chest", CFrame.new(0, 1.2, 0.05))
	-- two leather straps crossing the chest, with a ring where they meet
	add(mkPart(model, "StrapA", Vector3.new(0.24, 2.4, 0.1), LEATHER, LEATHER_MAT), "chest", CFrame.new(0, 0, -0.55) * CFrame.Angles(0, 0, R(32)))
	add(mkPart(model, "StrapB", Vector3.new(0.24, 2.4, 0.1), LEATHER_D, LEATHER_MAT), "chest", CFrame.new(0, 0, -0.56) * CFrame.Angles(0, 0, R(-32)))
	add(mkPart(model, "StrapRing", Vector3.new(0.12, 0.42, 0.42), LEATHER_L, Enum.Material.Metal), "chest", CFrame.new(0, 0, -0.62) * CFrame.Angles(0, R(90), 0))
	for _, s in { -1, 1 } do
		add(mkPart(model, "Collar", Vector3.new(0.18, 1.7, 1.1), BLACK2, Enum.Material.Fabric), "chest", CFrame.new(s * 0.95, 1.5, 0.45) * CFrame.Angles(R(-12), 0, R(s * -22)))
		add(mkPart(model, "CollarTrim", Vector3.new(0.06, 1.7, 0.1), LEATHER, LEATHER_MAT), "chest", CFrame.new(s * 0.88, 1.5, -0.08) * CFrame.Angles(R(-12), 0, R(s * -22)))
	end

	------------------------------------------------------------------ head
	local head = mkPart(model, "Head", Vector3.new(1.7, 2.0, 1.7), BLACK, Enum.Material.SmoothPlastic, true)
	add(head, "head", CFrame.new(0, 0.8, 0))
	local function surfZ(x: number, y: number): number
		local k = 1 - (x / 0.85) ^ 2 - ((y - 0.8) / 1.0) ^ 2
		return -0.85 * math.sqrt(math.max(0.04, k))
	end
	for _, s in { -1, 1 } do
		local eye = mkPart(model, "Eye", Vector3.new(0.5, 0.2, 0.14), EYE, Enum.Material.SmoothPlastic, true)
		add(eye, "head", CFrame.new(s * 0.42, 1.02, surfZ(0.42, 1.02) + 0.04) * CFrame.Angles(0, R(s * 14), R(s * 22)))
		table.insert(eyes, { part = eye, size = eye.Size })
		add(mkPart(model, "Socket", Vector3.new(0.78, 0.52, 0.3), Color3.fromRGB(2, 2, 3), Enum.Material.SmoothPlastic, true), "head", CFrame.new(s * 0.42, 1.02, surfZ(0.42, 1.02) + 0.08) * CFrame.Angles(0, R(s * 14), R(s * 22)))
		add(mkPart(model, "Pupil", Vector3.new(0.1, 0.2, 0.05), BLACK, Enum.Material.SmoothPlastic), "head", CFrame.new(s * 0.42, 1.02, surfZ(0.42, 1.02) - 0.02) * CFrame.Angles(0, R(s * 14), R(s * 22)))
		add(mkPart(model, "Brow", Vector3.new(0.72, 0.18, 0.34), BLACK2, Enum.Material.SmoothPlastic), "head", CFrame.new(s * 0.44, 1.3, surfZ(0.44, 1.3) + 0.1) * CFrame.Angles(0, R(s * 14), R(s * -18)))
		add(mkPart(model, "Cheek", Vector3.new(0.5, 0.65, 0.3), Color3.fromRGB(3, 3, 4), Enum.Material.SmoothPlastic, true), "head", CFrame.new(s * 0.52, 0.55, surfZ(0.52, 0.55) + 0.08))
	end
	for _, s in { -1, 1 } do
		add(mkPart(model, "Nostril", Vector3.new(0.07, 0.2, 0.06), Color3.fromRGB(2, 2, 3), Enum.Material.SmoothPlastic), "head", CFrame.new(s * 0.1, 0.62, surfZ(0.1, 0.62) - 0.01) * CFrame.Angles(0, 0, R(s * 12)))
	end
	for i = -4, 4 do
		local x = i * 0.135
		local y = 0.3 + 0.28 * (x / 0.55) ^ 2
		add(mkPart(model, "Tooth", Vector3.new(0.1, (i % 2 == 0) and 0.26 or 0.2, 0.07), TOOTH, Enum.Material.SmoothPlastic), "head", CFrame.new(x, y, surfZ(x, y) + 0.01) * CFrame.Angles(0, R(x * -35), 0))
	end
	add(mkPart(model, "Jaw", Vector3.new(1.18, 0.32, 0.9), BLACK, Enum.Material.SmoothPlastic), "jaw", CFrame.new(0, -0.2, -0.32))
	for i = -3, 3 do
		local x = i * 0.13
		add(mkPart(model, "LowTooth", Vector3.new(0.09, (i % 2 == 0) and 0.2 or 0.15, 0.065), TOOTH, Enum.Material.SmoothPlastic), "jaw", CFrame.new(x, 0.02, -0.58 + 0.45 * (x / 0.6) ^ 2 * 0.3))
	end
	for _, s in { -1, 1 } do
		local cf = CFrame.new(s * 0.55, 1.6, 0.0) * CFrame.Angles(R(-8), 0, R(s * -26))
		for k = 0, 4 do
			local w = 0.26 - k * 0.04
			add(mkPart(model, "Horn", Vector3.new(w, 0.78, w), (k % 2 == 0) and BLACK or SHEEN, Enum.Material.SmoothPlastic), "head", cf * CFrame.new(0, 0.37, 0))
			cf = cf * CFrame.new(0, 0.72, 0) * CFrame.Angles(R(-7), 0, R(s * -13))
		end
	end

	------------------------------------------------------------------ arms: sleeve, leather bracer, hand with claw fingers
	for _, s in { -1, 1 } do
		local n = s == -1 and "L" or "R"
		add(mkPart(model, "Shoulder", Vector3.new(0.95, 0.75, 0.95), BLACK2, Enum.Material.Fabric, true), "sh" .. n)
		add(mkPart(model, "Pauldron", Vector3.new(1.05, 0.34, 1.05), LEATHER, LEATHER_MAT), "sh" .. n, CFrame.new(s * 0.1, 0.38, 0) * CFrame.Angles(0, 0, R(s * -10)))
		add(mkPart(model, "PauldronEdge", Vector3.new(1.1, 0.08, 1.1), LEATHER_D, LEATHER_MAT), "sh" .. n, CFrame.new(s * 0.1, 0.18, 0) * CFrame.Angles(0, 0, R(s * -10)))
		add(mkPart(model, "UpperArm", Vector3.new(0.4, 1.4, 0.4), BLACK2, Enum.Material.Fabric), "sh" .. n, CFrame.new(0, -0.7, 0))
		add(mkPart(model, "Forearm", Vector3.new(0.34, 1.4, 0.34), BLACK, Enum.Material.Fabric), "el" .. n, CFrame.new(0, -0.7, 0))
		add(mkPart(model, "Bracer", Vector3.new(0.46, 0.8, 0.46), LEATHER, LEATHER_MAT), "el" .. n, CFrame.new(0, -0.9, 0))
		add(mkPart(model, "BracerStrapA", Vector3.new(0.5, 0.08, 0.5), LEATHER_D, LEATHER_MAT), "el" .. n, CFrame.new(0, -0.7, 0))
		add(mkPart(model, "BracerStrapB", Vector3.new(0.5, 0.08, 0.5), LEATHER_D, LEATHER_MAT), "el" .. n, CFrame.new(0, -1.1, 0))
		add(mkPart(model, "Palm", Vector3.new(0.56, 0.5, 0.26), BLACK, Enum.Material.SmoothPlastic), "ha" .. n, CFrame.new(0, -0.25, 0))
		for j = 0, 4 do
			for k = 1, (j == 4 and 2 or 3) do
				local len = (k == 1 and 0.46) or (k == 2 and 0.42) or 0.38
				local isTip = k == (j == 4 and 2 or 3)
				add(mkPart(model, "Finger", Vector3.new(0.09 - k * 0.012, len, 0.09 - k * 0.012), isTip and BONE or BLACK, isTip and Enum.Material.SmoothPlastic or Enum.Material.SmoothPlastic), "f" .. n .. j .. k, CFrame.new(0, -len / 2, 0))
			end
		end
	end

	------------------------------------------------------------------ folded wings (black feathers) and a long coat that moves with him
	for _, s in { -1, 1 } do
		local n = s == -1 and "L" or "R"
		for i = 1, 7 do
			local len = 2.4 + (i - 1) * 0.2
			add(mkPart(model, "Feather", Vector3.new(len, 0.3, 0.05), (i % 2 == 0) and BLACK or SHEEN, Enum.Material.SmoothPlastic), "wg" .. n .. i, CFrame.new(s * len / 2, 0, 0))
			add(mkPart(model, "FeatherTip", Vector3.new(0.21, 0.21, 0.05), (i % 2 == 0) and BLACK or SHEEN, Enum.Material.SmoothPlastic), "wg" .. n .. i, CFrame.new(s * (len + 0.03), 0, 0) * CFrame.Angles(0, 0, R(45)))
		end
	end
	for i = 0, 7 do
		for k = 1, 2 do
			local seg = 0.95
			add(mkPart(model, "Coat", Vector3.new(0.62 - k * 0.08, seg, 0.07), BLACK, Enum.Material.Fabric), "ct" .. i .. k, CFrame.new(0, -seg / 2, 0))
		end
		add(mkPart(model, "CoatHem", Vector3.new(0.5, 0.08, 0.09), LEATHER_D, LEATHER_MAT), "ct" .. i .. 2, CFrame.new(0, -0.9, 0))
	end
	for i = 1, 5 do
		for k = 1, 2 do
			add(mkPart(model, "Cape", Vector3.new(0.5 - k * 0.04, 1.1, 0.06), (i % 2 == 0) and BLACK or BLACK2, Enum.Material.Fabric), "cp" .. i .. k, CFrame.new(0, -0.55, 0))
		end
		add(mkPart(model, "CapeHem", Vector3.new(0.46, 0.08, 0.08), LEATHER_D, LEATHER_MAT), "cp" .. i .. 2, CFrame.new(0, -1.08, 0))
	end
	for i = 1, 5 do
		for k = 1, 3 do
			add(mkPart(model, "Hair", Vector3.new(0.2 - k * 0.04, 0.95, 0.12), BLACK, Enum.Material.SmoothPlastic), "hr" .. i .. k, CFrame.new(0, -0.47, 0))
		end
	end

	------------------------------------------------------------------ a little dark smoke at his feet (the only effect)
	local aura = mkPart(model, "Aura", Vector3.new(3.6, 6.8, 3.6), BLACK)
	aura.Transparency = 1
	local cloud = Instance.new("ParticleEmitter")
	cloud.Name = "Cloud"
	cloud.Texture = "rbxasset://textures/particles/smoke_main.dds"
	cloud.Color = ColorSequence.new(Color3.fromRGB(6, 6, 8), Color3.fromRGB(26, 24, 28))
	cloud.Shape = Enum.ParticleEmitterShape.Box
	cloud.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	cloud.Rate = 34
	cloud.Lifetime = NumberRange.new(2.4, 3.8)
	cloud.Speed = NumberRange.new(0.2, 0.9)
	cloud.SpreadAngle = Vector2.new(180, 180)
	cloud.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(0.5, 4.2), NumberSequenceKeypoint.new(1, 5.2) })
	cloud.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.55), NumberSequenceKeypoint.new(0.75, 0.7), NumberSequenceKeypoint.new(1, 1) })
	cloud.Rotation = NumberRange.new(0, 360)
	cloud.RotSpeed = NumberRange.new(-20, 20)
	cloud.Acceleration = Vector3.new(0, 0.7, 0)
	cloud.Drag = 1.2
	cloud.LockedToPart = false
	cloud.Parent = aura
	local fog = Instance.new("ParticleEmitter")
	fog.Name = "Fog"
	fog.Texture = "rbxasset://textures/particles/smoke_main.dds"
	fog.Color = ColorSequence.new(Color3.fromRGB(8, 8, 10))
	fog.Shape = Enum.ParticleEmitterShape.Disc
	fog.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	fog.Rate = 14
	fog.Lifetime = NumberRange.new(2, 3)
	fog.Speed = NumberRange.new(0.5, 1.6)
	fog.SpreadAngle = Vector2.new(90, 90)
	fog.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 4.5) })
	fog.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.6), NumberSequenceKeypoint.new(1, 1) })
	fog.LockedToPart = false
	fog.Parent = aura
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(14, 12, 14))
	smoke.Rate = 10
	smoke.Lifetime = NumberRange.new(1.2, 2)
	smoke.Speed = NumberRange.new(0.2, 0.8)
	smoke.SpreadAngle = Vector2.new(80, 80)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0.1) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	smoke.Parent = aura
	local burst = Instance.new("ParticleEmitter")
	burst.Texture = "rbxasset://textures/particles/smoke_main.dds"
	burst.Color = ColorSequence.new(Color3.fromRGB(10, 9, 10))
	burst.Rate = 0
	burst.Lifetime = NumberRange.new(0.8, 1.5)
	burst.Speed = NumberRange.new(5, 11)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 0.2) })
	burst.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	burst.Parent = aura

	model.Parent = workspace
	local parts, cfs = {}, {}
	for i, e in entries do
		parts[i] = e.part
		cfs[i] = e.part.CFrame
	end
	table.insert(parts, aura)
	table.insert(cfs, aura.CFrame)
	return { model = model, head = head, entries = entries, eyes = eyes, aura = aura, burst = burst, parts = parts, cfs = cfs, blinkAt = os.clock() + 3, speak = 0, fade = 1, alive = true, phase = 0, amt = 0 }
end

local function chain(base: CFrame, n: number, segLen: number, t: number, phase: number, amp: number, out: { [string]: CFrame }, prefix: string)
	local cf = base
	for k = 1, n do
		cf = cf * CFrame.Angles(math.sin(t * 2.2 + phase + k * 0.55) * amp, 0, math.sin(t * 1.7 + phase * 1.3 + k * 0.5) * amp * 0.6)
		out[prefix .. k] = cf
		cf = cf * CFrame.new(0, -segLen, 0)
	end
end

function KuroRig.Update(rig: Rig, dt: number, rootCF: CFrame, lookAt: Vector3, speak: number, move: number)
	if not rig.alive then
		return
	end
	local t = os.clock()
	rig.speak += (speak - rig.speak) * math.min(1, dt * 10)
	rig.amt += (math.clamp(move, 0, 2) - rig.amt) * math.min(1, dt * 7)
	local amt = rig.amt
	local walk = math.min(1, amt)
	rig.phase += dt * (5.2 + 3.4 * amt) * (amt > 0.05 and 1 or 0)
	local ph = rig.phase
	local sp = rig.speak
	local B: { [string]: CFrame } = {}

	-- the body: hips ride on the legs (a small bounce while walking), he leans into the walk
	local bounce = math.abs(math.sin(ph)) * 0.16 * walk
	B.hip = rootCF * CFrame.new(0, 3.05 + bounce + math.sin(t * 1.4) * 0.03, 0) * CFrame.Angles(-0.07 * amt, math.sin(ph) * 0.1 * walk, math.sin(ph) * 0.03 * walk)
	B.chest = B.hip * CFrame.new(0, 1.35, 0) * CFrame.Angles(math.sin(t * 1.6) * 0.015 - 0.04 * amt, -math.sin(ph) * 0.12 * walk, 0)

	-- legs: thigh swings, the knee bends when the leg lifts, the boot follows
	for _, s in { -1, 1 } do
		local n = s == -1 and "L" or "R"
		local lp = ph + (s == 1 and 0 or math.pi)
		local swing = math.sin(lp) * 0.62 * walk
		local th = B.hip * CFrame.new(s * 0.45, -0.3, 0) * CFrame.Angles(swing, 0, 0)
		B["th" .. n] = th
		local bend = math.max(0, math.sin(lp + 1.0)) * 0.95 * walk
		local sn = th * CFrame.new(0, -1.35, 0) * CFrame.Angles(-bend, 0, 0)
		B["sn" .. n] = sn
		B["ft" .. n] = sn * CFrame.new(0, -1.35, 0) * CFrame.Angles(-swing * 0.45 + bend * 0.25, 0, 0)
	end

	-- the head turns to look at you, the jaw opens when he speaks
	local rel = B.chest:PointToObjectSpace(lookAt)
	local yaw = math.clamp(math.atan2(-rel.X, -rel.Z), -1.15, 1.15)
	local pitch = math.clamp(math.atan2(rel.Y - 1.5, math.sqrt(rel.X * rel.X + rel.Z * rel.Z)), -0.35, 0.5)
	B.head = B.chest * CFrame.new(0, 1.5, 0.1) * CFrame.Angles(pitch + sp * math.sin(t * 9) * 0.04, yaw, math.sin(t * 0.7) * 0.04)
	local open = 0.08 + sp * 0.34 * (0.5 + 0.5 * math.sin(t * 21))
	B.jaw = B.head * CFrame.new(0, 0.12, -0.25) * CFrame.Angles(-open, 0, 0)

	-- arms swing against the legs; when he talks the forearms lift a little
	for _, s in { -1, 1 } do
		local n = s == -1 and "L" or "R"
		local lp = ph + (s == 1 and math.pi or 0)
		local sh = B.chest * CFrame.new(s * 1.4, 0.85, 0) * CFrame.Angles(math.sin(lp) * 0.5 * walk + math.sin(t * 1.5 + s) * 0.05 - 0.05, 0, s * (0.17 + math.sin(t * 1.1) * 0.03))
		B["sh" .. n] = sh
		local el = sh * CFrame.new(0, -1.4, 0) * CFrame.Angles(0.35 + math.max(0, math.sin(lp)) * 0.4 * walk + sp * 0.25, 0, 0)
		B["el" .. n] = el
		local ha = el * CFrame.new(0, -1.4, 0) * CFrame.Angles(math.sin(t * 1.7 + s * 2) * 0.1, 0, 0)
		B["ha" .. n] = ha
		for j = 0, 4 do
			local base = j == 4 and (ha * CFrame.new(-s * 0.3, -0.18, -0.04) * CFrame.Angles(0, 0, -s * 0.55)) or (ha * CFrame.new(-0.21 + j * 0.14, -0.5, 0))
			local curl = 0.4 + 0.2 * math.sin(t * 1.4 + j * 0.8 + s) + 0.15 * walk
			local f1 = base * CFrame.Angles(curl, 0, 0)
			local f2 = f1 * CFrame.new(0, -0.46, 0) * CFrame.Angles(curl * 1.1, 0, 0)
			local f3 = f2 * CFrame.new(0, -0.42, 0) * CFrame.Angles(curl * 0.9, 0, 0)
			B["f" .. n .. j .. 1], B["f" .. n .. j .. 2], B["f" .. n .. j .. 3] = f1, f2, f3
		end
	end

	-- folded wings: they only breathe a little (more when he runs)
	for _, s in { -1, 1 } do
		local n = s == -1 and "L" or "R"
		local root = B.chest * CFrame.new(s * 0.5, 0.8, 0.6) * CFrame.Angles(0, -s * (0.2 + math.sin(t * 1.3) * 0.03 + 0.12 * amt), s * -0.08)
		for i = 1, 7 do
			B["wg" .. n .. i] = root * CFrame.Angles(0, 0, s * (0.05 + (i - 1) * 0.09 + math.sin(t * 1.3 - i * 0.2) * 0.02))
		end
	end

	-- the coat tails and the hair trail behind when he moves
	for i = 0, 7 do
		local a = i * math.pi / 4
		local base = B.hip * CFrame.new(math.cos(a) * 0.58, 0.3, math.sin(a) * 0.46) * CFrame.Angles(0, math.pi / 2 - a, 0) * CFrame.Angles(-0.12 - 0.35 * amt * (math.sin(a) > 0 and 1 or -0.2), 0, 0)
		chain(base, 2, 0.95, t, i * 0.9, 0.06 + 0.04 * amt, B, "ct" .. i)
	end
	for i = 1, 5 do
		local base = B.chest * CFrame.new((i - 3) * 0.7, 0.55, 0.62) * CFrame.Angles(-0.08 - 0.45 * amt, 0, 0)
		chain(base, 2, 1.1, t, i * 0.9 + 3, 0.05 + 0.05 * amt, B, "cp" .. i)
	end
	for i = 1, 5 do
		local base = B.head * CFrame.new((i - 3) * 0.28, 1.35, 0.6) * CFrame.Angles(-0.75 - 0.25 * amt, 0, (i - 3) * 0.1)
		chain(base, 3, 0.95, t, i * 1.1, 0.1, B, "hr" .. i)
	end

	-- blink
	local blinking = t >= rig.blinkAt and t < rig.blinkAt + 0.14
	if t >= rig.blinkAt + 0.14 then
		rig.blinkAt = t + 2.5 + math.random() * 3.5
	end
	for _, e in rig.eyes do
		e.part.Size = blinking and Vector3.new(e.size.X, 0.02, e.size.Z) or e.size
	end

	local cfs = rig.cfs
	local entries = rig.entries
	for i = 1, #entries do
		local e = entries[i]
		local bone = B[e.bone]
		cfs[i] = bone and (bone * e.off) or (B.hip * e.off)
	end
	cfs[#entries + 1] = B.hip * CFrame.new(0, 0.8, 0) -- (the cloud's box follows his body)
	workspace:BulkMoveTo(rig.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

function KuroRig.SetFade(rig: Rig, f: number)
	if math.abs(f - rig.fade) < 0.01 then
		return
	end
	rig.fade = f
	for _, e in rig.entries do
		e.part.Transparency = e.base + (1 - e.base) * f
	end
end

function KuroRig.Burst(rig: Rig)
	rig.burst:Emit(50)
end

function KuroRig.Destroy(rig: Rig)
	rig.alive = false
	rig.model:Destroy()
end

return KuroRig
