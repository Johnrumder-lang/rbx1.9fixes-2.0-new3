--!nonstrict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Persist = require(script.Parent.Persist)
local JobService = {}
local definitions = {
	assassination = { name = "PLAYER BOUNTY", description = "Eliminate one marked player. You must survive.", reward = 150, goal = 1, duration = 600 },
	courier = { name = "PACKAGE DELIVERY", description = "Carry a real package between two random locations.", reward = 30, goal = 2, duration = 600 },
	cleanup = { name = "THREE KILL STREAK", description = "Kill three players without dying. NPCs do not count.", reward = 200, goal = 3, duration = 600 },
}
local active, cooldown, requests = {}, {}, {}
local deps, remote
local rng = Random.new()
local function root(p)
	local ch = p.Character
	return ch and not ch:GetAttribute("Dead") and ch:FindFirstChild("Torso") or nil
end
local function syncCooldown(p, prof)
	if not prof or not prof.loaded then return end
	if prof.jobActive and not active[p] then
		prof.jobActive = false; prof.jobFailedUntil = os.time() + 180; Persist.Dirty(p)
	end
	local remaining = math.max(0, (prof.jobFailedUntil or 0) - os.time())
	if remaining > 0 then cooldown[p] = math.max(cooldown[p] or 0, workspace:GetServerTimeNow() + remaining) end
end
local function send(p, message)
	if not p.Parent then return end
	syncCooldown(p, Persist.Get(p))
	local job = active[p]
	local d = job and definitions[job.id]
	local target = job and job.targetPlayer and job.targetPlayer.Character
	remote:FireClient(p, "state", job and {
		id = job.id, name = d.name, reward = d.reward, goal = d.goal, progress = job.progress,
		deadline = job.deadline, target = target, point = job.point,
		objective = job.objective or d.description,
	} or false, message, cooldown[p] or 0)
end
local function clear(p)
	local job = active[p]; active[p] = nil
	-- A PvP target is another player's character; never destroy it as job cleanup.
	if job and job.package and job.package.Parent then
		deps.OwnershipService.DropItem(job.package); job.package:Destroy()
	end
end
local function fail(p, why)
	if not active[p] then return end
	local prof = Persist.Get(p)
	if prof then prof.jobActive = false; prof.jobFailedUntil = os.time() + 180; Persist.Dirty(p) end
	clear(p); cooldown[p] = workspace:GetServerTimeNow() + 180
	send(p, (why or "CONTRACT FAILED") .. " / TRY AGAIN IN 3 MINUTES")
end
local function finish(p)
	local job = active[p]
	if not job then return end
	local reward = definitions[job.id].reward
	local progress = Persist.Get(p)
	if progress then progress.jobActive = false; progress.jobFailedUntil = 0 end
	clear(p); cooldown[p] = 0
	deps.SkinService.AddCash(p, reward, "contract")
	local prof = Persist.Get(p)
	if prof then prof.jobsCompleted = (prof.jobsCompleted or 0) + 1; Persist.Dirty(p) end
	send(p, "CONTRACT COMPLETE  +$" .. reward)
end
local function deliveryLocations()
	local map = workspace:FindFirstChild("Map")
	if not map then return {} end
	local points = {}
	local function add(label, pos)
		local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Include
		local env = { map }; for _, p in workspace:GetChildren() do if p:IsA("BasePart") and p.Anchored then table.insert(env, p) end end
		rp.FilterDescendantsInstances = env
		local hit = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -18, 0), rp)
		if hit and hit.Normal.Y > 0.8 then table.insert(points, { name = label, point = hit.Position + Vector3.new(0, 1.3, 0) }) end
	end
	local site = map:FindFirstChild("TeleportTarget_Site", true)
	if site then add("CONSTRUCTION SITE", site.Position + Vector3.new(5, 0, 0)) end
	local red = map:FindFirstChild("BrickHouse", true)
	if red and red:IsA("Model") then local cf, size = red:GetBoundingBox(); add("RED HOUSE", Vector3.new(cf.X, 2, cf.Z + size.Z / 2 + 5)) end
	local desk = map:FindFirstChild("RipperDeskSpot", true)
	if desk then add("RIPPERDOC", desk.Position + Vector3.new(0, 0, 3)) end
	local garage = map:FindFirstChild("Garage", true)
	if garage and garage:IsA("Model") then local cf, size = garage:GetBoundingBox(); add("GARAGE", Vector3.new(cf.X, 2, cf.Z + size.Z / 2 + 5)) end
	return points
end
local function accept(p, id)
	local d, torso = definitions[id], root(p)
	local prof = Persist.Get(p)
	if not d or not torso or not prof or not prof.loaded or active[p] then return end
	if torso.Parent:GetAttribute("ControlActive") then return end
	syncCooldown(p, prof)
	if workspace:GetServerTimeNow() < (cooldown[p] or 0) then send(p, "FAILED CONTRACT COOLDOWN"); return end
	local mode = workspace:GetAttribute("Mode")
	if mode and mode ~= "sandbox" and mode ~= "" then send(p, "Contracts are available in sandbox mode."); return end
	local job = { id = id, progress = 0, deadline = workspace:GetServerTimeNow() + d.duration, character = p.Character, seen = {} }
	if id == "assassination" then
		local candidates = {}
		for _, other in Players:GetPlayers() do
			if other ~= p and root(other) and not deps.DamageService.Protected(other.Character, p) then table.insert(candidates, other) end
		end
		if #candidates == 0 then send(p, "No eligible player target is available."); return end
		job.targetPlayer = candidates[rng:NextInteger(1, #candidates)]
		job.targetCharacter = job.targetPlayer.Character
		job.objective = "ELIMINATE " .. job.targetPlayer.DisplayName .. " (@" .. job.targetPlayer.Name .. ")"
	elseif id == "cleanup" then
		if #Players:GetPlayers() < 2 then send(p, "Another player must join first."); return end
	elseif id == "courier" then
		local locations = deliveryLocations()
		if #locations < 2 then send(p, "Load the sandbox city for package routes."); return end
		local start = table.remove(locations, rng:NextInteger(1, #locations))
		local dest = locations[rng:NextInteger(1, #locations)]
		job.point, job.destination, job.destinationName = start.point, dest.point, dest.name
		job.objective = "COLLECT AT " .. start.name .. " / DELIVER TO " .. dest.name
		job.package = deps.PropService.Place("package", CFrame.new(start.point), p)
		if not job.package or not job.package.PrimaryPart then send(p, "Package unavailable."); return end
		job.package:SetAttribute("BoundTo", p.UserId)
		job.package:SetAttribute("DeliveryOwner", p.UserId)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText, prompt.ObjectText = "Collect package", start.name
		prompt.KeyboardKeyCode = Enum.KeyCode.F; prompt.MaxActivationDistance = 9
		prompt.Parent = job.package.PrimaryPart
		prompt.Triggered:Connect(function(who)
			if who ~= p or active[p] ~= job or not root(p) or root(p).Parent:GetAttribute("ControlActive") then return end
			if (root(p).Position - job.package.PrimaryPart.Position).Magnitude > 10 then return end
			deps.OwnershipService.Equip(p, job.package, "Right")
		end)
		job.prompt = prompt
	end
	active[p] = job; prof.jobActive = true; Persist.Dirty(p); send(p, "CONTRACT ACCEPTED")
end
local function tick()
			for p, job in active do
				local torso = root(p)
				if not torso or p.Character ~= job.character or workspace:GetServerTimeNow() >= job.deadline then fail(p)
				elseif job.targetPlayer and (not root(job.targetPlayer) or job.targetPlayer.Character ~= job.targetCharacter) then fail(p, "TARGET LOST")
				elseif job.package then
					local box = job.package
					if not box.Parent or not box.PrimaryPart then fail(p, "PACKAGE LOST"); continue end
					local carrying = deps.OwnershipService.ItemHolder(box) == p or box:GetAttribute("StowedBy") == p.UserId
					if job.progress == 0 and carrying then
						job.progress = 1; job.point = job.destination; job.prompt.Enabled = false
						job.objective = "CARRY THE PACKAGE TO " .. job.destinationName; send(p, "PACKAGE COLLECTED")
					elseif job.progress == 1 and carrying and (torso.Position - job.destination).Magnitude < 9 and (box.PrimaryPart.Position - torso.Position).Magnitude < 12 then finish(p) end
				end
			end
end
function JobService.Init(d)
	deps = d
	remote = Instance.new("RemoteEvent"); remote.Name, remote.Parent = "Jobs", ReplicatedStorage.Remotes
	remote.OnServerEvent:Connect(function(p, action, id)
		if typeof(action) ~= "string" then return end
		if p.Character and p.Character:GetAttribute("ControlActive") then return end
		local now = os.clock()
		if now - (requests[p] or 0) < 0.3 then return end
		requests[p] = now
		if action == "list" then remote:FireClient(p, "catalog", definitions); send(p)
		elseif action == "accept" and typeof(id) == "string" then accept(p, id)
		elseif action == "cancel" then fail(p, "CONTRACT CANCELLED") end
	end)
	local prior = deps.DamageService.OnKill
	deps.DamageService.OnKill = function(victim, killer, state)
		if prior then prior(victim, killer, state) end
		local victimPlayer = Players:GetPlayerFromCharacter(victim)
		if victimPlayer then fail(victimPlayer, "YOU DIED / CONTRACT FAILED") end
		local job = killer and active[killer]
		if job and root(killer) and victimPlayer and victimPlayer ~= killer and not job.seen[victim] then
			if (job.id == "assassination" and job.targetPlayer == victimPlayer) or job.id == "cleanup" then
				job.seen[victim] = true; job.progress += 1
				if job.progress >= definitions[job.id].goal then finish(killer) else send(killer, "PLAYER ELIMINATED") end
			end
		end
		for p, other in active do
			if other.id == "assassination" and other.targetPlayer == victimPlayer then fail(p, "SOMEONE ELSE KILLED YOUR TARGET") end
		end
	end
	Players.PlayerRemoving:Connect(function(p)
		fail(p, "CONTRACT ABANDONED"); cooldown[p], requests[p] = nil, nil
		for who, job in active do if job.targetPlayer == p then fail(who, "TARGET LEFT") end end
	end)
	task.spawn(function() while true do task.wait(0.25); tick() end end)
end
return JobService
