--!nonstrict
-- JetClient (v2.0): flying the jet (this client simulates it while you are its pilot).
--   W / S        throttle up / down (on the runway: S with the throttle at zero = brakes)
--   the camera   the nose follows where you look (mouse aim); it banks into turns by itself, A / D roll more
--   F (hold)     the cannon (straight ahead: the small circle on the screen)
--   C            a homing missile at what is LOCKED (keep a vehicle / player in front of the nose: the box turns green)
--   X            drop a bomb
--   B            eject (in the air: the seat fires you out and a parachute opens)
-- It needs Config.JetMinSpeed to fly: slower it sinks (STALL). Everybody sees the afterburners from the throttle the
-- pilot reports, and hears the engine.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))

local Modules = script.Parent
local Input = require(Modules:WaitForChild("Input"))
local Cam = require(Modules:WaitForChild("CameraController"))

local VehicleRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Vehicle") :: RemoteEvent

local player = Players.LocalPlayer

local JetClient = {}

local st = { throttle = 0, roll = 0, gunCD = 0, sentThrottle = -1, sentAt = 0, lock = nil :: any, lockBeep = 0 }
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude

local function parts(c: Model): (VectorForce?, AlignOrientation?)
	local chassis = c.PrimaryPart
	local f = chassis and chassis:FindFirstChild("JetForce")
	local a = chassis and chassis:FindFirstChild("JetAlign")
	return (f and f:IsA("VectorForce")) and f or nil, (a and a:IsA("AlignOrientation")) and a or nil
end

function JetClient.Reset(c: Model?)
	st.throttle = 0
	st.roll = 0
	st.lock = nil
	if c then
		local v = c.PrimaryPart and c.PrimaryPart.AssemblyLinearVelocity or Vector3.zero
		local fwd = c.PrimaryPart and c.PrimaryPart.CFrame.LookVector or Vector3.zero
		-- (getting into a jet that is still flying fast: keep it flying)
		st.throttle = math.clamp(v:Dot(fwd) / Config.JetMaxSpeed, 0, 1)
	end
end

function JetClient.Throttle(): number
	return st.throttle
end

-- forces off (nobody flies it any more)
function JetClient.Stop(c: Model)
	local f, a = parts(c)
	if f then
		f.Force = Vector3.zero
	end
	if a then
		a.Enabled = false
	end
end

-- auto = { throttle, dir } when it flies on without a pilot (runaway)
function JetClient.Fly(c: Model, chassis: BasePart, dt: number, auto: any?)
	local force, align = parts(c)
	if not force or not align then
		return
	end
	local M = chassis.AssemblyMass
	local g = workspace.Gravity
	local cf = chassis.CFrame
	local fwd = cf.LookVector
	local vel = chassis.AssemblyLinearVelocity
	local speed = vel:Dot(fwd)
	local ignore: { Instance } = { c }
	local char = player.Character
	if char then
		table.insert(ignore, char)
	end
	groundParams.FilterDescendantsInstances = ignore
	local grounded = workspace:Raycast(chassis.Position, -cf.UpVector * 3.9, groundParams) ~= nil
	local throttle, aimDir, rollIn, braking = 0, fwd, 0, false
	if auto then
		throttle = auto.throttle or 0
		aimDir = auto.dir or fwd
	else
		local blocked = Input.menuOpen or Input.promptOpen
		local mv = blocked and Vector3.zero or Input.GetMoveVector()
		st.throttle = math.clamp(st.throttle + (-mv.Z) * dt * 0.65, 0, 1)
		throttle = st.throttle
		braking = grounded and st.throttle < 0.02 and mv.Z > 0.5
		aimDir = Cam.LookVector()
		rollIn = mv.X
	end
	local k = math.clamp(speed / Config.JetMinSpeed, 0, 1)
	if grounded and speed < Config.JetMinSpeed * 0.85 then
		-- rolling on the runway: steer with the camera, the nose stays level (a little up to rotate)
		local flat = MathUtil.SafeUnit(MathUtil.Flat(aimDir), MathUtil.SafeUnit(MathUtil.Flat(fwd), Vector3.new(0, 0, -1)))
		local up = math.clamp(aimDir.Y, 0, 0.12) * k
		aimDir = (flat + Vector3.new(0, up, 0)).Unit
	end
	-- bank into the turn
	local flatF = MathUtil.SafeUnit(MathUtil.Flat(fwd), Vector3.new(0, 0, -1))
	local flatA = MathUtil.SafeUnit(MathUtil.Flat(aimDir), flatF)
	local turn = math.atan2(flatF:Cross(flatA).Y, flatF:Dot(flatA))
	local wantRoll = math.clamp(-turn * 2.4, -1.25, 1.25) * k + rollIn * 0.9 * k
	if grounded then
		wantRoll = 0
	end
	st.roll += (wantRoll - st.roll) * math.min(1, dt * 3)
	align.Enabled = true
	align.CFrame = CFrame.lookAt(Vector3.zero, aimDir) * CFrame.Angles(0, 0, st.roll)
	align.Responsiveness = 2.5 + 9 * k
	-- forces: thrust along the nose, drag, lift that grows with speed, no sideways drift
	local thrust = fwd * throttle * Config.JetThrust * M
	local dragK = Config.JetThrust / Config.JetMaxSpeed
	local total = thrust - vel * dragK * M
	local liftK = math.clamp((speed / Config.JetMinSpeed) ^ 2, 0, 1)
	total += Vector3.new(0, M * g * liftK, 0)
	local lateral = vel - fwd * speed
	total -= lateral * M * 2.4 * math.max(k, grounded and 0.8 or 0)
	if braking then
		total -= MathUtil.Flat(vel) * M * 1.6
	end
	force.Force = total
	if auto then
		return
	end
	-- the throttle for everybody's afterburner
	local now = os.clock()
	if math.abs(st.throttle - st.sentThrottle) > 0.04 and now - st.sentAt > 0.25 then
		st.sentThrottle = st.throttle
		st.sentAt = now
		VehicleRemote:FireServer("throttle", st.throttle)
	end
	-- cannon (hold F)
	if Input.useHeld and not Input.menuOpen and now > st.gunCD then
		st.gunCD = now + Config.JetGunInterval
		VehicleRemote:FireServer("jetgun", fwd)
		Cam.Shake(0.08)
	end
	JetClient.UpdateLock(c, chassis, dt)
end

-- the seeker: the target closest to the nose (vehicles and players), locked after Config.JetLockTime
function JetClient.UpdateLock(c: Model, chassis: BasePart, dt: number)
	local fwd = chassis.CFrame.LookVector
	local best, bestAng = nil, math.rad(Config.JetLockCone)
	local function consider(part: BasePart, model: Instance)
		local to = part.Position - chassis.Position
		local dist = to.Magnitude
		if dist < 20 or dist > Config.JetLockRange then
			return
		end
		local ang = math.acos(math.clamp(to.Unit:Dot(fwd), -1, 1))
		if ang < bestAng then
			losParams.FilterDescendantsInstances = { c, model, player.Character :: Instance }
			if not workspace:Raycast(chassis.Position, to, losParams) then
				best, bestAng = part, ang
			end
		end
	end
	for _, v in CollectionService:GetTagged("Vehicle") do
		if v ~= c and v:IsA("Model") and v.PrimaryPart and not v:GetAttribute("Wrecked") then
			consider(v.PrimaryPart, v)
		end
	end
	for _, p in Players:GetPlayers() do
		local ch = p.Character
		local t = ch and ch:FindFirstChild("Torso")
		if p ~= player and t and t:IsA("BasePart") and not ch:GetAttribute("Dead") and not ch:GetAttribute("InCar") then
			consider(t, ch)
		end
	end
	if not best then
		st.lock = nil
		return
	end
	local lock = st.lock
	if not lock or lock.part ~= best then
		lock = { part = best, t = 0, locked = false }
		st.lock = lock
	end
	lock.t += dt
	local was = lock.locked
	lock.locked = lock.t >= Config.JetLockTime
	st.lockBeep -= dt
	if st.lockBeep <= 0 then
		st.lockBeep = lock.locked and 0.14 or 0.3
		SoundLibrary.Play(lock.locked and "lockTone" or "lockBeep", nil, 0.7)
	end
	if lock.locked and not was then
		SoundLibrary.Play("lockTone", nil, 1)
	end
end

function JetClient.GetLock()
	local lock = st.lock
	if not lock or not lock.part.Parent then
		return nil
	end
	return { part = lock.part, progress = math.clamp(lock.t / Config.JetLockTime, 0, 1), locked = lock.locked }
end

-- C: a missile (homing when locked)
function JetClient.Missile(c: Model)
	local chassis = c.PrimaryPart
	if not chassis then
		return
	end
	local lock = st.lock
	local target = (lock and lock.locked and lock.part.Parent) and lock.part or nil
	VehicleRemote:FireServer("jetmissile", chassis.CFrame.LookVector, target)
end

-- X: a bomb
function JetClient.Bomb(_c: Model)
	VehicleRemote:FireServer("jetbomb")
end

-- for the HUD
function JetClient.Info(c: Model): any
	local chassis = c.PrimaryPart
	if not chassis then
		return nil
	end
	local vel = chassis.AssemblyLinearVelocity
	local speed = vel:Dot(chassis.CFrame.LookVector)
	groundParams.FilterDescendantsInstances = { c, player.Character :: Instance }
	local down = workspace:Raycast(chassis.Position, Vector3.new(0, -2000, 0), groundParams)
	local alt = down and (chassis.Position.Y - down.Position.Y - 2.6) or chassis.Position.Y
	return {
		throttle = st.throttle,
		speed = speed,
		alt = math.max(0, alt),
		missiles = c:GetAttribute("Missiles") or 0,
		bombs = c:GetAttribute("Bombs") or 0,
		stall = speed < Config.JetMinSpeed * 0.8 and alt > 6,
		pipper = chassis.Position + chassis.CFrame.LookVector * 600,
		lock = JetClient.GetLock(),
	}
end

-- everybody: afterburners and engine sound of every jet
local whines: { [Model]: Sound } = {}
local engines: { [Model]: Sound } = {}
local flames: { [Model]: { ParticleEmitter } } = {}
function JetClient.Init()
	RunService.RenderStepped:Connect(function()
		for _, v in CollectionService:GetTagged("Vehicle") do
			if v:IsA("Model") and v:GetAttribute("Jet") and v.PrimaryPart then
				local thr = v:GetAttribute("Throttle")
				thr = typeof(thr) == "number" and thr or 0
				if v:GetAttribute("Wrecked") then
					thr = 0
				end
				local list = flames[v]
				if not list then
					list = {}
					for _, d in v:GetDescendants() do
						if d:IsA("ParticleEmitter") and d.Name == "Flame" then
							table.insert(list, d)
						end
					end
					flames[v] = list
				end
				for _, f in list do
					f.Rate = thr > 0.05 and (30 + thr * 160) or 0
				end
				local snd = engines[v]
				if not snd or not snd.Parent then
					snd = SoundLibrary.Loop("jetEngine", v.PrimaryPart)
					if snd then
						snd:Play()
						engines[v] = snd
					end
				end
				local live = v:GetAttribute("DriverId") or thr > 0.05
				if snd then
					snd.Volume = live and (0.35 + thr * 0.65) or 0
					snd.PlaybackSpeed = 0.45 + thr * 0.55
				end
				-- (v2.0) the turbine whine over the roar: it climbs with the throttle
				local wh = whines[v]
				if not wh or not wh.Parent then
					wh = SoundLibrary.Loop("jetWhine", v.PrimaryPart)
					if wh then
						wh:Play()
						whines[v] = wh
					end
				end
				if wh then
					wh.Volume = live and (0.08 + thr * 0.22) or 0
					wh.PlaybackSpeed = (wh:GetAttribute("BaseSpeed") or 1.6) * (0.8 + thr * 0.5)
				end
			end
		end
		for v, snd in engines do
			if not v.Parent then
				snd:Destroy()
				engines[v] = nil
				flames[v] = nil
				if whines[v] then
					whines[v]:Destroy()
					whines[v] = nil
				end
			end
		end
	end)
end

return JetClient
