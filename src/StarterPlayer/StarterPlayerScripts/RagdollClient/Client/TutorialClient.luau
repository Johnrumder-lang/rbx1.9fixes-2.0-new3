--!nonstrict
-- TutorialClient (v2.1f): a PLAYABLE tutorial for new players (it starts once; "REPLAY" in the settings starts it again).
-- Every step first SENDS YOU somewhere - a glowing beam and a ring on the ground, a label with the distance, and an arrow at the edge of the
-- screen when the marker is behind you - and then shows HOW to do the thing (per device: keyboard / gamepad / phone). Where the thing needs
-- an object (an item to grab, a dummy to kick, an item on the floor) a second marker sits right on it.
-- Steps: move to the armory, grab an item, use it at the targets, pockets, drop kick a dummy, lie down, pick up from the floor, stand up.
-- Every step completes by itself when you do the thing. SKIP leaves it for good.
-- (v2.8) A LINE of glowing dots runs along the ground from you towards the marker (it marches forward), and the same marker
-- and line show a quest's goal when no tutorial runs (player attributes Objective / ObjectiveName: the STILLWATER quest).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Settings = require(Shared:WaitForChild("Settings"))
local UI = require(script.Parent:WaitForChild("UI"))
local Input = require(script.Parent:WaitForChild("Input"))

local C = UI.C
local player = Players.LocalPlayer

local TutorialClient = {}

local controller: any = nil
local gui: ScreenGui? = nil
local titleL: TextLabel
local whereL: TextLabel
local textL: TextLabel
local stepL: TextLabel
local bar: Frame
local stepIndex = 0
local running = false
local flags = { fired = false, kicked = false }
local phase = "go" -- "go": walk to the marker, "do": do the thing
local arrowHolder: Frame
local arrow: Frame
local arrowDist: TextLabel
local cacheT, cacheGo, cacheTarget, cacheLabel = 0, nil, nil, nil -- (what is where: looked up 3 times a second)

------------------------------------------------------------------------
-- what you hold / do
------------------------------------------------------------------------

local function holding(): boolean
	local c = controller
	if not c or not c.hands then
		return false
	end
	for _, h in c.hands do
		if h.grip and h.grip.item then
			return true
		end
	end
	return false
end

local function anyGrip(): boolean
	local c = controller
	if not c or not c.hands then
		return false
	end
	for _, h in c.hands do
		if h.grip then
			return true
		end
	end
	return false
end

local function stowedCount(): number
	local c = controller
	if not c or not c._pockets then
		return 0
	end
	local n = 0
	for _ in c:_pockets() do
		n += 1
	end
	return n
end

local function torsoPos(): Vector3?
	local c = player.Character
	local t = c and c:FindFirstChild("Torso")
	return t and t:IsA("BasePart") and t.Position or nil
end

------------------------------------------------------------------------
-- where things are
------------------------------------------------------------------------

local function mapFolder(): Instance?
	return workspace:FindFirstChild("Map")
end

-- the middle of the weapon tables (the ARMORY)
local function armoryPos(): Vector3
	local mf = mapFolder()
	local m = mf and mf:FindFirstChild("Armory")
	if m and m:IsA("Model") then
		local cf = m:GetBoundingBox()
		return Vector3.new(cf.Position.X, 0, cf.Position.Z)
	end
	return Vector3.new(45, 0, 48)
end

-- the target dummies of the range
local function dummies(): { Vector3 }
	local out = {}
	local folder = workspace:FindFirstChild("Dummies")
	for _, d in (folder and folder:GetChildren() or {}) do
		if d:IsA("Model") and d:GetAttribute("IsDummy") then
			local t = d:FindFirstChild("Torso")
			if t and t:IsA("BasePart") then
				table.insert(out, t.Position)
			end
		end
	end
	return out
end

local function nearestTo(list: { Vector3 }, from: Vector3): Vector3?
	local best, bd = nil, math.huge
	for _, p in list do
		local d = (p - from).Magnitude
		if d < bd then
			best, bd = p, d
		end
	end
	return best
end

local function rangePos(): Vector3
	local list = dummies()
	local from = torsoPos() or Vector3.zero
	local near = nearestTo(list, from)
	if near then
		return Vector3.new(near.X, 0, near.Z)
	end
	return Vector3.new(8, 0, 58) -- (where the dummies stand in the sandbox)
end

-- the nearest loose item (not held, not in a pocket) within 'range' studs
local function nearestItem(range: number): Vector3?
	local from = torsoPos()
	if not from then
		return nil
	end
	local best, bd = nil, range
	local folder = workspace:FindFirstChild("SpawnedProps")
	for _, d in (folder and folder:GetChildren() or {}) do
		if d:IsA("Model") and d:GetAttribute("Item") ~= nil and d:GetAttribute("HolderId") == nil and d:GetAttribute("StowedBy") == nil and d.PrimaryPart then
			local dist = (d.PrimaryPart.Position - from).Magnitude
			if dist < bd then
				best, bd = d.PrimaryPart.Position, dist
			end
		end
	end
	return best
end

local function nearestDummy(): Vector3?
	return nearestTo(dummies(), torsoPos() or Vector3.zero)
end

------------------------------------------------------------------------
-- the markers: a beam of light, a ring on the ground, a label, and an arrow at the screen edge
------------------------------------------------------------------------

local markerFolder: Folder? = nil
local beam: Part? = nil
local ring: Part? = nil
local anchorPart: Part? = nil
local markerLabel: TextLabel? = nil
local markerSub: TextLabel? = nil
local markerPos: Vector3? = nil

-- (v2.8) the line to the goal: dots on the ground that march towards it
local GUIDE_N = 16
local GUIDE_GAP = 3
local guideFolder: Folder? = nil
local guideDots: { BasePart } = {}

local function hideGuide()
	for _, d in guideDots do
		d.Transparency = 1
	end
end

local function updateGuide(to: Vector3?)
	local me = torsoPos()
	if not to or not me then
		hideGuide()
		return
	end
	if not guideFolder or not guideFolder.Parent then
		local f = Instance.new("Folder")
		f.Name = "GuideLine"
		f.Parent = workspace
		guideFolder = f
		table.clear(guideDots)
		for _ = 1, GUIDE_N do
			local p = Instance.new("Part")
			p.Anchored = true
			p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
			p.Material = Enum.Material.Neon
			p.Color = Color3.fromRGB(255, 196, 64)
			p.Shape = Enum.PartType.Ball
			p.Size = Vector3.new(0.5, 0.5, 0.5)
			p.Transparency = 1
			p.Parent = f
			table.insert(guideDots, p)
		end
	end
	local flat = Vector3.new(to.X - me.X, 0, to.Z - me.Z)
	local dist = flat.Magnitude
	if dist < 9 then
		hideGuide()
		return
	end
	local dir = flat.Unit
	local footY = me.Y - 2.7
	local offset = (os.clock() * 7) % GUIDE_GAP
	for i, d in guideDots do
		local along = 2 + (i - 1) * GUIDE_GAP + offset
		if along > dist - 3 then
			d.Transparency = 1
		else
			local k = along / dist
			local y = footY + (to.Y - footY) * k
			d.CFrame = CFrame.new(me.X + dir.X * along, y + 0.35, me.Z + dir.Z * along)
			d.Transparency = 0.15 + 0.8 * (i / GUIDE_N)
		end
	end
end

local function clearMarker()
	hideGuide()
	if markerFolder then
		markerFolder:Destroy()
	end
	markerFolder, beam, ring, anchorPart, markerLabel, markerSub, markerPos = nil, nil, nil, nil, nil, nil, nil
	if arrowHolder then
		arrowHolder.Visible = false
	end
end

local function ground(pos: Vector3): Vector3
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = player.Character and { player.Character } or {}
	local hit = workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -140, 0), rp)
	return hit and hit.Position or pos
end

local function setMarker(pos: Vector3?, label: string?, onItem: boolean?)
	if not pos then
		clearMarker()
		return
	end
	local at = onItem and pos or ground(pos)
	if markerFolder and markerPos and (markerPos - at).Magnitude < 0.5 and markerLabel and markerLabel.Text == label then
		return
	end
	clearMarker()
	markerPos = at
	local f = Instance.new("Folder")
	f.Name = "TutorialMarker"
	f.Parent = workspace
	markerFolder = f
	local function part(size: Vector3, cf: CFrame, transparency: number, shape: Enum.PartType?)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(255, 196, 64)
		p.Transparency = transparency
		p.Size = size
		p.CFrame = cf
		if shape then
			p.Shape = shape
		end
		p.Parent = f
		return p
	end
	local h = onItem and 14 or 90
	beam = part(Vector3.new(onItem and 0.5 or 1.6, h, onItem and 0.5 or 1.6), CFrame.new(at + Vector3.new(0, h / 2, 0)), 0.55)
	ring = part(Vector3.new(0.3, onItem and 3 or 10, onItem and 3 or 10), CFrame.new(at + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.3, Enum.PartType.Cylinder)
	anchorPart = part(Vector3.new(0.5, 0.5, 0.5), CFrame.new(at + Vector3.new(0, onItem and 4.5 or 12, 0)), 1)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(300, 74)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 5000
	bb.Adornee = anchorPart
	bb.Parent = anchorPart
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
	back.BackgroundTransparency = 0.15
	back.BorderSizePixel = 0
	back.Parent = bb
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 5, 1, 0)
	stripe.BackgroundColor3 = Color3.fromRGB(255, 196, 64)
	stripe.BorderSizePixel = 0
	stripe.Parent = back
	markerLabel = UI.label({ Text = label or "", Font = UI.FONT_TITLE, TextSize = 28, TextColor3 = Color3.fromRGB(255, 214, 110), Position = UDim2.fromOffset(16, 4), Size = UDim2.new(1, -24, 0, 36), Parent = back })
	markerSub = UI.label({ Text = "", TextSize = 20, TextColor3 = Color3.fromRGB(230, 230, 232), Position = UDim2.fromOffset(16, 38), Size = UDim2.new(1, -24, 0, 28), Parent = back })
end

local function updateMarker()
	local pos, a = markerPos, anchorPart
	local cam = workspace.CurrentCamera
	if not pos or not a or not cam then
		return
	end
	local t = os.clock()
	if ring then
		ring.Size = Vector3.new(0.3, ring.Size.Y, ring.Size.Z)
		ring.Transparency = 0.25 + 0.25 * (0.5 + 0.5 * math.sin(t * 3))
	end
	if beam then
		beam.Transparency = 0.5 + 0.15 * math.sin(t * 2.4)
	end
	local me = torsoPos()
	local dist = me and (me - pos).Magnitude or 0
	if markerSub then
		markerSub.Text = string.format("%d studs", math.floor(dist))
	end
	updateGuide(pos)
	-- an arrow at the edge of the screen when the marker is not in view
	local v, onScreen = cam:WorldToViewportPoint(a.Position)
	local size = cam.ViewportSize
	if onScreen and v.Z > 0 then
		arrowHolder.Visible = false
	else
		local dir = Vector2.new(v.X - size.X / 2, v.Y - size.Y / 2)
		if v.Z < 0 then
			dir = -dir
		end
		if dir.Magnitude < 1 then
			dir = Vector2.new(0, -1)
		end
		local u = dir.Unit
		local margin = 70
		local scale = math.min((size.X / 2 - margin) / math.max(math.abs(u.X), 0.001), (size.Y / 2 - margin) / math.max(math.abs(u.Y), 0.001))
		local p = Vector2.new(size.X / 2, size.Y / 2) + u * scale
		arrowHolder.Position = UDim2.fromOffset(p.X, p.Y)
		arrow.Rotation = math.deg(math.atan2(u.Y, u.X)) + 45
		arrowDist.Text = string.format("%d", math.floor(dist))
		arrowHolder.Visible = true
	end
end

------------------------------------------------------------------------
-- the steps
------------------------------------------------------------------------

-- go = where to walk first (name, position, radius); target = an object to mark while you do the thing
local STEPS = {
	{
		title = "MOVE",
		go = { name = "THE ARMORY", pos = armoryPos, radius = 16, line = "The weapon tables. Walk there." },
		text = {
			KeyboardMouse = "Walk with W A S D, hold SHIFT to run, SPACE to jump. Follow the glowing beam to the weapon tables.",
			Gamepad = "Walk with the left stick, A jumps. Follow the glowing beam to the weapon tables.",
			Touch = "Walk with the stick on the left, JUMP to jump. Follow the glowing beam to the weapon tables.",
		},
		check = function()
			return phase == "do"
		end,
	},
	{
		title = "GRAB AN ITEM",
		go = { name = "THE ARMORY", pos = armoryPos, radius = 16, line = "Go to the weapon tables." },
		target = function()
			return nearestItem(40), "GRAB THIS"
		end,
		text = {
			KeyboardMouse = "Hold the LEFT or RIGHT mouse button to reach with that arm, then press Q (left hand) or E (right hand) while your hand touches an item.",
			Gamepad = "Hold L2 / R2 to reach with an arm, then press L1 / R1 while the hand touches an item.",
			Touch = "Hold AIM L / AIM R to reach with that arm, then tap GRAB L / GRAB R while the hand touches an item.",
		},
		check = holding,
	},
	{
		title = "USE IT",
		go = { name = "THE TARGETS", pos = rangePos, radius = 28, line = "Go to the shooting range and face the dummies." },
		target = function()
			return nearestDummy(), "SHOOT / HIT"
		end,
		text = {
			KeyboardMouse = "Press F to use the item (shoot, swing, throw...). Hold G to aim. Hold F for automatic guns.",
			Gamepad = "Press X to use the item. Hold D-pad left to aim.",
			Touch = "Tap USE to use the item (hold it for automatic guns). SIGHT aims.",
		},
		check = function()
			return flags.fired
		end,
	},
	{
		title = "POCKETS",
		text = {
			KeyboardMouse = "HOLD Q or E while that hand holds an item: it goes into a pocket (hip or back). Hold the key again with an empty hand to take it out. Stowed items stay on you when you fall.",
			Gamepad = "HOLD L1 or R1 while that hand holds an item: it goes into a pocket. Hold it again with an empty hand to take it out.",
			Touch = "Tap STOW L or STOW R: the item in that hand goes into a pocket. Tap again with an empty hand to take it out.",
		},
		check = function()
			return stowedCount() > 0
		end,
	},
	{
		title = "DROP KICK",
		go = { name = "A DUMMY", pos = rangePos, radius = 22, line = "Go to the dummies." },
		target = function()
			return nearestDummy(), "KICK THIS"
		end,
		text = {
			KeyboardMouse = "Run at a dummy, jump (SPACE), then press C in the air: a drop kick. It sends people flying and goes through window glass.",
			Gamepad = "Run at a dummy, jump (A), then press R3 in the air: a drop kick.",
			Touch = "Run at a dummy, tap JUMP, then KICK while you are in the air: a drop kick.",
		},
		check = function()
			return flags.kicked
		end,
	},
	{
		title = "LIE DOWN",
		text = {
			KeyboardMouse = "First put your item on the floor (tap Q / E), then press X to lie down (prone).",
			Gamepad = "First put your item on the floor (tap L1 / R1), then press D-pad down to lie down.",
			Touch = "First put your item on the floor (tap GRAB), then tap the PRONE button to lie down.",
		},
		check = function()
			local c = controller
			return c ~= nil and (c.state == "Prone" or c.state == "Downed") and not holding()
		end,
	},
	{
		title = "PICK UP FROM THE FLOOR",
		target = function()
			return nearestItem(14), "PICK UP"
		end,
		text = {
			KeyboardMouse = "While lying down: hold the mouse button to reach, bring your arm close to the item on the floor, and press Q / E to pick it up.",
			Gamepad = "While lying down: hold L2 / R2 to reach, bring your arm close to the item, and press L1 / R1.",
			Touch = "While lying down: hold AIM L / AIM R to reach, bring your arm close to the item, and tap GRAB.",
		},
		check = function()
			local c = controller
			return c ~= nil and (c.state == "Prone" or c.state == "Downed") and anyGrip()
		end,
	},
	{
		title = "STAND UP",
		text = {
			KeyboardMouse = "Press X again to stand up.",
			Gamepad = "Press D-pad down again to stand up.",
			Touch = "Tap PRONE again to stand up.",
		},
		check = function()
			local c = controller
			return c ~= nil and c.state ~= "Prone" and c.state ~= "Downed" and c.state ~= "Ragdoll"
		end,
	},
}

local function close(done: boolean)
	running = false
	clearMarker()
	if gui then
		gui:Destroy()
		gui = nil
	end
	if done then
		Settings.Set("tutorialDone", true)
	end
end

local function show(i: number)
	stepIndex = i
	local s = STEPS[i]
	if not s or not gui then
		return
	end
	local device = Input.lastDevice
	phase = s.go and "go" or "do"
	cacheT = 0
	titleL.Text = s.title
	titleL.TextColor3 = C.amber
	textL.Text = s.text[device] or s.text.KeyboardMouse
	whereL.Text = s.go and ("GO TO  " .. s.go.name .. "   -   " .. s.go.line) or ""
	stepL.Text = string.format("STEP %d / %d", i, #STEPS)
	bar.Size = UDim2.fromScale((i - 1) / #STEPS, 1)
end

-- each frame: where the marker is, and when you arrive the step turns from "go" to "do"
local function tick()
	local s = STEPS[stepIndex]
	if not s or not gui then
		return
	end
	local me = torsoPos()
	-- (what is where is looked up 3 times a second, not every frame)
	if os.clock() - cacheT > 0.33 then
		cacheT = os.clock()
		cacheGo = s.go and s.go.pos() or nil
		if s.target then
			cacheTarget, cacheLabel = s.target()
		else
			cacheTarget, cacheLabel = nil, nil
		end
	end
	if phase == "go" and s.go and me and cacheGo then
		local p = cacheGo
		local flat = Vector3.new(p.X - me.X, 0, p.Z - me.Z).Magnitude
		setMarker(p, s.go.name, false)
		if flat <= s.go.radius then
			phase = "do"
			whereL.Text = "YOU ARE HERE"
		end
	end
	if phase == "do" then
		if s.target and cacheTarget then
			setMarker(cacheTarget, cacheLabel, true)
		else
			clearMarker()
		end
	end
	updateMarker()
end

function TutorialClient.Start()
	if running then
		return
	end
	running = true
	flags.fired, flags.kicked = false, false
	phase = "go"
	gui = UI.make("ScreenGui", { Name = "Tutorial", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 12, Parent = player:WaitForChild("PlayerGui") })
	-- (a big panel: 540 x 320, scaled to the screen)
	local panel = UI.panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(540, 330),
		Accent = C.amber,
		Parent = gui,
	})
	local scale = UI.make("UIScale", { Parent = panel })
	scale:SetAttribute("Managed", true)
	local cam = workspace.CurrentCamera
	if cam then
		scale.Scale = math.clamp((cam.ViewportSize.X * 0.46) / 540, 0.62, 1.2) * UI.Global()
	end
	UI.label({ Text = "TUTORIAL", Font = UI.FONT_TITLE, TextSize = 16, TextColor3 = C.dim, Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(160, 20), Parent = panel })
	stepL = UI.label({ Text = "", Font = UI.FONT_NUM, TextSize = 16, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(1, -198, 0, 10), Size = UDim2.fromOffset(180, 20), Parent = panel })
	titleL = UI.label({ Text = "", Font = UI.FONT_TITLE, TextSize = 34, TextColor3 = C.amber, Position = UDim2.fromOffset(18, 34), Size = UDim2.new(1, -36, 0, 42), Parent = panel })
	whereL = UI.label({ Text = "", Font = UI.FONT_TITLE, TextSize = 18, TextColor3 = C.good, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(18, 80), Size = UDim2.new(1, -36, 0, 24), Parent = panel })
	textL = UI.label({ Text = "", TextSize = 21, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(18, 112), Size = UDim2.new(1, -36, 0, 152), Parent = panel })
	local back = UI.make("Frame", { BackgroundColor3 = C.panel2, BorderSizePixel = 0, Position = UDim2.new(0, 18, 1, -42), Size = UDim2.new(1, -190, 0, 8), Parent = panel })
	bar = UI.make("Frame", { BackgroundColor3 = C.good, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = back })
	UI.button({ Text = "SKIP", TextSize = 18, Size = UDim2.fromOffset(140, 34), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14), Parent = panel }, function()
		close(true)
	end)
	-- the arrow at the edge of the screen (a square turned 45 degrees: its corner points at the marker)
	arrowHolder = UI.make("Frame", { Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(60, 60), BackgroundTransparency = 1, ZIndex = 5, Parent = gui })
	arrow = UI.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = Color3.fromRGB(255, 196, 64), BorderSizePixel = 0, Rotation = 45, Parent = arrowHolder })
	arrowDist = UI.label({ Text = "", Font = UI.FONT_TITLE, TextSize = 18, TextColor3 = Color3.fromRGB(10, 10, 12), TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(40, 24), ZIndex = 6, Parent = arrowHolder })
	show(1)
	task.spawn(function()
		while running and gui do
			task.wait(0.15)
			local s = STEPS[stepIndex]
			if s and s.check() then
				bar.Size = UDim2.fromScale(stepIndex / #STEPS, 1)
				titleL.Text = "DONE!"
				titleL.TextColor3 = C.good
				clearMarker()
				task.wait(0.9)
				if not running then
					return
				end
				if stepIndex >= #STEPS then
					titleL.Text = "TUTORIAL COMPLETE"
					textL.Text = "That is everything. Have fun. You can replay this in the settings (M)."
					whereL.Text = ""
					task.wait(3.5)
					close(true)
					return
				end
				flags.fired, flags.kicked = false, false
				show(stepIndex + 1)
			end
		end
	end)
end

function TutorialClient.SetController(c)
	controller = c
end

function TutorialClient.Init()
	Input.Action:Connect(function(action: string)
		if not running then
			return
		end
		if action == "Fire" and holding() then
			flags.fired = true
		elseif action == "Kick" then
			local c = controller
			if c and (c.groundTime or 0) < 0.05 then
				flags.kicked = true
			end
		end
	end)
	-- (v2.8) a quest's goal (the STILLWATER quest) when no tutorial runs
	local questMarker = false
	RunService.RenderStepped:Connect(function()
		if running then
			questMarker = false
			tick()
			return
		end
		local goal = player:GetAttribute("Objective")
		if typeof(goal) == "Vector3" then
			if not arrowHolder or not arrowHolder:IsDescendantOf(player) then
				-- (no tutorial gui (never ran / closed): the arrow at the edge of the screen lives in its own little gui)
				local old = player:WaitForChild("PlayerGui"):FindFirstChild("GoalArrow")
				if old then
					old:Destroy()
				end
				local g = UI.make("ScreenGui", { Name = "GoalArrow", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 12, Parent = player:WaitForChild("PlayerGui") })
				arrowHolder = UI.make("Frame", { Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(60, 60), BackgroundTransparency = 1, ZIndex = 5, Parent = g })
				arrow = UI.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = Color3.fromRGB(255, 196, 64), BorderSizePixel = 0, Rotation = 45, Parent = arrowHolder })
				arrowDist = UI.label({ Text = "", Font = UI.FONT_TITLE, TextSize = 18, TextColor3 = Color3.fromRGB(10, 10, 12), TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(40, 24), ZIndex = 6, Parent = arrowHolder })
			end
			local name = player:GetAttribute("ObjectiveName")
			setMarker(goal, typeof(name) == "string" and name or "GOAL", false)
			questMarker = true
			updateMarker()
		elseif questMarker then
			questMarker = false
			clearMarker()
		end
	end)
	-- a new player: start after the settings have arrived
	task.delay(6, function()
		if Settings.Get("tutorialDone") ~= true then
			TutorialClient.Start()
		end
	end)
end

return TutorialClient
