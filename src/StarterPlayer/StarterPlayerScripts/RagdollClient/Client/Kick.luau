--!nonstrict
-- Kick (mixin for CharacterController): C = a kick with a random leg (left or right).
--   wind-up (leg back) -> strike (leg swings forward and up, strong muscle) -> back down.
--   In the air (jump, then C): a DROP KICK - you fly forward feet first, both legs out, and
--   land on your back. Whoever you hit flies.
--   The foot hurts and knocks over people it hits (the server checks and applies it), pushes
--   loose things (props, grenades, barrels, bodies lying around) and kicks stuff on the ground.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))

local KickRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Kick") :: RemoteEvent

local Modules = script.Parent
local Cam = require(Modules:WaitForChild("CameraController"))

local rng = Random.new()

local KICK_STATES = { Standing = true, Stumbling = true, Airborne = true }

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

return function(Controller)
	function Controller:_dropKick(legs: { string })
		local look = MathUtil.SafeUnit(MathUtil.Flat(Cam.LookVector()), self.torso.CFrame.LookVector)
		self.kick = { leg = "Both", legs = legs, drop = true, t0 = os.clock(), dir = look, hit = {} }
		local tk = self.slowK or 1 -- (v2.8.1) in somebody's Sandevistan the drop kick is slow too (it shot you far away)
		local function launch(part: BasePart)
			local cur = part.AssemblyLinearVelocity
			local target = Vector3.new(look.X * Config.DropKickSpeed * tk, math.max(cur.Y, 0) + 9 * tk, look.Z * Config.DropKickSpeed * tk)
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
		self.suppressImpacts = math.max(self.suppressImpacts, os.clock() + 0.3)
		self:_setState("DropKick")
		SoundLibrary.Play("dropKickWhoosh", self.torso, 1)
	end

	function Controller:_kick()
		local now = os.clock()
		if self.kick and now - self.kick.t0 < (self.kick.drop and Config.DropKickTime or Config.KickTime) + 0.08 then
			return
		end
		if not KICK_STATES[self.state] or self.car then
			return
		end
		-- a random leg that still works
		local legs = {}
		for _, k in { "LeftLeg", "RightLeg" } do
			local L = self.limbs[k]
			if L and not L.severed and not L.broken then
				table.insert(legs, k)
			end
		end
		if #legs == 0 then
			return
		end
		-- off the ground (jumping): drop kick
		if self.state == "Airborne" and not self.grounded and self.airTime > 0.06 then
			-- (v2.0) a drop kick needs a breather before the next one
			if now - (self.lastDropKick or -100) < Config.DropKickCooldown then
				return
			end
			self.lastDropKick = now
			self:_dropKick(legs)
			return
		end
		local leg = legs[rng:NextInteger(1, #legs)]
		local look = MathUtil.SafeUnit(MathUtil.Flat(Cam.LookVector()), self.torso.CFrame.LookVector)
		self.kick = { leg = leg, t0 = now, dir = look, hit = {} }
		SoundLibrary.Play("kickSwoosh", self.torso, 0.9)
	end

	-- the angle the kicking leg swings forward (radians) over the kick
	function Controller:_kickAngle(kk, now: number): number
		local t = now - kk.t0
		if t < 0.1 then
			return -0.55 * (t / 0.1) -- wind up: leg back
		elseif t < 0.22 then
			local k = (t - 0.1) / 0.12
			return -0.55 + (1.55 + 0.55) * k * k * (3 - 2 * k) -- strike: forward and up
		elseif t < 0.3 then
			return 1.55
		end
		local k = math.clamp((t - 0.3) / (Config.KickTime - 0.3), 0, 1)
		return 1.55 * (1 - k)
	end

	-- leg target while kicking (nil = not this leg)
	function Controller:_kickRel(key: string, invTorso: CFrame, side: number): CFrame?
		local kk = self.kick
		if kk and kk.drop then
			if not table.find(kk.legs, key) or self.state ~= "DropKick" then
				return nil
			end
			-- both feet forward (a quick tuck first), a little apart
			local t = os.clock() - kk.t0
			local a = t < 0.09 and 0.9 + 6 * t or 1.45
			local heading = CFrame.lookAt(Vector3.zero, kk.dir)
			local world = heading * CFrame.fromAxisAngle(Vector3.xAxis, a) * CFrame.Angles(0, 0, side * 0.12)
			return invTorso * world.Rotation
		end
		if not kk or kk.leg ~= key then
			return nil
		end
		local now = os.clock()
		if now - kk.t0 > Config.KickTime then
			return nil
		end
		local heading = CFrame.lookAt(Vector3.zero, kk.dir)
		local world = heading * CFrame.fromAxisAngle(Vector3.xAxis, self:_kickAngle(kk, now)) * CFrame.Angles(0, 0, side * 0.05)
		return invTorso * world.Rotation
	end

	-- a foot touched something: tell the server (it checks and hurts / pushes)
	local function strike(self, kk, L, style: string?)
		local foot = L.part.CFrame:PointToWorldSpace(Vector3.new(0, -0.9, 0))
		local footVel = L.part:GetVelocityAtPosition(foot)
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.RespectCanCollide = false
		local fx = workspace:FindFirstChild("FX")
		params.FilterDescendantsInstances = fx and { self.character, fx } or { self.character }
		local hitBody = false
		for _, p in workspace:GetPartBoundsInRadius(foot, style == "drop" and 1.4 or 1.0, params) do
			-- (v1.9) a drop kick goes through window glass: the pane is not solid for you any more at once, the
			-- server shatters it
			local glass = style == "drop" and p.Material == Enum.Material.Glass and p.Transparency < 0.98
			if (p.Anchored and not glass) or p:GetAttribute("Gore") then
				continue
			end
			if glass then
				p.CanCollide = false
			end
			local body = bodyOf(p)
			local key = body or p.AssemblyRootPart or p
			if kk.hit[key] then
				continue
			end
			kk.hit[key] = true
			local speed = math.max(footVel.Magnitude, 12)
			local v = style == "drop" and kk.dir * math.max(speed, Config.DropKickSpeed) or (kk.dir * speed + Vector3.new(0, speed * 0.3, 0))
			KickRemote:FireServer(p, foot, v, style)
			SoundLibrary.Play(body and (style == "drop" and "dropKick" or "punch") or "thud", foot, 1)
			Cam.Shake(body and (style == "drop" and 0.7 or 0.35) or 0.15)
			if body then
				hitBody = true
			end
		end
		return hitBody
	end

	function Controller:_updateKick(_dt: number)
		local kk = self.kick
		if not kk then
			return
		end
		local now = os.clock()
		if kk.drop then
			if self.state ~= "DropKick" or now - kk.t0 > Config.DropKickTime or self.dead then
				self.kick = nil
				self.legCollide = nil
				return
			end
			for _, key in kk.legs do
				local L = self.limbs[key]
				if L and not L.severed and L.part.Parent then
					if L.collider and L.collider.Parent then
						L.collider.CanCollide = true
					end
					if now - kk.t0 > 0.05 and strike(self, kk, L, "drop") and not kk.bounced then
						-- you bounce off the one you hit
						kk.bounced = true
						pcall(function()
							for _, part in { self.torso, L.part } do
								part:ApplyImpulse(-kk.dir * 18 * (self.slowK or 1) * part.AssemblyMass)
							end
						end)
					end
				end
			end
			return
		end
		local L = self.limbs[kk.leg]
		if now - kk.t0 > Config.KickTime or not L or L.severed or self.dead then
			self.kick = nil
			self.legCollide = nil -- (re-applied by _setLegCollision next frame)
			return
		end
		-- the kicking leg is solid while it kicks
		if L.collider and L.collider.Parent then
			L.collider.CanCollide = true
		end
		local t = now - kk.t0
		if t < 0.1 or t > 0.32 then
			return
		end
		-- a little push forward with the kick
		if not kk.pushed then
			kk.pushed = true
			pcall(function()
				L.part:ApplyImpulse(kk.dir * 22 * (self.slowK or 1) * L.part.AssemblyMass)
			end)
		end
		strike(self, kk, L, nil)
	end
end
