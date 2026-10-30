--!nonstrict
-- LedgerClient (v2.1c): everything you SEE of the Black Ledger.
--   * Kuro, the shikigami: built and drawn only on the keeper's screen. He WANDERS around you (he is not stuck to you): he walks to
--     spots around you, stands, looks about - and when you get too far away he runs after you. He talks to you (a plain speech bubble).
--   * the book (F with the ledger in your hand; F again closes it): 1. the FACE  2. the NAME  3. HOW  -> WRITE. Plain black and white.
--   * the writing animation: the picture, the name written letter by letter with a pen, the way it ends, and the time left.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LedgerData = require(Shared:WaitForChild("LedgerData"))
local UI = require(script.Parent:WaitForChild("UI"))
local KuroRig = require(script.Parent:WaitForChild("KuroRig"))
local Input = require(script.Parent:WaitForChild("Input"))

local LedgerClient = {}

local player = Players.LocalPlayer
local Remote: RemoteEvent
local state: any = { kills = 0, needKills = Config.LedgerQuestKills, apples = 0, needApples = Config.LedgerQuestApples, unlocked = false, cooldown = 0 }
local rng = Random.new()

local BG = Color3.fromRGB(12, 12, 14)
local PANEL = Color3.fromRGB(23, 23, 26)
local PANEL2 = Color3.fromRGB(34, 34, 38)
local LINE = Color3.fromRGB(56, 56, 62)
local TEXT = Color3.fromRGB(236, 236, 238)
local DIM = Color3.fromRGB(138, 138, 148)
local FONT = UI.FONT
local FONT_B = UI.FONT_TITLE

local function lbl(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or TEXT
	props.TextSize = (props.TextSize or 14) + 2
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
	return UI.make("TextLabel", props)
end

local function btn(props: { [string]: any }, onClick: () -> ()): TextButton
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or TEXT
	props.TextSize = (props.TextSize or 14) + 2
	props.BackgroundColor3 = props.BackgroundColor3 or PANEL2
	props.BorderSizePixel = 0
	props.AutoButtonColor = true
	local b = UI.make("TextButton", props)
	b.Activated:Connect(onClick)
	return b
end

------------------------------------------------------------------------
-- Kuro's lines (short and plain)
------------------------------------------------------------------------

local function pick(t: { string }): string
	return t[rng:NextInteger(1, #t)]
end

local LINES = {
	first = {
		"Oh. Somebody picked it up.",
		"I'm Kuro. I come with the book.",
		"Don't worry, only you can see me.",
		"When you want to write something, hold it and press F.",
	},
	again = { "Back again.", "Oh, it's you.", "There you are." },
	smear = { "That's not their name.", "Wrong name. Check the face again." },
	nobody = { "They're gone already.", "Nobody there anymore." },
	badself = { "Your own name? No.", "Not yourself. Pick somebody else." },
	badtarget = { "I can't find that one.", "They left." },
	resisted = { "It didn't work. Weird.", "Nothing happened. Something's protecting them." },
	ate = { "You ate it? That was mine.", "...Okay. Fine." },
	cooldown = { "Ink's still wet, give it a second.", "Not yet." },
	idle = {
		"Hey.",
		"Quiet today.",
		"You walk fast.",
		"Got any more apples?",
		"I'm bored.",
		"What are we doing?",
		"Nice weather.",
		"I could eat.",
		"Don't look at me like that.",
		"Is it always this loud here?",
	},
}

local function questLine(): string
	return string.format("%d names written this life.", state.kills or 0)
end

------------------------------------------------------------------------
-- Kuro: appearance, walking about, speaking
------------------------------------------------------------------------

type Kuro = { rig: any, head: BasePart, pos: Vector3, yaw: number, target: Vector3?, idleUntil: number, speed: number, born: number, alive: boolean, mode: string, glance: number, glanceDir: Vector3 }
local kuro: Kuro? = nil
local bubble: { gui: BillboardGui, label: TextLabel, voice: Sound }? = nil
local speakQueue: { string } = {}
local speaking = false
local bubbleBusy = false
local lastLine = 0
local fxFolder: Instance? = nil

local WALK, RUN = 6.5, 15
local STAY, FAR = 22, 80 -- he follows when you are further than STAY studs, and is simply put next to you beyond FAR

local function setBubble()
	if bubble or not kuro then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "KuroBubble"
	gui.Adornee = kuro.head
	gui.Size = UDim2.fromOffset(250, 66)
	gui.StudsOffset = Vector3.new(0, 3.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 70
	gui.Parent = kuro.head
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(16, 16, 18)
	back.BackgroundTransparency = 0.1
	back.BorderSizePixel = 0
	back.Parent = gui
	local edge = Instance.new("Frame")
	edge.Size = UDim2.new(0, 3, 1, 0)
	edge.BackgroundColor3 = Color3.fromRGB(236, 236, 238)
	edge.BorderSizePixel = 0
	edge.Parent = back
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 12), UDim.new(0, 12), UDim.new(0, 8), UDim.new(0, 8)
	pad.Parent = back
	local label = lbl({ Text = "", TextSize = 15, Font = UI.FONT, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = back })
	gui.Enabled = false
	local voice = Instance.new("Sound")
	voice.SoundId = "rbxasset://sounds/switch.wav"
	voice.Volume = 0.05
	voice.PlaybackSpeed = 0.4
	voice.Parent = kuro.head
	bubble = { gui = gui, label = label, voice = voice }
end

local function sayNow(text: string)
	if not bubble or not kuro then
		return
	end
	local b = bubble
	b.gui.Enabled = true
	b.label.Text = ""
	speaking = true
	for i = 1, #text do
		if not kuro or not kuro.alive then
			break
		end
		b.label.Text = string.sub(text, 1, i)
		if i % 3 == 0 then
			b.voice.PlaybackSpeed = 0.34 + rng:NextNumber(0, 0.14)
			b.voice:Play()
		end
		task.wait(0.028)
	end
	speaking = false -- (the jaw rests; the bubble stays a moment to be read)
	task.wait(math.clamp(#text * 0.05, 2, 6.5))
	if #speakQueue == 0 and bubble == b then
		b.gui.Enabled = false
	end
end

local function say(text: string, urgent: boolean?)
	lastLine = os.clock()
	if urgent then
		table.clear(speakQueue)
	end
	table.insert(speakQueue, text)
	if #speakQueue > 3 then
		table.remove(speakQueue, 1)
	end
end

local function pumpSpeech()
	task.spawn(function()
		while true do
			task.wait(0.15)
			if not bubbleBusy and #speakQueue > 0 then
				bubbleBusy = true
				sayNow(table.remove(speakQueue, 1) :: string)
				bubbleBusy = false
			end
		end
	end)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function groundAt(p: Vector3, ignore: { Instance }): Vector3?
	rayParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(p + Vector3.new(0, 6, 0), Vector3.new(0, -22, 0), rayParams)
	return hit and hit.Position or nil
end

local function ignoreList(): { Instance }
	local list = {}
	if player.Character then
		table.insert(list, player.Character)
	end
	if kuro then
		table.insert(list, kuro.rig.model)
	end
	if fxFolder then
		table.insert(list, fxFolder)
	end
	return list
end

local function showKuro()
	if kuro then
		return
	end
	fxFolder = workspace:FindFirstChild("SkinLocalFX")
	local rig = KuroRig.new()
	KuroRig.SetFade(rig, 1)
	kuro = {
		rig = rig, head = rig.head, pos = Vector3.new(0, -1000, 0), yaw = 0, target = nil, idleUntil = 0, speed = 0, born = os.clock(), alive = true, mode = "idle",
		glance = 0, glanceDir = Vector3.zero,
	}
	setBubble()
	task.defer(KuroRig.Burst, rig)
end

local function hideKuro(slow: boolean?)
	local k = kuro
	if not k then
		return
	end
	k.alive = false
	table.clear(speakQueue)
	kuro = nil
	bubble = nil
	task.spawn(function()
		KuroRig.Burst(k.rig)
		for i = 1, 8 do
			KuroRig.SetFade(k.rig, i / 8)
			task.wait(slow and 0.07 or 0.025)
		end
		KuroRig.Destroy(k.rig)
	end)
end

local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * math.min(1, t)
end

local seenBefore = false
local function animate(dt: number)
	local k = kuro
	if not k or not k.alive then
		return
	end
	local char = player.Character
	local torso = char and char:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") or (char and char:GetAttribute("Dead") == true) then
		KuroRig.SetFade(k.rig, 1) -- (hidden while you are dead; he is back when you are)
		return
	end
	local t = os.clock()
	local P = torso.Position
	local ign = ignoreList()
	-- first appearance, or you teleported / ran very far: he is put next to you
	local flat = Vector3.new(k.pos.X - P.X, 0, k.pos.Z - P.Z).Magnitude
	if (k.pos.Y < -500 and not Config.InPit(k.pos)) or flat > FAR then
		local a = rng:NextNumber(0, math.pi * 2)
		local spot = P + Vector3.new(math.cos(a) * 7, 0, math.sin(a) * 7)
		k.pos = groundAt(spot, ign) or Vector3.new(spot.X, P.Y - 3, spot.Z)
		k.target, k.idleUntil, k.mode = nil, t + 1, "idle"
		flat = 7
	end

	-- what does he do: follow (you are far), walk to a spot he picked, or stand about
	local speed = 0
	local goal: Vector3? = nil
	if flat > STAY then
		k.mode = "follow"
	end
	if k.mode == "follow" then
		local away = Vector3.new(k.pos.X - P.X, 0, k.pos.Z - P.Z)
		goal = P + (away.Magnitude > 0.1 and away.Unit or Vector3.xAxis) * 8
		speed = RUN
		if flat < 12 then
			k.mode, k.idleUntil = "idle", t + 1.2
		end
	elseif k.target then
		local tg = k.target :: Vector3
		goal = tg
		speed = WALK
		if Vector3.new(tg.X - k.pos.X, 0, tg.Z - k.pos.Z).Magnitude < 0.9 then
			k.target, goal, speed = nil, nil, 0
			k.idleUntil = t + rng:NextNumber(1.5, 5)
		end
	elseif t >= k.idleUntil then
		-- pick a spot 6-13 studs around you (not through a wall, not off a cliff)
		for _ = 1, 6 do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = rng:NextNumber(6, 13)
			local cand = P + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			local g = groundAt(cand, ign)
			if g and math.abs(g.Y - k.pos.Y) < 5 then
				rayParams.FilterDescendantsInstances = ign
				local from = k.pos + Vector3.new(0, 2.5, 0)
				local to = Vector3.new(g.X, from.Y, g.Z)
				if not workspace:Raycast(from, to - from, rayParams) then
					k.target = g
					break
				end
			end
		end
		k.idleUntil = t + 0.6
	end

	local heading: Vector3? = nil
	if goal and speed > 0 then
		local to = Vector3.new(goal.X - k.pos.X, 0, goal.Z - k.pos.Z)
		local d = to.Magnitude
		if d > 0.05 then
			local hv = to / d
			heading = hv
			-- something in the way: choose another spot
			rayParams.FilterDescendantsInstances = ign
			if workspace:Raycast(k.pos + Vector3.new(0, 2.5, 0), hv * 3, rayParams) then
				k.target = nil
				k.idleUntil = t + 0.4
				speed = 0
				heading = nil
			else
				k.pos += hv * math.min(d, speed * dt)
			end
		end
	end
	k.speed += (speed - k.speed) * math.min(1, dt * 8)

	-- the ground under his feet
	local g = groundAt(k.pos, ign)
	if g then
		k.pos = Vector3.new(k.pos.X, k.pos.Y + (g.Y - k.pos.Y) * math.min(1, dt * 14), k.pos.Z)
	end

	-- he turns the way he walks; standing, he turns to you
	local faceYaw
	if heading then
		faceYaw = math.atan2(-heading.X, -heading.Z)
		k.yaw = lerpAngle(k.yaw, faceYaw, dt * 9)
	else
		local toYou = Vector3.new(P.X - k.pos.X, 0, P.Z - k.pos.Z)
		if toYou.Magnitude > 0.5 then
			k.yaw = lerpAngle(k.yaw, math.atan2(-toYou.X, -toYou.Z), dt * 2.2)
		end
	end

	-- where his eyes go: mostly at your camera, now and then somewhere else
	local cam = workspace.CurrentCamera
	local lookAt = cam and cam.CFrame.Position or P
	if t > k.glance + 1.4 and rng:NextInteger(1, 260) == 1 and not heading then
		k.glance = t
		k.glanceDir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.2, 0.4), rng:NextNumber(-1, 1)).Unit * 12
	end
	if t < k.glance + 1.4 then
		lookAt = k.pos + Vector3.new(0, 6, 0) + k.glanceDir
	end

	KuroRig.SetFade(k.rig, 1 - math.clamp((t - k.born) / 0.9, 0, 1))
	KuroRig.Update(k.rig, dt, CFrame.new(k.pos) * CFrame.Angles(0, k.yaw, 0), lookAt, speaking and 1 or 0, k.speed / WALK)
end

------------------------------------------------------------------------
-- the book
------------------------------------------------------------------------

local gui: ScreenGui
local book: Frame
local open = false
local pickedUser: number? = nil
local pickedName = ""
local pickedCause: string? = nil
local toastLabel: TextLabel
local photoCache: { [number]: string } = {}
local faceList: ScrollingFrame
local causeList: ScrollingFrame
local nameBox: TextBox
local writeBtn: TextButton
local pinned: ImageLabel
local statusLabel: TextLabel
local questLabel: TextLabel
local toastTween: Tween? = nil

local function photo(userId: number, into: ImageLabel)
	if photoCache[userId] then
		into.Image = photoCache[userId]
		return
	end
	task.spawn(function()
		local ok, content = pcall(function()
			return (Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150))
		end)
		if ok and content then
			photoCache[userId] = content
			if into.Parent then
				into.Image = content
			end
		end
	end)
end

local function toast(text: string, seconds: number?)
	toastLabel.Text = text
	toastLabel.TextTransparency = 0
	toastLabel.BackgroundTransparency = 0.15
	if toastTween then
		toastTween:Cancel()
	end
	local tw = TweenService:Create(toastLabel, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, seconds or 3), { TextTransparency = 1, BackgroundTransparency = 1 })
	toastTween = tw
	tw:Play()
end

local function refreshWrite()
	local ready = pickedUser ~= nil and #nameBox.Text > 0 and pickedCause ~= nil
	local cd = state.cooldown or 0
	local on = ready and cd <= 0
	writeBtn.BackgroundColor3 = on and TEXT or PANEL2
	writeBtn.TextColor3 = on and BG or DIM
	if cd > 0 then
		writeBtn.Text = string.format("Ink drying  %d:%02d", math.floor(cd / 60), cd % 60)
	else
		writeBtn.Text = "Write"
	end
	statusLabel.Text = pickedUser == nil and "Pick the face." or (#nameBox.Text == 0 and "Type their name." or (pickedCause == nil and "Choose how." or ""))
	questLabel.Text = string.format("%d names this life", state.kills or 0)
end

local function row(parent: Instance, y: number, selected: boolean, height: number, onClick: () -> ()): TextButton
	local b = btn({ Text = "", BackgroundColor3 = selected and TEXT or PANEL, Size = UDim2.new(1, -6, 0, height), Position = UDim2.fromOffset(0, y), Parent = parent }, onClick)
	return b
end

local function buildFaces()
	for _, c in faceList:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local y, n = 0, 0
	for _, p in Players:GetPlayers() do
		if p ~= player then
			n += 1
			local sel = pickedUser == p.UserId
			local b = row(faceList, y, sel, 50, function()
				pickedUser = p.UserId
				pickedName = p.DisplayName
				pinned.Visible = true
				photo(p.UserId, pinned)
				buildFaces()
				refreshWrite()
			end)
			local img = UI.make("ImageLabel", { Size = UDim2.fromOffset(42, 42), Position = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = b })
			photo(p.UserId, img)
			lbl({ Text = sel and "Selected" or "Select", TextSize = 13, TextColor3 = sel and BG or DIM, Position = UDim2.fromOffset(54, 0), Size = UDim2.new(1, -60, 1, 0), Parent = b })
			y += 54
		end
	end
	if n == 0 then
		lbl({ Text = "Nobody else is here.", TextSize = 13, TextColor3 = DIM, Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 0, 20), Parent = faceList })
	end
	faceList.CanvasSize = UDim2.fromOffset(0, y)
end

local function buildCauses()
	for _, c in causeList:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local y = 0
	for _, cause in LedgerData.Causes do
		local sel = pickedCause == cause.id
		local b = row(causeList, y, sel, 38, function()
			pickedCause = cause.id
			buildCauses()
			refreshWrite()
		end)
		lbl({ Text = cause.name, TextSize = 14, TextColor3 = sel and BG or TEXT, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -16, 1, 0), Parent = b })
		y += 42
	end
	causeList.CanvasSize = UDim2.fromOffset(0, y)
end

local function setOpen(on: boolean)
	if open == on then
		return
	end
	open = on
	Input.ledgerOpen = on -- (the mouse is free while the book is open)
	Remote:FireServer("book", on) -- (the book in your hand opens / closes)
	book.Visible = on
	if on then
		pickedUser, pickedName, pickedCause = nil, "", nil
		nameBox.Text = ""
		pinned.Visible = false
		buildFaces()
		buildCauses()
		refreshWrite()
	end
end

------------------------------------------------------------------------
-- the writing
------------------------------------------------------------------------

-- (the book opens in your hand and the free hand writes in it: Hands:StartWriting. There is no screen animation any more)
local controller: any = nil
local function heldBook(): Model?
	local c = controller
	if not c then
		return nil
	end
	for _, side in { "Left", "Right" } do
		local g = c.hands[side].grip
		if g and g.item and g.item:GetAttribute("Item") == "ledger" then
			return g.item
		end
	end
	return nil
end

------------------------------------------------------------------------

local function onEvent(name: string, data: any)
	if name == "pickup" then
		showKuro()
		if not seenBefore then
			seenBefore = true
			for _, l in LINES.first do
				say(l)
			end
		else
			say(pick(LINES.again), true)
		end
	elseif name == "leave" then
		hideKuro() -- (somebody else took the ledger: he is gone at once)
	elseif name == "smear" then
		say(pick(LINES.smear), true)
		toast("Wrong name for that face.")
	elseif name == "cooldown" then
		say(string.format("%s (%d s)", pick(LINES.cooldown), state.cooldown or 0), true)
	elseif name == "badtarget" then
		say(pick(data and LINES.badself or LINES.badtarget), true)
	elseif name == "writing" then
		local cause = data and LedgerData.ById[data.cause]
		say(string.format("%s, %s. Okay.", data and data.name or "Them", cause and string.lower(cause.name) or "quietly"), true)
	elseif name == "killed" then
		local n = data and data.n or 0
		say(string.format("%s is gone. That's %d.", data and data.name or "They", n))
	elseif name == "resisted" then
		say(pick(LINES.resisted), true)
	elseif name == "nobody" then
		say(pick(LINES.nobody), true)
	elseif name == "fed" then
		say(pick({ "*munch* Good.", "*munch* Thanks.", "*munch* Another one?" }), true)
	elseif name == "ate" then
		say(pick(LINES.ate), true)
		toast("You eat the apple.")
	end
end

function LedgerClient.SetController(c: any)
	controller = c
end

function LedgerClient.Init()
	Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Ledger") :: RemoteEvent
	local pg = player:WaitForChild("PlayerGui")
	-- (ZIndexBehavior Sibling: a child always draws above its parent - with Global the grey panel covered its own buttons)
	gui = UI.make("ScreenGui", { Name = "LedgerGui", ResetOnSpawn = false, DisplayOrder = 45, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = pg })
	toastLabel = lbl({
		Text = "", TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -120),
		Size = UDim2.fromOffset(520, 34), BackgroundColor3 = Color3.fromRGB(14, 14, 16), BackgroundTransparency = 1, Parent = gui,
	})

	book = UI.make("Frame", {
		Name = "Book", Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 410),
		BackgroundColor3 = BG, BorderSizePixel = 0, Parent = gui,
	})
	UI.make("UIStroke", { Color = LINE, Thickness = 1, Parent = book })
	local sc = UI.make("UIScale", { Parent = book })
	local function fit()
		local v = gui.AbsoluteSize
		sc.Scale = math.min(1, (v.X - 12) / 640, (v.Y - 12) / 410)
	end
	fit()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	lbl({ Text = "Black Ledger", Font = FONT_B, TextSize = 20, Position = UDim2.fromOffset(18, 12), Size = UDim2.fromOffset(300, 26), Parent = book })
	questLabel = lbl({ Text = "", TextSize = 12, TextColor3 = DIM, Position = UDim2.fromOffset(18, 38), Size = UDim2.fromOffset(420, 16), Parent = book })
	btn({ Text = "X", Size = UDim2.fromOffset(30, 26), Position = UDim2.new(1, -44, 0, 12), Parent = book }, function()
		setOpen(false)
	end)
	UI.make("Frame", { Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = LINE, BorderSizePixel = 0, Parent = book })

	lbl({ Text = "FACE", Font = FONT_B, TextSize = 11, TextColor3 = DIM, Position = UDim2.fromOffset(18, 72), Size = UDim2.fromOffset(120, 14), Parent = book })
	faceList = UI.make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(16, 92), Size = UDim2.fromOffset(196, 258), ScrollBarThickness = 3, CanvasSize = UDim2.fromOffset(0, 0), Parent = book })

	lbl({ Text = "NAME", Font = FONT_B, TextSize = 11, TextColor3 = DIM, Position = UDim2.fromOffset(232, 72), Size = UDim2.fromOffset(120, 14), Parent = book })
	pinned = UI.make("ImageLabel", { Visible = false, Position = UDim2.fromOffset(282, 96), Size = UDim2.fromOffset(100, 100), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = book })
	UI.make("UIStroke", { Color = TEXT, Thickness = 2, Parent = pinned })
	nameBox = UI.make("TextBox", {
		Text = "", PlaceholderText = "Type the name", PlaceholderColor3 = DIM, ClearTextOnFocus = false, Font = FONT, TextSize = 18, TextColor3 = TEXT,
		BackgroundColor3 = PANEL, BorderSizePixel = 0, Position = UDim2.fromOffset(232, 214), Size = UDim2.fromOffset(196, 40), Parent = book,
	})
	UI.make("UIStroke", { Color = LINE, Thickness = 1, Parent = nameBox })
	lbl({ Text = "It has to match the face.", TextSize = 12, TextColor3 = DIM, Position = UDim2.fromOffset(234, 258), Size = UDim2.fromOffset(196, 16), Parent = book })
	nameBox:GetPropertyChangedSignal("Text"):Connect(refreshWrite)

	lbl({ Text = "HOW", Font = FONT_B, TextSize = 11, TextColor3 = DIM, Position = UDim2.fromOffset(448, 72), Size = UDim2.fromOffset(120, 14), Parent = book })
	causeList = UI.make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(446, 92), Size = UDim2.fromOffset(182, 258), ScrollBarThickness = 3, CanvasSize = UDim2.fromOffset(0, 0), Parent = book })

	statusLabel = lbl({ Text = "", TextSize = 13, TextColor3 = DIM, Position = UDim2.fromOffset(18, 366), Size = UDim2.fromOffset(300, 20), Parent = book })
	writeBtn = btn({
		Text = "Write", TextSize = 16, Font = FONT_B, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 358), Size = UDim2.fromOffset(190, 38), BackgroundColor3 = PANEL2, Parent = book,
	}, function()
		if not pickedUser or #nameBox.Text == 0 or not pickedCause or (state.cooldown or 0) > 0 then
			return
		end
		Remote:FireServer("write", pickedUser, nameBox.Text, pickedCause)
		setOpen(false)
	end)

	pumpSpeech()
	RunService.RenderStepped:Connect(animate)
	task.spawn(function()
		while true do
			task.wait(1)
			if (state.cooldown or 0) > 0 then
				state.cooldown -= 1
				if open then
					refreshWrite()
				end
			end
		end
	end)

	Remote.OnClientEvent:Connect(function(action, a, b, c, d)
		if action == "event" then
			if typeof(c) == "table" then
				state = c
			end
			onEvent(a, b)
		elseif action == "open" then
			if typeof(a) == "table" then
				state = a
			end
			setOpen(not open) -- F again closes the book
		elseif action == "writing" then
			local item = heldBook()
			if item and controller then
				controller:StartWriting(item, tonumber(d) or Config.LedgerWriteTime)
			end
		elseif action == "world" then
			toast(tostring(a), 6)
		end
	end)
	player:GetAttributeChangedSignal("SpawnDenied"):Connect(function()
		local v = player:GetAttribute("SpawnDenied")
		if typeof(v) == "string" then
			toast(string.split(v, "|")[1] .. " can only be spawned by admins.", 4)
		end
	end)

	-- Kuro is there exactly while the server says you are the keeper of the ledger
	local function sync()
		if player:GetAttribute("HasLedger") == true then
			showKuro()
		else
			hideKuro()
		end
	end
	player:GetAttributeChangedSignal("HasLedger"):Connect(sync)
	sync()

	-- he talks now and then
	task.spawn(function()
		while true do
			task.wait(rng:NextNumber(20, 40))
			if kuro and not speaking and not bubbleBusy and #speakQueue == 0 and os.clock() - lastLine > 15 then
				say(pick(LINES.idle))
			end
		end
	end)

	UserInputService.InputBegan:Connect(function(io)
		if Input.IsControlled() then return end
		if open and io.KeyCode == Enum.KeyCode.Escape then
			setOpen(false)
		end
	end)
end

return LedgerClient
