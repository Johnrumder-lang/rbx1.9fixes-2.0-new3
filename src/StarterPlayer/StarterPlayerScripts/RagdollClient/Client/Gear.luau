--!nonstrict
-- Gear (v2.0, mixin for CharacterController): the new things in your hands, and your fists.
--   fists       : both hands empty, F = a punch (left, right, left ...). The hands stay up in a guard for a moment.
--   weave       : Left Alt = slip to the side. For a moment punches, kicks and swings miss you, and a punch right
--                 after it is a counter (hits harder).
--   flashlight  : F = on / off
--   glue        : F on a thing (crosshair, close) = a coat of glue; F on another thing = the lighter one is pulled
--                 onto the heavier one, glued sides tight together
--   prosthetics : F = fit it. To your own missing arm / leg, or point at somebody who misses one. It takes
--                 Config.ProstheticTime seconds with the hand working at the stump; walking away or falling stops it.
--   harpoon gun : F fires; while the line is out, hold F = reel in
--   lock-on     : hold G = the seeker. Keep a vehicle in the box: amber = locking, green = LOCKED; then F
--   taser       : who is hit lies there twitching (_tased)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))

local Modules = script.Parent
local Input = require(Modules:WaitForChild("Input"))
local Cam = require(Modules:WaitForChild("CameraController"))
local SteelBallFX = require(Modules:WaitForChild("SteelBallFX"))
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ItemRemote = Remotes:WaitForChild("Item") :: RemoteEvent
local KickRemote = Remotes:WaitForChild("Kick") :: RemoteEvent
-- (v2.9) the cyberdeck remote (ChipService / CameraService make it at startup)
local chipRemote: RemoteEvent? = nil
local function ChipRemote(): RemoteEvent?
	if not chipRemote then
		chipRemote = Remotes:FindFirstChild("Chip") :: RemoteEvent
	end
	return chipRemote
end

local player = Players.LocalPlayer
local rng = Random.new()

local SIDES = { "Left", "Right" }
local ARM_OF = { Left = "LeftArm", Right = "RightArm" }
local FIST_STATES = { Standing = true, Stumbling = true, Airborne = true }
local LIMB_KEYS = { Arm = { "LeftArm", "RightArm" }, Leg = { "LeftLeg", "RightLeg" } }

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
	----------------------------------------------------------------------
	-- fists
	----------------------------------------------------------------------

	function Controller:_fistsReady(): boolean
		if self.car or self.passenger or self.dead or self.flying or not FIST_STATES[self.state] then
			return false
		end
		for _, side in SIDES do
			if self.hands[side].grip then
				return false
			end
		end
		return self:_limbUsable("LeftArm") or self:_limbUsable("RightArm")
	end

	function Controller:_punch()
		local now = os.clock()
		if now < (self.fistReady or 0) then
			return
		end
		local side = self.nextFist or "Right"
		if not self:_limbUsable(ARM_OF[side]) then
			side = side == "Left" and "Right" or "Left"
		end
		if not self:_limbUsable(ARM_OF[side]) then
			return
		end
		local L = self.limbs[ARM_OF[side]]
		local shoulder = self.torso.CFrame:PointToWorldSpace(L.def.torsoPivot)
		local dir = self:_aimDir(side, shoulder)
		self.fist = { side = side, t0 = now, dir = dir, hit = {}, pushed = false }
		self.fistReady = now + Config.FistCooldown
		self.guardUntil = now + 1.6
		self.nextFist = side == "Left" and "Right" or "Left"
		SoundLibrary.Play("kickSwoosh", self.torso, 0.6, 1.25)
	end

	-- Left Alt
	function Controller:_weave()
		local now = os.clock()
		if now < (self.weaveReady or 0) or self.car or self.dead or self.flying then
			return
		end
		local s = self.state
		if s ~= "Standing" and s ~= "Stumbling" then
			return
		end
		-- slip away from where you move, or alternate
		local mv = Input.GetMoveVector()
		local dir = mv.X > 0.3 and 1 or (mv.X < -0.3 and -1 or ((self.weaveSide or 1) * -1))
		self.weaveSide = dir
		self.weave = { t0 = now, side = dir }
		self.weaveReady = now + Config.WeaveCooldown
		self.guardUntil = math.max(self.guardUntil or 0, now + 1)
		KickRemote:FireServer("weave")
		SoundLibrary.Play("weave", self.torso, 0.8)
		-- (v2.0) a little burst of speed the way you press (W A S D, seen from the camera); no key: to the side
		local push: Vector3
		if mv.Magnitude > 0.2 then
			local flat = CFrame.Angles(0, Cam.yaw, 0)
			push = flat:VectorToWorldSpace(Vector3.new(mv.X, 0, mv.Z)).Unit
		else
			push = self.torso.CFrame.RightVector * dir
			push = Vector3.new(push.X, 0, push.Z)
			push = push.Magnitude > 0.05 and push.Unit or Vector3.zero
		end
		pcall(function()
			local seen = {}
			for _, p in self.character:GetChildren() do
				local r = p:IsA("BasePart") and p.AssemblyRootPart or nil
				if r and not seen[r] then
					seen[r] = true
					r:ApplyImpulse(push * Config.WeaveDash * (self.slowK or 1) * r.AssemblyMass) -- (v2.8.1: slow in a Sandevistan)
				end
			end
		end)
	end

	-- the body dips and leans while weaving (pitch, roll added to the balance target)
	function Controller:_weaveLean(): (number, number)
		local w = self.weave
		if not w then
			return 0, 0
		end
		local t = (os.clock() - w.t0) / Config.WeaveTime
		if t >= 1 then
			self.weave = nil
			return 0, 0
		end
		local k = math.sin(math.pi * t)
		return -math.rad(20) * k, -w.side * math.rad(30) * k
	end

	function Controller:_prostheticSpeed(): number
		local k = 1
		local char = self.character
		for _, key in LIMB_KEYS.Leg do
			if char:GetAttribute("Prosthetic_" .. key) then
				k *= Config.ProstheticLegSpeed
			end
		end
		return k
	end

	----------------------------------------------------------------------
	-- (v2.0) steel balls: F = throw. The arm winds up for a moment, then the ball leaves the hand (the server flies
	-- it; SteelBallFX draws it here at once). With the Spin it comes back by itself ("ballcatch").
	----------------------------------------------------------------------

	function Controller:_throwBall(side: string, g)
		local now = os.clock()
		if now < (self.ballReady or 0) or self.ballThrow then
			return
		end
		-- a ball in each hand: right, left, right ... (F asks both hands; the other one waits its turn)
		local want = self.nextBall or "Right"
		if side ~= want then
			local og = self.hands[want].grip
			if og and og.kind == "steelball" then
				return
			end
		end
		self.nextBall = side == "Right" and "Left" or "Right"
		self.ballReady = now + Config.SteelBallCooldown
		local item = g.item
		self.ballThrow = { side = side, t0 = now, item = item, dir = nil }
		task.delay(Config.SteelBallWindup, function()
			local bt = self.ballThrow
			local hg = self.hands[side].grip
			if not bt or bt.item ~= item or not self.alive or self.dead or not hg or hg.item ~= item then
				self.ballThrow = nil
				return
			end
			local origin = hg.part.Position
			local dir = MathUtil.SafeUnit(self:_crosshairPoint() - origin, Cam.LookVector())
			bt.dir = dir
			self:_release(side, false)
			-- (out of sight here until the server puts it back into the world)
			for _, d in item:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 1
				end
			end
			ItemRemote:FireServer("ballthrow", item, origin, dir, side)
			SteelBallFX.LocalThrow(origin, dir * Config.SteelBallSpeed, player:GetAttribute("HasSpin") == true)
			SoundLibrary.Play("steelThrow", origin, 1)
			Cam.Shake(0.1)
		end)
	end

	function Controller:_ballArmAim(side: string, shoulder: Vector3, heading: CFrame): Vector3?
		local bt = self.ballThrow
		if not bt or bt.side ~= side then
			return nil
		end
		local t = os.clock() - bt.t0
		if t > Config.SteelBallWindup + 0.24 then
			self.ballThrow = nil
			return nil
		end
		if t < Config.SteelBallWindup then
			-- wound up: the hand back by the ear
			local sx = side == "Left" and -0.6 or 0.6
			local p = self.torso.Position + Vector3.new(0, 1.7, 0) - heading.LookVector * 0.9 + self.torso.CFrame.RightVector * sx
			return MathUtil.SafeUnit(p - shoulder, heading.LookVector)
		end
		-- the follow-through
		local d = bt.dir or Cam.LookVector()
		return MathUtil.SafeUnit(d - Vector3.new(0, 0.3, 0), d)
	end

	-- (v2.0) hit by a Spin ball: limp, lifted a little and spun around
	function Controller:_spun(duration: number)
		if self.dead or self.car then
			return
		end
		self:Ragdoll(duration + 0.4)
		self.spunUntil = os.clock() + duration
		if self.spinning then
			return
		end
		self.spinning = true
		local y0 = self.torso.Position.Y
		task.spawn(function()
			while self.alive and not self.dead and os.clock() < (self.spunUntil or 0) do
				if not workspace:GetAttribute("TimeStop") then
					pcall(function()
						local v = self.torso.AssemblyLinearVelocity
						self.torso.AssemblyAngularVelocity = Vector3.new(0, Config.SpinVictimSpeed, 0)
						local lift = math.clamp((y0 + Config.SpinVictimLift - self.torso.Position.Y) * 6, -20, 20)
						self.torso.AssemblyLinearVelocity = Vector3.new(v.X * 0.9, lift, v.Z * 0.9)
					end)
				end
				Cam.Shake(0.04)
				RunService.Heartbeat:Wait()
			end
			self.spinning = false
		end)
	end

	-- arm directions for the punch / guard / fitting (nil = not ours)
	function Controller:_gearArmAim(side: string, shoulder: Vector3, heading: CFrame): (Vector3?, boolean?)
		local now = os.clock()
		-- the slide: one hand trails on the floor, the other is up
		local sa = self:_slideArmAim(side, shoulder, heading)
		if sa then
			return sa, false
		end
		-- (v2.0) throwing a steel ball: the arm swings through
		local ta = self:_ballArmAim(side, shoulder, heading)
		if ta then
			return ta, true
		end
		-- (v2.0) the Spin cutscene: the right hand reaches for it
		local reach = self.cutsceneReach
		if reach and side == "Right" then
			return MathUtil.SafeUnit(reach - shoulder, heading.LookVector), true
		end
		-- fitting a prosthetic: the hand works at the stump
		local f = self.fitting
		if f and f.side == side and f.stump then
			local t = now - f.t0
			local p = f.stump + Vector3.new(math.cos(t * 7) * 0.35, math.sin(t * 9) * 0.3, math.sin(t * 7) * 0.35)
			return MathUtil.SafeUnit(p - shoulder, heading.LookVector), true
		end
		local fist = self.fist
		if fist and fist.side == side then
			local t = now - fist.t0
			if t < Config.FistTime then
				if t < 0.05 then
					-- cocked back a little
					local back = self.torso.Position + self.torso.CFrame.UpVector * 1.2 + heading.LookVector * 0.3
					return MathUtil.SafeUnit(back - shoulder, heading.LookVector), true
				end
				return fist.dir, true
			end
			self.fist = nil
		end
		-- (v2.0) bleeding: a free hand presses on the wound by itself
		local wound = self.pressWound
		if wound and wound.side == side and wound.part.Parent then
			local p = wound.part.Position + wound.part.CFrame.LookVector * -0.55
			return MathUtil.SafeUnit(p - shoulder, heading.LookVector), false
		end
		-- (v2.0) a zombie: both arms out in front, reaching
		if self.character:GetAttribute("Zombie") and not self.hands[side].grip and self.state ~= "Ragdoll" then
			local sx = side == "Left" and -0.35 or 0.35
			local p = self.torso.Position + heading.LookVector * 3 + self.torso.CFrame.RightVector * sx + Vector3.new(0, 0.9 + 0.2 * math.sin(now * 3 + sx * 9), 0)
			return MathUtil.SafeUnit(p - shoulder, heading.LookVector), false
		end
		-- the guard: both fists up in front of the face for a moment after punching / weaving
		if (self.guardUntil or 0) > now and self:_fistsReady() then
			local sx = side == "Left" and -1 or 1
			local p = self.torso.Position + heading.LookVector * 1.4 + self.torso.CFrame.UpVector * 1.25 + self.torso.CFrame.RightVector * sx * 0.35
			return MathUtil.SafeUnit(p - shoulder, heading.LookVector), false
		end
		return nil, nil
	end

	local fistParams = OverlapParams.new()
	fistParams.FilterType = Enum.RaycastFilterType.Exclude
	fistParams.RespectCanCollide = false

	local function updateFist(self)
		local fist = self.fist
		if not fist then
			return
		end
		local t = os.clock() - fist.t0
		local L = self.limbs[ARM_OF[fist.side]]
		if not L or L.severed or t > Config.FistTime then
			return
		end
		if t < 0.05 or t > 0.24 then
			return
		end
		if not fist.pushed then
			fist.pushed = true
			pcall(function()
				local tk = self.slowK or 1
				L.part:ApplyImpulse(fist.dir * 30 * tk * L.part.AssemblyMass)
				self.torso:ApplyImpulse(MathUtil.Flat(fist.dir) * 3 * tk * self.torso.AssemblyMass)
			end)
		end
		local hand = L.part.CFrame:PointToWorldSpace(Vector3.new(0, -1, 0))
		local vel = L.part:GetVelocityAtPosition(hand)
		local fx = workspace:FindFirstChild("FX")
		fistParams.FilterDescendantsInstances = fx and { self.character, fx } or { self.character }
		for _, p in workspace:GetPartBoundsInRadius(hand, 0.95, fistParams) do
			if p.Anchored or p:GetAttribute("Gore") then
				continue
			end
			local body = bodyOf(p)
			local key = body or p.AssemblyRootPart or p
			if fist.hit[key] then
				continue
			end
			fist.hit[key] = true
			local v = fist.dir * math.max(vel.Magnitude, 14)
			KickRemote:FireServer(p, hand, v, "punch")
			if body then
				SoundLibrary.Play("punch", hand, 1)
				Cam.Shake(0.25)
			end
		end
	end

	----------------------------------------------------------------------
	-- F on the new gear (true = handled)
	----------------------------------------------------------------------

	-- what the crosshair is on, within `range` studs of the body
	local function crosshairHit(self, range: number): RaycastResult?
		local camera = workspace.CurrentCamera
		local vs = camera.ViewportSize
		local ray = camera:ViewportPointToRay(vs.X * 0.5, vs.Y * 0.5)
		local hit = workspace:Raycast(ray.Origin, ray.Direction * (range + 40), self.rayParams)
		if hit and (hit.Position - self.torso.Position).Magnitude <= range then
			return hit
		end
		return nil
	end

	local function severedKey(model: Model, limbKind: string): string?
		for _, key in LIMB_KEYS[limbKind] do
			if model:GetAttribute("Severed_" .. key) == true then
				return key
			end
		end
		return nil
	end

	function Controller:_useGear(side: string, g, kind: string?): boolean
		if kind == "camera" then
			-- (v2.9) F: start / stop filming
			local r = ChipRemote()
			if r then
				r:FireServer("cam", g.item)
			end
			SoundLibrary.Play("click", g.part, 0.7)
			return true
		elseif kind == "chip" then
			-- (v2.9) F: play the video / push the chip into whoever the other hand is grabbing
			local r = ChipRemote()
			if r then
				local other = side == "Left" and "Right" or "Left"
				local og = self.hands[other] and self.hands[other].grip
				local grabbingPlayer = og ~= nil and (og.playerBody == true or og.remoteBody == true or og.puppet == true)
				r:FireServer(grabbingPlayer and "insert" or "play", g.item)
			end
			SoundLibrary.Play("click", g.part, 0.6)
			return true
		elseif kind == "steelball" then
			self:_throwBall(side, g)
			return true
		elseif kind == "flashlight" then
			ItemRemote:FireServer("use", g.item)
			return true
		elseif kind == "chainsaw" then
			-- (v2.0) F starts / stops the motor (it cuts by itself while it runs: Hands _updateMelee)
			ItemRemote:FireServer("use", g.item)
			SoundLibrary.Play(g.item:GetAttribute("SawOn") and "chainsawStop" or "chainsawStart", g.part, 0.9)
			return true
		elseif kind == "glue" then
			local hit = crosshairHit(self, Config.GlueRange)
			if hit then
				ItemRemote:FireServer("glue", g.item, hit.Instance, hit.Position, hit.Normal)
				SoundLibrary.Play("glue", hit.Position, 0.7)
			else
				SoundLibrary.Play("dryfire", g.part, 0.4)
			end
			return true
		elseif kind == "sandevistan" or kind == "armor" then
			-- (v2.1) the implant goes into SOMEBODY ELSE (aim at them, close by); the armor goes on YOU. Same bar, same range as a prosthetic.
			if self.fitting then
				return true
			end
			local target = self.character
			local key = "Armor"
			local duration = Config.ArmorEquipTime
			if kind == "sandevistan" then
				key, duration = "Sandevistan", Config.SandevistanImplantTime
				local hit = crosshairHit(self, Config.ProstheticRange)
				local body = hit and bodyOf(hit.Instance)
				if not body or body == self.character or body:GetAttribute("Dead") or body:GetAttribute("Sandevistan") then
					SoundLibrary.Play("dryfire", g.part, 0.4)
					return true -- (nobody to aim at: someone else has to implant it)
				end
				target = body
			end
			self.fitting = { t0 = os.clock(), item = g.item, target = target, key = key, side = side, duration = duration }
			ItemRemote:FireServer("fitstart", g.item, target, key)
			SoundLibrary.Play("ratchet", g.part, 0.8)
			return true
		elseif kind == "syringe" then
			-- (v2.8) into somebody close: they sleep a long time
			local hit = crosshairHit(self, Config.SyringeRange)
			local body = hit and bodyOf(hit.Instance)
			if not body or body == self.character or body:GetAttribute("Dead") then
				SoundLibrary.Play("dryfire", g.part, 0.4)
				if Controller.OnCyberHint then
					Controller.OnCyberHint("Aim at somebody close.")
				end
				return true
			end
			ItemRemote:FireServer("syringe", g.item, body)
			SoundLibrary.Play("click", g.part, 0.9)
			return true
		elseif kind == "implantcase" or kind == "ripperkit" then
			-- (v2.8) cyberware: always into / out of SOMEBODY ELSE (aim at them, close by). A ripper kit needs them asleep and
			-- asks which implant comes out.
			if self.fitting then
				return true
			end
			local hit = crosshairHit(self, Config.ProstheticRange)
			local body = hit and bodyOf(hit.Instance)
			if not body or body == self.character or body:GetAttribute("Dead") or not game:GetService("Players"):GetPlayerFromCharacter(body) then
				SoundLibrary.Play("dryfire", g.part, 0.4)
				if Controller.OnCyberHint then
					Controller.OnCyberHint(kind == "implantcase" and "Aim at somebody close: they get the implant." or "Aim at somebody close who is asleep.")
				end
				return true
			end
			local function start(key: string)
				if self.fitting or not g.item.Parent then
					return
				end
				self.fitting = { t0 = os.clock(), item = g.item, target = body, key = key, side = side, duration = Config.CyberFitTime }
				ItemRemote:FireServer("fitstart", g.item, body, key)
				SoundLibrary.Play("ratchet", g.part, 0.8)
			end
			if kind == "implantcase" then
				start("Cyber")
			else
				if body:GetAttribute("Asleep") ~= true then
					if Controller.OnCyberHint then
						Controller.OnCyberHint("They have to be asleep (sleep dart, syringe).")
					end
					return true
				end
				if Controller.OnPickImplant then
					Controller.OnPickImplant(body, function(implantKey: string)
						start("Uncyber:" .. implantKey)
					end)
				end
			end
			return true
		elseif kind == "prosthetic_arm" or kind == "prosthetic_leg" then
			if self.fitting then
				return true
			end
			local limbKind = kind == "prosthetic_arm" and "Arm" or "Leg"
			local target, key = nil, nil
			key = severedKey(self.character, limbKind)
			if key then
				target = self.character
			else
				local hit = crosshairHit(self, Config.ProstheticRange)
				local body = hit and bodyOf(hit.Instance)
				if body and body ~= self.character and not body:GetAttribute("Dead") then
					key = severedKey(body, limbKind)
					target = key and body or nil
				end
			end
			if not target or not key then
				SoundLibrary.Play("dryfire", g.part, 0.4)
				return true
			end
			-- you cannot fit an arm to yourself with the only arm you have... unless it is the other one
			self.fitting = { t0 = os.clock(), item = g.item, target = target, key = key, side = side }
			ItemRemote:FireServer("fitstart", g.item, target, key)
			SoundLibrary.Play("ratchet", g.part, 0.8)
			return true
		end
		return false
	end

	local function updateFitting(self)
		local f = self.fitting
		if not f then
			return
		end
		local g = self.hands[f.side].grip
		local tt = f.target:FindFirstChild("Torso")
		local special = f.key == "Sandevistan" or f.key == "Armor" or f.key == "Cyber" or string.sub(f.key, 1, 8) == "Uncyber:"
		local ok = g and g.item == f.item and f.target.Parent and tt and not f.target:GetAttribute("Dead")
			and (special or f.target:GetAttribute("Severed_" .. f.key) == true) and self.state ~= "Ragdoll" and not self.dead
			and (tt.Position - self.torso.Position).Magnitude <= Config.ProstheticRange + 2
		if ok and f.key == "Sandevistan" and f.target:GetAttribute("Sandevistan") == true then
			ok = false
		end
		if not ok then
			self.fitting = nil
			ItemRemote:FireServer("fitcancel", f.item)
			return
		end
		if f.key == "Sandevistan" or f.key == "Cyber" or string.sub(f.key, 1, 8) == "Uncyber:" then
			f.stump = tt.CFrame:PointToWorldSpace(Vector3.new(0, 0.4, 0.55)) -- (the hand works at the back, on the spine)
		elseif f.key == "Armor" then
			f.stump = tt.CFrame:PointToWorldSpace(Vector3.new(0, 0.2, -0.6)) -- (at your own chest)
		else
			local def = RigInfo.ByKey[f.key]
			f.stump = tt.CFrame:PointToWorldSpace(def.torsoPivot + (def.kind == "Arm" and Vector3.new(def.side * 0.3, 0, 0) or Vector3.new(0, -0.3, 0)))
		end
		local now = os.clock()
		if now - (f.lastSound or 0) > 0.7 then
			f.lastSound = now
			SoundLibrary.Play(rng:NextNumber() < 0.5 and "ratchet" or "click", tt, 0.6)
		end
		if now - f.t0 >= (f.duration or Config.ProstheticTime) then
			self.fitting = nil
			ItemRemote:FireServer("fitdone", f.item)
		end
	end

	-- 0..1 while fitting a prosthetic (HUD)
	function Controller:GetFitProgress(): number?
		local f = self.fitting
		if not f then
			return nil
		end
		return math.clamp((os.clock() - f.t0) / (f.duration or Config.ProstheticTime), 0, 1)
	end

	----------------------------------------------------------------------
	-- harpoon: hold F to reel in
	----------------------------------------------------------------------

	local function updateHarpoon(self)
		if not Input.useHeld or Input.menuOpen then
			return
		end
		for _, side in SIDES do
			local g = self.hands[side].grip
			if g and g.kind == "harpoon" and g.item:GetAttribute("LineOut") then
				local now = os.clock()
				if now - (self.reelSent or 0) > 0.1 then
					self.reelSent = now
					ItemRemote:FireServer("reel", g.item)
				end
				if now - (self.reelSound or 0) > 0.3 then
					self.reelSound = now
					SoundLibrary.Play("reel", g.part, 0.8)
				end
			end
		end
	end

	----------------------------------------------------------------------
	-- lock-on launcher: the seeker
	----------------------------------------------------------------------

	local losParams = RaycastParams.new()
	losParams.FilterType = Enum.RaycastFilterType.Exclude

	local function updateLock(self, dt: number)
		local gun = nil
		for _, side in SIDES do
			local g = self.hands[side].grip
			if g and g.kind == "lockon" then
				gun = g.item
			end
		end
		if not gun or not self.aiming then
			if self.lock then
				self.lock = nil
			end
			Cam.fovOverride = nil
			return
		end
		Cam.fovOverride = Config.LockonFOV
		local camera = workspace.CurrentCamera
		local camCF = camera.CFrame
		local best, bestAng = nil, math.rad(Config.LockonCone)
		-- (v2.0) vehicles, people, bots and creatures can all be locked
		local function consider(root: BasePart, model: Instance)
			local to = root.Position - camCF.Position
			local dist = to.Magnitude
			if dist > 8 and dist <= Config.LockonRange then
				local ang = math.acos(math.clamp(to.Unit:Dot(camCF.LookVector), -1, 1))
				if ang < bestAng then
					losParams.FilterDescendantsInstances = { self.character, gun, model }
					local block = workspace:Raycast(camCF.Position, to, losParams)
					if not block or (block.Instance.Transparency >= 0.9 and not block.Instance.CanCollide) then
						best, bestAng = root, ang
					end
				end
			end
		end
		for _, car in CollectionService:GetTagged("Vehicle") do
			local root = car:IsA("Model") and car.PrimaryPart
			if root and root:IsDescendantOf(workspace) and not car:GetAttribute("Wrecked") and car ~= self.car then
				consider(root, car)
			end
		end
		local function bodies(list: { Instance })
			for _, m in list do
				local t = m:IsA("Model") and m ~= self.character and m:FindFirstChild("Torso")
				if t and t:IsA("BasePart") and not m:GetAttribute("Dead") and not m:GetAttribute("InCar") then
					consider(t, m)
				end
			end
		end
		local chars = {}
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(chars, p.Character)
			end
		end
		bodies(chars)
		for _, folderName in { "NPCs", "Dummies", "Creatures" } do
			local f = workspace:FindFirstChild(folderName)
			if f then
				bodies(f:GetChildren())
			end
		end
		local lock = self.lock
		if not best then
			self.lock = nil
			return
		end
		if not lock or lock.part ~= best then
			lock = { part = best, t = 0, locked = false, beep = 0 }
			self.lock = lock
		end
		lock.t += dt
		local was = lock.locked
		lock.locked = lock.t >= Config.LockonTime
		lock.beep -= dt
		if lock.beep <= 0 then
			lock.beep = lock.locked and 0.12 or 0.28
			SoundLibrary.Play(lock.locked and "lockTone" or "lockBeep", nil, 0.8)
		end
		if lock.locked and not was then
			SoundLibrary.Play("lockTone", nil, 1)
		end
	end

	-- the part the lock-on launcher is locked on (fired with the rocket), or nil
	function Controller:GetLockTarget(gun: Instance): BasePart?
		local lock = self.lock
		if lock and lock.locked and lock.part.Parent then
			for _, side in SIDES do
				local g = self.hands[side].grip
				if g and g.item == gun then
					return lock.part
				end
			end
		end
		return nil
	end

	-- for the HUD: { part, progress 0..1, locked }
	function Controller:GetLockInfo()
		local lock = self.lock
		if not lock or not lock.part.Parent then
			return nil
		end
		return { part = lock.part, progress = math.clamp(lock.t / Config.LockonTime, 0, 1), locked = lock.locked }
	end

	----------------------------------------------------------------------
	-- things that happen to you
	----------------------------------------------------------------------

	-- the taser: down and twitching
	function Controller:_tased(duration: number)
		if self.dead then
			return
		end
		self:Ragdoll(duration)
		self.tasedUntil = os.clock() + duration
		task.spawn(function()
			while self.alive and not self.dead and os.clock() < (self.tasedUntil or 0) do
				for _, L in self.limbs do
					if not L.severed and L.part.Parent and rng:NextNumber() < 0.6 then
						pcall(function()
							L.part:ApplyImpulse(Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 1), rng:NextNumber(-1, 1)) * 14 * (self.slowK or 1) * L.part.AssemblyMass)
						end)
					end
				end
				Cam.Shake(0.18)
				task.wait(0.08)
			end
		end)
	end

	-- a prosthetic was fitted: the controller takes the new limb
	function Controller:_rebindLimb(key: string)
		local def = RigInfo.ByKey[key]
		if not def or not self.rig then
			return
		end
		task.spawn(function()
			local part = self.character:WaitForChild(def.partName, 5)
			local muscle = self.rig:WaitForChild("Muscle_" .. key, 5)
			if not part or not muscle or not part:IsA("BasePart") or not muscle:IsA("AlignOrientation") then
				return
			end
			for _ = 1, 30 do
				if muscle.Attachment1 then
					break
				end
				task.wait(0.05)
			end
			self.limbs[key] = {
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
			if self._rebuildFilters then
				self:_rebuildFilters()
			end
			SoundLibrary.Play("metal", part, 0.8)
		end)
	end

	----------------------------------------------------------------------
	-- every frame
	----------------------------------------------------------------------

	-- bleeding and a hand free: that hand goes to the latest wound and presses on it (bleeds slower)
	local PRESS_STATES = { Standing = true, Stumbling = true, Prone = true, Downed = true, GettingUp = true }
	local function updateWoundPress(self)
		local char = self.character
		local region = char:GetAttribute("WoundAt")
		local bleeding = char:GetAttribute("Bleeding") == true
		self.pressWound = nil
		if not bleeding or typeof(region) ~= "string" or not PRESS_STATES[self.state] or self.fist or self.fitting
			or (self.guardUntil or 0) > os.clock() or Input.HandControlActive() then
			return
		end
		local partName = RigInfo.RegionPart[region]
		local part = partName and char:FindFirstChild(partName)
		if not part or not part:IsA("BasePart") or char:GetAttribute("Severed_" .. region) == true then
			return
		end
		for _, side in SIDES do
			local hand = self.hands[side]
			if not hand.grip and not hand.armed and ARM_OF[side] ~= region and self:_limbUsable(ARM_OF[side]) then
				self.pressWound = { side = side, part = part }
				local now = os.clock()
				if now - (self.pressSent or 0) > 0.5 then
					self.pressSent = now
					KickRemote:FireServer("press")
				end
				return
			end
		end
	end

	-- (v2.0) under a parachute (ejected from a jet): you sink slowly
	local function updateParachute(self)
		local untilT = self.character:GetAttribute("ParachuteUntil")
		if typeof(untilT) ~= "number" or workspace:GetServerTimeNow() > untilT or self.grounded then
			if self.chuteLoop then
				self.chuteLoop:Destroy()
				self.chuteLoop = nil
			end
			return
		end
		-- the canopy flutters over you
		if not self.chuteLoop then
			local l = SoundLibrary.Loop("chuteFlutter", self.torso)
			if l then
				l.Volume = 0.32
				l:Play()
			end
			self.chuteLoop = l
		end
		pcall(function()
			for _, p in self.character:GetChildren() do
				if p:IsA("BasePart") then
					local v = p.AssemblyLinearVelocity
					if v.Y < -Config.ParachuteFall then
						p.AssemblyLinearVelocity = Vector3.new(v.X * 0.98, -Config.ParachuteFall, v.Z * 0.98)
					end
				end
			end
		end)
		self.suppressImpacts = math.max(self.suppressImpacts or 0, os.clock() + 0.3)
	end

	-- (v2.0) a zombie's leap: whoever it flies into gets bitten (the server's punch = a zombie's bite)
	local leapParams = OverlapParams.new()
	leapParams.FilterType = Enum.RaycastFilterType.Exclude
	leapParams.RespectCanCollide = false
	local function updateZombieLeap(self)
		if os.clock() > (self.zombieLeapUntil or 0) then
			return
		end
		local fx = workspace:FindFirstChild("FX")
		leapParams.FilterDescendantsInstances = fx and { self.character, fx } or { self.character }
		local head = self.character:FindFirstChild("Head")
		local at = (head and head:IsA("BasePart")) and head.Position or self.torso.Position
		for _, p in workspace:GetPartBoundsInRadius(at + self.torso.CFrame.LookVector * 0.8, 2.4, leapParams) do
			local body = bodyOf(p)
			if body and body ~= self.character and not self.zombieLeapHit[body] then
				self.zombieLeapHit[body] = true
				local v = self.torso.AssemblyLinearVelocity
				KickRemote:FireServer(p, at, v.Magnitude > 1 and v or self.torso.CFrame.LookVector * 30, "punch")
				SoundLibrary.Play("zombieBite", at, 1)
				Cam.Shake(0.5)
			end
		end
	end

	function Controller:_updateGear(dt: number)
		updateFist(self)
		updateZombieLeap(self)
		updateParachute(self)
		updateWoundPress(self)
		updateFitting(self)
		updateHarpoon(self)
		updateLock(self, dt)
	end
end
