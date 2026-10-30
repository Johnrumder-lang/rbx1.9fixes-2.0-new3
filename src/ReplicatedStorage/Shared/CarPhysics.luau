--!nonstrict
-- CarPhysics: raycast suspension + tires for the cars. Run by whoever simulates the car:
-- the driver's client while someone drives it, the server while it is parked (handbrake on).
--   every wheel casts a ray down; a spring-damper pushes the chassis up at that wheel, the tire
--   grips sideways (up to the friction limit), the rear wheels drive, all wheels brake.
-- The forces go into one VectorForce per wheel ("Force_FL" at attachment "Mount_FL", ...).

local Config = require(script.Parent:WaitForChild("Config"))

local CarPhysics = {}

CarPhysics.Wheels = {
	FL = { front = true },
	FR = { front = true },
	RL = { front = false },
	RR = { front = false },
}

export type Input = { throttle: number, steer: number, brake: boolean, coast: boolean? }

function CarPhysics.NewState()
	return { steer = 0, spin = 0 }
end

-- one step; returns the forward speed. `visual` = also animate the wheel welds.
function CarPhysics.Step(car: Model, dt: number, input: Input, st, params: RaycastParams, visual: boolean): number
	local chassis = car.PrimaryPart
	if not chassis then
		return 0
	end
	local cf = chassis.CFrame
	local up = cf.UpVector
	local M = chassis.AssemblyMass
	local g = workspace.Gravity
	local vel = chassis.AssemblyLinearVelocity
	local fwdSpeed = vel:Dot(cf.LookVector)
	local throttle, brake = input.throttle, input.brake
	-- (v2.8) a van / a tank: its own top speed
	local ms = car:GetAttribute("MaxSpeed")
	local maxSpeed = typeof(ms) == "number" and ms or Config.CarMaxSpeed

	local maxSteer = math.rad(Config.CarMaxSteer) * (1 - 0.55 * math.clamp(math.abs(fwdSpeed) / maxSpeed, 0, 1))
	st.steer += (-input.steer * maxSteer - st.steer) * math.min(1, dt * 8)
	st.spin += fwdSpeed / Config.CarWheelRadius * dt

	local rest = Config.CarSuspensionRest
	local r = Config.CarWheelRadius
	local k = M * g / 4 / Config.CarSag
	local damp = 2 * Config.CarDamping * math.sqrt(k * M / 4)
	local mu = Config.CarGrip
	for name, info in CarPhysics.Wheels do
		local att = chassis:FindFirstChild("Mount_" .. name)
		local vf = chassis:FindFirstChild("Force_" .. name)
		if not att or not vf or not att:IsA("Attachment") or not vf:IsA("VectorForce") then
			continue
		end
		local mount = att.WorldPosition
		-- a popped tire: smaller, grips worse, drags
		local wheelPart = car:FindFirstChild("Wheel_" .. name)
		local popped = wheelPart ~= nil and wheelPart:GetAttribute("Popped") == true
		local rw = popped and r - Config.CarPoppedDrop or r
		local wlen = rest + rw
		local hit = workspace:Raycast(mount, -up * wlen, params)
		local drop = rest
		if hit then
			local dist = (mount - hit.Position):Dot(up)
			local comp = math.clamp(wlen - dist, 0, rest + 0.4)
			drop = math.clamp(dist - rw, 0, rest)
			local pv = chassis:GetVelocityAtPosition(mount)
			local Fs = math.max(0, k * comp - damp * pv:Dot(up))
			local n = hit.Normal
			local fwd = cf.LookVector
			if info.front then
				fwd = CFrame.fromAxisAngle(up, st.steer):VectorToWorldSpace(fwd)
			end
			fwd = fwd - n * fwd:Dot(n)
			fwd = fwd.Magnitude > 0.01 and fwd.Unit or cf.LookVector
			local right = fwd:Cross(n)
			right = right.Magnitude > 0.01 and right.Unit or cf.RightVector
			local vF = pv:Dot(fwd)
			local vR = pv:Dot(right)
			local load = math.max(Fs, M * g * 0.08)
			local wmu = popped and mu * Config.CarPoppedGrip or mu
			-- tires grip sideways (up to the friction limit: hard turns at speed slide)
			local lat = math.clamp(-vR * (M / 4) / 0.12, -wmu * load, wmu * load)
			-- engine (rear wheels), brakes, rolling resistance
			local lon = 0
			if not info.front then
				if throttle > 0 and fwdSpeed < maxSpeed then
					lon += throttle * M * Config.CarAccel / 2
				elseif throttle < 0 then
					if fwdSpeed > 2 then
						lon += throttle * M * Config.CarBrake / 2
					elseif fwdSpeed > -Config.CarReverseSpeed then
						lon += throttle * M * Config.CarAccel * 0.6 / 2
					end
				end
			end
			if brake then
				lon += -math.sign(vF) * math.min(math.abs(vF) * (M / 4) / 0.1, M * Config.CarBrake / 4)
			elseif throttle == 0 then
				-- (v1.9.1) a car nobody drives only slows down through the air (a tiny drag), not like it is braking
				lon += -vF * (M / 4) * (input.coast and 0.03 or 0.3)
			end
			if popped then
				lon += -vF * (M / 4) * 0.5 -- the flat drags (the car pulls to that side)
			end
			lon = math.clamp(lon, -wmu * load * 1.2, wmu * load * 1.2)
			vf.Force = n * Fs + right * lat + fwd * lon
		else
			vf.Force = Vector3.zero
		end
		if visual then
			local wheel = car:FindFirstChild("Wheel_" .. name)
			local weld = wheel and wheel:FindFirstChild("WheelWeld")
			if weld and weld:IsA("Weld") then
				local base = CFrame.new(att.Position - Vector3.new(0, drop, 0))
				weld.C0 = base * CFrame.Angles(0, info.front and st.steer or 0, 0) * CFrame.Angles(-st.spin, 0, 0)
			end
		end
	end
	return fwdSpeed
end

return CarPhysics
