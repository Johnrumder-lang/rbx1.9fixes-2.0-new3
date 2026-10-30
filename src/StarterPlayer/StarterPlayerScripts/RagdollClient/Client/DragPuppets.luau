--!nonstrict
-- DragPuppets (v2.0): how a dragged player looks on every screen but their own.
--
-- The dragged body stays its own player's: Roblox keeps a player's character with that player, so their client
-- pulls it to the dragger's hand (DragClient). Everybody else would see that body arrive late - on the dragger's
-- screen twice the network delay behind the hand (the "magnet", the stretched arm, the body that does not follow).
-- So every other machine hides the real body while it is dragged and shows a local limp copy of it instead,
-- simulated right here and hanging exactly from the dragger's hand. When the drag ends the copy goes and the real
-- body (pulled to the same hand all along) shows again.
--   * a limb cut off while dragged: the copy loses it too, and the real (loose) limb shows again
--   * the copy never collides with the dragger or the hidden real body; shots, grabs and rays ignore it
--   * physics gun drags (DragBeam) keep the plain pull (the beam end is no hand)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))

local player = Players.LocalPlayer

local DragPuppets = {}

type Puppet = {
	real: Model,
	model: Model,
	by: number,
	partName: string,
	map: { [BasePart]: BasePart },
	ap: AlignPosition?,
	att: Attachment?,
	hidden: { [Instance]: any },
	freed: { [Instance]: boolean },
	conns: { RBXScriptConnection },
	nocolFor: Model?,
}

local puppets: { [Model]: Puppet } = {}
local folder: Folder? = nil

-- what the copy keeps of the rig's constraints (the joints); muscles, drives and forces go
local KEEP = {
	BallSocketConstraint = true,
	HingeConstraint = true,
	NoCollisionConstraint = true,
	WeldConstraint = true,
	RigidConstraint = true,
}

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "DragPuppets"
	f.Parent = workspace
	folder = f
	return f
end

local function collidable(p: BasePart): boolean
	-- (v2.8.1) the limbs too: they only collide while limp (the puppet hung from your hand and you could stand on it)
	return p.CanCollide or p.Name == "Collider" or (p.Parent ~= nil and p.Parent:IsA("Model") and p.Parent:FindFirstChildOfClass("Humanoid") ~= nil)
end

local function hideOne(pp: Puppet, d: Instance)
	if pp.hidden[d] ~= nil or pp.freed[d] then
		return
	end
	if d:IsA("BasePart") or d:IsA("Decal") then
		pp.hidden[d] = true
		local dd: any = d
		dd.LocalTransparencyModifier = 1
	elseif d:IsA("SurfaceGui") then
		pp.hidden[d] = d.Enabled
		d.Enabled = false
	end
end

local function showOne(d: Instance, was: any)
	if not d.Parent then
		return
	end
	if d:IsA("BasePart") or d:IsA("Decal") then
		local dd: any = d
		dd.LocalTransparencyModifier = 0
	elseif d:IsA("SurfaceGui") then
		d.Enabled = was == true
	end
end

-- the copy: the real body as it is now, stripped to a plain limp ragdoll that only this screen simulates
local function makeCopy(real: Model): Model?
	local ok, copy = pcall(function()
		local was = real.Archivable
		real.Archivable = true
		local c = real:Clone()
		real.Archivable = was
		return c
	end)
	if not ok or not copy then
		return nil
	end
	local c = copy :: Model
	-- nothing else on this machine may take the copy for a body (no tags, no attributes)
	for _, inst in { c, table.unpack(c:GetDescendants()) } do
		for _, tag in CollectionService:GetTags(inst) do
			CollectionService:RemoveTag(inst, tag)
		end
	end
	for k in c:GetAttributes() do
		c:SetAttribute(k, nil)
	end
	for _, d in c:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("BillboardGui") or d:IsA("Sound") or d:IsA("ParticleEmitter") or d:IsA("Trail")
			or d:IsA("Beam") or d:IsA("Light") or d:IsA("ProximityPrompt") or d:IsA("Highlight") or d:IsA("BodyMover")
			or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") or (d:IsA("Folder") and d.Name == "DragNoCollide") then
			d:Destroy()
		elseif d:IsA("Constraint") and not KEEP[d.ClassName] then
			d:Destroy()
		end
	end
	for _, d in c:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanQuery = false
			d.CanTouch = false
			d.LocalTransparencyModifier = 0
			local cur = d.CurrentPhysicalProperties
			d.CustomPhysicalProperties = PhysicalProperties.new(cur.Density, Config.DragFriction, cur.Elasticity, 100, cur.ElasticityWeight)
		end
	end
	local hum = c:FindFirstChildOfClass("Humanoid")
	if hum then
		-- (kept for the clothes; it must never stand the copy up or kill it)
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.RequiresNeck = false
		hum.BreakJointsOnDeath = false
		pcall(function()
			hum.EvaluateStateMachine = false
		end)
		for _, st in Enum.HumanoidStateType:GetEnumItems() do
			if st ~= Enum.HumanoidStateType.None and st ~= Enum.HumanoidStateType.Physics then
				pcall(function()
					hum:SetStateEnabled(st, false)
				end)
			end
		end
	end
	c.Name = "DragPuppet"
	return c
end

local function handOf(by: number, side: string): Vector3?
	local p = Players:GetPlayerByUserId(by)
	local char = p and p.Character
	if not char then
		return nil
	end
	local arm = char:FindFirstChild(side == "Left" and "Left Arm" or "Right Arm")
	if arm and arm:IsA("BasePart") and not char:GetAttribute("Severed_" .. (side == "Left" and "LeftArm" or "RightArm")) then
		return arm.CFrame:PointToWorldSpace(Vector3.new(0, -1, 0)) -- (the grip point of Hands)
	end
	local torso = char:FindFirstChild("Torso")
	return (torso and torso:IsA("BasePart")) and torso.Position or nil
end

local function remove(real: Model)
	local pp = puppets[real]
	if not pp then
		return
	end
	puppets[real] = nil
	for _, c in pp.conns do
		c:Disconnect()
	end
	for d, was in pp.hidden do
		showOne(d, was)
	end
	pp.model:Destroy()
end

-- the copy must not bump into the dragger's body or the hidden real one
local function noCollide(pp: Puppet, char: Model?)
	local others = {}
	for _, m in { pp.real, char } do
		if m then
			for _, p in m:GetDescendants() do
				if p:IsA("BasePart") and collidable(p) then
					table.insert(others, p)
				end
			end
		end
	end
	local nc = Instance.new("Folder")
	nc.Name = "NoCollide"
	for _, a in pp.model:GetDescendants() do
		if a:IsA("BasePart") and collidable(a) then
			for _, b in others do
				local n = Instance.new("NoCollisionConstraint")
				n.Part0 = a
				n.Part1 = b
				n.Parent = nc
			end
		end
	end
	local old = pp.model:FindFirstChild("NoCollide")
	if old then
		old:Destroy()
	end
	nc.Parent = pp.model
	pp.nocolFor = char
end

local function attach(pp: Puppet, partName: string, lp: Vector3)
	if pp.ap then
		pp.ap:Destroy()
	end
	if pp.att then
		pp.att:Destroy()
	end
	pp.ap = nil
	pp.att = nil
	local part = pp.model:FindFirstChild(partName)
	if not (part and part:IsA("BasePart")) then
		part = pp.model:FindFirstChild("Torso")
	end
	if not (part and part:IsA("BasePart")) then
		return
	end
	if lp.Magnitude > part.Size.Magnitude then
		lp = Vector3.zero
	end
	local att = Instance.new("Attachment")
	att.Name = "PuppetGrip"
	att.Position = lp
	att.Parent = part
	local ap = Instance.new("AlignPosition")
	ap.Name = "PuppetHand"
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.Position = att.WorldPosition
	ap.RigidityEnabled = true -- (it hangs exactly from the hand, like a dummy on a ball joint)
	ap.Parent = part
	pp.att = att
	pp.ap = ap
	pp.partName = partName
end

local function create(real: Model, by: number)
	local copy = makeCopy(real)
	if not copy then
		return
	end
	local pp: Puppet = {
		real = real,
		model = copy,
		by = by,
		partName = "",
		map = {},
		ap = nil,
		att = nil,
		hidden = {},
		freed = {},
		conns = {},
		nocolFor = nil,
	}
	for _, d in real:GetChildren() do
		if d:IsA("BasePart") then
			local twin = copy:FindFirstChild(d.Name)
			if twin and twin:IsA("BasePart") then
				pp.map[d] = twin
				twin.AssemblyLinearVelocity = d.AssemblyLinearVelocity
			end
		end
	end
	copy.Parent = getFolder()
	puppets[real] = pp
	for _, d in real:GetDescendants() do
		hideOne(pp, d)
	end
	table.insert(pp.conns, real.DescendantAdded:Connect(function(d)
		task.defer(function()
			if puppets[real] == pp and d:IsDescendantOf(real) then
				hideOne(pp, d)
			end
		end)
	end))
	local lp = real:GetAttribute("DragPoint")
	attach(pp, tostring(real:GetAttribute("DragPart") or "Torso"), typeof(lp) == "Vector3" and lp or Vector3.zero)
	local p = Players:GetPlayerByUserId(by)
	noCollide(pp, p and p.Character)
end

-- a limb the real body lost while it was dragged: gone from the copy, and the real one (lying loose) shows again
local function syncLimbs(pp: Puppet)
	for key, def in RigInfo.ByKey do
		if pp.real:GetAttribute("Severed_" .. key) then
			local twin = pp.model:FindFirstChild(def.partName)
			if twin then
				twin:Destroy()
				local realPart = pp.real:FindFirstChild(def.partName)
				if realPart then
					for _, d in { realPart, table.unpack(realPart:GetDescendants()) } do
						if pp.hidden[d] ~= nil then
							showOne(d, pp.hidden[d])
						end
						pp.hidden[d] = nil
						pp.freed[d] = true -- (never hidden again)
					end
				end
			end
		end
	end
	if pp.real:GetAttribute("Severed_Head") then
		local twin = pp.model:FindFirstChild("Head")
		if twin then
			twin:Destroy()
			local realHead = pp.real:FindFirstChild("Head")
			if realHead then
				for _, d in { realHead, table.unpack(realHead:GetDescendants()) } do
					if pp.hidden[d] ~= nil then
						showOne(d, pp.hidden[d])
					end
					pp.hidden[d] = nil
					pp.freed[d] = true
				end
			end
		end
	end
end

local function wanted(char: Model): number?
	if char == player.Character then
		return nil -- (my own body: I see the real one, pulled to the hand)
	end
	local by = char:GetAttribute("DraggedBy")
	if typeof(by) ~= "number" or char:GetAttribute("DragBeam") then
		return nil
	end
	if not char:IsDescendantOf(workspace) then
		return nil
	end
	return by
end

local function step()
	if not Config.DragPuppets then
		return
	end
	-- which bodies are dragged right now
	local seen: { [Model]: boolean } = {}
	for _, p in Players:GetPlayers() do
		local char = p.Character
		if char then
			local by = wanted(char)
			if by then
				seen[char] = true
				local pp = puppets[char]
				if pp and pp.by ~= by then
					remove(char)
					pp = nil
				end
				if not pp then
					create(char, by)
				end
			end
		end
	end
	for real in puppets do
		if not seen[real] then
			remove(real)
		end
	end
	for real, pp in puppets do
		if not pp.model.Parent then
			remove(real)
			continue
		end
		-- the hand / the grabbed part changed (the other hand took over)
		local partName = tostring(real:GetAttribute("DragPart") or "Torso")
		if partName ~= pp.partName then
			local lp = real:GetAttribute("DragPoint")
			attach(pp, partName, typeof(lp) == "Vector3" and lp or Vector3.zero)
		end
		local byPlayer = Players:GetPlayerByUserId(pp.by)
		local byChar = byPlayer and byPlayer.Character
		if byChar ~= pp.nocolFor then
			noCollide(pp, byChar)
		end
		syncLimbs(pp)
		local hand = handOf(pp.by, tostring(real:GetAttribute("DragSide") or "Right"))
		if hand and pp.ap then
			pp.ap.Position = hand
		end
		-- (things that keep setting the real parts back to visible: hidden again every frame)
		for d in pp.hidden do
			local dd: any = d
			if d.Parent and (d:IsA("BasePart") or d:IsA("Decal")) and dd.LocalTransparencyModifier ~= 1 then
				dd.LocalTransparencyModifier = 1
			end
		end
	end
end

-- the copy this screen shows for a dragged body (name tags hang over it), or nil
function DragPuppets.Of(real: Model): Model?
	local pp = puppets[real]
	return pp and pp.model or nil
end

function DragPuppets.Init()
	RunService.Stepped:Connect(step)
	Players.PlayerRemoving:Connect(function(p)
		if p.Character then
			remove(p.Character)
		end
	end)
end

return DragPuppets
