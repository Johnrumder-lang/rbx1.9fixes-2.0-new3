--!nonstrict
-- HospitalService (v2.8): the hospital next to the ripperdoc.
--   * RECOVERY BEDS (HealBed): lie down, sleep a few seconds, wake up healed (bones set, bleeding stopped). Once every 30 s.
--   * the REPLAY CHAIR (neuro lab): sit down - it plugs into your neck and holds you - and your last kills play: full
--     screen for you, on the big screen for the room. (v2.8.2) The records are the game's own recording (ReplayService):
--     the real bodies, cars, shots and blood, your own camera, the place round it built from the map.
--   * the operating room is a SurgeryZone (RipperdocService): a player surgeon earns money in there.
--   * POSES (v2.8.2): lying / sitting is held by the server too (anchored), so everybody sees you in the chair or on the bed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Poses = require(Shared:WaitForChild("Poses"))

local HospitalService = {}

local deps: any = {}
local Remote: RemoteEvent

local healCD: { [Player]: number } = {}
local chairBusy: Player? = nil
local held: { [Model]: { token: number, parts: { BasePart } } } = {}
local poseToken = 0

local function _torsoOf(m: Instance?): BasePart?
	local t = m and m:FindFirstChild("Torso")
	return (t and t:IsA("BasePart")) and t or nil
end

-- (v2.8) where a body lies on a bed: on its top, along its longest side, face up, the head towards `headEnd`
-- (a point; nil = the bed's +axis end). The client puts the body there and holds it (CharacterController POSE).
function HospitalService.LieOn(bed: BasePart, headEnd: Vector3?): CFrame
	local cf = bed.CFrame
	local s = bed.Size
	local along = s.X >= s.Z and cf.RightVector or cf.LookVector
	if headEnd and (headEnd - bed.Position):Dot(along) < 0 then
		along = -along
	end
	along = Vector3.new(along.X, 0, along.Z).Unit
	local top = bed.Position + Vector3.new(0, s.Y / 2, 0)
	local pos = top + Vector3.new(0, 0.55, 0) + along * 0.4
	local back = Vector3.new(0, -1, 0)
	local right = along:Cross(back)
	return CFrame.fromMatrix(pos, right, along)
end

-- (v2.8.2) the server holds the body in the pose too: anchored where the pose puts it (everybody sees it), and back to
-- its own machine afterwards
local function releaseHold(char: Model)
	local h = held[char]
	held[char] = nil
	if not h then
		return
	end
	for _, part in h.parts do
		if part.Parent then
			part.Anchored = false
			part.AssemblyLinearVelocity = Vector3.zero
		end
	end
	local p = Players:GetPlayerFromCharacter(char)
	if p then
		for _, d in char:GetDescendants() do
			if d:IsA("BasePart") and not d.Anchored then
				pcall(function()
					d:SetNetworkOwner(p)
				end)
			end
		end
	end
end

local function hold(char: Model, cf: CFrame, kind: string): number
	releaseHold(char)
	poseToken += 1
	local bs = char:GetAttribute("BodyScale")
	local S = typeof(bs) == "number" and bs or 1
	local list = {}
	for _, name in Poses.PARTS do
		local part = char:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local where = Poses.Where(kind, cf, name, S)
			if where then
				if not part.Anchored then
					part.Anchored = true
					table.insert(list, part)
				end
				part.CFrame = where
				part.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end
	held[char] = { token = poseToken, parts = list }
	return poseToken
end

-- lays / sits a player's body for `seconds` (kind "lie" | "sit")
function HospitalService.Pose(char: Model, cf: CFrame, kind: string, seconds: number)
	char:SetAttribute("PoseCF", cf)
	char:SetAttribute("PoseKind", kind)
	char:SetAttribute("PoseUntil", workspace:GetServerTimeNow() + seconds)
	local my = hold(char, cf, kind)
	task.delay(seconds, function()
		local h = held[char]
		if h and h.token == my then
			releaseHold(char)
		end
	end)
end

function HospitalService.Unpose(char: Model)
	char:SetAttribute("PoseUntil", nil)
	char:SetAttribute("PoseCF", nil)
	char:SetAttribute("PoseKind", nil)
	releaseHold(char)
end

------------------------------------------------------------------------

local function find(name: string): { BasePart }
	local out = {}
	local map = workspace:FindFirstChild("Map")
	if not map then
		return out
	end
	for _, d in map:GetDescendants() do
		if d.Name == name and d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

local function heal(p: Player, bed: BasePart)
	local char = p.Character
	if not char or char:GetAttribute("Dead") then
		return
	end
	local now = os.clock()
	if now < (healCD[p] or 0) then
		Remote:FireClient(p, "ripper", "msg", "THE NURSE SAYS: COME BACK IN A MOMENT.")
		return
	end
	healCD[p] = now + 30
	-- (v2.8) you lie down on it (face up, the head on the pillow) and sleep
	local headAt = nil
	local around: { Instance } = bed.Parent and bed.Parent:GetChildren() or {}
	for _, d in around do
		if d.Name == "BedPillow" and d:IsA("BasePart") and (d.Position - bed.Position).Magnitude < 6 then
			headAt = d.Position
		end
	end
	HospitalService.Pose(char, HospitalService.LieOn(bed, headAt), "lie", 6.5)
	task.wait(0.4)
	deps.DamageService.Sleep(char, 6, nil)
	Remote:FireClient(p, "ripper", "msg", "YOU REST ON THE RECOVERY BED...")
	task.delay(6, function()
		if char.Parent and not char:GetAttribute("Dead") then
			deps.DamageService.Heal(char)
			deps.DamageService.StopBleeding(char)
			Remote:FireClient(p, "ripper", "msg", "PATCHED UP.")
		end
	end)
end

-- the replay chair: you sit down facing the screen, the jack on its arm swings into your neck (a click, the screen boots),
-- then your records play one after the other - full screen for you, on the big screen for the room (everybody within
-- reach of it). (v2.8.2) The records come from ReplayService: the game's own recording.
local VIEW_RANGE = 70
local BOOT = 1.6 -- s of static before the first record
local BUILD = 2.6 -- s a client gets to build the place before a record starts

local function viewersOf(p: Player, screen: BasePart?): { Player }
	local out = { p }
	for _, o in Players:GetPlayers() do
		if o ~= p then
			local c = o.Character
			local t = c and c:FindFirstChild("Head")
			local at = screen or nil
			if t and t:IsA("BasePart") and at and (t.Position - at.Position).Magnitude < VIEW_RANGE then
				table.insert(out, o)
			end
		end
	end
	return out
end

local function sitReplay(p: Player, chair: BasePart, screen: BasePart?)
	local char = p.Character
	if not char or char:GetAttribute("Dead") then
		return
	end
	if chairBusy and chairBusy ~= p and chairBusy.Parent then
		Remote:FireClient(p, "ripper", "msg", "SOMEBODY IS PLUGGED IN.")
		return
	end
	if chairBusy == p then
		return
	end
	local list = deps.ReplayService.Records(p)
	chairBusy = p
	local total = BOOT + 1
	for _, r in list do
		total += BUILD + deps.ReplayService.Length(r) + 1.2
	end
	if #list == 0 then
		total += 3
	end
	-- sit: the back against the backrest, facing the screen (held by the server: everybody sees you sit)
	local face = screen and Vector3.new(screen.Position.X, 0, screen.Position.Z) or (chair.Position + Vector3.new(0, 0, 10))
	local flatFrom = Vector3.new(chair.Position.X, 0, chair.Position.Z)
	local dir = (face - flatFrom).Magnitude > 0.1 and (face - flatFrom).Unit or Vector3.new(0, 0, 1)
	local seat = chair.Position + Vector3.new(0, chair.Size.Y / 2 + 1.5, 0) - dir * 0.6
	HospitalService.Pose(char, CFrame.lookAt(seat, seat + dir), "sit", total + 1.5)
	char:SetAttribute("PluggedIn", workspace:GetServerTimeNow() + total)
	-- the jack: from its rest on the headrest into the back of the neck
	local jack = chair.Parent and chair.Parent:FindFirstChild("NeuroJack")
	local rest = nil
	if jack and jack:IsA("BasePart") then
		rest = jack.CFrame
		local neck = seat + Vector3.new(0, 1.05, 0) - dir * 0.55
		TweenService:Create(jack, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = CFrame.lookAt(neck - dir * 0.6, neck) }):Play()
	end
	pcall(deps.GoreService.Sound, "click", chair, 1)
	local function still(): boolean
		return char.Parent ~= nil and not char:GetAttribute("Dead") and p.Character == char and p.Parent ~= nil
	end
	for _, v in viewersOf(p, screen) do
		Remote:FireClient(v, "replaystart", p.UserId, #list, screen)
	end
	task.wait(BOOT)
	if #list == 0 and still() then
		for _, v in viewersOf(p, screen) do
			Remote:FireClient(v, "replay", p.UserId, 0, 0, nil, screen)
		end
		task.wait(3)
	end
	for i, rec in list do
		if not still() then
			break
		end
		local viewers = viewersOf(p, screen)
		local seen = {}
		local startAt = workspace:GetServerTimeNow() + BUILD
		for _, v in viewers do
			seen[v] = true
			Remote:FireClient(v, "replay", p.UserId, i, #list, rec.id, screen)
		end
		deps.ReplayService.Send(rec, viewers, screen, p, startAt)
		local endAt = startAt + deps.ReplayService.Length(rec) + 1.2
		repeat
			task.wait(0.5)
			for _, v in viewersOf(p, screen) do
				if not seen[v] then
					seen[v] = true
					Remote:FireClient(v, "replaystart", p.UserId, #list, screen)
					Remote:FireClient(v, "replay", p.UserId, i, #list, rec.id, screen)
					deps.ReplayService.Send(rec, { v }, screen, p, startAt)
				end
			end
		until workspace:GetServerTimeNow() >= endAt or not still()
	end
	for _, v in Players:GetPlayers() do
		Remote:FireClient(v, "replayend", p.UserId, screen)
	end
	if jack and jack:IsA("BasePart") and rest then
		TweenService:Create(jack, TweenInfo.new(0.5), { CFrame = rest }):Play()
	end
	if chairBusy == p then
		chairBusy = nil
	end
	if char.Parent then
		char:SetAttribute("PluggedIn", nil)
		HospitalService.Unpose(char)
	end
end

function HospitalService.Init(d: any)
	deps = d
	Remote = d.Remote

	Players.PlayerRemoving:Connect(function(p)
		healCD[p] = nil
		if chairBusy == p then
			chairBusy = nil
		end
	end)

	task.spawn(function()
		for _ = 1, 50 do
			if workspace:FindFirstChild("Map") then
				break
			end
			task.wait(0.2)
		end
		for _, bed in find("HealBed") do
			local pr = Instance.new("ProximityPrompt")
			pr.ActionText = "Lie down"
			pr.ObjectText = "Recovery bed"
			pr.HoldDuration = 0.5
			pr.MaxActivationDistance = 8
			pr.RequiresLineOfSight = false
			pr.Parent = bed
			pr.Triggered:Connect(function(p)
				heal(p, bed)
			end)
		end
		local screen = find("ReplayScreen")[1]
		for _, chair in find("ReplayChair") do
			local pr = Instance.new("ProximityPrompt")
			pr.ActionText = "Plug in"
			pr.ObjectText = "Replay chair: your last kills"
			pr.HoldDuration = 0.8
			pr.MaxActivationDistance = 8
			pr.RequiresLineOfSight = false
			pr.Parent = chair
			pr.Triggered:Connect(function(p)
				task.spawn(sitReplay, p, chair, screen)
			end)
		end
	end)
	local _ = Config
end

return HospitalService
