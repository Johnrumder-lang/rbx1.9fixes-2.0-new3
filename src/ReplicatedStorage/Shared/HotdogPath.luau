--!nonstrict
-- HotdogPath (v2.0): where the admin's hotdog is at any moment (server and every client compute the same thing from
-- the same start values, so it flies smoothly on every screen without sending positions).
--   charge : it hovers over the start point and shakes (Config.HotdogCharge seconds)
--   launch : it shoots onto a big circle around the map centre and goes round and round, faster and faster
--            (its speed grows exponentially: Mach 1 ... Mach 30 and more)
--   boom   : at Config.HotdogCharge + Config.HotdogFlight seconds it explodes

local Config = require(script.Parent:WaitForChild("Config"))

local HotdogPath = {}

HotdogPath.MACH = 343 -- studs/s that count as Mach 1 here

export type Info = { start: Vector3, center: Vector3, radius: number, height: number }

local function speedAt(tf: number): number
	-- v0 * e^(k t): from 60 studs/s to past Mach 30 at the end of the flight
	local v0 = 60
	local vEnd = HotdogPath.MACH * 34
	local k = math.log(vEnd / v0) / Config.HotdogFlight
	return v0 * math.exp(k * tf), v0, k
end

-- the hotdog's speed (studs/s) at `t` seconds after it was started
function HotdogPath.Speed(t: number): number
	local tf = t - Config.HotdogCharge
	if tf <= 0 then
		return 0
	end
	return (speedAt(tf))
end

function HotdogPath.Mach(t: number): number
	return HotdogPath.Speed(t) / HotdogPath.MACH
end

-- position and forward direction at `t` seconds after the start
function HotdogPath.At(info: Info, t: number): (Vector3, Vector3)
	local c = info.center
	local r = info.radius
	local h = info.height
	local tf = t - Config.HotdogCharge
	if tf <= 0 then
		-- hovering over the start, shaking more and more
		local k = math.clamp(t / Config.HotdogCharge, 0, 1)
		local shake = Vector3.new(math.sin(t * 47) * 0.3 * k, math.sin(t * 3) * 0.6, math.cos(t * 53) * 0.3 * k)
		return info.start + Vector3.new(0, 4 + 6 * k, 0) + shake, Vector3.new(1, 0, 0)
	end
	local _, v0, k = speedAt(tf)
	-- the angle travelled on the circle so far: integral of v / r
	local theta = (v0 / (r * k)) * (math.exp(k * tf) - 1)
	-- the circle starts at the point closest to the start
	local toStart = Vector3.new(info.start.X - c.X, 0, info.start.Z - c.Z)
	local a0 = math.atan2(toStart.Z, toStart.X)
	local a = a0 + theta
	local onCircle = c + Vector3.new(math.cos(a) * r, h + math.sin(a * 3) * 6, math.sin(a) * r)
	local fwd = Vector3.new(-math.sin(a), 0, math.cos(a))
	-- the first second: it swoops from the start onto the circle
	if tf < 1.2 then
		local s = tf / 1.2
		s = s * s * (3 - 2 * s)
		local from = info.start + Vector3.new(0, 10, 0)
		return from:Lerp(onCircle, s), fwd
	end
	return onCircle, fwd
end

-- how hard the tornado pulls (0..1) at `t`
function HotdogPath.Pull(t: number): number
	local tf = t - Config.HotdogCharge
	if tf <= 0 then
		return 0
	end
	return math.clamp(tf / 6, 0, 1)
end

-- the velocity a body at `pos` is pulled towards at `t` (tornado around the circle)
function HotdogPath.Wind(info: Info, t: number, pos: Vector3): Vector3
	local pull = HotdogPath.Pull(t)
	if pull <= 0 then
		return Vector3.zero
	end
	local c = info.center
	local d = Vector3.new(pos.X - c.X, 0, pos.Z - c.Z)
	local dist = d.Magnitude
	local radial = dist > 0.1 and d / dist or Vector3.xAxis
	local tangent = Vector3.new(-radial.Z, 0, radial.X)
	local tf = t - Config.HotdogCharge
	local spin = math.min(40 + tf * 14, 260)
	local inward = (info.radius * 0.8 - dist) * 0.9
	local lift = (c.Y + info.height * (0.5 + 0.5 * pull) - pos.Y) * 0.8
	return tangent * spin + radial * inward + Vector3.new(0, lift, 0)
end

return HotdogPath
