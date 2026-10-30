--!nonstrict
-- Cyberpsychosis: private memories, server-verified phantom hits, malfunction and close-range rampages.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Items)
local Service = {}
local memories, phantoms, nextEpisode, nextFault, nextStrike = {}, {}, {}, {}, {}
local sequence = 0
local deps, remote
local rng = Random.new()
local function severity(p)
	if workspace:GetAttribute("PsychosisOff") then return 0 end
	if p:GetAttribute("AdminPsychoEnabled") ~= true and (Items.IsOwner(p) or (p.Character and p.Character:GetAttribute("Colossus"))) then return 0 end
	return math.clamp(math.max(p:GetAttribute("CyPsycho") or 0, p:GetAttribute("SandevistanPsycho") or 0), 0, 1)
end
local function torso(p)
	local ch = p.Character
	return ch and not ch:GetAttribute("Dead") and ch:FindFirstChild("Torso")
end
local function clear(p)
	phantoms[p] = nil
	if p.Parent then remote:FireClient(p, "clear") end
end
local function spawnMemory(p, level)
	local root = torso(p)
	local list = memories[p]
	if not root or not list or #list == 0 then return end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { p.Character, workspace:FindFirstChild("FX") or p.Character }
	local angle = rng:NextNumber(-math.pi, math.pi)
	local at = root.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(24, 48)
	local floor = workspace:Raycast(at + Vector3.new(0, 12, 0), Vector3.new(0, -32, 0), rp)
	if not floor or floor.Normal.Y < 0.7 then return end
	at = floor.Position + Vector3.new(0, 3, 0)
	local rec = { id = list[rng:NextInteger(1, #list)], at = at, untilT = workspace:GetServerTimeNow() + 10 + 6 * level, character = p.Character }
	phantoms[p] = rec
	remote:FireClient(p, "phantom", rec.id, at, rec.untilT)
end
local function shot(p, origin, dir, range)
	local rec = phantoms[p]
	if not rec or rec.character ~= p.Character or rec.untilT < workspace:GetServerTimeNow() or severity(p) < 0.25 or dir.Magnitude < 0.1 then return end
	dir = dir.Unit
	local delta = rec.at - origin
	local along = delta:Dot(dir)
	if along <= 0 or along > range then return end
	local nearest = origin + dir * along
	local diff = nearest - rec.at
	if Vector2.new(diff.X, diff.Z).Magnitude > 1.7 or math.abs(diff.Y) > 3 then return end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { p.Character, workspace:FindFirstChild("FX") or p.Character }
	local hit = workspace:Raycast(origin, dir * math.max(0, along - 1.8), rp)
	if hit then return end
	clear(p)
	local root = torso(p)
	if not root then return end
	remote:FireClient(p, "detonate")
	deps.ExplosionService.Explode(root.Position, { radius = 10, damage = 65, power = 55, attacker = p, cause = "Psychosis feedback", kind = "grenade" })
	p.Character:SetAttribute("ForceKill", true)
	p.Character:SetAttribute("NoRegrowth", true)
	deps.DamageService.Kill(p.Character, "Shot a neural phantom")
end
function Service.Init(d)
	deps = d
	remote = Instance.new("RemoteEvent")
	remote.Name, remote.Parent = "Psychosis", ReplicatedStorage.Remotes
	-- No client request can claim a phantom hit: only validated gun / cyberarm shots reach this hook.
	local previousShot = deps.GunService.OnShotLine
	deps.GunService.OnShotLine = function(p, origin, dir, range)
		if previousShot then previousShot(p, origin, dir, range) end
		shot(p, origin, dir, range)
	end
	local previousKill = deps.DamageService.OnKill
	deps.DamageService.OnKill = function(victim, killer, state)
		if previousKill then previousKill(victim, killer, state) end
		if killer and killer.Parent and victim ~= killer.Character and not victim:GetAttribute("IsDummy") then
			sequence += 1
			local list = memories[killer] or {}; memories[killer] = list
			table.insert(list, sequence)
			while #list > 6 do table.remove(list, 1) end
			remote:FireClient(killer, "remember", sequence, victim)
		end
	end
	local function hook(p)
		p.CharacterAdded:Connect(function() clear(p) end)
	end
	Players.PlayerAdded:Connect(hook); for _, p in Players:GetPlayers() do hook(p) end
	Players.PlayerRemoving:Connect(function(p)
		memories[p], phantoms[p], nextEpisode[p], nextFault[p], nextStrike[p] = nil, nil, nil, nil, nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.4)
			local now = workspace:GetServerTimeNow()
			for _, p in Players:GetPlayers() do
				local level, root = severity(p), torso(p)
				if level < 0.25 or not root then if phantoms[p] then clear(p) end; continue end
				if phantoms[p] and phantoms[p].untilT <= now then clear(p) end
				if now >= (nextEpisode[p] or 0) then
					nextEpisode[p] = now + rng:NextNumber(12, 22) * (1.4 - level)
					spawnMemory(p, level)
					remote:FireClient(p, "episode", level, 5 + 6 * level)
				end
				if level >= 0.55 and now >= (nextFault[p] or 0) then
					nextFault[p] = now + rng:NextNumber(10, 18)
					local ch = p.Character
					local duration = 1.5 + 3 * level
					local choice = rng:NextInteger(1, 3)
					if choice == 1 then ch:SetAttribute("ChipsDisabled", math.max(ch:GetAttribute("ChipsDisabled") or 0, now + duration))
					elseif choice == 2 then ch:SetAttribute("ChipCrawl", 0.25); ch:SetAttribute("ChipCrawlUntil", now + duration)
					else
						ch:SetAttribute("ChipGrabLock", now + duration)
						for _, item in deps.OwnershipService.HeldItems(p) do deps.OwnershipService.DropItem(item) end
					end
					remote:FireClient(p, "fault", choice, duration)
					if level >= 0.8 then
						ch:SetAttribute("CrashOut", now + 8)
						deps.CyberService.Remote:FireClient(p, "crash", 8, "neural overload")
					end
				end
				-- A real, server-controlled melee burst makes unarmed rampages dangerous too.
				if (p.Character:GetAttribute("CrashOut") or 0) > now and now >= (nextStrike[p] or 0) then
					nextStrike[p] = now + 0.8
					local victim, best = nil, 7
					for body in deps.DamageService.Bodies() do
						local t = body:FindFirstChild("Torso")
						if body ~= p.Character and t and not body:GetAttribute("Dead") and (t.Position - root.Position).Magnitude < best then victim, best = body, (t.Position - root.Position).Magnitude end
					end
					if victim then
						local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = { p.Character }
						local hit = workspace:Raycast(root.Position, victim.Torso.Position - root.Position, rp)
						if not hit or hit.Instance:IsDescendantOf(victim) then
							deps.DamageService.ApplyDamage(victim, "Torso", 24 + 24 * level, nil, { attacker = p, cause = "Cyberpsychosis rampage", melee = true, allowSever = false })
						end
					end
				end
			end
		end
	end)
end
return Service
