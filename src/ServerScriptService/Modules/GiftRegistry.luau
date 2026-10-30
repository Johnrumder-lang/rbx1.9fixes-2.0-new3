--!nonstrict
-- Persistent gift records are updated by field, so an offline revoke cannot be undone by a stale player snapshot.
local Players = game:GetService("Players")
local DSS = game:GetService("DataStoreService")
local Messaging = game:GetService("MessagingService")
local RunService = game:GetService("RunService")
local Shared = game.ReplicatedStorage.Shared
local Items, Titles, Config = require(Shared.Items), require(Shared.Titles), require(Shared.Config)
local SaveGate = require(script.Parent.SaveGate)
local Registry = {}
local store, apply, remote
local cache, versions, pages, busy, last = {}, {}, {}, {}, {}
local TOPIC = "RagdollGiftChanges_v2"
local function key(id) return "g_" .. id end
local function normalize(raw)
	local d = typeof(raw) == "table" and table.clone(raw) or {}
	d.powers = typeof(d.powers) == "table" and table.clone(d.powers) or {}
	d.titles = typeof(d.titles) == "table" and table.clone(d.titles) or {}
	d.granters = typeof(d.granters) == "table" and table.clone(d.granters) or {}
	d.admin = d.admin == true; d.rev = tonumber(d.rev) or 0
	return d
end
local function valid(k)
	if k == "admin" then return true end
	local kind, id = k:match("^(%a+):([%w_]+)$")
	return kind == "power" and table.find(Items.POWERS, id) ~= nil or kind == "title" and Titles.ById[id] and Titles.ById[id].source == "gift"
end
local function keys(d)
	local all = {}
	for _, p in d.powers do if table.find(Items.POWERS, p) then table.insert(all, "power:" .. p) end end
	for _, p in d.titles do if Titles.ById[p] and Titles.ById[p].source == "gift" then table.insert(all, "title:" .. p) end end
	if d.admin then table.insert(all, "admin") end
	return all
end
local function accept(id, d)
	if d.rev < (versions[id] or -1) then return end
	cache[id], versions[id] = d, d.rev
	local p = Players:GetPlayerByUserId(id)
	if p and apply then apply(p, d) end
end
function Registry.Load(p)
	local ok, data = pcall(function() if not store then return cache[p.UserId] end
		local options = Instance.new("DataStoreGetOptions"); options.UseCache = false
		return store:GetAsync(key(p.UserId), options) end)
	if ok and p.Parent then accept(p.UserId, normalize(data)) end
	return ok
end
function Registry.Set(by, id, gift, on)
	if not Items.IsOwner(by) or typeof(id) ~= "number" or id % 1 ~= 0 or id <= 0 or typeof(gift) ~= "string" or not valid(gift) then return false, "Invalid gift request." end
	local owner = Items.IsGameOwner(by)
	if gift == "admin" and not owner then return false, "Only the owner can change admin gifts." end
	local target = Players:GetPlayerByUserId(id)
	if target and Items.IsGameOwner(target) and not RunService:IsStudio() then return false, "The owner already has every power." end
	if busy[id] then return false, "This record is being updated. Try again." end
	busy[id] = true
	local denied = false
	local function update(raw)
		local d = normalize(raw)
		if not owner and (d.admin or (not on and d.granters[gift] ~= by.UserId)) then denied = true; return nil end
		if gift == "admin" then d.admin = on
		else
			local group, name = gift:match("^(%a+):(.+)$")
			local list = group == "power" and d.powers or d.titles
			local i = table.find(list, name)
			if on and not i then table.insert(list, name) elseif not on and i then table.remove(list, i) end
		end
		d.granters[gift] = on and by.UserId or nil
		d.name = target and target.Name or d.name or ("User " .. id)
		d.rev += 1; d.v = 2
		return d
	end
	-- Ordinary private-server gifts remain session-only. The game owner can manage durable gifts anywhere.
	local durable = store and (SaveGate.CanSave() or owner)
	if not durable and not target then busy[id] = nil; return false, "Offline gift storage is unavailable here." end
	local ok, data = pcall(function()
		if durable then return store:UpdateAsync(key(id), update) end
		return update(cache[id])
	end)
	busy[id] = nil
	if not ok or not data or denied then return false, denied and "You can only revoke your own gifts." or "Gift save failed; try again." end
	accept(id, normalize(data))
	if durable then pcall(function() Messaging:PublishAsync(TOPIC, { id = id, rev = data.rev }) end) end
	return true, on and "Gift granted." or "Gift revoked globally."
end
local function entry(by, id, d)
	local visible = {}
	for _, gift in keys(d) do
		if Items.IsGameOwner(by) or d.granters[gift] == by.UserId then table.insert(visible, gift) end
	end
	if #visible == 0 then return nil end
	return { userId = id, name = d.name or ("User " .. id), online = Players:GetPlayerByUserId(id) ~= nil, gifts = visible }
end
local function list(by, nextPage, userId)
	local entries, more = {}, false
	local ok, err = pcall(function()
		if userId then
			local d = normalize(store and store:GetAsync(key(userId)) or cache[userId])
			local e = entry(by, userId, d); if e then table.insert(entries, e) end
		elseif store then
			if not nextPage or not pages[by] then pages[by] = store:ListKeysAsync("g_", 20)
			elseif not pages[by].IsFinished then pages[by]:AdvanceToNextPageAsync() end
			for _, k in pages[by]:GetCurrentPage() do
				local id = tonumber(k.KeyName:match("^g_(%d+)$"))
				if id then
					local e = entry(by, id, normalize(store:GetAsync(k.KeyName)))
					if e then table.insert(entries, e) end
				end
			end
			more = not pages[by].IsFinished
		else
			for id, d in cache do local e = entry(by, id, d); if e then table.insert(entries, e) end end
		end
	end)
	if by.Parent then remote:FireClient(by, "list", entries, more, ok and (#entries == 0 and "No matching gifts on this page." or "Saved gifts / select one to revoke") or "Gift storage is unavailable. Try again.") end
end
function Registry.Init(callback)
	apply = callback
	if not (RunService:IsStudio() and game.GameId == 0) then
		local ok, value = pcall(function() return DSS:GetDataStore(Config.GiftStoreName) end)
		if ok then store = value end
	end
	remote = Instance.new("RemoteEvent"); remote.Name, remote.Parent = "GiftRegistry", game.ReplicatedStorage.Remotes
	remote.OnServerEvent:Connect(function(by, action, id, gift)
		if not Items.IsOwner(by) or (by.Character and by.Character:GetAttribute("ControlActive")) then return end
		if os.clock() - (last[by] or -10) < 1 then return end
		last[by] = os.clock()
		if action == "list" then list(by, false)
		elseif action == "next" then list(by, true)
		elseif action == "lookup" and typeof(id) == "number" and id % 1 == 0 and id > 0 then list(by, false, id)
		elseif action == "revoke" then
			local ok, message = Registry.Set(by, id, gift, false)
			remote:FireClient(by, "result", ok, message)
			if ok then list(by, false, id) end
		end
	end)
	if store then
		pcall(function() Messaging:SubscribeAsync(TOPIC, function(m)
			local d = m.Data
			if typeof(d) == "table" and typeof(d.id) == "number" then
				local p = Players:GetPlayerByUserId(d.id)
				if p then Registry.Load(p) end
			end
		end) end)
		task.spawn(function()
			while true do task.wait(45); for _, p in Players:GetPlayers() do Registry.Load(p) end end
		end)
	end
	Players.PlayerRemoving:Connect(function(p) pages[p], last[p] = nil, nil end)
end
return Registry
