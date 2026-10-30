--!nonstrict
-- UTC calendar days; consecutive 7-day cycle. Rewards and claim receipt commit together.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Persist = require(script.Parent.Persist)
local WeaponSkins = require(ReplicatedStorage.Shared.WeaponSkins)
local Cyberware = require(ReplicatedStorage.Shared.Cyberware)
local Service = {}
local remote, deps
local busy, last = {}, {}
local rng = Random.new()
local function today() return math.floor(os.time() / 86400) end
local function schedule(daily, date)
	if (daily.date or -1) >= date then return daily.step or 1, false end
	return daily.date == date - 1 and ((daily.step or 0) % 7 + 1) or 1, true
end
local function state(p, message)
	local c = Persist.Community(p)
	if not c then return end
	local daily = c.daily or { date = -1, step = 0, cases = {} }
	local date = today()
	local step, available = schedule(daily, date)
	local cases = {}
	for token, id in daily.cases or {} do
		local def = Cyberware.ById[id]
		if def then table.insert(cases, { token = token, name = def.name, id = id }) end
	end
	table.sort(cases, function(a, b) return a.token < b.token end)
	p:SetAttribute("DailyAvailable", available)
	remote:FireClient(p, "state", { date = date, step = step, available = available, nextAt = (date + 1) * 86400, cases = cases, message = message })
end
local function roll(p, step)
	local prof = Persist.Get(p)
	local count = step == 3 and 1 or (step == 7 and 3 or 0)
	local reward = { cash = 0, skins = {}, names = {} }
	if count > 0 then
		local pool = {}
		for _, skin in WeaponSkins.List do if not prof.owned[skin.id] then table.insert(pool, skin) end end
		for _ = 1, count do
			if #pool == 0 then reward.cash += 250
			else
				local skin = table.remove(pool, rng:NextInteger(1, #pool))
				table.insert(reward.skins, skin.id); table.insert(reward.names, skin.name)
			end
		end
	else
		reward.cash = math.clamp(math.floor(25 + rng:NextNumber() ^ 2 * 976), 25, 1000)
		if rng:NextNumber() < 0.005 then
			local pool = {}
			for _, def in Cyberware.List do if not def.admin then table.insert(pool, def) end end
			if #pool > 0 then reward.implant = pool[rng:NextInteger(1, #pool)].id end
		end
	end
	return reward
end
local function claim(p)
	local c = Persist.Community(p)
	if not c then return false, "Your profile is loading." end
	local date = today()
	local step, available = schedule(c.daily or {}, date)
	if not available then return false, "Already claimed today. Next reward at 00:00 UTC." end
	local reward = roll(p, step) -- never reroll inside an UpdateAsync callback
	local ok, message = Persist.CommitCommunity(p, function(data, profile)
		data.daily = data.daily or { date = -1, step = 0, cases = {} }
		local expected, allowed = schedule(data.daily, date)
		if not allowed or expected ~= step then return false, "Today's reward was already claimed." end
		data.daily.date, data.daily.step = date, step
		data.daily.cases = data.daily.cases or {}
		if reward.implant then data.daily.cases[tostring(date)] = reward.implant end
		profile.cash += reward.cash
		for _, id in reward.skins do if not table.find(profile.owned, id) then table.insert(profile.owned, id) end end
		return true, "Day " .. step .. " claimed."
	end)
	if not ok then return false, message end
	deps.SkinService.Refresh(p)
	local parts = {}
	if reward.cash > 0 then table.insert(parts, "$" .. reward.cash) end
	for _, name in reward.names do table.insert(parts, name) end
	if reward.implant then table.insert(parts, Cyberware.ById[reward.implant].name .. " case (TAKE below)") end
	return true, "RECEIVED: " .. table.concat(parts, " + ")
end
local function takeCase(p, token)
	if typeof(token) ~= "string" or #token > 20 then return false, "Invalid reward." end
	local ch = p.Character
	local root = ch and not ch:GetAttribute("Dead") and ch:FindFirstChild("Torso")
	if not root then return false, "Respawn before collecting an implant." end
	local c = Persist.Community(p)
	local id = c and c.daily and c.daily.cases and c.daily.cases[token]
	if not id or not Cyberware.ById[id] or Cyberware.ById[id].admin then return false, "That case is not available." end
	-- Build off-world before consuming the voucher. No one can take it during saving.
	local item = deps.PropBuilders.implantcase(root.CFrame * CFrame.new(0, 1, -3))
	deps.RipperdocService.LabelCase(item, id, 1)
	local ok, message = Persist.CommitCommunity(p, function(data)
		if not data.daily or not data.daily.cases or data.daily.cases[token] ~= id then return false, "Case already collected." end
		data.daily.cases[token] = nil
		return true, "Tier 1 implant case collected. Another player can install it with F."
	end)
	if not ok then item:Destroy(); return false, message end
	item:SetAttribute("Spawner", p.UserId)
	item.Parent = workspace:FindFirstChild("Props") or workspace
	if deps.PropService.OnPlaced then deps.PropService.OnPlaced(item) end
	if item.PrimaryPart then pcall(function() item.PrimaryPart:SetNetworkOwner(p) end) end
	if p.Parent and p.Character == ch then deps.OwnershipService.Equip(p, item, "Right") end
	return true, message
end
function Service.Init(d)
	deps = d
	remote = Instance.new("RemoteEvent"); remote.Name = "DailyRewards"; remote.Parent = ReplicatedStorage.Remotes
	remote.OnServerEvent:Connect(function(p, action, value)
		if busy[p] or typeof(action) ~= "string" or os.clock() - (last[p] or -10) < 0.5 then return end
		last[p] = os.clock()
		if action == "state" then state(p); return end
		if p.Character and p.Character:GetAttribute("ControlActive") then return end
		busy[p] = true
		local ok, success, message = pcall(function()
			if action == "claim" then return claim(p) elseif action == "take" then return takeCase(p, value) end
			return false, "Unknown reward action."
		end)
		busy[p] = nil
		if not ok then warn("[Daily rewards]", success); message = "Reward request failed. Please retry." end
		state(p, message)
		if ok and success then remote:FireClient(p, "claimed") end
	end)
	local function added(p) task.spawn(function() if Persist.Wait(p) then state(p) end end) end
	Players.PlayerAdded:Connect(added); for _, p in Players:GetPlayers() do added(p) end
	Players.PlayerRemoving:Connect(function(p) busy[p], last[p] = nil, nil end)
	task.spawn(function() while true do task.wait(30); for _, p in Players:GetPlayers() do state(p) end end end)
end
return Service
