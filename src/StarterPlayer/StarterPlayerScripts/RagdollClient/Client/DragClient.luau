--!nonstrict
-- DragClient: another player grabbed YOUR body (by hand or with the physics gun).
--
-- Your body stays yours: this client keeps simulating it, exactly like when you walk. A force on
-- the part they grabbed pulls it to their hand (as you see it, a little ahead of where they move so
-- that on THEIR screen your body hangs right at their hand), the rest of the body dangles.
-- Nothing of your body is handed to the other player and nothing joins the two bodies, so both
-- of you, and everybody else, see both bodies move all the time.
-- (Before v1.8 the dragger's machine simulated your body. On your own screen that left you or the
-- dragger frozen in place.)
-- (v2.0, Config.DragOwnerMode) "the dragger carries you like a dummy": Roblox keeps a player's own character with
-- that player, so on the victim's screen the body froze where it was grabbed. Off now.
-- (v2.0) back to this client pulling the body, and every OTHER screen shows a local copy hanging right from the
-- dragger's hand (DragPuppets): nobody sees the delay any more, so the pull only aims a little ahead. It keeps
-- pulling a body that died in the hand (it is still yours until you respawn).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local DragClient = {}

type Drag = {
	body: Model,
	by: number,
	part: BasePart,
	side: string,
	beam: boolean,
	pos: Vector3?,
	att: Attachment?,
	ap: AlignPosition?,
	owned: boolean?,
	follow: { [string]: { any } }?, -- (v2.0) owned: where the server says my body is (dragsnap)
	mass: number,
	t0: number,
	slick: { [BasePart]: PhysicalProperties? }?,
}

local player = Players.LocalPlayer
local active: Drag? = nil

local function cleanup()
	local d = active
	active = nil
	if d then
		-- (v1.9.1) friction back to normal
		if d.slick then
			for p, old in d.slick do
				if p.Parent then
					p.CustomPhysicalProperties = old
				end
			end
		end
		if d.ap and d.ap.Parent then
			d.ap:Destroy()
		end
		if d.att and d.att.Parent then
			d.att:Destroy()
		end
	end
end

function DragClient.IsDragged(body: Instance): boolean
	return active ~= nil and active.body == body
end

-- who drags me (UserId) or nil
function DragClient.By(): number?
	return active and active.by or nil
end

-- payload: { body, by = UserId, part = name, lp = Vector3 (grab point on that part), side, beam }
function DragClient.Start(payload)
	local body = payload.body
	if typeof(body) ~= "Instance" or body ~= player.Character then
		if payload.beam == true then
			warn("[physgun] a beam grab arrived for a body that is not my character:", body)
		end
		return
	end
	local part = typeof(payload.part) == "string" and body:FindFirstChild(payload.part) or nil
	if not (part and part:IsA("BasePart")) then
		part = body:FindFirstChild("Torso")
	end
	if not (part and part:IsA("BasePart")) then
		return
	end
	-- a new hand / a new grab point: start over
	cleanup()
	if payload.owned == true then
		-- (v2.0) the dragger's machine carries the limp body: nothing to pull here, we only watch (and stay down)
		active = {
			body = body,
			by = typeof(payload.by) == "number" and payload.by or 0,
			part = part,
			side = payload.side == "Left" and "Left" or "Right",
			beam = payload.beam == true,
			pos = nil,
			att = nil,
			ap = nil,
			owned = true,
			mass = 0,
			t0 = os.clock(),
		}
		return
	end
	local lp = typeof(payload.lp) == "Vector3" and payload.lp or Vector3.zero
	if lp.Magnitude > part.Size.Magnitude then
		lp = Vector3.zero
	end
	local att = Instance.new("Attachment")
	att.Name = "DraggedHere"
	att.Position = lp
	att.Parent = part
	local mass = 0
	for _, p in body:GetChildren() do
		if p:IsA("BasePart") then
			mass += p:GetMass()
		end
	end
	local ap = Instance.new("AlignPosition")
	ap.Name = "Dragged"
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.Position = att.WorldPosition
	ap.MaxForce = mass * workspace.Gravity * Config.DragPullForce
	ap.MaxVelocity = Config.DragMaxSpeed
	ap.Responsiveness = Config.DragResponsiveness
	ap.Parent = part
	-- (v1.9.1) a dragged body used to scrape along the floor with full friction ("too heavy"): while it is dragged
	-- its parts are slippery
	local slick: { [BasePart]: PhysicalProperties? } = {}
	for _, p in body:GetChildren() do
		if p:IsA("BasePart") then
			slick[p] = p.CustomPhysicalProperties
			local cur = p.CurrentPhysicalProperties
			p.CustomPhysicalProperties = PhysicalProperties.new(cur.Density, 0.08, cur.Elasticity, 100, cur.ElasticityWeight)
		end
	end
	active = {
		slick = slick,
		body = body,
		by = typeof(payload.by) == "number" and payload.by or 0,
		part = part,
		side = payload.side == "Left" and "Left" or "Right",
		beam = payload.beam == true,
		pos = nil,
		att = att,
		ap = ap,
		mass = mass,
		t0 = os.clock(),
	}
end

-- (v2.0) carried by someone else's machine: where my body is right now (the server relays it)
function DragClient.Follow(payload)
	local d = active
	if d and d.owned and payload.body == d.body and typeof(payload.snap) == "table" then
		d.follow = payload.snap
	end
end

-- the physics gun's beam end moved (payload.pos)
function DragClient.Move(payload)
	local d = active
	if d and typeof(payload.pos) == "Vector3" and payload.pos == payload.pos then
		d.pos = payload.pos
	end
end

local function apply(body: Instance, snap)
	for name, rec in snap do
		local p = typeof(name) == "string" and body:FindFirstChild(name)
		if p and p:IsA("BasePart") and typeof(rec) == "table" and typeof(rec[1]) == "CFrame" then
			pcall(function()
				p.CFrame = rec[1]
				if typeof(rec[2]) == "Vector3" then
					p.AssemblyLinearVelocity = rec[2]
				end
			end)
		end
	end
end

-- payload: { body, snap? } - snap (getting out of a car as the passenger): where the body is now
-- ({ [partName] = { CFrame, velocity } }); the body comes back to this client exactly there.
function DragClient.Stop(body: Instance?, snap: any?)
	if active and (body == nil or active.body == body) then
		cleanup()
	end
	if typeof(snap) ~= "table" or not body or body ~= player.Character then
		return
	end
	local rec = snap["Torso"]
	local dropPos: Vector3? = (typeof(rec) == "table" and typeof(rec[1]) == "CFrame") and rec[1].Position or nil
	apply(body, snap)
	if not dropPos then
		return
	end
	-- some Roblox versions keep the old state of a body whose owner changes back for a moment:
	-- check again right after
	local vel = (typeof(rec[2]) == "Vector3") and rec[2] or Vector3.zero
	for _, delay in { 0.12, 0.35 } do
		task.delay(delay, function()
			local torso = body:FindFirstChild("Torso")
			if torso and torso:IsA("BasePart") and body.Parent and not active then
				-- (v1.9) only put it back when the OLD state really came back. A fast body (a bail-out, a huge
				-- knockback) is legitimately far from "drop point + velocity * time": that used to teleport it back.
				local popped: boolean
				if vel.Magnitude > 12 then
					popped = (torso.Position - dropPos):Dot(vel.Unit) < -6 -- behind where it was dropped
				else
					popped = (torso.Position - (dropPos + vel * delay)).Magnitude > 10
				end
				if popped then
					apply(body, snap)
				end
			end
		end)
	end
end

-- where the hand that holds me is, a little ahead in time (it reached me late, and my body
-- reaches the dragger late again: aiming a bit ahead keeps me at their hand on their screen)
local function handTarget(d: Drag): Vector3?
	local by = Players:GetPlayerByUserId(d.by)
	local char = by and by.Character
	if not char then
		return nil
	end
	local arm = char:FindFirstChild(d.side == "Left" and "Left Arm" or "Right Arm")
	local torso = char:FindFirstChild("Torso")
	if not (arm and arm:IsA("BasePart")) then
		arm = torso
	end
	if not (arm and arm:IsA("BasePart")) then
		return nil
	end
	local hand = arm.CFrame:PointToWorldSpace(Vector3.new(0, -1, 0)) -- (the dragger's grip point, Hands)
	local vel = (torso and torso:IsA("BasePart")) and torso.AssemblyLinearVelocity or Vector3.zero
	local ping = 0.08
	pcall(function()
		ping = player:GetNetworkPing()
	end)
	local lead = math.clamp(ping * Config.DragLead, 0, Config.DragLeadMax)
	if vel.Magnitude > 60 then
		vel = vel.Unit * 60
	end
	return hand + vel * lead
end

local function step(_t: number, dt: number)
	local d = active
	if not d then
		return
	end
	local released = d.body:GetAttribute("DraggedBy") == nil and os.clock() - d.t0 > 0.6
	if not d.body.Parent or d.body ~= player.Character or not d.part.Parent or released then
		cleanup()
		return
	end
	if d.owned then
		-- my own screen: the body glides to where the dragger's machine has it (no freeze, no snapping back)
		local snap = d.follow
		if snap then
			local k = math.min(1, (dt or 1 / 60) * 16)
			for name, rec in snap do
				local p = d.body:FindFirstChild(name)
				if p and p:IsA("BasePart") and typeof(rec) == "table" and typeof(rec[1]) == "CFrame" then
					pcall(function()
						if (p.Position - rec[1].Position).Magnitude > 25 then
							p.CFrame = rec[1]
						else
							p.CFrame = p.CFrame:Lerp(rec[1], k)
						end
						if typeof(rec[2]) == "Vector3" then
							p.AssemblyLinearVelocity = rec[2]
						end
					end)
				end
			end
		end
		return
	end
	if not d.ap then
		return
	end
	local target = d.beam and d.pos or handTarget(d)
	if not target then
		return
	end
	d.ap.Position = target
	-- (lighter when limbs are gone)
	d.ap.MaxForce = d.mass * workspace.Gravity * Config.DragPullForce * (d.beam and 3 or 1)
	if d.beam then
		d.ap.Responsiveness = 90 -- (the physics gun pulls hard)
	end
end

function DragClient.Init()
	RunService.Stepped:Connect(step)
end

return DragClient
