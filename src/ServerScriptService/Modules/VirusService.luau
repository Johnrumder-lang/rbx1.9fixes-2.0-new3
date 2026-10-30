--!nonstrict
-- VirusService: the virus bottle (game owner only). Smash it and a green cloud comes out.
--   * whoever breathes the cloud is infected; after a few seconds the symptoms start
--   * it spreads: standing close to a sick body (alive or dead, player, dummy or NPC), being
--     sneezed at, stepping into the vomit or the blood of a sick body
--   * symptoms: sneezing, vomiting, tumbling over, hallucinations (on the sick player's own
--     screen, see the client's Hallucinations), slowly losing health
--   * a heal dart cures it (and makes the body immune for a while)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))

local Modules = script.Parent
local DamageService = require(Modules:WaitForChild("DamageService"))
local GoreService = require(Modules:WaitForChild("GoreService"))
local OwnershipService = require(Modules:WaitForChild("OwnershipService"))

local VirusService = {}

type Sick = { t0: number, nextSymptom: number, by: Player?, lastBlood: number }
local sick: { [Model]: Sick } = {}
-- places the virus lingers: clouds, vomit, blood
local spots: { { p: Vector3, r: number, untilT: number, chance: number } } = {}
local rng = Random.new()

local function torsoOf(m: Model): BasePart?
	local t = m:FindFirstChild("Torso")
	return (t and t:IsA("BasePart")) and t or nil
end

local function immune(m: Model): boolean
	local t = m:GetAttribute("ImmuneUntil")
	return typeof(t) == "number" and workspace:GetServerTimeNow() < t
end

function VirusService.IsSick(m: Model): boolean
	return sick[m] ~= nil
end

function VirusService.Infect(m: Model, by: Player?, cyberAttack: boolean?)
	if sick[m] or immune(m) or not DamageService.Get(m) or (m:GetAttribute("God") and not cyberAttack) then
		return
	end
	if m:GetAttribute("CyLungs") == 0 then
		return -- (v2.8) DEEPWATER LUNGS tier 3 filter it out
	end
	sick[m] = { t0 = os.clock(), nextSymptom = os.clock() + Config.VirusIncubation + rng:NextNumber(0, 3), by = by, lastBlood = 0 }
	m:SetAttribute("Infected", true)
end

function VirusService.Cure(m: Model)
	if not sick[m] then
		return
	end
	sick[m] = nil
	m:SetAttribute("Infected", nil)
	m:SetAttribute("Sick", nil)
	m:SetAttribute("ImmuneUntil", workspace:GetServerTimeNow() + 60)
end

local function addSpot(p: Vector3, r: number, life: number, chance: number)
	table.insert(spots, { p = p, r = r, untilT = os.clock() + life, chance = chance })
	while #spots > 60 do
		table.remove(spots, 1)
	end
end

-- the bottle broke here
function VirusService.Smash(pos: Vector3, by: Player?)
	GoreService.FX({ t = "virusCloud", p = pos, r = Config.VirusCloudRadius, d = Config.VirusCloudTime })
	GoreService.Sound("glass", pos, 1)
	addSpot(pos, Config.VirusCloudRadius, Config.VirusCloudTime, 0.9)
	-- right in the burst: infected at once
	for m in DamageService.Bodies() do
		local t = torsoOf(m)
		if t and (t.Position - pos).Magnitude < Config.VirusCloudRadius * 0.5 then
			VirusService.Infect(m, by)
		end
	end
end

local function smashBottle(bottle: Model, by: Player?)
	if bottle:GetAttribute("Smashed") or not bottle.PrimaryPart then
		return
	end
	bottle:SetAttribute("Smashed", true)
	local pos = bottle.PrimaryPart.Position
	OwnershipService.DropItem(bottle)
	bottle:Destroy()
	VirusService.Smash(pos, by)
end
VirusService.SmashBottle = smashBottle

local function symptom(m: Model, s: Sick)
	local t = torsoOf(m)
	if not t then
		return
	end
	local head = m:FindFirstChild("Head")
	local headPos = (head and head:IsA("BasePart")) and head.Position or (t.Position + Vector3.new(0, 1.5, 0))
	local look = t.CFrame.LookVector
	local r = rng:NextNumber()
	local kind = r < 0.4 and "sneeze" or (r < 0.75 and "barf" or "tumble")
	GoreService.FX({ t = "symptom", k = kind, body = m })
	if kind == "sneeze" then
		-- a cone in front of the face
		for other in DamageService.Bodies() do
			local ot = other ~= m and torsoOf(other)
			if ot then
				local to = ot.Position - headPos
				if to.Magnitude < 7 and to.Unit:Dot(look) > 0.4 and rng:NextNumber() < 0.65 then
					VirusService.Infect(other, s.by)
				end
			end
		end
	elseif kind == "barf" then
		DamageService.ApplyDamage(m, "Torso", 3, nil, { cause = "Virus", allowSever = false, quiet = true, attacker = s.by })
		local spotPos = headPos + look * 2.5 + Vector3.new(0, -4, 0)
		task.delay(1.2, addSpot, spotPos, 3.2, 45, Config.VirusBloodChance)
	else
		local dir = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
		dir = dir.Magnitude > 0.1 and dir.Unit or look
		DamageService.Knock(m, "Torso", dir * 8 * DamageService.PartMass(m, "Torso"), rng:NextNumber(1.2, 2.2))
	end
end

local function tick()
	local now = os.clock()
	for i = #spots, 1, -1 do
		if now > spots[i].untilT then
			table.remove(spots, i)
		end
	end
	local bodies = {}
	for m, state in DamageService.Bodies() do
		local t = m.Parent and torsoOf(m)
		if t then
			table.insert(bodies, { m = m, t = t, dead = state.dead })
		end
	end
	-- spreading
	for _, b in bodies do
		if sick[b.m] or b.dead or immune(b.m) then
			continue
		end
		local by: Player? = nil
		local chance = 0
		for _, sp in spots do
			if (b.t.Position - sp.p).Magnitude < sp.r then
				chance = math.max(chance, sp.chance)
			end
		end
		for _, o in bodies do
			local s = sick[o.m]
			if s and now - s.t0 > 2 then
				local d = (o.t.Position - b.t.Position).Magnitude
				if d < Config.VirusSpreadRadius then
					chance = math.max(chance, Config.VirusSpreadChance * (1.6 - d / Config.VirusSpreadRadius))
					by = s.by
				end
			end
		end
		if chance > 0 and rng:NextNumber() < chance then
			VirusService.Infect(b.m, by)
		end
	end
	-- the sick
	for m, s in sick do
		local t = m.Parent and torsoOf(m)
		local state = DamageService.Get(m)
		if not t or not state then
			sick[m] = nil
			continue
		end
		if now - s.t0 > Config.VirusDuration and not state.dead then
			VirusService.Cure(m)
			continue
		end
		-- their blood carries it too
		if m:GetAttribute("Bleeding") and now - s.lastBlood > 2 then
			s.lastBlood = now
			addSpot(t.Position - Vector3.new(0, 2.5, 0), 3, 30, Config.VirusBloodChance)
		end
		if state.dead or now - s.t0 < Config.VirusIncubation then
			continue
		end
		if not m:GetAttribute("Sick") then
			m:SetAttribute("Sick", true)
		end
		DamageService.ApplyDamage(m, "Torso", Config.VirusDPS, nil, { cause = "Virus", allowSever = false, quiet = true, attacker = s.by })
		if now >= s.nextSymptom then
			s.nextSymptom = now + rng:NextNumber(Config.VirusSymptomGap[1], Config.VirusSymptomGap[2])
			symptom(m, s)
		end
	end
end

function VirusService.Init()
	DamageService.OnHeal = VirusService.Cure
	task.spawn(function()
		while true do
			task.wait(1)
			tick()
		end
	end)
	-- a bottle that hits something hard breaks
	local last: { [Model]: number } = {}
	RunService.Heartbeat:Connect(function()
		local f = workspace:FindFirstChild("SpawnedProps")
		if not f then
			return
		end
		for _, m in f:GetChildren() do
			if m:IsA("Model") and Items.Kind(m) == "virus" and m.PrimaryPart and not m:GetAttribute("HolderId") then
				local v = m.PrimaryPart.AssemblyLinearVelocity.Magnitude
				if (last[m] or 0) - v > 22 then
					local id = m:GetAttribute("LastHolder")
					local by = nil
					for _, p in game:GetService("Players"):GetPlayers() do
						if p.UserId == id then
							by = p
						end
					end
					smashBottle(m, by)
				end
				last[m] = v
			end
		end
		for m in last do
			if not m.Parent then
				last[m] = nil
			end
		end
	end)
end

return VirusService
