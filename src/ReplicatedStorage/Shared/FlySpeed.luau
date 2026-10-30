--!strict
-- FlySpeed: the admin's flight speed as typed into the box (N while flying).
--   Parse("45") -> 45, Parse("2,5") -> 2.5, Parse("1e6") -> 1000000, Parse("inf") -> math.huge
--   Text(v) -> "45" / "1200" / "2.5" / "INF" (everything from Config.FlyMaxSpeed on is INF)

local Config = require(script.Parent:WaitForChild("Config"))

local FlySpeed = {}

function FlySpeed.Parse(text: string?): number?
	local t = string.gsub(string.gsub(string.lower(text or ""), "[%s_]", ""), ",", ".")
	if string.find(t, "inf", 1, true) or string.find(t, "unendlich", 1, true) or string.find(t, "max", 1, true) then
		return math.huge
	end
	local s = string.match(t, "%d*%.?%d+e?%d*")
	local v = s and tonumber(s)
	if not v or v ~= v or v <= 0 then
		return nil
	end
	return v
end

function FlySpeed.Text(v: number): string
	if v >= Config.FlyMaxSpeed then
		return "INF"
	end
	if v >= 100 or math.abs(v - math.floor(v + 0.5)) < 0.05 then
		return string.format("%d", math.floor(v + 0.5))
	end
	return string.format("%.1f", v)
end

return FlySpeed
