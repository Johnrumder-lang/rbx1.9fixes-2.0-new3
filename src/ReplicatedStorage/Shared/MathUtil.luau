--!nonstrict
local MathUtil = {}

local EPS = 1e-5

-- Smallest rotation that turns unit vector a into unit vector b.
function MathUtil.RotationBetween(a: Vector3, b: Vector3): CFrame
	local dot = math.clamp(a:Dot(b), -1, 1)
	if dot > 1 - EPS then
		return CFrame.identity
	end
	if dot < -1 + EPS then
		local axis = a:Cross(Vector3.xAxis)
		if axis.Magnitude < 1e-3 then
			axis = a:Cross(Vector3.zAxis)
		end
		return CFrame.fromAxisAngle(axis.Unit, math.pi)
	end
	return CFrame.fromAxisAngle(a:Cross(b).Unit, math.acos(dot))
end

-- Frame-rate independent smoothing factor.
function MathUtil.Alpha(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

function MathUtil.Flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function MathUtil.ClampMagnitude(v: Vector3, maxLen: number): Vector3
	local m = v.Magnitude
	if m > maxLen and m > 0 then
		return v * (maxLen / m)
	end
	return v
end

function MathUtil.SafeUnit(v: Vector3, fallback: Vector3?): Vector3
	local m = v.Magnitude
	if m < 1e-4 then
		return fallback or Vector3.zero
	end
	return v / m
end

-- Angle in degrees between two unit vectors.
function MathUtil.AngleDeg(a: Vector3, b: Vector3): number
	return math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
end

function MathUtil.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Approach a value at a fixed rate.
function MathUtil.Approach(current: number, target: number, step: number): number
	if current < target then
		return math.min(current + step, target)
	end
	return math.max(current - step, target)
end

function MathUtil.Yaw(look: Vector3): number
	return math.atan2(-look.X, -look.Z)
end

return MathUtil
