--!nonstrict
-- HUD: crosshair with hand chips, body condition card, held items, ammo counter, context hints,
-- controls help (per device), categorized spawn menu, death screen, damage flash.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))
local PropCatalog = require(Shared:WaitForChild("PropCatalog"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))
local Items = require(Shared:WaitForChild("Items"))
local Settings = require(Shared:WaitForChild("Settings"))

local SandboxRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Sandbox") :: RemoteEvent

local Input = require(script.Parent:WaitForChild("Input"))
local UI = require(script.Parent:WaitForChild("UI"))
local VehicleClient = require(script.Parent:WaitForChild("VehicleClient"))
local Cam = require(script.Parent:WaitForChild("CameraController"))
local Dream = require(script.Parent:WaitForChild("Dream"))

local ItemRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Item") :: RemoteEvent

local player = Players.LocalPlayer

local HUD = {}

local controller = nil
local gui: ScreenGui
local refs: any = {}

local C = {
	panel = Color3.fromRGB(17, 15, 13),
	panel2 = Color3.fromRGB(38, 35, 30),
	line = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(238, 231, 218),
	dim = Color3.fromRGB(165, 156, 140),
	accent = Color3.fromRGB(226, 112, 34),
	amber = Color3.fromRGB(240, 186, 66),
	good = Color3.fromRGB(138, 176, 86),
	bad = Color3.fromRGB(205, 62, 48),
	gone = Color3.fromRGB(40, 40, 44),
	useF = Color3.fromRGB(255, 136, 32),
	prop = Color3.fromRGB(70, 200, 92),
}
-- plain game-like type: condensed headings, a condensed body face, numbers in mono
local FONT_TITLE = Enum.Font.Sarpanch
local FONT_BODY = Enum.Font.Sarpanch -- (v2.0: one font for everything)
local FONT_BOLD = Enum.Font.Sarpanch
local FONT_NUM = Enum.Font.Sarpanch

-- a key in a hint: [F]
local function key(k: string): string
	return '<font color="#F2B33D"><b>[' .. k .. "]</b></font>"
end
-- (v2.8) the key of an action the player can change (M > SETTINGS > KEYS)
local function akey(action: string): string
	return key(Input.KeyName(action))
end

local function make(className: string, props: { [string]: any }, children: { Instance }?): any
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
	return inst
end

local function corner(_r: number): UICorner
	return make("UICorner", { CornerRadius = UDim.new(0, 0) }) -- (v2.0: square boxes)
end

local function stroke(t: number, color: Color3?, thickness: number?): UIStroke
	return make("UIStroke", { Color = color or C.line, Transparency = t, Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

-- a flat dark box with a thin coloured bar on its left edge
local function panel(props: { [string]: any }): Frame
	props.BackgroundColor3 = props.BackgroundColor3 or C.panel
	props.BackgroundTransparency = props.BackgroundTransparency or 0.25
	props.BorderSizePixel = 0
	local accent = props.Accent
	props.Accent = nil
	local f = make("Frame", props)
	make("Frame", {
		Name = "Edge",
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = accent or C.accent,
		BorderSizePixel = 0,
		ZIndex = props.ZIndex or 1,
		Parent = f,
	})
	return f
end

local function label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.TextColor3 = props.TextColor3 or C.text
	props.Font = props.Font or FONT_BODY
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return make("TextLabel", props)
end

------------------------------------------------------------------------
-- crosshair + hand chips
------------------------------------------------------------------------

local function buildCrosshair()
	local root = make("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(140, 30),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = root,
	}, { corner(2), stroke(0.4, Color3.new(0, 0, 0)) })
	for i, off in { Vector2.new(0, -9), Vector2.new(0, 9), Vector2.new(-9, 0), Vector2.new(9, 0) } do
		local vertical = i <= 2
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, off.X, 0.5, off.Y),
			Size = vertical and UDim2.fromOffset(2, 6) or UDim2.fromOffset(6, 2),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			Parent = root,
		})
	end
	local function chip(name: string, x: number)
		local f = make("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, x, 0.5, 0),
			Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = C.panel,
			BackgroundTransparency = 0.35,
			Parent = root,
		}, { corner(13), make("UIStroke", { Name = "Ring", Color = Color3.new(1, 1, 1), Transparency = 0.6, Thickness = 1.5 }) })
		label({ Name = "Key", Size = UDim2.fromScale(1, 1), Text = "", TextXAlignment = Enum.TextXAlignment.Center, Font = FONT_BOLD, TextSize = 11, Parent = f })
		return f
	end
	refs.handL = chip("LeftHand", -40)
	refs.handR = chip("RightHand", 40)
	refs.crosshair = root
end

------------------------------------------------------------------------
-- body card
------------------------------------------------------------------------

local function buildBodyCard()
	local p = panel({
		Name = "Body",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(250, 176),
		Parent = gui,
	})
	label({ Text = "CONDITION", Font = FONT_TITLE, TextSize = 11, TextColor3 = C.dim, Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(120, 14), Parent = p })
	local pill = make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.accent,
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = p,
	}, { corner(9), make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })
	refs.statePillText = label({ Text = "", Font = FONT_BOLD, TextSize = 10, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Parent = pill })
	refs.statePill = pill

	-- silhouette
	local fig = make("Frame", { Name = "Figure", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 34), Size = UDim2.fromOffset(68, 124), Parent = p })
	local u = 16.5
	local layout = {
		Head = { 1.3, 0, 1.5, 1.05 },
		Torso = { 1.05, 1.15, 2, 2.05 },
		LeftArm = { 0, 1.15, 0.95, 2.05 },
		RightArm = { 3.15, 1.15, 0.95, 2.05 },
		LeftLeg = { 1.05, 3.3, 0.95, 2.55 },
		RightLeg = { 2.1, 3.3, 0.95, 2.55 },
	}
	refs.regions = {}
	for region, l in layout do
		local f = make("Frame", {
			Name = region,
			Position = UDim2.fromOffset(l[1] * u, l[2] * u),
			Size = UDim2.fromOffset(l[3] * u, l[4] * u),
			BackgroundColor3 = C.good,
			BorderSizePixel = 0,
			Parent = fig,
		}, { corner(4), make("UIStroke", { Name = "S", Color = Color3.new(0, 0, 0), Transparency = 0.5, Thickness = 1 }) })
		-- crack line shown for broken parts
		make("Frame", {
			Name = "Crack",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1.15, 0, 0, 2),
			Rotation = -55,
			BackgroundColor3 = Color3.fromRGB(30, 4, 6),
			BorderSizePixel = 0,
			Visible = false,
			Parent = f,
		})
		refs.regions[region] = f
	end

	local info = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(104, 34), Size = UDim2.fromOffset(134, 130), Parent = p })
	refs.bloodText = label({ Text = "BLOOD 100%", Font = FONT_BOLD, TextSize = 11, TextColor3 = C.dim, Size = UDim2.fromOffset(134, 14), Parent = info })
	local bar = make("Frame", { Position = UDim2.fromOffset(0, 17), Size = UDim2.fromOffset(130, 7), BackgroundColor3 = Color3.fromRGB(48, 14, 16), BorderSizePixel = 0, Parent = info }, { corner(4) })
	refs.bloodFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(196, 38, 34), BorderSizePixel = 0, Parent = bar }, { corner(4) })
	refs.stance = label({ Text = "STANDING", Font = FONT_BOLD, TextSize = 10, TextColor3 = C.dim, Position = UDim2.fromOffset(0, 30), Size = UDim2.fromOffset(134, 12), Parent = info })
	local list = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 48), Size = UDim2.fromOffset(134, 82), Parent = info })
	make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	refs.statusList = list
	refs.statusChips = {}
end

local function setChips(entries: { { text: string, color: Color3 } })
	local list = refs.statusList
	for i, e in entries do
		local chip = refs.statusChips[i]
		if not chip then
			chip = make("Frame", {
				Size = UDim2.fromOffset(0, 16),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = e.color,
				BackgroundTransparency = 0.8,
				LayoutOrder = i,
				Parent = list,
			}, { corner(5), make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }) })
			label({ Name = "T", Text = "", Font = FONT_BOLD, TextSize = 10, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Parent = chip })
			refs.statusChips[i] = chip
		end
		chip.Visible = true
		chip.BackgroundColor3 = e.color
		local t = chip:FindFirstChild("T") :: TextLabel
		t.Text = e.text
		t.TextColor3 = e.color:Lerp(Color3.new(1, 1, 1), 0.35)
	end
	for i = #entries + 1, #refs.statusChips do
		refs.statusChips[i].Visible = false
	end
end

------------------------------------------------------------------------
-- held items, ammo, context hints
------------------------------------------------------------------------

local function buildBottom()
	refs.hold = label({
		Name = "Hold",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(560, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 14,
		RichText = true,
		TextStrokeTransparency = 0.6,
		Text = "",
		Parent = gui,
	})
	local hint = make("Frame", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -48),
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.25,
		Visible = false,
		Parent = gui,
	}, { corner(14), stroke(0.85), make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }) })
	refs.hintText = label({ Text = "", TextSize = 13, RichText = true, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Parent = hint })
	refs.hint = hint

	local ammo = panel({
		Name = "Ammo",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(190, 84),
		Visible = false,
		Parent = gui,
	})
	refs.ammoTitle = label({ Text = "PISTOL", Font = FONT_TITLE, TextSize = 11, TextColor3 = C.dim, Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(100, 14), Parent = ammo })
	refs.ammoNum = label({ Text = "12", Font = FONT_NUM, TextSize = 34, Position = UDim2.fromOffset(14, 26), Size = UDim2.fromOffset(60, 36), Parent = ammo })
	refs.ammoMax = label({ Text = "/ 12", Font = FONT_NUM, TextSize = 14, TextColor3 = C.dim, Position = UDim2.fromOffset(70, 40), Size = UDim2.fromOffset(60, 18), Parent = ammo })
	refs.ammoNote = label({ Text = "F  FIRE", Font = FONT_BOLD, TextSize = 10, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 11), Size = UDim2.fromOffset(100, 12), Parent = ammo })
	local pips = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 66), Size = UDim2.fromOffset(162, 8), Parent = ammo })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2), Parent = pips })
	refs.pips = {}
	local most = 0
	for _, g in Config.Guns do
		most = math.max(most, g.mag)
	end
	for i = 1, most do
		refs.pips[i] = make("Frame", { Size = UDim2.fromOffset(10, 8), BackgroundColor3 = C.amber, BorderSizePixel = 0, LayoutOrder = i, Parent = pips }, { corner(2) })
	end
	refs.ammo = ammo
end

------------------------------------------------------------------------
-- hand cursor (while LMB / RMB moves an arm): open hand, closed while that hand holds something
------------------------------------------------------------------------

local function buildHandCursor()
	local root = make("Frame", {
		Name = "HandCursor",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(30, 34),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 50,
		Parent = gui,
	})
	local skin = Color3.fromRGB(246, 238, 228)
	local function blob(name: string, pos: UDim2, size: UDim2, rot: number?)
		return make("Frame", {
			Name = name,
			Position = pos,
			Size = size,
			Rotation = rot or 0,
			BackgroundColor3 = skin,
			BorderSizePixel = 0,
			ZIndex = 50,
			Parent = root,
		}, { corner(4), make("UIStroke", { Color = Color3.fromRGB(20, 20, 24), Thickness = 1.6 }) })
	end
	blob("Palm", UDim2.fromOffset(6, 14), UDim2.fromOffset(19, 17))
	refs.handFingers = {}
	for i = 0, 3 do
		refs.handFingers[i + 1] = blob("Finger", UDim2.fromOffset(6 + i * 5, 2 + (i == 0 and 3 or i == 3 and 4 or 0)), UDim2.fromOffset(4, 14))
	end
	blob("Thumb", UDim2.fromOffset(0, 15), UDim2.fromOffset(9, 4), -35)
	refs.handCursor = root
end

local function updateHandCursor()
	local show = Input.HandControlActive() and Input.UsesCursor() and not Input.menuOpen
	refs.handCursor.Visible = show
	if not show then
		return
	end
	local m = UserInputService:GetMouseLocation()
	refs.handCursor.Position = UDim2.fromOffset(m.X, m.Y)
	local closed = Input.handHolding
	for i, f in refs.handFingers do
		local base = (i == 1 and 5 or i == 4 and 6 or 2)
		f.Size = UDim2.fromOffset(4, closed and 6 or 14)
		f.Position = UDim2.fromOffset(6 + (i - 1) * 5, closed and 11 or base)
	end
end

------------------------------------------------------------------------
-- help
------------------------------------------------------------------------

local HELP = {
	KeyboardMouse = {
		{ "W A S D", "Walk" },
		{ "SHIFT", "Run" },
		{ "SPACE", "Jump. Hold it while holding a ledge to climb" },
		{ "Q / E", "Close the left / right hand to grab, again to let go" },
		{ "LMB / RMB", "Hold: that arm points at the cursor" },
		{ "F", "Use what you hold (hold: full auto). Talk to people" },
		{ "G", "Hold: aim the gun (scope: the wheel zooms). No gun: car" },
		{ "{TwoHand}", "Hold the item with both hands, less recoil" },
		{ "RELOAD", "Free hand's mouse button, touch the gun" },
		{ "{Kick}", "Kick. Jump first for a drop kick" },
		{ "CTRL / {Prone}", "Crouch / lie down. {Prone} in a jump: dive" },
		{ "SHIFT + CTRL", "Slide. Slide into someone: they fall over" },
		{ "{Weave}", "Weave: duck out of a punch" },
		{ "{Car}", "Car in / out (take a bot's car). Owner: fly" },
		{ "IN THE JET", "W/S throttle, F gun, {Kick} missile, {Prone} bomb, {Car} eject" },
		{ "{FirstPerson} / {Ragdoll}", "First person / go limp" },
		{ "J", "Out of the round: watch the next player" },
		{ "{SuperPunch} / K", "Owner: super punch / laser eyes (flying)" },
		{ "{Hotdog} / {TimeStop} / U", "Admin: hotdog / time stop / free cam" },
		{ "{Menu} / {Settings} / {Help}", "Spawn menu / menu: codes, titles, settings, keys / help" },
	},
	Gamepad = {
		{ "L-STICK / L3", "Walk / toggle run" },
		{ "A", "Jump. Hold while holding a ledge: climb" },
		{ "L1 / R1", "Close the left / right hand" },
		{ "L2 / R2", "Hold: aim that hand at the crosshair" },
		{ "X", "Use what you hold (hold for full auto)" },
		{ "D-PAD LEFT", "Hold: aim the gun. No gun: car" },
		{ "D-PAD RIGHT", "Both hands on the item" },
		{ "RELOAD", "Free hand's trigger, touch the gun" },
		{ "R3", "Kick. In a jump: drop kick" },
		{ "B / D-PAD DOWN", "Crouch / lie down. In a jump: dive" },
		{ "RUN + B", "Slide. Slide into someone: they fall over" },
		{ "Y", "First person" },
		{ "D-PAD UP", "Go limp" },
		{ "SELECT / START", "Spawn menu / this help" },
	},
	Touch = {
		{ "LEFT STICK", "Walk" },
		{ "DRAG RIGHT", "Look around" },
		{ "JUMP", "Jump. Hold while hanging: climb" },
		{ "GRAB L / R", "Close the left / right hand" },
		{ "AIM L / R", "Hold: aim that hand at the crosshair" },
		{ "USE", "Use what you hold (hold for full auto)" },
		{ "SIGHT", "Hold: aim the gun" },
		{ "2 HANDS", "Both hands on the item" },
		{ "KICK", "Kick. In a jump: drop kick" },
		{ "RELOAD", "Hold the free hand's AIM, touch the gun" },
		{ "CAR", "Car in or out. Owner: fly" },
		{ "CROUCH / PRONE", "Lower stance, crawl" },
		{ "EYE / LIMP / MENU / SET", "First person, ragdoll, spawn, settings" },
	},
}
local HELP_ROWS = 20

local function buildHelp()
	local p = panel({
		Name = "Help",
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(530, 0), -- (v2.0: bigger on a PC; phones / controllers scale it down)
		AutomaticSize = Enum.AutomaticSize.Y,
		Accent = C.amber,
		Parent = gui,
	})
	local inner = make("Frame", { Name = "Inner", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = p })
	make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 14), Parent = inner })
	make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = inner })
	local head = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 0, Parent = inner })
	label({ Text = string.upper(Config.GameName), Font = FONT_TITLE, TextSize = 26, Size = UDim2.new(1, -60, 1, 0), Parent = head })
	label({ Text = Config.Version, Font = FONT_NUM, TextSize = 15, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.new(1, 0, 1, 0), Parent = head })
	refs.helpRows = {}
	for i = 1, HELP_ROWS do
		local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1 + i, Parent = inner })
		-- the key in a small box
		local cap = make("Frame", { Name = "Cap", BackgroundColor3 = C.panel2, BackgroundTransparency = 0.1, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 23), AutomaticSize = Enum.AutomaticSize.X, Parent = row }, {
			make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
		})
		local k = label({ Name = "K", Text = "", Font = FONT_BOLD, TextSize = 16, TextColor3 = C.amber, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Parent = cap })
		local v = label({ Name = "V", Text = "", Font = FONT_BODY, TextSize = 18, Position = UDim2.fromOffset(172, 0), Size = UDim2.new(1, -172, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
		refs.helpRows[i] = { row = row, k = k, v = v }
	end
	refs.help = p
	refs.helpScale = make("UIScale", { Scale = 1, Parent = p })
	refs.helpScale:SetAttribute("Managed", true) -- (refreshHelp sets it, the UI size setting included)
	refs.helpDevice = nil
	refs.helpHint = label({
		Text = "",
		Font = FONT_BOLD,
		TextSize = 13,
		TextColor3 = C.dim,
		Position = UDim2.fromOffset(18, 14),
		Size = UDim2.fromOffset(220, 16),
		Visible = false,
		Parent = gui,
	})
end

-- (v1.9) settings: hide the crosshair, the body panel, the ammo panel, the key hints, or the whole HUD.
-- A hidden frame moves to a disabled ScreenGui (the code that updates it keeps working).
local hiddenGui: ScreenGui
local HIDE_MAP = {
	Crosshair = { "hideCrosshair" },
	HandCursor = { "hideCrosshair" },
	Body = { "hideStatus" },
	Ammo = { "hideAmmo" },
	Hold = { "hideAmmo" },
	Hint = { "hideHints" },
}
local function applyHide()
	if not gui or not hiddenGui then
		return
	end
	gui.Enabled = Settings.Get("hideAll") ~= true
	for name, keys in HIDE_MAP do
		local f = gui:FindFirstChild(name) or hiddenGui:FindFirstChild(name)
		if f then
			local hide = false
			for _, k in keys do
				if Settings.Get(k) == true then
					hide = true
				end
			end
			f.Parent = hide and hiddenGui or gui
		end
	end
end

local function refreshHelp()
	local device = Input.lastDevice
	if refs.helpDevice == device then
		return
	end
	refs.helpDevice = device
	-- (v1.9: smaller on a phone / with a controller)
	-- (v2.0: 20 lines: a little smaller on a low screen)
	-- (v2.0: the panel is bigger now - 26 px rows; it still fits a low screen)
	local cam = workspace.CurrentCamera
	local fit = cam and math.clamp((cam.ViewportSize.Y - 40) / 640, 0.45, 1) or 1
	refs.helpScale.Scale = (device == "Touch" and 0.5 or (device == "Gamepad" and 0.58 or 1)) * fit * UI.Global()
	local lines = HELP[device] or HELP.KeyboardMouse
	for i, r in refs.helpRows do
		local line = lines[i]
		r.row.Visible = line ~= nil
		if line then
			r.k.Text = Input.Keyed(line[1]) -- (v2.8: the player's own keys)
			r.v.Text = Input.Keyed(line[2])
		end
	end
	refs.helpHint.Text = device == "Gamepad" and "START  CONTROLS" or device == "Touch" and "" or "H  CONTROLS"
end

------------------------------------------------------------------------
-- spawn menu
------------------------------------------------------------------------

local currentCategory = "Props"

-- the spawn menu: a narrow list on the right that scrolls (never covers half the screen)
-- (v2.0) skins: gold in the list; who has not unlocked one sees it locked (a code unlocks it: M > CODES)
local SKIN_GOLD = Color3.fromRGB(255, 206, 70)
local function skinUnlocked(id: string): boolean
	return player:GetAttribute("Skin_" .. id) == true or Items.IsOwner(player)
end

local function buildMenu()
	local p = panel({
		Name = "SpawnMenu",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0, 262, 0.6, 0),
		Visible = false,
		BackgroundTransparency = 0.15,
		Accent = C.accent,
		Parent = gui,
	})
	make("UISizeConstraint", { MinSize = Vector2.new(230, 260), MaxSize = Vector2.new(262, 470), Parent = p })
	label({ Text = "SPAWN", Font = FONT_TITLE, TextSize = 20, Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -60, 0, 26), Parent = p })
	-- a game mode runs / the owner switched spawning off: say so
	refs.spawnLocked = label({
		Text = "SPAWNING IS OFF",
		Font = FONT_BOLD,
		TextSize = 12,
		TextColor3 = C.bad,
		Position = UDim2.fromOffset(84, 12),
		Size = UDim2.new(1, -120, 0, 16),
		Visible = false,
		Parent = p,
	})
	local close = make("TextButton", {
		Text = "X",
		Font = FONT_BOLD,
		TextSize = 15,
		TextColor3 = C.dim,
		BackgroundColor3 = C.panel2,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(24, 22),
		Parent = p,
	})
	close.Activated:Connect(function()
		HUD.ToggleMenu()
	end)

	-- categories: two rows of three
	local tabs = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 36), Size = UDim2.new(1, -20, 0, 48), Parent = p })
	make("UIGridLayout", { CellSize = UDim2.new(1 / 3, -4, 0, 22), CellPadding = UDim2.fromOffset(4, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabs })
	refs.tabs = {}
	for i, cat in PropCatalog.Categories do
		local b = make("TextButton", {
			Text = string.upper(cat),
			Font = FONT_BOLD,
			TextColor3 = C.dim,
			BackgroundColor3 = C.panel2,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			TextSize = 13,
			LayoutOrder = i,
			Parent = tabs,
		})
		b.Activated:Connect(function()
			currentCategory = cat
			HUD.RefreshMenu()
			SoundLibrary.Play("click")
		end)
		refs.tabs[cat] = b
	end

	-- the list
	local list = make("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(12, 90),
		Size = UDim2.new(1, -16, 1, -152),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.dim,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = p,
	})
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	make("UIPadding", { PaddingRight = UDim.new(0, 8), Parent = list })
	refs.menuList = list
	refs.cards = {}
	for i, item in PropCatalog.Items do
		-- orange = something you use with F, green = everything else
		local swatch = item.useF and C.useF or C.prop
		local row = make("TextButton", {
			Text = "",
			AutoButtonColor = true,
			BackgroundColor3 = C.panel2,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 28),
			LayoutOrder = i,
			Parent = list,
		})
		if item.skin then
			swatch = SKIN_GOLD -- (v2.0: a skin you unlocked with a code)
		end
		make("Frame", { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = swatch, BorderSizePixel = 0, Parent = row })
		local nameL = label({ Text = string.upper(item.name), Font = FONT_BOLD, TextSize = 14, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -70, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
		local kg = PropCatalog.Kg(item, Config.MassToKg)
		local right = label({ Text = string.format("%d KG", math.floor(kg + 0.5)), Font = FONT_NUM, TextSize = 11, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.new(0, 110, 1, 0), Parent = row })
		local entry = { card = row, item = item, nameL = nameL, right = right }
		row.Activated:Connect(function()
			if item.skin and not skinUnlocked(item.skin) then
				-- (locked: where to get it)
				right.Text = "CODE: M > CODES"
				right.TextColor3 = C.amber
				SoundLibrary.Play("click", nil, 0.6, 0.7)
				return
			end
			if item.unlock and player:GetAttribute(item.unlock) ~= true and not Items.IsOwner(player) then
				right.Text = "EARN IT FIRST"
				right.TextColor3 = C.amber
				SoundLibrary.Play("click", nil, 0.6, 0.7)
				return
			end
			SandboxRemote:FireServer("spawn", item.id)
			SoundLibrary.Play("click")
		end)
		refs.cards[item.id] = entry
	end

	-- legend + clear
	local legend = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -40), Size = UDim2.new(1, -20, 0, 14), Parent = p })
	make("Frame", { Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(0, 2), BackgroundColor3 = C.useF, BorderSizePixel = 0, Parent = legend })
	label({ Text = "USE WITH F", Font = FONT_BOLD, TextSize = 11, TextColor3 = C.dim, Position = UDim2.fromOffset(15, 0), Size = UDim2.fromOffset(90, 14), Parent = legend })
	make("Frame", { Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(104, 2), BackgroundColor3 = C.prop, BorderSizePixel = 0, Parent = legend })
	label({ Text = "OTHER", Font = FONT_BOLD, TextSize = 11, TextColor3 = C.dim, Position = UDim2.fromOffset(119, 0), Size = UDim2.fromOffset(60, 14), Parent = legend })
	local clear = make("TextButton", {
		Text = "CLEAR MY STUFF",
		Font = FONT_BOLD,
		TextSize = 14,
		TextColor3 = C.text,
		BackgroundColor3 = Color3.fromRGB(110, 30, 28),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -8),
		Size = UDim2.new(1, -20, 0, 26),
		Parent = p,
	})
	clear.Activated:Connect(function()
		SandboxRemote:FireServer("clear")
		SoundLibrary.Play("click")
	end)
	refs.menu = p
end

function HUD.RefreshMenu()
	local locked = workspace:GetAttribute("SpawningLocked") == true and not Items.IsOwner(player)
	refs.spawnLocked.Visible = locked
	refs.spawnLocked.Text = typeof(workspace:GetAttribute("Mode")) == "string" and "OFF - A GAME IS RUNNING" or "SPAWNING IS OFF"
	for cat, b in refs.tabs do
		local on = cat == currentCategory
		b.BackgroundColor3 = on and C.accent or C.panel2
		b.TextColor3 = on and C.text or C.dim
	end
	local first = nil
	for _, e in refs.cards do
		e.card.Visible = e.item.category == currentCategory and (not e.item.ownerOnly or Items.Has(player, e.item.id)) -- (admin items: owner only)
		if e.item.unlock and e.right then
			local have = player:GetAttribute(e.item.unlock) == true or Items.IsOwner(player)
			e.right.Text = have and "YOURS" or "LOCKED"
			e.right.TextColor3 = have and Color3.fromRGB(230, 90, 110) or C.dim
			e.nameL.TextColor3 = have and C.text or C.dim
		end
		if e.item.skin and e.right then
			local have = skinUnlocked(e.item.skin)
			e.right.Text = have and "SKIN" or "LOCKED"
			e.right.TextColor3 = have and SKIN_GOLD or C.dim
			e.nameL.TextColor3 = have and SKIN_GOLD or C.dim
			e.card.BackgroundTransparency = have and 0.35 or 0.6
		end
		if e.card.Visible and (not first or e.card.LayoutOrder < first.LayoutOrder) then
			first = e.card
		end
	end
	refs.menuList.CanvasPosition = Vector2.zero
	if Input.menuOpen and Input.lastDevice == "Gamepad" and first then
		GuiService.SelectedObject = first
	end
end

------------------------------------------------------------------------
-- overlays
------------------------------------------------------------------------

local function buildOverlays()
	refs.flash = make("Frame", { Name = "DamageFlash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(150, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 0, Parent = gui })
	local vignette = make("Frame", { Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(90, 0, 0), BorderSizePixel = 0, ZIndex = 0, Visible = false, Parent = gui })
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.22, 1),
			NumberSequenceKeypoint.new(0.78, 1),
			NumberSequenceKeypoint.new(1, 0.15),
		}),
		Parent = vignette,
	})
	refs.vignette = vignette

	local death = make("Frame", { Name = "Death", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(12, 0, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 10, Parent = gui })
	make("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.5, 0.75), NumberSequenceKeypoint.new(1, 0.3) }),
		Parent = death,
	})
	refs.deathTitle = label({ Text = "YOU DIED", Font = FONT_TITLE, TextSize = 120, TextColor3 = C.bad, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.new(1, -40, 0, 130), ZIndex = 11, Parent = death })
	refs.deathSub = label({ Text = "", Font = FONT_BOLD, TextSize = 40, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.new(0.9, 0, 0, 100), ZIndex = 11, Parent = death })
	refs.deathTimer = label({ Text = "", Font = FONT_NUM, TextSize = 28, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.66), Size = UDim2.new(0.9, 0, 0, 40), ZIndex = 11, Parent = death })
	refs.death = death
	-- (v2.8.1) realistic death: pure black over everything (its own screen layer above every other one)
	local bgui = make("ScreenGui", { Name = "Blackout", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 200, Parent = gui.Parent })
	refs.blackout = make("Frame", { Name = "Black", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0,
		BorderSizePixel = 0, Visible = false, ZIndex = 1, Parent = bgui })
	refs.blackoutText = label({ Text = "", Font = FONT_NUM, TextSize = 18, TextColor3 = Color3.fromRGB(70, 70, 74), TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.new(0.9, 0, 0, 24), ZIndex = 2, Parent = refs.blackout })
end

------------------------------------------------------------------------
-- v1.6: scope, reload bar, boombox prompt, nuke warning
------------------------------------------------------------------------

local function buildScope()
	local scope = make("Frame", { Name = "Scope", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 2, Parent = gui })
	-- the round view: a transparent circle whose huge black outline covers the rest of the screen
	local lens = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.9),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = scope,
	}, { make("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }), make("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	-- (v1.9: no black mask over the screen: what you see is what the scope sees, the camera itself zooms;
	-- only a thin dark rim and a soft shadow ring show where the glass ends)
	make("UIStroke", { Name = "Rim", Color = Color3.fromRGB(14, 14, 16), Thickness = 3, Transparency = 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = lens })
	make("UIGradient", { Parent = lens })
	-- crosshair lines with thick outer parts, mil dots
	local function bar(pos: UDim2, size: UDim2)
		make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = size, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 3, Parent = lens })
	end
	bar(UDim2.fromScale(0.5, 0.5), UDim2.new(1, 0, 0, 1))
	bar(UDim2.fromScale(0.5, 0.5), UDim2.new(0, 1, 1, 0))
	bar(UDim2.fromScale(0.12, 0.5), UDim2.new(0.24, 0, 0, 4))
	bar(UDim2.fromScale(0.88, 0.5), UDim2.new(0.24, 0, 0, 4))
	bar(UDim2.fromScale(0.5, 0.88), UDim2.new(0, 4, 0.24, 0))
	for i = 1, 4 do
		bar(UDim2.fromScale(0.5 + i * 0.06, 0.5), UDim2.fromOffset(2, 8))
		bar(UDim2.fromScale(0.5 - i * 0.06, 0.5), UDim2.fromOffset(2, 8))
		bar(UDim2.fromScale(0.5, 0.5 + i * 0.06), UDim2.fromOffset(8, 2))
	end
	make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.fromRGB(255, 40, 40), BorderSizePixel = 0, ZIndex = 4, Parent = lens }, { corner(2) })
	-- (v2.0) the zoom (mouse wheel)
	refs.scopeZoom = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.92),
		Size = UDim2.fromOffset(220, 22),
		BackgroundTransparency = 1,
		Font = UI.FONT_NUM,
		TextSize = 18,
		TextColor3 = Color3.fromRGB(240, 240, 240),
		TextStrokeTransparency = 0.4,
		Text = "",
		ZIndex = 4,
		Parent = scope,
	})
	refs.scope = scope
end

local function buildReloadBar()
	local ammo = refs.ammo
	local bg = make("Frame", { Name = "Reload", Position = UDim2.new(0, 14, 1, 6), Size = UDim2.new(1, -28, 0, 5), BackgroundColor3 = Color3.fromRGB(40, 42, 50), BorderSizePixel = 0, Visible = false, Parent = ammo }, { corner(3) })
	refs.reloadFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.amber, BorderSizePixel = 0, Parent = bg }, { corner(3) })
	refs.reloadBar = bg
end

-- boombox: type / paste a Roblox sound id
local boomboxItem: Model? = nil
local function closeBoombox()
	boomboxItem = nil
	refs.boombox.Visible = false
	Input.promptOpen = false
end

local function buildBoombox()
	local p = panel({ Name = "Boombox", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(360, 150), Visible = false, ZIndex = 20, Parent = gui })
	label({ Text = "BOOMBOX", Font = FONT_TITLE, TextSize = 14, Position = UDim2.fromOffset(16, 12), Size = UDim2.fromOffset(200, 18), ZIndex = 21, Parent = p })
	label({ Text = "Paste a Roblox sound or music ID", TextSize = 13, TextColor3 = C.dim, Position = UDim2.fromOffset(16, 32), Size = UDim2.fromOffset(320, 16), ZIndex = 21, Parent = p })
	local box = make("TextBox", {
		Text = "",
		PlaceholderText = "SOUND ID, FOR EXAMPLE 1837849285",
		ClearTextOnFocus = false,
		Font = FONT_NUM,
		TextSize = 16,
		TextColor3 = C.text,
		PlaceholderColor3 = C.dim,
		BackgroundColor3 = C.panel2,
		Position = UDim2.fromOffset(16, 56),
		Size = UDim2.new(1, -32, 0, 34),
		ZIndex = 21,
		Parent = p,
	}, { corner(8), stroke(0.85) })
	local function button(text: string, x: number, w: number, color: Color3, fn: () -> ())
		local b = make("TextButton", { Text = text, Font = FONT_BOLD, TextSize = 13, TextColor3 = C.text, BackgroundColor3 = color, Position = UDim2.fromOffset(x, 102), Size = UDim2.fromOffset(w, 32), ZIndex = 21, AutoButtonColor = true, Parent = p }, { corner(8) })
		b.Activated:Connect(fn)
	end
	local function play()
		local item = boomboxItem
		local id = string.match(box.Text, "(%d+)%s*$")
		if item and id then
			ItemRemote:FireServer("boombox", item, id)
			SoundLibrary.Play("click")
		end
		closeBoombox()
	end
	button("PLAY", 16, 140, Color3.fromRGB(46, 150, 80), play)
	button("STOP", 164, 90, Color3.fromRGB(150, 50, 46), function()
		if boomboxItem then
			ItemRemote:FireServer("boombox", boomboxItem, "stop")
		end
		closeBoombox()
	end)
	button("CLOSE", 262, 82, C.panel2, closeBoombox)
	box.FocusLost:Connect(function(enter)
		if enter then
			play()
		end
	end)
	refs.boombox = p
	refs.boomboxBox = box
end

function HUD.OpenBoombox(item: Model)
	if item:GetAttribute("Broken") then
		return -- (v1.9.1: a broken boombox plays nothing)
	end
	boomboxItem = item
	refs.boombox.Visible = true
	Input.promptOpen = true
	local last = item:GetAttribute("SoundId")
	if typeof(last) == "string" and refs.boomboxBox.Text == "" then
		refs.boomboxBox.Text = last
	end
	task.defer(function()
		refs.boomboxBox:CaptureFocus()
	end)
end

-- flying (game owner): the speed at the top. N (or a click / tap on the number) types a new one:
-- any number, or "inf"
local function buildFly()
	local p = panel({
		Name = "FlySpeed",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 84),
		Size = UDim2.fromOffset(250, 58),
		Visible = false,
		Accent = C.amber,
		ZIndex = 12,
		Parent = gui,
	})
	label({ Text = "FLY SPEED", Font = FONT_TITLE, TextSize = 11, TextColor3 = C.dim, Position = UDim2.fromOffset(14, 7), Size = UDim2.fromOffset(100, 14), ZIndex = 13, Parent = p })
	refs.flyNote = label({
		Text = "",
		RichText = true,
		Font = FONT_BOLD,
		TextSize = 11,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 7),
		Size = UDim2.fromOffset(140, 14),
		ZIndex = 13,
		Parent = p,
	})
	local box = make("TextBox", {
		Name = "Speed",
		Text = "45",
		PlaceholderText = "NUMBER OR INF",
		ClearTextOnFocus = false,
		Font = FONT_NUM,
		TextSize = 24,
		TextColor3 = C.text,
		PlaceholderColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = C.panel2,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 23),
		Size = UDim2.fromOffset(132, 28),
		ZIndex = 13,
		Parent = p,
	}, { corner(3) })
	refs.flyUnit = label({ Text = "STUDS/S", Font = FONT_BOLD, TextSize = 11, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 34), Size = UDim2.fromOffset(100, 14), ZIndex = 13, Parent = p })
	box.Focused:Connect(function()
		Input.promptOpen = true
		box.BackgroundTransparency = 0.2
	end)
	box.FocusLost:Connect(function()
		Input.promptOpen = false
		box.BackgroundTransparency = 1
		local c = controller
		if c and c.ParseFlySpeed and c.SetFlySpeed then
			local v = c.ParseFlySpeed(box.Text)
			if v then
				c:SetFlySpeed(v)
				SoundLibrary.Play("click")
			end
		end
		-- (the next frame shows the speed that is set, also when the text was no number)
	end)
	refs.fly = p
	refs.flyBox = box
end

-- start typing a fly speed (N, or a digit key while flying: that digit is the first one)
function HUD.EditFlySpeed(first: string?)
	local c = controller
	if not c or not c.flying or not refs.flyBox then
		return
	end
	local box = refs.flyBox
	if box:IsFocused() then
		return
	end
	box.Text = first or ""
	task.defer(function()
		box:CaptureFocus()
		box.CursorPosition = #box.Text + 1
		-- (some keyboards also type the key that opened the box: no doubled first digit)
		task.delay(0.06, function()
			if first and box:IsFocused() and box.Text == first .. first then
				box.Text = first
				box.CursorPosition = #first + 1
			end
		end)
	end)
end

-- the nuke countdown: an emergency broadcast across the top of everybody's screen + a siren
local nukeUntil = 0
local function buildNuke()
	local root = make("Frame", { Name = "NukeAlert", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 15, Parent = gui })
	-- the screen border blinks red
	refs.nukeEdges = {}
	for _, e in { { UDim2.fromScale(0, 0), UDim2.new(1, 0, 0, 6) }, { UDim2.new(0, 0, 1, -6), UDim2.new(1, 0, 0, 6) }, { UDim2.fromScale(0, 0), UDim2.new(0, 6, 1, 0) }, { UDim2.new(1, -6, 0, 0), UDim2.new(0, 6, 1, 0) } } do
		table.insert(refs.nukeEdges, make("Frame", { Position = e[1], Size = e[2], BackgroundColor3 = Color3.fromRGB(220, 20, 20), BorderSizePixel = 0, ZIndex = 15, Parent = root }))
	end
	local band = make("Frame", { Name = "Band", Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 112), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.12, BorderSizePixel = 0, ZIndex = 15, Parent = root })
	local strip = make("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = Color3.fromRGB(190, 18, 18), BorderSizePixel = 0, ZIndex = 16, Parent = band })
	label({ Text = "EMERGENCY ALERT", Font = FONT_TITLE, TextSize = 18, Position = UDim2.fromOffset(24, 0), Size = UDim2.fromOffset(300, 26), ZIndex = 17, Parent = strip })
	label({ Text = "CIVIL DEFENSE  /  ALL STATIONS", Font = FONT_NUM, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 0), Size = UDim2.fromOffset(320, 26), ZIndex = 17, Parent = strip })
	label({
		Text = "NUCLEAR DETONATION IMMINENT IN THIS AREA.\nTAKE COVER BEHIND THICK WALLS OR GET AS FAR AWAY AS YOU CAN.\nDO NOT LOOK AT THE FLASH.",
		Font = FONT_NUM,
		TextSize = 14,
		TextYAlignment = Enum.TextYAlignment.Top,
		LineHeight = 1.15,
		Position = UDim2.fromOffset(24, 36),
		Size = UDim2.new(1, -260, 0, 70),
		ZIndex = 17,
		Parent = band,
	})
	refs.nukeCount = label({ Text = "T-00:30", Font = FONT_NUM, TextSize = 40, TextColor3 = Color3.fromRGB(255, 80, 60), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 30), Size = UDim2.fromOffset(230, 46), ZIndex = 17, Parent = band })
	refs.nukeDist = label({ Text = "", Font = FONT_NUM, TextSize = 13, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 80), Size = UDim2.fromOffset(230, 18), ZIndex = 17, Parent = band })
	refs.nuke = root
end

function HUD.NukeWarn(n: number, pos: Vector3?)
	refs.nuke.Visible = true
	nukeUntil = os.clock() + 1.6
	refs.nukeCount.Text = n > 1 and string.format("T-00:%02d", math.min(n, 99)) or "T-00:00"
	local char = player.Character
	local torso = char and char:FindFirstChild("Torso")
	if pos and torso and torso:IsA("BasePart") then
		refs.nukeDist.Text = string.format("YOU ARE %d STUDS FROM IT", math.floor((torso.Position - pos).Magnitude))
	else
		refs.nukeDist.Text = ""
	end
	-- siren: two tones every second
	SoundLibrary.Play("siren", nil, 1, 1)
	task.delay(0.5, function()
		SoundLibrary.Play("siren", nil, 1, 1.35)
	end)
end

-- flash grenade: the screen goes white and slowly comes back
local function buildBlind()
	refs.blind = make("Frame", { Name = "Blind", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 34, Visible = false, Parent = gui })
end

local blindToken = 0
function HUD.Blind(strength: number, duration: number)
	local f = refs.blind
	blindToken += 1
	local token = blindToken
	f.Visible = true
	f.BackgroundTransparency = 1 - math.clamp(strength, 0, 1)
	task.delay(duration * 0.45, function()
		if blindToken ~= token then
			return
		end
		local tw = TweenService:Create(f, TweenInfo.new(duration * 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 })
		tw.Completed:Connect(function()
			if blindToken == token then
				f.Visible = false
			end
		end)
		tw:Play()
	end)
end

-- drowning: no meter, the picture just gets darker and closes in
local function buildDrown()
	local root = make("Frame", { Name = "Drown", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 33, Visible = false, Parent = gui })
	refs.drownEdges = {}
	for _, rot in { 0, 90, 180, 270 } do
		local e = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(0, 6, 14), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 33, Parent = root })
		make("UIGradient", { Rotation = rot, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.45, 1), NumberSequenceKeypoint.new(1, 1) }), Parent = e })
		table.insert(refs.drownEdges, e)
	end
	refs.drownFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(0, 4, 10), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 33, Parent = root })
	refs.drown = root
end

function HUD.SetDrown(k: number)
	k = math.clamp(k, 0, 1)
	refs.drown.Visible = k > 0.01
	for _, e in refs.drownEdges do
		e.BackgroundTransparency = 1 - math.min(1, k * 1.6)
	end
	refs.drownFill.BackgroundTransparency = 1 - math.clamp((k - 0.45) / 0.55, 0, 1) * 0.92
end

-- the construction lift: a floor picker while you stand on a lift pad
local function buildLift()
	local p = panel({ Name = "Lift", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(176, 330), Visible = false, ZIndex = 12, Parent = gui })
	label({ Text = "LIFT", Font = FONT_TITLE, TextSize = 14, Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(140, 16), ZIndex = 13, Parent = p })
	label({ Text = "click a floor or press 0-9 / =", TextSize = 11, TextColor3 = C.dim, Position = UDim2.fromOffset(14, 28), Size = UDim2.fromOffset(150, 14), ZIndex = 13, Parent = p })
	local grid = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 50), Size = UDim2.new(1, -24, 1, -60), ZIndex = 13, Parent = p })
	make("UIGridLayout", { CellSize = UDim2.fromOffset(72, 40), CellPadding = UDim2.fromOffset(8, 7), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	refs.liftButtons = {}
	for f = 10, 0, -1 do
		local text = f == 10 and "ROOF  =" or (f == 0 and "GROUND 0" or string.format("%d", f))
		local b = make("TextButton", { Text = text, Font = FONT_BOLD, TextSize = 13, TextColor3 = C.text, BackgroundColor3 = C.panel2, LayoutOrder = 10 - f, ZIndex = 14, AutoButtonColor = true, Parent = grid }, { corner(8) })
		b.Activated:Connect(function()
			if controller and controller.LiftTo then
				controller:LiftTo(f)
			end
		end)
		refs.liftButtons[f] = b
	end
	refs.lift = p
end

function HUD.ShowLift(floor: number?)
	refs.lift.Visible = floor ~= nil
	Input.freeCursor = floor ~= nil
	if floor then
		for f, b in refs.liftButtons do
			b.BackgroundColor3 = f == floor and Color3.fromRGB(46, 120, 170) or C.panel2
		end
	end
end

-- knocked out by a sleep dart: black screen, silence
local function buildSleep()
	local f = make("Frame", { Name = "Sleep", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, ZIndex = 35, Parent = gui })
	refs.sleepText = label({ Text = "KNOCKED OUT", Font = FONT_TITLE, TextSize = 22, TextColor3 = Color3.fromRGB(70, 70, 80), TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.94), Size = UDim2.fromOffset(300, 30), ZIndex = 40, Parent = f })
	refs.sleep = f
end

function HUD.Sleep(duration: number)
	refs.sleep.Visible = true
	Dream.Start(refs.sleep, duration)
	TweenService:Create(refs.sleep, TweenInfo.new(0.35), { BackgroundTransparency = 0 }):Play()
	TweenService:Create(refs.sleepText, TweenInfo.new(3), { TextTransparency = 0.3 }):Play()
	SoundLibrary.SetMuted(true)
end

-- (v2.8.2) the black sleep screen is up
function HUD.IsSleeping(): boolean
	return refs.sleep ~= nil and refs.sleep.Visible and refs.sleep.BackgroundTransparency < 0.5
end

function HUD.Wake()
	SoundLibrary.SetMuted(false)
	Dream.Stop()
	if not refs.sleep.Visible then
		return
	end
	TweenService:Create(refs.sleepText, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
	local tw = TweenService:Create(refs.sleep, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 })
	tw.Completed:Connect(function()
		if refs.sleep.BackgroundTransparency > 0.95 then
			refs.sleep.Visible = false
		end
	end)
	tw:Play()
end

local function updateExtras(_char: Model)
	refs.scope.Visible = Cam.scope
	if Cam.scope then
		local z = Cam.ScopeZoomFactor()
		refs.scopeZoom.Text = string.format("x%s   (WHEEL: ZOOM)", z % 1 == 0 and string.format("%d", z) or string.format("%.1f", z))
	end
	if refs.nuke.Visible and os.clock() > nukeUntil then
		refs.nuke.Visible = false
	end
	if refs.nuke.Visible then
		local on = (os.clock() % 0.5) < 0.25
		for _, e in refs.nukeEdges do
			e.BackgroundTransparency = on and 0 or 0.7
		end
	end
	if refs.boombox.Visible and (not boomboxItem or not boomboxItem.Parent) then
		closeBoombox()
	end
end

------------------------------------------------------------------------
-- update
------------------------------------------------------------------------

-- (v2.0) the body card shows each body part in the colour of its injury: unhurt = light, then
-- yellow (scratched), orange (hurt), red (badly hurt / broken), black (destroyed, burnt to coal or gone)
local INJURY = {
	ok = Color3.fromRGB(196, 190, 176),
	yellow = Color3.fromRGB(242, 214, 64),
	orange = Color3.fromRGB(240, 132, 36),
	red = Color3.fromRGB(206, 36, 30),
	black = Color3.fromRGB(14, 12, 12),
}
local function injuryLevel(hp: number, broken: boolean, severed: boolean, charred: boolean): string
	local t = math.clamp(hp / Config.LimbMaxHP, 0, 1)
	if severed or charred or t <= 0.08 then
		return "black"
	elseif broken or t <= 0.35 then
		return "red"
	elseif t <= 0.62 then
		return "orange"
	elseif t <= 0.9 then
		return "yellow"
	end
	return "ok"
end
local function hpColor(hp: number, broken: boolean, severed: boolean, charred: boolean?): Color3
	return INJURY[injuryLevel(hp, broken, severed, charred == true)]
end
local lastRegionHp: { [string]: number } = {}
local regionPulse: { [string]: number } = {}

local KEYS = {
	KeyboardMouse = { L = "Q", R = "E" },
	Gamepad = { L = "L1", R = "R1" },
	Touch = { L = "L", R = "R" },
}

local function setHand(frame: Frame, info, side: string, controlled: boolean)
	local ring = frame:FindFirstChild("Ring") :: UIStroke
	local key = frame:FindFirstChild("Key") :: TextLabel
	key.Text = (KEYS[Input.lastDevice] or KEYS.KeyboardMouse)[side]
	if info.severed then
		frame.BackgroundColor3 = C.gone
		ring.Color = C.bad
		ring.Transparency = 0
		key.TextColor3 = C.bad
		return
	end
	if info.broken then
		frame.BackgroundColor3 = Color3.fromRGB(70, 15, 15)
		ring.Color = C.bad
		ring.Transparency = 0
		key.TextColor3 = C.bad
		return
	end
	key.TextColor3 = C.text
	if info.holding then
		frame.BackgroundColor3 = info.gun and Color3.fromRGB(120, 86, 24) or Color3.fromRGB(36, 116, 58)
		ring.Color = info.gun and C.amber or C.good
		ring.Transparency = 0
	elseif info.armed then
		frame.BackgroundColor3 = Color3.fromRGB(70, 70, 82)
		ring.Color = Color3.new(1, 1, 1)
		ring.Transparency = 0
	else
		frame.BackgroundColor3 = C.panel
		ring.Color = Color3.new(1, 1, 1)
		ring.Transparency = 0.6
	end
	if controlled then
		ring.Color = C.amber
		ring.Transparency = 0
	end
end

local STATE_TEXT = {
	DropKick = "DROP KICK",
	Passenger = "PASSENGER",
	Flying = "FLYING",
	Swimming = "SWIMMING",
	Stumbling = "STUMBLING",
	Hanging = "HANGING",
	Tumble = "FALLING",
	Ragdoll = "KNOCKED DOWN",
	GettingUp = "GETTING UP",
	Prone = "LYING DOWN",
	Downed = "CAN'T STAND",
	Dead = "DEAD",
	Driving = "DRIVING",
	Diving = "DIVING",
}

local ITEM_HINTS = {
	spear = key("F") .. " Thrust    " .. key("Q/E") .. " Let go to throw it",
	blade = key("F") .. " Slash. A hard cut takes a limb off and cuts ropes",
	axe = key("F") .. " Chop. Takes limbs off, cuts ropes",
	bat = key("F") .. " Swing. Sends people flying",
	bandage = key("F") .. " Bandage. Stops your bleeding, or the bleeding of the body you hold",
	rope = "Hold a body with the other hand, then " .. key("F") .. " ties it to the nearest wall",
	tether = key("F") .. " on one thing, then " .. key("F") .. " on another: a rope between them",
	physgun = "Hold " .. key("F") .. " to grab anything. Scroll: closer / further",
	katana = key("F") .. " Slash. Cuts limbs off easily",
	sledge = key("F") .. " Swing. Breaks bones, throws people",
	c4 = key("F") .. " Throw it. It sticks to walls, cars and people. Then use the detonator",
	detonator = key("F") .. " Set off all your C4",
	boombox = key("F") .. " Paste a Roblox sound ID and play it",
	nuke = key("F") .. " Arm the nuke. Then run",
	laser = key("F") .. " Laser on / off",
	shield = "Hold it in front of you. Stops bullets, blades and darts",
	virus = key("F") .. " Throw it. The bottle breaks and the virus gets out",
	tv = key("F") .. " Switch it on / off",
	knife = key("F") .. " Stab. Aim and let go to throw it: it sticks",
	machete = key("F") .. " Chop. Takes limbs off",
	crossbow = key("F") .. " Shoot a bolt. It stays where it hits",
	flamethrower = "Hold " .. key("F") .. " Fire",
	molotov = key("F") .. " Throw it. Everything around it burns",
	-- v2.0
	flashlight = key("F") .. " Light on / off",
	glue = key("F") .. " on one thing, then " .. key("F") .. " on another: the lighter one is glued onto the heavier one",
	prosthetic_arm = key("F") .. " Fit it to your missing arm (or point at somebody who misses one)",
	prosthetic_leg = key("F") .. " Fit it to your missing leg (or point at somebody who misses one)",
	steelball = key("F") .. " Throw it - straight and hard. Then go and pick it up again",
	crowbar = key("F") .. " Swing. Hits hard",
	chainsaw = key("F") .. " Motor on / off. The running chain cuts whatever it touches",
	-- v2.8
	sheath = "Hold " .. key("Q/E") .. " Wear it in a pocket. Then put STILLWATER into the same pocket",
}
local GUN_HINTS = {
	lockon = "Hold " .. key("G") .. " Seeker: keep a target in the box until it turns green, then " .. key("F"),
	taser = key("F") .. " Tase (close range): they drop and twitch",
	harpoon = key("F") .. " Fire the harpoon. It drags what it hits on its line",
	flaregun = key("F") .. " Fire a flare (into the sky: it floats down and lights the area)",
	garand = key("F") .. " Fire. Reload only when the clip pinged out",
	usp = key("F") .. " Fire (suppressed)",
}

local function contextHint(c, char): string?
	local hints = {
		Hanging = key("SPACE") .. " Climb    " .. key("Q/E") .. " Let go",
		Downed = "You can't stand. Crawl with your arms, grab the floor and pull",
		Prone = "Crawling    " .. akey("Prone") .. " or " .. key("SPACE") .. " Stand up",
		Driving = key("W/S") .. " Gas / brake    " .. key("A/D") .. " Steer    " .. key("SPACE") .. " Handbrake    " .. akey("Car") .. " Get out",
		Passenger = key("F") .. " Shoot out of the window    " .. akey("Car") .. " Get out",
		Flying = key("WASD") .. " Fly    " .. key("SPACE") .. "/" .. key("CTRL") .. " Up / down    " .. akey("FlySpeed") .. " Speed    " .. key("Q/E") .. " Lift anything    " .. key("K") .. " Laser eyes    " .. akey("SuperPunch") .. " Punch    " .. akey("Car") .. " Land",
	}
	local s = c:GetStateName()
	local dead = char:GetAttribute("Dead") == true
	if c.IsPinned and c:IsPinned() and not dead then
		return "Stuck on a spike. Hold a move key or " .. key("SPACE") .. " to tear free"
	end
	local by = char:GetAttribute("DraggedBy")
	if typeof(by) == "number" and not dead then
		local p = Players:GetPlayerByUserId(by)
		return '<font color="#D6342C"><b>DRAGGED BY ' .. string.upper(p and p.DisplayName or "SOMEONE") .. "</b></font>"
	end
	if char:GetAttribute("Sick") and not dead then
		return "You are sick. A heal dart cures it. Keep away from others"
	elseif char:GetAttribute("Infected") and not dead then
		return "You feel strange"
	end
	if char:GetAttribute("Tied") and not dead then
		return "You are tied up. Somebody has to cut the rope"
	end
	if c.swimming and not dead then
		return c.canSwim and ("Swimming    " .. key("SPACE") .. " Swim up") or '<font color="#D6342C"><b>YOU CAN\'T SWIM LIKE THIS</b></font>'
	end
	if c.passenger then
		return hints.Passenger
	end
	if c.car and c.car:GetAttribute("Jet") then
		return key("W/S") .. " Throttle    " .. key("MOUSE") .. " Steer    " .. key("A/D") .. " Roll    " .. key("F") .. " Cannon    "
			.. akey("Kick") .. " Missile    " .. akey("Prone") .. " Bomb    " .. akey("Car") .. " Eject"
	end
	if c.car and c.car:GetAttribute("Heli") then
		return key("SPACE") .. "/" .. key("CTRL") .. " Up / down    " .. key("W/S") .. " Tilt    " .. key("A/D") .. " Turn    "
			.. key("Q/E") .. " Sideways    " .. key("F") .. " Gun    " .. akey("Kick") .. " Missile (" .. tostring(c.car:GetAttribute("Missiles") or 0) .. " left)    " .. akey("Car") .. " Out"
	end
	if c.flying then
		return hints.Flying
	end
	if hints[s] then
		return hints[s]
	end
	local gun = c:GetGunInfo()
	if gun and gun.reloading then
		return "Reloading. Keep the hand on the gun"
	end
	if gun and gun.ammo <= 0 then
		if gun.dual then
			return "Out of ammo. Two guns: no free hand to reload, drop one"
		end
		local k = Input.lastDevice == "Gamepad" and (gun.free == "Left" and "L2" or "R2") or (gun.free == "Left" and "LMB" or "RMB")
		return "Out of ammo. Hold " .. key(k) .. " and touch the gun with that hand"
	end
	-- (v2.0) the new guns
	if gun and gun.kind == "harpoon" and gun.lineOut then
		return "Hold " .. key("F") .. " Reel in    " .. key("LMB/RMB") .. " Reload cuts the line"
	end
	if gun and gun.kind and GUN_HINTS[gun.kind] and gun.ammo > 0 then
		return GUN_HINTS[gun.kind]
	end
	local fit = c.GetFitProgress and c:GetFitProgress()
	if fit then
		return string.format("<b>FITTING THE PROSTHETIC  %d%%</b>    stay close and keep still", math.floor(fit * 100))
	end
	local both = ""
	if c.twoHand then
		both = "    " .. akey("TwoHand") .. " One hand"
	elseif c._twoHandCandidate and c:_twoHandCandidate() then
		both = "    " .. akey("TwoHand") .. " Both hands"
	end
	local item = c.GetItemInfo and c:GetItemInfo()
	if item then
		if item.kind == "grenade" or item.kind == "flash" then
			return (item.armed and ("<b>THROW IT</b>    " .. key("Q/E") .. " Let go") or (key("F") .. " Pull the pin, then " .. key("Q/E") .. " let go to throw")) .. both
		elseif item.kind == "nuke" and item.armed then
			return "<b>IT IS ARMED.</b> Run as far as you can"
		end
		local h = ITEM_HINTS[item.kind]
		if item.kind == "flamethrower" and item.fuel then
			h = h .. string.format("    FUEL %d%%", math.floor(item.fuel + 0.5))
		elseif item.kind == "glue" and typeof(item.coats) == "number" then
			h = h .. string.format("    (%d coats left)", item.coats)
		elseif item.kind == "steelball" and player:GetAttribute("HasSpin") then
			h = key("F") .. " Throw it with the <b>SPIN</b> - it comes back to you, whoever it hits spins"
		elseif item.stillwater then
			-- (v2.8) STILLWATER: back into its sheath = the STILL CUT
			local pk = item.side == "Left" and "Q" or "E"
			if player:GetAttribute("HasStillCut") == true or player:GetAttribute("Gift_stillcut") == true then
				h = key("F") .. " Slash    Hold " .. key(pk) .. " Sheathe it in the sheath's pocket: <b>STILL CUT</b>"
			else
				h = key("F") .. " Slash    Hold " .. key(pk) .. " Sheathe it"
			end
		end
		local throwHint = "    " .. key("G") .. "+" .. key("Q/E") .. " Throw"
		return h and (h .. both .. throwHint) or (string.sub(both .. throwHint, 5))
	end
	if gun and both ~= "" then
		return string.sub(both, 5)
	end
	if not dead and VehicleClient.NearCar() then
		return akey("Car") .. " Get in (passenger seat if somebody drives)"
	end
	return nil
end

local deathShownFor = nil
local deathAt = 0
local blackoutFor: Model? = nil -- (v2.8.1) the body that died with realistic death on
local fadingIn = false
local function update()
	local c = controller
	local char = player.Character
	if not c or not c.ready or not char then
		return
	end
	refreshHelp()
	updateHandCursor()
	updateExtras(char)

	refs.crosshair.Visible = not Input.CursorFree() and not Cam.scope
	local left = c:GetHandInfo("Left")
	local right = c:GetHandInfo("Right")
	setHand(refs.handL, left, "L", Input.mouseLeft)
	setHand(refs.handR, right, "R", Input.mouseRight)

	-- condition
	local chips = {}
	local nowT = os.clock()
	for _, region in RigInfo.Regions do
		local hp = char:GetAttribute("HP_" .. region) or 100
		local broken = char:GetAttribute("Broken_" .. region) == true
		local severed = char:GetAttribute("Severed_" .. region) == true
		local charred = char:GetAttribute("Charred_" .. region) == true
		local f = refs.regions[region]
		-- (v2.0) the part that was just hit flashes white for a moment
		local key = tostring(char) .. region
		local prev = lastRegionHp[key]
		if prev and hp < prev - 0.5 then
			regionPulse[region] = nowT
		end
		lastRegionHp[key] = hp
		if f then
			local col = hpColor(hp, broken, severed, charred)
			local pt = regionPulse[region]
			if pt and nowT - pt < 0.45 then
				col = col:Lerp(Color3.new(1, 1, 1), 1 - (nowT - pt) / 0.45)
			end
			f.BackgroundColor3 = col
			f.BackgroundTransparency = severed and 0.35 or 0
			local s = f:FindFirstChild("S") :: UIStroke
			s.Color = severed and C.bad or Color3.new(0, 0, 0)
			s.Transparency = severed and 0 or 0.5
			local crack = f:FindFirstChild("Crack") :: Frame
			crack.Visible = broken and not severed
			crack.BackgroundColor3 = Color3.fromRGB(250, 240, 230)
		end
		if severed then
			table.insert(chips, { text = RigInfo.DisplayName[region]:upper() .. " MISSING", color = C.bad })
		elseif broken then
			table.insert(chips, { text = RigInfo.DisplayName[region]:upper() .. " BROKEN", color = C.amber })
		end
	end
	if char:GetAttribute("Bleeding") then
		table.insert(chips, 1, { text = "BLEEDING", color = C.accent })
	end
	if char:GetAttribute("God") then
		table.insert(chips, 1, { text = "INVINCIBLE", color = C.amber })
	end
	if (c.IsPinned and c:IsPinned()) or char:GetAttribute("Impaled") then
		table.insert(chips, 1, { text = "IMPALED", color = C.accent })
	end
	while #chips > 5 do
		table.remove(chips)
	end
	setChips(chips)
	local blood = char:GetAttribute("Blood") or 100
	refs.bloodFill.Size = UDim2.fromScale(math.clamp(blood / 100, 0, 1), 1)
	refs.bloodText.Text = string.format("BLOOD %d%%", math.floor(blood + 0.5))
	local stance = c:GetStance()
	refs.stance.Text = (c.car and "DRIVING" or stance == "Crouch" and "CROUCHING" or stance == "Prone" and "LYING DOWN" or stance == "Downed" and "CRAWLING" or "STANDING")
		.. (Input.firstPerson and "  /  FIRST PERSON" or "")
	local st = STATE_TEXT[c:GetStateName()]
	refs.statePill.Visible = st ~= nil
	refs.statePillText.Text = st or ""
	local critical = blood < 45 or (char:GetAttribute("HP_Torso") or 100) < 30 or (char:GetAttribute("HP_Head") or 100) < 30
	refs.vignette.Visible = critical
	if critical then
		refs.vignette.BackgroundTransparency = 0.35 + 0.25 * math.sin(os.clock() * 4)
	end

	-- held objects
	local parts = {}
	for _, pair in { { "L", left }, { "R", right } } do
		local info = pair[2]
		if info.holding and info.name then
			local w = info.static and "solid" or string.format("%d kg", math.floor(info.mass * Config.MassToKg + 0.5))
			table.insert(parts, string.format('<b>%s</b>  %s  <font color="#9aa0ad">%s</font>', pair[1], info.name, w))
		end
	end
	refs.hold.Text = table.concat(parts, "      ")

	-- ammo
	local gun = c:GetGunInfo()
	refs.ammo.Visible = gun ~= nil
	if gun then
		refs.ammoTitle.Text = gun.name or "GUN"
		refs.ammoNum.Text = tostring(gun.ammo)
		refs.ammoNum.TextColor3 = gun.ammo > 0 and C.text or C.bad
		refs.ammoMax.Text = "/ " .. tostring(gun.max)
		local fire = Input.lastDevice == "Gamepad" and "X  FIRE" or Input.lastDevice == "Touch" and "FIRE" or "F  FIRE"
		local freeKey = Input.lastDevice == "Gamepad" and (gun.free == "Left" and "L2" or "R2")
			or Input.lastDevice == "Touch" and ("AIM " .. (gun.free == "Left" and "L" or "R"))
			or (gun.free == "Left" and "LMB" or "RMB")
		local reload = gun.dual and "2 GUNS, NO RELOAD" or ("RELOAD: " .. freeKey .. " ON GUN")
		refs.ammoNote.Text = gun.reloading and "RELOADING" or (gun.ammo > 0 and fire or reload)
		refs.reloadBar.Visible = gun.reloading or gun.assist
		refs.reloadFill.Size = UDim2.fromScale(gun.progress, 1)
		local w = gun.max <= 12 and 10 or math.max(3, math.floor((162 - (gun.max - 1) * 2) / gun.max))
		for i, pip in refs.pips do
			pip.BackgroundTransparency = (i <= gun.ammo and not gun.reloading) and 0 or 0.8
			pip.Visible = i <= gun.max
			pip.Size = UDim2.fromOffset(w, 8)
		end
	end

	-- flying: the speed (the box shows what is set unless you are typing in it)
	local flying = c.flying == true
	refs.fly.Visible = flying
	if flying and not refs.flyBox:IsFocused() then
		local v = c:GetFlySpeed()
		refs.flyBox.Text = c.FlySpeedText(v)
		refs.flyNote.Text = "SHIFT  " .. c.FlySpeedText(v * Config.FlySprintMult) .. "    " .. akey("FlySpeed") .. " SET"
		refs.flyUnit.Text = v >= Config.FlyMaxSpeed and "AS FAST AS IT GOES" or "STUDS/S"
	elseif not flying and refs.flyBox:IsFocused() then
		refs.flyBox:ReleaseFocus()
	end

	-- context hint
	local hint = contextHint(c, char)
	refs.hint.Visible = hint ~= nil
	refs.hintText.Text = hint or ""

	-- death
	local dead = char:GetAttribute("Dead") == true
	-- (v2.8.1) realistic death: black at once; when you are back, the black fades away
	local realistic = Settings.Get("realisticDeath") == true
	if dead and deathShownFor ~= char then
		deathShownFor = char
		deathAt = os.clock()
		refs.death.Visible = true
		refs.death.BackgroundTransparency = 1
		refs.deathSub.Text = tostring(char:GetAttribute("DeathCause") or "")
		if realistic then
			refs.blackout.BackgroundTransparency = 0
			refs.blackout.Visible = true
			blackoutFor = char
		else
			TweenService:Create(refs.death, TweenInfo.new(1.5), { BackgroundTransparency = 0.35 }):Play()
		end
	elseif not dead and refs.death.Visible then
		refs.death.Visible = false
	end
	if not dead and refs.blackout.Visible and blackoutFor ~= char and not fadingIn then
		-- a new body: from black back to the world
		fadingIn = true
		local tw = TweenService:Create(refs.blackout, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 })
		tw.Completed:Connect(function()
			refs.blackout.Visible = false
			fadingIn = false
		end)
		tw:Play()
	end
	if dead then
		-- (v2.8.1) REGROWTH tier 3: the body grows back where it lies
		local ru = char:GetAttribute("RegrowUntil")
		if typeof(ru) == "number" then
			local left = math.max(0, ru - workspace:GetServerTimeNow())
			refs.deathSub.Text = "REGROWTH CORE: YOUR BODY IS GROWING BACK"
			refs.deathTimer.Text = string.format("BACK ON YOUR FEET IN %d", math.ceil(left))
			refs.blackoutText.Text = refs.deathTimer.Text
		else
			local remaining = math.max(0, Config.RespawnTime - (os.clock() - deathAt))
			refs.deathTimer.Text = string.format("RESPAWN IN %d", math.ceil(remaining))
			refs.blackoutText.Text = ""
		end
	end
end

------------------------------------------------------------------------
-- api
------------------------------------------------------------------------

function HUD.SetController(c)
	controller = c
end

function HUD.Flash(amount: number)
	if not Settings.Get("hurtflash") then
		return
	end
	local t = math.clamp(1 - amount / 120, 0.45, 0.9)
	refs.flash.BackgroundTransparency = t
	TweenService:Create(refs.flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

-- set by the client entry: closes the settings menu (only one menu at a time)
HUD.CloseOther = nil :: (() -> ())?

function HUD.ToggleMenu()
	if HUD.CloseOther then
		HUD.CloseOther()
	end
	Input.menuOpen = not Input.menuOpen
	refs.menu.Visible = Input.menuOpen
	if Input.menuOpen then
		HUD.RefreshMenu()
	elseif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(refs.menu) then
		GuiService.SelectedObject = nil
	end
end

function HUD.ToggleHelp()
	refs.help.Visible = not refs.help.Visible
	refs.helpHint.Visible = not refs.help.Visible and refs.helpHint.Text ~= ""
end

function HUD.GetGui(): ScreenGui
	return gui
end

function HUD.Init()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
	gui = make("ScreenGui", {
		Name = "RagdollHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	buildOverlays()
	buildCrosshair()
	buildBodyCard()
	buildBottom()
	buildHelp()
	buildMenu()
	buildHandCursor()
	buildScope()
	buildReloadBar()
	buildBoombox()
	buildNuke()
	buildFly()
	buildBlind()
	buildDrown()
	buildSleep()
	buildLift()
	refreshHelp()
	hiddenGui = make("ScreenGui", { Name = "RagdollHUDHidden", Enabled = false, ResetOnSpawn = false, Parent = player:WaitForChild("PlayerGui") })
	applyHide()
	Settings.Changed:Connect(function(key)
		if string.sub(key, 1, 4) == "hide" then
			applyHide()
		elseif key == "uiScale" or key == "keyBinds" then
			refs.helpDevice = nil -- (the help panel: scaled / written again on the next refresh)
			task.defer(refreshHelp)
		end
	end)

	Input.Action:Connect(function(action)
		if action == "Menu" then
			HUD.ToggleMenu()
		elseif action == "Help" then
			HUD.ToggleHelp()
		elseif action == "FlySpeed" then
			HUD.EditFlySpeed(nil)
		elseif controller and controller.flying and string.match(action, "^Lift%d$") then
			-- flying: a digit starts typing a speed right away
			HUD.EditFlySpeed(string.sub(action, 5))
		end
	end)

	task.delay(25, function()
		if refs.help.Visible then
			HUD.ToggleHelp()
		end
	end)
	-- (v2.0) a skin unlocked: the spawn menu shows it at once
	player.AttributeChanged:Connect(function(name)
		if (string.sub(name, 1, 5) == "Skin_" or name == "HexUnlocked") and refs.menu and refs.menu.Visible then
			HUD.RefreshMenu()
		end
	end)

	RunService.RenderStepped:Connect(update)
end

return HUD
