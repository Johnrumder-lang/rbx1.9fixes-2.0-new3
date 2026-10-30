--!nonstrict
-- SeverService (v2.8): SEVER - admins only (or whoever an admin gave it to). Its key is on the cyber bar.
-- A slash along the middle of your screen: an invisible blade-thin plane through your eye, spanned by where you look and
-- your screen's left-right. Everything it crosses in front of you (up to Config.SeverRange studs) is cut exactly there:
--   * a body: the limb the plane goes through comes off, through the neck the head comes off, through the trunk it is cut
--     in two (dead).
--   * a part of the world (a wall, a car, a crate): it becomes two pieces, split on that plane (CSG). The smaller piece of an
--     anchored part falls; loose things just fall apart.
-- Huge parts (the ground, roads) and the people's own map markers are left alone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))

local SeverService = {}

local deps: any = {}
local Remote: RemoteEvent
local last: { [Player]: number } = {}

local RANGE = 140
local WIDTH = 30 -- studs to each side of the screen's middle
local MAX_CUTS = 12
local MAX_SIZE = 140 -- (no cutting of the ground)

local function regionOf(part: BasePart): string?
	return RigInfo.PartRegion[part.Name]
end

-- the signed distance of a point to the plane
local function side(point: Vector3, origin: Vector3, normal: Vector3): number
	return (point - origin):Dot(normal)
end

-- how far a box reaches along a direction (half)
local function reach(part: BasePart, dir: Vector3): number
	local cf = part.CFrame
	local h = part.Size / 2
	return math.abs(cf.RightVector:Dot(dir)) * h.X + math.abs(cf.UpVector:Dot(dir)) * h.Y + math.abs(cf.LookVector:Dot(dir)) * h.Z
end

local function cutBody(model: Model, origin: Vector3, normal: Vector3, by: Player)
	local cut = {}
	for _, name in { "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "Torso" } do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") and math.abs(side(p.Position, origin, normal)) <= reach(p, normal) then
			table.insert(cut, p)
		end
	end
	for _, p in cut do
		local region = regionOf(p)
		if region and model:GetAttribute("Severed_" .. region) ~= true then
			local point = p.Position - normal * side(p.Position, origin, normal)
			deps.DamageService.ApplyDamage(model, region, 400, point, {
				cause = "Severed by " .. by.DisplayName, allowSever = true, severAt = 1, attacker = by, bleed = 2, bleedTime = 20,
			})
			if region == "Torso" then
				pcall(deps.GoreService.Gibs, point, 8, 30)
				pcall(deps.GoreService.Burst, point, normal, 40, 26)
			end
		end
	end
end

-- splits one part on the plane into two pieces (two subtractions: each keeps one side)
local function cutPart(part: BasePart, origin: Vector3, normal: Vector3): boolean
	local s = part.Size
	if s.X > MAX_SIZE or s.Y > MAX_SIZE or s.Z > MAX_SIZE then
		return false
	end
	local L = s.Magnitude * 2 + 4
	local center = part.Position - normal * side(part.Position, origin, normal)
	local ref = math.abs(normal.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis
	local right = normal:Cross(ref).Unit
	local function cutter(sign: number): Part
		local c = Instance.new("Part")
		c.Size = Vector3.new(L, L, L)
		c.CFrame = CFrame.fromMatrix(center + normal * sign * (L / 2), right, normal)
		c.Anchored = true
		c.CanCollide = false
		return c
	end
	local ca, cb = cutter(1), cutter(-1)
	local okA, a = pcall(function()
		return part:SubtractAsync({ ca })
	end)
	local okB, b = pcall(function()
		return part:SubtractAsync({ cb })
	end)
	ca:Destroy()
	cb:Destroy()
	if not okA or not okB or not a or not b then
		return false
	end
	local parent = part.Parent
	local anchored = part.Anchored
	for _, piece in { a, b } do
		piece.Name = part.Name .. "Piece"
		piece.UsePartColor = true
		piece.Color = part.Color
		piece.Material = part.Material
		piece.CanCollide = part.CanCollide
		piece.Anchored = anchored
		piece.Parent = parent
	end
	-- an anchored wall: the smaller piece comes loose and falls; a loose thing falls apart
	local va = a.Size.X * a.Size.Y * a.Size.Z
	local vb = b.Size.X * b.Size.Y * b.Size.Z
	if anchored then
		local small = va < vb and a or b
		small.Anchored = false
		small:SetAttribute("Debris", true)
	else
		a.AssemblyLinearVelocity = part.AssemblyLinearVelocity + normal * 6
		b.AssemblyLinearVelocity = part.AssemblyLinearVelocity - normal * 6
	end
	part:Destroy()
	return true
end

-- (v2.8) STILL CUT cuts loose things with it
SeverService.CutPart = cutPart
SeverService.CutBody = cutBody

local function sever(p: Player, origin: any, look: any, right: any)
	if not Items.Has(p, "sever") then
		return
	end
	if typeof(origin) ~= "Vector3" or typeof(look) ~= "Vector3" or typeof(right) ~= "Vector3" then
		return
	end
	if look.Magnitude < 0.5 or right.Magnitude < 0.5 or origin ~= origin then
		return
	end
	local char = p.Character
	local head = char and char:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") or (head.Position - origin).Magnitude > 60 then
		return
	end
	local now = os.clock()
	if now - (last[p] or 0) < Config.SeverCooldown * 0.9 then
		return
	end
	last[p] = now
	p:SetAttribute("CyCD_sever", workspace:GetServerTimeNow() + Config.SeverCooldown)
	look, right = look.Unit, right.Unit
	local normal = look:Cross(right).Unit
	Remote:FireAllClients("fx", { t = "sever", p = origin, l = look, r = right })
	pcall(deps.GoreService.Sound, "slash", head, 1)
	-- what lies on the plane, in front, within reach
	local box = CFrame.fromMatrix(origin + look * (RANGE / 2), right, normal)
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { char, workspace:FindFirstChild("FX") }
	local parts = workspace:GetPartBoundsInBox(box, Vector3.new(WIDTH * 2, 1, RANGE), op)
	local bodies = {}
	local cuts = 0
	for _, part in parts do
		local m = part:FindFirstAncestorOfClass("Model")
		local body = m and deps.DamageService.BodyOf(part)
		if body then
			bodies[body] = true
		elseif cuts < MAX_CUTS and part:IsA("Part") and not part:IsA("SpawnLocation") and part.Transparency < 0.95 and not part.Locked
			and part.Name ~= "Baseplate" and not (m and m:GetAttribute("RagdollRig")) then
			if math.abs(side(part.Position, origin, normal)) <= reach(part, normal) and side(part.Position, origin, look) > 0 then
				if cutPart(part, origin, normal) then
					cuts += 1
				end
			end
		end
	end
	for body in bodies do
		if body ~= char and body.Parent then
			cutBody(body, origin, normal, p)
		end
	end
end

function SeverService.Init(d: any)
	deps = d
	Remote = d.Remote
	Remote.OnServerEvent:Connect(function(p, action, a, b, c)
		if action == "sever" then
			sever(p, a, b, c)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		last[p] = nil
	end)
end

return SeverService
