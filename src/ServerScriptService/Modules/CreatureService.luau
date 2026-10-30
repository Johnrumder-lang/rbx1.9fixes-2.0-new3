--!nonstrict
-- CreatureService (v2.0): the things that hunt you on the new maps. The server moves an invisible hit box
-- (the "Torso" of a model in workspace.Creatures, anchored; bullets, blades and blasts hurt it); every client draws
-- the creature itself around it and animates it (CreatureFX).
--   crawler : the horror map's monster. It crawls on floors, walls AND ceilings (it sticks to whatever surface it
--             is on and climbs onto the next one), drops on you from above or leaps at you from a wall. When it gets
--             you it grabs you, holds you up to its jaws, bites your head off - and lets you fall. One roams the
--             asylum whenever the horror map is loaded; the MONSTER game mode brings a stronger one.
--   shark   : in the sea. Circles under the surface (the fin shows), hunts whoever is in the water, bites a limb
--             off and swims away, comes back for more.
-- Creature models carry: Creature = kind, HP, MaxHP, State, Spectatable, DisplayName.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TimeScale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TimeScale")) -- (v2.8) the Sandevistan's slow motion
local Water = require(Shared:WaitForChild("Water"))

local Modules = script.Parent
local DamageService = require(Modules:WaitForChild("DamageService"))
local GoreService = require(Modules:WaitForChild("GoreService"))

local FXRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("FX") :: RemoteEvent

local CreatureService = {}

-- set by GameModeService: may this creature go for that body? (a game mode decides who is fair game)
CreatureService.CanTarget = nil :: ((any, Model) -> boolean)?
-- told when a creature dies (the MONSTER mode ends with it)
CreatureService.OnDeath = nil :: ((any, Player?) -> ())?
-- a creature killed somebody
CreatureService.OnKill = nil :: ((any, Model) -> ())?
-- (v2.0) the Crawler digs: knock a hole of this radius into a part (Main: FractureService); smash a window
CreatureService.OnDig = nil :: ((BasePart, Vector3, number, Vector3) -> boolean)?
CreatureService.OnGlass = nil :: ((BasePart, Vector3, Vector3) -> boolean)?

type Creature = {
	id: number,
	kind: string,
	model: Model,
	root: BasePart,
	head: BasePart?,
	hp: number,
	maxHp: number,
	pos: Vector3,
	up: Vector3,
	fwd: Vector3,
	vel: Vector3,
	state: string,
	stateT: number,
	target: Model?,
	victim: Model?,
	nextThink: number,
	nextPounce: number,
	nextBite: number,
	mapId: string?,
	bounds: (Vector3) -> boolean,
	home: Vector3,
	roamGoal: Vector3?,
	path: { Vector3 }?,
	pathIdx: number,
	pathAt: number,
	stuckRef: Vector3,
	stuckT: number,
	lastHitBy: Player?,
	mode: boolean,
	speedK: number,
	-- (v2.0) the Crawler: what it saw last, who it is angry at, digging, squeezing
	lastSeen: Vector3?,
	lastSeenT: number,
	aggroUntil: number,
	blockedT: number,
	dig: { part: BasePart, point: Vector3, dir: Vector3, untilT: number }?,
	squeezeUntil: number,
	-- (v2.0) never stuck, never long on a wall: when it last had somebody, when it got onto the wall / ceiling,
	-- until when a drop slides off walls instead of sticking to them
	idleSince: number,
	surfaceT: number,
	dropUntil: number,
	stuckDig: boolean,
	nextHop: number,
	roamClimb: boolean?,
}

local creatures: { [Model]: Creature } = {}
local counter = 0
local rng = Random.new()
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true

local CRAWLER_H = 2.1 -- the hit box centre above the surface it crawls on (v2.0: it is much bigger now)
local CRAWLER_LEN = 10
local JAW = Vector3.new(0, 1.8, -(CRAWLER_LEN * 0.5 + 2.4)) -- where it holds what it eats

local function folder(): Folder
	local f = workspace:FindFirstChild("Creatures")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Creatures"
		f.Parent = workspace
	end
	return f :: Folder
end

local function now(): number
	return os.clock()
end

-- everything a creature does not stand on / see through: bodies, items, FX, other creatures
local function ignoreList(extra: { Instance }?): { Instance }
	local list: { Instance } = { folder() }
	for _, n in { "FX", "SpawnedProps", "Corpses", "Gibs", "Dummies", "NPCs" } do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(list, f)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	if extra then
		for _, e in extra do
			table.insert(list, e)
		end
	end
	return list
end

local function cast(from: Vector3, dir: Vector3): RaycastResult?
	return workspace:Raycast(from, dir, params)
end

local function setCF(c: Creature)
	local up = c.up
	local f = c.fwd - up * c.fwd:Dot(up)
	if f.Magnitude < 0.05 then
		f = up:Cross(Vector3.xAxis)
		if f.Magnitude < 0.05 then
			f = up:Cross(Vector3.zAxis)
		end
	end
	f = f.Unit
	c.fwd = f
	local right = f:Cross(up)
	local cf = CFrame.fromMatrix(c.pos, right, up)
	c.root.CFrame = cf
	if c.head then
		c.head.CFrame = cf * CFrame.new(0, 0.9, -(CRAWLER_LEN * 0.5 + 1.5))
	end
	if c.kind == "crawler" then
		local sq = now() < c.squeezeUntil
		if (c.model:GetAttribute("Squeeze") == true) ~= sq then
			c.model:SetAttribute("Squeeze", sq or nil)
		end
	end
end

local function setState(c: Creature, s: string)
	if c.state ~= s then
		c.state = s
		c.stateT = now()
		c.model:SetAttribute("State", s)
	end
end

local function hitbox(model: Model, name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = true
	p.CanTouch = false
	p.Transparency = 1
	p.CastShadow = false
	p.Parent = model
	return p
end

------------------------------------------------------------------------
-- spawning
------------------------------------------------------------------------

function CreatureService.Spawn(kind: string, pos: Vector3, opts: any?): Model
	opts = opts or {}
	counter += 1
	local model = Instance.new("Model")
	model.Name = kind == "crawler" and "The Crawler" or "Shark"
	model:SetAttribute("Creature", kind)
	model:SetAttribute("Spectatable", true)
	model:SetAttribute("DisplayName", kind == "crawler" and "THE CRAWLER" or "SHARK")
	local root, head
	if kind == "crawler" then
		root = hitbox(model, "Torso", Vector3.new(4.2, 2.8, CRAWLER_LEN))
		head = hitbox(model, "Head", Vector3.new(2.8, 2.6, 2.8))
		head:SetAttribute("Weak", true)
	else
		root = hitbox(model, "Torso", Vector3.new(2.4, 2.4, 8.5))
	end
	model.PrimaryPart = root
	local hp = opts.hp or (kind == "crawler" and Config.CrawlerHP or Config.SharkHP)
	model:SetAttribute("HP", hp)
	model:SetAttribute("MaxHP", hp)
	model:SetAttribute("State", "roam")
	local c: Creature = {
		id = counter,
		kind = kind,
		model = model,
		root = root,
		head = head,
		hp = hp,
		maxHp = hp,
		pos = pos,
		up = Vector3.yAxis,
		fwd = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit,
		vel = Vector3.zero,
		state = "roam",
		stateT = now(),
		target = nil,
		victim = nil,
		nextThink = 0,
		nextPounce = now() + 3,
		nextBite = now() + 2,
		mapId = opts.mapId,
		bounds = opts.bounds or function()
			return true
		end,
		home = pos,
		roamGoal = nil,
		path = nil,
		pathIdx = 1,
		pathAt = 0,
		stuckRef = pos,
		stuckT = now(),
		lastHitBy = nil,
		mode = opts.mode == true,
		speedK = opts.speedK or 1,
		lastSeen = nil,
		lastSeenT = 0,
		aggroUntil = 0,
		blockedT = 0,
		dig = nil,
		squeezeUntil = 0,
		idleSince = now(),
		surfaceT = now(),
		dropUntil = 0,
		stuckDig = false,
		nextHop = 0,
		roamClimb = false,
	}
	if kind == "crawler" then
		-- start on whatever is under the spawn point
		local hit = cast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -30, 0))
		if hit then
			c.pos = hit.Position + hit.Normal * CRAWLER_H
			c.up = hit.Normal
		end
	end
	if opts.mode then
		model:SetAttribute("ModeCreature", true)
	end
	model.Parent = folder()
	creatures[model] = c
	setCF(c)
	return model
end

function CreatureService.All(): { [Model]: any }
	return creatures
end

function CreatureService.Remove(model: Model)
	creatures[model] = nil
	if model.Parent then
		model:Destroy()
	end
end

-- (v2.0) gone at the end of a round: it lets go of whoever it holds and fades out (CreatureFX), then it is removed
function CreatureService.Despawn(model: Model)
	local c = creatures[model]
	if not c then
		if model.Parent then
			model:Destroy()
		end
		return
	end
	if c.state == "dead" then
		return -- (it is dying already: it curls up, sinks and goes by itself)
	end
	local v = c.victim
	c.victim = nil
	if v then
		FXRemote:FireAllClients({ t = "ungrab", body = v })
	end
	if c.state ~= "dead" then
		setState(c, "gone")
	end
	model:SetAttribute("Despawn", true)
	task.delay(1.6, function()
		if creatures[model] == c then
			CreatureService.Remove(model)
		end
	end)
end

function CreatureService.RemoveWhere(fn: (any) -> boolean)
	for m, c in creatures do
		if fn(c) then
			CreatureService.Remove(m)
		end
	end
end

------------------------------------------------------------------------
-- damage
------------------------------------------------------------------------

local function die(c: Creature, by: Player?)
	if c.state == "dead" then
		return
	end
	setState(c, "dead")
	c.model:SetAttribute("Dead", true)
	c.model:SetAttribute("HP", 0)
	local v = c.victim
	c.victim = nil
	if v then
		FXRemote:FireAllClients({ t = "ungrab", body = v })
	end
	GoreService.Sound(c.kind == "crawler" and "monsterScreech" or "splash", c.pos, 1)
	GoreService.Burst(c.pos, c.up, 40, 22)
	if CreatureService.OnDeath then
		task.spawn(CreatureService.OnDeath, c, by)
	end
	local m = c.model
	task.delay(c.kind == "crawler" and 8 or 10, function()
		if creatures[m] == c then
			CreatureService.Remove(m)
		end
	end)
end

-- a bullet / a blade / a blast hit a creature's hit box
function CreatureService.Damage(model: Model, part: Instance?, dmg: number, by: Player?, point: Vector3?)
	local c = creatures[model]
	if not c or c.state == "dead" or dmg <= 0 then
		return
	end
	if part and part:IsA("BasePart") and part:GetAttribute("Weak") then
		dmg *= 2 -- (its head)
	end
	c.hp -= dmg
	c.lastHitBy = by or c.lastHitBy
	model:SetAttribute("HP", math.max(0, c.hp))
	if point then
		GoreService.Burst(point, (point - c.pos).Magnitude > 0.1 and (point - c.pos).Unit or c.up, math.clamp(dmg * 0.25, 3, 20), 12)
	end
	-- (v2.0) whoever hurt it last is the one it goes for - it stays angry at them for a while, even behind walls
	if by and by.Character and not by.Character:GetAttribute("Dead") then
		c.aggroUntil = now() + Config.CrawlerAggroTime
		if c.state ~= "eat" and c.target ~= by.Character then
			c.target = by.Character
			if c.kind == "crawler" then
				GoreService.Sound("monsterScreech", c.pos, 0.8)
			end
		end
	end
	if c.hp <= 0 then
		die(c, by)
	end
end

-- explosions: everything in the radius
function CreatureService.Blast(pos: Vector3, radius: number, by: Player?)
	for m, c in creatures do
		local d = (c.pos - pos).Magnitude
		if d < radius + 4 then
			CreatureService.Damage(m, c.root, Config.CreatureBlastDamage * math.clamp(1 - d / (radius + 4), 0.2, 1), by, c.pos)
		end
	end
end

------------------------------------------------------------------------
-- who to hunt
------------------------------------------------------------------------

local function bodyCandidates(): { Model }
	local list = {}
	for _, p in Players:GetPlayers() do
		local ch = p.Character
		if ch and not ch:GetAttribute("Dead") and not p:GetAttribute("InLobby") then
			table.insert(list, ch)
		end
	end
	local npcs = workspace:FindFirstChild("NPCs")
	if npcs then
		for _, m in npcs:GetChildren() do
			if m:IsA("Model") and not m:GetAttribute("Dead") then
				table.insert(list, m)
			end
		end
	end
	return list
end

local function torsoOf(m: Model): BasePart?
	local t = m:FindFirstChild("Torso")
	return (t and t:IsA("BasePart")) and t or nil
end

local function fair(c: Creature, m: Model): boolean
	if m:GetAttribute("God") or m:GetAttribute("Wonder") == true or DamageService.SpawnProtected(m) then
		return false
	end
	local t = torsoOf(m)
	if not t or not c.bounds(t.Position) then
		return false
	end
	if CreatureService.CanTarget then
		local ok = CreatureService.CanTarget(c, m)
		if ok == false then
			return false
		end
	end
	return true
end

local function pickTarget(c: Creature, range: number, inWater: boolean?): Model?
	local best, bestD = nil, math.huge
	for _, m in bodyCandidates() do
		if not fair(c, m) then
			continue
		end
		local t = torsoOf(m) :: BasePart
		if inWater then
			local d = Water.Depth(t.Position)
			if not d or d < -1.2 then
				continue
			end
		end
		local dist = (t.Position - c.pos).Magnitude
		if dist < range and dist < bestD then
			best, bestD = m, dist
		end
	end
	return best
end

------------------------------------------------------------------------
-- the crawler
------------------------------------------------------------------------

local function crawlerPath(c: Creature, goal: Vector3)
	if now() - c.pathAt < 1.2 then
		return
	end
	c.pathAt = now()
	task.spawn(function()
		local path = PathfindingService:CreatePath({ AgentRadius = 1.4, AgentHeight = 2.4, AgentCanJump = true, AgentCanClimb = true, WaypointSpacing = 5 })
		local ok = pcall(function()
			path:ComputeAsync(c.pos - c.up * CRAWLER_H, goal)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			local pts = {}
			for _, w in path:GetWaypoints() do
				table.insert(pts, w.Position)
			end
			c.path = pts
			c.pathIdx = math.min(2, #pts)
		else
			c.path = nil
		end
	end)
end

local function visible(c: Creature, t: BasePart): boolean
	local from = c.root.CFrame:PointToWorldSpace(Vector3.new(0, 1.2, -CRAWLER_LEN * 0.5))
	local hit = cast(from, t.Position - from)
	return hit == nil or (hit.Position - t.Position).Magnitude < 2.5
end

-- (v2.0) what it can see (or hear right next to it): it does not go for what is behind walls
local function pickSeen(c: Creature, range: number): Model?
	local best, bestD = nil, math.huge
	for _, m in bodyCandidates() do
		if not fair(c, m) then
			continue
		end
		local t = torsoOf(m) :: BasePart
		local dist = (t.Position - c.pos).Magnitude
		if dist < range and dist < bestD and (dist < Config.CrawlerHear or visible(c, t)) then
			best, bestD = m, dist
		end
	end
	return best
end

local function grab(c: Creature, victim: Model)
	c.victim = victim
	setState(c, "eat")
	GoreService.Sound("monsterScreech", c.pos, 1)
	local vp = Players:GetPlayerFromCharacter(victim)
	local off = JAW
	DamageService.Knock(victim, nil, nil, Config.CrawlerEatTime + 1.5)
	if vp then
		FXRemote:FireClient(vp, { t = "grabbed", part = c.root, off = off, d = Config.CrawlerEatTime })
	end
	FXRemote:FireAllClients({ t = "crawlergrab", body = victim, part = c.root })
end

local function eatStep(c: Creature)
	local v = c.victim
	local t0 = c.stateT
	local age = now() - t0
	if not v or not v.Parent then
		c.victim = nil
		setState(c, "chase")
		return
	end
	-- a bot / a dummy: the server holds it at the jaws (a player's own client does that: "grabbed")
	local tt = torsoOf(v)
	if tt and not Players:GetPlayerFromCharacter(v) then
		local jaw = c.root.CFrame:PointToWorldSpace(JAW)
		pcall(function()
			tt.AssemblyLinearVelocity = (jaw - tt.Position) * 10
		end)
	end
	if age >= Config.CrawlerEatTime * 0.65 and not v:GetAttribute("Severed_Head") then
		-- the bite
		local head = v:FindFirstChild("Head")
		local point = (head and head:IsA("BasePart")) and head.Position or c.pos
		DamageService.ApplyDamage(v, "Head", 999, point, { allowSever = true, severAt = 1, cause = "Eaten by the Crawler" })
		GoreService.Sound("crunch", point, 1)
		GoreService.Burst(point, c.up, 60, 26)
		if head and head:IsA("BasePart") then
			-- (it swallowed it)
			head.Transparency = 1
			head.CanCollide = false
			head.CanQuery = false
			for _, d in head:GetDescendants() do
				if d:IsA("Decal") or d:IsA("Texture") then
					d:Destroy()
				elseif d:IsA("BasePart") then
					d.Transparency = 1
				end
			end
			for _, acc in v:GetChildren() do
				if acc:IsA("Accessory") then
					acc:Destroy()
				end
			end
		end
		if CreatureService.OnKill then
			task.spawn(CreatureService.OnKill, c, v)
		end
	end
	if age >= Config.CrawlerEatTime then
		-- and lets you fall
		FXRemote:FireAllClients({ t = "ungrab", body = v })
		c.victim = nil
		c.target = nil
		c.nextPounce = now() + 2.5
		setState(c, "chase")
	end
end

-- move along the surface it is on, climbing onto walls / ceilings in the way and around edges
local function crawl(c: Creature, goal: Vector3, speed: number, dt: number, climb: boolean?)
	local up = c.up
	local to = goal - c.pos
	local dir = to - up * to:Dot(up)
	if dir.Magnitude < 0.3 then
		return
	end
	dir = dir.Unit
	c.fwd = c.fwd:Lerp(dir, math.min(1, dt * 6))
	local step = speed * dt
	-- something in the way: climb onto it
	local reach = step + CRAWLER_LEN * 0.5 + 0.4
	local ahead = cast(c.pos, dir * reach)
	if ahead and ahead.Instance:IsA("BasePart") and ahead.Instance.Material == Enum.Material.Glass and CreatureService.OnGlass then
		-- (v2.0) a window: straight through it
		pcall(CreatureService.OnGlass, ahead.Instance, ahead.Position, dir)
		ahead = cast(c.pos, dir * reach)
	end
	if ahead and ahead.Normal:Dot(up) < 0.6 and c.state == "chase" then
		-- (v2.0) a gap in it - a window, a door left ajar, a crack: it squeezes through instead of climbing
		local right = dir:Cross(up)
		for _, off in { up * 1.4, up * 2.6, right * 1.6, -right * 1.6, up * 3.8, right * 2.8, -right * 2.8 } do
			if cast(c.pos, off) == nil and cast(c.pos + off, dir * (reach + 3)) == nil then
				c.pos += off * math.min(1, dt * 7)
				c.pos += dir * step * 0.6
				c.squeezeUntil = now() + 0.7
				return
			end
		end
	end
	if ahead and ahead.Normal:Dot(up) < 0.6 and climb == false and up.Y > 0.7 then
		-- (v2.0) who it wants is down here: it does not go up the wall, it slides along it
		local along = dir - ahead.Normal * dir:Dot(ahead.Normal)
		along = along - up * along:Dot(up)
		if along.Magnitude > 0.2 then
			c.pos += along.Unit * step * 0.8
			local below0 = cast(c.pos + up * 0.6, -up * (CRAWLER_H + 2.6))
			if below0 then
				c.pos = below0.Position + below0.Normal * CRAWLER_H
			end
			return
		end
	end
	if ahead and ahead.Normal:Dot(up) < 0.6 then
		local oldUp = up
		if c.up.Y > 0.7 and ahead.Normal.Y <= 0.7 then
			c.surfaceT = now() -- (onto a wall: the clock for coming down again starts)
		end
		c.up = ahead.Normal
		c.pos = ahead.Position + ahead.Normal * CRAWLER_H
		local f = dir - c.up * dir:Dot(c.up)
		c.fwd = f.Magnitude > 0.2 and f.Unit or oldUp
		return
	end
	c.pos += dir * step
	-- stick to the surface below
	local below = cast(c.pos + up * 0.6, -up * (CRAWLER_H + 2.6))
	if below then
		c.pos = below.Position + below.Normal * CRAWLER_H
		c.up = up:Lerp(below.Normal, 0.5).Unit
		return
	end
	-- an edge: wrap round it (v2.0: unless it should stay down - then it simply drops off the edge)
	local around = climb ~= false and cast(c.pos - up * (CRAWLER_H + 0.8), -dir * 3.5) or nil
	if around then
		c.up = around.Normal
		c.pos = around.Position + around.Normal * CRAWLER_H
		c.fwd = -up
		return
	end
	-- nothing: it drops
	c.vel = dir * speed * 0.3
	setState(c, "fall")
end

local function fly(c: Creature, dt: number)
	c.vel += Vector3.new(0, -TimeScale.Gravity() * 0.8 * dt, 0)
	local stepV = c.vel * dt
	-- a pounce that reaches its target
	local t = c.target and torsoOf(c.target)
	if c.state == "pounce" and t and (t.Position - c.pos).Magnitude < 4 and fair(c, c.target :: Model) then
		grab(c, c.target :: Model)
		return
	end
	local hit = cast(c.pos, stepV + (stepV.Magnitude > 0.01 and stepV.Unit * CRAWLER_H or Vector3.zero))
	if hit and hit.Normal.Y < 0.6 and now() < c.dropUntil then
		-- (v2.0) coming down on purpose: walls on the way down do not catch it, it slides off them
		c.vel -= hit.Normal * math.min(0, c.vel:Dot(hit.Normal)) * 1.1
		c.pos = hit.Position + hit.Normal * (CRAWLER_H + 0.15)
		return
	end
	if hit then
		c.up = hit.Normal
		c.pos = hit.Position + hit.Normal * CRAWLER_H
		c.vel = Vector3.zero
		GoreService.Sound("thud", c.pos, 0.8)
		setState(c, c.target and "chase" or "roam")
		return
	end
	c.pos += stepV
	if c.vel.Magnitude > 1 then
		c.fwd = c.vel.Unit
	end
	if c.pos.Y < -250 and not Config.InPit(c.pos) then
		die(c, nil)
	end
end

-- (v2.0) off the wall / the ceiling, down towards where it wants to be
local function dropToward(c: Creature, goal: Vector3?)
	local flat = Vector3.zero
	if goal then
		local d = goal - c.pos
		flat = Vector3.new(d.X, 0, d.Z)
		flat = flat.Magnitude > 0.5 and flat.Unit * math.min(flat.Magnitude * 1.5, 22) or Vector3.zero
	end
	c.vel = c.up * 7 + flat
	c.pos += c.up * 0.8
	c.dropUntil = now() + 1.5
	setState(c, "fall")
end

local function pounce(c: Creature, t: BasePart)
	local to = t.Position - c.pos
	local dist = to.Magnitude
	local flight = math.clamp(dist / 62, 0.25, 1.1)
	-- a throw that lands on them (gravity compensated)
	local g = TimeScale.Gravity() * 0.8
	c.vel = to / flight + Vector3.new(0, 0.5 * g * flight, 0)
	c.pos += c.up * 0.8
	c.nextPounce = now() + Config.CrawlerPounceCooldown
	setState(c, "pounce")
	GoreService.Sound("monsterLeap", c.pos, 1)
end

-- (v2.0) dig: a wall / a ceiling / a floor between it and who it wants - it claws a hole and goes through
local function startDig(c: Creature, t: BasePart | Vector3): boolean
	if not CreatureService.OnDig then
		return false
	end
	local goal = typeof(t) == "Vector3" and t or (t :: BasePart).Position
	local from = c.pos + c.up * 0.6
	local hit = cast(from, (goal - from).Unit * math.min((goal - from).Magnitude, CRAWLER_LEN * 0.5 + 12))
	if not hit or not hit.Instance:IsA("BasePart") then
		return false
	end
	local part = hit.Instance :: BasePart
	if not part.Anchored or part.Name == "Baseplate" or part:GetAttribute("NoDig") then
		return false
	end
	local sz = part.Size
	if math.min(sz.X, sz.Y, sz.Z) > Config.CrawlerDigMaxThick then
		return false -- (too thick: solid rock, a pillar)
	end
	local dir = (goal - from).Unit
	c.dig = { part = part, point = hit.Position, dir = dir, untilT = now() + Config.CrawlerDigTime }
	c.fwd = dir
	setState(c, "dig")
	GoreService.Sound("monsterGrowl", c.pos, 1)
	return true
end

local function digStep(c: Creature)
	local d = c.dig
	if not d then
		setState(c, "chase")
		return
	end
	-- claws at it (noise while it digs; the clients throw the debris)
	if rng:NextNumber() < 0.08 then
		GoreService.Sound("monsterDig", d.point, 0.9)
	end
	if now() < d.untilT then
		return
	end
	c.dig = nil
	local part = d.part
	if part.Parent and CreatureService.OnDig then
		if not part:GetAttribute("Fracture") then
			part:SetAttribute("Fracture", true) -- (any thin wall, floor or ceiling of the map gives way to it)
		end
		local ok = CreatureService.OnDig(part, d.point, Config.CrawlerDigRadius, d.dir)
		GoreService.Sound("concreteBreak", d.point, 1)
		if ok then
			-- through the hole
			if math.abs(d.dir.Y) > 0.6 then
				-- up / down through a ceiling or a floor
				c.vel = d.dir * 46 + Vector3.new(0, d.dir.Y > 0 and 30 or 0, 0)
				c.pos += d.dir * 1.5
				setState(c, "fall")
				return
			end
			c.pos += d.dir * 2
		end
	end
	c.blockedT = now()
	setState(c, "chase")
end

local function crawlerThink(c: Creature)
	local t = c.target and torsoOf(c.target)
	if not c.target or not t or not fair(c, c.target) or c.target:GetAttribute("Dead") then
		c.target = nil
		-- (v2.0) the last one who hurt it first, then what it sees
		local by = c.lastHitBy
		local ch = by and by.Character
		if ch and now() < c.aggroUntil and fair(c, ch) and not ch:GetAttribute("Dead") then
			c.target = ch
		else
			c.target = pickSeen(c, Config.CrawlerSense)
		end
		if not c.target and now() - c.idleSince > Config.CrawlerHuntAfter then
			-- (v2.0) nobody for a while: it picks somebody on the map and hunts them down, walls or not
			c.target = pickTarget(c, math.huge)
			if c.target then
				c.aggroUntil = now() + Config.CrawlerHuntTime
				GoreService.Sound("monsterScreech", c.pos, 1)
			end
		end
		if c.target then
			c.lastSeenT = now()
			c.blockedT = now()
			GoreService.Sound("monsterGrowl", c.pos, 1)
		end
	elseif t then
		-- (v2.0) it only keeps after what it can see - or who it is angry at; out of sight too long: it forgets
		if visible(c, t) then
			c.lastSeen = t.Position
			c.lastSeenT = now()
		elseif now() - c.lastSeenT > Config.CrawlerForget and now() > c.aggroUntil then
			c.target = nil
			c.lastSeen = nil
		end
	end
	if c.target then
		c.idleSince = now()
	end
	setState(c, c.target and "chase" or "roam")
	-- (v2.0) roaming on a wall / the ceiling for a while: down again
	if not c.target and c.up.Y < 0.7 and now() - c.surfaceT > 5 then
		dropToward(c, c.home)
		return
	end
	-- (v2.0) stuck: dig towards where it wants to go; then leap that way; then slip out further along its way
	if (c.pos - c.stuckRef).Magnitude > 4 then
		c.stuckRef = c.pos
		c.stuckT = now()
		c.stuckDig = false
		return
	end
	local stuck = now() - c.stuckT
	local tt = c.target and torsoOf(c.target)
	local goal = (tt and tt.Position) or c.roamGoal or c.home
	if stuck > 2.2 and not c.stuckDig then
		c.stuckDig = true
		if startDig(c, goal) then
			return
		end
	end
	if stuck > Config.CrawlerUnstuckAfter then
		c.stuckT = now()
		c.stuckRef = c.pos
		c.stuckDig = false
		-- a point further along its path (or near home): it is simply there next (out of a vent, round a corner)
		local p = c.path
		local spot: Vector3 = c.home
		if p and #p >= 2 then
			spot = p[math.min(#p, math.max(c.pathIdx + 3, math.floor(#p * 0.5)))]
		end
		local hit = cast(spot + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0))
		c.pos = hit and (hit.Position + hit.Normal * CRAWLER_H) or (spot + Vector3.new(0, CRAWLER_H, 0))
		c.up = hit and hit.Normal or Vector3.yAxis
		c.path = nil
		c.vel = Vector3.zero
		return
	end
	if stuck > 4 and now() >= c.nextHop then
		-- a leap towards where it wants to go (a little sideways each time)
		c.nextHop = now() + 1.8
		local flat = Vector3.new(goal.X - c.pos.X, 0, goal.Z - c.pos.Z)
		flat = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit
		c.vel = (flat * 0.8 + Vector3.new(0, 1.1, 0) + Vector3.new(rng:NextNumber(-0.5, 0.5), 0, rng:NextNumber(-0.5, 0.5))).Unit * 46
		c.pos += c.up * 1
		c.dropUntil = now() + 0.6
		setState(c, "fall")
	end
end

local function crawlerStep(c: Creature, dt: number)
	local s = c.state
	if s == "dead" or s == "gone" then
		return
	end
	if s == "eat" then
		eatStep(c)
		return
	end
	if s == "dig" then
		digStep(c)
		return
	end
	if s == "fall" or s == "pounce" then
		fly(c, dt)
		return
	end
	if now() >= c.nextThink then
		c.nextThink = now() + 0.4
		crawlerThink(c)
	end
	local speed = (c.state == "chase" and Config.CrawlerSpeed or Config.CrawlerSpeed * 0.45) * c.speedK
	local tm = c.target
	local t = tm and torsoOf(tm)
	if tm and t then
		local to = t.Position - c.pos
		local dist = to.Magnitude
		-- in reach: grab
		if dist < Config.CrawlerReach then
			grab(c, tm)
			return
		end
		local seen = visible(c, t)
		-- above them (ceiling / wall) or a few strides away: drop / leap on them
		if now() > c.nextPounce and dist < Config.CrawlerPounceRange and seen then
			local below = c.up.Y < -0.5 and (Vector3.new(to.X, 0, to.Z).Magnitude < 8)
			local onWall = math.abs(c.up.Y) < 0.6
			if below or onWall or (dist > 12 and rng:NextNumber() < 0.45) then
				pounce(c, t)
				return
			end
		end
		if c.up.Y < 0.7 and (t.Position.Y < c.pos.Y + 2 or not seen) and now() - c.surfaceT > 0.5 then
			-- (v2.0) on a wall / the ceiling and they are down there (or out of sight): straight down to them
			dropToward(c, t.Position)
			return
		end
		if seen then
			c.blockedT = now()
		elseif now() - c.blockedT > Config.CrawlerDigAfter and dist < 140 and startDig(c, t) then
			-- (v2.0) no way round: through the wall
			return
		end
		-- on the floor and it can't see them: follow a path
		local goal = t.Position
		if c.up.Y > 0.7 and not seen then
			crawlerPath(c, t.Position)
			local p = c.path
			if p and p[c.pathIdx] then
				local wp = p[c.pathIdx] + Vector3.new(0, CRAWLER_H, 0)
				if (wp - c.pos).Magnitude < 3 then
					c.pathIdx += 1
				end
				goal = p[math.min(c.pathIdx, #p)] + Vector3.new(0, CRAWLER_H, 0)
			end
		else
			c.path = nil
		end
		-- (v2.0) up a wall only when they are up there
		crawl(c, goal, speed, dt, t.Position.Y > c.pos.Y + 4)
	else
		-- roam: wander about, now and then up a wall
		if not c.roamGoal or (c.roamGoal - c.pos).Magnitude < 5 or now() - c.stateT > 12 then
			c.roamGoal = c.home + Vector3.new(rng:NextNumber(-60, 60), rng:NextNumber(0, 10), rng:NextNumber(-60, 60))
			c.stateT = now()
			c.roamClimb = rng:NextNumber() < 0.35
		end
		crawl(c, c.roamGoal :: Vector3, speed, dt, c.roamClimb == true)
	end
	if not c.bounds(c.pos) then
		-- (never leaves its map: back home)
		c.pos = c.home
		c.up = Vector3.yAxis
		setState(c, "fall")
	end
end

------------------------------------------------------------------------
-- sharks
------------------------------------------------------------------------

local function sharkStep(c: Creature, dt: number)
	if c.state == "dead" then
		-- belly up, floating
		local surf = Water.SurfaceAt(c.pos)
		if surf and c.pos.Y < surf - 0.6 then
			c.pos += Vector3.new(0, 2 * dt, 0)
		end
		c.up = c.up:Lerp(-Vector3.yAxis, math.min(1, dt * 2)).Unit
		return
	end
	if now() >= c.nextThink then
		c.nextThink = now() + 0.5
		local t = c.target and torsoOf(c.target)
		local okT = t and fair(c, c.target :: Model) and not (c.target :: Model):GetAttribute("Dead")
		if okT then
			local d = Water.Depth((t :: BasePart).Position)
			okT = d ~= nil and d > -1.5
		end
		if not okT then
			c.target = pickTarget(c, Config.SharkSense, true)
		end
		if c.state ~= "flee" or now() - c.stateT > Config.SharkFleeTime then
			setState(c, c.target and "hunt" or "circle")
		end
	end
	local surf = Water.SurfaceAt(c.pos) or (c.home.Y + 6)
	local goal: Vector3
	local speed = Config.SharkSpeed
	local t = c.target and torsoOf(c.target)
	if c.state == "hunt" and t then
		goal = t.Position + Vector3.new(0, -0.8, 0)
		local dist = (goal - c.pos).Magnitude
		-- (v2.0) the last stretch: a burst of speed straight at them
		if dist < Config.SharkLungeRange then
			speed *= Config.SharkLunge
		end
		if dist < Config.SharkReach and now() > c.nextBite then
			-- the bite: a limb comes off (nothing left to take: the torso)
			c.nextBite = now() + Config.SharkBiteCooldown
			local v = c.target :: Model
			local limbs = {}
			for _, key in { "LeftLeg", "RightLeg", "LeftArm", "RightArm" } do
				if not v:GetAttribute("Severed_" .. key) then
					table.insert(limbs, key)
				end
			end
			local point = t.Position
			if #limbs > 0 then
				local key = limbs[rng:NextInteger(1, #limbs)]
				local lp = v:FindFirstChild(({ LeftLeg = "Left Leg", RightLeg = "Right Leg", LeftArm = "Left Arm", RightArm = "Right Arm" })[key])
				if lp and lp:IsA("BasePart") then
					point = lp.Position
				end
				DamageService.ApplyDamage(v, key, 999, point, { allowSever = true, severAt = 1, cause = "Eaten by a shark", bleed = 2.2, bleedTime = 40 })
				if lp and lp:IsA("BasePart") then
					task.delay(0.3, function()
						-- (the shark keeps it)
						if lp.Parent then
							lp.Transparency = 1
							lp.CanCollide = false
							lp.CanQuery = false
							for _, d in lp:GetDescendants() do
								if d:IsA("BasePart") then
									d.Transparency = 1
								elseif d:IsA("Decal") then
									d:Destroy()
								end
							end
						end
					end)
				end
			else
				DamageService.ApplyDamage(v, "Torso", 80, point, { allowSever = false, cause = "Eaten by a shark", bleed = 2.5, bleedTime = 40 })
			end
			DamageService.Knock(v, nil, (point - c.pos).Unit * 30, 1.5, point)
			GoreService.Sound("sharkBite", point, 1)
			GoreService.Burst(point, Vector3.yAxis, 24, 14) -- (v2.0: no red cloud in the water any more)
			if v:GetAttribute("Dead") and CreatureService.OnKill then
				task.spawn(CreatureService.OnKill, c, v)
			end
			setState(c, "flee")
			c.roamGoal = c.pos + Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit * 50
		end
	elseif c.state == "flee" then
		goal = c.roamGoal or c.home
		speed *= 1.1
	else
		if not c.roamGoal or (Vector3.new(c.roamGoal.X - c.pos.X, 0, c.roamGoal.Z - c.pos.Z)).Magnitude < 8 then
			local a = rng:NextNumber(0, math.pi * 2)
			c.roamGoal = c.home + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(20, 90)
		end
		goal = c.roamGoal :: Vector3
		speed *= 0.45
	end
	-- stay in the water: not above the surface (the fin shows), not below the sea floor
	local depthWanted = c.state == "hunt" and 1.6 or 2.2
	goal = Vector3.new(goal.X, math.min(goal.Y, surf - depthWanted), goal.Z)
	local to = goal - c.pos
	if to.Magnitude > 0.5 then
		c.fwd = c.fwd:Lerp(to.Unit, math.min(1, dt * (c.state == "hunt" and 5 or 2.5))).Unit
	end
	local nextPos = c.pos + c.fwd * speed * dt
	local s2 = Water.SurfaceAt(nextPos)
	if not s2 or not c.bounds(nextPos) then
		-- the edge of the water: turn round
		c.fwd = -c.fwd
		c.roamGoal = c.home
		return
	end
	nextPos = Vector3.new(nextPos.X, math.min(nextPos.Y, s2 - 1.1), nextPos.Z)
	local floor = cast(nextPos + Vector3.new(0, 2, 0), Vector3.new(0, -4.5, 0))
	if floor and floor.Position.Y > nextPos.Y - 1.5 then
		nextPos = Vector3.new(nextPos.X, floor.Position.Y + 1.5, nextPos.Z)
	end
	c.pos = nextPos
	c.up = Vector3.yAxis
end

------------------------------------------------------------------------

function CreatureService.Init()
	folder()
	RunService.Heartbeat:Connect(function(dt)
		if workspace:GetAttribute("TimeStop") then
			return
		end
		dt = math.min(dt, 1 / 20) * TimeScale.Get() -- (v2.8) slow motion
		params.FilterDescendantsInstances = ignoreList()
		for m, c in creatures do
			if not m.Parent then
				creatures[m] = nil
				continue
			end
			local ok, err = pcall(function()
				if c.kind == "crawler" then
					crawlerStep(c, dt)
				else
					sharkStep(c, dt)
				end
				setCF(c)
			end)
			if not ok then
				warn("[creature]", err)
			end
		end
	end)
end

return CreatureService
