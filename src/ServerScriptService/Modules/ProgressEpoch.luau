--!nonstrict
-- Global progress reset: rotate a namespace, including profiles belonging to offline players.
-- Old servers keep their old namespace, so a late autosave cannot resurrect erased progress.
local DSS = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Messaging = game:GetService("MessagingService")
local RunService = game:GetService("RunService")
local Epoch = { Ready = false, Value = 0 }
local store, initialized, closing, wiping = nil, false, false, false
local TOPIC = "RagdollProgressEpoch_v1"
local function closeForReset()
	if closing then return end
	closing = true
	workspace:SetAttribute("ProgressResetPending", true)
	for _, p in Players:GetPlayers() do p:Kick("The game owner reset all progress. Rejoin to start a new save.") end
end
function Epoch.Init()
	if initialized then return end
	initialized = true
	store = DSS:GetDataStore("RagdollProgressControl_v1")
	for attempt = 1, 3 do
		local ok, v = pcall(function() return store:GetAsync("epoch") end)
		if ok then Epoch.Value = typeof(v) == "number" and math.max(0, math.floor(v)) or 0; Epoch.Ready = true; break end
		if RunService:IsStudio() then break end
		task.wait(attempt)
	end
	if not Epoch.Ready then
		warn("[Ragdoll] Progress namespace unavailable; persistence disabled for this session to protect saves.")
		return
	end
	pcall(function()
		Messaging:SubscribeAsync(TOPIC, function(message)
			if typeof(message.Data) == "number" and message.Data > Epoch.Value then closeForReset() end
		end)
	end)
	Players.PlayerAdded:Connect(function(p) if closing then p:Kick("Progress reset in progress. Please rejoin.") end end)
	task.spawn(function()
		while not closing do
			task.wait(30)
			local ok, v = pcall(function() return store:GetAsync("epoch") end)
			if ok and typeof(v) == "number" and v > Epoch.Value then closeForReset() end
		end
	end)
end
function Epoch.Key(userId: number, prefix: string?): string
	local key = (prefix or "p_") .. userId
	return Epoch.Value == 0 and key or ("e" .. Epoch.Value .. "_" .. key)
end
function Epoch.Store(name: string)
	if not Epoch.Ready then error("Progress namespace not ready") end
	return DSS:GetDataStore(name)
end
function Epoch.Wipe(by: Player): (boolean, string)
	local Items = require(game.ReplicatedStorage.Shared.Items)
	if not Items.IsGameOwner(by) then return false, "Only the game owner can reset all progress." end
	if wiping or closing or not Epoch.Ready then return false, "Progress storage is unavailable or a reset is already running." end
	wiping = true
	local ok, value = pcall(function()
		return store:UpdateAsync("epoch", function(old) return math.max(tonumber(old) or 0, Epoch.Value) + 1 end)
	end)
	wiping = false
	if not ok then return false, "The reset failed. No progress was reset. Try again later." end
	-- Deliberately leave Epoch.Value unchanged here; in-flight writes belong to the old epoch.
	pcall(function() Messaging:PublishAsync(TOPIC, value) end)
	closeForReset()
	return true, "All player progress reset."
end
return Epoch
