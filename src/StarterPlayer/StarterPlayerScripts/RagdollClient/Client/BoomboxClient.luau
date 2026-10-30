--!nonstrict
-- BoomboxClient (v1.9.1): the setting "Boombox music" turns every boombox off for YOU (the others still hear it).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Settings = require(Shared:WaitForChild("Settings"))

local BoomboxClient = {}

local function apply()
	local on = Settings.Get("boombox") ~= false
	for _, box in CollectionService:GetTagged("Boombox") do
		local root = box:IsA("Model") and box.PrimaryPart
		local snd = root and root:FindFirstChild("Music")
		if snd and snd:IsA("Sound") then
			local want = on and Config.BoomboxMaxVolume or 0
			if snd.Volume ~= want then
				snd.Volume = want
			end
		end
	end
end

function BoomboxClient.Init()
	Settings.Changed:Connect(function(key)
		if key == "boombox" then
			apply()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5) -- (a boombox somebody just switched on is muted within half a second)
			apply()
		end
	end)
end

return BoomboxClient
