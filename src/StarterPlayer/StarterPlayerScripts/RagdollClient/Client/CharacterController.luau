--!nonstrict
-- CharacterController: physics-driven "Human Fall Flat" style body (core).
--
--   * A spring force on the torso keeps the hips at leg height. While walking the legs do not
--     collide with the world (no more getting wedged on steps); per-foot raycasts place every foot
--     on the surface below it (IK), so legs climb stairs, stand on slopes and react to parts.
--   * Balance: an AlignOrientation with limited torque keeps the torso upright, leaning into
--     motion and towards where the hands reach. Big hits still topple you.
--   * Stances: stand, crouch (C), lie down (X). Lying / downed bodies crawl on their arms.
--     X in the air = dive forward and land on your belly.
--   * Stairs / steps: the hips follow the slope of the steps ahead (no lag), and walking into a
--     step that is still too high gives a small hop onto it.
--   * Driving: in a car the body is welded into the seat (VehicleClient drives the car).
--   * Hands (Hands.luau): Q/E grab, LMB/RMB aim, guns, climbing.
--   * Sensor (Sensor.luau): fall damage, objects hitting you, spikes, crushing, wall slams, strikes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))
local ContactSolver = require(Shared:WaitForChild("ContactSolver"))
local TimeScale = require(Shared:WaitForChild("TimeScale"))
local Poses = require(Shared:WaitForChild("Poses"))
local LocalPlayer = game:GetService("Players").LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StateRemote = Remotes:WaitForChild("State") :: RemoteEvent

local Modules = script.Parent
local Input = require(Modules:WaitForChild("Input"))
local Cam = require(Modules:WaitForChild("CameraController"))

local Controller = {}
Controller.__index = Controller

local SIDES = { "Left", "Right" }
local ARM_OF = { Left = "LeftArm", Right = "RightArm" }
local DOWN = Vector3.new(0, -1, 0)
local COS_SLOPE = math.cos(math.rad(Config.MaxWalkableSlope))
local PRONE_ROT = CFrame.Angles(-math.pi / 2, 0, 0) -- face down, head forward

Controller.SIDES = SIDES
Controller.ARM_OF = ARM_OF

local UPRIGHT_STATES = { Standing = true, Stumbling = true, GettingUp = true }
local LYING_STATES = { Prone = true, Downed = true }
local KNOCKED_STATES = { Ragdoll = true, Tumble = true, Downed = true, Dead = true }
local DIVE_ROT = CFrame.Angles(-1.3, 0, 0) -- flying forward, nearly horizontal
local DROPKICK_ROT = CFrame.Angles(1.15, 0, 0) -- leaning far back, feet first

------------------------------------------------------------------------
-- construction
------------------------------------------------------------------------

function Controller.new(character: Model)
	local self = setmetatable({}, Controller)
	self.character = character
	self.alive = true
	self.ready = false
	self.connections = {}
	self.state = "Standing"
	self.stance = "Stand" -- "Stand" | "Crouch"
	self.stateTime = 0
	self.time = 0
	self.phase = 0
	self.amp = 0
	self.gaitDir = Vector3.new(0, 0, -1)
	self.airTime = 0
	self.groundTime = 0
	self.jumpLock = 0
	self.lastJump = -10
	self.ragdollTimer = 0
	self.getUp = 1
	self.getUpTarget = "Stand"
	self.stumbleCalm = 0
	self.fallDir = Vector3.zero
	self.tilt = 0
	self.suppressImpacts = os.clock() + 1.2
	self.armSuppress = { Left = 0, Right = 0 }
	self.dropCooldown = 0
	self.lastStepSign = 1
	self.hands = {
		Left = { armed = false, grip = nil },
		Right = { armed = false, grip = nil },
	}
	self.handTarget = { Left = nil, Right = nil } -- world point a manually controlled hand points at
	self.bodyMass = 10
	self.carryMass = 0
	self.grounded = false
	self.ground = nil
	self.dead = false
	self.reportedKnocked = nil
	self.struggleHold = 0
	self.climbIntent = false
	self.mantleT0 = nil :: number? -- (v2.8) when the climb over a top edge began
	self.slowK = 1 -- (v2.8) the Sandevistan of somebody else: the speed this body lives at (1 = normal)
	self.slowYaw = nil :: number? -- (v2.8) where the body faces while it turns slowly
	self.scale = 1 -- (v2.8) BULK FRAME / COLOSSUS: the body is this much bigger (attribute BodyScale)
	self.embedCheckUntil = os.clock() + 4 -- (v2.8.1) a big body is lifted out of the ground after its spawn
	self.faceYaw = nil :: number? -- (v2.8) SENTRY REFLEX: the body turns to a shooter on its own until faceYawUntil
	self.faceYawUntil = 0
	self.frozenParts = nil :: { BasePart }? -- (v2.8) ZERO HOUR: held still (anchored on this machine)
	self.posed = nil :: any -- (v2.8) lying on a bed / sitting in the replay chair (PoseCF)
	self.cyberFire = nil :: (() -> boolean)? -- (v2.8) F with the SHIFTGUN open: CyberClient fires it (no punch)
	self.lastRegrip = 0
	self.legCollide = nil
	self.car = nil -- the car we drive (set by VehicleClient)
	self.attacks = {}
	self.pins = {}
	self.blockedTime = 0
	self.nextStepAssist = 0
	task.spawn(function()
		self:_init()
	end)
	return self
end

function Controller:_connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(self.connections, c)
	return c
end

function Controller:_init()
	local char = self.character
	local t0 = os.clock()
	while self.alive and not (char:GetAttribute("RagdollRig") and char:FindFirstChild("Rig") and char:IsDescendantOf(workspace)) do
		if os.clock() - t0 > 30 then
			warn("[Ragdoll] rig never arrived")
			return
		end
		task.wait()
	end
	if not self.alive then
		return
	end

	local rig = char:WaitForChild("Rig")
	self.rig = rig
	self.humanoid = char:WaitForChild("Humanoid") :: Humanoid
	self.torso = char:WaitForChild("Torso") :: BasePart
	self.head = char:WaitForChild("Head") :: BasePart
	self.balance = rig:WaitForChild("Balance") :: AlignOrientation
	self.drive = rig:WaitForChild("Drive") :: VectorForce

	self.limbs = {}
	for _, def in RigInfo.Limbs do
		local part = char:WaitForChild(def.partName, 10) :: BasePart
		local muscle = rig:WaitForChild("Muscle_" .. def.key, 10) :: AlignOrientation
		if part and muscle then
			self.limbs[def.key] = {
				def = def,
				part = part,
				collider = part:FindFirstChild("Collider"),
				muscle = muscle,
				target = muscle.Attachment1,
				broken = false,
				severed = false,
				hist = {},
				cooldown = 0,
			}
		end
	end
	self.torsoTrack = { hist = {}, cooldown = 0 }
	self.velCache = ContactSolver.NewVelocityCache()

	local hum = self.humanoid
	hum.PlatformStand = true
	hum.AutoRotate = false
	pcall(function()
		for _, st in {
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.GettingUp,
			Enum.HumanoidStateType.Climbing,
			Enum.HumanoidStateType.Swimming,
			Enum.HumanoidStateType.Seated,
			Enum.HumanoidStateType.Jumping,
			Enum.HumanoidStateType.Freefall,
			Enum.HumanoidStateType.Landed,
			Enum.HumanoidStateType.Running,
			Enum.HumanoidStateType.RunningNoPhysics,
			Enum.HumanoidStateType.StrafingNoPhysics,
			Enum.HumanoidStateType.Flying,
		} do
			hum:SetStateEnabled(st, false)
		end
		hum:ChangeState(Enum.HumanoidStateType.Physics)
	end)

	self.rayParams = RaycastParams.new()
	self.rayParams.FilterType = Enum.RaycastFilterType.Exclude
	self.rayParams.RespectCanCollide = true
	self.rayParams.IgnoreWater = true
	self.grabParams = RaycastParams.new()
	self.grabParams.FilterType = Enum.RaycastFilterType.Exclude
	self.grabParams.RespectCanCollide = false
	self.overlapParams = OverlapParams.new()
	self.overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	self.overlapParams.RespectCanCollide = false
	self.aimParams = RaycastParams.new() -- gun aim: may target your own body
	self.aimParams.FilterType = Enum.RaycastFilterType.Exclude
	self:_rebuildFilters()

	self.wind = SoundLibrary.Loop("wind", self.torso)

	local look = self.torso.CFrame.LookVector
	Cam.SnapYaw(MathUtil.Yaw(Vector3.new(look.X, 0, look.Z)))
	Cam.SetSubject(function()
		if self.torso and self.torso.Parent then
			return self.torso.Position + Vector3.new(0, 1.2, 0)
		end
		return nil
	end, function()
		local list = self:_heldInstances()
		if self.car then
			table.insert(list, self.car)
		end
		return list
	end, function()
		return self.head
	end)

	self:_connect(Input.Action, function(action)
		self:_onAction(action)
	end)
	self:_connect(RunService.PreSimulation, function(dt)
		self:_step(dt)
	end)
	self:_connect(hum.Died, function()
		self:_die()
	end)

	self.balance.Enabled = true
	self.ready = true
end

function Controller:Destroy()
	self.alive = false
	for _, c in self.connections do
		c:Disconnect()
	end
	table.clear(self.connections)
	for _, side in SIDES do
		self:_release(side, false)
	end
	if self.wind then
		self.wind:Destroy()
	end
	Input.firstPerson = false
	self:_clearAim()
	self:Wake()
end

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------

function Controller:_play(name: string, volume: number?, where: any?)
	SoundLibrary.Play(name, where or self.torso, volume)
end

function Controller:_limbUsable(key: string): boolean
	local L = self.limbs[key]
	return L ~= nil and not L.broken and not L.severed and L.muscle.Parent ~= nil
end

function Controller:_workingLegs(): number
	local n = 0
	for _, k in { "LeftLeg", "RightLeg" } do
		if self:_limbUsable(k) then
			n += 1
		end
	end
	return n
end

function Controller:_severedLegs(): number
	local n = 0
	for _, k in { "LeftLeg", "RightLeg" } do
		local L = self.limbs[k]
		if not L or L.severed then
			n += 1
		end
	end
	return n
end

function Controller:_workingArms(): number
	local n = 0
	for _, k in { "LeftArm", "RightArm" } do
		if self:_limbUsable(k) then
			n += 1
		end
	end
	return n
end

-- can this body stand at all?
function Controller:_canStand(): boolean
	return self:_workingLegs() >= 1 and self:_severedLegs() == 0
end

function Controller:_setState(s: string)
	if self.state == s then
		return
	end
	local prev = self.state
	self.state = s
	self.stateTime = 0
	if s == "GettingUp" then
		self.getUp = 0
		self:_play("getup")
	elseif s == "Ragdoll" then
		for _, side in SIDES do
			self:_release(side, false)
			self.hands[side].armed = false
		end
	elseif s == "Tumble" then
		local axis = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
		if axis.Magnitude > 0.01 then
			pcall(function()
				self.torso:ApplyAngularImpulse(axis.Unit * self.torso.AssemblyMass * 3)
			end)
		end
	elseif s == "Stumbling" then
		self.stumbleCalm = 0
	end
	if prev == "Tumble" and self.wind then
		self.wind:Stop()
	end
end

function Controller:Ragdoll(duration: number)
	if self.dead or self.car or self.flying then
		return -- (flying: nothing knocks you out of the air)
	end
	self.ragdollTimer = math.max(self.ragdollTimer, math.clamp(duration, Config.RagdollMinTime * 0.5, Config.RagdollMaxTime))
	self:_setState("Ragdoll")
end

-- a server-forwarded hit (bullets, punches, stabs, explosions)
--   impulse goes into the body part that was hit (at the hit point: a head shot snaps the head
--   back); `all` is a velocity change for the whole body (explosions)
function Controller:Knock(region: string?, impulse: Vector3?, ragdollTime: number?, point: Vector3?, all: Vector3?)
	local tk = self.slowK or 1 -- (v2.8) hit in the Sandevistan's slow motion: the push is slow too
	if typeof(all) == "Vector3" then
		all *= tk
	end
	if typeof(impulse) == "Vector3" then
		impulse *= tk
	end
	if typeof(all) == "Vector3" and not self.car then
		pcall(function()
			self.torso:ApplyImpulse(all * self.torso.AssemblyMass)
			for _, L in self.limbs do
				if not L.severed then
					L.part:ApplyImpulse(all * L.part.AssemblyMass)
				end
			end
		end)
	end
	if impulse and typeof(impulse) == "Vector3" then
		local part: BasePart = self.torso
		if region == "Head" and self.head and self.head.Parent then
			part = self.head
		elseif region and self.limbs[region] and not self.limbs[region].severed then
			part = self.limbs[region].part
		end
		pcall(function()
			if typeof(point) == "Vector3" and (point - part.Position).Magnitude < 4 then
				part:ApplyImpulseAtPosition(impulse, point)
			else
				part:ApplyImpulse(impulse)
			end
		end)
	end
	if ragdollTime and not self.dead then
		self:Ragdoll(ragdollTime)
	end
end

-- (v2.8.1) THE MUSCLE-UP. Where you can climb over: the top of the wall at `edge` (a hold, or a point on the wall face at
-- shoulder height), seen from the side you are on (`wallDir` points into the wall). Nil when the wall goes on up, the top
-- is no floor, or there is no room to stand up there.
function Controller:_mantleTop(edge: Vector3, wallDir: Vector3): Vector3?
	local S = self.scale
	local upv = Vector3.new(0, 1, 0)
	-- the wall must end below this: nothing in front of you a little above the edge
	local over = workspace:Raycast(edge - wallDir * 0.6 * S + upv * 2.3 * S, wallDir * 1.8 * S, self.rayParams)
	if over then
		return nil
	end
	local hit = workspace:Raycast(edge + wallDir * 1.0 * S + upv * 2.2 * S, Vector3.new(0, -3.8 * S, 0), self.rayParams)
	if not hit or hit.Normal.Y < 0.7 then
		return nil
	end
	local top = hit.Position
	local roomH = (Config.TorsoHalfHeight * 2 + Config.LegLength + 1.4) * S
	if workspace:Raycast(top + upv * 0.15, upv * roomH, self.rayParams) then
		return nil
	end
	return top
end

function Controller:_startMantle(top: Vector3, wallDir: Vector3)
	if self.mantle then
		return
	end
	for _, side in SIDES do
		local g = self.hands[side].grip
		if g and g.static then
			self:_release(side, false)
		end
	end
	self.mantle = { t0 = os.clock(), top = top, dir = MathUtil.SafeUnit(MathUtil.Flat(wallDir), self.torso.CFrame.LookVector) }
	self.mantleT0 = nil
	self.suppressImpacts = math.max(self.suppressImpacts, os.clock() + 1.5)
	self:_play("jump", 0.4)
	if self.state ~= "Standing" and self.state ~= "Airborne" then
		self:_setState("Airborne")
	end
end

-- one frame of the muscle-up: up along the wall until the feet are over the edge, then forward onto the top.
-- Returns false when it is over.
function Controller:_mantleStep(dt: number): boolean
	local m = self.mantle
	if not m then
		return false
	end
	local S = self.scale
	local tk = self.slowK or 1
	local pos = self.torso.Position
	local legs = (Config.TorsoHalfHeight + Config.LegLength) * S
	local wantY = m.top.Y + legs + 0.35 * S
	local feetY = pos.Y - legs
	local goal = m.top + m.dir * 1.1 * S
	local flatTo = MathUtil.Flat(goal - pos)
	local v
	if feetY < m.top.Y + 0.3 * S and not m.forward then
		v = Vector3.new(0, 16 * math.sqrt(S) * tk, 0) + m.dir * 1.2 * tk
	else
		m.forward = true
		v = MathUtil.SafeUnit(flatTo, m.dir) * 13 * math.sqrt(S) * tk + Vector3.new(0, math.clamp((wantY - pos.Y) * 8, -6, 12) * tk, 0)
	end
	local done = m.forward and flatTo.Magnitude < 0.7 * S
	local late = os.clock() - m.t0 > 1.4
	if late and not done then
		-- (stuck on something: put the body up there if it fits)
		self.character:PivotTo(CFrame.new(goal + Vector3.new(0, legs + 0.2 * S, 0)) * self.torso.CFrame.Rotation)
		done = true
	end
	if done then
		self.mantle = nil
		for _, d in self.character:GetChildren() do
			if d:IsA("BasePart") and not d.Anchored then
				d.AssemblyLinearVelocity = m.dir * 4 * tk
			end
		end
		return false
	end
	for _, d in self.character:GetChildren() do
		if d:IsA("BasePart") and not d.Anchored then
			d.AssemblyLinearVelocity = v
			d.AssemblyAngularVelocity *= 0.5
		end
	end
	-- the arms reach for the edge while you go over it
	return true
end

-- (v2.8.1) jumping at a wall you can get over (Space held, walking into it): the hands catch the top and you go over
function Controller:_tryVault(moveWorld: Vector3)
	if self.mantle or moveWorld.Magnitude < 0.3 or not Input.jumpHeld or self.car or self.flying then
		return
	end
	if os.clock() < (self.nextVaultCheck or 0) then
		return
	end
	self.nextVaultCheck = os.clock() + 0.08
	local S = self.scale
	local dir = moveWorld.Unit
	local chest = self.torso.Position + Vector3.new(0, 0.6 * S, 0)
	local wall = workspace:Raycast(chest, dir * 1.9 * S, self.rayParams)
	if not wall or math.abs(wall.Normal.Y) > 0.35 then
		return
	end
	local into = MathUtil.SafeUnit(MathUtil.Flat(-wall.Normal), dir)
	local edge = Vector3.new(wall.Position.X, self.torso.Position.Y + 1.4 * S, wall.Position.Z)
	local top = self:_mantleTop(edge, into)
	if not top then
		return
	end
	local feetY = self.torso.Position.Y - (Config.TorsoHalfHeight + Config.LegLength) * S
	if top.Y - feetY < 1.4 * S then
		return -- (a step: the legs take it)
	end
	for key, L in self.limbs do
		if (L.severed or L.broken) and (key == "LeftArm" or key == "RightArm") then
			return -- (a muscle-up needs both arms)
		end
	end
	self:_startMantle(top, into)
end

-- X in the air: leap forward, then land on the belly
function Controller:_dive()
	local look = CFrame.Angles(0, Cam.yaw, 0).LookVector
	local tk = self.slowK or 1 -- (v2.8.1) in somebody's Sandevistan the leap is slow too (it flew far away before)
	local function launch(part: BasePart)
		local cur = part.AssemblyLinearVelocity
		local target = Vector3.new(look.X * Config.DiveSpeed * tk, math.max(cur.Y, 0) + 7 * tk, look.Z * Config.DiveSpeed * tk)
		part:ApplyImpulse((target - cur) * part.AssemblyMass)
	end
	pcall(function()
		launch(self.torso)
		for _, L in self.limbs do
			if not L.severed then
				launch(L.part)
			end
		end
	end)
	self.suppressImpacts = math.max(self.suppressImpacts, os.clock() + 0.25)
	self:_play("jump", 0.5)
	self:_setState("Diving")
end

------------------------------------------------------------------------
-- input actions
------------------------------------------------------------------------

-- sleep dart: knocked out (no moving, no hands, black screen, silence - see HUD)
function Controller:Sleep(duration: number)
	if self.dead then
		return
	end
	self.sleepUntil = os.clock() + duration
	for _, side in SIDES do
		self:_release(side, false)
		self.hands[side].armed = false
	end
	self:Ragdoll(duration)
	if self.onSleep then
		self.onSleep(duration)
	end
end

function Controller:Wake()
	if (self.sleepUntil or 0) > os.clock() then
		self.sleepUntil = 0
		if self.onWake then
			self.onWake()
		end
	end
end

function Controller:IsAsleep(): boolean
	return (self.sleepUntil or 0) > os.clock()
end

local PASSENGER_ACTIONS = { Fire = true, TwoHand = true, GrabLeft = true, GrabRight = true }

function Controller:_onAction(action: string)
	if not self.ready or self.dead or self.car or self:IsAsleep() then
		return
	end
	if Input.promptOpen or Input.cutscene then
		return -- (v2.0: a key while the piano / a text box is open did things with the body too)
	end
	if self.passenger and not PASSENGER_ACTIONS[action] then
		return -- sitting next to the driver: shoot, nothing else
	end
	local s = self.state
	if action == "GrabLeft" then
		self:_toggleHand("Left")
	elseif action == "GrabRight" then
		self:_toggleHand("Right")
	elseif action == "StowLeft" then
		self:_pocketToggle("Left")
	elseif action == "StowRight" then
		self:_pocketToggle("Right")
	elseif action == "Fire" then
		if self.cyberFire and self.cyberFire() then
			return -- (v2.8) the arm gun took it
		end
		if self:_fistsReady() then
			self:_punch() -- (v2.0) empty hands: fists
		else
			self:_use()
		end
	elseif action == "Weave" then
		self:_weave()
	elseif action == "Kick" then
		self:_kick()
	elseif action == "SuperPunch" then
		self:_superPunch()
	elseif action == "TwoHand" then
		self:_toggleTwoHand()
	elseif string.sub(action, 1, 4) == "Lift" then
		local n = tonumber(string.sub(action, 5))
		if n and not self.flying then -- (flying: the digits type a speed)
			self:LiftTo(n)
		end
	elseif action == "Ragdoll" then
		if self.flying then
			self:SetFlying(false)
		end
		if s ~= "Ragdoll" and s ~= "Downed" then
			self:Ragdoll(Config.ManualRagdollTime)
		end
	elseif action == "Jump" then
		local _, G = self:_hasStaticGrip()
		if G and G.Y > self.torso.Position.Y - 0.4 then
			return -- holding a ledge: Space climbs instead of jumping
		end
		if s == "Prone" then
			self:_standUp("Stand")
		elseif self.stance == "Crouch" and (s == "Standing" or s == "Stumbling") then
			self.stance = "Stand"
			self:_tryJump()
		else
			self:_tryJump()
		end
	elseif action == "Crouch" then
		if self.slide then
			self:_endSlide() -- Ctrl again: out of the slide
		elseif s == "Standing" and self:_startSlide() then
			return -- (sprinting + Ctrl = slide)
		elseif s == "Standing" or s == "Stumbling" then
			self.stance = self.stance == "Crouch" and "Stand" or "Crouch"
		elseif s == "Prone" then
			self:_standUp("Crouch")
		end
	elseif action == "Prone" then
		if s == "Airborne" and self.airTime > 0.05 then
			self:_dive()
		elseif s == "Standing" or s == "Stumbling" then
			self:_setState("Prone")
		elseif s == "Prone" then
			self:_standUp(self.stance)
		end
	end
end

function Controller:_standUp(stance: string)
	if not self:_canStand() then
		return
	end
	self.stance = stance
	self:_setState("GettingUp")
end

function Controller:_tryJump()
	local s = self.state
	if s ~= "Standing" and s ~= "Stumbling" then
		return
	end
	local now = os.clock()
	if now - self.lastJump < Config.JumpCooldown then
		return
	end
	if not self.grounded and self.airTime > Config.CoyoteTime then
		return
	end
	local legs = self:_workingLegs()
	if legs == 0 then
		return
	end
	self.lastJump = now
	local jv = Config.JumpVelocity * (legs == 1 and 0.55 or 1)
	-- (v2.0) a zombie running at somebody: the jump is a long, low leap - and whoever it lands on is bitten
	local leap = Vector3.zero
	if self.character:GetAttribute("Zombie") and legs == 2 then
		local mv = Input.GetMoveVector()
		if mv.Magnitude > 0.3 then
			local heading = CFrame.Angles(0, Cam.yaw, 0)
			leap = heading:VectorToWorldSpace(Vector3.new(mv.X, 0, mv.Z)).Unit * Config.ZombieLeapForward
			jv *= Config.ZombieLeapUp
			self.zombieLeapUntil = now + Config.ZombieLeapTime
			self.zombieLeapHit = {}
			SoundLibrary.Play("zombieLeap", self.torso, 1)
		end
	end
	local tk = self.slowK or 1 -- (v2.8) slow motion: the same jump, slower
	jv *= tk
	local cj = self.character:GetAttribute("CyJump") -- (v2.8) STRIDER LEGS
	if typeof(cj) == "number" then
		jv *= math.clamp(cj, 0.5, 2.5)
		self.striderAir = true -- (v2.8.1) the landing of your own STRIDER jump never hurts
		self.striderLandAt = nil
	end
	jv *= math.sqrt(self.scale)
	leap *= tk
	local function kick(part: BasePart)
		local vy = part.AssemblyLinearVelocity.Y
		part:ApplyImpulse((Vector3.new(0, jv - math.min(vy, 0), 0) + leap) * part.AssemblyMass)
	end
	pcall(function()
		kick(self.torso)
		for _, L in self.limbs do
			if not L.severed then
				kick(L.part)
			end
		end
	end)
	self.jumpLock = Config.JumpHoverLock
	self.suppressImpacts = math.max(self.suppressImpacts, now + 0.15)
	self.airTime = Config.CoyoteTime + 0.01
	self:_play("jump")
	self:_setState("Airborne")
end

------------------------------------------------------------------------
-- sensing the ground
------------------------------------------------------------------------

function Controller:_standHeight(): number
	local slideH = self:_slideHeight() -- (v2.0) low and leaned back while sliding
	if slideH then
		return slideH
	end
	if self.state == "Prone" or self.state == "Downed" then
		return Config.ProneHeight * self.scale
	end
	local legAngle = math.rad(self.amp) * math.abs(math.sin(self.phase))
	local vertical
	if self.stance == "Crouch" then
		local a = math.rad(Config.CrouchLegAngle) + legAngle * 0.5
		vertical = math.cos(a) * math.cos(math.rad(Config.CrouchLegSplay))
	else
		vertical = math.cos(legAngle * Config.WalkBob)
	end
	local h = Config.TorsoHalfHeight + Config.LegLength * vertical + Config.FootClearance
	if self:_workingLegs() == 1 then
		h -= 0.3
	end
	return h * self.scale
end

-- (v2.8.2) a body (a player, an NPC, a corpse) is never ground to stand on: you slide off it
local function isBody(self, inst: Instance): Vector3?
	local m = inst:FindFirstAncestorWhichIsA("Model")
	if m and m ~= self.character and m:FindFirstChildOfClass("Humanoid") then
		local t = m:FindFirstChild("Torso")
		return (t and t:IsA("BasePart")) and t.Position or (inst :: BasePart).Position
	end
	return nil
end

function Controller:_probeGround(moveWorld: Vector3, heading: CFrame, speed: number)
	local origin = self.torso.Position
	local S = self.scale
	local probeLen = (Config.TorsoHalfHeight + Config.LegLength + Config.FootClearance + Config.ProbeExtra) * S
	local down = Vector3.new(0, -probeLen, 0)
	local best: RaycastResult? = nil
	self.bodyUnder = nil
	for _, off in { Vector3.zero, Vector3.new(0.45, 0, 0), Vector3.new(-0.45, 0, 0), Vector3.new(0, 0, 0.35), Vector3.new(0, 0, -0.35) } do
		local r = workspace:Raycast(origin + heading:VectorToWorldSpace(off * S), down, self.rayParams)
		if r and r.Normal.Y >= COS_SLOPE then
			local under = isBody(self, r.Instance)
			if under then
				self.bodyUnder = under
			elseif not best or r.Position.Y > best.Position.Y then
				best = r
			end
		end
	end
	-- look ahead in the walking direction so the body rises onto steps before the legs get there
	if best and moveWorld.Magnitude > 0.1 and UPRIGHT_STATES[self.state] then
		local ahead = Config.StepLookAhead + speed * Config.StepLookAheadPerSpeed
		for _, k in { 0.5, 1 } do
			local r = workspace:Raycast(origin + moveWorld.Unit * ahead * k, down, self.rayParams)
			if r and r.Normal.Y >= COS_SLOPE and r.Position.Y > best.Position.Y and r.Position.Y - best.Position.Y <= Config.StepUpMax * S
				and not isBody(self, r.Instance) then
				best = r
			end
		end
	end
	if not best then
		return nil
	end
	local part = best.Instance
	local vel = Vector3.zero
	if part:IsA("BasePart") and not part.Anchored then
		vel = part.AssemblyLinearVelocity
	end
	-- slope of the ground in the walking direction (stairs count as a ramp): the hips follow it
	-- with the right vertical speed instead of lagging behind and catching the step edges
	local slope = 0
	if moveWorld.Magnitude > 0.1 and UPRIGHT_STATES[self.state] then
		local here = workspace:Raycast(origin, down, self.rayParams)
		local ahead = workspace:Raycast(origin + moveWorld.Unit * 1.6, down, self.rayParams)
		if here and ahead and ahead.Normal.Y >= COS_SLOPE then
			slope = math.clamp((ahead.Position.Y - here.Position.Y) / 1.6, -1, 1.3)
		end
	end
	return {
		part = part,
		y = best.Position.Y,
		height = origin.Y - best.Position.Y,
		normal = best.Normal,
		velocity = vel,
		slope = slope,
	}
end

------------------------------------------------------------------------
-- condition (broken / severed / dead / dragged), read from server attributes
------------------------------------------------------------------------

function Controller:_readCondition()
	local char = self.character
	for key, L in self.limbs do
		local severed = char:GetAttribute("Severed_" .. key) == true or not L.muscle.Parent
		local broken = char:GetAttribute("Broken_" .. key) == true
		if severed and not L.severed then
			L.severed = true
			if key == "LeftArm" then
				self:_release("Left", false)
			elseif key == "RightArm" then
				self:_release("Right", false)
			end
		end
		L.broken = broken or severed
	end
	local m = self.torso.AssemblyMass
	for _, L in self.limbs do
		if not L.severed then
			m += L.part.AssemblyMass
		end
	end
	self.bodyMass = m
	local carry = 0
	local counted = {}
	for _, side in SIDES do
		local g = self.hands[side].grip
		if g and not g.static and not g.strong and not g.remoteBody and g.part.Parent then
			local root = g.part.AssemblyRootPart or g.part
			if not counted[root] then
				counted[root] = true
				carry += g.part.AssemblyMass
			end
		end
	end
	self.carryMass = carry

	if (char:GetAttribute("Dead") or self.humanoid.Health <= 0) and not self.dead then
		self:_die()
	end
	-- someone is dragging us: stay down (only the stabbed body part sticks to a spike, see Sensor)
	if self:IsAsleep() and not self.dead then
		if self.state ~= "Ragdoll" then
			self:Ragdoll(1)
		end
		self.ragdollTimer = math.max(self.ragdollTimer, 0.6)
	elseif self.wasAsleep and not self.dead then
		if self.onWake then
			self.onWake()
		end
	end
	self.wasAsleep = self:IsAsleep()
	-- sitting in a car (driver or passenger) or dragged: bumps are not impacts. Getting in / out
	-- moves the body in one jump (and a passenger's body is moved by the driver's machine).
	local seated = self.car ~= nil or self.passenger == true or char:GetAttribute("InCar") == true or char:GetAttribute("Passenger") == true
	if seated or char:GetAttribute("DraggedBy") then
		self.suppressImpacts = math.max(self.suppressImpacts, os.clock() + 0.6)
	elseif self.wasSeated then
		self.suppressImpacts = math.max(self.suppressImpacts, os.clock() + 1.5)
	end
	self.wasSeated = seated
	if Config.DragKnockdown and not self.dead and not self.car and char:GetAttribute("DraggedBy") then
		if self.state ~= "Ragdoll" then
			self:Ragdoll(1)
		end
		self.ragdollTimer = math.max(self.ragdollTimer, 0.6)
	end
end

function Controller:_die()
	if self.dead then
		return
	end
	self.dead = true
	for _, side in SIDES do
		self:_release(side, false)
		self.hands[side].armed = false
	end
	self:_dropTwoHand(true)
	if self.flying then
		self.flying = false
	end
	self.state = "Dead"
	self.balance.Enabled = false
	self.drive.Force = Vector3.zero
	for _, L in self.limbs do
		if L.muscle.Parent then
			L.muscle.Enabled = false
		end
	end
	if self.wind then
		self.wind:Stop()
	end
	Input.firstPerson = false
	self.kick = nil
	self:_clearAim()
	self:Wake()
	if self.liftPad then
		self.liftPad = nil
		if self.onLiftPad then
			self.onLiftPad(nil)
		end
	end
	self:_setLegCollision(true)
end

-- legs only collide with the world while you are not actively walking on them
function Controller:_setLegCollision(on: boolean)
	if self.legCollide == on then
		return
	end
	self.legCollide = on
	for _, k in { "LeftLeg", "RightLeg" } do
		local L = self.limbs[k]
		if L and L.collider and L.collider.Parent then
			L.collider.CanCollide = on
		end
	end
end

------------------------------------------------------------------------
-- state machine
------------------------------------------------------------------------

function Controller:_updateState(dt: number, ground, moveWorld: Vector3)
	local s = self.state
	self.stateTime += dt
	local vel = self.torso.AssemblyLinearVelocity
	local hasStatic = self:_hasStaticGrip()
	local standH = self:_standHeight()
	local nearGround = ground ~= nil and ground.height <= math.max(standH, 1.2) + 0.45
	local canStand = self:_canStand()

	if self.car then
		if s ~= "Driving" then
			self:_setState("Driving")
		end
		return
	elseif s == "Driving" then
		self:_setState("Airborne")
		return
	end
	if self.passenger then
		if s ~= "Passenger" then
			self:_setState("Passenger")
		end
		return
	elseif s == "Passenger" then
		self:_setState("Airborne")
		return
	end
	if self.flying then
		if s ~= "Flying" then
			self:_setState("Flying")
		end
		return
	elseif s == "Flying" then
		self:_setState("Airborne")
		return
	end
	if self.swimming then
		-- knocked over in the water: limp until it wears off, then swim
		if s == "Ragdoll" and self.ragdollTimer > 0 then
			self.ragdollTimer -= dt
			return
		end
		if s ~= "Swimming" then
			self:_setState("Swimming")
		end
		return
	elseif s == "Swimming" then
		self:_setState(self.grounded and "Standing" or "Airborne")
		return
	end

	if s == "DropKick" then
		if hasStatic then
			self:_setState("Hanging")
		elseif ground and ground.height < 2.2 and self.stateTime > 0.2 then
			-- landed: on the back for a moment
			self:Ragdoll(Config.DropKickLandRagdoll)
		elseif self.stateTime > Config.DropKickTime then
			self:_setState("Tumble")
		end
		return
	end

	if s == "Diving" then
		if hasStatic then
			self:_setState("Hanging")
		elseif ground and ground.height < 1.7 and self.stateTime > 0.15 then
			-- landed on the belly: slide out the leap, then lie there
			self.diveSlide = os.clock() + 0.6
			self:_setState(canStand and "Prone" or "Downed")
		elseif self.stateTime > 1.6 then
			self:_setState("Tumble")
		end
		return
	end

	if not canStand and (s == "Standing" or s == "Stumbling" or s == "GettingUp" or s == "Prone") then
		self:_setState("Downed")
		s = "Downed"
	end

	if s == "Standing" or s == "Stumbling" then
		-- holding something solid above the waist and pulling up: start climbing right away
		local _, G = self:_hasStaticGrip()
		if self.climbIntent and G and G.Y > self.torso.Position.Y - 0.4 then
			self:_setState("Hanging")
			return
		end
		if not self.grounded and self.airTime > Config.CoyoteTime then
			self:_setState(hasStatic and "Hanging" or "Airborne")
			return
		end
		if self.slide then
			-- (v2.0 fix) leaning back is the slide itself: it used to count as falling over, so every slide ended
			-- in a ragdoll (and a thump) after a moment. Only a real tumble ends it now.
			if self.tilt > Config.SlideLean + 38 then
				self:_endSlide()
				self:Ragdoll(1.2)
			elseif s == "Stumbling" then
				self:_setState("Standing")
			end
			return
		end
		if self.tilt > Config.FallTilt then
			self:Ragdoll(1.5)
			return
		end
		if s == "Standing" then
			if self.tilt > Config.StumbleTilt then
				self:_setState("Stumbling")
			elseif self:_workingLegs() == 1 and Vector3.new(vel.X, 0, vel.Z).Magnitude > 3 and math.random() < dt * 0.25 then
				self:_setState("Stumbling")
			end
		else
			if self.tilt < Config.StumbleRecoverTilt then
				self.stumbleCalm += dt
			else
				self.stumbleCalm = 0
			end
			if self.stumbleCalm > 0.25 and self.stateTime > 0.35 then
				self:_setState("Standing")
			elseif self.stateTime > Config.StumbleMaxTime then
				self:Ragdoll(1.3)
			end
		end
	elseif s == "Airborne" then
		if hasStatic then
			self:_setState("Hanging")
		elseif self.grounded and self.jumpLock <= 0 then
			-- (v2.8.2) your own STRIDER jump (and any fall with BEDROCK STABILIZER tier 3) lands on its feet
			local st3 = self.character:GetAttribute("CyStance")
			local feet = self.striderAir or (typeof(st3) == "number" and st3 >= 3)
			self:_setState((vel.Y < -48 and not feet) and "Stumbling" or "Standing")
		elseif not self.striderAir and not (typeof(self.character:GetAttribute("CyStance")) == "number" and (self.character:GetAttribute("CyStance") :: number) >= 3)
			and self.airTime > Config.TumbleMinAirTime and vel.Y < -Config.TumbleFallSpeed then
			self:_setState("Tumble")
		end
	elseif s == "Hanging" then
		if not hasStatic then
			self:_setState(self.grounded and "Standing" or "Airborne")
		elseif self.grounded and self.stateTime > 0.3 and not self.climbIntent then
			self:_setState("Standing")
		end
	elseif s == "Tumble" then
		if hasStatic then
			self:_setState("Hanging")
		elseif nearGround then
			self:Ragdoll(0.9 + vel.Magnitude / 70)
		end
	elseif s == "Ragdoll" then
		self.ragdollTimer -= dt
		local still = vel.Magnitude < 7
		if self.ragdollTimer <= 0 and (still and nearGround or self.ragdollTimer < -4) then
			if not canStand then
				self:_setState("Downed")
			else
				self:_setState("GettingUp")
			end
		end
	elseif s == "GettingUp" then
		self.getUp = math.min(1, self.getUp + dt / Config.GetUpTime)
		if self.getUp >= 1 and self.tilt < 25 and nearGround then
			self:_setState("Standing")
		elseif self.stateTime > Config.GetUpTime * 2.2 then
			if nearGround then
				self:Ragdoll(0.6)
			else
				self:_setState("Airborne")
			end
		end
	elseif s == "Prone" or s == "Downed" then
		if s == "Downed" and canStand then
			self:_setState("GettingUp")
		elseif not ground or ground.height > 3.5 then
			-- crawled off an edge
			if self.airTime > 0.35 then
				self:_setState(s == "Downed" and "Tumble" or "Airborne")
			end
		end
	end
end

------------------------------------------------------------------------
-- forces on the torso
------------------------------------------------------------------------

function Controller:_reachLean(heading: CFrame): (number, number, number)
	-- average direction the active hands are reaching to
	local sum, n = Vector3.zero, 0
	for _, side in SIDES do
		local aim = self.lastAim and self.lastAim[side]
		if aim then
			sum += aim
			n += 1
		end
	end
	if n == 0 then
		return 0, 0, 0
	end
	local d = heading:VectorToObjectSpace((sum / n).Unit)
	local pitch, yaw, roll = 0, 0, 0
	if d.Y < -0.15 then
		-- bending down to reach low
		pitch = -math.rad(Config.ReachLeanDown) * math.clamp((-d.Y - 0.15) / 0.7, 0, 1) * math.clamp(-d.Z + 0.6, 0.3, 1)
	elseif d.Y > 0.4 then
		pitch = math.rad(6) * math.clamp((d.Y - 0.4) / 0.5, 0, 1)
	end
	local side = math.atan2(-d.X, -d.Z) -- 0 straight ahead, + to the left
	yaw = math.clamp(side, -1.2, 1.2) / 1.2 * math.rad(Config.ReachTwist)
	roll = math.clamp(d.X, -1, 1) * math.rad(-5)
	return pitch, yaw, roll
end

function Controller:_applyForces(dt: number, ground, moveWorld: Vector3, heading: CFrame)
	local s = self.state
	local torso = self.torso
	local g = workspace.Gravity * (self.slowK or 1) ^ 2
	local M = self.bodyMass
	local W = M * g
	local vel = torso.AssemblyLinearVelocity
	local groundVel = ground and ground.velocity or Vector3.zero
	local vh = MathUtil.Flat(vel - groundVel)

	local legs = self:_workingLegs()
	local maxSpeed = Input.Running() and Config.RunSpeed or Config.WalkSpeed
	if self.stance == "Crouch" then
		maxSpeed = Config.CrouchSpeed
	end
	if legs == 1 then
		maxSpeed *= Config.LimpSpeedMultiplier
	end
	if self.carryMass > 0 then
		local k = math.clamp(self.carryMass / (M * Config.CarrySlowdownRatio), 0, 0.7)
		maxSpeed *= 1 - k
	end
	if self.aiming then
		maxSpeed *= Config.AimWalkMult
	end
	maxSpeed *= self:_prostheticSpeed() -- (v2.0)
	if self.character:GetAttribute("SandevistanOn") then
		maxSpeed *= Config.SandevistanSpeed -- (v2.1) the Sandevistan runs: you move at double speed while the world crawls
	end
	if self.character:GetAttribute("Zombie") then
		maxSpeed *= Config.ZombieSpeed -- (v2.0) zombies are a little faster
	end
	local tk = self.slowK or 1 -- (v2.8) somebody else's Sandevistan runs: you live in slow motion
	maxSpeed *= tk
	local cs = self.character:GetAttribute("CySpeed") -- (v2.8) STRIDER LEGS
	if typeof(cs) == "number" then
		maxSpeed *= math.clamp(cs, 0.5, 2)
	end
	-- (v2.9) CRIPPLE MOVEMENT (a netrunner quickhack): your leg servos are locked half-shut for a while
	local crawl = self.character:GetAttribute("ChipCrawl")
	if typeof(crawl) == "number" and workspace:GetServerTimeNow() < (self.character:GetAttribute("ChipCrawlUntil") or 0) then
		maxSpeed *= math.clamp(crawl, 0.1, 1)
	end
	maxSpeed *= math.sqrt(self.scale) -- (a bigger body takes longer strides)
	local desired = moveWorld * maxSpeed

	local force = Vector3.zero
	local balanceOn = true
	local balanceTorque = Config.BalanceTorque
	local balanceResp = Config.BalanceResponsiveness
	local balanceCF = nil

	if s == "Standing" or s == "Stumbling" or s == "GettingUp" then
		local support = 1
		balanceCF = self:_slideBalance() -- (v2.0) the slide: leaned back along the slide (nil otherwise)
		if s == "GettingUp" then
			support = 0.35 + 0.65 * self.getUp
			balanceTorque = Config.BalanceTorque * math.max(0.04, self.getUp ^ 1.5)
			balanceResp = 14
			desired *= 0.3 * self.getUp
		elseif s == "Stumbling" then
			balanceTorque *= 1.5
			desired += self.fallDir * 7
		end
		local fy = 0
		if ground and self.jumpLock <= 0 then
			local err = self:_standHeight() - ground.height
			local vy = vel.Y - groundVel.Y
			-- feed-forward: on stairs / ramps the hips rise at the speed the ground rises
			local vyWant = 0
			if ground.slope and moveWorld.Magnitude > 0.1 then
				vyWant = ground.slope * math.max(0, vh:Dot(moveWorld.Unit)) * Config.SlopeFeedForward
			end
			fy = M * (g + Config.SpringK * tk * tk * err - Config.SpringD * tk * (vy - vyWant))
			fy = math.clamp(fy, 0, W * Config.MaxSupportFactor) * support
		end
		local accCap = (self.grounded and Config.GroundAccel or Config.AirAccel) * tk * tk
		local carry = self.carryMass
		local extraPull = 0
		if carry > 0 and self.grounded then
			extraPull = math.min(carry, M * Config.MaxDragRatio) * g * Config.DragStrength
		end
		local fh = MathUtil.ClampMagnitude((desired - vh) * Config.VelocityGain * tk * (M + carry), M * accCap + extraPull)
		force = Vector3.new(fh.X, fy, fh.Z)
	elseif s == "Airborne" then
		local acc = MathUtil.ClampMagnitude((desired - vh) * Config.VelocityGain * tk, Config.AirAccel * tk * tk)
		force = Vector3.new(acc.X, 0, acc.Z) * M
		balanceTorque *= 0.6
	elseif s == "Hanging" then
		balanceTorque *= 0.35
		force = self:_climbForce(moveWorld, heading, desired, vh, M, W)
	elseif s == "Diving" then
		local acc = MathUtil.ClampMagnitude((desired * 0.3 - vh) * 1.5, Config.AirAccel * 0.4)
		force = Vector3.new(acc.X, 0, acc.Z) * M
		balanceTorque *= 0.7
		balanceCF = heading * DIVE_ROT
	elseif s == "Swimming" then
		force, balanceCF = self:_swimForces(dt, moveWorld, heading)
		balanceTorque *= 0.7
		balanceResp = 10
	elseif s == "Flying" then
		local fk
		force, balanceCF, fk = self:_flyForces(heading, dt)
		self.flySpeedK = fk
		balanceTorque *= 1.3
		balanceResp = 18
	elseif s == "DropKick" then
		balanceTorque *= 0.8
		local kk = self.kick
		local dir = kk and kk.dir or heading.LookVector
		balanceCF = CFrame.lookAt(Vector3.zero, dir) * DROPKICK_ROT
	elseif s == "Driving" or s == "Passenger" then
		balanceOn = false
	elseif s == "Tumble" then
		local acc = MathUtil.ClampMagnitude(desired * 0.5, Config.TumbleAirAccel)
		force = Vector3.new(acc.X, 0, acc.Z) * M
		balanceOn = false
	elseif s == "Prone" or s == "Downed" then
		-- lying on the belly: light support so the body glides, crawl with the arms
		local arms = self:_workingArms()
		local speed = s == "Prone" and Config.ProneSpeed or Config.CrawlSpeed * (0.25 + 0.375 * arms)
		if s == "Prone" and self:_workingLegs() < 2 then
			speed *= 0.6
		end
		speed *= tk
		local crawl = moveWorld * speed
		-- holding the floor: pull yourself towards that hand
		local pull = (moveWorld.Magnitude > 0.3 or Input.jumpHeld) and self:_floorPull(speed, moveWorld) or nil
		if pull then
			crawl = pull
		end
		local fy = 0
		if ground and ground.height < 2.5 then
			local err = Config.ProneHeight * self.scale - ground.height
			fy = math.clamp(M * (g * 0.8 + 120 * tk * tk * err - 12 * tk * vel.Y), 0, W * 1.1)
			local gain = (os.clock() < (self.diveSlide or 0) and 1.2 or 6) * tk
			local fh = MathUtil.ClampMagnitude((crawl - vh) * gain * M, M * 24 * tk * tk)
			force = Vector3.new(fh.X, fy, fh.Z)
		end
		balanceTorque = Config.BalanceTorque * (s == "Prone" and 0.45 or 0.3)
		if torso.CFrame.UpVector.Y > 0.6 then
			-- still sitting up (e.g. after the legs broke): get onto the belly first
			balanceTorque = Config.BalanceTorque * 0.9
		end
		balanceResp = 12
		balanceCF = heading * PRONE_ROT
	else -- Ragdoll / Dead
		balanceOn = false
	end

	self.drive.Enabled = true
	self.drive.Force = force

	if balanceOn then
		if not balanceCF then
			local localVel = heading:VectorToObjectSpace(vh)
			local fwd = math.clamp(-localVel.Z / Config.WalkSpeed, -1, 1.4)
			local sideways = math.clamp(localVel.X / Config.WalkSpeed, -1, 1)
			local ampK = math.clamp(self.amp / Config.StepAmplitude, 0, 1)
			local pitch = -math.rad(Config.LeanForward) * fwd
			local roll = -math.rad(4) * sideways + math.rad(Config.WaddleRoll) * math.sin(self.phase) * ampK
			local yaw = 0
			if self.stance == "Crouch" and s ~= "GettingUp" then
				pitch -= math.rad(16)
			end
			if s == "Hanging" or s == "Airborne" then
				pitch, roll = 0, 0
			end
			if s == "Standing" or s == "Stumbling" then
				local lp, ly, lr = self:_reachLean(heading)
				pitch += lp
				yaw += ly
				roll += lr
				local wp, wr = self:_weaveLean() -- (v2.0) slipping a punch
				pitch += wp
				roll += wr
			end
			balanceCF = heading * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll)
		end
		self.balance.CFrame = balanceCF
		local cb = self.character:GetAttribute("CyBalance") -- (v2.8) KEEL SPINE
		local S4 = self.scale ^ 4 -- (a bigger body needs much more torque: mass x lever)
		self.balance.MaxTorque = balanceTorque * tk * S4 * (typeof(cb) == "number" and math.clamp(cb, 1, 3) or 1)
		self.balance.Responsiveness = math.max(5, balanceResp * tk)
		self.balance.Enabled = true
	else
		self.balance.Enabled = false
	end
end

------------------------------------------------------------------------
-- procedural gait, foot IK, muscle targets
------------------------------------------------------------------------

function Controller:_updateGait(dt: number, ground, heading: CFrame)
	local s = self.state
	local vel = self.torso.AssemblyLinearVelocity
	local groundVel = ground and ground.velocity or Vector3.zero
	local vh = MathUtil.Flat(vel - groundVel)
	local speed = vh.Magnitude
	local walking = (s == "Standing" or s == "Stumbling" or s == "GettingUp") and ground ~= nil

	local target = 0
	if walking and speed > 0.7 then
		local maxAmp = self.stance == "Crouch" and 24 or Config.StepAmplitudeMax
		target = math.clamp(Config.StepAmplitude * speed / Config.WalkSpeed, 14, maxAmp)
	end
	if s == "Stumbling" then
		target = math.max(target, 30)
	end
	if LYING_STATES[s] and speed > 0.4 then
		target = 20 -- arm crawl cycle uses the same phase
	end
	self.amp = MathUtil.Approach(self.amp, target, dt * 160)

	if speed > 0.5 then
		local d = heading:VectorToObjectSpace(vh)
		d = Vector3.new(d.X, 0, d.Z)
		if d.Magnitude > 0.01 then
			local blended = self.gaitDir:Lerp(d.Unit, MathUtil.Alpha(14, dt))
			self.gaitDir = blended.Magnitude > 0.01 and blended.Unit or d.Unit
		end
	end
	if s == "Stumbling" and self.fallDir.Magnitude > 0.1 then
		local d = heading:VectorToObjectSpace(self.fallDir)
		self.gaitDir = MathUtil.SafeUnit(Vector3.new(d.X, 0, d.Z), self.gaitDir)
	end

	if self.amp > 0.5 then
		local stride = math.max(1.6, 8 * math.sin(math.rad(self.amp)))
		local rate = math.max(speed, s == "Stumbling" and 9 or 0)
		if LYING_STATES[s] then
			rate = math.max(speed * 2.2, 2)
		end
		self.phase += (rate / stride) * math.pi * 2 * dt
		local sign = math.sin(self.phase) >= 0 and 1 or -1
		if sign ~= self.lastStepSign then
			self.lastStepSign = sign
			if self.grounded and UPRIGHT_STATES[s] then
				self:_play("step", 0.5 + 0.5 * math.clamp(speed / Config.RunSpeed, 0, 1))
			end
		end
	end
end

-- Place the foot of a leg (world direction d from the hip) on the surface under it.
function Controller:_footIK(L, hip: Vector3, d: Vector3, heading: CFrame): Vector3
	local foot = hip + d * Config.LegLength
	local origin = Vector3.new(foot.X, hip.Y + 0.3, foot.Z)
	local hit = workspace:Raycast(origin, Vector3.new(0, -(Config.LegLength + 2.6), 0), self.rayParams)
	if not hit then
		return d
	end
	local available = hip.Y - hit.Position.Y
	local extent = -d.Y * Config.LegLength
	local result = d
	if available < extent then
		-- ground is higher than the foot: tilt the leg further so the sole rests on it
		local vertical = math.clamp(available / Config.LegLength, 0.25, 1)
		local horiz = Vector3.new(d.X, 0, d.Z)
		if horiz.Magnitude < 0.05 then
			horiz = heading.LookVector
		end
		horiz = horiz.Unit
		local h = math.sqrt(1 - vertical * vertical)
		local ik = horiz * h - Vector3.new(0, vertical, 0)
		result = d:Lerp(ik, Config.FootIKBlend)
		result = result.Magnitude > 0.01 and result.Unit or d
	end
	-- stand flat on slopes: tilt the leg a little towards the surface normal
	if hit.Normal.Y < 0.985 and Config.SlopeFootAlign > 0 then
		local r = MathUtil.RotationBetween(Vector3.yAxis, hit.Normal)
		local axis, angle = r:ToAxisAngle()
		result = CFrame.fromAxisAngle(axis, angle * Config.SlopeFootAlign):VectorToWorldSpace(result)
	end
	return result
end

function Controller:_updateMuscles(dt: number, heading: CFrame)
	local s = self.state
	local torsoRot = self.torso.CFrame.Rotation
	local invTorso = torsoRot:Inverse()
	local t = self.time
	local strength = Config.StateStrength[s] or { 1, 1 }
	local legTheta = math.rad(self.amp) * math.sin(self.phase)
	local legsOK = self:_workingLegs()
	local moving = MathUtil.Flat(self.torso.AssemblyLinearVelocity).Magnitude > 1.2
	local gaitAxis = self.gaitDir:Cross(Vector3.yAxis)
	gaitAxis = gaitAxis.Magnitude < 0.01 and Vector3.xAxis or gaitAxis.Unit
	local crouch = self.stance == "Crouch"
	self.lastAim = self.lastAim or {}

	for key, L in self.limbs do
		if L.severed or not L.muscle.Parent then
			continue
		end
		local def = L.def
		local side = def.side
		local isLeg = def.kind == "Leg"
		local k = isLeg and strength[1] or strength[2]
		if L.broken then
			k = Config.BrokenLimbStrength
		end
		if s == "Dead" then
			k = 0
		end
		local base = isLeg and Config.LegMuscleTorque or Config.ArmMuscleTorque
		if not isLeg and self.character:GetAttribute("Prosthetic_" .. key) then
			base *= Config.ProstheticArmStrength -- (v2.0) a prosthetic arm is a little weaker
		end
		local torque = base * k * self.scale ^ 4 -- (v2.8) a bigger body: much stronger muscles
		if torque < 5 then
			L.muscle.Enabled = false
			if not isLeg then
				self.lastAim[side < 0 and "Left" or "Right"] = nil
			end
			continue
		end
		L.muscle.Enabled = true
		L.muscle.MaxTorque = torque

		local rel: CFrame
		local kickRel = isLeg and self:_kickRel(key, invTorso, side) or nil
		local slideRel = isLeg and not kickRel and self:_slideLegRel(side) or nil
		if kickRel then
			rel = kickRel
			L.muscle.MaxTorque = torque * 3.5
		elseif slideRel then
			rel = slideRel -- (v2.0) the slide: lead leg out in front
			L.muscle.MaxTorque = torque * 2
		elseif isLeg then
			if UPRIGHT_STATES[s] then
				local theta = (side < 0) and legTheta or -legTheta
				if legsOK == 1 then
					theta = legTheta * 1.15
				end
				local splay = math.rad(Config.IdleLegSplay) * (1 - math.clamp(self.amp / Config.StepAmplitude, 0, 1) * 0.6)
				local world: CFrame
				if crouch and s ~= "GettingUp" then
					local a = math.rad(Config.CrouchLegAngle) + theta * 0.6
					world = heading * CFrame.fromAxisAngle(Vector3.xAxis, a) * CFrame.Angles(0, 0, side * math.rad(Config.CrouchLegSplay))
				else
					world = heading * CFrame.fromAxisAngle(gaitAxis, theta) * CFrame.Angles(0, 0, side * splay)
				end
				if s == "Stumbling" and self.tilt > 5 then
					local fallAxis = self.fallDir:Cross(Vector3.yAxis)
					if fallAxis.Magnitude > 0.01 then
						world = CFrame.fromAxisAngle(fallAxis.Unit, math.rad(self.tilt) * 0.7) * world
					end
				end
				-- foot IK: put the sole on whatever is below it
				local d = world:VectorToWorldSpace(DOWN)
				if not L.broken and self.ground then
					local hip = self.torso.CFrame:PointToWorldSpace(def.torsoPivot)
					local placed = self:_footIK(L, hip, d, heading)
					if placed ~= d then
						world = MathUtil.RotationBetween(d, placed) * world
					end
				end
				rel = invTorso * world.Rotation
			elseif s == "Airborne" then
				local a = (side < 0) and 0.45 or -0.2
				rel = CFrame.Angles(a + 0.12 * math.sin(t * 3 + side), 0, side * 0.1)
			elseif s == "Hanging" then
				rel = CFrame.Angles(0.15 + 0.25 * math.sin(t * 2.4 + side), 0, side * 0.08)
			elseif s == "Tumble" then
				rel = CFrame.Angles(0.6 * math.sin(t * 7 + side * 1.3), 0, side * (0.3 + 0.2 * math.sin(t * 5)))
			elseif s == "Prone" then
				-- legs stretched back, small kicks while crawling
				local kick = moving and 0.22 * math.sin(self.phase + (side > 0 and math.pi or 0)) or 0
				rel = CFrame.Angles(kick, 0, side * 0.12)
			elseif s == "Driving" or s == "Passenger" then
				rel = CFrame.Angles(1.45, 0, side * 0.08) -- sitting: legs forward
			elseif s == "Diving" then
				rel = CFrame.Angles(-0.05, 0, side * 0.1) -- legs stretched out behind
			elseif s == "DropKick" then
				rel = CFrame.Angles(1.4, 0, side * 0.1) -- (a broken leg trails along)
			elseif s == "Flying" then
				rel = self:_flyPose(true, side)
			elseif s == "Swimming" then
				rel = self:_swimPose(true, side)
			else
				rel = CFrame.identity
			end
		else
			local handSide = side < 0 and "Left" or "Right"
			local aim, strong = nil, false
			if not L.broken and s ~= "Ragdoll" and s ~= "Dead" and s ~= "Driving" then
				aim, strong = self:_armAim(handSide, L, heading)
			end
			self.lastAim[handSide] = aim
			if aim then
				local dirLocal = invTorso:VectorToWorldSpace(aim)
				if not LYING_STATES[s] then
					dirLocal = Vector3.new(dirLocal.X, dirLocal.Y, math.min(dirLocal.Z, 0.3))
				end
				dirLocal = MathUtil.SafeUnit(dirLocal, DOWN)
				if dirLocal.Y > 0.97 then
					dirLocal = MathUtil.SafeUnit(Vector3.new(dirLocal.X, 0.97, dirLocal.Z - 0.2), DOWN)
				end
				rel = MathUtil.RotationBetween(DOWN, dirLocal)
				-- (a melee attack swings the arm hard)
				L.muscle.MaxTorque = torque * (strong and 3 or 1.25)
				-- a hand that supports an item (Y) is soft: the grip carries it, the arm only guides
				if self.twoHand and self.twoHand.support == handSide then
					L.muscle.MaxTorque = torque * 0.6
				end
				-- an arm that only holds on to something solid is loose like a rope, so the body can
				-- still move around the hand (a stiff arm + a fixed hand = a frozen body)
				local g = self.hands[handSide].grip
				if not strong and g and g.static and not self.handTarget[handSide] and not (s == "Hanging" and self.climbIntent) then
					L.muscle.MaxTorque = torque * Config.HoldArmSoftness
				end
			elseif s == "Standing" or s == "GettingUp" then
				local legSame = (side < 0) and legTheta or -legTheta
				local swing = math.rad(Config.ArmIdleForward) - legSame * Config.ArmSwingFactor
				local out = math.rad(Config.ArmIdleOut) + math.rad(3) * math.sin(t * 1.3)
				if s == "GettingUp" then
					swing, out = 0.9, 0.25
				elseif crouch then
					swing += 0.35
					out += 0.15
				end
				rel = CFrame.Angles(swing, 0, side * out)
			elseif s == "Stumbling" then
				rel = CFrame.Angles(0.5 + 0.5 * math.sin(t * 9 + side), 0, side * (0.9 + 0.3 * math.sin(t * 7)))
			elseif s == "Airborne" then
				rel = CFrame.Angles(0.45, 0, side * math.rad(70))
			elseif s == "DropKick" then
				rel = CFrame.Angles(-0.4, 0, side * math.rad(80)) -- arms flung out back
			elseif s == "Flying" then
				rel = self:_flyPose(false, side)
			elseif s == "Swimming" then
				rel = self:_swimPose(false, side)
			elseif s == "Hanging" then
				rel = CFrame.Angles(2.6, 0, side * 0.25)
			elseif s == "Tumble" then
				rel = CFrame.Angles(1.2 * math.sin(t * 6 + side), 0, side * (1.3 + 0.4 * math.sin(t * 8)))
			elseif s == "Driving" and self.car and self.car:GetAttribute("Jet") then
				rel = CFrame.Angles(0.55, 0, -side * 0.42) -- (v2.0) a jet: both hands on the stick between the knees
			elseif s == "Driving" then
				rel = CFrame.Angles(1.1, 0, -side * 0.22) -- hands on the steering wheel
			elseif s == "Diving" then
				rel = CFrame.Angles(2.95, 0, side * 0.12) -- arms forward over the head
			elseif s == "Prone" or s == "Downed" then
				-- arm crawl: reach over the head, pull back under the shoulder
				if moving then
					local ph = self.phase + (side > 0 and math.pi or 0)
					rel = CFrame.Angles(2.45 + 0.6 * math.sin(ph), 0, side * (0.35 + 0.15 * math.cos(ph)))
				else
					rel = CFrame.Angles(2.3, 0, side * 0.45)
				end
			else
				rel = CFrame.identity
			end
		end
		L.target.CFrame = CFrame.new(def.torsoPivot) * rel
	end
end

------------------------------------------------------------------------
-- frame
------------------------------------------------------------------------

-- A physics engine lets bodies that barely move "fall asleep" and then skips them. A sleeping body
-- ignores forces that only change gradually (a held hand, a drag, a spike), which looked like the
-- body freezing. A tiny impulse now and then keeps every part of the body awake.
-- (v2.8) a POSE the world puts you in (server attributes PoseCF / PoseKind / PoseUntil): lying on a bed (the ripperdoc's
-- operating bed, the hospital's recovery beds) or sitting in the replay chair. PoseCF is where the Torso goes; the limbs
-- are laid out round it and held there (anchored on this machine, the server sees it as usual). When it ends you go
-- limp for a moment and get up.
function Controller:_holdPose(cf: CFrame, kind: string)
	local char = self.character
	if not self.posed or self.posed.cf ~= cf then
		local list = (self.posed and self.posed.parts) or {}
		local S = self.scale or 1
		local torso = char:FindFirstChild("Torso")
		if torso and torso:IsA("BasePart") then
			for _, name in Poses.PARTS do
				local p = char:FindFirstChild(name)
				if p and p:IsA("BasePart") then
					if not p.Anchored then
						p.Anchored = true
						table.insert(list, p)
					end
					local where = Poses.Where(kind, cf, name, S)
					if where then
						p.CFrame = where
					end
					p.AssemblyLinearVelocity = Vector3.zero
				end
			end
		end
		self.posed = { cf = cf, parts = list }
	end
	if self.drive then
		self.drive.Force = Vector3.zero
	end
end

function Controller:_releasePose()
	local posed = self.posed
	self.posed = nil
	if not posed then
		return
	end
	for _, p in posed.parts do
		if p.Parent then
			p.Anchored = false
			p.AssemblyLinearVelocity = Vector3.zero
		end
	end
	if not self.dead then
		self:Ragdoll(0.6) -- (and up again)
	end
end

function Controller:_keepAwake()
	local now = os.clock()
	if now < (self.nextAwake or 0) or self.car then
		return
	end
	self.nextAwake = now + Config.KeepAwakeInterval
	pcall(function()
		local nudge = Vector3.new(0, 0.015, 0)
		if self.torso.AssemblyLinearVelocity.Magnitude < 4 then
			self.torso:ApplyImpulse(nudge * self.torso.AssemblyMass)
		end
		for _, L in self.limbs do
			if L.part.Parent and L.part.AssemblyRootPart ~= self.torso.AssemblyRootPart and L.part.AssemblyLinearVelocity.Magnitude < 4 then
				L.part:ApplyImpulse(nudge * L.part.AssemblyMass)
			end
		end
	end)
end

-- put the whole body somewhere else (drop pads, shortcuts, the lift)
function Controller:_teleportTo(pos: Vector3, keepItems: boolean)
	for _, side in SIDES do
		local g = self.hands[side].grip
		if g and not (keepItems and g.item) then
			self:_release(side, false)
		end
	end
	local cf = CFrame.new(pos) * self.torso.CFrame.Rotation
	self.character:PivotTo(cf * self.torso.CFrame:ToObjectSpace(self.character:GetPivot()))
	for _, p in self.character:GetDescendants() do
		if p:IsA("BasePart") then
			p.AssemblyLinearVelocity = Vector3.zero
			p.AssemblyAngularVelocity = Vector3.zero
		end
	end
	self.suppressImpacts = os.clock() + 0.3
	self:_setState("Airborne")
end

-- the construction lift: pick a floor (HUD buttons or number keys)
function Controller:LiftTo(floor: number)
	if not self.liftPad or self.dead or os.clock() < self.dropCooldown then
		return
	end
	local map = workspace:FindFirstChild("Map")
	local target = map and map:FindFirstChild("LiftTarget_" .. floor, true)
	if not target or not target:IsA("BasePart") then
		return
	end
	self.dropCooldown = os.clock() + Config.TeleportCooldown
	SoundLibrary.Play("teleport", self.torso, 1)
	self:_teleportTo(target.Position + Vector3.new(0, 3.2, 0), true)
	self.airTime = 0
end

-- drop pads (launch you up), shortcut pads, lift pads
function Controller:_checkDropPad(ground)
	local part = ground and self.grounded and ground.part or nil
	-- trampolines: how fast you came down is how fast you go up again (Space: higher)
	local vy = self.torso.AssemblyLinearVelocity.Y
	if not self.grounded then
		self.airVy = math.min(self.airVy or 0, vy)
	end
	local bounce = part and part:GetAttribute("Bounce")
	if typeof(bounce) == "number" and os.clock() > (self.bounceCD or 0) and not self.dead then
		local up = math.max(-(self.airVy or 0) * bounce, Input.jumpHeld and 75 or 0, 32)
		self.bounceCD = os.clock() + 0.3
		self.airVy = 0
		up = math.min(up, 220)
		pcall(function()
			for _, d in self.character:GetChildren() do
				if d:IsA("BasePart") and d.AssemblyRootPart == d and not d.Anchored then
					local v = d.AssemblyLinearVelocity
					d.AssemblyLinearVelocity = Vector3.new(v.X, up, v.Z)
				end
			end
		end)
		SoundLibrary.Play("thud", self.torso, 0.6)
		self.jumpLock = 0.3
		if self.state ~= "Ragdoll" then
			self:_setState("Airborne")
		end
		return
	elseif part then
		self.airVy = 0
	end
	local floor = part and part:GetAttribute("LiftFloor")
	local onLift = typeof(floor) == "number" and floor or nil
	if onLift ~= self.liftPad then
		self.liftPad = onLift
		if self.onLiftPad then
			self.onLiftPad(onLift)
		end
	end
	if not part then
		return
	end
	local h = part:GetAttribute("DropHeight")
	local tp = part:GetAttribute("TeleportTo")
	if (typeof(h) ~= "number" and typeof(tp) ~= "Vector3") or os.clock() < self.dropCooldown then
		return
	end
	local teleport = typeof(tp) == "Vector3"
	self.dropCooldown = os.clock() + (teleport and Config.TeleportCooldown or 2.5)
	if teleport then
		SoundLibrary.Play("teleport", self.torso, 1)
		self:_teleportTo(tp + Vector3.new(0, 3.2, 0), true)
		self.airTime = 0
	else
		self:_teleportTo(self.torso.Position + Vector3.new(0, h, 0), false)
		self.airTime = 1
	end
end

function Controller:_reportState()
	local knocked = KNOCKED_STATES[self.state] == true
	if knocked ~= self.reportedKnocked then
		self.reportedKnocked = knocked
		StateRemote:FireServer(knocked)
	end
end

-- Walking into a step that the hips have not risen above yet (it caught the torso / arms): a small
-- hop onto it. Only for real steps (between StepAssistRise and StepUpMax high), with a cooldown.
function Controller:_stepAssist(dt: number, ground, moveWorld: Vector3)
	local s = self.state
	if (s ~= "Standing" and s ~= "Stumbling") or moveWorld.Magnitude < 0.3 or not self.grounded or not ground then
		self.blockedTime = 0
		return
	end
	local dir = moveWorld.Unit
	local vh = MathUtil.Flat(self.torso.AssemblyLinearVelocity)
	local want = (Input.Running() and Config.RunSpeed or Config.WalkSpeed) * math.min(1, moveWorld.Magnitude)
	if self.stance == "Crouch" then
		want = Config.CrouchSpeed
	end
	if vh:Dot(dir) > want * 0.45 then
		self.blockedTime = 0
		return
	end
	self.blockedTime += dt
	if self.blockedTime < 0.12 or os.clock() < self.nextStepAssist then
		return
	end
	local origin = self.torso.Position + dir * 1.3 + Vector3.new(0, 1.2, 0)
	local hit = workspace:Raycast(origin, Vector3.new(0, -6, 0), self.rayParams)
	if not hit or hit.Normal.Y < COS_SLOPE then
		return
	end
	local rise = hit.Position.Y - ground.y
	if rise < Config.StepAssistRise or rise > Config.StepUpMax + 0.1 then
		return
	end
	self.nextStepAssist = os.clock() + Config.StepAssistCooldown
	self.blockedTime = 0
	local up = math.sqrt(2 * workspace.Gravity * (rise + 0.5))
	local function hop(part: BasePart)
		local v = part.AssemblyLinearVelocity
		local target = Vector3.new(v.X, math.max(v.Y, up), v.Z) + dir * 4 * (self.slowK or 1)
		part:ApplyImpulse((target - v) * part.AssemblyMass)
	end
	pcall(function()
		hop(self.torso)
		for _, L in self.limbs do
			if not L.severed then
				hop(L.part)
			end
		end
	end)
	self.jumpLock = 0.1
end

-- (v2.8) slow motion starts / ends: the body's speed shrinks (or comes back: the fall goes on at full speed) and its
-- muscles answer slower
function Controller:_slowShift(k: number)
	local f = k / (self.slowK or 1)
	self.slowK = k
	for _, part in self.character:GetDescendants() do
		if part:IsA("BasePart") then
			for _, name in { "LocalTemporalGravity", "LocalTemporalAttachment" } do
				local old = part:FindFirstChild(name)
				if old then old:Destroy() end
			end
			if k < 1 and not part.Anchored and part.AssemblyRootPart == part then
				local att = Instance.new("Attachment")
				att.Name, att.Parent = "LocalTemporalAttachment", part
				local force = Instance.new("VectorForce")
				force.Name, force.Attachment0, force.RelativeTo, force.ApplyAtCenterOfMass = "LocalTemporalGravity", att, Enum.ActuatorRelativeTo.World, true
				force.Force = Vector3.new(0, workspace.Gravity * (1 - k * k) * part.AssemblyMass, 0)
				force.Parent = part
			end
		end
	end
	for _, d in self.character:GetDescendants() do
		if d:IsA("BasePart") and not d.Anchored and d.AssemblyRootPart == d then
			pcall(function()
				d.AssemblyLinearVelocity *= f
				d.AssemblyAngularVelocity *= f
			end)
		end
	end
	for _, L in self.limbs do
		local m = L.muscle
		if m then
			local base = m:GetAttribute("BaseResp")
			if typeof(base) ~= "number" then
				base = m.Responsiveness
				m:SetAttribute("BaseResp", base)
			end
			m.Responsiveness = math.max(5, (base :: number) * k)
		end
	end
	-- (v2.8.1) what you hold slows down with you: a body or a crate in your hand kept its full speed and yanked you away
	if self._heldInstances then
		for _, inst in self:_heldInstances() do
			local root = inst:IsA("BasePart") and inst or (inst:IsA("Model") and inst.PrimaryPart or nil)
			root = root and (root.AssemblyRootPart or root)
			if root and not root.Anchored then
				pcall(function()
					root.AssemblyLinearVelocity *= f
					root.AssemblyAngularVelocity *= f
				end)
			end
		end
	end
end

function Controller:_step(dt: number)
	if not self.ready or not self.alive then
		return
	end
	local torso = self.torso
	if not torso.Parent or not self.character.Parent then
		return
	end
	if (self.character:GetAttribute("TemporalFrozenUntil") or 0) > workspace:GetServerTimeNow() then
		Input.useHeld = false
		return
	end
	dt = math.min(dt, 1 / 20)
	-- (v2.8) the Sandevistan: for its user nothing changes (their screen keeps the real gravity); everybody else lives
	-- in slow motion - their clock, their speed, their turning, their jumps
	-- (v2.9) a LOCAL Sandevistan (SlowFieldR): only a body within the radius of the one who runs it is slowed; farther
	-- away you keep moving at full speed
	local tk = TimeScale.ForField(LocalPlayer.UserId, torso.Position)
	if tk ~= (self.slowK or 1) then
		self:_slowShift(tk)
	end
	dt *= tk
	self.time += dt
	-- (v2.8.1) living in somebody's Sandevistan: on your feet you never shoot off faster than slow motion allows
	-- (a recoil, the weight in your hand, a kick from the ground: you flew away in the lowered gravity)
	if tk < 1 and UPRIGHT_STATES[self.state] and not self.flying then
		local v = torso.AssemblyLinearVelocity
		local cj = self.character:GetAttribute("CyJump")
		local capUp = Config.JumpVelocity * 1.4 * tk * (typeof(cj) == "number" and math.clamp(cj, 1, 2.5) or 1) * math.sqrt(self.scale)
		local flat = Vector3.new(v.X, 0, v.Z)
		local capH = Config.RunSpeed * 1.8 * tk * math.sqrt(self.scale)
		if v.Y > capUp or flat.Magnitude > capH then
			local h = flat.Magnitude > capH and flat.Unit * capH or flat
			torso.AssemblyLinearVelocity = Vector3.new(h.X, math.min(v.Y, capUp), h.Z)
		end
	end
	-- (v2.8) the body's size (BULK FRAME / COLOSSUS)
	local bs = self.character:GetAttribute("BodyScale")
	local S = typeof(bs) == "number" and math.clamp(bs, 0.5, 4) or 1
	if S ~= self.scale then
		self.scale = S
		self.embedCheckUntil = os.clock() + 2.5
	end
	-- (v2.8.1 fix) a big body (BULK FRAME / COLOSSUS) grows on spawn: its legs could end up in the ground (the body
	-- grew round its middle, or the lift came before the body was here). For a moment after a spawn or a size change:
	-- if the ground is above the feet, the body is put on top of it.
	if os.clock() < (self.embedCheckUntil or 0) and not self.dead and not self.car and self.state ~= "Ragdoll" then
		local top = self.torso.Position + Vector3.new(0, 3 * S, 0)
		local hit = workspace:Raycast(top, Vector3.new(0, -9 * S, 0), self.rayParams)
		if hit and hit.Position.Y < self.torso.Position.Y + 0.5 * S then
			local need = (Config.TorsoHalfHeight + Config.LegLength + Config.FootClearance) * S
			local feet = self.torso.Position.Y - need
			if hit.Position.Y > feet + 0.4 * S then
				local lift = hit.Position.Y - feet + 0.1
				self.character:PivotTo(self.character:GetPivot() + Vector3.new(0, lift, 0))
				for _, d in self.character:GetDescendants() do
					if d:IsA("BasePart") and not d.Anchored then
						d.AssemblyLinearVelocity = Vector3.zero
					end
				end
			end
		end
	end
	-- (v2.8) a pose: lying on a bed, sitting in the replay chair
	local poseCF = self.character:GetAttribute("PoseCF")
	local poseUntil = self.character:GetAttribute("PoseUntil")
	if typeof(poseCF) == "CFrame" and typeof(poseUntil) == "number" and workspace:GetServerTimeNow() < poseUntil and not self.dead then
		local kind = self.character:GetAttribute("PoseKind")
		self:_holdPose(poseCF, typeof(kind) == "string" and kind or "lie")
		-- (v2.8.2 fix) asleep on the table / the bed: waking up still counts here (the screen stayed black for good when
		-- the sleep began and ended inside the pose: nobody ever said "awake")
		local asleep = self:IsAsleep()
		if self.wasAsleep and not asleep and self.onWake then
			self.onWake()
		end
		self.wasAsleep = asleep
		return
	elseif self.posed then
		self:_releasePose()
	end
	-- (v2.8.2) in the back of a VAN (sitting, or held there): the van carries the body; the body's own machine does nothing.
	-- Sitting by choice ("seat"): Space gets you out.
	local inVan = self.character:GetAttribute("InVan")
	if inVan and not self.dead then
		if self.drive then
			self.drive.Force = Vector3.zero
		end
		self.suppressImpacts = math.max(self.suppressImpacts, os.clock() + 0.6)
		local asleep = self:IsAsleep()
		if self.wasAsleep and not asleep and self.onWake then
			self.onWake()
		end
		self.wasAsleep = asleep
		if inVan == "seat" and Input.jumpHeld and os.clock() - (self.vanOutAt or 0) > 1 then
			self.vanOutAt = os.clock()
			local cyber = Remotes:FindFirstChild("Cyber")
			if cyber and cyber:IsA("RemoteEvent") then
				cyber:FireServer("vanout")
			end
		end
		return
	end
	-- (v2.8) ZERO HOUR: frozen in the ice - nothing moves until it melts
	local fz = self.character:GetAttribute("CyFrozen")
	local frozen = typeof(fz) == "number" and workspace:GetServerTimeNow() < fz
	if frozen and not self.frozenParts then
		local list = {}
		for _, d in self.character:GetDescendants() do
			if d:IsA("BasePart") and not d.Anchored then
				d.Anchored = true
				table.insert(list, d)
			end
		end
		self.frozenParts = list
	elseif not frozen and self.frozenParts then
		for _, d in self.frozenParts do
			if d.Parent then
				d.Anchored = false
			end
		end
		self.frozenParts = nil
	end
	if frozen then
		return
	end
	-- (v2.8) a paralysis dart: limp until it wears off (awake)
	local pz = self.character:GetAttribute("ParalyzedUntil")
	if typeof(pz) == "number" and workspace:GetServerTimeNow() < pz and not self.dead then
		if self.state ~= "Ragdoll" then
			self:Ragdoll(1)
		end
		self.ragdollTimer = math.max(self.ragdollTimer, 0.5)
	end

	self:_readCondition()
	self:_reportState()
	self:_keepAwake()
	if self.dead then
		self.drive.Force = Vector3.zero
		self.balance.Enabled = false
		self:_senseImpacts(dt) -- corpses still take damage
		return
	end

	local yaw = Cam.yaw
	if self.faceYaw and os.clock() < self.faceYawUntil then
		yaw = self.faceYaw -- (v2.8) SENTRY REFLEX: turned to the shooter
	end
	if tk < 1 then
		-- the body turns slowly towards where you look (the camera itself turns slower too: CameraController)
		local cur = self.slowYaw or yaw
		local diff = (yaw - cur + math.pi) % (2 * math.pi) - math.pi
		cur += math.clamp(diff, -dt * 7, dt * 7)
		self.slowYaw = cur
		yaw = cur
	else
		self.slowYaw = nil
	end
	local heading = CFrame.Angles(0, yaw, 0)
	local mv = Input.GetMoveVector()
	local moveWorld = heading:VectorToWorldSpace(Vector3.new(mv.X, 0, mv.Z))
	if Input.menuOpen or Input.promptOpen or self:IsAsleep() then
		moveWorld = Vector3.zero
	end
	local hv = MathUtil.Flat(torso.AssemblyLinearVelocity)

	self.tilt = MathUtil.AngleDeg(torso.CFrame.UpVector, Vector3.yAxis)
	local up = torso.CFrame.UpVector
	self.fallDir = MathUtil.SafeUnit(Vector3.new(up.X, 0, up.Z), Vector3.zero)

	self.jumpLock = math.max(0, self.jumpLock - dt)
	-- (v2.8.1) the muscle-up runs on its own until you are on top
	if self.mantle then
		if self.dead or self.state == "Ragdoll" or self.car then
			self.mantle = nil
		elseif self:_mantleStep(dt) then
			return
		end
	end
	if self.state == "Airborne" and self.airTime < 1.2 then
		self:_tryVault(moveWorld)
	end
	local ground = self:_probeGround(moveWorld, heading, hv.Magnitude)
	-- (v2.8.2) standing on somebody: you slip off them (sideways, away from their middle)
	if self.bodyUnder and (not ground or ground.height > self:_standHeight() + Config.GroundTolerance * self.scale) and not self.dead then
		local away = MathUtil.Flat(torso.Position - self.bodyUnder)
		away = away.Magnitude > 0.2 and away.Unit or MathUtil.SafeUnit(MathUtil.Flat(torso.CFrame.LookVector), Vector3.xAxis)
		local v = torso.AssemblyLinearVelocity
		if MathUtil.Flat(v):Dot(away) < 9 then
			torso.AssemblyLinearVelocity = v + away * 1.6
		end
	end
	local standH = self:_standHeight()
	self.grounded = ground ~= nil and ground.height <= standH + Config.GroundTolerance * self.scale and self.jumpLock <= 0
	self.ground = ground
	if self.striderAir then
		if self.state == "Ragdoll" or self.state == "Tumble" or self.dead then
			self.striderAir = nil -- (knocked out of the air: that fall counts)
		elseif self.grounded then
			self.striderLandAt = self.striderLandAt or os.clock()
			if os.clock() - self.striderLandAt > 0.35 then
				self.striderAir = nil
				self.striderLandAt = nil
			end
		end
	end
	if self.grounded then
		self.airTime = 0
		self.groundTime += dt
	else
		self.airTime += dt
		self.groundTime = 0
	end

	self:_updateHandTargets()
	self:_updateGrips(dt, moveWorld)
	self:_updateClimbIntent()
	self:_updateWater(dt)
	self:_updateState(dt, ground, moveWorld)
	if self.state == "Hanging" then
		for _, side in SIDES do
			local g = self.hands[side].grip
			if g and g.static then
				g.hung = true
			end
		end
	end
	self:_setLegCollision(not UPRIGHT_STATES[self.state])
	self:_updateGait(dt, ground, heading)
	self:_applyForces(dt, ground, moveWorld, heading)
	self:_stepAssist(dt, ground, moveWorld)
	self:_updateMuscles(dt, heading)
	self:_updateKick(dt)
	self:_updateSlide(dt)
	self:_updatePowers(dt)
	self:_updateGuns(dt)
	self:_updateGear(dt)
	self:_tryGrab()
	self:_senseImpacts(dt)
	if not self.car then
		self:_checkDropPad(ground)
	elseif self.liftPad then
		self.liftPad = nil
		if self.onLiftPad then
			self.onLiftPad(nil)
		end
	end

	local wind = self.wind
	if wind then
		local vy = torso.AssemblyLinearVelocity.Y
		if self.state == "Tumble" or (self.state == "Airborne" and vy < -50) then
			if not wind.IsPlaying then
				wind:Play()
			end
			wind.Volume = math.clamp(-vy / 200, 0.05, 0.6)
		elseif wind.IsPlaying then
			wind:Stop()
		end
	end
end

------------------------------------------------------------------------
-- info for the HUD
------------------------------------------------------------------------

function Controller:GetStateName(): string
	return self.state
end

function Controller:GetStance(): string
	if self.state == "Prone" then
		return "Prone"
	elseif self.state == "Downed" then
		return "Downed"
	end
	return self.stance
end

-- mix in hands (grab / guns / climbing) and the sensor (impacts / strikes)
require(Modules:WaitForChild("Hands"))(Controller)
require(Modules:WaitForChild("Sensor"))(Controller)
require(Modules:WaitForChild("Kick"))(Controller)
require(Modules:WaitForChild("Slide"))(Controller)
require(Modules:WaitForChild("Pockets"))(Controller)
require(Modules:WaitForChild("TwoHand"))(Controller)
require(Modules:WaitForChild("Fly"))(Controller)
require(Modules:WaitForChild("Swim"))(Controller)
require(Modules:WaitForChild("Powers"))(Controller)
require(Modules:WaitForChild("Gear"))(Controller)

return Controller
