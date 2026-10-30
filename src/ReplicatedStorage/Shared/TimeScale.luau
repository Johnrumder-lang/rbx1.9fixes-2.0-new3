--!strict
-- TimeScale (v2.8): the Sandevistan's slow motion for everything that moves by script (rockets, flares, bombs, steel
-- balls, bullets in flight, the Crawler, NPC brains, bodies' controllers). Game time = real time x Get().
--   workspace attributes (set by SuperService.SlowMo): SlowScale (0..1), SlowMo (the user's UserId), RealGravity
--   (the gravity before it was lowered: the physics runs with RealGravity x SlowScale^2, so things fall in slow motion).
-- The one who runs it lives in normal time: For(userId) is 1 for them.

local TimeScale = {}

local function rawScale(): number
	local s = workspace:GetAttribute("SlowScale")
	if typeof(s) == "number" and s > 0 and s < 1 then
		return s
	end
	return 1
end

-- A local field never changes the entire world's clock.
function TimeScale.Get(): number
	return workspace:GetAttribute("SlowFieldR") and 1 or rawScale()
end
function TimeScale.Active(): boolean
	return rawScale() < 1
end
-- (v2.9) a LOCAL Sandevistan: the slow motion only catches a body that is within SlowFieldR studs of the one who runs
-- it (SuperService sets SlowFieldR). The user runs at normal speed as always; so does anybody far enough away. With no
-- SlowFieldR set it is the old whole-world slow.
local function isSlowUser(uid: number): boolean
	if workspace:GetAttribute("SlowMo") == uid then
		return true
	end
	local users = workspace:GetAttribute("SlowMoUsers")
	return typeof(users) == "string" and string.find(users, "," .. tostring(uid) .. ",", 1, true) ~= nil
end

function TimeScale.ForField(userId: number?, pos: Vector3?): number
	local base = userId and isSlowUser(userId) and 1 or rawScale()
	if base >= 1 or not pos then
		return pos and base or 1 -- (a user, or no slow running)
	end
	local r = workspace:GetAttribute("SlowFieldR")
	if typeof(r) ~= "number" or r <= 0 then
		return base -- (whole-world slow: no radius)
	end
	local best = math.huge
	for _, p in game:GetService("Players"):GetPlayers() do
		if isSlowUser(p.UserId) then
			local c = p.Character
			local t = c and c:FindFirstChild("Torso")
			if t and t:IsA("BasePart") then
				best = math.min(best, (t.Position - pos).Magnitude)
			end
		end
	end
	return best <= r and base or 1
end

function TimeScale.For(userId: number?): number
	local p = userId and game:GetService("Players"):GetPlayerByUserId(userId)
	local t = p and p.Character and p.Character:FindFirstChild("Torso")
	return TimeScale.ForField(userId, t and t.Position)
end

-- the real gravity (slow motion lowers workspace.Gravity for the physics)
function TimeScale.Gravity(): number
	local g = workspace:GetAttribute("RealGravity")
	if typeof(g) == "number" and TimeScale.Get() < 1 then
		return g
	end
	return workspace.Gravity
end

return TimeScale
