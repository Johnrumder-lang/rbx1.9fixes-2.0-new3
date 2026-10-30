--!nonstrict
-- SandevistanClient (v2.1h): what you see of the Sandevistan.
--   * double-tap SHIFT (a button on a phone): use it
--   * while it runs: a green screen, afterimages behind every body that runs it (they stay until it ends), the world in
--     slow motion (the server and every other player's machine do that: SuperService.SlowMo, TimeScale)
--   * the implant: a progress bar for the one who implants and the one who gets it
--   * the burn: the screen flashes (red when it hurts, white when the circuits fry), glitch bars when you lose control of your body
--   * a small status box: READY / ACTIVE / HOT (using it now fries it) / STRAIN (using it now hurts)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UI = require(script.Parent:WaitForChild("UI"))
local Input = require(script.Parent:WaitForChild("Input"))
local Items = require(Shared:WaitForChild("Items"))
local Hallucinations = require(script.Parent:WaitForChild("Hallucinations"))

local SandevistanClient = {}

local player = Players.LocalPlayer
local C = UI.C
local Remote: RemoteEvent
local gui: ScreenGui
local tint: ColorCorrectionEffect
local greenFrame: Frame
local flashFrame: Frame
local glitchHolder: Frame
local toastLabel: TextLabel
local statusLabel: TextLabel
local useButton: TextButton

local firstUseAt: number? = nil -- (client clock) when the first use of this cycle began
local activeUntil = 0
local activeMode = ""
local rng = Random.new()

local function toast(text: string)
	toastLabel.Text = text
	toastLabel.TextTransparency = 0
	toastLabel.BackgroundTransparency = 0.15
	TweenService:Create(toastLabel, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 3.5), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
end

local function flash(intensity: number, color: string)
	flashFrame.BackgroundColor3 = color == "white" and Color3.new(1, 1, 1) or (color == "red" and Color3.fromRGB(255, 30, 40) or Color3.fromRGB(60, 255, 150))
	flashFrame.BackgroundTransparency = math.clamp(1 - intensity * 0.75, 0.1, 1)
	TweenService:Create(flashFrame, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
end

local function setActive(on: boolean)
	tint.Enabled = on
	greenFrame.Visible = on
end

-- the glitch of a body that does not obey: bars of static for a moment
local function psychosis(dur: number)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < dur do
			for _, c in glitchHolder:GetChildren() do
				c:Destroy()
			end
			for _ = 1, rng:NextInteger(4, 9) do
				local bar = Instance.new("Frame")
				bar.BorderSizePixel = 0
				bar.BackgroundColor3 = (rng:NextInteger(1, 3) == 1) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(60, 255, 150)
				bar.BackgroundTransparency = rng:NextNumber(0.3, 0.7)
				bar.Position = UDim2.fromScale(rng:NextNumber(-0.1, 0.4), rng:NextNumber(0, 1))
				bar.Size = UDim2.fromScale(rng:NextNumber(0.2, 0.9), rng:NextNumber(0.004, 0.03))
				bar.Parent = glitchHolder
			end
			task.wait(0.06)
		end
		for _, c in glitchHolder:GetChildren() do
			c:Destroy()
		end
	end)
	flash(0.5, "green")
end

------------------------------------------------------------------------
-- (v2.8) afterimages: every body that runs it leaves neon copies of itself while it moves. They STAY - a trail of
-- frozen poses that shifts through the colours - until the Sandevistan ends; then they are all gone at once.
------------------------------------------------------------------------

local ghostFolder: Folder
local GHOST_HUES = { Color3.fromRGB(70, 255, 160), Color3.fromRGB(60, 230, 255), Color3.fromRGB(80, 140, 255), Color3.fromRGB(190, 90, 255), Color3.fromRGB(255, 80, 200) }
type Trail = { snaps: { Model }, last: Vector3?, n: number }
local trails: { [Model]: Trail } = {}
local MAX_SNAPS = 90 -- per body (the oldest goes first)

local function snapshot(char: Model, tr: Trail)
	local m = Instance.new("Model")
	m.Name = "Afterimage"
	local color = GHOST_HUES[(tr.n // 3) % #GHOST_HUES + 1]
	local parts = 0
	for _, d in char:GetChildren() do
		if d:IsA("BasePart") and d.Transparency < 0.9 and d.Name ~= "HumanoidRootPart" and parts < 10 then
			parts += 1
			-- a copy of the real part with its own shape (the round head, the arms), everything else removed
			local g = d:Clone()
			for _, c in g:GetChildren() do
				if not c:IsA("DataModelMesh") then
					c:Destroy()
				end
			end
			g.Anchored = true
			g.CanCollide, g.CanQuery, g.CanTouch, g.CastShadow = false, false, false, false
			g.Material = Enum.Material.Neon
			g.Color = color
			g.Reflectance = 0
			g.CFrame = d.CFrame
			g.Transparency = 0.5
			g.Parent = m
		end
	end
	m.Parent = ghostFolder
	tr.n += 1
	table.insert(tr.snaps, m)
	if #tr.snaps > MAX_SNAPS then
		local old = table.remove(tr.snaps, 1)
		if old then
			old:Destroy()
		end
	end
end

local function clearTrail(char: Model)
	local tr = trails[char]
	trails[char] = nil
	if not tr then
		return
	end
	for _, m in tr.snaps do
		m:Destroy() -- (all at once)
	end
end

local function stepTrails()
	for _, p in Players:GetPlayers() do
		local ch = p.Character
		if ch and ch:GetAttribute("SandevistanOn") then
			local torso = ch:FindFirstChild("Torso") or ch.PrimaryPart
			if torso and torso:IsA("BasePart") then
				local tr = trails[ch]
				if not tr then
					tr = { snaps = {}, last = nil, n = 0 }
					trails[ch] = tr
				end
				-- only while it moves: standing still leaves one image, not a pile
				if not tr.last or (torso.Position - tr.last).Magnitude > 0.7 then
					tr.last = torso.Position
					snapshot(ch, tr)
				end
			end
		end
	end
	for ch in trails do
		if not ch.Parent or not ch:GetAttribute("SandevistanOn") then
			clearTrail(ch)
		end
	end
end

------------------------------------------------------------------------

function SandevistanClient.Init()
	Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Sandevistan") :: RemoteEvent
	local pg = player:WaitForChild("PlayerGui")
	gui = UI.make("ScreenGui", { Name = "SandevistanGui", ResetOnSpawn = false, DisplayOrder = 60, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = pg })
	ghostFolder = Instance.new("Folder")
	ghostFolder.Name = "SandevistanFX"
	ghostFolder.Parent = workspace

	tint = Lighting:FindFirstChild("SandevistanTint") :: ColorCorrectionEffect
	if not tint then
		local t = Instance.new("ColorCorrectionEffect")
		t.Name = "SandevistanTint"
		t.TintColor = Color3.fromRGB(150, 255, 175)
		t.Saturation = 0.15
		t.Contrast = 0.18
		t.Brightness = -0.03
		t.Parent = Lighting
		tint = t
	end
	tint.Enabled = false
	greenFrame = UI.make("Frame", { Visible = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(40, 255, 120), BackgroundTransparency = 0.86, BorderSizePixel = 0, Parent = gui })
	flashFrame = UI.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5, Parent = gui })
	glitchHolder = UI.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 6, Parent = gui })

	toastLabel = UI.label({
		Text = "", TextSize = 20, Font = UI.FONT_TITLE, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -120),
		Size = UDim2.fromOffset(620, 36), BackgroundColor3 = Color3.fromRGB(10, 10, 12), BackgroundTransparency = 1, ZIndex = 8, Parent = gui,
	})

	-- the status box (only when you have the implant)
	statusLabel = UI.label({
		Text = "", Font = UI.FONT_TITLE, TextSize = 16, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, BackgroundColor3 = C.panel, BackgroundTransparency = 0.2,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.74, 0), Size = UDim2.fromOffset(240, 54), Visible = false, Parent = gui,
	})
	UI.make("UIStroke", { Color = Color3.fromRGB(60, 255, 150), Thickness = 1, Parent = statusLabel })
	UI.make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), Parent = statusLabel })

	-- a phone has no double-tap Shift: a button
	useButton = UI.button({
		Text = "SANDEVISTAN", TextSize = 16, Size = UDim2.fromOffset(150, 40), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -150), Visible = false, Parent = gui,
	}, function()
		Remote:FireServer("use")
	end)

	local lastShift = 0
	UserInputService.InputBegan:Connect(function(io, processed)
		if Input.IsControlled() then return end
		if UserInputService:GetFocusedTextBox() or (player:GetAttribute("HasSandevistan") ~= true and not Items.IsOwner(player)) then
			return
		end
		if io.KeyCode == Enum.KeyCode.LeftShift or io.KeyCode == Enum.KeyCode.RightShift then
			local now = os.clock()
			if now - lastShift <= 0.32 then
				lastShift = 0
				Remote:FireServer("use")
			else
				lastShift = now
			end
		end
	end)

	Remote.OnClientEvent:Connect(function(action, a, b, c, d)
		if action == "msg" then
			toast(tostring(a))
		elseif action == "active" then
			activeMode = tostring(a)
			local dur, since = tonumber(b) or 10, tonumber(d) or 0
			activeUntil = os.clock() + dur
			firstUseAt = os.clock() - since
			setActive(true)
			if activeMode == "fry" then
				toast("The circuits are still hot...")
				flash(0.6, "white")
			end
		elseif action == "ended" then
			setActive(false)
		elseif action == "flash" then
			flash(tonumber(a) or 0.5, tostring(b))
		elseif action == "psycho" then
			-- cyberpsychosis: you start to SEE things (the game's own hallucinations: watchers, crawlers, whispers, writing on the walls)
			Hallucinations.Force(tonumber(a) or 14, tonumber(b) or 0.3)
			psychosis(1.2)
			toast("...something is wrong.")
		end
	end)

	-- afterimages of whoever runs it
	task.spawn(function()
		while true do
			task.wait(Config.SlowGhostRate)
			stepTrails()
		end
	end)

	-- the status box
	task.spawn(function()
		while true do
			task.wait(0.25)
			local has = player:GetAttribute("HasSandevistan") == true or Items.Has(player, "sandevistan")
			statusLabel.Visible = has
			useButton.Visible = has and Input.lastDevice == "Touch"
			if not has then
				firstUseAt = nil
				setActive(false)
			else
				local now = os.clock()
				local text
				if now < activeUntil then
					text = string.format("SANDEVISTAN  ACTIVE  %ds", math.ceil(activeUntil - now))
				elseif Items.IsOwner(player) then
					text = "SANDEVISTAN  READY (admin)\nDouble-tap SHIFT - no limits"
				elseif not firstUseAt then
					text = "SANDEVISTAN  READY\nDouble-tap SHIFT"
				else
					local since = now - firstUseAt
					local hotEnd = Config.SandevistanDuration + Config.SandevistanHot
					if since < hotEnd then
						text = string.format("HOT  %ds\nUsing it now FRIES the circuits", math.ceil(hotEnd - since))
					elseif since < Config.SandevistanCycle then
						text = string.format("STRAIN  %d:%02d\nUsing it now HURTS", math.floor((Config.SandevistanCycle - since) / 60), math.floor((Config.SandevistanCycle - since) % 60))
					else
						text = "SANDEVISTAN  READY\nDouble-tap SHIFT"
					end
				end
				statusLabel.Text = text
			end
		end
	end)
	player.CharacterAdded:Connect(function()
		setActive(false)
		activeUntil = 0
		local cycleEnd = player:GetAttribute("SandevistanCycleEnd")
		firstUseAt = typeof(cycleEnd) == "number" and (os.clock() + cycleEnd - workspace:GetServerTimeNow() - Config.SandevistanCycle) or firstUseAt
	end)
end

return SandevistanClient
