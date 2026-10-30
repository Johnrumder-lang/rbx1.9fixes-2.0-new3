--!nonstrict
-- DamageService: per-limb health, breaking, severing, piercing, bullets, crushing, bleeding and
-- death for every ragdoll body (player characters, corpses and dummies).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))
local HitMath = require(Shared:WaitForChild("HitMath"))

local Modules = script.Parent
local GoreService = require(Modules:WaitForChild("GoreService"))
local RigBuilder = require(Modules:WaitForChild("RigBuilder"))

local FXRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("FX") :: RemoteEvent

local DamageService = {}
DamageService.Shield = nil :: ((Model, string, number, Vector3?, any) -> boolean)? -- (set by CalamityService)
DamageService.ShieldBullet = nil :: ((Model, string, Vector3, Vector3, Player?, string?) -> boolean)?
-- (v2.8) cyberware: change the damage before it lands ((model, region, dmg, opts) -> (dmg, opts?)); see who got hurt after
DamageService.Modifiers = {} :: { (Model, string, number, any, Vector3?) -> (number, any?) }
DamageService.AfterDamage = {} :: { (Model, string, number, any) -> () }
-- (v2.8) may this body be knocked over / pushed? ((model, kind "knock" | "blast", ragdollTime, push) -> (ragdollTime, push))
DamageService.KnockFilter = nil :: ((Model, string, number?, Vector3?) -> (number?, Vector3?))?
DamageService.heavyHit = false -- (v2.8) set while a car / a nuke hits (a COLOSSUS goes down only then)
DamageService.ImpactScale = nil :: ((Model) -> number)? -- (v2.8) fall damage x (STRIDER LEGS)

type BodyState = {
	model: Model,
	player: Player?,
	humanoid: Humanoid?,
	bleeds: { { rate: number, untilTime: number } },
	lastHit: number,
	onDeath: ((cause: string) -> ())?,
	dead: boolean,
	impaled: { [BasePart]: number }, -- part -> time it was impaled
	spikes: { [BasePart]: { spike: BasePart, point: Vector3, t: number } },
	lastAttacker: { player: Player, t: number }?,
}

local bodies: { [Model]: BodyState } = {}

function DamageService.Register(model: Model, info: { player: Player?, humanoid: Humanoid?, onDeath: ((string) -> ())? })
	bodies[model] = {
		model = model,
		player = info.player,
		humanoid = info.humanoid,
		bleeds = {},
		lastHit = 0,
		onDeath = info.onDeath,
		dead = false,
		impaled = {},
		spikes = {},
		lastAttacker = nil,
	}
	model.Destroying:Connect(function()
		bodies[model] = nil
	end)
end

function DamageService.Unregister(model: Model)
	bodies[model] = nil
end

function DamageService.Get(model: Model): BodyState?
	return bodies[model]
end

-- every registered body (players, corpses, dummies)
function DamageService.Bodies(): { [Model]: BodyState }
	return bodies
end

-- set by KillService: (victimModel, killer: Player?, state) when a body dies
DamageService.OnKill = nil :: ((Model, Player?, any) -> ())?
-- set by NPCService: a non-player body was knocked over (hostile NPCs go limp for a while)
DamageService.OnRagdoll = nil :: ((Model, number) -> ())?
-- set by VirusService: a heal dart cures the virus
DamageService.OnHeal = nil :: ((Model) -> ())?
-- set by GameModeService: may `attacker` hurt the player `victim` right now? (team mates, the lobby)
DamageService.CanHurt = nil :: ((Player, Player) -> boolean)?

-- (v2.0) the first seconds after spawning nothing hurts you
function DamageService.SpawnProtected(model: Model): boolean
	local untilT = model:GetAttribute("SpawnProtect")
	return typeof(untilT) == "number" and workspace:GetServerTimeNow() < untilT
end

-- (v2.0) weaving: the body slips punches, kicks and swings for a moment (Left Alt). True = this hit missed; the one
-- who slipped it gets a counter window (their next punch hits harder).
function DamageService.Dodged(model: Model): boolean
	local untilT = model:GetAttribute("WeaveUntil")
	if typeof(untilT) == "number" and workspace:GetServerTimeNow() < untilT then
		model:SetAttribute("CounterUntil", workspace:GetServerTimeNow() + 1.0)
		local head = model:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			GoreService.Sound("weave", head, 1)
		end
		return true
	end
	return false
end

-- the game mode protects this body from that attacker
function DamageService.Protected(model: Model, attacker: Player?): boolean
	if DamageService.SpawnProtected(model) then
		return true
	end
	local st = bodies[model]
	if not attacker or not st or not st.player or not DamageService.CanHurt then
		return false
	end
	return not DamageService.CanHurt(attacker, st.player)
end

-- (v2.0) a player body that another player carries (Config.DragOwnerMode) is simulated on the carrier's machine:
-- pushes go to whoever simulates it
local function pushParts(model: Model, region: string?, impulse: Vector3?, point: Vector3?, velocity: Vector3?)
	if impulse then
		local partName = region and RigInfo.RegionPart[region] or "Torso"
		local part = model:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			GoreService.FX({ t = "push", part = part, i = impulse, p = point or part.Position })
		end
	end
	if velocity then
		for _, d in model:GetChildren() do
			if d:IsA("BasePart") then
				GoreService.FX({ t = "push", part = d, i = velocity * d:GetMass(), p = d.Position })
			end
		end
	end
end

-- Who is to blame for an object that hit someone: the driver of a car, or whoever held / threw
-- the object a moment ago.
function DamageService.AttackerOf(part: Instance?): Player?
	if not part then
		return nil
	end
	local m = part:FindFirstAncestorOfClass("Model")
	while m do
		local driver = m:GetAttribute("DriverId")
		if typeof(driver) == "number" then
			return Players:GetPlayerByUserId(driver)
		end
		if m:GetAttribute("Car") then
			break
		end
		m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
	end
	local holderInst: Instance? = part
	if part:IsA("BasePart") and part.AssemblyRootPart then
		holderInst = part.AssemblyRootPart
	end
	local model = part:FindFirstAncestorOfClass("Model")
	for _, inst in { holderInst, part, model } do
		if inst then
			local id = inst:GetAttribute("LastHolder")
			local t = inst:GetAttribute("LastHeldT")
			if typeof(id) == "number" and typeof(t) == "number" and workspace:GetServerTimeNow() - t < 6 then
				return Players:GetPlayerByUserId(id)
			end
		end
	end
	return nil
end

function DamageService.BodyOf(inst: Instance): (Model?, string?)
	local m = inst:FindFirstAncestorOfClass("Model")
	while m and not bodies[m] do
		m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
	end
	if not m then
		return nil, nil
	end
	local region = RigInfo.PartRegion[inst.Name]
	-- colliders, wounds, bones ... live inside a limb: use that limb
	local p = inst.Parent
	while not region and p and p ~= m do
		region = RigInfo.PartRegion[p.Name]
		p = p.Parent
	end
	if not region and inst:IsA("BasePart") then
		-- hats, hair, root part, loose gore: the closest real body part
		local bestD = math.huge
		for name, r in RigInfo.PartRegion do
			local bp = m:FindFirstChild(name)
			if bp and bp:IsA("BasePart") then
				local d = (bp.Position - inst.Position).Magnitude
				if d < bestD then
					region, bestD = r, d
				end
			end
		end
	end
	return m, region
end

local function addBleed(state: BodyState, rate: number, duration: number)
	table.insert(state.bleeds, { rate = rate, untilTime = os.clock() + duration })
end

function DamageService.Kill(model: Model, cause: string, cyberAttack: boolean?)
	local state = bodies[model]
	if not state or state.dead then
		return
	end
	if model:GetAttribute("God") and not cyberAttack and cause ~= "Reset" and not model:GetAttribute("ForceKill") then
		return
	end
	if DamageService.SpawnProtected(model) and cause ~= "Reset" and cause ~= "Fell into the void" and not model:GetAttribute("ForceKill") then
		return -- (v2.0) spawn protection
	end
	state.dead = true
	model:SetAttribute("Dead", true)
	model:SetAttribute("DeathCause", cause)
	local killer: Player? = nil
	local la = state.lastAttacker
	if la and os.clock() - la.t <= Config.KillCreditTime and la.player.Parent and la.player ~= state.player then
		killer = la.player
	end
	if DamageService.OnKill then
		task.spawn(DamageService.OnKill, model, killer, state)
	end
	model:SetAttribute("Knocked", true)
	RigBuilder.GoLimp(model)
	-- died on a spike: the body stays on it
	task.defer(DamageService.ReattachImpales, model)
	if state.humanoid and state.humanoid.Parent then
		state.humanoid.Health = 0
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") and state.player then
		GoreService.Sound("oof", head, 1)
	end
	if state.onDeath then
		task.spawn(state.onDeath, cause)
	end
end

-- Push / knock a body down. Players are simulated on their own client, so they get told to do it.
-- (v2.0) a zombie stays on its feet (pushed a little, never knocked over) while it still has a leg to stand on
local function zombieStands(model: Model): boolean
	return not Config.ZombieKnockdown and model:GetAttribute("Zombie") == true
		and not (model:GetAttribute("Severed_LeftLeg") and model:GetAttribute("Severed_RightLeg"))
end

function DamageService.Knock(model: Model, region: string?, impulse: Vector3?, ragdollTime: number?, point: Vector3?)
	local state = bodies[model]
	if not state or model:GetAttribute("Wonder") == true then
		return -- (v1.9.1: nothing pushes a Wonder player)
	end
	if zombieStands(model) then
		ragdollTime = nil
		impulse = impulse and impulse * 0.35 or nil
	end
	if DamageService.SpawnProtected(model) then
		return
	end
	if DamageService.KnockFilter then
		ragdollTime, impulse = DamageService.KnockFilter(model, "knock", ragdollTime, impulse)
	end
	-- a player's current body is simulated by that player's client (while another player carries it
	-- (v2.0), by the carrier's machine: the push goes there, the knock-down still to its own client)
	if state.player and state.player.Character == model then
		FXRemote:FireClient(state.player, { t = "knock", r = region, i = impulse, rt = ragdollTime, p = point })
		if model:GetAttribute("DragOwned") then
			pushParts(model, region, impulse, point, nil)
		end
		return
	end
	if ragdollTime and DamageService.OnRagdoll then
		DamageService.OnRagdoll(model, ragdollTime)
	end
	if impulse then
		local partName = region and RigInfo.RegionPart[region] or "Torso"
		local part = model:FindFirstChild(partName) :: BasePart?
		if part then
			pcall(function()
				if point and (point - part.Position).Magnitude < part.Size.Magnitude then
					part:ApplyImpulseAtPosition(impulse, point)
				else
					part:ApplyImpulse(impulse)
				end
			end)
		end
	end
end

-- an explosion throws the whole body (every part gets the same velocity change)
function DamageService.Blast(model: Model, velocity: Vector3, ragdollTime: number?)
	local state = bodies[model]
	if not state or model:GetAttribute("Wonder") == true then
		return
	end
	if zombieStands(model) then
		ragdollTime = nil
		velocity *= 0.35
	end
	if DamageService.SpawnProtected(model) then
		return
	end
	if DamageService.KnockFilter then
		local v2
		ragdollTime, v2 = DamageService.KnockFilter(model, "blast", ragdollTime, velocity)
		velocity = v2 or Vector3.zero
	end
	if state.player and state.player.Character == model then
		FXRemote:FireClient(state.player, { t = "knock", all = velocity, rt = ragdollTime })
		if model:GetAttribute("DragOwned") then
			pushParts(model, nil, nil, nil, velocity)
		end
		return
	end
	if ragdollTime and DamageService.OnRagdoll then
		DamageService.OnRagdoll(model, ragdollTime)
	end
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and not d.Anchored then
			pcall(function()
				d.AssemblyLinearVelocity += velocity
			end)
		end
	end
end

-- A dead body is thrown (sniper head shot, ...). A player's body is normally simulated by
-- that player's client; a corpse is taken over by the server right away, so the throw happens
-- for sure and looks the same for everybody.
function DamageService.Fling(model: Model, velocity: Vector3, spinAxis: Vector3?)
	local state = bodies[model]
	if not state or model:GetAttribute("Wonder") == true then
		return
	end
	if not state.dead or model:GetAttribute("DraggedBy") then
		DamageService.Blast(model, velocity, 3)
		return
	end
	if state.player and state.player.Character == model then
		-- (v1.9) the player's own client keeps the body and throws it itself. Taking it over made the
		-- body jump back to where the server had last seen it - tens of studs behind at high speed
		-- ("teleporting back after a huge knockback").
		FXRemote:FireClient(state.player, { t = "knock", all = velocity * 1.1, rt = 3 })
		return
	elseif DamageService.OnRagdoll then
		DamageService.OnRagdoll(model, 3)
	end
	local spin = spinAxis and spinAxis:Cross(Vector3.yAxis) or Vector3.zero
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and not d.Anchored then
			pcall(function()
				d.AssemblyLinearVelocity += velocity * (d.Name == "Head" and 1.25 or 1)
				if spin.Magnitude > 0.01 then
					d.AssemblyAngularVelocity += spin.Unit * -8
				end
			end)
		end
	end
end

-- sleep dart: knocked out - limp, the screen goes black, no sound, no moving
function DamageService.Sleep(model: Model, duration: number, by: Player?, cyberAttack: boolean?)
	local state = bodies[model]
	if not state or state.dead or (model:GetAttribute("God") and not cyberAttack) then
		return
	end
	DamageService.MarkAttacker(model, by)
	model:SetAttribute("Asleep", true)
	local token = os.clock()
	model:SetAttribute("SleepToken", token)
	task.delay(duration, function()
		if model.Parent and model:GetAttribute("SleepToken") == token then
			model:SetAttribute("Asleep", nil)
		end
	end)
	if state.player and state.player.Character == model then
		FXRemote:FireClient(state.player, { t = "sleep", d = duration })
	elseif DamageService.OnRagdoll then
		DamageService.OnRagdoll(model, duration)
	end
end

-- (v2.8) a paralysis dart: limp on the ground for `duration` s, awake (the body's own machine keeps it down: ParalyzedUntil)
function DamageService.Paralyze(model: Model, duration: number, by: Player?)
	local state = bodies[model]
	if not state or state.dead or model:GetAttribute("God") then
		return
	end
	DamageService.MarkAttacker(model, by)
	model:SetAttribute("ParalyzedUntil", workspace:GetServerTimeNow() + duration)
	if state.player and state.player.Character == model then
		FXRemote:FireClient(state.player, { t = "knock", rt = 3 })
	elseif DamageService.OnRagdoll then
		DamageService.OnRagdoll(model, duration)
	end
end

-- heal dart: HP back everywhere, bones set, bleeding stops, wakes you up, cures the virus
function DamageService.Heal(model: Model)
	local state = bodies[model]
	if not state or state.dead then
		return
	end
	for _, region in RigInfo.Regions do
		if not model:GetAttribute("Severed_" .. region) then
			local hp = math.min(Config.LimbMaxHP, (model:GetAttribute("HP_" .. region) or Config.LimbMaxHP) + Config.HealDartHP)
			model:SetAttribute("HP_" .. region, hp)
			if hp > 0 then
				model:SetAttribute("Broken_" .. region, false)
			end
		end
	end
	DamageService.StopBleeding(model)
	-- (v2.8.2) the broken bones sink back in, the wounds and bullet holes close (slowly)
	for _, region in RigInfo.Regions do
		if not model:GetAttribute("Severed_" .. region) then
			local part = model:FindFirstChild(RigInfo.RegionPart[region] or "")
			if part and part:IsA("BasePart") then
				pcall(GoreService.Mend, part, 2.5)
			end
		end
	end
	model:SetAttribute("ParalyzedUntil", nil) -- (v2.8)
	model:SetAttribute("Blood", math.min(100, (model:GetAttribute("Blood") or 100) + Config.HealDartBlood))
	if model:GetAttribute("Asleep") then
		model:SetAttribute("Asleep", nil)
		model:SetAttribute("SleepToken", nil)
		if state.player and state.player.Character == model then
			FXRemote:FireClient(state.player, { t = "wake" })
		end
	end
	if DamageService.OnHeal then
		DamageService.OnHeal(model)
	end
	local torso = model:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		GoreService.FX({ t = "heal", p = torso.Position })
	end
end

-- mass of one body part (+ what is rigidly attached to it, e.g. the head on the torso)
function DamageService.PartMass(model: Model, region: string): number
	local part = model:FindFirstChild(RigInfo.RegionPart[region] or "Torso")
	if part and part:IsA("BasePart") then
		return part.AssemblyMass
	end
	return 2
end

-- (v2.0) a bot (mode NPC) hurt this body: it gets the kill if the body dies soon (gun game, zombies)
function DamageService.MarkBotAttacker(model: Model, bot: Model?)
	local state = bodies[model]
	if state and bot and bot ~= model then
		(state :: any).lastBot = { model = bot, t = os.clock() }
	end
end

function DamageService.MarkAttacker(model: Model, player: Player?)
	local state = bodies[model]
	if state and player and player ~= state.player and not state.dead then
		state.lastAttacker = { player = player, t = os.clock() }
	end
end

function DamageService.StopBleeding(model: Model)
	local state = bodies[model]
	if not state then
		return
	end
	table.clear(state.bleeds)
	model:SetAttribute("Bleeding", false)
end

local function hurtClient(state: BodyState, amount: number, region: string)
	if state.player then
		FXRemote:FireClient(state.player, { t = "hurt", a = amount, r = region })
	end
end

export type DamageOpts = {
	cause: string?,
	allowSever: boolean?,
	bullet: boolean?,
	quiet: boolean?, -- no splatter / sound (crush ticks)
	attacker: Player?, -- who did it (kill credit)
	severAt: number?, -- one hit this strong severs the limb / head (blades, explosions)
	bleed: number?,
	bleedTime: number?,
	blast: boolean?, -- (v2.8) an explosion did it (BLASTWEAVE)
	nuke: boolean?,
	cyberAttack: boolean?,
	melee: boolean?, -- (v2.8) a punch / kick / blade up close (STATIC DERMIS shocks back)
}

-- Core: subtract HP from one region and play out the consequences.
function DamageService.ApplyDamage(model: Model, region: string, dmg: number, pointIn: Vector3?, optsIn: DamageOpts?)
	local state = bodies[model]
	if not state or dmg <= 0 then
		return
	end
	if model:GetAttribute("God") and not (optsIn and optsIn.cyberAttack) then
		return -- the game owner flying (invincible)
	end
	if DamageService.SpawnProtected(model) then
		return -- (v2.0) just spawned
	end
	if not (optsIn and optsIn.cyberAttack) and DamageService.Shield and DamageService.Shield(model, region, dmg, pointIn, optsIn) then
		return -- (v1.9) the Wonder spec: it goes through them
	end
	if #DamageService.Modifiers > 0 then
		for _, m in DamageService.Modifiers do
			local ok, d2, o2 = pcall(m, model, region, dmg, optsIn or {}, pointIn) -- (v2.8.2: + where it hit)
			if ok and typeof(d2) == "number" then
				dmg = d2
				if o2 ~= nil then
					optsIn = o2
				end
			end
			if dmg <= 0 then
				return
			end
		end
	end
	if model:GetAttribute("Severed_" .. region) then
		return
	end
	local partName = RigInfo.RegionPart[region]
	local part = partName and model:FindFirstChild(partName) :: BasePart?
	if not part then
		return
	end
	local opts: any = optsIn or {}
	if opts.attacker and DamageService.Protected(model, opts.attacker) then
		return
	end
	-- (v2.0) zombies: only the head counts (shoot off their legs and they crawl - but a hit to the body does nothing)
	if model:GetAttribute("Zombie") then
		if region == "Torso" then
			if not opts.quiet then
				GoreService.Burst(pointIn or part.Position, Vector3.yAxis, 4, 8)
			end
			return
		end
		opts = table.clone(opts)
		opts.bleed = nil
	end
	-- gore is placed relative to where the server sees the part (its copy may lag behind)
	local point: Vector3 = part.Position
	if pointIn and (pointIn - part.Position).Magnitude <= 4 then
		point = pointIn
	elseif pointIn then
		local dir = pointIn - part.Position
		point = part.Position + dir.Unit * math.min(dir.Magnitude, part.Size.Magnitude * 0.5)
	end

	local hp = (model:GetAttribute("HP_" .. region) or Config.LimbMaxHP) - dmg
	model:SetAttribute("HP_" .. region, hp)
	state.lastHit = os.clock()
	if opts.attacker and opts.attacker ~= state.player and not state.dead then
		state.lastAttacker = { player = opts.attacker, t = os.clock() }
	end

	-- (v2.8.1) a TITAN arm is metal: no holes, no wounds - sparks and black oil
	local chrome = (region == "LeftArm" and model:GetAttribute("Titan_L") ~= nil) or (region == "RightArm" and model:GetAttribute("Titan_R") ~= nil)
	if not opts.quiet then
		local outward = (point - part.Position)
		local dir = outward.Magnitude > 0.01 and outward.Unit or Vector3.yAxis
		if chrome then
			GoreService.FX({ t = "burst", p = point, d = dir, n = math.clamp(math.floor(2 + dmg * 0.2), 1, 30), s = 12, black = true })
			GoreService.Sound("metal", point, 0.7)
		else
			GoreService.Burst(point, dir, 3 + dmg * 0.3, 10 + math.min(dmg, 120) * 0.12)
			if opts.bullet then
				GoreService.BulletHole(part, point)
			elseif dmg >= 10 then
				GoreService.Wound(part, point, math.clamp(dmg / 90, 0, 1.2))
			end
		end
		if dmg >= 60 then
			GoreService.Sound("heavyHit", point, 0.8)
		elseif dmg >= 12 and not opts.bullet then
			GoreService.Sound("bodyHit", point, 0.8)
		end
	end
	if opts.bleed then
		addBleed(state, opts.bleed, opts.bleedTime or 20)
		model:SetAttribute("WoundAt", region) -- (v2.0: a free hand presses on the latest wound)
	elseif hp <= Config.InjuredHP and hp > 0 and dmg >= 15 then
		addBleed(state, 0.25, 8)
		model:SetAttribute("WoundAt", region)
	end
	if not state.dead then
		hurtClient(state, dmg, region)
	end
	for _, f in DamageService.AfterDamage do
		task.spawn(f, model, region, dmg, opts)
	end

	local broken = model:GetAttribute("Broken_" .. region)
	local allowSever = opts.allowSever ~= false

	if region == "Head" then
		if allowSever and (hp <= Config.DecapitateHP or dmg >= (opts.severAt or Config.DecapitateSingleHit)) then
			model:SetAttribute("Severed_Head", true)
			model:SetAttribute("Broken_Head", true)
			GoreService.Decapitate(model)
			DamageService.Kill(model, opts.cause or "Decapitated", opts.cyberAttack)
		elseif hp <= 0 and not broken then
			model:SetAttribute("Broken_Head", true)
			GoreService.Crush(part, point)
			GoreService.Burst(point, Vector3.yAxis, 40, 22)
			GoreService.Sound("boneCrack", part, 1)
			DamageService.Kill(model, opts.cause or "Skull crushed", opts.cyberAttack)
		end
	elseif region == "Torso" then
		if hp <= 0 and not broken then
			model:SetAttribute("Broken_Torso", true)
			GoreService.Crush(part, point)
			GoreService.Burst(point, Vector3.yAxis, 50, 24)
			GoreService.Sound("boneCrack", part, 1)
			DamageService.Kill(model, opts.cause or "Crushed", opts.cyberAttack)
		end
	else
		if allowSever and (hp <= Config.SeverHP or dmg >= (opts.severAt or Config.SeverSingleHit)) then
			model:SetAttribute("Severed_" .. region, true)
			model:SetAttribute("Broken_" .. region, true)
			model:SetAttribute("HP_" .. region, math.min(hp, Config.SeverHP))
			GoreService.Sever(model, region)
			addBleed(state, Config.BleedSevered, Config.BleedDuration)
		elseif hp <= 0 and not broken and model:GetAttribute("Prosthetic_" .. region) ~= true then
			-- (v2.1: a prosthetic limb never breaks - it can only be ripped off, above)
			model:SetAttribute("Broken_" .. region, true)
			GoreService.Crush(part, point)
			GoreService.Burst(point, Vector3.yAxis, 25, 16)
			GoreService.Sound("boneCrack", part, 1)
			addBleed(state, Config.BleedBroken, Config.BleedDuration * 0.6)
		end
	end

	if dmg >= Config.GibHit and (region == "Torso" or region == "Head") and not opts.bullet then
		GoreService.Gibs(point, 6, 30)
	end
end

-- Hitting the ground / a wall: velocity change of the body part.
function DamageService.ApplyImpact(model: Model, region: string, dv: number, point: Vector3?)
	local dmg = (dv - Config.ImpactMin) * Config.DamagePerSpeed * (Config.LimbMultiplier[region] or 1)
	if DamageService.ImpactScale then
		dmg *= DamageService.ImpactScale(model)
	end
	if dmg > 0 then
		DamageService.ApplyDamage(model, region, dmg, point, { cause = "Fell" })
	end
end

-- Hit by an object: kinetic energy of the collision.
function DamageService.ApplyEnergy(model: Model, region: string, energy: number, point: Vector3?, cause: string?, other: Instance?, attacker: Player?)
	local dmg = HitMath.EnergyDamage(energy) * (Config.LimbMultiplier[region] or 1)
	attacker = attacker or DamageService.AttackerOf(other)
	if dmg > 0 then
		local carHit = other ~= nil and other:FindFirstAncestorOfClass("Model") ~= nil and (other:FindFirstAncestorOfClass("Model") :: Model):GetAttribute("Car") ~= nil
		DamageService.ApplyDamage(model, region, dmg, point, {
			cause = cause or (carHit and "Run over" or "Hit by something heavy"),
			attacker = attacker,
		})
	end
	if energy >= Config.ObjectKnockdownEnergy then
		local m = other and other:FindFirstAncestorOfClass("Model")
		DamageService.heavyHit = m ~= nil and m:GetAttribute("Car") ~= nil -- (v2.8) a car throws even a COLOSSUS
		DamageService.Knock(model, region, nil, math.clamp(0.8 + energy / 6000, 1, 3))
		DamageService.heavyHit = false
	end
end

-- Something heavy resting on a body part.
function DamageService.ApplyCrush(model: Model, region: string, amount: number, point: Vector3?)
	DamageService.ApplyDamage(model, region, amount, point, { cause = "Crushed", quiet = amount < 6 })
end

-- Sharp object went in. Torso / head = death and the corpse stays on the spike.
function DamageService.ApplyPierce(model: Model, region: string, speed: number, sharpness: number, spike: BasePart, point: Vector3)
	local state = bodies[model]
	if not state then
		return
	end
	-- the stab itself plus the blunt force of the fall / run that drove you onto it
	local stab = HitMath.PierceDamage(speed, sharpness)
	if stab <= 0 then
		return
	end
	local blunt = math.max(0, speed - Config.ImpactMin) * Config.DamagePerSpeed
	local dmg = (stab + blunt) * (Config.LimbMultiplier[region] or 1)
	local part = model:FindFirstChild(RigInfo.RegionPart[region]) :: BasePart?
	if not part then
		return
	end
	-- only stick to things that do not just fly along with you
	if spike:IsGrounded() or spike.AssemblyMass > 8 then
		local isLivePlayer = state.player ~= nil and state.player.Character == model
		if isLivePlayer then
			-- living players are NOT pinned to the spike (that froze them in place): they get the
			-- wound, the blood and the damage. If they die on it, the corpse stays on the spike
			-- (see ReattachImpales).
			GoreService.Wound(part, point, 1.1)
			GoreService.Burst(point, Vector3.yAxis, 30, 12)
			GoreService.Sound("stab", point, 1)
			GoreService.Spurt(part, part.CFrame:PointToObjectSpace(point), Vector3.new(0, 1, 0), 6, 0.6)
		else
			-- dummies / corpses (simulated by the server) hang on the spike
			GoreService.Impale(part, spike, point)
			state.impaled[part] = os.clock()
			model:SetAttribute("Impaled", true)
		end
		state.spikes[part] = { spike = spike, point = point, t = os.clock() }
	else
		GoreService.Sound("stab", point, 1)
	end
	-- no instant death: the damage and the bleeding decide
	DamageService.ApplyDamage(model, region, dmg, point, {
		cause = "Impaled",
		allowSever = false,
		bleed = region == "Torso" and Config.PierceBleedTorso or Config.PierceBleedLimb,
		bleedTime = 25,
		attacker = DamageService.AttackerOf(spike), -- a thrown spear counts for the thrower
	})
end

export type BulletOpts = {
	mult: number?, -- damage multiplier (gun, shotgun range)
	count: number?, -- pellets that hit this body part
	push: number?, -- knockback multiplier
	severAt: number?, -- the hit can blow the body part off (shotgun up close)
	allowSever: boolean?, -- enough hits shoot the limb off (revolver, sniper)
	kind: string?, -- (v2.8) the gun's kind (a COLOSSUS shrugs off the normal ones)
}

function DamageService.ApplyBullet(model: Model, region: string, point: Vector3, dir: Vector3, shooter: Player?, pellet: boolean?, optsIn: BulletOpts?)
	local o: BulletOpts = optsIn or {}
	if DamageService.Protected(model, shooter) then
		return
	end
	if DamageService.ShieldBullet and DamageService.ShieldBullet(model, region, point, dir, shooter, o.kind) then
		return -- (v1.9) the bullet passes through a Wonder player
	end
	local count = o.count or 1
	local base = ((pellet and Config.PelletDamage[region] or Config.BulletDamage[region]) or 50) * (o.mult or 1) * count
	local bleed = region == "Head" and Config.BulletBleed.Head or region == "Torso" and Config.BulletBleed.Torso or Config.BulletBleed.Limb
	if pellet then
		bleed *= 0.35 * math.sqrt(count)
	end
	local cause = "Shot"
	if shooter and Players:GetPlayerFromCharacter(model) == shooter then
		cause = "Shot themselves"
	elseif shooter then
		cause = "Shot by " .. shooter.DisplayName
	end
	-- (v2.8.1) COLOSSUS: bullets ping off the armour (no damage, a head shot does not kill either)
	if model:GetAttribute("Colossus") then
		GoreService.Sound("metal", point, 0.8)
		GoreService.FX({ t = "burst", p = point - dir * 0.15, d = -dir, n = 3, s = 10, black = true })
		return
	end
	local chrome = (region == "LeftArm" and model:GetAttribute("Titan_L") ~= nil) or (region == "RightArm" and model:GetAttribute("Titan_R") ~= nil)
	if chrome then
		GoreService.Sound("metal", point, 0.9)
	else
		GoreService.Sound("bulletFlesh", point, 1)
		-- (v2.0) a little back-spatter out of the entry wound (towards the shooter); a bullet that goes through
		-- sprays forward out of the exit wound (GunService)
		GoreService.Burst(point - dir * 0.15, -dir, pellet and 4 or 7, 9)
	end
	local wasSevered = model:GetAttribute("Severed_" .. region) == true
	local wasBroken = model:GetAttribute("Broken_" .. region) == true
	-- (v2.8.2) an AEGIS shield with charge left takes a head shot too (it drains the shield; the head's HP decide the rest)
	local sh = model:GetAttribute("CyShield")
	local shielded = typeof(sh) == "number" and sh >= 1
	DamageService.ApplyDamage(model, region, base, point, {
		cause = region == "Head" and (cause .. " (head)") or cause,
		allowSever = o.severAt ~= nil or o.allowSever == true,
		severAt = o.severAt,
		bullet = true,
		bleed = bleed,
		bleedTime = Config.BulletBleedTime,
		attacker = shooter,
	})
	if region == "Head" and not pellet and not shielded then
		DamageService.Kill(model, cause .. " (head)")
	end
	-- point blank shotgun: the body part bursts
	if o.severAt and base >= o.severAt then
		if (not wasSevered and model:GetAttribute("Severed_" .. region)) or (region == "Torso" and not wasBroken) then
			GoreService.Gibs(point, region == "Torso" and 10 or 6, 38)
			GoreService.Burst(point, dir, 45, 30)
			GoreService.Sound("gore", point, 1)
		end
		if region == "Torso" and not model:GetAttribute("Zombie") then
			DamageService.Kill(model, cause .. " (point blank)")
		end
	end
	-- the hit body part itself is knocked (a head shot snaps the head back, a leg shot kicks the leg)
	local push = (pellet and Config.PelletPush or Config.BulletPush) * DamageService.PartMass(model, region) * (o.push or 1)
	local down = ((not pellet and region == "Torso") or (pellet and count >= 3)) and Config.BulletTorsoKnockdown or nil
	DamageService.Knock(model, region, dir * push, down, point)
end

-- a living player tore a stuck body part off a spike
function DamageService.TearFree(model: Model, region: string)
	local state = bodies[model]
	local partName = RigInfo.RegionPart[region]
	local part = partName and model:FindFirstChild(partName)
	if not state or state.dead or not part then
		return
	end
	state.spikes[part] = nil
	GoreService.Burst(part.Position, Vector3.yAxis, 25, 12)
	GoreService.Sound("gore", part, 0.6)
	DamageService.ApplyDamage(model, region, Config.ImpaleTearDamage, part.Position, { cause = "Tore free", allowSever = false })
end

-- Tear an impaled body off its spike (player struggled or time ran out).
function DamageService.Unimpale(model: Model, extraDamage: boolean)
	local state = bodies[model]
	if not state then
		return
	end
	for part in state.impaled do
		if part.Parent then
			GoreService.Unimpale(part)
			if extraDamage then
				local region = RigInfo.PartRegion[part.Name]
				if region then
					DamageService.ApplyDamage(model, region, 12, part.Position, { cause = "Tore free", allowSever = false })
				end
			end
		end
	end
	table.clear(state.impaled)
	table.clear(state.spikes)
	model:SetAttribute("Impaled", false)
end

-- A player's body was held on the spike by their own client. When it becomes a corpse the server
-- takes over the physics, so it re-creates the joints (positions are exact now: the body is still).
function DamageService.ReattachImpales(model: Model)
	local state = bodies[model]
	if not state then
		return
	end
	local now = os.clock()
	local any = false
	for part, rec in state.spikes do
		-- only a body that died ON the spike (recently, and still lying on it) stays stuck to it
		local recent = now - (rec.t or 0) < Config.ImpaleTime + 4
		local onIt = part.Parent ~= nil and (part.Position - rec.point).Magnitude <= part.Size.Magnitude * 0.5 + 0.6
		if recent and onIt and rec.spike.Parent and not part:FindFirstChild("Impale") then
			GoreService.Impale(part, rec.spike, rec.point, true)
			state.impaled[part] = now
			any = true
		end
	end
	if any then
		model:SetAttribute("Impaled", true)
	end
end

-- Bleeding, healing, impale timeouts and health sync.
local accum = 0
RunService.Heartbeat:Connect(function(dt)
	accum += dt
	if accum < 0.2 then
		return
	end
	local step = accum
	accum = 0
	local now = os.clock()
	for model, state in bodies do
		if not model.Parent then
			continue
		end
		local rate = 0
		if model:GetAttribute("Zombie") then
			table.clear(state.bleeds) -- (v2.0) the dead do not bleed out
		end
		for i = #state.bleeds, 1, -1 do
			local b = state.bleeds[i]
			if now > b.untilTime then
				table.remove(state.bleeds, i)
			else
				rate += b.rate
			end
		end
		local blood = model:GetAttribute("Blood") or 100
		-- (v2.0) a hand pressed on the wound slows the bleeding
		local pressing = model:GetAttribute("PressingWound")
		if typeof(pressing) == "number" and workspace:GetServerTimeNow() - pressing < 1.2 then
			rate *= Config.WoundPressBleed
		end
		if rate > 0 and blood > 0 then
			blood = math.max(0, blood - rate * step)
			model:SetAttribute("Blood", blood)
			if blood <= 0 then
				DamageService.Kill(model, "Bled out")
			end
		end
		model:SetAttribute("Bleeding", rate > 0)

		if not state.dead and now - state.lastHit > Config.HealDelay then
			for _, region in RigInfo.Regions do
				if not model:GetAttribute("Broken_" .. region) then
					local hp = model:GetAttribute("HP_" .. region) or Config.LimbMaxHP
					if hp < Config.LimbMaxHP then
						model:SetAttribute("HP_" .. region, math.min(Config.LimbMaxHP, hp + Config.HealRate * step))
					end
				end
			end
		end

		-- the living tear free from spikes after a while; corpses stay
		if not state.dead and next(state.impaled) then
			local oldest = math.huge
			for _, t in state.impaled do
				oldest = math.min(oldest, t)
			end
			if now - oldest > Config.ImpaleTime then
				DamageService.Unimpale(model, true)
			end
		end

		local hum = state.humanoid
		if hum and hum.Parent and not state.dead then
			local h = math.min(blood, model:GetAttribute("HP_Head") or 100, model:GetAttribute("HP_Torso") or 100)
			hum.Health = math.clamp(h, 1, hum.MaxHealth)
		end

		local torso = model:FindFirstChild("Torso") :: BasePart?
		if torso and torso.Position.Y < -150 and not state.dead and not Config.InPit(torso.Position) then
			DamageService.Kill(model, "Fell into the void")
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	for model, state in bodies do
		if state.player == player then
			bodies[model] = nil
		end
	end
end)

return DamageService
