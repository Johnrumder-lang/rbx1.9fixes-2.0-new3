--!nonstrict
-- Global and per-account save generations. A live server never changes a loaded generation:
-- late saves stay in the old namespace, and affected players reconnect before loading a new one.
local DSS = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Messaging = game:GetService("MessagingService")
local RunService = game:GetService("RunService")
local Epoch = { Ready = false, Value = 0, SessionOnly = false }
local store, initialized, closing, wiping = nil, false, false, false
local generations, loading, resetUsers, exploding = {}, {}, {}, {}
local TOPIC = "RagdollProgressEpoch_v1"
local function removePlayer(p)
	if exploding[p] then return end
	exploding[p] = true
	local ch = p.Character
	local head = ch and ch:FindFirstChild("Head")
	if ch and head then
		local ok, err = pcall(function()
			local Gore = require(script.Parent.GoreService)
			local Damage = require(script.Parent.DamageService)
			ch:SetAttribute("NoRegrowth", true); ch:SetAttribute("ForceKill", true)
			Gore.Gibs(head.Position, 9, 28)
			Gore.Burst(head.Position, Vector3.yAxis, 32, 22)
			Gore.Sound("gore", head.Position, 1)
			head.Transparency = 1
			for _, face in head:GetChildren() do if face:IsA("Decal") then face.Transparency = 1 end end
			Damage.Kill(ch, "Progress reset by an admin", true)
		end)
		if not ok then warn("[Progress reset effect]", err) end
	end
	task.delay(2, function() if p.Parent then p:Kick("Your progress was reset. Rejoin a fresh server to start a new save.") end end)
end
local function closeForReset(userId)
	if userId then
		resetUsers[userId] = true
		local p = Players:GetPlayerByUserId(userId)
		if p then removePlayer(p) end
	else
		if closing then return end
		closing = true
		workspace:SetAttribute("ProgressResetPending", true)
		for _, p in Players:GetPlayers() do removePlayer(p) end
	end
end
local function receive(data)
	if typeof(data) == "number" and data > Epoch.Value then closeForReset()
	elseif typeof(data) == "table" and typeof(data.userId) == "number" and typeof(data.generation) == "number" then
		local loaded = generations[data.userId]
		if loaded ~= nil and data.generation > loaded then closeForReset(data.userId) end
	end
end
function Epoch.Init()
	if initialized then return end
	initialized = true
	-- GetDataStore itself throws for unpublished places; it must be inside the protected call.
	if game.GameId == 0 and RunService:IsStudio() then
		Epoch.SessionOnly, Epoch.Ready = true, true
		return
	end
	local acquired, result = pcall(function() return DSS:GetDataStore("RagdollProgressControl_v1") end)
	if acquired then store = result end
	if store then
		for attempt = 1, 3 do
			local ok, v = pcall(function() return store:GetAsync("epoch") end)
			if ok then Epoch.Value = typeof(v) == "number" and math.max(0, math.floor(v)) or 0; Epoch.Ready = true; break end
			if RunService:IsStudio() then break end
			task.wait(attempt)
		end
	end
	if not Epoch.Ready then
		if RunService:IsStudio() then Epoch.SessionOnly, Epoch.Ready = true, true; return end
		warn("[Ragdoll] Progress storage unavailable; persistence is disabled for this session.")
		return
	end
	pcall(function() Messaging:SubscribeAsync(TOPIC, function(m) receive(m.Data) end) end)
	Players.PlayerAdded:Connect(function(p)
		if closing or resetUsers[p.UserId] then p:Kick("Progress reset in progress. Join a fresh server.") end
	end)
	task.spawn(function()
		while not closing do
			task.wait(30)
			local ok, v = pcall(function() return store:GetAsync("epoch") end)
			if ok then receive(v) end
			for _, p in Players:GetPlayers() do
				if generations[p.UserId] ~= nil then
					local got, n = pcall(function() return store:GetAsync("u_" .. p.UserId) end)
					if got then receive({ userId = p.UserId, generation = tonumber(n) or 0 }) end
				end
			end
		end
	end)
end
function Epoch.Key(userId: number, prefix: string?): string
	if not Epoch.Ready then error("Progress namespace unavailable") end
	if generations[userId] == nil then
		while loading[userId] do task.wait() end
		if generations[userId] == nil then
			loading[userId] = true
			local ok, v = pcall(function() return not Epoch.SessionOnly and store:GetAsync("u_" .. userId) or 0 end)
			loading[userId] = nil
			if not ok then error("Player progress namespace unavailable") end
			generations[userId] = math.max(0, math.floor(tonumber(v) or 0))
		end
	end
	local key = (prefix or "p_") .. userId
	if Epoch.Value > 0 then key = "e" .. Epoch.Value .. "_" .. key end
	if generations[userId] > 0 then key = "r" .. generations[userId] .. "_" .. key end
	return key
end
function Epoch.Store(name: string)
	if not Epoch.Ready or Epoch.SessionOnly then error("Session-only storage") end
	return DSS:GetDataStore(name)
end
function Epoch.Wipe(by: Player, userId: number?): (boolean, string)
	local Items = require(game.ReplicatedStorage.Shared.Items)
	if userId == nil then
		if not Items.IsGameOwner(by) then return false, "Only the game owner can reset all progress." end
	else
		if not Items.IsOwner(by) or typeof(userId) ~= "number" or userId % 1 ~= 0 or userId <= 0 then return false, "Invalid player." end
		local target = Players:GetPlayerByUserId(userId)
		if target and Items.IsGameOwner(target) and not Items.IsGameOwner(by) then return false, "You cannot reset the game owner." end
	end
	if wiping or closing or not Epoch.Ready then return false, "Progress storage unavailable or reset already running." end
	if Epoch.SessionOnly then closeForReset(userId); return true, "Studio session reset; no persistent saves changed." end
	wiping = true
	local ok, value = pcall(function()
		return store:UpdateAsync(userId and ("u_" .. userId) or "epoch", function(old)
			return math.max(tonumber(old) or 0, userId and (generations[userId] or 0) or Epoch.Value) + 1
		end)
	end)
	wiping = false
	if not ok then return false, "Reset failed; no new save generation was created." end
	local data = userId and { userId = userId, generation = value } or value
	pcall(function() Messaging:PublishAsync(TOPIC, data) end)
	closeForReset(userId)
	return true, userId and "Player progress reset globally." or "All player progress reset globally."
end
return Epoch
