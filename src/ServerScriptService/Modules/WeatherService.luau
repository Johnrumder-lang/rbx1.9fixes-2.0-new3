--!nonstrict
-- WeatherService (v1.9): clear -> rain -> storm -> rain -> clear ... (or fixed by the owner in the admin menu).
-- (v2.8) also SNOW and FOG: clear -> rain / fog / snow -> ...
-- Clients read: workspace "Weather" (clear / rain / storm / snow / fog), "WeatherK" (0..1: the rain - 0.5 rain, 1 storm -
-- how strong it is right now, it fades in and out), (v2.8) "SnowK" and "FogK" (0..1, they fade too),
-- "LightningId" + "LightningPos" (every strike, so everybody sees and hears the same one).

local Players = game:GetService("Players")

local FireService = require(script.Parent:WaitForChild("FireService"))

local WeatherService = {}

local TARGET = { clear = 0, rain = 0.5, storm = 1, snow = 0, fog = 0 }
local SNOW = { snow = 1 }
local FOG = { rain = 0.1, storm = 0.25, snow = 0.3, fog = 1 }
local rng = Random.new()

local mode = "auto" -- auto / clear / rain / storm
local current = "clear"
local phaseEnds = 0
local k = 0
local snowK = 0
local fogK = 0
local nextStrike = 0
local strikeId = 0

local function pickNext()
	-- the automatic weather: mostly dry, a rainy spell now and then, sometimes a storm in it
	if current == "clear" then
		local r = rng:NextNumber()
		current = r < 0.58 and "rain" or (r < 0.8 and "fog" or "snow")
		phaseEnds = os.clock() + rng:NextNumber(120, 300)
	elseif current == "fog" or current == "snow" then
		current = "clear"
		phaseEnds = os.clock() + rng:NextNumber(240, 600)
	elseif current == "rain" then
		if rng:NextNumber() < 0.45 then
			current = "storm"
			phaseEnds = os.clock() + rng:NextNumber(60, 170)
		else
			current = "clear"
			phaseEnds = os.clock() + rng:NextNumber(240, 600)
		end
	else
		current = "rain"
		phaseEnds = os.clock() + rng:NextNumber(60, 150)
	end
end

local function strike()
	local list = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local t = c and c:FindFirstChild("Torso")
		if t and t:IsA("BasePart") then
			table.insert(list, t.Position)
		end
	end
	local origin = #list > 0 and list[rng:NextInteger(1, #list)] or Vector3.zero
	local a = rng:NextNumber(0, math.pi * 2)
	local d = rng:NextNumber(40, 260)
	local flat = origin + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local fx = workspace:FindFirstChild("FX")
	rp.FilterDescendantsInstances = fx and { fx } or {}
	local hit = workspace:Raycast(flat + Vector3.new(0, 300, 0), Vector3.new(0, -600, 0), rp)
	local pos = hit and hit.Position or flat
	strikeId += 1
	workspace:SetAttribute("LightningPos", pos)
	workspace:SetAttribute("LightningId", strikeId)
	-- now and then a bolt sets something on fire (a small fire that burns out soon)
	if hit and rng:NextNumber() < 0.25 then
		FireService.Ignite(pos, 2.5, 5, nil)
	end
end

function WeatherService.Set(newMode: string)
	if newMode ~= "auto" and not TARGET[newMode] then
		return
	end
	mode = newMode
	if mode ~= "auto" then
		current = mode
	else
		phaseEnds = os.clock() + rng:NextNumber(30, 90)
	end
	workspace:SetAttribute("WeatherMode", mode)
end

function WeatherService.Init()
	workspace:SetAttribute("Weather", current)
	workspace:SetAttribute("WeatherMode", mode)
	workspace:SetAttribute("WeatherK", 0)
	phaseEnds = os.clock() + rng:NextNumber(60, 240) -- the first rain comes a little after the start
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.25)
			local now = os.clock()
			local dt = now - last
			last = now
			if mode == "auto" and now >= phaseEnds then
				pickNext()
			end
			local target = TARGET[current] or 0
			if k < target then
				k = math.min(target, k + dt / 10)
			elseif k > target then
				k = math.max(target, k - dt / 8) -- (v1.9.1: it clears up faster)
			end
			-- (v2.8) snow and fog come and go a little slower
			local st, ft = SNOW[current] or 0, FOG[current] or 0
			snowK = snowK < st and math.min(st, snowK + dt / 14) or math.max(st, snowK - dt / 10)
			fogK = fogK < ft and math.min(ft, fogK + dt / 16) or math.max(ft, fogK - dt / 10)
			workspace:SetAttribute("Weather", current)
			workspace:SetAttribute("WeatherK", math.floor(k * 100 + 0.5) / 100)
			workspace:SetAttribute("SnowK", math.floor(snowK * 100 + 0.5) / 100)
			workspace:SetAttribute("FogK", math.floor(fogK * 100 + 0.5) / 100)
			if current == "storm" and k > 0.8 and now >= nextStrike then
				strike()
				nextStrike = now + rng:NextNumber(5, 16)
			end
		end
	end)
end

return WeatherService
