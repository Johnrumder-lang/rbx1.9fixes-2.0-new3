--!nonstrict
-- BotDriverService (v2.0): BOT CARS (owner menu). While it is on and the city is loaded (and no game mode
-- runs), a few bots drive cars round the city.
--   The city is a grid of streets and the build marks every junction ("Junction_<n>"). A bot keeps to the
--   right-hand lane from one junction to the next and picks a way at each one (mostly straight on).
--   The server owns these cars and runs the same CarPhysics a driver's client runs (raycast suspension and
--   tires), so they drive, slide and crash like a player's car.
--   It looks ahead along its lane: it slows down behind a moving car, steers round a parked one (or
--   anything else in the lane, through the other lane if it is free) and stops for people when it can.
--   When it can't, it runs them over (same damage as a player's car).
--   Stuck: it backs up and tries again. Stuck for long, on its roof or far off the street: the bot gets
--   out and walks off (car and bot are cleared later, when nobody is near).
--   A player can take the car (G): the bot is pulled out and runs away. Bots never fight (civilians).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CarPhysics = require(Shared:WaitForChild("CarPhysics"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))

local Modules = script.Parent
local MapService = require(Modules:WaitForChild("MapService"))
local NPCService = require(Modules:WaitForChild("NPCService"))
local VehicleService = require(Modules:WaitForChild("VehicleService"))
local PropService = require(Modules:WaitForChild("PropService"))

local BotDriverService = {}

local UP = Vector3.yAxis
local rng = Random.new()

type Bot = {
	car: Model,
	driver: Model,
	st: any, -- CarPhysics state
	params: RaycastParams,
	from: number, -- junction we come from
	to: number, -- junction we drive to
	dir: Vector3, -- along the street (unit, flat)
	nextTo: number?, -- the junction after `to`
	turn: string, -- at `to`: "straight" | "left" | "right"
	offset: number, -- right of the centre line now
	wantOffset: number,
	dodgeUntil: number, -- along the street (from `from`): back into the lane after this
	input: CarPhysics.Input,
	stuckT: number,
	stuckTotal: number,
	reverseUntil: number,
	revSteer: number,
	frame: number,
	key: string,
	nextThink: number,
	dead: boolean,
	flipT: number,
}

local bots: { [Model]: Bot } = {} -- by car
local walkers: { [Model]: number } = {} -- bots out of their car (and when they got out)
local abandoned: { [Model]: number } = {} -- bot cars nobody drives any more
local junctions: { Vector3 } = {}
local neighbors: { [number]: { number } } = {}
local serial = 0

local scanParams = RaycastParams.new()
scanParams.FilterType = Enum.RaycastFilterType.Exclude
scanParams.RespectCanCollide = true
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
local boxParams = OverlapParams.new()
boxParams.FilterType = Enum.RaycastFilterType.Exclude
boxParams.RespectCanCollide = true

local DRIVER_SHIRTS = {
	Color3.fromRGB(64, 98, 160), Color3.fromRGB(196, 186, 160), Color3.fromRGB(70, 120, 76), Color3.fromRGB(150, 60, 50),
	Color3.fromRGB(230, 230, 226), Color3.fromRGB(46, 46, 52), Color3.fromRGB(196, 140, 52), Color3.fromRGB(110, 74, 130),
}
local SKINS = {
	Color3.fromRGB(234, 196, 160), Color3.fromRGB(204, 160, 130), Color3.fromRGB(160, 112, 80), Color3.fromRGB(110, 74, 52),
}

------------------------------------------------------------------------
-- the street grid
------------------------------------------------------------------------

local function buildGraph()
	table.clear(junctions)
	table.clear(neighbors)
	for _, p in MapService.Points("Junction_") do
		table.insert(junctions, Vector3.new(p.Position.X, 0, p.Position.Z))
	end
	for i, a in junctions do
		local list = {}
		for j, b in junctions do
			local d = b - a
			local ax, az = math.abs(d.X), math.abs(d.Z)
			if i ~= j and ((ax < 1 and az > 60 and az < 200) or (az < 1 and ax > 60 and ax < 200)) then
				-- only the next junction that way (not one further down the same street)
				local dir = MathUtil.SafeUnit(d, Vector3.zero)
				local closer = false
				for k, c in junctions do
					local e = c - a
					if k ~= i and k ~= j and e.Magnitude < d.Magnitude - 1 and MathUtil.SafeUnit(e, Vector3.zero):Dot(dir) > 0.999 then
						closer = true
						break
					end
				end
				if not closer then
					table.insert(list, j)
				end
			end
		end
		neighbors[i] = list
	end
end

local function flatUnit(v: Vector3): Vector3
	return MathUtil.SafeUnit(Vector3.new(v.X, 0, v.Z), Vector3.new(0, 0, -1))
end

-- the next junction after arriving at `at` from `from`: mostly straight on, never back (unless a dead end)
local function pickNext(from: number, at: number): (number, string)
	local inDir = flatUnit(junctions[at] - junctions[from])
	local options, weights, total = {}, {}, 0
	local list: { number } = neighbors[at] or {}
	for _, n in list do
		if n ~= from then
			local d = flatUnit(junctions[n] - junctions[at])
			local w = d:Dot(inDir) > 0.9 and 2.2 or 1
			table.insert(options, n)
			table.insert(weights, w)
			total += w
		end
	end
	if #options == 0 then
		return from, "back"
	end
	local r = rng:NextNumber(0, total)
	local pick = options[#options]
	for i, n in options do
		r -= weights[i]
		if r <= 0 then
			pick = n
			break
		end
	end
	local d = flatUnit(junctions[pick] - junctions[at])
	if d:Dot(inDir) > 0.9 then
		return pick, "straight"
	end
	return pick, (inDir:Cross(d).Y < 0) and "right" or "left"
end

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------

local function nearestPlayer(pos: Vector3): number
	local best = math.huge
	for _, p in Players:GetPlayers() do
		local t = p.Character and p.Character:FindFirstChild("Torso")
		if t and t:IsA("BasePart") then
			best = math.min(best, (t.Position - pos).Magnitude)
		end
	end
	return best
end

local function anyoneInCity(): boolean
	for _, p in Players:GetPlayers() do
		local t = p.Character and p.Character:FindFirstChild("Torso")
		if t and t:IsA("BasePart") and MapService.InMap(t.Position, "city") then
			return true
		end
	end
	return false
end

local function enabled(): boolean
	return workspace:GetAttribute("BotCars") == true and MapService.Current() == "city" and workspace:GetAttribute("Mode") == nil
end

local function botCount(): number
	local n = 0
	for _ in bots do
		n += 1
	end
	return n
end

-- the bot is done driving this car: out it gets (thrown out when `fling`), the car stays parked
local function release(b: Bot, fling: boolean?, scare: number?)
	bots[b.car] = nil
	local driver = b.driver
	if b.car.Parent then
		VehicleService.UnseatBot(b.car, driver, fling)
		if b.car:GetAttribute("BotCar") then
			abandoned[b.car] = os.clock()
		end
	end
	if driver.Parent then
		NPCService.SetSeated(driver, false)
		if scare then
			NPCService.Scare(driver, scare)
		end
		walkers[driver] = os.clock()
	end
end

-- car and bot gone at once (nobody sees it)
local function remove(b: Bot)
	bots[b.car] = nil
	if b.driver.Parent then
		b.driver:Destroy()
	end
	if b.car.Parent then
		b.car:Destroy()
	end
end

------------------------------------------------------------------------
-- spawning
------------------------------------------------------------------------

local function spawnBot(): Bot?
	if #junctions < 2 then
		return nil
	end
	for _ = 1, 14 do
		local a = rng:NextInteger(1, #junctions)
		local nb = neighbors[a]
		if not nb or #nb == 0 then
			continue
		end
		local bIdx = nb[rng:NextInteger(1, #nb)]
		local A, B = junctions[a], junctions[bIdx]
		local len = (B - A).Magnitude
		local dir = flatUnit(B - A)
		local right = dir:Cross(UP)
		local p = A + dir * rng:NextNumber(32, math.max(33, len - 40)) + right * Config.BotCarLane
		local hit = workspace:Raycast(p + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), groundParams)
		if not hit or hit.Normal.Y < 0.9 or not hit.Instance.Anchored or hit.Position.Y > 2 then
			continue -- (the road itself, not the roof of something standing on it)
		end
		local pos = hit.Position + Vector3.new(0, 2.4, 0)
		if nearestPlayer(pos) < 34 then
			continue -- (not right in front of anybody)
		end
		local cf = CFrame.lookAt(pos, pos + dir)
		boxParams.FilterDescendantsInstances = {}
		if #workspace:GetPartBoundsInBox(cf * CFrame.new(0, 0.6, 0), Vector3.new(7.6, 3.6, 15), boxParams) > 0 then
			continue -- (something is in the way)
		end
		local car = PropService.Place("car", cf, nil)
		if not car or not car:IsA("Model") or not car.PrimaryPart then
			if car then
				car:Destroy()
			end
			return nil
		end
		local skin = SKINS[rng:NextInteger(1, #SKINS)]
		local driver = NPCService.Spawn("melee", cf, nil, {
			bot = true,
			civilian = true,
			name = "DRIVER",
			colors = { Head = skin, Arms = skin, Torso = DRIVER_SHIRTS[rng:NextInteger(1, #DRIVER_SHIRTS)], Legs = Color3.fromRGB(40, 44, 58) },
		})
		if not driver then
			car:Destroy()
			return nil
		end
		if not VehicleService.SeatBot(car, driver) then
			car:Destroy()
			driver:Destroy()
			return nil
		end
		NPCService.SetSeated(driver, true)
		VehicleService.SetWheelsSolid(car, false)
		car:SetAttribute("BotCar", true)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.RespectCanCollide = true
		params.FilterDescendantsInstances = { car, driver }
		serial += 1
		local nextTo, turn = pickNext(a, bIdx)
		local b: Bot = {
			car = car,
			driver = driver,
			st = CarPhysics.NewState(),
			params = params,
			from = a,
			to = bIdx,
			dir = dir,
			nextTo = nextTo,
			turn = turn,
			offset = Config.BotCarLane,
			wantOffset = Config.BotCarLane,
			dodgeUntil = -math.huge,
			input = { throttle = 0, steer = 0, brake = false },
			stuckT = 0,
			stuckTotal = 0,
			reverseUntil = 0,
			revSteer = 1,
			frame = 0,
			key = "bot" .. serial,
			nextThink = 0,
			dead = false,
			flipT = 0,
		}
		bots[car] = b
		-- a car that leaves the world / the map takes the bot with it
		car.Destroying:Connect(function()
			if bots[car] == b then
				bots[car] = nil
				if driver.Parent then
					driver:Destroy()
				end
			end
			abandoned[car] = nil
		end)
		return b
	end
	return nil
end

------------------------------------------------------------------------
-- driving
------------------------------------------------------------------------

-- the first thing in a box swept `dist` studs along `dir` from `origin` (at bumper height)
local function sweep(b: Bot, origin: Vector3, dir: Vector3, dist: number, width: number): RaycastResult?
	scanParams.FilterDescendantsInstances = { b.car, b.driver }
	local cf = CFrame.lookAt(origin, origin + dir)
	return workspace:Blockcast(cf, Vector3.new(width, 2.4, 1), dir * dist, scanParams)
end

-- what a hit is: a body, a car (and how fast it goes our way), or something standing there
local function classify(hit: RaycastResult, dir: Vector3): (string, number)
	local inst = hit.Instance
	local m = inst:FindFirstAncestorOfClass("Model")
	while m do
		if m:GetAttribute("RagdollRig") then
			return "body", 0
		end
		if m:GetAttribute("Car") then
			break
		end
		m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
	end
	local v = inst.AssemblyLinearVelocity:Dot(dir)
	if v > 4 then
		return "moving", v
	end
	return "static", v
end

local function advance(b: Bot)
	local arrived = b.to
	local nextTo = b.nextTo or (pickNext(b.from, b.to))
	b.from = arrived
	b.to = nextTo
	b.dir = flatUnit(junctions[nextTo] - junctions[arrived])
	b.nextTo, b.turn = pickNext(arrived, nextTo)
	b.offset = Config.BotCarLane
	b.wantOffset = Config.BotCarLane
	b.dodgeUntil = -math.huge
end

local function think(b: Bot, dt: number)
	local car = b.car
	local chassis = car.PrimaryPart :: BasePart
	local cf = chassis.CFrame
	local pos = cf.Position
	local vel = chassis.AssemblyLinearVelocity
	local fwd = vel:Dot(cf.LookVector)
	local now = os.clock()
	local lane = Config.BotCarLane

	if b.dead then
		b.input = { throttle = 0, steer = 0, brake = vel.Magnitude < 6, coast = vel.Magnitude >= 6 }
		return
	end
	if now < b.reverseUntil then
		b.input = { throttle = -0.75, steer = b.revSteer, brake = false }
		return
	end

	-- where on the street are we
	local A = junctions[b.from]
	local d = b.dir
	local right = d:Cross(UP)
	local rel = Vector3.new(pos.X - A.X, 0, pos.Z - A.Z)
	local s = rel:Dot(d)
	local len = (junctions[b.to] - A).Magnitude
	-- where the two lanes cross at the junction (a right turn: before the middle, a left one: after it)
	local cold = if b.turn == "right" then -lane elseif b.turn == "left" then lane else 0
	if s > len + cold then
		advance(b)
		A = junctions[b.from]
		d = b.dir
		right = d:Cross(UP)
		rel = Vector3.new(pos.X - A.X, 0, pos.Z - A.Z)
		s = rel:Dot(d)
		len = (junctions[b.to] - A).Magnitude
		cold = if b.turn == "right" then -lane elseif b.turn == "left" then lane else 0
	end
	local remain = len - s
	local side = rel:Dot(right)
	if math.abs(side) > 40 then
		b.stuckTotal = math.huge -- (thrown way off the street: it gives up)
		return
	end
	local heading = flatUnit(cf.LookVector)
	local aligned = heading:Dot(d) > 0.94

	-- speed we want
	local want = Config.BotCarCruise
	if b.turn ~= "straight" and remain < 46 then
		want = Config.BotCarTurnSpeed
	end
	if not aligned then
		want = math.min(want, Config.BotCarTurnSpeed)
	end

	-- look ahead along the lane (or along where we point, in a turn)
	local look = math.max(14, 8 + math.max(fwd, 0) * 0.9)
	local frontHalf = 6.6
	local y = pos.Y + 0.2
	local scanDir = aligned and d or heading
	local origin = if aligned
		then Vector3.new(A.X, y, A.Z) + d * (s + frontHalf) + right * b.offset
		else pos + heading * frontHalf + Vector3.new(0, 0.2, 0)
	local hit = sweep(b, origin, scanDir, look, 6.6)
	local brakeHard = false
	if hit then
		local kind, v = classify(hit, scanDir)
		local gap = hit.Distance
		if kind == "moving" then
			-- keep a gap behind it
			want = math.min(want, gap < 9 and 0 or v * math.clamp((gap - 6) / 16, 0.2, 1.1))
		else
			-- in the way: go round it if the other side of the street is free, else stop in front of it
			local dodged = false
			if aligned and remain > 24 then
				for _, o in { 0, -lane } do
					if math.abs(o - b.offset) > 0.5 then
						local o2 = Vector3.new(A.X, y, A.Z) + d * (s + frontHalf) + right * o
						if not sweep(b, o2, d, look + 12, 6.8) then
							b.wantOffset = o
							b.dodgeUntil = s + gap + 22
							dodged = true
							want = math.min(want, 22)
							break
						end
					end
				end
			end
			if not dodged then
				local stopAt = 5 + math.max(fwd, 0) * 0.42
				if gap < stopAt then
					want = 0
					brakeHard = gap < stopAt * 0.6 or kind == "body"
				else
					want = math.min(want, (gap - stopAt) * 1.4 + 4)
				end
			end
		end
	end
	if s > b.dodgeUntil and b.wantOffset ~= lane then
		-- past it: back into the lane (if the lane is free there)
		local o2 = Vector3.new(A.X, y, A.Z) + d * (s + frontHalf) + right * lane
		if not sweep(b, o2, d, 16, 6.6) then
			b.wantOffset = lane
		else
			b.dodgeUntil = s + 8
		end
	end
	b.offset += math.clamp(b.wantOffset - b.offset, -dt * 6, dt * 6)

	-- steer at a point ahead on the lane. At the junction the lane goes round the corner in a quarter
	-- circle (a car can't turn on the spot: without it the bot swung out into the other lane)
	local L = math.clamp(8 + math.abs(fwd) * 0.32, 8, 24)
	local tS = math.max(s, 0) + L
	local corner = len + cold
	local R = if b.turn == "right" then Config.BotCarTurnRadius elseif b.turn == "left" then Config.BotCarTurnRadius - 1 else 0
	local target: Vector3
	if b.nextTo and tS > corner - R then
		local B = junctions[b.to]
		local d2 = flatUnit(junctions[b.nextTo] - B)
		local C = B + d * cold + right * lane
		if R > 0 then
			local uT1 = corner - R
			local arc = math.pi / 2 * R
			if tS > uT1 + arc then
				target = C + d2 * (R + tS - uT1 - arc)
			else
				local O = C - d * R + d2 * R
				local ph = (tS - uT1) / R
				target = O - d2 * (R * math.cos(ph)) + d * (R * math.sin(ph))
			end
		else
			target = C + d2 * (tS - corner)
		end
	else
		target = A + d * tS + right * b.offset
	end
	local loc = cf:PointToObjectSpace(Vector3.new(target.X, pos.Y, target.Z))
	local ang = math.atan2(loc.X, -loc.Z)
	local maxSteer = math.rad(Config.CarMaxSteer) * (1 - 0.55 * math.clamp(math.abs(fwd) / Config.CarMaxSpeed, 0, 1))
	local steer = math.clamp(ang / math.max(maxSteer, 0.05), -1, 1)

	local throttle = math.clamp((want - fwd) / 6, -1, 1)
	local brake = false
	if brakeHard or (want < 0.5 and fwd < 4) then
		throttle = 0
		brake = true
	end
	b.input = { throttle = throttle, steer = steer, brake = brake }

	-- stuck (blocked and nothing to go round, or wedged): back up a little, try again
	if want > 3 and math.abs(fwd) < 1.5 then
		b.stuckT += dt
	elseif want <= 3 then
		b.stuckT += dt * 0.35 -- (waiting for something to move; give up eventually too)
	else
		b.stuckT = math.max(0, b.stuckT - dt * 2)
	end
	if b.stuckT > 3 then
		b.stuckTotal += b.stuckT
		b.stuckT = 0
		b.reverseUntil = now + 1.6
		b.revSteer = rng:NextNumber() < 0.5 and -1 or 1
	end
end

local function step(dt: number)
	local now = os.clock()
	for car, b in bots do
		local chassis = car.PrimaryPart
		if not car.Parent or not chassis then
			bots[car] = nil
			continue
		end
		if car:GetAttribute("Wrecked") then
			release(b, true, 20)
			continue
		end
		if not b.driver.Parent or b.driver:GetAttribute("Dead") then
			if not b.dead then
				b.dead = true
				b.input = { throttle = 0, steer = 0, brake = false, coast = true }
			end
			if chassis.AssemblyLinearVelocity.Magnitude < 2 then
				release(b) -- (the body slumps out of the door)
				continue
			end
		end
		-- somebody holds the car (physics gun): their client simulates it, wait
		local ok, owner = pcall(function()
			return chassis:GetNetworkOwner()
		end)
		if ok and owner ~= nil then
			continue
		end
		if now >= b.nextThink then
			b.nextThink = now + 0.1
			think(b, 0.1)
		end
		b.frame += 1
		CarPhysics.Step(car, dt, b.input, b.st, b.params, b.frame % 3 == 0)
		if b.frame % 6 == 0 and not b.dead then
			VehicleService.BotRunOver(car, b.driver, b.key)
		end
		-- on its roof / stuck for too long: it gets out and walks off
		if chassis.CFrame.UpVector.Y < 0.35 then
			b.flipT += dt
		else
			b.flipT = 0
		end
		if b.flipT > 3 or b.stuckTotal > Config.BotCarStuckTime then
			if nearestPlayer(chassis.Position) > 70 then
				remove(b)
			else
				release(b)
			end
		end
	end
end

------------------------------------------------------------------------
-- upkeep: spawning, clearing up
------------------------------------------------------------------------

local function upkeep()
	local on = enabled()
	if on and #junctions == 0 then
		buildGraph()
	elseif not on and MapService.Current() ~= "city" then
		table.clear(junctions)
	end
	if not on then
		for _, b in bots do
			if nearestPlayer(b.car.PrimaryPart and b.car.PrimaryPart.Position or Vector3.zero) > 70 then
				remove(b)
			else
				release(b)
			end
		end
	elseif botCount() < Config.BotCarMax and anyoneInCity() then
		spawnBot()
	end
	local now = os.clock()
	-- bots that got out: gone once nobody is near (or after a while)
	for m, t0 in walkers do
		if not m.Parent then
			walkers[m] = nil
		elseif not m:GetAttribute("Dead") and now - t0 > 20 then
			local torso = m:FindFirstChild("Torso")
			local far = not torso or nearestPlayer((torso :: BasePart).Position) > 45
			if far or now - t0 > 120 then
				m:Destroy()
				walkers[m] = nil
			end
		elseif m:GetAttribute("Dead") then
			walkers[m] = nil -- (a body: NPCService clears it)
		end
	end
	-- bot cars left standing: gone once nobody is near and nobody took them
	for car, t0 in abandoned do
		if not car.Parent then
			abandoned[car] = nil
		elseif car:GetAttribute("DriverId") or not car:GetAttribute("BotCar") then
			abandoned[car] = nil -- (somebody drives it now: it is theirs)
			car:SetAttribute("BotCar", nil)
		elseif now - t0 > 40 and car.PrimaryPart and nearestPlayer(car.PrimaryPart.Position) > 70 then
			car:Destroy()
			abandoned[car] = nil
		end
	end
end

function BotDriverService.Count(): number
	return botCount()
end

function BotDriverService.Init()
	-- G at a bot's car: the bot is pulled out (and runs), the player drives
	VehicleService.OnEnter = function(_player: Player, car: Model)
		local b = bots[car]
		if b then
			release(b, true, 15)
			car:SetAttribute("BotCar", nil)
			abandoned[car] = nil
		end
	end
	workspace:GetAttributeChangedSignal("MapLoaded"):Connect(function()
		table.clear(junctions)
	end)
	RunService.Heartbeat:Connect(function(dt)
		if next(bots) ~= nil then
			step(math.min(dt, 1 / 20))
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1.25)
			local ok, err = pcall(upkeep)
			if not ok then
				warn("[BotDriverService] " .. tostring(err))
			end
		end
	end)
end

return BotDriverService
