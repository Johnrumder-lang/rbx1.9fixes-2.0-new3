--!nonstrict
-- Hands (mixin for CharacterController): grabbing, hand aiming, items and climbing.
--
--   Q / E          close / open a hand. ONLY a closed hand grabs (whatever it touches).
--   LMB / RMB hold the arm follows the cursor (or the crosshair in first person / on gamepad).
--                  Pointing never grabs anything by itself.
--   Solid things   (walls, floor, anchored parts): NO joint to the world. A strong force holds the
--                  hand at the spot (AlignPosition, one attachment). Pulling the arm or climbing
--                  therefore moves YOUR BODY, never the wall, and nothing can lock the body.
--   Loose things   ball joint at the hand (you own them while you hold them).
--   Players        grabbing another player knocks them over. Their body stays THEIRS: their own
--                  client pulls it to your hand (no joint between two players, nobody changes
--                  owner), so they move with you and see you. Dummies / NPCs / corpses hang at your
--                  hand (ball joint) as before. Let go = it stays there.
--   Items          held rigidly (the server welds them too); the ARM aims them.
--                  F = use: fire / thrust / slash / swing / pull the pin / bandage / tie up (rope) /
--                      throw C4 / detonate / boombox / arm the nuke
--                  hold F: full auto, physics-gun beam.   hold G = aim the gun (sniper: scope).
--                  Let go of a grenade / C4 (Q/E) = throw it; let go of the spear while aiming = javelin.
--   Reloading      by hand: the FREE hand touches the gun (or the hand holding it) for the gun's reload
--                  time. Hold that hand's mouse button and point at your gun: the hand snaps to it and
--                  the gun comes in front of your chest. Two guns = no free hand = no reload.
--   Climbing       hold something solid + hold Space = pull yourself up (steady speed, never a lock).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TimeScale = require(Shared:WaitForChild("TimeScale"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))
local Items = require(Shared:WaitForChild("Items"))
local Ballistics = require(Shared:WaitForChild("Ballistics"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GripRemote = Remotes:WaitForChild("Grip") :: RemoteEvent
local GunRemote = Remotes:WaitForChild("Gun") :: RemoteEvent
local ItemRemote = Remotes:WaitForChild("Item") :: RemoteEvent

local Modules = script.Parent
local Input = require(Modules:WaitForChild("Input"))
local Cam = require(Modules:WaitForChild("CameraController"))

local player = Players.LocalPlayer
-- (v2.0) reload sounds per weapon: start (the hand touches it), mid (half way), done, after (a moment later)
type ReloadSteps = { start: string?, mid: string?, done: string, after: string? }
local RELOAD_STEPS: { [string]: ReloadSteps } = {
	default = { start = "magOut", mid = "magIn", done = "slideRack" },
	pistol = { start = "magOut", mid = "magIn", done = "slideRack" },
	usp = { start = "magOut", mid = "magIn", done = "slideRack" },
	revolver = { start = "gunMech", mid = "shellIn", done = "gunMech", after = "clink" },
	rifle = { start = "magOut", mid = "magIn", done = "bolt" },
	smg = { start = "magOut", mid = "magIn", done = "slideRack" },
	mp5 = { start = "magOut", mid = "magIn", done = "bolt" },
	minigun = { start = "magOut", mid = "metal", done = "ratchet" },
	shotgun = { start = "shellIn", mid = "shellIn", done = "pump" },
	sniper = { start = "bolt", mid = "magIn", done = "bolt" },
	garand = { start = "gunMech", mid = "magIn", done = "bolt" },
	crossbow = { start = "crossbowReload", done = "gunMech", after = "bowString" },
	launcher = { start = "metal", mid = "slideRack", done = "gunMech" },
	lockon = { start = "metal", mid = "slideRack", done = "lockBeep" },
	taser = { start = "gunMech", done = "zap" },
	harpoon = { start = "ratchet", mid = "metal", done = "gunMech" },
	flaregun = { start = "gunMech", mid = "shellIn", done = "gunMech" },
	sleepdart = { start = "gunMech", done = "blowdart" },
	healdart = { start = "gunMech", done = "blowdart" },
	paradart = { start = "gunMech", done = "blowdart" },
	smartpistol = { start = "magOut", mid = "magIn", done = "slideRack" },
	smartsmg = { start = "magOut", mid = "magIn", done = "slideRack" },
}

local SIDES = { "Left", "Right" }
local ARM_OF = { Left = "LeftArm", Right = "RightArm" }
local rng = Random.new()

local function bodyOf(inst: Instance): Model?
	local m = inst:FindFirstAncestorOfClass("Model")
	while m do
		if m:GetAttribute("RagdollRig") then
			return m
		end
		m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function regionOf(inst: Instance, body: Model): string?
	local p: Instance? = inst
	while p and p ~= body do
		local r = RigInfo.PartRegion[p.Name]
		if r then
			return r
		end
		p = p.Parent
	end
	return nil
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- distance from a point to the segment a-b
local function segmentDistance(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	if len2 < 1e-6 then
		return (p - a).Magnitude
	end
	local t = math.clamp((p - a):Dot(ab) / len2, 0, 1)
	return (p - (a + ab * t)).Magnitude
end

return function(Controller)
	----------------------------------------------------------------------
	-- filters
	----------------------------------------------------------------------

	function Controller:_heldInstances(): { Instance }
		local list = {}
		for _, side in SIDES do
			local g = self.hands[side].grip
			if g and g.part.Parent and not g.static then
				if g.item then
					table.insert(list, g.item)
				elseif g.body then
					table.insert(list, g.body)
				else
					table.insert(list, g.part.AssemblyRootPart or g.part)
				end
			end
		end
		if self.beam and self.beam.target and self.beam.target.Parent then
			table.insert(list, self.beam.model or self.beam.target)
		end
		return list
	end

	function Controller:_rebuildFilters()
		local ignore = { self.character }
		local fx = workspace:FindFirstChild("FX")
		if fx then
			table.insert(ignore, fx)
		end
		local grabIgnore = table.clone(ignore)
		local held = self:_heldInstances()
		for _, inst in held do
			table.insert(ignore, inst)
		end
		if self.car then
			table.insert(ignore, self.car)
			table.insert(grabIgnore, self.car)
		end
		if self.passenger then
			table.insert(ignore, self.passenger)
			table.insert(grabIgnore, self.passenger)
		end
		self.rayParams.FilterDescendantsInstances = ignore
		self.grabParams.FilterDescendantsInstances = grabIgnore
		self.overlapParams.FilterDescendantsInstances = grabIgnore
		local aimIgnore = { fx }
		for _, inst in held do
			table.insert(aimIgnore, inst)
		end
		self.aimParams.FilterDescendantsInstances = aimIgnore
		self.crushParams = self.crushParams or OverlapParams.new()
		self.crushParams.FilterType = Enum.RaycastFilterType.Exclude
		self.crushParams.FilterDescendantsInstances = ignore
	end

	local function isValidGrabTarget(self, inst: Instance?): boolean
		if not inst or not inst:IsA("BasePart") then
			return false
		end
		if inst:IsDescendantOf(self.character) then
			return false
		end
		local fx = workspace:FindFirstChild("FX")
		if fx and inst:IsDescendantOf(fx) then
			return false
		end
		if inst:GetAttribute("Gore") and not inst.CanCollide then
			return false
		end
		local item = Items.ModelOf(inst)
		if item then
			local holder = item:GetAttribute("HolderId")
			if not Items.MayUse(player, item) then
				return false
			end
			return holder == nil or holder == player.UserId
		end
		if not inst.CanCollide then
			local body = inst:FindFirstAncestorOfClass("Model")
			return body ~= nil and body:GetAttribute("RagdollRig") == true and RigInfo.PartRegion[inst.Name] ~= nil
		end
		return true
	end
	Controller._isValidGrabTarget = isValidGrabTarget

	local function isSolid(self, part: BasePart): boolean
		return part:IsGrounded() or part.AssemblyMass > self.bodyMass * Config.HeavyRatio
	end

	----------------------------------------------------------------------
	-- grabbing
	----------------------------------------------------------------------

	function Controller:_toggleHand(side: string)
		-- (v2.9) WEAPON GLITCH (a quickhack): the hand servos are jammed for a moment
		local lock = self.character:GetAttribute("ChipGrabLock")
		if typeof(lock) == "number" and workspace:GetServerTimeNow() < lock then
			return
		end
		if self.twoHand and self.twoHand.support == side then
			self:_dropTwoHand(true) -- Q / E on the supporting hand: it lets go
			return
		end
		local hand = self.hands[side]
		if hand.grip then
			self:_release(side, true)
			hand.armed = false
		elseif hand.armed then
			hand.armed = false
		elseif self:_limbUsable(ARM_OF[side]) and self.state ~= "Ragdoll" and not self.car then
			hand.armed = true
		end
	end

	-- hand frame on the arm: looks down the arm (-Y), up = front of the arm (-Z)
	Controller.GUN_HAND_CFRAME = RigInfo.GunHandCFrame

	function Controller:_gripItem(side: string, item: Model, serverAssigned: boolean?)
		local L = self.limbs[ARM_OF[side]]
		local hand = self.hands[side]
		local handle = item.PrimaryPart
		local gripAtt = handle and handle:FindFirstChild("GripAttachment")
		if not L or not handle or not gripAtt then
			return
		end
		if not Items.MayUse(player, item) then
			return
		end
		if self.character:GetAttribute("Zombie") then
			return -- (v2.0) zombies hold nothing
		end
		-- one hand per item
		for _, other in SIDES do
			local og = self.hands[other].grip
			if og and og.item == item then
				return
			end
		end
		-- rigid in the hand: forward along the arm, top = front of the arm. The server makes the same
		-- weld (so everyone sees it in the hand); this local one only makes it instant here.
		local a0 = Instance.new("Attachment")
		a0.Name = "ItemHand"
		a0.CFrame = RigInfo.GunHandCFrame
		a0.Parent = L.part
		local socket = Instance.new("RigidConstraint")
		socket.Name = "Grip"
		socket.Attachment0 = a0
		socket.Attachment1 = gripAtt
		-- the item never collides with your own body (children of the socket go with it)
		for _, ip in item:GetDescendants() do
			if ip:IsA("BasePart") then
				for _, bp in self.character:GetDescendants() do
					if bp:IsA("BasePart") and (bp.CanCollide or bp.Name == "Collider") then
						local nc = Instance.new("NoCollisionConstraint")
						nc.Part0 = ip
						nc.Part1 = bp
						nc.Parent = socket
					end
				end
			end
		end
		-- pinned in the world (a spear in the ground, a C4 on a wall): the server pulls it out in a
		-- moment. Until then the hand does not lock onto it (that would lock the hand to the world).
		-- (v2.0 fix) "pinned" also means joined to something pinned (a weld into a wall / the ground), not only anchored
		-- itself: before, a hand could lock onto such an item and the whole body was stuck to the world
		if handle.Anchored or handle:IsGrounded() then
			socket.Enabled = false
			task.spawn(function()
				local t0 = os.clock()
				while os.clock() - t0 < 1.6 do
					if not socket.Parent or not (hand.grip and hand.grip.item == item) then
						return
					end
					if not handle.Anchored and not handle:IsGrounded() then
						socket.Enabled = true
						return
					end
					task.wait()
				end
				-- (v1.9) it is still pinned: let go instead of staying locked to it
				if hand.grip and hand.grip.item == item then
					self:_release(side, false)
				end
			end)
		end
		socket.Parent = L.part
		local kind = Items.Kind(item)
		hand.grip = {
			part = handle,
			a0 = a0,
			a1 = gripAtt,
			keepA1 = true,
			socket = socket,
			item = item,
			gun = Items.IsGun(item) and item or nil,
			kind = kind,
			static = false,
			time = os.clock(),
			remote = true,
		}
		hand.armed = true
		if not serverAssigned then GripRemote:FireServer("grab", handle, side) end
		self.armSuppress[side] = os.clock() + 0.3
		SoundLibrary.Play("click", handle, 0.6)
		self:_rebuildFilters()
	end

	-- Infinite strength (flying admin): a loose thing (a car, the anvil, a barrel) is not hung on
	-- the arm but carried by movers that put the grabbed spot exactly into the hand and keep the
	-- thing turned the way it was (it turns with the camera). They push only on the thing, never
	-- back on you, so there is no weight limit and your flight does not change. It never bumps
	-- into your own body. The server gives you the thing (network owner) when you grab it.
	function Controller:_strongHold(side: string, L, part: BasePart, a0: Attachment, a1: Attachment)
		local root = part.AssemblyRootPart or part
		local other = self.hands[side == "Left" and "Right" or "Left"].grip
		if other and other.strong and other.part.Parent and (other.part.AssemblyRootPart or other.part) == root then
			-- the other hand already carries it: this hand only sticks to it
			local stick = Instance.new("AlignPosition")
			stick.Name = "Grip"
			stick.Mode = Enum.PositionAlignmentMode.TwoAttachment
			stick.Attachment0 = a0
			stick.Attachment1 = a1
			stick.ReactionForceEnabled = false
			stick.MaxForce = self.bodyMass * workspace.Gravity * 3
			stick.MaxVelocity = math.huge
			stick.Responsiveness = 60
			stick.Parent = L.part
			return stick, nil
		end
		local hold = Instance.new("AlignPosition")
		hold.Name = "Grip"
		hold.Mode = Enum.PositionAlignmentMode.TwoAttachment
		hold.Attachment0 = a1 -- (on the thing: it moves)
		hold.Attachment1 = a0 -- (the hand)
		hold.ReactionForceEnabled = false
		hold.RigidityEnabled = true
		hold.Parent = L.part
		local turn = Instance.new("AlignOrientation")
		turn.Name = "GripTurn"
		turn.Mode = Enum.OrientationAlignmentMode.OneAttachment
		turn.Attachment0 = a1
		turn.RigidityEnabled = true
		turn.CFrame = a1.WorldCFrame.Rotation
		turn.Parent = hold
		-- no collisions between the thing and your own body
		local mine = {}
		for _, bp in self.character:GetDescendants() do
			if bp:IsA("BasePart") and (bp.CanCollide or bp.Name == "Collider") then
				table.insert(mine, bp)
			end
		end
		local carried = {}
		local model = part:FindFirstAncestorOfClass("Model")
		if model then
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.CanCollide and d.AssemblyRootPart == root then
					table.insert(carried, d)
					if #carried >= 120 then
						break
					end
				end
			end
		end
		if #carried == 0 then
			carried = { part }
		end
		for _, cp in carried do
			for _, bp in mine do
				local nc = Instance.new("NoCollisionConstraint")
				nc.Part0 = cp
				nc.Part1 = bp
				nc.Parent = hold
			end
		end
		return hold, { turn = turn, yaw0 = Cam.yaw, rot0 = a1.WorldCFrame.Rotation }
	end

	function Controller:_grip(side: string, part: BasePart, point: Vector3)
		local L = self.limbs[ARM_OF[side]]
		if not L or L.severed then
			return
		end
		local hand = self.hands[side]
		if hand.grip then
			return
		end
		local item = Items.ModelOf(part)
		if item then
			self:_gripItem(side, item)
			return
		end
		if part.Name == "Collider" and part.Parent and part.Parent:IsA("BasePart") then
			part = part.Parent :: BasePart
		end
		local body = bodyOf(part)
		local otherPlayer = body and body ~= self.character and Players:GetPlayerFromCharacter(body) or nil

		local a0 = Instance.new("Attachment")
		a0.Name = "GripHand"
		a0.Position = Vector3.new(0, -1, 0)
		a0.Parent = L.part
		local a1 = Instance.new("Attachment")
		a1.Name = "GripPoint_" .. player.UserId
		a1.CFrame = part.CFrame:ToObjectSpace(CFrame.new(point))
		a1.Parent = part
		local localPoint = part.CFrame:PointToObjectSpace(point)

		-- things that must not change hands (a car somebody else drives, the wrecking ball the server
		-- swings) are held like the world: a force, no joint, no ownership change
		local model = part:FindFirstAncestorOfClass("Model")
		local driver = model and model:GetAttribute("Car") and model:GetAttribute("DriverId")
		local root = part.AssemblyRootPart
		local pinned = (driver ~= nil and driver ~= player.UserId)
			or part:GetAttribute("NoOwnershipGrab") == true
			or (root ~= nil and root:GetAttribute("NoOwnershipGrab") == true)
		local grounded = part:IsGrounded() or pinned
		local static = grounded or isSolid(self, part)
		-- flying: infinite strength. Anything loose that is not a body is lifted, however heavy.
		local strong = self.flying == true and not grounded and body == nil
		if strong then
			static = false
		end
		local socket: Instance
		local carry = nil
		-- a living player: their own client pulls their body to this hand (DragClient). No joint
		-- between the two bodies: this hand only reaches for the spot it holds.
		-- (v2.0, Config.DragOwnerMode) the server hands the limp body to this machine instead: it is held like a
		-- dummy (a joint at the hand, no delay)
		-- (v2.0, Config.DragPuppets) a player's body is never joined to this hand: their client pulls it here, and this
		-- screen shows a limp copy hanging from the hand (DragPuppets). The hand only holds a placeholder.
		local puppet = otherPlayer ~= nil and not strong and Config.DragPuppets == true
		local remoteBody = otherPlayer ~= nil and not body:GetAttribute("Dead") and not strong and not Config.DragOwnerMode and not puppet
		if otherPlayer and body and not remoteBody and not puppet then
			local hum = body:FindFirstChildOfClass("Humanoid")
			if hum then
				pcall(function()
					hum:ChangeState(Enum.HumanoidStateType.Physics) -- (their Humanoid never stands up on this machine)
				end)
			end
		end
		if puppet then
			static = false
			local hold = Instance.new("AlignPosition")
			hold.Name = "Grip"
			hold.Enabled = false
			hold.Mode = Enum.PositionAlignmentMode.OneAttachment
			hold.Attachment0 = a0
			hold.Parent = L.part
			socket = hold
		elseif remoteBody then
			static = false
			local reach = Instance.new("AlignPosition")
			reach.Name = "Grip"
			reach.Mode = Enum.PositionAlignmentMode.OneAttachment
			reach.Attachment0 = a0
			reach.Position = point
			reach.MaxForce = self.bodyMass * workspace.Gravity * 0.35
			reach.MaxVelocity = 30
			reach.Responsiveness = 18
			reach.Parent = L.part
			socket = reach
		elseif strong then
			socket, carry = self:_strongHold(side, L, part, a0, a1)
		elseif grounded then
			-- solid world: a force holds the hand at this spot. No joint to the world: pulling on
			-- the arm / climbing moves the body, and nothing can freeze it in place.
			local hold = Instance.new("AlignPosition")
			hold.Name = "Grip"
			hold.Mode = Enum.PositionAlignmentMode.OneAttachment
			hold.Attachment0 = a0
			hold.Position = point
			hold.MaxForce = self.bodyMass * workspace.Gravity * Config.HoldForce
			hold.MaxVelocity = 80
			hold.Responsiveness = Config.HoldResponsiveness
			hold.RigidityEnabled = false
			hold.Parent = L.part
			socket = hold
		else
			local ball = Instance.new("BallSocketConstraint")
			ball.Name = "Grip"
			ball.Attachment0 = a0
			ball.Attachment1 = a1
			ball.MaxFrictionTorque = static and 40 or Config.GripFrictionTorque
			ball.Parent = L.part
			socket = ball
		end

		-- (v2.8.1 fix) a body in your hand never touches your own body: you stood on the body you held (it hangs from
		-- your hand, so standing on it lifted you - "air walking", flying up). Every part of both, limbs too (they only
		-- collide while limp, so "collides right now" missed them).
		local bodyNoCol: Folder? = nil
		if body and body ~= self.character then
			local nf = Instance.new("Folder")
			nf.Name = "CarryNoCollide"
			bodyNoCol = nf
			local mine = {}
			for _, bp in self.character:GetDescendants() do
				if bp:IsA("BasePart") and (bp.Parent == self.character or bp.CanCollide or bp.Name == "Collider") then
					table.insert(mine, bp)
				end
			end
			for _, tp in body:GetDescendants() do
				if tp:IsA("BasePart") and (tp.Parent == body or tp.CanCollide or tp.Name == "Collider") then
					for _, bp in mine do
						local nc = Instance.new("NoCollisionConstraint")
						nc.Part0 = tp
						nc.Part1 = bp
						nc.Parent = nf
					end
				end
			end
			nf.Parent = L.part
		end
		hand.grip = {
			part = part,
			a0 = a0,
			a1 = a1,
			socket = socket,
			static = static,
			hold = grounded,
			body = body,
			bodyNoCol = bodyNoCol,
			playerBody = otherPlayer ~= nil,
			time = os.clock(),
			remote = not grounded,
			stretch = 0,
			strong = strong or nil,
			carry = carry,
			remoteBody = remoteBody or nil,
			puppet = puppet or nil,
		}
		if not grounded then
			GripRemote:FireServer("grab", part, side, localPoint)
		end
		self.armSuppress[side] = os.clock() + 0.25
		SoundLibrary.Play("thud", point, 0.15)
		self:_rebuildFilters()
	end

	-- where the player aims a throw / beam from this hand
	-- (v2.1) writing in the Black Ledger: the hand that holds the book keeps it open in front of the chest, the other hand takes a pen and writes
	function Controller:StartWriting(item: Model, seconds: number): boolean
		local hold: string? = nil
		for _, side in SIDES do
			local g = self.hands[side].grip
			if g and g.item == item then
				hold = side
			end
		end
		if not hold then
			return false
		end
		local free = hold == "Left" and "Right" or "Left"
		if self.hands[free].grip then
			return false -- (the other hand is busy with something)
		end
		self:StopWriting()
		local L = self.limbs[ARM_OF[free]]
		local pen = Instance.new("Part")
		pen.Name = "WritingPen"
		pen.Size = Vector3.new(0.09, 0.09, 0.9)
		pen.Color = Color3.fromRGB(14, 14, 18)
		pen.Material = Enum.Material.Metal
		pen.CanCollide, pen.CanQuery, pen.CanTouch, pen.Massless = false, false, false, true
		pen.Parent = workspace
		if L and L.part then
			local w = Instance.new("Weld")
			w.Part0 = L.part
			w.Part1 = pen
			w.C0 = CFrame.new(0, -1.0, -0.15) * CFrame.Angles(math.rad(-50), 0, 0)
			w.Parent = pen
		end
		local tip = Instance.new("Part")
		tip.Size = Vector3.new(0.05, 0.05, 0.14)
		tip.Color = Color3.fromRGB(150, 110, 44)
		tip.Material = Enum.Material.Metal
		tip.CanCollide, tip.CanQuery, tip.CanTouch, tip.Massless = false, false, false, true
		tip.Parent = pen
		local tw = Instance.new("Weld")
		tw.Part0, tw.Part1 = pen, tip
		tw.C0 = CFrame.new(0, 0, -0.5)
		tw.Parent = tip
		self.writing = { item = item, hold = hold, free = free, t0 = os.clock(), dur = seconds, pen = pen }
		return true
	end

	function Controller:StopWriting()
		local w = self.writing
		self.writing = nil
		if w and w.pen then
			w.pen:Destroy()
		end
	end

	function Controller:_aimDir(side: string, from: Vector3): Vector3
		local target = self.handTarget[side] or self:_crosshairPoint()
		return MathUtil.SafeUnit(target - from, Cam.LookVector())
	end

	function Controller:_release(side: string, throw: boolean, serverAssigned: boolean?)
		local hand = self.hands[side]
		local g = hand.grip
		hand.armed = false -- a released hand is open again; only Q / E closes it
		if self.attacks then
			self.attacks[side] = nil
		end
		if self.bandaging and self.bandaging.side == side then
			self.bandaging = nil
		end
		if not g then
			return
		end
		if g.kind == "physgun" then
			self:_beamDrop()
		end
		hand.grip = nil
		local L = self.limbs and self.limbs[ARM_OF[side]]
		local handPos = g.a0.Parent and g.a0.WorldPosition or g.part.Position
		local throwVel: Vector3? = nil
		local handVel = Vector3.zero
		if L and L.part.Parent then
			handVel = L.part:GetVelocityAtPosition(L.part.CFrame:PointToWorldSpace(Vector3.new(0, -1, 0)))
		end
		g.socket:Destroy()
		g.a0:Destroy()
		if g.bodyNoCol then
			-- (a moment later: a body dropped right on you does not shove you away)
			local nc = g.bodyNoCol
			task.delay(0.6, function()
				nc:Destroy()
			end)
		end
		if not g.keepA1 then
			g.a1:Destroy()
		end
		if g.item then
			for _, d in g.item:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 0
				end
			end
		end
		if g.part.Parent then
			if g.item then
				-- the server's weld would keep the item in the hand until our message arrives: drop
				-- it here right away (it is gone on the server a moment later too)
				for _, d in g.part:GetChildren() do
					if d.Name == "ItemWeld" then
						d:Destroy()
					end
				end
				local root = g.part
				local aiming = (side == "Left" and Input.mouseLeft) or (side == "Right" and Input.mouseRight)
				pcall(function()
					if throw and (g.kind == "grenade" or g.kind == "flash") then
						local dir = self:_aimDir(side, handPos)
						root.AssemblyLinearVelocity = (dir * Config.GrenadeThrowSpeed + Vector3.new(0, 7, 0)) * (self.slowK or 1) + self.torso.AssemblyLinearVelocity * 0.5
						root.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8))
						SoundLibrary.Play("toss", handPos, 0.8)
					elseif throw and (g.kind == "virus" or g.kind == "molotov") then
						root.AssemblyLinearVelocity = self:_lob(side, handPos, 60, 120)
						root.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-6, 6))
						SoundLibrary.Play("toss", handPos, 0.8)
						self:_trackThrown(g.item, g.kind)
					elseif throw and g.kind == "c4" then
						root.AssemblyLinearVelocity = self:_lob(side, handPos, Config.C4ThrowSpeed, 140)
						root.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-5, 5), rng:NextNumber(-5, 5), rng:NextNumber(-5, 5))
						SoundLibrary.Play("toss", handPos, 0.8)
						self:_trackThrown(g.item, "c4")
					elseif throw and g.kind == "spear" and (aiming or self.aiming or self.stance ~= "Crouch") then
						-- javelin: aimed with gravity at what you point at, point first
						local v = self:_lob(side, handPos, Config.SpearThrowSpeed, Config.SpearThrowRange)
						root.AssemblyLinearVelocity = v
						root.AssemblyAngularVelocity = Vector3.zero
						self:_orientAlong(g.item, v)
						SoundLibrary.Play("javelin", handPos, 1)
						self:_trackThrown(g.item, "spear")
					elseif throw and (aiming or self.aiming) and not root:IsGrounded() then
						-- aiming (G, or that hand's mouse button) while letting go: thrown at the crosshair.
						-- Blades and knives fly point first and stick; everything else tumbles and hits hard.
						local mass = math.max(root.AssemblyMass, 0.5)
						local speed = math.clamp(Config.ThrowSpeedMax / math.sqrt(mass / 1.5), Config.ThrowSpeedMin, Config.ThrowSpeedMax)
						local v = self:_lob(side, handPos, speed, Config.ThrowRange)
						root.AssemblyLinearVelocity = v
						local sharp = Items.Sharp(g.item)
						if sharp then
							root.AssemblyAngularVelocity = Vector3.zero
							self:_orientAlong(g.item, v)
							SoundLibrary.Play("javelin", handPos, 0.8)
						else
							root.AssemblyAngularVelocity = self.torso.CFrame.RightVector * rng:NextNumber(10, 18)
							SoundLibrary.Play("toss", handPos, 0.9)
						end
						self:_trackThrown(g.item, sharp and "blade" or "thrown")
					elseif throw and handVel.Magnitude > 6 then
						root.AssemblyLinearVelocity += handVel * Config.ThrowBoost
					end
				end)
			elseif throw and g.puppet then
				-- (v2.0) a player: their own client throws their body (the server passes it on)
				if (side == "Left" and Input.mouseLeft) or (side == "Right" and Input.mouseRight) or self.aiming then
					local speed = math.clamp(Config.ThrowSpeedMax / math.sqrt(math.max(g.part.AssemblyMass, 1.5) / 1.5), Config.ThrowSpeedMin, Config.ThrowSpeedMax)
					throwVel = self:_lob(side, handPos, speed * 1.6, Config.ThrowRange)
				elseif handVel.Magnitude > 6 then
					throwVel = handVel * Config.ThrowBoost + Vector3.new(0, 6, 0)
				end
			elseif throw and g.strong and g.carry then
				-- infinite strength: the swing of the arm (not the flight itself) throws it
				local swing = handVel - self.torso.AssemblyLinearVelocity
				if swing.Magnitude > 6 then
					pcall(function()
						g.part.AssemblyLinearVelocity += swing * Config.FlyThrowBoost
					end)
				end
			elseif throw and not g.static and g.part.AssemblyMass < self.bodyMass * 1.5 and handVel.Magnitude > 6 then
				pcall(function()
					g.part.AssemblyLinearVelocity += handVel * Config.ThrowBoost
				end)
			end
			if g.remote and not serverAssigned then
				GripRemote:FireServer("release", g.part, side, throwVel)
			end
		end
		-- the hand that carried it let go, the other hand still holds the same thing: that hand
		-- carries it now
		if g.carry and self.flying and not self.dead then
			local otherSide = side == "Left" and "Right" or "Left"
			local og = self.hands[otherSide].grip
			if og and og.strong and not og.carry and og.part.Parent and og.a1.Parent then
				local part, point = og.part, og.a1.WorldPosition
				self:_release(otherSide, false)
				self.hands[otherSide].armed = true
				self:_grip(otherSide, part, point)
			end
		end
		if self.ready then
			self:_rebuildFilters()
		end
	end

	function Controller:_hasStaticGrip(): (boolean, Vector3?)
		local best: Vector3? = nil
		for _, side in SIDES do
			local g = self.hands[side].grip
			if g and g.static and g.a1.Parent then
				local p = g.a1.WorldPosition
				if not best or p.Y > best.Y then
					best = p
				end
			end
		end
		return best ~= nil, best
	end

	-- Holding something solid must never lock you in place. While you try to move (walk keys,
	-- Space) and the body makes no progress for a moment, the hand slips off. Hanging in the air
	-- with no keys pressed is fine: that is just hanging.
	function Controller:_unstick(dt: number, moveWorld: Vector3)
		local hasStatic, G = self:_hasStaticGrip()
		local s = self.state
		local trying = Input.jumpHeld or (moveWorld.Magnitude > 0.5 and s ~= "Hanging")
		if s == "Hanging" and G and moveWorld.Magnitude > 0.5 then
			-- hanging: only pushing AWAY from the hold counts (keys towards the wall are normal)
			local toWall = MathUtil.Flat(G - self.torso.Position)
			if toWall.Magnitude > 0.05 and moveWorld:Dot(toWall.Unit) < -0.3 then
				trying = true
			end
		end
		if not hasStatic or not trying or Input.menuOpen then
			self.stuckRef = nil
			return
		end
		local now = os.clock()
		local pos = self.torso.Position
		local ref = self.stuckRef
		if not ref or (pos - ref.p).Magnitude > Config.GripStuckDistance then
			self.stuckRef = { p = pos, t = now }
			return
		end
		local limit = s == "Hanging" and Config.GripStuckTimeClimb or Config.GripStuckTime
		if now - ref.t > limit then
			self.stuckRef = nil
			for _, side in SIDES do
				local g = self.hands[side].grip
				if g and g.static then
					self:_release(side, false)
				end
			end
		end
	end

	-- lying on the floor and holding it: drag yourself towards the hand; once you are there the
	-- hand lets go so you can grab further ahead
	function Controller:_floorPull(speed: number, moveWorld: Vector3): Vector3?
		local s = self.state
		if s ~= "Prone" and s ~= "Downed" then
			return nil
		end
		local best: string? = nil
		local bestP: Vector3? = nil
		for _, side in SIDES do
			local g = self.hands[side].grip
			if g and g.static and g.a1.Parent then
				best, bestP = side, g.a1.WorldPosition
			end
		end
		if not best or not bestP then
			return nil
		end
		local to = MathUtil.Flat(bestP - self.torso.Position)
		local crawlingAway = moveWorld.Magnitude > 0.3 and to.Magnitude > 0.01 and moveWorld:Dot(to.Unit) < -0.2
		if to.Magnitude < Config.FloorPullDone or crawlingAway then
			self:_release(best, false)
			return nil
		end
		return to.Unit * speed * Config.FloorPullSpeed
	end

	function Controller:_updateGrips(dt: number, moveWorld: Vector3)
		local onFeet = self.state == "Standing" or self.state == "Stumbling" or self.state == "GettingUp"
		self:_unstick(dt, moveWorld)
		local holding = false
		for _, side in SIDES do
			local hand = self.hands[side]
			local g = hand.grip
			local L = self.limbs[ARM_OF[side]]
			local usable = self:_limbUsable(ARM_OF[side])
			if not usable then
				hand.armed = false
			end
			if not g then
				continue
			end
			-- (v2.0 fix) an item in the hand that got pinned to the world (it was stuck in a wall / the ground a moment
			-- ago): the hand lets go of it instead of locking the whole body in place
			if g.item and g.socket and (g.socket :: any).Enabled and g.part and g.part.Parent and g.part:IsGrounded() then
				(g.socket :: any).Enabled = false
				g.pinnedT = g.pinnedT or os.clock()
			elseif g.item and g.pinnedT and g.part and g.part.Parent and not g.part:IsGrounded() then
				g.pinnedT = nil
				if g.socket and g.socket.Parent then
					(g.socket :: any).Enabled = true
				end
			end
			if g.pinnedT and os.clock() - g.pinnedT > 0.3 then -- (v2.1: 1.2 -> 0.3: let go of an item that got pinned to the world at once)
				self:_release(side, false)
				continue
			end
			local controlled = (side == "Left" and Input.mouseLeft or side == "Right" and Input.mouseRight) and not Input.menuOpen
			if controlled then
				holding = true
			end
			-- a hold follows its spot (an anchored part may still be moved by a script)
			if g.hold and g.a1.Parent then
				g.socket.Position = g.a1.WorldPosition
				g.socket.MaxForce = self.bodyMass * workspace.Gravity * Config.HoldForce
			end
			if g.strong then
				local model = g.part:FindFirstAncestorOfClass("Model")
				local driven = model ~= nil and model:GetAttribute("Car") and model:GetAttribute("DriverId") ~= nil
				if not self.flying or driven then
					self:_release(side, false)
					continue
				end
				-- what you carry turns with the camera
				if g.carry and g.carry.turn.Parent then
					g.carry.turn.CFrame = CFrame.Angles(0, Cam.yaw - g.carry.yaw0, 0) * g.carry.rot0
				end
			end
			if g.remoteBody then
				if g.body and g.body:GetAttribute("Dead") then
					-- they died in your hand: now you simply hold the corpse (the server gives it to you)
					g.socket:Destroy()
					local ball = Instance.new("BallSocketConstraint")
					ball.Name = "Grip"
					ball.Attachment0 = g.a0
					ball.Attachment1 = g.a1
					ball.MaxFrictionTorque = Config.GripFrictionTorque
					ball.Parent = L.part
					g.socket = ball
					g.remoteBody = nil
					g.playerBody = false
				elseif g.socket:IsA("AlignPosition") then
					-- the hand reaches for the spot it holds (their body comes to the hand by itself)
					g.socket.Position = g.a1.WorldPosition
					local far = (g.a0.WorldPosition - g.a1.WorldPosition).Magnitude > Config.DragBreakDistance
					g.farTime = far and (g.farTime or 0) + dt or 0
					if g.farTime > 1.2 then
						self:_release(side, false)
						continue
					end
				end
			end
			if g.puppet then
				if g.body and not Players:GetPlayerFromCharacter(g.body) then
					-- (v2.0) they respawned: the body in your hand is a corpse now and the server gives it to you
					g.socket:Destroy()
					local ball = Instance.new("BallSocketConstraint")
					ball.Name = "Grip"
					ball.Attachment0 = g.a0
					ball.Attachment1 = g.a1
					ball.MaxFrictionTorque = Config.GripFrictionTorque
					ball.Parent = L.part
					g.socket = ball
					g.puppet = nil
					g.playerBody = false
				elseif os.clock() - g.time > 1.2 and g.body and g.body:GetAttribute("DraggedBy") ~= player.UserId then
					self:_release(side, false) -- (the server said no: somebody else has them, ...)
					continue
				end
			end
			local maxStretch = g.strong and Config.FlyCarryBreak or (g.playerBody and 5 or (g.item and 4 or Config.GripBreakDistance))
			if g.remoteBody or g.puppet then
				maxStretch = math.huge -- (see above: it slips only after a while far away)
			end
			if g.strong and os.clock() - g.time < 1.5 then
				maxStretch = math.huge -- (the server is still handing the thing over)
			end
			local stolen = g.item and g.item:GetAttribute("HolderId") ~= nil and g.item:GetAttribute("HolderId") ~= player.UserId
			local broken = not usable
				or stolen
				or not g.part.Parent
				or not g.a1.Parent
				or not g.socket.Parent
				or (g.a0.WorldPosition - g.a1.WorldPosition).Magnitude > maxStretch
			if broken then
				self:_release(side, false)
				continue
			end
			if g.static and g.hung and onFeet and self.groundTime > 0.35 then
				-- climbed over the ledge: let go automatically once the grip is below the hips
				if g.a1.WorldPosition.Y < self.torso.Position.Y - 1.1 then
					self:_release(side, false)
					hand.armed = false
					continue
				end
			end
			-- walking away from a wall you hold: the hand slips off instead of holding you back
			if g.static and onFeet and not self.climbIntent and moveWorld.Magnitude > 0.5 and not controlled then
				local shoulder = self.torso.CFrame:PointToWorldSpace(L.def.torsoPivot)
				local toGrip = g.a1.WorldPosition - shoulder
				local stretched = toGrip.Magnitude > Config.ArmReach + 0.7
				local away = moveWorld:Dot(MathUtil.SafeUnit(MathUtil.Flat(toGrip), Vector3.zero)) < -0.2
				if stretched or away then
					g.stretch = (g.stretch or 0) + dt
				else
					g.stretch = 0
				end
				if g.stretch > 0.25 then
					self:_release(side, false)
					hand.armed = false
				end
			end
		end
		Input.handHolding = holding
	end

	-- (v2.8.1) what this hand would take hold of right now (the same search the grab uses; the outline asks it too).
	-- An item near the hand wins over the world the reach ray touched: a blade stuck in the ground used to lose to the
	-- ground under it (you took hold of the floor, never the sword).
	local function closestOn(p: BasePart, at: Vector3): Vector3
		local half = p.Size / 2
		local lp = p.CFrame:PointToObjectSpace(at)
		return p.CFrame:PointToWorldSpace(Vector3.new(math.clamp(lp.X, -half.X, half.X), math.clamp(lp.Y, -half.Y, half.Y),
			math.clamp(lp.Z, -half.Z, half.Z)))
	end

	function Controller:GrabCandidate(side: string, extra: number?): (BasePart?, Vector3?)
		local L = self.limbs and self.limbs[ARM_OF[side]]
		if not L or L.severed or L.broken or not L.part.Parent then
			return nil, nil
		end
		local tip = L.part.CFrame:PointToWorldSpace(Vector3.new(0, -1.05, 0))
		local shoulder = self.torso.CFrame:PointToWorldSpace(L.def.torsoPivot)
		local along = tip - shoulder
		local found, point = nil, nil
		if along.Magnitude > 0.2 then
			local hit = workspace:Raycast(shoulder, along.Unit * (along.Magnitude + 0.5), self.grabParams)
			if hit and isValidGrabTarget(self, hit.Instance) then
				found, point = hit.Instance, hit.Position
			end
		end
		if not found or not Items.ModelOf(found) then
			local r = Config.GrabRadius + (extra or 0)
			local bestD = math.huge
			local bestItemD = math.huge
			local item, itemPoint = nil, nil
			local near, nearPoint = nil, nil
			for _, p in workspace:GetPartBoundsInRadius(tip, r + 0.9, self.overlapParams) do
				if isValidGrabTarget(self, p) then
					local c = closestOn(p, tip)
					local d = (c - tip).Magnitude
					if d <= r + 0.35 then
						if Items.ModelOf(p) then
							if d < bestItemD then
								bestItemD, item, itemPoint = d, p, c
							end
						elseif d < bestD and d <= r then
							bestD, near, nearPoint = d, p, c
						end
					end
				end
			end
			if item then
				found, point = item, itemPoint
			elseif not found then
				found, point = near, nearPoint
			end
		end
		return found, point
	end

	function Controller:_tryGrab()
		if self.car or self:IsAsleep() then
			return
		end
		for _, side in SIDES do
			local hand = self.hands[side]
			if hand.grip then
				continue
			end
			local L = self.limbs[ARM_OF[side]]
			if not L or L.severed or L.broken then
				continue
			end
			if not hand.armed then
				continue -- only a hand closed with Q / E grabs
			end
			if self.reload and self.reload.assist and self.reload.free == side then
				continue -- this hand is reloading
			end
			local found, point = self:GrabCandidate(side)
			if found and point then
				self:_grip(side, found, point)
			end
		end
	end

	----------------------------------------------------------------------
	-- aiming
	----------------------------------------------------------------------

	function Controller:_screenRay(): Ray
		local camera = workspace.CurrentCamera
		if Input.UsesCursor() then
			local m = UserInputService:GetMouseLocation()
			return camera:ViewportPointToRay(m.X, m.Y)
		end
		local vs = camera.ViewportSize
		return camera:ViewportPointToRay(vs.X * 0.5, vs.Y * 0.5)
	end

	function Controller:_crosshairPoint(): Vector3
		local camera = workspace.CurrentCamera
		local vs = camera.ViewportSize
		local ray = camera:ViewportPointToRay(vs.X * 0.5, vs.Y * 0.5)
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 400, self.rayParams)
		return hit and hit.Position or (ray.Origin + ray.Direction * 200)
	end

	function Controller:_updateHandTargets()
		self:_updateAim()
		self.handTarget.Left = nil
		self.handTarget.Right = nil
		if not Input.HandControlActive() or self:IsAsleep() then
			return
		end
		-- the cursor ray ignores your own body, so the arm never tries to point into yourself
		-- (pointing a gun down past your leg still lets you shoot your own foot)
		local ray = self:_screenRay()
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 400, self.rayParams)
		local p = hit and hit.Position or (ray.Origin + ray.Direction * 30)
		if Input.mouseLeft then
			self.handTarget.Left = p
		end
		if Input.mouseRight then
			self.handTarget.Right = p
		end
	end

	-- melee attack animation: direction of the arm over the attack
	local function attackDir(a, now: number): Vector3
		local t = now - a.t0
		local dir: Vector3 = a.dir
		local up = Vector3.yAxis
		local right = MathUtil.SafeUnit(dir:Cross(up), Vector3.xAxis)
		if a.kind == "stab" then
			if t < 0.1 then
				-- draw back a little (arm up)
				return CFrame.fromAxisAngle(right, math.rad(35) * smooth(t / 0.1)):VectorToWorldSpace(dir)
			end
			return CFrame.fromAxisAngle(right, math.rad(35) * (1 - smooth((t - 0.1) / 0.08))):VectorToWorldSpace(dir)
		end
		-- slash / swing: from high and to the side across to low on the other side
		local k = smooth((t - 0.05) / (a.slow and 0.3 or 0.22))
		local yaw = math.rad(-65) * (1 - k) + math.rad(55) * k -- (x side: + = starts on the right)
		local pitch = math.rad(a.kind == "blunt" and 25 or 55) * (1 - k) + math.rad(-35) * k
		local d = CFrame.fromAxisAngle(up, yaw * a.side):VectorToWorldSpace(dir)
		local r2 = MathUtil.SafeUnit(d:Cross(up), Vector3.xAxis)
		return CFrame.fromAxisAngle(r2, pitch):VectorToWorldSpace(d)
	end

	-- the body part a bandage is being wrapped around
	function Controller:_bandageTarget(): BasePart?
		for _, side in SIDES do
			local g = self.hands[side].grip
			if g and g.body and g.body ~= self.character and g.body.Parent then
				return g.part
			end
		end
		-- your own most hurt body part
		local worst, worstHp = nil, math.huge
		for _, region in RigInfo.Regions do
			if not self.character:GetAttribute("Severed_" .. region) then
				local hp = self.character:GetAttribute("HP_" .. region) or 100
				if hp < worstHp then
					worst, worstHp = region, hp
				end
			end
		end
		local name = worst and RigInfo.RegionPart[worst]
		local part = name and self.character:FindFirstChild(name)
		return (part and part:IsA("BasePart")) and part or self.torso
	end

	-- direction the arm should point (nil = default pose) and whether it should be extra strong
	function Controller:_armAim(side: string, L, heading: CFrame): (Vector3?, boolean?)
		local hand = self.hands[side]
		local shoulder = self.torso.CFrame:PointToWorldSpace(L.def.torsoPivot)
		local now = os.clock()
		-- super punch: the right fist leads
		local pa = self:_punchAim(side)
		if pa then
			return pa, true
		end
		-- (v2.x) other modules may point an arm (cyberware, auto-defense, rituals ...)
		if Input.ArmAimHook then
			local hd, hs = Input.ArmAimHook(self, side, shoulder, heading)
			if hd then
				return hd, hs == true
			end
		end
		-- (v2.1) writing in the Black Ledger: one hand holds the open book in front of the chest, the other writes in it with a pen
		local wr = self.writing
		if wr then
			local t = now - wr.t0
			if t > wr.dur or not wr.item.Parent or not wr.item.PrimaryPart then
				self:StopWriting()
			elseif side == wr.hold then
				local d = heading.LookVector + Vector3.new(0, -0.62, 0) - heading.RightVector * 0.12 * (side == "Right" and 1 or -1)
				return MathUtil.SafeUnit(d, heading.LookVector), true
			elseif side == wr.free then
				local book = wr.item.PrimaryPart.Position
				local right, look = heading.RightVector, heading.LookVector
				-- the pen goes over the page in short strokes (a line, a step down, the next line)
				local line = (t * 1.3) % 1
				local p = book + Vector3.new(0, 0.5, 0) + right * (math.sin(t * 11) * 0.34) + look * ((line - 0.5) * 0.7) + Vector3.new(0, math.abs(math.sin(t * 11)) * 0.06, 0)
				return MathUtil.SafeUnit(p - shoulder, heading.LookVector), true
			end
		end
		-- (v2.0) fists, the guard, fitting a prosthetic
		local ga, gs = self:_gearArmAim(side, shoulder, heading)
		if ga then
			return ga, gs == true
		end
		local a = self.attacks and self.attacks[side]
		if a then
			if now - a.t0 > Config.MeleeAttackTime * (a.slow and 1.3 or 1) then
				self.attacks[side] = nil
			else
				return attackDir(a, now), true
			end
		end
		-- wrapping a bandage: the hand circles around the body part
		local b = self.bandaging
		if b and b.side == side and b.target and b.target.Parent then
			local t = now - b.t0
			local c = b.target.Position
			local right = self.torso.CFrame.RightVector
			local up = self.torso.CFrame.UpVector
			local p = c + right * math.cos(t * 11) * 0.7 + up * math.sin(t * 11) * 0.45 - self.torso.CFrame.LookVector * 0.2
			return MathUtil.SafeUnit(p - shoulder, heading.LookVector), true
		end
		-- reloading by hand: the free hand goes to the gun, the gun comes in front of the chest
		local r = self.reload
		if r and r.assist then
			if side == r.free and r.touchPoint then
				return MathUtil.SafeUnit(r.touchPoint - shoulder, heading.LookVector), true
			elseif side == r.gunSide then
				local fwd = MathUtil.SafeUnit(MathUtil.Flat(Cam.LookVector()), heading.LookVector)
				local toFree = (r.free == "Left") and -self.torso.CFrame.RightVector or self.torso.CFrame.RightVector
				local p = self.torso.Position + fwd * 1.9 + toFree * 0.6 + Vector3.new(0, 0.2, 0)
				return MathUtil.SafeUnit(p - shoulder, fwd), true
			end
		end
		-- Y: the supporting hand stays on the item
		local support = self:_twoHandAim(side, shoulder)
		if support then
			return support, false
		end
		-- G: the gun points exactly at the crosshair
		local g0 = hand.grip
		if self.aiming and g0 and g0.gun then
			return MathUtil.SafeUnit(self:_crosshairPoint() - shoulder, Cam.LookVector()), true
		end
		local target = self.handTarget[side]
		if target then
			return MathUtil.SafeUnit(target - shoulder, heading.LookVector), false
		end
		local g = hand.grip
		if g and (g.static or g.remoteBody) and g.a1.Parent then
			return MathUtil.SafeUnit(g.a1.WorldPosition - shoulder, Vector3.yAxis), false
		end
		if g and g.puppet then
			-- (v2.0) a player in your hand: held out in front, a little low (they hang from it)
			local look = Cam.LookVector()
			local chest = self.torso.CFrame:PointToWorldSpace(Vector3.new(0, 0.5, 0))
			local aim = chest + look * Config.ReachConverge - Vector3.new(0, 1.2, 0)
			return MathUtil.SafeUnit(aim - shoulder, look), false
		end
		if g and g.strong then
			-- infinite strength: hold it up over your head, out of your view
			return MathUtil.SafeUnit(Vector3.new(0, 2, 0) + MathUtil.Flat(Cam.LookVector()) * 0.35, Vector3.yAxis), false
		end
		if hand.armed or g then
			local look = Cam.LookVector()
			if g and g.item and (g.gun or Items.Melee(g.item) or g.kind == "physgun" or g.kind == "c4" or g.kind == "detonator" or g.kind == "laser" or g.kind == "shield" or g.kind == "virus" or g.kind == "molotov" or g.kind == "flamethrower") then
				-- point the weapon at what the crosshair is on
				return MathUtil.SafeUnit(self:_crosshairPoint() - shoulder, look), false
			end
			local chest = self.torso.CFrame:PointToWorldSpace(Vector3.new(0, 0.5, 0))
			local aim = chest + look * Config.ReachConverge
			return MathUtil.SafeUnit(aim - shoulder, look), false
		end
		return nil, false
	end

	----------------------------------------------------------------------
	-- guns
	----------------------------------------------------------------------

	local shotParams = RaycastParams.new()
	shotParams.FilterType = Enum.RaycastFilterType.Exclude
	shotParams.RespectCanCollide = false

	-- (v2.0) where my own bullet really ends up: on through the body parts it is strong enough to pass (the
	-- server decides the damage; this only draws the tracer to the right place)
	local function throughBodies(origin: Vector3, d: Vector3, range: number, pen: number, hit: RaycastResult?): RaycastResult?
		if not hit or pen <= 0 or not bodyOf(hit.Instance) then
			return hit
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.RespectCanCollide = false
		local ignore = shotParams.FilterDescendantsInstances
		local left = pen
		for _ = 1, Config.PenetrationMaxParts do
			if not hit or not bodyOf(hit.Instance) then
				break
			end
			local bp = hit.Instance
			if bp.Name == "Collider" and bp.Parent and bp.Parent:IsA("BasePart") then
				bp = bp.Parent :: BasePart
			end
			local thick = Ballistics.ExitDistance(bp, hit.Position, d)
			if thick > left then
				break
			end
			left -= thick
			table.insert(ignore, bp)
			params.FilterDescendantsInstances = ignore
			local exitPos = hit.Position + d * thick
			local rest = range - (exitPos - origin).Magnitude
			local nextHit = rest > 0.5 and workspace:Raycast(exitPos, d * rest, params) or nil
			if not nextHit then
				return nil -- (on into the distance)
			end
			hit = nextHit
		end
		return hit
	end

	function Controller:_fireGun(side: string, g)
		local gun = g.item
		local stats = Config.Guns[g.kind] or Config.Guns.pistol
		local shotgun = g.kind == "shotgun"
		local now = os.clock()
		self.lastFire = self.lastFire or {}
		if now - (self.lastFire[gun] or 0) < stats.interval then
			return
		end
		if self.reload and self.reload.gun == gun and self.reload.progress > 0 then
			return -- the free hand is on it, reloading
		end
		self.lastFire[gun] = now
		local muzzle = Items.Muzzle(gun)
		if not muzzle then
			return
		end
		local origin = muzzle.WorldPosition
		local barrel = muzzle.WorldCFrame.LookVector
		local dir = barrel
		if stats.projectile then
			-- rocket launcher: the server flies the rocket
			local aimedR = self.aiming
			local targetR = (not aimedR and self.handTarget[side]) or self:_crosshairPoint()
			local wantR = targetR - origin
			if wantR.Magnitude > 1 and wantR.Unit:Dot(barrel) > math.cos(math.rad(aimedR and 25 or Config.GunAimAssist)) then
				dir = wantR.Unit
			end
			if (gun:GetAttribute("Ammo") or 0) <= 0 then
				SoundLibrary.Play("dryfire", origin)
				return
			end
			-- (v2.0) the lock-on launcher sends what it is locked on
			ItemRemote:FireServer("rocket", gun, origin, dir, self.GetLockTarget and self:GetLockTarget(gun) or nil)
			local Lr = self.limbs[ARM_OF[side]]
			local rk = self:_twoHandMult(gun) * (self.slowK or 1) -- (v2.8.1) slowed by a Sandevistan: the kick is slow too
			pcall(function()
				Lr.part:ApplyImpulse((Vector3.new(0, stats.recoil, 0) - dir * stats.recoil * 0.4) * Lr.part.AssemblyMass * rk)
				self.torso:ApplyImpulse(-MathUtil.Flat(dir) * 8 * self.torso.AssemblyMass * rk)
			end)
			Cam.Shake(0.9 * (0.4 + 0.6 * rk))
			return
		end
		-- the arm sways a little: if the barrel is close to what you aim at, the shot goes there
		-- (aiming with G: always exactly at the crosshair)
		local aimed = self.aiming
		local target = (not aimed and self.handTarget[side]) or self:_crosshairPoint()
		local want = target - origin
		local gs0 = Config.Guns[g.kind]
		local assist = (gs0 and gs0.smart) and 85 or (aimed and 25 or Config.GunAimAssist) -- (v2.8: a smart gun follows the lock)
		if want.Magnitude > 1 and math.deg(math.acos(math.clamp(want.Unit:Dot(barrel), -1, 1))) < assist then
			dir = want.Unit
		end
		local ignore: { Instance } = { gun }
		local fx = workspace:FindFirstChild("FX")
		if fx then
			table.insert(ignore, fx)
		end
		if self.car then
			table.insert(ignore, self.car)
		end
		if self.passenger then
			-- out of the window: your car does not stop your bullets; the arm follows the
			-- crosshair (turned by the server), so the shot goes where you aim
			table.insert(ignore, self.passenger)
			if want.Magnitude > 1 then
				dir = want.Unit
			end
		end
		-- (your own shield / other gun does not stop your bullets)
		for _, sd in SIDES do
			local og = self.hands[sd].grip
			if og and og.item and og.item ~= gun then
				table.insert(ignore, og.item)
			end
		end
		shotParams.FilterDescendantsInstances = ignore
		-- this client sees its own gun and body exactly, so it finds the hits; the server checks them
		local count = shotgun and Config.ShotgunPellets or 1
		local rm = gun:GetAttribute("RangeMult") -- (v2.0: the sniper mode's rifle reaches further)
		local range = (stats.range or Config.GunRange) * ((typeof(rm) == "number" and rm >= 1 and rm <= 10) and rm or 1)
		local spreadDeg = shotgun and Config.ShotgunSpread * (aimed and 0.75 or 1)
			or (stats.spread or 0) * (aimed and (stats.scope and 0 or Config.AimSpreadMult) or 1)
		local recoilK, spreadK = self:_twoHandMult(gun)
		local spread = math.rad(spreadDeg * spreadK)
		local shots, visuals = {}, {}
		for i = 1, count do
			local d = dir
			if spread > 0 then
				d = (CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(rng:NextNumber(-spread, spread), rng:NextNumber(-spread, spread), 0)).LookVector
			end
			local hit = workspace:Raycast(origin, d * range, shotParams)
			shots[i] = { dir = d, part = hit and hit.Instance or nil, pos = hit and hit.Position or nil, n = hit and hit.Normal or nil }
			local seen = shotgun and hit or throughBodies(origin, d, range, Ballistics.Pen(g.kind), hit)
			local worldMat: string? = nil
			if seen and not bodyOf(seen.Instance) then
				worldMat = seen.Material.Name
			end
			visuals[i] = { to = seen and seen.Position or (origin + d * range), n = seen and seen.Normal or nil, mat = worldMat }
		end
		GunRemote:FireServer(gun, origin, shots)
		local ammo = gun:GetAttribute("Ammo") or 0
		if ammo > 0 then
			if self.onLocalShot then
				-- (v2.8) in the Sandevistan's slow motion the server flies the bullet: only the flash here
				self.onLocalShot(gun, origin, TimeScale.Active() and {} or visuals, shotgun)
			end
			local L = self.limbs[ARM_OF[side]]
			-- (v2.8.1) slowed by somebody's Sandevistan: the recoil is slow too (a full kick in slow gravity threw you away)
			local stk = self.slowK or 1
			local kick = (stats.recoil or 7) * recoilK * stk
			recoilK *= stk
			pcall(function()
				L.part:ApplyImpulse((Vector3.new(0, kick, 0) - dir * kick * 0.6) * L.part.AssemblyMass)
				if shotgun then
					self.torso:ApplyImpulse(-MathUtil.Flat(dir) * 5 * recoilK * self.torso.AssemblyMass)
				elseif g.kind == "sniper" then
					-- the sniper kicks like a mule (with both hands on it: a lot less)
					self.torso:ApplyImpulse((-MathUtil.Flat(dir) * Config.SniperSelfKick * recoilK + Vector3.new(0, 4 * recoilK, 0)) * self.torso.AssemblyMass)
				end
			end)
			Cam.Shake((shotgun and 0.75 or (g.kind == "sniper" and 1.3 or (g.kind == "revolver" and 0.55 or 0.25))) * (0.4 + 0.6 * recoilK))
			if Input.firstPerson or aimed then
				local kickUp = shotgun and 0.05 or (g.kind == "sniper" and 0.16 or (g.kind == "revolver" and 0.035 or 0.012))
				Cam.pitch = math.min(Cam.pitch + kickUp * (0.35 + 0.65 * recoilK), 1.35)
			end
			if g.kind == "sniper" then
				task.delay(0.55, function()
					if gun.Parent and gun.PrimaryPart then
						SoundLibrary.Play("bolt", gun.PrimaryPart, 1)
					end
				end)
			end
			if shotgun then
				task.delay(0.35, function()
					if gun.Parent and gun.PrimaryPart then
						SoundLibrary.Play("pump", gun.PrimaryPart, 1)
					end
				end)
			end
		else
			SoundLibrary.Play("dryfire", origin)
		end
	end

	----------------------------------------------------------------------
	-- aiming (hold G with a gun in your hand)
	----------------------------------------------------------------------

	function Controller:_clearAim()
		self.aiming = false
		Input.aiming = false
		Cam.aiming = false
		Cam.scope = false
	end

	function Controller:_updateAim()
		local gun, scope, extra = false, false, false
		for _, side in SIDES do
			local g = self.hands[side].grip
			if g and g.item and g.item.Parent then
				gun = true -- (any item: G aims it - a gun shoots there, everything else is thrown there)
				if Items.HasScope(g.item) then
					scope = true
					extra = g.item:GetAttribute("ScopeExtra") == true
				end
			end
		end
		local s = self.state
		local able = not self.dead and not self.car and s ~= "Ragdoll" and s ~= "Tumble" and not Input.menuOpen and not self:IsAsleep()
		self.aiming = gun and able and Input.aimHeld
		Input.aiming = self.aiming
		Cam.aiming = self.aiming
		Cam.scope = self.aiming and scope
		Cam.scopeExtra = extra
		if self.aiming and not self.wasAiming and scope then
			SoundLibrary.Play("scope", self.torso, 0.8)
		end
		self.wasAiming = self.aiming
		-- looking through the scope: your own gun must not block the view
		local hide = Cam.scope
		if hide ~= self.gunHidden then
			self.gunHidden = hide
			for _, side in SIDES do
				local g = self.hands[side].grip
				if g and g.item then
					for _, d in g.item:GetDescendants() do
						if d:IsA("BasePart") then
							d.LocalTransparencyModifier = hide and 1 or 0
						end
					end
				end
			end
		end
	end

	----------------------------------------------------------------------
	-- reloading by hand: the free hand touches the gun for the gun's reload time
	----------------------------------------------------------------------

	-- the gun that needs a reload and the free hand that can do it (two guns: none)
	function Controller:_reloadCandidate()
		for _, side in SIDES do
			local g = self.hands[side].grip
			if g and g.gun and g.gun.Parent then
				local other = side == "Left" and "Right" or "Left"
				local stats = Config.Guns[g.kind] or Config.Guns.pistol
				local ammo = g.gun:GetAttribute("Ammo") or 0
				local max = g.gun:GetAttribute("MaxAmmo") or stats.mag
				if ammo < max and not self.hands[other].grip and self:_limbUsable(ARM_OF[other]) then
					return side, other, g, stats
				end
			end
		end
		return nil, nil, nil, nil
	end

	-- where the free hand may touch: the grip, the middle of the gun, the forearm holding it
	function Controller:_gunTouchPoints(g, gunSide: string): { Vector3 }
		local pts = { g.part.Position }
		local muzzle = Items.Muzzle(g.item)
		if muzzle then
			table.insert(pts, g.part.Position:Lerp(muzzle.WorldPosition, 0.4))
		end
		local L = self.limbs[ARM_OF[gunSide]]
		if L and L.part.Parent then
			table.insert(pts, L.part.CFrame:PointToWorldSpace(Vector3.new(0, -0.5, 0)))
		end
		return pts
	end

	function Controller:_handTip(side: string): Vector3
		local L = self.limbs[ARM_OF[side]]
		return L.part.CFrame:PointToWorldSpace(Vector3.new(0, -1.05, 0))
	end

	function Controller:_updateReload(dt: number)
		local now = os.clock()
		local gunSide, free, g, stats = self:_reloadCandidate()
		local s = self.state
		if not gunSide or not free or not g or not stats or self.dead or self.car or s == "Ragdoll" or s == "Tumble" then
			self.reload = nil
			return
		end
		local r = self.reload
		if not r or r.gun ~= g.item then
			r = { gun = g.item, progress = 0, lastTouch = 0, assist = false, blockUntil = 0 }
			self.reload = r
		end
		r.gunSide, r.free, r.need = gunSide, free, stats.reload
		local pts = self:_gunTouchPoints(g, gunSide)
		local tip = self:_handTip(free)
		-- the hand snaps to the gun when you point near it (or the gun is empty) with that hand
		local intent = ((free == "Left" and Input.mouseLeft) or (free == "Right" and Input.mouseRight)) and not Input.menuOpen
		local assist = false
		if intent then
			if r.assist or (g.item:GetAttribute("Ammo") or 0) <= 0 then
				assist = true
			else
				local ray = self:_screenRay()
				local dir = ray.Direction.Unit
				for _, p in pts do
					local along = math.max(0, (p - ray.Origin):Dot(dir))
					if (p - (ray.Origin + dir * along)).Magnitude < Config.ReloadMagnetRadius or (tip - p).Magnitude < 3 then
						assist = true
						break
					end
				end
			end
		end
		r.assist = assist
		r.touchPoint = pts[2] or pts[1]
		-- touching it?
		local touching = false
		for _, p in pts do
			if (tip - p).Magnitude < Config.ReloadTouchDistance then
				touching = true
				break
			end
		end
		if touching and now >= r.blockUntil then
			-- (v2.0) every kind of weapon reloads with its own steps: a magazine out and in and the slide / bolt,
			-- shells into a tube, a crossbow string cranked back, a rocket slid into the tube
			local steps = RELOAD_STEPS[g.kind] or RELOAD_STEPS.default
			if r.progress == 0 and steps.start then
				SoundLibrary.Play(steps.start, g.part, 0.8)
			end
			local before = r.progress
			r.progress += dt
			r.lastTouch = now
			if steps.mid and before < r.need * 0.55 and r.progress >= r.need * 0.55 then
				SoundLibrary.Play(steps.mid, g.part, 0.8)
			end
			if r.progress >= r.need then
				ItemRemote:FireServer("reload", g.item)
				SoundLibrary.Play(steps.done, g.part, 1)
				if steps.after then
					local part = g.part
					task.delay(0.22, function()
						if part.Parent then
							SoundLibrary.Play(steps.after :: string, part, 0.9)
						end
					end)
				end
				r.progress = 0
				r.blockUntil = now + 0.6
				r.assist = false
			end
		elseif now - r.lastTouch > Config.ReloadForgive then
			r.progress = 0
		end
	end

	-- a velocity that throws from `from` onto what this hand points at (gravity compensated)
	function Controller:_lob(side: string, from: Vector3, speed: number, maxRange: number): Vector3
		local target = (not self.aiming and self.handTarget[side]) or self:_crosshairPoint()
		local to = target - from
		local dist = math.min(to.Magnitude, maxRange)
		local dir = MathUtil.SafeUnit(to, Cam.LookVector())
		local t = dist / speed
		-- (v2.8.1) worked out in real gravity, then slowed by somebody's Sandevistan: the same arc, in slow motion
		-- (before: a full-speed throw in the lowered gravity flew straight and far)
		local tk = self.slowK or 1
		return (dir * speed + Vector3.new(0, 0.5 * TimeScale.Gravity() * t, 0)) * tk + self.torso.AssemblyLinearVelocity * 0.3
	end

	-- turn a held-item model so its forward (grip attachment) points along v
	function Controller:_orientAlong(item: Model, v: Vector3)
		local root = item.PrimaryPart
		local grip = root and root:FindFirstChild("GripAttachment")
		if not root or not grip or not grip:IsA("Attachment") or v.Magnitude < 1 then
			return
		end
		if root:IsGrounded() or item:GetAttribute("Stuck") then
			return -- (pinned in the world: turning it would turn the world with it)
		end
		local look = CFrame.lookAt(Vector3.zero, v.Unit)
		root.CFrame = CFrame.new(root.Position) * look * grip.CFrame.Rotation:Inverse()
	end

	-- a thrown spear / C4: this client threw it, so it sees it exactly and reports what it hits
	function Controller:_trackThrown(item: Model, kind: string)
		self.thrown = self.thrown or {}
		table.insert(self.thrown, { item = item, kind = kind, t0 = os.clock(), last = nil })
	end

	local thrownParams = RaycastParams.new()
	thrownParams.FilterType = Enum.RaycastFilterType.Exclude

	function Controller:_updateThrown(dt: number)
		local list = self.thrown
		if not list or #list == 0 then
			return
		end
		local now = os.clock()
		local fx = workspace:FindFirstChild("FX")
		for i = #list, 1, -1 do
			local th = list[i]
			local item = th.item
			local root = item.PrimaryPart
			-- (the server still lists it as ours for a moment after the throw: that is not a catch)
			local holder = item:GetAttribute("HolderId")
			local caught = holder ~= nil and (holder ~= player.UserId or now - th.t0 > 1.2)
			for _, side in SIDES do
				local g = self.hands[side].grip
				if g and g.item == item then
					caught = true
				end
			end
			if not item.Parent or not root or now - th.t0 > 6 or caught or item:GetAttribute("Stuck") then
				table.remove(list, i)
				continue
			end
			local v = root.AssemblyLinearVelocity
			local point: Vector3
			if th.kind == "spear" or th.kind == "blade" then
				if v.Magnitude > 10 then
					self:_orientAlong(item, v)
				end
				point = Items.TipPoint(item) or root.Position
			else
				point = root.Position
			end
			local from = th.last or point
			th.last = point
			local seg = point - from + v * dt + (v.Magnitude > 1 and v.Unit * 0.5 or Vector3.zero)
			if seg.Magnitude < 0.05 then
				-- lying still: a spear that stopped is just a spear on the ground
				if v.Magnitude < 1 and now - th.t0 > 0.5 then
					table.remove(list, i)
				end
				continue
			end
			local ignore: { Instance } = { self.character, item }
			if fx then
				table.insert(ignore, fx)
			end
			thrownParams.FilterDescendantsInstances = ignore
			local hit = workspace:Raycast(from, seg, thrownParams)
			if hit and (hit.Instance.CanCollide or bodyOf(hit.Instance)) then
				local speed = v.Magnitude
				if th.kind == "virus" or th.kind == "molotov" then
					ItemRemote:FireServer("smash", item, hit.Position)
				elseif th.kind == "thrown" then
					if speed > 14 then
						ItemRemote:FireServer("thrownhit", item, hit.Instance, hit.Position, speed, hit.Normal, v)
						SoundLibrary.Play(bodyOf(hit.Instance) and "bodyHit" or "thud", hit.Position, math.clamp(speed / 60, 0.3, 1))
					end
				elseif th.kind == "c4" or speed > 18 then
					ItemRemote:FireServer("stick", item, hit.Instance, hit.Position, speed, hit.Normal, v)
					-- stop it right there (the server glues it in a moment)
					pcall(function()
						root.AssemblyLinearVelocity = Vector3.zero
						root.AssemblyAngularVelocity = Vector3.zero
					end)
					if th.kind == "spear" or th.kind == "blade" then
						SoundLibrary.Play(bodyOf(hit.Instance) and "stab" or "thud", hit.Position, 1)
					else
						SoundLibrary.Play("stick", hit.Position, 1)
					end
				end
				table.remove(list, i)
			end
		end
	end

	----------------------------------------------------------------------
	-- physics gun (game owner only): hold F to grab anything you point at, no weight limit
	----------------------------------------------------------------------

	function Controller:_beamStart(side: string, g)
		local muzzle = Items.Muzzle(g.item)
		if not muzzle then
			return
		end
		local origin = muzzle.WorldPosition
		local dir = self:_aimDir(side, origin)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local fx = workspace:FindFirstChild("FX")
		params.FilterDescendantsInstances = fx and { self.character, g.item, fx } or { self.character, g.item }
		local hit = workspace:Raycast(origin, dir * Config.PhysgunRange, params)
		if not hit or hit.Instance.Anchored then
			return
		end
		local part = hit.Instance
		if part.Name == "Collider" and part.Parent and part.Parent:IsA("BasePart") then
			part = part.Parent :: BasePart
		end
		local body = bodyOf(part)
		local camera = workspace.CurrentCamera
		local dist = (hit.Position - camera.CFrame.Position).Magnitude
		local beam = {
			side = side,
			item = g.item,
			target = part,
			model = body or part:FindFirstAncestorOfClass("Model") or part,
			dist = dist,
			-- a living player pulls their own body to the beam's end (we only send where it is)
			-- (v2.0, Config.DragOwnerMode: the server hands their body to us like a prop, the movers carry it)
			player = body ~= nil and Players:GetPlayerFromCharacter(body) ~= nil and not body:GetAttribute("Dead") and not Config.DragOwnerMode,
			sent = 0,
		}
		local att = Instance.new("Attachment")
		att.Name = "PhysgunGrab"
		att.Parent = part
		att.WorldPosition = hit.Position
		beam.att = att
		do
			-- the server hands it to us (players too), then these movers carry it - no weight limit
			local ap = Instance.new("AlignPosition")
			ap.Mode = Enum.PositionAlignmentMode.OneAttachment
			ap.Attachment0 = att
			ap.Position = hit.Position
			ap.MaxForce = math.huge
			ap.MaxVelocity = 400
			ap.Responsiveness = 40
			ap.Parent = part
			local ao = Instance.new("AlignOrientation")
			ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
			ao.Attachment0 = att
			ao.CFrame = att.WorldCFrame.Rotation
			ao.MaxTorque = math.huge
			ao.Responsiveness = 25
			ao.Parent = part
			beam.ap, beam.ao = ap, ao
		end
		-- the beam you see
		local visual = Instance.new("Beam")
		visual.Attachment0 = muzzle
		visual.Attachment1 = att
		visual.Color = ColorSequence.new(Color3.fromRGB(90, 200, 255))
		visual.LightEmission = 1
		visual.Width0 = 0.18
		visual.Width1 = 0.08
		visual.FaceCamera = true
		visual.CurveSize0 = 2
		visual.Segments = 12
		visual.Parent = att
		beam.visual = visual
		self.beam = beam
		ItemRemote:FireServer("physgrab", g.item, part, part.CFrame:PointToObjectSpace(hit.Position), hit.Position)
		SoundLibrary.Play("physgun", muzzle.WorldPosition, 1)
		self:_rebuildFilters()
	end

	function Controller:_beamDrop()
		local beam = self.beam
		if not beam then
			return
		end
		self.beam = nil
		Input.wheelCapture = false
		if beam.ap then
			beam.ap:Destroy()
		end
		if beam.ao then
			beam.ao:Destroy()
		end
		beam.att:Destroy()
		ItemRemote:FireServer("physdrop", beam.item)
		if self.ready then
			self:_rebuildFilters()
		end
	end

	function Controller:_updateBeam(dt: number)
		local beam = self.beam
		if not beam then
			return
		end
		local g = self.hands[beam.side].grip
		if not (g and g.item == beam.item) or not Input.useHeld or not beam.target.Parent then
			self:_beamDrop()
			return
		end
		-- scroll wheel pulls it closer / pushes it away
		Input.wheelCapture = true
		beam.dist = math.clamp(beam.dist + Input.TakeWheel() * 2.5, 4, Config.PhysgunRange)
		local ray = self:_screenRay()
		local goal = ray.Origin + ray.Direction.Unit * beam.dist
		if beam.ap then
			beam.ap.Position = goal
		end
		if beam.player then
			local now = os.clock()
			if now - beam.sent > 0.05 then
				beam.sent = now
				ItemRemote:FireServer("physmove", beam.item, goal)
			end
			if beam.model:GetAttribute("Dead") then
				beam.player = false -- (a corpse now: the server hands it to us, the movers carry it)
			end
		end
	end

	----------------------------------------------------------------------
	-- items: F = use
	----------------------------------------------------------------------

	function Controller:_use()
		local now = os.clock()
		for _, side in SIDES do
			local g = self.hands[side].grip
			if not (g and g.item and g.item.Parent) then
				continue
			end
			local kind = g.kind
			if self:_useGear(side, g, kind) then
				continue -- (v2.0: flashlight, glue, prosthetics)
			end
			if g.gun then
				local gs = Config.Guns[kind]
				if not (gs and gs.spinup) then -- (the minigun fires from _updateHeld once its barrels have spun up)
					self:_fireGun(side, g)
				end
			elseif kind == "physgun" then
				if not self.beam then
					self:_beamStart(side, g)
				end
			elseif Items.Melee(g.item) then
				self.attacks = self.attacks or {}
				local a = self.attacks[side]
				local melee = Items.Melee(g.item)
				local slow = kind == "axe" or kind == "bat" or kind == "sledge"
				if not a or now - a.t0 > Config.MeleeAttackTime * (slow and 1.3 or 1) then
					local L = self.limbs[ARM_OF[side]]
					local shoulder = self.torso.CFrame:PointToWorldSpace(L.def.torsoPivot)
					local dir = self:_aimDir(side, shoulder)
					self.attacks[side] = {
						kind = melee,
						t0 = now,
						dir = dir,
						side = side == "Right" and 1 or -1,
						slow = slow,
					}
					SoundLibrary.Play("slash", self.torso, kind == "spear" and 0.5 or 0.8, slow and 0.8 or 1)
					if kind == "spear" then
						-- the thrust: lunge forward and drive the arm along the spear
						task.delay(0.1, function()
							if self.alive and self.torso.Parent then
								pcall(function()
									self.torso:ApplyImpulse(MathUtil.Flat(dir) * Config.SpearLunge * (self.slowK or 1) * self.torso.AssemblyMass)
									L.part:ApplyImpulse(dir * 30 * (self.slowK or 1) * L.part.AssemblyMass)
								end)
							end
						end)
					end
				end
			elseif kind == "tether" then
				-- the crosshair picks the spot (the first click marks it, the second ties)
				local cam = workspace.CurrentCamera
				local ray = cam:ViewportPointToRay(cam.ViewportSize.X * 0.5, cam.ViewportSize.Y * 0.5)
				local hit = workspace:Raycast(ray.Origin, ray.Direction * (Config.TetherRange + 20), self.rayParams)
				if hit and (hit.Position - self.torso.Position).Magnitude <= Config.TetherRange then
					ItemRemote:FireServer("tether", g.item, hit.Instance, hit.Position)
					SoundLibrary.Play("tether", hit.Position, 0.7)
				else
					SoundLibrary.Play("dryfire", g.part, 0.5)
				end
			elseif kind == "grenade" or kind == "flash" then
				if not g.item:GetAttribute("Armed") then
					ItemRemote:FireServer("use", g.item)
					SoundLibrary.Play("pin", g.part, 0.8)
				end
			elseif kind == "chip" or kind == "camera" then
				local chipRemote = ReplicatedStorage.Remotes:FindFirstChild("Chip")
				if chipRemote then chipRemote:FireServer(kind == "chip" and "helduse" or "cam", g.item) end
			elseif kind == "bandage" then
				if not self.bandaging then
					-- wrap it on: the hand circles around the body part, then the server applies it
					self.bandaging = { t0 = now, side = side, item = g.item, target = self:_bandageTarget() }
					SoundLibrary.Play("bandage", g.part, 0.9)
				end
			elseif kind == "rope" then
				ItemRemote:FireServer("use", g.item)
				SoundLibrary.Play("rope", g.part, 0.8)
			elseif kind == "ledger" or kind == "apple" then
				ItemRemote:FireServer("use", g.item) -- (v2.1) F: open the Black Ledger / eat or feed the apple (LedgerService)
			elseif kind == "c4" or kind == "virus" or kind == "molotov" then
				-- F throws it (C4 sticks to whatever it hits, the bottle shatters)
				self:_release(side, true)
				break
			elseif kind == "laser" then
				ItemRemote:FireServer("use", g.item)
			elseif kind == "detonator" then
				ItemRemote:FireServer("use", g.item)
				SoundLibrary.Play("detonator", g.part, 1)
			elseif kind == "boombox" then
				if self.onBoombox then
					self.onBoombox(g.item)
				end
			elseif kind == "nuke" then
				if not g.item:GetAttribute("Armed") then
					ItemRemote:FireServer("use", g.item)
				end
			end
		end
	end
	Controller._fire = Controller._use

	-- flamethrower: while F is held the nozzle burns (seen right away here, the server lights it
	-- for everybody and does the burning)
	function Controller:_updateFlame(_dt: number)
		local now = os.clock()
		local active = nil
		if Input.useHeld and not Input.menuOpen and not self.dead then
			for _, side in SIDES do
				local g = self.hands[side].grip
				if g and g.kind == "flamethrower" and g.item.Parent and (g.item:GetAttribute("Fuel") or 0) > 0 then
					active = { side = side, g = g }
					break
				end
			end
		end
		local last = self.flameItem
		if last and (not active or active.g.item ~= last) then
			for _, d in last:GetDescendants() do
				if (d:IsA("ParticleEmitter") and d.Name == "Flame") or (d:IsA("PointLight") and d.Name == "FlameLight") then
					d.Enabled = false
				end
			end
			if self.flameSound then
				self.flameSound:Destroy()
				self.flameSound = nil
			end
			self.flameItem = nil
		end
		if not active then
			return
		end
		local item = active.g.item
		if self.flameItem ~= item then
			self.flameItem = item
			for _, d in item:GetDescendants() do
				if (d:IsA("ParticleEmitter") and d.Name == "Flame") or (d:IsA("PointLight") and d.Name == "FlameLight") then
					d.Enabled = true
				end
			end
			local snd = SoundLibrary.Loop("flame", active.g.part)
			if snd then
				snd.Volume = 0.8
				snd:Play()
			end
			self.flameSound = snd
		end
		if now - (self.flameSent or 0) > 0.08 then
			self.flameSent = now
			local muzzle = Items.Muzzle(item)
			local from = muzzle and muzzle.WorldPosition or active.g.part.Position
			ItemRemote:FireServer("flame", item, self:_aimDir(active.side, from))
		end
	end

	-- F held: full auto rifle, physics gun beam; bandage / reload timers
	function Controller:_updateHeld(dt: number)
		local now = os.clock()
		local spinning = false
		if Input.useHeld and not Input.menuOpen then
			for _, side in SIDES do
				local g = self.hands[side].grip
				if g and g.gun and Items.IsAuto(g.item) then
					local stats = Config.Guns[g.kind]
					if stats and stats.spinup then
						-- the minigun's barrels spin up before it fires
						spinning = true
						if (self.spin or 0) == 0 then
							SoundLibrary.Play("spinUp", g.part, 0.8)
						end
						self.spin = (self.spin or 0) + dt
						if self.spin >= Config.MinigunSpinUp then
							self:_fireGun(side, g)
						end
					else
						self:_fireGun(side, g)
					end
				end
			end
		end
		if not spinning then
			self.spin = 0
		end
		self:_updateFlame(dt)
		self:_updateBeam(dt)
		local b = self.bandaging
		if b then
			local g = self.hands[b.side].grip
			if not (g and g.item == b.item and b.item.Parent) then
				self.bandaging = nil
			elseif now - b.t0 >= Config.BandageTime then
				self.bandaging = nil
				ItemRemote:FireServer("use", b.item)
			end
		end
		self:_updateReload(dt)
		self:_updateThrown(dt)
		self:_updateTwoHand(dt)
	end

	-- melee hits: the tip of the spear / edge of a blade / end of the bat going into somebody fast
	-- enough. Slashes also cut ropes.
	function Controller:_updateMelee(_dt: number)
		local now = os.clock()
		self.meleeHits = self.meleeHits or {}
		for _, side in SIDES do
			local g = self.hands[side].grip
			if not (g and g.item and g.item.Parent) then
				continue
			end
			local kind = Items.Melee(g.item)
			if not kind then
				continue
			end
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.RespectCanCollide = false
			local fx = workspace:FindFirstChild("FX")
			params.FilterDescendantsInstances = fx and { self.character, g.item, fx } or { self.character, g.item }
			local need = kind == "stab" and Config.SpearStabSpeed or (kind == "blunt" and Config.BatSwingSpeed or Config.BladeSlashSpeed)
			-- (v2.0) the chainsaw: only while its motor runs (F), and then any touch of the bar cuts
			local saw = g.kind == "chainsaw"
			local cooldown = Config.MeleeCooldown
			if saw then
				if not g.item:GetAttribute("SawOn") then
					continue
				end
				need = 0
				cooldown = Config.ChainsawTick
			end
			local ties = workspace:FindFirstChild("Ties")
			for _, pt in Items.DamagePoints(g.item) do
				local v = pt.part:GetVelocityAtPosition(pt.point)
				for _, p in workspace:GetPartBoundsInRadius(pt.point, 0.45, params) do
					local body = bodyOf(p)
					if not body then
						-- (v2.0) the Crawler / a shark: its hit box
						local cm = p:FindFirstAncestorOfClass("Model")
						if cm and cm:GetAttribute("Creature") and not cm:GetAttribute("Dead") then
							local rel = (v - p.AssemblyLinearVelocity).Magnitude
							local ck = cm:GetFullName()
							if rel >= need and now - (self.meleeHits[ck] or 0) >= cooldown then
								self.meleeHits[ck] = now
								ItemRemote:FireServer("melee", g.item, p, pt.point, saw and math.max(rel, 8) or rel)
							end
						end
						continue
					end
					if body == self.character then
						continue
					end
					local region = regionOf(p, body)
					if not region then
						continue
					end
					local rel = (v - p.AssemblyLinearVelocity).Magnitude
					if rel < need then
						continue
					end
					local key = body:GetFullName() .. region
					if now - (self.meleeHits[key] or 0) < cooldown then
						continue
					end
					self.meleeHits[key] = now
					ItemRemote:FireServer("melee", g.item, p, pt.point, saw and math.max(rel, 8) or rel)
					if saw then
						Cam.Shake(0.12)
						self.sawBiteT = now
					else
						SoundLibrary.Play(kind == "stab" and "stab" or (kind == "blunt" and "bodyHit" or "slash"), pt.point, 0.8)
						Cam.Shake(kind == "blunt" and 0.45 or 0.25)
					end
				end
				-- cut a rope
				if kind == "slash" and ties and v.Magnitude > need * 0.6 then
					for _, rope in ties:GetChildren() do
						if rope:IsA("RopeConstraint") and rope.Attachment0 and rope.Attachment1 then
							local d = segmentDistance(pt.point, rope.Attachment0.WorldPosition, rope.Attachment1.WorldPosition)
							if d < 0.9 and now - (self.meleeHits[rope] or 0) > 0.4 then
								self.meleeHits[rope] = now
								ItemRemote:FireServer("cut", g.item, rope)
								SoundLibrary.Play("slash", pt.point, 1, 1.2)
							end
						end
					end
				end
			end
		end
	end

	function Controller:_updateGuns(dt: number)
		self:_updateHeld(dt)
		self:_updateMelee(dt)
	end

	function Controller:GetGunInfo(): { ammo: number, max: number, name: string, reloading: boolean, progress: number, dual: boolean, free: string?, assist: boolean, scope: boolean, kind: string?, lineOut: boolean }?
		local guns = 0
		local info = nil
		for _, side in SIDES do
			local g = self.hands[side].grip
			if g and g.gun and g.gun.Parent then
				guns += 1
				if not info then
					local k = Items.Kinds[g.kind or "pistol"]
					local stats = Config.Guns[g.kind] or Config.Guns.pistol
					info = {
						ammo = g.gun:GetAttribute("Ammo") or 0,
						max = g.gun:GetAttribute("MaxAmmo") or stats.mag,
						name = k and k.name or "GUN",
						reloading = false,
						progress = 0,
						dual = false,
						free = side == "Left" and "Right" or "Left",
						assist = false,
						scope = Items.HasScope(g.item),
						kind = g.kind,
						lineOut = g.item:GetAttribute("LineOut") == true,
					}
				end
			end
		end
		if not info then
			return nil
		end
		info.dual = guns >= 2
		local r = self.reload
		if r and r.need and r.need > 0 then
			info.progress = math.clamp(r.progress / r.need, 0, 1)
			info.reloading = r.progress > 0
			info.assist = r.assist
			info.free = r.free
		end
		return info
	end

	-- the non-gun item in your hands (for the HUD hint)
	function Controller:GetItemInfo(): { kind: string, armed: boolean, busy: boolean, fuel: number?, coats: number?, on: boolean, stillwater: boolean?, side: string? }?
		for _, side in SIDES do
			local g = self.hands[side].grip
			if g and g.item and not g.gun and g.item.Parent then
				local fuel = g.item:GetAttribute("Fuel")
				return {
					kind = g.kind,
					coats = g.item:GetAttribute("Coats"),
					on = g.item:GetAttribute("On") == true,
					armed = g.item:GetAttribute("Armed") == true,
					busy = self.bandaging ~= nil or self.beam ~= nil,
					playing = g.item:GetAttribute("Playing") == true,
					fuel = typeof(fuel) == "number" and fuel or nil,
					stillwater = g.item:GetAttribute("Stillwater") == true, -- (v2.8)
					side = side,
				}
			end
		end
		return nil
	end

	----------------------------------------------------------------------
	-- climbing
	----------------------------------------------------------------------

	-- climbing is ONLY Space (looking up / pointing the hand never starts it by accident)
	function Controller:_updateClimbIntent()
		local hasStatic = self:_hasStaticGrip()
		self.climbIntent = hasStatic and Input.jumpHeld and not Input.menuOpen
	end

	-- grab the wall higher up with the free (or lowest) hand
	function Controller:_regrip(wallDir: Vector3)
		local now = os.clock()
		if now - self.lastRegrip < Config.ClimbRegripCooldown then
			return
		end
		local chosen: string? = nil
		for _, side in SIDES do
			if not self.hands[side].grip and self:_limbUsable(ARM_OF[side]) then
				chosen = side
				break
			end
		end
		if not chosen then
			local lowestY = math.huge
			for _, side in SIDES do
				local g = self.hands[side].grip
				if g and g.static and g.a1.Parent and g.a1.WorldPosition.Y < lowestY then
					lowestY = g.a1.WorldPosition.Y
					chosen = side
				end
			end
		end
		if not chosen then
			return
		end
		local L = self.limbs[ARM_OF[chosen]]
		local shoulder = self.torso.CFrame:PointToWorldSpace(L.def.torsoPivot)
		local origin = shoulder + Vector3.new(0, Config.ClimbRegripStep, 0) - wallDir * 0.3
		local hit = workspace:Raycast(origin, wallDir * 2.6, self.grabParams)
		if hit and isValidGrabTarget(self, hit.Instance) and isSolid(self, hit.Instance) then
			local other = chosen == "Left" and "Right" or "Left"
			local og = self.hands[other].grip
			-- never let go of the last hold
			if self.hands[chosen].grip and not (og and og.static) then
				return
			end
			if self.hands[chosen].grip then
				self:_release(chosen, false)
			end
			self.hands[chosen].armed = true
			self:_grip(chosen, hit.Instance, hit.Position)
			local g = self.hands[chosen].grip
			if g then
				g.hung = true
			end
			self.lastRegrip = now
		end
	end

	-- Hanging: with Space the body is pulled up at a steady speed (a velocity, never a stiff
	-- position spring). Without Space you simply hang from your hands.
	function Controller:_climbForce(moveWorld: Vector3, heading: CFrame, desired: Vector3, vh: Vector3, M: number, W: number): Vector3
		local _, G = self:_hasStaticGrip()
		if not G then
			return Vector3.zero
		end
		local torso = self.torso
		local pos = torso.Position
		local vel = torso.AssemblyLinearVelocity
		local toWall = MathUtil.Flat(G - pos)
		local wallDir = MathUtil.SafeUnit(toWall, heading.LookVector)
		if self.climbIntent then
			local vyWant = Config.ClimbSpeed
			local hWant = Vector3.zero
			if toWall.Magnitude > 1.3 then
				hWant = wallDir * 2 -- stay close to the wall
			end
			local mantling = false
			-- (v2.8.1) THE MUSCLE-UP: the hold is at the top of the wall and there is room up there - you go over it in one
			-- move (up past the edge, then forward onto the top), from wherever you hang
			if pos.Y > G.Y - 3.8 * self.scale and self._mantleTop then
				local top = self:_mantleTop(G, wallDir)
				if top then
					self:_startMantle(top, wallDir)
					return Vector3.zero
				end
			end
			if pos.Y > G.Y - 0.9 then
				local above = workspace:Raycast(pos + Vector3.new(0, 1.7, 0) - wallDir * 0.3, wallDir * 2.4, self.rayParams)
				if above and (above.Instance:IsGrounded() or above.Instance.AssemblyMass > self.bodyMass * Config.HeavyRatio) then
					if pos.Y > G.Y - 0.3 then
						self:_regrip(wallDir)
					end
				else
					-- top edge: climb over it. (v2.8) a firm pull up and, as soon as the chest is over the edge (or after a
					-- moment), the hands let go and the body gets a push forward onto the top: before, you could hang at
					-- the edge forever and never get over it
					mantling = true
					vyWant = Config.ClimbSpeed + 2
					hWant = wallDir * Config.MantleSpeed
					self.mantleT0 = self.mantleT0 or os.clock()
					local over = pos.Y > G.Y + 0.25
					if over or os.clock() - self.mantleT0 > 1.0 then
						self.mantleT0 = nil
						for _, side in SIDES do
							local hg = self.hands[side].grip
							if hg and hg.static then
								self:_release(side, false)
							end
						end
						local push = wallDir * Config.MantlePush + Vector3.new(0, over and 9 or 20, 0)
						for _, bp in self.character:GetChildren() do
							if bp:IsA("BasePart") and not bp.Anchored then
								bp.AssemblyLinearVelocity = Vector3.new(bp.AssemblyLinearVelocity.X * 0.3, math.max(bp.AssemblyLinearVelocity.Y, 0), bp.AssemblyLinearVelocity.Z * 0.3) + push
							end
						end
						return Vector3.zero
					end
				end
			end
			if not mantling then
				self.mantleT0 = nil
			end
			local fy = M * (workspace.Gravity + (vyWant - vel.Y) * 7)
			local fh = (hWant - MathUtil.Flat(vel)) * 5 * M
			return MathUtil.ClampMagnitude(Vector3.new(fh.X, fy, fh.Z), W * Config.ClimbPullFactor)
		end
		local acc = MathUtil.ClampMagnitude((desired * 0.5 - vh) * 3, Config.AirAccel * 0.6)
		return Vector3.new(acc.X, 0, acc.Z) * M
	end

	----------------------------------------------------------------------
	-- HUD info
	----------------------------------------------------------------------

	function Controller:GetHandInfo(side: string)
		local hand = self.hands[side]
		local L = self.limbs and self.limbs[ARM_OF[side]]
		local info = {
			armed = hand.armed,
			holding = hand.grip ~= nil,
			name = nil :: string?,
			mass = 0,
			static = false,
			gun = false,
			item = false,
			broken = L ~= nil and L.broken and not L.severed,
			severed = L ~= nil and L.severed,
		}
		local g = hand.grip
		if g and g.part.Parent then
			local body = g.part:FindFirstAncestorOfClass("Model")
			if g.item then
				info.name = g.item.Name
				info.gun = g.gun ~= nil
				info.item = true
			elseif body and body:GetAttribute("RagdollRig") then
				info.name = body.Name
			elseif body and body ~= workspace and body.PrimaryPart then
				info.name = body.Name
			else
				info.name = g.part.Name
			end
			info.static = g.static and g.part:IsGrounded()
			info.mass = (g.part.AssemblyRootPart or g.part).AssemblyMass
		end
		return info
	end
end
