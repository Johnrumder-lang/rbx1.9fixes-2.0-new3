--!nonstrict
-- HitMath: physics formulas shared by client and server so both agree on damage.
--   * Sharpness(part): 0..1 from the geometry (thin rods / points / blades are sharp)
--   * PierceThreshold(sharpness): speed needed to pierce flesh
--   * ImpactEnergy(...): kinetic energy of a collision between an object and a body

local Config = require(script.Parent:WaitForChild("Config"))

local HitMath = {}

local function sorted3(v: Vector3): (number, number, number)
	local a, b, c = v.X, v.Y, v.Z
	if a > b then
		a, b = b, a
	end
	if b > c then
		b, c = c, b
	end
	if a > b then
		a, b = b, a
	end
	return a, b, c
end

-- How sharp a part is. Attribute "Sharpness" (0..1) overrides the geometry guess.
function HitMath.Sharpness(part: BasePart): number
	local attr = part:GetAttribute("Sharpness")
	if typeof(attr) == "number" then
		return math.clamp(attr, 0, 1)
	end
	if not part.CanCollide or part:GetAttribute("Gore") then
		return 0
	end
	local size = part.Size
	if part:IsA("Part") then
		if part.Shape == Enum.PartType.Ball then
			return 0
		elseif part.Shape == Enum.PartType.Cylinder then
			local d = math.min(size.Y, size.Z)
			size = Vector3.new(size.X, d, d)
		end
	end
	local a, b, c = sorted3(size)
	-- a point / spike: both cross dimensions small and the thing is long
	local point = math.clamp((0.55 - b) / 0.4, 0, 1) * math.clamp((c / math.max(b, 0.01) - 3) / 5, 0, 1)
	-- a blade: one dimension paper thin, the other two reasonably large
	local blade = math.clamp((0.22 - a) / 0.18, 0, 1) * math.clamp((b - 0.6) / 1.2, 0, 1) * 0.5
	local wedge = 0
	if part:IsA("WedgePart") or part:IsA("CornerWedgePart") then
		-- very acute wedges have a cutting edge / point
		local acute = math.deg(math.atan(math.min(size.Y, size.Z) / math.max(size.Y, size.Z, 0.01)))
		wedge = math.clamp(1 - acute / 22, 0, 1) * (part:IsA("CornerWedgePart") and 0.7 or 0.45)
	end
	return math.max(point, blade, wedge)
end

-- Sharpness for one particular hit: rods and spikes only stab with their tips (hit along the axis),
-- blades only cut with their edge. relVel = velocity of the body relative to the object.
function HitMath.EffectiveSharpness(part: BasePart, contact: Vector3, relVel: Vector3): number
	local s = HitMath.Sharpness(part)
	if s <= 0.02 or relVel.Magnitude < 1 then
		return 0
	end
	local dir = relVel.Unit
	local size = part.Size
	local cf = part.CFrame
	local isCylinder = part:IsA("Part") and part.Shape == Enum.PartType.Cylinder
	-- local axes sorted by size
	local axes = {
		{ v = cf.RightVector, len = size.X },
		{ v = cf.UpVector, len = isCylinder and math.min(size.Y, size.Z) or size.Y },
		{ v = cf.LookVector, len = isCylinder and math.min(size.Y, size.Z) or size.Z },
	}
	table.sort(axes, function(a, b)
		return a.len > b.len
	end)
	local long, mid, thin = axes[1], axes[2], axes[3]
	if part:IsA("WedgePart") or part:IsA("CornerWedgePart") then
		return s
	end
	if mid.len < 0.6 and long.len > mid.len * 2.5 then
		-- spike / rod: must hit the tip, roughly along the axis
		local along = math.abs(dir:Dot(long.v))
		local localPos = cf:PointToObjectSpace(contact)
		local axisCoord = math.abs(localPos:Dot(cf:VectorToObjectSpace(long.v)))
		local half = long.len * 0.5
		local nearTip = axisCoord >= half - math.max(0.6, half * 0.3)
		if along > 0.5 and nearTip then
			return s
		end
		return s * 0.12
	end
	-- blade: the motion must be inside the blade plane
	local across = math.abs(dir:Dot(thin.v))
	return s * math.clamp(1 - across * 1.4, 0, 1)
end

-- Speed (studs/s) at which an object of this sharpness goes through flesh.
function HitMath.PierceThreshold(sharpness: number): number
	if sharpness <= 0.02 then
		return math.huge
	end
	return Config.PierceSpeedDull + (Config.PierceSpeedSharp - Config.PierceSpeedDull) * sharpness
end

-- Kinetic energy dissipated when an object (massObj) and a body (massBody) collide with relative speed v.
function HitMath.ImpactEnergy(massObj: number, massBody: number, relSpeed: number): number
	local mu = (massObj * massBody) / math.max(massObj + massBody, 1e-3)
	return 0.5 * mu * relSpeed * relSpeed
end

function HitMath.EnergyDamage(energy: number): number
	return math.max(0, energy - Config.ObjectEnergyMin) / Config.ObjectEnergyPerDamage
end

function HitMath.PierceDamage(speed: number, sharpness: number): number
	local over = speed - HitMath.PierceThreshold(sharpness)
	if over < 0 then
		return 0
	end
	return Config.PierceBase + over * Config.PierceDamage
end

return HitMath
