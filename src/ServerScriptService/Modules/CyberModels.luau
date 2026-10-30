--!nonstrict
-- CyberModels (v2.8): what implants look like on a body. Every implant is a Folder "Cy_<key>" of small parts welded to
-- the body part it sits in (no mass, no collisions). Built at the body's size (attribute BodyScale).
--   R6 parts: front = -Z. Head 2x1x1 drawn as a 1.25 ball. Arms / legs 1x2x1 (shoulder / hip at the top).
-- Also the look of an implant in its CASE (PropBuilders.implantcase uses Mini).

local Cyberware = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Cyberware"))

local CyberModels = {}

local CHROME = Color3.fromRGB(190, 196, 206)
local STEEL = Color3.fromRGB(110, 114, 122)
local DARK = Color3.fromRGB(26, 27, 31)
local BLACK = Color3.fromRGB(14, 14, 16)
local RED = Color3.fromRGB(255, 40, 40)
local CYAN = Color3.fromRGB(70, 220, 255)
local M = Enum.Material

local YAXIS = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder (axis = X) turned to run along Y
local ZAXIS = CFrame.Angles(0, math.rad(90), 0) -- ... along Z (facing front / back)

type Ctx = { folder: Folder, host: BasePart, s: number }

-- (v2.8.1) less glow: only lenses, eyes, visors and power cores still shine; every other light strip, seam and stripe is
-- painted on (the colour stays, the neon goes)
local KEEP_NEON = { Lens = true, Pupil = true, Visor = true, Reactor = true, Eye = true, Core = true, PortCore = true, SpineEye = true }

local function add(c: Ctx, name: string, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?, refl: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size * c.s
	p.CFrame = c.host.CFrame * (CFrame.new(off.Position * c.s) * off.Rotation)
	p.Color = color
	if mat == M.Neon and not KEEP_NEON[name] then
		mat = M.SmoothPlastic
		p.Color = color:Lerp(Color3.new(0, 0, 0), 0.25)
	end
	p.Material = mat or M.Metal
	if shape then
		p.Shape = shape
	end
	p.Reflectance = refl or 0
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = c.host, p
	w.Parent = p
	p.Parent = c.folder
	return p
end

local function light(p: BasePart, color: Color3, range: number, brightness: number?)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1
	l.Shadows = false
	l.Parent = p
end

-- an ellipsoid (a Part with a sphere mesh: any proportions)
local function egg(c: Ctx, name: string, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material?, refl: number?): Part
	local p = add(c, name, size, off, color, mat, nil, refl)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

local function ctx(char: Model, partName: string, key: string): Ctx?
	local host = char:FindFirstChild(partName)
	if not host or not host:IsA("BasePart") then
		return nil
	end
	local f = Instance.new("Folder")
	f.Name = "Cy_" .. key
	f.Parent = host
	local s = char:GetAttribute("BodyScale")
	return { folder = f, host = host, s = typeof(s) == "number" and s or 1 }
end

------------------------------------------------------------------------
-- head
------------------------------------------------------------------------

local function optics(char: Model, key: string, tier: number)
	local c = ctx(char, "Head", key)
	if not c then
		return
	end
	-- a black visor band across the eyes, lens housings in it
	add(c, "Band", Vector3.new(1.06, 0.26, 0.2), CFrame.new(0, 0.1, -0.5), BLACK, M.Metal)
	add(c, "BandTrim", Vector3.new(1.08, 0.04, 0.22), CFrame.new(0, 0.245, -0.5), STEEL, M.Metal)
	local function lens(x: number, y: number, r: number)
		add(c, "Housing", Vector3.new(0.12, r + 0.08, r + 0.08), CFrame.new(x, y, -0.6) * ZAXIS, DARK, M.Metal, Enum.PartType.Cylinder)
		local l = add(c, "Lens", Vector3.new(0.05, r, r), CFrame.new(x, y, -0.66) * ZAXIS, RED, M.Neon, Enum.PartType.Cylinder)
		add(c, "Pupil", Vector3.new(0.02, r * 0.35, r * 0.35), CFrame.new(x, y, -0.69) * ZAXIS, Color3.fromRGB(255, 220, 200), M.Neon, Enum.PartType.Cylinder)
		return l
	end
	if tier == 1 then
		local l = lens(0.24, 0.1, 0.2)
		light(l, RED, 4, 0.8)
		add(c, "Cover", Vector3.new(0.2, 0.18, 0.12), CFrame.new(-0.24, 0.1, -0.6), STEEL, M.Metal)
	elseif tier == 2 then
		local l = lens(0.24, 0.1, 0.2)
		lens(-0.24, 0.1, 0.2)
		light(l, RED, 5, 1)
	else
		-- three small lenses stacked on the right, one big on the left, a sensor ridge on the temple
		local l = lens(0.26, 0.2, 0.12)
		lens(0.26, 0.05, 0.12)
		lens(0.26, -0.1, 0.12)
		lens(-0.22, 0.1, 0.22)
		add(c, "Ridge", Vector3.new(0.12, 0.5, 0.36), CFrame.new(0.6, 0.1, -0.25), DARK, M.Metal)
		add(c, "RidgeLed", Vector3.new(0.13, 0.32, 0.03), CFrame.new(0.6, 0.1, -0.45), RED, M.Neon)
		light(l, RED, 6, 1.2)
	end
end

local function cortex(char: Model, key: string, tier: number)
	local c = ctx(char, "Head", key)
	if not c then
		return
	end
	for _, x in { -1, 1 } do
		add(c, "Port", Vector3.new(0.1, 0.26, 0.26), CFrame.new(x * 0.6, 0.15, 0.05), CHROME, M.Metal, Enum.PartType.Cylinder, 0.3)
		add(c, "PortCore", Vector3.new(0.11, 0.12, 0.12), CFrame.new(x * 0.61, 0.15, 0.05), Color3.fromRGB(80, 255, 140), M.Neon, Enum.PartType.Cylinder)
		if tier >= 2 then
			add(c, "Plate", Vector3.new(0.06, 0.4, 0.22), CFrame.new(x * 0.6, 0.12, 0.3), DARK, M.Metal)
		end
	end
	if tier >= 3 then
		-- a data cable from the back of the head down into the neck
		add(c, "Jack", Vector3.new(0.22, 0.22, 0.1), CFrame.new(0, -0.15, 0.6), CHROME, M.Metal, nil, 0.3)
		add(c, "Cable", Vector3.new(0.08, 0.5, 0.08), CFrame.new(0, -0.45, 0.6) * CFrame.Angles(math.rad(-12), 0, 0), BLACK, M.Rubber)
	end
end

------------------------------------------------------------------------
-- torso
------------------------------------------------------------------------

local function keel(char: Model, key: string, tier: number)
	local c = ctx(char, "Torso", key)
	if not c then
		return
	end
	local low = char:FindFirstChild("SandevistanSpine", true) ~= nil -- (the Sandevistan takes the upper back)
	local top = low and -0.25 or 0.8
	local n = low and 3 or 6
	for i = 0, n - 1 do
		local y = top - i * 0.26
		add(c, "Vertebra", Vector3.new(0.12, 0.34, 0.34), CFrame.new(0, y, 0.56) * YAXIS, CHROME, M.Metal, Enum.PartType.Cylinder, 0.35)
		add(c, "Disc", Vector3.new(0.05, 0.26, 0.26), CFrame.new(0, y - 0.13, 0.55) * YAXIS, DARK, M.Metal, Enum.PartType.Cylinder)
		if tier >= 2 then
			for _, x in { -1, 1 } do
				add(c, "Fin", Vector3.new(0.2, 0.06, 0.12), CFrame.new(x * 0.2, y, 0.55) * CFrame.Angles(0, 0, math.rad(x * -20)), STEEL, M.Metal)
			end
		end
	end
	-- the gyroscope at the bottom
	local g = add(c, "Gyro", Vector3.new(0.1, 0.5, 0.5), CFrame.new(0, -0.85, 0.56) * ZAXIS, DARK, M.Metal, Enum.PartType.Cylinder)
	add(c, "GyroRing", Vector3.new(0.11, 0.3, 0.3), CFrame.new(0, -0.85, 0.58) * ZAXIS, Color3.fromRGB(80, 160, 255), M.Neon, Enum.PartType.Cylinder)
	if tier >= 3 then
		light(g, Color3.fromRGB(80, 160, 255), 4, 0.8)
	end
end

local function aegis(char: Model, key: string, tier: number)
	local c = ctx(char, "Torso", key)
	if not c then
		return
	end
	local blue = Color3.fromRGB(90, 190, 255)
	add(c, "Mount", Vector3.new(0.08, 0.78, 0.78), CFrame.new(0, 0.35, -0.53) * ZAXIS, DARK, M.Metal, Enum.PartType.Cylinder)
	add(c, "Rim", Vector3.new(0.1, 0.6, 0.6), CFrame.new(0, 0.35, -0.56) * ZAXIS, CHROME, M.Metal, Enum.PartType.Cylinder, 0.3)
	local core = add(c, "Core", Vector3.new(0.12, 0.36, 0.36), CFrame.new(0, 0.35, -0.57) * ZAXIS, blue, M.Neon, Enum.PartType.Cylinder)
	light(core, blue, 5 + tier, 1)
	-- six emitter studs round it
	for i = 0, 5 do
		local a = i * math.pi / 3
		add(c, "Emitter", Vector3.new(0.1, 0.1, 0.06), CFrame.new(math.cos(a) * 0.48, 0.35 + math.sin(a) * 0.48, -0.53), tier >= 2 and blue or STEEL, tier >= 2 and M.Neon or M.Metal)
	end
	if tier >= 3 then
		for _, x in { -1, 1 } do
			add(c, "Conduit", Vector3.new(0.5, 0.06, 0.05), CFrame.new(x * 0.62, 0.35, -0.52), blue, M.Neon)
		end
	end
end

local function sentry(char: Model, key: string, tier: number)
	local c = ctx(char, "Torso", key)
	if not c then
		return
	end
	for _, x in { -1, 1 } do
		add(c, "Node", Vector3.new(0.3, 0.2, 0.36), CFrame.new(x * 0.72, 1.08, 0.05), DARK, M.Metal)
		local eye = add(c, "Eye", Vector3.new(0.05, 0.1, 0.1), CFrame.new(x * 0.72, 1.1, -0.14) * ZAXIS, RED, M.Neon, Enum.PartType.Cylinder)
		if tier >= 2 then
			add(c, "Antenna", Vector3.new(0.03, 0.4, 0.03), CFrame.new(x * 0.8, 1.35, 0.15), STEEL, M.Metal)
		end
		if tier >= 3 and x > 0 then
			light(eye, RED, 3, 0.6)
		end
	end
	add(c, "Collar", Vector3.new(0.9, 0.12, 0.7), CFrame.new(0, 1.04, 0.05), BLACK, M.Metal)
end

local function skinLines(char: Model, key: string, color: Color3, transp: number)
	local c = ctx(char, "Torso", key)
	if not c then
		return
	end
	for i = 0, 2 do
		for _, x in { -1, 1 } do
			local p = add(c, "Seam", Vector3.new(0.03, 0.6, 0.03), CFrame.new(x * 1.0, 0.5 - i * 0.55, -0.3 + i * 0.25) * CFrame.Angles(0, 0, math.rad(x * 18)), color, M.Neon)
			p.Transparency = transp
		end
	end
	return c
end

local function ghostskin(char: Model, key: string, tier: number)
	-- (v2.8.2) light-bending skin: faint seams, pale glass refractor plates down the spine and on the shoulders, small
	-- emitter studs on the arms (more with every tier)
	local c = skinLines(char, key, Color3.fromRGB(170, 230, 255), 0.6)
	local glassC = Color3.fromRGB(190, 225, 240)
	if c then
		for i = 0, 3 do
			local g = add(c, "Refractor", Vector3.new(0.5 - i * 0.05, 0.3, 0.05), CFrame.new(0, 0.7 - i * 0.38, 0.52), glassC, M.Glass)
			g.Transparency = 0.35
			g.Reflectance = 0.4
		end
		for _, x in { -1, 1 } do
			local g = add(c, "Refractor", Vector3.new(0.6, 0.05, 0.5), CFrame.new(x * 0.6, 1.01, 0), glassC, M.Glass)
			g.Transparency = 0.35
			g.Reflectance = 0.4
		end
	end
	for _, arm in { "Left Arm", "Right Arm" } do
		local ca = ctx(char, arm, key)
		if ca then
			local sx = arm == "Left Arm" and -1 or 1
			for i = 1, 1 + tier do
				add(ca, "Emitter", Vector3.new(0.05, 0.14, 0.14), CFrame.new(sx * 0.51, 0.75 - i * 0.32, 0.15), Color3.fromRGB(60, 66, 74), M.Metal, Enum.PartType.Cylinder, 0.3)
			end
		end
	end
end

local function dermis(char: Model, key: string, tier: number)
	-- (v2.8.2) capacitors under the skin: a charge cell on each outer forearm with coil rings, contact plates on the
	-- knuckles, painted circuit lines, discharge prongs on the shoulders (tier 2+)
	local blue = Color3.fromRGB(90, 170, 255)
	for _, arm in { "Left Arm", "Right Arm" } do
		local c = ctx(char, arm, key)
		if c then
			local side = arm == "Left Arm" and -1 or 1
			add(c, "Circuit", Vector3.new(0.03, 1.6, 0.03), CFrame.new(side * 0.505, -0.1, 0.1), blue, M.Neon)
			add(c, "Circuit", Vector3.new(0.03, 0.03, 0.4), CFrame.new(side * 0.505, 0.3, -0.1), blue, M.Neon)
			add(c, "Cell", Vector3.new(0.7, 0.3, 0.3), CFrame.new(side * 0.6, -0.3, 0) * YAXIS, DARK, M.Metal, Enum.PartType.Cylinder)
			for i = 1, tier + 1 do
				add(c, "CoilRing", Vector3.new(0.06, 0.34, 0.34), CFrame.new(side * 0.6, -0.08 - i * 0.12, 0) * YAXIS, Color3.fromRGB(196, 120, 60), M.Metal, Enum.PartType.Cylinder, 0.2)
			end
			add(c, "Contact", Vector3.new(0.9, 0.12, 0.1), CFrame.new(0, -0.66, -0.53), CHROME, M.Metal, nil, 0.3)
			if tier >= 2 then
				for _, z in { -0.15, 0.15 } do
					add(c, "Prong", Vector3.new(0.06, 0.28, 0.06), CFrame.new(side * 0.3, 1.12, z), CHROME, M.Metal, nil, 0.3)
				end
			end
		end
	end
end

local function blastweave(char: Model, key: string, tier: number)
	-- (v2.8.2) a woven armour layer under the skin that shows at the edges: a high collar, panels down the sides of the
	-- chest, a woven band at the waist; thigh panels from tier 2
	local c = ctx(char, "Torso", key)
	if not c then
		return
	end
	local col = Color3.fromRGB(64, 62, 56)
	local dk = Color3.fromRGB(40, 40, 36)
	add(c, "Collar", Vector3.new(1.3, 0.22, 0.9), CFrame.new(0, 1.06, 0), col, M.Fabric)
	for _, x in { -1, 1 } do
		add(c, "SidePanel", Vector3.new(0.06, 1.6, 0.86), CFrame.new(x * 1.01, 0, 0), col, M.Fabric)
		for i = 0, 3 do
			add(c, "Weave", Vector3.new(0.065, 0.06, 0.86), CFrame.new(x * 1.012, 0.6 - i * 0.4, 0), dk, M.Fabric)
		end
	end
	add(c, "WaistBand", Vector3.new(2.04, 0.22, 1.04), CFrame.new(0, -0.9, 0), col, M.Fabric)
	for i = 0, tier do
		add(c, "Weave", Vector3.new(0.5, 0.18, 0.03), CFrame.new(-0.34, 0.1 - i * 0.3, -0.51), dk, M.Fabric)
		add(c, "Weave", Vector3.new(0.5, 0.18, 0.03), CFrame.new(0.34, 0.1 - i * 0.3, -0.51), dk, M.Fabric)
	end
	if tier >= 2 then
		for _, leg in { "Left Leg", "Right Leg" } do
			local cl = ctx(char, leg, key)
			if cl then
				local sx = leg == "Left Leg" and -1 or 1
				add(cl, "ThighPanel", Vector3.new(0.06, 0.9, 0.8), CFrame.new(sx * 0.51, 0.45, 0), col, M.Fabric)
			end
		end
	end
end

local function zerohour(char: Model, key: string, _tier: number)
	local c = ctx(char, "Torso", key)
	if not c then
		return
	end
	local ice = Color3.fromRGB(160, 230, 255)
	add(c, "Collar", Vector3.new(0.2, 1.0, 1.0), CFrame.new(0, 1.05, 0) * YAXIS, CHROME, M.Metal, Enum.PartType.Cylinder, 0.35)
	local g = add(c, "Glow", Vector3.new(0.08, 1.04, 1.04), CFrame.new(0, 1.12, 0) * YAXIS, ice, M.Neon, Enum.PartType.Cylinder)
	light(g, ice, 6, 1)
end

------------------------------------------------------------------------
-- arms
------------------------------------------------------------------------

local function finishOf(look: string?): (any, string)
	local fName, model = string.match(look or "", "^(%w+):(%w+)$")
	local fin = Cyberware.Finishes[1]
	for _, f in Cyberware.Finishes do
		if f.name == fName then
			fin = f
		end
	end
	if not table.find(Cyberware.Models, model or "") then
		model = "PLATED"
	end
	return fin, model :: string
end

-- a TITAN arm replaces the whole arm: the real arm part is hidden (CyberService) and this is what you see.
-- (v2.8.1) It keeps the blocky shape of an arm (1 x 2 x 1): a metal block with panel gaps, glowing seams and a hand
-- block - the three models only differ in what is on and in that block.
local function titan(char: Model, key: string, tier: number, look: string?)
	local side = string.sub(key, -1) == "L" and -1 or 1
	local c = ctx(char, side < 0 and "Left Arm" or "Right Arm", key)
	if not c then
		return
	end
	local fin, model = finishOf(look)
	local plate, dark, glow, refl = fin.plate, fin.dark, fin.glow, fin.refl
	local out = side -- the outer side (+X for the right arm)
	-- the hand: the lowest part of the block, darker, with finger grooves on the front and a knuckle ridge
	local function hand(col: Color3)
		add(c, "Hand", Vector3.new(1.02, 0.42, 1.02), CFrame.new(0, -0.8, 0), col, M.Metal, nil, refl)
		for i = 0, 3 do
			add(c, "FingerGap", Vector3.new(0.03, 0.3, 0.04), CFrame.new(-0.36 + i * 0.24, -0.84, -0.505), BLACK, M.Metal)
		end
		add(c, "Knuckles", Vector3.new(1.04, 0.08, 0.2), CFrame.new(0, -0.62, -0.43), plate, M.Metal, nil, refl)
		add(c, "PalmCore", Vector3.new(0.04, 0.2, 0.2), CFrame.new(-out * 0.515, -0.8, 0), glow, M.Neon)
	end
	-- a horizontal gap round the block
	local function gap(y: number)
		add(c, "Gap", Vector3.new(1.035, 0.05, 1.035), CFrame.new(0, y, 0), BLACK, M.Metal)
	end
	if model == "PLATED" then
		-- smooth plates: shoulder plate, upper arm, elbow band (glowing), forearm, a seam line down the outer face
		add(c, "Upper", Vector3.new(1.02, 0.95, 1.02), CFrame.new(0, 0.5, 0), plate, M.Metal, nil, refl)
		add(c, "ShoulderPlate", Vector3.new(1.06, 0.14, 1.06), CFrame.new(0, 0.94, 0), dark, M.Metal)
		add(c, "ElbowBand", Vector3.new(1.03, 0.1, 1.03), CFrame.new(0, -0.02, 0), glow, M.Neon)
		add(c, "Fore", Vector3.new(1.02, 0.5, 1.02), CFrame.new(0, -0.33, 0), plate, M.Metal, nil, refl)
		gap(0.75)
		gap(-0.6)
		add(c, "Seam", Vector3.new(0.02, 1.4, 0.06), CFrame.new(out * 0.515, 0.2, 0), glow, M.Neon)
		add(c, "Inset", Vector3.new(0.5, 0.5, 0.025), CFrame.new(0, 0.45, -0.512), dark, M.Metal)
		hand(dark)
	elseif model == "SKELETAL" then
		-- (v2.8.2) a cage you can see into: a thin dark core with two chrome bones in it, the frame on the edges and bars
		-- round it (still the shape of an arm block), joint discs on the sides, a piston down the back
		add(c, "Body", Vector3.new(0.6, 1.6, 0.6), CFrame.new(0, 0.18, 0), dark, M.DiamondPlate)
		for _, x in { -0.16, 0.16 } do
			add(c, "Bone", Vector3.new(1.5, 0.14, 0.14), CFrame.new(x, 0.18, -0.32) * YAXIS, plate, M.Metal, Enum.PartType.Cylinder, refl)
		end
		for _, y in { 0.62, 0.2, -0.22 } do
			add(c, "CageBar", Vector3.new(1.02, 0.08, 0.08), CFrame.new(0, y, -0.47), plate, M.Metal, nil, refl)
			add(c, "CageBar", Vector3.new(1.02, 0.08, 0.08), CFrame.new(0, y, 0.47), plate, M.Metal, nil, refl)
			add(c, "CageBar", Vector3.new(0.08, 0.08, 1.02), CFrame.new(-0.47, y, 0), plate, M.Metal, nil, refl)
			add(c, "CageBar", Vector3.new(0.08, 0.08, 1.02), CFrame.new(0.47, y, 0), plate, M.Metal, nil, refl)
		end
		for _, x in { -0.47, 0.47 } do
			for _, z in { -0.47, 0.47 } do
				add(c, "Edge", Vector3.new(0.1, 1.6, 0.1), CFrame.new(x, 0.18, z), plate, M.Metal, nil, refl)
			end
		end
		add(c, "TopFrame", Vector3.new(1.04, 0.1, 1.04), CFrame.new(0, 0.97, 0), plate, M.Metal, nil, refl)
		for _, x in { -1, 1 } do
			add(c, "Joint", Vector3.new(0.03, 0.26, 0.26), CFrame.new(x * 0.505, -0.02, 0), glow, M.Neon)
			add(c, "Joint", Vector3.new(0.03, 0.2, 0.2), CFrame.new(x * 0.505, 0.75, 0), glow, M.Neon)
		end
		add(c, "Piston", Vector3.new(0.12, 1.1, 0.06), CFrame.new(0, 0.2, 0.515), CHROME, M.Metal, nil, 0.4)
		add(c, "PistonSleeve", Vector3.new(0.18, 0.4, 0.07), CFrame.new(0, 0.55, 0.52), BLACK, M.Metal)
		hand(plate)
	else -- HEAVY
		-- a thick block: a square pauldron on top, armour slabs, a vent on the outer face, a heavy knuckle plate
		add(c, "Upper", Vector3.new(1.08, 1.0, 1.08), CFrame.new(0, 0.48, 0), dark, M.Metal)
		add(c, "Pauldron", Vector3.new(1.3, 0.36, 1.24), CFrame.new(out * 0.08, 0.86, 0), plate, M.Metal, nil, refl)
		add(c, "PauldronEdge", Vector3.new(1.32, 0.06, 1.26), CFrame.new(out * 0.08, 0.68, 0), glow, M.Neon)
		add(c, "Fore", Vector3.new(1.12, 0.55, 1.12), CFrame.new(0, -0.32, 0), plate, M.Metal, nil, refl)
		add(c, "Vent", Vector3.new(0.03, 0.34, 0.6), CFrame.new(out * 0.565, -0.3, 0), glow, M.Neon)
		for i = 0, 2 do
			add(c, "VentSlat", Vector3.new(0.05, 0.04, 0.62), CFrame.new(out * 0.57, -0.42 + i * 0.12, 0), BLACK, M.Metal)
		end
		hand(dark)
		add(c, "KnucklePlate", Vector3.new(1.06, 0.22, 0.12), CFrame.new(0, -0.74, -0.56), plate, M.Metal, nil, refl)
	end
	-- tier marks on the outer face of the shoulder
	for i = 1, tier do
		add(c, "Tier", Vector3.new(0.03, 0.05, 0.22), CFrame.new(out * (model == "HEAVY" and 0.57 or 0.52), 0.86 - i * 0.09, -0.25), glow, M.Neon)
	end
end

-- the forearm weapons sit on the outer side of the forearm; "open" = attribute Cy_open_<key> on the body
local function howler(char: Model, key: string, tier: number, look: string?)
	local side = string.sub(key, -1) == "L" and -1 or 1
	local c = ctx(char, side < 0 and "Left Arm" or "Right Arm", key)
	if not c then
		return
	end
	local colName = string.match(look or "", ":(%w+)$")
	local col = Cyberware.Colors[1].c
	for _, cc in Cyberware.Colors do
		if cc.name == colName then
			col = cc.c
		end
	end
	local x = side * 0.62
	add(c, "Housing", Vector3.new(0.34, 1.0, 0.7), CFrame.new(x, -0.45, 0), DARK, M.Metal)
	add(c, "HousingTop", Vector3.new(0.36, 0.1, 0.72), CFrame.new(x, 0.08, 0), STEEL, M.Metal)
	local r = 0.3 + tier * 0.05
	add(c, "Barrel", Vector3.new(0.9, r, r), CFrame.new(x, -0.95, -0.05) * YAXIS, STEEL, M.Metal, Enum.PartType.Cylinder, 0.2)
	add(c, "Muzzle", Vector3.new(0.12, r + 0.08, r + 0.08), CFrame.new(x, -1.38, -0.05) * YAXIS, BLACK, M.Metal, Enum.PartType.Cylinder)
	local core = add(c, "Core", Vector3.new(0.06, 0.34, 0.34), CFrame.new(x + side * 0.18, -0.45, 0) * ZAXIS * CFrame.Angles(0, math.rad(90), 0), col, M.Neon, Enum.PartType.Cylinder)
	for i = 0, 2 do
		add(c, "Coil", Vector3.new(0.05, r + 0.06, r + 0.06), CFrame.new(x, -0.62 - i * 0.14, -0.05) * YAXIS, col, M.Neon, Enum.PartType.Cylinder)
	end
	light(core, col, 4, 0.8)
end

local function shiftgun(char: Model, key: string, tier: number, _look: string?)
	local side = string.sub(key, -1) == "L" and -1 or 1
	local c = ctx(char, side < 0 and "Left Arm" or "Right Arm", key)
	if not c then
		return
	end
	local open = char:GetAttribute("Cy_open_" .. key) == true
	local x = side * 0.6
	add(c, "Case", Vector3.new(0.28, 0.9, 0.6), CFrame.new(x, -0.45, 0), DARK, M.Metal)
	add(c, "Rail", Vector3.new(0.05, 0.8, 0.08), CFrame.new(x + side * 0.15, -0.45, -0.18), RED, M.Neon)
	if open then
		-- the gun out past the hand: barrel, shroud, magazine, sight
		add(c, "Shroud", Vector3.new(0.42, 1.2, 0.42), CFrame.new(0, -1.5, -0.05), DARK, M.Metal)
		add(c, "Barrel", Vector3.new(0.7, 0.18, 0.18), CFrame.new(0, -2.3, -0.05) * YAXIS, STEEL, M.Metal, Enum.PartType.Cylinder, 0.2)
		add(c, "Mag", Vector3.new(0.2, 0.5, 0.3), CFrame.new(0, -1.3, 0.35) * CFrame.Angles(math.rad(-15), 0, 0), BLACK, M.Metal)
		add(c, "Sight", Vector3.new(0.12, 0.3, 0.12), CFrame.new(0, -1.5, -0.32), RED, M.Neon)
		for i = 1, tier do
			add(c, "Vent", Vector3.new(0.44, 0.05, 0.3), CFrame.new(0, -1.1 - i * 0.2, -0.05), STEEL, M.Metal)
		end
	else
		add(c, "Folded", Vector3.new(0.3, 0.7, 0.4), CFrame.new(x, -0.55, 0.12), STEEL, M.Metal)
	end
end

local function sickles(char: Model, key: string, tier: number, _look: string?)
	local side = string.sub(key, -1) == "L" and -1 or 1
	local c = ctx(char, side < 0 and "Left Arm" or "Right Arm", key)
	if not c then
		return
	end
	local open = char:GetAttribute("Cy_open_" .. key) == true
	local edge = Color3.fromRGB(255, 50, 60)
	local blade = Color3.fromRGB(42, 44, 50)
	-- the housing on the back of the forearm
	add(c, "Housing", Vector3.new(0.5, 0.9, 0.24), CFrame.new(side * 0.12, -0.45, 0.56), DARK, M.Metal)
	add(c, "Hinge", Vector3.new(0.6, 0.2, 0.2), CFrame.new(side * 0.12, -0.85, 0.56), CHROME, M.Metal, Enum.PartType.Cylinder, 0.4)
	local len = tier >= 3 and 1.9 or 1.4
	if open then
		-- out: the blade runs forward past the fist, then curves down (like a sickle)
		-- (when you punch, the arm's back faces down: the hook hangs under your fist)
		local base = CFrame.new(side * 0.12, -0.85, 0.58)
		local b1 = base * CFrame.new(0, -len / 2, 0)
		add(c, "Blade", Vector3.new(0.06, len, 0.3), b1, blade, M.Metal, nil, 0.25)
		add(c, "Edge", Vector3.new(0.065, len, 0.04), b1 * CFrame.new(0, 0, 0.15), edge, M.Neon)
		local b2 = base * CFrame.new(0, -len, 0) * CFrame.Angles(math.rad(-50), 0, 0) * CFrame.new(0, -0.3, 0)
		add(c, "Tip", Vector3.new(0.06, 0.62, 0.24), b2, blade, M.Metal, nil, 0.25)
		add(c, "TipEdge", Vector3.new(0.065, 0.62, 0.04), b2 * CFrame.new(0, 0, 0.12), edge, M.Neon)
	else
		-- folded flat along the forearm
		add(c, "Blade", Vector3.new(0.06, 1.1, 0.3), CFrame.new(side * 0.12, -0.35, 0.7), blade, M.Metal, nil, 0.25)
		add(c, "Edge", Vector3.new(0.065, 1.1, 0.03), CFrame.new(side * 0.12, -0.35, 0.86), edge, M.Neon)
	end
end

local function lodestone(char: Model, key: string, tier: number)
	-- (v2.8.2) the magnet in the palm, and copper coil rings round the wrist you can see from every side
	for _, arm in { "Left Arm", "Right Arm" } do
		local c = ctx(char, arm, key)
		if c then
			local side = arm == "Left Arm" and -1 or 1
			local x = -side * 0.5 -- the inner side (the palm faces the body)
			add(c, "Pad", Vector3.new(0.08, 0.5, 0.5), CFrame.new(x, -0.72, 0), DARK, M.Metal, Enum.PartType.Cylinder)
			add(c, "Coil", Vector3.new(0.09, 0.38, 0.38), CFrame.new(x - side * 0.01, -0.72, 0), Color3.fromRGB(196, 110, 60), M.Metal, Enum.PartType.Cylinder, 0.2)
			local core = add(c, "Core", Vector3.new(0.1, 0.18, 0.18), CFrame.new(x - side * 0.02, -0.72, 0), Color3.fromRGB(110, 170, 255), M.Neon, Enum.PartType.Cylinder)
			if tier >= 3 then
				light(core, Color3.fromRGB(110, 170, 255), 3, 0.6)
			end
			-- the wrist rings: a frame of four bars round the arm, one more per tier
			for r = 1, tier do
				local y = -0.42 + (r - 1) * 0.14
				local copper = Color3.fromRGB(184, 104, 56)
				add(c, "WristBar", Vector3.new(1.06, 0.08, 0.06), CFrame.new(0, y, -0.52), copper, M.Metal, nil, 0.25)
				add(c, "WristBar", Vector3.new(1.06, 0.08, 0.06), CFrame.new(0, y, 0.52), copper, M.Metal, nil, 0.25)
				add(c, "WristBar", Vector3.new(0.06, 0.08, 1.06), CFrame.new(-0.52, y, 0), copper, M.Metal, nil, 0.25)
				add(c, "WristBar", Vector3.new(0.06, 0.08, 1.06), CFrame.new(0.52, y, 0), copper, M.Metal, nil, 0.25)
			end
		end
	end
end

------------------------------------------------------------------------
-- legs
------------------------------------------------------------------------

local function strider(char: Model, key: string, tier: number)
	-- (v2.8.1) blocky: a metal shin block over the lower leg (the leg keeps its shape), a knee plate, pistons flush in
	-- the calf; tier 2 a thigh band, tier 3 a heel spur
	local orange = Color3.fromRGB(255, 160, 40)
	for _, leg in { "Left Leg", "Right Leg" } do
		local c = ctx(char, leg, key)
		if c then
			add(c, "Shin", Vector3.new(1.03, 0.95, 1.03), CFrame.new(0, -0.52, 0), DARK, M.Metal)
			add(c, "Sole", Vector3.new(1.05, 0.12, 1.05), CFrame.new(0, -0.94, 0), STEEL, M.Metal)
			add(c, "KneePlate", Vector3.new(0.8, 0.42, 0.08), CFrame.new(0, 0.0, -0.53), CHROME, M.Metal, nil, 0.35)
			add(c, "KneeLight", Vector3.new(0.4, 0.05, 0.03), CFrame.new(0, 0.0, -0.575), orange, M.Neon)
			add(c, "CalfSlot", Vector3.new(0.6, 0.7, 0.03), CFrame.new(0, -0.5, 0.52), BLACK, M.Metal)
			for _, x in { -0.16, 0.16 } do
				add(c, "Piston", Vector3.new(0.1, 0.62, 0.05), CFrame.new(x, -0.5, 0.535), CHROME, M.Metal, nil, 0.4)
			end
			add(c, "ShinStripe", Vector3.new(0.035, 0.6, 0.06), CFrame.new(0.515 * (leg == "Left Leg" and -1 or 1), -0.5, -0.2), orange, M.Neon)
			if tier >= 2 then
				add(c, "ThighBand", Vector3.new(1.03, 0.22, 1.03), CFrame.new(0, 0.62, 0), DARK, M.Metal)
				add(c, "ThighLight", Vector3.new(1.035, 0.04, 1.035), CFrame.new(0, 0.62, 0), orange, M.Neon)
			end
			if tier >= 3 then
				add(c, "HeelSpur", Vector3.new(0.3, 0.3, 0.22), CFrame.new(0, -0.85, 0.6), CHROME, M.Metal, nil, 0.4)
			end
		end
	end
end

-- (v2.8.1) REGROWTH CORE: a port on the right thigh, green fluid behind glass; tier 3 a second one on the left
local function regrowth(char: Model, key: string, tier: number)
	-- (v2.8.2) engineered marrow: bone-white braces round the thighs with culture vials set in them (pale green glass),
	-- a marrow column down the back from tier 2, a reservoir on the side of the chest at tier 3
	local boneC = Color3.fromRGB(226, 218, 200)
	local vialC = Color3.fromRGB(150, 220, 170)
	for _, leg in { "Right Leg", "Left Leg" } do
		local c = ctx(char, leg, key)
		if c then
			local sx = leg == "Right Leg" and 1 or -1
			for _, y in { 0.75, 0.15 } do
				add(c, "Brace", Vector3.new(1.06, 0.14, 1.06), CFrame.new(0, y, 0), boneC, M.SmoothPlastic)
			end
			add(c, "Port", Vector3.new(0.06, 0.62, 0.44), CFrame.new(sx * 0.52, 0.45, 0), DARK, M.Metal)
			local vial = add(c, "Vial", Vector3.new(0.07, 0.46, 0.28), CFrame.new(sx * 0.54, 0.45, 0), vialC, M.Glass)
			vial.Transparency = 0.25
			vial.Reflectance = 0.2
		end
	end
	if tier >= 2 then
		local c = ctx(char, "Torso", key)
		if c then
			for i = 0, 5 do
				add(c, "MarrowSeg", Vector3.new(0.3, 0.2, 0.12), CFrame.new(0, 0.75 - i * 0.3, 0.55), boneC, M.SmoothPlastic)
			end
			if tier >= 3 then
				add(c, "Reservoir", Vector3.new(0.9, 0.36, 0.36), CFrame.new(1.08, -0.2, 0) * YAXIS, DARK, M.Metal, Enum.PartType.Cylinder)
				local v = add(c, "ReservoirGlass", Vector3.new(0.6, 0.3, 0.3), CFrame.new(1.1, -0.2, 0) * YAXIS, vialC, M.Glass, Enum.PartType.Cylinder)
				v.Transparency = 0.3
			end
		end
	end
end

------------------------------------------------------------------------
-- the admin protocol: heavy plates everywhere, a red visor
------------------------------------------------------------------------

local function colossus(char: Model, key: string, _tier: number)
	-- (v2.8.1) a war machine, still blocky: layered chest plates round a square reactor, a gorget, a power pack with two
	-- stacks on the back, a helmet with a burning visor slit and a grilled jaw, square pauldrons, gauntlets, knee guards
	-- and heavy boots. Gunmetal, black and red.
	local gun = Color3.fromRGB(70, 72, 78)
	local gun2 = Color3.fromRGB(96, 98, 104)
	local dk = Color3.fromRGB(22, 23, 26)
	local red = Color3.fromRGB(255, 34, 34)
	local c = ctx(char, "Torso", key)
	if c then
		add(c, "ChestPlate", Vector3.new(2.14, 0.95, 1.18), CFrame.new(0, 0.5, -0.02), gun, M.Metal, nil, 0.12)
		add(c, "ChestUpper", Vector3.new(1.7, 0.3, 1.24), CFrame.new(0, 0.86, -0.02), gun2, M.Metal, nil, 0.15)
		add(c, "ReactorFrame", Vector3.new(0.62, 0.62, 0.1), CFrame.new(0, 0.45, -0.63), dk, M.Metal)
		local r = add(c, "Reactor", Vector3.new(0.4, 0.4, 0.06), CFrame.new(0, 0.45, -0.67), red, M.Neon)
		light(r, red, 10, 1.6)
		for _, x in { -1, 1 } do
			add(c, "ReactorLine", Vector3.new(0.5, 0.05, 0.04), CFrame.new(x * 0.6, 0.45, -0.62), red, M.Neon)
		end
		for i = 0, 2 do
			add(c, "AbPlate", Vector3.new(1.7 - i * 0.12, 0.2, 1.12), CFrame.new(0, -0.12 - i * 0.26, -0.02), i % 2 == 0 and gun or dk, M.Metal, nil, 0.08)
		end
		add(c, "Belt", Vector3.new(2.12, 0.22, 1.14), CFrame.new(0, -0.9, 0), dk, M.DiamondPlate)
		add(c, "Gorget", Vector3.new(1.3, 0.3, 1.1), CFrame.new(0, 1.12, 0.02), dk, M.Metal)
		-- the power pack on the back
		add(c, "Pack", Vector3.new(1.6, 1.5, 0.6), CFrame.new(0, 0.35, 0.86), dk, M.Metal)
		add(c, "PackPlate", Vector3.new(1.3, 1.1, 0.08), CFrame.new(0, 0.35, 1.2), gun, M.Metal, nil, 0.1)
		for i = 0, 3 do
			add(c, "PackVent", Vector3.new(1.0, 0.05, 0.04), CFrame.new(0, 0.05 + i * 0.2, 1.255), red, M.Neon)
		end
		for _, x in { -0.5, 0.5 } do
			add(c, "Stack", Vector3.new(0.34, 0.9, 0.34), CFrame.new(x, 1.3, 0.92), gun2, M.Metal, nil, 0.2)
			add(c, "StackTop", Vector3.new(0.38, 0.08, 0.38), CFrame.new(x, 1.79, 0.92), dk, M.Metal)
		end
	end
	local h = ctx(char, "Head", key)
	if h then
		-- the helmet: a block over the head, a crest, a visor slit, a grilled jaw, sensor blocks on the sides
		add(h, "Helmet", Vector3.new(1.34, 0.8, 1.34), CFrame.new(0, 0.28, 0.02), gun, M.Metal, nil, 0.15)
		add(h, "Crest", Vector3.new(0.22, 0.2, 1.3), CFrame.new(0, 0.75, 0.02), dk, M.Metal)
		add(h, "Brow", Vector3.new(1.36, 0.14, 0.2), CFrame.new(0, 0.32, -0.62), dk, M.Metal)
		local v = add(h, "Visor", Vector3.new(1.0, 0.1, 0.06), CFrame.new(0, 0.16, -0.68), red, M.Neon)
		light(v, red, 9, 1.5)
		add(h, "Jaw", Vector3.new(1.1, 0.5, 0.56), CFrame.new(0, -0.32, -0.4), dk, M.Metal)
		for i = -2, 2 do
			add(h, "Grill", Vector3.new(0.06, 0.34, 0.04), CFrame.new(i * 0.16, -0.32, -0.69), gun2, M.Metal)
		end
		for _, x in { -1, 1 } do
			add(h, "Sensor", Vector3.new(0.2, 0.4, 0.5), CFrame.new(x * 0.74, 0.2, 0), gun2, M.Metal)
			add(h, "SensorLed", Vector3.new(0.04, 0.08, 0.3), CFrame.new(x * 0.85, 0.2, 0), red, M.Neon)
		end
	end
	for _, name in { "Left Arm", "Right Arm", "Left Leg", "Right Leg" } do
		local l = ctx(char, name, key)
		if l then
			local arm = string.find(name, "Arm") ~= nil
			local side = string.find(name, "Left") and -1 or 1
			if arm then
				add(l, "Pauldron", Vector3.new(1.42, 0.55, 1.34), CFrame.new(side * 0.12, 0.84, 0), gun, M.Metal, nil, 0.12)
				add(l, "PauldronTrim", Vector3.new(1.44, 0.07, 1.36), CFrame.new(side * 0.12, 0.6, 0), red, M.Neon)
				add(l, "PauldronTop", Vector3.new(1.1, 0.14, 1.0), CFrame.new(side * 0.12, 1.15, 0), dk, M.Metal)
				add(l, "UpperPlate", Vector3.new(1.12, 0.5, 1.12), CFrame.new(0, 0.18, 0), dk, M.Metal)
				add(l, "Gauntlet", Vector3.new(1.2, 0.9, 1.2), CFrame.new(0, -0.5, 0), gun, M.Metal, nil, 0.12)
				add(l, "GauntletLine", Vector3.new(0.04, 0.6, 0.06), CFrame.new(side * 0.62, -0.5, -0.3), red, M.Neon)
				add(l, "Knuckle", Vector3.new(1.08, 0.24, 0.2), CFrame.new(0, -0.86, -0.62), dk, M.Metal)
			else
				add(l, "Thigh", Vector3.new(1.14, 0.75, 1.14), CFrame.new(0, 0.5, 0), gun, M.Metal, nil, 0.1)
				add(l, "KneeGuard", Vector3.new(0.9, 0.5, 0.2), CFrame.new(0, -0.05, -0.62), gun2, M.Metal, nil, 0.15)
				add(l, "KneeLed", Vector3.new(0.4, 0.06, 0.04), CFrame.new(0, -0.05, -0.74), red, M.Neon)
				add(l, "Shin", Vector3.new(1.1, 0.5, 1.1), CFrame.new(0, -0.45, 0), dk, M.Metal)
				add(l, "Boot", Vector3.new(1.2, 0.36, 1.44), CFrame.new(0, -0.84, -0.14), gun, M.Metal, nil, 0.1)
				add(l, "BootToe", Vector3.new(1.0, 0.2, 0.2), CFrame.new(0, -0.92, -0.9), dk, M.Metal)
			end
		end
	end
end

------------------------------------------------------------------------
-- (v2.8) the pump, the lungs, the ears
------------------------------------------------------------------------

-- IRONHEART PUMP: a port on the left of the chest with a red ring that glows stronger with the tier
local function pump(char: Model, key: string, tier: number)
	-- (v2.8.2) a second heart: a housing on the chest with the pump in it, hoses over the shoulders (one more per tier)
	local c = ctx(char, "Torso", key)
	if not c then
		return
	end
	add(c, "PumpHousing", Vector3.new(0.7, 0.7, 0.08), CFrame.new(-0.48, 0.42, -0.52), DARK, M.Metal)
	add(c, "PumpPort", Vector3.new(0.12, 0.42, 0.42), CFrame.new(-0.48, 0.42, -0.56) * ZAXIS, STEEL, M.Metal, Enum.PartType.Cylinder, 0.2)
	local ring = add(c, "PumpRing", Vector3.new(0.13, 0.3, 0.3), CFrame.new(-0.48, 0.42, -0.58) * ZAXIS, RED, M.Neon, Enum.PartType.Cylinder)
	ring.Transparency = 0.45 - tier * 0.12
	add(c, "PumpCore", Vector3.new(0.14, 0.14, 0.14), CFrame.new(-0.48, 0.42, -0.61) * ZAXIS, CHROME, M.Metal, Enum.PartType.Cylinder, 0.4)
	for i = 1, tier do
		local x = -0.75 + i * 0.12
		add(c, "PumpHose", Vector3.new(0.09, 0.62, 0.09), CFrame.new(x, 0.8, -0.53), Color3.fromRGB(120, 24, 28), M.Fabric)
		add(c, "PumpHose", Vector3.new(0.09, 0.09, 1.06), CFrame.new(x, 1.04, 0), Color3.fromRGB(120, 24, 28), M.Fabric)
	end
end

-- DEEPWATER LUNGS: two vents in the back, slats over them
local function lungs(char: Model, key: string, tier: number)
	-- (v2.8.2) vents on the back, two filter canisters on the sides of the ribs, hoses up to the neck
	local c = ctx(char, "Torso", key)
	if not c then
		return
	end
	for _, x in { -1, 1 } do
		add(c, "Vent", Vector3.new(0.5, 0.42, 0.06), CFrame.new(x * 0.45, 0.4, 0.52), DARK, M.Metal)
		for i = 0, 2 do
			add(c, "Slat", Vector3.new(0.46, 0.05, 0.07), CFrame.new(x * 0.45, 0.55 - i * 0.14, 0.535), STEEL, M.Metal)
		end
		add(c, "Canister", Vector3.new(0.8, 0.32, 0.32), CFrame.new(x * 1.08, 0.05, 0.25) * YAXIS, Color3.fromRGB(60, 80, 90), M.Metal, Enum.PartType.Cylinder, 0.2)
		add(c, "CanisterCap", Vector3.new(0.1, 0.34, 0.34), CFrame.new(x * 1.08, 0.48, 0.25) * YAXIS, STEEL, M.Metal, Enum.PartType.Cylinder)
		add(c, "Hose", Vector3.new(0.09, 0.8, 0.09), CFrame.new(x * 0.82, 0.75, 0.36) * CFrame.Angles(0, 0, math.rad(x * 30)), BLACK, M.Fabric)
		if tier >= 3 then
			local glow = add(c, "VentGlow", Vector3.new(0.4, 0.04, 0.065), CFrame.new(x * 0.45, 0.62, 0.53), CYAN, M.Neon)
			glow.Transparency = 0.3
		end
	end
end

-- ECHO EARS: chrome discs on both sides of the head; tier 3 a short antenna
local function echo(char: Model, key: string, tier: number)
	local c = ctx(char, "Head", key)
	if not c then
		return
	end
	for _, x in { -1, 1 } do
		add(c, "EarDisc", Vector3.new(0.1, 0.38, 0.38), CFrame.new(x * 0.62, 0.02, 0.02), CHROME, M.Metal, Enum.PartType.Cylinder, 0.35)
		add(c, "EarGrill", Vector3.new(0.11, 0.24, 0.24), CFrame.new(x * 0.63, 0.02, 0.02), BLACK, M.Metal, Enum.PartType.Cylinder)
		if tier >= 2 then
			add(c, "EarLight", Vector3.new(0.115, 0.07, 0.07), CFrame.new(x * 0.635, 0.16, -0.08), Color3.fromRGB(255, 170, 40), M.Neon, Enum.PartType.Cylinder)
		end
		if tier >= 3 and x > 0 then
			add(c, "EarAntenna", Vector3.new(0.04, 0.5, 0.04), CFrame.new(0.66, 0.38, 0.06) * CFrame.Angles(0, 0, math.rad(-12)), STEEL, M.Metal)
		end
	end
end

-- (v2.8.2) BEDROCK STABILIZER: gyro drums on both hips, locking braces over the knees
local function anchor(char: Model, key: string, tier: number)
	local c = ctx(char, "Torso", key)
	if not c then
		return
	end
	for _, x in { -1, 1 } do
		add(c, "HipDrum", Vector3.new(0.18, 0.66, 0.66), CFrame.new(x * 1.04, -0.7, 0), DARK, M.Metal, Enum.PartType.Cylinder)
		add(c, "HipRing", Vector3.new(0.2, 0.46, 0.46), CFrame.new(x * 1.07, -0.7, 0), STEEL, M.Metal, Enum.PartType.Cylinder, 0.3)
		add(c, "HipCap", Vector3.new(0.22, 0.2, 0.2), CFrame.new(x * 1.1, -0.7, 0), tier >= 3 and Color3.fromRGB(230, 150, 50) or CHROME, M.Metal, Enum.PartType.Cylinder, 0.2)
		if tier >= 2 then
			add(c, "HipStrut", Vector3.new(0.1, 0.5, 0.14), CFrame.new(x * 1.04, -0.3, 0.2), STEEL, M.Metal)
		end
	end
	for _, leg in { "Left Leg", "Right Leg" } do
		local cl = ctx(char, leg, key)
		if cl then
			add(cl, "KneeLock", Vector3.new(0.9, 0.36, 0.12), CFrame.new(0, 0.02, -0.54), STEEL, M.Metal, nil, 0.2)
			add(cl, "KneeBolt", Vector3.new(0.08, 0.2, 0.2), CFrame.new(0, 0.02, -0.61) * ZAXIS, DARK, M.Metal, Enum.PartType.Cylinder)
			for _, x in { -1, 1 } do
				add(cl, "Brace", Vector3.new(0.08, 1.3, 0.14), CFrame.new(x * 0.53, 0.05, -0.1), DARK, M.Metal)
				add(cl, "BraceJoint", Vector3.new(0.1, 0.22, 0.22), CFrame.new(x * 0.55, 0.02, -0.1), STEEL, M.Metal, Enum.PartType.Cylinder)
			end
			if tier >= 3 then
				add(cl, "AnkleClamp", Vector3.new(1.06, 0.2, 1.06), CFrame.new(0, -0.82, 0), DARK, M.Metal)
			end
		end
	end
end

-- (v2.8.2) BASTION SHELL folded away: stacked plates along the spine and on the outside of the limbs
local function bastion(char: Model, key: string, tier: number)
	local c = ctx(char, "Torso", key)
	if not c then
		return
	end
	local gun = Color3.fromRGB(70, 74, 82)
	for i = 0, 2 + math.min(tier, 2) do
		add(c, "FoldedPlate", Vector3.new(1.3 - i * 0.08, 0.22, 0.1), CFrame.new(0, 0.75 - i * 0.3, 0.56) * CFrame.Angles(math.rad(-12), 0, 0), gun, M.Metal, nil, 0.15)
	end
	add(c, "SpineRail", Vector3.new(0.14, 1.6, 0.08), CFrame.new(0, 0.05, 0.53), DARK, M.Metal)
	for _, limb in { "Left Arm", "Right Arm", "Left Leg", "Right Leg" } do
		local cl = ctx(char, limb, key)
		if cl then
			local sx = string.find(limb, "Left") and -1 or 1
			for i = 0, 1 do
				add(cl, "FoldedPlate", Vector3.new(0.08, 0.36, 0.7), CFrame.new(sx * 0.53, 0.55 - i * 0.42, 0), gun, M.Metal, nil, 0.15)
			end
		end
	end
end

-- (v2.8.2) the BASTION SHELL closed round a body: big plates that fold out of the small ones. The sides of the chest
-- (under the arms), the head and the backs of the legs stay open - the gaps. Returns every plate with its weld, where it
-- goes (out) and where it comes from (tuck), so CyberService can unfold / fold them.
function CyberModels.Bastion(char: Model, tier: number): { any }
	local sc = char:GetAttribute("BodyScale")
	local k = typeof(sc) == "number" and sc or 1
	local list = {}
	local gun = Color3.fromRGB(64, 68, 76)
	local edge = Color3.fromRGB(150, 156, 166)
	local function plate(hostName: string, name: string, size: Vector3, out: CFrame, tuck: CFrame, color: Color3?)
		local host = char:FindFirstChild(hostName)
		if not host or not host:IsA("BasePart") then
			return
		end
		local f = host:FindFirstChild("Cy_bastion_up")
		if not f then
			f = Instance.new("Folder")
			f.Name = "Cy_bastion_up"
			f.Parent = host
		end
		local pt = Instance.new("Part")
		pt.Name = name
		pt.Size = size * k * 0.2
		pt.Color = color or gun
		pt.Material = M.Metal
		pt.Reflectance = 0.18
		pt.CanCollide, pt.CanQuery, pt.CanTouch, pt.Massless, pt.CastShadow = false, false, false, true, false
		pt.TopSurface, pt.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		local o = CFrame.new(out.Position * k) * out.Rotation
		local t = CFrame.new(tuck.Position * k) * tuck.Rotation
		pt.CFrame = host.CFrame * t
		local w = Instance.new("Weld")
		w.Part0 = host
		w.Part1 = pt
		w.C0 = t
		w.Parent = pt
		pt.Parent = f
		table.insert(list, { part = pt, weld = w, out = o, tuck = t, size = size * k })
	end
	-- the chest: front and back plates 1.5 wide (the sides stay open), a collar, a belly band (tier 3)
	plate("Torso", "ChestPlate", Vector3.new(1.5, 1.75, 0.16), CFrame.new(0, 0.05, -0.62), CFrame.new(0, 0.7, 0.5))
	plate("Torso", "BackPlate", Vector3.new(1.5, 1.75, 0.16), CFrame.new(0, 0.05, 0.62), CFrame.new(0, 0.7, 0.5))
	plate("Torso", "Collar", Vector3.new(1.4, 0.26, 1.3), CFrame.new(0, 1.05, 0), CFrame.new(0, 0.8, 0.45), edge)
	plate("Torso", "ChestRidge", Vector3.new(0.14, 1.5, 0.08), CFrame.new(0, 0.05, -0.72), CFrame.new(0, 0.7, 0.5), edge)
	if tier >= 3 then
		plate("Torso", "BellyBand", Vector3.new(1.5, 0.3, 1.32), CFrame.new(0, -0.8, 0), CFrame.new(0, 0.5, 0.45))
	end
	-- the arms: a pauldron over the shoulder, a plate down the outside
	for _, arm in { "Left Arm", "Right Arm" } do
		local sx = arm == "Left Arm" and -1 or 1
		plate(arm, "Pauldron", Vector3.new(1.25, 0.5, 1.25), CFrame.new(sx * 0.08, 0.9, 0), CFrame.new(sx * 0.4, 0.6, 0))
		plate(arm, "ArmPlate", Vector3.new(0.16, 1.3, 1.06), CFrame.new(sx * 0.59, 0.0, 0), CFrame.new(sx * 0.48, 0.55, 0))
	end
	-- the legs: front and outside (the backs stay open)
	for _, leg in { "Left Leg", "Right Leg" } do
		local sx = leg == "Left Leg" and -1 or 1
		plate(leg, "ThighPlate", Vector3.new(1.06, 0.9, 0.16), CFrame.new(0, 0.5, -0.59), CFrame.new(sx * 0.48, 0.55, 0))
		plate(leg, "ShinPlate", Vector3.new(1.06, 0.85, 0.16), CFrame.new(0, -0.48, -0.59), CFrame.new(sx * 0.48, 0.2, 0))
		plate(leg, "LegSide", Vector3.new(0.16, 1.75, 0.75), CFrame.new(sx * 0.59, 0, -0.1), CFrame.new(sx * 0.48, 0.4, 0))
	end
	return list
end

local BUILDERS = {
	optics = optics, cortex = cortex, keel = keel, aegis = aegis, sentry = sentry, ghostskin = ghostskin, dermis = dermis,
	blastweave = blastweave, zerohour = zerohour, titan = titan, howler = howler, shiftgun = shiftgun, sickles = sickles,
	lodestone = lodestone, strider = strider, colossus = colossus, pump = pump, lungs = lungs, echo = echo, regrowth = regrowth,
	anchor = anchor, bastion = bastion,
}

-- remove every implant model from a body
function CyberModels.Strip(char: Model, key: string?)
	for _, d in char:GetDescendants() do
		if d:IsA("Folder") and string.sub(d.Name, 1, 3) == "Cy_" and (key == nil or d.Name == "Cy_" .. key) then
			d:Destroy()
		end
	end
end

-- (re)build the models of all implants in the list on a body
function CyberModels.Dress(char: Model, list: { [string]: number }, look: { [string]: string })
	CyberModels.Strip(char)
	for key, tier in list do
		CyberModels.DressOne(char, key, tier, look[key] or look[(Cyberware.Split(key))])
	end
end

function CyberModels.DressOne(char: Model, key: string, tier: number, look: string?)
	CyberModels.Strip(char, key)
	local id = Cyberware.Split(key)
	local b = BUILDERS[id]
	if b then
		local ok, err = pcall(b, char, key, tier, look)
		if not ok then
			warn("[cyber] model", key, err)
		end
	end
end

-- a random look for a new TITAN arm
function CyberModels.RandomLook(rng: Random): string
	local f = Cyberware.Finishes[rng:NextInteger(1, #Cyberware.Finishes)]
	local m = Cyberware.Models[rng:NextInteger(1, #Cyberware.Models)]
	return f.name .. ":" .. m
end

return CyberModels
