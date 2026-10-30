--!nonstrict
-- UI: the look of the HUD (dark flat panels with a coloured edge, condensed type) for the menus
-- that live in their own modules (settings / admin menu, game mode bar).

local Settings = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Settings"))

local UI = {}

UI.C = {
	panel = Color3.fromRGB(8, 8, 8), panel2 = Color3.fromRGB(23, 23, 23), panel3 = Color3.fromRGB(43, 43, 43),
	line = Color3.fromRGB(88, 88, 88), text = Color3.fromRGB(240, 240, 240), dim = Color3.fromRGB(168, 168, 168),
	accent = Color3.fromRGB(204, 204, 204), amber = Color3.fromRGB(220, 220, 220), good = Color3.fromRGB(205, 205, 205),
	bad = Color3.fromRGB(65, 65, 65), red = Color3.fromRGB(210, 210, 210), blue = Color3.fromRGB(190, 190, 190),
}
local SoundLibrary = require(game:GetService("ReplicatedStorage").Shared.SoundLibrary)
local lastHover = 0
local function neutral(c: Color3, background: boolean): Color3
	local hi, lo = math.max(c.R, c.G, c.B), math.min(c.R, c.G, c.B)
	if hi - lo < 0.015 then
		if background and hi > 0.3 then return Color3.new(0.2, 0.2, 0.2) end
		if not background and hi < 0.3 then return Color3.new(0.85, 0.85, 0.85) end
		return c
	end
	local v = c.R * 0.21 + c.G * 0.72 + c.B * 0.07
	v = background and math.clamp(v * 0.3, 0.025, 0.22) or math.clamp(v, 0.62, 0.96)
	return Color3.new(v, v, v)
end
local function theme(inst, props)
	if inst:IsA("ViewportFrame") then return end
	local fields = {}
	if inst:IsA("GuiObject") then
		-- Full-screen transient flashes are effects, not menus.
		local size = props.Size
		local effect = inst:IsA("Frame") and size and size.X.Scale == 1 and size.Y.Scale == 1 and (props.ZIndex or 1) >= 5
		if not effect then table.insert(fields, { "BackgroundColor3", true }) end
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then table.insert(fields, { "TextColor3", false }) end
	if inst:IsA("UIStroke") then table.insert(fields, { "Color", false }) end
	for _, f in fields do
		local function apply()
			local color = inst[f[1]]
			local n = neutral(color, f[2])
			if n ~= color then inst[f[1]] = n end
		end
		apply()
		inst:GetPropertyChangedSignal(f[1]):Connect(apply)
	end
	if inst:IsA("GuiButton") then
		inst.Activated:Connect(function() SoundLibrary.Play("click", nil, 0.55) end)
		inst.MouseEnter:Connect(function()
			if os.clock() - lastHover > 0.08 then lastHover = os.clock(); SoundLibrary.Play("rollTick", nil, 0.16) end
		end)
	end
end

-- (v2.0: ONE font for everything in the game - menus, HUD, name tags, signs, prompts, chat: the squared "Sarpanch")
UI.FONT = Enum.Font.GothamMedium
UI.FONT_TITLE = UI.FONT
UI.FONT_BODY = UI.FONT
UI.FONT_NUM = UI.FONT

function UI.make(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	theme(inst, props)
	return inst
end

-- (v2.0) square: every box of the game's own UI has hard, straight corners
function UI.corner(_r: number): UICorner
	return UI.make("UICorner", { CornerRadius = UDim.new(0, 0) })
end

-- a flat dark box with a thin coloured bar on its left edge
function UI.panel(props: { [string]: any }): Frame
	props.BackgroundColor3 = props.BackgroundColor3 or UI.C.panel
	props.BackgroundTransparency = props.BackgroundTransparency or 0.04
	props.BorderSizePixel = 0
	local accent = props.Accent
	props.Accent = nil
	local f = UI.make("Frame", props)
	UI.make("Frame", {
		Name = "Edge",
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = accent or UI.C.accent,
		BorderSizePixel = 0,
		ZIndex = props.ZIndex or 1,
		Parent = f,
	})
	return f
end

function UI.label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.TextColor3 = props.TextColor3 or UI.C.text
	props.Font = props.Font or UI.FONT_BODY
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return UI.make("TextLabel", props)
end

-- a flat button; onClick runs on click / tap / gamepad A
function UI.button(props: { [string]: any }, onClick: () -> ()): TextButton
	props.BackgroundColor3 = props.BackgroundColor3 or UI.C.panel2
	props.BackgroundTransparency = props.BackgroundTransparency or 0.05
	props.BorderSizePixel = 0
	props.AutoButtonColor = true
	props.TextColor3 = props.TextColor3 or UI.C.text
	props.Font = props.Font or UI.FONT_TITLE
	props.TextSize = props.TextSize or 14
	local b = UI.make("TextButton", props, { UI.corner(3) })
	b.Activated:Connect(onClick)
	return b
end

-- (v2.0) the UI size setting (M > SETTINGS > UI size): every menu and panel is scaled by it
function UI.Global(): number
	local v = Settings.Get("uiScale")
	return typeof(v) == "number" and math.clamp(v, 0.6, 1.6) or 1
end

-- Every top-level frame of every ScreenGui gets a "GlobalScale" UIScale (it scales round the frame's anchor
-- point, so a panel in a corner stays in its corner). A frame that already has its own UIScale: a static one
-- (set once, to fit the screen) is multiplied; one marked "Managed" is set by its module, which multiplies by
-- UI.Global() itself.
local scalerOn = false
function UI.InitGlobalScale(playerGui: Instance)
	if scalerOn then
		return
	end
	scalerOn = true
	local function apply()
		local g = UI.Global()
		for _, sg in playerGui:GetChildren() do
			if not sg:IsA("ScreenGui") or sg:GetAttribute("NoGlobalScale") then
				continue
			end
			for _, top in sg:GetChildren() do
				if not top:IsA("GuiObject") then
					continue
				end
				local own: UIScale? = nil
				local mine: UIScale? = nil
				for _, c in top:GetChildren() do
					if c:IsA("UIScale") then
						if c.Name == "GlobalScale" then
							mine = c
						else
							own = c
						end
					end
				end
				if own then
					if mine then
						mine:Destroy()
					end
					if not own:GetAttribute("Managed") then
						local base = own:GetAttribute("BaseScale")
						if typeof(base) ~= "number" then
							base = own.Scale
							own:SetAttribute("BaseScale", base)
						end
						own.Scale = (base :: number) * g
					end
				elseif g ~= 1 or mine then
					if not mine then
						local m = Instance.new("UIScale")
						m.Name = "GlobalScale"
						m.Parent = top
						mine = m
					end
					(mine :: UIScale).Scale = g
				end
			end
		end
	end
	Settings.Changed:Connect(function(key)
		if key == "uiScale" then
			apply()
		end
	end)
	task.spawn(function()
		while true do
			apply()
			task.wait(1)
		end
	end)
end

-- (v2.0) every text in the game in the one font: whatever is (or gets) under `root` - text that a module made
-- without a font, signs, the TV - is switched to it
function UI.EnforceFont(root: Instance)
	local function fix(d: Instance)
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			local t = d :: any
			if t.Font ~= UI.FONT then
				t.Font = UI.FONT
			end
		end
	end
	for _, d in root:GetDescendants() do
		fix(d)
	end
	root.DescendantAdded:Connect(fix)
end

-- the chat (window, input bar, bubbles) in the same font, where Roblox lets a game set it
function UI.ChatFont()
	pcall(function()
		local tcs = game:GetService("TextChatService")
		local face = Font.fromEnum(UI.FONT)
		local win = tcs:FindFirstChildOfClass("ChatWindowConfiguration")
		if win then
			win.FontFace = face
		end
		local bar = tcs:FindFirstChildOfClass("ChatInputBarConfiguration")
		if bar then
			(bar :: any).FontFace = face
		end
		local bub = tcs:FindFirstChildOfClass("BubbleChatConfiguration")
		if bub then
			bub.FontFace = face
		end
	end)
end

return UI
