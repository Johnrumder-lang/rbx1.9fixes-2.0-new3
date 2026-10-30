--!nonstrict
-- CyberService (v2.8): the implants a player carries (Shared/Cyberware), and everything they do.
--   * the list lives in the profile (Persist: cy / lk): it stays through death and rejoining until somebody operates it out
--     (on a private server nothing is saved - SaveGate - but the implants stay for the session).
--   * a body gets them on every spawn: models (CyberModels), size (BULK FRAME / COLOSSUS: Model:ScaleTo), a hidden real arm
--     under a TITAN arm, the Sandevistan, numbers for the client (CySpeed, CyJump, CyBalance), the shield.
--   * passive effects: DamageService.Modifiers (AEGIS shield, TITAN arms, BULK, BLASTWEAVE, HUNTER bonus, COLOSSUS),
--     AfterDamage (STATIC DERMIS shocks back, cyberpsychosis triggers), KnockFilter (KEEL, BLASTWEAVE, COLOSSUS),
--     KnockService.PunchMod (TITAN punches, SICKLE BLADES), the fall damage of STRIDER LEGS, SENTRY REFLEX warnings.
--   * abilities (the cyber bar, keys 1-9; CyberClient asks): HUNT, CANNON, ARM GUN, BLADES, PULL, CLOAK, FREEZE.
--   * CYBERPSYCHOSIS: load over tolerance -> CyPsycho grows (hallucinations on the client); touched / shooting somebody ->
--     a CRASH OUT (the client loses control for Config.CrashOutTime s). Admins and COLOSSUS: never.
-- Install / Remove are called by the ripperdoc (RipperdocService) and by player surgeons (GearService fitting).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Cyberware = require(Shared:WaitForChild("Cyberware"))
local TimeScale = require(Shared:WaitForChild("TimeScale"))
local Modules = script.Parent
local Persist = require(Modules:WaitForChild("Persist"))
local CyberModels = require(Modules:WaitForChild("CyberModels"))

local CyberService = {}

local deps: any = {}
local Remote: RemoteEvent
local rng = Random.new()

type St = {
	list: { [string]: number },
	look: { [string]: string },
	psycho: number,
	lastCrash: number,
	cd: { [string]: number },
	shield: number,
	lastHit: number,
	hunt: Player?,
	lastShot: number,
	gifted: { [string]: boolean }, -- admin-only implants an admin gave this player
	lastHurt: number?, -- (v2.8) IRONHEART PUMP: the last hit
	armAmmo: { [string]: number }?, -- (v2.8.1) SHIFTGUN: rounds left per arm
	armReload: { [string]: number }?, -- (v2.8.1) SHIFTGUN: reloading until (os.clock)
	armLast: { [string]: number }?, -- (v2.8.1) SHIFTGUN: the last shot per arm
	bastionUntil: number?, -- (v2.8.2) BASTION SHELL: the plates stay closed until (os.clock)
	bastionPlates: { any }?, -- (v2.8.2) the plates that are out
}
local states: { [Player]: St } = {}

local ARM_PART = { L = "Left Arm", R = "Right Arm" }

------------------------------------------------------------------------
-- the list
------------------------------------------------------------------------

local function stOf(p: Player): St
	local st = states[p]
	if not st then
		st = { list = {}, look = {}, psycho = 0, lastCrash = 0, cd = {}, shield = 0, lastHit = 0, hunt = nil, lastShot = 0, gifted = {} }
		states[p] = st
	end
	return st
end

local function save(p: Player)
	local st = states[p]
	local prof = Persist.Get(p)
	if st and prof then
		prof.cyber = table.clone(st.list)
		prof.look = table.clone(st.look)
		Persist.Dirty(p)
	end
end

-- what a body effectively has: COLOSSUS = every best implant (no TITAN models: its own armour)
local function effective(st: St): { [string]: number }
	if not st.list.colossus then
		return st.list
	end
	local out = { colossus = 1 }
	for _, d in Cyberware.List do
		if not d.admin and d.id ~= "bulk" and d.id ~= "shiftgun" then
			if d.slot == "arm" then
				out[d.id .. "_L"] = d.tiers
				out[d.id .. "_R"] = d.tiers
			elseif d.slot == "fore" then
				if d.id == "howler" then
					out.howler_L = d.tiers
				elseif d.id == "sickles" then
					out.sickles_R = d.tiers
				end
			else
				out[d.id] = d.tiers
			end
		end
	end
	if st.list.zerohour then
		out.zerohour = 1
	end
	return out
end
CyberService.Effective = function(p: Player): { [string]: number }
	return effective(stOf(p))
end

local function tierOf(p: Player?, id: string): number
	if not p then
		return 0
	end
	local st = states[p]
	return st and Cyberware.Tier(effective(st), id) or 0
end
CyberService.Tier = tierOf

local function playerOf(model: Model?): Player?
	return model and Players:GetPlayerFromCharacter(model) or nil
end

local function tolerance(p: Player): number
	local b = p:GetAttribute("CyTolBonus")
	return Config.CyberTolerance + (typeof(b) == "number" and b or 0)
end
CyberService.Tolerance = tolerance

local function immune(p: Player): boolean
	local st = states[p]
	if workspace:GetAttribute("PsychosisOff") == true then
		return true -- (v2.8.2) an admin switched cyberpsychosis off for the server (M > ADMIN)
	end
	if p:GetAttribute("AdminPsychoEnabled") == true then return false end
	return Items.IsOwner(p) or (st ~= nil and st.list.colossus ~= nil)
end

local function publish(p: Player)
	local st = stOf(p)
	p:SetAttribute("Cyber", Cyberware.Encode(st.list))
	p:SetAttribute("CyLook", (function()
		local parts = {}
		for k, v in st.look do
			table.insert(parts, k .. "=" .. v)
		end
		table.sort(parts)
		return table.concat(parts, ";")
	end)())
	p:SetAttribute("CyLoad", immune(p) and 0 or Cyberware.Load(st.list))
	p:SetAttribute("CyTol", tolerance(p))
end

------------------------------------------------------------------------
-- the body
------------------------------------------------------------------------

local function alive(p: Player): (Model?, BasePart?)
	local c = p.Character
	local t = c and c:FindFirstChild("Torso")
	if c and t and t:IsA("BasePart") and c:GetAttribute("Dead") ~= true and c.Parent then
		return c, t
	end
	return nil, nil
end

local function scaleFor(list: { [string]: number }): number
	if list.colossus then
		return Config.ColossusScale
	end
	local b = list.bulk
	return b and Config.BulkScale[b] or 1
end

-- size, models, hidden arms, numbers for the client, the Sandevistan
local function applyBody(p: Player, char: Model, quiet: boolean?)
	local st = stOf(p)
	local eff = effective(st)
	-- the size first (the models are built at it)
	local want = scaleFor(st.list)
	local cur = char:GetAttribute("BodyScale")
	cur = typeof(cur) == "number" and cur or 1
	if math.abs(want - cur) > 0.01 then
		CyberModels.Strip(char)
		local ok, err = pcall(function()
			char:ScaleTo(want)
			if want > cur then
				-- (grown from the middle: lift it so the legs do not end up in the floor)
				char:PivotTo(char:GetPivot() + Vector3.new(0, (want - cur) * 3, 0))
			end
		end)
		if not ok then
			warn("[cyber] scale", err)
		else
			char:SetAttribute("BodyScale", want ~= 1 and want or nil)
		end
	end
	char:SetAttribute("Colossus", st.list.colossus ~= nil or nil)
	-- the models (COLOSSUS: its armour, its cannon and blades)
	local dressList = st.list
	if st.list.colossus then
		dressList = { colossus = 1, howler_L = 3, sickles_R = 3 }
	end
	CyberModels.Dress(char, dressList, st.look)
	-- a TITAN arm replaces the real one: hide it (and show it again when it is out)
	for side, partName in ARM_PART do
		local arm = char:FindFirstChild(partName)
		if arm and arm:IsA("BasePart") and char:GetAttribute("Severed_" .. (side == "L" and "LeftArm" or "RightArm")) ~= true then
			local metal = dressList["titan_" .. side] ~= nil
			arm.Transparency = metal and 1 or 0
			char:SetAttribute("Titan_" .. side, metal and dressList["titan_" .. side] or nil)
		end
	end
	-- the numbers the client uses
	local s = Cyberware.Tier(eff, "strider")
	char:SetAttribute("CySpeed", s > 0 and Config.StriderSpeed[s] or nil)
	char:SetAttribute("CyJump", s > 0 and Config.StriderJump[s] or nil)
	local k = Cyberware.Tier(eff, "keel")
	char:SetAttribute("CyBalance", k > 0 and (1 + 0.3 * k) or nil)
	-- (v2.8.2) BEDROCK STABILIZER: the body's own machine ignores what would knock it over (Sensor, the controller)
	local an = Cyberware.Tier(eff, "anchor")
	char:SetAttribute("CyStance", an > 0 and an or nil)
	-- (v2.8) DEEPWATER LUNGS (DrownService, VirusService, Swim) and ECHO EARS (CyberClient's radar)
	local lu = Cyberware.Tier(eff, "lungs")
	char:SetAttribute("CyLungs", lu > 0 and Config.LungsBreath[lu] or nil)
	local ec = Cyberware.Tier(eff, "echo")
	char:SetAttribute("CyEcho", ec > 0 and ec or nil)
	char:SetAttribute("Cyber", Cyberware.Encode(eff))
	-- the shield
	local a = Cyberware.Tier(eff, "aegis")
	st.shield = a > 0 and Config.AegisShield[a] or 0
	char:SetAttribute("CyShield", a > 0 and st.shield or nil)
	char:SetAttribute("CyShieldMax", a > 0 and Config.AegisShield[a] or nil)
	-- the Sandevistan stays in
	if eff.sandevistan and deps.SandevistanService and not char:GetAttribute("Sandevistan") then
		deps.SandevistanService.Grant(p, true, st.list.colossus ~= nil)
	end
	if not quiet then
		publish(p)
	end
end

-- (v2.8.1) the body's chrome again (a TITAN arm rebuilt after it was cut off)
function CyberService.Redress(p: Player)
	local char = alive(p)
	if char then
		applyBody(p, char, true)
	end
end

local function waitRig(char: Model): boolean
	local t0 = os.clock()
	while char.Parent and not char:GetAttribute("RagdollRig") and os.clock() - t0 < 10 do
		task.wait(0.1)
	end
	return char:GetAttribute("RagdollRig") == true
end

------------------------------------------------------------------------
-- install / remove (the ripperdoc, a player surgeon)
------------------------------------------------------------------------

-- may this implant go into this body? (nil = yes, else why not)
function CyberService.CanInstall(p: Player, id: string, tier: number, side: string?): string?
	local d = Cyberware.ById[id]
	if not d then
		return "unknown implant"
	end
	if d.admin and not Items.Has(p, id) and not stOf(p).gifted[id] then
		return "only admins"
	end
	local st = stOf(p)
	local key = Cyberware.Key(id, side)
	local slot = Cyberware.SlotKey(d, side)
	for k in st.list do
		local kid, kside = Cyberware.Split(k)
		local kd = Cyberware.ById[kid]
		if kd and Cyberware.SlotKey(kd, kside) == slot and k ~= key then
			return "the " .. Cyberware.SlotName[d.slot] .. (side and (" (" .. (side == "L" and "LEFT" or "RIGHT") .. ")") or "") .. " slot is taken by " .. kd.name
		end
	end
	if st.list[key] and st.list[key] >= tier then
		return "already in"
	end
	return nil
end

-- puts it in (or a higher tier over the old one). Returns the key.
function CyberService.Install(p: Player, id: string, tier: number, side: string?, look: string?): string?
	local d = Cyberware.ById[id]
	if not d or CyberService.CanInstall(p, id, tier, side) then
		return nil
	end
	local st = stOf(p)
	local key = Cyberware.Key(id, side)
	st.list[key] = math.clamp(tier, 1, d.tiers)
	if id == "titan" and not st.look[key] then
		st.look[key] = look or CyberModels.RandomLook(rng)
	elseif id == "howler" and not st.look.howler then
		st.look.howler = "EXPLOSIVE:RED"
	end
	save(p)
	publish(p)
	local char = alive(p)
	if char then
		applyBody(p, char)
	end
	if Remote then
		local extra = id == "sandevistan" and " DOUBLE-TAP SHIFT TO USE IT." or (d.ability and (" ITS KEY IS ON THE CYBER BAR (" .. d.ability .. ").") or "")
		Remote:FireClient(p, "msg", d.name .. " (TIER " .. tier .. ") IS IN." .. extra)
	end
	return key
end

-- takes it out. Returns (id, tier) of what came out.
function CyberService.Remove(p: Player, key: string): (string?, number?)
	local st = stOf(p)
	local tier = st.list[key]
	if not tier then
		return nil, nil
	end
	local id = Cyberware.Split(key)
	st.list[key] = nil
	if id == "titan" then
		st.look[key] = nil
	end
	if st.hunt and id == "cortex" then
		st.hunt = nil
		p:SetAttribute("CyHunt", nil)
	end
	save(p)
	publish(p)
	local char = alive(p)
	if id == "sandevistan" and deps.SandevistanService then
		deps.SandevistanService.Revoke(p)
	end
	if char then
		if id == "colossus" and deps.SandevistanService and not st.list.sandevistan then
			deps.SandevistanService.Revoke(p)
		end
		char:SetAttribute("Cy_open_" .. key, nil)
		applyBody(p, char)
	end
	return id, tier
end

function CyberService.List(p: Player): { [string]: number }
	return table.clone(stOf(p).list)
end

-- (admin gifts) an admin-only implant this player may have
function CyberService.Gift(p: Player, id: string)
	stOf(p).gifted[id] = true
end

-- the HOWLER's shell / colour (M > CYBERWARE)
local function setLook(p: Player, key: string, value: string)
	local st = stOf(p)
	if key == "howler" then
		local shell, col = string.match(value, "^(%u+):(%u+)$")
		local okS, okC = false, false
		for _, s in Cyberware.Shells do
			okS = okS or s == shell
		end
		for _, c in Cyberware.Colors do
			okC = okC or c.name == col
		end
		if okS and okC then
			st.look.howler = value
			save(p)
			publish(p)
			local char = alive(p)
			if char then
				for k in effective(st) do
					if string.sub(k, 1, 6) == "howler" then
						CyberModels.DressOne(char, k, effective(st)[k], value)
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- abilities
------------------------------------------------------------------------

local function say(p: Player, text: string)
	Remote:FireClient(p, "msg", text)
end

local function ready(p: Player, key: string, id: string): boolean
	local st = stOf(p)
	local d = Cyberware.ById[id]
	local t = Cyberware.Tier(effective(st), id)
	if not d or t <= 0 then
		return false
	end
	local cd = d.cooldown and d.cooldown[t] or 1
	local now = os.clock()
	if now < (st.cd[key] or 0) then
		return false
	end
	st.cd[key] = now + cd * 0.9
	p:SetAttribute("CyCD_" .. key, workspace:GetServerTimeNow() + cd)
	return true
end

local function fx(t: string, data: { [string]: any })
	data.t = t
	Remote:FireAllClients("fx", data)
end

-- HUNT: the person at your crosshair becomes your target
local function hunt(p: Player, target: any)
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target == p then
		return
	end
	local st = stOf(p)
	st.hunt = target
	p:SetAttribute("CyHunt", target.UserId)
	say(p, "TARGET: " .. string.upper(target.DisplayName))
end

-- the forearm a key sits in (its part and the scale)
local function foreArm(p: Player, key: string): (BasePart?, number)
	local char = alive(p)
	local side = string.sub(key, -1)
	local arm = char and char:FindFirstChild(ARM_PART[side] or "")
	local s = char and char:GetAttribute("BodyScale")
	return (arm and arm:IsA("BasePart")) and arm or nil, typeof(s) == "number" and s or 1
end

-- CANNON: a shell out of the forearm
local launchShell

local function cannon(p: Player, key: string, dir: any)
	if typeof(dir) ~= "Vector3" or dir.Magnitude < 0.5 or dir ~= dir then
		return
	end
	dir = dir.Unit
	local arm, s = foreArm(p, key)
	local char = p.Character
	if not arm or not char then
		return
	end
	local t = tierOf(p, "howler")
	local look = stOf(p).look.howler or "EXPLOSIVE:RED"
	local shell, colName = string.match(look, "^(%u+):(%u+)$")
	local col = Cyberware.Colors[1].c
	for _, c in Cyberware.Colors do
		if c.name == colName then
			col = c.c
		end
	end
	local origin = (arm.CFrame * CFrame.new(0, -1.4 * s, 0)).Position
	if (origin - arm.Position).Magnitude > 6 * s then
		return
	end
	launchShell(origin, dir, t, shell or "EXPLOSIVE", col, p, char, s)
end

-- a HOWLER shell (a player's, or a chromed NPC's): flies on game time, explodes / shocks / slugs what it hits
launchShell = function(origin: Vector3, dir: Vector3, t: number, shell: string, col: Color3, p: Player?, char: Instance?, scale: number?)
	local speed = shell == "SLUG" and 650 or (shell == "SHOCK" and 170 or 190)
	-- (v2.8.2) the shell you SEE is drawn by every screen itself (smooth: a cased round with a glowing tail, smoke and
	-- a light - CyberClient "cannon"); this one is invisible and only does the work
	local ball = Instance.new("Part")
	ball.Name = "HowlerShell"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(0.5, 0.5, 0.5) * (0.8 + t * 0.2) * math.min(scale or 1, 1.6)
	ball.Transparency = 1
	ball.Anchored, ball.CanCollide, ball.CanQuery, ball.CanTouch, ball.CastShadow = true, false, false, false, false
	ball.CFrame = CFrame.new(origin)
	ball.Parent = workspace:FindFirstChild("FX") or workspace
	fx("cannon", { p = origin, d = dir, c = col, by = p and p.UserId or 0, shell = shell, v = speed, tier = t, s = math.min(scale or 1, 1.6), ig = char })
	pcall(deps.GoreService.Sound, "rocketLaunch", origin, 1)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	if char then
		table.insert(ignore, char)
	end
	local fxFolder = workspace:FindFirstChild("FX")
	if fxFolder then
		table.insert(ignore, fxFolder)
	end
	params.FilterDescendantsInstances = ignore
	local pos, vel, flown = origin, dir * speed, 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not ball.Parent then
			conn:Disconnect()
			return
		end
		if workspace:GetAttribute("TimeStop") then
			return
		end
		dt *= TimeScale.Get()
		if shell ~= "SLUG" then
			vel += Vector3.new(0, -TimeScale.Gravity() * 0.08, 0) * dt
		end
		local step = vel * dt
		local hit = workspace:Raycast(pos, step, params)
		flown += step.Magnitude
		if hit or flown > 900 then
			conn:Disconnect()
			ball:Destroy()
			local at = hit and hit.Position or pos
			if shell == "EXPLOSIVE" then
				deps.ExplosionService.Explode(at - vel.Unit * 0.3, {
					radius = Config.HowlerRadius[t], damage = Config.HowlerDamage[t], power = 55 + t * 20,
					attacker = p, cause = "HOWLER shell", kind = "grenade",
				})
			elseif hit then
				local body, region = deps.DamageService.BodyOf(hit.Instance)
				if shell == "SHOCK" then
					fx("shock", { p = at, r = 5 })
					pcall(deps.GoreService.Sound, "taser", at, 1)
					for m in deps.DamageService.Bodies() do
						local tt = m:FindFirstChild("Torso")
						if m ~= char and tt and tt:IsA("BasePart") and (tt.Position - at).Magnitude < 5 + t then
							deps.DamageService.ApplyDamage(m, "Torso", 18 + 8 * t, tt.Position, { cause = "Shocked by " .. (p and p.DisplayName or "a chromed merc"), allowSever = false, attacker = p })
							deps.DamageService.Knock(m, "Torso", nil, 2.5 + t)
						end
					end
				elseif body and region then
					deps.DamageService.ApplyDamage(body, region, 80 + 30 * t, at, {
						cause = "Slugged by " .. (p and p.DisplayName or "a chromed merc"), allowSever = true, severAt = 90, attacker = p, bleed = 1, bleedTime = 15,
					})
					deps.DamageService.Blast(body, vel.Unit * (50 + 15 * t) + Vector3.new(0, 15, 0), 2)
					pcall(deps.GoreService.Sound, "heavyHit", at, 1)
				else
					fx("spark", { p = at })
					pcall(deps.GoreService.Sound, "ricochet", at, 1)
				end
			end
			return
		end
		pos += step
		ball.CFrame = CFrame.new(pos)
	end)
end

-- ARM GUN / BLADES: open or close
local function toggle(p: Player, key: string)
	local char = alive(p)
	if not char then
		return
	end
	local open = not char:GetAttribute("Cy_open_" .. key)
	char:SetAttribute("Cy_open_" .. key, open or nil)
	local eff = effective(stOf(p))
	CyberModels.DressOne(char, key, eff[key] or 1, stOf(p).look[key])
	fx("toggle", { by = p.UserId, k = key, o = open })
	pcall(deps.GoreService.Sound, "ratchet", char:FindFirstChild("Torso"), 1)
end

-- ARM GUN: one shot (F while it is open and the hand is empty)
local function armShot(p: Player, key: string, dir: any)
	if typeof(dir) ~= "Vector3" or dir.Magnitude < 0.5 or dir ~= dir then
		return
	end
	local char = alive(p)
	if not char or not char:GetAttribute("Cy_open_" .. key) then
		return
	end
	local t = tierOf(p, "shiftgun")
	local st = stOf(p)
	local now = os.clock()
	-- (v2.8.1) each arm has its own trigger: two arm guns fire together
	local lastT = st.armLast or {}
	st.armLast = lastT
	if t <= 0 or now - (lastT[key] or 0) < Config.ShiftgunRate[t] * 0.75 then
		return
	end
	-- (v2.8.1) a magazine: empty, the arm reloads itself (a moment, then it is full again)
	local ammoT = st.armAmmo or {}
	st.armAmmo = ammoT
	local reloadT = st.armReload or {}
	st.armReload = reloadT
	local mag = Config.ShiftgunMag[t]
	if reloadT[key] then
		if now < reloadT[key] then
			return
		end
		reloadT[key] = nil
		ammoT[key] = mag
	end
	local ammo = ammoT[key] or mag
	if ammo <= 0 then
		return
	end
	st.lastShot = now
	local arm, s = foreArm(p, key)
	if not arm then
		return
	end
	local origin = (arm.CFrame * CFrame.new(0, -2.65 * s, -0.05 * s)).Position
	deps.GunService.ArmShot(p, char, origin, dir.Unit, Config.ShiftgunDamage[t], "rifle")
	fx("armshot", { by = p.UserId, k = key })
	lastT[key] = now
	ammo -= 1
	ammoT[key] = ammo
	p:SetAttribute("CyAmmo_" .. key, ammo)
	if ammo <= 0 then
		local rt = Config.ShiftgunReload[t]
		reloadT[key] = now + rt
		p:SetAttribute("CyReload_" .. key, workspace:GetServerTimeNow() + rt)
		fx("armreload", { by = p.UserId, k = key, t = rt })
		task.delay(rt, function()
			if reloadT[key] and os.clock() >= reloadT[key] - 0.05 then
				reloadT[key] = nil
				ammoT[key] = Config.ShiftgunMag[math.max(1, tierOf(p, "shiftgun"))]
				if p.Parent then
					p:SetAttribute("CyAmmo_" .. key, ammoT[key])
					p:SetAttribute("CyReload_" .. key, nil)
				end
			end
		end)
	end
end

-- PULL: the item you look at flies to you
local function pull(p: Player, item: any)
	local char, torso = alive(p)
	if not char or not torso or typeof(item) ~= "Instance" or not item:IsA("Model") or not Items.Kind(item) then
		return
	end
	local t = tierOf(p, "lodestone")
	local root = item.PrimaryPart
	if not root or root.Anchored or (root.Position - torso.Position).Magnitude > Config.LodestoneRange[t] + 6 then
		return
	end
	-- (v2.8.1) never out of a pocket, a sheath or a holster, and never what is bound to somebody else
	local bound = item:GetAttribute("BoundTo")
	if item:GetAttribute("StowedBy") ~= nil or item:GetAttribute("InSheath") or (typeof(bound) == "number" and bound ~= p.UserId) then
		say(p, "It is in a pocket: the palms can not reach it.")
		return
	end
	local holder = deps.OwnershipService.ItemHolder(item)
	if holder == p then
		return
	end
	if holder then
		-- tier 3 rips a gun out of somebody's hand (never out of an admin's)
		if t < 3 or not Items.IsGun(item) or Items.IsOwner(holder) then
			say(p, "It is held too tight.")
			return
		end
		deps.OwnershipService.DropItem(item)
	end
	fx("pull", { by = p.UserId, item = item })
	pcall(deps.GoreService.Sound, "metal", torso, 0.8)
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 1.2 and root.Parent and torso.Parent and not deps.OwnershipService.ItemHolder(item) do
			local goal = torso.Position + torso.CFrame.LookVector * 2.5 + Vector3.new(0, 1, 0)
			local d = goal - root.Position
			if d.Magnitude < 2 then
				root.AssemblyLinearVelocity = Vector3.zero
				break
			end
			root.AssemblyLinearVelocity = d.Unit * math.min(70, d.Magnitude * 7) + Vector3.new(0, 2, 0)
			root.AssemblyAngularVelocity *= 0.8
			RunService.Heartbeat:Wait()
		end
		task.delay(0.3, function()
			if root.Parent and not deps.OwnershipService.ItemHolder(item) then
				pcall(function()
					root:SetNetworkOwner(p)
				end)
			end
		end)
	end)
	Remote:FireClient(p, "pulled", item)
end

-- CLOAK
local function cloak(p: Player)
	local char = alive(p)
	if not char then
		return
	end
	local t = tierOf(p, "ghostskin")
	local untilT = workspace:GetServerTimeNow() + Config.CloakTime[t]
	char:SetAttribute("Cloaked", untilT)
	fx("cloak", { by = p.UserId })
	task.delay(Config.CloakTime[t], function()
		if char.Parent and char:GetAttribute("Cloaked") == untilT then
			char:SetAttribute("Cloaked", nil)
		end
	end)
end

-- FREEZE (ZERO HOUR, admins): every other player and bot is frozen in ice
local frozenUntil = 0
local function freezeAll(p: Player)
	local untilT = workspace:GetServerTimeNow() + Config.ZeroHourTime
	frozenUntil = untilT
	fx("freeze", { by = p.UserId, d = Config.ZeroHourTime })
	local frozenBodies = {}
	for m in deps.DamageService.Bodies() do
		if m ~= p.Character and m.Parent and m:GetAttribute("Dead") ~= true then
			m:SetAttribute("CyFrozen", untilT)
			table.insert(frozenBodies, m)
			-- an ice block round it
			local ok, cf, size = pcall(function()
				return m:GetBoundingBox()
			end)
			if ok and cf then
				local ice = Instance.new("Part")
				ice.Name = "ZeroHourIce"
				ice.Size = size + Vector3.new(0.6, 0.6, 0.6)
				ice.CFrame = cf
				ice.Material = Enum.Material.Ice
				ice.Color = Color3.fromRGB(170, 220, 255)
				ice.Transparency = 0.45
				ice.Anchored, ice.CanCollide, ice.CanQuery, ice.CanTouch = true, false, false, false
				ice.Parent = workspace:FindFirstChild("FX") or workspace
				task.delay(Config.ZeroHourTime, function()
					ice:Destroy()
				end)
			end
			if not Players:GetPlayerFromCharacter(m) then
				-- a bot / a corpse: the server holds it still
				local torso = m:FindFirstChild("Torso")
				if torso and torso:IsA("BasePart") then
					torso.Anchored = true
				end
			end
		end
	end
	pcall(deps.GoreService.Sound, "glass", p.Character and p.Character:FindFirstChild("Torso"), 1)
	task.delay(Config.ZeroHourTime, function()
		if frozenUntil ~= untilT then
			return
		end
		for _, m in frozenBodies do
			if m.Parent then
				m:SetAttribute("CyFrozen", nil)
				if not Players:GetPlayerFromCharacter(m) then
					local torso = m:FindFirstChild("Torso")
					if torso and torso:IsA("BasePart") then
						torso.Anchored = false
					end
				end
			end
		end
	end)
end

local function useAbility(p: Player, key: string, a: any, b: any)
	if typeof(key) ~= "string" then
		return
	end
	local st = stOf(p)
	local eff = effective(st)
	if not eff[key] then
		return
	end
	local id = Cyberware.Split(key)
	local char = alive(p)
	if not char or char:GetAttribute("Asleep") or char:GetAttribute("CyFrozen") then
		return
	end
	if id == "cortex" then
		if ready(p, key, id) then
			hunt(p, a)
		end
	elseif id == "howler" then
		if ready(p, key, id) then
			cannon(p, key, a)
		end
	elseif id == "shiftgun" or id == "sickles" then
		if ready(p, key, id) then
			toggle(p, key)
		end
	elseif id == "lodestone" then
		if ready(p, key, id) then
			pull(p, a)
		end
	elseif id == "ghostskin" then
		if ready(p, key, id) then
			cloak(p)
		end
	elseif id == "zerohour" then
		if (Items.Has(p, "zerohour") or st.gifted.zerohour) and ready(p, key, id) then
			freezeAll(p)
		end
	end
	local _ = b
end

------------------------------------------------------------------------
-- passive effects
------------------------------------------------------------------------

local function regionArmSide(region: string): string?
	if region == "LeftArm" then
		return "L"
	elseif region == "RightArm" then
		return "R"
	end
	return nil
end

-- (v2.8.2) BASTION SHELL: is the spot a bullet hit one of the gaps? (the head, the sides of the chest under the arms,
-- the backs of the legs, the hands)
local function bastionGap(model: Model, region: string, point: Vector3?): boolean
	if region == "Head" then
		return true
	end
	if not point then
		return false
	end
	local sc = model:GetAttribute("BodyScale")
	local k = typeof(sc) == "number" and sc or 1
	local partName = (region == "Torso" and "Torso") or (region == "LeftArm" and "Left Arm") or (region == "RightArm" and "Right Arm")
		or (region == "LeftLeg" and "Left Leg") or (region == "RightLeg" and "Right Leg") or nil
	local part = partName and model:FindFirstChild(partName)
	if not part or not part:IsA("BasePart") then
		return false
	end
	local lp = part.CFrame:PointToObjectSpace(point)
	if region == "Torso" then
		return math.abs(lp.X) > 0.74 * k and math.abs(lp.Z) < 0.55 * k -- (the sides under the arms)
	elseif region == "LeftLeg" or region == "RightLeg" then
		return lp.Z > 0.2 * k -- (the back of the leg)
	else
		return lp.Y < -0.75 * k -- (the hand)
	end
end

local function modifyDamage(model: Model, region: string, dmg: number, opts: any, point: Vector3?): (number, any?)
	if opts.cyberAttack then return dmg, nil end
	-- the attacker's side: HUNTER CORTEX tier 3
	local atk = opts.attacker
	if atk and states[atk] and states[atk].hunt and Cyberware.Tier(effective(states[atk]), "cortex") >= 3 then
		local victim = playerOf(model)
		if victim and victim == states[atk].hunt then
			dmg *= Config.HunterBonus
		end
	end
	local p = playerOf(model)
	local st = p and states[p]
	if not p or not st then
		-- (v2.8) a chromed NPC's AEGIS
		local sh = model:GetAttribute("NPCShield")
		if typeof(sh) == "number" and sh > 0 then
			local take = math.min(sh, dmg)
			model:SetAttribute("NPCShield", sh - take)
			model:SetAttribute("NPCShieldHit", os.clock())
			local tt = model:FindFirstChild("Torso")
			if tt and tt:IsA("BasePart") then
				fx("shieldat", { p = tt.Position })
			end
			return dmg - take, nil
		end
		return dmg, nil
	end
	local off = model:GetAttribute("ChipsDisabled")
	if typeof(off) == "number" and off > workspace:GetServerTimeNow() then return dmg, nil end
	local eff = effective(st)
	local newOpts = nil
	st.lastHurt = os.clock()
	if eff.colossus then
		-- (v2.8.1) bullets and blades do nothing to it at all; blasts, cars, falls and nukes still hurt (less)
		if opts.bullet or opts.melee then
			return 0, nil
		end
		dmg *= opts.nuke and 0.6 or 0.35
	end
	-- (v2.8) IRONHEART PUMP: the wound bleeds less
	local pu = Cyberware.Tier(eff, "pump")
	if pu > 0 and typeof(opts.bleed) == "number" then
		newOpts = table.clone(opts)
		newOpts.bleed = opts.bleed * Config.PumpBleed[pu]
	end
	local b = eff.bulk
	if b then
		dmg *= Config.BulkArmor[b]
	end
	local bw = Cyberware.Tier(eff, "blastweave")
	if bw > 0 and opts.blast then
		dmg *= Config.BlastDamage[bw]
	end
	local side = regionArmSide(region)
	local ti = side and eff["titan_" .. side]
	if ti then
		dmg /= 1 + Config.TitanBonus[ti]
		if ti >= 3 and opts.allowSever ~= false then
			newOpts = newOpts or table.clone(opts)
			newOpts.allowSever = false
		end
	end
	-- (v2.8.2) BASTION SHELL: a bullet on a plate does little; one through a gap does it all. A bullet is a threat too:
	-- the plates close (the first one still hits as it comes)
	local bt = Cyberware.Tier(eff, "bastion")
	if bt > 0 and opts.bullet then
		local up = st.bastionUntil ~= nil and os.clock() < st.bastionUntil
		if up and not bastionGap(model, region, point) then
			dmg *= Config.BastionCut[bt]
			if point then
				pcall(deps.GoreService.Sound, "metal", point, 0.9)
				pcall(deps.GoreService.FX, { t = "burst", p = point, d = Vector3.yAxis, n = 4, s = 10, black = true })
			end
		end
		pcall(CyberService.BastionUp, p)
	end
	-- the AEGIS shield takes what is left first
	if st.shield > 0 and dmg > 0 then
		local take = math.min(st.shield, dmg)
		st.shield -= take
		dmg -= take
		st.lastHit = os.clock()
		model:SetAttribute("CyShield", math.floor(st.shield))
		fx("shield", { by = p.UserId, left = st.shield, r = region, max = Config.AegisShield[math.max(1, Cyberware.Tier(eff, "aegis"))] })
	elseif eff.aegis then
		st.lastHit = os.clock()
	end
	return dmg, newOpts
end

local function maybeCrash(p: Player, why: string)
	local st = states[p]
	if not st or immune(p) or st.psycho < 0.2 then
		return
	end
	local now = os.clock()
	if now - st.lastCrash < Config.CrashOutCooldown then
		return
	end
	if rng:NextNumber() > st.psycho * 0.6 then
		return
	end
	local char = alive(p)
	if not char then
		return
	end
	st.lastCrash = now
	char:SetAttribute("CrashOut", workspace:GetServerTimeNow() + Config.CrashOutTime)
	Remote:FireClient(p, "crash", Config.CrashOutTime, why)
	task.delay(Config.CrashOutTime, function()
		if char.Parent then
			char:SetAttribute("CrashOut", nil)
		end
	end)
end

local function afterDamage(model: Model, region: string, dmg: number, opts: any)
	local victim = playerOf(model)
	local atk = opts.attacker
	-- STATIC DERMIS: hurt up close -> shocked back
	if victim and atk and atk ~= victim and opts.melee then
		local t = tierOf(victim, "dermis")
		local ac = atk.Character
		local at = ac and ac:FindFirstChild("Torso")
		local vt = model:FindFirstChild("Torso")
		if t > 0 and at and vt and at:IsA("BasePart") and vt:IsA("BasePart") and (at.Position - vt.Position).Magnitude < 10 then
			fx("zap", { a = vt.Position, b = at.Position })
			pcall(deps.GoreService.Sound, "taser", at, 1)
			deps.DamageService.ApplyDamage(ac, "Torso", Config.DermisShock[t], at.Position, { cause = "Shocked by " .. victim.DisplayName, allowSever = false, attacker = victim })
			if t >= 2 then
				local push = t >= 3 and (at.Position - vt.Position).Unit * 45 + Vector3.new(0, 18, 0) or nil
				deps.DamageService.Knock(ac, "Torso", push and push * deps.DamageService.PartMass(ac, "Torso") or nil, 1 + t * 0.8)
			end
		end
	end
	-- cyberpsychosis: you hurt somebody / somebody hurt you up close
	if atk and states[atk] and atk ~= victim then
		maybeCrash(atk, "shot")
	end
	if victim and opts.melee then
		maybeCrash(victim, "touched")
	end
	-- GHOSTSKIN: attacking shows you for a moment
	local ac = atk and atk.Character
	if ac and ac:GetAttribute("Cloaked") then
		ac:SetAttribute("CloakReveal", workspace:GetServerTimeNow() + 1)
	end
	local _ = dmg
	local _r = region
end

local function knockFilter(model: Model, kind: string, ragdollTime: number?, push: Vector3?): (number?, Vector3?)
	local p = playerOf(model)
	local st = p and states[p]
	if not st then
		return ragdollTime, push
	end
	local eff = effective(st)
	if eff.colossus and not deps.DamageService.heavyHit then
		local big = kind == "blast" and push ~= nil and push.Magnitude >= Config.ColossusBigBlast
		if not big then
			return nil, push and push * 0.12 or nil
		end
	end
	local k = Cyberware.Tier(eff, "keel")
	if k > 0 and ragdollTime then
		if kind == "knock" and k >= 2 and math.abs(ragdollTime - Config.BulletTorsoKnockdown) < 1e-3 then
			ragdollTime = nil -- (a body shot no longer knocks you over)
		else
			ragdollTime *= Config.KeelKnock[k]
		end
	end
	local bw = Cyberware.Tier(eff, "blastweave")
	if bw > 0 and kind == "blast" and push then
		push *= Config.BlastPush[bw]
	end
	-- (v2.8.2) BEDROCK STABILIZER: hits and kicks never knock you over and barely push you; tier 3 not even a blast
	local an = Cyberware.Tier(eff, "anchor")
	if an > 0 then
		if kind == "knock" then
			ragdollTime = nil
			push = push and push * Config.AnchorPush[an] or nil
		elseif kind == "blast" then
			if an >= 3 then
				ragdollTime = nil
				push = push and push * 0.35 or nil
			elseif ragdollTime then
				ragdollTime *= an >= 2 and 0.5 or 0.8
			end
		end
	end
	return ragdollTime, push
end

-- KnockService: a punch from a TITAN arm / with SICKLE BLADES out
local function punchMod(p: Player, fist: Vector3): any
	local char = alive(p)
	local st = states[p]
	if not char or not st then
		return nil
	end
	local eff = effective(st)
	local best, side = math.huge, "R"
	for sd, name in ARM_PART do
		local a = char:FindFirstChild(name)
		if a and a:IsA("BasePart") then
			local d = (a.Position - fist).Magnitude
			if d < best then
				best, side = d, sd
			end
		end
	end
	local out: any = nil
	local ti = eff["titan_" .. side]
	if ti then
		out = { k = 1 + Config.TitanBonus[ti] }
	end
	local sk = eff["sickles_" .. side]
	if sk and char:GetAttribute("Cy_open_sickles_" .. side) then
		out = out or { k = 1 }
		out.k *= 1.6 + 0.4 * sk
		out.bleed = 0.9
		out.sever = sk >= 2 and 75 or nil
		out.cause = "Sliced by "
	end
	if eff.colossus then
		out = out or { k = 1 }
		out.k *= 2.2
	end
	return out
end

-- (v2.8.2) BASTION SHELL: the plates fold out of their slots and close round you (or stay closed longer); when the threat
-- is over they fold away again
function CyberService.BastionUp(p: Player)
	local st = states[p]
	local char = alive(p)
	if not st or not char then
		return
	end
	local t = Cyberware.Tier(effective(st), "bastion")
	if t <= 0 then
		return
	end
	st.bastionUntil = os.clock() + Config.BastionTime[t]
	char:SetAttribute("BastionUntil", workspace:GetServerTimeNow() + Config.BastionTime[t])
	if st.bastionPlates then
		return -- (closed already: it just stays closed longer)
	end
	local plates = CyberModels.Bastion(char, t)
	st.bastionPlates = plates
	local TweenService = game:GetService("TweenService")
	local open = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	for i, pl in plates do
		task.delay(i * 0.015, function()
			if pl.part.Parent then
				TweenService:Create(pl.weld, open, { C0 = pl.out }):Play()
				TweenService:Create(pl.part, open, { Size = pl.size }):Play()
			end
		end)
	end
	local torso = char:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		pcall(deps.GoreService.Sound, "ratchet", torso, 1)
		pcall(deps.GoreService.Sound, "metal", torso, 0.7)
	end
	task.spawn(function()
		while char.Parent and not char:GetAttribute("Dead") and st.bastionUntil and os.clock() < st.bastionUntil and states[p] == st do
			task.wait(0.2)
		end
		local close = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, pl in plates do
			if pl.part.Parent then
				TweenService:Create(pl.weld, close, { C0 = pl.tuck }):Play()
				TweenService:Create(pl.part, close, { Size = pl.size * 0.2 }):Play()
			end
		end
		task.wait(0.32)
		for _, pl in plates do
			local f = pl.part.Parent
			pl.part:Destroy()
			if f and f:IsA("Folder") and #f:GetChildren() == 0 then
				f:Destroy()
			end
		end
		if st.bastionPlates == plates then
			st.bastionPlates = nil
			st.bastionUntil = nil
		end
		if char.Parent then
			char:SetAttribute("BastionUntil", nil)
		end
	end)
end

-- (v2.8.2) an arm swung into a body with SICKLE BLADES out: the blade cuts (KnockService.BladeMod)
local function bladeMod(p: Player, at: Vector3): any
	local char = alive(p)
	local st = states[p]
	if not char or not st then
		return nil
	end
	local eff = effective(st)
	local best, side = math.huge, "R"
	for sd, name in ARM_PART do
		local a = char:FindFirstChild(name)
		if a and a:IsA("BasePart") then
			local d = (a.Position - at).Magnitude
			if d < best then
				best, side = d, sd
			end
		end
	end
	local sk = eff["sickles_" .. side]
	if not sk or not char:GetAttribute("Cy_open_sickles_" .. side) or best > 5 then
		return nil
	end
	return { base = 14 + 8 * sk, perSpeed = 0.7 + 0.15 * sk, sever = sk >= 2 and (sk >= 3 and 55 or 70) or nil }
end

-- SENTRY REFLEX: a shot went past / at you
local function shotLine(shooter: Player, origin: Vector3, dir: Vector3, range: number)
	for p, st in states do
		if p ~= shooter then
			local t = Cyberware.Tier(effective(st), "sentry")
			local char, torso = alive(p)
			-- (v2.8.1) an arm gun that is out fires back too: it needs to know (tier 0 = no SENTRY, only the arm gun)
			local armOut = char ~= nil and (char:GetAttribute("Cy_open_shiftgun_L") or char:GetAttribute("Cy_open_shiftgun_R"))
			local shell = Cyberware.Tier(effective(st), "bastion") > 0 -- (v2.8.2) BASTION SHELL closes on a threat
			if (t > 0 or armOut or shell) and torso then
				local rel = torso.Position - origin
				local along = rel:Dot(dir)
				if along > 0 and along < range then
					local off = (rel - dir * along).Magnitude
					if off < 7 then
						if t > 0 or armOut then
							Remote:FireClient(p, "threat", shooter.UserId, origin, t)
						end
						if shell then
							pcall(CyberService.BastionUp, p)
						end
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- (v2.8) CHROMED MERCS: NPCs with random cyberware (and their gun). What they carry shows, and does something:
-- optics aim better, STRIDER legs run faster, an AEGIS shield, a HOWLER that fires at their target, SICKLE BLADES that cut
-- whoever comes close, a TITAN arm.
------------------------------------------------------------------------

local npcNext: { [Model]: number } = {}

local function chromeNPC(model: Model, npc: any)
	local list: { [string]: number } = { optics = rng:NextInteger(1, 3) }
	local look: { [string]: string } = {}
	if rng:NextNumber() < 0.55 then
		list.howler_R = rng:NextInteger(1, 3)
		look.howler = Cyberware.Shells[rng:NextInteger(1, 2)] .. ":" .. Cyberware.Colors[rng:NextInteger(1, #Cyberware.Colors)].name
	else
		list.sickles_R = rng:NextInteger(1, 3)
	end
	if rng:NextNumber() < 0.5 then
		list.titan_L = rng:NextInteger(1, 3)
		look.titan_L = CyberModels.RandomLook(rng)
	end
	if rng:NextNumber() < 0.5 then
		list.strider = rng:NextInteger(1, 3)
	end
	if rng:NextNumber() < 0.45 then
		list.aegis = rng:NextInteger(1, 3)
	end
	if rng:NextNumber() < 0.3 then
		list.keel = 2
	end
	model:SetAttribute("Cyber", Cyberware.Encode(list))
	model:SetAttribute("CyberNPC", true)
	CyberModels.Dress(model, list, look)
	if list.titan_L then
		local arm = model:FindFirstChild("Left Arm")
		if arm and arm:IsA("BasePart") then
			arm.Transparency = 1
		end
	end
	if list.strider then
		model:SetAttribute("CySpeed", Config.StriderSpeed[list.strider])
	end
	if list.aegis then
		model:SetAttribute("NPCShield", Config.AegisShield[list.aegis])
		model:SetAttribute("NPCShieldMax", Config.AegisShield[list.aegis])
	end
	model:SetAttribute("NPCLook", look.howler)
	local _ = npc
end

-- every think of a chromed NPC: the cannon, the blades, the shield
local function npcThink(npc: any)
	local model: Model = npc.model
	if not model:GetAttribute("CyberNPC") then
		return
	end
	local list = Cyberware.Decode(model:GetAttribute("Cyber"))
	local now = os.clock()
	-- the shield comes back
	local sh, mx = model:GetAttribute("NPCShield"), model:GetAttribute("NPCShieldMax")
	if typeof(mx) == "number" and typeof(sh) == "number" and sh < mx and now - (model:GetAttribute("NPCShieldHit") or 0) > 6 then
		model:SetAttribute("NPCShield", math.min(mx, sh + 8))
	end
	local target: Model? = npc.target
	local tt = target and target:FindFirstChild("Torso")
	local me = model:FindFirstChild("Torso")
	if not target or not tt or not me or not tt:IsA("BasePart") or not me:IsA("BasePart") or target:GetAttribute("Dead") then
		return
	end
	local d = (tt.Position - me.Position).Magnitude
	if now < (npcNext[model] or 0) then
		return
	end
	if list.howler_R and d < 140 and d > 10 then
		npcNext[model] = now + Config.Cyber_NPCCannon
		local arm = model:FindFirstChild("Right Arm")
		if arm and arm:IsA("BasePart") then
			local origin = (arm.CFrame * CFrame.new(0, -1.4, 0)).Position
			local aim = tt.Position + tt.AssemblyLinearVelocity * (d / 190) * 0.6 + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(-1, 2), rng:NextNumber(-2, 2))
			local lookStr = model:GetAttribute("NPCLook")
			local shell, colName = string.match(typeof(lookStr) == "string" and lookStr or "EXPLOSIVE:RED", "^(%u+):(%u+)$")
			local col = Cyberware.Colors[1].c
			for _, c in Cyberware.Colors do
				if c.name == colName then
					col = c.c
				end
			end
			launchShell(origin, (aim - origin).Unit, list.howler_R, shell or "EXPLOSIVE", col, nil, model, 1)
			fx("cannon", { p = origin, d = (aim - origin).Unit, c = col, by = 0 })
		end
	elseif list.sickles_R and d < 6 then
		npcNext[model] = now + 1.1
		model:SetAttribute("Cy_open_sickles_R", true)
		CyberModels.DressOne(model, "sickles_R", list.sickles_R, nil)
		local region = ({ "Torso", "LeftArm", "RightArm", "Head" })[rng:NextInteger(1, 4)]
		deps.DamageService.ApplyDamage(target, region, 24 + 8 * list.sickles_R, tt.Position, {
			cause = "Sliced by a chromed merc", allowSever = list.sickles_R >= 2, severAt = 70, bleed = 0.9, bleedTime = 12, melee = true,
		})
		deps.DamageService.Knock(target, region, (tt.Position - me.Position).Unit * 30 * deps.DamageService.PartMass(target, region), 1.2)
		pcall(deps.GoreService.Sound, "slash", tt, 1)
	end
end

------------------------------------------------------------------------

function CyberService.AdminPsychosis(p: Player, enabled: boolean)
	if not Items.IsOwner(p) then return end
	local st = stOf(p)
	st.psycho = enabled and math.max(st.psycho, 0.65) or 0
	publish(p)
	p:SetAttribute("CyPsycho", st.psycho > 0 and st.psycho or nil)
end

function CyberService.Init(d: any)
	deps = d
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	Remote = Remotes:FindFirstChild("Cyber") :: RemoteEvent
	if not Remote then
		local r = Instance.new("RemoteEvent")
		r.Name = "Cyber"
		r.Parent = Remotes
		Remote = r
	end
	CyberService.Remote = Remote

	table.insert(deps.DamageService.Modifiers, modifyDamage)
	table.insert(deps.DamageService.AfterDamage, afterDamage)
	deps.DamageService.KnockFilter = knockFilter
	deps.KnockService.PunchMod = punchMod
	deps.KnockService.BladeMod = bladeMod -- (v2.8.2) the blades cut when the arm hits
	if deps.NPCService then
		deps.NPCService.OnCyber = chromeNPC
		deps.NPCService.OnThink = npcThink
	end
	deps.GunService.OnShotLine = shotLine
	deps.DamageService.ImpactScale = function(model: Model): number
		local p = playerOf(model)
		if not p then
			return 1
		end
		if tierOf(p, "colossus") > 0 then
			return 0.1
		end
		local s = tierOf(p, "strider")
		return s > 0 and Config.StriderFall[s] or 1
	end
	-- a COLOSSUS shrugs off normal bullets (only the sniper, the M1, the minigun and the gunships hurt it)
	local prevBullet = deps.DamageService.ShieldBullet
	deps.DamageService.ShieldBullet = function(model: Model, region: string, point: Vector3, dir: Vector3, shooter: Player?, kind: string?)
		if prevBullet and prevBullet(model, region, point, dir, shooter, kind) then
			return true
		end
		if model:GetAttribute("Colossus") and not (kind == "sniper" or kind == "garand" or kind == "minigun" or kind == "jet" or kind == "heli") then
			fx("poof", { p = point, d = dir })
			pcall(deps.GoreService.Sound, "ricochet", point, 1)
			return true
		end
		return false
	end
	-- the Sandevistan from the item is remembered like every implant
	if deps.SandevistanService then
		deps.SandevistanService.OnImplanted = function(p: Player)
			local st = stOf(p)
			st.list.sandevistan = 1
			save(p)
			publish(p)
		end
	end

	Remote.OnServerEvent:Connect(function(p, action, a, b, c)
		local ch = p.Character
		local off = ch and ch:GetAttribute("ChipsDisabled")
		if ch and (ch:GetAttribute("TemporalFrozenUntil") or 0) > workspace:GetServerTimeNow() then return end
		if (action == "ab" or action == "armshot") and typeof(off) == "number" and off > workspace:GetServerTimeNow() then return end
		if action == "ab" then
			useAbility(p, a, b, c)
		elseif action == "armshot" then
			if typeof(a) == "string" and effective(stOf(p))[a] then
				armShot(p, a, b)
			end
		elseif action == "look" then
			if typeof(a) == "string" and typeof(b) == "string" and #b < 40 then
				setLook(p, a, b)
			end
		end
	end)

	-- the profile: implants come back
	local prevLoaded = Persist.OnLoaded
	Persist.OnLoaded = function(p, prof)
		if prevLoaded then
			prevLoaded(p, prof)
		end
		local st = stOf(p)
		for k, t in prof.cyber do
			local id = Cyberware.Split(k)
			if Cyberware.ById[id] and not st.list[k] then
				st.list[k] = t
			end
		end
		for k, v in prof.look do
			st.look[k] = v
		end
		publish(p)
		local char = alive(p)
		if char then
			applyBody(p, char)
		end
	end
	local prevSpawn = deps.CharacterService.OnSpawned
	deps.CharacterService.OnSpawned = function(p: Player, model: Model)
		if prevSpawn then
			prevSpawn(p, model)
		end
		if waitRig(model) and p.Character == model then
			applyBody(p, model)
		end
	end
	Players.PlayerAdded:Connect(function(p)
		stOf(p)
		publish(p)
	end)
	for _, p in Players:GetPlayers() do
		stOf(p)
		publish(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		states[p] = nil
		for _, st in states do
			if st.hunt == p then
				st.hunt = nil
			end
		end
	end)

	-- (v2.9) the admin "WIPE ALL PROGRESS": this player's implants come out (and are saved gone)
	function CyberService.Reset(p: Player)
		local st = stOf(p)
		st.list = {}
		st.look = {}
		st.psycho = 0
		st.gifted = {}
		st.hunt = nil
		local prof = Persist.Get(p)
		if prof then
			prof.cyber = {}
			prof.look = {}
			Persist.Dirty(p)
		end
		if deps.SandevistanService then
			deps.SandevistanService.Revoke(p)
		end
		p:SetAttribute("CyTolBonus", nil)
		p:SetAttribute("CyHunt", nil)
		publish(p)
		local char = alive(p)
		if char then
			applyBody(p, char)
		end
	end

	-- every second: the shield recharges, psychosis grows / fades, grabs count as touching
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = os.clock()
			for p, st in states do
				if not p.Parent then
					continue
				end
				local char = alive(p)
				local eff = effective(st)
				local a = Cyberware.Tier(eff, "aegis")
				if char and a > 0 and st.shield < Config.AegisShield[a] and now - st.lastHit > Config.AegisDelay[a] then
					st.shield = math.min(Config.AegisShield[a], st.shield + Config.AegisRate[a] * 0.5)
					char:SetAttribute("CyShield", math.floor(st.shield))
				end
				-- (v2.8) IRONHEART PUMP: healing sooner and faster, tier 3 closes open wounds
				local pu = Cyberware.Tier(eff, "pump")
				if char and pu > 0 then
					local quiet = now - (st.lastHurt or 0)
					if quiet > Config.PumpDelay[pu] then
						for _, region in { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" } do
							local hp = char:GetAttribute("HP_" .. region)
							if typeof(hp) == "number" and hp < Config.LimbMaxHP and hp > 0 and not char:GetAttribute("Broken_" .. region) then
								char:SetAttribute("HP_" .. region, math.min(Config.LimbMaxHP, hp + Config.PumpRegen[pu] * 0.5))
							end
						end
					end
					if pu >= 3 and quiet > Config.PumpClose and char:GetAttribute("Bleeding") then
						pcall(deps.DamageService.StopBleeding, char)
					end
				end
				-- psychosis
				if immune(p) then
					st.psycho = 0
				else
					local over = Cyberware.Load(st.list) - tolerance(p)
					if over > 0 then
						st.psycho = math.min(1, st.psycho + over * Config.PsychoRate * 0.5)
					else
						st.psycho = math.max(0, st.psycho - Config.PsychoDecay * 0.5)
					end
				end
				local shown = math.floor(st.psycho * 100 + 0.5) / 100
				if p:GetAttribute("CyPsycho") ~= shown then
					p:SetAttribute("CyPsycho", shown > 0 and shown or nil)
				end
				p:SetAttribute("CyLoad", immune(p) and 0 or Cyberware.Load(st.list))
				if char and st.psycho >= 0.7 then maybeCrash(p, "neural overload") end
				if char and st.psycho >= 0.2 then
					local by = char:GetAttribute("DraggedBy")
					if by ~= nil and by ~= false then
						maybeCrash(p, "touched")
					end
				end
				-- the hunt target left / died: keep it (it is a person, not a body)
				if st.hunt and not st.hunt.Parent then
					st.hunt = nil
					p:SetAttribute("CyHunt", nil)
				end
			end
		end
	end)
end

return CyberService
