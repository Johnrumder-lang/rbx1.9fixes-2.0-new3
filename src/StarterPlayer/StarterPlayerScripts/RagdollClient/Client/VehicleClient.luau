--!nonstrict
-- VehicleClient: G (or B) = get in / out of the nearest car. While you drive, THIS client simulates the
-- car (the server made you its physics owner) with CarPhysics: every wheel casts a ray down, a
-- spring-damper pushes the chassis up (one VectorForce per wheel), the tires grip sideways and the
-- rear wheels drive.
--   W / S  gas / brake + reverse      A / D  steer      Space  handbrake
-- While you drive, the wheels are not solid here (the rays carry the car); when you get out they
-- are solid again and the parked car stands on them.
-- People in front of the car are reported to the server, which hurts and throws them (run over);
-- at speed the car ploughs through them instead of getting stuck on them. Crashes wear the car
-- down (hidden HP on the server). Breakable walls ahead are smashed through.
-- G with a gun in your hand aims it instead; B always gets you in / out.
-- Somebody already drives: B gets you into the passenger seat. The driver's client simulates
-- your body then; you aim with the crosshair (the server turns your arms) and shoot (F).
-- The helicopter (v1.8) is a "car" too, flown by THIS client when you are its pilot:
--   Space / Ctrl  up / down     W / S  tilt forward / back (= fly forward / back)
--   A / D  turn                 Q / E  tilt sideways        F (hold) nose gun   C  rocket
-- A lift force along the rotor axis holds it up (it climbs / sinks at the speed you ask for), an
-- AlignOrientation tilts it; tilted, the lift pushes it that way. Three passengers can ride along
-- and shoot. Every client spins the rotors of helicopters that somebody flies.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TimeScale = require(Shared:WaitForChild("TimeScale"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))
local CarPhysics = require(Shared:WaitForChild("CarPhysics"))
local Items = require(Shared:WaitForChild("Items"))

local VehicleRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Vehicle") :: RemoteEvent

local Modules = script.Parent
local Input = require(Modules:WaitForChild("Input"))
local Cam = require(Modules:WaitForChild("CameraController"))
local JetClient = require(Modules:WaitForChild("JetClient"))

local VehicleClient = {}

local player = Players.LocalPlayer
local controller = nil
local car: Model? = nil
local engine: Sound? = nil
local pending: Model? = nil
local pendingUntil = 0
local passengerCar: Model? = nil
local nextAim = 0

local st = { lastVel = nil :: Vector3?, crashCD = 0, smashCD = 0, flipTime = 0, steer = 0, spin = 0, nudge = 0, seatCheck = 0, lastThrottle = 0, slowK = 1, turretSend = 0, tankShot = 0 }
local heli = { yaw = 0, spin = 0, gunCD = 0, rotorCheck = 0, lastForward = 0, lastTurn = 0 }
-- cars / helicopters we left while they were moving: our client keeps simulating them (the server hands the
-- physics over later), so they keep driving / flying without us
local runaways: { [Model]: any } = {}
local rotorState: { [Model]: { angle: number, tail: number, speed: number } } = setmetatable({}, { __mode = "k" }) :: any
local restC0: { [Weld]: CFrame } = {} -- wheel welds of the car we drive, as the server built them
local runOverCD: { [Instance]: number } = {}

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

-- wheels: rays carry the car while we drive it (not solid); solid when parked
local function setWheelsSolid(c: Model, solid: boolean)
	for _, d in c:GetChildren() do
		if d:IsA("BasePart") and string.match(d.Name, "^Wheel_") then
			d.CanCollide = solid
			local weld = d:FindFirstChild("WheelWeld")
			if weld and weld:IsA("Weld") then
				if solid then
					if restC0[weld] then
						weld.C0 = restC0[weld]
					end
				else
					restC0[weld] = weld.C0
				end
			end
		end
	end
	if solid then
		-- our suspension forces stop here (we may still simulate the car for a moment)
		local chassis = c.PrimaryPart
		if chassis then
			for _, f in chassis:GetChildren() do
				if f:IsA("VectorForce") then
					f.Force = Vector3.zero
				end
			end
		end
		table.clear(restC0)
	end
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
local boxParams = OverlapParams.new()
boxParams.FilterType = Enum.RaycastFilterType.Exclude

local function heliParts(c: Model): (VectorForce?, AlignOrientation?)
	local chassis = c.PrimaryPart
	local lift = chassis and chassis:FindFirstChild("HeliLift")
	local align = chassis and chassis:FindFirstChild("HeliAlign")
	return (lift and lift:IsA("VectorForce")) and lift or nil, (align and align:IsA("AlignOrientation")) and align or nil
end

local function setCar(c: Model?, keepSim: boolean?)
	if car and car ~= c and not keepSim then
		setWheelsSolid(car, true)
		if car:GetAttribute("Jet") then
			JetClient.Stop(car) -- (v2.0)
		end
		if car:GetAttribute("Heli") then
			-- (the rotor stops lifting: it comes down unless somebody else flies it)
			local lift, align = heliParts(car)
			if lift then
				lift.Force = Vector3.zero
			end
			if align then
				align.Enabled = false
			end
		end
	end
	if c and c ~= car and c:GetAttribute("Heli") and c.PrimaryPart then
		heli.yaw = MathUtil.Yaw(MathUtil.SafeUnit(MathUtil.Flat(c.PrimaryPart.CFrame.LookVector), Vector3.new(0, 0, -1)))
		heli.spin = 0
	end
	if c and c ~= car then
		setWheelsSolid(c, false)
		if c:GetAttribute("Jet") then
			JetClient.Reset(c)
		end
	end
	car = c
	if controller then
		controller.car = c
		if controller.ready then
			controller:_rebuildFilters()
		end
	end
	Cam.extra = c and (c:GetAttribute("Jet") and Config.JetCameraExtra or (c:GetAttribute("Heli") and Config.HeliCameraExtra or Config.CarCameraExtra)) or 0
	-- (v2.0) first person in the jet: the eye sits still in the cockpit (from the seat, not the bobbing head)
	if c and c:GetAttribute("Jet") then
		local seat = c:FindFirstChild("DriverSeat", true)
		local att = seat and seat:FindFirstChild("SeatAtt")
		Cam.cockpitFn = function(): CFrame?
			if not (seat and seat:IsA("BasePart") and seat.Parent) then
				return nil
			end
			local base = (att and att:IsA("Attachment")) and att.WorldCFrame or (seat :: BasePart).CFrame * CFrame.new(0, 1.6, 0)
			return base * CFrame.new(0, 1.65, -0.25)
		end
	else
		Cam.cockpitFn = nil
	end
	if engine then
		engine:Destroy()
		engine = nil
	end
	st.lastVel = nil
	st.steer = 0
	if c and c.PrimaryPart then
		-- (a jet's engine sound is JetClient's)
		local s = not c:GetAttribute("Jet") and SoundLibrary.Loop(c:GetAttribute("Heli") and "rotor" or "engine", c.PrimaryPart) or nil
		if s then
			s.Volume = 0.35
			s:Play()
			engine = s
		end
		local ignore: { Instance } = { c }
		if controller then
			table.insert(ignore, controller.character)
		end
		local fx = workspace:FindFirstChild("FX")
		if fx then
			table.insert(ignore, fx)
		end
		rayParams.FilterDescendantsInstances = ignore
		boxParams.FilterDescendantsInstances = ignore
	end
end

-- (v2.0) the jet we fly (for the HUD), or nil
function VehicleClient.Jet(): Model?
	return (car and car:GetAttribute("Jet")) and car or nil
end

function VehicleClient.IsDriving(): boolean
	return car ~= nil
end

function VehicleClient.SetController(c)
	controller = c
	if car then
		setCar(nil)
	end
	passengerCar = nil
	pending = nil
end

function VehicleClient.IsPassenger(): boolean
	return passengerCar ~= nil
end

local function carsFolder(): Instance?
	return workspace:FindFirstChild("SpawnedProps")
end

local function nearestCar(torso: BasePart): Model?
	local f = carsFolder()
	if not f then
		return nil
	end
	local best, bestD = nil, Config.CarEnterDistance
	for _, m in f:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("Car") and not m:GetAttribute("Wrecked") and m:GetAttribute("DriverId") == nil then
			local seat = m:FindFirstChild("DriverSeat")
			if seat and seat:IsA("BasePart") then
				local d = (seat.Position - torso.Position).Magnitude
				if d < bestD then
					best, bestD = m, d
				end
			end
		end
	end
	return best
end

local function endRunaway(c: Model)
	if not runaways[c] then
		return
	end
	runaways[c] = nil
	if c == car or not c.Parent then
		return
	end
	if c:GetAttribute("Jet") then
		JetClient.Stop(c)
		return
	end
	setWheelsSolid(c, true) -- (wheels solid again, our forces off)
	local lift, align = heliParts(c)
	if lift then
		lift.Force = Vector3.zero
	end
	if align then
		align.Enabled = false
	end
end

local function startRunaway(c: Model)
	local r: any = { t0 = os.clock(), throttle = 0, forward = 0, turn = 0, climb = -0.12 }
	if c:GetAttribute("Jet") then
		-- (v2.0) an empty jet flies straight on, a little nose down, with the throttle it had
		r.jet = true
		r.throttle = JetClient.Throttle()
		local fwd = c.PrimaryPart and c.PrimaryPart.CFrame.LookVector or Vector3.new(0, 0, -1)
		r.dir = (fwd - Vector3.new(0, 0.12, 0)).Unit
	elseif c:GetAttribute("Heli") then
		r.forward = heli.lastForward * 0.8
		r.turn = heli.lastTurn * 0.5
		r.state = { yaw = heli.yaw, spin = heli.spin }
	else
		local v = c.PrimaryPart and c.PrimaryPart.AssemblyLinearVelocity or Vector3.zero
		local fwd = c.PrimaryPart and v:Dot(c.PrimaryPart.CFrame.LookVector) or 0
		local thr = st.lastThrottle or 0
		if math.abs(thr) < 0.2 then
			thr = fwd > 15 and 0.55 or 0 -- (still rolling fast: it keeps driving)
		end
		r.throttle = math.clamp(thr, -1, 1)
		r.st = CarPhysics.NewState()
		r.st.steer = st.steer or 0
		r.st.spin = st.spin or 0
	end
	local ignore: { Instance } = { c }
	if controller and controller.character then
		table.insert(ignore, controller.character)
	end
	local fx = workspace:FindFirstChild("FX")
	if fx then
		table.insert(ignore, fx)
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.RespectCanCollide = true
	rp.FilterDescendantsInstances = ignore
	r.params = rp
	runaways[c] = r
end

-- climb out on the driver's side right away (the server removes its weld a moment later).
-- Leaving something that is moving (or flying): it keeps going without you and you tumble out.
local function exitLocal()
	local c = car
	local bail = false
	if c and c.PrimaryPart and not c:GetAttribute("Wrecked") then
		bail = c.PrimaryPart.AssemblyLinearVelocity.Magnitude > Config.RunawayMinSpeed
		if not bail and (c:GetAttribute("Heli") or c:GetAttribute("Jet")) then
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { c }
			bail = workspace:Raycast(c.PrimaryPart.Position, Vector3.new(0, c:GetAttribute("Jet") and -8 or -5, 0), rp) == nil
		end
	end
	if bail and c then
		startRunaway(c)
	end
	setCar(nil, bail) -- (otherwise: wheels solid again, our forces off)
	if not c or not controller or not controller.torso then
		return
	end
	local seat = c:FindFirstChild("DriverSeat")
	if seat then
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	local att = controller.torso:FindFirstChild("SeatTorsoAtt")
	if att then
		att:Destroy()
	end
	if seat and seat:IsA("BasePart") then
		local out = seat.CFrame * CFrame.new(-(bail and 3.1 or 3.8), 1.4, 0)
		local yaw = MathUtil.Yaw(MathUtil.Flat(seat.CFrame.LookVector))
		local char = controller.character
		local outPos = (bail and c:GetAttribute("Jet")) and (seat.Position + seat.CFrame.UpVector * 4.5) or out.Position
		local target = CFrame.new(outPos) * CFrame.Angles(0, yaw, 0)
		char:PivotTo(target * controller.torso.CFrame:ToObjectSpace(char:GetPivot()))
		local carV = c.PrimaryPart and c.PrimaryPart.AssemblyLinearVelocity or Vector3.zero
		local v = carV * (bail and 0.95 or 0.5)
		if bail and c:GetAttribute("Jet") then
			-- (v2.0) the ejection seat: straight up out of the cockpit, the parachute opens
			v = carV * 0.6 + seat.CFrame.UpVector * 75
			SoundLibrary.Play("rocketLaunch", seat.Position, 0.8)
		elseif bail then
			v += -seat.CFrame.RightVector * Config.BailKick + Vector3.new(0, 1.5, 0) -- (v1.9.1: no upward kick: you used to shoot out higher than the helicopter)
		end
		for _, p in char:GetDescendants() do
			if p:IsA("BasePart") then
				p.AssemblyLinearVelocity = v
				p.AssemblyAngularVelocity = Vector3.zero
			end
		end
		if bail then
			controller:Ragdoll(Config.BailRagdoll)
			Cam.Shake(0.7)
		end
	end
end

local flyHeli: (c: Model, chassis: BasePart, dt: number, auto: any?) -> () -- (defined below)

local function runawayStep(dt: number)
	if next(runaways) == nil then
		return
	end
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	for c, r in runaways do
		local endAt = c.Parent and c:GetAttribute("RunawayEnd")
		if
			not c.Parent
			or not c.PrimaryPart
			or c:GetAttribute("Wrecked")
			or c:GetAttribute("DriverId") ~= nil
			or (now - r.t0 > 1.5 and c:GetAttribute("Runaway") ~= player.UserId)
			or (typeof(endAt) == "number" and serverNow > endAt)
		then
			endRunaway(c)
			continue
		end
		local chassis = c.PrimaryPart :: BasePart
		if r.jet then
			JetClient.Fly(c, chassis, dt, r)
		elseif c:GetAttribute("Heli") then
			flyHeli(c, chassis, dt, r)
		else
			local age = now - r.t0
			local thr = r.throttle * (age < 3.5 and 1 or math.max(0, 1 - (age - 3.5) / 4))
			CarPhysics.Step(c, dt, { throttle = thr, steer = 0, brake = false, coast = true }, r.st, r.params, true)
		end
	end
end

-- the nearest car with a free passenger seat while somebody else drives it
local function nearestPassengerSeat(torso: BasePart): Model?
	local f = carsFolder()
	if not f then
		return nil
	end
	local best, bestD = nil, Config.CarEnterDistance
	for _, m in f:GetChildren() do
		local driver = m:IsA("Model") and m:GetAttribute("DriverId")
		if driver and driver ~= player.UserId and m:GetAttribute("Car") and not m:GetAttribute("Wrecked") then
			for _, seat in m:GetChildren() do
				if seat:IsA("BasePart") and string.match(seat.Name, "^PassengerSeat") and seat:GetAttribute("Occupant") == nil then
					local d = (seat.Position - torso.Position).Magnitude
					if d < bestD then
						best, bestD = m, d
					end
				end
			end
		end
	end
	return best
end

-- the vehicle whose passenger seat we sit in
local function seatedIn(): Model?
	local f = carsFolder()
	if not f then
		return nil
	end
	for _, m in f:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("Car") then
			for _, seat in m:GetChildren() do
				if seat:IsA("BasePart") and seat:GetAttribute("Occupant") == player.UserId then
					return m
				end
			end
		end
	end
	return nil
end

-- a free car (or passenger seat) close enough to get in (for the HUD hint)
function VehicleClient.NearCar(): boolean
	if car or passengerCar or not controller or not controller.ready or not controller.torso then
		return false
	end
	return nearestCar(controller.torso) ~= nil or nearestPassengerSeat(controller.torso) ~= nil
end

local function setPassenger(c: Model?)
	if passengerCar == c then
		return
	end
	passengerCar = c
	if controller then
		controller.passenger = c
		if controller.ready then
			controller:_rebuildFilters()
		end
	end
	Cam.extra = c and (c:GetAttribute("Heli") and Config.HeliCameraExtra or Config.CarCameraExtra) or 0
end

local function aimPoint(): Vector3
	if controller and controller._crosshairPoint then
		return controller:_crosshairPoint()
	end
	local cam = workspace.CurrentCamera
	return cam.CFrame.Position + cam.CFrame.LookVector * 300
end

local function onAction(action: string)
	-- (v2.0) the jet: C = missile, X = bomb
	if car and car:GetAttribute("Jet") and controller and not controller.dead then
		if action == "Kick" then
			JetClient.Missile(car)
			return
		elseif action == "Prone" then
			JetClient.Bomb(car)
			return
		end
	end
	if action == "Kick" and car and car:GetAttribute("Heli") and heli.spin > 0.5 and controller and not controller.dead then
		VehicleRemote:FireServer("helirocket", aimPoint() - (car.PrimaryPart and car.PrimaryPart.Position or aimPoint()))
		return
	end
	if (action ~= "Vehicle" and action ~= "Car") or not controller or not controller.ready or controller.dead then
		return
	end
	if car then
		VehicleRemote:FireServer("exit")
		exitLocal()
		return
	end
	if passengerCar then
		VehicleRemote:FireServer("exit")
		return
	end
	-- the game owner: B away from cars = fly (B again lands)
	if action == "Car" and controller.flying then
		controller:SetFlying(false)
		return
	end
	-- G with a gun in the hand aims it (B always works for cars)
	if action == "Vehicle" and ((controller.GetGunInfo and controller:GetGunInfo()) or (controller.GetItemInfo and controller:GetItemInfo())) then
		return
	end
	local c = nearestCar(controller.torso)
	local pc = not c and nearestPassengerSeat(controller.torso) or nil
	if pc then
		VehicleRemote:FireServer("passenger", pc)
		return
	end
	if not c and action == "Car" and Items.Has(player, "fly") and controller.SetFlying then
		controller:SetFlying(true)
		return
	end
	if c then
		for _, side in { "Left", "Right" } do
			controller:_release(side, false)
		end
		pending = c
		pendingUntil = os.clock() + 2
		VehicleRemote:FireServer("enter", c)
	end
end

local function keyDown(kb: Enum.KeyCode, pad: Enum.KeyCode): boolean
	return UserInputService:IsKeyDown(kb) or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, pad)
end

function flyHeli(c: Model, chassis: BasePart, dt: number, auto: any?)
	local lift, align = heliParts(c)
	if not lift or not align then
		return
	end
	local now = os.clock()
	local blocked = false
	local forward, turn, side, climb = 0, 0, 0, 0
	local hs = heli -- the state that holds yaw and rotor speed (a runaway helicopter has its own)
	if auto then
		hs = auto.state
		forward, turn, climb = auto.forward, auto.turn, auto.climb
	else
		blocked = Input.menuOpen or Input.promptOpen
		local mv = blocked and Vector3.zero or Input.GetMoveVector()
		forward = -mv.Z -- W = +1
		turn = mv.X -- D = +1
		if not blocked then
			side = (keyDown(Enum.KeyCode.E, Enum.KeyCode.ButtonR1) and 1 or 0) - (keyDown(Enum.KeyCode.Q, Enum.KeyCode.ButtonL1) and 1 or 0)
		end
		climb = blocked and 0 or ((Input.jumpHeld and 1 or 0) - (Input.downHeld and 1 or 0))
		heli.lastForward = forward
		heli.lastTurn = turn
	end
	-- blades that broke off take lift with them
	local blades = c:GetAttribute("Blades")
	local bladeK = typeof(blades) == "number" and math.clamp(blades / Config.HeliBladeCount, 0, 1) or 1
	if auto then
		-- nobody is in it: the rotor speed is what the server says (it coasts down slowly)
		local rs = c:GetAttribute("RotorSpeed")
		hs.spin = typeof(rs) == "number" and rs or 0
	else
		-- the rotor spins up before it lifts
		hs.spin = math.min(1, hs.spin + dt / Config.HeliSpinUp)
	end
	local k = hs.spin * hs.spin * bladeK
	hs.yaw -= turn * Config.HeliYawRate * dt * k
	local tilt = math.rad(Config.HeliTilt)
	align.Enabled = true
	align.CFrame = CFrame.Angles(0, hs.yaw, 0) * CFrame.Angles(-forward * tilt * k, 0, -side * tilt * 0.8 * k)
	local M = chassis.AssemblyMass
	local g = workspace.Gravity
	local vel = chassis.AssemblyLinearVelocity
	local up = chassis.CFrame.UpVector
	local wantVy = climb * Config.HeliClimbSpeed
	local ay = math.clamp((wantVy - vel.Y) * 2.6, -70, 70)
	local mag = M * (g + ay) / math.max(up.Y, 0.4)
	local flat = Vector3.new(vel.X, 0, vel.Z)
	local force = up * math.max(mag, 0) * k - flat * M * Config.HeliDrag * k
	lift.Force = force
	if auto then
		return
	end

	-- (crashes and the rotor chopping people are the server's job now)
	-- nose gun (hold F)
	if Input.useHeld and not blocked and now > heli.gunCD and k > 0.5 then
		heli.gunCD = now + Config.HeliGunInterval
		local muzzle = c:FindFirstChild("Muzzle", true)
		local from = (muzzle and muzzle:IsA("Attachment")) and muzzle.WorldPosition or chassis.Position
		VehicleRemote:FireServer("heligun", aimPoint() - from)
	end

	-- upside down on the ground: put it back on its skids
	if up.Y < 0.3 and vel.Magnitude < 4 and (forward ~= 0 or turn ~= 0 or climb ~= 0) then
		st.flipTime += dt
		if st.flipTime > 1.2 then
			st.flipTime = 0
			c:PivotTo(CFrame.new(chassis.Position + Vector3.new(0, 4, 0)) * CFrame.Angles(0, heli.yaw, 0))
		end
	else
		st.flipTime = 0
	end
	st.lastVel = vel
	if engine then
		engine.PlaybackSpeed = 0.15 + 0.12 * heli.spin + math.clamp(vel.Magnitude / 300, 0, 0.12)
		engine.Volume = 0.25 + 0.6 * heli.spin
	end
end

local function drive(dt: number)
	local c = car :: Model
	local chassis = c.PrimaryPart
	if not chassis then
		return
	end
	if c:GetAttribute("Jet") then
		JetClient.Fly(c, chassis, dt)
		return
	end
	if c:GetAttribute("Heli") then
		flyHeli(c, chassis, dt)
		return
	end
	local now = os.clock()
	local cf = chassis.CFrame
	local up = cf.UpVector
	local mv = Input.menuOpen and Vector3.zero or Input.GetMoveVector()
	local throttle = -mv.Z
	-- (v2.8) somebody else's Sandevistan: your car crawls too (and gets its speed back when it ends)
	local tk = TimeScale.For(player.UserId)
	if tk ~= (st.slowK or 1) then
		local f = tk / (st.slowK or 1)
		st.slowK = tk
		pcall(function()
			chassis.AssemblyLinearVelocity *= f
			chassis.AssemblyAngularVelocity *= f
		end)
	end
	throttle *= tk
	st.lastThrottle = throttle
	local steerIn = mv.X
	local brake = Input.jumpHeld and not Input.menuOpen
	local vel = chassis.AssemblyLinearVelocity
	local fwdSpeed = CarPhysics.Step(c, dt, { throttle = throttle, steer = steerIn, brake = brake }, st, rayParams, true)
	-- (v2.8) the tank: the turret follows where you look, F fires a shell
	if c:GetAttribute("Tank") then
		if now > (st.turretSend or 0) then
			st.turretSend = now + 0.08
			local target = aimPoint()
			local root = c:FindFirstChild("TurretRoot", true)
			local base = root and root:IsA("BasePart") and root.Position or chassis.Position
			local rel = chassis.CFrame:VectorToObjectSpace(target - base)
			local yaw = math.atan2(-rel.X, -rel.Z)
			local flat = Vector3.new(rel.X, 0, rel.Z).Magnitude
			local pitch = math.atan2(rel.Y - 1.2, math.max(flat, 1))
			VehicleRemote:FireServer("turret", yaw, pitch)
		end
		if Input.useHeld and not Input.menuOpen then
			local ready = c:GetAttribute("TankReady")
			if typeof(ready) ~= "number" or workspace:GetServerTimeNow() >= ready then
				if now > (st.tankShot or 0) then
					st.tankShot = now + Config.TankReload
					VehicleRemote:FireServer("tankfire")
					Cam.Shake(1.2)
				end
			end
		end
	end

	-- crashes
	if st.lastVel then
		local dv = (vel - st.lastVel).Magnitude
		if dv >= Config.CarCrashMin and now > st.crashCD then
			st.crashCD = now + 0.3
			VehicleRemote:FireServer("crash", dv)
			Cam.Shake(math.clamp(dv / 60, 0.4, 1.5))
		end
	end
	st.lastVel = vel

	-- breakable walls ahead: drive through them
	local speed = vel.Magnitude
	if speed > Config.CarSmashSpeed and now > st.smashCD then
		local dir = vel.Unit
		local center = chassis.Position + dir * 6.5 + up * 1.5
		local box = CFrame.lookAt(center, center + dir)
		local list = {}
		for _, p in workspace:GetPartBoundsInBox(box, Vector3.new(7, 5, 3 + speed * 0.1), boxParams) do
			if p.Anchored and (p:GetAttribute("Destructible") or (p:GetAttribute("Fracture") and speed >= Config.CarWallSpeed)) then
				table.insert(list, p)
				-- let the car through here at once; the server breaks the bricks a moment later
				p.CanCollide = false
				task.delay(0.7, function()
					if p.Parent then
						p.CanCollide = true
					end
				end)
			end
		end
		if #list > 0 then
			st.smashCD = now + 0.1
			VehicleRemote:FireServer("smash", list)
		end
	end

	-- people in front of the car: run them over
	if speed > Config.RunOverMinSpeed then
		local dir = MathUtil.SafeUnit(vel - up * vel:Dot(up), cf.LookVector)
		local center = chassis.Position + dir * 6.2 + up * 0.6
		local box = CFrame.lookAt(center, center + dir, up)
		local reported = {}
		for _, p in workspace:GetPartBoundsInBox(box, Vector3.new(6.6, 4.5, 2.5 + speed * 0.06), boxParams) do
			local body = bodyOf(p)
			if not body or body == controller.character or reported[body] or (runOverCD[body] or 0) > now then
				continue
			end
			reported[body] = true
			runOverCD[body] = now + 0.6
			VehicleRemote:FireServer("runover", p, speed)
			Cam.Shake(math.clamp(speed / 70, 0.3, 1))
			if speed > Config.RunOverMinSpeed + 6 then
				-- at speed the car goes through instead of getting stuck on the body (only here: the
				-- victim's own client still feels the hit)
				local changed = {}
				for _, bp in body:GetDescendants() do
					if bp:IsA("BasePart") and bp.CanCollide then
						bp.CanCollide = false
						table.insert(changed, bp)
					end
				end
				task.delay(0.55, function()
					for _, bp in changed do
						if bp.Parent then
							bp.CanCollide = true
						end
					end
				end)
			end
		end
	end

	-- a car that barely moves can fall asleep in the physics engine; keep it awake
	if speed < 3 and now > st.nudge then
		st.nudge = now + Config.KeepAwakeInterval
		pcall(function()
			chassis:ApplyImpulse(Vector3.new(0, chassis.AssemblyMass * 0.01, 0))
		end)
	end

	-- upside down and stuck: put it back on its wheels
	if up.Y < 0.3 and speed < 4 and (throttle ~= 0 or steerIn ~= 0) then
		st.flipTime += dt
		if st.flipTime > 1.2 then
			st.flipTime = 0
			local yaw = MathUtil.Yaw(MathUtil.SafeUnit(MathUtil.Flat(cf.LookVector), Vector3.new(0, 0, -1)))
			c:PivotTo(CFrame.new(chassis.Position + Vector3.new(0, 3, 0)) * CFrame.Angles(0, yaw, 0))
		end
	else
		st.flipTime = 0
	end

	if engine then
		engine.PlaybackSpeed = 0.75 + math.abs(fwdSpeed) / Config.CarMaxSpeed * 0.9
		engine.Volume = 0.3 + math.abs(throttle) * 0.25
	end
end

local function step(dt: number)
	if not controller or not controller.ready then
		return
	end
	runawayStep(dt)
	-- the passenger seat (the server says so through the attributes)
	local char = controller.character
	if char and char:GetAttribute("Passenger") and not controller.dead then
		local now0 = os.clock()
		if not passengerCar or now0 > st.seatCheck then
			st.seatCheck = now0 + 0.5
			local found = seatedIn()
			if found ~= passengerCar then
				setPassenger(found)
			end
		end
		-- tell the server where we aim (it turns our arms)
		local now = os.clock()
		if passengerCar and now > nextAim then
			nextAim = now + 0.08
			VehicleRemote:FireServer("aim", controller:_crosshairPoint())
		end
	elseif passengerCar then
		setPassenger(nil)
	end
	if not car then
		-- the server confirmed: we are welded into the seat
		if pending then
			local seat = pending:FindFirstChild("DriverSeat")
			if pending:GetAttribute("DriverId") == player.UserId and seat and seat:FindFirstChild("SeatWeld") then
				setCar(pending)
				pending = nil
			elseif os.clock() > pendingUntil then
				pending = nil
			end
		end
		return
	end
	local c = car :: Model
	if not c.Parent or c:GetAttribute("Wrecked") or c:GetAttribute("DriverId") ~= player.UserId or controller.dead or not c.PrimaryPart then
		-- thrown out (car wrecked, died, server said so): the server removes the seat weld
		setCar(nil)
		return
	end
	drive(dt)
end

-- every client turns the rotors of the helicopters that somebody flies (purely visual: the hub
-- Welds' C0); they spin down when the pilot gets out
local CYL_Y = CFrame.Angles(0, 0, math.rad(90))
local function spinRotors(dt: number)
	local f = carsFolder()
	if not f then
		return
	end
	for _, m in f:GetChildren() do
		if not (m:IsA("Model") and m:GetAttribute("Heli")) then
			continue
		end
		local rs = rotorState[m]
		-- the server owns the rotor speed (it spins up while somebody flies and coasts down slowly after)
		local target = m:GetAttribute("RotorSpeed")
		if typeof(target) ~= "number" then
			target = (m:GetAttribute("DriverId") ~= nil and not m:GetAttribute("Wrecked")) and 1 or 0
		end
		if not rs then
			if target <= 0.01 then
				continue
			end
			rs = { angle = 0, tail = 0, speed = 0 }
			rotorState[m] = rs
		end
		rs.speed += (target - rs.speed) * math.min(1, dt * 6)
		if rs.speed < 0.01 then
			rs.speed = 0
			continue
		end
		rs.angle = (rs.angle + rs.speed * Config.HeliBladeSpeed * dt) % (2 * math.pi)
		rs.tail = (rs.tail + rs.speed * 40 * dt) % (2 * math.pi)
		for _, hubName in { "RotorHub", "TailRotorHub" } do
			local hub = m:FindFirstChild(hubName)
			local weld = hub and hub:FindFirstChild("RotorWeld")
			local base = hub and hub:GetAttribute("RotorBase")
			if weld and weld:IsA("Weld") and typeof(base) == "CFrame" then
				if hub:GetAttribute("RotorAxis") == "Y" then
					weld.C0 = base * CFrame.Angles(0, rs.angle, 0) * CYL_Y
				else
					weld.C0 = base * CFrame.Angles(rs.tail, 0, 0)
				end
			end
		end
	end
end

-- (v2.0) the engines of the bot cars near us (BotDriverService drives them on the server)
local botEngines: { [Model]: Sound } = {}
local nextBotScan = 0
local function botEngineStep()
	local now = os.clock()
	if now >= nextBotScan then
		nextBotScan = now + 0.5
		local cam = workspace.CurrentCamera
		local f = carsFolder()
		local seen = {}
		if f and cam then
			for _, m in f:GetChildren() do
				if m:IsA("Model") and m:GetAttribute("BotDriver") and not m:GetAttribute("Wrecked") and m.PrimaryPart then
					if (m.PrimaryPart.Position - cam.CFrame.Position).Magnitude < 160 then
						seen[m] = true
						if not botEngines[m] then
							local s = SoundLibrary.Loop("engine", m.PrimaryPart)
							if s then
								s.Volume = 0.25
								s:Play()
								botEngines[m] = s
							end
						end
					end
				end
			end
		end
		for m, s in botEngines do
			if not seen[m] then
				s:Destroy()
				botEngines[m] = nil
			end
		end
	end
	for m, s in botEngines do
		local ch = m.PrimaryPart
		if ch then
			local v = ch.AssemblyLinearVelocity.Magnitude
			s.PlaybackSpeed = 0.7 + math.min(v, Config.CarMaxSpeed) / Config.CarMaxSpeed * 0.9
		end
	end
end

function VehicleClient.Init()
	Input.Action:Connect(onAction)
	RunService.PreSimulation:Connect(step)
	RunService.RenderStepped:Connect(spinRotors)
	RunService.Heartbeat:Connect(botEngineStep)
end

-- get out of whatever you sit in (before a teleport); true if you sat in something
function VehicleClient.Leave(): boolean
	if car then
		VehicleRemote:FireServer("exit")
		exitLocal()
		return true
	end
	if passengerCar then
		VehicleRemote:FireServer("exit")
		return true
	end
	return false
end

return VehicleClient
