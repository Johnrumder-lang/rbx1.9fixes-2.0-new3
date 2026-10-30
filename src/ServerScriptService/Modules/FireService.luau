--!nonstrict
-- FireService: fire on the ground and people on fire.
--   * Ignite(pos, radius, seconds): a patch of fire (molotov, flamethrower, a blown-up barrel).
--     Everybody draws the flames (FX "fire"); whoever stands in it catches fire, an explosive
--     barrel in it goes off after a few seconds.
--   * a burning body (tag "Burning") takes damage every moment and can set others on fire when
--     it touches them. Water puts it out at once; lying down (prone) and rolling puts it out faster.
--   * Molotov(bottle): the bottle shatters, burning fuel splashes around.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Water = require(Shared:WaitForChild("Water"))

local Modules = script.Parent
local DamageService = require(Modules:WaitForChild("DamageService"))
local GoreService = require(Modules:WaitForChild("GoreService"))

local FireService = {}

-- set by Main (avoids a require cycle): blows up an explosive barrel model
FireService.OnBarrel = nil :: ((Model, Player?) -> ())?

type Zone = { pos: Vector3, r: number, t0: number, life: number, attacker: Player? }
local zones: { Zone } = {}
local burning: { [Model]: { untilT: number, attacker: Player?, nextTick: number } } = {}
local barrelsLit: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

-- the ground under / near a point (fire lies on it): only ANCHORED surfaces count, so a fire (and the
-- scorch mark under it) never ends up floating on a body, a prop or a car. nil = no ground there.
local function groundAt(pos: Vector3): (Vector3?, Vector3?)
	local ignore = {}
	local fx = workspace:FindFirstChild("FX")
	if fx then
		table.insert(ignore, fx)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	for _ = 1, 10 do
		groundParams.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), groundParams)
		if not hit then
			return nil, nil
		end
		local inst = hit.Instance
		if inst:IsA("Terrain") or inst.Anchored then
			return hit.Position, hit.Normal
		end
		table.insert(ignore, inst)
	end
	return nil, nil
end

function FireService.Ignite(pos: Vector3, radius: number, seconds: number, attacker: Player?)
	-- (not on water)
	local d = Water.Depth(pos)
	if d and d > 0 then
		return
	end
	local g, n = groundAt(pos)
	if not g then
		return -- (nothing solid to burn on: no floating fires)
	end
	table.insert(zones, { pos = g, r = radius, t0 = os.clock(), life = seconds, attacker = attacker })
	while #zones > Config.FireMaxZones do
		table.remove(zones, 1)
	end
	GoreService.FX({ t = "fire", p = g, r = radius, l = seconds, n = n })
end

-- (the part names have spaces: v1.9 skipped the arms and legs)
local CHAR_REGIONS = { "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "Head" }
local charHeat: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any
local charShown: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any

-- the body parts of a burning body toast: skin colour -> coal black over Config.CharTime seconds
local function charBody(body: Model, dt: number)
	for _, region in CHAR_REGIONS do
		local part = body:FindFirstChild(region)
		if part and part:IsA("BasePart") then
			local base = part:GetAttribute("CharBase")
			if typeof(base) ~= "Color3" then
				base = part.Color
				part:SetAttribute("CharBase", base)
			end
			local h = math.min((charHeat[part] or 0) + dt, Config.CharTime)
			charHeat[part] = h
			local k = h / Config.CharTime
			if k - (charShown[part] or 0) >= 0.08 or (k >= 1 and (charShown[part] or 0) < 1) then
				charShown[part] = k
				part.Color = (base :: Color3):Lerp(Config.CharColor, k)
				if k >= 0.85 then
					-- (v2.0) the body card shows a burnt-black body part
					local rk = string.gsub(region, " ", "")
					body:SetAttribute("Charred_" .. rk, true)
				end
			end
		end
	end
end

function FireService.SetOnFire(body: Model, seconds: number, attacker: Player?)
	if body:GetAttribute("God") then
		return
	end
	local b = burning[body]
	local now = os.clock()
	if b then
		b.untilT = math.max(b.untilT, now + seconds)
		b.attacker = attacker or b.attacker
		return
	end
	burning[body] = { untilT = now + seconds, attacker = attacker, nextTick = now }
	CollectionService:AddTag(body, "Burning")
	local t = body:FindFirstChild("Torso")
	GoreService.Sound("ignite", (t and t:IsA("BasePart")) and t.Position or body:GetPivot().Position, 1)
	if attacker then
		DamageService.MarkAttacker(body, attacker)
	end
end

function FireService.Extinguish(body: Model)
	if burning[body] then
		burning[body] = nil
		CollectionService:RemoveTag(body, "Burning")
		local t = body:FindFirstChild("Torso")
		if t and t:IsA("BasePart") then
			GoreService.Sound("hiss", t.Position, 0.8)
		end
	end
end

function FireService.IsBurning(body: Model): boolean
	return burning[body] ~= nil
end

-- a molotov bottle breaks: burning fuel splashes around where it hit
function FireService.Molotov(bottle: Model?, pos: Vector3, attacker: Player?)
	if bottle and bottle.Parent then
		if bottle:GetAttribute("Broken") then
			return
		end
		bottle:SetAttribute("Broken", true)
		bottle:Destroy()
	end
	GoreService.Sound("glass", pos, 1)
	GoreService.Sound("fireWhoosh", pos, 1)
	FireService.Ignite(pos, Config.MolotovRadius, Config.MolotovTime, attacker)
	for i = 1, 3 do
		local a = i * 2.1 + math.random()
		local off = Vector3.new(math.cos(a), 0, math.sin(a)) * Config.MolotovRadius * (0.8 + math.random() * 0.5)
		FireService.Ignite(pos + off, Config.MolotovRadius * 0.55, Config.MolotovTime * (0.6 + math.random() * 0.3), attacker)
	end
	-- whoever was hit directly burns right away
	for body in DamageService.Bodies() do
		local t = body:FindFirstChild("Torso")
		if t and t:IsA("BasePart") and (t.Position - pos).Magnitude < Config.MolotovRadius * 0.8 then
			FireService.SetOnFire(body, Config.BurnTime, attacker)
		end
	end
end

local function horizontalIn(p: Vector3, z: Zone): boolean
	local d = p - z.pos
	return Vector3.new(d.X, 0, d.Z).Magnitude <= z.r and d.Y > -2 and d.Y < 5
end

local function tick(dt: number)
	local now = os.clock()
	-- old fires burn out
	for i = #zones, 1, -1 do
		if now - zones[i].t0 > zones[i].life then
			table.remove(zones, i)
		end
	end
	local bodies = DamageService.Bodies()
	-- standing in fire: you catch fire
	if #zones > 0 then
		for body, state in bodies do
			if state.dead or burning[body] then
				continue
			end
			local torso = body:FindFirstChild("Torso")
			local legs = body:FindFirstChild("Left Leg")
			local probe = (legs and legs:IsA("BasePart")) and legs.Position or (torso and torso:IsA("BasePart") and torso.Position)
			if not probe then
				continue
			end
			for _, z in zones do
				if horizontalIn(probe, z) then
					FireService.SetOnFire(body, Config.BurnTime, z.attacker)
					break
				end
			end
		end
		-- explosive barrels sitting in a fire go off after a while
		if FireService.OnBarrel then
			for _, z in zones do
				for _, p in workspace:GetPartBoundsInRadius(z.pos, z.r + 1) do
					local m = p:FindFirstAncestorOfClass("Model")
					if m and m:GetAttribute("Explosive") and not barrelsLit[m] and not m:GetAttribute("Exploded") then
						barrelsLit[m] = true
						local by = z.attacker
						task.delay(Config.FireBarrelDelay + math.random() * 1.5, function()
							if m.Parent and FireService.OnBarrel then
								FireService.OnBarrel(m, by)
							end
						end)
					end
				end
			end
		end
	end
	-- the burning
	for body, b in burning do
		local torso = body:FindFirstChild("Torso")
		if not body.Parent or not torso or not torso:IsA("BasePart") or now > b.untilT or body:GetAttribute("God") then
			FireService.Extinguish(body)
			continue
		end
		local depth = Water.Depth(torso.Position)
		if depth and depth > -0.5 then
			FireService.Extinguish(body) -- (jumped into the pool)
			continue
		end
		-- lying flat and rolling: it goes out faster
		if math.abs(torso.CFrame.UpVector.Y) < 0.4 and torso.AssemblyAngularVelocity.Magnitude > 3 then
			b.untilT -= dt * 2
		end
		-- every part that burns slowly turns coal black (living or dead; the heat stays on the part)
		charBody(body, dt)
		local state = bodies[body]
		if state and not state.dead then
			local regions = { "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Head" }
			local region = regions[math.random(1, #regions)]
			DamageService.ApplyDamage(body, region, Config.BurnDPS * dt, nil, {
				cause = b.attacker and ("Burned by " .. b.attacker.DisplayName) or "Burned to death",
				allowSever = false,
				quiet = true,
				attacker = b.attacker,
			})
			-- a burning body sets others on fire when it touches them
			for other, os2 in bodies do
				if other ~= body and not burning[other] and not os2.dead then
					local ot = other:FindFirstChild("Torso")
					if ot and ot:IsA("BasePart") and (ot.Position - torso.Position).Magnitude < 3.2 and math.random() < 0.5 * dt * 4 then
						FireService.SetOnFire(other, Config.BurnTime * 0.7, b.attacker)
					end
				end
			end
		end
	end
end

function FireService.Init()
	task.spawn(function()
		while true do
			local dt = task.wait(0.25)
			tick(dt)
		end
	end)
end

return FireService
