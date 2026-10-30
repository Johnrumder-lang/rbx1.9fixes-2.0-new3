--!nonstrict
-- ContactSolver: decides WHAT a body part just hit and how bad it is. Shared by the client sensor
-- (own character) and the server sensor (dummies, corpses).
--   pierce : a sharp object went in (spikes, spear tips, thin rods tip-first)
--   energy : a moving object hit the body (kinetic energy of the collision)
--   impact : the body hit the world (ground / wall) -> velocity change
-- plus Crush(): weight of objects resting on a body part.

local Config = require(script.Parent:WaitForChild("Config"))
local HitMath = require(script.Parent:WaitForChild("HitMath"))
local Items = require(script.Parent:WaitForChild("Items"))

local ContactSolver = {}

-- Remembers velocities of loose objects near bodies, so the speed BEFORE a collision is known.
local VelocityCache = {}
VelocityCache.__index = VelocityCache

function ContactSolver.NewVelocityCache()
	return setmetatable({ map = {} :: { [BasePart]: { v: Vector3, t: number } } }, VelocityCache)
end

function VelocityCache:Track(center: Vector3, radius: number, params: OverlapParams)
	local now = os.clock()
	for _, p in workspace:GetPartBoundsInRadius(center, radius, params) do
		if not p.Anchored then
			local root = p.AssemblyRootPart or p
			local rec = self.map[root]
			local v = root.AssemblyLinearVelocity
			if rec then
				-- keep the faster recent sample (pre-impact speed survives one frame of collision)
				if now - rec.t > 0.08 or v.Magnitude >= rec.v.Magnitude * 0.9 then
					rec.v = v
					rec.t = now
				end
			else
				self.map[root] = { v = v, t = now }
			end
		end
	end
	for root, rec in self.map do
		if now - rec.t > 0.5 or not root.Parent then
			self.map[root] = nil
		end
	end
end

function VelocityCache:Get(part: BasePart): Vector3
	if part.Anchored then
		return Vector3.zero
	end
	local root = part.AssemblyRootPart or part
	local rec = self.map[root]
	if rec and os.clock() - rec.t < 0.25 then
		return rec.v
	end
	return root.AssemblyLinearVelocity
end

export type Result = { kind: string, value: number, other: BasePart?, sharpness: number? }

-- vBefore: the body part's velocity just before the hit; dv: its velocity change.
function ContactSolver.Solve(point: Vector3, vBefore: Vector3, dv: number, bodyMass: number, cache, params: OverlapParams): Result?
	local best: Result? = nil
	local bestScore = 0
	for _, cand in workspace:GetPartBoundsInRadius(point, 1.5, params) do
		if not cand.CanCollide or cand:GetAttribute("Gore") then
			continue
		end
		-- a weapon somebody holds: the one swinging it reports the hit (no double damage)
		local item = Items.ModelOf(cand)
		if item and item:GetAttribute("HolderId") then
			continue
		end
		local objV = cache and cache:Get(cand) or cand.AssemblyLinearVelocity
		local relVel = vBefore - objV
		local relSpeed = relVel.Magnitude
		local sharp = HitMath.EffectiveSharpness(cand, point, relVel)
		if sharp > 0 then
			local threshold = HitMath.PierceThreshold(sharp)
			if relSpeed >= threshold then
				local score = 1000 + (relSpeed - threshold)
				if score > bestScore then
					bestScore = score
					best = { kind = "pierce", value = relSpeed, other = cand, sharpness = sharp }
				end
			end
		end
		if not cand:IsGrounded() and objV.Magnitude >= Config.ObjectHitMinSpeed * 0.6 and relSpeed >= Config.ObjectHitMinSpeed then
			local e = HitMath.ImpactEnergy(cand.AssemblyMass, bodyMass, relSpeed)
			local score = HitMath.EnergyDamage(e) + 1
			if (not best or best.kind ~= "pierce") and score > bestScore then
				bestScore = score
				best = { kind = "energy", value = e, other = cand }
			end
		end
	end
	if best then
		return best
	end
	if dv >= Config.ImpactMin then
		return { kind = "impact", value = dv }
	end
	return nil
end

-- Damage per second from objects resting on top of a body part.
function ContactSolver.Crush(part: BasePart, params: OverlapParams, cache): (number, BasePart?)
	local force = 0
	local heaviest: BasePart? = nil
	local counted = {}
	for _, p in workspace:GetPartBoundsInBox(part.CFrame, part.Size + Vector3.new(0.35, 0.35, 0.35), params) do
		if p.Anchored or not p.CanCollide or p:GetAttribute("Gore") then
			continue
		end
		local root = p.AssemblyRootPart or p
		if counted[root] then
			continue
		end
		counted[root] = true
		-- a car stands on its own wheels (touching it is not being crushed; running over is
		-- handled by the car), and only something really ON TOP of the body part weighs on it
		local model = p:FindFirstAncestorOfClass("Model")
		if model and model:GetAttribute("Car") then
			continue
		end
		local lowest = p.Position.Y - (math.abs(p.CFrame.UpVector.Y) * p.Size.Y + math.abs(p.CFrame.RightVector.Y) * p.Size.X + math.abs(p.CFrame.LookVector.Y) * p.Size.Z) * 0.5
		if lowest < part.Position.Y - 0.1 then
			continue
		end
		local v = cache and cache:Get(p) or root.AssemblyLinearVelocity
		if v.Magnitude < 6 and root.Position.Y > part.Position.Y - 0.2 then
			force += root.AssemblyMass * workspace.Gravity
			if not heaviest or root.AssemblyMass > heaviest.AssemblyMass then
				heaviest = root
			end
		end
	end
	local dps = math.max(0, force - Config.CrushForceMin) / Config.CrushForcePerDamage
	return dps, heaviest
end

-- While a body hangs on a spike the spike is INSIDE it: without this the collision solver pushes
-- the body off the spike every frame while the impale joint pulls it back (jitter / push-out).
-- Makes the body's colliders ignore the spike (and the spike's tip / shaft / neighbours).
-- The constraints are parented to `holder`, so destroying the impale cleans them up.
function ContactSolver.PassThrough(body: Model, spike: BasePart, point: Vector3, holder: Instance): { Instance }
	local group = { spike }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { body }
	for _, p in workspace:GetPartBoundsInRadius(point, 1.8, params) do
		if p ~= spike and p.CanCollide and HitMath.Sharpness(p) > 0.02 then
			table.insert(group, p)
		end
	end
	local made = {}
	for _, d in body:GetDescendants() do
		if d:IsA("BasePart") and (d.CanCollide or d.Name == "Collider") then
			for _, s in group do
				local nc = Instance.new("NoCollisionConstraint")
				nc.Name = "ImpaleNC"
				nc.Part0 = d
				nc.Part1 = s
				nc.Parent = holder
				table.insert(made, nc)
			end
		end
	end
	return made
end

return ContactSolver
