--!nonstrict
-- MapMood (v2.0): how a map feels while your camera is in it (only on this screen).
--   horror : dark, cold, washed-out colours, fog drifting over the ground (FogPoint_n in the map), now and then a
--            creak or a whisper somewhere in the dark
--   sea    : the sound of the waves, a little more blue
--   ikea   : warm shop light
--   valley : (v2.0) hot, dusty, orange
--   sky    : (v2.0) bright and airy, the wind up there
--   pit    : (v2.8) THE PIT under the ritual circle: hot, red, the fire hisses
-- It fades in and out over a second when you go in / come out (the pads, a respawn, spectating).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local SoundLibrary = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SoundLibrary"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local MapMood = {}

-- the same boxes as MapService.MAPS (centre, half size)
local BOXES = {
	city = { Vector3.new(0, 0, 2600), 310 },
	horror = { Vector3.new(2800, 0, 0), 420 },
	sea = { Vector3.new(-3000, 0, 0), 700 },
	ikea = { Vector3.new(0, 0, -3300), 460 },
	valley = { Vector3.new(2800, 0, 2800), 460 },
	sky = { Vector3.new(-3000, 0, 2800), 460 },
	-- (v2.8) THE PIT (the STILLWATER quest), not a map: it is always there - (v2.8.1) deep under the ritual circle: Config.InPit
}

local MOODS = {
	horror = { brightness = -0.16, contrast = 0.22, saturation = -0.6, tint = Color3.fromRGB(196, 206, 236), blur = 0 },
	sea = { brightness = 0.02, contrast = 0.05, saturation = 0.1, tint = Color3.fromRGB(226, 240, 255), blur = 0 },
	ikea = { brightness = 0.03, contrast = 0.04, saturation = 0.05, tint = Color3.fromRGB(255, 246, 228), blur = 0 },
	valley = { brightness = 0.04, contrast = 0.1, saturation = 0.12, tint = Color3.fromRGB(255, 232, 204), blur = 0 },
	sky = { brightness = 0.06, contrast = 0.03, saturation = 0.18, tint = Color3.fromRGB(232, 242, 255), blur = 0 },
	pit = { brightness = -0.04, contrast = 0.26, saturation = 0.1, tint = Color3.fromRGB(255, 200, 180), blur = 0 },
}

local cc: ColorCorrectionEffect
local blur: BlurEffect
local k = 0
local current: string? = nil
local waves: Sound? = nil
local fog: { BasePart } = {}
local nextScare = 0

local function mapAt(pos: Vector3): string?
	for id, b in BOXES do
		local d = pos - b[1]
		if math.abs(d.X) < b[2] and math.abs(d.Z) < b[2] and pos.Y < 400 and pos.Y > -150 then
			return id
		end
	end
	if Config.InPit(pos) then
		return "pit"
	end
	return nil
end

local function makeFog()
	for _, f in fog do
		f:Destroy()
	end
	table.clear(fog)
	local map = workspace:FindFirstChild("ActiveMap")
	if not map or map:GetAttribute("MapId") ~= "horror" then
		return
	end
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and string.match(d.Name, "^FogPoint_%d+$") then
			local a = Instance.new("Part")
			a.Name = "Fog"
			a.Size = Vector3.new(40, 1, 40)
			a.Transparency = 1
			a.Anchored = true
			a.CanCollide = false
			a.CanQuery = false
			a.CanTouch = false
			a.CFrame = d.CFrame
			a.Parent = workspace.CurrentCamera
			local e = Instance.new("ParticleEmitter")
			e.Texture = "rbxasset://textures/particles/smoke_main.dds"
			e.Color = ColorSequence.new(Color3.fromRGB(190, 196, 204))
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 8), NumberSequenceKeypoint.new(1, 16) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.82), NumberSequenceKeypoint.new(1, 1) })
			e.Lifetime = NumberRange.new(8, 12)
			e.Speed = NumberRange.new(0.5, 1.5)
			e.SpreadAngle = Vector2.new(20, 180)
			e.EmissionDirection = Enum.NormalId.Top
			e.Rate = 2
			e.LightInfluence = 0.6
			e.Parent = a
			table.insert(fog, a)
		end
	end
end

local ownLight: PointLight? = nil
local lightK = 0
local function updateOwnLight(dt: number, darkMap: boolean)
	local player = game:GetService("Players").LocalPlayer
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	local clock = Lighting.ClockTime
	local night = clock < 6.2 or clock > 18.4
	local want = ((darkMap or night) and head and not char:GetAttribute("Dead")) and 1 or 0
	lightK += (want - lightK) * math.min(1, dt * 2)
	if lightK < 0.01 then
		if ownLight then
			if ownLight.Parent and ownLight.Parent:IsA("Attachment") then
				ownLight.Parent:Destroy()
			end
			ownLight:Destroy()
			ownLight = nil
		end
		return
	end
	if not ownLight or not ownLight.Parent or ownLight.Parent.Parent ~= head then
		if ownLight then
			if ownLight.Parent and ownLight.Parent:IsA("Attachment") then
				ownLight.Parent:Destroy()
			end
			ownLight:Destroy()
		end
		-- (v2.0 fix) a little above and in front of the head, and no shadows: your own head, body and hats used to
		-- block it (the light sat inside the head)
		local att = Instance.new("Attachment")
		att.Name = "OwnLightAt"
		att.Position = Vector3.new(0, 1.4, -0.6)
		att.Parent = head
		local l = Instance.new("PointLight")
		l.Name = "OwnLight"
		l.Color = Color3.fromRGB(255, 226, 190)
		l.Shadows = false
		l.Parent = att
		ownLight = l
	end
	local l = ownLight :: PointLight
	l.Range = 18 * lightK
	l.Brightness = 0.85 * lightK
end

function MapMood.Init()
	cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "MapMood"
	cc.Enabled = false
	cc.Parent = Lighting
	blur = Instance.new("BlurEffect")
	blur.Name = "MapMoodBlur"
	blur.Size = 0
	blur.Enabled = false
	blur.Parent = Lighting
	workspace:GetAttributeChangedSignal("MapLoaded"):Connect(function()
		task.wait(1)
		makeFog()
	end)
	makeFog()
	RunService.RenderStepped:Connect(function(dt)
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local here = mapAt(cam.CFrame.Position)
		if here and not MOODS[here] then
			here = nil
		end
		if here ~= current and k <= 0.01 then
			current = here
		end
		local want = (here ~= nil and here == current) and 1 or 0
		k += (want - k) * math.min(1, dt * 1.5)
		local m = current and MOODS[current]
		if m and k > 0.005 then
			cc.Enabled = true
			cc.Brightness = m.brightness * k
			cc.Contrast = m.contrast * k
			cc.Saturation = m.saturation * k
			cc.TintColor = Color3.new(1, 1, 1):Lerp(m.tint, k)
			blur.Enabled = m.blur > 0
			blur.Size = m.blur * k
		else
			cc.Enabled = false
			blur.Enabled = false
		end
		-- the sea: waves; (v2.0) the sky islands: wind
		local loopName = (current == "sea" and "waves") or (current == "sky" and "windLoop") or (current == "pit" and "fireLoop") or nil
		if loopName and k > 0.05 then
			if waves and waves:GetAttribute("Loop") ~= loopName then
				waves:Destroy()
				waves = nil
			end
			if not waves or not waves.Parent then
				waves = SoundLibrary.Loop(loopName, game:GetService("SoundService"))
				if waves then
					waves:SetAttribute("Loop", loopName)
					waves:Play()
				end
			end
			if waves then
				waves.Volume = (loopName == "waves" and 0.35 or 0.22) * k
			end
		elseif waves then
			waves:Destroy()
			waves = nil
		end
		-- (v2.0) in the dark (the asylum, or night anywhere) you carry a small light of your own: it shows the way
		-- round you (only on your screen: hiding stays fair)
		updateOwnLight(dt, current == "horror" and k > 0.3)
		-- the horror map: noises in the dark
		local now = os.clock()
		if current == "horror" and k > 0.5 and now > nextScare then
			nextScare = now + math.random(12, 26)
			local pos = cam.CFrame.Position + Vector3.new(math.random(-30, 30), math.random(-2, 6), math.random(-30, 30))
			SoundLibrary.Play(math.random() < 0.6 and "creak" or "whisper", pos, 0.8, 0.8 + math.random() * 0.4)
		end
	end)
end

return MapMood
