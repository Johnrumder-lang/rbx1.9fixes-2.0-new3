--!nonstrict
-- Server-owned directives: client inputs cannot choose the goal, gun, target, or end time.
local Players = game:GetService("Players")
local Items = require(game.ReplicatedStorage.Shared.Items)
local Config = require(game.ReplicatedStorage.Shared.Config)
local Navigation = require(script.Parent.DirectivePath)
local Service = {}
local directives, deps = {}, nil
local function torso(ch) return ch and not ch:GetAttribute("Dead") and ch:FindFirstChild("Torso") end
local function clear(p)
	if directives[p] and directives[p].nav then Navigation.Clear(directives[p].nav) end
	directives[p] = nil
	p:SetAttribute("ControlTarget", nil)
	local ch = p.Character
	if ch then
		for _, a in { "ControlActive", "ControlGoal", "ControlAim", "ControlMove", "ControlJump", "CrashOut", "CrashOutSource" } do ch:SetAttribute(a, nil) end
	end
end
function Service.Start(p, targetId, seconds, source)
	if not p or not p.Parent then return false end
	if targetId then
		local target = Players:GetPlayerByUserId(targetId)
		if not target or target == p or not torso(target.Character) then return false end
	end
	local current = directives[p]
	if current and current.targetId and not targetId then return true end
	if current and current.nav then Navigation.Clear(current.nav) end
	directives[p] = { nav = Navigation.New(), source = source, targetId = targetId, untilT = targetId and math.huge or workspace:GetServerTimeNow() + (seconds or 10), nextGun = 0, nextShot = 0 }
	p:SetAttribute("ControlTarget", targetId)
	if p.Character then p.Character:SetAttribute("ControlActive", true) end
	return true
end
local function nearestTarget(p, root)
	local result, distance = nil, 300
	for body in deps.DamageService.Bodies() do
		local t = torso(body)
		if body ~= p.Character and t and not deps.DamageService.Protected(body, p) then
			local d = (t.Position - root.Position).Magnitude
			if d < distance then result, distance = body, d end
		end
	end
	return result
end
local function gunFor(p, root, rec)
	for _, m in deps.OwnershipService.HeldItems(p) do
		local k = Items.Kind(m)
		if k and Config.Guns[k] and not Config.Guns[k].projectile and not Config.Guns[k].dart then return m end
	end
	local candidate = rec.gun
	if candidate and (not candidate.Parent or deps.OwnershipService.ItemHolder(candidate)) then candidate = nil end
	if not candidate and os.clock() >= rec.nextGun then
		rec.nextGun = os.clock() + 1
		local props = workspace:FindFirstChild("Props")
		local best = 80
		for _, m in (props and props:GetChildren() or {}) do
			local k = m:IsA("Model") and Items.Kind(m)
			local bound = m:GetAttribute("BoundTo")
			if k and Config.Guns[k] and not Config.Guns[k].projectile and not Config.Guns[k].dart and m.PrimaryPart and not m.PrimaryPart.Anchored and not deps.OwnershipService.ItemHolder(m) and not m:GetAttribute("StowedBy") and (not bound or bound == p.UserId) then
				local d = (m.PrimaryPart.Position - root.Position).Magnitude
				if d < best then candidate, best = m, d end
			end
		end
		-- The directive arms an unarmed player even when the room has no loose weapon.
		if not candidate then
			candidate = deps.PropService.Place("pistol", root.CFrame * CFrame.new(0, 0, -2), p)
			if candidate then candidate:SetAttribute("BoundTo", p.UserId) end
		end
		rec.gun = candidate
	end
	if candidate and candidate.PrimaryPart then
		local pos = candidate.PrimaryPart.Position
		if (pos - root.Position).Magnitude <= 6 then
			for _, item in deps.OwnershipService.HeldItems(p) do deps.OwnershipService.DropItem(item) end
			deps.OwnershipService.Equip(p, candidate, "Right")
			if deps.OwnershipService.ItemHolder(candidate) == p then return candidate end
		end
		return nil, pos
	end
end
function Service.Init(d)
	deps = d
	local previous = deps.DamageService.OnKill
	deps.DamageService.OnKill = function(victim, killer, state)
		if previous then previous(victim, killer, state) end
		local target = Players:GetPlayerFromCharacter(victim)
		if target then
			for p, rec in directives do if rec.targetId == target.UserId then clear(p) end end
		end
	end
	Players.PlayerRemoving:Connect(clear)
	task.spawn(function()
		while true do
			task.wait(0.1)
			local now = workspace:GetServerTimeNow()
			for _, p in Players:GetPlayers() do
				local ch, rec = p.Character, directives[p]
				local root = torso(ch)
				if not rec and root and (ch:GetAttribute("CrashOut") or 0) > now then
					Service.Start(p, nil, ch:GetAttribute("CrashOut") - now, ch:GetAttribute("CrashOutSource")); rec = directives[p]
				end
				if not rec then continue end
				if now >= rec.untilT or (rec.source == "psychosis" and (p:GetAttribute("CyPsycho") or 0) <= 0) then clear(p); continue end
				local tp = rec.targetId and Players:GetPlayerByUserId(rec.targetId)
				if tp and tp.Character and tp.Character:GetAttribute("Dead") then clear(p); continue end
				if not root then continue end -- target directives resume after their carrier respawns
				ch:SetAttribute("ControlActive", true)
				if (ch:GetAttribute("TemporalFrozenUntil") or 0) > now then ch:SetAttribute("ControlMove", false); ch:SetAttribute("ControlJump", false); continue end
				local target
				if rec.targetId then target = tp and tp.Character else target = nearestTarget(p, root) end
				local tt = torso(target)
				local gun, pickup = gunFor(p, root, rec)
				local goal = pickup or (tt and tt.Position)
				local visible = false
				if tt then
					local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
					rp.FilterDescendantsInstances = { ch, gun or ch }; rp.RespectCanCollide = true
					local hit = workspace:Raycast(root.Position, tt.Position - root.Position, rp)
					visible = not hit or hit.Instance:IsDescendantOf(target)
				end
				local waypoint, moving, jump = Navigation.Step(rec.nav, root, goal, pickup and 4 or 18, pickup ~= nil or visible)
				ch:SetAttribute("ControlGoal", waypoint)
				ch:SetAttribute("ControlAim", tt and tt.Position or goal)
				ch:SetAttribute("ControlMove", moving)
				ch:SetAttribute("ControlJump", jump)
				if gun and tt and visible and os.clock() >= rec.nextShot then
					rec.nextShot = os.clock() + 0.25
					if (gun:GetAttribute("Ammo") or 0) <= 0 then deps.ItemService.Reload(p, gun)
					else
						local muzzle = Items.Muzzle(gun)
						if muzzle then
							local origin = muzzle.WorldPosition
							local delta = tt.Position - origin
							if delta.Magnitude > 0.1 then deps.GunService.Fire(p, gun, origin, { { dir = delta.Unit } }, true) end
						end
					end
				end
			end
		end
	end)
end
return Service
