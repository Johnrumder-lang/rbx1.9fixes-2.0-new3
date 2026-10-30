--!nonstrict
-- ArmorService (v2.1g): BODY ARMOR. A set = a helmet, a vest, two arm plates and two leg plates. Every piece stops bullets that hit the armoured
-- part of its body part and BREAKS after ARMOR_HITS hits. Small places stay open (the face under the helmet's brim, the sides of the chest under
-- the arms, the neck / belt line, the forearm below the plate, the ankles): a bullet that hits there goes through as usual.
-- Only bullets count (melee, blasts, falls hurt as before). It is put on with F: the "Body Armor" item of the spawn menu (Items).
-- Model attributes: Armor_<Head|Torso|LeftArm|RightArm|LeftLeg|RightLeg> = hits left.  Player attribute ArmorStatus = "H30,V30,AL30,AR30,LL30,LR30".

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local ArmorService = {}

local ARMOR_HITS = 30
local deps: any = {}

local ORDER = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
local PART_OF = { Head = "Head", Torso = "Torso", LeftArm = "Left Arm", RightArm = "Right Arm", LeftLeg = "Left Leg", RightLeg = "Right Leg" }
local SHORT = { Head = "H", Torso = "V", LeftArm = "AL", RightArm = "AR", LeftLeg = "LL", RightLeg = "LR" }

local OLIVE = Color3.fromRGB(62, 68, 58)
local OLIVE_D = Color3.fromRGB(40, 44, 38)
local STEEL = Color3.fromRGB(86, 90, 98)
local BLACKISH = Color3.fromRGB(22, 22, 24)

-- the part of each body part that the armour covers, in the body part's own space (y up; the face looks to -z)
local COVER: { [string]: (Vector3, Vector3) -> boolean } = {
	Torso = function(lp, sz) -- the sides (under the arms), the shoulder / neck line and the belt line are open
		return math.abs(lp.X) < sz.X * 0.5 * 0.80 and lp.Y < sz.Y * 0.5 * 0.78 and lp.Y > -sz.Y * 0.5 * 0.70
	end,
	Head = function(lp, sz) -- the helmet: the top and the back; the chin / mouth and the face opening in front stay open
		if lp.Y < -sz.Y * 0.5 * 0.2 then
			return false
		end
		if lp.Z < -sz.Z * 0.5 * 0.25 and lp.Y < sz.Y * 0.5 * 0.35 then
			return false
		end
		return true
	end,
	LeftArm = function(lp, sz) -- the plate covers the upper arm and the elbow; the forearm and the hand are open
		return lp.Y > -sz.Y * 0.5 * 0.35
	end,
	RightArm = function(lp, sz)
		return lp.Y > -sz.Y * 0.5 * 0.35
	end,
	LeftLeg = function(lp, sz) -- the thigh and the shin; the ankle and the groin line stay open
		return lp.Y < sz.Y * 0.5 * 0.85 and lp.Y > -sz.Y * 0.5 * 0.55
	end,
	RightLeg = function(lp, sz)
		return lp.Y < sz.Y * 0.5 * 0.85 and lp.Y > -sz.Y * 0.5 * 0.55
	end,
}

local function status(model: Model)
	local p = Players:GetPlayerFromCharacter(model)
	if not p then
		return
	end
	local parts = {}
	local any = false
	for _, r in ORDER do
		local h = model:GetAttribute("Armor_" .. r)
		h = typeof(h) == "number" and h or 0
		if h > 0 then
			any = true
		end
		table.insert(parts, SHORT[r] .. h)
	end
	p:SetAttribute("ArmorStatus", any and table.concat(parts, ",") or nil)
end

local function piece(model: Model, host: BasePart, name: string, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material?, ellipsoid: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
	p.CastShadow = true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p:SetAttribute("ArmorPiece", true)
	if ellipsoid then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	p.CFrame = host.CFrame * off
	p.Parent = host
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = host, p
	w.Parent = p
	return p
end

local function clearPieces(host: BasePart)
	for _, d in host:GetChildren() do
		if d:IsA("BasePart") and d:GetAttribute("ArmorPiece") then
			d:Destroy()
		end
	end
end

-- the look of each piece (they are welded to the body part, so they move with it)
local function dress(model: Model, region: string)
	local host = model:FindFirstChild(PART_OF[region])
	if not host or not host:IsA("BasePart") then
		return
	end
	clearPieces(host)
	local sz = host.Size
	if region == "Torso" then
		piece(model, host, "Vest", Vector3.new(sz.X * 0.8 + 0.12, sz.Y * 0.74, sz.Z + 0.16), CFrame.new(0, sz.Y * 0.02, 0), OLIVE, Enum.Material.Fabric)
		piece(model, host, "VestPlateFront", Vector3.new(sz.X * 0.5, sz.Y * 0.46, 0.12), CFrame.new(0, sz.Y * 0.06, -(sz.Z * 0.5 + 0.13)), STEEL, Enum.Material.Metal)
		piece(model, host, "VestPlateBack", Vector3.new(sz.X * 0.5, sz.Y * 0.46, 0.12), CFrame.new(0, sz.Y * 0.06, sz.Z * 0.5 + 0.13), STEEL, Enum.Material.Metal)
		for _, s2 in { -1, 1 } do -- (a dark frame around the front plate)
			piece(model, host, "PlateFrameV", Vector3.new(0.06, sz.Y * 0.5, 0.15), CFrame.new(s2 * sz.X * 0.27, sz.Y * 0.06, -(sz.Z * 0.5 + 0.14)), BLACKISH, Enum.Material.Metal)
		end
		piece(model, host, "PlateFrameT", Vector3.new(sz.X * 0.54, 0.06, 0.15), CFrame.new(0, sz.Y * 0.31, -(sz.Z * 0.5 + 0.14)), BLACKISH, Enum.Material.Metal)
		piece(model, host, "PlateFrameB", Vector3.new(sz.X * 0.54, 0.06, 0.15), CFrame.new(0, -sz.Y * 0.19, -(sz.Z * 0.5 + 0.14)), BLACKISH, Enum.Material.Metal)
		for _, s2 in { -1, 1 } do -- (shoulder pads on the straps)
			piece(model, host, "ShoulderPad", Vector3.new(0.32, 0.16, sz.Z * 0.8), CFrame.new(s2 * sz.X * 0.28, sz.Y * 0.46, 0), OLIVE_D, Enum.Material.Fabric)
		end
		for i = -1, 1 do -- (three magazine pouches across the front)
			piece(model, host, "MagPouch", Vector3.new(0.3, 0.34, 0.16), CFrame.new(i * sz.X * 0.26, -sz.Y * 0.3, -(sz.Z * 0.5 + 0.2)), OLIVE_D, Enum.Material.Fabric)
		end
		for k = 0, 2 do -- (webbing rows across the back plate)
			piece(model, host, "Webbing", Vector3.new(sz.X * 0.52, 0.05, 0.14), CFrame.new(0, sz.Y * (0.2 - k * 0.14), sz.Z * 0.5 + 0.2), OLIVE_D, Enum.Material.Fabric)
		end
		piece(model, host, "Radio", Vector3.new(0.22, 0.4, 0.16), CFrame.new(-sz.X * 0.3, sz.Y * 0.14, -(sz.Z * 0.5 + 0.22)), BLACKISH, Enum.Material.SmoothPlastic)
		piece(model, host, "RadioAntenna", Vector3.new(0.04, 0.5, 0.04), CFrame.new(-sz.X * 0.33, sz.Y * 0.4, -(sz.Z * 0.5 + 0.22)), BLACKISH, Enum.Material.SmoothPlastic)
		for _, s in { -1, 1 } do
			piece(model, host, "Strap", Vector3.new(0.2, 0.14, sz.Z + 0.2), CFrame.new(s * sz.X * 0.28, sz.Y * 0.42, 0), BLACKISH, Enum.Material.Fabric)
			piece(model, host, "Pouch", Vector3.new(0.34, 0.3, 0.2), CFrame.new(s * sz.X * 0.2, -sz.Y * 0.28, -(sz.Z * 0.5 + 0.18)), OLIVE_D, Enum.Material.Fabric)
		end
	elseif region == "Head" then
		-- (v2.8) sized to the head you SEE, not to the head's 2-stud wide box: the old helmet was twice as wide as the head.
		-- The R6 head mesh is about 1.25 studs wide, deep and tall.
		local W = 1.25
		piece(model, host, "Helmet", Vector3.new(W * 1.12, 0.98, W * 1.18), CFrame.new(0, 0.3, 0.04), OLIVE, Enum.Material.SmoothPlastic, true)
		local band = piece(model, host, "HelmetBand", Vector3.new(0.09, W * 1.13, W * 1.19), CFrame.new(0, 0.2, 0.04) * CFrame.Angles(0, 0, math.rad(90)), BLACKISH, Enum.Material.Fabric)
		band.Shape = Enum.PartType.Cylinder
		piece(model, host, "Brim", Vector3.new(W * 0.86, 0.07, 0.3), CFrame.new(0, 0.2, -W * 0.6) * CFrame.Angles(math.rad(-8), 0, 0), OLIVE_D)
		piece(model, host, "NeckGuard", Vector3.new(W * 0.92, 0.32, 0.11), CFrame.new(0, 0.02, W * 0.58) * CFrame.Angles(math.rad(10), 0, 0), OLIVE_D, Enum.Material.Fabric)
		piece(model, host, "NvgMount", Vector3.new(0.3, 0.2, 0.12), CFrame.new(0, 0.36, -W * 0.64) * CFrame.Angles(math.rad(-20), 0, 0), BLACKISH, Enum.Material.Metal)
		piece(model, host, "NvgArm", Vector3.new(0.12, 0.14, 0.18), CFrame.new(0, 0.26, -W * 0.72), STEEL, Enum.Material.Metal)
		piece(model, host, "HelmetRidge", Vector3.new(0.08, 0.06, W * 0.86), CFrame.new(0, 0.78, 0.05), OLIVE_D)
		for _, s2 in { -1, 1 } do
			-- side rails, ear cups, the chin strap
			piece(model, host, "SideRail", Vector3.new(0.05, 0.08, 0.5), CFrame.new(s2 * W * 0.57, 0.28, 0.02), STEEL, Enum.Material.Metal)
			piece(model, host, "EarCup", Vector3.new(0.12, 0.34, 0.38), CFrame.new(s2 * W * 0.55, 0.02, 0.04), BLACKISH, Enum.Material.SmoothPlastic, true)
			piece(model, host, "ChinStrap", Vector3.new(0.05, 0.46, 0.05), CFrame.new(s2 * W * 0.44, -0.16, -0.18) * CFrame.Angles(math.rad(14), 0, 0), BLACKISH, Enum.Material.Fabric)
		end
		piece(model, host, "StrobeLight", Vector3.new(0.12, 0.08, 0.16), CFrame.new(0, 0.72, W * 0.36), Color3.fromRGB(120, 255, 140), Enum.Material.Neon)
	elseif region == "LeftArm" or region == "RightArm" then
		-- (v2.8) slimmer: a plate on the upper arm, a rounded shoulder, an elbow pad - no more boxes twice the arm's size
		local out = region == "LeftArm" and -1 or 1
		piece(model, host, "ArmPlate", Vector3.new(sz.X * 1.1, sz.Y * 0.46, sz.Z * 1.1), CFrame.new(0, sz.Y * 0.2, 0), OLIVE, Enum.Material.Fabric)
		piece(model, host, "Pauldron", Vector3.new(sz.X * 1.3, 0.62, sz.Z * 1.3), CFrame.new(out * 0.05, sz.Y * 0.42, 0), OLIVE_D, Enum.Material.SmoothPlastic, true)
		piece(model, host, "ArmStrap", Vector3.new(sz.X * 1.13, 0.08, sz.Z * 1.13), CFrame.new(0, sz.Y * 0.06, 0), BLACKISH, Enum.Material.Fabric)
		piece(model, host, "ElbowPad", Vector3.new(sz.X * 0.8, 0.34, 0.22), CFrame.new(0, -sz.Y * 0.06, sz.Z * 0.55), STEEL, Enum.Material.Metal, true)
		piece(model, host, "ArmPatch", Vector3.new(0.05, 0.3, 0.42), CFrame.new(out * (sz.X * 0.56), sz.Y * 0.22, 0), Color3.fromRGB(150, 140, 96), Enum.Material.Fabric)
	else
		piece(model, host, "LegPlate", Vector3.new(sz.X * 1.08, sz.Y * 0.36, sz.Z * 1.08), CFrame.new(0, sz.Y * 0.24, 0), OLIVE, Enum.Material.Fabric)
		piece(model, host, "KneeCap", Vector3.new(sz.X * 0.78, 0.44, 0.32), CFrame.new(0, -sz.Y * 0.02, -(sz.Z * 0.5 + 0.06)), STEEL, Enum.Material.Metal, true)
		piece(model, host, "ShinPlate", Vector3.new(sz.X * 0.84, sz.Y * 0.28, 0.12), CFrame.new(0, -sz.Y * 0.24, -(sz.Z * 0.5 + 0.07)), OLIVE_D, Enum.Material.SmoothPlastic)
		piece(model, host, "LegStrap", Vector3.new(sz.X * 1.1, 0.08, sz.Z * 1.1), CFrame.new(0, sz.Y * 0.1, 0), BLACKISH, Enum.Material.Fabric)
		local side = region == "LeftLeg" and -1 or 1
		piece(model, host, "ThighPouch", Vector3.new(0.22, sz.Y * 0.18, sz.Z * 0.5), CFrame.new(side * sz.X * 0.6, sz.Y * 0.28, 0), OLIVE_D, Enum.Material.Fabric)
	end
end

local function breakPiece(model: Model, region: string, at: Vector3)
	local host = model:FindFirstChild(PART_OF[region])
	model:SetAttribute("Armor_" .. region, nil)
	if host and host:IsA("BasePart") then
		for _, d in host:GetChildren() do
			if d:IsA("BasePart") and d:GetAttribute("ArmorPiece") then
				for _, w in d:GetChildren() do
					if w:IsA("WeldConstraint") then
						w:Destroy()
					end
				end
				d:SetAttribute("ArmorPiece", nil)
				d.Massless = false
				d.CanCollide = true
				d.Parent = workspace
				d.AssemblyLinearVelocity = Vector3.new(math.random() - 0.5, 0.5 + math.random(), math.random() - 0.5) * 22
				d.AssemblyAngularVelocity = Vector3.new(math.random(), math.random(), math.random()) * 12
				Debris:AddItem(d, 3.5)
			end
		end
	end
	pcall(function()
		deps.GoreService.Sound("ricochet", at, 1)
	end)
end

-- put the whole set on (every piece new: 30 hits)
function ArmorService.Equip(model: Model)
	for _, r in ORDER do
		model:SetAttribute("Armor_" .. r, ARMOR_HITS)
		dress(model, r)
	end
	status(model)
end

-- how many hits are left on a body part (0 = none)
function ArmorService.Hits(model: Model, region: string): number
	local h = model:GetAttribute("Armor_" .. region)
	return typeof(h) == "number" and h or 0
end

function ArmorService.Init(d: any)
	deps = d
	local DamageService = deps.DamageService
	-- bullets: the same hook the Wonder shield uses
	local prev = DamageService.ShieldBullet
	DamageService.ShieldBullet = function(model: Model, region: string, point: Vector3, dir: Vector3, shooter: Player?)
		if prev and prev(model, region, point, dir, shooter) then
			return true
		end
		local hits = model:GetAttribute("Armor_" .. region)
		if typeof(hits) ~= "number" or hits <= 0 then
			return false
		end
		local host = model:FindFirstChild(PART_OF[region])
		local cover = COVER[region]
		if not host or not host:IsA("BasePart") or not cover then
			return false
		end
		if not cover(host.CFrame:PointToObjectSpace(point), host.Size) then
			return false -- one of the small open places: the bullet goes through
		end
		hits -= 1
		model:SetAttribute("Armor_" .. region, hits)
		pcall(function()
			deps.GoreService.Sound("ricochet", point, 1)
		end)
		if hits <= 0 then
			breakPiece(model, region, point)
		end
		status(model)
		return true
	end

	-- the item is fitted like a prosthetic (the same bar, Config.ArmorEquipTime s): then the whole set is on and the item is used up
	deps.GearService.OnArmor = function(p: Player, target: Model, item: Model)
		local char = p.Character
		if char ~= target or not char or char:GetAttribute("Dead") == true then
			return
		end
		pcall(deps.OwnershipService.DropItem, item)
		item:Destroy()
		ArmorService.Equip(char)
		pcall(function()
			deps.GoreService.Sound("metal", char:FindFirstChild("Torso"), 1)
		end)
	end

	-- a new body wears nothing
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function()
			p:SetAttribute("ArmorStatus", nil)
		end)
	end)
end

return ArmorService
