--!nonstrict
-- ExplosionFX: explosions built from real particle effects (client side, everybody sees them).
--
--   Boom   : flash + flickering light, a fireball of flame particles that blooms and cools, fire
--            tongues, thick smoke that rolls up and drifts away, spark streaks with gravity, floating
--            embers, a dust ring blown out along the ground, a heat shell, ground chunks with smoke
--            trails (some burning), a scorch mark with glowing embers, small fires that keep burning,
--            camera blur / shake, ear ringing up close and the bang arriving late far away.
--            Kinds change the mix: "barrel" (oily black smoke, more fire), "c4" (sharp, lots of
--            dust), "grenade" (fragments), "rocket", "car".
--   Flash  : the flash grenade (a white burst, sparks, a little smoke; the blinding is in the HUD)
--   Nuke   : fireball, a mushroom cloud made of thousands of particles (stem, head, rolling cap),
--            base surge along the ground and a shockwave that throws up a wall of dust as it passes.
--
--   Textures: the engine's own flame / smoke / spark textures. To use a flipbook explosion texture
--   from the Creator Store instead, set Config.ExplosionFlipbook = { texture = "rbxassetid://...",
--   layout = "Grid4x4" | "Grid8x8", fps = 30 }.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))
local Settings = require(Shared:WaitForChild("Settings"))
local Ground = require(Shared:WaitForChild("Ground"))

local player = Players.LocalPlayer

local ExplosionFX = {}

local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local rng = Random.new()
local folder: Instance = workspace
local rayParams: RaycastParams = RaycastParams.new()
local onShake: ((number) -> ())? = nil

function ExplosionFX.Setup(fxFolder: Instance, params: RaycastParams, shake: (number) -> ())
	folder = fxFolder
	rayParams = params
	onShake = shake
end

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------

-- ns(0, a, 0.4, b, 1, c) -> NumberSequence
local function ns(...: number): NumberSequence
	local a = { ... }
	local kps = {}
	for i = 1, #a, 2 do
		table.insert(kps, NumberSequenceKeypoint.new(a[i], math.max(0, a[i + 1])))
	end
	return NumberSequence.new(kps)
end

-- cs(0, color, 0.5, color, 1, color) -> ColorSequence
local function cs(...: any): ColorSequence
	local a = { ... }
	local kps = {}
	for i = 1, #a, 2 do
		table.insert(kps, ColorSequenceKeypoint.new(a[i], a[i + 1]))
	end
	return ColorSequence.new(kps)
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function anchor(cf: CFrame, life: number): (BasePart, Attachment)
	local p = Instance.new("Part")
	p.Name = "BoomRig"
	p.Size = Vector3.one
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = cf
	p.Parent = folder
	local a = Instance.new("Attachment")
	a.Parent = p
	Debris:AddItem(p, life)
	return p, a
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.LightInfluence = 0
	e.EmissionDirection = Enum.NormalId.Top
	e.Rotation = NumberRange.new(0, 360)
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

-- optional flipbook texture for the fireball (see the top of the file)
local function flipbook(e: ParticleEmitter)
	local fb = (Config :: any).ExplosionFlipbook
	if typeof(fb) ~= "table" or typeof(fb.texture) ~= "string" then
		return
	end
	pcall(function()
		e.Texture = fb.texture
		e.FlipbookLayout = fb.layout == "Grid8x8" and Enum.ParticleFlipbookLayout.Grid8x8
			or (fb.layout == "Grid2x2" and Enum.ParticleFlipbookLayout.Grid2x2 or Enum.ParticleFlipbookLayout.Grid4x4)
		e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
		e.FlipbookFramerate = NumberRange.new(fb.fps or 30)
		e.RotSpeed = NumberRange.new(0)
	end)
end

local function randomUnit(): Vector3
	local v = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
	return v.Magnitude > 0.01 and v.Unit or Vector3.yAxis
end

-- emit `per` particles in each of `n` directions around the up axis (flat fan, slightly up)
local function radial(att: Attachment, e: ParticleEmitter, n: number, per: number, lift: number)
	local base = att.WorldPosition
	for i = 1, n do
		local a = (i / n) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local dir = Vector3.new(math.cos(a), lift, math.sin(a)).Unit
		att.WorldCFrame = CFrame.lookAt(base, base + dir)
		e:Emit(per)
	end
	att.WorldCFrame = CFrame.new(base)
end

local function flicker(light: PointLight, brightness: number, range: number, duration: number)
	task.spawn(function()
		local t0 = os.clock()
		while light.Parent do
			local k = (os.clock() - t0) / duration
			if k >= 1 then
				break
			end
			light.Brightness = brightness * (1 - k) ^ 2 * rng:NextNumber(0.7, 1.1)
			light.Range = range * (1 - k * 0.4)
			RunService.Heartbeat:Wait()
		end
		light:Destroy()
	end)
end

local function postFX(strength: number, duration: number, warm: boolean)
	if strength <= 0.02 then
		return
	end
	local blur = Instance.new("BlurEffect")
	blur.Name = "BoomBlur"
	blur.Size = 16 * strength
	blur.Parent = Lighting
	TweenService:Create(blur, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = 0 }):Play()
	Debris:AddItem(blur, duration + 0.1)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "BoomCC"
	cc.Brightness = 0.35 * strength
	cc.Contrast = 0.15 * strength
	cc.TintColor = warm and rgb(255, 222, 190) or rgb(255, 255, 255)
	cc.Parent = Lighting
	TweenService:Create(cc, TweenInfo.new(duration * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) }):Play()
	Debris:AddItem(cc, duration)
end

local function cameraDistance(pos: Vector3): number
	local cam = workspace.CurrentCamera
	return cam and (cam.CFrame.Position - pos).Magnitude or 1e4
end

-- the sound of a bang travels: far away it comes late and low
local function distantBang(pos: Vector3, dist: number, scale: number)
	if dist < 140 then
		return
	end
	task.delay(math.min(dist / 1100, 2.5), function()
		SoundLibrary.Play("boomFar", nil, math.clamp(scale * (1.2 - dist / 2500), 0.15, 1))
	end)
end

------------------------------------------------------------------------
-- a normal explosion
------------------------------------------------------------------------

-- (v2.8) many explosions at once (a chain of barrels, a bomb run, a nuke): each one draws less, the far ones least
local recentBooms: { number } = {}
local function crowd(): (number, number)
	local now = os.clock()
	for i = #recentBooms, 1, -1 do
		if now - recentBooms[i] > 2 then
			table.remove(recentBooms, i)
		end
	end
	table.insert(recentBooms, now)
	local n = #recentBooms
	return math.clamp(1 / (1 + 0.4 * math.max(0, n - 1)), 0.25, 1), n
end

function ExplosionFX.Boom(pos: Vector3, radius: number, kind: string?)
	local crowdK, crowdN = crowd()
	if not Settings.Get("vfx") then
		-- big effects switched off in the settings: a small puff, the flash and the shake
		ExplosionFX.Small(pos, Vector3.yAxis)
		if onShake then
			onShake(math.clamp(radius / 30, 0.2, 1.2) * math.clamp(1 - cameraDistance(pos) / (radius * 8), 0, 1))
		end
		return
	end
	local r = math.max(radius, 4)
	local fb = math.clamp(r * 0.3, 3, 14) -- fireball radius
	local dist = cameraDistance(pos)
	local oily = kind == "barrel" or kind == "car"
	local sharp = kind == "c4"
	local lod = (dist > 600 and 0.4 or (dist > 250 and 0.7 or 1)) * crowdK -- fewer particles far away (and in a crowd of blasts)

	local hit = Ground.Cast(pos + Vector3.new(0, 1, 0), Vector3.new(0, -(fb * 1.6 + 2), 0), rayParams)
	local onGround = hit ~= nil
	local groundPos = hit and hit.Position or pos
	local groundCol = hit and hit.Instance.Color or rgb(130, 120, 108)
	local center = onGround and Vector3.new(pos.X, math.max(pos.Y, groundPos.Y + fb * 0.3), pos.Z) or pos
	local rigPart, att = anchor(CFrame.new(center), 10)

	-- 1. the flash: a soft white-hot glow for a split second + a light that flickers out
	local flash = emitter(att, {
		Texture = TEX_SMOKE,
		Color = cs(0, rgb(255, 255, 240), 1, rgb(255, 210, 140)),
		Size = ns(0, fb * 2.2, 1, fb * 3.4),
		Transparency = ns(0, 0, 1, 1),
		Lifetime = NumberRange.new(0.12, 0.18),
		Speed = NumberRange.new(0),
		LightEmission = 1,
		Brightness = 6,
		ZOffset = 4,
	})
	flash:Emit(3)
	local light = Instance.new("PointLight")
	light.Color = oily and rgb(255, 150, 70) or rgb(255, 180, 100)
	light.Shadows = true
	light.Parent = rigPart
	flicker(light, 18, math.min(60, r * 2.6), oily and 2.2 or 1.3)

	-- 2. the fireball: flame particles shoot out, slow down hard, swell and cool from white to soot
	local fire = emitter(att, {
		Texture = TEX_FIRE,
		Color = cs(0, rgb(255, 250, 225), 0.12, rgb(255, 214, 120), 0.35, rgb(255, 140, 40), 0.65, rgb(200, 60, 18), 1, rgb(50, 30, 22)),
		Size = ns(0, fb * 0.45, 0.25, fb * 1.05, 1, fb * 0.7),
		Transparency = ns(0, 0, 0.55, 0.15, 1, 1),
		Lifetime = NumberRange.new(0.4, oily and 1.1 or 0.8),
		Speed = NumberRange.new(fb * 1.6, fb * 4.2),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 7,
		Acceleration = Vector3.new(0, fb * 2.2, 0),
		RotSpeed = NumberRange.new(-140, 140),
		LightEmission = 0.85,
		Brightness = 3,
		ZOffset = 1,
	})
	flipbook(fire)
	fire:Emit(math.floor((oily and 46 or 36) * lod))
	-- fire tongues that roll up out of it
	local tongues = emitter(att, {
		Texture = TEX_FIRE,
		Color = cs(0, rgb(255, 200, 100), 0.4, rgb(255, 110, 30), 1, rgb(70, 30, 20)),
		Size = ns(0, fb * 0.5, 0.5, fb * 0.75, 1, 0),
		Transparency = ns(0, 0.1, 1, 1),
		Lifetime = NumberRange.new(0.8, 1.5),
		Speed = NumberRange.new(fb * 0.4, fb * 1.4),
		SpreadAngle = Vector2.new(60, 60),
		Acceleration = Vector3.new(0, fb * 3.2, 0),
		Drag = 2,
		RotSpeed = NumberRange.new(-60, 60),
		LightEmission = 0.8,
		Brightness = 2,
	})
	tongues:Emit(math.floor((oily and 24 or 14) * lod))

	-- 3. smoke: thick, rolls up, spreads and slowly turns lighter (oil fires: black)
	local smokeDark = oily and rgb(24, 22, 22) or (sharp and rgb(92, 88, 82) or rgb(58, 52, 48))
	local smokeLight = oily and rgb(60, 58, 58) or rgb(128, 122, 116)
	local smoke = emitter(att, {
		Texture = TEX_SMOKE,
		Color = cs(0, rgb(90, 60, 40), 0.15, smokeDark, 1, smokeLight),
		Size = ns(0, fb * 0.8, 0.4, fb * 1.9, 1, fb * 2.9),
		Transparency = ns(0, 0.1, 0.6, 0.45, 1, 1),
		Lifetime = NumberRange.new(3.5, 6.5),
		Speed = NumberRange.new(fb * 0.7, fb * 2.4),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 1.7,
		Acceleration = Vector3.new(rng:NextNumber(-1, 1), fb * 0.55, rng:NextNumber(-1, 1)),
		RotSpeed = NumberRange.new(-25, 25),
		LightInfluence = 1,
		ZOffset = -1,
	})
	task.delay(0.05, function()
		if smoke.Parent then
			smoke:Emit(math.floor((oily and 34 or 24) * lod))
			-- a little more keeps coming out for a moment
			smoke.Rate = (oily and 14 or 7) * lod
			task.delay(oily and 3 or 1.4, function()
				smoke.Rate = 0
			end)
		end
	end)

	-- 4. spark streaks (stretched along their flight) and floating embers
	local sparks = emitter(att, {
		Texture = TEX_SPARK,
		Color = cs(0, rgb(255, 236, 170), 1, rgb(255, 110, 30)),
		Size = ns(0, 0.45, 1, 0),
		Transparency = ns(0, 0, 0.8, 0.2, 1, 1),
		Lifetime = NumberRange.new(0.5, 1.5),
		Speed = NumberRange.new(r * 1.8, r * 4.5),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -workspace.Gravity * 0.55, 0),
		Drag = 1.1,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = ns(0, 2.4, 1, 1.2),
		LightEmission = 1,
		Brightness = 5,
	})
	sparks:Emit(math.floor((kind == "grenade" and 70 or 45) * lod))
	local embers = emitter(att, {
		Texture = TEX_FIRE,
		Color = cs(0, rgb(255, 190, 90), 1, rgb(255, 70, 20)),
		Size = ns(0, 0.35, 1, 0),
		Transparency = ns(0, 0, 1, 1),
		Lifetime = NumberRange.new(2, 4.5),
		Speed = NumberRange.new(math.min(4, r * 0.9), math.max(4, r * 0.9)), -- (v2.8 fix: a small blast had min > max: "invalid range")
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 3, 0),
		Drag = 1.5,
		LightEmission = 1,
		Brightness = 3,
	})
	embers:Emit(math.floor(24 * lod))

	-- 5. the pressure wave: a heat shell and a ring of dust blown out along the ground
	local shell = Instance.new("Part")
	shell.Name = "HeatShell"
	shell.Shape = Enum.PartType.Ball
	shell.Material = Enum.Material.ForceField
	shell.Color = rgb(255, 238, 215)
	shell.Size = Vector3.one * 2
	shell.Transparency = 0.15
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.CastShadow = false
	shell.CFrame = CFrame.new(center)
	shell.Parent = folder
	TweenService:Create(shell, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * r * 2.4, Transparency = 1 }):Play()
	Debris:AddItem(shell, 0.4)
	if onGround and (pos.Y - groundPos.Y) < r * 0.6 then
		local _, gAtt = anchor(CFrame.new(groundPos + Vector3.new(0, 0.6, 0)), 5)
		local dust = emitter(gAtt, {
			Texture = TEX_SMOKE,
			Color = cs(0, groundCol:Lerp(rgb(160, 150, 130), 0.55), 1, groundCol:Lerp(rgb(190, 184, 170), 0.7)),
			Size = ns(0, 1.5, 0.3, fb * 1.1, 1, fb * 1.9),
			Transparency = ns(0, 0.25, 0.5, 0.5, 1, 1),
			Lifetime = NumberRange.new(1.2, 2.6),
			Speed = NumberRange.new(r * 1.1, r * 2.3),
			SpreadAngle = Vector2.new(6, 6),
			EmissionDirection = Enum.NormalId.Front,
			Drag = 3.2,
			Acceleration = Vector3.new(0, 2, 0),
			RotSpeed = NumberRange.new(-30, 30),
			LightInfluence = 1,
		})
		radial(gAtt, dust, math.floor((sharp and 30 or 22) * lod), 2, 0.08)
		-- a flat haze ring racing outwards
		local haze = emitter(gAtt, {
			Texture = TEX_SMOKE,
			Color = cs(0, rgb(255, 250, 240), 1, rgb(255, 250, 240)),
			Size = ns(0, 1, 1, r * 2.6),
			Transparency = ns(0, 0.55, 1, 1),
			Lifetime = NumberRange.new(0.4),
			Speed = NumberRange.new(0.05),
			SpreadAngle = Vector2.new(0, 0),
			Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
			LightInfluence = 1,
		})
		haze:Emit(1)

		-- chunks of the ground fly away, trailing smoke; some burn
		local nChunks = crowdN >= 4 and 0 or math.floor((sharp and 18 or 12) * lod)
		for i = 1, nChunks do
			local s = rng:NextNumber(0.25, 0.75)
			local d = Instance.new("Part")
			d.Name = "Debris"
			d.Size = Vector3.new(s, s * rng:NextNumber(0.4, 1), s * rng:NextNumber(0.7, 1.2))
			d.Color = groundCol:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0.15, 0.55))
			d.Material = hit and hit.Material or Enum.Material.Slate
			d.CanQuery = false
			d.CanTouch = false
			d.CFrame = CFrame.new(groundPos + Vector3.new(0, 0.8, 0)) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
			d.Parent = folder
			d.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.6, 1.7), rng:NextNumber(-1, 1)).Unit * rng:NextNumber(30, 90)
			d.AssemblyAngularVelocity = randomUnit() * 18
			local a = Instance.new("Attachment")
			a.Parent = d
			emitter(a, {
				Texture = i <= 3 and TEX_FIRE or TEX_SMOKE,
				Color = i <= 3 and cs(0, rgb(255, 170, 70), 1, rgb(90, 40, 20)) or cs(0, rgb(70, 66, 62), 1, rgb(120, 116, 110)),
				Size = ns(0, i <= 3 and 0.9 or 0.6, 1, i <= 3 and 0.2 or 1.8),
				Transparency = ns(0, 0.2, 1, 1),
				Lifetime = NumberRange.new(0.5, 1.1),
				Speed = NumberRange.new(0.5),
				Rate = i <= 3 and 30 or 18,
				LightEmission = i <= 3 and 1 or 0,
				LightInfluence = i <= 3 and 0 or 1,
			})
			task.delay(rng:NextNumber(1.2, 2.2), function()
				for _, e in a:GetChildren() do
					if e:IsA("ParticleEmitter") then
						e.Rate = 0
					end
				end
			end)
			Debris:AddItem(d, 6)
		end

		-- scorch mark with embers glowing in it
		local scorch = Instance.new("Part")
		scorch.Name = "Scorch"
		scorch.Shape = Enum.PartType.Cylinder
		scorch.Size = Vector3.new(0.05, fb * 2.6, fb * 2.6)
		scorch.Color = rgb(20, 18, 17)
		scorch.Material = Enum.Material.SmoothPlastic
		scorch.Transparency = 0.1
		scorch.Anchored = true
		scorch.CanCollide = false
		scorch.CanQuery = false
		scorch.CanTouch = false
		scorch.CastShadow = false
		scorch.CFrame = CFrame.lookAt(hit.Position + hit.Normal * 0.03, hit.Position + hit.Normal * 2) * CFrame.Angles(0, math.rad(90), 0)
		scorch.Parent = folder
		TweenService:Create(scorch, TweenInfo.new(40, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
		Debris:AddItem(scorch, 40)
		local glow = scorch:Clone()
		glow.Name = "ScorchGlow"
		glow.Size = Vector3.new(0.05, fb * 1.4, fb * 1.4)
		glow.Color = rgb(255, 110, 30)
		glow.Material = Enum.Material.Neon
		glow.Transparency = 0.35
		glow.CFrame = scorch.CFrame + hit.Normal * 0.03
		glow.Parent = folder
		TweenService:Create(glow, TweenInfo.new(4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Color = rgb(120, 20, 10) }):Play()
		Debris:AddItem(glow, 4.1)

		-- small fires keep burning around it
		local nFires = crowdN >= 4 and 0 or (oily and 6 or (kind == "grenade" and 2 or 3))
		for _ = 1, math.floor(nFires * lod + 0.5) do
			local off = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * fb * 1.3
			local down = Ground.Cast(groundPos + off + Vector3.new(0, 3, 0), Vector3.new(0, -6, 0), rayParams)
			if down then
				local life = rng:NextNumber(4, oily and 12 or 8)
				local _, fa = anchor(CFrame.new(down.Position), life + 3)
				local f = emitter(fa, {
					Texture = TEX_FIRE,
					Color = cs(0, rgb(255, 210, 110), 0.5, rgb(255, 110, 30), 1, rgb(80, 30, 20)),
					Size = ns(0, rng:NextNumber(0.9, 1.6), 1, 0.2),
					Transparency = ns(0, 0.15, 1, 1),
					Lifetime = NumberRange.new(0.5, 1),
					Speed = NumberRange.new(2, 5),
					SpreadAngle = Vector2.new(12, 12),
					Acceleration = Vector3.new(0, 6, 0),
					Rate = 22,
					LightEmission = 1,
					Brightness = 2,
				})
				local sm = emitter(fa, {
					Texture = TEX_SMOKE,
					Color = cs(0, rgb(40, 38, 36), 1, rgb(110, 106, 102)),
					Size = ns(0, 1, 1, 4),
					Transparency = ns(0, 0.5, 1, 1),
					Lifetime = NumberRange.new(2, 3.5),
					Speed = NumberRange.new(3, 6),
					SpreadAngle = Vector2.new(15, 15),
					Rate = 4,
					LightInfluence = 1,
				})
				local fl = Instance.new("PointLight")
				fl.Color = rgb(255, 140, 60)
				fl.Range = 10
				fl.Brightness = 1.6
				fl.Parent = fa.Parent
				task.delay(life, function()
					f.Rate = 0
					sm.Rate = 0
					fl:Destroy()
				end)
			end
		end
	end

	-- 6. camera / ears
	if onShake then
		onShake(math.clamp(1.7 - dist / (r * 4), 0, 1.7))
	end
	postFX(math.clamp(1 - dist / (r * 2.8), 0, 1), 0.8, true)
	if dist < r * 0.9 then
		local k = 1 - dist / (r * 0.9)
		SoundLibrary.Play("ringing", nil, 0.3 + 0.7 * k)
		SoundLibrary.Muffle(1.5 + 3 * k, 0.6 + 0.4 * k)
	end
	distantBang(pos, dist, r / 25)
	task.delay(0.6, function()
		if dist < 220 then
			SoundLibrary.Play("debris", pos, 0.8)
		end
	end)
end

-- a small burst (rocket exhaust puffs, sparks off metal)
function ExplosionFX.Small(pos: Vector3, dir: Vector3)
	local _, att = anchor(CFrame.lookAt(pos, pos + (dir.Magnitude > 0.01 and dir.Unit or Vector3.yAxis)), 4)
	local smoke = emitter(att, {
		Texture = TEX_SMOKE,
		Color = cs(0, rgb(90, 86, 82), 1, rgb(150, 146, 140)),
		Size = ns(0, 0.6, 1, 3),
		Transparency = ns(0, 0.3, 1, 1),
		Lifetime = NumberRange.new(0.8, 1.6),
		Speed = NumberRange.new(4, 14),
		SpreadAngle = Vector2.new(30, 30),
		EmissionDirection = Enum.NormalId.Front,
		Drag = 2,
		LightInfluence = 1,
	})
	smoke:Emit(8)
	local sparks = emitter(att, {
		Texture = TEX_SPARK,
		Color = cs(0, rgb(255, 230, 160), 1, rgb(255, 120, 40)),
		Size = ns(0, 0.3, 1, 0),
		Lifetime = NumberRange.new(0.2, 0.5),
		Speed = NumberRange.new(20, 45),
		SpreadAngle = Vector2.new(35, 35),
		EmissionDirection = Enum.NormalId.Front,
		Acceleration = Vector3.new(0, -60, 0),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = ns(0, 2, 1, 1),
		LightEmission = 1,
		Brightness = 4,
	})
	sparks:Emit(12)
end

-- something fell into the water: a crown of spray and foam
function ExplosionFX.Splash(pos: Vector3, scale: number)
	local _, att = anchor(CFrame.new(pos), 4)
	local spray = emitter(att, {
		Texture = TEX_SMOKE,
		Color = cs(0, rgb(235, 245, 250), 1, rgb(200, 225, 235)),
		Size = ns(0, 0.6 * scale, 1, 2.2 * scale),
		Transparency = ns(0, 0.15, 1, 1),
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(12 * scale, 30 * scale),
		SpreadAngle = Vector2.new(28, 28),
		Acceleration = Vector3.new(0, -workspace.Gravity * 0.6, 0),
		Drag = 0.8,
		LightInfluence = 1,
	})
	spray:Emit(math.floor(26 * scale + 6))
	local drops = emitter(att, {
		Texture = TEX_SPARK,
		Color = cs(0, rgb(220, 240, 255), 1, rgb(200, 230, 255)),
		Size = ns(0, 0.25, 1, 0.1),
		Lifetime = NumberRange.new(0.5, 1.1),
		Speed = NumberRange.new(15 * scale, 35 * scale),
		SpreadAngle = Vector2.new(40, 40),
		Acceleration = Vector3.new(0, -workspace.Gravity * 0.6, 0),
		LightInfluence = 1,
	})
	drops:Emit(math.floor(30 * scale + 8))
	local foam = emitter(att, {
		Texture = TEX_SMOKE,
		Color = cs(0, rgb(240, 248, 250), 1, rgb(220, 235, 240)),
		Size = ns(0, 1, 1, 5 * scale),
		Transparency = ns(0, 0.3, 1, 1),
		Lifetime = NumberRange.new(1.2, 2),
		Speed = NumberRange.new(0.05),
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		LightInfluence = 1,
	})
	foam:Emit(2)
end

-- air bubbles rising from somebody under water
function ExplosionFX.Bubbles(pos: Vector3)
	local _, att = anchor(CFrame.new(pos), 4)
	local b = emitter(att, {
		Texture = TEX_SPARK,
		Color = cs(0, rgb(230, 245, 255), 1, rgb(200, 230, 255)),
		Size = ns(0, 0.18, 1, 0.3),
		Transparency = ns(0, 0.2, 1, 0.8),
		Lifetime = NumberRange.new(1, 2.2),
		Speed = NumberRange.new(4, 7),
		SpreadAngle = Vector2.new(12, 12),
		Acceleration = Vector3.new(0, 3, 0),
		LightInfluence = 1,
	})
	b:Emit(rng:NextInteger(3, 7))
end

------------------------------------------------------------------------
-- the flash grenade
------------------------------------------------------------------------

function ExplosionFX.Flash(pos: Vector3)
	local rigPart, att = anchor(CFrame.new(pos), 6)
	local burst = emitter(att, {
		Texture = TEX_SMOKE,
		Color = cs(0, rgb(255, 255, 255), 1, rgb(220, 235, 255)),
		Size = ns(0, 4, 1, 22),
		Transparency = ns(0, 0, 1, 1),
		Lifetime = NumberRange.new(0.18, 0.25),
		Speed = NumberRange.new(0),
		LightEmission = 1,
		Brightness = 10,
		ZOffset = 4,
	})
	burst:Emit(3)
	local light = Instance.new("PointLight")
	light.Color = rgb(235, 240, 255)
	light.Shadows = true
	light.Parent = rigPart
	flicker(light, 40, 60, 0.45)
	local sparks = emitter(att, {
		Texture = TEX_SPARK,
		Color = cs(0, rgb(255, 255, 255), 1, rgb(190, 210, 255)),
		Size = ns(0, 0.35, 1, 0),
		Lifetime = NumberRange.new(0.3, 0.8),
		Speed = NumberRange.new(30, 70),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -50, 0),
		Drag = 2,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = ns(0, 2.2, 1, 1),
		LightEmission = 1,
		Brightness = 6,
	})
	sparks:Emit(40)
	local smoke = emitter(att, {
		Texture = TEX_SMOKE,
		Color = cs(0, rgb(200, 200, 205), 1, rgb(160, 160, 165)),
		Size = ns(0, 1.5, 1, 7),
		Transparency = ns(0, 0.35, 1, 1),
		Lifetime = NumberRange.new(2.5, 4),
		Speed = NumberRange.new(3, 9),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 1.5,
		Acceleration = Vector3.new(0, 1.5, 0),
		LightInfluence = 1,
	})
	smoke:Emit(12)
	if onShake then
		onShake(math.clamp(0.8 - cameraDistance(pos) / 80, 0, 0.8))
	end
end

------------------------------------------------------------------------
-- the nuke
------------------------------------------------------------------------

local function screenFlash(strength: number, duration: number, color: Color3)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Flash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.ResetOnSpawn = false
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - strength
	f.BorderSizePixel = 0
	f.Parent = gui
	gui.Parent = pg
	TweenService:Create(f, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(gui, duration + 0.1)
end
ExplosionFX.ScreenFlash = screenFlash

function ExplosionFX.Nuke(pos: Vector3, R: number, S: number, speed: number)
	local dist = cameraDistance(pos)
	local hit = Ground.Cast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -400, 0), rayParams)
	local g = hit and hit.Position or pos
	local t0 = os.clock()
	local life = 46
	local fireR = R * 0.3

	-- the flash: everything goes white, then a long warm afterglow
	screenFlash(math.clamp(1.15 - dist / 3000, 0.45, 1), 2.8, Color3.new(1, 1, 1))
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "NukeCC"
	cc.Brightness = 0.6
	cc.Contrast = 0.25
	cc.Saturation = -0.25
	cc.TintColor = rgb(255, 210, 165)
	cc.Parent = Lighting
	TweenService:Create(cc, TweenInfo.new(16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = Color3.new(1, 1, 1) }):Play()
	Debris:AddItem(cc, 16.5)
	SoundLibrary.Play("explosion", pos, 1, 0.5)

	local nf = Instance.new("Folder")
	nf.Name = "Nuke"
	nf.Parent = folder

	local function mover(name: string): (BasePart, Attachment)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.one
		p.Transparency = 1
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CFrame = CFrame.new(g)
		p.Parent = nf
		local a = Instance.new("Attachment")
		a.Parent = p
		return p, a
	end

	-- the white-hot core (a glowing ball: brighter than any particle can be)
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	core.Material = Enum.Material.Neon
	core.Color = rgb(255, 250, 230)
	core.Size = Vector3.one * 8
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.CFrame = CFrame.new(g)
	core.Parent = nf
	for _ = 1, 3 do
		local l = Instance.new("PointLight")
		l.Color = rgb(255, 190, 110)
		l.Range = 60
		l.Brightness = 25
		l.Shadows = true
		l.Parent = core
	end

	-- head of the mushroom: fire first, then thick rolling smoke (it leaves the column behind)
	local headPart, headAtt = mover("Head")
	local headFire = emitter(headAtt, {
		Texture = TEX_FIRE,
		Color = cs(0, rgb(255, 245, 210), 0.2, rgb(255, 180, 80), 0.55, rgb(230, 80, 25), 1, rgb(70, 35, 25)),
		Size = ns(0, 30, 0.4, 70, 1, 90),
		Transparency = ns(0, 0, 0.6, 0.2, 1, 1),
		Lifetime = NumberRange.new(2, 4),
		Speed = NumberRange.new(fireR * 0.3, fireR * 0.9),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 1.2,
		Rate = 60,
		RotSpeed = NumberRange.new(-30, 30),
		LightEmission = 0.9,
		Brightness = 3,
	})
	local headSmoke = emitter(headAtt, {
		Texture = TEX_SMOKE,
		Color = cs(0, rgb(150, 80, 45), 0.25, rgb(95, 75, 65), 1, rgb(130, 122, 116)),
		Size = ns(0, 50, 0.5, 85, 1, 100),
		Transparency = ns(0, 0.1, 0.7, 0.35, 1, 1),
		Lifetime = NumberRange.new(9, 15),
		Speed = NumberRange.new(fireR * 0.25, fireR * 0.8),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 0.6,
		Rate = 0,
		RotSpeed = NumberRange.new(-12, 12),
		LightInfluence = 1,
	})
	-- the rolling ring under the cap (torus)
	local ringParts = {}
	for i = 1, 10 do
		local p, a = mover("Cap" .. i)
		local e = emitter(a, {
			Texture = TEX_SMOKE,
			Color = cs(0, rgb(170, 90, 45), 0.3, rgb(100, 82, 72), 1, rgb(135, 128, 120)),
			Size = ns(0, 40, 1, 80),
			Transparency = ns(0, 0.15, 0.7, 0.4, 1, 1),
			Lifetime = NumberRange.new(5, 9),
			Speed = NumberRange.new(4, 14),
			SpreadAngle = Vector2.new(40, 40),
			EmissionDirection = Enum.NormalId.Front,
			Drag = 0.5,
			Rate = 0,
			RotSpeed = NumberRange.new(-15, 15),
			LightInfluence = 1,
		})
		ringParts[i] = { part = p, e = e }
	end
	-- the stem: dust and smoke sucked up from the ground into the head
	local _, stemAtt = mover("Stem")
	local stem = emitter(stemAtt, {
		Texture = TEX_SMOKE,
		Color = cs(0, rgb(200, 120, 60), 0.3, rgb(120, 98, 84), 1, rgb(110, 104, 100)),
		Size = ns(0, 30, 1, 55),
		Transparency = ns(0, 0.2, 0.8, 0.4, 1, 1),
		Lifetime = NumberRange.new(5, 7),
		Speed = NumberRange.new(30, 48),
		SpreadAngle = Vector2.new(7, 7),
		Rate = 0,
		RotSpeed = NumberRange.new(-20, 20),
		LightInfluence = 1,
	})
	-- base surge: a wall of dust rolling out along the ground
	local _, surgeAtt = mover("Surge")
	surgeAtt.WorldPosition = g + Vector3.new(0, 8, 0)
	local surge = emitter(surgeAtt, {
		Texture = TEX_SMOKE,
		Color = cs(0, rgb(190, 160, 120), 1, rgb(165, 155, 140)),
		Size = ns(0, 25, 1, 70),
		Transparency = ns(0, 0.2, 0.7, 0.45, 1, 1),
		Lifetime = NumberRange.new(6, 10),
		Speed = NumberRange.new(speed * 0.25, speed * 0.45),
		SpreadAngle = Vector2.new(5, 5),
		EmissionDirection = Enum.NormalId.Front,
		Drag = 0.35,
		RotSpeed = NumberRange.new(-15, 15),
		LightInfluence = 1,
	})
	-- the shockwave throws up dust where it passes
	local SHOCK_POINTS = 56
	local shockAtts = {}
	local shockHolder = Instance.new("Part")
	shockHolder.Name = "Shock"
	shockHolder.Size = Vector3.one
	shockHolder.Transparency = 1
	shockHolder.Anchored = true
	shockHolder.CanCollide = false
	shockHolder.CanQuery = false
	shockHolder.CanTouch = false
	shockHolder.CFrame = CFrame.new(g)
	shockHolder.Parent = nf
	local shockEmitters = {}
	for i = 1, SHOCK_POINTS do
		local a = Instance.new("Attachment")
		a.Parent = shockHolder
		shockAtts[i] = a
		shockEmitters[i] = emitter(a, {
			Texture = TEX_SMOKE,
			Color = cs(0, rgb(205, 190, 165), 1, rgb(180, 172, 160)),
			Size = ns(0, 14, 1, 42),
			Transparency = ns(0, 0.25, 0.6, 0.5, 1, 1),
			Lifetime = NumberRange.new(2, 3.6),
			Speed = NumberRange.new(10, 30),
			SpreadAngle = Vector2.new(25, 25),
			EmissionDirection = Enum.NormalId.Front,
			Drag = 0.8,
			Acceleration = Vector3.new(0, 4, 0),
			LightInfluence = 1,
		})
	end
	-- a condensation shell racing out (refracts the world behind it)
	local shell = Instance.new("Part")
	shell.Name = "Shell"
	shell.Shape = Enum.PartType.Ball
	shell.Material = Enum.Material.ForceField
	shell.Color = rgb(255, 255, 255)
	shell.Size = Vector3.one * 10
	shell.Transparency = 0.1
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.CastShadow = false
	shell.CFrame = CFrame.new(g)
	shell.Parent = nf
	-- the crater
	local crater = Instance.new("Part")
	crater.Name = "Crater"
	crater.Shape = Enum.PartType.Cylinder
	crater.Size = Vector3.new(0.3, 2, 2)
	crater.Color = rgb(26, 22, 20)
	crater.Material = Enum.Material.Slate
	crater.Anchored = true
	crater.CanCollide = false
	crater.CanQuery = false
	crater.CanTouch = false
	crater.CastShadow = false
	crater.CFrame = CFrame.new(g + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
	crater.Parent = nf
	TweenService:Create(crater, TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.3, R * 0.75, R * 0.75) }):Play()

	local shockHit = false
	local lastShockEmit = 0
	local lastSurge = 0
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		if t > life or not nf.Parent then
			conn:Disconnect()
			nf:Destroy()
			return
		end
		local function ease(x: number): number
			x = math.clamp(x, 0, 1)
			return 1 - (1 - x) ^ 3
		end
		local swell = ease(t / 1.2)
		local rise = math.clamp((t - 1) / 16, 0, 1)
		local headY = fireR * 0.6 + rise ^ 0.7 * R * 1.05
		local head = g + Vector3.new(0, headY, 0)
		local hot = 1 - math.clamp((t - 1) / 8, 0, 1)
		core.Size = Vector3.one * math.max(fireR * 1.7 * swell * (0.35 + 0.65 * hot), 0.5)
		core.CFrame = CFrame.new(head)
		core.Color = rgb(255, 250, 230):Lerp(rgb(255, 120, 40), 1 - hot)
		core.Transparency = 1 - hot * 0.97
		for _, l in core:GetChildren() do
			if l:IsA("PointLight") then
				l.Brightness = 25 * hot
			end
		end
		headPart.CFrame = CFrame.new(head)
		headFire.Rate = t < 7 and 60 or 0
		headSmoke.Rate = (t > 1.5 and t < 24) and 30 or 0
		-- the cap ring rolls around the head
		local capR = fireR * (0.6 + 1.3 * rise) * swell
		for i, rp in ringParts do
			local a = (i / #ringParts) * math.pi * 2 + t * 0.12
			local p = head + Vector3.new(math.cos(a) * capR, -fireR * 0.2, math.sin(a) * capR)
			rp.part.CFrame = CFrame.lookAt(p, p + Vector3.new(math.cos(a), -0.5, math.sin(a)))
			rp.e.Rate = (t > 2 and t < 22) and 6 or 0
		end
		stem.Rate = (t > 1.5 and t < 22) and 14 or 0
		-- base surge (the first seconds)
		if t > 0.4 and t < 6 and os.clock() - lastSurge > 0.12 then
			lastSurge = os.clock()
			radial(surgeAtt, surge, 18, 1, 0.05)
		end
		-- shockwave
		local sr = t * speed
		if sr < S then
			shell.Size = Vector3.one * (sr * 2)
			shell.Transparency = 0.1 + 0.9 * math.clamp(sr / (S * 0.5), 0, 1)
			if os.clock() - lastShockEmit > 0.12 and sr > fireR then
				lastShockEmit = os.clock()
				for i, a in shockAtts do
					local ang = (i / SHOCK_POINTS) * math.pi * 2 + rng:NextNumber(-0.04, 0.04)
					local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
					a.WorldCFrame = CFrame.lookAt(g + dir * sr + Vector3.new(0, 3, 0), g + dir * (sr + 10) + Vector3.new(0, 4, 0))
					shockEmitters[i]:Emit(1)
				end
			end
		else
			shell.Transparency = 1
		end
		-- the wave reaches the camera: hard shake, the bang, a dust flash
		local camDist = cameraDistance(pos)
		if not shockHit and sr >= camDist then
			shockHit = true
			if camDist < S * 1.3 then
				SoundLibrary.Play("boomFar", nil, math.clamp(1.4 - camDist / (S * 1.5), 0.4, 1.4))
				SoundLibrary.Play("explosion", nil, math.clamp(1.2 - camDist / S, 0.3, 1.2), 0.55)
				screenFlash(math.clamp(0.6 - camDist / (S * 2), 0.1, 0.6), 1.2, rgb(200, 170, 130))
				postFX(math.clamp(1 - camDist / S, 0.2, 1), 2.5, true)
				SoundLibrary.Muffle(3 + 4 * math.clamp(1 - camDist / S, 0, 1), 0.8)
				if onShake then
					onShake(math.clamp(2.4 - camDist / S, 0.5, 1.7))
				end
			end
		end
		if shockHit and onShake and t < 12 and camDist < S then
			onShake(0.28 * (1 - t / 12))
		end
	end)
	-- the crater stays a while after the cloud is gone
	task.delay(life - 0.5, function()
		local left = crater:Clone()
		left.Parent = folder
		TweenService:Create(left, TweenInfo.new(60, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
		Debris:AddItem(left, 60)
	end)
end

------------------------------------------------------------------------
-- glass: a pane shatters into shards that fall and tinkle on the ground
------------------------------------------------------------------------

function ExplosionFX.Glass(cf: CFrame, size: Vector3, point: Vector3, dir: Vector3, color: Color3?)
	local area = size.X * size.Y + size.Y * size.Z + size.X * size.Z
	local n = math.clamp(math.floor(area * 0.6), 6, 22)
	if not Settings.Get("vfx") then
		n = 4
	end
	local col = color or rgb(190, 220, 240)
	local push = dir.Magnitude > 0.1 and dir.Unit or Vector3.zero
	for _ = 1, n do
		local s = rng:NextNumber(0.12, 0.55)
		local shard = Instance.new("Part")
		shard.Name = "Shard"
		shard.Size = Vector3.new(s, 0.05, s * rng:NextNumber(0.6, 1.8))
		shard.Material = Enum.Material.Glass
		shard.Color = col
		shard.Transparency = 0.35
		shard.Reflectance = 0.25
		shard.CanQuery = false
		shard.CanTouch = false
		shard.CastShadow = false
		shard.Massless = true
		local lp = Vector3.new(rng:NextNumber(-0.5, 0.5) * size.X, rng:NextNumber(-0.5, 0.5) * size.Y, rng:NextNumber(-0.5, 0.5) * size.Z)
		shard.CFrame = cf * CFrame.new(lp) * CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
		shard.Parent = folder
		local away = (shard.Position - point)
		away = away.Magnitude > 0.05 and away.Unit or randomUnit()
		shard.AssemblyLinearVelocity = push * rng:NextNumber(8, 22) + away * rng:NextNumber(2, 8) + Vector3.new(0, rng:NextNumber(0, 6), 0)
		shard.AssemblyAngularVelocity = randomUnit() * rng:NextNumber(5, 20)
		task.delay(rng:NextNumber(2.5, 4), function()
			if shard.Parent then
				TweenService:Create(shard, TweenInfo.new(0.8), { Transparency = 1 }):Play()
			end
		end)
		Debris:AddItem(shard, 5)
	end
	-- glitter where it broke
	local _, a = anchor(CFrame.new(point), 2)
	local e = emitter(a, {
		Texture = TEX_SPARK,
		Color = ColorSequence.new(rgb(230, 245, 255)),
		Size = ns(0, 0.35, 1, 0),
		Transparency = ns(0, 0.1, 1, 1),
		Lifetime = NumberRange.new(0.3, 0.7),
		Speed = NumberRange.new(6, 16),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 0.6,
	})
	e:Emit(24)
	task.delay(0.35, function()
		SoundLibrary.Play("glassTinkle", point, 0.6)
	end)
end

return ExplosionFX
