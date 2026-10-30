--!strict
-- ReplayService (v2.8.2): the game records itself, so a kill can be watched again the way it happened.
--   * 10 times a second the server writes down where every body part is (the six parts of every player, NPC, bot and
--     boss) and every vehicle, plus where every player's camera looks (the clients report it, ReplayCam).
--   * shots, blood and explosions are written down too (they go through GoreService.FX).
--   * a kill makes a RECORD for the killer: 4.5 s before it and 1.5 s after it, the bodies and cars round the killer, the
--     killer's own camera. At the moment of the kill each of those bodies is copied as it looks then (clothes, hair,
--     armour, implants, the gun in the hand, the sword at the hip) and kept in ServerStorage.
--   * Play(record, viewers, screen): the copies go to ReplicatedStorage for a moment, the frames are sent a second at a
--     time (ReplayCodec buffers), and the clients (ReplayClient) rebuild the place round the kill from their own map and
--     play it back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ReplayCodec = require(Shared:WaitForChild("ReplayCodec"))

local ReplayService = {}

local STEP = 0.1 -- s between two frames
local KEEP = 9 -- s of history
ReplayService.BEFORE = 4.5
ReplayService.AFTER = 1.5
local MAX_RECORDS = 5
local MAX_ACTORS = 8
local MAX_CARS = 3
local MAX_PARTS = 56 -- per body
local MAX_CAR_PARTS = 140
local RADIUS = 150
local CHUNK = 10 -- frames per message
local REGIONS = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
ReplayService.REGIONS = REGIONS

type Tick = { t: number, cams: { [Player]: CFrame }, bodies: { [Model]: { [number]: CFrame } }, cars: { [Instance]: CFrame } }
type Ev = { t: number, k: string, a: Vector3, b: Vector3?, n: number? }
export type Actor = { kind: string, model: Model, slots: { BasePart }, killer: boolean, victim: boolean }
export type Record = {
	id: string,
	killer: Player,
	victim: string,
	t0: number,
	at: number,
	actors: { Actor },
	folder: Folder,
	frames: { ReplayCodec.Frame }?,
	slots: number,
	events: { any },
	center: Vector3,
	done: boolean,
}

local deps: any = nil
local ticks: { Tick } = {}
local events: { Ev } = {}
local lastCam: { [Player]: { cf: CFrame, t: number } } = {}
local records: { [Player]: { Record } } = {}
local counter = 0
local vault: Folder
local live: Folder
local Remote: RemoteEvent
local CamRemote: Instance?

local function bodies(): { [Model]: any }
	local ok, b = pcall(function()
		return deps.DamageService.Bodies()
	end)
	return (ok and typeof(b) == "table") and b or {}
end

local function headOf(m: Model?): BasePart?
	local h = m and m:FindFirstChild("Head")
	return (h and h:IsA("BasePart")) and h or nil
end

-- where a player looks: the camera they reported, or (none lately) their head's view
local function camOf(p: Player): CFrame?
	local c = lastCam[p]
	if c and os.clock() - c.t < 1.5 then
		return c.cf
	end
	local h = headOf(p.Character)
	if h then
		local look = h.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.2 then
			flat = Vector3.new(0, 0, -1)
		end
		local eye = h.Position + Vector3.new(0, 0.3, 0)
		return CFrame.lookAt(eye, eye + flat.Unit)
	end
	return nil
end

local function carRoot(car: Instance): BasePart?
	if car:IsA("Model") then
		if car.PrimaryPart then
			return car.PrimaryPart
		end
		return car:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- one frame of the whole game
local function record()
	local now = os.clock()
	local tick: Tick = { t = now, cams = {}, bodies = {}, cars = {} }
	for _, p in Players:GetPlayers() do
		local c = camOf(p)
		if c then
			tick.cams[p] = c
		end
	end
	for m in bodies() do
		if m.Parent then
			local six = {}
			for i, name in REGIONS do
				local part = m:FindFirstChild(name)
				if part and part:IsA("BasePart") then
					six[i] = part.CFrame
				end
			end
			tick.bodies[m] = six
		end
	end
	for _, car in CollectionService:GetTagged("Vehicle") do
		local r = carRoot(car)
		if r and r.Parent then
			tick.cars[car] = r.CFrame
		end
	end
	table.insert(ticks, tick)
	while #ticks > 0 and ticks[1].t < now - KEEP do
		table.remove(ticks, 1)
	end
	while #events > 0 and events[1].t < now - KEEP do
		table.remove(events, 1)
	end
end

-- shots, blood and blasts go into the record too
local function logFX(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local now = os.clock()
	local t = payload.t
	if t == "shot" and typeof(payload.from) == "Vector3" then
		local any = false
		if typeof(payload.hits) == "table" then
			for _, h in payload.hits do
				if typeof(h) == "table" and typeof(h.to) == "Vector3" then
					table.insert(events, { t = now, k = "shot", a = payload.from, b = h.to })
					any = true
				end
			end
		end
		if not any then
			table.insert(events, { t = now, k = "flash", a = payload.from })
		end
	elseif t == "burst" and typeof(payload.p) == "Vector3" then
		table.insert(events, { t = now, k = "blood", a = payload.p, b = typeof(payload.d) == "Vector3" and payload.d or Vector3.yAxis, n = tonumber(payload.n) or 6 })
	elseif t == "boom" and typeof(payload.p) == "Vector3" then
		table.insert(events, { t = now, k = "boom", a = payload.p, n = tonumber(payload.r) or 6 })
	end
end

------------------------------------------------------------------------
-- copies of the bodies as they look right now
------------------------------------------------------------------------

local KEEP_CHILD = { SpecialMesh = true, BlockMesh = true, CylinderMesh = true, FileMesh = true, Decal = true, Texture = true, SurfaceAppearance = true }

local function cleanCopy(part: BasePart): BasePart?
	local ok, c = pcall(function()
		return part:Clone()
	end)
	if not ok or not c then
		return nil
	end
	local copy = c :: BasePart
	for _, d in copy:GetDescendants() do
		if not KEEP_CHILD[d.ClassName] then
			pcall(function()
				d:Destroy()
			end)
		end
	end
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.Massless = true
	return copy
end

local function itemsOf(p: Player?): { Instance }
	local out = {}
	if not p then
		return out
	end
	pcall(function()
		for _, it in deps.OwnershipService.HeldItems(p) do
			table.insert(out, it)
		end
	end)
	pcall(function()
		for _, it in deps.OwnershipService.Pockets(p) do
			table.insert(out, it)
		end
	end)
	return out
end

local function rootOf(part: BasePart): any
	local ok, r = pcall(function()
		return part.AssemblyRootPart
	end)
	return ok and r or nil
end

-- a body: every visible part rides on one of the six (the one it is fixed to, else the nearest)
local function copyBody(a: Actor, into: Model)
	local m = a.model
	local regs: { [number]: BasePart } = {}
	for i, name in REGIONS do
		local r = m:FindFirstChild(name)
		if r and r:IsA("BasePart") then
			regs[i] = r
		end
	end
	local list: { BasePart } = {}
	local function take(root: Instance)
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 0.98 and d.Name ~= "HumanoidRootPart" and d.Name ~= "Collider" then
				table.insert(list, d)
			end
		end
	end
	take(m)
	local owner = Players:GetPlayerFromCharacter(m)
	for _, it in itemsOf(owner) do
		take(it)
	end
	-- the six first, then the rest by size
	table.sort(list, function(x, y)
		local rx, ry = table.find(REGIONS, x.Name) ~= nil and x.Parent == m, table.find(REGIONS, y.Name) ~= nil and y.Parent == m
		if rx ~= ry then
			return rx
		end
		return x.Size.Magnitude > y.Size.Magnitude
	end)
	local n = 0
	for _, d in list do
		if n >= MAX_PARTS then
			break
		end
		local best, bestD = nil, math.huge
		for i, r in regs do
			if r == d then
				best, bestD = i, -1
				break
			end
			local dist = (r.Position - d.Position).Magnitude
			local fixed = rootOf(r) ~= nil and rootOf(r) == rootOf(d)
			local score = fixed and dist or dist + 100
			if score < bestD then
				best, bestD = i, score
			end
		end
		if best and bestD < 106 then
			local r = regs[best]
			local c = cleanCopy(d)
			if c then
				c:SetAttribute("R", best)
				c:SetAttribute("O", r.CFrame:ToObjectSpace(d.CFrame))
				c:SetAttribute("T", d.Transparency)
				if a.killer and best == 1 then
					c:SetAttribute("H", true) -- (the killer's own head: hidden when the camera is in it)
				end
				c.Parent = into
				n += 1
			end
		end
	end
end

local function copyCar(a: Actor, into: Model)
	local root = a.slots[1]
	local n = 0
	for _, d in a.model:GetDescendants() do
		if n >= MAX_CAR_PARTS then
			break
		end
		if d:IsA("BasePart") and d.Transparency < 0.98 then
			local c = cleanCopy(d)
			if c then
				c:SetAttribute("R", 1)
				c:SetAttribute("O", root.CFrame:ToObjectSpace(d.CFrame))
				c:SetAttribute("T", d.Transparency)
				c.Parent = into
				n += 1
			end
		end
	end
end

-- who is in the record: the victim, the killer, the nearest bodies and cars round the killer's eye
local function pick(killer: Player, victim: Model): ({ Actor }, Vector3)
	local eye = camOf(killer)
	local vh = headOf(victim) or (victim:FindFirstChild("Torso") :: BasePart?)
	local centre = (eye and eye.Position) or (vh and vh.Position) or Vector3.zero
	local cands = {}
	for m in bodies() do
		local t = m:FindFirstChild("Torso")
		if m.Parent and t and t:IsA("BasePart") then
			local d = (t.Position - centre).Magnitude
			local isVictim = m == victim
			local isKiller = m == killer.Character
			if isVictim or isKiller or d < RADIUS then
				table.insert(cands, { m = m, d = isVictim and -2 or (isKiller and -1 or d), victim = isVictim, killer = isKiller })
			end
		end
	end
	table.sort(cands, function(x, y)
		return x.d < y.d
	end)
	local actors: { Actor } = {}
	for _, c in cands do
		if #actors >= MAX_ACTORS then
			break
		end
		local slots = {}
		for i, name in REGIONS do
			local part = c.m:FindFirstChild(name)
			slots[i] = (part and part:IsA("BasePart")) and part or (nil :: any)
		end
		table.insert(actors, { kind = "body", model = c.m, slots = slots, killer = c.killer == true, victim = c.victim == true })
	end
	local cars = {}
	for _, car in CollectionService:GetTagged("Vehicle") do
		local r = carRoot(car)
		if r and car:IsA("Model") and (r.Position - centre).Magnitude < RADIUS then
			table.insert(cars, { m = car, r = r, d = (r.Position - centre).Magnitude })
		end
	end
	table.sort(cars, function(x, y)
		return x.d < y.d
	end)
	for i = 1, math.min(MAX_CARS, #cars) do
		table.insert(actors, { kind = "car", model = cars[i].m, slots = { cars[i].r }, killer = false, victim = false })
	end
	local mid = centre
	if vh then
		mid = (centre + vh.Position) / 2
	end
	return actors, mid
end

local function slotCount(actors: { Actor }): number
	local n = 0
	for _, a in actors do
		n += a.kind == "body" and 6 or 1
	end
	return n
end

local function finish(r: Record)
	local from, to = r.t0 - ReplayService.BEFORE, r.t0 + ReplayService.AFTER
	local frames: { ReplayCodec.Frame } = {}
	for _, tk in ticks do
		if tk.t >= from - 1e-3 and tk.t <= to + 1e-3 then
			local f: ReplayCodec.Frame = { dt = tk.t - from, cam = tk.cams[r.killer], cfs = {} }
			local s = 0
			for _, a in r.actors do
				if a.kind == "body" then
					local six = tk.bodies[a.model]
					for i = 1, 6 do
						s += 1
						if six then
							f.cfs[s] = six[i]
						end
					end
				else
					s += 1
					f.cfs[s] = tk.cars[a.model]
				end
			end
			table.insert(frames, f)
		end
	end
	local evs = {}
	for _, e in events do
		if e.t >= from and e.t <= to then
			table.insert(evs, { dt = e.t - from, k = e.k, a = e.a, b = e.b, n = e.n })
		end
	end
	r.frames = frames
	r.events = evs
	r.done = true
end

local function onKill(victim: Model, killer: Player?)
	if not killer or not killer.Parent or Players:GetPlayerFromCharacter(victim) == killer then
		return
	end
	counter += 1
	local id = "R" .. counter
	local actors, centre = pick(killer, victim)
	local folder = Instance.new("Folder")
	folder.Name = id
	for i, a in actors do
		local m = Instance.new("Model")
		m.Name = "A" .. i
		m:SetAttribute("Kind", a.kind)
		if a.kind == "body" then
			copyBody(a, m)
		else
			copyCar(a, m)
		end
		m.Parent = folder
	end
	folder.Parent = vault
	local name = victim.Name
	local vp = Players:GetPlayerFromCharacter(victim)
	if vp then
		name = vp.DisplayName
	end
	local r: Record = {
		id = id, killer = killer, victim = name, t0 = os.clock(), at = os.time(), actors = actors, folder = folder,
		frames = nil, slots = slotCount(actors), events = {}, center = centre, done = false,
	}
	local list = records[killer] or {}
	records[killer] = list
	table.insert(list, 1, r)
	while #list > MAX_RECORDS do
		local old = table.remove(list) :: Record
		old.folder:Destroy()
	end
	killer:SetAttribute("Replays", #list)
	task.delay(ReplayService.AFTER + 0.15, function()
		finish(r)
	end)
end

function ReplayService.Records(p: Player): { Record }
	local out = {}
	local list: { Record } = records[p] or {}
	for _, r in list do
		if r.done and r.frames and #r.frames >= 2 then
			table.insert(out, r)
		end
	end
	return out
end

-- how long one record runs on the screen (s)
function ReplayService.Length(r: Record): number
	local f = r.frames
	if not f or #f == 0 then
		return 0
	end
	return f[#f].dt
end

-- play a record for these players: the copies go out, then the frames a second at a time.
-- Returns when everything is sent; the clients need ReplayService.Length(r) + a moment to show it.
function ReplayService.Send(r: Record, viewers: { Player }, screen: BasePart?, sitter: Player, startAt: number?)
	local frames = r.frames
	if not frames then
		return
	end
	local copy = live:FindFirstChild(r.id)
	if not copy then
		copy = r.folder:Clone()
		copy.Parent = live
	end
	local expiry = (startAt or workspace:GetServerTimeNow()) + ReplayService.Length(r) + 15
	copy:SetAttribute("Expires", expiry)
	task.delay(math.max(1, expiry - workspace:GetServerTimeNow()), function()
		if copy.Parent and (copy:GetAttribute("Expires") or 0) <= workspace:GetServerTimeNow() then copy:Destroy() end
	end)
	local kinds = {}
	for i, a in r.actors do
		kinds[i] = a.kind
	end
	local chunks = math.max(1, math.ceil(#frames / CHUNK))
	local meta = {
		id = r.id,
		victim = r.victim,
		killer = r.killer.UserId,
		kinds = kinds,
		slots = r.slots,
		chunks = chunks,
		length = ReplayService.Length(r),
		killAt = ReplayService.BEFORE,
		center = r.center,
		events = r.events,
		screen = screen,
		sitter = sitter.UserId,
		startAt = startAt or (workspace:GetServerTimeNow() + 2.6),
	}
	for _, v in viewers do
		if v.Parent then
			Remote:FireClient(v, "clip", meta)
		end
	end
	for c = 1, chunks do
		local part = {}
		for i = (c - 1) * CHUNK + 1, math.min(#frames, c * CHUNK) do
			table.insert(part, frames[i])
		end
		local b = ReplayCodec.Encode(part, r.slots)
		for _, v in viewers do
			if v.Parent then
				Remote:FireClient(v, "clipdata", r.id, c, b)
			end
		end
	end
end

function ReplayService.Init(d: any)
	deps = d
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	Remote = remotes:WaitForChild("Replay") :: RemoteEvent
	CamRemote = remotes:FindFirstChild("ReplayCam")
	vault = Instance.new("Folder")
	vault.Name = "ReplayVault"
	vault.Parent = ServerStorage
	live = Instance.new("Folder")
	live.Name = "ReplayLive"
	live.Parent = d.LiveParent or ReplicatedStorage -- (tests give their own)

	-- the clients tell where their camera looks (10 times a second)
	if CamRemote and (CamRemote:IsA("RemoteEvent") or CamRemote:IsA("UnreliableRemoteEvent")) then
		(CamRemote :: any).OnServerEvent:Connect(function(p: Player, cf: any)
			if ReplayCodec.OkCF(cf) then
				lastCam[p] = { cf = cf, t = os.clock() }
			end
		end)
	end

	-- every shot, splash of blood and blast
	local GoreService = deps.GoreService
	local fx = GoreService.FX
	GoreService.FX = function(payload)
		fx(payload)
		pcall(logFX, payload)
	end

	local prev = deps.DamageService.OnKill
	deps.DamageService.OnKill = function(model: Model, killer: Player?, state: any)
		if prev then
			prev(model, killer, state)
		end
		local ok, err = pcall(onKill :: any, model, killer)
		if not ok then
			warn("[Ragdoll] replay record:", err)
		end
	end

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= STEP then
			acc = math.min(acc - STEP, STEP)
			record()
		end
	end)

	Players.PlayerRemoving:Connect(function(p)
		lastCam[p] = nil
		local list: { Record } = records[p] or {}
		for _, r in list do
			r.folder:Destroy()
		end
		records[p] = nil
	end)
end

-- (tests)
ReplayService._record = record
ReplayService._onKill = onKill
ReplayService._finish = finish
ReplayService._logFX = logFX
ReplayService._ticks = ticks

return ReplayService
