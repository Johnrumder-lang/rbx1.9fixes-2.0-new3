--!nonstrict
-- SteelBallService (v2.0): the steel balls.
--   F with a ball in your hand throws it: hard and almost straight (Config.SteelBallGravity), a bit of damage where
--   it hits and a little push. Without the Spin it bounces off and lies there - go and pick it up again.
--   With the Spin (the Steel Ball Master's reward, see QuestService) the ball is green and has a yellow trail; whoever
--   it hits is ragdolled and spins in the air for a moment (Config.SpinVictimTime), and the ball comes back to your
--   hand in an arc.
-- The flight is the server's: the item waits out of sight (ReplicatedStorage.InFlight) while every client draws the
-- same straight flight / return arc from the FX messages ("steelball", "ballend", "ballreturn"); the thrower's
-- client draws its own ball at once and gets "ballcatch" to close its hand on the ball that came back.
-- Quests: OnThrow / OnPickup (a ball you threw, picked up again by you) / RecentHit (for the kills).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TimeScale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TimeScale")) -- (v2.8) the Sandevistan's slow motion
local Items = require(Shared:WaitForChild("Items"))

local Modules = script.Parent
local DamageService = require(Modules:WaitForChild("DamageService"))
local GoreService = require(Modules:WaitForChild("GoreService"))
local OwnershipService = require(Modules:WaitForChild("OwnershipService"))

local FXRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("FX") :: RemoteEvent

local SteelBallService = {}

-- set by QuestService
SteelBallService.HasSpin = nil :: ((Player) -> boolean)?
SteelBallService.OnThrow = nil :: ((Player, Model) -> ())?
SteelBallService.OnPickup = nil :: ((Player, Model) -> ())?
-- (the glass a ball flies into; set by Main)
SteelBallService.OnGlass = nil :: ((BasePart, Vector3, Vector3) -> boolean)?

type Flight = {
	id: number,
	item: Model,
	player: Player,
	side: string,
	pos: Vector3,
	vel: Vector3,
	t0: number,
	dist: number,
	phase: string, -- "out" | "back"
	spin: boolean,
	backFrom: Vector3?,
	backT0: number?,
	backDur: number?,
}

local flights: { [number]: Flight } = {}
local lastThrow: { [Player]: number } = {}
local recentHits: { [Model]: { by: Player, t: number } } = setmetatable({}, { __mode = "k" }) :: any
local spinning: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local watched: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local counter = 0
local parked: Folder? = nil
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function parkFolder(): Folder
	if parked and parked.Parent then
		return parked
	end
	local f = ReplicatedStorage:FindFirstChild("InFlight")
	if not f then
		f = Instance.new("Folder")
		f.Name = "InFlight"
		f.Parent = ReplicatedStorage
	end
	parked = f :: Folder
	return f :: Folder
end

local function hasSpin(p: Player): boolean
	return SteelBallService.HasSpin ~= nil and SteelBallService.HasSpin(p) == true
end

local function torsoOf(p: Player): BasePart?
	local c = p.Character
	local t = c and c:FindFirstChild("Torso")
	return (t and t:IsA("BasePart")) and t or nil
end

-- where the ball goes back to: the hand of the arm that threw it
local function handOf(p: Player, side: string): Vector3?
	local c = p.Character
	if not c or c:GetAttribute("Dead") or not p.Parent then
		return nil
	end
	local arm = c:FindFirstChild(side == "Left" and "Left Arm" or "Right Arm")
	if not arm or not arm:IsA("BasePart") or c:GetAttribute("Severed_" .. side .. "Arm") then
		arm = c:FindFirstChild(side == "Left" and "Right Arm" or "Left Arm")
		if not arm or not arm:IsA("BasePart") then
			local t = c:FindFirstChild("Torso")
			return (t and t:IsA("BasePart")) and t.Position or nil
		end
	end
	return (arm :: BasePart).CFrame:PointToWorldSpace(Vector3.new(0, -1.1, -0.3))
end
SteelBallService.HandOf = handOf

-- the return arc (the same formula on every client: SteelBallFX)
function SteelBallService.Arc(a: Vector3, b: Vector3, t: number): Vector3
	local d = (b - a).Magnitude
	local ctrl = (a + b) * 0.5 + Vector3.new(0, d * 0.3 + 5, 0)
	local u = 1 - t
	return a * (u * u) + ctrl * (2 * u * t) + b * (t * t)
end

------------------------------------------------------------------------
-- the look (green with the Spin)
------------------------------------------------------------------------

function SteelBallService.SetLook(item: Model, spin: boolean)
	if (item:GetAttribute("SpinLook") == true) == spin then
		return
	end
	item:SetAttribute("SpinLook", spin)
	for _, d in item:GetDescendants() do
		if d:IsA("BasePart") then
			local base = d:GetAttribute("BaseColor")
			if typeof(base) ~= "Color3" then
				d:SetAttribute("BaseColor", d.Color)
				base = d.Color
			end
			if spin then
				d.Color = d.Name == "Ball" and Config.SpinBallColor or Color3.fromRGB(24, 92, 40)
			else
				d.Color = base
			end
		end
	end
	local root = item.PrimaryPart
	if root then
		local glow = root:FindFirstChild("SpinGlow")
		if spin and not glow then
			local l = Instance.new("PointLight")
			l.Name = "SpinGlow"
			l.Color = Config.SpinBallColor
			l.Range = 6
			l.Brightness = 1.2
			l.Parent = root
		elseif not spin and glow then
			glow:Destroy()
		end
	end
end

-- every steel ball: whoever picks it up decides its look; a ball picked up again by its thrower counts (quest 2)
local function watch(item: Instance)
	if not item:IsA("Model") or watched[item] or Items.Kind(item) ~= "steelball" then
		return
	end
	watched[item] = true
	item:GetAttributeChangedSignal("HolderId"):Connect(function()
		local id = item:GetAttribute("HolderId")
		if typeof(id) ~= "number" or id <= 0 then
			return
		end
		local p = Players:GetPlayerByUserId(id)
		if not p then
			return
		end
		SteelBallService.SetLook(item, hasSpin(p))
		local thrower = item:GetAttribute("ThrownBy")
		if thrower ~= nil then
			item:SetAttribute("ThrownBy", nil)
			if thrower == id and SteelBallService.OnPickup then
				SteelBallService.OnPickup(p, item)
			end
		end
	end)
end

-- the Spin was learned / lost: the balls in that player's hands change colour now
function SteelBallService.Refresh(p: Player)
	for _, item in OwnershipService.HeldItems(p) do
		if Items.Kind(item) == "steelball" then
			SteelBallService.SetLook(item, hasSpin(p))
		end
	end
end

------------------------------------------------------------------------
-- hits
------------------------------------------------------------------------

-- was this body hit by `by`'s ball within Config.SteelBallKillWindow?
function SteelBallService.RecentHit(body: Model, by: Player?): boolean
	local h = recentHits[body]
	return h ~= nil and (by == nil or h.by == by) and os.clock() - h.t <= Config.SteelBallKillWindow
end

-- the Spin: who is hit is ragdolled and spins in the air
function SteelBallService.Spin(body: Model, _by: Player?)
	if DamageService.SpawnProtected(body) or body:GetAttribute("Wonder") == true then
		return
	end
	local state = DamageService.Get(body)
	if not state or state.dead then
		return
	end
	local torso = body:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return
	end
	GoreService.FX({ t = "spinfx", part = torso, d = Config.SpinVictimTime })
	local victim = Players:GetPlayerFromCharacter(body)
	if victim then
		DamageService.Knock(body, nil, nil, Config.SpinVictimTime + 0.4)
		FXRemote:FireClient(victim, { t = "spun", d = Config.SpinVictimTime })
		return
	end
	-- a bot / a dummy: the server spins it
	DamageService.Knock(body, nil, nil, Config.SpinVictimTime + 0.4)
	local fresh = spinning[body] == nil
	spinning[body] = os.clock() + Config.SpinVictimTime
	if not fresh then
		return
	end
	local y0 = torso.Position.Y
	task.spawn(function()
		while body.Parent and torso.Parent and os.clock() < (spinning[body] or 0) do
			if not workspace:GetAttribute("TimeStop") then
				pcall(function()
					local v = torso.AssemblyLinearVelocity
					torso.AssemblyAngularVelocity = Vector3.new(0, Config.SpinVictimSpeed, 0)
					local lift = math.clamp((y0 + Config.SpinVictimLift - torso.Position.Y) * 6, -20, 20)
					torso.AssemblyLinearVelocity = Vector3.new(v.X * 0.9, lift, v.Z * 0.9)
				end)
			end
			RunService.Heartbeat:Wait()
		end
		spinning[body] = nil
	end)
end

------------------------------------------------------------------------
-- the flight
------------------------------------------------------------------------

local function landItem(rec: Flight, pos: Vector3, vel: Vector3)
	local item = rec.item
	item:SetAttribute("InFlight", nil)
	if not item.Parent then
		return -- (cleaned away meanwhile)
	end
	local props = workspace:FindFirstChild("SpawnedProps") or workspace
	item:PivotTo(CFrame.new(pos) * item:GetPivot().Rotation)
	item.Parent = props
	local root = item.PrimaryPart
	if root then
		pcall(function()
			root.AssemblyLinearVelocity = vel
			root.AssemblyAngularVelocity = Vector3.zero
		end)
	end
end

local function finish(rec: Flight)
	flights[rec.id] = nil
end

local function startReturn(rec: Flight, from: Vector3)
	local hand = handOf(rec.player, rec.side)
	if not hand then
		-- nobody to come back to: it drops where it is
		landItem(rec, from, Vector3.zero)
		GoreService.FX({ t = "ballend", id = rec.id, p = from, item = rec.item, by = rec.player.UserId })
		finish(rec)
		return
	end
	rec.phase = "back"
	rec.backFrom = from
	rec.pos = from
	rec.backT0 = os.clock()
	rec.backDur = math.clamp((hand - from).Magnitude / Config.SpinBallReturnSpeed, 0.45, 2.4)
	GoreService.FX({ t = "ballreturn", id = rec.id, a = from, by = rec.player.UserId, side = rec.side, dur = rec.backDur })
end

local function catch(rec: Flight)
	local p = rec.player
	local item = rec.item
	local sides = OwnershipService.HeldItemSides(p)
	local side = rec.side
	if sides[side] then
		side = side == "Left" and "Right" or "Left"
	end
	local hand = handOf(p, side) or rec.pos
	item:SetAttribute("ThrownBy", nil)
	landItem(rec, hand, Vector3.zero)
	GoreService.FX({ t = "ballend", id = rec.id, p = hand, item = item, by = p.UserId })
	GoreService.Sound("steelCatch", hand, 1)
	local char = p.Character
	if not sides[side] and char and not char:GetAttribute("Dead") and item.Parent then
		local root = item.PrimaryPart
		if root then
			OwnershipService.SetOwner(root, p)
		end
		FXRemote:FireClient(p, { t = "ballcatch", item = item, side = side })
	end
	finish(rec)
end

local function onHit(rec: Flight, hit: RaycastResult)
	local part = hit.Instance
	local point = hit.Position
	local dir = rec.vel.Magnitude > 0.1 and rec.vel.Unit or Vector3.zAxis
	local body, region = DamageService.BodyOf(part)
	if body and region and body ~= rec.player.Character then
		local head = region == "Head"
		local dmg = (rec.spin and Config.SpinBallDamage or Config.SteelBallDamage) * (Config.LimbMultiplier[region] or 1)
		if head and Config.SteelBallHeadKill then
			dmg = 1000 -- (v2.0) a headshot: dead on the spot
		end
		recentHits[body] = { by = rec.player, t = os.clock() }
		local protected = DamageService.Protected(body, rec.player) -- (a team mate in a game mode: no push, no spin)
		DamageService.ApplyDamage(body, region, dmg, point, {
			cause = (head and "Headshot with a steel ball (" or "Hit by a steel ball (") .. rec.player.DisplayName .. ")",
			allowSever = false,
			attacker = rec.player,
			quiet = dmg < 10,
		})
		GoreService.Sound(head and "steelHead" or "steelHit", point, 1)
		GoreService.Sound("bodyHit", point, 0.9)
		GoreService.FX({ t = "steelimpact", p = point, n = -dir, body = true, head = head })
		if not protected then
			local mass = DamageService.PartMass(body, region)
			-- (v2.0) way more knockback: the part it hits snaps back hard, the whole body is thrown and goes down
			DamageService.Knock(body, region, dir * Config.SteelBallKnock * mass, Config.SteelBallDownTime, point)
			DamageService.Blast(body, dir * Config.SteelBallLaunch * (head and 1.3 or 1) + Vector3.new(0, Config.SteelBallLaunch * 0.28, 0), Config.SteelBallDownTime)
			if rec.spin then
				SteelBallService.Spin(body, rec.player)
			end
		end
	else
		if part:IsA("BasePart") and part.Material == Enum.Material.Glass and SteelBallService.OnGlass then
			pcall(SteelBallService.OnGlass, part, point, dir)
		end
		-- a loose thing gets a knock
		local root = part:IsA("BasePart") and part.AssemblyRootPart or nil
		if root and not root.Anchored then
			local push = dir * 16 * math.clamp(4 / math.max(root.AssemblyMass, 0.5), 0.15, 1.4) * root.AssemblyMass
			local ok, owner = pcall(function()
				return root:GetNetworkOwner()
			end)
			if ok and owner == nil then
				pcall(function()
					root:ApplyImpulseAtPosition(push, point)
				end)
			else
				GoreService.FX({ t = "push", part = root, i = push, p = point })
			end
		end
		GoreService.Sound("steelHit", point, 1)
		GoreService.FX({ t = "steelimpact", p = point, n = hit.Normal })
	end
	if rec.spin then
		GoreService.FX({ t = "ballend", id = rec.id, p = point, keep = true })
		startReturn(rec, point + hit.Normal * 0.6)
		return
	end
	-- it bounces off and drops
	local n = hit.Normal
	local v = rec.vel
	local bounce = (v - 2 * v:Dot(n) * n) * (body and 0.1 or 0.2)
	landItem(rec, point + n * 0.6, bounce)
	GoreService.FX({ t = "ballend", id = rec.id, p = point, item = rec.item, by = rec.player.UserId })
	finish(rec)
end

local function step(rec: Flight, dt: number)
	if rec.phase == "out" then
		rec.vel += Vector3.new(0, -TimeScale.Gravity() * Config.SteelBallGravity * dt, 0)
		local stepV = rec.vel * dt
		local ignore: { Instance } = {}
		local fx = workspace:FindFirstChild("FX")
		if fx then
			table.insert(ignore, fx)
		end
		local c = rec.player.Character
		if c then
			table.insert(ignore, c)
		end
		for _, it in OwnershipService.HeldItems(rec.player) do
			table.insert(ignore, it)
		end
		params.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(rec.pos, stepV, params)
		if hit then
			onHit(rec, hit)
			return
		end
		rec.pos += stepV
		rec.dist += stepV.Magnitude
		if rec.dist > Config.SteelBallRange or os.clock() - rec.t0 > 5 or (rec.pos.Y < -400 and not Config.InPit(rec.pos)) then
			if rec.spin then
				GoreService.FX({ t = "ballend", id = rec.id, p = rec.pos, keep = true })
				startReturn(rec, rec.pos)
			else
				-- out of breath: from here it just falls
				landItem(rec, rec.pos, rec.vel * 0.5)
				GoreService.FX({ t = "ballend", id = rec.id, p = rec.pos, item = rec.item, by = rec.player.UserId })
				finish(rec)
			end
		end
	else
		local hand = handOf(rec.player, rec.side)
		if not hand then
			landItem(rec, rec.pos, Vector3.zero)
			GoreService.FX({ t = "ballend", id = rec.id, p = rec.pos, item = rec.item, by = rec.player.UserId })
			finish(rec)
			return
		end
		local t = (os.clock() - (rec.backT0 or 0)) / (rec.backDur or 1)
		if t >= 1 then
			catch(rec)
			return
		end
		rec.pos = SteelBallService.Arc(rec.backFrom or rec.pos, hand, t)
	end
end

-- (v2.0) a bot throws a steel ball (gun game, a bot with balls): the same flight and the same hit as a player's
-- throw (every client draws it from the same FX), only the ball is the bot's own and stays in its hand
function SteelBallService.BotThrow(bot: Model, origin: Vector3, dir: Vector3)
	if dir.Magnitude < 0.5 or origin ~= origin then
		return
	end
	counter += 1
	local id = counter
	local vel = dir.Unit * Config.SteelBallSpeed
	GoreService.FX({ t = "steelball", id = id, p = origin, v = vel, by = 0, spin = false })
	GoreService.Sound("steelThrow", origin, 1)
	local bp = RaycastParams.new()
	bp.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { bot }
	local fx = workspace:FindFirstChild("FX")
	if fx then
		table.insert(ignore, fx)
	end
	bp.FilterDescendantsInstances = ignore
	task.spawn(function()
		local pos = origin
		local dist = 0
		local t0 = os.clock()
		while bot.Parent do
			local dt = RunService.Heartbeat:Wait()
			if workspace:GetAttribute("TimeStop") then
				t0 += dt
				continue
			end
			local ts = TimeScale.Get() -- (v2.8) slow motion
			t0 += dt * (1 - ts)
			dt *= ts
			vel += Vector3.new(0, -TimeScale.Gravity() * Config.SteelBallGravity * dt, 0)
			local stepV = vel * dt
			local hit = workspace:Raycast(pos, stepV, bp)
			if hit then
				local point = hit.Position
				local d = vel.Unit
				local body, region = DamageService.BodyOf(hit.Instance)
				if body and region and body ~= bot then
					local head = region == "Head"
					local dmg = Config.SteelBallDamage * (Config.LimbMultiplier[region] or 1)
					if head and Config.SteelBallHeadKill then
						dmg = 1000
					end
					DamageService.MarkBotAttacker(body, bot)
					DamageService.ApplyDamage(body, region, dmg, point, {
						cause = head and "Headshot with a steel ball" or "Hit by a steel ball",
						allowSever = false,
						quiet = dmg < 10,
					})
					GoreService.Sound(head and "steelHead" or "steelHit", point, 1)
					GoreService.Sound("bodyHit", point, 0.9)
					GoreService.FX({ t = "steelimpact", p = point, n = -d, body = true, head = head })
					local mass = DamageService.PartMass(body, region)
					DamageService.Knock(body, region, d * Config.SteelBallKnock * mass, Config.SteelBallDownTime, point)
					DamageService.Blast(body, d * Config.SteelBallLaunch * (head and 1.3 or 1) + Vector3.new(0, Config.SteelBallLaunch * 0.28, 0), Config.SteelBallDownTime)
				else
					if hit.Instance:IsA("BasePart") and hit.Instance.Material == Enum.Material.Glass and SteelBallService.OnGlass then
						pcall(SteelBallService.OnGlass, hit.Instance, point, d)
					end
					GoreService.Sound("steelHit", point, 1)
					GoreService.FX({ t = "steelimpact", p = point, n = hit.Normal })
				end
				GoreService.FX({ t = "ballend", id = id, p = point })
				return
			end
			pos += stepV
			dist += stepV.Magnitude
			if dist > Config.SteelBallRange or os.clock() - t0 > 5 then
				GoreService.FX({ t = "ballend", id = id, p = pos })
				return
			end
		end
		GoreService.FX({ t = "ballend", id = id, p = pos })
	end)
end

-- F: the client let go of the ball and asks for the throw
local function throw(player: Player, item: any, origin: any, dir: any, side: any)
	if typeof(item) ~= "Instance" or not item:IsA("Model") or Items.Kind(item) ~= "steelball" or not item:IsDescendantOf(workspace) then
		return
	end
	if item:GetAttribute("InFlight") then
		return
	end
	if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" or origin ~= origin or dir ~= dir or dir.Magnitude < 0.5 then
		return
	end
	local char = player.Character
	local torso = torsoOf(player)
	if not char or not torso or char:GetAttribute("Dead") then
		return
	end
	local now = os.clock()
	if now - (lastThrow[player] or 0) < Config.SteelBallCooldown * 0.7 then
		return
	end
	if OwnershipService.ItemHolder(item) == player then
		OwnershipService.DropItem(item)
	else
		-- the client let go a moment before this message arrived
		local last = item:GetAttribute("LastHolder")
		local lt = item:GetAttribute("LastHeldT")
		if last ~= player.UserId or typeof(lt) ~= "number" or workspace:GetServerTimeNow() - lt > 1.5 or item:GetAttribute("HolderId") then
			return
		end
	end
	lastThrow[player] = now
	if (origin - torso.Position).Magnitude > 7 then
		origin = torso.Position + torso.CFrame.LookVector * 1.2 + Vector3.new(0, 0.8, 0)
	end
	local s = side == "Left" and "Left" or "Right"
	local spin = hasSpin(player)
	SteelBallService.SetLook(item, spin)
	counter += 1
	item:SetAttribute("InFlight", true)
	item:SetAttribute("ThrownBy", player.UserId)
	item.Parent = parkFolder()
	local rec: Flight = {
		id = counter,
		item = item,
		player = player,
		side = s,
		pos = origin,
		vel = dir.Unit * Config.SteelBallSpeed,
		t0 = now,
		dist = 0,
		phase = "out",
		spin = spin,
	}
	flights[counter] = rec
	GoreService.FX({ t = "steelball", id = counter, p = origin, v = rec.vel, by = player.UserId, spin = spin })
	if SteelBallService.OnThrow then
		SteelBallService.OnThrow(player, item)
	end
end
SteelBallService.Throw = throw

function SteelBallService.Init()
	parkFolder()
	-- (v2.0 fix) EVERY steel ball is watched, wherever it lies: only the spawn menu's balls were (the master's
	-- table, the weapon tables and the armory put theirs elsewhere), so quest 2 counted only some pick-ups
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") then
			watch(d)
		end
	end
	workspace.DescendantAdded:Connect(function(d)
		if d:IsA("Model") and not watched[d] then
			task.defer(watch, d) -- (its Item attribute may be set right after it is parented)
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		if workspace:GetAttribute("TimeStop") then
			-- (time is stopped: the balls hang in the air; a ball on its way back waits too)
			for _, rec in flights do
				if rec.backT0 then
					rec.backT0 += dt
				end
				rec.t0 += dt
			end
			return
		end
		local ts = TimeScale.Get() -- (v2.8) slow motion: the balls crawl
		if ts < 1 then
			for _, rec in flights do
				if rec.backT0 then
					rec.backT0 += dt * (1 - ts)
				end
				rec.t0 += dt * (1 - ts)
			end
			dt *= ts
		end
		for _, rec in flights do
			local ok, err = pcall(step, rec, dt)
			if not ok then
				warn("[steel ball]", err)
				pcall(landItem, rec, rec.pos, Vector3.zero)
				finish(rec)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastThrow[p] = nil
	end)
end

return SteelBallService
