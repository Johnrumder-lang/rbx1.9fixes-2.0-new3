--!nonstrict
-- KillService: the Tab leaderboard. "Kills" = players you killed, "NPC Kills" = dummies you killed.
-- Totals are saved (DataStore) and come back next time you play.
-- Whoever hurt a body last (within Config.KillCreditTime) gets the kill: shots, stabs, cuts,
-- punches, grenades, cars, thrown objects, and knocking someone off a tower all count.
-- There is deliberately NO kill feed: nobody is told who died.

local Players = game:GetService("Players")
local SaveGate = require(script.Parent:WaitForChild("SaveGate"))
local ProgressEpoch = require(script.Parent:WaitForChild("ProgressEpoch"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local DamageService = require(script.Parent:WaitForChild("DamageService"))

local KillService = {}

local store: DataStore? = nil
local storeWarned = false
local loaded: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}

local function warnStore(err: any)
	if not storeWarned then
		storeWarned = true
		warn("[Ragdoll] kills are not saved:", err, "(in Studio: Game Settings > Security > Enable Studio Access to API Services)")
	end
end

local function key(player: Player): string
	return ProgressEpoch.Key(player.UserId, "u_")
end

local function stats(player: Player): (IntValue?, IntValue?)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		return nil, nil
	end
	return ls:FindFirstChild("Kills") :: IntValue?, ls:FindFirstChild("NPC Kills") :: IntValue?
end

local function setup(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local kills = Instance.new("IntValue")
	kills.Name = "Kills"
	kills.Parent = ls
	local npc = Instance.new("IntValue")
	npc.Name = "NPC Kills"
	npc.Parent = ls
	ls.Parent = player

	if store and player.UserId > 0 then
		task.spawn(function()
			for attempt = 1, 3 do
				local ok, data = pcall(function()
					return (store :: DataStore):GetAsync(key(player))
				end)
				if ok then
					if typeof(data) == "table" then
						kills.Value += tonumber(data.k) or 0
						npc.Value += tonumber(data.n) or 0
					end
					loaded[player] = true
					return
				end
				warnStore(data)
				task.wait(attempt * 2)
			end
		end)
	end
end

local function save(player: Player)
	if not SaveGate.CanSave() then
		return -- (v2.8) a private server saves nothing
	end
	if not store or not loaded[player] or not dirty[player] then
		return
	end
	local kills, npc = stats(player)
	if not kills or not npc then
		return
	end
	local k, n = kills.Value, npc.Value
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync(key(player), { k = k, n = n })
	end)
	if ok then
		dirty[player] = nil
	else
		warnStore(err)
	end
end

function KillService.Init()
	local ok, result = pcall(function()
		return ProgressEpoch.Store(Config.KillStoreName)
	end)
	if ok then
		store = result
	else
		warnStore(result)
	end

	DamageService.OnKill = function(victim: Model, killer: Player?, state)
		if not killer or not killer.Parent then
			return
		end
		local kills, npc = stats(killer)
		if state.player then
			if kills then
				kills.Value += 1
			end
		elseif victim:GetAttribute("IsDummy") or victim:GetAttribute("IsNPC") then
			if npc then
				npc.Value += 1
			end
		else
			return
		end
		dirty[killer] = true
	end

	Players.PlayerAdded:Connect(setup)
	for _, p in Players:GetPlayers() do
		setup(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		loaded[player] = nil
		dirty[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(75)
			for _, p in Players:GetPlayers() do
				save(p)
			end
		end
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		for _, p in Players:GetPlayers() do
			task.spawn(save, p)
		end
		task.wait(2)
	end)
end

-- (v2.9) the admin "WIPE ALL PROGRESS": this player's kills go to zero (and are saved so)
function KillService.Reset(player: Player)
	local kills, npc = stats(player)
	if kills then
		kills.Value = 0
	end
	if npc then
		npc.Value = 0
	end
	dirty[player] = true
	task.spawn(save, player)
end

return KillService
