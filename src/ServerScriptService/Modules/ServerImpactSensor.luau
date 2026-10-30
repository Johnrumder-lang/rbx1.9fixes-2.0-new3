--!nonstrict
-- ServerImpactSensor: impacts, object hits, spikes and crushing for bodies the server simulates
-- (dummies, corpses). Player characters are sensed on their owning client.
-- Also launches these bodies on drop pads.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))
local ContactSolver = require(Shared:WaitForChild("ContactSolver"))

local DamageService = require(script.Parent:WaitForChild("DamageService"))

local Sensor = {}

type Track = { part: BasePart, region: string, hist: { { t: number, v: Vector3 } }, cooldown: number }
type Body = { tracks: { Track }, cache: any, params: OverlapParams, crushTimer: number, dropCooldown: number }
local bodies: { [Model]: Body } = {}

function Sensor.Add(model: Model)
	local list = {}
	for partName, region in RigInfo.PartRegion do
		if region == "Head" then
			continue -- head shares the torso assembly; classified from torso hits
		end
		local p = model:FindFirstChild(partName)
		if p and p:IsA("BasePart") then
			table.insert(list, { part = p, region = region, hist = {}, cooldown = 0 })
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	bodies[model] = { tracks = list, cache = ContactSolver.NewVelocityCache(), params = params, crushTimer = 0, dropCooldown = 0 }
	model.Destroying:Connect(function()
		bodies[model] = nil
	end)
end

function Sensor.Remove(model: Model)
	bodies[model] = nil
end

local function bodyMass(model: Model): number
	local m = 0
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and RigInfo.PartRegion[d.Name] then
			m += d.Mass
		end
	end
	return math.max(m, 1)
end

local downParams = RaycastParams.new()
downParams.FilterType = Enum.RaycastFilterType.Exclude

local function checkDropPad(model: Model, body: Body, now: number)
	if now < body.dropCooldown then
		return
	end
	local torso = model:FindFirstChild("Torso") :: BasePart?
	if not torso then
		return
	end
	downParams.FilterDescendantsInstances = { model }
	local hit = workspace:Raycast(torso.Position, Vector3.new(0, -3.2, 0), downParams)
	local h = hit and hit.Instance:GetAttribute("DropHeight")
	if typeof(h) ~= "number" then
		return
	end
	-- held by a player? then that player's client owns it; leave it alone
	local ok, owner = pcall(function()
		return torso:GetNetworkOwner()
	end)
	if ok and owner ~= nil then
		return
	end
	body.dropCooldown = now + 3
	model:PivotTo(model:GetPivot() + Vector3.new(0, h, 0))
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.AssemblyLinearVelocity = Vector3.zero
			p.AssemblyAngularVelocity = Vector3.zero
		end
	end
	for _, tr in body.tracks do
		table.clear(tr.hist)
	end
end

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for model, body in bodies do
		if not model.Parent then
			bodies[model] = nil
			continue
		end
		local torso = model:FindFirstChild("Torso") :: BasePart?
		if torso then
			body.cache:Track(torso.Position, 8, body.params)
		end
		local mass = bodyMass(model)

		for _, tr in body.tracks do
			local p = tr.part
			if not p.Parent or model:GetAttribute("Severed_" .. tr.region) then
				continue
			end
			local v = p.AssemblyLinearVelocity
			local hist = tr.hist
			table.insert(hist, { t = now, v = v })
			while #hist > 5 do
				table.remove(hist, 1)
			end
			if now < tr.cooldown then
				continue
			end
			local best, bestV = 0, nil
			for i = 1, #hist - 1 do
				local h = hist[i]
				if now - h.t <= 0.07 then
					local d = (v - h.v).Magnitude
					if d > best then
						best, bestV = d, h.v
					end
				end
			end
			if best >= 12 and bestV then
				local region, point = tr.region, nil
				if region == "Torso" then
					region, point = RigInfo.ClassifyTorsoHit(p.CFrame, bestV)
				else
					point = RigInfo.LeadingPoint(p.CFrame, p.Size, bestV)
				end
				local result = ContactSolver.Solve(point, bestV, best, mass, body.cache, body.params)
				if result then
					tr.cooldown = now + Config.ImpactCooldown
					if result.kind == "pierce" and result.other then
						DamageService.ApplyPierce(model, region, result.value, result.sharpness or 0, result.other, point)
					elseif result.kind == "energy" then
						DamageService.ApplyEnergy(model, region, result.value, point, nil, result.other)
					else
						DamageService.ApplyImpact(model, region, result.value, point)
					end
				end
			end
		end

		body.crushTimer += dt
		if body.crushTimer >= 0.25 then
			local step = body.crushTimer
			body.crushTimer = 0
			for _, tr in body.tracks do
				local p = tr.part
				if p.Parent and not model:GetAttribute("Severed_" .. tr.region) then
					local dps = ContactSolver.Crush(p, body.params, body.cache)
					if dps > 0 then
						DamageService.ApplyCrush(model, tr.region, dps * step, p.Position + Vector3.new(0, p.Size.Y * 0.4, 0))
					end
				end
			end
			checkDropPad(model, body, now)
		end
	end
end)

return Sensor
