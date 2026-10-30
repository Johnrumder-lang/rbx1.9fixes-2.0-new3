--!strict
-- Poses (v2.8.2): where the parts of a body go when the world puts it in a pose - lying on a bed (the ripperdoc's
-- operating table, the hospital's recovery beds) or sitting in the replay chair. `cf` is where the Torso goes; the
-- head and the limbs are laid out round it. The server holds the body there (anchored, so everybody sees it) and the
-- body's own machine does the same (CharacterController).

local Poses = {}

Poses.OFF = {
	lie = {
		Head = CFrame.new(0, 1.5, 0),
		["Left Arm"] = CFrame.new(-1.55, 0, 0) * CFrame.Angles(0, 0, math.rad(-6)),
		["Right Arm"] = CFrame.new(1.55, 0, 0) * CFrame.Angles(0, 0, math.rad(6)),
		["Left Leg"] = CFrame.new(-0.52, -2, 0),
		["Right Leg"] = CFrame.new(0.52, -2, 0),
	},
	sit = {
		Head = CFrame.new(0, 1.5, 0) * CFrame.Angles(math.rad(-6), 0, 0),
		["Left Arm"] = CFrame.new(-1.5, -0.1, -0.35) * CFrame.Angles(math.rad(25), 0, 0),
		["Right Arm"] = CFrame.new(1.5, -0.1, -0.35) * CFrame.Angles(math.rad(25), 0, 0),
		["Left Leg"] = CFrame.new(-0.5, -1, -1) * CFrame.Angles(math.rad(90), 0, 0),
		["Right Leg"] = CFrame.new(0.5, -1, -1) * CFrame.Angles(math.rad(90), 0, 0),
	},
}

Poses.PARTS = { "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "HumanoidRootPart" }

-- where one part of the body goes (nil: that part is not laid out)
function Poses.Where(kind: string, cf: CFrame, name: string, scale: number?): CFrame?
	local S = scale or 1
	if name == "Torso" or name == "HumanoidRootPart" then
		return cf
	end
	local offs = (Poses.OFF :: any)[kind] or Poses.OFF.lie
	local off = offs[name]
	if not off then
		return nil
	end
	return cf * (CFrame.new(off.Position * S) * off.Rotation)
end

return Poses
