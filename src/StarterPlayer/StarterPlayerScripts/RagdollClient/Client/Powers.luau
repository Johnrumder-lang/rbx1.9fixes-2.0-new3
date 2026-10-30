--!nonstrict
-- Powers (mixin for CharacterController): what only the game owner can do.
--   L  SUPER PUNCH: you shoot forward (where the camera looks) with your fist out. Whatever the
--      fist meets flies away: people (huge damage), props, cars, bricks, glass.
--   K (hold, only while flying)  LASER EYES: two red beams from your eyes to the crosshair. They
--      burn people, set things on fire, melt glass and bricks.
-- The server checks that you are the owner (and flying, for the eyes) and does the damage; the
-- beams of every owner are drawn by LaserFX on every screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))
local Items = require(Shared:WaitForChild("Items"))

local AdminRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Admin") :: RemoteEvent

local Modules = script.Parent
local Input = require(Modules:WaitForChild("Input"))
local Cam = require(Modules:WaitForChild("CameraController"))

local player = Players.LocalPlayer

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

local punchParams = OverlapParams.new()
punchParams.FilterType = Enum.RaycastFilterType.Exclude

local laserParams = RaycastParams.new()
laserParams.FilterType = Enum.RaycastFilterType.Exclude

return function(Controller)
	function Controller:_superPunch()
		if self.dead or self.car or self.passenger or not Items.Has(player, "punch") or self:IsAsleep() then
			return
		end
		local s = self.state
		if s == "Ragdoll" or s == "Tumble" or s == "Dead" then
			return
		end
		local now = os.clock()
		if now < (self.punchCD or 0) then
			return
		end
		self.punchCD = now + Config.SuperPunchCooldown
		local look = Cam.LookVector()
		local dir = self.flying and look or MathUtil.SafeUnit(MathUtil.Flat(look) + Vector3.new(0, 0.06, 0), self.torso.CFrame.LookVector)
		self.superPunch = { t0 = now, dir = dir, hit = {} }
		if not self.flying then
			AdminRemote:FireServer("punchsafe") -- (v1.9: no damage, nothing torn off, for the dash + a second)
		end
		SoundLibrary.Play("dropKickWhoosh", self.torso, 1)
		Cam.Shake(0.5)
	end

	-- the right arm shoots out along the punch
	function Controller:_punchAim(side: string): Vector3?
		local sp = self.superPunch
		if sp and side == "Right" then
			return sp.dir
		end
		return nil
	end

	local function stopLaser(self)
		if self.laserOn then
			self.laserOn = false
			AdminRemote:FireServer("laser", false)
		end
		if self.laserSound then
			self.laserSound:Destroy()
			self.laserSound = nil
		end
	end

	function Controller:_updatePowers(_dt: number)
		local now = os.clock()
		-- super punch: the dash and the hits
		local sp = self.superPunch
		if sp then
			if now - sp.t0 > Config.SuperPunchTime or self.dead then
				self.superPunch = nil
			else
				self:_flySetVelocity(sp.dir * Config.SuperPunchSpeed)
				local center = self.torso.Position + sp.dir * 2.8
				local ignore: { Instance } = { self.character }
				local fx = workspace:FindFirstChild("FX")
				if fx then
					table.insert(ignore, fx)
				end
				for _, side in { "Left", "Right" } do
					local g = self.hands[side].grip
					if g and g.item then
						table.insert(ignore, g.item)
					end
				end
				punchParams.FilterDescendantsInstances = ignore
				local hitBody = false
				for _, p in workspace:GetPartBoundsInBox(CFrame.lookAt(center, center + sp.dir), Vector3.new(4.5, 5.5, 4), punchParams) do
					if not p.CanCollide and not bodyOf(p) then
						continue
					end
					local body = bodyOf(p)
					local key: Instance = body or p.AssemblyRootPart or p
					if sp.hit[key] then
						continue
					end
					if p.Anchored and not (p:GetAttribute("Destructible") or p.Material == Enum.Material.Glass) then
						continue
					end
					sp.hit[key] = true
					AdminRemote:FireServer("punch", p, sp.dir)
					if body then
						hitBody = true
					end
				end
				if hitBody then
					-- the fist landed: the dash stops there
					self.superPunch = nil
					self:_flySetVelocity(sp.dir * 12)
					SoundLibrary.Play("punchBoom", center, 1)
					Cam.Shake(1.4)
				end
			end
		end

		-- laser eyes (owner, flying, K held)
		local want = Input.laserHeld and self.flying and not self.dead and not Input.menuOpen and Items.Has(player, "laser")
		if not want then
			stopLaser(self)
			self.laserTarget = nil
			return
		end
		local head = self.head
		if not head or not head.Parent then
			stopLaser(self)
			return
		end
		local from = head.Position
		local aim = self:_crosshairPoint()
		local ignore: { Instance } = { self.character }
		local fx = workspace:FindFirstChild("FX")
		if fx then
			table.insert(ignore, fx)
		end
		laserParams.FilterDescendantsInstances = ignore
		local to = aim - from
		if to.Magnitude > Config.LaserEyesRange then
			to = to.Unit * Config.LaserEyesRange
		end
		local hit = workspace:Raycast(from, to, laserParams)
		local target = hit and hit.Position or (from + to)
		self.laserTarget = target
		if not self.laserOn then
			self.laserOn = true
			local snd = SoundLibrary.Loop("laserEyes", head)
			if snd then
				snd.Volume = 0.5
				snd:Play()
			end
			self.laserSound = snd
		end
		if now - (self.laserSent or 0) > 0.08 then
			self.laserSent = now
			AdminRemote:FireServer("laser", target)
		end
	end
end
