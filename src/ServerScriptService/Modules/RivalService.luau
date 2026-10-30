--!nonstrict
-- RivalService (v2.8): VESPER CROWE, THE PALE HEIR - the swordswoman down in the Pit (quest 3 of the STILLWATER quest;
-- SwordQuestService spawns her). (v2.8.1: she) A pale woman in a long fitted crimson coat, long ash-black hair in a high
-- tail, a cracked white half-mask, one red eye. She fights with STILLWATER and never lets go of it.
--   * his health is a boss bar (model attributes BossHP / BossMax): every hit counts in full there; his body only shows it
--     (he cannot be one-shot through the head, he does not bleed out). Below Config.RivalSeverBelow his limbs come off.
--     Knock-downs barely move him; explosions throw him a little.
--   * phase 1: the sword and the BLINK STEP - he is suddenly behind you and cuts.
--   * phase 2 (under 60 %): the SHADE ARMS - two huge ghostly arms over his shoulders. They SLAM the ground where you stand
--     (a ring warns you first), GRAB you and throw you across the Pit, and catch bullets (Config.RivalBulletCatch).
--   * phase 3 (under 30 %): HIS STILL CUT - he stops, sheathes, a ring of stillness grows round him; when the blade
--     clicks shut, everything inside the ring is cut (Config.RivalStillCut). Get out of the ring.
-- The arms are drawn by every client (SwordClient) from attributes on his model: ArmsOut, ArmL / ArmR (where the hand
-- goes, nil = beside him), ArmLFist / ArmRFist.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))

local RivalService = {}

local deps: any = {}
local rival: Model? = nil
local lastHitter: Player? = nil
local rng = Random.new()

-- set by SwordQuestService
RivalService.Targets = nil :: (() -> { Model })? -- the bodies he hunts (players down in the Pit)
RivalService.OnDefeated = nil :: ((Model, Player?) -> ())?
RivalService.Say = nil :: ((string, { string }?) -> ())? -- a line of his (key in Config.RivalLines) to everybody down there

local COAT = Color3.fromRGB(86, 18, 28)
local COAT_DARK = Color3.fromRGB(46, 10, 16)
local TRIM = Color3.fromRGB(176, 180, 190)
local SKIN = Color3.fromRGB(232, 222, 212)
local HAIR = Color3.fromRGB(30, 28, 32)
local MASK = Color3.fromRGB(240, 238, 232)

function RivalService.Active(): Model?
	if rival and rival.Parent and not rival:GetAttribute("Dead") then
		return rival
	end
	return nil
end

local function say(key: string)
	if RivalService.Say then
		RivalService.Say(key, Config.RivalLines[key])
	end
end

------------------------------------------------------------------------
-- his look
------------------------------------------------------------------------

local function deco(model: Model, attachTo: BasePart, name: string, size: Vector3, off: CFrame, color: Color3, material: Enum.Material, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.CFrame = attachTo.CFrame * off
	local w = Instance.new("WeldConstraint")
	w.Part0 = attachTo
	w.Part1 = p
	w.Parent = p
	p.Parent = model
	return p
end

local function dress(model: Model)
	local head = model:FindFirstChild("Head") :: BasePart
	local torso = model:FindFirstChild("Torso") :: BasePart
	if not head or not torso then
		return
	end
	local mask = model:FindFirstChild("Mask")
	if mask then
		mask:Destroy()
	end
	local face = head:FindFirstChild("face")
	if face and face:IsA("Decal") then
		face.Transparency = 1
	end
	local SP = Enum.Material.SmoothPlastic
	-- (v2.8.1) her hair: a fringe swept to one side, long hair down the back, two locks framing the face, a high tail
	deco(model, head, "Hair", Vector3.new(1.32, 0.44, 1.3), CFrame.new(0, 0.5, 0.05), HAIR, Enum.Material.Fabric)
	deco(model, head, "Fringe", Vector3.new(0.8, 0.26, 0.2), CFrame.new(-0.24, 0.42, -0.58) * CFrame.Angles(0, 0, math.rad(-10)), HAIR, Enum.Material.Fabric)
	deco(model, head, "HairBack", Vector3.new(1.3, 1.9, 0.34), CFrame.new(0, -0.45, 0.52), HAIR, Enum.Material.Fabric)
	deco(model, head, "HairEnd", Vector3.new(1.1, 0.5, 0.3), CFrame.new(0, -1.55, 0.56) * CFrame.Angles(math.rad(8), 0, 0), HAIR, Enum.Material.Fabric)
	for _, sx in { -1, 1 } do
		deco(model, head, "Lock", Vector3.new(0.18, 1.2, 0.3), CFrame.new(sx * 0.6, -0.12, -0.32), HAIR, Enum.Material.Fabric)
	end
	deco(model, head, "HairTail", Vector3.new(0.34, 1.7, 0.34), CFrame.new(0, 0.55, 0.78) * CFrame.Angles(math.rad(35), 0, 0), HAIR, Enum.Material.Fabric)
	deco(model, head, "HairTie", Vector3.new(0.4, 0.16, 0.4), CFrame.new(0, 0.86, 0.62) * CFrame.Angles(math.rad(35), 0, 0), Color3.fromRGB(150, 20, 30), Enum.Material.Fabric)
	-- the cracked half-mask over the right side of the face; the other eye red, with a dark lash line; dark red lips
	deco(model, head, "HalfMask", Vector3.new(0.6, 1.02, 0.08), CFrame.new(0.3, 0.02, -0.63), MASK, SP, { Reflectance = 0.1 })
	deco(model, head, "MaskCrack", Vector3.new(0.04, 0.6, 0.09), CFrame.new(0.22, 0.1, -0.635) * CFrame.Angles(0, 0, math.rad(20)), Color3.fromRGB(40, 40, 46), SP)
	deco(model, head, "MaskSlit", Vector3.new(0.26, 0.05, 0.09), CFrame.new(0.3, 0.16, -0.64), Color3.fromRGB(20, 20, 26), SP)
	deco(model, head, "Eye", Vector3.new(0.16, 0.08, 0.05), CFrame.new(-0.25, 0.16, -0.61), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
	deco(model, head, "Lash", Vector3.new(0.24, 0.035, 0.05), CFrame.new(-0.26, 0.215, -0.615) * CFrame.Angles(0, 0, math.rad(-8)), HAIR, SP)
	deco(model, head, "Lips", Vector3.new(0.22, 0.05, 0.04), CFrame.new(-0.08, -0.24, -0.61), Color3.fromRGB(120, 20, 30), SP)
	-- the long coat: a high collar, the skirt in front (split) and behind, silver trim
	deco(model, torso, "Collar", Vector3.new(2.15, 0.55, 1.2), CFrame.new(0, 1.18, 0.05), COAT_DARK, Enum.Material.Fabric)
	deco(model, torso, "CoatBack", Vector3.new(2.1, 2.4, 0.14), CFrame.new(0, -1.95, 0.56) * CFrame.Angles(math.rad(-6), 0, 0), COAT, Enum.Material.Fabric)
	for _, sx in { -1, 1 } do
		deco(model, torso, "CoatFront", Vector3.new(0.9, 2.2, 0.12), CFrame.new(sx * 0.58, -1.85, -0.56) * CFrame.Angles(math.rad(5), 0, math.rad(sx * 3)), COAT, Enum.Material.Fabric)
		deco(model, torso, "CoatSide", Vector3.new(0.12, 2.3, 1.0), CFrame.new(sx * 1.06, -1.9, 0.02), COAT, Enum.Material.Fabric)
		deco(model, torso, "Trim", Vector3.new(0.06, 2.2, 0.13), CFrame.new(sx * 0.14, -1.85, -0.57), TRIM, Enum.Material.Metal)
		deco(model, torso, "Lapel", Vector3.new(0.5, 1.4, 0.1), CFrame.new(sx * 0.42, 0.35, -0.53) * CFrame.Angles(0, 0, math.rad(sx * -14)), COAT_DARK, Enum.Material.Fabric)
	end
	-- a fitted waist: a high corset belt with straps
	deco(model, torso, "Belt", Vector3.new(2.06, 0.5, 1.06), CFrame.new(0, -0.45, 0), Color3.fromRGB(22, 20, 24), Enum.Material.Leather)
	for _, y in { -0.33, -0.57 } do
		deco(model, torso, "Strap", Vector3.new(2.08, 0.06, 1.08), CFrame.new(0, y, 0), TRIM, Enum.Material.Metal)
	end
	deco(model, torso, "Buckle", Vector3.new(0.3, 0.2, 0.06), CFrame.new(0, -0.45, -0.54), TRIM, Enum.Material.Metal, { Reflectance = 0.3 })
	-- her empty sheath on the left hip
	deco(model, torso, "HeirSheath", Vector3.new(0.26, 0.32, 3.8), CFrame.new(-1.15, -1.3, 0.9) * CFrame.Angles(math.rad(-160), 0, math.rad(-6)), Color3.fromRGB(20, 20, 24), SP, { Reflectance = 0.15 })
end

RivalService._dress = dress -- (the preview / tests)

------------------------------------------------------------------------
-- damage: the boss bar
------------------------------------------------------------------------

local function isRival(model: Model): boolean
	return rival ~= nil and model == rival
end

local function hpShare(): number
	local r = rival
	if not r then
		return 0
	end
	return (r:GetAttribute("BossHP") or 0) / math.max(1, r:GetAttribute("BossMax") or 1)
end

local function modifier(model: Model, region: string, dmg: number, opts: any): (number, any?)
	if not isRival(model) or model:GetAttribute("Dead") then
		return dmg, nil
	end
	local r = model
	if opts.attacker then
		lastHitter = opts.attacker
	end
	-- the shade arms catch bullets
	if opts.bullet and r:GetAttribute("ArmsOut") and rng:NextNumber() < Config.RivalBulletCatch then
		local t = r:FindFirstChild("Torso")
		if t and t:IsA("BasePart") then
			deps.GoreService.FX({ t = "shadecatch", p = t.Position + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(0, 3), rng:NextNumber(-2, 2)) })
		end
		return 0, nil
	end
	local hp = (r:GetAttribute("BossHP") or 0) - dmg
	r:SetAttribute("BossHP", math.max(0, hp))
	if hp <= 0 then
		task.defer(function()
			if r.Parent and not r:GetAttribute("Dead") then
				r:SetAttribute("ForceKill", true)
				deps.DamageService.Kill(r, "Defeated" .. (lastHitter and (" by " .. lastHitter.DisplayName) or ""))
			end
		end)
		return dmg * 0.3, nil
	end
	-- his body only shows the hit
	local o2 = table.clone(opts)
	o2.bleed = nil
	if hpShare() > Config.RivalSeverBelow then
		o2.allowSever = false
	end
	local cur = r:GetAttribute("HP_" .. region) or Config.LimbMaxHP
	local out = dmg * 0.3
	if region == "Head" or region == "Torso" then
		out = math.min(out, math.max(0, cur - 20))
		o2.allowSever = false
	end
	return out, o2
end

local function knockFilter(model: Model, kind: string, ragdollTime: number?, push: Vector3?): (number?, Vector3?)
	if not isRival(model) or model:GetAttribute("Dead") then
		return ragdollTime, push
	end
	if kind == "blast" then
		return ragdollTime and math.min(ragdollTime, 0.8) or nil, push and push * 0.35 or nil
	end
	return nil, push and push * 0.25 or nil
end

------------------------------------------------------------------------
-- his moves
------------------------------------------------------------------------

local function torsoOf(m: Model?): BasePart?
	local t = m and m:FindFirstChild("Torso")
	return (t and t:IsA("BasePart")) and t or nil
end

local function ground(pos: Vector3, ignore: { Instance }): Vector3
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), rp)
	return hit and hit.Position or (pos - Vector3.new(0, 3, 0))
end

local function aliveTargets(): { Model }
	local out = {}
	for _, m in (RivalService.Targets and RivalService.Targets() or {}) do
		if m.Parent and not m:GetAttribute("Dead") and torsoOf(m) then
			table.insert(out, m)
		end
	end
	return out
end

local function nearest(): Model?
	local r = rival
	local rt = torsoOf(r)
	if not rt then
		return nil
	end
	local best, bestD = nil, math.huge
	for _, m in aliveTargets() do
		local t = torsoOf(m) :: BasePart
		local d = (t.Position - rt.Position).Magnitude
		if d < bestD then
			best, bestD = m, d
		end
	end
	return best
end

local function hurt(body: Model, region: string, dmg: number, point: Vector3, cause: string, sever: boolean)
	deps.DamageService.ApplyDamage(body, region, dmg, point, {
		cause = cause,
		allowSever = sever,
		severAt = sever and (Config.KatanaSeverDamage + 4) or nil,
		bleed = sever and 0.8 or nil,
		bleedTime = 12,
		melee = true,
	})
end

local LIMBS = { "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Torso", "Torso" }

-- BLINK STEP: gone, and behind you, and the blade is already moving
local function blink(target: Model)
	local r = rival :: Model
	local rt, tt = torsoOf(r), torsoOf(target)
	if not rt or not tt then
		return
	end
	local look = tt.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, 1)
	local spot = ground(tt.Position - flat * 4.5, { r, target })
	local from = rt.Position
	local to = spot + Vector3.new(0, 3, 0)
	deps.GoreService.FX({ t = "blink", a = from, b = to })
	deps.GoreService.Sound("kickSwoosh", from, 1)
	r:PivotTo(CFrame.lookAt(to, Vector3.new(tt.Position.X, to.Y, tt.Position.Z)))
	pcall(function()
		for _, d in r:GetDescendants() do
			if d:IsA("BasePart") and not d.Anchored then
				d.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end)
	task.wait(0.25)
	if not r.Parent or r:GetAttribute("Dead") then
		return
	end
	tt = torsoOf(target)
	if tt and not target:GetAttribute("Dead") and (tt.Position - to).Magnitude < 8 then
		local region = LIMBS[rng:NextInteger(1, #LIMBS)]
		local part = target:FindFirstChild(RigInfo.RegionPart[region] or "Torso")
		local point = (part and part:IsA("BasePart")) and part.Position or tt.Position
		deps.GoreService.FX({ t = "crescent", p = point, d = (tt.Position - to).Unit })
		deps.GoreService.Sound("slash", point, 1.2)
		hurt(target, region, Config.RivalSlash, point, "Cut down by " .. Config.RivalName, true)
		deps.DamageService.Knock(target, region, (tt.Position - to).Unit * 40, 1.0, point)
		if rng:NextNumber() < 0.5 then
			say("taunt")
		end
	end
end

local function setArm(side: string, pos: Vector3?, fist: boolean?)
	local r = rival
	if not r then
		return
	end
	r:SetAttribute("Arm" .. side, pos)
	r:SetAttribute("Arm" .. side .. "Fist", fist or nil)
end

-- SLAM: the hand rises over where you stand, then comes down
local function slam(target: Model)
	local r = rival :: Model
	local tt = torsoOf(target)
	if not tt then
		return
	end
	local side = rng:NextNumber() < 0.5 and "L" or "R"
	local g = ground(tt.Position, { r, target })
	deps.GoreService.FX({ t = "shadeslam", ph = "tele", p = g, at = workspace:GetServerTimeNow() + 0.9 })
	setArm(side, g + Vector3.new(0, 16, 0), true)
	task.wait(0.9)
	if not r.Parent or r:GetAttribute("Dead") then
		return
	end
	setArm(side, g + Vector3.new(0, 1.6, 0), true)
	task.wait(0.12)
	deps.GoreService.FX({ t = "shadeslam", ph = "hit", p = g })
	deps.GoreService.Sound("heavyHit", g, 1.4)
	deps.GoreService.Sound("groundCrack", g, 1.2)
	for body in deps.DamageService.Bodies() do
		local bt = torsoOf(body)
		if body ~= r and bt and not body:GetAttribute("Dead") and (bt.Position - g).Magnitude < 10 then
			local away = Vector3.new(bt.Position.X - g.X, 0, bt.Position.Z - g.Z)
			local dir = away.Magnitude > 0.1 and away.Unit or Vector3.xAxis
			hurt(body, "Torso", Config.RivalSlam, bt.Position, "Crushed by a shade arm", false)
			deps.DamageService.Blast(body, dir * 38 + Vector3.new(0, 48, 0), 2.2)
		end
	end
	task.wait(0.5)
	setArm(side, nil, false)
end

-- GRAB: the open hand shoots at you; caught, you are lifted, crushed and thrown across the Pit
local function grab(target: Model)
	local r = rival :: Model
	local tt, rt = torsoOf(target), torsoOf(r)
	if not tt or not rt then
		return
	end
	local side = rng:NextNumber() < 0.5 and "L" or "R"
	local at = tt.Position + Vector3.new(0, 1.5, 0)
	setArm(side, at, false)
	deps.GoreService.Sound("kickSwoosh", rt, 1)
	task.wait(0.45)
	if not r.Parent or r:GetAttribute("Dead") then
		return
	end
	tt = torsoOf(target)
	if tt and not target:GetAttribute("Dead") and (tt.Position - at).Magnitude < 7 then
		setArm(side, tt.Position, true)
		deps.GoreService.Sound("crunch", tt, 1)
		hurt(target, "Torso", 16, tt.Position, "Crushed in a shade hand", false)
		deps.DamageService.Blast(target, Vector3.new(0, 30, 0), 3)
		task.wait(0.25)
		setArm(side, rt.Position + Vector3.new(0, 14, 0), true)
		task.wait(0.4)
		tt = torsoOf(target)
		if tt and r.Parent then
			local away = Vector3.new(tt.Position.X - rt.Position.X, 0, tt.Position.Z - rt.Position.Z)
			local dir = away.Magnitude > 0.1 and away.Unit or -rt.CFrame.LookVector
			setArm(side, tt.Position + dir * 10, false)
			deps.GoreService.FX({ t = "shadethrow", p = tt.Position, d = dir })
			deps.DamageService.Blast(target, dir * 95 + Vector3.new(0, 42, 0), 3)
		end
	else
		deps.GoreService.FX({ t = "shadecatch", p = at })
	end
	task.wait(0.5)
	setArm(side, nil, false)
end

-- HIS STILL CUT: he stops and sheathes; the ring of stillness grows; the click - everything in it is cut
local function stillCut()
	local r = rival :: Model
	local rt = torsoOf(r)
	if not rt then
		return
	end
	say("stillcut")
	local weapon = deps.NPCService.Weapon(r)
	local hidden = {}
	if weapon then
		for _, d in weapon:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				hidden[d] = d.Transparency
				d.Transparency = 1
			end
		end
	end
	rt.Anchored = true
	local center = rt.Position
	local R = Config.RivalStillCutRadius
	local dur = 1.8
	deps.GoreService.FX({ t = "stillcut", ph = "begin", by = 0, rival = true, p = center, r = R, d = dur, seed = rng:NextInteger(1, 1e6) })
	deps.GoreService.Sound("click", rt, 1)
	task.wait(dur)
	if r.Parent and rt.Parent then
		rt.Anchored = false
	end
	for d, tr in hidden do
		if d.Parent then
			d.Transparency = tr
		end
	end
	if not r.Parent or r:GetAttribute("Dead") then
		return
	end
	deps.GoreService.FX({ t = "stillcut", ph = "end", by = 0, rival = true, p = center, r = R })
	deps.GoreService.Sound("clink", center, 1.2)
	deps.GoreService.Sound("slash", center, 1.4)
	for body in deps.DamageService.Bodies() do
		local bt = torsoOf(body)
		if body ~= r and bt and not body:GetAttribute("Dead") and (bt.Position - center).Magnitude <= R then
			for _ = 1, 2 do
				local region = LIMBS[rng:NextInteger(1, #LIMBS)]
				local part = body:FindFirstChild(RigInfo.RegionPart[region] or "Torso")
				hurt(body, region, Config.RivalStillCut * 0.5, (part and part:IsA("BasePart")) and part.Position or bt.Position, "Cut in the stillness by " .. Config.RivalName, true)
			end
			deps.DamageService.Knock(body, "Torso", (bt.Position - center).Unit * 30, 1.5, bt.Position)
		end
	end
end

------------------------------------------------------------------------
-- the brain on top of the NPC's own (it walks and swings by itself)
------------------------------------------------------------------------

local busy = false
local nextBlink = 0
local nextArm = 0
local nextStill = 0
local phase = 1

local function act(fn: (any) -> (), target: Model?)
	busy = true
	task.spawn(function()
		local ok, err = pcall(fn, target)
		if not ok then
			warn("[Ragdoll] rival move failed:", err)
		end
		busy = false
	end)
end

local function step()
	local r = rival
	if not r or not r.Parent or r:GetAttribute("Dead") then
		return
	end
	-- he never bleeds out and his head / chest never give before his health does
	r:SetAttribute("Blood", 100)
	for _, region in { "Head", "Torso" } do
		local hp = r:GetAttribute("HP_" .. region) or 100
		if hp < 40 then
			r:SetAttribute("HP_" .. region, 40)
		end
	end
	local share = hpShare()
	local want = share > 0.6 and 1 or (share > 0.3 and 2 or 3)
	if want > phase then
		phase = want
		r:SetAttribute("Phase", phase)
		if phase == 2 then
			r:SetAttribute("ArmsOut", true)
			say("phase2")
		elseif phase == 3 then
			say("phase3")
			nextStill = os.clock() + 2
		end
	end
	if busy then
		return
	end
	local target = nearest()
	local rt, tt = torsoOf(r), torsoOf(target)
	if not target or not rt or not tt then
		return
	end
	local now = os.clock()
	local d = (tt.Position - rt.Position).Magnitude
	if phase >= 3 and now > nextStill and d < Config.RivalStillCutRadius + 6 then
		nextStill = now + rng:NextNumber(11, 15)
		act(stillCut)
	elseif phase >= 2 and now > nextArm and d < 45 then
		nextArm = now + rng:NextNumber(4.5, 7)
		act(rng:NextNumber() < 0.55 and slam or grab, target)
	elseif now > nextBlink and d > 7 and d < 60 then
		nextBlink = now + rng:NextNumber(6, 9) + (phase >= 2 and 2 or 0)
		act(blink, target)
	end
end

------------------------------------------------------------------------

function RivalService.Spawn(cf: CFrame): Model?
	if RivalService.Active() then
		return rival
	end
	RivalService.Despawn()
	local m = deps.NPCService.Spawn("melee", cf, nil, {
		weapon = "stillwater",
		name = Config.RivalName,
		hellborn = true,
		colors = { Head = SKIN, Torso = COAT, Arms = COAT, Legs = Color3.fromRGB(26, 24, 30) },
	})
	if not m then
		return nil
	end
	dress(m)
	m:SetAttribute("Rival", true)
	m:SetAttribute("Boss", true)
	m:SetAttribute("BossMax", Config.RivalHP)
	m:SetAttribute("BossHP", Config.RivalHP)
	m:SetAttribute("BossName", Config.RivalName)
	m:SetAttribute("BossTitle", Config.RivalTitle)
	m:SetAttribute("DisplayName", Config.RivalName)
	m:SetAttribute("Hellborn", true)
	m:SetAttribute("Phase", 1)
	CollectionService:AddTag(m, "Rival")
	local w = deps.NPCService.Weapon(m)
	if w then
		w:SetAttribute("RivalBlade", true)
		CollectionService:AddTag(w, "RivalBlade")
	end
	rival = m
	lastHitter = nil
	phase = 1
	busy = false
	nextBlink = os.clock() + 4
	nextArm = 0
	nextStill = math.huge
	m:GetAttributeChangedSignal("Dead"):Connect(function()
		if not m:GetAttribute("Dead") or rival ~= m then
			return
		end
		m:SetAttribute("ArmsOut", nil)
		m:SetAttribute("ArmL", nil)
		m:SetAttribute("ArmR", nil)
		say("death")
		-- her own sword does not stay: whoever beat her gets their own (SwordQuestService)
		local blade = deps.NPCService.Weapon(m)
		task.delay(0.2, function()
			for _, b in CollectionService:GetTagged("RivalBlade") do
				b:Destroy()
			end
			if blade and blade.Parent then
				blade:Destroy()
			end
		end)
		if RivalService.OnDefeated then
			task.spawn(RivalService.OnDefeated, m, lastHitter)
		end
		task.delay(12, function()
			if m.Parent then
				m:Destroy()
			end
		end)
	end)
	return m
end

function RivalService.Despawn()
	if rival and rival.Parent then
		rival:Destroy()
	end
	for _, b in CollectionService:GetTagged("RivalBlade") do
		b:Destroy()
	end
	rival = nil
end

function RivalService.Init(d: any)
	deps = d
	table.insert(deps.DamageService.Modifiers, modifier)
	local prevKnock = deps.DamageService.KnockFilter
	deps.DamageService.KnockFilter = function(model, kind, rt, push)
		if prevKnock then
			rt, push = prevKnock(model, kind, rt, push)
		end
		return knockFilter(model, kind, rt, push)
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		local ok, err = pcall(step)
		if not ok then
			warn("[Ragdoll] rival:", err)
		end
	end)
	local _ = Players
end

return RivalService
