--!strict
-- ReplayCodec (v2.8.2): packs the frames of a kill replay into a buffer (small enough to cross the network a second at a
-- time) and unpacks them again. Used by ReplayService (server) and ReplayClient.
--   one frame:  its time (f32, seconds from the start of the record), a flag + the camera, then for every slot (every
--               tracked part of every actor, in a fixed order) a flag and, when the part was there, its CFrame
--   a CFrame:   20 bytes - the position as 3 f32, the rotation as a unit quaternion in 4 i16

local ReplayCodec = {}

export type Frame = { dt: number, cam: CFrame?, cfs: { [number]: CFrame } }

local Q = 32767
local CF_BYTES = 20

local function finite(n: number): boolean
	return n == n and n > -1e7 and n < 1e7
end

-- the rotation of a CFrame as a unit quaternion (x, y, z, w)
function ReplayCodec.Quat(cf: CFrame): (number, number, number, number)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local x, y, z, w
	local tr = r00 + r11 + r22
	if tr > 0 then
		local s = math.sqrt(tr + 1) * 2
		w = 0.25 * s
		x = (r21 - r12) / s
		y = (r02 - r20) / s
		z = (r10 - r01) / s
	elseif r00 > r11 and r00 > r22 then
		local s = math.sqrt(1 + r00 - r11 - r22) * 2
		w = (r21 - r12) / s
		x = 0.25 * s
		y = (r01 + r10) / s
		z = (r02 + r20) / s
	elseif r11 > r22 then
		local s = math.sqrt(1 + r11 - r00 - r22) * 2
		w = (r02 - r20) / s
		x = (r01 + r10) / s
		y = 0.25 * s
		z = (r12 + r21) / s
	else
		local s = math.sqrt(1 + r22 - r00 - r11) * 2
		w = (r10 - r01) / s
		x = (r02 + r20) / s
		y = (r12 + r21) / s
		z = 0.25 * s
	end
	local n = math.sqrt(x * x + y * y + z * z + w * w)
	if not finite(n) or n < 1e-6 then
		return 0, 0, 0, 1
	end
	return x / n, y / n, z / n, w / n
end

-- a CFrame from a position and a quaternion (normalised here, so a rounded one is still a clean rotation)
function ReplayCodec.FromQuat(px: number, py: number, pz: number, x: number, y: number, z: number, w: number): CFrame
	local n = math.sqrt(x * x + y * y + z * z + w * w)
	if n < 1e-6 or not finite(n) then
		return CFrame.new(px, py, pz)
	end
	x, y, z, w = x / n, y / n, z / n, w / n
	local xx, yy, zz = x * x, y * y, z * z
	local xy, xz, yz = x * y, x * z, y * z
	local wx, wy, wz = w * x, w * y, w * z
	return CFrame.new(
		px, py, pz,
		1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy),
		2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx),
		2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy)
	)
end

local function okCF(cf: any): boolean
	if typeof(cf) ~= "CFrame" then
		return false
	end
	local p = cf.Position
	return finite(p.X) and finite(p.Y) and finite(p.Z)
end
ReplayCodec.OkCF = okCF

local function sizeOf(frames: { Frame }, slots: number): number
	local n = 0
	for _, f in frames do
		n += 4 + 1 + slots
		if okCF(f.cam) then
			n += CF_BYTES
		end
		for s = 1, slots do
			if okCF(f.cfs[s]) then
				n += CF_BYTES
			end
		end
	end
	return n
end

local function writeCF(b: buffer, o: number, cf: CFrame): number
	local p = cf.Position
	buffer.writef32(b, o, p.X)
	buffer.writef32(b, o + 4, p.Y)
	buffer.writef32(b, o + 8, p.Z)
	local x, y, z, w = ReplayCodec.Quat(cf)
	buffer.writei16(b, o + 12, math.round(x * Q))
	buffer.writei16(b, o + 14, math.round(y * Q))
	buffer.writei16(b, o + 16, math.round(z * Q))
	buffer.writei16(b, o + 18, math.round(w * Q))
	return o + CF_BYTES
end

local function readCF(b: buffer, o: number): (CFrame, number)
	local px, py, pz = buffer.readf32(b, o), buffer.readf32(b, o + 4), buffer.readf32(b, o + 8)
	local x, y, z, w = buffer.readi16(b, o + 12) / Q, buffer.readi16(b, o + 14) / Q, buffer.readi16(b, o + 16) / Q, buffer.readi16(b, o + 18) / Q
	return ReplayCodec.FromQuat(px, py, pz, x, y, z, w), o + CF_BYTES
end

-- frames -> one buffer (`slots`: how many tracked parts each frame has)
function ReplayCodec.Encode(frames: { Frame }, slots: number): buffer
	local b = buffer.create(math.max(1, sizeOf(frames, slots)))
	local o = 0
	for _, f in frames do
		buffer.writef32(b, o, f.dt)
		o += 4
		if okCF(f.cam) then
			buffer.writeu8(b, o, 1)
			o = writeCF(b, o + 1, f.cam :: CFrame)
		else
			buffer.writeu8(b, o, 0)
			o += 1
		end
		for s = 1, slots do
			local cf = f.cfs[s]
			if okCF(cf) then
				buffer.writeu8(b, o, 1)
				o = writeCF(b, o + 1, cf)
			else
				buffer.writeu8(b, o, 0)
				o += 1
			end
		end
	end
	return b
end

-- one buffer -> frames
function ReplayCodec.Decode(b: buffer, slots: number): { Frame }
	local out: { Frame } = {}
	local o = 0
	local len = buffer.len(b)
	while o + 5 + slots <= len do
		local f: Frame = { dt = buffer.readf32(b, o), cam = nil, cfs = {} }
		o += 4
		if buffer.readu8(b, o) == 1 then
			f.cam, o = readCF(b, o + 1)
		else
			o += 1
		end
		for s = 1, slots do
			if o >= len then
				break
			end
			if buffer.readu8(b, o) == 1 then
				f.cfs[s], o = readCF(b, o + 1)
			else
				o += 1
			end
		end
		table.insert(out, f)
	end
	return out
end

return ReplayCodec
