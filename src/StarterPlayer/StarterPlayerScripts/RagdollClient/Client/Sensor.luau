--!nonstrict
-- Sensor (mixin for CharacterController): everything that hurts or pushes the own body.
--   * velocity change of every body part -> what was hit? (ContactSolver)
--       spikes / blades  -> pierce (can impale you)
--       moving objects   -> kinetic energy of the collision (heavy things break bones)
--       ground / walls   -> fall damage
--   * crushing: weight of objects resting on a body part
--   * wall slam: sprinting into a wall throws you back
--   * strikes: your hands / held objects hitting other bodies (sent to the server, which
--     forwards them to the other player so they get knocked over too)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local ContactSolver = require(Shared:WaitForChild("ContactSolver"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ImpactRemote = Remotes:WaitForChild("Impact") :: RemoteEvent
local StrikeRemote = Remotes:WaitForChild("Strike") :: RemoteEvent
local StruggleRemote = Remotes:WaitForChild("Struggle") :: RemoteEvent

local Modules = script.Parent
local Cam = require(Modules:WaitForChild("CameraController"))
local Input = require(Modules:WaitForChild("Input"))

local SIDES = { "Left", "Right" }
local ARM_OF = { Left = "LeftArm", Right = "RightArm" }
local ACTIVE = { Standing = true, Stumbling = true, Airborne = true, Hanging = true, Prone = true, GettingUp = true }

local function sense(track, part: BasePart, now: number): (number, Vector3?)
	local v = part.AssemblyLinearVelocity
	local hist = track.hist
	table.insert(hist, { t = now, v = v })
	while #hist > 6 do
		table.remove(hist, 1)
	end
	local best, bestV = 0, nil
	for i = 1, #hist - 1 do
		local h = hist[i]
		if now - h.t <= 0.07 then
			local d = (v - h.v).Magnitude
			if d > best then
				best, bestV = d, h.v
			end
		end
	end
	return best, bestV
end

local function otherBodyOf(self, part: Instance): Model?
	local m = part:FindFirstAncestorOfClass("Model")
	while m do
		if m:GetAttribute("RagdollRig") then
			return m ~= self.character and m or nil
		end
		m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
	end
	return nil
end

return function(Controller)
	----------------------------------------------------------------------
	-- spikes: ONLY the stabbed body part sticks to the spike; the rest of the body keeps working.
	-- The pin lives on this client (it simulates the body, so the joint is made at the exact contact
	-- point). Hold a move key / Space to tear it free (hurts), or it tears free after a while.
	----------------------------------------------------------------------

	function Controller:_pinToSpike(region: string, spike: BasePart, point: Vector3)
		if self.dead or not (spike:IsGrounded() or spike.AssemblyMass > 8) then
			return
		end
		local part: BasePart? = nil
		if region == "Head" then
			part = self.head
		elseif region == "Torso" then
			part = self.torso
		else
			local L = self.limbs[region]
			part = (L and not L.severed) and L.part or nil
		end
		if not part then
			return
		end
		self.pins = self.pins or {}
		for _, pin in self.pins do
			if pin.part == part then
				return
			end
		end
		local a0 = Instance.new("Attachment")
		a0.Name = "SpikePinA"
		a0.Parent = part
		a0.WorldPosition = point
		local a1 = Instance.new("Attachment")
		a1.Name = "SpikePinB"
		a1.Parent = spike
		a1.WorldPosition = point
		-- a force holds the stabbed part at the spike (no joint to the spike: a joint to an anchored
		-- spike could lock the whole body). Only this body part is held, the rest hangs off it.
		local joint = Instance.new("AlignPosition")
		joint.Name = "SpikePin"
		joint.Mode = Enum.PositionAlignmentMode.OneAttachment
		joint.Attachment0 = a0
		joint.Position = point
		joint.MaxForce = self.bodyMass * workspace.Gravity * Config.PinForce
		joint.MaxVelocity = 40
		joint.Responsiveness = 60
		joint.RigidityEnabled = false
		joint.Parent = part
		-- the spike is inside that body part: no collision pushing it back out
		ContactSolver.PassThrough(self.character, spike, point, joint)
		table.insert(self.pins, { part = part, region = region, joint = joint, a0 = a0, a1 = a1, t = os.clock() })
	end

	function Controller:IsPinned(): boolean
		return self.pins ~= nil and #self.pins > 0
	end

	function Controller:_updatePins(dt: number)
		if not self.pins or #self.pins == 0 then
			self.pinStruggle = 0
			return
		end
		-- the spike may move (a held spear, a swinging trap): the pin follows it
		for _, pin in self.pins do
			if pin.a1.Parent and pin.joint.Parent then
				pin.joint.Position = pin.a1.WorldPosition
			end
		end
		if self.dead then
			self.pinStruggle = 0
			return -- (a corpse stays on the spike)
		end
		local now = os.clock()
		local trying = Input.jumpHeld or Input.GetMoveVector().Magnitude > 0.5
		self.pinStruggle = trying and (self.pinStruggle or 0) + dt or 0
		local tear = self.pinStruggle > Config.ImpaleStruggleTime
		for i = #self.pins, 1, -1 do
			local pin = self.pins[i]
			if tear or not pin.joint.Parent or not pin.part.Parent or now - pin.t > Config.ImpaleTime then
				pin.joint:Destroy()
				pin.a0:Destroy()
				pin.a1:Destroy()
				table.remove(self.pins, i)
				if pin.part.Parent then
					StruggleRemote:FireServer(pin.region)
					SoundLibrary.Play("gore", pin.part, 0.6)
				end
			end
		end
		if tear then
			self.pinStruggle = 0
		end
	end

	-- (v1.9) soft things (trampoline, mattress, bed, sofa ...) carry a "Soft" attribute 0..1: the share of the
	-- landing they swallow. A trampoline (1) never hurts.
	local function softnessAt(self, point: Vector3): number
		local best = 0
		for _, p in workspace:GetPartBoundsInRadius(point, 1.8, self.overlapParams) do
			local v = p:GetAttribute("Soft")
			if typeof(v) ~= "number" then
				local m = p:FindFirstAncestorOfClass("Model")
				v = m and m:GetAttribute("Soft")
			end
			if typeof(v) == "number" and v > best then
				best = v
			end
		end
		return best
	end

	function Controller:_handleHit(region: string, res, point: Vector3, dv: number): number
		local kind = res.kind
		if kind == "pierce" then
			-- one stab per body part per moment (resting on a spike is not a new stab every frame)
			self.lastPierce = self.lastPierce or {}
			local now = os.clock()
			if now - (self.lastPierce[region] or 0) < Config.PierceCooldown then
				return 0
			end
			self.lastPierce[region] = now
			-- only this body part sticks to the spike
			if res.other then
				self:_pinToSpike(region, res.other, point)
			end
			ImpactRemote:FireServer("pierce", region, res.value, point, res.other)
			Cam.Shake(1.1)
			SoundLibrary.Play("stab", point, 1)
			if not self.dead then
				if res.value >= Config.PierceKnockSpeed then
					self:Ragdoll(1.2)
				elseif self.state == "Standing" then
					self:_setState("Stumbling")
				end
			end
			return 0
		elseif kind == "energy" then
			ImpactRemote:FireServer("energy", region, res.value, point, res.other)
			Cam.Shake(math.clamp(res.value / 3000, 0.2, 1.4))
			if not self.dead then
				-- (v2.8.2) BEDROCK STABILIZER tier 2+: whatever crashes into you does not knock you over
				local stance = self.character:GetAttribute("CyStance")
				local anchored = typeof(stance) == "number" and stance >= 2
				if res.value >= Config.ObjectKnockdownEnergy and not anchored then
					self:Ragdoll(math.clamp(0.8 + res.value / 6000, 1, 3))
				elseif res.value >= 700 and self.state == "Standing" and not anchored then
					self:_setState("Stumbling")
				end
			end
			return 0
		end
		-- ground / wall
		local soft = softnessAt(self, point)
		if soft > 0 then
			dv = dv * (1 - math.min(soft, 1))
			if soft >= 0.95 then
				return 0
			end
		end
		if dv >= Config.ImpactMin then
			ImpactRemote:FireServer("impact", region, dv, point)
			Cam.Shake(math.clamp((dv - Config.ImpactMin) / 60, 0.25, 1.4))
			SoundLibrary.Play(dv > 95 and "bodyHit" or "thud", point, math.clamp(dv / 120, 0.3, 1))
		end
		return dv
	end

	function Controller:_wallSlam()
		local s = self.state
		local now = os.clock()
		local hv = MathUtil.Flat(self.torso.AssemblyLinearVelocity)
		self.hvHist = self.hvHist or {}
		local hist = self.hvHist
		table.insert(hist, { t = now, v = hv })
		while #hist > 0 and now - hist[1].t > 0.15 do
			table.remove(hist, 1)
		end
		if (s ~= "Standing" and s ~= "Stumbling") or self:_hasStaticGrip() then
			return
		end
		local prev: Vector3? = nil
		for _, h in hist do
			if not prev or h.v.Magnitude > prev.Magnitude then
				prev = h.v
			end
		end
		if not prev or prev.Magnitude < Config.WallSlamMinSpeed or hv.Magnitude > prev.Magnitude * Config.WallSlamStopRatio then
			return
		end
		local dir = prev.Unit
		local hit = nil
		for _, h in { 0.6, -0.3 } do
			hit = hit or workspace:Raycast(self.torso.Position + Vector3.new(0, h, 0), dir * 2.3, self.rayParams)
		end
		if not hit or hit.Normal:Dot(-dir) < 0.45 then
			return
		end
		local inst = hit.Instance
		if not (inst:IsGrounded() or inst.AssemblyMass > self.bodyMass * 3) then
			return
		end
		table.clear(hist)
		local speed = prev.Magnitude
		local bounce = -dir * speed * Config.WallSlamBounce + Vector3.new(0, 9, 0)
		pcall(function()
			self.torso:ApplyImpulse(bounce * self.torso.AssemblyMass)
			for _, L in self.limbs do
				if not L.severed then
					L.part:ApplyImpulse(bounce * L.part.AssemblyMass)
				end
			end
		end)
		self.suppressImpacts = os.clock() + 0.12
		SoundLibrary.Play("bodyHit", hit.Position, math.clamp(speed / 30, 0.5, 1))
		Cam.Shake(math.clamp(speed / 25, 0.5, 1.3))
		local stance = self.character:GetAttribute("CyStance")
		if not (typeof(stance) == "number" and stance >= 2) then
			self:Ragdoll(1 + speed / 30) -- (v2.8.2: BEDROCK STABILIZER tier 2+ stays on its feet)
		end
		if speed >= Config.WallSlamHurtSpeed then
			local region = math.random() < 0.5 and "Head" or "Torso"
			ImpactRemote:FireServer("impact", region, Config.ImpactMin + 8 + (speed - Config.WallSlamHurtSpeed) * 3, hit.Position)
		end
	end

	function Controller:_senseCrush(dt: number)
		self.crushTimer = (self.crushTimer or 0) + dt
		if self.crushTimer < 0.25 then
			return
		end
		local step = self.crushTimer
		self.crushTimer = 0
		local parts = { { region = "Torso", part = self.torso }, { region = "Head", part = self.head } }
		for key, L in self.limbs do
			if not L.severed then
				table.insert(parts, { region = key, part = L.collider or L.part })
			end
		end
		for _, e in parts do
			local p = e.part
			if p and p.Parent and not self.character:GetAttribute("Severed_" .. e.region) then
				local dps, other = ContactSolver.Crush(p, self.crushParams, self.velCache)
				if dps > 0 then
					local amount = math.min(dps * step, 60)
					ImpactRemote:FireServer("crush", e.region, amount, p.Position + Vector3.new(0, p.Size.Y * 0.4, 0), other)
					if amount > 4 and not self.dead and self.state ~= "Ragdoll" then
						self:Ragdoll(1.5)
					end
				end
			end
		end
	end

	function Controller:_senseStrikes()
		if not ACTIVE[self.state] then
			return
		end
		local now = os.clock()
		self.strikeCD = self.strikeCD or {}
		-- never "hit" a body we are holding / dragging
		local holding = {}
		for _, inst in self:_heldInstances() do
			holding[inst] = true
		end
		local function tryStrike(probeParts: { BasePart }, velocity: Vector3, mass: number)
			for _, p in probeParts do
				local body = otherBodyOf(self, p)
				if body and not holding[body] and (self.strikeCD[body] or 0) < now then
					self.strikeCD[body] = now + 0.35
					StrikeRemote:FireServer(p, velocity, mass)
					return
				end
			end
		end
		for _, side in SIDES do
			local L = self.limbs[ARM_OF[side]]
			local held = self.hands[side].grip
			if L and not L.severed and not L.broken and not (held and held.item) then
				-- (v2.8.2) SICKLE BLADES out: the blade reaches past the fist and a lighter swing already cuts (the server
				-- makes it a cut: KnockService.BladeMod)
				local blade = self.character:GetAttribute("Cy_open_sickles_" .. (side == "Left" and "L" or "R")) == true
				local tip = L.part.CFrame:PointToWorldSpace(Vector3.new(0, blade and -1.6 or -0.9, 0))
				local v = L.part:GetVelocityAtPosition(tip)
				if v.Magnitude >= (blade and Config.StrikeMinSpeed * 0.5 or Config.StrikeMinSpeed) then
					tryStrike(workspace:GetPartBoundsInRadius(tip, blade and 1.3 or 0.9, self.overlapParams), v, L.part.AssemblyMass)
				end
			end
			local g = self.hands[side].grip
			-- (weapons in the hand report their own hits, see Hands:_updateMelee)
			if g and not g.static and not g.item and not g.body and g.part.Parent and not otherBodyOf(self, g.part) then
				local root = g.part.AssemblyRootPart or g.part
				local v = root.AssemblyLinearVelocity
				if v.Magnitude >= Config.StrikeMinSpeed then
					tryStrike(workspace:GetPartBoundsInBox(root.CFrame, root.Size + Vector3.new(1, 1, 1), self.overlapParams), v, root.AssemblyMass)
				end
			end
		end
		for key, cd in self.strikeCD do
			if cd < now - 2 then
				self.strikeCD[key] = nil
			end
		end
	end

	function Controller:_senseImpacts(dt: number)
		local now = os.clock()
		-- (v2.8.1) landing your own STRIDER LEGS jump: no fall damage
		local suppressed = now < self.suppressImpacts or (self.striderAir == true and self.state ~= "Ragdoll" and self.state ~= "Tumble")
		local worst = 0
		self.velCache:Track(self.torso.Position, 9, self.crushParams)

		do
			local tr = self.torsoTrack
			local dv, before = sense(tr, self.torso, now)
			if not suppressed and before and dv >= 12 and now >= tr.cooldown then
				local region, point = RigInfo.ClassifyTorsoHit(self.torso.CFrame, before)
				local res = ContactSolver.Solve(point, before, dv, self.bodyMass, self.velCache, self.crushParams)
				if res then
					tr.cooldown = now + Config.ImpactCooldown
					worst = math.max(worst, self:_handleHit(region, res, point, dv))
				end
				if dv >= Config.BumpImpact and self.state == "Standing" and self.groundTime > 0.4 and dv < Config.KnockdownImpact then
					self:_setState("Stumbling")
				end
			end
		end

		for key, L in self.limbs do
			if L.severed or not L.part.Parent then
				continue
			end
			local dv, before = sense(L, L.part, now)
			local side = key == "LeftArm" and "Left" or key == "RightArm" and "Right" or nil
			if suppressed or (side and now < self.armSuppress[side]) then
				continue
			end
			if before and dv >= 12 and now >= L.cooldown then
				local point = RigInfo.LeadingPoint(L.part.CFrame, L.part.Size, before)
				local res = ContactSolver.Solve(point, before, dv, self.bodyMass, self.velCache, self.crushParams)
				if res then
					L.cooldown = now + Config.ImpactCooldown
					worst = math.max(worst, self:_handleHit(key, res, point, dv))
				end
			end
		end

		local stance = self.character:GetAttribute("CyStance")
		if worst >= Config.KnockdownImpact and not self.dead and self.state ~= "Ragdoll" and not (typeof(stance) == "number" and stance >= 3) then
			self:Ragdoll(0.9 + (worst - Config.KnockdownImpact) / 55) -- (v2.8.2: BEDROCK STABILIZER tier 3: never)
		end

		self:_senseCrush(dt)
		self:_updatePins(dt)
		if not self.dead then
			self:_wallSlam()
			self:_senseStrikes()
		end
	end
end
