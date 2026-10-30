--!nonstrict
-- SwordClient (v2.8): the STILLWATER quest on this screen (SwordQuestService, RivalService and StillCutService have the rules).
--   * the quest tracker (right, under the Steel Ball tracker); after the quest: the STILL CUT's readiness
--   * what VESPER CROWE says: subtitles at the bottom, one line after the other
--   * the hole at the ritual circle while it is open (rings of fire turning, embers, smoke, a red glow, the roar)
--   * the fall into it, THE PIT's own air (dark red haze, embers drifting; MapMood tints it, the weather stays out)
--   * the boss bar while the Pale Heir is near, his SHADE ARMS (built and moved here from his attributes), the warning ring
--     before a slam, his blink streaks, the crescent of his cut
--   * the STILL CUT: the world turns blue and still, the picture tears in bands, cuts appear in the air one after the
--     other - and when the blade clicks shut they flash and are gone. His own still cut: a ring on the ground (get out)
--   * the card that explains the STILL CUT when STILLWATER becomes yours

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))

local Modules = script.Parent
local UI = require(Modules:WaitForChild("UI"))
local Events = require(Modules:WaitForChild("Events"))
local Input = require(Modules:WaitForChild("Input"))
local Cam = require(Modules:WaitForChild("CameraController"))
local QuestClient = require(Modules:WaitForChild("QuestClient"))

local SwordRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Sword") :: RemoteEvent

local C = UI.C
local player = Players.LocalPlayer
local PALE = Color3.fromRGB(150, 210, 255)
local BLOOD = Color3.fromRGB(220, 50, 50)

local SwordClient = {}

local gui: ScreenGui
local fx: Folder
local tracker: Frame
local trackTitle: TextLabel
local trackText: TextLabel
local subPanel: Frame
local subName: TextLabel
local subText: TextLabel
local bossPanel: Frame
local bossName: TextLabel
local bossFill: Frame
local bands: Frame
local card: Frame? = nil

local PIT_C = Config.PitCenter -- (v2.8.1: deep under the ritual circle)
local PIT_HALF = 210

local function now(): number
	return workspace:GetServerTimeNow()
end

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Neon
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function inPit(pos: Vector3): boolean
	local d = pos - PIT_C
	return math.abs(d.X) < PIT_HALF and math.abs(d.Z) < PIT_HALF and d.Y > -100 and d.Y < 240
end

------------------------------------------------------------------------
-- the tracker
------------------------------------------------------------------------

local TITLES = {
	[1] = "QUEST 1/3  -  BLOOD FOR THE DOOR",
	[2] = "QUEST 2/3  -  THE DESCENT",
	[3] = "QUEST 3/3  -  THE PALE HEIR",
}

local function knowsCut(): boolean
	return player:GetAttribute("HasStillCut") == true or player:GetAttribute("Gift_stillcut") == true
end

local function updateTracker()
	local stage = player:GetAttribute("SwordStage")
	stage = typeof(stage) == "number" and stage or 0
	-- (under the Steel Ball tracker when that one is up)
	local qg = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("Quest")
	local qt = qg and qg:FindFirstChild("QuestTracker")
	tracker.Position = UDim2.new(1, -12, 0, (qt and qt.Visible) and 218 or 158)
	if TITLES[stage] then
		tracker.Visible = true
		trackTitle.Text = TITLES[stage]
		trackTitle.TextColor3 = BLOOD
		local text = player:GetAttribute("ObjectiveText")
		if stage == 1 then
			text = string.format("Kill with a blade  %d/%d", player:GetAttribute("SwordProg") or 0, player:GetAttribute("SwordGoal") or Config.SwordQ1Kills)
		elseif typeof(text) ~= "string" then
			text = stage == 2 and "Take the sheath from the bone altar" or "Beat " .. Config.RivalName
		end
		trackText.Text = text
		return
	end
	if knowsCut() then
		local ready = player:GetAttribute("StillCutReady")
		local left = typeof(ready) == "number" and math.ceil(ready - now()) or 0
		tracker.Visible = left > 0 -- (only while it rests: a ready blade needs no reminder)
		trackTitle.Text = "STILL CUT"
		trackTitle.TextColor3 = PALE
		trackText.Text = string.format("The blade rests  %d s", math.max(0, left))
		return
	end
	tracker.Visible = false
end

------------------------------------------------------------------------
-- subtitles (what he says)
------------------------------------------------------------------------

local queue: { { name: string, text: string } } = {}
local talking = false

local function talk()
	if talking then
		return
	end
	talking = true
	task.spawn(function()
		while #queue > 0 do
			local line = table.remove(queue, 1)
			subName.Text = string.upper(line.name)
			subText.Text = line.text
			subText.MaxVisibleGraphemes = 0
			subPanel.Visible = true
			SoundLibrary.Play("whisper", nil, 0.35, 0.7)
			local n = 0
			while n < #line.text do
				n = math.min(#line.text, n + 2)
				subText.MaxVisibleGraphemes = n
				task.wait(0.02)
			end
			subText.MaxVisibleGraphemes = -1
			task.wait(1.6 + #line.text * 0.04)
		end
		subPanel.Visible = false
		talking = false
	end)
end

local function say(name: string, lines: { string })
	for _, l in lines do
		if typeof(l) == "string" then
			table.insert(queue, { name = name, text = l })
		end
	end
	talk()
end

------------------------------------------------------------------------
-- the explanation card
------------------------------------------------------------------------

local function closeCard()
	if card then
		card:Destroy()
		card = nil
		Input.promptOpen = false
		GuiService.SelectedObject = nil
	end
end

local function showCard()
	closeCard()
	Input.promptOpen = true
	local w = 620
	local p = UI.panel({ Name = "StillCutCard", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(w, 0),
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0.08, Accent = PALE, ZIndex = 40, Parent = gui })
	UI.make("UIScale", { Scale = math.min(1, (workspace.CurrentCamera.ViewportSize.X - 24) / w), Parent = p })
	local inner = UI.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 40, Parent = p })
	UI.make("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 18), PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 14), Parent = inner })
	UI.make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = inner })
	UI.label({ Text = Config.SwordName .. " IS YOURS", Font = UI.FONT_TITLE, TextSize = 30, TextColor3 = PALE, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 1, ZIndex = 40, Parent = inner })
	local lines = {
		"From now on you spawn with it: the sheath at your left hip, the sword inside.",
		"DRAW IT: hold Q with an empty left hand (L1 on a controller, STOW L on a phone).",
		"STILL CUT: hold Q again with " .. Config.SwordName .. " in your left hand. It slides back into its sheath in the SAME pocket - and the world stops. Cuts appear all round you, only you can move. When the blade clicks shut, everything they went through falls apart.",
		string.format("Put it into the other pocket and it is only sheathed. After a cut the blade rests for %d s.", Config.StillCutCooldown),
	}
	for i, t in lines do
		UI.label({ Text = t, TextSize = 17, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 + i, ZIndex = 40, Parent = inner })
	end
	local row = UI.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 10, ZIndex = 40, Parent = inner })
	local ok = UI.button({ Text = "UNDERSTOOD", TextSize = 16, TextColor3 = Color3.fromRGB(10, 14, 20), BackgroundColor3 = PALE, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(170, 34), ZIndex = 41, Parent = row }, closeCard)
	card = p
	if Input.lastDevice == "Gamepad" then
		GuiService.SelectedObject = ok
	end
	SoundLibrary.Play("questDone", nil, 1)
end

------------------------------------------------------------------------
-- the hole at the ritual circle
------------------------------------------------------------------------

local holeFX: Model? = nil
local holeRings: { { model: Model, speed: number } } = {}

local function holePart(): BasePart?
	local map = workspace:FindFirstChild("Map")
	local site = map and map:FindFirstChild("RitualSite")
	local h = site and site:FindFirstChild("HellHole")
	return (h and h:IsA("BasePart")) and h or nil
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function buildHole(h: BasePart)
	local m = Instance.new("Model")
	m.Name = "HoleFX"
	local top = h.Position + Vector3.new(0, 0.06, 0)
	table.clear(holeRings)
	for i, r in { 5.4, 3.9, 2.4 } do
		local ring = Instance.new("Model")
		ring.Name = "Ring"
		local n = 18
		for k = 0, n - 1 do
			local a = 2 * math.pi * k / n
			local seg = part("RingSeg", Vector3.new(2 * math.pi * r / n * 0.7, 0.06, 0.35),
				CFrame.new(top + Vector3.new(r * math.cos(a), i * 0.03, r * math.sin(a))) * CFrame.Angles(0, -a - math.pi / 2, 0),
				Color3.fromRGB(255, 60 + i * 30, 20))
			seg.Transparency = 0.1 + i * 0.15
			seg.Parent = ring
		end
		ring.WorldPivot = CFrame.new(top) -- (no PrimaryPart: the ring turns round its centre, the pivot)
		ring.Parent = m
		table.insert(holeRings, { model = ring, speed = (i % 2 == 0 and -1 or 1) * (0.6 + i * 0.35) })
	end
	local core = part("HoleCore", Vector3.new(1, 1, 1), CFrame.new(top), Color3.new(0, 0, 0))
	core.Transparency = 1
	core.Parent = m
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = Color3.fromRGB(255, 70, 30)
	light.Range = 26
	light.Brightness = 3
	light.Parent = core
	emitter(core, {
		Name = "Embers",
		Rate = 45,
		Lifetime = NumberRange.new(1.6, 3),
		Speed = NumberRange.new(6, 14),
		SpreadAngle = Vector2.new(22, 22),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(Color3.fromRGB(255, 180, 60), Color3.fromRGB(255, 40, 10)),
		LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Disc,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})
	emitter(core, {
		Name = "Smoke",
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = 10,
		Lifetime = NumberRange.new(2.5, 4),
		Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(15, 15),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(40, 20, 18)),
		RotSpeed = NumberRange.new(-30, 30),
	})
	local roar = SoundLibrary.Loop("fireLoop", core)
	if roar then
		roar.Volume = 0.6
		roar:Play()
	end
	m.Parent = fx
	holeFX = m
end

local function updateHole(dt: number)
	local open = workspace:GetAttribute("PitOpen")
	local isOpen = typeof(open) == "number" and open > now()
	local h = holePart()
	if isOpen and h and not holeFX then
		buildHole(h)
	elseif (not isOpen or not h) and holeFX then
		holeFX:Destroy()
		holeFX = nil
		table.clear(holeRings)
	end
	if holeFX then
		for _, r in holeRings do
			r.model:PivotTo(r.model:GetPivot() * CFrame.Angles(0, r.speed * dt, 0))
		end
		local core = holeFX:FindFirstChild("HoleCore")
		local glow = core and core:FindFirstChild("Glow")
		if glow and glow:IsA("PointLight") then
			glow.Brightness = 2.6 + math.sin(os.clock() * 3) * 0.8
		end
	end
end

------------------------------------------------------------------------
-- the Pit's air
------------------------------------------------------------------------

local atmDefaults: { [string]: any }? = nil
local pitOn = false
local embers: BasePart? = nil

local PIT_AIR = { Density = 0.42, Offset = 0, Color = Color3.fromRGB(70, 16, 10), Decay = Color3.fromRGB(34, 8, 4), Glare = 0, Haze = 1.4 }

local function setPit(on: boolean)
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if on == pitOn then
		if on and atm then
			for k, v in PIT_AIR do
				(atm :: any)[k] = v
			end
		end
		return
	end
	pitOn = on
	Lighting:SetAttribute("PitOverride", on or nil)
	if on then
		local e = part("PitEmbers", Vector3.new(60, 30, 60), CFrame.new(), Color3.new(0, 0, 0))
		e.Transparency = 1
		emitter(e, {
			Rate = 60,
			Lifetime = NumberRange.new(3, 6),
			Speed = NumberRange.new(1, 4),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, 2, 0),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) }),
			Color = ColorSequence.new(Color3.fromRGB(255, 160, 60), Color3.fromRGB(255, 50, 20)),
			LightEmission = 1,
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		})
		e.Parent = fx
		embers = e
	else
		if embers then
			embers:Destroy()
			embers = nil
		end
		if atm and atmDefaults then
			for k, v in atmDefaults do
				(atm :: any)[k] = v
			end
		end
	end
end

------------------------------------------------------------------------
-- the boss bar and the SHADE ARMS
------------------------------------------------------------------------

type Arm = { upper: BasePart, fore: BasePart, palm: BasePart, fingers: { BasePart }, cores: { BasePart }, orb: BasePart, hand: Vector3? }
type Arms = { L: Arm, R: Arm, model: Model, k: number }
local armsOf: { [Model]: Arms } = {}

local SHADE = Color3.fromRGB(140, 170, 255)
local SHADE_CORE = Color3.fromRGB(110, 130, 255)

local function buildArm(folder: Model): Arm
	local function ff(name: string, size: Vector3): BasePart
		local p = part(name, size, CFrame.new(), SHADE, Enum.Material.ForceField)
		p.Parent = folder
		return p
	end
	local function core(name: string, size: Vector3): BasePart
		local p = part(name, size, CFrame.new(), SHADE_CORE, Enum.Material.Neon)
		p.Transparency = 0.55
		p.Parent = folder
		return p
	end
	local a: Arm = {
		upper = ff("ShadeUpper", Vector3.new(1.8, 1.8, 6)),
		fore = ff("ShadeFore", Vector3.new(1.6, 1.6, 6)),
		palm = ff("ShadePalm", Vector3.new(2.8, 0.9, 2.6)),
		fingers = {},
		cores = { core("ShadeBone", Vector3.new(0.45, 0.45, 5.6)), core("ShadeBone", Vector3.new(0.4, 0.4, 5.6)) },
		orb = part("ShadeOrb", Vector3.new(2.2, 2.2, 2.2), CFrame.new(), SHADE_CORE, Enum.Material.Neon, Enum.PartType.Ball),
		hand = nil,
	}
	a.orb.Transparency = 0.45
	a.orb.Parent = folder
	for i = 1, 5 do
		table.insert(a.fingers, ff("ShadeFinger", i == 5 and Vector3.new(0.6, 0.6, 1.8) or Vector3.new(0.55, 0.55, 2.2)))
	end
	return a
end

local function setArmLook(a: Arm, k: number)
	local t = 1 - k
	for _, p in { a.upper, a.fore, a.palm } do
		p.Transparency = t
	end
	for _, f in a.fingers do
		f.Transparency = t
	end
	for _, c in a.cores do
		c.Transparency = 0.55 + 0.45 * t
	end
	a.orb.Transparency = 0.45 + 0.55 * t
end

local function poseArm(a: Arm, torso: BasePart, side: number, target: Vector3?, fist: boolean, dt: number)
	local tcf = torso.CFrame
	local shoulder = tcf:PointToWorldSpace(Vector3.new(side * 3.6, 3.4, 1.6))
	local idle = tcf:PointToWorldSpace(Vector3.new(side * 4.4, 2.2 + math.sin(os.clock() * 1.6 + side) * 0.4, -3.4))
	local want = target or idle
	a.hand = a.hand or idle
	a.hand = (a.hand :: Vector3):Lerp(want, 1 - math.exp(-dt * (target and 16 or 6)))
	local hand = a.hand :: Vector3
	local d = hand - shoulder
	local dist = math.clamp(d.Magnitude, 0.5, 11.6)
	local dir = d.Magnitude > 0.01 and d.Unit or tcf.LookVector
	hand = shoulder + dir * dist
	local pole = tcf.RightVector * side * 0.8 + Vector3.yAxis * 0.6 - tcf.LookVector * 0.3
	pole = pole - dir * pole:Dot(dir)
	pole = pole.Magnitude > 0.01 and pole.Unit or Vector3.yAxis
	local cosA = math.clamp(dist / 12, -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local elbow = shoulder + dir * 6 * cosA + pole * 6 * sinA
	a.orb.CFrame = CFrame.new(shoulder)
	a.upper.CFrame = CFrame.lookAt((shoulder + elbow) / 2, elbow)
	a.fore.CFrame = CFrame.lookAt((elbow + hand) / 2, hand)
	a.cores[1].CFrame = a.upper.CFrame
	a.cores[2].CFrame = a.fore.CFrame
	local fwd = (hand - elbow).Magnitude > 0.01 and (hand - elbow).Unit or dir
	local palm = CFrame.lookAt(hand, hand + fwd, pole) * CFrame.new(0, 0, -1.2)
	a.palm.CFrame = palm
	for i, f in a.fingers do
		local curl = fist and math.rad(-95) or math.rad(-12)
		if i == 5 then
			-- the thumb
			f.CFrame = palm * CFrame.new(side * -1.5, 0.2, 0.2) * CFrame.Angles(0, side * math.rad(fist and 70 or 35), 0) * CFrame.new(0, 0, -0.9)
		else
			local x = -1.05 + (i - 1) * 0.7
			f.CFrame = palm * CFrame.new(x, 0, -1.3) * CFrame.Angles(curl, 0, 0) * CFrame.new(0, 0, -1.1)
		end
	end
end

local function updateRivals(dt: number)
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	local shown: Model? = nil
	for _, m in CollectionService:GetTagged("Rival") do
		if not m:IsA("Model") or not m.Parent then
			continue
		end
		local torso = m:FindFirstChild("Torso")
		if not torso or not torso:IsA("BasePart") then
			continue
		end
		local dead = m:GetAttribute("Dead") == true
		if not dead and (torso.Position - camPos).Magnitude < 260 then
			shown = m
		end
		local want = (m:GetAttribute("ArmsOut") == true and not dead) and 1 or 0
		local rec = armsOf[m]
		if want > 0 and not rec then
			local folder = Instance.new("Model")
			folder.Name = "ShadeArms"
			folder.Parent = fx
			rec = { L = buildArm(folder), R = buildArm(folder), model = folder, k = 0 }
			armsOf[m] = rec
		end
		if rec then
			rec.k += (want - rec.k) * math.min(1, dt * 3)
			if want == 0 and rec.k < 0.02 then
				rec.model:Destroy()
				armsOf[m] = nil
			else
				for _, side in { "L", "R" } do
					local a = side == "L" and rec.L or rec.R
					local target = m:GetAttribute("Arm" .. side)
					poseArm(a, torso, side == "L" and -1 or 1, typeof(target) == "Vector3" and target or nil, m:GetAttribute("Arm" .. side .. "Fist") == true, dt)
					setArmLook(a, rec.k)
				end
			end
		end
	end
	for m, rec in armsOf do
		if not m.Parent then
			rec.model:Destroy()
			armsOf[m] = nil
		end
	end
	-- the bar
	if shown then
		bossPanel.Visible = true
		local name = shown:GetAttribute("BossName") or Config.RivalName
		local title = shown:GetAttribute("BossTitle") or Config.RivalTitle
		bossName.Text = string.format("%s  -  %s", tostring(name), tostring(title))
		local hp = tonumber(shown:GetAttribute("BossHP")) or 0
		local max = math.max(1, tonumber(shown:GetAttribute("BossMax")) or 1)
		local k = math.clamp(hp / max, 0, 1)
		bossFill.Size = bossFill.Size:Lerp(UDim2.fromScale(k, 1), math.min(1, dt * 8))
	else
		bossPanel.Visible = false
	end
end

------------------------------------------------------------------------
-- the STILL CUT (and his)
------------------------------------------------------------------------

-- (v2.8.1) a cut is drawn with beams: tapered (thin - thick - thin), a white core in a pale blue glow, a slight curve
type Slash = { anchor: BasePart, beams: { Beam }, w: number }
type Cut = { lines: { Slash }, alive: boolean, cc: ColorCorrectionEffect?, blur: BlurEffect?, sphere: BasePart?, ring: Model?, near: boolean }

local function slashAt(point: Vector3, dir: Vector3, L: number, w: number, rng: Random): Slash
	local anchor = Instance.new("Part")
	anchor.Name = "Slash"
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = CFrame.new(point)
	anchor.Parent = fx
	local side = dir:Cross(Vector3.yAxis)
	if side.Magnitude < 0.1 then
		side = dir:Cross(Vector3.xAxis)
	end
	side = side.Unit * (rng:NextNumber() < 0.5 and -1 or 1)
	local function att(pos: Vector3): Attachment
		local a = Instance.new("Attachment")
		a.WorldPosition = pos
		a.Parent = anchor
		return a
	end
	local a0 = att(point - dir * L * 0.5)
	local am = att(point + side * L * 0.06)
	local a1 = att(point + dir * L * 0.5)
	local beams = {}
	local function beam(from: Attachment, to: Attachment, w0: number, w1: number, color: Color3, transp: number, glow: number)
		local b = Instance.new("Beam")
		b.Attachment0 = from
		b.Attachment1 = to
		b.Width0 = w0
		b.Width1 = w1
		b.FaceCamera = true
		b.Segments = 4
		b.LightEmission = glow
		b.LightInfluence = 0
		b.Color = ColorSequence.new(color)
		b.Transparency = NumberSequence.new(transp)
		b.Parent = anchor
		b:SetAttribute("W0", w0)
		b:SetAttribute("W1", w1)
		table.insert(beams, b)
	end
	-- the glow first (wider, faint), then the core
	beam(a0, am, 0, w * 3.2, Color3.fromRGB(130, 190, 255), 0.6, 1)
	beam(am, a1, w * 3.2, 0, Color3.fromRGB(130, 190, 255), 0.6, 1)
	beam(a0, am, 0, w, Color3.fromRGB(245, 250, 255), 0, 1)
	beam(am, a1, w, 0, Color3.fromRGB(245, 250, 255), 0, 1)
	return { anchor = anchor, beams = beams, w = w }
end
local cuts: { [number]: Cut } = {}

local function bodiesNear(center: Vector3, r: number): { BasePart }
	local out = {}
	local function add(m: Instance)
		local t = m:FindFirstChild("Torso")
		if t and t:IsA("BasePart") and (t.Position - center).Magnitude <= r and not m:GetAttribute("Dead") then
			table.insert(out, t)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character and p.UserId ~= player.UserId then
			add(p.Character)
		end
	end
	local npcs = workspace:FindFirstChild("NPCs")
	if npcs then
		for _, m in npcs:GetChildren() do
			add(m)
		end
	end
	return out
end

local function bandsOn(on: boolean)
	bands.Visible = on
end

local function stillBegin(payload)
	local center = typeof(payload.p) == "Vector3" and payload.p or nil
	if not center then
		return
	end
	local R = tonumber(payload.r) or 30
	local dur = tonumber(payload.d) or 2.5
	local seed = tonumber(payload.seed) or math.random(1, 1e6)
	local rival = payload.rival == true
	local rng = Random.new(seed)
	local cam = workspace.CurrentCamera
	local dist = cam and (cam.CFrame.Position - center).Magnitude or math.huge
	local near = dist < R + (rival and 40 or 140)
	local cut: Cut = { lines = {}, alive = true, near = near }
	cuts[seed] = cut
	if near then
		local strength = rival and 0.6 or 1
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "StillCut"
		cc.Brightness = 0.35 * strength
		cc.TintColor = Color3.fromRGB(210, 235, 255)
		cc.Parent = Lighting
		TweenService:Create(cc, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
			Brightness = -0.05 * strength, Contrast = 0.45 * strength, Saturation = -0.75 * strength,
			TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(140, 190, 255), strength),
		}):Play()
		local blur = Instance.new("BlurEffect")
		blur.Name = "StillCutBlur"
		blur.Size = 0
		blur.Parent = Lighting
		TweenService:Create(blur, TweenInfo.new(0.3), { Size = 4 * strength }):Play()
		cut.cc = cc
		cut.blur = blur
		if not rival then
			bandsOn(true)
		end
		SoundLibrary.Play("timeStop", nil, 0.6, 1.7)
		Cam.Shake(0.5)
	end
	if rival then
		-- a ring on the ground: get out of it
		local ring = Instance.new("Model")
		ring.Name = "StillRing"
		local n = 40
		for k = 0, n - 1 do
			local a = 2 * math.pi * k / n
			local seg = part("RingSeg", Vector3.new(2 * math.pi * R / n * 0.8, 0.12, 0.5),
				CFrame.new(center + Vector3.new(R * math.cos(a), -2.6, R * math.sin(a))) * CFrame.Angles(0, -a - math.pi / 2, 0), PALE)
			seg.Transparency = 0.2
			seg.Parent = ring
		end
		local disc = part("RingDisc", Vector3.new(0.1, R * 2, R * 2), CFrame.new(center + Vector3.new(0, -2.7, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(120, 170, 255), Enum.Material.Neon, Enum.PartType.Cylinder)
		disc.Transparency = 0.85
		disc.Parent = ring
		ring.Parent = fx
		cut.ring = ring
	else
		local sphere = part("StillSphere", Vector3.new(4, 4, 4), CFrame.new(center), Color3.fromRGB(120, 180, 255), Enum.Material.ForceField, Enum.PartType.Ball)
		sphere.Parent = fx
		TweenService:Create(sphere, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = Vector3.new(R * 2, R * 2, R * 2) }):Play()
		cut.sphere = sphere
	end
	-- the cuts appear one after the other
	task.spawn(function()
		local n = rival and 22 or 64
		local gap = dur * 0.85 / n
		for i = 1, n do
			if not cut.alive then
				return
			end
			local point
			local targets = bodiesNear(center, R)
			if #targets > 0 and rng:NextNumber() < 0.5 then
				local t = targets[rng:NextInteger(1, #targets)]
				point = t.Position + Vector3.new(rng:NextNumber(-1.5, 1.5), rng:NextNumber(-1.5, 2), rng:NextNumber(-1.5, 1.5))
			elseif rival then
				local a = rng:NextNumber(0, math.pi * 2)
				local d = R * math.sqrt(rng:NextNumber())
				point = center + Vector3.new(math.cos(a) * d, rng:NextNumber(-2, 5), math.sin(a) * d)
			else
				local v = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.6, 1), rng:NextNumber(-1, 1))
				v = v.Magnitude > 0.01 and v.Unit or Vector3.xAxis
				point = center + v * R * rng:NextNumber() ^ (1 / 3)
			end
			local L = rival and rng:NextNumber(6, 14) or rng:NextNumber(10, 26)
			local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.8, 0.8), rng:NextNumber(-1, 1))
			dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.xAxis
			-- (v2.8.1) a tapered, slightly curved slash that flashes in thick and settles thin
			local sl = slashAt(point, dir, L, rival and 0.16 or 0.12, rng)
			for _, b in sl.beams do
				local w0, w1 = b.Width0, b.Width1
				b.Width0, b.Width1 = w0 * 2.2, w1 * 2.2
				TweenService:Create(b, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Width0 = w0, Width1 = w1 }):Play()
			end
			table.insert(cut.lines, sl)
			if cut.near and i % 3 == 0 then
				SoundLibrary.Play("slash", point, 0.25, 1.5 + rng:NextNumber() * 0.3)
			end
			task.wait(gap)
		end
	end)
end

local function stillEnd(payload)
	local seed = tonumber(payload.seed)
	local cut = seed and cuts[seed]
	local center = typeof(payload.p) == "Vector3" and payload.p or Vector3.zero
	if not cut then
		-- (joined in the middle of it / missed the start): only the bang
		local cam = workspace.CurrentCamera
		if cam and (cam.CFrame.Position - center).Magnitude < 120 then
			Cam.Shake(0.8)
		end
		return
	end
	cuts[seed :: number] = nil
	cut.alive = false
	-- the blade clicks shut: every cut flashes wide, then closes to nothing
	for _, l in cut.lines do
		for _, b in l.beams do
			local w0, w1 = b:GetAttribute("W0") or b.Width0, b:GetAttribute("W1") or b.Width1
			b.Width0, b.Width1 = w0 * 3, w1 * 3
			TweenService:Create(b, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Width0 = 0, Width1 = 0 }):Play()
		end
		Debris:AddItem(l.anchor, 0.5)
	end
	if cut.sphere then
		local s = cut.sphere
		TweenService:Create(s, TweenInfo.new(0.4), { Size = s.Size * 1.15, Transparency = 1 }):Play()
		Debris:AddItem(s, 0.45)
	end
	if cut.ring then
		cut.ring:Destroy()
	end
	if cut.near then
		bandsOn(false)
		local flash = UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(230, 244, 255), BackgroundTransparency = 0.15, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = gui })
		TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		Debris:AddItem(flash, 0.55)
		Cam.Shake(1.2)
		SoundLibrary.Play("clink", nil, 1, 0.8)
	end
	if cut.cc then
		local cc = cut.cc
		local tw = TweenService:Create(cc, TweenInfo.new(0.6), { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = Color3.new(1, 1, 1) })
		tw:Play()
		Debris:AddItem(cc, 0.65)
	end
	if cut.blur then
		local b = cut.blur
		TweenService:Create(b, TweenInfo.new(0.5), { Size = 0 }):Play()
		Debris:AddItem(b, 0.55)
	end
end

-- the picture tears: thin bright bands that jump about while the world stands still
local function updateBands()
	if not bands.Visible then
		return
	end
	for _, b in bands:GetChildren() do
		if b:IsA("Frame") and math.random() < 0.5 then
			b.Position = UDim2.new(math.random(-20, 20) / 1000, 0, math.random(), 0)
			b.Size = UDim2.new(1, 0, 0, math.random(1, 7))
			b.BackgroundTransparency = 0.55 + math.random() * 0.4
		end
	end
end

------------------------------------------------------------------------
-- small effects
------------------------------------------------------------------------

local function flashBall(pos: Vector3, color: Color3, size: number, life: number)
	local b = part("Flash", Vector3.new(1, 1, 1), CFrame.new(pos), color, Enum.Material.Neon, Enum.PartType.Ball)
	b.Transparency = 0.2
	b.Parent = fx
	TweenService:Create(b, TweenInfo.new(life, Enum.EasingStyle.Quad), { Size = Vector3.new(size, size, size), Transparency = 1 }):Play()
	Debris:AddItem(b, life + 0.05)
end

local function shockRing(pos: Vector3, radius: number, color: Color3)
	local r = part("Shock", Vector3.new(0.2, 2, 2), CFrame.new(pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, Enum.PartType.Cylinder)
	r.Transparency = 0.3
	r.Parent = fx
	TweenService:Create(r, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Size = Vector3.new(0.2, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(r, 0.5)
end

local function slamFX(payload)
	local p = typeof(payload.p) == "Vector3" and payload.p or nil
	if not p then
		return
	end
	if payload.ph == "tele" then
		local at = tonumber(payload.at) or (now() + 0.9)
		local ring = part("SlamWarn", Vector3.new(0.12, 20, 20), CFrame.new(p + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(150, 110, 255), Enum.Material.Neon, Enum.PartType.Cylinder)
		ring.Transparency = 0.85
		ring.Parent = fx
		local inner = part("SlamFill", Vector3.new(0.14, 1, 1), CFrame.new(p + Vector3.new(0, 0.17, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(190, 120, 255), Enum.Material.Neon, Enum.PartType.Cylinder)
		inner.Transparency = 0.5
		inner.Parent = fx
		local t = math.max(0.1, at - now())
		TweenService:Create(inner, TweenInfo.new(t, Enum.EasingStyle.Linear), { Size = Vector3.new(0.14, 20, 20) }):Play()
		Debris:AddItem(ring, t + 0.1)
		Debris:AddItem(inner, t + 0.1)
	else
		shockRing(p, 16, Color3.fromRGB(170, 140, 255))
		flashBall(p, Color3.fromRGB(190, 170, 255), 9, 0.35)
		local cam = workspace.CurrentCamera
		if cam and (cam.CFrame.Position - p).Magnitude < 70 then
			Cam.Shake(1.4)
		end
		for _ = 1, 10 do
			local chunk = part("SlamChunk", Vector3.new(0.6, 0.6, 0.6) * (0.6 + math.random()), CFrame.new(p + Vector3.new(math.random(-3, 3), 0.5, math.random(-3, 3))), Color3.fromRGB(40, 32, 30), Enum.Material.Basalt)
			chunk.Anchored = false
			chunk.Parent = fx
			chunk.AssemblyLinearVelocity = Vector3.new(math.random(-30, 30), math.random(30, 60), math.random(-30, 30))
			Debris:AddItem(chunk, 2.5)
		end
	end
end

local function blinkFX(payload)
	local a, b = payload.a, payload.b
	if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
		return
	end
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	if len < 0.5 then
		return
	end
	local streak = part("Blink", Vector3.new(0.35, 0.35, len), CFrame.lookAt(mid, b), Color3.fromRGB(220, 236, 255))
	streak.Transparency = 0.1
	streak.Parent = fx
	local glow = part("BlinkGlow", Vector3.new(1.4, 1.4, len), CFrame.lookAt(mid, b), Color3.fromRGB(120, 160, 255))
	glow.Transparency = 0.7
	glow.Parent = fx
	TweenService:Create(streak, TweenInfo.new(0.35), { Transparency = 1, Size = Vector3.new(0.05, 0.05, len) }):Play()
	TweenService:Create(glow, TweenInfo.new(0.35), { Transparency = 1 }):Play()
	Debris:AddItem(streak, 0.4)
	Debris:AddItem(glow, 0.4)
	flashBall(a, Color3.fromRGB(140, 170, 255), 6, 0.3)
	flashBall(b, Color3.fromRGB(140, 170, 255), 6, 0.3)
end

local function crescentFX(payload)
	local p, d = payload.p, payload.d
	if typeof(p) ~= "Vector3" then
		return
	end
	d = typeof(d) == "Vector3" and d.Magnitude > 0.01 and d.Unit or Vector3.xAxis
	local base = CFrame.lookAt(p, p + d)
	local tilt = math.random() * math.pi
	for k = 0, 8 do
		local a = -math.pi / 2 + k * math.pi / 8
		local pos = base * CFrame.Angles(0, 0, tilt) * CFrame.new(math.cos(a) * 2.6, math.sin(a) * 2.6, 0)
		local seg = part("Crescent", Vector3.new(0.12, 0.9, 0.12), pos * CFrame.Angles(0, 0, a), Color3.fromRGB(230, 244, 255))
		seg.Transparency = 0.15
		seg.Parent = fx
		TweenService:Create(seg, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		Debris:AddItem(seg, 0.3)
	end
end

local function offeringFX(payload)
	local p = typeof(payload.p) == "Vector3" and payload.p or nil
	if not p then
		return
	end
	local holder = part("Offering", Vector3.new(1, 1, 1), CFrame.new(p), Color3.new(0, 0, 0))
	holder.Transparency = 1
	holder.Parent = fx
	local e = emitter(holder, {
		Rate = 0,
		Lifetime = NumberRange.new(0.6, 1.4),
		Speed = NumberRange.new(10, 24),
		SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(200, 20, 10)),
		LightEmission = 1,
		Texture = "rbxasset://textures/particles/fire_main.dds",
	})
	e:Emit(80)
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(255, 110, 40)
	l.Range = 30
	l.Brightness = 6
	l.Parent = holder
	TweenService:Create(l, TweenInfo.new(1.4), { Brightness = 0 }):Play()
	Debris:AddItem(holder, 2)
end

local function fallFX()
	local f = UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(30, 4, 2), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 45, Parent = gui })
	TweenService:Create(f, TweenInfo.new(0.5), { BackgroundTransparency = 0 }):Play()
	SoundLibrary.Play("fallingWhistle", nil, 0.7, 0.7)
	Cam.Shake(0.8)
	task.delay(1.4, function()
		TweenService:Create(f, TweenInfo.new(0.9), { BackgroundTransparency = 1 }):Play()
		task.wait(0.95)
		f:Destroy()
	end)
end

------------------------------------------------------------------------

function SwordClient.Init()
	task.defer(function()
		local pg = player:WaitForChild("PlayerGui")
		local sg = UI.make("ScreenGui", { Name = "StillwaterSummon", ResetOnSpawn = false, Parent = pg })
		local b = UI.button({ Text = "SUMMON STILLWATER", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -150), Size = UDim2.fromOffset(210, 34), Parent = sg }, function()
			SwordRemote:FireServer("summon")
		end)
		local function refresh()
			b.Visible = (player:GetAttribute("SwordStage") or 0) >= 4
			b.Text = player:GetAttribute("StillwaterSummoned") and "DISMISS STILLWATER" or "SUMMON STILLWATER"
		end
		refresh()
		player:GetAttributeChangedSignal("SwordStage"):Connect(refresh)
		player:GetAttributeChangedSignal("StillwaterSummoned"):Connect(refresh)
	end)
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		atmDefaults = { Density = atm.Density, Offset = atm.Offset, Color = atm.Color, Decay = atm.Decay, Glare = atm.Glare, Haze = atm.Haze }
	end
	fx = Instance.new("Folder")
	fx.Name = "SwordFX"
	fx.Parent = workspace
	gui = UI.make("ScreenGui", { Name = "Sword", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 8, Parent = player:WaitForChild("PlayerGui") })
	tracker = UI.panel({ Name = "SwordTracker", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 158), Size = UDim2.fromOffset(250, 54), Accent = BLOOD, Visible = false, Parent = gui })
	trackTitle = UI.label({ Text = "", Font = UI.FONT_TITLE, TextSize = 13, TextColor3 = BLOOD, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -20, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, Parent = tracker })
	trackText = UI.label({ Text = "", TextSize = 14, TextWrapped = true, Position = UDim2.fromOffset(12, 22), Size = UDim2.new(1, -20, 0, 30), TextYAlignment = Enum.TextYAlignment.Top, Parent = tracker })
	subPanel = UI.panel({ Name = "Subtitle", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -150), Size = UDim2.fromOffset(640, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.25, Accent = BLOOD, Visible = false, Parent = gui })
	local sp = UI.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = subPanel })
	UI.make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10), Parent = sp })
	UI.make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sp })
	subName = UI.label({ Text = "", Font = UI.FONT_TITLE, TextSize = 15, TextColor3 = BLOOD, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, Parent = sp })
	subText = UI.label({ Text = "", TextSize = 19, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = sp })
	UI.make("UIScale", { Scale = math.min(1, (workspace.CurrentCamera.ViewportSize.X - 24) / 640), Parent = subPanel })
	bossPanel = UI.make("Frame", { Name = "BossBar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.fromOffset(540, 40), BackgroundTransparency = 1, Visible = false, Parent = gui })
	bossName = UI.label({ Text = "", Font = UI.FONT_TITLE, TextSize = 17, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4, Size = UDim2.new(1, 0, 0, 20), Parent = bossPanel })
	local back = UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(14, 10, 10), BackgroundTransparency = 0.15, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 12), Parent = bossPanel })
	UI.make("UIStroke", { Color = Color3.fromRGB(90, 20, 26), Thickness = 1, Parent = back })
	bossFill = UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(200, 34, 44), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = back })
	for _, mark in { 0.6, 0.3 } do
		UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(240, 230, 220), BackgroundTransparency = 0.3, BorderSizePixel = 0, Position = UDim2.new(mark, -1, 0, 0), Size = UDim2.new(0, 2, 1, 0), ZIndex = 2, Parent = back })
	end
	UI.make("UIScale", { Scale = math.min(1, (workspace.CurrentCamera.ViewportSize.X - 24) / 540), Parent = bossPanel })
	bands = UI.make("Frame", { Name = "StillBands", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 30, Parent = gui })
	for i = 1, 14 do
		UI.make("Frame", { BackgroundColor3 = i % 3 == 0 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(120, 190, 255), BackgroundTransparency = 0.7, BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 2), Position = UDim2.fromScale(0, i / 15), ZIndex = 30, Parent = bands })
	end

	for _, attr in { "SwordStage", "SwordProg", "SwordGoal", "ObjectiveText", "HasStillCut", "StillCutReady" } do
		player:GetAttributeChangedSignal(attr):Connect(updateTracker)
	end
	updateTracker()

	SwordRemote.OnClientEvent:Connect(function(action, a, b)
		if action == "note" and typeof(a) == "string" then
			QuestClient.Toast(a, typeof(b) == "string" and b or nil)
		elseif action == "say" and typeof(a) == "string" and typeof(b) == "table" then
			say(a, b)
		elseif action == "fall" then
			fallFX()
		elseif action == "learned" then
			task.delay(1.5, showCard)
		end
	end)
	Events.On("stillcut", function(payload)
		if payload.ph == "begin" then
			stillBegin(payload)
		else
			stillEnd(payload)
		end
	end)
	Events.On("shadeslam", slamFX)
	Events.On("blink", blinkFX)
	Events.On("crescent", crescentFX)
	Events.On("offering", offeringFX)
	Events.On("shadecatch", function(payload)
		if typeof(payload.p) == "Vector3" then
			flashBall(payload.p, Color3.fromRGB(170, 190, 255), 3, 0.2)
			SoundLibrary.Play("metal", payload.p, 0.5, 1.6)
		end
	end)
	Events.On("shadethrow", function(payload)
		if typeof(payload.p) == "Vector3" then
			SoundLibrary.Play("kickSwoosh", payload.p, 1, 0.6)
		end
	end)
	Events.On("pitopen", function(payload)
		local cam = workspace.CurrentCamera
		if typeof(payload.p) == "Vector3" and cam and (cam.CFrame.Position - payload.p).Magnitude < 90 then
			Cam.Shake(1.2)
			flashBall(payload.p, Color3.fromRGB(255, 80, 30), 16, 0.6)
		end
	end)
	UserInputService.InputBegan:Connect(function(io)
		if card and io.KeyCode == Enum.KeyCode.Escape then
			closeCard()
		end
	end)

	local bandClock = 0
	local trackClock = 0
	RunService:BindToRenderStep("SwordClient", Enum.RenderPriority.Last.Value, function(dt)
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local camPos = cam.CFrame.Position
		setPit(inPit(camPos))
		if embers then
			embers.CFrame = CFrame.new(camPos)
		end
		updateHole(dt)
		updateRivals(dt)
		bandClock += dt
		if bandClock > 0.05 then
			bandClock = 0
			updateBands()
		end
		trackClock += dt
		if trackClock > 0.5 then
			trackClock = 0
			updateTracker()
		end
	end)
end

return SwordClient
