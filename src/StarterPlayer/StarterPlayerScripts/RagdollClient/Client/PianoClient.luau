--!nonstrict
-- PianoClient (v1.9): press the prompt at a piano and a keyboard opens. Play with the mouse / your finger on
-- the keys, or with the keyboard: A S D F G H J K L ; = white keys, W E T Y U O P = black keys.
-- Esc, the X, or walking away closes it. The notes are heard by everybody near the piano.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))
local UI = require(script.Parent:WaitForChild("UI"))
local Input = require(script.Parent:WaitForChild("Input"))

local C = UI.C
local player = Players.LocalPlayer

local PianoClient = {}

-- semitone offsets: white keys then black keys, with the computer key that plays each one
local WHITE = {
	{ 0, Enum.KeyCode.A, "A" }, { 2, Enum.KeyCode.S, "S" }, { 4, Enum.KeyCode.D, "D" }, { 5, Enum.KeyCode.F, "F" },
	{ 7, Enum.KeyCode.G, "G" }, { 9, Enum.KeyCode.H, "H" }, { 11, Enum.KeyCode.J, "J" }, { 12, Enum.KeyCode.K, "K" },
	{ 14, Enum.KeyCode.L, "L" }, { 16, Enum.KeyCode.Semicolon, ";" },
}
-- black keys sit between white key index i and i+1
local BLACK = { { 1, Enum.KeyCode.W, "W", 1 }, { 3, Enum.KeyCode.E, "E", 2 }, { 6, Enum.KeyCode.T, "T", 4 }, { 8, Enum.KeyCode.Y, "Y", 5 }, { 10, Enum.KeyCode.U, "U", 6 }, { 13, Enum.KeyCode.O, "O", 8 }, { 15, Enum.KeyCode.P, "P", 9 } }

local gui: ScreenGui? = nil
local root: BasePart? = nil
local held: { [Enum.KeyCode]: boolean } = {}
local keyButtons: { [number]: TextButton } = {}
local conn: RBXScriptConnection? = nil

local function play(semi: number)
	local r = root
	if not r then
		return
	end
	SoundLibrary.Play("tvNote", r, 0.9, 2 ^ ((semi - 5) / 12))
	local b = keyButtons[semi]
	if b then
		local black = b:GetAttribute("Black")
		b.BackgroundColor3 = black and Color3.fromRGB(80, 80, 90) or Color3.fromRGB(255, 226, 150)
		task.delay(0.16, function()
			if b.Parent then
				b.BackgroundColor3 = black and Color3.fromRGB(20, 20, 24) or Color3.fromRGB(244, 242, 234)
			end
		end)
	end
end

local function close()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	ContextActionService:UnbindAction("PianoKeys")
	if gui then
		gui:Destroy()
		gui = nil
	end
	root = nil
	Input.promptOpen = false
	Input.keysCaptured = false
end

local function open(piano: BasePart)
	if gui then
		close()
	end
	root = piano
	Input.promptOpen = true
	Input.keysCaptured = true
	gui = UI.make("ScreenGui", { Name = "Piano", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 20, Parent = player:WaitForChild("PlayerGui") })
	local w = 10 * 62 + 40
	local panel = UI.panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.fromOffset(w, 230),
		Accent = C.amber,
		Parent = gui,
	})
	UI.make("UIScale", { Name = "Scale", Scale = math.min(1, (workspace.CurrentCamera.ViewportSize.X - 20) / w), Parent = panel })
	UI.label({ Text = "PIANO", Font = UI.FONT_TITLE, TextSize = 18, Position = UDim2.fromOffset(16, 8), Size = UDim2.fromOffset(200, 22), Parent = panel })
	UI.label({ Text = "A S D F G H J K L ;  white      W E T Y U O P  black", TextSize = 13, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(1, -330, 0, 10), Size = UDim2.fromOffset(280, 20), Parent = panel })
	UI.button({ Text = "X", Size = UDim2.fromOffset(28, 24), Position = UDim2.new(1, -38, 0, 8), Parent = panel }, close)
	keyButtons = {}
	for i, k in WHITE do
		local b = UI.make("TextButton", {
			Text = k[3],
			Font = UI.FONT_BODY,
			TextSize = 16,
			TextColor3 = Color3.fromRGB(90, 90, 96),
			TextYAlignment = Enum.TextYAlignment.Bottom,
			AutoButtonColor = false,
			BackgroundColor3 = Color3.fromRGB(244, 242, 234),
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(20 + (i - 1) * 62, 40),
			Size = UDim2.fromOffset(60, 170),
			Parent = panel,
		})
		keyButtons[k[1]] = b
		b.MouseButton1Down:Connect(function()
			play(k[1])
		end)
	end
	for _, k in BLACK do
		local b = UI.make("TextButton", {
			Text = k[3],
			Font = UI.FONT_BODY,
			TextSize = 14,
			TextColor3 = Color3.fromRGB(190, 190, 196),
			TextYAlignment = Enum.TextYAlignment.Bottom,
			AutoButtonColor = false,
			BackgroundColor3 = Color3.fromRGB(20, 20, 24),
			BorderSizePixel = 0,
			ZIndex = 3,
			Position = UDim2.fromOffset(20 + (k[4]) * 62 - 20, 40),
			Size = UDim2.fromOffset(40, 104),
			Parent = panel,
		})
		b:SetAttribute("Black", true)
		keyButtons[k[1]] = b
		b.MouseButton1Down:Connect(function()
			play(k[1])
		end)
	end
	-- the computer keyboard: these keys belong to the piano while it is open
	local keys = { Enum.KeyCode.Escape }
	local map: { [Enum.KeyCode]: number } = {}
	for _, k in WHITE do
		table.insert(keys, k[2])
		map[k[2]] = k[1]
	end
	for _, k in BLACK do
		table.insert(keys, k[2])
		map[k[2]] = k[1]
	end
	ContextActionService:BindActionAtPriority("PianoKeys", function(_, state, io)
		if io.KeyCode == Enum.KeyCode.Escape then
			if state == Enum.UserInputState.Begin then
				close()
			end
			return Enum.ContextActionResult.Sink
		end
		if state == Enum.UserInputState.Begin then
			local semi = map[io.KeyCode]
			if semi then
				play(semi)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 10, table.unpack(keys))
	-- walking away closes it
	conn = RunService.Heartbeat:Connect(function()
		local c = player.Character
		local t = c and c:FindFirstChild("Torso")
		if not root or not root.Parent or not t or (t.Position - root.Position).Magnitude > 16 then
			close()
		end
	end)
end

function PianoClient.Init()
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who ~= player or prompt.Name ~= "PianoPrompt" then
			return
		end
		local part = prompt.Parent
		if part and part:IsA("BasePart") then
			open(part)
		end
	end)
end

return PianoClient
