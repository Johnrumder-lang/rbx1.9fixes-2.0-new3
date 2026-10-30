--!nonstrict
-- ExperimentalLighting (v1.9): a switch in the settings (M). On, the lighting looks the way the owner set
-- it up in Studio (values copied from his screenshots: soft grey ambient, warm top shift, no
-- environment light, retro tonemapper, desaturated, dim exposure). Off (the default) it is exactly what the
-- game normally uses. It is local to the player. The day / night cycle still works: brightness and the
-- outdoor light fade to the night values like they do normally.
-- All values are in V below, so they are easy to change.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Settings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Settings"))

local ExperimentalLighting = {}

local V = {
	Ambient = Color3.fromRGB(61, 63, 72),
	Brightness = 1.61,
	ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
	ColorShift_Top = Color3.fromRGB(255, 246, 232),
	EnvironmentDiffuseScale = 0,
	EnvironmentSpecularScale = 0,
	GlobalShadows = true,
	OutdoorAmbient = Color3.fromRGB(128, 131, 142),
	PrioritizeLightingQuality = true,
	ShadowSoftness = 0,
	GeographicLatitude = 28,
	ExposureCompensation = -12.5,
	FogColor = Color3.fromRGB(191, 191, 191),
	FogStart = 0,
	FogEnd = 100000,
}
-- the colour correction in the screenshot (tint [200000, 200000, 200000] in the 0-255 scale of the Studio panel)
local CC = { Brightness = 0, Contrast = 0, Saturation = -0.5, TintColor = Color3.new(200000 / 255, 200000 / 255, 200000 / 255) }

local NIGHT_AMBIENT = Color3.fromRGB(42, 46, 66)

local on = false
local saved: { [string]: any }? = nil
local savedCC: { [string]: any }? = nil
local savedTone: any = nil

local function daylight(t: number): number
	local function ramp(a: number, b: number, x: number): number
		return math.clamp((x - a) / (b - a), 0, 1)
	end
	if t < 12 then
		return ramp(5.2, 7.4, t)
	end
	return 1 - ramp(17.4, 19.6, t)
end

local function setProp(name: string, value: any)
	pcall(function()
		(Lighting :: any)[name] = value
	end)
end

local function colorCorrection(): ColorCorrectionEffect?
	return Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
end

local function colorGrading(): any
	local ok, inst = pcall(function()
		return Lighting:FindFirstChildOfClass("ColorGradingEffect")
	end)
	return ok and inst or nil
end

local function applyStatic()
	for name, value in V do
		if name ~= "Brightness" and name ~= "OutdoorAmbient" then
			setProp(name, value)
		end
	end
	pcall(function()
		Lighting.LightingStyle = Enum.LightingStyle.Realistic
	end)
	local cc = colorCorrection()
	if cc then
		for k, v in CC do
			pcall(function()
				(cc :: any)[k] = v
			end)
		end
	end
	local cg = colorGrading()
	if cg then
		pcall(function()
			cg.TonemapperPreset = Enum.TonemapperPreset.Retro
		end)
	end
end

local function enable()
	if on then
		return
	end
	on = true
	saved = {}
	for name in V do
		pcall(function()
			(saved :: any)[name] = (Lighting :: any)[name]
		end)
	end
	pcall(function()
		(saved :: any).LightingStyle = Lighting.LightingStyle
	end)
	local cc = colorCorrection()
	if cc then
		savedCC = { Brightness = cc.Brightness, Contrast = cc.Contrast, Saturation = cc.Saturation, TintColor = cc.TintColor }
	end
	local cg = colorGrading()
	if cg then
		pcall(function()
			savedTone = cg.TonemapperPreset
		end)
	end
	applyStatic()
end

local function disable()
	if not on then
		return
	end
	on = false
	if saved then
		for name, value in saved do
			setProp(name, value)
		end
	end
	local cc = colorCorrection()
	if cc and savedCC then
		for k, v in savedCC do
			pcall(function()
				(cc :: any)[k] = v
			end)
		end
	end
	local cg = colorGrading()
	if cg and savedTone ~= nil then
		pcall(function()
			cg.TonemapperPreset = savedTone
		end)
	end
	saved, savedCC, savedTone = nil, nil, nil
end

function ExperimentalLighting.Init()
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		if not on then
			return
		end
		-- (the server's cycle changes these two every half second: we put ours back each frame, with the
		-- night fade, so the cycle still shows)
		local k = daylight(Lighting.ClockTime)
		Lighting.Brightness = 0.6 + (V.Brightness - 0.6) * k
		Lighting.OutdoorAmbient = NIGHT_AMBIENT:Lerp(V.OutdoorAmbient, k)
		acc += dt
		if acc > 1 then
			acc = 0
			applyStatic() -- (the "Bloom / sun rays / colour" setting may have touched the colour correction)
		end
	end)
	Settings.Changed:Connect(function(key, value)
		if key == "experimental" then
			if value == true then
				enable()
			else
				disable()
			end
		end
	end)
	if Settings.Get("experimental") == true then
		enable()
	end
end

return ExperimentalLighting
