--!nonstrict
-- TVClient: a TV that is switched on plays a show on its screen (drawn here, the same on every
-- client because it runs on the clock). Three channels, the next one each time it comes on:
--   1 CARTOON  a little block guy runs through a sunny land and jumps over crates
--   2 NEWS     a news anchor, a LIVE badge and a ticker with the latest from the sandbox
--   3 NATURE   fish swimming past swaying seaweed, bubbles rising
-- Close to it you hear a little tune / the news jingle / bubbles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SoundLibrary = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SoundLibrary"))

local TVClient = {}

type Show = { gui: SurfaceGui, channel: number, update: (number) -> (), screen: BasePart, nextNote: number, note: number }
local shows: { [Model]: Show } = {}

local TICKER = "BREAKING: MAN FALLS OFF THE CRANE, GETS UP AGAIN   +++   LOCAL DUMMY RUN OVER FOR THE 40TH TIME THIS WEEK   +++   WEATHER: SUNNY, CHANCE OF GRENADES IN THE AFTERNOON   +++   EXPERTS: THE SPIKE WALL IS STILL SHARP   +++   SPORTS: DROP KICK RECORD BROKEN AT THE CONSTRUCTION SITE   +++   "

local TUNE = { 0, 4, 7, 12, 7, 4, 0, 5, 9, 12, 9, 5, 2, 7, 11, 14 } -- semitones

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function box(parent: Instance, pos: UDim2, size: UDim2, color: Color3, z: number?, round: number?): Frame
	local f = Instance.new("Frame")
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z or 1
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(round, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end

local function text(parent: Instance, t: string, pos: UDim2, size: UDim2, color: Color3, font: Enum.Font, z: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Text = t
	l.TextColor3 = color
	l.Font = font
	l.TextScaled = true
	l.ZIndex = z or 2
	l.Parent = parent
	return l
end

------------------------------------------------------------------------
-- channels: build(canvas) -> update(t)
------------------------------------------------------------------------

local function cartoon(c: Frame)
	c.BackgroundColor3 = rgb(120, 200, 255)
	local sun = box(c, UDim2.fromScale(0.78, 0.08), UDim2.fromScale(0.13, 0.22), rgb(255, 220, 80), 1, 0.5)
	local clouds = {}
	for i = 1, 3 do
		local cl = box(c, UDim2.fromScale(0.3 * i, 0.12 + 0.08 * i), UDim2.fromScale(0.2, 0.09), rgb(255, 255, 255), 1, 0.5)
		table.insert(clouds, cl)
	end
	box(c, UDim2.fromScale(0, 0.72), UDim2.fromScale(1, 0.28), rgb(90, 180, 80), 2)
	box(c, UDim2.fromScale(0, 0.72), UDim2.fromScale(1, 0.03), rgb(60, 140, 50), 3)
	local crates = {}
	for i = 1, 2 do
		local cr = box(c, UDim2.fromScale(0.5 + 0.5 * i, 0.6), UDim2.fromScale(0.08, 0.12), rgb(170, 120, 60), 3)
		box(cr, UDim2.fromScale(0.1, 0.45), UDim2.fromScale(0.8, 0.1), rgb(120, 80, 40), 4)
		table.insert(crates, cr)
	end
	-- the hero
	local hero = box(c, UDim2.fromScale(0.3, 0.5), UDim2.fromScale(0.08, 0.22), rgb(0, 0, 0), 5)
	hero.BackgroundTransparency = 1
	local body = box(hero, UDim2.fromScale(0.1, 0.35), UDim2.fromScale(0.8, 0.35), rgb(220, 60, 60), 6)
	local head = box(hero, UDim2.fromScale(0.15, 0.02), UDim2.fromScale(0.7, 0.33), rgb(250, 210, 160), 6)
	box(head, UDim2.fromScale(0.6, 0.35), UDim2.fromScale(0.15, 0.2), rgb(0, 0, 0), 7)
	local legL = box(hero, UDim2.fromScale(0.15, 0.7), UDim2.fromScale(0.28, 0.3), rgb(50, 60, 140), 5)
	local legR = box(hero, UDim2.fromScale(0.57, 0.7), UDim2.fromScale(0.28, 0.3), rgb(50, 60, 140), 5)
	text(c, "BLOCKY & FRIENDS", UDim2.fromScale(0.03, 0.88), UDim2.fromScale(0.4, 0.09), rgb(255, 255, 255), Enum.Font.Sarpanch, 8)
	return function(t: number)
		-- the world scrolls by
		for i, cr in crates do
			local x = 1.1 - ((t * 0.25 + i * 0.55) % 1.3)
			cr.Position = UDim2.fromScale(x, 0.6)
		end
		for i, cl in clouds do
			cl.Position = UDim2.fromScale(1.1 - ((t * 0.05 + i * 0.37) % 1.3), 0.08 + 0.07 * i)
		end
		sun.Rotation = t * 20
		-- jump when a crate comes close
		local jump = 0
		for _, cr in crates do
			local dx = cr.Position.X.Scale - 0.3
			if dx > -0.08 and dx < 0.12 then
				jump = math.max(jump, math.sin(math.clamp((0.12 - dx) / 0.2, 0, 1) * math.pi))
			end
		end
		hero.Position = UDim2.fromScale(0.3, 0.5 - jump * 0.22)
		local step = math.sin(t * 14) * 0.08
		legL.Position = UDim2.fromScale(0.15 + step, 0.7)
		legR.Position = UDim2.fromScale(0.57 - step, 0.7)
		body.Rotation = jump > 0 and 0 or math.sin(t * 14) * 3
	end
end

local function news(c: Frame)
	c.BackgroundColor3 = rgb(16, 28, 60)
	box(c, UDim2.fromScale(0, 0.55), UDim2.fromScale(1, 0.45), rgb(10, 18, 40), 1)
	for i = 0, 5 do
		box(c, UDim2.fromScale(0.05 + i * 0.16, 0.08), UDim2.fromScale(0.01, 0.45), rgb(40, 60, 110), 1)
	end
	-- the anchor
	local anchor = box(c, UDim2.fromScale(0.38, 0.22), UDim2.fromScale(0.24, 0.5), rgb(0, 0, 0), 2)
	anchor.BackgroundTransparency = 1
	box(anchor, UDim2.fromScale(0, 0.45), UDim2.fromScale(1, 0.55), rgb(30, 30, 36), 3, 0.25)
	box(anchor, UDim2.fromScale(0.42, 0.45), UDim2.fromScale(0.16, 0.35), rgb(200, 30, 30), 4)
	local head = box(anchor, UDim2.fromScale(0.27, 0.02), UDim2.fromScale(0.46, 0.46), rgb(220, 180, 140), 4, 0.5)
	local mouth = box(head, UDim2.fromScale(0.35, 0.68), UDim2.fromScale(0.3, 0.08), rgb(90, 30, 30), 5)
	box(head, UDim2.fromScale(0.22, 0.38), UDim2.fromScale(0.12, 0.12), rgb(0, 0, 0), 5, 0.5)
	box(head, UDim2.fromScale(0.66, 0.38), UDim2.fromScale(0.12, 0.12), rgb(0, 0, 0), 5, 0.5)
	box(c, UDim2.fromScale(0.25, 0.62), UDim2.fromScale(0.5, 0.1), rgb(90, 60, 40), 6)
	-- badges and the ticker
	local live = box(c, UDim2.fromScale(0.04, 0.06), UDim2.fromScale(0.13, 0.1), rgb(210, 20, 20), 7)
	text(live, "LIVE", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), rgb(255, 255, 255), Enum.Font.Sarpanch, 8)
	text(c, "RSN 24", UDim2.fromScale(0.78, 0.05), UDim2.fromScale(0.18, 0.1), rgb(255, 255, 255), Enum.Font.Sarpanch, 8)
	local bar = box(c, UDim2.fromScale(0, 0.8), UDim2.fromScale(1, 0.12), rgb(200, 20, 20), 7)
	bar.ClipsDescendants = true
	local tick = text(bar, TICKER .. TICKER, UDim2.fromScale(0, 0), UDim2.fromScale(8, 1), rgb(255, 255, 255), Enum.Font.Sarpanch, 8)
	tick.TextScaled = false
	tick.TextSize = 22
	tick.TextXAlignment = Enum.TextXAlignment.Left
	local headline = box(c, UDim2.fromScale(0, 0.72), UDim2.fromScale(0.6, 0.08), rgb(250, 250, 250), 7)
	text(headline, "SANDBOX TONIGHT", UDim2.fromScale(0.03, 0), UDim2.fromScale(0.94, 1), rgb(20, 20, 30), Enum.Font.Sarpanch, 8)
	return function(t: number)
		tick.Position = UDim2.fromScale(-((t * 0.06) % 4), 0)
		mouth.Size = UDim2.fromScale(0.3, 0.05 + 0.1 * math.abs(math.sin(t * 9)) * (math.sin(t * 0.7) > -0.3 and 1 or 0))
		live.BackgroundTransparency = (t % 1) < 0.5 and 0 or 0.3
		head.Rotation = math.sin(t * 0.8) * 4
	end
end

local function nature(c: Frame)
	c.BackgroundColor3 = rgb(20, 90, 140)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(rgb(80, 170, 220), rgb(10, 40, 80))
	grad.Rotation = 90
	grad.Parent = c
	box(c, UDim2.fromScale(0, 0.86), UDim2.fromScale(1, 0.14), rgb(210, 190, 130), 2)
	local weeds = {}
	for i = 1, 6 do
		local w = box(c, UDim2.fromScale(0.08 + i * 0.15, 0.55), UDim2.fromScale(0.025, 0.35), rgb(40, 140, 70), 2)
		w.AnchorPoint = Vector2.new(0.5, 1)
		w.Position = UDim2.fromScale(0.05 + i * 0.15, 0.88)
		table.insert(weeds, w)
	end
	local fish = {}
	local colors = { rgb(255, 150, 40), rgb(255, 220, 60), rgb(240, 80, 120), rgb(120, 220, 255) }
	for i = 1, 5 do
		local f = box(c, UDim2.fromScale(0, 0.2 + 0.12 * i), UDim2.fromScale(0.12, 0.08), colors[(i - 1) % #colors + 1], 3, 0.5)
		box(f, UDim2.fromScale(-0.3, 0.2), UDim2.fromScale(0.35, 0.6), f.BackgroundColor3, 3)
		box(f, UDim2.fromScale(0.7, 0.25), UDim2.fromScale(0.12, 0.25), rgb(0, 0, 0), 4, 0.5)
		table.insert(fish, { f = f, speed = 0.06 + i * 0.015, y = 0.18 + 0.12 * i, ph = i * 1.7 })
	end
	local bubbles = {}
	for i = 1, 8 do
		table.insert(bubbles, { b = box(c, UDim2.fromScale(0, 0), UDim2.fromScale(0.02, 0.035), rgb(220, 240, 255), 4, 0.5), x = i * 0.11, ph = i * 0.37 })
	end
	text(c, "DEEP BLUE", UDim2.fromScale(0.03, 0.04), UDim2.fromScale(0.3, 0.09), rgb(255, 255, 255), Enum.Font.Sarpanch, 8)
	return function(t: number)
		for i, w in weeds do
			w.Rotation = math.sin(t * 1.3 + i) * 10
		end
		for _, fi in fish do
			local x = ((t * fi.speed + fi.ph) % 1.4) - 0.2
			fi.f.Position = UDim2.fromScale(x, fi.y + math.sin(t * 2 + fi.ph) * 0.02)
		end
		for _, bu in bubbles do
			local y = 1 - ((t * 0.15 + bu.ph) % 1)
			bu.b.Position = UDim2.fromScale(bu.x + math.sin(t * 3 + bu.ph) * 0.01, y)
		end
	end
end

local CHANNELS = { cartoon, news, nature }

------------------------------------------------------------------------

local function stop(tv: Model)
	local s = shows[tv]
	if s then
		shows[tv] = nil
		s.gui:Destroy()
	end
end

local function start(tv: Model, screen: BasePart, channel: number)
	stop(tv)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Show"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(420, 250)
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.ClipsDescendants = true
	gui.Parent = screen
	local canvas = Instance.new("Frame")
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.BorderSizePixel = 0
	canvas.ClipsDescendants = true
	canvas.Parent = gui
	-- a burst of static when it comes on
	local static = Instance.new("Frame")
	static.Size = UDim2.fromScale(1, 1)
	static.BackgroundColor3 = Color3.new(1, 1, 1)
	static.BorderSizePixel = 0
	static.ZIndex = 20
	static.Parent = canvas
	local build = CHANNELS[((channel - 1) % #CHANNELS) + 1]
	local update = build(canvas)
	local t0 = os.clock()
	shows[tv] = {
		gui = gui,
		channel = channel,
		screen = screen,
		nextNote = 0,
		note = 1,
		update = function(t: number)
			local on = os.clock() - t0
			static.Visible = on < 0.45
			if static.Visible then
				static.BackgroundColor3 = Color3.new(1, 1, 1):Lerp(Color3.new(0.2, 0.2, 0.2), math.random())
			end
			update(t)
		end,
	}
	SoundLibrary.Play("static", screen, 0.8)
end

local function tvs(): { Model }
	local list = {}
	for _, name in { "SpawnedProps", "Map" } do
		local f = workspace:FindFirstChild(name)
		if f then
			for _, d in f:GetDescendants() do
				if d:IsA("Model") and d:GetAttribute("TV") then
					table.insert(list, d)
				end
			end
		end
	end
	return list
end

function TVClient.Init()
	-- which TVs are on (twice a second)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local seen = {}
			for _, tv in tvs() do
				seen[tv] = true
				local screen = tv:FindFirstChild("Screen")
				local on = tv:GetAttribute("On") == true and screen ~= nil and screen:IsA("BasePart")
				local channel = tv:GetAttribute("Channel") or 1
				local s = shows[tv]
				if on and (not s or s.channel ~= channel) then
					start(tv, screen :: BasePart, channel)
				elseif not on and s then
					stop(tv)
				end
			end
			for tv in shows do
				if not seen[tv] or not tv.Parent then
					stop(tv)
				end
			end
		end
	end)
	-- animate the shows you are close to, and their sound
	RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local t = workspace:GetServerTimeNow()
		local now = os.clock()
		for _, s in shows do
			if not s.screen.Parent then
				continue
			end
			local d = (s.screen.Position - cam.CFrame.Position).Magnitude
			if d < 90 then
				pcall(s.update, t)
			end
			if d < 45 and now > s.nextNote then
				if s.channel % 3 == 1 then
					-- the cartoon tune
					s.nextNote = now + 0.22
					local semi = TUNE[s.note]
					s.note = s.note % #TUNE + 1
					SoundLibrary.Play("tvNote", s.screen, 0.5, 2 ^ (semi / 12))
				elseif s.channel % 3 == 2 then
					-- the news: a jingle now and then, otherwise the anchor's murmur
					s.nextNote = now + 0.16
					SoundLibrary.Play("tvNote", s.screen, 0.12, 0.45 + math.random() * 0.12)
				else
					s.nextNote = now + 0.5 + math.random() * 0.8
					SoundLibrary.Play("bubbles", s.screen, 0.4)
				end
			end
		end
	end)
end

return TVClient
