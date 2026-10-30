--!nonstrict
-- Paid fictional contracts. Targets, completion and payouts are all decided by the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Persist = require(script.Parent.Persist)
local JobService = {}
local definitions = {
	assassination = { name = "ASSASSINATION", description = "Track and eliminate a marked rogue mercenary.", reward = 450, goal = 1, duration = 300 },
	courier = { name = "NEURAL COURIER", description = "Collect a data package at the ripperdoc and deliver it to the hospital.", reward = 250, goal = 2, duration = 240 },
	cleanup = { name = "STREET CLEANUP", description = "Eliminate three hostile NPCs. Training dummies do not count.", reward = 300, goal = 3, duration = 300 },
}
local active, cooldown, requests = {}, {}, {}
local deps, remote
local function root(p)
	local ch = p.Character
	return ch and not ch:GetAttribute("Dead") and ch:FindFirstChild("Torso") or nil
end
local function send(p, message)
	local job = active[p]
	local d = job and definitions[job.id]
	remote:FireClient(p, "state", job and {
		id = job.id, name = d.name, reward = d.reward, goal = d.goal, progress = job.progress,
		deadline = job.deadline, target = job.target, point = job.point,
		objective = job.id == "courier" and (job.progress == 0 and "COLLECT AT RIPPERDOC" or "DELIVER TO HOSPITAL") or d.description,
	} or false, message, cooldown[p] or 0)
end
local function clear(p)
	local job = active[p]
	active[p] = nil
	if job and job.target and job.target.Parent then job.target:Destroy() end
end
local function finish(p)
	local job = active[p]
	if not job then return end
	local d = definitions[job.id]
	active[p] = nil -- Claim before paying; repeated kill callbacks cannot pay twice.
	if job.target and job.target.Parent then task.delay(4, function() if job.target.Parent then job.target:Destroy() end end) end
	cooldown[p] = workspace:GetServerTimeNow() + 45
	deps.SkinService.AddCash(p, d.reward, "contract: " .. d.name)
	local prof = Persist.Get(p)
	if prof then prof.jobsCompleted = (prof.jobsCompleted or 0) + 1; Persist.Dirty(p) end
	send(p, "CONTRACT COMPLETE  +$" .. d.reward)
end
local function accept(p, id)
	local d, torso = definitions[id], root(p)
	local prof = Persist.Get(p)
	if not d or not torso or not prof or not prof.loaded or active[p] then return end
	if workspace:GetServerTimeNow() < (cooldown[p] or 0) then send(p, "New contracts are cooling down."); return end
	local mode = workspace:GetAttribute("Mode")
	if mode and mode ~= "sandbox" and mode ~= "" then send(p, "Contracts are available in sandbox mode."); return end
	local job = { id = id, progress = 0, deadline = workspace:GetServerTimeNow() + d.duration, character = p.Character }
	if id == "assassination" then
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Include
		local map = workspace:FindFirstChild("Map")
		rp.FilterDescendantsInstances = map and { map } or { workspace.Terrain }
		local at
		for n = 1, 16 do
			local angle = n * math.pi / 8
			local pos = torso.Position + Vector3.new(math.cos(angle) * 65, 18, math.sin(angle) * 65)
			local hit = workspace:Raycast(pos, Vector3.new(0, -55, 0), rp)
			if hit and hit.Normal.Y > 0.85 and math.abs(hit.Position.Y - torso.Position.Y) < 12 then at = hit.Position + Vector3.new(0, 3.5, 0); break end
		end
		if not at then send(p, "Move into the city to locate a contract target."); return end
		job.target = deps.NPCService.Spawn("cyber", CFrame.new(at), p, { name = "Rogue Netrunner", weapon = "smg" })
		if not job.target then send(p, "Target unavailable. Try again."); return end
		job.target:SetAttribute("ContractOwner", p.UserId)
	elseif id == "courier" then
		local map = workspace:FindFirstChild("Map")
		local desk = map and map:FindFirstChild("RipperFrontDesk", true)
		local hospital = map and map:FindFirstChild("ReplayChair", true)
		if not desk or not hospital then send(p, "Load the city map for courier work."); return end
		job.point, job.destination = desk.Position, hospital.Position
	end
	active[p] = job
	send(p, "CONTRACT ACCEPTED")
end
function JobService.Init(d)
	deps = d
	remote = Instance.new("RemoteEvent")
	remote.Name, remote.Parent = "Jobs", ReplicatedStorage.Remotes
	remote.OnServerEvent:Connect(function(p, action, id)
		if typeof(action) ~= "string" then return end
		local now = os.clock()
		if now - (requests[p] or 0) < 0.3 then return end
		requests[p] = now
		if action == "list" then remote:FireClient(p, "catalog", definitions); send(p)
		elseif action == "accept" and typeof(id) == "string" then accept(p, id)
		elseif action == "cancel" then clear(p); cooldown[p] = workspace:GetServerTimeNow() + 15; send(p, "Contract cancelled.") end
	end)
	local prior = deps.DamageService.OnKill
	deps.DamageService.OnKill = function(victim, killer, state)
		if prior then prior(victim, killer, state) end
		if not killer then return end
		local job = active[killer]
		if not job or not root(killer) then return end
		if (job.id == "assassination" and victim == job.target) or (job.id == "cleanup" and victim:GetAttribute("IsNPC") and not victim:GetAttribute("IsDummy") and not victim:GetAttribute("StandUp") and victim:GetAttribute("Hostile") == true and victim:GetAttribute("Spawner") == nil and not victim:GetAttribute("ContractOwner")) then
			job.progress += 1
			if job.progress >= definitions[job.id].goal then finish(killer) else send(killer, "TARGET ELIMINATED") end
		end
	end
	Players.PlayerRemoving:Connect(function(p) clear(p); cooldown[p], requests[p] = nil, nil end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			for p, job in active do
				local torso = root(p)
				if not torso or p.Character ~= job.character or workspace:GetServerTimeNow() >= job.deadline then
					clear(p); cooldown[p] = workspace:GetServerTimeNow() + 15; send(p, "CONTRACT FAILED")
				elseif job.target and (not job.target.Parent or job.target:GetAttribute("Dead")) then
					clear(p); send(p, "The marked target was lost. Choose another contract.")
				elseif job.id == "courier" and job.point and (torso.Position - job.point).Magnitude <= 9 then
					job.progress += 1
					if job.progress >= 2 then finish(p)
					else job.point = job.destination; send(p, "PACKAGE COLLECTED — DELIVER TO HOSPITAL") end
				end
			end
		end
	end)
end
return JobService
