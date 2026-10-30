--!nonstrict
-- GearHUD (v2.0): screens for the new gear.
--   * the lock-on launcher's seeker: corner brackets in the middle while you aim with it; a box around the vehicle
--     it tracks - amber while locking (with the percentage), green and "LOCKED" when it holds
--   * MISSILE WARNING when a lock-on missile flies at the vehicle you drive

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local UI = require(script.Parent:WaitForChild("UI"))
local Events = require(script.Parent:WaitForChild("Events"))
local VehicleClient = require(script.Parent:WaitForChild("VehicleClient"))
local JetClient = require(script.Parent:WaitForChild("JetClient"))
local SoundLibrary = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("SoundLibrary"))

local C = UI.C
local player = Players.LocalPlayer

local GearHUD = {}

local controller = nil
local gui: ScreenGui
local seeker: Frame
local box: Frame
local boxStroke: UIStroke
local boxText: TextLabel
local seekText: TextLabel
local warn: TextLabel
local warnUntil = 0
local jetPanel: Frame
local jetText: TextLabel
local pipper: Frame
local stall: TextLabel

local AMBER = Color3.fromRGB(240, 186, 66)
local GREEN = Color3.fromRGB(90, 230, 110)

local function corner(parent: Instance, ax: number, ay: number)
	local thick = 2
	local len = 22
	UI.make("Frame", { AnchorPoint = Vector2.new(ax, ay), Position = UDim2.fromScale(ax, ay), Size = UDim2.fromOffset(len, thick), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = parent })
	UI.make("Frame", { AnchorPoint = Vector2.new(ax, ay), Position = UDim2.fromScale(ax, ay), Size = UDim2.fromOffset(thick, len), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = parent })
end

-- the lock box in one colour (amber = locking, green = locked)
local function paintBox(col: Color3)
	boxStroke.Color = col
	for _, f in box:GetChildren() do
		if f:IsA("Frame") and f.Name == "Bracket" then
			f.BackgroundColor3 = col
		end
	end
end

function GearHUD.SetController(c)
	controller = c
end

function GearHUD.Init()
	gui = UI.make("ScreenGui", { Name = "GearHUD", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 6, Parent = player:WaitForChild("PlayerGui") })
	-- the seeker field: four corner brackets
	seeker = UI.make("Frame", { Name = "Seeker", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.34, 0.34), BackgroundTransparency = 1, Visible = false, Parent = gui },
		{ UI.make("UIAspectRatioConstraint", { AspectRatio = 1.4 }) })
	for _, a in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		corner(seeker, a[1], a[2])
	end
	seekText = UI.label({ Text = "SEEK", Font = UI.FONT_TITLE, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 8), Size = UDim2.fromOffset(240, 20), TextStrokeTransparency = 0.5, Parent = seeker })
	-- the box on the target
	-- (v2.0: sharp - a hairline square with heavy corner brackets and a centre mark, no rounded joins)
	box = UI.make("Frame", { Name = "Lock", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Visible = false, Parent = gui })
	boxStroke = UI.make("UIStroke", { Color = AMBER, Thickness = 1, Transparency = 0.45, LineJoinMode = Enum.LineJoinMode.Miter, Parent = box })
	for _, a in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		for _, horizontal in { true, false } do
			UI.make("Frame", {
				Name = "Bracket",
				AnchorPoint = Vector2.new(a[1], a[2]),
				Position = UDim2.new(a[1], a[1] == 0 and -2 or 2, a[2], a[2] == 0 and -2 or 2),
				Size = horizontal and UDim2.new(0.28, 0, 0, 3) or UDim2.new(0, 3, 0.28, 0),
				BackgroundColor3 = AMBER,
				BorderSizePixel = 0,
				Parent = box,
			})
		end
	end
	UI.make("Frame", { Name = "Bracket", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(9, 1), BackgroundColor3 = AMBER, BorderSizePixel = 0, Parent = box })
	UI.make("Frame", { Name = "Bracket", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1, 9), BackgroundColor3 = AMBER, BorderSizePixel = 0, Parent = box })
	boxText = UI.label({ Text = "", Font = UI.FONT_TITLE, TextSize = 15, TextColor3 = AMBER, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -4), Size = UDim2.fromOffset(200, 18), TextStrokeTransparency = 0.4, Parent = box })
	-- missile warning
	warn = UI.label({ Text = "MISSILE WARNING", Font = UI.FONT_TITLE, TextSize = 34, TextColor3 = C.bad, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150), Size = UDim2.fromOffset(500, 40), TextStrokeTransparency = 0.3, Visible = false, Parent = gui })

	-- (v2.0) the jet: numbers at the bottom, the cannon's aim circle, STALL
	jetPanel = UI.panel({ Name = "Jet", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -86), Size = UDim2.fromOffset(560, 34), Accent = C.amber, Visible = false, Parent = gui })
	jetText = UI.label({ Text = "", Font = UI.FONT_NUM, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 1, -8), Parent = jetPanel })
	pipper = UI.make("Frame", { Name = "Pipper", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, Visible = false, Parent = gui },
		{ UI.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.make("UIStroke", { Color = Color3.fromRGB(120, 255, 140), Thickness = 2 }) })
	stall = UI.label({ Text = "STALL - SPEED UP", Font = UI.FONT_TITLE, TextSize = 26, TextColor3 = C.bad, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 200), Size = UDim2.fromOffset(400, 30), TextStrokeTransparency = 0.4, Visible = false, Parent = gui })

	Events.On("missile", function()
		warnUntil = os.clock() + 4
		task.spawn(function()
			for _ = 1, 8 do
				SoundLibrary.Play("missileWarn", nil, 0.8)
				task.wait(0.22)
			end
		end)
	end)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		warn.Visible = now < warnUntil and (now % 0.5) < 0.32
		-- the jet
		local jet = VehicleClient.Jet()
		local ji = jet and JetClient.Info(jet)
		jetPanel.Visible = ji ~= nil
		stall.Visible = ji ~= nil and ji.stall and (now % 0.6) < 0.4
		if ji then
			jetText.Text = string.format("THROTTLE %d%%    SPEED %d    ALT %d    MISSILES %d    BOMBS %d", math.floor(ji.throttle * 100 + 0.5),
				math.floor(math.max(0, ji.speed) + 0.5), math.floor(ji.alt + 0.5), ji.missiles, ji.bombs)
			local cam = workspace.CurrentCamera
			local pp, on = cam:WorldToViewportPoint(ji.pipper)
			pipper.Visible = on
			pipper.Position = UDim2.fromOffset(pp.X, pp.Y)
			local lock = ji.lock
			if lock then
				local lp, lon = cam:WorldToViewportPoint(lock.part.Position)
				box.Visible = lon
				box.Position = UDim2.fromOffset(lp.X, lp.Y)
				box.Size = UDim2.fromOffset(70, 54)
				local col = lock.locked and GREEN or AMBER
				paintBox(col)
				boxText.TextColor3 = col
				boxText.Text = lock.locked and "LOCKED - C" or string.format("LOCKING %d%%", math.floor(lock.progress * 100))
			else
				box.Visible = false
			end
			seeker.Visible = false
			return
		end
		pipper.Visible = false
		local c = controller
		local aimingLock = false
		if c and c.ready and c.aiming then
			for _, side in { "Left", "Right" } do
				local g = c.hands[side].grip
				if g and g.kind == "lockon" then
					aimingLock = true
				end
			end
		end
		seeker.Visible = aimingLock
		if not aimingLock then
			box.Visible = false
			return
		end
		local info = c.GetLockInfo and c:GetLockInfo()
		if not info then
			box.Visible = false
			seekText.Text = "SEEK - put a target in the box"
			seekText.TextColor3 = C.text
			return
		end
		local cam = workspace.CurrentCamera
		local pos, onScreen = cam:WorldToViewportPoint(info.part.Position)
		if not onScreen then
			box.Visible = false
			return
		end
		local car = info.part:FindFirstAncestorOfClass("Model")
		local size = car and car:GetExtentsSize().Magnitude or 12
		local dist = (cam.CFrame.Position - info.part.Position).Magnitude
		local px = math.clamp(size / math.max(dist, 1) * cam.ViewportSize.Y * 0.9, 40, 400)
		box.Visible = true
		box.Position = UDim2.fromOffset(pos.X, pos.Y)
		box.Size = UDim2.fromOffset(px * 1.3, px)
		local col = info.locked and GREEN or AMBER
		paintBox(col)
		boxText.TextColor3 = col
		boxText.Text = info.locked and "LOCKED" or string.format("LOCKING %d%%", math.floor(info.progress * 100))
		seekText.Text = info.locked and "LOCKED - FIRE (F)" or "TRACKING - HOLD STILL"
		seekText.TextColor3 = col
	end)
end

return GearHUD
