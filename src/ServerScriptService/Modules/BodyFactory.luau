--!nonstrict
-- BodyFactory: builds a classic blocky R6 body from scratch.
-- Used for ragdoll dummies and as a fallback when avatar loading fails.

local BodyFactory = {}

local DEFAULT_COLORS = {
	Head = Color3.fromRGB(245, 205, 48),
	Torso = Color3.fromRGB(13, 105, 172),
	Arms = Color3.fromRGB(245, 205, 48),
	Legs = Color3.fromRGB(164, 189, 71),
}

BodyFactory.DEFAULT_COLORS = DEFAULT_COLORS -- (the ragdoll dummy's colours; the Steel Ball Master wears them too)

local function bodyPart(name: string, size: Vector3, color: Color3, cf: CFrame, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.CFrame = cf
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

function BodyFactory.BuildR6(opts: { name: string, humanoid: boolean, colors: { [string]: Color3 }? }): Model
	local colors = opts.colors or DEFAULT_COLORS
	local model = Instance.new("Model")
	model.Name = opts.name

	local root = CFrame.new(0, 3, 0)
	local torso = bodyPart("Torso", Vector3.new(2, 2, 1), colors.Torso, root, model)
	local head = bodyPart("Head", Vector3.new(2, 1, 1), colors.Head, root * CFrame.new(0, 1.5, 0), model)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head

	bodyPart("Left Arm", Vector3.new(1, 2, 1), colors.Arms, root * CFrame.new(-1.5, 0, 0), model)
	bodyPart("Right Arm", Vector3.new(1, 2, 1), colors.Arms, root * CFrame.new(1.5, 0, 0), model)
	bodyPart("Left Leg", Vector3.new(1, 2, 1), colors.Legs, root * CFrame.new(-0.5, -2, 0), model)
	bodyPart("Right Leg", Vector3.new(1, 2, 1), colors.Legs, root * CFrame.new(0.5, -2, 0), model)

	if opts.humanoid then
		local hrp = bodyPart("HumanoidRootPart", Vector3.new(2, 2, 1), Color3.new(1, 1, 1), root, model)
		hrp.Transparency = 1
		hrp.CanCollide = false
		local rootJoint = Instance.new("Motor6D")
		rootJoint.Name = "RootJoint"
		rootJoint.Part0 = hrp
		rootJoint.Part1 = torso
		rootJoint.Parent = hrp
		local neck = Instance.new("Motor6D")
		neck.Name = "Neck"
		neck.Part0 = torso
		neck.Part1 = head
		neck.C0 = CFrame.new(0, 1, 0)
		neck.C1 = CFrame.new(0, -0.5, 0)
		neck.Parent = torso
		local hum = Instance.new("Humanoid")
		hum.RigType = Enum.HumanoidRigType.R6
		-- (v2.0) no Roblox name / health over NPCs (it shows through walls): TitleClient draws a tag walls hide
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.Parent = model
		model.PrimaryPart = hrp
	else
		local neck = Instance.new("Weld")
		neck.Name = "Neck"
		neck.Part0 = torso
		neck.Part1 = head
		neck.C0 = CFrame.new(0, 1, 0)
		neck.C1 = CFrame.new(0, -0.5, 0)
		neck.Parent = torso
		model.PrimaryPart = torso
	end
	return model
end

return BodyFactory
