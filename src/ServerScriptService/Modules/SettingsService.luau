--!nonstrict
-- SettingsService: keeps every player's settings (menu, M: blood, gore, effects, camera shake,
-- volume, ...) between visits. The client applies them itself; the server only stores them
-- (DataStore; without API access in Studio they simply are not saved).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Settings = require(Shared:WaitForChild("Settings"))

local SettingsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Settings") :: RemoteEvent

local SettingsService = {}

local store: DataStore? = nil
local lastSave: { [Player]: number } = {}
local pending: { [Player]: { [string]: any } } = {}

local function key(player: Player): string
	return "s_" .. tostring(player.UserId)
end

local function save(player: Player)
	local data = pending[player]
	if not data or not store or player.UserId <= 0 then
		return
	end
	pending[player] = nil
	lastSave[player] = os.clock()
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync(key(player), data)
	end)
	if not ok then
		warn("[Ragdoll] settings not saved:", err)
	end
end

local function load(player: Player)
	if not store or player.UserId <= 0 then
		return
	end
	local ok, data = pcall(function()
		return (store :: DataStore):GetAsync(key(player))
	end)
	if ok and typeof(data) == "table" and player.Parent then
		SettingsRemote:FireClient(player, "load", Settings.Clean(data))
	end
end

function SettingsService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.SettingsStoreName)
	end)
	if ok then
		store = result
	end
	SettingsRemote.OnServerEvent:Connect(function(player, action, data)
		if action == "save" and typeof(data) == "table" then
			pending[player] = Settings.Clean(data)
			-- (at most every 8 s; the rest is saved when the player leaves)
			if os.clock() - (lastSave[player] or 0) > 8 then
				task.spawn(save, player)
			end
		elseif action == "load" then
			task.spawn(load, player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		lastSave[player] = nil
		pending[player] = nil
	end)
	game:BindToClose(function()
		for _, p in Players:GetPlayers() do
			save(p)
		end
	end)
end

return SettingsService
