--!nonstrict
-- FireFX: what fire looks like (client side, everybody sees it).
--   Patch(pos, radius, seconds): burning fuel on the ground - flames that lick up, smoke, a
--     flickering orange light, crackling, and a scorched spot that stays a while.
--   Bodies tagged "Burning" (by the server's FireService) have flames on every body part, a light
--     and a crackle until the tag goes away.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))
local Settings = require(Shared:WaitForChild("Settings"))

local FireFX = {}

local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local folder: Instance = workspace
local rng = Random.new()
FireFX.quality = 1 -- (settings: 0.35 with reduced effects)

local function ns(a: number, b: number, c: number?, d: number?): NumberSequence
	if c and d then
		return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(c, b), NumberSequenceKeypoint.new(1, d) })
	end
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

local FIRE_COLORS = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 140)),
	ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 140, 40)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 40, 20)),
})

local function flames(parent: Instance, rate: number, size: number, life: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Fire"
	e.Texture = TEX_FIRE
	e.Rate = rate * FireFX.quality
	e.Lifetime = NumberRange.new(life * 0.6, life)
	e.Speed = NumberRange.new(1.5, 4)
	e.SpreadAngle = Vector2.new(12, 12)
	e.Acceleration = Vector3.new(0, 9, 0)
	e.Drag = 1
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-90, 90)
	e.Size = ns(size, size * 0.15, 0.3, size * 1.1)
	e.Transparency = ns(0.25, 1, 0.6, 0.45)
	e.Color = FIRE_COLORS
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = parent
	return e
end

local function smoke(parent: Instance, rate: number, size: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Smoke"
	e.Texture = TEX_SMOKE
	e.Rate = rate * FireFX.quality
	e.Lifetime = NumberRange.new(2.5, 4)
	e.Speed = NumberRange.new(3, 6)
	e.SpreadAngle = Vector2.new(15, 15)
	e.Acceleration = Vector3.new(0.6, 2.5, 0)
	e.Drag = 0.6
	e.LightInfluence = 0.6
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-30, 30)
	e.Size = ns(size, size * 4)
	e.Transparency = ns(0.55, 1, 0.3, 0.6)
	e.Color = ColorSequence.new(Color3.fromRGB(40, 36, 34), Color3.fromRGB(90, 88, 86))
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Parent = parent
	return e
end

local function rig(cf: CFrame, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = "FireRig"
	p.Size = size
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = cf
	p.Parent = folder
	return p
end

function FireFX.Patch(pos: Vector3, radius: number, seconds: number, normal: Vector3?)
	local r = math.max(radius, 1)
	local p = rig(CFrame.new(pos + Vector3.new(0, 0.4, 0)), Vector3.new(r * 1.7, 0.6, r * 1.7))
	local f = flames(p, (18 + r * 9) * (Settings.Get("vfx") and 1 or 0.35), math.clamp(r * 0.55, 1.2, 4), 0.9)
	local f2 = flames(p, 8 + r * 3, math.clamp(r * 0.9, 2, 6), 1.3)
	f2.Transparency = ns(0.45, 1, 0.5, 0.6)
	local s = smoke(p, 3 + r * 0.8, math.clamp(r * 0.6, 1.5, 4))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 50)
	light.Range = math.clamp(r * 3.5, 10, 30)
	light.Brightness = 2.2
	light.Shadows = true
	light.Parent = p
	local snd = SoundLibrary.Loop("fireLoop", p)
	if snd then
		snd.Volume = 0.45
		snd:Play()
	end
	-- the scorched ground under it (stays a little longer)
	local scorch = Instance.new("Part")
	scorch.Name = "Scorch"
	scorch.Size = Vector3.new(r * 1.9, 0.05, r * 1.9)
	scorch.Color = Color3.fromRGB(20, 18, 16)
	scorch.Material = Enum.Material.Slate
	scorch.Transparency = 0.35
	scorch.Anchored = true
	scorch.CanCollide = false
	scorch.CanQuery = false
	scorch.CanTouch = false
	scorch.CastShadow = false
	-- lies flat on the ground or on the slope the fire burns on (the normal comes from the server)
	local up = (normal and normal.Magnitude > 0.5) and normal.Unit or Vector3.yAxis
	local spot = pos + up * (0.035 + rng:NextNumber(0, 0.01))
	scorch.CFrame = CFrame.lookAt(spot, spot + up) * CFrame.Angles(-math.pi / 2, 0, 0) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	scorch.Parent = folder
	-- flicker while it burns, then die down
	local t0 = os.clock()
	task.spawn(function()
		while p.Parent and os.clock() - t0 < seconds do
			light.Brightness = 1.6 + rng:NextNumber(0, 1.2)
			task.wait(0.08 + rng:NextNumber(0, 0.07))
		end
		if not p.Parent then
			return
		end
		f.Enabled = false
		f2.Enabled = false
		s.Rate = s.Rate * 0.4
		TweenService:Create(light, TweenInfo.new(1.2), { Brightness = 0 }):Play()
		if snd then
			TweenService:Create(snd, TweenInfo.new(1.2), { Volume = 0 }):Play()
		end
		task.wait(3)
		p:Destroy()
	end)
	task.delay(seconds + 20, function()
		if scorch.Parent then
			TweenService:Create(scorch, TweenInfo.new(4), { Transparency = 1 }):Play()
			Debris:AddItem(scorch, 4.5)
		end
	end)
end

------------------------------------------------------------------------
-- burning bodies
------------------------------------------------------------------------

local onBodies: { [Instance]: { Instance } } = {}

local function lightUp(body: Instance)
	if onBodies[body] or not body:IsA("Model") then
		return
	end
	local made = {}
	for _, n in { "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" } do
		local p = body:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			local e = flames(p, n == "Torso" and 30 or 14, n == "Torso" and 1.6 or 1, 0.7)
			table.insert(made, e)
		end
	end
	local torso = body:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		table.insert(made, smoke(torso, 4, 1.2))
		local light = Instance.new("PointLight")
		light.Name = "BurnLight"
		light.Color = Color3.fromRGB(255, 140, 50)
		light.Range = 14
		light.Brightness = 2
		light.Parent = torso
		table.insert(made, light)
		local snd = SoundLibrary.Loop("fireLoop", torso)
		if snd then
			snd.Volume = 0.35
			snd:Play()
			table.insert(made, snd)
		end
	end
	onBodies[body] = made
end

local function putOut(body: Instance)
	local made = onBodies[body]
	onBodies[body] = nil
	if made then
		for _, inst in made do
			if inst:IsA("ParticleEmitter") then
				inst.Enabled = false
				Debris:AddItem(inst, 2)
			else
				inst:Destroy()
			end
		end
	end
end

function FireFX.Init(fxFolder: Instance)
	folder = fxFolder
	CollectionService:GetInstanceAddedSignal("Burning"):Connect(lightUp)
	CollectionService:GetInstanceRemovedSignal("Burning"):Connect(putOut)
	for _, b in CollectionService:GetTagged("Burning") do
		lightUp(b)
	end
end

return FireFX
