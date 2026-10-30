--!nonstrict
-- MobileControls: on-screen buttons for touch devices. The default Roblox thumbstick (left side)
-- still moves you; dragging on the right side of the screen turns the camera.

local UserInputService = game:GetService("UserInputService")

local Input = require(script.Parent:WaitForChild("Input"))
local Settings = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Settings"))

local MobileControls = {}
MobileControls.editing = false -- (v1.9) the buttons can be dragged around (settings -> edit touch buttons)

local buttons: { [string]: TextButton } = {}
local defaults: { [string]: UDim2 } = {}
local frame: Frame
local refreshVisible: () -> () = function() end

local function button(parent: Instance, name: string, text: string, pos: UDim2, size: number, accent: Color3?)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text
	b.Font = Enum.Font.Sarpanch
	b.TextSize = size > 60 and 14 or 11
	b.TextColor3 = Color3.fromRGB(240, 240, 244)
	b.BackgroundColor3 = accent or Color3.fromRGB(20, 21, 27)
	b.BackgroundTransparency = 0.25
	b.AutoButtonColor = true
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = pos
	b.Size = UDim2.fromOffset(size, size)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = b
	local s = Instance.new("UIStroke")
	s.Color = Color3.new(1, 1, 1)
	s.Transparency = 0.7
	s.Thickness = 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = b
	b.Parent = parent
	return b
end

-- tap button -> one action
local function tap(b: TextButton, action: string)
	b.Activated:Connect(function()
		if MobileControls.editing then
			return
		end
		Input.FireAction(action)
	end)
end

-- hold button -> virtual held state
local function hold(b: TextButton, name: string)
	b.InputBegan:Connect(function(io)
		if Input.IsControlled() then return end
		if MobileControls.editing then
			return
		end
		if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
			Input.SetVirtual(name, true)
			b.BackgroundTransparency = 0.05
		end
	end)
	b.InputEnded:Connect(function(io)
		if Input.IsControlled() then return end
		if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
			Input.SetVirtual(name, false)
			b.BackgroundTransparency = 0.25
		end
	end)
end

function MobileControls.Init(gui: ScreenGui)
	local f = Instance.new("Frame")
	f.Name = "MobileControls"
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.Visible = false
	f.Parent = gui

	local red = Color3.fromRGB(160, 30, 34)
	local amber = Color3.fromRGB(150, 104, 30)
	-- right cluster (from bottom-right corner)
	local jump = button(f, "Jump", "JUMP", UDim2.new(1, -78, 1, -86), 78)
	hold(jump, "Jump")
	tap(button(f, "GrabR", "GRAB R", UDim2.new(1, -172, 1, -60), 58), "GrabRight")
	tap(button(f, "GrabL", "GRAB L", UDim2.new(1, -168, 1, -136), 58), "GrabLeft")
	tap(button(f, "StowL", "STOW L", UDim2.new(1, -240, 1, -136), 50), "StowLeft") -- (v1.9.1: pockets)
	tap(button(f, "StowR", "STOW R", UDim2.new(1, -244, 1, -60), 50), "StowRight")
	hold(button(f, "Fire", "USE", UDim2.new(1, -78, 1, -186), 62, red), "Use")
	tap(button(f, "Car", "CAR", UDim2.new(1, -92, 0.5, 52), 44), "Car")
	tap(button(f, "Kick", "KICK", UDim2.new(1, -148, 0.5, -4), 44), "Kick")
	hold(button(f, "Sight", "SIGHT", UDim2.new(1, -148, 0.5, 52), 44), "Aim")
	hold(button(f, "AimR", "AIM R", UDim2.new(1, -250, 1, -50), 52, amber), "AimRight")
	hold(button(f, "AimL", "AIM L", UDim2.new(1, -244, 1, -122), 52, amber), "AimLeft")
	-- small utility row on the right edge
	tap(button(f, "Crouch", "CROUCH", UDim2.new(1, -36, 0.5, -60), 48), "Crouch")
	tap(button(f, "Prone", "PRONE", UDim2.new(1, -36, 0.5, -4), 48), "Prone")
	tap(button(f, "Limp", "LIMP", UDim2.new(1, -36, 0.5, 52), 48), "Ragdoll")
	tap(button(f, "Eye", "EYE", UDim2.new(1, -92, 0.5, -60), 44), "FirstPerson")
	tap(button(f, "Menu", "MENU", UDim2.new(1, -92, 0.5, -4), 44), "Menu")
	tap(button(f, "TwoHand", "2 HANDS", UDim2.new(1, -148, 0.5, -60), 44), "TwoHand")
	-- second column: down (flying / helicopter), settings; the owner's powers
	hold(button(f, "Down", "DOWN", UDim2.new(1, -204, 0.5, -60), 44), "Down")
	tap(button(f, "Settings", "SET", UDim2.new(1, -204, 0.5, -4), 44), "Settings")
	-- (v2.0) weave (slip a punch) and spectate
	tap(button(f, "Weave", "WEAVE", UDim2.new(1, -260, 0.5, -60), 44), "Weave")
	tap(button(f, "Watch", "WATCH", UDim2.new(1, -260, 0.5, -4), 44), "Spectate")
	-- Left edge, above the movement thumbstick; included in the saved touch layout.
	tap(button(f, "Chips", "CHIPS", UDim2.new(0, 38, 0.5, -60), 52), "Chips")
	local ok, Items = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Items"))
	end)
	if ok and Items.IsOwner(game:GetService("Players").LocalPlayer) then
		tap(button(f, "Punch", "PUNCH", UDim2.new(1, -204, 0.5, 52), 44, red), "SuperPunch")
		hold(button(f, "Eyes", "EYES", UDim2.new(1, -260, 0.5, 52), 44, red), "Laser")
	end

	frame = f
	for _, c in f:GetChildren() do
		if c:IsA("TextButton") then
			buttons[c.Name] = c
			defaults[c.Name] = c.Position
		end
	end
	MobileControls.BuildEditor(f)
	MobileControls.ApplyLayout()
	Settings.Changed:Connect(function(key)
		if key == "mobileLayout" and not MobileControls.editing then
			MobileControls.ApplyLayout()
		end
	end)

	refreshVisible = function()
		f.Visible = MobileControls.editing or Input.lastDevice == "Touch"
	end
	refreshVisible()

	-- (v2.1) the SET button can never be hidden. "Hide the whole HUD" disables the HUD gui - and every touch button in it, SET
	-- too - so on a phone you could lock yourself out of the settings. This little gear lives in its own ScreenGui: it shows
	-- up exactly when the HUD is hidden, and one tap opens the settings, where the HUD can be switched back on.
	do
		local safety = Instance.new("ScreenGui")
		safety.Name = "SafetySettings"
		safety.ResetOnSpawn = false
		safety.DisplayOrder = 900
		safety.IgnoreGuiInset = false
		safety.Parent = gui.Parent or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
		local gear = Instance.new("TextButton")
		gear.Name = "SafetySet"
		gear.Text = "SET"
		gear.Font = Enum.Font.Sarpanch
		gear.TextSize = 16
		gear.TextColor3 = Color3.fromRGB(255, 255, 255)
		gear.BackgroundColor3 = Color3.fromRGB(20, 21, 27)
		gear.BackgroundTransparency = 0.2
		gear.AnchorPoint = Vector2.new(1, 0)
		gear.Position = UDim2.new(1, -10, 0, 8)
		gear.Size = UDim2.fromOffset(62, 36)
		gear.Visible = false
		gear.Parent = safety
		local gs = Instance.new("UIStroke")
		gs.Color = Color3.fromRGB(240, 186, 66)
		gs.Thickness = 1.5
		gs.Parent = gear
		gear.Activated:Connect(function()
			Input.FireAction("Settings")
		end)
		-- (v2.8) shown whenever a touch screen has no visible SET button - whatever hid it (the setting, a disabled HUD,
		-- the touch controls switched off): you can never lock yourself out of the settings
		local function refreshGear()
			local touch = UserInputService.TouchEnabled or Input.lastDevice == "Touch"
			local setVisible = gui.Enabled and f.Visible and Settings.Get("hideAll") ~= true
			gear.Visible = touch and not setVisible and not MobileControls.editing
		end
		refreshGear()
		task.spawn(function()
			while safety.Parent do
				task.wait(0.5)
				refreshGear()
			end
		end)
		Settings.Changed:Connect(function(key)
			if key == "hideAll" then
				refreshGear()
			end
		end)
		UserInputService.LastInputTypeChanged:Connect(function()
			task.defer(refreshGear)
		end)
	end
	UserInputService.LastInputTypeChanged:Connect(function()
		task.defer(refreshVisible)
	end)
end

------------------------------------------------------------------------
-- (v1.9) the player's own layout: drag every button where it suits his thumbs; it is saved with the settings
------------------------------------------------------------------------

local function parseLayout(s: string): { [string]: Vector2 }
	local out = {}
	for name, x, y in string.gmatch(s, "([%w_]+)=([%d%.%-]+),([%d%.%-]+)") do
		local nx, ny = tonumber(x), tonumber(y)
		if nx and ny then
			out[name] = Vector2.new(math.clamp(nx, 0.03, 0.97), math.clamp(ny, 0.05, 0.95))
		end
	end
	return out
end

function MobileControls.ApplyLayout()
	local saved = Settings.Get("mobileLayout")
	local layout = parseLayout(typeof(saved) == "string" and saved or "")
	for name, b in buttons do
		local p = layout[name]
		b.Position = p and UDim2.fromScale(p.X, p.Y) or defaults[name]
	end
end

local function saveLayout()
	local size = frame.AbsoluteSize
	if size.X < 10 or size.Y < 10 then
		return
	end
	local parts = {}
	for name, b in buttons do
		local c = b.AbsolutePosition + b.AbsoluteSize / 2 -- (the buttons are anchored in their middle)
		local rel = c - frame.AbsolutePosition
		table.insert(parts, string.format("%s=%.4f,%.4f", name, rel.X / size.X, rel.Y / size.Y))
	end
	Settings.Set("mobileLayout", table.concat(parts, ";"))
end

function MobileControls.ResetLayout()
	for name, b in buttons do
		b.Position = defaults[name]
	end
	Settings.Set("mobileLayout", "")
end

local editorUi: { banner: TextLabel, done: TextButton, reset: TextButton }? = nil

function MobileControls.SetEdit(on: boolean)
	MobileControls.editing = on
	if editorUi then
		editorUi.banner.Visible = on
		editorUi.done.Visible = on
		editorUi.reset.Visible = on
	end
	for _, b in buttons do
		b.BackgroundTransparency = on and 0.05 or 0.25
		local stroke = b:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = on and Color3.fromRGB(240, 186, 66) or Color3.new(1, 1, 1)
			stroke.Transparency = on and 0 or 0.7
		end
	end
	refreshVisible()
	if not on then
		saveLayout()
	end
end

function MobileControls.BuildEditor(f: Frame)
	local banner = Instance.new("TextLabel")
	banner.Name = "EditBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 14)
	banner.Size = UDim2.fromOffset(420, 44)
	banner.BackgroundColor3 = Color3.fromRGB(17, 15, 13)
	banner.BackgroundTransparency = 0.15
	banner.BorderSizePixel = 0
	banner.Font = Enum.Font.Sarpanch
	banner.TextSize = 16
	banner.TextWrapped = true
	banner.TextColor3 = Color3.fromRGB(240, 186, 66)
	banner.Text = "Drag the buttons where you want them. Tap DONE to save."
	banner.Visible = false
	banner.ZIndex = 30
	banner.Parent = f
	local function small(name: string, text: string, x: number, color: Color3): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.AnchorPoint = Vector2.new(0.5, 0)
		b.Position = UDim2.new(0.5, x, 0, 64)
		b.Size = UDim2.fromOffset(120, 38)
		b.BackgroundColor3 = color
		b.BorderSizePixel = 0
		b.Font = Enum.Font.Sarpanch
		b.TextSize = 16
		b.TextColor3 = Color3.new(0, 0, 0)
		b.Text = text
		b.Visible = false
		b.ZIndex = 30
		b.Parent = f
		return b
	end
	local done = small("EditDone", "DONE", -66, Color3.fromRGB(138, 176, 86))
	local reset = small("EditReset", "RESET", 66, Color3.fromRGB(240, 186, 66))
	done.Activated:Connect(function()
		MobileControls.SetEdit(false)
	end)
	reset.Activated:Connect(function()
		MobileControls.ResetLayout()
	end)
	editorUi = { banner = banner, done = done, reset = reset }

	-- dragging
	local dragging: TextButton? = nil
	local dragInput: InputObject? = nil
	for _, b in buttons do
		b.InputBegan:Connect(function(io)
		if Input.IsControlled() then return end
			if MobileControls.editing and (io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1) then
				dragging = b
				dragInput = io
			end
		end)
	end
	UserInputService.InputChanged:Connect(function(io)
		if Input.IsControlled() then return end
		local b = dragging
		if not b then
			return
		end
		if io.UserInputType == Enum.UserInputType.Touch and io ~= dragInput then
			return
		end
		if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseMovement then
			local size = f.AbsoluteSize
			if size.X < 10 or size.Y < 10 then
				return
			end
			local rel = Vector2.new(io.Position.X, io.Position.Y) - f.AbsolutePosition
			b.Position = UDim2.fromScale(math.clamp(rel.X / size.X, 0.03, 0.97), math.clamp(rel.Y / size.Y, 0.05, 0.95))
		end
	end)
	UserInputService.InputEnded:Connect(function(io)
		if Input.IsControlled() then return end
		if dragging and (io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = nil
			dragInput = nil
			saveLayout()
		end
	end)
end

return MobileControls
