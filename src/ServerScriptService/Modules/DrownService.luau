--!nonstrict
-- DrownService: the pool. Every body with its head under water counts up; after a while it starts
-- to drown (the torso takes damage until it dies). Coming up resets the count quickly. Falling into
-- the water makes a splash.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Water = require(Shared:WaitForChild("Water"))

local Modules = script.Parent
local DamageService = require(Modules:WaitForChild("DamageService"))
local GoreService = require(Modules:WaitForChild("GoreService"))

local DrownService = {}

-- (v2.0) a body just went into the water (the sea map puts an island near it)
DrownService.OnEnterWater = nil :: ((Model, Vector3) -> ())?

local under: { [Model]: number } = {}
local wasIn: { [Model]: boolean } = {}

local function tick(dt: number)
	if #Water.Volumes() == 0 then
		return
	end
	for model, state in DamageService.Bodies() do
		local head = model:FindFirstChild("Head")
		local torso = model:FindFirstChild("Torso")
		if not torso or not torso:IsA("BasePart") then
			continue
		end
		-- a splash when a body falls in
		local tDepth = Water.Depth(torso.Position)
		local isIn = tDepth ~= nil and tDepth > 0
		if isIn and not wasIn[model] then
			if DrownService.OnEnterWater then
				task.spawn(DrownService.OnEnterWater, model, torso.Position)
			end
			local v = torso.AssemblyLinearVelocity
			if v.Y < -12 then
				local surf = Water.SurfaceAt(torso.Position) or torso.Position.Y
				GoreService.FX({ t = "splash", p = Vector3.new(torso.Position.X, surf, torso.Position.Z), s = math.clamp(-v.Y / 60, 0.3, 1.5) })
				GoreService.Sound("splash", Vector3.new(torso.Position.X, surf, torso.Position.Z), math.clamp(-v.Y / 50, 0.4, 1.2))
			end
		end
		wasIn[model] = isIn or nil
		if state.dead or not head or not head:IsA("BasePart") then
			under[model] = nil
			continue
		end
		local d = Water.Depth(head.Position)
		if d and d > 0.25 then
			local t = (under[model] or 0) + dt
			under[model] = t
			-- (v2.8) DEEPWATER LUNGS: twice / four times the breath, or no drowning at all (0)
			local lungs = model:GetAttribute("CyLungs")
			local breath = Config.DrownTime * ((typeof(lungs) == "number" and lungs > 0) and lungs or 1)
			if typeof(lungs) == "number" and lungs == 0 then
				breath = math.huge
			end
			if t > breath then
				DamageService.ApplyDamage(model, "Torso", Config.DrownDPS * dt, nil, {
					cause = "Drowned",
					allowSever = false,
					quiet = true,
				})
			end
		elseif under[model] then
			local t = under[model] - dt * 4
			under[model] = t > 0 and t or nil
		end
	end
	for m in under do
		if not m.Parent then
			under[m] = nil
		end
	end
	for m in wasIn do
		if not m.Parent then
			wasIn[m] = nil
		end
	end
end

function DrownService.Init()
	task.spawn(function()
		while true do
			local dt = task.wait(0.25)
			tick(dt)
		end
	end)
end

return DrownService
