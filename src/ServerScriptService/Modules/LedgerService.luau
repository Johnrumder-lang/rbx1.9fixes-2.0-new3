--!nonstrict
-- LedgerService (v2.1): the BLACK LEDGER (a notebook) and Kuro, its shikigami.
--   * one ledger lies in the construction site when the server starts (and comes back if it is lost); pocketed it is invisible
--   * whoever holds / pockets it has Kuro behind him (HasLedger attribute: only that client draws him, so nobody else sees or hears him)
--   * F with the ledger in the hand: LedgerClient opens the book: pick the FACE, write the NAME, choose HOW. After Config.LedgerWriteTime
--     seconds it happens (LedgerService.Kill -> one of the causes of Shared/LedgerData)
--   * QUEST: Config.LedgerQuestKills kills with the ledger in ONE life + Config.LedgerQuestApples apples fed to Kuro (hold an apple, F)
--     = the ledger is yours for good: it appears in the spawn menu. A SPAWNED ledger can be used once every Config.LedgerSpawnCooldown s.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local LedgerData = require(Shared:WaitForChild("LedgerData"))
local Persist = require(script.Parent:WaitForChild("Persist"))

local LedgerService = {}

local WORLD_COOLDOWN = 12 -- s between two writings of the ledger that lies in the world
local FEED_LINGER = 12 -- s Kuro waits after the ledger left the hands

local deps: any = {}
local Remote: RemoteEvent
local ledgers: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local lifeKills: { [Player]: number } = {}
local nextWrite: { [Player]: number } = {}
local lastHad: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}
local rng = Random.new()

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------

local function aliveBody(p: Player): (Model?, BasePart?)
	local c = p.Character
	local t = c and c:FindFirstChild("Torso")
	if c and t and t:IsA("BasePart") and c:GetAttribute("Dead") ~= true and c.Parent then
		return c, t
	end
	return nil, nil
end

local function heldLedger(p: Player): Model?
	for _, item in deps.OwnershipService.HeldItems(p) do
		if Items.Kind(item) == "ledger" then
			return item
		end
	end
	return nil
end

-- Kuro belongs to the KEEPER of a ledger: the last player who held or pocketed it. He stays with him when he drops it (or dies, and drops it)
-- until somebody else takes it: then he leaves the old keeper at once and shows up behind the new one.
local keeper: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

local function currentCarrier(item: Model): Player?
	local h = deps.OwnershipService.ItemHolder(item)
	if h then
		return h
	end
	local sb = item:GetAttribute("StowedBy")
	if typeof(sb) == "number" then
		return Players:GetPlayerByUserId(sb)
	end
	return nil
end

local function hasLedger(p: Player): boolean
	for item in ledgers do
		if item.Parent and keeper[item] == p.UserId then
			return true
		end
	end
	return false
end

local function stateOf(p: Player): any
	local prof = Persist.Get(p)
	local cd = math.max(0, (nextWrite[p] or 0) - os.clock())
	return {
		kills = lifeKills[p] or 0, needKills = Config.LedgerQuestKills,
		apples = prof and prof.ledgerApples or 0, needApples = Config.LedgerQuestApples,
		unlocked = prof ~= nil and prof.ledgerUnlocked, cooldown = math.floor(cd),
	}
end

local function tell(p: Player, event: string, data: any?)
	Remote:FireClient(p, "event", event, data, stateOf(p))
end

-- (v2.1: no quest any more - the ledger belongs to the admins; the counters stay only as flavour for Kuro)
local function checkUnlock(_p: Player) end

------------------------------------------------------------------------
-- the ways to die
------------------------------------------------------------------------

local function face(char: Model): Vector3
	local t = char:FindFirstChild("Torso")
	if t and t:IsA("BasePart") then
		local look = Vector3.new(t.CFrame.LookVector.X, 0, t.CFrame.LookVector.Z)
		if look.Magnitude > 0.05 then
			return look.Unit
		end
	end
	return Vector3.new(0, 0, -1)
end

local function groundAt(pos: Vector3, ignore: { Instance }): Vector3
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), rp)
	return hit and hit.Position or (pos - Vector3.new(0, 3, 0))
end

local function sfx(name: string, where: Vector3)
	pcall(function()
		deps.GoreService.Sound(name, where, 1)
	end)
end

-- the body dies (or the name "resists": a god-mode admin, spawn protection)
local function finish(victim: Player, killer: Player, cause: string): boolean
	local char = victim.Character
	if not char or char:GetAttribute("Dead") == true then
		return false
	end
	deps.DamageService.MarkAttacker(char, killer)
	deps.DamageService.Kill(char, cause)
	return char:GetAttribute("Dead") == true
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = workspace
	return p
end

local function fade(char: Model, color: Color3, seconds: number, particleColor: Color3)
	task.spawn(function()
		local parts = {}
		for _, d in char:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
				d.Color = color
				d.Material = Enum.Material.Slate
			end
		end
		local t = char:FindFirstChild("Torso")
		if t and t:IsA("BasePart") then
			local pe = Instance.new("ParticleEmitter")
			pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
			pe.Color = ColorSequence.new(particleColor)
			pe.Rate = 70
			pe.Lifetime = NumberRange.new(0.8, 1.6)
			pe.Speed = NumberRange.new(2, 6)
			pe.SpreadAngle = Vector2.new(180, 180)
			pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
			pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			pe.Acceleration = Vector3.new(0, 4, 0)
			pe.Parent = t
			task.delay(seconds, function()
				if pe.Parent then
					pe.Enabled = false
				end
			end)
		end
		for k = 1, 10 do
			task.wait(seconds / 10)
			for _, d in parts do
				if d.Parent then
					d.Transparency = k / 10
				end
			end
		end
	end)
end

-- a body torn apart: every limb and the head come off (real gore), and every piece is thrown away
local function flyApart(char: Model, power: number)
	for _, key in { "LeftArm", "RightArm", "LeftLeg", "RightLeg" } do
		pcall(deps.GoreService.Sever, char, key)
	end
	pcall(deps.GoreService.Decapitate, char)
	for _, d in char:GetChildren() do
		if d:IsA("BasePart") then
			pcall(function()
				local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.5, 1.3), rng:NextNumber(-1, 1)).Unit
				d:ApplyImpulse(dir * power * d.AssemblyMass)
			end)
		end
	end
end

-- little pieces of a material thrown out of a point (ice shards, stones ...)
local function shards(pos: Vector3, count: number, color: Color3, material: Enum.Material, speed: number)
	for _ = 1, count do
		local s = rng:NextNumber(0.25, 0.8)
		local p = Instance.new("Part")
		p.Size = Vector3.new(s, s * rng:NextNumber(0.5, 1.6), s * rng:NextNumber(0.5, 1.2))
		p.Color = color
		p.Material = material
		p.CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0, 2), rng:NextNumber(-1, 1))) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6))
		p.CanCollide = true
		p.CanQuery = false
		p.Parent = workspace
		p.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.4, 1.4), rng:NextNumber(-1, 1)).Unit * speed * rng:NextNumber(0.5, 1.2)
		p.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))
		Debris:AddItem(p, 7)
	end
end

local DEATHS: { [string]: (Player, Player, Model, BasePart) -> () } = {}

-- a car of the game (the "car" prop) comes from behind and hits him
DEATHS.crash = function(victim, killer, char, torso)
	local dir = -face(char)
	local ground = groundAt(torso.Position, { char })
	local start = Vector3.new(torso.Position.X + dir.X * 110, ground.Y + 3.5, torso.Position.Z + dir.Z * 110)
	local aim = CFrame.lookAt(start, Vector3.new(torso.Position.X, start.Y, torso.Position.Z))
	local ok, car = pcall(deps.PropService.Place, "car", aim, nil)
	if not ok or not car or not car:IsA("Model") or not car.PrimaryPart then
		finish(victim, killer, "Died in a car crash")
		return
	end
	Debris:AddItem(car, 30)
	pcall(function()
		require(script.Parent:WaitForChild("VehicleService")).SetWheelsSolid(car, true)
	end)
	local root = car.PrimaryPart
	local forward = aim.LookVector
	local t0 = os.clock()
	local hit = false
	while os.clock() - t0 < 5 and car.Parent and root.Parent do
		root.AssemblyLinearVelocity = Vector3.new(forward.X * 75, root.AssemblyLinearVelocity.Y, forward.Z * 75)
		local t = char:FindFirstChild("Torso")
		if t and t:IsA("BasePart") and (t.Position - root.Position).Magnitude < 7 then
			hit = true
			pcall(function()
				deps.DamageService.Blast(char, forward * 140 + Vector3.new(0, 50, 0), 3)
			end)
			sfx("explosion", t.Position)
			pcall(function()
				deps.GoreService.Burst(t.Position, forward, 40, 30)
			end)
			break
		end
		task.wait()
	end
	finish(victim, killer, "Died in a car crash")
	if hit and root.Parent then
		root.AssemblyLinearVelocity = forward * 60 -- (it keeps rolling a little)
	end
end

DEATHS.trip = function(victim, killer, char, torso)
	local ground = groundAt(torso.Position, { char })
	local peel = part({ Name = "Peel", Size = Vector3.new(1.1, 0.14, 0.6), CFrame = CFrame.new(ground + face(char) * 1.4 + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, math.rad(rng:NextInteger(0, 360)), 0), Color = Color3.fromRGB(246, 214, 60), Material = Enum.Material.SmoothPlastic })
	Debris:AddItem(peel, 5)
	task.wait(0.35)
	pcall(function()
		deps.DamageService.Blast(char, face(char) * 22 + Vector3.new(0, 7, 0), 3)
	end)
	task.wait(0.95)
	local head = char:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		sfx("oof", head.Position)
		pcall(function()
			deps.GoreService.Burst(head.Position, Vector3.new(0, 1, 0), 10, 14)
		end)
	end
	finish(victim, killer, "Tripped and broke their neck")
end

DEATHS.heart = function(victim, killer, char, torso)
	task.wait(0.6)
	pcall(function()
		deps.DamageService.Blast(char, Vector3.new(0, 4, 0), 4)
	end)
	task.wait(1.6)
	finish(victim, killer, "Died of a heart attack")
end

DEATHS.fall = function(victim, killer, char, torso)
	deps.MapService.Teleport(victim, torso.Position + Vector3.new(0, 420, 0))
	local t0 = os.clock()
	while os.clock() - t0 < 14 and char.Parent and char:GetAttribute("Dead") ~= true do
		task.wait(0.5)
	end
	finish(victim, killer, "Fell from the sky") -- (usually the landing did it already: then this does nothing)
end

-- the game's own lightning strike (WeatherService: every client draws and hears it) right on him
DEATHS.lightning = function(victim, killer, char, torso)
	local ground = groundAt(torso.Position, { char })
	workspace:SetAttribute("LightningPos", ground)
	workspace:SetAttribute("LightningId", (workspace:GetAttribute("LightningId") or 0) + 1)
	pcall(function()
		deps.FireService.SetOnFire(char, 3, killer)
	end)
	task.wait(0.15)
	finish(victim, killer, "Struck by lightning")
end

-- a heavy prop of the game (the anvil, the piano) falls on him
local function dropper(propId: string, cause: string, height: number): (Player, Player, Model, BasePart) -> ()
	return function(victim, killer, char, torso)
		local top = torso.Position + Vector3.new(0, height, 0)
		local ok, prop = pcall(deps.PropService.Place, propId, CFrame.new(top) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), nil)
		if not ok or not prop or not prop:IsA("Model") or not prop.PrimaryPart then
			finish(victim, killer, cause)
			return
		end
		Debris:AddItem(prop, 25)
		local root = prop.PrimaryPart
		root.Anchored = true
		local vy = 0
		local landed = false
		local last = os.clock()
		while prop.Parent and not landed and os.clock() - last < 6 do
			local dt = task.wait()
			vy += 130 * dt
			prop:PivotTo(prop:GetPivot() - Vector3.new(0, vy * dt, 0))
			local t = char:FindFirstChild("Torso")
			local aim = t and t:IsA("BasePart") and t.Position.Y or torso.Position.Y
			if root.Position.Y <= aim + 2 then
				landed = true
			end
		end
		if root.Parent then
			root.Anchored = false
			root.AssemblyLinearVelocity = Vector3.new(0, -vy, 0)
		end
		local t = char:FindFirstChild("Torso")
		local at = t and t:IsA("BasePart") and t.Position or torso.Position
		sfx("explosion", at)
		pcall(function()
			deps.GoreService.Burst(at, Vector3.new(0, 1, 0), 40, 26)
		end)
		pcall(function()
			deps.DamageService.Blast(char, Vector3.new(rng:NextNumber(-8, 8), -6, rng:NextNumber(-8, 8)), 2)
		end)
		finish(victim, killer, cause)
	end
end
DEATHS.anvil = dropper("anvil", "Crushed by a falling anvil", 60)
DEATHS.piano = dropper("piano", "Crushed by a falling piano", 65)

DEATHS.burn = function(victim, killer, char, torso)
	pcall(function()
		deps.FireService.SetOnFire(char, 14, killer)
	end)
	local t0 = os.clock()
	while os.clock() - t0 < 10 and char.Parent and char:GetAttribute("Dead") ~= true do
		task.wait(0.5)
	end
	finish(victim, killer, "Burst into flames")
end

DEATHS.explode = function(victim, killer, char, torso)
	task.wait(0.8)
	local t = char:FindFirstChild("Torso")
	local at = t and t:IsA("BasePart") and t.Position or torso.Position
	pcall(function()
		deps.ExplosionService.Explode(at, { radius = 8, damage = 120, power = 60, attacker = killer, cause = "Exploded", ignore = nil })
	end)
	local died = finish(victim, killer, "Exploded")
	-- the body comes apart: arms, legs and head are thrown in every direction
	flyApart(char, 70)
	if died then
		sfx("explosion", at)
	end
end

DEATHS.choke = function(victim, killer, char, torso)
	pcall(function()
		deps.PropService.Place("apple", CFrame.new(torso.Position + face(char) * 1.6 + Vector3.new(0, 1, 0)), nil)
	end)
	task.wait(0.8)
	pcall(function()
		deps.DamageService.Blast(char, Vector3.new(0, 3, 0), 3)
	end)
	task.wait(1.6)
	finish(victim, killer, "Choked on an apple")
end

DEATHS.freeze = function(victim, killer, char, torso)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = Color3.fromRGB(170, 225, 255)
			d.Material = Enum.Material.Ice
		end
	end
	task.wait(1.6)
	local t = char:FindFirstChild("Torso")
	local at = t and t:IsA("BasePart") and t.Position or torso.Position
	local died = finish(victim, killer, "Froze solid and shattered")
	if died then
		-- it shatters: ice flies in all directions and so do the limbs
		shards(at, 28, Color3.fromRGB(190, 232, 255), Enum.Material.Ice, 38)
		flyApart(char, 62)
		sfx("explosion", at)
	end
end

DEATHS.ash = function(victim, killer, char, torso)
	task.wait(1)
	if finish(victim, killer, "Turned to ash") then
		fade(char, Color3.fromRGB(90, 90, 94), 2.6, Color3.fromRGB(150, 150, 155))
	end
end

DEATHS.ink = function(victim, killer, char, torso)
	task.wait(1)
	if finish(victim, killer, "Dissolved into black ink") then
		fade(char, Color3.fromRGB(8, 8, 12), 2.4, Color3.fromRGB(10, 6, 22))
	end
end

------------------------------------------------------------------------
-- writing
------------------------------------------------------------------------

-- the cover opens / closes (a hinge along the spine; everybody sees it) and the pen is taken out of the band while somebody writes
local bookToken: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local function setBook(item: Model, open: boolean, pen: boolean?)
	local hinge = item:FindFirstChild("Hinge", true)
	if not hinge or not hinge:IsA("Weld") then
		return
	end
	local closed = hinge:GetAttribute("ClosedC1")
	if typeof(closed) ~= "CFrame" then
		return
	end
	local want = open and math.rad(168) or 0
	local from = item:GetAttribute("BookAngle") or 0
	local tok = (bookToken[item] or 0) + 1
	bookToken[item] = tok
	item:SetAttribute("BookOpen", open or nil)
	for _, d in item:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("LedgerPen") then
			d.LocalTransparencyModifier = 0
			d.Transparency = pen and 1 or 0
		end
	end
	task.spawn(function()
		local steps = 12
		for i = 1, steps do
			if bookToken[item] ~= tok or not hinge.Parent then
				return
			end
			local a = from + (want - from) * (i / steps)
			hinge.C1 = closed * CFrame.Angles(0, 0, -a)
			item:SetAttribute("BookAngle", a)
			task.wait(0.03)
		end
	end)
end

local function norm(s: string): string
	return string.lower((string.gsub(s, "^%s*(.-)%s*$", "%1")))
end

local function write(p: Player, targetId: any, typed: any, causeId: any)
	if typeof(targetId) ~= "number" or typeof(typed) ~= "string" or typeof(causeId) ~= "string" or #typed > 60 then
		return
	end
	local book = heldLedger(p)
	local cause = LedgerData.ById[causeId]
	if not book or not cause or busy[p] or not aliveBody(p) then
		return
	end
	local now = os.clock()
	if now < (nextWrite[p] or 0) then
		tell(p, "cooldown")
		return
	end
	local target = Players:GetPlayerByUserId(targetId)
	if not target or target == p then
		tell(p, "badtarget", target == p)
		return
	end
	-- the name must match the face
	local t = norm(typed)
	if t ~= norm(target.Name) and t ~= norm(target.DisplayName) then
		nextWrite[p] = now + 5
		tell(p, "smear")
		return
	end
	-- a ledger an ADMIN spawned (or the one that lies in the world) has only the short wait; one a player earned and spawned waits 4 minutes
	local spawned = book:GetAttribute("Spawner") ~= nil and book:GetAttribute("NoCooldown") ~= true
	local wait = spawned and Config.LedgerSpawnCooldown or WORLD_COOLDOWN
	nextWrite[p] = now + wait + Config.LedgerWriteTime
	busy[p] = true
	setBook(book, true, true) -- (open, the pen taken out: the free hand writes)
	Remote:FireClient(p, "writing", target.UserId, target.DisplayName, causeId, Config.LedgerWriteTime)
	tell(p, "writing", { name = target.DisplayName, cause = causeId })
	task.delay(Config.LedgerWriteTime, function()
		busy[p] = nil
		setBook(book, false, false)
		local char, torso = aliveBody(target)
		if not char or not torso or not p.Parent then
			tell(p, "nobody")
			return
		end
		local fn = DEATHS[causeId]
		local ok, err = pcall(fn, target, p, char, torso)
		if not ok then
			warn("[Ledger] " .. causeId .. " failed: " .. tostring(err))
			finish(target, p, "Died by the Black Ledger")
		end
		-- (the death methods run on; count the kill when the body is dead - or say the name resisted)
		task.spawn(function()
			local t0 = os.clock()
			local c = target.Character
			while os.clock() - t0 < 16 and c and c.Parent and c:GetAttribute("Dead") ~= true do
				task.wait(0.4)
			end
			if c and c:GetAttribute("Dead") == true then
				lifeKills[p] = (lifeKills[p] or 0) + 1
				tell(p, "killed", { name = target.DisplayName, n = lifeKills[p] })
				checkUnlock(p)
			else
				tell(p, "resisted", { name = target.DisplayName })
			end
		end)
	end)
end

------------------------------------------------------------------------
-- items: hiding in the pocket, the spirit following the holder, using
------------------------------------------------------------------------

local function track(m: Model)
	if ledgers[m] then
		return
	end
	ledgers[m] = true
	local orig: { [BasePart]: number } = {}
	m:GetAttributeChangedSignal("StowedBy"):Connect(function()
		local stowed = m:GetAttribute("StowedBy") ~= nil
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				if stowed then
					orig[d] = orig[d] or d.Transparency
					d.Transparency = 1
				elseif orig[d] then
					d.Transparency = orig[d]
				end
			elseif d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("Highlight") then
				d.Enabled = not stowed -- (the eye of the sigil glows: not in the pocket)
			end
		end
		m:SetAttribute("SkinHidden", stowed or nil)
	end)
end

local function onUse(p: Player, item: Model, kind: string): boolean
	if kind == "ledger" then
		if not aliveBody(p) then
			return true
		end
		Remote:FireClient(p, "open", stateOf(p))
		return true
	elseif kind == "apple" then
		pcall(deps.OwnershipService.DropItem, item)
		item:Destroy()
		if hasLedger(p) then
			local prof = Persist.Get(p)
			if prof then
				prof.ledgerApples = math.min(99, prof.ledgerApples + 1)
				Persist.Dirty(p)
				p:SetAttribute("LedgerApples", prof.ledgerApples)
				tell(p, "fed", { n = prof.ledgerApples })
				checkUnlock(p)
			end
		else
			tell(p, "ate")
		end
		return true
	end
	return false
end

function LedgerService.Init(d: any)
	deps = d
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	Remote = Remotes:FindFirstChild("Ledger") :: RemoteEvent
	if not Remote then
		local r = Instance.new("RemoteEvent")
		r.Name = "Ledger"
		r.Parent = Remotes
		Remote = r
	end
	Remote.OnServerEvent:Connect(function(p, action, a, b, c)
		if action == "book" then
			-- the menu opened / closed: the book in the hand opens / closes
			local book = heldLedger(p)
			if book and typeof(a) == "boolean" and not busy[p] then
				setBook(book, a, false)
			end
		elseif action == "write" then
			write(p, a, b, c)
		elseif action == "sync" then
			tell(p, "sync")
		end
	end)

	-- F on a ledger / an apple
	local prevUse = deps.ItemService.OnUse
	deps.ItemService.OnUse = function(p: Player, item: Model, kind: string)
		if not onUse(p, item, kind) and prevUse then
			prevUse(p, item, kind)
		end
	end

	-- every ledger in the world is watched
	workspace.DescendantAdded:Connect(function(dsc)
		if dsc:IsA("Model") and dsc:GetAttribute("Item") == "ledger" then
			track(dsc)
		end
	end)
	for _, dsc in workspace:GetDescendants() do
		if dsc:IsA("Model") and dsc:GetAttribute("Item") == "ledger" then
			track(dsc)
		end
	end

	-- the permanent unlock and the apples fed are saved
	local function onPlayer(p: Player)
		task.spawn(function()
			local prof = Persist.Wait(p, 30)
			if prof then
				p:SetAttribute("LedgerUnlocked", prof.ledgerUnlocked or nil)
				p:SetAttribute("LedgerApples", prof.ledgerApples)
			end
		end)
		-- the kills count ONE life: a new body starts at 0
		p.CharacterAdded:Connect(function()
			lifeKills[p] = 0
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		lifeKills[p], nextWrite[p], lastHad[p], busy[p] = nil, nil, nil, nil
	end)
	-- whoever dies drops the ledger - the hand's and the pocket's (the body would carry it away otherwise)
	local function watchDeath(p: Player, char: Model)
		char:GetAttributeChangedSignal("Dead"):Connect(function()
			if char:GetAttribute("Dead") ~= true then
				return
			end
			for item in ledgers do
				if item.Parent and item.PrimaryPart then
					if deps.OwnershipService.ItemHolder(item) == p then
						pcall(deps.OwnershipService.DropItem, item)
					elseif item:GetAttribute("StowedBy") == p.UserId then
						pcall(deps.OwnershipService.Unstow, p, item.PrimaryPart)
					end
				end
			end
		end)
	end
	local function hook(p: Player)
		p.CharacterAdded:Connect(function(c)
			watchDeath(p, c)
		end)
		if p.Character then
			watchDeath(p, p.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end

	-- a ledger an admin spawns never waits; everybody is told when one appears; the admin menu button spawns one
	local prevPlaced = deps.PropService.OnPlaced
	deps.PropService.OnPlaced = function(inst: Instance)
		if prevPlaced then
			prevPlaced(inst)
		end
		if inst:GetAttribute("Item") == "ledger" then
			local sp = inst:GetAttribute("Spawner")
			local who = typeof(sp) == "number" and Players:GetPlayerByUserId(sp) or nil
			if who and Items.IsOwner(who) then
				inst:SetAttribute("NoCooldown", true)
			end
			Remote:FireAllClients("world", who and (who.DisplayName .. " spawned the Black Ledger.") or "An admin spawned the Black Ledger.")
		end
	end
	local AdminService = require(script.Parent:WaitForChild("AdminService"))
	AdminService.SpawnLedger = function(admin: Player)
		local char, torso = aliveBody(admin)
		if char and torso then
			deps.PropService.Place("ledger", torso.CFrame * CFrame.new(0, 0.5, -4), admin)
		end
	end

	-- Kuro follows the keeper of the ledger (see hasLedger)
	task.spawn(function()
		while true do
			task.wait(0.2)
			for item in ledgers do
				if item.Parent then
					local c = currentCarrier(item)
					if c then
						keeper[item] = c.UserId
					elseif item:GetAttribute("BookOpen") then
						setBook(item, false, false) -- (dropped while open: it closes)
					end
				end
			end
			for _, p in Players:GetPlayers() do
				local on = hasLedger(p)
				if (p:GetAttribute("HasLedger") == true) ~= on then
					p:SetAttribute("HasLedger", on or nil)
					if on then
						tell(p, "pickup")
					else
						tell(p, "leave")
					end
				end
			end
		end
	end)

end

return LedgerService
