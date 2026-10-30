--!nonstrict
-- DummyService: limp ragdoll dummies to throw around, drop things on and dismember.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Modules = script.Parent
local RigBuilder = require(Modules:WaitForChild("RigBuilder"))
local BodyFactory = require(Modules:WaitForChild("BodyFactory"))
local DamageService = require(Modules:WaitForChild("DamageService"))
local ServerImpactSensor = require(Modules:WaitForChild("ServerImpactSensor"))

local DummyService = {}

local dummies: { Model } = {}

local function folder(): Folder
	local f = workspace:FindFirstChild("Dummies")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Dummies"
		f.Parent = workspace
	end
	return f :: Folder
end

function DummyService.Spawn(cf: CFrame, spawnerUserId: number?): Model
	local model = BodyFactory.BuildR6({ name = "Ragdoll Dummy", humanoid = false })
	RigBuilder.Build(model, { colliders = false, muscles = false })
	model:SetAttribute("IsDummy", true)
	if spawnerUserId then
		model:SetAttribute("Spawner", spawnerUserId)
	end
	model:PivotTo(cf)
	model.Parent = folder()
	DamageService.Register(model, {})
	ServerImpactSensor.Add(model)

	table.insert(dummies, model)
	model.Destroying:Connect(function()
		local i = table.find(dummies, model)
		if i then
			table.remove(dummies, i)
		end
	end)
	while #dummies > Config.MaxDummies do
		local old = table.remove(dummies, 1)
		if old then
			old:Destroy()
		end
	end
	return model
end

function DummyService.Init()
	-- one dummy waiting next to the spawn
	local marker = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("DummySpawn")
	local cf = (marker and marker:IsA("BasePart")) and (marker.CFrame + Vector3.new(0, 3.5, 0)) or CFrame.new(10, 4, -6)
	DummyService.Spawn(cf)
end

return DummyService
