--!nonstrict
-- Canonical clan rosters + versioned profile memberships. Invites are consent-based,
-- limited to the current server; accepted memberships survive reconnects.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Persist = require(script.Parent.Persist)
local Epoch = require(script.Parent.ProgressEpoch)
local SaveGate = require(script.Parent.SaveGate)
local Service = { Cost = 2500, MaxMembers = 50 }
local store, remote
local memory, invites, busy, last = {}, {}, {}, {}
local function copy(v)
	if typeof(v) ~= "table" then return v end
	local out = {}; for k, value in v do out[k] = copy(value) end; return out
end
local function key(id) return "e" .. Epoch.Value .. "_" .. id end
local function read(id)
	if not store then return RunService:IsStudio(), copy(memory[id]) end
	return pcall(function()
		local options = Instance.new("DataStoreGetOptions"); options.UseCache = false
		return store:GetAsync(key(id), options)
	end)
end
local function update(id, change)
	if not store then
		if not RunService:IsStudio() then return false end
		local data = change(copy(memory[id])); if data then memory[id] = copy(data) end
		return true, copy(memory[id])
	end
	return pcall(function() return store:UpdateAsync(key(id), change) end)
end
local function refOf(p)
	local c = Persist.Community(p); return c and c.clan
end
local function member(p, ref)
	return { name = p.Name, display = p.DisplayName, token = ref.token }
end
local function valid(record, p, ref)
	local m = record and not record.disbanded and record.members and record.members[tostring(p.UserId)]
	return m and m.token == ref.token
end
local function recover(p, ref)
	local ok, record = read(ref.id)
	if not ok then return false end
	if not record and ref.owner == p.UserId then
		-- The cost + intent was committed before writing the roster. A disconnect or
		-- temporary roster failure resumes the same creation without charging twice.
		ok, record = update(ref.id, function(old)
			return old or { name = ref.name, owner = p.UserId, members = { [tostring(p.UserId)] = member(p, ref) } }
		end)
	end
	return ok, record
end
local function setAttributes(p, ref, record)
	p:SetAttribute("ClanId", ref and ref.id)
	p:SetAttribute("ClanName", record and record.name)
	p:SetAttribute("ClanOwner", record and record.owner)
end
local function refresh(p, message)
	if not p.Parent then return end
	local c = Persist.Community(p)
	if not c then return end
	local ref, record = c.clan, nil
	if ref then
		local ok; ok, record = recover(p, ref)
		if not ok then remote:FireClient(p, "state", { error = "Clan storage unavailable. Retry shortly." }); return end
		if not valid(record, p, ref) then
			local removed = Persist.CommitCommunity(p, function(data) data.clan = nil; return true end)
			if removed then ref = nil end
			record = nil
		end
	end
	setAttributes(p, record and ref, record)
	local state = { message = message, cost = Service.Cost, clan = nil, invites = {} }
	if ref and record then
		local members = {}
		for id, m in record.members do table.insert(members, { userId = tonumber(id), name = m.name, display = m.display }) end
		table.sort(members, function(a, b) return a.userId < b.userId end)
		state.clan = { id = ref.id, name = record.name, owner = record.owner, members = members }
	end
	local now = os.time()
	for id, invite in invites[p] or {} do
		if invite.expires <= now then invites[p][id] = nil
		else table.insert(state.invites, { id = id, name = invite.name, by = invite.by, expires = invite.expires }) end
	end
	remote:FireClient(p, "state", state)
end
local function publish(id)
	for _, p in Players:GetPlayers() do
		local ref = refOf(p)
		if ref and ref.id == id then task.spawn(refresh, p) end
	end
end
local function filterName(p, raw)
	if typeof(raw) ~= "string" or #raw > 24 then return nil, "Use 3–24 letters, numbers, spaces, _ or -." end
	local name = raw:match("^%s*(.-)%s*$"):gsub("%s+", " ")
	if #name < 3 or not name:match("^[%w _%-]+$") then return nil, "Use 3–24 letters, numbers, spaces, _ or -." end
	local ok, clean = pcall(function()
		return TextService:FilterStringAsync(name, p.UserId):GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		if RunService:IsStudio() then return "Studio Clan" end
		return nil, "Name filtering unavailable. Please retry."
	end
	if clean:find("#", 1, true) or #clean < 3 then return nil, "Choose a different clan name." end
	return clean
end
local function create(p, raw)
	if refOf(p) then return false, "Leave your current clan first." end
	local name, why = filterName(p, raw); if not name then return false, why end
	local ref = { id = HttpService:GenerateGUID(false), token = HttpService:GenerateGUID(false), name = name, owner = p.UserId }
	local ok, message = Persist.CommitCommunity(p, function(c)
		if c.clan then return false, "You already belong to a clan." end
		c.clan = ref; return true, "Clan created for $2,500."
	end, Service.Cost)
	if not ok then return false, message end
	local saved = recover(p, ref)
	return true, saved and message or "Clan paid for. The roster will finish saving automatically; no second charge."
end
local function ownerRecord(p)
	local ref = refOf(p); if not ref then return nil end
	local ok, record = recover(p, ref)
	if ok and valid(record, p, ref) and record.owner == p.UserId then return ref, record end
	return nil
end
local function invite(p, userId)
	local ref, record = ownerRecord(p)
	if not ref then return false, "Only the clan leader can invite." end
	local target = typeof(userId) == "number" and Players:GetPlayerByUserId(userId)
	if not target or target == p or refOf(target) then return false, "Choose a player in this server who has no clan." end
	invites[target] = invites[target] or {}
	local count = 0; for _ in invites[target] do count += 1 end
	if count >= 10 and not invites[target][ref.id] then return false, "This player already has too many invitations." end
	invites[target][ref.id] = { by = p.DisplayName, name = record.name, expires = os.time() + 300 }
	refresh(target); remote:FireClient(target, "invite", record.name)
	return true, "Invitation sent (valid for 5 minutes)."
end
local function accept(p, id)
	if typeof(id) ~= "string" or refOf(p) then return false, "Leave your current clan first." end
	local invitation = invites[p] and invites[p][id]
	if not invitation or invitation.expires <= os.time() then return false, "That invitation expired." end
	local ref = { id = id, token = HttpService:GenerateGUID(false) }
	local joined, why = false, "Clan unavailable."
	local ok, record = update(id, function(old)
		joined = false
		if not old or old.disbanded then return nil end
		local count = 0; for _ in old.members do count += 1 end
		if count >= Service.MaxMembers then why = "This clan is full."; return nil end
		old.members[tostring(p.UserId)] = member(p, ref); joined = true; return old
	end)
	if not ok or not joined then return false, why end
	ref.name, ref.owner = record.name, record.owner
	local saved, message = Persist.CommitCommunity(p, function(c)
		if c.clan then return false, "You already belong to a clan." end
		c.clan = ref; return true, "Joined " .. record.name .. "."
	end)
	if not saved then
		update(id, function(old)
			if old and old.members and old.members[tostring(p.UserId)] and old.members[tostring(p.UserId)].token == ref.token then old.members[tostring(p.UserId)] = nil end
			return old
		end)
		return false, message
	end
	invites[p] = nil; publish(id)
	return true, message
end
local function remove(p, action, userId)
	local ref = refOf(p); if not ref then return false, "You have no clan." end
	local done, why = false, "Clan unavailable."
	local targetId = action == "leave" and p.UserId or userId
	local ok = update(ref.id, function(old)
		done = false
		if not valid(old, p, ref) then return nil end
		if action == "leave" and old.owner == p.UserId then why = "The leader must disband the clan first."; return nil end
		if action ~= "leave" and old.owner ~= p.UserId then why = "Only the leader can do that."; return nil end
		if action == "disband" then old.disbanded = true; old.members = {}
		elseif typeof(targetId) == "number" and targetId ~= old.owner then old.members[tostring(targetId)] = nil
		else why = "Invalid member."; return nil end
		done = true; return old
	end)
	if not ok or not done then return false, why end
	publish(ref.id)
	return true, action == "disband" and "Clan disbanded. The creation cost is not refunded." or "Membership removed."
end
function Service.Init()
	pcall(function() store = Epoch.Store("RagdollClans_v1") end)
	remote = Instance.new("RemoteEvent"); remote.Name = "Clans"; remote.Parent = ReplicatedStorage.Remotes
	remote.OnServerEvent:Connect(function(p, action, value)
		if typeof(action) ~= "string" or busy[p] or os.clock() - (last[p] or -10) < 0.5 then return end
		last[p] = os.clock()
		if action == "state" then task.spawn(refresh, p); return end
		if p.Character and p.Character:GetAttribute("ControlActive") then return end
		if not RunService:IsStudio() and (not SaveGate.CanSave() or not store) then refresh(p, "Clan changes require a public server with saving available."); return end
		busy[p] = true
		local ok, success, message = pcall(function()
			if action == "create" then return create(p, value)
			elseif action == "invite" then return invite(p, value)
			elseif action == "accept" then return accept(p, value)
			elseif action == "decline" and typeof(value) == "string" then if invites[p] then invites[p][value] = nil end; return true, "Invitation declined."
			elseif action == "leave" or action == "kick" or action == "disband" then return remove(p, action, value) end
			return false, "Unknown clan action."
		end)
		busy[p] = nil
		if not ok then warn("[Clans]", success); message = "Clan request failed. Please retry." end
		refresh(p, message)
	end)
	local function added(p) task.spawn(function() if Persist.Wait(p) then refresh(p) end end) end
	Players.PlayerAdded:Connect(added); for _, p in Players:GetPlayers() do added(p) end
	Players.PlayerRemoving:Connect(function(p) invites[p], busy[p], last[p] = nil, nil, nil end)
	task.spawn(function() while true do task.wait(30); for _, p in Players:GetPlayers() do task.spawn(refresh, p) end end end)
end
return Service
