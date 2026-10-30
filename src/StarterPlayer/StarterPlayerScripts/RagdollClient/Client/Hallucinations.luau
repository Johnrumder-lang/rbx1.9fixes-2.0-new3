--!nonstrict
-- Hallucinations: what a player sick with the virus sees and hears (only on their own screen).
-- It gets worse the longer you are sick: more often, longer, closer.
--
--   always   the world loses its colour, the picture breathes (blur, field of view), a heartbeat
--            that gets faster, a dark vignette that closes in, now and then the world tilts
--   watcher  a tall black figure with red eyes at the edge of your view. Look at it: it twitches,
--            stretches and is gone
--   behind   something right behind you, breathing. Turn around: nothing
--   crawler  something on all fours rushes at you in jerks and jumps in your face
--   closer   a figure far ahead that comes closer every time you look away. Do not look away
--   eyes     a ring of red eyes in the dark around you, blinking out one by one
--   runner   a shadow person sprints past through the corner of your eye
--   writing  words in blood appear on the wall in front of you
--   steps    footsteps walk around you in a circle; nobody is there
--   hands    black hands reach in from the edges of the screen
--   names    something whispers your name
--   glitch   the colours invert for a moment, a face fills the screen, fake pain

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local SoundLibrary = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SoundLibrary"))
local Settings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Settings"))
local Cam = require(script.Parent:WaitForChild("CameraController"))

local Hallucinations = {}

local player = Players.LocalPlayer
local rng = Random.new()
local gui: ScreenGui? = nil
local cc: ColorCorrectionEffect? = nil
local blur: BlurEffect? = nil
local vignette: Frame? = nil
local active = false
local sickSince = 0
local nextEvent = 0
local nextBeat = 0
local forcedUntil = 0 -- (v2.1) cyberpsychosis: hallucinations for a while, whether you are sick or not
local forcedSev = 0
local psychoUntil, psychoSev = 0, 0
local tiltUntil = 0
local tiltTarget = 0

type Fig = { model: Model, mode: string, untilT: number, vel: Vector3, data: any }
local figs: { Fig } = {}

local WRITING = { "IT SEES YOU", "TURN AROUND", "YOU CAN'T LEAVE", "WE ARE HERE", "DON'T SLEEP", "IT'S INSIDE YOU", "LOOK BEHIND YOU", "NO WAY OUT", "STAY" }
local WHISPERS = { "behind you", "it sees you", "don't look", "you can't leave", "it's inside you", "turn around", "we are here", "so cold", "let us in", "closer" }

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function severity(): number
	return math.clamp((os.clock() - sickSince) / 90, 0, 1)
end

local function torsoOf(): BasePart?
	local char = player.Character
	local t = char and char:FindFirstChild("Torso")
	return (t and t:IsA("BasePart")) and t or nil
end

local function flatLook(): Vector3
	local cam = workspace.CurrentCamera
	local look = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
	local f = Vector3.new(look.X, 0, look.Z)
	return f.Magnitude > 0.01 and f.Unit or Vector3.new(0, 0, -1)
end

local function part(m: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = m
	return p
end

local BLACK = Color3.fromRGB(5, 4, 6)
local RED = Color3.fromRGB(255, 20, 20)

-- a tall thin black thing with long arms and red eyes (feet at the origin)
local function buildTall(): Model
	local m = Instance.new("Model")
	m.Name = "Hallucination"
	part(m, "Body", Vector3.new(1.3, 4.8, 0.7), CFrame.new(0, 5.4, 0), BLACK)
	part(m, "Head", Vector3.new(1.05, 1.5, 1.05), CFrame.new(0, 8.6, 0) * CFrame.Angles(0, 0, 0.18), BLACK)
	for _, x in { -1, 1 } do
		part(m, "Arm", Vector3.new(0.28, 6.2, 0.28), CFrame.new(x * 0.95, 4.4, 0) * CFrame.Angles(0, 0, x * 0.07), BLACK)
		for f = -1, 1 do
			part(m, "Finger", Vector3.new(0.06, 1.1, 0.06), CFrame.new(x * 1.12 + f * 0.08, 0.95, -0.05) * CFrame.Angles(0, 0, x * 0.1 + f * 0.08), BLACK)
		end
		part(m, "Leg", Vector3.new(0.38, 3.3, 0.38), CFrame.new(x * 0.4, 1.65, 0), BLACK)
	end
	for _, x in { -0.24, 0.24 } do
		part(m, "Eye", Vector3.new(0.2, 0.12, 0.1), CFrame.new(x, 8.8, -0.52), RED, Enum.Material.Neon)
	end
	part(m, "Mouth", Vector3.new(0.55, 0.5, 0.1), CFrame.new(0, 8.1, -0.52), Color3.fromRGB(70, 0, 0), Enum.Material.Neon)
	local root = part(m, "Root", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), BLACK)
	root.Transparency = 1
	m.PrimaryPart = root
	return m
end

local function buildCrawler(): Model
	local m = Instance.new("Model")
	m.Name = "Hallucination"
	part(m, "Body", Vector3.new(1.3, 0.8, 4.2), CFrame.new(0, 1.3, 0) * CFrame.Angles(-0.15, 0, 0), BLACK)
	part(m, "Head", Vector3.new(1, 1.1, 1), CFrame.new(0, 1.7, -2.5) * CFrame.Angles(0, 0, math.pi), BLACK)
	for _, x in { -1, 1 } do
		part(m, "UpperArm", Vector3.new(0.3, 0.3, 2), CFrame.new(x * 1.1, 1.6, -2.0) * CFrame.Angles(0.9, x * 0.4, 0), BLACK)
		part(m, "LowerArm", Vector3.new(0.25, 0.25, 2), CFrame.new(x * 1.5, 0.6, -2.9) * CFrame.Angles(-0.7, x * 0.3, 0), BLACK)
		part(m, "Leg", Vector3.new(0.32, 0.32, 3.4), CFrame.new(x * 0.8, 1.0, 2.3) * CFrame.Angles(0.5, -x * 0.3, 0), BLACK)
	end
	for _, x in { -0.22, 0.22 } do
		part(m, "Eye", Vector3.new(0.18, 0.12, 0.1), CFrame.new(x, 1.55, -3.0), RED, Enum.Material.Neon)
	end
	local root = part(m, "Root", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), BLACK)
	root.Transparency = 1
	m.PrimaryPart = root
	return m
end

local function groundAt(p: Vector3): Vector3?
	local char = player.Character
	rayParams.FilterDescendantsInstances = char and { char, workspace.CurrentCamera } or { workspace.CurrentCamera }
	local hit = workspace:Raycast(p + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), rayParams)
	return hit and hit.Position or nil
end

local function spawnFig(model: Model, at: Vector3, facing: Vector3, mode: string, life: number, data: any?): Fig?
	local g = groundAt(at)
	if not g then
		model:Destroy()
		return nil
	end
	local look = Vector3.new(facing.X, 0, facing.Z)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
	model:PivotTo(CFrame.lookAt(g, g + look))
	model.Parent = workspace.CurrentCamera -- (only this client, never in the world)
	local f = { model = model, mode = mode, untilT = os.clock() + life, vel = Vector3.zero, data = data or {} }
	table.insert(figs, f)
	return f
end

local function removeFig(f: Fig)
	local i = table.find(figs, f)
	if i then
		table.remove(figs, i)
	end
	f.model:Destroy()
end

local function clearFigs()
	for i = #figs, 1, -1 do
		figs[i].model:Destroy()
		figs[i] = nil
	end
end

-- looking at it vanishes it: it twitches and stretches first
local function vanish(f: Fig)
	f.mode = "dying"
	f.untilT = os.clock() + 0.25
	SoundLibrary.Play("sting", nil, 0.6, 0.6)
	local cf = f.model:GetPivot()
	task.spawn(function()
		for i = 1, 5 do
			if not f.model.Parent then
				return
			end
			f.model:PivotTo(cf * CFrame.new(rng:NextNumber(-0.4, 0.4), 0, 0) * CFrame.Angles(0, rng:NextNumber(-0.6, 0.6), rng:NextNumber(-0.15, 0.15)))
			for _, p in f.model:GetDescendants() do
				if p:IsA("BasePart") and p.Name ~= "Root" then
					p.Transparency = i / 5
				end
			end
			task.wait(0.04)
		end
	end)
end

------------------------------------------------------------------------
-- screen effects
------------------------------------------------------------------------

local function overlay(z: number): Frame?
	if not gui then
		return nil
	end
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = gui
	return f
end

local function flashFace()
	local f = overlay(40)
	if not f then
		return
	end
	local face = Instance.new("Frame")
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.52)
	face.Size = UDim2.fromScale(0.42, 0.95)
	face.BackgroundColor3 = Color3.fromRGB(186, 180, 166)
	face.BorderSizePixel = 0
	face.ZIndex = 41
	face.Parent = f
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.45, 0)
	c.Parent = face
	local function hole(x: number, y: number, w: number, h: number, color: Color3, z: number)
		local e = Instance.new("Frame")
		e.AnchorPoint = Vector2.new(0.5, 0.5)
		e.Position = UDim2.fromScale(x, y)
		e.Size = UDim2.fromScale(w, h)
		e.BackgroundColor3 = color
		e.BorderSizePixel = 0
		e.ZIndex = z
		e.Parent = face
		local ec = Instance.new("UICorner")
		ec.CornerRadius = UDim.new(0.5, 0)
		ec.Parent = e
	end
	hole(0.3, 0.36, 0.24, 0.18, Color3.new(0, 0, 0), 42)
	hole(0.7, 0.36, 0.24, 0.18, Color3.new(0, 0, 0), 42)
	hole(0.3, 0.37, 0.05, 0.035, Color3.fromRGB(255, 30, 30), 43)
	hole(0.7, 0.37, 0.05, 0.035, Color3.fromRGB(255, 30, 30), 43)
	hole(0.5, 0.74, 0.56, 0.34, Color3.new(0, 0, 0), 42)
	for i = 0, 7 do
		local tooth = Instance.new("Frame")
		tooth.AnchorPoint = Vector2.new(0.5, 0)
		tooth.Position = UDim2.fromScale(0.27 + i * 0.066, 0.6)
		tooth.Size = UDim2.fromScale(0.035, 0.08 + (i % 2) * 0.03)
		tooth.BackgroundColor3 = Color3.fromRGB(214, 206, 180)
		tooth.BorderSizePixel = 0
		tooth.ZIndex = 43
		tooth.Parent = face
	end
	SoundLibrary.Play("sting", nil, 1)
	SoundLibrary.Play("groan", nil, 1)
	Cam.Shake(0.8)
	task.delay(0.16, function()
		f:Destroy()
	end)
end

local function screenText(text: string, size: number, color: Color3, life: number)
	if not gui then
		return
	end
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = text
	t.Font = Enum.Font.Sarpanch
	t.TextColor3 = color
	t.TextTransparency = 1
	t.TextSize = size
	t.Position = UDim2.fromScale(rng:NextNumber(0.08, 0.7), rng:NextNumber(0.12, 0.8))
	t.Size = UDim2.fromOffset(460, 70)
	t.Rotation = rng:NextNumber(-8, 8)
	t.ZIndex = 30
	t.Parent = gui
	TweenService:Create(t, TweenInfo.new(1.1), { TextTransparency = 0.1 }):Play()
	task.delay(life, function()
		TweenService:Create(t, TweenInfo.new(1.2), { TextTransparency = 1 }):Play()
		Debris:AddItem(t, 1.3)
	end)
end

local function whisper(name: boolean?)
	local text = name and (string.lower(player.DisplayName) .. "...") or WHISPERS[rng:NextInteger(1, #WHISPERS)]
	screenText(text, rng:NextInteger(26, 44), Color3.fromRGB(150, 20, 20), 2.2)
	SoundLibrary.Play("whisper", nil, 1)
end

local function flicker(n: number?)
	if not cc then
		return
	end
	task.spawn(function()
		for _ = 1, n or rng:NextInteger(3, 6) do
			if cc then
				cc.Brightness = -0.75
			end
			task.wait(rng:NextNumber(0.04, 0.12))
			if cc then
				cc.Brightness = -0.05
			end
			task.wait(rng:NextNumber(0.05, 0.25))
		end
	end)
end

local function glitch()
	if not cc then
		return
	end
	task.spawn(function()
		for _ = 1, rng:NextInteger(2, 4) do
			if not cc then
				return
			end
			cc.Saturation = -1
			cc.Contrast = 1
			cc.TintColor = Color3.fromRGB(255, 60, 60)
			Cam.roll = rng:NextNumber(-0.25, 0.25)
			task.wait(rng:NextNumber(0.05, 0.1))
			cc.TintColor = Color3.new(1, 1, 1)
			cc.Contrast = 0.2
			Cam.roll = 0
			task.wait(rng:NextNumber(0.05, 0.18))
		end
	end)
	SoundLibrary.Play("static", nil, 1)
end

-- fake pain: a red flash and a jolt, nothing hit you
local function phantomPain()
	local f = overlay(35)
	if not f then
		return
	end
	f.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
	f.BackgroundTransparency = 0.35
	TweenService:Create(f, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(f, 0.7)
	Cam.Shake(0.6)
	SoundLibrary.Play("bodyHit", nil, 0.7)
	whisper()
end

-- black hands reaching in from the edges
local function hands()
	if not gui then
		return
	end
	local list = {}
	for i = 1, rng:NextInteger(3, 5) do
		local side = rng:NextInteger(1, 4)
		local h = Instance.new("Frame")
		h.BackgroundColor3 = BLACK
		h.BorderSizePixel = 0
		h.ZIndex = 32
		local along = rng:NextNumber(0.15, 0.85)
		local reach = rng:NextNumber(0.12, 0.26)
		local start, finish
		if side == 1 then -- left
			h.Size = UDim2.fromScale(reach, 0.035)
			h.AnchorPoint = Vector2.new(1, 0.5)
			start, finish = UDim2.fromScale(0, along), UDim2.fromScale(reach, along)
		elseif side == 2 then -- right
			h.Size = UDim2.fromScale(reach, 0.035)
			h.AnchorPoint = Vector2.new(0, 0.5)
			start, finish = UDim2.fromScale(1, along), UDim2.fromScale(1 - reach, along)
		elseif side == 3 then -- top
			h.Size = UDim2.fromScale(0.02, reach * 1.6)
			h.AnchorPoint = Vector2.new(0.5, 1)
			start, finish = UDim2.fromScale(along, 0), UDim2.fromScale(along, reach * 1.6)
		else -- bottom
			h.Size = UDim2.fromScale(0.02, reach * 1.6)
			h.AnchorPoint = Vector2.new(0.5, 0)
			start, finish = UDim2.fromScale(along, 1), UDim2.fromScale(along, 1 - reach * 1.6)
		end
		h.Position = start
		-- fingers at the tip
		for f = -2, 2 do
			local finger = Instance.new("Frame")
			finger.BackgroundColor3 = BLACK
			finger.BorderSizePixel = 0
			finger.ZIndex = 32
			if side <= 2 then
				finger.Size = UDim2.new(0, 30 + math.abs(f) * -4, 0, 4)
				finger.AnchorPoint = Vector2.new(side == 1 and 0 or 1, 0.5)
				finger.Position = UDim2.new(side == 1 and 1 or 0, 0, 0.5 + f * 0.3, 0)
				finger.Rotation = f * 12 * (side == 1 and 1 or -1)
			else
				finger.Size = UDim2.new(0, 4, 0, 30 + math.abs(f) * -4)
				finger.AnchorPoint = Vector2.new(0.5, side == 3 and 0 or 1)
				finger.Position = UDim2.new(0.5 + f * 0.6, 0, side == 3 and 1 or 0, 0)
				finger.Rotation = f * 12
			end
			finger.Parent = h
		end
		h.Parent = gui
		table.insert(list, h)
		TweenService:Create(h, TweenInfo.new(rng:NextNumber(1.6, 2.6) + i * 0.2, Enum.EasingStyle.Sine), { Position = finish }):Play()
		task.delay(3.4, function()
			TweenService:Create(h, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = start }):Play()
			Debris:AddItem(h, 0.3)
		end)
	end
	SoundLibrary.Play("groan", nil, 0.6)
end

-- words written in blood on the wall in front of you
local function writing(): boolean
	local cam = workspace.CurrentCamera
	local torso = torsoOf()
	if not cam or not torso then
		return false
	end
	local char = player.Character
	rayParams.FilterDescendantsInstances = char and { char, cam } or { cam }
	local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 45, rayParams)
	if not hit or math.abs(hit.Normal.Y) > 0.5 then
		return false
	end
	local board = part(cam, "Writing", Vector3.new(12, 5, 0.05), CFrame.lookAt(hit.Position + hit.Normal * 0.06, hit.Position + hit.Normal * 2) + Vector3.new(0, 1.5, 0), Color3.new(), nil)
	board.Transparency = 1
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(600, 250)
	sg.LightInfluence = 0.6
	sg.Parent = board
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.Sarpanch
	t.TextScaled = true
	t.Text = WRITING[rng:NextInteger(1, #WRITING)]
	t.TextColor3 = Color3.fromRGB(120, 6, 8)
	t.TextTransparency = 1
	t.Rotation = rng:NextNumber(-6, 6)
	t.Parent = sg
	TweenService:Create(t, TweenInfo.new(2.5), { TextTransparency = 0.05 }):Play()
	task.delay(7, function()
		TweenService:Create(t, TweenInfo.new(0.15), { TextTransparency = 1 }):Play()
		Debris:AddItem(board, 0.2)
	end)
	SoundLibrary.Play("whisper", nil, 0.8)
	return true
end

-- footsteps walking around you; nobody is there
local function circlingSteps()
	local torso = torsoOf()
	if not torso then
		return
	end
	task.spawn(function()
		local a = rng:NextNumber(0, math.pi * 2)
		local dirSign = rng:NextNumber() < 0.5 and -1 or 1
		for _ = 1, 16 do
			local t = torsoOf()
			if not t or not active then
				return
			end
			a += dirSign * 0.38
			local p = t.Position + Vector3.new(math.cos(a), -2.5, math.sin(a)) * 6
			SoundLibrary.Play("step", p, 1.6, 0.8)
			task.wait(0.42)
		end
		SoundLibrary.Play("groan", nil, 0.5)
	end)
end

-- a ring of red eyes in the dark, they go out one by one
local function eyeRing()
	local torso = torsoOf()
	local cam = workspace.CurrentCamera
	if not torso or not cam then
		return
	end
	local m = Instance.new("Model")
	m.Name = "Eyes"
	local pairsList = {}
	local n = rng:NextInteger(8, 14)
	for i = 1, n do
		local a = (i / n) * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local r = rng:NextNumber(14, 26)
		local base = torso.Position + Vector3.new(math.cos(a) * r, rng:NextNumber(1, 4), math.sin(a) * r)
		local cf = CFrame.lookAt(base, torso.Position)
		local l = part(m, "Eye", Vector3.new(0.22, 0.12, 0.05), cf * CFrame.new(-0.22, 0, 0), RED, Enum.Material.Neon)
		local r2 = part(m, "Eye", Vector3.new(0.22, 0.12, 0.05), cf * CFrame.new(0.22, 0, 0), RED, Enum.Material.Neon)
		table.insert(pairsList, { l, r2 })
	end
	m.Parent = cam
	flicker(2)
	if cc then
		TweenService:Create(cc, TweenInfo.new(0.5), { Brightness = -0.45 }):Play()
	end
	task.spawn(function()
		task.wait(2.5)
		for _, pr in pairsList do
			for _, e in pr do
				e.Transparency = 1
			end
			task.wait(0.18)
		end
		m:Destroy()
		if cc then
			TweenService:Create(cc, TweenInfo.new(1), { Brightness = 0 }):Play()
		end
	end)
	SoundLibrary.Play("heartbeat", nil, 1.2)
end

------------------------------------------------------------------------
-- events
------------------------------------------------------------------------

local function event()
	local cam = workspace.CurrentCamera
	local torso = torsoOf()
	if not cam or not torso then
		return
	end
	local sev = severity()
	local look = flatLook()
	local r = rng:NextNumber()
	if r < 0.14 then
		-- the watcher
		local side = rng:NextNumber() < 0.5 and -1 or 1
		local dir = CFrame.Angles(0, side * math.rad(rng:NextNumber(36, 52)), 0):VectorToWorldSpace(look)
		local at = torso.Position + dir * rng:NextNumber(22, 38) * (1 - sev * 0.4)
		spawnFig(buildTall(), at, torso.Position - at, "watch", 8)
		SoundLibrary.Play("whisper", nil, 0.8)
	elseif r < 0.25 then
		-- right behind you
		local at = torso.Position - look * 4.5
		spawnFig(buildTall(), at, torso.Position - at, "behind", 3.5)
		SoundLibrary.Play("groan", nil, 0.7)
		SoundLibrary.Play("heartbeat", nil, 1)
	elseif r < 0.36 then
		-- a crawler rushing at you in jerks
		local at = torso.Position + look * rng:NextNumber(26, 34)
		local f = spawnFig(buildCrawler(), at, torso.Position - at, "crawl", 5)
		if f then
			f.vel = ((torso.Position - at) * Vector3.new(1, 0, 1)).Unit * (24 + sev * 14)
		end
		SoundLibrary.Play("groan", nil, 0.9, 1.4)
	elseif r < 0.45 then
		-- it comes closer whenever you look away
		local at = torso.Position + look * 40
		local f = spawnFig(buildTall(), at, torso.Position - at, "closer", 14 + sev * 8, { seen = true })
		if f then
			SoundLibrary.Play("sting", nil, 0.4, 0.5)
		end
	elseif r < 0.53 then
		eyeRing()
	elseif r < 0.61 then
		-- a shadow person sprints past at the edge of your view
		local side = rng:NextNumber() < 0.5 and -1 or 1
		local right = look:Cross(Vector3.yAxis)
		local at = torso.Position + look * 16 + right * side * 22
		local f = spawnFig(buildTall(), at, -right * side, "run", 1.4)
		if f then
			f.vel = -right * side * 34
		end
	elseif r < 0.69 then
		if not writing() then
			whisper()
		end
	elseif r < 0.76 then
		circlingSteps()
	elseif r < 0.83 then
		hands()
	elseif r < 0.88 then
		whisper(true)
		whisper()
	elseif r < 0.93 then
		glitch()
		if sev > 0.4 then
			phantomPain()
		end
	elseif r < 0.97 then
		flicker()
		whisper()
	else
		flashFace()
	end
	-- the world tilts for a moment
	if rng:NextNumber() < 0.25 + sev * 0.3 then
		tiltTarget = rng:NextNumber(-0.22, 0.22) * (0.5 + sev)
		tiltUntil = os.clock() + rng:NextNumber(2, 4)
	end
end

local function updateFigs(dt: number)
	local cam = workspace.CurrentCamera
	local torso = torsoOf()
	if not cam or not torso then
		return
	end
	local now = os.clock()
	for i = #figs, 1, -1 do
		local f = figs[i]
		if not f.model.Parent or not f.model.PrimaryPart then
			table.remove(figs, i)
			continue
		end
		if now > f.untilT then
			removeFig(f)
			continue
		end
		if f.mode == "dying" then
			continue
		end
		local pos = f.model.PrimaryPart.Position
		local to = (pos + Vector3.new(0, 3, 0)) - cam.CFrame.Position
		local dot = to.Unit:Dot(cam.CFrame.LookVector)
		local flatTo = (torso.Position - pos) * Vector3.new(1, 0, 1)
		if f.mode == "crawl" then
			-- stop-and-go: it jerks forward
			local burst = (math.sin(now * 9) > -0.2) and 1 or 0.1
			local cf = f.model:GetPivot() + f.vel * dt * burst
			f.model:PivotTo(cf * CFrame.Angles(0, 0, math.sin(now * 23) * 0.06))
			if flatTo.Magnitude < 3 then
				removeFig(f)
				flashFace()
			end
		elseif f.mode == "run" then
			f.model:PivotTo(f.model:GetPivot() + f.vel * dt)
		elseif f.mode == "closer" then
			local seen = dot > 0.55
			if f.data.seen and not seen then
				-- you looked away: it is closer now
				local d = flatTo.Magnitude
				if d > 1 then
					local step = math.min(d - 2.5, math.max(6, d * 0.4))
					local newPos = pos + flatTo.Unit * step
					local g = groundAt(newPos) or newPos
					f.model:PivotTo(CFrame.lookAt(g, g + flatTo.Unit))
					SoundLibrary.Play("step", g, 1.4, 0.7)
				end
				if d < 4 then
					removeFig(f)
					flashFace()
					phantomPain()
					continue
				end
			end
			f.data.seen = seen
		elseif f.mode == "watch" then
			-- its head follows you
			local head = f.model:FindFirstChild("Head")
			if head and head:IsA("BasePart") then
				head.CFrame = CFrame.lookAt(head.Position, torso.Position + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, math.pi, 0.18)
			end
			if dot > 0.93 then
				vanish(f)
			end
		elseif f.mode == "behind" then
			if dot > 0.6 then
				vanish(f)
			end
		end
	end
end

local function step(dt: number)
	local char = player.Character
	local now = os.clock()
	if require(game.ReplicatedStorage.Shared.PsychosisState).Level(player) <= 0 then psychoUntil = 0 end
	local sick = char ~= nil and (char:GetAttribute("Sick") == true or now < forcedUntil or now < psychoUntil) and not char:GetAttribute("Dead")
		and Settings.Get("hallucinations") == true
	if sick ~= active then
		active = sick
		if active then
			sickSince = (char:GetAttribute("Sick") == true) and now or (now - math.max(now < forcedUntil and forcedSev or 0, now < psychoUntil and psychoSev or 0) * 90) -- (an episode starts as bad as the psychosis is)
			nextEvent = now + rng:NextNumber(3, 6)
		else
			clearFigs()
			Cam.roll = 0
			Cam.fovOffset = 0
		end
	end
	local sev = active and severity() or 0
	if cc and blur then
		local k = active and 1 or 0
		cc.Saturation += ((active and (-0.5 - 0.35 * sev) or 0) - cc.Saturation) * math.min(1, dt * 2)
		cc.Contrast += ((active and (0.15 + 0.15 * sev) or 0) - cc.Contrast) * math.min(1, dt * 2)
		cc.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(200, 230, 190), k * (0.6 + 0.4 * math.sin(now * 1.3)))
		blur.Size = active and (3 + (4 + 6 * sev) * math.max(0, math.sin(now * 0.9)) ^ 3) or math.max(0, blur.Size - dt * 10)
	end
	if vignette then
		local want = active and (0.55 - 0.35 * sev - 0.12 * math.max(0, math.sin(now * 0.8))) or 1
		local cur = vignette:GetAttribute("T") or 1
		cur += (want - cur) * math.min(1, dt * 2)
		vignette:SetAttribute("T", cur)
		for _, e in vignette:GetChildren() do
			if e:IsA("Frame") then
				e.BackgroundTransparency = cur
			end
		end
	end
	if not active then
		return
	end
	-- the picture breathes and sometimes tilts
	Cam.fovOffset = math.sin(now * 0.7) * (2 + 5 * sev)
	local roll = now < tiltUntil and tiltTarget or 0
	Cam.roll += (roll - Cam.roll) * math.min(1, dt * 1.5)
	if now > nextBeat then
		nextBeat = now + (0.9 - 0.4 * sev)
		SoundLibrary.Play("heartbeat", nil, 0.7 + 0.5 * sev)
	end
	if now > nextEvent then
		nextEvent = now + rng:NextNumber(6, 12) * (1 - 0.5 * sev)
		event()
	end
	updateFigs(dt)
end

-- (v2.1) the Sandevistan's cyberpsychosis: hallucinations for 'seconds', as bad as 'sev' (0..1)
function Hallucinations.Force(seconds: number, sev: number, source: string?)
	if source == "overload" then
		psychoUntil = math.max(psychoUntil, os.clock() + seconds); psychoSev = math.clamp(sev, 0, 1); return
	end
	forcedUntil = math.max(forcedUntil, os.clock() + seconds)
	forcedSev = math.clamp(sev, 0, 1)
end

function Hallucinations.Init()
	local g = Instance.new("ScreenGui")
	g.Name = "Hallucinations"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 30
	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
	-- a dark vignette (four soft edges)
	local v = Instance.new("Frame")
	v.Name = "Vignette"
	v.Size = UDim2.fromScale(1, 1)
	v.BackgroundTransparency = 1
	v.ZIndex = 20
	v.Parent = g
	for _, rot in { 0, 90, 180, 270 } do
		local e = Instance.new("Frame")
		e.Size = UDim2.fromScale(1, 1)
		e.BackgroundColor3 = Color3.new(0, 0, 0)
		e.BackgroundTransparency = 1
		e.BorderSizePixel = 0
		e.ZIndex = 20
		local grad = Instance.new("UIGradient")
		grad.Rotation = rot
		grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 1), NumberSequenceKeypoint.new(1, 1) })
		grad.Parent = e
		e.Parent = v
	end
	vignette = v
	local c = Instance.new("ColorCorrectionEffect")
	c.Name = "SickCC"
	c.Parent = Lighting
	cc = c
	local b = Instance.new("BlurEffect")
	b.Name = "SickBlur"
	b.Size = 0
	b.Parent = Lighting
	blur = b
	RunService.RenderStepped:Connect(step)
end

return Hallucinations
