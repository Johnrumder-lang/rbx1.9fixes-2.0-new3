--!nonstrict
-- QuestClient (v2.0): the Steel Ball Master's questline on this screen (QuestService has the rules).
--   * F at the master: what she says (a compact panel at the bottom, Accept / Close)
--   * the quest tracker (right, under TOP KILLS) and short notes at the top ("Steel ball kill 3/5")
--   * a "!" (she has something for you) or "?" (go back to her) over her head; she is a tsundere (turns to you,
--     glances, looks away, peeks, blushes, grumbles in speech bubbles)
--   * quest 3: the SPIN in the construction site - only you see it while you look for it, and it hums (SpinFX)
--   * the cutscene when you touch it: the hand reaches for it, its light pours into you, and the moment you start
--     to spin the cutscene is over (v2.0)
--   * (v2.0) she only talks to you once you touched a Spin Circle: before that a sulky speech bubble. When one
--     appears everybody gets a note (no marker); whoever finds it fills with the Spin (everybody sees it)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))

local Modules = script.Parent
local UI = require(Modules:WaitForChild("UI"))
local Input = require(Modules:WaitForChild("Input"))
local Cam = require(Modules:WaitForChild("CameraController"))
local SpinFX = require(Modules:WaitForChild("SpinFX"))

local QuestRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Quest") :: RemoteEvent

local C = UI.C
local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 214, 70)

local QuestClient = {}

local controller = nil
local gui: ScreenGui
local tracker: Frame
local trackTitle: TextLabel
local trackText: TextLabel
local toastHolder: Frame
local dialog: Frame? = nil
local dialogConn: RBXScriptConnection? = nil
local bars: { Frame } = {}
local relicVis: SpinFX.Relic? = nil
local relicHum: Sound? = nil
local relicBoost = 0 -- (0..1: the relic speeds up while your hand reaches for it)
local relicHold = 0 -- (it stays visible a moment after the stage moved on: the cutscene still needs it)
local inCutscene = false

function QuestClient.SetController(c)
	controller = c
end

------------------------------------------------------------------------
-- the tracker and the notes
------------------------------------------------------------------------

local BACK = "Go back to the " .. Config.SpinMasterTitle
local TRACK = {
	[1] = { "QUEST 1/3  -  STEEL BALL KILLS", "Kill with steel balls, do not die  %d/%d" },
	[2] = { "QUEST 1/3  -  DONE", BACK },
	[3] = { "QUEST 2/3  -  THROW AND FETCH", "Throw a ball, pick it up again (one life)  %d/%d" },
	[4] = { "QUEST 2/3  -  DONE", BACK },
	[5] = { "QUEST 3/3  -  THE SPIN", "Find it in the construction site. Listen for the hum" },
	[6] = { "QUEST 3/3  -  DONE", BACK },
}

local function stage(): number
	local s = player:GetAttribute("QuestStage")
	return typeof(s) == "number" and s or 0
end

local function updateTracker()
	local s = stage()
	local t = TRACK[s]
	tracker.Visible = t ~= nil and not inCutscene
	if not t then
		return
	end
	trackTitle.Text = t[1]
	local prog = player:GetAttribute("QuestProg") or 0
	local goal = player:GetAttribute("QuestGoal") or 0
	trackText.Text = string.format(t[2], prog, goal)
	trackTitle.TextColor3 = (s % 2 == 0) and C.good or GOLD
end

local function toast(text: string, kind: string?)
	local col = kind == "fail" and C.bad or (kind == "done" and C.good or (kind == "new" and GOLD or C.text))
	local p = UI.panel({ Size = UDim2.fromOffset(460, 34), BackgroundTransparency = 0.2, Accent = col, Parent = toastHolder })
	UI.label({ Text = text, Font = UI.FONT_TITLE, TextSize = 17, TextColor3 = col, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = p })
	SoundLibrary.Play(kind == "done" and "questDone" or (kind == "fail" and "questFail" or "questDing"), nil, 0.8) -- (v2.8.2: little tunes)
	task.delay(4.5, function()
		if p.Parent then
			TweenService:Create(p, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			for _, d in p:GetDescendants() do
				if d:IsA("TextLabel") then
					TweenService:Create(d, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
				elseif d:IsA("Frame") then
					TweenService:Create(d, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
				end
			end
			task.wait(0.45)
			p:Destroy()
		end
	end)
end
QuestClient.Toast = toast

------------------------------------------------------------------------
-- the master (a tsundere: she glances at you, turns her head away with a "hmph", peeks at you from the corner of
-- her eye, blushes when you talk to her - and never admits anything)
------------------------------------------------------------------------

local master: Model? = nil
local headParts: { [BasePart]: CFrame } = {} -- everything on her head: offset from the head
local tailPivot: { [BasePart]: { pivot: CFrame, side: number } } = {}
local headBase: CFrame? = nil
local bodyBase: CFrame? = nil -- where she stands (the server's pose); she turns on this screen only
local bodyYaw = 0
local marker: TextLabel? = nil
local face: any = nil -- { eyes = { {open, closed, iris} }, blush = { Frame }, brows = { Frame }, mouth = Frame }
local quip: BillboardGui? = nil
local mood = { phase = "idle", phaseEnd = 0, near = false, nextQuip = 0, blush = 0.7, flusterUntil = 0, eyesClosedUntil = 0 }

-- (v2.0) what she mutters: Config.SpinMasterQuips (change them there)
local QUIPS = Config.SpinMasterQuips

local function findMaster(): Model?
	if master and master.Parent then
		return master
	end
	local map = workspace:FindFirstChild("Map")
	local m = map and map:FindFirstChild("SteelBallMaster", true)
	if not m or not m:IsA("Model") then
		return nil
	end
	local head = m:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	master = m
	headBase = head.CFrame
	bodyBase = m:GetPivot()
	bodyYaw = 0
	table.clear(headParts)
	table.clear(tailPivot)
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") and p:GetAttribute("OnHead") then
			headParts[p] = head.CFrame:ToObjectSpace(p.CFrame)
			local piv = p:GetAttribute("TailPivot")
			if typeof(piv) == "Vector3" then
				-- (TailPivot is in head space: where the tail hangs from, relative to the head)
				tailPivot[p] = { pivot = CFrame.new(piv), side = p:GetAttribute("Tail") or 1 }
			end
		end
	end
	-- her face (drawn on a SurfaceGui: QuestService buildFace)
	local plate = m:FindFirstChild("FacePlate")
	local gui = plate and plate:FindFirstChild("Face")
	if gui then
		local eyes = {}
		for _, n in { "EyeL", "EyeR" } do
			local e = gui:FindFirstChild(n)
			local open = e and e:FindFirstChild("Open")
			if e and open then
				table.insert(eyes, { open = open, closed = e:FindFirstChild("Closed"), iris = open:FindFirstChild("Iris") })
			end
		end
		face = {
			eyes = eyes,
			blush = { gui:FindFirstChild("BlushL"), gui:FindFirstChild("BlushR") },
			brows = { gui:FindFirstChild("BrowL"), gui:FindFirstChild("BrowR") },
			mouth = gui:FindFirstChild("Mouth"),
		}
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "QuestMarker"
	bb.Size = UDim2.fromOffset(60, 60)
	bb.StudsOffset = Vector3.new(0, 3.4, 0)
	bb.MaxDistance = 90
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false -- (walls hide it)
	bb.Parent = head
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Sarpanch
	l.TextScaled = true
	l.TextColor3 = GOLD
	l.TextStrokeTransparency = 0.2
	l.Text = ""
	l.Parent = bb
	marker = l
	return m
end

-- a speech bubble over her head (only on this screen)
local function say(text: string)
	local m = findMaster()
	local head = m and m:FindFirstChild("Head")
	if not head then
		return
	end
	if quip then
		quip:Destroy()
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "Quip"
	bb.Size = UDim2.fromOffset(250, 44)
	bb.StudsOffset = Vector3.new(0, 4.6, 0)
	bb.MaxDistance = 45
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	bb.Parent = head
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 1)
	l.Position = UDim2.fromScale(0.5, 1)
	l.Size = UDim2.fromOffset(0, 30)
	l.AutomaticSize = Enum.AutomaticSize.X
	l.BackgroundColor3 = Color3.fromRGB(255, 250, 240)
	l.BackgroundTransparency = 0.05
	l.Font = Enum.Font.Sarpanch
	l.TextSize = 16
	l.TextColor3 = Color3.fromRGB(70, 30, 36)
	l.Text = text
	l.Parent = bb
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = l
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 0) -- (v2.0: a square speech box)
	c.Parent = l
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(118, 30, 44)
	st.Thickness = 2
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = l
	quip = bb
	task.delay(3.2, function()
		if quip == bb then
			TweenService:Create(l, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
			TweenService:Create(st, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			task.wait(0.45)
			if quip == bb then
				quip = nil
			end
			bb:Destroy()
		end
	end)
end

local function sayFrom(list: { string }?)
	if typeof(list) == "table" and #list > 0 then
		say(list[math.random(1, #list)])
	end
end

local function touched(): boolean
	return player:GetAttribute("SpinCircle") == true
end

-- she gets flustered (you accepted a quest, you learned the Spin)
local function fluster(list: { string }?)
	local now = os.clock()
	mood.flusterUntil = now + 2.6
	mood.eyesClosedUntil = now + 0.7
	mood.phase = "away"
	mood.phaseEnd = now + 2.6
	if list then
		sayFrom(list)
	end
end

local function setFace(blushT: number, eyesClosed: boolean, irisX: number, angry: boolean)
	if not face then
		return
	end
	for _, b in face.blush do
		if b then
			b.BackgroundTransparency = blushT
		end
	end
	for _, e in face.eyes do
		e.open.Visible = not eyesClosed
		if e.closed then
			e.closed.Visible = eyesClosed
		end
		if e.iris then
			e.iris.Position = UDim2.fromScale(0.5 + irisX * 0.16, 0.56)
		end
	end
	for i, b in face.brows do
		if b then
			local side = i == 1 and -1 or 1
			b.Rotation = side * (angry and -18 or -6)
		end
	end
	if face.mouth then
		face.mouth.Size = angry and UDim2.fromOffset(8, 4) or UDim2.fromOffset(10, 3)
	end
end

local function updateMaster(dt: number)
	local m = findMaster()
	if not m then
		return
	end
	local now = os.clock()
	local s = stage()
	if marker then
		if not touched() then
			marker.Text = "" -- (she has nothing for you without the Spin in you)
		elseif s == 0 or s == 6 then
			marker.Text = "!"
		elseif s == 2 or s == 4 then
			marker.Text = "?"
		else
			marker.Text = ""
		end
	end
	local head = m:FindFirstChild("Head")
	local torso = m:FindFirstChild("Torso")
	if not head or not head:IsA("BasePart") or not torso or not torso:IsA("BasePart") or not headBase then
		return
	end
	local c = player.Character
	local me = c and c:FindFirstChild("Head")
	local dist = (me and me:IsA("BasePart")) and (me.Position - head.Position).Magnitude or math.huge
	local near = dist < 22
	-- her whole body turns to you (all the way while you talk, half way when she glances, barely when she sulks)
	local headWas = head.CFrame
	if bodyBase then
		local want = 0
		if near and me and me:IsA("BasePart") then
			local to = bodyBase:PointToObjectSpace(me.Position)
			local a = math.atan2(-to.X, -to.Z)
			local share = (mood.phase == "talk" and 1) or (mood.phase == "glance" and 0.7) or (mood.phase == "away" and 0.35) or 0.5
			want = math.clamp(a * share, -2.8, 2.8)
		end
		local nextYaw = bodyYaw + (want - bodyYaw) * math.min(1, dt * 2.6)
		if math.abs(nextYaw - bodyYaw) > 1e-4 then
			bodyYaw = nextYaw
			m:PivotTo(bodyBase * CFrame.Angles(0, bodyYaw, 0))
		end
	end
	-- where you are, seen from her (yaw / pitch for her head)
	local yawTo, pitchTo = 0, 0
	if me and me:IsA("BasePart") then
		local to = torso.CFrame:PointToObjectSpace(me.Position)
		yawTo = math.atan2(-to.X, -to.Z)
		pitchTo = math.clamp(math.atan2(to.Y - 1.5, math.sqrt(to.X * to.X + to.Z * to.Z)), -0.5, 0.5)
	end
	if near and not mood.near then
		-- you came over: a remark, a quick look, then she turns away
		if now > mood.nextQuip and touched() then
			mood.nextQuip = now + 14
			sayFrom(s == 0 and QUIPS.first or (s == 7 and QUIPS.done or ((s % 2 == 0) and QUIPS.back or QUIPS.busy)))
		end
		mood.phase = "glance"
		mood.phaseEnd = now + 1.2 + math.random() * 0.6
	elseif not near and mood.near then
		mood.phase = "idle"
	end
	mood.near = near
	if dialog and near then
		mood.phase = "talk"
	elseif mood.phase == "talk" then
		mood.phase = "away"
		mood.phaseEnd = now + 2
		mood.eyesClosedUntil = now + 0.5
	end
	if near and mood.phase ~= "talk" and now > mood.phaseEnd then
		if mood.phase == "glance" then
			mood.phase = "away"
			mood.phaseEnd = now + 2.4 + math.random() * 1.8
			mood.eyesClosedUntil = now + 0.55 -- (hmph)
		else
			mood.phase = "glance"
			mood.phaseEnd = now + 0.8 + math.random() * 0.6
		end
	end
	local yaw, pitch, irisX = 0, 0, 0
	local flustered = now < mood.flusterUntil
	if mood.phase == "glance" or mood.phase == "talk" then
		yaw = math.clamp(yawTo, -1.0, 1.0)
		pitch = pitchTo
		irisX = math.clamp((yawTo - yaw) * -1.5, -1, 1)
	elseif mood.phase == "away" then
		-- head turned to the other side, chin up... but her eyes still peek at you
		local away = (yawTo >= 0) and -1 or 1
		yaw = math.clamp(yawTo + away * 1.15, -1.25, 1.25)
		pitch = flustered and -0.2 or 0.16
		irisX = away * -0.9
	else
		yaw = math.sin(now * 0.4) * 0.25
	end
	local want = torso.CFrame * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	local nextCF = headWas:Lerp(want, math.min(1, dt * (mood.phase == "away" and 7 or 4.5)))
	head.CFrame = nextCF
	-- the twin tails sway a little (a bit more when she tosses her head)
	local swayA = math.sin(now * 1.4) * 0.05
	local swayB = math.sin(now * 1.1 + 0.7) * 0.06
	for p, off in headParts do
		if p.Parent then
			local tp = tailPivot[p]
			if tp then
				local rot = CFrame.Angles(swayA * tp.side, 0, swayB * tp.side + (mood.phase == "away" and 0.05 * tp.side or 0))
				p.CFrame = nextCF * tp.pivot * rot * tp.pivot:Inverse() * off
			else
				p.CFrame = nextCF * off
			end
		end
	end
	-- the face
	local wantBlush = flustered and 0.05 or (mood.phase == "talk" and 0.25 or (near and 0.45 or 0.75))
	mood.blush += (wantBlush - mood.blush) * math.min(1, dt * 4)
	setFace(mood.blush, now < mood.eyesClosedUntil, irisX, mood.phase ~= "idle" and not flustered)
end

------------------------------------------------------------------------
-- what she says
------------------------------------------------------------------------

local function closeDialog()
	if dialogConn then
		dialogConn:Disconnect()
		dialogConn = nil
	end
	if dialog then
		dialog:Destroy()
		dialog = nil
		Input.promptOpen = false
		GuiService.SelectedObject = nil
	end
end

local function openDialog(d: any)
	closeDialog()
	if typeof(d) ~= "table" or typeof(d.text) ~= "string" then
		return
	end
	Input.promptOpen = true
	local w = 600
	local p = UI.panel({
		Name = "QuestDialog",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -36),
		Size = UDim2.fromOffset(w, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.12,
		Accent = GOLD,
		Parent = gui,
	})
	UI.make("UIScale", { Scale = math.min(1, (workspace.CurrentCamera.ViewportSize.X - 24) / w), Parent = p })
	-- (v2.0 fix) the content sits in its own frame: the list layout used to stack the panel's accent bar too, and
	-- the box grew to the top of the screen
	local inner = UI.make("Frame", { Name = "Inner", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = p })
	UI.make("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12), Parent = inner })
	UI.make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = inner })
	UI.label({ Text = tostring(d.name or "STEEL BALL MASTER"), Font = UI.FONT_TITLE, TextSize = 20, TextColor3 = GOLD, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, Parent = inner })
	local body = UI.label({ Text = d.text, MaxVisibleGraphemes = 0, TextSize = 17, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = inner })
	local row = UI.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 3, Parent = inner })
	UI.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
	local first = nil
	if typeof(d.accept) == "string" then
		first = UI.button({ Text = string.upper(d.accept), TextSize = 15, TextColor3 = Color3.fromRGB(20, 18, 14), BackgroundColor3 = GOLD, Size = UDim2.fromOffset(170, 32), LayoutOrder = 1, Parent = row }, function()
			QuestRemote:FireServer("accept")
			closeDialog()
			if d.stage ~= 6 then
				fluster(QUIPS.accept)
			end
		end)
	end
	local closeB = UI.button({ Text = string.upper(tostring(d.close or "Close")), TextSize = 15, Size = UDim2.fromOffset(130, 32), LayoutOrder = 2, Parent = row }, function()
		closeDialog()
	end)
	dialog = p
	if Input.lastDevice == "Gamepad" then
		GuiService.SelectedObject = first or closeB
	end
	-- the words come one after the other (the box already has its full size: nothing jumps)
	local full = d.text
	task.spawn(function()
		local n = 0
		while dialog == p and n < #full do
			n = math.min(#full, n + 3)
			body.MaxVisibleGraphemes = n
			task.wait(0.012)
		end
		if dialog == p then
			body.MaxVisibleGraphemes = -1
		end
	end)
	-- walking away / Esc closes it
	dialogConn = RunService.Heartbeat:Connect(function()
		local m = findMaster()
		local c = player.Character
		local t = c and c:FindFirstChild("Torso")
		local mt = m and m:FindFirstChild("Torso")
		if not t or not mt or (t.Position - mt.Position).Magnitude > Config.QuestTalkRange + 4 then
			closeDialog()
		end
	end)
end

------------------------------------------------------------------------
-- the Spin in the construction site (only while you look for it)
------------------------------------------------------------------------

local function relicPart(): BasePart?
	local map = workspace:FindFirstChild("Map")
	local r = map and map:FindFirstChild("SpinRelic", true)
	return (r and r:IsA("BasePart")) and r or nil
end

local function showRelic(on: boolean)
	if on and not relicVis then
		local r = relicPart()
		if not r then
			return
		end
		local rv = SpinFX.Relic()
		relicVis = rv
		relicHum = SoundLibrary.Loop("relicHum", rv.model.PrimaryPart or rv.model)
		if relicHum then
			relicHum.RollOffMaxDistance = 70
			relicHum:Play()
		end
	elseif not on and relicVis then
		relicVis:Destroy()
		relicVis = nil
		relicHum = nil
	end
end

local function updateRelic(now: number)
	local rv = relicVis
	local r = relicPart()
	if not rv or not r then
		return
	end
	rv:Step(now, r.CFrame * CFrame.new(0, math.sin(now * 1.6) * 0.3, 0), relicBoost)
end

------------------------------------------------------------------------
-- the cutscene
------------------------------------------------------------------------

local function letterbox(on: boolean)
	for i, b in bars do
		b.Visible = true
		local goal = on and UDim2.new(1, 0, 0.12, 0) or UDim2.new(1, 0, 0, 0)
		TweenService:Create(b, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = goal }):Play()
		if not on then
			task.delay(0.55, function()
				if not inCutscene then
					bars[i].Visible = false
				end
			end)
		end
	end
end

local function bigText(text: string, sub: string?)
	local l = UI.label({ Text = text, Font = UI.FONT_TITLE, TextSize = 46, TextColor3 = GOLD, TextStrokeTransparency = 0.3, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.74), Size = UDim2.fromOffset(800, 54), TextTransparency = 1, ZIndex = 30, Parent = gui })
	local s = sub and UI.label({ Text = sub, Font = UI.FONT_BODY, TextSize = 20, TextStrokeTransparency = 0.4, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.74, 30), Size = UDim2.fromOffset(800, 26), TextTransparency = 1, ZIndex = 30, Parent = gui }) or nil
	for _, x in { l, s } do
		if x then
			TweenService:Create(x, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
		end
	end
	task.delay(3.2, function()
		for _, x in { l, s } do
			if x then
				TweenService:Create(x, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end
		task.wait(0.65)
		l:Destroy()
		if s then
			s:Destroy()
		end
	end)
end

local function flash(strength: number, color: Color3?)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "SpinFlash"
	cc.TintColor = color or Color3.fromRGB(255, 236, 170)
	cc.Brightness = strength
	cc.Parent = Lighting
	TweenService:Create(cc, TweenInfo.new(1.4, Enum.EasingStyle.Quad), { Brightness = 0, TintColor = Color3.new(1, 1, 1) }):Play()
	task.delay(1.5, function()
		cc:Destroy()
	end)
end

local function cutscene(relicPos: Vector3)
	local c = controller
	if inCutscene or not c or not c.ready or c.dead or typeof(relicPos) ~= "Vector3" then
		return
	end
	inCutscene = true
	closeDialog()
	updateTracker()
	Input.cutscene = true
	local wasFP = Input.firstPerson
	Input.firstPerson = false
	letterbox(true)
	local t0 = os.clock()
	local torso = c.torso
	local start = torso.Position
	local to = relicPos - start
	Cam.yaw = math.atan2(-to.X, -to.Z)
	c.cutsceneReach = relicPos
	relicHold = os.clock() + 2
	local mid = start:Lerp(relicPos, 0.5) + Vector3.new(0, 0.5, 0)
	local baseA = math.atan2(to.Z, to.X) + math.pi * 0.5
	Cam.override = function(_dt)
		local t = os.clock() - t0
		local focusPos = t < 1.6 and mid or (torso.Parent and torso.Position or mid)
		local a = baseA + t * 0.5
		local r = t < 1.6 and (8 - t * 1.2) or 13
		local h = t < 1.6 and 2 or (3 + math.min(t - 1.6, 3) * 1.2)
		local pos = focusPos + Vector3.new(math.cos(a) * r, h, math.sin(a) * r)
		return CFrame.lookAt(pos, focusPos)
	end
	SoundLibrary.Play("spinPower", nil, 0.5, 1.6)
	-- (v2.0) the relic winds up faster and tighter while your hand reaches for it
	local w0 = os.clock()
	while os.clock() - w0 < 1.4 do
		relicBoost = (os.clock() - w0) / 1.4
		RunService.RenderStepped:Wait()
	end
	relicBoost = 0
	-- it bursts into you: its light pours into your body
	c.cutsceneReach = nil
	relicHold = 0
	showRelic(false)
	SpinFX.Absorb(relicPos, c.character or torso.Parent)
	flash(0.9, Color3.fromRGB(210, 255, 200))
	SoundLibrary.Play("spinPower", nil, 1)
	Cam.Shake(0.8)
	local a = Instance.new("Attachment")
	a.Name = "SpinAura"
	a.Parent = torso
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(GOLD, Config.SpinBallColor)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.5, 1)
	e.Speed = NumberRange.new(5, 10)
	e.SpreadAngle = Vector2.new(180, 40)
	e.RotSpeed = NumberRange.new(-400, 400)
	e.Rate = 120
	e.Parent = a
	local glow = Instance.new("PointLight")
	glow.Color = GOLD
	glow.Range = 14
	glow.Brightness = 2
	glow.Parent = a
	-- limp, up into the air, spinning faster and faster. (v2.0) The cutscene ends right here, as the spin starts:
	-- your own camera is back while you spin
	pcall(function()
		c:Ragdoll(2.8)
	end)
	Cam.override = nil
	letterbox(false)
	Input.cutscene = false
	Input.firstPerson = wasFP
	inCutscene = false
	updateTracker()
	bigText("THE SPIN", BACK)
	local floatT = 1.9
	local f0 = os.clock()
	while os.clock() - f0 < floatT and c.alive and not c.dead and torso.Parent do
		local k = (os.clock() - f0) / floatT
		local tt = os.clock() - f0
		pcall(function()
			torso.AssemblyAngularVelocity = Vector3.new(math.sin(tt * 3) * 2.5, 8 + 22 * k, math.cos(tt * 2.3) * 2.5)
			local p = torso.Position
			local lift = math.clamp((start.Y + 5 - p.Y) * 3, -14, 14)
			torso.AssemblyLinearVelocity = Vector3.new((start.X - p.X) * 2, lift, (start.Z - p.Z) * 2)
		end)
		RunService.Heartbeat:Wait()
	end
	e.Rate = 25
	task.wait(0.6)
	e.Enabled = false
	task.delay(1, function()
		a:Destroy()
	end)
end

------------------------------------------------------------------------

function QuestClient.Init()
	SpinFX.Init()
	gui = UI.make("ScreenGui", { Name = "Quest", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 7, Parent = player:WaitForChild("PlayerGui") })
	for i = 1, 2 do
		local b = UI.make("Frame", {
			Name = "Letterbox",
			AnchorPoint = Vector2.new(0, i == 1 and 0 or 1),
			Position = UDim2.fromScale(0, i == 1 and 0 or 1),
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 20,
			Parent = gui,
		})
		table.insert(bars, b)
	end
	-- (right side, under TOP KILLS)
	tracker = UI.panel({ Name = "QuestTracker", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 158), Size = UDim2.fromOffset(250, 54), Accent = GOLD, Visible = false, Parent = gui })
	trackTitle = UI.label({ Text = "", Font = UI.FONT_TITLE, TextSize = 13, TextColor3 = GOLD, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -20, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, Parent = tracker })
	trackText = UI.label({ Text = "", TextSize = 14, TextWrapped = true, Position = UDim2.fromOffset(12, 22), Size = UDim2.new(1, -20, 0, 30), TextYAlignment = Enum.TextYAlignment.Top, Parent = tracker })
	toastHolder = UI.make("Frame", { Name = "QuestNotes", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150), Size = UDim2.fromOffset(460, 200), BackgroundTransparency = 1, Parent = gui })
	UI.make("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = toastHolder })

	for _, attr in { "QuestStage", "QuestProg", "QuestGoal" } do
		player:GetAttributeChangedSignal(attr):Connect(updateTracker)
	end
	local lastStage = stage()
	player:GetAttributeChangedSignal("QuestStage"):Connect(function()
		local s = stage()
		if lastStage == 5 and s == 6 then
			relicHold = os.clock() + 2.5
		end
		lastStage = s
	end)
	updateTracker()

	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who == player and prompt.Name == "QuestPrompt" and not inCutscene then
			QuestRemote:FireServer("talk")
		end
	end)
	UserInputService.InputBegan:Connect(function(io)
		if Input.IsControlled() then return end
		if dialog and io.KeyCode == Enum.KeyCode.Escape then
			closeDialog()
		end
	end)
	QuestRemote.OnClientEvent:Connect(function(action, a, b, name, c)
		if action == "dialog" then
			openDialog(a)
		elseif action == "notify" and typeof(a) == "string" then
			toast(a, typeof(b) == "string" and b or nil)
		elseif action == "cutscene" then
			task.spawn(cutscene, a)
		elseif action == "snub" and typeof(a) == "string" then
			-- (v2.0) no Spin in you: she won't talk, she sulks
			say(a)
			mood.phase = "away"
			mood.phaseEnd = os.clock() + 2.5
			mood.eyesClosedUntil = os.clock() + 0.6
		elseif action == "circle" then
			if a == "spawn" then
				toast(touched() and "A SPIN CIRCLE appeared somewhere..." or "A SPIN CIRCLE appeared somewhere. Find it first!", "new")
				SoundLibrary.Play("spinPower", nil, 0.5, 0.75)
			elseif a == "gone" and not touched() then
				toast("The Spin Circle faded away", "info")
			end
		elseif action == "spinfill" then
			-- someone stepped into the Spin Circle: the Spin fills their body (everybody sees it)
			if typeof(a) == "Instance" and a:IsA("Model") then
				SpinFX.Fill(a)
			end
			if typeof(b) == "Vector3" then
				SpinFX.Shock(CFrame.new(b), GOLD, 8, 0.8)
			end
			if c == player.UserId then
				flash(0.6, Color3.fromRGB(200, 255, 200))
				bigText("THE SPIN FILLS YOU", Config.SpinMasterTitle .. " will talk to you now - behind the red brick house")
			elseif typeof(name) == "string" then
				toast(name .. " found the Spin Circle", "info")
			end
		elseif action == "learned" then
			fluster(QUIPS.learned)
			flash(0.7, Color3.fromRGB(190, 255, 190))
			bigText("YOU LEARNED THE SPIN", "Your steel balls are green now - and they come back to you")
			SoundLibrary.Play("spinPower", nil, 1, 1.3)
		end
	end)

	-- a hint after a while, for whoever has not met him yet
	task.delay(45, function()
		if stage() == 0 and not touched() then
			toast("Rumour has it Spin Circles appear out of nowhere... rarely.", "info")
		elseif stage() == 0 then
			toast("Rumour has it a " .. Config.SpinMasterTitle .. " camps behind the red brick house... and she bites.", "info")
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		updateMaster(dt)
		showRelic(stage() == 5 or now < relicHold)
		updateRelic(now)
	end)
end

return QuestClient
