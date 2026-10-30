--!nonstrict
-- PromptUI (v2.0): our own look for every "press F" prompt (talk to the master, play the piano, ...), in the game's
-- font and colours instead of Roblox's default prompt. Every ProximityPrompt is switched to the Custom style here;
-- what it does is unchanged (the key still triggers it; a tap / click on the box works too).
-- The look: a plain rectangle - no rounded corners, no glow, no outline. A solid amber key block on the left with
-- the key in black, the action in white capitals, what it is in grey under it, a thin amber line along the bottom
-- that fills while you hold the key.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local player = Players.LocalPlayer
local C = UI.C

local PromptUI = {}

local GAMEPAD_NAMES = {
	[Enum.KeyCode.ButtonA] = "A",
	[Enum.KeyCode.ButtonB] = "B",
	[Enum.KeyCode.ButtonX] = "X",
	[Enum.KeyCode.ButtonY] = "Y",
	[Enum.KeyCode.ButtonL1] = "LB",
	[Enum.KeyCode.ButtonR1] = "RB",
}

local function adopt(d: Instance)
	if d:IsA("ProximityPrompt") then
		d.Style = Enum.ProximityPromptStyle.Custom
	end
end

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return GAMEPAD_NAMES[prompt.GamepadKeyCode] or string.gsub(prompt.GamepadKeyCode.Name, "Button", "")
	end
	local name = prompt.KeyboardKeyCode.Name
	return #name <= 6 and string.upper(name) or string.upper(string.sub(name, 1, 5))
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType, gui: ScreenGui)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Prompt"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(240, 58)
	bb.SizeOffset = Vector2.new(prompt.UIOffset.X / 240, prompt.UIOffset.Y / 58)
	bb.StudsOffset = Vector3.new(0, 1.2, 0)
	bb.Active = true
	bb.Adornee = prompt.Parent
	bb.ResetOnSpawn = false
	bb.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6 * UI.Global()
	scale.Parent = bb
	TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = UI.Global() }):Play()

	local panel = UI.make("Frame", {
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(14, 14, 16),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Parent = bb,
	})
	-- the key: a solid block, the letter in black
	local cap = UI.make("Frame", {
		Name = "Cap",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(0, 50, 1, 0),
		BackgroundColor3 = C.amber,
		BorderSizePixel = 0,
		Parent = panel,
	})
	UI.make("TextLabel", {
		Name = "Key",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = UI.FONT_TITLE,
		Text = keyText(prompt, inputType),
		TextSize = 22,
		TextColor3 = Color3.fromRGB(14, 14, 16),
		Parent = cap,
	})
	-- holding: a line along the bottom of the box fills up
	UI.make("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 50, 1, 0),
		Size = UDim2.new(1, -50, 0, 3),
		BackgroundColor3 = Color3.fromRGB(60, 50, 26),
		BorderSizePixel = 0,
		Parent = panel,
	})
	local fill = UI.make("Frame", {
		Name = "Hold",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 50, 1, 0),
		Size = UDim2.new(0, 0, 0, 3),
		BackgroundColor3 = C.amber,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = panel,
	})
	local holdFull = UDim2.new(1, -50, 0, 3)
	local holdEmpty = UDim2.new(0, 0, 0, 3)
	local action = UI.make("TextLabel", {
		Name = "Action",
		Position = UDim2.fromOffset(62, prompt.ObjectText ~= "" and 7 or 0),
		Size = UDim2.new(1, -70, 0, prompt.ObjectText ~= "" and 24 or 58),
		BackgroundTransparency = 1,
		Font = UI.FONT_TITLE,
		Text = string.upper(prompt.ActionText),
		TextSize = 21,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = panel,
	})
	local object = UI.make("TextLabel", {
		Name = "Object",
		Position = UDim2.fromOffset(62, 31),
		Size = UDim2.new(1, -70, 0, 18),
		BackgroundTransparency = 1,
		Font = UI.FONT_TITLE,
		Text = string.upper(prompt.ObjectText),
		TextSize = 14,
		TextColor3 = Color3.fromRGB(150, 150, 156),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = prompt.ObjectText ~= "",
		Parent = panel,
	})
	-- tap / click on the box = the key
	local button = UI.make("TextButton", {
		Name = "Press",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Parent = panel,
	})
	local conns = {}
	if inputType == Enum.ProximityPromptInputType.Touch or prompt.ClickablePrompt then
		table.insert(conns, button.InputBegan:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
				prompt:InputHoldBegin()
			end
		end))
		table.insert(conns, button.InputEnded:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
				prompt:InputHoldEnd()
			end
		end))
	end
	local holdTween: Tween? = nil
	table.insert(conns, prompt.PromptButtonHoldBegan:Connect(function()
		if prompt.HoldDuration > 0 then
			local tw = TweenService:Create(fill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Size = holdFull })
			tw:Play()
			holdTween = tw
		end
		cap.BackgroundColor3 = Color3.new(1, 1, 1)
	end))
	table.insert(conns, prompt.PromptButtonHoldEnded:Connect(function()
		if holdTween then
			holdTween:Cancel()
		end
		fill.Size = holdEmpty
		cap.BackgroundColor3 = C.amber
	end))
	table.insert(conns, prompt.Triggered:Connect(function()
		-- a quick flash on the key block
		cap.BackgroundColor3 = Color3.new(1, 1, 1)
		TweenService:Create(cap, TweenInfo.new(0.25), { BackgroundColor3 = C.amber }):Play()
	end))
	table.insert(conns, prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
		action.Text = string.upper(prompt.ActionText)
	end))
	table.insert(conns, prompt:GetPropertyChangedSignal("ObjectText"):Connect(function()
		object.Text = string.upper(prompt.ObjectText)
	end))
	return function()
		for _, c in conns do
			c:Disconnect()
		end
		bb:Destroy()
	end
end

function PromptUI.Init()
	for _, d in workspace:GetDescendants() do
		adopt(d)
	end
	workspace.DescendantAdded:Connect(adopt)
	local gui = UI.make("ScreenGui", { Name = "Prompts", ResetOnSpawn = false, Parent = player:WaitForChild("PlayerGui") })
	gui:SetAttribute("NoGlobalScale", true) -- (the billboards scale themselves)
	local open: { [ProximityPrompt]: () -> () } = {}
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
			return -- (Roblox draws this one itself)
		end
		if open[prompt] then
			open[prompt]()
		end
		open[prompt] = show(prompt, inputType, gui)
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		local close = open[prompt]
		if close then
			open[prompt] = nil
			close()
		end
	end)
end

return PromptUI
