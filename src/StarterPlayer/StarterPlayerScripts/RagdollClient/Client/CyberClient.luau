--!nonstrict
-- CyberClient (v2.8): everything you see and press of the cyberware.
--   * the CYBER BAR: one slot per implant with an ability, keys 1-9 (M > CYBER: click a slot, press another key). Tap on a phone.
--     LOCK (optics), HUNT (cortex), CANNON, ARM GUN, BLADES, PULL (palms), CLOAK, FREEZE (admins).
--   * what implants do on your screen: the locked target (WARDEN OPTICS: through walls, aim pulled onto it, red combat
--     vision), the hunted person (HUNTER CORTEX: arrow + distance), the item your palms lock (LODESTONE), the shooter
--     SENTRY REFLEX turns you to, the shield (AEGIS), the cloak, the ice of ZERO HOUR.
--   * CYBERPSYCHOSIS: hallucinations that grow with it; a CRASH OUT takes your body for a few seconds - it shoots / hits
--     everything that moves.
--   * the RIPPERDOC: his shop (sharp, dark, red), the waiting list, your turn (a line to the bed), the syringe, the TV
--     ads, the list on the waiting room board; the picker of a ripper kit (which implant comes out).
--   * M > CYBER: your implants, load / tolerance, the keys, the HOWLER's shell and colour.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cyberware = require(Shared:WaitForChild("Cyberware"))
local Settings = require(Shared:WaitForChild("Settings"))
local Items = require(Shared:WaitForChild("Items"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))
local TimeScale = require(Shared:WaitForChild("TimeScale"))
local Modules = script.Parent
local UI = require(Modules:WaitForChild("UI"))
local Input = require(Modules:WaitForChild("Input"))
local Cam = require(Modules:WaitForChild("CameraController"))
local MathUtil = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MathUtil"))
local Hallucinations = require(Modules:WaitForChild("Hallucinations"))
local Controller = (require(Modules:WaitForChild("CharacterController")) :: any)

local CyberClient = {}
CyberClient.crashTarget = nil :: Model? -- (a crash out: what the body goes for)

local player = Players.LocalPlayer
local C = UI.C
local RED = Color3.fromRGB(255, 52, 64)
local CYAN = Color3.fromRGB(70, 220, 255)
local PANEL = Color3.fromRGB(10, 11, 14)
local PANEL2 = Color3.fromRGB(26, 27, 33)

local Remote: RemoteEvent
local controller: any = nil
local gui: ScreenGui
local rng = Random.new()

type Slot = { key: string, id: string, def: Cyberware.Def, tier: number }
local eff: { [string]: number } = {}
local bar: { Slot } = {}
local binds: { string } = table.clone(Cyberware.DefaultKeys)
local barFrame: Frame
local barButtons: { TextButton } = {}
local statusPanel: Frame
local shieldFill: Frame
local shieldText: TextLabel
local psychoFill: Frame
local psychoText: TextLabel
local toastLabel: TextLabel
local overlay: Frame
local redVision: ColorCorrectionEffect

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------

local function now(): number
	return workspace:GetServerTimeNow()
end

local lastToastSound = 0
local function toast(text: string, color: Color3?)
	if not toastLabel then
		return
	end
	-- (v2.8.2) a soft notice sound (not more than one every half second)
	if os.clock() - lastToastSound > 0.5 then
		lastToastSound = os.clock()
		SoundLibrary.Play("notify", nil, 0.6)
	end
	toastLabel.Text = text
	toastLabel.TextColor3 = color or CYAN
	toastLabel.TextTransparency = 0
	toastLabel.TextStrokeTransparency = 0.4
	TweenService:Create(toastLabel, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
end
CyberClient.Toast = toast

local function myChar(): Model?
	return player.Character
end

local function torsoOf(m: Instance?): BasePart?
	local t = m and m:FindFirstChild("Torso")
	return (t and t:IsA("BasePart")) and t or nil
end

local function bodyOf(inst: Instance?): Model?
	local m = inst and inst:FindFirstAncestorOfClass("Model")
	while m do
		if m:GetAttribute("RagdollRig") or m:FindFirstChild("Torso") and m:FindFirstChildOfClass("Humanoid") then
			return m
		end
		m = m:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function camRay(): Ray
	local cam = workspace.CurrentCamera
	local vs = cam.ViewportSize
	return cam:ViewportPointToRay(vs.X * 0.5, vs.Y * 0.5)
end

local function ignoreParams(): RaycastParams
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local list = {}
	local ch = myChar()
	if ch then
		table.insert(list, ch)
	end
	local fx = workspace:FindFirstChild("FX")
	if fx then
		table.insert(list, fx)
	end
	rp.FilterDescendantsInstances = list
	return rp
end

-- every body that can be a target (players, NPCs, dummies)
local function bodies(): { Model }
	local out = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and p.Character then
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

-- the body nearest the middle of the screen (hit by the ray or within `cone` degrees)
local function bodyAtCrosshair(range: number, cone: number): Model?
	local ray = camRay()
	local hit = workspace:Raycast(ray.Origin, ray.Direction * range, ignoreParams())
	local b = hit and bodyOf(hit.Instance)
	if b and b ~= myChar() then
		return b
	end
	local best, bestA = nil, math.rad(cone)
	for _, m in bodies() do
		local t = torsoOf(m)
		if t and m:GetAttribute("Dead") ~= true then
			local d = t.Position - ray.Origin
			if d.Magnitude < range then
				local a = math.acos(math.clamp(d.Unit:Dot(ray.Direction), -1, 1))
				if a < bestA then
					best, bestA = m, a
				end
			end
		end
	end
	return best
end

local function yawPitchTo(dir: Vector3): (number, number)
	local d = dir.Unit
	return math.atan2(-d.X, -d.Z), math.asin(math.clamp(d.Y, -1, 1))
end

-- (v2.8.1) the mark round a locked / hunted body: a sharp square frame like the LODESTONE's lock on an item - a thin
-- edge and thick corner brackets - that sits round the whole body, through walls, and grows / shrinks with the distance
local function highlight(m: Instance, color: Color3, name: string): BillboardGui
	local torso = (m:IsA("Model") and (m:FindFirstChild("Torso") or m.PrimaryPart)) or m
	local sc = m:GetAttribute("BodyScale")
	local k = typeof(sc) == "number" and sc or 1
	local bb = Instance.new("BillboardGui")
	bb.Name = name
	bb.Size = UDim2.fromScale(5.4 * k, 6.8 * k) -- (studs)
	bb.StudsOffset = Vector3.new(0, -0.3 * k, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = torso :: any
	local box = UI.make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = bb })
	UI.make("UIStroke", { Color = color, Thickness = 1.5, Transparency = 0.25, Parent = box })
	local T = 3
	for _, c in { { 0, 0, 1, 1 }, { 1, 0, -1, 1 }, { 0, 1, 1, -1 }, { 1, 1, -1, -1 } } do
		local ax, ay = c[1], c[2]
		UI.make("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, AnchorPoint = Vector2.new(ax, ay), Position = UDim2.fromScale(ax, ay),
			Size = UDim2.new(0.28, 0, 0, T), Parent = box })
		UI.make("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, AnchorPoint = Vector2.new(ax, ay), Position = UDim2.fromScale(ax, ay),
			Size = UDim2.new(0, T, 0.22, 0), Parent = box })
	end
	-- a small cross in the middle
	UI.make("Frame", { BackgroundColor3 = color, BackgroundTransparency = 0.3, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.new(0, 10, 0, 2), Parent = box })
	UI.make("Frame", { BackgroundColor3 = color, BackgroundTransparency = 0.3, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.new(0, 2, 0, 10), Parent = box })
	bb.Parent = gui
	return bb
end

local function tag(adornee: Instance, color: Color3): (BillboardGui, TextLabel)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 34)
	bb.StudsOffset = Vector3.new(0, 3.6, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = adornee
	local l = UI.label({ Text = "", TextSize = 15, Font = UI.FONT, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3, Size = UDim2.fromScale(1, 1), Parent = bb })
	bb.Parent = gui
	return bb, l
end

------------------------------------------------------------------------
-- the bar
------------------------------------------------------------------------

local function readBinds()
	local s = Settings.Get("cyberKeys")
	local list = typeof(s) == "string" and string.split(s, ",") or {}
	for i = 1, 9 do
		local k = list[i]
		local ok = k ~= nil and pcall(function()
			return (Enum.KeyCode :: any)[k]
		end)
		binds[i] = (ok and k ~= "") and k or Cyberware.DefaultKeys[i]
	end
end

local KEY_NAMES = { One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0" }
local function keyLabel(k: string): string
	return KEY_NAMES[k] or string.upper(k)
end

local function rebuildBar()
	bar = {}
	-- the catalog's order; L before R
	for _, d in Cyberware.List do
		if d.ability then
			for _, key in { d.id, d.id .. "_L", d.id .. "_R" } do
				local t = eff[key]
				if t then
					table.insert(bar, { key = key, id = d.id, def = d, tier = t })
				end
			end
		end
	end
	-- (v2.8) SEVER: an admin power (or a gift), on the same bar
	if Items.Has(player, "sever") then
		table.insert(bar, {
			key = "sever", id = "sever", tier = 1,
			def = { id = "sever", name = "SEVER", ability = "SEVER", cooldown = { Config.SeverCooldown }, tiers = 1 } :: any,
		})
	end
	for _, b in barButtons do
		b:Destroy()
	end
	barButtons = {}
	for i, s in bar do
		if i > 9 then
			break
		end
		local side = string.sub(s.key, -2) == "_L" and " L" or (string.sub(s.key, -2) == "_R" and " R" or "")
		local b = UI.button({
			Name = "Slot" .. i, Text = "", Size = UDim2.fromOffset(66, 50), BackgroundColor3 = PANEL, BackgroundTransparency = 0.15,
			LayoutOrder = i, Parent = barFrame,
		}, function()
			CyberClient.Use(i)
		end)
		UI.make("UIStroke", { Color = RED, Thickness = 1, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
		UI.label({ Name = "Key", Text = keyLabel(binds[i]), TextSize = 13, TextColor3 = RED, Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(30, 14), Parent = b })
		UI.label({ Name = "Name", Text = (s.def.ability or "") .. side, TextSize = 12, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 14), Parent = b })
		UI.label({ Name = "Tier", Text = "T" .. s.tier, TextSize = 10, TextColor3 = C.dim, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 2), Size = UDim2.fromOffset(20, 12), TextXAlignment = Enum.TextXAlignment.Right, Parent = b })
		UI.make("Frame", { Name = "CD", BackgroundColor3 = RED, BackgroundTransparency = 0.55, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(0, 0), Parent = b })
		UI.label({ Name = "State", Text = "", TextSize = 10, TextColor3 = CYAN, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 12), Parent = b })
		table.insert(barButtons, b)
	end
	barFrame.Visible = #bar > 0
end

------------------------------------------------------------------------
-- LOCK (WARDEN OPTICS) and the aim it pulls
------------------------------------------------------------------------

-- (v2.8.1) several locks at once: WARDEN OPTICS holds one per lens (tier 1: one, tier 3: three); SENTRY REFLEX puts a
-- shooter on the list too. `lock` is the one the aim works with: the living locked body nearest the crosshair.
type Lock = { model: Model, hl: Instance, bb: BillboardGui, label: TextLabel, t: number, threat: boolean? }
local locks: { Lock } = {}
local lock: Lock? = nil
local lastLockPress = 0

local function optics(): number
	return Cyberware.Tier(eff, "optics")
end

local function maxLocks(): number
	return math.max(1, optics())
end

local function dropLock(i: number)
	local l = table.remove(locks, i)
	if l then
		l.hl:Destroy()
		l.bb:Destroy()
		if lock == l then
			lock = nil
		end
	end
end

local function clearLock()
	while #locks > 0 do
		dropLock(#locks)
	end
	lock = nil
end

local function lockIndex(m: Model?): number?
	for i, l in locks do
		if l.model == m then
			return i
		end
	end
	return nil
end

local function isLocked(m: Model?): boolean
	return lockIndex(m) ~= nil
end

-- puts a body on the list (the oldest lock goes when the lenses are full)
local function addLock(m: Model, quiet: boolean?)
	if lockIndex(m) then
		return
	end
	while #locks >= maxLocks() do
		dropLock(1)
	end
	local hl = highlight(m, RED, "OpticLock")
	local bb, l = tag(m:FindFirstChild("Head") or m, RED)
	table.insert(locks, { model = m, hl = hl, bb = bb, label = l, t = os.clock() })
	if not quiet then
		SoundLibrary.Play("click", nil, 0.6)
	end
end

-- the lock the aim uses: the living locked body nearest the middle of the screen
local function pickPrimary()
	local ray = camRay()
	local best, bestA = nil, math.huge
	for _, l in locks do
		local tt = torsoOf(l.model)
		if tt and l.model.Parent and l.model:GetAttribute("Dead") ~= true then
			local a = math.acos(math.clamp((tt.Position - ray.Origin).Unit:Dot(ray.Direction), -1, 1))
			if a < bestA then
				best, bestA = l, a
			end
		end
	end
	lock = best
end

local function setLock(m: Model?)
	if not m then
		clearLock()
		return
	end
	local i = lockIndex(m)
	if i then
		dropLock(i)
	else
		addLock(m)
	end
	pickPrimary()
end

-- the hand that holds a SMART gun (nil = none)
local function smartSide(self): string?
	for _, side in { "Right", "Left" } do
		local h = self.hands and self.hands[side]
		local g = h and h.grip
		local gs = g and g.item and Config.Guns[Items.Kind(g.item) or ""]
		if gs and gs.smart then
			return side
		end
	end
	return nil
end

-- (aiming with G) the crosshair point is pulled onto the locked target; a SMART gun follows it always
local origCrosshair = Controller._crosshairPoint
Controller._crosshairPoint = function(self)
	local p = origCrosshair(self)
	local t = optics()
	if t >= 1 and lock and lock.model.Parent and lock.model:GetAttribute("Dead") ~= true and smartSide(self) then
		local tt = torsoOf(lock.model)
		if tt then
			local ray = camRay()
			local a = math.deg(math.acos(math.clamp((tt.Position - ray.Origin).Unit:Dot(ray.Direction), -1, 1)))
			if a < 80 then
				return tt.Position
			end
		end
	end
	if t >= 2 and lock and self.aiming and lock.model.Parent and lock.model:GetAttribute("Dead") ~= true then
		local tt = torsoOf(lock.model)
		if tt then
			local ray = camRay()
			local want = tt.Position - ray.Origin
			local a = math.deg(math.acos(math.clamp(want.Unit:Dot(ray.Direction), -1, 1)))
			if a < (t >= 3 and 50 or 22) then
				return tt.Position
			end
		end
	end
	return p
end

------------------------------------------------------------------------
-- HUNT (HUNTER CORTEX)
------------------------------------------------------------------------

local hunt: { p: Player, hl: Instance?, bb: BillboardGui?, label: TextLabel? }? = nil
local huntArrow: TextLabel

local function refreshHunt()
	local id = player:GetAttribute("CyHunt")
	local p = typeof(id) == "number" and Players:GetPlayerByUserId(id) or nil
	if hunt and (hunt.p ~= p or not hunt.p.Character or (hunt.hl and not ((hunt.hl :: any).Adornee and (hunt.hl :: any).Adornee:IsDescendantOf(hunt.p.Character)))) then
		if hunt.hl then
			hunt.hl:Destroy()
		end
		if hunt.bb then
			hunt.bb:Destroy()
		end
		hunt = nil
	end
	if p and not hunt then
		local h: any = { p = p }
		hunt = h
		local ch = p.Character
		if ch then
			h.hl = highlight(ch, Color3.fromRGB(255, 150, 40), "HuntMark")
			local bb, l = tag(ch:FindFirstChild("Head") or ch, Color3.fromRGB(255, 150, 40))
			h.bb, h.label = bb, l
		end
	end
end

------------------------------------------------------------------------
-- PULL (LODESTONE PALMS): the item your palms lock on
------------------------------------------------------------------------

local magnet: { item: Model?, bb: BillboardGui, label: TextLabel, box: Frame }? = nil

local function magnetPick(): Model?
	local t = Cyberware.Tier(eff, "lodestone")
	if t <= 0 then
		return nil
	end
	local range = Config.LodestoneRange[t]
	local ray = camRay()
	local torso = torsoOf(myChar())
	local props = workspace:FindFirstChild("SpawnedProps")
	if not torso or not props then
		return nil
	end
	local best, bestA = nil, math.rad(14)
	for _, m in props:GetChildren() do
		if m:IsA("Model") and m.PrimaryPart and Items.Kind(m) and m:GetAttribute("StowedBy") == nil and not m:GetAttribute("InSheath") then
			local bound = m:GetAttribute("BoundTo")
			if typeof(bound) == "number" and bound ~= player.UserId then
				continue
			end
			local holder = m:GetAttribute("HolderId")
			local held = typeof(holder) == "number" and holder > 0
			if held and (holder == player.UserId or t < 3 or not Items.IsGun(m)) then
				continue
			end
			local pos = m.PrimaryPart.Position
			if (pos - torso.Position).Magnitude <= range then
				local d = pos - ray.Origin
				local a = math.acos(math.clamp(d.Unit:Dot(ray.Direction), -1, 1))
				if a < bestA then
					best, bestA = m, a
				end
			end
		end
	end
	return best
end

local function updateMagnet()
	local item = magnetPick()
	if not magnet then
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(150, 70)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.Enabled = false
		local box = UI.make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(44, 44), Parent = bb })
		UI.make("UIStroke", { Color = CYAN, Thickness = 2, Parent = box })
		local l = UI.label({ Text = "", TextSize = 13, TextColor3 = CYAN, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3, Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 0, 18), Parent = bb })
		bb.Parent = gui
		magnet = { item = nil, bb = bb, label = l, box = box }
	end
	local mg = magnet :: any
	mg.item = item
	if item and item.PrimaryPart then
		local k = Items.Kinds[Items.Kind(item) or ""]
		local torso = torsoOf(myChar())
		local dist = torso and math.floor((item.PrimaryPart.Position - torso.Position).Magnitude) or 0
		mg.bb.Adornee = item.PrimaryPart
		mg.bb.Enabled = true
		local held = typeof(item:GetAttribute("HolderId")) == "number"
		mg.label.Text = "LOCKED: " .. (k and k.name or "ITEM") .. "  " .. dist .. "m" .. (held and "  (HELD)" or "")
	else
		mg.bb.Enabled = false
	end
end

------------------------------------------------------------------------
-- using a slot
------------------------------------------------------------------------

local function muzzleOf(key: string): Vector3?
	local ch = myChar()
	local arm = ch and ch:FindFirstChild(string.sub(key, -1) == "L" and "Left Arm" or "Right Arm")
	if not arm or not arm:IsA("BasePart") then
		return nil
	end
	local s = ch:GetAttribute("BodyScale")
	s = typeof(s) == "number" and s or 1
	return (arm.CFrame * CFrame.new(0, -1.4 * s, 0)).Position
end

local function aimPoint(): Vector3
	if controller and controller.ready then
		return controller:_crosshairPoint()
	end
	local r = camRay()
	return r.Origin + r.Direction * 200
end

local redOn = false
function CyberClient.Use(i: number)
	local s = bar[i]
	if not s or not controller or not controller.ready or controller.dead then
		return
	end
	local ch = myChar()
	if not ch or ch:GetAttribute("CrashOut") or ch:GetAttribute("CyFrozen") then
		return
	end
	local cdUntil = player:GetAttribute("CyCD_" .. s.key)
	if s.id ~= "optics" and typeof(cdUntil) == "number" and now() < cdUntil - 0.05 then
		SoundLibrary.Play("dryfire", nil, 0.3)
		return
	end
	if s.id == "sever" then
		local cam = workspace.CurrentCamera
		Remote:FireServer("sever", cam.CFrame.Position, cam.CFrame.LookVector, cam.CFrame.RightVector)
		-- the slash across your screen
		local line = UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 0, 0, 3), ZIndex = 45, Parent = gui })
		TweenService:Create(line, TweenInfo.new(0.12), { Size = UDim2.new(1.2, 0, 0, 3) }):Play()
		TweenService:Create(line, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.12), { BackgroundTransparency = 1 }):Play()
		Debris:AddItem(line, 0.6)
		return
	end
	if s.id == "optics" then
		local t = os.clock()
		-- tier 3: a double tap switches the red combat vision
		if s.tier >= 3 and t - lastLockPress < 0.35 then
			redOn = not redOn
			toast(redOn and "COMBAT VISION ON (FIRST PERSON)" or "COMBAT VISION OFF", RED)
			lastLockPress = 0
			return
		end
		lastLockPress = t
		-- (v2.8.1) at a body: lock it (or let it go if it is locked); at nothing: every lock off
		local m = bodyAtCrosshair(500, 6)
		local was = m ~= nil and isLocked(m)
		setLock(m)
		if not m then
			toast("ALL LOCKS OFF", RED)
		elseif was then
			toast("LOCK OFF", RED)
		else
			toast(string.format("LOCKED  %d / %d", #locks, maxLocks()), RED)
		end
	elseif s.id == "cortex" then
		local m = bodyAtCrosshair(800, 8)
		local p = m and Players:GetPlayerFromCharacter(m)
		if p then
			Remote:FireServer("ab", s.key, p)
		else
			toast("NOBODY THERE - AIM AT A PERSON", RED)
		end
	elseif s.id == "howler" then
		local from = muzzleOf(s.key) or (torsoOf(ch) :: BasePart).Position
		Remote:FireServer("ab", s.key, (aimPoint() - from).Unit)
	elseif s.id == "lodestone" then
		local item = magnet and magnet.item
		if item then
			Remote:FireServer("ab", s.key, item)
		else
			toast("NOTHING LOCKED - LOOK AT AN ITEM", CYAN)
		end
	else
		Remote:FireServer("ab", s.key)
	end
end

-- the SHIFTGUN fires with F while it is open and its hand is empty
local firing = false
-- (v2.8.1) every SHIFTGUN that is out with its hand empty: both arms fire together
local function armGunKeys(): { string }
	local out = {}
	local ch = myChar()
	if not ch or not controller then
		return out
	end
	for _, side in { "R", "L" } do
		local key = "shiftgun_" .. side
		local hand = controller.hands and controller.hands[side == "R" and "Right" or "Left"]
		if eff[key] and ch:GetAttribute("Cy_open_" .. key) and hand and not hand.grip then
			table.insert(out, key)
		end
	end
	return out
end

local function armGunKey(): string?
	return armGunKeys()[1]
end

-- (v2.8.1) the SHIFTGUN's magazine: reloading right now?
local function armReloading(key: string): boolean
	local r = player:GetAttribute("CyReload_" .. key)
	return typeof(r) == "number" and workspace:GetServerTimeNow() < r
end

-- (v2.8.1) SMART arm guns: they aim at the locked target nearest the crosshair (if it is in front of you), else at the
-- crosshair; during a return burst at the shooter
local armTarget: { model: Model, untilT: number }? = nil
local function armAimAt(): Vector3
	if armTarget and os.clock() < armTarget.untilT and armTarget.model.Parent then
		local tt = torsoOf(armTarget.model)
		if tt then
			return tt.Position
		end
	end
	if lock and lock.model.Parent and lock.model:GetAttribute("Dead") ~= true then
		local tt = torsoOf(lock.model)
		if tt then
			local ray = camRay()
			local a = math.deg(math.acos(math.clamp((tt.Position - ray.Origin).Unit:Dot(ray.Direction), -1, 1)))
			if a < 70 then
				return tt.Position
			end
		end
	end
	return aimPoint()
end

-- (v2.8.2) the arm's own mouse button held (LMB = left arm, RMB = right arm): that arm gun follows the MOUSE (the
-- crosshair), not the lock - you aim it yourself
local function manualArm(side: string): boolean
	if side == "L" or side == "Left" then
		return Input.mouseLeft == true
	end
	return Input.mouseRight == true
end

local function shootArm(key: string)
	local ch = myChar()
	local s = ch and ch:GetAttribute("BodyScale")
	s = typeof(s) == "number" and s or 1
	local arm = ch and ch:FindFirstChild(string.sub(key, -1) == "L" and "Left Arm" or "Right Arm")
	if not arm or not arm:IsA("BasePart") then
		return
	end
	local from = (arm.CFrame * CFrame.new(0, -2.65 * s, 0)).Position
	-- aimed by hand (its mouse button): straight out of the muzzle, where the arm points; else the smart aim
	local dir = manualArm(string.sub(key, -1)) and -arm.CFrame.UpVector * 100 or (armAimAt() - from)
	if dir.Magnitude > 0.1 then
		Remote:FireServer("armshot", key, dir.Unit)
	end
end

local function cyberFire(): boolean
	if #armGunKeys() == 0 then
		return false
	end
	if firing then
		return true
	end
	firing = true
	task.spawn(function()
		local t = Cyberware.Tier(eff, "shiftgun")
		local first = true
		repeat
			local any = false
			for _, key in armGunKeys() do
				if not armReloading(key) then
					shootArm(key)
					any = true
				end
			end
			if not any then
				if first then
					SoundLibrary.Play("dryfire", nil, 0.3)
				end
				break
			end
			first = false
			task.wait(Config.ShiftgunRate[math.max(1, t)])
		until not Input.useHeld or #armGunKeys() == 0 or t < 3
		firing = false
	end)
	return true
end

-- (v2.8.2) THREAT: whoever shot at you (the SENTRY / the arm guns saw it) is marked THREAT over the head, in the lock
-- frame, for a while; the smart guns go for them
local function markThreat(m: Model)
	if not m or not m.Parent then
		return
	end
	local i = lockIndex(m)
	if not i then
		addLock(m, true)
		i = lockIndex(m)
	end
	local l = i and locks[i]
	if l then
		l.threat = true
		l.t = os.clock()
	end
	pickPrimary()
	toast("THREAT IDENTIFIED", RED)
end

-- (v2.8.1) somebody shoots at you while an arm gun is out: it fires back at them on its own (a short burst)
local lastReturnFire = 0
local function returnFire(shooter: Model)
	if os.clock() - lastReturnFire < 1.5 or #armGunKeys() == 0 or not controller or controller.dead then
		return
	end
	local ch = myChar()
	if ch and (ch:GetAttribute("CrashOut") or ch:GetAttribute("CyFrozen")) then
		return
	end
	lastReturnFire = os.clock()
	markThreat(shooter) -- (v2.8.2) the one who shot at you is marked THREAT (and locked: the smart guns go for them)
	armTarget = { model = shooter, untilT = os.clock() + 0.9 }
	task.spawn(function()
		task.wait(0.15) -- (the arm comes round first)
		for _ = 1, 3 do
			if not shooter.Parent or shooter:GetAttribute("Dead") then
				break
			end
			for _, key in armGunKeys() do
				if not armReloading(key) then
					shootArm(key)
				end
			end
			task.wait(0.14)
		end
	end)
end

------------------------------------------------------------------------
-- SENTRY REFLEX, crash outs, the cloak, the ice, psychosis
------------------------------------------------------------------------

local threat: { origin: Vector3, untilT: number, tier: number }? = nil
local threatMark: TextLabel
-- (v2.8.1) SENTRY REFLEX: the camera swings onto the shooter; one shot back when they were locked already
local camTurn: { yaw: number, pitch: number, t0: number, y0: number, p0: number }? = nil
local autoShot: { side: string, target: Model, at: number, fired: boolean }? = nil
local lastAutoShot = 0

Input.ArmAimHook = function(self, side: string, shoulder: Vector3, _heading: CFrame): (Vector3?, boolean?)
	-- the auto shot: the gun hand points at the locked shooter
	if autoShot and autoShot.side == side and os.clock() < autoShot.at + 0.4 then
		local tt = torsoOf(autoShot.target)
		if tt then
			return (tt.Position - shoulder).Unit, true
		end
	end
	-- the SHIFTGUN out and its hand empty: the arm comes up like holding a gun (at the locked target / the shooter if any)
	do
		local key = "shiftgun_" .. (side == "Left" and "L" or "R")
		local ch = self.character
		local hand = self.hands and self.hands[side]
		if eff[key] and ch and ch:GetAttribute("Cy_open_" .. key) and hand and not hand.grip and not ch:GetAttribute("CrashOut") then
			if manualArm(side) then
				return nil, nil -- (v2.8.2) its mouse button is held: the arm follows the mouse like a hand does
			end
			local target = armAimAt()
			return MathUtil.SafeUnit(target - shoulder, _heading.LookVector), true
		end
	end
	-- SENTRY REFLEX tier 3: the hand with a gun snaps to the shooter
	if threat and threat.tier >= 3 and os.clock() < threat.untilT then
		local hand = self.hands and self.hands[side]
		if hand and hand.grip and hand.grip.item and Items.IsGun(hand.grip.item) then
			return (threat.origin - shoulder).Unit, true
		end
	end
	-- a crash out: every arm with a gun points at the target
	local ct = CyberClient.crashTarget
	if ct and ct.Parent then
		local hand = self.hands and self.hands[side]
		local tt = torsoOf(ct)
		if tt and hand and hand.grip then
			return (tt.Position - shoulder).Unit, true
		end
	end
	return nil, nil
end

local function crashOut(dur: number)
	toast("CRASH OUT", RED)
	SoundLibrary.Play("heartbeat", nil, 1)
	local o = overlay
	o.BackgroundColor3 = Color3.fromRGB(160, 0, 0)
	o.BackgroundTransparency = 0.55
	TweenService:Create(o, TweenInfo.new(dur, Enum.EasingStyle.Linear), { BackgroundTransparency = 1 }):Play()
	Hallucinations.Force(dur + 4, 1)
	-- ControlService supplies the single authoritative movement/aim directive.

end

-- cloaked bodies: nearly invisible for everyone else, see-through for yourself
local cloakItems: { [Player]: { [Model]: boolean } } = {}
local function updateCloaks()
	local t = now()
	for _, p in Players:GetPlayers() do
		local ch = p.Character
		if ch then
			local c = ch:GetAttribute("Cloaked")
			local rev = ch:GetAttribute("CloakReveal")
			local on = typeof(c) == "number" and t < c and not (typeof(rev) == "number" and t < rev)
			local was = ch:GetAttribute("CloakSeen") == true
			if on or was then
				-- (v2.8.1) fully invisible for everybody else (the body, its face, its chrome, what it holds, its blood
				-- trail lights); see-through for yourself so you still know where your arms are
				local k = on and (p == player and 0.6 or 1) or 0
				local function fade(root: Instance)
					for _, d in root:GetDescendants() do
						if d:IsA("BasePart") or d:IsA("Decal") then
							if p ~= player or not Input.firstPerson then
								(d :: any).LocalTransparencyModifier = k
							end
						elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("Highlight") or d:IsA("ParticleEmitter") or d:IsA("Light") then
							if p ~= player then
								if on then
									if d:GetAttribute("CloakWas") == nil then
										d:SetAttribute("CloakWas", (d :: any).Enabled)
									end
									(d :: any).Enabled = false
								elseif d:GetAttribute("CloakWas") ~= nil then
									(d :: any).Enabled = d:GetAttribute("CloakWas") == true
									d:SetAttribute("CloakWas", nil)
								end
							end
						end
					end
				end
				fade(ch)
				-- the items in its hands / pockets (one it lets go of shows again at once)
				local mine = cloakItems[p] or {}
				cloakItems[p] = mine
				local props = workspace:FindFirstChild("SpawnedProps")
				for _, m in (props and props:GetChildren() or {}) do
					if on and (m:GetAttribute("HolderId") == p.UserId or m:GetAttribute("StowedBy") == p.UserId) then
						mine[m] = true
					end
				end
				for m in mine do
					local still = on and m.Parent ~= nil and (m:GetAttribute("HolderId") == p.UserId or m:GetAttribute("StowedBy") == p.UserId)
					if still then
						fade(m)
					else
						local kk = k
						k = 0
						fade(m)
						k = kk
						mine[m] = nil
					end
				end
				ch:SetAttribute("CloakSeen", on or nil)
			end
		end
	end
end

local nextEpisode = os.clock() + 25
local function updatePsycho()
	local v = player:GetAttribute("CyPsycho")
	local ps = typeof(v) == "number" and v or 0
	psychoFill.Size = UDim2.fromScale(math.clamp(ps, 0, 1), 1)
	psychoText.Text = string.format("PSYCHOSIS %d%%", math.floor(ps * 100))
	if ps > 0.12 and os.clock() > nextEpisode and Settings.Get("hallucinations") ~= false then
		nextEpisode = os.clock() + rng:NextNumber(18, 50) * (1.3 - ps)
		Hallucinations.Force(6 + 18 * ps, math.clamp(ps, 0.15, 1))
	end
end

------------------------------------------------------------------------
-- effects the server sends
------------------------------------------------------------------------

local howlerShell: (any) -> () -- (v2.8.2, below)
local function flash(pos: Vector3, color: Color3, size: number, life: number)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.one * size
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace:FindFirstChild("FX") or workspace
	TweenService:Create(p, TweenInfo.new(life), { Transparency = 1, Size = Vector3.one * size * 1.8 }):Play()
	Debris:AddItem(p, life + 0.05)
	return p
end

-- (v2.8.1) AEGIS: a hit on the field. A hexagon-skinned bubble flashes round the body (brighter the fuller it is), a ripple
-- spreads from where the hit landed, small shards spark off it; the last hit breaks it: the bubble shatters into pieces.
local REGION_PART = { Head = "Head", Torso = "Torso", LeftArm = "Left Arm", RightArm = "Right Arm", LeftLeg = "Left Leg", RightLeg = "Right Leg" }
local function fxPart(shape: Enum.PartType?, mat: Enum.Material, color: Color3, size: Vector3, cf: CFrame): Part
	local p = Instance.new("Part")
	if shape then
		p.Shape = shape
	end
	p.Material = mat
	p.Color = color
	p.Size = size
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.CFrame = cf
	p.Parent = workspace:FindFirstChild("FX") or workspace
	return p
end

local function shieldFX(ch: Model, tt: BasePart, region: any, left: number, max: number, k: number)
	local blue = Color3.fromRGB(90, 190, 255)
	local full = math.clamp(left / math.max(1, max), 0, 1)
	local R = 3.3 * k
	-- the bubble: two shells (a hex-like force field and a faint glass skin), they swell and fade
	local shell = fxPart(Enum.PartType.Ball, Enum.Material.ForceField, blue, Vector3.one * R * 2, tt.CFrame)
	local skin = fxPart(Enum.PartType.Ball, Enum.Material.Glass, Color3.fromRGB(150, 220, 255), Vector3.one * R * 2.02, tt.CFrame)
	skin.Transparency = 0.82
	local life = 0.38
	TweenService:Create(shell, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * R * 2.15, Transparency = 1 }):Play()
	TweenService:Create(skin, TweenInfo.new(life), { Size = Vector3.one * R * 2.2, Transparency = 1 }):Play()
	-- the bubble follows the body while it fades
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if os.clock() - t0 > life or not tt.Parent then
			conn:Disconnect()
			return
		end
		shell.CFrame = tt.CFrame
		skin.CFrame = tt.CFrame
	end)
	Debris:AddItem(shell, life + 0.05)
	Debris:AddItem(skin, life + 0.05)
	-- where it was hit: a ripple on the surface, sparks off it
	local hitPart = typeof(region) == "string" and ch:FindFirstChild(REGION_PART[region] or "") or nil
	local dir = (hitPart and hitPart:IsA("BasePart") and (hitPart.Position - tt.Position).Magnitude > 0.2) and (hitPart.Position - tt.Position).Unit
		or (workspace.CurrentCamera.CFrame.Position - tt.Position).Unit
	local at = tt.Position + dir * R
	local ring = fxPart(Enum.PartType.Cylinder, Enum.Material.Neon, Color3.fromRGB(200, 240, 255), Vector3.new(0.05, 0.6 * k, 0.6 * k),
		CFrame.lookAt(at, at + dir) * CFrame.Angles(0, math.rad(90), 0))
	TweenService:Create(ring, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, 3.2 * k, 3.2 * k), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.35)
	for _ = 1, 6 do
		local sp = fxPart(nil, Enum.Material.Neon, blue, Vector3.new(0.12, 0.12, 0.5) * k, CFrame.lookAt(at, at + dir))
		local spread = (dir + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * 0.9).Unit
		TweenService:Create(sp, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.lookAt(at + spread * 2.2 * k, at + spread * 3 * k), Transparency = 1, Size = Vector3.new(0.04, 0.04, 0.2) * k }):Play()
		Debris:AddItem(sp, 0.32)
	end
	shell.Transparency = 0.15 + (1 - full) * 0.5
	-- broken: the field shatters
	if left <= 0 then
		SoundLibrary.Play("glass", tt, 1)
		for _ = 1, 26 do
			local d = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.6, 1), rng:NextNumber(-1, 1)).Unit
			local from = tt.Position + d * R
			local shard = fxPart(nil, Enum.Material.Glass, Color3.fromRGB(140, 210, 255), Vector3.new(rng:NextNumber(0.3, 0.8), 0.05, rng:NextNumber(0.3, 0.8)) * k,
				CFrame.lookAt(from, from + d) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0))
			shard.Transparency = 0.3
			local to = from + d * rng:NextNumber(3, 6) * k + Vector3.new(0, -rng:NextNumber(1, 4), 0)
			TweenService:Create(shard, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ CFrame = CFrame.new(to) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)), Transparency = 1 }):Play()
			Debris:AddItem(shard, 0.85)
		end
		flash(tt.Position, Color3.fromRGB(200, 235, 255), 2 * k, 0.25)
	end
end

-- a jagged electric arc between two points
-- (v2.8.2) the HOWLER's shell as you see it: a cased round (a metal body, a glowing nose in the shell's colour, fins),
-- a bright tail behind it, smoke and a light; it flies the same way the server's shell does (the same speed and drop,
-- slowed by the Sandevistan, stopped by a time stop) and is gone where it hits
howlerShell = function(d: any)
	local col: Color3 = typeof(d.c) == "Color3" and d.c or RED
	local dir = (d.d :: Vector3).Unit
	local speed = tonumber(d.v) or 190
	local k = (0.8 + (tonumber(d.tier) or 1) * 0.2) * (tonumber(d.s) or 1)
	local slug = d.shell == "SLUG"
	local m = Instance.new("Model")
	m.Name = "HowlerShellFX"
	local function piece(name: string, size: Vector3, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * k
		p.Color = color
		p.Material = mat
		if shape then
			p.Shape = shape
		end
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Parent = m
		return p
	end
	-- (the shell's length runs along its X axis)
	local body = piece("Casing", Vector3.new(slug and 0.9 or 1.2, 0.42, 0.42), Color3.fromRGB(70, 72, 78), Enum.Material.Metal, Enum.PartType.Cylinder)
	body.Reflectance = 0.3
	local band = piece("Band", Vector3.new(0.12, 0.46, 0.46), Color3.fromRGB(190, 160, 80), Enum.Material.Metal, Enum.PartType.Cylinder)
	local nose = piece("Nose", Vector3.new(0.44, 0.44, 0.44), col, Enum.Material.Neon, Enum.PartType.Ball)
	local fins = {}
	for i = 1, 4 do
		fins[i] = piece("Fin", Vector3.new(0.3, 0.05, 0.3), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
	end
	local glow = piece("Tail", Vector3.new(0.5, 0.3, 0.3), col:Lerp(Color3.new(1, 1, 1), 0.4), Enum.Material.Neon, Enum.PartType.Ball)
	glow.Transparency = 0.2
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.18 * k, 0)
	a0.Parent = glow
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.18 * k, 0)
	a1.Parent = glow
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = slug and 0.12 or 0.35
	trail.Color = ColorSequence.new(col:Lerp(Color3.new(1, 1, 1), 0.5), col)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.LightEmission = 1
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail.Parent = glow
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Rate = slug and 0 or 60
	smoke.Lifetime = NumberRange.new(0.5, 0.9)
	smoke.Speed = NumberRange.new(0.5, 2)
	smoke.SpreadAngle = Vector2.new(15, 15)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 * k), NumberSequenceKeypoint.new(1, 2.2 * k) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	smoke.Color = ColorSequence.new(Color3.fromRGB(110, 106, 102))
	smoke.Parent = glow
	local light = Instance.new("PointLight")
	light.Color = col
	light.Range = 12
	light.Brightness = 2.5
	light.Parent = nose
	m.Parent = workspace:FindFirstChild("FX") or workspace
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { m }
	if typeof(d.ig) == "Instance" then
		table.insert(ignore, d.ig)
	end
	local fxf = workspace:FindFirstChild("FX")
	if fxf then
		table.insert(ignore, fxf)
	end
	params.FilterDescendantsInstances = ignore
	local pos: Vector3 = d.p
	local vel = dir * speed
	local flown, spin = 0, 0
	local function place(at: Vector3, v: Vector3)
		local f = v.Magnitude > 0.1 and v.Unit or dir
		-- a frame whose X axis runs along the flight (nose in front)
		local look = CFrame.lookAt(at, at + f) * CFrame.Angles(0, math.rad(90), 0)
		local cf = look * CFrame.Angles(spin, 0, 0)
		body.CFrame = cf
		-- (+X is forward: the nose in front, the band, fins and the glowing tail behind)
		band.CFrame = cf * CFrame.new(-0.2 * k, 0, 0)
		nose.CFrame = cf * CFrame.new(0.62 * k, 0, 0)
		glow.CFrame = cf * CFrame.new(-0.72 * k, 0, 0)
		for i, fn in fins do
			fn.CFrame = cf * CFrame.new(-0.55 * k, 0, 0) * CFrame.Angles(i * math.pi / 2, 0, 0) * CFrame.new(0, 0.28 * k, 0)
		end
	end
	place(pos, vel)
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		if not m.Parent then
			conn:Disconnect()
			return
		end
		if workspace:GetAttribute("TimeStop") then
			return
		end
		dt *= TimeScale.Get()
		if not slug then
			vel += Vector3.new(0, -TimeScale.Gravity() * 0.08, 0) * dt
		end
		local step = vel * dt
		local hit = workspace:Raycast(pos, step, params)
		flown += step.Magnitude
		spin += dt * 18
		if hit or flown > 900 then
			conn:Disconnect()
			smoke.Rate = 0
			for _, c in m:GetChildren() do
				if c:IsA("BasePart") and c ~= glow then
					c:Destroy()
				end
			end
			glow.Transparency = 1
			Debris:AddItem(m, 1)
			return
		end
		pos += step
		place(pos, vel)
	end)
end

local function arc(a: Vector3, b: Vector3, color: Color3, life: number)
	local n = 6
	local prev = a
	for i = 1, n do
		local t = i / n
		local nxt = a:Lerp(b, t)
		if i < n then
			nxt += Vector3.new(rng:NextNumber(-0.6, 0.6), rng:NextNumber(-0.6, 0.6), rng:NextNumber(-0.6, 0.6))
		end
		local len = (nxt - prev).Magnitude
		local seg = Instance.new("Part")
		seg.Material = Enum.Material.Neon
		seg.Color = color
		seg.Size = Vector3.new(0.08, 0.08, len)
		seg.Anchored, seg.CanCollide, seg.CanQuery, seg.CanTouch, seg.CastShadow = true, false, false, false, false
		seg.CFrame = CFrame.lookAt((prev + nxt) / 2, nxt)
		seg.Parent = workspace:FindFirstChild("FX") or workspace
		TweenService:Create(seg, TweenInfo.new(life), { Transparency = 1 }):Play()
		Debris:AddItem(seg, life + 0.05)
		prev = nxt
	end
end

local function charOf(userId: any): Model?
	local p = typeof(userId) == "number" and Players:GetPlayerByUserId(userId) or nil
	return p and p.Character or nil
end

local function onFx(d: any)
	if typeof(d) ~= "table" then
		return
	end
	local t = d.t
	if t == "cannon" and typeof(d.p) == "Vector3" then
		flash(d.p, typeof(d.c) == "Color3" and d.c or RED, 1.6, 0.2)
		if typeof(d.d) == "Vector3" then
			howlerShell(d)
		end
	elseif t == "shock" and typeof(d.p) == "Vector3" then
		for _ = 1, 7 do
			local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 1), rng:NextNumber(-1, 1)).Unit
			arc(d.p, d.p + dir * (d.r or 5), Color3.fromRGB(120, 200, 255), 0.25)
		end
		flash(d.p, Color3.fromRGB(150, 220, 255), 2, 0.25)
	elseif t == "zap" and typeof(d.a) == "Vector3" and typeof(d.b) == "Vector3" then
		for _ = 1, 3 do
			arc(d.a, d.b, Color3.fromRGB(110, 190, 255), 0.22)
		end
	elseif t == "shield" then
		local ch = charOf(d.by)
		local tt = torsoOf(ch)
		if tt and ch then
			local s = ch:GetAttribute("BodyScale")
			local k = typeof(s) == "number" and s or 1
			shieldFX(ch, tt, d.r, tonumber(d.left) or 0, tonumber(d.max) or 100, k)
		end
		if d.by == player.UserId then
			overlay.BackgroundColor3 = Color3.fromRGB(60, 140, 255)
			overlay.BackgroundTransparency = 0.8
			TweenService:Create(overlay, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			if (d.left or 0) <= 0 then
				toast("SHIELD DOWN", RED)
			end
		end
	elseif t == "shieldat" and typeof(d.p) == "Vector3" then
		local b = flash(d.p, Color3.fromRGB(90, 190, 255), 5.5, 0.3)
		b.Material = Enum.Material.ForceField
	elseif t == "poof" and typeof(d.p) == "Vector3" then
		flash(d.p, Color3.fromRGB(255, 220, 160), 0.6, 0.12)
	elseif t == "spark" and typeof(d.p) == "Vector3" then
		flash(d.p, Color3.fromRGB(255, 200, 120), 0.8, 0.15)
	elseif t == "armshot" then
		local ch = charOf(d.by)
		local arm = ch and ch:FindFirstChild(string.sub(d.k or "", -1) == "L" and "Left Arm" or "Right Arm")
		if arm and arm:IsA("BasePart") then
			local s = ch:GetAttribute("BodyScale")
			s = typeof(s) == "number" and s or 1
			local p = (arm.CFrame * CFrame.new(0, -2.7 * s, 0)).Position
			flash(p, Color3.fromRGB(255, 210, 120), 0.5, 0.06)
			SoundLibrary.Play("gunshot", p, 0.8)
		end
	elseif t == "armreload" then
		local ch = charOf(d.by)
		local arm = ch and ch:FindFirstChild(string.sub(d.k or "", -1) == "L" and "Left Arm" or "Right Arm")
		if arm and arm:IsA("BasePart") then
			SoundLibrary.Play("magOut", arm, 0.9)
			task.delay(math.max(0.3, (tonumber(d.t) or 1.4) - 0.3), function()
				if arm.Parent then
					SoundLibrary.Play("magIn", arm, 1)
				end
			end)
		end
		if d.by == player.UserId then
			toast("ARM GUN RELOADING", CYAN)
		end
	elseif t == "toggle" then
		local ch = charOf(d.by)
		SoundLibrary.Play("ratchet", torsoOf(ch), 0.9)
	elseif t == "pull" and typeof(d.item) == "Instance" then
		local ch = charOf(d.by)
		local tt = torsoOf(ch)
		local item = d.item :: Model
		if tt and item.PrimaryPart then
			arc(tt.Position, item.PrimaryPart.Position, CYAN, 0.4)
		end
	elseif t == "cloak" then
		local ch = charOf(d.by)
		local tt = torsoOf(ch)
		if tt then
			local b = flash(tt.Position, Color3.fromRGB(200, 230, 255), 6, 0.5)
			b.Material = Enum.Material.Glass
		end
	elseif t == "sever" and typeof(d.p) == "Vector3" and typeof(d.l) == "Vector3" and typeof(d.r) == "Vector3" then
		local n = d.l:Cross(d.r).Unit
		local plane = Instance.new("Part")
		plane.Material = Enum.Material.Neon
		plane.Color = Color3.fromRGB(255, 255, 255)
		plane.Size = Vector3.new(60, 0.05, 140)
		plane.Anchored, plane.CanCollide, plane.CanQuery, plane.CanTouch, plane.CastShadow = true, false, false, false, false
		plane.CFrame = CFrame.fromMatrix(d.p + d.l * 72, d.r, n)
		plane.Transparency = 0.35
		plane.Parent = workspace:FindFirstChild("FX") or workspace
		TweenService:Create(plane, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		Debris:AddItem(plane, 0.35)
		SoundLibrary.Play("slash", d.p, 1)
	elseif t == "freeze" then
		overlay.BackgroundColor3 = Color3.fromRGB(200, 235, 255)
		overlay.BackgroundTransparency = 0.3
		TweenService:Create(overlay, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
		SoundLibrary.Play("glass", nil, 1)
	end
end

------------------------------------------------------------------------
-- the ripperdoc: shop, list, turn, dream, TV, board, picker
------------------------------------------------------------------------

local shop: Frame
local shopRefresh: (() -> ())? = nil
local cart: { any } = {}
local turnBeam: Beam? = nil
local turnA0: Attachment?
local turnUntil = 0

local function closeShop()
	if shop then
		shop.Visible = false
	end
	Input.freeCursor = false
end

local function cashNow(): number
	local c = player:GetAttribute("Cash")
	return typeof(c) == "number" and c or 0
end

local function myList(): { [string]: number }
	return Cyberware.Decode(player:GetAttribute("Cyber"))
end

local function cartTotal(): (number, number)
	local list = myList()
	local total = 0
	for _, o in cart do
		if o.op == "out" then
			local id = Cyberware.Split(o.key)
			total += math.floor(Cyberware.Price(id, list[o.key] or 1) * Config.CyberRemoveShare)
			list[o.key] = nil
		end
	end
	for _, o in cart do
		if o.op == "in" then
			local key = Cyberware.Key(o.id, o.side)
			local had = list[key] or 0
			total += Cyberware.Price(o.id, o.tier) - (had > 0 and Cyberware.Price(o.id, had) or 0)
			list[key] = o.tier
		end
	end
	return total, Cyberware.Load(list)
end

-- (v2.8.1) THE CLINIC'S FRONT DESK, redrawn: no three grey boxes any more. A grimy terminal under a red neon sign:
--   * left: the BODY CHART - a blocky body with a socket for every slot (cyan = chrome in you, red = on your slip).
--     Click a socket: what fits there.
--   * middle: the SPEC SHEET of the implant (its tiers as a ladder, the side, put in / take out / buy in a case)
--   * right: the INTAKE SLIP - a paper ticket: what the doc does, the total, the load meter with your limit on it, your
--     number on the waiting list (like a deli counter), sign the list / tear it up; kits and syringes under it
local INK = Color3.fromRGB(34, 30, 28)
local PAPER = Color3.fromRGB(226, 219, 199)
local GRIME = Color3.fromRGB(14, 13, 15)
local STEEL = Color3.fromRGB(46, 46, 52)

-- where every slot's socket sits on the chart (offsets inside a 230 x 330 figure)
local SOCKETS: { [string]: Vector2 } = {
	brain = Vector2.new(115, 14), eyes = Vector2.new(103, 34), ears = Vector2.new(139, 34), os = Vector2.new(115, 62),
	spine = Vector2.new(115, 84), chest = Vector2.new(96, 104), blood = Vector2.new(134, 104), lungs = Vector2.new(96, 128),
	frame = Vector2.new(134, 128), nerves = Vector2.new(115, 150), skin = Vector2.new(80, 168), dermis = Vector2.new(115, 172),
	subdermal = Vector2.new(150, 168),
	arm_L = Vector2.new(40, 96), arm_R = Vector2.new(190, 96), fore_L = Vector2.new(40, 140), fore_R = Vector2.new(190, 140),
	palms = Vector2.new(190, 172),
	legs = Vector2.new(96, 250), marrow = Vector2.new(134, 250), core = Vector2.new(115, 304),
	stance = Vector2.new(96, 208), shell = Vector2.new(134, 208), -- (v2.8.2)
}
local SOCKET_CODE: { [string]: string } = {
	brain = "CX", eyes = "OP", ears = "EA", os = "OS", spine = "SP", chest = "CH", blood = "HR", lungs = "LU", frame = "SK",
	nerves = "NV", skin = "SN", dermis = "DM", subdermal = "SD", arm = "AR", fore = "FA", palms = "PA", legs = "LG",
	marrow = "MW", core = "PR", stance = "ST", shell = "AS",
}

local function buildShop()
	shop = UI.make("Frame", {
		Name = "Ripperdoc", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(780, 520),
		BackgroundColor3 = GRIME, BackgroundTransparency = 0.02, BorderSizePixel = 0, Visible = false, ClipsDescendants = true, Parent = gui,
	})
	UI.make("UIStroke", { Color = Color3.fromRGB(70, 20, 26), Thickness = 3, Parent = shop })
	local scale = UI.make("UIScale", { Name = "Scale", Parent = shop })
	scale:SetAttribute("Managed", true)
	local function fit()
		local cam = workspace.CurrentCamera
		local vs = cam and cam.ViewportSize or Vector2.new(1280, 720)
		scale.Scale = math.max(0.45, math.min(1, (vs.X - 20) / 780, (vs.Y - 20) / 520)) * UI.Global()
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	-- the terminal's scanlines and a dirty vignette (under everything)
	for i = 0, 51 do
		UI.make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.975, BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, i * 10), Size = UDim2.new(1, 0, 0, 1), ZIndex = 1, Parent = shop })
	end
	-- the sign: red neon letters on a black board, with two bolts; one letter flickers
	local sign = UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(6, 6, 8), BorderSizePixel = 0, Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(420, 40), ZIndex = 2, Parent = shop })
	UI.make("UIStroke", { Color = Color3.fromRGB(40, 40, 46), Thickness = 2, Parent = sign })
	for _, bx in { 6, 408 } do
		UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(120, 120, 128), BorderSizePixel = 0, Position = UDim2.fromOffset(bx, 17), Size = UDim2.fromOffset(6, 6), ZIndex = 3, Parent = sign })
	end
	local signText = UI.label({ Text = string.upper(Config.RipperDocName) .. "  CHROME CLINIC", TextSize = 24, TextColor3 = Color3.fromRGB(255, 70, 80),
		TextStrokeColor3 = Color3.fromRGB(255, 0, 30), TextStrokeTransparency = 0.55, TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = sign })
	task.spawn(function()
		while shop and shop.Parent do
			task.wait(math.random() * 3 + 0.6)
			if shop.Visible then
				signText.TextTransparency = 0.6
				task.wait(0.06)
				signText.TextTransparency = 0
				task.wait(0.05)
				signText.TextTransparency = 0.45
				task.wait(0.08)
				signText.TextTransparency = 0
			end
		end
	end)
	UI.label({ Text = "FRONT DESK  -  NO REFUNDS  -  NO QUESTIONS", TextSize = 11, TextColor3 = Color3.fromRGB(150, 140, 120), Position = UDim2.fromOffset(446, 12), Size = UDim2.fromOffset(240, 14), ZIndex = 2, Parent = shop })
	local cashL = UI.label({ Text = "", TextSize = 18, TextColor3 = C.amber, Position = UDim2.fromOffset(446, 28), Size = UDim2.fromOffset(240, 22), ZIndex = 2, Parent = shop })
	UI.button({ Text = "CLOSE", TextSize = 12, Size = UDim2.fromOffset(64, 26), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 14), BackgroundColor3 = Color3.fromRGB(120, 16, 24), ZIndex = 3, Parent = shop }, closeShop)

	-- the BODY CHART
	local chart = UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(8, 14, 16), BorderSizePixel = 0, Position = UDim2.fromOffset(14, 60), Size = UDim2.fromOffset(250, 448), ZIndex = 2, Parent = shop })
	UI.make("UIStroke", { Color = Color3.fromRGB(30, 70, 76), Thickness = 1, Parent = chart })
	UI.label({ Text = "BODY CHART", TextSize = 13, TextColor3 = CYAN, Position = UDim2.fromOffset(10, 6), Size = UDim2.fromOffset(200, 16), ZIndex = 3, Parent = chart })
	-- a grid on the screen
	for i = 1, 11 do
		UI.make("Frame", { BackgroundColor3 = CYAN, BackgroundTransparency = 0.93, BorderSizePixel = 0, Position = UDim2.fromOffset(i * 22, 26), Size = UDim2.new(0, 1, 1, -60), ZIndex = 2, Parent = chart })
	end
	local fig = UI.make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 34), Size = UDim2.fromOffset(230, 330), ZIndex = 3, Parent = chart })
	local function block(x: number, y: number, w: number, h: number)
		local b = UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(28, 60, 66), BackgroundTransparency = 0.35, BorderSizePixel = 0,
			Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), ZIndex = 3, Parent = fig })
		UI.make("UIStroke", { Color = CYAN, Thickness = 1, Transparency = 0.45, Parent = b })
	end
	block(93, 0, 44, 46) -- head
	block(75, 52, 80, 128) -- torso
	block(25, 52, 46, 128) -- arms
	block(159, 52, 46, 128)
	block(77, 184, 37, 136) -- legs
	block(116, 184, 37, 136)
	local legend = UI.label({ Text = "CYAN: CHROME IN YOU    RED: ON YOUR SLIP", TextSize = 10, TextColor3 = Color3.fromRGB(110, 150, 156), Position = UDim2.fromOffset(10, 420), Size = UDim2.new(1, -20, 0, 14), ZIndex = 3, Parent = chart })
	local _ = legend

	-- the SPEC SHEET
	local spec = UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(20, 19, 22), BorderSizePixel = 0, Position = UDim2.fromOffset(274, 60), Size = UDim2.fromOffset(262, 448), ZIndex = 2, Parent = shop })
	UI.make("Frame", { BackgroundColor3 = RED, BorderSizePixel = 0, Size = UDim2.new(0, 3, 1, 0), ZIndex = 3, Parent = spec })
	local slotL = UI.label({ Text = "", TextSize = 12, TextColor3 = RED, Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -24, 0, 14), ZIndex = 3, Parent = spec })
	local tabs = UI.make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 22), Size = UDim2.new(1, -24, 0, 22), ZIndex = 3, Parent = spec })
	UI.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3), Parent = tabs })
	local iName = UI.label({ Text = "", TextSize = 22, TextColor3 = C.text, Position = UDim2.fromOffset(14, 48), Size = UDim2.new(1, -24, 0, 26), TextWrapped = true, ZIndex = 3, Parent = spec })
	local iBrand = UI.label({ Text = "", TextSize = 11, TextColor3 = Color3.fromRGB(150, 140, 120), Position = UDim2.fromOffset(14, 74), Size = UDim2.new(1, -24, 0, 14), ZIndex = 3, Parent = spec })
	local iText = UI.label({ Text = "", TextSize = 13, TextColor3 = C.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(14, 92), Size = UDim2.new(1, -24, 0, 44), ZIndex = 3, Parent = spec })
	local ladder = UI.make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 138), Size = UDim2.new(1, -24, 0, 168), ZIndex = 3, Parent = spec })
	local sideRow = UI.make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 310), Size = UDim2.new(1, -24, 0, 26), ZIndex = 3, Parent = spec })
	local actRow = UI.make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 340), Size = UDim2.new(1, -24, 0, 104), ZIndex = 3, Parent = spec })

	-- the INTAKE SLIP (paper, a torn bottom edge)
	local slip = UI.make("Frame", { BackgroundColor3 = PAPER, BorderSizePixel = 0, Position = UDim2.fromOffset(548, 60), Size = UDim2.fromOffset(218, 330), Rotation = 0.6, ZIndex = 2, Parent = shop })
	for i = 0, 21 do
		UI.make("Frame", { BackgroundColor3 = PAPER, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 5 + i * 10, 1, 0),
			Size = UDim2.fromOffset(7, 7), Rotation = 45, ZIndex = 2, Parent = slip })
	end
	UI.label({ Text = "INTAKE SLIP", TextSize = 16, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 18), ZIndex = 3, Parent = slip })
	UI.label({ Text = "- - - - - - - - - - - - - - - - - - -", TextSize = 10, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 10), ZIndex = 3, Parent = slip })
	local cartList = UI.make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 36), Size = UDim2.new(1, -20, 0, 128), ZIndex = 3, Parent = slip })
	UI.make("UIListLayout", { Padding = UDim.new(0, 1), Parent = cartList })
	local totalL = UI.label({ Text = "", TextSize = 18, TextColor3 = INK, Position = UDim2.fromOffset(10, 168), Size = UDim2.new(1, -20, 0, 20), ZIndex = 3, Parent = slip })
	-- the load meter: 30 cells, a tick where your limit is
	local meter = UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(200, 192, 170), BorderSizePixel = 0, Position = UDim2.fromOffset(10, 196), Size = UDim2.new(1, -20, 0, 12), ZIndex = 3, Parent = slip })
	local cells = {}
	for i = 1, 30 do
		cells[i] = UI.make("Frame", { BackgroundColor3 = INK, BackgroundTransparency = 0.85, BorderSizePixel = 0, Position = UDim2.new((i - 1) / 30, 1, 0, 1), Size = UDim2.new(1 / 30, -2, 1, -2), ZIndex = 4, Parent = meter })
	end
	local tick = UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(180, 20, 30), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -3), Size = UDim2.new(0, 2, 1, 6), ZIndex = 5, Parent = meter })
	local loadL = UI.label({ Text = "", TextSize = 11, TextColor3 = INK, Position = UDim2.fromOffset(10, 210), Size = UDim2.new(1, -20, 0, 14), ZIndex = 3, Parent = slip })
	-- the deli ticket: your number on the list
	local ticket = UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(196, 40, 46), BorderSizePixel = 0, Position = UDim2.fromOffset(10, 230), Size = UDim2.new(1, -20, 0, 50), ZIndex = 3, Parent = slip })
	local ticketL = UI.label({ Text = "", TextSize = 13, TextColor3 = Color3.fromRGB(255, 240, 230), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = ticket })
	UI.button({ Text = "SIGN THE LIST", TextSize = 14, TextColor3 = PAPER, BackgroundColor3 = INK, Position = UDim2.fromOffset(10, 288), Size = UDim2.new(0.62, -12, 0, 28), ZIndex = 3, Parent = slip }, function()
		if #cart == 0 then
			toast("THE SLIP IS EMPTY - PICK SOMETHING ON THE CHART", RED)
			return
		end
		Remote:FireServer("ripper", "queue", cart)
	end)
	UI.button({ Text = "TEAR IT UP", TextSize = 11, TextColor3 = INK, BackgroundColor3 = Color3.fromRGB(196, 186, 160), Position = UDim2.new(0.62, 0, 0, 288), Size = UDim2.new(0.38, -10, 0, 28), ZIndex = 3, Parent = slip }, function()
		table.clear(cart)
		Remote:FireServer("ripper", "leave")
		if shopRefresh then
			shopRefresh()
		end
	end)
	-- under the slip: the counter's own stock
	UI.label({ Text = "ON THE COUNTER", TextSize = 11, TextColor3 = Color3.fromRGB(150, 140, 120), Position = UDim2.fromOffset(548, 400), Size = UDim2.fromOffset(218, 14), ZIndex = 2, Parent = shop })
	UI.button({ Text = "RIPPER KIT  $" .. 150, TextSize = 12, BackgroundColor3 = STEEL, Position = UDim2.fromOffset(548, 418), Size = UDim2.fromOffset(106, 30), ZIndex = 2, Parent = shop }, function()
		Remote:FireServer("ripper", "kit")
	end)
	UI.button({ Text = "SYRINGE  $" .. 120, TextSize = 12, BackgroundColor3 = STEEL, Position = UDim2.fromOffset(660, 418), Size = UDim2.fromOffset(106, 30), ZIndex = 2, Parent = shop }, function()
		Remote:FireServer("ripper", "syringe")
	end)
	UI.label({ Text = "Nobody puts chrome in themselves. When your number comes up, lie down on the table in the back.", TextSize = 10,
		TextColor3 = Color3.fromRGB(150, 140, 120), TextWrapped = true, Position = UDim2.fromOffset(548, 454), Size = UDim2.fromOffset(218, 40), ZIndex = 2, Parent = shop })

	local selected = Cyberware.List[1]
	local selTier = 1
	local selSide = "R"
	local sockets: { [string]: TextButton } = {}
	local function onSlip(key: string): string?
		for _, o in cart do
			if o.op == "in" and Cyberware.Key(o.id, o.side) == key then
				return "in"
			elseif o.op == "out" and o.key == key then
				return "out"
			end
		end
		return nil
	end
	local function slotDefs(slotId: string): { any }
		local out = {}
		for _, d in Cyberware.List do
			if d.slot == slotId and (not d.admin or Items.IsOwner(player)) then
				table.insert(out, d)
			end
		end
		return out
	end
	local refresh: () -> ()
	local function pickSlot(slotId: string, side: string?)
		local defs = slotDefs(slotId)
		if #defs == 0 then
			return
		end
		local keep = false
		for _, d in defs do
			if d == selected then
				keep = true
			end
		end
		if not keep then
			selected = defs[1]
		end
		if side then
			selSide = side
		end
		local mine = myList()
		selTier = math.min(selected.tiers, math.max(1, Cyberware.Tier(mine, selected.id) + 1))
		refresh()
	end
	-- the sockets
	for _, slot in Cyberware.Slots do
		local ids = slot.side and { slot.id .. "_L", slot.id .. "_R" } or { slot.id }
		for _, sk in ids do
			local at = SOCKETS[sk]
			if at and (#slotDefs(slot.id) > 0) then
				local side = slot.side and string.sub(sk, -1) or nil
				local b = UI.button({ Text = SOCKET_CODE[slot.id] or "?", TextSize = 9, TextColor3 = Color3.fromRGB(10, 20, 22), BackgroundColor3 = Color3.fromRGB(60, 90, 96),
					AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(at.X, at.Y), Size = UDim2.fromOffset(22, 18), ZIndex = 5, Parent = fig }, function()
					pickSlot(slot.id, side)
				end)
				sockets[sk] = b
			end
		end
	end

	refresh = function()
		local mine = myList()
		cashL.Text = Items.IsOwner(player) and ("$" .. cashNow() .. "  (ADMIN: FREE)") or ("CREDIT  $" .. cashNow())
		-- the sockets: cyan = in you, red = on the slip, the selected one white-edged
		for sk, b in sockets do
			local slotId = Cyberware.Split(sk)
			local side = string.match(sk, "_([LR])$")
			local inYou, slipped = false, false
			for _, d in slotDefs(slotId) do
				local key = Cyberware.Key(d.id, side)
				if mine[key] then
					inYou = true
				end
				if onSlip(key) then
					slipped = true
				end
			end
			b.BackgroundColor3 = slipped and RED or (inYou and CYAN or Color3.fromRGB(60, 90, 96))
			local isSel = selected.slot == slotId and (side == nil or side == selSide)
			local st = b:FindFirstChild("Sel") :: UIStroke?
			if isSel and not st then
				UI.make("UIStroke", { Name = "Sel", Color = Color3.new(1, 1, 1), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
			elseif not isSel and st then
				st:Destroy()
			end
		end
		-- the spec sheet
		local d = selected
		slotL.Text = "SOCKET: " .. (Cyberware.SlotName[d.slot] or "") 
		for _, c in tabs:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local defs = slotDefs(d.slot)
		if #defs > 1 then
			for _, od in defs do
				UI.button({ Text = od.name, TextSize = 10, BackgroundColor3 = od == d and Color3.fromRGB(120, 16, 24) or STEEL,
					Size = UDim2.new(1 / #defs, -3, 1, 0), ZIndex = 4, Parent = tabs }, function()
					selected = od
					selTier = math.min(od.tiers, math.max(1, Cyberware.Tier(mine, od.id) + 1))
					refresh()
				end)
			end
		end
		iName.Text = d.name
		iBrand.Text = "BY " .. d.brand .. (d.ability and ("   //   KEY: " .. d.ability) or "   //   ALWAYS ON")
		iText.Text = d.info
		for _, c in ladder:GetChildren() do
			c:Destroy()
		end
		local h = math.floor(168 / d.tiers)
		local have = Cyberware.Tier(mine, d.id)
		for i = 1, d.tiers do
			local on = i == selTier
			local row = UI.button({ Text = "", BackgroundColor3 = on and Color3.fromRGB(70, 14, 20) or Color3.fromRGB(28, 27, 31),
				Position = UDim2.fromOffset(0, (i - 1) * h), Size = UDim2.new(1, 0, 0, h - 4), ZIndex = 4, Parent = ladder }, function()
				selTier = i
				refresh()
			end)
			UI.label({ Text = "T" .. i, TextSize = 20, TextColor3 = on and RED or Color3.fromRGB(110, 104, 96), Position = UDim2.fromOffset(6, 2), Size = UDim2.fromOffset(30, 22), ZIndex = 5, Parent = row })
			UI.label({ Text = "$" .. d.price[i] .. "   LOAD " .. d.load[i] .. (have >= i and "   (IN YOU)" or ""), TextSize = 11, TextColor3 = have >= i and CYAN or C.amber,
				Position = UDim2.fromOffset(40, 4), Size = UDim2.new(1, -46, 0, 14), ZIndex = 5, Parent = row })
			UI.label({ Text = d.desc[i], TextSize = 11, TextColor3 = C.text, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.fromOffset(40, 19), Size = UDim2.new(1, -46, 1, -20), ZIndex = 5, Parent = row })
		end
		for _, c in sideRow:GetChildren() do
			c:Destroy()
		end
		for _, c in actRow:GetChildren() do
			c:Destroy()
		end
		local sided = Cyberware.Key(d.id, "R") ~= d.id
		if sided then
			for i, sd in { "L", "R" } do
				UI.button({ Text = sd == "L" and "LEFT SIDE" or "RIGHT SIDE", TextSize = 11, BackgroundColor3 = sd == selSide and Color3.fromRGB(120, 16, 24) or STEEL,
					Position = UDim2.new((i - 1) * 0.5, (i - 1) * 3, 0, 0), Size = UDim2.new(0.5, -3, 1, 0), ZIndex = 4, Parent = sideRow }, function()
					selSide = sd
					refresh()
				end)
			end
		end
		local side = sided and selSide or nil
		local key = Cyberware.Key(d.id, side)
		local function clearKey()
			for i = #cart, 1, -1 do
				local o = cart[i]
				if (o.op == "in" and Cyberware.Key(o.id, o.side) == key) or (o.op == "out" and o.key == key) then
					table.remove(cart, i)
				end
			end
		end
		UI.button({ Text = "ON THE SLIP: PUT IN T" .. selTier, TextSize = 13, BackgroundColor3 = Color3.fromRGB(150, 20, 30), Size = UDim2.new(1, 0, 0, 30), ZIndex = 4, Parent = actRow }, function()
			clearKey()
			table.insert(cart, { op = "in", id = d.id, tier = selTier, side = side })
			refresh()
		end)
		if mine[key] then
			UI.button({ Text = "ON THE SLIP: TAKE IT OUT  $" .. math.floor(Cyberware.Price(d.id, mine[key]) * Config.CyberRemoveShare), TextSize = 12,
				BackgroundColor3 = STEEL, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 28), ZIndex = 4, Parent = actRow }, function()
				clearKey()
				table.insert(cart, { op = "out", key = key })
				refresh()
			end)
		end
		UI.button({ Text = "BUY IT IN A CASE  $" .. d.price[selTier], TextSize = 11, BackgroundColor3 = Color3.fromRGB(30, 30, 34), Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 0, 24), ZIndex = 4, Parent = actRow }, function()
			Remote:FireServer("ripper", "case", d.id, selTier)
		end)
		UI.label({ Text = "(a case: another player puts it in - in here it pays them)", TextSize = 9, TextColor3 = Color3.fromRGB(120, 112, 100), Position = UDim2.fromOffset(0, 92), Size = UDim2.new(1, 0, 0, 12), ZIndex = 4, Parent = actRow })
		-- the slip
		for _, c in cartList:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		if #cart == 0 then
			UI.label({ Text = "(nothing yet - pick a socket)", TextSize = 11, TextColor3 = Color3.fromRGB(110, 100, 86), Size = UDim2.new(1, 0, 0, 16), ZIndex = 4, Parent = cartList })
		end
		for i, o in cart do
			local text
			if o.op == "in" then
				local od = Cyberware.ById[o.id]
				text = "IN   " .. (od and od.name or o.id) .. " T" .. o.tier .. (o.side and (" " .. o.side) or "")
			else
				local id, sd = Cyberware.Split(o.key)
				local od = Cyberware.ById[id]
				text = "OUT  " .. (od and od.name or id) .. (sd and (" " .. sd) or "")
			end
			UI.button({ Text = text, TextSize = 11, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = PAPER, BackgroundTransparency = 0,
				AutoButtonColor = true, Size = UDim2.new(1, 0, 0, 16), ZIndex = 4, Parent = cartList }, function()
				table.remove(cart, i)
				refresh()
			end)
		end
		local total, load = cartTotal()
		local tol = player:GetAttribute("CyTol")
		tol = typeof(tol) == "number" and tol or Config.CyberTolerance
		totalL.Text = "TOTAL   $" .. total
		local maxCells = 30
		for i = 1, maxCells do
			local filled = i <= load
			cells[i].BackgroundTransparency = filled and 0.05 or 0.85
			cells[i].BackgroundColor3 = (filled and i > tol) and Color3.fromRGB(190, 20, 30) or INK
		end
		tick.Position = UDim2.new(math.clamp(tol / maxCells, 0, 1), 0, 0, -3)
		loadL.Text = string.format("LOAD %d / LIMIT %d%s", load, tol, load > tol and "   OVER: PSYCHOSIS" or "")
		loadL.TextColor3 = load > tol and Color3.fromRGB(170, 20, 30) or INK
		local q = player:GetAttribute("RipperQueue")
		if typeof(q) == "number" then
			ticketL.Text = q == 0 and "NOW SERVING: YOU\nLIE DOWN ON THE TABLE IN THE BACK" or string.format("YOUR NUMBER  %02d\nPLACE %d IN LINE", q, q)
			ticket.BackgroundColor3 = q == 0 and Color3.fromRGB(30, 140, 70) or Color3.fromRGB(196, 40, 46)
		else
			ticketL.Text = "NOT ON THE LIST\nSIGN IT TO GET A NUMBER"
			ticket.BackgroundColor3 = Color3.fromRGB(120, 112, 100)
		end
	end
	shopRefresh = refresh
	player:GetAttributeChangedSignal("Cash"):Connect(function()
		if shop.Visible then
			refresh()
		end
	end)
	player:GetAttributeChangedSignal("RipperQueue"):Connect(function()
		if shop.Visible then
			refresh()
		end
	end)
	player:GetAttributeChangedSignal("Cyber"):Connect(function()
		if shop.Visible then
			refresh()
		end
	end)
end

local function openShop()
	if not shop then
		buildShop()
	end
	shop.Visible = true
	Input.freeCursor = true
	if shopRefresh then
		shopRefresh()
	end
end

-- your turn: a line from you to the bed
local function showTurn(seconds: number)
	turnUntil = os.clock() + seconds
	local map = workspace:FindFirstChild("Map")
	local bed = map and map:FindFirstChild("RipperBed", true)
	local me = torsoOf(myChar())
	if not bed or not me then
		return
	end
	if turnBeam then
		turnBeam:Destroy()
	end
	local a0 = Instance.new("Attachment")
	a0.Parent = me
	local a1 = Instance.new("Attachment")
	a1.Parent = bed
	local b = Instance.new("Beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.Color = ColorSequence.new(RED)
	b.LightEmission = 1
	b.Width0, b.Width1 = 0.25, 0.25
	b.FaceCamera = true
	b.Transparency = NumberSequence.new(0.2)
	b.Parent = me
	turnBeam, turnA0 = b, a0
	toast("YOUR TURN - LIE DOWN ON THE BED", RED)
	SoundLibrary.Play("click", nil, 1)
end

local function clearTurn()
	turnUntil = 0
	if turnBeam then
		turnBeam:Destroy()
		turnBeam = nil
	end
	if turnA0 then
		turnA0:Destroy()
		turnA0 = nil
	end
end

-- the syringe: a cold blue flash, a needle on the screen, then the dream (the sleep does that)
local function syringe()
	clearTurn()
	closeShop()
	local s = UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(120, 220, 255), BackgroundTransparency = 0.5, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, ZIndex = 50, Parent = gui })
	local t = UI.label({ Text = "THE DOC LEANS OVER YOU WITH A SYRINGE...", TextSize = 24, TextColor3 = Color3.fromRGB(255, 255, 255), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 51, TextStrokeTransparency = 0.4, Parent = gui })
	SoundLibrary.Play("click", nil, 1)
	TweenService:Create(s, TweenInfo.new(1.6), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(t, TweenInfo.new(2.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(2.5, function()
		s:Destroy()
		t:Destroy()
	end)
end

-- the ripper kit: which implant comes out?
local picker: Frame? = nil
local function pickImplant(body: Model, cb: (string) -> ())
	if picker then
		picker:Destroy()
	end
	local list = Cyberware.Decode(body:GetAttribute("Cyber"))
	local keys = {}
	for k in list do
		table.insert(keys, k)
	end
	table.sort(keys)
	if #keys == 0 then
		toast("NO CHROME IN THEM", RED)
		return
	end
	local f = UI.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(300, 46 + #keys * 30),
		BackgroundColor3 = PANEL, BackgroundTransparency = 0.05, BorderSizePixel = 0, Parent = gui,
	})
	UI.make("UIStroke", { Color = RED, Thickness = 2, Parent = f })
	UI.label({ Text = "WHICH ONE COMES OUT?", TextSize = 15, TextColor3 = RED, Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 20), Parent = f })
	picker = f
	Input.freeCursor = true
	for i, k in keys do
		local id, sd = Cyberware.Split(k)
		local d = Cyberware.ById[id]
		UI.button({ Text = (d and d.name or id) .. (sd and (" (" .. sd .. ")") or "") .. "  T" .. list[k], TextSize = 13, Position = UDim2.fromOffset(10, 34 + (i - 1) * 30), Size = UDim2.new(1, -20, 0, 26), Parent = f }, function()
			f:Destroy()
			picker = nil
			Input.freeCursor = false
			cb(k)
		end)
	end
	task.delay(12, function()
		if picker == f then
			f:Destroy()
			picker = nil
			Input.freeCursor = false
		end
	end)
end

-- the TV on the east wall: ads for chrome, round and round
local function startTV()
	local map = workspace:FindFirstChild("Map")
	local tv = map and map:FindFirstChild("RipperTV", true)
	if not tv or not tv:IsA("BasePart") then
		return
	end
	local g = Instance.new("SurfaceGui")
	g.Name = "Ads"
	g.Face = Enum.NormalId.Left -- (the screen looks west, into the room)
	g.CanvasSize = Vector2.new(870, 372)
	g.LightInfluence = 0
	g.Brightness = 1.6
	g.MaxDistance = 90
	g.Parent = tv
	local bg = UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(6, 6, 10), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ClipsDescendants = true, Parent = g })
	local title = UI.label({ Text = "", TextSize = 64, TextColor3 = RED, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 80), Parent = bg })
	local sub = UI.label({ Text = "", TextSize = 30, TextColor3 = CYAN, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 140), Size = UDim2.new(1, 0, 0, 40), TextWrapped = true, Parent = bg })
	local small = UI.label({ Text = "", TextSize = 22, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(40, 200), Size = UDim2.new(1, -80, 0, 110), TextWrapped = true, Parent = bg })
	local scan = UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.9, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 6), Parent = bg })
	local ticker = UI.label({ Text = "", TextSize = 22, TextColor3 = C.amber, Position = UDim2.new(0, 0, 1, -34), Size = UDim2.new(4, 0, 0, 30), Parent = bg })
	local slides = {
		{ "RIPPERDOC", "CHROME FOR EVERY BODY", "Talk to " .. Config.RipperDocName .. ". Pick your chrome. Wait your turn. Sleep. Wake up better." },
	}
	for _, d in Cyberware.List do
		if not d.admin then
			table.insert(slides, { d.name, d.brand .. "  -  FROM $" .. d.price[1], d.desc[d.tiers] })
		end
	end
	table.insert(slides, { "KNOW YOUR LIMIT", "TOLERANCE " .. Config.CyberTolerance, "Too much chrome and the world starts to look back at you. We are not responsible for what you do then." })
	local tickText = "+++ NO REFUNDS +++ BRING YOUR OWN SURGEON: CASES SOLD HERE +++ SURGEONS GET PAID IN THIS ROOM +++ THE DOC IS NOT LIABLE FOR DREAMS +++ "
	task.spawn(function()
		local i = 0
		while tv.Parent do
			i = i % #slides + 1
			local s = slides[i]
			title.Text, sub.Text, small.Text = s[1], s[2], s[3]
			title.TextTransparency = 1
			TweenService:Create(title, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
			-- a glitch now and then
			for _ = 1, 6 do
				task.wait(0.7)
				if rng:NextNumber() < 0.25 then
					title.Position = UDim2.fromOffset(rng:NextInteger(-12, 12), 40)
					title.TextColor3 = rng:NextNumber() < 0.5 and CYAN or RED
					task.wait(0.06)
					title.Position = UDim2.fromOffset(0, 40)
					title.TextColor3 = RED
				end
			end
		end
	end)
	local t0 = os.clock()
	RunService.Heartbeat:Connect(function()
		if not g.Parent then
			return
		end
		local cam = workspace.CurrentCamera
		if cam and (cam.CFrame.Position - tv.Position).Magnitude > 90 then
			return
		end
		local t = os.clock() - t0
		scan.Position = UDim2.new(0, 0, (t * 0.35) % 1, 0)
		ticker.Text = string.rep(tickText, 4)
		ticker.Position = UDim2.new(-((t * 0.04) % 1), 0, 1, -34)
	end)
end

-- the waiting room board (the server writes the list into its attribute)
local function startBoard()
	local map = workspace:FindFirstChild("Map")
	local b = map and map:FindFirstChild("RipperBoard", true)
	if not b or not b:IsA("BasePart") then
		return
	end
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Front
	g.CanvasSize = Vector2.new(390, 216)
	g.LightInfluence = 0
	g.MaxDistance = 60
	g.Parent = b
	UI.label({ Text = "WAITING LIST", TextSize = 30, TextColor3 = RED, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 40), Parent = g })
	local l = UI.label({ Text = "", TextSize = 22, TextColor3 = C.text, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(14, 44), Size = UDim2.new(1, -28, 1, -50), TextWrapped = true, Parent = g })
	local function upd()
		local q = b:GetAttribute("Queue")
		l.Text = typeof(q) == "string" and q or ""
	end
	b:GetAttributeChangedSignal("Queue"):Connect(upd)
	upd()
end

------------------------------------------------------------------------
-- M > CYBER
------------------------------------------------------------------------

function CyberClient.BuildPage(page: ScrollingFrame)
	local rows = UI.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 900), Parent = page })
	page.CanvasSize = UDim2.fromOffset(0, 900)
	local head = UI.label({ Text = "", TextSize = 15, TextColor3 = C.amber, Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -28, 0, 40), TextWrapped = true, Parent = rows })
	local listL = UI.label({ Text = "", TextSize = 13, TextColor3 = C.text, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(14, 50), Size = UDim2.new(1, -28, 0, 220), TextWrapped = true, Parent = rows })
	UI.label({ Text = "CYBER BAR KEYS (click a slot, then press a key)", TextSize = 13, TextColor3 = C.amber, Position = UDim2.fromOffset(14, 276), Size = UDim2.new(1, -28, 0, 18), Parent = rows })
	local keyBtns = {}
	local waiting: number? = nil
	for i = 1, 9 do
		local b = UI.button({ Text = "", TextSize = 12, Position = UDim2.fromOffset(14 + ((i - 1) % 3) * 172, 298 + math.floor((i - 1) / 3) * 32), Size = UDim2.fromOffset(166, 28), Parent = rows }, function()
			waiting = i
			keyBtns[i].Text = "SLOT " .. i .. ": PRESS A KEY..."
		end)
		keyBtns[i] = b
	end
	UI.button({ Text = "DEFAULT KEYS (1-9)", TextSize = 12, Position = UDim2.fromOffset(14, 400), Size = UDim2.fromOffset(166, 26), Parent = rows }, function()
		Settings.Set("cyberKeys", table.concat(Cyberware.DefaultKeys, ","))
	end)
	-- the HOWLER: shell and colour
	UI.label({ Text = "HOWLER ARM CANNON", TextSize = 13, TextColor3 = C.amber, Position = UDim2.fromOffset(14, 436), Size = UDim2.new(1, -28, 0, 18), Parent = rows })
	local shellBtns, colBtns = {}, {}
	local function lookNow(): (string, string)
		local raw = player:GetAttribute("CyLook")
		local v = typeof(raw) == "string" and string.match(raw, "howler=([%u:]+)") or nil
		local s, c = string.match(v or "", "^(%u+):(%u+)$")
		return s or "EXPLOSIVE", c or "RED"
	end
	for i, sh in Cyberware.Shells do
		shellBtns[sh] = UI.button({ Text = sh, TextSize = 12, Position = UDim2.fromOffset(14 + (i - 1) * 120, 458), Size = UDim2.fromOffset(114, 26), Parent = rows }, function()
			local _, c = lookNow()
			Remote:FireServer("look", "howler", sh .. ":" .. c)
		end)
	end
	for i, cc in Cyberware.Colors do
		colBtns[cc.name] = UI.button({ Text = cc.name, TextSize = 11, TextColor3 = cc.c, Position = UDim2.fromOffset(14 + (i - 1) * 82, 490), Size = UDim2.fromOffset(78, 24), Parent = rows }, function()
			local s = lookNow()
			Remote:FireServer("look", "howler", s .. ":" .. cc.name)
		end)
	end
	local function refresh()
		readBinds()
		local mine = myList()
		local load = player:GetAttribute("CyLoad")
		local tol = player:GetAttribute("CyTol")
		local ps = player:GetAttribute("CyPsycho")
		head.Text = string.format("LOAD %d / %d   PSYCHOSIS %d%%   %s", typeof(load) == "number" and load or 0, typeof(tol) == "number" and tol or Config.CyberTolerance,
			math.floor((typeof(ps) == "number" and ps or 0) * 100), (Items.IsOwner(player) and player:GetAttribute("AdminPsychoEnabled") ~= true) and "(ADMIN IMMUNITY ON)" or "")
		local lines = {}
		for _, d in Cyberware.List do
			for _, k in { d.id, d.id .. "_L", d.id .. "_R" } do
				local t = mine[k]
				if t then
					local sd = string.sub(k, -2) == "_L" and " (LEFT)" or (string.sub(k, -2) == "_R" and " (RIGHT)" or "")
					table.insert(lines, d.name .. sd .. "  T" .. t .. "  -  " .. d.desc[t])
				end
			end
		end
		listL.Text = #lines > 0 and table.concat(lines, "\n") or "No chrome yet. The ripperdoc is the dark building south of the red house."
		for i = 1, 9 do
			if waiting ~= i then
				local s = bar[i]
				keyBtns[i].Text = "SLOT " .. i .. ": " .. keyLabel(binds[i]) .. (s and ("  " .. (s.def.ability or "")) or "")
			end
		end
		local sh, col = lookNow()
		for name, b in shellBtns do
			b.BackgroundColor3 = name == sh and Color3.fromRGB(150, 20, 30) or C.panel2
		end
		for name, b in colBtns do
			b.BackgroundColor3 = name == col and Color3.fromRGB(70, 70, 80) or C.panel2
		end
	end
	UserInputService.InputBegan:Connect(function(io)
		if Input.IsControlled() then return end
		if waiting and io.UserInputType == Enum.UserInputType.Keyboard then
			local i = waiting
			waiting = nil
			if io.KeyCode ~= Enum.KeyCode.Escape then
				readBinds()
				binds[i] = io.KeyCode.Name
				Settings.Set("cyberKeys", table.concat(binds, ","))
			end
			refresh()
		end
	end)
	Settings.Changed:Connect(function(key)
		if key == "cyberKeys" then
			refresh()
			rebuildBar()
		end
	end)
	for _, a in { "Cyber", "CyLoad", "CyTol", "CyPsycho", "CyLook" } do
		player:GetAttributeChangedSignal(a):Connect(refresh)
	end
	page:GetPropertyChangedSignal("Visible"):Connect(refresh)
	refresh()
end

------------------------------------------------------------------------

function CyberClient.SetController(c: any)
	controller = c
	if c then
		c.cyberFire = cyberFire
	end
	clearLock()
end

local function readEff()
	local ch = myChar()
	eff = Cyberware.Decode(ch and ch:GetAttribute("Cyber"))
	rebuildBar()
end

local watched: Model? = nil
local function watchChar(ch: Model?)
	if not ch or watched == ch then
		return
	end
	watched = ch
	-- (v2.8.1) REGROWTH / TITAN: what is mending and how long it takes
	local NAMES = { LeftArm = "LEFT ARM", RightArm = "RIGHT ARM", LeftLeg = "LEFT LEG", RightLeg = "RIGHT LEG" }
	for key, nm in NAMES do
		ch:GetAttributeChangedSignal("RegrowAt_" .. key):Connect(function()
			local at = ch:GetAttribute("RegrowAt_" .. key)
			if typeof(at) == "number" then
				local left = math.ceil(at - workspace:GetServerTimeNow())
				local severed = ch:GetAttribute("Severed_" .. key) == true
				toast(nm .. (severed and " GROWS BACK IN " or " KNITS IN ") .. left .. " S", Color3.fromRGB(120, 255, 170))
			elseif ch:GetAttribute("Broken_" .. key) ~= true and ch:GetAttribute("Severed_" .. key) ~= true and ch:GetAttribute("Dead") ~= true then
				toast(nm .. " IS WHOLE AGAIN", Color3.fromRGB(120, 255, 170))
			end
		end)
	end
	ch:GetAttributeChangedSignal("Cyber"):Connect(function()
		local old = #bar
		readEff()
		if #bar > old then
			local s = bar[#bar]
			toast("NEW CHROME: " .. s.def.name .. "  -  KEY " .. keyLabel(binds[#bar]) .. ": " .. (s.def.ability or ""), CYAN)
		end
	end)
	readEff()
end

function CyberClient.Init()
	Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Cyber") :: RemoteEvent
	gui = UI.make("ScreenGui", { Name = "CyberGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 25, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
	overlay = UI.make("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 40, Parent = gui })
	toastLabel = UI.label({ Text = "", TextSize = 20, TextColor3 = CYAN, TextTransparency = 1, TextStrokeTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.2, 0), Size = UDim2.fromOffset(700, 26), Parent = gui })
	-- (v2.8.1) on the right edge, stacked from the bottom up (above the ammo panel); a phone keeps it along the bottom
	local phone = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if phone then
		barFrame = UI.make("Frame", { Name = "CyberBar", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -84), Size = UDim2.fromOffset(9 * 70, 50), Visible = false, Parent = gui })
		UI.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = barFrame })
	else
		barFrame = UI.make("Frame", { Name = "CyberBar", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -112), Size = UDim2.fromOffset(66, 9 * 54), Visible = false, Parent = gui })
		UI.make("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = barFrame })
	end
	-- shield / psychosis (only when there is something to show)
	statusPanel = UI.make("Frame", { BackgroundColor3 = PANEL, BackgroundTransparency = 0.25, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -200), Size = UDim2.fromOffset(250, 44), Visible = false, Parent = gui })
	local sb = UI.make("Frame", { BackgroundColor3 = PANEL2, BorderSizePixel = 0, Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 14), Parent = statusPanel })
	shieldFill = UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(80, 170, 255), BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = sb })
	shieldText = UI.label({ Text = "", TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = sb })
	local pb = UI.make("Frame", { BackgroundColor3 = PANEL2, BorderSizePixel = 0, Position = UDim2.fromOffset(8, 24), Size = UDim2.new(1, -16, 0, 14), Parent = statusPanel })
	psychoFill = UI.make("Frame", { BackgroundColor3 = RED, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = pb })
	psychoText = UI.label({ Text = "", TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = pb })
	huntArrow = UI.label({ Text = "", TextSize = 16, TextColor3 = Color3.fromRGB(255, 150, 40), TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(220, 22), Visible = false, TextStrokeTransparency = 0.3, Parent = gui })
	threatMark = UI.label({ Text = "<<  SHOOTER  >>", TextSize = 18, TextColor3 = RED, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(200, 24), Visible = false, TextStrokeTransparency = 0.2, Parent = gui })
	redVision = Instance.new("ColorCorrectionEffect")
	redVision.Name = "CyberRedVision"
	redVision.TintColor = Color3.fromRGB(255, 150, 150)
	redVision.Contrast = 0.25
	redVision.Saturation = -0.6
	redVision.Enabled = false
	redVision.Parent = Lighting

	readBinds()
	Controller.OnCyberHint = function(text: string)
		toast(text, RED)
	end
	Controller.OnPickImplant = pickImplant

	Remote.OnClientEvent:Connect(function(action, a, b, c, d)
		if action == "fx" then
			onFx(a)
		elseif action == "msg" then
			toast(tostring(a), CYAN)
		elseif action == "threat" then
			local tier = tonumber(c) or 1
			local shooterP = Players:GetPlayerByUserId(tonumber(a) or 0)
			local shooter = shooterP and shooterP.Character
			-- (v2.8.1) an arm gun that is out answers on its own
			if shooter and shooter.Parent and shooter:GetAttribute("Dead") ~= true then
				returnFire(shooter)
			end
			if tier >= 1 then
				threat = { origin = b, untilT = os.clock() + 1.6, tier = tier }
				SoundLibrary.Play("click", nil, 0.7)
			end
			local wasLocked = shooter ~= nil and isLocked(shooter)
			if tier >= 2 and controller and typeof(b) == "Vector3" then
				local me = torsoOf(myChar())
				if me then
					local yaw = yawPitchTo(b - me.Position)
					controller.faceYaw = yaw
					controller.faceYawUntil = os.clock() + 1.4
					-- (v2.8.1) the whole view swings onto them (the crosshair is on them), and they are locked
					local aimAt = (shooter and torsoOf(shooter) and (torsoOf(shooter) :: BasePart).Position) or b
					local cy, cp = yawPitchTo(aimAt - workspace.CurrentCamera.CFrame.Position)
					camTurn = { yaw = cy, pitch = math.clamp(cp, -1.2, 1.2), t0 = os.clock(), y0 = Cam.yaw, p0 = Cam.pitch }
					if shooter and shooter.Parent and shooter:GetAttribute("Dead") ~= true then
						markThreat(shooter)
					end
				end
			end
			-- (v2.8.1) locked already, and they shoot your way while a hand holds a gun: one shot back, on its own
			if tier >= 2 and wasLocked and shooter and controller and controller.ready and os.clock() - lastAutoShot > 0.6 then
				for _, side in { "Right", "Left" } do
					local g = controller.hands and controller.hands[side] and controller.hands[side].grip
					if g and g.item and Items.IsGun(g.item) and not (Config.Guns[g.kind or ""] and Config.Guns[g.kind or ""].projectile) then
						lastAutoShot = os.clock()
						autoShot = { side = side, target = shooter, at = os.clock(), fired = false }
						local shot = autoShot
						task.delay(0.16, function()
							if autoShot == shot and controller and controller.ready and not controller.dead then
								local gg = controller.hands[side] and controller.hands[side].grip
								if gg and gg.item == g.item then
									pcall(controller._fireGun, controller, side, gg)
								end
								shot.fired = true
							end
						end)
						break
					end
				end
			end
		elseif action == "crash" then
			crashOut(tonumber(a) or Config.CrashOutTime)
		elseif action == "pulled" then
			SoundLibrary.Play("metal", nil, 0.6)
			-- (v2.8.1) it flies into a free hand: the hand closes on it when it gets there
			local item = a
			if typeof(item) == "Instance" and item:IsA("Model") and controller then
				local c = controller
				task.spawn(function()
					local t0 = os.clock()
					while os.clock() - t0 < 1.8 do
						task.wait(0.03)
						local root = item.PrimaryPart
						local me = torsoOf(myChar())
						if not item.Parent or not root or not me or c ~= controller or not c.ready or c.dead then
							return
						end
						local holder = item:GetAttribute("HolderId")
						if typeof(holder) == "number" and holder ~= 0 then
							return
						end
						if (root.Position - me.Position).Magnitude < 5.5 then
							for _, side in { "Right", "Left" } do
								local h = c.hands and c.hands[side]
								if h and not h.grip and c:_limbUsable(side == "Right" and "RightArm" or "LeftArm") then
									h.armed = true
									c:_gripItem(side, item)
									return
								end
							end
							return
						end
					end
				end)
			end
		elseif action == "ripper" then
			if a == "open" then
				openShop()
			elseif a == "msg" then
				toast(tostring(b), RED)
				if shop and shop.Visible and shopRefresh then
					shopRefresh()
				end
			elseif a == "turn" then
				showTurn(tonumber(b) or Config.RipperShowUpTime)
			elseif a == "dream" then
				syringe()
			elseif a == "done" then
				cart = {}
				toast("WELCOME BACK", CYAN)
			end
		end
		local _ = d
	end)

	-- the keys of the bar
	UserInputService.InputBegan:Connect(function(io, processed)
		if Input.IsControlled() then return end
		if processed or io.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if Input.menuOpen or Input.promptOpen or Input.keysCaptured or Input.ledgerOpen or Input.freeCam then
			return
		end
		local name = io.KeyCode.Name
		if KEY_NAMES[name] and controller and (controller.liftPad or controller.flying) then
			return -- (the lift / flying use the digits)
		end
		for i = 1, math.min(9, #bar) do
			if binds[i] == name then
				CyberClient.Use(i)
				return
			end
		end
	end)
	-- SICKLE BLADES tier 3: a jump with the blades out is a lunge
	Input.Action:Connect(function(action)
		if action ~= "Jump" or not controller or not controller.ready or not controller.grounded then
			return
		end
		local ch = myChar()
		if not ch or Cyberware.Tier(eff, "sickles") < 3 then
			return
		end
		if ch:GetAttribute("Cy_open_sickles_L") or ch:GetAttribute("Cy_open_sickles_R") then
			task.delay(0.05, function()
				local t = controller.torso
				if t and t.Parent then
					local look = Cam.LookVector()
					local flat = Vector3.new(look.X, 0, look.Z).Unit
					pcall(function()
						t:ApplyImpulse(flat * 38 * (controller.slowK or 1) * t.AssemblyMass)
					end)
				end
			end)
		end
	end)

	player.CharacterAdded:Connect(watchChar)
	watchChar(player.Character)
	player:GetAttributeChangedSignal("CyHunt"):Connect(refreshHunt)
	for _, a in { "Gift_sever", "Admin" } do
		player:GetAttributeChangedSignal(a):Connect(rebuildBar)
	end
	player:GetAttributeChangedSignal("RipperQueue"):Connect(function()
		local q = player:GetAttribute("RipperQueue")
		if q == nil then
			clearTurn()
		end
	end)

	task.spawn(function()
		local map = workspace:WaitForChild("Map", 30)
		if map then
			task.wait(1)
			startTV()
			startBoard()
		end
	end)

	-- every frame / tick: cooldowns, targets, arrows, the cloak, the ice
	local tick = 0
	local prevMouse = { L = false, R = false }
	local lastClick = { L = 0, R = 0 }
	RunService.RenderStepped:Connect(function(dt)
		tick += dt
		local ch = myChar()
		local tnow = now()
		-- (v2.8.2) a SHIFTGUN that is out fires with ITS mouse button (LMB left arm, RMB right arm) where the arm points (it
		-- follows the mouse like a hand); held down, tier 3 keeps firing
		for _, sd in { "L", "R" } do
			local key = "shiftgun_" .. sd
			local down = manualArm(sd)
			local tier = eff[key]
			local hand = controller and controller.hands and controller.hands[sd == "L" and "Left" or "Right"]
			if down and tier and ch and ch:GetAttribute("Cy_open_" .. key) and hand and not hand.grip and controller and not controller.dead then
				local edge = not prevMouse[sd]
				local rate = Config.ShiftgunRate[math.clamp(tier, 1, 3)] or 0.2
				if (edge or tier >= 3) and os.clock() - lastClick[sd] >= rate then
					if armReloading(key) then
						if edge then
							SoundLibrary.Play("dryfire", nil, 0.3)
						end
					else
						lastClick[sd] = os.clock()
						shootArm(key)
					end
				end
			end
			prevMouse[sd] = down
		end
		-- (v2.8.2) WARDEN OPTICS: only in FIRST PERSON you look through the lenses - a faint red shade (the combat vision of
		-- tier 3 a strong one); third person is clear. Off in the settings: "Red optics shade".
		do
			local fp = Input.firstPerson == true
			local opt = optics() > 0 and ch ~= nil and not (controller and controller.dead)
			local want = fp and opt and Settings.Get("opticsShade") ~= false
			redVision.Enabled = want
			if want then
				if redOn then
					redVision.TintColor = Color3.fromRGB(255, 150, 150)
					redVision.Contrast = 0.25
					redVision.Saturation = -0.6
				else
					redVision.TintColor = Color3.fromRGB(255, 222, 222)
					redVision.Contrast = 0.06
					redVision.Saturation = -0.12
				end
			end
		end
		-- the cooldowns and the open state on the bar
		for i, b in barButtons do
			local s = bar[i]
			if s then
				local cd = player:GetAttribute("CyCD_" .. s.key)
				local cdF = b:FindFirstChild("CD") :: Frame?
				if cdF then
					local d = s.def.cooldown and s.def.cooldown[s.tier] or 1
					local left = typeof(cd) == "number" and math.max(0, cd - tnow) or 0
					cdF.Size = UDim2.fromScale(1, math.clamp(left / d, 0, 1))
				end
				local st = b:FindFirstChild("State") :: TextLabel?
				if st then
					local open = ch and ch:GetAttribute("Cy_open_" .. s.key)
					local ammo = player:GetAttribute("CyAmmo_" .. s.key)
					local reloading = s.id == "shiftgun" and armReloading(s.key)
					st.Text = reloading and "RELOAD"
						or (s.id == "shiftgun" and open and ("OUT " .. (typeof(ammo) == "number" and ammo or Config.ShiftgunMag[math.max(1, s.tier)])))
						or (s.id == "shiftgun" or s.id == "sickles") and (open and "OUT" or "IN")
						or (s.id == "optics" and #locks > 0 and (#locks .. " LOCKED") or (s.id == "ghostskin" and ch and ch:GetAttribute("Cloaked") and "ACTIVE" or ""))
				end
			end
		end
		barFrame.Visible = #bar > 0 and Settings.Get("cyberHud") ~= false and Settings.Get("hideAll") ~= true and not (controller and controller.car)
		-- the shield / psychosis panel
		local sh = ch and ch:GetAttribute("CyShield")
		local shMax = ch and ch:GetAttribute("CyShieldMax")
		local ps = player:GetAttribute("CyPsycho")
		local showShield = typeof(shMax) == "number" and shMax > 0
		local showPsy = typeof(ps) == "number" and ps > 0
		statusPanel.Visible = (showShield or showPsy) and Settings.Get("hideAll") ~= true
		if showShield then
			shieldFill.Size = UDim2.fromScale(math.clamp((typeof(sh) == "number" and sh or 0) / shMax, 0, 1), 1)
			shieldText.Text = string.format("AEGIS %d / %d", typeof(sh) == "number" and sh or 0, shMax)
		else
			shieldText.Text = ""
			shieldFill.Size = UDim2.fromScale(0, 1)
		end
		-- the locked target (distance) / the hunt arrow
		local me = torsoOf(ch)
		for i = #locks, 1, -1 do
			local l = locks[i]
			local tt = torsoOf(l.model)
			-- (a SENTRY lock stays without optics for a while)
			local keep = optics() > 0 or os.clock() - l.t < 12
			if not l.model.Parent or not tt or l.model:GetAttribute("Dead") == true or not keep then
				dropLock(i)
			elseif me then
				l.label.Text = string.format(l.threat and "THREAT  %dm" or "LOCK  %dm", math.floor((tt.Position - me.Position).Magnitude))
			end
		end
		pickPrimary()
		if lock then
			local tt = torsoOf(lock.model)
			if tt and me then
				-- tier 3: aiming keeps the camera on it
				if optics() >= 3 and controller and controller.aiming then
					local yaw, pitch = yawPitchTo(tt.Position - workspace.CurrentCamera.CFrame.Position)
					local dy = (yaw - Cam.yaw + math.pi) % (2 * math.pi) - math.pi
					if math.abs(dy) < math.rad(50) then
						Cam.yaw += dy * math.min(1, dt * 10)
						Cam.pitch += (pitch - Cam.pitch) * math.min(1, dt * 10)
					end
				end
			end
		end
		if hunt and Cyberware.Tier(eff, "cortex") > 0 then
			local ch2 = hunt.p.Character
			local ad = hunt.hl and (hunt.hl :: any).Adornee
			if ch2 and hunt.hl and not (ad and ad:IsDescendantOf(ch2)) then
				refreshHunt()
			end
			local tt = torsoOf(ch2)
			if tt and me then
				local dist = math.floor((tt.Position - me.Position).Magnitude)
				if hunt.label then
					hunt.label.Text = string.upper(hunt.p.DisplayName) .. "  " .. dist .. "m"
				end
				-- tier 2: an arrow at the screen's edge when it is off screen
				local cam = workspace.CurrentCamera
				local sp, onScreen = cam:WorldToViewportPoint(tt.Position)
				if Cyberware.Tier(eff, "cortex") >= 2 and not onScreen then
					local vs = cam.ViewportSize
					local dir = Vector2.new(sp.X - vs.X / 2, sp.Y - vs.Y / 2)
					if sp.Z < 0 then
						dir = -dir
					end
					dir = dir.Magnitude > 0 and dir.Unit or Vector2.new(0, -1)
					huntArrow.Position = UDim2.fromOffset(vs.X / 2 + dir.X * vs.X * 0.4, vs.Y / 2 + dir.Y * vs.Y * 0.4)
					huntArrow.Text = ">> " .. string.upper(hunt.p.DisplayName) .. " " .. dist .. "m <<"
					huntArrow.Visible = true
				else
					huntArrow.Visible = false
				end
			else
				huntArrow.Visible = false
			end
		else
			huntArrow.Visible = false
		end
		-- (v2.8.1) SENTRY REFLEX: the camera swings onto the shooter in a fifth of a second
		if camTurn then
			local k = math.clamp((os.clock() - camTurn.t0) / 0.2, 0, 1)
			local e = 1 - (1 - k) * (1 - k)
			local dy = (camTurn.yaw - camTurn.y0 + math.pi) % (2 * math.pi) - math.pi
			Cam.yaw = camTurn.y0 + dy * e
			Cam.pitch = camTurn.p0 + (camTurn.pitch - camTurn.p0) * e
			if k >= 1 then
				camTurn = nil
			end
		end
		-- the shooter marker
		if threat and os.clock() < threat.untilT and me then
			local cam = workspace.CurrentCamera
			local sp, onScreen = cam:WorldToViewportPoint(threat.origin)
			local vs = cam.ViewportSize
			local pos = Vector2.new(sp.X, sp.Y)
			if not onScreen then
				local dir = Vector2.new(sp.X - vs.X / 2, sp.Y - vs.Y / 2)
				if sp.Z < 0 then
					dir = -dir
				end
				dir = dir.Magnitude > 0 and dir.Unit or Vector2.new(0, -1)
				pos = Vector2.new(vs.X / 2, vs.Y / 2) + dir * math.min(vs.X, vs.Y) * 0.38
			end
			threatMark.Position = UDim2.fromOffset(pos.X, pos.Y)
			threatMark.Visible = true
		else
			threatMark.Visible = false
		end
		-- frozen in the ice
		local fz = ch and ch:GetAttribute("CyFrozen")
		if typeof(fz) == "number" and tnow < fz then
			overlay.BackgroundColor3 = Color3.fromRGB(190, 230, 255)
			overlay.BackgroundTransparency = math.max(overlay.BackgroundTransparency - 0, 0.55)
		end
		if tick >= 0.15 then
			tick = 0
			updateCloaks()
			updatePsycho()
			if Cyberware.Tier(eff, "lodestone") > 0 then
				updateMagnet()
			elseif magnet then
				magnet.bb.Enabled = false
			end
			if turnUntil > 0 and os.clock() > turnUntil then
				clearTurn()
			end
		end
	end)
end

return CyberClient
