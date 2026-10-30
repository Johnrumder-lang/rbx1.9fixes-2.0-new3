--!nonstrict
-- ItemService: using held items (F), melee hits, reloading (G), ropes and the physics gun.
--   grenade : F pulls the pin (fuse starts, it blinks), release Q/E to throw it. A shot grenade
--             (or one caught in an explosion) goes off at once.
--   bandage : wrapped on with F (short animation on the client), then it stops the bleeding of the
--             body you hold (or your own) and patches the worst limb
--   rope    : hold a body with one hand, the rope in the other, F: the body is tied to the nearest
--             wall / post / anchored thing. It stays tied until somebody cuts the rope (blade, axe)
--             or an explosion tears it.
--   physgun : (game owner only) hold F to grab anything with the beam, no weight limit
--   spear   : thrown, it flies point first; the thrower's client reports the hit -> damage, it sticks
--   c4      : F throws it, it sticks to whatever it hits; the detonator (F) sets off all of yours
--   boombox : F -> type a Roblox sound id -> it plays (everybody hears it)
--   nuke    : (game owner only) F arms it: long countdown, then ExplosionService.Nuke
--   spear / blade / axe / bat : the holder's client detects the hits (it sees its weapon
--             exactly); the server checks them and hurts the body part. Blades and axes cut
--             limbs and heads off, the bat knocks people flying.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TimeScale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TimeScale")) -- (v2.8) the Sandevistan's slow motion
local RigInfo = require(Shared:WaitForChild("RigInfo"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local Items = require(Shared:WaitForChild("Items"))

local Modules = script.Parent
local DamageService = require(Modules:WaitForChild("DamageService"))
local GoreService = require(Modules:WaitForChild("GoreService"))
local OwnershipService = require(Modules:WaitForChild("OwnershipService"))
local ExplosionService = require(Modules:WaitForChild("ExplosionService"))
local VirusService = require(Modules:WaitForChild("VirusService"))
local FireService = require(Modules:WaitForChild("FireService"))

local ItemRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Item") :: RemoteEvent
local FXRemoteW = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("FX") :: RemoteEvent

local ItemService = {}
-- (v2.0) set by GearService: the new gear
ItemService.OnAction = nil :: ((Player, string, Model, any, any, any, any, any) -> ())? -- remote actions it handles
ItemService.OnUse = nil :: ((Player, Model, string) -> ())? -- F on flashlight / glue / prosthetics
ItemService.OnProjectile = nil :: ((Player, Model, Vector3, Vector3, any) -> ())? -- lock-on, flare gun
ItemService.OnReload = nil :: ((Player, Model) -> ())? -- (the harpoon's line is cut)
ItemService.OnMeleeCreature = nil :: ((Model, BasePart, number, Player, Vector3) -> ())? -- (v2.0) a swing hit a creature

local meleeTimes: { [string]: number } = {}
local lastReload: { [Model]: number } = {}

------------------------------------------------------------------------
-- grenade
------------------------------------------------------------------------

function ItemService.ArmGrenade(grenade: Model, player: Player?)
	if grenade:GetAttribute("Armed") or not grenade.PrimaryPart then
		return
	end
	grenade:SetAttribute("Armed", true)
	local pin = grenade:FindFirstChild("Pin")
	if pin then
		pin:Destroy()
	end
	local lever = grenade:FindFirstChild("Lever")
	if lever and lever:IsA("BasePart") then
		lever.Transparency = 1
	end
	GoreService.Sound("pin", grenade.PrimaryPart, 1)
	local fuse = grenade:GetAttribute("Fuse") or Config.GrenadeFuse
	local light = grenade.PrimaryPart:FindFirstChild("Blink")
	task.spawn(function()
		local t0 = os.clock()
		while grenade.Parent and os.clock() - t0 < fuse do
			local left = fuse - (os.clock() - t0)
			if light and light:IsA("PointLight") then
				light.Enabled = not light.Enabled
			end
			if grenade.PrimaryPart then
				GoreService.Sound("beep", grenade.PrimaryPart, 0.6)
			end
			task.wait(math.clamp(left * 0.18, 0.08, 0.35))
		end
	end)
	task.delay(fuse, function()
		ItemService.DetonateExplosive(grenade, player)
	end)
end

-- flash grenade: a blinding flash and a bang. Everybody who looks at it is blinded for a while
-- (their own client works that out), NPCs that see it are stunned. Almost no damage.
ItemService.OnFlash = nil :: ((Vector3, number, Player?) -> ())? -- set by Main (NPCs)
function ItemService.DetonateFlash(item: Model, attacker: Player?)
	if item:GetAttribute("Detonated") or not item.Parent or not item.PrimaryPart then
		return
	end
	item:SetAttribute("Detonated", true)
	local pos = item.PrimaryPart.Position
	OwnershipService.DropItem(item)
	item:Destroy()
	GoreService.FX({ t = "flash", p = pos, r = Config.FlashRadius })
	GoreService.Sound("flashbang", pos, 1)
	-- right on top of it: it still hurts a bit
	for model in DamageService.Bodies() do
		local t = model:FindFirstChild("Torso")
		if t and t:IsA("BasePart") and (t.Position - pos).Magnitude < 2.5 then
			DamageService.ApplyDamage(model, "Torso", 6, pos, { cause = "Flashbang", allowSever = false, attacker = attacker, quiet = true })
		end
	end
	if ItemService.OnFlash then
		ItemService.OnFlash(pos, Config.FlashRadius, attacker)
	end
end

-- boom now (fuse ran out, it was shot, another explosion set it off)
function ItemService.DetonateGrenade(grenade: Model, attacker: Player?)
	if grenade:GetAttribute("Detonated") or not grenade.Parent or not grenade.PrimaryPart then
		return
	end
	grenade:SetAttribute("Detonated", true)
	local pos = grenade.PrimaryPart.Position
	OwnershipService.DropItem(grenade)
	grenade:Destroy()
	ExplosionService.Explode(pos, {
		radius = Config.GrenadeRadius,
		damage = Config.GrenadeDamage,
		power = Config.GrenadePower,
		attacker = attacker,
		cause = "Grenade",
		kind = "grenade",
	})
end

------------------------------------------------------------------------
-- reload (G)
------------------------------------------------------------------------

function ItemService.Reload(player: Player, gun: Model)
	if OwnershipService.ItemHolder(gun) ~= player or not Items.IsGun(gun) then
		return
	end
	-- the other hand has to be free (two guns = no reload)
	if #OwnershipService.HeldItems(player) > 1 then
		return
	end
	local kind = Items.Kind(gun) or "pistol"
	local stats = Config.Guns[kind] or Config.Guns.pistol
	local now = os.clock()
	if now - (lastReload[gun] or 0) < stats.reload * 0.6 then
		return
	end
	local max = gun:GetAttribute("MaxAmmo") or stats.mag
	if (gun:GetAttribute("Ammo") or 0) >= max then
		return
	end
	-- (v2.0) the M1 Garand only takes a new clip when the old one is empty (it pinged out)
	if stats.enbloc and (gun:GetAttribute("Ammo") or 0) > 0 then
		return
	end
	lastReload[gun] = now
	gun:SetAttribute("Ammo", max)
	if ItemService.OnReload then
		ItemService.OnReload(player, gun)
	end
	if kind == "launcher" or kind == "crossbow" or (stats.projectile or stats.harpoon or stats.taser) then
		for _, p in gun:GetDescendants() do
			if p:IsA("BasePart") and p:GetAttribute("Warhead") then
				p.Transparency = 0
			end
		end
	end
	if gun.PrimaryPart then
		GoreService.FX({ t = "sfx", n = kind == "shotgun" and "pump" or "reload", w = gun.PrimaryPart, v = 1, by = player.UserId })
	end
end

------------------------------------------------------------------------
-- rope: tie a body to a wall
------------------------------------------------------------------------

local function tiesFolder(): Folder
	local f = workspace:FindFirstChild("Ties")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Ties"
		f.Parent = workspace
	end
	return f :: Folder
end

local function closestPointOn(part: BasePart, p: Vector3): Vector3
	local l = part.CFrame:PointToObjectSpace(p)
	local h = part.Size * 0.5
	local c = Vector3.new(math.clamp(l.X, -h.X, h.X), math.clamp(l.Y, -h.Y, h.Y), math.clamp(l.Z, -h.Z, h.Z))
	return part.CFrame:PointToWorldSpace(c)
end

local function countTies(body: Model)
	local n = 0
	for _, r in tiesFolder():GetChildren() do
		if r:IsA("RopeConstraint") and ((r.Attachment0 and r.Attachment0:IsDescendantOf(body)) or (r.Attachment1 and r.Attachment1:IsDescendantOf(body))) then
			n += 1
		end
	end
	body:SetAttribute("Tied", n > 0 and n or nil)
end

-- cut one rope (and its attachments)
function ItemService.CutRope(rope: Instance)
	if not rope:IsA("RopeConstraint") or rope.Parent ~= workspace:FindFirstChild("Ties") then
		return
	end
	local a0, a1 = rope.Attachment0, rope.Attachment1
	local bodies = {}
	for _, a in { a0, a1 } do
		local b = a and a.Parent and a.Parent:IsA("BasePart") and DamageService.BodyOf(a.Parent :: BasePart)
		if b then
			table.insert(bodies, b)
		end
	end
	if a0 then
		GoreService.Sound("ropeSnap", a0.WorldPosition, 0.9)
	end
	rope:Destroy()
	if a0 then
		a0:Destroy()
	end
	if a1 then
		a1:Destroy()
	end
	for _, b in bodies do
		countTies(b)
	end
end

-- explosions tear the ropes close to them
function ItemService.CutRopesNear(pos: Vector3, radius: number)
	local f = workspace:FindFirstChild("Ties")
	if not f then
		return
	end
	for _, r in f:GetChildren() do
		if r:IsA("RopeConstraint") and r.Attachment0 and r.Attachment1 then
			local a, b = r.Attachment0.WorldPosition, r.Attachment1.WorldPosition
			local ab = b - a
			local t = ab.Magnitude > 0.01 and math.clamp((pos - a):Dot(ab) / ab:Dot(ab), 0, 1) or 0
			if (pos - (a + ab * t)).Magnitude < radius * 0.6 then
				ItemService.CutRope(r)
			end
		end
	end
end

local function tie(player: Player, rope: Model)
	local body = OwnershipService.HeldBody(player)
	if not body or body == player.Character or not rope.PrimaryPart then
		return
	end
	local torso = body:FindFirstChild("Torso") :: BasePart?
	if not torso then
		return
	end
	-- the nearest wall / post / anything anchored around the body
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { body, rope }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	params.FilterDescendantsInstances = ignore
	-- walls / posts first; the floor right below only if there is nothing else
	local best, bestPoint, bestD = nil, nil, math.huge
	local floor, floorPoint, floorD = nil, nil, math.huge
	for _, p in workspace:GetPartBoundsInRadius(torso.Position, Config.RopeSearch, params) do
		if p.Anchored and p.CanCollide and p.Transparency < 0.9 and not p:GetAttribute("DropHeight") and not p:GetAttribute("TeleportTo") then
			local cp = closestPointOn(p, torso.Position)
			local off = cp - torso.Position
			local d = off.Magnitude
			local below = off.Y < -1.2 and Vector3.new(off.X, 0, off.Z).Magnitude < 1
			if below then
				if d < floorD then
					floor, floorPoint, floorD = p, cp, d
				end
			elseif d < bestD then
				best, bestPoint, bestD = p, cp, d
			end
		end
	end
	if not best and floor then
		best, bestPoint, bestD = floor, floorPoint, floorD
	end
	if not best or not bestPoint then
		GoreService.FX({ t = "sfx", n = "dryfire", w = rope.PrimaryPart, v = 0.6 })
		return
	end
	OwnershipService.EndDrag(body)
	local a0 = Instance.new("Attachment")
	a0.Name = "TieBody"
	a0.Position = Vector3.new(0, 0.2, 0.5) -- the back of the torso
	a0.Parent = torso
	local a1 = Instance.new("Attachment")
	a1.Name = "TieWall"
	a1.Parent = best
	a1.WorldPosition = bestPoint
	local r = Instance.new("RopeConstraint")
	r.Name = "TieRope"
	r.Attachment0 = a0
	r.Attachment1 = a1
	r.Length = math.min(bestD + 0.5, Config.RopeLength)
	r.Restitution = 0
	r.Visible = true
	r.Thickness = 0.14
	r.Color = BrickColor.new("Brown")
	r.WinchEnabled = false
	r:SetAttribute("Body", body:GetFullName())
	r:SetAttribute("TiedBy", player.UserId)
	r.Parent = tiesFolder()
	countTies(body)
	DamageService.MarkAttacker(body, player)
	GoreService.Sound("rope", torso, 1)
	OwnershipService.DropItem(rope)
	rope:Destroy()
end

------------------------------------------------------------------------
-- tether rope: two clicks (F) = a rope between the two points
------------------------------------------------------------------------

local tetherFirst: { [Player]: { part: BasePart, att: Attachment, mark: BasePart, t: number } } = {}

local function clearTetherFirst(player: Player)
	local f = tetherFirst[player]
	tetherFirst[player] = nil
	if f then
		if f.att.Parent and not f.att:GetAttribute("Used") then
			f.att:Destroy()
		end
		if f.mark.Parent then
			f.mark:Destroy()
		end
	end
end

local function tetherClick(player: Player, item: Model, part: any, point: any)
	if OwnershipService.ItemHolder(item) ~= player or Items.Kind(item) ~= "tether" then
		return
	end
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) or typeof(point) ~= "Vector3" or point ~= point then
		return
	end
	local char = player.Character
	local torso = char and char:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") or (torso.Position - point).Magnitude > Config.TetherRange + 8 then
		return
	end
	if (closestPointOn(part, point) - point).Magnitude > 2 then
		return
	end
	local fx = workspace:FindFirstChild("FX")
	if fx and part:IsDescendantOf(fx) then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "TetherEnd"
	att.Parent = part
	att.WorldPosition = point
	local first = tetherFirst[player]
	if first and (not first.part.Parent or os.clock() - first.t > 30) then
		clearTetherFirst(player)
		first = nil
	end
	if not first or first.part == part then
		clearTetherFirst(player)
		-- the first end: a small orange marker until the second click
		local mark = Instance.new("Part")
		mark.Name = "TetherMark"
		mark.Shape = Enum.PartType.Ball
		mark.Size = Vector3.new(0.45, 0.45, 0.45)
		mark.Color = Color3.fromRGB(255, 140, 30)
		mark.Material = Enum.Material.Neon
		mark.CanCollide = false
		mark.CanQuery = false
		mark.CanTouch = false
		mark.Massless = true
		mark.CFrame = CFrame.new(point)
		local w = Instance.new("WeldConstraint")
		w.Part0 = part
		w.Part1 = mark
		w.Parent = mark
		mark.Anchored = false
		mark.Parent = fx or workspace
		tetherFirst[player] = { part = part, att = att, mark = mark, t = os.clock() }
		GoreService.Sound("tether", point, 0.8)
		return
	end
	-- the second end: tie them together
	first.att:SetAttribute("Used", true)
	clearTetherFirst(player)
	local a0, a1 = first.att, att
	local r = Instance.new("RopeConstraint")
	r.Name = "Tether"
	r.Attachment0 = a0
	r.Attachment1 = a1
	r.Length = math.max((a0.WorldPosition - a1.WorldPosition).Magnitude + 0.3, 1)
	r.Restitution = 0.05
	r.Visible = true
	r.Thickness = 0.18
	r.Color = BrickColor.new("Deep orange")
	r:SetAttribute("Tether", true)
	r:SetAttribute("TiedBy", player.UserId)
	-- a body on one end counts as tied up
	for _, a in { a0, a1 } do
		local body = DamageService.BodyOf(a.Parent :: BasePart)
		if body then
			r:SetAttribute("Body", body:GetFullName())
			DamageService.MarkAttacker(body, player)
		end
	end
	r.Parent = tiesFolder()
	for _, a in { a0, a1 } do
		local body = DamageService.BodyOf(a.Parent :: BasePart)
		if body then
			countTies(body)
		end
	end
	GoreService.Sound("tether", point, 1)
	-- at most a few per player: the oldest goes
	local mine = {}
	for _, c in tiesFolder():GetChildren() do
		if c:GetAttribute("Tether") and c:GetAttribute("TiedBy") == player.UserId then
			table.insert(mine, c)
		end
	end
	while #mine > Config.TetherMax do
		ItemService.CutRope(table.remove(mine, 1) :: Instance)
	end
end

-- a blade / axe went through a rope
local function cut(player: Player, item: Model, rope: any)
	if OwnershipService.ItemHolder(item) ~= player or Items.Melee(item) ~= "slash" or not item.PrimaryPart then
		return
	end
	if typeof(rope) ~= "Instance" or not rope:IsA("RopeConstraint") or not rope.Attachment0 or not rope.Attachment1 then
		return
	end
	local a, b = rope.Attachment0.WorldPosition, rope.Attachment1.WorldPosition
	local p = item.PrimaryPart.Position
	local ab = b - a
	local t = ab.Magnitude > 0.01 and math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1) or 0
	if (p - (a + ab * t)).Magnitude > 9 then
		return
	end
	ItemService.CutRope(rope)
end

------------------------------------------------------------------------
-- physics gun (owner only)
------------------------------------------------------------------------

local function physgunOk(player: Player, item: Model): boolean
	return Items.Kind(item) == "physgun" and Items.Has(player, "physgun") and OwnershipService.ItemHolder(item) == player
end

------------------------------------------------------------------------
-- bandage
------------------------------------------------------------------------

local function useBandage(player: Player, bandage: Model)
	local target = OwnershipService.HeldBody(player) or player.Character
	if not target or not DamageService.Get(target) then
		return
	end
	DamageService.StopBleeding(target)
	-- patch the worst body part that is still there
	local worst, worstHp = nil, math.huge
	for _, region in RigInfo.Regions do
		if not target:GetAttribute("Severed_" .. region) then
			local hp = target:GetAttribute("HP_" .. region) or Config.LimbMaxHP
			if hp < worstHp then
				worst, worstHp = region, hp
			end
		end
	end
	if worst then
		if not target:GetAttribute("Broken_" .. worst) then
			target:SetAttribute("HP_" .. worst, math.min(Config.LimbMaxHP, worstHp + Config.BandageHeal))
		end
		local part = target:FindFirstChild(RigInfo.RegionPart[worst])
		if part and part:IsA("BasePart") then
			GoreService.Bandage(part)
		end
	end
	target:SetAttribute("Blood", math.min(100, (target:GetAttribute("Blood") or 100) + Config.BandageBlood))
	if bandage.PrimaryPart then
		GoreService.Sound("bandage", bandage.PrimaryPart.Position, 1)
	end
	OwnershipService.DropItem(bandage)
	bandage:Destroy()
end

------------------------------------------------------------------------
-- melee
------------------------------------------------------------------------

function ItemService.Melee(player: Player, item: Model, part: any, point: any, speed: any)
	if OwnershipService.ItemHolder(item) ~= player then
		return
	end
	local kind = Items.Melee(item)
	if not kind or typeof(part) ~= "Instance" or not part:IsA("BasePart") or typeof(point) ~= "Vector3" or typeof(speed) ~= "number" then
		return
	end
	if speed ~= speed or speed <= 0 then
		return
	end
	speed = math.min(speed, 70)
	local body, region = DamageService.BodyOf(part)
	local char = player.Character
	local saw = Items.Kind(item) == "chainsaw"
	if saw and not item:GetAttribute("SawOn") then
		return -- (v2.0) a chainsaw that is off does not cut
	end
	local cooldown = saw and Config.ChainsawTick * 0.8 or Config.MeleeCooldown * 0.8
	if not body and item.PrimaryPart and ItemService.OnMeleeCreature then
		-- (v2.0) a blade / a bat into the Crawler or a shark
		local m = part:FindFirstAncestorOfClass("Model")
		if m and m:GetAttribute("Creature") and (item.PrimaryPart.Position - point).Magnitude < 12 then
			local key = player.UserId .. ":c:" .. m:GetFullName()
			local t = os.clock()
			if t - (meleeTimes[key] or 0) >= cooldown then
				meleeTimes[key] = t
				local heavy = Items.Kinds[Items.Kind(item) or ""] and Items.Kinds[Items.Kind(item) or ""].heavy
				local dmg = saw and Config.ChainsawTickDamage * 1.4 or (Config.BladeDamage + speed * Config.BladeDamagePerSpeed) * (heavy and 1.6 or 1)
				GoreService.Sound(kind == "blunt" and "heavyHit" or "slash", point, 1)
				ItemService.OnMeleeCreature(m, part, dmg, player, point)
			end
		end
		return
	end
	if not body or not region or body == char or not item.PrimaryPart then
		return
	end
	-- the weapon is at the hit, the hit is on the victim (both copies may lag a little)
	if (item.PrimaryPart.Position - point).Magnitude > 10 then
		return
	end
	if (part.Position - point).Magnitude > part.Size.Magnitude * 0.5 + Config.GunHitTolerance then
		return
	end
	local key = player.UserId .. ":" .. body:GetFullName() .. ":" .. region
	local now = os.clock()
	if now - (meleeTimes[key] or 0) < cooldown then
		return
	end
	meleeTimes[key] = now
	if DamageService.Dodged(body) then
		return -- (v2.0) the swing was slipped (weave)
	end
	-- (v2.0) the admins' kick hammer: whoever it hits flies - and out of the server
	if Items.Kind(item) == "banhammer" and Items.IsOwner(player) then
		local victim = Players:GetPlayerFromCharacter(body)
		local dirK = point - item.PrimaryPart.Position
		dirK = dirK.Magnitude > 0.05 and dirK.Unit or Vector3.yAxis
		GoreService.Sound("punchBoom", point, 1)
		GoreService.FX({ t = "boomSmall", p = point, d = dirK })
		DamageService.Fling(body, dirK * 160 + Vector3.new(0, 90, 0), dirK)
		if victim and victim ~= player and not Items.Unkickable(victim) then
			task.delay(0.8, function()
				if victim.Parent then
					victim:Kick("You were hit by the kick hammer of an admin (" .. player.DisplayName .. ").")
				end
			end)
		end
		return
	end

	local mult = Config.LimbMultiplier[region] or 1
	-- (v2.0) a prosthetic arm is a little weaker
	if char and (char:GetAttribute("Prosthetic_LeftArm") or char:GetAttribute("Prosthetic_RightArm")) then
		mult *= Config.ProstheticArmStrength
	end
	local dir = point - item.PrimaryPart.Position
	dir = dir.Magnitude > 0.05 and dir.Unit or Vector3.yAxis
	local partMass = DamageService.PartMass(body, region)
	if kind == "stab" then
		local knife = Items.Kind(item) == "knife"
		local dmg = (Config.SpearDamage + speed * Config.SpearDamagePerSpeed) * mult * (knife and Config.KnifeDamageMult or 1)
		GoreService.Sound("stab", point, 1)
		local hitPart = body:FindFirstChild(RigInfo.RegionPart[region])
		if hitPart and hitPart:IsA("BasePart") then
			GoreService.Wound(hitPart, point, 1)
		end
		DamageService.ApplyDamage(body, region, dmg, point, {
			cause = (knife and "Stabbed by " or "Speared by ") .. player.DisplayName,
			allowSever = false,
			bleed = region == "Torso" and Config.PierceBleedTorso or Config.PierceBleedLimb,
			bleedTime = 20,
			attacker = player,
			melee = true,
		})
		DamageService.Knock(body, region, dir * math.min(speed, 40) * partMass * 0.7, speed > 24 and 1.4 or nil, point)
	elseif kind == "blunt" then
		-- bat / sledgehammer: no cuts, but it hits hard and sends people flying
		local sledge = Items.Kind(item) == "sledge"
		local dmg = sledge and (Config.SledgeDamage + speed * Config.SledgeDamagePerSpeed) * mult or (Config.BatDamage + speed * Config.BatDamagePerSpeed) * mult
		GoreService.Sound(sledge and "heavyHit" or "punch", point, 1)
		DamageService.ApplyDamage(body, region, dmg, point, {
			cause = "Beaten by " .. player.DisplayName,
			allowSever = false,
			attacker = player,
			melee = true,
		})
		local fling = dir * math.min(speed, 45) * (sledge and Config.SledgeKnock or Config.BatKnock) + Vector3.new(0, math.min(speed, 45) * 0.35, 0)
		DamageService.Knock(body, region, fling * partMass, speed > 14 and 1.8 or nil, point)
		if speed > 22 then
			DamageService.Blast(body, fling * 0.35, 1.8)
		end
	else
		local axe = Items.Kind(item) == "axe"
		local katana = Items.Kind(item) == "katana"
		local machete = Items.Kind(item) == "machete"
		local chainsaw = Items.Kind(item) == "chainsaw" -- (v2.0)
		katana = katana or chainsaw
		local dmg = (Config.BladeDamage + speed * Config.BladeDamagePerSpeed) * mult * (axe and Config.AxeDamageMult or (chainsaw and Config.ChainsawDamageMult or (katana and Config.KatanaDamageMult or (machete and Config.MacheteDamageMult or 1))))
		if chainsaw then
			-- (v2.0) the running chain chews: small bites many times a second (the limb comes off when it is spent)
			dmg = Config.ChainsawTickDamage * mult
			speed = math.min(speed, 12)
			GoreService.Sound("chainsawCut", point, 0.8)
			GoreService.FX({ t = "sawSpray", p = point, d = dir })
		else
			GoreService.Sound("slash", point, 1)
		end
		GoreService.Sound("gore", point, chainsaw and 0.35 or 0.6)
		local severAt = region == "Head" and Config.BladeDecapitateDamage * (katana and 0.85 or 1)
			or (axe and Config.AxeSeverDamage or (katana and Config.KatanaSeverDamage or Config.BladeSeverDamage))
		DamageService.ApplyDamage(body, region, dmg, point, {
			cause = (axe and "Chopped by " or "Cut down by ") .. player.DisplayName,
			allowSever = true,
			severAt = severAt,
			bleed = axe and 1.1 or 0.8,
			bleedTime = 15,
			attacker = player,
			melee = true,
		})
		DamageService.Knock(body, region, dir * math.min(speed, 40) * partMass * (axe and 0.7 or 0.45), speed > (axe and 22 or 30) and 1.4 or nil, point)
	end
end

------------------------------------------------------------------------
-- thrown things that stick: the spear (point first) and C4 (anything)
------------------------------------------------------------------------

-- Stuck in the world (ground, a wall): the item is pinned on its own (anchored), NOT welded to it.
-- A weld made it part of the anchored world, and whatever then pushed or turned the item (a kick,
-- a blast, picking it up) pushed or moved the whole baseplate: the ground shifted, and after a C4
-- the ground kept shoving people around (a moving anchored part acts like a conveyor belt).
-- Stuck in something loose (a player, a car, a prop): welded, it moves with it.
local lastThrownHit: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
ItemService.OnGlass = nil :: ((BasePart, Vector3, Vector3) -> boolean)?

local stuck: { [Model]: { weld: Instance?, on: BasePart, at: CFrame?, parts: { [BasePart]: { cc: boolean, massless: boolean } } } } = {}

-- (v2.1 fix) a spear / knife / bolt pulled out of a wall is still partly INSIDE it. Its parts collide again at once, the
-- wall pushes back and the hand that holds it cannot get away: the player was stuck. Now the item ignores what it
-- came out of (NoCollisionConstraints) until it is clear of it, so it slides out freely.
local function slideOut(item: Model, on: BasePart?)
	if not on or not on.Parent then
		return
	end
	local made: { Instance } = {}
	for _, d in item:GetDescendants() do
		if d:IsA("BasePart") then
			local nc = Instance.new("NoCollisionConstraint")
			nc.Name = "SlideOut"
			nc.Part0 = d
			nc.Part1 = on
			nc.Parent = d
			table.insert(made, nc)
		end
	end
	if #made == 0 then
		return
	end
	task.spawn(function()
		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Include
		op.FilterDescendantsInstances = { on }
		local t0 = os.clock()
		local clear = 0
		while os.clock() - t0 < 10 and item.Parent and on.Parent do
			task.wait(0.2)
			local touching = false
			for _, d in item:GetDescendants() do
				if d:IsA("BasePart") and #workspace:GetPartsInPart(d, op) > 0 then
					touching = true
					break
				end
			end
			clear = touching and 0 or clear + 1
			if clear >= 3 then
				break
			end
		end
		for _, nc in made do
			if nc.Parent then
				nc:Destroy()
			end
		end
	end)
end

function ItemService.Unstick(item: Model)
	local rec = stuck[item]
	if not rec then
		return
	end
	stuck[item] = nil
	if rec.weld and rec.weld.Parent then
		rec.weld:Destroy()
	end
	if item.PrimaryPart then
		item.PrimaryPart.Anchored = false -- (a stuck item is never left anchored)
	end
	for p, st in rec.parts do
		if p.Parent then
			p.CanCollide = st.cc
			p.Massless = st.massless
		end
	end
	item:SetAttribute("Stuck", nil)
	item:SetAttribute("NoStickUntil", os.clock() + 2.5)
	slideOut(item, rec.on)
end

local function glue(item: Model, part: BasePart, cf: CFrame)
	local root = item.PrimaryPart :: BasePart
	-- (v2.1 fix) an item that somebody HOLDS never sticks, and one that was just pulled out does not stick again for a moment: pulling a
	-- spear out of a wall dragged its tip back into the wall, it stuck again - anchored, in the hand - and the whole body was locked to the wall
	if item:GetAttribute("HolderId") ~= nil or os.clock() < ((item:GetAttribute("NoStickUntil") :: number?) or 0) then
		return
	end
	ItemService.Unstick(item)
	local recs = {}
	for _, d in item:GetDescendants() do
		if d:IsA("BasePart") then
			recs[d] = { cc = d.CanCollide, massless = d.Massless }
			d.CanCollide = false
			d.Massless = true -- (it does not weigh down whatever it sticks in)
		end
	end
	-- whoever simulates the thing it sticks in keeps simulating it (a player's own limb stays theirs)
	local owner: Player? = nil
	local ownerKnown = false
	if not part.Anchored then
		ownerKnown = pcall(function()
			owner = part:GetNetworkOwner()
		end)
	end
	if not root:IsGrounded() then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	if part:IsGrounded() then
		root.Anchored = true
		root.CFrame = cf
		stuck[item] = { weld = nil, on = part, at = part.CFrame, parts = recs }
		item:SetAttribute("Stuck", true)
		return
	end
	root.CFrame = cf
	local w = Instance.new("WeldConstraint")
	w.Name = "StuckWeld"
	w.Part0 = root
	w.Part1 = part
	w.Parent = root
	stuck[item] = { weld = w, on = part, parts = recs }
	item:SetAttribute("Stuck", true)
	if ownerKnown then
		pcall(function()
			part:SetNetworkOwner(owner)
		end)
	end
end

-- the thrower's client saw its spear / C4 hit `part` at `point`
function ItemService.Stick(player: Player, item: Model, part: any, point: any, speed: any, normal: any, vel: any)
	local kind = Items.Kind(item)
	local sharp = Items.Sharp(item)
	local isSpear = kind == "spear"
	if not sharp and kind ~= "c4" then
		return
	end
	local root = item.PrimaryPart
	if not root or item:GetAttribute("HolderId") or stuck[item] or item:GetAttribute("LastHolder") ~= player.UserId then
		return
	end
	local t = item:GetAttribute("LastHeldT")
	if typeof(t) ~= "number" or workspace:GetServerTimeNow() - t > 8 then
		return
	end
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) or typeof(point) ~= "Vector3" or point ~= point then
		return
	end
	if typeof(speed) ~= "number" or speed ~= speed or typeof(normal) ~= "Vector3" or typeof(vel) ~= "Vector3" or vel ~= vel then
		return
	end
	if (root.Position - point).Magnitude > 30 or (part.Position - point).Magnitude > part.Size.Magnitude * 0.5 + Config.GunHitTolerance then
		return
	end
	if player.Character and part:IsDescendantOf(player.Character) then
		return
	end
	speed = math.clamp(speed, 0, 250)
	local dir = vel.Magnitude > 0.5 and vel.Unit or -normal
	if part.Material == Enum.Material.Glass and ItemService.OnGlass and ItemService.OnGlass(part, point, dir) then
		return -- (through the window: it does not stick in glass)
	end
	local body, region = DamageService.BodyOf(part)
	if sharp then
		if body and region then
			local base = isSpear and Config.SpearThrowDamage or Config.ThrownBladeDamage
			local per = isSpear and Config.SpearThrowDamagePerSpeed or Config.ThrownBladeDamagePerSpeed
			local dmg = (base + speed * per) * (Config.LimbMultiplier[region] or 1)
			GoreService.Sound("stab", point, 1)
			GoreService.Wound(part, point, 1.2)
			DamageService.ApplyDamage(body, region, dmg, point, {
				cause = (isSpear and "Speared by " or "Knifed by ") .. player.DisplayName,
				allowSever = false,
				bleed = region == "Torso" and Config.PierceBleedTorso or Config.PierceBleedLimb,
				bleedTime = 25,
				attacker = player,
			})
			DamageService.Knock(body, region, dir * math.min(speed, 80) * 0.6 * DamageService.PartMass(body, region), 1.6, point)
		elseif speed < 40 then
			return -- too slow to go into a wall: it just falls
		end
		-- point first, 0.7 studs deep
		local grip = root:FindFirstChild("GripAttachment")
		local tipWorld = Items.TipPoint(item)
		if not grip or not grip:IsA("Attachment") or not tipWorld then
			return
		end
		local rot = CFrame.lookAt(Vector3.zero, dir) * grip.CFrame.Rotation:Inverse()
		local tipLocal = root.CFrame:PointToObjectSpace(tipWorld)
		local cf = CFrame.new(root.Position) * rot
		cf += (point + dir * 0.7) - cf:PointToWorldSpace(tipLocal)
		glue(item, part, cf)
	else
		-- C4: flat on the surface it hit (walls, floors, props, cars, people)
		local n = normal.Magnitude > 0.5 and normal.Unit or -dir
		local perp = math.abs(n.Y) < 0.9 and n:Cross(Vector3.yAxis) or n:Cross(Vector3.xAxis)
		local half = root.Size.Y * 0.5
		local pos = point + n * half
		glue(item, part, CFrame.lookAt(pos, pos + perp, n))
		item:SetAttribute("PlacedBy", player.UserId)
		GoreService.Sound("stick", point, 1)
	end
end

------------------------------------------------------------------------
-- flamethrower (hold F): the holder's client says where the nozzle points ~12 times a second.
-- Bodies in the cone (no walls in between) catch fire, the stream sets the ground on fire.
------------------------------------------------------------------------

local flameLast: { [Model]: number } = {}
local flameZoneT: { [Model]: number } = {}
local flameParams = RaycastParams.new()
flameParams.FilterType = Enum.RaycastFilterType.Exclude

local function setFlame(item: Model, on: boolean)
	if (item:GetAttribute("Flaming") == true) == on then
		return
	end
	for _, d in item:GetDescendants() do
		if (d:IsA("ParticleEmitter") and d.Name == "Flame") or (d:IsA("PointLight") and d.Name == "FlameLight") then
			d.Enabled = on
		end
	end
	item:SetAttribute("Flaming", on or nil)
end

function ItemService.Flame(player: Player, item: Model, dir: any)
	if OwnershipService.ItemHolder(item) ~= player or Items.Kind(item) ~= "flamethrower" then
		return
	end
	if typeof(dir) ~= "Vector3" or dir ~= dir or dir.Magnitude < 0.5 then
		return
	end
	local now = os.clock()
	local last = flameLast[item] or 0
	if now - last < 0.06 then
		return
	end
	local dt = math.min(now - last, 0.25)
	flameLast[item] = now
	local fuel = item:GetAttribute("Fuel") or 0
	if fuel <= 0 then
		setFlame(item, false)
		return
	end
	item:SetAttribute("Fuel", math.max(0, fuel - Config.FlameFuelUse * dt))
	local muzzle = Items.Muzzle(item)
	if not muzzle then
		return
	end
	local origin = muzzle.WorldPosition
	dir = dir.Unit
	local nozzle = muzzle.WorldCFrame.LookVector
	if dir:Dot(nozzle) < 0.5 then
		dir = nozzle -- (the client may lag a little; it never sprays backwards)
	end
	setFlame(item, true)
	local char = player.Character
	local ignore: { Instance } = { item }
	if char then
		table.insert(ignore, char)
	end
	local fx = workspace:FindFirstChild("FX")
	if fx then
		table.insert(ignore, fx)
	end
	local cosA = math.cos(math.rad(Config.FlameAngle))
	for body, state in DamageService.Bodies() do
		if body == char or state.dead then
			continue
		end
		local t = body:FindFirstChild("Torso")
		if not (t and t:IsA("BasePart")) then
			continue
		end
		local to = t.Position - origin
		local d = to.Magnitude
		if d > Config.FlameRange or d < 0.1 or to.Unit:Dot(dir) < cosA then
			continue
		end
		local list = table.clone(ignore)
		table.insert(list, body)
		flameParams.FilterDescendantsInstances = list
		local wall = workspace:Raycast(origin, to, flameParams)
		if wall and wall.Instance.Anchored and wall.Instance.CanCollide then
			continue
		end
		FireService.SetOnFire(body, Config.BurnTime, player)
		DamageService.ApplyDamage(body, "Torso", Config.FlameDPS * dt, nil, {
			cause = "Burned by " .. player.DisplayName,
			allowSever = false,
			quiet = true,
			attacker = player,
		})
	end
	if now - (flameZoneT[item] or 0) > 0.45 then
		flameZoneT[item] = now
		flameParams.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(origin, dir * Config.FlameRange, flameParams)
		local p = hit and hit.Position or (origin + dir * Config.FlameRange)
		FireService.Ignite(p, 3.5, 4, player)
	end
end

-- flames off when the trigger is let go; fuel comes back slowly
local function flameLoop()
	while true do
		local dt = task.wait(0.15)
		local now = os.clock()
		for item, t in flameLast do
			if not item.Parent then
				flameLast[item] = nil
				flameZoneT[item] = nil
				continue
			end
			if now - t > 0.25 then
				setFlame(item, false)
				local f = item:GetAttribute("Fuel") or 0
				if f < Config.FlameFuel then
					item:SetAttribute("Fuel", math.min(Config.FlameFuel, f + Config.FlameFuelRegen * dt))
				end
			end
		end
	end
end

-- anything else thrown (aimed throw): it hits with its weight and speed; glass breaks
function ItemService.ThrownHit(player: Player, item: Model, part: any, point: any, speed: any, vel: any)
	local root = item.PrimaryPart
	if not root or item:GetAttribute("HolderId") or stuck[item] or item:GetAttribute("LastHolder") ~= player.UserId then
		return
	end
	local t = item:GetAttribute("LastHeldT")
	if typeof(t) ~= "number" or workspace:GetServerTimeNow() - t > 6 then
		return
	end
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) or typeof(point) ~= "Vector3" or point ~= point then
		return
	end
	if typeof(speed) ~= "number" or speed ~= speed or typeof(vel) ~= "Vector3" or vel ~= vel then
		return
	end
	if (root.Position - point).Magnitude > 30 or (part.Position - point).Magnitude > part.Size.Magnitude * 0.5 + Config.GunHitTolerance then
		return
	end
	if player.Character and part:IsDescendantOf(player.Character) then
		return
	end
	local now = os.clock()
	if now - (lastThrownHit[item] or 0) < 0.3 then
		return
	end
	lastThrownHit[item] = now
	speed = math.clamp(speed, 0, 160)
	local dir = vel.Magnitude > 0.5 and vel.Unit or Vector3.yAxis
	if ItemService.OnGlass then
		ItemService.OnGlass(part, point, dir)
	end
	local body, region = DamageService.BodyOf(part)
	if not body or not region then
		return
	end
	local mass = math.max(root.AssemblyMass, 0.5)
	local kind = Items.Kind(item)
	local dmg = math.min(mass * speed * Config.ThrownBluntDamage, Config.ThrownBluntMax)
	local axe = kind == "axe"
	if axe then
		dmg *= 1.6
	end
	DamageService.ApplyDamage(body, region, dmg, point, {
		cause = "Hit by a thrown " .. string.lower((Items.Kinds[kind or ""] and Items.Kinds[kind or ""].name) or "thing") .. " (" .. player.DisplayName .. ")",
		allowSever = axe,
		severAt = axe and Config.AxeSeverDamage or nil,
		attacker = player,
	})
	if dmg > 12 then
		DamageService.Knock(body, region, dir * math.min(speed, 90) * 0.5 * DamageService.PartMass(body, region), dmg > 30 and 1.4 or nil, point)
	end
	GoreService.Sound(axe and "slash" or "bodyHit", point, math.clamp(dmg / 40, 0.4, 1))
end

------------------------------------------------------------------------
-- C4 + detonator
------------------------------------------------------------------------

function ItemService.DetonateC4(c4: Model, attacker: Player?)
	if c4:GetAttribute("Detonated") or not c4.Parent or not c4.PrimaryPart then
		return
	end
	c4:SetAttribute("Detonated", true)
	local pos = c4.PrimaryPart.Position
	ItemService.Unstick(c4)
	OwnershipService.DropItem(c4)
	c4:Destroy()
	ExplosionService.Explode(pos, {
		radius = Config.C4Radius,
		damage = Config.C4Damage,
		power = Config.C4Power,
		attacker = attacker,
		cause = "C4",
		kind = "c4",
	})
end

-- grenades and C4 (shot, caught in a blast, hit hard); a shot virus bottle breaks
function ItemService.DetonateExplosive(model: Model, attacker: Player?)
	local kind = Items.Kind(model)
	if kind == "grenade" then
		ItemService.DetonateGrenade(model, attacker)
	elseif kind == "flash" then
		ItemService.DetonateFlash(model, attacker)
	elseif kind == "c4" then
		ItemService.DetonateC4(model, attacker)
	elseif kind == "virus" and (attacker == nil or Items.Has(attacker, "virus")) then
		VirusService.SmashBottle(model, attacker) -- (only the game owner can set the virus free)
	elseif kind == "molotov" and model.PrimaryPart then
		FireService.Molotov(model, model.PrimaryPart.Position, attacker)
	end
end

------------------------------------------------------------------------
-- rocket launcher: the server flies the rocket
------------------------------------------------------------------------

local lastRocket: { [Model]: number } = {}

local function makeRocket(cf: CFrame): BasePart
	local r = Instance.new("Part")
	r.Name = "Rocket"
	r.Size = Vector3.new(0.4, 0.4, 1.5)
	r.Color = Color3.fromRGB(110, 120, 80)
	r.Material = Enum.Material.Metal
	r.Anchored = true
	r.CanCollide = false
	r.CanQuery = false
	r.CanTouch = false
	r.CFrame = cf
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.12, 0.7)
	a0.Parent = r
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.12, 0.7)
	a1.Parent = r
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.7
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120), Color3.fromRGB(120, 116, 110))
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.WidthScale = NumberSequence.new(1, 4)
	trail.LightEmission = 0.6
	trail.Parent = r
	local fire = Instance.new("Fire")
	fire.Size = 2
	fire.Heat = 0
	fire.Parent = r
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(200, 196, 190)
	smoke.Opacity = 0.25
	smoke.RiseVelocity = 1
	smoke.Size = 1.5
	smoke.Parent = r
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 180, 100)
	light.Range = 12
	light.Brightness = 3
	light.Parent = r
	r.Parent = workspace:FindFirstChild("FX") or workspace
	return r
end

function ItemService.FireRocket(player: Player, gun: Model, origin: any, dir: any, target: any)
	if OwnershipService.ItemHolder(gun) ~= player or not gun.PrimaryPart then
		return
	end
	if Items.Kind(gun) ~= "launcher" then
		-- (v2.0) the lock-on launcher and the flare gun
		if ItemService.OnProjectile and typeof(origin) == "Vector3" and typeof(dir) == "Vector3" and origin == origin and dir == dir and dir.Magnitude > 0.5 then
			ItemService.OnProjectile(player, gun, origin, dir.Unit, target)
		end
		return
	end
	local stats = Config.Guns.launcher
	local now = os.clock()
	if now - (lastRocket[gun] or 0) < stats.interval * 0.8 then
		return
	end
	local char = player.Character
	local torso = char and char:FindFirstChild("Torso") :: BasePart?
	local muzzle = Items.Muzzle(gun)
	if not torso or not muzzle or typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" or origin ~= origin or dir ~= dir or dir.Magnitude < 0.5 then
		return
	end
	if (origin - torso.Position).Magnitude > Config.GunOriginTolerance then
		origin = muzzle.WorldPosition
	end
	local ammo = gun:GetAttribute("Ammo") or 0
	if ammo <= 0 then
		GoreService.FX({ t = "sfx", n = "dryfire", w = origin, v = 1, by = player.UserId })
		return
	end
	lastRocket[gun] = now
	gun:SetAttribute("Ammo", ammo - 1)
	for _, p in gun:GetDescendants() do
		if p:IsA("BasePart") and p:GetAttribute("Warhead") then
			p.Transparency = 1
		end
	end
	ItemService.LaunchRocket(origin, dir, player, { gun, char :: Instance })
end

-- a rocket from origin along dir (the launcher, the helicopter's pods); `ignore` = what it may not
-- hit right after the launch (the shooter, the gun, the helicopter)
-- (v2.0) `homing`: a part to steer at (the lock-on launcher, the jet's missiles). A ground target gets a top attack:
-- the missile climbs first and comes down on the roof.
function ItemService.LaunchRocket(origin: Vector3, dir: Vector3, attacker: Player?, ignore: { Instance }?, homing: BasePart?, opts: any?)
	dir = dir.Unit
	GoreService.Sound("rocketLaunch", origin, 1)
	GoreService.FX({ t = "boomSmall", p = origin, d = -dir })
	local rocket = makeRocket(CFrame.lookAt(origin, origin + dir))
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list: { Instance } = { rocket }
	if ignore then
		for _, inst in ignore do
			table.insert(list, inst)
		end
	end
	local fx = workspace:FindFirstChild("FX")
	if fx then
		table.insert(list, fx)
	end
	params.FilterDescendantsInstances = list
	local pos = origin
	local o = opts or {}
	local speed = homing and Config.LockonSpeed or Config.RocketSpeed
	local vel = dir * speed
	local t0 = os.clock()
	local life = homing and 9 or 6
	local topAttack = false
	if homing then
		local car = homing:FindFirstAncestorOfClass("Model")
		topAttack = o.top ~= false and car ~= nil and car:GetAttribute("Car") == true and not (car:GetAttribute("Heli") or car:GetAttribute("Jet"))
		-- (close: no time to climb first)
		if topAttack and MathUtil.Flat(homing.Position - origin).Magnitude < 70 then
			topAttack = false
		end
		-- the driver hears the warning
		local m = homing:FindFirstAncestorOfClass("Model")
		while m and not m:GetAttribute("Car") do
			m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
		end
		local driverId = m and m:GetAttribute("DriverId")
		local driver = typeof(driverId) == "number" and Players:GetPlayerByUserId(driverId) or nil
		if driver then
			FXRemoteW:FireClient(driver, { t = "missile", p = origin })
		end
	end
	local conn
	conn = game:GetService("RunService").Heartbeat:Connect(function(dt)
		if not rocket.Parent then
			conn:Disconnect()
			return
		end
		if workspace:GetAttribute("TimeStop") then
			t0 += dt -- (v2.0: time is stopped - so is the rocket)
			return
		end
		local ts = TimeScale.Get() -- (v2.8) the Sandevistan: the rocket crawls, and flies on at full speed after it
		t0 += dt * (1 - ts)
		dt *= ts
		if homing and homing.Parent then
			local age = os.clock() - t0
			speed = math.min(Config.LockonMaxSpeed, speed + 90 * dt)
			-- (v2.0 fix) aim where the target will be, turn harder the closer it gets, and a proximity fuse:
			-- the old missile turned so slowly that it flew circles round anything close and never hit
			local tpos = homing.Position
			local dist = (tpos - pos).Magnitude
			if dist < 6 then
				conn:Disconnect()
				rocket:Destroy()
				ExplosionService.Explode(pos, {
					radius = Config.RocketRadius,
					damage = Config.RocketDamage,
					power = Config.RocketPower,
					attacker = attacker,
					cause = "Rocket",
					kind = "rocket",
					bot = o.bot,
				})
				return
			end
			local tv = homing.AssemblyLinearVelocity
			local goal = tpos + tv * math.clamp(dist / math.max(speed, 1), 0, 1.5) * 0.85
			-- (v2.0 fix) a top attack only when there is room for it: close up the climb made it curve up right
			-- before the target and fly over it. It climbs while it is far, and dives once it is near.
			local flatD = Vector3.new(tpos.X - pos.X, 0, tpos.Z - pos.Z).Magnitude
			if topAttack and age < 1.3 and flatD > 110 and pos.Y < tpos.Y + 45 then
				goal = Vector3.new(goal.X, math.max(pos.Y, tpos.Y) + math.min(60, flatD * 0.35), goal.Z) -- climb first, then dive
			end
			local want = (goal - pos).Unit
			local cur = vel.Unit
			local ang = math.acos(math.clamp(cur:Dot(want), -1, 1))
			local maxTurn = (Config.LockonTurnRate + 55 / math.max(dist, 8)) * dt * (topAttack and age < 1.4 and 1.6 or 1)
			local newDir = cur
			if ang > 1e-4 then
				local k = math.min(1, maxTurn / ang)
				newDir = (cur:Lerp(want, k)).Unit
			end
			vel = newDir * speed
		else
			vel += Vector3.new(0, -TimeScale.Gravity() * 0.06, 0) * dt
		end
		local step = vel * dt
		local hit = workspace:Raycast(pos, step, params)
		if hit or os.clock() - t0 > life then
			conn:Disconnect()
			local at = hit and (hit.Position - vel.Unit * 0.4) or pos
			rocket:Destroy()
			ExplosionService.Explode(at, {
				radius = Config.RocketRadius,
				damage = Config.RocketDamage,
				power = Config.RocketPower,
				attacker = attacker,
				cause = "Rocket",
				kind = "rocket",
				bot = o.bot,
			})
			return
		end
		pos += step
		rocket.CFrame = CFrame.lookAt(pos, pos + vel)
	end)
end

local function detonateAll(player: Player, detonator: Model)
	local list = {}
	for _, folderName in { "SpawnedProps", "Map" } do
		local f = workspace:FindFirstChild(folderName)
		if f then
			for _, m in f:GetDescendants() do
				if m:IsA("Model") and Items.Kind(m) == "c4" and not m:GetAttribute("HolderId") then
					local placed = m:GetAttribute("PlacedBy") == player.UserId
					local thrown = m:GetAttribute("LastHolder") == player.UserId and m:GetAttribute("PlacedBy") == nil
					if placed or thrown then
						table.insert(list, m)
					end
				end
			end
		end
	end
	if detonator.PrimaryPart then
		GoreService.Sound(#list > 0 and "detonator" or "dryfire", detonator.PrimaryPart, 1)
	end
	for i, c4 in list do
		task.delay(0.1 + (i - 1) * 0.08, ItemService.DetonateC4, c4, player)
	end
end

------------------------------------------------------------------------
-- boombox: plays any Roblox sound id, everybody hears it
------------------------------------------------------------------------

-- (v1.9.1) a boombox breaks: the music stops, it smokes and sparks, and it stays dead
local function breakBoombox(box: Model)
	if box:GetAttribute("Broken") then
		return
	end
	box:SetAttribute("Broken", true)
	box:SetAttribute("Playing", nil)
	local root = box.PrimaryPart
	if not root then
		return
	end
	local snd = root:FindFirstChild("Music")
	if snd and snd:IsA("Sound") then
		snd:Stop()
	end
	local glow = box:FindFirstChild("Glow")
	if glow and glow:IsA("BasePart") then
		glow.Material = Enum.Material.SmoothPlastic
		glow.Color = Color3.fromRGB(10, 10, 12)
	end
	for _, d in box:GetChildren() do
		if d:IsA("BasePart") and (d.Name == "Cone" or d.Name == "Speaker") then
			d.Color = Color3.fromRGB(14, 14, 16)
		end
	end
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(50, 50, 52)
	smoke.Opacity = 0.35
	smoke.RiseVelocity = 3
	smoke.Size = 1.6
	smoke.Parent = root
	game:GetService("Debris"):AddItem(smoke, 7)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Rate = 0
	sparks.Lifetime = NumberRange.new(0.3, 0.7)
	sparks.Speed = NumberRange.new(10, 22)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -40, 0)
	sparks.Size = NumberSequence.new(0.15, 0)
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90))
	sparks.LightEmission = 1
	sparks.Parent = root
	sparks:Emit(24)
	game:GetService("Debris"):AddItem(sparks, 2)
	for _ = 1, 5 do
		local s = Instance.new("Part")
		s.Size = Vector3.new(0.35, 0.25, 0.3)
		s.Color = Color3.fromRGB(30, 30, 34)
		s.Material = Enum.Material.Plastic
		s.CFrame = root.CFrame * CFrame.new(math.random() - 0.5, math.random() * 0.5, math.random() - 0.5)
		s.Parent = workspace:FindFirstChild("SpawnedProps") or workspace
		s.AssemblyLinearVelocity = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5) * 24
		game:GetService("Debris"):AddItem(s, 8)
	end
	GoreService.Sound("metal", root.Position, 1)
end

function ItemService.DamageBoombox(box: Model, amount: number)
	if Items.Kind(box) ~= "boombox" or box:GetAttribute("Broken") or amount <= 0 then
		return
	end
	local hp = (box:GetAttribute("HP") or Config.BoomboxHP) - amount
	box:SetAttribute("HP", hp)
	if hp <= 0 then
		breakBoombox(box)
	end
end

local function boombox(player: Player, box: Model, id: any)
	if Items.Kind(box) ~= "boombox" or not box.PrimaryPart or box:GetAttribute("Broken") then
		return
	end
	local char = player.Character
	local torso = char and char:FindFirstChild("Torso") :: BasePart?
	if OwnershipService.ItemHolder(box) ~= player and not (torso and (torso.Position - box.PrimaryPart.Position).Magnitude < 14) then
		return
	end
	local root = box.PrimaryPart
	local snd = root:FindFirstChild("Music")
	if id == "stop" then
		if snd and snd:IsA("Sound") then
			snd:Stop()
		end
		box:SetAttribute("Playing", nil)
		return
	end
	local text = tostring(id or "")
	text = string.match(text, "(%d+)%s*$") or "" -- also accepts "rbxassetid://123"
	if #text < 4 or #text > 20 then
		return
	end
	if not snd or not snd:IsA("Sound") then
		snd = Instance.new("Sound")
		snd.Name = "Music"
		snd.Parent = root
	end
	local music = snd :: Sound
	music:Stop()
	music.SoundId = "rbxassetid://" .. text
	music.Looped = true
	music.Volume = Config.BoomboxMaxVolume
	music.RollOffMode = Enum.RollOffMode.InverseTapered
	music.RollOffMinDistance = 14
	music.RollOffMaxDistance = Config.BoomboxRange
	music:Play()
	box:SetAttribute("Playing", true)
	box:SetAttribute("SoundId", text)
end

------------------------------------------------------------------------
-- nuke (game owner only)
------------------------------------------------------------------------

local function armNuke(player: Player?, nuke: Model, force: boolean?)
	if nuke:GetAttribute("Armed") or not (force or Items.Has(player, "nuke")) or not nuke.PrimaryPart then
		return
	end
	nuke:SetAttribute("Armed", true)
	local display = nuke:FindFirstChild("Display", true)
	local label = display and display:FindFirstChild("Count", true)
	task.spawn(function()
		for n = Config.NukeCountdown, 1, -1 do
			if not nuke.Parent or not nuke.PrimaryPart then
				return
			end
			if label and label:IsA("TextLabel") then
				label.Text = string.format("%02d", n)
			end
			nuke:SetAttribute("Countdown", n)
			GoreService.FX({ t = "nukewarn", n = n, p = nuke.PrimaryPart.Position })
			task.wait(1)
		end
		if not nuke.Parent or not nuke.PrimaryPart then
			return
		end
		local pos = nuke.PrimaryPart.Position
		OwnershipService.DropItem(nuke)
		nuke:Destroy()
		ExplosionService.Nuke(pos, player)
	end)
end

------------------------------------------------------------------------

-- (v1.9) a nuke that is armed the moment it exists (the community vote): it still has its countdown
ItemService.PlaceProp = nil :: ((string, CFrame, Player?) -> Instance?)? -- (set by Main: PropService.Place)
function ItemService.SpawnArmedNuke(pos: Vector3, attacker: Player?): Model?
	if not ItemService.PlaceProp then
		return nil
	end
	local nuke = ItemService.PlaceProp("nuke", CFrame.new(pos), nil)
	if not nuke or not nuke:IsA("Model") then
		return nil
	end
	armNuke(attacker, nuke, true)
	return nuke
end

function ItemService.Use(player: Player, item: Model)
	if OwnershipService.ItemHolder(item) ~= player then
		return
	end
	local kind = Items.Kind(item)
	if kind == "grenade" or kind == "flash" then
		ItemService.ArmGrenade(item, player)
	elseif kind == "bandage" then
		useBandage(player, item)
	elseif kind == "rope" then
		tie(player, item)
	elseif kind == "detonator" then
		detonateAll(player, item)
	elseif kind == "nuke" then
		armNuke(player, item)
	elseif kind == "chainsaw" then
		-- (v2.0) F: the motor on / off (every client plays its loop: ToolFX)
		item:SetAttribute("SawOn", not item:GetAttribute("SawOn"))
	elseif kind == "laser" then
		item:SetAttribute("On", not item:GetAttribute("On"))
		if item.PrimaryPart then
			GoreService.Sound("click", item.PrimaryPart, 1)
		end
	elseif kind and ItemService.OnUse then
		ItemService.OnUse(player, item, kind)
	end
end

function ItemService.Init()
	-- (v1.9.1) hard knocks break a boombox (a fall, being thrown into a wall)
	task.spawn(function()
		local CollectionService = game:GetService("CollectionService")
		local lastSpeed: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
		while true do
			task.wait(0.12)
			for _, box in CollectionService:GetTagged("Boombox") do
				local root = box:IsA("Model") and box.PrimaryPart
				if root and not box:GetAttribute("Broken") then
					local v = root.AssemblyLinearVelocity.Magnitude
					local last = lastSpeed[box] or 0
					lastSpeed[box] = v
					if last - v > 22 and not box:GetAttribute("HolderId") then
						ItemService.DamageBoombox(box, (last - v) * 0.9)
					end
				end
			end
		end
	end)
	task.spawn(flameLoop)
	tiesFolder()
	-- ropes whose body is gone (respawned / removed)
	task.spawn(function()
		while true do
			task.wait(4)
			for _, r in tiesFolder():GetChildren() do
				if r:IsA("RopeConstraint") then
					local a0, a1 = r.Attachment0, r.Attachment1
					if not a0 or not a1 or not a0:IsDescendantOf(workspace) or not a1:IsDescendantOf(workspace) then
						r:Destroy()
						if a0 then
							a0:Destroy()
						end
						if a1 then
							a1:Destroy()
						end
					end
				end
			end
		end
	end)
	-- (v2.0) a rope from a vehicle to somebody: when the vehicle pulls away and the rope goes tight, they are
	-- yanked off their feet and dragged behind it
	task.spawn(function()
		local lastYank: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
		local function vehicleOf(a: Attachment): Model?
			local p = a.Parent
			local m = p and p:FindFirstAncestorOfClass("Model")
			while m do
				if m:GetAttribute("Car") then
					return m
				end
				m = m:FindFirstAncestorOfClass("Model")
			end
			return nil
		end
		while true do
			task.wait(0.15)
			for _, r in tiesFolder():GetChildren() do
				if not r:IsA("RopeConstraint") or not r.Attachment0 or not r.Attachment1 then
					continue
				end
				for _, pair in { { r.Attachment0, r.Attachment1 }, { r.Attachment1, r.Attachment0 } } do
					local bodyAtt, carAtt = pair[1], pair[2]
					local bp = bodyAtt.Parent
					local body = bp and bp:IsA("BasePart") and DamageService.BodyOf(bp) or nil
					local car = vehicleOf(carAtt)
					if not body or not car or body:GetAttribute("Dead") or not car.PrimaryPart then
						continue
					end
					local v = car.PrimaryPart.AssemblyLinearVelocity
					local span = carAtt.WorldPosition - bodyAtt.WorldPosition
					if v.Magnitude < Config.RopeYankSpeed or span.Magnitude < r.Length * 0.9 or v:Dot(span) > 0 then
						continue -- (slow, slack, or driving towards them)
					end
					local now = os.clock()
					if now - (lastYank[body] or 0) < 0.9 then
						continue
					end
					lastYank[body] = now
					local pull = span.Unit * math.min(v.Magnitude, 70) * 0.8 + Vector3.new(0, 6, 0)
					DamageService.Blast(body, pull, Config.RopeYankDown)
				end
			end
		end
	end)
	-- picking up something that sticks somewhere pulls it out
	OwnershipService.OnHold = ItemService.Unstick
	-- a spear / C4 pinned in a wall that breaks (or a part that is gone / moved) falls out
	task.spawn(function()
		while true do
			task.wait(0.4)
			for item, rec in stuck do
				if rec.at then
					local on = rec.on
					if not item.Parent or not on.Parent or not on:IsGrounded() or (on.CFrame.Position - rec.at.Position).Magnitude > 0.05 then
						ItemService.Unstick(item)
					end
				end
				-- (v2.1) anything stuck that somebody holds comes out at once
				if item.Parent and item:GetAttribute("HolderId") ~= nil then
					ItemService.Unstick(item)
				end
			end
		end
	end)
	-- TVs: F next to one switches it on / off (every client plays the show); each time it comes
	-- on it is on the next channel
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt, _player)
		if prompt.Name ~= "TVPrompt" then
			return
		end
		local tv = prompt:FindFirstAncestorOfClass("Model")
		if not tv or not tv:GetAttribute("TV") then
			return
		end
		local on = not tv:GetAttribute("On")
		tv:SetAttribute("On", on)
		if on then
			tv:SetAttribute("Channel", ((tv:GetAttribute("Channel") or 0) % 3) + 1)
		end
		prompt.ActionText = on and "Switch off" or "Switch on"
		local screen = prompt.Parent
		if screen and screen:IsA("BasePart") then
			GoreService.Sound("tvOn", screen, 1)
		end
	end)
	-- back-up for thrown spears / C4: the server follows them too and sticks them if the thrower's
	-- report never comes (lag, the thrower left, ...)
	local flying: { [Model]: { last: Vector3, t0: number } } = {}
	local flyParams = RaycastParams.new()
	flyParams.FilterType = Enum.RaycastFilterType.Exclude
	RunService.Heartbeat:Connect(function(dt)
		local f = workspace:FindFirstChild("SpawnedProps")
		if not f then
			return
		end
		local now = workspace:GetServerTimeNow()
		for _, m in f:GetChildren() do
			if not m:IsA("Model") or flying[m] then
				continue
			end
			local kind = Items.Kind(m)
			if (kind == "spear" or kind == "c4") and m.PrimaryPart and not m:GetAttribute("HolderId") and not stuck[m] then
				local t = m:GetAttribute("LastHeldT")
				if typeof(t) == "number" and now - t < 0.5 then
					flying[m] = { last = m.PrimaryPart.Position, t0 = now }
				end
			end
		end
		for m, rec in flying do
			local root = m.PrimaryPart
			if not m.Parent or not root or stuck[m] or m:GetAttribute("HolderId") or now - rec.t0 > 5 then
				flying[m] = nil
				continue
			end
			local kind = Items.Kind(m)
			local v = root.AssemblyLinearVelocity
			local point = root.Position
			if kind == "spear" then
				local tip = m:FindFirstChild("SpearPoint")
				if tip and tip:IsA("BasePart") then
					point = tip.Position
				end
			end
			local from = rec.last
			rec.last = point
			local seg = point - from + v * dt
			if seg.Magnitude < 0.05 then
				if v.Magnitude < 1 and now - rec.t0 > 0.6 then
					flying[m] = nil
				end
				continue
			end
			local holderId = m:GetAttribute("LastHolder")
			local thrower = typeof(holderId) == "number" and Players:GetPlayerByUserId(holderId) or nil
			local ignore: { Instance } = { m }
			if thrower and thrower.Character then
				table.insert(ignore, thrower.Character)
			end
			local fx = workspace:FindFirstChild("FX")
			if fx then
				table.insert(ignore, fx)
			end
			flyParams.FilterDescendantsInstances = ignore
			local hit = workspace:Raycast(from, seg, flyParams)
			if hit and thrower and (hit.Instance.CanCollide or DamageService.BodyOf(hit.Instance)) then
				local speed = v.Magnitude
				if kind == "c4" or speed > 18 then
					ItemService.Stick(thrower, m, hit.Instance, hit.Position, speed, hit.Normal, v.Magnitude > 1 and v or seg)
				end
				flying[m] = nil
			end
		end
	end)
	ItemRemote.OnServerEvent:Connect(function(player, action, item, a, b, c, d, e)
		if typeof(item) ~= "Instance" or not item:IsA("Model") or not item:IsDescendantOf(workspace) then
			return
		end
		if action == "use" then
			ItemService.Use(player, item)
		elseif action == "melee" then
			ItemService.Melee(player, item, a, b, c)
		elseif action == "reload" then
			ItemService.Reload(player, item)
		elseif action == "cut" then
			cut(player, item, a)
		elseif action == "physgrab" then
			if physgunOk(player, item) and typeof(a) == "Instance" and a:IsA("BasePart") and a:IsDescendantOf(workspace) and typeof(b) == "Vector3" and typeof(c) == "Vector3" then
				if b == b and c == c and (c - a.Position).Magnitude < a.Size.Magnitude + 20 then
					OwnershipService.BeamGrab(player, a, b, c)
				end
			end
		elseif action == "physmove" then
			if physgunOk(player, item) and typeof(a) == "Vector3" and a == a and a.Magnitude < 1e5 then
				OwnershipService.BeamMove(player, a)
			end
		elseif action == "physdrop" then
			OwnershipService.BeamDrop(player)
		elseif action == "thrownhit" then
			if typeof(item) == "Instance" and item:IsA("Model") then
				ItemService.ThrownHit(player, item, a, b, c, e)
			end
		elseif action == "stick" then
			ItemService.Stick(player, item, a, b, c, d, e)
		elseif action == "tether" then
			tetherClick(player, item, a, b)
		elseif action == "rocket" then
			ItemService.FireRocket(player, item, a, b, c)
		elseif action == "smash" then
			-- the thrower's client saw its virus bottle / molotov hit something
			local sk = Items.Kind(item)
			if (sk == "virus" or sk == "molotov") and item:GetAttribute("LastHolder") == player.UserId and not item:GetAttribute("HolderId") and item.PrimaryPart then
				if typeof(a) == "Vector3" and a == a and (item.PrimaryPart.Position - a).Magnitude < 30 then
					if sk == "virus" then
						VirusService.SmashBottle(item, player)
					else
						FireService.Molotov(item, a, player)
					end
				end
			end
		elseif action == "flame" then
			ItemService.Flame(player, item, a)
		elseif action == "boombox" then
			if typeof(a) == "string" or typeof(a) == "number" then
				boombox(player, item, a)
			end
		elseif ItemService.OnAction then
			ItemService.OnAction(player, action, item, a, b, c, d, e)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		clearTetherFirst(player)
		local prefix = tostring(player.UserId) .. ":"
		for k in meleeTimes do
			if string.sub(k, 1, #prefix) == prefix then
				meleeTimes[k] = nil
			end
		end
	end)
end

return ItemService
