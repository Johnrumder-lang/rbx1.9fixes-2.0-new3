--!nonstrict
-- LightingService: the time of day. The owner switches the day / night cycle on and off (and can
-- jump to day / dusk / night) in the menu (M). With the cycle on, a whole day takes
-- Config.DayLength seconds. At night the sky is dark, the ambient light drops and the street lamps
-- come on (every light named "NightLight", every lamp part named "LampGlow" starts to glow).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local LightingService = {}

local cycleOn = false
local isNight: boolean? = nil
local dayAmbient = Lighting.OutdoorAmbient
local dayBrightness = Lighting.Brightness

local NIGHT_AMBIENT = Color3.fromRGB(42, 46, 66)

local lamps: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function setLamp(inst: Instance, on: boolean)
	if inst:IsA("Light") then
		inst.Enabled = on
	elseif inst:IsA("BasePart") then
		inst.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
	end
end

local function nightLights(on: boolean)
	for inst in lamps do
		if inst.Parent then
			setLamp(inst, on)
		else
			lamps[inst] = nil
		end
	end
end

-- 0 = deep night, 1 = full day (smooth around dawn / dusk)
local function daylight(t: number): number
	local function ramp(a: number, b: number, x: number): number
		return math.clamp((x - a) / (b - a), 0, 1)
	end
	if t < 12 then
		return ramp(5.2, 7.4, t)
	end
	return 1 - ramp(17.4, 19.6, t)
end

local function apply()
	local t = Lighting.ClockTime
	local k = daylight(t)
	Lighting.OutdoorAmbient = NIGHT_AMBIENT:Lerp(dayAmbient, k)
	Lighting.Brightness = 0.6 + (dayBrightness - 0.6) * k
	local night = k < 0.35
	if night ~= isNight then
		isNight = night
		nightLights(night)
		workspace:SetAttribute("Night", night)
	end
end

function LightingService.SetCycle(on: boolean)
	cycleOn = on == true
	workspace:SetAttribute("DayNightCycle", cycleOn)
end

function LightingService.SetTime(hour: number)
	if typeof(hour) ~= "number" or hour ~= hour then
		return
	end
	Lighting.ClockTime = hour % 24
	apply()
end

function LightingService.IsCycleOn(): boolean
	return cycleOn
end

-- the lamps of a map (the city when it is loaded): they follow the time of day from now on
function LightingService.Register(root: Instance)
	for _, d in root:GetDescendants() do
		if (d:IsA("Light") and d.Name == "NightLight") or (d:IsA("BasePart") and d.Name == "LampGlow") then
			lamps[d] = true
			setLamp(d, isNight == true)
		end
	end
end

function LightingService.Init()
	dayAmbient = Lighting.OutdoorAmbient
	dayBrightness = Lighting.Brightness
	Lighting.ClockTime = Config.StartTime
	workspace:SetAttribute("DayNightCycle", false)
	LightingService.Register(workspace)
	apply()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		if not cycleOn then
			return
		end
		Lighting.ClockTime = (Lighting.ClockTime + dt * 24 / Config.DayLength) % 24
		acc += dt
		if acc > 0.5 then
			acc = 0
			apply()
		end
	end)
end

return LightingService
