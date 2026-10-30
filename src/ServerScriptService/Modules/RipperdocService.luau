--!nonstrict
-- RipperdocService (v2.8): the ripperdoc's shop next to the red house, and every operation that puts chrome in or takes it out.
--   * the DOC (Config.RipperDocName) stands at the bed (RipperDocSpot). Talk to him: his shop opens (CyberClient).
--     Pick what goes in / comes out, JOIN THE WAITING LIST. One patient at a time: when it is your turn, lie down on the bed
--     (RipperBed) within Config.RipperShowUpTime s. You pay then (Cyberware prices; taking one out costs Config.CyberRemoveShare),
--     he gives you the syringe, you sleep and dream (Config.RipperDreamTime s) and wake up with the new chrome.
--   * he also sells IMPLANT CASES (for a player surgeon to put in somebody else), RIPPER KITS and SYRINGES.
--   * a PLAYER SURGEON: an implant case / a ripper kit used on somebody (GearService fitting). Inside the ripperdoc or the
--     hospital's operating room (SurgeryZone parts) the surgeon earns Config.SurgeonShare of the implant's price.
--     Not asleep while an implant goes in: it hurts. A ripper kit only works on somebody asleep; the implant comes out in a case.
-- The building is imported from the owner's model (build.py); its markers: RipperDocSpot, RipperBed, RipperBoard, SurgeryZone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Cyberware = require(Shared:WaitForChild("Cyberware"))
local Modules = script.Parent
local CyberService = require(Modules:WaitForChild("CyberService"))
local CyberModels = require(Modules:WaitForChild("CyberModels"))
local Persist = require(Modules:WaitForChild("Persist"))
local HospitalService = require(Modules:WaitForChild("HospitalService"))

local RipperdocService = {}

local deps: any = {}
local Remote: RemoteEvent

export type Op = { op: string, id: string?, tier: number?, side: string?, key: string? }
type Entry = { p: Player, ops: { Op }, total: number, since: number }

local queue: { Entry } = {}
local current: Entry? = nil
local busy = false -- (an operation runs)
local doc: Model? = nil
local docArm: BasePart? = nil
local docArmRest: CFrame? = nil

local KIT_PRICE = 150
local SYRINGE_PRICE = 120

------------------------------------------------------------------------
-- the building
------------------------------------------------------------------------

local function find(name: string): BasePart?
	local map = workspace:FindFirstChild("Map")
	local p = map and map:FindFirstChild(name, true)
	return (p and p:IsA("BasePart")) and p or nil
end

-- is this point inside a surgery room (the ripperdoc, the hospital's operating room)?
function RipperdocService.InSurgery(pos: Vector3): boolean
	local map = workspace:FindFirstChild("Map")
	if not map then
		return false
	end
	for _, z in map:GetDescendants() do
		if z.Name == "SurgeryZone" and z:IsA("BasePart") then
			local l = z.CFrame:PointToObjectSpace(pos)
			local h = z.Size / 2
			if math.abs(l.X) <= h.X and math.abs(l.Y) <= h.Y and math.abs(l.Z) <= h.Z then
				return true
			end
		end
	end
	return false
end

local function say(p: Player, text: string)
	Remote:FireClient(p, "ripper", "msg", text)
end

local function cashOf(p: Player): number
	local prof = Persist.Get(p)
	return prof and prof.cash or 0
end

local function pay(p: Player, n: number, why: string): boolean
	if n <= 0 then
		return true
	end
	if Items.IsOwner(p) then
		return true -- (admins operate for free)
	end
	if cashOf(p) < n then
		return false
	end
	deps.SkinService.AddCash(p, -n, why)
	return true
end

------------------------------------------------------------------------
-- the doc himself: a still figure in a long coat, chrome right arm, red optics
------------------------------------------------------------------------

-- (v2.8.1) `desk`: the receptionist at the front desk (the waiting list is signed with her), not the doc
local function buildDoc(spot: BasePart, desk: boolean?): Model
	local m = Instance.new("Model")
	m.Name = desk and "RipperReception" or "RipperDoc"
	local base = spot.CFrame * CFrame.new(0, -spot.Size.Y / 2, 0) -- (his feet)
	-- (v2.8.2) as tall as a player standing next to them (a player's body floats a little over its feet and its head is
	-- a big round one): the whole figure is built a bit bigger
	local K = Config.RipperNpcScale or 1.12
	local skin = desk and Color3.fromRGB(150, 108, 86) or Color3.fromRGB(196, 150, 118)
	local coat = desk and Color3.fromRGB(38, 36, 44) or Color3.fromRGB(214, 216, 210)
	local pants = desk and Color3.fromRGB(26, 26, 30) or Color3.fromRGB(34, 36, 40)
	local function p(name: string, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material?): Part
		local x = Instance.new("Part")
		x.Name = name
		x.Size = size * K
		x.CFrame = base * (CFrame.new(off.Position * K) * off.Rotation)
		x.Color = color
		x.Material = mat or Enum.Material.SmoothPlastic
		x.Anchored = true
		x.CanCollide = name == "Torso"
		x.CanQuery = true
		x.CanTouch = false
		x.TopSurface, x.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		x.Parent = m
		return x
	end
	p("Left Leg", Vector3.new(1, 2, 1), CFrame.new(-0.5, 1, 0), pants)
	p("Right Leg", Vector3.new(1, 2, 1), CFrame.new(0.5, 1, 0), pants)
	local torso = p("Torso", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), coat, Enum.Material.Fabric)
	p("Left Arm", Vector3.new(1, 2, 1), CFrame.new(-1.5, 3, 0), coat, Enum.Material.Fabric)
	local right = p("Right Arm", Vector3.new(1, 2, 1), CFrame.new(1.5, 3, 0), coat, Enum.Material.Fabric)
	local head = p("Head", Vector3.new(2, 1, 1), CFrame.new(0, 4.5, 0), skin)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	if desk then
		-- a short jacket with a red collar, a bob of black hair, a headset with a microphone
		p("Collar", Vector3.new(2.06, 0.3, 1.06), CFrame.new(0, 3.85, 0), Color3.fromRGB(170, 24, 34), Enum.Material.Fabric)
		p("Zip", Vector3.new(0.08, 1.6, 0.04), CFrame.new(0, 3, -0.53), Color3.fromRGB(150, 150, 156), Enum.Material.Metal)
		p("Hair", Vector3.new(1.32, 0.45, 1.32), CFrame.new(0, 5.0, 0.04), Color3.fromRGB(18, 16, 18), Enum.Material.Fabric)
		p("HairBack", Vector3.new(1.32, 0.9, 0.3), CFrame.new(0, 4.55, 0.55), Color3.fromRGB(18, 16, 18), Enum.Material.Fabric)
		p("Headset", Vector3.new(0.16, 0.5, 0.5), CFrame.new(0.66, 4.55, 0), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
		p("Mic", Vector3.new(0.06, 0.06, 0.6), CFrame.new(0.6, 4.25, -0.35), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
		p("MicTip", Vector3.new(0.14, 0.14, 0.14), CFrame.new(0.55, 4.25, -0.66), Color3.fromRGB(255, 60, 70), Enum.Material.Neon)
	else
		-- the coat: tails down to the knees, lapels, a stained apron, a pocket with pens
		local tails = p("CoatTails", Vector3.new(2.1, 1.3, 1.06), CFrame.new(0, 1.45, 0), coat, Enum.Material.Fabric)
		tails.CanCollide = false
		p("Apron", Vector3.new(1.5, 2.4, 0.06), CFrame.new(0, 2.25, -0.54), Color3.fromRGB(70, 90, 96), Enum.Material.Fabric)
		p("Stain", Vector3.new(0.4, 0.3, 0.02), CFrame.new(0.3, 2.0, -0.58), Color3.fromRGB(110, 20, 22), Enum.Material.Fabric)
		p("Stain", Vector3.new(0.2, 0.5, 0.02), CFrame.new(-0.35, 1.5, -0.58), Color3.fromRGB(96, 18, 20), Enum.Material.Fabric)
		p("Pocket", Vector3.new(0.5, 0.4, 0.04), CFrame.new(-0.55, 3.45, -0.53), coat, Enum.Material.Fabric)
		p("Pen", Vector3.new(0.05, 0.3, 0.05), CFrame.new(-0.45, 3.7, -0.54), Color3.fromRGB(30, 30, 30), Enum.Material.Plastic)
		-- grey hair, a beard
		p("Hair", Vector3.new(1.3, 0.3, 1.3), CFrame.new(0, 5.05, 0.05), Color3.fromRGB(150, 150, 150), Enum.Material.Fabric)
		p("Beard", Vector3.new(0.9, 0.35, 0.3), CFrame.new(0, 4.05, -0.45), Color3.fromRGB(140, 140, 140), Enum.Material.Fabric)
	end
	m.PrimaryPart = torso
	m:SetAttribute("BodyScale", K) -- (the implants on them are built at this size too)
	m.Parent = workspace:FindFirstChild("Map") or workspace
	if desk then
		-- her chrome: one red lens
		CyberModels.DressOne(m, "optics", 1, nil)
	else
		-- his own chrome: three red lenses, a cortex jack and a chrome right arm
		CyberModels.DressOne(m, "optics", 3, nil)
		CyberModels.DressOne(m, "cortex", 3, nil)
		CyberModels.DressOne(m, "titan_R", 3, "CHROME:SKELETAL")
		right.Transparency = 1
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	-- a name over his head and the prompt
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(240, 46)
	bb.StudsOffset = Vector3.new(0, 2.2 * K, 0)
	bb.MaxDistance = 60
	bb.AlwaysOnTop = false
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.Sarpanch
	t.TextColor3 = Color3.fromRGB(255, 70, 70)
	t.TextStrokeTransparency = 0.4
	t.TextScaled = true
	t.Text = desk and "FRONT DESK\nWAITING LIST" or (Config.RipperDocName .. "\nRIPPERDOC")
	t.Parent = bb
	bb.Parent = head
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TalkPrompt"
	prompt.ActionText = desk and "Sign up" or "Talk"
	prompt.ObjectText = desk and "Front desk: the waiting list" or Config.RipperDocName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.Parent = torso
	prompt.Triggered:Connect(function(pl)
		if desk then
			Remote:FireClient(pl, "ripper", "open", RipperdocService.QueueInfo(pl))
			return
		end
		-- (v2.8.1) the doc only works: the list is at the front desk
		local q = RipperdocService.QueueInfo(pl)
		if q == 0 then
			say(pl, "YOUR TURN. LIE DOWN ON THE TABLE.")
		elseif q > 0 then
			say(pl, "YOU ARE NUMBER " .. q .. ". WAIT OUT THERE.")
		else
			say(pl, "SIGN THE LIST AT THE FRONT DESK FIRST. I DO NOT DO PAPERWORK.")
		end
	end)
	if not desk then
		docArm = right
		docArmRest = right.CFrame
	end
	return m
end

-- the doc turns his chrome arm towards the bed, a syringe in the hand
local function docInject(target: Vector3)
	local arm = docArm
	local rest = docArmRest
	if not arm or not rest then
		return
	end
	local shoulder = rest * CFrame.new(0, 0.5, 0)
	local dir = (target - shoulder.Position)
	local aim = CFrame.lookAt(shoulder.Position, shoulder.Position + dir) * CFrame.Angles(math.rad(90), 0, 0) * CFrame.new(0, -0.5, 0)
	local syringe = Instance.new("Part")
	syringe.Name = "Syringe"
	syringe.Size = Vector3.new(0.12, 0.7, 0.12)
	syringe.Color = Color3.fromRGB(120, 220, 255)
	syringe.Material = Enum.Material.Neon
	syringe.Anchored, syringe.CanCollide, syringe.CanQuery, syringe.CanTouch = true, false, false, false
	syringe.CFrame = arm.CFrame * CFrame.new(0, -1.3, 0)
	syringe.Parent = doc
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = arm, syringe
	w.Parent = syringe
	syringe.Anchored = false
	syringe.Massless = true
	TweenService:Create(arm, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { CFrame = aim }):Play()
	task.delay(2.6, function()
		syringe:Destroy()
		TweenService:Create(arm, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { CFrame = rest }):Play()
	end)
end

------------------------------------------------------------------------
-- the waiting list
------------------------------------------------------------------------

local function board()
	local b = find("RipperBoard")
	if not b then
		return
	end
	local lines = {}
	if current then
		table.insert(lines, "NOW: " .. string.upper(current.p.DisplayName))
	else
		table.insert(lines, "NOW: NOBODY - SIGN UP AT THE FRONT DESK")
	end
	for i, e in queue do
		if i > 6 then
			table.insert(lines, "... +" .. tostring(#queue - 6))
			break
		end
		table.insert(lines, tostring(i) .. ". " .. string.upper(e.p.DisplayName))
	end
	b:SetAttribute("Queue", table.concat(lines, "\n"))
end

function RipperdocService.QueueInfo(p: Player): number
	if current and current.p == p then
		return 0
	end
	for i, e in queue do
		if e.p == p then
			return i
		end
	end
	return -1
end

local function publishQueue()
	for _, pl in Players:GetPlayers() do
		local pos = RipperdocService.QueueInfo(pl)
		pl:SetAttribute("RipperQueue", pos >= 0 and pos or nil)
	end
	board()
end

-- the ops a patient picked: checked against his body; returns (clean ops, total) or nil + why
local function check(p: Player, opsIn: any): ({ Op }?, number, string?)
	if typeof(opsIn) ~= "table" then
		return nil, 0, "nothing picked"
	end
	local list = CyberService.List(p)
	local ops: { Op } = {}
	local total = 0
	local removes, installs = {}, {}
	for i, o in opsIn do
		if i > 8 or typeof(o) ~= "table" then
			break
		end
		if o.op == "out" and typeof(o.key) == "string" and list[o.key] then
			table.insert(removes, { op = "out", key = o.key })
		elseif o.op == "in" and typeof(o.id) == "string" and typeof(o.tier) == "number" then
			local d = Cyberware.ById[o.id]
			local side = (o.side == "L" or o.side == "R") and o.side or nil
			if d then
				table.insert(installs, { op = "in", id = o.id, tier = math.clamp(math.floor(o.tier), 1, d.tiers), side = side })
			end
		end
	end
	for _, r in removes do
		local id = Cyberware.Split(r.key)
		total += math.floor(Cyberware.Price(id, list[r.key]) * Config.CyberRemoveShare)
		list[r.key] = nil
		table.insert(ops, r)
	end
	for _, o in installs do
		local d = Cyberware.ById[o.id]
		if d.admin and not Items.Has(p, d.id) then
			return nil, 0, d.name .. " is for admins only"
		end
		local key = Cyberware.Key(o.id, o.side)
		local slot = Cyberware.SlotKey(d, o.side)
		for k in list do
			local kid, kside = Cyberware.Split(k)
			local kd = Cyberware.ById[kid]
			if kd and k ~= key and Cyberware.SlotKey(kd, kside) == slot then
				return nil, 0, "the " .. Cyberware.SlotName[d.slot] .. " slot is taken by " .. kd.name .. " (take it out first)"
			end
		end
		local had = list[key] or 0
		if had >= o.tier then
			return nil, 0, d.name .. " is already in"
		end
		-- an upgrade pays the difference
		total += Cyberware.Price(o.id, o.tier) - (had > 0 and Cyberware.Price(o.id, had) or 0)
		list[key] = o.tier
		table.insert(ops, o)
	end
	if #ops == 0 then
		return nil, 0, "nothing picked"
	end
	return ops, total, nil
end

local function enqueue(p: Player, opsIn: any)
	local ops, total, why = check(p, opsIn)
	if not ops then
		say(p, string.upper(why or "no"))
		return
	end
	if not Items.IsOwner(p) and cashOf(p) < total then
		say(p, string.format("THAT IS $%d. YOU HAVE $%d.", total, cashOf(p)))
		return
	end
	-- already waiting: the new list replaces the old one
	for i, e in queue do
		if e.p == p then
			table.remove(queue, i)
			break
		end
	end
	if current and current.p == p then
		current.ops, current.total = ops, total
		say(p, "UPDATED. LIE DOWN ON THE BED.")
		return
	end
	table.insert(queue, { p = p, ops = ops, total = total, since = os.clock() })
	publishQueue()
	say(p, string.format("YOU ARE ON THE LIST (#%d). $%d WHEN IT IS YOUR TURN.", #queue, total))
end

local function leave(p: Player)
	for i, e in queue do
		if e.p == p then
			table.remove(queue, i)
		end
	end
	if current and current.p == p and not busy then
		current = nil
	end
	publishQueue()
end

local function nextPatient()
	if busy then
		return
	end
	while #queue > 0 do
		local e = table.remove(queue, 1)
		if e and e.p.Parent then
			current = e
			e.since = os.clock()
			Remote:FireClient(e.p, "ripper", "turn", Config.RipperShowUpTime)
			say(e.p, "YOUR TURN. LIE DOWN ON THE BED.")
			publishQueue()
			return
		end
	end
	current = nil
	publishQueue()
end

-- the patient lies down: pay, syringe, dream, chrome
local function operate(p: Player)
	local e = current
	if busy or not e or e.p ~= p then
		say(p, "WAIT YOUR TURN.")
		return
	end
	local char = p.Character
	local torso = char and char:FindFirstChild("Torso")
	local bed = find("RipperBed")
	if not char or not torso or not bed or char:GetAttribute("Dead") then
		return
	end
	-- the prices may have changed (another surgeon, an admin): check again
	local ops, total, why = check(p, e.ops)
	if not ops then
		say(p, string.upper(why or "no"))
		current = nil
		task.defer(nextPatient)
		return
	end
	if not pay(p, total, "ripperdoc") then
		say(p, string.format("YOU CAN NOT PAY $%d. NEXT!", total))
		current = nil
		task.defer(nextPatient)
		return
	end
	busy = true
	-- (v2.8.1) you lie on the table, face up, the head on the raised end (+X), for the whole operation
	local lieCF = HospitalService.LieOn(bed, bed.Position + bed.CFrame.RightVector * 3)
	HospitalService.Pose(char, lieCF, "lie", Config.RipperDreamTime + 2.2)
	task.wait(0.4)
	docInject(bed.Position + Vector3.new(0, 1, 0))
	Remote:FireClient(p, "ripper", "dream", Config.RipperDreamTime)
	task.wait(0.9)
	if char.Parent and not char:GetAttribute("Dead") then
		deps.DamageService.Sleep(char, Config.RipperDreamTime, nil)
	end
	-- the work is done while you dream
	for _, o in ops do
		if o.op == "out" and o.key then
			CyberService.Remove(p, o.key)
		elseif o.op == "in" and o.id and o.tier then
			CyberService.Install(p, o.id, o.tier, o.side)
		end
	end
	pcall(deps.GoreService.Sound, "ratchet", bed, 1)
	task.delay(Config.RipperDreamTime, function()
		if p.Parent then
			Remote:FireClient(p, "ripper", "done")
			say(p, "WELCOME BACK. THE CHROME TOOK.")
		end
		busy = false
		current = nil
		nextPatient()
	end)
end

------------------------------------------------------------------------
-- selling: implant cases, ripper kits, syringes
------------------------------------------------------------------------

local function dropFor(p: Player, kind: string): Instance?
	local char = p.Character
	local torso = char and char:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return nil
	end
	local cf = torso.CFrame * CFrame.new(0, 0.5, -3)
	return deps.PropService.Place(kind, cf, p)
end

-- writes the implant on a case (attributes + the name on the lid + the glow in its colour)
local function labelCase(case: Instance, id: string, tier: number)
	local d = Cyberware.ById[id]
	if not d or not case:IsA("Model") then
		return
	end
	case:SetAttribute("CyId", id)
	case:SetAttribute("CyTier", tier)
	case.Name = d.name .. " T" .. tier
	local lid = case:FindFirstChild("Lid")
	if lid and lid:IsA("BasePart") then
		local g = Instance.new("SurfaceGui")
		g.Face = Enum.NormalId.Top
		g.CanvasSize = Vector2.new(280, 180)
		g.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.Sarpanch
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(120, 230, 255)
		t.Text = d.name .. "\nTIER " .. tier
		t.Parent = g
		g.Parent = lid
	end
end
RipperdocService.LabelCase = labelCase

local function buyCase(p: Player, id: any, tier: any)
	local d = typeof(id) == "string" and Cyberware.ById[id] or nil
	if not d or typeof(tier) ~= "number" then
		return
	end
	tier = math.clamp(math.floor(tier), 1, d.tiers)
	if d.admin and not Items.Has(p, d.id) then
		say(p, "ADMINS ONLY.")
		return
	end
	local price = Cyberware.Price(id, tier)
	if not pay(p, price, "implant case") then
		say(p, string.format("THAT IS $%d.", price))
		return
	end
	local case = dropFor(p, "implantcase")
	if case then
		labelCase(case, id, tier)
		say(p, d.name .. " (TIER " .. tier .. ") IN A CASE. SOMEBODY ELSE HAS TO PUT IT IN YOU (F, AIMED AT THEM).")
	end
end

local function buySimple(p: Player, kind: string)
	local price = kind == "ripperkit" and KIT_PRICE or SYRINGE_PRICE
	if not pay(p, price, kind) then
		say(p, string.format("THAT IS $%d.", price))
		return
	end
	dropFor(p, kind)
end

------------------------------------------------------------------------
-- player surgeons (GearService fitting)
------------------------------------------------------------------------

local function onCyber(surgeon: Player, target: Model, item: Model, key: string)
	local patient = Players:GetPlayerFromCharacter(target)
	if not patient then
		return
	end
	local torso = target:FindFirstChild("Torso")
	local sTorso = surgeon.Character and surgeon.Character:FindFirstChild("Torso")
	local inRoom = sTorso and sTorso:IsA("BasePart") and RipperdocService.InSurgery(sTorso.Position)
	if key == "Cyber" then
		local id = item:GetAttribute("CyId")
		local tier = item:GetAttribute("CyTier")
		local d = typeof(id) == "string" and Cyberware.ById[id] or nil
		if not d or typeof(tier) ~= "number" then
			return
		end
		-- a sided implant: the right side first, then the left
		local side = nil
		local sided = Cyberware.Key(id, "R") ~= id
		if sided then
			side = CyberService.CanInstall(patient, id, tier, "R") == nil and "R" or "L"
		end
		local why = CyberService.CanInstall(patient, id, tier, side)
		if why then
			Remote:FireClient(surgeon, "ripper", "msg", string.upper(why))
			return
		end
		if d.admin and not Items.IsOwner(patient) then
			CyberService.Gift(patient, id) -- (an admin's case: whoever gets it may have it)
		end
		CyberService.Install(patient, id, tier, side)
		pcall(deps.OwnershipService.DropItem, item)
		item:Destroy()
		-- awake: it hurt
		if target:GetAttribute("Asleep") ~= true and torso and torso:IsA("BasePart") then
			pcall(function()
				deps.DamageService.ApplyDamage(target, "Torso", 18, torso.Position, { cause = "Implant surgery", allowSever = false, attacker = surgeon, bleed = 0.6, bleedTime = 6 })
				deps.DamageService.Knock(target, "Torso", nil, 1.2)
			end)
		end
		pcall(deps.GoreService.Sound, "metal", torso, 1)
		Remote:FireClient(patient, "ripper", "msg", string.upper(surgeon.DisplayName) .. " PUT " .. d.name .. " IN YOU.")
		if inRoom and surgeon ~= patient then
			local fee = math.floor(Cyberware.Price(id, tier) * Config.SurgeonShare)
			if fee > 0 then
				deps.SkinService.AddCash(surgeon, fee, "surgery")
				Remote:FireClient(surgeon, "ripper", "msg", string.format("SURGERY DONE: +$%d", fee))
			end
		end
	elseif string.sub(key, 1, 8) == "Uncyber:" then
		if target:GetAttribute("Asleep") ~= true then
			Remote:FireClient(surgeon, "ripper", "msg", "THEY HAVE TO BE ASLEEP.")
			return
		end
		local implantKey = string.sub(key, 9)
		local list = CyberService.List(patient)
		local tier = list[implantKey]
		if not tier then
			return
		end
		local id = CyberService.Remove(patient, implantKey)
		if not id then
			return
		end
		local d = Cyberware.ById[id]
		pcall(deps.GoreService.Sound, "gore", torso, 0.7)
		Remote:FireClient(patient, "ripper", "msg", string.upper(surgeon.DisplayName) .. " TOOK " .. (d and d.name or id) .. " OUT OF YOU.")
		-- the implant comes out in a case (an admin's protocol just shuts down)
		if d and not d.admin and torso and torso:IsA("BasePart") then
			local case = deps.PropService.Place("implantcase", torso.CFrame * CFrame.new(0, 1.5, 0), surgeon)
			if case then
				labelCase(case, id, tier)
			end
		end
		if inRoom and d then
			local fee = math.floor(Cyberware.Price(id, tier) * Config.SurgeonShare * 0.5)
			if fee > 0 then
				deps.SkinService.AddCash(surgeon, fee, "surgery")
			end
		end
	end
end

------------------------------------------------------------------------

function RipperdocService.Init(d: any)
	deps = d
	Remote = CyberService.Remote
	deps.GearService.OnCyber = onCyber

	Remote.OnServerEvent:Connect(function(p, action, sub, a, b)
		if action ~= "ripper" then
			return
		end
		if sub == "queue" then
			enqueue(p, a)
		elseif sub == "leave" then
			leave(p)
		elseif sub == "case" then
			buyCase(p, a, b)
		elseif sub == "kit" then
			buySimple(p, "ripperkit")
		elseif sub == "syringe" then
			buySimple(p, "syringe")
		elseif sub == "info" then
			Remote:FireClient(p, "ripper", "info", RipperdocService.QueueInfo(p))
		end
	end)

	task.spawn(function()
		-- the map is there once WorldSetup ran
		local spot
		for _ = 1, 50 do
			spot = find("RipperDocSpot")
			if spot then
				break
			end
			task.wait(0.2)
		end
		if spot then
			doc = buildDoc(spot)
		end
		-- (v2.8.1) the front desk: the receptionist, and the counter itself takes the sign-up too
		local deskSpot = find("RipperDeskSpot")
		if deskSpot then
			buildDoc(deskSpot, true)
		end
		local desk = find("RipperFrontDesk")
		if desk then
			local pr = Instance.new("ProximityPrompt")
			pr.Name = "DeskPrompt"
			pr.ActionText = "Sign up"
			pr.ObjectText = "Waiting list"
			pr.HoldDuration = 0
			pr.MaxActivationDistance = 9
			pr.RequiresLineOfSight = false
			pr.KeyboardKeyCode = Enum.KeyCode.F
			pr.Parent = desk
			pr.Triggered:Connect(function(pl)
				Remote:FireClient(pl, "ripper", "open", RipperdocService.QueueInfo(pl))
			end)
		end
		local bed = find("RipperBed")
		if bed then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "BedPrompt"
			prompt.ActionText = "Lie down"
			prompt.ObjectText = "Operating table"
			prompt.HoldDuration = 0.6
			prompt.MaxActivationDistance = 9
			prompt.RequiresLineOfSight = false
			prompt.Parent = bed
			prompt.Triggered:Connect(function(pl)
				operate(pl)
			end)
		end
		board()
	end)

	Players.PlayerRemoving:Connect(function(p)
		leave(p)
		if current and current.p == p and not busy then
			current = nil
			nextPatient()
		end
	end)

	-- the next one when nobody is on the table; a patient who does not show up loses the turn
	task.spawn(function()
		while true do
			task.wait(1)
			if not busy then
				if current and (not current.p.Parent or os.clock() - current.since > Config.RipperShowUpTime) then
					if current.p.Parent then
						say(current.p, "YOU DID NOT SHOW UP. BACK OF THE LINE.")
					end
					current = nil
				end
				if not current then
					nextPatient()
				end
			end
		end
	end)
end

return RipperdocService
