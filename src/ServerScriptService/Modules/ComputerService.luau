--!nonstrict
-- ComputerService (v2.9): the computers. A computer is a terminal you can set down (the spawn menu) or find standing
-- in the ripperdoc. Walk up to it and the prompt opens its screen (ChipClient): buy chips, program a blank chip into a
-- virus, or bake a virus into one of your videos (a trojan). The money and the chips themselves live in ChipService -
-- this only owns the terminals in the world and the "are you at a computer" check.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local ComputerService = {}

local deps: any = {}
local Remote: RemoteEvent
local USE_RANGE = 14

local function torsoOf(p: Player): BasePart?
	local c = p.Character
	local t = c and c:FindFirstChild("Torso")
	return (t and t:IsA("BasePart")) and t or nil
end

-- is this player standing at a computer?
function ComputerService.Near(p: Player): boolean
	local torso = torsoOf(p)
	if not torso then
		return false
	end
	for _, m in CollectionService:GetTagged("Computer") do
		local root = m:IsA("Model") and m.PrimaryPart or (m:IsA("BasePart") and m)
		if root and root:IsDescendantOf(workspace) and (root.Position - torso.Position).Magnitude < USE_RANGE then
			return true
		end
	end
	return false
end

-- give a computer model its prompt + tag (once)
local function wire(m: Instance)
	if not m:IsA("Model") or not m:GetAttribute("Computer") or m:GetAttribute("Wired") then
		return
	end
	local root = m.PrimaryPart or m:FindFirstChild("Monitor")
	if not root or not root:IsA("BasePart") then
		return
	end
	m:SetAttribute("Wired", true)
	CollectionService:AddTag(m, "Computer")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ComputerPrompt"
	prompt.ActionText = "Use"
	prompt.ObjectText = "Computer"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = USE_RANGE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.Parent = root
	prompt.Triggered:Connect(function(pl)
		Remote:FireClient(pl, "pc", "open")
	end)
end

-- a fixed terminal (ripperdoc): a computer that is always there
local function buildFixed(cf: CFrame)
	local ok, m = pcall(function()
		return deps.PropBuilders.computer(cf)
	end)
	if not ok or not m then
		return
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	m.Parent = workspace:FindFirstChild("Map") or workspace
	wire(m)
end

function ComputerService.Init(d: any)
	deps = d
	Remote = d.ChipService.Remote
	-- ChipService asks us whether a player is at a computer (buying / programming)
	d.ChipService.NearComputer = ComputerService.Near

	-- any computer placed from the spawn menu gets a prompt
	local prevPlaced = deps.PropService.OnPlaced
	deps.PropService.OnPlaced = function(inst: Instance)
		if prevPlaced then
			prevPlaced(inst)
		end
		wire(inst)
	end
	for _, m in workspace:GetDescendants() do
		if m:IsA("Model") and m:GetAttribute("Computer") then
			wire(m)
		end
	end

	-- two terminals at the ripperdoc's front desk (the cyberdeck lives next to the chrome)
	task.spawn(function()
		local map
		for _ = 1, 50 do
			map = workspace:FindFirstChild("Map")
			if map and map:FindFirstChild("RipperFrontDesk", true) then
				break
			end
			task.wait(0.2)
		end
		local desk = map and map:FindFirstChild("RipperFrontDesk", true)
		if desk and desk:IsA("BasePart") then
			-- against the wall beside the waiting-room desk, facing into the room
			-- Build a grounded workstation beside the desk; the terminal base rests on its top.
			for _, z in { 2, -4 } do
				local pos = desk.Position + Vector3.new(-9, 0, z)
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Exclude
				rp.FilterDescendantsInstances = { desk }
				local hit = workspace:Raycast(pos + Vector3.new(0, 1, 0), Vector3.new(0, -20, 0), rp)
				local floorY = hit and hit.Position.Y or desk.Position.Y - 3.45
				local surface = floorY + 2.8
				local station = Instance.new("Model")
				station.Name = "RipperdocWorkstation"
				local function solid(name, size, at)
					local part = Instance.new("Part")
					part.Name, part.Size, part.CFrame, part.Anchored = name, size, at, true
					part.Color, part.Material = Color3.fromRGB(25, 25, 28), Enum.Material.Metal
					part.Parent = station
				end
				local frame = CFrame.new(pos.X, surface, pos.Z) * CFrame.Angles(0, math.rad(90), 0)
				solid("Worktop", Vector3.new(4.2, 0.22, 2.8), frame)
				for _, x in { -1.7, 1.7 } do
					solid("Pedestal", Vector3.new(0.3, 2.7, 2.1), frame * CFrame.new(x, -1.45, 0))
				end
				station.Parent = map
				buildFixed(frame * CFrame.new(0, 1.41, 0))
			end
		end
	end)

	Players.PlayerRemoving:Connect(function() end)
end

return ComputerService
