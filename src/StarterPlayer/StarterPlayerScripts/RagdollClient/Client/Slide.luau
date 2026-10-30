--!nonstrict
-- Slide (mixin for CharacterController, v1.9 / v2.0): sprint, then press Ctrl (crouch) and you slide: you drop low,
-- lean back with the lead leg out in front and glide forward fast, slowing down over Config.SlideTime, and you can
-- steer a little. Jump or press Ctrl again to get out of it early. It only starts while you are running on the ground.
-- (v2.0) a proper slide pose (lean back, lead leg out, one hand trailing on the floor, the other up), it goes
-- longer, and it is a slide tackle: slide into somebody's legs and their feet are swept away - they fall over you
-- while you slide on under them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))

local Modules = script.Parent
local Input = require(Modules:WaitForChild("Input"))
local Cam = require(Modules:WaitForChild("CameraController"))

local KickRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Kick") :: RemoteEvent

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

local tackleParams = OverlapParams.new()
tackleParams.FilterType = Enum.RaycastFilterType.Exclude
tackleParams.RespectCanCollide = false

return function(Controller)
	-- true when a slide started
	function Controller:_startSlide(): boolean
		if Config.Lite then
			return false -- (switched off in the reduced test build)
		end
		if self.slide or self.state ~= "Standing" or self.flying or self.car or self.dead then
			return false
		end
		if os.clock() < (self.slideReady or 0) then
			return false
		end
		if not Input.Running() or (self.groundTime or 0) < 0.15 then
			return false
		end
		local flat = MathUtil.Flat(self.torso.AssemblyLinearVelocity)
		if flat.Magnitude < Config.WalkSpeed * 1.15 then
			return false
		end
		self.slide = {
			t0 = os.clock(),
			dir = flat.Unit,
			v0 = math.clamp(flat.Magnitude * 1.35, Config.RunSpeed, Config.SlideMaxSpeed),
			hit = {},
			speed = 0,
		}
		self.stance = "Crouch"
		Cam.Shake(0.18)
		SoundLibrary.Play("slideStart", self.torso, 0.9)
		local loop = SoundLibrary.Loop("slideScrape", self.torso)
		if loop then
			loop.Volume = 0.7
			loop:Play()
			self.slide.loop = loop
		end
		self:_slideDust(true)
		return true
	end

	function Controller:_endSlide()
		if not self.slide then
			return
		end
		local loop = self.slide.loop
		if loop then
			-- (the scrape fades out - no thump at the end)
			task.spawn(function()
				for i = 1, 8 do
					if not loop.Parent then
						return
					end
					loop.Volume *= 0.7
					task.wait(0.03)
				end
				loop:Destroy()
			end)
		end
		self.slide = nil
		self.slideReady = os.clock() + Config.SlideCooldown
		-- (getting up out of the slide is not a landing: no impact sounds / damage for a moment)
		self.suppressImpacts = math.max(self.suppressImpacts or 0, os.clock() + 0.6)
		if self.stance == "Crouch" then
			self.stance = "Stand"
		end
		self:_slideDust(false)
	end

	-- a little dust under you while you slide (only you see it: the body itself is what the others see)
	function Controller:_slideDust(on: boolean)
		local e = self.slideDustEmitter
		if on then
			if not e or not e.Parent then
				local a = Instance.new("Attachment")
				a.Name = "SlideDust"
				a.Position = Vector3.new(0, -1.1, 0)
				a.Parent = self.torso
				e = Instance.new("ParticleEmitter")
				e.Texture = "rbxasset://textures/particles/smoke_main.dds"
				e.Color = ColorSequence.new(Color3.fromRGB(196, 186, 168))
				e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.4) })
				e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
				e.Lifetime = NumberRange.new(0.5, 0.9)
				e.Speed = NumberRange.new(1, 3)
				e.SpreadAngle = Vector2.new(60, 20)
				e.Drag = 3
				e.Rate = 40
				e.Parent = a
				self.slideDustEmitter = e
			end
			e.Enabled = true
		elseif e then
			e.Enabled = false
		end
	end

	-- the hip height while sliding (the spring under the torso holds it there)
	function Controller:_slideHeight(): number?
		if not self.slide then
			return nil
		end
		return Config.SlideHeight
	end

	-- the whole body leans back along the slide
	function Controller:_slideBalance(): CFrame?
		local sl = self.slide
		if not sl then
			return nil
		end
		return CFrame.lookAt(Vector3.zero, sl.dir) * CFrame.Angles(math.rad(Config.SlideLean), 0, 0)
	end

	-- legs (relative to the torso): the lead leg straight out in front, the other one tucked a little and out to the side
	function Controller:_slideLegRel(side: number): CFrame?
		if not self.slide then
			return nil
		end
		local lead = side > 0
		if self.limbs.RightLeg and self.limbs.RightLeg.severed then
			lead = side < 0
		end
		local base = math.rad(90 - Config.SlideLean) -- (level with the floor)
		if lead then
			return CFrame.Angles(base - 0.04, 0, side * 0.04)
		end
		return CFrame.Angles(base - 0.32, 0, side * 0.34)
	end

	-- arms: the left hand trails on the floor behind you, the right one is up for balance (a hand holding something
	-- keeps doing its job - you can shoot while you slide)
	function Controller:_slideArmAim(side: string, shoulder: Vector3, heading: CFrame): Vector3?
		local sl = self.slide
		if not sl or self.hands[side].grip then
			return nil
		end
		local right = sl.dir:Cross(Vector3.yAxis)
		local p: Vector3
		if side == "Left" then
			p = self.torso.Position - sl.dir * 1.2 - right * 1.3 + Vector3.new(0, -2.2, 0)
		else
			p = self.torso.Position + sl.dir * 0.6 + right * 1.1 + Vector3.new(0, 1.6, 0)
		end
		return MathUtil.SafeUnit(p - shoulder, heading.LookVector)
	end

	-- the slide tackle: whoever's legs are right in front of your lead foot gets swept off their feet (once each)
	local function tackle(self, sl, speed: number)
		if speed < Config.SlideTackleMinSpeed then
			return
		end
		local L = self.limbs.RightLeg
		if not L or L.severed then
			L = self.limbs.LeftLeg
		end
		if not L or L.severed or not L.part.Parent then
			return
		end
		local foot = L.part.CFrame:PointToWorldSpace(Vector3.new(0, -0.9, 0))
		local probe = foot + sl.dir * 0.9 + Vector3.new(0, 0.4, 0)
		tackleParams.FilterDescendantsInstances = { self.character }
		local seen: { [Model]: BasePart } = {}
		for _, p in workspace:GetPartBoundsInRadius(probe, Config.SlideTackleRadius, tackleParams) do
			local body = bodyOf(p)
			if body and body ~= self.character and not sl.hit[body] and not body:GetAttribute("Dead") then
				-- prefer a leg (that is what you slide into)
				local cur = seen[body]
				if not cur or (string.find(p.Name, "Leg") ~= nil and string.find(cur.Name, "Leg") == nil) then
					seen[body] = p
				end
			end
		end
		for body, part in seen do
			sl.hit[body] = true
			KickRemote:FireServer(part, probe, sl.dir * speed, "slide")
			Cam.Shake(0.25)
			SoundLibrary.Play("bodyHit", probe, 0.8)
		end
	end

	function Controller:_updateSlide(dt: number)
		local sl = self.slide
		if not sl then
			return
		end
		local t = os.clock() - sl.t0
		local state = self.state
		if t >= Config.SlideTime or (state ~= "Standing" and state ~= "Stumbling") or self.flying or self.car or self.dead or (self.groundTime or 0) < 0.02 and t > 0.25 then
			self:_endSlide()
			return
		end
		local k = 1 - t / Config.SlideTime
		local speed = Config.SlideEndSpeed + (sl.v0 - Config.SlideEndSpeed) * (k ^ 1.25)
		sl.speed = speed
		-- (sliding over the floor is not a crash: the impact sensor stays quiet)
		self.suppressImpacts = math.max(self.suppressImpacts or 0, os.clock() + 0.2)
		if sl.loop then
			sl.loop.PlaybackSpeed = 0.8 + math.clamp(speed / Config.SlideMaxSpeed, 0, 1) * 0.5
			sl.loop.Volume = 0.25 + math.clamp(speed / Config.SlideMaxSpeed, 0, 1) * 0.6
		end
		-- a little steering with the move keys
		local mv = Input.GetMoveVector()
		if mv.Magnitude > 0.1 then
			local look = MathUtil.Flat(Cam.LookVector())
			local right = look:Cross(Vector3.yAxis)
			local want = MathUtil.SafeUnit(look * -mv.Z + right * mv.X, sl.dir)
			sl.dir = sl.dir:Lerp(want, math.min(1, dt * 1.6)).Unit
		end
		-- the whole body glides: every part keeps the slide's speed along the ground
		for _, p in self.character:GetDescendants() do
			if p:IsA("BasePart") and not p.Anchored then
				local v = p.AssemblyLinearVelocity
				p.AssemblyLinearVelocity = Vector3.new(sl.dir.X * speed, v.Y, sl.dir.Z * speed)
			end
		end
		tackle(self, sl, speed)
	end
end
