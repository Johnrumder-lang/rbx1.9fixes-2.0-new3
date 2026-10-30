--!nonstrict
-- RigBuilder: turns an R6 model into an active ragdoll.
--   * shoulders / hips become BallSocketConstraints with anatomical limits
--   * every limb gets an AlignOrientation "muscle" driven by the owning client
--   * torso gets a Balance AlignOrientation and a Drive VectorForce
--   * invisible colliders make limbs collide even though Humanoids disable limb collisions

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))

local RigBuilder = {}

-- (v2.8) every ragdoll body is in the "Body" collision group: crater rubble ("Crater") lies in the way of props and cars,
-- but bodies walk straight through it (nobody gets stuck on a crater any more)
local PhysicsService = game:GetService("PhysicsService")
pcall(function()
	PhysicsService:RegisterCollisionGroup("Body")
	PhysicsService:RegisterCollisionGroup("Crater")
	PhysicsService:CollisionGroupSetCollidable("Crater", "Body", false)
end)
-- (v2.8.2) a body somebody has grabbed / carries is "Carried": it goes through every other body (nobody bumps into it,
-- nobody walks on it), the world still holds it
pcall(function()
	PhysicsService:RegisterCollisionGroup("Carried")
	PhysicsService:CollisionGroupSetCollidable("Carried", "Body", false)
	PhysicsService:CollisionGroupSetCollidable("Carried", "Carried", false)
	PhysicsService:CollisionGroupSetCollidable("Carried", "Crater", false)
end)

-- (v2.8.2) a grabbed body: through every other body while it is held; back to "Body" when it is let go
function RigBuilder.SetCarried(model: Instance, on: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and (d.CollisionGroup == "Body" or d.CollisionGroup == "Carried") then
			d.CollisionGroup = on and "Carried" or "Body"
		end
	end
end

function RigBuilder.SetBodyGroup(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Body"
		end
	end
end

local LIMB_PROPS = PhysicalProperties.new(0.7, 0.35, 0, 1, 1)
local LEG_PROPS = PhysicalProperties.new(0.7, 0.25, 0, 1, 1)
local TORSO_PROPS = PhysicalProperties.new(0.7, 0.45, 0, 1, 1)

local function newAttachment(name: string, parent: BasePart, cf: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = parent
	return a
end

local function makeCollider(part: BasePart, props: PhysicalProperties, shrink: number): BasePart
	local c = Instance.new("Part")
	c.Name = "Collider"
	c.Size = part.Size * shrink
	c.CFrame = part.CFrame
	c.Transparency = 1
	c.CanCollide = true
	c.CanTouch = false
	c.CanQuery = true -- so others can stand on / grab you (own probes exclude the character)
	c.CastShadow = false
	c.Massless = true
	c.CustomPhysicalProperties = props
	c.TopSurface = Enum.SurfaceType.Smooth
	c.BottomSurface = Enum.SurfaceType.Smooth
	local w = Instance.new("WeldConstraint")
	w.Part0 = part
	w.Part1 = c
	w.Parent = c
	c.Parent = part
	return c
end

-- opts.colliders: add invisible collider parts (needed for Humanoid characters)
-- opts.muscles: create muscle constraints (player characters); dummies are pure ragdolls
function RigBuilder.Build(model: Model, opts: { colliders: boolean, muscles: boolean })
	local torso = model:FindFirstChild("Torso") :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart
	assert(torso and head, "R6 rig needs Torso and Head")

	local rig = Instance.new("Folder")
	rig.Name = "Rig"

	torso.CustomPhysicalProperties = TORSO_PROPS
	head.CustomPhysicalProperties = TORSO_PROPS

	-- HumanoidRootPart: keep it (camera / networking anchor) but make it weightless.
	local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.CanCollide = false
		hrp.CanQuery = false
		hrp.CanTouch = false
		hrp.Transparency = 1
		hrp.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0, 0, 1, 1)
	end

	-- Accessories must not add weight or collide.
	for _, d in model:GetDescendants() do
		if d:IsA("Accessory") then
			local handle = d:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				handle.Massless = true
				handle.CanCollide = false
				handle.CanTouch = false
				handle.CanQuery = false
			end
		end
	end

	local groups = {} -- list of { parts } that are rigid with each other
	local core = { torso, head }

	local colliders = {}
	if opts.colliders then
		torso.CanCollide = false
		head.CanCollide = false
		local ct = makeCollider(torso, TORSO_PROPS, 0.98)
		local ch = makeCollider(head, TORSO_PROPS, 0.95)
		table.insert(core, ct)
		table.insert(core, ch)
		colliders.Torso = ct
		colliders.Head = ch
	end
	table.insert(groups, core)

	for _, def in RigInfo.Limbs do
		local limb = model:FindFirstChild(def.partName) :: BasePart?
		if not limb then
			continue
		end

		local motor = torso:FindFirstChild(def.motorName)
		if motor then
			motor:Destroy()
		end

		local props = def.kind == "Leg" and LEG_PROPS or LIMB_PROPS
		limb.CustomPhysicalProperties = props

		-- Place the limb exactly at its rest pose relative to the torso (before welding colliders).
		limb.CFrame = torso.CFrame * CFrame.new(def.torsoPivot) * CFrame.new(-def.limbPivot)

		local group = { limb }
		if opts.colliders then
			limb.CanCollide = false
			local c = makeCollider(limb, props, 0.96)
			table.insert(group, c)
			colliders[def.key] = c
		else
			limb.CanCollide = true
		end
		table.insert(groups, group)

		-- Skeleton joint
		local jT = newAttachment("J_" .. def.key, torso, CFrame.new(def.torsoPivot) * RigInfo.SocketRotation)
		local jL = newAttachment("J", limb, CFrame.new(def.limbPivot) * RigInfo.SocketRotation)
		local socket = Instance.new("BallSocketConstraint")
		socket.Name = "Joint_" .. def.key
		socket.Attachment0 = jL
		socket.Attachment1 = jT
		socket.LimitsEnabled = true
		socket.UpperAngle = def.upperAngle
		socket.TwistLimitsEnabled = true
		socket.TwistLowerAngle = -def.twist
		socket.TwistUpperAngle = def.twist
		socket.Restitution = 0
		socket.MaxFrictionTorque = Config.JointFriction
		socket.Parent = rig

		-- Muscle (driven by the client every frame)
		if opts.muscles then
			local mT = newAttachment("M_" .. def.key, torso, CFrame.new(def.torsoPivot))
			local mL = newAttachment("M", limb, CFrame.new(def.limbPivot))
			local muscle = Instance.new("AlignOrientation")
			muscle.Name = "Muscle_" .. def.key
			muscle.Mode = Enum.OrientationAlignmentMode.TwoAttachment
			muscle.Attachment0 = mL
			muscle.Attachment1 = mT
			muscle.RigidityEnabled = false
			muscle.ReactionTorqueEnabled = true
			local isLeg = def.kind == "Leg"
			muscle.MaxTorque = isLeg and Config.LegMuscleTorque or Config.ArmMuscleTorque
			muscle.Responsiveness = isLeg and Config.LegMuscleResponsiveness or Config.ArmMuscleResponsiveness
			muscle.MaxAngularVelocity = Config.MuscleMaxAngularVelocity
			muscle.Enabled = true
			muscle.Parent = rig
		end
	end

	-- No self collisions between body groups.
	local parts = {}
	for gi, group in groups do
		for _, p in group do
			table.insert(parts, { part = p, group = gi })
		end
	end
	for i = 1, #parts do
		for j = i + 1, #parts do
			if parts[i].group ~= parts[j].group then
				local nc = Instance.new("NoCollisionConstraint")
				nc.Part0 = parts[i].part
				nc.Part1 = parts[j].part
				nc.Parent = rig
			end
		end
	end

	if opts.muscles then
		local bal = newAttachment("BalanceAttachment", torso, CFrame.identity)
		local balance = Instance.new("AlignOrientation")
		balance.Name = "Balance"
		balance.Mode = Enum.OrientationAlignmentMode.OneAttachment
		balance.Attachment0 = bal
		balance.RigidityEnabled = false
		balance.MaxTorque = Config.BalanceTorque
		balance.Responsiveness = Config.BalanceResponsiveness
		balance.CFrame = CFrame.identity
		-- on from the start: until the client takes over, the body stands on its stiff legs
		balance.Enabled = true
		balance.Parent = rig

		local drive = Instance.new("VectorForce")
		drive.Name = "Drive"
		drive.Attachment0 = bal
		drive.RelativeTo = Enum.ActuatorRelativeTo.World
		drive.ApplyAtCenterOfMass = true
		drive.Force = Vector3.zero
		drive.Enabled = true
		drive.Parent = rig
	end

	-- health bookkeeping lives in attributes so every client can read it
	for _, region in RigInfo.Regions do
		model:SetAttribute("HP_" .. region, Config.LimbMaxHP)
		model:SetAttribute("Broken_" .. region, false)
		model:SetAttribute("Severed_" .. region, false)
	end
	model:SetAttribute("Blood", 100)
	model:SetAttribute("Dead", false)
	model:SetAttribute("RagdollRig", true)

	rig.Parent = model
	RigBuilder.SetBodyGroup(model)
	model.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") and d.CollisionGroup == "Default" then
			d.CollisionGroup = "Body"
		end
	end)
	return rig
end

-- (v2.0) a new limb where one was cut off (a prosthetic). The old limb stays where it lies (as a loose piece of
-- gore); a fresh part takes its place at the rest pose with a joint, a muscle (players), a collider and no
-- collisions with the rest of the body. `dress` gets the new part to put the prosthetic's look on it.
function RigBuilder.Reattach(model: Model, key: string, dress: ((BasePart) -> ())?): BasePart?
	local def = RigInfo.ByKey[key]
	local torso = model:FindFirstChild("Torso") :: BasePart?
	local rig = model:FindFirstChild("Rig")
	if not def or not torso or not rig then
		return nil
	end
	-- the old one is just a piece of meat on the floor now
	local old = model:FindFirstChild(def.partName)
	if old then
		old.Name = def.partName .. " (severed)"
		old.Parent = workspace:FindFirstChild("FX") or workspace
		task.delay(60, function()
			if old.Parent then
				old:Destroy()
			end
		end)
	end
	-- the open stump on the torso is covered by the socket
	local stumpAt = def.kind == "Arm" and Vector3.new(def.side * 1.0, 0.45, 0) or Vector3.new(def.side * 0.5, -1.0, 0)
	local gore = torso:FindFirstChild("Gore")
	if gore then
		for _, g in gore:GetChildren() do
			if g:IsA("BasePart") and (torso.CFrame:PointToObjectSpace(g.Position) - stumpAt).Magnitude < 0.7 then
				g:Destroy()
			end
		end
	end
	for _, n in { "J_" .. key, "M_" .. key } do
		local a = torso:FindFirstChild(n)
		if a then
			a:Destroy()
		end
	end
	for _, n in { "Joint_" .. key, "Muscle_" .. key } do
		local j = rig:FindFirstChild(n)
		if j then
			j:Destroy()
		end
	end

	local props = def.kind == "Leg" and LEG_PROPS or LIMB_PROPS
	local limb = Instance.new("Part")
	limb.Name = def.partName
	limb.Size = Vector3.new(1, 2, 1)
	limb.Color = Color3.fromRGB(60, 62, 68)
	limb.Material = Enum.Material.Metal
	limb.Transparency = dress and 1 or 0
	limb.TopSurface = Enum.SurfaceType.Smooth
	limb.BottomSurface = Enum.SurfaceType.Smooth
	limb.CustomPhysicalProperties = props
	limb.CFrame = torso.CFrame * CFrame.new(def.torsoPivot) * CFrame.new(-def.limbPivot)
	local hasColliders = torso:FindFirstChild("Collider") ~= nil
	limb.CanCollide = not hasColliders
	limb.Parent = model
	if dress then
		dress(limb)
	end
	local parts: { BasePart } = { limb }
	if hasColliders then
		table.insert(parts, makeCollider(limb, props, 0.96))
	end
	local jT = newAttachment("J_" .. key, torso, CFrame.new(def.torsoPivot) * RigInfo.SocketRotation)
	local jL = newAttachment("J", limb, CFrame.new(def.limbPivot) * RigInfo.SocketRotation)
	local socket = Instance.new("BallSocketConstraint")
	socket.Name = "Joint_" .. key
	socket.Attachment0 = jL
	socket.Attachment1 = jT
	socket.LimitsEnabled = true
	socket.UpperAngle = def.upperAngle
	socket.TwistLimitsEnabled = true
	socket.TwistLowerAngle = -def.twist
	socket.TwistUpperAngle = def.twist
	socket.Restitution = 0
	socket.MaxFrictionTorque = Config.JointFriction
	socket.Parent = rig
	if rig:FindFirstChild("Balance") then
		local mT = newAttachment("M_" .. key, torso, CFrame.new(def.torsoPivot))
		local mL = newAttachment("M", limb, CFrame.new(def.limbPivot))
		local muscle = Instance.new("AlignOrientation")
		muscle.Name = "Muscle_" .. key
		muscle.Mode = Enum.OrientationAlignmentMode.TwoAttachment
		muscle.Attachment0 = mL
		muscle.Attachment1 = mT
		muscle.RigidityEnabled = false
		muscle.ReactionTorqueEnabled = true
		local isLeg = def.kind == "Leg"
		muscle.MaxTorque = isLeg and Config.LegMuscleTorque or Config.ArmMuscleTorque
		muscle.Responsiveness = isLeg and Config.LegMuscleResponsiveness or Config.ArmMuscleResponsiveness
		muscle.MaxAngularVelocity = Config.MuscleMaxAngularVelocity
		muscle.Enabled = not model:GetAttribute("Dead")
		muscle.Parent = rig
	end
	-- never collides with the rest of the body
	for _, other in model:GetDescendants() do
		if other:IsA("BasePart") and other ~= limb and other.Parent ~= limb and (other.Parent == model or other.Name == "Collider") then
			for _, mine in parts do
				local nc = Instance.new("NoCollisionConstraint")
				nc.Part0 = mine
				nc.Part1 = other
				nc.Parent = rig
			end
		end
	end
	model:SetAttribute("Severed_" .. key, false)
	model:SetAttribute("Broken_" .. key, false)
	model:SetAttribute("HP_" .. key, Config.LimbMaxHP)
	model:SetAttribute("Prosthetic_" .. key, true)
	return limb
end

-- Turn the muscles back on (after being dragged around by another player).
function RigBuilder.Restore(model: Model)
	local rig = model:FindFirstChild("Rig")
	if not rig then
		return
	end
	for _, c in rig:GetChildren() do
		if c:IsA("AlignOrientation") or c:IsA("VectorForce") then
			c.Enabled = true
		end
	end
end

-- Turn every muscle and the balance off (death / corpse).
function RigBuilder.GoLimp(model: Model)
	local rig = model:FindFirstChild("Rig")
	if not rig then
		return
	end
	for _, c in rig:GetChildren() do
		if c:IsA("AlignOrientation") then
			c.Enabled = false
		elseif c:IsA("VectorForce") then
			c.Force = Vector3.zero
			c.Enabled = false
		end
	end
end

return RigBuilder
