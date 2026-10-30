--!nonstrict
-- VehicleService: cars.
--   G near a car = get in / out. The driver is welded into the seat by the server (so everybody sees
--   it) and becomes the car's physics owner; the driver's client simulates the suspension and the
--   tires (VehicleClient). A parked car simply stands on its wheels (they are solid while nobody
--   drives it, so nothing has to hold it up and it never bounces).
--   Running people over: the driver's client reports the body parts in front of the car, the server
--   checks them and hurts / throws the victim (speed based, limbs can come off); the kill goes to the
--   driver. Their own impact sensors add the crash damage on top.
--   Every car has hidden HP: crashes, bullets and explosions wear it down. Below 40 % it smokes,
--   below 18 % it burns, at 0 it explodes and falls apart.
--   Passenger seat: B next to a car somebody drives. The passenger is welded into the seat and
--   their body is simulated by the driver's client together with the car (so it never lags
--   behind); the passenger keeps what they hold, aims with the crosshair (the server turns the
--   arms) and shoots out of the window.
--   Tires: shot or driven over something sharp (spikes) they pop: the car sits lower on that
--   wheel, pulls to that side and grips worse.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TimeScale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TimeScale")) -- (v2.8) the Sandevistan's slow motion
local RigInfo = require(Shared:WaitForChild("RigInfo"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local HitMath = require(Shared:WaitForChild("HitMath"))

local Modules = script.Parent
local OwnershipService = require(Modules:WaitForChild("OwnershipService"))
local ExplosionService = require(Modules:WaitForChild("ExplosionService"))
local GoreService = require(Modules:WaitForChild("GoreService"))
local DamageService = require(Modules:WaitForChild("DamageService"))
local GunService = require(Modules:WaitForChild("GunService"))

local VehicleRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Vehicle") :: RemoteEvent
local FXRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("FX") :: RemoteEvent
local RigBuilder = require(Modules:WaitForChild("RigBuilder"))

local VehicleService = {}
VehicleService.OnEnter = nil :: ((Player, Model) -> ())? -- (v2.0) BotDriverService: a player takes a bot's car

type Seat = { car: Model, weld: Instance, att: Instance, conns: { RBXScriptConnection }, seatPart: BasePart? }
local drivers: { [Player]: Seat } = {}
local passengers: { [Player]: Seat } = {}
local lastAim: { [Player]: number } = {}
local lastCrash: { [Player]: number } = {}
local lastSmash: { [Player]: number } = {}
local lastRunOver: { [string]: number } = {}
local lastHeliGun: { [Player]: number } = {}
local lastTankShot: { [Player]: number } = {} -- (v2.8)
local lastHeliRocket: { [Player]: number } = {}
local podSide: { [Model]: number } = {}
local lastRotorHit: { [Model]: number } = {}
local helis: { [Model]: boolean } = {}
local heliVel: { [Model]: Vector3 } = {}
local jets: { [Model]: boolean } = {} -- (v2.0)
local jetVel: { [Model]: Vector3 } = {}
local lastJetGun: { [Player]: number } = {}
local lastJetMissile: { [Player]: number } = {}
local lastJetBomb: { [Player]: number } = {}
local lastBladeStrike: { [Model]: number } = {}
local lastBladeBody: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
local rotorOverlap = OverlapParams.new()
rotorOverlap.FilterType = Enum.RaycastFilterType.Exclude

-- set by Main (avoids a require cycle): launches a rocket (origin, dir, attacker, ignore)
VehicleService.OnRocket = nil :: ((Vector3, Vector3, Player?, { Instance }?, BasePart?, any?) -> ())?

local function setGroup(model: Instance, group: string)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
end

function VehicleService.Register(car: Model)
	if not car:GetAttribute("Car") then
		return
	end
	setGroup(car, "Car")
	game:GetService("CollectionService"):AddTag(car, "Vehicle") -- (v2.0: the lock-on launcher finds vehicles by this tag)
	if car:GetAttribute("Jet") then
		jets[car] = true
		car:SetAttribute("BornAt", os.clock())
		car:SetAttribute("CarHP", Config.JetHP)
		car:SetAttribute("CarMaxHP", Config.JetHP)
	end
	if car:GetAttribute("Heli") then
		helis[car] = true
		car:SetAttribute("RotorSpeed", 0)
		car:SetAttribute("Missiles", Config.HeliMissiles)
		car:SetAttribute("Blades", Config.HeliBladeCount)
		car:SetAttribute("BornAt", os.clock())
		car:SetAttribute("CarHP", Config.HeliHP)
		car:SetAttribute("CarMaxHP", Config.HeliHP)
	end
	car:SetAttribute("CarHP", car:GetAttribute("CarHP") or Config.CarHP)
	car:SetAttribute("CarMaxHP", car:GetAttribute("CarMaxHP") or Config.CarHP)
	if car.PrimaryPart then
		OwnershipService.SetOwner(car.PrimaryPart, nil)
	end
end

-- a body part in front of a moving car: hurt / throw the person (the driver's client reports it; (v2.0)
-- a bot driver's car is checked by the server). `by` gets the kill (nil for a bot), `key` tells drivers apart
local function hitBody(car: Model, by: Player?, byName: string, key: string, own: Model?, part: BasePart, claimed: number)
	local chassis = car.PrimaryPart
	if not chassis then
		return
	end
	local body, region = DamageService.BodyOf(part)
	if not body or not region or body == own or body:GetAttribute("InCar") then
		return
	end
	if (part.Position - chassis.Position).Magnitude > 18 then
		return
	end
	local v = chassis.AssemblyLinearVelocity
	local speed = math.min(claimed, v.Magnitude + 15, Config.CarMaxSpeed + 15)
	if speed < Config.RunOverMinSpeed then
		return
	end
	local k = key .. ":" .. body:GetFullName()
	local now = os.clock()
	if now - (lastRunOver[k] or 0) < 0.6 then
		return
	end
	lastRunOver[k] = now
	local dmg = (speed - Config.RunOverMinSpeed) * Config.RunOverDamage
	local cause = "Run over by " .. byName
	local opts = { cause = cause, allowSever = true, severAt = Config.RunOverSeverDamage, attacker = by }
	DamageService.ApplyDamage(body, region, dmg, part.Position, opts)
	if region ~= "Torso" then
		DamageService.ApplyDamage(body, "Torso", dmg * 0.5, nil, { cause = cause, allowSever = false, attacker = by, quiet = true })
	end
	for _, leg in { "LeftLeg", "RightLeg" } do
		if leg ~= region then
			DamageService.ApplyDamage(body, leg, dmg * 0.35, nil, { cause = cause, allowSever = false, attacker = by, quiet = true })
		end
	end
	-- thrown ahead of the car and up a bit
	local dir = v.Magnitude > 1 and v.Unit or chassis.CFrame.LookVector
	DamageService.Blast(body, dir * speed * 0.85 + Vector3.new(0, 10 + speed * 0.3, 0), 2.6)
	GoreService.Sound("carCrash", part.Position, math.clamp(speed / 70, 0.4, 1))
	GoreService.Sound("bodyHit", part.Position, 1)
	VehicleService.Damage(car, speed * 0.08, nil)
end

local function runOver(player: Player, seat: Seat, part: any, claimed: any)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or typeof(claimed) ~= "number" or claimed ~= claimed then
		return
	end
	hitBody(seat.car, player, player.DisplayName, tostring(player.UserId), player.Character, part, claimed)
end

local function driverOf(car: Model): Player?
	local id = car:GetAttribute("DriverId")
	return typeof(id) == "number" and Players:GetPlayerByUserId(id) or nil
end

------------------------------------------------------------------------
-- the passenger seat
------------------------------------------------------------------------

local DOWN = Vector3.new(0, -1, 0)

-- everybody in a passenger seat of this vehicle (a car has one, the helicopter three)
local function passengersOf(car: Model): { Player }
	local out = {}
	for p, rec in passengers do
		if rec.car == car then
			table.insert(out, p)
		end
	end
	return out
end

-- the free passenger seat closest to `pos` (seats are parts named PassengerSeat*, with a SeatAtt)
local function freeSeat(car: Model, pos: Vector3): BasePart?
	local best, bestD = nil, math.huge
	for _, d in car:GetChildren() do
		if d:IsA("BasePart") and string.match(d.Name, "^PassengerSeat") and d:FindFirstChild("SeatAtt") and d:GetAttribute("Occupant") == nil then
			local dist = (d.Position - pos).Magnitude
			if dist < bestD then
				best, bestD = d, dist
			end
		end
	end
	return best
end

-- the passenger's body (and what they hold) is simulated by whoever simulates the car
local function setPassengerOwner(passenger: Player, owner: Player?)
	local char = passenger.Character
	if char then
		for _, d in char:GetDescendants() do
			if d:IsA("BasePart") and not d.Anchored then
				pcall(function()
					d:SetNetworkOwner(owner)
				end)
			end
		end
	end
	for _, item in OwnershipService.HeldItems(passenger) do
		if item.PrimaryPart then
			OwnershipService.SetOwner(item.PrimaryPart, owner)
		end
	end
end

local function muscle(char: Model, key: string): (AlignOrientation?, Attachment?)
	local rig = char:FindFirstChild("Rig")
	local torso = char:FindFirstChild("Torso")
	local m = rig and rig:FindFirstChild("Muscle_" .. key)
	local t = torso and torso:FindFirstChild("M_" .. key)
	return (m and m:IsA("AlignOrientation")) and m or nil, (t and t:IsA("Attachment")) and t or nil
end

-- sitting: no balance / walking forces, legs forward, arms where the passenger aims
local function seatPose(char: Model)
	RigBuilder.GoLimp(char)
	for _, def in RigInfo.Limbs do
		local m, t = muscle(char, def.key)
		if m and t and not char:GetAttribute("Severed_" .. def.key) then
			m.Enabled = true
			if def.kind == "Leg" then
				m.MaxTorque = Config.LegMuscleTorque * 0.6
				t.CFrame = CFrame.new(def.torsoPivot) * CFrame.Angles(1.45, 0, def.side * 0.08)
			else
				m.MaxTorque = Config.ArmMuscleTorque * 1.3
				t.CFrame = CFrame.new(def.torsoPivot) * CFrame.Angles(0.35, 0, def.side * 0.15)
			end
		end
	end
end

local function aimPassenger(player: Player, point: Vector3)
	local char = player.Character
	local torso = char and char:FindFirstChild("Torso")
	if not char or not torso or not torso:IsA("BasePart") then
		return
	end
	local held = OwnershipService.HeldItemSides(player)
	for _, def in RigInfo.Limbs do
		if def.kind == "Leg" then
			continue
		end
		local side = def.side < 0 and "Left" or "Right"
		local _, t = muscle(char, def.key)
		if not t then
			continue
		end
		if held[side] or held[side == "Left" and "Right" or "Left"] then
			local shoulder = torso.CFrame:PointToWorldSpace(def.torsoPivot)
			local dir = point - shoulder
			if held[side] then
				dir = point - shoulder
			else
				-- the free hand supports the gun in the other hand
				local other = held[side == "Left" and "Right" or "Left"]
				local gp = other and other.PrimaryPart and other.PrimaryPart.Position
				dir = gp and (gp + (point - gp).Unit * 1.2 - shoulder) or dir
			end
			local local_ = torso.CFrame:VectorToObjectSpace(MathUtil.SafeUnit(dir, torso.CFrame.LookVector))
			local_ = MathUtil.SafeUnit(Vector3.new(local_.X, math.min(local_.Y, 0.95), math.min(local_.Z, 0.3)), DOWN)
			t.CFrame = CFrame.new(def.torsoPivot) * MathUtil.RotationBetween(DOWN, local_)
		else
			t.CFrame = CFrame.new(def.torsoPivot) * CFrame.Angles(0.35, 0, def.side * 0.15)
		end
	end
end

-- is this car / helicopter going fast enough (or flying) that getting out is a bail-out?
local function isRunaway(car: Model): boolean
	if car:GetAttribute("Wrecked") then
		return false
	end
	local chassis = car.PrimaryPart
	if not chassis then
		return false
	end
	if chassis.AssemblyLinearVelocity.Magnitude > Config.RunawayMinSpeed then
		return true
	end
	if car:GetAttribute("Heli") or car:GetAttribute("Jet") then
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { car }
		return workspace:Raycast(chassis.Position, Vector3.new(0, car:GetAttribute("Jet") and -8 or -5, 0), rp) == nil
	end
	return false
end

-- (v2.0) out of a jet in the air: the seat fires you up and a parachute opens. The canopy is a dome of panels
-- over you; its lines run from the canopy's rim down to your shoulders (beams between attachments, so they always
-- end on your body). When you land, the canopy comes loose: it drifts down past you, slumps onto the ground,
-- folds and fades; the lines go slack and fade with it.
local function collapseParachute(canopy: Model, torso: BasePart?)
	if canopy:GetAttribute("Collapsing") then
		return
	end
	canopy:SetAttribute("Collapsing", true)
	local fx = workspace:FindFirstChild("FX")
	canopy.Parent = fx or workspace -- (off the body: it is not part of the character any more)
	local TweenService = game:GetService("TweenService")
	local panels = {}
	for _, p in canopy:GetChildren() do
		if p:IsA("BasePart") then
			for _, w in p:GetChildren() do
				if w:IsA("WeldConstraint") then
					w:Destroy()
				end
			end
			p.Anchored = true
			table.insert(panels, p)
		end
	end
	if #panels == 0 then
		canopy:Destroy()
		return
	end
	-- where it comes down: beside you, downwind, on the ground
	local centre = torso and torso.Parent and torso.Position or panels[1].Position
	local side = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
	side = side.Magnitude > 0.01 and side.Unit or Vector3.xAxis
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { canopy, torso and torso.Parent or canopy }
	local ground = workspace:Raycast(centre + side * 7 + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), rp)
	local groundY = ground and ground.Position.Y or (centre.Y - 3)
	GoreService.Sound("chuteFold", centre, 1)
	local info1 = TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local info2 = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for i, p in panels do
		local rel = (p.Position - centre)
		-- 1) the dome tips over to one side and sinks
		local mid = CFrame.new(centre + side * 6 + Vector3.new(rel.X * 0.8, math.max(rel.Y * 0.35, 1.5), rel.Z * 0.8) + side * (i % 3)) * (p.CFrame - p.Position) * CFrame.Angles(0, 0, math.rad(50))
		TweenService:Create(p, info1, { CFrame = mid }):Play()
		-- 2) it slumps flat onto the ground, crumples and fades
		task.delay(1.1, function()
			if not p.Parent then
				return
			end
			local flat = CFrame.new(Vector3.new(mid.Position.X + math.random() * 1.6 - 0.8, groundY + 0.12 + i * 0.02, mid.Position.Z + math.random() * 1.6 - 0.8))
				* CFrame.Angles(0, math.rad(math.random(-40, 40)), 0)
				* CFrame.Angles(math.rad(math.random(-8, 8)), 0, math.rad(math.random(-8, 8)))
			TweenService:Create(p, info2, { CFrame = flat, Size = Vector3.new(p.Size.X * 0.9, 0.12, p.Size.Z * 0.55) }):Play()
		end)
		task.delay(2.6, function()
			if p.Parent then
				TweenService:Create(p, TweenInfo.new(1.6), { Transparency = 1 }):Play()
			end
		end)
	end
	-- the lines: slack (they curve), then gone
	for _, d in canopy:GetDescendants() do
		if d:IsA("Beam") then
			d.CurveSize0 = 1.5
			d.CurveSize1 = -1.5
			task.delay(1.6, function()
				for k = 1, 10 do
					if not d.Parent then
						return
					end
					d.Transparency = NumberSequence.new(k / 10)
					task.wait(0.06)
				end
			end)
		end
	end
	task.delay(4.4, function()
		if canopy.Parent then
			canopy:Destroy()
		end
	end)
end

local function giveParachute(player: Player)
	local char = player.Character
	local torso = char and char:FindFirstChild("Torso")
	if not char or not torso or not torso:IsA("BasePart") then
		return
	end
	local old = char:FindFirstChild("Parachute")
	if old then
		old:Destroy()
	end
	char:SetAttribute("ParachuteUntil", workspace:GetServerTimeNow() + Config.ParachuteTime)
	local canopy = Instance.new("Model")
	canopy.Name = "Parachute"
	local colors = { Color3.fromRGB(230, 90, 40), Color3.fromRGB(240, 236, 226) }
	local top = torso.CFrame * CFrame.new(0, 10, 0)
	local rims: { Attachment } = {}
	for i = -4, 4 do
		local seg = Instance.new("Part")
		seg.Name = "Canopy"
		seg.Size = Vector3.new(1.75, 0.22, 7.4)
		seg.Color = colors[(i % 2) + 1]
		seg.Material = Enum.Material.Fabric
		seg.CanCollide = false
		seg.CanQuery = false
		seg.CanTouch = false
		seg.Massless = true
		seg.CastShadow = true
		local a = math.rad(i * 13)
		-- the panels sit on an arc (a dome seen from the front), each tipped to follow it
		seg.CFrame = top * CFrame.new(math.sin(a) * 7.6, (math.cos(a) - 1) * 7.6, 0) * CFrame.Angles(0, 0, -a)
		local w = Instance.new("WeldConstraint")
		w.Part0 = torso
		w.Part1 = seg
		w.Parent = seg
		seg.Parent = canopy
		-- rim attachments: the lines start at the front and back edge of every other panel
		if i % 2 == 0 then
			for _, sz in { -1, 1 } do
				local at = Instance.new("Attachment")
				at.Name = "Rim"
				at.Position = Vector3.new(0, -0.11, sz * 3.5)
				at.Parent = seg
				table.insert(rims, at)
			end
		end
	end
	-- the harness on your back: the lines end on your shoulders
	local shoulders = {}
	for _, sx in { -1, 1 } do
		local at = Instance.new("Attachment")
		at.Name = "ChuteRiser"
		at.Position = Vector3.new(sx * 0.75, 0.95, 0.25)
		at.Parent = torso
		shoulders[sx] = at
	end
	for _, rim in rims do
		local local0 = torso.CFrame:PointToObjectSpace(rim.WorldPosition)
		local shoulder = shoulders[(local0.X >= 0) and 1 or -1]
		local b = Instance.new("Beam")
		b.Name = "Line"
		b.Attachment0 = rim
		b.Attachment1 = shoulder
		b.Width0 = 0.05
		b.Width1 = 0.05
		b.Segments = 1
		b.FaceCamera = true
		b.Color = ColorSequence.new(Color3.fromRGB(225, 225, 220))
		b.LightInfluence = 1
		b.Parent = rim
	end
	-- the harness straps (two dark bands over the shoulders)
	for _, sx in { -1, 1 } do
		local strap = Instance.new("Part")
		strap.Name = "Strap"
		strap.Size = Vector3.new(0.25, 2.05, 1.05)
		strap.Color = Color3.fromRGB(40, 40, 44)
		strap.Material = Enum.Material.Fabric
		strap.CanCollide = false
		strap.CanQuery = false
		strap.CanTouch = false
		strap.Massless = true
		strap.CFrame = torso.CFrame * CFrame.new(sx * 0.55, 0.02, 0)
		local w = Instance.new("WeldConstraint")
		w.Part0 = torso
		w.Part1 = strap
		w.Parent = strap
		strap.Parent = canopy
		strap:SetAttribute("Harness", true)
	end
	canopy.Parent = char
	GoreService.Sound("chuteOpen", torso, 1)
	-- down: when your feet are on something, or the time is up
	task.spawn(function()
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { char }
		local t0 = os.clock()
		while canopy.Parent and torso.Parent and os.clock() - t0 < Config.ParachuteTime do
			task.wait(0.15)
			if os.clock() - t0 > 0.8 and workspace:Raycast(torso.Position, Vector3.new(0, -4.2, 0), rp) then
				break
			end
		end
		if char.Parent then
			char:SetAttribute("ParachuteUntil", nil)
		end
		if canopy.Parent then
			-- the harness comes off with it
			for _, p in canopy:GetChildren() do
				if p:GetAttribute("Harness") then
					p:Destroy()
				end
			end
			collapseParachute(canopy, torso)
		end
		task.delay(4.5, function()
			for _, at in shoulders do
				if at.Parent then
					at:Destroy()
				end
			end
		end)
	end)
end

local function attackerOf(car: Model): Player?
	local id = car:GetAttribute("DriverId") or car:GetAttribute("Runaway") or car:GetAttribute("LastDriverId")
	return typeof(id) == "number" and Players:GetPlayerByUserId(id) or nil
end

function VehicleService.ExitPassenger(player: Player)
	local seat = passengers[player]
	if not seat then
		return
	end
	passengers[player] = nil
	for _, c in seat.conns do
		c:Disconnect()
	end
	seat.weld:Destroy()
	seat.att:Destroy()
	local car = seat.car
	local seatPart = seat.seatPart
	if seatPart and seatPart:GetAttribute("Occupant") == player.UserId then
		seatPart:SetAttribute("Occupant", nil)
	end
	local char = player.Character
	if not char or not char.Parent then
		return
	end
	local bail = isRunaway(car)
	if bail then
		-- a moment longer the body ignores the car it just left (it rushes past)
		task.delay(1.3, function()
			if char.Parent and not char:GetAttribute("InCar") then
				setGroup(char, "Body")
			end
		end)
	else
		setGroup(char, "Body")
	end
	char:SetAttribute("InCar", nil)
	char:SetAttribute("Passenger", nil)
	if char:GetAttribute("Dead") then
		-- a corpse stays with the server
		setPassengerOwner(player, nil)
		return
	end
	-- out on the side of the seat
	local torso = char:FindFirstChild("Torso")
	if seatPart and seatPart.Parent and torso and torso:IsA("BasePart") then
		local side = seatPart:GetAttribute("ExitSide")
		local out = seatPart.CFrame * CFrame.new(3.8 * (typeof(side) == "number" and side or 1), 1.4, 0)
		local yaw = MathUtil.Yaw(MathUtil.SafeUnit(MathUtil.Flat(seatPart.CFrame.LookVector), Vector3.new(0, 0, -1)))
		local target = CFrame.new(out.Position) * CFrame.Angles(0, yaw, 0)
		char:PivotTo(target * torso.CFrame:ToObjectSpace(char:GetPivot()))
	end
	RigBuilder.Restore(char)
	local snap = {}
	local v = car.PrimaryPart and car.PrimaryPart.AssemblyLinearVelocity * (bail and 0.95 or 0.5) or Vector3.zero
	for _, p in char:GetChildren() do
		if p:IsA("BasePart") then
			snap[p.Name] = { p.CFrame, v }
		end
	end
	setPassengerOwner(player, player)
	FXRemote:FireClient(player, { t = "undrag", body = char, snap = snap })
	if bail and seatPart then
		-- jumping out of something fast: you tumble
		local side = seatPart:GetAttribute("ExitSide")
		local kick = seatPart.CFrame.RightVector * (typeof(side) == "number" and side or 1) * Config.BailKick + Vector3.new(0, 1.5, 0)
		FXRemote:FireClient(player, { t = "knock", all = kick, rt = Config.BailRagdoll })
	end
	GoreService.Sound("carDoor", seatPart and (seatPart :: BasePart).Position or Vector3.zero, 1)
end

function VehicleService.EnterPassenger(player: Player, car: Model)
	if drivers[player] or passengers[player] or not car.Parent or not car:GetAttribute("Car") or car:GetAttribute("Wrecked") then
		return
	end
	if car:GetAttribute("DriverId") == player.UserId then
		return
	end
	local char = player.Character
	local torso = char and char:FindFirstChild("Torso") :: BasePart?
	local seatPart = torso and freeSeat(car, torso.Position) or nil
	local seatAtt = seatPart and seatPart:FindFirstChild("SeatAtt")
	if not char or not torso or not seatPart or not seatAtt or char:GetAttribute("Dead") or char:GetAttribute("DraggedBy") or char:GetAttribute("Tied") then
		return
	end
	if (torso.Position - seatPart.Position).Magnitude > Config.CarEnterDistance + 4 then
		return
	end
	OwnershipService.EndDragsBy(player)
	setGroup(char, "Driving")
	local att = Instance.new("Attachment")
	att.Name = "SeatTorsoAtt"
	att.Parent = torso
	local weld = Instance.new("RigidConstraint")
	weld.Name = "SeatWeld"
	weld.Attachment0 = att
	weld.Attachment1 = seatAtt
	weld.Parent = seatPart
	seatPart:SetAttribute("Occupant", player.UserId)
	char:SetAttribute("InCar", true)
	char:SetAttribute("Passenger", true)
	seatPose(char)
	setPassengerOwner(player, driverOf(car))
	local seat: Seat = { car = car, weld = weld, att = att, conns = {}, seatPart = seatPart }
	passengers[player] = seat
	table.insert(seat.conns, char:GetAttributeChangedSignal("Dead"):Connect(function()
		if char:GetAttribute("Dead") then
			VehicleService.ExitPassenger(player)
		end
	end))
	table.insert(seat.conns, char.AncestryChanged:Connect(function()
		if not char:IsDescendantOf(workspace) then
			VehicleService.ExitPassenger(player)
		end
	end))
	table.insert(seat.conns, car.AncestryChanged:Connect(function()
		if not car:IsDescendantOf(workspace) then
			VehicleService.ExitPassenger(player)
		end
	end))
	GoreService.Sound("carDoor", seatPart, 1)
end

function VehicleService.Exit(player: Player)
	if passengers[player] then
		VehicleService.ExitPassenger(player)
		return
	end
	local seat = drivers[player]
	if not seat then
		return
	end
	drivers[player] = nil
	for _, c in seat.conns do
		c:Disconnect()
	end
	seat.weld:Destroy()
	seat.att:Destroy()
	local car = seat.car
	-- leaving something that is moving (or flying): it keeps going without you, and you tumble out
	local runaway = isRunaway(car)
	local isHeli = car:GetAttribute("Heli") == true or car:GetAttribute("Jet") == true
	local runTime = isHeli and Config.RunawayHeliTime or Config.RunawayTime
	if runaway and car:GetAttribute("Jet") then
		task.delay(0.15, giveParachute, player) -- (v2.0) ejection seat
	end
	if car.Parent then
		car:SetAttribute("LastDriverId", player.UserId)
		heliVel[car] = nil
		if runaway then
			car:SetAttribute("Runaway", player.UserId)
			car:SetAttribute("RunawayEnd", workspace:GetServerTimeNow() + runTime)
		end
	end
	if car.Parent and car:GetAttribute("DriverId") == player.UserId then
		car:SetAttribute("DriverId", nil)
	end
	local char = player.Character
	if char then
		if runaway then
			task.delay(1.3, function()
				if char.Parent and not char:GetAttribute("InCar") then
					setGroup(char, "Body")
				end
			end)
		else
			setGroup(char, "Body")
		end
		char:SetAttribute("InCar", nil)
	end
	task.delay(runaway and (runTime + 0.6) or 1.5, function()
		if not car.Parent then
			return
		end
		if car:GetAttribute("Runaway") == player.UserId then
			car:SetAttribute("Runaway", nil)
			car:SetAttribute("RunawayEnd", nil)
		end
		if not car:GetAttribute("DriverId") and car.PrimaryPart then
			OwnershipService.SetOwner(car.PrimaryPart, nil)
			for _, p in passengersOf(car) do
				setPassengerOwner(p, nil)
			end
		end
	end)
end

function VehicleService.Enter(player: Player, car: Model)
	if drivers[player] or not car.Parent or not car:GetAttribute("Car") or car:GetAttribute("Wrecked") then
		return
	end
	local char = player.Character
	local torso = char and char:FindFirstChild("Torso") :: BasePart?
	local seatPart = car:FindFirstChild("DriverSeat") :: BasePart?
	local seatAtt = seatPart and seatPart:FindFirstChild("SeatAtt")
	if not char or not torso or not seatPart or not seatAtt or char:GetAttribute("Dead") then
		return
	end
	if (torso.Position - seatPart.Position).Magnitude > Config.CarEnterDistance + 4 then
		return
	end
	local other = driverOf(car)
	if other and other ~= player and drivers[other] then
		return -- taken
	end
	-- (v2.0) a bot drives it: carjacking (the bot is pulled out first)
	if VehicleService.OnEnter then
		VehicleService.OnEnter(player, car)
	end
	OwnershipService.ReleaseAll(player)
	setGroup(char, "Driving")
	local att = Instance.new("Attachment")
	att.Name = "SeatTorsoAtt"
	att.Parent = torso
	local weld = Instance.new("RigidConstraint")
	weld.Name = "SeatWeld"
	weld.Attachment0 = att
	weld.Attachment1 = seatAtt
	weld.Parent = seatPart
	car:SetAttribute("DriverId", player.UserId)
	car:SetAttribute("Runaway", nil)
	car:SetAttribute("RunawayEnd", nil)
	heliVel[car] = nil
	char:SetAttribute("InCar", true)
	if car.PrimaryPart then
		OwnershipService.SetOwner(car.PrimaryPart, player)
	end
	for _, pass in passengersOf(car) do
		setPassengerOwner(pass, player)
	end
	local seat: Seat = { car = car, weld = weld, att = att, conns = {} }
	drivers[player] = seat
	table.insert(seat.conns, char:GetAttributeChangedSignal("Dead"):Connect(function()
		if char:GetAttribute("Dead") then
			VehicleService.Exit(player)
		end
	end))
	table.insert(seat.conns, char.AncestryChanged:Connect(function()
		if not char:IsDescendantOf(workspace) then
			VehicleService.Exit(player)
		end
	end))
	table.insert(seat.conns, car.AncestryChanged:Connect(function()
		if not car:IsDescendantOf(workspace) then
			VehicleService.Exit(player)
		end
	end))
	GoreService.Sound("door", seatPart, 1)
end

------------------------------------------------------------------------
-- (v2.0) bot drivers (BotDriverService drives; this seats them and checks what they run over)
------------------------------------------------------------------------

-- the wheels: not solid while somebody simulates the suspension, solid when the car is parked
local botRestC0: { [Weld]: CFrame } = {}
function VehicleService.SetWheelsSolid(car: Model, solid: boolean)
	for _, d in car:GetChildren() do
		if d:IsA("BasePart") and string.match(d.Name, "^Wheel_") then
			d.CanCollide = solid
			local weld = d:FindFirstChild("WheelWeld")
			if weld and weld:IsA("Weld") then
				if solid then
					if botRestC0[weld] then
						weld.C0 = botRestC0[weld]
						botRestC0[weld] = nil
					end
				elseif not botRestC0[weld] then
					botRestC0[weld] = weld.C0
				end
			end
		end
	end
	if solid and car.PrimaryPart then
		for _, f in car.PrimaryPart:GetChildren() do
			if f:IsA("VectorForce") then
				f.Force = Vector3.zero
			end
		end
	end
end

-- a bot body into the driver's seat (welded and posed like a player); false = no free seat
function VehicleService.SeatBot(car: Model, body: Model): boolean
	local seatPart = car:FindFirstChild("DriverSeat") :: BasePart?
	local seatAtt = seatPart and seatPart:FindFirstChild("SeatAtt")
	local torso = body:FindFirstChild("Torso") :: BasePart?
	if not seatPart or not seatAtt or not torso or car:GetAttribute("DriverId") or car:GetAttribute("BotDriver") then
		return false
	end
	setGroup(body, "Driving")
	body:PivotTo((seatAtt :: Attachment).WorldCFrame)
	local att = Instance.new("Attachment")
	att.Name = "SeatTorsoAtt"
	att.Parent = torso
	local weld = Instance.new("RigidConstraint")
	weld.Name = "BotSeatWeld"
	weld.Attachment0 = att
	weld.Attachment1 = seatAtt :: Attachment
	weld.Parent = seatPart
	body:SetAttribute("InCar", true)
	car:SetAttribute("BotDriver", body.Name)
	car:SetAttribute("Runaway", nil)
	car:SetAttribute("RunawayEnd", nil)
	seatPose(body)
	if car.PrimaryPart then
		OwnershipService.SetOwner(car.PrimaryPart, nil)
	end
	return true
end

-- the bot out of the seat (thrown out a little when `fling`); the car is parked again
function VehicleService.UnseatBot(car: Model, body: Model?, fling: boolean?)
	local seatPart = car:FindFirstChild("DriverSeat")
	local weld = seatPart and seatPart:FindFirstChild("BotSeatWeld")
	if weld then
		weld:Destroy()
	end
	car:SetAttribute("BotDriver", nil)
	if car.Parent then
		VehicleService.SetWheelsSolid(car, true)
	end
	if not body or not body.Parent then
		return
	end
	local torso = body:FindFirstChild("Torso") :: BasePart?
	local att = torso and torso:FindFirstChild("SeatTorsoAtt")
	if att then
		att:Destroy()
	end
	body:SetAttribute("InCar", nil)
	if torso and seatPart and seatPart:IsA("BasePart") then
		-- out of the door, next to the car (driver's side)
		local side = -seatPart.CFrame.RightVector
		body:PivotTo(CFrame.new(seatPart.Position + side * 4 + Vector3.new(0, 1.5, 0)) * seatPart.CFrame.Rotation)
		if fling then
			DamageService.Blast(body, side * 26 + Vector3.new(0, 14, 0), 1.6)
		end
	end
	task.delay(1.0, function()
		if body.Parent and not body:GetAttribute("InCar") then
			setGroup(body, "Body")
		end
	end)
end

-- what a bot's car hits: the server looks in front of the bumper (players report it for their own car)
local botBox = OverlapParams.new()
botBox.FilterType = Enum.RaycastFilterType.Exclude
function VehicleService.BotRunOver(car: Model, driver: Model?, key: string)
	local chassis = car.PrimaryPart
	if not chassis then
		return
	end
	local v = chassis.AssemblyLinearVelocity
	local speed = v.Magnitude
	if speed < Config.RunOverMinSpeed then
		return
	end
	local cf = chassis.CFrame
	local ext = car:GetExtentsSize()
	local fwd = v:Dot(cf.LookVector) >= 0 and 1 or -1
	local reach = 2 + speed * 0.06
	local center = cf * CFrame.new(0, 0, -fwd * (ext.Z / 2 + reach / 2 - 0.5))
	botBox.FilterDescendantsInstances = driver and { car, driver } or { car }
	local seen = {}
	for _, part in workspace:GetPartBoundsInBox(center, Vector3.new(ext.X + 0.6, 4.5, reach + 1), botBox) do
		local body = DamageService.BodyOf(part)
		if body and not seen[body] then
			seen[body] = true
			if driver and body ~= driver then
				DamageService.MarkBotAttacker(body, driver)
			end
			hitBody(car, nil, "a bot driver", key, driver, part, speed)
		end
	end
end

-- (v2.0) the bot drives it: a player may still get in (G) and throw it out
function VehicleService.IsBotDriven(car: Model): boolean
	return car:GetAttribute("BotDriver") ~= nil
end

------------------------------------------------------------------------
-- damage
------------------------------------------------------------------------

local function setEffects(car: Model, hp: number)
	local max = car:GetAttribute("CarMaxHP") or Config.CarHP
	local hood = car:FindFirstChild("Hood")
	if not hood then
		return
	end
	local smoke = hood:FindFirstChild("EngineSmoke")
	local fire = hood:FindFirstChild("EngineFire")
	if smoke and smoke:IsA("Smoke") then
		smoke.Enabled = hp < max * 0.4
		smoke.Opacity = hp < max * 0.18 and 0.6 or 0.3
	end
	if fire and fire:IsA("Fire") then
		fire.Enabled = hp < max * 0.18
	end
end

function VehicleService.Wreck(car: Model)
	if car:GetAttribute("Wrecked") or not car.PrimaryPart then
		return
	end
	car:SetAttribute("Wrecked", true)
	local chassis = car.PrimaryPart
	local pos = chassis.Position
	local driver = driverOf(car)
	if driver then
		VehicleService.Exit(driver)
	end
	for _, pass in passengersOf(car) do
		VehicleService.ExitPassenger(pass)
	end
	local id = car:GetAttribute("LastDamager")
	local attacker = typeof(id) == "number" and Players:GetPlayerByUserId(id) or nil
	local heliWreck = car:GetAttribute("Heli") == true or car:GetAttribute("Jet") == true
	if heliWreck then
		helis[car] = nil
		jets[car] = nil
		car:SetAttribute("RotorSpeed", 0)
	end
	ExplosionService.Explode(pos + Vector3.new(0, 1, 0), {
		radius = heliWreck and 26 or 19,
		damage = heliWreck and 220 or 160,
		power = heliWreck and 150 or 110,
		attacker = attacker,
		cause = heliWreck and "Helicopter explosion" or "Car explosion",
		ignore = car,
		kind = "car",
	})
	-- fall apart: every panel comes off, everything is burnt
	OwnershipService.SetOwner(chassis, nil)
	for _, d in car:GetDescendants() do
		if d:IsA("WeldConstraint") or d:IsA("Weld") then
			d:Destroy()
		elseif d:IsA("VectorForce") then
			d.Force = Vector3.zero
			d.Enabled = false
		end
	end
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = d.Color:Lerp(Color3.fromRGB(22, 20, 19), 0.78)
			if d.Material ~= Enum.Material.Glass then
				d.Material = Enum.Material.CorrodedMetal
			else
				d.Transparency = 1
				d.CanCollide = false
			end
			d.Massless = false
			if d ~= chassis then
				local out = (d.Position - pos)
				out = out.Magnitude > 0.1 and out.Unit or Vector3.yAxis
				pcall(function()
					d:SetNetworkOwner(nil)
				end)
				d.AssemblyLinearVelocity = (out + Vector3.new(0, 1.2, 0)).Unit * math.random(25, 55)
				d.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 18
			end
		end
	end
	chassis.AssemblyLinearVelocity += Vector3.new(0, 38, 0)
	chassis.AssemblyAngularVelocity += Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 4
	local fire = Instance.new("Fire")
	fire.Size = 9
	fire.Heat = 14
	fire.Parent = chassis
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(40, 38, 36)
	smoke.Opacity = 0.5
	smoke.RiseVelocity = 9
	smoke.Size = 6
	smoke.Parent = chassis
	car:SetAttribute("Car", nil)
	Debris:AddItem(car, 30)
end

------------------------------------------------------------------------
-- tires
------------------------------------------------------------------------

function VehicleService.PopTire(car: Model, name: string)
	local wheel = car:FindFirstChild("Wheel_" .. name)
	if not wheel or not wheel:IsA("BasePart") or wheel:GetAttribute("Popped") or car:GetAttribute("Wrecked") then
		return
	end
	wheel:SetAttribute("Popped", true)
	wheel.Size = Vector3.new(wheel.Size.X, Config.CarPoppedDiameter, Config.CarPoppedDiameter)
	wheel.Color = Color3.fromRGB(16, 16, 17)
	local tread = car:FindFirstChild("Tread_" .. name)
	if tread and tread:IsA("BasePart") then
		tread.Transparency = 1
	end
	GoreService.FX({ t = "boomSmall", p = wheel.Position, d = Vector3.yAxis })
	GoreService.Sound("tirePop", wheel.Position, 1)
	GoreService.Sound("hiss", wheel.Position, 1)
end

-- a loose tire (prop) that gets shot goes flat
local function popPropTire(model: Model)
	local tire = model:FindFirstChild("Tire")
	if not tire or not tire:IsA("BasePart") or model:GetAttribute("Popped") then
		return
	end
	model:SetAttribute("Popped", true)
	tire.Size = Vector3.new(tire.Size.X * 1.18, tire.Size.Y * 0.82, tire.Size.Z * 0.82)
	tire.Color = Color3.fromRGB(18, 18, 19)
	GoreService.Sound("tirePop", tire.Position, 0.9)
	GoreService.Sound("hiss", tire.Position, 0.8)
	GoreService.FX({ t = "boomSmall", p = tire.Position, d = Vector3.yAxis })
end

-- something got shot: a tire?
function VehicleService.OnShotPart(part: BasePart, _player: Player?)
	local m = part:FindFirstAncestorOfClass("Model")
	if not m then
		return
	end
	local name = string.match(part.Name, "^Wheel_(%u%u)$") or string.match(part.Name, "^Tread_(%u%u)$")
	if name and m:GetAttribute("Car") then
		VehicleService.PopTire(m, name)
	elseif part.Name == "Tire" and m.Name == "Tire" then
		popPropTire(m)
	end
end

local spikeParams = OverlapParams.new()
spikeParams.FilterType = Enum.RaycastFilterType.Exclude
local function spikeCheck()
	local f = workspace:FindFirstChild("SpawnedProps")
	if not f then
		return
	end
	for _, car in f:GetChildren() do
		if not car:IsA("Model") or not car:GetAttribute("Car") or not car.PrimaryPart then
			continue
		end
		if car.PrimaryPart.AssemblyLinearVelocity.Magnitude < 4 then
			continue
		end
		spikeParams.FilterDescendantsInstances = { car }
		for _, d in car:GetChildren() do
			local name = string.match(d.Name, "^Wheel_(%u%u)$")
			if name and d:IsA("BasePart") and not d:GetAttribute("Popped") then
				local bottom = d.Position - car.PrimaryPart.CFrame.UpVector * (d.Size.Y * 0.4)
				for _, p in workspace:GetPartBoundsInRadius(bottom, 0.9, spikeParams) do
					if p.CanCollide and HitMath.Sharpness(p) >= 0.6 then
						VehicleService.PopTire(car, name)
						break
					end
				end
			end
		end
	end
end

function VehicleService.Damage(car: Model, amount: number, attacker: Player?)
	if car:GetAttribute("Wrecked") or amount <= 0 then
		return
	end
	local hp = (car:GetAttribute("CarHP") or Config.CarHP) - amount
	car:SetAttribute("CarHP", hp)
	if attacker then
		car:SetAttribute("LastDamager", attacker.UserId)
	end
	setEffects(car, hp)
	if hp <= 0 then
		VehicleService.Wreck(car)
	end
end

------------------------------------------------------------------------
-- helicopter: rotor (spin, chopping, blades coming off) and crashes
------------------------------------------------------------------------

-- a loose blade flies off and hurts whatever it hits fast enough
local function looseBladeDamage(blade: BasePart, attacker: Player?)
	blade.Touched:Connect(function(other)
		if not blade.Parent then
			return
		end
		local body, region = DamageService.BodyOf(other)
		if not body or not region or body:GetAttribute("InCar") then
			return
		end
		local v = blade.AssemblyLinearVelocity.Magnitude
		if v < Config.HeliBladeFlySpeed then
			return
		end
		local now = os.clock()
		if now - (lastBladeBody[body] or 0) < 0.5 then
			return
		end
		lastBladeBody[body] = now
		DamageService.ApplyDamage(body, region, math.min(Config.HeliBladeDamage + v * 0.6, 140), other.Position, {
			cause = "Hit by a flying rotor blade",
			allowSever = true,
			severAt = 40,
			attacker = attacker,
		})
		DamageService.Blast(body, blade.AssemblyLinearVelocity.Unit * 40 + Vector3.new(0, 12, 0), 1.5)
		GoreService.Sound("slash", other.Position, 1)
	end)
end

-- a blade breaks off the hub and flies away (it keeps the rotor's speed)
local function breakBlade(heli: Model, hub: BasePart, rotorSpeed: number)
	local chassis = heli.PrimaryPart
	if not chassis then
		return false
	end
	local candidates: { BasePart } = {}
	for _, d in heli:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("MainBlade") and d:GetAttribute("Loose") == nil then
			table.insert(candidates, d)
		end
	end
	if #candidates == 0 then
		return false
	end
	local blade = candidates[math.random(#candidates)]
	blade:SetAttribute("Loose", true)
	for _, w in heli:GetDescendants() do
		if w:IsA("WeldConstraint") and ((w.Part0 == blade and w.Part1 == hub) or (w.Part1 == blade and w.Part0 == hub)) then
			w:Destroy()
		end
	end
	local axis = hub.CFrame.UpVector
	local rel = blade.Position - hub.Position
	local radial = rel - axis * rel:Dot(axis)
	radial = radial.Magnitude > 0.1 and radial.Unit or hub.CFrame.RightVector
	local tangent = axis:Cross(radial)
	blade.CollisionGroup = "Default"
	blade.Massless = false
	blade.CanCollide = true
	pcall(function()
		blade:SetNetworkOwner(nil)
	end)
	blade.AssemblyLinearVelocity = chassis.AssemblyLinearVelocity + tangent * (rotorSpeed * Config.HeliBladeSpeed * 5.5) + radial * 12 + axis * 6
	blade.AssemblyAngularVelocity = axis * rotorSpeed * Config.HeliBladeSpeed * 0.6
	Debris:AddItem(blade, 25)
	looseBladeDamage(blade, attackerOf(heli))
	heli:SetAttribute("Blades", #candidates - 1)
	GoreService.Sound("metal", blade.Position, 1)
	GoreService.Sound("ricochet", blade.Position, 1)
	return true
end

local function rotorStrike(heli: Model, hub: BasePart, speed: number)
	local chassis = heli.PrimaryPart
	if not chassis then
		return
	end
	local r = Config.HeliRotorRadius
	rotorOverlap.FilterDescendantsInstances = { heli }
	-- (v1.9.1) the disc lies in the HELICOPTER's frame. The hub part itself is turned on its side (its cylinder
	-- axis is vertical), so a box built from the hub's rotation was a tall slab that touched the ground and
	-- tore blades off for no reason.
	local frame = chassis.CFrame
	local hubLocal = frame:PointToObjectSpace(hub.Position)
	local box = CFrame.new(hub.Position) * frame.Rotation
	local parts = workspace:GetPartBoundsInBox(box, Vector3.new(r * 2, 1.2, r * 2), rotorOverlap)
	local attacker = attackerOf(heli)
	local now = os.clock()
	local moving = chassis.AssemblyLinearVelocity.Magnitude > 2 or chassis.AssemblyAngularVelocity.Magnitude > 0.3
	local worldHit: BasePart? = nil
	for _, p in parts do
		local body, region = DamageService.BodyOf(p)
		if body and region then
			if not body:GetAttribute("InCar") then
				local d = frame:PointToObjectSpace(p.Position) - hubLocal
				local flat = Vector3.new(d.X, 0, d.Z).Magnitude
				if flat <= r + 1.2 and flat > 1.1 and math.abs(d.Y) < 1.8 and now - (lastRotorHit[body] or 0) > 0.4 then
					lastRotorHit[body] = now
					DamageService.ApplyDamage(body, region, Config.HeliRotorDamage * (0.5 + 0.5 * speed), p.Position, {
						cause = "Chopped up by a rotor",
						allowSever = true,
						severAt = Config.HeliRotorDamage * 0.6,
						attacker = attacker,
					})
					local out = p.Position - hub.Position
					out = Vector3.new(out.X, 0, out.Z)
					out = out.Magnitude > 0.1 and out.Unit or Vector3.xAxis
					DamageService.Blast(body, out * 70 + Vector3.new(0, 25, 0), 2.5)
					GoreService.Sound("slash", p.Position, 1)
					GoreService.Sound("gore", p.Position, 1)
				end
			end
		elseif
			moving
			and not worldHit
			and speed > 0.5
			and now - (heli:GetAttribute("BornAt") or 0) > 3
			and p.CanCollide
			and p.Size.Magnitude > 2.5
			and (p.Anchored or p.AssemblyMass > 60)
		then
			-- only something solid and real, far enough inside the disc to be reached by a blade
			-- (the point of that part closest to the hub; v2.0: was a call that does not compile)
			local o = p.CFrame:PointToObjectSpace(hub.Position)
			local hs = p.Size * 0.5
			local closest = p.CFrame:PointToWorldSpace(Vector3.new(math.clamp(o.X, -hs.X, hs.X), math.clamp(o.Y, -hs.Y, hs.Y), math.clamp(o.Z, -hs.Z, hs.Z)))
			local d = frame:PointToObjectSpace(closest) - hubLocal
			if Vector3.new(d.X, 0, d.Z).Magnitude <= r - 0.3 and math.abs(d.Y) < 1.0 then
				worldHit = p
			end
		end
	end
	-- the blades hit a wall, a tree, a building: one comes off, the rotor shakes the machine
	if worldHit and now - (lastBladeStrike[heli] or 0) > Config.HeliBladeStrikeCooldown then
		lastBladeStrike[heli] = now
		if worldHit.Anchored and worldHit:GetAttribute("Destructible") then
			ExplosionService.Break(worldHit, chassis.AssemblyLinearVelocity * 0.5 + Vector3.new(0, 6, 0))
		end
		breakBlade(heli, hub, speed)
		VehicleService.Damage(heli, 35, nil)
		chassis.AssemblyAngularVelocity += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 3
	end
end

local function heliStep(dt: number)
	for heli in helis do
		local chassis = heli.PrimaryPart
		if not heli.Parent or not chassis then
			helis[heli] = nil
			heliVel[heli] = nil
			continue
		end
		local wrecked = heli:GetAttribute("Wrecked")
		local blades = heli:GetAttribute("Blades")
		if typeof(blades) ~= "number" then
			blades = Config.HeliBladeCount
		end
		local speed = heli:GetAttribute("RotorSpeed")
		if typeof(speed) ~= "number" then
			speed = 0
		end
		if wrecked then
			speed = 0
		elseif heli:GetAttribute("DriverId") ~= nil and blades > 0 then
			speed = math.min(1, speed + dt / Config.HeliSpinUp)
		else
			-- nobody flies it: the rotor coasts down slowly, drag only
			speed = math.max(0, speed - dt / Config.HeliSpinDown)
		end
		heli:SetAttribute("RotorSpeed", speed)
		if wrecked then
			continue
		end
		local hub = heli:FindFirstChild("RotorHub")
		if speed > 0.25 and blades > 0 and hub and hub:IsA("BasePart") then
			rotorStrike(heli, hub, speed)
		end
		-- crashes: a sudden change of velocity hurts the machine (it blows up much more easily than a car)
		local v = chassis.AssemblyLinearVelocity
		local last = heliVel[heli]
		heliVel[heli] = v
		if last and os.clock() - (heli:GetAttribute("BornAt") or 0) > 2 then
			local dv = (v - last).Magnitude
			if dv >= Config.HeliCrashMin and dv < 400 then
				VehicleService.Damage(heli, (dv - Config.HeliCrashMin) * Config.HeliCrashDamage, nil)
				local hurt = (dv - Config.HeliCrashMin - 12) * Config.CarCrashHurt * 1.4
				if hurt > 0 then
					local occupants: { Player } = {}
					local d = driverOf(heli)
					if d then
						table.insert(occupants, d)
					end
					for _, p in passengersOf(heli) do
						table.insert(occupants, p)
					end
					for _, p in occupants do
						local c = p.Character
						if c and not c:GetAttribute("Dead") then
							DamageService.ApplyDamage(c, "Torso", hurt, nil, { cause = "Helicopter crash", allowSever = false, quiet = true })
							DamageService.ApplyDamage(c, "Head", hurt * 0.5, nil, { cause = "Helicopter crash", allowSever = false, quiet = true })
						end
					end
				end
				GoreService.Sound("carCrash", chassis.Position, math.clamp(dv / 60, 0.4, 1))
			end
		end
	end
end

-- (v2.0) jets: crashes (a hard change of speed hurts it a lot; a jet that hits the ground fast is gone)
local function jetStep(_dt: number)
	for jet in jets do
		local chassis = jet.PrimaryPart
		if not jet.Parent or not chassis or jet:GetAttribute("Wrecked") then
			jets[jet] = nil
			jetVel[jet] = nil
			continue
		end
		local v = chassis.AssemblyLinearVelocity
		local last = jetVel[jet]
		jetVel[jet] = v
		if last and os.clock() - (jet:GetAttribute("BornAt") or 0) > 2 then
			local dv = (v - last).Magnitude
			if dv >= Config.JetCrashMin and dv < 2000 then
				VehicleService.Damage(jet, (dv - Config.JetCrashMin) * Config.JetCrashDamage, nil)
				local d = driverOf(jet)
				local c = d and d.Character
				if c and not c:GetAttribute("Dead") then
					local hurt = (dv - Config.JetCrashMin) * 1.5
					DamageService.ApplyDamage(c, "Torso", hurt, nil, { cause = "Jet crash", allowSever = false, quiet = true })
					DamageService.ApplyDamage(c, "Head", hurt * 0.6, nil, { cause = "Jet crash", allowSever = false, quiet = true })
				end
				GoreService.Sound("carCrash", chassis.Position, math.clamp(dv / 80, 0.4, 1))
			end
		end
	end
end

-- a falling bomb (server stepped, like the rockets): it explodes where it lands
local function dropBomb(origin: Vector3, vel: Vector3, attacker: Player?, ignore: { Instance })
	local bomb = Instance.new("Part")
	bomb.Name = "Bomb"
	bomb.Shape = Enum.PartType.Cylinder
	bomb.Size = Vector3.new(2.2, 0.62, 0.62)
	bomb.Color = Color3.fromRGB(70, 82, 56)
	bomb.Material = Enum.Material.Metal
	bomb.Anchored = true
	bomb.CanCollide = false
	bomb.CanQuery = false
	bomb.CanTouch = false
	bomb.CFrame = CFrame.lookAt(origin, origin + vel) * CFrame.Angles(0, math.rad(90), 0)
	bomb.Parent = workspace:FindFirstChild("FX") or workspace
	GoreService.Sound("bombWhistle", bomb, 1)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = table.clone(ignore)
	table.insert(list, bomb)
	params.FilterDescendantsInstances = list
	local pos = origin
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not bomb.Parent then
			conn:Disconnect()
			return
		end
		if workspace:GetAttribute("TimeStop") then
			t0 += dt
			return
		end
		local ts = TimeScale.Get() -- (v2.8) slow motion
		t0 += dt * (1 - ts)
		dt *= ts
		vel += Vector3.new(0, -TimeScale.Gravity() * 0.5, 0) * dt
		vel *= (1 - 0.15 * dt)
		local step = vel * dt
		local hit = workspace:Raycast(pos, step, params)
		if hit or os.clock() - t0 > 20 then
			conn:Disconnect()
			bomb:Destroy()
			ExplosionService.Explode(hit and hit.Position or pos, {
				radius = Config.JetBombRadius,
				damage = Config.JetBombDamage,
				power = Config.JetBombPower,
				attacker = attacker,
				cause = "Bombed",
				kind = "rocket",
			})
			return
		end
		pos += step
		bomb.CFrame = CFrame.lookAt(pos, pos + vel) * CFrame.Angles(0, math.rad(90), 0)
	end)
end

------------------------------------------------------------------------

function VehicleService.Init()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Car")
		PhysicsService:RegisterCollisionGroup("Driving")
		-- the driver sits inside the car body
		PhysicsService:CollisionGroupSetCollidable("Car", "Driving", false)
		-- driver and passenger sit side by side: their bodies never bump into each other (the
		-- passenger's aiming arms hit the driver's arms and broke both)
		PhysicsService:CollisionGroupSetCollidable("Driving", "Driving", false)
	end)
	pcall(function()
		-- (v2.8) a body in a car rolls over crater rubble like everybody else (the car itself bumps over it)
		PhysicsService:RegisterCollisionGroup("Crater")
		PhysicsService:CollisionGroupSetCollidable("Crater", "Driving", false)
	end)
	ExplosionService.OnCar = VehicleService.Damage

	VehicleRemote.OnServerEvent:Connect(function(player, action, a, b)
		if action == "enter" then
			if typeof(a) == "Instance" and a:IsA("Model") and a:IsDescendantOf(workspace) then
				VehicleService.Enter(player, a)
			end
		elseif action == "exit" then
			VehicleService.Exit(player)
		elseif action == "passenger" then
			if typeof(a) == "Instance" and a:IsA("Model") and a:IsDescendantOf(workspace) then
				VehicleService.EnterPassenger(player, a)
			end
		elseif action == "aim" then
			local now = os.clock()
			if passengers[player] and typeof(a) == "Vector3" and a == a and a.Magnitude < 1e5 and now - (lastAim[player] or 0) > 0.05 then
				lastAim[player] = now
				aimPassenger(player, a)
			end
		elseif action == "turret" or action == "tankfire" then
			-- (v2.8) the tank: the driver turns the turret (a = yaw, b = pitch, from where he looks) and fires a shell (F)
			local seat = drivers[player]
			local tank = seat and seat.car
			if not tank or not tank:GetAttribute("Tank") or tank:GetAttribute("Wrecked") then
				return
			end
			if action == "turret" then
				if typeof(a) ~= "number" or typeof(b) ~= "number" or a ~= a or b ~= b then
					return
				end
				local tw = tank:FindFirstChild("TurretWeld", true)
				local gw = tank:FindFirstChild("GunWeld", true)
				if tw and tw:IsA("Weld") and typeof(tw:GetAttribute("BaseC0")) == "CFrame" then
					tw.C0 = (tw:GetAttribute("BaseC0") :: CFrame) * CFrame.Angles(0, a, 0)
				end
				if gw and gw:IsA("Weld") and typeof(gw:GetAttribute("BaseC0")) == "CFrame" then
					gw.C0 = (gw:GetAttribute("BaseC0") :: CFrame) * CFrame.Angles(math.clamp(b, -0.12, 0.45), 0, 0)
				end
			else
				local now = os.clock()
				if now - (lastTankShot[player] or 0) < Config.TankReload * 0.9 or not VehicleService.OnRocket then
					return
				end
				lastTankShot[player] = now
				tank:SetAttribute("TankReady", workspace:GetServerTimeNow() + Config.TankReload)
				local muzzle = tank:FindFirstChild("TankMuzzle", true)
				if muzzle and muzzle:IsA("Attachment") then
					local ignore: { Instance } = { tank }
					if player.Character then
						table.insert(ignore, player.Character)
					end
					local cf = muzzle.WorldCFrame
					VehicleService.OnRocket(cf.Position, cf.LookVector, player, ignore)
					GoreService.FX({ t = "boom", p = cf.Position + cf.LookVector * 1.5, r = 3, k = "muzzle" })
					GoreService.Sound("explosion", cf.Position, 0.8)
					-- the recoil
					local chassis = tank.PrimaryPart
					if chassis then
						GoreService.FX({ t = "push", part = chassis, i = -cf.LookVector * chassis.AssemblyMass * 6, p = cf.Position })
					end
				end
			end
		elseif action == "heligun" or action == "helirocket" then
			-- the pilot fires the nose gun (F) / a rocket (C) where the crosshair is (within a cone
			-- in front of the helicopter)
			local seat = drivers[player]
			local heli = seat and seat.car
			if not heli or not heli:GetAttribute("Heli") or heli:GetAttribute("Wrecked") or typeof(a) ~= "Vector3" or a ~= a or a.Magnitude < 0.5 then
				return
			end
			local now = os.clock()
			local body = heli.PrimaryPart
			if not body then
				return
			end
			local fwd = body.CFrame.LookVector
			local dir = a.Unit
			if dir:Dot(fwd) < math.cos(math.rad(40)) then
				dir = fwd
			end
			if action == "heligun" then
				if now - (lastHeliGun[player] or 0) < Config.HeliGunInterval * 0.8 then
					return
				end
				lastHeliGun[player] = now
				local muzzle = heli:FindFirstChild("Muzzle", true)
				if muzzle and muzzle:IsA("Attachment") then
					GunService.VehicleShot(player, heli, muzzle.WorldPosition, dir)
				end
			else
				if now - (lastHeliRocket[player] or 0) < Config.HeliRocketCooldown or not VehicleService.OnRocket then
					return
				end
				lastHeliRocket[player] = now
				-- three missiles in the pods, no reload
				local left = heli:GetAttribute("Missiles")
				if typeof(left) ~= "number" then
					left = Config.HeliMissiles
				end
				if left <= 0 then
					GoreService.Sound("dryfire", body.Position, 0.8)
					return
				end
				local idx = Config.HeliMissiles - left + 1
				local origin: Vector3? = nil
				for _, d in heli:GetDescendants() do
					if d:IsA("BasePart") and d:GetAttribute("MissileIdx") == idx then
						if d:GetAttribute("MissileTip") then
							origin = d.Position
						end
						d.Transparency = 1 -- (that missile leaves the rack)
					end
				end
				heli:SetAttribute("Missiles", left - 1)
				local ignore: { Instance } = { heli }
				if player.Character then
					table.insert(ignore, player.Character)
				end
				VehicleService.OnRocket((origin or (body.Position + fwd * 3)) + fwd * 1.8, dir, player, ignore)
			end
		elseif action == "jetgun" or action == "jetmissile" or action == "jetbomb" or action == "throttle" then
			-- (v2.0) the jet: cannon (F), homing missile at the locked target (C), bombs (X), the throttle (for the
			-- afterburner everybody sees)
			local seat = drivers[player]
			local jet = seat and seat.car
			if not jet or not jet:GetAttribute("Jet") or jet:GetAttribute("Wrecked") or not jet.PrimaryPart then
				return
			end
			local body = jet.PrimaryPart
			local now = os.clock()
			local fwd = body.CFrame.LookVector
			if action == "throttle" then
				if typeof(a) == "number" and a == a then
					jet:SetAttribute("Throttle", math.clamp(math.floor(a * 20 + 0.5) / 20, 0, 1))
				end
				return
			end
			if action == "jetbomb" then
				if now - (lastJetBomb[player] or 0) < 0.35 then
					return
				end
				local left = jet:GetAttribute("Bombs") or 0
				if left <= 0 then
					GoreService.Sound("dryfire", body.Position, 0.8)
					return
				end
				lastJetBomb[player] = now
				local idx = Config.JetBombs - left + 1
				local origin = body.Position - body.CFrame.UpVector * 2.4
				for _, d in jet:GetDescendants() do
					if d:IsA("BasePart") and d:GetAttribute("BombIdx") == idx then
						origin = d.Position
						d.Transparency = 1
					end
				end
				jet:SetAttribute("Bombs", left - 1)
				local ignore: { Instance } = { jet }
				if player.Character then
					table.insert(ignore, player.Character)
				end
				dropBomb(origin - body.CFrame.UpVector * 0.8, body.AssemblyLinearVelocity, player, ignore)
				return
			end
			if typeof(a) ~= "Vector3" or a ~= a or a.Magnitude < 0.5 then
				return
			end
			local dir = a.Unit
			if dir:Dot(fwd) < math.cos(math.rad(action == "jetgun" and 12 or 35)) then
				dir = fwd
			end
			if action == "jetgun" then
				if now - (lastJetGun[player] or 0) < Config.JetGunInterval * 0.8 then
					return
				end
				lastJetGun[player] = now
				local muzzle = jet:FindFirstChild("Muzzle", true)
				if muzzle and muzzle:IsA("Attachment") then
					GunService.VehicleShot(player, jet, muzzle.WorldPosition + body.AssemblyLinearVelocity * 0.02, dir)
				end
			else
				if now - (lastJetMissile[player] or 0) < 0.8 or not VehicleService.OnRocket then
					return
				end
				local left = jet:GetAttribute("Missiles") or 0
				if left <= 0 then
					GoreService.Sound("dryfire", body.Position, 0.8)
					return
				end
				lastJetMissile[player] = now
				local idx = Config.JetMissiles - left + 1
				local origin = body.Position + fwd * 4
				for _, d in jet:GetDescendants() do
					if d:IsA("BasePart") and d:GetAttribute("MissileIdx") == idx then
						if d:GetAttribute("MissileTip") then
							origin = d.Position
						end
						d.Transparency = 1
					end
				end
				jet:SetAttribute("Missiles", left - 1)
				-- the lock must be real: something in front of the jet, in range
				local homing: BasePart? = nil
				if typeof(b) == "Instance" and b:IsA("BasePart") and b:IsDescendantOf(workspace) then
					local to = b.Position - origin
					if to.Magnitude < Config.JetLockRange + 60 and to.Unit:Dot(fwd) > math.cos(math.rad(45)) then
						homing = b
					end
				end
				local ignore: { Instance } = { jet }
				if player.Character then
					table.insert(ignore, player.Character)
				end
				VehicleService.OnRocket(origin + fwd * 2, dir, player, ignore, homing, { top = false })
			end
		elseif action == "rotor" then
			-- (v1.9: the server checks the rotor itself, see rotorStep)
			return
		elseif action == "crash" then
			local seat = drivers[player]
			local now = os.clock()
			if seat and not seat.car:GetAttribute("Heli") and typeof(a) == "number" and a == a and a >= Config.CarCrashMin and a <= 400 and now - (lastCrash[player] or 0) > 0.25 then
				lastCrash[player] = now
				VehicleService.Damage(seat.car, (a - Config.CarCrashMin) * Config.CarCrashDamage, nil)
				-- a really hard crash also hurts the people inside (their own bodies do not sense
				-- bumps while they sit: that broke arms on every pothole)
				local hurt = (a - Config.CarCrashMin - 25) * Config.CarCrashHurt
				if hurt > 0 then
					local occupants = { player }
					for p, ps in passengers do
						if ps.car == seat.car then
							table.insert(occupants, p)
						end
					end
					for _, p in occupants do
						local c = p.Character
						if c and not c:GetAttribute("Dead") then
							DamageService.ApplyDamage(c, "Torso", hurt, nil, { cause = "Car crash", allowSever = false, quiet = true })
							DamageService.ApplyDamage(c, "Head", hurt * 0.5, nil, { cause = "Car crash", allowSever = false, quiet = true })
						end
					end
				end
				if seat.car.PrimaryPart then
					GoreService.Sound("carCrash", seat.car.PrimaryPart.Position, math.clamp(a / 80, 0.4, 1))
				end
			end
		elseif action == "runover" then
			local seat = drivers[player]
			if seat then
				runOver(player, seat, a, b)
			end
		elseif action == "smash" then
			-- driving through a breakable wall
			local seat = drivers[player]
			local now = os.clock()
			if not seat or typeof(a) ~= "table" or not seat.car.PrimaryPart or now - (lastSmash[player] or 0) < 0.1 then
				return
			end
			lastSmash[player] = now
			local chassis = seat.car.PrimaryPart
			local v = chassis.AssemblyLinearVelocity
			for i, p in a do
				if i > 24 then
					break
				end
				if typeof(p) == "Instance" and p:IsA("BasePart") and p:GetAttribute("Destructible") and p.Anchored and (p.Position - chassis.Position).Magnitude < 18 then
					ExplosionService.Break(p, v * 0.85 + Vector3.new(0, 6, 0))
				elseif typeof(p) == "Instance" and p:IsA("BasePart") and p:GetAttribute("Fracture") and p.Anchored and ExplosionService.OnFracture
					and v.Magnitude >= Config.CarWallSpeed * 0.8 then
					-- (v2.0) a car through a house wall: a car-sized hole
					local l = p.CFrame:PointToObjectSpace(chassis.Position)
					local h = p.Size * 0.5
					local cp = p.CFrame:PointToWorldSpace(Vector3.new(math.clamp(l.X, -h.X, h.X), math.clamp(l.Y, -h.Y, h.Y), math.clamp(l.Z, -h.Z, h.Z)))
					if (cp - chassis.Position).Magnitude < 14 then
						ExplosionService.OnFracture(p, cp + Vector3.new(0, 1.2, 0), seat.car:GetAttribute("Jet") and 7 or 4.2, v.Unit, v.Magnitude)
						VehicleService.Damage(seat.car, 18, nil)
					end
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		VehicleService.Exit(player)
		lastAim[player] = nil
		lastCrash[player] = nil
		lastSmash[player] = nil
		local prefix = tostring(player.UserId) .. ":"
		for k in lastRunOver do
			if string.sub(k, 1, #prefix) == prefix then
				lastRunOver[k] = nil
			end
		end
	end)

	-- tires on spikes
	task.spawn(function()
		while true do
			task.wait(0.1)
			spikeCheck()
		end
	end)
	-- helicopters: rotor spin / chopping / crashes (about 15 times a second); (v2.0) jets: crashes
	task.spawn(function()
		while true do
			local dt = task.wait(0.066)
			heliStep(dt)
			jetStep(dt)
		end
	end)
	-- cars that fell off the world are removed
	RunService.Heartbeat:Connect(function()
		local f = workspace:FindFirstChild("SpawnedProps")
		if not f then
			return
		end
		for _, m in f:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Car") and m.PrimaryPart and m.PrimaryPart.Position.Y < -200 and not Config.InPit(m.PrimaryPart.Position) then
				local d = driverOf(m)
				if d then
					VehicleService.Exit(d)
				end
				m:Destroy()
			end
		end
	end)
end

return VehicleService
