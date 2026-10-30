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
			-- RipperFrontDesk is an invisible interaction marker over the actual counter.
			-- Place the terminal on that counter, not nine studs out in the waiting room.
			local at = desk.CFrame * CFrame.new(0, 0, 0.8)
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Include
			rp.FilterDescendantsInstances = { desk.Parent }
			local hit = workspace:Raycast(at.Position + Vector3.new(0, 1, 0), Vector3.new(0, -4, 0), rp)
			if hit and hit.Normal.Y > 0.8 then
				buildFixed(CFrame.new(at.Position.X, hit.Position.Y + 1.3, at.Position.Z) * desk.CFrame.Rotation * CFrame.Angles(0, math.rad(-90), 0))
			end
		end
	end)

	Players.PlayerRemoving:Connect(function() end)
end

return ComputerService
