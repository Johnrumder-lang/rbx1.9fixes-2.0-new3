--!nonstrict
-- RigInfo: R6 joint layout used by the server rig builder, the client controller and the damage code.

local RigInfo = {}

export type LimbDef = {
	key: string, -- "LeftArm"
	partName: string, -- "Left Arm"
	kind: string, -- "Arm" | "Leg"
	side: number, -- -1 left, 1 right
	torsoPivot: Vector3, -- joint position in torso space
	limbPivot: Vector3, -- same point in limb space
	tip: Vector3, -- hand / sole in limb space
	motorName: string,
	upperAngle: number,
	twist: number,
}

RigInfo.Limbs = {
	{
		key = "LeftArm",
		partName = "Left Arm",
		kind = "Arm",
		side = -1,
		torsoPivot = Vector3.new(-1.5, 0.5, 0),
		limbPivot = Vector3.new(0, 0.5, 0),
		tip = Vector3.new(0, -1, 0),
		motorName = "Left Shoulder",
		upperAngle = 170,
		twist = 70,
	},
	{
		key = "RightArm",
		partName = "Right Arm",
		kind = "Arm",
		side = 1,
		torsoPivot = Vector3.new(1.5, 0.5, 0),
		limbPivot = Vector3.new(0, 0.5, 0),
		tip = Vector3.new(0, -1, 0),
		motorName = "Right Shoulder",
		upperAngle = 170,
		twist = 70,
	},
	{
		key = "LeftLeg",
		partName = "Left Leg",
		kind = "Leg",
		side = -1,
		torsoPivot = Vector3.new(-0.5, -1, 0),
		limbPivot = Vector3.new(0, 1, 0),
		tip = Vector3.new(0, -1, 0),
		motorName = "Left Hip",
		upperAngle = 95,
		twist = 35,
	},
	{
		key = "RightLeg",
		partName = "Right Leg",
		kind = "Leg",
		side = 1,
		torsoPivot = Vector3.new(0.5, -1, 0),
		limbPivot = Vector3.new(0, 1, 0),
		tip = Vector3.new(0, -1, 0),
		motorName = "Right Hip",
		upperAngle = 95,
		twist = 35,
	},
} :: { LimbDef }

RigInfo.ByKey = {} :: { [string]: LimbDef }
RigInfo.ByPartName = {} :: { [string]: LimbDef }
for _, def in RigInfo.Limbs do
	RigInfo.ByKey[def.key] = def
	RigInfo.ByPartName[def.partName] = def
end

-- Every body region that has its own health value.
RigInfo.Regions = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
RigInfo.RegionPart = {
	Head = "Head",
	Torso = "Torso",
	LeftArm = "Left Arm",
	RightArm = "Right Arm",
	LeftLeg = "Left Leg",
	RightLeg = "Right Leg",
}
-- How a pistol sits in the hand, in arm space: the frame looks down the arm (-Y) and its top is
-- the front of the arm (-Z). The gun's GripAttachment is matched to this frame, so the barrel
-- always points where the arm points. Used by the server weld AND the client's instant weld.
RigInfo.GunHandCFrame = CFrame.fromMatrix(Vector3.new(0, -0.95, -0.05), Vector3.new(1, 0, 0), Vector3.new(0, 0, -1), Vector3.new(0, 1, 0))

RigInfo.PartRegion = {
	["Head"] = "Head",
	["Torso"] = "Torso",
	["Left Arm"] = "LeftArm",
	["Right Arm"] = "RightArm",
	["Left Leg"] = "LeftLeg",
	["Right Leg"] = "RightLeg",
}
RigInfo.DisplayName = {
	Head = "Head",
	Torso = "Torso",
	LeftArm = "Left arm",
	RightArm = "Right arm",
	LeftLeg = "Left leg",
	RightLeg = "Right leg",
}

-- Ball-socket attachments use their X axis as the cone axis.
-- We point X straight down the limb so the cone limits swing and twist limits spin.
RigInfo.SocketRotation = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, -1, 0), Vector3.new(1, 0, 0))

-- Point on the surface of an axis-aligned box (size) in the direction dir (local space).
function RigInfo.LeadingPoint(cf: CFrame, size: Vector3, worldDir: Vector3): Vector3
	if worldDir.Magnitude < 1e-3 then
		return cf.Position
	end
	local d = cf:VectorToObjectSpace(worldDir.Unit)
	local half = size * 0.5
	local t = math.huge
	if math.abs(d.X) > 1e-4 then
		t = math.min(t, half.X / math.abs(d.X))
	end
	if math.abs(d.Y) > 1e-4 then
		t = math.min(t, half.Y / math.abs(d.Y))
	end
	if math.abs(d.Z) > 1e-4 then
		t = math.min(t, half.Z / math.abs(d.Z))
	end
	if t == math.huge then
		t = 0
	end
	return cf:PointToWorldSpace(d * t)
end

-- Torso and head are one rigid assembly; decide which of the two took a hit.
function RigInfo.ClassifyTorsoHit(torsoCF: CFrame, worldDir: Vector3): (string, Vector3)
	-- combined box: torso (2x2x1) + head (2x1x1) on top -> centre shifted up 0.5, height 3
	local box = torsoCF * CFrame.new(0, 0.5, 0)
	local p = RigInfo.LeadingPoint(box, Vector3.new(2, 3, 1), worldDir)
	local localY = torsoCF:PointToObjectSpace(p).Y
	if localY > 1.05 then
		return "Head", p
	end
	return "Torso", p
end

return RigInfo
