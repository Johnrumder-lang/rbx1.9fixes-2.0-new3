--!nonstrict
-- StillCutService (v2.8): STILLWATER, its sheath and the STILL CUT.
--   * STILLWATER is a katana to everything that cuts (PropBuilders.stillwater). The sheath is worn in a pocket at the hip.
--   * Put STILLWATER into a pocket that holds its sheath (hold Q / E with the sword in that hand): it slides into the
--     sheath. Drawing it is just taking it out of that pocket again (hold Q / E with the empty hand).
--   * If the hand was on the SHEATH'S side (left hand -> left pocket) and you know the STILL CUT (the quest, or the gift
--     "stillcut"): the moment the blade slides home the world stands still (Config.StillCutFreeze s). Cuts appear in the
--     air all round you (Config.StillCutRadius) - only you move. When the blade clicks shut, time goes on and everything
--     the cuts went through falls apart: bodies lose limbs (3 cuts each), loose things are cut in two, glass bursts.
--     Then the blade has to rest (Config.StillCutCooldown s; the player attribute "StillCutReady" says until when).
--   * Players who own it (quest done / gift) spawn with it: the sheath in the left pocket, the sword in the sheath.
--     Both are BOUND to them (attribute BoundTo): nobody else can pick them up, no NPC takes them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))

local StillCutService = {}

local deps: any = {}
local Remote: RemoteEvent

type Sheathed = { sword: Model, sheath: Model, weld: Weld, saved: { [BasePart]: { boolean } }, by: Player }
local sheathed: { [Model]: Sheathed } = {} -- sword -> where it sits
local lastCut: { [Player]: number } = {}
local gear: { [Player]: { Model } } = {} -- the bound copies a player has out in the world right now

-- set by SwordQuestService: does this player know the STILL CUT / spawn with STILLWATER?
StillCutService.Knows = nil :: ((Player) -> boolean)?
StillCutService.Owns = nil :: ((Player) -> boolean)?

local SHEATH_OFFSET = CFrame.new(0, 0, 2.9) -- the sword's Handle, from the sheath's Saya (the blade inside, the guard at the mouth)

local function isSword(m: Model?): boolean
	return m ~= nil and m:GetAttribute("Stillwater") == true
end

local function isSheath(m: Model?): boolean
	return m ~= nil and m:GetAttribute("Sheath") == true
end

local function swordIn(sheath: Model): Model?
	for sword, rec in sheathed do
		if rec.sheath == sheath and sword.Parent then
			return sword
		end
	end
	return nil
end

local function knows(p: Player): boolean
	if Items.Has(p, "stillcut") then
		return true
	end
	local f = StillCutService.Knows
	return f ~= nil and f(p) == true
end

------------------------------------------------------------------------
-- sheathing / drawing
------------------------------------------------------------------------

local function unsheathe(sword: Model)
	local rec = sheathed[sword]
	if not rec then
		return
	end
	sheathed[sword] = nil
	if rec.weld.Parent then
		rec.weld:Destroy()
	end
	for p, st in rec.saved do
		if p.Parent then
			p.CanCollide = st[1]
			p.Massless = st[2]
		end
	end
	sword:SetAttribute("InSheath", nil)
	sword:SetAttribute("StowedBy", nil)
	sword:SetAttribute("StowSlot", nil)
	CollectionService:RemoveTag(sword, "Stowed")
end

-- the sword slides into the sheath (wherever the sheath is)
local function sheathe(p: Player, sword: Model, sheath: Model)
	local saya = sheath.PrimaryPart
	local handle = sword.PrimaryPart
	if not saya or not handle then
		return
	end
	if deps.OwnershipService.ItemHolder(sword) then
		deps.OwnershipService.DropItem(sword)
	end
	unsheathe(sword)
	local saved: { [BasePart]: { boolean } } = {}
	for _, d in sword:GetDescendants() do
		if d:IsA("BasePart") then
			saved[d] = { d.CanCollide, d.Massless }
			d.CanCollide = false
			d.Massless = true
			d.Anchored = false
		end
	end
	sword:PivotTo(saya.CFrame * SHEATH_OFFSET * handle.CFrame:ToObjectSpace(sword:GetPivot()))
	local weld = Instance.new("Weld")
	weld.Name = "SheathWeld"
	weld.Part0 = saya
	weld.Part1 = handle
	weld.C0 = SHEATH_OFFSET
	weld.Parent = handle
	sheathed[sword] = { sword = sword, sheath = sheath, weld = weld, saved = saved, by = p }
	sword:SetAttribute("InSheath", true)
	local slot = sheath:GetAttribute("StowSlot")
	if sheath:GetAttribute("StowedBy") == p.UserId and typeof(slot) == "number" then
		-- (it shares the sheath's pocket: taking out of that pocket draws it)
		sword:SetAttribute("StowedBy", p.UserId)
		sword:SetAttribute("StowSlot", slot)
		CollectionService:AddTag(sword, "Stowed")
	end
end

------------------------------------------------------------------------
-- the STILL CUT
------------------------------------------------------------------------

local REGIONS = { "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }

local function cutBodies(p: Player, targets: { Model }, center: Vector3)
	local rng = Random.new()
	for _, body in targets do
		if not body.Parent or body:GetAttribute("Dead") then
			continue
		end
		local torso = body:FindFirstChild("Torso")
		local used = {}
		for _ = 1, 3 do
			local region = rng:NextNumber() < 0.1 and "Head" or REGIONS[rng:NextInteger(1, #REGIONS)]
			if used[region] and region ~= "Torso" then
				region = "Torso"
			end
			used[region] = true
			local part = body:FindFirstChild(RigInfo.RegionPart[region] or "Torso")
			local point = (part and part:IsA("BasePart")) and part.Position or (torso and torso:IsA("BasePart") and torso.Position or center)
			deps.DamageService.ApplyDamage(body, region, Config.StillCutDamage, point, {
				cause = "Cut in the stillness by " .. p.DisplayName,
				allowSever = true,
				severAt = Config.StillCutDamage - 5,
				bleed = 1.2,
				bleedTime = 20,
				attacker = p,
				melee = true,
			})
		end
		if torso and torso:IsA("BasePart") and body.Parent then
			local away = torso.Position - center
			local dir = away.Magnitude > 0.1 and away.Unit or Vector3.yAxis
			deps.DamageService.Blast(body, dir * 14 + Vector3.new(0, 10, 0), 2)
		end
	end
end

local function cutThings(p: Player, center: Vector3, radius: number)
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	local fx = workspace:FindFirstChild("FX")
	if fx then
		table.insert(ignore, fx)
	end
	op.FilterDescendantsInstances = ignore
	local parts = workspace:GetPartBoundsInRadius(center, radius, op)
	local rng = Random.new()
	local cuts, glass = 0, 0
	for _, part in parts do
		if not part.Parent then
			continue
		end
		if part.Material == Enum.Material.Glass and glass < 12 then
			glass += 1
			pcall(deps.ExplosionService.Shatter, part, part.Position, (part.Position - center).Unit)
			continue
		end
		if cuts >= Config.StillCutProps or part.Anchored or not part:IsA("Part") or part.Transparency > 0.9 or part:IsGrounded() then
			continue
		end
		local m = part:FindFirstAncestorOfClass("Model")
		if deps.DamageService.BodyOf(part) or (m and (m:GetAttribute("HolderId") or m:GetAttribute("StowedBy") or m:GetAttribute("BoundTo"))) then
			continue
		end
		if part.Size.Magnitude < 1.2 then
			continue -- (crumbs)
		end
		local normal = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
		if normal.Magnitude < 0.1 then
			normal = Vector3.xAxis
		end
		local ok, did = pcall(deps.SeverService.CutPart, part, part.Position, normal.Unit)
		if ok and did then
			cuts += 1
		end
	end
	local _ = p
end

function StillCutService.Ready(p: Player): boolean
	return os.clock() >= (lastCut[p] or -math.huge) + Config.StillCutCooldown
end

function StillCutService.Cut(p: Player)
	if not knows(p) or not StillCutService.Ready(p) then return end
	local char = p.Character
	local torso = char and char:FindFirstChild("Torso")
	if not char or not torso or not torso:IsA("BasePart") or char:GetAttribute("Dead") then
		return
	end
	if (char:GetAttribute("TemporalFrozenUntil") or 0) > workspace:GetServerTimeNow() then return end
	lastCut[p] = os.clock()
	p:SetAttribute("StillCutReady", workspace:GetServerTimeNow() + Config.StillCutCooldown + Config.StillCutFreeze)
	local center = torso.Position
	local R = Config.StillCutRadius
	local targets = {}
	for body in deps.DamageService.Bodies() do
		local t = body.Parent and body:FindFirstChild("Torso")
		if body ~= char and t and t:IsA("BasePart") and not body:GetAttribute("Dead") and (t.Position - center).Magnitude <= R then
			table.insert(targets, body)
		end
	end
	-- (v2.9) by default the STILL CUT only freezes what is inside the ring (the people around you), not the whole server
	local froze = false
	if Config.StillCutLocal then
		deps.SuperService.LocalFreeze(p, center, R, Config.StillCutFreeze)
	elseif not deps.SuperService.TimeStopped() and not deps.SuperService.SlowMoActive() then
		deps.SuperService.TimeStop(p, true, "still")
		froze = true
	end
	local seed = math.random(1, 1e6)
	deps.GoreService.FX({ t = "stillcut", ph = "begin", by = p.UserId, p = center, r = R, d = Config.StillCutFreeze, seed = seed })
	deps.GoreService.Sound("click", torso, 1)
	task.wait(Config.StillCutFreeze)
	-- the blade clicks shut
	if froze then
		deps.SuperService.TimeStop(p, false)
	end
	deps.GoreService.FX({ t = "stillcut", ph = "end", by = p.UserId, p = center, r = R, seed = seed })
	deps.GoreService.Sound("clink", center, 1.2)
	deps.GoreService.Sound("slash", center, 1.5)
	cutBodies(p, targets, center)
	task.spawn(cutThings, p, center, R)
end

------------------------------------------------------------------------
-- the pocket hooks
------------------------------------------------------------------------

local function onStow(p: Player, item: Model, sideSlot: number, pockets: { [number]: Model }): boolean
	if not isSword(item) then
		return false
	end
	local target, same = nil, false
	if isSheath(pockets[sideSlot]) and not swordIn(pockets[sideSlot]) then
		target, same = pockets[sideSlot], true
	else
		local other = pockets[3 - sideSlot]
		if pockets[sideSlot] ~= nil and isSheath(other) and not swordIn(other) then
			target = other -- (the pocket on this side is taken: it goes home anyway, quietly)
		end
	end
	if not target then
		return false
	end
	sheathe(p, item, target)
	deps.GoreService.Sound("metal", target.PrimaryPart or item.PrimaryPart, 0.6)
	if not same or not knows(p) then
		if same and not knows(p) then
			Remote:FireClient(p, "note", "SHEATHED. (Only who beat " .. Config.RivalName .. " knows what else it can do.)")
		end
		return true
	end
	if not StillCutService.Ready(p) then
		local left = math.ceil((lastCut[p] or 0) + Config.StillCutCooldown - os.clock())
		Remote:FireClient(p, "note", string.format("SHEATHED. THE BLADE IS STILL RESTING (%d S).", left))
		return true
	end
	task.spawn(StillCutService.Cut, p)
	return true
end

local function onUnstow(p: Player, item: Model, side: string?): boolean
	if isSword(item) and sheathed[item] then
		local rec = sheathed[item]
		if item:GetAttribute("BoundTo") ~= nil and item:GetAttribute("BoundTo") ~= p.UserId then
			return true
		end
		if rec.sheath:GetAttribute("StowedBy") ~= p.UserId and rec.by ~= p then
			return true
		end
		-- (v2.8.1 fix) drawn straight into the hand, in the same moment: before, the sword was loose for a moment inside
		-- the sheath at your hip (colliding again), jammed against the sheath and your body, and the hand missed it
		local handle = item.PrimaryPart
		local char = p.Character
		local arm = char and char:FindFirstChild(side == "Left" and "Left Arm" or "Right Arm")
		unsheathe(item)
		if handle and arm and arm:IsA("BasePart") then
			item:PivotTo(arm.CFrame * RigInfo.GunHandCFrame * (handle:FindFirstChild("GripAttachment") and (handle :: any).GripAttachment.CFrame:Inverse() or CFrame.identity)
				* handle.CFrame:ToObjectSpace(item:GetPivot()))
			deps.OwnershipService.Grab(p, handle, side or "Right")
		end
		deps.GoreService.Sound("kickSwoosh", item.PrimaryPart or rec.sheath.PrimaryPart, 0.6)
		return true
	end
	if isSheath(item) and swordIn(item) then
		return true -- (the sword is in it: you draw the sword, the sheath stays at your hip)
	end
	return false
end

------------------------------------------------------------------------
-- giving it out
------------------------------------------------------------------------

local function clearGear(p: Player)
	for _, m in (gear[p] or {}) :: { Model } do
		if m.Parent then
			if sheathed[m] then
				unsheathe(m)
			end
			m:Destroy()
		end
	end
	gear[p] = nil
end

local function bind(p: Player, m: Model)
	m:SetAttribute("BoundTo", p.UserId)
	m:SetAttribute("OwnerName", p.DisplayName)
	local list = gear[p] or {}
	gear[p] = list
	table.insert(list, m)
	m.Destroying:Connect(function()
		sheathed[m] = nil
	end)
end

local function place(m: Model, at: CFrame)
	m:PivotTo(at)
	local f = workspace:FindFirstChild("SpawnedProps")
	if not f then
		f = Instance.new("Folder")
		f.Name = "SpawnedProps"
		f.Parent = workspace
	end
	m.Parent = f
end

-- the sheath alone (quest 2), straight into a pocket (or at your feet when both are full)
function StillCutService.GiveSheath(p: Player): Model?
	local torso = p.Character and p.Character:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return nil
	end
	local sheath = deps.PropBuilders.sheath(torso.CFrame * CFrame.new(0, 0, -2))
	bind(p, sheath)
	place(sheath, torso.CFrame * CFrame.new(0, 0, -2))
	if not deps.OwnershipService.PocketItem(p, sheath, 1) then
		Remote:FireClient(p, "note", "YOUR POCKETS ARE FULL: THE SHEATH LIES AT YOUR FEET.")
	end
	return sheath
end

-- the whole set: the sheath in the left pocket, STILLWATER in it. Old copies of this player are gone.
function StillCutService.GiveGear(p: Player)
	if not (StillCutService.Owns and StillCutService.Owns(p)) then return end
	local char = p.Character
	local torso = char and char:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") or char:GetAttribute("Dead") then
		return
	end
	clearGear(p)
	local at = torso.CFrame * CFrame.new(0, 0, -2.5)
	local sheath = deps.PropBuilders.sheath(at)
	local sword = deps.PropBuilders.stillwater(at)
	bind(p, sheath)
	bind(p, sword)
	place(sheath, at)
	place(sword, at * CFrame.new(1.5, 0, 0))
	deps.OwnershipService.PocketItem(p, sheath, 1)
	sheathe(p, sword, sheath)
end

-- a quest sheath (quest 2) that is somewhere on this player (hand or pocket)
function StillCutService.CarriesSheath(p: Player): boolean
	for _, m in (gear[p] or {}) :: { Model } do
		if m.Parent and isSheath(m) and (m:GetAttribute("StowedBy") == p.UserId or m:GetAttribute("HolderId") == p.UserId) then
			return true
		end
	end
	return false
end

function StillCutService.ClearGear(p: Player)
	clearGear(p)
end

function StillCutService.Init(d: any)
	deps = d
	Remote = d.Remote
	deps.OwnershipService.StowHook = onStow
	deps.OwnershipService.UnstowHook = onUnstow
	local prevSpawn = deps.CharacterService.OnSpawned
	deps.CharacterService.OnSpawned = function(p: Player, model: Model)
		if prevSpawn then
			prevSpawn(p, model)
		end
		local t0 = os.clock()
		while model.Parent and not model:GetAttribute("RagdollRig") and os.clock() - t0 < 10 do
			task.wait(0.1)
		end
		task.wait(0.5)
		if p.Character ~= model or not model.Parent then
			return
		end
		clearGear(p)
		p:SetAttribute("StillwaterSummoned", nil)
	end
	Players.PlayerRemoving:Connect(function(p)
		clearGear(p)
		lastCut[p] = nil
	end)

end

return StillCutService
