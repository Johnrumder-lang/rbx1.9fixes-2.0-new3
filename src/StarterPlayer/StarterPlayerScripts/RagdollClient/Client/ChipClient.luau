--!nonstrict
-- ChipClient (v2.9): everything you see and press of the cyberdeck.
--   * K: the CYBERDECK - your 4 neck slots, your chips, and the NETRUNNER INTERFACE (nearby targets + their firewall,
--     your quickhacks, the Blackwall for admins). Sharp panels, the game font.
--   * SCANNER / ZOOM: toggles (combat chips). SCANNER boxes and names everything on screen; ZOOM pulls the view in.
--   * REFLEX BUFFER: a flash when it dodges a bullet for you.
--   * being hit: BLIND (reboot), HALLUCINATE / RAMPAGE (a virus / cyberpsychosis), EMP, WEAPON GLITCH.
--   * the computer screen (a terminal's prompt): buy chips, program a blank chip into a virus, bake a trojan into a video.
--   * a VIDEO plays full-screen in a little scene (the bodies and the place as the camera filmed them).
--   * the BLACKWALL: a red beam comes down and whoever it lands on is ash.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Chips = require(Shared:WaitForChild("Chips"))
local Items = require(Shared:WaitForChild("Items"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))
local ReplayCodec = require(Shared:WaitForChild("ReplayCodec"))
local Modules = script.Parent
local UI = require(Modules:WaitForChild("UI"))
local Input = require(Modules:WaitForChild("Input"))
local Cam = require(Modules:WaitForChild("CameraController"))
local Hallucinations = require(Modules:WaitForChild("Hallucinations"))

local ChipClient = {}

local player = Players.LocalPlayer
local C = UI.C
local RED = Color3.fromRGB(255, 52, 64)
local CYAN = Color3.fromRGB(70, 220, 255)
local GREEN = Color3.fromRGB(90, 255, 150)
local PANEL = Color3.fromRGB(10, 11, 14)
local PANEL2 = Color3.fromRGB(26, 27, 33)

local Remote: RemoteEvent
local controller: any = nil
local gui: ScreenGui
local rng = Random.new()

local deck = { slots = { false, false, false, false }, bag = {} }
local zoomOn, scanOn = false, false
local selTarget: number? = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

local function myChar(): Model?
	return player.Character
end

local function torsoOf(m: Instance?): BasePart?
	local t = m and m:FindFirstChild("Torso")
	return (t and t:IsA("BasePart")) and t or nil
end

------------------------------------------------------------------------
-- toast
------------------------------------------------------------------------

local toastLabel: TextLabel
local function toast(text: string, color: Color3?)
	if not toastLabel then
		return
	end
	toastLabel.Text = text
	toastLabel.TextColor3 = color or CYAN
	toastLabel.TextTransparency = 0
	toastLabel.TextStrokeTransparency = 0.4
	TweenService:Create(toastLabel, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
end

------------------------------------------------------------------------
-- bodies on screen (scan + netrunner)
------------------------------------------------------------------------

local function allBodies(): { Model }
	local out = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(out, p.Character)
		end
	end
	for _, name in { "NPCs", "Dummies" } do
		local f = workspace:FindFirstChild(name)
		for _, m in (f and f:GetChildren() or {}) do
			if m:IsA("Model") and m:FindFirstChild("Torso") then
				table.insert(out, m)
			end
		end
	end
	return out
end

local function slotChips(kind: string): { { slot: number, chip: any } }
	local out = {}
	for i, chip in deck.slots do
		if chip and chip.kind == kind then
			table.insert(out, { slot = i, chip = chip })
		end
	end
	return out
end

local function hasSlotted(id: string): any
	for _, chip in deck.slots do
		if chip and chip.id == id then
			return chip
		end
	end
	return nil
end

------------------------------------------------------------------------
-- the CYBERDECK (K)
------------------------------------------------------------------------

local panel: Frame
local slotRows: { Frame } = {}
local bagList: ScrollingFrame
local netList: ScrollingFrame
local hackRow: Frame
local deckRefresh: (() -> ())?
local deckOpen = false

local function firstFreeSlot(): number?
	for i = 1, Config.ChipSlots do
		if not deck.slots[i] then
			return i
		end
	end
	return nil
end

-- F4 enters an in-world targeting mode. K only manages installed chips.
local CAS = game:GetService("ContextActionService")
local hackMode, hackIndex = false, 1
local hackTarget: Player? = nil
local hackHud, hackTitle, hackStatus, hackList, hackMark
local function installedHacks()
	local list = {}
	for slot = 1, Config.ChipSlots do
		local chip = deck.slots[slot]
		if chip and (chip.kind == "net" or (chip.id == "blackwall" and Items.IsOwner(player))) then
			table.insert(list, { slot = slot, chip = chip })
		end
	end
	return list
end
local function clearHackTarget()
	hackTarget = nil
	if hackMark then hackMark:Destroy(); hackMark = nil end
end
local function setHackMode(on: boolean)
	hackMode = on
	Input.quickhackMode = on
	Input.useHeld = false
	if hackHud then hackHud.Visible = on end
	if not on then clearHackTarget() end
	if on then
		ChipClient.CloseDeck()
		ChipClient.CloseComputer()
		SoundLibrary.Play("scope", nil, 0.7)
	end
end
local function targetVisible(p: Player): boolean
	local ch = p.Character
	local mine = torsoOf(myChar())
	local head = ch and (ch:FindFirstChild("Head") or torsoOf(ch))
	local cam = workspace.CurrentCamera
	if p == player or not mine or not head or not cam or ch:GetAttribute("Dead") then return false end
	if (head.Position - mine.Position).Magnitude > Config.NetRange then return false end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { myChar(), workspace:FindFirstChild("FX") or myChar() }
	local hit = workspace:Raycast(cam.CFrame.Position, head.Position - cam.CFrame.Position, rp)
	return not hit or hit.Instance:IsDescendantOf(ch)
end
local function executeHack()
	if not hackMode or Input.IsControlled() or UserInputService:GetFocusedTextBox() then return end
	if not hackTarget or not targetVisible(hackTarget) then
		toast("NO CLEAR TARGET — AIM AT A PLAYER")
		SoundLibrary.Play("dryfire", nil, 0.5)
		return
	end
	local choices = installedHacks()
	hackIndex = math.clamp(hackIndex, 1, math.max(1, #choices))
	local chosen = choices[hackIndex]
	if not chosen then toast("INSTALL A QUICKHACK CHIP IN K FIRST"); return end
	local untilT = player:GetAttribute("ChipCD_" .. chosen.slot) or 0
	if untilT > now() then SoundLibrary.Play("dryfire", nil, 0.4); return end
	Remote:FireServer(chosen.chip.id == "blackwall" and "blackwall" or "hack", chosen.slot, hackTarget.UserId)
	SoundLibrary.Play("beep", nil, 0.45, 0.8)
end
local function startHackControls()
	hackHud = UI.panel({ Name = "QuickhackMode", Position = UDim2.fromScale(0.68, 0.36), Size = UDim2.fromOffset(310, 230), Visible = false, Parent = gui })
	hackTitle = UI.label({ Text = "QUICKHACK MODE", Position = UDim2.fromOffset(14, 12), Size = UDim2.fromOffset(282, 24), TextSize = 18, Parent = hackHud })
	hackStatus = UI.label({ Text = "AIM AT A PLAYER", Position = UDim2.fromOffset(14, 40), Size = UDim2.fromOffset(282, 38), TextWrapped = true, TextSize = 13, TextColor3 = C.dim, Parent = hackHud })
	hackList = UI.label({ Text = "", Position = UDim2.fromOffset(14, 82), Size = UDim2.fromOffset(282, 110), TextSize = 14, TextYAlignment = Enum.TextYAlignment.Top, Parent = hackHud })
	UI.label({ Text = "WHEEL  Select    F  Execute    F4  Exit", Position = UDim2.fromOffset(14, 200), Size = UDim2.fromOffset(285, 22), TextSize = 12, TextColor3 = C.dim, Parent = hackHud })
	local function fit()
		local vs = workspace.CurrentCamera.ViewportSize
		hackHud.Position = UDim2.fromOffset(math.max(8, vs.X - 330), math.max(72, vs.Y * 0.34))
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	CAS:BindActionAtPriority("QuickhackMode", function(_, state)
		if state == Enum.UserInputState.Begin and not UserInputService:GetFocusedTextBox() then
			if not Input.IsControlled() and not Input.menuOpen and not Input.cutscene and not Input.keysCaptured and not Input.freeCam then
				setHackMode(not hackMode)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, 4000, Enum.KeyCode.F4)
	CAS:BindActionAtPriority("HeldChipCamera", function(_, state)
		if hackMode or Input.IsControlled() or Input.menuOpen or UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
		if controller and controller.hands then
			for _, side in { "Left", "Right" } do
				local hand = controller.hands[side]
				local grip = hand and hand.grip
				local item = grip and grip.item
				local kind = item and item.Parent and Items.Kind(item)
				if kind == "chip" or kind == "camera" then
					if state == Enum.UserInputState.Begin then Remote:FireServer(kind == "chip" and "helduse" or "cam", item) end
					return Enum.ContextActionResult.Sink
				end
			end
		end
		return Enum.ContextActionResult.Pass
	end, false, 4500, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
	CAS:BindActionAtPriority("QuickhackExecute", function(_, state)
		if not hackMode then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then executeHack() end
		return Enum.ContextActionResult.Sink
	end, false, 4000, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
	CAS:BindActionAtPriority("QuickhackWheel", function(_, state, io)
		if not hackMode then return Enum.ContextActionResult.Pass end
		if io.Position.Z ~= 0 and state == Enum.UserInputState.Change then
			local count = #installedHacks()
			if count > 0 then hackIndex = ((hackIndex - 1 + (io.Position.Z > 0 and -1 or 1)) % count) + 1 end
			SoundLibrary.Play("rollTick", nil, 0.4)
		end
		return Enum.ContextActionResult.Sink
	end, false, 4000, Enum.UserInputType.MouseWheel)
	player.CharacterAdded:Connect(function() setHackMode(false) end)
	local elapsed = 0
	RunService.RenderStepped:Connect(function(dt)
		if not hackMode then return end
		local char = myChar()
		if Input.IsControlled() or not char or char:GetAttribute("Dead") or (char:GetAttribute("TemporalFrozenUntil") or 0) > now() or Input.menuOpen or Input.cutscene or Input.freeCursor or Input.spectating or Input.freeCam then setHackMode(false); return end
		elapsed += dt
		if elapsed < 0.07 then return end
		elapsed = 0
		local cam = workspace.CurrentCamera
		local center = cam.ViewportSize * 0.5
		local aimed, best = nil, math.min(90, cam.ViewportSize.Y * 0.13)
		for _, p in Players:GetPlayers() do
			local root = torsoOf(p.Character)
			if root and targetVisible(p) then
				local pt, visible = cam:WorldToViewportPoint(root.Position)
				local dist = (Vector2.new(pt.X, pt.Y) - center).Magnitude
				if visible and dist < best then aimed, best = p, dist end
			end
		end
		if hackTarget and not targetVisible(hackTarget) then clearHackTarget() end
		if aimed and aimed ~= hackTarget then
			clearHackTarget()
			hackTarget = aimed
			hackMark = Instance.new("Highlight")
			hackMark.Name = "QuickhackLocked"
			hackMark.Adornee = aimed.Character
			hackMark.FillColor, hackMark.OutlineColor = Color3.new(1, 1, 1), Color3.new(1, 1, 1)
			hackMark.FillTransparency, hackMark.OutlineTransparency = 0.88, 0.1
			hackMark.DepthMode = Enum.HighlightDepthMode.Occluded
			hackMark.Parent = gui
			SoundLibrary.Play("click", nil, 0.5)
		end
		hackStatus.Text = hackTarget and ("QUICKHACK LOCKED\n" .. string.upper(hackTarget.DisplayName) .. "  /  FIREWALL " .. (hackTarget:GetAttribute("ChipFirewall") or 0)) or "AIM AT A PLAYER TO LOCK"
		local choices, lines = installedHacks(), {}
		hackIndex = math.clamp(hackIndex, 1, math.max(1, #choices))
		for i, choice in choices do
			local def = Chips.ById[choice.chip.id]
			local left = math.max(0, (player:GetAttribute("ChipCD_" .. choice.slot) or 0) - now())
			table.insert(lines, (i == hackIndex and "> " or "   ") .. def.name .. " T" .. choice.chip.tier .. (left > 0 and ("  " .. math.ceil(left) .. "s") or ""))
		end
		hackList.Text = #lines > 0 and table.concat(lines, "\n") or "NO QUICKHACKS INSTALLED\nOpen K to install a chip."
	end)
end

local function buildDeck()
	panel = UI.make("Frame", {
		Name = "Cyberdeck", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(820, 500),
		BackgroundColor3 = PANEL, BackgroundTransparency = 0.04, BorderSizePixel = 0, Visible = false, ClipsDescendants = true, Parent = gui,
	})
	UI.make("UIStroke", { Color = CYAN, Thickness = 2, Transparency = 0.3, Parent = panel })
	local scale = UI.make("UIScale", { Name = "Scale", Parent = panel })
	scale:SetAttribute("Managed", true)
	local function fit()
		local cam = workspace.CurrentCamera
		local vs = cam and cam.ViewportSize or Vector2.new(1280, 720)
		scale.Scale = math.max(0.45, math.min(1, (vs.X - 20) / 820, (vs.Y - 20) / 500)) * UI.Global()
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	UI.label({ Text = "CYBERDECK", TextSize = 22, TextColor3 = CYAN, Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(300, 26), Parent = panel })
	local cashL = UI.label({ Name = "Cash", Text = "", TextSize = 15, TextColor3 = C.amber, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -90, 0, 14), Size = UDim2.fromOffset(200, 20), TextXAlignment = Enum.TextXAlignment.Right, Parent = panel })
	UI.button({ Text = "CLOSE", TextSize = 12, Size = UDim2.fromOffset(64, 24), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), BackgroundColor3 = Color3.fromRGB(120, 16, 24), Parent = panel }, function()
		ChipClient.CloseDeck()
	end)

	-- NECK SLOTS
	UI.label({ Text = "NECK SLOTS", TextSize = 13, TextColor3 = C.amber, Position = UDim2.fromOffset(16, 44), Size = UDim2.fromOffset(240, 16), Parent = panel })
	for i = 1, Config.ChipSlots do
		local row = UI.make("Frame", { Name = "Slot" .. i, BackgroundColor3 = PANEL2, BorderSizePixel = 0, Position = UDim2.fromOffset(16, 64 + (i - 1) * 42), Size = UDim2.fromOffset(250, 38), Parent = panel })
		UI.make("UIStroke", { Color = Color3.fromRGB(60, 64, 72), Thickness = 1, Parent = row })
		UI.label({ Name = "Name", Text = "", TextSize = 13, Position = UDim2.fromOffset(8, 3), Size = UDim2.new(1, -70, 0, 16), Parent = row })
		UI.label({ Name = "Sub", Text = "", TextSize = 10, TextColor3 = C.dim, Position = UDim2.fromOffset(8, 20), Size = UDim2.new(1, -70, 0, 14), Parent = row })
		UI.button({ Name = "Act", Text = "", TextSize = 11, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(56, 28), Parent = row }, function()
			local chip = deck.slots[i]
			if chip then
				if chip.id == "zoom" then
					zoomOn = not zoomOn
				elseif chip.id == "scan" then
					scanOn = not scanOn
				else
					Remote:FireServer("eject", i)
				end
			end
			if deckRefresh then
				deckRefresh()
			end
		end)
		slotRows[i] = row
	end

	-- CHIPS (the bag)
	UI.label({ Text = "CHIPS", TextSize = 13, TextColor3 = C.amber, Position = UDim2.fromOffset(282, 44), Size = UDim2.fromOffset(240, 16), Parent = panel })
	bagList = UI.make("ScrollingFrame", { BackgroundColor3 = Color3.fromRGB(8, 9, 12), BorderSizePixel = 0, Position = UDim2.fromOffset(282, 64), Size = UDim2.fromOffset(250, 420), ScrollBarThickness = 4, CanvasSize = UDim2.fromOffset(0, 0), Parent = panel })
	UI.make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = bagList })
	UI.make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = bagList })

	-- NETRUNNER INTERFACE
	UI.label({ Text = "NETRUNNER", TextSize = 13, TextColor3 = RED, Position = UDim2.fromOffset(548, 44), Size = UDim2.fromOffset(240, 16), Parent = panel })
	UI.label({ Text = "IN-WORLD TARGET LOCK", TextSize = 10, TextColor3 = C.dim, Position = UDim2.fromOffset(548, 62), Size = UDim2.fromOffset(256, 14), Parent = panel })
	netList = UI.make("ScrollingFrame", { BackgroundColor3 = Color3.fromRGB(8, 9, 12), BorderSizePixel = 0, Position = UDim2.fromOffset(548, 78), Size = UDim2.fromOffset(256, 210), ScrollBarThickness = 4, CanvasSize = UDim2.fromOffset(0, 0), Parent = panel })
	UI.make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = netList })
	UI.make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = netList })
	UI.label({ Text = "QUICKHACKS", TextSize = 11, TextColor3 = RED, Position = UDim2.fromOffset(548, 294), Size = UDim2.fromOffset(240, 14), Parent = panel })
	hackRow = UI.make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(548, 312), Size = UDim2.fromOffset(256, 172), ScrollBarThickness = 4, CanvasSize = UDim2.fromOffset(0, 0), Parent = panel })
	UI.make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = hackRow })

	local function cashNow(): number
		local c = player:GetAttribute("Cash")
		return typeof(c) == "number" and c or 0
	end

	local function refresh()
		cashL.Text = Items.IsOwner(player) and "ADMIN" or ("$" .. cashNow())
		-- slots
		for i = 1, Config.ChipSlots do
			local row = slotRows[i]
			local chip = deck.slots[i]
			local nameL = row:FindFirstChild("Name") :: TextLabel
			local subL = row:FindFirstChild("Sub") :: TextLabel
			local act = row:FindFirstChild("Act") :: TextButton
			if chip then
				local def = Chips.ById[chip.id]
				nameL.Text = (chip.name or chip.id) .. "  T" .. chip.tier
				nameL.TextColor3 = def and Chips.Color(def) or C.text
				subL.Text = def and (def.ability or "PASSIVE") or ""
				if chip.id == "zoom" then
					act.Text = zoomOn and "ON" or "OFF"
					act.BackgroundColor3 = zoomOn and C.good or PANEL2
				elseif chip.id == "scan" then
					act.Text = scanOn and "ON" or "OFF"
					act.BackgroundColor3 = scanOn and C.good or PANEL2
				elseif chip.id == "dodge" then
					local left = player:GetAttribute("ChipDodge")
					subL.Text = "DODGE  " .. (typeof(left) == "number" and (left .. " READY") or "RECHARGING")
					act.Text = "EJECT"
					act.BackgroundColor3 = PANEL2
				else
					act.Text = "EJECT"
					act.BackgroundColor3 = PANEL2
				end
			else
				nameL.Text = "- EMPTY -"
				nameL.TextColor3 = C.dim
				subL.Text = ""
				act.Text = ""
				act.BackgroundColor3 = PANEL
			end
		end
		-- the bag
		for _, c in bagList:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local h = 0
		for _, chip in deck.bag do
			local def = Chips.ById[chip.id]
			local row = UI.make("Frame", { BackgroundColor3 = PANEL2, BorderSizePixel = 0, Size = UDim2.new(1, -8, 0, 48), Parent = bagList })
			UI.make("UIStroke", { Color = Color3.fromRGB(50, 54, 62), Thickness = 1, Parent = row })
			UI.label({ Text = (chip.name or chip.id) .. (chip.tier > 1 and ("  T" .. chip.tier) or ""), TextSize = 12, TextColor3 = chip.video and CYAN or (def and Chips.Color(def) or C.text), Position = UDim2.fromOffset(6, 3), Size = UDim2.new(1, -12, 0, 15), Parent = row })
			local kindText = chip.video and (chip.trojan and "VIDEO (TROJAN)" or "VIDEO") or (chip.kind == "virus" and "VIRUS" or (def and def.kind:upper() or "CHIP"))
			UI.label({ Text = kindText, TextSize = 9, TextColor3 = C.dim, Position = UDim2.fromOffset(6, 18), Size = UDim2.new(1, -12, 0, 12), Parent = row })
			local uid = chip.uid
			UI.button({ Text = "TAKE", TextSize = 10, Position = UDim2.fromOffset(6, 30), Size = UDim2.fromOffset(60, 14), Parent = row }, function()
				Remote:FireServer("take", uid)
			end)
			if chip.video then
				UI.button({ Text = "PLAY", TextSize = 10, Position = UDim2.fromOffset(72, 30), Size = UDim2.fromOffset(60, 14), Parent = row }, function() Remote:FireServer("playbag", uid) end)
			end
			local slottable = not chip.video and chip.kind ~= "video"
			if slottable then
				UI.button({ Text = "SLOT", TextSize = 10, Position = UDim2.fromOffset(72, 30), Size = UDim2.fromOffset(60, 14), BackgroundColor3 = Color3.fromRGB(30, 60, 70), Parent = row }, function()
					local s = firstFreeSlot()
					if s then
						Remote:FireServer("install", uid, s)
					else
						toast("NO FREE SLOT", RED)
					end
				end)
			end
			h += 52
		end
		bagList.CanvasSize = UDim2.fromOffset(0, h + 6)
		netList:ClearAllChildren()
		UI.label({ Text = "F4  ENTER QUICKHACK MODE\n\nAim at a player to lock.\nScroll to select an installed hack.\nF executes the selected hack.\nF4 exits targeting mode.", TextSize = 15, TextWrapped = true, Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 1, -20), TextYAlignment = Enum.TextYAlignment.Top, Parent = netList })
		hackRow:ClearAllChildren()
		UI.label({ Text = "Install netrunner chips into your neck slots.\nThe target must stay in sight and in range.\nAdmins can be hacked too.", TextSize = 14, TextWrapped = true, Size = UDim2.new(1, -12, 1, -12), TextYAlignment = Enum.TextYAlignment.Top, Parent = hackRow })
	end
	deckRefresh = refresh
	player:GetAttributeChangedSignal("Cash"):Connect(function()
		if deckOpen then
			refresh()
		end
	end)
end

function ChipClient.OpenDeck()
	if not panel then
		buildDeck()
	end
	setHackMode(false)
	SoundLibrary.Play("tvOn", nil, 0.4)
	deckOpen = true
	panel.Visible = true
	Input.freeCursor = true
	if deckRefresh then
		deckRefresh()
	end
end

function ChipClient.CloseDeck()
	deckOpen = false
	if panel then
		panel.Visible = false
	end
	Input.freeCursor = false
end

function ChipClient.ToggleDeck()
	if deckOpen then
		ChipClient.CloseDeck()
	else
		ChipClient.OpenDeck()
	end
end

------------------------------------------------------------------------
-- SCANNER (identify) boxes
------------------------------------------------------------------------

local scanGui: ScreenGui
local scanPool: { Frame } = {}

local function updateScan()
	local on = scanOn and hasSlotted("scan") ~= nil
	if not on then
		for _, f in scanPool do
			f.Visible = false
		end
		return
	end
	local scanChip = hasSlotted("scan")
	local tier = scanChip and scanChip.tier or 1
	local cam = workspace.CurrentCamera
	local me = torsoOf(myChar())
	if not cam or not me then
		return
	end
	local targets = {}
	for _, m in allBodies() do
		if m ~= myChar() then
			local t = torsoOf(m)
			if t and (t.Position - me.Position).Magnitude < Config.ScanRange then
				table.insert(targets, { part = t, model = m, kind = "body" })
			end
		end
	end
	local props = workspace:FindFirstChild("SpawnedProps")
	for _, m in (props and props:GetChildren() or {}) do
		if m:IsA("Model") and m.PrimaryPart and Items.Kind(m) and (m.PrimaryPart.Position - me.Position).Magnitude < Config.ScanRange then
			table.insert(targets, { part = m.PrimaryPart, model = m, kind = "item" })
		end
	end
	local i = 0
	for _, tg in targets do
		i += 1
		if i > 24 then
			break
		end
		local f = scanPool[i]
		if not f then
			f = UI.make("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Parent = scanGui })
			UI.make("UIStroke", { Color = GREEN, Thickness = 1.5, Transparency = 0.2, Parent = f })
			UI.label({ Name = "L", Text = "", TextSize = 11, TextColor3 = GREEN, TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 0.4, Position = UDim2.fromScale(0, 1), Size = UDim2.fromOffset(180, 30), Parent = f })
			scanPool[i] = f
		end
		local sp, on2 = cam:WorldToViewportPoint(tg.part.Position)
		if on2 then
			local dist = (tg.part.Position - cam.CFrame.Position).Magnitude
			local box = math.clamp(260 / math.max(dist, 1), 16, 150)
			f.Position = UDim2.fromOffset(sp.X, sp.Y)
			f.Size = UDim2.fromOffset(box * 0.8, box)
			local lbl = f:FindFirstChild("L") :: TextLabel
			if tg.kind == "body" then
				local who = Players:GetPlayerFromCharacter(tg.model)
				local nm = who and who.DisplayName or tg.model.Name
				local txt = string.upper(nm)
				if tier >= 2 then
					local hp = tg.model:GetAttribute("HP_Torso")
					txt ..= typeof(hp) == "number" and ("  " .. math.floor(hp) .. "hp") or ""
				end
				if tier >= 3 then
					local fw = tg.model:GetAttribute("ChipFirewall")
					txt ..= "\nFIREWALL " .. (typeof(fw) == "number" and ("T" .. fw) or "NONE")
				end
				lbl.Text = txt
				lbl.TextColor3 = GREEN
			else
				local k = Items.Kinds[Items.Kind(tg.model) or ""]
				lbl.Text = k and k.name or "ITEM"
				lbl.TextColor3 = Color3.fromRGB(255, 220, 120)
			end
			f.Visible = true
		else
			f.Visible = false
		end
	end
	for j = i + 1, #scanPool do
		scanPool[j].Visible = false
	end
end

------------------------------------------------------------------------
-- victim effects
------------------------------------------------------------------------

local overlay: Frame

local function flashOverlay(color: Color3, t: number, life: number)
	overlay.BackgroundColor3 = color
	overlay.BackgroundTransparency = t
	TweenService:Create(overlay, TweenInfo.new(life), { BackgroundTransparency = 1 }):Play()
end

local function blind(dur: number)
	toast("OPTICS REBOOTING", RED)
	local w = UI.make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 60, Parent = gui })
	TweenService:Create(w, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(w, dur + 0.1)
	SoundLibrary.Play("static", nil, 0.5)
end

local rampageUntil = 0
local rampageTarget: number? = nil
local function rampage(dur: number, targetUserId: number?)
	rampageUntil = os.clock() + dur
	rampageTarget = targetUserId
	toast("CYBERPSYCHOSIS", Color3.fromRGB(190, 90, 255))
	SoundLibrary.Play("heartbeat", nil, 1)
	flashOverlay(Color3.fromRGB(120, 0, 160), 0.5, dur)
	Hallucinations.Force(dur + 3, 1)
	-- Movement, weapon acquisition and firing are driven by ControlService.

end

------------------------------------------------------------------------
-- the Blackwall beam + ash
------------------------------------------------------------------------

local function blackwallBeam(pos: Vector3)
	local camera = workspace.CurrentCamera
	local distance = camera and (camera.CFrame.Position - pos).Magnitude or math.huge
	if distance > 600 then return end
	local fx = Instance.new("Folder")
	fx.Name = "BlackwallBreach"
	fx.Parent = workspace:FindFirstChild("FX") or workspace
	Debris:AddItem(fx, 3)
	local red, white = Color3.fromRGB(235, 12, 30), Color3.fromRGB(255, 195, 195)
	local function piece(name, size, cf, color, shape)
		local p = Instance.new("Part")
		p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.Neon
		if shape then p.Shape = shape end
		p.Parent = fx
		return p
	end
	SoundLibrary.Play("static", pos, 0.8, 0.65)
	SoundLibrary.Play("ringing", pos, 0.65, 0.6)
	local core = piece("BreachCore", Vector3.one * 0.4, CFrame.new(pos), Color3.fromRGB(8, 0, 0), Enum.PartType.Ball)
	TweenService:Create(core, TweenInfo.new(0.7, Enum.EasingStyle.Exponential, Enum.EasingDirection.In), { Size = Vector3.one * 4.2 }):Play()
	local beams = {}
	for ring = 1, 3 do
		for i = 1, 12 do
			local angle = i * math.pi / 6 + ring * 0.3
			local r = 2.5 + ring * 1.2
			local at = pos + Vector3.new(math.cos(angle) * r, -2.6 + ring * 0.14, math.sin(angle) * r)
			local glyph = piece("BreachGlyph", Vector3.new(0.12, 0.06, 0.6), CFrame.lookAt(at, Vector3.new(pos.X, at.Y, pos.Z)), red)
			glyph.Transparency = 0.15 + ring * 0.1
			TweenService:Create(glyph, TweenInfo.new(1.2), { CFrame = glyph.CFrame + Vector3.new(0, ring * 0.7, 0), Transparency = 1 }):Play()
		end
	end
	for strand = 1, 7 do
		local angle = strand * math.pi * 2 / 7
		local a = pos + Vector3.new(math.cos(angle) * 4, -2.5, math.sin(angle) * 4)
		for j = 1, 7 do
			local b = pos + Vector3.new(math.cos(angle + j * 0.8) * (4 - j * 0.4), j * 1.6 - 2.5, math.sin(angle + j * 0.8) * (4 - j * 0.4))
			local len = (b - a).Magnitude
			local line = piece("CorruptionArc", Vector3.new(0.04 + j * 0.01, 0.04, len), CFrame.lookAt((a + b) * 0.5, b), j % 3 == 0 and white or red)
			TweenService:Create(line, TweenInfo.new(1.1, Enum.EasingStyle.Quad), { Transparency = 1 }):Play()
			a = b
		end
	end
	for _ = 1, 22 do
		local off = Vector3.new(rng:NextNumber(-5, 5), rng:NextNumber(-2, 3), rng:NextNumber(-5, 5))
		local shard = piece("DataFragment", Vector3.new(0.08, rng:NextNumber(0.15, 0.7), 0.06), CFrame.new(pos + off), red)
		TweenService:Create(shard, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = pos + Vector3.new(0, rng:NextNumber(1, 5), 0), Transparency = 0.85 }):Play()
	end
	task.delay(0.72, function()
		if not fx.Parent then return end
		local beam = piece("BlackwallBeam", Vector3.new(180, 0.5, 0.5), CFrame.new(pos + Vector3.new(0, 88, 0)) * CFrame.Angles(0, 0, math.pi / 2), red, Enum.PartType.Cylinder)
		local inner = piece("WhiteCore", Vector3.new(180, 0.18, 0.18), beam.CFrame, white, Enum.PartType.Cylinder)
		TweenService:Create(beam, TweenInfo.new(0.55), { Size = Vector3.new(180, 5, 5), Transparency = 1 }):Play()
		TweenService:Create(inner, TweenInfo.new(0.3), { Size = Vector3.new(180, 1.1, 1.1), Transparency = 1 }):Play()
		TweenService:Create(core, TweenInfo.new(0.45), { Size = Vector3.one * 13, Transparency = 1 }):Play()
		local ring = piece("ShockRing", Vector3.new(0.08, 2, 2), CFrame.new(pos + Vector3.new(0, -2.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), red, Enum.PartType.Cylinder)
		TweenService:Create(ring, TweenInfo.new(0.6), { Size = Vector3.new(0.06, 27, 27), Transparency = 1 }):Play()
		SoundLibrary.Play("ignite", pos, 0.9, 0.5)
		if distance < 75 then
			Cam.Shake((1 - distance / 75) * 0.9)
			flashOverlay(Color3.fromRGB(70, 0, 6), 0.8, 0.3)
		end
	end)
end

local function ash(victim: Model, pos: Vector3)
	-- the body crumbles into drifting ash
	local fx = workspace:FindFirstChild("FX") or workspace
	for _, d in victim:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.9 and d.Name ~= "HumanoidRootPart" then
			TweenService:Create(d, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		end
	end
	for _ = 1, 40 do
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = Color3.fromRGB(30 + rng:NextInteger(0, 30), 28, 28)
		local s = rng:NextNumber(0.1, 0.4)
		p.Size = Vector3.new(s, s, s)
		p.CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-1.5, 1.5), rng:NextNumber(-2, 2), rng:NextNumber(-1.5, 1.5)))
		p.Parent = fx
		local up = pos + Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(4, 9), rng:NextNumber(-3, 3))
		TweenService:Create(p, TweenInfo.new(rng:NextNumber(0.8, 1.6), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(up), Transparency = 1 }):Play()
		Debris:AddItem(p, 1.7)
	end
	SoundLibrary.Play("ignite", pos, 1)
end

local function uplink(fromId: number, toId: number, color: Color3)
	local a = Players:GetPlayerByUserId(fromId)
	local b = Players:GetPlayerByUserId(toId)
	local ta = a and torsoOf(a.Character)
	local tb = b and torsoOf(b.Character)
	if not ta or not tb then
		return
	end
	local fx = workspace:FindFirstChild("FX") or workspace
	local mid = (ta.Position + tb.Position) / 2
	local len = (tb.Position - ta.Position).Magnitude
	local line = Instance.new("Part")
	line.Anchored, line.CanCollide, line.CanQuery, line.CanTouch, line.CastShadow = true, false, false, false, false
	line.Material = Enum.Material.Neon
	line.Color = color
	line.Size = Vector3.new(0.18, 0.18, len)
	line.CFrame = CFrame.lookAt(mid, tb.Position)
	line.Parent = fx
	TweenService:Create(line, TweenInfo.new(0.4), { Transparency = 1 }):Play()
	Debris:AddItem(line, 0.45)
end

------------------------------------------------------------------------
-- the computer screen
------------------------------------------------------------------------

local pc: Frame
local pcRefresh: (() -> ())?

local function buildComputer()
	pc = UI.make("Frame", {
		Name = "Computer", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 460),
		BackgroundColor3 = Color3.fromRGB(6, 10, 14), BorderSizePixel = 0, Visible = false, ClipsDescendants = true, Parent = gui,
	})
	UI.make("UIStroke", { Color = CYAN, Thickness = 2, Parent = pc })
	local scale = UI.make("UIScale", { Name = "Scale", Parent = pc })
	scale:SetAttribute("Managed", true)
	local function fit()
		local cam = workspace.CurrentCamera
		local vs = cam and cam.ViewportSize or Vector2.new(1280, 720)
		scale.Scale = math.max(0.45, math.min(1, (vs.X - 20) / 640, (vs.Y - 20) / 460)) * UI.Global()
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	for i = 0, 45 do
		UI.make("Frame", { BackgroundColor3 = CYAN, BackgroundTransparency = 0.97, BorderSizePixel = 0, Position = UDim2.fromOffset(0, i * 10), Size = UDim2.new(1, 0, 0, 1), ZIndex = 1, Parent = pc })
	end
	UI.label({ Text = "NET TERMINAL  //  CHIP SHOP", TextSize = 18, TextColor3 = CYAN, Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(400, 22), ZIndex = 2, Parent = pc })
	local cashL = UI.label({ Name = "Cash", Text = "", TextSize = 14, TextColor3 = C.amber, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -80, 0, 12), Size = UDim2.fromOffset(200, 18), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 2, Parent = pc })
	UI.button({ Text = "CLOSE", TextSize = 11, Size = UDim2.fromOffset(60, 22), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), BackgroundColor3 = Color3.fromRGB(120, 16, 24), ZIndex = 2, Parent = pc }, function()
		ChipClient.CloseComputer()
	end)
	-- tabs
	local body = UI.make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(12, 70), Size = UDim2.fromOffset(616, 378), ScrollBarThickness = 5, CanvasSize = UDim2.fromOffset(0, 0), ZIndex = 2, Parent = pc })
	UI.make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
	local tab = "buy"
	local tabs = UI.make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 44), Size = UDim2.fromOffset(616, 22), ZIndex = 2, Parent = pc })
	UI.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), Parent = tabs })

	local function cashNow(): number
		local c = player:GetAttribute("Cash")
		return typeof(c) == "number" and c or 0
	end
	local function bagOf(kind: string): { any }
		local out = {}
		for _, chip in deck.bag do
			if kind == "blank" and chip.kind == "blank" then
				table.insert(out, chip)
			elseif kind == "virus" and chip.kind == "virus" then
				table.insert(out, chip)
			elseif kind == "video" and chip.video then
				table.insert(out, chip)
			end
		end
		return out
	end

	local selBlank, selPayload, selTier, selVideo, selVirus = nil, "explode", 1, nil, nil

	local function refresh()
		cashL.Text = Items.IsOwner(player) and "ADMIN (FREE)" or ("$" .. cashNow())
		for _, c in body:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local h = 0
		local function add(frame: GuiObject, height: number)
			frame.Parent = body
			h += height + 5
		end
		if tab == "buy" then
			for _, def in Chips.List do
				if def.admin and not Items.IsOwner(player) then
					continue
				end
				local row = UI.make("Frame", { BackgroundColor3 = PANEL2, BorderSizePixel = 0, Size = UDim2.new(1, -6, 0, 54), ZIndex = 2 })
				UI.make("UIStroke", { Color = Chips.Color(def), Thickness = 1, Transparency = 0.4, Parent = row })
				UI.label({ Text = def.name, TextSize = 14, TextColor3 = C.text, Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -240, 0, 18), ZIndex = 3, Parent = row })
				UI.label({ Text = def.info, TextSize = 10, TextColor3 = C.dim, TextWrapped = true, Position = UDim2.fromOffset(8, 20), Size = UDim2.new(1, -16, 0, 30), TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 3, Parent = row })
				for t = 1, def.tiers do
					UI.button({ Text = "T" .. t .. "  $" .. def.price[t], TextSize = 10, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8 - (def.tiers - t) * 74, 0, 4), Size = UDim2.fromOffset(70, 20), BackgroundColor3 = Color3.fromRGB(30, 60, 70), ZIndex = 3, Parent = row }, function()
						Remote:FireServer("buy", def.id, t)
					end)
				end
				add(row, 54)
			end
		elseif tab == "sell" then
			UI.label({ Text = "Sell unequipped chips for 40% of their purchase price.", TextSize = 13, Size = UDim2.new(1, -6, 0, 30), Parent = body })
			h += 35
			for _, chip in deck.bag do
				local def = Chips.ById[chip.id]
				if def and not def.admin and not chip.video then
					local value = math.floor(Chips.Price(chip.id, chip.tier) * 0.4)
					local row = UI.button({ Text = def.name .. " T" .. chip.tier .. "     SELL $" .. value, TextSize = 14, Size = UDim2.new(1, -6, 0, 38) }, function()
						Remote:FireServer("sell", chip.uid)
					end)
					add(row, 38)
				end
			end
		elseif tab == "virus" then
			UI.label({ Text = "PROGRAM A BLANK CHIP INTO A VIRUS ($" .. Config.VirusPrice .. ")", TextSize = 12, TextColor3 = GREEN, Size = UDim2.new(1, -6, 0, 18), ZIndex = 2 }).Parent = body
			h += 23
			local blanks = bagOf("blank")
			local pick = UI.make("Frame", { BackgroundColor3 = PANEL2, BorderSizePixel = 0, Size = UDim2.new(1, -6, 0, 30), ZIndex = 2 })
			UI.label({ Text = "BLANK:", TextSize = 11, Position = UDim2.fromOffset(6, 7), Size = UDim2.fromOffset(60, 16), ZIndex = 3, Parent = pick })
			if #blanks == 0 then
				UI.label({ Text = "(buy a BLANK CHIP first)", TextSize = 10, TextColor3 = C.dim, Position = UDim2.fromOffset(70, 7), Size = UDim2.fromOffset(300, 16), ZIndex = 3, Parent = pick })
			else
				for i, b in blanks do
					if i > 4 then
						break
					end
					UI.button({ Text = "#" .. i, TextSize = 10, Position = UDim2.fromOffset(60 + (i - 1) * 46, 4), Size = UDim2.fromOffset(42, 22), BackgroundColor3 = selBlank == b.uid and Color3.fromRGB(30, 120, 60) or PANEL, ZIndex = 3, Parent = pick }, function()
						selBlank = b.uid
						refresh()
					end)
				end
			end
			add(pick, 30)
			local payRow = UI.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, 54), ZIndex = 2 })
			UI.label({ Text = "PAYLOAD:", TextSize = 11, Position = UDim2.fromOffset(6, 2), Size = UDim2.fromOffset(80, 16), ZIndex = 3, Parent = payRow })
			for i, pl in Chips.Payloads do
				UI.button({ Text = pl.name, TextSize = 10, Position = UDim2.fromOffset(6 + ((i - 1) % 2) * 150, 20 + math.floor((i - 1) / 2) * 16), Size = UDim2.fromOffset(146, 15), BackgroundColor3 = selPayload == pl.id and Color3.fromRGB(120, 16, 24) or PANEL2, ZIndex = 3, Parent = payRow }, function()
				selPayload = pl.id
				refresh()
			end)
			end
			add(payRow, 54)
			local tierRow = UI.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, 26), ZIndex = 2 })
			UI.label({ Text = "TIER:", TextSize = 11, Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(50, 16), ZIndex = 3, Parent = tierRow })
			for t = 1, 3 do
				UI.button({ Text = "T" .. t, TextSize = 11, Position = UDim2.fromOffset(56 + (t - 1) * 48, 2), Size = UDim2.fromOffset(44, 22), BackgroundColor3 = selTier == t and Color3.fromRGB(120, 16, 24) or PANEL2, ZIndex = 3, Parent = tierRow }, function()
					selTier = t
					refresh()
				end)
			end
			add(tierRow, 26)
			local plInfo = Chips.PayloadById[selPayload]
			UI.label({ Text = plInfo and plInfo.info or "", TextSize = 10, TextColor3 = C.dim, Size = UDim2.new(1, -6, 0, 16), TextWrapped = true, ZIndex = 2 }).Parent = body
			h += 21
			UI.button({ Text = "WRITE THE VIRUS", TextSize = 13, Size = UDim2.new(1, -6, 0, 30), BackgroundColor3 = Color3.fromRGB(30, 130, 60), ZIndex = 2 }, function()
				if not selBlank then
					toast("PICK A BLANK CHIP", RED)
					return
				end
				Remote:FireServer("program", selBlank, selPayload, selTier)
			end).Parent = body
			h += 35
		elseif tab == "trojan" then
			UI.label({ Text = "BAKE A VIRUS INTO A VIDEO (A TROJAN)", TextSize = 12, TextColor3 = RED, Size = UDim2.new(1, -6, 0, 18), ZIndex = 2 }).Parent = body
			h += 23
			local vids = bagOf("video")
			local viruses = bagOf("virus")
			UI.label({ Text = "VIDEO:", TextSize = 11, Size = UDim2.new(1, -6, 0, 16), ZIndex = 2 }).Parent = body
			h += 21
			if #vids == 0 then
				UI.label({ Text = "(record one with a camera first)", TextSize = 10, TextColor3 = C.dim, Size = UDim2.new(1, -6, 0, 16), ZIndex = 2 }).Parent = body
				h += 21
			end
			for i, v in vids do
				UI.button({ Text = (v.name or "VIDEO") .. (selVideo == v.uid and "  ◄" or ""), TextSize = 11, Size = UDim2.new(1, -6, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = selVideo == v.uid and Color3.fromRGB(30, 60, 70) or PANEL2, ZIndex = 2 }, function()
					selVideo = v.uid
					refresh()
				end).Parent = body
				h += 27
			end
			UI.label({ Text = "VIRUS CHIP:", TextSize = 11, Size = UDim2.new(1, -6, 0, 16), ZIndex = 2 }).Parent = body
			h += 21
			if #viruses == 0 then
				UI.label({ Text = "(program a blank chip into a virus first)", TextSize = 10, TextColor3 = C.dim, Size = UDim2.new(1, -6, 0, 16), ZIndex = 2 }).Parent = body
				h += 21
			end
			for i, v in viruses do
				UI.button({ Text = (v.name or "VIRUS") .. (selVirus == v.uid and "  ◄" or ""), TextSize = 11, Size = UDim2.new(1, -6, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = selVirus == v.uid and Color3.fromRGB(120, 16, 24) or PANEL2, ZIndex = 2 }, function()
					selVirus = v.uid
					refresh()
				end).Parent = body
				h += 27
			end
			UI.button({ Text = "MAKE THE TROJAN", TextSize = 13, Size = UDim2.new(1, -6, 0, 30), BackgroundColor3 = Color3.fromRGB(150, 20, 30), ZIndex = 2 }, function()
				if not selVideo or not selVirus then
					toast("PICK A VIDEO AND A VIRUS", RED)
					return
				end
				Remote:FireServer("trojan", selVideo, selVirus)
			end).Parent = body
			h += 35
		end
		body.CanvasSize = UDim2.fromOffset(0, h + 10)
	end
	pcRefresh = refresh
	local function mkTab(id: string, text: string)
		UI.button({ Text = text, TextSize = 12, Size = UDim2.fromOffset(148, 22), BackgroundColor3 = PANEL2, ZIndex = 3, Parent = tabs }, function()
			tab = id
			refresh()
		end)
	end
	mkTab("buy", "BUY CHIPS")
	mkTab("sell", "SELL CHIPS")
	mkTab("virus", "PROGRAM VIRUS")
	mkTab("trojan", "MAKE TROJAN")
	player:GetAttributeChangedSignal("Cash"):Connect(function()
		if pc.Visible then
			refresh()
		end
	end)
end

function ChipClient.OpenComputer()
	if not pc then
		buildComputer()
	end
	setHackMode(false)
	SoundLibrary.Play("tvOn", nil, 0.5)
	pc.Visible = true
	Input.freeCursor = true
	if pcRefresh then
		pcRefresh()
	end
end

function ChipClient.CloseComputer()
	if pc then
		pc.Visible = false
	end
	Input.freeCursor = false
end

------------------------------------------------------------------------
-- the video player (a ViewportFrame scene, like the kill replays)
------------------------------------------------------------------------

local videoToken = 0
local pendingClip: { [string]: buffer } = {}

local function playVideo(meta: any)
	videoToken += 1
	local my = videoToken
	local g = UI.make("ScreenGui", { Name = "VideoPlay", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 35, Parent = player:WaitForChild("PlayerGui") })
	local bg = UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(2, 3, 4), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ClipsDescendants = true, Parent = g })
	local vp = UI.make("ViewportFrame", { BackgroundColor3 = Color3.fromRGB(80, 100, 120), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(150, 150, 160), LightColor = Color3.fromRGB(255, 250, 240), LightDirection = Vector3.new(-0.4, -1, -0.3), Parent = bg })
	local title = UI.label({ Text = meta.trojan and "PLAYBACK" or "PLAYBACK", TextSize = 24, TextColor3 = meta.trojan and RED or CYAN, TextStrokeTransparency = 0.4, Position = UDim2.fromOffset(24, 18), Size = UDim2.new(1, -40, 0, 30), ZIndex = 3, Parent = bg })
	local rec = UI.label({ Text = "● PLAY", TextSize = 20, TextColor3 = RED, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 18), Size = UDim2.fromOffset(120, 28), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3, Parent = bg })
	for i = 0, 28 do
		UI.make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.85, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromScale(0, i / 29), ZIndex = 4, Parent = bg })
	end
	local close = UI.button({ Text = "SKIP", TextSize = 12, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(100, 26), BackgroundColor3 = Color3.fromRGB(60, 62, 70), ZIndex = 5, Parent = bg }, function()
		videoToken += 1
		g:Destroy()
	end)
	Input.freeCursor = true

	task.spawn(function()
		-- wait for the data
		local t0 = os.clock()
		while not pendingClip[meta.code] and os.clock() - t0 < 4 and my == videoToken do
			task.wait(0.05)
		end
		local buf = pendingClip[meta.code]
		pendingClip[meta.code] = nil
		if my ~= videoToken or not buf then
			if g.Parent then
				g:Destroy()
			end
			Input.freeCursor = false
			return
		end
		local frames = ReplayCodec.Decode(buf, meta.slots)
		if #frames < 2 then
			g:Destroy()
			Input.freeCursor = false
			return
		end
		local cam = Instance.new("Camera")
		cam.FieldOfView = 70
		cam.Parent = vp
		vp.CurrentCamera = cam
		-- the place round the scene (copied from this machine's own map)
		local center = typeof(meta.center) == "Vector3" and meta.center or Vector3.zero
		require(script.Parent.ReplayGround).Copy(vp, center, 120)
		local map = workspace:FindFirstChild("Map")
		if map then
			local op = OverlapParams.new()
			op.FilterType = Enum.RaycastFilterType.Include
			op.FilterDescendantsInstances = { map }
			local okp, parts = pcall(function()
				return workspace:GetPartBoundsInRadius(center, 120, op)
			end)
			if okp then
				local n = 0
				for _, p in parts do
					if n >= 1400 then
						break
					end
					if p:IsA("BasePart") and p.Transparency < 0.95 and not p:IsA("Terrain") then
						local okc, c = pcall(function()
							return p:Clone()
						end)
						if okc and c then
							for _, d in c:GetDescendants() do
								if not (d:IsA("SpecialMesh") or d:IsA("Decal") or d:IsA("Texture") or d:IsA("BlockMesh")) then
									pcall(function()
										d:Destroy()
									end)
								end
							end
							c.Anchored = true
							c.Parent = vp
							n += 1
						end
						if n % 300 == 0 then
							task.wait()
						end
					end
				end
			end
		end
		if my ~= videoToken then
			g:Destroy()
			Input.freeCursor = false
			return
		end
		-- generic bodies for each actor (6 blocks)
		local actors = typeof(meta.actors) == "table" and meta.actors or {}
		local pieces = {}
		local SIZES = { Vector3.new(1.2, 1.2, 1.2), Vector3.new(2, 2, 1), Vector3.new(1, 2, 1), Vector3.new(1, 2, 1), Vector3.new(1, 2, 1), Vector3.new(1, 2, 1) }
		for ai, a in actors do
			local function c3(t): Color3
				return typeof(t) == "table" and Color3.fromRGB(t[1], t[2], t[3]) or Color3.fromRGB(150, 150, 150)
			end
			local cols = { c3(a.head), c3(a.torso), c3(a.arm), c3(a.arm), c3(a.leg), c3(a.leg) }
			for r = 1, 6 do
				local p = Instance.new("Part")
				p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
				p.Size = SIZES[r]
				p.Color = cols[r]
				p.Material = Enum.Material.SmoothPlastic
				p.Parent = vp
				pieces[(ai - 1) * 6 + r] = p
			end
		end
		rec.Visible = true
		local length = tonumber(meta.length) or frames[#frames].dt
		local start = os.clock()
		local fi = 1
		while my == videoToken do
			local t = os.clock() - start
			if t > length then
				break
			end
			while frames[fi + 1] and frames[fi + 1].dt <= t do
				fi += 1
			end
			local fa = frames[fi]
			local fb = frames[fi + 1] or fa
			local k = fb.dt > fa.dt and math.clamp((t - fa.dt) / (fb.dt - fa.dt), 0, 1) or 0
			local camcf = (ReplayCodec.OkCF(fa.cam) and ReplayCodec.OkCF(fb.cam) and fa.cam:Lerp(fb.cam, k)) or fa.cam or fb.cam
			if camcf then
				cam.CFrame = camcf
			end
			for s = 1, meta.slots do
				local p = pieces[s]
				if p then
					local ca, cb = fa.cfs[s], fb.cfs[s]
					local cf = (ca and cb and ca:Lerp(cb, k)) or ca or cb
					if cf then
						p.CFrame = cf
						p.Transparency = 0
					else
						p.Transparency = 1
					end
				end
			end
			rec.Visible = (os.clock() % 1) < 0.6
			RunService.RenderStepped:Wait()
		end
		if my == videoToken then
			title.Text = "END"
			rec.Visible = false
			task.wait(1.2)
			if my == videoToken and g.Parent then
				g:Destroy()
				Input.freeCursor = false
			end
		end
	end)
end

------------------------------------------------------------------------

local targetPicker
local function pickVirusTarget(item, carrierId)
	if targetPicker then targetPicker:Destroy() end
	Input.freeCursor = true
	targetPicker = UI.panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 370), Parent = gui })
	local function closePicker()
		if targetPicker then targetPicker:Destroy(); targetPicker = nil end
		Input.freeCursor = false
	end
	UI.label({ Text = "KILL DIRECTIVE / CHOOSE TARGET", TextSize = 18, Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(390, 28), Parent = targetPicker })
	UI.label({ Text = "15 s incubation. Control lasts until this target dies.", TextSize = 12, Position = UDim2.fromOffset(12, 44), Size = UDim2.fromOffset(390, 25), Parent = targetPicker })
	local list = UI.make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(12, 80), Size = UDim2.fromOffset(396, 238), ScrollBarThickness = 3, Parent = targetPicker })
	local y = 0
	for _, target in Players:GetPlayers() do
		if target.UserId ~= carrierId and target.Character and not target.Character:GetAttribute("Dead") then
			UI.button({ Text = target.DisplayName .. "  @" .. target.Name, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, -6, 0, 32), Parent = list }, function()
				Remote:FireServer("insert", item, target.UserId); closePicker()
			end)
			y += 38
		end
	end
	list.CanvasSize = UDim2.fromOffset(0, y)
	UI.button({ Text = "CANCEL", Position = UDim2.fromOffset(12, 330), Size = UDim2.fromOffset(396, 28), Parent = targetPicker }, closePicker)
end

function ChipClient.SetController(c: any)
	controller = c
end

function ChipClient.Init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	Remote = Remotes:WaitForChild("Chip") :: RemoteEvent

	gui = UI.make("ScreenGui", { Name = "ChipGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 26, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
	overlay = UI.make("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 41, Parent = gui })
	toastLabel = UI.label({ Text = "", TextSize = 20, TextColor3 = CYAN, TextTransparency = 1, TextStrokeTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.26, 0), Size = UDim2.fromOffset(700, 26), Parent = gui })
	scanGui = UI.make("ScreenGui", { Name = "ChipScan", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 24, Parent = player:WaitForChild("PlayerGui") })

	Remote.OnClientEvent:Connect(function(action, a, b, c)
		if action == "deck" then
			if typeof(a) == "table" then
				deck.slots = {}
				for i = 1, Config.ChipSlots do
					deck.slots[i] = (a.slots and a.slots[i]) or false
				end
				deck.bag = typeof(a.bag) == "table" and a.bag or {}
				if pcRefresh and pc and pc.Visible then pcRefresh() end
				if deckRefresh and deckOpen then
					deckRefresh()
				end
			end
		elseif action == "opendeck" then
			ChipClient.OpenDeck()
		elseif action == "picktarget" then
			pickVirusTarget(a, b)
		elseif action == "sound" and typeof(a) == "string" then
			SoundLibrary.Play(a, nil, 0.65)
		elseif action == "msg" or action == "cammsg" then
			toast(tostring(a), action == "cammsg" and RED or CYAN)
		elseif action == "blind" then
			blind(tonumber(a) or 3)
		elseif action == "rampage" then
			rampage(tonumber(a) or 8, typeof(b) == "number" and b or nil)
		elseif action == "hallucinate" then
			Hallucinations.Force(tonumber(a) or 15, 1)
			toast("SOMETHING IS WRONG", Color3.fromRGB(190, 90, 255))
		elseif action == "emp" then
			toast("CHIPS FRIED", CYAN)
			flashOverlay(Color3.fromRGB(120, 200, 255), 0.4, 0.6)
			SoundLibrary.Play("taser", nil, 0.8)
		elseif action == "glitch" then
			toast("HANDS GLITCHED", Color3.fromRGB(255, 200, 70))
		elseif action == "blocked" then
			toast("FIREWALL HELD", GREEN)
		elseif action == "dodge" then
			if typeof(a) == "CFrame" and player.Character then player.Character:PivotTo(a) end
			flashOverlay(CYAN, 0.55, 0.3)
			SoundLibrary.Play("whoosh", nil, 0.6)
		elseif action == "uplink" and typeof(a) == "number" and typeof(b) == "number" then
			uplink(a, b, typeof(c) == "Color3" and c or RED)
		elseif action == "blackwall" and typeof(a) == "Vector3" then
			blackwallBeam(a)
		elseif action == "ash" and typeof(a) == "Instance" and typeof(b) == "Vector3" then
			ash(a, b)
		elseif action == "pc" and a == "open" then
			ChipClient.OpenComputer()
		elseif action == "videostart" and typeof(a) == "table" and typeof(a.code) == "string" then
			playVideo(a)
		elseif action == "videodata" and typeof(a) == "string" and typeof(b) == "buffer" then
			pendingClip[a] = b
		end
	end)

	-- K: open the cyberdeck (unless you are an admin flying with the laser - then K is the laser)
	UserInputService.InputBegan:Connect(function(io, processed)
		if Input.IsControlled() then return end
		if processed or io.KeyCode ~= Enum.KeyCode.K then
			return
		end
		if controller and controller.flying and Items.Has(player, "laser") then
			return -- (K is the laser eyes right then)
		end
		if Input.menuOpen or Input.keysCaptured or Input.cutscene then
			return
		end
		ChipClient.ToggleDeck()
	end)
	UserInputService.InputBegan:Connect(function(io, processed)
		if Input.IsControlled() then return end
		if io.KeyCode == Enum.KeyCode.Escape then
			setHackMode(false)
			if deckOpen then
				ChipClient.CloseDeck()
			end
			if pc and pc.Visible then
				ChipClient.CloseComputer()
			end
		end
	end)

	-- zoom / scan every frame
	RunService.RenderStepped:Connect(function()
		local zChip = hasSlotted("zoom")
		if zoomOn and zChip and not (controller and controller.dead) then
			Cam.zoomFov = Config.ZoomFov[math.clamp(zChip.tier, 1, 3)]
		else
			if Cam.zoomFov ~= nil then
				Cam.zoomFov = nil
			end
			if zoomOn and not zChip then
				zoomOn = false
			end
		end
		updateScan()
	end)

	startHackControls()
	Remote:FireServer("deck")
end

return ChipClient
