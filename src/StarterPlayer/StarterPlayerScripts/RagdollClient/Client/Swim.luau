--!nonstrict
-- Swim (mixin for CharacterController): the pool.
--   In deep water you swim: WASD swim where you look (flat), Space swims up (at the surface it
--   keeps your head out of the water), Ctrl dives. Let go of everything and you slowly sink.
--   With both legs or both arms gone you cannot swim at all: you go down.
--   Stay under too long and you drown (the server counts and hurts; there is no meter: the picture
--   just gets darker and closes in). Under water everything sounds dull; bubbles come out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))
local Water = require(Shared:WaitForChild("Water"))

local Modules = script.Parent
local Input = require(Modules:WaitForChild("Input"))

local rng = Random.new()

return function(Controller)
	function Controller:_canSwim(): boolean
		local function gone(key: string): boolean
			local L = self.limbs[key]
			return L == nil or L.severed
		end
		local noLegs = gone("LeftLeg") and gone("RightLeg")
		local noArms = gone("LeftArm") and gone("RightArm")
		return not (noLegs or noArms)
	end

	function Controller:_updateWater(dt: number)
		local torso = self.torso
		local surf = Water.SurfaceAt(torso.Position)
		self.waterSurf = surf
		local was = self.swimming
		self.swimming = surf ~= nil
			and torso.Position.Y < surf - 0.5
			and not self.car
			and not self.passenger
			and not self.flying
			and not self.dead
		self.canSwim = self:_canSwim()
		if self.swimming then
			-- hitting water is not hitting the ground
			self.suppressImpacts = math.max(self.suppressImpacts, os.clock() + 0.4)
			if not was then
				self.swimI = 0
				SoundLibrary.Play("swim", torso, 0.8)
			end
		end
		-- head under water: count (the server does the real counting and the drowning)
		local head = self.head
		local under = surf ~= nil and head ~= nil and head.Parent ~= nil and head.Position.Y < surf - 0.2 and not self.dead
		local now = os.clock()
		-- (v2.8) DEEPWATER LUNGS: more breath (0 = never drowns)
		local lungs = self.character and self.character:GetAttribute("CyLungs")
		local drownT = Config.DrownTime * ((typeof(lungs) == "number" and lungs > 0) and lungs or 1)
		if lungs == 0 then
			drownT = math.huge
		end
		if under then
			self.underTime = (self.underTime or 0) + dt
			if now > (self.nextBubble or 0) then
				self.nextBubble = now + rng:NextNumber(0.4, 1.1) * (self.underTime > drownT and 0.4 or 1)
				SoundLibrary.Play(self.underTime > drownT and "gurgle" or "bubbles", head, 0.6)
				if self.onBubbles then
					self.onBubbles(head.Position)
				end
			end
		else
			self.underTime = math.max(0, (self.underTime or 0) - dt * 4)
		end
		if self.onDrown then
			local t = self.underTime or 0
			self.onDrown(drownT == math.huge and 0 or math.clamp((t - drownT * 0.35) / (drownT * 0.65 + Config.DrownDeathTime), 0, 1))
		end
		-- the camera under water: everything sounds dull
		local cam = workspace.CurrentCamera
		local camUnder = cam ~= nil and (Water.Depth(cam.CFrame.Position) or -1) > 0
		if camUnder ~= self.camUnder then
			self.camUnder = camUnder
			SoundLibrary.SetUnderwater(camUnder)
		end
		-- swimming strokes
		if self.swimming and self.canSwim and now > (self.nextStroke or 0) then
			local moving = MathUtil.Flat(torso.AssemblyLinearVelocity).Magnitude > 3 or Input.jumpHeld
			if moving then
				self.nextStroke = now + 0.9
				SoundLibrary.Play("swim", torso, 0.35)
			end
		end
	end

	-- force on the torso + its orientation while swimming
	function Controller:_swimForces(dt: number, moveWorld: Vector3, heading: CFrame): (Vector3, CFrame)
		local torso = self.torso
		local M = self.bodyMass
		local g = workspace.Gravity
		local vel = torso.AssemblyLinearVelocity
		local vh = MathUtil.Flat(vel)
		local surf = self.waterSurf or torso.Position.Y
		local head = self.head
		local headY = (head and head.Parent) and head.Position.Y or (torso.Position.Y + 1.5)
		local vyWant: number
		local speed = Input.Running() and Config.SwimSprintSpeed or Config.SwimSpeed
		if not self.canSwim then
			vyWant = -Config.SinkSpeedHelpless
			speed *= 0.15
		elseif Input.jumpHeld and not Input.menuOpen then
			-- up; at the top the head stays just above the water
			vyWant = math.clamp((surf + 0.7 - headY) * 4, -3, Config.SwimUpSpeed)
		elseif Input.downHeld and not Input.menuOpen then
			vyWant = -Config.SwimUpSpeed * 0.7
		else
			vyWant = -Config.SinkSpeed
		end
		-- (the water lifts the body by an amount we do not know exactly: an integral term finds it)
		local err = vyWant - vel.Y
		self.swimI = math.clamp((self.swimI or 0) + err * Config.SwimKi * dt, -g * 1.5, g * 1.5)
		local fy = M * (err * Config.SwimKp + self.swimI)
		fy = math.clamp(fy, -M * g * 2.5, M * g * 2.5)
		local desired = moveWorld * speed
		local fh = MathUtil.ClampMagnitude((desired - vh) * 3 * M, M * 40)
		-- lying flat while swimming forward, upright while treading water
		local k = math.clamp(vh.Magnitude / Config.SwimSpeed, 0, 1)
		local face = vh.Magnitude > 1.5 and vh.Unit or heading.LookVector
		local pitch = -math.rad(70) * k
		if not self.canSwim then
			pitch = math.sin(self.time * 3) * 0.4
		end
		return Vector3.new(fh.X, fy, fh.Z), CFrame.lookAt(Vector3.zero, face) * CFrame.Angles(pitch, 0, 0)
	end

	-- limb targets while swimming (relative to the torso)
	function Controller:_swimPose(isLeg: boolean, side: number): CFrame
		local t = self.time
		local moving = MathUtil.Flat(self.torso.AssemblyLinearVelocity).Magnitude > 2 or Input.jumpHeld
		if not self.canSwim then
			-- helpless: flailing
			return CFrame.Angles(1.2 * math.sin(t * 7 + side), 0, side * (0.8 + 0.4 * math.sin(t * 5)))
		end
		if isLeg then
			return CFrame.Angles((moving and 0.35 or 0.2) * math.sin(t * (moving and 9 or 5) + side * 1.6), 0, side * 0.14)
		end
		if moving then
			-- breaststroke: reach forward, sweep out and back
			local ph = t * 3.4
			return CFrame.Angles(2.3 + 0.7 * math.sin(ph), 0, side * (0.5 + 0.6 * math.max(0, math.cos(ph))))
		end
		-- treading water
		return CFrame.Angles(1.1 + 0.35 * math.sin(t * 4 + side), 0, side * (0.9 + 0.25 * math.sin(t * 4)))
	end
end
