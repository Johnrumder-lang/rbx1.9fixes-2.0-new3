--!nonstrict
-- OwnershipService: what players hold.
--   * loose objects: the grabbing player's client becomes the physics owner, so the hand
--     constraint (made on that client) moves it without lag
--   * items (guns, spear, blade, grenade, bandage): the SERVER welds them into the hand, so every
--     machine agrees where they are (a client-only weld left the server's copy hanging in the air)
--   * other players (v1.8, v2.0): grabbing one knocks them over, but their body stays THEIRS (nobody
--     changes owner, no joint between two players). Their own client pulls the grabbed spot to
--     your hand; every other screen shows a local limp copy hanging from your hand (DragPuppets) so
--     nobody sees the network delay. When you let go they fall where they are (or fly, if you threw).
--   * physics gun (owner only): props / dummies / cars / players become the beam holder's to move

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))
local Items = require(Shared:WaitForChild("Items"))

local DamageService = require(script.Parent:WaitForChild("DamageService"))
local RigBuilder = require(script.Parent:WaitForChild("RigBuilder"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GripRemote = Remotes:WaitForChild("Grip") :: RemoteEvent
local FXRemote = Remotes:WaitForChild("FX") :: RemoteEvent

local OwnershipService = {}

-- set by Main: pull a player out of the car they drive (before they are dragged away)
-- set by CalamityService: somebody tried to grab a "Wonder of U" player
OwnershipService.OnGrabWonder = nil :: ((Player, Model) -> ())?
OwnershipService.OnGrabDriver = nil :: ((Player) -> ())?
-- set by ItemService: an item stuck in something is pulled out when somebody takes it
OwnershipService.OnHold = nil :: ((Model) -> ())?

-- holders[rootPart][player] = number of hands
local holders: { [BasePart]: { [Player]: number } } = {}
-- drags[victimCharacter] = { by = Player, hands = number, owner = Player, beam = physics gun?, owned = the dragger
-- simulates the body (v2.0) }
local drags: { [Model]: any } = {}
-- beams[player] = what their physics gun holds
local beams: { [Player]: { victim: Model?, roots: { BasePart } } } = {}
-- items[itemModel] = the server weld that puts it in a player's hand
local items: { [Model]: { by: Player, weld: Instance, att: Instance, handle: BasePart, side: string } } = {}

local function bodyModelOf(part: BasePart): Model?
	local m = part:FindFirstAncestorOfClass("Model")
	while m do
		if m:GetAttribute("RagdollRig") then
			return m
		end
		m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- (v2.0) set by GameModeService: may this player take this item into a hand?
OwnershipService.CanHold = nil :: ((Player, Model) -> boolean)?

local function setOwner(part: BasePart, player: Player?)
	local ok, can = pcall(function()
		return part:CanSetNetworkOwnership()
	end)
	if ok and can then
		pcall(function()
			if player then
				part:SetNetworkOwner(player)
			else
				part:SetNetworkOwnershipAuto()
			end
		end)
	end
end
OwnershipService.SetOwner = setOwner

local function rootsOf(model: Model): { BasePart }
	local roots = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.AssemblyRootPart == d and not d.Anchored then
			table.insert(roots, d)
		end
	end
	return roots
end

local function torsoOf(player: Player): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("Torso") :: BasePart?
end

local function markHeld(inst: Instance, player: Player)
	inst:SetAttribute("LastHolder", player.UserId)
	inst:SetAttribute("LastHeldT", workspace:GetServerTimeNow())
end

----------------------------------------------------------------------
-- dragging other players
----------------------------------------------------------------------

-- Dragging a PLAYER: nothing changes hands. The victim's own client keeps simulating its body
-- and pulls the grabbed part to the dragger's hand (DragClient); the dragger's client only
-- reaches for it. (Handing a player's body to another player's machine left the victim - or the
-- dragger, on the victim's screen - frozen in place.)
local function sendDrag(victim: Model, d)
	-- (v2.0) every screen draws the drag from these (DragPuppets): who, which hand, which part, where on it
	victim:SetAttribute("DragSide", d.side)
	victim:SetAttribute("DragPart", d.partName)
	victim:SetAttribute("DragPoint", d.lp)
	victim:SetAttribute("DragBeam", d.beam == true or nil)
	if d.owner and d.owner.Parent then
		FXRemote:FireClient(d.owner, {
			t = "drag",
			body = victim,
			by = d.by.UserId,
			part = d.partName,
			lp = d.lp,
			side = d.side,
			beam = d.beam == true,
			owned = d.owned == true,
		})
	end
end

-- where every part of a body is and how fast it moves (handed to its own client with the body)
local function snapOf(model: Model): { [string]: { any } }
	local snap = {}
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			snap[p.Name] = { p.CFrame, p.AssemblyLinearVelocity }
		end
	end
	return snap
end

-- (v2.0) a dragged body slides along the floor instead of scraping (set here so the dragger's machine,
-- which simulates it, sees it too)
local function setSlick(victim: Model, d, on: boolean)
	if on then
		d.slick = d.slick or {}
		for _, p in victim:GetDescendants() do
			if p:IsA("BasePart") and (p.Parent == victim or p.Name == "Collider") and d.slick[p] == nil then
				d.slick[p] = p.CustomPhysicalProperties or false
				local cur = p.CurrentPhysicalProperties
				p.CustomPhysicalProperties = PhysicalProperties.new(cur.Density, Config.DragFriction, cur.Elasticity, 100, cur.ElasticityWeight)
			end
		end
	elseif d.slick then
		for p, old in d.slick do
			if p.Parent then
				p.CustomPhysicalProperties = old or nil
			end
		end
		d.slick = nil
	end
end

-- (v2.0) the two bodies never shove each other while one holds the other (made here: every machine has it)
local function noCollide(victim: Model, d, by: Player)
	local char = by.Character
	if not char then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "DragNoCollide"
	local mine, theirs = {}, {}
	-- (v2.8.1) limbs too (p.Parent == the model): they only collide while limp, so they were missed and the dragger stood on them
	for _, p in victim:GetDescendants() do
		if p:IsA("BasePart") and (p.CanCollide or p.Name == "Collider" or p.Parent == victim) then
			table.insert(theirs, p)
		end
	end
	for _, p in char:GetDescendants() do
		if p:IsA("BasePart") and (p.CanCollide or p.Name == "Collider" or p.Parent == char) then
			table.insert(mine, p)
		end
	end
	for _, a in theirs do
		for _, b in mine do
			local nc = Instance.new("NoCollisionConstraint")
			nc.Part0 = a
			nc.Part1 = b
			nc.Parent = folder
		end
	end
	folder.Parent = victim
	d.nocol = folder
	pcall(RigBuilder.SetCarried, victim, true) -- (v2.8.2) through every other body while it is carried
end

local function clearDragAttributes(victim: Model)
	for _, k in { "DraggedBy", "DragOwned", "DragSide", "DragPart", "DragPoint", "DragBeam" } do
		victim:SetAttribute(k, nil)
	end
end

local function endDrag(victim: Model, throw: Vector3?)
	local d = drags[victim]
	if not d then
		return
	end
	drags[victim] = nil
	clearDragAttributes(victim)
	if d.nocol then
		d.nocol:Destroy()
		pcall(RigBuilder.SetCarried, victim, false)
	end
	if d.watch then
		d.watch:Disconnect()
	end
	setSlick(victim, d, false)
	if victim.Parent and not victim:GetAttribute("Dead") then
		RigBuilder.Restore(victim)
	end
	if d.owner and d.owner.Parent then
		local snap = nil
		if d.owned and victim.Parent then
			-- the body goes back to its own client exactly where the dragger left it
			snap = snapOf(victim)
			for _, root in rootsOf(victim) do
				setOwner(root, d.owner)
			end
		end
		FXRemote:FireClient(d.owner, { t = "undrag", body = victim, snap = snap })
		-- (v2.0) thrown: the body is that player's, so their client throws it
		if throw and throw.Magnitude > 1 and victim.Parent then
			FXRemote:FireClient(d.owner, { t = "knock", all = throw, rt = 1.5 })
		end
	end
end

local function startDrag(player: Player, victimPlayer: Player, victim: Model, beam: boolean?, part: BasePart?, localPoint: Vector3?, side: string?)
	local d = drags[victim]
	if d then
		if d.by == player and not d.beam and not beam then
			d.hands += 1
			if side then
				d.sides[side] = true
			end
		end
		return
	end
	if victim:GetAttribute("Wonder") == true and OwnershipService.OnGrabWonder then
		OwnershipService.OnGrabWonder(player, victim) -- (v1.9) nobody drags a Wonder player: a calamity finds them
		return
	end
	if victim:GetAttribute("InCar") and OwnershipService.OnGrabDriver then
		OwnershipService.OnGrabDriver(victimPlayer) -- yanked out of the car
	end
	local partName = part and part.Name or "Torso"
	local lp = localPoint
	if typeof(lp) ~= "Vector3" or lp ~= lp or (part and lp.Magnitude > part.Size.Magnitude) then
		lp = Vector3.zero
	end
	d = {
		by = player,
		hands = 1,
		owner = victimPlayer,
		beam = beam,
		partName = partName,
		lp = lp,
		side = side or "Right",
		sides = side and { [side] = true } or {},
	}
	drags[victim] = d
	victim:SetAttribute("DraggedBy", player.UserId)
	-- limp; the victim's own client goes ragdoll (and in the v1.9 mode pulls itself to the hand)
	RigBuilder.GoLimp(victim)
	markHeld(victim, player)
	if not beam then
		noCollide(victim, d, player)
	end
	-- (gone from the world - a fresh respawn destroys the old body): nothing to drag any more
	d.watch = victim.AncestryChanged:Connect(function()
		if not victim:IsDescendantOf(workspace) then
			endDrag(victim)
		end
	end)
	if Config.DragOwnerMode then
		-- (v2.0) like a dummy: the dragger's machine simulates the limp body while it is held, so it hangs right
		-- at the hand with no delay. The victim's client only watches until it gets the body back.
		d.owned = true
		victim:SetAttribute("DragOwned", true)
		for _, root in rootsOf(victim) do
			setOwner(root, player)
		end
		setSlick(victim, d, true)
	end
	sendDrag(victim, d)
end

-- a hand of the dragger let go: with the other hand still on the body, it follows that hand
local function dragHandReleased(victim: Model, side: string?, throw: Vector3?)
	local d = drags[victim]
	if not d or d.beam then
		return
	end
	d.hands -= 1
	if side then
		d.sides[side] = nil
	end
	if d.hands <= 0 then
		endDrag(victim, throw)
		return
	end
	local other = next(d.sides)
	if other and other ~= d.side then
		d.side = other
		sendDrag(victim, d)
	end
end

-- the dragged player died. (v2.0) While the body is still their character their client keeps pulling it to the
-- hand (Roblox does not let another machine take a player's own character); once it is a corpse
-- (OwnershipService.BecameCorpse) the dragger holds it like a dummy.
function OwnershipService.VictimDied(victim: Model)
	local d = drags[victim]
	if not d then
		return
	end
	if not d.owned then
		return
	end
	drags[victim] = nil
	victim:SetAttribute("DraggedBy", nil)
	victim:SetAttribute("DragOwned", nil)
	setSlick(victim, d, false)
	if d.owner and d.owner.Parent then
		FXRemote:FireClient(d.owner, { t = "undrag", body = victim })
	end
	local by = d.by
	if not by.Parent then
		return
	end
	if d.beam then
		local roots = rootsOf(victim)
		for _, root in roots do
			setOwner(root, by)
		end
		beams[by] = { roots = roots }
	else
		for _, root in rootsOf(victim) do
			holders[root] = holders[root] or {}
			holders[root][by] = math.max(d.hands, 1)
			setOwner(root, by)
		end
	end
	markHeld(victim, by)
end

-- (v2.0) the dead body is no player's character any more (they respawned): the dragger takes it over like a dummy
function OwnershipService.BecameCorpse(victim: Model)
	local d = drags[victim]
	if not d then
		return
	end
	drags[victim] = nil
	clearDragAttributes(victim)
	if d.nocol then
		d.nocol:Destroy()
		pcall(RigBuilder.SetCarried, victim, false)
	end
	if d.watch then
		d.watch:Disconnect()
	end
	setSlick(victim, d, false)
	local by = d.by
	if not by.Parent then
		return
	end
	local roots = rootsOf(victim)
	if d.beam then
		for _, root in roots do
			setOwner(root, by)
		end
		beams[by] = { roots = roots }
	else
		for _, root in roots do
			holders[root] = holders[root] or {}
			holders[root][by] = math.max(d.hands, 1)
			setOwner(root, by)
		end
	end
	markHeld(victim, by)
end

-- stop every drag this player does (e.g. they tied the body up)
function OwnershipService.EndDragsBy(player: Player)
	for victim, d in drags do
		if d.by == player then
			endDrag(victim)
		end
	end
end

function OwnershipService.EndDrag(victim: Model)
	endDrag(victim)
end

----------------------------------------------------------------------
-- physics gun
----------------------------------------------------------------------

function OwnershipService.BeamDrop(player: Player)
	local b = beams[player]
	if not b then
		return
	end
	beams[player] = nil
	if b.victim then
		local d = drags[b.victim]
		if d and d.by == player and d.beam then
			endDrag(b.victim)
		end
		return -- (a living player's body went back to its own client: never hand it to the server)
	end
	for _, root in b.roots do
		task.delay(1.5, function()
			if root.Parent and not holders[root] then
				local busy = false
				for _, other in beams do
					if table.find(other.roots, root) then
						busy = true
					end
				end
				if not busy then
					setOwner(root, nil)
				end
			end
		end)
	end
end

function OwnershipService.BeamGrab(player: Player, part: BasePart, localPoint: Vector3, pos: Vector3)
	OwnershipService.BeamDrop(player)
	if part:IsGrounded() then
		return
	end
	local body = bodyModelOf(part)
	local victimPlayer = body and Players:GetPlayerFromCharacter(body)
	if body and victimPlayer then
		if victimPlayer == player or drags[body] then
			if victimPlayer ~= player then
				warn("[physgun] refused: that player is already being dragged:", victimPlayer.Name)
			end
			return
		end
		if not body:GetAttribute("Dead") then
			DamageService.Knock(body, nil, nil, 2.5)
			DamageService.MarkAttacker(body, player)
		end
		startDrag(player, victimPlayer, body, true, part, localPoint, nil)
		local d = drags[body]
		beams[player] = { victim = body, roots = (d and d.owned) and rootsOf(body) or {} }
		return
	end
	-- props, dummies, corpses, cars nobody drives: the beam holder simulates them
	local model = body or part:FindFirstAncestorOfClass("Model")
	if model and model:GetAttribute("Car") and model:GetAttribute("DriverId") then
		return
	end
	local roots = {}
	if body then
		roots = rootsOf(body)
	elseif model and model:GetAttribute("Car") then
		roots = rootsOf(model)
	elseif part.AssemblyRootPart then
		roots = { part.AssemblyRootPart }
	end
	for _, root in roots do
		setOwner(root, player)
		markHeld(root, player)
	end
	if model then
		markHeld(model, player)
	end
	beams[player] = { roots = roots }
end

-- the beam's end point moved: a held player is pulled there by their own client
function OwnershipService.BeamMove(player: Player, pos: Vector3)
	local b = beams[player]
	if b and b.victim then
		local d = drags[b.victim]
		if d and d.by == player and d.owner and d.owner.Parent then
			FXRemote:FireClient(d.owner, { t = "dragpos", body = b.victim, pos = pos })
		end
	end
end

----------------------------------------------------------------------
-- items held in the hand (server weld)
----------------------------------------------------------------------

local function dropItem(item: Model)
	local rec = items[item]
	if not rec then
		return
	end
	items[item] = nil
	if rec.by.Parent then GripRemote:FireClient(rec.by, "release", item, rec.side) end
	if item:GetAttribute("SawOn") then
		item:SetAttribute("SawOn", nil) -- (v2.0) a chainsaw that is let go stalls
	end
	rec.weld:Destroy() -- (its no-collision constraints are children of it)
	rec.att:Destroy()
	if item:GetAttribute("HolderId") == rec.by.UserId then
		item:SetAttribute("HolderId", nil)
	end
	markHeld(item, rec.by)
	local handle = rec.handle
	-- thrown grenades / spears / C4 keep flying on the thrower's machine (it reports what they hit);
	-- everything else goes back to the server
	local kind = Items.Kind(item)
	if kind ~= "grenade" and kind ~= "flash" and kind ~= "spear" and kind ~= "c4" then
		task.delay(1.5, function()
			if not items[item] and handle.Parent and not item:GetAttribute("StowedBy") then
				setOwner(handle, nil) -- (a stowed item is part of its owner's body: never take that away)
			end
		end)
	end
end
OwnershipService.DropItem = dropItem

local function holdItem(player: Player, item: Model, side: string?)
	local handle = item.PrimaryPart
	local gripAtt = handle and handle:FindFirstChild("GripAttachment")
	local char = player.Character
	if not handle or not gripAtt or not char or char:GetAttribute("Dead") then
		return
	end
	if item:GetAttribute("NPCHeld") then
		return -- a hostile NPC holds it
	end
	local stowedBy = item:GetAttribute("StowedBy")
	if stowedBy then
		if stowedBy ~= player.UserId then
			return -- it is in somebody else's pocket
		end
		OwnershipService.Unstow(player, handle) -- (grabbing your own stowed item takes it out)
		if item:GetAttribute("StowedBy") ~= nil then
			return -- (v2.8) it stays in (the sheath while the sword is in it)
		end
	end
	if not Items.MayUse(player, item) then
		return -- the physics gun is the game owner's
	end
	local bound = item:GetAttribute("BoundTo")
	if typeof(bound) == "number" and bound ~= player.UserId then
		return -- (v2.8) STILLWATER and its sheath answer to the one who earned them
	end
	if OwnershipService.CanHold and not OwnershipService.CanHold(player, item) then
		return -- (v2.0) a game mode says no (zombies hold nothing, gun game: only your own gun)
	end
	local cur = items[item]
	if cur then
		if cur.by ~= player then
			return -- someone else has it
		end
		dropItem(item) -- switching hands
	end
	local key = side == "Left" and "LeftArm" or "RightArm"
	local arm = char:FindFirstChild(side == "Left" and "Left Arm" or "Right Arm")
	if not arm or not arm:IsA("BasePart") or char:GetAttribute("Severed_" .. key) then
		return
	end
	if OwnershipService.OnHold then
		OwnershipService.OnHold(item)
	end
	-- (v1.9) whatever pinned it: an item in a hand is never anchored (that froze the holder in place)
	for _, ip in item:GetDescendants() do
		if ip:IsA("BasePart") and ip.Anchored then
			ip.Anchored = false
		end
	end
	-- (v2.0 fix) nor joined to anything outside itself (a weld into a wall, the ground, a car): pulled out
	for _, ip in item:GetDescendants() do
		if ip:IsA("BasePart") then
			for _, j in ip:GetJoints() do
				local other = nil
				if j:IsA("WeldConstraint") or j:IsA("Weld") or j:IsA("Motor6D") or j:IsA("ManualWeld") then
					other = (j :: any).Part0 == ip and (j :: any).Part1 or (j :: any).Part0
				elseif j:IsA("Constraint") then
					local a0, a1 = (j :: any).Attachment0, (j :: any).Attachment1
					local p0 = a0 and a0.Parent
					local p1 = a1 and a1.Parent
					other = (p0 == ip) and p1 or p0
				end
				if other and other:IsA("BasePart") and not other:IsDescendantOf(item) and not other:IsDescendantOf(char) then
					j:Destroy()
				end
			end
		end
	end
	setOwner(handle, player)
	local att = Instance.new("Attachment")
	att.Name = "ItemHandServer"
	att.CFrame = RigInfo.GunHandCFrame
	att.Parent = arm
	local weld = Instance.new("RigidConstraint")
	weld.Name = "ItemWeld"
	weld.Attachment0 = att
	weld.Attachment1 = gripAtt
	-- the item never collides with its holder (a spear shaft would shove you around)
	for _, ip in item:GetDescendants() do
		if ip:IsA("BasePart") then
			for _, bp in char:GetDescendants() do
				if bp:IsA("BasePart") and (bp.CanCollide or bp.Name == "Collider") then
					local nc = Instance.new("NoCollisionConstraint")
					nc.Part0 = ip
					nc.Part1 = bp
					nc.Parent = weld
				end
			end
		end
	end
	weld.Parent = handle
	items[item] = { by = player, weld = weld, att = att, handle = handle, side = side or "Right" }
	item:SetAttribute("HolderId", player.UserId)
	markHeld(item, player)
	OwnershipService.FreeFromWorld(item)
end

-- (v2.8) an item that is partly INSIDE the floor or a wall when it is picked up (it fell fast, it was stuck, it lay half in
-- the ground) would fight the world: the body that holds it shook, jumped or got stuck. Like a spear pulled out of a
-- wall, it now ignores whatever it is inside of until it is clear of it.
local freeParams = OverlapParams.new()
freeParams.FilterType = Enum.RaycastFilterType.Exclude
function OwnershipService.FreeFromWorld(item: Model)
	local ignore: { Instance } = { item }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	freeParams.FilterDescendantsInstances = ignore
	local made: { Instance } = {}
	local walls: { [BasePart]: boolean } = {}
	for _, ip in item:GetDescendants() do
		if ip:IsA("BasePart") and ip.CanCollide then
			for _, other in workspace:GetPartsInPart(ip, freeParams) do
				if other.Anchored and other.CanCollide and #made < 60 then
					walls[other] = true
					local nc = Instance.new("NoCollisionConstraint")
					nc.Name = "FreeFromWorld"
					nc.Part0 = ip
					nc.Part1 = other
					nc.Parent = ip
					table.insert(made, nc)
				end
			end
		end
	end
	if #made == 0 then
		return
	end
	task.spawn(function()
		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Include
		local list = {}
		for w in walls do
			table.insert(list, w)
		end
		op.FilterDescendantsInstances = list
		local t0, clear = os.clock(), 0
		while os.clock() - t0 < 8 and item.Parent do
			task.wait(0.2)
			local touching = false
			for _, ip in item:GetDescendants() do
				if ip:IsA("BasePart") and #workspace:GetPartsInPart(ip, op) > 0 then
					touching = true
					break
				end
			end
			clear = touching and 0 or clear + 1
			if clear >= 3 then
				break
			end
		end
		for _, nc in made do
			if nc.Parent then
				nc:Destroy()
			end
		end
	end)
end

----------------------------------------------------------------------
-- pockets (v1.9.1): two items ride on the body (hips or back, depending on the item); they stay when you fall
----------------------------------------------------------------------

local CollectionService = game:GetService("CollectionService")

-- items that do not fit at the hip ride on the back
local BACK_KINDS = {
	sniper = true, rifle = true, shotgun = true, launcher = true, minigun = true, crossbow = true,
	flamethrower = true, spear = true, katana = true, sledge = true, axe = true, bat = true, shield = true,
	boombox = true, physgun = true,
}
local stowed: { [Player]: { [number]: { item: Model, weld: Weld, saved: { [BasePart]: { boolean } } } } } = {}

-- where an item sits, relative to the torso (front = -Z). slot 1 = left, slot 2 = right
local function pocketCFrame(kind: string?, slot: number): CFrame
	local sx = slot == 1 and -1 or 1
	if kind == "sheath" then
		-- (v2.8) STILLWATER's sheath: worn at the hip like a sword, the mouth forward, the tip back and a little down
		return CFrame.new(sx * 1.12, -1.4, 1.25) * CFrame.Angles(math.rad(-160), 0, math.rad(sx * 6))
	end
	if kind and BACK_KINDS[kind] then
		-- across the back, barrel / blade up and leaning outwards
		return CFrame.new(sx * 0.35, 0.45, 0.85) * CFrame.Angles(0, 0, math.rad(-sx * 24)) * CFrame.Angles(math.rad(90), 0, 0)
	end
	-- at the hip, pointing down
	return CFrame.new(sx * 1.2, -0.85, 0.05) * CFrame.Angles(math.rad(-90), 0, 0)
end

local function itemOfPart(part: BasePart): Model?
	return Items.ModelOf(part)
end

-- (v2.8) hooks (StillCutService): an item about to go into a pocket ((player, item, slot the hand points at, what is in the
-- pockets) -> true = handled, nothing else happens) and an item about to come out ((player, item) -> true = handled)
OwnershipService.StowHook = nil :: ((Player, Model, number, { [number]: Model }) -> boolean)?
OwnershipService.UnstowHook = nil :: ((Player, Model, string?) -> boolean)?

-- pockets of a body that is gone (died / respawned) are free again
local function prunePockets(player: Player, torso: BasePart): { [number]: any }
	local mine = stowed[player] or {}
	stowed[player] = mine
	for sl, r in mine do
		if not r.weld.Parent or r.weld.Part0 ~= torso or not r.item.Parent then
			if r.item.Parent then
				r.item:SetAttribute("StowedBy", nil)
				r.item:SetAttribute("StowSlot", nil)
				CollectionService:RemoveTag(r.item, "Stowed")
			end
			mine[sl] = nil
		end
	end
	return mine
end

-- puts an item (not in a hand) into this pocket
local function pocketInto(player: Player, item: Model, torso: BasePart, slot: number)
	local handle = item.PrimaryPart :: BasePart
	local mine = stowed[player] or {}
	stowed[player] = mine
	item:SetAttribute("StowedBy", player.UserId)
	item:SetAttribute("StowSlot", slot)
	CollectionService:AddTag(item, "Stowed")
	local saved: { [BasePart]: { boolean } } = {}
	for _, p in item:GetDescendants() do
		if p:IsA("BasePart") then
			saved[p] = { p.CanCollide, p.Massless }
			p.CanCollide = false
			p.Massless = true
			p.Anchored = false
		end
	end
	local weld = Instance.new("Weld")
	weld.Name = "PocketWeld"
	weld.Part0 = torso
	weld.Part1 = handle
	weld.C0 = pocketCFrame(Items.Kind(item), slot)
	weld.Parent = handle
	mine[slot] = { item = item, weld = weld, saved = saved }
	pcall(function()
		handle:SetNetworkOwner(player)
	end)
end

-- (v2.8) what is in this player's pockets right now: { [slot] = item }
function OwnershipService.Pockets(player: Player): { [number]: Model }
	local out = {}
	local char = player.Character
	local torso = char and char:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return out
	end
	for sl, r in prunePockets(player, torso) do
		out[sl] = r.item
	end
	return out
end

-- (v2.8) puts an item that is NOT in a hand straight into a pocket (the sheath you spawn with). Returns the slot, or nil
-- when both pockets are full.
function OwnershipService.PocketItem(player: Player, item: Model, prefer: number?): number?
	local char = player.Character
	local torso = char and char:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") or not item.PrimaryPart or char:GetAttribute("Dead") then
		return nil
	end
	local mine = prunePockets(player, torso)
	local slot = prefer == 2 and 2 or 1
	if mine[slot] then
		slot = 3 - slot
	end
	if mine[slot] then
		return nil
	end
	if items[item] then
		dropItem(item)
	end
	pocketInto(player, item, torso, slot)
	return slot
end

-- the held item goes into a pocket (side = the hand it was in: Left -> slot 1, Right -> slot 2 when free)
function OwnershipService.Stow(player: Player, part: BasePart, side: string?)
	local item = itemOfPart(part)
	local char = player.Character
	local torso = char and char:FindFirstChild("Torso")
	local rec = item and items[item]
	if not item or not rec or rec.by ~= player or not torso or not torso:IsA("BasePart") or char:GetAttribute("Dead") then
		return
	end
	local handle = item.PrimaryPart
	if not handle then
		return
	end
	local mine = prunePockets(player, torso)
	if OwnershipService.StowHook then
		local now = {}
		for sl, r in mine do
			now[sl] = r.item
		end
		local ok, handled = pcall(OwnershipService.StowHook, player, item, side == "Left" and 1 or 2, now)
		if ok and handled then
			return
		end
	end
	local slot = side == "Left" and 1 or 2
	if mine[slot] then
		slot = 3 - slot
	end
	if mine[slot] then
		return -- both pockets are full
	end
	dropItem(item) -- out of the hand
	pocketInto(player, item, torso, slot)
end

-- take it out again (it is loose at the pocket; the client puts it into the hand)
function OwnershipService.Unstow(player: Player, part: BasePart, side: string?)
	local item = itemOfPart(part)
	if item and OwnershipService.UnstowHook then
		local ok, handled = pcall(OwnershipService.UnstowHook, player, item, side)
		if ok and handled then
			return
		end
	end
	local mine = stowed[player]
	if not item or not mine then
		return
	end
	for slot, rec in mine do
		if rec.item == item then
			mine[slot] = nil
			if rec.weld.Parent then
				rec.weld:Destroy()
			end
			for p, st in rec.saved do
				if p.Parent then
					p.CanCollide = st[1]
					p.Massless = st[2]
				end
			end
			item:SetAttribute("StowedBy", nil)
			item:SetAttribute("StowSlot", nil)
			CollectionService:RemoveTag(item, "Stowed")
			return
		end
	end
end

function OwnershipService.ItemHolder(item: Model): Player?
	local rec = items[item]
	return rec and rec.by or nil
end
OwnershipService.GunHolder = OwnershipService.ItemHolder

-- the item a player holds in a given hand (or any hand)
function OwnershipService.HeldItems(player: Player): { Model }
	local list = {}
	for item, rec in items do
		if rec.by == player and item.Parent then
			table.insert(list, item)
		end
	end
	return list
end

-- side ("Left" / "Right") -> the item a player holds in that hand
function OwnershipService.HeldItemSides(player: Player): { [string]: Model }
	local out = {}
	for item, rec in items do
		if rec.by == player and item.Parent then
			out[rec.side] = item
		end
	end
	return out
end

-- Server-assigned equipment must also update the owning client's hand state.
function OwnershipService.Equip(player: Player, item: Model, side: string?): boolean
	local hand = side == "Left" and "Left" or "Right"
	local held = OwnershipService.HeldItemSides(player)[hand]
	if held and held ~= item then dropItem(held) end
	if not item.PrimaryPart then return false end
	OwnershipService.Grab(player, item.PrimaryPart, hand)
	if OwnershipService.ItemHolder(item) ~= player then return false end
	GripRemote:FireClient(player, "equip", item, hand)
	return true
end

-- the body a player is dragging / holding (bandaging someone else)
function OwnershipService.HeldBody(player: Player): Model?
	for victim, d in drags do
		if d.by == player and victim.Parent then
			return victim
		end
	end
	for root, h in holders do
		if h[player] and root.Parent then
			local b = bodyModelOf(root)
			if b then
				return b
			end
		end
	end
	return nil
end

----------------------------------------------------------------------
-- grab / release
----------------------------------------------------------------------

function OwnershipService.Grab(player: Player, part: BasePart, side: string?, localPoint: Vector3?)
	-- (v2.1 fix) a spear / knife / bolt lodged in a wall is ANCHORED: "grounded" parts are refused below, so the item was never pulled out
	-- and the hand stayed locked to the wall. A lodged item is pulled out first (ItemService.Unstick), then it is grabbed like any other.
	do
		local lodged = Items.ModelOf(part)
		if lodged and lodged:GetAttribute("Stuck") and OwnershipService.OnHold then
			OwnershipService.OnHold(lodged)
		end
	end
	-- (v2.8) rubble that came to rest was pinned where it lies (no physics): taking hold of it lets it go again
	if part.Anchored and part:GetAttribute("Settled") then
		part.Anchored = false
		part:SetAttribute("Settled", nil)
	end
	if part:IsGrounded() then
		return
	end
	local torso = torsoOf(player)
	if not torso or (torso.Position - part.Position).Magnitude > Config.MaxGrabDistanceServer + part.Size.Magnitude * 0.5 then
		return
	end
	local item = Items.ModelOf(part)
	if item then
		holdItem(player, item, side)
		return
	end
	local body = bodyModelOf(part)
	if body then
		local victimPlayer = Players:GetPlayerFromCharacter(body)
		if victimPlayer then
			if victimPlayer ~= player then
				-- grabbing someone knocks them into ragdoll; then you drag them
				if not body:GetAttribute("Dead") and not drags[body] then
					DamageService.Knock(body, nil, nil, 2.5)
					body:SetAttribute("Knocked", true)
				end
				startDrag(player, victimPlayer, body, false, part, localPoint, side)
			end
			return
		end
		-- dummies / corpses
		for _, root in rootsOf(body) do
			holders[root] = holders[root] or {}
			holders[root][player] = (holders[root][player] or 0) + 1
			setOwner(root, player)
		end
		return
	end
	local root = part.AssemblyRootPart
	if not root then
		return
	end
	-- a car somebody drives / the wrecking ball stay with their simulator (the client holds them
	-- with a force only)
	local model = part:FindFirstAncestorOfClass("Model")
	if (model and model:GetAttribute("Car") and model:GetAttribute("DriverId")) or root:GetAttribute("NoOwnershipGrab") then
		return
	end
	holders[root] = holders[root] or {}
	holders[root][player] = (holders[root][player] or 0) + 1
	setOwner(root, player)
	markHeld(root, player)
end

local function releaseRoot(player: Player, root: BasePart)
	local h = holders[root]
	if h and h[player] then
		h[player] -= 1
		if h[player] <= 0 then
			h[player] = nil
		end
		markHeld(root, player)
		if next(h) == nil then
			holders[root] = nil
			task.delay(1.5, function()
				if holders[root] == nil and root.Parent then
					setOwner(root, nil)
				end
			end)
		end
	end
end

function OwnershipService.Release(player: Player, part: BasePart, side: string?, throw: Vector3?)
	local item = Items.ModelOf(part)
	if item then
		local rec = items[item]
		if rec and rec.by == player then
			dropItem(item)
		end
		return
	end
	local body = bodyModelOf(part)
	if body then
		local d = drags[body]
		if d and d.by == player then
			dragHandReleased(body, side, throw)
			return
		end
		for _, root in rootsOf(body) do
			releaseRoot(player, root)
		end
		return
	end
	local root = part.AssemblyRootPart
	if root then
		releaseRoot(player, root)
	end
end

function OwnershipService.ReleaseAll(player: Player)
	OwnershipService.BeamDrop(player)
	for root, h in holders do
		if h[player] then
			h[player] = 1
			releaseRoot(player, root)
		end
	end
	for victim, d in drags do
		if d.by == player then
			endDrag(victim)
		end
	end
	for item, rec in items do
		if rec.by == player then
			dropItem(item)
		end
	end
end

-- a dragged player's own character changed (respawn) / was removed
function OwnershipService.ForgetBody(model: Model)
	if drags[model] then
		endDrag(model)
	end
end

-- somebody holds this body (a hand on a dummy / NPC, or the physics gun)
function OwnershipService.IsHeldBody(model: Model): boolean
	for _, root in rootsOf(model) do
		if holders[root] then
			return true
		end
		for _, b in beams do
			if table.find(b.roots, root) then
				return true
			end
		end
	end
	return false
end

function OwnershipService.IsDragged(model: Model): boolean
	return drags[model] ~= nil
end

function OwnershipService.Init()
	GripRemote.OnServerEvent:Connect(function(player, action, part, side, localPoint)
		if player.Character and player.Character:GetAttribute("ControlActive") then return end
		if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then
			return
		end
		if action == "stow" then
			OwnershipService.Stow(player, part, side)
		elseif action == "unstow" then
			OwnershipService.Unstow(player, part, (side == "Left" or side == "Right") and side or nil)
		elseif action == "grab" then
			OwnershipService.Grab(
				player,
				part,
				(side == "Left" or side == "Right") and side or nil,
				typeof(localPoint) == "Vector3" and localPoint or nil
			)
		elseif action == "release" then
			-- (v2.0) letting go of a player with a swing throws them (their own client does the throw)
			local throw = nil
			if typeof(localPoint) == "Vector3" and localPoint == localPoint then
				throw = localPoint.Magnitude > Config.DragThrowMax and localPoint.Unit * Config.DragThrowMax or localPoint
			end
			OwnershipService.Release(player, part, (side == "Left" or side == "Right") and side or nil, throw)
		end
	end)
	-- (v2.0 fix) the carried body on its own player's screen: Roblox does not move a player's own character there
	-- while another machine simulates it (the victim saw the dragger walk away and their body stay behind - and on
	-- release it snapped back). The server sends where the body is ~15 times a second; their client follows it.
	task.spawn(function()
		while Config.DragOwnerMode do
			task.wait(1 / 15)
			for victim, d in drags do
				if d.owned and victim.Parent and d.owner and d.owner.Parent and not victim:GetAttribute("Dead") then
					FXRemote:FireClient(d.owner, { t = "dragsnap", body = victim, snap = snapOf(victim) })
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		OwnershipService.ReleaseAll(player)
		local c = player.Character
		if c then
			OwnershipService.ForgetBody(c)
		end
		for victim, d in drags do
			if d.owner == player then
				drags[victim] = nil
			end
		end
		beams[player] = nil
	end)
end

return OwnershipService
