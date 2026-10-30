--!nonstrict
-- PropBuilders: multi-part props (anvil, guns, melee weapons, grenade, bandage, rope, physics gun,
-- explosive barrel, spike trap, car). Every builder returns a Model (PrimaryPart set, parts welded) positioned at cf.
-- Held items carry a "GripAttachment" on their PrimaryPart: LookVector = forward, UpVector = top.

local PropBuilders = {}

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = model
	return p
end

------------------------------------------------------------------------
-- anti-flicker: two parts whose faces lie in the same plane, face the same way, overlap and do not
-- look the same flicker in game ("z-fighting"). Before anything is welded, the smaller part's face
-- is pushed out by a hair (0.03 studs), so one face is always clearly in front.
------------------------------------------------------------------------

local DF_EPS = 0.012
local DF_PUSH = 0.03

local function dfFaces(p: BasePart)
	local cf, s = p.CFrame, p.Size
	local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
	local shape = p:IsA("Part") and (p :: Part).Shape or Enum.PartType.Block
	if shape == Enum.PartType.Ball then
		return {}
	end
	local function w(x: number, y: number, z: number): Vector3
		return cf:PointToWorldSpace(Vector3.new(x, y, z))
	end
	local ax, ay, az = cf.RightVector, cf.UpVector, -cf.LookVector
	if shape == Enum.PartType.Cylinder then
		local r = math.min(hy, hz)
		local out = {}
		for _, sgn in { 1, -1 } do
			local pts = {}
			for t = 0, 11 do
				local a = t * math.pi / 6
				table.insert(pts, w(sgn * hx, r * math.cos(a), r * math.sin(a)))
			end
			table.insert(out, { axis = "X", sgn = sgn, n = ax * sgn, pts = pts })
		end
		return out
	end
	local out = {
		{ axis = "X", sgn = 1, n = ax, pts = { w(hx, -hy, -hz), w(hx, hy, -hz), w(hx, hy, hz), w(hx, -hy, hz) } },
		{ axis = "X", sgn = -1, n = -ax, pts = { w(-hx, -hy, -hz), w(-hx, -hy, hz), w(-hx, hy, hz), w(-hx, hy, -hz) } },
		{ axis = "Y", sgn = 1, n = ay, pts = { w(-hx, hy, -hz), w(-hx, hy, hz), w(hx, hy, hz), w(hx, hy, -hz) } },
		{ axis = "Y", sgn = -1, n = -ay, pts = { w(-hx, -hy, -hz), w(hx, -hy, -hz), w(hx, -hy, hz), w(-hx, -hy, hz) } },
		{ axis = "Z", sgn = 1, n = az, pts = { w(-hx, -hy, hz), w(hx, -hy, hz), w(hx, hy, hz), w(-hx, hy, hz) } },
		{ axis = "Z", sgn = -1, n = -az, pts = { w(-hx, -hy, -hz), w(-hx, hy, -hz), w(hx, hy, -hz), w(hx, -hy, -hz) } },
	}
	if p:IsA("WedgePart") then
		-- (the slope is left alone; the top / front faces do not exist on a wedge)
		table.remove(out, 6)
		table.remove(out, 3)
	end
	return out
end

local function dfLook(p: BasePart): string
	local c = p.Color
	return string.format("%d,%d,%d|%s|%.3f|%.3f", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5), p.Material.Name, p.Transparency, p.Reflectance)
end

local function dfArea(poly: { { number } }): number
	local a = 0
	for i = 1, #poly do
		local p1, p2 = poly[i], poly[i % #poly + 1]
		a += p1[1] * p2[2] - p2[1] * p1[2]
	end
	return a / 2
end

local function dfOverlap(n: Vector3, pa: { Vector3 }, pb: { Vector3 }): number
	local ref = math.abs(n.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis
	local u = ref:Cross(n).Unit
	local v = n:Cross(u)
	local function flat(pts: { Vector3 })
		local out = {}
		for _, q in pts do
			table.insert(out, { q:Dot(u), q:Dot(v) })
		end
		if dfArea(out) < 0 then
			local rev = {}
			for i = #out, 1, -1 do
				table.insert(rev, out[i])
			end
			out = rev
		end
		return out
	end
	local poly = flat(pa)
	local clipper = flat(pb)
	for i = 1, #clipper do
		if #poly == 0 then
			break
		end
		local a, b = clipper[i], clipper[i % #clipper + 1]
		local function inside(q)
			return (b[1] - a[1]) * (q[2] - a[2]) - (b[2] - a[2]) * (q[1] - a[1]) >= -1e-9
		end
		local function cut(q, r)
			local dx1, dy1 = r[1] - q[1], r[2] - q[2]
			local dx2, dy2 = b[1] - a[1], b[2] - a[2]
			local den = dx1 * dy2 - dy1 * dx2
			if math.abs(den) < 1e-12 then
				return q
			end
			local t = ((a[1] - q[1]) * dy2 - (a[2] - q[2]) * dx2) / den
			return { q[1] + dx1 * t, q[2] + dy1 * t }
		end
		local inp = poly
		poly = {}
		for j = 1, #inp do
			local cur, prev = inp[j], inp[(j - 2) % #inp + 1]
			if inside(cur) then
				if not inside(prev) then
					table.insert(poly, cut(prev, cur))
				end
				table.insert(poly, cur)
			elseif inside(prev) then
				table.insert(poly, cut(prev, cur))
			end
		end
	end
	return #poly >= 3 and math.abs(dfArea(poly)) or 0
end

local function deflicker(model: Model, keep: BasePart?)
	for _ = 1, 8 do
		local parts = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 0.99 then
				table.insert(parts, d)
			end
		end
		local all = {}
		for _, p in parts do
			for _, f in dfFaces(p) do
				f.part = p
				f.d = f.n:Dot(f.pts[1])
				f.look = dfLook(p)
				table.insert(all, f)
			end
		end
		local moved = false
		local done: { [BasePart]: boolean } = {}
		for i = 1, #all do
			local fa = all[i]
			for j = i + 1, #all do
				local fb = all[j]
				if fa.part ~= fb.part and not done[fa.part] and not done[fb.part] and math.abs(fa.d - fb.d) < DF_EPS
					and fa.n:Dot(fb.n) > 0.999 and fa.look ~= fb.look and dfOverlap(fa.n, fa.pts, fb.pts) > 0.002 then
					-- push the smaller part's face out (never the main part)
					local va = fa.part.Size.X * fa.part.Size.Y * fa.part.Size.Z
					local vb = fb.part.Size.X * fb.part.Size.Y * fb.part.Size.Z
					local f = fa
					if fa.part == keep or (fb.part ~= keep and vb < va) then
						f = fb
					end
					local p = f.part
					local grow = Vector3.new(f.axis == "X" and DF_PUSH or 0, f.axis == "Y" and DF_PUSH or 0, f.axis == "Z" and DF_PUSH or 0)
					local cf = p.CFrame
					p.Size += grow
					p.CFrame = cf + f.n * (DF_PUSH / 2)
					done[p] = true
					moved = true
				end
			end
		end
		if not moved then
			return
		end
	end
end
PropBuilders.Deflicker = deflicker

local function weldAll(model: Model, root: BasePart)
	deflicker(model, root)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = p
			w.Parent = p
		end
	end
end

local function setDensity(model: Model, density: number, friction: number?, elasticity: number?)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CustomPhysicalProperties = PhysicalProperties.new(density, friction or 0.5, elasticity or 0.1, 1, 1)
		end
	end
end

-- frame at pos looking along `forward` with `up` as its top
local function frameAlong(pos: Vector3, forward: Vector3, up: Vector3): CFrame
	local f = forward.Unit
	local u = (up - f * up:Dot(f)).Unit
	return CFrame.fromMatrix(pos, f:Cross(u), u)
end

local function gripAttachment(holder: BasePart, worldFrame: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = "GripAttachment"
	a.CFrame = holder.CFrame:ToObjectSpace(worldFrame)
	a.Parent = holder
	return a
end

local CYL_Z = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis (X) -> Z
local CYL_Y = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis (X) -> Y

------------------------------------------------------------------------
-- Anvil: forged steel, horn on the front, heel at the back. ~640 kg
------------------------------------------------------------------------
function PropBuilders.anvil(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Anvil"
	local steel = Color3.fromRGB(46, 47, 52)
	local worn = Color3.fromRGB(118, 121, 128)
	local base = cf * CFrame.new(0, -0.95, 0) -- bottom of the anvil

	local body = part(m, "Body", Vector3.new(2.1, 0.58, 1.0), base * CFrame.new(0, 1.55, 0), steel, Enum.Material.Metal)
	part(m, "Face", Vector3.new(2.06, 0.05, 0.96), base * CFrame.new(-0.02, 1.865, 0), worn, Enum.Material.Metal, { Reflectance = 0.25 })
	part(m, "Waist", Vector3.new(1.05, 0.62, 0.72), base * CFrame.new(0, 0.95, 0), steel, Enum.Material.Metal)
	part(m, "Base", Vector3.new(2.0, 0.34, 1.26), base * CFrame.new(0, 0.17, 0), steel, Enum.Material.Metal)
	part(m, "BaseTop", Vector3.new(1.6, 0.22, 1.0), base * CFrame.new(0, 0.45, 0), steel, Enum.Material.Metal)
	-- feet at the four corners
	for _, x in { -0.88, 0.88 } do
		for _, z in { -0.5, 0.5 } do
			part(m, "Foot", Vector3.new(0.42, 0.12, 0.38), base * CFrame.new(x, 0.06, z), steel, Enum.Material.Metal)
		end
	end
	-- heel (back, square)
	part(m, "Heel", Vector3.new(0.55, 0.44, 0.78), base * CFrame.new(-1.32, 1.6, 0), steel, Enum.Material.Metal)
	part(m, "HeelFace", Vector3.new(0.53, 0.04, 0.74), base * CFrame.new(-1.32, 1.84, 0), worn, Enum.Material.Metal, { Reflectance = 0.2 })
	-- horn (front), tapering in steps
	local hornY = 1.62
	local steps = {
		{ len = 0.34, d = 0.56, x = 1.22 },
		{ len = 0.3, d = 0.44, x = 1.54 },
		{ len = 0.26, d = 0.32, x = 1.82 },
		{ len = 0.2, d = 0.2, x = 2.05 },
		{ len = 0.12, d = 0.1, x = 2.2 },
	}
	for i, s in steps do
		part(m, "Horn" .. i, Vector3.new(s.len, s.d, s.d), base * CFrame.new(s.x, hornY + (0.56 - s.d) * 0.25, 0), steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	end
	-- hardy and pritchel holes
	part(m, "Hardy", Vector3.new(0.16, 0.02, 0.16), base * CFrame.new(-0.78, 1.89, 0.15), Color3.fromRGB(15, 15, 17), Enum.Material.SmoothPlastic)
	part(m, "Pritchel", Vector3.new(0.09, 0.02, 0.09), base * CFrame.new(-0.55, 1.89, -0.2), Color3.fromRGB(15, 15, 17), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder, CFrame = base * CFrame.new(-0.55, 1.89, -0.2) * CYL_Y })

	setDensity(m, 30, 0.6, 0.05)
	m.PrimaryPart = body
	weldAll(m, body)
	return m
end

------------------------------------------------------------------------
-- Pistol: slide, frame, raked grip, trigger guard, sights. Forward = -Z.
------------------------------------------------------------------------
function PropBuilders.pistol(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Pistol"
	local black = Color3.fromRGB(28, 28, 31)
	local frameCol = Color3.fromRGB(38, 38, 41)
	local steel = Color3.fromRGB(70, 72, 78)

	local slide = part(m, "Slide", Vector3.new(0.22, 0.24, 1.0), cf * CFrame.new(0, 0.12, -0.05), black, Enum.Material.Metal, { Reflectance = 0.08 })
	part(m, "SlideSerrations", Vector3.new(0.225, 0.16, 0.18), cf * CFrame.new(0, 0.13, 0.33), Color3.fromRGB(20, 20, 22), Enum.Material.DiamondPlate)
	part(m, "Frame", Vector3.new(0.2, 0.14, 0.86), cf * CFrame.new(0, -0.07, -0.12), frameCol, Enum.Material.SmoothPlastic)
	part(m, "Rail", Vector3.new(0.16, 0.05, 0.3), cf * CFrame.new(0, -0.165, -0.38), frameCol, Enum.Material.SmoothPlastic)
	part(m, "Barrel", Vector3.new(0.08, 0.13, 0.13), cf * CFrame.new(0, 0.13, -0.585) * CYL_Z, steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Bore", Vector3.new(0.02, 0.07, 0.07), cf * CFrame.new(0, 0.13, -0.63) * CYL_Z, Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "FrontSight", Vector3.new(0.04, 0.05, 0.06), cf * CFrame.new(0, 0.265, -0.5), black, Enum.Material.Metal)
	part(m, "RearSight", Vector3.new(0.15, 0.05, 0.05), cf * CFrame.new(0, 0.265, 0.38), black, Enum.Material.Metal)
	part(m, "Port", Vector3.new(0.02, 0.09, 0.24), cf * CFrame.new(0.105, 0.15, -0.08), Color3.fromRGB(90, 85, 70), Enum.Material.Metal)
	local grip = part(m, "Handle", Vector3.new(0.2, 0.6, 0.32), cf * CFrame.new(0, -0.38, 0.2) * CFrame.Angles(math.rad(-16), 0, 0), black, Enum.Material.Fabric)
	part(m, "GripPanelL", Vector3.new(0.02, 0.5, 0.26), cf * CFrame.new(-0.105, -0.38, 0.2) * CFrame.Angles(math.rad(-16), 0, 0), Color3.fromRGB(45, 40, 35), Enum.Material.Wood)
	part(m, "GripPanelR", Vector3.new(0.02, 0.5, 0.26), cf * CFrame.new(0.105, -0.38, 0.2) * CFrame.Angles(math.rad(-16), 0, 0), Color3.fromRGB(45, 40, 35), Enum.Material.Wood)
	part(m, "MagBase", Vector3.new(0.21, 0.05, 0.32), cf * CFrame.new(0, -0.68, 0.29) * CFrame.Angles(math.rad(-16), 0, 0), black, Enum.Material.Metal)
	part(m, "GuardBottom", Vector3.new(0.06, 0.04, 0.32), cf * CFrame.new(0, -0.27, -0.14), frameCol, Enum.Material.SmoothPlastic)
	part(m, "GuardFront", Vector3.new(0.06, 0.15, 0.04), cf * CFrame.new(0, -0.2, -0.29), frameCol, Enum.Material.SmoothPlastic)
	part(m, "Trigger", Vector3.new(0.04, 0.11, 0.04), cf * CFrame.new(0, -0.18, -0.1) * CFrame.Angles(math.rad(12), 0, 0), steel, Enum.Material.Metal)
	part(m, "Hammer", Vector3.new(0.06, 0.08, 0.06), cf * CFrame.new(0, 0.2, 0.47), steel, Enum.Material.Metal)

	-- hand holds the grip; this attachment carries the gun's own orientation (forward = -Z)
	local gripAtt = Instance.new("Attachment")
	gripAtt.Name = "GripAttachment"
	gripAtt.CFrame = grip.CFrame:ToObjectSpace(cf * CFrame.new(0, -0.33, 0.17))
	gripAtt.Parent = grip
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = slide.CFrame:ToObjectSpace(cf * CFrame.new(0, 0.13, -0.66))
	muzzle.Parent = slide
	local eject = Instance.new("Attachment")
	eject.Name = "Ejection"
	eject.CFrame = slide.CFrame:ToObjectSpace(cf * CFrame.new(0.12, 0.16, -0.08))
	eject.Parent = slide

	setDensity(m, 1.4, 0.6, 0.1)
	m.PrimaryPart = grip
	weldAll(m, grip)
	m:SetAttribute("Gun", true)
	m:SetAttribute("Item", "pistol")
	m:SetAttribute("Ammo", 12)
	m:SetAttribute("MaxAmmo", 12)
	return m
end

------------------------------------------------------------------------
-- Spear: wooden shaft with a needle-sharp steel tip (only the tip stabs)
------------------------------------------------------------------------
function PropBuilders.spear(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Spear"
	local shaft = part(m, "Shaft", Vector3.new(6.6, 0.18, 0.18), cf, Color3.fromRGB(120, 86, 52), Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	part(m, "Binding", Vector3.new(0.3, 0.22, 0.22), cf * CFrame.new(3.25, 0, 0), Color3.fromRGB(60, 48, 36), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	local tip = part(m, "SpearTip", Vector3.new(0.7, 0.14, 0.14), cf * CFrame.new(3.65, 0, 0), Color3.fromRGB(160, 162, 168), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Reflectance = 0.2 })
	local point = part(m, "SpearPoint", Vector3.new(0.4, 0.07, 0.07), cf * CFrame.new(4.15, 0, 0), Color3.fromRGB(180, 182, 188), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Reflectance = 0.25 })
	tip:SetAttribute("Sharpness", 0.85)
	point:SetAttribute("Sharpness", 1)
	shaft:SetAttribute("Sharpness", 0)
	-- held a third from the back, tip forward (thrust with F, throw by letting go while aiming)
	gripAttachment(shaft, frameAlong(cf:PointToWorldSpace(Vector3.new(-1.3, 0, 0)), cf.RightVector, cf.UpVector))
	setDensity(m, 0.7, 0.5, 0.05)
	m.PrimaryPart = shaft
	weldAll(m, shaft)
	m:SetAttribute("Item", "spear")
	return m
end

------------------------------------------------------------------------
-- Spike trap: heavy plate with steel spikes pointing up
------------------------------------------------------------------------
function PropBuilders.spiketrap(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Spike Trap"
	local base = cf * CFrame.new(0, -0.65, 0)
	local plate = part(m, "Plate", Vector3.new(4, 0.3, 4), base, Color3.fromRGB(70, 60, 55), Enum.Material.CorrodedMetal)
	for ix = 0, 3 do
		for iz = 0, 3 do
			local x = -1.5 + ix
			local z = -1.5 + iz
			local rod = part(m, "Spike", Vector3.new(1.1, 0.16, 0.16), base * CFrame.new(x, 0.7, z) * CYL_Y, Color3.fromRGB(150, 150, 155), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Reflectance = 0.15 })
			rod:SetAttribute("Sharpness", 0.85)
			local tip = part(m, "SpikeTip", Vector3.new(0.3, 0.07, 0.07), base * CFrame.new(x, 1.38, z) * CYL_Y, Color3.fromRGB(190, 190, 195), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Reflectance = 0.2 })
			tip:SetAttribute("Sharpness", 1)
		end
	end
	setDensity(m, 2.5, 0.7, 0.05)
	m.PrimaryPart = plate
	weldAll(m, plate)
	return m
end

------------------------------------------------------------------------
-- Pump shotgun: 8 pellets, 6 shells (G reloads). Forward = -Z.
------------------------------------------------------------------------
function PropBuilders.shotgun(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Shotgun"
	local black = Color3.fromRGB(30, 30, 33)
	local steel = Color3.fromRGB(64, 66, 72)
	local wood = Color3.fromRGB(112, 72, 40)
	local receiver = part(m, "Receiver", Vector3.new(0.3, 0.42, 1.1), cf * CFrame.new(0, 0.1, -0.1), black, Enum.Material.Metal, { Reflectance = 0.06 })
	local barrel = part(m, "Barrel", Vector3.new(2.3, 0.17, 0.17), cf * CFrame.new(0, 0.22, -1.8) * CYL_Z, steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Reflectance = 0.1 })
	part(m, "Tube", Vector3.new(1.75, 0.14, 0.14), cf * CFrame.new(0, 0.03, -1.55) * CYL_Z, black, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Pump", Vector3.new(0.27, 0.27, 0.75), cf * CFrame.new(0, 0.02, -1.4), wood, Enum.Material.Wood)
	part(m, "Bead", Vector3.new(0.05, 0.05, 0.05), cf * CFrame.new(0, 0.33, -2.9), Color3.fromRGB(230, 230, 230), Enum.Material.Metal)
	local grip = part(m, "Handle", Vector3.new(0.22, 0.55, 0.3), cf * CFrame.new(0, -0.3, 0.28) * CFrame.Angles(math.rad(-18), 0, 0), wood, Enum.Material.Wood)
	part(m, "Stock", Vector3.new(0.26, 0.4, 1.35), cf * CFrame.new(0, -0.08, 1.15) * CFrame.Angles(math.rad(-6), 0, 0), wood, Enum.Material.Wood)
	part(m, "ButtPad", Vector3.new(0.27, 0.46, 0.08), cf * CFrame.new(0, -0.14, 1.84) * CFrame.Angles(math.rad(-6), 0, 0), black, Enum.Material.Fabric)
	part(m, "Guard", Vector3.new(0.06, 0.04, 0.34), cf * CFrame.new(0, -0.17, -0.02), black, Enum.Material.Metal)
	part(m, "Trigger", Vector3.new(0.04, 0.1, 0.04), cf * CFrame.new(0, -0.1, -0.05) * CFrame.Angles(math.rad(12), 0, 0), steel, Enum.Material.Metal)
	gripAttachment(grip, cf * CFrame.new(0, -0.3, 0.22))
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = barrel.CFrame:ToObjectSpace(cf * CFrame.new(0, 0.22, -2.97))
	muzzle.Parent = barrel
	local eject = Instance.new("Attachment")
	eject.Name = "Ejection"
	eject.CFrame = receiver.CFrame:ToObjectSpace(cf * CFrame.new(0.17, 0.18, -0.15))
	eject.Parent = receiver
	setDensity(m, 1.1, 0.6, 0.1)
	m.PrimaryPart = grip
	weldAll(m, grip)
	m:SetAttribute("Gun", true)
	m:SetAttribute("Item", "shotgun")
	m:SetAttribute("Ammo", 6)
	m:SetAttribute("MaxAmmo", 6)
	return m
end

------------------------------------------------------------------------
-- Blade (machete): slash with F or swing the arm, cuts limbs off. Forward = -Z.
------------------------------------------------------------------------
function PropBuilders.blade(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Blade"
	local handle = part(m, "Handle", Vector3.new(0.2, 0.24, 0.95), cf, Color3.fromRGB(40, 32, 26), Enum.Material.Fabric)
	part(m, "Pommel", Vector3.new(0.26, 0.28, 0.12), cf * CFrame.new(0, 0, 0.52), Color3.fromRGB(70, 70, 76), Enum.Material.Metal)
	part(m, "Guard", Vector3.new(0.7, 0.16, 0.12), cf * CFrame.new(0, 0, -0.52), Color3.fromRGB(70, 70, 76), Enum.Material.Metal)
	local blade = part(m, "Blade", Vector3.new(0.34, 0.05, 3.0), cf * CFrame.new(0, 0, -2.08), Color3.fromRGB(170, 174, 182), Enum.Material.Metal, { Reflectance = 0.3 })
	part(m, "Edge", Vector3.new(0.06, 0.055, 2.9), cf * CFrame.new(0.17, 0, -2.1), Color3.fromRGB(215, 218, 224), Enum.Material.Metal, { Reflectance = 0.45 })
	part(m, "BladeTip", Vector3.new(0.24, 0.05, 0.3), cf * CFrame.new(0.05, 0, -3.66) * CFrame.Angles(0, math.rad(25), 0), Color3.fromRGB(170, 174, 182), Enum.Material.Metal, { Reflectance = 0.3 })
	blade:SetAttribute("Sharpness", 0.9)
	gripAttachment(handle, cf)
	setDensity(m, 1.6, 0.5, 0.05)
	m.PrimaryPart = handle
	weldAll(m, handle)
	m:SetAttribute("Item", "blade")
	return m
end

------------------------------------------------------------------------
-- Grenade: F pulls the pin (blinks, fuse ~3 s), let go of it (Q/E) to throw.
------------------------------------------------------------------------
function PropBuilders.grenade(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Grenade"
	local olive = Color3.fromRGB(78, 88, 52)
	local body = part(m, "Body", Vector3.new(0.62, 0.62, 0.62), cf, olive, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
	part(m, "Band", Vector3.new(0.12, 0.64, 0.64), cf * CYL_Y, Color3.fromRGB(60, 68, 40), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Fuze", Vector3.new(0.22, 0.2, 0.2), cf * CFrame.new(0, 0.36, 0) * CYL_Y, Color3.fromRGB(120, 120, 124), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Lever", Vector3.new(0.08, 0.5, 0.06), cf * CFrame.new(0, 0.12, 0.29) * CFrame.Angles(math.rad(8), 0, 0), Color3.fromRGB(130, 130, 134), Enum.Material.Metal)
	part(m, "Pin", Vector3.new(0.03, 0.2, 0.2), cf * CFrame.new(0.17, 0.4, 0), Color3.fromRGB(190, 190, 194), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	local light = Instance.new("PointLight")
	light.Name = "Blink"
	light.Color = Color3.fromRGB(255, 60, 40)
	light.Brightness = 4
	light.Range = 7
	light.Enabled = false
	light.Parent = body
	gripAttachment(body, cf * CFrame.new(0, 0.05, 0))
	setDensity(m, 2.2, 0.6, 0.15)
	m.PrimaryPart = body
	weldAll(m, body)
	m:SetAttribute("Item", "grenade")
	m:SetAttribute("Fuse", 3.2)
	return m
end

------------------------------------------------------------------------
-- Flashbang: F pulls the pin, let go to throw. A blinding flash and a bang, no damage.
------------------------------------------------------------------------
function PropBuilders.flash(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Flashbang"
	local grey = Color3.fromRGB(70, 74, 80)
	local body = part(m, "Body", Vector3.new(0.9, 0.5, 0.5), cf * CYL_Y, grey, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	for i, y in { -0.25, 0, 0.25 } do
		part(m, "Holes" .. i, Vector3.new(0.12, 0.54, 0.54), cf * CFrame.new(0, y, 0) * CYL_Y, Color3.fromRGB(30, 32, 36), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	end
	part(m, "Fuze", Vector3.new(0.2, 0.22, 0.22), cf * CFrame.new(0, 0.55, 0) * CYL_Y, Color3.fromRGB(150, 150, 154), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Lever", Vector3.new(0.08, 0.6, 0.06), cf * CFrame.new(0, 0.2, 0.29) * CFrame.Angles(math.rad(6), 0, 0), Color3.fromRGB(170, 170, 174), Enum.Material.Metal)
	part(m, "Pin", Vector3.new(0.03, 0.2, 0.2), cf * CFrame.new(0.17, 0.62, 0), Color3.fromRGB(200, 200, 204), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Label", Vector3.new(0.1, 0.53, 0.53), cf * CFrame.new(0, -0.33, 0) * CYL_Y, Color3.fromRGB(220, 190, 40), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	local light = Instance.new("PointLight")
	light.Name = "Blink"
	light.Color = Color3.fromRGB(200, 220, 255)
	light.Brightness = 4
	light.Range = 7
	light.Enabled = false
	light.Parent = body
	gripAttachment(body, cf * CFrame.new(0, 0.05, 0))
	setDensity(m, 2, 0.6, 0.15)
	m.PrimaryPart = body
	weldAll(m, body)
	m:SetAttribute("Item", "flash")
	m:SetAttribute("Fuse", 1.8)
	return m
end

------------------------------------------------------------------------
-- Tether rope: F on one thing, F on another: a rope between them (any two points: car + anvil,
-- player + car, a body + a lamp post ...). Blades cut it.
------------------------------------------------------------------------
function PropBuilders.tether(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Tether Rope"
	local col = Color3.fromRGB(230, 120, 30)
	local coil = part(m, "Coil", Vector3.new(0.5, 1.1, 1.1), cf * CYL_Y, col, Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	for i, y in { -0.17, 0, 0.17 } do
		part(m, "Wrap" .. i, Vector3.new(0.1, 1.16, 1.16), cf * CFrame.new(0, y, 0) * CYL_Y, Color3.fromRGB(200, 96, 20), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	end
	part(m, "Hook", Vector3.new(0.14, 0.5, 0.3), cf * CFrame.new(0.55, 0.1, 0), Color3.fromRGB(150, 152, 158), Enum.Material.Metal)
	part(m, "HookTip", Vector3.new(0.14, 0.12, 0.3), cf * CFrame.new(0.55, -0.15, -0.1), Color3.fromRGB(150, 152, 158), Enum.Material.Metal)
	gripAttachment(coil, cf * CFrame.new(0, 0, 0.45))
	setDensity(m, 0.4, 0.8, 0.05)
	m.PrimaryPart = coil
	weldAll(m, coil)
	m:SetAttribute("Item", "tether")
	return m
end

------------------------------------------------------------------------
-- Bandage roll: F stops the bleeding (yours, or the body your other hand holds)
------------------------------------------------------------------------
function PropBuilders.bandage(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Bandage"
	local white = Color3.fromRGB(238, 234, 224)
	local roll = part(m, "Roll", Vector3.new(0.45, 0.55, 0.55), cf, white, Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	part(m, "Core", Vector3.new(0.47, 0.18, 0.18), cf, Color3.fromRGB(200, 190, 170), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "Strip", Vector3.new(0.4, 0.03, 0.6), cf * CFrame.new(0, -0.24, 0.3) * CFrame.Angles(math.rad(-30), 0, 0), white, Enum.Material.Fabric)
	part(m, "Cross", Vector3.new(0.02, 0.22, 0.07), cf * CFrame.new(0.235, 0, 0), Color3.fromRGB(200, 40, 40), Enum.Material.SmoothPlastic)
	part(m, "Cross2", Vector3.new(0.02, 0.07, 0.22), cf * CFrame.new(0.235, 0, 0), Color3.fromRGB(200, 40, 40), Enum.Material.SmoothPlastic)
	gripAttachment(roll, cf)
	setDensity(m, 0.3, 0.7, 0.05)
	m.PrimaryPart = roll
	weldAll(m, roll)
	m:SetAttribute("Item", "bandage")
	return m
end

------------------------------------------------------------------------
-- Explosive barrel: goes off when shot, hit hard, or caught in another explosion
------------------------------------------------------------------------
function PropBuilders.explosivebarrel(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Explosive Barrel"
	local red = Color3.fromRGB(176, 32, 28)
	local body = part(m, "Body", Vector3.new(3.0, 2.2, 2.2), cf * CYL_Y, red, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Reflectance = 0.05 })
	for _, y in { -0.95, 0.95 } do
		part(m, "Rib", Vector3.new(0.14, 2.28, 2.28), cf * CFrame.new(0, y, 0) * CYL_Y, Color3.fromRGB(120, 24, 22), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	end
	part(m, "Stripe", Vector3.new(0.5, 2.24, 2.24), cf * CYL_Y, Color3.fromRGB(240, 196, 40), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "Lid", Vector3.new(0.06, 2.05, 2.05), cf * CFrame.new(0, 1.52, 0) * CYL_Y, Color3.fromRGB(60, 60, 62), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Cap", Vector3.new(0.14, 0.32, 0.32), cf * CFrame.new(0.55, 1.58, 0.3) * CYL_Y, Color3.fromRGB(200, 200, 204), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	setDensity(m, 0.9, 0.6, 0.1)
	m.PrimaryPart = body
	weldAll(m, body)
	m:SetAttribute("Explosive", true)
	return m
end

------------------------------------------------------------------------
-- Revolver: six shots, heavy hitter, slow. Forward = -Z.
------------------------------------------------------------------------
function PropBuilders.revolver(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Revolver"
	local steel = Color3.fromRGB(150, 152, 158)
	local dark = Color3.fromRGB(52, 53, 58)
	local wood = Color3.fromRGB(96, 58, 32)
	local frame = part(m, "Frame", Vector3.new(0.2, 0.32, 0.6), cf * CFrame.new(0, 0.05, 0.05), steel, Enum.Material.Metal, { Reflectance = 0.2 })
	part(m, "Drum", Vector3.new(0.44, 0.42, 0.42), cf * CFrame.new(0, 0.07, -0.08) * CYL_Z, steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Reflectance = 0.25 })
	for i = 0, 5 do
		local a = math.rad(i * 60 + 30)
		part(m, "Flute", Vector3.new(0.46, 0.06, 0.06), cf * CFrame.new(math.cos(a) * 0.19, 0.07 + math.sin(a) * 0.19, -0.08) * CYL_Z, dark, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	end
	local barrel = part(m, "Barrel", Vector3.new(1.0, 0.15, 0.15), cf * CFrame.new(0, 0.16, -0.78) * CYL_Z, steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Reflectance = 0.25 })
	part(m, "Rib", Vector3.new(0.08, 0.06, 1.0), cf * CFrame.new(0, 0.25, -0.78), steel, Enum.Material.Metal)
	part(m, "Underlug", Vector3.new(0.11, 0.1, 0.85), cf * CFrame.new(0, 0.05, -0.72), steel, Enum.Material.Metal)
	part(m, "Bore", Vector3.new(0.02, 0.08, 0.08), cf * CFrame.new(0, 0.16, -1.285) * CYL_Z, Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "FrontSight", Vector3.new(0.04, 0.1, 0.12), cf * CFrame.new(0, 0.3, -1.2), dark, Enum.Material.Metal)
	part(m, "Hammer", Vector3.new(0.06, 0.14, 0.1), cf * CFrame.new(0, 0.25, 0.36) * CFrame.Angles(math.rad(-25), 0, 0), dark, Enum.Material.Metal)
	local grip = part(m, "Handle", Vector3.new(0.21, 0.66, 0.32), cf * CFrame.new(0, -0.33, 0.33) * CFrame.Angles(math.rad(-22), 0, 0), wood, Enum.Material.Wood)
	part(m, "GripCap", Vector3.new(0.22, 0.06, 0.3), cf * CFrame.new(0, -0.64, 0.46) * CFrame.Angles(math.rad(-22), 0, 0), steel, Enum.Material.Metal)
	part(m, "GuardBottom", Vector3.new(0.06, 0.04, 0.32), cf * CFrame.new(0, -0.16, 0.02), steel, Enum.Material.Metal)
	part(m, "GuardFront", Vector3.new(0.06, 0.14, 0.04), cf * CFrame.new(0, -0.1, -0.13), steel, Enum.Material.Metal)
	part(m, "Trigger", Vector3.new(0.04, 0.11, 0.04), cf * CFrame.new(0, -0.08, 0.03) * CFrame.Angles(math.rad(12), 0, 0), dark, Enum.Material.Metal)
	gripAttachment(grip, cf * CFrame.new(0, -0.3, 0.27))
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = barrel.CFrame:ToObjectSpace(cf * CFrame.new(0, 0.16, -1.3))
	muzzle.Parent = barrel
	local _ = frame
	setDensity(m, 1.6, 0.6, 0.1)
	m.PrimaryPart = grip
	weldAll(m, grip)
	m:SetAttribute("Gun", true)
	m:SetAttribute("Item", "revolver")
	m:SetAttribute("Ammo", 6)
	m:SetAttribute("MaxAmmo", 6)
	return m
end

------------------------------------------------------------------------
-- Assault rifle: full auto (hold F), 30 rounds. Forward = -Z.
------------------------------------------------------------------------
function PropBuilders.rifle(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Rifle"
	local black = Color3.fromRGB(32, 32, 35)
	local steel = Color3.fromRGB(62, 64, 70)
	local wood = Color3.fromRGB(128, 66, 32)
	local receiver = part(m, "Receiver", Vector3.new(0.28, 0.4, 1.6), cf * CFrame.new(0, 0.1, -0.2), black, Enum.Material.Metal, { Reflectance = 0.05 })
	part(m, "DustCover", Vector3.new(0.27, 0.07, 1.35), cf * CFrame.new(0, 0.33, -0.12), steel, Enum.Material.Metal)
	part(m, "ChargingHandle", Vector3.new(0.18, 0.06, 0.08), cf * CFrame.new(0.2, 0.22, -0.55), steel, Enum.Material.Metal)
	part(m, "Handguard", Vector3.new(0.3, 0.32, 0.9), cf * CFrame.new(0, 0.12, -1.45), wood, Enum.Material.Wood)
	part(m, "GasTube", Vector3.new(0.9, 0.11, 0.11), cf * CFrame.new(0, 0.34, -1.45) * CYL_Z, wood, Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	local barrel = part(m, "Barrel", Vector3.new(1.45, 0.11, 0.11), cf * CFrame.new(0, 0.15, -2.35) * CYL_Z, steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "MuzzleBrake", Vector3.new(0.26, 0.17, 0.17), cf * CFrame.new(0, 0.15, -3.08) * CYL_Z, black, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "FrontSight", Vector3.new(0.05, 0.24, 0.06), cf * CFrame.new(0, 0.3, -2.8), black, Enum.Material.Metal)
	part(m, "RearSight", Vector3.new(0.14, 0.08, 0.22), cf * CFrame.new(0, 0.38, -0.78), black, Enum.Material.Metal)
	part(m, "Mag1", Vector3.new(0.2, 0.6, 0.32), cf * CFrame.new(0, -0.36, -0.52) * CFrame.Angles(math.rad(14), 0, 0), black, Enum.Material.Metal)
	part(m, "Mag2", Vector3.new(0.2, 0.48, 0.3), cf * CFrame.new(0, -0.84, -0.7) * CFrame.Angles(math.rad(30), 0, 0), black, Enum.Material.Metal)
	local grip = part(m, "Handle", Vector3.new(0.2, 0.56, 0.3), cf * CFrame.new(0, -0.28, 0.5) * CFrame.Angles(math.rad(-18), 0, 0), black, Enum.Material.Fabric)
	part(m, "GuardBottom", Vector3.new(0.06, 0.04, 0.38), cf * CFrame.new(0, -0.15, 0.17), black, Enum.Material.Metal)
	part(m, "Trigger", Vector3.new(0.04, 0.1, 0.04), cf * CFrame.new(0, -0.08, 0.15) * CFrame.Angles(math.rad(12), 0, 0), steel, Enum.Material.Metal)
	part(m, "Stock", Vector3.new(0.26, 0.42, 1.5), cf * CFrame.new(0, -0.03, 1.32) * CFrame.Angles(math.rad(-5), 0, 0), wood, Enum.Material.Wood)
	part(m, "ButtPlate", Vector3.new(0.27, 0.48, 0.08), cf * CFrame.new(0, -0.1, 2.08) * CFrame.Angles(math.rad(-5), 0, 0), black, Enum.Material.Metal)
	gripAttachment(grip, cf * CFrame.new(0, -0.28, 0.45))
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = barrel.CFrame:ToObjectSpace(cf * CFrame.new(0, 0.15, -3.22))
	muzzle.Parent = barrel
	local eject = Instance.new("Attachment")
	eject.Name = "Ejection"
	eject.CFrame = receiver.CFrame:ToObjectSpace(cf * CFrame.new(0.16, 0.22, -0.35))
	eject.Parent = receiver
	setDensity(m, 1.0, 0.6, 0.1)
	m.PrimaryPart = grip
	weldAll(m, grip)
	m:SetAttribute("Gun", true)
	m:SetAttribute("Item", "rifle")
	m:SetAttribute("Ammo", 30)
	m:SetAttribute("MaxAmmo", 30)
	return m
end

------------------------------------------------------------------------
-- Baseball bat: blunt, sends people flying. Held at the knob, forward = -Z.
------------------------------------------------------------------------
function PropBuilders.bat(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Bat"
	local wood = Color3.fromRGB(196, 160, 112)
	local tape = Color3.fromRGB(30, 30, 34)
	local handle = part(m, "Handle", Vector3.new(1.3, 0.2, 0.2), cf * CFrame.new(0, 0, 0.75) * CYL_Z, wood, Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	part(m, "Tape", Vector3.new(0.85, 0.22, 0.22), cf * CFrame.new(0, 0, 0.95) * CYL_Z, tape, Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	part(m, "Knob", Vector3.new(0.12, 0.32, 0.32), cf * CFrame.new(0, 0, 1.45) * CYL_Z, wood, Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	part(m, "Taper", Vector3.new(0.8, 0.28, 0.28), cf * CFrame.new(0, 0, -0.3) * CYL_Z, wood, Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	part(m, "Taper2", Vector3.new(0.5, 0.33, 0.33), cf * CFrame.new(0, 0, -0.9) * CYL_Z, wood, Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	part(m, "BatEnd", Vector3.new(1.5, 0.38, 0.38), cf * CFrame.new(0, 0, -1.85) * CYL_Z, wood, Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	part(m, "EndCap", Vector3.new(0.06, 0.36, 0.36), cf * CFrame.new(0, 0, -2.62) * CYL_Z, Color3.fromRGB(176, 140, 96), Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	gripAttachment(handle, cf * CFrame.new(0, 0, 1.15))
	setDensity(m, 0.9, 0.5, 0.2)
	m.PrimaryPart = handle
	weldAll(m, handle)
	m:SetAttribute("Item", "bat")
	return m
end

------------------------------------------------------------------------
-- Fire axe: heavy, slow slash that chops limbs off. Forward = -Z (along the handle).
------------------------------------------------------------------------
function PropBuilders.axe(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Axe"
	local wood = Color3.fromRGB(140, 96, 56)
	local red = Color3.fromRGB(180, 30, 26)
	local steel = Color3.fromRGB(176, 180, 188)
	local handle = part(m, "Handle", Vector3.new(3.3, 0.2, 0.2), cf * CFrame.new(0, 0, -0.35) * CYL_Z, wood, Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	part(m, "Grip", Vector3.new(0.8, 0.23, 0.23), cf * CFrame.new(0, 0, 1.0) * CYL_Z, Color3.fromRGB(40, 36, 32), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	part(m, "Eye", Vector3.new(0.3, 0.42, 0.5), cf * CFrame.new(0, 0.06, -1.82), red, Enum.Material.Metal)
	local head = part(m, "AxeHead", Vector3.new(0.14, 0.62, 1.0), cf * CFrame.new(0, 0.48, -1.82), red, Enum.Material.Metal)
	part(m, "AxeEdge", Vector3.new(0.07, 0.12, 1.1), cf * CFrame.new(0, 0.84, -1.82), steel, Enum.Material.Metal, { Reflectance = 0.4 })
	part(m, "Pick", Vector3.new(0.14, 0.5, 0.26), cf * CFrame.new(0, -0.3, -1.82) * CFrame.Angles(math.rad(10), 0, 0), red, Enum.Material.Metal)
	head:SetAttribute("Sharpness", 0.8)
	gripAttachment(handle, cf * CFrame.new(0, 0, 1.0))
	setDensity(m, 1.4, 0.5, 0.05)
	m.PrimaryPart = handle
	weldAll(m, handle)
	m:SetAttribute("Item", "axe")
	return m
end

------------------------------------------------------------------------
-- Rope: hold a body with one hand, the rope in the other, F = tie the body to the nearest wall.
------------------------------------------------------------------------
function PropBuilders.rope(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Rope"
	local col = Color3.fromRGB(150, 116, 72)
	local coil = part(m, "Coil", Vector3.new(0.5, 1.1, 1.1), cf * CYL_Y, col, Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	for i, y in { -0.17, 0, 0.17 } do
		part(m, "Wrap" .. i, Vector3.new(0.1, 1.16, 1.16), cf * CFrame.new(0, y, 0) * CYL_Y, Color3.fromRGB(128, 98, 60), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	end
	part(m, "HoleTop", Vector3.new(0.02, 0.5, 0.5), cf * CFrame.new(0, 0.255, 0) * CYL_Y, Color3.fromRGB(40, 32, 22), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "HoleBottom", Vector3.new(0.02, 0.5, 0.5), cf * CFrame.new(0, -0.255, 0) * CYL_Y, Color3.fromRGB(40, 32, 22), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "LooseEnd", Vector3.new(0.9, 0.12, 0.12), cf * CFrame.new(0.55, -0.25, 0.25) * CFrame.Angles(0, math.rad(30), math.rad(-50)), col, Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	gripAttachment(coil, cf * CFrame.new(0, 0, 0.45))
	setDensity(m, 0.4, 0.8, 0.05)
	m.PrimaryPart = coil
	weldAll(m, coil)
	m:SetAttribute("Item", "rope")
	return m
end

------------------------------------------------------------------------
-- Physics gun (game owner only): hold F to grab anything with the beam - no weight limit, scroll
-- the mouse wheel to pull it closer / push it away. Forward = -Z.
------------------------------------------------------------------------
function PropBuilders.physgun(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Physics Gun"
	local body = Color3.fromRGB(40, 42, 50)
	local glow = Color3.fromRGB(90, 200, 255)
	local core = part(m, "Body", Vector3.new(0.38, 0.44, 1.35), cf * CFrame.new(0, 0.1, -0.15), body, Enum.Material.Metal, { Reflectance = 0.1 })
	part(m, "Spine", Vector3.new(0.16, 0.1, 1.2), cf * CFrame.new(0, 0.36, -0.15), Color3.fromRGB(70, 74, 84), Enum.Material.Metal)
	part(m, "Core", Vector3.new(1.1, 0.24, 0.24), cf * CFrame.new(0, 0.12, -0.5) * CYL_Z, glow, Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, Transparency = 0.15 })
	for i, z in { -0.95, -0.7, -0.45 } do
		part(m, "Ring" .. i, Vector3.new(0.07, 0.52, 0.52), cf * CFrame.new(0, 0.12, z) * CYL_Z, Color3.fromRGB(70, 74, 84), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	end
	for i = 0, 2 do
		local a = math.rad(i * 120 + 90)
		part(m, "Prong" .. i, Vector3.new(0.07, 0.07, 0.55), cf * CFrame.new(math.cos(a) * 0.24, 0.12 + math.sin(a) * 0.24, -1.3), Color3.fromRGB(150, 156, 170), Enum.Material.Metal)
	end
	local emitter = part(m, "Emitter", Vector3.new(0.24, 0.24, 0.24), cf * CFrame.new(0, 0.12, -1.25), glow, Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Range = 8
	light.Brightness = 2
	light.Parent = emitter
	local grip = part(m, "Handle", Vector3.new(0.22, 0.58, 0.32), cf * CFrame.new(0, -0.32, 0.32) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(28, 28, 32), Enum.Material.Fabric)
	part(m, "Trigger", Vector3.new(0.05, 0.12, 0.05), cf * CFrame.new(0, -0.1, 0.12) * CFrame.Angles(math.rad(12), 0, 0), glow, Enum.Material.Neon)
	gripAttachment(grip, cf * CFrame.new(0, -0.3, 0.27))
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = emitter.CFrame:ToObjectSpace(cf * CFrame.new(0, 0.12, -1.4))
	muzzle.Parent = emitter
	local _ = core
	setDensity(m, 0.8, 0.6, 0.1)
	m.PrimaryPart = grip
	weldAll(m, grip)
	m:SetAttribute("Item", "physgun")
	m:SetAttribute("OwnerOnly", true)
	return m
end

------------------------------------------------------------------------
-- small helpers for the v1.6 models
------------------------------------------------------------------------
local function muzzleAt(holder: BasePart, worldCf: CFrame, name: string?)
	local a = Instance.new("Attachment")
	a.Name = name or "Muzzle"
	a.CFrame = holder.CFrame:ToObjectSpace(worldCf)
	a.Parent = holder
	return a
end

local function finishGun(m: Model, grip: BasePart, kind: string, mag: number, density: number)
	setDensity(m, density, 0.6, 0.1)
	m.PrimaryPart = grip
	weldAll(m, grip)
	m:SetAttribute("Gun", true)
	m:SetAttribute("Item", kind)
	m:SetAttribute("Ammo", mag)
	m:SetAttribute("MaxAmmo", mag)
	return m
end

------------------------------------------------------------------------
-- SMG: small, very fast full auto (hold F). Forward = -Z.
------------------------------------------------------------------------
function PropBuilders.smg(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "SMG"
	local black = Color3.fromRGB(30, 30, 33)
	local steel = Color3.fromRGB(70, 72, 78)
	part(m, "Receiver", Vector3.new(0.26, 0.42, 1.15), cf * CFrame.new(0, 0.12, -0.15), black, Enum.Material.Metal, { Reflectance = 0.05 })
	part(m, "Top", Vector3.new(0.22, 0.06, 1.0), cf * CFrame.new(0, 0.36, -0.15), steel, Enum.Material.Metal)
	local barrel = part(m, "Barrel", Vector3.new(0.45, 0.12, 0.12), cf * CFrame.new(0, 0.15, -0.95) * CYL_Z, steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Suppressor", Vector3.new(0.6, 0.2, 0.2), cf * CFrame.new(0, 0.15, -1.45) * CYL_Z, black, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	local grip = part(m, "Handle", Vector3.new(0.22, 0.75, 0.32), cf * CFrame.new(0, -0.4, 0.05) * CFrame.Angles(math.rad(-8), 0, 0), black, Enum.Material.Fabric)
	part(m, "Mag", Vector3.new(0.18, 0.4, 0.26), cf * CFrame.new(0, -0.95, 0.12) * CFrame.Angles(math.rad(-8), 0, 0), steel, Enum.Material.Metal)
	part(m, "FrontGrip", Vector3.new(0.16, 0.42, 0.18), cf * CFrame.new(0, -0.24, -0.62), black, Enum.Material.Fabric)
	part(m, "StockArm", Vector3.new(0.06, 0.06, 0.9), cf * CFrame.new(0.1, 0.1, 0.85), steel, Enum.Material.Metal)
	part(m, "StockArm2", Vector3.new(0.06, 0.06, 0.9), cf * CFrame.new(-0.1, 0.1, 0.85), steel, Enum.Material.Metal)
	part(m, "ButtPlate", Vector3.new(0.26, 0.4, 0.06), cf * CFrame.new(0, 0.05, 1.3), black, Enum.Material.Metal)
	part(m, "Trigger", Vector3.new(0.04, 0.1, 0.04), cf * CFrame.new(0, -0.12, -0.1), steel, Enum.Material.Metal)
	gripAttachment(grip, cf * CFrame.new(0, -0.35, 0.02))
	muzzleAt(barrel, cf * CFrame.new(0, 0.15, -1.76))
	return finishGun(m, grip, "smg", 25, 1.1)
end

------------------------------------------------------------------------
-- Sniper rifle: scope (hold G), 5 shots, massive hit and kick. Forward = -Z.
------------------------------------------------------------------------
function PropBuilders.sniper(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Sniper"
	local green = Color3.fromRGB(62, 72, 52)
	local black = Color3.fromRGB(26, 26, 28)
	local steel = Color3.fromRGB(70, 72, 78)
	part(m, "Receiver", Vector3.new(0.28, 0.36, 1.7), cf * CFrame.new(0, 0.12, -0.2), black, Enum.Material.Metal)
	part(m, "Stock", Vector3.new(0.28, 0.5, 1.9), cf * CFrame.new(0, -0.02, 1.45) * CFrame.Angles(math.rad(-4), 0, 0), green, Enum.Material.SmoothPlastic)
	part(m, "CheekRest", Vector3.new(0.26, 0.14, 0.9), cf * CFrame.new(0, 0.28, 1.2), green, Enum.Material.SmoothPlastic)
	part(m, "ButtPad", Vector3.new(0.29, 0.56, 0.08), cf * CFrame.new(0, -0.08, 2.42), black, Enum.Material.Fabric)
	part(m, "Forend", Vector3.new(0.3, 0.32, 1.5), cf * CFrame.new(0, 0.06, -1.65), green, Enum.Material.SmoothPlastic)
	local barrel = part(m, "Barrel", Vector3.new(3.0, 0.13, 0.13), cf * CFrame.new(0, 0.16, -2.7) * CYL_Z, black, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "MuzzleBrake", Vector3.new(0.35, 0.22, 0.22), cf * CFrame.new(0, 0.16, -4.3) * CYL_Z, black, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Scope", Vector3.new(1.5, 0.24, 0.24), cf * CFrame.new(0, 0.55, -0.25) * CYL_Z, black, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "ScopeFront", Vector3.new(0.3, 0.34, 0.34), cf * CFrame.new(0, 0.55, -1.05) * CYL_Z, black, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "ScopeLens", Vector3.new(0.02, 0.3, 0.3), cf * CFrame.new(0, 0.55, -1.21) * CYL_Z, Color3.fromRGB(90, 150, 210), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Reflectance = 0.5 })
	part(m, "ScopeRear", Vector3.new(0.25, 0.3, 0.3), cf * CFrame.new(0, 0.55, 0.55) * CYL_Z, black, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	for _, z in { -0.6, 0.2 } do
		part(m, "ScopeMount", Vector3.new(0.12, 0.2, 0.14), cf * CFrame.new(0, 0.38, z), steel, Enum.Material.Metal)
	end
	part(m, "Bolt", Vector3.new(0.3, 0.06, 0.06), cf * CFrame.new(0.25, 0.18, 0.25), steel, Enum.Material.Metal)
	part(m, "BoltKnob", Vector3.new(0.12, 0.12, 0.12), cf * CFrame.new(0.42, 0.14, 0.25), black, Enum.Material.Metal, { Shape = Enum.PartType.Ball })
	part(m, "Mag", Vector3.new(0.2, 0.32, 0.5), cf * CFrame.new(0, -0.18, -0.35), black, Enum.Material.Metal)
	for _, x in { -0.1, 0.1 } do
		part(m, "Bipod", Vector3.new(0.05, 0.05, 1.0), cf * CFrame.new(x, -0.06, -2.2), steel, Enum.Material.Metal)
	end
	local grip = part(m, "Handle", Vector3.new(0.22, 0.6, 0.32), cf * CFrame.new(0, -0.3, 0.45) * CFrame.Angles(math.rad(-15), 0, 0), black, Enum.Material.Fabric)
	part(m, "Trigger", Vector3.new(0.04, 0.1, 0.04), cf * CFrame.new(0, -0.08, 0.18), steel, Enum.Material.Metal)
	gripAttachment(grip, cf * CFrame.new(0, -0.28, 0.4))
	muzzleAt(barrel, cf * CFrame.new(0, 0.16, -4.5))
	return finishGun(m, grip, "sniper", 5, 0.9)
end

------------------------------------------------------------------------
-- Rocket launcher: one rocket, big boom. Forward = -Z.
------------------------------------------------------------------------
function PropBuilders.launcher(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Rocket Launcher"
	local olive = Color3.fromRGB(74, 84, 54)
	local black = Color3.fromRGB(28, 28, 30)
	local tube = part(m, "Tube", Vector3.new(4.2, 0.55, 0.55), cf * CFrame.new(0, 0.35, -0.4) * CYL_Z, olive, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "RearFlare", Vector3.new(0.35, 0.7, 0.7), cf * CFrame.new(0, 0.35, 1.75) * CYL_Z, black, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "FrontRing", Vector3.new(0.2, 0.62, 0.62), cf * CFrame.new(0, 0.35, -2.4) * CYL_Z, black, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	local warhead = part(m, "Warhead", Vector3.new(0.7, 0.42, 0.42), cf * CFrame.new(0, 0.35, -2.8) * CYL_Z, Color3.fromRGB(110, 120, 80), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	local tip = part(m, "WarheadTip", Vector3.new(0.4, 0.4, 0.4), cf * CFrame.new(0, 0.35, -3.15), Color3.fromRGB(110, 120, 80), Enum.Material.Metal, { Shape = Enum.PartType.Ball })
	warhead:SetAttribute("Warhead", true)
	tip:SetAttribute("Warhead", true)
	part(m, "Sight", Vector3.new(0.12, 0.3, 0.3), cf * CFrame.new(-0.35, 0.6, -0.8), black, Enum.Material.Metal)
	local grip = part(m, "Handle", Vector3.new(0.22, 0.6, 0.3), cf * CFrame.new(0, -0.25, -0.1) * CFrame.Angles(math.rad(-10), 0, 0), black, Enum.Material.Fabric)
	part(m, "FrontGrip", Vector3.new(0.2, 0.5, 0.24), cf * CFrame.new(0, -0.12, -1.2), black, Enum.Material.Fabric)
	part(m, "Trigger", Vector3.new(0.05, 0.12, 0.05), cf * CFrame.new(0, 0.0, -0.3), Color3.fromRGB(150, 30, 30), Enum.Material.Metal)
	gripAttachment(grip, cf * CFrame.new(0, -0.22, -0.15))
	muzzleAt(tube, cf * CFrame.new(0, 0.35, -3.4))
	return finishGun(m, grip, "launcher", 1, 0.5)
end

------------------------------------------------------------------------
-- Blowgun: sleep darts (purple) or heal darts (green). Forward = -Z.
------------------------------------------------------------------------
local function blowgun(cf: CFrame, kind: string, name: string, band: Color3): Model
	local m = Instance.new("Model")
	m.Name = name
	local wood = Color3.fromRGB(120, 92, 60)
	local tube = part(m, "Tube", Vector3.new(2.6, 0.16, 0.16), cf * CFrame.new(0, 0, -0.9) * CYL_Z, wood, Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	part(m, "Mouthpiece", Vector3.new(0.18, 0.22, 0.22), cf * CFrame.new(0, 0, 0.42) * CYL_Z, Color3.fromRGB(40, 32, 26), Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	for _, z in { -0.3, -1.4 } do
		part(m, "Band", Vector3.new(0.12, 0.18, 0.18), cf * CFrame.new(0, 0, z) * CYL_Z, band, Enum.Material.Neon, { Shape = Enum.PartType.Cylinder })
	end
	part(m, "Quiver", Vector3.new(0.18, 0.18, 0.7), cf * CFrame.new(0.15, -0.12, -0.2), Color3.fromRGB(70, 50, 34), Enum.Material.Fabric)
	for i = 0, 2 do
		part(m, "Dart", Vector3.new(0.03, 0.03, 0.3), cf * CFrame.new(0.12 + i * 0.04, -0.02, -0.65), band, Enum.Material.Neon)
	end
	local grip = part(m, "Handle", Vector3.new(0.2, 0.2, 0.6), cf, wood, Enum.Material.Fabric)
	gripAttachment(grip, cf)
	muzzleAt(tube, cf * CFrame.new(0, 0, -2.25))
	return finishGun(m, grip, kind, 3, 0.5)
end

function PropBuilders.sleepdart(cf: CFrame): Model
	return blowgun(cf, "sleepdart", "Sleep Dart Blowgun", Color3.fromRGB(150, 80, 230))
end

function PropBuilders.healdart(cf: CFrame): Model
	return blowgun(cf, "healdart", "Heal Dart Blowgun", Color3.fromRGB(80, 230, 110))
end

-- (v2.8) SMART guns: a pistol / an SMG in white with teal lines and a smart-link module. With WARDEN OPTICS and a locked
-- target, every shot goes to it (even from the hip); without, they are ordinary guns.
local function smarten(m: Model, kind: string, name: string): Model
	m.Name = name
	local root = m.PrimaryPart :: BasePart
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Material ~= Enum.Material.Neon then
			local c = d.Color
			if (c.R + c.G + c.B) / 3 < 0.35 then
				d.Color = Color3.fromRGB(228, 232, 236) -- (the dark plastic / steel becomes white)
			end
		end
	end
	local top = root.CFrame
	local ext = root.Size
	local link = part(m, "SmartLink", Vector3.new(0.18, 0.14, 0.32), top * CFrame.new(0, ext.Y / 2 + 0.25, -0.1), Color3.fromRGB(30, 32, 38), Enum.Material.Metal)
	local led = part(m, "SmartLed", Vector3.new(0.19, 0.04, 0.2), top * CFrame.new(0, ext.Y / 2 + 0.33, -0.1), Color3.fromRGB(60, 230, 255), Enum.Material.Neon)
	for _, p in { link, led } do
		p.CanCollide = false
		p.Massless = true
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = p
	end
	m:SetAttribute("Item", kind)
	m:SetAttribute("Ammo", kind == "smartsmg" and 30 or 15)
	return m
end

function PropBuilders.smartpistol(cf: CFrame): Model
	return smarten(PropBuilders.pistol(cf), "smartpistol", "Smart Pistol")
end

function PropBuilders.smartsmg(cf: CFrame): Model
	return smarten(PropBuilders.smg(cf), "smartsmg", "Smart SMG")
end

-- (v2.8) paralysis darts: yellow bands. Down for Config.ParalysisTime s, awake (no dream).
function PropBuilders.paradart(cf: CFrame): Model
	return blowgun(cf, "paradart", "Paralysis Dart Blowgun", Color3.fromRGB(240, 210, 40))
end

-- (v2.8) a SYRINGE: a clear barrel with violet liquid, a plunger, a long needle. F aimed at somebody close (Config.SyringeRange):
-- they sleep Config.SyringeMult times as long as after a sleep dart. Used up.
function PropBuilders.syringe(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Syringe"
	local barrel = part(m, "Barrel", Vector3.new(0.7, 0.2, 0.2), cf * CYL_Z, Color3.fromRGB(220, 235, 245), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.35 })
	part(m, "Liquid", Vector3.new(0.5, 0.15, 0.15), cf * CFrame.new(0, 0, -0.08) * CYL_Z, Color3.fromRGB(170, 70, 255), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder })
	part(m, "Plunger", Vector3.new(0.4, 0.06, 0.06), cf * CFrame.new(0, 0, 0.5) * CYL_Z, Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "Thumb", Vector3.new(0.04, 0.22, 0.22), cf * CFrame.new(0, 0, 0.7) * CYL_Z, Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "Wings", Vector3.new(0.4, 0.04, 0.08), cf * CFrame.new(0, 0, 0.33), Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic)
	part(m, "Hub", Vector3.new(0.08, 0.1, 0.1), cf * CFrame.new(0, 0, -0.39) * CYL_Z, Color3.fromRGB(60, 160, 220), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "Needle", Vector3.new(0.02, 0.02, 0.5), cf * CFrame.new(0, 0, -0.68), Color3.fromRGB(200, 204, 210), Enum.Material.Metal, { Reflectance = 0.5 })
	gripAttachment(barrel, cf)
	setDensity(m, 0.5, 0.5, 0.05)
	m.PrimaryPart = barrel
	weldAll(m, barrel)
	m:SetAttribute("Item", "syringe")
	return m
end

------------------------------------------------------------------------
-- Katana: long curved blade, cuts limbs off easily. Forward = -Z.
------------------------------------------------------------------------
function PropBuilders.katana(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Katana"
	local handle = part(m, "Handle", Vector3.new(0.18, 0.22, 1.1), cf * CFrame.new(0, 0, 0.1), Color3.fromRGB(28, 26, 30), Enum.Material.Fabric)
	part(m, "Wrap", Vector3.new(0.19, 0.23, 0.9), cf * CFrame.new(0, 0, 0.1), Color3.fromRGB(150, 30, 34), Enum.Material.Fabric, { Transparency = 0.35 })
	part(m, "Pommel", Vector3.new(0.12, 0.24, 0.24), cf * CFrame.new(0, 0, 0.7) * CYL_Z, Color3.fromRGB(170, 150, 90), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Tsuba", Vector3.new(0.08, 0.6, 0.6), cf * CFrame.new(0, 0, -0.5) * CYL_Z, Color3.fromRGB(40, 38, 36), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Habaki", Vector3.new(0.1, 0.16, 0.2), cf * CFrame.new(0, 0, -0.62), Color3.fromRGB(190, 160, 90), Enum.Material.Metal)
	local blade = part(m, "Blade", Vector3.new(0.05, 0.22, 3.5), cf * CFrame.new(0, 0.03, -2.45) * CFrame.Angles(math.rad(-2.5), 0, 0), Color3.fromRGB(196, 200, 208), Enum.Material.Metal, { Reflectance = 0.45 })
	part(m, "Edge", Vector3.new(0.055, 0.06, 3.4), cf * CFrame.new(0, -0.08, -2.45) * CFrame.Angles(math.rad(-2.5), 0, 0), Color3.fromRGB(235, 238, 244), Enum.Material.Metal, { Reflectance = 0.6 })
	part(m, "Kissaki", Vector3.new(0.05, 0.16, 0.3), cf * CFrame.new(0, 0.12, -4.27) * CFrame.Angles(math.rad(-25), 0, 0), Color3.fromRGB(220, 224, 232), Enum.Material.Metal, { Reflectance = 0.5 })
	blade:SetAttribute("Sharpness", 0.95)
	gripAttachment(handle, cf * CFrame.new(0, 0, 0.2))
	setDensity(m, 1.2, 0.5, 0.05)
	m.PrimaryPart = handle
	weldAll(m, handle)
	m:SetAttribute("Item", "katana")
	return m
end

------------------------------------------------------------------------
-- Sledgehammer: very heavy blunt swing. Forward = -Z (along the handle).
------------------------------------------------------------------------
function PropBuilders.sledge(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Sledgehammer"
	local handle = part(m, "Handle", Vector3.new(3.4, 0.22, 0.22), cf * CFrame.new(0, 0, -0.6) * CYL_Z, Color3.fromRGB(196, 160, 110), Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	part(m, "Grip", Vector3.new(0.8, 0.25, 0.25), cf * CFrame.new(0, 0, 0.75) * CYL_Z, Color3.fromRGB(30, 30, 32), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	part(m, "SledgeHead", Vector3.new(1.5, 0.7, 0.7), cf * CFrame.new(0, 0, -2.4), Color3.fromRGB(60, 62, 68), Enum.Material.Metal, { Reflectance = 0.1 })
	for _, x in { -0.78, 0.78 } do
		part(m, "Face", Vector3.new(0.06, 0.66, 0.66), cf * CFrame.new(x, 0, -2.4), Color3.fromRGB(150, 152, 158), Enum.Material.Metal, { Reflectance = 0.3 })
	end
	gripAttachment(handle, cf * CFrame.new(0, 0, 0.75))
	setDensity(m, 1.6, 0.5, 0.05)
	m.PrimaryPart = handle
	weldAll(m, handle)
	m:SetAttribute("Item", "sledge")
	return m
end

------------------------------------------------------------------------
-- C4: F throws it, it sticks to whatever it hits. The detonator sets it off.
------------------------------------------------------------------------
function PropBuilders.c4(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "C4"
	local tan = Color3.fromRGB(196, 178, 130)
	local body = part(m, "Body", Vector3.new(1.0, 0.36, 0.64), cf, tan, Enum.Material.SmoothPlastic)
	part(m, "Seam", Vector3.new(1.02, 0.37, 0.04), cf, Color3.fromRGB(150, 135, 96), Enum.Material.SmoothPlastic)
	part(m, "Tape", Vector3.new(0.12, 0.38, 0.66), cf * CFrame.new(-0.3, 0, 0), Color3.fromRGB(40, 40, 44), Enum.Material.Fabric)
	part(m, "Tape2", Vector3.new(0.12, 0.38, 0.66), cf * CFrame.new(0.3, 0, 0), Color3.fromRGB(40, 40, 44), Enum.Material.Fabric)
	part(m, "Timer", Vector3.new(0.34, 0.08, 0.26), cf * CFrame.new(0, 0.22, 0), Color3.fromRGB(26, 26, 28), Enum.Material.SmoothPlastic)
	local led = part(m, "LED", Vector3.new(0.08, 0.06, 0.08), cf * CFrame.new(0.1, 0.27, 0.06), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 50, 40)
	light.Range = 4
	light.Brightness = 1.5
	light.Parent = led
	part(m, "WireR", Vector3.new(0.04, 0.04, 0.5), cf * CFrame.new(-0.12, 0.24, 0.02) * CFrame.Angles(0, math.rad(20), 0), Color3.fromRGB(200, 40, 40), Enum.Material.SmoothPlastic)
	part(m, "WireB", Vector3.new(0.04, 0.04, 0.5), cf * CFrame.new(-0.18, 0.24, -0.02) * CFrame.Angles(0, math.rad(-15), 0), Color3.fromRGB(40, 60, 200), Enum.Material.SmoothPlastic)
	gripAttachment(body, cf)
	setDensity(m, 1.4, 0.8, 0.02)
	m.PrimaryPart = body
	weldAll(m, body)
	m:SetAttribute("Item", "c4")
	return m
end

function PropBuilders.detonator(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Detonator"
	local box = part(m, "Box", Vector3.new(0.4, 0.3, 0.7), cf, Color3.fromRGB(46, 50, 44), Enum.Material.SmoothPlastic)
	part(m, "Button", Vector3.new(0.1, 0.18, 0.18), cf * CFrame.new(0, 0.18, -0.1) * CYL_Y, Color3.fromRGB(220, 30, 30), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder })
	part(m, "Guard", Vector3.new(0.3, 0.05, 0.3), cf * CFrame.new(0, 0.17, -0.1), Color3.fromRGB(230, 190, 40), Enum.Material.SmoothPlastic)
	part(m, "Antenna", Vector3.new(0.04, 0.6, 0.04), cf * CFrame.new(0.12, 0.42, 0.28), Color3.fromRGB(30, 30, 30), Enum.Material.Metal)
	part(m, "AntennaTip", Vector3.new(0.08, 0.08, 0.08), cf * CFrame.new(0.12, 0.74, 0.28), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, { Shape = Enum.PartType.Ball })
	gripAttachment(box, cf)
	setDensity(m, 0.8, 0.6, 0.05)
	m.PrimaryPart = box
	weldAll(m, box)
	m:SetAttribute("Item", "detonator")
	return m
end

------------------------------------------------------------------------
-- Boombox: F -> paste a Roblox sound id, everybody hears it. The strip glows with the music.
------------------------------------------------------------------------
function PropBuilders.boombox(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Boombox"
	local body = part(m, "Body", Vector3.new(2.4, 1.2, 0.7), cf, Color3.fromRGB(34, 34, 40), Enum.Material.SmoothPlastic)
	for _, x in { -0.75, 0.75 } do
		part(m, "Speaker", Vector3.new(0.08, 0.8, 0.8), cf * CFrame.new(x, -0.05, -0.36) * CYL_Z, Color3.fromRGB(18, 18, 20), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
		part(m, "Cone", Vector3.new(0.1, 0.32, 0.32), cf * CFrame.new(x, -0.05, -0.38) * CYL_Z, Color3.fromRGB(150, 150, 158), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	end
	part(m, "Deck", Vector3.new(0.6, 0.35, 0.06), cf * CFrame.new(0, 0.05, -0.37), Color3.fromRGB(60, 60, 70), Enum.Material.Glass, { Transparency = 0.2 })
	part(m, "Glow", Vector3.new(2.2, 0.08, 0.06), cf * CFrame.new(0, 0.48, -0.37), Color3.fromRGB(40, 40, 60), Enum.Material.Neon)
	local grip = part(m, "Handle", Vector3.new(1.8, 0.12, 0.12), cf * CFrame.new(0, 0.85, 0), Color3.fromRGB(150, 152, 160), Enum.Material.Metal)
	for _, x in { -0.85, 0.85 } do
		part(m, "HandlePost", Vector3.new(0.1, 0.3, 0.1), cf * CFrame.new(x, 0.7, 0), Color3.fromRGB(150, 152, 160), Enum.Material.Metal)
	end
	gripAttachment(grip, cf * CFrame.new(0, 0.85, 0))
	setDensity(m, 0.4, 0.6, 0.05)
	m.PrimaryPart = grip
	weldAll(m, grip)
	m:SetAttribute("Item", "boombox")
	game:GetService("CollectionService"):AddTag(m, "Boombox")
	local _ = body
	return m
end

------------------------------------------------------------------------
-- Laser pointer: F switches it on / off; everybody sees the red beam and dot.
------------------------------------------------------------------------
function PropBuilders.laser(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Laser Pointer"
	local body = part(m, "Body", Vector3.new(0.75, 0.16, 0.16), cf * CYL_Z, Color3.fromRGB(40, 40, 46), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Reflectance = 0.2 })
	part(m, "Tip", Vector3.new(0.08, 0.12, 0.12), cf * CFrame.new(0, 0, -0.4) * CYL_Z, Color3.fromRGB(255, 40, 40), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder })
	part(m, "Button", Vector3.new(0.06, 0.05, 0.08), cf * CFrame.new(0, 0.08, 0.05), Color3.fromRGB(200, 30, 30), Enum.Material.SmoothPlastic)
	part(m, "Clip", Vector3.new(0.03, 0.04, 0.35), cf * CFrame.new(0.09, 0.02, 0.15), Color3.fromRGB(160, 160, 166), Enum.Material.Metal)
	gripAttachment(body, cf * CFrame.new(0, 0, 0.15))
	muzzleAt(body, cf * CFrame.new(0, 0, -0.45))
	setDensity(m, 0.6, 0.5, 0.05)
	m.PrimaryPart = body
	weldAll(m, body)
	m:SetAttribute("Item", "laser")
	return m
end

------------------------------------------------------------------------
-- Riot shield: stops bullets, blades, darts and thrown spears. Faces forward (-Z).
------------------------------------------------------------------------
function PropBuilders.shield(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Shield"
	local frame = Color3.fromRGB(28, 28, 32)
	local plate = part(m, "Plate", Vector3.new(2.3, 3.6, 0.14), cf * CFrame.new(0, 0.6, -0.35), Color3.fromRGB(150, 175, 200), Enum.Material.Glass, { Transparency = 0.35, Reflectance = 0.15 })
	part(m, "FrameTop", Vector3.new(2.36, 0.12, 0.18), cf * CFrame.new(0, 2.42, -0.35), frame, Enum.Material.SmoothPlastic)
	part(m, "FrameBottom", Vector3.new(2.36, 0.12, 0.18), cf * CFrame.new(0, -1.22, -0.35), frame, Enum.Material.SmoothPlastic)
	for _, x in { -1.18, 1.18 } do
		part(m, "FrameSide", Vector3.new(0.12, 3.72, 0.18), cf * CFrame.new(x, 0.6, -0.35), frame, Enum.Material.SmoothPlastic)
	end
	part(m, "Stripe", Vector3.new(2.3, 0.35, 0.15), cf * CFrame.new(0, -0.5, -0.36), Color3.fromRGB(30, 30, 34), Enum.Material.SmoothPlastic, { Transparency = 0.1 })
	local grip = part(m, "Handle", Vector3.new(0.14, 0.6, 0.14), cf, frame, Enum.Material.Fabric)
	part(m, "HandleMount", Vector3.new(0.5, 0.12, 0.3), cf * CFrame.new(0, 0, -0.2), frame, Enum.Material.Metal)
	gripAttachment(grip, cf)
	setDensity(m, 0.2, 0.5, 0.1)
	plate.CustomPhysicalProperties = PhysicalProperties.new(0.2, 0.5, 0.1, 1, 1)
	m.PrimaryPart = grip
	weldAll(m, grip)
	m:SetAttribute("Item", "shield")
	return m
end

------------------------------------------------------------------------
-- Virus bottle (game owner only): throw it, it shatters and releases the virus.
------------------------------------------------------------------------
function PropBuilders.virus(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Virus"
	local glass = part(m, "Bottle", Vector3.new(1.0, 0.62, 0.62), cf * CYL_Y, Color3.fromRGB(200, 230, 210), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.55 })
	part(m, "Liquid", Vector3.new(0.75, 0.52, 0.52), cf * CFrame.new(0, -0.1, 0) * CYL_Y, Color3.fromRGB(90, 255, 70), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, Transparency = 0.15 })
	part(m, "Neck", Vector3.new(0.35, 0.24, 0.24), cf * CFrame.new(0, 0.66, 0) * CYL_Y, Color3.fromRGB(200, 230, 210), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.5 })
	part(m, "Cork", Vector3.new(0.2, 0.2, 0.2), cf * CFrame.new(0, 0.88, 0) * CYL_Y, Color3.fromRGB(150, 110, 70), Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	part(m, "Label", Vector3.new(0.3, 0.64, 0.64), cf * CFrame.new(0, 0.05, 0) * CYL_Y, Color3.fromRGB(240, 200, 30), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(110, 255, 90)
	glow.Range = 6
	glow.Brightness = 1.2
	glow.Parent = glass
	gripAttachment(glass, cf * CFrame.new(0, 0.1, 0))
	setDensity(m, 0.8, 0.4, 0.2)
	m.PrimaryPart = glass
	weldAll(m, glass)
	m:SetAttribute("Item", "virus")
	m:SetAttribute("OwnerOnly", true)
	return m
end

------------------------------------------------------------------------
-- Nuke (game owner only): F arms it - long countdown, then everything nearby is gone.
------------------------------------------------------------------------
function PropBuilders.nuke(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Nuke"
	local yellow = Color3.fromRGB(226, 186, 40)
	local black = Color3.fromRGB(26, 26, 28)
	local body = part(m, "Body", Vector3.new(3.0, 2.3, 2.3), cf * CYL_Z, yellow, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Nose", Vector3.new(2.3, 2.3, 2.3), cf * CFrame.new(0, 0, -1.5), yellow, Enum.Material.Metal, { Shape = Enum.PartType.Ball })
	part(m, "Rear", Vector3.new(2.0, 2.0, 2.0), cf * CFrame.new(0, 0, 1.5), yellow, Enum.Material.Metal, { Shape = Enum.PartType.Ball })
	for _, z in { -0.6, 0.6 } do
		part(m, "Stripe", Vector3.new(0.25, 2.34, 2.34), cf * CFrame.new(0, 0, z) * CYL_Z, black, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	end
	part(m, "TailBox", Vector3.new(1.9, 1.9, 1.2), cf * CFrame.new(0, 0, 2.8), black, Enum.Material.Metal)
	part(m, "FinH", Vector3.new(2.6, 0.1, 1.0), cf * CFrame.new(0, 0, 2.8), yellow, Enum.Material.Metal)
	part(m, "FinV", Vector3.new(0.1, 2.6, 1.0), cf * CFrame.new(0, 0, 2.8), yellow, Enum.Material.Metal)
	local display = part(m, "Display", Vector3.new(0.9, 0.5, 0.08), cf * CFrame.new(0, 0.6, -0.2) * CFrame.Angles(math.rad(-60), 0, 0), Color3.fromRGB(14, 14, 16), Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Screen"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Parent = display
	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.Size = UDim2.fromScale(1, 1)
	count.BackgroundTransparency = 1
	count.Text = "--"
	count.TextScaled = true
	count.Font = Enum.Font.Sarpanch
	count.TextColor3 = Color3.fromRGB(255, 50, 40)
	count.Parent = gui
	local grip = part(m, "Handle", Vector3.new(0.2, 0.2, 1.2), cf * CFrame.new(0, 1.3, 0.2), black, Enum.Material.Metal)
	gripAttachment(grip, cf * CFrame.new(0, 1.3, 0.2))
	setDensity(m, 0.12, 0.6, 0.05)
	m.PrimaryPart = grip
	weldAll(m, grip)
	m:SetAttribute("Item", "nuke")
	m:SetAttribute("OwnerOnly", true)
	local _ = body
	return m
end

------------------------------------------------------------------------
-- furniture and other movable props
------------------------------------------------------------------------
local function prop(name: string, root: BasePart, m: Model, density: number, friction: number?)
	setDensity(m, density, friction or 0.6, 0.1)
	m.Name = name
	m.PrimaryPart = root
	weldAll(m, root)
	return m
end

function PropBuilders.chair(cf: CFrame): Model
	local m = Instance.new("Model")
	local wood = Color3.fromRGB(150, 104, 62)
	local seat = part(m, "Seat", Vector3.new(2, 0.25, 2), cf * CFrame.new(0, -0.2, 0), wood, Enum.Material.WoodPlanks)
	for _, x in { -0.85, 0.85 } do
		for _, z in { -0.85, 0.85 } do
			part(m, "Leg", Vector3.new(0.2, 1.6, 0.2), cf * CFrame.new(x, -1.1, z), wood, Enum.Material.Wood)
		end
		part(m, "BackPost", Vector3.new(0.2, 2.2, 0.2), cf * CFrame.new(x, 0.9, 0.9), wood, Enum.Material.Wood)
	end
	part(m, "Back", Vector3.new(1.6, 0.9, 0.15), cf * CFrame.new(0, 1.4, 0.9), wood, Enum.Material.WoodPlanks)
	return prop("Chair", seat, m, 0.5)
end

function PropBuilders.table(cf: CFrame): Model
	local m = Instance.new("Model")
	local wood = Color3.fromRGB(120, 82, 50)
	local top = part(m, "Top", Vector3.new(6, 0.3, 3.4), cf * CFrame.new(0, 0.85, 0), wood, Enum.Material.WoodPlanks)
	for _, x in { -2.7, 2.7 } do
		for _, z in { -1.4, 1.4 } do
			part(m, "Leg", Vector3.new(0.3, 2.7, 0.3), cf * CFrame.new(x, -0.6, z), wood, Enum.Material.Wood)
		end
	end
	return prop("Table", top, m, 0.55)
end

function PropBuilders.sofa(cf: CFrame): Model
	local m = Instance.new("Model")
	local fabric = Color3.fromRGB(110, 60, 52)
	local base = part(m, "Base", Vector3.new(7, 1.2, 3), cf * CFrame.new(0, -0.6, 0), fabric, Enum.Material.Fabric)
	part(m, "Back", Vector3.new(7, 1.8, 0.8), cf * CFrame.new(0, 0.9, 1.1), fabric, Enum.Material.Fabric)
	for _, x in { -3.2, 3.2 } do
		part(m, "Arm", Vector3.new(0.7, 1.2, 3), cf * CFrame.new(x, 0.4, 0), fabric, Enum.Material.Fabric)
	end
	for _, x in { -1.6, 1.6 } do
		part(m, "Cushion", Vector3.new(2.9, 0.45, 2.1), cf * CFrame.new(x, 0.2, -0.3), fabric:Lerp(Color3.new(1, 1, 1), 0.08), Enum.Material.Fabric)
	end
	return prop("Sofa", base, m, 0.3, 0.8)
end

function PropBuilders.bed(cf: CFrame): Model
	local m = Instance.new("Model")
	local frame = part(m, "Frame", Vector3.new(4.4, 0.9, 7.4), cf * CFrame.new(0, -0.7, 0), Color3.fromRGB(110, 74, 46), Enum.Material.Wood)
	part(m, "Mattress", Vector3.new(4.2, 0.8, 7.2), cf * CFrame.new(0, 0.15, 0), Color3.fromRGB(235, 235, 240), Enum.Material.Fabric)
	part(m, "Blanket", Vector3.new(4.25, 0.85, 4.6), cf * CFrame.new(0, 0.2, -1.2), Color3.fromRGB(60, 90, 150), Enum.Material.Fabric)
	part(m, "Pillow", Vector3.new(3, 0.5, 1.2), cf * CFrame.new(0, 0.75, 2.8), Color3.fromRGB(250, 250, 252), Enum.Material.Fabric)
	part(m, "Headboard", Vector3.new(4.4, 2.6, 0.3), cf * CFrame.new(0, 0.4, 3.75), Color3.fromRGB(110, 74, 46), Enum.Material.WoodPlanks)
	return prop("Bed", frame, m, 0.35, 0.8)
end

function PropBuilders.tv(cf: CFrame): Model
	local m = Instance.new("Model")
	local screen = part(m, "Screen", Vector3.new(4.2, 2.5, 0.25), cf * CFrame.new(0, 0.5, 0), Color3.fromRGB(16, 16, 20), Enum.Material.Glass, { Reflectance = 0.3 })
	part(m, "Bezel", Vector3.new(4.4, 2.7, 0.2), cf * CFrame.new(0, 0.5, 0.06), Color3.fromRGB(30, 30, 34), Enum.Material.SmoothPlastic)
	part(m, "Stand", Vector3.new(0.3, 0.7, 0.3), cf * CFrame.new(0, -1.05, 0.1), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
	part(m, "Foot", Vector3.new(1.6, 0.1, 0.9), cf * CFrame.new(0, -1.4, 0.1), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
	-- F (or the button on the gamepad) next to it switches it on: every client then plays a show
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TVPrompt"
	prompt.ActionText = "Switch on"
	prompt.ObjectText = "TV"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = screen
	m:SetAttribute("TV", true)
	return prop("TV", screen, m, 0.6)
end

function PropBuilders.fridge(cf: CFrame): Model
	local m = Instance.new("Model")
	local white = Color3.fromRGB(232, 234, 236)
	local body = part(m, "Body", Vector3.new(3, 6.4, 2.8), cf, white, Enum.Material.SmoothPlastic)
	part(m, "Gap", Vector3.new(3.02, 0.06, 2.82), cf * CFrame.new(0, 1.2, 0), Color3.fromRGB(120, 122, 126), Enum.Material.SmoothPlastic)
	for _, y in { 2.2, -0.5 } do
		part(m, "Handle", Vector3.new(0.12, 1.2, 0.15), cf * CFrame.new(1.2, y, -1.47), Color3.fromRGB(170, 172, 178), Enum.Material.Metal)
	end
	return prop("Fridge", body, m, 1.1)
end

function PropBuilders.shelf(cf: CFrame): Model
	local m = Instance.new("Model")
	local wood = Color3.fromRGB(140, 100, 64)
	local back = part(m, "Back", Vector3.new(4, 6, 0.2), cf * CFrame.new(0, 0, 0.7), wood, Enum.Material.WoodPlanks)
	for _, x in { -1.9, 1.9 } do
		part(m, "Side", Vector3.new(0.2, 6, 1.6), cf * CFrame.new(x, 0, 0), wood, Enum.Material.WoodPlanks)
	end
	for i = 0, 3 do
		local y = -2.9 + i * 1.9
		part(m, "Board", Vector3.new(3.6, 0.15, 1.5), cf * CFrame.new(0, y, 0), wood, Enum.Material.WoodPlanks)
		for b = 0, 4 do
			part(m, "Book", Vector3.new(0.35, 1.1, 1.1), cf * CFrame.new(-1.4 + b * 0.55 + (i % 2) * 0.2, y + 0.65, 0), Color3.fromHSV((b * 0.17 + i * 0.29) % 1, 0.55, 0.6), Enum.Material.SmoothPlastic)
		end
	end
	return prop("Bookshelf", back, m, 0.5)
end

function PropBuilders.lamp(cf: CFrame): Model
	local m = Instance.new("Model")
	local base = part(m, "Base", Vector3.new(0.2, 1.2, 1.2), cf * CFrame.new(0, -2.6, 0) * CYL_Y, Color3.fromRGB(30, 30, 34), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Pole", Vector3.new(4.8, 0.14, 0.14), cf * CFrame.new(0, -0.1, 0) * CYL_Y, Color3.fromRGB(30, 30, 34), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	local shade = part(m, "Shade", Vector3.new(1.0, 1.4, 1.4), cf * CFrame.new(0, 2.6, 0) * CYL_Y, Color3.fromRGB(240, 226, 190), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 170)
	light.Range = 16
	light.Brightness = 1.2
	light.Shadows = true
	light.Parent = shade
	return prop("Lamp", base, m, 0.6)
end

function PropBuilders.tire(cf: CFrame): Model
	local m = Instance.new("Model")
	local tire = part(m, "Tire", Vector3.new(1.0, 2.8, 2.8), cf * CYL_Z, Color3.fromRGB(26, 26, 28), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	part(m, "Rim", Vector3.new(1.04, 1.5, 1.5), cf * CYL_Z, Color3.fromRGB(150, 152, 160), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	return prop("Tire", tire, m, 0.5, 0.9)
end

function PropBuilders.cone(cf: CFrame): Model
	local m = Instance.new("Model")
	local base = part(m, "Base", Vector3.new(1.4, 0.15, 1.4), cf * CFrame.new(0, -0.85, 0), Color3.fromRGB(240, 110, 30), Enum.Material.SmoothPlastic)
	part(m, "Low", Vector3.new(0.5, 0.9, 0.9), cf * CFrame.new(0, -0.5, 0) * CYL_Y, Color3.fromRGB(240, 110, 30), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "Stripe", Vector3.new(0.3, 0.72, 0.72), cf * CFrame.new(0, -0.05, 0) * CYL_Y, Color3.fromRGB(245, 245, 245), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "High", Vector3.new(0.6, 0.5, 0.5), cf * CFrame.new(0, 0.4, 0) * CYL_Y, Color3.fromRGB(240, 110, 30), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	return prop("Traffic Cone", base, m, 0.4)
end

function PropBuilders.pallet(cf: CFrame): Model
	local m = Instance.new("Model")
	local wood = Color3.fromRGB(170, 132, 84)
	local mid = part(m, "Stringer", Vector3.new(4, 0.45, 0.4), cf, wood, Enum.Material.WoodPlanks)
	for _, z in { -1.5, 1.5 } do
		part(m, "Stringer", Vector3.new(4, 0.45, 0.4), cf * CFrame.new(0, 0, z), wood, Enum.Material.WoodPlanks)
	end
	for i = 0, 6 do
		part(m, "Board", Vector3.new(0.45, 0.12, 3.6), cf * CFrame.new(-1.75 + i * 0.58, 0.28, 0), wood, Enum.Material.WoodPlanks)
	end
	return prop("Pallet", mid, m, 0.45)
end

function PropBuilders.trashcan(cf: CFrame): Model
	local m = Instance.new("Model")
	local can = part(m, "Can", Vector3.new(3, 2, 2), cf * CYL_Y, Color3.fromRGB(70, 90, 70), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Lid", Vector3.new(0.2, 2.15, 2.15), cf * CFrame.new(0, 1.55, 0) * CYL_Y, Color3.fromRGB(60, 78, 60), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "LidHandle", Vector3.new(0.6, 0.15, 0.15), cf * CFrame.new(0, 1.72, 0), Color3.fromRGB(150, 150, 156), Enum.Material.Metal)
	return prop("Trash Can", can, m, 0.4)
end

------------------------------------------------------------------------
-- Car (open off-road jeep). Forward = -Z, cf = chassis centre.
-- Raycast suspension: the driver's client pushes the chassis with one VectorForce per wheel
-- ("Force_FL" ... at "Mount_FL" ...) and animates the wheel Welds. The wheels are SOLID: a parked
-- car simply stands on them (the driver's client turns them off while it drives).
------------------------------------------------------------------------
local CAR_COLORS = {
	Color3.fromRGB(196, 44, 40),
	Color3.fromRGB(40, 92, 170),
	Color3.fromRGB(226, 180, 40),
	Color3.fromRGB(64, 130, 70),
	Color3.fromRGB(230, 230, 232),
	Color3.fromRGB(214, 110, 36),
}

PropBuilders.WHEELS = {
	FL = Vector3.new(-3.0, -0.1, -3.7),
	FR = Vector3.new(3.0, -0.1, -3.7),
	RL = Vector3.new(-3.0, -0.1, 3.9),
	RR = Vector3.new(3.0, -0.1, 3.9),
}
PropBuilders.WHEEL_REST_DROP = 0.73 -- CarSuspensionRest - CarSag: the wheel centre below its mount when parked

function PropBuilders.car(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Car"
	local paint = CAR_COLORS[math.random(1, #CAR_COLORS)]
	local dark = Color3.fromRGB(38, 38, 42)
	local trim = Color3.fromRGB(26, 26, 29)
	local chrome = Color3.fromRGB(190, 192, 198)
	local seatCol = Color3.fromRGB(58, 44, 36)
	local SP = Enum.Material.SmoothPlastic
	local MT = Enum.Material.Metal
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local chassis = part(m, "Chassis", Vector3.new(5.0, 0.7, 11.0), cf, dark, MT)
	local tub = part(m, "Tub", Vector3.new(5.6, 1.3, 11.4), at(0, 1.0, 0), paint, SP)
	-- inside of the tub (the cabin floor is lower than the sides)
	part(m, "CabinFloor", Vector3.new(5.0, 0.12, 4.6), at(0, 1.7, 1.2), Color3.fromRGB(44, 44, 48), Enum.Material.DiamondPlate)
	for _, x in { -2.725, 2.725 } do
		-- side walls of the cabin, with a step-in cut-out and a door seam
		part(m, "Side", Vector3.new(0.15, 0.55, 4.6), at(x, 1.95, 1.2), paint, SP)
		part(m, "DoorSeam", Vector3.new(0.16, 1.7, 0.06), at(x, 1.35, -0.6), trim, SP)
		part(m, "DoorSeam", Vector3.new(0.16, 1.7, 0.06), at(x, 1.35, 2.2), trim, SP)
		part(m, "DoorHandle", Vector3.new(0.12, 0.08, 0.3), at(x * 1.025, 1.85, 1.7), chrome, MT)
		part(m, "SideStep", Vector3.new(0.5, 0.12, 3.6), at(x * 1.1, 0.3, 0.8), trim, Enum.Material.DiamondPlate)
		part(m, "Mirror", Vector3.new(0.12, 0.38, 0.5), at(x * 1.12, 2.75, -1.8), trim, SP)
		part(m, "MirrorArm", Vector3.new(0.35, 0.06, 0.06), at(x * 1.06, 2.6, -1.8), trim, MT)
	end
	-- fenders / wheel arches
	for name, mount in PropBuilders.WHEELS do
		local front = mount.Z < 0
		local x = mount.X * 0.98
		part(m, "Fender_" .. name, Vector3.new(1.3, 0.22, 3.1), at(x, 1.75, mount.Z), front and paint or paint:Lerp(Color3.new(0, 0, 0), 0.1), SP)
		part(m, "FenderLip_" .. name, Vector3.new(1.32, 0.5, 0.18), at(x, 1.5, mount.Z + 1.5), trim, SP)
		part(m, "FenderLip_" .. name, Vector3.new(1.32, 0.5, 0.18), at(x, 1.5, mount.Z - 1.5), trim, SP)
	end
	local hood = part(m, "Hood", Vector3.new(5.3, 0.5, 3.8), at(0, 1.92, -3.75), paint, SP)
	part(m, "HoodScoop", Vector3.new(1.6, 0.22, 1.4), at(0, 2.25, -3.6), trim, SP)
	part(m, "Grille", Vector3.new(3.0, 1.0, 0.12), at(0, 1.25, -5.76), trim, SP)
	for i = -3, 3 do
		part(m, "GrilleSlat", Vector3.new(0.12, 0.9, 0.08), at(i * 0.4, 1.25, -5.84), chrome, MT)
	end
	part(m, "FrontBumper", Vector3.new(6.0, 0.55, 0.6), at(0, 0.55, -5.95), trim, MT)
	part(m, "BullBar", Vector3.new(3.4, 0.16, 0.16), at(0, 1.95, -6.15), chrome, MT, { Reflectance = 0.2 })
	for _, x in { -1.6, 1.6 } do
		part(m, "BullBarPost", Vector3.new(0.16, 1.3, 0.16), at(x, 1.3, -6.15), chrome, MT, { Reflectance = 0.2 })
	end
	part(m, "RearBumper", Vector3.new(6.0, 0.55, 0.6), at(0, 0.55, 5.95), trim, MT)
	part(m, "Tailgate", Vector3.new(5.0, 1.2, 0.12), at(0, 1.25, 5.72), paint:Lerp(Color3.new(0, 0, 0), 0.12), SP)
	part(m, "PlateFront", Vector3.new(1.4, 0.4, 0.05), at(0, 0.55, -6.27), Color3.fromRGB(235, 235, 228), SP)
	part(m, "PlateRear", Vector3.new(1.4, 0.4, 0.05), at(0, 0.55, 6.27), Color3.fromRGB(235, 235, 228), SP)
	part(m, "Exhaust", Vector3.new(0.6, 0.22, 0.22), at(2.0, 0.25, 5.95) * CYL_Z, chrome, MT, { Shape = Enum.PartType.Cylinder })
	for _, x in { -2.0, 2.0 } do
		local hl = part(m, "Headlight", Vector3.new(0.14, 0.7, 0.7), at(x, 1.4, -5.78) * CYL_Z, Color3.fromRGB(255, 248, 220), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder })
		part(m, "HeadlightRing", Vector3.new(0.1, 0.84, 0.84), at(x, 1.4, -5.74) * CYL_Z, chrome, MT, { Shape = Enum.PartType.Cylinder })
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Right -- (the cylinder's +X axis points forward here)
		spot.Range = 45
		spot.Angle = 55
		spot.Brightness = 1.6
		spot.Color = Color3.fromRGB(255, 244, 214)
		spot.Parent = hl
		part(m, "FogLight", Vector3.new(0.4, 0.22, 0.1), at(x * 0.75, 0.55, -6.28), Color3.fromRGB(255, 220, 140), Enum.Material.Neon)
		part(m, "Taillight", Vector3.new(0.7, 0.4, 0.12), at(x * 1.1, 1.4, 5.8), Color3.fromRGB(200, 20, 20), Enum.Material.Neon)
	end
	-- windshield and roll cage
	for _, x in { -2.5, 2.5 } do
		part(m, "WindshieldPost", Vector3.new(0.18, 1.6, 0.18), at(x, 2.95, -1.95), trim, MT)
		part(m, "RollbarPost", Vector3.new(0.22, 2.3, 0.22), at(x * 0.98, 2.9, 2.6), trim, MT)
		part(m, "CageRail", Vector3.new(0.18, 0.18, 4.55), at(x * 0.98, 3.95, 0.33), trim, MT)
	end
	part(m, "Windshield", Vector3.new(4.8, 1.3, 0.08), at(0, 2.9, -1.95), Color3.fromRGB(170, 205, 230), Enum.Material.Glass, { Transparency = 0.55, CanCollide = false })
	part(m, "WindshieldTop", Vector3.new(5.2, 0.16, 0.18), at(0, 3.75, -1.95), trim, MT)
	part(m, "Rollbar", Vector3.new(5.1, 0.22, 0.22), at(0, 4.05, 2.6), trim, MT)
	part(m, "RollbarBrace", Vector3.new(0.18, 0.18, 2.6), at(0, 3.0, 3.6) * CFrame.Angles(math.rad(-38), 0, 0), trim, MT)
	part(m, "Dashboard", Vector3.new(5.0, 0.5, 0.6), at(0, 2.15, -1.6), trim, SP)
	part(m, "Gauge", Vector3.new(0.05, 0.35, 0.35), at(-1.25, 2.3, -1.28) * CYL_Z, Color3.fromRGB(220, 220, 200), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	-- seats
	local seat = part(m, "DriverSeat", Vector3.new(1.8, 0.35, 1.7), at(-1.25, 1.93, 0.65), seatCol, Enum.Material.Fabric)
	part(m, "DriverBack", Vector3.new(1.8, 1.7, 0.32), at(-1.25, 2.85, 1.55), seatCol, Enum.Material.Fabric)
	part(m, "DriverHeadrest", Vector3.new(1.0, 0.45, 0.28), at(-1.25, 3.95, 1.58), seatCol, Enum.Material.Fabric)
	part(m, "PassengerSeat", Vector3.new(1.8, 0.35, 1.7), at(1.25, 1.93, 0.65), seatCol, Enum.Material.Fabric)
	part(m, "PassengerBack", Vector3.new(1.8, 1.7, 0.32), at(1.25, 2.85, 1.55), seatCol, Enum.Material.Fabric)
	part(m, "PassengerHeadrest", Vector3.new(1.0, 0.45, 0.28), at(1.25, 3.95, 1.58), seatCol, Enum.Material.Fabric)
	part(m, "SteeringColumn", Vector3.new(0.12, 0.12, 0.7), at(-1.25, 2.5, -1.2) * CFrame.Angles(math.rad(-25), 0, 0), trim, MT)
	part(m, "SteeringWheel", Vector3.new(0.12, 1.15, 1.15), at(-1.25, 2.75, -0.85) * CFrame.Angles(math.rad(-25), 0, 0) * CYL_Z, trim, SP, { Shape = Enum.PartType.Cylinder })
	part(m, "SpareWheel", Vector3.new(0.9, 2.2, 2.2), at(0, 1.9, 6.35) * CYL_Z, Color3.fromRGB(24, 24, 26), SP, { Shape = Enum.PartType.Cylinder })
	part(m, "SpareRim", Vector3.new(0.94, 1.2, 1.2), at(0, 1.9, 6.35) * CYL_Z, chrome, MT, { Shape = Enum.PartType.Cylinder })
	local seatAtt = Instance.new("Attachment")
	seatAtt.Name = "SeatAtt"
	seatAtt.CFrame = CFrame.new(0, 1.175, -0.1) -- torso centre when seated, facing forward
	seatAtt.Parent = seat
	local passSeat = m:FindFirstChild("PassengerSeat")
	if passSeat then
		local pa = seatAtt:Clone()
		pa.Parent = passSeat
	end
	-- engine smoke / fire (hidden HP)
	local smoke = Instance.new("Smoke")
	smoke.Name = "EngineSmoke"
	smoke.Color = Color3.fromRGB(70, 68, 66)
	smoke.Opacity = 0.3
	smoke.RiseVelocity = 7
	smoke.Size = 4
	smoke.Enabled = false
	smoke.Parent = hood
	local fire = Instance.new("Fire")
	fire.Name = "EngineFire"
	fire.Size = 6
	fire.Heat = 12
	fire.Enabled = false
	fire.Parent = hood

	deflicker(m, chassis)
	setDensity(m, 0.35, 0.5, 0.05)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(3, 0.3, 0.05, 1, 1)
	tub.CustomPhysicalProperties = PhysicalProperties.new(0.35, 0.3, 0.05, 1, 1)
	-- small trim does not need to collide
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") and (d.Size.X < 0.2 or d.Size.Y < 0.13 or d.Size.Z < 0.13) and d ~= chassis then
			d.CanCollide = false
		end
	end

	-- wheels: solid (a parked car stands on them), animated by the driver's client through Welds
	for name, mount in PropBuilders.WHEELS do
		local rest = CFrame.new(mount - Vector3.new(0, PropBuilders.WHEEL_REST_DROP, 0))
		local wheel = part(m, "Wheel_" .. name, Vector3.new(1.0, 2.6, 2.6), cf * rest, Color3.fromRGB(24, 24, 26), SP, { Shape = Enum.PartType.Cylinder, CanCollide = true, Massless = true, CanQuery = false })
		wheel.CustomPhysicalProperties = PhysicalProperties.new(0.5, 1.1, 0.05, 2, 1)
		local deco = {
			part(m, "Tread_" .. name, Vector3.new(0.7, 2.66, 2.66), cf * rest, Color3.fromRGB(34, 34, 36), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder }),
			part(m, "Rim_" .. name, Vector3.new(1.04, 1.4, 1.4), cf * rest, chrome, MT, { Shape = Enum.PartType.Cylinder, Reflectance = 0.2 }),
			part(m, "Hub_" .. name, Vector3.new(1.1, 0.45, 0.45), cf * rest, Color3.fromRGB(120, 122, 128), MT, { Shape = Enum.PartType.Cylinder }),
		}
		for _, dpart in deco do
			dpart.CanCollide = false
			dpart.CanQuery = string.match(dpart.Name, "^Tread_") ~= nil -- (bullets hit the tire: it pops)
			dpart.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = wheel
			w.Part1 = dpart
			w.Parent = dpart
		end
		local weld = Instance.new("Weld")
		weld.Name = "WheelWeld"
		weld.Part0 = chassis
		weld.Part1 = wheel
		weld.C0 = rest
		weld.C1 = CFrame.identity
		weld.Parent = wheel
		local mountAtt = Instance.new("Attachment")
		mountAtt.Name = "Mount_" .. name
		mountAtt.Position = mount
		mountAtt.Parent = chassis
		local force = Instance.new("VectorForce")
		force.Name = "Force_" .. name
		force.Attachment0 = mountAtt
		force.RelativeTo = Enum.ActuatorRelativeTo.World
		force.ApplyAtCenterOfMass = false
		force.Force = Vector3.zero
		force.Visible = false
		force.Parent = chassis
	end
	local wheelish = { "^Wheel_", "^Rim_", "^Tread_", "^Hub_" }
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") and d ~= chassis then
			local isWheel = false
			for _, pat in wheelish do
				if string.match(d.Name, pat) then
					isWheel = true
				end
			end
			if not isWheel then
				local w = Instance.new("WeldConstraint")
				w.Part0 = chassis
				w.Part1 = d
				w.Parent = d
			end
		end
	end
	m.PrimaryPart = chassis
	m:SetAttribute("Car", true)
	m:SetAttribute("CarHP", 260)
	return m
end

------------------------------------------------------------------------
-- (v2.8) the VAN and the TANK: the same raycast suspension as the car (CarPhysics: Mount_/Force_ per wheel, wheels on welds)
------------------------------------------------------------------------

-- four wheels on a chassis (the same rig as the car's): visible = tires and rims, else hidden inside tracks
local function wheelSet(m: Model, chassis: BasePart, cf: CFrame, mounts: { [string]: Vector3 }, radius: number, visible: boolean)
	local chrome = Color3.fromRGB(150, 152, 158)
	for name, mount in mounts do
		local rest = CFrame.new(mount - Vector3.new(0, PropBuilders.WHEEL_REST_DROP, 0))
		local wheel = part(m, "Wheel_" .. name, Vector3.new(1.1, radius * 2, radius * 2), cf * rest, Color3.fromRGB(24, 24, 26), Enum.Material.SmoothPlastic,
			{ Shape = Enum.PartType.Cylinder, CanCollide = true, Massless = true, CanQuery = false, Transparency = visible and 0 or 1 })
		wheel.CustomPhysicalProperties = PhysicalProperties.new(0.5, 1.1, 0.05, 2, 1)
		if visible then
			local deco = {
				part(m, "Tread_" .. name, Vector3.new(0.8, radius * 2 + 0.06, radius * 2 + 0.06), cf * rest, Color3.fromRGB(34, 34, 36), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder }),
				part(m, "Rim_" .. name, Vector3.new(1.14, radius * 1.1, radius * 1.1), cf * rest, chrome, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Reflectance = 0.2 }),
			}
			for _, dpart in deco do
				dpart.CanCollide = false
				dpart.CanQuery = string.match(dpart.Name, "^Tread_") ~= nil
				dpart.Massless = true
				local w = Instance.new("WeldConstraint")
				w.Part0 = wheel
				w.Part1 = dpart
				w.Parent = dpart
			end
		end
		local weld = Instance.new("Weld")
		weld.Name = "WheelWeld"
		weld.Part0 = chassis
		weld.Part1 = wheel
		weld.C0 = rest
		weld.C1 = CFrame.identity
		weld.Parent = wheel
		local mountAtt = Instance.new("Attachment")
		mountAtt.Name = "Mount_" .. name
		mountAtt.Position = mount
		mountAtt.Parent = chassis
		local force = Instance.new("VectorForce")
		force.Name = "Force_" .. name
		force.Attachment0 = mountAtt
		force.RelativeTo = Enum.ActuatorRelativeTo.World
		force.ApplyAtCenterOfMass = false
		force.Force = Vector3.zero
		force.Visible = false
		force.Parent = chassis
	end
end

-- welds everything but the wheels (and parts that have their own weld) to the chassis
local function weldBody(m: Model, chassis: BasePart)
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") and d ~= chassis and not string.match(d.Name, "^Wheel_") and not string.match(d.Name, "^Tread_") and not string.match(d.Name, "^Rim_")
			and not d:GetAttribute("OwnWeld") then
			local w = Instance.new("WeldConstraint")
			w.Part0 = chassis
			w.Part1 = d
			w.Parent = d
		end
	end
end

local function seat(m: Model, name: string, at: CFrame, col: Color3): BasePart
	local s = part(m, name, Vector3.new(1.8, 0.35, 1.7), at, col, Enum.Material.Fabric)
	part(m, name .. "Back", Vector3.new(1.8, 1.7, 0.32), at * CFrame.new(0, 0.92, 0.9), col, Enum.Material.Fabric)
	local a = Instance.new("Attachment")
	a.Name = "SeatAtt"
	a.CFrame = CFrame.new(0, 1.175, -0.1)
	a.Parent = s
	return s
end

-- (v2.8) the VAN: a black panel van. Two seats in the cab, a cargo box behind with two back doors (open / close them, put
-- a body you carry inside: VanService). Drives like the car, a little slower.
-- (v2.8.1) Bigger: the cargo box is 6.8 studs high inside - you walk around in it - with two steps up at the back, a bench
-- along one wall, rails and a light. Front = -Z.
function PropBuilders.van(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Van"
	local paint = Color3.fromRGB(26, 27, 31)
	local stripe = Color3.fromRGB(200, 30, 40)
	local trim = Color3.fromRGB(16, 16, 18)
	local chrome = Color3.fromRGB(180, 182, 188)
	local glass = Color3.fromRGB(120, 150, 170)
	local inside = Color3.fromRGB(58, 58, 62)
	local SP, MT = Enum.Material.SmoothPlastic, Enum.Material.Metal
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local chassis = part(m, "Chassis", Vector3.new(6.6, 0.8, 19.0), cf, trim, MT)
	part(m, "Body", Vector3.new(7.4, 1.5, 19.6), at(0, 1.15, 0), paint, SP)
	part(m, "Stripe", Vector3.new(7.44, 0.3, 19.64), at(0, 1.5, 0), stripe, SP)
	-- the cab (front, -Z): walls, a windshield, side windows, the roof
	part(m, "CabFloor", Vector3.new(7.0, 0.12, 5.2), at(0, 1.95, -6.6), Color3.fromRGB(40, 40, 44), Enum.Material.DiamondPlate)
	for _, x in { -3.6, 3.6 } do
		part(m, "CabSide", Vector3.new(0.2, 1.6, 5.4), at(x, 2.7, -6.6), paint, SP)
		part(m, "CabWindow", Vector3.new(0.12, 2.7, 4.4), at(x, 4.85, -6.6), glass, Enum.Material.Glass, { Transparency = 0.45 })
		part(m, "CabPillar", Vector3.new(0.26, 4.3, 0.34), at(x, 4.05, -9.2), paint, SP)
		part(m, "Mirror", Vector3.new(0.14, 0.7, 0.7), at(x * 1.12, 4.2, -8.8), trim, SP)
		part(m, "SideStep", Vector3.new(0.6, 0.14, 3.8), at(x * 1.08, 0.4, -6.5), trim, Enum.Material.DiamondPlate)
	end
	part(m, "Windshield", Vector3.new(7.0, 3.0, 0.12), at(0, 4.7, -9.25) * CFrame.Angles(math.rad(-12), 0, 0), glass, Enum.Material.Glass, { Transparency = 0.45 })
	-- (v2.8.2) the cab finished: a pillar behind each side window (no gap to the box), door seams and handles, and a wind
	-- deflector on the cab roof that runs up to the box (no more step between the low cab and the tall box)
	for _, x in { -3.6, 3.6 } do
		part(m, "CabPillarB", Vector3.new(0.26, 4.4, 0.9), at(x, 4.05, -3.85), paint, SP)
		part(m, "DoorSeam", Vector3.new(0.05, 4.2, 0.06), at(x * 1.006, 3.7, -8.75), trim, SP)
		part(m, "DoorSeam", Vector3.new(0.05, 4.2, 0.06), at(x * 1.006, 3.7, -4.45), trim, SP)
		part(m, "CabHandle", Vector3.new(0.12, 0.14, 0.6), at(x * 1.02, 3.45, -5.1), chrome, MT)
		part(m, "Fender", Vector3.new(0.5, 0.35, 3.4), at(x * 1.04, 1.75, -6.6), trim, SP)
		part(m, "Fender", Vector3.new(0.5, 0.35, 3.4), at(x * 1.04, 1.75, 6.4), trim, SP)
		part(m, "MarkerLight", Vector3.new(0.1, 0.25, 0.5), at(x * 1.045, 8.4, 9.2), Color3.fromRGB(255, 150, 40), SP)
		part(m, "MarkerLight", Vector3.new(0.1, 0.25, 0.5), at(x * 1.045, 8.4, -2.6), Color3.fromRGB(255, 150, 40), SP)
	end
	do
		local deflector = Instance.new("WedgePart")
		deflector.Name = "WindDeflector"
		deflector.Size = Vector3.new(7.2, 2.7, 2.6)
		deflector.CFrame = at(0, 7.85, -4.75)
		deflector.Color = paint
		deflector.Material = SP
		deflector.TopSurface = Enum.SurfaceType.Smooth
		deflector.BottomSurface = Enum.SurfaceType.Smooth
		deflector.Parent = m
	end
	part(m, "LicensePlate", Vector3.new(1.6, 0.6, 0.06), at(0, 0.7, -11.03), Color3.fromRGB(230, 230, 220), SP)
	part(m, "CabRoof", Vector3.new(7.4, 0.3, 5.8), at(0, 6.35, -6.6), paint, SP)
	part(m, "Hood", Vector3.new(7.2, 1.2, 1.6), at(0, 2.45, -9.9), paint, SP)
	part(m, "Grille", Vector3.new(4.2, 1.0, 0.12), at(0, 1.85, -10.75), trim, SP)
	for i = 0, 3 do
		part(m, "GrilleBar", Vector3.new(4.0, 0.08, 0.14), at(0, 1.5 + i * 0.24, -10.78), chrome, MT)
	end
	part(m, "FrontBumper", Vector3.new(7.6, 0.6, 0.6), at(0, 0.7, -10.7), chrome, MT)
	part(m, "Dashboard", Vector3.new(7.0, 0.7, 0.7), at(0, 2.75, -8.7), trim, SP)
	part(m, "SteeringWheel", Vector3.new(0.12, 1.2, 1.2), at(-1.7, 3.3, -8.1) * CFrame.Angles(math.rad(-30), 0, 0) * CYL_Z, trim, SP, { Shape = Enum.PartType.Cylinder })
	for _, x in { -2.8, 2.8 } do
		local hl = part(m, "Headlight", Vector3.new(0.14, 0.8, 0.8), at(x, 2.0, -10.76) * CYL_Z, Color3.fromRGB(255, 248, 220), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder })
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Right
		spot.Range = 45
		spot.Angle = 55
		spot.Brightness = 1.6
		spot.Parent = hl
		part(m, "Taillight", Vector3.new(0.5, 1.2, 0.12), at(x * 1.22, 3.0, 9.86), Color3.fromRGB(200, 20, 20), Enum.Material.Neon)
	end
	-- the cargo box (behind the cab): tall enough to stand and walk in
	for _, x in { -3.6, 3.6 } do
		part(m, "CargoWall", Vector3.new(0.3, 7.1, 13.0), at(x, 5.45, 3.2), paint, SP)
		part(m, "CargoStripe", Vector3.new(0.32, 0.35, 13.0), at(x, 2.6, 3.2), stripe, SP)
		part(m, "InnerRail", Vector3.new(0.12, 0.12, 11.6), at(x * 0.93, 5.0, 3.4), chrome, MT)
	end
	part(m, "CargoRoof", Vector3.new(7.6, 0.3, 13.2), at(0, 9.15, 3.2), paint, SP)
	part(m, "RoofRack", Vector3.new(6.2, 0.2, 10.0), at(0, 9.45, 3.4), trim, MT)
	part(m, "Bulkhead", Vector3.new(6.9, 7.1, 0.3), at(0, 5.45, -3.35), paint, SP)
	part(m, "BulkheadWindow", Vector3.new(2.4, 1.0, 0.32), at(0, 6.6, -3.35), glass, Enum.Material.Glass, { Transparency = 0.5 })
	local floor = part(m, "CargoFloor", Vector3.new(6.9, 0.2, 12.6), at(0, 2.0, 3.3), Color3.fromRGB(46, 46, 50), Enum.Material.DiamondPlate)
	floor:SetAttribute("Cargo", true)
	-- (v2.8.2) a bench along each wall: six places to sit (VanService)
	for _, x in { -2.6, 2.6 } do
		part(m, "Bench", Vector3.new(1.5, 0.4, 7.0), at(x, 3.6, 4.0), inside, Enum.Material.Fabric)
		part(m, "BenchLeg", Vector3.new(1.3, 1.3, 0.3), at(x, 2.75, 1.0), trim, MT)
		part(m, "BenchLeg", Vector3.new(1.3, 1.3, 0.3), at(x, 2.75, 7.0), trim, MT)
		part(m, "BenchBack", Vector3.new(0.2, 1.6, 7.0), at(x * 1.27, 4.8, 4.0), inside, Enum.Material.Fabric)
		for _, z in { 1.7, 4.0, 6.3 } do
			part(m, "Strap", Vector3.new(0.06, 1.2, 0.12), at(x * 1.25, 5.1, z), Color3.fromRGB(200, 160, 40), Enum.Material.Fabric)
		end
	end
	local lamp = part(m, "CargoLight", Vector3.new(2.4, 0.12, 0.6), at(0, 8.94, 3.2), Color3.fromRGB(255, 240, 210), Enum.Material.Neon)
	local pl = Instance.new("PointLight")
	pl.Range = 12
	pl.Brightness = 0.8
	pl.Color = Color3.fromRGB(255, 236, 200)
	pl.Parent = lamp
	part(m, "RearBumper", Vector3.new(7.6, 0.6, 0.6), at(0, 0.7, 10.05), chrome, MT)
	-- two steps up into the back
	-- (v2.8.2) one solid step box under the doors, two treads (it used to be a step hanging loose in the air)
	part(m, "RearStep", Vector3.new(3.6, 0.2, 1.0), at(0, 0.55, 10.4), trim, Enum.Material.DiamondPlate)
	part(m, "StepBox", Vector3.new(3.6, 1.2, 0.9), at(0, -0.15, 10.75), trim, MT)
	part(m, "RearStepLow", Vector3.new(3.6, 0.2, 0.8), at(0, -0.65, 11.55), trim, Enum.Material.DiamondPlate)
	part(m, "StepRiser", Vector3.new(3.6, 0.5, 0.2), at(0, -0.85, 11.15), trim, MT)
	-- the back doors: each on a hinge weld (VanService swings them)
	for i, x in { -1, 1 } do
		local hinge = cf * CFrame.new(x * 3.55, 5.45, 9.75)
		local door = part(m, i == 1 and "BackDoorL" or "BackDoorR", Vector3.new(3.5, 7.0, 0.2), hinge * CFrame.new(-x * 1.75, 0, 0), paint, SP)
		door:SetAttribute("OwnWeld", true)
		part(m, "DoorWindow", Vector3.new(2.0, 1.2, 0.22), hinge * CFrame.new(-x * 1.75, 2.0, 0), glass, Enum.Material.Glass, { Transparency = 0.45 }):SetAttribute("OwnWeld", true)
		part(m, "DoorHandle", Vector3.new(0.5, 0.12, 0.14), hinge * CFrame.new(-x * 3.0, 0, 0.16), chrome, MT):SetAttribute("OwnWeld", true)
		local w = Instance.new("Weld")
		w.Name = "DoorHinge"
		w.Part0 = chassis
		w.Part1 = door
		w.C0 = chassis.CFrame:ToObjectSpace(hinge)
		w.C1 = door.CFrame:ToObjectSpace(hinge)
		w:SetAttribute("ClosedC0", w.C0)
		w:SetAttribute("Side", x)
		w.Parent = door
	end
	-- the door's glass and handle ride on the door
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") and (d.Name == "DoorWindow" or d.Name == "DoorHandle") then
			local best, bestD = nil, math.huge
			for _, n in { "BackDoorL", "BackDoorR" } do
				local dd = m:FindFirstChild(n) :: BasePart
				local dist = (dd.CFrame.Position - d.CFrame.Position).Magnitude
				if dist < bestD then
					best, bestD = dd, dist
				end
			end
			local w = Instance.new("WeldConstraint")
			w.Part0 = best
			w.Part1 = d
			w.Parent = d
		end
	end
	local seatCol = Color3.fromRGB(40, 40, 46)
	seat(m, "DriverSeat", at(-1.7, 2.25, -6.0), seatCol)
	seat(m, "PassengerSeat", at(1.7, 2.25, -6.0), seatCol)
	local smoke = Instance.new("Smoke")
	smoke.Name = "EngineSmoke"
	smoke.Color = Color3.fromRGB(70, 68, 66)
	smoke.Opacity = 0.3
	smoke.Enabled = false
	smoke.Parent = m:FindFirstChild("Hood")
	local fire = Instance.new("Fire")
	fire.Name = "EngineFire"
	fire.Enabled = false
	fire.Parent = m:FindFirstChild("Hood")
	deflicker(m, chassis)
	setDensity(m, 0.35, 0.5, 0.05)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(3.4, 0.3, 0.05, 1, 1)
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") and (d.Size.X < 0.2 or d.Size.Y < 0.13 or d.Size.Z < 0.13) and d ~= chassis and d.Name ~= "CargoFloor" and not string.match(d.Name, "Step") then
			d.CanCollide = false
		end
	end
	wheelSet(m, chassis, cf, {
		FL = Vector3.new(-3.6, -0.1, -6.6), FR = Vector3.new(3.6, -0.1, -6.6),
		RL = Vector3.new(-3.6, -0.1, 6.4), RR = Vector3.new(3.6, -0.1, 6.4),
	}, 1.3, true)
	weldBody(m, chassis)
	m.PrimaryPart = chassis
	m:SetAttribute("Car", true)
	m:SetAttribute("Van", true)
	m:SetAttribute("CarHP", 480)
	m:SetAttribute("CarMaxHP", 480)
	m:SetAttribute("MaxSpeed", 74)
	return m
end

-- (v2.8) the TANK: tracks, a turret that turns to where the driver looks (VehicleService: "turret"), a cannon (F: a shell,
-- Config.TankReload s). Slow, heavy, very hard to destroy; runs over anything.
-- (v2.8.1) Bigger, and it stands on its tracks (the suspension mounts sit high in the hull: before, the hull floated
-- 1.8 studs over the ground). The hull is tall enough that the driver sits inside it, head and all, under a hatch.
function PropBuilders.tank(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Tank"
	local olive = Color3.fromRGB(78, 88, 62)
	local olive2 = Color3.fromRGB(92, 102, 72)
	local dark = Color3.fromRGB(46, 52, 38)
	local track = Color3.fromRGB(30, 30, 32)
	local MT = Enum.Material.Metal
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	-- (the ground is at y -0.3 here when it stands: mounts at +1.73, wheel centre 0.73 under them, radius 1.3)
	local chassis = part(m, "Chassis", Vector3.new(8.2, 0.8, 16.4), cf * CFrame.new(0, 0.5, 0), dark, MT)
	part(m, "LowerHull", Vector3.new(8.0, 4.0, 17.4), at(0, 2.8, 0), olive, MT)
	part(m, "Glacis", Vector3.new(8.0, 3.2, 2.4), at(0, 2.9, -9.1) * CFrame.Angles(math.rad(28), 0, 0), olive2, MT)
	part(m, "Deck", Vector3.new(11.0, 0.6, 15.6), at(0, 5.1, 0.4), olive, MT)
	part(m, "EngineGrille", Vector3.new(5.6, 0.12, 3.6), at(0, 5.46, 5.6), dark, Enum.Material.DiamondPlate)
	part(m, "RearPlate", Vector3.new(8.0, 3.0, 0.5), at(0, 3.0, 8.85), dark, MT)
	for _, x in { -1, 1 } do
		-- the tracks: the belt down to the ground, road wheels, sprocket and idler, a skirt over them
		part(m, "TrackBelt", Vector3.new(2.0, 3.0, 17.8), at(x * 4.7, 1.2, 0), track, Enum.Material.DiamondPlate, { CanCollide = false })
		part(m, "Skirt", Vector3.new(0.3, 1.7, 15.8), at(x * 5.85, 3.0, 0.2), olive2, MT)
		for i = 0, 5 do
			part(m, "RoadWheel", Vector3.new(0.5, 2.2, 2.2), at(x * 5.55, 0.85, -6.25 + i * 2.5), dark, MT, { Shape = Enum.PartType.Cylinder, CanCollide = false })
			part(m, "Hub", Vector3.new(0.52, 0.8, 0.8), at(x * 5.56, 0.85, -6.25 + i * 2.5), olive2, MT, { Shape = Enum.PartType.Cylinder, CanCollide = false })
		end
		part(m, "Sprocket", Vector3.new(0.6, 2.6, 2.6), at(x * 5.5, 1.5, 8.4), dark, MT, { Shape = Enum.PartType.Cylinder, CanCollide = false })
		part(m, "Idler", Vector3.new(0.6, 2.2, 2.2), at(x * 5.5, 1.4, -8.5), dark, MT, { Shape = Enum.PartType.Cylinder, CanCollide = false })
		part(m, "LampHousing", Vector3.new(0.8, 0.6, 0.6), at(x * 4.4, 5.7, -7.2), dark, MT)
		part(m, "Headlamp", Vector3.new(0.5, 0.4, 0.12), at(x * 4.4, 5.7, -7.52), Color3.fromRGB(255, 240, 200), Enum.Material.Neon)
		part(m, "Exhaust", Vector3.new(0.9, 0.6, 0.6), at(x * 2.2, 3.6, 9.25), track, MT)
		part(m, "Toolbox", Vector3.new(1.0, 0.7, 3.0), at(x * 4.6, 5.75, 4.4), dark, MT)
	end
	-- the driver's hatch (front left on the deck); his seat inside, low in the hull
	part(m, "Hatch", Vector3.new(1.8, 0.25, 1.8), at(-2.2, 5.53, -4.4), dark, MT)
	part(m, "Periscope", Vector3.new(0.9, 0.35, 0.3), at(-2.2, 5.78, -5.4), track, MT)
	local dseat = part(m, "DriverSeat", Vector3.new(1.8, 0.35, 1.7), at(-2.2, 0.95, -4.4), track, Enum.Material.Fabric)
	dseat.CanCollide = false
	local sa = Instance.new("Attachment")
	sa.Name = "SeatAtt"
	sa.CFrame = CFrame.new(0, 1.175, -0.1)
	sa.Parent = dseat
	-- the turret: on its own root, turned by a weld (the server sets it from the driver's aim)
	local troot = part(m, "TurretRoot", Vector3.new(1, 0.4, 1), at(0, 5.4, 0.8), dark, MT, { Transparency = 1, CanCollide = false })
	troot:SetAttribute("OwnWeld", true)
	local tw = Instance.new("Weld")
	tw.Name = "TurretWeld"
	tw.Part0 = chassis
	tw.Part1 = troot
	tw.C0 = chassis.CFrame:ToObjectSpace(troot.CFrame)
	tw:SetAttribute("BaseC0", tw.C0)
	tw.Parent = troot
	local tcf = troot.CFrame
	local turretParts = {
		part(m, "TurretRing", Vector3.new(0.4, 7.4, 7.4), tcf * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.rad(90)), dark, MT, { Shape = Enum.PartType.Cylinder }),
		part(m, "Turret", Vector3.new(6.8, 2.4, 7.6), tcf * CFrame.new(0, 1.5, 0.3), olive, MT),
		part(m, "TurretTop", Vector3.new(6.0, 0.3, 6.6), tcf * CFrame.new(0, 2.85, 0.5), olive2, MT),
		part(m, "TurretCheekL", Vector3.new(1.4, 2.0, 3.4), tcf * CFrame.new(-3.5, 1.4, -2.0) * CFrame.Angles(0, math.rad(-20), 0), olive, MT),
		part(m, "TurretCheekR", Vector3.new(1.4, 2.0, 3.4), tcf * CFrame.new(3.5, 1.4, -2.0) * CFrame.Angles(0, math.rad(20), 0), olive, MT),
		part(m, "Bustle", Vector3.new(6.0, 1.9, 2.8), tcf * CFrame.new(0, 1.45, 5.3), dark, MT),
		part(m, "StowageL", Vector3.new(0.7, 1.0, 3.0), tcf * CFrame.new(-3.75, 1.3, 2.6), dark, MT),
		part(m, "StowageR", Vector3.new(0.7, 1.0, 3.0), tcf * CFrame.new(3.75, 1.3, 2.6), dark, MT),
		part(m, "CupolaHatch", Vector3.new(0.4, 1.7, 1.7), tcf * CFrame.new(1.7, 3.15, 1.4) * CFrame.Angles(0, 0, math.rad(90)), dark, MT, { Shape = Enum.PartType.Cylinder }),
		part(m, "Antenna", Vector3.new(0.08, 5, 0.08), tcf * CFrame.new(-2.6, 5.2, 5.4), Color3.fromRGB(30, 30, 30), MT, { CanCollide = false }),
		part(m, "Mantlet", Vector3.new(2.8, 1.8, 1.0), tcf * CFrame.new(0, 1.45, -3.9), dark, MT),
	}
	for _, tp in turretParts do
		tp:SetAttribute("OwnWeld", true)
		local w = Instance.new("WeldConstraint")
		w.Part0 = troot
		w.Part1 = tp
		w.Parent = tp
	end
	-- the gun: its own weld on the turret (pitch)
	local groot = part(m, "GunRoot", Vector3.new(0.6, 0.6, 0.6), tcf * CFrame.new(0, 1.45, -4.2), dark, MT, { Transparency = 1, CanCollide = false })
	groot:SetAttribute("OwnWeld", true)
	local gw = Instance.new("Weld")
	gw.Name = "GunWeld"
	gw.Part0 = troot
	gw.Part1 = groot
	gw.C0 = troot.CFrame:ToObjectSpace(groot.CFrame)
	gw:SetAttribute("BaseC0", gw.C0)
	gw.Parent = groot
	local gcf = groot.CFrame
	local gunParts = {
		part(m, "Barrel", Vector3.new(10.0, 0.65, 0.65), gcf * CFrame.new(0, 0, -5.0) * CYL_Z, dark, MT, { Shape = Enum.PartType.Cylinder }),
		part(m, "Evacuator", Vector3.new(1.5, 0.9, 0.9), gcf * CFrame.new(0, 0, -5.5) * CYL_Z, olive, MT, { Shape = Enum.PartType.Cylinder }),
		part(m, "MuzzleBrake", Vector3.new(1.0, 0.9, 0.9), gcf * CFrame.new(0, 0, -9.9), dark, MT),
	}
	for _, gp in gunParts do
		gp:SetAttribute("OwnWeld", true)
		gp.CanCollide = false
		local w = Instance.new("WeldConstraint")
		w.Part0 = groot
		w.Part1 = gp
		w.Parent = gp
	end
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "TankMuzzle"
	muzzle.Position = Vector3.new(0, 0, -10.5)
	muzzle.Parent = groot
	local smoke = Instance.new("Smoke")
	smoke.Name = "EngineSmoke"
	smoke.Enabled = false
	smoke.Parent = m:FindFirstChild("Deck")
	local fire = Instance.new("Fire")
	fire.Name = "EngineFire"
	fire.Enabled = false
	fire.Parent = m:FindFirstChild("Deck")
	deflicker(m, chassis)
	setDensity(m, 1.2, 0.6, 0.02)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(6, 0.4, 0.02, 1, 1)
	wheelSet(m, chassis, cf, {
		FL = Vector3.new(-4.6, 1.73, -6.2), FR = Vector3.new(4.6, 1.73, -6.2),
		RL = Vector3.new(-4.6, 1.73, 6.2), RR = Vector3.new(4.6, 1.73, 6.2),
	}, 1.3, false)
	weldBody(m, chassis)
	m.PrimaryPart = chassis
	m:SetAttribute("Car", true)
	m:SetAttribute("Tank", true)
	m:SetAttribute("CarHP", 2400)
	m:SetAttribute("CarMaxHP", 2400)
	m:SetAttribute("MaxSpeed", 42)
	return m
end

------------------------------------------------------------------------
-- v1.8 weapons
------------------------------------------------------------------------

-- Knife: quick stabs; aim (G) and let go to throw it - it flies point first and sticks.
function PropBuilders.knife(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Knife"
	local handle = part(m, "Handle", Vector3.new(0.16, 0.2, 0.55), cf, Color3.fromRGB(28, 26, 24), Enum.Material.Fabric)
	part(m, "Guard", Vector3.new(0.36, 0.13, 0.06), cf * CFrame.new(0, 0, -0.3), Color3.fromRGB(80, 80, 86), Enum.Material.Metal)
	part(m, "Pommel", Vector3.new(0.18, 0.22, 0.06), cf * CFrame.new(0, 0, 0.3), Color3.fromRGB(80, 80, 86), Enum.Material.Metal)
	local blade = part(m, "Blade", Vector3.new(0.22, 0.035, 0.9), cf * CFrame.new(0, 0, -0.78), Color3.fromRGB(176, 180, 188), Enum.Material.Metal, { Reflectance = 0.35 })
	part(m, "BladeTip", Vector3.new(0.14, 0.036, 0.16), cf * CFrame.new(0.03, 0, -1.26) * CFrame.Angles(0, math.rad(28), 0), Color3.fromRGB(176, 180, 188), Enum.Material.Metal, { Reflectance = 0.35 })
	blade:SetAttribute("Sharpness", 0.95)
	gripAttachment(handle, cf)
	setDensity(m, 1.3, 0.5, 0.05)
	m.PrimaryPart = handle
	weldAll(m, handle)
	m:SetAttribute("Item", "knife")
	return m
end

-- Machete: a long, heavy cutting blade (takes limbs off like the blade, hits a bit harder).
function PropBuilders.machete(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Machete"
	local handle = part(m, "Handle", Vector3.new(0.2, 0.26, 0.8), cf, Color3.fromRGB(58, 40, 26), Enum.Material.Wood)
	part(m, "Bolster", Vector3.new(0.26, 0.3, 0.08), cf * CFrame.new(0, 0, -0.44), Color3.fromRGB(90, 90, 96), Enum.Material.Metal)
	local blade = part(m, "Blade", Vector3.new(0.5, 0.05, 2.3), cf * CFrame.new(0.04, 0, -1.63), Color3.fromRGB(150, 154, 160), Enum.Material.Metal, { Reflectance = 0.2 })
	part(m, "Edge", Vector3.new(0.07, 0.055, 2.2), cf * CFrame.new(0.27, 0, -1.65), Color3.fromRGB(210, 214, 220), Enum.Material.Metal, { Reflectance = 0.4 })
	part(m, "BladeTip", Vector3.new(0.42, 0.05, 0.3), cf * CFrame.new(0.1, 0, -2.86) * CFrame.Angles(0, math.rad(-22), 0), Color3.fromRGB(150, 154, 160), Enum.Material.Metal, { Reflectance = 0.2 })
	blade:SetAttribute("Sharpness", 0.85)
	gripAttachment(handle, cf)
	setDensity(m, 1.5, 0.5, 0.05)
	m.PrimaryPart = handle
	weldAll(m, handle)
	m:SetAttribute("Item", "machete")
	return m
end

-- Crossbow: one bolt, quiet, hits very hard; the bolt stays stuck where it hit. Forward = -Z.
function PropBuilders.crossbow(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Crossbow"
	local wood = Color3.fromRGB(96, 62, 36)
	local steel = Color3.fromRGB(60, 62, 68)
	part(m, "Stock", Vector3.new(0.3, 0.32, 2.5), cf * CFrame.new(0, 0.1, -0.1), wood, Enum.Material.Wood)
	part(m, "Rail", Vector3.new(0.12, 0.06, 1.6), cf * CFrame.new(0, 0.29, -0.65), steel, Enum.Material.Metal)
	local grip = part(m, "Handle", Vector3.new(0.22, 0.7, 0.3), cf * CFrame.new(0, -0.35, 0.35) * CFrame.Angles(math.rad(-12), 0, 0), wood, Enum.Material.Wood)
	for _, sx in { -1, 1 } do
		part(m, "Limb", Vector3.new(1.3, 0.12, 0.16), cf * CFrame.new(sx * 0.68, 0.2, -1.32) * CFrame.Angles(0, sx * math.rad(-14), 0), steel, Enum.Material.Metal)
	end
	part(m, "Riser", Vector3.new(0.4, 0.2, 0.22), cf * CFrame.new(0, 0.2, -1.28), steel, Enum.Material.Metal)
	part(m, "String", Vector3.new(2.3, 0.03, 0.03), cf * CFrame.new(0, 0.3, -0.45), Color3.fromRGB(210, 200, 170), Enum.Material.Fabric, { CanCollide = false })
	local bolt = part(m, "Bolt", Vector3.new(0.05, 0.05, 1.3), cf * CFrame.new(0, 0.35, -1.0), Color3.fromRGB(70, 50, 30), Enum.Material.Wood, { CanCollide = false })
	bolt:SetAttribute("Warhead", true)
	part(m, "BoltTip", Vector3.new(0.08, 0.08, 0.16), cf * CFrame.new(0, 0.35, -1.72), steel, Enum.Material.Metal, { CanCollide = false }):SetAttribute("Warhead", true)
	part(m, "Trigger", Vector3.new(0.04, 0.12, 0.05), cf * CFrame.new(0, -0.08, 0.15), steel, Enum.Material.Metal)
	gripAttachment(grip, cf * CFrame.new(0, -0.3, 0.33))
	muzzleAt(bolt, cf * CFrame.new(0, 0.35, -1.85))
	return finishGun(m, grip, "crossbow", 1, 0.9)
end

-- Minigun: hold F - the barrels spin up, then a storm of bullets. 150 rounds. Forward = -Z.
function PropBuilders.minigun(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Minigun"
	local dark = Color3.fromRGB(34, 35, 38)
	local steel = Color3.fromRGB(86, 88, 94)
	part(m, "Body", Vector3.new(0.7, 0.7, 1.5), cf * CFrame.new(0, 0.1, 0.1), dark, Enum.Material.Metal)
	part(m, "Motor", Vector3.new(0.5, 0.5, 0.5), cf * CFrame.new(0, 0.1, 1.05) * CYL_Z, dark, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	for i = 0, 5 do
		local a = i * math.pi / 3
		part(m, "Barrel", Vector3.new(2.2, 0.1, 0.1), cf * CFrame.new(math.cos(a) * 0.17, 0.1 + math.sin(a) * 0.17, -1.75) * CYL_Z, steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	end
	part(m, "RingFront", Vector3.new(0.1, 0.52, 0.52), cf * CFrame.new(0, 0.1, -2.6) * CYL_Z, dark, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "RingMid", Vector3.new(0.12, 0.52, 0.52), cf * CFrame.new(0, 0.1, -1.4) * CYL_Z, dark, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Spindle", Vector3.new(2.3, 0.08, 0.08), cf * CFrame.new(0, 0.1, -1.7) * CYL_Z, dark, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "CarryHandle", Vector3.new(0.12, 0.12, 0.9), cf * CFrame.new(0, 0.72, 0.05), steel, Enum.Material.Metal)
	part(m, "HandlePost", Vector3.new(0.1, 0.25, 0.1), cf * CFrame.new(0, 0.55, 0.45), steel, Enum.Material.Metal)
	part(m, "HandlePost2", Vector3.new(0.1, 0.25, 0.1), cf * CFrame.new(0, 0.55, -0.35), steel, Enum.Material.Metal)
	local grip = part(m, "Handle", Vector3.new(0.22, 0.7, 0.3), cf * CFrame.new(0, -0.5, 0.45) * CFrame.Angles(math.rad(-10), 0, 0), dark, Enum.Material.Fabric)
	part(m, "AmmoBox", Vector3.new(0.55, 0.6, 0.7), cf * CFrame.new(0.62, -0.05, 0.2), Color3.fromRGB(70, 82, 52), Enum.Material.Metal)
	part(m, "Belt", Vector3.new(0.3, 0.08, 0.5), cf * CFrame.new(0.38, 0.28, 0.05), Color3.fromRGB(190, 150, 60), Enum.Material.Metal)
	local front = part(m, "MuzzleBell", Vector3.new(0.1, 0.3, 0.3), cf * CFrame.new(0, 0.1, -2.84) * CYL_Z, dark, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	gripAttachment(grip, cf * CFrame.new(0, -0.45, 0.43))
	muzzleAt(front, cf * CFrame.new(0, 0.1, -2.92))
	return finishGun(m, grip, "minigun", 150, 1.25)
end

-- Flamethrower: hold F - a stream of fire (20 studs). Fuel comes back when you let go.
function PropBuilders.flamethrower(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Flamethrower"
	local red = Color3.fromRGB(150, 36, 28)
	local steel = Color3.fromRGB(80, 82, 88)
	local grip = part(m, "Handle", Vector3.new(0.22, 0.7, 0.3), cf * CFrame.new(0, -0.35, 0.05) * CFrame.Angles(math.rad(-10), 0, 0), Color3.fromRGB(30, 30, 32), Enum.Material.Fabric)
	part(m, "Body", Vector3.new(0.34, 0.36, 1.5), cf * CFrame.new(0, 0.12, -0.35), steel, Enum.Material.Metal)
	part(m, "Tank", Vector3.new(1.2, 0.55, 0.55), cf * CFrame.new(0, -0.18, 0.75) * CYL_Z, red, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "TankCap", Vector3.new(0.12, 0.3, 0.3), cf * CFrame.new(0, 0.12, 0.75) * CYL_Y, steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Hose", Vector3.new(0.1, 0.1, 0.9), cf * CFrame.new(0.2, -0.05, 0.2) * CFrame.Angles(math.rad(20), 0, 0), Color3.fromRGB(30, 30, 32), Enum.Material.Fabric)
	part(m, "FrontGrip", Vector3.new(0.16, 0.45, 0.18), cf * CFrame.new(0, -0.18, -0.8), Color3.fromRGB(30, 30, 32), Enum.Material.Fabric)
	local nozzle = part(m, "Nozzle", Vector3.new(1.1, 0.16, 0.16), cf * CFrame.new(0, 0.12, -1.6) * CYL_Z, steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "NozzleTip", Vector3.new(0.12, 0.24, 0.24), cf * CFrame.new(0, 0.12, -2.16) * CYL_Z, Color3.fromRGB(40, 40, 44), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Pilot", Vector3.new(0.08, 0.08, 0.08), cf * CFrame.new(0, -0.02, -2.2), Color3.fromRGB(90, 160, 255), Enum.Material.Neon, { CanCollide = false })
	local muzzle = muzzleAt(nozzle, cf * CFrame.new(0, 0.12, -2.25))
	local flame = Instance.new("ParticleEmitter")
	flame.Name = "Flame"
	flame.Enabled = false
	flame.Texture = "rbxasset://textures/particles/fire_main.dds"
	flame.EmissionDirection = Enum.NormalId.Front
	flame.Rate = 190
	flame.Lifetime = NumberRange.new(0.32, 0.5)
	flame.Speed = NumberRange.new(40, 52)
	flame.SpreadAngle = Vector2.new(7, 7)
	flame.Drag = 1.5
	flame.Acceleration = Vector3.new(0, 8, 0)
	flame.LightEmission = 1
	flame.LightInfluence = 0
	flame.Rotation = NumberRange.new(0, 360)
	flame.RotSpeed = NumberRange.new(-180, 180)
	flame.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.4, 1.6), NumberSequenceKeypoint.new(1, 3.2) })
	flame.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.7, 0.45), NumberSequenceKeypoint.new(1, 1) })
	flame.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 170, 255)),
		ColorSequenceKeypoint.new(0.12, Color3.fromRGB(255, 220, 120)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 30)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 40, 30)),
	})
	flame.Parent = muzzle
	local light = Instance.new("PointLight")
	light.Name = "FlameLight"
	light.Enabled = false
	light.Color = Color3.fromRGB(255, 150, 60)
	light.Range = 18
	light.Brightness = 3
	light.Parent = nozzle
	gripAttachment(grip, cf * CFrame.new(0, -0.3, 0.03))
	setDensity(m, 0.9, 0.6, 0.1)
	m.PrimaryPart = grip
	weldAll(m, grip)
	m:SetAttribute("Item", "flamethrower")
	m:SetAttribute("Fuel", 100)
	return m
end

-- Molotov: F throws it; the bottle breaks and the burning fuel sets the ground (and people) on fire.
function PropBuilders.molotov(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Molotov"
	local bottle = part(m, "Bottle", Vector3.new(1.0, 0.6, 0.6), cf * CYL_Y, Color3.fromRGB(110, 70, 30), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.4 })
	part(m, "Fuel", Vector3.new(0.7, 0.5, 0.5), cf * CFrame.new(0, -0.12, 0) * CYL_Y, Color3.fromRGB(230, 150, 40), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder, Transparency = 0.35 })
	part(m, "Neck", Vector3.new(0.4, 0.22, 0.22), cf * CFrame.new(0, 0.68, 0) * CYL_Y, Color3.fromRGB(110, 70, 30), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.4 })
	local rag = part(m, "Rag", Vector3.new(0.22, 0.42, 0.22), cf * CFrame.new(0.02, 1.0, 0) * CFrame.Angles(0, 0, math.rad(12)), Color3.fromRGB(205, 195, 170), Enum.Material.Fabric)
	local fire = Instance.new("ParticleEmitter")
	fire.Name = "RagFire"
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Rate = 22
	fire.Lifetime = NumberRange.new(0.25, 0.45)
	fire.Speed = NumberRange.new(1, 2.5)
	fire.SpreadAngle = Vector2.new(15, 15)
	fire.LightEmission = 1
	fire.LightInfluence = 0
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.05) })
	fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 80, 20))
	fire.Acceleration = Vector3.new(0, 6, 0)
	fire.Parent = rag
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 150, 60)
	glow.Range = 7
	glow.Brightness = 1.4
	glow.Parent = rag
	gripAttachment(bottle, cf * CFrame.new(0, 0.1, 0))
	setDensity(m, 0.8, 0.4, 0.2)
	m.PrimaryPart = bottle
	weldAll(m, bottle)
	m:SetAttribute("Item", "molotov")
	return m
end

------------------------------------------------------------------------
-- v1.8 props
------------------------------------------------------------------------

-- Trampoline: jump on the mat and you fly (the mat is very bouncy).
function PropBuilders.trampoline(cf: CFrame): Model
	local m = Instance.new("Model")
	local frame = Color3.fromRGB(60, 62, 70)
	local base = part(m, "Mat", Vector3.new(6.2, 0.2, 6.2), cf * CFrame.new(0, 0.05, 0), Color3.fromRGB(30, 30, 34), Enum.Material.Fabric)
	for _, sx in { -1, 1 } do
		part(m, "Rail", Vector3.new(0.35, 0.35, 7), cf * CFrame.new(sx * 3.3, 0.05, 0), Color3.fromRGB(40, 110, 200), Enum.Material.SmoothPlastic)
		part(m, "Rail", Vector3.new(6.25, 0.35, 0.35), cf * CFrame.new(0, 0.05, sx * 3.3), Color3.fromRGB(40, 110, 200), Enum.Material.SmoothPlastic)
		for _, sz in { -1, 1 } do
			part(m, "Leg", Vector3.new(0.25, 1.6, 0.25), cf * CFrame.new(sx * 3.2, -0.9, sz * 3.2), frame, Enum.Material.Metal)
		end
	end
	prop("Trampoline", base, m, 0.35)
	base.CustomPhysicalProperties = PhysicalProperties.new(0.35, 0.3, 1, 1, 100)
	base:SetAttribute("Bounce", 1.15)
	return m
end

function PropBuilders.mattress(cf: CFrame): Model
	local m = Instance.new("Model")
	local body = part(m, "Mattress", Vector3.new(4.2, 0.8, 7), cf, Color3.fromRGB(230, 230, 236), Enum.Material.Fabric)
	part(m, "Stripe", Vector3.new(4.25, 0.2, 7.05), cf * CFrame.new(0, 0.1, 0), Color3.fromRGB(120, 150, 200), Enum.Material.Fabric)
	prop("Mattress", body, m, 0.12, 1)
	return m
end

function PropBuilders.bowlingball(cf: CFrame): Model
	local m = Instance.new("Model")
	local ball = part(m, "Ball", Vector3.new(1.5, 1.5, 1.5), cf, Color3.fromRGB(30, 30, 90), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball, Reflectance = 0.25 })
	for i, off in { Vector3.new(-0.18, 0.62, -0.32), Vector3.new(0.18, 0.62, -0.32), Vector3.new(0, 0.66, -0.05) } do
		part(m, "Hole" .. i, Vector3.new(0.18, 0.18, 0.18), cf * CFrame.new(off), Color3.fromRGB(10, 10, 12), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball, CanCollide = false })
	end
	prop("Bowling Ball", ball, m, 3.2, 0.3)
	return m
end

------------------------------------------------------------------------
-- Helicopter: a pilot (B) and three passengers (B next to it while somebody flies it). The
-- pilot's client flies it (VehicleClient): a lift force along the rotor axis and a tilt.
-- Nose gun (F), rocket pods (C). The main rotor chops up whoever walks into it.
-- Forward = -Z. The chassis (floor) sits 2.2 above the ground on its skids.
------------------------------------------------------------------------
function PropBuilders.helicopter(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Helicopter"
	local paint = Color3.fromRGB(58, 76, 56)
	local paintLight = Color3.fromRGB(80, 100, 74)
	local dark = Color3.fromRGB(30, 32, 34)
	local black = Color3.fromRGB(16, 16, 18)
	local steel = Color3.fromRGB(128, 132, 138)
	local glass = Color3.fromRGB(150, 190, 215)
	local seatCol = Color3.fromRGB(46, 40, 34)
	local warn = Color3.fromRGB(232, 188, 38)
	local SP = Enum.Material.SmoothPlastic
	local MT = Enum.Material.Metal
	local NEON = Enum.Material.Neon
	local GL = Enum.Material.Glass
	local CYL = { Shape = Enum.PartType.Cylinder }
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function atr(x: number, y: number, z: number, rx: number, ry: number, rz: number): CFrame
		return cf * CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
	end
	local function v3(x: number, y: number, z: number): Vector3
		return Vector3.new(x, y, z)
	end
	local chassis = part(m, "Chassis", v3(5.4, 0.5, 10), cf, dark, MT)

	-- landing skids with struts, cross tubes, boarding steps
	for _, x in { -2.7, 2.7 } do
		part(m, "Skid", v3(0.4, 0.4, 11), at(x, -2.0, -0.3), dark, MT)
		part(m, "SkidTip", v3(0.38, 0.38, 1.2), at(x, -1.75, -6.2) * CFrame.Angles(math.rad(30), 0, 0), dark, MT)
		part(m, "SkidTail", v3(0.38, 0.38, 0.9), at(x, -1.82, 5.4) * CFrame.Angles(math.rad(-18), 0, 0), dark, MT)
		for _, z in { -3.2, 2.8 } do
			part(m, "Strut", v3(0.3, 1.7, 0.3), at(x * 0.93, -1.0, z), dark, MT)
		end
		part(m, "BoardingStep", v3(0.55, 0.1, 1.5), at(x * 1.08, -1.25, -0.2), steel, MT)
		part(m, "StepBracket", v3(0.1, 0.8, 0.12), at(x * 1.0, -1.6, -0.2) * CFrame.Angles(0, 0, math.rad(x < 0 and 25 or -25)), steel, MT)
	end
	for _, z in { -3.2, 2.8 } do
		part(m, "CrossTube", v3(5.0, 0.28, 0.28), at(0, -1.75, z), dark, MT, CYL)
	end

	-- belly, lower hull with panel lines, chin turret
	part(m, "Belly", v3(4.6, 0.55, 8.6), at(0, -0.5, 0.2), dark, MT)
	part(m, "BellyPlate", v3(3.4, 0.12, 4.4), at(0, -0.8, 1.2), steel, MT)
	for _, z in { -1.2, 0.6, 2.4 } do
		part(m, "PanelLine", v3(4.7, 0.5, 0.06), at(0, -0.5, z), black, SP)
	end
	part(m, "Turret", v3(1.2, 1.2, 1.2), at(0, -0.65, -6.9), dark, MT, { Shape = Enum.PartType.Ball })
	part(m, "TurretLens", v3(0.15, 0.5, 0.5), at(0, -0.75, -7.45) * CYL_Z, Color3.fromRGB(80, 200, 255), NEON, CYL)
	part(m, "SearchLight", v3(0.4, 0.7, 0.7), at(1.4, -0.55, -5.2) * CYL_Z, steel, MT, CYL)
	part(m, "SearchLightLens", v3(0.12, 0.6, 0.6), at(1.4, -0.55, -5.45) * CYL_Z, Color3.fromRGB(255, 244, 210), NEON, CYL)

	-- nose: stepped taper, chin windows, windshield with frame
	part(m, "Nose", v3(5.4, 1.4, 1.6), at(0, 0.95, -5.8), paint, SP)
	part(m, "NoseLow", v3(4.4, 1.1, 1.1), at(0, 0.7, -6.8), paint, SP)
	part(m, "NoseTip", v3(3.0, 0.9, 0.8), at(0, 0.55, -7.5), paint, SP)
	part(m, "NoseCap", v3(2.2, 0.7, 0.3), at(0, 0.5, -8.0), dark, SP)
	part(m, "NoseGlass", v3(4.2, 3.2, 0.12), at(0, 2.85, -5.25) * CFrame.Angles(math.rad(-22), 0, 0), glass, GL, { Transparency = 0.55 })
	for _, sx in { -1, 1 } do
		part(m, "NoseGlassSide", v3(0.9, 3.0, 0.12), at(sx * 2.55, 2.75, -4.95) * CFrame.Angles(math.rad(-22), math.rad(sx * 28), 0), glass, GL, { Transparency = 0.55 })
		part(m, "ChinGlass", v3(1.4, 0.12, 1.5), at(sx * 1.0, 0.45, -5.5) * CFrame.Angles(math.rad(8), 0, 0), glass, GL, { Transparency = 0.5 })
		part(m, "WindshieldPost", v3(0.16, 3.3, 0.16), at(sx * 2.1, 2.85, -5.1) * CFrame.Angles(math.rad(-22), 0, 0), black, SP)
		part(m, "Wiper", v3(1.5, 0.05, 0.05), at(sx * 0.9, 1.75, -5.55) * CFrame.Angles(math.rad(-22), 0, math.rad(sx * 12)), black, SP)
	end
	part(m, "WindshieldTop", v3(4.6, 0.25, 0.4), at(0, 4.35, -4.55), paint, SP)
	part(m, "WindshieldMid", v3(0.14, 3.2, 0.14), at(0, 2.85, -5.22) * CFrame.Angles(math.rad(-22), 0, 0), black, SP)
	part(m, "Panel", v3(4.8, 0.8, 0.7), at(0, 1.55, -4.55), dark, SP)

	-- instrument panel, screens, controls, pedals
	part(m, "PanelHood", v3(4.8, 0.14, 1.2), at(0, 2.02, -4.95), black, SP)
	for i, x in { -1.6, -0.5, 0.6, 1.7 } do
		part(m, "Screen", v3(0.9, 0.55, 0.05), at(x, 1.62, -4.17), i % 2 == 0 and Color3.fromRGB(70, 210, 120) or Color3.fromRGB(80, 170, 255), NEON)
		part(m, "ScreenBezel", v3(1.02, 0.67, 0.04), at(x, 1.62, -4.2), black, SP)
	end
	for _, x in { -1.6, 1.6 } do
		part(m, "Cyclic", v3(0.14, 1.0, 0.14), at(x * 0.75, 0.95, -3.9), black, SP)
		part(m, "CyclicGrip", v3(0.22, 0.3, 0.22), at(x * 0.75, 1.5, -3.9), dark, SP)
		part(m, "Pedal", v3(0.5, 0.1, 0.35), at(x * 0.75 - 0.35, 0.3, -4.0), steel, MT)
		part(m, "Pedal", v3(0.5, 0.1, 0.35), at(x * 0.75 + 0.35, 0.3, -4.0), steel, MT)
	end
	part(m, "Collective", v3(0.1, 0.1, 1.1), at(-2.15, 0.95, -3.0), black, SP)
	part(m, "CenterConsole", v3(0.9, 0.6, 2.0), at(0, 0.75, -2.6), dark, SP)
	part(m, "ConsoleScreen", v3(0.6, 0.04, 0.5), at(0, 1.07, -2.9), Color3.fromRGB(80, 200, 255), NEON)
	part(m, "OverheadPanel", v3(2.6, 0.2, 1.4), at(0, 4.2, -3.2), dark, SP)
	part(m, "DomeLight", v3(0.5, 0.08, 0.5), at(0, 4.07, -3.2), Color3.fromRGB(255, 244, 220), NEON)

	-- cockpit sides: doors with windows, handles, step
	for _, x in { -2.75, 2.75 } do
		part(m, "CockpitSide", v3(0.2, 1.3, 3.4), at(x, 0.9, -3.2), paint, SP)
		part(m, "DoorPanel", v3(0.1, 1.0, 3.0), at(x * 1.0 + (x < 0 and -0.12 or 0.12), 0.95, -3.2), paintLight, SP)
		part(m, "SideGlass", v3(0.12, 2.0, 3.4), at(x, 2.55, -3.2), glass, GL, { Transparency = 0.55 })
		part(m, "DoorHandle", v3(0.12, 0.12, 0.45), at(x * 1.0 + (x < 0 and -0.2 or 0.2), 1.25, -2.2), steel, MT)
		part(m, "Pillar", v3(0.3, 4.2, 0.3), at(x, 2.35, -1.35), paint, SP)
		part(m, "Pillar", v3(0.3, 4.2, 0.3), at(x, 2.35, 4.6), paint, SP)
		-- the rear cabin is open: a sill, a grab handle and a sliding door pushed back
		part(m, "RearSill", v3(0.2, 0.8, 5.0), at(x, 0.65, 1.9), paint, SP)
		part(m, "GrabHandle", v3(0.12, 0.12, 1.6), at(x * 0.98, 3.0, 1.2), steel, MT)
		part(m, "SlidingDoor", v3(0.14, 2.7, 2.4), at(x * 1.04, 2.2, 0.2), paint, SP)
		part(m, "SlidingWindow", v3(0.16, 1.2, 1.6), at(x * 1.04 + (x < 0 and -0.01 or 0.01), 2.7, 0.2), glass, GL, { Transparency = 0.5 })
		part(m, "DoorRail", v3(0.14, 0.14, 5.2), at(x * 1.04, 3.7, 1.4), steel, MT)
		part(m, "Roundel", v3(0.06, 0.8, 0.8), at(x * 1.0 + (x < 0 and -0.14 or 0.14), 0.95, -3.2), Color3.fromRGB(235, 235, 230), SP, CYL)
	end
	part(m, "BackWall", v3(5.4, 4.2, 0.25), at(0, 2.35, 4.9), paint, SP)
	part(m, "BackWindow", v3(2.6, 1.1, 0.12), at(0, 3.0, 5.04), glass, GL, { Transparency = 0.5 })
	part(m, "Roof", v3(5.7, 0.4, 10.6), at(0, 4.65, -0.2), paint, SP)
	part(m, "RoofPanel", v3(4.2, 0.1, 5.4), at(0, 4.9, -1.6), paintLight, SP)
	part(m, "FloorMat", v3(4.6, 0.06, 7.0), at(0, 0.28, 0.4), black, Enum.Material.Fabric)

	-- engine cowling, intakes, exhausts, mast with swashplate
	local hood = part(m, "Hood", v3(3.2, 1.6, 4.6), at(0, 5.65, 1.4), paint, SP)
	part(m, "HoodRound", v3(4.6, 2.5, 2.5), at(0, 5.95, 1.4) * CYL_Z, paintLight, SP, CYL)
	for i = 0, 3 do
		part(m, "IntakeFin", v3(1.9, 0.07, 0.07), at(0, 5.55 + i * 0.22, -1.02), black, SP)
	end
	part(m, "IntakeGrille", v3(2.0, 0.9, 0.1), at(0, 5.85, -0.93), dark, SP)
	for _, x in { -1.3, 1.3 } do
		part(m, "Exhaust", v3(0.9, 0.55, 0.55), at(x, 5.9, 3.9) * CYL_Z, dark, MT, CYL)
		part(m, "ExhaustTip", v3(0.2, 0.42, 0.42), at(x, 5.9, 4.4) * CYL_Z, Color3.fromRGB(120, 60, 30), MT, CYL)
	end
	part(m, "Mast", v3(1.5, 0.55, 0.55), at(0, 7.0, 0) * CYL_Y, dark, MT, CYL)
	part(m, "SwashPlate", v3(0.14, 1.7, 1.7), at(0, 6.7, 0) * CYL_Y, steel, MT, CYL)
	for _, a in { 0, 120, 240 } do
		local r = math.rad(a)
		part(m, "ControlRod", v3(0.1, 0.8, 0.1), at(math.cos(r) * 0.7, 6.3, math.sin(r) * 0.7), steel, MT)
	end
	part(m, "RoofAntenna", v3(0.06, 1.2, 0.06), at(1.0, 5.4, -2.4), black, SP)
	part(m, "RoofAntennaBlade", v3(0.05, 0.6, 0.35), at(-1.0, 5.2, 0.2), black, SP)
	part(m, "BeaconBase", v3(0.2, 0.5, 0.5), at(0, 6.6, 3.4) * CYL_Y, black, SP, CYL)
	part(m, "Beacon", v3(0.3, 0.3, 0.3), at(0, 6.8, 3.4), Color3.fromRGB(255, 50, 40), NEON, { Shape = Enum.PartType.Ball, CanCollide = false })

	-- tail: tapered boom, stripes, fin, stabilizers, lights
	part(m, "TailBoom", v3(1.0, 1.0, 11), at(0, 3.6, 10.35), paint, SP)
	part(m, "TailBoomLow", v3(0.7, 0.7, 4.0), at(0, 3.6, 14.8), paint, SP)
	part(m, "TailStripe", v3(1.04, 1.04, 0.5), at(0, 3.6, 8.2), warn, SP)
	part(m, "TailStripe", v3(1.04, 1.04, 0.5), at(0, 3.6, 12.2), warn, SP)
	part(m, "TailFin", v3(0.25, 3.2, 2.2), at(0, 5.0, 15.55), paint, SP)
	part(m, "TailFinTip", v3(0.28, 0.5, 2.0), at(0, 6.55, 15.55), warn, SP)
	part(m, "TailFinLow", v3(0.22, 1.6, 1.3), at(0, 2.5, 15.2), paint, SP)
	part(m, "TailSkid", v3(0.15, 0.15, 1.5), at(0, 1.8, 15.2) * CFrame.Angles(math.rad(-25), 0, 0), dark, MT)
	part(m, "Stabilizer", v3(3.6, 0.2, 1.2), at(0, 3.6, 14.3), paint, SP)
	for _, sx in { -1, 1 } do
		part(m, "StabilizerEnd", v3(0.2, 0.9, 1.0), at(sx * 1.85, 3.6, 14.3), warn, SP)
	end
	part(m, "TailLight", v3(0.3, 0.3, 0.3), at(0, 6.7, 16.1), Color3.fromRGB(255, 40, 30), NEON, { CanCollide = false })
	part(m, "TailAntenna", v3(0.05, 1.4, 0.05), at(0, 4.4, 9.0), black, SP)
	part(m, "TailGuard", v3(0.1, 2.2, 0.5), at(0.2, 4.2, 16.4), dark, MT)

	-- stub wings with hardpoints, nav lights, the nose gun
	for _, sx in { -1, 1 } do
		part(m, "Wing", v3(2.4, 0.2, 1.6), at(sx * 3.9, 0.95, -1.0), paint, SP)
		part(m, "WingTip", v3(0.3, 0.26, 1.7), at(sx * 5.2, 0.95, -1.0), paintLight, SP)
		part(m, "NavLight", v3(0.3, 0.3, 0.3), at(sx * 5.3, 1.1, -1.0), sx < 0 and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(60, 255, 90), NEON, { Shape = Enum.PartType.Ball, CanCollide = false })
		part(m, "Pylon", v3(0.3, 0.6, 1.4), at(sx * 4.1, 0.5, -1.0), dark, MT)
		part(m, sx < 0 and "RocketPodL" or "RocketPodR", v3(0.7, 0.2, 3.4), at(sx * 4.1, 0.1, -1.0), dark, MT)
		part(m, "WingStrut", v3(0.14, 0.14, 0.9), at(sx * 3.1, 0.55, -1.0) * CFrame.Angles(0, 0, math.rad(sx * 35)), steel, MT)
	end
	part(m, "GunMount", v3(0.6, 0.5, 0.8), at(0, -0.15, -6.3), dark, MT)
	part(m, "GunHousing", v3(0.8, 0.6, 1.2), at(0, -0.3, -6.9), black, MT)
	local gun = part(m, "NoseGun", v3(1.6, 0.25, 0.25), at(0, -0.3, -7.6) * CYL_Z, dark, MT, CYL)
	part(m, "GunShroud", v3(0.5, 0.4, 0.4), at(0, -0.3, -7.0) * CYL_Z, steel, MT, CYL)
	part(m, "AmmoFeed", v3(0.12, 0.12, 1.4), at(0.45, 0.1, -5.9), steel, MT)
	muzzleAt(gun, at(0, -0.3, -8.45))

	-- three missiles (the server hides the next one when it fires)
	local function missile(idx: number, x: number, y: number, z: number)
		local function mp(name: string, size: Vector3, cfl: CFrame, color: Color3, mat: Enum.Material, props: { [string]: any }?): Part
			local p = part(m, name, size, cfl, color, mat, props)
			p:SetAttribute("MissileIdx", idx)
			p.CanCollide = false
			return p
		end
		mp("MissileBody", v3(3.0, 0.44, 0.44), at(x, y, z) * CYL_Z, Color3.fromRGB(196, 198, 192), MT, CYL)
		mp("MissileBand", v3(0.2, 0.47, 0.47), at(x, y, z - 0.6) * CYL_Z, warn, SP, CYL)
		mp("MissileWarhead", v3(0.55, 0.36, 0.36), at(x, y, z - 1.7) * CYL_Z, Color3.fromRGB(150, 50, 40), MT, CYL)
		local tip = mp("MissileTip", v3(0.4, 0.2, 0.2), at(x, y, z - 2.1) * CYL_Z, black, MT, CYL)
		tip:SetAttribute("MissileTip", true)
		mp("MissileNozzle", v3(0.3, 0.36, 0.36), at(x, y, z + 1.6) * CYL_Z, dark, MT, CYL)
		mp("MissileFinV", v3(0.05, 0.9, 0.55), at(x, y, z + 1.2), steel, MT)
		mp("MissileFinH", v3(0.9, 0.05, 0.55), at(x, y, z + 1.2), steel, MT)
	end
	missile(1, -4.1, -0.3, -1.0)
	missile(2, 4.1, -0.3, -1.0)
	missile(3, 0, -1.15, 0.6)
	part(m, "BellyRack", v3(0.3, 0.5, 2.6), at(0, -0.85, 0.6), dark, MT)

	-- seats: pilot front left, co-pilot front right, two in the back facing out of the open sides
	local seat = part(m, "DriverSeat", v3(1.6, 0.35, 1.6), at(-1.2, 0.45, -3.0), seatCol, Enum.Material.Fabric)
	part(m, "DriverBack", v3(1.6, 1.8, 0.3), at(-1.2, 1.45, -2.1), seatCol, Enum.Material.Fabric)
	part(m, "DriverHeadrest", v3(0.7, 0.5, 0.25), at(-1.2, 2.55, -2.05), seatCol, Enum.Material.Fabric)
	local co = part(m, "PassengerSeat", v3(1.6, 0.35, 1.6), at(1.2, 0.45, -3.0), seatCol, Enum.Material.Fabric)
	part(m, "PassengerBack", v3(1.6, 1.8, 0.3), at(1.2, 1.45, -2.1), seatCol, Enum.Material.Fabric)
	part(m, "PassengerHeadrest", v3(0.7, 0.5, 0.25), at(1.2, 2.55, -2.05), seatCol, Enum.Material.Fabric)
	local rearL = part(m, "PassengerSeat2", v3(1.6, 0.35, 1.6), at(-1.3, 0.45, 1.8), seatCol, Enum.Material.Fabric)
	local rearR = part(m, "PassengerSeat3", v3(1.6, 0.35, 1.6), at(1.3, 0.45, 1.8), seatCol, Enum.Material.Fabric)
	part(m, "RearBench", v3(0.4, 1.8, 3.4), at(0, 1.4, 1.8), seatCol, Enum.Material.Fabric)
	for _, sx in { -1, 1 } do
		-- seat belts
		part(m, "SeatBelt", v3(0.12, 1.2, 0.04), at(sx * 1.2 - 0.3, 1.5, -2.22) * CFrame.Angles(0, 0, math.rad(sx * 28)), Color3.fromRGB(190, 120, 30), Enum.Material.Fabric)
		part(m, "SeatBelt", v3(0.12, 1.0, 0.04), at(sx * 1.2 + 0.25, 1.5, -2.22) * CFrame.Angles(0, 0, math.rad(-sx * 28)), Color3.fromRGB(190, 120, 30), Enum.Material.Fabric)
		part(m, "RearHeadrest", v3(0.25, 0.5, 0.7), at(sx * 0.0, 2.45, 1.8 + sx * 0.9), seatCol, Enum.Material.Fabric)
	end
	local function seatAtt(s: BasePart, yaw: number, exitSide: number)
		local a = Instance.new("Attachment")
		a.Name = "SeatAtt"
		a.CFrame = CFrame.new(0, 1.175, 0) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0, -0.1)
		a.Parent = s
		s:SetAttribute("ExitSide", exitSide)
	end
	seatAtt(seat, 0, -1)
	seatAtt(co, 0, 1)
	seatAtt(rearL, math.rad(90), -1)
	seatAtt(rearR, math.rad(-90), 1)
	-- engine smoke / fire (hidden HP)
	local smoke = Instance.new("Smoke")
	smoke.Name = "EngineSmoke"
	smoke.Color = Color3.fromRGB(60, 58, 56)
	smoke.Opacity = 0.3
	smoke.RiseVelocity = 6
	smoke.Size = 5
	smoke.Enabled = false
	smoke.Parent = hood
	local fire = Instance.new("Fire")
	fire.Name = "EngineFire"
	fire.Size = 8
	fire.Heat = 14
	fire.Enabled = false
	fire.Parent = hood

	deflicker(m, chassis)
	setDensity(m, 0.3, 0.5, 0.05)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(4, 0.4, 0.05, 1, 1)
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") and d ~= chassis then
			-- thin or small details (handles, screens, antennas, lights, missiles) never collide
			local s = d.Size
			if s.X < 0.2 or s.Y < 0.13 or s.Z < 0.13 or (math.max(s.X, s.Y, s.Z) < 0.9 and d.Name ~= "Strut") then
				d.CanCollide = false
			end
		end
	end
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") and d ~= chassis then
			local w = Instance.new("WeldConstraint")
			w.Part0 = chassis
			w.Part1 = d
			w.Parent = d
		end
	end

	-- the main rotor and the tail rotor: hubs on Welds (every client turns them while it flies)
	local function rotor(name: string, offset: CFrame, blades: number, length: number, width: number, axis: string)
		local hubSize = axis == "Y" and v3(0.6, 1.5, 1.5) or v3(0.5, 1.0, 1.0)
		local hub = part(m, name, hubSize, cf * offset * (axis == "Y" and CYL_Y or CFrame.identity), dark, MT, { Shape = Enum.PartType.Cylinder, CanCollide = false, Massless = true })
		local weld = Instance.new("Weld")
		weld.Name = "RotorWeld"
		weld.Part0 = chassis
		weld.Part1 = hub
		weld.C0 = offset * (axis == "Y" and CYL_Y or CFrame.identity)
		weld.C1 = CFrame.identity
		weld.Parent = hub
		-- (clients spin it: C0 = RotorBase * turn about the axis * (Y: CYL_Y))
		hub:SetAttribute("RotorBase", offset)
		hub:SetAttribute("RotorAxis", axis)
		for i = 0, blades - 1 do
			local a = i * 2 * math.pi / blades
			local bcf
			local tcf
			if axis == "Y" then
				bcf = cf * offset * CFrame.Angles(0, a, 0) * CFrame.new(length / 2 + 0.4, 0.05, 0)
				tcf = cf * offset * CFrame.Angles(0, a, 0) * CFrame.new(length + 0.1, 0.05, 0)
			else
				bcf = cf * offset * CFrame.Angles(a, 0, 0) * CFrame.new(0.1, length / 2 + 0.3, 0)
				tcf = cf * offset * CFrame.Angles(a, 0, 0) * CFrame.new(0.1, length + 0.3, 0)
			end
			local size = axis == "Y" and v3(length, 0.12, width) or v3(0.12, length, width)
			local blade = part(m, name .. "Blade", size, bcf, Color3.fromRGB(24, 24, 26), MT, { CanCollide = false, Massless = true })
			if axis == "Y" then
				blade:SetAttribute("MainBlade", true)
			end
			local bw = Instance.new("WeldConstraint")
			bw.Part0 = hub
			bw.Part1 = blade
			bw.Parent = blade
			-- coloured tip (stays on its blade when the blade breaks off)
			local tsize = axis == "Y" and v3(0.7, 0.16, width + 0.06) or v3(0.16, 0.5, width + 0.06)
			local tip = part(m, name .. "BladeTip", tsize, tcf, warn, SP, { CanCollide = false, Massless = true })
			local tw = Instance.new("WeldConstraint")
			tw.Part0 = blade
			tw.Part1 = tip
			tw.Parent = tip
			if axis == "Y" then
				-- blade root grip on the hub
				local grip = part(m, "RotorGrip", v3(1.1, 0.3, 0.55), cf * offset * CFrame.Angles(0, a, 0) * CFrame.new(1.0, 0.05, 0), black, MT, { CanCollide = false, Massless = true })
				local gw = Instance.new("WeldConstraint")
				gw.Part0 = hub
				gw.Part1 = grip
				gw.Parent = grip
			end
		end
		return hub
	end
	rotor("RotorHub", CFrame.new(0, 7.85, 0), 3, 12, 1.0, "Y")
	rotor("TailRotorHub", CFrame.new(0.55, 5.1, 15.75), 2, 3.4, 0.45, "X")

	-- flight: lift along the rotor axis + a tilt (the pilot's client drives both)
	local flyAtt = Instance.new("Attachment")
	flyAtt.Name = "FlyAtt"
	flyAtt.Parent = chassis
	local lift = Instance.new("VectorForce")
	lift.Name = "HeliLift"
	lift.Attachment0 = flyAtt
	lift.RelativeTo = Enum.ActuatorRelativeTo.World
	lift.ApplyAtCenterOfMass = true
	lift.Force = Vector3.zero
	lift.Visible = false
	lift.Parent = chassis
	local align = Instance.new("AlignOrientation")
	align.Name = "HeliAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = flyAtt
	align.Enabled = false
	align.MaxTorque = 1e8
	align.Responsiveness = 7
	align.Parent = chassis

	m.PrimaryPart = chassis
	m:SetAttribute("Car", true)
	m:SetAttribute("Heli", true)
	m:SetAttribute("CarHP", 300) -- (VehicleService.Register sets Config.HeliHP)
	m:SetAttribute("CarMaxHP", 300)
	return m
end

------------------------------------------------------------------------
-- v1.9: better props (these definitions replace the older ones above), new furniture, balloon, bottle
------------------------------------------------------------------------

local function dropFolder(): Instance
	return workspace:FindFirstChild("SpawnedProps") or workspace
end

-- a glass bottle (the vending machine hands them out; a thrown bottle is just a heavy-ish loose prop)
function PropBuilders.bottle(cf: CFrame): Model
	local m = Instance.new("Model")
	local colors = { Color3.fromRGB(196, 60, 52), Color3.fromRGB(60, 150, 200), Color3.fromRGB(80, 170, 90), Color3.fromRGB(235, 170, 50), Color3.fromRGB(150, 90, 190) }
	local c = colors[math.random(#colors)]
	local body = part(m, "Bottle", Vector3.new(1.5, 0.52, 0.52), cf * CFrame.Angles(0, 0, math.rad(90)), c, Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.25 })
	part(m, "Neck", Vector3.new(0.6, 0.26, 0.26), cf * CFrame.new(0, 0.95, 0) * CFrame.Angles(0, 0, math.rad(90)), c, Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.25 })
	part(m, "Cap", Vector3.new(0.12, 0.3, 0.3), cf * CFrame.new(0, 1.28, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 200, 205), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Label", Vector3.new(0.5, 0.54, 0.54), cf * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(240, 240, 235), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	local pm = prop("Bottle", body, m, 0.5, 0.5)
	body.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	return pm
end

-- vending machine: lit display with bottles, keypad, a red button (press it: a bottle drops out), flap
function PropBuilders.vending(cf: CFrame): Model
	local m = Instance.new("Model")
	local shell = Color3.fromRGB(176, 40, 38)
	local dark = Color3.fromRGB(24, 24, 28)
	local body = part(m, "Body", Vector3.new(4.2, 7, 3), cf, shell, Enum.Material.SmoothPlastic)
	part(m, "Header", Vector3.new(4.3, 0.9, 3.1), cf * CFrame.new(0, 3.4, 0), Color3.fromRGB(240, 236, 226), Enum.Material.SmoothPlastic)
	part(m, "HeaderGlow", Vector3.new(3.6, 0.5, 0.06), cf * CFrame.new(0, 3.4, -1.58), Color3.fromRGB(255, 230, 150), Enum.Material.Neon)
	part(m, "Window", Vector3.new(2.6, 4.3, 0.1), cf * CFrame.new(-0.55, 0.6, -1.52), Color3.fromRGB(190, 215, 230), Enum.Material.Glass, { Transparency = 0.5 })
	part(m, "WindowFrame", Vector3.new(2.8, 4.5, 0.12), cf * CFrame.new(-0.55, 0.6, -1.5), dark, Enum.Material.SmoothPlastic)
	local cols = { Color3.fromRGB(196, 60, 52), Color3.fromRGB(60, 150, 200), Color3.fromRGB(80, 170, 90), Color3.fromRGB(235, 170, 50) }
	for row = 0, 3 do
		part(m, "Shelf", Vector3.new(2.5, 0.08, 0.9), cf * CFrame.new(-0.55, 2.2 - row * 1.0, -1.1), Color3.fromRGB(150, 152, 158), Enum.Material.Metal)
		for i = 0, 4 do
			part(m, "ShownBottle", Vector3.new(0.45, 0.8, 0.45), cf * CFrame.new(-1.5 + i * 0.5, 2.62 - row * 1.0, -1.15), cols[(row + i) % 4 + 1], Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.2 })
		end
	end
	-- right column: coin slot, keypad, the red button, bill slot
	part(m, "Panel", Vector3.new(1.0, 4.3, 0.12), cf * CFrame.new(1.45, 0.6, -1.52), dark, Enum.Material.SmoothPlastic)
	part(m, "CoinSlot", Vector3.new(0.5, 0.1, 0.06), cf * CFrame.new(1.45, 2.4, -1.6), Color3.fromRGB(230, 200, 90), Enum.Material.Metal)
	part(m, "Display", Vector3.new(0.7, 0.35, 0.05), cf * CFrame.new(1.45, 1.8, -1.6), Color3.fromRGB(70, 255, 120), Enum.Material.Neon)
	for r = 0, 2 do
		for c = 0, 1 do
			part(m, "Key", Vector3.new(0.28, 0.28, 0.08), cf * CFrame.new(1.27 + c * 0.36, 1.2 - r * 0.38, -1.58), Color3.fromRGB(190, 190, 195), Enum.Material.SmoothPlastic)
		end
	end
	local btn = part(m, "RedButton", Vector3.new(0.7, 0.7, 0.2), cf * CFrame.new(1.45, -0.55, -1.6) * CFrame.Angles(math.rad(90), 0, 0), Color3.fromRGB(235, 30, 30), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder })
	part(m, "ButtonRing", Vector3.new(0.12, 0.9, 0.9), cf * CFrame.new(1.45, -0.55, -1.56) * CFrame.Angles(math.rad(90), 0, 0), dark, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Flap", Vector3.new(3.0, 1.0, 0.14), cf * CFrame.new(0, -2.5, -1.55), dark, Enum.Material.SmoothPlastic)
	part(m, "FlapSlot", Vector3.new(2.6, 0.6, 0.06), cf * CFrame.new(0, -2.5, -1.64), Color3.fromRGB(10, 10, 12), Enum.Material.SmoothPlastic)
	part(m, "Foot", Vector3.new(3.8, 0.3, 2.7), cf * CFrame.new(0, -3.4, 0), dark, Enum.Material.SmoothPlastic)
	part(m, "SideStripe", Vector3.new(0.06, 6.4, 1.2), cf * CFrame.new(2.13, 0, 0), Color3.fromRGB(240, 236, 226), Enum.Material.SmoothPlastic)
	part(m, "SideStripe", Vector3.new(0.06, 6.4, 1.2), cf * CFrame.new(-2.13, 0, 0), Color3.fromRGB(240, 236, 226), Enum.Material.SmoothPlastic)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 236, 190)
	glow.Range = 14
	glow.Brightness = 0.8
	glow.Parent = body
	prop("Vending machine", body, m, 0.6)
	-- press the red button: a bottle drops out of the flap
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "VendingPrompt"
	prompt.ActionText = "Press the red button"
	prompt.ObjectText = "Vending machine"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = btn
	local last = 0
	local function onTrigger()
		if os.clock() - last < 1.2 or not body.Parent then
			return
		end
		last = os.clock()
		btn.Color = Color3.fromRGB(120, 10, 10)
		task.delay(0.25, function()
			btn.Color = Color3.fromRGB(235, 30, 30)
		end)
		local pos = body.CFrame * CFrame.new(0, -2.5, -2.1)
		local b = PropBuilders.bottle(CFrame.new(pos.Position + Vector3.new(0, 0.4, 0)))
		b.Parent = dropFolder()
		if b.PrimaryPart then
			b.PrimaryPart.AssemblyLinearVelocity = body.CFrame.LookVector * 7 + Vector3.new(0, 4, 0)
		end
		game:GetService("Debris"):AddItem(b, 180)
	end
	-- (pcall: the offline tests run this builder without a real engine)
	pcall(function()
		prompt.Triggered:Connect(onTrigger)
	end)
	return m
end

-- dumpster: hollow box with a real hinged lid (push it open, throw things in, close it)
function PropBuilders.dumpster(cf: CFrame): Model
	local m = Instance.new("Model")
	local green = Color3.fromRGB(46, 92, 62)
	local dark = Color3.fromRGB(28, 56, 38)
	local floor = part(m, "Floor", Vector3.new(6, 0.3, 3.4), cf * CFrame.new(0, -1.6, 0), dark, Enum.Material.Metal)
	part(m, "WallFront", Vector3.new(6, 3.2, 0.25), cf * CFrame.new(0, 0, -1.6), green, Enum.Material.Metal)
	part(m, "WallBack", Vector3.new(6, 3.6, 0.25), cf * CFrame.new(0, 0.2, 1.6), green, Enum.Material.Metal)
	for _, sx in { -1, 1 } do
		part(m, "WallSide", Vector3.new(0.25, 3.2, 3.4), cf * CFrame.new(sx * 2.9, 0, 0), green, Enum.Material.Metal)
		part(m, "Rib", Vector3.new(0.12, 3.0, 0.3), cf * CFrame.new(sx * 3.05, 0, 0), dark, Enum.Material.Metal)
	end
	for _, x in { -2, 0, 2 } do
		part(m, "RibFront", Vector3.new(0.3, 3.0, 0.1), cf * CFrame.new(x, 0, -1.78), dark, Enum.Material.Metal)
	end
	part(m, "RimFront", Vector3.new(6.2, 0.2, 0.4), cf * CFrame.new(0, 1.65, -1.6), dark, Enum.Material.Metal)
	for _, sx in { -2.4, 2.4 } do
		part(m, "Wheel", Vector3.new(0.4, 0.9, 0.9), cf * CFrame.new(sx, -1.9, 1.5), Color3.fromRGB(20, 20, 22), Enum.Material.Rubber, { Shape = Enum.PartType.Cylinder })
	end
	part(m, "Stripe", Vector3.new(4, 0.5, 0.05), cf * CFrame.new(0, 0.3, -1.76), Color3.fromRGB(235, 235, 230), Enum.Material.SmoothPlastic)
	-- trash in it
	for i = 1, 5 do
		part(m, "Trash", Vector3.new(0.9, 0.6, 0.8), cf * CFrame.new(-2 + i * 0.8, -1.2, (i % 2 == 0) and 0.4 or -0.4) * CFrame.Angles(0, i, 0), Color3.fromRGB(70 + i * 20, 70, 60), Enum.Material.Fabric, { CanCollide = false })
	end
	prop("Dumpster", floor, m, 0.2, 0.6)
	-- the lid: its own part on a hinge at the back top edge (it is not welded to the rest)
	local lid = part(m, "Lid", Vector3.new(6.2, 0.2, 3.7), cf * CFrame.new(0, 1.85, -0.05), dark, Enum.Material.Metal)
	part(m, "LidHandle", Vector3.new(2.4, 0.2, 0.2), cf * CFrame.new(0, 2.0, -1.86), Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
	for _, w in m:GetDescendants() do
		if w:IsA("WeldConstraint") and (w.Part0 == lid or w.Part1 == lid) then
			w:Destroy()
		end
	end
	local handle = m:FindFirstChild("LidHandle")
	if handle then
		local hw = Instance.new("WeldConstraint")
		hw.Part0 = lid
		hw.Part1 = handle
		hw.Parent = handle
	end
	lid.Massless = false
	setDensity(m, 0.2, 0.6, 0.1)
	local a0 = Instance.new("Attachment")
	a0.Name = "HingeBody"
	a0.CFrame = floor.CFrame:ToObjectSpace(cf * CFrame.new(0, 1.85, 1.75))
	a0.Parent = floor
	local a1 = Instance.new("Attachment")
	a1.Name = "HingeLid"
	a1.CFrame = lid.CFrame:ToObjectSpace(cf * CFrame.new(0, 1.85, 1.75))
	a1.Parent = lid
	local hinge = Instance.new("HingeConstraint")
	hinge.Name = "LidHinge"
	hinge.Attachment0 = a0
	hinge.Attachment1 = a1
	hinge.LimitsEnabled = true
	hinge.LowerAngle = -115 -- (the box itself stops it from swinging down)
	hinge.UpperAngle = 115
	hinge.Restitution = 0.15
	hinge.Parent = lid
	m:SetAttribute("Container", true)
	return m
end

-- piano: playable (the prompt opens the keyboard; see PianoClient), with stool and pedals
local function basePiano(cf: CFrame): Model
	local m = Instance.new("Model")
	local black = Color3.fromRGB(18, 18, 20)
	local body = part(m, "Body", Vector3.new(6, 4, 2.2), cf * CFrame.new(0, 0.5, 0.4), black, Enum.Material.SmoothPlastic, { Reflectance = 0.15 })
	part(m, "KeyBed", Vector3.new(5.6, 0.5, 1.2), cf * CFrame.new(0, -0.35, -1.15), black, Enum.Material.SmoothPlastic, { Reflectance = 0.15 })
	part(m, "Keys", Vector3.new(5.2, 0.12, 0.8), cf * CFrame.new(0, -0.04, -1.3), Color3.fromRGB(240, 238, 230), Enum.Material.SmoothPlastic)
	for i = 0, 17 do
		part(m, "BlackKey", Vector3.new(0.12, 0.1, 0.45), cf * CFrame.new(-2.4 + i * 0.285, 0.05, -1.12), black, Enum.Material.SmoothPlastic)
	end
	for _, sx in { -2.6, 2.6 } do
		part(m, "Leg", Vector3.new(0.35, 1.6, 0.35), cf * CFrame.new(sx, -1.45, -1.3), black, Enum.Material.SmoothPlastic)
	end
	part(m, "Lid", Vector3.new(6.1, 0.15, 2.3), cf * CFrame.new(0, 2.57, 0.4), black, Enum.Material.SmoothPlastic, { Reflectance = 0.15 })
	part(m, "Pedals", Vector3.new(1, 0.1, 0.4), cf * CFrame.new(0, -1.95, -0.7), Color3.fromRGB(190, 160, 70), Enum.Material.Metal)
	-- (v2.0) the case goes down to the floor: it used to hang on the two front legs (and the stool) with all its
	-- weight behind them, so it always tipped over backwards
	part(m, "Plinth", Vector3.new(6, 0.75, 2.4), cf * CFrame.new(0, -1.875, 0.5), black, Enum.Material.SmoothPlastic, { Reflectance = 0.15 })
	return prop("Piano", body, m, 1.4)
end
local oldPiano = basePiano
function PropBuilders.piano(cf: CFrame): Model
	local m = oldPiano(cf)
	local root = m.PrimaryPart
	local function add(name: string, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material)
		local p = part(m, name, size, cf * off, color, mat)
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = p
		return p
	end
	for _, x in { -0.5, 0, 0.5 } do
		add("Pedal", Vector3.new(0.35, 0.1, 0.7), CFrame.new(x, -2.0, -1.2), Color3.fromRGB(190, 160, 70), Enum.Material.Metal)
	end
	add("MusicStand", Vector3.new(3.2, 1.3, 0.1), CFrame.new(0, 2.9, -0.5) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(20, 20, 22), Enum.Material.SmoothPlastic)
	add("Sheet", Vector3.new(2.6, 0.9, 0.04), CFrame.new(0, 2.95, -0.56) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(240, 238, 225), Enum.Material.SmoothPlastic)
	add("StoolSeat", Vector3.new(2.2, 0.3, 1.2), CFrame.new(0, -0.9, -3.0), Color3.fromRGB(60, 36, 28), Enum.Material.Wood)
	for _, sx in { -0.8, 0.8 } do
		add("StoolLeg", Vector3.new(0.2, 1.35, 0.2), CFrame.new(sx, -1.575, -3.0), Color3.fromRGB(60, 36, 28), Enum.Material.Wood)
	end
	local keys = m:FindFirstChild("Keys")
	if keys then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PianoPrompt"
		prompt.ActionText = "Play the piano"
		prompt.ObjectText = "Piano"
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = keys
	end
	m:SetAttribute("Piano", true)
	return m
end

-- bench: slats, cast-iron ends, the back leans AWAY from the person who sits (v1.9: it used to lean the wrong way)
function PropBuilders.bench(cf: CFrame): Model
	local m = Instance.new("Model")
	local wood = Color3.fromRGB(152, 102, 60)
	local iron = Color3.fromRGB(36, 38, 42)
	local seat = part(m, "SeatSlat", Vector3.new(6, 0.18, 0.34), cf * CFrame.new(0, 0, -0.55), wood, Enum.Material.WoodPlanks)
	for i = 1, 3 do
		part(m, "SeatSlat", Vector3.new(6, 0.18, 0.34), cf * CFrame.new(0, 0, -0.55 + i * 0.4), wood, Enum.Material.WoodPlanks)
	end
	for i = 0, 2 do
		part(m, "BackSlat", Vector3.new(6, 0.32, 0.14), cf * CFrame.new(0, 0.45 + i * 0.38, 0.78 + i * 0.07) * CFrame.Angles(math.rad(10), 0, 0), wood, Enum.Material.WoodPlanks)
	end
	for _, sx in { -2.7, 2.7 } do
		part(m, "Leg", Vector3.new(0.2, 1.6, 0.2), cf * CFrame.new(sx, -0.8, -0.6), iron, Enum.Material.Metal)
		part(m, "Leg", Vector3.new(0.2, 1.6, 0.2), cf * CFrame.new(sx, -0.8, 0.7), iron, Enum.Material.Metal)
		part(m, "BackPost", Vector3.new(0.2, 2.0, 0.2), cf * CFrame.new(sx, 0.3, 0.85) * CFrame.Angles(math.rad(10), 0, 0), iron, Enum.Material.Metal)
		part(m, "Arm", Vector3.new(0.22, 0.2, 1.7), cf * CFrame.new(sx, 0.62, 0.1), iron, Enum.Material.Metal)
		part(m, "ArmScroll", Vector3.new(0.22, 0.45, 0.2), cf * CFrame.new(sx, 0.4, -0.7), iron, Enum.Material.Metal)
		part(m, "Foot", Vector3.new(0.3, 0.12, 1.6), cf * CFrame.new(sx, -1.6, 0.05), iron, Enum.Material.Metal)
	end
	part(m, "Rail", Vector3.new(5.4, 0.12, 0.12), cf * CFrame.new(0, -0.3, 0.1), iron, Enum.Material.Metal)
	return prop("Bench", seat, m, 0.55)
end

-- a cluster of helium balloons: it floats up (a tether or a heavy thing holds it down)
-- (v2.0 fix) oval balloons (a sphere mesh on the block), each with its little knot; the shine is a flat spot on the
-- skin (the white cubes stuck out); the lift pulls at the balloons, not the knot under them, and keeps the bunch
-- upright (pulled from below it turned upside down)
function PropBuilders.balloon(cf: CFrame): Model
	local m = Instance.new("Model")
	local colors = { Color3.fromRGB(220, 50, 50), Color3.fromRGB(60, 130, 220), Color3.fromRGB(240, 200, 50), Color3.fromRGB(90, 190, 100) }
	local root = part(m, "Knot", Vector3.new(0.4, 0.4, 0.4), cf * CFrame.new(0, -4.2, 0), Color3.fromRGB(40, 40, 40), Enum.Material.SmoothPlastic)
	for i = 1, 3 do
		local a = i * 2.1
		local c = cf * CFrame.new(math.cos(a) * 0.95, 0.4 + (i % 2) * 0.55, math.sin(a) * 0.95) * CFrame.Angles(math.sin(a) * 0.12, 0, -math.cos(a) * 0.12)
		local col = colors[(i % 4) + 1]
		local b = part(m, "Balloon", Vector3.new(2.5, 3.0, 2.5), c, col, Enum.Material.SmoothPlastic, { Reflectance = 0.2, CanCollide = false })
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = b
		part(m, "BalloonKnot", Vector3.new(0.3, 0.3, 0.3), c * CFrame.new(0, -1.55, 0), col:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball, CanCollide = false })
		-- the shine: a thin disc lying on the skin, up and to the front-left
		local dir = Vector3.new(-0.42, 0.5, -0.76).Unit
		local onSkin = Vector3.new(dir.X * 1.25, dir.Y * 1.5, dir.Z * 1.25) * 0.97
		part(m, "Shine", Vector3.new(0.05, 0.55, 0.55), c * CFrame.lookAt(onSkin, onSkin + dir) * CFrame.Angles(0, math.rad(90), 0), Color3.new(1, 1, 1), Enum.Material.Neon,
			{ Shape = Enum.PartType.Cylinder, Transparency = 0.45, CanCollide = false })
		local knotPos = (c * CFrame.new(0, -1.7, 0)).Position
		local tie = root.CFrame.Position + Vector3.new(0, 0.2, 0)
		local along = (knotPos - tie).Unit
		local side = along:Cross(Vector3.zAxis)
		side = side.Magnitude > 0.05 and side.Unit or Vector3.xAxis
		part(m, "String", Vector3.new(0.04, (knotPos - tie).Magnitude, 0.04), CFrame.fromMatrix((knotPos + tie) / 2, side, along), Color3.fromRGB(230, 230, 230), Enum.Material.SmoothPlastic, { CanCollide = false })
	end
	prop("Balloons", root, m, 0.02, 0.4)
	-- the lift: at the middle of the balloons, so the knot hangs below it
	local att = Instance.new("Attachment")
	att.Name = "LiftAt"
	att.CFrame = CFrame.new(0, 4.8, 0) * CFrame.Angles(0, 0, math.rad(90)) -- (its primary axis points up: Upright)
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Name = "Float"
	lv.Attachment0 = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	lv.LineDirection = Vector3.yAxis
	lv.LineVelocity = 7
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = 4000
	lv.Parent = root
	local up = Instance.new("AlignOrientation")
	up.Name = "Upright"
	up.Mode = Enum.OrientationAlignmentMode.OneAttachment
	up.AlignType = Enum.AlignType.PrimaryAxisParallel
	up.Attachment0 = att
	up.PrimaryAxis = Vector3.yAxis
	up.MaxTorque = 600
	up.Responsiveness = 8
	up.Parent = root
	return m
end

-- ---- furniture (the houses were nearly empty) ----

function PropBuilders.coffeetable(cf: CFrame): Model
	local m = Instance.new("Model")
	local wood = Color3.fromRGB(110, 72, 44)
	local top = part(m, "Top", Vector3.new(3.6, 0.2, 2), cf * CFrame.new(0, 0.2, 0), wood, Enum.Material.WoodPlanks)
	part(m, "Glass", Vector3.new(3.0, 0.06, 1.4), cf * CFrame.new(0, 0.33, 0), Color3.fromRGB(190, 215, 225), Enum.Material.Glass, { Transparency = 0.5 })
	part(m, "Shelf", Vector3.new(3.2, 0.12, 1.6), cf * CFrame.new(0, -0.5, 0), wood, Enum.Material.Wood)
	for _, x in { -1.6, 1.6 } do
		for _, z in { -0.8, 0.8 } do
			part(m, "Leg", Vector3.new(0.2, 1.2, 0.2), cf * CFrame.new(x, -0.4, z), wood, Enum.Material.Wood)
		end
	end
	part(m, "Book", Vector3.new(0.9, 0.12, 0.65), cf * CFrame.new(-0.7, -0.38, 0.1) * CFrame.Angles(0, 0.3, 0), Color3.fromRGB(70, 90, 140), Enum.Material.SmoothPlastic)
	part(m, "Mug", Vector3.new(0.3, 0.4, 0.4), cf * CFrame.new(0.9, 0.52, 0.1), Color3.fromRGB(235, 235, 230), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	return prop("Coffee table", top, m, 0.45)
end

function PropBuilders.armchair(cf: CFrame): Model
	local m = Instance.new("Model")
	local fabric = Color3.fromRGB(122, 68, 54)
	local wood = Color3.fromRGB(70, 46, 30)
	local seat = part(m, "Seat", Vector3.new(2.6, 0.7, 2.4), cf * CFrame.new(0, -0.2, 0), fabric, Enum.Material.Fabric)
	part(m, "Cushion", Vector3.new(2.2, 0.4, 2.0), cf * CFrame.new(0, 0.3, 0.1), Color3.fromRGB(140, 80, 62), Enum.Material.Fabric)
	part(m, "Back", Vector3.new(2.6, 2.2, 0.7), cf * CFrame.new(0, 0.8, 1.0) * CFrame.Angles(math.rad(8), 0, 0), fabric, Enum.Material.Fabric)
	for _, sx in { -1.3, 1.3 } do
		part(m, "Arm", Vector3.new(0.5, 1.2, 2.4), cf * CFrame.new(sx, 0.2, 0), fabric, Enum.Material.Fabric)
		part(m, "Leg", Vector3.new(0.25, 0.6, 0.25), cf * CFrame.new(sx * 0.9, -0.8, -1.0), wood, Enum.Material.Wood)
		part(m, "Leg", Vector3.new(0.25, 0.6, 0.25), cf * CFrame.new(sx * 0.9, -0.8, 1.0), wood, Enum.Material.Wood)
	end
	return prop("Armchair", seat, m, 0.4)
end

function PropBuilders.wardrobe(cf: CFrame): Model
	local m = Instance.new("Model")
	local wood = Color3.fromRGB(128, 88, 56)
	local dark = Color3.fromRGB(96, 64, 40)
	local body = part(m, "Body", Vector3.new(4, 6.2, 1.8), cf, wood, Enum.Material.Wood)
	part(m, "Crown", Vector3.new(4.3, 0.35, 2.0), cf * CFrame.new(0, 3.2, 0), dark, Enum.Material.Wood)
	part(m, "Base", Vector3.new(4.2, 0.4, 1.9), cf * CFrame.new(0, -3.1, 0), dark, Enum.Material.Wood)
	for _, x in { -1, 1 } do
		part(m, "Door", Vector3.new(1.85, 5.5, 0.1), cf * CFrame.new(x * 0.97, 0, -0.93), dark, Enum.Material.WoodPlanks)
		part(m, "Panel", Vector3.new(1.35, 4.8, 0.05), cf * CFrame.new(x * 0.97, 0, -1.0), wood, Enum.Material.WoodPlanks)
		part(m, "Handle", Vector3.new(0.12, 0.7, 0.12), cf * CFrame.new(x * 0.2, 0, -1.05), Color3.fromRGB(210, 190, 90), Enum.Material.Metal)
	end
	return prop("Wardrobe", body, m, 0.35)
end

function PropBuilders.nightstand(cf: CFrame): Model
	local m = Instance.new("Model")
	local wood = Color3.fromRGB(140, 96, 60)
	local body = part(m, "Body", Vector3.new(1.8, 1.7, 1.6), cf, wood, Enum.Material.Wood)
	part(m, "Top", Vector3.new(2.0, 0.15, 1.8), cf * CFrame.new(0, 0.9, 0), Color3.fromRGB(110, 74, 46), Enum.Material.WoodPlanks)
	part(m, "Drawer", Vector3.new(1.5, 0.6, 0.08), cf * CFrame.new(0, 0.3, -0.83), Color3.fromRGB(110, 74, 46), Enum.Material.Wood)
	part(m, "Knob", Vector3.new(0.18, 0.18, 0.12), cf * CFrame.new(0, 0.3, -0.92), Color3.fromRGB(210, 190, 90), Enum.Material.Metal, { Shape = Enum.PartType.Ball })
	part(m, "LampBase", Vector3.new(0.5, 0.2, 0.5), cf * CFrame.new(0.4, 1.1, 0), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
	local shade = part(m, "LampShade", Vector3.new(0.9, 0.8, 0.9), cf * CFrame.new(0.4, 1.6, 0), Color3.fromRGB(255, 232, 180), Enum.Material.Neon, { Transparency = 0.2, Shape = Enum.PartType.Cylinder })
	shade.CFrame = shade.CFrame * CFrame.Angles(0, 0, math.rad(90))
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(255, 214, 150)
	l.Range = 14
	l.Brightness = 0.7
	l.Parent = shade
	return prop("Nightstand", body, m, 0.4)
end

function PropBuilders.desk(cf: CFrame): Model
	local m = Instance.new("Model")
	local wood = Color3.fromRGB(116, 80, 50)
	local top = part(m, "Top", Vector3.new(4.6, 0.25, 2.2), cf * CFrame.new(0, 0.5, 0), wood, Enum.Material.WoodPlanks)
	part(m, "DrawerBox", Vector3.new(1.4, 1.4, 2.0), cf * CFrame.new(1.5, -0.35, 0), Color3.fromRGB(96, 64, 40), Enum.Material.Wood)
	part(m, "DrawerFront", Vector3.new(1.2, 0.5, 0.06), cf * CFrame.new(1.5, -0.1, -1.03), wood, Enum.Material.Wood)
	part(m, "DrawerFront", Vector3.new(1.2, 0.5, 0.06), cf * CFrame.new(1.5, -0.7, -1.03), wood, Enum.Material.Wood)
	part(m, "Leg", Vector3.new(0.25, 1.5, 2.0), cf * CFrame.new(-2.2, -0.35, 0), wood, Enum.Material.Wood)
	part(m, "Monitor", Vector3.new(1.6, 1.0, 0.1), cf * CFrame.new(-0.6, 1.3, 0.5), Color3.fromRGB(20, 20, 24), Enum.Material.SmoothPlastic)
	part(m, "Screen", Vector3.new(1.4, 0.82, 0.04), cf * CFrame.new(-0.6, 1.3, 0.44), Color3.fromRGB(70, 150, 220), Enum.Material.Neon)
	part(m, "MonitorStand", Vector3.new(0.3, 0.4, 0.3), cf * CFrame.new(-0.6, 0.85, 0.5), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
	part(m, "Keyboard", Vector3.new(1.3, 0.08, 0.45), cf * CFrame.new(-0.6, 0.68, -0.4), Color3.fromRGB(210, 210, 212), Enum.Material.SmoothPlastic)
	return prop("Desk", top, m, 0.4)
end

function PropBuilders.stove(cf: CFrame): Model
	local m = Instance.new("Model")
	local steel = Color3.fromRGB(190, 192, 196)
	local body = part(m, "Body", Vector3.new(3, 3.2, 2.4), cf, steel, Enum.Material.Metal)
	part(m, "Hob", Vector3.new(3.04, 0.12, 2.44), cf * CFrame.new(0, 1.66, 0), Color3.fromRGB(26, 26, 30), Enum.Material.SmoothPlastic)
	for _, x in { -0.7, 0.7 } do
		for _, z in { -0.5, 0.5 } do
			part(m, "Burner", Vector3.new(0.06, 0.8, 0.8), cf * CFrame.new(x, 1.74, z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 70, 74), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
		end
	end
	part(m, "OvenDoor", Vector3.new(2.5, 1.7, 0.1), cf * CFrame.new(0, -0.2, -1.22), Color3.fromRGB(40, 40, 44), Enum.Material.Glass, { Transparency = 0.35 })
	part(m, "OvenHandle", Vector3.new(2.2, 0.12, 0.14), cf * CFrame.new(0, 0.8, -1.35), steel, Enum.Material.Metal)
	for i = 0, 3 do
		part(m, "Knob", Vector3.new(0.12, 0.3, 0.3), cf * CFrame.new(-1.0 + i * 0.66, 1.2, -1.24) * CFrame.Angles(math.rad(90), 0, 0), Color3.fromRGB(30, 30, 34), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	end
	return prop("Stove", body, m, 0.5)
end

function PropBuilders.sinkunit(cf: CFrame): Model
	local m = Instance.new("Model")
	local cab = Color3.fromRGB(230, 226, 214)
	local body = part(m, "Cabinet", Vector3.new(4.4, 3.0, 2.2), cf, cab, Enum.Material.SmoothPlastic)
	part(m, "Top", Vector3.new(4.6, 0.2, 2.4), cf * CFrame.new(0, 1.6, 0), Color3.fromRGB(80, 76, 72), Enum.Material.Granite)
	part(m, "Basin", Vector3.new(1.8, 0.1, 1.2), cf * CFrame.new(-0.7, 1.72, 0), Color3.fromRGB(190, 195, 200), Enum.Material.Metal)
	part(m, "Tap", Vector3.new(0.18, 0.7, 0.18), cf * CFrame.new(-0.7, 2.05, 0.7), Color3.fromRGB(210, 212, 216), Enum.Material.Metal)
	part(m, "TapSpout", Vector3.new(0.18, 0.18, 0.6), cf * CFrame.new(-0.7, 2.35, 0.45), Color3.fromRGB(210, 212, 216), Enum.Material.Metal)
	for _, x in { -1.1, 1.1 } do
		part(m, "Door", Vector3.new(2.0, 2.4, 0.08), cf * CFrame.new(x, -0.05, -1.14), Color3.fromRGB(214, 210, 198), Enum.Material.SmoothPlastic)
		part(m, "Handle", Vector3.new(0.1, 0.5, 0.1), cf * CFrame.new(x * 0.4, 0.6, -1.22), Color3.fromRGB(150, 150, 154), Enum.Material.Metal)
	end
	return prop("Sink unit", body, m, 0.45)
end

function PropBuilders.rug(cf: CFrame): Model
	local m = Instance.new("Model")
	local base = part(m, "Rug", Vector3.new(7, 0.1, 5), cf, Color3.fromRGB(140, 60, 50), Enum.Material.Fabric, { CanCollide = false })
	part(m, "Border", Vector3.new(6.4, 0.12, 4.4), cf * CFrame.new(0, 0.01, 0), Color3.fromRGB(226, 210, 170), Enum.Material.Fabric, { CanCollide = false })
	part(m, "Inner", Vector3.new(5.6, 0.14, 3.6), cf * CFrame.new(0, 0.02, 0), Color3.fromRGB(110, 50, 44), Enum.Material.Fabric, { CanCollide = false })
	part(m, "Medallion", Vector3.new(0.16, 2.2, 2.2), cf * CFrame.new(0, 0.04, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(210, 170, 90), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	return prop("Rug", base, m, 0.1, 1)
end

function PropBuilders.plant(cf: CFrame): Model
	local m = Instance.new("Model")
	local pot = part(m, "Pot", Vector3.new(1.8, 1.8, 1.8), cf * CFrame.new(0, -1.1, 0), Color3.fromRGB(176, 96, 64), Enum.Material.Slate, { Shape = Enum.PartType.Cylinder })
	pot.CFrame = pot.CFrame * CFrame.Angles(0, 0, math.rad(90))
	part(m, "Soil", Vector3.new(0.1, 1.6, 1.6), cf * CFrame.new(0, -0.18, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(60, 40, 28), Enum.Material.Ground, { Shape = Enum.PartType.Cylinder })
	local leaf = Color3.fromRGB(54, 130, 64)
	for i = 0, 6 do
		local a = i * 0.9
		part(m, "Leaf", Vector3.new(0.12, 2.2, 0.7), cf * CFrame.new(math.cos(a) * 0.5, 0.9, math.sin(a) * 0.5) * CFrame.Angles(math.rad(math.cos(a) * 28), a, math.rad(math.sin(a) * 28)), leaf, Enum.Material.Grass, { CanCollide = false })
	end
	return prop("Plant", pot, m, 0.3)
end

function PropBuilders.dresser(cf: CFrame): Model
	local m = Instance.new("Model")
	local wood = Color3.fromRGB(134, 92, 58)
	local body = part(m, "Body", Vector3.new(4.2, 2.8, 1.8), cf, wood, Enum.Material.Wood)
	part(m, "Top", Vector3.new(4.4, 0.18, 2.0), cf * CFrame.new(0, 1.5, 0), Color3.fromRGB(104, 70, 44), Enum.Material.WoodPlanks)
	for r = 0, 2 do
		part(m, "Drawer", Vector3.new(3.8, 0.7, 0.08), cf * CFrame.new(0, 0.85 - r * 0.85, -0.93), Color3.fromRGB(108, 74, 46), Enum.Material.WoodPlanks)
		part(m, "Knob", Vector3.new(0.5, 0.12, 0.12), cf * CFrame.new(0, 0.85 - r * 0.85, -1.02), Color3.fromRGB(210, 190, 90), Enum.Material.Metal)
	end
	return prop("Dresser", body, m, 0.4)
end

------------------------------------------------------------------------
-- v2.0 weapons and gear
------------------------------------------------------------------------

-- USP: a polymer pistol with a long suppressor (quiet, a little stronger than the pistol). Forward = -Z.
function PropBuilders.usp(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "USP"
	local poly = Color3.fromRGB(36, 37, 40)
	local slideCol = Color3.fromRGB(52, 54, 58)
	local steel = Color3.fromRGB(78, 80, 86)
	local slide = part(m, "Slide", Vector3.new(0.22, 0.24, 1.02), cf * CFrame.new(0, 0.12, -0.06), slideCol, Enum.Material.Metal, { Reflectance = 0.05 })
	part(m, "Serrations", Vector3.new(0.225, 0.15, 0.2), cf * CFrame.new(0, 0.13, 0.33), Color3.fromRGB(30, 30, 33), Enum.Material.DiamondPlate)
	part(m, "Frame", Vector3.new(0.2, 0.14, 0.9), cf * CFrame.new(0, -0.07, -0.14), poly, Enum.Material.SmoothPlastic)
	part(m, "Rail", Vector3.new(0.16, 0.05, 0.32), cf * CFrame.new(0, -0.165, -0.4), poly, Enum.Material.SmoothPlastic)
	part(m, "Barrel", Vector3.new(0.1, 0.13, 0.13), cf * CFrame.new(0, 0.13, -0.6) * CYL_Z, steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	local can = part(m, "Suppressor", Vector3.new(1.05, 0.21, 0.21), cf * CFrame.new(0, 0.13, -1.17) * CYL_Z, Color3.fromRGB(24, 24, 26), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	for _, z in { -0.78, -1.56 } do
		part(m, "SuppressorRing", Vector3.new(0.06, 0.225, 0.225), cf * CFrame.new(0, 0.13, z) * CYL_Z, steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	end
	part(m, "FrontSight", Vector3.new(0.04, 0.05, 0.06), cf * CFrame.new(0, 0.265, -0.5), poly, Enum.Material.Metal)
	part(m, "RearSight", Vector3.new(0.15, 0.05, 0.05), cf * CFrame.new(0, 0.265, 0.38), poly, Enum.Material.Metal)
	local grip = part(m, "Handle", Vector3.new(0.21, 0.62, 0.33), cf * CFrame.new(0, -0.39, 0.2) * CFrame.Angles(math.rad(-15), 0, 0), poly, Enum.Material.Fabric)
	part(m, "MagBase", Vector3.new(0.22, 0.05, 0.33), cf * CFrame.new(0, -0.7, 0.29) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(20, 20, 22), Enum.Material.Metal)
	part(m, "GuardBottom", Vector3.new(0.06, 0.04, 0.34), cf * CFrame.new(0, -0.27, -0.15), poly, Enum.Material.SmoothPlastic)
	part(m, "GuardFront", Vector3.new(0.06, 0.15, 0.04), cf * CFrame.new(0, -0.2, -0.31), poly, Enum.Material.SmoothPlastic)
	part(m, "Trigger", Vector3.new(0.04, 0.11, 0.04), cf * CFrame.new(0, -0.18, -0.1) * CFrame.Angles(math.rad(12), 0, 0), steel, Enum.Material.Metal)
	part(m, "Hammer", Vector3.new(0.06, 0.08, 0.06), cf * CFrame.new(0, 0.2, 0.48), steel, Enum.Material.Metal)
	gripAttachment(grip, cf * CFrame.new(0, -0.33, 0.17))
	muzzleAt(can, cf * CFrame.new(0, 0.13, -1.72))
	local eject = Instance.new("Attachment")
	eject.Name = "Ejection"
	eject.CFrame = slide.CFrame:ToObjectSpace(cf * CFrame.new(0.12, 0.16, -0.08))
	eject.Parent = slide
	return finishGun(m, grip, "usp", 12, 1.3)
end

-- MP5: compact 9 mm submachine gun, curved magazine, slim handguard, collapsible stock. Forward = -Z.
function PropBuilders.mp5(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "MP5"
	local black = Color3.fromRGB(28, 28, 31)
	local steel = Color3.fromRGB(68, 70, 76)
	local receiver = part(m, "Receiver", Vector3.new(0.24, 0.36, 1.35), cf * CFrame.new(0, 0.12, -0.2), black, Enum.Material.Metal, { Reflectance = 0.04 })
	part(m, "CockingTube", Vector3.new(1.0, 0.12, 0.12), cf * CFrame.new(0, 0.34, -0.75) * CYL_Z, steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "CockingHandle", Vector3.new(0.05, 0.05, 0.16), cf * CFrame.new(-0.1, 0.36, -1.0) * CFrame.Angles(0, math.rad(-35), 0), black, Enum.Material.Metal)
	part(m, "Handguard", Vector3.new(0.3, 0.3, 0.72), cf * CFrame.new(0, 0.08, -1.18), Color3.fromRGB(34, 34, 37), Enum.Material.Fabric)
	local barrel = part(m, "Barrel", Vector3.new(0.4, 0.1, 0.1), cf * CFrame.new(0, 0.14, -1.72) * CYL_Z, steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "FrontSightPost", Vector3.new(0.05, 0.24, 0.05), cf * CFrame.new(0, 0.42, -1.66), black, Enum.Material.Metal)
	part(m, "FrontSightRing", Vector3.new(0.06, 0.2, 0.2), cf * CFrame.new(0, 0.58, -1.66) * CYL_Z, black, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "RearDrum", Vector3.new(0.14, 0.18, 0.18), cf * CFrame.new(0, 0.42, 0.3) * CFrame.Angles(0, 0, math.rad(90)), black, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	-- curved magazine: three tilted pieces
	for i, rec in { { 0.0, -0.34, -0.6, 4 }, { 0.0, -0.66, -0.66, 14 }, { 0.0, -0.96, -0.76, 24 } } do
		part(m, "Mag" .. i, Vector3.new(0.16, 0.34, 0.26), cf * CFrame.new(rec[1], rec[2], rec[3]) * CFrame.Angles(math.rad(rec[4]), 0, 0), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
	end
	local grip = part(m, "Handle", Vector3.new(0.21, 0.6, 0.3), cf * CFrame.new(0, -0.3, 0.32) * CFrame.Angles(math.rad(-16), 0, 0), black, Enum.Material.Fabric)
	part(m, "TriggerGroup", Vector3.new(0.18, 0.12, 0.5), cf * CFrame.new(0, -0.1, 0.12), black, Enum.Material.SmoothPlastic)
	part(m, "Trigger", Vector3.new(0.04, 0.1, 0.04), cf * CFrame.new(0, -0.21, 0.02), steel, Enum.Material.Metal)
	for _, x in { -0.1, 0.1 } do
		part(m, "StockRail", Vector3.new(0.05, 0.05, 1.0), cf * CFrame.new(x, 0.18, 0.95), steel, Enum.Material.Metal)
	end
	part(m, "ButtPlate", Vector3.new(0.28, 0.46, 0.07), cf * CFrame.new(0, 0.1, 1.48), black, Enum.Material.Fabric)
	gripAttachment(grip, cf * CFrame.new(0, -0.28, 0.28))
	muzzleAt(barrel, cf * CFrame.new(0, 0.14, -1.93))
	local eject = Instance.new("Attachment")
	eject.Name = "Ejection"
	eject.CFrame = receiver.CFrame:ToObjectSpace(cf * CFrame.new(0.14, 0.2, -0.45))
	eject.Parent = receiver
	return finishGun(m, grip, "mp5", 30, 1.1)
end

-- M1 Garand: semi-automatic .30-06 battle rifle, walnut stock, 8 rounds in an en-bloc clip that pings out when
-- it is empty. Forward = -Z.
function PropBuilders.garand(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "M1 Garand"
	local walnut = Color3.fromRGB(112, 64, 34)
	local steel = Color3.fromRGB(58, 60, 58)
	local park = Color3.fromRGB(70, 72, 66)
	local receiver = part(m, "Receiver", Vector3.new(0.26, 0.3, 1.2), cf * CFrame.new(0, 0.16, -0.25), park, Enum.Material.Metal)
	part(m, "Clip", Vector3.new(0.18, 0.08, 0.5), cf * CFrame.new(0, 0.33, -0.35), Color3.fromRGB(176, 150, 82), Enum.Material.Metal, { Reflectance = 0.2 })
	part(m, "OpRod", Vector3.new(0.05, 0.07, 1.9), cf * CFrame.new(0.15, 0.17, -1.6), steel, Enum.Material.Metal)
	part(m, "OpRodHandle", Vector3.new(0.12, 0.09, 0.08), cf * CFrame.new(0.21, 0.17, -0.7), steel, Enum.Material.Metal)
	part(m, "Forestock", Vector3.new(0.3, 0.3, 1.5), cf * CFrame.new(0, 0.04, -1.4), walnut, Enum.Material.Wood)
	part(m, "Handguard", Vector3.new(0.24, 0.12, 1.3), cf * CFrame.new(0, 0.27, -1.45), walnut, Enum.Material.Wood)
	local barrel = part(m, "Barrel", Vector3.new(1.3, 0.11, 0.11), cf * CFrame.new(0, 0.18, -2.62) * CYL_Z, steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "GasCylinder", Vector3.new(0.34, 0.15, 0.15), cf * CFrame.new(0, 0.18, -3.08) * CYL_Z, steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "FrontSight", Vector3.new(0.05, 0.16, 0.06), cf * CFrame.new(0, 0.33, -3.12), steel, Enum.Material.Metal)
	part(m, "BayonetLug", Vector3.new(0.06, 0.08, 0.16), cf * CFrame.new(0, 0.05, -3.02), steel, Enum.Material.Metal)
	part(m, "RearSight", Vector3.new(0.18, 0.16, 0.12), cf * CFrame.new(0, 0.37, 0.27), steel, Enum.Material.Metal)
	part(m, "Wrist", Vector3.new(0.24, 0.36, 0.55), cf * CFrame.new(0, -0.06, 0.52) * CFrame.Angles(math.rad(-12), 0, 0), walnut, Enum.Material.Wood)
	local grip = part(m, "Handle", Vector3.new(0.22, 0.46, 0.3), cf * CFrame.new(0, -0.26, 0.42) * CFrame.Angles(math.rad(-20), 0, 0), walnut, Enum.Material.Wood)
	part(m, "Buttstock", Vector3.new(0.27, 0.5, 1.25), cf * CFrame.new(0, -0.14, 1.38) * CFrame.Angles(math.rad(-6), 0, 0), walnut, Enum.Material.Wood)
	part(m, "ButtPlate", Vector3.new(0.28, 0.56, 0.06), cf * CFrame.new(0, -0.21, 2.03) * CFrame.Angles(math.rad(-6), 0, 0), steel, Enum.Material.Metal)
	part(m, "TriggerGuard", Vector3.new(0.06, 0.05, 0.4), cf * CFrame.new(0, -0.17, 0.04), steel, Enum.Material.Metal)
	part(m, "Trigger", Vector3.new(0.04, 0.1, 0.04), cf * CFrame.new(0, -0.1, 0.02), steel, Enum.Material.Metal)
	part(m, "Sling", Vector3.new(0.04, 0.12, 2.6), cf * CFrame.new(0, -0.45, -0.1), Color3.fromRGB(86, 82, 54), Enum.Material.Fabric, { CanCollide = false })
	gripAttachment(grip, cf * CFrame.new(0, -0.24, 0.38))
	muzzleAt(barrel, cf * CFrame.new(0, 0.18, -3.28))
	local eject = Instance.new("Attachment")
	eject.Name = "Ejection"
	eject.CFrame = receiver.CFrame:ToObjectSpace(cf * CFrame.new(0, 0.42, -0.35))
	eject.Parent = receiver
	return finishGun(m, grip, "garand", 8, 0.95)
end

-- Lock-on launcher (Javelin style): a fat tube with the sight unit on its side. Hold G: the seeker finds cars,
-- helicopters and jets; keep one in the box until the lock turns green, then F. Forward = -Z.
function PropBuilders.lockon(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Lock-on Launcher"
	local olive = Color3.fromRGB(78, 88, 58)
	local dark = Color3.fromRGB(32, 34, 30)
	local tube = part(m, "Tube", Vector3.new(4.4, 0.62, 0.62), cf * CFrame.new(0, 0.42, -0.5) * CYL_Z, olive, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "FrontCap", Vector3.new(0.24, 0.72, 0.72), cf * CFrame.new(0, 0.42, -2.62) * CYL_Z, dark, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "RearCap", Vector3.new(0.3, 0.74, 0.74), cf * CFrame.new(0, 0.42, 1.65) * CYL_Z, dark, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	for _, z in { -1.5, 0.5 } do
		part(m, "Band", Vector3.new(0.12, 0.66, 0.66), cf * CFrame.new(0, 0.42, z) * CYL_Z, dark, Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	end
	local seeker = part(m, "Seeker", Vector3.new(0.02, 0.5, 0.5), cf * CFrame.new(0, 0.42, -2.75) * CYL_Z, Color3.fromRGB(40, 70, 90), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Reflectance = 0.4 })
	seeker:SetAttribute("Warhead", true)
	-- the command launch unit: a box with two lenses on the left side of the tube
	part(m, "SightUnit", Vector3.new(0.56, 0.5, 0.8), cf * CFrame.new(-0.62, 0.42, 0.05), dark, Enum.Material.Metal)
	part(m, "SightLens", Vector3.new(0.02, 0.24, 0.24), cf * CFrame.new(-0.62, 0.48, -0.36) * CYL_Z, Color3.fromRGB(150, 40, 40), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Reflectance = 0.4 })
	part(m, "SightLens2", Vector3.new(0.02, 0.14, 0.14), cf * CFrame.new(-0.62, 0.3, -0.36) * CYL_Z, Color3.fromRGB(60, 80, 110), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Reflectance = 0.4 })
	part(m, "Eyepiece", Vector3.new(0.3, 0.2, 0.2), cf * CFrame.new(-0.62, 0.48, 0.6) * CYL_Z, dark, Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	local grip = part(m, "Handle", Vector3.new(0.22, 0.58, 0.3), cf * CFrame.new(0, -0.22, -0.05) * CFrame.Angles(math.rad(-10), 0, 0), dark, Enum.Material.Fabric)
	part(m, "FrontGrip", Vector3.new(0.2, 0.46, 0.24), cf * CFrame.new(0, -0.08, -1.25), dark, Enum.Material.Fabric)
	part(m, "Trigger", Vector3.new(0.05, 0.12, 0.05), cf * CFrame.new(0, 0.04, -0.25), Color3.fromRGB(160, 34, 30), Enum.Material.Metal)
	gripAttachment(grip, cf * CFrame.new(0, -0.2, -0.1))
	muzzleAt(tube, cf * CFrame.new(0, 0.42, -2.9))
	return finishGun(m, grip, "lockon", 1, 0.5)
end

-- Taser: yellow and black, two darts on wires (38 studs): who is hit lies there twitching. Forward = -Z.
function PropBuilders.taser(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Taser"
	local yellow = Color3.fromRGB(236, 196, 34)
	local black = Color3.fromRGB(26, 26, 28)
	local body = part(m, "Body", Vector3.new(0.26, 0.3, 0.9), cf * CFrame.new(0, 0.1, -0.12), yellow, Enum.Material.SmoothPlastic)
	local cart = part(m, "Cartridge", Vector3.new(0.3, 0.34, 0.3), cf * CFrame.new(0, 0.1, -0.72), black, Enum.Material.SmoothPlastic)
	cart:SetAttribute("Warhead", true)
	for _, y in { 0.02, 0.18 } do
		part(m, "Port", Vector3.new(0.12, 0.06, 0.02), cf * CFrame.new(0, y, -0.88), Color3.fromRGB(180, 30, 30), Enum.Material.SmoothPlastic)
	end
	part(m, "Laser", Vector3.new(0.08, 0.08, 0.2), cf * CFrame.new(0, -0.1, -0.5), black, Enum.Material.Metal)
	local grip = part(m, "Handle", Vector3.new(0.22, 0.56, 0.3), cf * CFrame.new(0, -0.3, 0.2) * CFrame.Angles(math.rad(-14), 0, 0), black, Enum.Material.Fabric)
	part(m, "Trigger", Vector3.new(0.05, 0.11, 0.04), cf * CFrame.new(0, -0.14, -0.08), yellow, Enum.Material.SmoothPlastic)
	part(m, "GuardBottom", Vector3.new(0.06, 0.04, 0.3), cf * CFrame.new(0, -0.24, -0.12), black, Enum.Material.SmoothPlastic)
	gripAttachment(grip, cf * CFrame.new(0, -0.28, 0.17))
	muzzleAt(cart, cf * CFrame.new(0, 0.1, -0.92))
	return finishGun(m, grip, "taser", 1, 1.1)
end

-- Harpoon gun: a speargun with a barbed harpoon on a line. The line holds what you hit; hold F to reel it in.
function PropBuilders.harpoon(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Harpoon Gun"
	local blue = Color3.fromRGB(34, 66, 108)
	local steel = Color3.fromRGB(150, 154, 160)
	local barrelPart = part(m, "Barrel", Vector3.new(2.6, 0.24, 0.24), cf * CFrame.new(0, 0.18, -1.0) * CYL_Z, blue, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	local shaft = part(m, "Harpoon", Vector3.new(0.06, 0.06, 3.0), cf * CFrame.new(0, 0.36, -1.35), steel, Enum.Material.Metal, { CanCollide = false, Reflectance = 0.3 })
	shaft:SetAttribute("Warhead", true)
	local barb = part(m, "Barb", Vector3.new(0.16, 0.16, 0.3), cf * CFrame.new(0, 0.36, -2.95), steel, Enum.Material.Metal, { CanCollide = false })
	barb:SetAttribute("Warhead", true)
	for _, x in { -0.09, 0.09 } do
		part(m, "Band", Vector3.new(0.04, 0.04, 0.9), cf * CFrame.new(x, 0.3, -2.0), Color3.fromRGB(30, 30, 30), Enum.Material.Fabric, { CanCollide = false })
	end
	part(m, "Reel", Vector3.new(0.18, 0.5, 0.5), cf * CFrame.new(0.22, -0.1, -0.55), Color3.fromRGB(200, 200, 200), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Line", Vector3.new(0.24, 0.38, 0.38), cf * CFrame.new(0.22, -0.1, -0.55), Color3.fromRGB(230, 190, 40), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	local grip = part(m, "Handle", Vector3.new(0.22, 0.6, 0.3), cf * CFrame.new(0, -0.24, 0.25) * CFrame.Angles(math.rad(-12), 0, 0), Color3.fromRGB(28, 28, 30), Enum.Material.Fabric)
	part(m, "Stock", Vector3.new(0.24, 0.3, 0.6), cf * CFrame.new(0, 0.12, 0.55), blue, Enum.Material.SmoothPlastic)
	part(m, "Trigger", Vector3.new(0.05, 0.1, 0.04), cf * CFrame.new(0, -0.02, 0.0), steel, Enum.Material.Metal)
	gripAttachment(grip, cf * CFrame.new(0, -0.22, 0.22))
	muzzleAt(barrelPart, cf * CFrame.new(0, 0.18, -2.35))
	return finishGun(m, grip, "harpoon", 1, 0.9)
end

-- Flare gun: fat orange barrel, one red flare that lights everything around where it lands (and burns people).
function PropBuilders.flaregun(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Flare Gun"
	local orange = Color3.fromRGB(232, 104, 26)
	local barrel = part(m, "Barrel", Vector3.new(0.9, 0.3, 0.3), cf * CFrame.new(0, 0.14, -0.35) * CYL_Z, orange, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "Bore", Vector3.new(0.02, 0.2, 0.2), cf * CFrame.new(0, 0.14, -0.8) * CYL_Z, Color3.fromRGB(20, 20, 20), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	local flare = part(m, "Flare", Vector3.new(0.02, 0.14, 0.14), cf * CFrame.new(0, 0.14, -0.78) * CYL_Z, Color3.fromRGB(220, 30, 30), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	flare:SetAttribute("Warhead", true)
	part(m, "Breech", Vector3.new(0.26, 0.28, 0.24), cf * CFrame.new(0, 0.12, 0.18), orange, Enum.Material.SmoothPlastic)
	part(m, "Hammer", Vector3.new(0.06, 0.1, 0.08), cf * CFrame.new(0, 0.3, 0.27), Color3.fromRGB(40, 40, 40), Enum.Material.Metal)
	local grip = part(m, "Handle", Vector3.new(0.22, 0.58, 0.32), cf * CFrame.new(0, -0.24, 0.26) * CFrame.Angles(math.rad(-16), 0, 0), orange, Enum.Material.SmoothPlastic)
	part(m, "GuardBottom", Vector3.new(0.06, 0.04, 0.3), cf * CFrame.new(0, -0.16, -0.04), orange, Enum.Material.SmoothPlastic)
	part(m, "Trigger", Vector3.new(0.04, 0.1, 0.04), cf * CFrame.new(0, -0.09, -0.02), Color3.fromRGB(40, 40, 40), Enum.Material.Metal)
	gripAttachment(grip, cf * CFrame.new(0, -0.22, 0.22))
	muzzleAt(barrel, cf * CFrame.new(0, 0.14, -0.86))
	return finishGun(m, grip, "flaregun", 1, 0.8)
end

-- Flashlight: F switches it on / off (a real light with shadows, everybody sees it). Forward = -Z.
function PropBuilders.flashlight(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Flashlight"
	local black = Color3.fromRGB(30, 30, 33)
	local body = part(m, "Body", Vector3.new(1.0, 0.2, 0.2), cf * CFrame.new(0, 0, 0.1) * CYL_Z, black, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Reflectance = 0.1 })
	part(m, "Grip", Vector3.new(0.5, 0.215, 0.215), cf * CFrame.new(0, 0, 0.3) * CYL_Z, Color3.fromRGB(20, 20, 22), Enum.Material.DiamondPlate, { Shape = Enum.PartType.Cylinder })
	part(m, "Head", Vector3.new(0.3, 0.32, 0.32), cf * CFrame.new(0, 0, -0.52) * CYL_Z, black, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	local lens = part(m, "Lens", Vector3.new(0.03, 0.27, 0.27), cf * CFrame.new(0, 0, -0.68) * CYL_Z, Color3.fromRGB(200, 205, 210), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Reflectance = 0.3 })
	part(m, "Button", Vector3.new(0.08, 0.05, 0.1), cf * CFrame.new(0, 0.11, -0.1), Color3.fromRGB(180, 40, 40), Enum.Material.SmoothPlastic)
	part(m, "TailCap", Vector3.new(0.08, 0.22, 0.22), cf * CFrame.new(0, 0, 0.62) * CYL_Z, black, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	local beamAtt = Instance.new("Attachment")
	beamAtt.Name = "LightAtt"
	beamAtt.CFrame = lens.CFrame:ToObjectSpace(cf * CFrame.new(0, 0, -0.72))
	beamAtt.Parent = lens
	local light = Instance.new("SpotLight")
	light.Name = "Beam"
	light.Face = Enum.NormalId.Front
	light.Angle = 50
	light.Range = 70
	light.Brightness = 3.2
	light.Shadows = true
	light.Color = Color3.fromRGB(255, 244, 220)
	light.Enabled = false
	light.Parent = beamAtt
	local glow = Instance.new("SurfaceLight")
	glow.Name = "Glow"
	glow.Face = Enum.NormalId.Front
	glow.Range = 4
	glow.Brightness = 1
	glow.Enabled = false
	glow.Parent = lens
	gripAttachment(body, cf * CFrame.new(0, 0, 0.3))
	muzzleAt(lens, cf * CFrame.new(0, 0, -0.72))
	setDensity(m, 0.8, 0.5, 0.05)
	m.PrimaryPart = body
	weldAll(m, body)
	m:SetAttribute("Item", "flashlight")
	m:SetAttribute("On", false)
	return m
end

-- Glue: a fat tube of super glue. F on one thing, F on another: the lighter one is pulled onto the heavier one,
-- the glued sides tight together. Good for six coats (three joins).
function PropBuilders.glue(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Glue"
	local tube = part(m, "Tube", Vector3.new(1.0, 0.36, 0.36), cf * CFrame.new(0, 0, 0.1) * CYL_Z, Color3.fromRGB(236, 236, 230), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "Label", Vector3.new(0.6, 0.37, 0.37), cf * CFrame.new(0, 0, 0.12) * CYL_Z, Color3.fromRGB(230, 60, 40), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "Crimp", Vector3.new(0.1, 0.06, 0.42), cf * CFrame.new(0, 0, 0.65), Color3.fromRGB(200, 200, 196), Enum.Material.Metal)
	part(m, "Shoulder", Vector3.new(0.16, 0.26, 0.26), cf * CFrame.new(0, 0, -0.47) * CYL_Z, Color3.fromRGB(236, 236, 230), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	local nozzle = part(m, "Nozzle", Vector3.new(0.34, 0.09, 0.09), cf * CFrame.new(0, 0, -0.71) * CYL_Z, Color3.fromRGB(248, 210, 40), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	gripAttachment(tube, cf * CFrame.new(0, 0, 0.15))
	muzzleAt(nozzle, cf * CFrame.new(0, 0, -0.9))
	setDensity(m, 0.6, 0.6, 0.05)
	m.PrimaryPart = tube
	weldAll(m, tube)
	m:SetAttribute("Item", "glue")
	m:SetAttribute("Coats", 6)
	return m
end

-- (v2.0) steel ball: a polished steel sphere with two dark grooves around it. Thrown with F (SteelBallService);
-- with the Spin it turns green (SteelBallService.SetLook).
function PropBuilders.steelball(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "SteelBall"
	local steel = Color3.fromRGB(150, 154, 162)
	local groove = Color3.fromRGB(44, 46, 52)
	local ball = part(m, "Ball", Vector3.new(0.95, 0.95, 0.95), cf, steel, Enum.Material.Metal, { Shape = Enum.PartType.Ball, Reflectance = 0.35 })
	part(m, "Groove", Vector3.new(0.05, 0.965, 0.965), cf, groove, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Groove", Vector3.new(0.05, 0.965, 0.965), cf * CFrame.Angles(0, math.rad(90), 0), groove, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	for _, a in { 45, 135, 225, 315 } do
		local r = math.rad(a)
		part(m, "Stud", Vector3.new(0.12, 0.12, 0.12), cf * CFrame.new(math.cos(r) * 0.33, 0.33, math.sin(r) * 0.33), groove, Enum.Material.Metal, { Shape = Enum.PartType.Ball })
	end
	-- held in the palm: the ball sits in front of the hand
	gripAttachment(ball, cf * CFrame.new(0, -0.42, 0.18))
	setDensity(m, 6, 0.55, 0.35)
	m.PrimaryPart = ball
	weldAll(m, ball)
	m:SetAttribute("Item", "steelball")
	return m
end

-- a prosthetic limb (the same look in the hand and fitted on a body): carbon socket, steel struts and joints.
-- `cf` = the middle of a 1 x 2 x 1 limb (top = shoulder / hip end).
local function prostheticLook(m: Model, cf: CFrame, kind: string): BasePart
	local carbon = Color3.fromRGB(34, 36, 40)
	local steel = Color3.fromRGB(170, 174, 182)
	local socket = part(m, "Socket", Vector3.new(1.02, 0.7, 1.02), cf * CFrame.new(0, 0.62, 0), carbon, Enum.Material.SmoothPlastic, { Reflectance = 0.15 })
	part(m, "Strap", Vector3.new(1.06, 0.12, 1.06), cf * CFrame.new(0, 0.42, 0), Color3.fromRGB(70, 70, 76), Enum.Material.Fabric)
	if kind == "Arm" then
		part(m, "UpperStrut", Vector3.new(0.3, 0.5, 0.3), cf * CFrame.new(0, 0.05, 0), steel, Enum.Material.Metal, { Reflectance = 0.3 })
		part(m, "Elbow", Vector3.new(0.42, 0.42, 0.42), cf * CFrame.new(0, -0.2, 0), carbon, Enum.Material.Metal, { Shape = Enum.PartType.Ball })
		part(m, "Forearm", Vector3.new(0.5, 0.55, 0.5), cf * CFrame.new(0, -0.55, 0), steel, Enum.Material.Metal, { Reflectance = 0.3 })
		part(m, "Palm", Vector3.new(0.6, 0.3, 0.42), cf * CFrame.new(0, -0.93, 0), carbon, Enum.Material.SmoothPlastic)
		for i = 0, 3 do
			part(m, "Finger", Vector3.new(0.1, 0.24, 0.12), cf * CFrame.new(-0.21 + i * 0.14, -1.0, -0.1), steel, Enum.Material.Metal)
		end
		part(m, "Thumb", Vector3.new(0.1, 0.12, 0.2), cf * CFrame.new(0.33, -0.86, -0.12), steel, Enum.Material.Metal)
	else
		part(m, "Knee", Vector3.new(0.48, 0.48, 0.48), cf * CFrame.new(0, 0.12, 0), carbon, Enum.Material.Metal, { Shape = Enum.PartType.Ball })
		part(m, "Pylon", Vector3.new(0.22, 0.95, 0.22), cf * CFrame.new(0, -0.45, 0), steel, Enum.Material.Metal, { Reflectance = 0.3 })
		-- a carbon running blade for a foot
		part(m, "Blade", Vector3.new(0.5, 0.12, 0.9), cf * CFrame.new(0, -0.94, -0.18) * CFrame.Angles(math.rad(-8), 0, 0), carbon, Enum.Material.SmoothPlastic, { Reflectance = 0.2 })
		part(m, "BladeCurve", Vector3.new(0.5, 0.36, 0.12), cf * CFrame.new(0, -0.78, 0.22), carbon, Enum.Material.SmoothPlastic, { Reflectance = 0.2 })
	end
	return socket
end
PropBuilders.ProstheticLook = prostheticLook

function PropBuilders.prosthetic_arm(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Prosthetic Arm"
	-- lying along -Z in the hand: the limb's top points backwards
	local look = cf * CFrame.Angles(math.rad(-90), 0, 0)
	local socket = prostheticLook(m, look, "Arm")
	gripAttachment(socket, cf * CFrame.new(0, 0, 0.2))
	setDensity(m, 0.9, 0.5, 0.05)
	m.PrimaryPart = socket
	weldAll(m, socket)
	m:SetAttribute("Item", "prosthetic_arm")
	return m
end

function PropBuilders.prosthetic_leg(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Prosthetic Leg"
	local look = cf * CFrame.Angles(math.rad(-90), 0, 0)
	local socket = prostheticLook(m, look, "Leg")
	gripAttachment(socket, cf * CFrame.new(0, 0, 0.2))
	setDensity(m, 0.9, 0.5, 0.05)
	m.PrimaryPart = socket
	weldAll(m, socket)
	m:SetAttribute("Item", "prosthetic_leg")
	return m
end

------------------------------------------------------------------------
-- v2.0 admin gear
------------------------------------------------------------------------

-- Kick hammer (admins): a huge mallet with KICK on it. Whoever it hits is kicked out of the server.
function PropBuilders.banhammer(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Kick Hammer"
	local handle = part(m, "Handle", Vector3.new(3.6, 0.26, 0.26), cf * CFrame.new(0, 0, -0.7) * CYL_Z, Color3.fromRGB(70, 40, 24), Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	part(m, "Grip", Vector3.new(0.9, 0.3, 0.3), cf * CFrame.new(0, 0, 0.75) * CYL_Z, Color3.fromRGB(150, 24, 24), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	local head = part(m, "SledgeHead", Vector3.new(2.6, 1.3, 1.3), cf * CFrame.new(0, 0, -2.75), Color3.fromRGB(28, 28, 32), Enum.Material.Metal, { Reflectance = 0.15 })
	for _, x in { -1.33, 1.33 } do
		part(m, "Face", Vector3.new(0.08, 1.2, 1.2), cf * CFrame.new(x, 0, -2.75), Color3.fromRGB(200, 30, 30), Enum.Material.Neon)
	end
	for _, face in { Enum.NormalId.Top, Enum.NormalId.Bottom } do
		local g = Instance.new("SurfaceGui")
		g.Face = face
		g.CanvasSize = Vector2.new(260, 130)
		g.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Text = "KICK"
		t.TextScaled = true
		t.Font = Enum.Font.Sarpanch
		t.TextColor3 = Color3.fromRGB(255, 60, 50)
		t.Parent = g
		g.Parent = head
	end
	gripAttachment(handle, cf * CFrame.new(0, 0, 0.75))
	setDensity(m, 1.2, 0.5, 0.05)
	m.PrimaryPart = handle
	weldAll(m, handle)
	m:SetAttribute("Item", "banhammer")
	m:SetAttribute("OwnerOnly", true)
	return m
end

-- Sun cannon (admins): set it down anywhere. Its barrel always points at the sun. Fired from the admin menu it
-- charges for 20 s, shoots a giant beam into the sun, the sun swells and goes supernova.
-- (v2.0) rebuilt: an octagonal plinth on four hydraulic feet with capacitor banks round a glowing core; a rotor and a
-- yoke that turn towards the sun (parts marked SunYaw: SuperService turns them round the upright only); in the yoke
-- the gun itself (welded to the Turret: it also tilts): a finned breech, a stepped barrel wound with six glowing
-- coils, three capacitor tubes along it, a muzzle ring with three focusing prongs round the Lens.
function PropBuilders.suncannon(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Sun Cannon"
	local dark = Color3.fromRGB(34, 34, 40)
	local steel = Color3.fromRGB(78, 80, 90)
	local gold = Color3.fromRGB(214, 168, 64)
	local glowC = Color3.fromRGB(255, 176, 60)
	local hot = Color3.fromRGB(255, 236, 170)
	local MT = Enum.Material.Metal
	local NE = Enum.Material.Neon
	local bottom = cf * CFrame.new(0, -4.5, 0)
	local function at(x: number, y: number, z: number): CFrame
		return bottom * CFrame.new(x, y, z)
	end
	-- a round rod from a to b (world points)
	local function rod(name: string, a: Vector3, b: Vector3, d: number, color: Color3, mat: Enum.Material): Part
		local len = (b - a).Magnitude
		return part(m, name, Vector3.new(len, d, d), CFrame.lookAt((a + b) / 2, b) * CYL_Z, color, mat, { Shape = Enum.PartType.Cylinder })
	end

	-- the plinth (stays put)
	local base = part(m, "Base", Vector3.new(9, 1, 9), at(0, 0.5, 0), dark, Enum.Material.DiamondPlate)
	for i = 0, 7 do
		local a = i * math.pi / 4
		part(m, "Trim", Vector3.new(3.6, 0.22, 0.3), at(math.sin(a) * 4.32, 1.02, math.cos(a) * 4.32) * CFrame.Angles(0, a, 0), gold, MT, { Reflectance = 0.3 })
	end
	part(m, "Step", Vector3.new(7, 0.8, 7), at(0, 1.4, 0), steel, MT)
	part(m, "StepRing", Vector3.new(0.3, 6.4, 6.4), at(0, 1.9, 0) * CYL_Y, gold, MT, { Shape = Enum.PartType.Cylinder, Reflectance = 0.3 })
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local s, c = math.sin(a), math.cos(a)
		part(m, "FootPad", Vector3.new(1.7, 0.4, 1.7), at(s * 5.7, 0.2, c * 5.7) * CFrame.Angles(0, a, 0), dark, Enum.Material.DiamondPlate)
		rod("Strut", at(s * 3.1, 1.6, c * 3.1).Position, at(s * 5.6, 0.4, c * 5.6).Position, 0.55, steel, MT)
		rod("Piston", at(s * 3.9, 1.25, c * 3.9).Position, at(s * 5.15, 0.62, c * 5.15).Position, 0.75, Color3.fromRGB(170, 172, 180), MT)
	end
	part(m, "Column", Vector3.new(2.6, 3.2, 3.2), at(0, 3.1, 0) * CYL_Y, dark, MT, { Shape = Enum.PartType.Cylinder })
	part(m, "CoreGlow", Vector3.new(0.5, 3.3, 3.3), at(0, 3.0, 0) * CYL_Y, glowC, NE, { Shape = Enum.PartType.Cylinder })
	for i = 0, 3 do
		local a = i * math.pi / 2
		local s, c = math.sin(a), math.cos(a)
		part(m, "CapBank", Vector3.new(1.4, 2.2, 0.9), at(s * 2.55, 2.9, c * 2.55) * CFrame.Angles(0, a, 0), steel, MT)
		part(m, "Capacitor", Vector3.new(0.3, 1.7, 0.95), at(s * 2.55, 2.9, c * 2.55) * CFrame.Angles(0, a, 0) * CFrame.new(-0.35, 0, 0), glowC, NE, { Transparency = 0.35 })
		part(m, "Capacitor", Vector3.new(0.3, 1.7, 0.95), at(s * 2.55, 2.9, c * 2.55) * CFrame.Angles(0, a, 0) * CFrame.new(0.35, 0, 0), glowC, NE, { Transparency = 0.35 })
		rod("Cable", at(s * 2.55, 4.0, c * 2.55).Position, at(s * 1.2, 4.55, c * 1.2).Position, 0.25, Color3.fromRGB(20, 20, 22), Enum.Material.SmoothPlastic)
	end

	-- the rotor and the yoke (turn towards the sun round the upright)
	local pivot = at(0, 6.4, 0)
	local yawParts = {}
	local function yaw(p: BasePart)
		table.insert(yawParts, p)
		return p
	end
	yaw(part(m, "Rotor", Vector3.new(0.9, 4.6, 4.6), at(0, 4.95, 0) * CYL_Y, gold, MT, { Shape = Enum.PartType.Cylinder, Reflectance = 0.3 }))
	yaw(part(m, "RotorTop", Vector3.new(0.3, 4.0, 4.0), at(0, 5.5, 0) * CYL_Y, dark, MT, { Shape = Enum.PartType.Cylinder }))
	for _, sx in { -1, 1 } do
		yaw(part(m, "Yoke", Vector3.new(0.6, 3.0, 2.4), at(sx * 2.15, 6.3, 0), steel, MT))
		yaw(part(m, "YokeRib", Vector3.new(0.7, 0.3, 2.5), at(sx * 2.15, 7.85, 0), gold, MT))
		yaw(part(m, "Bearing", Vector3.new(0.5, 1.7, 1.7), at(sx * 2.55, 6.4, 0), gold, MT, { Shape = Enum.PartType.Cylinder, Reflectance = 0.3 }))
		yaw(part(m, "Counterweight", Vector3.new(0.9, 1.4, 1.4), at(sx * 2.6, 5.6, 1.4), dark, MT))
	end

	-- the gun (welded to the Turret: it turns and tilts at the sun). Forward = -Z
	local turret = part(m, "Turret", Vector3.new(3.0, 3.0, 3.0), pivot, gold, MT, { Shape = Enum.PartType.Ball, Reflectance = 0.35 })
	local gun = {}
	local function g(p: BasePart)
		table.insert(gun, p)
		return p
	end
	local function gp(name: string, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material, props: { [string]: any }?)
		return g(part(m, name, size, pivot * off, color, mat, props))
	end
	gp("Axle", Vector3.new(4.0, 0.9, 0.9), CFrame.identity, dark, MT, { Shape = Enum.PartType.Cylinder })
	gp("Breech", Vector3.new(2.6, 2.6, 3.0), CFrame.new(0, 0, 2.0), dark, MT)
	gp("BreechCap", Vector3.new(0.5, 2.3, 2.3), CFrame.new(0, 0, 3.6) * CYL_Z, gold, MT, { Shape = Enum.PartType.Cylinder })
	for i = 0, 4 do
		gp("HeatFin", Vector3.new(3.4, 3.4, 0.12), CFrame.new(0, 0, 1.0 + i * 0.5), steel, MT)
	end
	gp("Barrel1", Vector3.new(3.2, 2.1, 2.1), CFrame.new(0, 0, -2.6) * CYL_Z, steel, MT, { Shape = Enum.PartType.Cylinder })
	gp("Barrel2", Vector3.new(3.0, 1.8, 1.8), CFrame.new(0, 0, -5.6) * CYL_Z, dark, MT, { Shape = Enum.PartType.Cylinder })
	gp("Barrel3", Vector3.new(2.6, 1.5, 1.5), CFrame.new(0, 0, -8.4) * CYL_Z, steel, MT, { Shape = Enum.PartType.Cylinder })
	for i, z in { -1.5, -3.0, -4.5, -6.0, -7.4, -8.8 } do
		local d = i <= 2 and 2.55 or (i <= 4 and 2.25 or 1.95)
		gp("Coil", Vector3.new(0.34, d, d), CFrame.new(0, 0, z) * CYL_Z, glowC, NE, { Shape = Enum.PartType.Cylinder })
		gp("CoilCollar", Vector3.new(0.14, d + 0.12, d + 0.12), CFrame.new(0, 0, z + 0.26) * CYL_Z, gold, MT, { Shape = Enum.PartType.Cylinder })
	end
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3 + math.pi / 2
		local x, y = math.cos(a) * 1.2, math.sin(a) * 1.2
		gp("Capacitor", Vector3.new(6.2, 0.34, 0.34), CFrame.new(x, y, -4.9) * CYL_Z, hot, NE, { Shape = Enum.PartType.Cylinder, Transparency = 0.3 })
		gp("TubeClamp", Vector3.new(0.5, 0.5, 0.5), CFrame.new(x, y, -2.0), dark, MT)
		gp("TubeClamp", Vector3.new(0.5, 0.5, 0.5), CFrame.new(x, y, -7.8), dark, MT)
	end
	gp("MuzzleRing", Vector3.new(0.7, 2.5, 2.5), CFrame.new(0, 0, -9.9) * CYL_Z, gold, MT, { Shape = Enum.PartType.Cylinder, Reflectance = 0.3 })
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3 + math.pi / 2
		local x, y = math.cos(a) * 1.05, math.sin(a) * 1.05
		gp("Prong", Vector3.new(0.32, 0.32, 2.4), CFrame.new(x * 0.92, y * 0.92, -11.3) * CFrame.Angles(y * 0.12, -x * 0.12, 0), gold, MT)
		gp("ProngTip", Vector3.new(0.36, 0.36, 0.36), CFrame.new(x * 0.78, y * 0.78, -12.5), hot, NE, { Shape = Enum.PartType.Ball })
	end
	gp("Sight", Vector3.new(0.4, 0.5, 1.6), CFrame.new(0, 1.45, -1.2), dark, MT)
	local lens = gp("Lens", Vector3.new(0.25, 1.6, 1.6), CFrame.new(0, 0, -10.3) * CYL_Z, hot, NE, { Shape = Enum.PartType.Cylinder })
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = lens.CFrame:ToObjectSpace(pivot * CFrame.new(0, 0, -10.6))
	muzzle.Parent = lens

	for _, p in m:GetChildren() do
		if p:IsA("BasePart") then
			p.Anchored = true
		end
	end
	deflicker(m, base)
	m.PrimaryPart = base
	-- the gun: welded to the turret (SuperService moves what is welded to it); the yoke: turned round the upright
	for _, p in gun do
		local w = Instance.new("WeldConstraint")
		w.Part0 = turret
		w.Part1 = p
		w.Parent = p
	end
	local frame0 = CFrame.new(pivot.Position) * bottom.Rotation
	for _, p in yawParts do
		p:SetAttribute("SunYaw", true)
		p:SetAttribute("YawOff", frame0:ToObjectSpace(p.CFrame))
	end
	m:SetAttribute("SunCannon", true)
	m:SetAttribute("OwnerOnly", true)
	return m
end

------------------------------------------------------------------------
-- v2.0 jet: a fast fighter. Takes off from the runway (W = throttle up), points where you look, F = cannon,
-- C = homing missile at what is locked (keep it in front of the nose), X = bomb. Forward = -Z.
------------------------------------------------------------------------
function PropBuilders.jet(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Jet"
	local grey = Color3.fromRGB(116, 124, 132)
	local greyDark = Color3.fromRGB(86, 92, 100)
	local dark = Color3.fromRGB(34, 36, 40)
	local black = Color3.fromRGB(18, 18, 20)
	local glass = Color3.fromRGB(120, 150, 90)
	local SP = Enum.Material.SmoothPlastic
	local MT = Enum.Material.Metal
	local CYL = { Shape = Enum.PartType.Cylinder }
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function v3(x: number, y: number, z: number): Vector3
		return Vector3.new(x, y, z)
	end
	local chassis = part(m, "Chassis", v3(3.2, 2.4, 20), cf, grey, MT)
	-- nose: tapering steps to the radome
	part(m, "Nose1", v3(2.8, 2.1, 2.4), at(0, 0.05, -11.2), grey, MT)
	part(m, "Nose2", v3(2.2, 1.7, 2.2), at(0, 0.0, -13.4), grey, MT)
	part(m, "Nose3", v3(1.5, 1.2, 1.8), at(0, -0.05, -15.3), greyDark, MT)
	part(m, "Radome", v3(1.1, 0.9, 1.1), at(0, -0.1, -16.6), dark, SP, { Shape = Enum.PartType.Ball })
	part(m, "PitotTube", v3(0.08, 0.08, 1.4), at(0, -0.1, -17.6), black, MT, { CanCollide = false })
	-- cockpit: canopy, frame, seat, panel. (v2.0 fix) The pilot sits deep in the fuselage under a wide bubble: a
	-- player's arms and head no longer stick out through the glass (the canopy is as wide as a body with its arms)
	part(m, "CanopyBase", v3(3.0, 0.3, 5.2), at(0, 1.3, -7.2), greyDark, MT)
	part(m, "Canopy", v3(3.0, 1.55, 4.8), at(0, 2.0, -7.3), glass, Enum.Material.Glass, { Transparency = 0.5, Reflectance = 0.3, CanCollide = false })
	part(m, "CanopyFrame", v3(3.1, 0.16, 0.2), at(0, 2.7, -8.2), dark, MT, { CanCollide = false })
	part(m, "CanopyFrame", v3(0.16, 0.16, 4.6), at(0, 2.78, -7.3), dark, MT, { CanCollide = false })
	part(m, "Spine", v3(1.4, 0.7, 10), at(0, 1.55, 2.0), greyDark, MT)
	part(m, "InstrumentPanel", v3(2.4, 0.55, 0.35), at(0, 1.0, -8.75), black, SP, { CanCollide = false })
	for k, x in { -0.75, -0.25, 0.25, 0.75 } do
		-- the dials (green / amber glow)
		part(m, "Dial", v3(0.3, 0.3, 0.04), at(x, 1.05, -8.56), k % 2 == 0 and Color3.fromRGB(255, 190, 60) or Color3.fromRGB(80, 255, 120), Enum.Material.Neon, { CanCollide = false, Transparency = 0.25 })
	end
	part(m, "HUDGlass", v3(0.9, 0.55, 0.05), at(0, 1.55, -8.8) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(80, 255, 120), Enum.Material.Glass, { Transparency = 0.65, CanCollide = false })
	part(m, "Stick", v3(0.14, 0.8, 0.14), at(0, -0.2, -7.6) * CFrame.Angles(math.rad(-12), 0, 0), black, MT, { CanCollide = false })
	local seat = part(m, "DriverSeat", v3(1.6, 0.3, 1.4), at(0, -0.5, -6.6), Color3.fromRGB(40, 40, 36), Enum.Material.Fabric, { CanCollide = false })
	part(m, "SeatBack", v3(1.6, 2.2, 0.3), at(0, 0.55, -5.75), Color3.fromRGB(40, 40, 36), Enum.Material.Fabric, { CanCollide = false })
	part(m, "Headrest", v3(1.0, 0.6, 0.35), at(0, 1.85, -5.72), Color3.fromRGB(30, 30, 28), Enum.Material.Fabric, { CanCollide = false })
	local sa = Instance.new("Attachment")
	sa.Name = "SeatAtt"
	sa.CFrame = CFrame.new(0, 1.15, -0.1)
	sa.Parent = seat
	seat:SetAttribute("ExitSide", -1)
	-- intakes on both sides
	for _, sx in { -1, 1 } do
		part(m, "Intake", v3(1.3, 1.9, 4.6), at(sx * 2.15, -0.25, -3.6), greyDark, MT)
		part(m, "IntakeMouth", v3(1.0, 1.6, 0.1), at(sx * 2.15, -0.25, -5.95), black, SP)
	end
	-- delta wings (swept), wing tips with rails
	for _, sx in { -1, 1 } do
		part(m, "Wing", v3(7.6, 0.32, 7.2), at(sx * 5.2, -0.35, 2.4) * CFrame.Angles(0, math.rad(sx * 14), 0), grey, MT)
		part(m, "WingRoot", v3(3.0, 0.4, 9.0), at(sx * 2.6, -0.3, 1.6), grey, MT)
		part(m, "WingTip", v3(1.6, 0.3, 3.4), at(sx * 9.3, -0.35, 4.4), greyDark, MT)
		part(m, "TipRail", v3(0.25, 0.25, 3.8), at(sx * 10.1, -0.35, 4.3), dark, MT, { CanCollide = false })
		part(m, "WingLight", v3(0.2, 0.2, 0.3), at(sx * 10.25, -0.3, 2.5), sx < 0 and Color3.fromRGB(255, 40, 40) or Color3.fromRGB(40, 255, 60), Enum.Material.Neon, { CanCollide = false })
		-- tail: stabilizers and the two fins
		part(m, "Stabilizer", v3(4.4, 0.25, 3.0), at(sx * 3.4, -0.2, 9.6) * CFrame.Angles(0, math.rad(sx * 18), 0), grey, MT)
		part(m, "Fin", v3(0.25, 4.0, 3.6), at(sx * 1.3, 2.7, 8.6) * CFrame.Angles(0, 0, math.rad(-sx * 14)), grey, MT)
		part(m, "FinTip", v3(0.27, 0.5, 1.4), at(sx * 1.78, 4.6, 9.4) * CFrame.Angles(0, 0, math.rad(-sx * 14)), dark, MT, { CanCollide = false })
	end
	-- engines: two nozzles with afterburner flames (switched on by the clients from the "Throttle" attribute)
	local hood = part(m, "Hood", v3(3.0, 2.2, 2.4), at(0, -0.1, 9.6), greyDark, MT)
	for _, sx in { -1, 1 } do
		local nozzle = part(m, "Nozzle", v3(1.6, 1.4, 1.4), at(sx * 0.8, -0.1, 11.4) * CYL_Z, dark, MT, CYL)
		part(m, "NozzleInner", v3(0.1, 1.05, 1.05), at(sx * 0.8, -0.1, 12.22) * CYL_Z, Color3.fromRGB(255, 120, 40), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, CanCollide = false })
		local fa = Instance.new("Attachment")
		fa.Name = "Afterburner"
		fa.CFrame = nozzle.CFrame:ToObjectSpace(at(sx * 0.8, -0.1, 12.6) * CFrame.Angles(math.rad(90), 0, 0))
		fa.Parent = nozzle
		local flame = Instance.new("ParticleEmitter")
		flame.Name = "Flame"
		flame.Texture = "rbxasset://textures/particles/fire_main.dds"
		flame.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120), Color3.fromRGB(255, 80, 30))
		flame.LightEmission = 1
		flame.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0.2) })
		flame.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		flame.Lifetime = NumberRange.new(0.12, 0.25)
		flame.Rate = 0
		flame.Speed = NumberRange.new(40, 60)
		flame.EmissionDirection = Enum.NormalId.Top
		flame.LockedToPart = true
		flame.Parent = fa
	end
	-- landing gear: a nose wheel and two main wheels (balls on almost no friction: it rolls down the runway)
	local function wheel(name: string, x: number, z: number, d: number)
		part(m, name .. "Strut", v3(0.25, 1.5, 0.25), at(x, -1.75, z), dark, MT, { CanCollide = false })
		local w = part(m, name, v3(d, d, d), at(x, -2.6 + d * 0.5 - 0.05, z), black, Enum.Material.Fabric, { Shape = Enum.PartType.Ball })
		w.CustomPhysicalProperties = PhysicalProperties.new(1, 0.02, 0.1, 100, 1)
		w:SetAttribute("JetWheel", true)
	end
	wheel("NoseWheel", 0, -9.2, 1.0)
	wheel("MainWheelL", -2.3, 2.6, 1.3)
	wheel("MainWheelR", 2.3, 2.6, 1.3)
	-- 4 missiles under the wings, 6 bombs under the belly
	local function store(kind: string, idx: number, x: number, y: number, z: number, len: number, d: number, color: Color3)
		local body = part(m, kind .. "Body", v3(len, d, d), at(x, y, z) * CYL_Z, color, MT, { Shape = Enum.PartType.Cylinder, CanCollide = false })
		body:SetAttribute(kind .. "Idx", idx)
		local tip = part(m, kind .. "Tip", v3(d * 0.9, d * 0.9, d * 0.9), at(x, y, z - len * 0.5), color, MT, { Shape = Enum.PartType.Ball, CanCollide = false })
		tip:SetAttribute(kind .. "Idx", idx)
		tip:SetAttribute(kind .. "Tip", true)
		local fin = part(m, kind .. "Fin", v3(d * 1.8, 0.05, d * 1.2), at(x, y, z + len * 0.42), dark, MT, { CanCollide = false })
		fin:SetAttribute(kind .. "Idx", idx)
	end
	store("Missile", 1, -4.4, -0.85, 1.6, 3.4, 0.36, Color3.fromRGB(220, 222, 214))
	store("Missile", 2, 4.4, -0.85, 1.6, 3.4, 0.36, Color3.fromRGB(220, 222, 214))
	store("Missile", 3, -7.0, -0.85, 3.4, 3.0, 0.34, Color3.fromRGB(220, 222, 214))
	store("Missile", 4, 7.0, -0.85, 3.4, 3.0, 0.34, Color3.fromRGB(220, 222, 214))
	local bi = 0
	for _, z in { -2.5, 0.3, 3.1 } do
		for _, x in { -0.85, 0.85 } do
			bi += 1
			store("Bomb", bi, x, -1.75, z, 2.2, 0.62, Color3.fromRGB(70, 82, 56))
		end
	end
	part(m, "BombRack", v3(2.4, 0.3, 8.0), at(0, -1.33, 0.3), dark, MT, { CanCollide = false })
	-- the cannon in the nose
	local gunPort = part(m, "GunPort", v3(0.3, 0.3, 1.2), at(1.05, 0.55, -11.6), black, MT, { CanCollide = false })
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = gunPort.CFrame:ToObjectSpace(at(1.05, 0.55, -12.3))
	muzzle.Parent = gunPort
	-- markings
	for _, sx in { -1, 1 } do
		part(m, "Roundel", v3(0.05, 1.2, 1.2), at(sx * 1.62, 0.2, 4.0) * CFrame.Angles(0, 0, math.rad(90)) * CYL_Y, Color3.fromRGB(40, 70, 140), SP, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	end
	-- engine smoke / fire when it is hurt (VehicleService)
	local smoke = Instance.new("Smoke")
	smoke.Name = "EngineSmoke"
	smoke.Color = Color3.fromRGB(60, 58, 56)
	smoke.Opacity = 0.3
	smoke.RiseVelocity = 2
	smoke.Size = 4
	smoke.Enabled = false
	smoke.Parent = hood
	local fire = Instance.new("Fire")
	fire.Name = "EngineFire"
	fire.Size = 7
	fire.Heat = 4
	fire.Enabled = false
	fire.Parent = hood
	-- flight: one force (thrust + lift + drag, computed by the pilot's client) and the attitude
	local flyAtt = Instance.new("Attachment")
	flyAtt.Name = "FlyAtt"
	flyAtt.Parent = chassis
	local force = Instance.new("VectorForce")
	force.Name = "JetForce"
	force.Attachment0 = flyAtt
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Visible = false
	force.Parent = chassis
	local align = Instance.new("AlignOrientation")
	align.Name = "JetAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = flyAtt
	align.Enabled = false
	align.MaxTorque = 1e9
	align.Responsiveness = 9
	align.Parent = chassis

	-- (v2.0) more detail: a teardrop canopy (windscreen + fairing), leading-edge strakes, ventral fins, a two-tone
	-- belly, panel lines, nozzle rings, strobes and a number on the nose
	local function wedge(name: string, size: Vector3, wcf: CFrame, color: Color3, material: Enum.Material, props: { [string]: any }?): WedgePart
		local w = Instance.new("WedgePart")
		w.Name = name
		w.Size = size
		w.CFrame = wcf
		w.Color = color
		w.Material = material
		if props then
			for k, v in props do
				(w :: any)[k] = v
			end
		end
		w.Parent = m
		return w
	end
	wedge("Windscreen", v3(3.0, 1.55, 1.7), at(0, 2.0, -10.55), glass, Enum.Material.Glass, { Transparency = 0.5, Reflectance = 0.3, CanCollide = false })
	wedge("CanopyFairing", v3(2.6, 1.4, 2.6), at(0, 1.95, -3.6) * CFrame.Angles(0, math.rad(180), 0), greyDark, MT, { CanCollide = false })
	wedge("NoseTop", v3(2.2, 0.55, 2.6), at(0, 1.05, -12.3), grey, MT, { CanCollide = false })
	for _, sx in { -1, 1 } do
		part(m, "Strake", v3(1.5, 0.22, 5.6), at(sx * 2.55, 0.45, -5.6) * CFrame.Angles(0, math.rad(sx * 8), 0), grey, MT, { CanCollide = false })
		wedge("IntakeRamp", v3(1.3, 0.5, 1.4), at(sx * 2.15, 0.95, -5.2), greyDark, MT, { CanCollide = false })
		part(m, "VentralFin", v3(0.2, 1.3, 2.4), at(sx * 1.35, -1.75, 8.6) * CFrame.Angles(0, 0, math.rad(sx * 22)), greyDark, MT, { CanCollide = false })
		part(m, "Strobe", v3(0.22, 0.22, 0.22), at(sx * 1.85, 4.9, 10.1), Color3.fromRGB(255, 60, 50), Enum.Material.Neon, { CanCollide = false })
		part(m, "NozzleRing", v3(0.25, 1.62, 1.62), at(sx * 0.8, -0.1, 11.95) * CYL_Z, greyDark, MT, { Shape = Enum.PartType.Cylinder, CanCollide = false })
		part(m, "Pylon", v3(0.2, 0.45, 2.2), at(sx * 4.4, -0.62, 1.6), dark, MT, { CanCollide = false })
		part(m, "Pylon", v3(0.2, 0.45, 2.0), at(sx * 7.0, -0.62, 3.4), dark, MT, { CanCollide = false })
	end
	part(m, "Belly", v3(2.95, 0.08, 18), at(0, -1.22, 0.4), Color3.fromRGB(150, 158, 166), MT, { CanCollide = false })
	for _, z in { -4.2, 0.2, 4.6 } do
		part(m, "PanelLine", v3(3.24, 0.05, 0.06), at(0, 1.2, z), dark, SP, { CanCollide = false })
	end
	local noseNum = part(m, "NoseNumber", v3(2.25, 1.2, 1.6), at(0, 0.05, -13.4), grey, MT, { CanCollide = false, Transparency = 1 })
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		local g = Instance.new("SurfaceGui")
		g.Face = face
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 40
		g.LightInfluence = 1
		g.Parent = noseNum
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.Sarpanch
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(30, 34, 40)
		t.Text = "07"
		t.Parent = g
	end

	-- (v2.0) and bigger: the whole jet x1.4 (round its centre; the markers / the spawn menu stand it higher)
	m.PrimaryPart = chassis
	local JET_SCALE = 1.4
	local okScale = pcall(function()
		m:ScaleTo(JET_SCALE)
	end)
	if okScale then
		m:SetAttribute("JetScale", JET_SCALE)
	end

	deflicker(m, chassis)
	setDensity(m, 0.25, 0.4, 0.05)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(1.2, 0.3, 0.05, 1, 1)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("JetWheel") then
			d.CustomPhysicalProperties = PhysicalProperties.new(1, 0.02, 0.1, 100, 1)
		end
	end
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") and d ~= chassis then
			local w = Instance.new("WeldConstraint")
			w.Part0 = chassis
			w.Part1 = d
			w.Parent = d
		end
	end
	m.PrimaryPart = chassis
	m:SetAttribute("Car", true)
	m:SetAttribute("Jet", true)
	m:SetAttribute("CarHP", 260)
	m:SetAttribute("CarMaxHP", 260)
	m:SetAttribute("Missiles", 4)
	m:SetAttribute("Bombs", 6)
	return m
end

-- soft things swallow the landing (Sensor.luau reads the "Soft" attribute: 1 = never hurts)
for name, amount in { trampoline = 1, mattress = 0.75, bed = 0.55, sofa = 0.35, armchair = 0.3, rug = 0.2 } do
	local orig = (PropBuilders :: any)[name]
	if orig then
		(PropBuilders :: any)[name] = function(cf: CFrame)
			local m = orig(cf)
			m:SetAttribute("Soft", amount)
			return m
		end
	end
end

------------------------------------------------------------------------
-- v2.0: props for the new maps (asylum, ship, megastore) and two more weapons
------------------------------------------------------------------------

local function ring(m: Model, name: string, cf: CFrame, radius: number, thick: number, segs: number, colors: { Color3 }, mat: Enum.Material)
	local first = nil
	for i = 0, segs - 1 do
		local a = (i + 0.5) / segs * math.pi * 2
		local len = 2 * math.pi * radius / segs + 0.06
		local p = part(m, name, Vector3.new(thick, thick, len), cf * CFrame.Angles(0, -a, 0) * CFrame.new(radius, 0, 0), colors[i % #colors + 1], mat)
		first = first or p
	end
	return first :: BasePart
end

-- wheelchair: seat, back, two big wheels, two small ones, push handles. Centre of a 2.4 x 3.4 x 3.2 box.
function PropBuilders.wheelchair(cf: CFrame): Model
	local m = Instance.new("Model")
	local steel = Color3.fromRGB(160, 164, 170)
	local seatC = Color3.fromRGB(40, 40, 46)
	local seat = part(m, "Seat", Vector3.new(1.8, 0.25, 1.8), cf * CFrame.new(0, -0.2, 0.1), seatC, Enum.Material.Fabric)
	part(m, "Back", Vector3.new(1.8, 1.6, 0.2), cf * CFrame.new(0, 0.7, 1.0) * CFrame.Angles(math.rad(-8), 0, 0), seatC, Enum.Material.Fabric)
	for _, sx in { -1.05, 1.05 } do
		part(m, "Wheel", Vector3.new(0.18, 2.5, 2.5), cf * CFrame.new(sx, -0.45, 0.45), Color3.fromRGB(26, 26, 28), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
		part(m, "Rim", Vector3.new(0.2, 2.1, 2.1), cf * CFrame.new(sx * 1.01, -0.45, 0.45), steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
		part(m, "Caster", Vector3.new(0.14, 0.6, 0.6), cf * CFrame.new(sx * 0.75, -1.4, -1.25), Color3.fromRGB(26, 26, 28), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
		part(m, "Frame", Vector3.new(0.12, 0.12, 2.6), cf * CFrame.new(sx * 0.9, -0.45, -0.2), steel, Enum.Material.Metal)
		part(m, "Handle", Vector3.new(0.12, 0.12, 0.5), cf * CFrame.new(sx * 0.85, 1.55, 1.3), steel, Enum.Material.Metal)
		part(m, "Post", Vector3.new(0.12, 2.1, 0.12), cf * CFrame.new(sx * 0.85, 0.5, 1.1), steel, Enum.Material.Metal)
	end
	part(m, "FootRest", Vector3.new(1.4, 0.1, 0.5), cf * CFrame.new(0, -1.25, -1.35), steel, Enum.Material.DiamondPlate)
	return prop("Wheelchair", seat, m, 0.5)
end

-- gurney: a padded top on a frame with four castors. 2.6 x 3.2 x 6.6
function PropBuilders.gurney(cf: CFrame): Model
	local m = Instance.new("Model")
	local steel = Color3.fromRGB(176, 180, 186)
	local top = part(m, "Top", Vector3.new(2.4, 0.35, 6.2), cf * CFrame.new(0, 0.55, 0), steel, Enum.Material.Metal)
	part(m, "Pad", Vector3.new(2.2, 0.3, 6.0), cf * CFrame.new(0, 0.86, 0), Color3.fromRGB(70, 110, 120), Enum.Material.Fabric)
	part(m, "Sheet", Vector3.new(2.25, 0.08, 3.4), cf * CFrame.new(0, 1.05, 1.2), Color3.fromRGB(226, 224, 216), Enum.Material.Fabric)
	part(m, "Pillow", Vector3.new(1.6, 0.35, 0.9), cf * CFrame.new(0, 1.18, -2.4), Color3.fromRGB(236, 236, 230), Enum.Material.Fabric)
	for _, sx in { -1, 1 } do
		for _, sz in { -2.7, 2.7 } do
			part(m, "Leg", Vector3.new(0.14, 1.9, 0.14), cf * CFrame.new(sx * 1.0, -0.45, sz), steel, Enum.Material.Metal)
			part(m, "Castor", Vector3.new(0.4, 0.4, 0.4), cf * CFrame.new(sx * 1.0, -1.4, sz), Color3.fromRGB(30, 30, 32), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
		end
		part(m, "SideRail", Vector3.new(0.1, 0.1, 5.4), cf * CFrame.new(sx * 1.2, 1.3, 0), steel, Enum.Material.Metal)
	end
	return prop("Gurney", top, m, 0.5)
end

-- shopping cart: a wire-look basket on a frame, a red handle, four castors. 2.6 x 3.6 x 4.4
function PropBuilders.shoppingcart(cf: CFrame): Model
	local m = Instance.new("Model")
	local wire = Color3.fromRGB(190, 194, 200)
	local base = part(m, "Bottom", Vector3.new(2.3, 0.12, 3.6), cf * CFrame.new(0, 0.1, -0.2), wire, Enum.Material.DiamondPlate)
	for _, sx in { -1.15, 1.15 } do
		part(m, "Side", Vector3.new(0.08, 1.7, 3.8), cf * CFrame.new(sx, 0.95, -0.2), wire, Enum.Material.DiamondPlate, { Transparency = 0.35 })
	end
	part(m, "Front", Vector3.new(2.3, 1.7, 0.08), cf * CFrame.new(0, 0.95, -2.1), wire, Enum.Material.DiamondPlate, { Transparency = 0.35 })
	part(m, "BackGate", Vector3.new(2.3, 1.7, 0.08), cf * CFrame.new(0, 0.95, 1.7), wire, Enum.Material.DiamondPlate, { Transparency = 0.35 })
	part(m, "HandleBar", Vector3.new(2.5, 0.2, 0.2), cf * CFrame.new(0, 1.65, 2.0), Color3.fromRGB(200, 40, 36), Enum.Material.SmoothPlastic)
	for _, sx in { -1.0, 1.0 } do
		part(m, "HandlePost", Vector3.new(0.1, 0.6, 0.1), cf * CFrame.new(sx, 1.4, 1.85), wire, Enum.Material.Metal)
		for _, sz in { -1.8, 1.4 } do
			part(m, "Leg", Vector3.new(0.1, 1.2, 0.1), cf * CFrame.new(sx, -0.55, sz), wire, Enum.Material.Metal)
			part(m, "Castor", Vector3.new(0.45, 0.45, 0.45), cf * CFrame.new(sx, -1.55, sz), Color3.fromRGB(30, 30, 32), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
		end
	end
	return prop("Shopping cart", base, m, 0.35, 0.25)
end

-- a flat-pack box (heavy for its size). 5 x 0.8 x 2.6
function PropBuilders.flatpack(cf: CFrame): Model
	local m = Instance.new("Model")
	local b = part(m, "Box", Vector3.new(5, 0.8, 2.6), cf, Color3.fromRGB(178, 144, 102), Enum.Material.Fabric)
	part(m, "Tape", Vector3.new(5.04, 0.82, 0.3), cf, Color3.fromRGB(200, 170, 120), Enum.Material.SmoothPlastic)
	part(m, "Label", Vector3.new(1.2, 0.84, 0.8), cf * CFrame.new(1.6, 0, 0.6), Color3.fromRGB(236, 236, 232), Enum.Material.SmoothPlastic)
	return prop("Flat-pack box", b, m, 0.9)
end

-- a big shopping bag (yellow, dark straps). 2.2 x 2.4 x 1.2
function PropBuilders.shoppingbag(cf: CFrame): Model
	local m = Instance.new("Model")
	local bag = part(m, "Bag", Vector3.new(2.2, 1.7, 1.2), cf * CFrame.new(0, -0.35, 0), Color3.fromRGB(236, 196, 40), Enum.Material.Fabric)
	for _, sx in { -0.6, 0.6 } do
		part(m, "Strap", Vector3.new(0.18, 0.9, 0.12), cf * CFrame.new(sx, 0.75, 0), Color3.fromRGB(40, 40, 44), Enum.Material.Fabric)
	end
	return prop("Shopping bag", bag, m, 0.12)
end

-- office chair: seat, back, the gas column, a star base on castors. 2.4 x 4 x 2.4
function PropBuilders.officechair(cf: CFrame): Model
	local m = Instance.new("Model")
	local black = Color3.fromRGB(34, 34, 38)
	local seat = part(m, "Seat", Vector3.new(2, 0.35, 2), cf * CFrame.new(0, -0.2, 0), black, Enum.Material.Fabric)
	part(m, "Back", Vector3.new(1.9, 2.0, 0.3), cf * CFrame.new(0, 1.0, 0.95), black, Enum.Material.Fabric)
	part(m, "Column", Vector3.new(0.3, 1.3, 0.3), cf * CFrame.new(0, -1.0, 0), Color3.fromRGB(150, 152, 158), Enum.Material.Metal)
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2
		part(m, "StarLeg", Vector3.new(0.2, 0.15, 1.1), cf * CFrame.new(0, -1.6, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -0.55), black, Enum.Material.SmoothPlastic)
		part(m, "Castor", Vector3.new(0.3, 0.3, 0.3), cf * CFrame.new(0, -1.82, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -1.05), black, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
	end
	return prop("Office chair", seat, m, 0.45)
end

-- floor lamp: a heavy base, a pole, a shade with a light in it. 1.6 x 6 x 1.6
function PropBuilders.floorlamp(cf: CFrame): Model
	local m = Instance.new("Model")
	local base = part(m, "Base", Vector3.new(0.25, 1.5, 1.5), cf * CFrame.new(0, -2.88, 0) * CYL_Y, Color3.fromRGB(40, 40, 44), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Pole", Vector3.new(0.15, 4.6, 0.15), cf * CFrame.new(0, -0.45, 0), Color3.fromRGB(170, 172, 178), Enum.Material.Metal)
	local shade = part(m, "Shade", Vector3.new(1.2, 1.4, 1.4), cf * CFrame.new(0, 2.3, 0) * CYL_Y, Color3.fromRGB(236, 228, 208), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 170)
	light.Range = 14
	light.Brightness = 1.2
	light.Parent = shade
	return prop("Floor lamp", base, m, 0.9)
end

-- bunk bed: two beds on four posts, a ladder. 4.4 x 7 x 7.6
function PropBuilders.bunkbed(cf: CFrame): Model
	local m = Instance.new("Model")
	local wood = Color3.fromRGB(196, 160, 112)
	local low = part(m, "LowerFrame", Vector3.new(4.2, 0.4, 7.4), cf * CFrame.new(0, -2.4, 0), wood, Enum.Material.WoodPlanks)
	part(m, "LowerMattress", Vector3.new(3.9, 0.6, 7.0), cf * CFrame.new(0, -1.9, 0), Color3.fromRGB(80, 120, 190), Enum.Material.Fabric)
	part(m, "UpperFrame", Vector3.new(4.2, 0.4, 7.4), cf * CFrame.new(0, 1.0, 0), wood, Enum.Material.WoodPlanks)
	part(m, "UpperMattress", Vector3.new(3.9, 0.6, 7.0), cf * CFrame.new(0, 1.5, 0), Color3.fromRGB(200, 80, 80), Enum.Material.Fabric)
	for _, sx in { -2.05, 2.05 } do
		for _, sz in { -3.65, 3.65 } do
			part(m, "Post", Vector3.new(0.3, 7, 0.3), cf * CFrame.new(sx, 0, sz), wood, Enum.Material.Wood)
		end
	end
	for _, sz in { -3.65, 3.65 } do
		part(m, "GuardRail", Vector3.new(4.1, 0.25, 0.2), cf * CFrame.new(0, 2.7, sz), wood, Enum.Material.Wood)
	end
	for i = 0, 3 do
		part(m, "Rung", Vector3.new(0.2, 0.15, 1.2), cf * CFrame.new(2.15, -2.0 + i * 0.95, 2.6), wood, Enum.Material.Wood)
	end
	return prop("Bunk bed", low, m, 0.35, 0.8)
end

-- bar stool. 1.4 x 2.6 x 1.4
function PropBuilders.stool(cf: CFrame): Model
	local m = Instance.new("Model")
	local seat = part(m, "Seat", Vector3.new(0.25, 1.4, 1.4), cf * CFrame.new(0, 1.15, 0) * CYL_Y, Color3.fromRGB(150, 104, 62), Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2 + math.pi / 4
		part(m, "Leg", Vector3.new(0.14, 2.4, 0.14), cf * CFrame.Angles(0, a, 0) * CFrame.new(0, -0.1, -0.45) * CFrame.Angles(math.rad(-6), 0, 0), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
	end
	part(m, "FootRing", Vector3.new(0.1, 1.2, 1.2), cf * CFrame.new(0, -0.5, 0) * CYL_Y, Color3.fromRGB(40, 40, 44), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	return prop("Stool", seat, m, 0.5)
end

-- a plate of meatballs with sauce and a spoon of lingonberries. 1.6 x 0.6 x 1.6
function PropBuilders.meatballs(cf: CFrame): Model
	local m = Instance.new("Model")
	local plate = part(m, "Plate", Vector3.new(0.1, 1.6, 1.6), cf * CFrame.new(0, -0.25, 0) * CYL_Y, Color3.fromRGB(244, 244, 240), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "Sauce", Vector3.new(0.04, 1.1, 1.1), cf * CFrame.new(0, -0.18, 0) * CYL_Y, Color3.fromRGB(150, 100, 60), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	for k = 0, 6 do
		local a = k / 7 * math.pi * 2
		local r = k == 0 and 0 or 0.36
		part(m, "Meatball", Vector3.new(0.34, 0.34, 0.34), cf * CFrame.new(math.cos(a) * r, -0.02, math.sin(a) * r), Color3.fromRGB(110, 66, 40), Enum.Material.Sand, { Shape = Enum.PartType.Ball })
	end
	part(m, "Lingonberries", Vector3.new(0.3, 0.12, 0.3), cf * CFrame.new(0.55, -0.12, -0.4), Color3.fromRGB(170, 20, 36), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
	return prop("Meatballs", plate, m, 0.4)
end

-- cushion (soft, light). 1.8 x 0.6 x 1.8
function PropBuilders.cushion(cf: CFrame): Model
	local m = Instance.new("Model")
	local colors = { Color3.fromRGB(200, 70, 60), Color3.fromRGB(60, 110, 170), Color3.fromRGB(230, 200, 80), Color3.fromRGB(90, 150, 100) }
	local c = colors[math.random(1, #colors)]
	local body = part(m, "Cushion", Vector3.new(1.8, 0.55, 1.8), cf, c, Enum.Material.Fabric)
	part(m, "Seam", Vector3.new(1.84, 0.08, 1.84), cf, c:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Fabric)
	return prop("Cushion", body, m, 0.08, 0.9)
end

-- teddy bear. 1.6 x 2.2 x 1.2
function PropBuilders.teddy(cf: CFrame): Model
	local m = Instance.new("Model")
	local fur = Color3.fromRGB(160, 110, 64)
	local light = Color3.fromRGB(214, 176, 130)
	local body = part(m, "Body", Vector3.new(1.2, 1.2, 1.2), cf * CFrame.new(0, -0.35, 0), fur, Enum.Material.Fabric, { Shape = Enum.PartType.Ball })
	local head = cf * CFrame.new(0, 0.55, 0)
	part(m, "Head", Vector3.new(0.9, 0.9, 0.9), head, fur, Enum.Material.Fabric, { Shape = Enum.PartType.Ball })
	part(m, "Snout", Vector3.new(0.4, 0.4, 0.4), head * CFrame.new(0, -0.1, -0.38), light, Enum.Material.Fabric, { Shape = Enum.PartType.Ball })
	part(m, "Nose", Vector3.new(0.14, 0.14, 0.14), head * CFrame.new(0, -0.02, -0.57), Color3.fromRGB(30, 22, 18), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
	for _, sx in { -1, 1 } do
		part(m, "Ear", Vector3.new(0.34, 0.34, 0.34), head * CFrame.new(sx * 0.36, 0.36, 0), fur, Enum.Material.Fabric, { Shape = Enum.PartType.Ball })
		part(m, "Eye", Vector3.new(0.1, 0.1, 0.1), head * CFrame.new(sx * 0.17, 0.12, -0.42), Color3.fromRGB(20, 18, 16), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
		part(m, "Arm", Vector3.new(0.38, 0.38, 0.38), cf * CFrame.new(sx * 0.62, -0.15, -0.1), fur, Enum.Material.Fabric, { Shape = Enum.PartType.Ball })
		part(m, "Leg", Vector3.new(0.45, 0.45, 0.45), cf * CFrame.new(sx * 0.35, -0.85, -0.25), fur, Enum.Material.Fabric, { Shape = Enum.PartType.Ball })
	end
	part(m, "Belly", Vector3.new(0.7, 0.7, 0.7), cf * CFrame.new(0, -0.38, -0.3), light, Enum.Material.Fabric, { Shape = Enum.PartType.Ball })
	return prop("Teddy bear", body, m, 0.12, 0.9)
end

-- deck chair (a lounger): frame, a sloped back, a cushion. 2.4 x 2.6 x 6
function PropBuilders.deckchair(cf: CFrame): Model
	-- (v2.0 fix) the legs stand under the seat's frame (they used to stick out under the raised backrest, in the
	-- air); two struts hold the backrest up
	local m = Instance.new("Model")
	local wood = Color3.fromRGB(190, 150, 100)
	local dark = Color3.fromRGB(150, 112, 70)
	local seat = part(m, "Seat", Vector3.new(2.2, 0.25, 3.8), cf * CFrame.new(0, -0.45, 0.9), wood, Enum.Material.WoodPlanks)
	part(m, "BackRest", Vector3.new(2.2, 0.25, 2.4), cf * CFrame.new(0, 0.2, -1.95) * CFrame.Angles(math.rad(35), 0, 0), wood, Enum.Material.WoodPlanks)
	part(m, "Pad", Vector3.new(2.0, 0.2, 3.6), cf * CFrame.new(0, -0.24, 0.9), Color3.fromRGB(40, 110, 170), Enum.Material.Fabric)
	part(m, "BackPad", Vector3.new(2.0, 0.18, 2.2), cf * CFrame.new(0, 0.38, -1.88) * CFrame.Angles(math.rad(35), 0, 0), Color3.fromRGB(40, 110, 170), Enum.Material.Fabric)
	for _, sx in { -1, 1 } do
		-- the side rail of the frame, the legs at its ends
		part(m, "Rail", Vector3.new(0.16, 0.3, 3.9), cf * CFrame.new(sx * 1.08, -0.55, 0.9), dark, Enum.Material.Wood)
		for _, sz in { -0.85, 2.65 } do
			part(m, "Leg", Vector3.new(0.2, 0.78, 0.2), cf * CFrame.new(sx * 0.98, -0.91, sz), dark, Enum.Material.Wood)
		end
		-- the strut from the frame up under the backrest
		local a = (cf * CFrame.new(sx * 0.9, -0.62, -0.95)).Position
		local b = (cf * CFrame.new(sx * 0.9, 0.3, -2.35)).Position
		part(m, "Strut", Vector3.new(0.14, 0.14, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b, cf.UpVector), dark, Enum.Material.Wood)
	end
	return prop("Deck chair", seat, m, 0.4)
end

-- life buoy: a red and white ring. 3 x 0.7 x 3
function PropBuilders.lifebuoy(cf: CFrame): Model
	local m = Instance.new("Model")
	local first = ring(m, "Buoy", cf, 1.15, 0.65, 8, { Color3.fromRGB(220, 40, 34), Color3.fromRGB(244, 244, 240) }, Enum.Material.SmoothPlastic)
	return prop("Life buoy", first, m, 0.1)
end

-- crowbar: a steel bar with a hooked claw end (a blunt weapon). Forward = -Z.
function PropBuilders.crowbar(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Crowbar"
	local steel = Color3.fromRGB(70, 74, 82)
	local red = Color3.fromRGB(170, 30, 26)
	local handle = part(m, "Handle", Vector3.new(1.0, 0.18, 0.18), cf * CFrame.new(0, 0, 1.1) * CYL_Z, red, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(m, "Bar", Vector3.new(2.6, 0.15, 0.15), cf * CFrame.new(0, 0, -0.6) * CYL_Z, steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "CrowbarHook", Vector3.new(0.16, 0.16, 0.7), cf * CFrame.new(0, 0.22, -1.95) * CFrame.Angles(math.rad(45), 0, 0), steel, Enum.Material.Metal)
	part(m, "Claw", Vector3.new(0.22, 0.08, 0.35), cf * CFrame.new(0, 0.48, -2.15) * CFrame.Angles(math.rad(80), 0, 0), steel, Enum.Material.Metal)
	gripAttachment(handle, cf * CFrame.new(0, 0, 1.15))
	setDensity(m, 2.2, 0.5, 0.2)
	m.PrimaryPart = handle
	weldAll(m, handle)
	m:SetAttribute("Item", "crowbar")
	return m
end

-- chainsaw: the motor body, a handle on top, the guide bar with its chain (cuts limbs off). Forward = -Z.
function PropBuilders.chainsaw(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Chainsaw"
	local orange = Color3.fromRGB(230, 110, 30)
	local dark = Color3.fromRGB(36, 36, 40)
	local grip = part(m, "RearHandle", Vector3.new(0.3, 0.6, 0.9), cf * CFrame.new(0, -0.1, 0.95), dark, Enum.Material.SmoothPlastic)
	part(m, "Motor", Vector3.new(0.9, 1.0, 1.5), cf * CFrame.new(0, 0, 0), orange, Enum.Material.SmoothPlastic)
	part(m, "TopHandle", Vector3.new(0.2, 0.2, 1.1), cf * CFrame.new(0, 0.7, 0.1), dark, Enum.Material.SmoothPlastic)
	part(m, "Guard", Vector3.new(0.95, 0.5, 0.12), cf * CFrame.new(0, 0.45, -0.75), dark, Enum.Material.SmoothPlastic)
	part(m, "Blade", Vector3.new(0.08, 0.5, 2.6), cf * CFrame.new(0, -0.1, -2.05), Color3.fromRGB(176, 180, 188), Enum.Material.Metal)
	part(m, "Chain", Vector3.new(0.1, 0.56, 2.66), cf * CFrame.new(0, -0.1, -2.05), Color3.fromRGB(60, 60, 64), Enum.Material.DiamondPlate)
	gripAttachment(grip, cf * CFrame.new(0, -0.15, 1.0))
	setDensity(m, 1.2, 0.5, 0.1)
	m.PrimaryPart = grip
	weldAll(m, grip)
	m:SetAttribute("Item", "chainsaw")
	return m
end

------------------------------------------------------------------------
-- (v2.1) The BLACK LEDGER: a black leather notebook with a silver sigil. Whoever writes a name in it while picturing the
-- face (LedgerService) ... F opens it. Pocketed it is invisible (LedgerService).
------------------------------------------------------------------------
local okLeatherMat, leatherMatValue = pcall(function()
	return Enum.Material.Leather
end)
local LEATHER_MAT: Enum.Material = okLeatherMat and leatherMatValue or Enum.Material.Fabric

function PropBuilders.ledger(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Black Ledger"
	local W, L, T = 1.32, 1.84, 0.44 -- width (x), length (z), thickness (y); the spine is on the -x side
	local leather = Color3.fromRGB(13, 12, 16)
	local leather2 = Color3.fromRGB(22, 20, 26)
	local silver = Color3.fromRGB(124, 82, 48) -- (leather brown, light)
	local dark = Color3.fromRGB(62, 38, 22) -- (leather brown, dark)
	local crimson = Color3.fromRGB(96, 60, 34) -- (leather brown)
	local cream = Color3.fromRGB(236, 227, 204)
	local topY = T / 2 + 0.035 -- the surface of the front cover
	local function P(name: string, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material, props: { [string]: any }?): Part
		return part(m, name, size, cf * off, color, mat, props)
	end

	-- covers: soft black leather, the front one a touch lighter so the embossing reads
	local cover = P("Cover", Vector3.new(W, 0.07, L), CFrame.new(0, -T / 2 + 0.035, 0), leather, Enum.Material.Fabric)
	P("FrontCover", Vector3.new(W, 0.07, L), CFrame.new(0, T / 2 - 0.035, 0), leather2, Enum.Material.Fabric)
	-- rounded spine with four raised bands
	P("Spine", Vector3.new(L + 0.02, T + 0.03, T + 0.03), CFrame.new(-W / 2 + 0.01, 0, 0) * CFrame.Angles(0, math.rad(90), 0), leather, Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	for _, z in { -0.66, -0.22, 0.22, 0.66 } do
		P("SpineBand", Vector3.new(0.05, T + 0.07, T + 0.07), CFrame.new(-W / 2 + 0.01, 0, z) * CFrame.Angles(0, math.rad(90), 0), dark, LEATHER_MAT, { Shape = Enum.PartType.Cylinder, Reflectance = 0.03 })
	end
	-- the page block, with its blood-red gilded edges (thin lines on the fore-edge and the foot)
	P("Pages", Vector3.new(W - 0.12, T - 0.14, L - 0.1), CFrame.new(0.04, 0, 0), cream, Enum.Material.SmoothPlastic)
	for i = 0, 6 do
		local y = -T / 2 + 0.1 + i * ((T - 0.2) / 6)
		P("EdgeA", Vector3.new(0.012, 0.014, L - 0.16), CFrame.new(W / 2 - 0.075, y, 0), (i % 2 == 0) and crimson or Color3.fromRGB(70, 44, 26), LEATHER_MAT, { Reflectance = 0.03 })
		P("EdgeB", Vector3.new(W - 0.2, 0.014, 0.012), CFrame.new(0.03, y, L / 2 - 0.05), (i % 2 == 0) and crimson or Color3.fromRGB(70, 44, 26), LEATHER_MAT, { Reflectance = 0.03 })
	end

	-- embossed frame on the front cover
	local fy = topY + 0.004
	for _, z in { -L / 2 + 0.13, L / 2 - 0.13 } do
		P("FrameLine", Vector3.new(W - 0.34, 0.012, 0.025), CFrame.new(0.06, fy, z), dark, LEATHER_MAT, { Reflectance = 0.03 })
	end
	for _, x in { -W / 2 + 0.2, W / 2 - 0.1 } do
		P("FrameLine", Vector3.new(0.025, 0.012, L - 0.26), CFrame.new(x, fy, 0), dark, LEATHER_MAT, { Reflectance = 0.03 })
	end
	-- the sigil: a silver ring, a black field, an eye and twelve tick marks
	local sx = 0.05
	P("SigilRing", Vector3.new(0.02, 0.78, 0.78), CFrame.new(sx, fy + 0.004, -0.1) * CFrame.Angles(0, 0, math.rad(90)), silver, LEATHER_MAT, { Shape = Enum.PartType.Cylinder, Reflectance = 0.03 })
	P("SigilField", Vector3.new(0.024, 0.64, 0.64), CFrame.new(sx, fy + 0.006, -0.1) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(8, 8, 11), Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder })
	for i = 0, 11 do
		local a = i * math.pi / 6
		P("Tick", Vector3.new(0.03, 0.016, (i % 3 == 0) and 0.1 or 0.06), CFrame.new(sx + math.cos(a) * 0.3, fy + 0.012, -0.1 + math.sin(a) * 0.3) * CFrame.Angles(0, -a + math.rad(90), 0), silver, LEATHER_MAT, { Reflectance = 0.03 })
	end
	local eye = P("Eye", Vector3.new(0.42, 0.014, 0.17), CFrame.new(sx, fy + 0.014, -0.1), Color3.fromRGB(118, 78, 46), LEATHER_MAT)
	local almond = Instance.new("SpecialMesh") -- (a flat ellipsoid: an almond-shaped eye)
	almond.MeshType = Enum.MeshType.Sphere
	almond.Parent = eye
	P("Pupil", Vector3.new(0.14, 0.016, 0.14), CFrame.new(sx, fy + 0.02, -0.1) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(6, 4, 8), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	-- name plate with five little runes
	P("Plate", Vector3.new(0.7, 0.014, 0.2), CFrame.new(sx, fy + 0.002, L / 2 - 0.34), dark, LEATHER_MAT, { Reflectance = 0.03 })
	for i = -2, 2 do
		P("Rune", Vector3.new(0.05, 0.016, 0.08), CFrame.new(sx + i * 0.12, fy + 0.012, L / 2 - 0.34) * CFrame.Angles(0, math.rad(i * 9), 0), Color3.fromRGB(124, 82, 48), LEATHER_MAT)
	end
	-- corner guards (two bars and a rivet each)
	for _, cx in { -1, 1 } do
		for _, cz in { -1, 1 } do
			local x, z = cx * (W / 2 - 0.03), cz * (L / 2 - 0.03)
			P("GuardA", Vector3.new(0.3, 0.02, 0.055), CFrame.new(x - cx * 0.12, fy + 0.002, z), silver, LEATHER_MAT, { Reflectance = 0.03 })
			P("GuardB", Vector3.new(0.055, 0.02, 0.3), CFrame.new(x, fy + 0.002, z - cz * 0.12), silver, LEATHER_MAT, { Reflectance = 0.03 })
			P("Rivet", Vector3.new(0.02, 0.05, 0.05), CFrame.new(x - cx * 0.03, fy + 0.012, z - cz * 0.03) * CFrame.Angles(0, 0, math.rad(90)), dark, LEATHER_MAT, { Shape = Enum.PartType.Cylinder })
		end
	end

	-- the elastic band around the book (it runs over the top, the two ends and the back), with the pen tucked under it
	local bx = 0.42
	P("BandTop", Vector3.new(0.07, 0.012, L + 0.02), CFrame.new(bx, topY + 0.006, 0), Color3.fromRGB(8, 8, 10), Enum.Material.Fabric)
	P("BandBottom", Vector3.new(0.07, 0.012, L + 0.02), CFrame.new(bx, -T / 2 - 0.006, 0), Color3.fromRGB(8, 8, 10), Enum.Material.Fabric)
	for _, z in { -L / 2 - 0.006, L / 2 + 0.006 } do
		P("BandEnd", Vector3.new(0.07, T + 0.05, 0.012), CFrame.new(bx, 0, z), Color3.fromRGB(8, 8, 10), Enum.Material.Fabric)
	end
	local penY = topY + 0.012 + 0.04
	P("Pen", Vector3.new(1.2, 0.075, 0.075), CFrame.new(bx, penY, 0.02) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(14, 14, 18), LEATHER_MAT, { Shape = Enum.PartType.Cylinder, Reflectance = 0.03 })
	P("PenRing", Vector3.new(0.07, 0.082, 0.082), CFrame.new(bx, penY, 0.4) * CFrame.Angles(0, math.rad(90), 0), silver, LEATHER_MAT, { Shape = Enum.PartType.Cylinder, Reflectance = 0.03 })
	P("PenGem", Vector3.new(0.07, 0.07, 0.07), CFrame.new(bx, penY, -0.62), Color3.fromRGB(150, 110, 44), Enum.Material.Metal, { Shape = Enum.PartType.Ball })
	P("PenTip", Vector3.new(0.14, 0.04, 0.04), CFrame.new(bx, penY, 0.64) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(150, 110, 44), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Reflectance = 0.03 })
	-- a wax seal where the band crosses the cover
	P("Seal", Vector3.new(0.035, 0.24, 0.24), CFrame.new(bx, topY + 0.03, -0.62) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(84, 52, 30), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder, Reflectance = 0.03 })
	P("SealRing", Vector3.new(0.012, 0.15, 0.15), CFrame.new(bx, topY + 0.052, -0.62) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(58, 36, 20), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	-- a crimson ribbon bookmark hanging out of the foot, ending in a small silver charm
	P("Ribbon1", Vector3.new(0.09, 0.012, 0.38), CFrame.new(0.2, -0.02, L / 2 + 0.12) * CFrame.Angles(math.rad(-8), 0, 0), crimson, Enum.Material.Fabric)
	P("Ribbon2", Vector3.new(0.09, 0.012, 0.3), CFrame.new(0.2, -0.1, L / 2 + 0.4) * CFrame.Angles(math.rad(-26), 0, 0), crimson, Enum.Material.Fabric)
	P("Charm", Vector3.new(0.1, 0.1, 0.1), CFrame.new(0.2, -0.22, L / 2 + 0.58) * CFrame.Angles(math.rad(45), math.rad(45), 0), Color3.fromRGB(150, 110, 44), Enum.Material.Metal, { Reflectance = 0.03 })

	gripAttachment(cover, cf)
	setDensity(m, 0.3, 0.7, 0.05)
	m.PrimaryPart = cover
	weldAll(m, cover)

	-- (v2.1) the cover really OPENS: the front cover and everything on it hang on a hinge along the spine (LedgerService turns it)
	local FRONT = {
		FrontCover = true, FrameLine = true, SigilRing = true, SigilField = true, Tick = true, Eye = true, Pupil = true, Plate = true, Rune = true,
		GuardA = true, GuardB = true, Rivet = true, BandTop = true, Pen = true, PenRing = true, PenGem = true, PenTip = true, Seal = true, SealRing = true,
	}
	local frontRoot = m:FindFirstChild("FrontCover") :: BasePart
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") and FRONT[d.Name] then
			for _, w in d:GetChildren() do
				if w:IsA("WeldConstraint") then
					w:Destroy()
				end
			end
			if d ~= frontRoot then
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = frontRoot, d
				w.Parent = d
			end
			if d.Name == "Pen" or d.Name == "PenRing" or d.Name == "PenGem" or d.Name == "PenTip" then
				d:SetAttribute("LedgerPen", true) -- (hidden while somebody writes: the pen is in his hand)
			end
		end
	end
	local hingeAt = cf * CFrame.new(-W / 2 + 0.02, T / 2 - 0.035, 0)
	local hinge = Instance.new("Weld")
	hinge.Name = "Hinge"
	hinge.Part0, hinge.Part1 = cover, frontRoot
	hinge.C0 = cover.CFrame:ToObjectSpace(hingeAt)
	hinge.C1 = frontRoot.CFrame:ToObjectSpace(hingeAt)
	hinge:SetAttribute("ClosedC1", hinge.C1)
	hinge.Parent = frontRoot
	m:SetAttribute("Item", "ledger")
	return m
end

-- (v2.1) the SANDEVISTAN: a spine implant (six black vertebra plates with chrome clamps and green lights) on a carrier plate with cables.
-- F with it in the hand, aimed at somebody close: the implant (the same fitting as a prosthetic).
local SpineModel = require(script.Parent:WaitForChild("SpineModel"))
function PropBuilders.sandevistan(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Sandevistan"
	local black = Color3.fromRGB(14, 15, 18)
	local chrome = Color3.fromRGB(196, 202, 214)
	local carrier = part(m, "Carrier", Vector3.new(1.1, 0.1, 3.2), cf, black, Enum.Material.Metal)
	part(m, "CarrierRim", Vector3.new(1.18, 0.06, 3.28), cf * CFrame.new(0, -0.05, 0), Color3.fromRGB(34, 36, 42), Enum.Material.Metal)
	for _, x in { -0.46, 0.46 } do
		for _, z in { -1.5, 1.5 } do
			part(m, "Screw", Vector3.new(0.12, 0.05, 0.12), cf * CFrame.new(x, 0.07, z), chrome, Enum.Material.Metal, { Reflectance = 0.4 })
		end
	end
	-- the spine lies flat on the plate: its length along the plate, its plates standing up
	local flat = cf * CFrame.new(0, 0.12, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	for _, sp in SpineModel.Specs(1.12) do
		part(m, sp.name, sp.size, flat * sp.off, sp.color, sp.material, sp.refl and { Reflectance = sp.refl } or nil)
	end
	-- cables
	for i = 0, 3 do
		part(m, "Cable", Vector3.new(0.09, 0.09, 0.4), cf * CFrame.new(-0.7 - i * 0.12, 0.02 + i * 0.04, -1.2 + i * 0.25) * CFrame.Angles(0, math.rad(20 + i * 12), 0), black, Enum.Material.Rubber)
	end
	gripAttachment(carrier, cf)
	setDensity(m, 0.5, 0.7, 0.05)
	m.PrimaryPart = carrier
	weldAll(m, carrier)
	m:SetAttribute("Item", "sandevistan")
	return m
end

-- (v2.8) an IMPLANT CASE: a black case with a glass lid, the implant glowing inside on foam. RipperdocService writes the
-- implant on it (attributes CyId / CyTier) and its name on the lid. F aimed at somebody close: it goes into them.
function PropBuilders.implantcase(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Implant Case"
	local black = Color3.fromRGB(18, 19, 22)
	local chrome = Color3.fromRGB(190, 196, 206)
	local glow = Color3.fromRGB(70, 220, 255)
	local base = part(m, "Case", Vector3.new(1.4, 0.36, 0.9), cf, black, Enum.Material.Metal)
	part(m, "Foam", Vector3.new(1.26, 0.04, 0.76), cf * CFrame.new(0, 0.2, 0), Color3.fromRGB(34, 36, 40), Enum.Material.Fabric)
	for _, z in { -0.46, 0.46 } do
		part(m, "Trim", Vector3.new(1.42, 0.06, 0.04), cf * CFrame.new(0, 0.16, z), chrome, Enum.Material.Metal, { Reflectance = 0.3 })
	end
	for _, x in { -0.71, 0.71 } do
		part(m, "Trim", Vector3.new(0.04, 0.06, 0.94), cf * CFrame.new(x, 0.16, 0), chrome, Enum.Material.Metal, { Reflectance = 0.3 })
	end
	part(m, "Latch", Vector3.new(0.22, 0.12, 0.06), cf * CFrame.new(0, 0.04, -0.47), chrome, Enum.Material.Metal, { Reflectance = 0.3 })
	-- the implant inside: a small chrome module with a glowing core
	part(m, "Module", Vector3.new(0.6, 0.12, 0.34), cf * CFrame.new(0, 0.27, 0), chrome, Enum.Material.Metal, { Reflectance = 0.35 })
	local core = part(m, "Core", Vector3.new(0.3, 0.05, 0.14), cf * CFrame.new(0, 0.34, 0), glow, Enum.Material.Neon)
	core:SetAttribute("CaseGlow", true)
	for _, x in { -0.42, 0.42 } do
		part(m, "Pin", Vector3.new(0.12, 0.06, 0.06), cf * CFrame.new(x, 0.26, 0), Color3.fromRGB(200, 160, 60), Enum.Material.Metal)
	end
	local lid = part(m, "Lid", Vector3.new(1.36, 0.06, 0.86), cf * CFrame.new(0, 0.42, 0), Color3.fromRGB(140, 200, 230), Enum.Material.Glass, { Transparency = 0.6 })
	lid.Name = "Lid"
	gripAttachment(base, cf * CFrame.Angles(0, math.rad(90), 0))
	setDensity(m, 0.6, 0.6, 0.05)
	m.PrimaryPart = base
	weldAll(m, base)
	m:SetAttribute("Item", "implantcase")
	return m
end

-- (v2.8) a RIPPER KIT: a steel tray with a scalpel, a clamp, a little bone saw and an injector. F aimed at somebody close
-- (asleep): pick an implant, it comes out (into a case).
function PropBuilders.ripperkit(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Ripper Kit"
	local steel = Color3.fromRGB(176, 182, 190)
	local dark = Color3.fromRGB(30, 31, 35)
	local tray = part(m, "Tray", Vector3.new(1.5, 0.1, 0.9), cf, steel, Enum.Material.Metal, { Reflectance = 0.25 })
	for _, z in { -0.44, 0.44 } do
		part(m, "Rim", Vector3.new(1.5, 0.12, 0.04), cf * CFrame.new(0, 0.08, z), steel, Enum.Material.Metal, { Reflectance = 0.25 })
	end
	for _, x in { -0.74, 0.74 } do
		part(m, "Rim", Vector3.new(0.04, 0.12, 0.9), cf * CFrame.new(x, 0.08, 0), steel, Enum.Material.Metal, { Reflectance = 0.25 })
	end
	-- scalpel
	part(m, "ScalpelGrip", Vector3.new(0.6, 0.05, 0.07), cf * CFrame.new(-0.2, 0.08, -0.25), dark, Enum.Material.Metal)
	part(m, "ScalpelBlade", Vector3.new(0.22, 0.02, 0.08), cf * CFrame.new(0.21, 0.08, -0.25), steel, Enum.Material.Metal, { Reflectance = 0.5 })
	-- clamp
	for _, a in { -12, 12 } do
		part(m, "Clamp", Vector3.new(0.7, 0.04, 0.04), cf * CFrame.new(-0.1, 0.08, 0.02) * CFrame.Angles(0, math.rad(a), 0), steel, Enum.Material.Metal, { Reflectance = 0.4 })
	end
	part(m, "ClampRing", Vector3.new(0.04, 0.14, 0.14), cf * CFrame.new(-0.46, 0.08, 0.02) * CFrame.Angles(0, 0, math.rad(90)), steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	-- bone saw
	part(m, "SawBlade", Vector3.new(0.5, 0.02, 0.16), cf * CFrame.new(0.3, 0.07, 0.24), steel, Enum.Material.Metal, { Reflectance = 0.35 })
	part(m, "SawGrip", Vector3.new(0.24, 0.08, 0.12), cf * CFrame.new(-0.08, 0.09, 0.24), Color3.fromRGB(120, 30, 30), Enum.Material.Plastic)
	-- injector with a red glowing vial
	part(m, "Injector", Vector3.new(0.5, 0.1, 0.1), cf * CFrame.new(0.3, 0.1, -0.05), dark, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	part(m, "Vial", Vector3.new(0.18, 0.12, 0.12), cf * CFrame.new(0.38, 0.1, -0.05), Color3.fromRGB(255, 40, 60), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder })
	part(m, "Needle", Vector3.new(0.2, 0.02, 0.02), cf * CFrame.new(0.65, 0.1, -0.05), steel, Enum.Material.Metal)
	gripAttachment(tray, cf * CFrame.Angles(0, math.rad(90), 0))
	setDensity(m, 0.8, 0.6, 0.05)
	m.PrimaryPart = tray
	weldAll(m, tray)
	m:SetAttribute("Item", "ripperkit")
	return m
end

-- (v2.1) BODY ARMOR: the whole set laid out - a plate carrier with three magazine pouches, the helmet on top, two arm plates and two leg
-- plates around it. F (aimed at yourself): it takes Config.ArmorEquipTime s, like fitting a prosthetic (ArmorService / GearService).
function PropBuilders.armor(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Body Armor"
	local olive = Color3.fromRGB(62, 68, 58)
	local dark = Color3.fromRGB(40, 44, 38)
	local steel = Color3.fromRGB(86, 90, 98)
	local black = Color3.fromRGB(22, 22, 24)
	local body = part(m, "Vest", Vector3.new(1.7, 0.36, 2.1), cf, olive, Enum.Material.Fabric)
	part(m, "Cummerbund", Vector3.new(1.84, 0.3, 0.5), cf * CFrame.new(0, 0, 0.62), dark, Enum.Material.Fabric)
	part(m, "PlateFront", Vector3.new(1.0, 0.12, 1.2), cf * CFrame.new(0, 0.24, -0.05), steel, Enum.Material.Metal)
	for _, x in { -0.52, 0.52 } do
		part(m, "PlateFrame", Vector3.new(0.06, 0.14, 1.28), cf * CFrame.new(x, 0.25, -0.05), black, Enum.Material.Metal)
		part(m, "Strap", Vector3.new(0.24, 0.12, 2.3), cf * CFrame.new(x * 0.9, 0.2, -0.25), black, Enum.Material.Fabric)
		part(m, "ShoulderPad", Vector3.new(0.34, 0.16, 0.7), cf * CFrame.new(x * 0.95, 0.27, -1.0), dark, Enum.Material.Fabric)
	end
	for i = -1, 1 do
		part(m, "MagPouch", Vector3.new(0.4, 0.2, 0.34), cf * CFrame.new(i * 0.5, 0.24, 0.62), dark, Enum.Material.Fabric)
		part(m, "Webbing", Vector3.new(0.5, 0.05, 0.05), cf * CFrame.new(i * 0.5, 0.2, 0.34), black, Enum.Material.Fabric)
	end
	-- the helmet on top, with its brim, band and night-vision mount
	local helmetAt = cf * CFrame.new(0, 0.5, -0.1)
	part(m, "Helmet", Vector3.new(0.95, 0.6, 0.95), helmetAt, olive, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
	part(m, "HelmetBrim", Vector3.new(0.9, 0.08, 0.4), helmetAt * CFrame.new(0, -0.1, -0.5), dark, Enum.Material.SmoothPlastic)
	part(m, "HelmetBand", Vector3.new(0.98, 0.07, 0.98), helmetAt * CFrame.new(0, -0.08, 0), black, Enum.Material.SmoothPlastic)
	part(m, "NvgMount", Vector3.new(0.26, 0.14, 0.12), helmetAt * CFrame.new(0, 0.02, -0.52), black, Enum.Material.Metal)
	-- the arm plates and the leg plates beside it
	for _, x in { -1.25, 1.25 } do
		part(m, "ArmPlate", Vector3.new(0.5, 0.26, 1.0), cf * CFrame.new(x, 0.06, -0.5), olive, Enum.Material.Fabric)
		part(m, "ArmCap", Vector3.new(0.56, 0.1, 0.2), cf * CFrame.new(x, 0.14, -0.95), steel, Enum.Material.Metal)
		part(m, "LegPlate", Vector3.new(0.56, 0.26, 1.3), cf * CFrame.new(x, 0.06, 0.8), olive, Enum.Material.Fabric)
		part(m, "KneeCap", Vector3.new(0.5, 0.12, 0.3), cf * CFrame.new(x, 0.14, 0.55), steel, Enum.Material.Metal)
	end
	gripAttachment(body, cf)
	setDensity(m, 0.5, 0.7, 0.05)
	m.PrimaryPart = body
	weldAll(m, body)
	m:SetAttribute("Item", "armor")
	return m
end

-- (v2.1) an apple: food for Kuro, the shikigami of the Black Ledger
function PropBuilders.apple(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Apple"
	local body = part(m, "Body", Vector3.new(0.72, 0.68, 0.72), cf, Color3.fromRGB(196, 28, 34), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
	part(m, "Shine", Vector3.new(0.16, 0.12, 0.16), cf * CFrame.new(0.17, 0.2, -0.2), Color3.fromRGB(255, 190, 190), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball, Transparency = 0.35 })
	part(m, "Stem", Vector3.new(0.18, 0.05, 0.05), cf * CFrame.new(0, 0.36, 0) * CFrame.Angles(0, 0, math.rad(80)), Color3.fromRGB(88, 56, 28), Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	part(m, "Leaf", Vector3.new(0.22, 0.02, 0.12), cf * CFrame.new(0.13, 0.4, 0) * CFrame.Angles(0, 0, math.rad(-18)), Color3.fromRGB(60, 150, 50), Enum.Material.Grass)
	gripAttachment(body, cf)
	setDensity(m, 0.4, 0.6, 0.2)
	m.PrimaryPart = body
	weldAll(m, body)
	m:SetAttribute("Item", "apple")
	return m
end

------------------------------------------------------------------------
-- (v2.8) STILLWATER: the Pale Heir's sword (the STILLWATER quest). A katana to everything that cuts (Item = "katana"),
-- marked "Stillwater". A straight, long blade with a pale blue glowing edge and a dark groove, an iron guard ringed in
-- blue light, a black grip with bone-white diamonds, a blue stone in the pommel. Forward = -Z; the Handle is centred on cf.
------------------------------------------------------------------------
function PropBuilders.stillwater(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Stillwater"
	local iron = Color3.fromRGB(38, 42, 50)
	local bone = Color3.fromRGB(226, 220, 204)
	local glow = Color3.fromRGB(140, 210, 255)
	local handle = part(m, "Handle", Vector3.new(0.2, 0.24, 1.3), cf, Color3.fromRGB(16, 16, 20), Enum.Material.Fabric)
	for _, z in { -0.42, -0.14, 0.14, 0.42 } do
		part(m, "WrapDiamond", Vector3.new(0.22, 0.13, 0.13), cf * CFrame.new(0, 0, z) * CFrame.Angles(math.rad(45), 0, 0), bone, Enum.Material.Fabric)
	end
	part(m, "Pommel", Vector3.new(0.16, 0.28, 0.28), cf * CFrame.new(0, 0, 0.72) * CYL_Z, iron, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Reflectance = 0.2 })
	part(m, "PommelStone", Vector3.new(0.14, 0.14, 0.14), cf * CFrame.new(0, 0, 0.82), glow, Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	part(m, "Tsuba", Vector3.new(0.08, 0.64, 0.64), cf * CFrame.new(0, 0, -0.72) * CYL_Z, iron, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Reflectance = 0.15 })
	part(m, "TsubaRing", Vector3.new(0.06, 0.7, 0.7), cf * CFrame.new(0, 0, -0.72) * CYL_Z, glow, Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, Transparency = 0.35 })
	part(m, "Habaki", Vector3.new(0.1, 0.24, 0.2), cf * CFrame.new(0, 0, -0.86), Color3.fromRGB(200, 206, 216), Enum.Material.Metal, { Reflectance = 0.5 })
	local blade = part(m, "Blade", Vector3.new(0.05, 0.22, 3.7), cf * CFrame.new(0, 0.02, -2.8), Color3.fromRGB(206, 214, 226), Enum.Material.Metal, { Reflectance = 0.5 })
	part(m, "Groove", Vector3.new(0.06, 0.05, 2.9), cf * CFrame.new(0, 0.06, -2.55), Color3.fromRGB(70, 80, 98), Enum.Material.Metal, { Reflectance = 0.3 })
	part(m, "Edge", Vector3.new(0.055, 0.045, 3.6), cf * CFrame.new(0, -0.075, -2.82), glow, Enum.Material.Neon, { Transparency = 0.15 })
	part(m, "Kissaki", Vector3.new(0.05, 0.16, 0.32), cf * CFrame.new(0, 0.06, -4.72) * CFrame.Angles(math.rad(-28), 0, 0), Color3.fromRGB(226, 232, 242), Enum.Material.Metal, { Reflectance = 0.55 })
	blade:SetAttribute("Sharpness", 1)
	gripAttachment(handle, cf * CFrame.new(0, 0, 0.15))
	setDensity(m, 1.2, 0.5, 0.05)
	m.PrimaryPart = handle
	weldAll(m, handle)
	m:SetAttribute("Item", "katana")
	m:SetAttribute("Stillwater", true)
	m:SetAttribute("Skin", "stillwater") -- (weapon skins leave it alone)
	return m
end

-- (v2.8) its sheath: bone-white lacquer, dark iron bands and end cap, a thin blue-green seam of light, a dark red cord.
-- The body (Saya) is the PrimaryPart, centred on cf; the mouth is at +Z (2.05 from the centre), the tip at -Z.
-- Worn in a pocket at the hip; STILLWATER put into the SAME pocket slides into it (StillCutService).
function PropBuilders.sheath(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Stillwater Sheath"
	local iron = Color3.fromRGB(38, 42, 50)
	local saya = part(m, "Saya", Vector3.new(0.28, 0.36, 4.1), cf, Color3.fromRGB(232, 228, 216), Enum.Material.SmoothPlastic, { Reflectance = 0.12 })
	part(m, "Koiguchi", Vector3.new(0.32, 0.4, 0.22), cf * CFrame.new(0, 0, 1.96), iron, Enum.Material.Metal, { Reflectance = 0.15 })
	part(m, "Kojiri", Vector3.new(0.32, 0.4, 0.3), cf * CFrame.new(0, 0, -1.92), iron, Enum.Material.Metal, { Reflectance = 0.15 })
	for _, z in { 1.3, 0.2, -1.0 } do
		part(m, "Band", Vector3.new(0.31, 0.39, 0.12), cf * CFrame.new(0, 0, z), iron, Enum.Material.Metal, { Reflectance = 0.15 })
	end
	part(m, "Seam", Vector3.new(0.3, 0.035, 3.3), cf * CFrame.new(0, 0.06, -0.2), Color3.fromRGB(110, 220, 230), Enum.Material.Neon, { Transparency = 0.2 })
	part(m, "Kurikata", Vector3.new(0.1, 0.16, 0.3), cf * CFrame.new(0, -0.24, 1.45), iron, Enum.Material.Metal)
	part(m, "Sageo", Vector3.new(0.33, 0.41, 0.09), cf * CFrame.new(0, 0, 1.62), Color3.fromRGB(120, 24, 32), Enum.Material.Fabric)
	part(m, "SageoTail", Vector3.new(0.07, 0.3, 0.09), cf * CFrame.new(0.05, -0.3, 1.55) * CFrame.Angles(math.rad(14), 0, 0), Color3.fromRGB(120, 24, 32), Enum.Material.Fabric)
	gripAttachment(saya, cf * CFrame.new(0, 0, 0.9))
	setDensity(m, 0.6, 0.5, 0.05)
	m.PrimaryPart = saya
	weldAll(m, saya)
	m:SetAttribute("Item", "sheath")
	m:SetAttribute("Sheath", true)
	return m
end

------------------------------------------------------------------------
-- (v2.9) THE CYBERDECK: the video camera, a chip, and a computer.
------------------------------------------------------------------------

-- a VIDEO CAMERA: a blocky handheld with a lens, a red record light, a little screen and a mic. F films; stop and a
-- video chip pops out (CameraService).
function PropBuilders.camera(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Video Camera"
	local black = Color3.fromRGB(26, 27, 31)
	local dark = Color3.fromRGB(14, 14, 16)
	local steel = Color3.fromRGB(150, 154, 162)
	-- the body (forward = -Z, the lens points forward)
	local body = part(m, "Body", Vector3.new(1.0, 0.9, 1.5), cf, black, Enum.Material.SmoothPlastic)
	part(m, "Grip", Vector3.new(0.5, 0.8, 0.6), cf * CFrame.new(0, -0.7, 0.3), dark, Enum.Material.SmoothPlastic)
	-- the lens barrel
	part(m, "LensBarrel", Vector3.new(0.5, 0.66, 0.66), cf * CFrame.new(0, 0.05, -0.9) * CYL_Z, dark, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Reflectance = 0.1 })
	local glass = part(m, "Lens", Vector3.new(0.14, 0.46, 0.46), cf * CFrame.new(0, 0.05, -1.2) * CYL_Z, Color3.fromRGB(40, 60, 90), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Reflectance = 0.4, Transparency = 0.1 })
	glass.Name = "Lens"
	part(m, "Ring", Vector3.new(0.12, 0.64, 0.64), cf * CFrame.new(0, 0.05, -1.06) * CYL_Z, steel, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Reflectance = 0.3 })
	-- the flip-out screen on the left
	part(m, "Screen", Vector3.new(0.05, 0.55, 0.75), cf * CFrame.new(-0.55, 0.1, 0.1), Color3.fromRGB(90, 150, 170), Enum.Material.Neon, { Transparency = 0.2 })
	-- the record light (CameraService turns it on while filming)
	local led = part(m, "RecLight", Vector3.new(0.14, 0.14, 0.14), cf * CFrame.new(0.35, 0.4, -0.7), Color3.fromRGB(80, 20, 20), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	led.Name = "RecLight"
	-- the mic on top
	part(m, "Mic", Vector3.new(0.7, 0.18, 0.18), cf * CFrame.new(0, 0.55, 0.1) * CYL_Z, Color3.fromRGB(40, 42, 46), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, Reflectance = 0.15 })
	part(m, "Windscreen", Vector3.new(0.3, 0.3, 0.3), cf * CFrame.new(0, 0.55, -0.26), Color3.fromRGB(60, 62, 66), Enum.Material.Fabric, { Shape = Enum.PartType.Ball })
	part(m, "Battery", Vector3.new(0.76, 0.66, 0.24), cf * CFrame.new(0, -0.03, 0.83), dark, Enum.Material.Rubber)
	part(m, "TopHandle", Vector3.new(0.18, 0.14, 0.9), cf * CFrame.new(0.28, 0.68, 0.08), dark, Enum.Material.Metal)
	for _, z in { -0.3, 0.48 } do part(m, "HandleFoot", Vector3.new(0.18, 0.23, 0.14), cf * CFrame.new(0.28, 0.54, z), steel, Enum.Material.Metal) end
	for i = 1, 7 do
		part(m, "CoolingVent", Vector3.new(0.025, 0.28, 0.035), cf * CFrame.new(0.507, 0.12, -0.5 + i * 0.12), dark, Enum.Material.Metal)
		part(m, "FocusRidge", Vector3.new(0.025, 0.69, 0.69), cf * CFrame.new(0, 0.05, -0.76 - i * 0.045) * CYL_Z, black, Enum.Material.Rubber, { Shape = Enum.PartType.Cylinder })
	end
	part(m, "ScreenHinge", Vector3.new(0.1, 0.58, 0.1), cf * CFrame.new(-0.54, 0.1, -0.3), steel, Enum.Material.Metal)
	part(m, "ScreenBack", Vector3.new(0.06, 0.67, 0.87), cf * CFrame.new(-0.59, 0.1, 0.1), dark, Enum.Material.Metal)
	for _, z in { 0.1, 0.32, 0.54 } do part(m, "ControlKey", Vector3.new(0.08, 0.12, 0.12), cf * CFrame.new(0.54, -0.28, z), steel, Enum.Material.Rubber) end
	-- the chip slot the video pops out of (the muzzle for the pop)
	muzzleAt(body, cf * CFrame.new(0.55, -0.1, 0.4), "ChipSlot")
	gripAttachment(body, cf * CFrame.new(0, -0.5, 0.3))
	setDensity(m, 0.5, 0.6, 0.05)
	m.PrimaryPart = body
	weldAll(m, body)
	m:SetAttribute("Item", "camera")
	return m
end

-- a CHIP: a flat shard with gold contacts and a glowing core. Its colour / name is set by whoever makes it
-- (ChipService / CameraService). A blank one is grey.
function PropBuilders.package(cf: CFrame): Model
	local m = Instance.new("Model"); m.Name = "Delivery Package"
	local box = part(m, "Package", Vector3.new(1.8, 1.4, 1.4), cf, Color3.fromRGB(108, 91, 66), Enum.Material.SmoothPlastic)
	part(m, "Seal", Vector3.new(0.3, 0.02, 1.42), cf * CFrame.new(0, 0.71, 0), Color3.fromRGB(200, 193, 171), Enum.Material.SmoothPlastic)
	part(m, "Label", Vector3.new(0.6, 0.02, 0.6), cf * CFrame.new(0.5, 0.72, 0), Color3.fromRGB(225, 225, 220), Enum.Material.SmoothPlastic)
	gripAttachment(box, cf); m.PrimaryPart = box; weldAll(m, box); setDensity(m, 0.4, 0.6, 0.05)
	m:SetAttribute("Item", "package")
	return m
end

function PropBuilders.chip(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Chip"
	local shell = Color3.fromRGB(28, 30, 36)
	local gold = Color3.fromRGB(206, 170, 80)
	local base = part(m, "Shell", Vector3.new(0.9, 0.1, 1.1), cf, shell, Enum.Material.SmoothPlastic, { Reflectance = 0.05 })
	-- the notched tip
	part(m, "Tip", Vector3.new(0.5, 0.08, 0.2), cf * CFrame.new(0, 0.01, -0.62), shell, Enum.Material.SmoothPlastic)
	-- the gold contacts
	for i = -2, 2 do
		part(m, "Contact", Vector3.new(0.12, 0.02, 0.4), cf * CFrame.new(i * 0.16, 0.06, -0.4), gold, Enum.Material.Metal, { Reflectance = 0.3 })
	end
	-- the glowing core (ChipService colours it per chip)
	local core = part(m, "Core", Vector3.new(0.5, 0.06, 0.4), cf * CFrame.new(0, 0.06, 0.18), Color3.fromRGB(150, 150, 160), Enum.Material.Neon)
	core.Name = "Core"
	part(m, "Etch", Vector3.new(0.6, 0.02, 0.02), cf * CFrame.new(0, 0.07, 0.42), gold, Enum.Material.Metal)
	for _, x in { -0.32, 0.32 } do
		part(m, "Trace", Vector3.new(0.025, 0.016, 0.43), cf * CFrame.new(x, 0.065, 0.15), gold, Enum.Material.Metal)
		part(m, "RetainingScrew", Vector3.new(0.06, 0.02, 0.06), cf * CFrame.new(x, 0.065, 0.46), Color3.fromRGB(140, 140, 145), Enum.Material.Metal)
	end
	part(m, "DieFrame", Vector3.new(0.56, 0.025, 0.46), cf * CFrame.new(0, 0.055, 0.18), Color3.fromRGB(90, 92, 98), Enum.Material.Metal)
	gripAttachment(base, cf)
	setDensity(m, 0.4, 0.6, 0.05)
	m.PrimaryPart = base
	weldAll(m, base)
	m:ScaleTo(0.48)
	m:SetAttribute("Item", "chip")
	return m
end

-- a COMPUTER: a chunky terminal on a stand - a glowing screen, a keyboard, a chip reader slot. Set it down and the
-- prompt opens it (ComputerService).
function PropBuilders.computer(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Computer"
	local case = Color3.fromRGB(30, 32, 38)
	local dark = Color3.fromRGB(16, 17, 20)
	local cyan = Color3.fromRGB(200, 210, 215)
	-- the stand / base
	part(m, "Base", Vector3.new(2.2, 0.3, 1.4), cf * CFrame.new(0, -1.15, 0), dark, Enum.Material.Metal, { Reflectance = 0.1 })
	part(m, "Post", Vector3.new(0.4, 1.2, 0.4), cf * CFrame.new(0, -0.5, 0.3), dark, Enum.Material.Metal)
	-- the monitor
	local body = part(m, "Monitor", Vector3.new(3.4, 2.2, 0.5), cf * CFrame.new(0, 0.3, 0), case, Enum.Material.SmoothPlastic)
	local screen = part(m, "ScreenPart", Vector3.new(3.0, 1.8, 0.1), cf * CFrame.new(0, 0.3, -0.28), Color3.fromRGB(8, 8, 8), Enum.Material.SmoothPlastic)
	screen.Name = "ScreenPart"
	part(m, "Bezel", Vector3.new(3.2, 2.0, 0.3), cf * CFrame.new(0, 0.3, -0.12), dark, Enum.Material.Metal)
	-- the keyboard shelf
	part(m, "Shelf", Vector3.new(2.6, 0.12, 1.0), cf * CFrame.new(0, -0.95, -0.5), case, Enum.Material.SmoothPlastic)
	part(m, "Keys", Vector3.new(2.2, 0.08, 0.7), cf * CFrame.new(0, -0.88, -0.6), dark, Enum.Material.SmoothPlastic)
	-- the chip reader with a thin glowing slot
	part(m, "Reader", Vector3.new(0.9, 0.5, 0.3), cf * CFrame.new(1.2, -0.95, -0.2), dark, Enum.Material.Metal)
	part(m, "ReaderSlot", Vector3.new(0.7, 0.04, 0.05), cf * CFrame.new(1.2, -0.9, -0.36), cyan, Enum.Material.Neon)
	for row = 1, 3 do
		for col = 1, 11 do
			part(m, "Keycap", Vector3.new(0.15, 0.045, 0.13), cf * CFrame.new(-1.05 + col * 0.175, -0.815, -0.98 + row * 0.19), Color3.fromRGB(55, 55, 59), Enum.Material.Rubber)
		end
	end
	part(m, "Spacebar", Vector3.new(0.9, 0.045, 0.12), cf * CFrame.new(0, -0.815, -0.23), Color3.fromRGB(68, 68, 72), Enum.Material.Rubber)
	for i = 1, 9 do part(m, "Vent", Vector3.new(0.14, 0.42, 0.03), cf * CFrame.new(-1.25 + i * 0.25, 0.32, 0.265), dark, Enum.Material.Metal) end
	for _, x in { -1.54, 1.54 } do
		for _, y in { -0.6, 1.18 } do part(m, "BezelScrew", Vector3.new(0.06, 0.06, 0.025), cf * CFrame.new(x, y, -0.265), Color3.fromRGB(100, 100, 105), Enum.Material.Metal) end
	end
	local g = Instance.new("SurfaceGui")
	g.Name, g.Face, g.CanvasSize, g.LightInfluence = "TerminalDisplay", Enum.NormalId.Front, Vector2.new(600, 360), 0
	g.Parent = screen
	local label = Instance.new("TextLabel")
	label.Size, label.BackgroundColor3 = UDim2.fromScale(1, 1), Color3.fromRGB(5, 5, 5)
	label.TextColor3, label.Font, label.TextSize = Color3.fromRGB(220, 220, 220), Enum.Font.Code, 28
	label.Text = "N E T  /  T E R M I N A L\n________________________\n\nCHIPS   |   PROGRAM   |   SELL\n\n[ F ]  CONNECT"
	label.Parent = g
	gripAttachment(body, cf * CFrame.new(0, -0.6, 0.2))
	setDensity(m, 1.2, 0.8, 0.05)
	m.PrimaryPart = body
	weldAll(m, body)
	m:SetAttribute("Item", "computer")
	m:SetAttribute("Computer", true)
	return m
end

return PropBuilders
