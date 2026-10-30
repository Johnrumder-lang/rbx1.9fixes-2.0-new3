--!nonstrict
-- TwoHand (mixin for CharacterController): Y = hold the item in your hand with BOTH hands.
--   The free hand grabs the item too (guns: under the barrel, spear: further up the shaft, blades /
--   bats / hammers: below the other hand on the handle, everything else: the middle of it).
--   Two hands = much less recoil and spread, the sniper barely moves you, swings are steadier.
--   Y again (or Q / E on the supporting hand) lets go with the second hand. Reloading by hand
--   takes the supporting hand off the gun for a moment and puts it back afterwards.
--   (v1.8) The second hand is NOT jointed to the item any more: a joint closed a loop
--   (arm - item - arm) that the two arm muscles fought over - the item jerked, twisted and the
--   grip fell off. Now a pull that acts on the hand only brings it onto the item and keeps it
--   there; the item does not feel it.
--   (v1.9) The point on the item is often 3+ studs from the supporting shoulder, but an arm only
--   reaches ~1.5. The old pull dragged the whole body towards a point it could never reach (and
--   the item rides on the other hand, so the point ran away): you got pulled in one direction.
--   Now the hand's target is clamped to what the arm can reach, so the pull can never move you.
--   (v2.0) The real cause of "I can't move / I float" with both hands: the pull pushed only on the hand
--   (no reaction force), which is a force from nowhere on your own body. Now the pull is a spring BETWEEN
--   the hand and the item (both are part of you): equal and opposite, it can only bring hand and item
--   together and never moves, lifts or pins the body.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))

local SIDES = { "Left", "Right" }
local ARM_OF = { Left = "LeftArm", Right = "RightArm" }
local TWO_HAND_REACH = 1.4 -- studs from the shoulder: an arm is 1.5 long
local LOW_ON_HANDLE = { katana = true, bat = true, sledge = true, axe = true, blade = true }

return function(Controller)
	-- where on the item the second hand goes (in the item's PrimaryPart space)
	function Controller:_supportPoint(item: Model, kind: string?): Vector3?
		local root = item.PrimaryPart
		local grip = root and root:FindFirstChild("GripAttachment")
		if not root or not grip or not grip:IsA("Attachment") then
			return nil
		end
		local gripWorld = grip.WorldCFrame
		local p: Vector3
		if Items.IsGun(item) then
			local muzzle = Items.Muzzle(item)
			if muzzle then
				-- under the barrel, but within reach of the other arm
				local along = muzzle.WorldPosition - gripWorld.Position
				p = gripWorld.Position + along.Unit * math.min(along.Magnitude * 0.4, 0.9) - gripWorld.UpVector * 0.12
			else
				p = gripWorld.Position + gripWorld.LookVector * 1.2
			end
		elseif kind == "spear" then
			p = gripWorld.Position + gripWorld.LookVector * 1.6
		elseif kind and LOW_ON_HANDLE[kind] then
			p = gripWorld.Position - gripWorld.LookVector * 0.7
		else
			p = root.Position
		end
		return root.CFrame:PointToObjectSpace(p)
	end

	function Controller:_dropTwoHand(forget: boolean?)
		local th = self.twoHand
		if forget then
			self.twoHandWanted = nil
		end
		if not th then
			return
		end
		self.twoHand = nil
		for _, inst in { th.socket, th.a0, th.a1 } do
			if inst and inst.Parent then
				inst:Destroy()
			end
		end
	end

	-- the item in one hand and the other hand free and working, or nil
	function Controller:_twoHandCandidate(): (string?, string?, any)
		for _, side in SIDES do
			local g = self.hands[side].grip
			local other = side == "Left" and "Right" or "Left"
			if g and g.item and g.item.Parent and not g.static and not self.hands[other].grip and self:_limbUsable(ARM_OF[other]) then
				return side, other, g
			end
		end
		return nil, nil, nil
	end

	function Controller:_attachTwoHand(): boolean
		local main, support, g = self:_twoHandCandidate()
		if not main or not support or not g then
			return false
		end
		local L = self.limbs[ARM_OF[support]]
		local root = g.item.PrimaryPart
		local localPoint = self:_supportPoint(g.item, g.kind)
		if not L or not root or not localPoint then
			return false
		end
		local a0 = Instance.new("Attachment")
		a0.Name = "SupportHand"
		a0.Position = Vector3.new(0, -1, 0)
		a0.Parent = L.part
		local a1 = Instance.new("Attachment")
		a1.Name = "SupportPoint"
		a1.Position = localPoint
		a1.Parent = root
		-- (v2.0) a soft spring between the hand and its spot on the item, with the reaction force on: hand and item
		-- (both part of your own body) are pulled together, the body as a whole feels nothing
		local socket = Instance.new("AlignPosition")
		socket.Name = "SupportGrip"
		socket.Mode = Enum.PositionAlignmentMode.TwoAttachment
		socket.Attachment0 = a0
		socket.Attachment1 = a1
		socket.ReactionForceEnabled = true
		socket.RigidityEnabled = false
		socket.MaxForce = L.part:GetMass() * workspace.Gravity * Config.TwoHandSpring
		socket.MaxVelocity = 30
		socket.Responsiveness = 35
		socket.Enabled = Config.TwoHandPull
		socket.Parent = L.part
		-- the supporting arm never bumps into the item
		for _, ip in g.item:GetDescendants() do
			if ip:IsA("BasePart") then
				local nc = Instance.new("NoCollisionConstraint")
				nc.Part0 = ip
				nc.Part1 = L.part
				nc.Parent = socket
			end
		end
		self.twoHand = { main = main, support = support, item = g.item, a0 = a0, a1 = a1, socket = socket, t0 = os.clock() }
		self.hands[support].armed = false
		SoundLibrary.Play("click", root, 0.5)
		return true
	end

	-- Y
	function Controller:_toggleTwoHand()
		if self.twoHand then
			self:_dropTwoHand(true)
			return
		end
		if self.car or self.state == "Ragdoll" or self.dead then
			return
		end
		if self:_attachTwoHand() then
			self.twoHandWanted = true
		end
	end

	function Controller:IsTwoHanded(item: Instance?): boolean
		local th = self.twoHand
		return th ~= nil and (item == nil or th.item == item)
	end

	function Controller:_updateTwoHand(_dt: number)
		local th = self.twoHand
		if th then
			local g = self.hands[th.main].grip
			local stillOk = g and g.item == th.item and th.item.Parent and th.socket.Parent and th.a1.Parent
				and not self.hands[th.support].grip
				and self:_limbUsable(ARM_OF[th.support])
				and not self.car
				and self.state ~= "Ragdoll"
				and not self.dead
			-- where the hand can actually go: the point on the item, but never further than the arm reaches
			local L = self.limbs[ARM_OF[th.support]]
			local target = th.a1.WorldPosition
			if L and L.part and self.torso then
				local shoulder = self.torso.CFrame:PointToWorldSpace(L.def.torsoPivot)
				local d = target - shoulder
				if d.Magnitude > TWO_HAND_REACH then
					target = shoulder + d.Unit * TWO_HAND_REACH
				end
				-- the hand is stuck somewhere (a wall, a stretched arm) for a while: let go
				local far = (th.a0.WorldPosition - th.a1.WorldPosition).Magnitude > 2.5 and (th.a0.WorldPosition - target).Magnitude > 1.2
				th.farTime = far and (th.farTime or 0) + _dt or 0
				if stillOk and os.clock() - th.t0 > 0.8 and th.farTime > 0.8 then
					stillOk = false
				end
			end
			-- reloading by hand needs that hand
			if self.reload and self.reload.assist then
				stillOk = false
			end
			if not stillOk then
				local keep = self.twoHandWanted and g and g.item == th.item
				self:_dropTwoHand(not keep)
			end
			return
		end
		-- put the second hand back after a reload / getting up
		if self.twoHandWanted and not (self.reload and self.reload.assist) and self.state ~= "Ragdoll" and not self.car then
			local main = self:_twoHandCandidate()
			if not main then
				if not (self.hands.Left.grip or self.hands.Right.grip) then
					self.twoHandWanted = nil -- nothing in the hands any more
				end
				return
			end
			self:_attachTwoHand()
		end
	end

	-- the supporting arm reaches for its spot on the item (nil = not supporting)
	function Controller:_twoHandAim(side: string, shoulder: Vector3): Vector3?
		local th = self.twoHand
		if not th or th.support ~= side or not th.a1.Parent then
			return nil
		end
		local d = th.a1.WorldPosition - shoulder
		return d.Magnitude > 0.05 and d.Unit or nil
	end

	-- recoil / spread multipliers for a gun
	function Controller:_twoHandMult(item: Instance): (number, number)
		if self.twoHand and self.twoHand.item == item then
			return Config.TwoHandRecoil, Config.TwoHandSpread
		end
		return 1, 1
	end
end
