--!nonstrict
-- KnockService: interaction between bodies that live on different machines.
--   State    : a client reports whether it is knocked down (others may then drag it)
--   Strike   : a client's hand / held object hit someone else -> server forwards the hit
--   Struggle : an impaled player tears free
--   Kick     : a player's foot hit someone / something (C)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local HitMath = require(Shared:WaitForChild("HitMath"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))

local Modules = script.Parent
local DamageService = require(Modules:WaitForChild("DamageService"))
local GoreService = require(Modules:WaitForChild("GoreService"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StateRemote = Remotes:WaitForChild("State") :: RemoteEvent
local StrikeRemote = Remotes:WaitForChild("Strike") :: RemoteEvent
local StruggleRemote = Remotes:WaitForChild("Struggle") :: RemoteEvent
local KickRemote = Remotes:WaitForChild("Kick") :: RemoteEvent

local KnockService = {}

-- (v2.0) a punch landed (a zombie's punch is a bite: GameModeService)
KnockService.OnPunch = nil :: ((Player, Model, string) -> ())?
-- (v2.8) cyberware: a TITAN arm hits harder, SICKLE BLADES cut ((player, fist) -> { k, sever, bleed, cause }?)
KnockService.PunchMod = nil :: ((Player, Vector3) -> any)?
-- (v2.8.2) set by CyberService: an arm that hits a body with SICKLE BLADES out cuts it (nil = an ordinary blow)
KnockService.BladeMod = nil :: ((Player, Vector3) -> any)?

local strikeTimes: { [string]: number } = {}
local kickTimes: { [string]: number } = {}

-- C: the kicker's client saw its foot hit `target` at `foot` with velocity `vel`
local lastWeave: { [Player]: number } = {}

-- (v2.0) Left Alt: a slip to the side; for a moment punches, kicks and swings miss you
local function weave(player: Player)
	local char = player.Character
	if not char or char:GetAttribute("Dead") then
		return
	end
	local now = os.clock()
	if now - (lastWeave[player] or 0) < Config.WeaveCooldown * 0.8 then
		return
	end
	lastWeave[player] = now
	char:SetAttribute("WeaveUntil", workspace:GetServerTimeNow() + Config.WeaveTime + 0.08)
end

-- (v2.0) both hands empty, F: a punch. The puncher's client saw its fist hit `target`.
local function punch(player: Player, target: BasePart, fist: Vector3, vel: Vector3)
	local char = player.Character
	local torso = char and char:FindFirstChild("Torso") :: BasePart?
	if not char or not torso or char:GetAttribute("Dead") or target:IsDescendantOf(char) then
		return
	end
	if (torso.Position - fist).Magnitude > 7 or (target.Position - fist).Magnitude > target.Size.Magnitude * 0.5 + Config.GunHitTolerance then
		return
	end
	local speed = math.clamp(vel.Magnitude, 8, 40)
	local dir = vel.Magnitude > 0.1 and vel.Unit or torso.CFrame.LookVector
	local body, region = DamageService.BodyOf(target)
	local key = tostring(player.UserId) .. ":p:" .. (body and body:GetFullName() or target:GetFullName())
	local now = os.clock()
	if now - (kickTimes[key] or 0) < Config.FistTime * 0.8 then
		return
	end
	kickTimes[key] = now
	if body and region then
		if DamageService.Dodged(body) then
			return -- slipped
		end
		local k = 1
		local counter = char:GetAttribute("CounterUntil")
		if typeof(counter) == "number" and workspace:GetServerTimeNow() < counter then
			k = Config.WeaveCounter -- a counter right after a slip
			char:SetAttribute("CounterUntil", nil)
		end
		for _, arm in { "LeftArm", "RightArm" } do
			if char:GetAttribute("Prosthetic_" .. arm) then
				k *= Config.ProstheticArmStrength
				break
			end
		end
		local mod = KnockService.PunchMod and KnockService.PunchMod(player, fist) or nil
		if mod and typeof(mod.k) == "number" then
			k *= mod.k
		end
		local dmg = (Config.FistDamage + speed * Config.FistDamagePerSpeed) * (Config.LimbMultiplier[region] or 1) * k
		local mass = DamageService.PartMass(body, region)
		DamageService.ApplyDamage(body, region, dmg, fist, {
			cause = (mod and mod.cause or "Punched out by ") .. player.DisplayName,
			allowSever = mod ~= nil and mod.sever ~= nil,
			severAt = mod and mod.sever or nil,
			bleed = mod and mod.bleed or nil,
			bleedTime = mod and mod.bleed and 14 or nil,
			attacker = player,
			melee = true,
			quiet = dmg < 12 and not (mod and mod.bleed),
		})
		if mod and mod.bleed then
			GoreService.Sound("slash", fist, 1)
		end
		-- a hard one to the head knocks you out cold for a moment
		local down = (region == "Head" and speed * k > 24) and 1.6 or (k > 1.2 and 1.2 or nil)
		DamageService.Knock(body, region, dir * speed * Config.FistKnock * mass * k, down, fist)
		GoreService.Sound(k > 1.2 and "bodyHit" or "punch", fist, 1)
		if KnockService.OnPunch then
			KnockService.OnPunch(player, body, region)
		end
		return
	end
	-- loose things get a shove
	local root = target.AssemblyRootPart or target
	if root.Anchored then
		return
	end
	local push = dir * 14 * math.clamp(4 / math.max(root.AssemblyMass, 0.5), 0.15, 1.4)
	GoreService.FX({ t = "push", part = root, i = push * root.AssemblyMass, p = fist })
	GoreService.Sound("thud", fist, 0.7)
end

local function kick(player: Player, target: any, foot: any, vel: any, style: any)
	if target == "weave" then
		weave(player)
		return
	elseif target == "press" then
		-- (v2.0) the client holds a hand on its wound (sent about every half second while it does)
		local char = player.Character
		if char and not char:GetAttribute("Dead") then
			char:SetAttribute("PressingWound", workspace:GetServerTimeNow())
		end
		return
	end
	if style == "punch" then
		if typeof(target) == "Instance" and target:IsA("BasePart") and typeof(foot) == "Vector3" and typeof(vel) == "Vector3" and foot == foot and vel == vel then
			punch(player, target, foot, vel)
		end
		return
	end
	local drop = style == "drop"
	local slide = style == "slide" -- (v2.0) a slide tackle
	if typeof(target) ~= "Instance" or not target:IsA("BasePart") or target.Anchored or typeof(foot) ~= "Vector3" or typeof(vel) ~= "Vector3" then
		return
	end
	if vel ~= vel or foot ~= foot then
		return
	end
	local char = player.Character
	local torso = char and char:FindFirstChild("Torso") :: BasePart?
	if not char or not torso or char:GetAttribute("Dead") or target:IsDescendantOf(char) then
		return
	end
	if (torso.Position - foot).Magnitude > (drop and 11 or 9) or (target.Position - foot).Magnitude > target.Size.Magnitude * 0.5 + Config.GunHitTolerance then
		return
	end
	local speed = math.min(vel.Magnitude, drop and 48 or 45)
	local dir = vel.Magnitude > 0.1 and vel.Unit or torso.CFrame.LookVector
	local body, region = DamageService.BodyOf(target)
	local key = tostring(player.UserId) .. ":" .. (body and body:GetFullName() or target:GetFullName())
	local now = os.clock()
	if now - (kickTimes[key] or 0) < 0.3 then
		return
	end
	kickTimes[key] = now
	if body and region then
		if DamageService.Dodged(body) then
			return -- (v2.0) slipped the kick
		end
		if slide then
			-- (v2.0) the slide tackle: their feet are swept away in the direction of the slide, they fall over you
			if speed < Config.SlideTackleMinSpeed * 0.8 then
				return
			end
			local flat = Vector3.new(dir.X, 0, dir.Z)
			flat = flat.Magnitude > 0.1 and flat.Unit or torso.CFrame.LookVector
			local legRegion = (region == "LeftLeg" or region == "RightLeg") and region or "LeftLeg"
			DamageService.ApplyDamage(body, legRegion, Config.SlideTackleDamage, foot, {
				cause = "Slide-tackled by " .. player.DisplayName,
				allowSever = false,
				attacker = player,
				quiet = true,
			})
			local legMass = DamageService.PartMass(body, legRegion)
			DamageService.Blast(body, Vector3.new(0, 7, 0) - flat * 2, Config.SlideTripTime)
			for _, r in { "LeftLeg", "RightLeg" } do
				DamageService.Knock(body, r, (flat * speed * Config.SlideTackleSweep + Vector3.new(0, 16, 0)) * legMass, Config.SlideTripTime, nil)
			end
			GoreService.Sound("bodyHit", foot, 1)
			GoreService.Sound("thud", foot, 0.8)
			return
		end
		local dmg = (Config.KickDamage + speed * Config.KickDamagePerSpeed) * (Config.LimbMultiplier[region] or 1)
		if drop then
			dmg *= Config.DropKickDamageMult
		end
		local mass = DamageService.PartMass(body, region)
		DamageService.ApplyDamage(body, region, dmg, foot, {
			cause = (drop and "Drop-kicked by " or "Kicked by ") .. player.DisplayName,
			allowSever = false,
			attacker = player,
			melee = true,
		})
		if drop then
			-- both feet into them at full run: they fly
			local flat = Vector3.new(dir.X, 0, dir.Z)
			flat = flat.Magnitude > 0.1 and flat.Unit or dir
			DamageService.Knock(body, region, dir * speed * Config.KickKnock * mass * Config.DropKickKnockMult, 2.2, foot)
			DamageService.Blast(body, flat * Config.DropKickLaunch + Vector3.new(0, Config.DropKickLaunch * 0.3, 0), 2.2)
			GoreService.Sound("dropKick", foot, 1)
			GoreService.Sound("bodyHit", foot, 1)
			return
		end
		local knock = speed >= Config.KickKnockdownSpeed and 1.8 or nil
		DamageService.Knock(body, region, dir * speed * Config.KickKnock * mass, knock, foot)
		if knock then
			DamageService.Blast(body, dir * speed * 0.35 + Vector3.new(0, 6, 0), 1.8)
		end
		GoreService.Sound("punch", foot, 1)
		return
	end
	-- (v1.9) a drop kick shatters window glass and you fly on through it
	if drop and target.Material == Enum.Material.Glass and target.Transparency < 0.98 then
		local ExplosionService = require(script.Parent:WaitForChild("ExplosionService"))
		ExplosionService.Shatter(target, foot, dir)
		return
	end
	-- loose things: props, grenades, barrels, items on the floor
	local root = target.AssemblyRootPart or target
	if root.Anchored then
		return -- (the world, or something pinned in it)
	end
	local mass = root.AssemblyMass
	local push = dir * Config.KickPropImpulse * (drop and 2.2 or 1) * math.clamp(6 / math.max(mass, 0.5), 0.15, 1.6)
	local ok, owner = pcall(function()
		return root:GetNetworkOwner()
	end)
	if ok and owner == nil then
		pcall(function()
			root:ApplyImpulseAtPosition(push * mass, foot)
		end)
	else
		GoreService.FX({ t = "push", part = root, i = push * mass, p = foot })
	end
	root:SetAttribute("LastHolder", player.UserId)
	root:SetAttribute("LastHeldT", workspace:GetServerTimeNow())
	GoreService.Sound("thud", foot, 0.8)
end

local function bodyMass(model: Model): number
	local m = 0
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			m += d.Mass
		end
	end
	return math.max(m, 1)
end

function KnockService.Init()
	StateRemote.OnServerEvent:Connect(function(player, knocked)
		local char = player.Character
		if char and typeof(knocked) == "boolean" and not char:GetAttribute("Dead") then
			char:SetAttribute("Knocked", knocked)
		end
	end)

	-- a player tore a body part off a spike (the pin itself lives on that player's client)
	StruggleRemote.OnServerEvent:Connect(function(player, region)
		local char = player.Character
		if not char or char:GetAttribute("Dead") then
			return
		end
		if typeof(region) == "string" and RigInfo.RegionPart[region] then
			DamageService.TearFree(char, region)
		elseif char:GetAttribute("Impaled") then
			DamageService.Unimpale(char, true)
		end
	end)

	StrikeRemote.OnServerEvent:Connect(function(player, target, velocity, strikerMass)
		if typeof(target) ~= "Instance" or not target:IsA("BasePart") or typeof(velocity) ~= "Vector3" or typeof(strikerMass) ~= "number" then
			return
		end
		if velocity.Magnitude > 90 or strikerMass <= 0 or strikerMass > 60 then
			return
		end
		local body, region = DamageService.BodyOf(target)
		if not body or not region or body == player.Character then
			return
		end
		local torso = player.Character and player.Character:FindFirstChild("Torso")
		if not torso or (torso.Position - target.Position).Magnitude > 9 then
			return
		end
		local key = tostring(player.UserId) .. ":" .. body:GetFullName()
		local now = os.clock()
		if now - (strikeTimes[key] or 0) < 0.2 then
			return
		end
		strikeTimes[key] = now

		local rel = velocity - target.AssemblyLinearVelocity
		local speed = rel.Magnitude
		-- (v2.8.2) SICKLE BLADES out on the arm that hit: a cut, not a bump (bleeding; tier 2+ takes limbs off)
		local blade = KnockService.BladeMod and KnockService.BladeMod(player, target.Position) or nil
		if blade and speed >= Config.StrikeMinSpeed * 0.5 then
			local dmg = (blade.base or 20) + math.min(speed, 40) * (blade.perSpeed or 0.8)
			DamageService.ApplyDamage(body, region, dmg * (Config.LimbMultiplier[region] or 1), target.Position, {
				cause = "Sliced by " .. player.DisplayName,
				allowSever = blade.sever ~= nil,
				severAt = blade.sever,
				bleed = 0.9,
				bleedTime = 14,
				attacker = player,
				melee = true,
			})
			GoreService.Sound("slash", target.Position, 1)
			GoreService.Burst(target.Position, rel.Magnitude > 0.1 and rel.Unit or Vector3.yAxis, 10, 12)
			DamageService.Knock(body, region, (rel.Magnitude > 0.1 and rel.Unit or Vector3.zero) * math.min(speed, 30) * 2, nil, target.Position)
			return
		end
		if speed < Config.StrikeMinSpeed then
			return
		end
		local mass = bodyMass(body)
		local energy = HitMath.ImpactEnergy(strikerMass, mass, speed)
		local dir = rel.Unit
		local impulse = dir * math.min(speed * strikerMass * Config.StrikeImpulse, 900) + Vector3.new(0, speed * strikerMass * 0.6, 0)
		local knock = (speed >= Config.StrikeKnockSpeed or energy >= Config.ObjectKnockdownEnergy) and math.clamp(0.9 + speed / 40, 1, 3) or nil
		GoreService.Sound(strikerMass > 3 and "bodyHit" or "punch", target.Position, 1)
		DamageService.MarkAttacker(body, player)
		DamageService.Knock(body, region, impulse, knock, target.Position)
		if HitMath.EnergyDamage(energy) > 0 then
			DamageService.ApplyEnergy(body, region, energy, target.Position, "Beaten by " .. player.DisplayName, nil, player)
		end
	end)

	KickRemote.OnServerEvent:Connect(kick)

	Players.PlayerRemoving:Connect(function(player)
		lastWeave[player] = nil
		local prefix = tostring(player.UserId) .. ":"
		for _, map in { strikeTimes, kickTimes } do
			for k in map do
				if string.sub(k, 1, #prefix) == prefix then
					map[k] = nil
				end
			end
		end
	end)
end

return KnockService
