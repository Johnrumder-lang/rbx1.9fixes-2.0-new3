--!nonstrict
-- SuperService (v2.0): the admins' super powers.
--   timestop   : the whole server stops - everything that moves freezes where it is and the colours drain - except
--                the admin who stopped it (and what they hold). Again (or after Config.TimeStopMax) time goes on and
--                everything keeps the speed it had.
--   hotdog     : the player nearest to the admin's crosshair is put on a giant hotdog. It charges, launches, flies
--                round and round the map faster and faster (Mach 1 ... Mach 30+), pulls everybody and everything
--                into its tornado and finally explodes - with the whole map.
--   sun cannon : a heavy device (spawn menu) that always aims at the sun. "Fire" in the admin menu: it charges for
--                Config.SunCharge s, then a giant beam goes into the sun (jumping into the beam vaporises you), the
--                sun swells for Config.SunExpand s and goes supernova: everybody dies.
-- The heavy visuals are drawn by the clients (SuperFX) from the start time and a few numbers, so they are smooth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TimeScale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TimeScale")) -- (v2.8) the Sandevistan's slow motion
local HotdogPath = require(Shared:WaitForChild("HotdogPath"))

local Modules = script.Parent
local DamageService = require(Modules:WaitForChild("DamageService"))
local GoreService = require(Modules:WaitForChild("GoreService"))
local ExplosionService = require(Modules:WaitForChild("ExplosionService"))
local LightingService = require(Modules:WaitForChild("LightingService"))
local PropService = require(Modules:WaitForChild("PropService"))

local SuperService = {}

-- set by Main: the centre / size of the map a position is in (the sandbox or a loaded map)
SuperService.MapAround = nil :: ((Vector3) -> (Vector3, number))?

local function now(): number
	return workspace:GetServerTimeNow()
end

local function torsoOf(p: Player): BasePart?
	local c = p.Character
	local t = c and c:FindFirstChild("Torso")
	return (t and t:IsA("BasePart")) and t or nil
end

-- kill even through God mode / spawn protection (the end of the world)
local function forceKill(model: Model, cause: string)
	model:SetAttribute("ForceKill", true)
	model:SetAttribute("God", nil)
	model:SetAttribute("SpawnProtect", nil)
	DamageService.Kill(model, cause)
end

------------------------------------------------------------------------
-- time stop
------------------------------------------------------------------------

type Stop = { by: Player, parts: { [BasePart]: { v: Vector3, w: Vector3 } }, conn: RBXScriptConnection?, token: number, style: string? }
local stop: Stop? = nil
local stopToken = 0

local function exempt(p: BasePart, by: Player): boolean
	local char = by.Character
	if char and p:IsDescendantOf(char) then
		return true
	end
	-- what the admin holds moves with them: anything joined to their body (an item in the hand is welded to it) and
	-- items marked as theirs. (fix) NOT "everything their machine simulates": Roblox gives a player every loose part near
	-- them, so in a solo test that was the whole map - and time stop froze nothing at all.
	local root = p.AssemblyRootPart
	if char and root and root:IsDescendantOf(char) then
		return true
	end
	local item = p:FindFirstAncestorOfClass("Model")
	while item do
		if item:GetAttribute("HolderId") == by.UserId then
			return true
		end
		item = item:FindFirstAncestorOfClass("Model")
	end
	local fx = workspace:FindFirstChild("FX")
	return fx ~= nil and p:IsDescendantOf(fx) and p.Name ~= "Rocket" and p.Name ~= "FlareShot"
end

function SuperService.TimeStopped(): boolean
	return stop ~= nil
end

-- (v2.8) style "still": STILL CUT (StillCutService) - the clients draw it themselves (SwordClient), not the purple drain
function SuperService.TimeStop(by: Player, on: boolean, style: string?)
	if on and not stop then
		stopToken += 1
		local s: Stop = { by = by, parts = {}, conn = nil, token = stopToken, style = style }
		stop = s
		local function freeze(d: Instance)
			if stop ~= s or not d:IsA("BasePart") or d.Anchored or not d:IsDescendantOf(workspace) then
				return
			end
			if exempt(d, by) then
				return
			end
			s.parts[d] = { v = d.AssemblyLinearVelocity, w = d.AssemblyAngularVelocity }
			d.Anchored = true
		end
		for _, d in workspace:GetDescendants() do
			freeze(d)
		end
		s.conn = workspace.DescendantAdded:Connect(function(d)
			task.defer(freeze, d)
		end)
		workspace:SetAttribute("TimeStop", by.UserId)
		local t = torsoOf(by)
		GoreService.FX({ t = "timestop", on = true, by = by.UserId, p = t and t.Position or Vector3.zero, style = style })
		local my = s.token
		task.delay(Config.TimeStopMax, function()
			if stop and stop.token == my then
				SuperService.TimeStop(by, false)
			end
		end)
	elseif not on and stop then
		local s = stop
		stop = nil
		if s.conn then
			s.conn:Disconnect()
		end
		workspace:SetAttribute("TimeStop", nil)
		for p, rec in s.parts do
			if p.Parent then
				p.Anchored = false
				pcall(function()
					p.AssemblyLinearVelocity = rec.v
					p.AssemblyAngularVelocity = rec.w
				end)
			end
		end
		GoreService.FX({ t = "timestop", on = false, by = s.by.UserId, style = s.style })
	end
end

-- (v2.9) a LOCAL freeze (the STILL CUT): only the bodies and loose things within `radius` of `center` stand still for
-- `duration` s - not the whole server. The one who does it (and what they hold) are exempt. It restores itself.
local localHolds = setmetatable({}, { __mode = "k" })
function SuperService.LocalFreeze(by: Player, center: Vector3, radius: number, duration: number)
	-- Only character bodies in the cast radius. Overlaps extend the hold instead of releasing each other.
	for body in DamageService.Bodies() do
		local root = body:FindFirstChild("Torso")
		if body ~= by.Character and root and root:IsA("BasePart") and not body:GetAttribute("Dead") and (root.Position - center).Magnitude <= radius then
			local untilT = now() + duration
			local hold = localHolds[body]
			if hold then
				hold.untilT = math.max(hold.untilT, untilT)
			else
				hold = { untilT = untilT, parts = {} }
				localHolds[body] = hold
				for _, d in body:GetDescendants() do
					if d:IsA("BasePart") and not d.Anchored then
						hold.parts[d] = { v = d.AssemblyLinearVelocity, w = d.AssemblyAngularVelocity, k = TimeScale.ForField(nil, d.Position) }
						d.Anchored = true
					end
				end
				task.spawn(function()
					while body.Parent and now() < hold.untilT do task.wait(0.05) end
					localHolds[body] = nil
					if body.Parent then body:SetAttribute("TemporalFrozenUntil", nil) end
					for part, velocity in hold.parts do
						if part.Parent then
							part.Anchored = false
							local ratio = Players:GetPlayerFromCharacter(body) and 1 or (TimeScale.ForField(nil, part.Position) / math.max(0.02, velocity.k))
							part.AssemblyLinearVelocity, part.AssemblyAngularVelocity = velocity.v * ratio, velocity.w * ratio
						end
					end
				end)
			end
			body:SetAttribute("TemporalFrozenUntil", hold.untilT)
		end
	end
end

------------------------------------------------------------------------
-- (v2.8) SLOW MOTION (the Sandevistan): the world keeps moving - very slowly - instead of the old freeze-and-step.
--   * the physics: gravity becomes RealGravity x k^2 and every loose thing's speed is multiplied by k (and divided by k
--     again at the end: a crate that was falling goes on falling at full speed). The server simulates every loose thing
--     while it runs (only bodies of players are simulated by their own players, who slow themselves down: CharacterController).
--   * everything moved by script reads TimeScale (rockets, flares, bombs, steel balls, bullets in flight, the Crawler, NPC
--     brains): its time runs k times slower, and at full speed again the moment slow motion ends.
--   * the user lives in normal time (their screen keeps the normal gravity, their body is not slowed).
------------------------------------------------------------------------

-- (v2.8.1) users: everybody whose Sandevistan runs right now - they all live in normal time together (a second one
-- that starts while the first runs joins it instead of being slowed)
type Slow = { by: Player, users: { [Player]: number }, k: number, owned: { [BasePart]: boolean }, skip: { [BasePart]: boolean }, conn: RBXScriptConnection?, token: number, gravity: number }
local slow: Slow? = nil
local slowToken = 0

-- a body that is hit in slow motion: its push is slowed like everything else
function SuperService.SlowMoImpulse(model: Model, vel: Vector3)
	local s = slow
	if not s or Players:GetPlayerFromCharacter(model) or (model:FindFirstChild("Torso") and TimeScale.ForField(nil, model.Torso.Position) == 1) then
		return -- (a player's own machine slows its body: CharacterController)
	end
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and not d.Anchored then
			pcall(function()
				d.AssemblyLinearVelocity += vel * (s.k - 1) -- (the full push was added already: keep only k of it)
			end)
		end
	end
end

function SuperService.SlowMoActive(): boolean
	return slow ~= nil
end

local function playerBodyOf(part: Instance): boolean
	local m = part:FindFirstAncestorOfClass("Model")
	while m do
		if Players:GetPlayerFromCharacter(m) then
			return true
		end
		local h = m:GetAttribute("HolderId")
		if typeof(h) == "number" and h > 0 then
			return true -- (an item in somebody's hand moves with that hand)
		end
		m = m:FindFirstAncestorOfClass("Model")
	end
	return false
end

-- every assembly a player's body is part of (a car with its driver in the seat, a held item): those stay with that player
local function playerRoots(): { [BasePart]: boolean }
	local out = {}
	for _, pl in Players:GetPlayers() do
		local char = pl.Character
		if char then
			for _, d in char:GetChildren() do
				if d:IsA("BasePart") and d.AssemblyRootPart then
					out[d.AssemblyRootPart :: BasePart] = true
				end
			end
		end
	end
	return out
end

local function slowGrab(s: Slow, d: Instance)
	if slow ~= s or not d:IsA("BasePart") or d.Anchored or s.owned[d] then
		return
	end
	if d.AssemblyRootPart ~= d or not d:IsDescendantOf(workspace) or s.skip[d] then
		return
	end
	local mine = false
	for u in s.users do
		if exempt(d, u) then
			mine = true
		end
	end
	if mine or playerBodyOf(d) then
		return
	end
	if workspace:GetAttribute("SlowFieldR") then
		local belongs = false
		for body in DamageService.Bodies() do
			if d:IsDescendantOf(body) then belongs = true; break end
		end
		if not belongs or TimeScale.ForField(nil, d.Position) >= 1 then return end
		local att = Instance.new("Attachment")
		att.Name, att.Parent = "TemporalGravityAttachment", d
		local force = Instance.new("VectorForce")
		force.Name, force.Attachment0, force.RelativeTo, force.ApplyAtCenterOfMass = "TemporalGravity", att, Enum.ActuatorRelativeTo.World, true
		force.Force = Vector3.new(0, workspace.Gravity * (1 - s.k * s.k) * d.AssemblyMass, 0)
		force.Parent = d
	end
	s.owned[d] = true
	pcall(function()
		d:SetNetworkOwner(nil)
	end)
	pcall(function()
		d.AssemblyLinearVelocity *= s.k
		d.AssemblyAngularVelocity *= s.k
	end)
end

local function slowRelease(s: Slow, d: BasePart)
	for _, name in { "TemporalGravity", "TemporalGravityAttachment" } do
		local old = d:FindFirstChild(name)
		if old then old:Destroy() end
	end
	if not d.Parent or d.Anchored then
		return
	end
	pcall(function()
		if d.AssemblyRootPart == d then
			d.AssemblyLinearVelocity /= s.k
			d.AssemblyAngularVelocity /= s.k
			d:SetNetworkOwnershipAuto()
		end
	end)
end

local function publishUsers(s: Slow)
	local ids = {}
	for u in s.users do
		table.insert(ids, tostring(u.UserId))
	end
	workspace:SetAttribute("SlowMoUsers", #ids > 0 and ("," .. table.concat(ids, ",") .. ",") or nil)
end

function SuperService.SlowMo(by: Player, on: boolean)
	-- (v2.8.1) a second Sandevistan while one runs: its user joins the fast side
	if on and slow and not stop then
		local s = slow
		slowToken += 1
		local my = slowToken
		s.users[by] = my
		publishUsers(s)
		task.delay(Config.SandevistanDuration + 3, function()
			if slow == s and s.users[by] == my then
				SuperService.SlowMo(by, false)
			end
		end)
		return
	end
	if not on and slow and slow.users[by] ~= nil then
		local others = 0
		for u in slow.users do
			if u ~= by and u.Parent then
				others += 1
			end
		end
		if others > 0 then
			slow.users[by] = nil
			if slow.by == by then
				slow.by = next(slow.users) :: Player
				workspace:SetAttribute("SlowMo", slow.by.UserId)
			end
			publishUsers(slow)
			return -- (the others still run: the world stays slow)
		end
	elseif not on and slow and slow.users[by] == nil then
		return -- (not one of the users: nothing to stop)
	end
	if on and not slow and not stop then
		slowToken += 1
		local k = math.clamp(Config.SlowMoScale, 0.02, 0.9)
		local s: Slow = { by = by, users = { [by] = slowToken }, k = k, owned = {}, skip = playerRoots(), conn = nil, token = slowToken, gravity = workspace.Gravity }
		slow = s
		workspace:SetAttribute("RealGravity", s.gravity)
		workspace:SetAttribute("SlowScale", k)
		workspace:SetAttribute("SlowMo", by.UserId)
		-- (v2.9) a LOCAL Sandevistan: only players within this radius of a user are slowed (0 / nil = the whole world)
		workspace:SetAttribute("SlowFieldR", Config.SandevistanRadius > 0 and Config.SandevistanRadius or nil)
		publishUsers(s)
		if not workspace:GetAttribute("SlowFieldR") then workspace.Gravity = s.gravity * k * k end
		for _, d in workspace:GetDescendants() do
			slowGrab(s, d)
		end
		s.conn = workspace.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				task.defer(slowGrab, s, d)
			end
		end)
		-- what is let go of while it runs (thrown, dropped) joins the slow world
		task.spawn(function()
			while slow == s do
				task.wait(0.4)
				s.skip = playerRoots()
				for d in s.owned do -- (somebody climbed into a car / picked it up: it is theirs again)
					if slow == s and (s.skip[d] or not d.Parent or (workspace:GetAttribute("SlowFieldR") and TimeScale.ForField(nil, d.Position) >= 1)) then
						s.owned[d] = nil
						slowRelease(s, d)
					end
				end
				for body in DamageService.Bodies() do
					if body.Parent then
						for _, d in body:GetDescendants() do slowGrab(s, d) end
					end
				end
				local props = workspace:FindFirstChild("SpawnedProps")
				for _, m in (props and props:GetChildren() or {}) do
					if slow ~= s then
						break
					end
					for _, d in m:GetDescendants() do
						if d:IsA("BasePart") and not s.owned[d] and d.AssemblyRootPart == d then
							slowGrab(s, d)
						end
					end
				end
			end
		end)
		task.delay(Config.SandevistanDuration + 3, function() -- (a safety: it never stays on)
			if slow and slow.token == s.token then
				SuperService.SlowMo(by, false)
			end
		end)
	elseif not on and slow then
		local s = slow
		slow = nil
		if s.conn then
			s.conn:Disconnect()
		end
		if not workspace:GetAttribute("SlowFieldR") then workspace.Gravity = s.gravity end
		workspace:SetAttribute("SlowMo", nil)
		workspace:SetAttribute("SlowMoUsers", nil)
		workspace:SetAttribute("SlowScale", nil)
		workspace:SetAttribute("RealGravity", nil)
		workspace:SetAttribute("SlowFieldR", nil)
		for d in s.owned do
			slowRelease(s, d)
		end
	end
end

------------------------------------------------------------------------
-- hotdog
------------------------------------------------------------------------

local hotdog: { by: Player, target: Player, info: any, t0: number }? = nil

-- the player closest to where the admin looks (ray from the camera), or nil
function SuperService.PickTarget(by: Player, origin: Vector3, dir: Vector3): Player?
	local best, bestScore = nil, math.huge
	for _, p in Players:GetPlayers() do
		if p ~= by then
			local t = torsoOf(p)
			if t and not p.Character:GetAttribute("Dead") and not p:GetAttribute("InLobby") then
				local to = t.Position - origin
				local along = to:Dot(dir)
				if along > 0 then
					local miss = (to - dir * along).Magnitude
					local ang = math.atan2(miss, along)
					local score = ang + along * 0.0004
					if ang < math.rad(35) and score < bestScore then
						best, bestScore = p, score
					end
				end
			end
		end
	end
	return best
end

function SuperService.Hotdog(by: Player, target: Player)
	if hotdog then
		return -- one at a time
	end
	local t = torsoOf(target)
	local tchar = target.Character
	if not t or not tchar or tchar:GetAttribute("Dead") then
		return
	end
	local center, size = Vector3.new(0, 0, 0), Config.HotdogRadius
	if SuperService.MapAround then
		center, size = SuperService.MapAround(t.Position)
	end
	local info = { start = t.Position, center = center, radius = size, height = Config.HotdogHeight }
	local t0 = now()
	local rec = { by = by, target = target, info = info, t0 = t0 }
	hotdog = rec
	workspace:SetAttribute("Hotdog", target.UserId)
	GoreService.FX({ t = "hotdog", by = by.UserId, target = target.UserId, start = info.start, center = center, radius = size, height = info.height, t0 = t0 })
	-- the one on the hotdog cannot get away (their own client puts them on it); nothing can hurt them before the end
	tchar:SetAttribute("OnHotdog", true)
	local total = Config.HotdogCharge + Config.HotdogFlight
	-- the server pulls what it simulates itself (props, dummies, corpses, NPCs) into the tornado
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if hotdog ~= rec then
			conn:Disconnect()
			return
		end
		if workspace:GetAttribute("TimeStop") then
			rec.t0 += dt -- (time is stopped: so is the hotdog)
			return
		end
		rec.t0 += dt * (1 - TimeScale.Get()) -- (v2.8) slow motion
		local age = now() - rec.t0
		if age >= total then
			conn:Disconnect()
			return
		end
		local pull = HotdogPath.Pull(age)
		if pull <= 0 then
			return
		end
		for _, folderName in { "SpawnedProps", "Dummies", "Corpses", "NPCs" } do
			local f = workspace:FindFirstChild(folderName)
			if f then
				for _, m in f:GetChildren() do
					local root = (m:IsA("Model") and m.PrimaryPart) or (m:IsA("BasePart") and m) or nil
					if root and not root.Anchored and (root.Position - info.center).Magnitude < info.radius * 3 then
						local ok, owner = pcall(function()
							return root:GetNetworkOwner()
						end)
						if ok and owner == nil then
							local want = HotdogPath.Wind(info, age, root.Position)
							local v = root.AssemblyLinearVelocity
							pcall(function()
								root.AssemblyLinearVelocity = v:Lerp(want, math.clamp(pull * dt * 2.5, 0, 1))
							end)
						end
					end
				end
			end
		end
	end)
	task.spawn(function()
		while hotdog == rec and now() - rec.t0 < total do
			task.wait(0.1)
		end
		if hotdog ~= rec then
			return
		end
		local pos = HotdogPath.At(info, total)
		hotdog = nil
		workspace:SetAttribute("Hotdog", nil)
		GoreService.FX({ t = "hotdogboom", p = pos })
		ExplosionService.Nuke(pos, by)
		-- the whole map goes with it: everybody in this map dies
		for _, p in Players:GetPlayers() do
			local c = p.Character
			local tt = torsoOf(p)
			if c and tt and not c:GetAttribute("Dead") and not p:GetAttribute("InLobby") and (p ~= by or not c:GetAttribute("God")) then
				if (tt.Position - info.center).Magnitude < info.radius * 4 + 200 then
					task.delay(math.random() * 0.6, forceKill, c, "Hotdogged at Mach 34")
				end
			end
		end
		tchar:SetAttribute("OnHotdog", nil)
		if SuperService.OnMapBoom then
			SuperService.OnMapBoom(pos, info.radius * 2.5)
		end
	end)
end

-- set by Main: the whole map breaks apart (buildings)
SuperService.OnMapBoom = nil :: ((Vector3, number) -> ())?

------------------------------------------------------------------------
-- sun cannon
------------------------------------------------------------------------

local cannons: { [Model]: boolean } = {}
local sunEvent: { t0: number, by: Player }? = nil

local function sunDir(): Vector3
	local d = Lighting:GetSunDirection()
	return d.Magnitude > 0.01 and d.Unit or Vector3.yAxis
end

local function aimCannons()
	local d = sunDir()
	for m in cannons do
		if not m.Parent then
			cannons[m] = nil
			continue
		end
		local turret = m:FindFirstChild("Turret")
		if turret and turret:IsA("BasePart") then
			local pos = turret.Position
			local cf = CFrame.lookAt(pos, pos + d)
			-- (v2.0) the rotor and the yoke only turn round the upright
			local flat = Vector3.new(d.X, 0, d.Z)
			local yawCF = CFrame.new(pos) * CFrame.Angles(0, flat.Magnitude > 0.01 and math.atan2(-flat.X, -flat.Z) or 0, 0)
			for _, p in m:GetChildren() do
				local off = p:IsA("BasePart") and p:GetAttribute("SunYaw") and p:GetAttribute("YawOff")
				if typeof(off) == "CFrame" then
					(p :: BasePart).CFrame = yawCF * off
				end
			end
			-- (the turret and what is welded to it move together)
			for _, p in m:GetChildren() do
				if p:IsA("BasePart") and p ~= turret then
					local w = p:FindFirstChildOfClass("WeldConstraint")
					if w and (w.Part0 == turret or w.Part1 == turret) then
						p.CFrame = cf * turret.CFrame:ToObjectSpace(p.CFrame)
					end
				end
			end
			turret.CFrame = cf
		end
	end
end

local function registerCannon(m: Model)
	if cannons[m] then
		return
	end
	cannons[m] = true
	-- set down on the ground right where it was spawned
	local base = m.PrimaryPart
	if base then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { m }
		local hit = workspace:Raycast(base.Position + Vector3.new(0, 2, 0), Vector3.new(0, -60, 0), params)
		if hit then
			local bottom = base.Position.Y - base.Size.Y * 0.5
			m:PivotTo(m:GetPivot() + Vector3.new(0, hit.Position.Y - bottom, 0))
		end
	end
	aimCannons()
end

function SuperService.FireSun(by: Player)
	if sunEvent then
		return
	end
	local list = {}
	for m in cannons do
		if m.Parent then
			table.insert(list, m)
		end
	end
	if #list == 0 then
		return
	end
	-- the cannon calls the sun up when it is night
	if sunDir().Y < 0.15 then
		LightingService.SetTime(12)
		task.wait(0.2)
		aimCannons()
	end
	local ev = { t0 = now(), by = by }
	sunEvent = ev
	workspace:SetAttribute("SunCannon", true)
	GoreService.FX({ t = "suncharge", t0 = ev.t0, cannons = list, charge = Config.SunCharge, expand = Config.SunExpand })
	task.spawn(function()
		task.wait(Config.SunCharge)
		if sunEvent ~= ev then
			return
		end
		aimCannons()
		local d = sunDir()
		local beams = {}
		for _, m in list do
			local lens = m:FindFirstChild("Lens")
			if m.Parent and lens and lens:IsA("BasePart") then
				table.insert(beams, { from = lens.Position, dir = d })
			end
		end
		GoreService.FX({ t = "sunbeam", beams = beams, d = Config.SunExpand })
		-- whoever is in a beam is vaporised
		local tEnd = os.clock() + Config.SunExpand
		while os.clock() < tEnd and sunEvent == ev do
			for model in DamageService.Bodies() do
				local torso = model.Parent and model:FindFirstChild("Torso")
				if torso and torso:IsA("BasePart") and not model:GetAttribute("Dead") then
					for _, b in beams do
						local to = torso.Position - b.from
						local along = to:Dot(b.dir)
						if along > 0 and (to - b.dir * along).Magnitude < Config.SunBeamRadius + 1.5 then
							GoreService.FX({ t = "boomSmall", p = torso.Position, d = b.dir })
							forceKill(model, "Vaporized by the sun beam")
						end
					end
				end
			end
			task.wait(0.1)
		end
		if sunEvent ~= ev then
			return
		end
		-- supernova
		GoreService.FX({ t = "supernova" })
		task.wait(1.2)
		for _, p in Players:GetPlayers() do
			local c = p.Character
			if c and not c:GetAttribute("Dead") then
				task.delay(math.random() * 0.8, forceKill, c, "Supernova")
			end
		end
		for model, st in DamageService.Bodies() do
			if not st.player and not model:GetAttribute("Dead") then
				task.delay(math.random(), forceKill, model, "Supernova")
			end
		end
		task.wait(6)
		sunEvent = nil
		workspace:SetAttribute("SunCannon", nil)
		GoreService.FX({ t = "sunreset" })
	end)
end

------------------------------------------------------------------------

function SuperService.Init()
	local prevPlaced = PropService.OnPlaced
	PropService.OnPlaced = function(inst: Instance)
		if prevPlaced then
			prevPlaced(inst)
		end
		if inst:IsA("Model") and inst:GetAttribute("SunCannon") then
			registerCannon(inst)
		end
	end
	task.spawn(function()
		while true do
			task.wait(0.5)
			if next(cannons) then
				aimCannons()
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		if stop and stop.by == p then
			SuperService.TimeStop(p, false)
		end
	end)
	-- the one on the hotdog cannot be hurt before the end
	local prevShield = DamageService.Shield
	DamageService.Shield = function(model, region, dmg, point, opts)
		if model:GetAttribute("OnHotdog") then
			return true
		end
		return prevShield ~= nil and prevShield(model, region, dmg, point, opts) or false
	end
end

return SuperService
