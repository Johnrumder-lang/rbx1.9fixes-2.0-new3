--!nonstrict
-- Ballistics (v2.0): what server and clients agree on about a bullet's path.
--   * penetration: how far a bullet of a gun can still go through bodies (Config.Penetration)
--   * ExitDistance: how much body part lies on the bullet's way (a ray through the part's box)
--   * tracer speed of a gun (Config.TracerSpeed)

local Config = require(script.Parent:WaitForChild("Config"))

local Ballistics = {}

function Ballistics.Pen(kind: string?): number
	return (kind and Config.Penetration[kind]) or 0
end

function Ballistics.TracerSpeed(kind: string?): number
	return (kind and Config.TracerSpeed[kind]) or Config.TracerSpeed.default
end

-- distance from `entry` (on or in the part) along `dir` until the ray leaves the part's box
function Ballistics.ExitDistance(part: BasePart, entry: Vector3, dir: Vector3): number
	local cf = part.CFrame
	local o = cf:PointToObjectSpace(entry)
	local d = cf:VectorToObjectSpace(dir)
	local h = part.Size * 0.5
	local best = math.huge
	local function axis(oc: number, dc: number, hc: number)
		if math.abs(dc) > 1e-6 then
			local t = ((dc > 0 and hc or -hc) - oc) / dc
			if t < best then
				best = t
			end
		end
	end
	axis(o.X, d.X, h.X)
	axis(o.Y, d.Y, h.Y)
	axis(o.Z, d.Z, h.Z)
	if best == math.huge then
		best = part.Size.Magnitude
	end
	return math.clamp(best, 0.05, part.Size.Magnitude)
end

return Ballistics
