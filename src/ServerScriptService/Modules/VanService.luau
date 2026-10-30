--!nonstrict
-- VanService (v2.8): the VAN's back doors and its cargo.
--   * a prompt at the back opens / closes the two doors (they swing out on their hinges).
--   * (v2.8.2) the back has two benches with six places. Anybody can SIT on one ("Sit in the back", F; Space gets you up
--     again) and ride along: the body is held on the bench, it does not tumble about.
--   * doors open and you CARRY somebody (dragging / holding a body): "Put them in" - they are sat on a bench and held
--     there (they can not get out by themselves). "Take them out" (doors open) lets everybody out at the back; a
--     wrecked van lets everybody go. (A captive player is let go after Config.VanHoldTime s, so nobody is stuck forever.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Poses = require(Shared:WaitForChild("Poses"))

local VanService = {}

local deps: any = {}
type Rider = { body: Model, welds: { Instance }, seat: number, t0: number, held: boolean, off: { Instance } }
local riders: { [Model]: { Rider } } = {}

-- the six places on the two benches (van space x, z): you sit with your back to the wall, facing in
local SEATS = { { -2.5, 1.7 }, { -2.5, 4.0 }, { -2.5, 6.3 }, { 2.5, 1.7 }, { 2.5, 4.0 }, { 2.5, 6.3 } }
local SEAT_Y = 5.3 -- (the bench top is at 3.8: the torso sits 1.5 over it)

local function doorsOpen(van: Model): boolean
	return van:GetAttribute("DoorsOpen") == true
end

local function setDoors(van: Model, open: boolean)
	van:SetAttribute("DoorsOpen", open or nil)
	for _, d in van:GetDescendants() do
		if d:IsA("Weld") and d.Name == "DoorHinge" then
			local closed = d:GetAttribute("ClosedC0")
			local side = d:GetAttribute("Side")
			if typeof(closed) == "CFrame" and typeof(side) == "number" then
				d.C0 = open and (closed * CFrame.Angles(0, side * math.rad(100), 0)) or closed
			end
		end
	end
	local floor = van:FindFirstChild("CargoFloor")
	if floor then
		pcall(deps.GoreService.Sound, "door", floor, 1)
	end
end

-- where the torso sits on place i (world)
local function seatCF(van: Model, i: number, scale: number): CFrame?
	local chassis = van.PrimaryPart
	if not chassis then
		return nil
	end
	local x, z = SEATS[i][1], SEATS[i][2]
	local at = Vector3.new(x, SEAT_Y + (scale - 1) * 1.5, z)
	local face = x < 0 and Vector3.new(1, 0, 0) or Vector3.new(-1, 0, 0)
	return chassis.CFrame * CFrame.lookAt(at, at + face)
end

local function freeSeat(van: Model, prefer: Vector3?): number?
	local used = {}
	local list: { Rider } = riders[van] or {}
	for _, r in list do
		used[r.seat] = true
	end
	local best, bestD = nil, math.huge
	for i = 1, #SEATS do
		if not used[i] then
			local d = 0
			if prefer then
				local cf = seatCF(van, i, 1)
				d = cf and (cf.Position - prefer).Magnitude or 0
			end
			if d < bestD then
				best, bestD = i, d
			end
		end
	end
	return best
end

local function riderOf(body: Model): (Model?, Rider?, number?)
	for van, list in riders do
		for i, r in list do
			if r.body == body then
				return van, r, i
			end
		end
	end
	return nil, nil, nil
end

-- sits a body on a bench and holds it there: the parts laid out sitting, welded to the van, its own joints and muscles
-- off while it rides (the van's machine moves it; the body's machine does nothing: InVan)
local function seatBody(van: Model, body: Model, i: number, held: boolean): boolean
	local floor = van:FindFirstChild("CargoFloor")
	if not floor or not floor:IsA("BasePart") then
		return false
	end
	local bs = body:GetAttribute("BodyScale")
	local S = typeof(bs) == "number" and bs or 1
	local cf = seatCF(van, i, S)
	if not cf then
		return false
	end
	pcall(deps.OwnershipService.EndDrag, body)
	local off = {}
	for _, d in body:GetDescendants() do
		if d:IsA("Constraint") and d.Enabled then
			d.Enabled = false
			table.insert(off, d)
		end
	end
	local welds = {}
	for _, name in Poses.PARTS do
		local part = body:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local where = Poses.Where("sit", cf, name, S)
			if where then
				part.CFrame = where
				part.AssemblyLinearVelocity = Vector3.zero
				local w = Instance.new("WeldConstraint")
				w.Name = "VanHold"
				w.Part0 = floor
				w.Part1 = part
				w.Parent = floor
				table.insert(welds, w)
			end
		end
	end
	body:SetAttribute("InVan", held and "held" or "seat")
	local list = riders[van] or {}
	riders[van] = list
	table.insert(list, { body = body, welds = welds, seat = i, t0 = os.clock(), held = held, off = off })
	pcall(deps.GoreService.Sound, held and "thud" or "door", floor, 0.8)
	return true
end

local function release(van: Model, r: Rider, push: boolean)
	for _, w in r.welds do
		w:Destroy()
	end
	for _, c in r.off do
		if c.Parent then
			(c :: any).Enabled = true
		end
	end
	r.body:SetAttribute("InVan", nil)
	local chassis = van.PrimaryPart
	-- out at the back, standing
	if chassis and r.body.Parent and van.Parent then
		pcall(function()
			r.body:PivotTo(chassis.CFrame * CFrame.new(SEATS[r.seat][1] * 0.3, 3.4, 13.2))
		end)
	end
	local p = Players:GetPlayerFromCharacter(r.body)
	if p then
		for _, d in r.body:GetDescendants() do
			if d:IsA("BasePart") and not d.Anchored then
				pcall(function()
					d:SetNetworkOwner(p)
				end)
			end
		end
	end
	if push and chassis then
		deps.DamageService.Blast(r.body, chassis.CFrame.LookVector * 12 + Vector3.new(0, 5, 0), 1.2)
	end
end

local function unloadAll(van: Model)
	local list = riders[van]
	if not list then
		return
	end
	for _, r in list do
		if r.body.Parent then
			release(van, r, r.held)
		end
	end
	riders[van] = nil
end

local function load(p: Player, van: Model)
	if not doorsOpen(van) then
		deps.Remote:FireClient(p, "ripper", "msg", "OPEN THE BACK FIRST.")
		return
	end
	local body = deps.OwnershipService.HeldBody(p)
	local floor = van:FindFirstChild("CargoFloor")
	local torso = body and body:FindFirstChild("Torso")
	if not body or not floor or not floor:IsA("BasePart") or not torso or not torso:IsA("BasePart") then
		deps.Remote:FireClient(p, "ripper", "msg", "CARRY SOMEBODY HERE (GRAB A BODY) TO PUT THEM IN.")
		return
	end
	if (torso.Position - floor.Position).Magnitude > 16 or body:GetAttribute("InVan") then
		return
	end
	-- the far end first
	local chassis = van.PrimaryPart
	local slot = freeSeat(van, chassis and (chassis.CFrame * CFrame.new(0, 5, 0)).Position or nil)
	if not slot then
		deps.Remote:FireClient(p, "ripper", "msg", "THE VAN IS FULL.")
		return
	end
	deps.OwnershipService.ReleaseAll(p)
	seatBody(van, body, slot, true)
end

-- (v2.8.2) a player sits down on a bench by choice
local function sitDown(p: Player, van: Model)
	local char = p.Character
	local torso = char and char:FindFirstChild("Torso")
	if not char or not torso or not torso:IsA("BasePart") or char:GetAttribute("Dead") or char:GetAttribute("InVan") then
		return
	end
	local slot = freeSeat(van, torso.Position)
	if not slot then
		deps.Remote:FireClient(p, "ripper", "msg", "NO ROOM ON THE BENCHES.")
		return
	end
	deps.OwnershipService.ReleaseAll(p)
	seatBody(van, char, slot, false)
end

function VanService.Setup(van: Model)
	if not van:GetAttribute("Van") or van:GetAttribute("VanReady") then
		return
	end
	van:SetAttribute("VanReady", true)
	local door = van:FindFirstChild("BackDoorR")
	local floor = van:FindFirstChild("CargoFloor")
	if door and door:IsA("BasePart") then
		local pr = Instance.new("ProximityPrompt")
		pr.ActionText = "Open the back"
		pr.ObjectText = "Van"
		pr.HoldDuration = 0.3
		pr.MaxActivationDistance = 9
		pr.RequiresLineOfSight = false
		pr.Parent = door
		pr.Triggered:Connect(function()
			setDoors(van, not doorsOpen(van))
			pr.ActionText = doorsOpen(van) and "Close the back" or "Open the back"
		end)
	end
	if floor and floor:IsA("BasePart") then
		local put = Instance.new("ProximityPrompt")
		put.ActionText = "Put them in"
		put.ObjectText = "Van (carry somebody)"
		put.HoldDuration = 0.4
		put.MaxActivationDistance = 12
		put.RequiresLineOfSight = false
		put.KeyboardKeyCode = Enum.KeyCode.F
		put.UIOffset = Vector2.new(0, -70) -- (not on top of the doors' prompt)
		put.Parent = floor
		put.Triggered:Connect(function(p)
			load(p, van)
		end)
		local out = Instance.new("ProximityPrompt")
		out.ActionText = "Take them out"
		out.ObjectText = "Van"
		out.HoldDuration = 0.8
		out.MaxActivationDistance = 12
		out.RequiresLineOfSight = false
		out.KeyboardKeyCode = Enum.KeyCode.R
		out.UIOffset = Vector2.new(0, 70)
		out.Parent = floor
		out.Triggered:Connect(function()
			if doorsOpen(van) then
				unloadAll(van)
			end
		end)
	end
	-- (v2.8.2) the benches: sit down
	for _, b in van:GetChildren() do
		if b:IsA("BasePart") and b.Name == "Bench" then
			local sit = Instance.new("ProximityPrompt")
			sit.ActionText = "Sit in the back"
			sit.ObjectText = "Van bench (Space: get up)"
			sit.HoldDuration = 0.2
			sit.MaxActivationDistance = 8
			sit.RequiresLineOfSight = false
			sit.KeyboardKeyCode = Enum.KeyCode.F
			sit.Parent = b
			sit.Triggered:Connect(function(p)
				sitDown(p, van)
			end)
		end
	end
	van:GetAttributeChangedSignal("Wrecked"):Connect(function()
		if van:GetAttribute("Wrecked") then
			unloadAll(van)
		end
	end)
	van.Destroying:Connect(function()
		unloadAll(van)
	end)
end

function VanService.Init(d: any)
	deps = d
	local prev = deps.PropService.OnPlaced
	deps.PropService.OnPlaced = function(inst)
		if prev then
			prev(inst)
		end
		if inst:IsA("Model") and inst:GetAttribute("Van") then
			VanService.Setup(inst)
		end
	end
	-- a player who sits by choice gets up with Space ("vanout")
	deps.Remote.OnServerEvent:Connect(function(p, action)
		if action ~= "vanout" or not p.Character then
			return
		end
		local van, r, i = riderOf(p.Character)
		if van and r and i and not r.held then
			release(van, r, false)
			table.remove(riders[van], i)
		end
	end)
	-- the dead are let go; a captive player after Config.VanHoldTime s (nobody is stuck in there forever)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for van, list in riders do
				for i = #list, 1, -1 do
					local r = list[i]
					local p = Players:GetPlayerFromCharacter(r.body)
					local gone = not r.body.Parent or not van.Parent or r.body:GetAttribute("Dead") == true
						or (p and p.Character ~= r.body) or (p and r.held and now - r.t0 > Config.VanHoldTime)
					if gone then
						if r.body.Parent then
							release(van, r, r.held and van.Parent ~= nil)
						end
						table.remove(list, i)
					end
				end
				if #list == 0 then
					riders[van] = nil
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		if p.Character then
			local van, r, i = riderOf(p.Character)
			if van and r and i then
				release(van, r, false)
				table.remove(riders[van], i)
			end
		end
	end)
end

return VanService
