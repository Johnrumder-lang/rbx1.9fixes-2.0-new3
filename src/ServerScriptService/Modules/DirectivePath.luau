--!nonstrict
-- Navigation for the custom ragdoll controller (there is no Humanoid:MoveTo).
local Pathfinding = game:GetService("PathfindingService")
local Navigation = {}
local computing = 0
local function flatDistance(a, b)
	local d = a - b
	return Vector3.new(d.X, 0, d.Z).Magnitude
end
local function disconnect(nav)
	if nav.blocked then nav.blocked:Disconnect(); nav.blocked = nil end
	if nav.path then nav.path:Destroy(); nav.path = nil end
end
function Navigation.Clear(nav)
	nav.cancelled = true
	disconnect(nav)
end
function Navigation.New()
	return { index = 1, nextPlan = 0, lastProgress = os.clock() }
end
function Navigation.Step(nav, root, destination, stopDistance, canStop)
	local now = os.clock()
	if not destination or nav.cancelled then return nil, false, false end
	local changedBody = nav.body ~= root.Parent
	if changedBody then
		disconnect(nav); nav.body = root.Parent; nav.points = nil; nav.destination = nil
		nav.lastPosition = root.Position; nav.lastProgress = now; nav.generation = (nav.generation or 0) + 1
	end
	if canStop and (destination - root.Position).Magnitude <= stopDistance then return destination, false, false end
	if not nav.lastPosition or flatDistance(root.Position, nav.lastPosition) > 1.2 then
		nav.lastPosition, nav.lastProgress = root.Position, now
	end
	local stuck = now - nav.lastProgress > 1.4
	local changedGoal = not nav.destination or (destination - nav.destination).Magnitude > 6
	local needs = changedGoal or nav.replan or stuck or not nav.points or now >= (nav.refreshAt or 0)
	if needs and not nav.busy and now >= nav.nextPlan and computing < 4 then
		nav.busy = true; computing += 1
		nav.nextPlan = now + (stuck and 0.8 or 1.2)
		nav.destination = destination; nav.refreshAt = now + 2.5; nav.replan = false
		local generation, body, origin = nav.generation, root.Parent, root.Position
		local scale = root.Size and math.clamp(root.Size.X / 2, 0.5, 4) or 1
		task.spawn(function()
			local path, points
			local ok = pcall(function()
				path = Pathfinding:CreatePath({ AgentRadius = 2 * scale, AgentHeight = 5 * scale, AgentCanJump = true, AgentCanClimb = false, WaypointSpacing = 4 })
				path:ComputeAsync(origin, destination)
				if path.Status == Enum.PathStatus.Success then points = path:GetWaypoints() end
			end)
			computing -= 1; nav.busy = false
			if nav.cancelled or nav.generation ~= generation or nav.body ~= body then if path then path:Destroy() end; return end
			disconnect(nav)
			nav.points = ok and points and #points >= 2 and points or nil
			nav.index = 2; nav.lastProgress = os.clock(); nav.lastPosition = root.Position
			if nav.points then
				nav.path = path
				nav.blocked = path.Blocked:Connect(function(index) if index >= nav.index then nav.replan = true end end)
			elseif path then path:Destroy() end
		end)
	end
	local points = nav.points
	if not points then return nil, false, false end -- no blind walking into a wall while a route is unavailable
	local waypoint = points[nav.index]
	while waypoint and flatDistance(root.Position, waypoint.Position) < 2.2 and math.abs(root.Position.Y - waypoint.Position.Y) < 5 do
		if waypoint.Action == Enum.PathWaypointAction.Jump then nav.jumpUntil = now + 0.7 end
		nav.index += 1; waypoint = points[nav.index]
	end
	if not waypoint then nav.replan = true; return nil, false, false end
	local jump = waypoint.Action == Enum.PathWaypointAction.Jump or now < (nav.jumpUntil or 0) or (stuck and not nav.replan)
	return waypoint.Position, true, jump
end
return Navigation
