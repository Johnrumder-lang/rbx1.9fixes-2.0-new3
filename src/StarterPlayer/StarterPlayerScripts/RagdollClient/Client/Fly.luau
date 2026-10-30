--!nonstrict
-- Fly (mixin for CharacterController): the game owner presses B (away from cars) to fly, and is
-- invincible while flying (the server keeps that). B again lands.
--   WASD fly where the camera looks · Space up · Ctrl down · Shift faster (x2.5)
--   N (or click / tap the speed at the top) types a new speed: any number, or "inf"
--   Infinite strength: whatever loose thing you grab (a car, the anvil) comes along, no weight
--   limit (see Hands: strong carry). Landing drops it.
--   Nothing knocks a flying body over; R (go limp) stops flying.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))
local Items = require(Shared:WaitForChild("Items"))
local FlySpeed = require(Shared:WaitForChild("FlySpeed"))

local AdminRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Admin") :: RemoteEvent

local Modules = script.Parent
local Input = require(Modules:WaitForChild("Input"))
local Cam = require(Modules:WaitForChild("CameraController"))

-- the speed you set stays for the whole session (also after you die)
local flySpeed = Config.FlySpeed

return function(Controller)
	-- typed text -> speed (math.huge = INF) / speed -> text, see Shared/FlySpeed
	Controller.ParseFlySpeed = FlySpeed.Parse
	Controller.FlySpeedText = FlySpeed.Text

	function Controller:GetFlySpeed(): number
		return flySpeed
	end

	function Controller:SetFlySpeed(v: number)
		if typeof(v) ~= "number" or v ~= v or v <= 0 then
			return
		end
		flySpeed = math.max(v, 0.5)
	end

	-- the roots of everything the hands carry (a car, a dragged body): it flies along at your speed
	function Controller:_carriedRoots(): { BasePart }
		local out = {}
		local function add(p: BasePart?)
			if p and not p.Anchored and not table.find(out, p) then
				table.insert(out, p)
			end
		end
		for _, side in { "Left", "Right" } do
			local g = self.hands[side].grip
			if g and not g.hold and not g.item and not g.remoteBody and g.part.Parent and (g.strong or not g.static) then
				if g.body and g.body.Parent then
					for _, d in g.body:GetChildren() do
						if d:IsA("BasePart") and d.AssemblyRootPart == d then
							add(d)
						end
					end
				else
					add(g.part.AssemblyRootPart)
				end
			end
		end
		return out
	end

	-- every loose piece of the body (and what it carries) gets this speed
	function Controller:_flySetVelocity(v: Vector3)
		for _, d in self.character:GetChildren() do
			if d:IsA("BasePart") and not d.Anchored and d.AssemblyRootPart == d then
				d.AssemblyLinearVelocity = v
			end
		end
		for _, root in self:_carriedRoots() do
			pcall(function()
				root.AssemblyLinearVelocity = v
			end)
		end
	end

	function Controller:SetFlying(on: boolean)
		if (self.flying == true) == on then
			return
		end
		if on and (self.dead or self.car or not Items.Has(game:GetService("Players").LocalPlayer, "fly")) then
			return
		end
		self.flying = on
		AdminRemote:FireServer("fly", on)
		SoundLibrary.Play(on and "flyOn" or "flyOff", nil, 1)
		if on then
			self:_dropTwoHand(false)
			self:_setState("Flying")
			-- a little hop off the ground
			pcall(function()
				self.torso:ApplyImpulse(Vector3.new(0, 18, 0) * self.torso.AssemblyMass)
			end)
			-- already holding something heavy (a car): now you lift it
			for _, side in { "Left", "Right" } do
				local hand = self.hands[side]
				local g = hand.grip
				if g and not g.hold and not g.item and not g.body and not g.strong and g.part.Parent and g.a1.Parent and not g.part:IsGrounded() then
					local part, point = g.part, g.a1.WorldPosition
					self:_release(side, false)
					hand.armed = true
					self:_grip(side, part, point)
				end
			end
		else
			-- the strength is gone: what you carried falls
			for _, side in { "Left", "Right" } do
				local g = self.hands[side].grip
				if g and g.strong then
					self:_release(side, false)
				end
			end
			-- landing at a huge speed: brake first (you are not invincible any more)
			local v = self.torso.AssemblyLinearVelocity
			if v.Magnitude > Config.FlyLandSpeed then
				self:_flySetVelocity(v.Unit * Config.FlyLandSpeed)
			end
			self:_setState("Airborne")
		end
	end

	-- force on the torso + the torso's orientation while flying
	function Controller:_flyForces(heading: CFrame, dt: number): (Vector3, CFrame, number)
		local M = self.bodyMass + (self.carryMass or 0)
		local g = workspace.Gravity
		local vel = self.torso.AssemblyLinearVelocity
		local blocked = Input.menuOpen or Input.promptOpen
		local mv = blocked and Vector3.zero or Input.GetMoveVector()
		local dir = Cam.Rotation():VectorToWorldSpace(Vector3.new(mv.X, 0, mv.Z))
		local vertical = (Input.jumpHeld and 1 or 0) - (Input.downHeld and 1 or 0)
		if blocked then
			vertical = 0
		end
		dir += Vector3.new(0, vertical, 0)
		if dir.Magnitude > 1 then
			dir = dir.Unit
		end
		local speed = math.min(flySpeed, Config.FlyMaxSpeed)
		if Input.Running() then
			speed = math.min(speed * Config.FlySprintMult, Config.FlyMaxSpeed)
		end
		local desired = dir * speed
		local hover = Vector3.new(0, M * g, 0)
		local force
		if speed > Config.FlyDirectSpeed or vel.Magnitude > Config.FlyDirectSpeed * 1.2 then
			-- fast: steer the speed of every part directly. A force big enough to push a ragdoll to
			-- thousands of studs/s would tear its joints apart; this way all parts move together.
			-- Full speed (or a stop) in about 0.4 s, whatever the speed.
			local accMax = math.max(Config.FlyAccel, speed * 2.5, vel.Magnitude * 2.5)
			local newV = vel + MathUtil.ClampMagnitude(desired - vel, accMax * dt)
			self:_flySetVelocity(newV)
			force = hover
		else
			local acc = MathUtil.ClampMagnitude((desired - vel) * Config.FlyGain, math.max(Config.FlyAccel, speed * 3))
			force = hover + acc * M
		end
		-- the pose: upright while hovering, flat like a superhero when fast
		local k = math.clamp(vel.Magnitude / (Config.FlySpeed * Config.FlySprintMult), 0, 1)
		local flat = MathUtil.Flat(vel)
		local face = flat.Magnitude > 3 and flat.Unit or heading.LookVector
		local climb = vel.Magnitude > 2 and math.clamp(vel.Y / vel.Magnitude, -1, 1) or 0
		local pitch = -math.rad(78) * k * (1 - math.max(0, climb) * 0.6) - math.rad(10) * math.max(0, -climb)
		return force, CFrame.lookAt(Vector3.zero, face) * CFrame.Angles(pitch, 0, 0), k
	end

	function Controller:_flyPose(isLeg: boolean, side: number): CFrame
		local k = self.flySpeedK or 0
		if isLeg then
			return CFrame.Angles(-0.08 + (1 - k) * 0.15 * math.sin(self.time * 2 + side), 0, side * 0.07)
		end
		-- fast: the leading arm stretched over the head, the other along the body
		if side > 0 then
			return CFrame.Angles(0.3 + 2.75 * k, 0, side * (0.35 * (1 - k) + 0.08))
		end
		return CFrame.Angles(0.3 * (1 - k) - 0.1 * k, 0, side * (0.4 * (1 - k) + 0.12))
	end
end
